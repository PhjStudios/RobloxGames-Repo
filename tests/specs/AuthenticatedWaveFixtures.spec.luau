--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Fixtures = require(script.Parent.Parent.Fixtures.WaveFixtures)

local Shared = game:GetService("ReplicatedStorage").Shared
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local WaveSchema = require(Shared.config.WaveSchema)

type Assertions = TestHarness.Assertions

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

local function expectConfigurationIssue(
	assertions: Assertions,
	sources: { [string]: any },
	code: string,
	path: string,
	relatedPath: string?
): any
	local result = ConfigurationValidator.validate(sources)
	assertions.isFalse(result.ok)
	if result.ok then
		return nil
	end

	local report = result.error
	local issue = report.firstIssue
	assertions.equal(issue, report.issues[1])
	assertions.equal(issue.code, code)
	assertions.equal(issue.path, path)
	assertions.equal(issue.relatedPath, relatedPath)
	assertions.isTrue(table.isfrozen(report))
	assertions.isTrue(table.isfrozen(issue))
	return issue
end

local function expectSchemaIssue(assertions: Assertions, result: any, code: string, path: string): any
	assertions.isFalse(result.ok)
	if result.ok then
		return nil
	end

	local issue = result.error
	assertions.equal(issue.code, code)
	assertions.equal(issue.path, path)
	assertions.isTrue(table.isfrozen(issue))
	return issue
end

local function lastSpawnTime(group: any): number
	return group.startDelaySeconds + (group.count - 1) * group.spawnIntervalSeconds
end

local function scheduleStats(schedule: any): (number, number)
	local total = 0
	local maximumSimultaneous = 0
	for _, wave in schedule.waves do
		local times: { [number]: number } = {}
		for _, group in wave.groups do
			total += group.count
			for ordinal = 0, group.count - 1 do
				local time = group.startDelaySeconds + ordinal * group.spawnIntervalSeconds
				local simultaneous = (times[time] or 0) + 1
				times[time] = simultaneous
				maximumSimultaneous = math.max(maximumSimultaneous, simultaneous)
			end
		end
	end
	return total, maximumSimultaneous
end

return TestHarness.suite("authenticated authored-wave fixtures", {
	TestHarness.case("authenticates independent fresh full configuration roots", function(assertions)
		local first = Fixtures.createAuthenticatedFixture()
		local second = Fixtures.createAuthenticatedFixture()

		assertions.isTrue(ConfigurationValidator.isValidatedConfiguration(first.configuration))
		assertions.isTrue(ConfigurationValidator.isValidatedConfiguration(second.configuration))
		assertions.notEqual(first.rawSources, second.rawSources)
		assertions.notEqual(first.rawSources.waves, second.rawSources.waves)
		assertions.notEqual(first.configuration, second.configuration)
		assertions.isTrue(table.isfrozen(first))
		assertions.equal(#first.configuration.assets.ordered, 2)
		assertions.equal(#first.configuration.towers.ordered, 0)
		assertions.equal(#first.configuration.enemies.ordered, 2)
		assertions.equal(#first.configuration.difficulties.ordered, 2)
		assertions.equal(#first.configuration.maps.ordered, 1)
		assertions.equal(#first.configuration.waves.ordered, 2)
		assertions.equal(#first.configuration.economy.ordered, 2)
		assertions.equal(#first.configuration.banners.ordered, 0)
		assertions.equal(first.configuration.defaultSettings.version, 1)
	end),
	TestHarness.case("preserves exact canonical aliases and deep frozen runtime metadata", function(assertions)
		local fixture = Fixtures.createAuthenticatedFixture()
		local configuration = fixture.configuration
		local primary = fixture.primary
		local firstWave = primary.schedule.waves[1]

		assertions.equal(primary.mapDefinition, configuration.maps.byId[Fixtures.MAP_ID])
		assertions.equal(primary.difficultyDefinition, configuration.difficulties.byId[Fixtures.PRIMARY_DIFFICULTY_ID])
		assertions.equal(primary.schedule, configuration.waves.ordered[1])
		assertions.equal(primary.schedule, configuration.waves.byMapId[Fixtures.MAP_ID][Fixtures.PRIMARY_DIFFICULTY_ID])
		assertions.equal(firstWave, configuration.waves.byId[firstWave.id])
		assertions.equal(primary.economyRule, configuration.economy.byDifficultyId[Fixtures.PRIMARY_DIFFICULTY_ID])
		assertions.isTrue(table.isfrozen(configuration))
		assertions.isTrue(table.isfrozen(configuration.waves.byMapId[Fixtures.MAP_ID]))
		assertions.isTrue(table.isfrozen(firstWave.groups[1]))
		assertions.isTrue(table.isfrozen(primary.runtimeMetadata))
		assertions.equal(primary.runtimeMetadata.enemyHealthMultiplier, 1.25)
		assertions.equal(primary.runtimeMetadata.enemyMoveSpeedMultiplier, 0.8)
		assertions.equal(primary.runtimeMetadata.startingBattleCash, 375)
	end),
	TestHarness.case("matches a detached deeply frozen runtime map and lane order", function(assertions)
		local fixture = Fixtures.createAuthenticatedFixture()
		local map = fixture.primary.mapDefinition
		local runtimeMap = fixture.runtimeMap

		assertions.equal(runtimeMap.mapId, map.id)
		assertions.notEqual(runtimeMap, map)
		assertions.equal(#runtimeMap.lanes, #map.lanes)
		assertions.equal(runtimeMap.lanes[1].id, map.lanes[1].id)
		assertions.equal(runtimeMap.lanes[2].id, map.lanes[2].id)
		assertions.isTrue(table.isfrozen(runtimeMap))
		assertions.isTrue(table.isfrozen(runtimeMap.lanes))
		assertions.isTrue(table.isfrozen(runtimeMap.lanes[1].points[1]))
		assertions.isTrue(runtimeMap.lanes[1].totalDistance > 0)
		assertions.isTrue(runtimeMap.lanes[2].totalDistance > 0)

		local selection, selectionError = Fixtures.selectAuthoredFinite(
			fixture.configuration,
			Fixtures.createRuntimeMapSnapshot(),
			Fixtures.PRIMARY_DIFFICULTY_ID
		)
		assertions.isNotNil(selection)
		assertions.isNil(selectionError)

		local forgedRuntime = table.freeze({
			mapId = "map:not-the-graybox",
			lanes = table.freeze({}),
		})
		selection, selectionError =
			Fixtures.selectAuthoredFinite(fixture.configuration, forgedRuntime, Fixtures.PRIMARY_DIFFICULTY_ID)
		assertions.isNil(selection)
		assertions.equal(selectionError, Fixtures.INVALID_RUNTIME_MAP)
	end),
	TestHarness.case("contains the complete bounded authored-wave contract", function(assertions)
		local fixture = Fixtures.createAuthenticatedFixture()
		local primary = fixture.primary
		local waves = primary.schedule.waves
		local total, maximumSimultaneous = scheduleStats(primary.schedule)

		assertions.equal(primary.mapDefinition.id, "map:phase07-graybox")
		assertions.equal(primary.difficultyDefinition.timing.earlyClearIntermissionSeconds, 5)
		assertions.equal(#waves, 4)
		assertions.equal(waves[1].bossKind, "None")
		assertions.equal(waves[2].bossKind, "MiniBoss")
		assertions.equal(waves[3].bossKind, "None")
		assertions.equal(waves[4].bossKind, "Boss")
		assertions.equal(waves[1].rewardClass, "Standard")
		assertions.equal(waves[2].rewardClass, "Milestone")
		assertions.equal(waves[3].rewardClass, "Standard")
		assertions.equal(waves[4].rewardClass, "Final")
		assertions.equal(#waves[3].groups, 0)
		assertions.equal(waves[1].groups[1].spawnIntervalSeconds, 0)
		assertions.isTrue(waves[1].groups[2].spawnIntervalSeconds > 0)
		assertions.equal(waves[1].groups[1].laneId, Fixtures.MAIN_LANE_ID)
		assertions.equal(waves[1].groups[2].laneId, Fixtures.ALTERNATE_LANE_ID)
		assertions.equal(total, Fixtures.PRIMARY_SCHEDULED_SPAWNS)
		assertions.isTrue(total <= 4_096)
		assertions.equal(maximumSimultaneous, Fixtures.MAX_PRIMARY_SIMULTANEOUS_SPAWNS)
		assertions.isTrue(maximumSimultaneous <= 128)
		assertions.equal(primary.economyRule.waveRewards.standard.battleCashStipendPerActivePlayer, 25)
		assertions.equal(primary.economyRule.waveRewards.milestone.persistentGold.baseAmountPerEligiblePlayer, 2)
		assertions.equal(primary.economyRule.waveRewards.final.persistentGold.baseAmountPerEligiblePlayer, 10)
	end),
	TestHarness.case("distinguishes inclusive deadlines from deliberate scheduled overlap", function(assertions)
		local fixture = Fixtures.createAuthenticatedFixture()
		local finalWave = fixture.primary.schedule.waves[4]
		local finalGroup = finalWave.groups[1]
		local overlapWave = fixture.overlap.schedule.waves[1]
		local overlapGroup = overlapWave.groups[1]

		assertions.equal(finalWave.deadlinePolicy, "AllSpawnsByDeadline")
		assertions.equal(lastSpawnTime(finalGroup), finalWave.deadlineSeconds)
		assertions.equal(overlapWave.deadlinePolicy, "AllowScheduledOverlap")
		assertions.equal(
			overlapGroup.startDelaySeconds + overlapGroup.spawnIntervalSeconds,
			overlapWave.deadlineSeconds
		)
		assertions.isTrue(lastSpawnTime(overlapGroup) > overlapWave.deadlineSeconds)

		local total, maximumSimultaneous = scheduleStats(fixture.overlap.schedule)
		assertions.equal(total, Fixtures.OVERLAP_SCHEDULED_SPAWNS)
		assertions.isTrue(total <= 4_096)
		assertions.isTrue(maximumSimultaneous <= 128)

		local invalid = Fixtures.rawSources()
		invalid.waves[2].waves[1].deadlinePolicy = "AllSpawnsByDeadline"
		expectConfigurationIssue(
			assertions,
			invalid,
			"INVALID_ORDER",
			"WaveSchedules[2].waves[1].groups[1].spawnIntervalSeconds",
			nil
		)
	end),
	TestHarness.case("rejects forged catalogs and detached canonical-looking roots", function(assertions)
		local fixture = Fixtures.createAuthenticatedFixture()
		local configuration = fixture.configuration
		local detachedConfiguration = freezeRecursively(Fixtures.clone(configuration))

		assertions.isTrue(table.isfrozen(detachedConfiguration))
		assertions.isFalse(ConfigurationValidator.isValidatedConfiguration(detachedConfiguration))
		local selection, selectionError =
			Fixtures.selectAuthoredFinite(detachedConfiguration, fixture.runtimeMap, Fixtures.PRIMARY_DIFFICULTY_ID)
		assertions.isNil(selection)
		assertions.equal(selectionError, Fixtures.INVALID_CONFIGURATION)

		local forgedMaps = freezeRecursively(Fixtures.clone(configuration.maps))
		expectSchemaIssue(
			assertions,
			WaveSchema.validateCatalog(
				fixture.rawSources.waves,
				forgedMaps,
				configuration.difficulties,
				configuration.enemies
			),
			"INVALID_REFERENCE",
			"MapCatalog"
		)

		local forgedDifficulties = freezeRecursively(Fixtures.clone(configuration.difficulties))
		expectSchemaIssue(
			assertions,
			WaveSchema.validateCatalog(
				fixture.rawSources.waves,
				configuration.maps,
				forgedDifficulties,
				configuration.enemies
			),
			"INVALID_REFERENCE",
			"DifficultyCatalog"
		)

		local forgedEnemies = freezeRecursively(Fixtures.clone(configuration.enemies))
		expectSchemaIssue(
			assertions,
			WaveSchema.validateCatalog(
				fixture.rawSources.waves,
				configuration.maps,
				configuration.difficulties,
				forgedEnemies
			),
			"INVALID_REFERENCE",
			"EnemyCatalog"
		)
	end),
	TestHarness.case("rejects an unsupported map and difficulty pair", function(assertions)
		local invalid = Fixtures.rawSources()
		table.remove(invalid.maps[1].supportedDifficultyIds, 2)
		expectConfigurationIssue(assertions, invalid, "INVALID_REFERENCE", "WaveSchedules[2].difficultyId", nil)

		local fixture = Fixtures.createAuthenticatedFixture()
		local selection, selectionError =
			Fixtures.selectAuthoredFinite(fixture.configuration, fixture.runtimeMap, "difficulty:not-supported")
		assertions.isNil(selection)
		assertions.equal(selectionError, Fixtures.DIFFICULTY_NOT_FOUND)
	end),
	TestHarness.case("validates the GeneratedEndless boundary but rejects runtime selection", function(assertions)
		local raw = Fixtures.rawSources(true)
		local result = ConfigurationValidator.validate(raw)
		assertions.isTrue(result.ok)
		if not result.ok then
			return
		end

		assertions.isTrue(ConfigurationValidator.isValidatedConfiguration(result.value))
		assertions.equal(
			result.value.waves.byMapId[Fixtures.MAP_ID][Fixtures.ENDLESS_DIFFICULTY_ID].kind,
			"GeneratedEndless"
		)
		local selection, selectionError = Fixtures.selectAuthoredFinite(
			result.value,
			Fixtures.createRuntimeMapSnapshot(),
			Fixtures.ENDLESS_DIFFICULTY_ID
		)
		assertions.isNil(selection)
		assertions.equal(selectionError, Fixtures.GENERATED_ENDLESS_UNSUPPORTED)
	end),
	TestHarness.case("rejects inconsistent finite waveCount metadata", function(assertions)
		local invalid = Fixtures.rawSources()
		invalid.difficulties[1].waveCount = 5
		expectConfigurationIssue(assertions, invalid, "INVALID_ORDER", "WaveSchedules[1].waves", nil)
	end),
	TestHarness.case("rejects wrong missing and extra economy rules", function(assertions)
		local wrong = Fixtures.rawSources()
		wrong.economy.difficultyRules[1].difficultyId = "difficulty:not-present"
		expectConfigurationIssue(assertions, wrong, "INVALID_REFERENCE", "Economy.difficultyRules[1].difficultyId", nil)

		local missing = Fixtures.rawSources()
		table.remove(missing.economy.difficultyRules, 1)
		expectConfigurationIssue(assertions, missing, "INVALID_REFERENCE", "Difficulties[1].id", nil)

		local extra = Fixtures.rawSources()
		table.insert(extra.economy.difficultyRules, Fixtures.clone(extra.economy.difficultyRules[1]))
		expectConfigurationIssue(
			assertions,
			extra,
			"DUPLICATE_VALUE",
			"Economy.difficultyRules[3].difficultyId",
			"Economy.difficultyRules[1].difficultyId"
		)
	end),
	TestHarness.case("rejects hostile tables nonfinite times and nonfinite stat products", function(assertions)
		local hostile = Fixtures.rawSources()
		setmetatable(hostile.waves[1].waves[1].groups[1], {})
		expectConfigurationIssue(assertions, hostile, "INVALID_TABLE", "WaveSchedules[1].waves[1].groups[1]", nil)

		local nonfiniteDeadline = Fixtures.rawSources()
		nonfiniteDeadline.waves[1].waves[1].deadlineSeconds = math.huge
		expectConfigurationIssue(
			assertions,
			nonfiniteDeadline,
			"NON_FINITE_NUMBER",
			"WaveSchedules[1].waves[1].deadlineSeconds",
			nil
		)

		local nonfiniteDelay = Fixtures.rawSources()
		nonfiniteDelay.waves[1].waves[1].groups[1].startDelaySeconds = -math.huge
		expectConfigurationIssue(
			assertions,
			nonfiniteDelay,
			"NON_FINITE_NUMBER",
			"WaveSchedules[1].waves[1].groups[1].startDelaySeconds",
			nil
		)

		local nonfiniteInterval = Fixtures.rawSources()
		nonfiniteInterval.waves[1].waves[1].groups[1].spawnIntervalSeconds = 0 / 0
		expectConfigurationIssue(
			assertions,
			nonfiniteInterval,
			"NON_FINITE_NUMBER",
			"WaveSchedules[1].waves[1].groups[1].spawnIntervalSeconds",
			nil
		)

		local healthOverflow = Fixtures.rawSources()
		healthOverflow.enemies[1].maxHealth = 1e308
		healthOverflow.difficulties[1].modifiers.enemyHealthMultiplier = 1_000
		expectConfigurationIssue(
			assertions,
			healthOverflow,
			"OUT_OF_RANGE",
			"WaveSchedules[1].waves[1].groups[1].enemyId",
			nil
		)

		local speedOverflow = Fixtures.rawSources()
		speedOverflow.enemies[1].moveSpeedStudsPerSecond = 1e308
		speedOverflow.difficulties[1].modifiers.enemyMoveSpeedMultiplier = 1_000
		expectConfigurationIssue(
			assertions,
			speedOverflow,
			"OUT_OF_RANGE",
			"WaveSchedules[1].waves[1].groups[1].enemyId",
			nil
		)
	end),
	TestHarness.case("isolates canonical output from raw mutation and future fixture calls", function(assertions)
		local raw = Fixtures.rawSources()
		local fixture = Fixtures.authenticateSources(raw)
		local fresh = Fixtures.rawSources()

		raw.enemies[1].displayName = "Mutated Enemy"
		raw.maps[1].lanes[1].id = "mutated-lane"
		raw.waves[1].waves[1].groups[1].count = 99
		raw.economy.difficultyRules[1].startingBattleCash = 999

		assertions.equal(fixture.configuration.enemies.ordered[1].displayName, "Phase 11 Worker")
		assertions.equal(fixture.primary.mapDefinition.lanes[1].id, Fixtures.MAIN_LANE_ID)
		assertions.equal(fixture.primary.schedule.waves[1].groups[1].count, 3)
		assertions.equal(fixture.primary.economyRule.startingBattleCash, 375)
		assertions.equal(fresh.enemies[1].displayName, "Phase 11 Worker")
		assertions.equal(fresh.maps[1].lanes[1].id, Fixtures.MAIN_LANE_ID)
		assertions.equal(fresh.waves[1].waves[1].groups[1].count, 3)
		assertions.equal(fresh.economy.difficultyRules[1].startingBattleCash, 375)
		assertions.notEqual(raw, fresh)
		assertions.notEqual(raw.enemies[1], fresh.enemies[1])
	end),
})
