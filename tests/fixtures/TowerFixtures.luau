--!strict

-- Fresh, test/runtime-only Phase 12 tower fixtures. Every raw root is complete
-- and mutable until the production ConfigurationValidator canonicalizes it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AssetSchema = require(Shared.config.AssetSchema)
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local TowerSchema = require(Shared.config.TowerSchema)
local ConfigTypes = require(Shared.types.ConfigTypes)

local TowerFixtures = {}

export type RawSources = { [string]: any }

export type AuthenticatedFixture = {
	rawSources: RawSources,
	configuration: ConfigTypes.CoreConfiguration,
	single: ConfigTypes.TowerDefinition,
	splash: ConfigTypes.TowerDefinition,
	support: ConfigTypes.TowerDefinition,
}

TowerFixtures.SINGLE_TOWER_ID = "tower:phase12-single"
TowerFixtures.SPLASH_TOWER_ID = "tower:phase12-splash"
TowerFixtures.SUPPORT_TOWER_ID = "tower:phase12-support"
TowerFixtures.TARGET_ELIGIBILITY = "AllEligibleEnemies"

TowerFixtures.SINGLE_MODEL_ASSET_KEY = "test.phase12.single-model"
TowerFixtures.SINGLE_ICON_ASSET_KEY = "test.phase12.single-icon"
TowerFixtures.SPLASH_MODEL_ASSET_KEY = "test.phase12.splash-model"
TowerFixtures.SPLASH_ICON_ASSET_KEY = "test.phase12.splash-icon"
TowerFixtures.SUPPORT_MODEL_ASSET_KEY = "test.phase12.support-model"
TowerFixtures.SUPPORT_ICON_ASSET_KEY = "test.phase12.support-icon"

TowerFixtures.INVALID_CONFIGURATION = "INVALID_CONFIGURATION"
TowerFixtures.INVALID_MANIFEST = "INVALID_MANIFEST"
TowerFixtures.INVALID_CATALOG = "INVALID_CATALOG"
TowerFixtures.DEFINITION_NOT_FOUND = "DEFINITION_NOT_FOUND"
TowerFixtures.ORDERED_IDENTITY_MISMATCH = "ORDERED_IDENTITY_MISMATCH"
TowerFixtures.MODEL_ASSET_IDENTITY_MISMATCH = "MODEL_ASSET_IDENTITY_MISMATCH"

local function singleTower(): { [string]: any }
	return {
		id = TowerFixtures.SINGLE_TOWER_ID,
		displayName = "Phase 12 Single",
		description = "Authenticated single-target runtime fixture.",
		modelAssetKey = TowerFixtures.SINGLE_MODEL_ASSET_KEY,
		iconAssetKey = TowerFixtures.SINGLE_ICON_ASSET_KEY,
		placementCost = 125,
		footprintRadiusStuds = 1.5,
		placementCap = 2,
		supportedTargetModes = { "First", "Last" },
		defaultTargetMode = "First",
		levels = {
			{
				upgradeCost = 0,
				rangeStuds = 10,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-single" },
					damage = 8,
					cooldownSeconds = 1.25,
				},
			},
			{
				upgradeCost = 100,
				rangeStuds = 12,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-single" },
					damage = 14,
					cooldownSeconds = 0.75,
					statusEffects = {
						{ kind = "StatusEffect", key = "status.phase12-marked" },
					},
				},
			},
			{
				upgradeCost = 0,
				rangeStuds = 11,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-single" },
					damage = 0,
					cooldownSeconds = 1,
				},
			},
		},
		tags = { "fixture.phase12", "role.single" },
		mergeProgression = { kind = "MergeProgression", key = "merge.phase12-single" },
	}
end

local function splashTower(): { [string]: any }
	return {
		id = TowerFixtures.SPLASH_TOWER_ID,
		displayName = "Phase 12 Splash",
		description = "Authenticated splash-capable metadata fixture.",
		modelAssetKey = TowerFixtures.SPLASH_MODEL_ASSET_KEY,
		iconAssetKey = TowerFixtures.SPLASH_ICON_ASSET_KEY,
		placementCost = 200,
		footprintRadiusStuds = 2.25,
		placementCap = 3,
		supportedTargetModes = { "Strongest", "Closest", "First" },
		defaultTargetMode = "Strongest",
		levels = {
			{
				upgradeCost = 0,
				rangeStuds = 8,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-splash" },
					damage = 12,
					cooldownSeconds = 2,
				},
			},
			{
				upgradeCost = 150,
				rangeStuds = 10,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-splash" },
					damage = 20,
					cooldownSeconds = 1.5,
				},
			},
			{
				upgradeCost = 250,
				rangeStuds = 13,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-splash" },
					damage = 35,
					cooldownSeconds = 1.25,
					statusEffects = {
						{ kind = "StatusEffect", key = "status.phase12-slow" },
					},
				},
			},
		},
		tags = { "fixture.phase12", "role.splash" },
		mergeProgression = { kind = "MergeProgression", key = "merge.phase12-splash" },
	}
end

local function supportTower(): { [string]: any }
	return {
		id = TowerFixtures.SUPPORT_TOWER_ID,
		displayName = "Phase 12 Support",
		description = "Non-attacking support and economy metadata placeholder.",
		modelAssetKey = TowerFixtures.SUPPORT_MODEL_ASSET_KEY,
		iconAssetKey = TowerFixtures.SUPPORT_ICON_ASSET_KEY,
		placementCost = 100,
		footprintRadiusStuds = 1.75,
		placementCap = 1,
		supportedTargetModes = {},
		levels = {
			{ upgradeCost = 0, rangeStuds = 6 },
			{ upgradeCost = 75, rangeStuds = 8 },
			{ upgradeCost = 125, rangeStuds = 10 },
		},
		tags = { "fixture.phase12", "support.phase12", "economy.phase12" },
		mergeProgression = { kind = "MergeProgression", key = "merge.phase12-support" },
	}
end

function TowerFixtures.rawSources(): RawSources
	return {
		assets = {
			{ key = TowerFixtures.SINGLE_MODEL_ASSET_KEY, kind = "TowerModel" },
			{ key = TowerFixtures.SINGLE_ICON_ASSET_KEY, kind = "Icon" },
			{ key = TowerFixtures.SPLASH_MODEL_ASSET_KEY, kind = "TowerModel" },
			{ key = TowerFixtures.SPLASH_ICON_ASSET_KEY, kind = "Icon" },
			{ key = TowerFixtures.SUPPORT_MODEL_ASSET_KEY, kind = "TowerModel" },
			{ key = TowerFixtures.SUPPORT_ICON_ASSET_KEY, kind = "Icon" },
		},
		towers = {
			singleTower(),
			splashTower(),
			supportTower(),
		},
		enemies = {},
		difficulties = {},
		maps = {},
		waves = {},
		economy = {
			version = 1,
			sellRefund = { basisPoints = 7_000, rounding = "Floor" },
			difficultyRules = {},
		},
		banners = {},
		defaultSettings = {
			version = 2,
			masterVolume = 1,
			musicVolume = 0.75,
			sfxVolume = 0.8,
			uiVolume = 0.9,
			cameraShakeIntensity = 0.5,
			damageNumbersEnabled = true,
			enemyHealthBarsEnabled = true,
			otherPlayerEffectsEnabled = true,
			lowDetailEnabled = false,
			reducedMotionEnabled = false,
			towerRangeEnabled = true,
			uiScale = 1,
		},
	}
end

function TowerFixtures.selectDefinition(
	configuration: unknown,
	towerId: unknown,
	orderedIndex: unknown
): (ConfigTypes.TowerDefinition?, string?)
	if not ConfigurationValidator.isValidatedConfiguration(configuration) then
		return nil, TowerFixtures.INVALID_CONFIGURATION
	end

	local canonical = configuration :: ConfigTypes.CoreConfiguration
	if not AssetSchema.isValidatedManifest(canonical.assets) then
		return nil, TowerFixtures.INVALID_MANIFEST
	end
	if not TowerSchema.isValidatedCatalog(canonical.towers) then
		return nil, TowerFixtures.INVALID_CATALOG
	end
	if type(towerId) ~= "string" or type(orderedIndex) ~= "number" or orderedIndex % 1 ~= 0 then
		return nil, TowerFixtures.DEFINITION_NOT_FOUND
	end

	local definition = canonical.towers.byId[towerId :: any]
	if definition == nil then
		return nil, TowerFixtures.DEFINITION_NOT_FOUND
	end
	if canonical.towers.ordered[orderedIndex :: number] ~= definition then
		return nil, TowerFixtures.ORDERED_IDENTITY_MISMATCH
	end

	local modelAsset = canonical.assets.byKey[definition.modelAssetKey]
	if modelAsset == nil or modelAsset.kind ~= "TowerModel" then
		return nil, TowerFixtures.MODEL_ASSET_IDENTITY_MISMATCH
	end
	local retainsExactAsset = false
	for _, candidate in canonical.assets.ordered do
		if candidate == modelAsset then
			retainsExactAsset = true
			break
		end
	end
	if not retainsExactAsset then
		return nil, TowerFixtures.MODEL_ASSET_IDENTITY_MISMATCH
	end

	return definition, nil
end

function TowerFixtures.authenticateSources(rawSources: RawSources): AuthenticatedFixture
	local result = ConfigurationValidator.validate(rawSources)
	if not result.ok then
		error("Phase 12 fixture configuration failed production validation", 0)
	end
	local configuration = result.value
	if not ConfigurationValidator.isValidatedConfiguration(configuration) then
		error("Phase 12 fixture configuration was not authenticated", 0)
	end

	local single, singleError = TowerFixtures.selectDefinition(configuration, TowerFixtures.SINGLE_TOWER_ID, 1)
	local splash, splashError = TowerFixtures.selectDefinition(configuration, TowerFixtures.SPLASH_TOWER_ID, 2)
	local support, supportError = TowerFixtures.selectDefinition(configuration, TowerFixtures.SUPPORT_TOWER_ID, 3)
	if single == nil or splash == nil or support == nil then
		error("Phase 12 canonical selection failed: " .. (singleError or splashError or supportError or "UNKNOWN"), 0)
	end

	return table.freeze({
		rawSources = rawSources,
		configuration = configuration,
		single = single,
		splash = splash,
		support = support,
	})
end

function TowerFixtures.createAuthenticatedFixture(): AuthenticatedFixture
	return TowerFixtures.authenticateSources(TowerFixtures.rawSources())
end

return table.freeze(TowerFixtures)
