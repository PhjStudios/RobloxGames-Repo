--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local MatchReadyViewModel = require(script.Parent.Parent.ProductionClientMatch.MatchReadyViewModel)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:view-model-test"
local OTHER_MATCH_ID = "match:other-view-model"

local function participant(userId: number, state: string, ready: boolean): { [string]: unknown }
	return {
		userId = userId,
		state = state,
		ready = ready,
	}
end

local function snapshot(
	revision: number,
	state: string,
	participants: { { [string]: unknown } }?,
	matchId: string?,
	deadlineServerTime: number?
): { [string]: unknown }
	local value: { [string]: unknown } = {
		matchId = matchId or MATCH_ID,
		revision = revision,
		state = state,
		participants = participants or {},
	}
	if deadlineServerTime ~= nil then
		value.deadlineServerTime = deadlineServerTime
	end
	return value
end

local function readySnapshot(
	revision: number,
	participants: { { [string]: unknown } }?,
	deadlineServerTime: number?
): { [string]: unknown }
	return snapshot(revision, "ReadyCheck", participants, nil, deadlineServerTime or 100)
end

local function expectSuccess(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return result.value
end

local function expectFailure(assertions: Assertions, result: any, code: string): any
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	assertions.isTrue(table.isfrozen(result.error))
	assertions.equal(result.error.code, code)
	local fieldCount = 0
	for fieldName in result.error do
		fieldCount += 1
		assertions.equal(fieldName, "code")
	end
	assertions.equal(fieldCount, 1)
	return result.error
end

local function newModel(assertions: Assertions, localUserId: number?): any
	local model = expectSuccess(assertions, MatchReadyViewModel.new(localUserId or 2))
	assertions.isTrue(table.isfrozen(model))
	return model
end

local function render(assertions: Assertions, model: any, serverTime: unknown): any
	local state = expectSuccess(assertions, model:getRenderState(serverTime))
	assertions.isTrue(table.isfrozen(state))
	assertions.isTrue(table.isfrozen(state.participantRows))
	for _, row in state.participantRows do
		assertions.isTrue(table.isfrozen(row))
	end
	return state
end

return TestHarness.suite("match ready pure view model", {
	TestHarness.case("validates the injected local UserId without retaining rejected inputs", function(assertions)
		for _, invalid in { 0, 1.5, math.huge, -math.huge, 0 / 0, 9_007_199_254_740_992, "2" } do
			expectFailure(assertions, MatchReadyViewModel.new(invalid), "INVALID_LOCAL_USER_ID")
		end
		local studioModel = newModel(assertions, -9_007_199_254_740_991)
		local state = render(assertions, studioModel, nil)
		assertions.isNil(state.matchId)
		assertions.isNil(state.revision)
		assertions.isNil(state.matchState)
		assertions.equal(#state.participantRows, 0)
		assertions.equal(state.requestState, "Idle")
		assertions.isFalse(state.readyAvailable)
		assertions.isFalse(state.countdownKnown)
		assertions.isNil(state.countdownSeconds)
	end),

	TestHarness.case("orders initial event and recovery response snapshots by strict revision", function(assertions)
		local responseFirst = newModel(assertions)
		assertions.equal(expectSuccess(assertions, responseFirst:applySnapshot(readySnapshot(1, {}))).kind, "Applied")
		assertions.equal(expectSuccess(assertions, responseFirst:applySnapshot(readySnapshot(2, {}))).kind, "Applied")
		assertions.equal(expectSuccess(assertions, responseFirst:applySnapshot(readySnapshot(1, {}))).kind, "Stale")
		assertions.equal(
			expectSuccess(assertions, responseFirst:applySnapshot(snapshot(2, "PreWave", {}))).kind,
			"Duplicate"
		)
		local responseFirstState = render(assertions, responseFirst, 50)
		assertions.equal(responseFirstState.revision, 2)
		assertions.equal(responseFirstState.matchState, "ReadyCheck")

		local eventFirst = newModel(assertions)
		assertions.equal(expectSuccess(assertions, eventFirst:applySnapshot(readySnapshot(2, {}))).kind, "Applied")
		assertions.equal(expectSuccess(assertions, eventFirst:applySnapshot(readySnapshot(1, {}))).kind, "Stale")
		assertions.equal(render(assertions, eventFirst, 50).revision, 2)
	end),

	TestHarness.case("locks the first MatchId and ignores a wrong identity without mutation", function(assertions)
		local model = newModel(assertions)
		expectSuccess(assertions, model:applySnapshot(readySnapshot(3, { participant(2, "Active", false) })))
		local wrong = snapshot(99, "PreWave", {}, OTHER_MATCH_ID, nil)
		assertions.equal(expectSuccess(assertions, model:applySnapshot(wrong)).kind, "WrongMatch")
		local unchanged = render(assertions, model, 60)
		assertions.equal(unchanged.matchId, MATCH_ID)
		assertions.equal(unchanged.revision, 3)
		assertions.equal(unchanged.matchState, "ReadyCheck")
		assertions.equal(unchanged.requestState, "Idle")
	end),

	TestHarness.case("validates detaches and deeply freezes snapshot-derived render state", function(assertions)
		local model = newModel(assertions)
		local authoredParticipant = participant(2, "Active", false)
		local authoredParticipants = { authoredParticipant }
		local authored = readySnapshot(1, authoredParticipants)
		expectSuccess(assertions, model:applySnapshot(authored))

		authored.revision = 50
		authoredParticipant.userId = 8
		authoredParticipant.state = "Returned"
		local state = render(assertions, model, 60)
		assertions.equal(state.revision, 1)
		assertions.equal(state.participantRows[1].label, "Player 1")
		assertions.equal(state.participantRows[1].status, "Waiting")
		assertions.isTrue(state.participantRows[1].isLocal)
		assertions.isFalse(pcall(function()
			(state :: any).revision = 2
		end))
		assertions.isFalse(pcall(function()
			(state.participantRows :: any)[2] = state.participantRows[1]
		end))
		assertions.isFalse(pcall(function()
			(state.participantRows[1] :: any).label = "Private name"
		end))

		local invalid = readySnapshot(2, { participant(2, "Returned", true) })
		expectFailure(assertions, model:applySnapshot(invalid), "INVALID_SNAPSHOT")
		assertions.equal(render(assertions, model, 60).revision, 1)
	end),

	TestHarness.case("renders deterministic anonymous labels and every participant status", function(assertions)
		local model = newModel(assertions, 20)
		expectSuccess(
			assertions,
			model:applySnapshot(readySnapshot(1, {
				participant(-5, "Active", true),
				participant(10, "Disconnected", false),
				participant(20, "Returned", false),
				participant(30, "Spectator", false),
			}))
		)
		local state = render(assertions, model, 50)
		local expectedLabels = { "Player 1", "Player 2", "Player 3", "Player 4" }
		local expectedStatuses = { "Ready", "Disconnected", "Returned", "Spectator" }
		for index = 1, 4 do
			assertions.equal(state.participantRows[index].label, expectedLabels[index])
			assertions.equal(state.participantRows[index].status, expectedStatuses[index])
			assertions.equal(state.participantRows[index].isLocal, index == 3)
		end
		assertions.isFalse(state.readyAvailable)
	end),

	TestHarness.case(
		"disables a duplicate local Ready while Pending and accepts the authoritative revision",
		function(assertions)
			local model = newModel(assertions)
			expectFailure(assertions, model:beginReady(), "NO_SNAPSHOT")
			expectSuccess(assertions, model:applySnapshot(readySnapshot(7, { participant(2, "Active", false) })))
			assertions.isTrue(render(assertions, model, 50).readyAvailable)

			local submission = expectSuccess(assertions, model:beginReady())
			assertions.isTrue(table.isfrozen(submission))
			assertions.equal(submission.matchId, MATCH_ID)
			assertions.equal(submission.observedRevision, 7)
			local pending = render(assertions, model, 50)
			assertions.equal(pending.requestState, "Pending")
			assertions.isFalse(pending.readyAvailable)
			expectFailure(assertions, model:beginReady(), "REQUEST_PENDING")

			expectSuccess(assertions, model:applySnapshot(readySnapshot(8, { participant(2, "Active", true) })))
			local accepted = render(assertions, model, 51)
			assertions.equal(accepted.requestState, "Accepted")
			assertions.isFalse(accepted.readyAvailable)
			assertions.equal(expectSuccess(assertions, model:acceptReady()), "Accepted")
		end
	),

	TestHarness.case("presents allowlisted rejection and permits a safe retry only when eligible", function(assertions)
		local model = newModel(assertions)
		expectSuccess(assertions, model:applySnapshot(readySnapshot(1, { participant(2, "Active", false) })))
		expectFailure(assertions, model:rejectReady("RATE_LIMITED"), "INVALID_REQUEST_STATE")
		expectSuccess(assertions, model:beginReady())
		expectFailure(assertions, model:rejectReady("PRIVATE_CODE"), "INVALID_PUBLIC_ERROR")
		assertions.equal(expectSuccess(assertions, model:rejectReady("RATE_LIMITED")), "Rejected")
		local rejected = render(assertions, model, 50)
		assertions.equal(rejected.requestState, "Rejected")
		assertions.equal(rejected.rejectionCode, "RATE_LIMITED")
		assertions.isTrue(rejected.readyAvailable)
		assertions.equal(expectSuccess(assertions, model:rejectReady("RATE_LIMITED")), "Rejected")
		expectSuccess(assertions, model:beginReady())
		assertions.equal(render(assertions, model, 51).requestState, "Pending")
	end),

	TestHarness.case("presents an authoritative state change over a pending terminal callback", function(assertions)
		local idleModel = newModel(assertions)
		expectSuccess(assertions, idleModel:applySnapshot(snapshot(1, "Loading", {})))
		expectSuccess(assertions, idleModel:applySnapshot(readySnapshot(2, {})))
		assertions.equal(render(assertions, idleModel, 50).requestState, "Idle")

		local model = newModel(assertions)
		expectSuccess(assertions, model:applySnapshot(readySnapshot(1, { participant(2, "Active", false) })))
		expectSuccess(assertions, model:beginReady())
		expectSuccess(assertions, model:applySnapshot(snapshot(2, "PreWave", { participant(2, "Active", true) })))
		local changed = render(assertions, model, 50)
		assertions.equal(changed.requestState, "StateChanged")
		assertions.isFalse(changed.readyAvailable)
		assertions.isFalse(changed.countdownKnown)
		assertions.equal(expectSuccess(assertions, model:acceptReady()), "StateChanged")
		assertions.equal(expectSuccess(assertions, model:rejectReady("STALE_REQUEST")), "StateChanged")
	end),

	TestHarness.case("projects only a monotonic finite authoritative countdown", function(assertions)
		local model = newModel(assertions)
		expectSuccess(assertions, model:applySnapshot(readySnapshot(1, {}, 100.2)))

		local unknown = render(assertions, model, nil)
		assertions.isFalse(unknown.countdownKnown)
		assertions.isNil(unknown.countdownSeconds)
		for _, invalid in { -1, math.huge, -math.huge, 0 / 0, "50" } do
			local invalidProjection = render(assertions, model, invalid)
			assertions.isFalse(invalidProjection.countdownKnown)
			assertions.isNil(invalidProjection.countdownSeconds)
		end

		local first = render(assertions, model, 55.2)
		assertions.isTrue(first.countdownKnown)
		assertions.equal(first.countdownSeconds, 45)
		assertions.equal(render(assertions, model, 99.21).countdownSeconds, 1)
		assertions.equal(render(assertions, model, 100.2).countdownSeconds, 0)
		assertions.equal(render(assertions, model, 101).countdownSeconds, 0)

		local backwards = render(assertions, model, 100.99)
		assertions.isFalse(backwards.countdownKnown)
		assertions.isNil(backwards.countdownSeconds)
		assertions.equal(render(assertions, model, 102).countdownSeconds, 0)
	end),

	TestHarness.case(
		"excludes disconnected returned spectator ready and missing local participants",
		function(assertions)
			for _, participantState in { "Disconnected", "Returned", "Spectator" } do
				local model = newModel(assertions)
				expectSuccess(
					assertions,
					model:applySnapshot(readySnapshot(1, { participant(2, participantState, false) }))
				)
				assertions.isFalse(render(assertions, model, 50).readyAvailable)
				expectFailure(assertions, model:beginReady(), "NOT_ELIGIBLE")
			end
			local missing = newModel(assertions)
			expectSuccess(assertions, missing:applySnapshot(readySnapshot(1, { participant(3, "Active", false) })))
			assertions.isFalse(render(assertions, missing, 50).readyAvailable)
			expectFailure(assertions, missing:beginReady(), "NOT_ELIGIBLE")
		end
	),

	TestHarness.case("cleans idempotently and rejects every post-clean operation", function(assertions)
		local model = newModel(assertions)
		expectSuccess(assertions, model:applySnapshot(readySnapshot(1, { participant(2, "Active", false) })))
		expectSuccess(assertions, model:beginReady())
		assertions.isTrue(expectSuccess(assertions, model:cleanup()))
		assertions.isTrue(expectSuccess(assertions, model:cleanup()))
		expectFailure(assertions, model:getRenderState(50), "CLEANED_UP")
		expectFailure(assertions, model:applySnapshot(readySnapshot(2, {})), "CLEANED_UP")
		expectFailure(assertions, model:beginReady(), "CLEANED_UP")
		expectFailure(assertions, model:acceptReady(), "CLEANED_UP")
		expectFailure(assertions, model:rejectReady("RATE_LIMITED"), "CLEANED_UP")
	end),
})
