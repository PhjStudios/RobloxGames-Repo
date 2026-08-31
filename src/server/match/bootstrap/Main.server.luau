--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local PlacementProtocol = require(ReplicatedStorage.Shared.match.PlacementProtocol)
local PlayableMatchProtocol = require(ReplicatedStorage.Shared.match.PlayableMatchProtocol)
local WaveProtocol = require(ReplicatedStorage.Shared.match.WaveProtocol)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)

local ServerBootstrap = require(script.Parent.ServerBootstrap)
local ServerRequestDispatcher = require(script.Parent.Parent.networking.ServerRequestDispatcher)
local MatchLifecycleService = require(script.Parent.Parent.Parent.match.lifecycle.MatchLifecycleService)
local PlayableMatchService = require(script.Parent.Parent.Parent.match.playable.PlayableMatchService)

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
	local sendAttack = network:registerServerEvent(
		PlayableMatchProtocol.ENDPOINTS.ATTACK_EVENT,
		PlayableMatchProtocol.AttackEventSchema
	)

	local matchLifecycle = MatchLifecycleService.new(configuration.log, sendMatchSnapshot)
	local playable = PlayableMatchService.new(
		configuration.log,
		matchLifecycle,
		configuration.coreConfiguration,
		sendPlayableSnapshot,
		sendAttack
	)

	-- Preserve the Phase 8 ready/snapshot compatibility boundary. Superseded
	-- combat, wave, base, and placement requests fail closed without starting a
	-- second authoritative simulation graph.
	network:registerRequest(
		MatchProtocol.GET_MATCH_SNAPSHOT_ENDPOINT,
		MatchProtocol.GetMatchSnapshotPayloadSchema,
		MatchProtocol.MatchSnapshotSchema,
		authorizeLiveContext,
		function(_context, _payload)
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
			local result = playable:getSnapshot(context.player)
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
			return actionOutcome(playable:submitReady(context.player, payload :: PlayableMatchProtocol.ReadyPayload))
		end
	)
	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.SUBMIT_PLACEMENT,
		PlayableMatchProtocol.PlacementPayloadSchema,
		PlayableMatchProtocol.ActionReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return actionOutcome(
				playable:submitPlacement(context.player, payload :: PlayableMatchProtocol.PlacementPayload)
			)
		end
	)
	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.SUBMIT_UPGRADE,
		PlayableMatchProtocol.TowerPayloadSchema,
		PlayableMatchProtocol.ActionReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return actionOutcome(playable:submitUpgrade(context.player, payload :: PlayableMatchProtocol.TowerPayload))
		end
	)
	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.SUBMIT_SELL,
		PlayableMatchProtocol.TowerPayloadSchema,
		PlayableMatchProtocol.ActionReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return actionOutcome(playable:submitSell(context.player, payload :: PlayableMatchProtocol.TowerPayload))
		end
	)
	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.SUBMIT_TARGET_MODE,
		PlayableMatchProtocol.TargetModePayloadSchema,
		PlayableMatchProtocol.ActionReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return actionOutcome(
				playable:submitTargetMode(context.player, payload :: PlayableMatchProtocol.TargetModePayload)
			)
		end
	)
	network:registerRequest(
		PlayableMatchProtocol.ENDPOINTS.SUBMIT_REPLAY,
		PlayableMatchProtocol.ReplayPayloadSchema,
		PlayableMatchProtocol.ActionReceiptSchema,
		authorizeLiveContext,
		function(context, payload)
			return actionOutcome(playable:submitReplay(context.player, payload :: PlayableMatchProtocol.ReplayPayload))
		end
	)

	configuration.lifecycleRunner:register(matchLifecycle:getServiceDefinition())
	configuration.lifecycleRunner:register(playable:getServiceDefinition())
end)
