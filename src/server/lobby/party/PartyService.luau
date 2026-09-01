--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartyProtocol = require(ReplicatedStorage.Shared.party.PartyProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type ChangeKind = "Created" | "InvitationChanged" | "MembershipChanged" | "Disbanded"
export type RemovalReason = "Disconnected" | "ServerLeave"
export type Change = {
	kind: ChangeKind,
	reason: PartyProtocol.PublicReason,
	partyId: string,
	revision: number,
	membershipChanged: boolean,
	userIds: { number },
}

export type Dependencies = {
	clock: () -> unknown,
	makePartyId: () -> unknown,
	makeInvitationId: () -> unknown,
	isPresent: (number) -> unknown,
	canInvite: (number, number) -> unknown,
	isProfileReady: ((number) -> unknown)?,
	getQueueState: (({ number }) -> unknown)?,
	onChanged: ((Change) -> ())?,
	invitationLifetimeSeconds: number?,
}

export type PartyEnrollment = {
	partyId: string,
	revision: number,
	leaderUserId: number,
	members: { number },
}

export type ErrorCode =
	"INVALID_DEPENDENCIES"
	| "INVALID_USER_ID"
	| "INVALID_INTENT"
	| "NOT_PRESENT"
	| "ALREADY_MEMBER"
	| "NOT_IN_PARTY"
	| "NOT_LEADER"
	| "TARGET_NOT_PRESENT"
	| "TARGET_ALREADY_MEMBER"
	| "PERMISSION_DENIED"
	| "PARTY_FULL"
	| "TOO_MANY_INVITATIONS"
	| "INVITATION_NOT_FOUND"
	| "INVITATION_EXPIRED"
	| "STALE_REVISION"
	| "TRANSACTION_CONFLICT"
	| "ID_COLLISION"
	| "REVISION_EXHAUSTED"
	| "RECONSTRUCTION_UNAVAILABLE"
	| "REENTRANT"
	| "UNAVAILABLE"

export type ServiceError = {
	code: ErrorCode,
	operation: string,
}

type InvitationRecord = {
	invitationId: string,
	partyId: string,
	partyRevision: number,
	inviterUserId: number,
	targetUserId: number,
	createdAt: number,
	expiresAt: number,
}

type PartyRecord = {
	partyId: string,
	revision: number,
	leaderUserId: number,
	members: { number },
	privacy: PartyProtocol.Privacy,
	invitationIds: { [string]: boolean },
}

type StoredReceipt = {
	kind: PartyProtocol.MutationKind,
	fingerprint: string,
	receipt: PartyProtocol.MutationReceipt,
}

type ReceiptLedger = {
	byId: { [string]: StoredReceipt },
	ring: { string? },
	count: number,
	nextIndex: number,
}

type ServiceData = {
	dependencies: Dependencies,
	invitationLifetimeSeconds: number,
	partiesById: { [string]: PartyRecord },
	partyIdByUserId: { [number]: string },
	invitationsById: { [string]: InvitationRecord },
	incomingByUserId: { [number]: { [string]: boolean } },
	receiptsByUserId: { [number]: ReceiptLedger },
	busy: boolean,
	callbackFailureCount: number,
}

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local DEFAULT_INVITATION_LIFETIME_SECONDS = 60
local MAX_INVITATION_LIFETIME_SECONDS = 300
local MIN_INVITATION_LIFETIME_SECONDS = 10

local PartyService = {}

local function failure<T>(code: ErrorCode, operation: string): Result.Failure<ServiceError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_PARTY_SERVICE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value) and (value :: number) > 0
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed or coroutine.status(thread) ~= "dead" then
		if resumed then
			pcall(coroutine.close, thread)
		end
		return false, nil
	end
	return true, value
end

local function now(data: ServiceData): number?
	local called, value = callNonYielding(data.dependencies.clock)
	if called and type(value) == "number" and Validation.isSafeInteger(value) and (value :: number) >= 0 then
		return value :: number
	end
	return nil
end

local function dependencyBoolean(callback: (...any) -> unknown, ...: any): boolean?
	local called, value = callNonYielding(callback, ...)
	return if called and type(value) == "boolean" then value :: boolean else nil
end

local function isPresent(data: ServiceData, userId: number): boolean?
	return dependencyBoolean(data.dependencies.isPresent, userId)
end

local function canInvite(data: ServiceData, inviterUserId: number, targetUserId: number): boolean?
	return dependencyBoolean(data.dependencies.canInvite, inviterUserId, targetUserId)
end

local function profileReady(data: ServiceData, userId: number): boolean
	local callback = data.dependencies.isProfileReady
	if callback == nil then
		return false
	end
	return dependencyBoolean(callback, userId) == true
end

local function queueState(data: ServiceData, members: { number }): PartyProtocol.QueueState
	local callback = data.dependencies.getQueueState
	if callback == nil then
		return "Idle"
	end
	local copy = table.clone(members)
	local called, value = callNonYielding(callback, table.freeze(copy))
	if called and (value == "Idle" or value == "Queued" or value == "Starting" or value == "Traveling") then
		return value :: PartyProtocol.QueueState
	end
	return "Idle"
end

local function copyMembers(members: { number }): { number }
	return table.freeze(table.clone(members))
end

local function emitChange(
	data: ServiceData,
	party: PartyRecord,
	kind: ChangeKind,
	reason: PartyProtocol.PublicReason,
	membershipChanged: boolean
)
	local callback = data.dependencies.onChanged
	if callback == nil then
		return
	end
	local change: Change = table.freeze({
		kind = kind,
		reason = reason,
		partyId = party.partyId,
		revision = party.revision,
		membershipChanged = membershipChanged,
		userIds = copyMembers(party.members),
	})
	local called = callNonYielding(callback, change)
	if not called then
		data.callbackFailureCount += 1
	end
end

local function incrementRevision(party: PartyRecord): boolean
	if party.revision >= Validation.MAX_SAFE_INTEGER then
		return false
	end
	party.revision += 1
	return true
end

local function removeInvitation(data: ServiceData, invitationId: string): InvitationRecord?
	local invitation = data.invitationsById[invitationId]
	if invitation == nil then
		return nil
	end
	data.invitationsById[invitationId] = nil
	local incoming = data.incomingByUserId[invitation.targetUserId]
	if incoming ~= nil then
		incoming[invitationId] = nil
		if next(incoming) == nil then
			data.incomingByUserId[invitation.targetUserId] = nil
		end
	end
	local party = data.partiesById[invitation.partyId]
	if party ~= nil then
		party.invitationIds[invitationId] = nil
	end
	return invitation
end

local function clearPartyInvitations(data: ServiceData, party: PartyRecord)
	local ids: { string } = {}
	for invitationId in party.invitationIds do
		table.insert(ids, invitationId)
	end
	table.sort(ids)
	for _, invitationId in ids do
		removeInvitation(data, invitationId)
	end
end

local function syncInvitationRevisions(data: ServiceData, party: PartyRecord)
	for invitationId in party.invitationIds do
		local invitation = data.invitationsById[invitationId]
		if invitation ~= nil then
			invitation.partyRevision = party.revision
		end
	end
end

local function expireInvitations(data: ServiceData, currentTime: number)
	local ids: { string } = {}
	for invitationId, invitation in data.invitationsById do
		if invitation.expiresAt <= currentTime then
			table.insert(ids, invitationId)
		end
	end
	table.sort(ids)
	local changedParties: { [string]: PartyRecord } = {}
	for _, invitationId in ids do
		local removed = removeInvitation(data, invitationId)
		if removed ~= nil then
			local party = data.partiesById[removed.partyId]
			if party ~= nil and incrementRevision(party) then
				changedParties[party.partyId] = party
			end
		end
	end
	local partyIds: { string } = {}
	for partyId in changedParties do
		table.insert(partyIds, partyId)
	end
	table.sort(partyIds)
	for _, partyId in partyIds do
		syncInvitationRevisions(data, changedParties[partyId])
		emitChange(data, changedParties[partyId], "InvitationChanged", "InvitationExpired", false)
	end
end

local function partyForUser(data: ServiceData, userId: number): PartyRecord?
	local partyId = data.partyIdByUserId[userId]
	return if partyId == nil then nil else data.partiesById[partyId]
end

local function invitationCount(party: PartyRecord): number
	local count = 0
	for _ in party.invitationIds do
		count += 1
	end
	return count
end

local function snapshot(data: ServiceData, userId: number): PartyProtocol.ViewerSnapshot
	local party = partyForUser(data, userId)
	local partyView: PartyProtocol.PartyView? = nil
	if party ~= nil then
		local members: { PartyProtocol.MemberView } = table.create(#party.members)
		for order, memberUserId in party.members do
			members[order] = table.freeze({
				userId = memberUserId,
				order = order,
				isLeader = memberUserId == party.leaderUserId,
				profileReady = profileReady(data, memberUserId),
			})
		end
		partyView = table.freeze({
			version = PartyProtocol.VERSION,
			partyId = party.partyId,
			revision = party.revision,
			leaderUserId = party.leaderUserId,
			privacy = party.privacy,
			queueState = queueState(data, party.members),
			members = table.freeze(members),
			pendingInvitationCount = invitationCount(party),
		})
	end

	local incomingIds: { string } = {}
	for invitationId in data.incomingByUserId[userId] or {} do
		table.insert(incomingIds, invitationId)
	end
	table.sort(incomingIds)
	local incoming: { PartyProtocol.InvitationView } = table.create(#incomingIds)
	for index, invitationId in incomingIds do
		local invitation = data.invitationsById[invitationId]
		if invitation ~= nil then
			incoming[index] = table.freeze({
				invitationId = invitation.invitationId,
				partyId = invitation.partyId,
				partyRevision = invitation.partyRevision,
				inviterUserId = invitation.inviterUserId,
				targetUserId = invitation.targetUserId,
				createdAt = invitation.createdAt,
				expiresAt = invitation.expiresAt,
			})
		end
	end
	local value: PartyProtocol.ViewerSnapshot = table.freeze({
		version = PartyProtocol.VERSION,
		party = partyView,
		incomingInvitations = table.freeze(incoming),
	})
	local validated = PartyProtocol.validateViewerSnapshot(value)
	if not validated.ok then
		error("[ATD_PARTY_SERVICE][code=INVALID_SNAPSHOT]", 0)
	end
	return validated.value
end

local function receiptLedger(data: ServiceData, userId: number): ReceiptLedger
	local ledger = data.receiptsByUserId[userId]
	if ledger == nil then
		ledger = { byId = {}, ring = {}, count = 0, nextIndex = 1 }
		data.receiptsByUserId[userId] = ledger
	end
	return ledger
end

local function replay(
	data: ServiceData,
	userId: number,
	transactionId: string,
	kind: PartyProtocol.MutationKind,
	fingerprint: string,
	operation: string
): Result.Result<PartyProtocol.MutationReceipt?, ServiceError>
	local ledger = data.receiptsByUserId[userId]
	local stored = if ledger == nil then nil else ledger.byId[transactionId]
	if stored == nil then
		return Result.ok(nil)
	end
	if stored.kind ~= kind or stored.fingerprint ~= fingerprint then
		return failure("TRANSACTION_CONFLICT", operation)
	end
	return Result.ok(stored.receipt)
end

local function storeReceipt(data: ServiceData, userId: number, stored: StoredReceipt)
	local transactionId = stored.receipt.transactionId
	local ledger = receiptLedger(data, userId)
	if ledger.byId[transactionId] ~= nil then
		return
	end
	if ledger.count == PartyProtocol.MAX_RECEIPTS_PER_ACTOR then
		local evicted = ledger.ring[ledger.nextIndex]
		if evicted ~= nil then
			ledger.byId[evicted] = nil
		end
	else
		ledger.count += 1
	end
	ledger.ring[ledger.nextIndex] = transactionId
	ledger.byId[transactionId] = stored
	ledger.nextIndex = (ledger.nextIndex % PartyProtocol.MAX_RECEIPTS_PER_ACTOR) + 1
end

local function makeReceipt(
	data: ServiceData,
	userId: number,
	transactionId: string,
	kind: PartyProtocol.MutationKind,
	fingerprint: string,
	reason: PartyProtocol.PublicReason,
	changed: boolean
): PartyProtocol.MutationReceipt
	local viewer = snapshot(data, userId)
	local revision = if viewer.party == nil then 0 else viewer.party.revision
	local value: PartyProtocol.MutationReceipt = table.freeze({
		transactionId = transactionId,
		kind = kind,
		reason = reason,
		changed = changed,
		partyRevision = revision,
		snapshot = viewer,
	})
	local validated = PartyProtocol.validateMutationReceipt(value)
	if not validated.ok then
		error("[ATD_PARTY_SERVICE][code=INVALID_RECEIPT]", 0)
	end
	storeReceipt(data, userId, { kind = kind, fingerprint = fingerprint, receipt = validated.value })
	return validated.value
end

local function generatedId(
	callback: () -> unknown,
	validator: (unknown) -> boolean,
	existing: { [string]: any }
): string?
	local called, value = callNonYielding(callback)
	if not called or not validator(value) or existing[value :: string] ~= nil then
		return nil
	end
	return value :: string
end

local function removeMember(party: PartyRecord, userId: number): boolean
	for index, memberUserId in party.members do
		if memberUserId == userId then
			table.remove(party.members, index)
			return true
		end
	end
	return false
end

local function disband(data: ServiceData, party: PartyRecord)
	clearPartyInvitations(data, party)
	for _, userId in party.members do
		data.partyIdByUserId[userId] = nil
	end
	data.partiesById[party.partyId] = nil
end

local function enter(data: ServiceData, operation: string): ServiceError?
	if data.busy then
		return { code = "REENTRANT", operation = operation }
	end
	data.busy = true
	return nil
end

local function finish(data: ServiceData)
	data.busy = false
end

local function prepare(
	data: ServiceData,
	userIdValue: unknown,
	operation: string
): (number?, number?, Result.Failure<ServiceError>?)
	if not validUserId(userIdValue) then
		return nil, nil, failure("INVALID_USER_ID", operation)
	end
	local currentTime = now(data)
	if currentTime == nil then
		return nil, nil, failure("UNAVAILABLE", operation)
	end
	expireInvitations(data, currentTime)
	local userId = userIdValue :: number
	local present = isPresent(data, userId)
	if present == nil then
		return nil, nil, failure("UNAVAILABLE", operation)
	elseif not present then
		return nil, nil, failure("NOT_PRESENT", operation)
	end
	return userId, currentTime, nil
end

function Methods.getSnapshot(
	self: Service,
	userIdValue: unknown
): Result.Result<PartyProtocol.ViewerSnapshot, ServiceError>
	local data = requireData(self)
	local busyError = enter(data, "getSnapshot")
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local userId, _currentTime, preparedError = prepare(data, userIdValue, "getSnapshot")
	if preparedError ~= nil then
		finish(data)
		return preparedError
	end
	local value = snapshot(data, userId :: number)
	finish(data)
	return Result.ok(value)
end

function Methods.getPartyForUser(self: Service, userIdValue: unknown): PartyEnrollment?
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return nil
	end
	local party = partyForUser(data, userIdValue :: number)
	if party == nil then
		return nil
	end
	return table.freeze({
		partyId = party.partyId,
		revision = party.revision,
		leaderUserId = party.leaderUserId,
		members = copyMembers(party.members),
	})
end

function Methods.reconstruct(
	self: Service,
	priorLeaderUserIdValue: unknown,
	orderedPresentUserIdsValue: unknown
): Result.Result<PartyEnrollment, ServiceError>
	local data = requireData(self)
	local operation = "reconstruct"
	if
		not validUserId(priorLeaderUserIdValue)
		or type(orderedPresentUserIdsValue) ~= "table"
		or getmetatable(orderedPresentUserIdsValue :: any) ~= nil
	then
		return failure("RECONSTRUCTION_UNAVAILABLE", operation)
	end
	local raw = orderedPresentUserIdsValue :: { [any]: unknown }
	local count = 0
	local maximum = 0
	local seen: { [number]: boolean } = {}
	local input: { number } = {}
	local leaderFound = false
	for key, userIdValue in raw do
		if
			type(key) ~= "number"
			or not Validation.isSafeInteger(key)
			or key < 1
			or key > PartyProtocol.MAX_MEMBERS
			or not validUserId(userIdValue)
			or seen[userIdValue :: number]
		then
			return failure("RECONSTRUCTION_UNAVAILABLE", operation)
		end
		count += 1
		maximum = math.max(maximum, key)
		seen[userIdValue :: number] = true
		leaderFound = leaderFound or userIdValue == priorLeaderUserIdValue
		input[key] = userIdValue :: number
	end
	if count < 2 or maximum ~= count or not leaderFound then
		return failure("RECONSTRUCTION_UNAVAILABLE", operation)
	end
	local busyError = enter(data, operation)
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local currentTime = now(data)
	if currentTime == nil then
		finish(data)
		return failure("UNAVAILABLE", operation)
	end
	expireInvitations(data, currentTime)
	for _, userId in input do
		local present = isPresent(data, userId)
		if present ~= true or not profileReady(data, userId) or partyForUser(data, userId) ~= nil then
			finish(data)
			return failure("RECONSTRUCTION_UNAVAILABLE", operation)
		end
	end
	local partyId = generatedId(data.dependencies.makePartyId, PartyProtocol.isPartyId, data.partiesById)
	if partyId == nil then
		finish(data)
		return failure("ID_COLLISION", operation)
	end
	local leaderUserId = priorLeaderUserIdValue :: number
	local members: { number } = { leaderUserId }
	for _, userId in input do
		if userId ~= leaderUserId then
			table.insert(members, userId)
		end
	end
	local affectedInvitationParties: { [string]: PartyRecord } = {}
	for _, userId in members do
		local invitationIds: { string } = {}
		for invitationId in data.incomingByUserId[userId] or {} do
			table.insert(invitationIds, invitationId)
		end
		table.sort(invitationIds)
		for _, invitationId in invitationIds do
			local invitation = removeInvitation(data, invitationId)
			local invitationParty = if invitation == nil then nil else data.partiesById[invitation.partyId]
			if invitationParty ~= nil and incrementRevision(invitationParty) then
				affectedInvitationParties[invitationParty.partyId] = invitationParty
			end
		end
		data.receiptsByUserId[userId] = nil
	end
	local affectedIds: { string } = {}
	for affectedPartyId in affectedInvitationParties do
		table.insert(affectedIds, affectedPartyId)
	end
	table.sort(affectedIds)
	for _, affectedPartyId in affectedIds do
		local affected = affectedInvitationParties[affectedPartyId]
		syncInvitationRevisions(data, affected)
		emitChange(data, affected, "InvitationChanged", "InvitationRevoked", false)
	end
	local party: PartyRecord = {
		partyId = partyId,
		revision = 1,
		leaderUserId = leaderUserId,
		members = members,
		privacy = "InviteOnly",
		invitationIds = {},
	}
	data.partiesById[partyId] = party
	for _, userId in members do
		data.partyIdByUserId[userId] = partyId
	end
	emitChange(data, party, "Created", "PartyCreated", true)
	local enrollment = table.freeze({
		partyId = partyId,
		revision = 1,
		leaderUserId = leaderUserId,
		members = copyMembers(members),
	})
	finish(data)
	return Result.ok(enrollment)
end

function Methods.create(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<PartyProtocol.MutationReceipt, ServiceError>
	local data = requireData(self)
	local operation = "create"
	local intentResult = PartyProtocol.CreateIntentSchema:validate(intentValue)
	if not intentResult.ok then
		return failure("INVALID_INTENT", operation)
	end
	local intent = intentResult.value :: PartyProtocol.CreateIntent
	local fingerprint = `create|{intent.expectedRevision}|{intent.privacy}`
	local busyError = enter(data, operation)
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local userId, _currentTime, preparedError = prepare(data, userIdValue, operation)
	if preparedError ~= nil then
		finish(data)
		return preparedError
	end
	local replayed = replay(data, userId :: number, intent.transactionId, "Create", fingerprint, operation)
	if not replayed.ok or replayed.value ~= nil then
		finish(data)
		return if replayed.ok then Result.ok(replayed.value :: PartyProtocol.MutationReceipt) else replayed
	end
	if intent.expectedRevision ~= 0 then
		finish(data)
		return failure("STALE_REVISION", operation)
	end
	if partyForUser(data, userId :: number) ~= nil then
		finish(data)
		return failure("ALREADY_MEMBER", operation)
	end
	local partyId = generatedId(data.dependencies.makePartyId, PartyProtocol.isPartyId, data.partiesById)
	if partyId == nil then
		finish(data)
		return failure("ID_COLLISION", operation)
	end
	local party: PartyRecord = {
		partyId = partyId,
		revision = 1,
		leaderUserId = userId :: number,
		members = { userId :: number },
		privacy = intent.privacy,
		invitationIds = {},
	}
	data.partiesById[partyId] = party
	data.partyIdByUserId[userId :: number] = partyId
	emitChange(data, party, "Created", "PartyCreated", true)
	local receipt =
		makeReceipt(data, userId :: number, intent.transactionId, "Create", fingerprint, "PartyCreated", true)
	finish(data)
	return Result.ok(receipt)
end

function Methods.invite(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<PartyProtocol.MutationReceipt, ServiceError>
	local data = requireData(self)
	local operation = "invite"
	local intentResult = PartyProtocol.InviteIntentSchema:validate(intentValue)
	if not intentResult.ok then
		return failure("INVALID_INTENT", operation)
	end
	local intent = intentResult.value :: PartyProtocol.InviteIntent
	local fingerprint = `invite|{intent.expectedRevision}|{intent.targetUserId}`
	local busyError = enter(data, operation)
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local userId, currentTime, preparedError = prepare(data, userIdValue, operation)
	if preparedError ~= nil then
		finish(data)
		return preparedError
	end
	local replayed = replay(data, userId :: number, intent.transactionId, "Invite", fingerprint, operation)
	if not replayed.ok or replayed.value ~= nil then
		finish(data)
		return if replayed.ok then Result.ok(replayed.value :: PartyProtocol.MutationReceipt) else replayed
	end
	local party = partyForUser(data, userId :: number)
	if party == nil then
		finish(data)
		return failure("NOT_IN_PARTY", operation)
	elseif party.leaderUserId ~= userId then
		finish(data)
		return failure("NOT_LEADER", operation)
	elseif party.revision ~= intent.expectedRevision then
		finish(data)
		return failure("STALE_REVISION", operation)
	elseif #party.members >= PartyProtocol.MAX_MEMBERS then
		finish(data)
		return failure("PARTY_FULL", operation)
	elseif invitationCount(party) >= PartyProtocol.MAX_PENDING_INVITATIONS then
		finish(data)
		return failure("TOO_MANY_INVITATIONS", operation)
	end
	local targetPresent = isPresent(data, intent.targetUserId)
	if targetPresent == nil then
		finish(data)
		return failure("UNAVAILABLE", operation)
	elseif not targetPresent then
		finish(data)
		return failure("TARGET_NOT_PRESENT", operation)
	elseif partyForUser(data, intent.targetUserId) ~= nil then
		finish(data)
		return failure("TARGET_ALREADY_MEMBER", operation)
	end
	local permitted = canInvite(data, userId :: number, intent.targetUserId)
	if permitted == nil then
		finish(data)
		return failure("UNAVAILABLE", operation)
	elseif not permitted then
		finish(data)
		return failure("PERMISSION_DENIED", operation)
	end
	local incoming = data.incomingByUserId[intent.targetUserId]
	local incomingCount = 0
	for _ in incoming or {} do
		incomingCount += 1
	end
	if incomingCount >= PartyProtocol.MAX_INCOMING_INVITATIONS then
		finish(data)
		return failure("TOO_MANY_INVITATIONS", operation)
	end
	for invitationId in party.invitationIds do
		local existing = data.invitationsById[invitationId]
		if existing ~= nil and existing.targetUserId == intent.targetUserId then
			local receipt = makeReceipt(
				data,
				userId :: number,
				intent.transactionId,
				"Invite",
				fingerprint,
				"InvitationAlreadyPending",
				false
			)
			finish(data)
			return Result.ok(receipt)
		end
	end
	if not incrementRevision(party) then
		finish(data)
		return failure("REVISION_EXHAUSTED", operation)
	end
	syncInvitationRevisions(data, party)
	local invitationId =
		generatedId(data.dependencies.makeInvitationId, PartyProtocol.isInvitationId, data.invitationsById)
	if invitationId == nil then
		party.revision -= 1
		finish(data)
		return failure("ID_COLLISION", operation)
	end
	local invitation: InvitationRecord = {
		invitationId = invitationId,
		partyId = party.partyId,
		partyRevision = party.revision,
		inviterUserId = userId :: number,
		targetUserId = intent.targetUserId,
		createdAt = currentTime :: number,
		expiresAt = (currentTime :: number) + data.invitationLifetimeSeconds,
	}
	data.invitationsById[invitationId] = invitation
	party.invitationIds[invitationId] = true
	incoming = incoming or {}
	data.incomingByUserId[intent.targetUserId] = incoming
	incoming[invitationId] = true
	emitChange(data, party, "InvitationChanged", "InvitationSent", false)
	local receipt =
		makeReceipt(data, userId :: number, intent.transactionId, "Invite", fingerprint, "InvitationSent", true)
	finish(data)
	return Result.ok(receipt)
end

local function invitationMutation(
	data: ServiceData,
	userIdValue: unknown,
	intentValue: unknown,
	kind: "Accept" | "Decline"
): Result.Result<PartyProtocol.MutationReceipt, ServiceError>
	local operation = string.lower(kind)
	local intentResult = PartyProtocol.InvitationIntentSchema:validate(intentValue)
	if not intentResult.ok then
		return failure("INVALID_INTENT", operation)
	end
	local intent = intentResult.value :: PartyProtocol.InvitationIntent
	if not PartyProtocol.isInvitationId(intent.invitationId) then
		return failure("INVALID_INTENT", operation)
	end
	local fingerprint = `{operation}|{intent.expectedRevision}|{intent.invitationId}`
	local busyError = enter(data, operation)
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local userId, currentTime, preparedError = prepare(data, userIdValue, operation)
	if preparedError ~= nil then
		finish(data)
		return preparedError
	end
	local replayed = replay(data, userId :: number, intent.transactionId, kind, fingerprint, operation)
	if not replayed.ok or replayed.value ~= nil then
		finish(data)
		return if replayed.ok then Result.ok(replayed.value :: PartyProtocol.MutationReceipt) else replayed
	end
	local invitation = data.invitationsById[intent.invitationId]
	if invitation == nil or invitation.targetUserId ~= userId then
		finish(data)
		return failure("INVITATION_NOT_FOUND", operation)
	elseif invitation.expiresAt <= (currentTime :: number) then
		removeInvitation(data, invitation.invitationId)
		finish(data)
		return failure("INVITATION_EXPIRED", operation)
	elseif invitation.partyRevision ~= intent.expectedRevision then
		finish(data)
		return failure("STALE_REVISION", operation)
	end
	local party = data.partiesById[invitation.partyId]
	if party == nil then
		removeInvitation(data, invitation.invitationId)
		finish(data)
		return failure("INVITATION_NOT_FOUND", operation)
	elseif party.revision ~= intent.expectedRevision then
		finish(data)
		return failure("STALE_REVISION", operation)
	end
	if kind == "Decline" then
		removeInvitation(data, invitation.invitationId)
		if not incrementRevision(party) then
			finish(data)
			return failure("REVISION_EXHAUSTED", operation)
		end
		syncInvitationRevisions(data, party)
		emitChange(data, party, "InvitationChanged", "InvitationDeclined", false)
		local receipt =
			makeReceipt(data, userId :: number, intent.transactionId, kind, fingerprint, "InvitationDeclined", true)
		finish(data)
		return Result.ok(receipt)
	end
	if partyForUser(data, userId :: number) ~= nil then
		finish(data)
		return failure("ALREADY_MEMBER", operation)
	elseif #party.members >= PartyProtocol.MAX_MEMBERS then
		finish(data)
		return failure("PARTY_FULL", operation)
	end
	local inviterPresent = isPresent(data, invitation.inviterUserId)
	local permitted = canInvite(data, invitation.inviterUserId, userId :: number)
	if inviterPresent == nil or permitted == nil then
		finish(data)
		return failure("UNAVAILABLE", operation)
	elseif not inviterPresent or not permitted then
		clearPartyInvitations(data, party)
		if incrementRevision(party) then
			emitChange(data, party, "InvitationChanged", "InvitationRevoked", false)
		end
		finish(data)
		return failure("PERMISSION_DENIED", operation)
	end
	if party.revision >= Validation.MAX_SAFE_INTEGER then
		finish(data)
		return failure("REVISION_EXHAUSTED", operation)
	end
	clearPartyInvitations(data, party)
	table.insert(party.members, userId :: number)
	data.partyIdByUserId[userId :: number] = party.partyId
	party.revision += 1
	emitChange(data, party, "MembershipChanged", "InvitationAccepted", true)
	local receipt =
		makeReceipt(data, userId :: number, intent.transactionId, kind, fingerprint, "InvitationAccepted", true)
	finish(data)
	return Result.ok(receipt)
end

function Methods.accept(self: Service, userIdValue: unknown, intentValue: unknown)
	return invitationMutation(requireData(self), userIdValue, intentValue, "Accept")
end

function Methods.decline(self: Service, userIdValue: unknown, intentValue: unknown)
	return invitationMutation(requireData(self), userIdValue, intentValue, "Decline")
end

local function partyMutation(
	data: ServiceData,
	userIdValue: unknown,
	intentValue: unknown,
	kind: "Leave" | "Kick" | "TransferLeadership" | "SetPrivacy" | "Disband"
): Result.Result<PartyProtocol.MutationReceipt, ServiceError>
	local operation = if kind == "TransferLeadership" then "transferLeadership" else string.lower(kind)
	local schema = if kind == "Kick" or kind == "TransferLeadership"
		then PartyProtocol.MemberIntentSchema
		elseif kind == "SetPrivacy" then PartyProtocol.PrivacyIntentSchema
		else PartyProtocol.RevisionIntentSchema
	local intentResult = schema:validate(intentValue)
	if not intentResult.ok then
		return failure("INVALID_INTENT", operation)
	end
	local intent = intentResult.value :: any
	local fingerprint = if kind == "Kick" or kind == "TransferLeadership"
		then `{operation}|{intent.expectedRevision}|{intent.targetUserId}`
		elseif kind == "SetPrivacy" then `{operation}|{intent.expectedRevision}|{intent.privacy}`
		else `{operation}|{intent.expectedRevision}`
	local busyError = enter(data, operation)
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local userId, _currentTime, preparedError = prepare(data, userIdValue, operation)
	if preparedError ~= nil then
		finish(data)
		return preparedError
	end
	local replayed = replay(data, userId :: number, intent.transactionId, kind, fingerprint, operation)
	if not replayed.ok or replayed.value ~= nil then
		finish(data)
		return if replayed.ok then Result.ok(replayed.value :: PartyProtocol.MutationReceipt) else replayed
	end
	local party = partyForUser(data, userId :: number)
	if party == nil then
		finish(data)
		return failure("NOT_IN_PARTY", operation)
	elseif party.revision ~= intent.expectedRevision then
		finish(data)
		return failure("STALE_REVISION", operation)
	end
	if kind ~= "Leave" and party.leaderUserId ~= userId then
		finish(data)
		return failure("NOT_LEADER", operation)
	end
	if kind == "SetPrivacy" then
		local changed = party.privacy ~= intent.privacy
		if changed then
			if not incrementRevision(party) then
				finish(data)
				return failure("REVISION_EXHAUSTED", operation)
			end
			party.privacy = intent.privacy
			syncInvitationRevisions(data, party)
			emitChange(data, party, "InvitationChanged", "PrivacyChanged", false)
		end
		local reason: PartyProtocol.PublicReason = if changed then "PrivacyChanged" else "PrivacyUnchanged"
		local receipt = makeReceipt(data, userId :: number, intent.transactionId, kind, fingerprint, reason, changed)
		finish(data)
		return Result.ok(receipt)
	end
	if kind == "TransferLeadership" then
		local targetIsMember = false
		for _, memberUserId in party.members do
			targetIsMember = targetIsMember or memberUserId == intent.targetUserId
		end
		if not targetIsMember then
			finish(data)
			return failure("TARGET_ALREADY_MEMBER", operation)
		elseif intent.targetUserId == userId then
			local receipt = makeReceipt(
				data,
				userId :: number,
				intent.transactionId,
				kind,
				fingerprint,
				"LeadershipUnchanged",
				false
			)
			finish(data)
			return Result.ok(receipt)
		end
		if not incrementRevision(party) then
			finish(data)
			return failure("REVISION_EXHAUSTED", operation)
		end
		clearPartyInvitations(data, party)
		party.leaderUserId = intent.targetUserId
		for index, memberUserId in party.members do
			if memberUserId == intent.targetUserId then
				table.remove(party.members, index)
				table.insert(party.members, 1, memberUserId)
				break
			end
		end
		emitChange(data, party, "MembershipChanged", "LeadershipTransferred", true)
		local receipt =
			makeReceipt(data, userId :: number, intent.transactionId, kind, fingerprint, "LeadershipTransferred", true)
		finish(data)
		return Result.ok(receipt)
	end
	if kind == "Disband" then
		if not incrementRevision(party) then
			finish(data)
			return failure("REVISION_EXHAUSTED", operation)
		end
		emitChange(data, party, "Disbanded", "LeaderDisbanded", true)
		disband(data, party)
		local receipt =
			makeReceipt(data, userId :: number, intent.transactionId, kind, fingerprint, "LeaderDisbanded", true)
		finish(data)
		return Result.ok(receipt)
	end

	local targetUserId = if kind == "Kick" then intent.targetUserId else userId
	if kind == "Kick" and targetUserId == userId then
		finish(data)
		return failure("NOT_LEADER", operation)
	end
	if not removeMember(party, targetUserId) then
		finish(data)
		return failure("TARGET_ALREADY_MEMBER", operation)
	end
	data.partyIdByUserId[targetUserId] = nil
	clearPartyInvitations(data, party)
	if #party.members == 0 then
		if not incrementRevision(party) then
			finish(data)
			return failure("REVISION_EXHAUSTED", operation)
		end
		emitChange(data, party, "Disbanded", "LastMemberLeft", true)
		disband(data, party)
	else
		if party.leaderUserId == targetUserId then
			party.leaderUserId = party.members[1]
		end
		if not incrementRevision(party) then
			finish(data)
			return failure("REVISION_EXHAUSTED", operation)
		end
		local reason: PartyProtocol.PublicReason = if kind == "Kick" then "MemberKicked" else "MemberLeft"
		emitChange(data, party, "MembershipChanged", reason, true)
	end
	local reason: PartyProtocol.PublicReason = if kind == "Kick" then "MemberKicked" else "MemberLeft"
	if #party.members == 0 then
		reason = "LastMemberLeft"
	end
	local receipt = makeReceipt(data, userId :: number, intent.transactionId, kind, fingerprint, reason, true)
	finish(data)
	return Result.ok(receipt)
end

function Methods.leave(self: Service, userIdValue: unknown, intentValue: unknown)
	return partyMutation(requireData(self), userIdValue, intentValue, "Leave")
end

function Methods.kick(self: Service, userIdValue: unknown, intentValue: unknown)
	return partyMutation(requireData(self), userIdValue, intentValue, "Kick")
end

function Methods.transferLeadership(self: Service, userIdValue: unknown, intentValue: unknown)
	return partyMutation(requireData(self), userIdValue, intentValue, "TransferLeadership")
end

function Methods.setPrivacy(self: Service, userIdValue: unknown, intentValue: unknown)
	return partyMutation(requireData(self), userIdValue, intentValue, "SetPrivacy")
end

function Methods.disband(self: Service, userIdValue: unknown, intentValue: unknown)
	return partyMutation(requireData(self), userIdValue, intentValue, "Disband")
end

function Methods.removePlayer(
	self: Service,
	userIdValue: unknown,
	reasonValue: RemovalReason?
): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	local operation = "removePlayer"
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", operation)
	end
	local removalReason = reasonValue or "Disconnected"
	if removalReason ~= "Disconnected" and removalReason ~= "ServerLeave" then
		return failure("INVALID_INTENT", operation)
	end
	local publicReason: PartyProtocol.PublicReason = if removalReason == "ServerLeave"
		then "MemberServerLeft"
		else "MemberDisconnected"
	local busyError = enter(data, operation)
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local userId = userIdValue :: number
	local incomingIds: { string } = {}
	for invitationId in data.incomingByUserId[userId] or {} do
		table.insert(incomingIds, invitationId)
	end
	table.sort(incomingIds)
	for _, invitationId in incomingIds do
		local removed = removeInvitation(data, invitationId)
		local invitationParty = if removed == nil then nil else data.partiesById[removed.partyId]
		if invitationParty ~= nil and incrementRevision(invitationParty) then
			syncInvitationRevisions(data, invitationParty)
			emitChange(data, invitationParty, "InvitationChanged", "InvitationRevoked", false)
		end
	end
	local party = partyForUser(data, userId)
	if party ~= nil then
		removeMember(party, userId)
		data.partyIdByUserId[userId] = nil
		clearPartyInvitations(data, party)
		if #party.members == 0 then
			if incrementRevision(party) then
				emitChange(data, party, "Disbanded", publicReason, true)
			end
			disband(data, party)
		else
			if party.leaderUserId == userId then
				party.leaderUserId = party.members[1]
			end
			if incrementRevision(party) then
				emitChange(data, party, "MembershipChanged", publicReason, true)
			end
		end
	end
	data.receiptsByUserId[userId] = nil
	finish(data)
	return Result.ok(party ~= nil or #incomingIds > 0)
end

function Methods.cleanup(self: Service): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	local busyError = enter(data, "cleanup")
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local partyIds: { string } = {}
	for partyId in data.partiesById do
		table.insert(partyIds, partyId)
	end
	table.sort(partyIds)
	for _, partyId in partyIds do
		local party = data.partiesById[partyId]
		if party == nil then
			continue
		end
		emitChange(data, party, "Disbanded", "ServerShutdown", true)
		clearPartyInvitations(data, party)
		table.clear(party.members)
		table.clear(party.invitationIds)
	end
	table.clear(data.partiesById)
	table.clear(data.partyIdByUserId)
	table.clear(data.invitationsById)
	table.clear(data.incomingByUserId)
	table.clear(data.receiptsByUserId)
	finish(data)
	return Result.ok(true)
end

function Methods.getMetrics(self: Service): { [string]: number }
	local data = requireData(self)
	local partyCount = 0
	local memberCount = 0
	local invitationCountValue = 0
	local receiptCount = 0
	for _, party in data.partiesById do
		partyCount += 1
		memberCount += #party.members
	end
	for _ in data.invitationsById do
		invitationCountValue += 1
	end
	for _, ledger in data.receiptsByUserId do
		receiptCount += ledger.count
	end
	return table.freeze({
		partyCount = partyCount,
		memberCount = memberCount,
		invitationCount = invitationCountValue,
		receiptCount = receiptCount,
		callbackFailureCount = data.callbackFailureCount,
	})
end

function PartyService.new(dependenciesValue: unknown): Result.Result<Service, ServiceError>
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local dependencies = dependenciesValue :: any
	if
		type(dependencies.clock) ~= "function"
		or type(dependencies.makePartyId) ~= "function"
		or type(dependencies.makeInvitationId) ~= "function"
		or type(dependencies.isPresent) ~= "function"
		or type(dependencies.canInvite) ~= "function"
		or (dependencies.isProfileReady ~= nil and type(dependencies.isProfileReady) ~= "function")
		or (dependencies.getQueueState ~= nil and type(dependencies.getQueueState) ~= "function")
		or (dependencies.onChanged ~= nil and type(dependencies.onChanged) ~= "function")
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local lifetime = dependencies.invitationLifetimeSeconds or DEFAULT_INVITATION_LIFETIME_SECONDS
	if
		type(lifetime) ~= "number"
		or not Validation.isSafeInteger(lifetime)
		or lifetime < MIN_INVITATION_LIFETIME_SECONDS
		or lifetime > MAX_INVITATION_LIFETIME_SECONDS
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		dependencies = dependenciesValue :: Dependencies,
		invitationLifetimeSeconds = lifetime,
		partiesById = {},
		partyIdByUserId = {},
		invitationsById = {},
		incomingByUserId = {},
		receiptsByUserId = {},
		busy = false,
		callbackFailureCount = 0,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(PartyService)
