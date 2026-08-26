--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local NetworkFixtures = require(script.Parent.Parent.Fixtures.NetworkFixtures)
local ServerRemoteRegistry = require(script.Parent.Parent.ProductionServerNetworking.ServerRemoteRegistry)
local ServerRateLimiter = require(script.Parent.Parent.ProductionServerNetworking.ServerRateLimiter)
local ServerRequestDispatcher = require(script.Parent.Parent.ProductionServerNetworking.ServerRequestDispatcher)
local ClientRemoteLookup = require(script.Parent.Parent.ProductionClientNetworking.ClientRemoteLookup)
local ClientRequestTracker = require(script.Parent.Parent.ProductionClientNetworking.ClientRequestTracker)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local EnvironmentContext = require(Shared.logging.EnvironmentContext)
local Log = require(Shared.logging.Log)
local PayloadValidation = require(Shared.network.PayloadValidation)
local RemoteRegistry = require(Shared.network.RemoteRegistry)
local RequestProtocol = require(Shared.network.RequestProtocol)

type Assertions = TestHarness.Assertions
type Registry = RemoteRegistry.Registry
type RuntimePlaceRole = RemoteRegistry.RuntimePlaceRole
type ServerContext = ServerRequestDispatcher.ServerContext
type HandlerOutcome = ServerRequestDispatcher.HandlerOutcome

local PRIVATE_SENTINEL = "PRIVATE_NETWORK_SECURITY_SENTINEL_91af"
local UNKNOWN_PATH = PRIVATE_SENTINEL .. "/../../ServerStorage/Private"
local playerSequence = 0

local resolveForTests = ClientRemoteLookup.resolveForTests
if resolveForTests == nil then
	error("[ATD_TEST_FIXTURE][code=CLIENT_LOOKUP_TEST_RESOLVER_MISSING]", 0)
end

local newTrackerForTests = ClientRequestTracker.newForTests
if newTrackerForTests == nil then
	error("[ATD_TEST_FIXTURE][code=CLIENT_TRACKER_TEST_CONSTRUCTOR_MISSING]", 0)
end

local function makeRegistry(): Registry
	local result = RemoteRegistry.create(NetworkFixtures.validDefinitions())
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=SECURITY_REGISTRY_CREATION_FAILED]", 0)
	end
	return result.value
end

local REGISTRY = makeRegistry()

local function nestedRecord(depth: number): PayloadValidation.Validator
	local validator = PayloadValidation.string(8, 1)
	for _ = 1, depth do
		validator = PayloadValidation.record({ child = validator })
	end
	return validator
end

local CHILD_VALIDATOR = PayloadValidation.record({
	value = PayloadValidation.string(16, 1),
})
local RICH_PAYLOAD_VALIDATOR = PayloadValidation.record({
	amount = PayloadValidation.number(-100, 100),
	items = PayloadValidation.array(PayloadValidation.record({ label = PayloadValidation.string(16, 1) }), 4),
	left = PayloadValidation.optional(CHILD_VALIDATOR),
	mapId = PayloadValidation.id("map"),
	marker = PayloadValidation.string(32, 1),
	right = PayloadValidation.optional(CHILD_VALIDATOR),
})
local SECURITY_PAYLOAD_SCHEMA = PayloadValidation.schema(PayloadValidation.union({
	RICH_PAYLOAD_VALIDATOR,
	nestedRecord(PayloadValidation.MAX_DEPTH + 1),
}))
local SECURITY_RESPONSE_SCHEMA = PayloadValidation.schema(PayloadValidation.record({
	accepted = PayloadValidation.boolean(),
	commit = PayloadValidation.integer(1, 10_000),
}))

local function loggerFor(role: RuntimePlaceRole): Log.Logger
	return Log.new(EnvironmentContext.new("server", role, 0, false))
end

local function validPayload(marker: string?): { [string]: any }
	return {
		amount = 1,
		items = { { label = "safe" } },
		mapId = "map:test-security",
		marker = marker or "safe",
	}
end

local function nestedPayload(depth: number): unknown
	local value: unknown = "leaf"
	for _ = 1, depth do
		value = { child = value }
	end
	return value
end

local function requestWire(requestId: string, payload: unknown): RequestProtocol.RawRequest
	return {
		requestId = requestId,
		payload = payload,
	}
end

local function eventWire(payload: unknown): RequestProtocol.RawEvent
	return { payload = payload }
end

local function makePolicy(capacity: number, refillPerSecond: number): ServerRateLimiter.Policy
	local result = ServerRateLimiter.createPolicy(capacity, refillPerSecond)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=SECURITY_POLICY_CREATION_FAILED]", 0)
	end
	return result.value
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

local function keyCount(value: { [any]: unknown }): number
	local count = 0
	for _ in next, value do
		count += 1
	end
	return count
end

local function assertGraphDoesNotRetain(assertions: Assertions, root: unknown, forbidden: unknown)
	local visited: { [any]: boolean } = {}
	local function visit(value: unknown)
		assertions.notEqual(value, forbidden)
		if type(value) ~= "table" or rawget(visited, value) == true then
			return
		end
		rawset(visited, value, true)
		for key, child in next, value :: { [any]: unknown } do
			assertions.notEqual(key, forbidden)
			visit(child)
		end
	end
	visit(root)
end

local function responseCode(envelope: ServerRequestDispatcher.ResponseEnvelope): string
	local result = RequestProtocol.parseResponse(envelope)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=SECURITY_RESPONSE_PARSE_FAILED]", 0)
	end
	return if result.value.state == "Success" then "Success" else result.value.error.code
end

local function assertSafeAggregate(
	assertions: Assertions,
	report: { [string]: any },
	allowedFields: { [string]: boolean },
	forbiddenPlayer: Player?,
	forbiddenId: string?
)
	assertions.isTrue(table.isfrozen(report))
	assertions.equal(keyCount(report), 4)
	for key in next, report do
		assertions.equal(type(key), "string")
		assertions.isTrue(allowedFields[key] == true)
	end
	assertGraphDoesNotRetain(assertions, report, PRIVATE_SENTINEL)
	if forbiddenPlayer ~= nil then
		assertGraphDoesNotRetain(assertions, report, forbiddenPlayer)
	end
	if forbiddenId ~= nil then
		assertGraphDoesNotRetain(assertions, report, forbiddenId)
	end
end

local function formatProtocolReport(logger: Log.Logger, report: ServerRequestDispatcher.AggregateReport): string
	return logger:formatRecord(
		"WARN",
		"network",
		"protocol_rejections",
		"Network protocol rejections were aggregated",
		{
			code = report.code,
			endpoint = report.endpoint,
			protocolRejectionCount = report.protocolRejectionCount,
			protocolWindowSeconds = report.protocolWindowSeconds,
		}
	)
end

local function formatRateReport(logger: Log.Logger, report: ServerRateLimiter.AbuseReport): string
	return logger:formatRecord("WARN", "network", "rate_limit_rejections", "Rate limit rejections were aggregated", {
		code = report.code,
		endpoint = report.endpoint,
		rateLimitRejectionCount = report.rateLimitRejectionCount,
		rateLimitWindowSeconds = report.rateLimitWindowSeconds,
	})
end

type RuntimeOptions = {
	role: RuntimePlaceRole?,
	responseCapacity: number?,
	responseRefill: number?,
	eventCapacity: number?,
	eventRefill: number?,
	noResponseCapacity: number?,
	noResponseRefill: number?,
}

type Runtime = any

local function newRuntime(options: RuntimeOptions?): Runtime
	if ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME) ~= nil then
		error("[ATD_TEST_FIXTURE][code=SECURITY_ROOT_ALREADY_PRESENT]", 0)
	end

	local selected = options or {}
	local role = selected.role or "Match"
	local runtime: Runtime = {
		role = role,
		logger = loggerFor(role),
		rateNow = 0,
		observationNow = 0,
		listeners = {},
		listenerOrder = {},
		limiterReports = {},
		protocolReports = {},
		sent = {},
		players = {},
		instances = {},
		mutationCount = 0,
		authorizationCount = 0,
		handlerCount = 0,
		lastContext = nil,
		lastCanonicalPayload = nil,
		allowPlayer = nil,
		handlerMode = "success",
		customHandlers = {},
		limiterRemoval = nil,
		dispatcherRemoval = nil,
		limiterRemovalActive = false,
		dispatcherRemovalActive = false,
		limiterRemovalDisconnectCount = 0,
		dispatcherRemovalDisconnectCount = 0,
	}

	local responsePolicy = makePolicy(selected.responseCapacity or 100, selected.responseRefill or 100)
	local eventPolicy = makePolicy(selected.eventCapacity or 100, selected.eventRefill or 100)
	local noResponsePolicy = makePolicy(selected.noResponseCapacity or 100, selected.noResponseRefill or 100)
	local bindings = {}
	for _, definition in REGISTRY:list() do
		if definition.direction == "ClientToServer" then
			local policy = if definition.name == "TestResponseRequest"
				then responsePolicy
				elseif definition.name == "TestClientEvent" then eventPolicy
				else noResponsePolicy
			table.insert(bindings, {
				endpoint = definition.name,
				policy = policy,
			})
		end
	end

	local function connectEndpoint(remote: RemoteEvent, listener: ServerRemoteRegistry.Listener): RBXScriptConnection
		local endpointName = remote.Parent.Name
		local entry: any = {
			remote = remote,
			listener = listener,
			active = true,
			disconnectCount = 0,
		}
		entry.fire = function(player: Player, ...: unknown)
			if entry.active then
				listener(player, ...)
			end
		end
		runtime.listeners[endpointName] = entry
		table.insert(runtime.listenerOrder, endpointName)
		return RobloxAdapter.createConnection(function()
			entry.disconnectCount += 1
			entry.active = false
		end) :: any
	end

	local limiterDependencies: ServerRemoteRegistry.LimiterDependencies = {
		players = Players,
		clock = function(): number
			return runtime.rateNow
		end,
		connectPlayerRemoving = function(handler: ServerRateLimiter.PlayerRemovingHandler): RBXScriptConnection
			runtime.limiterRemoval = handler
			runtime.limiterRemovalActive = true
			return RobloxAdapter.createConnection(function()
				runtime.limiterRemovalDisconnectCount += 1
				runtime.limiterRemovalActive = false
			end) :: any
		end,
		reporter = function(report: ServerRateLimiter.AbuseReport)
			table.insert(runtime.limiterReports, report)
		end,
	}
	local dispatcherDependencies: ServerRemoteRegistry.DispatcherDependencies = {
		clock = function(): number
			return runtime.observationNow
		end,
		connectPlayerRemoving = function(handler: ServerRequestDispatcher.PlayerRemovingHandler): RBXScriptConnection
			runtime.dispatcherRemoval = handler
			runtime.dispatcherRemovalActive = true
			return RobloxAdapter.createConnection(function()
				runtime.dispatcherRemovalDisconnectCount += 1
				runtime.dispatcherRemovalActive = false
			end) :: any
		end,
		reporter = function(report: ServerRequestDispatcher.AggregateReport)
			table.insert(runtime.protocolReports, report)
		end,
		sender = function(remote: RemoteEvent, player: Player, envelope: ServerRequestDispatcher.ResponseEnvelope)
			table.insert(runtime.sent, {
				remote = remote,
				player = player,
				envelope = envelope,
			})
		end,
	}

	runtime.server = ServerRemoteRegistry.new(
		runtime.logger,
		REGISTRY,
		ReplicatedStorage,
		role,
		bindings,
		connectEndpoint,
		limiterDependencies,
		dispatcherDependencies
	)
	runtime.service = runtime.server:getServiceDefinition()
	return runtime
end

local function makeSuccess(runtime: Runtime, context: ServerContext): HandlerOutcome
	local nextCommit = runtime.mutationCount + 1
	local outcome = ServerRequestDispatcher.success({ accepted = true, commit = nextCommit })
	runtime.mutationCount = nextCommit
	runtime.lastContext = context
	return outcome
end

local function defaultAuthorizer(runtime: Runtime, context: ServerContext): boolean
	runtime.authorizationCount += 1
	runtime.lastContext = context
	return runtime.allowPlayer == nil or runtime.allowPlayer == context.player
end

local function responseHandler(runtime: Runtime, context: ServerContext, payload: unknown): HandlerOutcome
	runtime.handlerCount += 1
	runtime.lastCanonicalPayload = payload
	local custom = runtime.customHandlers.TestResponseRequest
	if custom ~= nil then
		return custom(context, payload)
	end
	if runtime.handlerMode == "throw" then
		error(PRIVATE_SENTINEL, 0)
	elseif runtime.handlerMode == "counterfeit" then
		return table.freeze({ kind = "Success", payload = PRIVATE_SENTINEL }) :: any
	elseif runtime.handlerMode == "invalid-response" then
		return ServerRequestDispatcher.success({ accepted = PRIVATE_SENTINEL, commit = 1 })
	end
	return makeSuccess(runtime, context)
end

local function noResponseHandler(
	runtime: Runtime,
	endpointName: string,
	context: ServerContext,
	payload: unknown
): HandlerOutcome
	runtime.handlerCount += 1
	runtime.lastCanonicalPayload = payload
	local custom = runtime.customHandlers[endpointName]
	if custom ~= nil then
		return custom(context, payload)
	end
	local outcome = ServerRequestDispatcher.success(nil)
	runtime.mutationCount += 1
	runtime.lastContext = context
	return outcome
end

local function bindAll(runtime: Runtime)
	local function authorize(context: ServerContext): boolean
		return defaultAuthorizer(runtime, context)
	end
	runtime.server:registerEvent(
		"TestClientEvent",
		SECURITY_PAYLOAD_SCHEMA,
		authorize,
		function(context: ServerContext, payload: unknown): HandlerOutcome
			return noResponseHandler(runtime, "TestClientEvent", context, payload)
		end
	)
	runtime.server:registerRequest(
		"TestNoResponseRequest",
		SECURITY_PAYLOAD_SCHEMA,
		nil,
		authorize,
		function(context: ServerContext, payload: unknown): HandlerOutcome
			return noResponseHandler(runtime, "TestNoResponseRequest", context, payload)
		end
	)
	runtime.server:registerRequest(
		"TestResponseRequest",
		SECURITY_PAYLOAD_SCHEMA,
		SECURITY_RESPONSE_SCHEMA,
		authorize,
		function(context: ServerContext, payload: unknown): HandlerOutcome
			return responseHandler(runtime, context, payload)
		end
	)
end

local function initializeRuntime(runtime: Runtime)
	local initialize = runtime.service.initialize
	if initialize == nil then
		error("[ATD_TEST_FIXTURE][code=SECURITY_INITIALIZE_MISSING]", 0)
	end
	initialize()
end

local function startRuntime(runtime: Runtime)
	local start = runtime.service.start
	if start == nil then
		error("[ATD_TEST_FIXTURE][code=SECURITY_START_MISSING]", 0)
	end
	start()
end

local function shutdownRuntime(runtime: Runtime)
	local shutdown = runtime.service.shutdown
	if shutdown == nil then
		error("[ATD_TEST_FIXTURE][code=SECURITY_SHUTDOWN_MISSING]", 0)
	end
	shutdown()
end

local function bindInitializeStart(runtime: Runtime)
	bindAll(runtime)
	initializeRuntime(runtime)
	startRuntime(runtime)
end

local function newPlayer(runtime: Runtime, prefix: string?): Player
	playerSequence += 1
	local player = Instance.new("Player") :: Player
	player.Name = `{prefix or "SecurityPlayer"}{playerSequence}`
	player.Parent = Players
	table.insert(runtime.players, player)
	return player
end

local function ownInstance(runtime: Runtime, instance: Instance): Instance
	table.insert(runtime.instances, instance)
	return instance
end

local function fire(runtime: Runtime, endpointName: string, player: Player, ...: unknown)
	local entry = runtime.listeners[endpointName]
	if entry == nil then
		error("[ATD_TEST_FIXTURE][code=SECURITY_LISTENER_MISSING]", 0)
	end
	entry.fire(player, ...)
end

local function rawFire(runtime: Runtime, endpointName: string, player: Player, ...: unknown)
	local entry = runtime.listeners[endpointName]
	if entry == nil then
		error("[ATD_TEST_FIXTURE][code=SECURITY_LISTENER_MISSING]", 0)
	end
	entry.listener(player, ...)
end

local function cleanupRuntime(runtime: Runtime)
	if runtime.server:getState() == "Initialized" then
		pcall(function()
			startRuntime(runtime)
		end)
	end
	if runtime.server:getState() == "Started" then
		pcall(function()
			shutdownRuntime(runtime)
		end)
	end
	for _, instance in runtime.instances do
		pcall(function()
			instance:Destroy()
		end)
	end
	for _, player in runtime.players do
		pcall(function()
			player:Destroy()
		end)
	end
end

local function withRuntime(options: RuntimeOptions?, callback: (runtime: Runtime) -> ())
	local runtime = newRuntime(options)
	local succeeded, failure = pcall(callback, runtime)
	cleanupRuntime(runtime)
	if not succeeded then
		error(failure, 0)
	end
end

local function resolveEndpoint(runtime: Runtime, endpointName: unknown): ClientRemoteLookup.LookupResult
	return (resolveForTests :: ClientRemoteLookup.TestResolver)(
		REGISTRY,
		ReplicatedStorage,
		runtime.role,
		endpointName,
		1,
		function(): number
			return 0
		end,
		function(parent: Instance, childName: string, _remaining: number): Instance?
			return parent:FindFirstChild(childName)
		end
	)
end

return TestHarness.suite("integrated network security boundary", {
	TestHarness.case(
		"completes one fixed client tracked request through the published response leaf",
		function(assertions)
			withRuntime(nil, function(runtime)
				bindInitializeStart(runtime)
				local player = newPlayer(runtime)
				local generated = false
				local trackerResult = (newTrackerForTests :: ClientRequestTracker.TestConstructor)(
					REGISTRY,
					"Match",
					function(): string
						generated = true
						return "Secure001"
					end
				)
				assertions.isTrue(trackerResult.ok)
				if not trackerResult.ok then
					return
				end
				local tracker = trackerResult.value
				assertions.isTrue(
					tracker:register("TestResponseRequest", SECURITY_PAYLOAD_SCHEMA, SECURITY_RESPONSE_SCHEMA).ok
				)
				local built = tracker:buildRequest("TestResponseRequest", validPayload("tracked"))
				assertions.isTrue(built.ok)
				if not built.ok then
					return
				end
				assertions.isTrue(generated)

				local resolved = resolveEndpoint(runtime, "TestResponseRequest")
				assertions.isTrue(resolved.ok)
				if not resolved.ok then
					return
				end
				assertions.equal(resolved.value.request, runtime.listeners.TestResponseRequest.remote)
				fire(runtime, "TestResponseRequest", player, built.value.envelope)

				assertions.equal(runtime.mutationCount, 1)
				assertions.equal(runtime.handlerCount, 1)
				assertions.isTrue(ServerRequestDispatcher.isContext(runtime.lastContext))
				assertions.equal(runtime.lastContext.player, player)
				assertions.equal(runtime.lastContext.definition, resolved.value.definition)
				assertions.notEqual(runtime.lastCanonicalPayload, built.value.envelope.payload)
				assertions.isTrue(table.isfrozen(runtime.lastCanonicalPayload))
				assertions.equal(#runtime.sent, 1)
				assertions.equal(runtime.sent[1].remote, resolved.value.response)
				assertions.equal(runtime.sent[1].player, player)
				assertions.equal(responseCode(runtime.sent[1].envelope), "Success")

				local handled = tracker:handleResponse(resolved.value.definition, runtime.sent[1].envelope)
				assertions.isTrue(handled.ok)
				if handled.ok then
					assertions.isTrue(RequestProtocol.isSuccess(handled.value))
					assertions.equal((handled.value :: RequestProtocol.Success).requestId.value, "Secure001")
					assertions.equal(((handled.value :: RequestProtocol.Success).payload :: any).commit, 1)
				end
				assertions.equal(tracker:getStats().pendingCount, 0)
			end)
		end
	),

	TestHarness.case(
		"rejects unknown path wrong direction wrong kind duplicate binding and lifecycle reentry",
		function(assertions)
			withRuntime({ role = "Development" }, function(runtime)
				local function authorize(_context: ServerContext): boolean
					return true
				end
				local function handler(_context: ServerContext, _payload: unknown): HandlerOutcome
					return ServerRequestDispatcher.success(nil)
				end

				local unknown = captureError(assertions, function()
					runtime.server:registerRequest(
						UNKNOWN_PATH,
						SECURITY_PAYLOAD_SCHEMA,
						SECURITY_RESPONSE_SCHEMA,
						authorize,
						handler
					)
				end)
				assertCode(assertions, unknown, "UNKNOWN_ENDPOINT")
				assertions.isNil(string.find(unknown, PRIVATE_SENTINEL, 1, true))

				local wrongDirection = captureError(assertions, function()
					runtime.server:registerEvent("TestServerEvent", SECURITY_PAYLOAD_SCHEMA, authorize, handler)
				end)
				assertCode(assertions, wrongDirection, "WRONG_DIRECTION")
				local wrongKind = captureError(assertions, function()
					runtime.server:registerEvent("TestResponseRequest", SECURITY_PAYLOAD_SCHEMA, authorize, handler)
				end)
				assertCode(assertions, wrongKind, "WRONG_KIND")
				local otherWrongKind = captureError(assertions, function()
					runtime.server:registerRequest("TestClientEvent", SECURITY_PAYLOAD_SCHEMA, nil, authorize, handler)
				end)
				assertCode(assertions, otherWrongKind, "WRONG_KIND")

				bindAll(runtime)
				local duplicate = captureError(assertions, function()
					runtime.server:registerRequest(
						"TestResponseRequest",
						SECURITY_PAYLOAD_SCHEMA,
						SECURITY_RESPONSE_SCHEMA,
						authorize,
						handler
					)
				end)
				assertCode(assertions, duplicate, "DUPLICATE_CONTRACT")
				initializeRuntime(runtime)
				local root = ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME)
				assertions.isNotNil(root)
				local initializeAgain = captureError(assertions, function()
					initializeRuntime(runtime)
				end)
				assertCode(assertions, initializeAgain, "INVALID_STATE")
				assertions.equal(ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME), root)
				startRuntime(runtime)
				local startAgain = captureError(assertions, function()
					startRuntime(runtime)
				end)
				assertCode(assertions, startAgain, "INVALID_STATE")

				assertions.equal(
					table.concat(runtime.listenerOrder, ","),
					"TestClientEvent,TestNoResponseRequest,TestResponseRequest"
				)
				assertions.equal(runtime.listeners.TestResponseRequest.remote.Name, "Request")
				local responseLeaf = (root :: Instance):FindFirstChild(RemoteRegistry.VERSION_NAME) :: Instance
				responseLeaf = responseLeaf:FindFirstChild("TestResponseRequest") :: Instance
				responseLeaf = responseLeaf:FindFirstChild("Response") :: Instance
				assertions.isNotNil(responseLeaf)
				for _, entry in runtime.listeners do
					assertions.notEqual(entry.remote, responseLeaf)
				end

				local waitCount = 0
				local lookup = (resolveForTests :: ClientRemoteLookup.TestResolver)(
					REGISTRY,
					ReplicatedStorage,
					"Development",
					UNKNOWN_PATH,
					1,
					function(): number
						return 0
					end,
					function(_parent: Instance, _childName: string, _remaining: number): Instance?
						waitCount += 1
						return nil
					end
				)
				assertions.isFalse(lookup.ok)
				if not lookup.ok then
					assertions.equal(lookup.error.code, "UNKNOWN_ENDPOINT")
					assertions.isNil(string.find(lookup.error.message, PRIVATE_SENTINEL, 1, true))
				end
				assertions.equal(waitCount, 0)
				assertions.isNil((root :: Instance):FindFirstChild(UNKNOWN_PATH))
			end)
		end
	),

	TestHarness.case(
		"drops malformed envelopes request IDs hostile tables and extra arguments before limiting",
		function(assertions)
			withRuntime({ responseCapacity = 2, responseRefill = 1 }, function(runtime)
				bindInitializeStart(runtime)
				local player = newPlayer(runtime)
				local hostileCalls = 0
				local hostile = setmetatable({
					requestId = "Hostile01",
					payload = validPayload(),
				}, {
					__index = function()
						hostileCalls += 1
						return PRIVATE_SENTINEL
					end,
					__len = function()
						hostileCalls += 1
						return 2
					end,
				})

				fire(runtime, "TestResponseRequest", player)
				fire(runtime, "TestResponseRequest", player, 42)
				fire(runtime, "TestResponseRequest", player, requestWire("short", validPayload()))
				fire(
					runtime,
					"TestResponseRequest",
					player,
					requestWire(string.rep("A", RequestProtocol.MAX_REQUEST_ID_BYTES + 1), validPayload())
				)
				fire(runtime, "TestResponseRequest", player, requestWire("Malformed/01", validPayload()))
				fire(runtime, "TestResponseRequest", player, {
					requestId = "ExtraKey01",
					payload = validPayload(),
					action = PRIVATE_SENTINEL,
				})
				fire(runtime, "TestResponseRequest", player, hostile)
				fire(
					runtime,
					"TestResponseRequest",
					player,
					requestWire("ExtraArg01", validPayload()),
					PRIVATE_SENTINEL
				)

				assertions.equal(hostileCalls, 0)
				assertions.equal(runtime.authorizationCount, 0)
				assertions.equal(runtime.handlerCount, 0)
				assertions.equal(runtime.mutationCount, 0)
				assertions.equal(#runtime.sent, 0)

				fire(runtime, "TestResponseRequest", player, requestWire("Budget001", validPayload()))
				fire(runtime, "TestResponseRequest", player, requestWire("Budget002", validPayload()))
				fire(runtime, "TestResponseRequest", player, requestWire("Budget003", validPayload()))
				assertions.equal(runtime.mutationCount, 2)
				assertions.equal(runtime.handlerCount, 2)
				assertions.equal(#runtime.sent, 3)
				assertions.equal(responseCode(runtime.sent[1].envelope), "Success")
				assertions.equal(responseCode(runtime.sent[2].envelope), "Success")
				assertions.equal(responseCode(runtime.sent[3].envelope), "RATE_LIMITED")
			end)
		end
	),

	TestHarness.case("rejects the adversarial payload matrix with zero mutation", function(assertions)
		withRuntime(nil, function(runtime)
			bindInitializeStart(runtime)
			local player = newPlayer(runtime)
			local hostileCalls = 0
			local unexpected = validPayload()
			unexpected.ownerUserId = PRIVATE_SENTINEL
			local oversizedString = validPayload()
			oversizedString.marker = string.rep("x", 33)
			local oversizedArray = validPayload()
			oversizedArray.items = {
				{ label = "one" },
				{ label = "two" },
				{ label = "three" },
				{ label = "four" },
				{ label = "five" },
			}
			local sparseArray = validPayload()
			sparseArray.items = { [1] = { label = "one" }, [3] = { label = "three" } }
			local cycle = validPayload()
			cycle.left = cycle
			local repeatedChild = { value = "shared" }
			local repeated = validPayload()
			repeated.left = repeatedChild
			repeated.right = repeatedChild
			local hostile = setmetatable(validPayload(), {
				__index = function()
					hostileCalls += 1
					return PRIVATE_SENTINEL
				end,
				__len = function()
					hostileCalls += 1
					return 0
				end,
			})
			local nanPayload = validPayload()
			nanPayload.amount = 0 / 0
			local positiveInfinity = validPayload()
			positiveInfinity.amount = math.huge
			local negativeInfinity = validPayload()
			negativeInfinity.amount = -math.huge
			local crossFamily = validPayload()
			crossFamily.mapId = "enemy:wrong-family"
			local oversizedId = validPayload()
			oversizedId.mapId = "map:" .. string.rep("a", 60)
			local unexpectedInstance = Instance.new("Folder")
			unexpectedInstance.Name = "PrivateUnexpectedInstance"
			ownInstance(runtime, unexpectedInstance)
			local instancePayload = validPayload()
			instancePayload.marker = unexpectedInstance

			local attacks: { unknown } = {
				unexpected,
				oversizedString,
				oversizedArray,
				sparseArray,
				nestedPayload(PayloadValidation.MAX_DEPTH + 1),
				cycle,
				repeated,
				hostile,
				nanPayload,
				positiveInfinity,
				negativeInfinity,
				crossFamily,
				oversizedId,
				instancePayload,
			}
			for index, payload in attacks do
				local beforeMutation = runtime.mutationCount
				local beforeSend = #runtime.sent
				fire(runtime, "TestResponseRequest", player, requestWire(string.format("Attack%03d", index), payload))
				assertions.equal(runtime.mutationCount, beforeMutation)
				assertions.equal(#runtime.sent, beforeSend + 1)
				local sent = runtime.sent[#runtime.sent]
				assertions.equal(sent.player, player)
				assertions.equal(responseCode(sent.envelope), "INVALID_PAYLOAD")
				assertGraphDoesNotRetain(assertions, sent.envelope, payload)
				assertGraphDoesNotRetain(assertions, sent.envelope, PRIVATE_SENTINEL)
				assertGraphDoesNotRetain(assertions, sent.envelope, unexpectedInstance)
				local parsed = RequestProtocol.parseResponse(sent.envelope)
				assertions.isTrue(parsed.ok)
				if parsed.ok and parsed.value.state == "Rejected" and parsed.value.error.metadata ~= nil then
					local path = parsed.value.error.metadata.validationPath
					assertions.isTrue(#path <= RequestProtocol.MAX_VALIDATION_PATH_BYTES)
					assertions.isNil(string.find(path, PRIVATE_SENTINEL, 1, true))
				end
			end
			assertions.equal(hostileCalls, 0)
			assertions.equal(runtime.handlerCount, 0)
			assertions.equal(runtime.mutationCount, 0)
		end)
	end),

	TestHarness.case(
		"authorizes from captured genuine Player context and rejects forged authority fields",
		function(assertions)
			withRuntime(nil, function(runtime)
				local allowedPlayer = newPlayer(runtime, "AllowedPlayer")
				local deniedPlayer = newPlayer(runtime, "DeniedPlayer")
				runtime.allowPlayer = allowedPlayer
				bindInitializeStart(runtime)

				local deniedForgery = validPayload()
				deniedForgery.claimedPlayer = allowedPlayer
				deniedForgery.ownerUserId = 12345
				fire(runtime, "TestResponseRequest", deniedPlayer, requestWire("Denied001", deniedForgery))
				assertions.equal(responseCode(runtime.sent[1].envelope), "NOT_AUTHORIZED")
				assertions.equal(runtime.sent[1].player, deniedPlayer)
				assertions.equal(runtime.handlerCount, 0)
				assertions.equal(runtime.mutationCount, 0)

				local allowedForgery = validPayload()
				allowedForgery.ownerUserId = 12345
				allowedForgery.team = PRIVATE_SENTINEL
				allowedForgery.action = "arbitrary"
				fire(runtime, "TestResponseRequest", allowedPlayer, requestWire("Forged001", allowedForgery))
				assertions.equal(responseCode(runtime.sent[2].envelope), "INVALID_PAYLOAD")
				assertions.equal(runtime.sent[2].player, allowedPlayer)
				assertions.equal(runtime.handlerCount, 0)
				assertions.equal(runtime.mutationCount, 0)

				fire(runtime, "TestResponseRequest", allowedPlayer, requestWire("Allowed01", validPayload()))
				assertions.equal(responseCode(runtime.sent[3].envelope), "Success")
				assertions.equal(runtime.sent[3].player, allowedPlayer)
				assertions.equal(runtime.authorizationCount, 3)
				assertions.equal(runtime.handlerCount, 1)
				assertions.equal(runtime.mutationCount, 1)
				assertions.equal(runtime.lastContext.player, allowedPlayer)
				assertions.isTrue(ServerRequestDispatcher.isContext(runtime.lastContext))
			end)
		end
	),

	TestHarness.case("contains pending duplicates and classifies completed replay as stale", function(assertions)
		withRuntime({ responseCapacity = 10, responseRefill = 10 }, function(runtime)
			local player = newPlayer(runtime)
			local wire = requestWire("Duplicate01", validPayload())
			local reentered = false
			runtime.customHandlers.TestResponseRequest = function(
				context: ServerContext,
				_payload: unknown
			): HandlerOutcome
				if not reentered then
					reentered = true
					fire(runtime, "TestResponseRequest", context.player, wire)
				end
				return makeSuccess(runtime, context)
			end
			bindInitializeStart(runtime)

			fire(runtime, "TestResponseRequest", player, wire)
			assertions.isTrue(reentered)
			assertions.equal(runtime.handlerCount, 1)
			assertions.equal(runtime.mutationCount, 1)
			assertions.equal(#runtime.sent, 1)
			assertions.equal(responseCode(runtime.sent[1].envelope), "Success")

			fire(runtime, "TestResponseRequest", player, wire)
			assertions.equal(runtime.handlerCount, 1)
			assertions.equal(runtime.mutationCount, 1)
			assertions.equal(#runtime.sent, 2)
			assertions.equal(responseCode(runtime.sent[2].envelope), "STALE_REQUEST")

			fire(runtime, "TestNoResponseRequest", player, wire)
			assertions.equal(runtime.handlerCount, 1)
			assertions.equal(runtime.mutationCount, 1)
			assertions.equal(#runtime.sent, 2)
		end)
	end),

	TestHarness.case("enforces independent player and action bursts while aggregating spam", function(assertions)
		withRuntime({
			responseCapacity = 1,
			responseRefill = 1,
			eventCapacity = 1,
			eventRefill = 1,
		}, function(runtime)
			bindInitializeStart(runtime)
			local firstPlayer = newPlayer(runtime, "BurstPlayer")
			local secondPlayer = newPlayer(runtime, "OtherBurstPlayer")

			fire(runtime, "TestResponseRequest", firstPlayer, requestWire("RateReq01", validPayload()))
			fire(runtime, "TestResponseRequest", firstPlayer, requestWire("RateReq02", validPayload()))
			fire(runtime, "TestClientEvent", firstPlayer, eventWire(validPayload("event")))
			fire(runtime, "TestResponseRequest", secondPlayer, requestWire("RateReq03", validPayload()))
			assertions.equal(responseCode(runtime.sent[1].envelope), "Success")
			assertions.equal(responseCode(runtime.sent[2].envelope), "RATE_LIMITED")
			assertions.equal(responseCode(runtime.sent[3].envelope), "Success")
			assertions.equal(runtime.mutationCount, 3)
			assertions.equal(#runtime.limiterReports, 1)

			runtime.rateNow = 1
			fire(runtime, "TestResponseRequest", firstPlayer, requestWire("RateReq04", validPayload()))
			assertions.equal(responseCode(runtime.sent[4].envelope), "Success")
			for index = 1, 20 do
				fire(
					runtime,
					"TestResponseRequest",
					firstPlayer,
					requestWire(string.format("RateSpam%03d", index), validPayload(PRIVATE_SENTINEL))
				)
			end
			assertions.equal(#runtime.limiterReports, 1)

			runtime.rateNow = 10
			fire(runtime, "TestResponseRequest", firstPlayer, requestWire("Refill010", validPayload()))
			fire(runtime, "TestResponseRequest", firstPlayer, requestWire("After010", validPayload()))
			assertions.equal(#runtime.limiterReports, 2)
			assertions.equal(runtime.mutationCount, 5)

			for _ = 1, 20 do
				fire(runtime, "TestResponseRequest", firstPlayer, { private = PRIVATE_SENTINEL })
			end
			assertions.equal(#runtime.protocolReports, 1)
			runtime.observationNow = ServerRequestDispatcher.REPORT_INTERVAL_SECONDS
			fire(runtime, "TestResponseRequest", firstPlayer, { private = PRIVATE_SENTINEL })
			assertions.equal(#runtime.protocolReports, 2)

			local rateAllowed = {
				code = true,
				endpoint = true,
				rateLimitRejectionCount = true,
				rateLimitWindowSeconds = true,
			}
			for _, report in runtime.limiterReports do
				assertSafeAggregate(assertions, report, rateAllowed, firstPlayer, "RateSpam001")
				local record = formatRateReport(runtime.logger, report)
				assertions.isNil(string.find(record, PRIVATE_SENTINEL, 1, true))
				assertions.isNil(string.find(record, firstPlayer.Name, 1, true))
				assertions.isNil(string.find(record, "RateSpam001", 1, true))
			end
			local protocolAllowed = {
				code = true,
				endpoint = true,
				protocolRejectionCount = true,
				protocolWindowSeconds = true,
			}
			for _, report in runtime.protocolReports do
				assertSafeAggregate(assertions, report, protocolAllowed, firstPlayer, "RateReq01")
				local record = formatProtocolReport(runtime.logger, report)
				assertions.isNil(string.find(record, PRIVATE_SENTINEL, 1, true))
				assertions.isNil(string.find(record, firstPlayer.Name, 1, true))
			end
		end)
	end),

	TestHarness.case(
		"translates handler failures and counterfeit outcomes without privacy leakage",
		function(assertions)
			withRuntime(nil, function(runtime)
				bindInitializeStart(runtime)
				local player = newPlayer(runtime)
				local modes = { "throw", "counterfeit", "invalid-response" }
				for index, mode in modes do
					runtime.handlerMode = mode
					local beforeMutation = runtime.mutationCount
					fire(
						runtime,
						"TestResponseRequest",
						player,
						requestWire(string.format("Failure%02d", index), validPayload("failure"))
					)
					assertions.equal(runtime.mutationCount, beforeMutation)
					local sent = runtime.sent[#runtime.sent]
					assertions.equal(sent.player, player)
					assertions.equal(responseCode(sent.envelope), "INTERNAL_ERROR")
					assertGraphDoesNotRetain(assertions, sent.envelope, PRIVATE_SENTINEL)
					assertGraphDoesNotRetain(assertions, sent.envelope, player)
				end

				runtime.customHandlers.TestClientEvent = function(
					_context: ServerContext,
					_payload: unknown
				): HandlerOutcome
					error(PRIVATE_SENTINEL, 0)
				end
				runtime.observationNow = ServerRequestDispatcher.REPORT_INTERVAL_SECONDS
				local sentBeforeEvent = #runtime.sent
				fire(runtime, "TestClientEvent", player, eventWire(validPayload("event-private")))
				assertions.equal(#runtime.sent, sentBeforeEvent)
				assertions.equal(runtime.mutationCount, 0)
				assertions.equal(runtime.handlerCount, 4)
				assertions.equal(#runtime.protocolReports, 2)
				for _, report in runtime.protocolReports do
					assertSafeAggregate(assertions, report, {
						code = true,
						endpoint = true,
						protocolRejectionCount = true,
						protocolWindowSeconds = true,
					}, player, "Failure01")
					local record = formatProtocolReport(runtime.logger, report)
					assertions.isNil(string.find(record, PRIVATE_SENTINEL, 1, true))
					assertions.isNil(string.find(record, player.Name, 1, true))
					assertions.isNil(string.find(record, "Failure01", 1, true))
					assertions.isNil(string.find(record, "event-private", 1, true))
				end
			end)
		end
	),

	TestHarness.case("clears player and network ownership on removal and shutdown", function(assertions)
		withRuntime(nil, function(runtime)
			bindInitializeStart(runtime)
			local removedPlayer = newPlayer(runtime, "RemovedPlayer")
			local survivingPlayer = newPlayer(runtime, "SurvivingPlayer")
			fire(runtime, "TestResponseRequest", removedPlayer, requestWire("BeforeGone", validPayload()))
			assertions.equal(runtime.mutationCount, 1)
			assertions.equal(#runtime.sent, 1)

			assertions.isNotNil(runtime.dispatcherRemoval)
			assertions.isNotNil(runtime.limiterRemoval)
			local dispatcherRemoval = runtime.dispatcherRemoval :: ServerRequestDispatcher.PlayerRemovingHandler
			local limiterRemoval = runtime.limiterRemoval :: ServerRateLimiter.PlayerRemovingHandler
			dispatcherRemoval(removedPlayer)
			limiterRemoval(removedPlayer)
			fire(runtime, "TestResponseRequest", removedPlayer, requestWire("AfterGone", validPayload()))
			assertions.equal(runtime.mutationCount, 1)
			assertions.equal(#runtime.sent, 1)

			fire(runtime, "TestResponseRequest", survivingPlayer, requestWire("Survives1", validPayload()))
			assertions.equal(runtime.mutationCount, 2)
			assertions.equal(#runtime.sent, 2)
			assertions.equal(runtime.sent[2].player, survivingPlayer)

			shutdownRuntime(runtime)
			assertions.equal(runtime.server:getState(), "Shutdown")
			assertions.isNil(ReplicatedStorage:FindFirstChild(RemoteRegistry.ROOT_NAME))
			assertions.equal(runtime.limiterRemovalDisconnectCount, 1)
			assertions.equal(runtime.dispatcherRemovalDisconnectCount, 1)
			assertions.isFalse(runtime.limiterRemovalActive)
			assertions.isFalse(runtime.dispatcherRemovalActive)
			for _, entry in runtime.listeners do
				assertions.isFalse(entry.active)
				assertions.equal(entry.disconnectCount, 1)
			end

			fire(runtime, "TestResponseRequest", survivingPlayer, requestWire("PostStop1", validPayload()))
			rawFire(runtime, "TestResponseRequest", survivingPlayer, requestWire("PostStop2", validPayload()))
			assertions.equal(runtime.mutationCount, 2)
			assertions.equal(#runtime.sent, 2)
		end)
	end),
})
