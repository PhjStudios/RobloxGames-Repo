--!strict

local AssetSchema = require(script.Parent.AssetSchema)
local SchemaPrimitives = require(script.Parent.SchemaPrimitives)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

local ROOT_PATH: { Validation.PathSegment } = { "Difficulties" }

local DIFFICULTY_FIELDS: { [string]: boolean } = table.freeze({
	base = true,
	description = true,
	displayName = true,
	iconAssetKey = true,
	id = true,
	kind = true,
	modifiers = true,
	tags = true,
	timing = true,
	waveCount = true,
})

local DIFFICULTY_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	activeWave = true,
	currentBaseHealth = true,
	currentWave = true,
	players = true,
	runtimeDifficultyId = true,
	startedAt = true,
	state = true,
})

local BASE_FIELDS: { [string]: boolean } = table.freeze({
	maxHealth = true,
})

local BASE_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	currentHealth = true,
	instance = true,
})

local MODIFIER_FIELDS: { [string]: boolean } = table.freeze({
	enemyHealthMultiplier = true,
	enemyMoveSpeedMultiplier = true,
})

local TIMING_FIELDS: { [string]: boolean } = table.freeze({
	bossCadenceWaves = true,
	earlyClearIntermissionSeconds = true,
	skipVoteMinimumDelaySeconds = true,
})

local NO_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({})

local validatedCatalogs: { [ConfigTypes.DifficultyCatalog]: boolean } = setmetatable({}, {
	__mode = "k",
}) :: any

local DifficultySchema = {}

local function invalidManifestResult(): Result.Failure<Validation.Issue>
	return Result.err(
		Validation.issue("INVALID_REFERENCE", { "AssetManifest" }, "Expected a manifest validated by AssetSchema")
	)
end

local function validateBase(
	value: unknown,
	path: { Validation.PathSegment }
): (ConfigTypes.BaseConfiguration?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, BASE_FIELDS, BASE_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local maxHealth, healthIssue = SchemaPrimitives.positiveInteger(record :: Validation.RawObject, "maxHealth", path)
	if healthIssue ~= nil then
		return nil, healthIssue
	end

	return table.freeze({
		maxHealth = maxHealth :: number,
	}), nil
end

local function validateModifiers(
	value: unknown,
	path: { Validation.PathSegment }
): (ConfigTypes.DifficultyModifiers?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, MODIFIER_FIELDS, NO_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local healthMultiplier, healthIssue = SchemaPrimitives.boundedNumber(
		record :: Validation.RawObject,
		"enemyHealthMultiplier",
		path,
		Validation.MIN_DIFFICULTY_MULTIPLIER,
		Validation.MAX_DIFFICULTY_MULTIPLIER
	)
	if healthIssue ~= nil then
		return nil, healthIssue
	end

	local speedMultiplier, speedIssue = SchemaPrimitives.boundedNumber(
		record :: Validation.RawObject,
		"enemyMoveSpeedMultiplier",
		path,
		Validation.MIN_DIFFICULTY_MULTIPLIER,
		Validation.MAX_DIFFICULTY_MULTIPLIER
	)
	if speedIssue ~= nil then
		return nil, speedIssue
	end

	return table.freeze({
		enemyHealthMultiplier = healthMultiplier :: number,
		enemyMoveSpeedMultiplier = speedMultiplier :: number,
	}),
		nil
end

local function validateTiming(
	value: unknown,
	path: { Validation.PathSegment }
): (ConfigTypes.WaveTimingConfiguration?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, TIMING_FIELDS, NO_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local intermission, intermissionIssue = SchemaPrimitives.boundedNumber(
		record :: Validation.RawObject,
		"earlyClearIntermissionSeconds",
		path,
		0,
		Validation.MAX_WAVE_TIME_SECONDS
	)
	if intermissionIssue ~= nil then
		return nil, intermissionIssue
	end

	local cadence, cadenceIssue = SchemaPrimitives.boundedInteger(
		record :: Validation.RawObject,
		"bossCadenceWaves",
		path,
		1,
		Validation.MAX_BOSS_CADENCE_WAVES
	)
	if cadenceIssue ~= nil then
		return nil, cadenceIssue
	end

	local skipDelay, skipDelayIssue = SchemaPrimitives.boundedNumber(
		record :: Validation.RawObject,
		"skipVoteMinimumDelaySeconds",
		path,
		0,
		Validation.MAX_WAVE_TIME_SECONDS
	)
	if skipDelayIssue ~= nil then
		return nil, skipDelayIssue
	end

	return table.freeze({
		earlyClearIntermissionSeconds = intermission :: number,
		bossCadenceWaves = cadence :: number,
		skipVoteMinimumDelaySeconds = skipDelay :: number,
	}),
		nil
end

local function validateDefinitionAt(
	value: unknown,
	path: { Validation.PathSegment },
	manifest: ConfigTypes.AssetManifest,
	firstIdPaths: { [string]: string }?
): (ConfigTypes.DifficultyDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, DIFFICULTY_FIELDS, DIFFICULTY_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawId, idMissing = Validation.getRequiredField(record :: Validation.RawObject, "id", path)
	if idMissing ~= nil then
		return nil, idMissing
	end
	local idPath = Validation.appendPath(path, "id")
	local idResult = Ids.validateDifficultyId(rawId)
	if not idResult.ok then
		return nil, Validation.issueWithCause("INVALID_ID", idPath, "Difficulty ID is invalid", idResult.error.code)
	end
	local id = idResult.value
	if firstIdPaths ~= nil then
		local firstPath = firstIdPaths[id]
		if firstPath ~= nil then
			return nil,
				Validation.issueWithRelated(
					"DUPLICATE_ID",
					idPath,
					"Difficulty ID duplicates an earlier catalog entry",
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
	local iconAssetKey, iconIssue =
		SchemaPrimitives.assetKey(record :: Validation.RawObject, "iconAssetKey", path, manifest, "Icon", false)
	if iconIssue ~= nil then
		return nil, iconIssue
	end

	local rawKind, kindMissing = Validation.getRequiredField(record :: Validation.RawObject, "kind", path)
	if kindMissing ~= nil then
		return nil, kindMissing
	end
	local kindPath = Validation.appendPath(path, "kind")
	if type(rawKind) ~= "string" then
		return nil, Validation.issueWithType("INVALID_TYPE", kindPath, "Difficulty kind must be a string", rawKind)
	end
	if rawKind ~= "Finite" and rawKind ~= "Endless" then
		return nil, Validation.issue("INVALID_ENUM", kindPath, "Difficulty kind is not recognized")
	end

	local waveCount: number? = nil
	local rawWaveCount = Validation.getField(record :: Validation.RawObject, "waveCount")
	if rawKind == "Finite" then
		local waveCountIssue: Validation.Issue?
		waveCount, waveCountIssue = SchemaPrimitives.boundedInteger(
			record :: Validation.RawObject,
			"waveCount",
			path,
			1,
			Validation.MAX_WAVES_PER_SCHEDULE
		)
		if waveCountIssue ~= nil then
			return nil, waveCountIssue
		end
	elseif rawWaveCount ~= nil then
		return nil,
			Validation.issue(
				"INVALID_REFERENCE",
				Validation.appendPath(path, "waveCount"),
				"Endless difficulty must not declare a finite wave count"
			)
	end

	local rawBase, baseMissing = Validation.getRequiredField(record :: Validation.RawObject, "base", path)
	if baseMissing ~= nil then
		return nil, baseMissing
	end
	local base, baseIssue = validateBase(rawBase, Validation.appendPath(path, "base"))
	if baseIssue ~= nil then
		return nil, baseIssue
	end

	local rawModifiers, modifiersMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "modifiers", path)
	if modifiersMissing ~= nil then
		return nil, modifiersMissing
	end
	local modifiers, modifiersIssue = validateModifiers(rawModifiers, Validation.appendPath(path, "modifiers"))
	if modifiersIssue ~= nil then
		return nil, modifiersIssue
	end

	local rawTiming, timingMissing = Validation.getRequiredField(record :: Validation.RawObject, "timing", path)
	if timingMissing ~= nil then
		return nil, timingMissing
	end
	local timing, timingIssue = validateTiming(rawTiming, Validation.appendPath(path, "timing"))
	if timingIssue ~= nil then
		return nil, timingIssue
	end

	local tags, tagsIssue = SchemaPrimitives.optionalTags(record :: Validation.RawObject, path)
	if tagsIssue ~= nil then
		return nil, tagsIssue
	end

	local common = {
		id = id,
		displayName = displayName :: string,
		description = description,
		iconAssetKey = iconAssetKey,
		base = base :: ConfigTypes.BaseConfiguration,
		modifiers = modifiers :: ConfigTypes.DifficultyModifiers,
		timing = timing :: ConfigTypes.WaveTimingConfiguration,
		tags = tags,
	}

	if rawKind == "Finite" then
		local definition: ConfigTypes.FiniteDifficultyDefinition = table.freeze({
			id = common.id,
			displayName = common.displayName,
			description = common.description,
			iconAssetKey = common.iconAssetKey,
			base = common.base,
			modifiers = common.modifiers,
			timing = common.timing,
			tags = common.tags,
			kind = "Finite",
			waveCount = waveCount :: number,
		})
		return definition, nil
	end

	local definition: ConfigTypes.EndlessDifficultyDefinition = table.freeze({
		id = common.id,
		displayName = common.displayName,
		description = common.description,
		iconAssetKey = common.iconAssetKey,
		base = common.base,
		modifiers = common.modifiers,
		timing = common.timing,
		tags = common.tags,
		kind = "Endless",
	})
	return definition, nil
end

function DifficultySchema.validateDefinition(
	value: unknown,
	manifest: ConfigTypes.AssetManifest
): Result.Result<ConfigTypes.DifficultyDefinition, Validation.Issue>
	if not AssetSchema.isValidatedManifest(manifest) then
		return invalidManifestResult()
	end

	local definition, issue = validateDefinitionAt(value, { "Difficulty" }, manifest, nil)
	if issue ~= nil then
		return Result.err(issue)
	end
	return Result.ok(definition :: ConfigTypes.DifficultyDefinition)
end

function DifficultySchema.validateCatalog(
	value: unknown,
	manifest: ConfigTypes.AssetManifest
): Result.Result<ConfigTypes.DifficultyCatalog, Validation.Issue>
	if not AssetSchema.isValidatedManifest(manifest) then
		return invalidManifestResult()
	end

	local rawDefinitions, arrayIssue = Validation.readArray(value, ROOT_PATH, Validation.MAX_CATALOG_ENTRIES)
	if arrayIssue ~= nil then
		return Result.err(arrayIssue)
	end

	local ordered: { ConfigTypes.DifficultyDefinition } = {}
	local byId: { [Ids.DifficultyId]: ConfigTypes.DifficultyDefinition } = {}
	local firstIdPaths: { [string]: string } = {}
	for index = 1, #(rawDefinitions :: { unknown }) do
		local definition, issue = validateDefinitionAt(
			(rawDefinitions :: { unknown })[index],
			Validation.appendPath(ROOT_PATH, index),
			manifest,
			firstIdPaths
		)
		if issue ~= nil then
			return Result.err(issue)
		end

		local canonical = definition :: ConfigTypes.DifficultyDefinition
		table.insert(ordered, canonical)
		byId[canonical.id] = canonical
	end

	local catalog: ConfigTypes.DifficultyCatalog = table.freeze({
		ordered = table.freeze(ordered),
		byId = table.freeze(byId),
	})
	validatedCatalogs[catalog] = true
	return Result.ok(catalog)
end

function DifficultySchema.isValidatedCatalog(value: unknown): boolean
	return type(value) == "table" and validatedCatalogs[value :: any] == true
end

return table.freeze(DifficultySchema)
