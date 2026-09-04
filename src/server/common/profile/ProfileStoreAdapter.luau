--!strict

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local PlaceRoles = require(game:GetService("ReplicatedStorage").Shared.config.PlaceRoles)
local Result = require(game:GetService("ReplicatedStorage").Shared.util.Result)

export type Transform = (currentValue: unknown) -> unknown

export type AdapterKind = "ProductionDataStore" | "StagingDataStore" | "StudioDevelopmentMemory"

export type Adapter = {
	updateAsync: (self: Adapter, key: string, transform: Transform) -> unknown,
	getKind: (self: Adapter) -> AdapterKind,
}

export type ErrorCode = "INVALID_DEPLOYMENT" | "STUDIO_FORBIDDEN" | "STUDIO_REQUIRED" | "DATASTORE_UNAVAILABLE"
export type AdapterError = {
	code: ErrorCode,
	message: string,
}

export type PublishedNamespace = {
	deployment: PlaceRoles.Deployment,
	storeName: string,
	scope: string,
}

local PRODUCTION_STORE_NAME = "ATD_Profile_Prod_v1"
local PRODUCTION_SCOPE = "profiles"
local STAGING_STORE_NAME = "ATD_Profile_Staging_v1"
local STAGING_SCOPE = "profiles_staging"
local STUDIO_SCOPE_NAME = "ATD_Profile_Studio_Development_Ephemeral"
local MAX_STUDIO_KEYS = 100

local PUBLISHED_NAMESPACES: { [string]: PublishedNamespace } = table.freeze({
	[PlaceRoles.PRODUCTION_DEPLOYMENT] = table.freeze({
		deployment = PlaceRoles.PRODUCTION_DEPLOYMENT,
		storeName = PRODUCTION_STORE_NAME,
		scope = PRODUCTION_SCOPE,
	}),
	[PlaceRoles.STAGING_DEPLOYMENT] = table.freeze({
		deployment = PlaceRoles.STAGING_DEPLOYMENT,
		storeName = STAGING_STORE_NAME,
		scope = STAGING_SCOPE,
	}),
})

local ProfileStoreAdapter = {
	PRODUCTION_STORE_NAME = PRODUCTION_STORE_NAME,
	PRODUCTION_SCOPE = PRODUCTION_SCOPE,
	STAGING_STORE_NAME = STAGING_STORE_NAME,
	STAGING_SCOPE = STAGING_SCOPE,
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

function ProfileStoreAdapter.resolvePublishedNamespace(
	deploymentValue: unknown
): Result.Result<PublishedNamespace, AdapterError>
	if type(deploymentValue) ~= "string" then
		return errorResult("INVALID_DEPLOYMENT", "Published profile storage requires an explicit deployment")
	end
	local namespace = PUBLISHED_NAMESPACES[deploymentValue]
	if namespace == nil then
		return errorResult("INVALID_DEPLOYMENT", "Published profile storage requires Production or Staging")
	end
	return Result.ok(namespace)
end

function ProfileStoreAdapter.newPublished(deploymentValue: unknown): Result.Result<Adapter, AdapterError>
	local namespaceResult = ProfileStoreAdapter.resolvePublishedNamespace(deploymentValue)
	if not namespaceResult.ok then
		return errorResult(namespaceResult.error.code, namespaceResult.error.message)
	end
	if RunService:IsStudio() then
		return errorResult("STUDIO_FORBIDDEN", "Published profile DataStore access is disabled in Studio")
	end
	local namespace = namespaceResult.value
	local opened, storeValue = pcall(function()
		return DataStoreService:GetDataStore(namespace.storeName, namespace.scope)
	end)
	if not opened or storeValue == nil then
		return errorResult("DATASTORE_UNAVAILABLE", "Published profile DataStore could not be opened")
	end
	local store = storeValue :: GlobalDataStore
	local kind: AdapterKind = if namespace.deployment == PlaceRoles.PRODUCTION_DEPLOYMENT
		then "ProductionDataStore"
		else "StagingDataStore"
	local adapter = {} :: any
	function adapter:updateAsync(key: string, transform: Transform): unknown
		return store:UpdateAsync(key, transform)
	end
	function adapter:getKind(): AdapterKind
		return kind
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
	function adapter:getKind(): AdapterKind
		return "StudioDevelopmentMemory"
	end
	return Result.ok(table.freeze(adapter) :: Adapter)
end

return table.freeze(ProfileStoreAdapter)
