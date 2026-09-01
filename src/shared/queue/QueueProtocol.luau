--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type Privacy = "Public" | "PartyOnly"
export type State = "Open" | "Starting" | "Traveling" | "Failed"
export type PublicStatus =
	"TicketPending"
	| "TeleportInitializing"
	| "TeleportRetrying"
	| "TicketFailed"
	| "TeleportFailed"
	| "PartialTeleportFailure"
export type Source = "Physical" | "UI"
export type EnrollmentKind = "Solo" | "Party"
export type Readiness = "Ready" | "ProfileNotReady" | "SessionUnavailable" | "InvalidLoadout" | "NotEligible"
export type MutationKind = "Join" | "Leave" | "Configure" | "Start"

export type Configuration = {
	mapId: string,
	difficultyId: string,
	privacy: Privacy,
	maxPlayers: number,
}

export type MemberView = {
	userId: number,
	order: number,
	isCaptain: boolean,
	readiness: Readiness,
}

export type EnrollmentView = {
	sequence: number,
	kind: EnrollmentKind,
	leaderUserId: number,
	partyId: string?,
	partyRevision: number?,
	userIds: { number },
	source: Source,
}

export type Snapshot = {
	version: number,
	queueId: string,
	revision: number,
	state: State,
	publicStatus: PublicStatus?,
	captainUserId: number?,
	configuration: Configuration,
	members: { MemberView },
	enrollments: { EnrollmentView },
	canStart: boolean,
}

export type MutationReceipt = {
	transactionId: string,
	kind: MutationKind,
	changed: boolean,
	revision: number,
	snapshot: Snapshot,
}

export type JoinIntent = {
	transactionId: string,
	expectedRevision: number,
	queueId: string,
	source: Source,
}

export type LeaveIntent = {
	transactionId: string,
	expectedRevision: number,
	queueId: string,
}

export type ConfigureIntent = {
	transactionId: string,
	expectedRevision: number,
	queueId: string,
	configuration: Configuration,
}

export type StartIntent = {
	transactionId: string,
	expectedRevision: number,
	queueId: string,
}

local VERSION = 1
local MAX_PLAYERS = 4
local MAX_ENROLLMENTS = 4
local MAX_QUEUES = 16
local MAX_RECEIPTS_PER_ACTOR = 32
local POSITIVE_SAFE_INTEGER = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)
local PRIVACY = PayloadValidation.enum({ "Public", "PartyOnly" })
local SOURCE = PayloadValidation.enum({ "Physical", "UI" })
local CONFIGURATION = PayloadValidation.record({
	mapId = PayloadValidation.id("map"),
	difficultyId = PayloadValidation.id("difficulty"),
	privacy = PRIVACY,
	maxPlayers = PayloadValidation.integer(1, MAX_PLAYERS),
})
local MEMBER = PayloadValidation.record({
	userId = POSITIVE_SAFE_INTEGER,
	order = PayloadValidation.integer(1, MAX_PLAYERS),
	isCaptain = PayloadValidation.boolean(),
	readiness = PayloadValidation.enum({
		"Ready",
		"ProfileNotReady",
		"SessionUnavailable",
		"InvalidLoadout",
		"NotEligible",
	}),
})
local ENROLLMENT = PayloadValidation.record({
	sequence = POSITIVE_SAFE_INTEGER,
	kind = PayloadValidation.enum({ "Solo", "Party" }),
	leaderUserId = POSITIVE_SAFE_INTEGER,
	partyId = PayloadValidation.optional(PayloadValidation.string(64, #"party:a")),
	partyRevision = PayloadValidation.optional(POSITIVE_SAFE_INTEGER),
	userIds = PayloadValidation.array(POSITIVE_SAFE_INTEGER, MAX_PLAYERS, 1),
	source = SOURCE,
})
local SNAPSHOT = PayloadValidation.record({
	version = PayloadValidation.integer(VERSION, VERSION),
	queueId = PayloadValidation.id("queue"),
	revision = POSITIVE_SAFE_INTEGER,
	state = PayloadValidation.enum({ "Open", "Starting", "Traveling", "Failed" }),
	publicStatus = PayloadValidation.optional(PayloadValidation.enum({
		"TicketPending",
		"TeleportInitializing",
		"TeleportRetrying",
		"TicketFailed",
		"TeleportFailed",
		"PartialTeleportFailure",
	})),
	captainUserId = PayloadValidation.optional(POSITIVE_SAFE_INTEGER),
	configuration = CONFIGURATION,
	members = PayloadValidation.array(MEMBER, MAX_PLAYERS, 0),
	enrollments = PayloadValidation.array(ENROLLMENT, MAX_ENROLLMENTS, 0),
	canStart = PayloadValidation.boolean(),
})
local MUTATION_RECEIPT = PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	kind = PayloadValidation.enum({ "Join", "Leave", "Configure", "Start" }),
	changed = PayloadValidation.boolean(),
	revision = POSITIVE_SAFE_INTEGER,
	snapshot = SNAPSHOT,
})

local QueueProtocol = {
	VERSION = VERSION,
	MAX_PLAYERS = MAX_PLAYERS,
	MAX_ENROLLMENTS = MAX_ENROLLMENTS,
	MAX_QUEUES = MAX_QUEUES,
	MAX_RECEIPTS_PER_ACTOR = MAX_RECEIPTS_PER_ACTOR,
	SnapshotSchema = PayloadValidation.schema(SNAPSHOT),
	MutationReceiptSchema = PayloadValidation.schema(MUTATION_RECEIPT),
	JoinIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		expectedRevision = POSITIVE_SAFE_INTEGER,
		queueId = PayloadValidation.id("queue"),
		source = SOURCE,
	})),
	LeaveIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		expectedRevision = POSITIVE_SAFE_INTEGER,
		queueId = PayloadValidation.id("queue"),
	})),
	ConfigureIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		expectedRevision = POSITIVE_SAFE_INTEGER,
		queueId = PayloadValidation.id("queue"),
		configuration = CONFIGURATION,
	})),
	StartIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		expectedRevision = POSITIVE_SAFE_INTEGER,
		queueId = PayloadValidation.id("queue"),
	})),
}

local function issue(path: { Validation.PathSegment }, message: string)
	return Result.err(Validation.issue("INVALID_REFERENCE", path, message))
end

function QueueProtocol.validateSnapshot(value: unknown): Result.Result<Snapshot, Validation.Issue>
	local parsed = QueueProtocol.SnapshotSchema:validate(value)
	if not parsed.ok then
		return Result.err(parsed.error)
	end
	local snapshot = parsed.value :: Snapshot
	local memberByUserId: { [number]: MemberView } = {}
	local captainCount = 0
	for index, member in snapshot.members do
		if member.order ~= index or memberByUserId[member.userId] ~= nil then
			return issue({ "payload", "members", index }, "Queue members must be unique and ordered")
		end
		memberByUserId[member.userId] = member
		if member.isCaptain then
			captainCount += 1
			if member.userId ~= snapshot.captainUserId then
				return issue({ "payload", "captainUserId" }, "Captain does not match member view")
			end
		end
	end
	if #snapshot.members == 0 then
		if
			snapshot.captainUserId ~= nil
			or captainCount ~= 0
			or snapshot.state ~= "Open"
			or snapshot.publicStatus ~= nil
			or snapshot.canStart
		then
			return issue({ "payload" }, "Empty queues must be fully reset and open")
		end
	elseif snapshot.captainUserId == nil or captainCount ~= 1 then
		return issue({ "payload", "captainUserId" }, "Non-empty queue must have exactly one captain")
	end
	if snapshot.configuration.maxPlayers < #snapshot.members then
		return issue({ "payload", "configuration", "maxPlayers" }, "Queue capacity cannot be below its roster")
	end

	local observed: { [number]: boolean } = {}
	local previousSequence = 0
	local flattened: { number } = {}
	for index, enrollment in snapshot.enrollments do
		if enrollment.sequence <= previousSequence then
			return issue({ "payload", "enrollments", index, "sequence" }, "Enrollments must use increasing sequence")
		end
		previousSequence = enrollment.sequence
		if enrollment.kind == "Solo" then
			if #enrollment.userIds ~= 1 or enrollment.partyId ~= nil or enrollment.partyRevision ~= nil then
				return issue({ "payload", "enrollments", index }, "Solo enrollment has party state")
			end
		elseif enrollment.partyId == nil or enrollment.partyRevision == nil then
			return issue({ "payload", "enrollments", index }, "Party enrollment lacks party identity")
		end
		if enrollment.userIds[1] ~= enrollment.leaderUserId then
			return issue({ "payload", "enrollments", index, "leaderUserId" }, "Enrollment leader must be first")
		end
		for _, userId in enrollment.userIds do
			if observed[userId] or memberByUserId[userId] == nil then
				return issue(
					{ "payload", "enrollments", index, "userIds" },
					"Enrollment users must uniquely match roster"
				)
			end
			observed[userId] = true
			table.insert(flattened, userId)
		end
	end
	if #flattened ~= #snapshot.members then
		return issue({ "payload", "enrollments" }, "Enrollment roster does not match member roster")
	end
	for index, userId in flattened do
		if snapshot.members[index].userId ~= userId then
			return issue({ "payload", "members", index }, "Members must follow enrollment ordering")
		end
	end
	if snapshot.state == "Open" then
		if snapshot.publicStatus ~= nil then
			return issue({ "payload", "publicStatus" }, "Open queue cannot retain travel status")
		end
	elseif snapshot.canStart then
		return issue({ "payload", "canStart" }, "Locked queue cannot advertise Start")
	elseif snapshot.state == "Starting" and snapshot.publicStatus ~= "TicketPending" then
		return issue({ "payload", "publicStatus" }, "Starting queue must expose bounded ticket-pending status")
	elseif
		snapshot.state == "Traveling"
		and snapshot.publicStatus ~= "TeleportInitializing"
		and snapshot.publicStatus ~= "TeleportRetrying"
	then
		return issue({ "payload", "publicStatus" }, "Traveling queue has invalid public status")
	elseif
		snapshot.state == "Failed"
		and snapshot.publicStatus ~= "TicketFailed"
		and snapshot.publicStatus ~= "TeleportFailed"
		and snapshot.publicStatus ~= "PartialTeleportFailure"
	then
		return issue({ "payload", "publicStatus" }, "Failed queue must expose a bounded privacy-safe reason")
	end
	return Result.ok(snapshot)
end

function QueueProtocol.validateMutationReceipt(value: unknown): Result.Result<MutationReceipt, Validation.Issue>
	local parsed = QueueProtocol.MutationReceiptSchema:validate(value)
	if not parsed.ok then
		return Result.err(parsed.error)
	end
	local receipt = parsed.value :: MutationReceipt
	local snapshot = QueueProtocol.validateSnapshot(receipt.snapshot)
	if not snapshot.ok then
		return Result.err(snapshot.error)
	end
	if receipt.revision ~= snapshot.value.revision then
		return issue({ "payload", "revision" }, "Receipt revision must match its queue snapshot")
	end
	return Result.ok(receipt)
end

return table.freeze(QueueProtocol)
