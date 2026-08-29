--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Fixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)

local Shared = game:GetService("ReplicatedStorage").Shared
local AssetSchema = require(Shared.config.AssetSchema)
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local TowerSchema = require(Shared.config.TowerSchema)
local Validation = require(Shared.util.Validation)
local ProductionAssets = require(Shared.config.Assets)
local ProductionTowers = require(Shared.config.Towers)

type Assertions = TestHarness.Assertions

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in next, value do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy
end

local function freezeRecursively(value: any): any
	if type(value) ~= "table" then
		return value
	end

	for _, child in next, value do
		freezeRecursively(child)
	end
	if not table.isfrozen(value) then
		table.freeze(value)
	end
	return value
end

local function validatedManifest(assertions: Assertions, sources: { [string]: any }): any
	local result = AssetSchema.validateManifest(sources.assets)
	assertions.isTrue(result.ok)
	if not result.ok then
		return nil
	end
	return result.value
end

local function expectTowerIssue(
	assertions: Assertions,
	sources: { [string]: any },
	code: string,
	path: string,
	relatedPath: string?
): any
	local manifest = validatedManifest(assertions, sources)
	if manifest == nil then
		return nil
	end

	local result = TowerSchema.validateCatalog(sources.towers, manifest)
	assertions.isFalse(result.ok)
	if result.ok then
		return nil
	end

	local issue = result.error
	assertions.equal(issue.code, code)
	assertions.equal(issue.path, path)
	assertions.equal(issue.relatedPath, relatedPath)
	assertions.isTrue(table.isfrozen(issue))
	return issue
end

return TestHarness.suite("authenticated Phase 12 tower fixtures", {
	TestHarness.case("authenticates independent complete roots exactly once", function(assertions)
		local first = Fixtures.createAuthenticatedFixture()
		local second = Fixtures.createAuthenticatedFixture()

		assertions.isTrue(ConfigurationValidator.isValidatedConfiguration(first.configuration))
		assertions.isTrue(AssetSchema.isValidatedManifest(first.configuration.assets))
		assertions.isTrue(TowerSchema.isValidatedCatalog(first.configuration.towers))
		assertions.notEqual(first.rawSources, second.rawSources)
		assertions.notEqual(first.rawSources.assets, second.rawSources.assets)
		assertions.notEqual(first.rawSources.towers, second.rawSources.towers)
		assertions.notEqual(first.configuration, second.configuration)
		assertions.notEqual(first.single, second.single)
		assertions.equal(#first.configuration.assets.ordered, 6)
		assertions.equal(#first.configuration.towers.ordered, 3)
		assertions.equal(#first.configuration.enemies.ordered, 0)
		assertions.equal(#first.configuration.difficulties.ordered, 0)
		assertions.equal(#first.configuration.maps.ordered, 0)
		assertions.equal(#first.configuration.waves.ordered, 0)
		assertions.equal(#first.configuration.economy.ordered, 0)
		assertions.equal(#first.configuration.banners.ordered, 0)
		assertions.isTrue(table.isfrozen(first))
		assertions.isTrue(table.isfrozen(first.configuration))
	end),
	TestHarness.case("retains exact ordered definition and model declaration identities", function(assertions)
		local fixture = Fixtures.createAuthenticatedFixture()
		local configuration = fixture.configuration
		local definitions = { fixture.single, fixture.splash, fixture.support }
		local ids = {
			Fixtures.SINGLE_TOWER_ID,
			Fixtures.SPLASH_TOWER_ID,
			Fixtures.SUPPORT_TOWER_ID,
		}

		for index, definition in definitions do
			assertions.equal(definition, configuration.towers.ordered[index])
			assertions.equal(definition, configuration.towers.byId[ids[index]])
			local selected, selectionError = Fixtures.selectDefinition(configuration, ids[index], index)
			assertions.equal(selected, definition)
			assertions.isNil(selectionError)

			local modelAsset = configuration.assets.byKey[definition.modelAssetKey]
			assertions.isNotNil(modelAsset)
			assertions.equal(modelAsset.kind, "TowerModel")
			assertions.isTrue(table.isfrozen(modelAsset))
		end

		local selected, selectionError = Fixtures.selectDefinition(configuration, Fixtures.SINGLE_TOWER_ID, 2)
		assertions.isNil(selected)
		assertions.equal(selectionError, Fixtures.ORDERED_IDENTITY_MISMATCH)
		selected, selectionError = Fixtures.selectDefinition(configuration, "tower:not-present", 1)
		assertions.isNil(selected)
		assertions.equal(selectionError, Fixtures.DEFINITION_NOT_FOUND)
	end),
	TestHarness.case("rejects copied separately validated and mismatched roots", function(assertions)
		local first = Fixtures.createAuthenticatedFixture()
		local second = Fixtures.createAuthenticatedFixture()
		local copied = freezeRecursively(deepCopy(first.configuration))
		local selected, selectionError = Fixtures.selectDefinition(copied, Fixtures.SINGLE_TOWER_ID, 1)
		assertions.isNil(selected)
		assertions.equal(selectionError, Fixtures.INVALID_CONFIGURATION)

		local raw = Fixtures.rawSources()
		local separateManifest = AssetSchema.validateManifest(raw.assets)
		assertions.isTrue(separateManifest.ok)
		if not separateManifest.ok then
			return
		end
		local separateCatalog = TowerSchema.validateCatalog(raw.towers, separateManifest.value)
		assertions.isTrue(separateCatalog.ok)
		if not separateCatalog.ok then
			return
		end
		local separatelyValidated = table.freeze({
			assets = separateManifest.value,
			towers = separateCatalog.value,
		})
		selected, selectionError = Fixtures.selectDefinition(separatelyValidated, Fixtures.SINGLE_TOWER_ID, 1)
		assertions.isNil(selected)
		assertions.equal(selectionError, Fixtures.INVALID_CONFIGURATION)

		local mismatched = table.freeze({
			assets = second.configuration.assets,
			towers = first.configuration.towers,
			enemies = first.configuration.enemies,
			difficulties = first.configuration.difficulties,
			maps = first.configuration.maps,
			waves = first.configuration.waves,
			economy = first.configuration.economy,
			banners = first.configuration.banners,
			defaultSettings = first.configuration.defaultSettings,
		})
		selected, selectionError = Fixtures.selectDefinition(mismatched, Fixtures.SINGLE_TOWER_ID, 1)
		assertions.isNil(selected)
		assertions.equal(selectionError, Fixtures.INVALID_CONFIGURATION)
		assertions.notEqual(first.single, second.single)
	end),
	TestHarness.case("contains all three inert fixture roles and metadata seams", function(assertions)
		local fixture = Fixtures.createAuthenticatedFixture()
		local single = fixture.single
		local splash = fixture.splash
		local support = fixture.support

		assertions.equal(Fixtures.TARGET_ELIGIBILITY, "AllEligibleEnemies")
		assertions.isNil((single :: any).targetEligibility)
		assertions.isNil((splash :: any).targetEligibility)
		assertions.isNil((support :: any).targetEligibility)
		assertions.equal(#single.levels, 3)
		assertions.equal(single.placementCost, 125)
		assertions.equal(single.footprintRadiusStuds, 1.5)
		assertions.equal(single.placementCap, 2)
		assertions.equal(single.defaultTargetMode, "First")
		assertions.equal(single.levels[2].upgradeCost, 100)
		assertions.equal(single.levels[3].upgradeCost, 0)
		assertions.equal(single.levels[2].attack.behavior.key, "attack.phase12-single")
		assertions.equal(single.levels[2].attack.statusEffects[1].key, "status.phase12-marked")
		assertions.equal(single.mergeProgression.key, "merge.phase12-single")

		assertions.equal(#splash.levels, 3)
		assertions.equal(splash.placementCost, 200)
		assertions.equal(splash.footprintRadiusStuds, 2.25)
		assertions.equal(splash.placementCap, 3)
		assertions.equal(splash.defaultTargetMode, "Strongest")
		assertions.equal(splash.levels[3].attack.behavior.key, "attack.phase12-splash")
		assertions.equal(splash.levels[3].attack.statusEffects[1].key, "status.phase12-slow")

		assertions.equal(#support.levels, 3)
		assertions.equal(support.placementCost, 100)
		assertions.equal(support.footprintRadiusStuds, 1.75)
		assertions.equal(support.placementCap, 1)
		assertions.equal(#support.supportedTargetModes, 0)
		assertions.isNil(support.defaultTargetMode)
		for _, level in support.levels do
			assertions.isNil(level.attack)
		end
		assertions.equal(support.tags[2], "support.phase12")
		assertions.equal(support.tags[3], "economy.phase12")
		assertions.equal(support.mergeProgression.key, "merge.phase12-support")
	end),
	TestHarness.case("direct schemas accept the fresh assets and towers in dependency order", function(assertions)
		local sources = Fixtures.rawSources()
		local manifestResult = AssetSchema.validateManifest(sources.assets)
		assertions.isTrue(manifestResult.ok)
		if not manifestResult.ok then
			return
		end

		local catalogResult = TowerSchema.validateCatalog(sources.towers, manifestResult.value)
		assertions.isTrue(catalogResult.ok)
		if not catalogResult.ok then
			return
		end
		assertions.isTrue(AssetSchema.isValidatedManifest(manifestResult.value))
		assertions.isTrue(TowerSchema.isValidatedCatalog(catalogResult.value))
		assertions.equal(#catalogResult.value.ordered, 3)
		assertions.equal(catalogResult.value.byId[Fixtures.SPLASH_TOWER_ID], catalogResult.value.ordered[2])
	end),
	TestHarness.case("rejects missing unknown and wrong-kind TowerModel assets", function(assertions)
		local missing = Fixtures.rawSources()
		missing.towers[1].modelAssetKey = nil
		expectTowerIssue(assertions, missing, "MISSING_FIELD", "Towers[1].modelAssetKey", nil)

		local unknown = Fixtures.rawSources()
		unknown.towers[1].modelAssetKey = "test.phase12.unknown-model"
		expectTowerIssue(assertions, unknown, "UNKNOWN_ASSET_KEY", "Towers[1].modelAssetKey", nil)

		local wrongKind = Fixtures.rawSources()
		wrongKind.towers[1].modelAssetKey = Fixtures.SINGLE_ICON_ASSET_KEY
		expectTowerIssue(assertions, wrongKind, "WRONG_ASSET_KIND", "Towers[1].modelAssetKey", nil)
	end),
	TestHarness.case("rejects duplicate TowerIds and malformed target modes", function(assertions)
		local duplicate = Fixtures.rawSources()
		duplicate.towers[2].id = duplicate.towers[1].id
		expectTowerIssue(assertions, duplicate, "DUPLICATE_ID", "Towers[2].id", "Towers[1].id")

		local invalidMode = Fixtures.rawSources()
		invalidMode.towers[1].supportedTargetModes[1] = "Nearest"
		expectTowerIssue(assertions, invalidMode, "INVALID_ENUM", "Towers[1].supportedTargetModes[1]", nil)

		local duplicateMode = Fixtures.rawSources()
		duplicateMode.towers[1].supportedTargetModes = { "First", "First" }
		expectTowerIssue(
			assertions,
			duplicateMode,
			"DUPLICATE_VALUE",
			"Towers[1].supportedTargetModes[2]",
			"Towers[1].supportedTargetModes[1]"
		)

		local unlistedDefault = Fixtures.rawSources()
		unlistedDefault.towers[1].defaultTargetMode = "Closest"
		expectTowerIssue(assertions, unlistedDefault, "INVALID_REFERENCE", "Towers[1].defaultTargetMode", nil)
	end),
	TestHarness.case("enforces attacking and non-attacking target cross-rules", function(assertions)
		local missingModes = Fixtures.rawSources()
		missingModes.towers[1].supportedTargetModes = {}
		expectTowerIssue(assertions, missingModes, "EMPTY_COLLECTION", "Towers[1].supportedTargetModes", nil)

		local missingDefault = Fixtures.rawSources()
		missingDefault.towers[1].defaultTargetMode = nil
		expectTowerIssue(assertions, missingDefault, "MISSING_FIELD", "Towers[1].defaultTargetMode", nil)

		local supportModes = Fixtures.rawSources()
		supportModes.towers[3].supportedTargetModes = { "First" }
		expectTowerIssue(assertions, supportModes, "INVALID_REFERENCE", "Towers[3].supportedTargetModes", nil)

		local supportDefault = Fixtures.rawSources()
		supportDefault.towers[3].defaultTargetMode = "First"
		expectTowerIssue(assertions, supportDefault, "INVALID_REFERENCE", "Towers[3].defaultTargetMode", nil)
	end),
	TestHarness.case("enforces placement and cumulative investment integer rules", function(assertions)
		local negativePlacement = Fixtures.rawSources()
		negativePlacement.towers[1].placementCost = -1
		expectTowerIssue(assertions, negativePlacement, "OUT_OF_RANGE", "Towers[1].placementCost", nil)

		local fractionalPlacement = Fixtures.rawSources()
		fractionalPlacement.towers[1].placementCost = 1.5
		expectTowerIssue(assertions, fractionalPlacement, "NOT_INTEGER", "Towers[1].placementCost", nil)

		local firstUpgrade = Fixtures.rawSources()
		firstUpgrade.towers[1].levels[1].upgradeCost = 1
		expectTowerIssue(assertions, firstUpgrade, "INVALID_ORDER", "Towers[1].levels[1].upgradeCost", nil)

		local negativeUpgrade = Fixtures.rawSources()
		negativeUpgrade.towers[1].levels[2].upgradeCost = -1
		expectTowerIssue(assertions, negativeUpgrade, "OUT_OF_RANGE", "Towers[1].levels[2].upgradeCost", nil)

		local overflow = Fixtures.rawSources()
		overflow.towers[1].placementCost = Validation.MAX_SAFE_INTEGER
		overflow.towers[1].levels[2].upgradeCost = 1
		expectTowerIssue(assertions, overflow, "OUT_OF_RANGE", "Towers[1].levels[2].upgradeCost", nil)
	end),
	TestHarness.case("accepts zero metadata edges and rejects invalid finite numbers", function(assertions)
		local zero = Fixtures.rawSources()
		zero.towers[1].levels[1].rangeStuds = 0
		zero.towers[1].levels[1].attack.damage = 0
		local zeroManifest = validatedManifest(assertions, zero)
		assertions.isNotNil(zeroManifest)
		if zeroManifest ~= nil then
			assertions.isTrue(TowerSchema.validateCatalog(zero.towers, zeroManifest).ok)
		end

		local footprintZero = Fixtures.rawSources()
		footprintZero.towers[1].footprintRadiusStuds = 0
		expectTowerIssue(assertions, footprintZero, "OUT_OF_RANGE", "Towers[1].footprintRadiusStuds", nil)

		local footprintNegative = Fixtures.rawSources()
		footprintNegative.towers[1].footprintRadiusStuds = -1
		expectTowerIssue(assertions, footprintNegative, "OUT_OF_RANGE", "Towers[1].footprintRadiusStuds", nil)

		local footprintNonfinite = Fixtures.rawSources()
		footprintNonfinite.towers[1].footprintRadiusStuds = math.huge
		expectTowerIssue(assertions, footprintNonfinite, "NON_FINITE_NUMBER", "Towers[1].footprintRadiusStuds", nil)

		local rangeNegative = Fixtures.rawSources()
		rangeNegative.towers[1].levels[1].rangeStuds = -1
		expectTowerIssue(assertions, rangeNegative, "OUT_OF_RANGE", "Towers[1].levels[1].rangeStuds", nil)

		local rangeNonfinite = Fixtures.rawSources()
		rangeNonfinite.towers[1].levels[1].rangeStuds = 0 / 0
		expectTowerIssue(assertions, rangeNonfinite, "NON_FINITE_NUMBER", "Towers[1].levels[1].rangeStuds", nil)
	end),
	TestHarness.case("rejects invalid damage cooldown and placement-cap values", function(assertions)
		local damageNegative = Fixtures.rawSources()
		damageNegative.towers[1].levels[1].attack.damage = -1
		expectTowerIssue(assertions, damageNegative, "OUT_OF_RANGE", "Towers[1].levels[1].attack.damage", nil)

		local damageNonfinite = Fixtures.rawSources()
		damageNonfinite.towers[1].levels[1].attack.damage = -math.huge
		expectTowerIssue(assertions, damageNonfinite, "NON_FINITE_NUMBER", "Towers[1].levels[1].attack.damage", nil)

		local cooldownZero = Fixtures.rawSources()
		cooldownZero.towers[1].levels[1].attack.cooldownSeconds = 0
		expectTowerIssue(assertions, cooldownZero, "OUT_OF_RANGE", "Towers[1].levels[1].attack.cooldownSeconds", nil)

		local cooldownNonfinite = Fixtures.rawSources()
		cooldownNonfinite.towers[1].levels[1].attack.cooldownSeconds = math.huge
		expectTowerIssue(
			assertions,
			cooldownNonfinite,
			"NON_FINITE_NUMBER",
			"Towers[1].levels[1].attack.cooldownSeconds",
			nil
		)

		local cooldownNegative = Fixtures.rawSources()
		cooldownNegative.towers[1].levels[1].attack.cooldownSeconds = -1
		expectTowerIssue(
			assertions,
			cooldownNegative,
			"OUT_OF_RANGE",
			"Towers[1].levels[1].attack.cooldownSeconds",
			nil
		)

		local capZero = Fixtures.rawSources()
		capZero.towers[1].placementCap = 0
		expectTowerIssue(assertions, capZero, "OUT_OF_RANGE", "Towers[1].placementCap", nil)

		local capFractional = Fixtures.rawSources()
		capFractional.towers[1].placementCap = 1.5
		expectTowerIssue(assertions, capFractional, "NOT_INTEGER", "Towers[1].placementCap", nil)

		local capNonfinite = Fixtures.rawSources()
		capNonfinite.towers[1].placementCap = math.huge
		expectTowerIssue(assertions, capNonfinite, "NON_FINITE_NUMBER", "Towers[1].placementCap", nil)
	end),
	TestHarness.case("rejects hostile tables unknown fields sparse arrays and bounds", function(assertions)
		local hostile = Fixtures.rawSources()
		setmetatable(hostile.towers[1], {})
		expectTowerIssue(assertions, hostile, "INVALID_TABLE", "Towers[1]", nil)

		local unknownField = Fixtures.rawSources()
		unknownField.towers[1].placementPreview = true
		expectTowerIssue(assertions, unknownField, "UNKNOWN_FIELD", "Towers[1].placementPreview", nil)

		local runtimeField = Fixtures.rawSources()
		runtimeField.towers[1].ownerUserId = 1
		expectTowerIssue(assertions, runtimeField, "RUNTIME_FIELD_FORBIDDEN", "Towers[1].ownerUserId", nil)

		local sparse = Fixtures.rawSources()
		sparse.towers[1].levels[2] = nil
		sparse.towers[1].levels[4] = { upgradeCost = 1, rangeStuds = 1 }
		expectTowerIssue(assertions, sparse, "INVALID_ARRAY", "Towers[1].levels", nil)

		local tooManyLevels = Fixtures.rawSources()
		local exemplar = deepCopy(tooManyLevels.towers[1].levels[1])
		for index = 4, Validation.MAX_LEVEL_ENTRIES + 1 do
			tooManyLevels.towers[1].levels[index] = deepCopy(exemplar)
		end
		expectTowerIssue(assertions, tooManyLevels, "OUT_OF_RANGE", "Towers[1].levels", nil)

		local tooManyFields = Fixtures.rawSources()
		for index = 1, 65 do
			tooManyFields.towers[1]["field" .. tostring(index)] = true
		end
		expectTowerIssue(assertions, tooManyFields, "INVALID_TABLE", "Towers[1]", nil)

		local tooManyTowers = Fixtures.rawSources()
		local towerExemplar = deepCopy(tooManyTowers.towers[1])
		for index = 4, Validation.MAX_CATALOG_ENTRIES + 1 do
			tooManyTowers.towers[index] = deepCopy(towerExemplar)
		end
		expectTowerIssue(assertions, tooManyTowers, "OUT_OF_RANGE", "Towers", nil)
	end),
	TestHarness.case("isolates canonical output from raw mutation and future fixture calls", function(assertions)
		local raw = Fixtures.rawSources()
		local fixture = Fixtures.authenticateSources(raw)
		local fresh = Fixtures.rawSources()

		raw.assets[1].key = "mutated.asset"
		raw.towers[1].displayName = "Mutated Tower"
		raw.towers[1].levels[1].attack.damage = 9_999
		raw.towers[3].tags[2] = "mutated.support"

		assertions.equal(fixture.single.modelAssetKey, Fixtures.SINGLE_MODEL_ASSET_KEY)
		assertions.equal(fixture.single.displayName, "Phase 12 Single")
		assertions.equal(fixture.single.levels[1].attack.damage, 8)
		assertions.equal(fixture.support.tags[2], "support.phase12")
		assertions.equal(fresh.assets[1].key, Fixtures.SINGLE_MODEL_ASSET_KEY)
		assertions.equal(fresh.towers[1].displayName, "Phase 12 Single")
		assertions.equal(fresh.towers[1].levels[1].attack.damage, 8)
		assertions.equal(fresh.towers[3].tags[2], "support.phase12")
		assertions.notEqual(raw, fresh)
		assertions.notEqual(raw.towers[1], fresh.towers[1])
		assertions.isTrue(table.isfrozen(fixture.single.levels[1].attack))
	end),
	TestHarness.case("keeps production Asset and Tower sources frozen and empty", function(assertions)
		assertions.isTrue(table.isfrozen(ProductionAssets))
		assertions.isTrue(table.isfrozen(ProductionTowers))
		assertions.equal(#ProductionAssets, 0)
		assertions.equal(#ProductionTowers, 0)
	end),
})
