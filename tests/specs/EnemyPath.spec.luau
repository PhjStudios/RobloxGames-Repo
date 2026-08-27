--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local EnemyPath = require(script.Parent.Parent.ProductionServerEnemies.EnemyPath)

type Assertions = TestHarness.Assertions
type RoutePointKind = EnemyPath.RoutePointKind
type RuntimeLaneSnapshot = EnemyPath.RuntimeLaneSnapshot

local EPSILON = 1e-6

local function routePoint(
	kind: RoutePointKind,
	nodeOrder: number?,
	position: Vector3,
	distance: number,
	rotationSeed: number
): EnemyPath.RoutePointSnapshot
	local record = {
		kind = kind,
		cframe = CFrame.new(position) * CFrame.Angles(rotationSeed, rotationSeed * 0.5, -rotationSeed),
		position = position,
		distance = distance,
	} :: any
	if nodeOrder ~= nil then
		record.nodeOrder = nodeOrder
	end
	return table.freeze(record) :: EnemyPath.RoutePointSnapshot
end

local function bentLane(): RuntimeLaneSnapshot
	return table.freeze({
		id = "lane.bent",
		totalDistance = 30,
		points = table.freeze({
			routePoint("EnemySpawn", nil, Vector3.new(0, 2, 0), 0, 0.7),
			routePoint("PathNode", 1, Vector3.new(10, 2, 0), 10, 1.1),
			routePoint("PathNode", 2, Vector3.new(10, 2, 10), 20, 1.7),
			routePoint("DefenderBase", nil, Vector3.new(10, 12, 10), 30, 2.3),
		}),
	})
end

local function straightLane(): RuntimeLaneSnapshot
	local delta = Vector3.new(6, 0, 8)
	return table.freeze({
		id = "lane.diagonal",
		totalDistance = delta.Magnitude,
		points = table.freeze({
			routePoint("EnemySpawn", nil, Vector3.new(-3, 4, -4), 0, 0.3),
			routePoint("DefenderBase", nil, Vector3.new(3, 4, 4), delta.Magnitude, 2.8),
		}),
	})
end

local function assertNear(assertions: Assertions, actual: number, expected: number)
	assertions.isTrue(math.abs(actual - expected) <= EPSILON)
end

local function assertVector(assertions: Assertions, actual: Vector3, expected: Vector3)
	assertNear(assertions, actual.X, expected.X)
	assertNear(assertions, actual.Y, expected.Y)
	assertNear(assertions, actual.Z, expected.Z)
end

local function expectSample(
	assertions: Assertions,
	lane: RuntimeLaneSnapshot,
	progress: number,
	expectedPosition: Vector3,
	expectedTangent: Vector3,
	expectedSegment: number,
	expectedStartDistance: number,
	expectedEndDistance: number
): EnemyPath.Sample
	local result = EnemyPath.sample(lane, progress)
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		error("[ATD_ENEMY_PATH_SPEC][code=EXPECTED_SAMPLE]", 0)
	end

	local sample = result.value
	assertions.isTrue(table.isfrozen(sample))
	assertions.equal(sample.segmentIndex, expectedSegment)
	assertions.equal(sample.segmentStartDistance, expectedStartDistance)
	assertions.equal(sample.segmentEndDistance, expectedEndDistance)
	assertVector(assertions, sample.worldCFrame.Position, expectedPosition)
	assertVector(assertions, sample.worldCFrame.LookVector, expectedTangent.Unit)

	local fields = 0
	for fieldName in next, sample :: any do
		fields += 1
		assertions.isTrue(
			fieldName == "worldCFrame"
				or fieldName == "segmentIndex"
				or fieldName == "segmentStartDistance"
				or fieldName == "segmentEndDistance"
				or fieldName == "segmentStartPosition"
				or fieldName == "segmentEndPosition"
		)
	end
	assertions.equal(fields, 6)
	assertions.equal(sample.segmentStartPosition, lane.points[expectedSegment].position)
	assertions.equal(sample.segmentEndPosition, lane.points[expectedSegment + 1].position)
	return sample
end

local function expectError(assertions: Assertions, lane: unknown, progress: unknown, expectedCode: EnemyPath.ErrorCode)
	local result = EnemyPath.sample(lane, progress)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if result.ok then
		error("[ATD_ENEMY_PATH_SPEC][code=EXPECTED_ERROR]", 0)
	end
	assertions.isTrue(table.isfrozen(result.error))
	assertions.equal(result.error.code, expectedCode)
	local fields = 0
	for fieldName in next, result.error :: any do
		fields += 1
		assertions.equal(fieldName, "code")
	end
	assertions.equal(fields, 1)
end

return TestHarness.suite("enemy path", {
	TestHarness.case("samples spawn segments corners and endpoint with canonical tangents", function(assertions)
		local lane = bentLane()
		expectSample(assertions, lane, 0, Vector3.new(0, 2, 0), Vector3.xAxis, 1, 0, 10)
		expectSample(assertions, lane, 4, Vector3.new(4, 2, 0), Vector3.xAxis, 1, 0, 10)
		expectSample(assertions, lane, 10, Vector3.new(10, 2, 0), Vector3.zAxis, 2, 10, 20)
		expectSample(assertions, lane, 16, Vector3.new(10, 2, 6), Vector3.zAxis, 2, 10, 20)
		local verticalCorner = expectSample(assertions, lane, 20, Vector3.new(10, 2, 10), Vector3.yAxis, 3, 20, 30)
		expectSample(assertions, lane, 25, Vector3.new(10, 7, 10), Vector3.yAxis, 3, 20, 30)
		local endpoint = expectSample(assertions, lane, 30, Vector3.new(10, 12, 10), Vector3.yAxis, 3, 20, 30)

		assertVector(assertions, verticalCorner.worldCFrame.UpVector, Vector3.xAxis)
		assertVector(assertions, endpoint.worldCFrame.UpVector, Vector3.xAxis)
		assertions.isFalse(lane.points[2].cframe.LookVector == Vector3.zAxis)
	end),

	TestHarness.case("canonicalizes scale-aware near-corner and near-endpoint progress", function(assertions)
		local lane = bentLane()
		local justBeforeCorner = 10 - 1e-9
		local justAfterCorner = 10 + 1e-9
		local justBeforeEndpoint = lane.totalDistance - 1e-9

		assertions.equal(EnemyPath.canonicalizeProgressTrusted(lane, justBeforeCorner), 10)
		assertions.equal(EnemyPath.canonicalizeProgressTrusted(lane, justAfterCorner), justAfterCorner)
		assertions.equal(EnemyPath.canonicalizeProgressTrusted(lane, justBeforeEndpoint), lane.totalDistance)
		expectSample(assertions, lane, justBeforeCorner, Vector3.new(10, 2, 0), Vector3.zAxis, 2, 10, 20)
		expectSample(assertions, lane, justAfterCorner, Vector3.new(10, 2, 0), Vector3.zAxis, 2, 10, 20)
		expectSample(assertions, lane, justBeforeEndpoint, Vector3.new(10, 12, 10), Vector3.yAxis, 3, 20, 30)
	end),

	TestHarness.case("samples multiple lanes and keeps trusted sampling metadata-free", function(assertions)
		local diagonal = straightLane()
		local expectedDirection = Vector3.new(6, 0, 8).Unit
		local safe = expectSample(
			assertions,
			diagonal,
			diagonal.totalDistance / 2,
			Vector3.new(0, 4, 0),
			expectedDirection,
			1,
			0,
			diagonal.totalDistance
		)
		local trustedCFrame, trustedSegment = EnemyPath.sampleTrusted(diagonal, diagonal.totalDistance / 2)
		assertions.equal(trustedSegment, safe.segmentIndex)
		assertVector(assertions, trustedCFrame.Position, safe.worldCFrame.Position)
		assertVector(assertions, trustedCFrame.LookVector, safe.worldCFrame.LookVector)
		assertVector(assertions, trustedCFrame.UpVector, Vector3.yAxis)

		local bent = bentLane()
		local bentCFrame, bentSegment = EnemyPath.sampleTrusted(bent, 10)
		assertions.equal(bentSegment, 2)
		assertVector(assertions, bentCFrame.Position, Vector3.new(10, 2, 0))
		assertVector(assertions, bentCFrame.LookVector, Vector3.zAxis)
	end),

	TestHarness.case("uses bounded binary lookup at the maximum route size", function(assertions)
		local points: { EnemyPath.RoutePointSnapshot } = table.create(EnemyPath.MAX_ROUTE_POINTS)
		for index = 1, EnemyPath.MAX_ROUTE_POINTS do
			local kind: RoutePointKind = if index == 1
				then "EnemySpawn"
				elseif index == EnemyPath.MAX_ROUTE_POINTS then "DefenderBase"
				else "PathNode"
			table.insert(
				points,
				routePoint(
					kind,
					if kind == "PathNode" then index - 1 else nil,
					Vector3.new(index - 1, 0, 0),
					index - 1,
					0.4
				)
			)
		end
		local lane: RuntimeLaneSnapshot = table.freeze({
			id = "lane.maximum",
			totalDistance = EnemyPath.MAX_ROUTE_POINTS - 1,
			points = table.freeze(points),
		})

		expectSample(assertions, lane, 127, Vector3.new(127, 0, 0), Vector3.xAxis, 128, 127, 128)
		expectSample(
			assertions,
			lane,
			EnemyPath.MAX_ROUTE_POINTS - 1,
			Vector3.new(EnemyPath.MAX_ROUTE_POINTS - 1, 0, 0),
			Vector3.xAxis,
			EnemyPath.MAX_ROUTE_POINTS - 1,
			EnemyPath.MAX_ROUTE_POINTS - 2,
			EnemyPath.MAX_ROUTE_POINTS - 1
		)
	end),

	TestHarness.case("rejects malformed lanes and invalid progress with static errors", function(assertions)
		local lane = bentLane()
		expectError(assertions, nil, 0, "INVALID_LANE")
		expectError(assertions, {}, 0, "INVALID_LANE")
		expectError(
			assertions,
			table.freeze({ id = "lane.empty", totalDistance = 1, points = table.freeze({}) }),
			0,
			"INVALID_LANE"
		)
		expectError(
			assertions,
			table.freeze({ id = "lane.nan", totalDistance = 0 / 0, points = lane.points }),
			0,
			"INVALID_LANE"
		)
		expectError(assertions, lane, "0", "INVALID_PROGRESS")
		expectError(assertions, lane, 0 / 0, "INVALID_PROGRESS")
		expectError(assertions, lane, math.huge, "INVALID_PROGRESS")
		expectError(assertions, lane, -math.huge, "INVALID_PROGRESS")
		expectError(assertions, lane, -EPSILON, "OUT_OF_RANGE")
		expectError(assertions, lane, lane.totalDistance + EPSILON, "OUT_OF_RANGE")
	end),
})
