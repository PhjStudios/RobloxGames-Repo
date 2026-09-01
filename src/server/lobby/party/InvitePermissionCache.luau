--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Dependencies = {
	clock: () -> unknown,
	schedule: (() -> ()) -> unknown,
	lookup: (number, number) -> unknown,
	allowLifetimeSeconds: number?,
	denyLifetimeSeconds: number?,
	maxEntries: number?,
	requestLimit: number?,
	requestWindowSeconds: number?,
}

export type ErrorCode = "INVALID_DEPENDENCIES" | "INVALID_USER_ID" | "RATE_LIMITED" | "UNAVAILABLE" | "CLEANED"
export type CacheError = { code: ErrorCode, operation: string }

type Entry = {
	inviterUserId: number,
	targetUserId: number,
	permitted: boolean,
	expiresAt: number,
}

type RateWindow = { startedAt: number, count: number }

type ServiceData = {
	dependencies: Dependencies,
	allowLifetimeSeconds: number,
	denyLifetimeSeconds: number,
	maxEntries: number,
	requestLimit: number,
	requestWindowSeconds: number,
	entries: { [string]: Entry },
	entryOrder: { string },
	inFlight: { [string]: boolean },
	rates: { [number]: RateWindow },
	cleaned: boolean,
	lookupFailureCount: number,
}

local Methods = {}
Methods.__index = Methods
export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local DEFAULT_ALLOW_LIFETIME_SECONDS = 60
local DEFAULT_DENY_LIFETIME_SECONDS = 15
local DEFAULT_MAX_ENTRIES = 128
local DEFAULT_REQUEST_LIMIT = 8
local DEFAULT_REQUEST_WINDOW_SECONDS = 10
local InvitePermissionCache = {}

local function failure<T>(code: ErrorCode, operation: string): Result.Failure<CacheError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_INVITE_PERMISSION_CACHE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and value > 0
end

local function currentTime(data: ServiceData): number?
	local called, value = pcall(data.dependencies.clock)
	return if called
			and type(value) == "number"
			and Validation.isSafeInteger(value :: number)
			and value >= 0
		then value :: number
		else nil
end

local function keyFor(inviterUserId: number, targetUserId: number): string
	return `{inviterUserId}/{targetUserId}`
end

local function removeEntry(data: ServiceData, key: string)
	data.entries[key] = nil
	for index, candidate in data.entryOrder do
		if candidate == key then
			table.remove(data.entryOrder, index)
			return
		end
	end
end

local function storeEntry(data: ServiceData, key: string, entry: Entry)
	if data.entries[key] ~= nil then
		removeEntry(data, key)
	end
	while #data.entryOrder >= data.maxEntries do
		local oldest = table.remove(data.entryOrder, 1)
		if oldest ~= nil then
			data.entries[oldest] = nil
		end
	end
	data.entries[key] = entry
	table.insert(data.entryOrder, key)
end

local function rateAllowed(data: ServiceData, inviterUserId: number, nowValue: number): boolean
	local window = data.rates[inviterUserId]
	if window == nil or nowValue - window.startedAt >= data.requestWindowSeconds then
		data.rates[inviterUserId] = { startedAt = nowValue, count = 1 }
		return true
	elseif window.count >= data.requestLimit then
		return false
	end
	window.count += 1
	return true
end

function Methods.get(self: Service, inviterUserIdValue: unknown, targetUserIdValue: unknown): boolean?
	local data = requireData(self)
	if
		data.cleaned
		or not validUserId(inviterUserIdValue)
		or not validUserId(targetUserIdValue)
		or inviterUserIdValue == targetUserIdValue
	then
		return nil
	end
	local nowValue = currentTime(data)
	if nowValue == nil then
		return nil
	end
	local key = keyFor(inviterUserIdValue :: number, targetUserIdValue :: number)
	local entry = data.entries[key]
	if entry ~= nil and entry.expiresAt <= nowValue then
		removeEntry(data, key)
		entry = nil
	end
	return if entry == nil then nil else entry.permitted
end

function Methods.request(
	self: Service,
	inviterUserIdValue: unknown,
	targetUserIdValue: unknown
): Result.Result<boolean, CacheError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "request")
	end
	if
		not validUserId(inviterUserIdValue)
		or not validUserId(targetUserIdValue)
		or inviterUserIdValue == targetUserIdValue
	then
		return failure("INVALID_USER_ID", "request")
	end
	local inviterUserId = inviterUserIdValue :: number
	local targetUserId = targetUserIdValue :: number
	if self:get(inviterUserId, targetUserId) ~= nil then
		return Result.ok(false)
	end
	local key = keyFor(inviterUserId, targetUserId)
	if data.inFlight[key] then
		return Result.ok(false)
	end
	local nowValue = currentTime(data)
	if nowValue == nil then
		return failure("UNAVAILABLE", "request")
	elseif not rateAllowed(data, inviterUserId, nowValue) then
		return failure("RATE_LIMITED", "request")
	end
	data.inFlight[key] = true
	local scheduled, scheduleResult = pcall(data.dependencies.schedule, function()
		if data.cleaned or not data.inFlight[key] then
			return
		end
		local called, permitted = pcall(data.dependencies.lookup, inviterUserId, targetUserId)
		if data.cleaned or not data.inFlight[key] then
			return
		end
		data.inFlight[key] = nil
		local completedAt = currentTime(data)
		if not called or type(permitted) ~= "boolean" or completedAt == nil then
			data.lookupFailureCount += 1
			return
		end
		storeEntry(data, key, {
			inviterUserId = inviterUserId,
			targetUserId = targetUserId,
			permitted = permitted,
			expiresAt = completedAt + if permitted then data.allowLifetimeSeconds else data.denyLifetimeSeconds,
		})
	end)
	if not scheduled or scheduleResult == false then
		data.inFlight[key] = nil
		return failure("UNAVAILABLE", "request")
	end
	return Result.ok(true)
end

function Methods.removePlayer(self: Service, userIdValue: unknown): boolean
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return false
	end
	local userId = userIdValue :: number
	local changed = false
	for index = #data.entryOrder, 1, -1 do
		local key = data.entryOrder[index]
		local entry = data.entries[key]
		if entry ~= nil and (entry.inviterUserId == userId or entry.targetUserId == userId) then
			data.entries[key] = nil
			table.remove(data.entryOrder, index)
			changed = true
		end
	end
	for key in data.inFlight do
		local separator = string.find(key, "/", 1, true)
		if separator ~= nil then
			local inviter = tonumber(string.sub(key, 1, separator - 1))
			local target = tonumber(string.sub(key, separator + 1))
			if inviter == userId or target == userId then
				data.inFlight[key] = nil
				changed = true
			end
		end
	end
	data.rates[userId] = nil
	return changed
end

function Methods.cleanup(self: Service): Result.Result<boolean, CacheError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	data.cleaned = true
	table.clear(data.entries)
	table.clear(data.entryOrder)
	table.clear(data.inFlight)
	table.clear(data.rates)
	return Result.ok(true)
end

function Methods.getMetrics(self: Service): { [string]: number | boolean }
	local data = requireData(self)
	local inFlightCount = 0
	for _ in data.inFlight do
		inFlightCount += 1
	end
	return table.freeze({
		entryCount = #data.entryOrder,
		inFlightCount = inFlightCount,
		lookupFailureCount = data.lookupFailureCount,
		cleaned = data.cleaned,
	})
end

function Methods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	return table.freeze({
		name = "InvitePermissionCache",
		dependencies = table.freeze({}),
		initialize = function() end,
		start = function() end,
		shutdown = function()
			self:cleanup()
		end,
	})
end

function InvitePermissionCache.new(dependenciesValue: unknown): Result.Result<Service, CacheError>
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local dependencies = dependenciesValue :: any
	local allowLifetime = dependencies.allowLifetimeSeconds or DEFAULT_ALLOW_LIFETIME_SECONDS
	local denyLifetime = dependencies.denyLifetimeSeconds or DEFAULT_DENY_LIFETIME_SECONDS
	local maxEntries = dependencies.maxEntries or DEFAULT_MAX_ENTRIES
	local requestLimit = dependencies.requestLimit or DEFAULT_REQUEST_LIMIT
	local requestWindow = dependencies.requestWindowSeconds or DEFAULT_REQUEST_WINDOW_SECONDS
	if
		type(dependencies.clock) ~= "function"
		or type(dependencies.schedule) ~= "function"
		or type(dependencies.lookup) ~= "function"
		or type(allowLifetime) ~= "number"
		or not Validation.isSafeInteger(allowLifetime)
		or allowLifetime < 5
		or allowLifetime > 300
		or type(denyLifetime) ~= "number"
		or not Validation.isSafeInteger(denyLifetime)
		or denyLifetime < 5
		or denyLifetime > 60
		or type(maxEntries) ~= "number"
		or not Validation.isSafeInteger(maxEntries)
		or maxEntries < 4
		or maxEntries > 512
		or type(requestLimit) ~= "number"
		or not Validation.isSafeInteger(requestLimit)
		or requestLimit < 1
		or requestLimit > 32
		or type(requestWindow) ~= "number"
		or not Validation.isSafeInteger(requestWindow)
		or requestWindow < 1
		or requestWindow > 60
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		dependencies = dependenciesValue :: Dependencies,
		allowLifetimeSeconds = allowLifetime,
		denyLifetimeSeconds = denyLifetime,
		maxEntries = maxEntries,
		requestLimit = requestLimit,
		requestWindowSeconds = requestWindow,
		entries = {},
		entryOrder = {},
		inFlight = {},
		rates = {},
		cleaned = false,
		lookupFailureCount = 0,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(InvitePermissionCache)
