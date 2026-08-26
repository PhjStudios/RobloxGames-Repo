--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage.Shared.logging.Log)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Cleanup = require(ReplicatedStorage.Shared.util.Cleanup)

export type PolicyErrorCode =
	"INVALID_CAPACITY"
	| "INVALID_REFILL"
	| "INVALID_ROLE"
	| "INVALID_REGISTRY"
	| "INVALID_POLICY_LIST"
	| "TOO_MANY_POLICIES"
	| "INVALID_POLICY_BINDING"
	| "UNKNOWN_ENDPOINT"
	| "WRONG_DIRECTION"
	| "DUPLICATE_POLICY"
	| "MISSING_POLICY"

export type PolicyError = {
	code: PolicyErrorCode,
	path: string,
	message: string,
}

export type Policy = {
	capacity: number,
	refillPerSecond: number,
}

export type PolicyBinding = {
	endpoint: string,
	policy: Policy,
}

export type LimiterState =
	"Registering"
	| "Initializing"
	| "Initialized"
	| "Starting"
	| "Started"
	| "Shutdown"
	| "Failed"

export type DecisionCode =
	"ALLOWED"
	| "RATE_LIMITED"
	| "INVALID_PLAYER"
	| "UNKNOWN_ACTION"
	| "INVALID_TIME"
	| "UNAVAILABLE"

export type Decision = {
	allowed: boolean,
	code: DecisionCode,
}

export type AbuseReport = {
	code: "RATE_LIMITED",
	endpoint: string,
	rateLimitRejectionCount: number,
	rateLimitWindowSeconds: number,
}

export type Stats = {
	trackedPlayerCount: number,
	bucketCount: number,
	pendingRejectionCount: number,
	reportFailureCount: number,
	activePolicyCount: number,
}

export type Clock = () -> number
export type PlayerRemovingHandler = (player: Player, ...unknown) -> ()
export type ConnectPlayerRemoving = (handler: PlayerRemovingHandler) -> RBXScriptConnection
export type Reporter = (report: AbuseReport) -> ()

type Definition = RemoteRegistry.Definition

type ActivePolicy = {
	definition: Definition,
	endpoint: string,
	policy: Policy,
}

type PolicySetData = {
	ordered: { PolicyBinding },
	active: { PolicyBinding },
	activeByDefinition: { [any]: ActivePolicy },
}

local PolicySetMethods = {}
PolicySetMethods.__index = PolicySetMethods

export type PolicySet = typeof(setmetatable({} :: {}, PolicySetMethods))

type Bucket = {
	tokens: number,
	lastRefill: number,
}

type PlayerState = {
	buckets: { [any]: Bucket },
	bucketCount: number,
}

type LimiterData = {
	logger: Log.Logger,
	players: Players,
	policySet: PolicySet,
	clock: () -> unknown,
	connectPlayerRemoving: ConnectPlayerRemoving,
	reporter: Reporter,
	state: LimiterState,
	cleanup: Cleanup.Container?,
	playerStates: { [any]: PlayerState },
	departingPlayers: { [any]: boolean },
	trackedPlayerCount: number,
	bucketCount: number,
	lastAcceptedTime: number?,
	lastReportAt: number?,
	pendingRejectionCount: number,
	pendingEndpoint: string?,
	reportFailureCount: number,
}

local LimiterMethods = {}
LimiterMethods.__index = LimiterMethods

export type Limiter = typeof(setmetatable({} :: {}, LimiterMethods))

local DEFAULT_CAPACITY = 4
local DEFAULT_REFILL_PER_SECOND = 2
local MIN_CAPACITY = 1
local MAX_CAPACITY = 100
local MIN_REFILL_PER_SECOND = 0.01
local MAX_REFILL_PER_SECOND = 100
local REPORT_INTERVAL_SECONDS = 10
local MAX_AGGREGATE_REJECTIONS = 4_096
local MULTIPLE_ENDPOINTS = "<multiple>"
local UNKNOWN_ENDPOINT = "<unknown>"
local CLEANUP_LABEL = "network-rate-limiter"

local POLICY_REGISTRY = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
local POLICY_SET_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: PolicySetData }
local LIMITER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: LimiterData }

local EMPTY_BINDINGS: { PolicyBinding } = table.freeze({})

local ALLOWED: Decision = table.freeze({ allowed = true, code = "ALLOWED" })
local RATE_LIMITED: Decision = table.freeze({ allowed = false, code = "RATE_LIMITED" })
local INVALID_PLAYER: Decision = table.freeze({ allowed = false, code = "INVALID_PLAYER" })
local UNKNOWN_ACTION: Decision = table.freeze({ allowed = false, code = "UNKNOWN_ACTION" })
local INVALID_TIME: Decision = table.freeze({ allowed = false, code = "INVALID_TIME" })
local UNAVAILABLE: Decision = table.freeze({ allowed = false, code = "UNAVAILABLE" })

local ServerRateLimiter = {
	DEFAULT_CAPACITY = DEFAULT_CAPACITY,
	DEFAULT_REFILL_PER_SECOND = DEFAULT_REFILL_PER_SECOND,
	MIN_CAPACITY = MIN_CAPACITY,
	MAX_CAPACITY = MAX_CAPACITY,
	MIN_REFILL_PER_SECOND = MIN_REFILL_PER_SECOND,
	MAX_REFILL_PER_SECOND = MAX_REFILL_PER_SECOND,
	REPORT_INTERVAL_SECONDS = REPORT_INTERVAL_SECONDS,
	MAX_AGGREGATE_REJECTIONS = MAX_AGGREGATE_REJECTIONS,
}

local function isFiniteNumber(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isSafeInteger(value: number): boolean
	return isFiniteNumber(value) and value % 1 == 0 and math.abs(value) <= 9_007_199_254_740_991
end

local function makeError(code: PolicyErrorCode, path: string, message: string): PolicyError
	return table.freeze({
		code = code,
		path = path,
		message = message,
	})
end

local function makePolicy(capacity: number, refillPerSecond: number): Policy
	local policy: Policy = table.freeze({
		capacity = capacity,
		refillPerSecond = refillPerSecond,
	})
	POLICY_REGISTRY[policy] = true
	return policy
end

local DEFAULT_POLICY = makePolicy(DEFAULT_CAPACITY, DEFAULT_REFILL_PER_SECOND)
ServerRateLimiter.DEFAULT_POLICY = DEFAULT_POLICY

local function isPolicy(value: unknown): boolean
	return type(value) == "table" and POLICY_REGISTRY[value :: any] == true
end

local function isPolicySet(value: unknown): boolean
	return type(value) == "table" and POLICY_SET_DATA[value :: any] ~= nil
end

local function requirePolicySetData(value: unknown): PolicySetData?
	if type(value) ~= "table" then
		return nil
	end
	return POLICY_SET_DATA[value :: any]
end

local function requireLimiterData(value: unknown): LimiterData
	if type(value) ~= "table" then
		error("[ATD_RATE_LIMITER][code=INVALID_CONTEXT]", 0)
	end
	local data = LIMITER_DATA[value :: any]
	if data == nil then
		error("[ATD_RATE_LIMITER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function bindingPath(index: number): string
	return `policies[{index}]`
end

local function bindingFieldPath(index: number, fieldName: string): string
	return `{bindingPath(index)}.{fieldName}`
end

local function readBindingArray(value: unknown): ({ unknown }?, PolicyError?)
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil, makeError("INVALID_POLICY_LIST", "policies", "Rate policies must use a plain dense array")
	end

	local rawTable = value :: { [any]: unknown }
	local count = 0
	local maximumIndex = 0
	local hasInvalidKey = false
	for rawKey in next, rawTable do
		count += 1
		if count > RemoteRegistry.MAX_DEFINITIONS then
			return nil, makeError("TOO_MANY_POLICIES", "policies", "Rate policy count exceeds the technical limit")
		end
		if type(rawKey) ~= "number" or not isSafeInteger(rawKey) or rawKey < 1 then
			hasInvalidKey = true
		else
			maximumIndex = math.max(maximumIndex, rawKey)
		end
	end
	if hasInvalidKey or maximumIndex ~= count then
		return nil, makeError("INVALID_POLICY_LIST", "policies", "Rate policies must use a plain dense array")
	end

	local copy: { unknown } = table.create(count)
	for index = 1, count do
		copy[index] = rawget(rawTable, index)
	end
	return copy, nil
end

local function readBinding(
	registry: RemoteRegistry.Registry,
	value: unknown,
	index: number
): (Definition?, Policy?, PolicyError?)
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil,
			nil,
			makeError("INVALID_POLICY_BINDING", bindingPath(index), "Rate policy bindings must use plain records")
	end

	local rawBinding = value :: { [any]: unknown }
	local hasInvalidKey = false
	local hasUnknownField = false
	for rawKey in next, rawBinding do
		if type(rawKey) ~= "string" then
			hasInvalidKey = true
		elseif rawKey ~= "endpoint" and rawKey ~= "policy" then
			hasUnknownField = true
		end
	end
	if hasInvalidKey or hasUnknownField then
		return nil,
			nil,
			makeError(
				"INVALID_POLICY_BINDING",
				bindingPath(index),
				"Rate policy bindings accept only endpoint and policy fields"
			)
	end

	local endpoint = rawget(rawBinding, "endpoint")
	if type(endpoint) ~= "string" then
		return nil,
			nil,
			makeError("INVALID_POLICY_BINDING", bindingFieldPath(index, "endpoint"), "Endpoint must be a string")
	end
	local policy = rawget(rawBinding, "policy")
	if not isPolicy(policy) then
		return nil,
			nil,
			makeError(
				"INVALID_POLICY_BINDING",
				bindingFieldPath(index, "policy"),
				"Policy must be an authenticated rate policy"
			)
	end

	local definition = registry:get(endpoint)
	if definition == nil then
		return nil,
			nil,
			makeError("UNKNOWN_ENDPOINT", bindingFieldPath(index, "endpoint"), "Policy endpoint is not registered")
	end
	if definition.direction ~= "ClientToServer" then
		return nil,
			nil,
			makeError(
				"WRONG_DIRECTION",
				bindingFieldPath(index, "endpoint"),
				"Only client-to-server endpoints may have a server rate policy"
			)
	end
	return definition, policy :: Policy, nil
end

function ServerRateLimiter.createPolicy(capacity: unknown, refillPerSecond: unknown): Result.Result<Policy, PolicyError>
	if
		type(capacity) ~= "number"
		or not isSafeInteger(capacity)
		or capacity < MIN_CAPACITY
		or capacity > MAX_CAPACITY
	then
		return Result.err(
			makeError("INVALID_CAPACITY", "policy.capacity", "Capacity must be a bounded positive safe integer")
		)
	end
	if
		type(refillPerSecond) ~= "number"
		or not isFiniteNumber(refillPerSecond)
		or refillPerSecond < MIN_REFILL_PER_SECOND
		or refillPerSecond > MAX_REFILL_PER_SECOND
	then
		return Result.err(
			makeError("INVALID_REFILL", "policy.refillPerSecond", "Refill must be a bounded positive finite number")
		)
	end
	return Result.ok(makePolicy(capacity, refillPerSecond))
end

function ServerRateLimiter.createPolicySet(
	registry: RemoteRegistry.Registry,
	role: RemoteRegistry.RuntimePlaceRole,
	bindings: unknown
): Result.Result<PolicySet, PolicyError>
	if not RemoteRegistry.isRegistry(registry) then
		return Result.err(makeError("INVALID_REGISTRY", "registry", "Expected an authenticated remote registry"))
	end
	if role ~= "Development" and role ~= "Lobby" and role ~= "Match" then
		return Result.err(makeError("INVALID_ROLE", "role", "Expected Development, Lobby, or Match"))
	end

	local rawBindings, arrayError = readBindingArray(bindings)
	if arrayError ~= nil then
		return Result.err(arrayError)
	end

	local policiesByEndpoint: { [string]: Policy } = {}
	for index = 1, rawlen(rawBindings :: { unknown }) do
		local definition, policy, bindingError = readBinding(registry, rawget(rawBindings :: { unknown }, index), index)
		if bindingError ~= nil then
			return Result.err(bindingError)
		end
		local endpoint = (definition :: Definition).name
		if rawget(policiesByEndpoint, endpoint) ~= nil then
			return Result.err(
				makeError(
					"DUPLICATE_POLICY",
					bindingFieldPath(index, "endpoint"),
					"Endpoint has more than one rate policy"
				)
			)
		end
		policiesByEndpoint[endpoint] = policy :: Policy
	end

	local canonical: { PolicyBinding } = {}
	for _, definition in registry:list() do
		if definition.direction == "ClientToServer" then
			local policy = rawget(policiesByEndpoint, definition.name)
			if policy == nil then
				return Result.err(
					makeError(
						"MISSING_POLICY",
						"policies",
						"Every client-to-server endpoint requires one explicit rate policy"
					)
				)
			end
			table.insert(canonical, table.freeze({ endpoint = definition.name, policy = policy }))
		end
	end

	local activeNames: { [string]: boolean } = {}
	for _, definition in registry:listForRole(role) do
		if definition.direction == "ClientToServer" then
			activeNames[definition.name] = true
		end
	end

	local active: { PolicyBinding } = {}
	local activeByDefinition: { [any]: ActivePolicy } = {}
	for _, binding in canonical do
		if rawget(activeNames, binding.endpoint) == true then
			local definition = registry:get(binding.endpoint) :: Definition
			local activeBinding = table.freeze({ endpoint = binding.endpoint, policy = binding.policy })
			table.insert(active, activeBinding)
			rawset(
				activeByDefinition,
				definition,
				table.freeze({
					definition = definition,
					endpoint = binding.endpoint,
					policy = binding.policy,
				})
			)
		end
	end

	local policySet = setmetatable({}, PolicySetMethods) :: PolicySet
	table.freeze(policySet)
	POLICY_SET_DATA[policySet] = {
		ordered = table.freeze(canonical),
		active = table.freeze(active),
		activeByDefinition = activeByDefinition,
	}
	return Result.ok(policySet)
end

function PolicySetMethods.list(self: PolicySet): { PolicyBinding }
	local data = requirePolicySetData(self)
	return if data == nil then EMPTY_BINDINGS else data.ordered
end

function PolicySetMethods.listActive(self: PolicySet): { PolicyBinding }
	local data = requirePolicySetData(self)
	return if data == nil then EMPTY_BINDINGS else data.active
end

function PolicySetMethods.count(self: PolicySet): number
	local data = requirePolicySetData(self)
	return if data == nil then 0 else rawlen(data.ordered)
end

function PolicySetMethods.activeCount(self: PolicySet): number
	local data = requirePolicySetData(self)
	return if data == nil then 0 else rawlen(data.active)
end

local function activePolicyFor(policySet: PolicySet, definition: unknown): ActivePolicy?
	local data = POLICY_SET_DATA[policySet]
	if data == nil then
		return nil
	end
	return rawget(data.activeByDefinition, definition)
end

local function failConstruction(logger: Log.Logger, code: string, message: string): never
	logger:error("network", "rate_limiter_construction_rejected", message, {
		code = code,
		endpoint = UNKNOWN_ENDPOINT,
		networkState = "Uninitialized",
	})
end

local function failLimiter(data: LimiterData, event: string, code: string, message: string): never
	data.logger:error("network", event, message, {
		code = code,
		endpoint = UNKNOWN_ENDPOINT,
		networkState = data.state,
	})
end

local function defaultReporter(logger: Log.Logger): Reporter
	return function(report: AbuseReport)
		logger:warn("network", "rate_limit_rejections", "Rate limit rejections were aggregated", {
			code = report.code,
			endpoint = report.endpoint,
			rateLimitRejectionCount = report.rateLimitRejectionCount,
			rateLimitWindowSeconds = report.rateLimitWindowSeconds,
		})
	end
end

local function clearPlayer(data: LimiterData, player: unknown)
	if typeof(player) ~= "Instance" then
		return
	end
	local classRead, isPlayer = pcall(function(): boolean
		return (player :: Instance):IsA("Player")
	end)
	if not classRead or not isPlayer then
		return
	end

	local canonicalPlayer = player :: Player
	local state = rawget(data.playerStates, canonicalPlayer)
	if state ~= nil then
		data.bucketCount -= state.bucketCount
		data.trackedPlayerCount -= 1
		rawset(data.playerStates, canonicalPlayer, nil)
	end
	rawset(data.departingPlayers, canonicalPlayer, true)
end

local function clearAll(data: LimiterData)
	table.clear(data.playerStates)
	table.clear(data.departingPlayers)
	data.trackedPlayerCount = 0
	data.bucketCount = 0
	data.lastAcceptedTime = nil
	data.lastReportAt = nil
	data.pendingRejectionCount = 0
	data.pendingEndpoint = nil
	data.reportFailureCount = 0
	data.cleanup = nil
	data.state = "Shutdown"
end

local function isActivePlayer(data: LimiterData, value: unknown): boolean
	if typeof(value) ~= "Instance" or rawget(data.departingPlayers, value) == true then
		return false
	end
	local succeeded, active = pcall(function(): boolean
		local player = value :: Instance
		return player:IsA("Player") and player.Parent == data.players
	end)
	return succeeded and active == true
end

local function sampleClock(data: LimiterData): number?
	local succeeded, value = pcall(data.clock)
	if
		not succeeded
		or type(value) ~= "number"
		or not isFiniteNumber(value)
		or value < 0
		or (data.lastAcceptedTime ~= nil and value < data.lastAcceptedTime)
	then
		return nil
	end
	return value
end

local function mergePendingEndpoint(data: LimiterData, endpoint: string)
	if data.pendingEndpoint == nil then
		data.pendingEndpoint = endpoint
	elseif data.pendingEndpoint ~= endpoint then
		data.pendingEndpoint = MULTIPLE_ENDPOINTS
	end
end

local function emitAggregate(data: LimiterData, now: number)
	local report: AbuseReport = table.freeze({
		code = "RATE_LIMITED",
		endpoint = data.pendingEndpoint or UNKNOWN_ENDPOINT,
		rateLimitRejectionCount = data.pendingRejectionCount,
		rateLimitWindowSeconds = REPORT_INTERVAL_SECONDS,
	})
	data.pendingRejectionCount = 0
	data.pendingEndpoint = nil
	data.lastReportAt = now

	local reported = pcall(data.reporter, report)
	if not reported then
		data.reportFailureCount = math.min(MAX_AGGREGATE_REJECTIONS, data.reportFailureCount + 1)
	end
end

local function recordRejection(data: LimiterData, now: number, endpoint: string)
	data.pendingRejectionCount = math.min(MAX_AGGREGATE_REJECTIONS, data.pendingRejectionCount + 1)
	mergePendingEndpoint(data, endpoint)
	if data.lastReportAt == nil or now - data.lastReportAt >= REPORT_INTERVAL_SECONDS then
		emitAggregate(data, now)
	end
end

function LimiterMethods.initialize(self: Limiter): Cleanup.Container
	local data = requireLimiterData(self)
	if data.state ~= "Registering" then
		failLimiter(
			data,
			"rate_limiter_transition_rejected",
			"INVALID_STATE",
			"Limiter initialization requires Registering"
		)
	end

	data.state = "Initializing"
	local cleanup = Cleanup.new(data.logger, CLEANUP_LABEL)
	data.cleanup = cleanup
	cleanup:add(function()
		clearAll(data)
	end)

	local connected, connection = pcall(data.connectPlayerRemoving, function(player: Player)
		clearPlayer(data, player)
	end)
	if not connected or typeof(connection) ~= "RBXScriptConnection" then
		pcall(function()
			cleanup:cleanup()
		end)
		data.state = "Failed"
		data.cleanup = nil
		failLimiter(
			data,
			"rate_limiter_initialization_rejected",
			if connected then "INVALID_CONNECTION" else "CONNECTION_FAILED",
			"PlayerRemoving could not be connected safely"
		)
	end

	local owned = pcall(function()
		cleanup:add(connection :: RBXScriptConnection)
	end)
	if not owned then
		pcall(function()
			(connection :: RBXScriptConnection):Disconnect()
		end)
		pcall(function()
			cleanup:cleanup()
		end)
		data.state = "Failed"
		data.cleanup = nil
		failLimiter(
			data,
			"rate_limiter_initialization_rejected",
			"OWNERSHIP_FAILED",
			"PlayerRemoving connection could not be owned safely"
		)
	end

	data.state = "Initialized"
	return cleanup
end

function LimiterMethods.start(self: Limiter)
	local data = requireLimiterData(self)
	if data.state ~= "Initialized" then
		failLimiter(data, "rate_limiter_transition_rejected", "INVALID_STATE", "Limiter start requires Initialized")
	end
	data.state = "Starting"
	data.state = "Started"
end

function LimiterMethods.consume(self: Limiter, player: unknown, definition: unknown): Decision
	local data = requireLimiterData(self)
	if data.state ~= "Started" then
		return UNAVAILABLE
	end

	local activePolicy = activePolicyFor(data.policySet, definition)
	if activePolicy == nil then
		return UNKNOWN_ACTION
	end
	if not isActivePlayer(data, player) then
		return INVALID_PLAYER
	end

	local now = sampleClock(data)
	if now == nil then
		return INVALID_TIME
	end
	data.lastAcceptedTime = now

	local canonicalPlayer = player :: Player
	local playerState = rawget(data.playerStates, canonicalPlayer)
	if playerState == nil then
		playerState = {
			buckets = {},
			bucketCount = 0,
		}
		rawset(data.playerStates, canonicalPlayer, playerState)
		data.trackedPlayerCount += 1
	end

	local bucket = rawget(playerState.buckets, activePolicy.definition)
	if bucket == nil then
		bucket = {
			tokens = activePolicy.policy.capacity,
			lastRefill = now,
		}
		rawset(playerState.buckets, activePolicy.definition, bucket)
		playerState.bucketCount += 1
		data.bucketCount += 1
	else
		local elapsed = now - bucket.lastRefill
		if elapsed > 0 then
			local missing = activePolicy.policy.capacity - bucket.tokens
			if missing > 0 then
				if elapsed >= missing / activePolicy.policy.refillPerSecond then
					bucket.tokens = activePolicy.policy.capacity
				else
					bucket.tokens += elapsed * activePolicy.policy.refillPerSecond
				end
			end
			bucket.lastRefill = now
		end
	end

	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return ALLOWED
	end

	recordRejection(data, now, activePolicy.endpoint)
	return RATE_LIMITED
end

function LimiterMethods.getState(self: Limiter): LimiterState
	return requireLimiterData(self).state
end

function LimiterMethods.getStats(self: Limiter): Stats
	local data = requireLimiterData(self)
	return table.freeze({
		trackedPlayerCount = data.trackedPlayerCount,
		bucketCount = data.bucketCount,
		pendingRejectionCount = data.pendingRejectionCount,
		reportFailureCount = data.reportFailureCount,
		activePolicyCount = data.policySet:activeCount(),
	})
end

function ServerRateLimiter.new(
	logger: Log.Logger,
	players: Instance,
	policySet: PolicySet,
	clock: Clock,
	connectPlayerRemoving: ConnectPlayerRemoving?,
	reporter: Reporter?
): Limiter
	if not Log.isLogger(logger) then
		error("[ATD_RATE_LIMITER][code=INVALID_LOGGER]", 0)
	end
	local classRead, isPlayers = pcall(function(): boolean
		return typeof(players) == "Instance" and players:IsA("Players")
	end)
	if not classRead or not isPlayers then
		failConstruction(logger, "INVALID_PLAYERS", "Limiter requires the Players service")
	end
	if not isPolicySet(policySet) then
		failConstruction(logger, "INVALID_POLICY_SET", "Limiter requires an authenticated policy set")
	end
	if type(clock) ~= "function" then
		failConstruction(logger, "INVALID_CLOCK", "Limiter requires an injected server clock")
	end
	if connectPlayerRemoving ~= nil and type(connectPlayerRemoving) ~= "function" then
		failConstruction(logger, "INVALID_CONNECTOR", "PlayerRemoving connector must be a function or nil")
	end
	if reporter ~= nil and type(reporter) ~= "function" then
		failConstruction(logger, "INVALID_REPORTER", "Abuse reporter must be a function or nil")
	end

	local playersService = players :: Players
	local connector: ConnectPlayerRemoving = connectPlayerRemoving
		or function(handler: PlayerRemovingHandler)
			return playersService.PlayerRemoving:Connect(handler)
		end
	local limiter = setmetatable({}, LimiterMethods) :: Limiter
	table.freeze(limiter)
	LIMITER_DATA[limiter] = {
		logger = logger,
		players = playersService,
		policySet = policySet,
		clock = clock :: any,
		connectPlayerRemoving = connector,
		reporter = reporter or defaultReporter(logger),
		state = "Registering",
		cleanup = nil,
		playerStates = {},
		departingPlayers = setmetatable({}, { __mode = "k" }),
		trackedPlayerCount = 0,
		bucketCount = 0,
		lastAcceptedTime = nil,
		lastReportAt = nil,
		pendingRejectionCount = 0,
		pendingEndpoint = nil,
		reportFailureCount = 0,
	}
	return limiter
end

function ServerRateLimiter.isPolicy(value: unknown): boolean
	return isPolicy(value)
end

function ServerRateLimiter.isPolicySet(value: unknown): boolean
	return isPolicySet(value)
end

function ServerRateLimiter.isLimiter(value: unknown): boolean
	return type(value) == "table" and LIMITER_DATA[value :: any] ~= nil
end

table.freeze(PolicySetMethods)
table.freeze(LimiterMethods)
return table.freeze(ServerRateLimiter)
