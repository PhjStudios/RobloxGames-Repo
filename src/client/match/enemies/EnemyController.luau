--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Log = require(ReplicatedStorage.Shared.logging.Log)
local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local EnemyRenderer = require(script.Parent.EnemyRenderer)
local EnemyReplicationState = require(script.Parent.EnemyReplicationState)

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
	renderConnectionCount: number,
	renderPassCount: number,
	renderDurationSampleCount: number,
	renderDurationP50Milliseconds: number,
	renderDurationP95Milliseconds: number,
	renderDurationMaximumMilliseconds: number,
	snapshotRefreshCount: number,
	snapshotAttemptCount: number,
	snapshotRequestPending: boolean,
	studioRecoverySuspended: boolean,
	cachedLocked: boolean,
	cachedMatchId: string?,
	cachedEnemyEpoch: number?,
	cachedLastSequence: number?,
	cachedEntryCount: number,
	cachedRecoveryRequired: boolean,
}

export type StudioDiagnostics = {
	controller: Metrics,
	replication: unknown,
	renderer: unknown?,
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

export type StateAdapter = {
	observeMessage: (self: StateAdapter, message: unknown) -> any,
	observeReceipt: (self: StateAdapter, receipt: unknown, now: unknown) -> any,
	advance: (self: StateAdapter, now: unknown) -> any,
	getSnapshot: (self: StateAdapter) -> any,
	cleanup: (self: StateAdapter) -> any,
}

export type RendererAdapter = {
	render: (self: RendererAdapter, snapshot: unknown, serverTime: unknown) -> any,
	reset: (self: RendererAdapter) -> any,
	cleanup: (self: RendererAdapter) -> any,
}

export type Dependencies = {
	tracker: TrackerAdapter,
	getSnapshot: RequestEndpoint,
	replicationEvent: EventEndpoint,
	state: StateAdapter,
	renderer: RendererAdapter,
	connectPreRender: (() -> ()) -> RBXScriptConnection,
	getServerTimeNow: () -> unknown,
}

type ControllerData = {
	controller: any?,
	logger: Log.Logger,
	state: LifecycleState,
	dependencyFactory: () -> Dependencies,
	dependencies: Dependencies?,
	connections: { RBXScriptConnection },
	callbacksEnabled: boolean,
	pending: RequestProtocol.Pending?,
	attemptCount: number,
	forcedRecoveryQueued: boolean,
	lastServerTime: number?,
	cachedSnapshot: any?,
	snapshotRefreshCount: number,
	renderConnectionCount: number,
	renderPassCount: number,
	renderDurationSamples: { number },
	renderDurationWriteIndex: number,
	renderDurationMaximum: number,
	studioDiagnosticsBridge: BindableFunction?,
	studioRecoverySuspended: boolean,
	cleanupFailed: boolean,
}

local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

export type Controller = typeof(setmetatable({} :: {}, ControllerMethods))
export type ControllerResult = Result.Result<Controller, Error>
export type TestConstructor = (logger: Log.Logger, dependencies: Dependencies) -> ControllerResult

local activeStudioController: Controller? = nil

local SERVICE_NAME = "EnemyController"
local MATCH_READY_SERVICE_NAME = "MatchReadyController"
local LOOKUP_TIMEOUT_SECONDS = 5
local MAX_RENDER_DURATION_SAMPLES = 1_024
local STUDIO_DIAGNOSTICS_BRIDGE_NAME = "_ATDPhase09EnemyDiagnostics"
local STATIC_PREFIX = "[ATD_ENEMY_CONTROLLER]"

local CONTROLLER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ControllerData }

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_CONTEXT = table.freeze({ code = "INVALID_CONTEXT" :: "INVALID_CONTEXT" }),
	INVALID_DEPENDENCIES = table.freeze({ code = "INVALID_DEPENDENCIES" :: "INVALID_DEPENDENCIES" }),
	INITIALIZE_FAILED = table.freeze({ code = "INITIALIZE_FAILED" :: "INITIALIZE_FAILED" }),
	START_FAILED = table.freeze({ code = "START_FAILED" :: "START_FAILED" }),
	CLEANUP_FAILED = table.freeze({ code = "CLEANUP_FAILED" :: "CLEANUP_FAILED" }),
})

local EnemyController = {
	SERVICE_NAME = SERVICE_NAME,
	MAX_SNAPSHOT_ATTEMPTS = EnemyProtocol.MAX_CLIENT_SNAPSHOT_ATTEMPTS,
	STUDIO_DIAGNOSTICS_BRIDGE_NAME = STUDIO_DIAGNOSTICS_BRIDGE_NAME,
	newForTests = nil :: TestConstructor?,
	getStudioDiagnostics = nil :: (() -> StudioDiagnostics?)?,
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
		and definition.name == EnemyProtocol.GET_ENEMY_SNAPSHOT_ENDPOINT
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
		and definition.name == EnemyProtocol.ENEMY_REPLICATION_ENDPOINT
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
	local allowed = {
		tracker = true,
		getSnapshot = true,
		replicationEvent = true,
		state = true,
		renderer = true,
		connectPreRender = true,
		getServerTimeNow = true,
	}
	local count = 0
	for key in next, dependencies do
		if type(key) ~= "string" or allowed[key] ~= true then
			return false
		end
		count += 1
	end
	local tracker = dependencies.tracker
	local state = dependencies.state
	local renderer = dependencies.renderer
	return count == 7
		and type(tracker) == "table"
		and type(tracker.register) == "function"
		and type(tracker.buildRequest) == "function"
		and type(tracker.handleResponse) == "function"
		and type(tracker.cancel) == "function"
		and type(tracker.clear) == "function"
		and validateRequestEndpoint(dependencies.getSnapshot)
		and validateEventEndpoint(dependencies.replicationEvent)
		and type(state) == "table"
		and type(state.observeMessage) == "function"
		and type(state.observeReceipt) == "function"
		and type(state.advance) == "function"
		and type(state.getSnapshot) == "function"
		and type(state.cleanup) == "function"
		and type(renderer) == "table"
		and type(renderer.render) == "function"
		and type(renderer.reset) == "function"
		and type(renderer.cleanup) == "function"
		and type(dependencies.connectPreRender) == "function"
		and type(dependencies.getServerTimeNow) == "function"
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
		local stateCleaned, stateResult = pcall(function()
			return dependencies.state:cleanup()
		end)
		if not stateCleaned or not isSuccess(stateResult) then
			failed = true
		end
		local rendererCleaned, rendererResult = pcall(function()
			return dependencies.renderer:cleanup()
		end)
		if not rendererCleaned or not isSuccess(rendererResult) then
			failed = true
		end
	end

	data.pending = nil
	data.forcedRecoveryQueued = false
	data.studioRecoverySuspended = false
	data.lastServerTime = nil
	data.cachedSnapshot = nil
	data.renderConnectionCount = 0
	table.clear(data.renderDurationSamples)
	data.renderDurationWriteIndex = 1
	data.dependencies = nil
	if activeStudioController == data.controller then
		activeStudioController = nil
	end
	data.controller = nil
	data.cleanupFailed = failed
	data.state = "Shutdown"
	return not failed
end

local function failAfterStart(data: ControllerData)
	if data.state == "Started" then
		cleanup(data)
	end
end

local function sampleServerTime(data: ControllerData): number?
	local dependencies = data.dependencies
	if dependencies == nil then
		return nil
	end
	local sampled, value = pcall(dependencies.getServerTimeNow)
	if
		not sampled
		or type(value) ~= "number"
		or not Validation.isFiniteNumber(value :: number)
		or (value :: number) < 0
		or (data.lastServerTime ~= nil and (value :: number) < (data.lastServerTime :: number))
	then
		return nil
	end
	data.lastServerTime = value :: number
	return value :: number
end

local function refreshSnapshot(data: ControllerData): boolean
	local dependencies = data.dependencies
	if dependencies == nil then
		return false
	end
	local read, snapshotResult = pcall(function()
		return dependencies.state:getSnapshot()
	end)
	if not read or not isSuccess(snapshotResult) then
		return false
	end
	data.cachedSnapshot = (snapshotResult :: any).value
	data.snapshotRefreshCount += 1
	return true
end

local function stateNeedsRecovery(data: ControllerData): boolean
	local snapshot = data.cachedSnapshot
	return type(snapshot) == "table" and snapshot.recoveryRequired == true
end

local issueSnapshotRequest: (ControllerData) -> boolean
local requestRecovery: (ControllerData, boolean) -> ()

issueSnapshotRequest = function(data: ControllerData): boolean
	if
		not data.callbacksEnabled
		or data.state ~= "Started"
		or data.studioRecoverySuspended
		or data.pending ~= nil
		or data.attemptCount >= EnemyProtocol.MAX_CLIENT_SNAPSHOT_ATTEMPTS
	then
		return false
	end
	data.attemptCount += 1
	local dependencies = data.dependencies :: Dependencies
	local built = dependencies.tracker:buildRequest(EnemyProtocol.GET_ENEMY_SNAPSHOT_ENDPOINT, {})
	if not isSuccess(built) then
		return false
	end
	local request = (built :: any).value
	if not RequestProtocol.isPending(request.pending) then
		return false
	end
	data.pending = request.pending
	if not pcall(dependencies.getSnapshot.fire, request.envelope) then
		cancelPending(data)
		return false
	end
	return true
end

requestRecovery = function(data: ControllerData, forced: boolean)
	if not data.callbacksEnabled or data.state ~= "Started" or data.studioRecoverySuspended then
		return
	end
	if data.pending ~= nil then
		if forced then
			data.forcedRecoveryQueued = true
		end
		return
	end
	if data.attemptCount >= EnemyProtocol.MAX_CLIENT_SNAPSHOT_ATTEMPTS then
		data.forcedRecoveryQueued = false
		return
	end
	if not forced and not stateNeedsRecovery(data) then
		return
	end
	data.forcedRecoveryQueued = false
	issueSnapshotRequest(data)
end

local function reconcileRecovery(data: ControllerData)
	local forced = data.forcedRecoveryQueued
	data.forcedRecoveryQueued = false
	requestRecovery(data, forced)
	if not forced then
		requestRecovery(data, false)
	end
end

local function onReplicationEvent(data: ControllerData, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.state ~= "Started" or data.studioRecoverySuspended then
		return
	end
	local parsed = RequestProtocol.parseEvent(value, ...)
	if not parsed.ok then
		requestRecovery(data, true)
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local observed = dependencies.state:observeMessage(parsed.value.payload)
	if not isSuccess(observed) then
		requestRecovery(data, true)
		return
	end
	local outcome = (observed :: any).value
	if not refreshSnapshot(data) then
		failAfterStart(data)
		return
	end
	if outcome.recoveryRequested == true or outcome.recoveryRequired == true then
		requestRecovery(data, false)
	end
end

local function shouldRecover(code: RequestProtocol.PublicErrorCode): boolean
	return code == "STALE_REQUEST"
		or code == "DUPLICATE_REQUEST"
		or code == "NOT_AUTHORIZED"
		or code == "UNAVAILABLE"
		or code == "INTERNAL_ERROR"
end

local function onSnapshotResponse(data: ControllerData, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.state ~= "Started" or data.studioRecoverySuspended then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local handled = dependencies.tracker:handleResponse(dependencies.getSnapshot.definition, value, ...)
	if not isSuccess(handled) then
		if type(handled) == "table" and (handled :: any).error.code == "MALFORMED_RESPONSE" then
			cancelPending(data)
			requestRecovery(data, true)
		end
		return
	end
	data.pending = nil
	local response = (handled :: any).value
	if RequestProtocol.isSuccess(response) then
		local now = sampleServerTime(data)
		if now == nil then
			requestRecovery(data, true)
		else
			local observed = dependencies.state:observeReceipt((response :: RequestProtocol.Success).payload, now)
			if not isSuccess(observed) then
				requestRecovery(data, true)
			else
				if not refreshSnapshot(data) then
					failAfterStart(data)
					return
				end
				if
					(observed :: any).value.recoveryRequested == true
					or (observed :: any).value.recoveryRequired == true
				then
					requestRecovery(data, false)
				end
			end
		end
	elseif shouldRecover((response :: RequestProtocol.Rejected).error.code) then
		requestRecovery(data, true)
	end
	reconcileRecovery(data)
end

local function renderNow(data: ControllerData): boolean
	if not data.callbacksEnabled or data.state ~= "Started" then
		return false
	end
	if data.studioRecoverySuspended then
		return true
	end
	local now = sampleServerTime(data)
	if now == nil then
		return true
	end
	local dependencies = data.dependencies :: Dependencies
	local beforeAdvance = data.cachedSnapshot
	if type(beforeAdvance) == "table" and beforeAdvance.receiptPending == true then
		local advanced = dependencies.state:advance(now)
		if not isSuccess(advanced) then
			requestRecovery(data, true)
			return true
		end
		local outcome = (advanced :: any).value
		if outcome.kind ~= "Noop" and not refreshSnapshot(data) then
			return false
		end
		if outcome.recoveryRequested == true or outcome.recoveryRequired == true then
			requestRecovery(data, false)
		end
	end
	local snapshot = data.cachedSnapshot
	if type(snapshot) ~= "table" then
		return false
	end
	if snapshot.recoveryRequired == true then
		requestRecovery(data, false)
	end
	local rendered = dependencies.renderer:render(snapshot, now)
	return isSuccess(rendered)
end

local function recordRenderDuration(data: ControllerData, durationSeconds: number)
	if not Validation.isFiniteNumber(durationSeconds) or durationSeconds < 0 then
		return
	end
	data.renderPassCount += 1
	data.renderDurationMaximum = math.max(data.renderDurationMaximum, durationSeconds)
	data.renderDurationSamples[data.renderDurationWriteIndex] = durationSeconds
	data.renderDurationWriteIndex = if data.renderDurationWriteIndex >= MAX_RENDER_DURATION_SAMPLES
		then 1
		else data.renderDurationWriteIndex + 1
end

local function profiledRender(data: ControllerData): boolean
	local profileBegin = (debug :: any).profilebegin
	local profileEnd = (debug :: any).profileend
	local profileStarted = false
	if type(profileBegin) == "function" and type(profileEnd) == "function" then
		profileStarted = pcall(profileBegin, "ATDEnemyRender")
	end
	local startedAt = os.clock()
	local rendered, succeeded = pcall(renderNow, data)
	recordRenderDuration(data, math.max(0, os.clock() - startedAt))
	if profileStarted then
		pcall(profileEnd)
	end
	return rendered and succeeded == true
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
		EnemyProtocol.GET_ENEMY_SNAPSHOT_ENDPOINT,
		EnemyProtocol.GetEnemySnapshotPayloadSchema,
		EnemyProtocol.EnemySnapshotReceiptSchema
	)
	if not isSuccess(registration) then
		data.state = "Failed"
		cleanup(data)
		staticError("INITIALIZE_FAILED")
	end
	if not refreshSnapshot(data) then
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

	-- Both inbound paths exist before the first empty recovery request. This
	-- closes the event-before-response race without adding another task or timer.
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
	connectOrFail(data, function()
		return dependencies.connectPreRender(function()
			if data.callbacksEnabled and not profiledRender(data) then
				failAfterStart(data)
			end
		end)
	end)
	data.renderConnectionCount = 1

	if not issueSnapshotRequest(data) then
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
		controller = controller,
		logger = logger,
		state = "Constructed",
		dependencyFactory = dependencyFactory,
		dependencies = nil,
		connections = {},
		callbacksEnabled = false,
		pending = nil,
		attemptCount = 0,
		forcedRecoveryQueued = false,
		lastServerTime = nil,
		cachedSnapshot = nil,
		snapshotRefreshCount = 0,
		renderConnectionCount = 0,
		renderPassCount = 0,
		renderDurationSamples = {},
		renderDurationWriteIndex = 1,
		renderDurationMaximum = 0,
		studioDiagnosticsBridge = nil,
		studioRecoverySuspended = false,
		cleanupFailed = false,
	}
	return Result.ok(controller)
end

function ControllerMethods.getState(self: Controller): LifecycleState
	return requireData(self).state
end

local function percentileMilliseconds(samples: { number }, fraction: number): number
	if #samples == 0 then
		return 0
	end
	local ordered = table.clone(samples)
	table.sort(ordered)
	local index = math.clamp(math.ceil(#ordered * fraction), 1, #ordered)
	return ordered[index] * 1_000
end

function ControllerMethods.getMetrics(self: Controller): Metrics
	local data = requireData(self)
	local snapshot = data.cachedSnapshot
	local snapshotTable = if type(snapshot) == "table" then snapshot else nil
	return table.freeze({
		lifecycleState = data.state,
		renderConnectionCount = data.renderConnectionCount,
		renderPassCount = data.renderPassCount,
		renderDurationSampleCount = #data.renderDurationSamples,
		renderDurationP50Milliseconds = percentileMilliseconds(data.renderDurationSamples, 0.5),
		renderDurationP95Milliseconds = percentileMilliseconds(data.renderDurationSamples, 0.95),
		renderDurationMaximumMilliseconds = data.renderDurationMaximum * 1_000,
		snapshotRefreshCount = data.snapshotRefreshCount,
		snapshotAttemptCount = data.attemptCount,
		snapshotRequestPending = data.pending ~= nil,
		studioRecoverySuspended = data.studioRecoverySuspended,
		cachedLocked = snapshotTable ~= nil and snapshotTable.locked == true,
		cachedMatchId = if snapshotTable == nil then nil else snapshotTable.matchId,
		cachedEnemyEpoch = if snapshotTable == nil then nil else snapshotTable.enemyEpoch,
		cachedLastSequence = if snapshotTable == nil then nil else snapshotTable.lastSequence,
		cachedEntryCount = if snapshotTable == nil or type(snapshotTable.entries) ~= "table"
			then 0
			else #snapshotTable.entries,
		cachedRecoveryRequired = snapshotTable ~= nil and snapshotTable.recoveryRequired == true,
	})
end

function ControllerMethods.getStudioDiagnostics(self: Controller): StudioDiagnostics
	local data = requireData(self)
	local rendererMetrics: unknown? = nil
	local dependencies = data.dependencies
	if dependencies ~= nil and type((dependencies.renderer :: any).getMetrics) == "function" then
		local read, resultValue = pcall((dependencies.renderer :: any).getMetrics, dependencies.renderer)
		if read and isSuccess(resultValue) then
			rendererMetrics = (resultValue :: any).value
		end
	end
	return table.freeze({
		controller = self:getMetrics(),
		replication = data.cachedSnapshot,
		renderer = rendererMetrics,
	})
end

local function resetStudioTiming(data: ControllerData)
	data.renderPassCount = 0
	table.clear(data.renderDurationSamples)
	data.renderDurationWriteIndex = 1
	data.renderDurationMaximum = 0
end

local function suspendStudioRecovery(data: ControllerData): boolean
	if data.studioRecoverySuspended then
		return true
	end
	-- Suspension is idempotent and fail-closed: gate callbacks before canceling
	-- the one pending request or clearing presentation, and never reopen the
	-- gate when presentation reset reports a failure.
	data.studioRecoverySuspended = true
	data.forcedRecoveryQueued = false
	cancelPending(data)
	local dependencies = data.dependencies
	if dependencies == nil then
		return false
	end
	local reset, resetResult = pcall(function()
		return dependencies.renderer:reset()
	end)
	return reset and isSuccess(resetResult)
end

local function resumeStudioRecovery(data: ControllerData): boolean
	if not data.studioRecoverySuspended then
		-- An already-active controller is an idempotent success and must not
		-- consume another attempt or create another request.
		return true
	end
	if data.attemptCount >= EnemyProtocol.MAX_CLIENT_SNAPSHOT_ATTEMPTS then
		return false
	end
	-- Reopen callbacks only for the existing bounded request path. A sender or
	-- construction failure restores suspension, so diagnostics cannot claim
	-- recovery without an authenticated request in flight.
	data.studioRecoverySuspended = false
	if issueSnapshotRequest(data) then
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
			or operation == "ResetTiming"
			or operation == "SuspendRecovery"
			or operation == "ResumeRecovery"
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
	if operation == "ResetTiming" then
		resetStudioTiming(data)
	elseif operation == "SuspendRecovery" then
		if not suspendStudioRecovery(data) then
			return STUDIO_DIAGNOSTICS_ERRORS.INTERNAL_ERROR
		end
	elseif operation == "ResumeRecovery" then
		if not resumeStudioRecovery(data) then
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
	local Workspace = game:GetService("Workspace")
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

	local requestLookup = ClientRemoteLookup.resolve(EnemyProtocol.GET_ENEMY_SNAPSHOT_ENDPOINT, LOOKUP_TIMEOUT_SECONDS)
	local eventLookup = ClientRemoteLookup.resolve(EnemyProtocol.ENEMY_REPLICATION_ENDPOINT, LOOKUP_TIMEOUT_SECONDS)
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
	local request = requestEndpoint.request :: RemoteEvent
	local response = requestEndpoint.response :: RemoteEvent
	local event = eventEndpoint.event :: RemoteEvent
	local rendererResult = EnemyRenderer.new()
	if not rendererResult.ok then
		staticError("RENDERER_CREATION_FAILED")
	end

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
		state = EnemyReplicationState.new(),
		renderer = rendererResult.value,
		connectPreRender = function(callback)
			return RunService.PreRender:Connect(callback)
		end,
		getServerTimeNow = function(): unknown
			return Workspace:GetServerTimeNow()
		end,
	}
end

function EnemyController.new(logger: Log.Logger): ControllerResult
	local resultValue = construct(logger, makeProductionDependencies)
	if resultValue.ok and EnemyController.getStudioDiagnostics ~= nil and activeStudioController == nil then
		activeStudioController = resultValue.value
	end
	return resultValue
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

if isProductionStudioClient() then
	EnemyController.getStudioDiagnostics = function(): StudioDiagnostics?
		local controller = activeStudioController
		if controller == nil then
			return nil
		end
		return controller:getStudioDiagnostics()
	end
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "EnemyController" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionClientEnemies" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

if isExactTestModule() then
	EnemyController.invokeStudioDiagnosticsForTests = function(controller: Controller, ...: unknown): unknown
		local data = requireData(controller)
		return invokeStudioDiagnostics(data, select("#", ...), ...)
	end
	EnemyController.newForTests = function(logger: Log.Logger, dependencies: Dependencies): ControllerResult
		if not validateDependencies(dependencies) then
			return failure("INVALID_DEPENDENCIES")
		end
		local copy: Dependencies = {
			tracker = dependencies.tracker,
			getSnapshot = dependencies.getSnapshot,
			replicationEvent = dependencies.replicationEvent,
			state = dependencies.state,
			renderer = dependencies.renderer,
			connectPreRender = dependencies.connectPreRender,
			getServerTimeNow = dependencies.getServerTimeNow,
		}
		return construct(logger, function(): Dependencies
			return copy
		end)
	end
end

table.freeze(ControllerMethods)
return table.freeze(EnemyController)
