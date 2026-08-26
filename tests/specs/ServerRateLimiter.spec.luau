--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local NetworkFixtures = require(script.Parent.Parent.Fixtures.NetworkFixtures)
local ServerRateLimiter = require(script.Parent.Parent.ProductionServerNetworking.ServerRateLimiter)

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage").Shared
local RemoteRegistry = require(Shared.network.RemoteRegistry)
local EnvironmentContext = require(Shared.logging.EnvironmentContext)
local Log = require(Shared.logging.Log)

type Assertions = TestHarness.Assertions
type Registry = RemoteRegistry.Registry
type RuntimePlaceRole = RemoteRegistry.RuntimePlaceRole
type Definition = RemoteRegistry.Definition
type Policy = ServerRateLimiter.Policy
type PolicySet = ServerRateLimiter.PolicySet
type Limiter = ServerRateLimiter.Limiter
type Decision = ServerRateLimiter.Decision

local PRIVATE_SENTINEL = "PRIVATE_RATE_LIMIT_SENTINEL_d91f"
local playerSequence = 0

local function loggerFor(role: RuntimePlaceRole): Log.Logger
	return Log.new(EnvironmentContext.new("server", role, 0, false))
end

local function makeRegistry(definitions: unknown): Registry
	local result = RemoteRegistry.create(definitions)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=REGISTRY_CREATION_FAILED]", 0)
	end
	return result.value
end

local FULL_REGISTRY = makeRegistry(NetworkFixtures.validDefinitions())
local EMPTY_REGISTRY = makeRegistry({})

local function requireDefinition(registry: Registry, endpoint: string): Definition
	local definition = registry:get(endpoint)
	if definition == nil then
		error("[ATD_TEST_FIXTURE][code=DEFINITION_MISSING]", 0)
	end
	return definition
end

local CLIENT_EVENT = requireDefinition(FULL_REGISTRY, "TestClientEvent")
local NO_RESPONSE_REQUEST = requireDefinition(FULL_REGISTRY, "TestNoResponseRequest")
local SERVER_EVENT = requireDefinition(FULL_REGISTRY, "TestServerEvent")

local function expectPolicyError(
	assertions: Assertions,
	result: any,
	code: ServerRateLimiter.PolicyErrorCode,
	path: string?
): ServerRateLimiter.PolicyError
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local policyError = result.error :: ServerRateLimiter.PolicyError
	assertions.equal(policyError.code, code)
	if path ~= nil then
		assertions.equal(policyError.path, path)
	end
	assertions.isTrue(type(policyError.message) == "string" and #policyError.message > 0)
	assertions.isTrue(table.isfrozen(policyError))
	return policyError
end

local function makePolicy(capacity: number, refillPerSecond: number): Policy
	local result = ServerRateLimiter.createPolicy(capacity, refillPerSecond)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=POLICY_CREATION_FAILED]", 0)
	end
	return result.value
end

local function bindingsFor(registry: Registry, policy: Policy): { ServerRateLimiter.PolicyBinding }
	local bindings = {}
	for _, definition in registry:list() do
		if definition.direction == "ClientToServer" then
			table.insert(bindings, {
				endpoint = definition.name,
				policy = policy,
			})
		end
	end
	return bindings
end

local function makePolicySet(registry: Registry, role: RuntimePlaceRole, policy: Policy?): PolicySet
	local result = ServerRateLimiter.createPolicySet(
		registry,
		role,
		bindingsFor(registry, policy or ServerRateLimiter.DEFAULT_POLICY)
	)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=POLICY_SET_CREATION_FAILED]", 0)
	end
	return result.value
end

local function captureError(assertions: Assertions, callback: () -> ()): string
	local succeeded, failure = pcall(callback)
	assertions.isFalse(succeeded)
	assertions.equal(type(failure), "string")
	return if type(failure) == "string" then failure else ""
end

local function assertErrorCode(assertions: Assertions, failure: string, code: string)
	assertions.contains(failure, `[code={code}]`)
end

local function assertDecision(assertions: Assertions, decision: Decision, code: ServerRateLimiter.DecisionCode)
	assertions.equal(decision.code, code)
	assertions.equal(decision.allowed, code == "ALLOWED")
	assertions.isTrue(table.isfrozen(decision))
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

local function newPlayer(): Player
	playerSequence += 1
	local player = Instance.new("Player") :: Player
	player.Name = `RateLimiterPlayer{playerSequence}`
	player.Parent = Players
	return player
end

local function withPlayers(count: number, callback: ({ Player }) -> ())
	local players = {}
	for _ = 1, count do
		table.insert(players, newPlayer())
	end

	local succeeded, failure = pcall(callback, players)
	for index = #players, 1, -1 do
		pcall(function()
			players[index]:Destroy()
		end)
	end
	if not succeeded then
		error(failure, 0)
	end
end

local function makeConnectorState(): any
	local state = {
		connectCount = 0,
		disconnectCount = 0,
		handler = nil,
	}
	state.connector = function(handler: ServerRateLimiter.PlayerRemovingHandler): RBXScriptConnection
		state.connectCount += 1
		state.handler = handler
		return RobloxAdapter.createConnection(function()
			state.disconnectCount += 1
		end) :: any
	end
	return state
end

local function startLimiter(
	policySet: PolicySet,
	clock: ServerRateLimiter.Clock,
	reporter: ServerRateLimiter.Reporter?
): (Limiter, any, any)
	local connectorState = makeConnectorState()
	local selectedReporter: ServerRateLimiter.Reporter = reporter or function(_report) end
	local limiter =
		ServerRateLimiter.new(loggerFor("Match"), Players, policySet, clock, connectorState.connector, selectedReporter)
	local cleanup = limiter:initialize()
	limiter:start()
	return limiter, cleanup, connectorState
end

local function reverseBindings(bindings: { ServerRateLimiter.PolicyBinding }): { ServerRateLimiter.PolicyBinding }
	local reversed = {}
	for index = #bindings, 1, -1 do
		table.insert(reversed, bindings[index])
	end
	return reversed
end

return TestHarness.suite("server authoritative rate limiter", {
	TestHarness.case("authenticates freezes and validates default and exact-bound policies", function(assertions)
		assertions.isTrue(table.isfrozen(ServerRateLimiter))
		assertions.isTrue(table.isfrozen(ServerRateLimiter.DEFAULT_POLICY))
		assertions.isTrue(ServerRateLimiter.isPolicy(ServerRateLimiter.DEFAULT_POLICY))
		assertions.equal(ServerRateLimiter.DEFAULT_POLICY.capacity, ServerRateLimiter.DEFAULT_CAPACITY)
		assertions.equal(ServerRateLimiter.DEFAULT_POLICY.refillPerSecond, ServerRateLimiter.DEFAULT_REFILL_PER_SECOND)

		local minimumResult =
			ServerRateLimiter.createPolicy(ServerRateLimiter.MIN_CAPACITY, ServerRateLimiter.MIN_REFILL_PER_SECOND)
		assertions.isTrue(minimumResult.ok)
		assertions.isTrue(table.isfrozen(minimumResult))
		local minimum = (minimumResult :: any).value :: Policy
		assertions.equal(minimum.capacity, ServerRateLimiter.MIN_CAPACITY)
		assertions.equal(minimum.refillPerSecond, ServerRateLimiter.MIN_REFILL_PER_SECOND)
		assertions.isTrue(table.isfrozen(minimum))
		assertions.isTrue(ServerRateLimiter.isPolicy(minimum))

		local maximumResult =
			ServerRateLimiter.createPolicy(ServerRateLimiter.MAX_CAPACITY, ServerRateLimiter.MAX_REFILL_PER_SECOND)
		assertions.isTrue(maximumResult.ok)
		local maximum = (maximumResult :: any).value :: Policy
		assertions.equal(maximum.capacity, ServerRateLimiter.MAX_CAPACITY)
		assertions.equal(maximum.refillPerSecond, ServerRateLimiter.MAX_REFILL_PER_SECOND)

		local mutationSucceeded = pcall(function()
			(minimum :: any).capacity = 2
		end)
		assertions.isFalse(mutationSucceeded)
		assertions.isFalse(ServerRateLimiter.isPolicy(table.freeze({
			capacity = minimum.capacity,
			refillPerSecond = minimum.refillPerSecond,
		})))
	end),

	TestHarness.case("rejects malformed policy numbers without coercion or private echo", function(assertions)
		local invalidCapacities: { unknown } = {
			PRIVATE_SENTINEL,
			0,
			ServerRateLimiter.MAX_CAPACITY + 1,
			1.5,
			0 / 0,
			math.huge,
			-math.huge,
		}
		for _, capacity in invalidCapacities do
			local policyError = expectPolicyError(
				assertions,
				ServerRateLimiter.createPolicy(capacity, ServerRateLimiter.DEFAULT_REFILL_PER_SECOND),
				"INVALID_CAPACITY",
				"policy.capacity"
			)
			assertions.isNil(string.find(policyError.message, PRIVATE_SENTINEL, 1, true))
		end

		local invalidRefills: { unknown } = {
			PRIVATE_SENTINEL,
			0,
			ServerRateLimiter.MIN_REFILL_PER_SECOND / 2,
			ServerRateLimiter.MAX_REFILL_PER_SECOND + 1,
			0 / 0,
			math.huge,
			-math.huge,
		}
		for _, refill in invalidRefills do
			local policyError = expectPolicyError(
				assertions,
				ServerRateLimiter.createPolicy(ServerRateLimiter.DEFAULT_CAPACITY, refill),
				"INVALID_REFILL",
				"policy.refillPerSecond"
			)
			assertions.isNil(string.find(policyError.message, PRIVATE_SENTINEL, 1, true))
		end
	end),

	TestHarness.case("builds globally complete canonical policy sets with exact role filtering", function(assertions)
		local custom = makePolicy(7, 1.25)
		local authored = reverseBindings(bindingsFor(FULL_REGISTRY, custom))
		local developmentResult = ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Development", authored)
		assertions.isTrue(developmentResult.ok)
		assertions.isTrue(table.isfrozen(developmentResult))
		local development = (developmentResult :: any).value :: PolicySet
		assertions.isTrue(ServerRateLimiter.isPolicySet(development))
		assertions.isTrue(table.isfrozen(development))
		assertions.equal(development:count(), 3)
		assertions.equal(development:activeCount(), 3)
		assertions.isTrue(table.isfrozen(development:list()))
		assertions.isTrue(table.isfrozen(development:listActive()))
		assertions.equal(
			table.concat({
				development:list()[1].endpoint,
				development:list()[2].endpoint,
				development:list()[3].endpoint,
			}, ","),
			"TestClientEvent,TestNoResponseRequest,TestResponseRequest"
		)
		for _, binding in development:list() do
			assertions.isTrue(table.isfrozen(binding))
			assertions.equal(binding.policy, custom)
		end

		authored[1].endpoint = PRIVATE_SENTINEL
		assertions.equal(development:list()[1].endpoint, "TestClientEvent")

		local lobby = makePolicySet(FULL_REGISTRY, "Lobby", custom)
		assertions.equal(lobby:count(), 3)
		assertions.equal(lobby:activeCount(), 1)
		assertions.equal(lobby:listActive()[1].endpoint, "TestResponseRequest")

		local match = makePolicySet(FULL_REGISTRY, "Match", custom)
		assertions.equal(match:count(), 3)
		assertions.equal(match:activeCount(), 3)

		local empty = makePolicySet(EMPTY_REGISTRY, "Development", custom)
		assertions.equal(empty:count(), 0)
		assertions.equal(empty:activeCount(), 0)

		local missingGlobalPolicy = bindingsFor(FULL_REGISTRY, custom)
		table.remove(missingGlobalPolicy, 1)
		expectPolicyError(
			assertions,
			ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Lobby", missingGlobalPolicy),
			"MISSING_POLICY",
			"policies"
		)
		expectPolicyError(
			assertions,
			ServerRateLimiter.createPolicySet({} :: any, "Match", {}),
			"INVALID_REGISTRY",
			"registry"
		)
		expectPolicyError(
			assertions,
			ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Private" :: any, bindingsFor(FULL_REGISTRY, custom)),
			"INVALID_ROLE",
			"role"
		)
	end),

	TestHarness.case(
		"rejects sparse hostile malformed unknown wrong-direction and duplicate bindings privately",
		function(assertions)
			local policy = makePolicy(2, 1)
			local valid = bindingsFor(FULL_REGISTRY, policy)
			expectPolicyError(
				assertions,
				ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Match", PRIVATE_SENTINEL),
				"INVALID_POLICY_LIST",
				"policies"
			)
			expectPolicyError(
				assertions,
				ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Match", { [1] = valid[1], [3] = valid[2] }),
				"INVALID_POLICY_LIST",
				"policies"
			)
			expectPolicyError(
				assertions,
				ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Match", { [0] = valid[1] }),
				"INVALID_POLICY_LIST",
				"policies"
			)

			local invocationCount = 0
			local hostileMetatable = {
				__index = function()
					invocationCount += 1
					return PRIVATE_SENTINEL
				end,
				__len = function()
					invocationCount += 1
					return 3
				end,
				__pairs = function()
					invocationCount += 1
					return next, {}, nil
				end,
				__iter = function()
					invocationCount += 1
					return next, {}, nil
				end,
				__tostring = function()
					invocationCount += 1
					return PRIVATE_SENTINEL
				end,
				__eq = function()
					invocationCount += 1
					return true
				end,
				__metatable = "locked",
			}
			local hostileList = setmetatable({}, hostileMetatable)
			expectPolicyError(
				assertions,
				ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Match", hostileList),
				"INVALID_POLICY_LIST",
				"policies"
			)
			local hostileBinding = setmetatable({ endpoint = "TestClientEvent", policy = policy }, hostileMetatable)
			expectPolicyError(
				assertions,
				ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Match", { hostileBinding }),
				"INVALID_POLICY_BINDING",
				"policies[1]"
			)
			assertions.equal(invocationCount, 0)

			local malformedBindings = {
				{ value = 1 },
				{ endpoint = "TestClientEvent" },
				{ policy = policy },
				{ endpoint = "TestClientEvent", policy = {} },
				{ endpoint = "TestClientEvent", policy = policy, extra = PRIVATE_SENTINEL },
				{ endpoint = "TestClientEvent", policy = policy, [1] = PRIVATE_SENTINEL },
			}
			for _, binding in malformedBindings do
				expectPolicyError(
					assertions,
					ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Match", { binding }),
					"INVALID_POLICY_BINDING"
				)
			end

			local unknown = bindingsFor(FULL_REGISTRY, policy)
			unknown[1].endpoint = PRIVATE_SENTINEL
			local unknownError = expectPolicyError(
				assertions,
				ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Match", unknown),
				"UNKNOWN_ENDPOINT",
				"policies[1].endpoint"
			)
			assertions.isNil(string.find(unknownError.message, PRIVATE_SENTINEL, 1, true))
			assertGraphDoesNotRetain(assertions, unknownError, PRIVATE_SENTINEL)

			local wrongDirection = bindingsFor(FULL_REGISTRY, policy)
			table.insert(wrongDirection, { endpoint = "TestServerEvent", policy = policy })
			expectPolicyError(
				assertions,
				ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Match", wrongDirection),
				"WRONG_DIRECTION",
				"policies[4].endpoint"
			)

			local duplicate = bindingsFor(FULL_REGISTRY, policy)
			table.insert(duplicate, { endpoint = duplicate[1].endpoint, policy = policy })
			expectPolicyError(
				assertions,
				ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Match", duplicate),
				"DUPLICATE_POLICY",
				"policies[4].endpoint"
			)
		end
	),

	TestHarness.case("accepts exactly 128 global bindings and rejects 129 before traversal", function(assertions)
		local definitions = {}
		for index = 1, RemoteRegistry.MAX_DEFINITIONS do
			local definition = NetworkFixtures.clientEventDefinition()
			definition.name = string.format("TestRate%03d", index)
			table.insert(definitions, definition)
		end
		local registry = makeRegistry(definitions)
		local bindings = bindingsFor(registry, ServerRateLimiter.DEFAULT_POLICY)
		local exactResult = ServerRateLimiter.createPolicySet(registry, "Match", bindings)
		assertions.isTrue(exactResult.ok)
		assertions.equal((exactResult :: any).value:count(), RemoteRegistry.MAX_DEFINITIONS)

		bindings[RemoteRegistry.MAX_DEFINITIONS + 1] = {
			endpoint = PRIVATE_SENTINEL,
			policy = ServerRateLimiter.DEFAULT_POLICY,
		}
		expectPolicyError(
			assertions,
			ServerRateLimiter.createPolicySet(registry, "Match", bindings),
			"TOO_MANY_POLICIES",
			"policies"
		)
	end),

	TestHarness.case("enforces construction provenance and lifecycle state ownership", function(assertions)
		local policySet = makePolicySet(FULL_REGISTRY, "Match")
		local clockReads = 0
		local connectorState = makeConnectorState()
		local limiter = ServerRateLimiter.new(loggerFor("Match"), Players, policySet, function()
			clockReads += 1
			return 0
		end, connectorState.connector, function(_report) end)
		assertions.isTrue(ServerRateLimiter.isLimiter(limiter))
		assertions.isTrue(table.isfrozen(limiter))
		assertions.equal(limiter:getState(), "Registering")
		assertDecision(assertions, limiter:consume({} :: any, CLIENT_EVENT), "UNAVAILABLE")
		assertions.equal(clockReads, 0)

		assertErrorCode(
			assertions,
			captureError(assertions, function()
				limiter:start()
			end),
			"INVALID_STATE"
		)
		local cleanup = limiter:initialize()
		assertions.equal(limiter:getState(), "Initialized")
		assertions.equal(connectorState.connectCount, 1)
		assertions.equal(cleanup:getState(), "Active")
		assertions.equal(cleanup:getTaskCount(), 2)
		assertErrorCode(
			assertions,
			captureError(assertions, function()
				limiter:initialize()
			end),
			"INVALID_STATE"
		)

		limiter:start()
		assertions.equal(limiter:getState(), "Started")
		assertErrorCode(
			assertions,
			captureError(assertions, function()
				limiter:start()
			end),
			"INVALID_STATE"
		)
		cleanup:cleanup()
		assertions.equal(limiter:getState(), "Shutdown")
		assertions.equal(connectorState.disconnectCount, 1)
		assertDecision(assertions, limiter:consume({} :: any, CLIENT_EVENT), "UNAVAILABLE")
		assertions.equal(clockReads, 0)
		cleanup:cleanup()
		assertErrorCode(
			assertions,
			captureError(assertions, function()
				limiter:initialize()
			end),
			"INVALID_STATE"
		)

		assertErrorCode(
			assertions,
			captureError(assertions, function()
				ServerRateLimiter.new({} :: any, Players, policySet, function()
					return 0
				end)
			end),
			"INVALID_LOGGER"
		)
		assertErrorCode(
			assertions,
			captureError(assertions, function()
				ServerRateLimiter.new(loggerFor("Match"), Instance.new("Folder"), policySet, function()
					return 0
				end)
			end),
			"INVALID_PLAYERS"
		)
		assertErrorCode(
			assertions,
			captureError(assertions, function()
				ServerRateLimiter.new(loggerFor("Match"), Players, {} :: any, function()
					return 0
				end)
			end),
			"INVALID_POLICY_SET"
		)
		assertErrorCode(
			assertions,
			captureError(assertions, function()
				ServerRateLimiter.new(loggerFor("Match"), Players, policySet, true :: any)
			end),
			"INVALID_CLOCK"
		)
		assertErrorCode(
			assertions,
			captureError(assertions, function()
				ServerRateLimiter.new(loggerFor("Match"), Players, policySet, function()
					return 0
				end, true :: any)
			end),
			"INVALID_CONNECTOR"
		)
		assertErrorCode(
			assertions,
			captureError(assertions, function()
				ServerRateLimiter.new(loggerFor("Match"), Players, policySet, function()
					return 0
				end, nil, true :: any)
			end),
			"INVALID_REPORTER"
		)
	end),

	TestHarness.case("contains connector failure and rejects initialization reentry", function(assertions)
		local policySet = makePolicySet(FULL_REGISTRY, "Match")
		local thrownLimiter = ServerRateLimiter.new(
			loggerFor("Match"),
			Players,
			policySet,
			function()
				return 0
			end,
			function(_handler)
				error(PRIVATE_SENTINEL, 0)
			end :: any,
			function(_report) end
		)
		local connectionFailure = captureError(assertions, function()
			thrownLimiter:initialize()
		end)
		assertErrorCode(assertions, connectionFailure, "CONNECTION_FAILED")
		assertions.isNil(string.find(connectionFailure, PRIVATE_SENTINEL, 1, true))
		assertions.equal(thrownLimiter:getState(), "Failed")
		assertDecision(assertions, thrownLimiter:consume({} :: any, CLIENT_EVENT), "UNAVAILABLE")

		local invalidConnectionLimiter = ServerRateLimiter.new(loggerFor("Match"), Players, policySet, function()
			return 0
		end, function(_handler)
			return {} :: any
		end, function(_report) end)
		assertErrorCode(
			assertions,
			captureError(assertions, function()
				invalidConnectionLimiter:initialize()
			end),
			"INVALID_CONNECTION"
		)
		assertions.equal(invalidConnectionLimiter:getState(), "Failed")

		local reentryFailure = ""
		local reentrantLimiter: Limiter
		local connector = function(_handler: ServerRateLimiter.PlayerRemovingHandler): RBXScriptConnection
			reentryFailure = captureError(assertions, function()
				reentrantLimiter:initialize()
			end)
			return RobloxAdapter.createConnection(function() end) :: any
		end
		reentrantLimiter = ServerRateLimiter.new(loggerFor("Match"), Players, policySet, function()
			return 0
		end, connector, function(_report) end)
		local cleanup = reentrantLimiter:initialize()
		assertErrorCode(assertions, reentryFailure, "INVALID_STATE")
		assertions.equal(reentrantLimiter:getState(), "Initialized")
		reentrantLimiter:start()
		cleanup:cleanup()
	end),

	TestHarness.case("enforces burst same-time fractional and exact refill boundaries", function(assertions)
		local now = 0
		local policy = makePolicy(3, 0.5)
		local policySet = makePolicySet(FULL_REGISTRY, "Match", policy)
		local limiter, cleanup = startLimiter(policySet, function()
			return now
		end)

		withPlayers(1, function(testPlayers)
			local player = testPlayers[1]
			for _ = 1, 3 do
				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
			end
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")

			now = 1
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
			now = 2
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
			now = 3
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
			now = 4
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
		end)

		cleanup:cleanup()
	end),

	TestHarness.case("caps full buckets without banking and saturates huge forward time", function(assertions)
		local now = 0
		local policy = makePolicy(2, 1)
		local limiter, cleanup = startLimiter(makePolicySet(FULL_REGISTRY, "Match", policy), function()
			return now
		end)

		withPlayers(1, function(testPlayers)
			local player = testPlayers[1]
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
			now = 100
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")

			now = 1e300
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
		end)

		cleanup:cleanup()
	end),

	TestHarness.case(
		"keeps aggregate cadence bounded when a huge clock cannot represent ten seconds",
		function(assertions)
			local hugeTime = 2 ^ 60
			local now = hugeTime
			local reports: { ServerRateLimiter.AbuseReport } = {}
			assertions.equal(hugeTime + ServerRateLimiter.REPORT_INTERVAL_SECONDS, hugeTime)
			local limiter, cleanup = startLimiter(makePolicySet(FULL_REGISTRY, "Match", makePolicy(1, 1)), function()
				return now
			end, function(report)
				table.insert(reports, report)
			end)

			withPlayers(1, function(testPlayers)
				local player = testPlayers[1]
				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
				assertions.equal(#reports, 1)
				for _ = 1, 32 do
					assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
				end
				assertions.equal(#reports, 1)
				assertions.equal(limiter:getStats().pendingRejectionCount, 32)

				now = hugeTime + 512
				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
				assertions.equal(#reports, 2)
				assertions.equal(reports[2].rateLimitRejectionCount, 33)
				assertions.equal(limiter:getStats().pendingRejectionCount, 0)
			end)

			cleanup:cleanup()
		end
	),

	TestHarness.case("isolates actual players actions and canonical definition identities", function(assertions)
		local now = 0
		local oneTokenPolicy = makePolicy(1, 1)
		local twoTokenPolicy = makePolicy(2, 2)
		local bindings = bindingsFor(FULL_REGISTRY, oneTokenPolicy)
		for _, binding in bindings do
			if binding.endpoint == NO_RESPONSE_REQUEST.name then
				binding.policy = twoTokenPolicy
			end
		end
		local policySetResult = ServerRateLimiter.createPolicySet(FULL_REGISTRY, "Match", bindings)
		assertions.isTrue(policySetResult.ok)
		local limiter, cleanup = startLimiter((policySetResult :: any).value, function()
			return now
		end)
		local secondRegistry = makeRegistry(NetworkFixtures.validDefinitions())
		local foreignDefinition = requireDefinition(secondRegistry, "TestClientEvent")

		withPlayers(2, function(testPlayers)
			local first = testPlayers[1]
			local second = testPlayers[2]
			assertDecision(assertions, limiter:consume(first, CLIENT_EVENT), "ALLOWED")
			assertDecision(assertions, limiter:consume(first, CLIENT_EVENT), "RATE_LIMITED")
			assertDecision(assertions, limiter:consume(second, CLIENT_EVENT), "ALLOWED")
			assertDecision(assertions, limiter:consume(first, NO_RESPONSE_REQUEST), "ALLOWED")
			assertDecision(assertions, limiter:consume(first, NO_RESPONSE_REQUEST), "ALLOWED")
			assertDecision(assertions, limiter:consume(first, NO_RESPONSE_REQUEST), "RATE_LIMITED")
			now = 0.5
			assertDecision(assertions, limiter:consume(first, CLIENT_EVENT), "RATE_LIMITED")
			assertDecision(assertions, limiter:consume(first, NO_RESPONSE_REQUEST), "ALLOWED")

			local stats = limiter:getStats()
			assertions.equal(stats.trackedPlayerCount, 2)
			assertions.equal(stats.bucketCount, 3)
			assertions.equal(stats.activePolicyCount, 3)
			assertDecision(assertions, limiter:consume(first, foreignDefinition), "UNKNOWN_ACTION")
			assertDecision(
				assertions,
				limiter:consume(first, NetworkFixtures.clientEventDefinition() :: any),
				"UNKNOWN_ACTION"
			)
			assertDecision(assertions, limiter:consume(first, SERVER_EVENT), "UNKNOWN_ACTION")
			assertions.equal(limiter:getStats().bucketCount, 3)
		end)

		cleanup:cleanup()
	end),

	TestHarness.case(
		"rejects invalid detached and departing players and removes only exact identity",
		function(assertions)
			local now = 0
			local connectorState = makeConnectorState()
			local limiter = ServerRateLimiter.new(
				loggerFor("Match"),
				Players,
				makePolicySet(FULL_REGISTRY, "Match", makePolicy(1, 1)),
				function()
					return now
				end,
				connectorState.connector,
				function(_report) end
			)
			local cleanup = limiter:initialize()
			limiter:start()

			assertDecision(assertions, limiter:consume({}, CLIENT_EVENT), "INVALID_PLAYER")
			local folder = Instance.new("Folder")
			folder.Parent = Players
			assertDecision(assertions, limiter:consume(folder, CLIENT_EVENT), "INVALID_PLAYER")
			folder:Destroy()

			withPlayers(3, function(testPlayers)
				local first = testPlayers[1]
				local second = testPlayers[2]
				local unrelated = testPlayers[3]
				local playerRemoving = connectorState.handler :: ServerRateLimiter.PlayerRemovingHandler
				assertDecision(assertions, limiter:consume(first, CLIENT_EVENT), "ALLOWED")
				assertDecision(assertions, limiter:consume(second, CLIENT_EVENT), "ALLOWED")
				assertions.equal(limiter:getStats().trackedPlayerCount, 2)
				playerRemoving(unrelated)
				assertions.equal(limiter:getStats().trackedPlayerCount, 2)
				assertDecision(assertions, limiter:consume(second, CLIENT_EVENT), "RATE_LIMITED")
				playerRemoving(first)
				assertions.equal(limiter:getStats().trackedPlayerCount, 1)
				assertions.equal(limiter:getStats().bucketCount, 1)
				assertDecision(assertions, limiter:consume(first, CLIENT_EVENT), "INVALID_PLAYER")
				assertDecision(assertions, limiter:consume(second, CLIENT_EVENT), "RATE_LIMITED")

				second.Parent = nil
				assertDecision(assertions, limiter:consume(second, CLIENT_EVENT), "INVALID_PLAYER")
			end)

			cleanup:cleanup()
		end
	),

	TestHarness.case(
		"fails closed on every clock anomaly with one read no allocation and recovery",
		function(assertions)
			local clockReads = 0
			local clockMode = "value"
			local clockValue: any = PRIVATE_SENTINEL
			local clock = function(): number
				clockReads += 1
				if clockMode == "throw" then
					error(PRIVATE_SENTINEL, 0)
				end
				return clockValue :: any
			end
			local limiter, cleanup = startLimiter(makePolicySet(FULL_REGISTRY, "Match", makePolicy(1, 1)), clock)

			withPlayers(1, function(testPlayers)
				local player = testPlayers[1]
				local invalidValues: { any } = { PRIVATE_SENTINEL, 0 / 0, math.huge, -math.huge, -1 }
				for _, invalidValue in invalidValues do
					clockMode = "value"
					clockValue = invalidValue
					local beforeReads = clockReads
					local decision = limiter:consume(player, CLIENT_EVENT)
					assertDecision(assertions, decision, "INVALID_TIME")
					assertions.equal(clockReads, beforeReads + 1)
					assertGraphDoesNotRetain(assertions, decision, PRIVATE_SENTINEL)
					assertions.equal(limiter:getStats().trackedPlayerCount, 0)
					assertions.equal(limiter:getStats().bucketCount, 0)
				end

				clockMode = "throw"
				local beforeThrowReads = clockReads
				local throwDecision = limiter:consume(player, CLIENT_EVENT)
				assertDecision(assertions, throwDecision, "INVALID_TIME")
				assertions.equal(clockReads, beforeThrowReads + 1)
				assertGraphDoesNotRetain(assertions, throwDecision, PRIVATE_SENTINEL)
				assertions.equal(limiter:getStats().bucketCount, 0)

				clockMode = "value"
				clockValue = 10
				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
				assertions.equal(limiter:getStats().bucketCount, 1)
				clockValue = 9
				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "INVALID_TIME")
				assertions.equal(limiter:getStats().bucketCount, 1)
				clockValue = 10
				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
				clockValue = 11
				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")

				local readsBeforeCheapRejects = clockReads
				assertDecision(assertions, limiter:consume({}, CLIENT_EVENT), "INVALID_PLAYER")
				assertDecision(assertions, limiter:consume(player, SERVER_EVENT), "UNKNOWN_ACTION")
				assertions.equal(clockReads, readsBeforeCheapRejects)
			end)

			cleanup:cleanup()
		end
	),

	TestHarness.case(
		"reports frozen identity-free exact stats and clears all runtime state on shutdown",
		function(assertions)
			local now = 0
			local connectorState = makeConnectorState()
			local reports = {}
			local limiter = ServerRateLimiter.new(
				loggerFor("Match"),
				Players,
				makePolicySet(FULL_REGISTRY, "Match", makePolicy(1, 1)),
				function()
					return now
				end,
				connectorState.connector,
				function(report)
					table.insert(reports, report)
				end
			)
			local initialStats = limiter:getStats()
			assertions.isTrue(table.isfrozen(initialStats))
			assertions.equal(initialStats.trackedPlayerCount, 0)
			assertions.equal(initialStats.bucketCount, 0)
			assertions.equal(initialStats.pendingRejectionCount, 0)
			assertions.equal(initialStats.reportFailureCount, 0)
			assertions.equal(initialStats.activePolicyCount, 3)

			local cleanup = limiter:initialize()
			limiter:start()
			withPlayers(3, function(testPlayers)
				local first = testPlayers[1]
				local second = testPlayers[2]
				local unrelated = testPlayers[3]
				local playerRemoving = connectorState.handler :: ServerRateLimiter.PlayerRemovingHandler
				assertDecision(assertions, limiter:consume(first, CLIENT_EVENT), "ALLOWED")
				assertDecision(assertions, limiter:consume(first, NO_RESPONSE_REQUEST), "ALLOWED")
				assertDecision(assertions, limiter:consume(second, CLIENT_EVENT), "ALLOWED")
				local populated = limiter:getStats()
				assertions.equal(populated.trackedPlayerCount, 2)
				assertions.equal(populated.bucketCount, 3)
				assertions.equal(populated.activePolicyCount, 3)
				assertGraphDoesNotRetain(assertions, populated, first)
				assertGraphDoesNotRetain(assertions, populated, second)

				assertDecision(assertions, limiter:consume(first, CLIENT_EVENT), "RATE_LIMITED")
				assertions.equal(#reports, 1)
				assertDecision(assertions, limiter:consume(first, CLIENT_EVENT), "RATE_LIMITED")
				assertDecision(assertions, limiter:consume(first, NO_RESPONSE_REQUEST), "RATE_LIMITED")
				assertions.equal(limiter:getStats().pendingRejectionCount, 2)
				playerRemoving(unrelated)
				assertions.equal(limiter:getStats().trackedPlayerCount, 2)
				playerRemoving(first)
				local afterRemoval = limiter:getStats()
				assertions.equal(afterRemoval.trackedPlayerCount, 1)
				assertions.equal(afterRemoval.bucketCount, 1)
				assertions.equal(afterRemoval.pendingRejectionCount, 2)
			end)

			cleanup:cleanup()
			local shutdownStats = limiter:getStats()
			assertions.equal(limiter:getState(), "Shutdown")
			assertions.equal(shutdownStats.trackedPlayerCount, 0)
			assertions.equal(shutdownStats.bucketCount, 0)
			assertions.equal(shutdownStats.pendingRejectionCount, 0)
			assertions.equal(shutdownStats.reportFailureCount, 0)
			assertions.equal(shutdownStats.activePolicyCount, 3)
			assertDecision(assertions, limiter:consume({} :: any, CLIENT_EVENT), "UNAVAILABLE")
		end
	),

	TestHarness.case("aggregates immediately on one global exact cadence with mixed endpoints", function(assertions)
		local now = 0
		local reports: { ServerRateLimiter.AbuseReport } = {}
		local limiter, cleanup = startLimiter(
			makePolicySet(FULL_REGISTRY, "Match", makePolicy(1, ServerRateLimiter.MIN_REFILL_PER_SECOND)),
			function()
				return now
			end,
			function(report)
				table.insert(reports, report)
			end
		)

		withPlayers(2, function(testPlayers)
			local first = testPlayers[1]
			local second = testPlayers[2]
			assertDecision(assertions, limiter:consume(first, CLIENT_EVENT), "ALLOWED")
			assertions.equal(#reports, 0)
			assertDecision(assertions, limiter:consume(first, CLIENT_EVENT), "RATE_LIMITED")
			assertions.equal(#reports, 1)
			assertions.isTrue(table.isfrozen(reports[1]))
			assertions.equal(reports[1].code, "RATE_LIMITED")
			assertions.equal(reports[1].endpoint, "TestClientEvent")
			assertions.equal(reports[1].rateLimitRejectionCount, 1)
			assertions.equal(reports[1].rateLimitWindowSeconds, ServerRateLimiter.REPORT_INTERVAL_SECONDS)

			assertDecision(assertions, limiter:consume(first, CLIENT_EVENT), "RATE_LIMITED")
			assertDecision(assertions, limiter:consume(first, NO_RESPONSE_REQUEST), "ALLOWED")
			assertDecision(assertions, limiter:consume(first, NO_RESPONSE_REQUEST), "RATE_LIMITED")
			assertDecision(assertions, limiter:consume(second, CLIENT_EVENT), "ALLOWED")
			now = ServerRateLimiter.REPORT_INTERVAL_SECONDS - 0.001
			assertDecision(assertions, limiter:consume(second, CLIENT_EVENT), "RATE_LIMITED")
			assertions.equal(#reports, 1)
			assertions.equal(limiter:getStats().pendingRejectionCount, 3)

			now = ServerRateLimiter.REPORT_INTERVAL_SECONDS
			assertDecision(assertions, limiter:consume(second, CLIENT_EVENT), "RATE_LIMITED")
			assertions.equal(#reports, 2)
			assertions.equal(reports[2].endpoint, "<multiple>")
			assertions.equal(reports[2].rateLimitRejectionCount, 4)
			assertions.equal(limiter:getStats().pendingRejectionCount, 0)

			now = ServerRateLimiter.REPORT_INTERVAL_SECONDS * 2 - 0.001
			assertDecision(assertions, limiter:consume(second, CLIENT_EVENT), "RATE_LIMITED")
			assertions.equal(#reports, 2)
			now = ServerRateLimiter.REPORT_INTERVAL_SECONDS * 2
			assertDecision(assertions, limiter:consume(second, CLIENT_EVENT), "RATE_LIMITED")
			assertions.equal(#reports, 3)
			assertions.equal(reports[3].endpoint, "TestClientEvent")
			assertions.equal(reports[3].rateLimitRejectionCount, 2)

			for _, report in reports do
				assertGraphDoesNotRetain(assertions, report, first)
				assertGraphDoesNotRetain(assertions, report, second)
			end
		end)

		cleanup:cleanup()
	end),

	TestHarness.case("saturates aggregate rejection counts at the fixed technical maximum", function(assertions)
		local now = 0
		local reports: { ServerRateLimiter.AbuseReport } = {}
		local limiter, cleanup = startLimiter(
			makePolicySet(FULL_REGISTRY, "Match", makePolicy(1, ServerRateLimiter.MIN_REFILL_PER_SECOND)),
			function()
				return now
			end,
			function(report)
				table.insert(reports, report)
			end
		)

		withPlayers(1, function(testPlayers)
			local player = testPlayers[1]
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
			for _ = 1, ServerRateLimiter.MAX_AGGREGATE_REJECTIONS + 5 do
				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
			end
			assertions.equal(limiter:getStats().pendingRejectionCount, ServerRateLimiter.MAX_AGGREGATE_REJECTIONS)
			now = ServerRateLimiter.REPORT_INTERVAL_SECONDS
			assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
			assertions.equal(#reports, 2)
			assertions.equal(reports[2].rateLimitRejectionCount, ServerRateLimiter.MAX_AGGREGATE_REJECTIONS)
			assertions.equal(limiter:getStats().pendingRejectionCount, 0)
		end)

		cleanup:cleanup()
	end),

	TestHarness.case(
		"contains reporter failure advances cadence and exposes no raw identity or error",
		function(assertions)
			local now = 0
			local reportCalls = 0
			local reports: { ServerRateLimiter.AbuseReport } = {}
			local limiter, cleanup = startLimiter(
				makePolicySet(FULL_REGISTRY, "Match", makePolicy(1, ServerRateLimiter.MIN_REFILL_PER_SECOND)),
				function()
					return now
				end,
				function(report)
					reportCalls += 1
					table.insert(reports, report)
					local mutationSucceeded = pcall(function()
						(report :: any).endpoint = PRIVATE_SENTINEL
					end)
					if mutationSucceeded then
						error("REPORT_MUTATION_SUCCEEDED", 0)
					end
					error(PRIVATE_SENTINEL, 0)
				end
			)

			withPlayers(1, function(testPlayers)
				local player = testPlayers[1]
				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "ALLOWED")
				local firstFailure = limiter:consume(player, CLIENT_EVENT)
				assertDecision(assertions, firstFailure, "RATE_LIMITED")
				assertions.equal(reportCalls, 1)
				assertions.equal(limiter:getStats().reportFailureCount, 1)
				assertions.equal(limiter:getStats().pendingRejectionCount, 0)
				assertGraphDoesNotRetain(assertions, firstFailure, PRIVATE_SENTINEL)

				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
				assertions.equal(reportCalls, 1)
				assertions.equal(limiter:getStats().pendingRejectionCount, 1)
				now = ServerRateLimiter.REPORT_INTERVAL_SECONDS
				local boundaryFailure = limiter:consume(player, CLIENT_EVENT)
				assertDecision(assertions, boundaryFailure, "RATE_LIMITED")
				assertions.equal(reportCalls, 2)
				assertions.equal(limiter:getStats().reportFailureCount, 2)
				assertions.equal(limiter:getStats().pendingRejectionCount, 0)
				assertions.equal(reports[2].rateLimitRejectionCount, 2)

				assertDecision(assertions, limiter:consume(player, CLIENT_EVENT), "RATE_LIMITED")
				assertions.equal(reportCalls, 2)
				assertions.equal(limiter:getStats().pendingRejectionCount, 1)
				for _, report in reports do
					assertGraphDoesNotRetain(assertions, report, player)
					assertions.isNil(string.find(report.endpoint, PRIVATE_SENTINEL, 1, true))
				end
			end)

			cleanup:cleanup()
			assertions.equal(limiter:getStats().reportFailureCount, 0)
			assertions.equal(limiter:getStats().pendingRejectionCount, 0)
		end
	),
})
