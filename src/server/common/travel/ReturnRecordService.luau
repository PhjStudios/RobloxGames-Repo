--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Adapter = {
	getAsync: (self: Adapter, key: string) -> unknown,
	updateAsync: (self: Adapter, key: string, expirationSeconds: number, transform: (unknown) -> unknown) -> unknown,
	removeAsync: (self: Adapter, key: string) -> unknown,
}

export type MemberState = "Expected" | "Arrived"
export type Member = { userId: number, state: MemberState, arrivedAt: number? }
export type ReturnState = "Active" | "Terminal"
export type ReturnRecord = {
	version: number,
	revision: number,
	returnId: string,
	matchId: string,
	priorLeaderUserId: number,
	expectedUserIds: { number },
	members: { Member },
	createdAt: number,
	expiresAt: number,
	state: ReturnState,
	terminalReason: string?,
}

export type ErrorCode =
	"INVALID_ARGUMENT"
	| "NOT_FOUND"
	| "EXPIRED"
	| "CONFLICT"
	| "UNEXPECTED_MEMBER"
	| "INVALID_STATE"
	| "STORE_UNAVAILABLE"
export type Operation = "create" | "get" | "admit" | "markTerminal"
export type ReturnError = { code: ErrorCode, operation: Operation }
export type MutationOutcome = { record: ReturnRecord, applied: boolean }

type ServiceData = { adapter: Adapter }

local VERSION = 1
local MAX_MEMBERS = 4
local MAX_TTL_SECONDS = 600
local ROOT_FIELDS = table.freeze({
	version = true,
	revision = true,
	returnId = true,
	matchId = true,
	priorLeaderUserId = true,
	expectedUserIds = true,
	members = true,
	createdAt = true,
	expiresAt = true,
	state = true,
	terminalReason = true,
})
local MEMBER_FIELDS = table.freeze({ userId = true, state = true, arrivedAt = true })

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local ReturnRecordService = {
	VERSION = VERSION,
	MAX_TTL_SECONDS = MAX_TTL_SECONDS,
}

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<ReturnError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_RETURN_RECORD][code=INVALID_CONTEXT]", 0)
	end
	return data :: ServiceData
end

local function clone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local output = {}
	for key, child in value do
		output[clone(key)] = clone(child)
	end
	return output
end

local function safeInteger(value: unknown, minimum: number): number?
	return if type(value) == "number"
			and Validation.isSafeInteger(value :: number)
			and value >= minimum
		then value :: number
		else nil
end

local function dense(value: unknown): { unknown }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local count = 0
	local largest = 0
	for key in value :: { [any]: unknown } do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 then
			return nil
		end
		count += 1
		largest = math.max(largest, key)
	end
	return if count == largest and count >= 1 and count <= MAX_MEMBERS then value :: { unknown } else nil
end

local function onlyFields(record: { [any]: unknown }, fields: { [string]: boolean }): boolean
	for key in record do
		if type(key) ~= "string" or fields[key] ~= true then
			return false
		end
	end
	return true
end

local function validate(value: unknown): ReturnRecord?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local record = value :: { [any]: unknown }
	if not onlyFields(record, ROOT_FIELDS) then
		return nil
	end
	for _, field in
		{
			"version",
			"revision",
			"returnId",
			"matchId",
			"priorLeaderUserId",
			"expectedUserIds",
			"members",
			"createdAt",
			"expiresAt",
			"state",
		}
	do
		if rawget(record, field) == nil then
			return nil
		end
	end
	local returnId = TravelProtocol.validateOpaqueId(record.returnId, "return")
	local revision = safeInteger(record.revision, 1)
	local leader = safeInteger(record.priorLeaderUserId, 1)
	local createdAt = safeInteger(record.createdAt, 0)
	local expiresAt = safeInteger(record.expiresAt, 0)
	local expected = dense(record.expectedUserIds)
	local rawMembers = dense(record.members)
	if
		record.version ~= VERSION
		or not returnId.ok
		or type(record.matchId) ~= "string"
		or string.sub(record.matchId :: string, 1, 6) ~= "match:"
		or #record.matchId > 100
		or revision == nil
		or leader == nil
		or createdAt == nil
		or expiresAt == nil
		or expiresAt <= createdAt
		or expiresAt - createdAt > MAX_TTL_SECONDS
		or expected == nil
		or rawMembers == nil
		or #expected ~= #rawMembers
		or (record.state ~= "Active" and record.state ~= "Terminal")
	then
		return nil
	end
	local expectedUserIds: { number } = table.create(#expected)
	local members: { Member } = table.create(#rawMembers)
	local seen: { [number]: boolean } = {}
	local leaderFound = false
	for index, rawUserId in expected do
		local id = safeInteger(rawUserId, 1)
		local rawMember = rawMembers[index]
		if id == nil or seen[id] or type(rawMember) ~= "table" or getmetatable(rawMember :: any) ~= nil then
			return nil
		end
		local member = rawMember :: { [any]: unknown }
		if
			not onlyFields(member, MEMBER_FIELDS)
			or member.userId ~= id
			or (member.state ~= "Expected" and member.state ~= "Arrived")
		then
			return nil
		end
		local arrivedAt = if member.arrivedAt == nil then nil else safeInteger(member.arrivedAt, createdAt)
		if (member.state == "Expected") ~= (arrivedAt == nil) or (arrivedAt ~= nil and arrivedAt > expiresAt) then
			return nil
		end
		seen[id] = true
		leaderFound = leaderFound or id == leader
		expectedUserIds[index] = id
		members[index] = { userId = id, state = member.state :: MemberState, arrivedAt = arrivedAt }
	end
	if not leaderFound then
		return nil
	end
	local terminalReason = if record.terminalReason == nil
		then nil
		elseif
			type(record.terminalReason) == "string"
			and #record.terminalReason >= 1
			and #record.terminalReason <= 100
		then record.terminalReason :: string
		else nil
	if (record.state == "Terminal") ~= (terminalReason ~= nil) then
		return nil
	end
	return table.freeze({
		version = VERSION,
		revision = revision,
		returnId = returnId.value,
		matchId = record.matchId :: string,
		priorLeaderUserId = leader,
		expectedUserIds = table.freeze(expectedUserIds),
		members = table.freeze(members),
		createdAt = createdAt,
		expiresAt = expiresAt,
		state = record.state :: ReturnState,
		terminalReason = terminalReason,
	})
end

local function keyFor(returnId: string): string
	return `return/{returnId}`
end

function Methods.create(
	self: Service,
	recordValue: unknown,
	nowValue: unknown
): Result.Result<MutationOutcome, ReturnError>
	local data = requireData(self)
	local record = validate(recordValue)
	if
		record == nil
		or type(nowValue) ~= "number"
		or not Validation.isSafeInteger(nowValue :: number)
		or nowValue < record.createdAt
		or nowValue >= record.expiresAt
	then
		return failure("INVALID_ARGUMENT", "create")
	end
	local applied = false
	local called, stored = pcall(
		data.adapter.updateAsync,
		data.adapter,
		keyFor(record.returnId),
		record.expiresAt - (nowValue :: number),
		function(current)
			if current ~= nil then
				return current
			end
			applied = true
			return record
		end
	)
	if not called then
		return failure("STORE_UNAVAILABLE", "create")
	end
	if not applied then
		return failure("CONFLICT", "create")
	end
	local canonical = validate(stored)
	return if canonical == nil
		then failure("STORE_UNAVAILABLE", "create")
		else Result.ok(table.freeze({ record = canonical, applied = true }))
end

function Methods.get(self: Service, returnIdValue: unknown, nowValue: unknown): Result.Result<ReturnRecord, ReturnError>
	local data = requireData(self)
	local returnId = TravelProtocol.validateOpaqueId(returnIdValue, "return")
	if
		not returnId.ok
		or type(nowValue) ~= "number"
		or not Validation.isSafeInteger(nowValue :: number)
		or nowValue < 0
	then
		return failure("INVALID_ARGUMENT", "get")
	end
	local called, stored = pcall(data.adapter.getAsync, data.adapter, keyFor(returnId.value))
	if not called then
		return failure("STORE_UNAVAILABLE", "get")
	end
	if stored == nil then
		return failure("NOT_FOUND", "get")
	end
	local record = validate(stored)
	if record == nil or record.returnId ~= returnId.value then
		return failure("STORE_UNAVAILABLE", "get")
	end
	if record.expiresAt <= (nowValue :: number) then
		return failure("EXPIRED", "get")
	end
	return Result.ok(record)
end

local function mutate(
	data: ServiceData,
	operation: Operation,
	returnId: string,
	nowValue: number,
	callback: (ReturnRecord) -> (ReturnRecord?, ErrorCode?, boolean?)
): Result.Result<MutationOutcome, ReturnError>
	local transformError: ErrorCode? = nil
	local applied = false
	local called, stored = pcall(
		data.adapter.updateAsync,
		data.adapter,
		keyFor(returnId),
		MAX_TTL_SECONDS,
		function(current)
			local record = validate(current)
			if record == nil then
				transformError = "NOT_FOUND"
				return current
			end
			if record.expiresAt <= nowValue then
				transformError = "EXPIRED"
				return current
			end
			local replacement, errorCode, changed = callback(record)
			if replacement == nil then
				transformError = errorCode or "INVALID_STATE"
				return current
			end
			local canonical = validate(replacement)
			if canonical == nil then
				transformError = "INVALID_STATE"
				return current
			end
			applied = changed ~= false
			return canonical
		end
	)
	if not called then
		return failure("STORE_UNAVAILABLE", operation)
	end
	if transformError ~= nil then
		return failure(transformError :: ErrorCode, operation)
	end
	local record = validate(stored)
	return if record == nil
		then failure("STORE_UNAVAILABLE", operation)
		else Result.ok(table.freeze({ record = record, applied = applied }))
end

function Methods.admit(
	self: Service,
	returnIdValue: unknown,
	userIdValue: unknown,
	nowValue: unknown
): Result.Result<MutationOutcome, ReturnError>
	local returnId = TravelProtocol.validateOpaqueId(returnIdValue, "return")
	local id = safeInteger(userIdValue, 1)
	if
		not returnId.ok
		or id == nil
		or type(nowValue) ~= "number"
		or not Validation.isSafeInteger(nowValue :: number)
		or nowValue < 0
	then
		return failure("INVALID_ARGUMENT", "admit")
	end
	return mutate(requireData(self), "admit", returnId.value, nowValue :: number, function(record)
		if record.state ~= "Active" then
			return nil, "INVALID_STATE"
		end
		local index: number? = nil
		for candidate, member in record.members do
			if member.userId == id then
				index = candidate
				break
			end
		end
		if index == nil then
			return nil, "UNEXPECTED_MEMBER"
		end
		if record.members[index].state == "Arrived" then
			return record, nil, false
		end
		local replacement = clone(record)
		replacement.revision += 1
		replacement.members[index].state = "Arrived"
		replacement.members[index].arrivedAt = nowValue
		return replacement
	end)
end

function Methods.markTerminal(
	self: Service,
	returnIdValue: unknown,
	reasonValue: unknown,
	nowValue: unknown
): Result.Result<MutationOutcome, ReturnError>
	local returnId = TravelProtocol.validateOpaqueId(returnIdValue, "return")
	if
		not returnId.ok
		or type(reasonValue) ~= "string"
		or #reasonValue < 1
		or #reasonValue > 100
		or type(nowValue) ~= "number"
		or not Validation.isSafeInteger(nowValue :: number)
		or nowValue < 0
	then
		return failure("INVALID_ARGUMENT", "markTerminal")
	end
	return mutate(requireData(self), "markTerminal", returnId.value, nowValue :: number, function(record)
		if record.state == "Terminal" then
			if record.terminalReason == reasonValue then
				return record, nil, false
			end
			return nil, "CONFLICT"
		end
		local replacement = clone(record)
		replacement.revision += 1
		replacement.state = "Terminal"
		replacement.terminalReason = reasonValue
		return replacement
	end)
end

function ReturnRecordService.new(adapterValue: unknown): Result.Result<Service, ReturnError>
	if
		type(adapterValue) ~= "table"
		or type((adapterValue :: any).getAsync) ~= "function"
		or type((adapterValue :: any).updateAsync) ~= "function"
		or type((adapterValue :: any).removeAsync) ~= "function"
	then
		return failure("INVALID_ARGUMENT", "create")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = { adapter = adapterValue :: Adapter }
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(ReturnRecordService)
