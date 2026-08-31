--!strict

-- Test-only UpdateAsync adapter. This module is intentionally mapped only into
-- the automated Test build and never opens Roblox DataStoreService.

export type Metrics = {
	keyCount: number,
	updateAttemptCount: number,
	updateSuccessCount: number,
	injectedFailureCount: number,
}

export type Store = {
	updateAsync: (self: Store, key: string, transform: (unknown) -> unknown) -> unknown,
	seed: (self: Store, key: string, value: unknown) -> (),
	read: (self: Store, key: string) -> unknown,
	failNext: (self: Store, count: number) -> (),
	getMetrics: (self: Store) -> Metrics,
}

type StoreData = {
	values: { [string]: unknown },
	keyCount: number,
	maximumKeys: number,
	remainingFailures: number,
	updateAttemptCount: number,
	updateSuccessCount: number,
	injectedFailureCount: number,
	inUpdate: boolean,
}

local DEFAULT_MAXIMUM_KEYS = 100
local MAXIMUM_KEYS = 1_000

local Methods = {}
Methods.__index = Methods

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: StoreData }

local IsolatedProfileStore = {}

local function dataFor(self: Store): StoreData
	local data = DATA[self]
	if data == nil then
		error("[ATD_TEST_PROFILE_STORE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function clone(value: any, ancestors: { [any]: boolean }?): any
	if type(value) ~= "table" then
		return value
	end
	if getmetatable(value) ~= nil then
		error("[ATD_TEST_PROFILE_STORE][code=NON_PLAIN_VALUE]", 0)
	end
	local path = ancestors or {}
	if path[value] then
		error("[ATD_TEST_PROFILE_STORE][code=CYCLIC_VALUE]", 0)
	end
	path[value] = true
	local output = {}
	for key, child in next, value do
		output[clone(key, path)] = clone(child, path)
	end
	path[value] = nil
	return output
end

local function validateKey(key: unknown): string
	if type(key) ~= "string" or #key < 1 or #key > 50 then
		error("[ATD_TEST_PROFILE_STORE][code=INVALID_KEY]", 0)
	end
	return key
end

function Methods.seed(self: Store, keyValue: string, value: unknown)
	local data = dataFor(self)
	local key = validateKey(keyValue)
	if data.inUpdate then
		error("[ATD_TEST_PROFILE_STORE][code=REENTRANT]", 0)
	end
	local existed = rawget(data.values, key) ~= nil
	if value == nil then
		if existed then
			rawset(data.values, key, nil)
			data.keyCount -= 1
		end
		return
	end
	if not existed and data.keyCount >= data.maximumKeys then
		error("[ATD_TEST_PROFILE_STORE][code=CAPACITY]", 0)
	end
	rawset(data.values, key, clone(value))
	if not existed then
		data.keyCount += 1
	end
end

function Methods.read(self: Store, keyValue: string): unknown
	local data = dataFor(self)
	return clone(rawget(data.values, validateKey(keyValue)))
end

function Methods.failNext(self: Store, count: number)
	local data = dataFor(self)
	if type(count) ~= "number" or count % 1 ~= 0 or count < 0 or count > 100 then
		error("[ATD_TEST_PROFILE_STORE][code=INVALID_FAILURE_COUNT]", 0)
	end
	data.remainingFailures = count
end

function Methods.updateAsync(self: Store, keyValue: string, transform: (unknown) -> unknown): unknown
	local data = dataFor(self)
	local key = validateKey(keyValue)
	if type(transform) ~= "function" then
		error("[ATD_TEST_PROFILE_STORE][code=INVALID_TRANSFORM]", 0)
	end
	if data.inUpdate then
		error("[ATD_TEST_PROFILE_STORE][code=REENTRANT]", 0)
	end
	data.updateAttemptCount += 1
	if data.remainingFailures > 0 then
		data.remainingFailures -= 1
		data.injectedFailureCount += 1
		error("[ATD_TEST_PROFILE_STORE][code=INJECTED_FAILURE]", 0)
	end

	data.inUpdate = true
	local succeeded, replacement = pcall(transform, clone(rawget(data.values, key)))
	data.inUpdate = false
	if not succeeded then
		error(replacement, 0)
	end
	if replacement ~= nil then
		local existed = rawget(data.values, key) ~= nil
		if not existed and data.keyCount >= data.maximumKeys then
			error("[ATD_TEST_PROFILE_STORE][code=CAPACITY]", 0)
		end
		rawset(data.values, key, clone(replacement))
		if not existed then
			data.keyCount += 1
		end
	end
	data.updateSuccessCount += 1
	return clone(rawget(data.values, key))
end

function Methods.getMetrics(self: Store): Metrics
	local data = dataFor(self)
	return table.freeze({
		keyCount = data.keyCount,
		updateAttemptCount = data.updateAttemptCount,
		updateSuccessCount = data.updateSuccessCount,
		injectedFailureCount = data.injectedFailureCount,
	})
end

function IsolatedProfileStore.new(maximumKeysValue: number?): Store
	local maximumKeys = maximumKeysValue or DEFAULT_MAXIMUM_KEYS
	if type(maximumKeys) ~= "number" or maximumKeys % 1 ~= 0 or maximumKeys < 1 or maximumKeys > MAXIMUM_KEYS then
		error("[ATD_TEST_PROFILE_STORE][code=INVALID_CAPACITY]", 0)
	end
	local store = setmetatable({}, Methods) :: any
	DATA[store] = {
		values = {},
		keyCount = 0,
		maximumKeys = maximumKeys,
		remainingFailures = 0,
		updateAttemptCount = 0,
		updateSuccessCount = 0,
		injectedFailureCount = 0,
		inUpdate = false,
	}
	table.freeze(store)
	return store :: Store
end

table.freeze(Methods)
return table.freeze(IsolatedProfileStore)
