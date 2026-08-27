--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local EnemyFixtures = require(script.Parent.Parent.Fixtures.EnemyFixtures)
local EnemyRuntimeStore = require(script.Parent.Parent.ProductionServerEnemies.EnemyRuntimeStore)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase09-movement"

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected Phase 09 movement operation to succeed", 0)
	end
	return result.value
end

local function expectError(assertions: Assertions, result: any, code: string)
	assertions.isFalse(result.ok)
	if not result.ok then
		assertions.equal(result.error.code, code)
	end
end

local function assertClose(assertions: Assertions, actual: number, expected: number, tolerance: number)
	assertions.isTrue(math.abs(actual - expected) <= tolerance)
end

local function assertVectorClose(assertions: Assertions, actual: Vector3, expected: Vector3, tolerance: number)
	assertions.isTrue((actual - expected).Magnitude <= tolerance)
end

local function newStore(
	assertions: Assertions,
	catalog: any?,
	endpointSink: ((snapshot: any) -> ())?,
	runtimeMap: any?
): (EnemyRuntimeStore.Store, { now: number, calls: number })
	local clock = { now = 100, calls = 0 }
	local result = EnemyRuntimeStore.newForTests(
		MATCH_ID,
		1,
		catalog or EnemyFixtures.createAuthenticatedCatalog(),
		runtimeMap or EnemyFixtures.createRuntimeMapSnapshot(),
		{
			clock = function()
				clock.calls += 1
				return clock.now
			end,
			endpointSink = endpointSink,
		}
	)
	return success(assertions, result), clock
end

return TestHarness.suite("fixed lane enemy movement", {
	TestHarness.case("samples exact spawn outgoing corners and endpoint orientation", function(assertions)
		local store, clock = newStore(assertions)
		local spawned = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		assertions.equal(spawned.segmentIndex, 1)
		assertions.equal(spawned.segmentStartDistance, 0)
		assertions.equal(spawned.segmentEndDistance, 10)
		assertVectorClose(assertions, spawned.worldCFrame.Position, Vector3.new(0, 5, 0), 1e-6)
		assertVectorClose(assertions, spawned.worldCFrame.LookVector, Vector3.xAxis, 1e-6)

		clock.now = 101
		success(assertions, store:step(1))
		local firstCorner = success(assertions, store:get(spawned.runtimeEnemyId))
		assertions.equal(firstCorner.pathProgress, 10)
		assertions.equal(firstCorner.segmentIndex, 2)
		assertVectorClose(assertions, firstCorner.worldCFrame.Position, Vector3.new(10, 5, 0), 1e-6)
		assertVectorClose(assertions, firstCorner.worldCFrame.LookVector, Vector3.zAxis, 1e-6)

		clock.now = 103
		success(assertions, store:step(2))
		local secondCorner = success(assertions, store:get(spawned.runtimeEnemyId))
		assertions.equal(secondCorner.pathProgress, 30)
		assertions.equal(secondCorner.segmentIndex, 3)
		assertVectorClose(assertions, secondCorner.worldCFrame.Position, Vector3.new(10, 5, 20), 1e-6)
		assertVectorClose(assertions, secondCorner.worldCFrame.LookVector, Vector3.xAxis, 1e-6)

		clock.now = 104
		local endpointStep = success(assertions, store:step(1))
		assertions.equal(endpointStep.endpointCount, 1)
		local endpoint = endpointStep.endpointResolutions[1].endpoint
		assertions.equal(endpoint.pathProgress, 40)
		assertions.equal(endpoint.segmentIndex, 3)
		assertVectorClose(assertions, endpoint.worldCFrame.Position, Vector3.new(20, 5, 20), 1e-6)
		assertVectorClose(assertions, endpoint.worldCFrame.LookVector, Vector3.xAxis, 1e-6)
	end),

	TestHarness.case("crosses multiple straight segments without losing overshoot", function(assertions)
		local store, clock = newStore(assertions)
		local spawned = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		clock.now = 103.5
		local step = success(assertions, store:step(3.5))
		assertions.equal(step.visitedCount, 1)
		assertions.equal(step.updatedCount, 1)
		assertions.equal(step.endpointCount, 0)
		assertions.isTrue(table.isfrozen(step.updatedRuntimeEnemyIds))
		assertions.equal(#step.updatedRuntimeEnemyIds, 1)
		assertions.equal(step.updatedRuntimeEnemyIds[1], spawned.runtimeEnemyId)
		local moved = success(assertions, store:get(spawned.runtimeEnemyId))
		assertions.equal(moved.pathProgress, 35)
		assertions.equal(moved.segmentIndex, 3)
		assertVectorClose(assertions, moved.worldCFrame.Position, Vector3.new(15, 5, 20), 1e-6)
	end),

	TestHarness.case("samples canonical boundaries without biasing analytic progress", function(assertions)
		local wholeStore, wholeClock = newStore(assertions)
		local partitionedStore, partitionedClock = newStore(assertions)
		local wholeEnemy =
			success(assertions, wholeStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		local partitionedEnemy =
			success(assertions, partitionedStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))

		wholeClock.now = 101
		success(assertions, wholeStore:step(1 - 1e-10))
		partitionedClock.now = 100.4
		success(assertions, partitionedStore:step(0.4))
		partitionedClock.now = 101
		success(assertions, partitionedStore:step(0.6 - 1e-10))

		local whole = success(assertions, wholeStore:get(wholeEnemy.runtimeEnemyId))
		local partitioned = success(assertions, partitionedStore:get(partitionedEnemy.runtimeEnemyId))
		assertClose(assertions, whole.pathProgress, 10 - 1e-9, 1e-12)
		assertClose(assertions, partitioned.pathProgress, 10 - 1e-9, 1e-12)
		assertions.equal(whole.segmentIndex, 2)
		assertions.equal(partitioned.segmentIndex, 2)
		assertVectorClose(assertions, whole.worldCFrame.Position, Vector3.new(10, 5, 0), 1e-6)
		assertVectorClose(assertions, whole.worldCFrame.LookVector, Vector3.zAxis, 1e-6)

		wholeClock.now = 104
		local terminal = success(assertions, wholeStore:step(3 - 1e-10))
		assertions.equal(terminal.endpointCount, 1)
		assertions.equal(terminal.endpointResolutions[1].endpoint.pathProgress, 40)
		expectError(assertions, wholeStore:get(wholeEnemy.runtimeEnemyId), "STALE_RUNTIME_ID")
	end),

	TestHarness.case("never erases tiny positive partitioned movement at spawn or after a corner", function(assertions)
		local function comparePartitions(beginAtCorner: boolean)
			local wholeStore, wholeClock = newStore(assertions)
			local partitionedStore, partitionedClock = newStore(assertions)
			local wholeEnemy =
				success(assertions, wholeStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			local partitionedEnemy =
				success(assertions, partitionedStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
			if beginAtCorner then
				wholeClock.now = 101
				partitionedClock.now = 101
				success(assertions, wholeStore:step(1))
				success(assertions, partitionedStore:step(1))
			end
			success(assertions, wholeStore:setSlowMultiplier(wholeEnemy.runtimeEnemyId, 1e-8))
			success(assertions, partitionedStore:setSlowMultiplier(partitionedEnemy.runtimeEnemyId, 1e-8))

			local startTime = if beginAtCorner then 101 else 100
			wholeClock.now = startTime + 1
			success(assertions, wholeStore:step(1))
			for index = 1, 10 do
				partitionedClock.now = startTime + index * 0.1
				success(assertions, partitionedStore:step(0.1))
			end

			local whole = success(assertions, wholeStore:get(wholeEnemy.runtimeEnemyId))
			local partitioned = success(assertions, partitionedStore:get(partitionedEnemy.runtimeEnemyId))
			local startingProgress = if beginAtCorner then 10 else 0
			assertions.isTrue(whole.pathProgress > startingProgress)
			assertions.isTrue(partitioned.pathProgress > startingProgress)
			assertClose(assertions, whole.pathProgress, partitioned.pathProgress, 1e-12)
		end

		comparePartitions(false)
		comparePartitions(true)
	end),

	TestHarness.case("does not accumulate tolerance bias across many route corners", function(assertions)
		local segmentCount = 32
		local points: { any } = table.create(segmentCount + 1)
		for index = 0, segmentCount do
			local kind = if index == 0 then "EnemySpawn" elseif index == segmentCount then "DefenderBase" else "PathNode"
			local point: any = {
				kind = kind,
				cframe = CFrame.new(index, 5, 0),
				position = Vector3.new(index, 5, 0),
				distance = index,
			}
			if kind == "PathNode" then
				point.nodeOrder = index
			end
			table.insert(points, table.freeze(point))
		end
		local laneId = "bias-lane"
		local lane = table.freeze({
			id = laneId,
			totalDistance = segmentCount,
			points = table.freeze(points),
		})
		local baseMap = EnemyFixtures.createRuntimeMapSnapshot()
		local runtimeMap = table.freeze({
			mapId = baseMap.mapId,
			base = baseMap.base,
			bounds = baseMap.bounds,
			lanes = table.freeze({ lane }),
			placementZones = baseMap.placementZones,
			noPlacementZones = baseMap.noPlacementZones,
			cameraAnchors = baseMap.cameraAnchors,
			playerSpawns = baseMap.playerSpawns,
		})
		local rawEnemies = EnemyFixtures.rawEnemies()
		rawEnemies[1].moveSpeedStudsPerSecond = 1
		local fixture = EnemyFixtures.authenticateCatalog(EnemyFixtures.rawAssets(), rawEnemies)
		local wholeStore, wholeClock = newStore(assertions, fixture.catalog, nil, runtimeMap)
		local partitionedStore, partitionedClock = newStore(assertions, fixture.catalog, nil, runtimeMap)
		local wholeEnemy = success(assertions, wholeStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, laneId))
		local partitionedEnemy = success(assertions, partitionedStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, laneId))
		local tolerance = segmentCount * 1e-9
		local epsilon = tolerance / 2
		local partitionDelta = 1 - epsilon
		local totalDelta = segmentCount * partitionDelta

		wholeClock.now = 100 + totalDelta
		local wholeStep = success(assertions, wholeStore:step(totalDelta))
		for index = 1, segmentCount do
			partitionedClock.now = 100 + index * partitionDelta
			local partStep = success(assertions, partitionedStore:step(partitionDelta))
			assertions.equal(partStep.endpointCount, 0)
		end
		assertions.equal(wholeStep.endpointCount, 0)
		local whole = success(assertions, wholeStore:get(wholeEnemy.runtimeEnemyId))
		local partitioned = success(assertions, partitionedStore:get(partitionedEnemy.runtimeEnemyId))
		assertions.isTrue(whole.pathProgress < segmentCount)
		assertions.isTrue(partitioned.pathProgress < segmentCount)
		assertClose(assertions, whole.pathProgress, partitioned.pathProgress, 1e-12)
		assertClose(assertions, whole.pathProgress, totalDelta, 1e-12)
	end),

	TestHarness.case("is frame partition equivalent within the declared tolerance", function(assertions)
		local oneStep, oneClock = newStore(assertions)
		local partitioned, partitionClock = newStore(assertions)
		local oneEnemy = success(assertions, oneStep:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		local partitionEnemy =
			success(assertions, partitioned:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		oneClock.now = 103.5
		success(assertions, oneStep:step(3.5))
		for index = 1, 35 do
			partitionClock.now = 100 + index * 0.1
			success(assertions, partitioned:step(0.1))
		end
		local whole = success(assertions, oneStep:get(oneEnemy.runtimeEnemyId))
		local pieces = success(assertions, partitioned:get(partitionEnemy.runtimeEnemyId))
		assertClose(assertions, whole.pathProgress, pieces.pathProgress, 1e-9)
		assertVectorClose(assertions, whole.worldCFrame.Position, pieces.worldCFrame.Position, 1e-6)
		assertions.equal(whole.segmentIndex, pieces.segmentIndex)
	end),

	TestHarness.case("advances multiple authoritative speeds and lanes in one bounded pass", function(assertions)
		local store, clock = newStore(assertions)
		local normal = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		local fast = success(assertions, store:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		local slow = success(assertions, store:spawn(EnemyFixtures.SLOW_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
		clock.now = 101.5
		local step = success(assertions, store:step(1.5))
		assertions.equal(step.visitedCount, 3)
		assertions.equal(step.updatedCount, 3)
		assertions.equal(#step.updatedRuntimeEnemyIds, 3)
		assertions.equal(step.updatedRuntimeEnemyIds[1], normal.runtimeEnemyId)
		assertions.equal(step.updatedRuntimeEnemyIds[2], fast.runtimeEnemyId)
		assertions.equal(step.updatedRuntimeEnemyIds[3], slow.runtimeEnemyId)
		assertions.equal(success(assertions, store:get(normal.runtimeEnemyId)).pathProgress, 15)
		assertions.equal(success(assertions, store:get(fast.runtimeEnemyId)).pathProgress, 30)
		assertions.equal(success(assertions, store:get(slow.runtimeEnemyId)).pathProgress, 7.5)
	end),

	TestHarness.case("applies only the server owned slow multiplier", function(assertions)
		local store, clock = newStore(assertions)
		local half = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		local stopped = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		clock.now = 101
		success(assertions, store:setSlowMultiplier(half.runtimeEnemyId, 0.5))
		success(assertions, store:setSlowMultiplier(stopped.runtimeEnemyId, 0))
		clock.now = 103
		local step = success(assertions, store:step(2))
		assertions.equal(step.visitedCount, 2)
		assertions.equal(step.updatedCount, 1)
		local halfMoved = success(assertions, store:get(half.runtimeEnemyId))
		local stoppedState = success(assertions, store:get(stopped.runtimeEnemyId))
		assertions.equal(halfMoved.pathProgress, 10)
		assertions.equal(halfMoved.effectiveSpeed, 5)
		assertions.equal(stoppedState.pathProgress, 0)
		assertions.equal(stoppedState.effectiveSpeed, 0)
	end),

	TestHarness.case("saturates huge finite speed and delta at the endpoint without overflow", function(assertions)
		local rawEnemies = EnemyFixtures.rawEnemies()
		rawEnemies[1].moveSpeedStudsPerSecond = 1e308
		local fixture = EnemyFixtures.authenticateCatalog(EnemyFixtures.rawAssets(), rawEnemies)
		local store, clock = newStore(assertions, fixture.catalog)
		local spawned = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		clock.now = 101
		local result = success(assertions, store:step(1e308))
		assertions.equal(result.endpointCount, 1)
		assertions.equal(result.endpointResolutions[1].endpoint.runtimeEnemyId, spawned.runtimeEnemyId)
		assertions.equal(result.endpointResolutions[1].endpoint.pathProgress, 40)
		assertions.isTrue(
			result.endpointResolutions[1].endpoint.worldCFrame == result.endpointResolutions[1].endpoint.worldCFrame
		)

		local tinyEnemies = EnemyFixtures.rawEnemies()
		tinyEnemies[1].moveSpeedStudsPerSecond = 1e-300
		local tinyFixture = EnemyFixtures.authenticateCatalog(EnemyFixtures.rawAssets(), tinyEnemies)
		local tinyStore, tinyClock = newStore(assertions, tinyFixture.catalog)
		local tinyEnemy =
			success(assertions, tinyStore:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		tinyClock.now = 101
		local tinyStep = success(assertions, tinyStore:step(1e-100))
		assertions.equal(tinyStep.updatedCount, 0)
		local tinyState = success(assertions, tinyStore:get(tinyEnemy.runtimeEnemyId))
		assertions.equal(tinyState.pathProgress, 0)
		assertions.equal(tinyState.revision, 1)
	end),

	TestHarness.case("terminalizes a rounded distance equal to the remaining route", function(assertions)
		local rawEnemies = EnemyFixtures.rawEnemies()
		rawEnemies[1].moveSpeedStudsPerSecond = 0.1
		local fixture = EnemyFixtures.authenticateCatalog(EnemyFixtures.rawAssets(), rawEnemies)
		local store, clock = newStore(assertions, fixture.catalog)
		local spawned = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))

		clock.now = 200
		success(assertions, store:step(100))
		assertions.equal(success(assertions, store:get(spawned.runtimeEnemyId)).pathProgress, 10)
		clock.now = 300
		local terminal = success(assertions, store:step(99.99999999999999))
		assertions.isFalse(terminal.faulted)
		assertions.equal(terminal.endpointCount, 1)
		assertions.equal(terminal.endpointResolutions[1].endpoint.pathProgress, 20)
		expectError(assertions, store:get(spawned.runtimeEnemyId), "STALE_RUNTIME_ID")
	end),

	TestHarness.case("rejects invalid deltas and treats zero as a clock neutral no op", function(assertions)
		local store, clock = newStore(assertions)
		local spawned = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		local callsBeforeZero = clock.calls
		local revisionBeforeZero = success(assertions, store:get(spawned.runtimeEnemyId)).revision
		local zero = success(assertions, store:step(0))
		assertions.equal(zero.updatedCount, 0)
		assertions.isNil(zero.sampleServerTime)
		assertions.equal(clock.calls, callsBeforeZero)
		assertions.equal(success(assertions, store:get(spawned.runtimeEnemyId)).revision, revisionBeforeZero)
		for _, invalid in { -1, 0 / 0, math.huge, "1", {} } do
			expectError(assertions, store:step(invalid), "INVALID_DELTA")
		end
		assertions.equal(success(assertions, store:get(spawned.runtimeEnemyId)).pathProgress, 0)
	end),

	TestHarness.case("has deterministic travel time and no updates after exact endpoint despawn", function(assertions)
		local endpointCount = 0
		local store, clock = newStore(assertions, nil, function()
			endpointCount += 1
		end)
		local spawned = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		for second = 1, 3 do
			clock.now = 100 + second
			local step = success(assertions, store:step(1))
			assertions.equal(step.endpointCount, 0)
		end
		assertions.equal(success(assertions, store:get(spawned.runtimeEnemyId)).pathProgress, 30)
		clock.now = 104
		local terminal = success(assertions, store:step(1))
		assertions.equal(terminal.endpointCount, 1)
		assertions.equal(endpointCount, 1)
		expectError(assertions, store:get(spawned.runtimeEnemyId), "STALE_RUNTIME_ID")
		clock.now = 105
		local after = success(assertions, store:step(1))
		assertions.equal(after.visitedCount, 0)
		assertions.equal(after.updatedCount, 0)
		assertions.equal(after.endpointCount, 0)
		assertions.equal(endpointCount, 1)
	end),

	TestHarness.case("orders simultaneous endpoint outcomes by runtime identity exactly once", function(assertions)
		local observed: { number } = {}
		local store, clock = newStore(assertions, nil, function(snapshot)
			table.insert(observed, snapshot.runtimeEnemyId)
		end)
		for _ = 1, 8 do
			success(assertions, store:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
		end
		clock.now = 101
		local step = success(assertions, store:step(1))
		assertions.equal(step.endpointCount, 8)
		assertions.equal(step.activeCountAfter, 0)
		for index = 1, 8 do
			assertions.equal(observed[index], index)
			assertions.equal(step.endpointResolutions[index].endpoint.runtimeEnemyId, index)
		end
	end),

	TestHarness.case("defers cleanup during an update and skips the remaining start frame IDs", function(assertions)
		local endpointCount = 0
		local store: any = nil
		local cleanupResult: any = nil
		local clock: any = nil
		store, clock = newStore(assertions, nil, function()
			endpointCount += 1
			cleanupResult = store:cleanup()
		end)
		success(assertions, store:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
		success(assertions, store:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
		clock.now = 101
		local step = success(assertions, store:step(1))
		assertions.equal(step.visitedCount, 1)
		assertions.equal(step.endpointCount, 1)
		assertions.equal(endpointCount, 1)
		assertions.isTrue(step.cleaned)
		assertions.equal(step.activeCountAfter, 0)
		assertions.isTrue(cleanupResult.ok)
		assertions.isFalse(cleanupResult.value)
		expectError(assertions, store:step(1), "CLEANED")
	end),

	TestHarness.case("contains nested update reentry after terminalizing the current enemy", function(assertions)
		local store: any = nil
		local nestedResult: any = nil
		local clock: any = nil
		store, clock = newStore(assertions, nil, function()
			nestedResult = store:step(1)
		end)
		local first = success(assertions, store:spawn(EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID))
		local second = success(assertions, store:spawn(EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID))
		clock.now = 101
		local step = success(assertions, store:step(1))
		assertions.equal(step.endpointCount, 1)
		assertions.equal(step.endpointResolutions[1].endpoint.runtimeEnemyId, first.runtimeEnemyId)
		assertions.isFalse(step.endpointResolutions[1].callbackSucceeded)
		assertions.isTrue(step.faulted)
		expectError(assertions, nestedResult, "REENTRANT")
		local untouched = success(assertions, store:get(second.runtimeEnemyId))
		assertions.equal(untouched.pathProgress, 0)
		expectError(assertions, store:step(1), "FAULTED")
	end),
})
