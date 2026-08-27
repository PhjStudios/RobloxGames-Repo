--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local EnemyPresentation = require(script.Parent.Parent.ProductionClientEnemies.EnemyPresentation)

local Shared = game:GetService("ReplicatedStorage").Shared
local EnemyProtocol = require(Shared.match.EnemyProtocol)

type Assertions = TestHarness.Assertions

local function canonicalCFrame(position: Vector3, tangent: Vector3): CFrame
	local direction = tangent.Unit
	local upHint = Vector3.yAxis
	if math.abs(direction:Dot(upHint)) >= 1 - 1e-6 then
		upHint = Vector3.xAxis
	end
	local right = direction:Cross(upHint).Unit
	local up = right:Cross(direction).Unit
	return CFrame.fromMatrix(position, right, up, -direction)
end

local function entry(
	revision: number,
	progress: number,
	time: number,
	segmentIndex: number,
	startDistance: number,
	endDistance: number,
	startPosition: Vector3,
	endPosition: Vector3,
	speed: number?
): EnemyProtocol.EnemyStateEntry
	local alpha = (progress - startDistance) / (endDistance - startDistance)
	local result = EnemyProtocol.validateEnemyStateEntry({
		runtimeEnemyId = 1,
		enemyId = "enemy:phase09-test",
		laneId = "lane:bent",
		revision = revision,
		lifecycle = "Active",
		pathProgress = progress,
		currentHealth = 100,
		maximumHealth = 100,
		slowMultiplier = 1,
		spawnServerTime = 10,
		sampleServerTime = time,
		worldCFrame = canonicalCFrame(startPosition:Lerp(endPosition, alpha), endPosition - startPosition),
		effectiveSpeed = speed or 10,
		segmentIndex = segmentIndex,
		segmentStartDistance = startDistance,
		segmentEndDistance = endDistance,
		segmentStartPosition = startPosition,
		segmentEndPosition = endPosition,
	})
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=ENEMY_PRESENTATION_ENTRY_INVALID][path={result.error.path}]`, 0)
	end
	return result.value
end

local function sample(previous: EnemyProtocol.EnemyStateEntry?, current: EnemyProtocol.EnemyStateEntry, now: number)
	local result = EnemyPresentation.sample(previous, current, now)
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=ENEMY_PRESENTATION_SAMPLE_FAILED][detail={result.error.code}]`, 0)
	end
	return result.value
end

local function expectPosition(assertions: Assertions, actual: Vector3, expected: Vector3)
	assertions.isTrue((actual - expected).Magnitude <= 1e-6)
end

return TestHarness.suite("enemy client presentation sampling", {
	TestHarness.case("interpolates scalar progress without cutting a straight segment", function(assertions)
		local previous = entry(1, 2, 10, 1, 0, 10, Vector3.zero, Vector3.new(10, 0, 0))
		local current = entry(2, 8, 11, 1, 0, 10, Vector3.zero, Vector3.new(10, 0, 0))
		local rendered = sample(previous, current, 10.65)
		assertions.isTrue(math.abs(rendered.pathProgress - 5) <= 1e-6)
		expectPosition(assertions, rendered.worldCFrame.Position, Vector3.new(5, 0, 0))
		assertions.isFalse(rendered.snapped)
		assertions.isFalse(rendered.extrapolated)
	end),

	TestHarness.case("uses the outgoing tangent at an exact bent-route corner", function(assertions)
		local previous = entry(1, 8, 10, 1, 0, 10, Vector3.zero, Vector3.new(10, 0, 0))
		local current = entry(2, 12, 11, 2, 10, 20, Vector3.new(10, 0, 0), Vector3.new(10, 0, 10))
		local rendered = sample(previous, current, 10.65)
		assertions.isTrue(math.abs(rendered.pathProgress - 10) <= 1e-6)
		expectPosition(assertions, rendered.worldCFrame.Position, Vector3.new(10, 0, 0))
		expectPosition(assertions, rendered.worldCFrame.LookVector, Vector3.zAxis)
		assertions.isFalse(rendered.segmentGap)
	end),

	TestHarness.case("snaps when two samples leave an unknown multi-segment gap", function(assertions)
		local previous = entry(1, 8, 10, 1, 0, 10, Vector3.zero, Vector3.new(10, 0, 0))
		local current = entry(2, 24, 11, 3, 20, 30, Vector3.new(10, 0, 10), Vector3.new(20, 0, 10))
		local rendered = sample(previous, current, 10.65)
		assertions.isTrue(rendered.snapped)
		assertions.isTrue(rendered.segmentGap)
		expectPosition(assertions, rendered.worldCFrame.Position, current.worldCFrame.Position)
		local afterNewest = sample(previous, current, 12)
		assertions.isTrue(afterNewest.snapped)
		assertions.isTrue(afterNewest.segmentGap)
	end),

	TestHarness.case("never extrapolates before oldest and bounds extrapolation at segment end", function(assertions)
		local current = entry(1, 9, 10, 1, 0, 10, Vector3.zero, Vector3.new(10, 0, 0), 20)
		local before = sample(nil, current, 10)
		expectPosition(assertions, before.worldCFrame.Position, Vector3.new(9, 0, 0))
		assertions.isFalse(before.extrapolated)

		local after = sample(nil, current, 11)
		expectPosition(assertions, after.worldCFrame.Position, Vector3.new(10, 0, 0))
		assertions.isTrue(math.abs(after.pathProgress - 10) <= 1e-6)
		assertions.isTrue(after.extrapolated)
	end),

	TestHarness.case("uses exact correction and snap thresholds", function(assertions)
		local accepted = EnemyPresentation.classifyCorrection(Vector3.new(0.249, 0, 0), Vector3.zero)
		local smoothLow = EnemyPresentation.classifyCorrection(Vector3.new(0.25, 0, 0), Vector3.zero)
		local smoothHigh = EnemyPresentation.classifyCorrection(Vector3.new(7.999, 0, 0), Vector3.zero)
		local snapped = EnemyPresentation.classifyCorrection(Vector3.new(8, 0, 0), Vector3.zero)
		assertions.isTrue(accepted.ok)
		assertions.isTrue(smoothLow.ok)
		assertions.isTrue(smoothHigh.ok)
		assertions.isTrue(snapped.ok)
		if accepted.ok and smoothLow.ok and smoothHigh.ok and snapped.ok then
			assertions.equal(accepted.value.mode, "Accept")
			assertions.equal(smoothLow.value.mode, "Smooth")
			assertions.equal(smoothHigh.value.mode, "Smooth")
			assertions.equal(snapped.value.mode, "Snap")
			expectPosition(assertions, smoothLow.value.offset, Vector3.new(0.25, 0, 0))
		end
	end),

	TestHarness.case("fails closed on invalid time and mismatched identity", function(assertions)
		local current = entry(1, 4, 10, 1, 0, 10, Vector3.zero, Vector3.new(10, 0, 0))
		assertions.isFalse(EnemyPresentation.sample(nil, current, 0 / 0).ok)
		local different = table.clone(current) :: any
		different.runtimeEnemyId = 2
		table.freeze(different)
		local rendered = sample(current, different, 11)
		assertions.isTrue(rendered.snapped)
		assertions.isTrue(rendered.segmentGap)

		local nonIncreasingTime = table.clone(current) :: any
		nonIncreasingTime.revision = 2
		nonIncreasingTime.pathProgress = 6
		nonIncreasingTime.worldCFrame = canonicalCFrame(Vector3.new(6, 0, 0), Vector3.xAxis)
		table.freeze(nonIncreasingTime)
		local malformedRelation = sample(current, nonIncreasingTime, 11)
		assertions.isTrue(malformedRelation.snapped)
		assertions.isTrue(malformedRelation.segmentGap)
	end),
})
