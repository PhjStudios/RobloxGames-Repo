--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type MatchState = "Loading" | "ReadyCheck" | "PreWave" | "WaveActive" | "Results" | "Closing"
export type ParticipantState = "Active" | "Disconnected" | "Returned" | "Spectator"

export type ParticipantSnapshot = {
	userId: number,
	state: ParticipantState,
	ready: boolean,
}

export type MatchSnapshot = {
	matchId: Ids.MatchId,
	revision: number,
	state: MatchState,
	deadlineServerTime: number?,
	participants: { ParticipantSnapshot },
}

export type SubmitReadyPayload = {
	matchId: Ids.MatchId,
	observedRevision: number,
}

local GET_MATCH_SNAPSHOT_ENDPOINT = "GetMatchSnapshot"
local SUBMIT_READY_ENDPOINT = "SubmitReady"
local MATCH_SNAPSHOT_ENDPOINT = "MatchSnapshot"
local READY_CHECK_SECONDS = 45
local MAX_FINITE_NUMBER = 1.7976931348623157e308

local MATCH_STATE_VALIDATOR = PayloadValidation.enum({
	"Loading",
	"ReadyCheck",
	"PreWave",
	"WaveActive",
	"Results",
	"Closing",
})

local PARTICIPANT_STATE_VALIDATOR = PayloadValidation.enum({
	"Active",
	"Disconnected",
	"Returned",
	"Spectator",
})

local POSITIVE_REVISION_VALIDATOR = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)
local NONZERO_USER_ID_VALIDATOR = PayloadValidation.union({
	PayloadValidation.integer(-Validation.MAX_SAFE_INTEGER, -1),
	PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER),
})

local PARTICIPANT_SNAPSHOT_VALIDATOR = PayloadValidation.record({
	userId = NONZERO_USER_ID_VALIDATOR,
	state = PARTICIPANT_STATE_VALIDATOR,
	ready = PayloadValidation.boolean(),
})

local GetMatchSnapshotPayloadSchema = PayloadValidation.schema(PayloadValidation.record({}))

local SubmitReadyPayloadSchema = PayloadValidation.schema(PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	observedRevision = POSITIVE_REVISION_VALIDATOR,
}))

local MatchSnapshotSchema = PayloadValidation.schema(PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	revision = POSITIVE_REVISION_VALIDATOR,
	state = MATCH_STATE_VALIDATOR,
	deadlineServerTime = PayloadValidation.optional(PayloadValidation.number(0, MAX_FINITE_NUMBER)),
	participants = PayloadValidation.array(PARTICIPANT_SNAPSHOT_VALIDATOR, 4),
}))

local function snapshotIssue(
	code: Validation.Code,
	path: { Validation.PathSegment },
	message: string
): Result.Failure<Validation.Issue>
	return Result.err(Validation.issue(code, path, message))
end

local MatchProtocol = {
	GET_MATCH_SNAPSHOT_ENDPOINT = GET_MATCH_SNAPSHOT_ENDPOINT,
	SUBMIT_READY_ENDPOINT = SUBMIT_READY_ENDPOINT,
	MATCH_SNAPSHOT_ENDPOINT = MATCH_SNAPSHOT_ENDPOINT,
	READY_CHECK_SECONDS = READY_CHECK_SECONDS,
	GetMatchSnapshotPayloadSchema = GetMatchSnapshotPayloadSchema,
	SubmitReadyPayloadSchema = SubmitReadyPayloadSchema,
	MatchSnapshotSchema = MatchSnapshotSchema,
}

function MatchProtocol.validateMatchSnapshot(value: unknown): Result.Result<MatchSnapshot, Validation.Issue>
	local schemaResult = MatchSnapshotSchema:validate(value)
	if not schemaResult.ok then
		return Result.err(schemaResult.error)
	end

	local snapshot = schemaResult.value :: MatchSnapshot
	if snapshot.state == "ReadyCheck" then
		if snapshot.deadlineServerTime == nil then
			return snapshotIssue(
				"MISSING_FIELD",
				{ "payload", "deadlineServerTime" },
				"ReadyCheck snapshots require the authoritative deadline"
			)
		end
	elseif snapshot.deadlineServerTime ~= nil then
		return snapshotIssue(
			"INVALID_REFERENCE",
			{ "payload", "deadlineServerTime" },
			"The authoritative deadline is valid only during ReadyCheck"
		)
	end

	local previousUserId: number? = nil
	for index, participant in snapshot.participants do
		if participant.ready and participant.state ~= "Active" then
			return snapshotIssue(
				"INVALID_REFERENCE",
				{ "payload", "participants", index, "ready" },
				"Only an Active participant can be ready"
			)
		end

		if previousUserId ~= nil then
			if participant.userId == previousUserId then
				return snapshotIssue(
					"DUPLICATE_VALUE",
					{ "payload", "participants", index, "userId" },
					"Participant UserIds must be unique"
				)
			elseif participant.userId < previousUserId then
				return snapshotIssue(
					"INVALID_ORDER",
					{ "payload", "participants", index, "userId" },
					"Participants must be ordered by numeric UserId"
				)
			end
		end
		previousUserId = participant.userId
	end

	return Result.ok(snapshot)
end

return table.freeze(MatchProtocol)
