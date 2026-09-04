--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local MatchTravelProtocol = require(ReplicatedStorage.Shared.match.MatchTravelProtocol)
local PlacementProtocol = require(ReplicatedStorage.Shared.match.PlacementProtocol)
local PlayableMatchProtocol = require(ReplicatedStorage.Shared.match.PlayableMatchProtocol)
local MatchLoadoutProtocol = require(ReplicatedStorage.Shared.match.MatchLoadoutProtocol)
local WaveProtocol = require(ReplicatedStorage.Shared.match.WaveProtocol)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)

local ServerBootstrap = require(script.Parent.ServerBootstrap)
local ServerRequestDispatcher = require(script.Parent.Parent.networking.ServerRequestDispatcher)
local ProfileService = require(script.Parent.Parent.profile.ProfileService)
local ProfileStoreAdapter = require(script.Parent.Parent.profile.ProfileStoreAdapter)
local PendingResultService = require(script.Parent.Parent.profile.PendingResultService)
local ActiveMatchRouteService = require(script.Parent.Parent.travel.ActiveMatchRouteService)
local MatchTicketContract = require(script.Parent.Parent.travel.MatchTicketContract)
local MemoryStoreTravelAdapter = require(script.Parent.Parent.travel.MemoryStoreTravelAdapter)
local ProfileTransferCoordinator = require(script.Parent.Parent.travel.ProfileTransferCoordinator)
local ReturnRecordService = require(script.Parent.Parent.travel.ReturnRecordService)
local SafeTeleportService = require(script.Parent.Parent.travel.SafeTeleportService)
local TeleportAdapter = require(script.Parent.Parent.travel.TeleportAdapter)
local TravelRecordStore = require(script.Parent.Parent.travel.TravelRecordStore)
local MatchAdmissionService = require(script.Parent.Parent.Parent.match.admission.MatchAdmissionService)
local MatchLifecycleService = require(script.Parent.Parent.Parent.match.lifecycle.MatchLifecycleService)
local PlayableMatchService = require(script.Parent.Parent.Parent.match.playable.PlayableMatchService)
local ProfileRewardClaimService = require(script.Parent.Parent.Parent.match.rewards.ProfileRewardClaimService)
local ResultLedgerService = require(script.Parent.Parent.Parent.match.rewards.ResultLedgerService)
local ResultLedgerStoreAdapter = require(script.Parent.Parent.Parent.match.rewards.ResultLedgerStoreAdapter)
local MatchTravelHost = require(script.Parent.Parent.Parent.match.travel.MatchTravelHost)
local RematchRecoveryScope = require(script.Parent.Parent.Parent.match.travel.RematchRecoveryScope)
local UnexpectedReturnService = require(script.Parent.Parent.Parent.match.travel.UnexpectedReturnService)

local function publicError(code: RequestProtocol.PublicErrorCode): RequestProtocol.PublicError
	local result = RequestProtocol.createPublicError(code, nil)
	if not result.ok then
		error("[ATD_MATCH_BOOTSTRAP][code=PUBLIC_ERROR_CONSTRUCTION_FAILED]", 0)
	end
	return result.value
end

local PUBLIC_ERRORS: { [string]: RequestProtocol.PublicError } = table.freeze({
	STALE_REQUEST = publicError("STALE_REQUEST"),
	DUPLICATE_REQUEST = publicError("DUPLICATE_REQUEST"),
	NOT_AUTHORIZED = publicError("NOT_AUTHORIZED"),
	UNAVAILABLE = publicError("UNAVAILABLE"),
	INTERNAL_ERROR = publicError("INTERNAL_ERROR"),
})

local function authorizeLiveContext(context: ServerRequestDispatcher.ServerContext): boolean
	if not ServerRequestDispatcher.isContext(context) then
		return false
	end
	local player = context.player
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local function unavailable(_context: ServerRequestDispatcher.ServerContext, _payload: unknown)
	return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
end

local function actionOutcome(receipt: PlayableMatchProtocol.ActionReceipt?): ServerRequestDispatcher.HandlerOutcome
	return if receipt == nil
		then ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		else ServerRequestDispatcher.success(receipt)
end

local function resultOk(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function resultCode(value: unknown): string?
	return if type(value) == "table"
			and type((value :: any).error) == "table"
			and type((value :: any).error.code) == "string"
		then (value :: any).error.code
		else nil
end

local function requireResult(value: any, code: string): any
	if not resultOk(value) then
		error(`[ATD_MATCH_BOOTSTRAP][code={code}]`, 0)
	end
	return value.value
end

local function livePlayer(player: Player): boolean
	return player.Parent == Players and player.UserId > 0 and Players:GetPlayerByUserId(player.UserId) == player
end

local function freshId(kind: "match" | "result" | "ticket" | "route" | "return"): string?
	local generated, guid = pcall(HttpService.GenerateGUID, HttpService, false)
	if not generated or type(guid) ~= "string" then
		return nil
	end
	local value = `{kind}:{string.lower(guid :: string)}`
	if kind == "ticket" or kind == "route" or kind == "return" then
		return if TravelProtocol.validateOpaqueId(value, kind).ok then value else nil
	end
	return if #value <= (if kind == "result" then 43 else 100) then value else nil
end

local function sameFlatRecord(left: unknown, right: unknown): boolean
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
	local count = 0
	for key, value in left :: any do
		if (right :: any)[key] ~= value then
			return false
		end
		count += 1
	end
	local otherCount = 0
	for _ in right :: any do
		otherCount += 1
	end
	return count == otherCount
end

local function sameLoadout(left: MatchLoadoutProtocol.Snapshot, right: MatchLoadoutProtocol.Snapshot): boolean
	if left.userId ~= right.userId or left.revision ~= right.revision or #left.slots ~= #right.slots then
		return false
	end
	for index, slot in left.slots do
		local other = right.slots[index]
		if other == nil or slot.slot ~= other.slot or slot.unitId ~= other.unitId or slot.towerId ~= other.towerId then
			return false
		end
	end
	return sameFlatRecord(left.settings, right.settings)
end

local function sameLoadoutContent(left: MatchLoadoutProtocol.Snapshot, right: MatchLoadoutProtocol.Snapshot): boolean
	if left.userId ~= right.userId or right.revision < left.revision or #left.slots ~= #right.slots then
		return false
	end
	for index, slot in left.slots do
		local other = right.slots[index]
		if other == nil or slot.slot ~= other.slot or slot.unitId ~= other.unitId or slot.towerId ~= other.towerId then
			return false
		end
	end
	return sameFlatRecord(left.settings, right.settings)
end

ServerBootstrap.run(PlaceRoles.MATCH_ROLE, function(configuration)
	local network = configuration.serverRemoteRegistry
	if network == nil then
		error("[ATD_MATCH_BOOTSTRAP][code=NETWORK_REGISTRY_MISSING]", 0)
	end

	-- Bind every production outbound contract exactly once. The legacy senders
	-- remain available to MatchLifecycle, while the playable outcome owns the
	-- compact combat/world presentation stream.
	local sendMatchSnapshot =
		network:registerServerEvent(MatchProtocol.MATCH_SNAPSHOT_ENDPOINT, MatchProtocol.MatchSnapshotSchema)
	network:registerServerEvent(BaseProtocol.BASE_REPLICATION_ENDPOINT, BaseProtocol.BaseReplicationSchema)
	network:registerServerEvent(EnemyProtocol.ENEMY_REPLICATION_ENDPOINT, EnemyProtocol.EnemyReplicationSchema)
	network:registerServerEvent(WaveProtocol.WAVE_REPLICATION_ENDPOINT, WaveProtocol.WaveSnapshotSchema)
	network:registerServerEvent(PlacementProtocol.REVISION_ENDPOINT, PlacementProtocol.RevisionEventSchema)
	local sendPlayableSnapshot =
		network:registerServerEvent(PlayableMatchProtocol.ENDPOINTS.REPLICATION, PlayableMatchProtocol.SnapshotSchema)
	local sendTravelSnapshot =
		network:registerServerEvent(MatchTravelProtocol.ENDPOINTS.REPLICATION, MatchTravelProtocol.SnapshotSchema)
	local sendAttack = network:registerServerEvent(
		PlayableMatchProtocol.ENDPOINTS.ATTACK_EVENT,
		PlayableMatchProtocol.AttackEventSchema
	)

	local matchLifecycle = MatchLifecycleService.new(configuration.log, sendMatchSnapshot)
	local storeResult = if RunService:IsStudio()
		then ProfileStoreAdapter.newStudioDevelopment()
		else ProfileStoreAdapter.newPublished(configuration.deployment)
	if not storeResult.ok then
		error("[ATD_MATCH_BOOTSTRAP][code=PROFILE_STORE_UNAVAILABLE]", 0)
	end
	local profileResult = ProfileService.new(configuration.coreConfiguration.towers, storeResult.value, nil)
	if not profileResult.ok then
		error("[ATD_MATCH_BOOTSTRAP][code=PROFILE_SERVICE_CREATION_FAILED]", 0)
	end
	local profile = profileResult.value
	local function snapshotLoadout(userId: number, saved: any): MatchLoadoutProtocol.Snapshot?
		local slots = table.create(#saved.equippedUnitIds)
		for slot, unitId in saved.equippedUnitIds do
			local unit = saved.units[unitId]
			if unit == nil then
				return nil
			end
			slots[slot] = {
				slot = slot,
				unitId = unit.unitId,
				towerId = unit.towerId,
			}
		end
		local validated = MatchLoadoutProtocol.validate({
			userId = userId,
			revision = saved.revision,
			slots = slots,
			settings = saved.settings,
		}, configuration.coreConfiguration)
		return if validated.ok then validated.value else nil
	end
	local function loadoutFor(userId: number): MatchLoadoutProtocol.Snapshot?
		local readResult = profile:read(userId)
		return if readResult.ok then snapshotLoadout(userId, readResult.value) else nil
	end

	local playable: PlayableMatchService.Service? = nil
	local travelHost: MatchTravelHost.Service? = nil
	local ticketedReservedHost = not RunService:IsStudio()
		and game.PrivateServerId ~= ""
		and game.PrivateServerOwnerId == 0
	if not ticketedReservedHost then
		playable = PlayableMatchService.new(
			configuration.log,
			matchLifecycle,
			configuration.coreConfiguration,
			sendPlayableSnapshot,
			sendAttack,
			loadoutFor
		)
	else
		local lobbyPlaceId = PlaceRoles.getConfiguredPlaceId(configuration.deployment, PlaceRoles.LOBBY_ROLE)
		local matchPlaceId = PlaceRoles.getConfiguredPlaceId(configuration.deployment, PlaceRoles.MATCH_ROLE)
		if lobbyPlaceId == nil or matchPlaceId == nil or game.JobId == "" then
			error("[ATD_MATCH_BOOTSTRAP][code=TRAVEL_PLACE_CONFIGURATION_MISSING]", 0)
		end
		local travelAdapter = requireResult(
			MemoryStoreTravelAdapter.newPublished(configuration.deployment),
			"TRAVEL_MEMORY_ADAPTER_UNAVAILABLE"
		)
		local ticketStore = requireResult(TravelRecordStore.new(travelAdapter), "TICKET_STORE_UNAVAILABLE")
		local routes = requireResult(ActiveMatchRouteService.new(travelAdapter), "ROUTE_STORE_UNAVAILABLE")
		local returnRecords = requireResult(ReturnRecordService.new(travelAdapter), "RETURN_STORE_UNAVAILABLE")
		local teleport = requireResult(TeleportAdapter.newProduction(), "TELEPORT_ADAPTER_UNAVAILABLE")
		local resultStore =
			requireResult(ResultLedgerStoreAdapter.newPublished(configuration.deployment), "RESULT_STORE_UNAVAILABLE")
		local resultLedger = requireResult(ResultLedgerService.new(resultStore, os.time), "RESULT_LEDGER_UNAVAILABLE")
		local rewardClaims = requireResult(
			ProfileRewardClaimService.new(profile, resultLedger, configuration.coreConfiguration, os.time),
			"REWARD_CLAIMS_UNAVAILABLE"
		)
		local pendingResults = requireResult(PendingResultService.new(profile), "PENDING_RESULTS_UNAVAILABLE")
		local profileTransfer = requireResult(
			ProfileTransferCoordinator.new(profile, {
				isPresent = function(userId)
					local player = Players:GetPlayerByUserId(userId)
					return player ~= nil and livePlayer(player)
				end,
				snapshotLoadout = function(userId, saved)
					return snapshotLoadout(userId, saved)
				end,
			}),
			"PROFILE_TRANSFER_UNAVAILABLE"
		)
		local unexpectedOwnershipTransfer = requireResult(
			ProfileTransferCoordinator.new(profile, {
				isPresent = function(userId)
					local player = Players:GetPlayerByUserId(userId)
					return player ~= nil and livePlayer(player)
				end,
				snapshotLoadout = function(userId, _saved)
					return { userId = userId, ownershipRelease = true }
				end,
			}),
			"UNEXPECTED_OWNERSHIP_TRANSFER_UNAVAILABLE"
		)
		local admission = requireResult(
			MatchAdmissionService.new(ticketStore, routes, {
				getUserId = function(player)
					return if typeof(player) == "Instance" and player:IsA("Player") then player.UserId else nil
				end,
				isLive = function(player)
					return typeof(player) == "Instance" and player:IsA("Player") and livePlayer(player)
				end,
				validateProfile = function(userId, frozenLoadout)
					if profile:getState(userId) ~= "Ready" then
						return false
					end
					local frozen = MatchLoadoutProtocol.validate(frozenLoadout, configuration.coreConfiguration)
					local current = loadoutFor(userId)
					return frozen.ok
						and current ~= nil
						and frozen.value.userId == userId
						and sameLoadout(frozen.value, current)
				end,
				validateRejoinProfile = function(userId, frozenLoadout)
					if profile:getState(userId) ~= "Ready" then
						return false
					end
					local frozen = MatchLoadoutProtocol.validate(frozenLoadout, configuration.coreConfiguration)
					local current = loadoutFor(userId)
					return frozen.ok
						and current ~= nil
						and frozen.value.userId == userId
						and sameLoadoutContent(frozen.value, current)
				end,
			}),
			"MATCH_ADMISSION_UNAVAILABLE"
		)

		local rematchDependenciesCleaned = false
		local dependencyCleanupPrepared = false
		local rematchRecovery = RematchRecoveryScope.new(function(delaySeconds, callback)
			return task.delay(delaySeconds, callback)
		end, function(handle)
			task.cancel(handle :: thread)
		end)
		local REMATCH_RECOVERY_FAST_PASSES = 120
		local REMATCH_RECOVERY_FAST_DELAY_SECONDS = 0.5
		local REMATCH_RECOVERY_SLOW_DELAY_SECONDS = 5
		local function rematchContextActive(context): boolean
			return not rematchDependenciesCleaned
				and type(context) == "table"
				and type(context.ticket) == "table"
				and rematchRecovery:get(context.ticket.ticketId) == context
				and not context.settled
		end
		local function restoreRoute(route)
			local currentTime = os.time()
			if route ~= nil and route.expiresAt > currentTime then
				local called, restored = pcall(routes.create, routes, route, currentTime)
				return called and resultOk(restored)
			end
			-- An old route that expires during a prolonged rollback is already a
			-- safe fail-open Lobby outcome and must not keep recovery alive forever.
			return true
		end
		local function clearRematchRoutes(context, userIds)
			for _, userId in userIds do
				pcall(routes.clear, routes, userId, context.ticket.matchId)
				restoreRoute(context.oldRoutes[userId])
			end
		end
		local safeTeleport: any = nil
		local function closeRematchResultIntent(context, reason, requireActive: boolean?): boolean
			if context.resultIntentClosed then
				return true
			end
			for attempt = 1, 3 do
				if requireActive and not rematchContextActive(context) then
					return false
				end
				local called, marked = pcall(
					resultLedger.cancelIntent,
					resultLedger,
					context.ticket.resultId,
					context.ticket.matchId,
					context.ticket.ticketId,
					reason,
					os.time()
				)
				if called and (resultOk(marked) or resultCode(marked) == "NOT_FOUND") then
					context.resultIntentClosed = true
					break
				elseif attempt < 3 then
					task.wait(0.1)
				end
			end
			return context.resultIntentClosed
		end
		local function terminalizeRematchTicket(context, reason): boolean
			if context.ticketTerminal then
				return true
			end
			for attempt = 1, 3 do
				if not rematchContextActive(context) then
					return false
				end
				local called, terminal =
					pcall(ticketStore.markTerminal, ticketStore, context.ticket.ticketId, reason, os.time())
				if called and (resultOk(terminal) or resultCode(terminal) == "NOT_FOUND") then
					context.ticketTerminal = true
					break
				elseif attempt < 3 then
					task.wait(0.1)
				end
			end
			return context.ticketTerminal
		end
		local function restoreFailedRoute(context, userId): boolean
			if not rematchContextActive(context) then
				return false
			end
			if context.routesRestoredUserIds[userId] or not context.touchedUserIds[userId] then
				context.routesRestoredUserIds[userId] = true
				return true
			end
			local clearedCalled, cleared = pcall(routes.clear, routes, userId, context.ticket.matchId)
			if
				not clearedCalled
				or not resultOk(cleared)
				or not rematchContextActive(context)
				or not restoreRoute(context.oldRoutes[userId])
			then
				return false
			end
			if not rematchContextActive(context) then
				return false
			end
			context.routesRestoredUserIds[userId] = true
			return true
		end
		local recoverAsynchronousRematch: (any, any) -> ()
		local function scheduleRematchRecovery(context, rollback)
			if not rematchContextActive(context) then
				return
			end
			local delaySeconds = if context.recoveryPasses < REMATCH_RECOVERY_FAST_PASSES
				then REMATCH_RECOVERY_FAST_DELAY_SECONDS
				else REMATCH_RECOVERY_SLOW_DELAY_SECONDS
			context.rollback = rollback
			rematchRecovery:schedule(context.ticket.ticketId, delaySeconds, function(scheduledContext)
				recoverAsynchronousRematch(scheduledContext, scheduledContext.rollback)
			end)
		end
		recoverAsynchronousRematch = function(context, rollback)
			if not rematchContextActive(context) then
				return
			end
			context.rollback = rollback
			context.recoveryPasses += 1
			local failed = if type(rollback.failedUserIds) == "table" then rollback.failedUserIds else {}
			local present = if type(rollback.presentUserIds) == "table" then rollback.presentUserIds else {}
			local departed = if type(rollback.departedUserIds) == "table" then rollback.departedUserIds else {}
			local expected = {}
			for _, userId in context.ticket.expectedUserIds do
				expected[userId] = true
			end
			local departedSet = {}
			for _, userId in departed do
				if expected[userId] then
					departedSet[userId] = true
				end
			end
			local recoverySet = {}
			for _, userId in present do
				if expected[userId] and not departedSet[userId] then
					recoverySet[userId] = true
				end
			end
			for _, userId in failed do
				if expected[userId] and not departedSet[userId] then
					recoverySet[userId] = true
				end
			end
			local recoveryUserIds = {}
			for _, userId in context.ticket.expectedUserIds do
				if recoverySet[userId] then
					table.insert(recoveryUserIds, userId)
				end
			end
			if context.requiresTransferRollback and not context.transferRolledBack then
				local called, rolledBack = pcall(profileTransfer.rollback, profileTransfer, context.transferHandle)
				if not rematchContextActive(context) then
					return
				end
				local recoveredByStep = true
				for _, userId in recoveryUserIds do
					if profile:getState(userId) ~= "Ready" then
						recoveredByStep = false
					end
				end
				if (called and resultOk(rolledBack)) or recoveredByStep then
					context.transferRolledBack = true
					for _, userId in recoveryUserIds do
						context.reacquiredUserIds[userId] = true
					end
				end
			end
			for _, userId in recoveryUserIds do
				if not rematchContextActive(context) then
					return
				end
				if not context.reacquiredUserIds[userId] and not context.requiresTransferRollback then
					local called, resultValue = pcall(profileTransfer.recoverCommitted, profileTransfer, userId)
					if not rematchContextActive(context) then
						return
					end
					if called and resultOk(resultValue) then
						context.reacquiredUserIds[userId] = true
					end
				end
				if context.reacquiredUserIds[userId] and not context.pendingReleasedUserIds[userId] then
					local called, released =
						pcall(pendingResults.release, pendingResults, { userId }, context.ticket.resultId, os.time())
					if not rematchContextActive(context) then
						return
					end
					if called and resultOk(released) then
						context.pendingReleasedUserIds[userId] = true
					end
				end
				if context.pendingReleasedUserIds[userId] then
					restoreFailedRoute(context, userId)
				end
			end
			local allFailedRecovered = true
			for _, userId in recoveryUserIds do
				allFailedRecovered = context.reacquiredUserIds[userId] == true
					and context.pendingReleasedUserIds[userId] == true
					and context.routesRestoredUserIds[userId] == true
					and allFailedRecovered
			end
			local noDeparture = #departed == 0
			if noDeparture then
				allFailedRecovered = closeRematchResultIntent(context, context.failureReason, true)
					and terminalizeRematchTicket(context, context.failureReason)
					and allFailedRecovered
			end
			if not rematchContextActive(context) then
				return
			end
			if not allFailedRecovered then
				scheduleRematchRecovery(context, rollback)
				return
			end
			context.settled = true
			pcall(safeTeleport.finish, safeTeleport, context.ticket.ticketId)
			rematchRecovery:remove(context.ticket.ticketId)
		end
		local function runRematchRecovery(context, rollback): boolean
			if not rematchContextActive(context) then
				return false
			end
			context.rollback = rollback
			return rematchRecovery:run(context.ticket.ticketId, function(ownedContext)
				recoverAsynchronousRematch(ownedContext, ownedContext.rollback)
			end)
		end
		local function scheduleImmediateRematchRecovery(context, rollback): boolean
			if not rematchContextActive(context) then
				return false
			end
			context.rollback = rollback
			return rematchRecovery:schedule(context.ticket.ticketId, 0, function(ownedContext)
				recoverAsynchronousRematch(ownedContext, ownedContext.rollback)
			end)
		end
		safeTeleport = requireResult(
			SafeTeleportService.new(ticketStore, teleport, {
				now = os.time,
				getUserId = function(player)
					return if typeof(player) == "Instance" and player:IsA("Player") then player.UserId else nil
				end,
				isPresent = function(player)
					return typeof(player) == "Instance" and player:IsA("Player") and livePlayer(player)
				end,
				onReserved = function(reserved)
					local context = rematchRecovery:get(reserved.ticketId)
					if
						context == nil
						or reserved.placeId ~= matchPlaceId
						or #reserved.orderedUserIds ~= #context.ticket.expectedUserIds
					then
						return false
					end
					local createdUserIds = {}
					for index, userId in context.ticket.expectedUserIds do
						if reserved.orderedUserIds[index] ~= userId then
							clearRematchRoutes(context, createdUserIds)
							return false
						end
						local routeId = freshId("route")
						local created = if routeId == nil
							then nil
							else routes:create({
								version = 1,
								revision = 1,
								routeId = routeId,
								userId = userId,
								ticketId = context.ticket.ticketId,
								matchId = context.ticket.matchId,
								destinationPlaceId = matchPlaceId,
								destinationJobId = nil,
								reservedServerAccessCode = reserved.accessCode,
								createdAt = os.time(),
								expiresAt = os.time() + 2_700,
							}, os.time())
						if not resultOk(created) then
							clearRematchRoutes(context, createdUserIds)
							return false
						end
						table.insert(createdUserIds, userId)
					end
					return true
				end,
				onRollback = function(rollback)
					local context = rematchRecovery:get(rollback.ticketId)
					if context ~= nil then
						context.rollback = rollback
						if context.initialized then
							scheduleImmediateRematchRecovery(context, rollback)
						end
					end
				end,
				onComplete = function(completion)
					local context = rematchRecovery:get(completion.ticketId)
					if context ~= nil then
						context.settled = true
						rematchRecovery:remove(completion.ticketId)
					end
				end,
			}),
			"SAFE_TELEPORT_UNAVAILABLE"
		)

		local function createRematch(activeUserIds, previousTicket)
			if rematchDependenciesCleaned then
				return nil
			end
			local currentTime = os.time()
			local ticketId = freshId("ticket")
			local matchId = freshId("match")
			local resultId = freshId("result")
			if ticketId == nil or matchId == nil or resultId == nil then
				return nil
			end
			local intentContext = {
				ticket = {
					ticketId = ticketId,
					matchId = matchId,
					resultId = resultId,
				},
				resultIntentClosed = false,
			}
			local intentCalled, intent = pcall(resultLedger.createIntent, resultLedger, {
				version = 1,
				resultId = resultId,
				matchId = matchId,
				ticketId = ticketId,
				expectedUserIds = activeUserIds,
				createdAt = currentTime,
			})
			if not intentCalled or not resultOk(intent) then
				-- A protected store update may have committed before its response was
				-- lost. Always attempt to close that exact intent before returning.
				closeRematchResultIntent(intentContext, "REMATCH_INTENT_CREATE_FAILED")
				return nil
			end
			local pending = pendingResults:reserve(activeUserIds, resultId, currentTime)
			if not pending.ok then
				closeRematchResultIntent(intentContext, "REMATCH_PENDING_RESERVE_FAILED")
				return nil
			end
			local prepared = profileTransfer:prepare(activeUserIds)
			if not prepared.ok then
				pendingResults:release(activeUserIds, resultId, currentTime)
				closeRematchResultIntent(intentContext, "REMATCH_PROFILE_PREPARE_FAILED")
				return nil
			end
			local members = {}
			for index, userId in activeUserIds do
				table.insert(members, {
					userId = userId,
					loadout = prepared.value.loadouts[index],
					admissionState = "Expected",
					admittedAt = nil,
				})
			end
			local candidate = MatchTicketContract.validate({
				version = MatchTicketContract.VERSION,
				revision = 1,
				ticketId = ticketId,
				matchId = matchId,
				resultId = resultId,
				expectedUserIds = activeUserIds,
				captainUserId = if table.find(activeUserIds, previousTicket.captainUserId)
					then previousTicket.captainUserId
					else activeUserIds[1],
				mapId = previousTicket.mapId,
				difficultyId = previousTicket.difficultyId,
				privacy = previousTicket.privacy,
				lobbyOrigin = previousTicket.lobbyOrigin,
				members = members,
				createdAt = currentTime,
				expiresAt = currentTime + MatchTicketContract.MAX_TTL_SECONDS,
				claimedDestinationJobId = nil,
				claimedDestinationAt = nil,
				state = "Created",
				retryCount = 0,
				terminalReason = nil,
			})
			if not candidate.ok then
				profileTransfer:rollback(prepared.value.handle)
				pendingResults:release(activeUserIds, resultId, currentTime)
				closeRematchResultIntent(intentContext, "REMATCH_TICKET_INVALID")
				return nil
			end
			local context = {
				ticket = candidate.value,
				oldRoutes = {},
				touchedUserIds = {},
				initialized = false,
				settled = false,
				reacquiredUserIds = {},
				pendingReleasedUserIds = {},
				routesRestoredUserIds = {},
				recoveryPasses = 0,
				transferHandle = prepared.value.handle,
				requiresTransferRollback = true,
				transferRolledBack = false,
				transferCommitted = false,
				resultIntentClosed = false,
				ticketTerminal = false,
				failureReason = "REMATCH_TELEPORT_FAILED",
			}
			if not rematchRecovery:register(ticketId, context) then
				profileTransfer:rollback(prepared.value.handle)
				pendingResults:release(activeUserIds, resultId, currentTime)
				closeRematchResultIntent(context, "REMATCH_RECOVERY_UNAVAILABLE")
				return nil
			end
			local created = ticketStore:create(candidate.value)
			if not created.ok then
				context.failureReason = "REMATCH_TICKET_CREATE_FAILED"
				local rollback = {
					ticketId = ticketId,
					failedUserIds = table.clone(activeUserIds),
					presentUserIds = table.clone(activeUserIds),
					departedUserIds = {},
					partial = false,
				}
				runRematchRecovery(context, rollback)
				return nil
			end
			local players = {}
			for index, userId in activeUserIds do
				local taken = routes:takeForMatch(userId, previousTicket.matchId, currentTime)
				if not taken.ok then
					context.failureReason = "REMATCH_ROUTE_SWAP_FAILED"
					runRematchRecovery(context, {
						ticketId = ticketId,
						failedUserIds = table.clone(activeUserIds),
						presentUserIds = table.clone(activeUserIds),
						departedUserIds = {},
						partial = false,
					})
					return nil
				end
				context.oldRoutes[userId] = taken.value
				context.touchedUserIds[userId] = true
				local player = Players:GetPlayerByUserId(userId)
				if player == nil or not livePlayer(player) then
					context.failureReason = "REMATCH_PLAYER_MISSING"
					runRematchRecovery(context, {
						ticketId = ticketId,
						failedUserIds = table.clone(activeUserIds),
						presentUserIds = table.clone(activeUserIds),
						departedUserIds = {},
						partial = false,
					})
					return nil
				end
				players[index] = player
			end
			local committed = profileTransfer:commit(prepared.value.handle)
			if not committed.ok then
				context.failureReason = "REMATCH_TRANSFER_COMMIT_FAILED"
				runRematchRecovery(context, {
					ticketId = ticketId,
					failedUserIds = table.clone(activeUserIds),
					presentUserIds = table.clone(activeUserIds),
					departedUserIds = {},
					partial = false,
				})
				return nil
			end
			context.requiresTransferRollback = false
			context.transferCommitted = true
			local started = safeTeleport:start(ticketId, matchPlaceId, players)
			if not started.ok then
				context.failureReason = "REMATCH_TELEPORT_FAILED"
				runRematchRecovery(context, {
					ticketId = ticketId,
					failedUserIds = table.clone(activeUserIds),
					presentUserIds = table.clone(activeUserIds),
					departedUserIds = {},
					partial = false,
				})
				return nil
			end
			context.initialized = true
			if context.rollback ~= nil then
				scheduleImmediateRematchRecovery(context, context.rollback)
			end
			local revisions = {}
			for index, userId in activeUserIds do
				table.insert(revisions, { userId = userId, revision = prepared.value.loadouts[index].revision })
			end
			return {
				matchId = matchId,
				resultId = resultId,
				ticketId = ticketId,
				loadouts = revisions,
			}
		end

		local unexpectedReturns = requireResult(
			UnexpectedReturnService.new({
				ownershipTransfer = unexpectedOwnershipTransfer,
				teleport = teleport,
				lobbyPlaceId = lobbyPlaceId,
				getUserId = function(player)
					return if typeof(player) == "Instance" and player:IsA("Player") then player.UserId else nil
				end,
				isLive = function(player)
					return typeof(player) == "Instance" and player:IsA("Player") and livePlayer(player)
				end,
				getProfileState = function(userId)
					return profile:getState(userId)
				end,
				rejectPlayer = function(player, publicReason)
					if typeof(player) == "Instance" and player:IsA("Player") and type(publicReason) == "string" then
						player:Kick(publicReason)
					end
				end,
				makeReturnId = function()
					return freshId("return")
				end,
				schedule = task.spawn,
				connectPlayerRemoving = function(callback)
					return Players.PlayerRemoving:Connect(callback)
				end,
				wait = task.wait,
				monotonic = os.clock,
			}),
			"UNEXPECTED_RETURN_UNAVAILABLE"
		)

		local hostResult = MatchTravelHost.new({
			configuration = configuration.coreConfiguration,
			profile = profile,
			ticketStore = ticketStore,
			admission = admission,
			routes = routes,
			returnRecords = returnRecords,
			profileTransfer = profileTransfer,
			teleport = teleport,
			resultLedger = resultLedger,
			rewardClaims = rewardClaims,
			snapshotSender = sendTravelSnapshot,
			playableFactory = function(ticket, connectedUserIds)
				local service = PlayableMatchService.new(
					configuration.log,
					matchLifecycle,
					configuration.coreConfiguration,
					sendPlayableSnapshot,
					sendAttack,
					loadoutFor,
					{
						expectedUserIds = ticket.expectedUserIds,
						frozenLoadouts = (function()
							local frozen = {}
							for _, member in ticket.members do
								table.insert(frozen, member.loadout)
							end
							return frozen
						end)(),
						rewarding = true,
						matchId = ticket.matchId,
						mapId = ticket.mapId,
						difficultyId = ticket.difficultyId,
						managedAdmissions = true,
						connectedParticipantUserIds = connectedUserIds,
					}
				)
				local definition = service:getServiceDefinition()
				local initialized = pcall(definition.initialize)
				local started = initialized and pcall(definition.start)
				if not started then
					pcall(definition.shutdown)
				end
				return if started then Result.ok(service) else Result.err("PLAYABLE_START_FAILED")
			end,
			stopPlayable = function(service)
				pcall(service:getServiceDefinition().shutdown)
			end,
			createRematch = createRematch,
			stepDependencies = function()
				profileTransfer:step()
				unexpectedOwnershipTransfer:step()
				unexpectedReturns:step()
			end,
			prepareCleanupDependencies = function()
				if dependencyCleanupPrepared then
					return true
				end
				rematchDependenciesCleaned = true
				local rematchMetrics = rematchRecovery:getMetrics()
				local rematchPrepared = rematchMetrics.cleaned
					or rematchRecovery:cleanup(function(context)
						if type(context) == "table" then
							(context :: any).settled = true
						end
					end)
				local unexpectedCalled, unexpectedPrepared = pcall(unexpectedReturns.cleanup, unexpectedReturns)
				if rematchPrepared and unexpectedCalled and resultOk(unexpectedPrepared) then
					dependencyCleanupPrepared = true
				end
				return dependencyCleanupPrepared
			end,
			cleanupDependencies = function()
				if not dependencyCleanupPrepared then
					return false
				end
				local profileCalled, profileCleaned = pcall(profileTransfer.cleanup, profileTransfer)
				if not profileCalled or not resultOk(profileCleaned) then
					return false
				end
				local unexpectedCalled, unexpectedCleaned =
					pcall(unexpectedOwnershipTransfer.cleanup, unexpectedOwnershipTransfer)
				if not unexpectedCalled or not resultOk(unexpectedCleaned) then
					return false
				end
				pcall(safeTeleport.cleanup, safeTeleport)
				pcall(pendingResults.cleanup, pendingResults)
				return true
			end,
			environment = {
				now = os.time,
				getUserId = function(player)
					return if typeof(player) == "Instance" and player:IsA("Player") then player.UserId else nil
				end,
				isLive = function(player)
					return typeof(player) == "Instance" and player:IsA("Player") and livePlayer(player)
				end,
				getPlayers = function()
					return Players:GetPlayers()
				end,
				getRoutingData = function(player)
					if typeof(player) ~= "Instance" or not player:IsA("Player") then
						return nil
					end
					local called, joinData = pcall(player.GetJoinData, player)
					return if called and type(joinData) == "table" then joinData.TeleportData else nil
				end,
				connectPlayerAdded = function(callback)
					return Players.PlayerAdded:Connect(callback)
				end,
				connectPlayerRemoving = function(callback)
					return Players.PlayerRemoving:Connect(callback)
				end,
				connectHeartbeat = function(callback)
					return RunService.Heartbeat:Connect(callback)
				end,
				scheduleReturn = task.defer,
				scheduleRematch = task.defer,
				destinationJobId = game.JobId,
				lobbyPlaceId = lobbyPlaceId,
				generateReturnId = function()
					return freshId("return")
				end,
				safeReturnUnexpected = function(player)
					if typeof(player) == "Instance" and player:IsA("Player") then
						unexpectedReturns:returnPlayer(player)
					end
				end,
			},
		})
		travelHost = requireResult(hostResult, "MATCH_TRAVEL_HOST_UNAVAILABLE")
	end

	local function playableFor(player: Player): PlayableMatchService.Service?
		return if travelHost ~= nil then travelHost:getPlayable(player) else playable
	end

	-- Preserve the Phase 8 ready/snapshot compatibility boundary. Superseded
	-- combat, wave, base, and placement requests fail closed without starting a
	-- second authoritative simulation graph.
	network:registerRequest(
		MatchProtocol.GET_MATCH_SNAPSHOT_ENDPOINT,
		MatchProtocol.GetMatchSnapshotPayloadSchema,
		MatchProtocol.MatchSnapshotSchema,
		authorizeLiveContext,
		function(_context, _payload)
			if travelHost ~= nil then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			local result = matchLifecycle:getSnapshot()
			return if result.ok
				then ServerRequestDispatcher.success(result.value)
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		MatchProtocol.SUBMIT_READY_ENDPOINT,
		MatchProtocol.SubmitReadyPayloadSchema,
		MatchProtocol.MatchSnapshotSchema,
		authorizeLiveContext,
		function(context, payload)
			if travelHost ~= nil then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			local intent = payload :: MatchProtocol.SubmitReadyPayload
			local result = matchLifecycle:submitReady(context.player, intent.matchId, intent.observedRevision)
			return if result.ok
				then ServerRequestDispatcher.success(result.value)
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		BaseProtocol.GET_BASE_SNAPSHOT_ENDPOINT,
		BaseProtocol.GetBaseSnapshotPayloadSchema,
		BaseProtocol.BaseSnapshotSchema,
		authorizeLiveContext,
		unavailable
	)
	network:registerRequest(
		EnemyProtocol.GET_ENEMY_SNAPSHOT_ENDPOINT,
		EnemyProtocol.GetEnemySnapshotPayloadSchema,
		EnemyProtocol.EnemySnapshotReceiptSchema,
		authorizeLiveContext,
		unavailable
	)
	network:registerRequest(
		WaveProtocol.GET_WAVE_SNAPSHOT_ENDPOINT,
		WaveProtocol.GetWaveSnapshotPayloadSchema,
		WaveProtocol.WaveSnapshotSchema,
		authorizeLiveContext,
		unavailable
	)
	network:registerRequest(
		WaveProtocol.SUBMIT_SKIP_VOTE_ENDPOINT,
		WaveProtocol.SubmitSkipVotePayloadSchema,
		WaveProtocol.WaveSnapshotSchema,
		authorizeLiveContext,
		unavailable
	)
	network:registerRequest(
		PlacementProtocol.GET_QUERY_ENDPOINT,
		PlacementProtocol.GetQueryPayloadSchema,
		PlacementProtocol.QuerySnapshotSchema,
		authorizeLiveContext,
		unavailable
	)
	network:registerRequest(
		PlacementProtocol.SUBMIT_PLACEMENT_ENDPOINT,
		PlacementProtocol.SubmitPlacementPayloadSchema,
		PlacementProtocol.PlacementReceiptSchema,
		authorizeLiveContext,
		unavailable
	)

	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT,
		PlayableMatchProtocol.GetSnapshotPayloadSchema,
		PlayableMatchProtocol.SnapshotSchema,
		authorizeLiveContext,
		function(context, _payload)
			local selected = playableFor(context.player)
			if selected == nil then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			local result = selected:getSnapshot(context.player)
			return if result.ok
				then ServerRequestDispatcher.success(result.value)
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.SUBMIT_READY,
		PlayableMatchProtocol.ReadyPayloadSchema,
		PlayableMatchProtocol.ActionReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local selected = playableFor(context.player)
			if selected == nil or (travelHost ~= nil and not travelHost:canSubmitReady(context.player)) then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			return actionOutcome(selected:submitReady(context.player, payload :: PlayableMatchProtocol.ReadyPayload))
		end
	)
	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.SUBMIT_PLACEMENT,
		PlayableMatchProtocol.PlacementPayloadSchema,
		PlayableMatchProtocol.ActionReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local selected = playableFor(context.player)
			if selected == nil then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			return actionOutcome(
				selected:submitPlacement(context.player, payload :: PlayableMatchProtocol.PlacementPayload)
			)
		end
	)
	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.SUBMIT_UPGRADE,
		PlayableMatchProtocol.TowerPayloadSchema,
		PlayableMatchProtocol.ActionReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local selected = playableFor(context.player)
			return if selected == nil
				then ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
				else actionOutcome(
					selected:submitUpgrade(context.player, payload :: PlayableMatchProtocol.TowerPayload)
				)
		end
	)
	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.SUBMIT_SELL,
		PlayableMatchProtocol.TowerPayloadSchema,
		PlayableMatchProtocol.ActionReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local selected = playableFor(context.player)
			return if selected == nil
				then ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
				else actionOutcome(
					selected:submitSell(context.player, payload :: PlayableMatchProtocol.TowerPayload)
				)
		end
	)
	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.SUBMIT_TARGET_MODE,
		PlayableMatchProtocol.TargetModePayloadSchema,
		PlayableMatchProtocol.ActionReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local selected = playableFor(context.player)
			if selected == nil then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			return actionOutcome(
				selected:submitTargetMode(context.player, payload :: PlayableMatchProtocol.TargetModePayload)
			)
		end
	)
	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.SUBMIT_REPLAY,
		PlayableMatchProtocol.ReplayPayloadSchema,
		PlayableMatchProtocol.ActionReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local selected = playableFor(context.player)
			return if selected == nil
				then ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
				else actionOutcome(
					selected:submitReplay(context.player, payload :: PlayableMatchProtocol.ReplayPayload)
				)
		end
	)

	network:registerRequest(
		MatchTravelProtocol.ENDPOINTS.GET_SNAPSHOT,
		MatchTravelProtocol.EmptyPayloadSchema,
		MatchTravelProtocol.SnapshotSchema,
		authorizeLiveContext,
		function(context, _payload)
			local result = if travelHost == nil then nil else travelHost:getSnapshot(context.player)
			return if result ~= nil and result.ok
				then ServerRequestDispatcher.success(result.value)
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		MatchTravelProtocol.ENDPOINTS.REQUEST_RETURN,
		MatchTravelProtocol.ReturnIntentSchema,
		MatchTravelProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local result = if travelHost == nil
				then nil
				else travelHost:requestReturn(context.player, payload :: MatchTravelProtocol.ReturnIntent)
			return if result ~= nil and result.ok
				then ServerRequestDispatcher.success(result.value)
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		MatchTravelProtocol.ENDPOINTS.VOTE_REMATCH,
		MatchTravelProtocol.RematchVoteIntentSchema,
		MatchTravelProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local result = if travelHost == nil
				then nil
				else travelHost:voteRematch(context.player, payload :: MatchTravelProtocol.RematchVoteIntent)
			return if result ~= nil and result.ok
				then ServerRequestDispatcher.success(result.value)
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)

	configuration.lifecycleRunner:register(profile:getServiceDefinition())
	configuration.lifecycleRunner:register(matchLifecycle:getServiceDefinition())
	if travelHost ~= nil then
		configuration.lifecycleRunner:register(travelHost:getServiceDefinition())
	elseif playable ~= nil then
		configuration.lifecycleRunner:register(playable:getServiceDefinition())
	end
end)
