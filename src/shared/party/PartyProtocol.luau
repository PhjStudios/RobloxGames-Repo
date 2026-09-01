--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type Privacy = "InviteOnly" | "FriendsOnly"
export type QueueState = "Idle" | "Queued" | "Starting" | "Traveling"
export type MembershipEndReason = "VoluntaryLeave" | "Kicked" | "Disconnected" | "ServerLeave" | "PartyDisbanded"
export type DisbandReason = "LeaderDisbanded" | "LastMemberLeft" | "Shutdown"
export type PublicReason =
	"PartyCreated"
	| "InvitationSent"
	| "InvitationAlreadyPending"
	| "InvitationAccepted"
	| "InvitationDeclined"
	| "InvitationExpired"
	| "InvitationRevoked"
	| "MemberLeft"
	| "MemberKicked"
	| "MemberDisconnected"
	| "MemberServerLeft"
	| "LeadershipTransferred"
	| "LeadershipUnchanged"
	| "PrivacyChanged"
	| "PrivacyUnchanged"
	| "LeaderDisbanded"
	| "LastMemberLeft"
	| "ServerShutdown"
export type MutationKind =
	"Create"
	| "Invite"
	| "Accept"
	| "Decline"
	| "Leave"
	| "Kick"
	| "TransferLeadership"
	| "SetPrivacy"
	| "Disband"

export type MemberView = {
	userId: number,
	order: number,
	isLeader: boolean,
	profileReady: boolean,
}

export type PartyView = {
	version: number,
	partyId: string,
	revision: number,
	leaderUserId: number,
	privacy: Privacy,
	queueState: QueueState,
	members: { MemberView },
	pendingInvitationCount: number,
}

export type InvitationView = {
	invitationId: string,
	partyId: string,
	partyRevision: number,
	inviterUserId: number,
	targetUserId: number,
	createdAt: number,
	expiresAt: number,
}

export type ViewerSnapshot = {
	version: number,
	party: PartyView?,
	incomingInvitations: { InvitationView },
}

export type MutationReceipt = {
	transactionId: string,
	kind: MutationKind,
	reason: PublicReason,
	changed: boolean,
	partyRevision: number,
	snapshot: ViewerSnapshot,
}

export type CreateIntent = {
	transactionId: string,
	expectedRevision: number,
	privacy: Privacy,
}

export type InviteIntent = {
	transactionId: string,
	expectedRevision: number,
	targetUserId: number,
}

export type InvitationIntent = {
	transactionId: string,
	expectedRevision: number,
	invitationId: string,
}

export type MemberIntent = {
	transactionId: string,
	expectedRevision: number,
	targetUserId: number,
}

export type RevisionIntent = {
	transactionId: string,
	expectedRevision: number,
}

export type PrivacyIntent = RevisionIntent & {
	privacy: Privacy,
}

local VERSION = 1
local MAX_MEMBERS = 4
local MAX_PENDING_INVITATIONS = 8
local MAX_INCOMING_INVITATIONS = 8
local MAX_RECEIPTS_PER_ACTOR = 32
local MAX_ID_BYTES = 64
local POSITIVE_SAFE_INTEGER = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)
local NONNEGATIVE_SAFE_INTEGER = PayloadValidation.integer(0, Validation.MAX_SAFE_INTEGER)
local PARTY_ID = PayloadValidation.string(MAX_ID_BYTES, #"party:a")
local INVITATION_ID = PayloadValidation.string(MAX_ID_BYTES, #"invitation:a")
local PRIVACY = PayloadValidation.enum({ "InviteOnly", "FriendsOnly" })
local QUEUE_STATE = PayloadValidation.enum({ "Idle", "Queued", "Starting", "Traveling" })
local PUBLIC_REASON = PayloadValidation.enum({
	"PartyCreated",
	"InvitationSent",
	"InvitationAlreadyPending",
	"InvitationAccepted",
	"InvitationDeclined",
	"InvitationExpired",
	"InvitationRevoked",
	"MemberLeft",
	"MemberKicked",
	"MemberDisconnected",
	"MemberServerLeft",
	"LeadershipTransferred",
	"LeadershipUnchanged",
	"PrivacyChanged",
	"PrivacyUnchanged",
	"LeaderDisbanded",
	"LastMemberLeft",
	"ServerShutdown",
})

local MEMBER = PayloadValidation.record({
	userId = POSITIVE_SAFE_INTEGER,
	order = PayloadValidation.integer(1, MAX_MEMBERS),
	isLeader = PayloadValidation.boolean(),
	profileReady = PayloadValidation.boolean(),
})

local PARTY = PayloadValidation.record({
	version = PayloadValidation.integer(VERSION, VERSION),
	partyId = PARTY_ID,
	revision = POSITIVE_SAFE_INTEGER,
	leaderUserId = POSITIVE_SAFE_INTEGER,
	privacy = PRIVACY,
	queueState = QUEUE_STATE,
	members = PayloadValidation.array(MEMBER, MAX_MEMBERS, 1),
	pendingInvitationCount = PayloadValidation.integer(0, MAX_PENDING_INVITATIONS),
})

local INVITATION = PayloadValidation.record({
	invitationId = INVITATION_ID,
	partyId = PARTY_ID,
	partyRevision = POSITIVE_SAFE_INTEGER,
	inviterUserId = POSITIVE_SAFE_INTEGER,
	targetUserId = POSITIVE_SAFE_INTEGER,
	createdAt = NONNEGATIVE_SAFE_INTEGER,
	expiresAt = POSITIVE_SAFE_INTEGER,
})

local VIEWER_SNAPSHOT = PayloadValidation.record({
	version = PayloadValidation.integer(VERSION, VERSION),
	party = PayloadValidation.optional(PARTY),
	incomingInvitations = PayloadValidation.array(INVITATION, MAX_INCOMING_INVITATIONS, 0),
})

local MUTATION_RECEIPT = PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	kind = PayloadValidation.enum({
		"Create",
		"Invite",
		"Accept",
		"Decline",
		"Leave",
		"Kick",
		"TransferLeadership",
		"SetPrivacy",
		"Disband",
	}),
	reason = PUBLIC_REASON,
	changed = PayloadValidation.boolean(),
	partyRevision = NONNEGATIVE_SAFE_INTEGER,
	snapshot = VIEWER_SNAPSHOT,
})

local PartyProtocol = {
	VERSION = VERSION,
	MAX_MEMBERS = MAX_MEMBERS,
	MAX_PENDING_INVITATIONS = MAX_PENDING_INVITATIONS,
	MAX_INCOMING_INVITATIONS = MAX_INCOMING_INVITATIONS,
	MAX_RECEIPTS_PER_ACTOR = MAX_RECEIPTS_PER_ACTOR,
	MAX_ID_BYTES = MAX_ID_BYTES,
	MEMBERSHIP_END_REASONS = table.freeze({
		"VoluntaryLeave",
		"Kicked",
		"Disconnected",
		"ServerLeave",
		"PartyDisbanded",
	}),
	DISBAND_REASONS = table.freeze({ "LeaderDisbanded", "LastMemberLeft", "Shutdown" }),
	PUBLIC_REASONS = table.freeze({
		"PartyCreated",
		"InvitationSent",
		"InvitationAlreadyPending",
		"InvitationAccepted",
		"InvitationDeclined",
		"InvitationExpired",
		"InvitationRevoked",
		"MemberLeft",
		"MemberKicked",
		"MemberDisconnected",
		"MemberServerLeft",
		"LeadershipTransferred",
		"LeadershipUnchanged",
		"PrivacyChanged",
		"PrivacyUnchanged",
		"LeaderDisbanded",
		"LastMemberLeft",
		"ServerShutdown",
	}),
	ViewerSnapshotSchema = PayloadValidation.schema(VIEWER_SNAPSHOT),
	MutationReceiptSchema = PayloadValidation.schema(MUTATION_RECEIPT),
	CreateIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		expectedRevision = NONNEGATIVE_SAFE_INTEGER,
		privacy = PRIVACY,
	})),
	InviteIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		expectedRevision = POSITIVE_SAFE_INTEGER,
		targetUserId = POSITIVE_SAFE_INTEGER,
	})),
	InvitationIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		expectedRevision = POSITIVE_SAFE_INTEGER,
		invitationId = INVITATION_ID,
	})),
	MemberIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		expectedRevision = POSITIVE_SAFE_INTEGER,
		targetUserId = POSITIVE_SAFE_INTEGER,
	})),
	RevisionIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		expectedRevision = POSITIVE_SAFE_INTEGER,
	})),
	PrivacyIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		expectedRevision = POSITIVE_SAFE_INTEGER,
		privacy = PRIVACY,
	})),
}

local function opaqueId(value: unknown, prefix: string): boolean
	if type(value) ~= "string" or #value < #prefix + 1 or #value > MAX_ID_BYTES then
		return false
	end
	if string.sub(value, 1, #prefix) ~= prefix then
		return false
	end
	for index = #prefix + 1, #value do
		local byte = string.byte(value, index)
		if
			byte == nil
			or not (
				(byte >= string.byte("a") and byte <= string.byte("z"))
				or (byte >= string.byte("0") and byte <= string.byte("9"))
				or byte == string.byte("-")
				or byte == string.byte("_")
			)
		then
			return false
		end
	end
	return true
end

function PartyProtocol.isPartyId(value: unknown): boolean
	return opaqueId(value, "party:")
end

function PartyProtocol.isInvitationId(value: unknown): boolean
	return opaqueId(value, "invitation:")
end

local function issue(path: { Validation.PathSegment }, message: string)
	return Result.err(Validation.issue("INVALID_REFERENCE", path, message))
end

function PartyProtocol.validateViewerSnapshot(value: unknown): Result.Result<ViewerSnapshot, Validation.Issue>
	local parsed = PartyProtocol.ViewerSnapshotSchema:validate(value)
	if not parsed.ok then
		return Result.err(parsed.error)
	end
	local snapshot = parsed.value :: ViewerSnapshot
	local party = snapshot.party
	if party ~= nil then
		if not PartyProtocol.isPartyId(party.partyId) then
			return issue({ "payload", "party", "partyId" }, "Party ID is not a bounded opaque party identifier")
		end
		local seen: { [number]: boolean } = {}
		local leaderCount = 0
		for index, member in party.members do
			if member.order ~= index or seen[member.userId] then
				return issue({ "payload", "party", "members", index }, "Party members must be unique and ordered")
			end
			seen[member.userId] = true
			if member.isLeader then
				leaderCount += 1
				if member.userId ~= party.leaderUserId then
					return issue({ "payload", "party", "leaderUserId" }, "Leader identity does not match members")
				end
			end
		end
		if leaderCount ~= 1 or not seen[party.leaderUserId] then
			return issue({ "payload", "party", "leaderUserId" }, "Party must have exactly one leader")
		end
	end

	local previousId: string? = nil
	for index, invitation in snapshot.incomingInvitations do
		if
			not PartyProtocol.isInvitationId(invitation.invitationId)
			or not PartyProtocol.isPartyId(invitation.partyId)
			or invitation.expiresAt <= invitation.createdAt
			or invitation.targetUserId < 1
			or (previousId ~= nil and invitation.invitationId <= previousId)
		then
			return issue({ "payload", "incomingInvitations", index }, "Invitation view is malformed or unordered")
		end
		previousId = invitation.invitationId
	end
	return Result.ok(snapshot)
end

function PartyProtocol.validateMutationReceipt(value: unknown): Result.Result<MutationReceipt, Validation.Issue>
	local parsed = PartyProtocol.MutationReceiptSchema:validate(value)
	if not parsed.ok then
		return Result.err(parsed.error)
	end
	local receipt = parsed.value :: MutationReceipt
	local snapshot = PartyProtocol.validateViewerSnapshot(receipt.snapshot)
	if not snapshot.ok then
		return Result.err(snapshot.error)
	end
	if snapshot.value.party ~= nil and snapshot.value.party.revision ~= receipt.partyRevision then
		return issue({ "payload", "partyRevision" }, "Receipt revision must match the current viewer party")
	end
	if snapshot.value.party == nil and receipt.partyRevision ~= 0 then
		return issue({ "payload", "partyRevision" }, "Party-less receipt must use revision zero")
	end
	local reasonMatchesKind = if receipt.kind == "Create"
		then receipt.reason == "PartyCreated"
		elseif receipt.kind == "Invite" then receipt.reason == "InvitationSent"
			or receipt.reason == "InvitationAlreadyPending"
		elseif receipt.kind == "Accept" then receipt.reason == "InvitationAccepted"
		elseif receipt.kind == "Decline" then receipt.reason == "InvitationDeclined"
		elseif receipt.kind == "Leave" then receipt.reason == "MemberLeft" or receipt.reason == "LastMemberLeft"
		elseif receipt.kind == "Kick" then receipt.reason == "MemberKicked"
		elseif receipt.kind == "TransferLeadership" then receipt.reason == "LeadershipTransferred"
			or receipt.reason == "LeadershipUnchanged"
		elseif receipt.kind == "SetPrivacy" then receipt.reason == "PrivacyChanged"
			or receipt.reason == "PrivacyUnchanged"
		else receipt.kind == "Disband" and receipt.reason == "LeaderDisbanded"
	if not reasonMatchesKind then
		return issue({ "payload", "reason" }, "Receipt reason is not valid for its mutation kind")
	end
	if
		(
			receipt.reason == "InvitationAlreadyPending"
			or receipt.reason == "LeadershipUnchanged"
			or receipt.reason == "PrivacyUnchanged"
		) ~= not receipt.changed
	then
		return issue({ "payload", "changed" }, "Receipt reason and changed flag disagree")
	end
	return Result.ok(receipt)
end

return table.freeze(PartyProtocol)
