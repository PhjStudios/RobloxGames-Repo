--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Operation = "new" | "publish" | "cleanup"
export type ErrorCode = "INVALID_ARGUMENT" | "INVALID_SNAPSHOT" | "UNAVAILABLE" | "INTERNAL_ERROR"

export type BroadcasterError = {
	code: ErrorCode,
	operation: Operation,
}

export type PublishKind = "Sent" | "Queued" | "Replaced" | "BudgetExhausted"

export type PublishOutcome = {
	kind: PublishKind,
}

export type RecipientRecord = {
	recipient: unknown,
	userId: number,
}

export type Clock = () -> unknown
export type TimerCallback = () -> ()
export type Schedule = (delaySeconds: number, callback: TimerCallback) -> unknown
export type Cancel = (handle: unknown) -> ()
export type Sender = (recipient: unknown, snapshot: MatchProtocol.MatchSnapshot) -> ()
export type GetRecipients = () -> unknown
export type OnFault = () -> ()

export type Dependencies = {
	clock: Clock,
	schedule: Schedule,
	cancel: Cancel,
	sender: Sender,
	getRecipients: GetRecipients,
	onFault: OnFault,
}

export type Stats = {
	batchesSent: number,
	senderCalls: number,
	senderFailures: number,
	hasPending: boolean,
	hasLiveFlush: boolean,
	faulted: boolean,
	cleaned: boolean,
}

local BroadcasterMethods = {}
BroadcasterMethods.__index = BroadcasterMethods

export type Broadcaster = typeof(setmetatable({} :: {}, BroadcasterMethods))

type BroadcasterData = {
	clock: Clock?,
	schedule: Schedule?,
	cancel: Cancel?,
	sender: Sender?,
	getRecipients: GetRecipients?,
	onFault: OnFault?,
	lastClockSample: number?,
	lastBatchTime: number?,
	latestSnapshot: MatchProtocol.MatchSnapshot?,
	flushHandle: unknown?,
	generation: number,
	batchesSent: number,
	senderCalls: number,
	senderFailures: number,
	faultNotified: boolean,
	faulted: boolean,
	cleaned: boolean,
	busy: boolean,
}

local SNAPSHOT_MIN_INTERVAL_SECONDS = 0.1
local MAX_SNAPSHOT_EVENT_BATCHES = 64
local MAX_RECIPIENTS_PER_BATCH = 4

local BROADCASTER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: BroadcasterData }

local SENT_OUTCOME: PublishOutcome = table.freeze({ kind = "Sent" })
local QUEUED_OUTCOME: PublishOutcome = table.freeze({ kind = "Queued" })
local REPLACED_OUTCOME: PublishOutcome = table.freeze({ kind = "Replaced" })
local BUDGET_EXHAUSTED_OUTCOME: PublishOutcome = table.freeze({ kind = "BudgetExhausted" })

local SnapshotBroadcaster = {
	SNAPSHOT_MIN_INTERVAL_SECONDS = SNAPSHOT_MIN_INTERVAL_SECONDS,
	MAX_SNAPSHOT_EVENT_BATCHES = MAX_SNAPSHOT_EVENT_BATCHES,
	MAX_RECIPIENTS_PER_BATCH = MAX_RECIPIENTS_PER_BATCH,
}

local function makeError(code: ErrorCode, operation: Operation): BroadcasterError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<BroadcasterError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): BroadcasterData
	if type(value) ~= "table" then
		error("[ATD_SNAPSHOT_BROADCASTER][code=INVALID_CONTEXT]", 0)
	end
	local data = BROADCASTER_DATA[value :: any]
	if data == nil then
		error("[ATD_SNAPSHOT_BROADCASTER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function notifyFault(data: BroadcasterData)
	if data.faultNotified then
		return
	end
	data.faultNotified = true
	local callback = data.onFault
	if callback ~= nil then
		pcall(callback)
	end
end

local function advanceGeneration(data: BroadcasterData): boolean
	if data.generation >= Validation.MAX_SAFE_INTEGER then
		return false
	end
	data.generation += 1
	return true
end

local function failClosed(data: BroadcasterData)
	if data.faulted or data.cleaned then
		return
	end
	data.faulted = true
	data.latestSnapshot = nil
	local _ = advanceGeneration(data)

	local handle = data.flushHandle
	data.flushHandle = nil
	local cancel = data.cancel
	if handle ~= nil and cancel ~= nil then
		pcall(cancel, handle)
	end
	notifyFault(data)
end

local function sampleClock(data: BroadcasterData): number?
	local clock = data.clock
	if clock == nil then
		return nil
	end
	local called, value = pcall(clock)
	if
		not called
		or type(value) ~= "number"
		or not Validation.isFiniteNumber(value)
		or value < 0
		or (data.lastClockSample ~= nil and value < data.lastClockSample)
	then
		return nil
	end
	data.lastClockSample = value
	return value
end

local function snapshotHasUserId(snapshot: MatchProtocol.MatchSnapshot, userId: number): boolean
	for _, participant in snapshot.participants do
		if participant.userId == userId then
			return true
		end
	end
	return false
end

local function readRecipients(value: unknown, snapshot: MatchProtocol.MatchSnapshot): { RecipientRecord }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end

	local rawRecipients = value :: { [any]: unknown }
	local count = 0
	local maximumIndex = 0
	for rawKey in next, rawRecipients do
		count += 1
		if
			count > MAX_RECIPIENTS_PER_BATCH
			or type(rawKey) ~= "number"
			or not Validation.isSafeInteger(rawKey)
			or rawKey < 1
		then
			return nil
		end
		maximumIndex = math.max(maximumIndex, rawKey)
	end
	if maximumIndex ~= count then
		return nil
	end

	local recipients: { RecipientRecord } = table.create(count)
	for index = 1, count do
		local rawRecord = rawget(rawRecipients, index)
		if type(rawRecord) ~= "table" or getmetatable(rawRecord :: any) ~= nil then
			return nil
		end

		local recordFieldCount = 0
		for rawField in next, rawRecord :: any do
			recordFieldCount += 1
			if
				recordFieldCount > 2
				or type(rawField) ~= "string"
				or (rawField ~= "recipient" and rawField ~= "userId")
			then
				return nil
			end
		end
		if recordFieldCount ~= 2 then
			return nil
		end

		local recipient = rawget(rawRecord :: any, "recipient")
		local userId = rawget(rawRecord :: any, "userId")
		if
			recipient == nil
			or type(userId) ~= "number"
			or not Validation.isSafeInteger(userId)
			or userId == 0
			or not snapshotHasUserId(snapshot, userId)
		then
			return nil
		end

		for previousIndex = 1, index - 1 do
			local previous = recipients[previousIndex]
			if previous.userId == userId or previous.recipient == recipient then
				return nil
			end
		end

		recipients[index] = {
			recipient = recipient,
			userId = userId,
		}
	end

	table.sort(recipients, function(left: RecipientRecord, right: RecipientRecord): boolean
		return left.userId < right.userId
	end)
	return recipients
end

local function deliver(data: BroadcasterData, snapshot: MatchProtocol.MatchSnapshot, now: number): boolean
	if data.cleaned or data.faulted or data.batchesSent >= MAX_SNAPSHOT_EVENT_BATCHES then
		return false
	end

	local getRecipients = data.getRecipients
	if getRecipients == nil then
		failClosed(data)
		return false
	end
	local called, recipientsValue = pcall(getRecipients)
	if not called or data.cleaned or data.faulted then
		if not data.cleaned and not data.faulted then
			failClosed(data)
		end
		return false
	end
	local recipients = readRecipients(recipientsValue, snapshot)
	if recipients == nil then
		failClosed(data)
		return false
	end

	data.batchesSent += 1
	data.lastBatchTime = now
	local sender = data.sender
	if sender == nil then
		failClosed(data)
		return false
	end
	for _, record in recipients do
		if data.cleaned or data.faulted then
			break
		end
		data.senderCalls += 1
		local sent = pcall(sender, record.recipient, snapshot)
		if not sent then
			data.senderFailures += 1
		end
	end
	return not data.cleaned and not data.faulted
end

local function cancelPending(data: BroadcasterData): boolean
	local handle = data.flushHandle
	data.flushHandle = nil
	data.latestSnapshot = nil
	if not advanceGeneration(data) then
		return false
	end
	if handle == nil then
		return true
	end
	local cancel = data.cancel
	if cancel == nil then
		return false
	end
	local cancelled = pcall(cancel, handle)
	return cancelled
end

local processFlush: (BroadcasterData, number) -> ()

local function armFlush(data: BroadcasterData, delaySeconds: number): boolean
	if
		data.cleaned
		or data.faulted
		or data.latestSnapshot == nil
		or data.flushHandle ~= nil
		or not Validation.isFiniteNumber(delaySeconds)
		or delaySeconds <= 0
		or delaySeconds > SNAPSHOT_MIN_INTERVAL_SECONDS
		or not advanceGeneration(data)
	then
		return false
	end

	local generation = data.generation
	local capturedHandle: unknown? = nil
	local armed = false
	local firedBeforeArmed = false
	local callback = function()
		if not armed then
			firedBeforeArmed = true
			return
		end
		if data.cleaned or data.faulted or generation ~= data.generation or data.flushHandle ~= capturedHandle then
			return
		end
		data.flushHandle = nil
		processFlush(data, generation)
	end

	local schedule = data.schedule
	local cancel = data.cancel
	if schedule == nil or cancel == nil then
		return false
	end
	local scheduled, handle = pcall(schedule, delaySeconds, callback)
	if not scheduled or handle == nil then
		return false
	end
	capturedHandle = handle
	if firedBeforeArmed then
		pcall(cancel, handle)
		return false
	end
	if data.cleaned or data.faulted or generation ~= data.generation then
		pcall(cancel, handle)
		return false
	end

	data.flushHandle = handle
	armed = true
	return true
end

processFlush = function(data: BroadcasterData, generation: number)
	if data.cleaned or data.faulted or data.busy or generation ~= data.generation or data.latestSnapshot == nil then
		return
	end
	data.busy = true

	local now = sampleClock(data)
	local lastBatchTime = data.lastBatchTime
	if now == nil or lastBatchTime == nil then
		failClosed(data)
		data.busy = false
		return
	end
	local elapsed = now - lastBatchTime
	if elapsed < SNAPSHOT_MIN_INTERVAL_SECONDS then
		local remaining = SNAPSHOT_MIN_INTERVAL_SECONDS - elapsed
		if not armFlush(data, remaining) then
			failClosed(data)
		end
		data.busy = false
		return
	end

	local pending = data.latestSnapshot :: MatchProtocol.MatchSnapshot
	data.latestSnapshot = nil
	if data.batchesSent < MAX_SNAPSHOT_EVENT_BATCHES then
		deliver(data, pending, now)
	end
	data.busy = false
end

function BroadcasterMethods.publish(
	self: Broadcaster,
	snapshotValue: unknown
): Result.Result<PublishOutcome, BroadcasterError>
	local data = requireData(self)
	if data.cleaned or data.faulted or data.busy then
		return failure("UNAVAILABLE", "publish")
	end

	local snapshotResult = MatchProtocol.validateMatchSnapshot(snapshotValue)
	if not snapshotResult.ok then
		return failure("INVALID_SNAPSHOT", "publish")
	end
	if data.batchesSent >= MAX_SNAPSHOT_EVENT_BATCHES then
		return Result.ok(BUDGET_EXHAUSTED_OUTCOME)
	end
	data.busy = true

	local now = sampleClock(data)
	if now == nil then
		failClosed(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "publish")
	end
	local canonicalSnapshot = snapshotResult.value
	local lastBatchTime = data.lastBatchTime
	if lastBatchTime == nil or now - lastBatchTime >= SNAPSHOT_MIN_INTERVAL_SECONDS then
		if data.flushHandle ~= nil and not cancelPending(data) then
			failClosed(data)
			data.busy = false
			return failure("INTERNAL_ERROR", "publish")
		end
		if not deliver(data, canonicalSnapshot, now) then
			data.busy = false
			return failure("INTERNAL_ERROR", "publish")
		end
		data.busy = false
		return Result.ok(SENT_OUTCOME)
	end

	local replaced = data.latestSnapshot ~= nil
	data.latestSnapshot = canonicalSnapshot
	if data.flushHandle == nil then
		local remaining = SNAPSHOT_MIN_INTERVAL_SECONDS - (now - lastBatchTime)
		if not armFlush(data, remaining) then
			failClosed(data)
			data.busy = false
			return failure("INTERNAL_ERROR", "publish")
		end
	end
	data.busy = false
	return Result.ok(if replaced then REPLACED_OUTCOME else QUEUED_OUTCOME)
end

function BroadcasterMethods.getStats(self: Broadcaster): Stats
	local data = requireData(self)
	return table.freeze({
		batchesSent = data.batchesSent,
		senderCalls = data.senderCalls,
		senderFailures = data.senderFailures,
		hasPending = data.latestSnapshot ~= nil,
		hasLiveFlush = data.flushHandle ~= nil,
		faulted = data.faulted,
		cleaned = data.cleaned,
	})
end

function BroadcasterMethods.cleanup(self: Broadcaster): Result.Result<boolean, BroadcasterError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	data.cleaned = true
	data.latestSnapshot = nil
	local generationAdvanced = advanceGeneration(data)
	local handle = data.flushHandle
	data.flushHandle = nil
	local cancel = data.cancel
	local cancelled = true
	if handle ~= nil then
		cancelled = cancel ~= nil and pcall(cancel, handle)
	end
	if not generationAdvanced or not cancelled then
		notifyFault(data)
	end

	data.clock = nil
	data.schedule = nil
	data.cancel = nil
	data.sender = nil
	data.getRecipients = nil
	data.onFault = nil
	data.lastClockSample = nil
	data.lastBatchTime = nil
	data.batchesSent = 0
	data.senderCalls = 0
	data.senderFailures = 0
	data.busy = false
	if not generationAdvanced or not cancelled then
		return failure("INTERNAL_ERROR", "cleanup")
	end
	return Result.ok(true)
end

function SnapshotBroadcaster.new(dependenciesValue: unknown): Result.Result<Broadcaster, BroadcasterError>
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return failure("INVALID_ARGUMENT", "new")
	end
	local allowedFields = table.freeze({
		clock = true,
		schedule = true,
		cancel = true,
		sender = true,
		getRecipients = true,
		onFault = true,
	})
	local fieldCount = 0
	for fieldName in next, dependenciesValue :: any do
		fieldCount += 1
		if type(fieldName) ~= "string" or allowedFields[fieldName] ~= true then
			return failure("INVALID_ARGUMENT", "new")
		end
	end
	if fieldCount ~= 6 then
		return failure("INVALID_ARGUMENT", "new")
	end

	local dependencies = dependenciesValue :: any
	if
		type(dependencies.clock) ~= "function"
		or type(dependencies.schedule) ~= "function"
		or type(dependencies.cancel) ~= "function"
		or type(dependencies.sender) ~= "function"
		or type(dependencies.getRecipients) ~= "function"
		or type(dependencies.onFault) ~= "function"
	then
		return failure("INVALID_ARGUMENT", "new")
	end

	local broadcaster = setmetatable({}, BroadcasterMethods) :: Broadcaster
	table.freeze(broadcaster)
	BROADCASTER_DATA[broadcaster] = {
		clock = dependencies.clock :: Clock,
		schedule = dependencies.schedule :: Schedule,
		cancel = dependencies.cancel :: Cancel,
		sender = dependencies.sender :: Sender,
		getRecipients = dependencies.getRecipients :: GetRecipients,
		onFault = dependencies.onFault :: OnFault,
		lastClockSample = nil,
		lastBatchTime = nil,
		latestSnapshot = nil,
		flushHandle = nil,
		generation = 0,
		batchesSent = 0,
		senderCalls = 0,
		senderFailures = 0,
		faultNotified = false,
		faulted = false,
		cleaned = false,
		busy = false,
	}
	return Result.ok(broadcaster)
end

table.freeze(BroadcasterMethods)
return table.freeze(SnapshotBroadcaster)
