--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Log = require(ReplicatedStorage.Shared.logging.Log)
local WaveProtocol = require(ReplicatedStorage.Shared.match.WaveProtocol)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local WaveStateReducer = require(script.Parent.WaveStateReducer)

export type LifecycleState =
	"Constructed"
	| "Initializing"
	| "Initialized"
	| "Starting"
	| "Started"
	| "ShuttingDown"
	| "Shutdown"
	| "Failed"

export type ErrorCode =
	"INVALID_CONTEXT"
	| "INVALID_DEPENDENCIES"
	| "INITIALIZE_FAILED"
	| "START_FAILED"
	| "CLEANUP_FAILED"
	| "UNAVAILABLE"
	| "REQUEST_PENDING"
	| "INVALID_ARGUMENT"
	| "INTERNAL_ERROR"

export type Error = {
	code: ErrorCode,
}

export type ApplyKind = "Applied" | "Replaced" | "Duplicate" | "Stale" | "Skipped" | "WrongMatch" | "Rejected"

export type ApplyOutcomeCounts = {
	Applied: number,
	Replaced: number,
	Duplicate: number,
	Stale: number,
	Skipped: number,
	WrongMatch: number,
	Rejected: number,
}

export type Metrics = {
	lifecycleState: LifecycleState,
	connectionCount: number,
	callbackGeneration: number,
	matchGeneration: number,
	getRequestCount: number,
	recoveryRequestCount: number,
	getRequestPending: boolean,
	recoveryQueued: boolean,
	recoveryUsed: boolean,
	skipRequestCount: number,
	skipRequestPending: boolean,
	acceptedStateCount: number,
	matchReplacementCount: number,
	rejectedInputCount: number,
	applyOutcomeCounts: ApplyOutcomeCounts,
	lastApplyKind: ApplyKind?,
	locked: boolean,
	matchId: string?,
	waveRevision: number?,
	recoveryRequired: boolean,
	studioRecoverySuspended: boolean,
	studioRecoveryUsed: boolean,
	studioDiagnosticsBridgeCount: number,
}

export type StudioDiagnostics = {
	controller: Metrics,
	state: unknown,
}

export type ResponseListener = (value: unknown, ...unknown) -> ()
export type EventListener = (value: unknown, ...unknown) -> ()

export type RequestEndpoint = {
	definition: RemoteRegistry.Definition,
	connectResponse: (ResponseListener) -> RBXScriptConnection,
	fire: (RequestProtocol.RawRequest) -> (),
}

export type EventEndpoint = {
	definition: RemoteRegistry.Definition,
	connectEvent: (EventListener) -> RBXScriptConnection,
}

export type TrackerAdapter = {
	register: (self: TrackerAdapter, endpointName: unknown, requestSchema: unknown, responseSchema: unknown) -> any,
	buildRequest: (self: TrackerAdapter, endpointName: unknown, payload: unknown) -> any,
	handleResponse: (self: TrackerAdapter, definition: unknown, responseValue: unknown, ...unknown) -> any,
	cancel: (self: TrackerAdapter, pending: unknown) -> any,
	clear: (self: TrackerAdapter) -> (),
}

export type ReducerAdapter = {
	observeEvent: (self: ReducerAdapter, value: unknown) -> any,
	observeGetResponse: (
		self: ReducerAdapter,
		value: unknown,
		allowMatchReplacement: unknown,
		confirmRecoveryEpisode: unknown?
	) -> any,
	observeSubmitResponse: (self: ReducerAdapter, value: unknown) -> any,
	getState: (self: ReducerAdapter) -> any,
	reset: (self: ReducerAdapter) -> any,
	cleanup: (self: ReducerAdapter) -> any,
}

export type Dependencies = {
	tracker: TrackerAdapter,
	getSnapshot: RequestEndpoint,
	submitSkipVote: RequestEndpoint,
	replicationEvent: EventEndpoint,
	reducer: ReducerAdapter,
}

type PendingRequest = {
	pending: RequestProtocol.Pending,
	matchGeneration: number,
}

type PendingGetRequest = {
	pending: RequestProtocol.Pending,
	matchGeneration: number,
	recovery: boolean,
	recoveryEpisode: number?,
}

type ControllerData = {
	state: LifecycleState,
	dependencyFactory: () -> Dependencies,
	dependencies: Dependencies?,
	connections: { RBXScriptConnection },
	callbacksEnabled: boolean,
	callbackGeneration: number,
	matchGeneration: number,
	getPending: PendingGetRequest?,
	skipPending: PendingRequest?,
	initialRequestIssued: boolean,
	recoveryEpisode: number,
	recoveryQueued: boolean,
	recoveryUsed: boolean,
	getRequestCount: number,
	recoveryRequestCount: number,
	skipRequestCount: number,
	acceptedStateCount: number,
	matchReplacementCount: number,
	rejectedInputCount: number,
	applyOutcomeCounts: ApplyOutcomeCounts,
	lastApplyKind: ApplyKind?,
	cleanupFailed: boolean,
	controller: unknown?,
	studioDiagnosticsBridge: BindableFunction?,
	studioRecoverySuspended: boolean,
	studioRecoveryUsed: boolean,
}

local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

export type Controller = typeof(setmetatable({} :: {}, ControllerMethods))
export type ControllerResult = Result.Result<Controller, Error>
export type TestConstructor = (logger: Log.Logger, dependencies: Dependencies) -> ControllerResult

local SERVICE_NAME = "WaveController"
local ENEMY_CONTROLLER_SERVICE_NAME = "EnemyController"
local LOOKUP_TIMEOUT_SECONDS = 5
local STATIC_PREFIX = "[ATD_WAVE_CONTROLLER]"
local STUDIO_DIAGNOSTICS_BRIDGE_NAME = "_ATDPhase11WaveDiagnostics"

local CONTROLLER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ControllerData }

local destroyStudioDiagnosticsBridge: (ControllerData) -> boolean
local installStudioDiagnosticsBridge: (ControllerData) -> ()

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_CONTEXT = table.freeze({ code = "INVALID_CONTEXT" :: "INVALID_CONTEXT" }),
	INVALID_DEPENDENCIES = table.freeze({ code = "INVALID_DEPENDENCIES" :: "INVALID_DEPENDENCIES" }),
	INITIALIZE_FAILED = table.freeze({ code = "INITIALIZE_FAILED" :: "INITIALIZE_FAILED" }),
	START_FAILED = table.freeze({ code = "START_FAILED" :: "START_FAILED" }),
	CLEANUP_FAILED = table.freeze({ code = "CLEANUP_FAILED" :: "CLEANUP_FAILED" }),
	UNAVAILABLE = table.freeze({ code = "UNAVAILABLE" :: "UNAVAILABLE" }),
	REQUEST_PENDING = table.freeze({ code = "REQUEST_PENDING" :: "REQUEST_PENDING" }),
	INVALID_ARGUMENT = table.freeze({ code = "INVALID_ARGUMENT" :: "INVALID_ARGUMENT" }),
	INTERNAL_ERROR = table.freeze({ code = "INTERNAL_ERROR" :: "INTERNAL_ERROR" }),
})

local WaveController = {
	SERVICE_NAME = SERVICE_NAME,
	CONNECTION_COUNT = 3,
	MAX_RECOVERY_REQUESTS_PER_GAP = 1,
	MAX_SKIP_REQUESTS_PENDING = 1,
	newForTests = nil :: TestConstructor?,
	invokeStudioDiagnosticsForTests = nil :: ((Controller, ...unknown) -> unknown)?,
}

local function failure(code: ErrorCode): Result.Failure<Error>
	return Result.err(ERRORS[code])
end

local function staticError(code: string): never
	error(`{STATIC_PREFIX}[code={code}]`, 0)
end

local function requireData(value: unknown): ControllerData
	if type(value) ~= "table" then
		staticError("INVALID_CONTEXT")
	end
	local data = CONTROLLER_DATA[value :: any]
	if data == nil then
		staticError("INVALID_CONTEXT")
	end
	return data
end

local function isSuccess(value: unknown): boolean
	return type(value) == "table" and rawget(value :: any, "ok") == true and rawget(value :: any, "value") ~= nil
end

local function exactDependencyFields(value: { [any]: unknown }): boolean
	local allowed = table.freeze({
		tracker = true,
		getSnapshot = true,
		submitSkipVote = true,
		replicationEvent = true,
		reducer = true,
	})
	local count = 0
	for key in next, value do
		count += 1
		if type(key) ~= "string" or allowed[key] ~= true then
			return false
		end
	end
	return count == 5
end

local function validateRequestEndpoint(value: unknown, endpointName: string): boolean
	if type(value) ~= "table" then
		return false
	end
	local endpoint = value :: any
	local definition = endpoint.definition
	return type(definition) == "table"
		and definition.name == endpointName
		and definition.direction == "ClientToServer"
		and definition.kind == "Request"
		and definition.response == "Required"
		and type(endpoint.connectResponse) == "function"
		and type(endpoint.fire) == "function"
end

local function validateEventEndpoint(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local endpoint = value :: any
	local definition = endpoint.definition
	return type(definition) == "table"
		and definition.name == WaveProtocol.WAVE_REPLICATION_ENDPOINT
		and definition.direction == "ServerToClient"
		and definition.kind == "Event"
		and definition.response == "None"
		and type(endpoint.connectEvent) == "function"
end

local function validateDependencies(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not exactDependencyFields(value :: any) then
		return false
	end
	local dependencies = value :: any
	local tracker = dependencies.tracker
	local reducer = dependencies.reducer
	return type(tracker) == "table"
		and type(tracker.register) == "function"
		and type(tracker.buildRequest) == "function"
		and type(tracker.handleResponse) == "function"
		and type(tracker.cancel) == "function"
		and type(tracker.clear) == "function"
		and validateRequestEndpoint(dependencies.getSnapshot, WaveProtocol.GET_WAVE_SNAPSHOT_ENDPOINT)
		and validateRequestEndpoint(dependencies.submitSkipVote, WaveProtocol.SUBMIT_SKIP_VOTE_ENDPOINT)
		and validateEventEndpoint(dependencies.replicationEvent)
		and type(reducer) == "table"
		and type(reducer.observeEvent) == "function"
		and type(reducer.observeGetResponse) == "function"
		and type(reducer.observeSubmitResponse) == "function"
		and type(reducer.getState) == "function"
		and type(reducer.reset) == "function"
		and type(reducer.cleanup) == "function"
end

local function addConnection(data: ControllerData, connection: unknown): boolean
	if typeof(connection) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, connection :: RBXScriptConnection)
	return true
end

local function cancelRequest(data: ControllerData, fieldName: "getPending" | "skipPending")
	local dependencies = data.dependencies
	local record = data[fieldName]
	data[fieldName] = nil
	if dependencies == nil or record == nil then
		return
	end
	pcall(function()
		dependencies.tracker:cancel(record.pending)
	end)
end

local function readConverged(data: ControllerData): any?
	local dependencies = data.dependencies
	if dependencies == nil then
		return nil
	end
	local called, stateResult = pcall(function()
		return dependencies.reducer:getState()
	end)
	if not called or not isSuccess(stateResult) then
		return nil
	end
	local converged = (stateResult :: any).value
	return if type(converged) == "table" then converged else nil
end

local issueRecovery: (ControllerData) -> boolean

local function reconcileRecovery(data: ControllerData)
	local converged = readConverged(data)
	if converged == nil then
		data.rejectedInputCount += 1
		return
	end
	if converged.recoveryRequired == true then
		if data.getPending ~= nil then
			data.recoveryQueued = true
		else
			issueRecovery(data)
		end
	else
		data.recoveryQueued = false
	end
end

local function issueGet(data: ControllerData, recovery: boolean): boolean
	if
		data.state ~= "Started"
		or not data.callbacksEnabled
		or data.getPending ~= nil
		or data.studioRecoverySuspended
		or (recovery and data.recoveryUsed)
		or (not recovery and data.initialRequestIssued)
	then
		return false
	end
	if recovery then
		data.recoveryUsed = true
		data.recoveryQueued = false
		data.recoveryRequestCount += 1
	else
		data.initialRequestIssued = true
	end
	data.getRequestCount += 1
	local dependencies = data.dependencies :: Dependencies
	local built = dependencies.tracker:buildRequest(WaveProtocol.GET_WAVE_SNAPSHOT_ENDPOINT, {})
	if not isSuccess(built) then
		return false
	end
	local request = (built :: any).value
	if not RequestProtocol.isPending(request.pending) then
		return false
	end
	data.getPending = {
		pending = request.pending,
		matchGeneration = data.matchGeneration,
		recovery = recovery,
		recoveryEpisode = if recovery then data.recoveryEpisode else nil,
	}
	if not pcall(dependencies.getSnapshot.fire, request.envelope) then
		cancelRequest(data, "getPending")
		return false
	end
	return true
end

issueRecovery = function(data: ControllerData): boolean
	if data.getPending ~= nil then
		data.recoveryQueued = true
		return false
	end
	return issueGet(data, true)
end

local function beginRecoveryEpisode(data: ControllerData): boolean
	if data.recoveryEpisode >= Validation.MAX_SAFE_INTEGER then
		data.rejectedInputCount += 1
		return false
	end
	data.recoveryEpisode += 1
	data.recoveryUsed = false
	return true
end

local function requestRecovery(data: ControllerData, forced: boolean, newEpisode: boolean?)
	if data.state ~= "Started" or not data.callbacksEnabled or data.studioRecoverySuspended then
		return
	end
	if newEpisode == true and not beginRecoveryEpisode(data) then
		return
	elseif forced and data.getPending == nil and not data.recoveryUsed and not beginRecoveryEpisode(data) then
		return
	end
	if data.getPending ~= nil then
		if newEpisode == true then
			data.recoveryQueued = true
		end
		return
	end
	if data.recoveryUsed then
		return
	end
	if forced then
		issueRecovery(data)
	else
		reconcileRecovery(data)
	end
end

local function handleGetFailure(data: ControllerData, pending: PendingGetRequest?, retryUnlockedInitial: boolean)
	local converged = readConverged(data)
	if converged == nil then
		if pending ~= nil and not pending.recovery and retryUnlockedInitial then
			requestRecovery(data, true)
		end
		return
	end
	if pending ~= nil and pending.recovery then
		if converged.recoveryRequired == true then
			requestRecovery(data, false)
		elseif converged.locked == true then
			data.recoveryUsed = false
		end
		return
	end
	if converged.recoveryRequired == true or (converged.locked ~= true and retryUnlockedInitial) then
		requestRecovery(data, true)
	end
end

local function resetApplyOutcomeDiagnostics(data: ControllerData)
	local counts = data.applyOutcomeCounts
	counts.Applied = 0
	counts.Replaced = 0
	counts.Duplicate = 0
	counts.Stale = 0
	counts.Skipped = 0
	counts.WrongMatch = 0
	counts.Rejected = 0
	data.lastApplyKind = nil
end

local function recordApplyOutcome(data: ControllerData, kindValue: unknown)
	if
		kindValue ~= "Applied"
		and kindValue ~= "Replaced"
		and kindValue ~= "Duplicate"
		and kindValue ~= "Stale"
		and kindValue ~= "Skipped"
		and kindValue ~= "WrongMatch"
		and kindValue ~= "Rejected"
	then
		return
	end
	local kind = kindValue :: ApplyKind
	local counts = data.applyOutcomeCounts
	counts[kind] = math.min(counts[kind] + 1, Validation.MAX_SAFE_INTEGER)
	data.lastApplyKind = kind
end

local function applyOutcome(data: ControllerData, resultValue: unknown): any?
	if not isSuccess(resultValue) or type((resultValue :: any).value) ~= "table" then
		data.rejectedInputCount += 1
		return nil
	end
	local outcome = (resultValue :: any).value
	recordApplyOutcome(data, outcome.kind)
	if outcome.stateChanged == true then
		data.acceptedStateCount += 1
	end
	if outcome.recoveryRequired ~= true and outcome.kind ~= "WrongMatch" and outcome.kind ~= "Rejected" then
		data.recoveryUsed = false
	end
	if outcome.matchReplaced == true then
		cancelRequest(data, "skipPending")
		data.matchGeneration += 1
		data.matchReplacementCount += 1
		data.recoveryQueued = false
		data.recoveryUsed = false
	end
	if outcome.recoveryRequested == true then
		requestRecovery(data, false, true)
	elseif outcome.recoveryRequired == true then
		requestRecovery(data, false)
	else
		data.recoveryQueued = false
	end
	return outcome
end

local function callbackIsCurrent(data: ControllerData, generation: number): boolean
	return data.callbacksEnabled
		and not data.studioRecoverySuspended
		and data.state == "Started"
		and generation == data.callbackGeneration
end

local function onReplicationEvent(data: ControllerData, generation: number, value: unknown, ...: unknown)
	if not callbackIsCurrent(data, generation) then
		return
	end
	local parsed = RequestProtocol.parseEvent(value, ...)
	if not parsed.ok then
		data.rejectedInputCount += 1
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local called, observed = pcall(function()
		return dependencies.reducer:observeEvent(parsed.value.payload)
	end)
	if not called then
		data.rejectedInputCount += 1
		return
	end
	applyOutcome(data, observed)
end

local function shouldRecoverResponse(response: unknown): boolean
	if not RequestProtocol.isRejected(response) then
		return false
	end
	local code = (response :: RequestProtocol.Rejected).error.code
	return code == "STALE_REQUEST"
		or code == "DUPLICATE_REQUEST"
		or code == "NOT_AUTHORIZED"
		or code == "UNAVAILABLE"
		or code == "INTERNAL_ERROR"
end

local function onGetResponse(data: ControllerData, generation: number, value: unknown, ...: unknown)
	if not callbackIsCurrent(data, generation) then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local pending = data.getPending
	local handled = dependencies.tracker:handleResponse(dependencies.getSnapshot.definition, value, ...)
	if not isSuccess(handled) then
		if
			type(handled) == "table"
			and type((handled :: any).error) == "table"
			and (handled :: any).error.code == "MALFORMED_RESPONSE"
		then
			cancelRequest(data, "getPending")
			data.rejectedInputCount += 1
			handleGetFailure(data, pending, true)
		end
		return
	end
	data.getPending = nil
	local response = (handled :: any).value
	if RequestProtocol.isSuccess(response) then
		local currentRequest = pending ~= nil and pending.matchGeneration == data.matchGeneration
		local confirmsRecoveryEpisode = currentRequest
			and pending ~= nil
			and pending.recovery
			and pending.recoveryEpisode == data.recoveryEpisode
		local called, observed = pcall(function()
			return dependencies.reducer:observeGetResponse(
				(response :: RequestProtocol.Success).payload,
				currentRequest,
				confirmsRecoveryEpisode
			)
		end)
		local outcome = if called then applyOutcome(data, observed) else nil
		if outcome == nil then
			handleGetFailure(data, pending, true)
		end
	elseif shouldRecoverResponse(response) then
		handleGetFailure(data, pending, (response :: RequestProtocol.Rejected).error.code ~= "UNAVAILABLE")
	end
	reconcileRecovery(data)
end

local function onSubmitResponse(data: ControllerData, generation: number, value: unknown, ...: unknown)
	if not callbackIsCurrent(data, generation) then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local handled = dependencies.tracker:handleResponse(dependencies.submitSkipVote.definition, value, ...)
	if not isSuccess(handled) then
		if
			type(handled) == "table"
			and type((handled :: any).error) == "table"
			and (handled :: any).error.code == "MALFORMED_RESPONSE"
		then
			cancelRequest(data, "skipPending")
			data.rejectedInputCount += 1
			requestRecovery(data, true)
		end
		return
	end
	local pending = data.skipPending
	data.skipPending = nil
	local response = (handled :: any).value
	if RequestProtocol.isSuccess(response) and pending ~= nil and pending.matchGeneration == data.matchGeneration then
		local called, observed = pcall(function()
			return dependencies.reducer:observeSubmitResponse((response :: RequestProtocol.Success).payload)
		end)
		local outcome = if called then applyOutcome(data, observed) else nil
		if outcome == nil or outcome.kind == "WrongMatch" or outcome.kind == "Rejected" then
			requestRecovery(data, true)
		end
	elseif shouldRecoverResponse(response) then
		requestRecovery(data, true)
	end
	reconcileRecovery(data)
end

local function cleanup(data: ControllerData): boolean
	if data.state == "Shutdown" then
		return not data.cleanupFailed
	end
	if data.state == "ShuttingDown" then
		data.cleanupFailed = true
		return false
	end
	data.state = "ShuttingDown"
	data.callbacksEnabled = false
	data.callbackGeneration += 1
	local failed = data.cleanupFailed
	if not destroyStudioDiagnosticsBridge(data) then
		failed = true
	end
	local dependencies = data.dependencies
	for index = #data.connections, 1, -1 do
		if not pcall(function()
			data.connections[index]:Disconnect()
		end) then
			failed = true
		end
	end
	table.clear(data.connections)
	cancelRequest(data, "skipPending")
	cancelRequest(data, "getPending")
	if dependencies ~= nil and not pcall(function()
		dependencies.tracker:clear()
	end) then
		failed = true
	end
	if dependencies ~= nil then
		local cleaned, cleanupResult = pcall(function()
			return dependencies.reducer:cleanup()
		end)
		if not cleaned or not isSuccess(cleanupResult) then
			failed = true
		end
	end
	data.getPending = nil
	data.skipPending = nil
	data.recoveryQueued = false
	data.recoveryUsed = false
	data.recoveryEpisode = 0
	data.studioRecoverySuspended = false
	data.studioRecoveryUsed = false
	resetApplyOutcomeDiagnostics(data)
	data.dependencies = nil
	data.controller = nil
	data.cleanupFailed = failed
	data.state = "Shutdown"
	return not failed
end

local function initialize(data: ControllerData)
	if data.state ~= "Constructed" then
		staticError("INVALID_INITIALIZE_STATE")
	end
	data.state = "Initializing"
	local created, dependencies = pcall(data.dependencyFactory)
	if not created or not validateDependencies(dependencies) then
		data.state = "Failed"
		cleanup(data)
		staticError("INITIALIZE_FAILED")
	end
	data.dependencies = dependencies :: Dependencies
	local getRegistration = (dependencies :: Dependencies).tracker:register(
		WaveProtocol.GET_WAVE_SNAPSHOT_ENDPOINT,
		WaveProtocol.GetWaveSnapshotPayloadSchema,
		WaveProtocol.WaveSnapshotSchema
	)
	local skipRegistration = (dependencies :: Dependencies).tracker:register(
		WaveProtocol.SUBMIT_SKIP_VOTE_ENDPOINT,
		WaveProtocol.SubmitSkipVotePayloadSchema,
		WaveProtocol.WaveSnapshotSchema
	)
	if not isSuccess(getRegistration) or not isSuccess(skipRegistration) or readConverged(data) == nil then
		data.state = "Failed"
		cleanup(data)
		staticError("INITIALIZE_FAILED")
	end
	data.state = "Initialized"
end

local function connectOrFail(data: ControllerData, connector: () -> unknown)
	local connected, connection = pcall(connector)
	if not connected or not addConnection(data, connection) then
		cleanup(data)
		staticError("START_FAILED")
	end
end

local function start(data: ControllerData)
	if data.state ~= "Initialized" then
		staticError("INVALID_START_STATE")
	end
	data.state = "Starting"
	data.callbackGeneration += 1
	local generation = data.callbackGeneration
	data.callbacksEnabled = true
	data.state = "Started"
	local dependencies = data.dependencies :: Dependencies
	connectOrFail(data, function()
		return dependencies.replicationEvent.connectEvent(function(value, ...)
			onReplicationEvent(data, generation, value, ...)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.getSnapshot.connectResponse(function(value, ...)
			onGetResponse(data, generation, value, ...)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.submitSkipVote.connectResponse(function(value, ...)
			onSubmitResponse(data, generation, value, ...)
		end)
	end)
	if not issueGet(data, false) then
		requestRecovery(data, true)
	end
	installStudioDiagnosticsBridge(data)
end

local function construct(logger: Log.Logger, dependencyFactory: () -> Dependencies): ControllerResult
	if not Log.isLogger(logger) then
		return failure("INVALID_CONTEXT")
	end
	if type(dependencyFactory) ~= "function" then
		return failure("INVALID_DEPENDENCIES")
	end
	local controller = setmetatable({}, ControllerMethods) :: Controller
	table.freeze(controller)
	CONTROLLER_DATA[controller] = {
		state = "Constructed",
		dependencyFactory = dependencyFactory,
		dependencies = nil,
		connections = {},
		callbacksEnabled = false,
		callbackGeneration = 0,
		matchGeneration = 1,
		getPending = nil,
		skipPending = nil,
		initialRequestIssued = false,
		recoveryEpisode = 0,
		recoveryQueued = false,
		recoveryUsed = false,
		getRequestCount = 0,
		recoveryRequestCount = 0,
		skipRequestCount = 0,
		acceptedStateCount = 0,
		matchReplacementCount = 0,
		rejectedInputCount = 0,
		applyOutcomeCounts = {
			Applied = 0,
			Replaced = 0,
			Duplicate = 0,
			Stale = 0,
			Skipped = 0,
			WrongMatch = 0,
			Rejected = 0,
		},
		lastApplyKind = nil,
		cleanupFailed = false,
		controller = controller,
		studioDiagnosticsBridge = nil,
		studioRecoverySuspended = false,
		studioRecoveryUsed = false,
	}
	return Result.ok(controller)
end

function ControllerMethods.getState(self: Controller): LifecycleState
	return requireData(self).state
end

function ControllerMethods.submitSkipVote(self: Controller, ...: unknown): Result.Result<boolean, Error>
	local data = requireData(self)
	if select("#", ...) ~= 0 then
		return failure("INVALID_ARGUMENT")
	end
	if data.state ~= "Started" or not data.callbacksEnabled or data.studioRecoverySuspended then
		return failure("UNAVAILABLE")
	end
	if data.skipPending ~= nil then
		return failure("REQUEST_PENDING")
	end
	local converged = readConverged(data)
	local snapshot = if converged == nil then nil else converged.snapshot
	if
		type(snapshot) ~= "table"
		or snapshot.state ~= "Running"
		or type(snapshot.skipState) ~= "table"
		or snapshot.skipState.available ~= true
	then
		return failure("UNAVAILABLE")
	end
	local dependencies = data.dependencies :: Dependencies
	local built = dependencies.tracker:buildRequest(WaveProtocol.SUBMIT_SKIP_VOTE_ENDPOINT, {
		matchId = snapshot.matchId,
		waveNumber = snapshot.currentWaveNumber,
	})
	if not isSuccess(built) then
		return failure("INTERNAL_ERROR")
	end
	local request = (built :: any).value
	if not RequestProtocol.isPending(request.pending) then
		return failure("INTERNAL_ERROR")
	end
	data.skipPending = {
		pending = request.pending,
		matchGeneration = data.matchGeneration,
	}
	data.skipRequestCount += 1
	if not pcall(dependencies.submitSkipVote.fire, request.envelope) then
		cancelRequest(data, "skipPending")
		return failure("INTERNAL_ERROR")
	end
	return Result.ok(true)
end

function ControllerMethods.getMetrics(self: Controller): Metrics
	local data = requireData(self)
	local converged = readConverged(data)
	local snapshot = if converged == nil then nil else converged.snapshot
	local outcomeCounts = data.applyOutcomeCounts
	return table.freeze({
		lifecycleState = data.state,
		connectionCount = #data.connections,
		callbackGeneration = data.callbackGeneration,
		matchGeneration = data.matchGeneration,
		getRequestCount = data.getRequestCount,
		recoveryRequestCount = data.recoveryRequestCount,
		getRequestPending = data.getPending ~= nil,
		recoveryQueued = data.recoveryQueued,
		recoveryUsed = data.recoveryUsed,
		skipRequestCount = data.skipRequestCount,
		skipRequestPending = data.skipPending ~= nil,
		acceptedStateCount = data.acceptedStateCount,
		matchReplacementCount = data.matchReplacementCount,
		rejectedInputCount = data.rejectedInputCount,
		applyOutcomeCounts = table.freeze({
			Applied = outcomeCounts.Applied,
			Replaced = outcomeCounts.Replaced,
			Duplicate = outcomeCounts.Duplicate,
			Stale = outcomeCounts.Stale,
			Skipped = outcomeCounts.Skipped,
			WrongMatch = outcomeCounts.WrongMatch,
			Rejected = outcomeCounts.Rejected,
		}),
		lastApplyKind = data.lastApplyKind,
		locked = type(snapshot) == "table",
		matchId = if type(snapshot) == "table" then snapshot.matchId else nil,
		waveRevision = if type(snapshot) == "table" then snapshot.waveRevision else nil,
		recoveryRequired = converged ~= nil and converged.recoveryRequired == true,
		studioRecoverySuspended = data.studioRecoverySuspended,
		studioRecoveryUsed = data.studioRecoveryUsed,
		studioDiagnosticsBridgeCount = if data.studioDiagnosticsBridge == nil then 0 else 1,
	})
end

function ControllerMethods.getStudioDiagnostics(self: Controller): StudioDiagnostics
	local data = requireData(self)
	local converged = readConverged(data)
	return table.freeze({
		controller = self:getMetrics(),
		state = converged,
	})
end

local function suspendStudioRecovery(data: ControllerData): boolean
	if data.studioRecoverySuspended then
		return true
	end
	if data.studioRecoveryUsed or data.state ~= "Started" or not data.callbacksEnabled then
		return false
	end
	data.studioRecoveryUsed = true
	data.studioRecoverySuspended = true
	cancelRequest(data, "skipPending")
	cancelRequest(data, "getPending")
	data.matchGeneration += 1
	data.initialRequestIssued = false
	data.recoveryEpisode = 0
	data.recoveryQueued = false
	data.recoveryUsed = false
	local dependencies = data.dependencies
	if dependencies == nil then
		return false
	end
	local reset, resetResult = pcall(function()
		return dependencies.reducer:reset()
	end)
	local succeeded = reset and isSuccess(resetResult)
	if succeeded then
		resetApplyOutcomeDiagnostics(data)
	end
	return succeeded
end

local function resumeStudioRecovery(data: ControllerData): boolean
	if not data.studioRecoverySuspended then
		return true
	end
	data.studioRecoverySuspended = false
	if issueGet(data, false) then
		return true
	end
	data.studioRecoverySuspended = true
	return false
end

local STUDIO_DIAGNOSTICS_ERRORS = table.freeze({
	INVALID_REQUEST = table.freeze({
		ok = false,
		error = table.freeze({ code = "INVALID_REQUEST" }),
	}),
	UNAVAILABLE = table.freeze({
		ok = false,
		error = table.freeze({ code = "UNAVAILABLE" }),
	}),
	INTERNAL_ERROR = table.freeze({
		ok = false,
		error = table.freeze({ code = "INTERNAL_ERROR" }),
	}),
})

local function isExactStudioDiagnosticsRequest(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local count = 0
	for key in next, value :: any do
		if key ~= "operation" then
			return false
		end
		count += 1
	end
	local operation = (value :: any).operation
	return count == 1
		and (
			operation == "Diagnostics"
			or operation == "SuspendRecovery"
			or operation == "ResumeRecovery"
			or operation == "SubmitSkipVote"
		)
end

local function invokeStudioDiagnostics(data: ControllerData, argumentCount: number, request: unknown): unknown
	if argumentCount ~= 1 or not isExactStudioDiagnosticsRequest(request) then
		return STUDIO_DIAGNOSTICS_ERRORS.INVALID_REQUEST
	end
	local controller = data.controller
	if controller == nil or data.state ~= "Started" then
		return STUDIO_DIAGNOSTICS_ERRORS.UNAVAILABLE
	end
	local operation = (request :: any).operation
	if operation == "SuspendRecovery" then
		if not suspendStudioRecovery(data) then
			return STUDIO_DIAGNOSTICS_ERRORS.INTERNAL_ERROR
		end
	elseif operation == "ResumeRecovery" then
		if not resumeStudioRecovery(data) then
			return STUDIO_DIAGNOSTICS_ERRORS.UNAVAILABLE
		end
	elseif operation == "SubmitSkipVote" then
		local submitted, submitResult = pcall(function()
			return (controller :: Controller):submitSkipVote()
		end)
		if not submitted then
			return STUDIO_DIAGNOSTICS_ERRORS.INTERNAL_ERROR
		end
		if not isSuccess(submitResult) then
			return STUDIO_DIAGNOSTICS_ERRORS.UNAVAILABLE
		end
	end
	local read, diagnostics = pcall(function()
		return (controller :: Controller):getStudioDiagnostics()
	end)
	if not read then
		return STUDIO_DIAGNOSTICS_ERRORS.INTERNAL_ERROR
	end
	return table.freeze({
		ok = true,
		value = diagnostics,
	})
end

function ControllerMethods.getServiceDefinition(self: Controller)
	local data = requireData(self)
	return table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({ ENEMY_CONTROLLER_SERVICE_NAME }),
		initialize = function()
			initialize(data)
		end,
		start = function()
			start(data)
		end,
		shutdown = function()
			if not cleanup(data) then
				staticError("CLEANUP_FAILED")
			end
		end,
	})
end

local function makeProductionDependencies(): Dependencies
	local clientRoot = script.Parent.Parent.Parent
	local common = clientRoot:FindFirstChild("common")
	local networking = if common == nil then nil else common:FindFirstChild("networking")
	if networking == nil then
		staticError("PRODUCTION_NETWORKING_MISSING")
	end
	local lookupModule = networking:FindFirstChild("ClientRemoteLookup")
	local trackerModule = networking:FindFirstChild("ClientRequestTracker")
	if lookupModule == nil or trackerModule == nil then
		staticError("PRODUCTION_NETWORKING_MISSING")
	end
	local ClientRemoteLookup = require(lookupModule :: ModuleScript)
	local ClientRequestTracker = require(trackerModule :: ModuleScript)
	local trackerResult = ClientRequestTracker.new()
	if not isSuccess(trackerResult) then
		staticError("TRACKER_CREATION_FAILED")
	end
	local getLookup = ClientRemoteLookup.resolve(WaveProtocol.GET_WAVE_SNAPSHOT_ENDPOINT, LOOKUP_TIMEOUT_SECONDS)
	local skipLookup = ClientRemoteLookup.resolve(WaveProtocol.SUBMIT_SKIP_VOTE_ENDPOINT, LOOKUP_TIMEOUT_SECONDS)
	local eventLookup = ClientRemoteLookup.resolve(WaveProtocol.WAVE_REPLICATION_ENDPOINT, LOOKUP_TIMEOUT_SECONDS)
	if not isSuccess(getLookup) or not isSuccess(skipLookup) or not isSuccess(eventLookup) then
		staticError("REMOTE_LOOKUP_FAILED")
	end
	local getEndpoint = getLookup.value
	local skipEndpoint = skipLookup.value
	local eventEndpoint = eventLookup.value
	if
		getEndpoint.request == nil
		or getEndpoint.response == nil
		or getEndpoint.event ~= nil
		or skipEndpoint.request == nil
		or skipEndpoint.response == nil
		or skipEndpoint.event ~= nil
		or eventEndpoint.request ~= nil
		or eventEndpoint.response ~= nil
		or eventEndpoint.event == nil
	then
		staticError("REMOTE_SHAPE_INVALID")
	end
	local reducerResult = WaveStateReducer.new()
	if not isSuccess(reducerResult) then
		staticError("REDUCER_CREATION_FAILED")
	end
	local getRequest = getEndpoint.request :: RemoteEvent
	local getResponse = getEndpoint.response :: RemoteEvent
	local skipRequest = skipEndpoint.request :: RemoteEvent
	local skipResponse = skipEndpoint.response :: RemoteEvent
	local event = eventEndpoint.event :: RemoteEvent
	return {
		tracker = trackerResult.value,
		getSnapshot = {
			definition = getEndpoint.definition,
			connectResponse = function(listener: ResponseListener): RBXScriptConnection
				return getResponse.OnClientEvent:Connect(listener)
			end,
			fire = function(envelope: RequestProtocol.RawRequest)
				getRequest:FireServer(envelope)
			end,
		},
		submitSkipVote = {
			definition = skipEndpoint.definition,
			connectResponse = function(listener: ResponseListener): RBXScriptConnection
				return skipResponse.OnClientEvent:Connect(listener)
			end,
			fire = function(envelope: RequestProtocol.RawRequest)
				skipRequest:FireServer(envelope)
			end,
		},
		replicationEvent = {
			definition = eventEndpoint.definition,
			connectEvent = function(listener: EventListener): RBXScriptConnection
				return event.OnClientEvent:Connect(listener)
			end,
		},
		reducer = reducerResult.value,
	}
end

function WaveController.new(logger: Log.Logger): ControllerResult
	return construct(logger, makeProductionDependencies)
end

local function isProductionStudioClient(): boolean
	local checked, valid = pcall(function(): boolean
		local localPlayer = Players.LocalPlayer
		local playerScripts = if localPlayer == nil then nil else localPlayer:FindFirstChild("PlayerScripts")
		return RunService:IsStudio()
			and RunService:IsClient()
			and playerScripts ~= nil
			and script:IsDescendantOf(playerScripts)
	end)
	return checked and valid == true
end

destroyStudioDiagnosticsBridge = function(data: ControllerData): boolean
	local bridge = data.studioDiagnosticsBridge
	data.studioDiagnosticsBridge = nil
	if bridge == nil then
		return true
	end
	return pcall(function()
		bridge.OnInvoke = nil
		bridge:Destroy()
	end)
end

installStudioDiagnosticsBridge = function(data: ControllerData)
	if not isProductionStudioClient() or data.studioDiagnosticsBridge ~= nil then
		return
	end
	local localPlayer = Players.LocalPlayer
	local playerScripts = if localPlayer == nil then nil else localPlayer:FindFirstChild("PlayerScripts")
	if playerScripts == nil or playerScripts:FindFirstChild(STUDIO_DIAGNOSTICS_BRIDGE_NAME) ~= nil then
		return
	end

	local bridge = Instance.new("BindableFunction")
	local installed = pcall(function()
		bridge.Name = STUDIO_DIAGNOSTICS_BRIDGE_NAME
		bridge.OnInvoke = function(...: unknown): unknown
			return invokeStudioDiagnostics(data, select("#", ...), ...)
		end
		if playerScripts:FindFirstChild(STUDIO_DIAGNOSTICS_BRIDGE_NAME) ~= nil then
			return
		end
		bridge.Parent = playerScripts
	end)
	if not installed or bridge.Parent ~= playerScripts then
		pcall(function()
			bridge.OnInvoke = nil
			bridge:Destroy()
		end)
		return
	end
	data.studioDiagnosticsBridge = bridge
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "WaveController" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionClientWaves" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

if isExactTestModule() then
	WaveController.newForTests = function(logger: Log.Logger, dependencies: Dependencies): ControllerResult
		if not validateDependencies(dependencies) then
			return failure("INVALID_DEPENDENCIES")
		end
		local copy: Dependencies = {
			tracker = dependencies.tracker,
			getSnapshot = dependencies.getSnapshot,
			submitSkipVote = dependencies.submitSkipVote,
			replicationEvent = dependencies.replicationEvent,
			reducer = dependencies.reducer,
		}
		return construct(logger, function(): Dependencies
			return copy
		end)
	end
	WaveController.invokeStudioDiagnosticsForTests = function(controller: Controller, ...: unknown): unknown
		local data = requireData(controller)
		return invokeStudioDiagnostics(data, select("#", ...), ...)
	end
end

table.freeze(ControllerMethods)
return table.freeze(WaveController)
