--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local PlacementProtocol = require(ReplicatedStorage.Shared.match.PlacementProtocol)
local WaveProtocol = require(ReplicatedStorage.Shared.match.WaveProtocol)
local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local ServerBootstrap = require(script.Parent.ServerBootstrap)
local ServerRequestDispatcher = require(script.Parent.Parent.networking.ServerRequestDispatcher)
local BaseRuntimeService = require(script.Parent.Parent.Parent.match.base.BaseRuntimeService)
local EnemySimulationService = require(script.Parent.Parent.Parent.match.enemies.EnemySimulationService)
local MatchLifecycleService = require(script.Parent.Parent.Parent.match.lifecycle.MatchLifecycleService)
local TowerPlacementService = require(script.Parent.Parent.Parent.match.placement.TowerPlacementService)
local WaveRuntimeService = require(script.Parent.Parent.Parent.match.waves.WaveRuntimeService)
local TowerRuntimeService = require(script.Parent.Parent.Parent.match.towers.TowerRuntimeService)

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

local function rejectCode(code: unknown): ServerRequestDispatcher.HandlerOutcome
	local errorValue = if type(code) == "string" then PUBLIC_ERRORS[code] else nil
	return ServerRequestDispatcher.reject(errorValue or PUBLIC_ERRORS.INTERNAL_ERROR)
end

local function authorizeContext(context: ServerRequestDispatcher.ServerContext): boolean
	return ServerRequestDispatcher.isContext(context)
end

local function authorizeLivePlacementContext(context: ServerRequestDispatcher.ServerContext): boolean
	if not ServerRequestDispatcher.isContext(context) then
		return false
	end
	local player = context.player
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local function rejectEnemySnapshot(code: unknown): ServerRequestDispatcher.HandlerOutcome
	if code == "INVALID_RECIPIENT" then
		return ServerRequestDispatcher.reject(PUBLIC_ERRORS.NOT_AUTHORIZED)
	elseif code == "INTERNAL_ERROR" or code == "INVALID_PROVIDER" then
		return ServerRequestDispatcher.reject(PUBLIC_ERRORS.INTERNAL_ERROR)
	end
	return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
end

local function rejectBaseSnapshot(code: unknown): ServerRequestDispatcher.HandlerOutcome
	if code == "INTERNAL_ERROR" then
		return ServerRequestDispatcher.reject(PUBLIC_ERRORS.INTERNAL_ERROR)
	end
	return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
end

local function rejectPlacementQuery(code: unknown): ServerRequestDispatcher.HandlerOutcome
	if code == "NOT_ELIGIBLE" or code == "INVALID_ARGUMENT" then
		return ServerRequestDispatcher.reject(PUBLIC_ERRORS.NOT_AUTHORIZED)
	elseif code == "INTERNAL_ERROR" then
		return ServerRequestDispatcher.reject(PUBLIC_ERRORS.INTERNAL_ERROR)
	end
	return ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)
end

ServerBootstrap.run(PlaceRoles.MATCH_ROLE, function(configuration)
	local network = configuration.serverRemoteRegistry
	if network == nil then
		error("[ATD_MATCH_BOOTSTRAP][code=NETWORK_REGISTRY_MISSING]", 0)
	end

	local sendSnapshot =
		network:registerServerEvent(MatchProtocol.MATCH_SNAPSHOT_ENDPOINT, MatchProtocol.MatchSnapshotSchema)
	local sendEnemyReplication =
		network:registerServerEvent(EnemyProtocol.ENEMY_REPLICATION_ENDPOINT, EnemyProtocol.EnemyReplicationSchema)
	local sendBaseReplication =
		network:registerServerEvent(BaseProtocol.BASE_REPLICATION_ENDPOINT, BaseProtocol.BaseReplicationSchema)
	local sendWaveReplication =
		network:registerServerEvent(WaveProtocol.WAVE_REPLICATION_ENDPOINT, WaveProtocol.WaveSnapshotSchema)
	local sendPlacementRevision =
		network:registerServerEvent(PlacementProtocol.REVISION_ENDPOINT, PlacementProtocol.RevisionEventSchema)
	local queryRevisionProvider: () -> unknown = function(): unknown
		return nil
	end
	local sendLifecycleSnapshot = TowerPlacementService.createRevisionAwareSnapshotSender(
		sendSnapshot,
		sendPlacementRevision,
		function(): unknown
			return queryRevisionProvider()
		end
	)
	local matchLifecycle = MatchLifecycleService.new(configuration.log, sendLifecycleSnapshot)
	local baseRuntime =
		BaseRuntimeService.new(matchLifecycle, configuration.coreConfiguration.difficulties, sendBaseReplication)
	local enemySimulation = EnemySimulationService.new(
		matchLifecycle,
		baseRuntime,
		configuration.coreConfiguration.enemies,
		sendEnemyReplication
	)
	local waveRuntime = WaveRuntimeService.new(
		matchLifecycle,
		baseRuntime,
		enemySimulation,
		configuration.coreConfiguration,
		nil,
		sendWaveReplication
	)
	local towerRuntime = TowerRuntimeService.new(matchLifecycle, waveRuntime, configuration.coreConfiguration)
	local towerPlacement = TowerPlacementService.new(matchLifecycle, towerRuntime, function(matchId, queryRevision)
		local payload = table.freeze({ matchId = matchId, queryRevision = queryRevision })
		local sent = true
		for _, player in Players:GetPlayers() do
			if not sendPlacementRevision(player, payload) then
				sent = false
			end
		end
		return sent
	end)
	queryRevisionProvider = function(): unknown
		return towerPlacement:getMetrics().queryRevision
	end

	network:registerRequest(
		MatchProtocol.GET_MATCH_SNAPSHOT_ENDPOINT,
		MatchProtocol.GetMatchSnapshotPayloadSchema,
		MatchProtocol.MatchSnapshotSchema,
		authorizeContext,
		function(_context, _payload)
			local snapshotResult = matchLifecycle:getSnapshot()
			if snapshotResult.ok then
				return ServerRequestDispatcher.success(snapshotResult.value)
			end
			return rejectCode(snapshotResult.error.code)
		end
	)
	network:registerRequest(
		MatchProtocol.SUBMIT_READY_ENDPOINT,
		MatchProtocol.SubmitReadyPayloadSchema,
		MatchProtocol.MatchSnapshotSchema,
		authorizeContext,
		function(context, payload)
			local canonicalPayload = payload :: MatchProtocol.SubmitReadyPayload
			local readyResult =
				matchLifecycle:submitReady(context.player, canonicalPayload.matchId, canonicalPayload.observedRevision)
			if readyResult.ok then
				return ServerRequestDispatcher.success(readyResult.value)
			end
			return rejectCode(readyResult.error.code)
		end
	)
	network:registerRequest(
		BaseProtocol.GET_BASE_SNAPSHOT_ENDPOINT,
		BaseProtocol.GetBaseSnapshotPayloadSchema,
		BaseProtocol.BaseSnapshotSchema,
		authorizeContext,
		function(_context, _payload)
			local snapshotResult = baseRuntime:getSnapshot()
			if snapshotResult.ok then
				return ServerRequestDispatcher.success(snapshotResult.value)
			end
			return rejectBaseSnapshot(snapshotResult.error.code)
		end
	)
	network:registerRequest(
		EnemyProtocol.GET_ENEMY_SNAPSHOT_ENDPOINT,
		EnemyProtocol.GetEnemySnapshotPayloadSchema,
		EnemyProtocol.EnemySnapshotReceiptSchema,
		authorizeContext,
		function(context, _payload)
			local snapshotResult = enemySimulation:requestSnapshot(context.player)
			if snapshotResult.ok then
				return ServerRequestDispatcher.success(snapshotResult.value)
			end
			return rejectEnemySnapshot(snapshotResult.error.code)
		end
	)
	network:registerRequest(
		WaveProtocol.GET_WAVE_SNAPSHOT_ENDPOINT,
		WaveProtocol.GetWaveSnapshotPayloadSchema,
		WaveProtocol.WaveSnapshotSchema,
		authorizeContext,
		function(_context, _payload)
			local snapshotResult = waveRuntime:getSnapshot()
			if snapshotResult.ok then
				return ServerRequestDispatcher.success(snapshotResult.value)
			end
			return rejectCode(snapshotResult.error.code)
		end
	)
	network:registerRequest(
		WaveProtocol.SUBMIT_SKIP_VOTE_ENDPOINT,
		WaveProtocol.SubmitSkipVotePayloadSchema,
		WaveProtocol.WaveSnapshotSchema,
		authorizeContext,
		function(context, payload)
			local canonicalPayload = payload :: WaveProtocol.SubmitSkipVotePayload
			local voteResult =
				waveRuntime:submitSkipVote(context.player.UserId, canonicalPayload.matchId, canonicalPayload.waveNumber)
			if voteResult.ok then
				return ServerRequestDispatcher.success(voteResult.value)
			end
			return rejectCode(voteResult.error.code)
		end
	)
	network:registerRequest(
		PlacementProtocol.GET_QUERY_ENDPOINT,
		PlacementProtocol.GetQueryPayloadSchema,
		PlacementProtocol.QuerySnapshotSchema,
		authorizeLivePlacementContext,
		function(context, _payload)
			if not authorizeLivePlacementContext(context) then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.NOT_AUTHORIZED)
			end
			local queryResult = towerPlacement:getQuery(context.player.UserId)
			if queryResult.ok then
				return ServerRequestDispatcher.success(queryResult.value)
			end
			return rejectPlacementQuery(queryResult.error.code)
		end
	)
	network:registerRequest(
		PlacementProtocol.SUBMIT_PLACEMENT_ENDPOINT,
		PlacementProtocol.SubmitPlacementPayloadSchema,
		PlacementProtocol.PlacementReceiptSchema,
		authorizeLivePlacementContext,
		function(context, payload)
			if not authorizeLivePlacementContext(context) then
				return ServerRequestDispatcher.reject(PUBLIC_ERRORS.NOT_AUTHORIZED)
			end
			local placementResult =
				towerPlacement:submitPlacement(context.player.UserId, payload :: PlacementProtocol.PlacementIntent)
			if placementResult.ok then
				return ServerRequestDispatcher.success(placementResult.value)
			end
			return rejectPlacementQuery(placementResult.error.code)
		end
	)
	configuration.lifecycleRunner:register(matchLifecycle:getServiceDefinition())
	configuration.lifecycleRunner:register(baseRuntime:getServiceDefinition())
	configuration.lifecycleRunner:register(enemySimulation:getServiceDefinition())
	configuration.lifecycleRunner:register(waveRuntime:getServiceDefinition())
	configuration.lifecycleRunner:register(towerRuntime:getServiceDefinition())
	configuration.lifecycleRunner:register(towerPlacement:getServiceDefinition())
end)
