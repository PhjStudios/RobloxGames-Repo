--!strict

local SchemaPrimitives = require(script.Parent.SchemaPrimitives)
local AssetSchema = require(script.Parent.AssetSchema)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

local ROOT_PATH: { Validation.PathSegment } = { "Enemies" }

local ENEMY_FIELDS: { [string]: boolean } = table.freeze({
	behaviors = true,
	damageIncomeClass = true,
	description = true,
	displayName = true,
	iconAssetKey = true,
	id = true,
	leakDamage = true,
	maxHealth = true,
	modelAssetKey = true,
	moveSpeedStudsPerSecond = true,
	resistanceProfile = true,
	tags = true,
	threatClass = true,
})

local ENEMY_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	activeEffects = true,
	cleanup = true,
	creditedDamage = true,
	currentHealth = true,
	damageIncomeEarned = true,
	instance = true,
	laneId = true,
	lifecycleState = true,
	model = true,
	pathProgress = true,
	position = true,
	runtimeEnemyId = true,
	spawnTime = true,
	statuses = true,
	worldCFrame = true,
})

local validatedCatalogs: { [ConfigTypes.EnemyCatalog]: boolean } = setmetatable({}, {
	__mode = "k",
}) :: any

local EnemySchema = {}

local THREAT_CLASSES: { [string]: boolean } = table.freeze({
	Boss = true,
	Elite = true,
	MiniBoss = true,
	Standard = true,
})

local function validateDefinitionAt(
	value: unknown,
	path: { Validation.PathSegment },
	manifest: ConfigTypes.AssetManifest,
	firstIdPaths: { [string]: string }?
): (ConfigTypes.EnemyDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, ENEMY_FIELDS, ENEMY_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawId, idMissing = Validation.getRequiredField(record :: Validation.RawObject, "id", path)
	if idMissing ~= nil then
		return nil, idMissing
	end
	local idPath = Validation.appendPath(path, "id")
	local idResult = Ids.validateEnemyId(rawId)
	if not idResult.ok then
		return nil, Validation.issueWithCause("INVALID_ID", idPath, "Enemy ID is invalid", idResult.error.code)
	end
	local id = idResult.value
	if firstIdPaths ~= nil then
		local firstPath = firstIdPaths[id]
		if firstPath ~= nil then
			return nil,
				Validation.issueWithRelated(
					"DUPLICATE_ID",
					idPath,
					"Enemy ID duplicates an earlier catalog entry",
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
		SchemaPrimitives.assetKey(record :: Validation.RawObject, "modelAssetKey", path, manifest, "EnemyModel", true)
	if modelIssue ~= nil then
		return nil, modelIssue
	end
	local iconAssetKey, iconIssue =
		SchemaPrimitives.assetKey(record :: Validation.RawObject, "iconAssetKey", path, manifest, "Icon", false)
	if iconIssue ~= nil then
		return nil, iconIssue
	end

	local maxHealth, healthIssue = SchemaPrimitives.positiveNumber(record :: Validation.RawObject, "maxHealth", path)
	if healthIssue ~= nil then
		return nil, healthIssue
	end
	local moveSpeedStudsPerSecond, speedIssue =
		SchemaPrimitives.positiveNumber(record :: Validation.RawObject, "moveSpeedStudsPerSecond", path)
	if speedIssue ~= nil then
		return nil, speedIssue
	end
	local leakDamage, leakIssue =
		SchemaPrimitives.nonNegativeInteger(record :: Validation.RawObject, "leakDamage", path)
	if leakIssue ~= nil then
		return nil, leakIssue
	end

	local rawDamageIncomeClass, incomeClassMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "damageIncomeClass", path)
	if incomeClassMissing ~= nil then
		return nil, incomeClassMissing
	end
	local incomeClassPath = Validation.appendPath(path, "damageIncomeClass")
	if type(rawDamageIncomeClass) ~= "string" then
		return nil,
			Validation.issueWithType(
				"INVALID_TYPE",
				incomeClassPath,
				"Damage-income class must be a string",
				rawDamageIncomeClass
			)
	end
	if rawDamageIncomeClass ~= "EligibleHealthRemoved" and rawDamageIncomeClass ~= "None" then
		return nil, Validation.issue("INVALID_ENUM", incomeClassPath, "Damage-income class is not recognized")
	end
	local damageIncomeClass = rawDamageIncomeClass :: ConfigTypes.DamageIncomeClass

	local threatClass: ConfigTypes.EnemyThreatClass = "Standard"
	local rawThreatClass = Validation.getField(record :: Validation.RawObject, "threatClass")
	if rawThreatClass ~= nil then
		local threatClassPath = Validation.appendPath(path, "threatClass")
		if type(rawThreatClass) ~= "string" then
			return nil,
				Validation.issueWithType(
					"INVALID_TYPE",
					threatClassPath,
					"Enemy threat class must be a string",
					rawThreatClass
				)
		end
		if THREAT_CLASSES[rawThreatClass] ~= true then
			return nil, Validation.issue("INVALID_ENUM", threatClassPath, "Enemy threat class is not recognized")
		end
		threatClass = rawThreatClass :: ConfigTypes.EnemyThreatClass
	end

	local tags, tagsIssue = SchemaPrimitives.optionalTags(record :: Validation.RawObject, path)
	if tagsIssue ~= nil then
		return nil, tagsIssue
	end

	local resistanceProfile: ConfigTypes.ResistanceProfileReference? = nil
	local rawResistanceProfile = Validation.getField(record :: Validation.RawObject, "resistanceProfile")
	if rawResistanceProfile ~= nil then
		local resistanceIssue: Validation.Issue?
		local reference: ConfigTypes.FeatureReference?
		reference, resistanceIssue = SchemaPrimitives.featureReference(
			rawResistanceProfile,
			Validation.appendPath(path, "resistanceProfile"),
			"ResistanceProfile"
		)
		if resistanceIssue ~= nil then
			return nil, resistanceIssue
		end
		resistanceProfile = reference :: ConfigTypes.ResistanceProfileReference
	end

	local behaviors: { ConfigTypes.EnemyBehaviorReference }? = nil
	local rawBehaviors = Validation.getField(record :: Validation.RawObject, "behaviors")
	if rawBehaviors ~= nil then
		local behaviorIssue: Validation.Issue?
		local references: { ConfigTypes.FeatureReference }?
		references, behaviorIssue = SchemaPrimitives.featureReferenceList(
			rawBehaviors,
			Validation.appendPath(path, "behaviors"),
			"EnemyBehavior"
		)
		if behaviorIssue ~= nil then
			return nil, behaviorIssue
		end
		behaviors = references :: { ConfigTypes.EnemyBehaviorReference }
	end

	local definition: ConfigTypes.EnemyDefinition = table.freeze({
		id = id,
		displayName = displayName :: string,
		description = description,
		modelAssetKey = modelAssetKey :: ConfigTypes.AssetKey,
		iconAssetKey = iconAssetKey,
		maxHealth = maxHealth :: number,
		moveSpeedStudsPerSecond = moveSpeedStudsPerSecond :: number,
		leakDamage = leakDamage :: number,
		damageIncomeClass = damageIncomeClass,
		threatClass = threatClass,
		tags = tags,
		resistanceProfile = resistanceProfile,
		behaviors = behaviors,
	})
	return definition, nil
end

function EnemySchema.validateDefinition(
	value: unknown,
	manifest: ConfigTypes.AssetManifest
): Result.Result<ConfigTypes.EnemyDefinition, Validation.Issue>
	if not AssetSchema.isValidatedManifest(manifest) then
		return Result.err(
			Validation.issue("INVALID_REFERENCE", { "AssetManifest" }, "Expected a manifest validated by AssetSchema")
		)
	end

	local definition, issue = validateDefinitionAt(value, { "Enemy" }, manifest, nil)
	if issue ~= nil then
		return Result.err(issue)
	end
	return Result.ok(definition :: ConfigTypes.EnemyDefinition)
end

function EnemySchema.validateCatalog(
	value: unknown,
	manifest: ConfigTypes.AssetManifest
): Result.Result<ConfigTypes.EnemyCatalog, Validation.Issue>
	if not AssetSchema.isValidatedManifest(manifest) then
		return Result.err(
			Validation.issue("INVALID_REFERENCE", { "AssetManifest" }, "Expected a manifest validated by AssetSchema")
		)
	end

	local rawDefinitions, arrayIssue = Validation.readArray(value, ROOT_PATH, Validation.MAX_CATALOG_ENTRIES)
	if arrayIssue ~= nil then
		return Result.err(arrayIssue)
	end

	local ordered: { ConfigTypes.EnemyDefinition } = {}
	local byId: { [Ids.EnemyId]: ConfigTypes.EnemyDefinition } = {}
	local firstIdPaths: { [string]: string } = {}
	for index = 1, #(rawDefinitions :: { unknown }) do
		local rawDefinition = (rawDefinitions :: { unknown })[index]
		local definition, issue =
			validateDefinitionAt(rawDefinition, Validation.appendPath(ROOT_PATH, index), manifest, firstIdPaths)
		if issue ~= nil then
			return Result.err(issue)
		end

		local canonicalDefinition = definition :: ConfigTypes.EnemyDefinition
		table.insert(ordered, canonicalDefinition)
		byId[canonicalDefinition.id] = canonicalDefinition
	end

	local catalog: ConfigTypes.EnemyCatalog = table.freeze({
		ordered = table.freeze(ordered),
		byId = table.freeze(byId),
	})
	validatedCatalogs[catalog] = true
	return Result.ok(catalog)
end

function EnemySchema.isValidatedCatalog(value: unknown): boolean
	return type(value) == "table" and validatedCatalogs[value :: any] == true
end

return table.freeze(EnemySchema)
