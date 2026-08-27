--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local ParticipantRoster = require(script.Parent.Parent.ProductionServerMatchRoster.ParticipantRoster)

type Assertions = TestHarness.Assertions

local ERROR_FIELDS: { [string]: boolean } = table.freeze({
	code = true,
	operation = true,
})

local function connection(label: string): { label: string }
	return { label = label }
end

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
	for fieldName in errorValue do
		fieldCount += 1
		assertions.isTrue(ERROR_FIELDS[fieldName] == true)
	end
	assertions.equal(fieldCount, 2)
	return errorValue
end

local function newRoster(assertions: Assertions): any
	local roster = expectSuccess(assertions, ParticipantRoster.new())
	assertions.isTrue(table.isfrozen(roster))
	assertions.isFalse(roster:isCleaned())
	return roster
end

local function add(assertions: Assertions, roster: any, key: any, userId: number, state: string?): any
	local outcome = expectSuccess(assertions, roster:connect(key, userId, state or "ReadyCheck"))
	assertions.isTrue(table.isfrozen(outcome))
	return outcome
end

local function snapshot(assertions: Assertions, roster: any): { any }
	local participants = expectSuccess(assertions, roster:getSnapshot())
	assertions.isTrue(table.isfrozen(participants))
	for _, participant in participants do
		assertions.isTrue(table.isfrozen(participant))
		assertions.isFalse(typeof(participant) == "Instance")
		for _, value in participant do
			assertions.isFalse(typeof(value) == "Instance")
		end
	end
	return participants
end

local function readiness(assertions: Assertions, roster: any): any
	local value = expectSuccess(assertions, roster:getReadiness())
	assertions.isTrue(table.isfrozen(value))
	return value
end

return TestHarness.suite("match participant roster", {
	TestHarness.case(
		"validates opaque connections UserIds and match states without sign assumptions",
		function(assertions)
			local roster = newRoster(assertions)
			local key = connection("valid")
			local nan = 0 / 0

			expectError(assertions, roster:connect(nil, 1, "Loading"), "INVALID_CONNECTION", "connect")
			expectError(assertions, roster:connect(key, 0, "Loading"), "INVALID_USER_ID", "connect")
			expectError(assertions, roster:connect(key, 1.5, "Loading"), "INVALID_USER_ID", "connect")
			expectError(assertions, roster:connect(key, nan, "Loading"), "INVALID_USER_ID", "connect")
			expectError(assertions, roster:connect(key, math.huge, "Loading"), "INVALID_USER_ID", "connect")
			expectError(assertions, roster:connect(key, 9_007_199_254_740_992, "Loading"), "INVALID_USER_ID", "connect")
			expectError(assertions, roster:connect(key, 1, "Lobby"), "INVALID_MATCH_STATE", "connect")

			local negative = add(assertions, roster, key, -9_007_199_254_740_991, "Loading")
			assertions.equal(negative.kind, "Admitted")
			assertions.isTrue(negative.changed)
			assertions.equal(negative.participant.userId, -9_007_199_254_740_991)
			assertions.equal(#snapshot(assertions, roster), 1)
		end
	),

	TestHarness.case("admits during Loading and ReadyCheck with deterministic detached ordering", function(assertions)
		local roster = newRoster(assertions)
		local forty = connection("forty")
		local minusSeven = connection("minus-seven")
		local ten = connection("ten")

		add(assertions, roster, forty, 40, "Loading")
		add(assertions, roster, minusSeven, -7, "ReadyCheck")
		add(assertions, roster, ten, 10, "ReadyCheck")
		local participants = snapshot(assertions, roster)
		assertions.equal(#participants, 3)
		assertions.equal(participants[1].userId, -7)
		assertions.equal(participants[2].userId, 10)
		assertions.equal(participants[3].userId, 40)
		for _, participant in participants do
			assertions.equal(participant.state, "Active")
			assertions.isFalse(participant.ready)
		end

		expectError(assertions, roster:connect(forty, 40, "ReadyCheck"), "DUPLICATE_CONNECTION", "connect")
		local duplicateIdentity = connection("duplicate-identity")
		expectError(assertions, roster:connect(duplicateIdentity, 40, "ReadyCheck"), "DUPLICATE_CONNECTION", "connect")
		expectError(assertions, roster:resolveConnection(duplicateIdentity), "UNKNOWN_CONNECTION", "resolveConnection")
	end),

	TestHarness.case("enforces the four identity lifetime cap without backfill", function(assertions)
		local roster = newRoster(assertions)
		local admitted = {}
		for userId = 1, ParticipantRoster.MAX_PARTICIPANTS do
			local key = connection(`admitted-{userId}`)
			admitted[userId] = key
			local outcome = add(assertions, roster, key, userId)
			assertions.equal(outcome.kind, "Admitted")
		end

		expectSuccess(assertions, roster:disconnect(admitted[1]))
		local excess = connection("excess")
		local excessOutcome = add(assertions, roster, excess, 5)
		assertions.equal(excessOutcome.kind, "UntrackedSpectator")
		assertions.isFalse(excessOutcome.changed)
		assertions.isNil(excessOutcome.participant)
		assertions.equal(#snapshot(assertions, roster), 4)
		expectError(assertions, roster:setReadyForConnection(excess), "UNTRACKED_SPECTATOR", "setReadyForConnection")
		expectError(assertions, roster:disconnect(excess), "UNTRACKED_SPECTATOR", "disconnect")

		local later = connection("later")
		local laterOutcome = add(assertions, roster, later, 6, "PreWave")
		assertions.equal(laterOutcome.kind, "UntrackedSpectator")
		assertions.equal(#snapshot(assertions, roster), 4)
	end),

	TestHarness.case("uses epochs so repeated and delayed removals cannot disconnect a reconnect", function(assertions)
		local roster = newRoster(assertions)
		local oldConnection = connection("old")
		local newConnection = connection("new")
		add(assertions, roster, oldConnection, 101)

		local disconnected = expectSuccess(assertions, roster:disconnect(oldConnection))
		assertions.equal(disconnected.state, "Disconnected")
		expectError(assertions, roster:disconnect(oldConnection), "ALREADY_DISCONNECTED", "disconnect")

		local reactivated = add(assertions, roster, newConnection, 101, "ReadyCheck")
		assertions.equal(reactivated.kind, "Reactivated")
		assertions.isTrue(reactivated.changed)
		assertions.equal(reactivated.participant.state, "Active")
		expectError(assertions, roster:disconnect(oldConnection), "STALE_CONNECTION", "disconnect")
		assertions.equal(readiness(assertions, roster).activeCount, 1)

		local newestRemoval = expectSuccess(assertions, roster:disconnect(newConnection))
		assertions.equal(newestRemoval.state, "Disconnected")
		assertions.equal(readiness(assertions, roster).activeCount, 0)
	end),

	TestHarness.case("reactivates a ReadyCheck placeholder with readiness reset", function(assertions)
		local roster = newRoster(assertions)
		local first = connection("first")
		local second = connection("second")
		add(assertions, roster, first, 22)
		expectSuccess(assertions, roster:setReadyForConnection(first))
		expectSuccess(assertions, roster:disconnect(first))

		local reactivated = add(assertions, roster, second, 22, "ReadyCheck")
		assertions.equal(reactivated.kind, "Reactivated")
		assertions.equal(reactivated.participant.state, "Active")
		assertions.isFalse(reactivated.participant.ready)
		local resolved = expectSuccess(assertions, roster:resolveConnection(second))
		assertions.equal(resolved.userId, 22)
		assertions.equal(resolved.state, "Active")
		assertions.isFalse(resolved.ready)
	end),

	TestHarness.case("turns only a retained disconnected participant into a post-check Spectator", function(assertions)
		local roster = newRoster(assertions)
		local first = connection("first")
		local spectator = connection("spectator")
		add(assertions, roster, first, 55)
		expectSuccess(assertions, roster:disconnect(first))

		local outcome = add(assertions, roster, spectator, 55, "PreWave")
		assertions.equal(outcome.kind, "Spectator")
		assertions.isTrue(outcome.changed)
		assertions.equal(outcome.participant.state, "Spectator")
		assertions.isFalse(outcome.participant.ready)
		expectError(
			assertions,
			roster:setReadyForConnection(spectator),
			"INACTIVE_PARTICIPANT",
			"setReadyForConnection"
		)
		expectError(assertions, roster:disconnect(spectator), "INACTIVE_PARTICIPANT", "disconnect")
		expectError(
			assertions,
			roster:connect(connection("spectator-again"), 55, "Results"),
			"DUPLICATE_CONNECTION",
			"connect"
		)

		local newIdentity = connection("new-identity")
		local untracked = add(assertions, roster, newIdentity, 56, "PreWave")
		assertions.equal(untracked.kind, "UntrackedSpectator")
		assertions.equal(#snapshot(assertions, roster), 1)
		assertions.equal(readiness(assertions, roster).activeCount, 0)
	end),

	TestHarness.case("keeps Returned placeholders retained and ineligible across reconnect", function(assertions)
		local roster = newRoster(assertions)
		local first = connection("first")
		local returnedConnection = connection("returned")
		add(assertions, roster, first, 77)

		local batch = expectSuccess(assertions, roster:markUnreadyActiveReturned())
		assertions.equal(batch.changedCount, 1)
		local outcome = add(assertions, roster, returnedConnection, 77, "ReadyCheck")
		assertions.equal(outcome.kind, "Returned")
		assertions.isFalse(outcome.changed)
		assertions.equal(outcome.participant.state, "Returned")
		expectError(assertions, roster:disconnect(first), "STALE_CONNECTION", "disconnect")
		expectError(
			assertions,
			roster:setReadyForConnection(returnedConnection),
			"INACTIVE_PARTICIPANT",
			"setReadyForConnection"
		)
		expectError(assertions, roster:disconnect(returnedConnection), "INACTIVE_PARTICIPANT", "disconnect")
		assertions.equal(readiness(assertions, roster).activeCount, 0)
	end),

	TestHarness.case("computes active readiness from current eligible voters only", function(assertions)
		local roster = newRoster(assertions)
		local first = connection("first")
		local second = connection("second")
		local third = connection("third")
		local empty = readiness(assertions, roster)
		assertions.equal(empty.activeCount, 0)
		assertions.equal(empty.readyActiveCount, 0)
		assertions.isFalse(empty.allActiveReady)

		add(assertions, roster, first, 1)
		add(assertions, roster, second, 2)
		add(assertions, roster, third, 3)
		expectSuccess(assertions, roster:setReadyForConnection(first))
		expectSuccess(assertions, roster:setReadyForConnection(second))
		expectError(assertions, roster:setReadyForConnection(first), "ALREADY_READY", "setReadyForConnection")
		local partial = readiness(assertions, roster)
		assertions.equal(partial.activeCount, 3)
		assertions.equal(partial.readyActiveCount, 2)
		assertions.isFalse(partial.allActiveReady)

		expectSuccess(assertions, roster:disconnect(third))
		local threshold = readiness(assertions, roster)
		assertions.equal(threshold.activeCount, 2)
		assertions.equal(threshold.readyActiveCount, 2)
		assertions.isTrue(threshold.allActiveReady)

		expectSuccess(assertions, roster:disconnect(first))
		expectSuccess(assertions, roster:disconnect(second))
		local noActive = readiness(assertions, roster)
		assertions.equal(noActive.activeCount, 0)
		assertions.equal(noActive.readyActiveCount, 0)
		assertions.isFalse(noActive.allActiveReady)
	end),

	TestHarness.case("marks all and only unready Active participants Returned in one batch", function(assertions)
		local roster = newRoster(assertions)
		local first = connection("first")
		local second = connection("second")
		local third = connection("third")
		local disconnected = connection("disconnected")
		add(assertions, roster, first, 1)
		add(assertions, roster, second, 2)
		add(assertions, roster, third, 3)
		add(assertions, roster, disconnected, 4)
		expectSuccess(assertions, roster:setReadyForConnection(first))
		expectSuccess(assertions, roster:disconnect(disconnected))

		local batch = expectSuccess(assertions, roster:markUnreadyActiveReturned())
		assertions.isTrue(table.isfrozen(batch))
		assertions.equal(batch.changedCount, 2)
		local participants = snapshot(assertions, roster)
		assertions.equal(participants[1].state, "Active")
		assertions.isTrue(participants[1].ready)
		assertions.equal(participants[2].state, "Returned")
		assertions.isFalse(participants[2].ready)
		assertions.equal(participants[3].state, "Returned")
		assertions.isFalse(participants[3].ready)
		assertions.equal(participants[4].state, "Disconnected")
		assertions.isFalse(participants[4].ready)

		local repeated = expectSuccess(assertions, roster:markUnreadyActiveReturned())
		assertions.equal(repeated.changedCount, 0)
		local finalReadiness = readiness(assertions, roster)
		assertions.equal(finalReadiness.activeCount, 1)
		assertions.equal(finalReadiness.readyActiveCount, 1)
		assertions.isTrue(finalReadiness.allActiveReady)
	end),

	TestHarness.case("returns newly detached deeply frozen snapshots that resist mutation", function(assertions)
		local roster = newRoster(assertions)
		local key = connection("private-connection")
		add(assertions, roster, key, 321)
		local first = snapshot(assertions, roster)
		local second = snapshot(assertions, roster)
		assertions.notEqual(first, second)
		assertions.notEqual(first[1], second[1])

		local arrayWrite = pcall(function()
			first[2] = first[1]
		end)
		local userIdWrite = pcall(function()
			first[1].userId = 999
		end)
		local stateWrite = pcall(function()
			first[1].state = "Returned"
		end)
		assertions.isFalse(arrayWrite)
		assertions.isFalse(userIdWrite)
		assertions.isFalse(stateWrite)

		local unchanged = snapshot(assertions, roster)
		assertions.equal(#unchanged, 1)
		assertions.equal(unchanged[1].userId, 321)
		assertions.equal(unchanged[1].state, "Active")
		assertions.isFalse(unchanged[1].ready)
		assertions.notEqual(unchanged, key)
		assertions.notEqual(unchanged[1], key)
	end),

	TestHarness.case("cleans all private state exactly once and blocks every later operation", function(assertions)
		local roster = newRoster(assertions)
		local key = connection("owned")
		add(assertions, roster, key, 444)
		snapshot(assertions, roster)

		assertions.isTrue(expectSuccess(assertions, roster:cleanup()))
		assertions.isTrue(roster:isCleaned())
		assertions.isFalse(expectSuccess(assertions, roster:cleanup()))
		expectError(assertions, roster:getSnapshot(), "CLEANED", "getSnapshot")
		expectError(assertions, roster:getReadiness(), "CLEANED", "getReadiness")
		expectError(assertions, roster:resolveConnection(key), "CLEANED", "resolveConnection")
		expectError(assertions, roster:disconnect(key), "CLEANED", "disconnect")
		expectError(assertions, roster:setReadyForConnection(key), "CLEANED", "setReadyForConnection")
		expectError(assertions, roster:markUnreadyActiveReturned(), "CLEANED", "markUnreadyActiveReturned")
		expectError(assertions, roster:connect(connection("later"), 445, "ReadyCheck"), "CLEANED", "connect")
	end),
})
