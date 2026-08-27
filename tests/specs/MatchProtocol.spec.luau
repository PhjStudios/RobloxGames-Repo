--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Shared = game:GetService("ReplicatedStorage").Shared
local MatchProtocol = require(Shared.match.MatchProtocol)
local PayloadValidation = require(Shared.network.PayloadValidation)
local Validation = require(Shared.util.Validation)

type Assertions = TestHarness.Assertions

local function participant(userId: number, state: string, ready: boolean): { [string]: unknown }
	return {
		userId = userId,
		state = state,
		ready = ready,
	}
end

local function snapshot(
	state: string,
	deadlineServerTime: number?,
	participants: { { [string]: unknown } }?
): { [string]: unknown }
	local value: { [string]: unknown } = {
		matchId = "match:phase08-test",
		revision = 1,
		state = state,
		participants = participants or {},
	}
	if deadlineServerTime ~= nil then
		value.deadlineServerTime = deadlineServerTime
	end
	return value
end

local function expectSchemaSuccess(assertions: Assertions, schema: any, value: unknown): any
	local result = schema:validate(value)
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return result.value
end

local function expectSchemaFailure(assertions: Assertions, schema: any, value: unknown): any
	local result = schema:validate(value)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	assertions.isTrue(table.isfrozen(result.error))
	return result.error
end

local function expectSnapshotSuccess(assertions: Assertions, value: unknown): MatchProtocol.MatchSnapshot
	local result = MatchProtocol.validateMatchSnapshot(value)
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return (result :: any).value :: MatchProtocol.MatchSnapshot
end

local function expectSnapshotFailure(assertions: Assertions, value: unknown, code: Validation.Code?, path: string?): any
	local result = MatchProtocol.validateMatchSnapshot(value)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local issue = (result :: any).error
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

local function graphContains(root: unknown, target: unknown, seen: { [any]: boolean }?): boolean
	if root == target then
		return true
	end
	if type(root) ~= "table" then
		return false
	end
	local visited = seen or {}
	if rawget(visited, root) == true then
		return false
	end
	rawset(visited, root, true)
	for key, value in next, root :: any do
		if graphContains(key, target, visited) or graphContains(value, target, visited) then
			return true
		end
	end
	return false
end

return TestHarness.suite("match protocol wire contract", {
	TestHarness.case("exports fixed endpoint constants and authentic strict schemas", function(assertions)
		assertions.equal(MatchProtocol.GET_MATCH_SNAPSHOT_ENDPOINT, "GetMatchSnapshot")
		assertions.equal(MatchProtocol.SUBMIT_READY_ENDPOINT, "SubmitReady")
		assertions.equal(MatchProtocol.MATCH_SNAPSHOT_ENDPOINT, "MatchSnapshot")
		assertions.equal(MatchProtocol.READY_CHECK_SECONDS, 45)
		assertions.isTrue(table.isfrozen(MatchProtocol))
		assertions.isTrue(PayloadValidation.isSchema(MatchProtocol.GetMatchSnapshotPayloadSchema))
		assertions.isTrue(PayloadValidation.isSchema(MatchProtocol.SubmitReadyPayloadSchema))
		assertions.isTrue(PayloadValidation.isSchema(MatchProtocol.MatchSnapshotSchema))
		assertions.isTrue(table.isfrozen(MatchProtocol.GetMatchSnapshotPayloadSchema))
		assertions.isTrue(table.isfrozen(MatchProtocol.SubmitReadyPayloadSchema))
		assertions.isTrue(table.isfrozen(MatchProtocol.MatchSnapshotSchema))
	end),

	TestHarness.case("validates the exact empty snapshot-recovery payload", function(assertions)
		local authored = {}
		local canonical = expectSchemaSuccess(assertions, MatchProtocol.GetMatchSnapshotPayloadSchema, authored)
		assertions.isTrue(table.isfrozen(canonical))
		assertions.notEqual(canonical, authored)
		expectSchemaFailure(assertions, MatchProtocol.GetMatchSnapshotPayloadSchema, { extra = true })
		expectSchemaFailure(assertions, MatchProtocol.GetMatchSnapshotPayloadSchema, setmetatable({}, {}))
		expectSchemaFailure(assertions, MatchProtocol.GetMatchSnapshotPayloadSchema, Instance.new("Folder"))
	end),

	TestHarness.case("validates and detaches the minimum SubmitReady payload", function(assertions)
		local authored = {
			matchId = "match:phase08-test",
			observedRevision = 7,
		}
		local canonical = expectSchemaSuccess(assertions, MatchProtocol.SubmitReadyPayloadSchema, authored)
		assertions.isTrue(table.isfrozen(canonical))
		assertions.notEqual(canonical, authored)
		assertions.equal(canonical.matchId, "match:phase08-test")
		assertions.equal(canonical.observedRevision, 7)

		authored.matchId = "match:changed"
		authored.observedRevision = 8
		assertions.equal(canonical.matchId, "match:phase08-test")
		assertions.equal(canonical.observedRevision, 7)

		for _, invalid in
			{
				{ matchId = "map:phase08-test", observedRevision = 1 },
				{ matchId = "match:phase08-test", observedRevision = 0 },
				{ matchId = "match:phase08-test", observedRevision = 1.5 },
				{ matchId = "match:phase08-test", observedRevision = math.huge },
				{ matchId = "match:phase08-test", observedRevision = 9_007_199_254_740_992 },
				{ matchId = "match:phase08-test", observedRevision = 1, extra = true },
			}
		do
			expectSchemaFailure(assertions, MatchProtocol.SubmitReadyPayloadSchema, invalid)
		end
		expectSchemaFailure(
			assertions,
			MatchProtocol.SubmitReadyPayloadSchema,
			setmetatable({ matchId = "match:phase08-test", observedRevision = 1 }, {})
		)
	end),

	TestHarness.case("accepts negative Studio IDs and every fixed match and participant state", function(assertions)
		local readyCheck = expectSnapshotSuccess(
			assertions,
			snapshot("ReadyCheck", 45, {
				participant(-9_007_199_254_740_991, "Active", true),
				participant(-2, "Disconnected", false),
				participant(7, "Returned", false),
				participant(9_007_199_254_740_991, "Spectator", false),
			})
		)
		assertions.equal(readyCheck.deadlineServerTime, 45)
		assertions.equal(#readyCheck.participants, 4)
		assertions.equal(readyCheck.participants[1].userId, -9_007_199_254_740_991)
		assertions.equal(readyCheck.participants[4].userId, 9_007_199_254_740_991)

		for _, state in { "Loading", "PreWave", "WaveActive", "Results", "Closing" } do
			local canonical = expectSnapshotSuccess(assertions, snapshot(state, nil, {}))
			assertions.equal(canonical.state, state)
			assertions.isNil(rawget(canonical :: any, "deadlineServerTime"))
		end
		expectSnapshotSuccess(assertions, snapshot("ReadyCheck", 0, {}))
	end),

	TestHarness.case("enforces the deadline cross-field invariant and finite nonnegative bounds", function(assertions)
		expectSnapshotFailure(
			assertions,
			snapshot("ReadyCheck", nil, {}),
			"MISSING_FIELD",
			"payload.deadlineServerTime"
		)
		for _, state in { "Loading", "PreWave", "WaveActive", "Results", "Closing" } do
			expectSnapshotFailure(
				assertions,
				snapshot(state, 45, {}),
				"INVALID_REFERENCE",
				"payload.deadlineServerTime"
			)
		end
		for _, invalidDeadline in { -1, math.huge, -math.huge, 0 / 0 } do
			expectSnapshotFailure(assertions, snapshot("ReadyCheck", invalidDeadline, {}), nil, nil)
		end
	end),

	TestHarness.case("allows ready only for Active participants", function(assertions)
		expectSnapshotSuccess(
			assertions,
			snapshot("ReadyCheck", 45, {
				participant(1, "Active", true),
			})
		)
		for _, state in { "Disconnected", "Returned", "Spectator" } do
			expectSnapshotFailure(
				assertions,
				snapshot("ReadyCheck", 45, { participant(1, state, true) }),
				"INVALID_REFERENCE",
				"payload.participants[1].ready"
			)
		end
	end),

	TestHarness.case("requires at most four strictly UserId-sorted unique participants", function(assertions)
		expectSnapshotFailure(
			assertions,
			snapshot("ReadyCheck", 45, {
				participant(2, "Active", false),
				participant(1, "Active", false),
			}),
			"INVALID_ORDER",
			"payload.participants[2].userId"
		)
		expectSnapshotFailure(
			assertions,
			snapshot("ReadyCheck", 45, {
				participant(1, "Active", false),
				participant(1, "Active", false),
			}),
			"DUPLICATE_VALUE",
			"payload.participants[2].userId"
		)
		expectSnapshotFailure(
			assertions,
			snapshot("ReadyCheck", 45, {
				participant(1, "Active", false),
				participant(2, "Active", false),
				participant(3, "Active", false),
				participant(4, "Active", false),
				participant(5, "Active", false),
			}),
			nil,
			nil
		)
	end),

	TestHarness.case("rejects every malformed UserId class and participant shape", function(assertions)
		for _, invalidUserId in { 0, 1.5, math.huge, -math.huge, 0 / 0, 9_007_199_254_740_992 } do
			expectSnapshotFailure(
				assertions,
				snapshot("ReadyCheck", 45, { participant(invalidUserId, "Active", false) }),
				nil,
				nil
			)
		end
		expectSnapshotFailure(
			assertions,
			snapshot("ReadyCheck", 45, {
				{
					userId = 1,
					state = "Active",
					ready = false,
					extra = "private",
				},
			}),
			nil,
			nil
		)
		expectSnapshotFailure(
			assertions,
			snapshot("ReadyCheck", 45, {
				participant(1, "Unknown", false),
			}),
			nil,
			nil
		)
	end),

	TestHarness.case("rejects extra fields metatables Instances and non-plain nested input", function(assertions)
		local extra = snapshot("ReadyCheck", 45, {})
		extra.extra = true
		expectSnapshotFailure(assertions, extra, nil, nil)

		local rootMetatable = snapshot("ReadyCheck", 45, {})
		setmetatable(rootMetatable, {})
		expectSnapshotFailure(assertions, rootMetatable, nil, nil)

		local participantMetatable = participant(1, "Active", false)
		setmetatable(participantMetatable, {})
		expectSnapshotFailure(assertions, snapshot("ReadyCheck", 45, { participantMetatable }), nil, nil)

		local participantsMetatable = { participant(1, "Active", false) }
		setmetatable(participantsMetatable, {})
		expectSnapshotFailure(assertions, snapshot("ReadyCheck", 45, participantsMetatable), nil, nil)

		expectSnapshotFailure(assertions, Instance.new("Folder"), nil, nil)
		expectSnapshotFailure(assertions, snapshot("ReadyCheck", 45, { Instance.new("Folder") :: any }), nil, nil)
	end),

	TestHarness.case("returns a newly detached deeply frozen snapshot with exact field omission", function(assertions)
		local authoredParticipant = participant(-10, "Active", true)
		local authoredParticipants = { authoredParticipant }
		local authored = snapshot("ReadyCheck", 100.25, authoredParticipants)
		local first = expectSnapshotSuccess(assertions, authored)
		local second = expectSnapshotSuccess(assertions, authored)

		assertions.notEqual(first, authored)
		assertions.notEqual(first.participants, authoredParticipants)
		assertions.notEqual(first.participants[1], authoredParticipant)
		assertions.notEqual(first, second)
		assertions.notEqual(first.participants, second.participants)
		assertions.notEqual(first.participants[1], second.participants[1])
		assertions.isTrue(table.isfrozen(first))
		assertions.isTrue(table.isfrozen(first.participants))
		assertions.isTrue(table.isfrozen(first.participants[1]))

		authored.revision = 99
		authored.deadlineServerTime = 101
		authoredParticipant.userId = 25
		authoredParticipant.state = "Returned"
		authoredParticipant.ready = false
		assertions.equal(first.revision, 1)
		assertions.equal(first.deadlineServerTime, 100.25)
		assertions.equal(first.participants[1].userId, -10)
		assertions.equal(first.participants[1].state, "Active")
		assertions.isTrue(first.participants[1].ready)

		assertions.isFalse(pcall(function()
			(first :: any).revision = 2
		end))
		assertions.isFalse(pcall(function()
			(first.participants :: any)[2] = first.participants[1]
		end))
		assertions.isFalse(pcall(function()
			(first.participants[1] :: any).ready = false
		end))

		local loading = expectSnapshotSuccess(assertions, snapshot("Loading", nil, {}))
		local fieldCount = 0
		for _ in next, loading :: any do
			fieldCount += 1
		end
		assertions.equal(fieldCount, 4)
		assertions.isNil(rawget(loading :: any, "deadlineServerTime"))
	end),

	TestHarness.case("returns static privacy-safe failures without retaining rejected values", function(assertions)
		local privateValue = {
			secret = "PRIVATE_MATCH_PROTOCOL_SENTINEL",
		}
		local invalid = snapshot("ReadyCheck", nil, {})
		invalid.private = privateValue
		local issue = expectSnapshotFailure(assertions, invalid, nil, nil)
		assertions.isFalse(graphContains(issue, privateValue))
		for _, fieldName in { "code", "path", "message" } do
			assertions.isNil(string.find(issue[fieldName], privateValue.secret, 1, true))
		end
	end),
})
