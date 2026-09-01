--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local MatchTicketContract = require(script.Parent.MatchTicketContract)

export type Adapter = {
	getAsync: (self: Adapter, key: string) -> unknown,
	updateAsync: (self: Adapter, key: string, expirationSeconds: number, transform: (unknown) -> unknown) -> unknown,
	removeAsync: (self: Adapter, key: string) -> unknown,
}

export type ErrorCode =
	"INVALID_ARGUMENT"
	| "NOT_FOUND"
	| "EXPIRED"
	| "CONFLICT"
	| "DESTINATION_CONFLICT"
	| "UNEXPECTED_MEMBER"
	| "INVALID_STATE"
	| "RETRY_EXHAUSTED"
	| "STORE_UNAVAILABLE"
	| "CORRUPT_RECORD"

export type Operation =
	"create"
	| "get"
	| "markTeleporting"
	| "claimDestination"
	| "markAdmission"
	| "recordRetry"
	| "markTerminal"
export type StoreError = { code: ErrorCode, operation: Operation }
export type MutationOutcome = { ticket: MatchTicketContract.Ticket, applied: boolean }

export type Dependencies = { clock: (() -> unknown)? }

type StoreData = {
	adapter: Adapter,
	clock: () -> unknown,
	mutationCount: number,
	readCount: number,
}

local Methods = {}
Methods.__index = Methods

export type Store = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: StoreData }
local MAX_INTERNAL_KEY_BYTES = 128

local TravelRecordStore = {}

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<StoreError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): StoreData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_TRAVEL_RECORD_STORE][code=INVALID_CONTEXT]", 0)
	end
	return data :: StoreData
end

local function now(data: StoreData): number?
	local called, value = pcall(data.clock)
	return if called
			and type(value) == "number"
			and Validation.isSafeInteger(value :: number)
			and value >= 0
		then value :: number
		else nil
end

local function ticketKey(ticketId: string): string?
	local key = `ticket/{ticketId}`
	return if #key <= MAX_INTERNAL_KEY_BYTES then key else nil
end

local function checkedTicketId(value: unknown): string?
	local result = TravelProtocol.validateOpaqueId(value, "ticket")
	return if result.ok then result.value else nil
end

local function expiration(ticket: MatchTicketContract.Ticket, currentTime: number): number
	return math.max(1, ticket.expiresAt - currentTime)
end

function Methods.create(self: Store, ticketValue: unknown): Result.Result<MutationOutcome, StoreError>
	local data = requireData(self)
	local ticketResult = MatchTicketContract.validate(ticketValue)
	local currentTime = now(data)
	if
		not ticketResult.ok
		or currentTime == nil
		or ticketResult.value.createdAt > currentTime
		or ticketResult.value.expiresAt <= currentTime
	then
		return failure("INVALID_ARGUMENT", "create")
	end
	local ticket = ticketResult.value
	local key = ticketKey(ticket.ticketId)
	if key == nil then
		return failure("INVALID_ARGUMENT", "create")
	end
	local applied = false
	local called, stored = pcall(
		data.adapter.updateAsync,
		data.adapter,
		key,
		expiration(ticket, currentTime),
		function(current)
			if current ~= nil then
				return current
			end
			applied = true
			return ticket
		end
	)
	if not called then
		return failure("STORE_UNAVAILABLE", "create")
	end
	local validated = MatchTicketContract.validate(stored)
	if not validated.ok then
		return failure("CORRUPT_RECORD", "create")
	end
	if not applied then
		return failure("CONFLICT", "create")
	end
	data.mutationCount += 1
	return Result.ok(table.freeze({ ticket = validated.value, applied = true }))
end

function Methods.get(
	self: Store,
	ticketIdValue: unknown,
	nowValue: unknown?
): Result.Result<MatchTicketContract.Ticket, StoreError>
	local data = requireData(self)
	local ticketId = checkedTicketId(ticketIdValue)
	local currentTime = if nowValue == nil then now(data) else nowValue
	if
		ticketId == nil
		or type(currentTime) ~= "number"
		or not Validation.isSafeInteger(currentTime :: number)
		or currentTime < 0
	then
		return failure("INVALID_ARGUMENT", "get")
	end
	local key = ticketKey(ticketId)
	local called, stored = pcall(data.adapter.getAsync, data.adapter, key :: string)
	if not called then
		return failure("STORE_UNAVAILABLE", "get")
	end
	if stored == nil then
		return failure("NOT_FOUND", "get")
	end
	local validated = MatchTicketContract.validate(stored)
	if not validated.ok or validated.value.ticketId ~= ticketId then
		return failure("CORRUPT_RECORD", "get")
	end
	data.readCount += 1
	if validated.value.expiresAt <= (currentTime :: number) then
		return failure("EXPIRED", "get")
	end
	return Result.ok(validated.value)
end

local function mutate(
	data: StoreData,
	operation: Operation,
	ticketIdValue: unknown,
	nowValue: unknown,
	callback: (MatchTicketContract.Ticket) -> (MatchTicketContract.Ticket?, ErrorCode?, boolean?)
): Result.Result<MutationOutcome, StoreError>
	local ticketId = checkedTicketId(ticketIdValue)
	if
		ticketId == nil
		or type(nowValue) ~= "number"
		or not Validation.isSafeInteger(nowValue :: number)
		or nowValue < 0
	then
		return failure("INVALID_ARGUMENT", operation)
	end
	local currentTime = nowValue :: number
	local key = ticketKey(ticketId)
	if key == nil then
		return failure("INVALID_ARGUMENT", operation)
	end
	local transformError: ErrorCode? = nil
	local applied = false
	local called, stored = pcall(
		data.adapter.updateAsync,
		data.adapter,
		key,
		MatchTicketContract.MAX_TTL_SECONDS,
		function(current)
			if current == nil then
				transformError = "NOT_FOUND"
				return nil
			end
			local validated = MatchTicketContract.validate(current)
			if not validated.ok or validated.value.ticketId ~= ticketId then
				transformError = "CORRUPT_RECORD"
				return current
			end
			if validated.value.expiresAt <= currentTime then
				transformError = "EXPIRED"
				return current
			end
			local replacement, errorCode, changed = callback(validated.value)
			if replacement == nil then
				transformError = errorCode or "INVALID_STATE"
				return current
			end
			local replacementResult = MatchTicketContract.validate(replacement)
			if not replacementResult.ok then
				transformError = "CORRUPT_RECORD"
				return current
			end
			applied = changed ~= false
			return replacementResult.value
		end
	)
	if not called then
		return failure("STORE_UNAVAILABLE", operation)
	end
	if transformError ~= nil then
		return failure(transformError :: ErrorCode, operation)
	end
	local validated = MatchTicketContract.validate(stored)
	if not validated.ok then
		return failure("CORRUPT_RECORD", operation)
	end
	if applied then
		data.mutationCount += 1
	end
	return Result.ok(table.freeze({ ticket = validated.value, applied = applied }))
end

local function nextRevision(ticket: MatchTicketContract.Ticket): number?
	return if ticket.revision < Validation.MAX_SAFE_INTEGER then ticket.revision + 1 else nil
end

function Methods.markTeleporting(
	self: Store,
	ticketId: unknown,
	nowValue: unknown
): Result.Result<MutationOutcome, StoreError>
	return mutate(requireData(self), "markTeleporting", ticketId, nowValue, function(ticket)
		if ticket.state == "Teleporting" then
			return ticket, nil, false
		end
		if ticket.state ~= "Created" then
			return nil, "INVALID_STATE"
		end
		local revision = nextRevision(ticket)
		if revision == nil then
			return nil, "INVALID_STATE"
		end
		local replacement = MatchTicketContract.clone(ticket)
		replacement.revision = revision
		replacement.state = "Teleporting"
		return replacement
	end)
end

function Methods.claimDestination(
	self: Store,
	ticketId: unknown,
	destinationJobId: unknown,
	nowValue: unknown
): Result.Result<MutationOutcome, StoreError>
	return mutate(requireData(self), "claimDestination", ticketId, nowValue, function(ticket)
		if type(destinationJobId) ~= "string" or #destinationJobId < 1 or #destinationJobId > 100 then
			return nil, "INVALID_ARGUMENT"
		end
		if ticket.claimedDestinationJobId ~= nil then
			if ticket.claimedDestinationJobId == destinationJobId and ticket.state == "Active" then
				return ticket, nil, false
			end
			return nil, "DESTINATION_CONFLICT"
		end
		if ticket.state ~= "Created" and ticket.state ~= "Teleporting" then
			return nil, "INVALID_STATE"
		end
		local revision = nextRevision(ticket)
		if revision == nil then
			return nil, "INVALID_STATE"
		end
		local replacement = MatchTicketContract.clone(ticket)
		replacement.revision = revision
		replacement.claimedDestinationJobId = destinationJobId :: string
		replacement.claimedDestinationAt = nowValue :: number
		replacement.state = "Active"
		return replacement
	end)
end

function Methods.markAdmission(
	self: Store,
	ticketId: unknown,
	destinationJobId: unknown,
	userIdValue: unknown,
	stateValue: unknown,
	nowValue: unknown
): Result.Result<MutationOutcome, StoreError>
	return mutate(requireData(self), "markAdmission", ticketId, nowValue, function(ticket)
		if
			type(destinationJobId) ~= "string"
			or ticket.claimedDestinationJobId ~= destinationJobId
			or ticket.state ~= "Active"
		then
			return nil, "DESTINATION_CONFLICT"
		end
		if
			type(userIdValue) ~= "number"
			or not Validation.isSafeInteger(userIdValue :: number)
			or userIdValue <= 0
			or (stateValue ~= "Admitted" and stateValue ~= "LateSpectator" and stateValue ~= "Returned")
		then
			return nil, "INVALID_ARGUMENT"
		end
		local _, index = MatchTicketContract.member(ticket, userIdValue :: number)
		if index == nil then
			return nil, "UNEXPECTED_MEMBER"
		end
		local currentState = ticket.members[index].admissionState
		if currentState == stateValue then
			return ticket, nil, false
		end
		local validTransition = (
			currentState == "Expected" and (stateValue == "Admitted" or stateValue == "LateSpectator")
		) or ((currentState == "Admitted" or currentState == "LateSpectator") and stateValue == "Returned")
		if not validTransition then
			return nil, "INVALID_STATE"
		end
		local revision = nextRevision(ticket)
		if revision == nil then
			return nil, "INVALID_STATE"
		end
		local replacement = MatchTicketContract.clone(ticket)
		replacement.revision = revision
		replacement.members[index].admissionState = stateValue
		replacement.members[index].admittedAt = nowValue :: number
		return replacement
	end)
end

function Methods.recordRetry(
	self: Store,
	ticketId: unknown,
	nowValue: unknown
): Result.Result<MutationOutcome, StoreError>
	return mutate(requireData(self), "recordRetry", ticketId, nowValue, function(ticket)
		if ticket.state == "Terminal" then
			return nil, "INVALID_STATE"
		end
		if ticket.retryCount >= MatchTicketContract.MAX_RETRIES then
			return nil, "RETRY_EXHAUSTED"
		end
		local revision = nextRevision(ticket)
		if revision == nil then
			return nil, "INVALID_STATE"
		end
		local replacement = MatchTicketContract.clone(ticket)
		replacement.revision = revision
		replacement.retryCount += 1
		return replacement
	end)
end

function Methods.markTerminal(
	self: Store,
	ticketId: unknown,
	reasonValue: unknown,
	nowValue: unknown
): Result.Result<MutationOutcome, StoreError>
	return mutate(requireData(self), "markTerminal", ticketId, nowValue, function(ticket)
		if type(reasonValue) ~= "string" or #reasonValue < 1 or #reasonValue > 100 then
			return nil, "INVALID_ARGUMENT"
		end
		if ticket.state == "Terminal" then
			if ticket.terminalReason == reasonValue then
				return ticket, nil, false
			end
			return nil, "CONFLICT"
		end
		local revision = nextRevision(ticket)
		if revision == nil then
			return nil, "INVALID_STATE"
		end
		local replacement = MatchTicketContract.clone(ticket)
		replacement.revision = revision
		replacement.state = "Terminal"
		replacement.terminalReason = reasonValue :: string
		return replacement
	end)
end

function Methods.getMetrics(self: Store): { readCount: number, mutationCount: number }
	local data = requireData(self)
	return table.freeze({ readCount = data.readCount, mutationCount = data.mutationCount })
end

function TravelRecordStore.new(adapterValue: unknown, dependencies: Dependencies?): Result.Result<Store, StoreError>
	if
		type(adapterValue) ~= "table"
		or type((adapterValue :: any).getAsync) ~= "function"
		or type((adapterValue :: any).updateAsync) ~= "function"
		or type((adapterValue :: any).removeAsync) ~= "function"
		or (dependencies ~= nil and (type(dependencies) ~= "table" or getmetatable(dependencies :: any) ~= nil))
		or (dependencies ~= nil and dependencies.clock ~= nil and type(dependencies.clock) ~= "function")
	then
		return failure("INVALID_ARGUMENT", "create")
	end
	local store = setmetatable({}, Methods) :: Store
	table.freeze(store)
	DATA[store] = {
		adapter = adapterValue :: Adapter,
		clock = if dependencies ~= nil and dependencies.clock ~= nil then dependencies.clock else os.time,
		mutationCount = 0,
		readCount = 0,
	}
	return Result.ok(store)
end

table.freeze(Methods)
return table.freeze(TravelRecordStore)
