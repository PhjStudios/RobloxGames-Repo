--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local AssetSchema = require(ReplicatedStorage.Shared.config.AssetSchema)
local DifficultySchema = require(ReplicatedStorage.Shared.config.DifficultySchema)

local ConfigurationFixtures = require(script.Parent.Parent.Fixtures.ConfigurationFixtures)
local EnemyFixtures = require(script.Parent.Parent.Fixtures.EnemyFixtures)
local EnemyRuntimeStore = require(script.Parent.Parent.ProductionServerEnemies.EnemyRuntimeStore)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase09-runtime-store"

local function createDifficultyFixture(healthMultiplier: number?, speedMultiplier: number?): { [string]: any }
	local rawSources = ConfigurationFixtures.validSources()
	rawSources.difficulties[1].modifiers.enemyHealthMultiplier = healthMultiplier or 1.5
	rawSources.difficulties[1].modifiers.enemyMoveSpeedMultiplier = speedMultiplier or 1.25
	local manifestResult = AssetSchema.validateManifest(rawSources.assets)
	if not manifestResult.ok then
		error("expected difficulty fixture assets to authenticate", 0)
	end
	local catalogResult = DifficultySchema.validateCatalog(rawSources.difficulties, manifestResult.value)
	if not catalogResult.ok then
		error("expected difficulty fixture catalog to authenticate", 0)
	end
	local catalog = catalogResult.value
	local finite = catalog.byId["difficulty:normal"]
	local endless = catalog.byId["difficulty:endless"]
	if finite == nil or endless == nil then
		error("expected difficulty fixture definitions", 0)
	end
	return {
		catalog = catalog,
		finite = finite,
		endless = endless,
		rawSources = rawSources,
	}
end

local function expectError(assertions: Assertions, result: any, code: string, operation: string)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		assertions.isTrue(table.isfrozen(result.error))
		assertions.equal(result.error.code, code)
		assertions.equal(result.error.operation, operation)
	end
end

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected Phase 09 fixture operation to succeed", 0)
	end
	return result.value
end

local function assertDetachedFrozen(assertions: Assertions, value: unknown, seen: { [any]: boolean }?)
	assertions.isFalse(typeof(value) == "Instance")
	if type(value) ~= "table" then
		return
	end
	local visited = seen or {}
	if visited[value :: any] then
		return
	end
	visited[value :: any] = true
	assertions.isTrue(table.isfrozen(value :: any))
	for key, child in next, value :: { [any]: unknown } do
		assertDetachedFrozen(assertions, key, visited)
		assertDetachedFrozen(assertions, child, visited)
	end
end

local function assertVectorClose(assertions: Assertions, actual: Vector3, expected: Vector3, tolerance: number)
	assertions.isTrue((actual - expected).Magnitude <= tolerance)
end

local function newStore(
	assertions: Assertions,
	overrides: { [string]: any }?
): (EnemyRuntimeStore.Store, { now: number })
	local clockState = { now = 100 }
	local options: { [string]: any } = {
		clock = function()
			return clockState.now
		end,
	}
	if overrides ~= nil then
		for key, value in overrides do
			options[key] = value
		end
	end
	local result = EnemyRuntimeStore.newForTests(
		MATCH_ID,
		1,
		EnemyFixtures.createAuthenticatedCatalog(),
		EnemyFixtures.createRuntimeMapSnapshot(),
		options
	)
	return success(assertions, result), clockState
end

local function mapWithLane(lane: any): any
	local source = EnemyFixtures.createRuntimeMapSnapshot()
	return table.freeze({
		mapId = source.mapId,
		base = source.base,
		bounds = source.bounds,
		lanes = table.freeze({ lane }),
		placementZones = source.placementZones,
		noPlacementZones = source.noPlacementZones,
		cameraAnchors = source.cameraAnchors,
		playerSpawns = source.playerSpawns,
	})
end

local function malformedPoint(kind: string, position: Vector3, distance: number): any
	return table.freeze({
		kind = kind,
		cframe = CFrame.new(position),
		position = position,
		distance = distance,
	})
end

return TestHarness.suite("server enemy runtime store", {
	TestHarness.case("authenticates construction identity definitions and detached lanes", function(assertions)
		local fixture = EnemyFixtures.createAuthenticatedCatalogFixture()
		fixture.rawEnemies[1].maxHealth = 9_999
		fixture.rawAssets[1].key = "test.mutated"
		local clockState = { now = 25 }
		local result =
			EnemyRuntimeStore.newForTests(MATCH_ID, 7, fixture.catalog, EnemyFixtures.createRuntimeMapSnapshot(), {
				clock = function()
					return clockState.now
				end,
			})
		local store = success(assertions, result)
		local identity = success(assertions, store:getIdentity())
		assertions.equal(identity.matchId, MATCH_ID)
		assertions.equal(identity.enemyEpoch, 7)
		assertDetachedFrozen(assertions, identity)

		local spawned = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		assertions.equal(spawned.currentHealth, 100)
		assertions.equal(spawned.maximumHealth, 100)
		assertions.equal(spawned.speedModifiers.slowMultiplier, 1)
		assertions.equal(spawned.pathProgress, 0)
		assertions.equal(spawned.spawnServerTime, 25)
		assertions.equal(spawned.sampleServerTime, 25)
		assertions.equal(spawned.lifecycle, "Active")
		assertions.equal(spawned.revision, 1)
		assertVectorClose(assertions, spawned.worldCFrame.Position, Vector3.new(0, 5, 0), 1e-6)
		assertVectorClose(assertions, spawned.worldCFrame.LookVector, Vector3.xAxis, 1e-6)
		assertDetachedFrozen(assertions, spawned)
		assertions.isNil((spawned :: any).definition)
		assertions.isNil((spawned :: any).lane)

		local changed = pcall(function()
			(spawned :: any).currentHealth = 0
		end)
		assertions.isFalse(changed)
		assertions.equal(success(assertions, store:get(spawned.runtimeEnemyId)).currentHealth, 100)

		expectError(
			assertions,
			EnemyRuntimeStore.newForTests(
				MATCH_ID,
				1,
				EnemyFixtures.rawEnemies(),
				EnemyFixtures.createRuntimeMapSnapshot(),
				{
					clock = function()
						return 1
					end,
				}
			),
			"UNAUTHENTICATED_CATALOG",
			"new"
		)
		expectError(
			assertions,
			EnemyRuntimeStore.newForTests("bad", 1, fixture.catalog, EnemyFixtures.createRuntimeMapSnapshot(), {
				clock = function()
					return 1
				end,
			}),
			"INVALID_MATCH_ID",
			"new"
		)
		expectError(
			assertions,
			EnemyRuntimeStore.newForTests(MATCH_ID, 0, fixture.catalog, EnemyFixtures.createRuntimeMapSnapshot(), {
				clock = function()
					return 1
				end,
			}),
			"INVALID_EPOCH",
			"new"
		)
	end),

	TestHarness.case("binds only authenticated definitions and valid fixed lanes", function(assertions)
		local store = newStore(assertions)
		expectError(
			assertions,
			store:spawn("enemy:missing", EnemyFixtures.BENT_LANE_ID),
			"DEFINITION_NOT_FOUND",
			"spawn"
		)
		expectError(assertions, store:spawn("bad", EnemyFixtures.BENT_LANE_ID), "INVALID_ENEMY_ID", "spawn")
		expectError(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, "missing"), "LANE_NOT_FOUND", "spawn")
		expectError(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, "UPPERCASE"), "INVALID_LANE_ID", "spawn")
		assertions.equal(store:getMetrics().nextRuntimeEnemyId, 1)

		local first = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		local second = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		assertions.equal(first.runtimeEnemyId, 1)
		assertions.equal(second.runtimeEnemyId, 2)
		assertions.isTrue(first ~= second)

		local mutableMap = {
			mapId = EnemyFixtures.MAP_ID,
			lanes = { EnemyFixtures.createBentLane() },
		}
		expectError(
			assertions,
			EnemyRuntimeStore.newForTests(MATCH_ID, 1, EnemyFixtures.createAuthenticatedCatalog(), mutableMap, {
				clock = function()
					return 1
				end,
			}),
			"INVALID_RUNTIME_MAP",
			"new"
		)
	end),

	TestHarness.case("permits one fresh Studio catalog only before any runtime ID is issued", function(assertions)
		local emptyCatalog = EnemyFixtures.authenticateCatalog({}, {}).catalog
		local runtimeMap = EnemyFixtures.createRuntimeMapSnapshot()
		local installable = success(
			assertions,
			EnemyRuntimeStore.newForTests(MATCH_ID, 1, emptyCatalog, runtimeMap, {
				clock = function()
					return 100
				end,
				studioCatalogInstallEnabled = true,
			})
		)
		local laneIds = success(assertions, installable:listLaneIds())
		assertions.isTrue(table.isfrozen(laneIds))
		assertions.equal(#laneIds, 2)
		assertions.equal(laneIds[1], EnemyFixtures.BENT_LANE_ID)
		assertions.equal(laneIds[2], EnemyFixtures.STRAIGHT_LANE_ID)
		expectError(
			assertions,
			installable:installStudioCatalog(EnemyFixtures.rawEnemies()),
			"UNAUTHENTICATED_CATALOG",
			"installStudioCatalog"
		)
		assertions.isTrue(
			success(assertions, installable:installStudioCatalog(EnemyFixtures.createAuthenticatedCatalog()))
		)
		local spawned =
			success(assertions, installable:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		assertions.equal(spawned.runtimeEnemyId, 1)
		expectError(
			assertions,
			installable:installStudioCatalog(EnemyFixtures.createAuthenticatedCatalog()),
			"STUDIO_ONLY",
			"installStudioCatalog"
		)

		local disabled = success(
			assertions,
			EnemyRuntimeStore.newForTests(MATCH_ID, 1, emptyCatalog, runtimeMap, {
				clock = function()
					return 100
				end,
			})
		)
		expectError(
			assertions,
			disabled:installStudioCatalog(EnemyFixtures.createAuthenticatedCatalog()),
			"STUDIO_ONLY",
			"installStudioCatalog"
		)

		local issued = success(
			assertions,
			EnemyRuntimeStore.newForTests(MATCH_ID, 1, emptyCatalog, runtimeMap, {
				clock = function()
					return 100
				end,
				studioCatalogInstallEnabled = true,
				nextRuntimeEnemyId = 2,
				issuedRuntimeEnemyIds = { 1 },
			})
		)
		expectError(
			assertions,
			issued:installStudioCatalog(EnemyFixtures.createAuthenticatedCatalog()),
			"ILLEGAL_LIFECYCLE",
			"installStudioCatalog"
		)
	end),

	TestHarness.case("binds one exact authenticated finite difficulty before runtime mutation", function(assertions)
		local difficulty = createDifficultyFixture(1.5, 1.25)
		difficulty.rawSources.difficulties[1].modifiers.enemyHealthMultiplier = 999
		difficulty.rawSources.difficulties[1].modifiers.enemyMoveSpeedMultiplier = 999
		local store = newStore(assertions)
		assertions.isTrue(success(assertions, store:bindDifficulty(difficulty.catalog, difficulty.finite)))
		local metrics = store:getMetrics()
		assertions.isTrue(metrics.difficultyBound)
		assertions.equal(metrics.boundDifficultyId, "difficulty:normal")
		assertions.isFalse(metrics.schedulerSampleActive)
		expectError(
			assertions,
			store:bindDifficulty(difficulty.catalog, difficulty.finite),
			"ILLEGAL_LIFECYCLE",
			"bindDifficulty"
		)
		expectError(
			assertions,
			store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
			"SCHEDULER_ONLY",
			"spawn"
		)

		local rawCatalogStore = newStore(assertions)
		expectError(
			assertions,
			rawCatalogStore:bindDifficulty(difficulty.rawSources.difficulties, difficulty.finite),
			"UNAUTHENTICATED_CATALOG",
			"bindDifficulty"
		)
		local copiedDefinition = table.freeze({
			id = difficulty.finite.id,
			kind = difficulty.finite.kind,
			modifiers = difficulty.finite.modifiers,
		})
		expectError(
			assertions,
			rawCatalogStore:bindDifficulty(difficulty.catalog, copiedDefinition),
			"INVALID_DIFFICULTY_DEFINITION",
			"bindDifficulty"
		)
		expectError(
			assertions,
			rawCatalogStore:bindDifficulty(difficulty.catalog, difficulty.endless),
			"INVALID_DIFFICULTY_DEFINITION",
			"bindDifficulty"
		)

		local mutatedStore = newStore(assertions)
		success(assertions, mutatedStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		expectError(
			assertions,
			mutatedStore:bindDifficulty(difficulty.catalog, difficulty.finite),
			"ILLEGAL_LIFECYCLE",
			"bindDifficulty"
		)
	end),

	TestHarness.case(
		"uses one authenticated scheduler sample for exact once modifiers without extra clock reads",
		function(assertions)
			local difficulty = createDifficultyFixture(1.5, 1.25)
			local rawEnemies = EnemyFixtures.rawEnemies()
			rawEnemies[1].leakDamage = 17
			local enemyCatalog = EnemyFixtures.authenticateCatalog(EnemyFixtures.rawAssets(), rawEnemies).catalog
			local clockState = { now = 100, reads = 0 }
			local leakOutcome: any = nil
			local store = success(
				assertions,
				EnemyRuntimeStore.newForTests(MATCH_ID, 1, enemyCatalog, EnemyFixtures.createRuntimeMapSnapshot(), {
					clock = function()
						clockState.reads += 1
						return clockState.now
					end,
					endpointSink = function(outcome: any)
						leakOutcome = outcome
					end,
				})
			)
			assertions.equal(clockState.reads, 1)
			assertions.isTrue(success(assertions, store:bindDifficulty(difficulty.catalog, difficulty.finite)))
			clockState.now = 125
			local stepResult = success(assertions, store:step(0))
			local token = stepResult.schedulerSampleToken
			assertions.equal(stepResult.sampleServerTime, 125)
			assertions.equal(clockState.reads, 2)
			assertions.isTrue(store:isAuthenticatedSchedulerSample(token))
			assertions.isTrue(EnemyRuntimeStore.isAuthenticatedSchedulerSample(token))

			local first = success(
				assertions,
				store:spawnScheduled(token, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID)
			)
			local second = success(
				assertions,
				store:spawnScheduled(token, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID)
			)
			assertions.equal(clockState.reads, 2)
			assertions.equal(first.spawnServerTime, 125)
			assertions.equal(second.spawnServerTime, 125)
			assertions.equal(first.sampleServerTime, 125)
			assertions.equal(first.currentHealth, 150)
			assertions.equal(first.maximumHealth, 150)
			assertions.equal(first.effectiveSpeed, 12.5)
			assertions.equal(second.effectiveSpeed, 12.5)
			assertions.equal(first.speedModifiers.slowMultiplier, 1)

			clockState.now = 126
			local slowed = success(assertions, store:setSlowMultiplier(first.runtimeEnemyId, 0.2))
			assertions.equal(slowed.effectiveSpeed, 2.5)
			assertions.equal(slowed.currentHealth, 150)
			assertions.equal(slowed.maximumHealth, 150)
			assertions.isFalse(store:isAuthenticatedSchedulerSample(token))
			expectError(
				assertions,
				store:spawnScheduled(token, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
				"INVALID_SCHEDULER_SAMPLE",
				"spawnScheduled"
			)
			clockState.now = 130
			success(assertions, store:resolveEndpoint(first.runtimeEnemyId))
			assertions.equal(leakOutcome.leakDamage, 17)
			assertions.equal(leakOutcome.serverTime, 130)
		end
	),

	TestHarness.case("rejects wrong forged stale and explicitly finished scheduler samples", function(assertions)
		local difficulty = createDifficultyFixture()
		local firstStore, firstClock = newStore(assertions)
		local secondStore, secondClock = newStore(assertions)
		success(assertions, firstStore:bindDifficulty(difficulty.catalog, difficulty.finite))
		success(assertions, secondStore:bindDifficulty(difficulty.catalog, difficulty.finite))
		firstClock.now = 101
		local firstToken = success(assertions, firstStore:step(0)).schedulerSampleToken
		local forgedToken = table.freeze({
			matchId = firstToken.matchId,
			enemyEpoch = firstToken.enemyEpoch,
			sampleServerTime = firstToken.sampleServerTime,
		})
		assertions.isFalse(firstStore:isAuthenticatedSchedulerSample(forgedToken))
		expectError(
			assertions,
			firstStore:spawnScheduled(forgedToken, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
			"INVALID_SCHEDULER_SAMPLE",
			"spawnScheduled"
		)
		expectError(
			assertions,
			secondStore:spawnScheduled(firstToken, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
			"INVALID_SCHEDULER_SAMPLE",
			"spawnScheduled"
		)

		firstClock.now = 102
		local replacementToken = success(assertions, firstStore:step(0)).schedulerSampleToken
		assertions.isFalse(firstStore:isAuthenticatedSchedulerSample(firstToken))
		assertions.isTrue(firstStore:isAuthenticatedSchedulerSample(replacementToken))
		expectError(
			assertions,
			firstStore:finishSchedulerSample(firstToken),
			"INVALID_SCHEDULER_SAMPLE",
			"finishSchedulerSample"
		)
		assertions.isTrue(success(assertions, firstStore:finishSchedulerSample(replacementToken)))
		assertions.isFalse(firstStore:isAuthenticatedSchedulerSample(replacementToken))
		expectError(
			assertions,
			firstStore:spawnScheduled(replacementToken, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
			"INVALID_SCHEDULER_SAMPLE",
			"spawnScheduled"
		)

		secondClock.now = 101
		local cleanupToken = success(assertions, secondStore:step(0)).schedulerSampleToken
		assertions.isTrue(success(assertions, secondStore:cleanup()))
		assertions.isFalse(EnemyRuntimeStore.isAuthenticatedSchedulerSample(cleanupToken))
		local cleanedMetrics = secondStore:getMetrics()
		assertions.isFalse(cleanedMetrics.difficultyBound)
		assertions.isFalse(cleanedMetrics.schedulerSampleActive)

		local faultStore, faultClock = newStore(assertions)
		success(assertions, faultStore:bindDifficulty(difficulty.catalog, difficulty.finite))
		faultClock.now = 101
		local faultToken = success(assertions, faultStore:step(0)).schedulerSampleToken
		faultClock.now = 99
		expectError(assertions, faultStore:step(0), "CLOCK_FAILED", "step")
		assertions.isFalse(faultStore:isAuthenticatedSchedulerSample(faultToken))
		assertions.isTrue(faultStore:getMetrics().faulted)
		assertions.isTrue(success(assertions, faultStore:cleanup()))
	end),

	TestHarness.case(
		"fault-despawns only the exact committed scheduler snapshot at its authenticated sample",
		function(assertions)
			local difficulty = createDifficultyFixture()
			local clockState = { now = 100, reads = 0 }
			local store = newStore(assertions, {
				clock = function()
					clockState.reads += 1
					return clockState.now
				end,
			})
			success(assertions, store:bindDifficulty(difficulty.catalog, difficulty.finite))
			clockState.now = 125
			local token = success(assertions, store:step(0)).schedulerSampleToken
			local spawned = success(
				assertions,
				store:spawnScheduled(token, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID)
			)
			local readsBeforeFaultDespawn = clockState.reads

			local forgedToken = table.freeze({
				matchId = token.matchId,
				enemyEpoch = token.enemyEpoch,
				sampleServerTime = token.sampleServerTime,
			})
			expectError(
				assertions,
				store:despawnScheduledForFault(forgedToken, spawned),
				"INVALID_SCHEDULER_SAMPLE",
				"despawnScheduledForFault"
			)
			local alteredSnapshot = table.clone(spawned)
			alteredSnapshot.revision += 1
			table.freeze(alteredSnapshot)
			expectError(
				assertions,
				store:despawnScheduledForFault(token, alteredSnapshot),
				"ILLEGAL_LIFECYCLE",
				"despawnScheduledForFault"
			)
			assertions.equal(store:getMetrics().activeCount, 1)
			assertions.equal(clockState.reads, readsBeforeFaultDespawn)

			local resolution = success(assertions, store:despawnScheduledForFault(token, spawned))
			assertions.equal(clockState.reads, readsBeforeFaultDespawn)
			assertDetachedFrozen(assertions, resolution)
			assertions.equal(resolution.despawn.runtimeEnemyId, spawned.runtimeEnemyId)
			assertions.equal(resolution.despawn.enemyId, spawned.enemyId)
			assertions.equal(resolution.despawn.laneId, spawned.laneId)
			assertions.equal(resolution.despawn.revision, spawned.revision + 1)
			assertions.equal(resolution.despawn.lifecycle, "Despawned")
			assertions.equal(resolution.despawn.reason, "Manual")
			assertions.equal(resolution.despawn.sampleServerTime, 125)
			assertions.equal(resolution.terminalOutcome.matchId, MATCH_ID)
			assertions.equal(resolution.terminalOutcome.enemyEpoch, 1)
			assertions.equal(resolution.terminalOutcome.runtimeEnemyId, spawned.runtimeEnemyId)
			assertions.equal(resolution.terminalOutcome.enemyId, spawned.enemyId)
			assertions.equal(resolution.terminalOutcome.reason, "Manual")
			assertions.equal(resolution.terminalOutcome.serverTime, 125)
			assertions.isTrue(store:isAuthenticatedTerminalOutcome(resolution.terminalOutcome))
			assertions.equal(store:getMetrics().activeCount, 0)
			assertions.equal(store:getMetrics().terminalCount, 1)
			assertions.equal(success(assertions, store:queryTerminal(spawned.runtimeEnemyId)), resolution.despawn)
			local outcomes = success(assertions, store:drainTerminalOutcomes())
			assertions.equal(#outcomes, 1)
			assertions.equal(outcomes[1], resolution.terminalOutcome)
			assertions.isTrue(store:isAuthenticatedSchedulerSample(token))
			expectError(
				assertions,
				store:despawnScheduledForFault(token, spawned),
				"STALE_RUNTIME_ID",
				"despawnScheduledForFault"
			)
			assertions.isTrue(success(assertions, store:finishSchedulerSample(token)))
		end
	),

	TestHarness.case(
		"uses the exact live scheduler sample for bound defeat removal without another clock read",
		function(assertions)
			local difficulty = createDifficultyFixture()
			local clockState = { now = 100, reads = 0 }
			local store = newStore(assertions, {
				clock = function()
					clockState.reads += 1
					return clockState.now
				end,
			})
			success(assertions, store:bindDifficulty(difficulty.catalog, difficulty.finite))
			clockState.now = 125
			local token = success(assertions, store:step(0)).schedulerSampleToken
			local first = success(
				assertions,
				store:spawnScheduled(token, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID)
			)
			local second = success(
				assertions,
				store:spawnScheduled(token, EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID)
			)
			local readsBeforeDefeat = clockState.reads
			local expectedIds = table.freeze({ first.runtimeEnemyId, second.runtimeEnemyId })
			expectError(
				assertions,
				store:despawnAllForDefeat(expectedIds),
				"INVALID_SCHEDULER_SAMPLE",
				"despawnAllForDefeat"
			)
			local forgedToken = table.freeze({
				matchId = token.matchId,
				enemyEpoch = token.enemyEpoch,
				sampleServerTime = token.sampleServerTime,
			})
			expectError(
				assertions,
				store:despawnAllForDefeat(expectedIds, forgedToken),
				"INVALID_SCHEDULER_SAMPLE",
				"despawnAllForDefeat"
			)
			assertions.equal(clockState.reads, readsBeforeDefeat)
			assertions.equal(store:getMetrics().activeCount, 2)

			local despawns = success(assertions, store:despawnAllForDefeat(expectedIds, token))
			assertions.equal(clockState.reads, readsBeforeDefeat)
			assertions.equal(#despawns, 2)
			for _, despawn in despawns do
				assertions.equal(despawn.reason, "Defeat")
				assertions.equal(despawn.sampleServerTime, 125)
			end
			local outcomes = success(assertions, store:drainTerminalOutcomes())
			assertions.equal(#outcomes, 2)
			for _, outcome in outcomes do
				assertions.equal(outcome.reason, "Defeat")
				assertions.equal(outcome.serverTime, 125)
				assertions.isTrue(store:isAuthenticatedTerminalOutcome(outcome))
			end
			assertions.isTrue(store:isAuthenticatedSchedulerSample(token))
			assertions.isTrue(store:getMetrics().schedulerSampleActive)
			assertions.isTrue(success(assertions, store:finishSchedulerSample(token)))
			assertions.isFalse(store:isAuthenticatedSchedulerSample(token))
		end
	),

	TestHarness.case("rejects frozen lanes with zero mismatched or oversized geometric segments", function(assertions)
		local catalog = EnemyFixtures.createAuthenticatedCatalog()
		local malformedLanes = {
			table.freeze({
				id = "zero-span",
				totalDistance = 10,
				points = table.freeze({
					malformedPoint("EnemySpawn", Vector3.zero, 0),
					malformedPoint("DefenderBase", Vector3.zero, 10),
				}),
			}),
			table.freeze({
				id = "mismatch",
				totalDistance = 9,
				points = table.freeze({
					malformedPoint("EnemySpawn", Vector3.zero, 0),
					malformedPoint("DefenderBase", Vector3.new(10, 0, 0), 9),
				}),
			}),
			table.freeze({
				id = "oversized",
				totalDistance = 600,
				points = table.freeze({
					malformedPoint("EnemySpawn", Vector3.zero, 0),
					malformedPoint("DefenderBase", Vector3.new(600, 0, 0), 600),
				}),
			}),
		}
		for _, lane in malformedLanes do
			expectError(
				assertions,
				EnemyRuntimeStore.newForTests(MATCH_ID, 1, catalog, mapWithLane(lane), {
					clock = function()
						return 1
					end,
				}),
				"INVALID_RUNTIME_MAP",
				"new"
			)
		end
	end),

	TestHarness.case("generates ordered nonreused IDs and fails collision or exhaustion closed", function(assertions)
		local store = newStore(assertions, {
			maxActive = 2,
			maxLifetime = 3,
		})
		local first = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		local second = success(assertions, store:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
		expectError(
			assertions,
			store:spawn(EnemyFixtures.SLOW_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
			"CAPACITY_EXCEEDED",
			"spawn"
		)
		success(assertions, store:despawn(first.runtimeEnemyId))
		local third = success(assertions, store:spawn(EnemyFixtures.SLOW_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		assertions.equal(third.runtimeEnemyId, 3)
		success(assertions, store:despawn(second.runtimeEnemyId))
		success(assertions, store:despawn(third.runtimeEnemyId))
		expectError(
			assertions,
			store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
			"ID_EXHAUSTED",
			"spawn"
		)
		expectError(assertions, store:get(first.runtimeEnemyId), "STALE_RUNTIME_ID", "get")
		expectError(assertions, store:get(4), "NOT_FOUND", "get")
		expectError(assertions, store:get(0), "INVALID_RUNTIME_ID", "get")

		local collisionStore = newStore(assertions, {
			maxLifetime = 3,
			nextRuntimeEnemyId = 2,
			issuedRuntimeEnemyIds = { 2 },
		})
		expectError(
			assertions,
			collisionStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
			"ID_COLLISION",
			"spawn"
		)
		assertions.equal(collisionStore:getMetrics().lifetimeCount, 1)
	end),

	TestHarness.case("returns deterministic frozen query ordering without shared mutation", function(assertions)
		local store = newStore(assertions)
		local first = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		local second = success(assertions, store:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
		local third = success(assertions, store:spawn(EnemyFixtures.SLOW_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		success(assertions, store:despawn(second.runtimeEnemyId))
		local listed = success(assertions, store:list())
		assertions.equal(#listed, 2)
		assertions.equal(listed[1].runtimeEnemyId, first.runtimeEnemyId)
		assertions.equal(listed[2].runtimeEnemyId, third.runtimeEnemyId)
		assertDetachedFrozen(assertions, listed)
		local changed = pcall(function()
			table.insert(listed, listed[1])
		end)
		assertions.isFalse(changed)
		assertions.equal(#success(assertions, store:list()), 2)
	end),

	TestHarness.case("owns the sole bounded slow state without combat mutation", function(assertions)
		local store, clock = newStore(assertions)
		local spawned = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		clock.now = 101
		local slowed = success(assertions, store:setSlowMultiplier(spawned.runtimeEnemyId, 0.25))
		assertions.equal(slowed.speedModifiers.slowMultiplier, 0.25)
		assertions.equal(slowed.revision, 2)
		assertions.equal(slowed.sampleServerTime, 101)
		assertions.equal(slowed.currentHealth, slowed.maximumHealth)
		local duplicate = success(assertions, store:setSlowMultiplier(spawned.runtimeEnemyId, 0.25))
		assertions.equal(duplicate.revision, 2)
		for _, invalid in { -0.1, 1.1, 0 / 0, math.huge, "0.5" } do
			expectError(
				assertions,
				store:setSlowMultiplier(spawned.runtimeEnemyId, invalid),
				"INVALID_SLOW_MULTIPLIER",
				"setSlowMultiplier"
			)
		end
		assertions.equal(success(assertions, store:get(spawned.runtimeEnemyId)).currentHealth, 100)
	end),

	TestHarness.case(
		"issues one authenticated definition-derived leak outcome before terminal despawn",
		function(assertions)
			local endpointCount = 0
			local endpointOutcome: any = nil
			local clock = { now = 100 }
			local rawEnemies = EnemyFixtures.rawEnemies()
			rawEnemies[2].leakDamage = 37
			local catalog = EnemyFixtures.authenticateCatalog(EnemyFixtures.rawAssets(), rawEnemies).catalog
			local store: any = nil
			store = success(
				assertions,
				EnemyRuntimeStore.newForTests(MATCH_ID, 1, catalog, EnemyFixtures.createRuntimeMapSnapshot(), {
					clock = function()
						return clock.now
					end,
					endpointSink = function(outcome: any)
						endpointCount += 1
						endpointOutcome = outcome
						assertions.isTrue(store:isAuthenticatedLeakOutcome(outcome))
						assertions.isTrue(EnemyRuntimeStore.isAuthenticatedLeakOutcome(outcome))
					end,
				})
			)
			rawEnemies[2].leakDamage = 9_999
			local spawned = success(assertions, store:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			clock.now = 104
			local resolution = success(assertions, store:resolveEndpoint(spawned.runtimeEnemyId))
			assertions.isTrue(resolution.callbackSucceeded)
			assertions.equal(endpointCount, 1)
			assertions.equal(endpointOutcome.matchId, MATCH_ID)
			assertions.equal(endpointOutcome.enemyEpoch, 1)
			assertions.equal(endpointOutcome.runtimeEnemyId, spawned.runtimeEnemyId)
			assertions.equal(endpointOutcome.enemyId, EnemyFixtures.FAST_ENEMY_ID)
			assertions.equal(endpointOutcome.leakDamage, 37)
			assertions.equal(endpointOutcome.serverTime, 104)
			local outcomeFieldCount = 0
			for _ in endpointOutcome do
				outcomeFieldCount += 1
			end
			assertions.equal(outcomeFieldCount, 6)
			assertDetachedFrozen(assertions, endpointOutcome)
			assertions.isNil(endpointOutcome.lifecycle)
			assertions.isNil(endpointOutcome.laneId)
			assertions.isNil(endpointOutcome.definition)
			assertions.equal(resolution.endpoint.lifecycle, "EndpointResolved")
			assertions.equal(resolution.endpoint.pathProgress, EnemyFixtures.BENT_LANE_TOTAL_DISTANCE)
			assertions.equal(resolution.endpoint.revision, 2)
			assertions.equal(resolution.despawn.lifecycle, "Despawned")
			assertions.equal(resolution.despawn.reason, "Endpoint")
			assertions.equal(resolution.despawn.revision, 3)
			assertVectorClose(assertions, resolution.endpoint.worldCFrame.Position, Vector3.new(20, 5, 20), 1e-6)
			assertVectorClose(assertions, resolution.endpoint.worldCFrame.LookVector, Vector3.xAxis, 1e-6)
			assertDetachedFrozen(assertions, resolution)
			assertions.isNil((resolution :: any).baseDamage)
			assertions.isNil((resolution :: any).matchState)
			assertions.equal(store:getMetrics().retainedLeakOutcomeCount, 1)
			local forgedOutcome = table.freeze({
				matchId = endpointOutcome.matchId,
				enemyEpoch = endpointOutcome.enemyEpoch,
				runtimeEnemyId = endpointOutcome.runtimeEnemyId,
				enemyId = endpointOutcome.enemyId,
				leakDamage = endpointOutcome.leakDamage,
				serverTime = endpointOutcome.serverTime,
			})
			assertions.isFalse(store:isAuthenticatedLeakOutcome(forgedOutcome))
			assertions.isFalse(EnemyRuntimeStore.isAuthenticatedLeakOutcome(forgedOutcome))
			local otherStore = newStore(assertions)
			assertions.isFalse(otherStore:isAuthenticatedLeakOutcome(endpointOutcome))
			assertions.isTrue(success(assertions, otherStore:cleanup()))
			assertions.equal(success(assertions, store:queryTerminal(spawned.runtimeEnemyId)), resolution.despawn)
			expectError(assertions, store:get(spawned.runtimeEnemyId), "STALE_RUNTIME_ID", "get")
			expectError(
				assertions,
				store:resolveEndpoint(spawned.runtimeEnemyId),
				"STALE_RUNTIME_ID",
				"resolveEndpoint"
			)
			expectError(assertions, store:despawn(spawned.runtimeEnemyId), "STALE_RUNTIME_ID", "despawn")
			assertions.equal(endpointCount, 1)
			assertions.isTrue(success(assertions, store:cleanup()))
			assertions.isFalse(store:isAuthenticatedLeakOutcome(endpointOutcome))
			assertions.isFalse(EnemyRuntimeStore.isAuthenticatedLeakOutcome(endpointOutcome))
			assertions.equal(store:getMetrics().retainedLeakOutcomeCount, 0)
		end
	),

	TestHarness.case(
		"queues ordered separately authenticated endpoint manual and defeat terminal outcomes",
		function(assertions)
			local clockState = { now = 100 }
			local endpointLeak: any = nil
			local store = success(
				assertions,
				EnemyRuntimeStore.newForTests(
					MATCH_ID,
					7,
					EnemyFixtures.createAuthenticatedCatalog(),
					EnemyFixtures.createRuntimeMapSnapshot(),
					{
						clock = function()
							return clockState.now
						end,
						endpointSink = function(outcome: any)
							endpointLeak = outcome
						end,
					}
				)
			)
			local first = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			local second = success(assertions, store:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			local third = success(assertions, store:spawn(EnemyFixtures.SLOW_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			local fourth =
				success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
			clockState.now = 101
			success(assertions, store:resolveEndpoint(first.runtimeEnemyId))
			clockState.now = 102
			success(assertions, store:despawn(second.runtimeEnemyId))
			clockState.now = 103
			success(
				assertions,
				store:despawnAllForDefeat(table.freeze({ third.runtimeEnemyId, fourth.runtimeEnemyId }))
			)

			local beforeDrain = store:getMetrics()
			assertions.equal(beforeDrain.queuedTerminalOutcomeCount, 4)
			assertions.equal(beforeDrain.retainedTerminalOutcomeCount, 4)
			local outcomes = success(assertions, store:drainTerminalOutcomes())
			assertDetachedFrozen(assertions, outcomes)
			assertions.equal(#outcomes, 4)
			local expectedReasons = { "Endpoint", "Manual", "Defeat", "Defeat" }
			local expectedTimes = { 101, 102, 103, 103 }
			local expectedIds = {
				first.runtimeEnemyId,
				second.runtimeEnemyId,
				third.runtimeEnemyId,
				fourth.runtimeEnemyId,
			}
			for index, outcome in outcomes do
				assertions.equal(outcome.matchId, MATCH_ID)
				assertions.equal(outcome.enemyEpoch, 7)
				assertions.equal(outcome.runtimeEnemyId, expectedIds[index])
				assertions.equal(outcome.reason, expectedReasons[index])
				assertions.equal(outcome.serverTime, expectedTimes[index])
				assertions.isTrue(store:isAuthenticatedTerminalOutcome(outcome))
				assertions.isTrue(EnemyRuntimeStore.isAuthenticatedTerminalOutcome(outcome))
				local fieldCount = 0
				for _ in outcome do
					fieldCount += 1
				end
				assertions.equal(fieldCount, 6)
				assertions.isNil((outcome :: any).leakDamage)
				assertions.isNil((outcome :: any).laneId)
			end
			assertions.isTrue(endpointLeak ~= outcomes[1])
			assertions.isTrue(store:isAuthenticatedLeakOutcome(endpointLeak))
			assertions.isFalse(store:isAuthenticatedTerminalOutcome(endpointLeak))
			assertions.isFalse(EnemyRuntimeStore.isAuthenticatedTerminalOutcome(endpointLeak))

			local forged = table.freeze({
				matchId = outcomes[1].matchId,
				enemyEpoch = outcomes[1].enemyEpoch,
				runtimeEnemyId = outcomes[1].runtimeEnemyId,
				enemyId = outcomes[1].enemyId,
				reason = outcomes[1].reason,
				serverTime = outcomes[1].serverTime,
			})
			assertions.isFalse(store:isAuthenticatedTerminalOutcome(forged))
			assertions.isFalse(EnemyRuntimeStore.isAuthenticatedTerminalOutcome(forged))
			local otherStore = newStore(assertions)
			assertions.isFalse(otherStore:isAuthenticatedTerminalOutcome(outcomes[1]))
			success(assertions, otherStore:cleanup())

			local afterDrain = store:getMetrics()
			assertions.equal(afterDrain.queuedTerminalOutcomeCount, 0)
			assertions.equal(afterDrain.retainedTerminalOutcomeCount, 4)
			assertions.equal(#success(assertions, store:drainTerminalOutcomes()), 0)
			for _, outcome in outcomes do
				assertions.isTrue(store:isAuthenticatedTerminalOutcome(outcome))
			end
			assertions.isTrue(success(assertions, store:cleanup()))
			for _, outcome in outcomes do
				assertions.isFalse(store:isAuthenticatedTerminalOutcome(outcome))
				assertions.isFalse(EnemyRuntimeStore.isAuthenticatedTerminalOutcome(outcome))
			end
			assertions.equal(store:getMetrics().retainedTerminalOutcomeCount, 0)
		end
	),

	TestHarness.case(
		"contains callback errors yields and forbidden mutation reentry after terminalizing",
		function(assertions)
			local reentryResult: any = nil
			local store: any = nil
			store = newStore(assertions, {
				endpointSink = function(snapshot: any)
					reentryResult = store:despawn(snapshot.runtimeEnemyId)
				end,
			})
			local spawned = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			local resolution = success(assertions, store:resolveEndpoint(spawned.runtimeEnemyId))
			assertions.isFalse(resolution.callbackSucceeded)
			expectError(assertions, reentryResult, "REENTRANT", "despawn")
			assertions.equal(success(assertions, store:queryTerminal(spawned.runtimeEnemyId)).reason, "Endpoint")
			assertions.isTrue(store:getMetrics().faulted)
			expectError(
				assertions,
				store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
				"FAULTED",
				"spawn"
			)

			local yieldingStore = newStore(assertions, {
				endpointSink = function()
					coroutine.yield()
				end,
			})
			local yieldingEnemy =
				success(assertions, yieldingStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			local yieldingResolution = success(assertions, yieldingStore:resolveEndpoint(yieldingEnemy.runtimeEnemyId))
			assertions.isFalse(yieldingResolution.callbackSucceeded)
			assertions.equal(
				success(assertions, yieldingStore:queryTerminal(yieldingEnemy.runtimeEnemyId)).reason,
				"Endpoint"
			)

			local throwingStore = newStore(assertions, {
				endpointSink = function()
					error("private endpoint failure", 0)
				end,
			})
			local throwingEnemy =
				success(assertions, throwingStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			local throwingResolution = success(assertions, throwingStore:resolveEndpoint(throwingEnemy.runtimeEnemyId))
			assertions.isFalse(throwingResolution.callbackSucceeded)
			assertions.equal(throwingResolution.endpoint.lifecycle, "EndpointResolved")
			assertions.equal(throwingResolution.despawn.reason, "Endpoint")
		end
	),

	TestHarness.case(
		"bounds scheduler capacity revokes on timed mutation and faults terminal drain reentry",
		function(assertions)
			local difficulty = createDifficultyFixture()
			local store, clock = newStore(assertions, {
				maxActive = 1,
				maxLifetime = 1,
			})
			success(assertions, store:bindDifficulty(difficulty.catalog, difficulty.finite))
			clock.now = 101
			local token = success(assertions, store:step(0)).schedulerSampleToken
			local spawned = success(
				assertions,
				store:spawnScheduled(token, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID)
			)
			expectError(
				assertions,
				store:spawnScheduled(token, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
				"CAPACITY_EXCEEDED",
				"spawnScheduled"
			)
			clock.now = 102
			success(assertions, store:despawn(spawned.runtimeEnemyId))
			assertions.isFalse(store:isAuthenticatedSchedulerSample(token))
			assertions.equal(store:getMetrics().queuedTerminalOutcomeCount, 1)
			clock.now = 103
			local exhaustedToken = success(assertions, store:step(0)).schedulerSampleToken
			expectError(
				assertions,
				store:spawnScheduled(exhaustedToken, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
				"ID_EXHAUSTED",
				"spawnScheduled"
			)
			success(assertions, store:finishSchedulerSample(exhaustedToken))

			local drainReentryResult: any = nil
			local reentryStore: any = nil
			reentryStore = newStore(assertions, {
				endpointSink = function()
					drainReentryResult = reentryStore:drainTerminalOutcomes()
				end,
			})
			local reentryEnemy =
				success(assertions, reentryStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			local resolution = success(assertions, reentryStore:resolveEndpoint(reentryEnemy.runtimeEnemyId))
			assertions.isFalse(resolution.callbackSucceeded)
			expectError(assertions, drainReentryResult, "REENTRANT", "drainTerminalOutcomes")
			local reentryMetrics = reentryStore:getMetrics()
			assertions.isTrue(reentryMetrics.faulted)
			assertions.equal(reentryMetrics.queuedTerminalOutcomeCount, 1)
			assertions.equal(reentryMetrics.retainedTerminalOutcomeCount, 1)
			assertions.isTrue(success(assertions, reentryStore:cleanup()))
			assertions.equal(reentryStore:getMetrics().queuedTerminalOutcomeCount, 0)
		end
	),

	TestHarness.case("defers cleanup requested inside an endpoint callback to a safe boundary", function(assertions)
		local cleanupResult: any = nil
		local endpointOutcome: any = nil
		local authenticDuringCallback = false
		local store: any = nil
		store = newStore(assertions, {
			endpointSink = function(outcome: any)
				endpointOutcome = outcome
				authenticDuringCallback = store:isAuthenticatedLeakOutcome(outcome)
				cleanupResult = store:cleanup()
			end,
		})
		local spawned = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		local resolution = success(assertions, store:resolveEndpoint(spawned.runtimeEnemyId))
		assertions.equal(resolution.despawn.reason, "Endpoint")
		assertions.isTrue(cleanupResult.ok)
		assertions.isFalse(cleanupResult.value)
		assertions.isTrue(authenticDuringCallback)
		assertions.isFalse(store:isAuthenticatedLeakOutcome(endpointOutcome))
		assertions.isFalse(EnemyRuntimeStore.isAuthenticatedLeakOutcome(endpointOutcome))
		local metrics = store:getMetrics()
		assertions.isTrue(metrics.cleaned)
		assertions.equal(metrics.activeCount, 0)
		assertions.equal(metrics.lifetimeCount, 0)
		assertions.equal(metrics.terminalCount, 0)
		assertions.equal(metrics.retainedLeakOutcomeCount, 0)
		expectError(assertions, store:get(spawned.runtimeEnemyId), "CLEANED", "get")
		assertions.isFalse(success(assertions, store:cleanup()))
	end),

	TestHarness.case("rejects invalid or backwards clocks without partial IDs or records", function(assertions)
		local store, clock = newStore(assertions)
		local first = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		clock.now = 99
		expectError(
			assertions,
			store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
			"CLOCK_FAILED",
			"spawn"
		)
		assertions.equal(store:getMetrics().activeCount, 1)
		assertions.equal(store:getMetrics().nextRuntimeEnemyId, 2)
		assertions.isTrue(store:getMetrics().faulted)
		assertions.equal(success(assertions, store:get(first.runtimeEnemyId)).runtimeEnemyId, 1)
		clock.now = 101
		expectError(
			assertions,
			store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
			"FAULTED",
			"spawn"
		)

		for _, invalid in { -1, 0 / 0, math.huge, "now" } do
			expectError(
				assertions,
				EnemyRuntimeStore.newForTests(
					MATCH_ID,
					1,
					EnemyFixtures.createAuthenticatedCatalog(),
					EnemyFixtures.createRuntimeMapSnapshot(),
					{
						clock = function()
							return invalid
						end,
					}
				),
				"CLOCK_FAILED",
				"new"
			)
		end
	end),

	TestHarness.case("preserves unbound zero-step and repeated legacy step behavior", function(assertions)
		local clockState = { now = 100, reads = 0 }
		local store = success(
			assertions,
			EnemyRuntimeStore.newForTests(
				MATCH_ID,
				1,
				EnemyFixtures.createAuthenticatedCatalog(),
				EnemyFixtures.createRuntimeMapSnapshot(),
				{
					clock = function()
						clockState.reads += 1
						return clockState.now
					end,
				}
			)
		)
		assertions.equal(clockState.reads, 1)
		local noOp = success(assertions, store:step(0))
		assertions.equal(clockState.reads, 1)
		assertions.isNil(noOp.sampleServerTime)
		assertions.isNil(noOp.schedulerSampleToken)
		local spawned = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		assertions.equal(spawned.currentHealth, 100)
		assertions.equal(spawned.effectiveSpeed, 10)
		clockState.now = 101
		local firstStep = success(assertions, store:step(0.1))
		clockState.now = 102
		local secondStep = success(assertions, store:step(0.1))
		assertions.isNil(firstStep.schedulerSampleToken)
		assertions.isNil(secondStep.schedulerSampleToken)
		assertions.equal(clockState.reads, 4)
	end),

	TestHarness.case("guards clock callbacks against recursive mutation and deferred cleanup", function(assertions)
		local catalog = EnemyFixtures.createAuthenticatedCatalog()
		local runtimeMap = EnemyFixtures.createRuntimeMapSnapshot()
		local recursiveStore: any = nil
		local recursiveResult: any = nil
		local recursiveArmed = false
		local recursiveConstruction = EnemyRuntimeStore.newForTests(MATCH_ID, 1, catalog, runtimeMap, {
			clock = function()
				if recursiveArmed then
					recursiveResult = recursiveStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID)
				end
				return 100
			end,
		})
		recursiveStore = success(assertions, recursiveConstruction)
		recursiveArmed = true
		expectError(
			assertions,
			recursiveStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
			"CLOCK_FAILED",
			"spawn"
		)
		expectError(assertions, recursiveResult, "REENTRANT", "spawn")
		local recursiveMetrics = recursiveStore:getMetrics()
		assertions.isTrue(recursiveMetrics.faulted)
		assertions.equal(recursiveMetrics.activeCount, 0)
		assertions.equal(recursiveMetrics.lifetimeCount, 0)
		assertions.equal(recursiveMetrics.nextRuntimeEnemyId, 1)

		local cleanupStore: any = nil
		local cleanupResult: any = nil
		local cleanupArmed = false
		local cleanupConstruction = EnemyRuntimeStore.newForTests(MATCH_ID, 1, catalog, runtimeMap, {
			clock = function()
				if cleanupArmed then
					cleanupResult = cleanupStore:cleanup()
				end
				return 100
			end,
		})
		cleanupStore = success(assertions, cleanupConstruction)
		cleanupArmed = true
		expectError(
			assertions,
			cleanupStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID),
			"CLEANED",
			"spawn"
		)
		assertions.isTrue(cleanupResult.ok)
		assertions.isFalse(cleanupResult.value)
		local cleanupMetrics = cleanupStore:getMetrics()
		assertions.isTrue(cleanupMetrics.cleaned)
		assertions.equal(cleanupMetrics.activeCount, 0)
		assertions.equal(cleanupMetrics.lifetimeCount, 0)
		assertions.equal(cleanupMetrics.nextRuntimeEnemyId, 1)
	end),

	TestHarness.case(
		"terminalizes the exact active snapshot for defeat in ascending order with one clock sample and no leaks",
		function(assertions)
			local clockState = { now = 100, reads = 0 }
			local endpointCalls = 0
			local store = success(
				assertions,
				EnemyRuntimeStore.newForTests(
					MATCH_ID,
					1,
					EnemyFixtures.createAuthenticatedCatalog(),
					EnemyFixtures.createRuntimeMapSnapshot(),
					{
						clock = function()
							clockState.reads += 1
							return clockState.now
						end,
						endpointSink = function()
							endpointCalls += 1
						end,
					}
				)
			)
			local first = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			local removed = success(assertions, store:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			local third = success(assertions, store:spawn(EnemyFixtures.SLOW_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
			clockState.now = 101
			success(assertions, store:despawn(removed.runtimeEnemyId))
			local fourth = success(assertions, store:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))

			clockState.now = 250
			local readsBefore = clockState.reads
			local despawns = success(
				assertions,
				store:despawnAllForDefeat(table.freeze({
					first.runtimeEnemyId,
					third.runtimeEnemyId,
					fourth.runtimeEnemyId,
				}))
			)
			assertions.equal(clockState.reads, readsBefore + 1)
			assertions.equal(endpointCalls, 0)
			assertions.equal(#despawns, 3)
			assertDetachedFrozen(assertions, despawns)
			for index, expectedId in { first.runtimeEnemyId, third.runtimeEnemyId, fourth.runtimeEnemyId } do
				local despawn = despawns[index]
				assertions.equal(despawn.runtimeEnemyId, expectedId)
				assertions.equal(despawn.reason, "Defeat")
				assertions.equal(despawn.lifecycle, "Despawned")
				assertions.equal(despawn.revision, 2)
				assertions.equal(despawn.sampleServerTime, 250)
				assertions.equal(success(assertions, store:queryTerminal(expectedId)), despawn)
			end
			local metrics = store:getMetrics()
			assertions.equal(metrics.activeCount, 0)
			assertions.equal(metrics.terminalCount, 4)
			assertions.equal(metrics.retainedLeakOutcomeCount, 0)
			assertions.isFalse(metrics.cleaned)
			assertions.isFalse(metrics.faulted)

			clockState.now = 251
			local postDefeatSpawn =
				success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			assertions.equal(postDefeatSpawn.runtimeEnemyId, 5)
			assertions.equal(endpointCalls, 0)
		end
	),

	TestHarness.case("accepts an exact empty defeat snapshot and samples its clock once", function(assertions)
		local clockReads = 0
		local store = success(
			assertions,
			EnemyRuntimeStore.newForTests(
				MATCH_ID,
				1,
				EnemyFixtures.createAuthenticatedCatalog(),
				EnemyFixtures.createRuntimeMapSnapshot(),
				{
					clock = function()
						clockReads += 1
						return 100
					end,
				}
			)
		)
		local readsBefore = clockReads
		local despawns = success(assertions, store:despawnAllForDefeat(table.freeze({})))
		assertions.equal(clockReads, readsBefore + 1)
		assertions.equal(#despawns, 0)
		assertDetachedFrozen(assertions, despawns)
		assertions.equal(store:getMetrics().activeCount, 0)
		assertions.isFalse(store:getMetrics().cleaned)
	end),

	TestHarness.case("rejects malformed or stale defeat snapshots before time or mutation", function(assertions)
		local clockState = { now = 100, reads = 0 }
		local store = success(
			assertions,
			EnemyRuntimeStore.newForTests(
				MATCH_ID,
				1,
				EnemyFixtures.createAuthenticatedCatalog(),
				EnemyFixtures.createRuntimeMapSnapshot(),
				{
					clock = function()
						clockState.reads += 1
						return clockState.now
					end,
				}
			)
		)
		for _ = 1, 3 do
			success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		end
		local readsBefore = clockState.reads
		local hostileIndexReads = 0
		local hostile = setmetatable({}, {
			__index = function()
				hostileIndexReads += 1
				return 1
			end,
		})
		local extraField = { 1, 2, 3 }
		(extraField :: any).extra = true
		local malformed: { { value: any, code: string } } = {
			{ value = "1,2,3", code = "INVALID_RUNTIME_ID" },
			{ value = hostile, code = "INVALID_RUNTIME_ID" },
			{ value = { [1] = 1, [3] = 3 }, code = "INVALID_RUNTIME_ID" },
			{ value = extraField, code = "INVALID_RUNTIME_ID" },
			{ value = { 1, 1, 3 }, code = "INVALID_RUNTIME_ID" },
			{ value = { 2, 1, 3 }, code = "INVALID_RUNTIME_ID" },
			{ value = { 0, 2, 3 }, code = "INVALID_RUNTIME_ID" },
			{ value = { 1, 2, math.huge }, code = "INVALID_RUNTIME_ID" },
			{ value = { 1, 2 }, code = "STALE_RUNTIME_ID" },
			{ value = { 1, 2, 4 }, code = "STALE_RUNTIME_ID" },
			{ value = { 1, 2, 3, 4 }, code = "STALE_RUNTIME_ID" },
		}
		for _, fixture in malformed do
			expectError(assertions, store:despawnAllForDefeat(fixture.value), fixture.code, "despawnAllForDefeat")
			assertions.equal(store:getMetrics().activeCount, 3)
			assertions.equal(store:getMetrics().terminalCount, 0)
		end
		assertions.equal(hostileIndexReads, 0)
		assertions.equal(clockState.reads, readsBefore)

		clockState.now = 101
		success(assertions, store:despawn(2))
		local postDespawnReads = clockState.reads
		expectError(
			assertions,
			store:despawnAllForDefeat(table.freeze({ 1, 2, 3 })),
			"STALE_RUNTIME_ID",
			"despawnAllForDefeat"
		)
		assertions.equal(clockState.reads, postDespawnReads)
		assertions.equal(store:getMetrics().activeCount, 2)
		assertions.equal(store:getMetrics().terminalCount, 1)
	end),

	TestHarness.case(
		"fails defeat time callbacks without partial terminalization and guards reentry",
		function(assertions)
			local clockState = { now = 100, yieldOnRead = false }
			local yieldingStore = success(
				assertions,
				EnemyRuntimeStore.newForTests(
					MATCH_ID,
					1,
					EnemyFixtures.createAuthenticatedCatalog(),
					EnemyFixtures.createRuntimeMapSnapshot(),
					{
						clock = function()
							if clockState.yieldOnRead then
								coroutine.yield()
							end
							return clockState.now
						end,
					}
				)
			)
			success(assertions, yieldingStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			success(assertions, yieldingStore:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
			clockState.yieldOnRead = true
			expectError(
				assertions,
				yieldingStore:despawnAllForDefeat(table.freeze({ 1, 2 })),
				"CLOCK_FAILED",
				"despawnAllForDefeat"
			)
			assertions.equal(yieldingStore:getMetrics().activeCount, 2)
			assertions.equal(yieldingStore:getMetrics().terminalCount, 0)
			assertions.isTrue(yieldingStore:getMetrics().faulted)

			local reentryResult: any = nil
			local reentryStore: any = nil
			reentryStore = newStore(assertions, {
				endpointSink = function()
					reentryResult = reentryStore:despawnAllForDefeat(table.freeze({ 1, 2 }))
				end,
			})
			success(assertions, reentryStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			success(assertions, reentryStore:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
			local endpoint = success(assertions, reentryStore:resolveEndpoint(1))
			assertions.isFalse(endpoint.callbackSucceeded)
			expectError(assertions, reentryResult, "REENTRANT", "despawnAllForDefeat")
			assertions.equal(reentryStore:getMetrics().activeCount, 1)
			assertions.equal(reentryStore:getMetrics().terminalCount, 1)
			assertions.equal(reentryStore:getMetrics().retainedLeakOutcomeCount, 1)
			assertions.isTrue(success(assertions, reentryStore:cleanup()))
			assertions.isFalse(success(assertions, reentryStore:cleanup()))

			local cleanupStore: any = nil
			local cleanupResult: any = nil
			local cleanupArmed = false
			cleanupStore = success(
				assertions,
				EnemyRuntimeStore.newForTests(
					MATCH_ID,
					1,
					EnemyFixtures.createAuthenticatedCatalog(),
					EnemyFixtures.createRuntimeMapSnapshot(),
					{
						clock = function()
							if cleanupArmed then
								cleanupResult = cleanupStore:cleanup()
							end
							return 100
						end,
					}
				)
			)
			success(assertions, cleanupStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			success(assertions, cleanupStore:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
			cleanupArmed = true
			expectError(
				assertions,
				cleanupStore:despawnAllForDefeat(table.freeze({ 1, 2 })),
				"CLEANED",
				"despawnAllForDefeat"
			)
			assertions.isTrue(cleanupResult.ok)
			assertions.isFalse(cleanupResult.value)
			assertions.isTrue(cleanupStore:getMetrics().cleaned)
			assertions.equal(cleanupStore:getMetrics().activeCount, 0)
			assertions.equal(cleanupStore:getMetrics().terminalCount, 0)
		end
	),

	TestHarness.case(
		"terminalizes the maximum active defeat batch and cleanup releases every record",
		function(assertions)
			local endpointCalls = 0
			local store, clock = newStore(assertions, {
				endpointSink = function()
					endpointCalls += 1
				end,
			})
			local expectedIds: { number } = table.create(EnemyRuntimeStore.MAX_ACTIVE)
			for runtimeEnemyId = 1, EnemyRuntimeStore.MAX_ACTIVE do
				success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
				table.insert(expectedIds, runtimeEnemyId)
			end
			clock.now = 500
			table.freeze(expectedIds)
			local despawns = success(assertions, store:despawnAllForDefeat(expectedIds))
			assertions.equal(#despawns, EnemyRuntimeStore.MAX_ACTIVE)
			assertions.equal(despawns[1].runtimeEnemyId, 1)
			assertions.equal(despawns[#despawns].runtimeEnemyId, EnemyRuntimeStore.MAX_ACTIVE)
			assertions.equal(endpointCalls, 0)
			assertions.equal(store:getMetrics().activeCount, 0)
			assertions.equal(store:getMetrics().terminalCount, EnemyRuntimeStore.MAX_ACTIVE)
			assertions.isTrue(success(assertions, store:cleanup()))
			local cleaned = store:getMetrics()
			assertions.equal(cleaned.activeCount, 0)
			assertions.equal(cleaned.terminalCount, 0)
			assertions.equal(cleaned.lifetimeCount, 0)
			assertions.equal(cleaned.retainedLeakOutcomeCount, 0)
			assertions.isFalse(success(assertions, store:cleanup()))
		end
	),

	TestHarness.case("mass cleanup is exact idempotent and releases all bounded state", function(assertions)
		local store = newStore(assertions, {
			endpointSink = function() end,
		})
		for index = 1, 32 do
			local enemyId = if index % 2 == 0 then EnemyFixtures.FAST_ENEMY_ID else EnemyFixtures.NORMAL_ENEMY_ID
			success(assertions, store:spawn(enemyId, EnemyFixtures.BENT_LANE_ID))
		end
		local before = store:getMetrics()
		assertions.equal(before.activeCount, 32)
		assertions.equal(before.lifetimeCount, 32)
		assertions.equal(before.retainedLeakOutcomeCount, 0)
		assertions.equal(before.retainedLaneCount, 2)
		assertions.isTrue(before.retainsCatalog)
		assertions.isTrue(before.retainsClockCallback)
		assertions.isTrue(before.retainsEndpointCallback)
		assertions.equal(#success(assertions, store:list()), 32)
		assertions.isTrue(success(assertions, store:cleanup()))
		local after = store:getMetrics()
		assertions.isTrue(after.cleaned)
		assertions.equal(after.activeCount, 0)
		assertions.equal(after.lifetimeCount, 0)
		assertions.equal(after.terminalCount, 0)
		assertions.equal(after.retainedLeakOutcomeCount, 0)
		assertions.equal(after.nextRuntimeEnemyId, 1)
		assertions.equal(after.retainedLaneCount, 0)
		assertions.isFalse(after.retainsCatalog)
		assertions.isFalse(after.retainsClockCallback)
		assertions.isFalse(after.retainsEndpointCallback)
		assertions.isFalse(success(assertions, store:cleanup()))
		expectError(assertions, store:list(), "CLEANED", "list")
	end),
})
