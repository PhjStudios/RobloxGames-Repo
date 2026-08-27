--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local ServerBootstrap = require(script.Parent.ServerBootstrap)
local ServerRequestDispatcher = require(script.Parent.Parent.networking.ServerRequestDispatcher)
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

ServerBootstrap.run(PlaceRoles.MATCH_ROLE, function(configuration)
	local network = configuration.serverRemoteRegistry
	if network == nil then
		error("[ATD_MATCH_BOOTSTRAP][code=NETWORK_REGISTRY_MISSING]", 0)
	end

	local sendSnapshot =
		network:registerServerEvent(MatchProtocol.MATCH_SNAPSHOT_ENDPOINT, MatchProtocol.MatchSnapshotSchema)
	local matchLifecycle = MatchLifecycleService.new(configuration.log, sendSnapshot)

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
	configuration.lifecycleRunner:register(matchLifecycle:getServiceDefinition())
end)
