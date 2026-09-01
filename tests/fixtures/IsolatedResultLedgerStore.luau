--!strict

-- Test-only result ledger adapter. It never opens DataStoreService and clones
-- every value so tests exercise the same detached-record assumptions as a
-- production persistence boundary.

export type Store = {
	read: (self: Store, key: string) -> unknown,
	update: (self: Store, key: string, transform: (unknown) -> unknown) -> unknown,
	failNext: (self: Store, count: number) -> (),
	getMetrics: (self: Store) -> { reads: number, updates: number, failures: number, keys: number },
}

type StoreData = {
	values: { [string]: unknown },
	remainingFailures: number,
	reads: number,
	updates: number,
	failures: number,
	inUpdate: boolean,
}

local Methods = {}
Methods.__index = Methods

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: StoreData }

local IsolatedResultLedgerStore = {}

local function dataFor(self: Store): StoreData
	local data = DATA[self]
	if data == nil then
		error("[ATD_TEST_RESULT_STORE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function clone(value: any, seen: { [any]: boolean }?): any
	if type(value) ~= "table" then
		return value
	end
	if getmetatable(value) ~= nil then
		-- Canonical production records are frozen; detach them as ordinary store data.
		local output = {}
		for key, child in value do
			output[clone(key, seen)] = clone(child, seen)
		end
		return output
	end
	local ancestors = seen or {}
	if ancestors[value] then
		error("[ATD_TEST_RESULT_STORE][code=CYCLIC_VALUE]", 0)
	end
	ancestors[value] = true
	local output = {}
	for key, child in value do
		output[clone(key, ancestors)] = clone(child, ancestors)
	end
	ancestors[value] = nil
	return output
end

local function validateKey(value: unknown): string
	if type(value) ~= "string" or #value < 1 or #value > 128 then
		error("[ATD_TEST_RESULT_STORE][code=INVALID_KEY]", 0)
	end
	return value
end

local function maybeFail(data: StoreData)
	if data.remainingFailures > 0 then
		data.remainingFailures -= 1
		data.failures += 1
		error("[ATD_TEST_RESULT_STORE][code=INJECTED_FAILURE]", 0)
	end
end

function Methods.read(self: Store, keyValue: string): unknown
	local data = dataFor(self)
	maybeFail(data)
	data.reads += 1
	return clone(data.values[validateKey(keyValue)])
end

function Methods.update(self: Store, keyValue: string, transform: (unknown) -> unknown): unknown
	local data = dataFor(self)
	local key = validateKey(keyValue)
	if type(transform) ~= "function" or data.inUpdate then
		error("[ATD_TEST_RESULT_STORE][code=INVALID_UPDATE]", 0)
	end
	maybeFail(data)
	data.updates += 1
	data.inUpdate = true
	local called, replacement = pcall(transform, clone(data.values[key]))
	data.inUpdate = false
	if not called then
		error(replacement, 0)
	end
	if replacement ~= nil then
		data.values[key] = clone(replacement)
	end
	return clone(data.values[key])
end

function Methods.failNext(self: Store, count: number)
	local data = dataFor(self)
	if type(count) ~= "number" or count % 1 ~= 0 or count < 0 or count > 20 then
		error("[ATD_TEST_RESULT_STORE][code=INVALID_FAILURE_COUNT]", 0)
	end
	data.remainingFailures = count
end

function Methods.getMetrics(self: Store)
	local data = dataFor(self)
	local keys = 0
	for _ in data.values do
		keys += 1
	end
	return table.freeze({ reads = data.reads, updates = data.updates, failures = data.failures, keys = keys })
end

function IsolatedResultLedgerStore.new(): Store
	local store = setmetatable({}, Methods) :: any
	DATA[store] = {
		values = {},
		remainingFailures = 0,
		reads = 0,
		updates = 0,
		failures = 0,
		inUpdate = false,
	}
	table.freeze(store)
	return store :: Store
end

return table.freeze(IsolatedResultLedgerStore)
