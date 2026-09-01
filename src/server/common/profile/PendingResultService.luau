--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local ProfileSchema = require(script.Parent.ProfileSchema)

export type ProfileOwner = {
	read: (self: ProfileOwner, userId: number) -> unknown,
	flush: (self: ProfileOwner, userId: number) -> unknown,
	transact: (
		self: ProfileOwner,
		userId: number,
		transactionId: string,
		expectedRevision: number,
		kind: string,
		fingerprint: string,
		callback: (profile: any) -> unknown
	) -> unknown,
}

export type Reservation = {
	resultId: string,
	createdAt: number,
	orderedUserIds: { number },
}

export type ErrorCode =
	"INVALID_ARGUMENT"
	| "PROFILE_NOT_READY"
	| "ALREADY_CLAIMED"
	| "CAPACITY_EXCEEDED"
	| "RESERVE_FAILED"
	| "ROLLBACK_FAILED"
	| "RELEASE_FAILED"
	| "BUSY"
	| "CLEANED"

export type Operation = "reserve" | "release" | "list" | "cleanup"
export type PendingError = { code: ErrorCode, operation: Operation }

type ServiceData = {
	profile: ProfileOwner,
	busyUserIds: { [number]: boolean },
	cleaned: boolean,
}

local Methods = {}
Methods.__index = Methods
export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local PendingResultService = {}

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<PendingError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_PENDING_RESULT][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function resultId(value: unknown): string?
	if type(value) ~= "string" or #value < 9 or #value > 43 or string.sub(value :: string, 1, 7) ~= "result:" then
		return nil
	end
	for index = 8, #value do
		local byte = string.byte(value :: string, index)
		if
			byte == nil
			or not (
				(byte >= string.byte("a") and byte <= string.byte("z"))
				or (byte >= string.byte("0") and byte <= string.byte("9"))
				or byte == string.byte("-")
			)
		then
			return nil
		end
	end
	return value :: string
end

local function roster(value: unknown): { number }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or #value < 1 or #value > 4 then
		return nil
	end
	local output: { number } = table.create(#value)
	local seen: { [number]: boolean } = {}
	for index, userId in value :: { unknown } do
		if
			type(userId) ~= "number"
			or not Validation.isSafeInteger(userId :: number)
			or userId <= 0
			or seen[userId :: number]
		then
			return nil
		end
		seen[userId :: number] = true
		output[index] = userId :: number
	end
	return output
end

local function success(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function readProfile(data: ServiceData, userId: number): any?
	local called, value = pcall(data.profile.read, data.profile, userId)
	return if called and success(value) then (value :: any).value else nil
end

local function contains(records: { any }, id: string): boolean
	for _, record in records do
		if record.resultId == id then
			return true
		end
	end
	return false
end

local function transactionId(id: string, prefix: string): string
	return `transaction:{prefix}-{string.sub(id, 8)}`
end

local function receipt(profile: any, code: string)
	return Result.ok({
		resultCode = code,
		goldBalance = profile.gold,
		unitIds = {},
		towerIds = {},
		newFlags = {},
		pityCount = 0,
	})
end

local function mutate(
	data: ServiceData,
	userId: number,
	id: string,
	createdAt: number,
	add: boolean
): (boolean, ErrorCode?)
	local profile = readProfile(data, userId)
	if profile == nil then
		return false, "PROFILE_NOT_READY"
	end
	if add and contains(profile.claimedResults, id) then
		return false, "ALREADY_CLAIMED"
	elseif
		add
		and not contains(profile.pendingResults, id)
		and #profile.pendingResults >= ProfileSchema.MAX_PENDING_RESULT_IDS
	then
		return false, "CAPACITY_EXCEEDED"
	end
	local called, value = pcall(
		data.profile.transact,
		data.profile,
		userId,
		transactionId(id, if add then "p" else "x"),
		profile.revision,
		if add then "ReserveMatchResult" else "ReleaseMatchResult",
		`pending-result|{if add then "add" else "remove"}|{id}|{userId}`,
		function(draft: any)
			local index: number? = nil
			for candidate, pending in draft.pendingResults do
				if pending.resultId == id then
					index = candidate
					break
				end
			end
			if add then
				if contains(draft.claimedResults, id) then
					return Result.err("ALREADY_CLAIMED")
				elseif index == nil then
					if #draft.pendingResults >= ProfileSchema.MAX_PENDING_RESULT_IDS then
						return Result.err("CAPACITY_EXCEEDED")
					end
					table.insert(draft.pendingResults, { resultId = id, createdAt = createdAt })
				end
			else
				if index ~= nil then
					table.remove(draft.pendingResults, index)
				end
			end
			return receipt(draft, if add then "RESULT_RESERVED" else "RESULT_RELEASED")
		end
	)
	if called and success(value) then
		return true, nil
	end
	-- ProfileService mutates its owned in-memory profile before a durable-store
	-- response can fail. Verify the exact postcondition so commit-before-error is
	-- treated as success, while a genuine rejection still fails closed.
	local verified = readProfile(data, userId)
	if verified ~= nil and contains(verified.pendingResults, id) == add then
		return true, nil
	end
	return false, nil
end

function Methods.reserve(
	self: Service,
	userIdsValue: unknown,
	resultIdValue: unknown,
	createdAtValue: unknown
): Result.Result<Reservation, PendingError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "reserve")
	end
	local userIds = roster(userIdsValue)
	local id = resultId(resultIdValue)
	if
		userIds == nil
		or id == nil
		or type(createdAtValue) ~= "number"
		or not Validation.isSafeInteger(createdAtValue :: number)
		or createdAtValue < 0
	then
		return failure("INVALID_ARGUMENT", "reserve")
	end
	for _, userId in userIds do
		if data.busyUserIds[userId] then
			return failure("BUSY", "reserve")
		end
		data.busyUserIds[userId] = true
	end
	local failedCode: ErrorCode? = nil
	for _, userId in userIds do
		local applied, code = mutate(data, userId, id, createdAtValue :: number, true)
		if not applied then
			failedCode = code or "RESERVE_FAILED"
			break
		end
	end
	if failedCode ~= nil then
		-- A protected profile transaction may commit and still return a transport
		-- failure. Treat every attempted squad member as potentially committed and
		-- remove this exact result ID idempotently from the complete roster. This
		-- keeps a failed ticket launch from leaving an orphan reward reservation.
		local rollbackFailed = false
		for index = #userIds, 1, -1 do
			rollbackFailed = not mutate(data, userIds[index], id, createdAtValue :: number, false) or rollbackFailed
		end
		for _, userId in userIds do
			data.busyUserIds[userId] = nil
		end
		return failure(if rollbackFailed then "ROLLBACK_FAILED" else failedCode, "reserve")
	end
	for _, userId in userIds do
		data.busyUserIds[userId] = nil
	end
	return Result.ok(table.freeze({
		resultId = id,
		createdAt = createdAtValue :: number,
		orderedUserIds = table.freeze(table.clone(userIds)),
	}))
end

function Methods.release(
	self: Service,
	userIdsValue: unknown,
	resultIdValue: unknown,
	createdAtValue: unknown
): Result.Result<boolean, PendingError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "release")
	end
	local userIds = roster(userIdsValue)
	local id = resultId(resultIdValue)
	if
		userIds == nil
		or id == nil
		or type(createdAtValue) ~= "number"
		or not Validation.isSafeInteger(createdAtValue :: number)
		or createdAtValue < 0
	then
		return failure("INVALID_ARGUMENT", "release")
	end
	for _, userId in userIds do
		if data.busyUserIds[userId] then
			return failure("BUSY", "release")
		end
		data.busyUserIds[userId] = true
	end
	local released = true
	for _, userId in userIds do
		released = mutate(data, userId, id, createdAtValue :: number, false) and released
	end
	-- Reservations become durable when travel flushes/releases profile leases.
	-- Their compensating removal must therefore be durable before callers expose
	-- a recovered queue; an autosave-only cleanup can resurrect an orphan result
	-- after a server crash.
	for _, userId in userIds do
		local called, flushed = pcall(data.profile.flush, data.profile, userId)
		released = called and success(flushed) and released
	end
	for _, userId in userIds do
		data.busyUserIds[userId] = nil
	end
	return if released then Result.ok(true) else failure("RELEASE_FAILED", "release")
end

function Methods.list(
	self: Service,
	userIdValue: unknown
): Result.Result<{ ProfileSchema.PendingResultRecord }, PendingError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "list")
	end
	if type(userIdValue) ~= "number" or not Validation.isSafeInteger(userIdValue :: number) or userIdValue <= 0 then
		return failure("INVALID_ARGUMENT", "list")
	end
	local profile = readProfile(data, userIdValue :: number)
	if profile == nil then
		return failure("PROFILE_NOT_READY", "list")
	end
	local output = table.create(#profile.pendingResults)
	for index, pending in profile.pendingResults do
		output[index] = table.freeze({ resultId = pending.resultId, createdAt = pending.createdAt })
	end
	return Result.ok(table.freeze(output))
end

function Methods.cleanup(self: Service): Result.Result<boolean, PendingError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	data.cleaned = true
	table.clear(data.busyUserIds)
	return Result.ok(true)
end

function PendingResultService.new(profileValue: unknown): Result.Result<Service, PendingError>
	if
		type(profileValue) ~= "table"
		or type((profileValue :: any).read) ~= "function"
		or type((profileValue :: any).flush) ~= "function"
		or type((profileValue :: any).transact) ~= "function"
	then
		return failure("INVALID_ARGUMENT", "reserve")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = { profile = profileValue :: ProfileOwner, busyUserIds = {}, cleaned = false }
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(PendingResultService)
