--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Operation =
	"new"
	| "preflightPublication"
	| "queueState"
	| "queueDamage"
	| "flush"
	| "publishState"
	| "getMetrics"
	| "cleanup"

export type ErrorCode =
	"INVALID_ARGUMENT"
	| "INVALID_SNAPSHOT"
	| "INVALID_DAMAGE"
	| "WRONG_IDENTITY"
	| "CAPACITY_EXCEEDED"
	| "REENTRANT"
	| "FAULTED"
	| "CLEANED"
	| "INTERNAL_ERROR"

export type PublisherError = {
	code: ErrorCode,
	operation: Operation,
}

export type RecipientRecord = {
	recipient: Player,
	userId: number,
}

export type Sender = (recipient: Player, message: BaseProtocol.BaseReplicationMessage) -> boolean
export type GetRecipients = () -> unknown

export type Dependencies = {
	sender: Sender,
	getRecipients: GetRecipients,
}

export type FlushOutcome = {
	published: boolean,
	kind: BaseProtocol.BaseReplicationKind?,
	recipientCount: number,
	senderFailureCount: number,
}

export type Metrics = {
	publicationCount: number,
	flushCount: number,
	stateQueueCount: number,
	damageQueueCount: number,
	coalescedDamageCount: number,
	senderCallCount: number,
	senderFailureCount: number,
	hasPending: boolean,
	pendingKind: BaseProtocol.BaseReplicationKind?,
	latestBaseRevision: number?,
	retainsSender: boolean,
	retainsRecipientProvider: boolean,
	retainsTestRecipientValidator: boolean,
	faulted: boolean,
	cleaned: boolean,
}

type TestRecipientValidator = (recipient: unknown, userId: number) -> boolean

type TestOptions = {
	maxPublications: number?,
	recipientValidator: TestRecipientValidator?,
}

type InternalRecipientRecord = {
	recipient: unknown,
	userId: number,
}

type PublisherData = {
	matchId: Ids.MatchId?,
	enemyEpoch: number,
	sender: ((unknown, BaseProtocol.BaseReplicationMessage) -> boolean)?,
	getRecipients: GetRecipients?,
	testRecipientValidator: TestRecipientValidator?,
	maxPublications: number,
	pending: BaseProtocol.BaseReplicationMessage?,
	latestSnapshot: BaseProtocol.BaseSnapshot?,
	publicationCount: number,
	flushCount: number,
	stateQueueCount: number,
	damageQueueCount: number,
	coalescedDamageCount: number,
	senderCallCount: number,
	senderFailureCount: number,
	lowHealthCrossingSeen: boolean,
	busy: boolean,
	cleanupRequested: boolean,
	faulted: boolean,
	cleaned: boolean,
}

local PublisherMethods = {}
PublisherMethods.__index = PublisherMethods

export type Publisher = typeof(setmetatable({} :: {}, PublisherMethods))
export type TestConstructor = (
	matchId: unknown,
	enemyEpoch: unknown,
	dependencies: unknown,
	options: TestOptions?
) -> Result.Result<Publisher, PublisherError>

local DEPENDENCY_FIELDS: { [string]: boolean } = table.freeze({
	sender = true,
	getRecipients = true,
})

local RECIPIENT_FIELDS: { [string]: boolean } = table.freeze({
	recipient = true,
	userId = true,
})

local TEST_OPTION_FIELDS: { [string]: boolean } = table.freeze({
	maxPublications = true,
	recipientValidator = true,
})

local PUBLISHER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: PublisherData }

local BaseReplicationPublisher = {
	MAX_BROADCAST_RECIPIENTS = BaseProtocol.MAX_BROADCAST_RECIPIENTS,
	MAX_LEAKS_PER_MESSAGE = BaseProtocol.MAX_LEAKS_PER_MESSAGE,
	MAX_LIFETIME_PUBLICATIONS = BaseProtocol.MAX_LIFETIME_PUBLICATIONS,
	newForTests = nil :: TestConstructor?,
}

local function makeError(code: ErrorCode, operation: Operation): PublisherError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<PublisherError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): PublisherData
	if type(value) ~= "table" then
		error("[ATD_BASE_REPLICATION_PUBLISHER][code=INVALID_CONTEXT]", 0)
	end
	local data = PUBLISHER_DATA[value :: any]
	if data == nil then
		error("[ATD_BASE_REPLICATION_PUBLISHER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function hasExactFields(value: { [any]: unknown }, fields: { [string]: boolean }): boolean
	local actualCount = 0
	for fieldName in next, value do
		actualCount += 1
		if type(fieldName) ~= "string" or fields[fieldName] ~= true then
			return false
		end
	end
	local expectedCount = 0
	for _ in fields do
		expectedCount += 1
	end
	return actualCount == expectedCount
end

local function isSafePositiveInteger(value: unknown, maximum: number): boolean
	return type(value) == "number"
		and Validation.isSafeInteger(value :: number)
		and (value :: number) >= 1
		and (value :: number) <= maximum
end

local function isUserId(value: unknown): boolean
	return type(value) == "number" and value ~= 0 and Validation.isSafeInteger(value :: number)
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, any)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function validateLive(data: PublisherData, operation: Operation): PublisherError?
	if data.cleaned then
		return makeError("CLEANED", operation)
	end
	if data.busy then
		return makeError("REENTRANT", operation)
	end
	if data.faulted then
		return makeError("FAULTED", operation)
	end
	return nil
end

local function snapshotsEqual(left: BaseProtocol.BaseSnapshot, right: BaseProtocol.BaseSnapshot): boolean
	return left.matchId == right.matchId
		and left.enemyEpoch == right.enemyEpoch
		and left.mapId == right.mapId
		and left.difficultyId == right.difficultyId
		and left.basePosition == right.basePosition
		and left.baseRevision == right.baseRevision
		and left.status == right.status
		and left.currentHealth == right.currentHealth
		and left.maximumHealth == right.maximumHealth
		and left.lowHealth == right.lowHealth
		and left.initializedServerTime == right.initializedServerTime
		and left.updatedServerTime == right.updatedServerTime
end

local function isLegalStatusSuccessor(previous: BaseProtocol.BaseStatus, current: BaseProtocol.BaseStatus): boolean
	if previous == "Active" then
		return current == "Active" or current == "Defeated" or current == "Faulted"
	end
	return current == previous
end

local function validateSnapshotOrder(
	data: PublisherData,
	snapshot: BaseProtocol.BaseSnapshot,
	operation: Operation
): PublisherError?
	if snapshot.matchId ~= data.matchId or snapshot.enemyEpoch ~= data.enemyEpoch then
		return makeError("WRONG_IDENTITY", operation)
	end
	local previous = data.latestSnapshot
	if previous == nil then
		return nil
	end
	if snapshot.baseRevision < previous.baseRevision then
		return makeError("INVALID_SNAPSHOT", operation)
	end
	if snapshot.baseRevision == previous.baseRevision then
		if not snapshotsEqual(previous, snapshot) then
			return makeError("INVALID_SNAPSHOT", operation)
		end
		return nil
	end
	if
		snapshot.mapId ~= previous.mapId
		or snapshot.difficultyId ~= previous.difficultyId
		or snapshot.basePosition ~= previous.basePosition
		or snapshot.maximumHealth ~= previous.maximumHealth
		or snapshot.initializedServerTime ~= previous.initializedServerTime
		or snapshot.updatedServerTime < previous.updatedServerTime
		or snapshot.currentHealth > previous.currentHealth
		or (previous.lowHealth and not snapshot.lowHealth)
		or not isLegalStatusSuccessor(previous.status, snapshot.status)
	then
		return makeError("INVALID_SNAPSHOT", operation)
	end
	return nil
end

local function canonicalStateMessage(snapshot: BaseProtocol.BaseSnapshot): BaseProtocol.BaseStateMessage?
	local result = BaseProtocol.validateBaseReplicationMessage({
		kind = BaseProtocol.STATE_KIND,
		snapshot = snapshot,
	})
	if not result.ok or result.value.kind ~= BaseProtocol.STATE_KIND then
		return nil
	end
	return result.value :: BaseProtocol.BaseStateMessage
end

local function canonicalDamageMessage(
	snapshot: BaseProtocol.BaseSnapshot,
	appliedDamage: number,
	leakCount: number,
	lowHealthCrossed: boolean
): BaseProtocol.BaseDamageMessage?
	local result = BaseProtocol.validateBaseReplicationMessage({
		kind = BaseProtocol.DAMAGE_KIND,
		snapshot = snapshot,
		appliedDamage = appliedDamage,
		leakCount = leakCount,
		lowHealthCrossed = lowHealthCrossed,
	})
	if not result.ok or result.value.kind ~= BaseProtocol.DAMAGE_KIND then
		return nil
	end
	return result.value :: BaseProtocol.BaseDamageMessage
end

local function preflightInternal(data: PublisherData, operation: Operation): PublisherError?
	if data.publicationCount >= data.maxPublications then
		return makeError("CAPACITY_EXCEEDED", operation)
	end
	return nil
end

local function queueStateInternal(
	data: PublisherData,
	snapshotValue: unknown,
	operation: Operation
): Result.Result<boolean, PublisherError>
	local snapshotResult = BaseProtocol.validateBaseSnapshot(snapshotValue)
	if not snapshotResult.ok then
		return failure("INVALID_SNAPSHOT", operation)
	end
	local snapshot = snapshotResult.value
	local orderError = validateSnapshotOrder(data, snapshot, operation)
	if orderError ~= nil then
		return Result.err(orderError)
	end
	local previous = data.latestSnapshot
	if previous ~= nil and snapshot.baseRevision == previous.baseRevision then
		return Result.ok(false)
	end
	local capacityError = preflightInternal(data, operation)
	if capacityError ~= nil then
		return Result.err(capacityError)
	end

	local pending = data.pending
	if pending ~= nil and pending.kind == BaseProtocol.DAMAGE_KIND and snapshot.status ~= "Faulted" then
		local damage = pending :: BaseProtocol.BaseDamageMessage
		local updated =
			canonicalDamageMessage(snapshot, damage.appliedDamage, damage.leakCount, damage.lowHealthCrossed)
		if updated == nil then
			return failure("INVALID_SNAPSHOT", operation)
		end
		data.pending = updated
	else
		local state = canonicalStateMessage(snapshot)
		if state == nil then
			return failure("INVALID_SNAPSHOT", operation)
		end
		data.pending = state
	end
	data.latestSnapshot = snapshot
	data.stateQueueCount += 1
	return Result.ok(true)
end

local function queueDamageInternal(
	data: PublisherData,
	snapshotValue: unknown,
	appliedDamageValue: unknown,
	leakCountValue: unknown,
	lowHealthCrossedValue: unknown,
	operation: Operation
): Result.Result<boolean, PublisherError>
	local snapshotResult = BaseProtocol.validateBaseSnapshot(snapshotValue)
	if not snapshotResult.ok then
		return failure("INVALID_SNAPSHOT", operation)
	end
	if
		not isSafePositiveInteger(appliedDamageValue, Validation.MAX_SAFE_INTEGER)
		or not isSafePositiveInteger(leakCountValue, BaseProtocol.MAX_LEAKS_PER_MESSAGE)
		or type(lowHealthCrossedValue) ~= "boolean"
	then
		return failure("INVALID_DAMAGE", operation)
	end
	local snapshot = snapshotResult.value
	local orderError = validateSnapshotOrder(data, snapshot, operation)
	if orderError ~= nil then
		return Result.err(orderError)
	end
	local previous = data.latestSnapshot
	if
		previous == nil
		or snapshot.baseRevision <= previous.baseRevision
		or previous.currentHealth - snapshot.currentHealth ~= appliedDamageValue
		or ((not previous.lowHealth and snapshot.lowHealth) ~= lowHealthCrossedValue)
		or (lowHealthCrossedValue and data.lowHealthCrossingSeen)
	then
		return failure("INVALID_DAMAGE", operation)
	end
	local capacityError = preflightInternal(data, operation)
	if capacityError ~= nil then
		return Result.err(capacityError)
	end

	local appliedDamage = appliedDamageValue :: number
	local leakCount = leakCountValue :: number
	local lowHealthCrossed = lowHealthCrossedValue :: boolean
	local pending = data.pending
	if pending ~= nil and pending.kind == BaseProtocol.DAMAGE_KIND then
		local damage = pending :: BaseProtocol.BaseDamageMessage
		if appliedDamage > Validation.MAX_SAFE_INTEGER - damage.appliedDamage then
			return failure("INVALID_DAMAGE", operation)
		end
		if leakCount > BaseProtocol.MAX_LEAKS_PER_MESSAGE - damage.leakCount then
			return failure("INVALID_DAMAGE", operation)
		end
		appliedDamage += damage.appliedDamage
		leakCount += damage.leakCount
		lowHealthCrossed = lowHealthCrossed or damage.lowHealthCrossed
	end
	local message = canonicalDamageMessage(snapshot, appliedDamage, leakCount, lowHealthCrossed)
	if message == nil then
		return failure("INVALID_DAMAGE", operation)
	end
	if pending ~= nil and pending.kind == BaseProtocol.DAMAGE_KIND then
		data.coalescedDamageCount += 1
	end
	data.pending = message
	data.latestSnapshot = snapshot
	data.damageQueueCount += 1
	if lowHealthCrossed then
		data.lowHealthCrossingSeen = true
	end
	return Result.ok(true)
end

local function productionRecipientIsLive(recipient: unknown, userId: number): boolean
	if typeof(recipient) ~= "Instance" or not (recipient :: Instance):IsA("Player") then
		return false
	end
	local player = recipient :: Player
	return player.Parent == Players and player.UserId == userId
end

local function recipientIsLive(data: PublisherData, recipient: unknown, userId: number): boolean
	local validator = data.testRecipientValidator
	if validator == nil then
		return productionRecipientIsLive(recipient, userId)
	end
	local called, accepted = callNonYielding(validator, recipient, userId)
	return called and accepted == true
end

local function readRecipients(data: PublisherData): { InternalRecipientRecord }?
	local provider = data.getRecipients
	if provider == nil then
		return nil
	end
	local called, value = callNonYielding(provider)
	if not called or type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local length = #value
	if length > BaseProtocol.MAX_BROADCAST_RECIPIENTS then
		return nil
	end
	local keyCount = 0
	for key in next, value :: any do
		keyCount += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return nil
		end
	end
	if keyCount ~= length then
		return nil
	end

	local recipients: { InternalRecipientRecord } = table.create(length)
	for index = 1, length do
		local record = rawget(value :: any, index)
		if
			type(record) ~= "table"
			or getmetatable(record) ~= nil
			or not hasExactFields(record, RECIPIENT_FIELDS)
			or not isUserId(record.userId)
			or not recipientIsLive(data, record.recipient, record.userId)
		then
			return nil
		end
		for previousIndex = 1, index - 1 do
			local previous = recipients[previousIndex]
			if previous.recipient == record.recipient or previous.userId == record.userId then
				return nil
			end
		end
		recipients[index] = {
			recipient = record.recipient,
			userId = record.userId,
		}
	end
	table.sort(recipients, function(left: InternalRecipientRecord, right: InternalRecipientRecord): boolean
		return left.userId < right.userId
	end)
	return recipients
end

local function failClosed(data: PublisherData)
	data.faulted = true
	data.pending = nil
end

local function flushInternal(data: PublisherData, operation: Operation): Result.Result<FlushOutcome, PublisherError>
	local pending = data.pending
	if pending == nil then
		return Result.ok(table.freeze({
			published = false,
			kind = nil,
			recipientCount = 0,
			senderFailureCount = 0,
		}))
	end
	local capacityError = preflightInternal(data, operation)
	if capacityError ~= nil then
		return Result.err(capacityError)
	end
	local wireResult = BaseProtocol.validateBaseReplicationMessage(pending)
	if not wireResult.ok then
		failClosed(data)
		return failure("INTERNAL_ERROR", operation)
	end
	local recipients = readRecipients(data)
	if recipients == nil then
		failClosed(data)
		return failure("INTERNAL_ERROR", operation)
	end
	local sender = data.sender
	if sender == nil then
		failClosed(data)
		table.clear(recipients)
		return failure("INTERNAL_ERROR", operation)
	end

	local message = wireResult.value
	data.pending = nil
	data.publicationCount += 1
	data.flushCount += 1
	local failureStart = data.senderFailureCount
	local recipientCount = #recipients
	for _, record in recipients do
		if data.cleanupRequested then
			break
		end
		data.senderCallCount += 1
		local called, sent = callNonYielding(sender, record.recipient, message)
		if not called or sent ~= true then
			data.senderFailureCount += 1
		end
	end
	table.clear(recipients)
	if data.cleanupRequested then
		return failure("CLEANED", operation)
	end
	return Result.ok(table.freeze({
		published = true,
		kind = message.kind,
		recipientCount = recipientCount,
		senderFailureCount = data.senderFailureCount - failureStart,
	}))
end

local function clearData(data: PublisherData)
	data.matchId = nil
	data.sender = nil
	data.getRecipients = nil
	data.testRecipientValidator = nil
	data.pending = nil
	data.latestSnapshot = nil
	data.publicationCount = 0
	data.flushCount = 0
	data.stateQueueCount = 0
	data.damageQueueCount = 0
	data.coalescedDamageCount = 0
	data.senderCallCount = 0
	data.senderFailureCount = 0
	data.lowHealthCrossingSeen = false
	data.busy = false
	data.cleanupRequested = false
	data.faulted = false
	data.cleaned = true
end

local function finishMutation(data: PublisherData)
	data.busy = false
	if data.cleanupRequested then
		clearData(data)
	end
end

function PublisherMethods.preflightPublication(self: Publisher): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "preflightPublication")
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local capacityError = preflightInternal(data, "preflightPublication")
	if capacityError ~= nil then
		return Result.err(capacityError)
	end
	return Result.ok(true)
end

function PublisherMethods.queueState(self: Publisher, snapshotValue: unknown): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "queueState")
	if liveError ~= nil then
		return Result.err(liveError)
	end
	data.busy = true
	local outcome = queueStateInternal(data, snapshotValue, "queueState")
	finishMutation(data)
	return outcome
end

function PublisherMethods.queueDamage(
	self: Publisher,
	snapshotValue: unknown,
	appliedDamageValue: unknown,
	leakCountValue: unknown,
	lowHealthCrossedValue: unknown
): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "queueDamage")
	if liveError ~= nil then
		return Result.err(liveError)
	end
	data.busy = true
	local outcome = queueDamageInternal(
		data,
		snapshotValue,
		appliedDamageValue,
		leakCountValue,
		lowHealthCrossedValue,
		"queueDamage"
	)
	finishMutation(data)
	return outcome
end

function PublisherMethods.flush(self: Publisher): Result.Result<FlushOutcome, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "flush")
	if liveError ~= nil then
		return Result.err(liveError)
	end
	data.busy = true
	local outcome = flushInternal(data, "flush")
	finishMutation(data)
	return outcome
end

function PublisherMethods.publishState(
	self: Publisher,
	snapshotValue: unknown
): Result.Result<FlushOutcome, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "publishState")
	if liveError ~= nil then
		return Result.err(liveError)
	end
	data.busy = true
	local queued = queueStateInternal(data, snapshotValue, "publishState")
	local outcome: Result.Result<FlushOutcome, PublisherError>
	if not queued.ok then
		outcome = Result.err(queued.error)
	else
		outcome = flushInternal(data, "publishState")
	end
	finishMutation(data)
	return outcome
end

function PublisherMethods.getMetrics(self: Publisher): Metrics
	local data = requireData(self)
	local pending = data.pending
	local latest = data.latestSnapshot
	return table.freeze({
		publicationCount = data.publicationCount,
		flushCount = data.flushCount,
		stateQueueCount = data.stateQueueCount,
		damageQueueCount = data.damageQueueCount,
		coalescedDamageCount = data.coalescedDamageCount,
		senderCallCount = data.senderCallCount,
		senderFailureCount = data.senderFailureCount,
		hasPending = pending ~= nil,
		pendingKind = if pending == nil then nil else pending.kind,
		latestBaseRevision = if latest == nil then nil else latest.baseRevision,
		retainsSender = data.sender ~= nil,
		retainsRecipientProvider = data.getRecipients ~= nil,
		retainsTestRecipientValidator = data.testRecipientValidator ~= nil,
		faulted = data.faulted,
		cleaned = data.cleaned,
	})
end

function PublisherMethods.cleanup(self: Publisher): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	if data.busy then
		data.cleanupRequested = true
		return Result.ok(false)
	end
	clearData(data)
	return Result.ok(true)
end

local function validateTestOptions(optionsValue: TestOptions?): (number?, TestRecipientValidator?, boolean)
	if optionsValue == nil then
		return BaseProtocol.MAX_LIFETIME_PUBLICATIONS, nil, true
	end
	if
		type(optionsValue) ~= "table"
		or getmetatable(optionsValue :: any) ~= nil
		or not hasExactFields(optionsValue :: { [any]: unknown }, TEST_OPTION_FIELDS)
	then
		return nil, nil, false
	end
	local maxPublications = optionsValue.maxPublications
	if maxPublications == nil then
		maxPublications = BaseProtocol.MAX_LIFETIME_PUBLICATIONS
	end
	if not isSafePositiveInteger(maxPublications, BaseProtocol.MAX_LIFETIME_PUBLICATIONS) then
		return nil, nil, false
	end
	local recipientValidator = optionsValue.recipientValidator
	if recipientValidator ~= nil and type(recipientValidator) ~= "function" then
		return nil, nil, false
	end
	return maxPublications :: number, recipientValidator, true
end

local function construct(
	matchIdValue: unknown,
	enemyEpochValue: unknown,
	dependenciesValue: unknown,
	testOptions: TestOptions?
): Result.Result<Publisher, PublisherError>
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if not matchIdResult.ok or not isSafePositiveInteger(enemyEpochValue, BaseProtocol.MAX_ENEMY_EPOCH) then
		return failure("INVALID_ARGUMENT", "new")
	end
	if
		type(dependenciesValue) ~= "table"
		or getmetatable(dependenciesValue :: any) ~= nil
		or not hasExactFields(dependenciesValue :: { [any]: unknown }, DEPENDENCY_FIELDS)
	then
		return failure("INVALID_ARGUMENT", "new")
	end
	local dependencies = dependenciesValue :: any
	if type(dependencies.sender) ~= "function" or type(dependencies.getRecipients) ~= "function" then
		return failure("INVALID_ARGUMENT", "new")
	end
	local maxPublications, recipientValidator, validOptions = validateTestOptions(testOptions)
	if not validOptions or maxPublications == nil then
		return failure("INVALID_ARGUMENT", "new")
	end

	local publisher = setmetatable({}, PublisherMethods) :: Publisher
	table.freeze(publisher)
	PUBLISHER_DATA[publisher] = {
		matchId = matchIdResult.value,
		enemyEpoch = enemyEpochValue :: number,
		sender = dependencies.sender,
		getRecipients = dependencies.getRecipients,
		testRecipientValidator = recipientValidator,
		maxPublications = maxPublications,
		pending = nil,
		latestSnapshot = nil,
		publicationCount = 0,
		flushCount = 0,
		stateQueueCount = 0,
		damageQueueCount = 0,
		coalescedDamageCount = 0,
		senderCallCount = 0,
		senderFailureCount = 0,
		lowHealthCrossingSeen = false,
		busy = false,
		cleanupRequested = false,
		faulted = false,
		cleaned = false,
	}
	return Result.ok(publisher)
end

function BaseReplicationPublisher.new(
	matchId: unknown,
	enemyEpoch: unknown,
	dependencies: unknown
): Result.Result<Publisher, PublisherError>
	return construct(matchId, enemyEpoch, dependencies, nil)
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "BaseReplicationPublisher" then
		return false
	end
	local productionServerBase = script.Parent
	if
		productionServerBase == nil
		or not productionServerBase:IsA("Folder")
		or productionServerBase.Name ~= "ProductionServerBase"
	then
		return false
	end
	local automatedTests = productionServerBase.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	return automatedTests.Parent == ServerStorage and ServerScriptService:FindFirstChild("Server") == nil
end

if testModuleIdentityIsExact() then
	BaseReplicationPublisher.newForTests = function(
		matchId: unknown,
		enemyEpoch: unknown,
		dependencies: unknown,
		options: TestOptions?
	): Result.Result<Publisher, PublisherError>
		return construct(matchId, enemyEpoch, dependencies, options)
	end
end

table.freeze(PublisherMethods)
return table.freeze(BaseReplicationPublisher)
