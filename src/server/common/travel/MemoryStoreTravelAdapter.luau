--!strict

local RunService = game:GetService("RunService")

local PlaceRoles = require(game:GetService("ReplicatedStorage").Shared.config.PlaceRoles)
local Result = require(game:GetService("ReplicatedStorage").Shared.util.Result)
local Validation = require(game:GetService("ReplicatedStorage").Shared.util.Validation)

export type Transform = (unknown) -> unknown
export type Adapter = {
	getAsync: (self: Adapter, key: string) -> unknown,
	updateAsync: (self: Adapter, key: string, expirationSeconds: number, transform: Transform) -> unknown,
	removeAsync: (self: Adapter, key: string) -> unknown,
	getKind: (self: Adapter) -> string,
}

export type ErrorCode =
	"INVALID_DEPLOYMENT"
	| "STUDIO_FORBIDDEN"
	| "STUDIO_REQUIRED"
	| "MEMORY_STORE_UNAVAILABLE"
	| "INVALID_CLOCK"
export type AdapterError = { code: ErrorCode }

export type PublishedNamespace = {
	deployment: PlaceRoles.Deployment,
	mapName: string,
}

type StudioEntry = { value: unknown, expiresAt: number }

local PRODUCTION_MAP_NAME = "ATD_Travel_Prod_v1"
local STAGING_MAP_NAME = "ATD_Travel_Staging_v1"
local MAX_KEY_BYTES = 128
local MAX_EXPIRATION_SECONDS = 2_700
local MAX_STUDIO_KEYS = 512
local MAX_PRODUCTION_ATTEMPTS = 3
local MAX_PRODUCTION_BACKOFF_SECONDS = 0.5

local PUBLISHED_NAMESPACES: { [string]: PublishedNamespace } = table.freeze({
	[PlaceRoles.PRODUCTION_DEPLOYMENT] = table.freeze({
		deployment = PlaceRoles.PRODUCTION_DEPLOYMENT,
		mapName = PRODUCTION_MAP_NAME,
	}),
	[PlaceRoles.STAGING_DEPLOYMENT] = table.freeze({
		deployment = PlaceRoles.STAGING_DEPLOYMENT,
		mapName = STAGING_MAP_NAME,
	}),
})

local MemoryStoreTravelAdapter = {
	PRODUCTION_MAP_NAME = PRODUCTION_MAP_NAME,
	STAGING_MAP_NAME = STAGING_MAP_NAME,
	MAX_EXPIRATION_SECONDS = MAX_EXPIRATION_SECONDS,
}

local function failure(code: ErrorCode): Result.Failure<AdapterError>
	return Result.err(table.freeze({ code = code }))
end

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

local function validateKey(key: unknown): string
	if type(key) ~= "string" or #key < 1 or #key > MAX_KEY_BYTES then
		error("[ATD_MEMORY_TRAVEL_ADAPTER][code=INVALID_KEY]", 0)
	end
	return key :: string
end

local function validateExpiration(value: unknown): number
	if
		type(value) ~= "number"
		or not Validation.isSafeInteger(value :: number)
		or value < 1
		or value > MAX_EXPIRATION_SECONDS
	then
		error("[ATD_MEMORY_TRAVEL_ADAPTER][code=INVALID_EXPIRATION]", 0)
	end
	return value :: number
end

local function productionCall(callback: () -> unknown): unknown
	for attempt = 1, MAX_PRODUCTION_ATTEMPTS do
		local called, value = pcall(callback)
		if called then
			return value
		end
		if attempt < MAX_PRODUCTION_ATTEMPTS then
			task.wait(math.min(0.1 * (2 ^ (attempt - 1)), MAX_PRODUCTION_BACKOFF_SECONDS))
		end
	end
	error("[ATD_MEMORY_TRAVEL_ADAPTER][code=MEMORY_STORE_UNAVAILABLE]", 0)
end

function MemoryStoreTravelAdapter.resolvePublishedNamespace(
	deploymentValue: unknown
): Result.Result<PublishedNamespace, AdapterError>
	if type(deploymentValue) ~= "string" then
		return failure("INVALID_DEPLOYMENT")
	end
	local namespace = PUBLISHED_NAMESPACES[deploymentValue]
	if namespace == nil then
		return failure("INVALID_DEPLOYMENT")
	end
	return Result.ok(namespace)
end

function MemoryStoreTravelAdapter.newPublished(deploymentValue: unknown): Result.Result<Adapter, AdapterError>
	local namespaceResult = MemoryStoreTravelAdapter.resolvePublishedNamespace(deploymentValue)
	if not namespaceResult.ok then
		return failure(namespaceResult.error.code)
	end
	if RunService:IsStudio() then
		return failure("STUDIO_FORBIDDEN")
	end
	local namespace = namespaceResult.value
	local loaded, memoryStoreService = pcall(function()
		return game:GetService("MemoryStoreService")
	end)
	if not loaded then
		return failure("MEMORY_STORE_UNAVAILABLE")
	end
	local mapped, hashMap = pcall(function()
		return (memoryStoreService :: MemoryStoreService):GetHashMap(namespace.mapName)
	end)
	if not mapped then
		return failure("MEMORY_STORE_UNAVAILABLE")
	end
	local adapter = {} :: any
	function adapter:getAsync(keyValue: string): unknown
		local key = validateKey(keyValue)
		return productionCall(function()
			return (hashMap :: MemoryStoreHashMap):GetAsync(key)
		end)
	end
	function adapter:updateAsync(keyValue: string, expirationValue: number, transform: Transform): unknown
		if type(transform) ~= "function" then
			error("[ATD_MEMORY_TRAVEL_ADAPTER][code=INVALID_TRANSFORM]", 0)
		end
		local key = validateKey(keyValue)
		local expiration = validateExpiration(expirationValue)
		return productionCall(function()
			return (hashMap :: MemoryStoreHashMap):UpdateAsync(key, transform, expiration)
		end)
	end
	function adapter:removeAsync(keyValue: string): unknown
		local key = validateKey(keyValue)
		return productionCall(function()
			return (hashMap :: MemoryStoreHashMap):RemoveAsync(key)
		end)
	end
	function adapter:getKind(): string
		return if namespace.deployment == PlaceRoles.PRODUCTION_DEPLOYMENT
			then "ProductionMemoryStore"
			else "StagingMemoryStore"
	end
	return Result.ok(table.freeze(adapter) :: Adapter)
end

function MemoryStoreTravelAdapter.newStudioDevelopment(
	clockValue: (() -> unknown)?
): Result.Result<Adapter, AdapterError>
	if not RunService:IsStudio() then
		return failure("STUDIO_REQUIRED")
	end
	if clockValue ~= nil and type(clockValue) ~= "function" then
		return failure("INVALID_CLOCK")
	end
	local clock = clockValue or os.time
	local entries: { [string]: StudioEntry } = {}
	local keyCount = 0
	local function currentTime(): number
		local value = clock()
		if type(value) ~= "number" or not Validation.isSafeInteger(value :: number) or value < 0 then
			error("[ATD_MEMORY_TRAVEL_ADAPTER][code=INVALID_CLOCK]", 0)
		end
		return value :: number
	end
	local function currentEntry(key: string): StudioEntry?
		local entry = entries[key]
		if entry ~= nil and entry.expiresAt <= currentTime() then
			entries[key] = nil
			keyCount -= 1
			return nil
		end
		return entry
	end
	local adapter = {} :: any
	function adapter:getAsync(keyValue: string): unknown
		local entry = currentEntry(validateKey(keyValue))
		return if entry == nil then nil else clone(entry.value)
	end
	function adapter:updateAsync(keyValue: string, expirationValue: number, transform: Transform): unknown
		local key = validateKey(keyValue)
		local expiration = validateExpiration(expirationValue)
		if type(transform) ~= "function" then
			error("[ATD_MEMORY_TRAVEL_ADAPTER][code=INVALID_TRANSFORM]", 0)
		end
		local entry = currentEntry(key)
		local replacement = transform(if entry == nil then nil else clone(entry.value))
		if replacement == nil then
			-- Match MemoryStoreHashMap.UpdateAsync: nil aborts the write and
			-- preserves the current value. Removal is an explicit RemoveAsync.
			return if entry == nil then nil else clone(entry.value)
		end
		if entry == nil then
			if keyCount >= MAX_STUDIO_KEYS then
				error("[ATD_MEMORY_TRAVEL_ADAPTER][code=CAPACITY_EXCEEDED]", 0)
			end
			keyCount += 1
		end
		entries[key] = { value = clone(replacement), expiresAt = currentTime() + expiration }
		return clone(replacement)
	end
	function adapter:removeAsync(keyValue: string): unknown
		local key = validateKey(keyValue)
		local entry = currentEntry(key)
		if entry ~= nil then
			entries[key] = nil
			keyCount -= 1
		end
		return nil
	end
	function adapter:getKind(): string
		return "StudioDevelopmentMemory"
	end
	return Result.ok(table.freeze(adapter) :: Adapter)
end

return table.freeze(MemoryStoreTravelAdapter)
