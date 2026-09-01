--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AcquisitionProtocol = require(ReplicatedStorage.Shared.acquisition.AcquisitionProtocol)
local InventoryProtocol = require(ReplicatedStorage.Shared.inventory.InventoryProtocol)
local LobbyQueues = require(ReplicatedStorage.Shared.config.LobbyQueues)
local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local LobbyProtocol = require(ReplicatedStorage.Shared.lobby.LobbyProtocol)
local MatchLoadoutProtocol = require(ReplicatedStorage.Shared.match.MatchLoadoutProtocol)
local PartyProtocol = require(ReplicatedStorage.Shared.party.PartyProtocol)
local ProfileProtocol = require(ReplicatedStorage.Shared.profile.ProfileProtocol)
local QueueProtocol = require(ReplicatedStorage.Shared.queue.QueueProtocol)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local SettingsProtocol = require(ReplicatedStorage.Shared.settings.SettingsProtocol)

local ServerBootstrap = require(script.Parent.ServerBootstrap)
local ServerRequestDispatcher = require(script.Parent.Parent.networking.ServerRequestDispatcher)
local ProfileService = require(script.Parent.Parent.profile.ProfileService)
local ProfileSchema = require(script.Parent.Parent.profile.ProfileSchema)
local ProfileStoreAdapter = require(script.Parent.Parent.profile.ProfileStoreAdapter)
local PendingResultService = require(script.Parent.Parent.profile.PendingResultService)
local ActiveMatchRouteService = require(script.Parent.Parent.travel.ActiveMatchRouteService)
local MemoryStoreTravelAdapter = require(script.Parent.Parent.travel.MemoryStoreTravelAdapter)
local ProfileTransferCoordinator = require(script.Parent.Parent.travel.ProfileTransferCoordinator)
local ReturnRecordService = require(script.Parent.Parent.travel.ReturnRecordService)
local SafeTeleportService = require(script.Parent.Parent.travel.SafeTeleportService)
local TeleportAdapter = require(script.Parent.Parent.travel.TeleportAdapter)
local TravelRecordStore = require(script.Parent.Parent.travel.TravelRecordStore)
local ProfileRewardClaimService = require(script.Parent.Parent.rewards.ProfileRewardClaimService)
local ResultLedgerService = require(script.Parent.Parent.rewards.ResultLedgerService)
local ResultLedgerStoreAdapter = require(script.Parent.Parent.rewards.ResultLedgerStoreAdapter)
local AcquisitionService = require(script.Parent.Parent.Parent.lobby.acquisition.AcquisitionService)
local InventoryService = require(script.Parent.Parent.Parent.lobby.inventory.InventoryService)
local InvitePermissionCache = require(script.Parent.Parent.Parent.lobby.party.InvitePermissionCache)
local PartyService = require(script.Parent.Parent.Parent.lobby.party.PartyService)
local PlatformInviteAdapter = require(script.Parent.Parent.Parent.lobby.party.PlatformInviteAdapter)
local LobbyQueueService = require(script.Parent.Parent.Parent.lobby.queue.LobbyQueueService)
local QueueWorldDisplayService = require(script.Parent.Parent.Parent.lobby.queue.QueueWorldDisplayService)
local QueueZoneService = require(script.Parent.Parent.Parent.lobby.queue.QueueZoneService)
local SettingsService = require(script.Parent.Parent.Parent.lobby.settings.SettingsService)
local LobbyReconnectService = require(script.Parent.Parent.Parent.lobby.travel.LobbyReconnectService)
local LobbyReturnCoordinator = require(script.Parent.Parent.Parent.lobby.travel.LobbyReturnCoordinator)
local LobbyTravelCoordinator = require(script.Parent.Parent.Parent.lobby.travel.LobbyTravelCoordinator)
local PendingClaimCoordinator = require(script.Parent.Parent.Parent.lobby.travel.PendingClaimCoordinator)

type BannerRequest = { bannerId: string }

local function publicError(code: RequestProtocol.PublicErrorCode): RequestProtocol.PublicError
	local result = RequestProtocol.createPublicError(code, nil)
	if not result.ok then
		error("[ATD_LOBBY_BOOTSTRAP][code=PUBLIC_ERROR_CONSTRUCTION_FAILED]", 0)
	end
	return result.value
end

local PUBLIC_ERRORS = table.freeze({
	STALE_REQUEST = publicError("STALE_REQUEST"),
	UNAVAILABLE = publicError("UNAVAILABLE"),
})

local function authorizeLiveContext(context: ServerRequestDispatcher.ServerContext): boolean
	if not ServerRequestDispatcher.isContext(context) then
		return false
	end
	local player = context.player
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local function required<T>(resultValue: any, code: string): T
	if type(resultValue) ~= "table" or resultValue.ok ~= true then
		error(`[ATD_LOBBY_BOOTSTRAP][code={code}]`, 0)
	end
	return resultValue.value :: T
end

local function opaqueId(kind: string): string
	return `{kind}:{string.lower(HttpService:GenerateGUID(false))}`
end

local function snapshotLoadout(userId: number, profileValue: unknown, configuration: any): unknown
	if type(profileValue) ~= "table" then
		return nil
	end
	local profile = profileValue :: any
	if type(profile.equippedUnitIds) ~= "table" or type(profile.units) ~= "table" then
		return nil
	end
	local slots = table.create(#profile.equippedUnitIds)
	for slot, unitId in profile.equippedUnitIds do
		local unit = profile.units[unitId]
		if type(unit) ~= "table" then
			return nil
		end
		slots[slot] = { slot = slot, unitId = unitId, towerId = unit.towerId }
	end
	local validated = MatchLoadoutProtocol.validate({
		userId = userId,
		revision = profile.revision,
		slots = slots,
		settings = profile.settings,
	}, configuration)
	return if validated.ok then validated.value else nil
end

local function queueDefinitions(): { any }
	local definitions = table.create(#LobbyQueues.ordered)
	for index, definition in LobbyQueues.ordered do
		definitions[index] = {
			queueId = definition.queueId,
			configuration = definition.configuration,
		}
	end
	return definitions
end

ServerBootstrap.run(PlaceRoles.LOBBY_ROLE, function(configuration)
	local network = configuration.serverRemoteRegistry
	if network == nil then
		error("[ATD_LOBBY_BOOTSTRAP][code=NETWORK_REGISTRY_MISSING]", 0)
	end

	local storeResult = if RunService:IsStudio()
		then ProfileStoreAdapter.newStudioDevelopment()
		else ProfileStoreAdapter.newProduction()
	if not storeResult.ok then
		error("[ATD_LOBBY_BOOTSTRAP][code=PROFILE_STORE_UNAVAILABLE]", 0)
	end
	local profileResult = ProfileService.new(configuration.coreConfiguration.towers, storeResult.value, nil)
	if not profileResult.ok then
		error("[ATD_LOBBY_BOOTSTRAP][code=PROFILE_SERVICE_CREATION_FAILED]", 0)
	end
	local profile = profileResult.value
	local inventoryResult = InventoryService.new(profile, configuration.coreConfiguration)
	local acquisitionResult = AcquisitionService.new(profile, configuration.coreConfiguration, nil, nil, nil)
	local settingsResult = SettingsService.new(profile)
	if not inventoryResult.ok or not acquisitionResult.ok or not settingsResult.ok then
		error("[ATD_LOBBY_BOOTSTRAP][code=LOBBY_SERVICE_CREATION_FAILED]", 0)
	end
	local inventory = inventoryResult.value
	local acquisition = acquisitionResult.value
	local settings = settingsResult.value

	local sendProfile =
		network:registerServerEvent(LobbyProtocol.ENDPOINTS.PROFILE_REPLICATION, ProfileProtocol.SnapshotSchema)
	local sendInventory =
		network:registerServerEvent(LobbyProtocol.ENDPOINTS.INVENTORY_REPLICATION, InventoryProtocol.SnapshotSchema)
	local sendParty =
		network:registerServerEvent(LobbyProtocol.ENDPOINTS.PARTY_REPLICATION, PartyProtocol.ViewerSnapshotSchema)
	local sendQueues =
		network:registerServerEvent(LobbyProtocol.ENDPOINTS.QUEUE_REPLICATION, LobbyProtocol.QueueListSchema)
	local sendActiveRoute = network:registerServerEvent(
		LobbyProtocol.ENDPOINTS.ACTIVE_ROUTE_REPLICATION,
		LobbyProtocol.ActiveRouteViewSchema
	)

	local publishViews: (Player) -> () = function(_player: Player) end
	local publishPartyViews: () -> () = function() end
	local publishQueueViews: () -> () = function() end
	local runtimeCleaned = false
	local routeBlockedByUserId: { [number]: boolean } = {}
	local activeRouteViewByUserId: { [number]: LobbyProtocol.ActiveRouteView } = {}

	local memoryAdapter = required(
		if RunService:IsStudio()
			then MemoryStoreTravelAdapter.newStudioDevelopment(os.time)
			else MemoryStoreTravelAdapter.newProduction(),
		"TRAVEL_ADAPTER_UNAVAILABLE"
	)
	local ticketStore = required(TravelRecordStore.new(memoryAdapter, { clock = os.time }), "TICKET_STORE_UNAVAILABLE")
	local activeRoutes = required(ActiveMatchRouteService.new(memoryAdapter), "ROUTE_STORE_UNAVAILABLE")
	local returnRecords = required(ReturnRecordService.new(memoryAdapter), "RETURN_STORE_UNAVAILABLE")
	local pendingResults = required(PendingResultService.new(profile), "PENDING_RESULT_SERVICE_UNAVAILABLE")
	local ledgerAdapter = required(
		if RunService:IsStudio()
			then ResultLedgerStoreAdapter.newStudioDevelopment()
			else ResultLedgerStoreAdapter.newProduction(),
		"RESULT_LEDGER_ADAPTER_UNAVAILABLE"
	)
	local resultLedger = required(ResultLedgerService.new(ledgerAdapter, os.time), "RESULT_LEDGER_UNAVAILABLE")
	local profileTransfer = required(
		ProfileTransferCoordinator.new(profile, {
			isPresent = function(userId: number): boolean
				return Players:GetPlayerByUserId(userId) ~= nil
			end,
			snapshotLoadout = function(userId: number, profileValue: unknown): unknown
				return snapshotLoadout(userId, profileValue, configuration.coreConfiguration)
			end,
		}),
		"PROFILE_TRANSFER_UNAVAILABLE"
	)
	local teleportAdapter = required(
		if RunService:IsStudio() then TeleportAdapter.newStudioDevelopment() else TeleportAdapter.newProduction(),
		"TELEPORT_ADAPTER_UNAVAILABLE"
	)

	local permissionCache = required(
		InvitePermissionCache.new({
			clock = os.time,
			schedule = task.spawn,
			lookup = function(inviterUserId: number, targetUserId: number): unknown
				local inviter = Players:GetPlayerByUserId(inviterUserId)
				local target = Players:GetPlayerByUserId(targetUserId)
				if inviter == nil or target == nil then
					return nil
				end
				return inviter:IsFriendsWith(targetUserId)
			end,
		}),
		"INVITE_PERMISSION_CACHE_UNAVAILABLE"
	)
	local platformInvite = required(PlatformInviteAdapter.newProduction(), "PLATFORM_INVITE_UNAVAILABLE")

	local queue: any = nil
	local travel: any = nil
	local party = required(
		PartyService.new({
			clock = os.time,
			makePartyId = function(): string
				return opaqueId("party")
			end,
			makeInvitationId = function(): string
				return opaqueId("invitation")
			end,
			isPresent = function(userId: number): boolean
				return Players:GetPlayerByUserId(userId) ~= nil
			end,
			canInvite = function(inviterUserId: number, targetUserId: number): boolean?
				return permissionCache:get(inviterUserId, targetUserId)
			end,
			isProfileReady = function(userId: number): boolean
				return profile:getState(userId) == "Ready"
			end,
			getQueueState = function(memberUserIds: { number }): string
				if queue == nil then
					return "Idle"
				end
				local queueId: string? = nil
				for _, userId in memberUserIds do
					local memberQueueId = queue:getQueueForUser(userId)
					if memberQueueId == nil or (queueId ~= nil and memberQueueId ~= queueId) then
						return "Idle"
					end
					queueId = memberQueueId
				end
				local snapshotResult = if queueId == nil then nil else queue:getSnapshot(queueId)
				if snapshotResult == nil or not snapshotResult.ok then
					return "Idle"
				end
				local state = snapshotResult.value.state
				return if state == "Starting" then "Starting" elseif state == "Traveling" then "Traveling" else "Queued"
			end,
			onChanged = function(change: PartyService.Change)
				if queue ~= nil and change.membershipChanged then
					queue:invalidateParty(change.partyId, change.userIds)
				end
				task.defer(function()
					if not runtimeCleaned then
						publishPartyViews()
						publishQueueViews()
					end
				end)
			end,
		}),
		"PARTY_SERVICE_UNAVAILABLE"
	)

	queue = required(
		LobbyQueueService.new(configuration.coreConfiguration, queueDefinitions(), {
			isPresent = function(userId: number): boolean
				return Players:GetPlayerByUserId(userId) ~= nil
			end,
			getParty = function(userId: number): unknown
				return party:getPartyForUser(userId)
			end,
			getEligibility = function(userId: number): unknown
				local ready = profile:getState(userId) == "Ready"
				local read = if ready then profile:read(userId) else nil
				local loadout = if read ~= nil and read.ok
					then snapshotLoadout(userId, read.value, configuration.coreConfiguration)
					else nil
				local pending = if ready then pendingResults:list(userId) else nil
				local pendingCapacity = pending ~= nil
					and pending.ok
					and #pending.value < ProfileSchema.MAX_PENDING_RESULT_IDS
				local ticketEligible = ready
					and pendingCapacity
					and routeBlockedByUserId[userId] == false
					and (travel == nil or not travel:isUserTravelPending(userId))
				return {
					profileReady = ready,
					sessionOwned = ready and read ~= nil and read.ok,
					loadoutReady = loadout ~= nil,
					ticketEligible = ticketEligible,
					loadout = loadout,
				}
			end,
			beginStart = function(locked): boolean
				return travel ~= nil and travel:beginStart(locked)
			end,
			onChanged = function(_queueId: string, _snapshot: QueueProtocol.Snapshot)
				task.defer(function()
					if not runtimeCleaned then
						publishQueueViews()
						publishPartyViews()
					end
				end)
			end,
		}),
		"QUEUE_SERVICE_UNAVAILABLE"
	)

	local safeTeleport: any = nil
	safeTeleport = required(
		SafeTeleportService.new(ticketStore, teleportAdapter, {
			now = os.time,
			isPresent = function(playerValue: unknown): boolean
				return typeof(playerValue) == "Instance"
					and (playerValue :: Instance):IsA("Player")
					and (playerValue :: Player).Parent == Players
			end,
			onReserved = function(reserved): unknown
				return if travel == nil then false else travel:onReserved(reserved)
			end,
			onRollback = function(rollback)
				if travel ~= nil then
					travel:onRollback(rollback)
				end
			end,
		}),
		"SAFE_TELEPORT_UNAVAILABLE"
	)
	local lobbyPlaceId = PlaceRoles.getConfiguredPlaceId(PlaceRoles.LOBBY_ROLE) :: number
	local matchPlaceId = PlaceRoles.getConfiguredPlaceId(PlaceRoles.MATCH_ROLE) :: number
	travel = required(
		LobbyTravelCoordinator.new({
			clock = os.time,
			schedule = task.spawn,
			makeId = function(kind: LobbyTravelCoordinator.IdKind): string
				return opaqueId(kind)
			end,
			ticketStore = ticketStore,
			pendingResults = pendingResults,
			resultLedger = resultLedger,
			profileTransfer = profileTransfer,
			safeTeleport = safeTeleport,
			activeRoutes = activeRoutes,
			queue = queue,
			getPlayer = function(userId: number): Player?
				return Players:GetPlayerByUserId(userId)
			end,
			isPresent = function(userId: number): boolean
				return Players:GetPlayerByUserId(userId) ~= nil
			end,
			lobbyPlaceId = lobbyPlaceId,
			matchPlaceId = matchPlaceId,
			lobbyJobId = if #game.JobId > 0 then game.JobId else "studio-lobby-job",
			developmentSimulation = RunService:IsStudio(),
		}),
		"LOBBY_TRAVEL_COORDINATOR_UNAVAILABLE"
	)

	local rewardClaims = required(
		ProfileRewardClaimService.new(profile, resultLedger, configuration.coreConfiguration, os.time),
		"REWARD_CLAIM_SERVICE_UNAVAILABLE"
	)
	local pendingClaims = required(
		PendingClaimCoordinator.new({
			pendingResults = pendingResults,
			rewardClaims = rewardClaims,
			onClaim = function(userId: number, _view: unknown)
				task.defer(function()
					local player = Players:GetPlayerByUserId(userId)
					if player ~= nil and not runtimeCleaned then
						publishViews(player)
					end
				end)
			end,
		}),
		"PENDING_CLAIM_COORDINATOR_UNAVAILABLE"
	)
	local returns = required(
		LobbyReturnCoordinator.new({
			clock = os.time,
			returnRecords = returnRecords,
			party = party,
			isPresent = function(userId: number): boolean
				return Players:GetPlayerByUserId(userId) ~= nil
			end,
			isProfileReady = function(userId: number): boolean
				return profile:getState(userId) == "Ready"
			end,
			lobbyClaimId = if #game.JobId > 0 then game.JobId else "studio-lobby-job",
		}),
		"LOBBY_RETURN_COORDINATOR_UNAVAILABLE"
	)
	local reconnect = required(
		LobbyReconnectService.new({
			clock = os.time,
			activeRoutes = activeRoutes,
			teleportAdapter = teleportAdapter,
			profileTransfer = profileTransfer,
			getPlayer = function(userId: number): Player?
				return Players:GetPlayerByUserId(userId)
			end,
			isPresent = function(userId: number): boolean
				return Players:GetPlayerByUserId(userId) ~= nil
			end,
			makeAttemptId = function(): string
				return opaqueId("attempt")
			end,
			developmentSimulation = RunService:IsStudio(),
		}),
		"LOBBY_RECONNECT_UNAVAILABLE"
	)

	local worldDisplay: any = nil
	local displayAnchors: { any } = {}
	for _, definition in LobbyQueues.ordered do
		local candidate = Workspace:FindFirstChild(definition.worldDisplayName, true)
		if candidate ~= nil and (candidate:IsA("BasePart") or candidate:IsA("Attachment")) then
			table.insert(displayAnchors, { queueId = definition.queueId, adornee = candidate })
		end
	end
	if #displayAnchors > 0 then
		local displayResult = QueueWorldDisplayService.new(displayAnchors)
		if displayResult.ok then
			worldDisplay = displayResult.value
		end
	end

	local zoneDefinitions: { any } = {}
	for _, definition in LobbyQueues.ordered do
		local zonePart = Workspace:FindFirstChild(definition.worldPartName, true)
		if zonePart ~= nil and zonePart:IsA("BasePart") then
			local sampler = QueueZoneService.createWorkspaceSampler(definition.queueId, zonePart, Workspace, Players)
			if sampler.ok then
				table.insert(zoneDefinitions, sampler.value)
			end
		end
	end
	local zoneService: any = nil
	if #zoneDefinitions > 0 then
		local zoneResult = QueueZoneService.new(queue, zoneDefinitions, {
			clock = os.clock,
			connectStep = function(callback: () -> ()): RBXScriptConnection
				return RunService.Heartbeat:Connect(callback)
			end,
		})
		if zoneResult.ok then
			zoneService = zoneResult.value
		end
	end

	publishViews = function(player: Player)
		local profileView = profile:getClientSnapshot(player.UserId)
		if profileView.ok then
			sendProfile(player, profileView.value)
		end
		local inventoryView = inventory:getSnapshot(player.UserId)
		if inventoryView.ok then
			sendInventory(player, inventoryView.value)
		end
		local partyView = party:getSnapshot(player.UserId)
		if partyView.ok then
			sendParty(player, partyView.value)
		end
		local routeView = activeRouteViewByUserId[player.UserId]
		if routeView ~= nil then
			sendActiveRoute(player, routeView)
		end
	end

	publishPartyViews = function()
		for _, player in Players:GetPlayers() do
			local result = party:getSnapshot(player.UserId)
			if result.ok then
				sendParty(player, result.value)
			end
		end
	end

	local function queueList(): LobbyProtocol.QueueList
		local validated = LobbyProtocol.validateQueueList({
			version = LobbyProtocol.VERSION,
			queues = queue:listSnapshots(),
		})
		if not validated.ok then
			error("[ATD_LOBBY_BOOTSTRAP][code=INVALID_QUEUE_LIST]", 0)
		end
		return validated.value
	end

	publishQueueViews = function()
		local value = queueList()
		for _, player in Players:GetPlayers() do
			sendQueues(player, value)
		end
		if worldDisplay ~= nil then
			for _, snapshot in value.queues do
				worldDisplay:update(snapshot.queueId, snapshot)
			end
		end
	end

	local function refreshRoute(player: Player)
		local result = reconnect:getView(player.UserId)
		if not result.ok or player.Parent ~= Players or runtimeCleaned then
			return
		end
		activeRouteViewByUserId[player.UserId] = result.value
		routeBlockedByUserId[player.UserId] = result.value.status == "Available"
		sendActiveRoute(player, result.value)
	end

	local processingReadyByUserId: { [number]: boolean } = {}
	local function processPlayerReady(player: Player)
		local userId = player.UserId
		if processingReadyByUserId[userId] or runtimeCleaned then
			return
		end
		processingReadyByUserId[userId] = true
		local succeeded = pcall(function()
			for _attempt = 1, 300 do
				if runtimeCleaned or player.Parent ~= Players then
					return
				end
				if profile:getState(userId) == "Ready" then
					break
				end
				task.wait(0.1)
			end
			if runtimeCleaned or player.Parent ~= Players or profile:getState(userId) ~= "Ready" then
				return
			end

			local joined, joinData = pcall(player.GetJoinData, player)
			if joined and type(joinData) == "table" then
				local launchHint = PlatformInviteAdapter.parseLaunchData((joinData :: any).LaunchData)
				if
					launchHint.ok
					and launchHint.value.inviterUserId ~= userId
					and Players:GetPlayerByUserId(launchHint.value.inviterUserId) ~= nil
				then
					permissionCache:request(launchHint.value.inviterUserId, userId)
				end
				local admitted = returns:admitJoinData(userId, (joinData :: any).TeleportData)
				if admitted.ok then
					if admitted.value.arrivedCount >= admitted.value.expectedCount then
						returns:reconstruct(admitted.value.returnId)
					else
						task.delay(10, function()
							if not runtimeCleaned then
								returns:reconstruct(admitted.value.returnId)
								publishPartyViews()
							end
						end)
					end
				end
			end

			pendingClaims:processReady(userId)
			refreshRoute(player)
			publishViews(player)
			publishQueueViews()
		end)
		processingReadyByUserId[userId] = nil
		if not succeeded then
			return
		end
	end

	local function finishMutation(player: Player, result: any): ServerRequestDispatcher.HandlerOutcome
		if type(result) ~= "table" or result.ok ~= true then
			local code = if type(result) == "table" and type(result.error) == "table" then result.error.code else nil
			return ServerRequestDispatcher.reject(
				if code == "STALE_REVISION" then PUBLIC_ERRORS.STALE_REQUEST else PUBLIC_ERRORS.UNAVAILABLE
			)
		end
		profile:queueImportantSave(player.UserId)
		publishViews(player)
		return ServerRequestDispatcher.success(result.value)
	end

	local function ready(player: Player): boolean
		return profile:getState(player.UserId) == "Ready"
	end

	local function finishParty(result: any): ServerRequestDispatcher.HandlerOutcome
		if type(result) ~= "table" or result.ok ~= true then
			local code = if type(result) == "table" and type(result.error) == "table" then result.error.code else nil
			return ServerRequestDispatcher.reject(
				if code == "STALE_REVISION" then PUBLIC_ERRORS.STALE_REQUEST else PUBLIC_ERRORS.UNAVAILABLE
			)
		end
		return ServerRequestDispatcher.success(result.value)
	end

	local function finishQueue(result: any): ServerRequestDispatcher.HandlerOutcome
		if type(result) ~= "table" or result.ok ~= true then
			local code = if type(result) == "table" and type(result.error) == "table" then result.error.code else nil
			return ServerRequestDispatcher.reject(
				if code == "STALE_REVISION" then PUBLIC_ERRORS.STALE_REQUEST else PUBLIC_ERRORS.UNAVAILABLE
			)
		end
		return ServerRequestDispatcher.success(result.value)
	end

	local function preparePermission(inviterUserId: number, targetUserId: number): boolean
		local cached = permissionCache:get(inviterUserId, targetUserId)
		if cached == nil then
			permissionCache:request(inviterUserId, targetUserId)
			return false
		end
		return true
	end

	local function prepareInvitationAcceptance(userId: number, invitationId: string): boolean
		local snapshot = party:getSnapshot(userId)
		if not snapshot.ok then
			return false
		end
		for _, invitation in snapshot.value.incomingInvitations do
			if invitation.invitationId == invitationId then
				return preparePermission(invitation.inviterUserId, userId)
			end
		end
		return true
	end

	network:registerRequest(
		LobbyProtocol.ENDPOINTS.GET_PROFILE,
		LobbyProtocol.EmptyPayloadSchema,
		ProfileProtocol.SnapshotSchema,
		authorizeLiveContext,
		function(context, _payload)
			local result = profile:getClientSnapshot(context.player.UserId)
			return if result.ok
				then ServerRequestDispatcher.success(result.value)
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.RETRY_PROFILE,
		LobbyProtocol.EmptyPayloadSchema,
		ProfileProtocol.SnapshotSchema,
		authorizeLiveContext,
		function(context, _payload)
			if profile:getState(context.player.UserId) ~= "Failed" then
				local current = profile:getClientSnapshot(context.player.UserId)
				return if current.ok
					then ServerRequestDispatcher.success(current.value)
					else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			task.spawn(function()
				profile:retryLoad(context.player.UserId)
				processPlayerReady(context.player)
			end)
			return ServerRequestDispatcher.success(ProfileProtocol.status("Loading"))
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.GET_INVENTORY,
		LobbyProtocol.EmptyPayloadSchema,
		InventoryProtocol.SnapshotSchema,
		authorizeLiveContext,
		function(context, _payload)
			local result = inventory:getSnapshot(context.player.UserId)
			return if result.ok
				then ServerRequestDispatcher.success(result.value)
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.EQUIP_TOWER,
		InventoryProtocol.EquipIntentSchema,
		InventoryProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return finishMutation(context.player, inventory:equip(context.player.UserId, payload))
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.UNEQUIP_TOWER,
		InventoryProtocol.UnitMutationIntentSchema,
		InventoryProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return finishMutation(context.player, inventory:unequip(context.player.UserId, payload))
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.FAVORITE_TOWER,
		InventoryProtocol.ToggleIntentSchema,
		InventoryProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return finishMutation(context.player, inventory:favorite(context.player.UserId, payload))
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.LOCK_TOWER,
		InventoryProtocol.ToggleIntentSchema,
		InventoryProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return finishMutation(context.player, inventory:lock(context.player.UserId, payload))
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.GET_BANNER,
		LobbyProtocol.BannerRequestSchema,
		AcquisitionProtocol.BannerViewSchema,
		authorizeLiveContext,
		function(context, payload)
			local request = payload :: BannerRequest
			local result = acquisition:getBannerView(context.player.UserId, request.bannerId)
			return if result.ok
				then ServerRequestDispatcher.success(result.value)
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.PULL_CHEST,
		AcquisitionProtocol.PullIntentSchema,
		AcquisitionProtocol.PullReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return finishMutation(context.player, acquisition:pull(context.player.UserId, payload))
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.UPDATE_SETTINGS,
		SettingsProtocol.UpdateIntentSchema,
		SettingsProtocol.UpdateReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return finishMutation(context.player, settings:update(context.player.UserId, payload))
		end
	)

	network:registerRequest(
		LobbyProtocol.ENDPOINTS.GET_PARTY,
		LobbyProtocol.EmptyPayloadSchema,
		PartyProtocol.ViewerSnapshotSchema,
		authorizeLiveContext,
		function(context, _payload)
			if not ready(context.player) then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			local result = party:getSnapshot(context.player.UserId)
			return if result.ok
				then ServerRequestDispatcher.success(result.value)
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.CREATE_PARTY,
		PartyProtocol.CreateIntentSchema,
		PartyProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return if ready(context.player)
				then finishParty(party:create(context.player.UserId, payload))
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.INVITE_PARTY,
		PartyProtocol.InviteIntentSchema,
		PartyProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local intent = payload :: PartyProtocol.InviteIntent
			if not ready(context.player) or not preparePermission(context.player.UserId, intent.targetUserId) then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			return finishParty(party:invite(context.player.UserId, intent))
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.ACCEPT_PARTY_INVITE,
		PartyProtocol.InvitationIntentSchema,
		PartyProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local intent = payload :: PartyProtocol.InvitationIntent
			if
				not ready(context.player)
				or not prepareInvitationAcceptance(context.player.UserId, intent.invitationId)
			then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			return finishParty(party:accept(context.player.UserId, intent))
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.DECLINE_PARTY_INVITE,
		PartyProtocol.InvitationIntentSchema,
		PartyProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return if ready(context.player)
				then finishParty(party:decline(context.player.UserId, payload))
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.LEAVE_PARTY,
		PartyProtocol.RevisionIntentSchema,
		PartyProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return if ready(context.player)
				then finishParty(party:leave(context.player.UserId, payload))
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.KICK_PARTY_MEMBER,
		PartyProtocol.MemberIntentSchema,
		PartyProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return if ready(context.player)
				then finishParty(party:kick(context.player.UserId, payload))
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.TRANSFER_PARTY_LEADERSHIP,
		PartyProtocol.MemberIntentSchema,
		PartyProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return if ready(context.player)
				then finishParty(party:transferLeadership(context.player.UserId, payload))
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.SET_PARTY_PRIVACY,
		PartyProtocol.PrivacyIntentSchema,
		PartyProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return if ready(context.player)
				then finishParty(party:setPrivacy(context.player.UserId, payload))
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.DISBAND_PARTY,
		PartyProtocol.RevisionIntentSchema,
		PartyProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return if ready(context.player)
				then finishParty(party:disband(context.player.UserId, payload))
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.PROMPT_PARTY_INVITE,
		LobbyProtocol.InvitePromptIntentSchema,
		LobbyProtocol.InvitePromptReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local intent = payload :: any
			local enrollment = party:getPartyForUser(context.player.UserId)
			if
				not ready(context.player)
				or enrollment == nil
				or enrollment.leaderUserId ~= context.player.UserId
				or enrollment.revision ~= intent.expectedRevision
			then
				return ServerRequestDispatcher.reject(
					if enrollment ~= nil and enrollment.revision ~= intent.expectedRevision
						then PUBLIC_ERRORS.STALE_REQUEST
						else PUBLIC_ERRORS.UNAVAILABLE
				)
			end
			local prompted = platformInvite:prompt(context.player, context.player.UserId, opaqueId("invitation"))
			local status = if prompted.ok and prompted.value == "Prompted"
				then "Opened"
				elseif prompted.ok and prompted.value == "Denied" then "Denied"
				else "Unavailable"
			return ServerRequestDispatcher.success({ transactionId = intent.transactionId, status = status })
		end
	)

	network:registerRequest(
		LobbyProtocol.ENDPOINTS.GET_QUEUES,
		LobbyProtocol.EmptyPayloadSchema,
		LobbyProtocol.QueueListSchema,
		authorizeLiveContext,
		function(_context, _payload)
			return ServerRequestDispatcher.success(queueList())
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.JOIN_QUEUE,
		QueueProtocol.JoinIntentSchema,
		QueueProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			local intent = payload :: QueueProtocol.JoinIntent
			if not ready(context.player) or intent.source ~= "UI" then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			return finishQueue(queue:join(context.player.UserId, intent))
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.LEAVE_QUEUE,
		QueueProtocol.LeaveIntentSchema,
		QueueProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return if ready(context.player)
				then finishQueue(queue:leave(context.player.UserId, payload))
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.CONFIGURE_QUEUE,
		QueueProtocol.ConfigureIntentSchema,
		QueueProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return if ready(context.player)
				then finishQueue(queue:configure(context.player.UserId, payload))
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.START_QUEUE,
		QueueProtocol.StartIntentSchema,
		QueueProtocol.MutationReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return if ready(context.player)
				then finishQueue(queue:start(context.player.UserId, payload))
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.GET_ACTIVE_ROUTE,
		LobbyProtocol.EmptyPayloadSchema,
		LobbyProtocol.ActiveRouteViewSchema,
		authorizeLiveContext,
		function(context, _payload)
			local result = reconnect:getView(context.player.UserId)
			if not result.ok then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			activeRouteViewByUserId[context.player.UserId] = result.value
			routeBlockedByUserId[context.player.UserId] = result.value.status == "Available"
			return ServerRequestDispatcher.success(result.value)
		end
	)
	network:registerRequest(
		LobbyProtocol.ENDPOINTS.RECONNECT_ACTIVE_MATCH,
		LobbyProtocol.ReconnectIntentSchema,
		LobbyProtocol.ReconnectReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			if not ready(context.player) then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
			end
			local result = reconnect:reconnect(context.player.UserId, (payload :: any).transactionId)
			return if result.ok
				then ServerRequestDispatcher.success(result.value)
				else ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
		end
	)

	local runtimeConnections: { RBXScriptConnection } = {}
	local travelStepRunning = false
	local nextMaintenanceAt = 0
	local nextClaimRetryAt = 0
	local MAINTENANCE_INTERVAL_SECONDS = 5
	local CLAIM_RETRY_INTERVAL_SECONDS = 60
	local runtimeDefinition = table.freeze({
		name = "LobbySquadTravelRuntime",
		dependencies = table.freeze({}),
		initialize = function() end,
		start = function()
			table.insert(
				runtimeConnections,
				Players.PlayerAdded:Connect(function(player)
					task.spawn(processPlayerReady, player)
				end)
			)
			table.insert(
				runtimeConnections,
				Players.PlayerRemoving:Connect(function(player)
					travel:removePlayer(player.UserId)
					party:removePlayer(player.UserId, "ServerLeave")
					queue:removePlayer(player.UserId)
					reconnect:removePlayer(player.UserId)
					permissionCache:removePlayer(player.UserId)
					processingReadyByUserId[player.UserId] = nil
					routeBlockedByUserId[player.UserId] = nil
					activeRouteViewByUserId[player.UserId] = nil
				end)
			)
			table.insert(
				runtimeConnections,
				RunService.Heartbeat:Connect(function()
					if not travelStepRunning then
						travelStepRunning = true
						task.spawn(function()
							pcall(function()
								profileTransfer:step()
								travel:step()
								returns:step()
								reconnect:step()
								local currentTime = os.time()
								if currentTime >= nextMaintenanceAt then
									nextMaintenanceAt = currentTime + MAINTENANCE_INTERVAL_SECONDS
									local retryClaims = currentTime >= nextClaimRetryAt
									if retryClaims then
										nextClaimRetryAt = currentTime + CLAIM_RETRY_INTERVAL_SECONDS
									end
									for _, player in Players:GetPlayers() do
										if profile:getState(player.UserId) == "Ready" then
											if retryClaims then
												pendingClaims:processReady(player.UserId)
											end
											refreshRoute(player)
										end
									end
									publishQueueViews()
								end
							end)
							travelStepRunning = false
						end)
					end
				end)
			)
			for _, player in Players:GetPlayers() do
				task.spawn(processPlayerReady, player)
			end
			task.defer(publishQueueViews)
		end,
		shutdown = function()
			runtimeCleaned = true
			for index = #runtimeConnections, 1, -1 do
				runtimeConnections[index]:Disconnect()
			end
			table.clear(runtimeConnections)
			reconnect:cleanup()
			safeTeleport:cleanup()
			profileTransfer:cleanup()
			party:cleanup()
			queue:cleanup()
			pendingResults:cleanup()
			table.clear(processingReadyByUserId)
			table.clear(routeBlockedByUserId)
			table.clear(activeRouteViewByUserId)
		end,
	})

	configuration.lifecycleRunner:register(profile:getServiceDefinition())
	configuration.lifecycleRunner:register(permissionCache:getServiceDefinition())
	configuration.lifecycleRunner:register(runtimeDefinition)
	configuration.lifecycleRunner:register(travel:getServiceDefinition())
	configuration.lifecycleRunner:register(returns:getServiceDefinition())
	configuration.lifecycleRunner:register(pendingClaims:getServiceDefinition())
	if worldDisplay ~= nil then
		configuration.lifecycleRunner:register(worldDisplay:getServiceDefinition())
	end
	if zoneService ~= nil then
		configuration.lifecycleRunner:register(zoneService:getServiceDefinition())
	end
end)
