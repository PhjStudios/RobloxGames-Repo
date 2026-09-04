--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local ContentBalanceSimulation = require(script.Parent.Parent.Support.ContentBalanceSimulation)

local Shared = game:GetService("ReplicatedStorage").Shared
local AcquisitionConfig = require(Shared.acquisition.AcquisitionConfig)
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local ContentSelection = require(Shared.config.ContentSelection)
local EnemySchema = require(Shared.config.EnemySchema)
local LobbyQueues = require(Shared.config.LobbyQueues)
local TowerSchema = require(Shared.config.TowerSchema)
local PlacementGeometry = require(Shared.match.PlacementGeometry)

local function configuration(assertions: TestHarness.Assertions): any
	local result = ConfigurationValidator.validateLoaded()
	assertions.isTrue(result.ok)
	if not result.ok then
		error("release content failed validation", 0)
	end
	return result.value
end

local function hasTag(definition: any, expected: string): boolean
	for _, tag in definition.tags or {} do
		if tag == expected then
			return true
		end
	end
	return false
end

local function scheduledPressure(config: any, schedule: any, limit: number): number
	local difficulty = config.difficulties.byId[schedule.difficultyId]
	local total = 0
	for index = 1, math.min(limit, #schedule.waves) do
		for _, group in schedule.waves[index].groups do
			total += config.enemies.byId[group.enemyId].maxHealth * difficulty.modifiers.enemyHealthMultiplier * group.count
		end
	end
	return total
end

local function averageSpawnInterval(schedule: any, limit: number): number
	local total = 0
	local count = 0
	for index = 1, math.min(limit, #schedule.waves) do
		for _, group in schedule.waves[index].groups do
			total += group.spawnIntervalSeconds
			count += 1
		end
	end
	return total / count
end

local function regionsOverlap(left: any, right: any): boolean
	local leftCenter = left.cframe.Position
	local rightCenter = right.cframe.Position
	local leftHalf = left.size * 0.5
	local rightHalf = right.size * 0.5
	return math.min(leftCenter.X + leftHalf.X, rightCenter.X + rightHalf.X)
			> math.max(leftCenter.X - leftHalf.X, rightCenter.X - rightHalf.X)
		and math.min(leftCenter.Z + leftHalf.Z, rightCenter.Z + rightHalf.Z)
			> math.max(leftCenter.Z - leftHalf.Z, rightCenter.Z - rightHalf.Z)
end

local function regionInside(inner: any, outer: any): boolean
	local localCenter = outer.cframe:PointToObjectSpace(inner.cframe.Position)
	local innerHalf = inner.size * 0.5
	local outerHalf = outer.size * 0.5
	return math.abs(localCenter.X) + innerHalf.X <= outerHalf.X
		and math.abs(localCenter.Y) + innerHalf.Y <= outerHalf.Y
		and math.abs(localCenter.Z) + innerHalf.Z <= outerHalf.Z
end

return TestHarness.suite("release content catalog", {
	TestHarness.case("centralizes stable release and development identifiers", function(assertions)
		assertions.equal(ContentSelection.CONTENT_VERSION, 1)
		assertions.equal(ContentSelection.DEVELOPMENT_MAP_ID, "map:phase07-graybox")
		assertions.equal(ContentSelection.DEVELOPMENT_DIFFICULTY_ID, "difficulty:local")
		assertions.equal(ContentSelection.RELEASE_MAP_ID, "map:backyard-garden-v1")
		assertions.equal(ContentSelection.EASY_DIFFICULTY_ID, "difficulty:easy-v1")
		assertions.equal(ContentSelection.NORMAL_DIFFICULTY_ID, "difficulty:normal-v1")
		assertions.equal(ContentSelection.HARD_DIFFICULTY_ID, "difficulty:hard-v1")
		assertions.equal(ContentSelection.ENDLESS_DIFFICULTY_ID, "difficulty:endless-v1")
		assertions.equal(ContentSelection.RELEASE_BANNER_ID, "banner:garden-v1")
		assertions.equal(ContentSelection.ENDLESS_GENERATOR_KEY, "wave-generator.garden-v1")
		assertions.equal(ContentSelection.STARTER_TOWER_IDS[1], "tower:dart-ant")
		assertions.equal(ContentSelection.STARTER_TOWER_IDS[2], "tower:bombardier-ant")
		assertions.isTrue(table.isfrozen(ContentSelection))
		assertions.isTrue(table.isfrozen(ContentSelection.STARTER_TOWER_IDS))
		assertions.isTrue(table.isfrozen(ContentSelection.RELEASE_DIFFICULTY_IDS))
	end),
	TestHarness.case("retains legacy identities while selecting the release garden queue", function(assertions)
		local config = configuration(assertions)
		local legacyMap = config.maps.byId["map:phase07-graybox"]
		local legacyDifficulty = config.difficulties.byId["difficulty:local"]
		local legacySchedule = config.waves.byMapId[legacyMap.id][legacyDifficulty.id]
		assertions.equal(legacyMap, config.maps.ordered[1])
		assertions.equal(legacyDifficulty, config.difficulties.ordered[1])
		assertions.equal(#legacyMap.supportedDifficultyIds, 1)
		assertions.equal(legacyMap.supportedDifficultyIds[1], "difficulty:local")
		assertions.equal(#legacySchedule.waves, 5)
		for index, wave in legacySchedule.waves do
			assertions.equal(wave.id, `wave:local-{index}`)
		end
		assertions.equal(config.towers.ordered[1].id, "tower:dart-ant")
		assertions.equal(config.towers.ordered[2].id, "tower:rapid-ant")
		assertions.equal(config.towers.ordered[3].id, "tower:guard-ant")
		assertions.equal(config.enemies.ordered[4].id, "enemy:garden-queen")
		assertions.equal(config.banners.ordered[1].id, "banner:starter")
		assertions.equal(config.banners.ordered[1].version, 1)
		assertions.equal(config.banners.ordered[1].outcomes[1].probabilityPercent, 60)
		assertions.equal(config.banners.ordered[1].outcomes[2].probabilityPercent, 30)
		assertions.equal(config.banners.ordered[1].outcomes[3].probabilityPercent, 10)
		local releaseMap = config.maps.byId[ContentSelection.RELEASE_MAP_ID]
		assertions.equal(#releaseMap.supportedDifficultyIds, #ContentSelection.RELEASE_DIFFICULTY_IDS)
		for index, difficultyId in ContentSelection.RELEASE_DIFFICULTY_IDS do
			assertions.equal(releaseMap.supportedDifficultyIds[index], difficultyId)
		end

		assertions.equal(LobbyQueues.ordered[1].queueId, "queue:backyard-squad")
		assertions.equal(LobbyQueues.ordered[1].configuration.mapId, ContentSelection.RELEASE_MAP_ID)
		assertions.equal(LobbyQueues.ordered[1].configuration.difficultyId, ContentSelection.EASY_DIFFICULTY_ID)
	end),
	TestHarness.case("defines four complete and strategically distinct tower paths", function(assertions)
		local config = configuration(assertions)
		assertions.equal(#config.towers.ordered, 4)
		for _, tower in config.towers.ordered do
			assertions.equal(#tower.levels, 3)
			assertions.equal(#tower.supportedTargetModes, 5)
			for _, level in tower.levels do
				assertions.isNotNil(level.attack)
			end
		end

		local bombardier = config.towers.byId["tower:bombardier-ant"]
		assertions.equal(bombardier, config.towers.ordered[4])
		assertions.isTrue(hasTag(bombardier, "starter"))
		assertions.isTrue(hasTag(bombardier, "role.area"))
		for _, level in bombardier.levels do
			assertions.equal(level.attack.behavior.key, "attack.splash")
			assertions.isTrue(level.attack.splashRadiusStuds > 0)
		end
		assertions.equal(config.towers.byId["tower:dart-ant"].levels[1].attack.behavior.key, "attack.direct")
		assertions.equal(config.towers.byId["tower:rapid-ant"].defaultTargetMode, "Closest")
		assertions.equal(config.towers.byId["tower:guard-ant"].defaultTargetMode, "Strongest")
	end),
	TestHarness.case("defines readable enemy roles and threat presentation", function(assertions)
		local config = configuration(assertions)
		assertions.equal(#config.enemies.ordered, 6)
		assertions.isTrue(hasTag(config.enemies.byId["enemy:worker-ant"], "role.basic"))
		assertions.isTrue(hasTag(config.enemies.byId["enemy:scout-ant"], "role.fast"))
		assertions.isTrue(hasTag(config.enemies.byId["enemy:soldier-ant"], "role.durable"))
		assertions.isTrue(hasTag(config.enemies.byId["enemy:broodling-ant"], "role.swarm"))
		assertions.equal(config.enemies.byId["enemy:soldier-ant"].threatClass, "Elite")
		assertions.equal(config.enemies.byId["enemy:royal-guard-ant"].threatClass, "MiniBoss")
		assertions.equal(config.enemies.byId["enemy:garden-queen"].threatClass, "Boss")
	end),
	TestHarness.case("bounds splash metadata and defaults legacy threat presentation", function(assertions)
		local config = configuration(assertions)
		local authoredTowers = require(Shared.config.Towers)
		for _, invalidRadius in { 0, -1, 129, math.huge, "wide" } do
			local tower = table.clone(authoredTowers[4])
			tower.levels = table.clone(tower.levels)
			tower.levels[1] = table.clone(tower.levels[1])
			tower.levels[1].attack = table.clone(tower.levels[1].attack)
			tower.levels[1].attack.splashRadiusStuds = invalidRadius
			assertions.isFalse(TowerSchema.validateDefinition(tower, config.assets).ok)
		end

		local authoredEnemies = require(Shared.config.Enemies)
		local legacy = table.clone(authoredEnemies[1])
		legacy.threatClass = nil
		local defaulted = EnemySchema.validateDefinition(legacy, config.assets)
		assertions.isTrue(defaulted.ok)
		if defaulted.ok then
			assertions.equal(defaulted.value.threatClass, "Standard")
		end
		local invalidThreat = table.clone(authoredEnemies[1])
		invalidThreat.threatClass = "Catastrophic"
		assertions.isFalse(EnemySchema.validateDefinition(invalidThreat, config.assets).ok)
	end),
	TestHarness.case("authors exact finite campaigns with ten-wave boss cadence", function(assertions)
		local config = configuration(assertions)
		local mapSchedules = config.waves.byMapId[ContentSelection.RELEASE_MAP_ID]
		local expectedCounts = {
			[ContentSelection.EASY_DIFFICULTY_ID] = 20,
			[ContentSelection.NORMAL_DIFFICULTY_ID] = 30,
			[ContentSelection.HARD_DIFFICULTY_ID] = 40,
		}
		local ids: { [string]: boolean } = {}
		local easyRoles: { [string]: boolean } = {}
		for difficultyId, expectedCount in expectedCounts do
			local schedule = mapSchedules[difficultyId]
			assertions.equal(schedule.kind, "AuthoredFinite")
			assertions.equal(#schedule.waves, expectedCount)
			for index, wave in schedule.waves do
				assertions.isFalse(ids[wave.id] == true)
				ids[wave.id] = true
				assertions.equal(wave.bossKind == "Boss", index % 10 == 0)
				assertions.equal(wave.rewardClass == "Final", index == expectedCount)
				local scheduledCount = 0
				local hasBossEnemy = false
				local hasMiniBossEnemy = false
				for _, group in wave.groups do
					scheduledCount += group.count
					local enemy = config.enemies.byId[group.enemyId]
					hasBossEnemy = hasBossEnemy or enemy.threatClass == "Boss"
					hasMiniBossEnemy = hasMiniBossEnemy or enemy.threatClass == "MiniBoss"
					if difficultyId == ContentSelection.EASY_DIFFICULTY_ID and index < 10 then
						for _, tag in enemy.tags do
							easyRoles[tag] = true
						end
					end
				end
				assertions.isTrue(scheduledCount <= 20)
				if wave.bossKind == "Boss" then
					assertions.isTrue(hasBossEnemy)
				elseif wave.bossKind == "MiniBoss" then
					assertions.isTrue(hasMiniBossEnemy)
				end
			end
		end
		assertions.isTrue(easyRoles["role.basic"])
		assertions.isTrue(easyRoles["role.fast"])
		assertions.isTrue(easyRoles["role.swarm"])
		assertions.isTrue(easyRoles["role.durable"])
	end),
	TestHarness.case("distinguishes campaign pressure pacing and economy", function(assertions)
		local config = configuration(assertions)
		local schedules = config.waves.byMapId[ContentSelection.RELEASE_MAP_ID]
		local easy = schedules[ContentSelection.EASY_DIFFICULTY_ID]
		local normal = schedules[ContentSelection.NORMAL_DIFFICULTY_ID]
		local hard = schedules[ContentSelection.HARD_DIFFICULTY_ID]
		assertions.isTrue(scheduledPressure(config, easy, 20) < scheduledPressure(config, normal, 20))
		assertions.isTrue(scheduledPressure(config, normal, 20) < scheduledPressure(config, hard, 20))
		assertions.isTrue(averageSpawnInterval(easy, 20) > averageSpawnInterval(normal, 20))
		assertions.isTrue(averageSpawnInterval(normal, 20) > averageSpawnInterval(hard, 20))
		assertions.isTrue(
			config.economy.byDifficultyId[ContentSelection.EASY_DIFFICULTY_ID].startingBattleCash
				> config.economy.byDifficultyId[ContentSelection.NORMAL_DIFFICULTY_ID].startingBattleCash
		)
		assertions.isTrue(
			config.economy.byDifficultyId[ContentSelection.NORMAL_DIFFICULTY_ID].startingBattleCash
				> config.economy.byDifficultyId[ContentSelection.HARD_DIFFICULTY_ID].startingBattleCash
		)
		assertions.isTrue(
			config.difficulties.byId[ContentSelection.EASY_DIFFICULTY_ID].timing.earlyClearIntermissionSeconds
				> config.difficulties.byId[ContentSelection.NORMAL_DIFFICULTY_ID].timing.earlyClearIntermissionSeconds
		)
	end),
	TestHarness.case("provides a bounded authored opening for deterministic Endless", function(assertions)
		local config = configuration(assertions)
		local schedule = config.waves.byMapId[ContentSelection.RELEASE_MAP_ID][ContentSelection.ENDLESS_DIFFICULTY_ID]
		assertions.equal(schedule.kind, "GeneratedEndless")
		assertions.equal(schedule.generator.kind, "EndlessWaveGenerator")
		assertions.equal(schedule.generator.key, ContentSelection.ENDLESS_GENERATOR_KEY)
		assertions.equal(#schedule.authoredOpeningWaves, 10)
		for index, wave in schedule.authoredOpeningWaves do
			assertions.equal(wave.bossKind == "Boss", index == 10)
			assertions.equal(wave.rewardClass, if index == 5 or index == 10 then "Milestone" else "Standard")
		end
	end),
	TestHarness.case("exposes the earn-only Garden chest without mutating starter v1", function(assertions)
		local config = configuration(assertions)
		local garden = config.banners.byId[ContentSelection.RELEASE_BANNER_ID]
		assertions.equal(garden.version, 1)
		assertions.equal(garden.pullOptions.onePull.goldCost, 250)
		assertions.equal(garden.pullOptions.tenPull.goldCost, 2_250)
		assertions.equal(garden.outcomes[1].towerId, "tower:dart-ant")
		assertions.equal(garden.outcomes[1].probabilityPercent, 40)
		assertions.equal(garden.outcomes[2].probabilityPercent, 30)
		assertions.equal(garden.outcomes[3].probabilityPercent, 20)
		assertions.equal(garden.outcomes[4].probabilityPercent, 10)
		assertions.equal(garden.pityRule.hardPityPullCount, 10)
		assertions.equal(garden.pityRule.guaranteedTowerId, "tower:guard-ant")
		local unlockable: { [string]: boolean } = {}
		for _, outcome in garden.outcomes do
			unlockable[outcome.towerId] = true
		end
		for _, tower in config.towers.ordered do
			assertions.isTrue(unlockable[tower.id])
		end
		assertions.equal(#AcquisitionConfig.banners, 2)
		assertions.equal(AcquisitionConfig.banners[1].bannerId, "banner:starter")
		assertions.equal(AcquisitionConfig.banners[1].bannerVersion, 1)
		assertions.equal(AcquisitionConfig.banners[2].bannerId, "banner:garden-v1")
		assertions.equal(AcquisitionConfig.banners[2].currencyPolicy, "EarnOnlyGold")
	end),
	TestHarness.case(
		"anchors balance evidence to legal garden build pockets and two-dimensional range",
		function(assertions)
			local zones = ContentBalanceSimulation.GARDEN_PLACEMENT_ZONES
			local exclusions = ContentBalanceSimulation.GARDEN_EXCLUSIONS
			local slots = ContentBalanceSimulation.GARDEN_PLACEMENT_SLOTS
			assertions.equal(#zones, 4)
			assertions.equal(#exclusions, 1)
			assertions.equal(#slots, 8)
			assertions.isTrue(ContentBalanceSimulation.GARDEN_PATH_LENGTH_STUDS > 168)
			assertions.isTrue(ContentBalanceSimulation.GARDEN_PATH_LENGTH_STUDS < 169)

			local expectedZoneIds = { "west-overlook", "middle-bend", "upper-choke", "east-choke" }
			local buildableArea = 0
			for leftIndex = 1, #zones do
				assertions.equal(zones[leftIndex].id, expectedZoneIds[leftIndex])
				buildableArea += zones[leftIndex].size.X * zones[leftIndex].size.Z
				for rightIndex = leftIndex + 1, #zones do
					assertions.isFalse(regionsOverlap(zones[leftIndex], zones[rightIndex]))
				end
			end
			assertions.equal(buildableArea, 1_556)
			assertions.equal(exclusions[1].id, "west-rock")
			assertions.isTrue(regionInside(exclusions[1], zones[1]))

			local expectedSlots = {
				{ id = "west-a", zoneId = "west-overlook", positionXZ = Vector2.new(-54, -54), minimumDistance = 14 },
				{ id = "middle-a", zoneId = "middle-bend", positionXZ = Vector2.new(-25, -5), minimumDistance = 13 },
				{
					id = "upper-a",
					zoneId = "upper-choke",
					positionXZ = Vector2.new(16, 19),
					minimumDistance = math.sqrt(145),
				},
				{ id = "east-a", zoneId = "east-choke", positionXZ = Vector2.new(43, -5), minimumDistance = 15 },
				{
					id = "west-b",
					zoneId = "west-overlook",
					positionXZ = Vector2.new(-33, -54),
					minimumDistance = math.sqrt(277),
				},
				{
					id = "middle-b",
					zoneId = "middle-bend",
					positionXZ = Vector2.new(1, -5),
					minimumDistance = 404 / math.sqrt(1_040),
				},
				{ id = "upper-b", zoneId = "upper-choke", positionXZ = Vector2.new(44, 23), minimumDistance = 13 },
				{ id = "east-b", zoneId = "east-choke", positionXZ = Vector2.new(61, -5), minimumDistance = 15 },
			}
			local footprints: { Vector3 } = {}
			for index, slot in slots do
				local expected = expectedSlots[index]
				assertions.equal(slot.id, expected.id)
				assertions.equal(slot.zoneId, expected.zoneId)
				assertions.equal(slot.positionXZ, expected.positionXZ)
				local evaluation = PlacementGeometry.evaluate(
					slot.positionXZ,
					1.9,
					ContentBalanceSimulation.GARDEN_BOUNDS,
					zones,
					exclusions,
					footprints
				)
				assertions.isTrue(evaluation.valid)
				assertions.equal(zones[evaluation.zoneIndex].id, expected.zoneId)
				local encoded = PlacementGeometry.encodeFootprint(slot.positionXZ, 1.9)
				assertions.isNotNil(encoded)
				table.insert(footprints, encoded :: Vector3)
				local distance = ContentBalanceSimulation.minimumDistanceToPath(slot.positionXZ)
				assertions.isTrue(math.abs(distance - expected.minimumDistance) < 0.000001)
				assertions.isTrue(distance < 20)
			end

			for _, blockedPosition in
				{
					Vector2.new(-50, -40), -- lane
					Vector2.new(27, 38), -- raised bed
					Vector2.new(42, 39), -- player spawn
					Vector2.new(70, 10), -- goal
				}
			do
				local evaluation = PlacementGeometry.evaluate(
					blockedPosition,
					1.4,
					ContentBalanceSimulation.GARDEN_BOUNDS,
					zones,
					exclusions,
					{}
				)
				assertions.isFalse(evaluation.valid)
				assertions.equal(evaluation.reason, "OutsideZone")
			end
			local rock = PlacementGeometry.evaluate(
				Vector2.new(-45, -54),
				1.4,
				ContentBalanceSimulation.GARDEN_BOUNDS,
				zones,
				exclusions,
				{}
			)
			assertions.isFalse(rock.valid)
			assertions.equal(rock.reason, "Excluded")
		end
	),
	TestHarness.case("keeps starter and alternate two-role strategies viable through Easy", function(assertions)
		local config = configuration(assertions)
		local result = ContentBalanceSimulation.run(
			config,
			ContentSelection.EASY_DIFFICULTY_ID,
			ContentSelection.STARTER_TOWER_IDS
		)
		assertions.isTrue(result.victory)
		assertions.equal(result.wavesCompleted, 20)
		assertions.isTrue(result.baseHealthRemaining > 0)
		assertions.isTrue(result.damageDealt > 0)
		assertions.isTrue(result.attackCount > 0)
		assertions.isTrue(result.durationSeconds > 0)
		assertions.isTrue(result.maximumActiveEnemies <= 20)
		assertions.equal(result.towerCount, 8)
		assertions.equal(#result.placements, result.towerCount)
		for _, placement in result.placements do
			assertions.isTrue(placement.minimumPathDistanceStuds < 20)
			assertions.isTrue(placement.footprintRadiusStuds <= 1.9)
		end

		-- The same authored campaign, decisions, map, seed, and virtual clock
		-- produce identical authoritative evidence without wall-clock waits.
		local repeated = ContentBalanceSimulation.run(
			config,
			ContentSelection.EASY_DIFFICULTY_ID,
			ContentSelection.STARTER_TOWER_IDS
		)
		assertions.equal(repeated.victory, result.victory)
		assertions.equal(repeated.wavesCompleted, result.wavesCompleted)
		assertions.equal(repeated.baseHealthRemaining, result.baseHealthRemaining)
		assertions.equal(repeated.battleCashRemaining, result.battleCashRemaining)
		assertions.equal(repeated.damageDealt, result.damageDealt)
		assertions.equal(repeated.attackCount, result.attackCount)
		assertions.equal(repeated.durationSeconds, result.durationSeconds)
		assertions.equal(repeated.maximumActiveEnemies, result.maximumActiveEnemies)
		assertions.equal(repeated.towerCount, result.towerCount)
		for index, placement in result.placements do
			local repeatedPlacement = repeated.placements[index]
			assertions.equal(repeatedPlacement.towerId, placement.towerId)
			assertions.equal(repeatedPlacement.slotId, placement.slotId)
			assertions.equal(repeatedPlacement.zoneId, placement.zoneId)
			assertions.equal(repeatedPlacement.positionXZ, placement.positionXZ)
		end
		for _, roster in
			{
				{ "tower:rapid-ant", "tower:guard-ant" },
				{ "tower:dart-ant", "tower:guard-ant" },
				{ "tower:rapid-ant", "tower:bombardier-ant" },
			}
		do
			local alternative = ContentBalanceSimulation.run(config, ContentSelection.EASY_DIFFICULTY_ID, roster)
			assertions.isTrue(alternative.victory)
			assertions.equal(alternative.wavesCompleted, 20)
			assertions.isTrue(alternative.baseHealthRemaining > 0)
			assertions.isTrue(alternative.maximumActiveEnemies <= 20)
		end
	end),
})
