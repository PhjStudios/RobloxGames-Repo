--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AcquisitionProtocol = require(ReplicatedStorage.Shared.acquisition.AcquisitionProtocol)
local InventoryProtocol = require(ReplicatedStorage.Shared.inventory.InventoryProtocol)
local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local LobbyProtocol = require(ReplicatedStorage.Shared.lobby.LobbyProtocol)
local ProfileProtocol = require(ReplicatedStorage.Shared.profile.ProfileProtocol)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local SettingsProtocol = require(ReplicatedStorage.Shared.settings.SettingsProtocol)

local ServerBootstrap = require(script.Parent.ServerBootstrap)
local ServerRequestDispatcher = require(script.Parent.Parent.networking.ServerRequestDispatcher)
local ProfileService = require(script.Parent.Parent.profile.ProfileService)
local ProfileStoreAdapter = require(script.Parent.Parent.profile.ProfileStoreAdapter)
local AcquisitionService = require(script.Parent.Parent.Parent.lobby.acquisition.AcquisitionService)
local InventoryService = require(script.Parent.Parent.Parent.lobby.inventory.InventoryService)
local SettingsService = require(script.Parent.Parent.Parent.lobby.settings.SettingsService)

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

	local function publishViews(player: Player)
		local profileView = profile:getClientSnapshot(player.UserId)
		if profileView.ok then
			sendProfile(player, profileView.value)
		end
		local inventoryView = inventory:getSnapshot(player.UserId)
		if inventoryView.ok then
			sendInventory(player, inventoryView.value)
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

	configuration.lifecycleRunner:register(profile:getServiceDefinition())
end)
