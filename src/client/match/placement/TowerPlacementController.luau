--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Log = require(ReplicatedStorage.Shared.logging.Log)
local PlacementProtocol = require(ReplicatedStorage.Shared.match.PlacementProtocol)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local PlacementInputAdapter = require(script.Parent.PlacementInputAdapter)
local PlacementPreviewReducer = require(script.Parent.PlacementPreviewReducer)
local PlacementPreviewView = require(script.Parent.PlacementPreviewView)

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
	| "UNAVAILABLE"
	| "REQUEST_PENDING"
	| "INVALID_ARGUMENT"
	| "INTERNAL_ERROR"

export type Error = {
	code: ErrorCode,
}

export type ResponseListener = (unknown, ...unknown) -> ()
export type EventListener = (unknown, ...unknown) -> ()

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
	register: (self: TrackerAdapter, unknown, unknown, unknown) -> any,
	buildRequest: (self: TrackerAdapter, unknown, unknown) -> any,
	handleResponse: (self: TrackerAdapter, unknown, unknown, ...unknown) -> any,
	cancel: (self: TrackerAdapter, unknown) -> any,
	clear: (self: TrackerAdapter) -> (),
}

export type ReducerAdapter = {
	observeQuery: (self: ReducerAdapter, unknown) -> any,
	observeRevision: (self: ReducerAdapter, unknown) -> any,
	selectSlot: (self: ReducerAdapter, unknown) -> any,
	setPosition: (self: ReducerAdapter, unknown) -> any,
	clearPosition: (self: ReducerAdapter) -> any,
	rotate: (self: ReducerAdapter, unknown) -> any,
	setPreferredInput: (self: ReducerAdapter, unknown) -> any,
	beginSubmit: (self: ReducerAdapter) -> any,
	observeReceipt: (self: ReducerAdapter, unknown) -> any,
	abortSubmit: (self: ReducerAdapter) -> any,
	cancel: (self: ReducerAdapter) -> any,
	getState: (self: ReducerAdapter) -> any,
	cleanup: (self: ReducerAdapter) -> any,
}

export type InputAdapter = {
	setPreferredInput: (self: InputAdapter, unknown) -> any,
	setViewport: (self: InputAdapter, unknown) -> any,
	desktopPointer: (self: InputAdapter, unknown) -> any,
	touchBegan: (self: InputAdapter, unknown, unknown, unknown) -> any,
	touchChanged: (self: InputAdapter, unknown, unknown) -> any,
	touchEnded: (self: InputAdapter, unknown, unknown) -> any,
	touchCancelled: (self: InputAdapter, unknown) -> any,
	confirm: (self: InputAdapter, unknown) -> any,
	cancel: (self: InputAdapter, unknown) -> any,
	rotate: (self: InputAdapter, unknown, unknown) -> any,
	selectSlot: (self: InputAdapter, unknown, unknown) -> any,
	cycleSlot: (self: InputAdapter, unknown) -> any,
	gamepadStep: (self: InputAdapter, unknown, unknown) -> any,
	getReticle: (self: InputAdapter) -> any,
	getMetrics: (self: InputAdapter) -> any,
	cleanup: (self: InputAdapter) -> any,
}

export type ViewAdapter = {
	render: (self: ViewAdapter, unknown) -> any,
	setReticle: (self: ViewAdapter, unknown, unknown) -> any,
	getMetrics: (self: ViewAdapter) -> any,
	cleanup: (self: ViewAdapter) -> any,
}

export type StudioEvidenceHandler = (...unknown) -> unknown
export type CreateStudioEvidenceTrigger = (StudioEvidenceHandler) -> unknown

export type InputFamily = PlacementInputAdapter.InputFamily

export type NormalizedInput = {
	kind: "SelectSlot"
		| "Confirm"
		| "Cancel"
		| "Rotate"
		| "CycleSlot"
		| "TouchBegin"
		| "TouchMove"
		| "TouchEnd"
		| "TouchCancel"
		| "GamepadAxis",
	source: InputFamily,
	processed: boolean?,
	slot: number?,
	direction: number?,
	touchId: number?,
	position: Vector2?,
	axis: Vector2?,
}

export type Dependencies = {
	tracker: TrackerAdapter,
	getQuery: RequestEndpoint,
	submitPlacement: RequestEndpoint,
	revisionEvent: EventEndpoint,
	reducer: ReducerAdapter,
	input: InputAdapter,
	view: ViewAdapter,
	connectInputBegan: ((NormalizedInput) -> ()) -> RBXScriptConnection,
	connectInputChanged: ((NormalizedInput) -> ()) -> RBXScriptConnection,
	connectInputEnded: ((NormalizedInput) -> ()) -> RBXScriptConnection,
	connectPreferredInputChanged: ((InputFamily) -> ()) -> RBXScriptConnection,
	connectRenderStep: ((number) -> ()) -> RBXScriptConnection,
	getPointerPosition: () -> Vector2,
	getViewportSize: () -> Vector2,
	getInitialInput: () -> InputFamily,
	raycast: (Vector2) -> Vector3?,
	isStudio: () -> boolean,
	createStudioEvidenceTrigger: CreateStudioEvidenceTrigger,
}

export type Metrics = {
	lifecycleState: LifecycleState,
	connectionCount: number,
	callbackGeneration: number,
	queryRequestCount: number,
	queryPending: boolean,
	refreshQueued: boolean,
	submitRequestCount: number,
	submitPending: boolean,
	acceptedPlacementCount: number,
	rejectedPlacementCount: number,
	revisionEventCount: number,
	renderCount: number,
	raycastCount: number,
	maximumRaycastsPerFrame: number,
	inputActionCount: number,
	rejectedInputCount: number,
	studioTriggerCount: number,
	studioOperationCount: number,
	preferredInput: InputFamily?,
	phase: string?,
	selectedSlot: number?,
	queryRevision: number?,
	refreshRequired: boolean,
	viewMetrics: unknown,
	inputMetrics: unknown,
}

type PendingRequest = {
	pending: RequestProtocol.Pending,
}

type DependencyFactory = (PlacementPreviewView.UiActionCallback) -> Dependencies

type ControllerData = {
	state: LifecycleState,
	dependencyFactory: DependencyFactory,
	dependencies: Dependencies?,
	connections: { RBXScriptConnection },
	callbacksEnabled: boolean,
	callbackGeneration: number,
	getPending: PendingRequest?,
	submitPending: PendingRequest?,
	refreshQueued: boolean,
	raycastRequested: Vector2?,
	gamepadAxis: Vector2,
	queryRequestCount: number,
	submitRequestCount: number,
	acceptedPlacementCount: number,
	rejectedPlacementCount: number,
	revisionEventCount: number,
	renderCount: number,
	raycastCount: number,
	maximumRaycastsPerFrame: number,
	inputActionCount: number,
	rejectedInputCount: number,
	studioEvidenceTrigger: unknown?,
	studioOperationCount: number,
}

local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

export type Controller = typeof(setmetatable({} :: {}, ControllerMethods))
export type ControllerResult = Result.Result<Controller, Error>
export type TestConstructor = (Log.Logger, Dependencies) -> ControllerResult

local SERVICE_NAME = "TowerPlacementController"
local WAVE_CONTROLLER_SERVICE_NAME = "WaveController"
local LOOKUP_TIMEOUT_SECONDS = 5
local CONNECTION_COUNT = 8
local RAY_LENGTH_STUDS = 4_096
local RUNTIME_MAP_NAME = "ATDRuntimeMap"
local STUDIO_EVIDENCE_TRIGGER_NAME = "_ATDPhase13PlacementClientEvidence"
local STATIC_PREFIX = "[ATD_TOWER_PLACEMENT_CONTROLLER]"

local CONTROLLER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ControllerData }

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_CONTEXT = table.freeze({ code = "INVALID_CONTEXT" :: "INVALID_CONTEXT" }),
	INVALID_DEPENDENCIES = table.freeze({ code = "INVALID_DEPENDENCIES" :: "INVALID_DEPENDENCIES" }),
	UNAVAILABLE = table.freeze({ code = "UNAVAILABLE" :: "UNAVAILABLE" }),
	REQUEST_PENDING = table.freeze({ code = "REQUEST_PENDING" :: "REQUEST_PENDING" }),
	INVALID_ARGUMENT = table.freeze({ code = "INVALID_ARGUMENT" :: "INVALID_ARGUMENT" }),
	INTERNAL_ERROR = table.freeze({ code = "INTERNAL_ERROR" :: "INTERNAL_ERROR" }),
})

local TowerPlacementController = {
	SERVICE_NAME = SERVICE_NAME,
	CONNECTION_COUNT = CONNECTION_COUNT,
	RAY_LENGTH_STUDS = RAY_LENGTH_STUDS,
	STUDIO_EVIDENCE_TRIGGER_NAME = STUDIO_EVIDENCE_TRIGGER_NAME,
	newForTests = nil :: TestConstructor?,
	invokeUiActionForTests = nil :: ((Controller, unknown) -> ())?,
}

local onUiAction: (ControllerData, unknown) -> ()
local collectMetrics: (ControllerData) -> Metrics

local function failure(code: ErrorCode)
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

local function resultIsOk(value: unknown): boolean
	return type(value) == "table" and rawget(value :: any, "ok") == true
end

local function resultValue(value: unknown): unknown
	return if resultIsOk(value) then rawget(value :: any, "value") else nil
end

local function saturatingIncrement(value: number): number
	return math.min(value + 1, Validation.MAX_SAFE_INTEGER)
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
		and definition.name == PlacementProtocol.REVISION_ENDPOINT
		and definition.direction == "ServerToClient"
		and definition.kind == "Event"
		and definition.response == "None"
		and type(endpoint.connectEvent) == "function"
end

local function methodsExist(value: unknown, names: { string }): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, name in names do
		if type(rawget(value :: any, name)) ~= "function" and type((value :: any)[name]) ~= "function" then
			return false
		end
	end
	return true
end

local function validateDependencies(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local dependencies = value :: any
	local allowed = {
		tracker = true,
		getQuery = true,
		submitPlacement = true,
		revisionEvent = true,
		reducer = true,
		input = true,
		view = true,
		connectInputBegan = true,
		connectInputChanged = true,
		connectInputEnded = true,
		connectPreferredInputChanged = true,
		connectRenderStep = true,
		getPointerPosition = true,
		getViewportSize = true,
		getInitialInput = true,
		raycast = true,
		isStudio = true,
		createStudioEvidenceTrigger = true,
	}
	local count = 0
	for key in next, dependencies do
		count += 1
		if type(key) ~= "string" or allowed[key] ~= true then
			return false
		end
	end
	if count ~= 18 then
		return false
	end
	return methodsExist(dependencies.tracker, { "register", "buildRequest", "handleResponse", "cancel", "clear" })
		and validateRequestEndpoint(dependencies.getQuery, PlacementProtocol.GET_QUERY_ENDPOINT)
		and validateRequestEndpoint(dependencies.submitPlacement, PlacementProtocol.SUBMIT_PLACEMENT_ENDPOINT)
		and validateEventEndpoint(dependencies.revisionEvent)
		and methodsExist(dependencies.reducer, {
			"observeQuery",
			"observeRevision",
			"selectSlot",
			"setPosition",
			"clearPosition",
			"rotate",
			"setPreferredInput",
			"beginSubmit",
			"observeReceipt",
			"abortSubmit",
			"cancel",
			"getState",
			"cleanup",
		})
		and methodsExist(dependencies.input, {
			"setPreferredInput",
			"setViewport",
			"desktopPointer",
			"touchBegan",
			"touchChanged",
			"touchEnded",
			"touchCancelled",
			"confirm",
			"cancel",
			"rotate",
			"selectSlot",
			"cycleSlot",
			"gamepadStep",
			"getReticle",
			"getMetrics",
			"cleanup",
		})
		and methodsExist(dependencies.view, { "render", "setReticle", "getMetrics", "cleanup" })
		and type(dependencies.connectInputBegan) == "function"
		and type(dependencies.connectInputChanged) == "function"
		and type(dependencies.connectInputEnded) == "function"
		and type(dependencies.connectPreferredInputChanged) == "function"
		and type(dependencies.connectRenderStep) == "function"
		and type(dependencies.getPointerPosition) == "function"
		and type(dependencies.getViewportSize) == "function"
		and type(dependencies.getInitialInput) == "function"
		and type(dependencies.raycast) == "function"
		and type(dependencies.isStudio) == "function"
		and type(dependencies.createStudioEvidenceTrigger) == "function"
end

local function readState(data: ControllerData): any?
	local dependencies = data.dependencies
	if dependencies == nil then
		return nil
	end
	local called, result = pcall(function()
		return dependencies.reducer:getState()
	end)
	if not called or not resultIsOk(result) then
		return nil
	end
	local state = resultValue(result)
	return if type(state) == "table" then state else nil
end

local function render(data: ControllerData): boolean
	local dependencies = data.dependencies
	if dependencies == nil then
		return false
	end
	local state = readState(data)
	if state == nil then
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return false
	end
	local rendered, renderResult = pcall(function()
		return dependencies.view:render(state)
	end)
	if not rendered or not resultIsOk(renderResult) then
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return false
	end
	local reticleResult = dependencies.input:getReticle()
	if resultIsOk(reticleResult) then
		local reticle = resultValue(reticleResult)
		local visible = state.preferredInput == "Gamepad" and state.selectedSlot ~= nil
		local reticleRendered, reticleRenderResult = pcall(function()
			return dependencies.view:setReticle(reticle, visible)
		end)
		if not reticleRendered or not resultIsOk(reticleRenderResult) then
			data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
			return false
		end
	end
	data.renderCount = saturatingIncrement(data.renderCount)
	return true
end

local function addConnection(data: ControllerData, value: unknown): boolean
	if typeof(value) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, value :: RBXScriptConnection)
	return true
end

local function disconnectAll(data: ControllerData): boolean
	local succeeded = true
	for index = #data.connections, 1, -1 do
		local connection = data.connections[index]
		data.connections[index] = nil
		if not pcall(function()
			connection:Disconnect()
		end) then
			succeeded = false
		end
	end
	return succeeded
end

local function cancelPending(data: ControllerData, field: "getPending" | "submitPending")
	local record = data[field]
	data[field] = nil
	local dependencies = data.dependencies
	if record == nil or dependencies == nil then
		return
	end
	pcall(function()
		dependencies.tracker:cancel(record.pending)
	end)
end

local function callbackIsCurrent(data: ControllerData, generation: number): boolean
	return data.callbacksEnabled and data.state == "Started" and generation == data.callbackGeneration
end

local function issueQuery(data: ControllerData): boolean
	local dependencies = data.dependencies
	if data.state ~= "Started" or not data.callbacksEnabled or dependencies == nil then
		return false
	end
	if data.getPending ~= nil then
		data.refreshQueued = true
		return true
	end
	local built = dependencies.tracker:buildRequest(PlacementProtocol.GET_QUERY_ENDPOINT, {})
	if not resultIsOk(built) then
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return false
	end
	local request = resultValue(built)
	if type(request) ~= "table" or not RequestProtocol.isPending((request :: any).pending) then
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return false
	end
	data.getPending = { pending = (request :: any).pending }
	data.queryRequestCount = saturatingIncrement(data.queryRequestCount)
	if not pcall(dependencies.getQuery.fire, (request :: any).envelope) then
		cancelPending(data, "getPending")
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return false
	end
	return true
end

local function requestRefresh(data: ControllerData)
	if data.getPending ~= nil then
		data.refreshQueued = true
	else
		issueQuery(data)
	end
end

local function applyQueryResponse(data: ControllerData, payload: unknown): boolean
	local dependencies = data.dependencies :: Dependencies
	local called, applied = pcall(function()
		return dependencies.reducer:observeQuery(payload)
	end)
	if not called or not resultIsOk(applied) then
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return false
	end
	return render(data)
end

local function onGetResponse(data: ControllerData, generation: number, value: unknown, ...: unknown)
	if not callbackIsCurrent(data, generation) then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local handled = dependencies.tracker:handleResponse(dependencies.getQuery.definition, value, ...)
	if not resultIsOk(handled) then
		if
			type(handled) == "table"
			and type((handled :: any).error) == "table"
			and (handled :: any).error.code == "MALFORMED_RESPONSE"
		then
			cancelPending(data, "getPending")
			data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		end
		return
	end
	data.getPending = nil
	local response = resultValue(handled)
	if RequestProtocol.isSuccess(response) then
		applyQueryResponse(data, (response :: RequestProtocol.Success).payload)
	else
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
	end
	local queued = data.refreshQueued
	data.refreshQueued = false
	local state = readState(data)
	if queued or (state ~= nil and state.refreshRequired == true) then
		issueQuery(data)
	end
end

local function onRevisionEvent(data: ControllerData, generation: number, value: unknown, ...: unknown)
	if not callbackIsCurrent(data, generation) then
		return
	end
	local parsed = RequestProtocol.parseEvent(value, ...)
	if not parsed.ok then
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local called, observed = pcall(function()
		return dependencies.reducer:observeRevision(parsed.value.payload)
	end)
	if not called or not resultIsOk(observed) then
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return
	end
	data.revisionEventCount = saturatingIncrement(data.revisionEventCount)
	local outcome = resultValue(observed)
	if type(outcome) == "table" and ((outcome :: any).kind == "Advanced" or (outcome :: any).kind == "Bootstrap") then
		requestRefresh(data)
	end
	render(data)
end

local function issueSubmit(data: ControllerData): boolean
	local dependencies = data.dependencies
	if data.state ~= "Started" or not data.callbacksEnabled or dependencies == nil then
		return false
	end
	if data.submitPending ~= nil then
		return false
	end
	local began = dependencies.reducer:beginSubmit()
	if not resultIsOk(began) then
		return false
	end
	local built = dependencies.tracker:buildRequest(PlacementProtocol.SUBMIT_PLACEMENT_ENDPOINT, resultValue(began))
	if not resultIsOk(built) then
		dependencies.reducer:abortSubmit()
		return false
	end
	local request = resultValue(built)
	if type(request) ~= "table" or not RequestProtocol.isPending((request :: any).pending) then
		dependencies.reducer:abortSubmit()
		return false
	end
	data.submitPending = { pending = (request :: any).pending }
	data.submitRequestCount = saturatingIncrement(data.submitRequestCount)
	render(data)
	if not pcall(dependencies.submitPlacement.fire, (request :: any).envelope) then
		cancelPending(data, "submitPending")
		dependencies.reducer:abortSubmit()
		render(data)
		return false
	end
	return true
end

local function onSubmitResponse(data: ControllerData, generation: number, value: unknown, ...: unknown)
	if not callbackIsCurrent(data, generation) then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local handled = dependencies.tracker:handleResponse(dependencies.submitPlacement.definition, value, ...)
	if not resultIsOk(handled) then
		if
			type(handled) == "table"
			and type((handled :: any).error) == "table"
			and (handled :: any).error.code == "MALFORMED_RESPONSE"
		then
			cancelPending(data, "submitPending")
			dependencies.reducer:abortSubmit()
			data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
			render(data)
		end
		return
	end
	data.submitPending = nil
	local response = resultValue(handled)
	if RequestProtocol.isSuccess(response) then
		local observed = dependencies.reducer:observeReceipt((response :: RequestProtocol.Success).payload)
		if resultIsOk(observed) then
			local receipt = resultValue(observed)
			if type(receipt) == "table" and (receipt :: any).state == "Accepted" then
				data.acceptedPlacementCount = saturatingIncrement(data.acceptedPlacementCount)
			else
				data.rejectedPlacementCount = saturatingIncrement(data.rejectedPlacementCount)
			end
		else
			dependencies.reducer:abortSubmit()
			data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		end
	else
		dependencies.reducer:abortSubmit()
		data.rejectedPlacementCount = saturatingIncrement(data.rejectedPlacementCount)
	end
	render(data)
	local state = readState(data)
	if state ~= nil and state.refreshRequired == true then
		requestRefresh(data)
	end
end

local function selectCycledSlot(data: ControllerData, direction: number): boolean
	local dependencies = data.dependencies :: Dependencies
	local state = readState(data)
	if state == nil or type(state.snapshot) ~= "table" then
		return false
	end
	local start = if type(state.selectedSlot) == "number" then state.selectedSlot else (if direction > 0 then 0 else 6)
	for offset = 1, PlacementProtocol.MAX_LOADOUT_SLOTS do
		local slot = ((start - 1 + direction * offset) % PlacementProtocol.MAX_LOADOUT_SLOTS) + 1
		if state.snapshot.slots[slot].kind == "Occupied" then
			return resultIsOk(dependencies.reducer:selectSlot(slot))
		end
	end
	return false
end

local function applyAction(data: ControllerData, actionValue: unknown)
	if type(actionValue) ~= "table" then
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return
	end
	local action = actionValue :: any
	local dependencies = data.dependencies :: Dependencies
	data.inputActionCount = saturatingIncrement(data.inputActionCount)
	if action.kind == "Position" and typeof(action.screenPosition) == "Vector2" then
		data.raycastRequested = action.screenPosition
		return
	elseif action.kind == "Confirm" then
		if not issueSubmit(data) then
			data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		end
		return
	elseif action.kind == "Cancel" then
		if data.submitPending == nil then
			dependencies.reducer:cancel()
			render(data)
		end
		return
	elseif action.kind == "Rotate" and type(action.rotationDegrees) == "number" then
		dependencies.reducer:rotate(action.rotationDegrees)
		render(data)
		return
	elseif action.kind == "SelectSlot" and type(action.slot) == "number" then
		dependencies.reducer:selectSlot(action.slot)
		render(data)
		return
	elseif action.kind == "CycleSlot" and (action.direction == -1 or action.direction == 1) then
		selectCycledSlot(data, action.direction)
		render(data)
		return
	end
	data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
end

local function applyAdapterResult(data: ControllerData, result: unknown)
	if not resultIsOk(result) then
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return
	end
	local action = resultValue(result)
	if action ~= nil then
		applyAction(data, action)
	end
end

local function onInput(data: ControllerData, generation: number, value: unknown)
	if not callbackIsCurrent(data, generation) or type(value) ~= "table" then
		return
	end
	local input = value :: any
	local dependencies = data.dependencies :: Dependencies
	if input.kind == "TouchBegin" then
		applyAdapterResult(data, dependencies.input:touchBegan(input.touchId, input.position, input.processed == true))
	elseif input.kind == "TouchMove" then
		applyAdapterResult(data, dependencies.input:touchChanged(input.touchId, input.position))
	elseif input.kind == "TouchEnd" then
		applyAdapterResult(data, dependencies.input:touchEnded(input.touchId, input.position))
	elseif input.kind == "TouchCancel" then
		applyAdapterResult(data, dependencies.input:touchCancelled(input.touchId))
	elseif input.kind == "GamepadAxis" then
		if typeof(input.axis) == "Vector2" then
			data.gamepadAxis = input.axis
		else
			data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		end
	elseif input.kind == "Confirm" then
		applyAdapterResult(data, dependencies.input:confirm(input.source))
	elseif input.kind == "Cancel" then
		applyAdapterResult(data, dependencies.input:cancel(input.source))
	elseif input.kind == "Rotate" then
		applyAdapterResult(data, dependencies.input:rotate(input.source, input.direction))
	elseif input.kind == "SelectSlot" then
		applyAdapterResult(data, dependencies.input:selectSlot(input.source, input.slot))
	elseif input.kind == "CycleSlot" then
		applyAdapterResult(data, dependencies.input:cycleSlot(input.direction))
	else
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
	end
end

local function setPreferredInput(data: ControllerData, generation: number, value: unknown)
	if not callbackIsCurrent(data, generation) then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local inputResult = dependencies.input:setPreferredInput(value)
	local reducerResult = dependencies.reducer:setPreferredInput(value)
	if not resultIsOk(inputResult) or not resultIsOk(reducerResult) then
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return
	end
	render(data)
end

local function studioRequestHasExactKeys(value: unknown, operation: string, extraKey: string?): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local request = value :: any
	if request.operation ~= operation then
		return false
	end
	local expectedCount = if extraKey == nil then 1 else 2
	local count = 0
	for key in next, request do
		count += 1
		if key ~= "operation" and key ~= extraKey then
			return false
		end
	end
	return count == expectedCount
end

local function dispatchStudioEvidence(data: ControllerData, argumentCount: number, requestValue: unknown): unknown
	if data.state ~= "Started" or not data.callbacksEnabled then
		return failure("UNAVAILABLE")
	end
	if argumentCount ~= 1 or type(requestValue) ~= "table" then
		return failure("INVALID_ARGUMENT")
	end
	local request = requestValue :: any
	local operation = request.operation
	local normalized: NormalizedInput? = nil
	if operation == "Diagnostics" and studioRequestHasExactKeys(request, "Diagnostics", nil) then
		data.studioOperationCount = saturatingIncrement(data.studioOperationCount)
		return Result.ok(collectMetrics(data))
	elseif operation == "CycleNext" and studioRequestHasExactKeys(request, "CycleNext", nil) then
		normalized = table.freeze({ kind = "CycleSlot", source = "Gamepad", direction = 1 })
	elseif operation == "CyclePrevious" and studioRequestHasExactKeys(request, "CyclePrevious", nil) then
		normalized = table.freeze({ kind = "CycleSlot", source = "Gamepad", direction = -1 })
	elseif operation == "Rotate" and studioRequestHasExactKeys(request, "Rotate", nil) then
		normalized = table.freeze({ kind = "Rotate", source = "Gamepad", direction = 1 })
	elseif operation == "Confirm" and studioRequestHasExactKeys(request, "Confirm", nil) then
		normalized = table.freeze({ kind = "Confirm", source = "Gamepad" })
	elseif operation == "Cancel" and studioRequestHasExactKeys(request, "Cancel", nil) then
		normalized = table.freeze({ kind = "Cancel", source = "Gamepad" })
	elseif operation == "Axis" and studioRequestHasExactKeys(request, "Axis", "axis") then
		local axis = request.axis
		if
			typeof(axis) == "Vector2"
			and Validation.isFiniteNumber(axis.X)
			and Validation.isFiniteNumber(axis.Y)
			and math.abs(axis.X) <= 1
			and math.abs(axis.Y) <= 1
		then
			normalized = table.freeze({ kind = "GamepadAxis", source = "Gamepad", axis = axis })
		end
	end
	if normalized == nil then
		return failure("INVALID_ARGUMENT")
	end
	data.studioOperationCount = saturatingIncrement(data.studioOperationCount)
	local generation = data.callbackGeneration
	setPreferredInput(data, generation, "Gamepad")
	onInput(data, generation, normalized)
	return Result.ok(collectMetrics(data))
end

local function isStudioEvidenceTrigger(value: unknown): boolean
	if typeof(value) == "Instance" then
		return (value :: Instance):IsA("BindableFunction")
	end
	return type(value) == "table" and type((value :: any).Destroy) == "function"
end

local function installStudioEvidenceTrigger(data: ControllerData): boolean
	local dependencies = data.dependencies :: Dependencies
	local studioCalled, studioValue = pcall(dependencies.isStudio)
	if not studioCalled or type(studioValue) ~= "boolean" then
		return false
	end
	if not studioValue then
		return true
	end
	local handler = function(...: unknown): unknown
		local called, result = pcall(dispatchStudioEvidence, data, select("#", ...), select(1, ...))
		if called then
			return result
		end
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
		return failure("INTERNAL_ERROR")
	end
	local created, trigger = pcall(dependencies.createStudioEvidenceTrigger, handler)
	if not created or not isStudioEvidenceTrigger(trigger) then
		if isStudioEvidenceTrigger(trigger) then
			pcall(function()
				(trigger :: any):Destroy()
			end)
		end
		return false
	end
	data.studioEvidenceTrigger = trigger
	return true
end

local function destroyStudioEvidenceTrigger(data: ControllerData): boolean
	local trigger = data.studioEvidenceTrigger
	data.studioEvidenceTrigger = nil
	data.studioOperationCount = 0
	if trigger == nil then
		return true
	end
	if typeof(trigger) == "Instance" and (trigger :: Instance):IsA("BindableFunction") then
		local detached = pcall(function()
			(trigger :: BindableFunction).OnInvoke = nil
		end)
		local destroyed = pcall(function()
			(trigger :: Instance):Destroy()
		end)
		return detached and destroyed
	end
	return pcall(function()
		(trigger :: any):Destroy()
	end)
end

local function onRenderStep(data: ControllerData, generation: number, deltaSecondsValue: unknown)
	if not callbackIsCurrent(data, generation) then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local deltaSeconds = if type(deltaSecondsValue) == "number" and Validation.isFiniteNumber(deltaSecondsValue)
		then math.clamp(deltaSecondsValue, 0, PlacementInputAdapter.MAX_GAMEPAD_STEP_SECONDS)
		else 0
	local viewportCalled, viewport = pcall(dependencies.getViewportSize)
	if viewportCalled and typeof(viewport) == "Vector2" then
		dependencies.input:setViewport(viewport)
	end
	local state = readState(data)
	if state ~= nil and state.selectedSlot ~= nil then
		if state.preferredInput == "Desktop" then
			local pointerCalled, pointer = pcall(dependencies.getPointerPosition)
			if pointerCalled then
				applyAdapterResult(data, dependencies.input:desktopPointer(pointer))
			end
		elseif state.preferredInput == "Gamepad" then
			applyAdapterResult(data, dependencies.input:gamepadStep(data.gamepadAxis, deltaSeconds))
		end
	end
	local requested = data.raycastRequested
	data.raycastRequested = nil
	local frameRaycasts = 0
	if requested ~= nil and state ~= nil and state.selectedSlot ~= nil and state.phase ~= "Submitting" then
		frameRaycasts = 1
		data.raycastCount = saturatingIncrement(data.raycastCount)
		local raycastCalled, hitPosition = pcall(dependencies.raycast, requested)
		if raycastCalled and typeof(hitPosition) == "Vector3" then
			local position = hitPosition :: Vector3
			if
				Validation.isFiniteNumber(position.X)
				and Validation.isFiniteNumber(position.Y)
				and Validation.isFiniteNumber(position.Z)
			then
				dependencies.reducer:setPosition(Vector2.new(position.X, position.Z))
			else
				dependencies.reducer:clearPosition()
			end
		else
			dependencies.reducer:clearPosition()
		end
	end
	data.maximumRaycastsPerFrame = math.max(data.maximumRaycastsPerFrame, frameRaycasts)
	render(data)
end

onUiAction = function(data: ControllerData, value: unknown)
	if data.state ~= "Started" or not data.callbacksEnabled or type(value) ~= "table" then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local state = readState(data)
	if state == nil then
		return
	end
	local action = value :: any
	if action.kind == "SelectSlot" then
		applyAdapterResult(data, dependencies.input:selectSlot(state.preferredInput, action.slot))
	elseif state.preferredInput == "Touch" and action.kind == "Confirm" then
		applyAdapterResult(data, dependencies.input:confirm("Touch"))
	elseif state.preferredInput == "Touch" and action.kind == "Cancel" then
		applyAdapterResult(data, dependencies.input:cancel("Touch"))
	elseif state.preferredInput == "Touch" and action.kind == "Rotate" then
		applyAdapterResult(data, dependencies.input:rotate("Touch", 1))
	else
		data.rejectedInputCount = saturatingIncrement(data.rejectedInputCount)
	end
end

local function cleanup(data: ControllerData): boolean
	if data.state == "Shutdown" then
		return true
	end
	data.state = "ShuttingDown"
	data.callbacksEnabled = false
	data.callbackGeneration += 1
	cancelPending(data, "getPending")
	cancelPending(data, "submitPending")
	data.refreshQueued = false
	data.raycastRequested = nil
	data.gamepadAxis = Vector2.zero
	local succeeded = destroyStudioEvidenceTrigger(data)
	if not disconnectAll(data) then
		succeeded = false
	end
	local dependencies = data.dependencies
	if dependencies ~= nil then
		if not pcall(function()
			dependencies.tracker:clear()
		end) then
			succeeded = false
		end
		for _, target in { dependencies.view, dependencies.input, dependencies.reducer } do
			local cleaned, cleanResult = pcall(function()
				return target:cleanup()
			end)
			if not cleaned or not resultIsOk(cleanResult) then
				succeeded = false
			end
		end
	end
	data.dependencies = nil
	data.state = if succeeded then "Shutdown" else "Failed"
	return succeeded
end

local function initialize(data: ControllerData)
	if data.state ~= "Constructed" then
		staticError("INVALID_INITIALIZE_STATE")
	end
	data.state = "Initializing"
	local created, dependencies = pcall(data.dependencyFactory, function(action)
		onUiAction(data, action)
	end)
	if not created or not validateDependencies(dependencies) then
		data.state = "Failed"
		staticError("INITIALIZE_FAILED")
	end
	data.dependencies = dependencies
	local selected = dependencies :: Dependencies
	local getRegistered = selected.tracker:register(
		PlacementProtocol.GET_QUERY_ENDPOINT,
		PlacementProtocol.GetQueryPayloadSchema,
		PlacementProtocol.QuerySnapshotSchema
	)
	local submitRegistered = selected.tracker:register(
		PlacementProtocol.SUBMIT_PLACEMENT_ENDPOINT,
		PlacementProtocol.SubmitPlacementPayloadSchema,
		PlacementProtocol.PlacementReceiptSchema
	)
	if not resultIsOk(getRegistered) or not resultIsOk(submitRegistered) then
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
		return dependencies.revisionEvent.connectEvent(function(value, ...)
			onRevisionEvent(data, generation, value, ...)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.getQuery.connectResponse(function(value, ...)
			onGetResponse(data, generation, value, ...)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.submitPlacement.connectResponse(function(value, ...)
			onSubmitResponse(data, generation, value, ...)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.connectInputBegan(function(value)
			onInput(data, generation, value)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.connectInputChanged(function(value)
			onInput(data, generation, value)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.connectInputEnded(function(value)
			onInput(data, generation, value)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.connectPreferredInputChanged(function(value)
			setPreferredInput(data, generation, value)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.connectRenderStep(function(deltaSeconds)
			onRenderStep(data, generation, deltaSeconds)
		end)
	end)
	local initialCalled, initialInput = pcall(dependencies.getInitialInput)
	if initialCalled then
		dependencies.input:setPreferredInput(initialInput)
		dependencies.reducer:setPreferredInput(initialInput)
	end
	local viewportCalled, viewport = pcall(dependencies.getViewportSize)
	if viewportCalled then
		dependencies.input:setViewport(viewport)
	end
	render(data)
	if not installStudioEvidenceTrigger(data) then
		cleanup(data)
		staticError("STUDIO_TRIGGER_INSTALL_FAILED")
	end
	if not issueQuery(data) then
		cleanup(data)
		staticError("START_FAILED")
	end
end

local function construct(logger: Log.Logger, dependencyFactory: DependencyFactory): ControllerResult
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
		getPending = nil,
		submitPending = nil,
		refreshQueued = false,
		raycastRequested = nil,
		gamepadAxis = Vector2.zero,
		queryRequestCount = 0,
		submitRequestCount = 0,
		acceptedPlacementCount = 0,
		rejectedPlacementCount = 0,
		revisionEventCount = 0,
		renderCount = 0,
		raycastCount = 0,
		maximumRaycastsPerFrame = 0,
		inputActionCount = 0,
		rejectedInputCount = 0,
		studioEvidenceTrigger = nil,
		studioOperationCount = 0,
	}
	return Result.ok(controller)
end

function ControllerMethods.getState(self: Controller): LifecycleState
	return requireData(self).state
end

collectMetrics = function(data: ControllerData): Metrics
	local dependencies = data.dependencies
	local state = readState(data)
	local snapshot = if state == nil then nil else state.snapshot
	local viewMetrics: unknown = nil
	local inputMetrics: unknown = nil
	if dependencies ~= nil then
		pcall(function()
			viewMetrics = dependencies.view:getMetrics()
			inputMetrics = dependencies.input:getMetrics()
		end)
	end
	return table.freeze({
		lifecycleState = data.state,
		connectionCount = #data.connections,
		callbackGeneration = data.callbackGeneration,
		queryRequestCount = data.queryRequestCount,
		queryPending = data.getPending ~= nil,
		refreshQueued = data.refreshQueued,
		submitRequestCount = data.submitRequestCount,
		submitPending = data.submitPending ~= nil,
		acceptedPlacementCount = data.acceptedPlacementCount,
		rejectedPlacementCount = data.rejectedPlacementCount,
		revisionEventCount = data.revisionEventCount,
		renderCount = data.renderCount,
		raycastCount = data.raycastCount,
		maximumRaycastsPerFrame = data.maximumRaycastsPerFrame,
		inputActionCount = data.inputActionCount,
		rejectedInputCount = data.rejectedInputCount,
		studioTriggerCount = if data.studioEvidenceTrigger == nil then 0 else 1,
		studioOperationCount = data.studioOperationCount,
		preferredInput = if state == nil then nil else state.preferredInput,
		phase = if state == nil then nil else state.phase,
		selectedSlot = if state == nil then nil else state.selectedSlot,
		queryRevision = if type(snapshot) == "table" then snapshot.queryRevision else nil,
		refreshRequired = state ~= nil and state.refreshRequired == true,
		viewMetrics = viewMetrics,
		inputMetrics = inputMetrics,
	})
end

function ControllerMethods.getMetrics(self: Controller): Metrics
	return collectMetrics(requireData(self))
end

function ControllerMethods.getServiceDefinition(self: Controller)
	local data = requireData(self)
	return table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({ WAVE_CONTROLLER_SERVICE_NAME }),
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

local function inputFamilyFromType(inputType: Enum.UserInputType): InputFamily
	local name = inputType.Name
	if name == "Touch" then
		return "Touch"
	elseif string.sub(name, 1, 7) == "Gamepad" then
		return "Gamepad"
	end
	return "Desktop"
end

local function inputPosition(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function makeProductionDependencies(uiActionCallback: PlacementPreviewView.UiActionCallback): Dependencies
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
	local reducerResult = PlacementPreviewReducer.new()
	local inputResult = PlacementInputAdapter.new()
	local viewResult = PlacementPreviewView.new(uiActionCallback)
	if
		not resultIsOk(trackerResult)
		or not resultIsOk(reducerResult)
		or not resultIsOk(inputResult)
		or not resultIsOk(viewResult)
	then
		staticError("CLIENT_DEPENDENCY_CREATION_FAILED")
	end
	local getLookup = ClientRemoteLookup.resolve(PlacementProtocol.GET_QUERY_ENDPOINT, LOOKUP_TIMEOUT_SECONDS)
	local submitLookup = ClientRemoteLookup.resolve(PlacementProtocol.SUBMIT_PLACEMENT_ENDPOINT, LOOKUP_TIMEOUT_SECONDS)
	local revisionLookup = ClientRemoteLookup.resolve(PlacementProtocol.REVISION_ENDPOINT, LOOKUP_TIMEOUT_SECONDS)
	if not resultIsOk(getLookup) or not resultIsOk(submitLookup) or not resultIsOk(revisionLookup) then
		staticError("REMOTE_LOOKUP_FAILED")
	end
	local getEndpoint = resultValue(getLookup) :: any
	local submitEndpoint = resultValue(submitLookup) :: any
	local revisionEndpoint = resultValue(revisionLookup) :: any
	if
		getEndpoint.request == nil
		or getEndpoint.response == nil
		or getEndpoint.event ~= nil
		or submitEndpoint.request == nil
		or submitEndpoint.response == nil
		or submitEndpoint.event ~= nil
		or revisionEndpoint.request ~= nil
		or revisionEndpoint.response ~= nil
		or revisionEndpoint.event == nil
	then
		staticError("REMOTE_SHAPE_INVALID")
	end
	local getRequest = getEndpoint.request :: RemoteEvent
	local getResponse = getEndpoint.response :: RemoteEvent
	local submitRequest = submitEndpoint.request :: RemoteEvent
	local submitResponse = submitEndpoint.response :: RemoteEvent
	local revisionEvent = revisionEndpoint.event :: RemoteEvent
	local touchIds: { [InputObject]: number } = {}

	local function findTouchId(input: InputObject, create: boolean): number?
		local existing = touchIds[input]
		if existing ~= nil or not create then
			return existing
		end
		local occupied: { [number]: boolean } = {}
		for _, touchId in touchIds do
			occupied[touchId] = true
		end
		for touchId = 1, PlacementInputAdapter.MAX_ACTIVE_TOUCHES do
			if occupied[touchId] ~= true then
				touchIds[input] = touchId
				return touchId
			end
		end
		return nil
	end

	local function normalizedControl(input: InputObject): NormalizedInput?
		local inputType = input.UserInputType
		local keyCode = input.KeyCode
		local source = inputFamilyFromType(inputType)
		if inputType == Enum.UserInputType.MouseButton1 then
			return table.freeze({ kind = "Confirm", source = "Desktop" })
		elseif inputType == Enum.UserInputType.Keyboard then
			local slots = {
				[Enum.KeyCode.One] = 1,
				[Enum.KeyCode.Two] = 2,
				[Enum.KeyCode.Three] = 3,
				[Enum.KeyCode.Four] = 4,
				[Enum.KeyCode.Five] = 5,
			}
			local slot = slots[keyCode]
			if slot ~= nil then
				return table.freeze({ kind = "SelectSlot", source = "Desktop", slot = slot })
			elseif keyCode == Enum.KeyCode.R then
				return table.freeze({ kind = "Rotate", source = "Desktop", direction = 1 })
			elseif keyCode == Enum.KeyCode.Q or keyCode == Enum.KeyCode.Escape then
				return table.freeze({ kind = "Cancel", source = "Desktop" })
			elseif keyCode == Enum.KeyCode.Return then
				return table.freeze({ kind = "Confirm", source = "Desktop" })
			end
		elseif source == "Gamepad" then
			if keyCode == Enum.KeyCode.ButtonA then
				return table.freeze({ kind = "Confirm", source = "Gamepad" })
			elseif keyCode == Enum.KeyCode.ButtonB then
				return table.freeze({ kind = "Cancel", source = "Gamepad" })
			elseif keyCode == Enum.KeyCode.ButtonR1 then
				return table.freeze({ kind = "Rotate", source = "Gamepad", direction = 1 })
			elseif keyCode == Enum.KeyCode.ButtonL1 then
				return table.freeze({ kind = "CycleSlot", source = "Gamepad", direction = -1 })
			elseif keyCode == Enum.KeyCode.ButtonR2 then
				return table.freeze({ kind = "CycleSlot", source = "Gamepad", direction = 1 })
			end
		end
		return nil
	end

	return {
		tracker = resultValue(trackerResult) :: any,
		getQuery = {
			definition = getEndpoint.definition,
			connectResponse = function(listener)
				return getResponse.OnClientEvent:Connect(listener)
			end,
			fire = function(envelope)
				getRequest:FireServer(envelope)
			end,
		},
		submitPlacement = {
			definition = submitEndpoint.definition,
			connectResponse = function(listener)
				return submitResponse.OnClientEvent:Connect(listener)
			end,
			fire = function(envelope)
				submitRequest:FireServer(envelope)
			end,
		},
		revisionEvent = {
			definition = revisionEndpoint.definition,
			connectEvent = function(listener)
				return revisionEvent.OnClientEvent:Connect(listener)
			end,
		},
		reducer = resultValue(reducerResult) :: any,
		input = resultValue(inputResult) :: any,
		view = resultValue(viewResult) :: any,
		connectInputBegan = function(listener)
			return UserInputService.InputBegan:Connect(function(input, processed)
				if input.UserInputType == Enum.UserInputType.Touch then
					local touchId = findTouchId(input, true)
					if touchId ~= nil then
						listener(table.freeze({
							kind = "TouchBegin",
							source = "Touch",
							touchId = touchId,
							position = inputPosition(input),
							processed = processed,
						}))
					end
					return
				end
				if processed then
					return
				end
				local normalized = normalizedControl(input)
				if normalized ~= nil then
					listener(normalized)
				end
			end)
		end,
		connectInputChanged = function(listener)
			return UserInputService.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch then
					local touchId = findTouchId(input, false)
					if touchId ~= nil then
						listener(table.freeze({
							kind = "TouchMove",
							source = "Touch",
							touchId = touchId,
							position = inputPosition(input),
						}))
					end
				elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
					listener(table.freeze({
						kind = "GamepadAxis",
						source = "Gamepad",
						axis = Vector2.new(input.Position.X, -input.Position.Y),
					}))
				end
			end)
		end,
		connectInputEnded = function(listener)
			return UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch then
					local touchId = findTouchId(input, false)
					if touchId ~= nil then
						listener(table.freeze({
							kind = "TouchEnd",
							source = "Touch",
							touchId = touchId,
							position = inputPosition(input),
						}))
						touchIds[input] = nil
					end
				elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
					listener(table.freeze({
						kind = "GamepadAxis",
						source = "Gamepad",
						axis = Vector2.zero,
					}))
				end
			end)
		end,
		connectPreferredInputChanged = function(listener)
			return UserInputService.LastInputTypeChanged:Connect(function(inputType)
				listener(inputFamilyFromType(inputType))
			end)
		end,
		connectRenderStep = function(listener)
			return RunService.RenderStepped:Connect(listener)
		end,
		getPointerPosition = function()
			return UserInputService:GetMouseLocation()
		end,
		getViewportSize = function()
			local camera = Workspace.CurrentCamera
			return if camera == nil then Vector2.new(1280, 720) else camera.ViewportSize
		end,
		getInitialInput = function()
			return inputFamilyFromType(UserInputService:GetLastInputType())
		end,
		raycast = function(screenPosition)
			local camera = Workspace.CurrentCamera
			local runtimeMap = Workspace:FindFirstChild(RUNTIME_MAP_NAME)
			if camera == nil or runtimeMap == nil or not runtimeMap:IsA("Model") then
				return nil
			end
			local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
			local parameters = RaycastParams.new()
			parameters.FilterType = Enum.RaycastFilterType.Include
			parameters.FilterDescendantsInstances = { runtimeMap }
			parameters.IgnoreWater = false
			local result = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH_STUDS, parameters)
			if result == nil or not result.Instance:IsDescendantOf(runtimeMap) then
				return nil
			end
			return result.Position
		end,
		isStudio = function()
			return RunService:IsStudio()
		end,
		createStudioEvidenceTrigger = function(handler)
			local player = Players.LocalPlayer
			local playerGui = if player == nil then nil else player:FindFirstChildOfClass("PlayerGui")
			if
				not RunService:IsStudio()
				or playerGui == nil
				or playerGui:FindFirstChild(STUDIO_EVIDENCE_TRIGGER_NAME) ~= nil
			then
				return nil
			end
			local trigger = Instance.new("BindableFunction")
			local configured = pcall(function()
				trigger.Name = STUDIO_EVIDENCE_TRIGGER_NAME
				trigger.OnInvoke = handler
				trigger.Parent = playerGui
			end)
			if not configured then
				pcall(function()
					trigger.OnInvoke = nil
					trigger:Destroy()
				end)
				return nil
			end
			return trigger
		end,
	}
end

function TowerPlacementController.new(logger: Log.Logger): ControllerResult
	return construct(logger, makeProductionDependencies)
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "TowerPlacementController" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionClientPlacement" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

if isExactTestModule() then
	TowerPlacementController.newForTests = function(logger: Log.Logger, dependencies: Dependencies): ControllerResult
		return construct(logger, function(_uiActionCallback)
			return dependencies
		end)
	end
	TowerPlacementController.invokeUiActionForTests = function(controller: Controller, action: unknown)
		onUiAction(requireData(controller), action)
	end
end

table.freeze(ControllerMethods)
return table.freeze(TowerPlacementController)
