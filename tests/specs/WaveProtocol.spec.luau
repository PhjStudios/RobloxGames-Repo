--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Shared = game:GetService("ReplicatedStorage").Shared
local PayloadValidation = require(Shared.network.PayloadValidation)
local Validation = require(Shared.util.Validation)
local WaveProtocol = require(Shared.match.WaveProtocol)

type Assertions = TestHarness.Assertions

local function counts(
	totalScheduled: number,
	pending: number,
	spawned: number,
	alive: number,
	leaked: number,
	otherwiseResolved: number
): { [string]: any }
	return {
		totalScheduled = totalScheduled,
		pending = pending,
		spawned = spawned,
		alive = alive,
		leaked = leaked,
		otherwiseResolved = otherwiseResolved,
	}
end

local function skipState(
	available: boolean,
	activeParticipantCount: number,
	yesVoteCount: number,
	requiredVoteCount: number,
	quorumPending: boolean
): { [string]: any }
	return {
		available = available,
		activeParticipantCount = activeParticipantCount,
		yesVoteCount = yesVoteCount,
		requiredVoteCount = requiredVoteCount,
		quorumPending = quorumPending,
	}
end

local function runningSnapshot(): { [string]: any }
	return {
		matchId = "match:phase11-protocol",
		enemyEpoch = 1,
		mapId = "map:phase11-protocol",
		difficultyId = "difficulty:phase11-protocol",
		state = "Running",
		waveRevision = 7,
		currentWaveNumber = 2,
		totalWaves = 4,
		currentWaveId = "wave:phase11-protocol-2",
		bossKind = "MiniBoss",
		timerPhase = "WaveDeadline",
		waveStartedServerTime = 100,
		deadlineServerTime = 112,
		intermissionEndsServerTime = 0,
		skipAvailableServerTime = 102,
		finiteCompleteServerTime = 0,
		currentCounts = counts(3, 1, 2, 1, 1, 0),
		aggregateCounts = counts(8, 2, 6, 2, 2, 2),
		skipState = skipState(true, 4, 2, 3, false),
	}
end

local function expectSnapshotSuccess(assertions: Assertions, value: unknown): WaveProtocol.WaveSnapshot
	local result = WaveProtocol.validateWaveSnapshot(value)
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local snapshot = (result :: any).value :: WaveProtocol.WaveSnapshot
	assertions.isTrue(table.isfrozen(snapshot))
	assertions.isTrue(table.isfrozen(snapshot.currentCounts))
	assertions.isTrue(table.isfrozen(snapshot.aggregateCounts))
	assertions.isTrue(table.isfrozen(snapshot.skipState))
	return snapshot
end

local function expectSnapshotFailure(
	assertions: Assertions,
	value: unknown,
	code: Validation.Code?,
	path: string?
): Validation.Issue
	local result = WaveProtocol.validateWaveSnapshot(value)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local issue = (result :: any).error :: Validation.Issue
	assertions.isTrue(table.isfrozen(issue))
	assertions.isTrue(table.isfrozen(issue.pathSegments))
	if code ~= nil then
		assertions.equal(issue.code, code)
	end
	if path ~= nil then
		assertions.equal(issue.path, path)
	end
	return issue
end

return TestHarness.suite("wave protocol wire contract", {
	TestHarness.case("exports exact endpoints bounds and authenticated schemas", function(assertions)
		assertions.equal(WaveProtocol.GET_WAVE_SNAPSHOT_ENDPOINT, "GetWaveSnapshot")
		assertions.equal(WaveProtocol.SUBMIT_SKIP_VOTE_ENDPOINT, "SubmitSkipVote")
		assertions.equal(WaveProtocol.WAVE_REPLICATION_ENDPOINT, "WaveReplication")
		assertions.equal(WaveProtocol.MAX_ENEMY_EPOCH, 4_096)
		assertions.equal(WaveProtocol.MAX_TOTAL_WAVES, 1_000)
		assertions.equal(WaveProtocol.MAX_TOTAL_SCHEDULED, 4_096)
		assertions.equal(WaveProtocol.MAX_ACTIVE_PARTICIPANTS, 4)
		assertions.equal(WaveProtocol.MAX_BROADCAST_RECIPIENTS, 4)
		assertions.equal(WaveProtocol.MAX_WAVE_REVISION, Validation.MAX_SAFE_INTEGER)
		assertions.isTrue(table.isfrozen(WaveProtocol))
		assertions.isTrue(PayloadValidation.isSchema(WaveProtocol.GetWaveSnapshotPayloadSchema))
		assertions.isTrue(PayloadValidation.isSchema(WaveProtocol.SubmitSkipVotePayloadSchema))
		assertions.isTrue(PayloadValidation.isSchema(WaveProtocol.WaveSnapshotSchema))
	end),

	TestHarness.case("accepts only exact detached Get and Submit payloads", function(assertions)
		local empty = {}
		local getResult = WaveProtocol.GetWaveSnapshotPayloadSchema:validate(empty)
		assertions.isTrue(getResult.ok)
		assertions.notEqual((getResult :: any).value, empty)
		assertions.isTrue(table.isfrozen((getResult :: any).value))
		assertions.isFalse(WaveProtocol.GetWaveSnapshotPayloadSchema:validate({ extra = true }).ok)
		assertions.isFalse(WaveProtocol.GetWaveSnapshotPayloadSchema:validate(setmetatable({}, {})).ok)
		assertions.isFalse(WaveProtocol.GetWaveSnapshotPayloadSchema:validate(Instance.new("Folder")).ok)

		local authored = {
			matchId = "match:phase11-protocol",
			waveNumber = 4,
		}
		local voteResult = WaveProtocol.SubmitSkipVotePayloadSchema:validate(authored)
		assertions.isTrue(voteResult.ok)
		local canonical = (voteResult :: any).value
		assertions.notEqual(canonical, authored)
		assertions.isTrue(table.isfrozen(canonical))
		assertions.equal(canonical.matchId, "match:phase11-protocol")
		assertions.equal(canonical.waveNumber, 4)
		authored.matchId = "match:changed"
		authored.waveNumber = 2
		assertions.equal(canonical.matchId, "match:phase11-protocol")
		assertions.equal(canonical.waveNumber, 4)

		for _, invalid in
			{
				{ matchId = "map:phase11-protocol", waveNumber = 1 },
				{ matchId = "match:phase11-protocol", waveNumber = 0 },
				{ matchId = "match:phase11-protocol", waveNumber = 1.5 },
				{ matchId = "match:phase11-protocol", waveNumber = 1_001 },
				{ matchId = "match:phase11-protocol", waveNumber = 1, voterUserId = 4 },
			}
		do
			assertions.isFalse(WaveProtocol.SubmitSkipVotePayloadSchema:validate(invalid).ok)
		end
	end),

	TestHarness.case("detaches and deeply freezes every full snapshot component", function(assertions)
		local authored = runningSnapshot()
		local authoredCurrent = authored.currentCounts
		local authoredAggregate = authored.aggregateCounts
		local authoredSkip = authored.skipState
		local first = expectSnapshotSuccess(assertions, authored)
		local second = expectSnapshotSuccess(assertions, authored)
		assertions.notEqual(first, authored)
		assertions.notEqual(first, second)
		assertions.notEqual(first.currentCounts, authoredCurrent)
		assertions.notEqual(first.aggregateCounts, authoredAggregate)
		assertions.notEqual(first.skipState, authoredSkip)
		assertions.notEqual(first.currentCounts, second.currentCounts)
		assertions.notEqual(first.skipState, second.skipState)

		authored.waveRevision = 99
		authoredCurrent.alive = 0
		authoredAggregate.spawned = 0
		authoredSkip.yesVoteCount = 4
		assertions.equal(first.waveRevision, 7)
		assertions.equal(first.currentCounts.alive, 1)
		assertions.equal(first.aggregateCounts.spawned, 6)
		assertions.equal(first.skipState.yesVoteCount, 2)
		assertions.isFalse(pcall(function()
			(first.currentCounts :: any).pending = 0
		end))
		assertions.isFalse(pcall(function()
			(first.skipState :: any).available = false
		end))
	end),

	TestHarness.case("accepts each exact state timer and boss variant", function(assertions)
		for _, bossKind in { "None", "MiniBoss", "Boss" } do
			local value = runningSnapshot()
			value.bossKind = bossKind
			expectSnapshotSuccess(assertions, value)
		end

		local intermission = runningSnapshot()
		intermission.state = "Intermission"
		intermission.timerPhase = "EarlyClearIntermission"
		intermission.intermissionEndsServerTime = 115
		intermission.skipAvailableServerTime = 0
		intermission.currentCounts = counts(3, 0, 3, 0, 1, 2)
		intermission.aggregateCounts = counts(8, 0, 8, 0, 3, 5)
		intermission.skipState = skipState(false, 3, 1, 2, false)
		expectSnapshotSuccess(assertions, intermission)

		local postDeadline = runningSnapshot()
		postDeadline.currentWaveNumber = 4
		postDeadline.currentWaveId = "wave:phase11-protocol-4"
		postDeadline.timerPhase = "PostDeadline"
		postDeadline.skipAvailableServerTime = 0
		postDeadline.skipState = skipState(false, 4, 0, 3, false)
		expectSnapshotSuccess(assertions, postDeadline)

		local complete = runningSnapshot()
		complete.state = "FiniteComplete"
		complete.timerPhase = "None"
		complete.currentWaveNumber = 4
		complete.currentWaveId = "wave:phase11-protocol-4"
		complete.skipAvailableServerTime = 0
		complete.finiteCompleteServerTime = 108
		complete.currentCounts = counts(3, 0, 3, 0, 1, 2)
		complete.aggregateCounts = counts(8, 0, 8, 0, 3, 5)
		complete.skipState = skipState(false, 0, 0, 0, false)
		expectSnapshotSuccess(assertions, complete)

		for _, terminalState in { "DefeatClosed", "Faulted" } do
			local terminal = runningSnapshot()
			terminal.state = terminalState
			terminal.timerPhase = "None"
			terminal.skipAvailableServerTime = 0
			terminal.skipState = skipState(false, 4, 2, 3, false)
			expectSnapshotSuccess(assertions, terminal)
		end
	end),

	TestHarness.case("enforces exact IDs enumerations bounds and record shapes", function(assertions)
		local cases: { { field: string, value: any } } = {
			{ field = "matchId", value = "map:phase11-protocol" },
			{ field = "enemyEpoch", value = 0 },
			{ field = "enemyEpoch", value = 4_097 },
			{ field = "mapId", value = "match:phase11-protocol" },
			{ field = "difficultyId", value = "wave:phase11-protocol" },
			{ field = "state", value = "Uninitialized" },
			{ field = "state", value = "Cleaned" },
			{ field = "waveRevision", value = 0 },
			{ field = "waveRevision", value = 1.5 },
			{ field = "waveRevision", value = Validation.MAX_SAFE_INTEGER + 1 },
			{ field = "currentWaveNumber", value = 0 },
			{ field = "totalWaves", value = 1_001 },
			{ field = "currentWaveId", value = "enemy:phase11-protocol" },
			{ field = "bossKind", value = "MegaBoss" },
			{ field = "timerPhase", value = "Countdown" },
			{ field = "deadlineServerTime", value = math.huge },
			{ field = "waveStartedServerTime", value = -1 },
		}
		for _, fixture in cases do
			local value = runningSnapshot()
			value[fixture.field] = fixture.value
			expectSnapshotFailure(assertions, value, nil, nil)
		end

		local missing = runningSnapshot()
		missing.skipState = nil
		expectSnapshotFailure(assertions, missing, "MISSING_FIELD", "payload.skipState")
		local extra = runningSnapshot()
		extra.rewardClass = "Milestone"
		expectSnapshotFailure(assertions, extra, "UNKNOWN_FIELD", "payload")
		local nestedExtra = runningSnapshot()
		nestedExtra.skipState.voterUserIds = { 1, 2 }
		expectSnapshotFailure(assertions, nestedExtra, "UNKNOWN_FIELD", "payload.skipState")
		expectSnapshotFailure(assertions, setmetatable(runningSnapshot(), {}), "INVALID_TABLE", "payload")
	end),

	TestHarness.case("enforces current and aggregate counter equations and containment", function(assertions)
		local invalidFixtures = {
			{ scope = "currentCounts", field = "pending", value = 2 },
			{ scope = "currentCounts", field = "alive", value = 2 },
			{ scope = "currentCounts", field = "leaked", value = 3 },
			{ scope = "aggregateCounts", field = "pending", value = 3 },
			{ scope = "aggregateCounts", field = "otherwiseResolved", value = 5 },
			{ scope = "aggregateCounts", field = "totalScheduled", value = 4 },
		}
		for _, fixture in invalidFixtures do
			local value = runningSnapshot()
			value[fixture.scope][fixture.field] = fixture.value
			expectSnapshotFailure(assertions, value, "INVALID_TOTAL", nil)
		end

		for _, invalidCount in { -1, 4_097, 1.5, math.huge, 0 / 0 } do
			local value = runningSnapshot()
			value.currentCounts.totalScheduled = invalidCount
			expectSnapshotFailure(assertions, value, nil, nil)
		end

		local intermissionPending = runningSnapshot()
		intermissionPending.state = "Intermission"
		intermissionPending.timerPhase = "EarlyClearIntermission"
		intermissionPending.intermissionEndsServerTime = 115
		intermissionPending.skipAvailableServerTime = 0
		intermissionPending.skipState = skipState(false, 4, 2, 3, false)
		expectSnapshotFailure(assertions, intermissionPending, "INVALID_REFERENCE", "payload.aggregateCounts")

		local completeAlive = runningSnapshot()
		completeAlive.state = "FiniteComplete"
		completeAlive.timerPhase = "None"
		completeAlive.currentWaveNumber = 4
		completeAlive.skipAvailableServerTime = 0
		completeAlive.finiteCompleteServerTime = 108
		completeAlive.skipState = skipState(false, 4, 2, 3, false)
		expectSnapshotFailure(assertions, completeAlive, "INVALID_REFERENCE", "payload.aggregateCounts")
	end),

	TestHarness.case("enforces wave timer state and zero-sentinel relationships", function(assertions)
		local reversedDeadline = runningSnapshot()
		reversedDeadline.deadlineServerTime = 100
		expectSnapshotFailure(assertions, reversedDeadline, "INVALID_ORDER", "payload.deadlineServerTime")

		local wrongRunningPhase = runningSnapshot()
		wrongRunningPhase.timerPhase = "None"
		expectSnapshotFailure(assertions, wrongRunningPhase, "INVALID_REFERENCE", "payload.timerPhase")

		local wrongIntermission = runningSnapshot()
		wrongIntermission.state = "Intermission"
		wrongIntermission.skipAvailableServerTime = 0
		wrongIntermission.currentCounts = counts(3, 0, 3, 0, 1, 2)
		wrongIntermission.aggregateCounts = counts(8, 0, 8, 0, 3, 5)
		expectSnapshotFailure(assertions, wrongIntermission, "INVALID_REFERENCE", "payload.timerPhase")

		local finalIntermission = runningSnapshot()
		finalIntermission.state = "Intermission"
		finalIntermission.timerPhase = "EarlyClearIntermission"
		finalIntermission.currentWaveNumber = 4
		finalIntermission.intermissionEndsServerTime = 115
		finalIntermission.skipAvailableServerTime = 0
		finalIntermission.currentCounts = counts(3, 0, 3, 0, 1, 2)
		finalIntermission.aggregateCounts = counts(8, 0, 8, 0, 3, 5)
		finalIntermission.skipState = skipState(false, 4, 2, 3, false)
		expectSnapshotFailure(assertions, finalIntermission, "INVALID_REFERENCE", "payload.state")

		local earlyIntermissionEnd = runningSnapshot()
		earlyIntermissionEnd.state = "Intermission"
		earlyIntermissionEnd.timerPhase = "EarlyClearIntermission"
		earlyIntermissionEnd.intermissionEndsServerTime = 99
		earlyIntermissionEnd.skipAvailableServerTime = 0
		earlyIntermissionEnd.currentCounts = counts(3, 0, 3, 0, 1, 2)
		earlyIntermissionEnd.aggregateCounts = counts(8, 0, 8, 0, 3, 5)
		earlyIntermissionEnd.skipState = skipState(false, 4, 2, 3, false)
		expectSnapshotFailure(assertions, earlyIntermissionEnd, "INVALID_ORDER", "payload.intermissionEndsServerTime")

		local strayIntermission = runningSnapshot()
		strayIntermission.intermissionEndsServerTime = 115
		expectSnapshotFailure(assertions, strayIntermission, "INVALID_REFERENCE", "payload.intermissionEndsServerTime")

		local earlySkipTime = runningSnapshot()
		earlySkipTime.skipAvailableServerTime = 99
		expectSnapshotFailure(assertions, earlySkipTime, "INVALID_ORDER", "payload.skipAvailableServerTime")

		local postDeadlineNonfinal = runningSnapshot()
		postDeadlineNonfinal.timerPhase = "PostDeadline"
		postDeadlineNonfinal.skipAvailableServerTime = 0
		postDeadlineNonfinal.skipState = skipState(false, 4, 2, 3, false)
		expectSnapshotFailure(assertions, postDeadlineNonfinal, "INVALID_REFERENCE", "payload.timerPhase")

		local completionTooEarly = runningSnapshot()
		completionTooEarly.state = "FiniteComplete"
		completionTooEarly.timerPhase = "None"
		completionTooEarly.currentWaveNumber = 4
		completionTooEarly.skipAvailableServerTime = 0
		completionTooEarly.finiteCompleteServerTime = 99
		completionTooEarly.currentCounts = counts(3, 0, 3, 0, 1, 2)
		completionTooEarly.aggregateCounts = counts(8, 0, 8, 0, 3, 5)
		completionTooEarly.skipState = skipState(false, 0, 0, 0, false)
		expectSnapshotFailure(assertions, completionTooEarly, "INVALID_ORDER", "payload.finiteCompleteServerTime")

		local strayCompletion = runningSnapshot()
		strayCompletion.finiteCompleteServerTime = 108
		expectSnapshotFailure(assertions, strayCompletion, "INVALID_REFERENCE", "payload.finiteCompleteServerTime")
	end),

	TestHarness.case("enforces the bounded strict-majority skip state", function(assertions)
		for activeCount = 0, 4 do
			local value = runningSnapshot()
			local expectedRequired = if activeCount == 0 then 0 else math.floor(activeCount / 2) + 1
			value.skipState = skipState(activeCount > 0, activeCount, 0, expectedRequired, false)
			expectSnapshotSuccess(assertions, value)
		end

		local tooManyVotes = runningSnapshot()
		tooManyVotes.skipState = skipState(true, 2, 3, 2, true)
		expectSnapshotFailure(assertions, tooManyVotes, "INVALID_TOTAL", "payload.skipState.yesVoteCount")

		local wrongThreshold = runningSnapshot()
		wrongThreshold.skipState = skipState(true, 4, 2, 2, true)
		expectSnapshotFailure(assertions, wrongThreshold, "INVALID_TOTAL", "payload.skipState.requiredVoteCount")

		local quorum = runningSnapshot()
		quorum.skipState = skipState(true, 4, 3, 3, true)
		expectSnapshotSuccess(assertions, quorum)

		local falseQuorum = runningSnapshot()
		falseQuorum.skipState = skipState(true, 4, 2, 3, true)
		expectSnapshotFailure(assertions, falseQuorum, "INVALID_REFERENCE", "payload.skipState.quorumPending")

		local unavailableQuorum = runningSnapshot()
		unavailableQuorum.skipState = skipState(false, 4, 3, 3, true)
		expectSnapshotFailure(assertions, unavailableQuorum, "INVALID_REFERENCE", "payload.skipState.quorumPending")

		local finalAvailable = runningSnapshot()
		finalAvailable.currentWaveNumber = 4
		finalAvailable.skipAvailableServerTime = 0
		expectSnapshotFailure(assertions, finalAvailable, "INVALID_REFERENCE", "payload.skipState.available")

		local impossibleWindow = runningSnapshot()
		impossibleWindow.skipAvailableServerTime = 112
		expectSnapshotFailure(assertions, impossibleWindow, "INVALID_ORDER", "payload.skipAvailableServerTime")
	end),

	TestHarness.case("rejects hostile nested tables and repeated identities", function(assertions)
		local currentMetatable = runningSnapshot()
		setmetatable(currentMetatable.currentCounts, {})
		expectSnapshotFailure(assertions, currentMetatable, "INVALID_TABLE", "payload.currentCounts")

		local skipMetatable = runningSnapshot()
		setmetatable(skipMetatable.skipState, {})
		expectSnapshotFailure(assertions, skipMetatable, "INVALID_TABLE", "payload.skipState")

		local repeated = runningSnapshot()
		repeated.aggregateCounts = repeated.currentCounts
		expectSnapshotFailure(assertions, repeated, "INVALID_TABLE", "payload.currentCounts")
		expectSnapshotFailure(assertions, Instance.new("Folder"), "INVALID_TYPE", "payload")
	end),

	TestHarness.case("returns static privacy-safe failures", function(assertions)
		local privateValue = {
			secret = "PRIVATE_WAVE_PROTOCOL_SENTINEL",
		}
		local invalid = runningSnapshot()
		invalid.private = privateValue
		local validationIssue = expectSnapshotFailure(assertions, invalid, "UNKNOWN_FIELD", "payload")
		for _, fieldName in { "code", "path", "message" } do
			assertions.isNil(string.find((validationIssue :: any)[fieldName], privateValue.secret, 1, true))
		end
	end),
})
