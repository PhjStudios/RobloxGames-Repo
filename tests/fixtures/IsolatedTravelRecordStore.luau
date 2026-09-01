--!strict

-- Test-only deterministic adapter. It never opens MemoryStoreService,
-- TeleportService, or DataStoreService.

export type Adapter = {
	getAsync: (self: Adapter, key: string) -> unknown,
	updateAsync: (self: Adapter, key: string, expirationSeconds: number, transform: (unknown) -> unknown) -> unknown,
	removeAsync: (self: Adapter, key: string) -> unknown,
	seed: (self: Adapter, key: string, value: unknown, expirationSeconds: number?) -> (),
	read: (self: Adapter, key: string) -> unknown,
	failNext: (self: Adapter, count: number) -> (),
	setNow: (self: Adapter, now: number) -> (),
	getMetrics: (self: Adapter) -> { keyCount: number, readCount: number, updateCount: number, failureCount: number },
}

type Entry = { value: unknown, expiresAt: number }
type Data = {
	entries: { [string]: Entry },
	now: number,
	remainingFailures: number,
	readCount: number,
	updateCount: number,
	failureCount: number,
	inUpdate: boolean,
}

local Methods = {}
Methods.__index = Methods

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: Data }
local IsolatedTravelRecordStore = {}

local function clone(value: any, seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end
	local memo = seen or {}
	if memo[value] ~= nil then
		return memo[value]
	end
	local output = {}
	memo[value] = output
	for key, child in value do
		output[clone(key, memo)] = clone(child, memo)
	end
	return output
end

local function dataFor(value: unknown): Data
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ISOLATED_TRAVEL_STORE][code=INVALID_CONTEXT]", 0)
	end
	return data :: Data
end

local function validKey(value: unknown): string
	if type(value) ~= "string" or #value < 1 or #value > 128 then
		error("[ISOLATED_TRAVEL_STORE][code=INVALID_KEY]", 0)
	end
	return value :: string
end

local function maybeFail(data: Data)
	if data.remainingFailures > 0 then
		data.remainingFailures -= 1
		data.failureCount += 1
		error("[ISOLATED_TRAVEL_STORE][code=INJECTED_FAILURE]", 0)
	end
end

local function current(data: Data, key: string): Entry?
	local entry = data.entries[key]
	if entry ~= nil and entry.expiresAt <= data.now then
		data.entries[key] = nil
		return nil
	end
	return entry
end

function Methods:getAsync(keyValue: string): unknown
	local data = dataFor(self)
	maybeFail(data)
	data.readCount += 1
	local entry = current(data, validKey(keyValue))
	return if entry == nil then nil else clone(entry.value)
end

function Methods:updateAsync(keyValue: string, expirationValue: number, transform: (unknown) -> unknown): unknown
	local data = dataFor(self)
	maybeFail(data)
	if data.inUpdate or type(expirationValue) ~= "number" or expirationValue < 1 or type(transform) ~= "function" then
		error("[ISOLATED_TRAVEL_STORE][code=INVALID_UPDATE]", 0)
	end
	local key = validKey(keyValue)
	local entry = current(data, key)
	data.inUpdate = true
	local called, replacement = pcall(transform, if entry == nil then nil else clone(entry.value))
	data.inUpdate = false
	if not called then
		error("[ISOLATED_TRAVEL_STORE][code=TRANSFORM_FAILED]", 0)
	end
	data.updateCount += 1
	if replacement == nil then
		data.entries[key] = nil
		return nil
	end
	data.entries[key] = { value = clone(replacement), expiresAt = data.now + expirationValue }
	return clone(replacement)
end

function Methods:removeAsync(keyValue: string): unknown
	local data = dataFor(self)
	maybeFail(data)
	data.entries[validKey(keyValue)] = nil
	return nil
end

function Methods:seed(keyValue: string, value: unknown, expirationValue: number?)
	local data = dataFor(self)
	local expiration = expirationValue or 2_700
	if type(expiration) ~= "number" or expiration < 1 then
		error("[ISOLATED_TRAVEL_STORE][code=INVALID_EXPIRATION]", 0)
	end
	data.entries[validKey(keyValue)] = { value = clone(value), expiresAt = data.now + expiration }
end

function Methods:read(keyValue: string): unknown
	local entry = current(dataFor(self), validKey(keyValue))
	return if entry == nil then nil else clone(entry.value)
end

function Methods:failNext(countValue: number)
	if type(countValue) ~= "number" or countValue < 0 or countValue % 1 ~= 0 then
		error("[ISOLATED_TRAVEL_STORE][code=INVALID_FAILURE_COUNT]", 0)
	end
	dataFor(self).remainingFailures = countValue
end

function Methods:setNow(nowValue: number)
	if type(nowValue) ~= "number" or nowValue < 0 or nowValue % 1 ~= 0 then
		error("[ISOLATED_TRAVEL_STORE][code=INVALID_TIME]", 0)
	end
	dataFor(self).now = nowValue
end

function Methods:getMetrics(): { keyCount: number, readCount: number, updateCount: number, failureCount: number }
	local data = dataFor(self)
	local count = 0
	for key in data.entries do
		if current(data, key) ~= nil then
			count += 1
		end
	end
	return table.freeze({
		keyCount = count,
		readCount = data.readCount,
		updateCount = data.updateCount,
		failureCount = data.failureCount,
	})
end

function IsolatedTravelRecordStore.new(nowValue: number?): Adapter
	local now = nowValue or 1_700_000_000
	local adapter = setmetatable({}, Methods) :: any
	table.freeze(adapter)
	DATA[adapter] = {
		entries = {},
		now = now,
		remainingFailures = 0,
		readCount = 0,
		updateCount = 0,
		failureCount = 0,
		inUpdate = false,
	}
	return adapter :: Adapter
end

table.freeze(Methods)
return table.freeze(IsolatedTravelRecordStore)
