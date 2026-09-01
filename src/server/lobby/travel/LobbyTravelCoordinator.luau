--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local QueueProtocol = require(ReplicatedStorage.Shared.queue.QueueProtocol)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local productionCommon = script.Parent.Parent.Parent:FindFirstChild("common")
local matchTicketModule = if productionCommon ~= nil
	then productionCommon.travel.MatchTicketContract
	else ServerStorage.AutomatedTests.ProductionServerTravel.MatchTicketContract
local MatchTicketContract = require(matchTicketModule)

export type IdKind = "ticket" | "match" | "result" | "route"
export type PublicFailure = "TicketFailed" | "TeleportFailed" | "PartialTeleportFailure"

export type LockedStart = {
	queueId: string,
	revision: number,
	captainUserId: number,
	configuration: QueueProtocol.Configuration,
	orderedUserIds: { number },
	members: { unknown },
}

export type Dependencies = {
	clock: () -> unknown,
	schedule: (() -> ()) -> unknown,
	makeId: (IdKind) -> unknown,
	ticketStore: any,
	pendingResults: any,
	resultLedger: any,
	profileTransfer: any,
	safeTeleport: any,
	activeRoutes: any,
	queue: any,
	getPlayer: (number) -> unknown,
	isPresent: (number) -> unknown,
	lobbyPlaceId: number,
	matchPlaceId: number,
	lobbyJobId: string,
	ticketLifetimeSeconds: number?,
	routeLifetimeSeconds: number?,
	developmentSimulation: boolean?,
}

export type ErrorCode = "INVALID_DEPENDENCIES" | "INVALID_LOCK" | "BUSY" | "CLEANED"
export type CoordinatorError = { code: ErrorCode, operation: string }

type Context = {
	locked: LockedStart,
	phase: string,
	ticketId: string?,
	matchId: string?,
	resultId: string?,
	routeIds: { [number]: string },
	transferHandle: unknown?,
	transferCommitted: boolean,
	pendingReserved: boolean,
	resultIntentAttempted: boolean,
	resultIntentCreated: boolean,
	resultIntentConflict: boolean,
	resultIntentCancelled: boolean,
	ticketCreated: boolean,
	ticketCreationAttempted: boolean,
	ticketTerminalized: boolean,
	initialized: boolean,
	settled: boolean,
	partial: boolean,
	departedUserIds: { [number]: boolean },
	guardExpiresAt: number?,
	recoveryStatus: PublicFailure?,
	recoveryReason: string?,
	recoveryPresentUserIds: { [number]: boolean },
	reacquiredUserIds: { [number]: boolean },
	pendingReleasedUserIds: { [number]: boolean },
	routesClearedUserIds: { [number]: boolean },
	queueRecovered: boolean,
	teleportFinished: boolean,
	recoveryCounted: boolean,
	simulationRecovery: boolean,
}

type ServiceData = {
	dependencies: Dependencies,
	ticketLifetimeSeconds: number,
	routeLifetimeSeconds: number,
	contextsByQueueId: { [string]: Context },
	contextsByTicketId: { [string]: Context },
	cleaned: boolean,
	scheduleViolationCount: number,
	completedCount: number,
	failureCount: number,
	partialFailureCount: number,
	simulatedCount: number,
}

local Methods = {}
Methods.__index = Methods
export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local DEFAULT_TICKET_LIFETIME_SECONDS = 600
local DEFAULT_ROUTE_LIFETIME_SECONDS = 2_700
local MAX_CONTEXTS = 32
local SHUTDOWN_DURABILITY_ATTEMPTS = 3

local LobbyTravelCoordinator = {
	SHUTDOWN_DURABILITY_ATTEMPTS = SHUTDOWN_DURABILITY_ATTEMPTS,
}

local function failure<T>(code: ErrorCode, operation: string): Result.Failure<CoordinatorError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_LOBBY_TRAVEL][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function resultOk(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function callResult(callback: (...any) -> unknown, ...: any): unknown
	local called, value = pcall(callback, ...)
	return if called then value else nil
end

local function safeInteger(value: unknown): number?
	return if type(value) == "number"
			and Validation.isSafeInteger(value :: number)
			and value > 0
		then value :: number
		else nil
end

local function plainExact(value: unknown, fields: { [string]: boolean }): { [string]: unknown }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local record = value :: { [any]: unknown }
	local count = 0
	for key in record do
		if type(key) ~= "string" or fields[key] ~= true then
			return nil
		end
		count += 1
	end
	local expected = 0
	for _ in fields do
		expected += 1
	end
	return if count == expected then record :: { [string]: unknown } else nil
end

local function lockedStart(value: unknown): LockedStart?
	local record = plainExact(value, {
		queueId = true,
		revision = true,
		captainUserId = true,
		configuration = true,
		orderedUserIds = true,
		members = true,
	})
	if record == nil or not Ids.validateQueueId(record.queueId).ok then
		return nil
	end
	local revision = safeInteger(record.revision)
	local captain = safeInteger(record.captainUserId)
	local configuration = record.configuration
	local users = record.orderedUserIds
	local members = record.members
	if
		revision == nil
		or captain == nil
		or type(configuration) ~= "table"
		or type(users) ~= "table"
		or type(members) ~= "table"
		or getmetatable(configuration :: any) ~= nil
		or getmetatable(users :: any) ~= nil
		or getmetatable(members :: any) ~= nil
		or #users < 1
		or #users > QueueProtocol.MAX_PLAYERS
		or #users ~= #members
	then
		return nil
	end
	local rawConfiguration = configuration :: any
	if
		type(rawConfiguration.mapId) ~= "string"
		or type(rawConfiguration.difficultyId) ~= "string"
		or (rawConfiguration.privacy ~= "Public" and rawConfiguration.privacy ~= "PartyOnly")
		or type(rawConfiguration.maxPlayers) ~= "number"
		or rawConfiguration.maxPlayers < #users
		or rawConfiguration.maxPlayers > QueueProtocol.MAX_PLAYERS
	then
		return nil
	end
	local ordered: { number } = table.create(#users)
	local seen: { [number]: boolean } = {}
	local captainFound = false
	for index, userIdValue in users :: { unknown } do
		local userId = safeInteger(userIdValue)
		if userId == nil or seen[userId] then
			return nil
		end
		seen[userId] = true
		captainFound = captainFound or userId == captain
		ordered[index] = userId
	end
	if not captainFound then
		return nil
	end
	return table.freeze({
		queueId = record.queueId :: string,
		revision = revision,
		captainUserId = captain,
		configuration = table.freeze({
			mapId = rawConfiguration.mapId,
			difficultyId = rawConfiguration.difficultyId,
			privacy = rawConfiguration.privacy,
			maxPlayers = rawConfiguration.maxPlayers,
		}),
		orderedUserIds = table.freeze(ordered),
		members = table.freeze(table.clone(members :: { unknown })),
	})
end

local function currentTime(data: ServiceData): number?
	local called, value = pcall(data.dependencies.clock)
	return if called
			and type(value) == "number"
			and Validation.isSafeInteger(value :: number)
			and value >= 0
		then value :: number
		else nil
end

local function boundedToken(value: unknown, prefix: string, maximum: number): string?
	if type(value) ~= "string" or #value < #prefix + 2 or #value > maximum then
		return nil
	end
	if string.sub(value :: string, 1, #prefix + 1) ~= `{prefix}:` then
		return nil
	end
	for index = #prefix + 2, #value do
		local byte = string.byte(value :: string, index)
		if
			byte == nil
			or not (
				(byte >= string.byte("a") and byte <= string.byte("z"))
				or (byte >= string.byte("0") and byte <= string.byte("9"))
				or byte == string.byte("-")
			)
		then
			return nil
		end
	end
	return value :: string
end

local function freshId(data: ServiceData, kind: IdKind): string?
	local called, value = pcall(data.dependencies.makeId, kind)
	if not called then
		return nil
	end
	if kind == "ticket" or kind == "route" then
		local checked = TravelProtocol.validateOpaqueId(value, kind)
		return if checked.ok then checked.value else nil
	elseif kind == "result" then
		return boundedToken(value, "result", 43)
	else
		return boundedToken(value, "match", 100)
	end
end

local function queueStatus(data: ServiceData, context: Context, status: QueueProtocol.PublicStatus): boolean
	local value =
		callResult(data.dependencies.queue.setTravelStatus, data.dependencies.queue, context.locked.queueId, status)
	return resultOk(value)
end

local function clearRoutes(data: ServiceData, context: Context, onlyUserIds: { number }?): boolean
	local users = onlyUserIds or context.locked.orderedUserIds
	local matchId = context.matchId
	if matchId == nil then
		return true
	end
	local cleared = true
	for _, userId in users do
		local value = callResult(data.dependencies.activeRoutes.clear, data.dependencies.activeRoutes, userId, matchId)
		cleared = resultOk(value) and cleared
	end
	return cleared
end

local function rollbackTransfer(data: ServiceData, context: Context): boolean
	if context.transferHandle == nil then
		return true
	end
	local value = callResult(
		data.dependencies.profileTransfer.rollback,
		data.dependencies.profileTransfer,
		context.transferHandle
	)
	if resultOk(value) then
		context.transferHandle = nil
		return true
	end
	return false
end

local function commitTransfer(data: ServiceData, context: Context): boolean
	if context.transferHandle == nil then
		return true
	end
	local value =
		callResult(data.dependencies.profileTransfer.commit, data.dependencies.profileTransfer, context.transferHandle)
	if resultOk(value) then
		context.transferHandle = nil
		context.transferCommitted = true
		return true
	end
	return false
end

local function resultErrorCode(value: unknown): string?
	return if type(value) == "table" and type((value :: any).error) == "table" then (value :: any).error.code else nil
end

local function terminalTicket(data: ServiceData, context: Context, reason: string, nowValue: number): boolean
	if context.ticketTerminalized or not context.ticketCreationAttempted or context.ticketId == nil then
		return true
	end
	local terminal = callResult(
		data.dependencies.ticketStore.markTerminal,
		data.dependencies.ticketStore,
		context.ticketId,
		reason,
		nowValue
	)
	local code = resultErrorCode(terminal)
	if resultOk(terminal) or code == "NOT_FOUND" or code == "EXPIRED" then
		context.ticketTerminalized = true
		return true
	end
	return false
end

local function cancelResultIntent(data: ServiceData, context: Context, reason: string, nowValue: number): boolean
	if
		context.resultIntentCancelled
		or not context.resultIntentAttempted
		or context.resultIntentConflict
		or context.resultId == nil
		or context.matchId == nil
		or context.ticketId == nil
	then
		return true
	end
	local cancelled = callResult(
		data.dependencies.resultLedger.cancelIntent,
		data.dependencies.resultLedger,
		context.resultId,
		context.matchId,
		context.ticketId,
		reason,
		nowValue
	)
	local code = resultErrorCode(cancelled)
	if resultOk(cancelled) or code == "NOT_FOUND" then
		context.resultIntentCancelled = true
		return true
	end
	return false
end

local function currentPresence(data: ServiceData, userId: number): boolean
	local called, present = pcall(data.dependencies.isPresent, userId)
	return called and present == true
end

local function recoverCommittedProfiles(data: ServiceData, context: Context, partial: boolean): boolean
	if not context.transferCommitted then
		return true
	end
	local complete = true
	for _, userId in context.locked.orderedUserIds do
		local required = if partial
			then context.recoveryPresentUserIds[userId] == true
			else currentPresence(data, userId)
		if not required then
			context.reacquiredUserIds[userId] = true
		elseif not context.reacquiredUserIds[userId] then
			local reacquired = callResult(
				data.dependencies.profileTransfer.recoverCommitted,
				data.dependencies.profileTransfer,
				userId
			)
			if resultOk(reacquired) then
				context.reacquiredUserIds[userId] = true
			end
		end
		complete = context.reacquiredUserIds[userId] == true and complete
	end
	if complete then
		context.transferCommitted = false
	end
	return complete
end

local function releasePendingProfiles(data: ServiceData, context: Context, nowValue: number): boolean
	if not context.pendingReserved or context.resultId == nil then
		return true
	end
	local complete = true
	for _, userId in context.locked.orderedUserIds do
		if not currentPresence(data, userId) then
			-- The compacted failure tombstone clears this marker on the next load.
			context.pendingReleasedUserIds[userId] = true
		elseif not context.pendingReleasedUserIds[userId] then
			local released = callResult(
				data.dependencies.pendingResults.release,
				data.dependencies.pendingResults,
				{ userId },
				context.resultId,
				nowValue
			)
			if resultOk(released) then
				context.pendingReleasedUserIds[userId] = true
			end
		end
		complete = context.pendingReleasedUserIds[userId] == true and complete
	end
	if complete then
		context.pendingReserved = false
	end
	return complete
end

local function clearRecoveryRoutes(data: ServiceData, context: Context): boolean
	if context.matchId == nil then
		return true
	end
	local complete = true
	for _, userId in context.locked.orderedUserIds do
		if not context.routesClearedUserIds[userId] then
			local cleared = callResult(
				data.dependencies.activeRoutes.clear,
				data.dependencies.activeRoutes,
				userId,
				context.matchId
			)
			if resultOk(cleared) then
				context.routesClearedUserIds[userId] = true
			end
		end
		complete = context.routesClearedUserIds[userId] == true and complete
	end
	return complete
end

local function finishTeleportSession(data: ServiceData, context: Context): boolean
	if context.teleportFinished or context.ticketId == nil then
		return true
	end
	local finished = callResult(data.dependencies.safeTeleport.finish, data.dependencies.safeTeleport, context.ticketId)
	if resultOk(finished) then
		context.teleportFinished = true
		return true
	end
	return false
end

local function recoverQueue(data: ServiceData, context: Context): boolean
	if context.queueRecovered then
		return true
	end
	if context.recoveryStatus ~= nil then
		queueStatus(data, context, context.recoveryStatus)
	end
	local recovered = callResult(data.dependencies.queue.recover, data.dependencies.queue, context.locked.queueId)
	if resultOk(recovered) then
		context.queueRecovered = true
		return true
	end
	return false
end

local function detachContext(data: ServiceData, context: Context)
	if context.ticketId ~= nil and data.contextsByTicketId[context.ticketId] == context then
		data.contextsByTicketId[context.ticketId] = nil
	end
	if data.contextsByQueueId[context.locked.queueId] == context then
		data.contextsByQueueId[context.locked.queueId] = nil
	end
end

local function attemptRecovery(data: ServiceData, context: Context, nowValue: number): boolean
	local reason = context.recoveryReason
	if reason == nil or context.settled then
		return context.settled
	end
	if context.partial then
		if not commitTransfer(data, context) or not recoverCommittedProfiles(data, context, true) then
			return false
		end
		if not recoverQueue(data, context) then
			return false
		end
		context.phase = "PartialTeleportFailure"
		context.settled = true
		if not context.recoveryCounted then
			context.recoveryCounted = true
			data.partialFailureCount += 1
		end
		return true
	end

	local ticketSafe = terminalTicket(data, context, reason, nowValue)
	local intentSafe = cancelResultIntent(data, context, reason, nowValue)
	local transferSafe = rollbackTransfer(data, context)
	if transferSafe then
		transferSafe = recoverCommittedProfiles(data, context, false)
	end
	local pendingSafe = if transferSafe then releasePendingProfiles(data, context, nowValue) else false
	local routesSafe = clearRecoveryRoutes(data, context)
	local teleportSafe = finishTeleportSession(data, context)
	if
		not ticketSafe
		or not intentSafe
		or not transferSafe
		or not pendingSafe
		or not routesSafe
		or not teleportSafe
	then
		return false
	end
	if not recoverQueue(data, context) then
		return false
	end
	context.settled = true
	context.phase = if context.simulationRecovery then "StudioSimulated" else reason
	if not context.recoveryCounted then
		context.recoveryCounted = true
		if context.simulationRecovery then
			data.simulatedCount += 1
		else
			data.failureCount += 1
		end
	end
	detachContext(data, context)
	return true
end

local function failFull(data: ServiceData, context: Context, status: PublicFailure, reason: string)
	if context.settled then
		return
	end
	context.phase = "RecoveryPending"
	context.recoveryStatus = status
	context.recoveryReason = reason
	context.partial = false
	attemptRecovery(data, context, currentTime(data) or 0)
end

local function contextCount(data: ServiceData): number
	local count = 0
	for _ in data.contextsByQueueId do
		count += 1
	end
	return count
end

local function createTicket(data: ServiceData, context: Context, prepared: any, nowValue: number): unknown?
	local ticketId = context.ticketId :: string
	local matchId = context.matchId :: string
	local resultId = context.resultId :: string
	local members = table.create(#context.locked.orderedUserIds)
	for index, userId in context.locked.orderedUserIds do
		members[index] = {
			userId = userId,
			loadout = prepared.loadouts[index],
			admissionState = "Expected",
			admittedAt = nil,
		}
	end
	local candidate = {
		version = MatchTicketContract.VERSION,
		revision = 1,
		ticketId = ticketId,
		matchId = matchId,
		resultId = resultId,
		expectedUserIds = table.clone(context.locked.orderedUserIds),
		captainUserId = context.locked.captainUserId,
		mapId = context.locked.configuration.mapId,
		difficultyId = context.locked.configuration.difficultyId,
		privacy = context.locked.configuration.privacy,
		lobbyOrigin = { placeId = data.dependencies.lobbyPlaceId, jobId = data.dependencies.lobbyJobId },
		members = members,
		createdAt = nowValue,
		expiresAt = nowValue + data.ticketLifetimeSeconds,
		claimedDestinationJobId = nil,
		claimedDestinationAt = nil,
		state = "Created",
		retryCount = 0,
		terminalReason = nil,
	}
	local validated = MatchTicketContract.validate(candidate)
	return if validated.ok then validated.value else nil
end

local function exactContent(left: unknown, right: unknown, depth: number, nodes: { count: number }): boolean
	if typeof(left) ~= typeof(right) then
		return false
	elseif type(left) ~= "table" then
		return left == right
	elseif depth > 8 or getmetatable(left :: any) ~= nil or getmetatable(right :: any) ~= nil then
		return false
	end
	nodes.count += 1
	if nodes.count > 256 then
		return false
	end
	local leftRecord = left :: { [any]: unknown }
	local rightRecord = right :: { [any]: unknown }
	local count = 0
	for key, value in leftRecord do
		if key ~= "revision" or depth ~= 0 then
			if rawget(rightRecord, key) == nil or not exactContent(value, rightRecord[key], depth + 1, nodes) then
				return false
			end
			count += 1
		end
	end
	local rightCount = 0
	for key in rightRecord do
		if key ~= "revision" or depth ~= 0 then
			rightCount += 1
		end
	end
	return count == rightCount
end

local function preparedMatchesLock(context: Context, prepared: any): boolean
	if type(prepared) ~= "table" or type(prepared.loadouts) ~= "table" then
		return false
	end
	local preparedLoadouts = prepared.loadouts :: { unknown }
	if #preparedLoadouts ~= #context.locked.members then
		return false
	end
	for index, memberValue in context.locked.members do
		local expectedUserId = context.locked.orderedUserIds[index]
		local preparedLoadout = preparedLoadouts[index]
		if
			type(memberValue) ~= "table"
			or (memberValue :: any).userId ~= expectedUserId
			or type((memberValue :: any).loadout) ~= "table"
			or type(preparedLoadout) ~= "table"
			or (preparedLoadout :: any).userId ~= expectedUserId
		then
			return false
		end
		local lockedLoadout = (memberValue :: any).loadout
		local lockedRevision = safeInteger(lockedLoadout.revision)
		local preparedRevision = safeInteger((preparedLoadout :: any).revision)
		if
			lockedRevision == nil
			or preparedRevision == nil
			or preparedRevision ~= lockedRevision + 1
			or not exactContent(lockedLoadout, preparedLoadout, 0, { count = 0 })
		then
			return false
		end
	end
	return true
end

local function process(data: ServiceData, context: Context)
	if data.cleaned or context.settled or context.phase ~= "Scheduled" then
		return
	end
	context.phase = "Preparing"
	local nowValue = currentTime(data)
	local ticketId = freshId(data, "ticket")
	local matchId = freshId(data, "match")
	local resultId = freshId(data, "result")
	if nowValue == nil or ticketId == nil or matchId == nil or resultId == nil then
		failFull(data, context, "TicketFailed", "ID_OR_CLOCK_FAILED")
		return
	end
	context.ticketId = ticketId
	context.matchId = matchId
	context.resultId = resultId
	data.contextsByTicketId[ticketId] = context

	context.resultIntentAttempted = true
	local intentCreated = callResult(data.dependencies.resultLedger.createIntent, data.dependencies.resultLedger, {
		version = 1,
		resultId = resultId,
		matchId = matchId,
		ticketId = ticketId,
		expectedUserIds = table.clone(context.locked.orderedUserIds),
		createdAt = nowValue,
	})
	if not resultOk(intentCreated) then
		context.resultIntentConflict = resultErrorCode(intentCreated) == "RESULT_CONFLICT"
		failFull(data, context, "TicketFailed", "RESULT_INTENT_CREATE_FAILED")
		return
	end
	context.resultIntentCreated = true
	local reserved = callResult(
		data.dependencies.pendingResults.reserve,
		data.dependencies.pendingResults,
		context.locked.orderedUserIds,
		resultId,
		nowValue
	)
	if not resultOk(reserved) then
		failFull(data, context, "TicketFailed", "PENDING_RESULT_RESERVE_FAILED")
		return
	end
	context.pendingReserved = true

	local prepared = callResult(
		data.dependencies.profileTransfer.prepare,
		data.dependencies.profileTransfer,
		context.locked.orderedUserIds
	)
	if not resultOk(prepared) then
		failFull(data, context, "TicketFailed", "PROFILE_TRANSFER_FAILED")
		return
	end
	local preparedValue = (prepared :: any).value
	context.transferHandle = preparedValue.handle
	if not preparedMatchesLock(context, preparedValue) then
		failFull(data, context, "TicketFailed", "LOADOUT_CHANGED_AFTER_LOCK")
		return
	end
	local ticket = createTicket(data, context, preparedValue, nowValue)
	if ticket == nil then
		failFull(data, context, "TicketFailed", "TICKET_INVALID")
		return
	end
	context.ticketCreationAttempted = true
	local created = callResult(data.dependencies.ticketStore.create, data.dependencies.ticketStore, ticket)
	if not resultOk(created) then
		failFull(data, context, "TicketFailed", "TICKET_CREATE_FAILED")
		return
	end
	context.ticketCreated = true
	context.phase = "Teleporting"
	local players: { unknown } = table.create(#context.locked.orderedUserIds)
	for index, userId in context.locked.orderedUserIds do
		local called, player = pcall(data.dependencies.getPlayer, userId)
		if not called or player == nil then
			failFull(data, context, "TeleportFailed", "PLAYER_MISSING")
			return
		end
		players[index] = player
	end
	local started = callResult(
		data.dependencies.safeTeleport.start,
		data.dependencies.safeTeleport,
		ticketId,
		data.dependencies.matchPlaceId,
		players
	)
	if data.cleaned then
		return
	end
	if not resultOk(started) then
		if not context.settled and not context.partial and context.phase ~= "RecoveryPending" then
			failFull(data, context, "TeleportFailed", "TELEPORT_INITIALIZATION_FAILED")
		end
		return
	end
	if context.settled then
		return
	end
	if data.dependencies.developmentSimulation == true then
		context.simulationRecovery = true
		failFull(data, context, "TeleportFailed", "STUDIO_SIMULATED")
		return
	end
	if not commitTransfer(data, context) then
		failFull(data, context, "TeleportFailed", "TRANSFER_COMMIT_FAILED")
		return
	end
	-- Teleport initialization is already live once the adapter and profile
	-- transfer commit succeed. Record that fact before finalizing the Lobby queue
	-- so a narrow queue-finalization error cannot make cleanup terminalize a
	-- reward-capable ticket or suppress a later TeleportInitFailed rollback.
	context.initialized = true
	local completed = callResult(data.dependencies.queue.completeStart, data.dependencies.queue, context.locked.queueId)
	if not resultOk(completed) then
		context.phase = "QueueCompletionPending"
		return
	end
	context.phase = "Initialized"
	data.completedCount += 1
end

function Methods.beginStart(self: Service, lockedValue: unknown): boolean
	local data = requireData(self)
	if data.cleaned then
		return false
	end
	local locked = lockedStart(lockedValue)
	if locked == nil or data.contextsByQueueId[locked.queueId] ~= nil or contextCount(data) >= MAX_CONTEXTS then
		return false
	end
	local context: Context = {
		locked = locked,
		phase = "Scheduled",
		ticketId = nil,
		matchId = nil,
		resultId = nil,
		routeIds = {},
		transferHandle = nil,
		transferCommitted = false,
		pendingReserved = false,
		resultIntentAttempted = false,
		resultIntentCreated = false,
		resultIntentConflict = false,
		resultIntentCancelled = false,
		ticketCreated = false,
		ticketCreationAttempted = false,
		ticketTerminalized = false,
		initialized = false,
		settled = false,
		partial = false,
		departedUserIds = {},
		guardExpiresAt = nil,
		recoveryStatus = nil,
		recoveryReason = nil,
		recoveryPresentUserIds = {},
		reacquiredUserIds = {},
		pendingReleasedUserIds = {},
		routesClearedUserIds = {},
		queueRecovered = false,
		teleportFinished = false,
		recoveryCounted = false,
		simulationRecovery = false,
	}
	data.contextsByQueueId[locked.queueId] = context
	local scheduling = true
	local ranInline = false
	local scheduled, scheduleResult = pcall(data.dependencies.schedule, function()
		if scheduling then
			ranInline = true
			data.scheduleViolationCount += 1
			return
		end
		process(data, context)
	end)
	scheduling = false
	if not scheduled or scheduleResult == false or ranInline then
		data.contextsByQueueId[locked.queueId] = nil
		return false
	end
	return true
end

function Methods.onReserved(self: Service, reservedValue: unknown): boolean
	local data = requireData(self)
	if data.cleaned or type(reservedValue) ~= "table" then
		return false
	end
	local reserved = reservedValue :: any
	local context = if type(reserved.ticketId) == "string" then data.contextsByTicketId[reserved.ticketId] else nil
	if
		context == nil
		or context.settled
		or context.ticketId ~= reserved.ticketId
		or reserved.placeId ~= data.dependencies.matchPlaceId
		or type(reserved.accessCode) ~= "string"
		or #reserved.accessCode < 1
		or #reserved.accessCode > 200
		or type(reserved.orderedUserIds) ~= "table"
		or #reserved.orderedUserIds ~= #context.locked.orderedUserIds
	then
		return false
	end
	for index, userId in context.locked.orderedUserIds do
		if reserved.orderedUserIds[index] ~= userId then
			return false
		end
	end
	local nowValue = currentTime(data)
	if nowValue == nil then
		return false
	end
	context.guardExpiresAt = nowValue + data.routeLifetimeSeconds
	local createdUsers: { number } = {}
	for _, userId in context.locked.orderedUserIds do
		local routeId = freshId(data, "route")
		if routeId == nil then
			clearRoutes(data, context, createdUsers)
			return false
		end
		local route = {
			version = 1,
			revision = 1,
			routeId = routeId,
			userId = userId,
			ticketId = context.ticketId,
			matchId = context.matchId,
			destinationPlaceId = data.dependencies.matchPlaceId,
			destinationJobId = nil,
			reservedServerAccessCode = reserved.accessCode,
			createdAt = nowValue,
			expiresAt = nowValue + data.routeLifetimeSeconds,
		}
		local created =
			callResult(data.dependencies.activeRoutes.create, data.dependencies.activeRoutes, route, nowValue)
		if not resultOk(created) then
			clearRoutes(data, context, createdUsers)
			return false
		end
		context.routeIds[userId] = routeId
		table.insert(createdUsers, userId)
	end
	return queueStatus(data, context, "TeleportInitializing")
end

function Methods.onRollback(self: Service, rollbackValue: unknown)
	local data = requireData(self)
	if data.cleaned or type(rollbackValue) ~= "table" then
		return
	end
	local rollback = rollbackValue :: any
	local context = if type(rollback.ticketId) == "string" then data.contextsByTicketId[rollback.ticketId] else nil
	if context == nil or context.settled then
		return
	end
	local departed = if type(rollback.departedUserIds) == "table" then rollback.departedUserIds else {}
	local present = if type(rollback.presentUserIds) == "table" then rollback.presentUserIds else {}
	local partial = rollback.partial == true or #departed > 0
	if partial then
		context.partial = true
		for _, userId in departed do
			if safeInteger(userId) ~= nil and table.find(context.locked.orderedUserIds, userId) ~= nil then
				context.departedUserIds[userId] = true
			end
		end
		for _, userId in present do
			if safeInteger(userId) ~= nil and table.find(context.locked.orderedUserIds, userId) ~= nil then
				context.recoveryPresentUserIds[userId] = true
			end
		end
		context.recoveryStatus = "PartialTeleportFailure"
		context.recoveryReason = "PARTIAL_TELEPORT_FAILURE"
		context.phase = "RecoveryPending"
		attemptRecovery(data, context, currentTime(data) or 0)
		return
	end
	failFull(data, context, "TeleportFailed", "TELEPORT_ROLLBACK")
end

function Methods.isUserTravelPending(self: Service, userIdValue: unknown): boolean
	local data = requireData(self)
	local userId = safeInteger(userIdValue)
	if userId == nil or data.cleaned then
		return false
	end
	for _, context in data.contextsByQueueId do
		if context.pendingReserved then
			for _, expectedUserId in context.locked.orderedUserIds do
				if expectedUserId == userId then
					return true
				end
			end
		end
	end
	return false
end

function Methods.step(self: Service): number
	local data = requireData(self)
	if data.cleaned then
		return 0
	end
	local nowValue = currentTime(data)
	if nowValue == nil then
		return 0
	end
	local progressed = 0
	local removable: { Context } = {}
	for _, context in data.contextsByQueueId do
		if not context.settled and context.phase == "RecoveryPending" then
			if attemptRecovery(data, context, nowValue) then
				progressed += 1
			end
		elseif not context.settled and context.phase == "QueueCompletionPending" then
			local completed =
				callResult(data.dependencies.queue.completeStart, data.dependencies.queue, context.locked.queueId)
			if resultOk(completed) then
				context.phase = "Initialized"
				data.completedCount += 1
				progressed += 1
			end
		end

		if
			context.partial
			and context.settled
			and context.guardExpiresAt ~= nil
			and context.guardExpiresAt <= nowValue
		then
			local terminal = terminalTicket(data, context, "LOBBY_RECONCILE_EXPIRED", nowValue)
			local routes = clearRoutes(data, context, nil)
			local finished = finishTeleportSession(data, context)
			if terminal and routes and finished then
				table.insert(removable, context)
				progressed += 1
			end
		elseif context.initialized and context.phase == "Initialized" then
			local allAbsent = true
			for _, userId in context.locked.orderedUserIds do
				allAbsent = not currentPresence(data, userId) and allAbsent
			end
			if allAbsent and finishTeleportSession(data, context) then
				table.insert(removable, context)
				progressed += 1
			end
		end
	end
	for _, context in removable do
		if context.ticketId ~= nil then
			data.contextsByTicketId[context.ticketId] = nil
		end
		if data.contextsByQueueId[context.locked.queueId] == context then
			data.contextsByQueueId[context.locked.queueId] = nil
		end
	end
	return progressed
end

function Methods.resolveTicket(self: Service, ticketIdValue: unknown): boolean
	local data = requireData(self)
	local ticketId = TravelProtocol.validateOpaqueId(ticketIdValue, "ticket")
	local context = if ticketId.ok then data.contextsByTicketId[ticketId.value] else nil
	if context == nil then
		return false
	end
	clearRoutes(data, context, nil)
	pcall(data.dependencies.safeTeleport.finish, data.dependencies.safeTeleport, ticketId.value)
	data.contextsByTicketId[ticketId.value] = nil
	if data.contextsByQueueId[context.locked.queueId] == context then
		data.contextsByQueueId[context.locked.queueId] = nil
	end
	return true
end

function Methods.getContextSummary(self: Service, queueIdValue: unknown): { [string]: unknown }?
	local data = requireData(self)
	local queueId = Ids.validateQueueId(queueIdValue)
	local context = if queueId.ok then data.contextsByQueueId[queueId.value] else nil
	if context == nil then
		return nil
	end
	return table.freeze({
		phase = context.phase,
		initialized = context.initialized,
		settled = context.settled,
		partial = context.partial,
		ticketId = context.ticketId,
		matchId = context.matchId,
		resultId = context.resultId,
	})
end

function Methods.removePlayer(self: Service, userIdValue: unknown): boolean
	local data = requireData(self)
	local userId = safeInteger(userIdValue)
	if userId == nil then
		return false
	end
	local changed = false
	for _, context in data.contextsByTicketId do
		for _, expectedUserId in context.locked.orderedUserIds do
			if expectedUserId == userId then
				context.departedUserIds[userId] = true
				changed = true
				break
			end
		end
		-- Final queue cleanup is retried by step(). In particular, never discard a
		-- QueueCompletionPending context merely because the last player departed.
	end
	return changed
end

function Methods.cleanup(self: Service): Result.Result<boolean, CoordinatorError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	local recoveryComplete = true
	local contexts = table.create(contextCount(data))
	for _, context in data.contextsByQueueId do
		table.insert(contexts, context)
	end
	for _, context in contexts do
		if not context.settled and context.phase == "RecoveryPending" then
			if not attemptRecovery(data, context, currentTime(data) or 0) then
				recoveryComplete = false
			end
		elseif not context.initialized and not context.partial then
			local nowValue = currentTime(data) or 0
			context.recoveryStatus = "TeleportFailed"
			context.recoveryReason = "LOBBY_SHUTDOWN"
			context.phase = "RecoveryPending"
			if not attemptRecovery(data, context, nowValue) then
				recoveryComplete = false
			end
		end
	end
	if not recoveryComplete then
		-- Keep every unfinished context live so a later bounded shutdown attempt can
		-- continue only the idempotent recovery work that has not yet succeeded.
		return failure("BUSY", "cleanup")
	end
	data.cleaned = true
	table.clear(data.contextsByQueueId)
	table.clear(data.contextsByTicketId)
	return Result.ok(true)
end

function Methods.getMetrics(self: Service): { [string]: number | boolean }
	local data = requireData(self)
	return table.freeze({
		contextCount = contextCount(data),
		completedCount = data.completedCount,
		failureCount = data.failureCount,
		partialFailureCount = data.partialFailureCount,
		simulatedCount = data.simulatedCount,
		scheduleViolationCount = data.scheduleViolationCount,
		cleaned = data.cleaned,
	})
end

function Methods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	return table.freeze({
		name = "LobbyTravelCoordinator",
		dependencies = table.freeze({}),
		initialize = function() end,
		start = function() end,
		shutdown = function()
			for _attempt = 1, SHUTDOWN_DURABILITY_ATTEMPTS do
				local cleaned = self:cleanup()
				if cleaned.ok then
					return
				end
			end
			-- TravelRecordStore and the other production boundaries already own their
			-- protected retry/backoff. This outer fixed count retries the coherent
			-- cross-boundary recovery without exceeding the BindToClose budget.
			error("[ATD_LOBBY_TRAVEL][code=SHUTDOWN_DURABILITY_FAILED]", 0)
		end,
	})
end

function LobbyTravelCoordinator.new(dependenciesValue: unknown): Result.Result<Service, CoordinatorError>
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local dependencies = dependenciesValue :: any
	if
		type(dependencies.clock) ~= "function"
		or type(dependencies.schedule) ~= "function"
		or type(dependencies.makeId) ~= "function"
		or type(dependencies.ticketStore) ~= "table"
		or type(dependencies.ticketStore.create) ~= "function"
		or type(dependencies.ticketStore.markTerminal) ~= "function"
		or type(dependencies.pendingResults) ~= "table"
		or type(dependencies.pendingResults.reserve) ~= "function"
		or type(dependencies.pendingResults.release) ~= "function"
		or type(dependencies.resultLedger) ~= "table"
		or type(dependencies.resultLedger.createIntent) ~= "function"
		or type(dependencies.resultLedger.cancelIntent) ~= "function"
		or type(dependencies.profileTransfer) ~= "table"
		or type(dependencies.profileTransfer.prepare) ~= "function"
		or type(dependencies.profileTransfer.rollback) ~= "function"
		or type(dependencies.profileTransfer.recoverCommitted) ~= "function"
		or type(dependencies.profileTransfer.commit) ~= "function"
		or type(dependencies.safeTeleport) ~= "table"
		or type(dependencies.safeTeleport.start) ~= "function"
		or type(dependencies.safeTeleport.finish) ~= "function"
		or type(dependencies.activeRoutes) ~= "table"
		or type(dependencies.activeRoutes.create) ~= "function"
		or type(dependencies.activeRoutes.clear) ~= "function"
		or type(dependencies.queue) ~= "table"
		or type(dependencies.queue.setTravelStatus) ~= "function"
		or type(dependencies.queue.recover) ~= "function"
		or type(dependencies.queue.completeStart) ~= "function"
		or type(dependencies.getPlayer) ~= "function"
		or type(dependencies.isPresent) ~= "function"
		or safeInteger(dependencies.lobbyPlaceId) == nil
		or safeInteger(dependencies.matchPlaceId) == nil
		or type(dependencies.lobbyJobId) ~= "string"
		or #dependencies.lobbyJobId < 1
		or #dependencies.lobbyJobId > 100
		or (dependencies.developmentSimulation ~= nil and type(dependencies.developmentSimulation) ~= "boolean")
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local ticketLifetime = dependencies.ticketLifetimeSeconds or DEFAULT_TICKET_LIFETIME_SECONDS
	local routeLifetime = dependencies.routeLifetimeSeconds or DEFAULT_ROUTE_LIFETIME_SECONDS
	if
		type(ticketLifetime) ~= "number"
		or not Validation.isSafeInteger(ticketLifetime)
		or ticketLifetime < 1
		or ticketLifetime > MatchTicketContract.MAX_TTL_SECONDS
		or type(routeLifetime) ~= "number"
		or not Validation.isSafeInteger(routeLifetime)
		or routeLifetime < 1
		or routeLifetime > DEFAULT_ROUTE_LIFETIME_SECONDS
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		dependencies = dependenciesValue :: Dependencies,
		ticketLifetimeSeconds = ticketLifetime,
		routeLifetimeSeconds = routeLifetime,
		contextsByQueueId = {},
		contextsByTicketId = {},
		cleaned = false,
		scheduleViolationCount = 0,
		completedCount = 0,
		failureCount = 0,
		partialFailureCount = 0,
		simulatedCount = 0,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(LobbyTravelCoordinator)
