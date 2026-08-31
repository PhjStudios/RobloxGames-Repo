--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local TargetQuery = require(script.Parent.Parent.ProductionServerPlayable.TargetQuery)

type Assertions = TestHarness.Assertions

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		error("expected target query to succeed", 0)
	end
	return result.value
end

local function expectError(assertions: Assertions, result: any, code: string, candidateIndex: number?)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		assertions.isTrue(table.isfrozen(result.error))
		assertions.equal(result.error.code, code)
		assertions.equal(result.error.operation, "select")
		assertions.equal(result.error.candidateIndex, candidateIndex)
	end
end

local function enemy(
	runtimeEnemyId: number,
	pathProgress: number,
	currentHealth: number,
	position: Vector3,
	lifecycle: string?
): any
	return {
		runtimeEnemyId = runtimeEnemyId,
		pathProgress = pathProgress,
		currentHealth = currentHealth,
		lifecycle = lifecycle or "Active",
		worldCFrame = CFrame.new(position),
	}
end

local function selectedId(assertions: Assertions, mode: string, candidates: { any }, range: number?): number?
	local selection = success(assertions, TargetQuery.select(CFrame.new(), range or 20, mode, candidates))
	return if selection == nil then nil else selection.runtimeEnemyId
end

return TestHarness.suite("TargetQuery", {
	TestHarness.case("selects all five standard modes from authoritative current state", function(assertions)
		local candidates = {
			enemy(1, 80, 30, Vector3.new(6, 0, 0)),
			enemy(2, 20, 100, Vector3.new(4, 0, 0)),
			enemy(3, 50, 10, Vector3.new(2, 0, 0)),
		}
		assertions.equal(selectedId(assertions, "First", candidates), 1)
		assertions.equal(selectedId(assertions, "Last", candidates), 2)
		assertions.equal(selectedId(assertions, "Strongest", candidates), 2)
		assertions.equal(selectedId(assertions, "Weakest", candidates), 3)
		assertions.equal(selectedId(assertions, "Closest", candidates), 3)
	end),

	TestHarness.case("filters inactive dead and out-of-range enemies at an inclusive range edge", function(assertions)
		local candidates = {
			enemy(1, 100, 100, Vector3.new(1, 0, 0), "Despawned"),
			enemy(2, 90, 0, Vector3.new(1, 0, 0)),
			enemy(3, 80, 100, Vector3.new(5.001, 0, 0)),
			enemy(4, 70, 100, Vector3.new(3, 4, 0)),
		}
		local selection = success(assertions, TargetQuery.select(CFrame.new(), 5, "First", candidates))
		assertions.isNotNil(selection)
		assertions.equal(selection.runtimeEnemyId, 4)
		assertions.equal(selection.distanceSquared, 25)
		assertions.isTrue(table.isfrozen(selection))
		assertions.isNil(success(assertions, TargetQuery.select(CFrame.new(), 4.999, "First", candidates)))
	end),

	TestHarness.case("uses current health for strongest and weakest", function(assertions)
		local formerlyStrong = enemy(1, 20, 5, Vector3.new(1, 0, 0))
		formerlyStrong.maximumHealth = 10_000
		local currentlyStrong = enemy(2, 10, 50, Vector3.new(2, 0, 0))
		currentlyStrong.maximumHealth = 50
		local candidates = { formerlyStrong, currentlyStrong }
		assertions.equal(selectedId(assertions, "Strongest", candidates), 2)
		assertions.equal(selectedId(assertions, "Weakest", candidates), 1)
	end),

	TestHarness.case("applies documented secondary ties before runtime ID", function(assertions)
		local progressTie = {
			enemy(4, 50, 20, Vector3.new(2, 0, 0)),
			enemy(3, 50, 30, Vector3.new(3, 0, 0)),
		}
		assertions.equal(selectedId(assertions, "First", progressTie), 3)
		assertions.equal(selectedId(assertions, "Last", progressTie), 3)

		local healthTie = {
			enemy(4, 20, 30, Vector3.new(1, 0, 0)),
			enemy(3, 50, 30, Vector3.new(3, 0, 0)),
		}
		assertions.equal(selectedId(assertions, "Strongest", healthTie), 3)
		assertions.equal(selectedId(assertions, "Weakest", healthTie), 3)

		local distanceTie = {
			enemy(4, 20, 20, Vector3.new(-4, 0, 0)),
			enemy(3, 50, 10, Vector3.new(4, 0, 0)),
		}
		assertions.equal(selectedId(assertions, "Closest", distanceTie), 3)
	end),

	TestHarness.case("ends every exact tie with ascending runtime ID independent of input order", function(assertions)
		local low = enemy(3, 50, 30, Vector3.new(4, 0, 0))
		local high = enemy(9, 50, 30, Vector3.new(-4, 0, 0))
		for _, mode in { "First", "Last", "Strongest", "Weakest", "Closest" } do
			assertions.equal(selectedId(assertions, mode, { high, low }), 3)
			assertions.equal(selectedId(assertions, mode, { low, high }), 3)
		end
	end),

	TestHarness.case("does not sort or mutate caller-owned arrays and records", function(assertions)
		local first = enemy(7, 10, 20, Vector3.new(2, 0, 0))
		local second = enemy(2, 20, 10, Vector3.new(1, 0, 0))
		local candidates = { first, second }
		local selection = success(assertions, TargetQuery.select(CFrame.new(), 10, "First", candidates))
		assertions.equal(selection.runtimeEnemyId, 2)
		assertions.equal(candidates[1], first)
		assertions.equal(candidates[2], second)
		assertions.equal(first.runtimeEnemyId, 7)
		assertions.equal(second.runtimeEnemyId, 2)
		assertions.isFalse(table.isfrozen(candidates))
		assertions.isFalse(table.isfrozen(first))
		assertions.notEqual(selection, second)
	end),

	TestHarness.case("rejects malformed query inputs and duplicate runtime identities", function(assertions)
		expectError(assertions, TargetQuery.select("CFrame", 5, "First", {}), "INVALID_TOWER_CFRAME", nil)
		for _, range in { -1, 0 / 0, math.huge, TargetQuery.MAX_COORDINATE + 1 } do
			expectError(assertions, TargetQuery.select(CFrame.new(), range, "First", {}), "INVALID_RANGE", nil)
		end
		expectError(assertions, TargetQuery.select(CFrame.new(), 5, "Highest", {}), "INVALID_TARGET_MODE", nil)
		expectError(assertions, TargetQuery.select(CFrame.new(), 5, "First", "enemies"), "INVALID_ENEMY_ARRAY", nil)
		local sparse = { enemy(1, 1, 1, Vector3.zero) }
		sparse[3] = enemy(3, 1, 1, Vector3.zero)
		expectError(assertions, TargetQuery.select(CFrame.new(), 5, "First", sparse), "INVALID_ENEMY_ARRAY", nil)
		expectError(assertions, TargetQuery.select(CFrame.new(), 5, "First", { {} }), "INVALID_ENEMY", 1)
		local duplicate = enemy(1, 1, 1, Vector3.zero)
		expectError(
			assertions,
			TargetQuery.select(CFrame.new(), 5, "First", { duplicate, enemy(1, 2, 2, Vector3.one) }),
			"DUPLICATE_RUNTIME_ID",
			2
		)
		local oversized = table.create(TargetQuery.MAX_CANDIDATES + 1, duplicate)
		expectError(assertions, TargetQuery.select(CFrame.new(), 5, "First", oversized), "CAPACITY_EXCEEDED", nil)
	end),
})
