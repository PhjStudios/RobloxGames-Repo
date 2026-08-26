--!strict

local SchemaPrimitives = require(script.Parent.SchemaPrimitives)
local AssetSchema = require(script.Parent.AssetSchema)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

local ROOT_PATH: { Validation.PathSegment } = { "Towers" }

local TARGET_MODES: { [string]: boolean } = table.freeze({
	Closest = true,
	First = true,
	Last = true,
	Strongest = true,
	Weakest = true,
})

local TOWER_FIELDS: { [string]: boolean } = table.freeze({
	defaultTargetMode = true,
	description = true,
	displayName = true,
	footprintRadiusStuds = true,
	iconAssetKey = true,
	id = true,
	levels = true,
	mergeProgression = true,
	modelAssetKey = true,
	placementCap = true,
	placementCost = true,
	supportedTargetModes = true,
	tags = true,
})

local TOWER_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	activeEffects = true,
	cleanup = true,
	cooldownEndsAt = true,
	currentLevel = true,
	currentTargetId = true,
	instance = true,
	level = true,
	mergeRank = true,
	model = true,
	ownerUserId = true,
	placedTowerId = true,
	position = true,
	targetMode = true,
	totalInvestment = true,
	unitId = true,
})

local LEVEL_FIELDS: { [string]: boolean } = table.freeze({
	attack = true,
	rangeStuds = true,
	upgradeCost = true,
})

local LEVEL_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	activeEffects = true,
	cooldownEndsAt = true,
	cooldownRemaining = true,
	currentTargetId = true,
	level = true,
})

local ATTACK_FIELDS: { [string]: boolean } = table.freeze({
	behavior = true,
	cooldownSeconds = true,
	damage = true,
	statusEffects = true,
})

local ATTACK_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	lastAttackAt = true,
	targetId = true,
})

local validatedCatalogs: { [ConfigTypes.TowerCatalog]: boolean } = setmetatable({}, {
	__mode = "k",
}) :: any

local TowerSchema = {}

local function validateAttack(
	value: unknown,
	path: { Validation.PathSegment }
): (ConfigTypes.TowerAttackDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, ATTACK_FIELDS, ATTACK_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawBehavior, behaviorMissing = Validation.getRequiredField(record :: Validation.RawObject, "behavior", path)
	if behaviorMissing ~= nil then
		return nil, behaviorMissing
	end
	local behavior, behaviorIssue =
		SchemaPrimitives.featureReference(rawBehavior, Validation.appendPath(path, "behavior"), "AttackBehavior")
	if behaviorIssue ~= nil then
		return nil, behaviorIssue
	end

	local damage, damageIssue = SchemaPrimitives.nonNegativeNumber(record :: Validation.RawObject, "damage", path)
	if damageIssue ~= nil then
		return nil, damageIssue
	end
	local cooldownSeconds, cooldownIssue =
		SchemaPrimitives.positiveNumber(record :: Validation.RawObject, "cooldownSeconds", path)
	if cooldownIssue ~= nil then
		return nil, cooldownIssue
	end

	local statusEffects: { ConfigTypes.StatusEffectReference }? = nil
	local rawStatusEffects = Validation.getField(record :: Validation.RawObject, "statusEffects")
	if rawStatusEffects ~= nil then
		local statusIssue: Validation.Issue?
		local references: { ConfigTypes.FeatureReference }?
		references, statusIssue = SchemaPrimitives.featureReferenceList(
			rawStatusEffects,
			Validation.appendPath(path, "statusEffects"),
			"StatusEffect"
		)
		if statusIssue ~= nil then
			return nil, statusIssue
		end
		statusEffects = references :: { ConfigTypes.StatusEffectReference }
	end

	local attack: ConfigTypes.TowerAttackDefinition = table.freeze({
		behavior = behavior :: ConfigTypes.AttackBehaviorReference,
		damage = damage :: number,
		cooldownSeconds = cooldownSeconds :: number,
		statusEffects = statusEffects,
	})
	return attack, nil
end

local function validateLevels(
	value: unknown,
	path: { Validation.PathSegment }
): ({ ConfigTypes.TowerLevelDefinition }?, boolean, Validation.Issue?)
	local rawLevels, arrayIssue = Validation.readArray(value, path, Validation.MAX_LEVEL_ENTRIES)
	if arrayIssue ~= nil then
		return nil, false, arrayIssue
	end
	if #(rawLevels :: { unknown }) == 0 then
		return nil, false, Validation.issue("EMPTY_COLLECTION", path, "Tower must define at least one level")
	end

	local levels: { ConfigTypes.TowerLevelDefinition } = {}
	local hasAttack = false
	for index = 1, #(rawLevels :: { unknown }) do
		local rawLevel = (rawLevels :: { unknown })[index]
		local levelPath = Validation.appendPath(path, index)
		local record, recordIssue = Validation.readObject(rawLevel, levelPath, LEVEL_FIELDS, LEVEL_RUNTIME_FIELDS)
		if recordIssue ~= nil then
			return nil, false, recordIssue
		end

		local upgradeCost, upgradeIssue =
			SchemaPrimitives.nonNegativeInteger(record :: Validation.RawObject, "upgradeCost", levelPath)
		if upgradeIssue ~= nil then
			return nil, false, upgradeIssue
		end
		if index == 1 and upgradeCost ~= 0 then
			return nil,
				false,
				Validation.issue(
					"INVALID_ORDER",
					Validation.appendPath(levelPath, "upgradeCost"),
					"First level upgrade cost must be zero"
				)
		end

		local rangeStuds, rangeIssue =
			SchemaPrimitives.nonNegativeNumber(record :: Validation.RawObject, "rangeStuds", levelPath)
		if rangeIssue ~= nil then
			return nil, false, rangeIssue
		end

		local attack: ConfigTypes.TowerAttackDefinition? = nil
		local rawAttack = Validation.getField(record :: Validation.RawObject, "attack")
		if rawAttack ~= nil then
			local attackIssue: Validation.Issue?
			attack, attackIssue = validateAttack(rawAttack, Validation.appendPath(levelPath, "attack"))
			if attackIssue ~= nil then
				return nil, false, attackIssue
			end
			hasAttack = true
		end

		local level: ConfigTypes.TowerLevelDefinition = table.freeze({
			upgradeCost = upgradeCost :: number,
			rangeStuds = rangeStuds :: number,
			attack = attack,
		})
		table.insert(levels, level)
	end

	return table.freeze(levels), hasAttack, nil
end

local function validateTargetModes(
	value: unknown,
	path: { Validation.PathSegment }
): ({ ConfigTypes.TargetMode }?, { [string]: boolean }?, Validation.Issue?)
	local rawModes, arrayIssue = Validation.readArray(value, path, 5)
	if arrayIssue ~= nil then
		return nil, nil, arrayIssue
	end

	local modes: { ConfigTypes.TargetMode } = {}
	local seen: { [string]: boolean } = {}
	local firstPaths: { [string]: string } = {}
	for index = 1, #(rawModes :: { unknown }) do
		local rawMode = (rawModes :: { unknown })[index]
		local modePath = Validation.appendPath(path, index)
		if type(rawMode) ~= "string" then
			return nil, nil, Validation.issueWithType("INVALID_TYPE", modePath, "Target mode must be a string", rawMode)
		end
		if TARGET_MODES[rawMode] ~= true then
			return nil, nil, Validation.issue("INVALID_ENUM", modePath, "Target mode is not recognized")
		end

		local firstPath = firstPaths[rawMode]
		if firstPath ~= nil then
			return nil,
				nil,
				Validation.issueWithRelated(
					"DUPLICATE_VALUE",
					modePath,
					"Target mode duplicates an earlier list entry",
					firstPath
				)
		end
		firstPaths[rawMode] = Validation.renderPath(modePath)
		seen[rawMode] = true
		table.insert(modes, rawMode :: ConfigTypes.TargetMode)
	end

	return table.freeze(modes), seen, nil
end

local function validateDefinitionAt(
	value: unknown,
	path: { Validation.PathSegment },
	manifest: ConfigTypes.AssetManifest,
	firstIdPaths: { [string]: string }?
): (ConfigTypes.TowerDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, TOWER_FIELDS, TOWER_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawId, idMissing = Validation.getRequiredField(record :: Validation.RawObject, "id", path)
	if idMissing ~= nil then
		return nil, idMissing
	end
	local idPath = Validation.appendPath(path, "id")
	local idResult = Ids.validateTowerId(rawId)
	if not idResult.ok then
		return nil, Validation.issueWithCause("INVALID_ID", idPath, "Tower ID is invalid", idResult.error.code)
	end
	local id = idResult.value
	if firstIdPaths ~= nil then
		local firstPath = firstIdPaths[id]
		if firstPath ~= nil then
			return nil,
				Validation.issueWithRelated(
					"DUPLICATE_ID",
					idPath,
					"Tower ID duplicates an earlier catalog entry",
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
		SchemaPrimitives.assetKey(record :: Validation.RawObject, "modelAssetKey", path, manifest, "TowerModel", true)
	if modelIssue ~= nil then
		return nil, modelIssue
	end
	local iconAssetKey, iconIssue =
		SchemaPrimitives.assetKey(record :: Validation.RawObject, "iconAssetKey", path, manifest, "Icon", false)
	if iconIssue ~= nil then
		return nil, iconIssue
	end

	local placementCost, placementCostIssue =
		SchemaPrimitives.nonNegativeInteger(record :: Validation.RawObject, "placementCost", path)
	if placementCostIssue ~= nil then
		return nil, placementCostIssue
	end
	local footprintRadiusStuds, footprintIssue =
		SchemaPrimitives.positiveNumber(record :: Validation.RawObject, "footprintRadiusStuds", path)
	if footprintIssue ~= nil then
		return nil, footprintIssue
	end
	local placementCap, placementCapIssue =
		SchemaPrimitives.positiveInteger(record :: Validation.RawObject, "placementCap", path)
	if placementCapIssue ~= nil then
		return nil, placementCapIssue
	end

	local rawTargetModes, targetModesMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "supportedTargetModes", path)
	if targetModesMissing ~= nil then
		return nil, targetModesMissing
	end
	local targetModes, targetModeSet, targetModesIssue =
		validateTargetModes(rawTargetModes, Validation.appendPath(path, "supportedTargetModes"))
	if targetModesIssue ~= nil then
		return nil, targetModesIssue
	end

	local defaultTargetMode: ConfigTypes.TargetMode? = nil
	local rawDefaultTargetMode = Validation.getField(record :: Validation.RawObject, "defaultTargetMode")
	if rawDefaultTargetMode ~= nil then
		local defaultPath = Validation.appendPath(path, "defaultTargetMode")
		if type(rawDefaultTargetMode) ~= "string" then
			return nil,
				Validation.issueWithType(
					"INVALID_TYPE",
					defaultPath,
					"Default target mode must be a string",
					rawDefaultTargetMode
				)
		end
		if TARGET_MODES[rawDefaultTargetMode] ~= true then
			return nil, Validation.issue("INVALID_ENUM", defaultPath, "Default target mode is not recognized")
		end
		defaultTargetMode = rawDefaultTargetMode :: ConfigTypes.TargetMode
	end

	local rawLevels, levelsMissing = Validation.getRequiredField(record :: Validation.RawObject, "levels", path)
	if levelsMissing ~= nil then
		return nil, levelsMissing
	end
	local levels, hasAttack, levelsIssue = validateLevels(rawLevels, Validation.appendPath(path, "levels"))
	if levelsIssue ~= nil then
		return nil, levelsIssue
	end

	local totalInvestment = placementCost :: number
	for index, level in levels :: { ConfigTypes.TowerLevelDefinition } do
		if level.upgradeCost > Validation.MAX_SAFE_INTEGER - totalInvestment then
			return nil,
				Validation.issue(
					"OUT_OF_RANGE",
					Validation.appendPath(
						Validation.appendPath(Validation.appendPath(path, "levels"), index),
						"upgradeCost"
					),
					"Cumulative tower investment exceeds the exact safe-integer range"
				)
		end
		totalInvestment += level.upgradeCost
	end

	if hasAttack then
		if #(targetModes :: { ConfigTypes.TargetMode }) == 0 then
			return nil,
				Validation.issue(
					"EMPTY_COLLECTION",
					Validation.appendPath(path, "supportedTargetModes"),
					"Attacking tower must support at least one target mode"
				)
		end
		if defaultTargetMode == nil then
			return nil,
				Validation.issue(
					"MISSING_FIELD",
					Validation.appendPath(path, "defaultTargetMode"),
					"Attacking tower requires a default target mode"
				)
		end
		if (targetModeSet :: { [string]: boolean })[defaultTargetMode] ~= true then
			return nil,
				Validation.issue(
					"INVALID_REFERENCE",
					Validation.appendPath(path, "defaultTargetMode"),
					"Default target mode is not present in the supported list"
				)
		end
	elseif #(targetModes :: { ConfigTypes.TargetMode }) > 0 then
		return nil,
			Validation.issue(
				"INVALID_REFERENCE",
				Validation.appendPath(path, "supportedTargetModes"),
				"Non-attacking tower must not declare target modes"
			)
	elseif defaultTargetMode ~= nil then
		return nil,
			Validation.issue(
				"INVALID_REFERENCE",
				Validation.appendPath(path, "defaultTargetMode"),
				"Non-attacking tower must not declare a default target mode"
			)
	end

	local tags, tagsIssue = SchemaPrimitives.optionalTags(record :: Validation.RawObject, path)
	if tagsIssue ~= nil then
		return nil, tagsIssue
	end

	local mergeProgression: ConfigTypes.MergeProgressionReference? = nil
	local rawMergeProgression = Validation.getField(record :: Validation.RawObject, "mergeProgression")
	if rawMergeProgression ~= nil then
		local mergeIssue: Validation.Issue?
		local reference: ConfigTypes.FeatureReference?
		reference, mergeIssue = SchemaPrimitives.featureReference(
			rawMergeProgression,
			Validation.appendPath(path, "mergeProgression"),
			"MergeProgression"
		)
		if mergeIssue ~= nil then
			return nil, mergeIssue
		end
		mergeProgression = reference :: ConfigTypes.MergeProgressionReference
	end

	local definition: ConfigTypes.TowerDefinition = table.freeze({
		id = id,
		displayName = displayName :: string,
		description = description,
		modelAssetKey = modelAssetKey :: ConfigTypes.AssetKey,
		iconAssetKey = iconAssetKey,
		placementCost = placementCost :: number,
		footprintRadiusStuds = footprintRadiusStuds :: number,
		placementCap = placementCap :: number,
		supportedTargetModes = targetModes :: { ConfigTypes.TargetMode },
		defaultTargetMode = defaultTargetMode,
		levels = levels :: { ConfigTypes.TowerLevelDefinition },
		tags = tags,
		mergeProgression = mergeProgression,
	})
	return definition, nil
end

function TowerSchema.validateDefinition(
	value: unknown,
	manifest: ConfigTypes.AssetManifest
): Result.Result<ConfigTypes.TowerDefinition, Validation.Issue>
	if not AssetSchema.isValidatedManifest(manifest) then
		return Result.err(
			Validation.issue("INVALID_REFERENCE", { "AssetManifest" }, "Expected a manifest validated by AssetSchema")
		)
	end

	local definition, issue = validateDefinitionAt(value, { "Tower" }, manifest, nil)
	if issue ~= nil then
		return Result.err(issue)
	end
	return Result.ok(definition :: ConfigTypes.TowerDefinition)
end

function TowerSchema.validateCatalog(
	value: unknown,
	manifest: ConfigTypes.AssetManifest
): Result.Result<ConfigTypes.TowerCatalog, Validation.Issue>
	if not AssetSchema.isValidatedManifest(manifest) then
		return Result.err(
			Validation.issue("INVALID_REFERENCE", { "AssetManifest" }, "Expected a manifest validated by AssetSchema")
		)
	end

	local rawDefinitions, arrayIssue = Validation.readArray(value, ROOT_PATH, Validation.MAX_CATALOG_ENTRIES)
	if arrayIssue ~= nil then
		return Result.err(arrayIssue)
	end

	local ordered: { ConfigTypes.TowerDefinition } = {}
	local byId: { [Ids.TowerId]: ConfigTypes.TowerDefinition } = {}
	local firstIdPaths: { [string]: string } = {}
	for index = 1, #(rawDefinitions :: { unknown }) do
		local rawDefinition = (rawDefinitions :: { unknown })[index]
		local definition, issue =
			validateDefinitionAt(rawDefinition, Validation.appendPath(ROOT_PATH, index), manifest, firstIdPaths)
		if issue ~= nil then
			return Result.err(issue)
		end

		local canonicalDefinition = definition :: ConfigTypes.TowerDefinition
		table.insert(ordered, canonicalDefinition)
		byId[canonicalDefinition.id] = canonicalDefinition
	end

	local catalog: ConfigTypes.TowerCatalog = table.freeze({
		ordered = table.freeze(ordered),
		byId = table.freeze(byId),
	})
	validatedCatalogs[catalog] = true
	return Result.ok(catalog)
end

function TowerSchema.isValidatedCatalog(value: unknown): boolean
	return type(value) == "table" and validatedCatalogs[value :: any] == true
end

return table.freeze(TowerSchema)
