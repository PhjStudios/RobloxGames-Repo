--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local Cleanup = require(ReplicatedStorage.Shared.util.Cleanup)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local ServerRateLimiter = require(script.Parent.ServerRateLimiter)

export type NetworkState =
	"Registering"
	| "Initializing"
	| "Initialized"
	| "Starting"
	| "Started"
	| "ShuttingDown"
	| "Shutdown"
	| "Failed"
export type Handler = (player: Player, ...unknown) -> ()
export type ConnectAdapter = (remote: RemoteEvent, handler: Handler) -> RBXScriptConnection
export type LimiterDependencies = {
	players: Instance?,
	clock: ServerRateLimiter.Clock?,
	connectPlayerRemoving: ServerRateLimiter.ConnectPlayerRemoving?,
	reporter: ServerRateLimiter.Reporter?,
}

type HandlerMap = { [string]: Handler }
type RemoteMap = { [string]: RemoteEvent }
type ResolvedLimiterDependencies = {
	players: Instance,
	clock: ServerRateLimiter.Clock,
	connectPlayerRemoving: ServerRateLimiter.ConnectPlayerRemoving?,
	reporter: ServerRateLimiter.Reporter?,
}

type ServerData = {
	logger: Log.Logger,
	registry: RemoteRegistry.Registry,
	replicatedStorage: ReplicatedStorage,
	role: RemoteRegistry.RuntimePlaceRole,
	connectAdapter: ConnectAdapter,
	ratePolicySet: ServerRateLimiter.PolicySet,
	limiterDependencies: ResolvedLimiterDependencies,
	activeDefinitions: { RemoteRegistry.Definition },
	activeDefinitionsByName: { [string]: RemoteRegistry.Definition },
	handlers: HandlerMap,
	state: NetworkState,
	cleanup: Cleanup.Container?,
	rateLimiter: ServerRateLimiter.Limiter?,
	root: Folder?,
	serviceDefinition: ServiceLifecycle.ServiceDefinition?,
}

local Server = {}
Server.__index = Server

export type Server = typeof(setmetatable({} :: ServerData, Server))

local ServerRemoteRegistry = {}

local UNKNOWN_ENDPOINT = "<unknown>"
local SERVICE_NAME = "NetworkRegistry"
local CLEANUP_LABEL = "network-registry"
local SERVER_REGISTRY = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
local LIMITER_DEPENDENCY_FIELDS: { [string]: boolean } = table.freeze({
	clock = true,
	connectPlayerRemoving = true,
	players = true,
	reporter = true,
})

local function defaultConnect(remote: RemoteEvent, handler: Handler): RBXScriptConnection
	return remote.OnServerEvent:Connect(handler)
end

local function requireServer(value: unknown): ServerData
	if type(value) ~= "table" or SERVER_REGISTRY[value] ~= true then
		error(
			"[ATD][ERROR][context=unknown][role=Unresolved][placeId=unknown][environment=unknown][subsystem=network][event=method_rejected][code=INVALID_CONTEXT][endpoint=<unknown>][networkState=Unknown] Network registry method requires a genuine server registry",
			0
		)
	end

	return value :: ServerData
end

local function fail(server: ServerData, event: string, code: string, endpoint: string, message: string): never
	server.logger:error("network", event, message, {
		code = code,
		endpoint = endpoint,
		networkState = server.state,
	})
end

local function failConstruction(logger: Log.Logger, code: string, message: string, validationPath: string?): never
	local fields: Log.Fields = {
		code = code,
		endpoint = UNKNOWN_ENDPOINT,
		networkState = "Uninitialized",
	}
	if validationPath ~= nil then
		fields.validationPath = validationPath
	end
	logger:error("network", "construction_rejected", message, fields)
end

local function resolveLimiterDependencies(logger: Log.Logger, value: LimiterDependencies?): ResolvedLimiterDependencies
	if value == nil then
		return table.freeze({
			players = Players,
			clock = os.clock,
			connectPlayerRemoving = nil,
			reporter = nil,
		})
	end
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		failConstruction(
			logger,
			"INVALID_LIMITER_DEPENDENCIES",
			"Rate-limiter dependencies must be an exact plain record",
			"limiterDependencies"
		)
	end

	local rawDependencies = value :: { [any]: unknown }
	for rawKey in next, rawDependencies do
		if type(rawKey) ~= "string" or LIMITER_DEPENDENCY_FIELDS[rawKey] ~= true then
			failConstruction(
				logger,
				"INVALID_LIMITER_DEPENDENCIES",
				"Rate-limiter dependencies contain an unsupported field",
				"limiterDependencies"
			)
		end
	end

	local players = rawget(rawDependencies, "players")
	if players == nil then
		players = Players
	end
	local classRead, isPlayers = pcall(function(): boolean
		return typeof(players) == "Instance" and (players :: Instance):IsA("Players")
	end)
	if not classRead or not isPlayers then
		failConstruction(
			logger,
			"INVALID_LIMITER_DEPENDENCIES",
			"Rate-limiter players dependency must be the Players service",
			"limiterDependencies.players"
		)
	end

	local clock = rawget(rawDependencies, "clock")
	if clock == nil then
		clock = os.clock
	end
	if type(clock) ~= "function" then
		failConstruction(
			logger,
			"INVALID_LIMITER_DEPENDENCIES",
			"Rate-limiter clock dependency must be a function",
			"limiterDependencies.clock"
		)
	end

	local connectPlayerRemoving = rawget(rawDependencies, "connectPlayerRemoving")
	if connectPlayerRemoving ~= nil and type(connectPlayerRemoving) ~= "function" then
		failConstruction(
			logger,
			"INVALID_LIMITER_DEPENDENCIES",
			"Rate-limiter PlayerRemoving connector must be a function or nil",
			"limiterDependencies.connectPlayerRemoving"
		)
	end

	local reporter = rawget(rawDependencies, "reporter")
	if reporter ~= nil and type(reporter) ~= "function" then
		failConstruction(
			logger,
			"INVALID_LIMITER_DEPENDENCIES",
			"Rate-limiter reporter must be a function or nil",
			"limiterDependencies.reporter"
		)
	end

	return table.freeze({
		players = players :: Instance,
		clock = clock :: ServerRateLimiter.Clock,
		connectPlayerRemoving = connectPlayerRemoving :: ServerRateLimiter.ConnectPlayerRemoving?,
		reporter = reporter :: ServerRateLimiter.Reporter?,
	})
end

local function endpointForLog(server: ServerData, endpointName: unknown): string
	if type(endpointName) ~= "string" then
		return UNKNOWN_ENDPOINT
	end

	local definition = server.registry:get(endpointName)
	if definition == nil then
		return UNKNOWN_ENDPOINT
	end

	return definition.name
end

local function createRemote(name: string, parent: Instance): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function populateUnpublishedTree(root: Folder, definitions: { RemoteRegistry.Definition }): RemoteMap
	root.Name = RemoteRegistry.ROOT_NAME
	local version = Instance.new("Folder")
	version.Name = RemoteRegistry.VERSION_NAME
	version.Parent = root

	local inboundRemotes: RemoteMap = {}
	for _, definition in definitions do
		local endpoint = Instance.new("Folder")
		endpoint.Name = definition.name
		endpoint.Parent = version

		if definition.kind == "Request" then
			local request = createRemote("Request", endpoint)
			if definition.direction == "ClientToServer" then
				inboundRemotes[definition.name] = request
			end

			if definition.response == "Required" then
				createRemote("Response", endpoint)
			end
		else
			local event = createRemote("Event", endpoint)
			if definition.direction == "ClientToServer" then
				inboundRemotes[definition.name] = event
			end
		end
	end

	return inboundRemotes
end

local function rollback(server: ServerData): boolean
	local cleanup = server.cleanup
	if cleanup == nil then
		server.rateLimiter = nil
		return true
	end

	local succeeded = pcall(function()
		cleanup:cleanup()
	end)
	server.rateLimiter = nil
	if succeeded then
		server.cleanup = nil
		server.root = nil
	end
	return succeeded
end

local function rejectInitialization(server: ServerData, code: string, endpoint: string, message: string): never
	local rollbackSucceeded = rollback(server)
	server.state = "Failed"
	if not rollbackSucceeded then
		fail(
			server,
			"initialization_rejected",
			"ROLLBACK_FAILED",
			UNKNOWN_ENDPOINT,
			"Network initialization failed and owned resources could not be cleaned completely"
		)
	end

	fail(server, "initialization_rejected", code, endpoint, message)
end

local function preflightRoot(server: ServerData)
	local rootCount = 0
	local hasWrongClass = false
	for _, child in server.replicatedStorage:GetChildren() do
		if child.Name == RemoteRegistry.ROOT_NAME then
			rootCount += 1
			if not child:IsA("Folder") then
				hasWrongClass = true
			end
		end
	end

	if hasWrongClass then
		server.state = "Failed"
		fail(
			server,
			"initialization_rejected",
			"ROOT_WRONG_CLASS",
			UNKNOWN_ENDPOINT,
			"The fixed network root name is occupied by an unexpected Instance class"
		)
	elseif rootCount > 0 then
		server.state = "Failed"
		fail(
			server,
			"initialization_rejected",
			"ROOT_CONFLICT",
			UNKNOWN_ENDPOINT,
			"The fixed network root is already present and cannot be adopted"
		)
	end
end

local function rejectLateRootConflict(server: ServerData)
	local rootCount = 0
	local hasWrongClass = false
	for _, child in server.replicatedStorage:GetChildren() do
		if child.Name == RemoteRegistry.ROOT_NAME then
			rootCount += 1
			if not child:IsA("Folder") then
				hasWrongClass = true
			end
		end
	end

	if hasWrongClass then
		rejectInitialization(
			server,
			"ROOT_WRONG_CLASS",
			UNKNOWN_ENDPOINT,
			"The fixed network root name became occupied by an unexpected Instance class"
		)
	elseif rootCount > 0 then
		rejectInitialization(
			server,
			"ROOT_CONFLICT",
			UNKNOWN_ENDPOINT,
			"Another owner published the fixed network root during initialization"
		)
	end
end

local function ownsUniquePublishedRoot(server: ServerData, root: Folder): boolean
	local rootCount = 0
	local foundOwnedRoot = false
	for _, child in server.replicatedStorage:GetChildren() do
		if child.Name == RemoteRegistry.ROOT_NAME then
			rootCount += 1
			foundOwnedRoot = foundOwnedRoot or child == root
		end
	end

	return rootCount == 1 and foundOwnedRoot
end

local function requireCompleteBindings(server: ServerData)
	for _, definition in server.activeDefinitions do
		if definition.direction == "ClientToServer" and server.handlers[definition.name] == nil then
			server.state = "Failed"
			fail(
				server,
				"initialization_rejected",
				"MISSING_HANDLER",
				definition.name,
				"Every active client-to-server endpoint requires exactly one handler before initialization"
			)
		end
	end
end

local function initialize(server: ServerData)
	if server.state ~= "Registering" then
		fail(
			server,
			"transition_rejected",
			"INVALID_STATE",
			UNKNOWN_ENDPOINT,
			"Network initialization requires the Registering state"
		)
	end

	server.state = "Initializing"
	preflightRoot(server)
	requireCompleteBindings(server)

	server.cleanup = Cleanup.new(server.logger, CLEANUP_LABEL)
	local rootCreated, rootValue = pcall(Instance.new, "Folder")
	if not rootCreated then
		rejectInitialization(
			server,
			"INSTANCE_CREATION_FAILED",
			UNKNOWN_ENDPOINT,
			"The fixed network Instance tree could not be created"
		)
	end

	local root = rootValue :: Folder
	server.root = root
	local ownedRoot = pcall(function()
		(server.cleanup :: Cleanup.Container):add(root)
	end)
	if not ownedRoot then
		root:Destroy()
		server.root = nil
		rejectInitialization(
			server,
			"OWNERSHIP_FAILED",
			UNKNOWN_ENDPOINT,
			"The fixed network Instance tree could not be registered for cleanup"
		)
	end

	local populated, remotesOrError = pcall(populateUnpublishedTree, root, server.activeDefinitions)
	if not populated then
		rejectInitialization(
			server,
			"INSTANCE_CREATION_FAILED",
			UNKNOWN_ENDPOINT,
			"The fixed network Instance tree could not be created"
		)
	end

	local remoteMap = remotesOrError :: RemoteMap
	local limiterDependencies = server.limiterDependencies
	local limiterCreated, limiterValue = pcall(
		ServerRateLimiter.new,
		server.logger,
		limiterDependencies.players,
		server.ratePolicySet,
		limiterDependencies.clock,
		limiterDependencies.connectPlayerRemoving,
		limiterDependencies.reporter
	)
	if not limiterCreated then
		rejectInitialization(
			server,
			"RATE_LIMITER_CREATION_FAILED",
			UNKNOWN_ENDPOINT,
			"The server rate limiter could not be created"
		)
	end

	local rateLimiter = limiterValue :: ServerRateLimiter.Limiter
	server.rateLimiter = rateLimiter
	local limiterInitialized, limiterCleanupValue = pcall(function()
		return rateLimiter:initialize()
	end)
	if not limiterInitialized then
		rejectInitialization(
			server,
			"RATE_LIMITER_INITIALIZATION_FAILED",
			UNKNOWN_ENDPOINT,
			"The server rate limiter could not initialize its owned resources"
		)
	end

	local limiterCleanup = limiterCleanupValue :: Cleanup.Container
	local limiterOwned = pcall(function()
		(server.cleanup :: Cleanup.Container):add(limiterCleanup)
	end)
	if not limiterOwned then
		pcall(function()
			limiterCleanup:cleanup()
		end)
		server.rateLimiter = nil
		rejectInitialization(
			server,
			"OWNERSHIP_FAILED",
			UNKNOWN_ENDPOINT,
			"The server rate limiter could not be registered for cleanup"
		)
	end

	for _, definition in server.activeDefinitions do
		if definition.direction == "ClientToServer" then
			local handler = server.handlers[definition.name] :: Handler
			local remote = remoteMap[definition.name]
			local connected, connection = pcall(server.connectAdapter, remote, function(player: Player, ...: unknown)
				handler(player, ...)
			end)
			if not connected then
				rejectInitialization(
					server,
					"CONNECTION_FAILED",
					definition.name,
					"The endpoint listener could not be connected"
				)
			end
			if typeof(connection) ~= "RBXScriptConnection" then
				rejectInitialization(
					server,
					"INVALID_CONNECTION",
					definition.name,
					"The endpoint connector did not return an engine connection"
				)
			end

			local connectionOwned = pcall(function()
				(server.cleanup :: Cleanup.Container):add(connection :: RBXScriptConnection)
			end)
			if not connectionOwned then
				pcall(function()
					(connection :: RBXScriptConnection):Disconnect()
				end)
				rejectInitialization(
					server,
					"OWNERSHIP_FAILED",
					definition.name,
					"The endpoint listener could not be registered for cleanup"
				)
			end
		end
	end

	-- A trusted test adapter may re-enter or yield while listeners are bound.
	-- Recheck at the no-yield publication boundary so only one owner can win.
	rejectLateRootConflict(server)
	local published = pcall(function()
		root.Parent = server.replicatedStorage
	end)
	if not published or root.Parent ~= server.replicatedStorage or not ownsUniquePublishedRoot(server, root) then
		rejectInitialization(
			server,
			"PUBLISH_CONFLICT",
			UNKNOWN_ENDPOINT,
			"The fixed network tree could not be published as the unique owned root"
		)
	end

	server.state = "Initialized"
end

local function start(server: ServerData)
	if server.state ~= "Initialized" then
		fail(
			server,
			"transition_rejected",
			"INVALID_STATE",
			UNKNOWN_ENDPOINT,
			"Network start requires the Initialized state"
		)
	end

	server.state = "Starting"
	local rateLimiter = server.rateLimiter
	if rateLimiter == nil then
		local rollbackSucceeded = rollback(server)
		server.state = "Failed"
		if not rollbackSucceeded then
			fail(
				server,
				"start_rejected",
				"ROLLBACK_FAILED",
				UNKNOWN_ENDPOINT,
				"Network start failed and owned resources could not be cleaned completely"
			)
		end
		fail(
			server,
			"start_rejected",
			"RATE_LIMITER_MISSING",
			UNKNOWN_ENDPOINT,
			"Network start requires its initialized server rate limiter"
		)
	end

	local limiterStarted = pcall(function()
		rateLimiter:start()
	end)
	if not limiterStarted then
		local rollbackSucceeded = rollback(server)
		server.state = "Failed"
		if not rollbackSucceeded then
			fail(
				server,
				"start_rejected",
				"ROLLBACK_FAILED",
				UNKNOWN_ENDPOINT,
				"Network start failed and owned resources could not be cleaned completely"
			)
		end
		fail(
			server,
			"start_rejected",
			"RATE_LIMITER_START_FAILED",
			UNKNOWN_ENDPOINT,
			"The server rate limiter could not enter its started state"
		)
	end
	server.state = "Started"
end

local function shutdown(server: ServerData)
	if server.state ~= "Started" then
		fail(
			server,
			"transition_rejected",
			"INVALID_STATE",
			UNKNOWN_ENDPOINT,
			"Network shutdown requires the Started state"
		)
	end

	server.state = "ShuttingDown"
	local cleaned = rollback(server)
	if not cleaned then
		server.state = "Failed"
		fail(
			server,
			"shutdown_failed",
			"CLEANUP_FAILED",
			UNKNOWN_ENDPOINT,
			"Network shutdown could not clean every owned resource"
		)
	end

	server.state = "Shutdown"
end

function Server.registerHandler(self: Server, endpointName: unknown, handler: unknown)
	local server = requireServer(self)
	if server.state ~= "Registering" then
		fail(
			server,
			"binding_rejected",
			"INVALID_STATE",
			endpointForLog(server, endpointName),
			"Endpoint handlers may only be registered before lifecycle initialization"
		)
	end

	local definition = if type(endpointName) == "string" then server.registry:get(endpointName) else nil
	if definition == nil then
		fail(
			server,
			"binding_rejected",
			"UNKNOWN_ENDPOINT",
			UNKNOWN_ENDPOINT,
			"Endpoint handler registration requires one fixed registry name"
		)
	end
	if server.activeDefinitionsByName[definition.name] == nil then
		fail(
			server,
			"binding_rejected",
			"INACTIVE_ENDPOINT",
			definition.name,
			"The endpoint is not active for this place role"
		)
	end
	if definition.direction ~= "ClientToServer" then
		fail(
			server,
			"binding_rejected",
			"WRONG_DIRECTION",
			definition.name,
			"Server handlers may bind only active client-to-server endpoints"
		)
	end
	if type(handler) ~= "function" then
		fail(server, "binding_rejected", "INVALID_HANDLER", definition.name, "An endpoint handler must be a function")
	end
	if server.handlers[definition.name] ~= nil then
		fail(
			server,
			"binding_rejected",
			"DUPLICATE_HANDLER",
			definition.name,
			"An endpoint may have only one server handler"
		)
	end

	server.handlers[definition.name] = handler :: Handler
end

function Server.getServiceDefinition(self: Server): ServiceLifecycle.ServiceDefinition
	local server = requireServer(self)
	return server.serviceDefinition :: ServiceLifecycle.ServiceDefinition
end

function Server.getState(self: Server): NetworkState
	return requireServer(self).state
end

function ServerRemoteRegistry.new(
	logger: Log.Logger,
	registry: RemoteRegistry.Registry,
	replicatedStorage: Instance,
	role: RemoteRegistry.RuntimePlaceRole,
	ratePolicyBindings: unknown,
	connectAdapter: ConnectAdapter?,
	limiterDependencies: LimiterDependencies?
): Server
	if not Log.isLogger(logger) then
		error(
			"[ATD][ERROR][context=unknown][role=Unresolved][placeId=unknown][environment=unknown][subsystem=network][event=construction_rejected][code=INVALID_CONTEXT][endpoint=<unknown>][networkState=Uninitialized] ServerRemoteRegistry requires a genuine context-bound Log",
			0
		)
	end
	if not RemoteRegistry.isRegistry(registry) then
		failConstruction(logger, "INVALID_REGISTRY", "ServerRemoteRegistry requires an authentic remote registry")
	end
	if typeof(replicatedStorage) ~= "Instance" or not replicatedStorage:IsA("ReplicatedStorage") then
		failConstruction(logger, "INVALID_PARENT", "ServerRemoteRegistry requires the ReplicatedStorage service")
	end
	if role ~= "Development" and role ~= "Lobby" and role ~= "Match" then
		failConstruction(logger, "INVALID_ROLE", "ServerRemoteRegistry requires Development, Lobby, or Match")
	end

	local policySetResult = ServerRateLimiter.createPolicySet(registry, role, ratePolicyBindings)
	if not policySetResult.ok then
		failConstruction(
			logger,
			policySetResult.error.code,
			"ServerRemoteRegistry rejected its fixed rate-limit policy bindings",
			policySetResult.error.path
		)
	end
	if connectAdapter ~= nil and type(connectAdapter) ~= "function" then
		failConstruction(logger, "INVALID_CONNECT_ADAPTER", "The endpoint connector must be a function or nil")
	end
	local resolvedLimiterDependencies = resolveLimiterDependencies(logger, limiterDependencies)

	local activeDefinitions = registry:listForRole(role)
	local activeDefinitionsByName: { [string]: RemoteRegistry.Definition } = {}
	for _, definition in activeDefinitions do
		activeDefinitionsByName[definition.name] = definition
	end

	local server = setmetatable({
		logger = logger,
		registry = registry,
		replicatedStorage = replicatedStorage :: ReplicatedStorage,
		role = role,
		connectAdapter = connectAdapter or defaultConnect,
		ratePolicySet = policySetResult.value,
		limiterDependencies = resolvedLimiterDependencies,
		activeDefinitions = activeDefinitions,
		activeDefinitionsByName = activeDefinitionsByName,
		handlers = {},
		state = "Registering",
		cleanup = nil,
		rateLimiter = nil,
		root = nil,
		serviceDefinition = nil,
	}, Server) :: Server

	server.serviceDefinition = table.freeze({
		name = SERVICE_NAME,
		initialize = function()
			initialize(server)
		end,
		start = function()
			start(server)
		end,
		shutdown = function()
			shutdown(server)
		end,
	})
	SERVER_REGISTRY[server] = true
	return server
end

table.freeze(Server)
return table.freeze(ServerRemoteRegistry)
