--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Fixtures = require(script.Parent.Parent.Fixtures.ConfigurationFixtures)

local Shared = game:GetService("ReplicatedStorage").Shared
local AssetSchema = require(Shared.config.AssetSchema)
local BannerSchema = require(Shared.config.BannerSchema)
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local DifficultySchema = require(Shared.config.DifficultySchema)
local EconomySchema = require(Shared.config.EconomySchema)
local EnemySchema = require(Shared.config.EnemySchema)
local MapSchema = require(Shared.config.MapSchema)
local SettingsSchema = require(Shared.config.SettingsSchema)
local TowerSchema = require(Shared.config.TowerSchema)
local WaveSchema = require(Shared.config.WaveSchema)

type Assertions = TestHarness.Assertions

local function expectIssue(assertions: Assertions, result: any, code: string, path: string, relatedPath: string?): any
	assertions.isFalse(result.ok)
	if result.ok then
		return nil
	end

	local issue = result.error
	assertions.equal(issue.code, code)
	assertions.equal(issue.path, path)
	assertions.equal(issue.relatedPath, relatedPath)
	assertions.isTrue(table.isfrozen(issue))
	assertions.isTrue(table.isfrozen(issue.pathSegments))
	return issue
end

local function canonicalDependencies(): ({ [string]: any }, { [string]: any })
	local sources = Fixtures.validSources()
	local assetsResult = AssetSchema.validateManifest(sources.assets)
	if not assetsResult.ok then
		error("fixture assets failed validation", 0)
	end
	local assets = assetsResult.value

	local towersResult = TowerSchema.validateCatalog(sources.towers, assets)
	local enemiesResult = EnemySchema.validateCatalog(sources.enemies, assets)
	local difficultiesResult = DifficultySchema.validateCatalog(sources.difficulties, assets)
	if not towersResult.ok or not enemiesResult.ok or not difficultiesResult.ok then
		error("fixture definition catalog failed validation", 0)
	end

	local mapsResult = MapSchema.validateCatalog(sources.maps, assets, difficultiesResult.value)
	if not mapsResult.ok then
		error("fixture map catalog failed validation", 0)
	end

	return sources,
		{
			assets = assets,
			towers = towersResult.value,
			enemies = enemiesResult.value,
			difficulties = difficultiesResult.value,
			maps = mapsResult.value,
		}
end

local function issueText(issue: any): string
	return table.concat({
		tostring(issue.code),
		tostring(issue.path),
		tostring(issue.message),
		tostring(issue.causeCode),
		tostring(issue.relatedPath),
		tostring(issue.actualType),
	}, "|")
end

return TestHarness.suite("configuration schema failures", {
	TestHarness.case("rejects duplicate assets with an exact related path", function(assertions)
		local sources = Fixtures.validSources()
		sources.assets[6] = Fixtures.clone(sources.assets[1])
		expectIssue(
			assertions,
			AssetSchema.validateManifest(sources.assets),
			"DUPLICATE_ASSET_KEY",
			"Assets[6].key",
			"Assets[1].key"
		)
	end),
	TestHarness.case("rejects duplicate definition IDs in deterministic authored order", function(assertions)
		local sources, canonical = canonicalDependencies()

		local towers = Fixtures.clone(sources.towers)
		towers[2].id = towers[1].id
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"DUPLICATE_ID",
			"Towers[2].id",
			"Towers[1].id"
		)

		local enemies = Fixtures.clone(sources.enemies)
		enemies[2] = Fixtures.clone(enemies[1])
		expectIssue(
			assertions,
			EnemySchema.validateCatalog(enemies, canonical.assets),
			"DUPLICATE_ID",
			"Enemies[2].id",
			"Enemies[1].id"
		)

		local difficulties = Fixtures.clone(sources.difficulties)
		difficulties[2].id = difficulties[1].id
		expectIssue(
			assertions,
			DifficultySchema.validateCatalog(difficulties, canonical.assets),
			"DUPLICATE_ID",
			"Difficulties[2].id",
			"Difficulties[1].id"
		)

		local maps = Fixtures.clone(sources.maps)
		maps[2] = Fixtures.clone(maps[1])
		expectIssue(
			assertions,
			MapSchema.validateCatalog(maps, canonical.assets, canonical.difficulties),
			"DUPLICATE_ID",
			"Maps[2].id",
			"Maps[1].id"
		)

		local banners = Fixtures.clone(sources.banners)
		banners[2] = Fixtures.clone(banners[1])
		expectIssue(
			assertions,
			BannerSchema.validateCatalog(banners, canonical.towers),
			"DUPLICATE_ID",
			"Banners[2].id",
			"Banners[1].id"
		)
	end),
	TestHarness.case("rejects duplicate wave IDs and schedule pairs with stable related paths", function(assertions)
		local sources, canonical = canonicalDependencies()
		local waves = Fixtures.clone(sources.waves)
		waves[2].authoredOpeningWaves[1].id = waves[1].waves[1].id
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"DUPLICATE_ID",
			"WaveSchedules[2].authoredOpeningWaves[1].id",
			"WaveSchedules[1].waves[1].id"
		)

		waves = Fixtures.clone(sources.waves)
		waves[3] = Fixtures.clone(waves[1])
		waves[3].waves[1].id = "wave:duplicate-pair-1"
		waves[3].waves[2].id = "wave:duplicate-pair-2"
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"DUPLICATE_VALUE",
			"WaveSchedules[3].difficultyId",
			"WaveSchedules[1].difficultyId"
		)
	end),
	TestHarness.case("rejects undeclared and wrong-kind symbolic assets", function(assertions)
		local sources, canonical = canonicalDependencies()
		local towers = Fixtures.clone(sources.towers)
		towers[1].modelAssetKey = "missing.tower-model"
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"UNKNOWN_ASSET_KEY",
			"Towers[1].modelAssetKey",
			nil
		)

		towers = Fixtures.clone(sources.towers)
		towers[1].modelAssetKey = "icon.worker"
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"WRONG_ASSET_KIND",
			"Towers[1].modelAssetKey",
			nil
		)

		local maps = Fixtures.clone(sources.maps)
		maps[1].modelAssetKey = "tower.worker-model"
		expectIssue(
			assertions,
			MapSchema.validateCatalog(maps, canonical.assets, canonical.difficulties),
			"WRONG_ASSET_KIND",
			"Maps[1].modelAssetKey",
			nil
		)
	end),
	TestHarness.case("rejects map to difficulty reference failures", function(assertions)
		local sources, canonical = canonicalDependencies()
		local maps = Fixtures.clone(sources.maps)
		maps[1].supportedDifficultyIds[1] = "difficulty:missing"
		expectIssue(
			assertions,
			MapSchema.validateCatalog(maps, canonical.assets, canonical.difficulties),
			"INVALID_REFERENCE",
			"Maps[1].supportedDifficultyIds[1]",
			nil
		)

		maps = Fixtures.clone(sources.maps)
		maps[1].supportedDifficultyIds[1] = "map:garden"
		local issue = expectIssue(
			assertions,
			MapSchema.validateCatalog(maps, canonical.assets, canonical.difficulties),
			"INVALID_ID",
			"Maps[1].supportedDifficultyIds[1]",
			nil
		)
		assertions.equal(issue.causeCode, "WRONG_KIND")
	end),
	TestHarness.case("rejects wave map difficulty enemy and lane references", function(assertions)
		local sources, canonical = canonicalDependencies()
		local waves = Fixtures.clone(sources.waves)
		waves[1].mapId = "map:missing"
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_REFERENCE",
			"WaveSchedules[1].mapId",
			nil
		)

		waves = Fixtures.clone(sources.waves)
		waves[1].difficultyId = "difficulty:missing"
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_REFERENCE",
			"WaveSchedules[1].difficultyId",
			nil
		)

		waves = Fixtures.clone(sources.waves)
		waves[1].waves[1].groups[1].enemyId = "enemy:missing"
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_REFERENCE",
			"WaveSchedules[1].waves[1].groups[1].enemyId",
			nil
		)

		waves = Fixtures.clone(sources.waves)
		waves[1].waves[1].groups[1].laneId = "lane.missing"
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_REFERENCE",
			"WaveSchedules[1].waves[1].groups[1].laneId",
			nil
		)
	end),
	TestHarness.case("rejects unsupported map and difficulty schedule pairs", function(assertions)
		local sources, canonical = canonicalDependencies()
		local maps = Fixtures.clone(sources.maps)
		maps[1].supportedDifficultyIds = { "difficulty:normal" }
		local mapResult = MapSchema.validateCatalog(maps, canonical.assets, canonical.difficulties)
		assertions.isTrue(mapResult.ok)
		if not mapResult.ok then
			return
		end

		expectIssue(
			assertions,
			WaveSchema.validateCatalog(sources.waves, mapResult.value, canonical.difficulties, canonical.enemies),
			"INVALID_REFERENCE",
			"WaveSchedules[2].difficultyId",
			nil
		)
	end),
	TestHarness.case(
		"rejects economy difficulty duplicates unknown references and missing coverage",
		function(assertions)
			local sources, canonical = canonicalDependencies()
			local economy = Fixtures.clone(sources.economy)
			economy.difficultyRules[2].difficultyId = economy.difficultyRules[1].difficultyId
			expectIssue(
				assertions,
				EconomySchema.validateConfiguration(economy, canonical.difficulties),
				"DUPLICATE_VALUE",
				"Economy.difficultyRules[2].difficultyId",
				"Economy.difficultyRules[1].difficultyId"
			)

			economy = Fixtures.clone(sources.economy)
			economy.difficultyRules[1].difficultyId = "difficulty:missing"
			expectIssue(
				assertions,
				EconomySchema.validateConfiguration(economy, canonical.difficulties),
				"INVALID_REFERENCE",
				"Economy.difficultyRules[1].difficultyId",
				nil
			)

			economy = Fixtures.clone(sources.economy)
			table.remove(economy.difficultyRules, 2)
			expectIssue(
				assertions,
				EconomySchema.validateConfiguration(economy, canonical.difficulties),
				"INVALID_REFERENCE",
				"Difficulties[2].id",
				nil
			)
		end
	),
	TestHarness.case("rejects banner tower and pity references", function(assertions)
		local sources, canonical = canonicalDependencies()
		local banners = Fixtures.clone(sources.banners)
		banners[1].outcomes[1].towerId = "tower:missing"
		expectIssue(
			assertions,
			BannerSchema.validateCatalog(banners, canonical.towers),
			"INVALID_REFERENCE",
			"Banners[1].outcomes[1].towerId",
			nil
		)

		banners = Fixtures.clone(sources.banners)
		banners[1].pityRule.guaranteedTowerId = "tower:missing"
		expectIssue(
			assertions,
			BannerSchema.validateCatalog(banners, canonical.towers),
			"INVALID_REFERENCE",
			"Banners[1].pityRule.guaranteedTowerId",
			nil
		)

		banners = Fixtures.clone(sources.banners)
		banners[1].outcomes = { { towerId = "tower:worker", probabilityPercent = 100 } }
		expectIssue(
			assertions,
			BannerSchema.validateCatalog(banners, canonical.towers),
			"INVALID_REFERENCE",
			"Banners[1].pityRule.guaranteedTowerId",
			nil
		)
	end),
	TestHarness.case("enforces probability totals floor and inclusive tolerance", function(assertions)
		local sources, canonical = canonicalDependencies()
		local banners = Fixtures.clone(sources.banners)
		banners[1].outcomes[1].probabilityPercent = 60 + 1e-9
		assertions.isTrue(BannerSchema.validateCatalog(banners, canonical.towers).ok)

		banners = Fixtures.clone(sources.banners)
		banners[1].outcomes[1].probabilityPercent = 60 + 2e-9
		expectIssue(
			assertions,
			BannerSchema.validateCatalog(banners, canonical.towers),
			"INVALID_TOTAL",
			"Banners[1].outcomes",
			nil
		)

		banners = Fixtures.clone(sources.banners)
		banners[1].outcomes[1].probabilityPercent = 0
		expectIssue(
			assertions,
			BannerSchema.validateCatalog(banners, canonical.towers),
			"OUT_OF_RANGE",
			"Banners[1].outcomes[1].probabilityPercent",
			nil
		)
	end),
	TestHarness.case("accepts documented numeric boundaries and rejects nonfinite values", function(assertions)
		local sources, canonical = canonicalDependencies()

		local settings = Fixtures.clone(sources.defaultSettings)
		settings.masterVolume = 0
		settings.musicVolume = 1
		settings.uiScale = 0.75
		settings.cameraShakeIntensity = 0
		assertions.isTrue(SettingsSchema.validateDefaults(settings).ok)

		settings = Fixtures.clone(sources.defaultSettings)
		settings.masterVolume = math.huge
		expectIssue(
			assertions,
			SettingsSchema.validateDefaults(settings),
			"NON_FINITE_NUMBER",
			"DefaultSettings.masterVolume",
			nil
		)

		local towers = Fixtures.clone(sources.towers)
		towers[1].footprintRadiusStuds = 0
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"OUT_OF_RANGE",
			"Towers[1].footprintRadiusStuds",
			nil
		)

		local enemies = Fixtures.clone(sources.enemies)
		enemies[1].maxHealth = 0 / 0
		expectIssue(
			assertions,
			EnemySchema.validateCatalog(enemies, canonical.assets),
			"NON_FINITE_NUMBER",
			"Enemies[1].maxHealth",
			nil
		)

		local economy = Fixtures.clone(sources.economy)
		economy.sellRefund.basisPoints = 10_000
		assertions.isTrue(EconomySchema.validateConfiguration(economy, canonical.difficulties).ok)
	end),
	TestHarness.case("rejects unreduced economy rates and unsupported settings versions", function(assertions)
		local sources, canonical = canonicalDependencies()
		local economy = Fixtures.clone(sources.economy)
		economy.difficultyRules[1].damageIncome.battleCashNumerator = 2
		economy.difficultyRules[1].damageIncome.healthRemovedDenominator = 10
		expectIssue(
			assertions,
			EconomySchema.validateConfiguration(economy, canonical.difficulties),
			"INVALID_ORDER",
			"Economy.difficultyRules[1].damageIncome.healthRemovedDenominator",
			nil
		)

		local settings = Fixtures.clone(sources.defaultSettings)
		settings.version = 2
		expectIssue(
			assertions,
			SettingsSchema.validateDefaults(settings),
			"UNSUPPORTED_VERSION",
			"DefaultSettings.version",
			nil
		)
	end),
	TestHarness.case("rejects forged downstream dependencies before lookup", function(assertions)
		local sources = Fixtures.validSources()
		local forged = table.freeze({ ordered = table.freeze({}), byId = table.freeze({}) })
		local forgedManifest = table.freeze({ ordered = table.freeze({}), byKey = table.freeze({}) })

		expectIssue(
			assertions,
			TowerSchema.validateCatalog(sources.towers, forgedManifest),
			"INVALID_REFERENCE",
			"AssetManifest",
			nil
		)
		expectIssue(
			assertions,
			EnemySchema.validateCatalog(sources.enemies, forgedManifest),
			"INVALID_REFERENCE",
			"AssetManifest",
			nil
		)
		expectIssue(
			assertions,
			DifficultySchema.validateCatalog(sources.difficulties, forgedManifest),
			"INVALID_REFERENCE",
			"AssetManifest",
			nil
		)
		expectIssue(
			assertions,
			MapSchema.validateCatalog(sources.maps, forgedManifest, forged),
			"INVALID_REFERENCE",
			"AssetManifest",
			nil
		)
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(sources.waves, forged, forged, forged),
			"INVALID_REFERENCE",
			"MapCatalog",
			nil
		)
		expectIssue(
			assertions,
			EconomySchema.validateConfiguration(sources.economy, forged),
			"INVALID_REFERENCE",
			"DifficultyCatalog",
			nil
		)
		expectIssue(
			assertions,
			BannerSchema.validateCatalog(sources.banners, forged),
			"INVALID_REFERENCE",
			"TowerCatalog",
			nil
		)
	end),
	TestHarness.case("keeps issue and blocked family order deterministic", function(assertions)
		local expectedSignature: string? = nil
		for _ = 1, 5 do
			local sources = Fixtures.validSources()
			sources.assets = "invalid assets"
			sources.defaultSettings.version = 2
			local result = ConfigurationValidator.validate(sources)
			assertions.isFalse(result.ok)
			if result.ok then
				return
			end

			local report = result.error
			assertions.equal(report.firstIssue, report.issues[1])
			assertions.equal(report.issues[1].code, "INVALID_TYPE")
			assertions.equal(report.issues[1].path, "Assets")
			assertions.equal(report.issues[2].code, "UNSUPPORTED_VERSION")
			assertions.equal(report.issues[2].path, "DefaultSettings.version")
			local signature = table.concat({
				report.issues[1].code,
				report.issues[1].path,
				report.issues[2].code,
				report.issues[2].path,
				table.concat(report.blockedFamilies, ","),
			}, "|")
			if expectedSignature == nil then
				expectedSignature = signature
			else
				assertions.equal(signature, expectedSignature)
			end
		end

		assertions.equal(
			expectedSignature,
			"INVALID_TYPE|Assets|UNSUPPORTED_VERSION|DefaultSettings.version|Towers,Enemies,Difficulties,Maps,WaveSchedules,Economy,Banners"
		)
	end),
	TestHarness.case("fails malformed configuration roots with every family blocked", function(assertions)
		local result = ConfigurationValidator.validate(nil)
		assertions.isFalse(result.ok)
		if result.ok then
			return
		end

		local report = result.error
		assertions.equal(report.firstIssue.code, "INVALID_TYPE")
		assertions.equal(report.firstIssue.path, "Configuration")
		assertions.equal(#report.issues, 1)
		assertions.equal(#report.blockedFamilies, ConfigurationValidator.FAMILY_COUNT)
		assertions.equal(report.blockedFamilies[1], "Assets")
		assertions.equal(report.blockedFamilies[9], "DefaultSettings")
		assertions.isTrue(table.isfrozen(report))
		assertions.isTrue(table.isfrozen(report.issues))
		assertions.isTrue(table.isfrozen(report.blockedFamilies))
	end),
	TestHarness.case("fails every malformed schema root at its actionable family path", function(assertions)
		local _, canonical = canonicalDependencies()
		expectIssue(assertions, AssetSchema.validateManifest(nil), "INVALID_TYPE", "Assets", nil)
		expectIssue(assertions, TowerSchema.validateCatalog(nil, canonical.assets), "INVALID_TYPE", "Towers", nil)
		expectIssue(assertions, EnemySchema.validateCatalog(nil, canonical.assets), "INVALID_TYPE", "Enemies", nil)
		expectIssue(
			assertions,
			DifficultySchema.validateCatalog(nil, canonical.assets),
			"INVALID_TYPE",
			"Difficulties",
			nil
		)
		expectIssue(
			assertions,
			MapSchema.validateCatalog(nil, canonical.assets, canonical.difficulties),
			"INVALID_TYPE",
			"Maps",
			nil
		)
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(nil, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_TYPE",
			"WaveSchedules",
			nil
		)
		expectIssue(
			assertions,
			EconomySchema.validateConfiguration(nil, canonical.difficulties),
			"INVALID_TYPE",
			"Economy",
			nil
		)
		expectIssue(assertions, BannerSchema.validateCatalog(nil, canonical.towers), "INVALID_TYPE", "Banners", nil)
		expectIssue(assertions, SettingsSchema.validateDefaults(nil), "INVALID_TYPE", "DefaultSettings", nil)
	end),
	TestHarness.case("never echoes rejected private values or catalogs in observable issues", function(assertions)
		local sources, canonical = canonicalDependencies()
		local privateValue = "PRIVATE_CONFIGURATION_SENTINEL_8491"
		local towers = Fixtures.clone(sources.towers)
		towers[1].displayName = ` {privateValue}`
		local issue = expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"INVALID_STRING",
			"Towers[1].displayName",
			nil
		)
		assertions.isFalse(string.find(issueText(issue), privateValue, 1, true) ~= nil)

		local settings = Fixtures.clone(sources.defaultSettings)
		settings.masterVolume = { secret = privateValue, catalog = sources }
		issue = expectIssue(
			assertions,
			SettingsSchema.validateDefaults(settings),
			"INVALID_TYPE",
			"DefaultSettings.masterVolume",
			nil
		)
		assertions.isFalse(string.find(issueText(issue), privateValue, 1, true) ~= nil)
	end),
})
