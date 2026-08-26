--!strict

local AssetSchema = require(script.Parent.AssetSchema)
local DifficultySchema = require(script.Parent.DifficultySchema)
local SchemaPrimitives = require(script.Parent.SchemaPrimitives)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

local ROOT_PATH: { Validation.PathSegment } = { "Maps" }

local MAP_FIELDS: { [string]: boolean } = table.freeze({
	description = true,
	displayName = true,
	iconAssetKey = true,
	id = true,
	lanes = true,
	modelAssetKey = true,
	supportedDifficultyIds = true,
	tags = true,
})

local MAP_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	baseInstance = true,
	cleanup = true,
	instance = true,
	loadedModel = true,
	placementZones = true,
	runtimeMapId = true,
	worldBounds = true,
})

local LANE_FIELDS: { [string]: boolean } = table.freeze({
	id = true,
})

local LANE_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	base = true,
	distance = true,
	instance = true,
	nodes = true,
	pathLength = true,
	spawn = true,
	waypoints = true,
})

local validatedCatalogs: { [ConfigTypes.MapCatalog]: boolean } = setmetatable({}, {
	__mode = "k",
}) :: any

local MapSchema = {}

local function dependencyIssue(pathName: string, message: string): Validation.Issue
	return Validation.issue("INVALID_REFERENCE", { pathName }, message)
end

local function validateLanes(
	value: unknown,
	path: { Validation.PathSegment }
): ({ ConfigTypes.MapLaneDefinition }?, Validation.Issue?)
	local rawLanes, arrayIssue = Validation.readArray(value, path, Validation.MAX_MAP_LANES)
	if arrayIssue ~= nil then
		return nil, arrayIssue
	end
	if #(rawLanes :: { unknown }) == 0 then
		return nil, Validation.issue("EMPTY_COLLECTION", path, "Map must declare at least one lane")
	end

	local lanes: { ConfigTypes.MapLaneDefinition } = {}
	local firstPaths: { [string]: string } = {}
	for index = 1, #(rawLanes :: { unknown }) do
		local lanePath = Validation.appendPath(path, index)
		local record, recordIssue =
			Validation.readObject((rawLanes :: { unknown })[index], lanePath, LANE_FIELDS, LANE_RUNTIME_FIELDS)
		if recordIssue ~= nil then
			return nil, recordIssue
		end

		local id, idIssue = SchemaPrimitives.requiredSymbolicKey(record :: Validation.RawObject, "id", lanePath)
		if idIssue ~= nil then
			return nil, idIssue
		end
		local idPath = Validation.appendPath(lanePath, "id")
		local firstPath = firstPaths[id :: string]
		if firstPath ~= nil then
			return nil,
				Validation.issueWithRelated(
					"DUPLICATE_VALUE",
					idPath,
					"Lane ID duplicates an earlier lane in this map",
					firstPath
				)
		end
		firstPaths[id :: string] = Validation.renderPath(idPath)

		local lane: ConfigTypes.MapLaneDefinition = table.freeze({
			id = id :: ConfigTypes.FeatureKey,
		})
		table.insert(lanes, lane)
	end

	return table.freeze(lanes), nil
end

local function validateSupportedDifficulties(
	value: unknown,
	path: { Validation.PathSegment },
	difficulties: ConfigTypes.DifficultyCatalog
): ({ Ids.DifficultyId }?, Validation.Issue?)
	local rawIds, arrayIssue = Validation.readArray(value, path, Validation.MAX_LIST_ENTRIES)
	if arrayIssue ~= nil then
		return nil, arrayIssue
	end
	if #(rawIds :: { unknown }) == 0 then
		return nil, Validation.issue("EMPTY_COLLECTION", path, "Map must support at least one difficulty")
	end

	local ids: { Ids.DifficultyId } = {}
	local firstPaths: { [string]: string } = {}
	local byId = rawget(difficulties :: any, "byId")
	for index = 1, #(rawIds :: { unknown }) do
		local idPath = Validation.appendPath(path, index)
		local idResult = Ids.validateDifficultyId((rawIds :: { unknown })[index])
		if not idResult.ok then
			return nil,
				Validation.issueWithCause(
					"INVALID_ID",
					idPath,
					"Supported difficulty ID is invalid",
					idResult.error.code
				)
		end
		local id = idResult.value
		if rawget(byId, id) == nil then
			return nil,
				Validation.issue("INVALID_REFERENCE", idPath, "Supported difficulty is not present in the catalog")
		end

		local firstPath = firstPaths[id]
		if firstPath ~= nil then
			return nil,
				Validation.issueWithRelated(
					"DUPLICATE_VALUE",
					idPath,
					"Supported difficulty duplicates an earlier list entry",
					firstPath
				)
		end
		firstPaths[id] = Validation.renderPath(idPath)
		table.insert(ids, id)
	end

	return table.freeze(ids), nil
end

local function validateDefinitionAt(
	value: unknown,
	path: { Validation.PathSegment },
	manifest: ConfigTypes.AssetManifest,
	difficulties: ConfigTypes.DifficultyCatalog,
	firstIdPaths: { [string]: string }?
): (ConfigTypes.MapDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, MAP_FIELDS, MAP_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawId, idMissing = Validation.getRequiredField(record :: Validation.RawObject, "id", path)
	if idMissing ~= nil then
		return nil, idMissing
	end
	local idPath = Validation.appendPath(path, "id")
	local idResult = Ids.validateMapId(rawId)
	if not idResult.ok then
		return nil, Validation.issueWithCause("INVALID_ID", idPath, "Map ID is invalid", idResult.error.code)
	end
	local id = idResult.value
	if firstIdPaths ~= nil then
		local firstPath = firstIdPaths[id]
		if firstPath ~= nil then
			return nil,
				Validation.issueWithRelated(
					"DUPLICATE_ID",
					idPath,
					"Map ID duplicates an earlier catalog entry",
					firstPath
				)
		end
		firstIdPaths[id] = Validation.renderPath(idPath)
	end

	local displayName, displayNameIssue = SchemaPrimitives.requiredText(
		record :: Validation.RawObject,
		"displayName",
		path,
		Validation.MAX_NAME_CHARACTERS
	)
	if displayNameIssue ~= nil then
		return nil, displayNameIssue
	end
	local description, descriptionIssue = SchemaPrimitives.optionalText(
		record :: Validation.RawObject,
		"description",
		path,
		Validation.MAX_DESCRIPTION_CHARACTERS
	)
	if descriptionIssue ~= nil then
		return nil, descriptionIssue
	end

	local modelAssetKey, modelIssue =
		SchemaPrimitives.assetKey(record :: Validation.RawObject, "modelAssetKey", path, manifest, "MapModel", true)
	if modelIssue ~= nil then
		return nil, modelIssue
	end
	local iconAssetKey, iconIssue =
		SchemaPrimitives.assetKey(record :: Validation.RawObject, "iconAssetKey", path, manifest, "Icon", false)
	if iconIssue ~= nil then
		return nil, iconIssue
	end

	local rawLanes, lanesMissing = Validation.getRequiredField(record :: Validation.RawObject, "lanes", path)
	if lanesMissing ~= nil then
		return nil, lanesMissing
	end
	local lanes, lanesIssue = validateLanes(rawLanes, Validation.appendPath(path, "lanes"))
	if lanesIssue ~= nil then
		return nil, lanesIssue
	end

	local rawDifficultyIds, difficultiesMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "supportedDifficultyIds", path)
	if difficultiesMissing ~= nil then
		return nil, difficultiesMissing
	end
	local supportedDifficultyIds, difficultiesIssue = validateSupportedDifficulties(
		rawDifficultyIds,
		Validation.appendPath(path, "supportedDifficultyIds"),
		difficulties
	)
	if difficultiesIssue ~= nil then
		return nil, difficultiesIssue
	end

	local tags, tagsIssue = SchemaPrimitives.optionalTags(record :: Validation.RawObject, path)
	if tagsIssue ~= nil then
		return nil, tagsIssue
	end

	local definition: ConfigTypes.MapDefinition = table.freeze({
		id = id,
		displayName = displayName :: string,
		description = description,
		modelAssetKey = modelAssetKey :: ConfigTypes.AssetKey,
		iconAssetKey = iconAssetKey,
		lanes = lanes :: { ConfigTypes.MapLaneDefinition },
		supportedDifficultyIds = supportedDifficultyIds :: { Ids.DifficultyId },
		tags = tags,
	})
	return definition, nil
end

function MapSchema.validateDefinition(
	value: unknown,
	manifest: ConfigTypes.AssetManifest,
	difficulties: ConfigTypes.DifficultyCatalog
): Result.Result<ConfigTypes.MapDefinition, Validation.Issue>
	if not AssetSchema.isValidatedManifest(manifest) then
		return Result.err(dependencyIssue("AssetManifest", "Expected a manifest validated by AssetSchema"))
	end
	if not DifficultySchema.isValidatedCatalog(difficulties) then
		return Result.err(
			dependencyIssue("DifficultyCatalog", "Expected a difficulty catalog validated by DifficultySchema")
		)
	end

	local definition, issue = validateDefinitionAt(value, { "Map" }, manifest, difficulties, nil)
	if issue ~= nil then
		return Result.err(issue)
	end
	return Result.ok(definition :: ConfigTypes.MapDefinition)
end

function MapSchema.validateCatalog(
	value: unknown,
	manifest: ConfigTypes.AssetManifest,
	difficulties: ConfigTypes.DifficultyCatalog
): Result.Result<ConfigTypes.MapCatalog, Validation.Issue>
	if not AssetSchema.isValidatedManifest(manifest) then
		return Result.err(dependencyIssue("AssetManifest", "Expected a manifest validated by AssetSchema"))
	end
	if not DifficultySchema.isValidatedCatalog(difficulties) then
		return Result.err(
			dependencyIssue("DifficultyCatalog", "Expected a difficulty catalog validated by DifficultySchema")
		)
	end

	local rawDefinitions, arrayIssue = Validation.readArray(value, ROOT_PATH, Validation.MAX_CATALOG_ENTRIES)
	if arrayIssue ~= nil then
		return Result.err(arrayIssue)
	end

	local ordered: { ConfigTypes.MapDefinition } = {}
	local byId: { [Ids.MapId]: ConfigTypes.MapDefinition } = {}
	local firstIdPaths: { [string]: string } = {}
	local supportedPairCount = 0
	for index = 1, #(rawDefinitions :: { unknown }) do
		local definition, issue = validateDefinitionAt(
			(rawDefinitions :: { unknown })[index],
			Validation.appendPath(ROOT_PATH, index),
			manifest,
			difficulties,
			firstIdPaths
		)
		if issue ~= nil then
			return Result.err(issue)
		end

		local canonical = definition :: ConfigTypes.MapDefinition
		supportedPairCount += #canonical.supportedDifficultyIds
		if supportedPairCount > Validation.MAX_CATALOG_ENTRIES then
			return Result.err(
				Validation.issue(
					"OUT_OF_RANGE",
					Validation.appendPath(Validation.appendPath(ROOT_PATH, index), "supportedDifficultyIds"),
					"Map catalog declares more supported pairs than the wave catalog can cover"
				)
			)
		end
		table.insert(ordered, canonical)
		byId[canonical.id] = canonical
	end

	local catalog: ConfigTypes.MapCatalog = table.freeze({
		ordered = table.freeze(ordered),
		byId = table.freeze(byId),
	})
	validatedCatalogs[catalog] = true
	return Result.ok(catalog)
end

function MapSchema.isValidatedCatalog(value: unknown): boolean
	return type(value) == "table" and validatedCatalogs[value :: any] == true
end

return table.freeze(MapSchema)
