--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local BaseStateReducer = require(script.Parent.Parent.ProductionClientBase.BaseStateReducer)

local Shared = game:GetService("ReplicatedStorage").Shared
local BaseProtocol = require(Shared.match.BaseProtocol)

type Assertions = TestHarness.Assertions
type Reducer = BaseStateReducer.Reducer

local MATCH_A = "match:base-client-a"
local MATCH_B = "match:base-client-b"
local MAP_A = "map:base-client-a"
local MAP_B = "map:base-client-b"
local DIFFICULTY_A = "difficulty:base-client-a"
local DIFFICULTY_B = "difficulty:base-client-b"

local function rawSnapshot(
	revision: number,
	currentHealth: number,
	status: "Active" | "Defeated" | "Faulted"?,
	overrides: { [string]: unknown }?
): { [string]: unknown }
	local selectedStatus = status or "Active"
	local value: { [string]: unknown } = {
		matchId = MATCH_A,
		enemyEpoch = 1,
		mapId = MAP_A,
		difficultyId = DIFFICULTY_A,
		basePosition = Vector3.new(12, 3, -4),
		baseRevision = revision,
		status = selectedStatus,
		currentHealth = currentHealth,
		maximumHealth = 100,
		lowHealth = currentHealth <= 25,
		initializedServerTime = 100,
		updatedServerTime = 100 + revision,
	}
	if overrides ~= nil then
		for key, override in overrides do
			value[key] = override
		end
	end
	return value
end

local function canonicalSnapshot(
	revision: number,
	currentHealth: number,
	status: "Active" | "Defeated" | "Faulted"?,
	overrides: { [string]: unknown }?
): BaseProtocol.BaseSnapshot
	local result = BaseProtocol.validateBaseSnapshot(rawSnapshot(revision, currentHealth, status, overrides))
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=BASE_SNAPSHOT_INVALID][path={result.error.path}]`, 0)
	end
	return result.value
end

local function stateMessage(snapshot: BaseProtocol.BaseSnapshot): BaseProtocol.BaseReplicationMessage
	local result = BaseProtocol.validateBaseReplicationMessage({
		kind = "State",
		snapshot = snapshot,
	})
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=BASE_STATE_MESSAGE_INVALID][path={result.error.path}]`, 0)
	end
	return result.value
end

local function damageMessage(
	snapshot: BaseProtocol.BaseSnapshot,
	appliedDamage: number?,
	leakCount: number?,
	lowHealthCrossed: boolean?
): BaseProtocol.BaseReplicationMessage
	local result = BaseProtocol.validateBaseReplicationMessage({
		kind = "Damage",
		snapshot = snapshot,
		appliedDamage = appliedDamage or 10,
		leakCount = leakCount or 1,
		lowHealthCrossed = lowHealthCrossed == true,
	})
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=BASE_DAMAGE_MESSAGE_INVALID][path={result.error.path}]`, 0)
	end
	return result.value
end

local function success<T>(result: any): T
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=BASE_REDUCER_FAILURE][detail={result.error.code}]`, 0)
	end
	return result.value :: T
end

local function expectFailure(assertions: Assertions, result: any, code: string)
	assertions.isFalse(result.ok)
	if not result.ok then
		assertions.equal(result.error.code, code)
	end
end

local function newReducer(): Reducer
	return success(BaseStateReducer.new())
end

local function current(reducer: Reducer): BaseProtocol.BaseSnapshot?
	return success(reducer:getState()).snapshot
end

return TestHarness.suite("BaseStateReducer", {
	TestHarness.case("pins the first valid canonical identity and detaches caller state", function(assertions)
		local reducer = newReducer()
		local authored = rawSnapshot(1, 100, "Active", nil)
		local applied = success(reducer:observeSnapshot(authored)) :: BaseStateReducer.ApplyOutcome
		assertions.equal(applied.kind, "Applied")
		assertions.isTrue(applied.stateChanged)
		assertions.isNil(applied.feedback)

		authored.currentHealth = 1
		authored.matchId = MATCH_B
		local state = success(reducer:getState()) :: BaseStateReducer.ConvergedState
		assertions.isTrue(state.locked)
		assertions.equal((state.snapshot :: BaseProtocol.BaseSnapshot).matchId, MATCH_A)
		assertions.equal((state.snapshot :: BaseProtocol.BaseSnapshot).currentHealth, 100)
		assertions.isFalse(pcall(function()
			((state.snapshot :: any) :: any).currentHealth = 2
		end))
	end),

	TestHarness.case("accepts full-state revision gaps without fabricating feedback", function(assertions)
		local reducer = newReducer()
		success(reducer:observeSnapshot(canonicalSnapshot(1, 100, "Active", nil)))
		local gap = success(reducer:observeMessage(stateMessage(canonicalSnapshot(8, 20, "Active", nil))))
		assertions.equal(gap.kind, "Applied")
		assertions.isTrue(gap.stateChanged)
		assertions.isNil(gap.feedback)
		assertions.equal((current(reducer) :: BaseProtocol.BaseSnapshot).baseRevision, 8)
		assertions.isTrue((current(reducer) :: BaseProtocol.BaseSnapshot).lowHealth)
	end),

	TestHarness.case("recovers event-response races without state rollback", function(assertions)
		local eventFirst = newReducer()
		local newer = canonicalSnapshot(2, 80, "Active", nil)
		local feedback = success(eventFirst:observeMessage(damageMessage(newer, 20, 2, false)))
		assertions.equal(feedback.kind, "Applied")
		assertions.equal((feedback.feedback :: BaseStateReducer.DamageFeedback).appliedDamage, 20)
		assertions.equal(success(eventFirst:observeSnapshot(canonicalSnapshot(1, 100, "Active", nil))).kind, "Stale")
		assertions.equal((current(eventFirst) :: BaseProtocol.BaseSnapshot).currentHealth, 80)

		local responseFirst = newReducer()
		success(responseFirst:observeSnapshot(newer))
		local recovered = success(responseFirst:observeMessage(damageMessage(newer, 20, 2, false)))
		assertions.equal(recovered.kind, "Feedback")
		assertions.isFalse(recovered.stateChanged)
		assertions.equal((recovered.feedback :: BaseStateReducer.DamageFeedback).leakCount, 2)
		assertions.equal(success(responseFirst:observeMessage(damageMessage(newer, 20, 2, false))).kind, "Duplicate")
	end),

	TestHarness.case("never fabricates damage feedback from snapshot or State correction", function(assertions)
		local reducer = newReducer()
		local first = success(reducer:observeMessage(stateMessage(canonicalSnapshot(1, 100, "Active", nil))))
		assertions.isNil(first.feedback)
		local correction = success(reducer:observeSnapshot(canonicalSnapshot(3, 75, "Active", nil)))
		assertions.equal(correction.kind, "Applied")
		assertions.isNil(correction.feedback)
		assertions.isNil(success(reducer:getState()).lastFeedbackRevision)
	end),

	TestHarness.case("rejects foreign and immutable identity conflicts without mutation", function(assertions)
		local reducer = newReducer()
		success(reducer:observeSnapshot(canonicalSnapshot(1, 100, "Active", nil)))
		local conflicts = {
			{ kind = "Foreign", snapshot = canonicalSnapshot(2, 90, "Active", { matchId = MATCH_B }) },
			{ kind = "Foreign", snapshot = canonicalSnapshot(2, 90, "Active", { enemyEpoch = 2 }) },
			{ kind = "Rejected", snapshot = canonicalSnapshot(2, 90, "Active", { mapId = MAP_B }) },
			{ kind = "Rejected", snapshot = canonicalSnapshot(2, 90, "Active", { difficultyId = DIFFICULTY_B }) },
			{
				kind = "Rejected",
				snapshot = canonicalSnapshot(2, 90, "Active", { basePosition = Vector3.new(12.001, 3, -4) }),
			},
			{ kind = "Rejected", snapshot = canonicalSnapshot(2, 180, "Active", { maximumHealth = 200 }) },
			{ kind = "Rejected", snapshot = canonicalSnapshot(2, 90, "Active", { initializedServerTime = 99 }) },
		}
		for _, conflict in conflicts do
			assertions.equal(success(reducer:observeSnapshot(conflict.snapshot)).kind, conflict.kind)
			assertions.equal((current(reducer) :: BaseProtocol.BaseSnapshot).currentHealth, 100)
		end
	end),

	TestHarness.case("rejects stale duplicate and equal-revision conflicts", function(assertions)
		local reducer = newReducer()
		local installed = canonicalSnapshot(5, 60, "Active", nil)
		success(reducer:observeSnapshot(installed))
		assertions.equal(success(reducer:observeSnapshot(installed)).kind, "Duplicate")
		assertions.equal(success(reducer:observeSnapshot(canonicalSnapshot(4, 70, "Active", nil))).kind, "Stale")
		assertions.equal(
			success(reducer:observeSnapshot(canonicalSnapshot(5, 50, "Active", { updatedServerTime = 106 }))).kind,
			"Rejected"
		)
		assertions.equal((current(reducer) :: BaseProtocol.BaseSnapshot).currentHealth, 60)
	end),

	TestHarness.case("enforces monotonic health low time and visible status transitions", function(assertions)
		local reducer = newReducer()
		success(reducer:observeSnapshot(canonicalSnapshot(2, 50, "Active", nil)))
		for _, invalid in
			{
				canonicalSnapshot(3, 60, "Active", nil),
				canonicalSnapshot(3, 40, "Active", { updatedServerTime = 101 }),
			}
		do
			assertions.equal(success(reducer:observeSnapshot(invalid)).kind, "Rejected")
		end
		assertions.equal(success(reducer:observeSnapshot(canonicalSnapshot(4, 0, "Defeated", nil))).kind, "Applied")
		assertions.equal(success(reducer:observeSnapshot(canonicalSnapshot(5, 0, "Faulted", nil))).kind, "Rejected")

		local faulted = newReducer()
		success(faulted:observeSnapshot(canonicalSnapshot(1, 50, "Faulted", nil)))
		assertions.equal(success(faulted:observeSnapshot(canonicalSnapshot(2, 0, "Defeated", nil))).kind, "Rejected")
	end),

	TestHarness.case("accepts late terminal snapshots and damage only on real health change", function(assertions)
		for _, terminal in
			{
				canonicalSnapshot(9, 0, "Defeated", nil),
				canonicalSnapshot(7, 35, "Faulted", nil),
			}
		do
			local reducer = newReducer()
			assertions.equal(success(reducer:observeSnapshot(terminal)).kind, "Applied")
		end

		local reducer = newReducer()
		success(reducer:observeSnapshot(canonicalSnapshot(1, 100, "Active", nil)))
		local noHealthChange = {
			kind = "Damage",
			snapshot = canonicalSnapshot(2, 100, "Active", nil),
			appliedDamage = 1,
			leakCount = 1,
			lowHealthCrossed = false,
		}
		expectFailure(assertions, reducer:observeMessage(noHealthChange), "INVALID_MESSAGE")
		assertions.isNil(success(reducer:getState()).lastFeedbackRevision)
	end),

	TestHarness.case("rejects malformed hostile payloads without changing cached state", function(assertions)
		local reducer = newReducer()
		success(reducer:observeSnapshot(canonicalSnapshot(1, 100, "Active", nil)))
		local malformed = rawSnapshot(2, 90, "Active", nil)
		malformed.privateHealth = 90
		expectFailure(assertions, reducer:observeSnapshot(malformed), "INVALID_SNAPSHOT")
		expectFailure(
			assertions,
			reducer:observeMessage({
				kind = "Damage",
				snapshot = canonicalSnapshot(2, 90, "Active", nil),
				appliedDamage = 0 / 0,
				leakCount = 1,
				lowHealthCrossed = false,
			}),
			"INVALID_MESSAGE"
		)
		assertions.equal((current(reducer) :: BaseProtocol.BaseSnapshot).baseRevision, 1)
	end),

	TestHarness.case("replaces match identity only through a fresh reducer lifecycle", function(assertions)
		local oldReducer = newReducer()
		success(oldReducer:observeSnapshot(canonicalSnapshot(7, 30, "Active", nil)))
		assertions.isTrue(success(oldReducer:cleanup()))
		expectFailure(
			assertions,
			oldReducer:observeSnapshot(canonicalSnapshot(8, 20, "Active", { matchId = MATCH_B, enemyEpoch = 2 })),
			"CLEANED_UP"
		)

		local replacement = newReducer()
		local replacementSnapshot = canonicalSnapshot(1, 100, "Active", {
			matchId = MATCH_B,
			enemyEpoch = 2,
			mapId = MAP_B,
			difficultyId = DIFFICULTY_B,
			initializedServerTime = 200,
			updatedServerTime = 201,
		})
		local applied = success(replacement:observeSnapshot(replacementSnapshot))
		assertions.equal(applied.kind, "Applied")
		assertions.equal((current(replacement) :: BaseProtocol.BaseSnapshot).matchId, MATCH_B)
		assertions.equal((current(replacement) :: BaseProtocol.BaseSnapshot).enemyEpoch, 2)
	end),

	TestHarness.case("cleans identity state and feedback idempotently", function(assertions)
		local reducer = newReducer()
		success(reducer:observeMessage(damageMessage(canonicalSnapshot(2, 80, "Active", nil), 20, 1, false)))
		assertions.isTrue(success(reducer:cleanup()))
		assertions.isTrue(success(reducer:cleanup()))
		expectFailure(assertions, reducer:getState(), "CLEANED_UP")
		expectFailure(assertions, reducer:observeSnapshot(canonicalSnapshot(3, 70, "Active", nil)), "CLEANED_UP")
		expectFailure(
			assertions,
			reducer:observeMessage(stateMessage(canonicalSnapshot(3, 70, "Active", nil))),
			"CLEANED_UP"
		)
	end),
})
