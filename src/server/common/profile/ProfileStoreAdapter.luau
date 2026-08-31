--!strict

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Result = require(game:GetService("ReplicatedStorage").Shared.util.Result)

export type Transform = (currentValue: unknown) -> unknown

export type Adapter = {
	updateAsync: (self: Adapter, key: string, transform: Transform) -> unknown,
	getKind: (self: Adapter) -> "ProductionDataStore" | "StudioDevelopmentMemory",
}

export type ErrorCode = "STUDIO_FORBIDDEN" | "STUDIO_REQUIRED" | "DATASTORE_UNAVAILABLE"
export type AdapterError = {
	code: ErrorCode,
	message: string,
}

local PRODUCTION_STORE_NAME = "ATD_Profile_Prod_v1"
local PRODUCTION_SCOPE = "profiles"
local STUDIO_SCOPE_NAME = "ATD_Profile_Studio_Development_Ephemeral"
local MAX_STUDIO_KEYS = 100

local ProfileStoreAdapter = {
	PRODUCTION_STORE_NAME = PRODUCTION_STORE_NAME,
	PRODUCTION_SCOPE = PRODUCTION_SCOPE,
	STUDIO_SCOPE_NAME = STUDIO_SCOPE_NAME,
	MAX_STUDIO_KEYS = MAX_STUDIO_KEYS,
}

local function errorResult(code: ErrorCode, message: string): Result.Failure<AdapterError>
	return Result.err(table.freeze({
		code = code,
		message = message,
	}))
end

local function clone(value: any, seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end
	local memo = seen or {}
	if memo[value] ~= nil then
		error("[ATD_PROFILE_STORE][code=CYCLIC_VALUE]", 0)
	end
	local output = {}
	local nextMemo = table.clone(memo)
	nextMemo[value] = output
	for key, child in next, value do
		output[clone(key, nextMemo)] = clone(child, nextMemo)
	end
	return output
end

function ProfileStoreAdapter.newProduction(): Result.Result<Adapter, AdapterError>
	if RunService:IsStudio() then
		return errorResult("STUDIO_FORBIDDEN", "Production profile DataStore access is disabled in Studio")
	end
	local opened, storeValue = pcall(function()
		return DataStoreService:GetDataStore(PRODUCTION_STORE_NAME, PRODUCTION_SCOPE)
	end)
	if not opened or storeValue == nil then
		return errorResult("DATASTORE_UNAVAILABLE", "Production profile DataStore could not be opened")
	end
	local store = storeValue :: GlobalDataStore
	local adapter = {} :: any
	function adapter:updateAsync(key: string, transform: Transform): unknown
		return store:UpdateAsync(key, transform)
	end
	function adapter:getKind(): "ProductionDataStore"
		return "ProductionDataStore"
	end
	return Result.ok(table.freeze(adapter) :: Adapter)
end

function ProfileStoreAdapter.newStudioDevelopment(): Result.Result<Adapter, AdapterError>
	if not RunService:IsStudio() then
		return errorResult("STUDIO_REQUIRED", "The ephemeral development profile store is available only in Studio")
	end
	local values: { [string]: unknown } = {}
	local keyCount = 0
	local adapter = {} :: any
	function adapter:updateAsync(key: string, transform: Transform): unknown
		if type(key) ~= "string" or #key < 1 or #key > 50 or type(transform) ~= "function" then
			error("[ATD_PROFILE_STORE][code=INVALID_UPDATE]", 0)
		end
		local existed = rawget(values, key) ~= nil
		if not existed and keyCount >= MAX_STUDIO_KEYS then
			error("[ATD_PROFILE_STORE][code=STUDIO_CAPACITY]", 0)
		end
		local replacement = transform(clone(rawget(values, key)))
		if replacement ~= nil then
			rawset(values, key, clone(replacement))
			if not existed then
				keyCount += 1
			end
		end
		return clone(rawget(values, key))
	end
	function adapter:getKind(): "StudioDevelopmentMemory"
		return "StudioDevelopmentMemory"
	end
	return Result.ok(table.freeze(adapter) :: Adapter)
end

return table.freeze(ProfileStoreAdapter)
