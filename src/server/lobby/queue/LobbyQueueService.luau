--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local PartyProtocol = require(ReplicatedStorage.Shared.party.PartyProtocol)
local QueueProtocol = require(ReplicatedStorage.Shared.queue.QueueProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type QueueDefinition = {
	queueId: string,
	configuration: QueueProtocol.Configuration?,
}

export type PartyEnrollment = {
	partyId: string,
	revision: number,
	leaderUserId: number,
	members: { number },
}

export type Eligibility = {
	profileReady: boolean,
	sessionOwned: boolean,
	loadoutReady: boolean,
	ticketEligible: boolean,
	loadout: unknown?,
}

export type LockedMember = {
	userId: number,
	loadout: unknown,
}

export type LockedStart = {
	queueId: string,
	revision: number,
	captainUserId: number,
	configuration: QueueProtocol.Configuration,
	orderedUserIds: { number },
	members: { LockedMember },
}

export type Dependencies = {
	isPresent: (number) -> unknown,
	getParty: (number) -> unknown,
	getEligibility: (number) -> unknown,
	beginStart: (LockedStart) -> unknown,
	onChanged: ((string, QueueProtocol.Snapshot) -> ())?,
}

export type ErrorCode =
	"INVALID_CONFIGURATION"
	| "INVALID_DEFINITIONS"
	| "INVALID_DEPENDENCIES"
	| "INVALID_USER_ID"
	| "INVALID_INTENT"
	| "QUEUE_NOT_FOUND"
	| "NOT_PRESENT"
	| "PROFILE_NOT_READY"
	| "ALREADY_QUEUED"
	| "NOT_QUEUED"
	| "NOT_PARTY_LEADER"
	| "INVALID_PARTY"
	| "PARTY_CHANGED"
	| "QUEUE_FULL"
	| "PRIVACY_RESTRICTED"
	| "NOT_CAPTAIN"
	| "STALE_REVISION"
	| "QUEUE_LOCKED"
	| "INVALID_SELECTION"
	| "INVALID_LOADOUT"
	| "NOT_ELIGIBLE"
	| "START_FAILED"
	| "TRANSACTION_CONFLICT"
	| "REVISION_EXHAUSTED"
	| "SEQUENCE_EXHAUSTED"
	| "REENTRANT"
	| "UNAVAILABLE"

export type ServiceError = {
	code: ErrorCode,
	operation: string,
}

type Enrollment = {
	sequence: number,
	kind: QueueProtocol.EnrollmentKind,
	leaderUserId: number,
	partyId: string?,
	partyRevision: number?,
	userIds: { number },
	source: QueueProtocol.Source,
}

type QueueRecord = {
	queueId: string,
	revision: number,
	state: QueueProtocol.State,
	publicStatus: QueueProtocol.PublicStatus?,
	configuration: QueueProtocol.Configuration,
	defaultConfiguration: QueueProtocol.Configuration,
	enrollments: { Enrollment },
	nextSequence: number,
	lockedStart: LockedStart?,
}

type StoredReceipt = {
	kind: QueueProtocol.MutationKind,
	fingerprint: string,
	receipt: QueueProtocol.MutationReceipt,
}

type ReceiptLedger = {
	byId: { [string]: StoredReceipt },
	ring: { string? },
	count: number,
	nextIndex: number,
}

type ServiceData = {
	configuration: ConfigTypes.CoreConfiguration,
	dependencies: Dependencies,
	queuesById: { [string]: QueueRecord },
	queueIds: { string },
	queueIdByUserId: { [number]: string },
	receiptsByUserId: { [number]: ReceiptLedger },
	busy: boolean,
	callbackFailureCount: number,
}

local Methods = {}
Methods.__index = Methods
export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local MAX_LOCKED_NODES = 256
local MAX_LOCKED_DEPTH = 8

local LobbyQueueService = {}

local function failure<T>(code: ErrorCode, operation: string): Result.Failure<ServiceError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_LOBBY_QUEUE_SERVICE][code=INVALID_CONTEXT]", 0)
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

local function dependencyBoolean(callback: (...any) -> unknown, ...: any): boolean?
	local called, value = callNonYielding(callback, ...)
	return if called and type(value) == "boolean" then value :: boolean else nil
end

local function present(data: ServiceData, userId: number): boolean?
	return dependencyBoolean(data.dependencies.isPresent, userId)
end

local function plainExact(value: unknown, fields: { [string]: boolean }): { [string]: unknown }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local record = value :: { [any]: unknown }
	local count = 0
	local required = 0
	for _ in fields do
		required += 1
	end
	for key in record do
		if type(key) ~= "string" or fields[key] ~= true then
			return nil
		end
		count += 1
	end
	return if count == required then record :: { [string]: unknown } else nil
end

local function readParty(data: ServiceData, userId: number): PartyEnrollment?
	local called, value = callNonYielding(data.dependencies.getParty, userId)
	if not called or value == nil then
		return nil
	end
	local record = plainExact(value, {
		partyId = true,
		revision = true,
		leaderUserId = true,
		members = true,
	})
	if
		record == nil
		or not PartyProtocol.isPartyId(record.partyId)
		or type(record.revision) ~= "number"
		or not Validation.isSafeInteger(record.revision :: number)
		or (record.revision :: number) < 1
		or not validUserId(record.leaderUserId)
		or type(record.members) ~= "table"
		or getmetatable(record.members :: any) ~= nil
	then
		return nil
	end
	local rawMembers = record.members :: { [any]: unknown }
	local count = 0
	local maximum = 0
	local seen: { [number]: boolean } = {}
	local members: { number } = {}
	for key, memberUserId in rawMembers do
		if
			type(key) ~= "number"
			or not Validation.isSafeInteger(key)
			or key < 1
			or key > QueueProtocol.MAX_PLAYERS
			or not validUserId(memberUserId)
			or seen[memberUserId :: number]
		then
			return nil
		end
		count += 1
		maximum = math.max(maximum, key)
		seen[memberUserId :: number] = true
		members[key] = memberUserId :: number
	end
	if count < 1 or maximum ~= count or members[1] ~= record.leaderUserId then
		return nil
	end
	return table.freeze({
		partyId = record.partyId :: string,
		revision = record.revision :: number,
		leaderUserId = record.leaderUserId :: number,
		members = table.freeze(members),
	})
end

local function readEligibility(data: ServiceData, userId: number): Eligibility?
	local called, value = callNonYielding(data.dependencies.getEligibility, userId)
	if not called or type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local record = value :: { [any]: unknown }
	local allowed = {
		profileReady = true,
		sessionOwned = true,
		loadoutReady = true,
		ticketEligible = true,
		loadout = true,
	}
	for key in record do
		if type(key) ~= "string" or allowed[key] ~= true then
			return nil
		end
	end
	if
		type(record.profileReady) ~= "boolean"
		or type(record.sessionOwned) ~= "boolean"
		or type(record.loadoutReady) ~= "boolean"
		or type(record.ticketEligible) ~= "boolean"
	then
		return nil
	end
	return {
		profileReady = record.profileReady :: boolean,
		sessionOwned = record.sessionOwned :: boolean,
		loadoutReady = record.loadoutReady :: boolean,
		ticketEligible = record.ticketEligible :: boolean,
		loadout = record.loadout,
	}
end

local function readiness(eligibility: Eligibility?): QueueProtocol.Readiness
	if eligibility == nil or not eligibility.ticketEligible then
		return "NotEligible"
	elseif not eligibility.profileReady then
		return "ProfileNotReady"
	elseif not eligibility.sessionOwned then
		return "SessionUnavailable"
	elseif not eligibility.loadoutReady then
		return "InvalidLoadout"
	end
	return "Ready"
end

local function configurationCopy(value: QueueProtocol.Configuration): QueueProtocol.Configuration
	return table.freeze({
		mapId = value.mapId,
		difficultyId = value.difficultyId,
		privacy = value.privacy,
		maxPlayers = value.maxPlayers,
	})
end

local function configurationValid(
	configuration: ConfigTypes.CoreConfiguration,
	value: QueueProtocol.Configuration
): boolean
	local map = configuration.maps.byId[value.mapId]
	if map == nil or configuration.difficulties.byId[value.difficultyId] == nil then
		return false
	end
	local supported = false
	for _, difficultyId in map.supportedDifficultyIds do
		supported = supported or difficultyId == value.difficultyId
	end
	return supported
		and (value.privacy == "Public" or value.privacy == "PartyOnly")
		and value.maxPlayers >= 1
		and value.maxPlayers <= QueueProtocol.MAX_PLAYERS
end

local function defaultConfiguration(configuration: ConfigTypes.CoreConfiguration): QueueProtocol.Configuration?
	for _, map in configuration.maps.ordered do
		for _, difficultyId in map.supportedDifficultyIds do
			if configuration.difficulties.byId[difficultyId] ~= nil then
				return configurationCopy({
					mapId = map.id,
					difficultyId = difficultyId,
					privacy = "Public",
					maxPlayers = QueueProtocol.MAX_PLAYERS,
				})
			end
		end
	end
	return nil
end

local function rosterCount(queue: QueueRecord): number
	local count = 0
	for _, enrollment in queue.enrollments do
		count += #enrollment.userIds
	end
	return count
end

local function privacyCompatible(queue: QueueRecord, privacy: QueueProtocol.Privacy): boolean
	-- PartyOnly represents one atomic enrollment unit: either a solo captain or
	-- one complete party. A mixed Public roster cannot be relabeled in place.
	return privacy ~= "PartyOnly" or #queue.enrollments <= 1
end

local function captainUserId(queue: QueueRecord): number?
	local first = queue.enrollments[1]
	return if first == nil then nil else first.leaderUserId
end

local function snapshot(data: ServiceData, queue: QueueRecord): QueueProtocol.Snapshot
	local enrollments: { QueueProtocol.EnrollmentView } = table.create(#queue.enrollments)
	local members: { QueueProtocol.MemberView } = {}
	local captain = captainUserId(queue)
	local allReady = #queue.enrollments > 0
	for enrollmentIndex, enrollment in queue.enrollments do
		enrollments[enrollmentIndex] = table.freeze({
			sequence = enrollment.sequence,
			kind = enrollment.kind,
			leaderUserId = enrollment.leaderUserId,
			partyId = enrollment.partyId,
			partyRevision = enrollment.partyRevision,
			userIds = table.freeze(table.clone(enrollment.userIds)),
			source = enrollment.source,
		})
		for _, userId in enrollment.userIds do
			local memberReadiness = readiness(readEligibility(data, userId))
			allReady = allReady and memberReadiness == "Ready"
			table.insert(
				members,
				table.freeze({
					userId = userId,
					order = #members + 1,
					isCaptain = userId == captain,
					readiness = memberReadiness,
				})
			)
		end
	end
	local value: QueueProtocol.Snapshot = table.freeze({
		version = QueueProtocol.VERSION,
		queueId = queue.queueId,
		revision = queue.revision,
		state = queue.state,
		publicStatus = queue.publicStatus,
		captainUserId = captain,
		configuration = configurationCopy(queue.configuration),
		members = table.freeze(members),
		enrollments = table.freeze(enrollments),
		canStart = queue.state == "Open" and allReady,
	})
	local validated = QueueProtocol.validateSnapshot(value)
	if not validated.ok then
		error("[ATD_LOBBY_QUEUE_SERVICE][code=INVALID_SNAPSHOT]", 0)
	end
	return validated.value
end

local function emitSnapshot(data: ServiceData, queue: QueueRecord)
	local callback = data.dependencies.onChanged
	if callback == nil then
		return
	end
	local value = snapshot(data, queue)
	local called = callNonYielding(callback, queue.queueId, value)
	if not called then
		data.callbackFailureCount += 1
	end
end

local function incrementRevision(queue: QueueRecord): boolean
	if queue.revision >= Validation.MAX_SAFE_INTEGER then
		return false
	end
	queue.revision += 1
	return true
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

local function ledger(data: ServiceData, userId: number): ReceiptLedger
	local value = data.receiptsByUserId[userId]
	if value == nil then
		value = { byId = {}, ring = {}, count = 0, nextIndex = 1 }
		data.receiptsByUserId[userId] = value
	end
	return value
end

local function replay(
	data: ServiceData,
	userId: number,
	transactionId: string,
	kind: QueueProtocol.MutationKind,
	fingerprint: string,
	operation: string
): Result.Result<QueueProtocol.MutationReceipt?, ServiceError>
	local actorLedger = data.receiptsByUserId[userId]
	local stored = if actorLedger == nil then nil else actorLedger.byId[transactionId]
	if stored == nil then
		return Result.ok(nil)
	end
	if stored.kind ~= kind or stored.fingerprint ~= fingerprint then
		return failure("TRANSACTION_CONFLICT", operation)
	end
	return Result.ok(stored.receipt)
end

local function storeReceipt(data: ServiceData, userId: number, value: StoredReceipt)
	local actorLedger = ledger(data, userId)
	local transactionId = value.receipt.transactionId
	if actorLedger.byId[transactionId] ~= nil then
		return
	end
	if actorLedger.count == QueueProtocol.MAX_RECEIPTS_PER_ACTOR then
		local evicted = actorLedger.ring[actorLedger.nextIndex]
		if evicted ~= nil then
			actorLedger.byId[evicted] = nil
		end
	else
		actorLedger.count += 1
	end
	actorLedger.ring[actorLedger.nextIndex] = transactionId
	actorLedger.byId[transactionId] = value
	actorLedger.nextIndex = (actorLedger.nextIndex % QueueProtocol.MAX_RECEIPTS_PER_ACTOR) + 1
end

local function makeReceipt(
	data: ServiceData,
	queue: QueueRecord,
	userId: number,
	transactionId: string,
	kind: QueueProtocol.MutationKind,
	fingerprint: string,
	changed: boolean
): QueueProtocol.MutationReceipt
	local queueSnapshot = snapshot(data, queue)
	local value: QueueProtocol.MutationReceipt = table.freeze({
		transactionId = transactionId,
		kind = kind,
		changed = changed,
		revision = queueSnapshot.revision,
		snapshot = queueSnapshot,
	})
	local validated = QueueProtocol.validateMutationReceipt(value)
	if not validated.ok then
		error("[ATD_LOBBY_QUEUE_SERVICE][code=INVALID_RECEIPT]", 0)
	end
	storeReceipt(data, userId, { kind = kind, fingerprint = fingerprint, receipt = validated.value })
	return validated.value
end

local function resetEmpty(queue: QueueRecord)
	if #queue.enrollments ~= 0 then
		return
	end
	queue.state = "Open"
	queue.publicStatus = nil
	queue.configuration = configurationCopy(queue.defaultConfiguration)
	queue.nextSequence = 1
	queue.lockedStart = nil
end

local function enrollmentForUser(queue: QueueRecord, userId: number): (Enrollment?, number?)
	for index, enrollment in queue.enrollments do
		for _, memberUserId in enrollment.userIds do
			if memberUserId == userId then
				return enrollment, index
			end
		end
	end
	return nil, nil
end

local function removeEnrollment(data: ServiceData, queue: QueueRecord, index: number): Enrollment
	local removed = table.remove(queue.enrollments, index)
	for _, userId in removed.userIds do
		data.queueIdByUserId[userId] = nil
	end
	resetEmpty(queue)
	return removed
end

local function affectedUsers(value: unknown): { [number]: boolean }?
	if value == nil then
		return {}
	elseif type(value) ~= "table" or getmetatable(value :: any) ~= nil or #value > PartyProtocol.MAX_MEMBERS then
		return nil
	end
	local output: { [number]: boolean } = {}
	for index, userId in value :: { unknown } do
		if index ~= math.floor(index) or index < 1 or not validUserId(userId) or output[userId :: number] then
			return nil
		end
		output[userId :: number] = true
	end
	return output
end

local function enrollmentHasAffectedUser(enrollment: Enrollment, affected: { [number]: boolean }): boolean
	for _, userId in enrollment.userIds do
		if affected[userId] then
			return true
		end
	end
	return false
end

local function sameMembers(left: { number }, right: { number }): boolean
	if #left ~= #right then
		return false
	end
	for index, userId in left do
		if right[index] ~= userId then
			return false
		end
	end
	return true
end

local function partyStillValid(data: ServiceData, enrollment: Enrollment): boolean
	if enrollment.kind ~= "Party" then
		return true
	end
	local party = readParty(data, enrollment.leaderUserId)
	return party ~= nil
		and party.partyId == enrollment.partyId
		and party.leaderUserId == enrollment.leaderUserId
		and sameMembers(party.members, enrollment.userIds)
end

local function joinInternal(
	data: ServiceData,
	queue: QueueRecord,
	userId: number,
	source: QueueProtocol.Source,
	operation: string
): Result.Result<boolean, ServiceError>
	if queue.state ~= "Open" then
		return failure("QUEUE_LOCKED", operation)
	end
	local existingQueueId = data.queueIdByUserId[userId]
	if existingQueueId ~= nil then
		if existingQueueId == queue.queueId then
			return Result.ok(false)
		end
		return failure("ALREADY_QUEUED", operation)
	end
	local actorPresent = present(data, userId)
	if actorPresent == nil then
		return failure("UNAVAILABLE", operation)
	elseif not actorPresent then
		return failure("NOT_PRESENT", operation)
	end
	local party = readParty(data, userId)
	if party ~= nil and party.leaderUserId ~= userId then
		return failure("NOT_PARTY_LEADER", operation)
	end
	local users = if party == nil then { userId } else table.clone(party.members)
	if #users < 1 or #users > QueueProtocol.MAX_PLAYERS then
		return failure("INVALID_PARTY", operation)
	end
	for _, memberUserId in users do
		local memberPresent = present(data, memberUserId)
		if memberPresent == nil then
			return failure("UNAVAILABLE", operation)
		elseif not memberPresent then
			return failure("NOT_PRESENT", operation)
		elseif data.queueIdByUserId[memberUserId] ~= nil then
			return failure("ALREADY_QUEUED", operation)
		end
		local eligibility = readEligibility(data, memberUserId)
		if eligibility == nil then
			return failure("UNAVAILABLE", operation)
		elseif not eligibility.profileReady then
			return failure("PROFILE_NOT_READY", operation)
		end
	end
	if rosterCount(queue) + #users > queue.configuration.maxPlayers then
		return failure("QUEUE_FULL", operation)
	end
	if queue.configuration.privacy == "PartyOnly" and #queue.enrollments > 0 then
		local first = queue.enrollments[1]
		if party == nil or first.partyId == nil or first.partyId ~= party.partyId then
			return failure("PRIVACY_RESTRICTED", operation)
		end
	end
	if queue.nextSequence > Validation.MAX_SAFE_INTEGER then
		return failure("SEQUENCE_EXHAUSTED", operation)
	elseif queue.revision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", operation)
	end
	local enrollment: Enrollment = {
		sequence = queue.nextSequence,
		kind = if party == nil then "Solo" else "Party",
		leaderUserId = userId,
		partyId = if party == nil then nil else party.partyId,
		partyRevision = if party == nil then nil else party.revision,
		userIds = users,
		source = source,
	}
	queue.nextSequence += 1
	queue.revision += 1
	table.insert(queue.enrollments, enrollment)
	for _, memberUserId in users do
		data.queueIdByUserId[memberUserId] = queue.queueId
	end
	emitSnapshot(data, queue)
	return Result.ok(true)
end

function Methods.listSnapshots(self: Service): { QueueProtocol.Snapshot }
	local data = requireData(self)
	local output: { QueueProtocol.Snapshot } = table.create(#data.queueIds)
	for index, queueId in data.queueIds do
		output[index] = snapshot(data, data.queuesById[queueId])
	end
	return table.freeze(output)
end

function Methods.getSnapshot(self: Service, queueIdValue: unknown): Result.Result<QueueProtocol.Snapshot, ServiceError>
	local data = requireData(self)
	local queueId = Ids.validateQueueId(queueIdValue)
	if not queueId.ok then
		return failure("QUEUE_NOT_FOUND", "getSnapshot")
	end
	local queue = data.queuesById[queueId.value]
	if queue == nil then
		return failure("QUEUE_NOT_FOUND", "getSnapshot")
	end
	return Result.ok(snapshot(data, queue))
end

function Methods.getQueueForUser(self: Service, userIdValue: unknown): string?
	local data = requireData(self)
	return if validUserId(userIdValue) then data.queueIdByUserId[userIdValue :: number] else nil
end

function Methods.join(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<QueueProtocol.MutationReceipt, ServiceError>
	local data = requireData(self)
	local operation = "join"
	local intentResult = QueueProtocol.JoinIntentSchema:validate(intentValue)
	if not intentResult.ok or not validUserId(userIdValue) then
		return failure(if not validUserId(userIdValue) then "INVALID_USER_ID" else "INVALID_INTENT", operation)
	end
	local intent = intentResult.value :: QueueProtocol.JoinIntent
	local queue = data.queuesById[intent.queueId]
	if queue == nil then
		return failure("QUEUE_NOT_FOUND", operation)
	end
	local userId = userIdValue :: number
	local fingerprint = `join|{intent.expectedRevision}|{intent.queueId}|{intent.source}`
	local busyError = enter(data, operation)
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local replayed = replay(data, userId, intent.transactionId, "Join", fingerprint, operation)
	if not replayed.ok or replayed.value ~= nil then
		finish(data)
		return if replayed.ok then Result.ok(replayed.value :: QueueProtocol.MutationReceipt) else replayed
	end
	if queue.revision ~= intent.expectedRevision then
		finish(data)
		return failure("STALE_REVISION", operation)
	elseif queue.state ~= "Open" then
		finish(data)
		return failure("QUEUE_LOCKED", operation)
	end
	local joined = joinInternal(data, queue, userId, intent.source, operation)
	if not joined.ok then
		finish(data)
		return joined
	end
	local receipt = makeReceipt(data, queue, userId, intent.transactionId, "Join", fingerprint, joined.value)
	finish(data)
	return Result.ok(receipt)
end

function Methods.leave(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<QueueProtocol.MutationReceipt, ServiceError>
	local data = requireData(self)
	local operation = "leave"
	local intentResult = QueueProtocol.LeaveIntentSchema:validate(intentValue)
	if not intentResult.ok or not validUserId(userIdValue) then
		return failure(if not validUserId(userIdValue) then "INVALID_USER_ID" else "INVALID_INTENT", operation)
	end
	local intent = intentResult.value :: QueueProtocol.LeaveIntent
	local queue = data.queuesById[intent.queueId]
	if queue == nil then
		return failure("QUEUE_NOT_FOUND", operation)
	end
	local userId = userIdValue :: number
	local fingerprint = `leave|{intent.expectedRevision}|{intent.queueId}`
	local busyError = enter(data, operation)
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local replayed = replay(data, userId, intent.transactionId, "Leave", fingerprint, operation)
	if not replayed.ok or replayed.value ~= nil then
		finish(data)
		return if replayed.ok then Result.ok(replayed.value :: QueueProtocol.MutationReceipt) else replayed
	end
	if queue.revision ~= intent.expectedRevision then
		finish(data)
		return failure("STALE_REVISION", operation)
	elseif queue.state ~= "Open" then
		finish(data)
		return failure("QUEUE_LOCKED", operation)
	end
	local _enrollment, index = enrollmentForUser(queue, userId)
	if index == nil then
		finish(data)
		return failure("NOT_QUEUED", operation)
	elseif queue.revision >= Validation.MAX_SAFE_INTEGER then
		finish(data)
		return failure("REVISION_EXHAUSTED", operation)
	end
	removeEnrollment(data, queue, index)
	queue.revision += 1
	emitSnapshot(data, queue)
	local receipt = makeReceipt(data, queue, userId, intent.transactionId, "Leave", fingerprint, true)
	finish(data)
	return Result.ok(receipt)
end

function Methods.configure(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<QueueProtocol.MutationReceipt, ServiceError>
	local data = requireData(self)
	local operation = "configure"
	local intentResult = QueueProtocol.ConfigureIntentSchema:validate(intentValue)
	if not intentResult.ok or not validUserId(userIdValue) then
		return failure(if not validUserId(userIdValue) then "INVALID_USER_ID" else "INVALID_INTENT", operation)
	end
	local intent = intentResult.value :: QueueProtocol.ConfigureIntent
	local queue = data.queuesById[intent.queueId]
	if queue == nil then
		return failure("QUEUE_NOT_FOUND", operation)
	end
	local userId = userIdValue :: number
	local selected = intent.configuration
	local fingerprint =
		`configure|{intent.expectedRevision}|{intent.queueId}|{selected.mapId}|{selected.difficultyId}|{selected.privacy}|{selected.maxPlayers}`
	local busyError = enter(data, operation)
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local replayed = replay(data, userId, intent.transactionId, "Configure", fingerprint, operation)
	if not replayed.ok or replayed.value ~= nil then
		finish(data)
		return if replayed.ok then Result.ok(replayed.value :: QueueProtocol.MutationReceipt) else replayed
	end
	if queue.revision ~= intent.expectedRevision then
		finish(data)
		return failure("STALE_REVISION", operation)
	elseif queue.state ~= "Open" then
		finish(data)
		return failure("QUEUE_LOCKED", operation)
	elseif captainUserId(queue) ~= userId then
		finish(data)
		return failure("NOT_CAPTAIN", operation)
	elseif
		not configurationValid(data.configuration, selected)
		or selected.maxPlayers < rosterCount(queue)
		or not privacyCompatible(queue, selected.privacy)
	then
		finish(data)
		return failure("INVALID_SELECTION", operation)
	end
	local changed = queue.configuration.mapId ~= selected.mapId
		or queue.configuration.difficultyId ~= selected.difficultyId
		or queue.configuration.privacy ~= selected.privacy
		or queue.configuration.maxPlayers ~= selected.maxPlayers
	if changed then
		if not incrementRevision(queue) then
			finish(data)
			return failure("REVISION_EXHAUSTED", operation)
		end
		queue.configuration = configurationCopy(selected)
		emitSnapshot(data, queue)
	end
	local receipt = makeReceipt(data, queue, userId, intent.transactionId, "Configure", fingerprint, changed)
	finish(data)
	return Result.ok(receipt)
end

local function detachedFreeze(value: unknown, depth: number, state: { nodes: number }): unknown?
	if depth > MAX_LOCKED_DEPTH then
		return nil
	end
	local kind = typeof(value)
	if kind ~= "table" then
		return if kind == "string" or kind == "number" or kind == "boolean" then value else nil
	end
	if getmetatable(value :: any) ~= nil then
		return nil
	end
	state.nodes += 1
	if state.nodes > MAX_LOCKED_NODES then
		return nil
	end
	local output = {}
	for key, child in value :: { [any]: unknown } do
		if type(key) ~= "string" and type(key) ~= "number" then
			return nil
		end
		local copied = detachedFreeze(child, depth + 1, state)
		if copied == nil and child ~= nil then
			return nil
		end
		output[key] = copied
	end
	return table.freeze(output)
end

local function buildLockedStart(data: ServiceData, queue: QueueRecord): Result.Result<LockedStart, ServiceError>
	if not privacyCompatible(queue, queue.configuration.privacy) then
		return failure("PRIVACY_RESTRICTED", "start")
	end
	local orderedUserIds: { number } = {}
	local members: { LockedMember } = {}
	for _, enrollment in queue.enrollments do
		if not partyStillValid(data, enrollment) then
			return failure("PARTY_CHANGED", "start")
		end
		for _, userId in enrollment.userIds do
			local isHere = present(data, userId)
			if isHere == nil then
				return failure("UNAVAILABLE", "start")
			elseif not isHere then
				return failure("NOT_PRESENT", "start")
			end
			local eligibility = readEligibility(data, userId)
			if eligibility == nil then
				return failure("UNAVAILABLE", "start")
			elseif not eligibility.profileReady or not eligibility.sessionOwned or not eligibility.ticketEligible then
				return failure("NOT_ELIGIBLE", "start")
			elseif not eligibility.loadoutReady or eligibility.loadout == nil then
				return failure("INVALID_LOADOUT", "start")
			end
			local frozenLoadout = detachedFreeze(eligibility.loadout, 0, { nodes = 0 })
			if frozenLoadout == nil then
				return failure("INVALID_LOADOUT", "start")
			end
			table.insert(orderedUserIds, userId)
			table.insert(members, table.freeze({ userId = userId, loadout = frozenLoadout }))
		end
	end
	local captain = captainUserId(queue)
	if captain == nil or #orderedUserIds < 1 then
		return failure("NOT_ELIGIBLE", "start")
	end
	return Result.ok(table.freeze({
		queueId = queue.queueId,
		revision = queue.revision + 1,
		captainUserId = captain,
		configuration = configurationCopy(queue.configuration),
		orderedUserIds = table.freeze(orderedUserIds),
		members = table.freeze(members),
	}))
end

function Methods.start(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<QueueProtocol.MutationReceipt, ServiceError>
	local data = requireData(self)
	local operation = "start"
	local intentResult = QueueProtocol.StartIntentSchema:validate(intentValue)
	if not intentResult.ok or not validUserId(userIdValue) then
		return failure(if not validUserId(userIdValue) then "INVALID_USER_ID" else "INVALID_INTENT", operation)
	end
	local intent = intentResult.value :: QueueProtocol.StartIntent
	local queue = data.queuesById[intent.queueId]
	if queue == nil then
		return failure("QUEUE_NOT_FOUND", operation)
	end
	local userId = userIdValue :: number
	local fingerprint = `start|{intent.expectedRevision}|{intent.queueId}`
	local busyError = enter(data, operation)
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local replayed = replay(data, userId, intent.transactionId, "Start", fingerprint, operation)
	if not replayed.ok or replayed.value ~= nil then
		finish(data)
		return if replayed.ok then Result.ok(replayed.value :: QueueProtocol.MutationReceipt) else replayed
	end
	if queue.revision ~= intent.expectedRevision then
		finish(data)
		return failure("STALE_REVISION", operation)
	elseif queue.state ~= "Open" then
		finish(data)
		return failure("QUEUE_LOCKED", operation)
	elseif captainUserId(queue) ~= userId then
		finish(data)
		return failure("NOT_CAPTAIN", operation)
	elseif queue.revision >= Validation.MAX_SAFE_INTEGER then
		finish(data)
		return failure("REVISION_EXHAUSTED", operation)
	end
	local removedInvalidParty = false
	for index = #queue.enrollments, 1, -1 do
		if not partyStillValid(data, queue.enrollments[index]) then
			removeEnrollment(data, queue, index)
			removedInvalidParty = true
		end
	end
	if removedInvalidParty then
		queue.revision += 1
		emitSnapshot(data, queue)
		finish(data)
		return failure("PARTY_CHANGED", operation)
	end
	local locked = buildLockedStart(data, queue)
	if not locked.ok then
		finish(data)
		return locked
	end
	queue.state = "Starting"
	queue.publicStatus = "TicketPending"
	queue.revision += 1
	queue.lockedStart = locked.value
	emitSnapshot(data, queue)
	local called, boundary = callNonYielding(data.dependencies.beginStart, locked.value)
	local accepted = called and (boundary == true or (type(boundary) == "table" and (boundary :: any).ok == true))
	if not accepted then
		queue.state = "Open"
		queue.publicStatus = nil
		queue.lockedStart = nil
		if queue.revision < Validation.MAX_SAFE_INTEGER then
			queue.revision += 1
		end
		emitSnapshot(data, queue)
		finish(data)
		return failure("START_FAILED", operation)
	end
	local receipt = makeReceipt(data, queue, userId, intent.transactionId, "Start", fingerprint, true)
	finish(data)
	return Result.ok(receipt)
end

function Methods.getLockedStart(self: Service, queueIdValue: unknown): LockedStart?
	local data = requireData(self)
	local queueId = Ids.validateQueueId(queueIdValue)
	local queue = if queueId.ok then data.queuesById[queueId.value] else nil
	return if queue == nil then nil else queue.lockedStart
end

function Methods.setTravelStatus(
	self: Service,
	queueIdValue: unknown,
	statusValue: unknown
): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	local queueId = Ids.validateQueueId(queueIdValue)
	local queue = if queueId.ok then data.queuesById[queueId.value] else nil
	if queue == nil then
		return failure("QUEUE_NOT_FOUND", "setTravelStatus")
	end
	local desiredState: QueueProtocol.State
	if statusValue == "TicketPending" then
		desiredState = "Starting"
	elseif statusValue == "TeleportInitializing" or statusValue == "TeleportRetrying" then
		desiredState = "Traveling"
	elseif
		statusValue == "TicketFailed"
		or statusValue == "TeleportFailed"
		or statusValue == "PartialTeleportFailure"
	then
		desiredState = "Failed"
	else
		return failure("INVALID_INTENT", "setTravelStatus")
	end
	local busyError = enter(data, "setTravelStatus")
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local currentState = queue.state
	local validTransition = currentState == "Starting"
			and (desiredState == "Starting" or desiredState == "Traveling" or desiredState == "Failed")
		or currentState == "Traveling" and (desiredState == "Traveling" or desiredState == "Failed")
		or currentState == "Failed" and desiredState == "Failed" and queue.publicStatus == statusValue
	if not validTransition or queue.lockedStart == nil then
		finish(data)
		return failure("QUEUE_LOCKED", "setTravelStatus")
	end
	local status = statusValue :: QueueProtocol.PublicStatus
	local changed = queue.state ~= desiredState or queue.publicStatus ~= status
	if changed then
		if not incrementRevision(queue) then
			finish(data)
			return failure("REVISION_EXHAUSTED", "setTravelStatus")
		end
		queue.state = desiredState
		queue.publicStatus = status
		emitSnapshot(data, queue)
	end
	finish(data)
	return Result.ok(changed)
end

function Methods.markTraveling(
	self: Service,
	queueIdValue: unknown,
	statusValue: unknown
): Result.Result<boolean, ServiceError>
	if statusValue ~= "TeleportInitializing" and statusValue ~= "TeleportRetrying" then
		return failure("INVALID_INTENT", "markTraveling")
	end
	return self:setTravelStatus(queueIdValue, statusValue)
end

function Methods.markFailed(
	self: Service,
	queueIdValue: unknown,
	statusValue: unknown
): Result.Result<boolean, ServiceError>
	if
		statusValue ~= "TicketFailed"
		and statusValue ~= "TeleportFailed"
		and statusValue ~= "PartialTeleportFailure"
	then
		return failure("INVALID_INTENT", "markFailed")
	end
	return self:setTravelStatus(queueIdValue, statusValue)
end

function Methods.recover(self: Service, queueIdValue: unknown): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	local queueId = Ids.validateQueueId(queueIdValue)
	local queue = if queueId.ok then data.queuesById[queueId.value] else nil
	if queue == nil then
		return failure("QUEUE_NOT_FOUND", "recover")
	end
	local busyError = enter(data, "recover")
	if busyError ~= nil then
		return Result.err(busyError)
	end
	if queue.state == "Open" then
		finish(data)
		return Result.ok(false)
	elseif not incrementRevision(queue) then
		finish(data)
		return failure("REVISION_EXHAUSTED", "recover")
	end
	queue.state = "Open"
	queue.publicStatus = nil
	queue.lockedStart = nil
	local index = #queue.enrollments
	while index >= 1 do
		local enrollment = queue.enrollments[index]
		local valid = partyStillValid(data, enrollment)
		for _, userId in enrollment.userIds do
			valid = valid and present(data, userId) == true
		end
		if not valid then
			removeEnrollment(data, queue, index)
		end
		index -= 1
	end
	resetEmpty(queue)
	emitSnapshot(data, queue)
	finish(data)
	return Result.ok(true)
end

function Methods.completeStart(self: Service, queueIdValue: unknown): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	local queueId = Ids.validateQueueId(queueIdValue)
	local queue = if queueId.ok then data.queuesById[queueId.value] else nil
	if queue == nil then
		return failure("QUEUE_NOT_FOUND", "completeStart")
	end
	local busyError = enter(data, "completeStart")
	if busyError ~= nil then
		return Result.err(busyError)
	end
	if queue.state ~= "Starting" and queue.state ~= "Traveling" then
		finish(data)
		return Result.ok(false)
	elseif not incrementRevision(queue) then
		finish(data)
		return failure("REVISION_EXHAUSTED", "completeStart")
	end
	for _, enrollment in queue.enrollments do
		for _, userId in enrollment.userIds do
			data.queueIdByUserId[userId] = nil
		end
	end
	table.clear(queue.enrollments)
	resetEmpty(queue)
	emitSnapshot(data, queue)
	finish(data)
	return Result.ok(true)
end

function Methods.enterPhysical(
	self: Service,
	queueIdValue: unknown,
	userIdValue: unknown
): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	local queueId = Ids.validateQueueId(queueIdValue)
	if not queueId.ok or not validUserId(userIdValue) then
		return failure(if not queueId.ok then "QUEUE_NOT_FOUND" else "INVALID_USER_ID", "enterPhysical")
	end
	local queue = data.queuesById[queueId.value]
	if queue == nil then
		return failure("QUEUE_NOT_FOUND", "enterPhysical")
	end
	local busyError = enter(data, "enterPhysical")
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local joined = joinInternal(data, queue, userIdValue :: number, "Physical", "enterPhysical")
	finish(data)
	return joined
end

function Methods.leavePhysical(
	self: Service,
	queueIdValue: unknown,
	userIdValue: unknown
): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	local queueId = Ids.validateQueueId(queueIdValue)
	if not queueId.ok or not validUserId(userIdValue) then
		return failure(if not queueId.ok then "QUEUE_NOT_FOUND" else "INVALID_USER_ID", "leavePhysical")
	end
	local queue = data.queuesById[queueId.value]
	if queue == nil then
		return failure("QUEUE_NOT_FOUND", "leavePhysical")
	end
	local busyError = enter(data, "leavePhysical")
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local enrollment, index = enrollmentForUser(queue, userIdValue :: number)
	if
		enrollment == nil
		or index == nil
		or enrollment.source ~= "Physical"
		or enrollment.leaderUserId ~= userIdValue
		or queue.state ~= "Open"
	then
		finish(data)
		return Result.ok(false)
	elseif not incrementRevision(queue) then
		finish(data)
		return failure("REVISION_EXHAUSTED", "leavePhysical")
	end
	removeEnrollment(data, queue, index)
	emitSnapshot(data, queue)
	finish(data)
	return Result.ok(true)
end

function Methods.invalidateParty(
	self: Service,
	partyIdValue: unknown,
	affectedUserIdsValue: unknown?
): Result.Result<number, ServiceError>
	local data = requireData(self)
	local affected = affectedUsers(affectedUserIdsValue)
	if not PartyProtocol.isPartyId(partyIdValue) or affected == nil then
		return failure("INVALID_PARTY", "invalidateParty")
	end
	local busyError = enter(data, "invalidateParty")
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local removedCount = 0
	for _, queueId in data.queueIds do
		local queue = data.queuesById[queueId]
		if queue.state ~= "Open" then
			continue
		end
		local index = #queue.enrollments
		local changed = false
		while index >= 1 do
			local enrollment = queue.enrollments[index]
			if enrollment.partyId == partyIdValue or enrollmentHasAffectedUser(enrollment, affected) then
				removeEnrollment(data, queue, index)
				removedCount += 1
				changed = true
			end
			index -= 1
		end
		if changed then
			if incrementRevision(queue) then
				emitSnapshot(data, queue)
			end
		end
	end
	finish(data)
	return Result.ok(removedCount)
end

function Methods.removePlayer(self: Service, userIdValue: unknown): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "removePlayer")
	end
	local userId = userIdValue :: number
	local queueId = data.queueIdByUserId[userId]
	if queueId == nil then
		data.receiptsByUserId[userId] = nil
		return Result.ok(false)
	end
	local queue = data.queuesById[queueId]
	local busyError = enter(data, "removePlayer")
	if busyError ~= nil then
		return Result.err(busyError)
	end
	local _enrollment, index = enrollmentForUser(queue, userId)
	if queue.state ~= "Open" then
		data.receiptsByUserId[userId] = nil
		finish(data)
		return Result.ok(false)
	elseif index ~= nil and incrementRevision(queue) then
		removeEnrollment(data, queue, index)
		emitSnapshot(data, queue)
	end
	data.receiptsByUserId[userId] = nil
	finish(data)
	return Result.ok(index ~= nil)
end

function Methods.cleanup(self: Service): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	local busyError = enter(data, "cleanup")
	if busyError ~= nil then
		return Result.err(busyError)
	end
	for _, queue in data.queuesById do
		for _, enrollment in queue.enrollments do
			table.clear(enrollment.userIds)
		end
		table.clear(queue.enrollments)
		queue.lockedStart = nil
	end
	table.clear(data.queuesById)
	table.clear(data.queueIds)
	table.clear(data.queueIdByUserId)
	table.clear(data.receiptsByUserId)
	finish(data)
	return Result.ok(true)
end

function Methods.getMetrics(self: Service): { [string]: number }
	local data = requireData(self)
	local enrollmentCount = 0
	local memberCount = 0
	local lockedCount = 0
	local receiptCount = 0
	for _, queue in data.queuesById do
		enrollmentCount += #queue.enrollments
		memberCount += rosterCount(queue)
		lockedCount += if queue.state ~= "Open" then 1 else 0
	end
	for _, actorLedger in data.receiptsByUserId do
		receiptCount += actorLedger.count
	end
	return table.freeze({
		queueCount = #data.queueIds,
		enrollmentCount = enrollmentCount,
		memberCount = memberCount,
		lockedCount = lockedCount,
		receiptCount = receiptCount,
		callbackFailureCount = data.callbackFailureCount,
	})
end

local function readDefinitions(
	configuration: ConfigTypes.CoreConfiguration,
	definitionsValue: unknown
): ({ [string]: QueueRecord }?, { string }?)
	if type(definitionsValue) ~= "table" or getmetatable(definitionsValue :: any) ~= nil then
		return nil, nil
	end
	local raw = definitionsValue :: { [any]: unknown }
	local count = 0
	local maximum = 0
	for key in raw do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > QueueProtocol.MAX_QUEUES then
			return nil, nil
		end
		count += 1
		maximum = math.max(maximum, key)
	end
	if count < 1 or maximum ~= count then
		return nil, nil
	end
	local fallback = defaultConfiguration(configuration)
	if fallback == nil then
		return nil, nil
	end
	local queues: { [string]: QueueRecord } = {}
	local ids: { string } = {}
	for index = 1, count do
		local definitionValue = raw[index]
		if type(definitionValue) ~= "table" or getmetatable(definitionValue :: any) ~= nil then
			return nil, nil
		end
		local definition = definitionValue :: { [any]: unknown }
		for key in definition do
			if key ~= "queueId" and key ~= "configuration" then
				return nil, nil
			end
		end
		local queueId = Ids.validateQueueId(definition.queueId)
		local selected = definition.configuration
		local validatedConfiguration = if selected == nil
			then fallback
			else QueueProtocol.ConfigureIntentSchema:validate({
				transactionId = "transaction:definition",
				expectedRevision = 1,
				queueId = definition.queueId,
				configuration = selected,
			})
		if
			not queueId.ok
			or queues[queueId.value] ~= nil
			or (selected ~= nil and not (validatedConfiguration :: any).ok)
		then
			return nil, nil
		end
		local canonical = if selected == nil
			then fallback
			else (validatedConfiguration :: any).value.configuration :: QueueProtocol.Configuration
		if not configurationValid(configuration, canonical) then
			return nil, nil
		end
		local default = configurationCopy(canonical)
		queues[queueId.value] = {
			queueId = queueId.value,
			revision = 1,
			state = "Open",
			publicStatus = nil,
			configuration = configurationCopy(default),
			defaultConfiguration = default,
			enrollments = {},
			nextSequence = 1,
			lockedStart = nil,
		}
		table.insert(ids, queueId.value)
	end
	table.sort(ids)
	return queues, table.freeze(ids)
end

function LobbyQueueService.new(
	configurationValue: unknown,
	definitionsValue: unknown,
	dependenciesValue: unknown
): Result.Result<Service, ServiceError>
	if not ConfigurationValidator.isValidatedConfiguration(configurationValue) then
		return failure("INVALID_CONFIGURATION", "new")
	end
	if
		type(dependenciesValue) ~= "table"
		or getmetatable(dependenciesValue :: any) ~= nil
		or type((dependenciesValue :: any).isPresent) ~= "function"
		or type((dependenciesValue :: any).getParty) ~= "function"
		or type((dependenciesValue :: any).getEligibility) ~= "function"
		or type((dependenciesValue :: any).beginStart) ~= "function"
		or ((dependenciesValue :: any).onChanged ~= nil and type((dependenciesValue :: any).onChanged) ~= "function")
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local queues, ids = readDefinitions(configurationValue :: ConfigTypes.CoreConfiguration, definitionsValue)
	if queues == nil or ids == nil then
		return failure("INVALID_DEFINITIONS", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		configuration = configurationValue :: ConfigTypes.CoreConfiguration,
		dependencies = dependenciesValue :: Dependencies,
		queuesById = queues,
		queueIds = ids,
		queueIdByUserId = {},
		receiptsByUserId = {},
		busy = false,
		callbackFailureCount = 0,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(LobbyQueueService)
