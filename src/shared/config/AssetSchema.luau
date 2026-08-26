--!strict

local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

local ASSET_KINDS: { [string]: boolean } = table.freeze({
	EnemyModel = true,
	Icon = true,
	MapModel = true,
	TowerModel = true,
})

local ASSET_FIELDS: { [string]: boolean } = table.freeze({
	key = true,
	kind = true,
})

local NO_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({})

local validatedManifests: { [ConfigTypes.AssetManifest]: boolean } = setmetatable({}, {
	__mode = "k",
}) :: any

local AssetSchema = {}

function AssetSchema.validateManifest(value: unknown): Result.Result<ConfigTypes.AssetManifest, Validation.Issue>
	local root = { "Assets" }
	local rawEntries, arrayIssue = Validation.readArray(value, root, Validation.MAX_ASSET_ENTRIES)
	if arrayIssue ~= nil then
		return Result.err(arrayIssue)
	end

	local ordered: { ConfigTypes.AssetDefinition } = {}
	local byKey: { [ConfigTypes.AssetKey]: ConfigTypes.AssetDefinition } = {}
	local firstPaths: { [string]: string } = {}

	for index = 1, #(rawEntries :: { unknown }) do
		local rawEntry = (rawEntries :: { unknown })[index]
		local entryPath = Validation.appendPath(root, index)
		local record, recordIssue = Validation.readObject(rawEntry, entryPath, ASSET_FIELDS, NO_RUNTIME_FIELDS)
		if recordIssue ~= nil then
			return Result.err(recordIssue)
		end

		local rawKey, keyIssue = Validation.getRequiredField(record :: Validation.RawObject, "key", entryPath)
		if keyIssue ~= nil then
			return Result.err(keyIssue)
		end
		local keyPath = Validation.appendPath(entryPath, "key")
		if type(rawKey) ~= "string" then
			return Result.err(Validation.issueWithType("INVALID_TYPE", keyPath, "Asset key must be a string", rawKey))
		end
		if not Validation.isSymbolicKey(rawKey) then
			return Result.err(
				Validation.issue("INVALID_ASSET_KEY", keyPath, "Asset key does not use the canonical symbolic grammar")
			)
		end

		local firstPath = firstPaths[rawKey]
		if firstPath ~= nil then
			return Result.err(
				Validation.issueWithRelated(
					"DUPLICATE_ASSET_KEY",
					keyPath,
					"Asset key duplicates an earlier manifest entry",
					firstPath
				)
			)
		end
		firstPaths[rawKey] = Validation.renderPath(keyPath)

		local rawKind, kindIssue = Validation.getRequiredField(record :: Validation.RawObject, "kind", entryPath)
		if kindIssue ~= nil then
			return Result.err(kindIssue)
		end
		local kindPath = Validation.appendPath(entryPath, "kind")
		if type(rawKind) ~= "string" then
			return Result.err(
				Validation.issueWithType("INVALID_TYPE", kindPath, "Asset kind must be a string", rawKind)
			)
		end
		if ASSET_KINDS[rawKind] ~= true then
			return Result.err(Validation.issue("INVALID_ENUM", kindPath, "Asset kind is not recognized"))
		end

		local canonicalEntry: ConfigTypes.AssetDefinition = table.freeze({
			key = rawKey,
			kind = rawKind :: ConfigTypes.AssetKind,
		})
		table.insert(ordered, canonicalEntry)
		byKey[rawKey] = canonicalEntry
	end

	local manifest: ConfigTypes.AssetManifest = table.freeze({
		ordered = table.freeze(ordered),
		byKey = table.freeze(byKey),
	})
	validatedManifests[manifest] = true
	return Result.ok(manifest)
end

function AssetSchema.isValidatedManifest(value: unknown): boolean
	return type(value) == "table" and validatedManifests[value :: any] == true
end

return table.freeze(AssetSchema)
