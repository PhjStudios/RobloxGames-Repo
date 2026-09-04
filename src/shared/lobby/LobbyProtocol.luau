--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local QueueProtocol = require(script.Parent.Parent.queue.QueueProtocol)
local TutorialProtocol = require(script.Parent.Parent.profile.TutorialProtocol)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type ActiveRouteStatus = "None" | "Available" | "Stale"
export type ActiveRouteView = {
	version: number,
	status: ActiveRouteStatus,
	matchId: string?,
	expiresAt: number?,
}

export type QueueList = {
	version: number,
	queues: { QueueProtocol.Snapshot },
}

export type InvitePromptStatus = "Opened" | "Unavailable" | "Denied"
export type InvitePromptReceipt = {
	transactionId: string,
	status: InvitePromptStatus,
}

export type ReconnectStatus = "Initializing" | "Unavailable" | "Stale" | "Failed"
export type ReconnectReceipt = {
	transactionId: string,
	status: ReconnectStatus,
	route: ActiveRouteView,
}

local VERSION = 1
local POSITIVE_SAFE_INTEGER = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)
local QUEUE_CONFIGURATION = PayloadValidation.record({
	mapId = PayloadValidation.id("map"),
	difficultyId = PayloadValidation.id("difficulty"),
	privacy = PayloadValidation.enum({ "Public", "PartyOnly" }),
	maxPlayers = PayloadValidation.integer(1, QueueProtocol.MAX_PLAYERS),
})
local QUEUE_MEMBER = PayloadValidation.record({
	userId = POSITIVE_SAFE_INTEGER,
	order = PayloadValidation.integer(1, QueueProtocol.MAX_PLAYERS),
	isCaptain = PayloadValidation.boolean(),
	readiness = PayloadValidation.enum({
		"Ready",
		"ProfileNotReady",
		"SessionUnavailable",
		"InvalidLoadout",
		"NotEligible",
	}),
})
local QUEUE_ENROLLMENT = PayloadValidation.record({
	sequence = POSITIVE_SAFE_INTEGER,
	kind = PayloadValidation.enum({ "Solo", "Party" }),
	leaderUserId = POSITIVE_SAFE_INTEGER,
	partyId = PayloadValidation.optional(PayloadValidation.string(64, #"party:a")),
	partyRevision = PayloadValidation.optional(POSITIVE_SAFE_INTEGER),
	userIds = PayloadValidation.array(POSITIVE_SAFE_INTEGER, QueueProtocol.MAX_PLAYERS, 1),
	source = PayloadValidation.enum({ "Physical", "UI" }),
})
local QUEUE_SNAPSHOT = PayloadValidation.record({
	version = PayloadValidation.integer(QueueProtocol.VERSION, QueueProtocol.VERSION),
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
	configuration = QUEUE_CONFIGURATION,
	members = PayloadValidation.array(QUEUE_MEMBER, QueueProtocol.MAX_PLAYERS, 0),
	enrollments = PayloadValidation.array(QUEUE_ENROLLMENT, QueueProtocol.MAX_ENROLLMENTS, 0),
	canStart = PayloadValidation.boolean(),
})
local ACTIVE_ROUTE = PayloadValidation.record({
	version = PayloadValidation.integer(VERSION, VERSION),
	status = PayloadValidation.enum({ "None", "Available", "Stale" }),
	matchId = PayloadValidation.optional(PayloadValidation.id("match")),
	expiresAt = PayloadValidation.optional(POSITIVE_SAFE_INTEGER),
})

local LobbyProtocol = {
	VERSION = VERSION,
	ENDPOINTS = table.freeze({
		GET_PROFILE = "GetLobbyProfile",
		RETRY_PROFILE = "RetryLobbyProfile",
		GET_INVENTORY = "GetLobbyInventory",
		EQUIP_TOWER = "EquipLobbyTower",
		UNEQUIP_TOWER = "UnequipLobbyTower",
		FAVORITE_TOWER = "FavoriteLobbyTower",
		LOCK_TOWER = "LockLobbyTower",
		GET_BANNER = "GetLobbyBanner",
		PULL_CHEST = "PullLobbyChest",
		UPDATE_SETTINGS = "UpdateLobbySettings",
		ADVANCE_TUTORIAL = "AdvanceLobbyTutorial",
		SKIP_TUTORIAL = "SkipLobbyTutorial",
		REPLAY_TUTORIAL = "ReplayLobbyTutorial",
		GET_PARTY = "GetLobbyParty",
		CREATE_PARTY = "CreateLobbyParty",
		INVITE_PARTY = "InviteLobbyParty",
		ACCEPT_PARTY_INVITE = "AcceptLobbyPartyInvite",
		DECLINE_PARTY_INVITE = "DeclineLobbyPartyInvite",
		LEAVE_PARTY = "LeaveLobbyParty",
		KICK_PARTY_MEMBER = "KickLobbyPartyMember",
		TRANSFER_PARTY_LEADERSHIP = "TransferLobbyPartyLeadership",
		SET_PARTY_PRIVACY = "SetLobbyPartyPrivacy",
		DISBAND_PARTY = "DisbandLobbyParty",
		PROMPT_PARTY_INVITE = "PromptLobbyPartyInvite",
		GET_QUEUES = "GetLobbyQueues",
		JOIN_QUEUE = "JoinLobbyQueue",
		LEAVE_QUEUE = "LeaveLobbyQueue",
		CONFIGURE_QUEUE = "ConfigureLobbyQueue",
		START_QUEUE = "StartLobbyQueue",
		GET_ACTIVE_ROUTE = "GetLobbyActiveRoute",
		RECONNECT_ACTIVE_MATCH = "ReconnectLobbyActiveMatch",
		PROFILE_REPLICATION = "LobbyProfileReplication",
		INVENTORY_REPLICATION = "LobbyInventoryReplication",
		PARTY_REPLICATION = "LobbyPartyReplication",
		QUEUE_REPLICATION = "LobbyQueueReplication",
		ACTIVE_ROUTE_REPLICATION = "LobbyActiveRouteReplication",
	}),
	EmptyPayloadSchema = PayloadValidation.schema(PayloadValidation.record({})),
	BannerRequestSchema = PayloadValidation.schema(PayloadValidation.record({
		bannerId = PayloadValidation.id("banner"),
	})),
	QueueListSchema = PayloadValidation.schema(PayloadValidation.record({
		version = PayloadValidation.integer(VERSION, VERSION),
		queues = PayloadValidation.array(QUEUE_SNAPSHOT, QueueProtocol.MAX_QUEUES, 0),
	})),
	InvitePromptIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		expectedRevision = POSITIVE_SAFE_INTEGER,
	})),
	InvitePromptReceiptSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		status = PayloadValidation.enum({ "Opened", "Unavailable", "Denied" }),
	})),
	ActiveRouteViewSchema = PayloadValidation.schema(ACTIVE_ROUTE),
	ReconnectIntentSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
	})),
	ReconnectReceiptSchema = PayloadValidation.schema(PayloadValidation.record({
		transactionId = PayloadValidation.id("transaction"),
		status = PayloadValidation.enum({ "Initializing", "Unavailable", "Stale", "Failed" }),
		route = ACTIVE_ROUTE,
	})),
	TutorialActionIntentSchema = TutorialProtocol.ActionIntentSchema,
	TutorialMutationReceiptSchema = TutorialProtocol.MutationReceiptSchema,
}

local function issue(path: { Validation.PathSegment }, message: string)
	return Result.err(Validation.issue("INVALID_REFERENCE", path, message))
end

function LobbyProtocol.validateQueueList(value: unknown): Result.Result<QueueList, Validation.Issue>
	local parsed = LobbyProtocol.QueueListSchema:validate(value)
	if not parsed.ok then
		return Result.err(parsed.error)
	end
	local list = parsed.value :: QueueList
	local previousQueueId: string? = nil
	for index, queue in list.queues do
		local validated = QueueProtocol.validateSnapshot(queue)
		if not validated.ok then
			return Result.err(validated.error)
		end
		if previousQueueId ~= nil and queue.queueId <= previousQueueId then
			return issue({ "payload", "queues", index, "queueId" }, "Queue snapshots must be unique and ordered")
		end
		previousQueueId = queue.queueId
	end
	return Result.ok(list)
end

function LobbyProtocol.validateActiveRoute(value: unknown): Result.Result<ActiveRouteView, Validation.Issue>
	local parsed = LobbyProtocol.ActiveRouteViewSchema:validate(value)
	if not parsed.ok then
		return Result.err(parsed.error)
	end
	local route = parsed.value :: ActiveRouteView
	if route.status == "Available" then
		if route.matchId == nil or route.expiresAt == nil then
			return issue({ "payload" }, "Available active-match routes require bounded display metadata")
		end
	elseif route.matchId ~= nil or route.expiresAt ~= nil then
		return issue({ "payload" }, "Unavailable active-match routes cannot expose routing metadata")
	end
	return Result.ok(route)
end

function LobbyProtocol.validateReconnectReceipt(value: unknown): Result.Result<ReconnectReceipt, Validation.Issue>
	local parsed = LobbyProtocol.ReconnectReceiptSchema:validate(value)
	if not parsed.ok then
		return Result.err(parsed.error)
	end
	local receipt = parsed.value :: ReconnectReceipt
	local route = LobbyProtocol.validateActiveRoute(receipt.route)
	if not route.ok then
		return Result.err(route.error)
	end
	if receipt.status == "Initializing" and route.value.status ~= "Available" then
		return issue({ "payload", "route", "status" }, "Reconnect initialization requires an active route")
	end
	return Result.ok(receipt)
end

return table.freeze(LobbyProtocol)
