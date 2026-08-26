--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local NetworkFixtures = require(script.Parent.Parent.Fixtures.NetworkFixtures)
local ServerRemoteRegistry = require(script.Parent.Parent.ProductionServerNetworking.ServerRemoteRegistry)
local ServerRateLimiter = require(script.Parent.Parent.ProductionServerNetworking.ServerRateLimiter)
local ServerRequestDispatcher = require(script.Parent.Parent.ProductionServerNetworking.ServerRequestDispatcher)
local ClientRemoteLookup = require(script.Parent.Parent.ProductionClientNetworking.ClientRemoteLookup)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local RemoteRegistry = require(Shared.network.RemoteRegistry)
local PayloadValidation = require(Shared.network.PayloadValidation)
local EnvironmentContext = require(Shared.logging.EnvironmentContext)
local Log = require(Shared.logging.Log)

local resolveForTests = ClientRemoteLookup.resolveForTests
if resolveForTests == nil then
	error("[ATD_TEST_FIXTURE][code=CLIENT_LOOKUP_TEST_RESOLVER_MISSING]", 0)
end

type Assertions = TestHarness.Assertions
type RuntimePlaceRole = RemoteRegistry.RuntimePlaceRole
type Registry = RemoteRegistry.Registry
type Server = ServerRemoteRegistry.Server

local PRIVATE_SENTINEL = "PRIVATE_NETWORK_SENTINEL_529d"

local function makeRegistry(definitions: unknown): Registry
	local result = RemoteRegistry.create(definitions)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=REGISTRY_CREATION_FAILED]", 0)
	end
	return result.value
end

local FULL_REGISTRY = makeRegistry(NetworkFixtures.validDefinitions())
local EMPTY_REGISTRY = makeRegistry({})

local function defaultRateBindings(registry: Registry): { ServerRateLimiter.PolicyBinding }
	local bindings: { ServerRateLimiter.PolicyBinding } = {}
	for _, definition in registry:list() do
		if definition.direction == "ClientToServer" then
			table.insert(bindings, {
				endpoint = definition.name,
				policy = ServerRateLimiter.DEFAULT_POLICY,
			})
		end
	end
	return bindings
end

local FULL_RATE_BINDINGS = defaultRateBindings(FULL_REGISTRY)
local EMPTY_RATE_BINDINGS = defaultRateBindings(EMPTY_REGISTRY)
local REQUEST_SCHEMA = PayloadValidation.schema(PayloadValidation.record({
	marker = PayloadValidation.string(64, 1),
}))
local RESPONSE_SCHEMA = PayloadValidation.schema(PayloadValidation.record({
	accepted = PayloadValidation.boolean(),
}))
local TEST_LIMITER_DEPENDENCIES: ServerRemoteRegistry.LimiterDependencies = table.freeze({
	clock = function(): number
		return 0
	end,
	connectPlayerRemoving = function(_callback: ServerRateLimiter.PlayerRemovingHandler): RBXScriptConnection
		return RobloxAdapter.createConnection(function() end) :: any
	end,
})
local TEST_DISPATCHER_DEPENDENCIES: ServerRemoteRegistry.DispatcherDependencies = table.freeze({
	clock = function(): number
		return 0
	end,
	connectPlayerRemoving = function(_callback: ServerRequestDispatcher.PlayerRemovingHandler): RBXScriptConnection
		return RobloxAdapter.createConnection(function() end) :: any
	end,
	sender = function(_remote: RemoteEvent, _player: Player, _envelope: ServerRequestDispatcher.ResponseEnvelope) end,
})

local function countingChildDependencies()
	local counts = {
		limiter = 0,
		dispatcher = 0,
	}
	local limiterDependencies: ServerRemoteRegistry.LimiterDependencies = {
		clock = function(): number
			return 0
		end,
		connectPlayerRemoving = function(_callback: ServerRateLimiter.PlayerRemovingHandler): RBXScriptConnection
			return RobloxAdapter.createConnection(function()
				counts.limiter += 1
			end) :: any
		end,
	}
	local dispatcherDependencies: ServerRemoteRegistry.DispatcherDependencies = {
		clock = function(): number
			return 0
		end,
		connectPlayerRemoving = function(_callback: ServerRequestDispatcher.PlayerRemovingHandler): RBXScriptConnection
			return RobloxAdapter.createConnection(function()
				counts.dispatcher += 1
			end) :: any
		end,
		sender = function(
			_remote: RemoteEvent,
			_player: Player,
			_envelope: ServerRequestDispatcher.ResponseEnvelope
		)
		end,
	}
	return limiterDependencies, dispatcherDependencies, counts
end

local function loggerFor(role: RuntimePlaceRole): Log.Logger
	return Log.new(EnvironmentContext.new("server", role, 0, false))
end

local function captureError(assertions: Assertions, callback: () -> ()): string
	local succeeded, value = pcall(callback)
	assertions.isFalse(succeeded)
	assertions.equal(type(value), "string")
	return if type(value) == "string" then value else ""
end

local function assertCode(assertions: Assertions, errorValue: string, code: string)
	assertions.contains(errorValue, `[code={code}]`)
end

local function assertLookupCode(assertions: Assertions, result: ClientRemoteLookup.LookupResult, code: string)
	assertions.isFalse(result.ok)
	if not result.ok then
		assertions.equal(result.error.code, code)
		assertions.isTrue(table.isfrozen(result))
		assertions.isTrue(table.isfrozen(result.error))
	end
end

local function child(assertions: Assertions, parent: Instance, name: string, className: string): Instance
	local instance = parent:FindFirstChild(name)
	assertions.isNotNil(instance)
	if instance == nil then
		error("[ATD_TEST_FIXTURE][code=EXPECTED_CHILD_MISSING]", 0)
	end
	assertions.equal(instance.ClassName, className)
	return instance
end

local function bindActiveHandlers(server: Server, role: RuntimePlaceRole, callback: ServerRemoteRegistry.Handler?)
	for _, definition in FULL_REGISTRY:listForRole(role) do
		if definition.direction == "ClientToServer" then
			local selectedHandler: ServerRemoteRegistry.Handler = callback
				or function(_context, _payload)
					return ServerRequestDispatcher.success(
						if definition.response == "Required" then { accepted = true } else nil
					)
				end
			local function authorize(_context: ServerRequestDispatcher.ServerContext): boolean
				return true
			end
			if definition.kind == "Request" then
				server:registerRequest(
					definition.name,
					REQUEST_SCHEMA,
					if definition.response == "Required" then RESPONSE_SCHEMA else nil,
					authorize,
					selectedHandler
				)
			else
				server:registerEvent(definition.name, REQUEST_SCHEMA, authorize, selectedHandler)
			end
		end
	end
end

local function fakeConnector(
	disconnectCallback: ((RemoteEvent) -> ())?,
	connectCallback: ((RemoteEvent, ServerRemoteRegistry.Listener) -> ())?
): ServerRemoteRegistry.ConnectAdapter
	return function(remote: RemoteEvent, handler: ServerRemoteRegistry.Listener): RBXScriptConnection
		if connectCallback ~= nil then
			connectCallback(remote, handler)
		end
		return RobloxAdapter.createConnection(function()
			if disconnectCallback ~= nil then
				disconnectCallback(remote)
			end
		end) :: any
	end
end

local function initialize(server: Server)
	local lifecycle = server:getServiceDefinition()
	if lifecycle.initialize == nil then
		error("[ATD_TEST_FIXTURE][code=INITIALIZE_MISSING]", 0)
	end
	lifecycle.initialize()
end

local function start(server: Server)
	local lifecycle = server:getServiceDefinition()
	if lifecycle.start == nil then
		error("[ATD_TEST_FIXTURE][code=START_MISSING]", 0)
	end
	lifecycle.start()
end

local function shutdown(server: Server)
	local lifecycle = server:getServiceDefinition()
	if lifecycle.shutdown == nil then
		error("[ATD_TEST_FIXTURE][code=SHUTDOWN_MISSING]", 0)
	end
	lifecycle.shutdown()
end

local function assertNoPublishedRoot(assertions: Assertions)
	assertions.isNil(ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME))
end

return TestHarness.suite("fixed remote runtime and client lookup", {
	TestHarness.case(
		"publishes the exact Match tree only after binding and disconnects before destruction",
		function(assertions)
			assertNoPublishedRoot(assertions)
			local connectedNames = {}
			local disconnectedNames = {}
			local cleanupOrder = {}
			local publishedDuringConnect = false
			local rootMissingDuringDisconnect = false
			local callbacks: { [string]: ServerRemoteRegistry.Listener } = {}
			local handledCount = 0
			local handledPlayer: Player? = nil
			local sentRemote: RemoteEvent? = nil
			local sentPlayer: Player? = nil
			local sentEnvelope: ServerRequestDispatcher.ResponseEnvelope? = nil

			local server = ServerRemoteRegistry.new(
				loggerFor("Match"),
				FULL_REGISTRY,
				ReplicatedStorage,
				"Match",
				FULL_RATE_BINDINGS,
				fakeConnector(function(remote)
					table.insert(disconnectedNames, remote.Parent.Name)
					table.insert(cleanupOrder, `Remote:{remote.Parent.Name}`)
					if ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME) == nil then
						rootMissingDuringDisconnect = true
					end
				end, function(remote, handler)
					table.insert(connectedNames, remote.Parent.Name)
					callbacks[remote.Parent.Name] = handler
					local root = remote.Parent.Parent.Parent
					if root.Parent ~= nil or ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME) ~= nil then
						publishedDuringConnect = true
					end
				end),
				{
					clock = function(): number
						return 0
					end,
					connectPlayerRemoving = function(
						_callback: ServerRateLimiter.PlayerRemovingHandler
					): RBXScriptConnection
						return RobloxAdapter.createConnection(function()
							table.insert(cleanupOrder, "LimiterPlayerRemoving")
							if ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME) == nil then
								rootMissingDuringDisconnect = true
							end
						end) :: any
					end,
				},
				{
					clock = function(): number
						return 0
					end,
					connectPlayerRemoving = function(
						_callback: ServerRequestDispatcher.PlayerRemovingHandler
					): RBXScriptConnection
						return RobloxAdapter.createConnection(function()
							table.insert(cleanupOrder, "DispatcherPlayerRemoving")
							if ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME) == nil then
								rootMissingDuringDisconnect = true
							end
						end) :: any
					end,
					sender = function(
						remote: RemoteEvent,
						player: Player,
						envelope: ServerRequestDispatcher.ResponseEnvelope
					)
						sentRemote = remote
						sentPlayer = player
						sentEnvelope = envelope
					end,
				}
			)
			bindActiveHandlers(server, "Match", function(context: ServerRequestDispatcher.ServerContext, _payload)
				handledCount += 1
				handledPlayer = context.player
				return ServerRequestDispatcher.success(
					if context.definition.response == "Required" then { accepted = true } else nil
				)
			end)

			local service = server:getServiceDefinition()
			assertions.equal(service.name, "NetworkRegistry")
			assertions.isTrue(table.isfrozen(service))
			assertions.equal(server:getServiceDefinition(), service)
			initialize(server)
			assertions.equal(server:getState(), "Initialized")
			assertions.isFalse(publishedDuringConnect)
			assertions.equal(
				table.concat(connectedNames, ","),
				"TestClientEvent,TestNoResponseRequest,TestResponseRequest"
			)

			local root = child(assertions, ReplicatedStorage, RemoteRegistry.ROOT_NAME, "Folder")
			assertions.equal(#root:GetChildren(), 1)
			local version = child(assertions, root, RemoteRegistry.VERSION_NAME, "Folder")
			assertions.equal(#version:GetChildren(), 3)
			assertions.isNil(version:FindFirstChild("TestServerEvent"))

			local clientEvent = child(assertions, version, "TestClientEvent", "Folder")
			assertions.equal(#clientEvent:GetChildren(), 1)
			child(assertions, clientEvent, "Event", "RemoteEvent")
			local noResponse = child(assertions, version, "TestNoResponseRequest", "Folder")
			assertions.equal(#noResponse:GetChildren(), 1)
			child(assertions, noResponse, "Request", "RemoteEvent")
			local response = child(assertions, version, "TestResponseRequest", "Folder")
			assertions.equal(#response:GetChildren(), 2)
			child(assertions, response, "Request", "RemoteEvent")
			child(assertions, response, "Response", "RemoteEvent")

			start(server)
			assertions.equal(server:getState(), "Started")
			local player = Instance.new("Player")
			player.Parent = game:GetService("Players")
			local clientEventCallback = callbacks.TestClientEvent
			clientEventCallback(player, { payload = { marker = PRIVATE_SENTINEL } })
			assertions.equal(handledCount, 1)
			assertions.equal(handledPlayer, player)

			local responseCallback = callbacks.TestResponseRequest
			responseCallback(player, {
				requestId = "runtime001",
				payload = { marker = "fixed" },
			})
			assertions.equal(handledCount, 2)
			assertions.equal(sentPlayer, player)
			assertions.equal(sentRemote, response:FindFirstChild("Response"))
			assertions.isNotNil(sentEnvelope)
			if sentEnvelope ~= nil then
				assertions.equal(sentEnvelope.requestId, "runtime001")
				assertions.equal(sentEnvelope.state, "Success")
				assertions.isTrue(table.isfrozen(sentEnvelope))
				if sentEnvelope.state == "Success" then
					assertions.equal((sentEnvelope.payload :: any).accepted, true)
				end
			end
			player:Destroy()
			shutdown(server)
			assertions.equal(server:getState(), "Shutdown")
			assertions.equal(#disconnectedNames, 3)
			assertions.equal(
				table.concat(cleanupOrder, ","),
				"Remote:TestResponseRequest,Remote:TestNoResponseRequest,Remote:TestClientEvent,DispatcherPlayerRemoving,LimiterPlayerRemoving"
			)
			assertions.isFalse(rootMissingDuringDisconnect)
			assertNoPublishedRoot(assertions)
		end
	),

	TestHarness.case("keeps Lobby Match and Development endpoint sets isolated", function(assertions)
		assertNoPublishedRoot(assertions)
		local expectations = {
			Lobby = "TestResponseRequest,TestServerEvent",
			Match = "TestClientEvent,TestNoResponseRequest,TestResponseRequest",
			Development = "TestClientEvent,TestNoResponseRequest,TestResponseRequest,TestServerEvent",
		}

		for _, role in { "Lobby", "Match", "Development" } :: { RuntimePlaceRole } do
			local server = ServerRemoteRegistry.new(
				loggerFor(role),
				FULL_REGISTRY,
				ReplicatedStorage,
				role,
				FULL_RATE_BINDINGS,
				fakeConnector(nil, nil),
				TEST_LIMITER_DEPENDENCIES,
				TEST_DISPATCHER_DEPENDENCIES
			)
			bindActiveHandlers(server, role)
			initialize(server)

			local root = child(assertions, ReplicatedStorage, RemoteRegistry.ROOT_NAME, "Folder")
			local version = child(assertions, root, RemoteRegistry.VERSION_NAME, "Folder")
			local names = {}
			for _, endpoint in version:GetChildren() do
				table.insert(names, endpoint.Name)
			end
			table.sort(names)
			assertions.equal(table.concat(names, ","), expectations[role])

			start(server)
			shutdown(server)
			assertNoPublishedRoot(assertions)
		end
	end),

	TestHarness.case(
		"rejects unknown inactive wrong-direction invalid and duplicate bindings privately",
		function(assertions)
			assertNoPublishedRoot(assertions)
			local invalidRatePolicies = captureError(assertions, function()
				ServerRemoteRegistry.new(loggerFor("Lobby"), FULL_REGISTRY, ReplicatedStorage, "Lobby", {
					{
						endpoint = PRIVATE_SENTINEL .. "/arbitrary/path",
						policy = ServerRateLimiter.DEFAULT_POLICY,
					},
				})
			end)
			assertCode(assertions, invalidRatePolicies, "UNKNOWN_ENDPOINT")
			assertions.contains(invalidRatePolicies, "[validationPath=policies[1].endpoint]")
			assertions.isNil(string.find(invalidRatePolicies, PRIVATE_SENTINEL, 1, true))

			local server = ServerRemoteRegistry.new(
				loggerFor("Lobby"),
				FULL_REGISTRY,
				ReplicatedStorage,
				"Lobby",
				FULL_RATE_BINDINGS,
				fakeConnector(nil, nil),
				TEST_LIMITER_DEPENDENCIES,
				TEST_DISPATCHER_DEPENDENCIES
			)
			local function authorize(_context: ServerRequestDispatcher.ServerContext): boolean
				return true
			end
			local function handleResponse(_context: ServerRequestDispatcher.ServerContext, _payload)
				return ServerRequestDispatcher.success({ accepted = true })
			end

			local unknown = captureError(assertions, function()
				server:registerRequest(
					PRIVATE_SENTINEL .. "/arbitrary/path",
					REQUEST_SCHEMA,
					RESPONSE_SCHEMA,
					authorize,
					handleResponse
				)
			end)
			assertCode(assertions, unknown, "UNKNOWN_ENDPOINT")
			assertions.contains(unknown, "[endpoint=<unknown>]")
			assertions.isNil(string.find(unknown, PRIVATE_SENTINEL, 1, true))

			local inactive = captureError(assertions, function()
				server:registerEvent("TestClientEvent", REQUEST_SCHEMA, authorize, handleResponse)
			end)
			assertCode(assertions, inactive, "INACTIVE_ENDPOINT")
			assertions.contains(inactive, "[endpoint=TestClientEvent]")

			local wrongDirection = captureError(assertions, function()
				server:registerEvent("TestServerEvent", REQUEST_SCHEMA, authorize, handleResponse)
			end)
			assertCode(assertions, wrongDirection, "WRONG_DIRECTION")

			local invalidHandler = captureError(assertions, function()
				server:registerRequest(
					"TestResponseRequest",
					REQUEST_SCHEMA,
					RESPONSE_SCHEMA,
					authorize,
					{ private = PRIVATE_SENTINEL } :: any
				)
			end)
			assertCode(assertions, invalidHandler, "INVALID_HANDLER")
			assertions.isNil(string.find(invalidHandler, PRIVATE_SENTINEL, 1, true))

			server:registerRequest("TestResponseRequest", REQUEST_SCHEMA, RESPONSE_SCHEMA, authorize, handleResponse)
			local duplicate = captureError(assertions, function()
				server:registerRequest(
					"TestResponseRequest",
					REQUEST_SCHEMA,
					RESPONSE_SCHEMA,
					authorize,
					handleResponse
				)
			end)
			assertCode(assertions, duplicate, "DUPLICATE_CONTRACT")
			assertNoPublishedRoot(assertions)
		end
	),

	TestHarness.case("fails closed on missing contracts and rolls back a partial listener bind", function(assertions)
		assertNoPublishedRoot(assertions)
		local missingServer = ServerRemoteRegistry.new(
			loggerFor("Match"),
			FULL_REGISTRY,
			ReplicatedStorage,
			"Match",
			FULL_RATE_BINDINGS,
			fakeConnector(nil, nil),
			TEST_LIMITER_DEPENDENCIES,
			TEST_DISPATCHER_DEPENDENCIES
		)
		local missing = captureError(assertions, function()
			initialize(missingServer)
		end)
		assertCode(assertions, missing, "MISSING_CONTRACT")
		assertions.contains(missing, "[endpoint=TestClientEvent]")
		assertions.equal(missingServer:getState(), "Failed")
		assertNoPublishedRoot(assertions)

		local connectionAttempts = 0
		local disconnectCount = 0
		local rollbackLimiterDependencies, rollbackDispatcherDependencies, rollbackChildDisconnects =
			countingChildDependencies()
		local rollbackServer = ServerRemoteRegistry.new(
			loggerFor("Match"),
			FULL_REGISTRY,
			ReplicatedStorage,
			"Match",
			FULL_RATE_BINDINGS,
			function(_remote: RemoteEvent, _handler: ServerRemoteRegistry.Listener): RBXScriptConnection
				connectionAttempts += 1
				if connectionAttempts == 2 then
					error(PRIVATE_SENTINEL, 0)
				end
				return RobloxAdapter.createConnection(function()
					disconnectCount += 1
				end) :: any
			end,
			rollbackLimiterDependencies,
			rollbackDispatcherDependencies
		)
		bindActiveHandlers(rollbackServer, "Match")
		local connectionFailure = captureError(assertions, function()
			initialize(rollbackServer)
		end)
		assertCode(assertions, connectionFailure, "CONNECTION_FAILED")
		assertions.isNil(string.find(connectionFailure, PRIVATE_SENTINEL, 1, true))
		assertions.equal(connectionAttempts, 2)
		assertions.equal(disconnectCount, 1)
		assertions.equal(rollbackChildDisconnects.dispatcher, 1)
		assertions.equal(rollbackChildDisconnects.limiter, 1)
		assertions.equal(rollbackServer:getState(), "Failed")
		assertNoPublishedRoot(assertions)

		local invalidLimiterDependencies, invalidDispatcherDependencies, invalidChildDisconnects =
			countingChildDependencies()
		local invalidConnectionServer = ServerRemoteRegistry.new(
			loggerFor("Match"),
			FULL_REGISTRY,
			ReplicatedStorage,
			"Match",
			FULL_RATE_BINDINGS,
			function(_remote: RemoteEvent, _handler: ServerRemoteRegistry.Listener): RBXScriptConnection
				return { Disconnect = function() end } :: any
			end,
			invalidLimiterDependencies,
			invalidDispatcherDependencies
		)
		bindActiveHandlers(invalidConnectionServer, "Match")
		local invalidConnection = captureError(assertions, function()
			initialize(invalidConnectionServer)
		end)
		assertCode(assertions, invalidConnection, "INVALID_CONNECTION")
		assertions.equal(invalidChildDisconnects.dispatcher, 1)
		assertions.equal(invalidChildDisconnects.limiter, 1)
		assertions.equal(invalidConnectionServer:getState(), "Failed")
		assertNoPublishedRoot(assertions)

		local dispatcherFailureLimiterDisconnects = 0
		local dispatcherFailureAttempts = 0
		local endpointConnectionAttempts = 0
		local dispatcherFailureServer = ServerRemoteRegistry.new(
			loggerFor("Match"),
			FULL_REGISTRY,
			ReplicatedStorage,
			"Match",
			FULL_RATE_BINDINGS,
			function(_remote: RemoteEvent, _handler: ServerRemoteRegistry.Listener): RBXScriptConnection
				endpointConnectionAttempts += 1
				return RobloxAdapter.createConnection(function() end) :: any
			end,
			{
				clock = function(): number
					return 0
				end,
				connectPlayerRemoving = function(
					_callback: ServerRateLimiter.PlayerRemovingHandler
				): RBXScriptConnection
					return RobloxAdapter.createConnection(function()
						dispatcherFailureLimiterDisconnects += 1
					end) :: any
				end,
			},
			{
				clock = function(): number
					return 0
				end,
				connectPlayerRemoving = function(
					_callback: ServerRequestDispatcher.PlayerRemovingHandler
				): RBXScriptConnection
					dispatcherFailureAttempts += 1
					error(PRIVATE_SENTINEL, 0)
				end,
				sender = function(
					_remote: RemoteEvent,
					_player: Player,
					_envelope: ServerRequestDispatcher.ResponseEnvelope
				)
				end,
			}
		)
		bindActiveHandlers(dispatcherFailureServer, "Match")
		local dispatcherFailure = captureError(assertions, function()
			initialize(dispatcherFailureServer)
		end)
		assertCode(assertions, dispatcherFailure, "DISPATCHER_INITIALIZATION_FAILED")
		assertions.isNil(string.find(dispatcherFailure, PRIVATE_SENTINEL, 1, true))
		assertions.equal(dispatcherFailureLimiterDisconnects, 1)
		assertions.equal(dispatcherFailureAttempts, 1)
		assertions.equal(endpointConnectionAttempts, 0)
		assertions.equal(dispatcherFailureServer:getState(), "Failed")
		assertNoPublishedRoot(assertions)
	end),

	TestHarness.case("preserves pre-existing root conflicts and distinguishes their classes", function(assertions)
		assertNoPublishedRoot(assertions)
		local existingFolder = Instance.new("Folder")
		existingFolder.Name = RemoteRegistry.ROOT_NAME
		existingFolder.Parent = ReplicatedStorage
		local folderServer = ServerRemoteRegistry.new(
			loggerFor("Lobby"),
			EMPTY_REGISTRY,
			ReplicatedStorage,
			"Lobby",
			EMPTY_RATE_BINDINGS,
			nil,
			TEST_LIMITER_DEPENDENCIES,
			TEST_DISPATCHER_DEPENDENCIES
		)
		local folderConflict = captureError(assertions, function()
			initialize(folderServer)
		end)
		assertCode(assertions, folderConflict, "ROOT_CONFLICT")
		assertions.equal(existingFolder.Parent, ReplicatedStorage)
		existingFolder:Destroy()

		local existingModel = Instance.new("Model")
		existingModel.Name = RemoteRegistry.ROOT_NAME
		existingModel.Parent = ReplicatedStorage
		local modelServer = ServerRemoteRegistry.new(
			loggerFor("Lobby"),
			EMPTY_REGISTRY,
			ReplicatedStorage,
			"Lobby",
			EMPTY_RATE_BINDINGS,
			nil,
			TEST_LIMITER_DEPENDENCIES,
			TEST_DISPATCHER_DEPENDENCIES
		)
		local classConflict = captureError(assertions, function()
			initialize(modelServer)
		end)
		assertCode(assertions, classConflict, "ROOT_WRONG_CLASS")
		assertions.equal(existingModel.Parent, ReplicatedStorage)
		existingModel:Destroy()
		assertNoPublishedRoot(assertions)
	end),

	TestHarness.case("allows only one owner when listener binding re-enters initialization", function(assertions)
		assertNoPublishedRoot(assertions)
		local winner = ServerRemoteRegistry.new(
			loggerFor("Match"),
			FULL_REGISTRY,
			ReplicatedStorage,
			"Match",
			FULL_RATE_BINDINGS,
			fakeConnector(nil, nil),
			TEST_LIMITER_DEPENDENCIES,
			TEST_DISPATCHER_DEPENDENCIES
		)
		bindActiveHandlers(winner, "Match")

		local reentered = false
		local loserDisconnectCount = 0
		local loser = ServerRemoteRegistry.new(
			loggerFor("Match"),
			FULL_REGISTRY,
			ReplicatedStorage,
			"Match",
			FULL_RATE_BINDINGS,
			function(_remote: RemoteEvent, _handler: ServerRemoteRegistry.Listener): RBXScriptConnection
				if not reentered then
					reentered = true
					initialize(winner)
				end
				return RobloxAdapter.createConnection(function()
					loserDisconnectCount += 1
				end) :: any
			end,
			TEST_LIMITER_DEPENDENCIES,
			TEST_DISPATCHER_DEPENDENCIES
		)
		bindActiveHandlers(loser, "Match")

		local rejection = captureError(assertions, function()
			initialize(loser)
		end)
		assertCode(assertions, rejection, "ROOT_CONFLICT")
		assertions.isTrue(reentered)
		assertions.equal(winner:getState(), "Initialized")
		assertions.equal(loser:getState(), "Failed")
		assertions.equal(loserDisconnectCount, 3)
		local ownedRoot = ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME)
		assertions.isNotNil(ownedRoot)

		start(winner)
		shutdown(winner)
		assertNoPublishedRoot(assertions)
	end),

	TestHarness.case("rejects lifecycle and contract re-entry without duplicating ownership", function(assertions)
		assertNoPublishedRoot(assertions)
		local server = ServerRemoteRegistry.new(
			loggerFor("Development"),
			EMPTY_REGISTRY,
			ReplicatedStorage,
			"Development",
			EMPTY_RATE_BINDINGS,
			nil,
			TEST_LIMITER_DEPENDENCIES,
			TEST_DISPATCHER_DEPENDENCIES
		)
		initialize(server)
		local root = ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME)
		assertions.isNotNil(root)

		local initializeAgain = captureError(assertions, function()
			initialize(server)
		end)
		assertCode(assertions, initializeAgain, "INVALID_STATE")
		local lateBinding = captureError(assertions, function()
			server:registerRequest("Anything", nil, nil, nil, nil)
		end)
		assertCode(assertions, lateBinding, "INVALID_STATE")
		assertions.equal(ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME), root)

		start(server)
		local startAgain = captureError(assertions, function()
			start(server)
		end)
		assertCode(assertions, startAgain, "INVALID_STATE")
		shutdown(server)
		local shutdownAgain = captureError(assertions, function()
			shutdown(server)
		end)
		assertCode(assertions, shutdownAgain, "INVALID_STATE")
		assertNoPublishedRoot(assertions)
	end),

	TestHarness.case("resolves only fixed active leaves through one decreasing total deadline", function(assertions)
		assertNoPublishedRoot(assertions)
		local server = ServerRemoteRegistry.new(
			loggerFor("Match"),
			FULL_REGISTRY,
			ReplicatedStorage,
			"Match",
			FULL_RATE_BINDINGS,
			fakeConnector(nil, nil),
			TEST_LIMITER_DEPENDENCIES,
			TEST_DISPATCHER_DEPENDENCIES
		)
		bindActiveHandlers(server, "Match")
		initialize(server)

		local now = 10
		local waits = {}
		local remainingValues = {}
		local result = resolveForTests(FULL_REGISTRY, ReplicatedStorage, "Match", "TestResponseRequest", 1, function()
			return now
		end, function(parent: Instance, childName: string, remaining: number): Instance?
			table.insert(waits, `{parent.Name}/{childName}`)
			table.insert(remainingValues, remaining)
			now += 0.05
			return parent:FindFirstChild(childName)
		end)
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.equal(result.value.name, "TestResponseRequest")
			assertions.isNotNil(result.value.request)
			assertions.isNotNil(result.value.response)
			assertions.isNil(result.value.event)
			assertions.equal((result.value.request :: RemoteEvent).ClassName, "RemoteEvent")
			assertions.equal((result.value.response :: RemoteEvent).ClassName, "RemoteEvent")
			assertions.isTrue(table.isfrozen(result))
			assertions.isTrue(table.isfrozen(result.value))
		end
		assertions.equal(
			table.concat(waits, ","),
			"ReplicatedStorage/ATDNetwork,ATDNetwork/v1,v1/TestResponseRequest,TestResponseRequest/Request,TestResponseRequest/Response"
		)
		assertions.equal(#remainingValues, 5)
		for index = 2, #remainingValues do
			assertions.isTrue(remainingValues[index] < remainingValues[index - 1])
		end

		start(server)
		shutdown(server)
		assertNoPublishedRoot(assertions)
	end),

	TestHarness.case("resolves event and no-response request leaves without fabricating siblings", function(assertions)
		assertNoPublishedRoot(assertions)
		local server = ServerRemoteRegistry.new(
			loggerFor("Match"),
			FULL_REGISTRY,
			ReplicatedStorage,
			"Match",
			FULL_RATE_BINDINGS,
			fakeConnector(nil, nil),
			TEST_LIMITER_DEPENDENCIES,
			TEST_DISPATCHER_DEPENDENCIES
		)
		bindActiveHandlers(server, "Match")
		initialize(server)

		local cases = {
			{ name = "TestClientEvent", expectedLeaf = "event" },
			{ name = "TestNoResponseRequest", expectedLeaf = "request" },
		}
		for _, fixture in cases do
			local result = resolveForTests(FULL_REGISTRY, ReplicatedStorage, "Match", fixture.name, 1, function()
				return 0
			end, function(parent: Instance, childName: string, _remaining: number): Instance?
				return parent:FindFirstChild(childName)
			end)
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.equal(result.value.name, fixture.name)
				assertions.equal(result.value.event ~= nil, fixture.expectedLeaf == "event")
				assertions.equal(result.value.request ~= nil, fixture.expectedLeaf == "request")
				assertions.isNil(result.value.response)
			end
		end

		start(server)
		shutdown(server)
		assertNoPublishedRoot(assertions)
	end),

	TestHarness.case("keeps dependency injection absent from a production-located module", function(assertions)
		local sourceModule = script.Parent.Parent.ProductionClientNetworking.ClientRemoteLookup
		local productionLocatedClone = sourceModule:Clone()
		productionLocatedClone.Name = "ClientRemoteLookupProductionLocationProbe"
		productionLocatedClone.Parent = ReplicatedStorage

		local loaded = require(productionLocatedClone) :: any
		assertions.equal(type(loaded.resolve), "function")
		assertions.isNil(loaded.resolveForTests)
		assertions.isTrue(table.isfrozen(loaded))
		productionLocatedClone:Destroy()
	end),

	TestHarness.case(
		"rejects arbitrary inactive malformed and counterfeit lookups without creating Instances",
		function(assertions)
			assertNoPublishedRoot(assertions)
			local waitCount = 0
			local function clock(): number
				return 0
			end
			local function waitAdapter(_parent: Instance, _name: string, _remaining: number): Instance?
				waitCount += 1
				return nil
			end

			local unknown = resolveForTests(
				FULL_REGISTRY,
				ReplicatedStorage,
				"Lobby",
				PRIVATE_SENTINEL .. "/arbitrary/path",
				1,
				clock,
				waitAdapter
			)
			assertLookupCode(assertions, unknown, "UNKNOWN_ENDPOINT")
			if not unknown.ok then
				assertions.isNil(string.find(unknown.error.message, PRIVATE_SENTINEL, 1, true))
			end

			local inactive =
				resolveForTests(FULL_REGISTRY, ReplicatedStorage, "Lobby", "TestClientEvent", 1, clock, waitAdapter)
			assertLookupCode(assertions, inactive, "INACTIVE_ENDPOINT")
			local invalidTimeout =
				resolveForTests(FULL_REGISTRY, ReplicatedStorage, "Lobby", "TestServerEvent", 6, clock, waitAdapter)
			assertLookupCode(assertions, invalidTimeout, "INVALID_TIMEOUT")
			local invalidParentInstance = Instance.new("Folder")
			local invalidParent =
				resolveForTests(FULL_REGISTRY, invalidParentInstance, "Lobby", "TestServerEvent", 1, clock, waitAdapter)
			assertLookupCode(assertions, invalidParent, "INVALID_PARENT")
			invalidParentInstance:Destroy()
			local counterfeit =
				resolveForTests({} :: any, ReplicatedStorage, "Lobby", "TestServerEvent", 1, clock, waitAdapter)
			assertLookupCode(assertions, counterfeit, "INVALID_REGISTRY")
			assertions.equal(waitCount, 0)

			local invalidRole = resolveForTests(
				FULL_REGISTRY,
				ReplicatedStorage,
				"Other" :: any,
				"TestServerEvent",
				1,
				clock,
				waitAdapter
			)
			assertLookupCode(assertions, invalidRole, "INVALID_ROLE")
			local invalidClock =
				resolveForTests(FULL_REGISTRY, ReplicatedStorage, "Lobby", "TestServerEvent", 1, {} :: any, waitAdapter)
			assertLookupCode(assertions, invalidClock, "INVALID_CLOCK")
			local invalidWait =
				resolveForTests(FULL_REGISTRY, ReplicatedStorage, "Lobby", "TestServerEvent", 1, clock, {} :: any)
			assertLookupCode(assertions, invalidWait, "INVALID_WAIT_ADAPTER")
			assertions.equal(waitCount, 0)

			local failedWait = resolveForTests(
				FULL_REGISTRY,
				ReplicatedStorage,
				"Lobby",
				"TestServerEvent",
				1,
				clock,
				function(_parent: Instance, _name: string, _remaining: number): Instance?
					error(PRIVATE_SENTINEL, 0)
				end
			)
			assertLookupCode(assertions, failedWait, "LOOKUP_FAILED")
			if not failedWait.ok then
				assertions.isNil(string.find(failedWait.error.message, PRIVATE_SENTINEL, 1, true))
			end

			local unrelatedRoot = Instance.new("Folder")
			unrelatedRoot.Name = RemoteRegistry.ROOT_NAME
			local unrelated = resolveForTests(
				FULL_REGISTRY,
				ReplicatedStorage,
				"Lobby",
				"TestServerEvent",
				1,
				clock,
				function(_parent: Instance, _name: string, _remaining: number): Instance?
					return unrelatedRoot
				end
			)
			assertLookupCode(assertions, unrelated, "UNEXPECTED_INSTANCE")
			unrelatedRoot:Destroy()
			assertNoPublishedRoot(assertions)
		end
	),

	TestHarness.case("fails on wrong classes clock anomalies and elapsed total deadlines", function(assertions)
		assertNoPublishedRoot(assertions)
		local root = Instance.new("Folder")
		root.Name = RemoteRegistry.ROOT_NAME
		local version = Instance.new("Folder")
		version.Name = RemoteRegistry.VERSION_NAME
		version.Parent = root
		local endpoint = Instance.new("Folder")
		endpoint.Name = "TestResponseRequest"
		endpoint.Parent = version
		local wrongRequest = Instance.new("Folder")
		wrongRequest.Name = "Request"
		wrongRequest.Parent = endpoint
		root.Parent = ReplicatedStorage

		local wrongClass = resolveForTests(
			FULL_REGISTRY,
			ReplicatedStorage,
			"Lobby",
			"TestResponseRequest",
			1,
			function()
				return 0
			end,
			function(parent: Instance, name: string, _remaining: number): Instance?
				return parent:FindFirstChild(name)
			end
		)
		assertLookupCode(assertions, wrongClass, "WRONG_CLASS")
		if not wrongClass.ok then
			assertions.equal(wrongClass.error.path, "ATDNetwork.v1.TestResponseRequest.Request")
		end
		assertions.isNil(endpoint:FindFirstChild("Response"))
		root:Destroy()

		local clockReads = 0
		local backwards = resolveForTests(FULL_REGISTRY, ReplicatedStorage, "Lobby", "TestServerEvent", 1, function()
			clockReads += 1
			return if clockReads == 1 then 1 else 0
		end, function(_parent: Instance, _name: string, _remaining: number): Instance?
			error(PRIVATE_SENTINEL, 0)
		end)
		assertLookupCode(assertions, backwards, "CLOCK_ANOMALY")

		local deadlineRoot = Instance.new("Folder")
		deadlineRoot.Name = RemoteRegistry.ROOT_NAME
		local deadlineVersion = Instance.new("Folder")
		deadlineVersion.Name = RemoteRegistry.VERSION_NAME
		deadlineVersion.Parent = deadlineRoot
		deadlineRoot.Parent = ReplicatedStorage
		local now = 0
		local remainingValues = {}
		local elapsed = resolveForTests(FULL_REGISTRY, ReplicatedStorage, "Lobby", "TestServerEvent", 1, function()
			return now
		end, function(parent: Instance, name: string, remaining: number): Instance?
			table.insert(remainingValues, remaining)
			if #remainingValues == 1 then
				now = 0.6
			else
				now = 1.01
			end
			return parent:FindFirstChild(name)
		end)
		assertLookupCode(assertions, elapsed, "LOOKUP_TIMEOUT")
		assertions.equal(#remainingValues, 2)
		assertions.isTrue(remainingValues[2] < remainingValues[1])
		assertions.isNil(deadlineVersion:FindFirstChild("TestServerEvent"))
		deadlineRoot:Destroy()
		assertNoPublishedRoot(assertions)
	end),
})
