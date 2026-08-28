--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local ServerBootstrap = require(script.Parent.ServerBootstrap)
local ServerRequestDispatcher = require(script.Parent.Parent.networking.ServerRequestDispatcher)
local BaseRuntimeService = require(script.Parent.Parent.Parent.match.base.BaseRuntimeService)
local EnemySimulationService = require(script.Parent.Parent.Parent.match.enemies.EnemySimulationService)
local MatchLifecycleService = require(script.Parent.Parent.Parent.match.lifecycle.MatchLifecycleService)

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
	local matchLifecycle = MatchLifecycleService.new(configuration.log, sendSnapshot)
	local baseRuntime =
		BaseRuntimeService.new(matchLifecycle, configuration.coreConfiguration.difficulties, sendBaseReplication)
	local enemySimulation = EnemySimulationService.new(
		matchLifecycle,
		baseRuntime,
		configuration.coreConfiguration.enemies,
		sendEnemyReplication
	)

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
	configuration.lifecycleRunner:register(matchLifecycle:getServiceDefinition())
	configuration.lifecycleRunner:register(baseRuntime:getServiceDefinition())
	configuration.lifecycleRunner:register(enemySimulation:getServiceDefinition())
end)
