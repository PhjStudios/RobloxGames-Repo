--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local WaveStateReducer = require(script.Parent.Parent.ProductionClientWaves.WaveStateReducer)

type Assertions = TestHarness.Assertions

local MATCH_A = "match:phase11-wave-reducer-a"
local MATCH_B = "match:phase11-wave-reducer-b"

local function counts(total: number, spawned: number, alive: number, leaked: number, otherwiseResolved: number): any
	return {
		totalScheduled = total,
		pending = total - spawned,
		spawned = spawned,
		alive = alive,
		leaked = leaked,
		otherwiseResolved = otherwiseResolved,
	}
end

local function runningSnapshot(revision: number, overrides: { [string]: any }?): { [string]: any }
	local values = overrides or {}
	local currentWaveNumber = values.currentWaveNumber or 1
	local totalWaves = values.totalWaves or 3
	local startTime = values.waveStartedServerTime or (100 + (currentWaveNumber - 1) * 20)
	local currentCounts = values.currentCounts or counts(3, math.min(revision - 1, 3), math.min(revision - 1, 3), 0, 0)
	local aggregateCounts = values.aggregateCounts
		or counts(3, math.min(revision - 1, 3), math.min(revision - 1, 3), 0, 0)
	return {
		matchId = values.matchId or MATCH_A,
		enemyEpoch = values.enemyEpoch or 1,
		mapId = values.mapId or "map:phase11-reducer",
		difficultyId = values.difficultyId or "difficulty:phase11-reducer",
		state = values.state or "Running",
		waveRevision = revision,
		currentWaveNumber = currentWaveNumber,
		totalWaves = totalWaves,
		currentWaveId = values.currentWaveId or `wave:phase11-reducer-{currentWaveNumber}`,
		bossKind = values.bossKind or "None",
		timerPhase = values.timerPhase or "WaveDeadline",
		waveStartedServerTime = startTime,
		deadlineServerTime = values.deadlineServerTime or (startTime + 10),
		intermissionEndsServerTime = values.intermissionEndsServerTime or 0,
		skipAvailableServerTime = values.skipAvailableServerTime or (startTime + 2),
		finiteCompleteServerTime = values.finiteCompleteServerTime or 0,
		currentCounts = currentCounts,
		aggregateCounts = aggregateCounts,
		skipState = values.skipState or {
			available = false,
			activeParticipantCount = 2,
			yesVoteCount = 0,
			requiredVoteCount = 2,
			quorumPending = false,
		},
	}
end

local function terminalSnapshot(revision: number, state: string): { [string]: any }
	local completeTime = if state == "FiniteComplete" then 150 else 0
	return runningSnapshot(revision, {
		state = state,
		timerPhase = "None",
		currentWaveNumber = 3,
		currentWaveId = "wave:phase11-reducer-3",
		waveStartedServerTime = 140,
		deadlineServerTime = 150,
		skipAvailableServerTime = 0,
		finiteCompleteServerTime = completeTime,
		currentCounts = counts(1, 1, 0, 0, 1),
		aggregateCounts = counts(7, 7, 0, 1, 6),
		skipState = {
			available = false,
			activeParticipantCount = 2,
			yesVoteCount = 0,
			requiredVoteCount = 2,
			quorumPending = false,
		},
	})
end

local function expectSuccess(assertions: Assertions, resultValue: any): any
	if not resultValue.ok then
		local errorValue = resultValue.error
		local detail = if type(errorValue) == "table" then tostring(errorValue.code) else "UNKNOWN"
		error(`[ATD_TEST][code=WAVE_REDUCER_EXPECTED_SUCCESS][detail={detail}]`, 0)
	end
	assertions.isTrue(resultValue.ok)
	return resultValue.value
end

local function expectError(assertions: Assertions, resultValue: any, code: string)
	assertions.isFalse(resultValue.ok)
	if resultValue.ok then
		error("[ATD_TEST][code=WAVE_REDUCER_EXPECTED_ERROR]", 0)
	end
	assertions.equal(resultValue.error.code, code)
end

local function newReducer(): WaveStateReducer.Reducer
	local resultValue = WaveStateReducer.new()
	if not resultValue.ok then
		error("[ATD_TEST][code=WAVE_REDUCER_CREATION_FAILED]", 0)
	end
	return resultValue.value
end

local function state(assertions: Assertions, reducer: WaveStateReducer.Reducer): any
	return expectSuccess(assertions, reducer:getState())
end

return TestHarness.suite("WaveStateReducer", {
	TestHarness.case("locks from the first valid event using a detached frozen snapshot", function(assertions)
		local reducer = newReducer()
		local raw = runningSnapshot(1)
		local outcome = expectSuccess(assertions, reducer:observeEvent(raw))
		assertions.equal(outcome.kind, "Applied")
		assertions.isTrue(outcome.stateChanged)
		local converged = state(assertions, reducer)
		assertions.isTrue(converged.locked)
		assertions.isTrue(table.isfrozen(converged.snapshot))
		assertions.isTrue(table.isfrozen(converged.snapshot.currentCounts))
		assertions.isTrue(table.isfrozen(converged.snapshot.skipState))
		raw.currentWaveNumber = 2
		raw.currentCounts.spawned = 3
		assertions.equal(state(assertions, reducer).snapshot.currentWaveNumber, 1)
		assertions.equal(state(assertions, reducer).snapshot.currentCounts.spawned, 0)
	end),

	TestHarness.case("accepts only contiguous newer events and latches one skipped recovery", function(assertions)
		local reducer = newReducer()
		expectSuccess(assertions, reducer:observeEvent(runningSnapshot(1)))
		local skipped = expectSuccess(assertions, reducer:observeEvent(runningSnapshot(3)))
		assertions.equal(skipped.kind, "Skipped")
		assertions.isTrue(skipped.recoveryRequired)
		assertions.isTrue(skipped.recoveryRequested)
		assertions.equal(state(assertions, reducer).snapshot.waveRevision, 1)

		local repeated = expectSuccess(assertions, reducer:observeEvent(runningSnapshot(4)))
		assertions.equal(repeated.kind, "Skipped")
		assertions.isFalse(repeated.recoveryRequested)
		assertions.equal(state(assertions, reducer).snapshot.waveRevision, 1)

		local contiguous = expectSuccess(assertions, reducer:observeEvent(runningSnapshot(2)))
		assertions.equal(contiguous.kind, "Applied")
		assertions.isFalse(contiguous.recoveryRequired)
		assertions.equal(state(assertions, reducer).snapshot.waveRevision, 2)
	end),

	TestHarness.case("uses direct Get and Submit responses to heal full-state revision gaps", function(assertions)
		local reducer = newReducer()
		expectSuccess(assertions, reducer:observeEvent(runningSnapshot(1)))
		expectSuccess(assertions, reducer:observeEvent(runningSnapshot(4)))
		local healed = expectSuccess(assertions, reducer:observeGetResponse(runningSnapshot(4), true))
		assertions.equal(healed.kind, "Applied")
		assertions.equal(state(assertions, reducer).snapshot.waveRevision, 4)
		assertions.isFalse(state(assertions, reducer).recoveryRequired)

		local submitted = expectSuccess(assertions, reducer:observeSubmitResponse(runningSnapshot(6)))
		assertions.equal(submitted.kind, "Applied")
		assertions.equal(state(assertions, reducer).snapshot.waveRevision, 6)
	end),

	TestHarness.case("only an authorized Get response may replace a locked Match", function(assertions)
		local reducer = newReducer()
		expectSuccess(assertions, reducer:observeEvent(runningSnapshot(1)))
		local foreignEvent = expectSuccess(
			assertions,
			reducer:observeEvent(runningSnapshot(1, {
				matchId = MATCH_B,
			}))
		)
		assertions.equal(foreignEvent.kind, "WrongMatch")
		assertions.isTrue(foreignEvent.recoveryRequested)
		assertions.equal(state(assertions, reducer).snapshot.matchId, MATCH_A)

		local submit = expectSuccess(
			assertions,
			reducer:observeSubmitResponse(runningSnapshot(2, {
				matchId = MATCH_B,
			}))
		)
		assertions.equal(submit.kind, "WrongMatch")
		assertions.equal(state(assertions, reducer).snapshot.matchId, MATCH_A)

		local staleGet = expectSuccess(
			assertions,
			reducer:observeGetResponse(
				runningSnapshot(2, {
					matchId = MATCH_B,
				}),
				false
			)
		)
		assertions.equal(staleGet.kind, "WrongMatch")
		assertions.equal(state(assertions, reducer).snapshot.matchId, MATCH_A)

		local replacement = expectSuccess(
			assertions,
			reducer:observeGetResponse(
				runningSnapshot(2, {
					matchId = MATCH_B,
				}),
				true
			)
		)
		assertions.equal(replacement.kind, "Replaced")
		assertions.isTrue(replacement.matchReplaced)
		assertions.equal(state(assertions, reducer).snapshot.matchId, MATCH_B)
		assertions.isFalse(state(assertions, reducer).recoveryRequired)
	end),

	TestHarness.case("pins epoch map difficulty and total-wave identity", function(assertions)
		local variants = {
			{ enemyEpoch = 2 },
			{ mapId = "map:phase11-other" },
			{ difficultyId = "difficulty:phase11-other" },
			{ totalWaves = 4 },
		}
		for _, overrides in variants do
			local reducer = newReducer()
			expectSuccess(assertions, reducer:observeEvent(runningSnapshot(1)))
			local rejected = expectSuccess(assertions, reducer:observeEvent(runningSnapshot(2, overrides)))
			assertions.equal(rejected.kind, "Rejected")
			assertions.equal(state(assertions, reducer).snapshot.waveRevision, 1)
		end
	end),

	TestHarness.case("ignores duplicate and stale snapshots and rejects equal-revision conflicts", function(assertions)
		local reducer = newReducer()
		local first = runningSnapshot(2)
		expectSuccess(assertions, reducer:observeGetResponse(first, true))
		assertions.equal(expectSuccess(assertions, reducer:observeEvent(runningSnapshot(2))).kind, "Duplicate")
		assertions.equal(expectSuccess(assertions, reducer:observeEvent(runningSnapshot(1))).kind, "Stale")
		local conflict = runningSnapshot(2, {
			skipState = {
				available = true,
				activeParticipantCount = 2,
				yesVoteCount = 0,
				requiredVoteCount = 2,
				quorumPending = false,
			},
		})
		assertions.equal(expectSuccess(assertions, reducer:observeEvent(conflict)).kind, "Rejected")
		assertions.isFalse(state(assertions, reducer).snapshot.skipState.available)
	end),

	TestHarness.case("pins terminal state and rejects wave-number regression", function(assertions)
		local reducer = newReducer()
		expectSuccess(assertions, reducer:observeGetResponse(terminalSnapshot(5, "FiniteComplete"), true))
		local reopened = expectSuccess(
			assertions,
			reducer:observeGetResponse(
				runningSnapshot(6, {
					currentWaveNumber = 3,
					currentWaveId = "wave:phase11-reducer-3",
					waveStartedServerTime = 140,
					deadlineServerTime = 150,
					skipAvailableServerTime = 0,
					timerPhase = "PostDeadline",
					currentCounts = counts(1, 1, 0, 0, 1),
					aggregateCounts = counts(7, 7, 0, 1, 6),
				}),
				true
			)
		)
		assertions.equal(reopened.kind, "Rejected")
		assertions.equal(state(assertions, reducer).snapshot.state, "FiniteComplete")

		local second = newReducer()
		expectSuccess(
			assertions,
			second:observeGetResponse(
				runningSnapshot(1, {
					currentWaveNumber = 2,
					currentWaveId = "wave:phase11-reducer-2",
				}),
				true
			)
		)
		local regressed = expectSuccess(assertions, second:observeGetResponse(runningSnapshot(2), true))
		assertions.equal(regressed.kind, "Rejected")
		assertions.equal(state(assertions, second).snapshot.currentWaveNumber, 2)
	end),

	TestHarness.case("rejects malformed values and cleans cached identity idempotently", function(assertions)
		local reducer = newReducer()
		expectError(assertions, reducer:observeEvent({}), "INVALID_SNAPSHOT")
		expectError(assertions, reducer:observeGetResponse(runningSnapshot(1), "yes"), "INVALID_ARGUMENT")
		expectSuccess(assertions, reducer:observeEvent(runningSnapshot(1)))
		assertions.isTrue(expectSuccess(assertions, reducer:reset()))
		assertions.isFalse(state(assertions, reducer).locked)
		assertions.isFalse(state(assertions, reducer).recoveryRequired)
		assertions.isFalse(expectSuccess(assertions, reducer:reset()))
		expectSuccess(assertions, reducer:observeGetResponse(runningSnapshot(2), true))
		assertions.isTrue(expectSuccess(assertions, reducer:cleanup()))
		assertions.isTrue(expectSuccess(assertions, reducer:cleanup()))
		expectError(assertions, reducer:getState(), "CLEANED_UP")
		expectError(assertions, reducer:reset(), "CLEANED_UP")
		expectError(assertions, reducer:observeEvent(runningSnapshot(2)), "CLEANED_UP")
	end),
})
