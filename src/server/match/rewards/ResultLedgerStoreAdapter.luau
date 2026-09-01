--!strict

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Result = require(ReplicatedStorage.Shared.util.Result)

export type Adapter = {
	read: (self: Adapter, key: string) -> unknown,
	update: (self: Adapter, key: string, transform: (unknown) -> unknown) -> unknown,
}

local STORE_NAME = "ATDMatchResultLedgerV1"
local MAX_ATTEMPTS = 3
local MAX_BACKOFF_SECONDS = 0.5

local ResultLedgerStoreAdapter = {}

local function retry(callback: () -> unknown): unknown
	for attempt = 1, MAX_ATTEMPTS do
		local called, value = pcall(callback)
		if called then
			return value
		end
		if attempt < MAX_ATTEMPTS then
			task.wait(math.min(0.1 * (2 ^ (attempt - 1)), MAX_BACKOFF_SECONDS))
		end
	end
	error("[ATD_RESULT_LEDGER_ADAPTER][code=STORE_UNAVAILABLE]", 0)
end

function ResultLedgerStoreAdapter.newProduction(): Result.Result<Adapter, string>
	if RunService:IsStudio() then
		return Result.err("PRODUCTION_ADAPTER_FORBIDDEN_IN_STUDIO")
	end
	local dataStoreService = game:GetService("DataStoreService")
	local opened, store = pcall(dataStoreService.GetDataStore, dataStoreService, STORE_NAME)
	if not opened or store == nil then
		return Result.err("STORE_UNAVAILABLE")
	end
	local adapter: Adapter = table.freeze({
		read = function(_self, key)
			return retry(function()
				return (store :: GlobalDataStore):GetAsync(key)
			end)
		end,
		update = function(_self, key, transform)
			return retry(function()
				return (store :: GlobalDataStore):UpdateAsync(key, transform)
			end)
		end,
	})
	return Result.ok(adapter)
end

function ResultLedgerStoreAdapter.newStudioDevelopment(): Result.Result<Adapter, string>
	if not RunService:IsStudio() then
		return Result.err("STUDIO_ADAPTER_FORBIDDEN")
	end
	local records: { [string]: unknown } = {}
	local adapter: Adapter = table.freeze({
		read = function(_self, key)
			return records[key]
		end,
		update = function(_self, key, transform)
			local replacement = transform(records[key])
			if replacement ~= nil then
				records[key] = replacement
			end
			return records[key]
		end,
	})
	return Result.ok(adapter)
end

return table.freeze(ResultLedgerStoreAdapter)
