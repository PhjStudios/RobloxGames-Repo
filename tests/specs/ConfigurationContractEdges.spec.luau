--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Fixtures = require(script.Parent.Parent.Fixtures.ConfigurationFixtures)

local Shared = game:GetService("ReplicatedStorage").Shared
local AssetSchema = require(Shared.config.AssetSchema)
local BannerSchema = require(Shared.config.BannerSchema)
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local DifficultySchema = require(Shared.config.DifficultySchema)
local EnemySchema = require(Shared.config.EnemySchema)
local MapSchema = require(Shared.config.MapSchema)
local SettingsSchema = require(Shared.config.SettingsSchema)
local TowerSchema = require(Shared.config.TowerSchema)
local WaveSchema = require(Shared.config.WaveSchema)
local Validation = require(Shared.util.Validation)

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

local function expectConfigurationReport(assertions: Assertions, sources: { [string]: any }): any
	local result = ConfigurationValidator.validate(sources)
	assertions.isFalse(result.ok)
	if result.ok then
		return nil
	end
	return result.error
end

return TestHarness.suite("configuration public contract edges", {
	TestHarness.case("enforces Tower level ordering and cumulative safe-integer investment", function(assertions)
		local sources, canonical = canonicalDependencies()
		local towers = Fixtures.clone(sources.towers)
		towers[1].levels[1].upgradeCost = 1
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"INVALID_ORDER",
			"Towers[1].levels[1].upgradeCost",
			nil
		)

		towers = Fixtures.clone(sources.towers)
		towers[1].placementCost = Validation.MAX_SAFE_INTEGER
		towers[1].levels[2].upgradeCost = 1
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"OUT_OF_RANGE",
			"Towers[1].levels[2].upgradeCost",
			nil
		)

		towers = Fixtures.clone(sources.towers)
		towers[1].placementCost = Validation.MAX_SAFE_INTEGER
		towers[1].levels[2].upgradeCost = 0
		assertions.isTrue(TowerSchema.validateCatalog(towers, canonical.assets).ok)
	end),
	TestHarness.case("enforces attacking and non-attacking Tower target-mode contracts", function(assertions)
		local sources, canonical = canonicalDependencies()
		local towers = Fixtures.clone(sources.towers)
		towers[1].supportedTargetModes = {}
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"EMPTY_COLLECTION",
			"Towers[1].supportedTargetModes",
			nil
		)

		towers = Fixtures.clone(sources.towers)
		towers[1].defaultTargetMode = "Last"
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"INVALID_REFERENCE",
			"Towers[1].defaultTargetMode",
			nil
		)

		towers = Fixtures.clone(sources.towers)
		towers[2].supportedTargetModes = { "First" }
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"INVALID_REFERENCE",
			"Towers[2].supportedTargetModes",
			nil
		)

		towers = Fixtures.clone(sources.towers)
		towers[2].defaultTargetMode = "First"
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"INVALID_REFERENCE",
			"Towers[2].defaultTargetMode",
			nil
		)
	end),
	TestHarness.case("accepts and rejects Tower numeric edges without coercion", function(assertions)
		local sources, canonical = canonicalDependencies()
		local towers = Fixtures.clone(sources.towers)
		towers[1].levels[1].attack.damage = 0
		towers[1].levels[1].rangeStuds = 0
		assertions.isTrue(TowerSchema.validateCatalog(towers, canonical.assets).ok)

		towers = Fixtures.clone(sources.towers)
		towers[1].levels[1].attack.cooldownSeconds = math.huge
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"NON_FINITE_NUMBER",
			"Towers[1].levels[1].attack.cooldownSeconds",
			nil
		)

		towers = Fixtures.clone(sources.towers)
		towers[1].levels[1].attack.damage = -math.huge
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"NON_FINITE_NUMBER",
			"Towers[1].levels[1].attack.damage",
			nil
		)
	end),
	TestHarness.case("enforces Finite and Endless Difficulty discrimination", function(assertions)
		local sources, canonical = canonicalDependencies()
		local difficulties = Fixtures.clone(sources.difficulties)
		difficulties[1].waveCount = nil
		expectIssue(
			assertions,
			DifficultySchema.validateCatalog(difficulties, canonical.assets),
			"MISSING_FIELD",
			"Difficulties[1].waveCount",
			nil
		)

		difficulties = Fixtures.clone(sources.difficulties)
		difficulties[2].waveCount = 1
		expectIssue(
			assertions,
			DifficultySchema.validateCatalog(difficulties, canonical.assets),
			"INVALID_REFERENCE",
			"Difficulties[2].waveCount",
			nil
		)

		difficulties = Fixtures.clone(sources.difficulties)
		difficulties[1].waveCount = 1_001
		expectIssue(
			assertions,
			DifficultySchema.validateCatalog(difficulties, canonical.assets),
			"OUT_OF_RANGE",
			"Difficulties[1].waveCount",
			nil
		)
	end),
	TestHarness.case("accepts exact Difficulty bounds and rejects finite overflow inputs", function(assertions)
		local sources, canonical = canonicalDependencies()
		local difficulties = Fixtures.clone(sources.difficulties)
		local finite = difficulties[1]
		finite.base.maxHealth = Validation.MAX_SAFE_INTEGER
		finite.modifiers.enemyHealthMultiplier = Validation.MIN_DIFFICULTY_MULTIPLIER
		finite.modifiers.enemyMoveSpeedMultiplier = Validation.MAX_DIFFICULTY_MULTIPLIER
		finite.timing.earlyClearIntermissionSeconds = 0
		finite.timing.bossCadenceWaves = 1_000
		finite.timing.skipVoteMinimumDelaySeconds = Validation.MAX_WAVE_TIME_SECONDS
		assertions.isTrue(DifficultySchema.validateCatalog(difficulties, canonical.assets).ok)

		difficulties = Fixtures.clone(sources.difficulties)
		difficulties[1].modifiers.enemyHealthMultiplier = Validation.MIN_DIFFICULTY_MULTIPLIER / 2
		expectIssue(
			assertions,
			DifficultySchema.validateCatalog(difficulties, canonical.assets),
			"OUT_OF_RANGE",
			"Difficulties[1].modifiers.enemyHealthMultiplier",
			nil
		)

		difficulties = Fixtures.clone(sources.difficulties)
		difficulties[1].modifiers.enemyMoveSpeedMultiplier = 0 / 0
		expectIssue(
			assertions,
			DifficultySchema.validateCatalog(difficulties, canonical.assets),
			"NON_FINITE_NUMBER",
			"Difficulties[1].modifiers.enemyMoveSpeedMultiplier",
			nil
		)

		difficulties = Fixtures.clone(sources.difficulties)
		difficulties[1].timing.earlyClearIntermissionSeconds = Validation.MAX_WAVE_TIME_SECONDS + 1
		expectIssue(
			assertions,
			DifficultySchema.validateCatalog(difficulties, canonical.assets),
			"OUT_OF_RANGE",
			"Difficulties[1].timing.earlyClearIntermissionSeconds",
			nil
		)
	end),
	TestHarness.case("enforces Wave schedule discrimination and reverse coverage", function(assertions)
		local sources, canonical = canonicalDependencies()
		local waves = Fixtures.clone(sources.waves)
		waves[1].kind = "GeneratedEndless"
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_REFERENCE",
			"WaveSchedules[1].kind",
			nil
		)

		waves = Fixtures.clone(sources.waves)
		waves[2].kind = "AuthoredFinite"
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_REFERENCE",
			"WaveSchedules[2].kind",
			nil
		)

		waves = Fixtures.clone(sources.waves)
		table.remove(waves, 2)
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_REFERENCE",
			"Maps[1].supportedDifficultyIds[2]",
			nil
		)

		waves = Fixtures.clone(sources.waves)
		table.remove(waves[1].waves, 2)
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_ORDER",
			"WaveSchedules[1].waves",
			nil
		)
	end),
	TestHarness.case("enforces Wave deadline tolerance and chronological group order", function(assertions)
		local sources, canonical = canonicalDependencies()
		local waves = Fixtures.clone(sources.waves)
		waves[1].waves[1].deadlineSeconds = 2 - 1e-9
		assertions.isTrue(
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies).ok
		)

		waves = Fixtures.clone(sources.waves)
		waves[1].waves[1].deadlineSeconds = 2 - 1e-8
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_ORDER",
			"WaveSchedules[1].waves[1].groups[1].spawnIntervalSeconds",
			nil
		)

		waves = Fixtures.clone(sources.waves)
		local firstGroup = waves[1].waves[1].groups[1]
		firstGroup.startDelaySeconds = 1
		waves[1].waves[1].groups[2] = Fixtures.clone(firstGroup)
		waves[1].waves[1].groups[2].startDelaySeconds = 0
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_ORDER",
			"WaveSchedules[1].waves[1].groups[2].startDelaySeconds",
			"WaveSchedules[1].waves[1].groups[1].startDelaySeconds"
		)

		waves = Fixtures.clone(sources.waves)
		waves[1].waves[1].deadlineSeconds = math.huge
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"NON_FINITE_NUMBER",
			"WaveSchedules[1].waves[1].deadlineSeconds",
			nil
		)
	end),
	TestHarness.case("enforces Wave cadence and reward metadata ordering", function(assertions)
		local sources, canonical = canonicalDependencies()
		local waves = Fixtures.clone(sources.waves)
		waves[1].waves[1].bossKind = "Boss"
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_ORDER",
			"WaveSchedules[1].waves[1].bossKind",
			nil
		)

		waves = Fixtures.clone(sources.waves)
		waves[1].waves[2].bossKind = "None"
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_ORDER",
			"WaveSchedules[1].waves[2].bossKind",
			nil
		)

		waves = Fixtures.clone(sources.waves)
		waves[1].waves[1].rewardClass = "Milestone"
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_ORDER",
			"WaveSchedules[1].waves[1].rewardClass",
			nil
		)

		waves = Fixtures.clone(sources.waves)
		waves[1].waves[2].rewardClass = "Milestone"
		expectIssue(
			assertions,
			WaveSchema.validateCatalog(waves, canonical.maps, canonical.difficulties, canonical.enemies),
			"INVALID_ORDER",
			"WaveSchedules[1].waves[2].rewardClass",
			nil
		)
	end),
	TestHarness.case("rejects derived Enemy and Difficulty stat overflow at the Wave reference", function(assertions)
		local sources = Fixtures.validSources()
		local assetsResult = AssetSchema.validateManifest(sources.assets)
		assertions.isTrue(assetsResult.ok)
		if not assetsResult.ok then
			return
		end

		sources.enemies[1].maxHealth = 1e308
		sources.difficulties[1].modifiers.enemyHealthMultiplier = Validation.MAX_DIFFICULTY_MULTIPLIER
		local enemiesResult = EnemySchema.validateCatalog(sources.enemies, assetsResult.value)
		local difficultiesResult = DifficultySchema.validateCatalog(sources.difficulties, assetsResult.value)
		assertions.isTrue(enemiesResult.ok)
		assertions.isTrue(difficultiesResult.ok)
		if not enemiesResult.ok or not difficultiesResult.ok then
			return
		end

		local mapsResult = MapSchema.validateCatalog(sources.maps, assetsResult.value, difficultiesResult.value)
		assertions.isTrue(mapsResult.ok)
		if not mapsResult.ok then
			return
		end

		expectIssue(
			assertions,
			WaveSchema.validateCatalog(sources.waves, mapsResult.value, difficultiesResult.value, enemiesResult.value),
			"OUT_OF_RANGE",
			"WaveSchedules[1].waves[1].groups[1].enemyId",
			nil
		)
	end),
	TestHarness.case("rejects duplicate Tower target tag and feature references", function(assertions)
		local sources, canonical = canonicalDependencies()
		local towers = Fixtures.clone(sources.towers)
		towers[1].supportedTargetModes = { "First", "First" }
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"DUPLICATE_VALUE",
			"Towers[1].supportedTargetModes[2]",
			"Towers[1].supportedTargetModes[1]"
		)

		towers = Fixtures.clone(sources.towers)
		towers[1].tags = { "fixture", "fixture" }
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"DUPLICATE_VALUE",
			"Towers[1].tags[2]",
			"Towers[1].tags[1]"
		)

		towers = Fixtures.clone(sources.towers)
		local status = Fixtures.clone(towers[1].levels[1].attack.statusEffects[1])
		towers[1].levels[1].attack.statusEffects[2] = status
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"DUPLICATE_VALUE",
			"Towers[1].levels[1].attack.statusEffects[2].key",
			"Towers[1].levels[1].attack.statusEffects[1].key"
		)
	end),
	TestHarness.case("rejects duplicate Enemy Map and Banner references", function(assertions)
		local sources, canonical = canonicalDependencies()
		local enemies = Fixtures.clone(sources.enemies)
		enemies[1].behaviors[2] = Fixtures.clone(enemies[1].behaviors[1])
		expectIssue(
			assertions,
			EnemySchema.validateCatalog(enemies, canonical.assets),
			"DUPLICATE_VALUE",
			"Enemies[1].behaviors[2].key",
			"Enemies[1].behaviors[1].key"
		)

		local maps = Fixtures.clone(sources.maps)
		maps[1].lanes[2] = { id = "lane.main" }
		expectIssue(
			assertions,
			MapSchema.validateCatalog(maps, canonical.assets, canonical.difficulties),
			"DUPLICATE_VALUE",
			"Maps[1].lanes[2].id",
			"Maps[1].lanes[1].id"
		)

		maps = Fixtures.clone(sources.maps)
		maps[1].supportedDifficultyIds[2] = maps[1].supportedDifficultyIds[1]
		expectIssue(
			assertions,
			MapSchema.validateCatalog(maps, canonical.assets, canonical.difficulties),
			"DUPLICATE_VALUE",
			"Maps[1].supportedDifficultyIds[2]",
			"Maps[1].supportedDifficultyIds[1]"
		)

		local banners = Fixtures.clone(sources.banners)
		banners[1].outcomes[2].towerId = banners[1].outcomes[1].towerId
		expectIssue(
			assertions,
			BannerSchema.validateCatalog(banners, canonical.towers),
			"DUPLICATE_VALUE",
			"Banners[1].outcomes[2].towerId",
			"Banners[1].outcomes[1].towerId"
		)
	end),
	TestHarness.case(
		"enforces both probability-total tolerance directions and the probability floor",
		function(assertions)
			local sources, canonical = canonicalDependencies()
			local banners = Fixtures.clone(sources.banners)
			banners[1].outcomes[1].probabilityPercent = 60 - 1e-9
			assertions.isTrue(BannerSchema.validateCatalog(banners, canonical.towers).ok)

			banners = Fixtures.clone(sources.banners)
			banners[1].outcomes[1].probabilityPercent = 60 - 2e-9
			expectIssue(
				assertions,
				BannerSchema.validateCatalog(banners, canonical.towers),
				"INVALID_TOTAL",
				"Banners[1].outcomes",
				nil
			)

			banners = Fixtures.clone(sources.banners)
			banners[1].outcomes[1].probabilityPercent = BannerSchema.MIN_PROBABILITY_PERCENT
			banners[1].outcomes[2].probabilityPercent = 100 - BannerSchema.MIN_PROBABILITY_PERCENT
			assertions.isTrue(BannerSchema.validateCatalog(banners, canonical.towers).ok)

			banners = Fixtures.clone(sources.banners)
			banners[1].outcomes[1].probabilityPercent = BannerSchema.MIN_PROBABILITY_PERCENT / 2
			banners[1].outcomes[2].probabilityPercent = 100 - BannerSchema.MIN_PROBABILITY_PERCENT / 2
			expectIssue(
				assertions,
				BannerSchema.validateCatalog(banners, canonical.towers),
				"OUT_OF_RANGE",
				"Banners[1].outcomes[1].probabilityPercent",
				nil
			)
		end
	),
	TestHarness.case("preserves complete multi-root issue and blocked-family order", function(assertions)
		local expectedSignature: string? = nil
		for _ = 1, 5 do
			local sources = Fixtures.validSources()
			sources.towers[2].id = sources.towers[1].id
			sources.enemies[1].maxHealth = 0 / 0
			sources.maps[1].modelAssetKey = "tower.worker-model"
			sources.economy.difficultyRules[1].damageIncome.battleCashNumerator = 2
			sources.economy.difficultyRules[1].damageIncome.healthRemovedDenominator = 10
			sources.defaultSettings.version = 3

			local report = expectConfigurationReport(assertions, sources)
			assertions.isNotNil(report)
			if report == nil then
				return
			end

			assertions.equal(report.firstIssue, report.issues[1])
			assertions.equal(#report.issues, 5)
			assertions.equal(#report.blockedFamilies, 2)
			local signature = table.concat({
				report.issues[1].code .. "@" .. report.issues[1].path,
				report.issues[2].code .. "@" .. report.issues[2].path,
				report.issues[3].code .. "@" .. report.issues[3].path,
				report.issues[4].code .. "@" .. report.issues[4].path,
				report.issues[5].code .. "@" .. report.issues[5].path,
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
			"DUPLICATE_ID@Towers[2].id|NON_FINITE_NUMBER@Enemies[1].maxHealth|WRONG_ASSET_KIND@Maps[1].modelAssetKey|INVALID_ORDER@Economy.difficultyRules[1].damageIncome.healthRemovedDenominator|UNSUPPORTED_VERSION@DefaultSettings.version|WaveSchedules,Banners"
		)
	end),
	TestHarness.case("blocks only the exact dependency families in deterministic order", function(assertions)
		local towersInvalid = Fixtures.validSources()
		towersInvalid.towers[2].id = towersInvalid.towers[1].id
		local report = expectConfigurationReport(assertions, towersInvalid)
		assertions.equal(#report.issues, 1)
		assertions.equal(report.issues[1].path, "Towers[2].id")
		assertions.equal(table.concat(report.blockedFamilies, ","), "Banners")

		local enemiesInvalid = Fixtures.validSources()
		enemiesInvalid.enemies[1].maxHealth = 0 / 0
		report = expectConfigurationReport(assertions, enemiesInvalid)
		assertions.equal(#report.issues, 1)
		assertions.equal(report.issues[1].path, "Enemies[1].maxHealth")
		assertions.equal(table.concat(report.blockedFamilies, ","), "WaveSchedules")

		local difficultiesInvalid = Fixtures.validSources()
		difficultiesInvalid.difficulties[1].modifiers.enemyHealthMultiplier = 0
		report = expectConfigurationReport(assertions, difficultiesInvalid)
		assertions.equal(#report.issues, 1)
		assertions.equal(report.issues[1].path, "Difficulties[1].modifiers.enemyHealthMultiplier")
		assertions.equal(table.concat(report.blockedFamilies, ","), "Maps,WaveSchedules,Economy")
	end),
	TestHarness.case(
		"rejects missing malformed and lexically ordered Configuration source fields",
		function(assertions)
			local sources = Fixtures.validSources()
			sources.assets = nil
			local report = expectConfigurationReport(assertions, sources)
			assertions.equal(report.firstIssue.code, "MISSING_FIELD")
			assertions.equal(report.firstIssue.path, "Configuration.assets")
			assertions.equal(#report.blockedFamilies, ConfigurationValidator.FAMILY_COUNT)

			sources = Fixtures.validSources()
			sources.zeta = true
			sources.alpha = true
			report = expectConfigurationReport(assertions, sources)
			assertions.equal(report.firstIssue.code, "UNKNOWN_FIELD")
			assertions.equal(report.firstIssue.path, "Configuration.alpha")

			sources = Fixtures.validSources()
			sources.alpha = true
			sources["unsafe field"] = true
			report = expectConfigurationReport(assertions, sources)
			assertions.equal(report.firstIssue.code, "UNKNOWN_FIELD")
			assertions.equal(report.firstIssue.path, "Configuration")

			sources = setmetatable(Fixtures.validSources(), {})
			report = expectConfigurationReport(assertions, sources)
			assertions.equal(report.firstIssue.code, "INVALID_TABLE")
			assertions.equal(report.firstIssue.path, "Configuration")
		end
	),
	TestHarness.case("preserves schema root shape and field-precedence failures", function(assertions)
		local sources, canonical = canonicalDependencies()
		local assets = Fixtures.clone(sources.assets)
		assets[2] = nil
		expectIssue(assertions, AssetSchema.validateManifest(assets), "INVALID_ARRAY", "Assets", nil)

		local towers = Fixtures.clone(sources.towers)
		towers[1].zeta = true
		towers[1].alpha = true
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"UNKNOWN_FIELD",
			"Towers[1].alpha",
			nil
		)

		towers = Fixtures.clone(sources.towers)
		towers[1].alpha = true
		towers[1].currentLevel = 1
		expectIssue(
			assertions,
			TowerSchema.validateCatalog(towers, canonical.assets),
			"RUNTIME_FIELD_FORBIDDEN",
			"Towers[1].currentLevel",
			nil
		)

		local settings = Fixtures.clone(sources.defaultSettings)
		settings.zeta = true
		settings.alpha = true
		expectIssue(
			assertions,
			SettingsSchema.validateDefaults(settings),
			"UNKNOWN_FIELD",
			"DefaultSettings.alpha",
			nil
		)
	end),
})
