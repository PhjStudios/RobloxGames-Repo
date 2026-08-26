--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage.Shared.logging.Log)
local PayloadValidation = require(ReplicatedStorage.Shared.network.PayloadValidation)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local Cleanup = require(ReplicatedStorage.Shared.util.Cleanup)

local ServerRateLimiter = require(script.Parent.ServerRateLimiter)

export type DispatcherState =
	"Registering"
	| "Initializing"
	| "Initialized"
	| "Starting"
	| "Started"
	| "Shutdown"
	| "Failed"

export type ServerContext = {
	player: Player,
	definition: RemoteRegistry.Definition,
	role: RemoteRegistry.RuntimePlaceRole,
}

export type HandlerOutcome = typeof(setmetatable({} :: {}, {}))
export type Authorizer = (context: ServerContext) -> boolean
export type Handler = (context: ServerContext, payload: unknown) -> HandlerOutcome

export type RequestContract = typeof(setmetatable({} :: {}, {}))
export type EventContract = typeof(setmetatable({} :: {}, {}))
export type Contract = RequestContract | EventContract

export type AggregateCode =
	"MALFORMED_ENVELOPE"
	| "INVALID_PLAYER"
	| "INVALID_RESPONSE_REMOTE"
	| "DUPLICATE_REQUEST"
	| "STALE_REQUEST"
	| "NOT_AUTHORIZED"
	| "INVALID_PAYLOAD"
	| "HANDLER_FAILED"
	| "INVALID_HANDLER_OUTCOME"
	| "INVALID_RESPONSE_PAYLOAD"
	| "UNAVAILABLE"
	| "RESPONSE_SEND_FAILED"
	| "MULTIPLE_SIGNALS"

export type AggregateReport = {
	code: AggregateCode,
	endpoint: string,
	protocolRejectionCount: number,
	protocolWindowSeconds: number,
}

export type Stats = {
	trackedPlayerCount: number,
	pendingRequestCount: number,
	completedRequestCount: number,
	pendingProtocolRejectionCount: number,
	reportFailureCount: number,
	observationClockFailureCount: number,
	responseSendFailureCount: number,
	registeredContractCount: number,
}

export type Clock = () -> number
export type PlayerRemovingHandler = (player: Player, ...unknown) -> ()
export type ConnectPlayerRemoving = (handler: PlayerRemovingHandler) -> RBXScriptConnection
export type Reporter = (report: AggregateReport) -> ()
export type ResponseEnvelope = RequestProtocol.RawSuccess | RequestProtocol.RawRejected
export type Sender = (remote: RemoteEvent, originatingPlayer: Player, envelope: ResponseEnvelope) -> ()

export type Dependencies = {
	clock: Clock?,
	connectPlayerRemoving: ConnectPlayerRemoving?,
	reporter: Reporter?,
	sender: Sender?,
}

type OutcomeData = {
	kind: "Success" | "Rejected",
	payload: unknown,
	publicError: RequestProtocol.PublicError?,
}

type ContractData = {
	kind: "Request" | "Event",
	registry: RemoteRegistry.Registry,
	role: RemoteRegistry.RuntimePlaceRole,
	definition: RemoteRegistry.Definition,
	payloadSchema: PayloadValidation.Schema,
	responseSchema: PayloadValidation.Schema?,
	authorizer: Authorizer,
	handler: Handler,
}

type PlayerLedger = {
	active: boolean,
	pending: { [string]: boolean },
	pendingCount: number,
	completed: { [string]: boolean },
	completedRing: { string? },
	completedCount: number,
	nextCompletedIndex: number,
}

type DispatcherData = {
	logger: Log.Logger,
	registry: RemoteRegistry.Registry,
	role: RemoteRegistry.RuntimePlaceRole,
	players: Players,
	limiter: ServerRateLimiter.Limiter,
	clock: () -> unknown,
	connectPlayerRemoving: ConnectPlayerRemoving,
	reporter: Reporter,
	sender: Sender,
	state: DispatcherState,
	cleanup: Cleanup.Container?,
	contractsByDefinition: { [any]: Contract },
	registeredContractCount: number,
	playerLedgers: { [any]: PlayerLedger },
	departingPlayers: { [any]: boolean },
	trackedPlayerCount: number,
	pendingRequestCount: number,
	completedRequestCount: number,
	lastAcceptedObservationTime: number?,
	lastReportAt: number?,
	pendingProtocolRejectionCount: number,
	pendingEndpoint: string?,
	pendingCode: AggregateCode?,
	reportFailureCount: number,
	observationClockFailureCount: number,
	responseSendFailureCount: number,
}

local ContractMethods = {}
ContractMethods.__index = ContractMethods

local DispatcherMethods = {}
DispatcherMethods.__index = DispatcherMethods

export type Dispatcher = typeof(setmetatable({} :: {}, DispatcherMethods))

local MAX_PENDING_REQUESTS_PER_PLAYER = 32
local MAX_COMPLETED_REQUESTS_PER_PLAYER = 128
local REPORT_INTERVAL_SECONDS = 10
local MAX_AGGREGATE_SIGNALS = 4_096
local MULTIPLE_ENDPOINTS = "<multiple>"
local UNKNOWN_ENDPOINT = "<unknown>"
local CLEANUP_LABEL = "network-request-dispatcher"

local AUTHENTIC_CONTEXTS = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
local OUTCOME_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: OutcomeData }
local CONTRACT_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ContractData }
local DISPATCHER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: DispatcherData }

local ServerRequestDispatcher = {
	MAX_PENDING_REQUESTS_PER_PLAYER = MAX_PENDING_REQUESTS_PER_PLAYER,
	MAX_COMPLETED_REQUESTS_PER_PLAYER = MAX_COMPLETED_REQUESTS_PER_PLAYER,
	REPORT_INTERVAL_SECONDS = REPORT_INTERVAL_SECONDS,
	MAX_AGGREGATE_SIGNALS = MAX_AGGREGATE_SIGNALS,
}

local function staticError(code: string): never
	error(`[ATD_REQUEST_DISPATCHER][code={code}]`, 0)
end

local function isFiniteNumber(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isRuntimeRole(value: unknown): boolean
	return value == "Development" or value == "Lobby" or value == "Match"
end

local function publicError(code: RequestProtocol.PublicErrorCode): RequestProtocol.PublicError
	local result = RequestProtocol.createPublicError(code, nil)
	if not result.ok then
		staticError("PUBLIC_ERROR_CONSTRUCTION_FAILED")
	end
	return result.value
end

local RATE_LIMITED_ERROR = publicError("RATE_LIMITED")
local NOT_AUTHORIZED_ERROR = publicError("NOT_AUTHORIZED")
local INVALID_PAYLOAD_ERROR = publicError("INVALID_PAYLOAD")
local UNAVAILABLE_ERROR = publicError("UNAVAILABLE")
local INTERNAL_ERROR = publicError("INTERNAL_ERROR")
local STALE_REQUEST_ERROR = publicError("STALE_REQUEST")

local function makeOutcome(data: OutcomeData): HandlerOutcome
	local outcome = table.freeze({}) :: HandlerOutcome
	OUTCOME_DATA[outcome] = data
	return outcome
end

function ServerRequestDispatcher.success(payload: unknown?): HandlerOutcome
	return makeOutcome({
		kind = "Success",
		payload = payload,
		publicError = nil,
	})
end

function ServerRequestDispatcher.reject(errorValue: unknown): HandlerOutcome
	if not RequestProtocol.isPublicError(errorValue) then
		staticError("INVALID_PUBLIC_ERROR")
	end
	return makeOutcome({
		kind = "Rejected",
		payload = nil,
		publicError = errorValue :: RequestProtocol.PublicError,
	})
end

function ServerRequestDispatcher.isOutcome(value: unknown): boolean
	return type(value) == "table" and OUTCOME_DATA[value :: any] ~= nil
end

function ServerRequestDispatcher.isContext(value: unknown): boolean
	return type(value) == "table" and AUTHENTIC_CONTEXTS[value :: any] == true
end

local function activeCanonicalDefinition(
	registry: RemoteRegistry.Registry,
	role: RemoteRegistry.RuntimePlaceRole,
	definition: unknown
): RemoteRegistry.Definition?
	for _, candidate in registry:listForRole(role) do
		if candidate == definition then
			return candidate
		end
	end
	return nil
end

local function createContract(
	kind: "Request" | "Event",
	registry: RemoteRegistry.Registry,
	role: RemoteRegistry.RuntimePlaceRole,
	definition: unknown,
	payloadSchema: unknown,
	responseSchema: unknown,
	authorizer: unknown,
	handler: unknown
): Contract
	if not RemoteRegistry.isRegistry(registry) then
		staticError("INVALID_REGISTRY")
	end
	if not isRuntimeRole(role) then
		staticError("INVALID_ROLE")
	end
	local canonical = activeCanonicalDefinition(registry, role, definition)
	if canonical == nil then
		staticError("INACTIVE_DEFINITION")
	end
	if canonical.direction ~= "ClientToServer" or canonical.kind ~= kind then
		staticError("INVALID_DEFINITION_KIND")
	end
	if not PayloadValidation.isSchema(payloadSchema) then
		staticError("INVALID_PAYLOAD_SCHEMA")
	end
	if kind == "Request" then
		if canonical.response == "Required" then
			if not PayloadValidation.isSchema(responseSchema) then
				staticError("MISSING_RESPONSE_SCHEMA")
			end
		elseif responseSchema ~= nil then
			staticError("UNEXPECTED_RESPONSE_SCHEMA")
		end
	elseif responseSchema ~= nil or canonical.response ~= "None" then
		staticError("UNEXPECTED_RESPONSE_SCHEMA")
	end
	if type(authorizer) ~= "function" then
		staticError("INVALID_AUTHORIZER")
	end
	if type(handler) ~= "function" then
		staticError("INVALID_HANDLER")
	end

	local contract = setmetatable({}, ContractMethods) :: Contract
	table.freeze(contract)
	CONTRACT_DATA[contract] = {
		kind = kind,
		registry = registry,
		role = role,
		definition = canonical,
		payloadSchema = payloadSchema :: PayloadValidation.Schema,
		responseSchema = responseSchema :: PayloadValidation.Schema?,
		authorizer = authorizer :: Authorizer,
		handler = handler :: Handler,
	}
	return contract
end

function ServerRequestDispatcher.createRequestContract(
	registry: RemoteRegistry.Registry,
	role: RemoteRegistry.RuntimePlaceRole,
	definition: unknown,
	payloadSchema: unknown,
	responseSchema: unknown,
	authorizer: unknown,
	handler: unknown
): RequestContract
	return createContract(
			"Request",
			registry,
			role,
			definition,
			payloadSchema,
			responseSchema,
			authorizer,
			handler
		) :: RequestContract
end

function ServerRequestDispatcher.createEventContract(
	registry: RemoteRegistry.Registry,
	role: RemoteRegistry.RuntimePlaceRole,
	definition: unknown,
	payloadSchema: unknown,
	authorizer: unknown,
	handler: unknown
): EventContract
	return createContract("Event", registry, role, definition, payloadSchema, nil, authorizer, handler) :: EventContract
end

function ServerRequestDispatcher.isRequestContract(value: unknown): boolean
	local data = if type(value) == "table" then CONTRACT_DATA[value :: any] else nil
	return data ~= nil and data.kind == "Request"
end

function ServerRequestDispatcher.isEventContract(value: unknown): boolean
	local data = if type(value) == "table" then CONTRACT_DATA[value :: any] else nil
	return data ~= nil and data.kind == "Event"
end

function ContractMethods.getDefinition(self: Contract): RemoteRegistry.Definition
	local data = CONTRACT_DATA[self]
	if data == nil then
		staticError("INVALID_CONTRACT_CONTEXT")
	end
	return data.definition
end

function ContractMethods.getKind(self: Contract): "Request" | "Event"
	local data = CONTRACT_DATA[self]
	if data == nil then
		staticError("INVALID_CONTRACT_CONTEXT")
	end
	return data.kind
end

local function requireDispatcher(value: unknown): DispatcherData
	if type(value) ~= "table" then
		staticError("INVALID_DISPATCHER_CONTEXT")
	end
	local data = DISPATCHER_DATA[value :: any]
	if data == nil then
		staticError("INVALID_DISPATCHER_CONTEXT")
	end
	return data
end

local function failConstruction(logger: Log.Logger, code: string, message: string): never
	logger:error("network", "request_dispatcher_construction_rejected", message, {
		code = code,
		endpoint = UNKNOWN_ENDPOINT,
		networkState = "Uninitialized",
	})
end

local function failDispatcher(data: DispatcherData, code: string, message: string): never
	data.logger:error("network", "request_dispatcher_transition_rejected", message, {
		code = code,
		endpoint = UNKNOWN_ENDPOINT,
		networkState = data.state,
	})
end

local function defaultConnectPlayerRemoving(players: Players): ConnectPlayerRemoving
	return function(handler: PlayerRemovingHandler): RBXScriptConnection
		return players.PlayerRemoving:Connect(handler)
	end
end

local function defaultReporter(logger: Log.Logger): Reporter
	return function(report: AggregateReport)
		logger:warn("network", "protocol_rejections", "Network protocol rejections were aggregated", {
			code = report.code,
			endpoint = report.endpoint,
			protocolRejectionCount = report.protocolRejectionCount,
			protocolWindowSeconds = report.protocolWindowSeconds,
		})
	end
end

local function defaultSender(remote: RemoteEvent, originatingPlayer: Player, envelope: ResponseEnvelope)
	remote:FireClient(originatingPlayer, envelope)
end

local function resolveDependencies(
	logger: Log.Logger,
	players: Players,
	dependencies: Dependencies?
): (Clock, ConnectPlayerRemoving, Reporter, Sender)
	if dependencies == nil then
		return os.clock, defaultConnectPlayerRemoving(players), defaultReporter(logger), defaultSender
	end
	if type(dependencies) ~= "table" or getmetatable(dependencies :: any) ~= nil then
		failConstruction(logger, "INVALID_DEPENDENCIES", "Dispatcher dependencies must use one plain exact record")
	end

	local allowed = {
		clock = true,
		connectPlayerRemoving = true,
		reporter = true,
		sender = true,
	}
	for rawKey in next, dependencies :: any do
		if type(rawKey) ~= "string" or rawget(allowed, rawKey) ~= true then
			failConstruction(logger, "INVALID_DEPENDENCIES", "Dispatcher dependencies contain an unknown field")
		end
	end

	local clockValue = rawget(dependencies :: any, "clock")
	local connectorValue = rawget(dependencies :: any, "connectPlayerRemoving")
	local reporterValue = rawget(dependencies :: any, "reporter")
	local senderValue = rawget(dependencies :: any, "sender")
	if clockValue ~= nil and type(clockValue) ~= "function" then
		failConstruction(logger, "INVALID_CLOCK", "Dispatcher observation clock must be a function")
	end
	if connectorValue ~= nil and type(connectorValue) ~= "function" then
		failConstruction(logger, "INVALID_CONNECTOR", "Dispatcher PlayerRemoving connector must be a function")
	end
	if reporterValue ~= nil and type(reporterValue) ~= "function" then
		failConstruction(logger, "INVALID_REPORTER", "Dispatcher reporter must be a function")
	end
	if senderValue ~= nil and type(senderValue) ~= "function" then
		failConstruction(logger, "INVALID_SENDER", "Dispatcher response sender must be a function")
	end

	return clockValue or os.clock,
		connectorValue or defaultConnectPlayerRemoving(players),
		reporterValue or defaultReporter(logger),
		senderValue or defaultSender
end

local function saturatingIncrement(value: number): number
	return math.min(MAX_AGGREGATE_SIGNALS, value + 1)
end

local function stateCanHandle(data: DispatcherData): boolean
	return data.state == "Initialized" or data.state == "Started"
end

local function mergeEndpoint(data: DispatcherData, endpoint: string)
	if data.pendingEndpoint == nil then
		data.pendingEndpoint = endpoint
	elseif data.pendingEndpoint ~= endpoint then
		data.pendingEndpoint = MULTIPLE_ENDPOINTS
	end
end

local function mergeCode(data: DispatcherData, code: AggregateCode)
	if data.pendingCode == nil then
		data.pendingCode = code
	elseif data.pendingCode ~= code then
		data.pendingCode = "MULTIPLE_SIGNALS"
	end
end

local function sampleObservationClock(data: DispatcherData): number?
	local succeeded, value = pcall(data.clock)
	if not stateCanHandle(data) then
		return nil
	end
	if
		not succeeded
		or type(value) ~= "number"
		or not isFiniteNumber(value)
		or value < 0
		or (data.lastAcceptedObservationTime ~= nil and value < data.lastAcceptedObservationTime)
	then
		data.observationClockFailureCount = saturatingIncrement(data.observationClockFailureCount)
		return nil
	end
	data.lastAcceptedObservationTime = value
	return value
end

local function reportIsDue(data: DispatcherData, now: number): boolean
	local lastReportAt = data.lastReportAt
	if lastReportAt == nil then
		return true
	end
	-- Subtraction plus the strict forward check avoids a collapsed
	-- `lastReportAt + interval` threshold at large floating-point magnitudes.
	return now > lastReportAt and now - lastReportAt >= REPORT_INTERVAL_SECONDS
end

local function emitAggregate(data: DispatcherData, now: number)
	local report: AggregateReport = table.freeze({
		code = data.pendingCode or "UNAVAILABLE",
		endpoint = data.pendingEndpoint or UNKNOWN_ENDPOINT,
		protocolRejectionCount = data.pendingProtocolRejectionCount,
		protocolWindowSeconds = REPORT_INTERVAL_SECONDS,
	})
	data.pendingProtocolRejectionCount = 0
	data.pendingEndpoint = nil
	data.pendingCode = nil
	data.lastReportAt = now

	local reported = pcall(data.reporter, report)
	if not reported and stateCanHandle(data) then
		data.reportFailureCount = saturatingIncrement(data.reportFailureCount)
	end
end

local function recordSignal(data: DispatcherData, endpoint: string, code: AggregateCode)
	if not stateCanHandle(data) then
		return
	end
	data.pendingProtocolRejectionCount = saturatingIncrement(data.pendingProtocolRejectionCount)
	mergeEndpoint(data, endpoint)
	mergeCode(data, code)
	local now = sampleObservationClock(data)
	if now ~= nil and reportIsDue(data, now) then
		emitAggregate(data, now)
	end
end

local function makeContext(
	player: Player,
	definition: RemoteRegistry.Definition,
	role: RemoteRegistry.RuntimePlaceRole
): ServerContext
	local context: ServerContext = table.freeze({
		player = player,
		definition = definition,
		role = role,
	})
	AUTHENTIC_CONTEXTS[context] = true
	return context
end

local function isActivePlayer(data: DispatcherData, value: unknown): boolean
	if typeof(value) ~= "Instance" or rawget(data.departingPlayers, value) == true then
		return false
	end
	local succeeded, active = pcall(function(): boolean
		local instance = value :: Instance
		return instance:IsA("Player") and instance.Parent == data.players
	end)
	return succeeded and active == true
end

local function newLedger(): PlayerLedger
	return {
		active = true,
		pending = {},
		pendingCount = 0,
		completed = {},
		completedRing = table.create(MAX_COMPLETED_REQUESTS_PER_PLAYER),
		completedCount = 0,
		nextCompletedIndex = 1,
	}
end

local function getOrCreateLedger(data: DispatcherData, player: Player): PlayerLedger
	local ledger = rawget(data.playerLedgers, player)
	if ledger == nil then
		ledger = newLedger()
		rawset(data.playerLedgers, player, ledger)
		data.trackedPlayerCount += 1
	end
	return ledger
end

local function clearPlayer(data: DispatcherData, value: unknown)
	if typeof(value) ~= "Instance" then
		return
	end
	local classRead, isPlayer = pcall(function(): boolean
		return (value :: Instance):IsA("Player")
	end)
	if not classRead or not isPlayer then
		return
	end

	local player = value :: Player
	local ledger = rawget(data.playerLedgers, player)
	if ledger ~= nil then
		ledger.active = false
		data.pendingRequestCount -= ledger.pendingCount
		data.completedRequestCount -= ledger.completedCount
		data.trackedPlayerCount -= 1
		rawset(data.playerLedgers, player, nil)
	end
	rawset(data.departingPlayers, player, true)
end

local function clearAll(data: DispatcherData)
	for _, ledger in next, data.playerLedgers do
		ledger.active = false
	end
	table.clear(data.playerLedgers)
	table.clear(data.departingPlayers)
	table.clear(data.contractsByDefinition)
	data.registeredContractCount = 0
	data.trackedPlayerCount = 0
	data.pendingRequestCount = 0
	data.completedRequestCount = 0
	data.lastAcceptedObservationTime = nil
	data.lastReportAt = nil
	data.pendingProtocolRejectionCount = 0
	data.pendingEndpoint = nil
	data.pendingCode = nil
	data.reportFailureCount = 0
	data.observationClockFailureCount = 0
	data.responseSendFailureCount = 0
	data.cleanup = nil
	data.state = "Shutdown"
end

local function classifyRequest(ledger: PlayerLedger, requestId: string): "Pending" | "Completed" | "New"
	if rawget(ledger.pending, requestId) == true then
		return "Pending"
	end
	if rawget(ledger.completed, requestId) == true then
		return "Completed"
	end
	return "New"
end

local function reserveRequest(data: DispatcherData, ledger: PlayerLedger, requestId: string): boolean
	if ledger.pendingCount >= MAX_PENDING_REQUESTS_PER_PLAYER then
		return false
	end
	rawset(ledger.pending, requestId, true)
	ledger.pendingCount += 1
	data.pendingRequestCount += 1
	return true
end

local function addCompleted(data: DispatcherData, ledger: PlayerLedger, requestId: string)
	if rawget(ledger.completed, requestId) == true then
		return
	end

	if ledger.completedCount == MAX_COMPLETED_REQUESTS_PER_PLAYER then
		local evicted = rawget(ledger.completedRing, ledger.nextCompletedIndex)
		if evicted ~= nil then
			rawset(ledger.completed, evicted, nil)
		end
	else
		ledger.completedCount += 1
		data.completedRequestCount += 1
	end

	rawset(ledger.completedRing, ledger.nextCompletedIndex, requestId)
	rawset(ledger.completed, requestId, true)
	ledger.nextCompletedIndex = (ledger.nextCompletedIndex % MAX_COMPLETED_REQUESTS_PER_PLAYER) + 1
end

local function completeRequest(data: DispatcherData, ledger: PlayerLedger, requestId: string): boolean
	if not ledger.active then
		return false
	end
	if rawget(ledger.pending, requestId) == true then
		rawset(ledger.pending, requestId, nil)
		ledger.pendingCount -= 1
		data.pendingRequestCount -= 1
	end
	addCompleted(data, ledger, requestId)
	return true
end

local function isRemoteEvent(value: unknown): boolean
	if typeof(value) ~= "Instance" then
		return false
	end
	local succeeded, result = pcall(function(): boolean
		return (value :: Instance):IsA("RemoteEvent")
	end)
	return succeeded and result == true
end

local function buildRejected(
	requestId: RequestProtocol.RequestId,
	errorValue: RequestProtocol.PublicError
): RequestProtocol.RawRejected
	local result = RequestProtocol.buildRejected(requestId, errorValue)
	if not result.ok then
		staticError("REJECTED_RESPONSE_CONSTRUCTION_FAILED")
	end
	return result.value
end

local function sendResponse(
	data: DispatcherData,
	contractData: ContractData,
	responseRemote: RemoteEvent,
	player: Player,
	envelope: ResponseEnvelope
)
	if not stateCanHandle(data) or not isActivePlayer(data, player) then
		return
	end
	local sent = pcall(data.sender, responseRemote, player, envelope)
	if not sent and stateCanHandle(data) then
		data.responseSendFailureCount = saturatingIncrement(data.responseSendFailureCount)
		recordSignal(data, contractData.definition.name, "RESPONSE_SEND_FAILED")
	end
end

local function finishRejectedRequest(
	data: DispatcherData,
	contractData: ContractData,
	ledger: PlayerLedger,
	requestId: RequestProtocol.RequestId,
	responseRemote: RemoteEvent?,
	player: Player,
	errorValue: RequestProtocol.PublicError
)
	local completed = completeRequest(data, ledger, requestId.value)
	if completed and contractData.definition.response == "Required" then
		sendResponse(data, contractData, responseRemote :: RemoteEvent, player, buildRejected(requestId, errorValue))
	end
end

local function validationError(issue: unknown): RequestProtocol.PublicError
	local result = RequestProtocol.createPublicError("INVALID_PAYLOAD", issue :: any)
	return if result.ok then result.value else INVALID_PAYLOAD_ERROR
end

local function validatePayload(
	schema: PayloadValidation.Schema,
	value: unknown
): ("Valid" | "Invalid" | "Failed", unknown, RequestProtocol.PublicError?)
	local succeeded, resultValue = pcall(PayloadValidation.validate, schema, value)
	if not succeeded or type(resultValue) ~= "table" then
		return "Failed", nil, nil
	end
	local result = resultValue :: any
	if result.ok == true then
		return "Valid", result.value, nil
	end
	if result.ok == false then
		return "Invalid", nil, validationError(result.error)
	end
	return "Failed", nil, nil
end

local function publicErrorAggregateCode(errorValue: RequestProtocol.PublicError): AggregateCode
	local code = errorValue.code
	if code == "NOT_AUTHORIZED" then
		return "NOT_AUTHORIZED"
	elseif code == "INVALID_PAYLOAD" then
		return "INVALID_PAYLOAD"
	elseif code == "DUPLICATE_REQUEST" then
		return "DUPLICATE_REQUEST"
	elseif code == "STALE_REQUEST" then
		return "STALE_REQUEST"
	elseif code == "UNAVAILABLE" or code == "RATE_LIMITED" then
		return "UNAVAILABLE"
	else
		return "HANDLER_FAILED"
	end
end

local function consumeLimiter(
	data: DispatcherData,
	player: unknown,
	definition: RemoteRegistry.Definition
): (boolean, string)
	local succeeded, decision = pcall(function()
		return data.limiter:consume(player, definition)
	end)
	if not succeeded or type(decision) ~= "table" then
		return false, "UNAVAILABLE"
	end
	local rawDecision = decision :: any
	if rawDecision.allowed == true and rawDecision.code == "ALLOWED" then
		return true, "ALLOWED"
	end
	if rawDecision.allowed == false and rawDecision.code == "RATE_LIMITED" then
		return false, "RATE_LIMITED"
	end
	return false, "UNAVAILABLE"
end

function DispatcherMethods.registerContract(self: Dispatcher, contract: unknown)
	local data = requireDispatcher(self)
	if data.state ~= "Registering" then
		failDispatcher(data, "INVALID_STATE", "Contracts may be registered only before dispatcher initialization")
	end
	local contractData = if type(contract) == "table" then CONTRACT_DATA[contract :: any] else nil
	if contractData == nil or contractData.registry ~= data.registry or contractData.role ~= data.role then
		failDispatcher(data, "INVALID_CONTRACT", "Dispatcher requires an authentic contract for its registry and role")
	end
	if rawget(data.contractsByDefinition, contractData.definition) ~= nil then
		failDispatcher(data, "DUPLICATE_CONTRACT", "An endpoint may have only one dispatcher contract")
	end
	rawset(data.contractsByDefinition, contractData.definition, contract :: Contract)
	data.registeredContractCount += 1
end

function DispatcherMethods.initialize(self: Dispatcher): Cleanup.Container
	local data = requireDispatcher(self)
	if data.state ~= "Registering" then
		failDispatcher(data, "INVALID_STATE", "Dispatcher initialization requires Registering")
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
		failDispatcher(
			data,
			if connected then "INVALID_CONNECTION" else "CONNECTION_FAILED",
			"Dispatcher PlayerRemoving connection could not be created safely"
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
		failDispatcher(data, "OWNERSHIP_FAILED", "Dispatcher PlayerRemoving connection could not be owned safely")
	end

	data.state = "Initialized"
	return cleanup
end

function DispatcherMethods.start(self: Dispatcher)
	local data = requireDispatcher(self)
	if data.state ~= "Initialized" then
		failDispatcher(data, "INVALID_STATE", "Dispatcher start requires Initialized")
	end
	data.state = "Starting"
	data.state = "Started"
end

function DispatcherMethods.getState(self: Dispatcher): DispatcherState
	return requireDispatcher(self).state
end

function DispatcherMethods.getStats(self: Dispatcher): Stats
	local data = requireDispatcher(self)
	return table.freeze({
		trackedPlayerCount = data.trackedPlayerCount,
		pendingRequestCount = data.pendingRequestCount,
		completedRequestCount = data.completedRequestCount,
		pendingProtocolRejectionCount = data.pendingProtocolRejectionCount,
		reportFailureCount = data.reportFailureCount,
		observationClockFailureCount = data.observationClockFailureCount,
		responseSendFailureCount = data.responseSendFailureCount,
		registeredContractCount = data.registeredContractCount,
	})
end

local function dispatcherCanHandle(data: DispatcherData): boolean
	return stateCanHandle(data)
end

local function contractForDispatch(data: DispatcherData, value: unknown): ContractData?
	if type(value) ~= "table" then
		return nil
	end
	local contractData = CONTRACT_DATA[value :: any]
	if contractData == nil or rawget(data.contractsByDefinition, contractData.definition) ~= value then
		return nil
	end
	return contractData
end

local function rejectRequest(
	data: DispatcherData,
	contractData: ContractData,
	ledger: PlayerLedger,
	requestId: RequestProtocol.RequestId,
	responseRemote: RemoteEvent?,
	player: Player,
	errorValue: RequestProtocol.PublicError,
	aggregateCode: AggregateCode?
)
	if aggregateCode ~= nil then
		recordSignal(data, contractData.definition.name, aggregateCode)
	end
	finishRejectedRequest(data, contractData, ledger, requestId, responseRemote, player, errorValue)
end

local function dispatchRequest(
	data: DispatcherData,
	contractData: ContractData,
	responseRemote: unknown,
	origin: unknown,
	...: unknown
)
	local startedAtEntry = data.state == "Started"
	local parsedResult = RequestProtocol.parseRequest(...)
	if not parsedResult.ok then
		recordSignal(data, contractData.definition.name, "MALFORMED_ENVELOPE")
		return
	end
	local request = parsedResult.value

	local allowed, limiterCode = consumeLimiter(data, origin, contractData.definition)
	if not dispatcherCanHandle(data) then
		return
	end
	if not isActivePlayer(data, origin) then
		recordSignal(data, contractData.definition.name, "INVALID_PLAYER")
		return
	end
	local player = origin :: Player
	if not startedAtEntry then
		allowed = false
		limiterCode = "UNAVAILABLE"
	end

	local responseRequired = contractData.definition.response == "Required"
	if (responseRequired and not isRemoteEvent(responseRemote)) or (not responseRequired and responseRemote ~= nil) then
		recordSignal(data, contractData.definition.name, "INVALID_RESPONSE_REMOTE")
		return
	end

	local requestId = request.requestId
	local requestIdValue = requestId.value
	local ledger = getOrCreateLedger(data, player)
	local classification = classifyRequest(ledger, requestIdValue)
	if classification == "Pending" then
		recordSignal(data, contractData.definition.name, "DUPLICATE_REQUEST")
		return
	elseif classification == "Completed" then
		recordSignal(data, contractData.definition.name, "STALE_REQUEST")
		if responseRequired then
			sendResponse(
				data,
				contractData,
				responseRemote :: RemoteEvent,
				player,
				buildRejected(requestId, STALE_REQUEST_ERROR)
			)
		end
		return
	end

	if not allowed then
		local errorValue = if limiterCode == "RATE_LIMITED" then RATE_LIMITED_ERROR else UNAVAILABLE_ERROR
		rejectRequest(
			data,
			contractData,
			ledger,
			requestId,
			responseRemote :: RemoteEvent?,
			player,
			errorValue,
			if limiterCode == "RATE_LIMITED" then nil else "UNAVAILABLE"
		)
		return
	end

	if not reserveRequest(data, ledger, requestIdValue) then
		rejectRequest(
			data,
			contractData,
			ledger,
			requestId,
			responseRemote :: RemoteEvent?,
			player,
			UNAVAILABLE_ERROR,
			"UNAVAILABLE"
		)
		return
	end

	local context = makeContext(player, contractData.definition, data.role)
	local authorizationSucceeded, authorized = pcall(contractData.authorizer, context)
	if not dispatcherCanHandle(data) or not ledger.active or not isActivePlayer(data, player) then
		return
	end
	if not authorizationSucceeded or authorized ~= true then
		rejectRequest(
			data,
			contractData,
			ledger,
			requestId,
			responseRemote :: RemoteEvent?,
			player,
			NOT_AUTHORIZED_ERROR,
			"NOT_AUTHORIZED"
		)
		return
	end

	local validationState, canonicalPayload, payloadError = validatePayload(contractData.payloadSchema, request.payload)
	if not dispatcherCanHandle(data) or not ledger.active or not isActivePlayer(data, player) then
		return
	end
	if validationState ~= "Valid" then
		local errorValue = if validationState == "Invalid"
			then payloadError :: RequestProtocol.PublicError
			else INTERNAL_ERROR
		rejectRequest(
			data,
			contractData,
			ledger,
			requestId,
			responseRemote :: RemoteEvent?,
			player,
			errorValue,
			if validationState == "Invalid" then "INVALID_PAYLOAD" else "INVALID_RESPONSE_PAYLOAD"
		)
		return
	end

	local handlerSucceeded, outcomeValue = pcall(contractData.handler, context, canonicalPayload)
	if not dispatcherCanHandle(data) or not ledger.active or not isActivePlayer(data, player) then
		return
	end
	if not handlerSucceeded then
		rejectRequest(
			data,
			contractData,
			ledger,
			requestId,
			responseRemote :: RemoteEvent?,
			player,
			INTERNAL_ERROR,
			"HANDLER_FAILED"
		)
		return
	end
	local outcomeData = if type(outcomeValue) == "table" then OUTCOME_DATA[outcomeValue :: any] else nil
	if outcomeData == nil then
		rejectRequest(
			data,
			contractData,
			ledger,
			requestId,
			responseRemote :: RemoteEvent?,
			player,
			INTERNAL_ERROR,
			"INVALID_HANDLER_OUTCOME"
		)
		return
	end

	if outcomeData.kind == "Rejected" then
		local errorValue = outcomeData.publicError :: RequestProtocol.PublicError
		rejectRequest(
			data,
			contractData,
			ledger,
			requestId,
			responseRemote :: RemoteEvent?,
			player,
			errorValue,
			publicErrorAggregateCode(errorValue)
		)
		return
	end

	if not responseRequired then
		if outcomeData.payload ~= nil then
			rejectRequest(data, contractData, ledger, requestId, nil, player, INTERNAL_ERROR, "INVALID_HANDLER_OUTCOME")
			return
		end
		completeRequest(data, ledger, requestIdValue)
		return
	end

	local responseSchema = contractData.responseSchema :: PayloadValidation.Schema
	local responseValidationState, canonicalResponse = validatePayload(responseSchema, outcomeData.payload)
	if responseValidationState ~= "Valid" or canonicalResponse == nil then
		rejectRequest(
			data,
			contractData,
			ledger,
			requestId,
			responseRemote :: RemoteEvent,
			player,
			INTERNAL_ERROR,
			"INVALID_RESPONSE_PAYLOAD"
		)
		return
	end
	local successResult = RequestProtocol.buildSuccess(requestId, canonicalResponse)
	if not successResult.ok then
		rejectRequest(
			data,
			contractData,
			ledger,
			requestId,
			responseRemote :: RemoteEvent,
			player,
			INTERNAL_ERROR,
			"INVALID_RESPONSE_PAYLOAD"
		)
		return
	end

	local completed = completeRequest(data, ledger, requestIdValue)
	if completed then
		sendResponse(data, contractData, responseRemote :: RemoteEvent, player, successResult.value)
	end
end

local function dispatchEvent(
	data: DispatcherData,
	contractData: ContractData,
	responseRemote: unknown,
	origin: unknown,
	...: unknown
)
	local startedAtEntry = data.state == "Started"
	local parsedResult = RequestProtocol.parseEvent(...)
	if not parsedResult.ok then
		recordSignal(data, contractData.definition.name, "MALFORMED_ENVELOPE")
		return
	end

	local allowed, limiterCode = consumeLimiter(data, origin, contractData.definition)
	if not dispatcherCanHandle(data) then
		return
	end
	if not isActivePlayer(data, origin) then
		recordSignal(data, contractData.definition.name, "INVALID_PLAYER")
		return
	end
	if responseRemote ~= nil then
		recordSignal(data, contractData.definition.name, "INVALID_RESPONSE_REMOTE")
		return
	end
	if not startedAtEntry then
		allowed = false
		limiterCode = "UNAVAILABLE"
	end
	if not allowed then
		if limiterCode ~= "RATE_LIMITED" then
			recordSignal(data, contractData.definition.name, "UNAVAILABLE")
		end
		return
	end

	local player = origin :: Player
	local context = makeContext(player, contractData.definition, data.role)
	local authorizationSucceeded, authorized = pcall(contractData.authorizer, context)
	if not dispatcherCanHandle(data) or not isActivePlayer(data, player) then
		return
	end
	if not authorizationSucceeded or authorized ~= true then
		recordSignal(data, contractData.definition.name, "NOT_AUTHORIZED")
		return
	end

	local validationState, canonicalPayload = validatePayload(contractData.payloadSchema, parsedResult.value.payload)
	if not dispatcherCanHandle(data) or not isActivePlayer(data, player) then
		return
	end
	if validationState ~= "Valid" then
		recordSignal(
			data,
			contractData.definition.name,
			if validationState == "Invalid" then "INVALID_PAYLOAD" else "INVALID_RESPONSE_PAYLOAD"
		)
		return
	end

	local handlerSucceeded, outcomeValue = pcall(contractData.handler, context, canonicalPayload)
	if not dispatcherCanHandle(data) or not isActivePlayer(data, player) then
		return
	end
	if not handlerSucceeded then
		recordSignal(data, contractData.definition.name, "HANDLER_FAILED")
		return
	end
	local outcomeData = if type(outcomeValue) == "table" then OUTCOME_DATA[outcomeValue :: any] else nil
	if outcomeData == nil then
		recordSignal(data, contractData.definition.name, "INVALID_HANDLER_OUTCOME")
		return
	end
	if outcomeData.kind == "Rejected" then
		recordSignal(
			data,
			contractData.definition.name,
			publicErrorAggregateCode(outcomeData.publicError :: RequestProtocol.PublicError)
		)
	elseif outcomeData.payload ~= nil then
		recordSignal(data, contractData.definition.name, "INVALID_HANDLER_OUTCOME")
	end
end

function DispatcherMethods.dispatch(
	self: Dispatcher,
	contract: unknown,
	responseRemote: unknown,
	originatingPlayer: unknown,
	...: unknown
)
	local data = requireDispatcher(self)
	if not dispatcherCanHandle(data) then
		return
	end
	local contractData = contractForDispatch(data, contract)
	if contractData == nil then
		recordSignal(data, UNKNOWN_ENDPOINT, "UNAVAILABLE")
		return
	end
	if contractData.kind == "Request" then
		dispatchRequest(data, contractData, responseRemote, originatingPlayer, ...)
	else
		dispatchEvent(data, contractData, responseRemote, originatingPlayer, ...)
	end
end

function ServerRequestDispatcher.new(
	logger: Log.Logger,
	registry: RemoteRegistry.Registry,
	role: RemoteRegistry.RuntimePlaceRole,
	players: Instance,
	limiter: ServerRateLimiter.Limiter,
	dependencies: Dependencies?
): Dispatcher
	if not Log.isLogger(logger) then
		error("[ATD_REQUEST_DISPATCHER][code=INVALID_LOGGER]", 0)
	end
	if not RemoteRegistry.isRegistry(registry) then
		failConstruction(logger, "INVALID_REGISTRY", "Dispatcher requires an authentic remote registry")
	end
	if not isRuntimeRole(role) then
		failConstruction(logger, "INVALID_ROLE", "Dispatcher requires Development, Lobby, or Match")
	end
	local playersRead, isPlayers = pcall(function(): boolean
		return typeof(players) == "Instance" and players:IsA("Players")
	end)
	if not playersRead or not isPlayers then
		failConstruction(logger, "INVALID_PLAYERS", "Dispatcher requires the Players service")
	end
	if not ServerRateLimiter.isLimiter(limiter) then
		failConstruction(logger, "INVALID_LIMITER", "Dispatcher requires an authentic server rate limiter")
	end

	local canonicalPlayers = players :: Players
	local clock, connector, reporter, sender = resolveDependencies(logger, canonicalPlayers, dependencies)
	local dispatcher = setmetatable({}, DispatcherMethods) :: Dispatcher
	table.freeze(dispatcher)
	DISPATCHER_DATA[dispatcher] = {
		logger = logger,
		registry = registry,
		role = role,
		players = canonicalPlayers,
		limiter = limiter,
		clock = clock,
		connectPlayerRemoving = connector,
		reporter = reporter,
		sender = sender,
		state = "Registering",
		cleanup = nil,
		contractsByDefinition = {},
		registeredContractCount = 0,
		playerLedgers = {},
		departingPlayers = setmetatable({}, { __mode = "k" }),
		trackedPlayerCount = 0,
		pendingRequestCount = 0,
		completedRequestCount = 0,
		lastAcceptedObservationTime = nil,
		lastReportAt = nil,
		pendingProtocolRejectionCount = 0,
		pendingEndpoint = nil,
		pendingCode = nil,
		reportFailureCount = 0,
		observationClockFailureCount = 0,
		responseSendFailureCount = 0,
	}
	return dispatcher
end

function ServerRequestDispatcher.isDispatcher(value: unknown): boolean
	return type(value) == "table" and DISPATCHER_DATA[value :: any] ~= nil
end

table.freeze(ContractMethods)
table.freeze(DispatcherMethods)
return table.freeze(ServerRequestDispatcher)
