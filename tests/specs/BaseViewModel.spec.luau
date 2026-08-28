--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local BaseViewModel = require(script.Parent.Parent.ProductionClientBase.BaseViewModel)
local BaseProtocol = require(game:GetService("ReplicatedStorage").Shared.match.BaseProtocol)

type Assertions = TestHarness.Assertions

local function snapshot(currentHealth: number, status: "Active" | "Defeated" | "Faulted"?): BaseProtocol.BaseSnapshot
	local result = BaseProtocol.validateBaseSnapshot({
		matchId = "match:phase10-view-model",
		enemyEpoch = 1,
		mapId = "map:phase10-view-model",
		difficultyId = "difficulty:phase10-view-model",
		basePosition = Vector3.new(20, 5, 20),
		baseRevision = 2,
		status = status or "Active",
		currentHealth = currentHealth,
		maximumHealth = 100,
		lowHealth = currentHealth <= 25,
		initializedServerTime = 10,
		updatedServerTime = 11,
	})
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=BASE_VIEW_SNAPSHOT_INVALID]", 0)
	end
	return result.value
end

local function success(result: any): BaseViewModel.RenderState
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=BASE_VIEW_MODEL_FAILURE]", 0)
	end
	return result.value
end

local function expectFailure(assertions: Assertions, result: any)
	assertions.isFalse(result.ok)
	if not result.ok then
		assertions.equal(result.error.code, "INVALID_STATE")
	end
end

return TestHarness.suite("base view model", {
	TestHarness.case("projects absence to one frozen hidden state", function(assertions)
		local state = success(BaseViewModel.project(nil, nil))
		assertions.isTrue(table.isfrozen(state))
		assertions.isFalse(state.visible)
		assertions.isNil(state.basePosition)
		assertions.isNil(state.baseRevision)
		assertions.equal(state.fillScale, 0)
		assertions.equal(state.healthText, "")
		assertions.isFalse(state.lowVisible)
		assertions.isFalse(state.damageVisible)
		expectFailure(
			assertions,
			BaseViewModel.project(nil, {
				baseRevision = 1,
				appliedDamage = 1,
				leakCount = 1,
				lowHealthCrossed = false,
			})
		)
	end),

	TestHarness.case("projects authoritative fill numeric health and active status", function(assertions)
		local state = success(BaseViewModel.project(snapshot(75, "Active"), nil))
		assertions.isTrue(state.visible)
		assertions.equal(state.basePosition, Vector3.new(20, 5, 20))
		assertions.equal(state.baseRevision, 2)
		assertions.equal(state.fillScale, 0.75)
		assertions.equal(state.healthText, "75 / 100")
		assertions.equal(state.statusText, "ACTIVE")
		assertions.isFalse(state.lowVisible)
		assertions.equal(state.lowText, "")
		assertions.isFalse(state.damageVisible)
	end),

	TestHarness.case("keeps low health visible as text at the exact one-quarter boundary", function(assertions)
		local state = success(BaseViewModel.project(snapshot(25, "Active"), nil))
		assertions.equal(state.fillScale, 0.25)
		assertions.isTrue(state.lowVisible)
		assertions.equal(state.lowText, "LOW")
		assertions.equal(state.healthText, "25 / 100")
	end),

	TestHarness.case("projects bounded textual damage and terminal status", function(assertions)
		local terminal = snapshot(0, "Defeated")
		local state = success(BaseViewModel.project(terminal, {
			baseRevision = 2,
			appliedDamage = 20,
			leakCount = 2,
			lowHealthCrossed = true,
		}))
		assertions.equal(state.fillScale, 0)
		assertions.equal(state.healthText, "0 / 100")
		assertions.equal(state.statusText, "DEFEATED")
		assertions.isTrue(state.lowVisible)
		assertions.isTrue(state.damageVisible)
		assertions.equal(state.damageText, "-20")
	end),

	TestHarness.case("rejects malformed snapshots and conflicting feedback", function(assertions)
		expectFailure(assertions, BaseViewModel.project({ currentHealth = 1 }, nil))
		local current = snapshot(75, "Active")
		expectFailure(
			assertions,
			BaseViewModel.project(current, {
				baseRevision = 1,
				appliedDamage = 25,
				leakCount = 1,
				lowHealthCrossed = false,
			})
		)
		expectFailure(
			assertions,
			BaseViewModel.project(current, {
				baseRevision = 2,
				appliedDamage = 0,
				leakCount = 1,
				lowHealthCrossed = false,
			})
		)
	end),
})
