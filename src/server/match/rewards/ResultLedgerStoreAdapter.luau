--!strict

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local Result = require(ReplicatedStorage.Shared.util.Result)

export type Adapter = {
	read: (self: Adapter, key: string) -> unknown,
	update: (self: Adapter, key: string, transform: (unknown) -> unknown) -> unknown,
}

export type ErrorCode =
	"INVALID_DEPLOYMENT"
	| "PUBLISHED_ADAPTER_FORBIDDEN_IN_STUDIO"
	| "STORE_UNAVAILABLE"
	| "STUDIO_ADAPTER_FORBIDDEN"

export type PublishedNamespace = {
	deployment: PlaceRoles.Deployment,
	storeName: string,
}

local PRODUCTION_STORE_NAME = "ATDMatchResultLedgerV1"
local STAGING_STORE_NAME = "ATD_MatchResultLedger_Staging_v1"
local MAX_ATTEMPTS = 3
local MAX_BACKOFF_SECONDS = 0.5

local PUBLISHED_NAMESPACES: { [string]: PublishedNamespace } = table.freeze({
	[PlaceRoles.PRODUCTION_DEPLOYMENT] = table.freeze({
		deployment = PlaceRoles.PRODUCTION_DEPLOYMENT,
		storeName = PRODUCTION_STORE_NAME,
	}),
	[PlaceRoles.STAGING_DEPLOYMENT] = table.freeze({
		deployment = PlaceRoles.STAGING_DEPLOYMENT,
		storeName = STAGING_STORE_NAME,
	}),
})

local ResultLedgerStoreAdapter = {
	PRODUCTION_STORE_NAME = PRODUCTION_STORE_NAME,
	STAGING_STORE_NAME = STAGING_STORE_NAME,
}

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

function ResultLedgerStoreAdapter.resolvePublishedNamespace(
	deploymentValue: unknown
): Result.Result<PublishedNamespace, ErrorCode>
	if type(deploymentValue) ~= "string" then
		return Result.err("INVALID_DEPLOYMENT")
	end
	local namespace = PUBLISHED_NAMESPACES[deploymentValue]
	if namespace == nil then
		return Result.err("INVALID_DEPLOYMENT")
	end
	return Result.ok(namespace)
end

function ResultLedgerStoreAdapter.newPublished(deploymentValue: unknown): Result.Result<Adapter, ErrorCode>
	local namespaceResult = ResultLedgerStoreAdapter.resolvePublishedNamespace(deploymentValue)
	if not namespaceResult.ok then
		return Result.err(namespaceResult.error)
	end
	if RunService:IsStudio() then
		return Result.err("PUBLISHED_ADAPTER_FORBIDDEN_IN_STUDIO")
	end
	local namespace = namespaceResult.value
	local dataStoreService = game:GetService("DataStoreService")
	local opened, store = pcall(dataStoreService.GetDataStore, dataStoreService, namespace.storeName)
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

function ResultLedgerStoreAdapter.newStudioDevelopment(): Result.Result<Adapter, ErrorCode>
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
