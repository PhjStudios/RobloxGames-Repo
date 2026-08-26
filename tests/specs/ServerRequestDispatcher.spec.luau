--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local NetworkFixtures = require(script.Parent.Parent.Fixtures.NetworkFixtures)
local ServerRateLimiter = require(script.Parent.Parent.ProductionServerNetworking.ServerRateLimiter)
local ServerRequestDispatcher = require(script.Parent.Parent.ProductionServerNetworking.ServerRequestDispatcher)

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage").Shared
local EnvironmentContext = require(Shared.logging.EnvironmentContext)
local Log = require(Shared.logging.Log)
local PayloadValidation = require(Shared.network.PayloadValidation)
local RemoteRegistry = require(Shared.network.RemoteRegistry)
local RequestProtocol = require(Shared.network.RequestProtocol)

type Assertions = TestHarness.Assertions
type Registry = RemoteRegistry.Registry
type Definition = RemoteRegistry.Definition
type Contract = ServerRequestDispatcher.Contract
type Dispatcher = ServerRequestDispatcher.Dispatcher

local PRIVATE_SENTINEL = "PRIVATE_DISPATCH_SENTINEL_7c2d"
local playerSequence = 0

local function logger(): Log.Logger
	return Log.new(EnvironmentContext.new("server", "Match", 0, false))
end

local function makeRegistry(definitions: unknown): Registry
	local result = RemoteRegistry.create(definitions)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=REGISTRY_CREATION_FAILED]", 0)
	end
	return result.value
end

local function definitionsWithSecondRequest(): { any }
	local definitions = NetworkFixtures.validDefinitions()
	table.insert(definitions, {
		name = "TestSecondResponseRequest",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	})
	return definitions
end

local REGISTRY = makeRegistry(definitionsWithSecondRequest())

local function definition(endpoint: string): Definition
	local value = REGISTRY:get(endpoint)
	if value == nil then
		error("[ATD_TEST_FIXTURE][code=DEFINITION_MISSING]", 0)
	end
	return value
end

local RESPONSE_REQUEST = definition("TestResponseRequest")
local SECOND_RESPONSE_REQUEST = definition("TestSecondResponseRequest")
local NO_RESPONSE_REQUEST = definition("TestNoResponseRequest")
local CLIENT_EVENT = definition("TestClientEvent")
local SERVER_EVENT = definition("TestServerEvent")

local PAYLOAD_SCHEMA = PayloadValidation.schema(PayloadValidation.record({
	value = PayloadValidation.integer(0, 10_000),
}))
local RESPONSE_SCHEMA = PayloadValidation.schema(PayloadValidation.record({
	accepted = PayloadValidation.boolean(),
}))

local function makePolicy(capacity: number, refill: number): ServerRateLimiter.Policy
	local result = ServerRateLimiter.createPolicy(capacity, refill)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=POLICY_CREATION_FAILED]", 0)
	end
	return result.value
end

local function makePolicySet(policy: ServerRateLimiter.Policy): ServerRateLimiter.PolicySet
	local bindings = {}
	for _, item in REGISTRY:list() do
		if item.direction == "ClientToServer" then
			table.insert(bindings, {
				endpoint = item.name,
				policy = policy,
			})
		end
	end
	local result = ServerRateLimiter.createPolicySet(REGISTRY, "Match", bindings)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=POLICY_SET_CREATION_FAILED]", 0)
	end
	return result.value
end

local function newPlayer(): Player
	playerSequence += 1
	local player = Instance.new("Player") :: Player
	player.Name = `DispatcherPlayer{playerSequence}`
	player.Parent = Players
	return player
end

local function makeConnectionState(): any
	local state = {
		handler = nil,
		disconnectCount = 0,
	}
	state.connector = function(handler: any): RBXScriptConnection
		state.handler = handler
		return RobloxAdapter.createConnection(function()
			state.disconnectCount += 1
		end) :: any
	end
	return state
end

local function makeRuntime(options: any?): any
	local selected = options or {}
	local state: any = {
		rateNow = 0,
		observationNow = 0,
		sent = {},
		reports = {},
	}
	local limiterConnection = makeConnectionState()
	local policy = selected.policy or makePolicy(100, 100)
	local limiter = ServerRateLimiter.new(logger(), Players, makePolicySet(policy), function(): number
		return state.rateNow
	end, limiterConnection.connector, selected.limiterReporter or function(_report) end)
	state.limiter = limiter
	state.limiterCleanup = limiter:initialize()
	limiter:start()

	local dispatcherConnection = makeConnectionState()
	state.dispatcherConnection = dispatcherConnection
	local dependencies: ServerRequestDispatcher.Dependencies = {
		clock = selected.clock or function(): number
			return state.observationNow
		end,
		connectPlayerRemoving = dispatcherConnection.connector,
		reporter = selected.reporter or function(report)
			table.insert(state.reports, report)
		end,
		sender = selected.sender or function(remote, player, envelope)
			table.insert(state.sent, {
				remote = remote,
				player = player,
				envelope = envelope,
			})
		end,
	}
	local dispatcher = ServerRequestDispatcher.new(logger(), REGISTRY, "Match", Players, limiter, dependencies)
	state.dispatcher = dispatcher
	return state
end

local function startDispatcher(state: any, contracts: { Contract })
	for _, contract in contracts do
		state.dispatcher:registerContract(contract)
	end
	state.dispatcherCleanup = state.dispatcher:initialize()
	state.dispatcher:start()
end

local function cleanupRuntime(state: any)
	if state.dispatcherCleanup ~= nil then
		pcall(function()
			state.dispatcherCleanup:cleanup()
		end)
	end
	if state.limiterCleanup ~= nil then
		pcall(function()
			state.limiterCleanup:cleanup()
		end)
	end
end

local function withRuntime(options: any?, callback: (any, Player) -> ())
	local state = makeRuntime(options)
	local player = newPlayer()
	local succeeded, failure = pcall(callback, state, player)
	cleanupRuntime(state)
	pcall(function()
		player:Destroy()
	end)
	if not succeeded then
		error(failure, 0)
	end
end

local function captureError(assertions: Assertions, callback: () -> ()): string
	local succeeded, value = pcall(callback)
	assertions.isFalse(succeeded)
	assertions.equal(type(value), "string")
	return if type(value) == "string" then value else ""
end

local function requestWire(requestId: string, value: number): RequestProtocol.RawRequest
	local idResult = RequestProtocol.createRequestId(requestId)
	if not idResult.ok then
		error("[ATD_TEST_FIXTURE][code=REQUEST_ID_CREATION_FAILED]", 0)
	end
	local wireResult = RequestProtocol.buildRequest(idResult.value, { value = value })
	if not wireResult.ok then
		error("[ATD_TEST_FIXTURE][code=REQUEST_BUILD_FAILED]", 0)
	end
	return wireResult.value
end

local function eventWire(value: number): RequestProtocol.RawEvent
	local result = RequestProtocol.buildEvent({ value = value })
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=EVENT_BUILD_FAILED]", 0)
	end
	return result.value
end

local function publicError(code: RequestProtocol.PublicErrorCode): RequestProtocol.PublicError
	local result = RequestProtocol.createPublicError(code, nil)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=PUBLIC_ERROR_CREATION_FAILED]", 0)
	end
	return result.value
end

local function responseCode(envelope: ServerRequestDispatcher.ResponseEnvelope): string
	local result = RequestProtocol.parseResponse(envelope)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=RESPONSE_PARSE_FAILED]", 0)
	end
	if result.value.state == "Success" then
		return "Success"
	end
	return result.value.error.code
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

local function assertAggregateReport(
	assertions: Assertions,
	report: ServerRequestDispatcher.AggregateReport,
	expectedCode: string,
	forbiddenPlayer: Player,
	forbiddenRequestId: string
)
	local allowedFields = {
		code = true,
		endpoint = true,
		protocolRejectionCount = true,
		protocolWindowSeconds = true,
	}
	local fieldCount = 0
	for key in next, report :: any do
		fieldCount += 1
		assertions.equal(type(key), "string")
		assertions.isTrue(allowedFields[key] == true)
	end
	assertions.equal(fieldCount, 4)
	assertions.isTrue(table.isfrozen(report))
	assertions.equal(report.code, expectedCode)
	assertions.equal(report.endpoint, RESPONSE_REQUEST.name)
	assertions.equal(report.protocolRejectionCount, 1)
	assertions.equal(report.protocolWindowSeconds, ServerRequestDispatcher.REPORT_INTERVAL_SECONDS)
	assertGraphDoesNotRetain(assertions, report, PRIVATE_SENTINEL)
	assertGraphDoesNotRetain(assertions, report, forbiddenPlayer)
	assertGraphDoesNotRetain(assertions, report, forbiddenRequestId)
end

local function responseRequestContract(
	handler: ServerRequestDispatcher.Handler
): ServerRequestDispatcher.RequestContract
	return ServerRequestDispatcher.createRequestContract(
		REGISTRY,
		"Match",
		RESPONSE_REQUEST,
		PAYLOAD_SCHEMA,
		RESPONSE_SCHEMA,
		function(_context): boolean
			return true
		end,
		handler
	)
end

return TestHarness.suite("server request dispatcher", {
	TestHarness.case("authenticates fixed contracts contexts and handler outcomes", function(assertions)
		local seenContext: ServerRequestDispatcher.ServerContext? = nil
		local contract = responseRequestContract(function(context, _payload)
			seenContext = context
			return ServerRequestDispatcher.success({ accepted = true })
		end)
		assertions.isTrue(ServerRequestDispatcher.isRequestContract(contract))
		assertions.isFalse(ServerRequestDispatcher.isEventContract(contract))
		assertions.isTrue(table.isfrozen(contract))
		assertions.equal(contract:getDefinition(), RESPONSE_REQUEST)
		assertions.equal(contract:getKind(), "Request")
		assertions.isFalse(ServerRequestDispatcher.isRequestContract(table.freeze({})))

		local outcome = ServerRequestDispatcher.success(nil)
		assertions.isTrue(ServerRequestDispatcher.isOutcome(outcome))
		assertions.isTrue(table.isfrozen(outcome))
		assertions.isFalse(ServerRequestDispatcher.isOutcome(table.freeze({})))
		local rejected = ServerRequestDispatcher.reject(publicError("NOT_AUTHORIZED"))
		assertions.isTrue(ServerRequestDispatcher.isOutcome(rejected))
		captureError(assertions, function()
			ServerRequestDispatcher.reject({ code = "NOT_AUTHORIZED" })
		end)

		withRuntime(nil, function(state, player)
			startDispatcher(state, { contract })
			local responseRemote = Instance.new("RemoteEvent") :: RemoteEvent
			state.dispatcher:dispatch(contract, responseRemote, player, requestWire("Context01", 1))
			assertions.isNotNil(seenContext)
			assertions.isTrue(ServerRequestDispatcher.isContext(seenContext))
			assertions.isTrue(table.isfrozen(seenContext :: any))
			assertions.equal((seenContext :: ServerRequestDispatcher.ServerContext).player, player)
			assertions.equal((seenContext :: ServerRequestDispatcher.ServerContext).definition, RESPONSE_REQUEST)
			assertions.equal((seenContext :: ServerRequestDispatcher.ServerContext).role, "Match")
			responseRemote:Destroy()
		end)
	end),

	TestHarness.case(
		"rejects inactive wrong-kind schema-response and counterfeit contracts privately",
		function(assertions)
			local allow = function(_context: ServerRequestDispatcher.ServerContext): boolean
				return true
			end
			local handle = function(_context: ServerRequestDispatcher.ServerContext, _payload: unknown)
				return ServerRequestDispatcher.success(nil)
			end
			local failures = {
				function()
					ServerRequestDispatcher.createRequestContract(
						REGISTRY,
						"Match",
						SERVER_EVENT,
						PAYLOAD_SCHEMA,
						RESPONSE_SCHEMA,
						allow,
						handle
					)
				end,
				function()
					ServerRequestDispatcher.createEventContract(
						REGISTRY,
						"Match",
						RESPONSE_REQUEST,
						PAYLOAD_SCHEMA,
						allow,
						handle
					)
				end,
				function()
					ServerRequestDispatcher.createRequestContract(
						REGISTRY,
						"Match",
						RESPONSE_REQUEST,
						{},
						RESPONSE_SCHEMA,
						allow,
						handle
					)
				end,
				function()
					ServerRequestDispatcher.createRequestContract(
						REGISTRY,
						"Match",
						NO_RESPONSE_REQUEST,
						PAYLOAD_SCHEMA,
						RESPONSE_SCHEMA,
						allow,
						handle
					)
				end,
			}
			for _, callback in failures do
				local failure = captureError(assertions, callback)
				assertions.isNil(string.find(failure, PRIVATE_SENTINEL, 1, true))
			end

			withRuntime(nil, function(state, _player)
				local invalidLimiter = captureError(assertions, function()
					ServerRequestDispatcher.new(logger(), REGISTRY, "Match", Players, {} :: any)
				end)
				assertions.contains(invalidLimiter, "[code=INVALID_LIMITER]")
				local folder = Instance.new("Folder")
				local invalidPlayers = captureError(assertions, function()
					ServerRequestDispatcher.new(logger(), REGISTRY, "Match", folder, state.limiter)
				end)
				assertions.contains(invalidPlayers, "[code=INVALID_PLAYERS]")
				folder:Destroy()

				local contract = responseRequestContract(handle)
				state.dispatcher:registerContract(contract)
				local duplicate = captureError(assertions, function()
					state.dispatcher:registerContract(contract)
				end)
				assertions.contains(duplicate, "[code=DUPLICATE_CONTRACT]")
			end)
		end
	),

	TestHarness.case(
		"runs limiter ledger authorization validation handler completion and origin send in order",
		function(assertions)
			local dispatcherRef: Dispatcher? = nil
			local expectedPlayer: Player? = nil
			local expectedRemote: RemoteEvent? = nil
			local sentEnvelope: ServerRequestDispatcher.ResponseEnvelope? = nil
			local order = {}
			local input = { value = 7 }
			local contract: ServerRequestDispatcher.RequestContract
			contract = ServerRequestDispatcher.createRequestContract(
				REGISTRY,
				"Match",
				RESPONSE_REQUEST,
				PAYLOAD_SCHEMA,
				RESPONSE_SCHEMA,
				function(context): boolean
					table.insert(order, "authorize")
					assertions.isTrue(ServerRequestDispatcher.isContext(context))
					assertions.equal(context.player, expectedPlayer)
					assertions.equal((dispatcherRef :: Dispatcher):getStats().pendingRequestCount, 1)
					return true
				end,
				function(context, payload)
					table.insert(order, "handler")
					assertions.equal(context.player, expectedPlayer)
					assertions.notEqual(payload, input)
					assertions.isTrue(table.isfrozen(payload :: any))
					assertions.equal((payload :: any).value, 7)
					return ServerRequestDispatcher.success({ accepted = true })
				end
			)

			withRuntime({
				sender = function(
					remote: RemoteEvent,
					player: Player,
					envelope: ServerRequestDispatcher.ResponseEnvelope
				)
					table.insert(order, "send")
					assertions.equal(remote, expectedRemote)
					assertions.equal(player, expectedPlayer)
					assertions.equal((dispatcherRef :: Dispatcher):getStats().pendingRequestCount, 0)
					assertions.equal((dispatcherRef :: Dispatcher):getStats().completedRequestCount, 1)
					sentEnvelope = envelope
				end,
			}, function(state, player)
				dispatcherRef = state.dispatcher
				expectedPlayer = player
				startDispatcher(state, { contract })
				local remote = Instance.new("RemoteEvent") :: RemoteEvent
				expectedRemote = remote
				local idResult = RequestProtocol.createRequestId("Ordered01")
				assertions.isTrue(idResult.ok)
				local wireResult = RequestProtocol.buildRequest((idResult :: any).value, input)
				assertions.isTrue(wireResult.ok)
				state.dispatcher:dispatch(contract, remote, player, (wireResult :: any).value)
				input.value = 99
				assertions.equal(table.concat(order, ","), "authorize,handler,send")
				assertions.isNotNil(sentEnvelope)
				assertions.equal(responseCode(sentEnvelope :: ServerRequestDispatcher.ResponseEnvelope), "Success")
				assertions.isTrue(table.isfrozen(sentEnvelope :: any))
				remote:Destroy()
			end)
		end
	),

	TestHarness.case(
		"silently drops malformed IDs shapes hostile tables and extra arguments before limiting",
		function(assertions)
			local handlerCount = 0
			local metamethodCount = 0
			local contract = responseRequestContract(function(_context, _payload)
				handlerCount += 1
				return ServerRequestDispatcher.success({ accepted = true })
			end)
			withRuntime(nil, function(state, player)
				startDispatcher(state, { contract })
				local remote = Instance.new("RemoteEvent") :: RemoteEvent
				local hostile = setmetatable({ requestId = "Hostile01", payload = { value = 1 } }, {
					__index = function()
						metamethodCount += 1
						error(PRIVATE_SENTINEL, 0)
					end,
				})
				local malformed = {
					{},
					{ requestId = "short", payload = { value = 1 } },
					{ requestId = "Malformed01", payload = { value = 1 }, action = PRIVATE_SENTINEL },
					hostile,
				}
				for _, envelope in malformed do
					state.dispatcher:dispatch(contract, remote, player, envelope)
				end
				state.dispatcher:dispatch(contract, remote, player)
				state.dispatcher:dispatch(contract, remote, player, requestWire("TooMany01", 1), PRIVATE_SENTINEL)
				local notPlayer = Instance.new("Folder")
				state.dispatcher:dispatch(contract, remote, notPlayer, requestWire("NotPlayer", 1))
				notPlayer:Destroy()

				assertions.equal(handlerCount, 0)
				assertions.equal(metamethodCount, 0)
				assertions.equal(#state.sent, 0)
				assertions.equal(state.limiter:getStats().bucketCount, 0)
				assertions.equal(state.dispatcher:getStats().trackedPlayerCount, 0)
				assertions.equal(state.dispatcher:getStats().completedRequestCount, 0)
				remote:Destroy()
			end)
		end
	),

	TestHarness.case("completes rate rejections and later classifies their retained IDs as stale", function(assertions)
		local authorizationCount = 0
		local handlerCount = 0
		local contract = ServerRequestDispatcher.createRequestContract(
			REGISTRY,
			"Match",
			RESPONSE_REQUEST,
			PAYLOAD_SCHEMA,
			RESPONSE_SCHEMA,
			function(_context): boolean
				authorizationCount += 1
				return true
			end,
			function(_context, _payload)
				handlerCount += 1
				return ServerRequestDispatcher.success({ accepted = true })
			end
		)
		withRuntime({ policy = makePolicy(1, 1) }, function(state, player)
			startDispatcher(state, { contract })
			local remote = Instance.new("RemoteEvent") :: RemoteEvent
			state.dispatcher:dispatch(contract, remote, player, requestWire("Allowed01", 1))
			state.dispatcher:dispatch(contract, remote, player, requestWire("Limited01", 1))
			assertions.equal(authorizationCount, 1)
			assertions.equal(handlerCount, 1)
			assertions.equal(responseCode(state.sent[1].envelope), "Success")
			assertions.equal(responseCode(state.sent[2].envelope), "RATE_LIMITED")
			assertions.equal(state.dispatcher:getStats().completedRequestCount, 2)

			state.rateNow = 1
			state.dispatcher:dispatch(contract, remote, player, requestWire("Limited01", 1))
			assertions.equal(authorizationCount, 1)
			assertions.equal(handlerCount, 1)
			assertions.equal(responseCode(state.sent[3].envelope), "STALE_REQUEST")
			remote:Destroy()
		end)
	end),

	TestHarness.case(
		"consumes a limiter token for a reentrant in-flight duplicate and sends only the original",
		function(assertions)
			local handlerCount = 0
			local stateRef: any = nil
			local playerRef: Player? = nil
			local remote = Instance.new("RemoteEvent") :: RemoteEvent
			local contract: ServerRequestDispatcher.RequestContract
			contract = responseRequestContract(function(_context, _payload)
				handlerCount += 1
				if handlerCount == 1 then
					stateRef.dispatcher:dispatch(contract, remote, playerRef, requestWire("Reenter01", 1))
				end
				return ServerRequestDispatcher.success({ accepted = true })
			end)
			withRuntime({ policy = makePolicy(2, 1) }, function(state, player)
				stateRef = state
				playerRef = player
				startDispatcher(state, { contract })
				state.dispatcher:dispatch(contract, remote, player, requestWire("Reenter01", 1))
				assertions.equal(handlerCount, 1)
				assertions.equal(#state.sent, 1)
				assertions.equal(responseCode(state.sent[1].envelope), "Success")

				state.dispatcher:dispatch(contract, remote, player, requestWire("ThirdReq", 1))
				assertions.equal(handlerCount, 1)
				assertions.equal(responseCode(state.sent[2].envelope), "RATE_LIMITED")
			end)
			remote:Destroy()
		end
	),

	TestHarness.case("uses one global request-ID ledger per Player across fixed endpoints", function(assertions)
		local firstCount = 0
		local secondCount = 0
		local stateRef: any = nil
		local playerRef: Player? = nil
		local firstRemote = Instance.new("RemoteEvent") :: RemoteEvent
		local secondRemote = Instance.new("RemoteEvent") :: RemoteEvent
		local firstContract: ServerRequestDispatcher.RequestContract
		local secondContract: ServerRequestDispatcher.RequestContract
		secondContract = ServerRequestDispatcher.createRequestContract(
			REGISTRY,
			"Match",
			SECOND_RESPONSE_REQUEST,
			PAYLOAD_SCHEMA,
			RESPONSE_SCHEMA,
			function(_context): boolean
				return true
			end,
			function(_context, _payload)
				secondCount += 1
				return ServerRequestDispatcher.success({ accepted = true })
			end
		)
		firstContract = responseRequestContract(function(_context, _payload)
			firstCount += 1
			stateRef.dispatcher:dispatch(secondContract, secondRemote, playerRef, requestWire("GlobalId1", 2))
			return ServerRequestDispatcher.success({ accepted = true })
		end)

		withRuntime(nil, function(state, player)
			stateRef = state
			playerRef = player
			startDispatcher(state, { firstContract, secondContract })
			state.dispatcher:dispatch(firstContract, firstRemote, player, requestWire("GlobalId1", 1))
			assertions.equal(firstCount, 1)
			assertions.equal(secondCount, 0)
			assertions.equal(#state.sent, 1)

			state.dispatcher:dispatch(secondContract, secondRemote, player, requestWire("GlobalId1", 2))
			assertions.equal(secondCount, 0)
			assertions.equal(#state.sent, 2)
			assertions.equal(state.sent[2].remote, secondRemote)
			assertions.equal(responseCode(state.sent[2].envelope), "STALE_REQUEST")

			local otherPlayer = newPlayer()
			state.dispatcher:dispatch(secondContract, secondRemote, otherPlayer, requestWire("GlobalId1", 2))
			assertions.equal(secondCount, 1)
			assertions.equal(responseCode(state.sent[3].envelope), "Success")
			otherPlayer:Destroy()
		end)
		firstRemote:Destroy()
		secondRemote:Destroy()
	end),

	TestHarness.case("enforces the exact 32-pending boundary without invoking a 33rd handler", function(assertions)
		local handlerCount = 0
		local stateRef: any = nil
		local playerRef: Player? = nil
		local remote = Instance.new("RemoteEvent") :: RemoteEvent
		local contract: ServerRequestDispatcher.RequestContract
		contract = responseRequestContract(function(_context, payload)
			handlerCount += 1
			local value = (payload :: any).value :: number
			if value < 33 then
				if value == 32 then
					assertions.equal(stateRef.dispatcher:getStats().pendingRequestCount, 32)
				end
				stateRef.dispatcher:dispatch(
					contract,
					remote,
					playerRef,
					requestWire(string.format("Pending%03d", value + 1), value + 1)
				)
			end
			return ServerRequestDispatcher.success({ accepted = true })
		end)

		withRuntime(nil, function(state, player)
			stateRef = state
			playerRef = player
			startDispatcher(state, { contract })
			state.dispatcher:dispatch(contract, remote, player, requestWire("Pending001", 1))
			assertions.equal(handlerCount, ServerRequestDispatcher.MAX_PENDING_REQUESTS_PER_PLAYER)
			assertions.equal(#state.sent, 33)
			assertions.equal(responseCode(state.sent[1].envelope), "UNAVAILABLE")
			assertions.equal(state.dispatcher:getStats().pendingRequestCount, 0)
			assertions.equal(state.dispatcher:getStats().completedRequestCount, 33)
		end)
		remote:Destroy()
	end),

	TestHarness.case(
		"keeps a fixed 128-entry completion ring and treats count-evicted IDs as fresh",
		function(assertions)
			local handlerCount = 0
			local contract = responseRequestContract(function(_context, _payload)
				handlerCount += 1
				return ServerRequestDispatcher.success({ accepted = true })
			end)
			withRuntime(nil, function(state, player)
				startDispatcher(state, { contract })
				local remote = Instance.new("RemoteEvent") :: RemoteEvent
				for index = 1, 129 do
					state.rateNow = index
					state.dispatcher:dispatch(
						contract,
						remote,
						player,
						requestWire(string.format("History%03d", index), index)
					)
				end
				assertions.equal(handlerCount, 129)
				assertions.equal(state.dispatcher:getStats().completedRequestCount, 128)

				state.rateNow = 130
				state.dispatcher:dispatch(contract, remote, player, requestWire("History001", 1))
				assertions.equal(handlerCount, 130)
				assertions.equal(responseCode(state.sent[130].envelope), "Success")
				state.rateNow = 131
				state.dispatcher:dispatch(contract, remote, player, requestWire("History003", 3))
				assertions.equal(handlerCount, 130)
				assertions.equal(responseCode(state.sent[131].envelope), "STALE_REQUEST")
				assertions.equal(state.dispatcher:getStats().completedRequestCount, 128)
				remote:Destroy()
			end)
		end
	),

	TestHarness.case(
		"authorizes from server context before strict payload validation and feature mutation",
		function(assertions)
			local mode = "deny"
			local handlerCount = 0
			local contract = ServerRequestDispatcher.createRequestContract(
				REGISTRY,
				"Match",
				RESPONSE_REQUEST,
				PAYLOAD_SCHEMA,
				RESPONSE_SCHEMA,
				function(context): boolean
					assertions.isTrue(ServerRequestDispatcher.isContext(context))
					if mode == "throw" then
						error(PRIVATE_SENTINEL, 0)
					end
					return mode == "allow"
				end,
				function(_context, _payload)
					handlerCount += 1
					return ServerRequestDispatcher.success({ accepted = true })
				end
			)
			withRuntime(nil, function(state, player)
				startDispatcher(state, { contract })
				local remote = Instance.new("RemoteEvent") :: RemoteEvent
				state.dispatcher:dispatch(contract, remote, player, {
					requestId = "Denied001",
					payload = setmetatable({ value = PRIVATE_SENTINEL }, {
						__index = function()
							error(PRIVATE_SENTINEL, 0)
						end,
					}),
				})
				assertions.equal(responseCode(state.sent[1].envelope), "NOT_AUTHORIZED")
				assertions.equal(handlerCount, 0)

				mode = "throw"
				state.dispatcher:dispatch(contract, remote, player, requestWire("AuthThrow", 1))
				assertions.equal(responseCode(state.sent[2].envelope), "NOT_AUTHORIZED")
				mode = "allow"
				state.dispatcher:dispatch(contract, remote, player, {
					requestId = "Invalid01",
					payload = { value = PRIVATE_SENTINEL },
				})
				assertions.equal(responseCode(state.sent[3].envelope), "INVALID_PAYLOAD")
				local parsed = RequestProtocol.parseResponse(state.sent[3].envelope)
				assertions.isTrue(parsed.ok)
				if parsed.ok and parsed.value.state == "Rejected" then
					assertions.equal(
						(parsed.value.error.metadata :: RequestProtocol.PublicErrorMetadata).validationPath,
						"payload.value"
					)
				end
				assertions.equal(handlerCount, 0)
				remote:Destroy()
			end)
		end
	),

	TestHarness.case(
		"contains handler exceptions counterfeit outcomes rejections and invalid success payloads",
		function(assertions)
			local mode = "throw"
			local contract = responseRequestContract(function(_context, _payload): any
				if mode == "throw" then
					error(PRIVATE_SENTINEL, 0)
				elseif mode == "counterfeit" then
					return table.freeze({ kind = "Success", payload = PRIVATE_SENTINEL })
				elseif mode == "invalid-response" then
					return ServerRequestDispatcher.success({ accepted = PRIVATE_SENTINEL })
				elseif mode == "reject" then
					return ServerRequestDispatcher.reject(publicError("UNAVAILABLE"))
				end
				return ServerRequestDispatcher.success({ accepted = true })
			end)
			withRuntime(nil, function(state, player)
				startDispatcher(state, { contract })
				local remote = Instance.new("RemoteEvent") :: RemoteEvent
				local expectations = {
					{ mode = "throw", code = "INTERNAL_ERROR" },
					{ mode = "counterfeit", code = "INTERNAL_ERROR" },
					{ mode = "invalid-response", code = "INTERNAL_ERROR" },
					{ mode = "reject", code = "UNAVAILABLE" },
				}
				for index, expectation in expectations do
					mode = expectation.mode
					state.rateNow = index
					state.dispatcher:dispatch(
						contract,
						remote,
						player,
						requestWire(string.format("Failure%02d", index), index)
					)
					assertions.equal(responseCode(state.sent[index].envelope), expectation.code)
					assertGraphDoesNotRetain(assertions, state.sent[index].envelope, PRIVATE_SENTINEL)
				end
				assertions.equal(state.dispatcher:getStats().completedRequestCount, 4)
				assertions.equal(#state.reports, 1)
				assertAggregateReport(assertions, state.reports[1], "HANDLER_FAILED", player, "Failure01")
				remote:Destroy()
			end)
		end
	),

	TestHarness.case(
		"handles Events and no-response Requests without allocating or sending response state",
		function(assertions)
			local eventCount = 0
			local requestCount = 0
			local eventContract = ServerRequestDispatcher.createEventContract(
				REGISTRY,
				"Match",
				CLIENT_EVENT,
				PAYLOAD_SCHEMA,
				function(_context): boolean
					return true
				end,
				function(_context, payload)
					eventCount += 1
					assertions.isTrue(table.isfrozen(payload :: any))
					return ServerRequestDispatcher.success(nil)
				end
			)
			local noResponseContract = ServerRequestDispatcher.createRequestContract(
				REGISTRY,
				"Match",
				NO_RESPONSE_REQUEST,
				PAYLOAD_SCHEMA,
				nil,
				function(_context): boolean
					return true
				end,
				function(_context, _payload)
					requestCount += 1
					return ServerRequestDispatcher.success(nil)
				end
			)
			withRuntime(nil, function(state, player)
				startDispatcher(state, { eventContract, noResponseContract })
				state.dispatcher:dispatch(eventContract, nil, player, eventWire(1))
				state.dispatcher:dispatch(eventContract, nil, player, eventWire(2), PRIVATE_SENTINEL)
				local wrongRemote = Instance.new("RemoteEvent") :: RemoteEvent
				state.dispatcher:dispatch(eventContract, wrongRemote, player, eventWire(3))
				state.dispatcher:dispatch(noResponseContract, nil, player, requestWire("NoReply01", 4))
				state.dispatcher:dispatch(noResponseContract, nil, player, requestWire("NoReply01", 4))

				assertions.equal(eventCount, 1)
				assertions.equal(requestCount, 1)
				assertions.equal(#state.sent, 0)
				assertions.equal(state.dispatcher:getStats().completedRequestCount, 1)
				wrongRemote:Destroy()
			end)
		end
	),

	TestHarness.case("completes before a narrow origin-only sender and contains sender failure", function(assertions)
		local dispatcherRef: Dispatcher? = nil
		local expectedPlayer: Player? = nil
		local expectedRemote: RemoteEvent? = nil
		local sendCount = 0
		local handlerCount = 0
		local contract = responseRequestContract(function(_context, _payload)
			handlerCount += 1
			return ServerRequestDispatcher.success({ accepted = true })
		end)
		withRuntime({
			sender = function(remote: RemoteEvent, player: Player, envelope: ServerRequestDispatcher.ResponseEnvelope)
				sendCount += 1
				assertions.equal(remote, expectedRemote)
				assertions.equal(player, expectedPlayer)
				assertions.isTrue(table.isfrozen(envelope :: any))
				assertions.equal((dispatcherRef :: Dispatcher):getStats().pendingRequestCount, 0)
				assertions.equal((dispatcherRef :: Dispatcher):getStats().completedRequestCount, 1)
				error(PRIVATE_SENTINEL, 0)
			end,
		}, function(state, player)
			dispatcherRef = state.dispatcher
			expectedPlayer = player
			startDispatcher(state, { contract })
			local remote = Instance.new("RemoteEvent") :: RemoteEvent
			expectedRemote = remote
			state.dispatcher:dispatch(contract, remote, player, requestWire("SendFail1", 1))
			assertions.equal(handlerCount, 1)
			assertions.equal(sendCount, 1)
			assertions.equal(state.dispatcher:getStats().responseSendFailureCount, 1)
			assertions.equal(#state.reports, 1)
			assertAggregateReport(assertions, state.reports[1], "RESPONSE_SEND_FAILED", player, "SendFail1")
			state.dispatcher:dispatch(contract, remote, player, requestWire("SendFail1", 1))
			assertions.equal(handlerCount, 1)
			assertions.equal(sendCount, 2)
			assertions.equal(state.dispatcher:getStats().completedRequestCount, 1)
			remote:Destroy()
		end)
	end),

	TestHarness.case("clears exact Player state on removal and contains removal during a handler", function(assertions)
		local stateRef: any = nil
		local contract = responseRequestContract(function(_context, payload)
			if (payload :: any).value == 2 then
				stateRef.dispatcherConnection.handler(stateRef.player)
			end
			return ServerRequestDispatcher.success({ accepted = true })
		end)
		withRuntime(nil, function(state, player)
			stateRef = state
			stateRef.player = player
			startDispatcher(state, { contract })
			local remote = Instance.new("RemoteEvent") :: RemoteEvent
			state.dispatcher:dispatch(contract, remote, player, requestWire("Cleanup01", 1))
			assertions.equal(state.dispatcher:getStats().trackedPlayerCount, 1)
			state.dispatcherConnection.handler(player)
			assertions.equal(state.dispatcher:getStats().trackedPlayerCount, 0)
			assertions.equal(state.dispatcher:getStats().completedRequestCount, 0)
			state.dispatcher:dispatch(contract, remote, player, requestWire("Cleanup02", 1))
			assertions.equal(#state.sent, 1)

			local secondPlayer = newPlayer()
			stateRef.player = secondPlayer
			state.dispatcher:dispatch(contract, remote, secondPlayer, requestWire("MidLeave1", 2))
			assertions.equal(state.dispatcher:getStats().trackedPlayerCount, 0)
			assertions.equal(state.dispatcher:getStats().pendingRequestCount, 0)
			assertions.equal(state.dispatcher:getStats().completedRequestCount, 0)
			assertions.equal(#state.sent, 1)
			secondPlayer:Destroy()
			remote:Destroy()
		end)
	end),

	TestHarness.case("contains Player removal and dispatcher cleanup during authorization", function(assertions)
		local removalState: any = nil
		local removalMutationCount = 0
		local removalContract = ServerRequestDispatcher.createRequestContract(
			REGISTRY,
			"Match",
			RESPONSE_REQUEST,
			PAYLOAD_SCHEMA,
			RESPONSE_SCHEMA,
			function(context): boolean
				removalState.dispatcherConnection.handler(context.player)
				return true
			end,
			function(_context, _payload)
				removalMutationCount += 1
				return ServerRequestDispatcher.success({ accepted = true })
			end
		)
		withRuntime(nil, function(state, player)
			removalState = state
			startDispatcher(state, { removalContract })
			local remote = Instance.new("RemoteEvent") :: RemoteEvent
			state.dispatcher:dispatch(removalContract, remote, player, requestWire("AuthLeave1", 1))
			assertions.equal(removalMutationCount, 0)
			assertions.equal(#state.sent, 0)
			assertions.equal(state.dispatcher:getStats().trackedPlayerCount, 0)
			assertions.equal(state.dispatcher:getStats().pendingRequestCount, 0)
			assertions.equal(state.dispatcher:getStats().completedRequestCount, 0)
			remote:Destroy()
		end)

		local cleanupState: any = nil
		local cleanupMutationCount = 0
		local cleanupContract = ServerRequestDispatcher.createRequestContract(
			REGISTRY,
			"Match",
			RESPONSE_REQUEST,
			PAYLOAD_SCHEMA,
			RESPONSE_SCHEMA,
			function(_context): boolean
				cleanupState.dispatcherCleanup:cleanup()
				return true
			end,
			function(_context, _payload)
				cleanupMutationCount += 1
				return ServerRequestDispatcher.success({ accepted = true })
			end
		)
		withRuntime(nil, function(state, player)
			cleanupState = state
			startDispatcher(state, { cleanupContract })
			local remote = Instance.new("RemoteEvent") :: RemoteEvent
			state.dispatcher:dispatch(cleanupContract, remote, player, requestWire("AuthStop1", 1))
			assertions.equal(cleanupMutationCount, 0)
			assertions.equal(#state.sent, 0)
			assertions.equal(state.dispatcher:getState(), "Shutdown")
			assertions.equal(state.dispatcher:getStats().trackedPlayerCount, 0)
			assertions.equal(state.dispatcher:getStats().pendingRequestCount, 0)
			assertions.equal(state.dispatcher:getStats().completedRequestCount, 0)
			remote:Destroy()
		end)
	end),

	TestHarness.case("owns lifecycle cleanup and exposes frozen identity-free bounded stats", function(assertions)
		local handlerCount = 0
		local contract = responseRequestContract(function(_context, _payload)
			handlerCount += 1
			return ServerRequestDispatcher.success({ accepted = true })
		end)
		withRuntime(nil, function(state, player)
			state.dispatcher:registerContract(contract)
			assertions.equal(state.dispatcher:getState(), "Registering")
			state.dispatcherCleanup = state.dispatcher:initialize()
			assertions.equal(state.dispatcher:getState(), "Initialized")
			local remote = Instance.new("RemoteEvent") :: RemoteEvent
			state.dispatcher:dispatch(contract, remote, player, requestWire("BeforeStart1", 1))
			assertions.equal(handlerCount, 0)
			assertions.equal(#state.sent, 1)
			assertions.equal(responseCode(state.sent[1].envelope), "UNAVAILABLE")
			state.dispatcher:start()
			assertions.equal(state.dispatcher:getState(), "Started")
			state.dispatcher:dispatch(contract, remote, player, requestWire("StatsReq1", 1))
			assertions.equal(handlerCount, 1)
			assertions.equal(#state.sent, 2)
			assertions.equal(responseCode(state.sent[2].envelope), "Success")
			local stats = state.dispatcher:getStats()
			assertions.isTrue(table.isfrozen(stats))
			assertions.equal(stats.registeredContractCount, 1)
			assertions.equal(stats.trackedPlayerCount, 1)
			assertions.equal(stats.completedRequestCount, 2)
			assertGraphDoesNotRetain(assertions, stats, player)
			assertGraphDoesNotRetain(assertions, stats, "BeforeStart1")
			assertGraphDoesNotRetain(assertions, stats, "StatsReq1")

			state.dispatcherCleanup:cleanup()
			assertions.equal(state.dispatcher:getState(), "Shutdown")
			assertions.equal(state.dispatcherConnection.disconnectCount, 1)
			local cleared = state.dispatcher:getStats()
			assertions.equal(cleared.trackedPlayerCount, 0)
			assertions.equal(cleared.pendingRequestCount, 0)
			assertions.equal(cleared.completedRequestCount, 0)
			remote:Destroy()
		end)
	end),

	TestHarness.case(
		"contains limiter and protocol reporter cleanup re-entry without reviving state",
		function(assertions)
			local handlerCount = 0
			local contract = responseRequestContract(function(_context, _payload)
				handlerCount += 1
				return ServerRequestDispatcher.success({ accepted = true })
			end)

			local limiterState: any = nil
			withRuntime({
				policy = makePolicy(1, 0.01),
				limiterReporter = function(_report)
					limiterState.dispatcherCleanup:cleanup()
				end,
			}, function(state, player)
				limiterState = state
				startDispatcher(state, { contract })
				local remote = Instance.new("RemoteEvent") :: RemoteEvent
				state.dispatcher:dispatch(contract, remote, player, requestWire("LimiterGood1", 1))
				state.dispatcher:dispatch(contract, remote, player, requestWire("LimiterStop1", 1))
				assertions.equal(handlerCount, 1)
				assertions.equal(#state.sent, 1)
				assertions.equal(responseCode(state.sent[1].envelope), "Success")
				assertions.equal(state.dispatcher:getState(), "Shutdown")
				assertions.equal(state.dispatcher:getStats().trackedPlayerCount, 0)
				assertions.equal(state.dispatcher:getStats().completedRequestCount, 0)
				remote:Destroy()
			end)

			local protocolState: any = nil
			withRuntime({
				reporter = function(_report)
					protocolState.dispatcherCleanup:cleanup()
				end,
			}, function(state, player)
				protocolState = state
				startDispatcher(state, { contract })
				local remote = Instance.new("RemoteEvent") :: RemoteEvent
				state.dispatcher:dispatch(contract, remote, player, requestWire("ProtocolStop1", 1))
				state.dispatcher:dispatch(contract, remote, player, requestWire("ProtocolStop1", 1))
				assertions.equal(handlerCount, 2)
				assertions.equal(#state.sent, 1)
				assertions.equal(responseCode(state.sent[1].envelope), "Success")
				assertions.equal(state.dispatcher:getState(), "Shutdown")
				assertions.equal(state.dispatcher:getStats().pendingProtocolRejectionCount, 0)
				assertions.equal(state.dispatcher:getStats().completedRequestCount, 0)
				remote:Destroy()
			end)
		end
	),

	TestHarness.case(
		"aggregates protocol signals with ULP-safe cadence and privacy-safe frozen reports",
		function(assertions)
			local mode = "deny"
			local contract = ServerRequestDispatcher.createRequestContract(
				REGISTRY,
				"Match",
				RESPONSE_REQUEST,
				PAYLOAD_SCHEMA,
				RESPONSE_SCHEMA,
				function(_context): boolean
					return mode == "allow"
				end,
				function(_context, _payload)
					return ServerRequestDispatcher.success({ accepted = true })
				end
			)
			local eventContract = ServerRequestDispatcher.createEventContract(
				REGISTRY,
				"Match",
				CLIENT_EVENT,
				PAYLOAD_SCHEMA,
				function(_context): boolean
					return true
				end,
				function(_context, _payload)
					return ServerRequestDispatcher.success(nil)
				end
			)
			withRuntime(nil, function(state, player)
				startDispatcher(state, { contract, eventContract })
				local remote = Instance.new("RemoteEvent") :: RemoteEvent
				state.observationNow = 1e30
				state.dispatcher:dispatch(contract, remote, player, { private = PRIVATE_SENTINEL })
				assertions.equal(#state.reports, 1)
				assertions.isTrue(table.isfrozen(state.reports[1]))
				assertions.equal(state.reports[1].code, "MALFORMED_ENVELOPE")
				assertions.equal(state.reports[1].protocolRejectionCount, 1)
				assertions.equal(state.reports[1].protocolWindowSeconds, 10)

				state.dispatcher:dispatch(contract, remote, player, { private = PRIVATE_SENTINEL })
				state.dispatcher:dispatch(eventContract, nil, player, { private = PRIVATE_SENTINEL })
				state.dispatcher:dispatch(contract, remote, player, requestWire("DeniedAgg", 1))
				assertions.equal(#state.reports, 1)
				state.observationNow = 2e30
				state.dispatcher:dispatch(contract, remote, player, { private = PRIVATE_SENTINEL })
				assertions.equal(#state.reports, 2)
				assertions.equal(state.reports[2].code, "MULTIPLE_SIGNALS")
				assertions.equal(state.reports[2].endpoint, "<multiple>")
				assertions.equal(state.reports[2].protocolRejectionCount, 4)

				for _ = 1, ServerRequestDispatcher.MAX_AGGREGATE_SIGNALS + 5 do
					state.dispatcher:dispatch(contract, remote, player, { private = PRIVATE_SENTINEL })
				end
				assertions.equal(
					state.dispatcher:getStats().pendingProtocolRejectionCount,
					ServerRequestDispatcher.MAX_AGGREGATE_SIGNALS
				)
				state.observationNow = 3e30
				state.dispatcher:dispatch(contract, remote, player, { private = PRIVATE_SENTINEL })
				assertions.equal(#state.reports, 3)
				assertions.equal(state.reports[3].protocolRejectionCount, ServerRequestDispatcher.MAX_AGGREGATE_SIGNALS)
				for _, report in state.reports do
					assertGraphDoesNotRetain(assertions, report, PRIVATE_SENTINEL)
					assertGraphDoesNotRetain(assertions, report, player)
				end
				remote:Destroy()
			end)
		end
	),

	TestHarness.case(
		"contains observation-clock and reporter failures without changing dispatch results or cadence",
		function(assertions)
			local clockMode = "throw"
			local now = 0
			local reportCount = 0
			local contract = responseRequestContract(function(_context, _payload)
				return ServerRequestDispatcher.success({ accepted = true })
			end)
			withRuntime({
				clock = function(): number
					if clockMode == "throw" then
						error(PRIVATE_SENTINEL, 0)
					elseif clockMode == "nan" then
						return 0 / 0
					end
					return now
				end,
				reporter = function(report)
					reportCount += 1
					assertGraphDoesNotRetain(assertions, report, PRIVATE_SENTINEL)
					error(PRIVATE_SENTINEL, 0)
				end,
			}, function(state, player)
				startDispatcher(state, { contract })
				local remote = Instance.new("RemoteEvent") :: RemoteEvent
				state.dispatcher:dispatch(contract, remote, player, { private = PRIVATE_SENTINEL })
				clockMode = "nan"
				state.dispatcher:dispatch(contract, remote, player, { private = PRIVATE_SENTINEL })
				assertions.equal(reportCount, 0)
				assertions.equal(state.dispatcher:getStats().observationClockFailureCount, 2)

				clockMode = "valid"
				now = 0
				state.dispatcher:dispatch(contract, remote, player, { private = PRIVATE_SENTINEL })
				assertions.equal(reportCount, 1)
				assertions.equal(state.dispatcher:getStats().reportFailureCount, 1)
				now = -1
				state.dispatcher:dispatch(contract, remote, player, { private = PRIVATE_SENTINEL })
				assertions.equal(reportCount, 1)
				assertions.equal(state.dispatcher:getStats().observationClockFailureCount, 3)
				now = 0
				state.dispatcher:dispatch(contract, remote, player, { private = PRIVATE_SENTINEL })
				assertions.equal(reportCount, 1)
				now = 10
				state.dispatcher:dispatch(contract, remote, player, { private = PRIVATE_SENTINEL })
				assertions.equal(reportCount, 2)
				assertions.equal(state.dispatcher:getStats().reportFailureCount, 2)

				state.rateNow = 1
				state.dispatcher:dispatch(contract, remote, player, requestWire("StillGood", 1))
				assertions.equal(#state.sent, 1)
				assertions.equal(responseCode(state.sent[1].envelope), "Success")
				remote:Destroy()
			end)
		end
	),
})
