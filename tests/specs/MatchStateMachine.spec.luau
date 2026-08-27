--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local MatchStateMachine = require(script.Parent.Parent.ProductionServerMatchLifecycle.MatchStateMachine)

type Assertions = TestHarness.Assertions
type MatchState = MatchStateMachine.MatchState
type StateMachine = MatchStateMachine.StateMachine

local MATCH_ID = "match:state-machine-spec"

local STATES: { MatchState } = {
	"Loading",
	"ReadyCheck",
	"PreWave",
	"WaveActive",
	"Results",
	"Closing",
}

local LEGAL_EDGES: { { MatchState } } = {
	{ "Loading", "ReadyCheck" },
	{ "Loading", "Closing" },
	{ "ReadyCheck", "PreWave" },
	{ "ReadyCheck", "Closing" },
	{ "PreWave", "WaveActive" },
	{ "PreWave", "Closing" },
	{ "WaveActive", "Results" },
	{ "WaveActive", "Closing" },
	{ "Results", "Closing" },
}

local PATH_TO_STATE: { [MatchState]: { MatchState } } = {
	Loading = {},
	ReadyCheck = { "ReadyCheck" },
	PreWave = { "ReadyCheck", "PreWave" },
	WaveActive = { "ReadyCheck", "PreWave", "WaveActive" },
	Results = { "ReadyCheck", "PreWave", "WaveActive", "Results" },
	Closing = { "Closing" },
}

local function expectSuccess(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return result.value
end

local function expectError(assertions: Assertions, result: any, code: string, operation: string): any
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local errorValue = result.error
	assertions.isTrue(table.isfrozen(errorValue))
	assertions.equal(errorValue.code, code)
	assertions.equal(errorValue.operation, operation)

	local fieldCount = 0
	for fieldName in next, errorValue do
		fieldCount += 1
		assertions.isTrue(fieldName == "code" or fieldName == "operation")
	end
	assertions.equal(fieldCount, 2)
	return errorValue
end

local function newMachine(assertions: Assertions): StateMachine
	local machine = expectSuccess(assertions, MatchStateMachine.new(MATCH_ID))
	assertions.isTrue(table.isfrozen(machine))
	return machine :: StateMachine
end

local function snapshot(assertions: Assertions, machine: StateMachine): any
	return expectSuccess(assertions, machine:getSnapshot())
end

local function commitTo(assertions: Assertions, machine: StateMachine, targetState: MatchState): any
	local beforeRevision = machine:getRevision()
	local token = expectSuccess(assertions, machine:beginTransition(targetState, beforeRevision))
	assertions.isTrue(table.isfrozen(token))
	local committed = expectSuccess(assertions, machine:commitTransition(token))
	assertions.equal(committed.state, targetState)
	assertions.equal(committed.revision, beforeRevision + 1)
	return committed
end

local function reachState(assertions: Assertions, machine: StateMachine, targetState: MatchState)
	for _, state in PATH_TO_STATE[targetState] do
		commitTo(assertions, machine, state)
	end
	assertions.equal(machine:getState(), targetState)
end

local function assertUnchanged(
	assertions: Assertions,
	machine: StateMachine,
	expectedState: MatchState,
	expectedRevision: number
)
	assertions.equal(machine:getState(), expectedState)
	assertions.equal(machine:getRevision(), expectedRevision)
	local current = snapshot(assertions, machine)
	assertions.equal(current.state, expectedState)
	assertions.equal(current.revision, expectedRevision)
end

return TestHarness.suite("match state machine transaction", {
	TestHarness.case("validates immutable identity and creates revision one Loading", function(assertions)
		for _, invalidId in { 17, "map:wrong-kind", "match:UPPERCASE", "match:" } do
			expectError(assertions, MatchStateMachine.new(invalidId), "INVALID_MATCH_ID", "new")
		end

		local machine = newMachine(assertions)
		assertions.equal(machine:getMatchId(), MATCH_ID)
		assertions.equal(machine:getState(), "Loading")
		assertions.equal(machine:getRevision(), MatchStateMachine.INITIAL_REVISION)
		assertions.isFalse(machine:isCleaned())

		local initial = snapshot(assertions, machine)
		assertions.equal(initial.matchId, MATCH_ID)
		assertions.equal(initial.state, "Loading")
		assertions.equal(initial.revision, 1)
		assertions.isTrue(table.isfrozen(initial))

		local changedHandle = pcall(function()
			(machine :: any).matchId = "match:counterfeit"
		end)
		assertions.isFalse(changedHandle)
		assertions.equal(machine:getMatchId(), MATCH_ID)
	end),

	TestHarness.case("commits every and only every legal state edge", function(assertions)
		local seen: { [string]: boolean } = {}
		for _, edge in LEGAL_EDGES do
			local fromState = edge[1]
			local targetState = edge[2]
			local signature = `{fromState}->{targetState}`
			assertions.isFalse(seen[signature] == true)
			seen[signature] = true
			assertions.isTrue(MatchStateMachine.isLegalTransition(fromState, targetState))

			local machine = newMachine(assertions)
			reachState(assertions, machine, fromState)
			local beforeRevision = machine:getRevision()
			local committed = commitTo(assertions, machine, targetState)
			assertions.equal(machine:getState(), targetState)
			assertions.equal(machine:getRevision(), beforeRevision + 1)
			assertions.equal(committed.matchId, MATCH_ID)
		end
		assertions.equal(#LEGAL_EDGES, 9)
	end),

	TestHarness.case("rejects every illegal duplicate and terminal edge without mutation", function(assertions)
		for _, fromState in STATES do
			local machine = newMachine(assertions)
			reachState(assertions, machine, fromState)
			local revision = machine:getRevision()

			for _, targetState in STATES do
				local isLegal = MatchStateMachine.isLegalTransition(fromState, targetState)
				if not isLegal then
					local expectedCode = if fromState == "Closing"
						then "TERMINAL_STATE"
						elseif fromState == targetState then "DUPLICATE_TRANSITION"
						else "ILLEGAL_TRANSITION"
					expectError(
						assertions,
						machine:beginTransition(targetState, revision),
						expectedCode,
						"beginTransition"
					)
					assertUnchanged(assertions, machine, fromState, revision)
				end
			end
		end

		assertions.isFalse(MatchStateMachine.isLegalTransition("Unknown", "Loading"))
		assertions.isFalse(MatchStateMachine.isLegalTransition("Loading", 4))
	end),

	TestHarness.case("rejects invalid stale and duplicate begins without acquiring a lock", function(assertions)
		local machine = newMachine(assertions)
		expectError(assertions, machine:beginTransition("ReadyCheck", 0), "INVALID_REVISION", "beginTransition")
		expectError(assertions, machine:beginTransition("ReadyCheck", math.huge), "INVALID_REVISION", "beginTransition")
		expectError(assertions, machine:beginTransition("ReadyCheck", 2), "STALE_REVISION", "beginTransition")
		expectError(assertions, machine:beginTransition("NotAState", 1), "INVALID_TARGET", "beginTransition")
		expectError(assertions, machine:beginTransition("Loading", 1), "DUPLICATE_TRANSITION", "beginTransition")
		assertUnchanged(assertions, machine, "Loading", 1)

		commitTo(assertions, machine, "ReadyCheck")
		expectError(assertions, machine:beginTransition("ReadyCheck", 2), "DUPLICATE_TRANSITION", "beginTransition")
		assertUnchanged(assertions, machine, "ReadyCheck", 2)
	end),

	TestHarness.case("holds one authenticated token against transition reentry", function(assertions)
		local machine = newMachine(assertions)
		local heldToken = expectSuccess(assertions, machine:beginTransition("ReadyCheck", 1))
		assertUnchanged(assertions, machine, "Loading", 1)

		expectError(assertions, machine:beginTransition("Closing", 1), "TRANSITION_IN_PROGRESS", "beginTransition")
		expectError(assertions, machine:touch(1), "TRANSITION_IN_PROGRESS", "touch")
		assertUnchanged(assertions, machine, "Loading", 1)

		local committed = expectSuccess(assertions, machine:commitTransition(heldToken))
		assertions.equal(committed.state, "ReadyCheck")
		assertions.equal(committed.revision, 2)
	end),

	TestHarness.case("rolls back exactly once without changing state or revision", function(assertions)
		local machine = newMachine(assertions)
		local token = expectSuccess(assertions, machine:beginTransition("ReadyCheck", 1))
		local rolledBack = expectSuccess(assertions, machine:rollbackTransition(token))
		assertions.equal(rolledBack.matchId, MATCH_ID)
		assertions.equal(rolledBack.state, "Loading")
		assertions.equal(rolledBack.revision, 1)
		assertions.isTrue(table.isfrozen(rolledBack))
		assertUnchanged(assertions, machine, "Loading", 1)

		expectError(assertions, machine:rollbackTransition(token), "INVALID_TOKEN", "rollbackTransition")
		commitTo(assertions, machine, "Closing")
	end),

	TestHarness.case(
		"rejects counterfeit foreign and repeated tokens without consuming the live token",
		function(assertions)
			local first = newMachine(assertions)
			local second = newMachine(assertions)
			local token = expectSuccess(assertions, first:beginTransition("ReadyCheck", 1))
			local counterfeit = table.freeze({})

			expectError(assertions, first:commitTransition(counterfeit), "INVALID_TOKEN", "commitTransition")
			expectError(assertions, second:commitTransition(token), "INVALID_TOKEN", "commitTransition")
			expectError(assertions, first:rollbackTransition(false), "INVALID_TOKEN", "rollbackTransition")
			assertUnchanged(assertions, first, "Loading", 1)

			expectSuccess(assertions, first:commitTransition(token))
			expectError(assertions, first:commitTransition(token), "INVALID_TOKEN", "commitTransition")
			expectError(assertions, first:rollbackTransition(token), "INVALID_TOKEN", "rollbackTransition")
			assertUnchanged(assertions, first, "ReadyCheck", 2)

			local rollbackToken = expectSuccess(assertions, first:beginTransition("PreWave", 2))
			expectError(assertions, first:rollbackTransition(counterfeit), "INVALID_TOKEN", "rollbackTransition")
			expectSuccess(assertions, first:rollbackTransition(rollbackToken))
			expectError(assertions, first:rollbackTransition(rollbackToken), "INVALID_TOKEN", "rollbackTransition")
			assertUnchanged(assertions, first, "ReadyCheck", 2)
		end
	),

	TestHarness.case("returns newly detached frozen snapshots and resists mutation", function(assertions)
		local machine = newMachine(assertions)
		local first = snapshot(assertions, machine)
		local second = snapshot(assertions, machine)
		assertions.notEqual(first, second)
		assertions.isTrue(table.isfrozen(first))
		assertions.isTrue(table.isfrozen(second))

		local stateWrite = pcall(function()
			first.state = "Closing"
		end)
		local revisionWrite = pcall(function()
			first.revision = 900
		end)
		assertions.isFalse(stateWrite)
		assertions.isFalse(revisionWrite)
		assertUnchanged(assertions, machine, "Loading", 1)
	end),

	TestHarness.case("touch advances one visible revision without changing state", function(assertions)
		local machine = newMachine(assertions)
		local touched = expectSuccess(assertions, machine:touch(1))
		assertions.equal(touched.matchId, MATCH_ID)
		assertions.equal(touched.state, "Loading")
		assertions.equal(touched.revision, 2)
		assertions.isTrue(table.isfrozen(touched))

		expectError(assertions, machine:touch(1), "STALE_REVISION", "touch")
		expectError(assertions, machine:touch(0), "INVALID_REVISION", "touch")
		assertUnchanged(assertions, machine, "Loading", 2)

		local token = expectSuccess(assertions, machine:beginTransition("ReadyCheck", 2))
		expectError(assertions, machine:touch(2), "TRANSITION_IN_PROGRESS", "touch")
		expectSuccess(assertions, machine:rollbackTransition(token))
		local secondTouch = expectSuccess(assertions, machine:touch(2))
		assertions.equal(secondTouch.revision, 3)
		assertions.equal(secondTouch.state, "Loading")
	end),

	TestHarness.case("keeps Closing terminal while it remains queryable", function(assertions)
		local machine = newMachine(assertions)
		commitTo(assertions, machine, "Closing")
		local terminal = snapshot(assertions, machine)
		assertions.equal(terminal.state, "Closing")
		assertions.equal(terminal.revision, 2)

		for _, targetState in STATES do
			expectError(assertions, machine:beginTransition(targetState, 2), "TERMINAL_STATE", "beginTransition")
		end
		expectError(assertions, machine:touch(2), "TERMINAL_STATE", "touch")
		assertUnchanged(assertions, machine, "Closing", 2)
	end),

	TestHarness.case("cleans once invalidates a held token and rejects post-clean operations", function(assertions)
		local machine = newMachine(assertions)
		local token = expectSuccess(assertions, machine:beginTransition("ReadyCheck", 1))

		assertions.isTrue(expectSuccess(assertions, machine:cleanup()))
		assertions.isTrue(machine:isCleaned())
		assertions.isFalse(expectSuccess(assertions, machine:cleanup()))
		assertions.equal(machine:getMatchId(), MATCH_ID)
		assertions.equal(machine:getState(), "Loading")
		assertions.equal(machine:getRevision(), 1)

		expectError(assertions, machine:commitTransition(token), "CLEANED", "commitTransition")
		expectError(assertions, machine:rollbackTransition(token), "CLEANED", "rollbackTransition")
		expectError(assertions, machine:beginTransition("ReadyCheck", 1), "CLEANED", "beginTransition")
		expectError(assertions, machine:touch(1), "CLEANED", "touch")
		expectError(assertions, machine:getSnapshot(), "CLEANED", "getSnapshot")
		assertions.equal(machine:getState(), "Loading")
		assertions.equal(machine:getRevision(), 1)
	end),
})
