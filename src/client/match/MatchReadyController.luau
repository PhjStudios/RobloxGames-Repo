--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Log = require(ReplicatedStorage.Shared.logging.Log)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)

local MatchReadyView = require(script.Parent.MatchReadyView)
local MatchReadyViewModel = require(script.Parent.MatchReadyViewModel)

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

export type ResponseListener = (value: unknown, ...unknown) -> ()
export type EventListener = (value: unknown, ...unknown) -> ()
export type ActionHandler = (actionName: string, inputState: unknown, inputObject: unknown) -> unknown

export type RequestEndpoint = {
	definition: RemoteRegistry.Definition,
	connectResponse: (ResponseListener) -> RBXScriptConnection,
	fire: (RequestProtocol.RawRequest) -> (),
}

export type EventEndpoint = {
	connectEvent: (EventListener) -> RBXScriptConnection,
}

export type TrackerAdapter = {
	register: (self: TrackerAdapter, endpointName: unknown, requestSchema: unknown, responseSchema: unknown) -> any,
	buildRequest: (self: TrackerAdapter, endpointName: unknown, payload: unknown) -> any,
	handleResponse: (self: TrackerAdapter, definition: unknown, responseValue: unknown, ...unknown) -> any,
	cancel: (self: TrackerAdapter, pending: unknown) -> any,
	clear: (self: TrackerAdapter) -> (),
}

export type Dependencies = {
	localUserId: number,
	tracker: TrackerAdapter,
	getSnapshot: RequestEndpoint,
	submitReady: RequestEndpoint,
	snapshotEvent: EventEndpoint,
	view: MatchReadyView.View,
	bindAction: (
		actionName: string,
		handler: ActionHandler,
		createTouchButton: boolean,
		keyboard: unknown,
		gamepad: unknown
	) -> (),
	unbindAction: (actionName: string) -> (),
	connectRenderStep: (() -> ()) -> RBXScriptConnection,
	getServerTimeNow: () -> unknown,
	actionBegin: unknown,
	actionPass: unknown,
	actionSink: unknown,
	keyboardKey: unknown,
	gamepadKey: unknown,
}

type ControllerData = {
	logger: Log.Logger,
	state: LifecycleState,
	dependencyFactory: () -> Dependencies,
	dependencies: Dependencies?,
	model: MatchReadyViewModel.Model?,
	connections: { RBXScriptConnection },
	callbacksEnabled: boolean,
	actionBound: boolean,
	getPending: RequestProtocol.Pending?,
	readyPending: RequestProtocol.Pending?,
	initialGetSent: boolean,
	recoveryGetUsed: boolean,
	recoveryQueued: boolean,
	cleanupFailed: boolean,
}

local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

export type Controller = typeof(setmetatable({} :: {}, ControllerMethods))
export type ControllerResult = Result.Result<Controller, Error>
export type TestConstructor = (logger: Log.Logger, dependencies: Dependencies) -> ControllerResult

local SERVICE_NAME = "MatchReadyController"
local ACTION_NAME = "ATDMatchReady"
local LOOKUP_TIMEOUT_SECONDS = 5
local STATIC_PREFIX = "[ATD_MATCH_READY_CONTROLLER]"

local CONTROLLER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ControllerData }

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_CONTEXT = table.freeze({ code = "INVALID_CONTEXT" :: "INVALID_CONTEXT" }),
	INVALID_DEPENDENCIES = table.freeze({ code = "INVALID_DEPENDENCIES" :: "INVALID_DEPENDENCIES" }),
	INITIALIZE_FAILED = table.freeze({ code = "INITIALIZE_FAILED" :: "INITIALIZE_FAILED" }),
	START_FAILED = table.freeze({ code = "START_FAILED" :: "START_FAILED" }),
	CLEANUP_FAILED = table.freeze({ code = "CLEANUP_FAILED" :: "CLEANUP_FAILED" }),
})

local MatchReadyController = {
	SERVICE_NAME = SERVICE_NAME,
	ACTION_NAME = ACTION_NAME,
	newForTests = nil :: TestConstructor?,
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

local function validateDependencies(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local dependencies = value :: any
	local allowed = {
		localUserId = true,
		tracker = true,
		getSnapshot = true,
		submitReady = true,
		snapshotEvent = true,
		view = true,
		bindAction = true,
		unbindAction = true,
		connectRenderStep = true,
		getServerTimeNow = true,
		actionBegin = true,
		actionPass = true,
		actionSink = true,
		keyboardKey = true,
		gamepadKey = true,
	}
	local count = 0
	for key in next, dependencies do
		if type(key) ~= "string" or allowed[key] ~= true then
			return false
		end
		count += 1
	end
	local tracker = dependencies.tracker
	local snapshotEvent = dependencies.snapshotEvent
	return count == 15
		and type(dependencies.localUserId) == "number"
		and type(tracker) == "table"
		and type(tracker.register) == "function"
		and type(tracker.buildRequest) == "function"
		and type(tracker.handleResponse) == "function"
		and type(tracker.cancel) == "function"
		and type(tracker.clear) == "function"
		and validateRequestEndpoint(dependencies.getSnapshot, MatchProtocol.GET_MATCH_SNAPSHOT_ENDPOINT)
		and validateRequestEndpoint(dependencies.submitReady, MatchProtocol.SUBMIT_READY_ENDPOINT)
		and type(snapshotEvent) == "table"
		and type(snapshotEvent.connectEvent) == "function"
		and type(dependencies.view) == "table"
		and type(dependencies.view.connectActivated) == "function"
		and type(dependencies.view.render) == "function"
		and type(dependencies.view.destroy) == "function"
		and type(dependencies.bindAction) == "function"
		and type(dependencies.unbindAction) == "function"
		and type(dependencies.connectRenderStep) == "function"
		and type(dependencies.getServerTimeNow) == "function"
		and dependencies.actionBegin ~= nil
		and dependencies.actionPass ~= nil
		and dependencies.actionSink ~= nil
		and dependencies.keyboardKey ~= nil
		and dependencies.gamepadKey ~= nil
end

local function addConnection(data: ControllerData, connection: unknown): boolean
	if typeof(connection) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, connection :: RBXScriptConnection)
	return true
end

local function cancelPending(data: ControllerData, kind: "Get" | "Ready")
	local dependencies = data.dependencies
	if dependencies == nil then
		return
	end
	local pending = if kind == "Get" then data.getPending else data.readyPending
	if pending == nil then
		return
	end
	pcall(function()
		dependencies.tracker:cancel(pending)
	end)
	if kind == "Get" then
		data.getPending = nil
	else
		data.readyPending = nil
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

	if dependencies ~= nil and data.actionBound then
		data.actionBound = false
		if not pcall(dependencies.unbindAction, ACTION_NAME) then
			failed = true
		end
	end

	for index = #data.connections, 1, -1 do
		if not pcall(function()
			data.connections[index]:Disconnect()
		end) then
			failed = true
		end
	end
	table.clear(data.connections)

	cancelPending(data, "Ready")
	cancelPending(data, "Get")
	if dependencies ~= nil and not pcall(function()
		dependencies.tracker:clear()
	end) then
		failed = true
	end
	if data.model ~= nil then
		local cleaned, result = pcall(function()
			return (data.model :: MatchReadyViewModel.Model):cleanup()
		end)
		if not cleaned or not isSuccess(result) then
			failed = true
		end
	end
	if dependencies ~= nil then
		local destroyed, result = pcall(function()
			return dependencies.view:destroy()
		end)
		if not destroyed or not isSuccess(result) then
			failed = true
		end
	end

	data.getPending = nil
	data.readyPending = nil
	data.recoveryQueued = false
	data.model = nil
	data.dependencies = nil
	data.cleanupFailed = failed
	data.state = "Shutdown"
	return not failed
end

local function failAfterStart(data: ControllerData)
	if data.state == "Started" then
		cleanup(data)
	end
end

local function renderNow(data: ControllerData): boolean
	if not data.callbacksEnabled or data.state ~= "Started" then
		return false
	end
	local dependencies = data.dependencies :: Dependencies
	local model = data.model :: MatchReadyViewModel.Model
	local sampled, serverTime = pcall(dependencies.getServerTimeNow)
	local renderResult = model:getRenderState(if sampled then serverTime else nil)
	if not renderResult.ok then
		return false
	end
	local state = renderResult.value
	if state.matchState == nil then
		return true
	end
	local countdownText = "--"
	if
		state.countdownKnown
		and state.countdownSeconds ~= nil
		and state.countdownSeconds >= 0
		and state.countdownSeconds <= MatchProtocol.READY_CHECK_SECONDS
	then
		countdownText = `{state.countdownSeconds}s`
	end

	local rows = table.create(#state.participantRows) :: { MatchReadyView.RenderRow }
	for index, row in state.participantRows do
		rows[index] = {
			label = row.label,
			status = row.status,
			isLocal = row.isLocal,
		}
	end
	local viewResult = dependencies.view:render({
		matchState = state.matchState,
		countdownText = countdownText,
		requestText = state.requestState,
		readyVisible = state.matchState == "ReadyCheck",
		readyEnabled = state.readyAvailable,
		rows = rows,
	})
	return viewResult.ok
end

local function reconcileReadyPending(data: ControllerData)
	if data.readyPending == nil or data.model == nil then
		return
	end
	local stateResult = data.model:getRenderState(nil)
	if not stateResult.ok then
		return
	end
	local state = stateResult.value
	if state.matchState ~= "ReadyCheck" or state.requestState == "StateChanged" then
		cancelPending(data, "Ready")
	end
end

local function applyValidatedSnapshot(
	data: ControllerData,
	snapshot: MatchProtocol.MatchSnapshot
): MatchReadyViewModel.ApplyKind?
	local model = data.model :: MatchReadyViewModel.Model
	local outcome = model:applySnapshot(snapshot)
	if not outcome.ok then
		return nil
	end
	local kind = outcome.value.kind
	if kind ~= "WrongMatch" then
		data.recoveryQueued = false
	end
	if kind == "Applied" then
		reconcileReadyPending(data)
		if not renderNow(data) then
			failAfterStart(data)
		end
	end
	return kind
end

local issueGet: (ControllerData, boolean) -> boolean
local requestRecovery: (ControllerData) -> ()

issueGet = function(data: ControllerData, isRecovery: boolean): boolean
	if not data.callbacksEnabled or data.state ~= "Started" or data.getPending ~= nil then
		return false
	end
	local dependencies = data.dependencies :: Dependencies
	local built = dependencies.tracker:buildRequest(MatchProtocol.GET_MATCH_SNAPSHOT_ENDPOINT, {})
	if not isSuccess(built) then
		return false
	end
	local request = (built :: any).value
	if not RequestProtocol.isPending(request.pending) then
		return false
	end
	data.getPending = request.pending
	local fired = pcall(dependencies.getSnapshot.fire, request.envelope)
	if not fired then
		cancelPending(data, "Get")
		if not isRecovery then
			requestRecovery(data)
		end
		return false
	end
	return true
end

requestRecovery = function(data: ControllerData)
	if not data.callbacksEnabled or data.state ~= "Started" or data.recoveryGetUsed then
		return
	end
	if data.getPending ~= nil then
		data.recoveryQueued = true
		return
	end
	data.recoveryQueued = false
	data.recoveryGetUsed = true
	issueGet(data, true)
end

local function shouldRecover(code: RequestProtocol.PublicErrorCode): boolean
	return code == "STALE_REQUEST" or code == "DUPLICATE_REQUEST" or code == "NOT_AUTHORIZED" or code == "UNAVAILABLE"
end

local function rejectPendingReady(data: ControllerData, code: RequestProtocol.PublicErrorCode)
	if data.model ~= nil then
		data.model:rejectReady(code)
	end
	if not renderNow(data) then
		failAfterStart(data)
	end
end

local function handleMalformedGet(data: ControllerData)
	cancelPending(data, "Get")
	requestRecovery(data)
end

local function handleMalformedReady(data: ControllerData)
	cancelPending(data, "Ready")
	rejectPendingReady(data, "INTERNAL_ERROR")
	requestRecovery(data)
end

local function onSnapshotEvent(data: ControllerData, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.state ~= "Started" then
		return
	end
	local parsed = RequestProtocol.parseEvent(value, ...)
	if not parsed.ok then
		requestRecovery(data)
		return
	end
	local validated = MatchProtocol.validateMatchSnapshot(parsed.value.payload)
	if not validated.ok then
		requestRecovery(data)
		return
	end
	local kind = applyValidatedSnapshot(data, validated.value)
	if kind == "WrongMatch" then
		requestRecovery(data)
	end
end

local function onGetResponse(data: ControllerData, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.state ~= "Started" then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local handled = dependencies.tracker:handleResponse(dependencies.getSnapshot.definition, value, ...)
	if not handled.ok then
		if handled.error.code == "MALFORMED_RESPONSE" then
			handleMalformedGet(data)
		end
		return
	end
	data.getPending = nil
	local response = handled.value
	if RequestProtocol.isSuccess(response) then
		local validated = MatchProtocol.validateMatchSnapshot((response :: RequestProtocol.Success).payload)
		if not validated.ok or applyValidatedSnapshot(data, validated.value) == "WrongMatch" then
			requestRecovery(data)
		end
	else
		local code = (response :: RequestProtocol.Rejected).error.code
		if shouldRecover(code) then
			requestRecovery(data)
		end
	end
	if data.recoveryQueued then
		requestRecovery(data)
	end
end

local function onReadyResponse(data: ControllerData, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.state ~= "Started" then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local handled = dependencies.tracker:handleResponse(dependencies.submitReady.definition, value, ...)
	if not handled.ok then
		if handled.error.code == "MALFORMED_RESPONSE" then
			handleMalformedReady(data)
		end
		return
	end
	data.readyPending = nil
	local response = handled.value
	if RequestProtocol.isSuccess(response) then
		local validated = MatchProtocol.validateMatchSnapshot((response :: RequestProtocol.Success).payload)
		if not validated.ok then
			rejectPendingReady(data, "INTERNAL_ERROR")
			requestRecovery(data)
			return
		end
		local kind = applyValidatedSnapshot(data, validated.value)
		if kind == "WrongMatch" or kind == nil then
			rejectPendingReady(data, "INTERNAL_ERROR")
			requestRecovery(data)
			return
		end
		(data.model :: MatchReadyViewModel.Model):acceptReady()
		if not renderNow(data) then
			failAfterStart(data)
		end
	else
		local code = (response :: RequestProtocol.Rejected).error.code
		rejectPendingReady(data, code)
		if shouldRecover(code) then
			requestRecovery(data)
		end
	end
end

local function activateReady(data: ControllerData): boolean
	if not data.callbacksEnabled or data.state ~= "Started" or data.readyPending ~= nil then
		return false
	end
	local model = data.model :: MatchReadyViewModel.Model
	local submission = model:beginReady()
	if not submission.ok then
		return false
	end
	if not renderNow(data) then
		failAfterStart(data)
		return true
	end
	local dependencies = data.dependencies :: Dependencies
	local built = dependencies.tracker:buildRequest(MatchProtocol.SUBMIT_READY_ENDPOINT, submission.value)
	if not isSuccess(built) then
		rejectPendingReady(data, "INTERNAL_ERROR")
		requestRecovery(data)
		return true
	end
	local request = (built :: any).value
	if not RequestProtocol.isPending(request.pending) then
		rejectPendingReady(data, "INTERNAL_ERROR")
		requestRecovery(data)
		return true
	end
	data.readyPending = request.pending
	if not pcall(dependencies.submitReady.fire, request.envelope) then
		cancelPending(data, "Ready")
		rejectPendingReady(data, "UNAVAILABLE")
		requestRecovery(data)
	end
	return true
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

	local modelResult = MatchReadyViewModel.new((dependencies :: Dependencies).localUserId)
	if not modelResult.ok then
		data.state = "Failed"
		cleanup(data)
		staticError("INITIALIZE_FAILED")
	end
	data.model = modelResult.value

	local tracker = (dependencies :: Dependencies).tracker
	local getRegistration = tracker:register(
		MatchProtocol.GET_MATCH_SNAPSHOT_ENDPOINT,
		MatchProtocol.GetMatchSnapshotPayloadSchema,
		MatchProtocol.MatchSnapshotSchema
	)
	local readyRegistration = tracker:register(
		MatchProtocol.SUBMIT_READY_ENDPOINT,
		MatchProtocol.SubmitReadyPayloadSchema,
		MatchProtocol.MatchSnapshotSchema
	)
	if not isSuccess(getRegistration) or not isSuccess(readyRegistration) then
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

	-- The event listener and both response listeners must exist before the first
	-- recovery request can be sent. Later UI and render bindings cannot move this
	-- fixed network order.
	connectOrFail(data, function()
		return dependencies.snapshotEvent.connectEvent(function(value, ...)
			onSnapshotEvent(data, value, ...)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.getSnapshot.connectResponse(function(value, ...)
			onGetResponse(data, value, ...)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.submitReady.connectResponse(function(value, ...)
			onReadyResponse(data, value, ...)
		end)
	end)

	local activationResult = dependencies.view:connectActivated(function()
		activateReady(data)
	end)
	if not activationResult.ok or not addConnection(data, activationResult.value) then
		cleanup(data)
		staticError("START_FAILED")
	end

	local bound = pcall(dependencies.bindAction, ACTION_NAME, function(_actionName, inputState, _inputObject)
		if inputState == dependencies.actionBegin and activateReady(data) then
			return dependencies.actionSink
		end
		return dependencies.actionPass
	end, false, dependencies.keyboardKey, dependencies.gamepadKey)
	if not bound then
		cleanup(data)
		staticError("START_FAILED")
	end
	data.actionBound = true

	connectOrFail(data, function()
		return dependencies.connectRenderStep(function()
			if data.callbacksEnabled and not renderNow(data) then
				failAfterStart(data)
			end
		end)
	end)

	data.initialGetSent = true
	if not issueGet(data, false) then
		requestRecovery(data)
	end
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
		logger = logger,
		state = "Constructed",
		dependencyFactory = dependencyFactory,
		dependencies = nil,
		model = nil,
		connections = {},
		callbacksEnabled = false,
		actionBound = false,
		getPending = nil,
		readyPending = nil,
		initialGetSent = false,
		recoveryGetUsed = false,
		recoveryQueued = false,
		cleanupFailed = false,
	}
	return Result.ok(controller)
end

function ControllerMethods.getState(self: Controller): LifecycleState
	return requireData(self).state
end

function ControllerMethods.getServiceDefinition(self: Controller)
	local data = requireData(self)
	return table.freeze({
		name = SERVICE_NAME,
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
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local ContextActionService = game:GetService("ContextActionService")
	local Workspace = game:GetService("Workspace")
	local clientRoot = script.Parent.Parent
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
	local function resolveRequest(endpointName: string): RequestEndpoint
		local lookup = ClientRemoteLookup.resolve(endpointName, LOOKUP_TIMEOUT_SECONDS)
		if not isSuccess(lookup) then
			staticError("REMOTE_LOOKUP_FAILED")
		end
		local endpoint = lookup.value
		if endpoint.request == nil or endpoint.response == nil or endpoint.event ~= nil then
			staticError("REMOTE_SHAPE_INVALID")
		end
		local request = endpoint.request :: RemoteEvent
		local response = endpoint.response :: RemoteEvent
		return {
			definition = endpoint.definition,
			connectResponse = function(listener: ResponseListener): RBXScriptConnection
				return response.OnClientEvent:Connect(listener)
			end,
			fire = function(envelope: RequestProtocol.RawRequest)
				request:FireServer(envelope)
			end,
		}
	end
	local function resolveEvent(endpointName: string): EventEndpoint
		local lookup = ClientRemoteLookup.resolve(endpointName, LOOKUP_TIMEOUT_SECONDS)
		if not isSuccess(lookup) then
			staticError("REMOTE_LOOKUP_FAILED")
		end
		local endpoint = lookup.value
		if endpoint.request ~= nil or endpoint.response ~= nil or endpoint.event == nil then
			staticError("REMOTE_SHAPE_INVALID")
		end
		local event = endpoint.event :: RemoteEvent
		return {
			connectEvent = function(listener: EventListener): RBXScriptConnection
				return event.OnClientEvent:Connect(listener)
			end,
		}
	end

	local getSnapshot = resolveRequest(MatchProtocol.GET_MATCH_SNAPSHOT_ENDPOINT)
	local submitReady = resolveRequest(MatchProtocol.SUBMIT_READY_ENDPOINT)
	local snapshotEvent = resolveEvent(MatchProtocol.MATCH_SNAPSHOT_ENDPOINT)
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		staticError("LOCAL_PLAYER_MISSING")
	end
	local localUserId = localPlayer.UserId
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		local candidate = localPlayer:WaitForChild("PlayerGui", LOOKUP_TIMEOUT_SECONDS)
		if candidate == nil or not candidate:IsA("PlayerGui") or candidate.Parent ~= localPlayer then
			staticError("PLAYER_GUI_MISSING")
		end
		playerGui = candidate :: PlayerGui
	end
	local viewResult = MatchReadyView.new(playerGui)
	if not viewResult.ok then
		staticError("VIEW_CREATION_FAILED")
	end

	return {
		localUserId = localUserId,
		tracker = trackerResult.value,
		getSnapshot = getSnapshot,
		submitReady = submitReady,
		snapshotEvent = snapshotEvent,
		view = viewResult.value,
		bindAction = function(actionName, handler, createTouchButton, keyboard, gamepad)
			ContextActionService:BindAction(
				actionName,
				handler :: any,
				createTouchButton,
				keyboard :: Enum.KeyCode,
				gamepad :: Enum.KeyCode
			)
		end,
		unbindAction = function(actionName)
			ContextActionService:UnbindAction(actionName)
		end,
		connectRenderStep = function(callback)
			return RunService.RenderStepped:Connect(callback)
		end,
		getServerTimeNow = function(): unknown
			return Workspace:GetServerTimeNow()
		end,
		actionBegin = Enum.UserInputState.Begin,
		actionPass = Enum.ContextActionResult.Pass,
		actionSink = Enum.ContextActionResult.Sink,
		keyboardKey = Enum.KeyCode.R,
		gamepadKey = Enum.KeyCode.ButtonA,
	}
end

function MatchReadyController.new(logger: Log.Logger): ControllerResult
	return construct(logger, makeProductionDependencies)
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "MatchReadyController" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionClientMatch" then
		return false
	end
	local automatedTests = container.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	if automatedTests.Parent ~= ServerStorage then
		return false
	end
	local support = automatedTests:FindFirstChild("Support")
	return support ~= nil and support:IsA("Folder") and support:FindFirstChild("TestRunner") ~= nil
end

if isExactTestModule() then
	MatchReadyController.newForTests = function(logger: Log.Logger, dependencies: Dependencies): ControllerResult
		if not validateDependencies(dependencies) then
			return failure("INVALID_DEPENDENCIES")
		end
		local copy: Dependencies = {
			localUserId = dependencies.localUserId,
			tracker = dependencies.tracker,
			getSnapshot = dependencies.getSnapshot,
			submitReady = dependencies.submitReady,
			snapshotEvent = dependencies.snapshotEvent,
			view = dependencies.view,
			bindAction = dependencies.bindAction,
			unbindAction = dependencies.unbindAction,
			connectRenderStep = dependencies.connectRenderStep,
			getServerTimeNow = dependencies.getServerTimeNow,
			actionBegin = dependencies.actionBegin,
			actionPass = dependencies.actionPass,
			actionSink = dependencies.actionSink,
			keyboardKey = dependencies.keyboardKey,
			gamepadKey = dependencies.gamepadKey,
		}
		return construct(logger, function(): Dependencies
			return copy
		end)
	end
end

table.freeze(ControllerMethods)
return table.freeze(MatchReadyController)
