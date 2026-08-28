--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Log = require(ReplicatedStorage.Shared.logging.Log)
local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)

local BaseStateReducer = require(script.Parent.BaseStateReducer)
local BaseViewModel = require(script.Parent.BaseViewModel)
local BaseWorldView = require(script.Parent.BaseWorldView)

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

export type Error = {
	code: ErrorCode,
}

export type Metrics = {
	lifecycleState: LifecycleState,
	connectionCount: number,
	snapshotAttemptCount: number,
	studioRecoveryAttemptCount: number,
	snapshotRequestPending: boolean,
	acceptedStateCount: number,
	feedbackCount: number,
	rejectedInputCount: number,
	studioRecoverySuspended: boolean,
	studioRecoveryUsed: boolean,
	locked: boolean,
	matchId: string?,
	enemyEpoch: number?,
	baseRevision: number?,
	view: unknown?,
}

export type StudioDiagnostics = {
	controller: Metrics,
	view: unknown?,
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
	observeSnapshot: (self: ReducerAdapter, value: unknown) -> any,
	observeMessage: (self: ReducerAdapter, value: unknown) -> any,
	getState: (self: ReducerAdapter) -> any,
	cleanup: (self: ReducerAdapter) -> any,
}

export type ViewAdapter = {
	render: (self: ViewAdapter, value: unknown) -> any,
	getMetrics: (self: ViewAdapter) -> any,
	cleanup: (self: ViewAdapter) -> any,
}

export type ProjectView = (snapshot: unknown, feedback: unknown?) -> any

export type Dependencies = {
	tracker: TrackerAdapter,
	getSnapshot: RequestEndpoint,
	replicationEvent: EventEndpoint,
	reducer: ReducerAdapter,
	view: ViewAdapter,
	projectView: ProjectView,
}

type ControllerData = {
	controller: any?,
	state: LifecycleState,
	dependencyFactory: () -> Dependencies,
	dependencies: Dependencies?,
	connections: { RBXScriptConnection },
	callbacksEnabled: boolean,
	pending: RequestProtocol.Pending?,
	snapshotAttemptCount: number,
	studioRecoveryAttemptCount: number,
	acceptedStateCount: number,
	feedbackCount: number,
	rejectedInputCount: number,
	studioDiagnosticsBridge: BindableFunction?,
	studioRecoverySuspended: boolean,
	studioRecoveryNeedsRender: boolean,
	studioRecoveryUsed: boolean,
	cleanupFailed: boolean,
}

local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

export type Controller = typeof(setmetatable({} :: {}, ControllerMethods))
export type ControllerResult = Result.Result<Controller, Error>
export type TestConstructor = (logger: Log.Logger, dependencies: Dependencies) -> ControllerResult

local SERVICE_NAME = "BaseController"
local MATCH_READY_SERVICE_NAME = "MatchReadyController"
local LOOKUP_TIMEOUT_SECONDS = 5
local MAX_SNAPSHOT_ATTEMPTS = 2
local STUDIO_DIAGNOSTICS_BRIDGE_NAME = "_ATDPhase10BaseDiagnostics"
local STATIC_PREFIX = "[ATD_BASE_CONTROLLER]"

local CONTROLLER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ControllerData }

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_CONTEXT = table.freeze({ code = "INVALID_CONTEXT" :: "INVALID_CONTEXT" }),
	INVALID_DEPENDENCIES = table.freeze({ code = "INVALID_DEPENDENCIES" :: "INVALID_DEPENDENCIES" }),
	INITIALIZE_FAILED = table.freeze({ code = "INITIALIZE_FAILED" :: "INITIALIZE_FAILED" }),
	START_FAILED = table.freeze({ code = "START_FAILED" :: "START_FAILED" }),
	CLEANUP_FAILED = table.freeze({ code = "CLEANUP_FAILED" :: "CLEANUP_FAILED" }),
})

local BaseController = {
	SERVICE_NAME = SERVICE_NAME,
	MAX_SNAPSHOT_ATTEMPTS = MAX_SNAPSHOT_ATTEMPTS,
	STUDIO_DIAGNOSTICS_BRIDGE_NAME = STUDIO_DIAGNOSTICS_BRIDGE_NAME,
	newForTests = nil :: TestConstructor?,
	invokeStudioDiagnosticsForTests = nil :: ((Controller, ...unknown) -> unknown)?,
}

local destroyStudioDiagnosticsBridge: (ControllerData) -> boolean
local installStudioDiagnosticsBridge: (ControllerData) -> ()

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

local function validateRequestEndpoint(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local endpoint = value :: any
	local definition = endpoint.definition
	return type(definition) == "table"
		and definition.name == BaseProtocol.GET_BASE_SNAPSHOT_ENDPOINT
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
		and definition.name == BaseProtocol.BASE_REPLICATION_ENDPOINT
		and definition.direction == "ServerToClient"
		and definition.kind == "Event"
		and definition.response == "None"
		and type(endpoint.connectEvent) == "function"
end

local function validateDependencies(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local dependencies = value :: any
	local allowed = table.freeze({
		tracker = true,
		getSnapshot = true,
		replicationEvent = true,
		reducer = true,
		view = true,
		projectView = true,
	})
	local count = 0
	for key in next, dependencies do
		if type(key) ~= "string" or allowed[key] ~= true then
			return false
		end
		count += 1
	end
	local tracker = dependencies.tracker
	local reducer = dependencies.reducer
	local view = dependencies.view
	return count == 6
		and type(tracker) == "table"
		and type(tracker.register) == "function"
		and type(tracker.buildRequest) == "function"
		and type(tracker.handleResponse) == "function"
		and type(tracker.cancel) == "function"
		and type(tracker.clear) == "function"
		and validateRequestEndpoint(dependencies.getSnapshot)
		and validateEventEndpoint(dependencies.replicationEvent)
		and type(reducer) == "table"
		and type(reducer.observeSnapshot) == "function"
		and type(reducer.observeMessage) == "function"
		and type(reducer.getState) == "function"
		and type(reducer.cleanup) == "function"
		and type(view) == "table"
		and type(view.render) == "function"
		and type(view.getMetrics) == "function"
		and type(view.cleanup) == "function"
		and type(dependencies.projectView) == "function"
end

local function addConnection(data: ControllerData, connection: unknown): boolean
	if typeof(connection) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, connection :: RBXScriptConnection)
	return true
end

local function cancelPending(data: ControllerData)
	local dependencies = data.dependencies
	local pending = data.pending
	if dependencies == nil or pending == nil then
		return
	end
	pcall(function()
		dependencies.tracker:cancel(pending)
	end)
	data.pending = nil
end

local function renderCurrent(data: ControllerData, feedback: unknown?): boolean
	local dependencies = data.dependencies
	if dependencies == nil then
		return false
	end
	local read, stateResult = pcall(function()
		return dependencies.reducer:getState()
	end)
	if not read or not isSuccess(stateResult) then
		return false
	end
	local converged = (stateResult :: any).value
	local snapshot = if type(converged) == "table" then converged.snapshot else nil
	local projected, viewStateResult = pcall(dependencies.projectView, snapshot, feedback)
	if not projected or not isSuccess(viewStateResult) then
		return false
	end
	local rendered, renderResult = pcall(function()
		return dependencies.view:render((viewStateResult :: any).value)
	end)
	return rendered and isSuccess(renderResult)
end

local function renderHidden(data: ControllerData): boolean
	local dependencies = data.dependencies
	if dependencies == nil then
		return false
	end
	local projected, viewStateResult = pcall(dependencies.projectView, nil, nil)
	if not projected or not isSuccess(viewStateResult) then
		return false
	end
	local rendered, renderResult = pcall(function()
		return dependencies.view:render((viewStateResult :: any).value)
	end)
	return rendered and isSuccess(renderResult)
end

local function requestSnapshot(data: ControllerData): boolean
	local dependencies = data.dependencies
	if
		dependencies == nil
		or not data.callbacksEnabled
		or data.studioRecoverySuspended
		or data.state ~= "Started"
		or data.pending ~= nil
	then
		return false
	end
	local useStudioRecovery = data.studioRecoveryUsed and data.studioRecoveryNeedsRender
	local function attemptCount(): number
		return if useStudioRecovery then data.studioRecoveryAttemptCount else data.snapshotAttemptCount
	end
	while attemptCount() < MAX_SNAPSHOT_ATTEMPTS and data.pending == nil do
		if useStudioRecovery then
			data.studioRecoveryAttemptCount += 1
		else
			data.snapshotAttemptCount += 1
		end
		local built = dependencies.tracker:buildRequest(BaseProtocol.GET_BASE_SNAPSHOT_ENDPOINT, {})
		if not isSuccess(built) then
			return false
		end
		local request = (built :: any).value
		if not RequestProtocol.isPending(request.pending) then
			return false
		end
		data.pending = request.pending
		if pcall(dependencies.getSnapshot.fire, request.envelope) then
			return true
		end
		cancelPending(data)
	end
	return false
end

local function retrySnapshot(data: ControllerData)
	local attemptCount = if data.studioRecoveryUsed and data.studioRecoveryNeedsRender
		then data.studioRecoveryAttemptCount
		else data.snapshotAttemptCount
	if data.pending == nil and attemptCount < MAX_SNAPSHOT_ATTEMPTS then
		requestSnapshot(data)
	end
end

local function observeOutcome(data: ControllerData, observed: unknown): boolean
	if not isSuccess(observed) then
		data.rejectedInputCount += 1
		return false
	end
	local outcome = (observed :: any).value
	if type(outcome) ~= "table" then
		data.rejectedInputCount += 1
		return false
	end
	local feedback = outcome.feedback
	if outcome.stateChanged == true then
		data.acceptedStateCount += 1
	end
	if feedback ~= nil then
		data.feedbackCount += 1
	end
	local recoveredFromSuspension = data.studioRecoveryNeedsRender
		and (outcome.kind == "Applied" or outcome.kind == "Feedback" or outcome.kind == "Duplicate")
	if outcome.stateChanged == true or feedback ~= nil or recoveredFromSuspension then
		local rendered = renderCurrent(data, feedback)
		if rendered and recoveredFromSuspension then
			data.studioRecoveryNeedsRender = false
		end
		return rendered
	end
	return true
end

local function onReplicationEvent(data: ControllerData, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.studioRecoverySuspended or data.state ~= "Started" then
		return
	end
	local parsed = RequestProtocol.parseEvent(value, ...)
	if not parsed.ok then
		data.rejectedInputCount += 1
		retrySnapshot(data)
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local observedCall, observed = pcall(function()
		return dependencies.reducer:observeMessage(parsed.value.payload)
	end)
	if not observedCall or not observeOutcome(data, observed) then
		retrySnapshot(data)
	end
end

local function shouldRetryResponse(value: unknown): boolean
	if not RequestProtocol.isRejected(value) then
		return false
	end
	local code = (value :: RequestProtocol.Rejected).error.code
	return code == "STALE_REQUEST"
		or code == "DUPLICATE_REQUEST"
		or code == "NOT_AUTHORIZED"
		or code == "UNAVAILABLE"
		or code == "INTERNAL_ERROR"
end

local function onSnapshotResponse(data: ControllerData, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.studioRecoverySuspended or data.state ~= "Started" then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local handled = dependencies.tracker:handleResponse(dependencies.getSnapshot.definition, value, ...)
	if not isSuccess(handled) then
		if
			type(handled) == "table"
			and type((handled :: any).error) == "table"
			and (handled :: any).error.code == "MALFORMED_RESPONSE"
		then
			cancelPending(data)
			data.rejectedInputCount += 1
			retrySnapshot(data)
		end
		return
	end
	data.pending = nil
	local response = (handled :: any).value
	if RequestProtocol.isSuccess(response) then
		local observedCall, observed = pcall(function()
			return dependencies.reducer:observeSnapshot((response :: RequestProtocol.Success).payload)
		end)
		if not observedCall or not observeOutcome(data, observed) then
			retrySnapshot(data)
		end
	elseif shouldRetryResponse(response) then
		retrySnapshot(data)
	end
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
	local failed = data.cleanupFailed
	local dependencies = data.dependencies
	for index = #data.connections, 1, -1 do
		if not pcall(function()
			data.connections[index]:Disconnect()
		end) then
			failed = true
		end
	end
	table.clear(data.connections)
	if not destroyStudioDiagnosticsBridge(data) then
		failed = true
	end
	cancelPending(data)
	if dependencies ~= nil and not pcall(function()
		dependencies.tracker:clear()
	end) then
		failed = true
	end
	if dependencies ~= nil then
		local viewCleaned, viewResult = pcall(function()
			return dependencies.view:cleanup()
		end)
		if not viewCleaned or not isSuccess(viewResult) then
			failed = true
		end
		local reducerCleaned, reducerResult = pcall(function()
			return dependencies.reducer:cleanup()
		end)
		if not reducerCleaned or not isSuccess(reducerResult) then
			failed = true
		end
	end
	data.pending = nil
	data.studioRecoverySuspended = false
	data.studioRecoveryNeedsRender = false
	data.studioRecoveryUsed = false
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
	local registration = (dependencies :: Dependencies).tracker:register(
		BaseProtocol.GET_BASE_SNAPSHOT_ENDPOINT,
		BaseProtocol.GetBaseSnapshotPayloadSchema,
		BaseProtocol.BaseSnapshotSchema
	)
	if not isSuccess(registration) or not renderCurrent(data, nil) then
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
	data.callbacksEnabled = true
	data.state = "Started"
	local dependencies = data.dependencies :: Dependencies
	-- The event listener is installed first, then the response listener, before
	-- the exact empty request. Every interleaving converges through one reducer.
	connectOrFail(data, function()
		return dependencies.replicationEvent.connectEvent(function(value, ...)
			onReplicationEvent(data, value, ...)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.getSnapshot.connectResponse(function(value, ...)
			onSnapshotResponse(data, value, ...)
		end)
	end)
	requestSnapshot(data)
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
		controller = controller,
		state = "Constructed",
		dependencyFactory = dependencyFactory,
		dependencies = nil,
		connections = {},
		callbacksEnabled = false,
		pending = nil,
		snapshotAttemptCount = 0,
		studioRecoveryAttemptCount = 0,
		acceptedStateCount = 0,
		feedbackCount = 0,
		rejectedInputCount = 0,
		studioDiagnosticsBridge = nil,
		studioRecoverySuspended = false,
		studioRecoveryNeedsRender = false,
		studioRecoveryUsed = false,
		cleanupFailed = false,
	}
	return Result.ok(controller)
end

function ControllerMethods.getState(self: Controller): LifecycleState
	return requireData(self).state
end

function ControllerMethods.getMetrics(self: Controller): Metrics
	local data = requireData(self)
	local locked = false
	local matchId: string? = nil
	local enemyEpoch: number? = nil
	local baseRevision: number? = nil
	local viewMetrics: unknown? = nil
	local dependencies = data.dependencies
	if dependencies ~= nil then
		local stateRead, stateResult = pcall(function()
			return dependencies.reducer:getState()
		end)
		if stateRead and isSuccess(stateResult) then
			local converged = (stateResult :: any).value
			local snapshot = if type(converged) == "table" then converged.snapshot else nil
			if type(snapshot) == "table" then
				locked = true
				matchId = snapshot.matchId
				enemyEpoch = snapshot.enemyEpoch
				baseRevision = snapshot.baseRevision
			end
		end
		local viewRead, viewResult = pcall(function()
			return dependencies.view:getMetrics()
		end)
		if viewRead and isSuccess(viewResult) then
			viewMetrics = (viewResult :: any).value
		end
	end
	return table.freeze({
		lifecycleState = data.state,
		connectionCount = #data.connections,
		snapshotAttemptCount = data.snapshotAttemptCount,
		studioRecoveryAttemptCount = data.studioRecoveryAttemptCount,
		snapshotRequestPending = data.pending ~= nil,
		acceptedStateCount = data.acceptedStateCount,
		feedbackCount = data.feedbackCount,
		rejectedInputCount = data.rejectedInputCount,
		studioRecoverySuspended = data.studioRecoverySuspended,
		studioRecoveryUsed = data.studioRecoveryUsed,
		locked = locked,
		matchId = matchId,
		enemyEpoch = enemyEpoch,
		baseRevision = baseRevision,
		view = viewMetrics,
	})
end

function ControllerMethods.getStudioDiagnostics(self: Controller): StudioDiagnostics
	local controllerMetrics = self:getMetrics()
	return table.freeze({
		controller = controllerMetrics,
		view = controllerMetrics.view,
	})
end

local function suspendStudioRecovery(data: ControllerData): boolean
	if data.studioRecoverySuspended then
		return true
	end
	if data.studioRecoveryUsed then
		return false
	end
	data.studioRecoveryUsed = true
	data.studioRecoverySuspended = true
	data.studioRecoveryNeedsRender = true
	cancelPending(data)
	return renderHidden(data)
end

local function resumeStudioRecovery(data: ControllerData): boolean
	if not data.studioRecoverySuspended then
		return true
	end
	if data.studioRecoveryAttemptCount >= MAX_SNAPSHOT_ATTEMPTS then
		return false
	end
	data.studioRecoverySuspended = false
	if requestSnapshot(data) then
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
		and (operation == "Diagnostics" or operation == "SuspendRecovery" or operation == "ResumeRecovery")
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
	elseif operation == "ResumeRecovery" and not resumeStudioRecovery(data) then
		return STUDIO_DIAGNOSTICS_ERRORS.UNAVAILABLE
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
		dependencies = table.freeze({ MATCH_READY_SERVICE_NAME }),
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
	local requestLookup = ClientRemoteLookup.resolve(BaseProtocol.GET_BASE_SNAPSHOT_ENDPOINT, LOOKUP_TIMEOUT_SECONDS)
	local eventLookup = ClientRemoteLookup.resolve(BaseProtocol.BASE_REPLICATION_ENDPOINT, LOOKUP_TIMEOUT_SECONDS)
	if not isSuccess(requestLookup) or not isSuccess(eventLookup) then
		staticError("REMOTE_LOOKUP_FAILED")
	end
	local requestEndpoint = requestLookup.value
	local eventEndpoint = eventLookup.value
	if
		requestEndpoint.request == nil
		or requestEndpoint.response == nil
		or requestEndpoint.event ~= nil
		or eventEndpoint.request ~= nil
		or eventEndpoint.response ~= nil
		or eventEndpoint.event == nil
	then
		staticError("REMOTE_SHAPE_INVALID")
	end
	local reducerResult = BaseStateReducer.new()
	local viewResult = BaseWorldView.new()
	if not isSuccess(reducerResult) or not isSuccess(viewResult) then
		staticError("PRESENTATION_CREATION_FAILED")
	end
	local request = requestEndpoint.request :: RemoteEvent
	local response = requestEndpoint.response :: RemoteEvent
	local event = eventEndpoint.event :: RemoteEvent
	return {
		tracker = trackerResult.value,
		getSnapshot = {
			definition = requestEndpoint.definition,
			connectResponse = function(listener: ResponseListener): RBXScriptConnection
				return response.OnClientEvent:Connect(listener)
			end,
			fire = function(envelope: RequestProtocol.RawRequest)
				request:FireServer(envelope)
			end,
		},
		replicationEvent = {
			definition = eventEndpoint.definition,
			connectEvent = function(listener: EventListener): RBXScriptConnection
				return event.OnClientEvent:Connect(listener)
			end,
		},
		reducer = reducerResult.value,
		view = viewResult.value,
		projectView = BaseViewModel.project,
	}
end

function BaseController.new(logger: Log.Logger): ControllerResult
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

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "BaseController" then
		return false
	end
	local folder = script.Parent
	local automatedTests = folder.Parent
	return folder:IsA("Folder")
		and folder.Name == "ProductionClientBase"
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
		and ServerScriptService:FindFirstChild("Server") == nil
end

if testModuleIdentityIsExact() then
	BaseController.newForTests = function(logger: Log.Logger, dependencies: Dependencies): ControllerResult
		return construct(logger, function(): Dependencies
			return dependencies
		end)
	end
	BaseController.invokeStudioDiagnosticsForTests = function(controller: Controller, ...: unknown): unknown
		local data = requireData(controller)
		return invokeStudioDiagnostics(data, select("#", ...), ...)
	end
end

table.freeze(ControllerMethods)
return table.freeze(BaseController)
