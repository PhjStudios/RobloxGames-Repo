--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type ViewerRole = "Participant" | "Spectator"
export type ReturnStatus = "Idle" | "Pending" | "Teleporting" | "Failed"
export type RematchState = "Pending" | "Approved" | "Declined" | "Failed"
export type VoteChoice = "Pending" | "Approve" | "Decline"

export type VoteView = {
	userId: number,
	choice: VoteChoice,
}

export type RematchView = {
	revision: number,
	state: RematchState,
	deadline: number,
	votes: { VoteView },
}

export type Snapshot = {
	version: number,
	matchId: string,
	revision: number,
	viewerRole: ViewerRole,
	returnStatus: ReturnStatus,
	publicFailure: string?,
	rematch: RematchView?,
}

export type ReturnIntent = {
	transactionId: string,
	matchId: string,
	observedRevision: number,
}

export type RematchVoteIntent = ReturnIntent & {
	approve: boolean,
	observedRematchRevision: number,
}

export type MutationReceipt = {
	transactionId: string,
	changed: boolean,
	snapshot: Snapshot,
}

local VERSION = 1
local MAX_VOTERS = 4
local SAFE_INTEGER = PayloadValidation.integer(0, Validation.MAX_SAFE_INTEGER)
local POSITIVE_SAFE_INTEGER = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)
local VOTE = PayloadValidation.record({
	userId = POSITIVE_SAFE_INTEGER,
	choice = PayloadValidation.enum({ "Pending", "Approve", "Decline" }),
})
local REMATCH = PayloadValidation.record({
	revision = POSITIVE_SAFE_INTEGER,
	state = PayloadValidation.enum({ "Pending", "Approved", "Declined", "Failed" }),
	deadline = SAFE_INTEGER,
	votes = PayloadValidation.array(VOTE, MAX_VOTERS, 1),
})
local SNAPSHOT = PayloadValidation.record({
	version = PayloadValidation.integer(VERSION, VERSION),
	matchId = PayloadValidation.id("match"),
	revision = POSITIVE_SAFE_INTEGER,
	viewerRole = PayloadValidation.enum({ "Participant", "Spectator" }),
	returnStatus = PayloadValidation.enum({ "Idle", "Pending", "Teleporting", "Failed" }),
	publicFailure = PayloadValidation.optional(PayloadValidation.enum({
		"RETURN_UNAVAILABLE",
		"PROFILE_RELEASE_FAILED",
		"TELEPORT_FAILED",
		"REMATCH_UNAVAILABLE",
	})),
	rematch = PayloadValidation.optional(REMATCH),
})
local RETURN_INTENT = PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	matchId = PayloadValidation.id("match"),
	observedRevision = POSITIVE_SAFE_INTEGER,
})

local MatchTravelProtocol = {
	VERSION = VERSION,
	MAX_VOTERS = MAX_VOTERS,
	ENDPOINTS = table.freeze({
		GET_SNAPSHOT = "GetMatchTravelSnapshot",
		REQUEST_RETURN = "RequestReturnToLobby",
		VOTE_REMATCH = "SubmitRematchVote",
		REPLICATION = "MatchTravelReplication",
	}),
	EmptyPayloadSchema = PayloadValidation.schema(PayloadValidation.record({})),
	SnapshotSchema = PayloadValidation.schema(SNAPSHOT),
	ReturnIntentSchema = PayloadValidation.schema(RETURN_INTENT),
	RematchVoteIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		matchId = PayloadValidation.id("match"),
		observedRevision = POSITIVE_SAFE_INTEGER,
		approve = PayloadValidation.boolean(),
		observedRematchRevision = POSITIVE_SAFE_INTEGER,
	})),
	MutationReceiptSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		changed = PayloadValidation.boolean(),
		snapshot = SNAPSHOT,
	})),
}

local function issue(path: { Validation.PathSegment }, message: string)
	return Result.err(Validation.issue("INVALID_REFERENCE", path, message))
end

function MatchTravelProtocol.validateSnapshot(value: unknown): Result.Result<Snapshot, Validation.Issue>
	local parsed = MatchTravelProtocol.SnapshotSchema:validate(value)
	if not parsed.ok then
		return Result.err(parsed.error)
	end
	local snapshot = parsed.value :: Snapshot
	if snapshot.returnStatus == "Failed" then
		if snapshot.publicFailure == nil then
			return issue({ "payload", "publicFailure" }, "Failed return status requires a bounded public reason")
		end
	elseif snapshot.publicFailure ~= nil then
		return issue({ "payload", "publicFailure" }, "Only a failed operation may retain a public reason")
	end
	local rematch = snapshot.rematch
	if rematch ~= nil then
		local seen: { [number]: boolean } = {}
		for index, vote in rematch.votes do
			if seen[vote.userId] then
				return issue({ "payload", "rematch", "votes", index }, "Rematch voters must be unique and ordered")
			end
			seen[vote.userId] = true
		end
		if rematch.state == "Approved" then
			for index, vote in rematch.votes do
				if vote.choice ~= "Approve" then
					return issue({ "payload", "rematch", "votes", index }, "Approved rematches require unanimous votes")
				end
			end
		elseif rematch.state == "Pending" then
			local pending = false
			for _, vote in rematch.votes do
				pending = pending or vote.choice == "Pending"
			end
			if not pending then
				return issue({ "payload", "rematch", "state" }, "Pending rematch requires an outstanding vote")
			end
		end
	end
	return Result.ok(snapshot)
end

function MatchTravelProtocol.validateMutationReceipt(value: unknown): Result.Result<MutationReceipt, Validation.Issue>
	local parsed = MatchTravelProtocol.MutationReceiptSchema:validate(value)
	if not parsed.ok then
		return Result.err(parsed.error)
	end
	local receipt = parsed.value :: MutationReceipt
	local snapshot = MatchTravelProtocol.validateSnapshot(receipt.snapshot)
	return if snapshot.ok then Result.ok(receipt) else Result.err(snapshot.error)
end

return table.freeze(MatchTravelProtocol)
