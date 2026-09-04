--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Log = require(ReplicatedStorage.Shared.logging.Log)
local MatchTravelProtocol = require(ReplicatedStorage.Shared.match.MatchTravelProtocol)
local PlayableMatchProtocol = require(ReplicatedStorage.Shared.match.PlayableMatchProtocol)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local SettingsProtocol = require(ReplicatedStorage.Shared.settings.SettingsProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)

local PlayableInputMap = require(script.Parent.PlayableInputMap)
local PlayableMatchView = require(script.Parent.PlayableMatchView)

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

export type ControllerError = {
	code: ErrorCode,
}

export type ResponseListener = (unknown, ...unknown) -> ()
export type EventListener = (unknown, ...unknown) -> ()
export type WorldPointerListener = (Vector2, PlayableInputMap.InputFamily) -> ()

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

export type InputAdapter = {
	setContext: (self: InputAdapter, value: unknown) -> any,
	getHints: (self: InputAdapter) -> any,
	getMetrics: (self: InputAdapter) -> any,
	cleanup: (self: InputAdapter) -> any,
}

export type ViewAdapter = {
	render: (self: ViewAdapter, value: unknown) -> any,
	syncWorld: (self: ViewAdapter, value: unknown) -> any,
	playAttackEffect: (self: ViewAdapter, value: unknown) -> any,
	getMetrics: (self: ViewAdapter) -> any,
	cleanup: (self: ViewAdapter) -> any,
}

export type Dependencies = {
	localUserId: number,
	tracker: TrackerAdapter,
	getSnapshot: RequestEndpoint,
	submitReady: RequestEndpoint,
	submitPlacement: RequestEndpoint,
	submitUpgrade: RequestEndpoint,
	submitSell: RequestEndpoint,
	submitTargetMode: RequestEndpoint,
	submitReplay: RequestEndpoint,
	getTravelSnapshot: RequestEndpoint,
	requestReturn: RequestEndpoint,
	voteRematch: RequestEndpoint,
	replicationEvent: EventEndpoint,
	attackEvent: EventEndpoint,
	travelReplicationEvent: EventEndpoint,
	view: ViewAdapter,
	input: InputAdapter,
	connectWorldPointer: (WorldPointerListener) -> RBXScriptConnection,
	connectRenderStep: ((number) -> ()) -> RBXScriptConnection,
	now: () -> number,
	getPointerPosition: () -> Vector2,
	getViewportSize: () -> Vector2,
	raycastPlacement: (Vector2) -> Vector3?,
	pickTower: (Vector2, { PlayableMatchProtocol.TowerSnapshot }, PlayableInputMap.InputFamily) -> number?,
	focusOverview: () -> boolean,
	focusBase: () -> boolean,
	focusSpectatorTarget: (Vector3) -> boolean,
	restoreCamera: () -> (),
	applySettings: (SettingsProtocol.Settings) -> (),
	newTransactionId: () -> string,
}

export type Metrics = {
	lifecycleState: LifecycleState,
	connectionCount: number,
	requestCount: number,
	getRequestCount: number,
	actionRequestCount: number,
	recoveryRequestCount: number,
	acceptedSnapshotCount: number,
	rejectedInputCount: number,
	attackEventCount: number,
	renderCount: number,
	matchGeneration: number,
	matchId: string?,
	revision: number?,
	selectedSlot: number?,
	selectedTowerId: number?,
	touchPlacementSelected: boolean,
	rotationDegrees: number,
	getPending: boolean,
	actionPending: boolean,
	travelGetPending: boolean,
	travelMutationPending: boolean,
	viewerRole: PlayableMatchProtocol.ViewerRole?,
	travelRevision: number?,
	spectatorTargetId: string?,
	feedbackCode: string?,
	viewMetrics: unknown,
	inputMetrics: unknown,
}

type PendingGet = {
	pending: RequestProtocol.Pending,
	isRecovery: boolean,
	issuedAt: number,
}

type ActionRequestKind = "Ready" | "Placement" | "Upgrade" | "Sell" | "Retarget" | "Replay"

type PendingAction = {
	pending: RequestProtocol.Pending,
	definition: RemoteRegistry.Definition,
	kind: ActionRequestKind,
	matchId: string,
	issuedAt: number,
}

type PendingTravelGet = {
	pending: RequestProtocol.Pending,
	issuedAt: number,
}

type TravelMutationKind = "Return" | "Rematch"

type PendingTravelMutation = {
	pending: RequestProtocol.Pending,
	definition: RemoteRegistry.Definition,
	kind: TravelMutationKind,
	matchId: string,
	transactionId: string,
	issuedAt: number,
}

type DependencyFactory = (PlayableMatchView.UiActionCallback, PlayableInputMap.ActionCallback) -> Dependencies

type ControllerData = {
	logger: Log.Logger,
	state: LifecycleState,
	dependencyFactory: DependencyFactory,
	dependencies: Dependencies?,
	connections: { RBXScriptConnection },
	callbacksEnabled: boolean,
	callbackGeneration: number,
	cleanupFailed: boolean,
	snapshot: PlayableMatchProtocol.Snapshot?,
	travelSnapshot: MatchTravelProtocol.Snapshot?,
	retiredMatchIds: { [string]: boolean },
	retiredMatchRing: { string },
	matchGeneration: number,
	overviewMatchId: string?,
	lastRenderedViewport: Vector2?,
	selectedSlot: number?,
	selectedTowerId: number?,
	touchPlacementPosition: Vector3?,
	rotationDegrees: number,
	getPending: PendingGet?,
	actionPending: PendingAction?,
	travelGetPending: PendingTravelGet?,
	travelMutationPending: PendingTravelMutation?,
	spectatorTargetId: string?,
	recoveryQueued: boolean,
	lastSnapshotAt: number,
	renderPending: boolean,
	feedbackCode: string?,
	feedbackExpiresAt: number,
	requestCount: number,
	getRequestCount: number,
	actionRequestCount: number,
	recoveryRequestCount: number,
	acceptedSnapshotCount: number,
	rejectedInputCount: number,
	attackEventCount: number,
	renderCount: number,
}

local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

export type Controller = typeof(setmetatable({} :: {}, ControllerMethods))
export type ControllerResult = Result.Result<Controller, ControllerError>
export type TestConstructor = (Log.Logger, Dependencies) -> ControllerResult

local SERVICE_NAME = "PlayableMatchController"
local LOOKUP_TIMEOUT_SECONDS = 5
local RECOVERY_SILENCE_SECONDS = 3
local REQUEST_TIMEOUT_SECONDS = 8
local FEEDBACK_SECONDS = 3
local RETIRED_MATCH_LIMIT = 8
local ROTATION_STEP_DEGREES = 15
local RAY_LENGTH_STUDS = 2_000
local RUNTIME_MAP_NAME = "ATDRuntimeMap"
local STATIC_PREFIX = "[ATD_PLAYABLE_MATCH_CONTROLLER]"

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ControllerData }

local ERRORS: { [ErrorCode]: ControllerError } = table.freeze({
	INVALID_CONTEXT = table.freeze({ code = "INVALID_CONTEXT" :: "INVALID_CONTEXT" }),
	INVALID_DEPENDENCIES = table.freeze({ code = "INVALID_DEPENDENCIES" :: "INVALID_DEPENDENCIES" }),
	INITIALIZE_FAILED = table.freeze({ code = "INITIALIZE_FAILED" :: "INITIALIZE_FAILED" }),
	START_FAILED = table.freeze({ code = "START_FAILED" :: "START_FAILED" }),
	CLEANUP_FAILED = table.freeze({ code = "CLEANUP_FAILED" :: "CLEANUP_FAILED" }),
})

local PlayableMatchController = {
	SERVICE_NAME = SERVICE_NAME,
	RECOVERY_SILENCE_SECONDS = RECOVERY_SILENCE_SECONDS,
	REQUEST_TIMEOUT_SECONDS = REQUEST_TIMEOUT_SECONDS,
	FEEDBACK_SECONDS = FEEDBACK_SECONDS,
	ROTATION_STEP_DEGREES = ROTATION_STEP_DEGREES,
	newForTests = nil :: TestConstructor?,
	invokeSemanticActionForTests = nil :: ((Controller, unknown) -> boolean)?,
	invokeWorldPointerForTests = nil :: ((Controller, unknown, unknown) -> ())?,
}

local REQUEST_SPECS = table.freeze({
	{
		field = "getSnapshot",
		endpoint = PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT,
		requestSchema = PlayableMatchProtocol.GetSnapshotPayloadSchema,
		responseSchema = PlayableMatchProtocol.SnapshotSchema,
	},
	{
		field = "submitReady",
		endpoint = PlayableMatchProtocol.ENDPOINTS.SUBMIT_READY,
		requestSchema = PlayableMatchProtocol.ReadyPayloadSchema,
		responseSchema = PlayableMatchProtocol.ActionReceiptSchema,
	},
	{
		field = "submitPlacement",
		endpoint = PlayableMatchProtocol.ENDPOINTS.SUBMIT_PLACEMENT,
		requestSchema = PlayableMatchProtocol.PlacementPayloadSchema,
		responseSchema = PlayableMatchProtocol.ActionReceiptSchema,
	},
	{
		field = "submitUpgrade",
		endpoint = PlayableMatchProtocol.ENDPOINTS.SUBMIT_UPGRADE,
		requestSchema = PlayableMatchProtocol.TowerPayloadSchema,
		responseSchema = PlayableMatchProtocol.ActionReceiptSchema,
	},
	{
		field = "submitSell",
		endpoint = PlayableMatchProtocol.ENDPOINTS.SUBMIT_SELL,
		requestSchema = PlayableMatchProtocol.TowerPayloadSchema,
		responseSchema = PlayableMatchProtocol.ActionReceiptSchema,
	},
	{
		field = "submitTargetMode",
		endpoint = PlayableMatchProtocol.ENDPOINTS.SUBMIT_TARGET_MODE,
		requestSchema = PlayableMatchProtocol.TargetModePayloadSchema,
		responseSchema = PlayableMatchProtocol.ActionReceiptSchema,
	},
	{
		field = "submitReplay",
		endpoint = PlayableMatchProtocol.ENDPOINTS.SUBMIT_REPLAY,
		requestSchema = PlayableMatchProtocol.ReplayPayloadSchema,
		responseSchema = PlayableMatchProtocol.ActionReceiptSchema,
	},
	{
		field = "getTravelSnapshot",
		endpoint = MatchTravelProtocol.ENDPOINTS.GET_SNAPSHOT,
		requestSchema = MatchTravelProtocol.EmptyPayloadSchema,
		responseSchema = MatchTravelProtocol.SnapshotSchema,
	},
	{
		field = "requestReturn",
		endpoint = MatchTravelProtocol.ENDPOINTS.REQUEST_RETURN,
		requestSchema = MatchTravelProtocol.ReturnIntentSchema,
		responseSchema = MatchTravelProtocol.MutationReceiptSchema,
	},
	{
		field = "voteRematch",
		endpoint = MatchTravelProtocol.ENDPOINTS.VOTE_REMATCH,
		requestSchema = MatchTravelProtocol.RematchVoteIntentSchema,
		responseSchema = MatchTravelProtocol.MutationReceiptSchema,
	},
})

local ACTION_ENDPOINTS: { [ActionRequestKind]: string } = table.freeze({
	Ready = PlayableMatchProtocol.ENDPOINTS.SUBMIT_READY,
	Placement = PlayableMatchProtocol.ENDPOINTS.SUBMIT_PLACEMENT,
	Upgrade = PlayableMatchProtocol.ENDPOINTS.SUBMIT_UPGRADE,
	Sell = PlayableMatchProtocol.ENDPOINTS.SUBMIT_SELL,
	Retarget = PlayableMatchProtocol.ENDPOINTS.SUBMIT_TARGET_MODE,
	Replay = PlayableMatchProtocol.ENDPOINTS.SUBMIT_REPLAY,
})

local RECEIPT_FEEDBACK: { [PlayableMatchProtocol.ActionReason]: string } = table.freeze({
	Accepted = "REQUEST_ACCEPTED",
	WrongState = "MATCH_NOT_ACTIVE",
	StaleMatch = "STALE_MATCH",
	StaleTower = "STALE_TOWER",
	NotParticipant = "REQUEST_REJECTED",
	InvalidPlacement = "INVALID_POSITION",
	InsufficientCash = "INSUFFICIENT_CASH",
	TowerCap = "TOWER_CAP_REACHED",
	NotFound = "TOWER_NOT_FOUND",
	NotOwner = "NOT_OWNER",
	MaxLevel = "REQUEST_REJECTED",
	UnsupportedTargetMode = "REQUEST_REJECTED",
	Busy = "RATE_LIMITED",
	Unavailable = "SERVER_UNAVAILABLE",
})

local PUBLIC_FEEDBACK: { [RequestProtocol.PublicErrorCode]: string } = table.freeze({
	STALE_REQUEST = "STALE_MATCH",
	DUPLICATE_REQUEST = "RATE_LIMITED",
	NOT_AUTHORIZED = "NOT_OWNER",
	RATE_LIMITED = "RATE_LIMITED",
	INVALID_PAYLOAD = "REQUEST_REJECTED",
	UNAVAILABLE = "SERVER_UNAVAILABLE",
	INTERNAL_ERROR = "SERVER_UNAVAILABLE",
})

local function failure(code: ErrorCode): Result.Failure<ControllerError>
	return Result.err(ERRORS[code])
end

local function staticError(code: string): never
	error(`{STATIC_PREFIX}[code={code}]`, 0)
end

local function requireData(value: unknown): ControllerData
	if type(value) ~= "table" then
		staticError("INVALID_CONTEXT")
	end
	local data = DATA[value :: any]
	if data == nil then
		staticError("INVALID_CONTEXT")
	end
	return data
end

local function isSuccess(value: unknown): boolean
	return type(value) == "table" and rawget(value :: any, "ok") == true and rawget(value :: any, "value") ~= nil
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and value % 1 == 0 and value ~= 0 and math.abs(value) <= 9_007_199_254_740_991
end

local function validateRequestEndpoint(value: unknown, expectedName: string): boolean
	if type(value) ~= "table" then
		return false
	end
	local endpoint = value :: any
	local definition = endpoint.definition
	return type(definition) == "table"
		and definition.name == expectedName
		and definition.direction == "ClientToServer"
		and definition.kind == "Request"
		and definition.response == "Required"
		and type(endpoint.connectResponse) == "function"
		and type(endpoint.fire) == "function"
end

local function validateEventEndpoint(value: unknown, expectedName: string): boolean
	if type(value) ~= "table" then
		return false
	end
	local endpoint = value :: any
	local definition = endpoint.definition
	return type(definition) == "table"
		and definition.name == expectedName
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
	local tracker = dependencies.tracker
	local view = dependencies.view
	local input = dependencies.input
	if
		not validUserId(dependencies.localUserId)
		or type(tracker) ~= "table"
		or type(tracker.register) ~= "function"
		or type(tracker.buildRequest) ~= "function"
		or type(tracker.handleResponse) ~= "function"
		or type(tracker.cancel) ~= "function"
		or type(tracker.clear) ~= "function"
		or type(view) ~= "table"
		or type(view.render) ~= "function"
		or type(view.syncWorld) ~= "function"
		or type(view.playAttackEffect) ~= "function"
		or type(view.getMetrics) ~= "function"
		or type(view.cleanup) ~= "function"
		or type(input) ~= "table"
		or type(input.setContext) ~= "function"
		or type(input.getHints) ~= "function"
		or type(input.getMetrics) ~= "function"
		or type(input.cleanup) ~= "function"
		or type(dependencies.connectWorldPointer) ~= "function"
		or type(dependencies.connectRenderStep) ~= "function"
		or type(dependencies.now) ~= "function"
		or type(dependencies.getPointerPosition) ~= "function"
		or type(dependencies.getViewportSize) ~= "function"
		or type(dependencies.raycastPlacement) ~= "function"
		or type(dependencies.pickTower) ~= "function"
		or type(dependencies.focusOverview) ~= "function"
		or type(dependencies.focusBase) ~= "function"
		or type(dependencies.focusSpectatorTarget) ~= "function"
		or type(dependencies.restoreCamera) ~= "function"
		or type(dependencies.applySettings) ~= "function"
		or type(dependencies.newTransactionId) ~= "function"
	then
		return false
	end
	for _, spec in REQUEST_SPECS do
		if not validateRequestEndpoint(dependencies[spec.field], spec.endpoint) then
			return false
		end
	end
	return validateEventEndpoint(dependencies.replicationEvent, PlayableMatchProtocol.ENDPOINTS.REPLICATION)
		and validateEventEndpoint(dependencies.attackEvent, PlayableMatchProtocol.ENDPOINTS.ATTACK_EVENT)
		and validateEventEndpoint(dependencies.travelReplicationEvent, MatchTravelProtocol.ENDPOINTS.REPLICATION)
end

local function addConnection(data: ControllerData, value: unknown): boolean
	if typeof(value) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, value :: RBXScriptConnection)
	return true
end

local function endpointFor(data: ControllerData, endpointName: string): RequestEndpoint?
	local dependencies = data.dependencies
	if dependencies == nil then
		return nil
	end
	for _, spec in REQUEST_SPECS do
		if spec.endpoint == endpointName then
			return (dependencies :: any)[spec.field] :: RequestEndpoint
		end
	end
	return nil
end

local function cancelGet(data: ControllerData)
	local pending = data.getPending
	data.getPending = nil
	if pending ~= nil and data.dependencies ~= nil then
		pcall(function()
			(data.dependencies :: Dependencies).tracker:cancel(pending.pending)
		end)
	end
end

local function cancelAction(data: ControllerData)
	local pending = data.actionPending
	data.actionPending = nil
	if pending ~= nil and data.dependencies ~= nil then
		pcall(function()
			(data.dependencies :: Dependencies).tracker:cancel(pending.pending)
		end)
	end
end

local function cancelTravelGet(data: ControllerData)
	local pending = data.travelGetPending
	data.travelGetPending = nil
	if pending ~= nil and data.dependencies ~= nil then
		pcall(function()
			(data.dependencies :: Dependencies).tracker:cancel(pending.pending)
		end)
	end
end

local function cancelTravelMutation(data: ControllerData)
	local pending = data.travelMutationPending
	data.travelMutationPending = nil
	if pending ~= nil and data.dependencies ~= nil then
		pcall(function()
			(data.dependencies :: Dependencies).tracker:cancel(pending.pending)
		end)
	end
end

local function setFeedback(data: ControllerData, code: string?)
	data.feedbackCode = code
	data.feedbackExpiresAt = if code == nil then 0 else (data.dependencies :: Dependencies).now() + FEEDBACK_SECONDS
end

local function retireMatch(data: ControllerData, matchId: string)
	if data.retiredMatchIds[matchId] then
		return
	end
	if #data.retiredMatchRing >= RETIRED_MATCH_LIMIT then
		local evicted = table.remove(data.retiredMatchRing, 1)
		data.retiredMatchIds[evicted] = nil
	end
	table.insert(data.retiredMatchRing, matchId)
	data.retiredMatchIds[matchId] = true
end

local function findTower(
	snapshot: PlayableMatchProtocol.Snapshot,
	runtimeTowerId: number?
): PlayableMatchProtocol.TowerSnapshot?
	if runtimeTowerId == nil then
		return nil
	end
	for _, tower in snapshot.towers do
		if tower.runtimeTowerId == runtimeTowerId then
			return tower
		end
	end
	return nil
end

local function findOption(snapshot: PlayableMatchProtocol.Snapshot, slot: number?): PlayableMatchProtocol.TowerOption?
	if slot == nil then
		return nil
	end
	return snapshot.towerOptions[slot]
end

local function findOptionForTower(
	snapshot: PlayableMatchProtocol.Snapshot,
	towerId: string
): PlayableMatchProtocol.TowerOption?
	for _, option in snapshot.towerOptions do
		if option.towerId == towerId then
			return option
		end
	end
	return nil
end

local function nextTargetMode(current: PlayableMatchProtocol.TargetMode): PlayableMatchProtocol.TargetMode
	for index, mode in PlayableMatchProtocol.TARGET_MODES do
		if mode == current then
			return PlayableMatchProtocol.TARGET_MODES[(index % #PlayableMatchProtocol.TARGET_MODES) + 1]
		end
	end
	return "First"
end

local function desiredInputContext(data: ControllerData): PlayableInputMap.Context
	local snapshot = data.snapshot
	if snapshot == nil then
		return "Match"
	elseif snapshot.state == "Ready" then
		return "Ready"
	elseif snapshot.state == "Results" then
		return "Results"
	elseif data.selectedTowerId ~= nil then
		return "Tower"
	elseif data.selectedSlot ~= nil then
		return "Placement"
	end
	return "Match"
end

local function inputFamily(data: ControllerData): PlayableInputMap.InputFamily
	local dependencies = data.dependencies :: Dependencies
	local called, metrics = pcall(function()
		return dependencies.input:getMetrics()
	end)
	if called and type(metrics) == "table" then
		local preferred = (metrics :: any).preferredInput
		if preferred == "Desktop" or preferred == "Touch" or preferred == "Gamepad" then
			return preferred
		end
	end
	return "Desktop"
end

local function setInputContext(data: ControllerData): string?
	local dependencies = data.dependencies :: Dependencies
	local context = desiredInputContext(data)
	pcall(function()
		dependencies.input:setContext(context)
	end)
	local called, resultValue = pcall(function()
		return dependencies.input:getHints()
	end)
	if called and isSuccess(resultValue) and type((resultValue :: any).value) == "string" then
		return (resultValue :: any).value
	end
	return nil
end

local function resultSummary(snapshot: PlayableMatchProtocol.Snapshot): string
	local stats = snapshot.stats
	local context = string.sub(`{snapshot.mapDisplayName} • {snapshot.difficultyDisplayName}`, 1, 72)
	if snapshot.modeKind == "Endless" then
		return `{context} • Endless • {stats.wavesCompleted} waves cleared • Base {stats.baseHealthRemaining} HP • Damage {stats.damageDealt}`
	end
	local totalWaves = snapshot.totalWaves or stats.wavesCompleted
	if snapshot.result == "Victory" then
		return `{context} • All {totalWaves} waves cleared • Base {stats.baseHealthRemaining} HP • Damage {stats.damageDealt}`
	end
	return `{context} • Base overrun after {stats.wavesCompleted}/{totalWaves} waves • Damage {stats.damageDealt}`
end

local function compatibleTravelSnapshot(
	playable: PlayableMatchProtocol.Snapshot,
	travel: MatchTravelProtocol.Snapshot?
): MatchTravelProtocol.Snapshot?
	if travel == nil or travel.matchId ~= playable.matchId or travel.viewerRole ~= playable.viewerRole then
		return nil
	end
	return travel
end

local function resultRewardView(snapshot: PlayableMatchProtocol.Snapshot): any
	local reward = snapshot.reward
	if reward ~= nil then
		return {
			status = reward.status,
			persistentGoldAwarded = reward.persistentGoldAwarded,
			firstClearBonus = reward.firstClearBonus,
			battleCashEarned = reward.battleCashEarned,
			battleCashSpent = reward.battleCashSpent,
			reason = reward.reason,
		}
	end
	if snapshot.viewerRole == "Spectator" then
		return {
			status = "Ineligible",
			persistentGoldAwarded = 0,
			firstClearBonus = 0,
			battleCashEarned = 0,
			battleCashSpent = 0,
			reason = "Spectators do not earn participation rewards.",
		}
	end
	if not snapshot.rewarding then
		return {
			status = "Ineligible",
			persistentGoldAwarded = 0,
			firstClearBonus = 0,
			battleCashEarned = snapshot.stats.battleCashEarned,
			battleCashSpent = snapshot.stats.battleCashSpent,
			reason = "Direct local matches are non-rewarding.",
		}
	end
	return {
		status = "Pending",
		persistentGoldAwarded = 0,
		firstClearBonus = 0,
		battleCashEarned = snapshot.stats.battleCashEarned,
		battleCashSpent = snapshot.stats.battleCashSpent,
		reason = "Waiting for the durable profile claim.",
	}
end

local function travelView(data: ControllerData, snapshot: PlayableMatchProtocol.Snapshot): any
	local travel = compatibleTravelSnapshot(snapshot, data.travelSnapshot)
	if travel == nil then
		return nil
	end
	local rematch = travel.rematch
	local localChoice: MatchTravelProtocol.VoteChoice? = nil
	if rematch ~= nil then
		for _, vote in rematch.votes do
			if vote.userId == (data.dependencies :: Dependencies).localUserId then
				localChoice = vote.choice
				break
			end
		end
	end
	return {
		returnStatus = travel.returnStatus,
		failure = travel.publicFailure,
		canReturn = travel.returnStatus ~= "Pending"
			and travel.returnStatus ~= "Teleporting"
			and (rematch == nil or (rematch.state ~= "Starting" and rematch.state ~= "Approved"))
			and data.travelMutationPending == nil,
		rematchState = if rematch == nil then nil else rematch.state,
		rematchStatus = if rematch == nil
			then nil
			else `{rematch.state} • {#rematch.votes} connected participant votes`,
		canApprove = snapshot.viewerRole == "Participant"
			and rematch ~= nil
			and rematch.state == "Pending"
			and localChoice == "Pending"
			and data.travelMutationPending == nil,
		canDecline = snapshot.viewerRole == "Participant"
			and rematch ~= nil
			and rematch.state == "Pending"
			and localChoice == "Pending"
			and data.travelMutationPending == nil,
	}
end

local function readViewport(dependencies: Dependencies): Vector2?
	local viewportRead, viewportValue = pcall(dependencies.getViewportSize)
	if viewportRead and typeof(viewportValue) == "Vector2" then
		local candidate = viewportValue :: Vector2
		if candidate.X >= 240 and candidate.X < math.huge and candidate.Y >= 320 and candidate.Y < math.huge then
			return candidate
		end
	end
	return nil
end

local function renderSnapshot(data: ControllerData): boolean
	if data.state ~= "Started" or not data.callbacksEnabled then
		return false
	end
	local snapshot = data.snapshot
	if snapshot == nil then
		data.renderPending = true
		local dependencies = data.dependencies :: Dependencies
		local hint = setInputContext(data)
		local family = inputFamily(data)
		local viewport = readViewport(dependencies)
		local loadingHotbar = table.create(PlayableMatchProtocol.MAX_TOWER_OPTIONS)
		for slot = 1, PlayableMatchProtocol.MAX_TOWER_OPTIONS do
			loadingHotbar[slot] = {
				slot = slot,
				displayName = "Loading",
				cost = 0,
				available = false,
				selected = false,
				reason = "WAITING",
			}
		end
		local rendered = dependencies.view:render({
			matchId = "match:loading-local",
			revision = 0,
			viewerRole = "Participant",
			state = "Loading",
			inputFamily = family,
			wave = {
				current = 0,
				total = 1,
				enemiesRemaining = 0,
				status = "Connecting",
				modeKind = "Finite",
				bossKind = "None",
			},
			base = { health = 0, maxHealth = 1 },
			battleCash = 0,
			hotbar = loadingHotbar,
			feedback = if data.feedbackCode == nil then nil else { code = data.feedbackCode },
			inputHint = if data.feedbackCode == nil then "Connecting to the authoritative match." else hint,
			viewport = viewport,
			uiScale = 1,
			reducedMotion = false,
			lowEffects = false,
		})
		if not isSuccess(rendered) then
			return false
		end
		data.lastRenderedViewport = viewport
		local worldResult = dependencies.view:syncWorld({ towers = {}, enemies = {} })
		if not isSuccess(worldResult) then
			return false
		end
		data.renderCount += 1
		data.renderPending = false
		return true
	end
	data.renderPending = true
	local dependencies = data.dependencies :: Dependencies
	if snapshot.state == "Results" then
		-- Runtime towers remain available for the final statistics snapshot, but
		-- Results is an exclusive presentation state. Retire transient gameplay
		-- selection before building the view model so a selected tower cannot
		-- prevent the authoritative result and replay controls from rendering.
		data.selectedTowerId = nil
		data.selectedSlot = nil
		data.touchPlacementPosition = nil
	else
		if data.selectedTowerId ~= nil and findTower(snapshot, data.selectedTowerId) == nil then
			data.selectedTowerId = nil
		end
		if data.selectedSlot ~= nil and findOption(snapshot, data.selectedSlot) == nil then
			data.selectedSlot = nil
			data.touchPlacementPosition = nil
		end
	end
	local hint = setInputContext(data)
	local family = inputFamily(data)
	local viewport = readViewport(dependencies)

	local hotbar = table.create(#snapshot.towerOptions)
	for slot, option in snapshot.towerOptions do
		local available = snapshot.state == "Playing" and snapshot.viewerRole == "Participant"
		local reason: string? = nil
		if not available then
			reason = "WAITING"
		elseif option.placementCost > snapshot.battleCash then
			available = false
			reason = "NEED CASH"
		end
		hotbar[slot] = {
			slot = slot,
			displayName = option.displayName,
			description = option.description,
			cost = option.placementCost,
			available = available and data.actionPending == nil,
			selected = data.selectedSlot == slot,
			reason = reason,
		}
	end

	local selectedTower = findTower(snapshot, data.selectedTowerId)
	local selection: any = nil
	if selectedTower ~= nil then
		local selectedOption = findOptionForTower(snapshot, selectedTower.towerId)
		local owner = selectedTower.ownerUserId == dependencies.localUserId
		local actionsAvailable = snapshot.state == "Playing"
			and snapshot.viewerRole == "Participant"
			and data.actionPending == nil
			and owner
		selection = {
			towerId = `tower-runtime:{selectedTower.runtimeTowerId}`,
			revision = selectedTower.revision,
			displayName = selectedTower.displayName,
			description = if selectedOption == nil then nil else selectedOption.description,
			isOwner = owner,
			level = selectedTower.level,
			maxLevel = math.max(3, selectedTower.level),
			targetMode = selectedTower.targetMode,
			damage = selectedTower.damage,
			range = selectedTower.rangeStuds,
			cooldownSeconds = selectedTower.cooldownSeconds,
			upgradeCost = if selectedTower.upgradeCost > 0 then selectedTower.upgradeCost else nil,
			sellValue = selectedTower.sellValue,
			canUpgrade = actionsAvailable and selectedTower.upgradeCost > 0,
			canRetarget = actionsAvailable,
			canSell = actionsAvailable,
		}
	end

	local state: PlayableMatchView.MatchState = if snapshot.state == "Ready"
		then "ReadyCheck"
		elseif snapshot.state == "Results" then "Results"
		elseif snapshot.wavePhase == "Intermission" then "PreWave"
		else "WaveActive"
	local ready: any = nil
	if snapshot.state == "Ready" and snapshot.viewerRole == "Participant" then
		ready = {
			enabled = data.actionPending == nil,
			countdownSeconds = nil,
			status = string.sub(
				`{snapshot.mapDisplayName} • {snapshot.difficultyDisplayName}\n{snapshot.participants.readyCount}/{snapshot.participants.participantCount} players ready`,
				1,
				96
			),
		}
	end
	local resultState: any = nil
	if snapshot.state == "Results" then
		local rewardView = resultRewardView(snapshot)
		resultState = {
			kind = snapshot.result,
			summary = resultSummary(snapshot),
			canReplay = snapshot.viewerRole == "Participant" and not snapshot.rewarding and data.actionPending == nil,
			status = if data.actionPending ~= nil then "Waiting for server confirmation." else nil,
			rewardStatus = rewardView.status,
			persistentGoldAwarded = rewardView.persistentGoldAwarded,
			firstClearBonus = rewardView.firstClearBonus,
			battleCashEarned = rewardView.battleCashEarned,
			battleCashSpent = rewardView.battleCashSpent,
			rewardReason = rewardView.reason,
		}
	end
	local renderResult = dependencies.view:render({
		matchId = snapshot.matchId,
		revision = snapshot.revision,
		viewerRole = snapshot.viewerRole,
		state = state,
		inputFamily = family,
		wave = {
			current = snapshot.waveNumber,
			total = snapshot.totalWaves,
			enemiesRemaining = snapshot.enemiesAlive,
			status = snapshot.wavePhase,
			modeKind = snapshot.modeKind or "Finite",
			bossKind = snapshot.bossKind or "None",
			boss = snapshot.boss,
		},
		base = { health = snapshot.baseHealth, maxHealth = snapshot.maximumBaseHealth },
		battleCash = snapshot.battleCash,
		hotbar = hotbar,
		tutorialStep = snapshot.tutorialStep,
		ready = ready,
		selection = selection,
		feedback = if data.feedbackCode == nil then nil else { code = data.feedbackCode },
		result = resultState,
		travel = travelView(data, snapshot),
		placement = if family == "Touch"
				and snapshot.state == "Playing"
				and data.selectedSlot ~= nil
			then {
				positionSelected = data.touchPlacementPosition ~= nil,
				rotationDegrees = data.rotationDegrees,
				controlsEnabled = data.actionPending == nil,
			}
			else nil,
		inputHint = hint,
		viewport = viewport,
		uiScale = snapshot.settings.uiScale,
		reducedMotion = snapshot.settings.reducedMotionEnabled,
		lowEffects = snapshot.settings.lowDetailEnabled,
		enemyHealthBars = snapshot.settings.enemyHealthBarsEnabled,
		towerRange = snapshot.settings.towerRangeEnabled,
	})
	if not isSuccess(renderResult) then
		return false
	end
	data.lastRenderedViewport = viewport

	local towerVisuals = table.create(#snapshot.towers)
	for index, tower in snapshot.towers do
		towerVisuals[index] = {
			id = `tower-runtime:{tower.runtimeTowerId}`,
			definitionId = tower.towerId,
			position = tower.position,
			rotationDegrees = tower.rotationDegrees,
			selected = tower.runtimeTowerId == data.selectedTowerId,
			level = tower.level,
			range = tower.rangeStuds,
		}
	end
	local enemyVisuals = table.create(#snapshot.enemies)
	for index, enemy in snapshot.enemies do
		enemyVisuals[index] = {
			id = `enemy-runtime:{enemy.runtimeEnemyId}`,
			definitionId = enemy.enemyId,
			position = enemy.position,
			health = enemy.currentHealth,
			maxHealth = enemy.maximumHealth,
		}
	end
	local worldResult = dependencies.view:syncWorld({ towers = towerVisuals, enemies = enemyVisuals })
	if not isSuccess(worldResult) then
		return false
	end
	data.renderCount += 1
	data.renderPending = false
	return true
end

local function resetForReplacement(data: ControllerData, previousMatchId: string)
	retireMatch(data, previousMatchId)
	cancelAction(data)
	data.selectedSlot = nil
	data.selectedTowerId = nil
	data.touchPlacementPosition = nil
	data.rotationDegrees = 0
	data.travelSnapshot = nil
	cancelTravelGet(data)
	cancelTravelMutation(data)
	data.spectatorTargetId = nil
	data.overviewMatchId = nil
	data.feedbackCode = nil
	data.feedbackExpiresAt = 0
	data.recoveryQueued = false
	data.matchGeneration += 1
end

local function focusOverviewIfNeeded(data: ControllerData, matchId: string)
	if data.overviewMatchId == matchId then
		return
	end
	local focused, resultValue = pcall((data.dependencies :: Dependencies).focusOverview)
	if focused and resultValue == true then
		data.overviewMatchId = matchId
	end
end

local function applySnapshot(
	data: ControllerData,
	snapshot: PlayableMatchProtocol.Snapshot,
	allowReplacement: boolean
): boolean
	local current = data.snapshot
	if current ~= nil then
		if snapshot.matchId == current.matchId then
			if snapshot.revision < current.revision then
				return false
			elseif snapshot.revision == current.revision then
				focusOverviewIfNeeded(data, snapshot.matchId)
				data.lastSnapshotAt = (data.dependencies :: Dependencies).now()
				data.recoveryQueued = false
				if data.renderPending then
					renderSnapshot(data)
				end
				return true
			end
		elseif data.retiredMatchIds[snapshot.matchId] then
			return false
		elseif not allowReplacement and not (current.state == "Results" and snapshot.state == "Ready") then
			return false
		else
			resetForReplacement(data, current.matchId)
		end
	end
	data.snapshot = snapshot
	focusOverviewIfNeeded(data, snapshot.matchId)
	if snapshot.viewerRole ~= "Spectator" then
		data.spectatorTargetId = nil
	elseif data.spectatorTargetId ~= nil then
		local found = false
		for _, tower in snapshot.towers do
			found = found or data.spectatorTargetId == `tower:{tower.runtimeTowerId}`
		end
		for _, enemy in snapshot.enemies do
			found = found or data.spectatorTargetId == `enemy:{enemy.runtimeEnemyId}`
		end
		if not found then
			data.spectatorTargetId = nil
		end
	end
	pcall((data.dependencies :: Dependencies).applySettings, snapshot.settings)
	data.lastSnapshotAt = (data.dependencies :: Dependencies).now()
	data.acceptedSnapshotCount += 1
	data.renderPending = true
	if not renderSnapshot(data) then
		data.rejectedInputCount += 1
	end
	return true
end

local function issueGet(data: ControllerData, recovery: boolean): boolean
	if data.state ~= "Started" or not data.callbacksEnabled or data.getPending ~= nil then
		return false
	end
	local dependencies = data.dependencies :: Dependencies
	local built = dependencies.tracker:buildRequest(PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT, {})
	if not isSuccess(built) then
		return false
	end
	local request = (built :: any).value
	if not RequestProtocol.isPending(request.pending) then
		return false
	end
	data.getPending = {
		pending = request.pending,
		isRecovery = recovery,
		issuedAt = dependencies.now(),
	}
	data.requestCount += 1
	data.getRequestCount += 1
	if recovery then
		data.recoveryRequestCount += 1
	end
	if not pcall(dependencies.getSnapshot.fire, request.envelope) then
		cancelGet(data)
		return false
	end
	return true
end

local function requestRecovery(data: ControllerData)
	if data.state ~= "Started" or not data.callbacksEnabled then
		return
	end
	if data.getPending ~= nil then
		data.recoveryQueued = true
		return
	end
	data.recoveryQueued = false
	issueGet(data, true)
end

local function applyTravelSnapshot(data: ControllerData, snapshot: MatchTravelProtocol.Snapshot): boolean
	local playable = data.snapshot
	if playable ~= nil and (snapshot.matchId ~= playable.matchId or snapshot.viewerRole ~= playable.viewerRole) then
		return false
	end
	local current = data.travelSnapshot
	if current ~= nil then
		if snapshot.matchId ~= current.matchId or snapshot.revision < current.revision then
			return false
		elseif snapshot.revision == current.revision then
			return true
		end
	end
	data.travelSnapshot = snapshot
	renderSnapshot(data)
	return true
end

local function issueTravelGet(data: ControllerData): boolean
	if data.state ~= "Started" or not data.callbacksEnabled or data.travelGetPending ~= nil then
		return false
	end
	local dependencies = data.dependencies :: Dependencies
	local built = dependencies.tracker:buildRequest(MatchTravelProtocol.ENDPOINTS.GET_SNAPSHOT, {})
	if not isSuccess(built) then
		return false
	end
	local request = (built :: any).value
	if not RequestProtocol.isPending(request.pending) then
		return false
	end
	data.travelGetPending = { pending = request.pending, issuedAt = dependencies.now() }
	data.requestCount += 1
	if not pcall(dependencies.getTravelSnapshot.fire, request.envelope) then
		cancelTravelGet(data)
		return false
	end
	return true
end

local function issueTravelMutation(data: ControllerData, kind: TravelMutationKind, approve: boolean?): boolean
	local snapshot = data.snapshot
	local travel = if snapshot == nil then nil else compatibleTravelSnapshot(snapshot, data.travelSnapshot)
	if snapshot == nil or travel == nil or data.travelMutationPending ~= nil then
		setFeedback(data, "TRAVEL_UNAVAILABLE")
		renderSnapshot(data)
		return false
	end
	local endpointName = if kind == "Return"
		then MatchTravelProtocol.ENDPOINTS.REQUEST_RETURN
		else MatchTravelProtocol.ENDPOINTS.VOTE_REMATCH
	local endpoint = endpointFor(data, endpointName)
	if endpoint == nil then
		return false
	end
	local dependencies = data.dependencies :: Dependencies
	local transactionId = dependencies.newTransactionId()
	local payload: any = {
		transactionId = transactionId,
		matchId = snapshot.matchId,
		observedRevision = travel.revision,
	}
	local rematch = travel.rematch
	if kind == "Return" then
		if
			travel.returnStatus == "Pending"
			or travel.returnStatus == "Teleporting"
			or (rematch ~= nil and (rematch.state == "Starting" or rematch.state == "Approved"))
		then
			setFeedback(data, "RETURN_UNAVAILABLE")
			renderSnapshot(data)
			return false
		end
	else
		if snapshot.viewerRole ~= "Participant" or rematch == nil or rematch.state ~= "Pending" then
			setFeedback(data, "REMATCH_UNAVAILABLE")
			renderSnapshot(data)
			return false
		end
		payload.approve = approve == true
		payload.observedRematchRevision = rematch.revision
	end
	local built = dependencies.tracker:buildRequest(endpointName, payload)
	if not isSuccess(built) then
		setFeedback(data, "REQUEST_REJECTED")
		renderSnapshot(data)
		return false
	end
	local request = (built :: any).value
	if not RequestProtocol.isPending(request.pending) then
		return false
	end
	data.travelMutationPending = {
		pending = request.pending,
		definition = endpoint.definition,
		kind = kind,
		matchId = snapshot.matchId,
		transactionId = transactionId,
		issuedAt = dependencies.now(),
	}
	data.requestCount += 1
	setFeedback(data, if kind == "Return" then "RETURN_PENDING" else "REMATCH_PENDING")
	renderSnapshot(data)
	if not pcall(endpoint.fire, request.envelope) then
		cancelTravelMutation(data)
		setFeedback(data, "SERVER_UNAVAILABLE")
		renderSnapshot(data)
		return false
	end
	return true
end

local function issueAction(
	data: ControllerData,
	kind: ActionRequestKind,
	payload: unknown,
	definitionOverride: RemoteRegistry.Definition?
): boolean
	local snapshot = data.snapshot
	if snapshot == nil or data.actionPending ~= nil then
		return false
	end
	local endpointName = ACTION_ENDPOINTS[kind]
	local endpoint = endpointFor(data, endpointName)
	if endpoint == nil or (definitionOverride ~= nil and endpoint.definition ~= definitionOverride) then
		return false
	end
	local dependencies = data.dependencies :: Dependencies
	local built = dependencies.tracker:buildRequest(endpointName, payload)
	if not isSuccess(built) then
		setFeedback(data, "REQUEST_REJECTED")
		return false
	end
	local request = (built :: any).value
	if not RequestProtocol.isPending(request.pending) then
		setFeedback(data, "REQUEST_REJECTED")
		return false
	end
	data.actionPending = {
		pending = request.pending,
		definition = endpoint.definition,
		kind = kind,
		matchId = snapshot.matchId,
		issuedAt = dependencies.now(),
	}
	data.requestCount += 1
	data.actionRequestCount += 1
	setFeedback(data, "REQUEST_PENDING")
	renderSnapshot(data)
	if not pcall(endpoint.fire, request.envelope) then
		cancelAction(data)
		setFeedback(data, "SERVER_UNAVAILABLE")
		requestRecovery(data)
		renderSnapshot(data)
		return false
	end
	return true
end

local function placementScreenPosition(data: ControllerData, action: PlayableInputMap.SemanticAction): Vector2?
	if action.screenPosition ~= nil then
		return action.screenPosition
	end
	local dependencies = data.dependencies :: Dependencies
	local viewport: Vector2? = nil
	local viewportRead, viewportValue = pcall(dependencies.getViewportSize)
	if viewportRead and typeof(viewportValue) == "Vector2" then
		local candidate = viewportValue :: Vector2
		if candidate.X > 0 and candidate.X < math.huge and candidate.Y > 0 and candidate.Y < math.huge then
			viewport = candidate
		end
	end
	if action.source == "Gamepad" and viewport ~= nil then
		return (viewport :: Vector2) * 0.5
	end
	local called, pointer = pcall(dependencies.getPointerPosition)
	if called and typeof(pointer) == "Vector2" then
		local position = pointer :: Vector2
		if
			viewport == nil
			or (position.X >= 0 and position.X <= viewport.X and position.Y >= 0 and position.Y <= viewport.Y)
		then
			return position
		end
	end
	return if viewport == nil then nil else (viewport :: Vector2) * 0.5
end

local function submitPlacement(data: ControllerData, action: PlayableInputMap.SemanticAction): boolean
	local snapshot = data.snapshot
	local option = if snapshot == nil then nil else findOption(snapshot, data.selectedSlot)
	if snapshot == nil or snapshot.state ~= "Playing" or option == nil then
		setFeedback(data, "MATCH_NOT_ACTIVE")
		renderSnapshot(data)
		return false
	end
	local position: Vector3? = nil
	if action.source == "Touch" then
		position = data.touchPlacementPosition
	else
		local screenPosition = placementScreenPosition(data, action)
		if screenPosition ~= nil then
			local dependencies = data.dependencies :: Dependencies
			local raycasted, raycastPosition = pcall(dependencies.raycastPlacement, screenPosition)
			if raycasted and typeof(raycastPosition) == "Vector3" then
				position = raycastPosition :: Vector3
			end
		end
	end
	if position == nil then
		setFeedback(data, "INVALID_POSITION")
		renderSnapshot(data)
		return false
	end
	return issueAction(data, "Placement", {
		matchId = snapshot.matchId,
		loadoutRevision = snapshot.loadoutRevision,
		slot = option.slot,
		towerId = option.towerId,
		position = position :: Vector3,
		rotationDegrees = data.rotationDegrees,
	}, nil)
end

local function selectHotbar(data: ControllerData, slot: number?): boolean
	local snapshot = data.snapshot
	local option = if snapshot == nil then nil else findOption(snapshot, slot)
	if
		snapshot == nil
		or snapshot.state ~= "Playing"
		or option == nil
		or option.placementCost > snapshot.battleCash
		or data.actionPending ~= nil
	then
		setFeedback(
			data,
			if option ~= nil
					and snapshot ~= nil
					and option.placementCost > snapshot.battleCash
				then "INSUFFICIENT_CASH"
				else "MATCH_NOT_ACTIVE"
		)
		renderSnapshot(data)
		return false
	end
	data.selectedSlot = slot
	data.selectedTowerId = nil
	data.touchPlacementPosition = nil
	setFeedback(data, nil)
	renderSnapshot(data)
	return true
end

local function cycleHotbar(data: ControllerData, direction: number?): boolean
	if direction ~= -1 and direction ~= 1 then
		return false
	end
	local snapshot = data.snapshot
	local optionCount = if snapshot == nil then 0 else #snapshot.towerOptions
	if optionCount == 0 then
		return false
	end
	local current = data.selectedSlot or (if direction == 1 then 0 else optionCount + 1)
	for offset = 1, optionCount do
		local slot = ((current - 1 + direction * offset) % optionCount) + 1
		local option = if snapshot == nil then nil else findOption(snapshot, slot)
		if snapshot ~= nil and option ~= nil and option.placementCost <= snapshot.battleCash then
			return selectHotbar(data, slot)
		end
	end
	setFeedback(data, "INSUFFICIENT_CASH")
	renderSnapshot(data)
	return false
end

local function cycleTower(data: ControllerData, direction: number?): boolean
	local snapshot = data.snapshot
	if direction ~= -1 and direction ~= 1 then
		return false
	end
	if snapshot == nil or snapshot.state ~= "Playing" or #snapshot.towers == 0 then
		setFeedback(data, "TOWER_NOT_FOUND")
		renderSnapshot(data)
		return false
	end
	local runtimeTowerIds = {}
	local localUserId = (data.dependencies :: Dependencies).localUserId
	for _, tower in snapshot.towers do
		if tower.ownerUserId == localUserId then
			table.insert(runtimeTowerIds, tower.runtimeTowerId)
		end
	end
	if #runtimeTowerIds == 0 then
		for _, tower in snapshot.towers do
			table.insert(runtimeTowerIds, tower.runtimeTowerId)
		end
	end
	table.sort(runtimeTowerIds)
	local currentIndex: number? = nil
	for index, runtimeTowerId in runtimeTowerIds do
		if runtimeTowerId == data.selectedTowerId then
			currentIndex = index
			break
		end
	end
	local nextIndex = if currentIndex == nil
		then (if direction == 1 then 1 else #runtimeTowerIds)
		else (((currentIndex :: number) - 1 + direction) % #runtimeTowerIds) + 1
	data.selectedSlot = nil
	data.selectedTowerId = runtimeTowerIds[nextIndex]
	data.touchPlacementPosition = nil
	setFeedback(data, nil)
	renderSnapshot(data)
	return true
end

local function submitTowerAction(data: ControllerData, kind: "Upgrade" | "Sell" | "Retarget"): boolean
	local snapshot = data.snapshot
	local tower = if snapshot == nil then nil else findTower(snapshot, data.selectedTowerId)
	if snapshot == nil or snapshot.state ~= "Playing" or tower == nil then
		setFeedback(data, "TOWER_NOT_FOUND")
		renderSnapshot(data)
		return false
	end
	if tower.ownerUserId ~= (data.dependencies :: Dependencies).localUserId then
		setFeedback(data, "NOT_OWNER")
		renderSnapshot(data)
		return false
	end
	if kind == "Upgrade" and tower.upgradeCost <= 0 then
		setFeedback(data, "REQUEST_REJECTED")
		renderSnapshot(data)
		return false
	end
	local payload: any = {
		matchId = snapshot.matchId,
		runtimeTowerId = tower.runtimeTowerId,
		towerRevision = tower.revision,
	}
	if kind == "Retarget" then
		payload.targetMode = nextTargetMode(tower.targetMode)
	end
	return issueAction(data, kind, payload, nil)
end

local function cycleSpectatorTarget(data: ControllerData, direction: number): boolean
	local snapshot = data.snapshot
	if snapshot == nil or snapshot.viewerRole ~= "Spectator" or (direction ~= -1 and direction ~= 1) then
		return false
	end
	local targets = {}
	for _, tower in snapshot.towers do
		table.insert(targets, { id = `tower:{tower.runtimeTowerId}`, position = tower.position })
	end
	for _, enemy in snapshot.enemies do
		table.insert(targets, { id = `enemy:{enemy.runtimeEnemyId}`, position = enemy.position })
	end
	table.sort(targets, function(left, right)
		return left.id < right.id
	end)
	if #targets == 0 then
		data.spectatorTargetId = nil
		setFeedback(data, "SPECTATOR_TARGET_UNAVAILABLE")
		renderSnapshot(data)
		return false
	end
	local currentIndex: number? = nil
	for index, target in targets do
		if target.id == data.spectatorTargetId then
			currentIndex = index
			break
		end
	end
	local nextIndex = if currentIndex == nil
		then (if direction == 1 then 1 else #targets)
		else (((currentIndex :: number) - 1 + direction) % #targets) + 1
	local target = targets[nextIndex]
	local focused, resultValue = pcall((data.dependencies :: Dependencies).focusSpectatorTarget, target.position)
	if not focused or resultValue ~= true then
		setFeedback(data, "SPECTATOR_TARGET_UNAVAILABLE")
		renderSnapshot(data)
		return false
	end
	data.spectatorTargetId = target.id
	setFeedback(data, nil)
	renderSnapshot(data)
	return true
end

local function onSemanticAction(data: ControllerData, value: unknown): boolean
	if data.state ~= "Started" or not data.callbacksEnabled or type(value) ~= "table" then
		return false
	end
	local action = value :: any
	local kind = action.kind
	local snapshot = data.snapshot
	if kind == "Return" then
		return issueTravelMutation(data, "Return", nil)
	elseif kind == "RematchApprove" then
		return issueTravelMutation(data, "Rematch", true)
	elseif kind == "RematchDecline" then
		return issueTravelMutation(data, "Rematch", false)
	elseif kind == "SpectatePrevious" then
		return cycleSpectatorTarget(data, -1)
	elseif kind == "SpectateNext" then
		return cycleSpectatorTarget(data, 1)
	elseif snapshot ~= nil and snapshot.viewerRole == "Spectator" and kind ~= "FocusBase" then
		setFeedback(data, "SPECTATOR_READ_ONLY")
		renderSnapshot(data)
		return false
	end
	if kind == "SelectHotbar" then
		return selectHotbar(data, action.slot)
	elseif kind == "CycleHotbar" then
		return cycleHotbar(data, action.direction)
	elseif kind == "CycleTower" then
		return cycleTower(data, action.direction)
	elseif kind == "Confirm" then
		return submitPlacement(data, action :: PlayableInputMap.SemanticAction)
	elseif kind == "Cancel" then
		local changed = data.selectedSlot ~= nil or data.selectedTowerId ~= nil
		data.selectedSlot = nil
		data.selectedTowerId = nil
		data.touchPlacementPosition = nil
		setFeedback(data, nil)
		renderSnapshot(data)
		return changed
	elseif kind == "Rotate" then
		if data.selectedSlot == nil then
			return false
		end
		data.rotationDegrees = ((data.rotationDegrees + ROTATION_STEP_DEGREES + 180) % 360) - 180
		renderSnapshot(data)
		return true
	elseif kind == "Upgrade" or kind == "Sell" or kind == "Retarget" then
		return submitTowerAction(data, kind)
	elseif kind == "Ready" then
		return snapshot ~= nil
			and snapshot.state == "Ready"
			and issueAction(data, "Ready", { matchId = snapshot.matchId }, nil)
	elseif kind == "Replay" then
		return snapshot ~= nil
			and snapshot.state == "Results"
			and snapshot.viewerRole == "Participant"
			and not snapshot.rewarding
			and issueAction(data, "Replay", { matchId = snapshot.matchId }, nil)
	elseif kind == "FocusBase" then
		local focused, resultValue = pcall((data.dependencies :: Dependencies).focusBase)
		if not focused or resultValue ~= true then
			setFeedback(data, "SERVER_UNAVAILABLE")
			renderSnapshot(data)
			return false
		end
		return true
	end
	data.rejectedInputCount += 1
	return false
end

local function onViewAction(data: ControllerData, value: PlayableMatchView.UiAction)
	local action: any = {
		kind = value.kind,
		source = value.source,
		slot = value.slot,
	}
	onSemanticAction(data, action)
end

local function onWorldPointer(data: ControllerData, positionValue: unknown, sourceValue: unknown)
	if
		data.state ~= "Started"
		or not data.callbacksEnabled
		or typeof(positionValue) ~= "Vector2"
		or (sourceValue ~= "Desktop" and sourceValue ~= "Touch" and sourceValue ~= "Gamepad")
	then
		return
	end
	local source = sourceValue :: PlayableInputMap.InputFamily
	if data.selectedSlot ~= nil then
		if source == "Touch" then
			local dependencies = data.dependencies :: Dependencies
			local raycasted, position = pcall(dependencies.raycastPlacement, positionValue :: Vector2)
			if raycasted and typeof(position) == "Vector3" then
				data.touchPlacementPosition = position :: Vector3
				setFeedback(data, "POSITION_SELECTED")
			else
				data.touchPlacementPosition = nil
				setFeedback(data, "INVALID_POSITION")
			end
			renderSnapshot(data)
		end
		return
	end
	local snapshot = data.snapshot
	if snapshot == nil or snapshot.state ~= "Playing" or snapshot.viewerRole ~= "Participant" then
		return
	end
	local picked, runtimeTowerId =
		pcall((data.dependencies :: Dependencies).pickTower, positionValue :: Vector2, snapshot.towers, source)
	if not picked or (runtimeTowerId ~= nil and type(runtimeTowerId) ~= "number") then
		data.rejectedInputCount += 1
		return
	end
	data.selectedTowerId = runtimeTowerId :: number?
	setFeedback(data, nil)
	renderSnapshot(data)
end

local function shouldRecoverPublic(code: RequestProtocol.PublicErrorCode): boolean
	return code == "STALE_REQUEST"
		or code == "DUPLICATE_REQUEST"
		or code == "NOT_AUTHORIZED"
		or code == "UNAVAILABLE"
		or code == "INTERNAL_ERROR"
end

local function onReplication(data: ControllerData, generation: number, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.state ~= "Started" or generation ~= data.callbackGeneration then
		return
	end
	local parsed = RequestProtocol.parseEvent(value, ...)
	if not parsed.ok then
		data.rejectedInputCount += 1
		requestRecovery(data)
		return
	end
	local validated = PlayableMatchProtocol.validateSnapshot(parsed.value.payload)
	if not validated.ok or not applySnapshot(data, validated.value, false) then
		if not validated.ok then
			data.rejectedInputCount += 1
			requestRecovery(data)
		end
	end
end

local function onTravelReplication(data: ControllerData, generation: number, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.state ~= "Started" or generation ~= data.callbackGeneration then
		return
	end
	local parsed = RequestProtocol.parseEvent(value, ...)
	if not parsed.ok then
		data.rejectedInputCount += 1
		return
	end
	local validated = MatchTravelProtocol.validateSnapshot(parsed.value.payload)
	if not validated.ok or not applyTravelSnapshot(data, validated.value) then
		data.rejectedInputCount += 1
	end
end

local function onAttack(data: ControllerData, generation: number, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.state ~= "Started" or generation ~= data.callbackGeneration then
		return
	end
	local parsed = RequestProtocol.parseEvent(value, ...)
	if not parsed.ok then
		data.rejectedInputCount += 1
		return
	end
	local validated = PlayableMatchProtocol.validateAttackEvent(parsed.value.payload)
	if not validated.ok or data.snapshot == nil or validated.value.matchId ~= data.snapshot.matchId then
		data.rejectedInputCount += 1
		return
	end
	local event = validated.value
	local settings = data.snapshot.settings
	if not settings.otherPlayerEffectsEnabled then
		local tower = findTower(data.snapshot, event.runtimeTowerId)
		if tower == nil or tower.ownerUserId ~= (data.dependencies :: Dependencies).localUserId then
			return
		end
	end
	local effect = (data.dependencies :: Dependencies).view:playAttackEffect({
		matchId = event.matchId,
		sequence = event.sequence,
		towerId = `tower-runtime:{event.runtimeTowerId}`,
		targetId = `enemy-runtime:{event.runtimeEnemyId}`,
		origin = event.sourcePosition,
		target = event.targetPosition,
		damage = if settings.damageNumbersEnabled then event.actualDamage else nil,
	})
	if isSuccess(effect) then
		data.attackEventCount += 1
	else
		data.rejectedInputCount += 1
	end
end

local function onGetResponse(data: ControllerData, generation: number, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.state ~= "Started" or generation ~= data.callbackGeneration then
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
			cancelGet(data)
			data.rejectedInputCount += 1
			requestRecovery(data)
		end
		return
	end
	data.getPending = nil
	local response = (handled :: any).value
	if RequestProtocol.isSuccess(response) then
		local validated = PlayableMatchProtocol.validateSnapshot((response :: RequestProtocol.Success).payload)
		if not validated.ok or not applySnapshot(data, validated.value, true) then
			data.rejectedInputCount += 1
		end
	else
		local code = (response :: RequestProtocol.Rejected).error.code
		setFeedback(data, PUBLIC_FEEDBACK[code] or "SERVER_UNAVAILABLE")
		if shouldRecoverPublic(code) and (pending == nil or not pending.isRecovery) then
			requestRecovery(data)
		end
		renderSnapshot(data)
	end
	if data.recoveryQueued then
		requestRecovery(data)
	end
end

local function onTravelGetResponse(data: ControllerData, generation: number, value: unknown, ...: unknown)
	if not data.callbacksEnabled or data.state ~= "Started" or generation ~= data.callbackGeneration then
		return
	end
	local dependencies = data.dependencies :: Dependencies
	local handled = dependencies.tracker:handleResponse(dependencies.getTravelSnapshot.definition, value, ...)
	if not isSuccess(handled) then
		if
			type(handled) == "table"
			and type((handled :: any).error) == "table"
			and (handled :: any).error.code == "MALFORMED_RESPONSE"
		then
			cancelTravelGet(data)
			data.rejectedInputCount += 1
		end
		return
	end
	data.travelGetPending = nil
	local response = (handled :: any).value
	if RequestProtocol.isSuccess(response) then
		local validated = MatchTravelProtocol.validateSnapshot((response :: RequestProtocol.Success).payload)
		if not validated.ok or not applyTravelSnapshot(data, validated.value) then
			data.rejectedInputCount += 1
		end
	end
end

local function onTravelMutationResponse(
	data: ControllerData,
	generation: number,
	definition: RemoteRegistry.Definition,
	value: unknown,
	...: unknown
)
	if not data.callbacksEnabled or data.state ~= "Started" or generation ~= data.callbackGeneration then
		return
	end
	local pending = data.travelMutationPending
	local handled = (data.dependencies :: Dependencies).tracker:handleResponse(definition, value, ...)
	if not isSuccess(handled) then
		if
			type(handled) == "table"
			and type((handled :: any).error) == "table"
			and (handled :: any).error.code == "MALFORMED_RESPONSE"
		then
			cancelTravelMutation(data)
			setFeedback(data, "SERVER_UNAVAILABLE")
			data.rejectedInputCount += 1
			renderSnapshot(data)
		end
		return
	end
	if pending == nil or pending.definition ~= definition then
		data.rejectedInputCount += 1
		return
	end
	data.travelMutationPending = nil
	local response = (handled :: any).value
	if RequestProtocol.isSuccess(response) then
		local validated = MatchTravelProtocol.validateMutationReceipt((response :: RequestProtocol.Success).payload)
		if
			not validated.ok
			or validated.value.transactionId ~= pending.transactionId
			or validated.value.snapshot.matchId ~= pending.matchId
			or not applyTravelSnapshot(data, validated.value.snapshot)
		then
			setFeedback(data, "STALE_MATCH")
			data.rejectedInputCount += 1
		else
			setFeedback(data, if pending.kind == "Return" then "RETURN_CONFIRMED" else "REMATCH_CONFIRMED")
		end
	else
		local code = (response :: RequestProtocol.Rejected).error.code
		setFeedback(data, PUBLIC_FEEDBACK[code] or "SERVER_UNAVAILABLE")
	end
	renderSnapshot(data)
end

local function finishAcceptedAction(data: ControllerData, kind: ActionRequestKind)
	if kind == "Placement" then
		data.selectedSlot = nil
		data.touchPlacementPosition = nil
	elseif kind == "Sell" or kind == "Replay" then
		data.selectedTowerId = nil
	end
end

local function onActionResponse(
	data: ControllerData,
	generation: number,
	definition: RemoteRegistry.Definition,
	value: unknown,
	...: unknown
)
	if not data.callbacksEnabled or data.state ~= "Started" or generation ~= data.callbackGeneration then
		return
	end
	local pending = data.actionPending
	local handled = (data.dependencies :: Dependencies).tracker:handleResponse(definition, value, ...)
	if not isSuccess(handled) then
		if
			type(handled) == "table"
			and type((handled :: any).error) == "table"
			and (handled :: any).error.code == "MALFORMED_RESPONSE"
		then
			cancelAction(data)
			setFeedback(data, "SERVER_UNAVAILABLE")
			data.rejectedInputCount += 1
			requestRecovery(data)
			renderSnapshot(data)
		end
		return
	end
	if pending == nil or pending.definition ~= definition then
		data.rejectedInputCount += 1
		return
	end
	data.actionPending = nil
	local response = (handled :: any).value
	if RequestProtocol.isSuccess(response) then
		local validated = PlayableMatchProtocol.validateActionReceipt((response :: RequestProtocol.Success).payload)
		if not validated.ok or validated.value.matchId ~= pending.matchId then
			setFeedback(data, "STALE_MATCH")
			data.rejectedInputCount += 1
		else
			setFeedback(data, RECEIPT_FEEDBACK[validated.value.reason])
			if validated.value.accepted then
				finishAcceptedAction(data, pending.kind)
			end
		end
	else
		local code = (response :: RequestProtocol.Rejected).error.code
		setFeedback(data, PUBLIC_FEEDBACK[code] or "SERVER_UNAVAILABLE")
	end
	renderSnapshot(data)
	requestRecovery(data)
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
	for index = #data.connections, 1, -1 do
		if not pcall(function()
			data.connections[index]:Disconnect()
		end) then
			failed = true
		end
	end
	table.clear(data.connections)
	cancelAction(data)
	cancelGet(data)
	cancelTravelGet(data)
	cancelTravelMutation(data)
	local dependencies = data.dependencies
	if dependencies ~= nil then
		if not pcall(function()
			dependencies.tracker:clear()
		end) then
			failed = true
		end
		local inputCleaned, inputResult = pcall(function()
			return dependencies.input:cleanup()
		end)
		if not inputCleaned or not isSuccess(inputResult) then
			failed = true
		end
		local viewCleaned, viewResult = pcall(function()
			return dependencies.view:cleanup()
		end)
		if not viewCleaned or not isSuccess(viewResult) then
			failed = true
		end
		if not pcall(dependencies.restoreCamera) then
			failed = true
		end
	end
	data.snapshot = nil
	data.travelSnapshot = nil
	data.spectatorTargetId = nil
	data.overviewMatchId = nil
	data.lastRenderedViewport = nil
	data.selectedSlot = nil
	data.selectedTowerId = nil
	data.touchPlacementPosition = nil
	data.dependencies = nil
	data.cleanupFailed = failed
	data.state = "Shutdown"
	return not failed
end

local function initialize(data: ControllerData)
	if data.state ~= "Constructed" then
		staticError("INVALID_INITIALIZE_STATE")
	end
	data.state = "Initializing"
	local created, dependencies = pcall(data.dependencyFactory, function(action)
		onViewAction(data, action)
	end, function(action)
		onSemanticAction(data, action)
	end)
	if not created or not validateDependencies(dependencies) then
		data.state = "Failed"
		staticError("INITIALIZE_FAILED")
	end
	data.dependencies = dependencies :: Dependencies
	for _, spec in REQUEST_SPECS do
		local registered = (dependencies :: Dependencies).tracker:register(
			spec.endpoint,
			spec.requestSchema,
			spec.responseSchema
		)
		if not isSuccess(registered) then
			cleanup(data)
			staticError("INITIALIZE_FAILED")
		end
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

local function onRenderStep(data: ControllerData, generation: number)
	if not data.callbacksEnabled or data.state ~= "Started" or generation ~= data.callbackGeneration then
		return
	end
	local now = (data.dependencies :: Dependencies).now()
	local getTimedOut = data.getPending ~= nil
		and now - (data.getPending :: PendingGet).issuedAt >= REQUEST_TIMEOUT_SECONDS
	local actionTimedOut = data.actionPending ~= nil
		and now - (data.actionPending :: PendingAction).issuedAt >= REQUEST_TIMEOUT_SECONDS
	local travelGetTimedOut = data.travelGetPending ~= nil
		and now - (data.travelGetPending :: PendingTravelGet).issuedAt >= REQUEST_TIMEOUT_SECONDS
	local travelMutationTimedOut = data.travelMutationPending ~= nil
		and now - (data.travelMutationPending :: PendingTravelMutation).issuedAt >= REQUEST_TIMEOUT_SECONDS
	if getTimedOut or actionTimedOut or travelGetTimedOut or travelMutationTimedOut then
		if getTimedOut then
			cancelGet(data)
		end
		if actionTimedOut then
			cancelAction(data)
		end
		if travelGetTimedOut then
			cancelTravelGet(data)
		end
		if travelMutationTimedOut then
			cancelTravelMutation(data)
		end
		setFeedback(data, "SERVER_UNAVAILABLE")
		renderSnapshot(data)
		requestRecovery(data)
		return
	end
	if data.feedbackCode ~= nil and now >= data.feedbackExpiresAt then
		setFeedback(data, nil)
		renderSnapshot(data)
	end
	if data.getPending == nil and now - data.lastSnapshotAt >= RECOVERY_SILENCE_SECONDS then
		data.lastSnapshotAt = now
		requestRecovery(data)
	end
	local family = inputFamily(data)
	local viewMetrics = (data.dependencies :: Dependencies).view:getMetrics()
	local viewport = readViewport(data.dependencies :: Dependencies)
	local viewportChanged = viewport ~= nil
		and (data.lastRenderedViewport == nil or viewport ~= data.lastRenderedViewport)
	if (type(viewMetrics) == "table" and (viewMetrics :: any).inputFamily ~= family) or viewportChanged then
		renderSnapshot(data)
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
	data.lastSnapshotAt = (data.dependencies :: Dependencies).now()
	data.state = "Started"
	local dependencies = data.dependencies :: Dependencies

	connectOrFail(data, function()
		return dependencies.replicationEvent.connectEvent(function(value, ...)
			onReplication(data, generation, value, ...)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.attackEvent.connectEvent(function(value, ...)
			onAttack(data, generation, value, ...)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.travelReplicationEvent.connectEvent(function(value, ...)
			onTravelReplication(data, generation, value, ...)
		end)
	end)
	for _, spec in REQUEST_SPECS do
		local endpoint = (dependencies :: any)[spec.field] :: RequestEndpoint
		connectOrFail(data, function()
			return endpoint.connectResponse(function(value, ...)
				if spec.endpoint == PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT then
					onGetResponse(data, generation, value, ...)
				elseif spec.endpoint == MatchTravelProtocol.ENDPOINTS.GET_SNAPSHOT then
					onTravelGetResponse(data, generation, value, ...)
				elseif
					spec.endpoint == MatchTravelProtocol.ENDPOINTS.REQUEST_RETURN
					or spec.endpoint == MatchTravelProtocol.ENDPOINTS.VOTE_REMATCH
				then
					onTravelMutationResponse(data, generation, endpoint.definition, value, ...)
				else
					onActionResponse(data, generation, endpoint.definition, value, ...)
				end
			end)
		end)
	end
	connectOrFail(data, function()
		return dependencies.connectWorldPointer(function(position, family)
			onWorldPointer(data, position, family)
		end)
	end)
	connectOrFail(data, function()
		return dependencies.connectRenderStep(function()
			onRenderStep(data, generation)
		end)
	end)
	data.renderPending = true
	if not renderSnapshot(data) then
		cleanup(data)
		staticError("START_FAILED")
	end
	if not issueGet(data, false) then
		cleanup(data)
		staticError("START_FAILED")
	end
	-- Direct local matches remain playable when no ticketed travel host is
	-- present; the travel request is therefore an optional parallel boundary.
	issueTravelGet(data)
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
	DATA[controller] = {
		logger = logger,
		state = "Constructed",
		dependencyFactory = dependencyFactory,
		dependencies = nil,
		connections = {},
		callbacksEnabled = false,
		callbackGeneration = 0,
		cleanupFailed = false,
		snapshot = nil,
		travelSnapshot = nil,
		retiredMatchIds = {},
		retiredMatchRing = {},
		matchGeneration = 0,
		overviewMatchId = nil,
		lastRenderedViewport = nil,
		selectedSlot = nil,
		selectedTowerId = nil,
		touchPlacementPosition = nil,
		rotationDegrees = 0,
		getPending = nil,
		actionPending = nil,
		travelGetPending = nil,
		travelMutationPending = nil,
		spectatorTargetId = nil,
		recoveryQueued = false,
		lastSnapshotAt = 0,
		renderPending = false,
		feedbackCode = nil,
		feedbackExpiresAt = 0,
		requestCount = 0,
		getRequestCount = 0,
		actionRequestCount = 0,
		recoveryRequestCount = 0,
		acceptedSnapshotCount = 0,
		rejectedInputCount = 0,
		attackEventCount = 0,
		renderCount = 0,
	}
	return Result.ok(controller)
end

function ControllerMethods.getState(self: Controller): LifecycleState
	return requireData(self).state
end

function ControllerMethods.getMetrics(self: Controller): Metrics
	local data = requireData(self)
	local viewMetrics: unknown = nil
	local inputMetrics: unknown = nil
	if data.dependencies ~= nil then
		pcall(function()
			viewMetrics = (data.dependencies :: Dependencies).view:getMetrics()
			inputMetrics = (data.dependencies :: Dependencies).input:getMetrics()
		end)
	end
	return table.freeze({
		lifecycleState = data.state,
		connectionCount = #data.connections,
		requestCount = data.requestCount,
		getRequestCount = data.getRequestCount,
		actionRequestCount = data.actionRequestCount,
		recoveryRequestCount = data.recoveryRequestCount,
		acceptedSnapshotCount = data.acceptedSnapshotCount,
		rejectedInputCount = data.rejectedInputCount,
		attackEventCount = data.attackEventCount,
		renderCount = data.renderCount,
		matchGeneration = data.matchGeneration,
		matchId = if data.snapshot == nil then nil else data.snapshot.matchId,
		revision = if data.snapshot == nil then nil else data.snapshot.revision,
		selectedSlot = data.selectedSlot,
		selectedTowerId = data.selectedTowerId,
		touchPlacementSelected = data.touchPlacementPosition ~= nil,
		rotationDegrees = data.rotationDegrees,
		getPending = data.getPending ~= nil,
		actionPending = data.actionPending ~= nil,
		travelGetPending = data.travelGetPending ~= nil,
		travelMutationPending = data.travelMutationPending ~= nil,
		viewerRole = if data.snapshot == nil then nil else data.snapshot.viewerRole,
		travelRevision = if data.travelSnapshot == nil then nil else data.travelSnapshot.revision,
		spectatorTargetId = data.spectatorTargetId,
		feedbackCode = data.feedbackCode,
		viewMetrics = viewMetrics,
		inputMetrics = inputMetrics,
	})
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

local function makeProductionDependencies(
	viewCallback: PlayableMatchView.UiActionCallback,
	inputCallback: PlayableInputMap.ActionCallback
): Dependencies
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
			connectResponse = function(listener)
				return response.OnClientEvent:Connect(listener)
			end,
			fire = function(envelope)
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
			definition = endpoint.definition,
			connectEvent = function(listener)
				return event.OnClientEvent:Connect(listener)
			end,
		}
	end

	local player = Players.LocalPlayer
	if player == nil then
		staticError("LOCAL_PLAYER_MISSING")
	end
	-- Resolve every required production endpoint before creating UI/input listeners so a
	-- partial network bootstrap cannot leave client-owned presentation state behind.
	local getSnapshotEndpoint = resolveRequest(PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT)
	local submitReadyEndpoint = resolveRequest(PlayableMatchProtocol.ENDPOINTS.SUBMIT_READY)
	local submitPlacementEndpoint = resolveRequest(PlayableMatchProtocol.ENDPOINTS.SUBMIT_PLACEMENT)
	local submitUpgradeEndpoint = resolveRequest(PlayableMatchProtocol.ENDPOINTS.SUBMIT_UPGRADE)
	local submitSellEndpoint = resolveRequest(PlayableMatchProtocol.ENDPOINTS.SUBMIT_SELL)
	local submitTargetModeEndpoint = resolveRequest(PlayableMatchProtocol.ENDPOINTS.SUBMIT_TARGET_MODE)
	local submitReplayEndpoint = resolveRequest(PlayableMatchProtocol.ENDPOINTS.SUBMIT_REPLAY)
	local getTravelSnapshotEndpoint = resolveRequest(MatchTravelProtocol.ENDPOINTS.GET_SNAPSHOT)
	local requestReturnEndpoint = resolveRequest(MatchTravelProtocol.ENDPOINTS.REQUEST_RETURN)
	local voteRematchEndpoint = resolveRequest(MatchTravelProtocol.ENDPOINTS.VOTE_REMATCH)
	local replicationEndpoint = resolveEvent(PlayableMatchProtocol.ENDPOINTS.REPLICATION)
	local attackEndpoint = resolveEvent(PlayableMatchProtocol.ENDPOINTS.ATTACK_EVENT)
	local travelReplicationEndpoint = resolveEvent(MatchTravelProtocol.ENDPOINTS.REPLICATION)
	local inputResult = PlayableInputMap.new(inputCallback)
	if not isSuccess(inputResult) then
		staticError("INPUT_CREATION_FAILED")
	end
	local viewResult = PlayableMatchView.new(viewCallback)
	if not isSuccess(viewResult) then
		inputResult.value:cleanup()
		staticError("VIEW_CREATION_FAILED")
	end

	local initialCamera = Workspace.CurrentCamera
	local initialCameraType = if initialCamera == nil then nil else initialCamera.CameraType
	local initialCameraSubject = if initialCamera == nil then nil else initialCamera.CameraSubject
	local initialCameraCFrame = if initialCamera == nil then nil else initialCamera.CFrame
	local baseFocused = false
	local function resolveMapFraming(): (Model?, Folder?, BasePart?, BasePart?)
		local runtimeMap = Workspace:FindFirstChild(RUNTIME_MAP_NAME)
		if runtimeMap == nil or not runtimeMap:IsA("Model") then
			return nil, nil, nil, nil
		end
		local markers = runtimeMap:FindFirstChild("Markers")
		if markers == nil or not markers:IsA("Folder") then
			return runtimeMap, nil, nil, nil
		end
		local bounds = markers:FindFirstChild("MapBounds")
		if bounds == nil or not bounds:IsA("BasePart") then
			return runtimeMap, markers, nil, nil
		end
		local cameraAnchors = markers:FindFirstChild("CameraAnchors")
		if cameraAnchors == nil or not cameraAnchors:IsA("Folder") then
			return runtimeMap, markers, bounds, nil
		end
		local selectedAnchor: BasePart? = nil
		local selectedId: string? = nil
		for _, candidate in cameraAnchors:GetChildren() do
			if candidate:IsA("BasePart") then
				local anchorId = candidate:GetAttribute("ATD_AnchorId")
				if type(anchorId) == "string" then
					if anchorId == "overview" then
						return runtimeMap, markers, bounds, candidate
					end
					if selectedId == nil or anchorId < selectedId then
						selectedAnchor = candidate
						selectedId = anchorId
					end
				end
			end
		end
		return runtimeMap, markers, bounds, selectedAnchor
	end
	local function applyOverviewCamera(): boolean
		local camera = Workspace.CurrentCamera
		local _, _, _, anchor = resolveMapFraming()
		if camera == nil or anchor == nil then
			return false
		end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = anchor.CFrame
		baseFocused = false
		return true
	end
	local function boundFocusPosition(bounds: BasePart, position: Vector3): Vector3
		local localPosition = bounds.CFrame:PointToObjectSpace(position)
		local halfSize = bounds.Size * 0.5
		return bounds.CFrame:PointToWorldSpace(
			Vector3.new(
				math.clamp(localPosition.X, -halfSize.X, halfSize.X),
				math.clamp(localPosition.Y, -halfSize.Y, halfSize.Y),
				math.clamp(localPosition.Z, -halfSize.Z, halfSize.Z)
			)
		)
	end
	local function focusCFrame(bounds: BasePart, position: Vector3, heightScale: number, depthScale: number): CFrame
		local horizontalSpan = math.max(bounds.Size.X, bounds.Size.Z)
		local height = math.clamp(horizontalSpan * heightScale, 18, 54)
		local depth = math.clamp(horizontalSpan * depthScale, 22, 62)
		local target = boundFocusPosition(bounds, position)
		local cameraPosition = target + bounds.CFrame.UpVector * height - bounds.CFrame.LookVector * depth
		return CFrame.lookAt(cameraPosition, target, bounds.CFrame.UpVector)
	end
	local function restoreInitialCamera(): boolean
		local camera = Workspace.CurrentCamera
		if camera == nil or camera ~= initialCamera then
			return false
		end
		if initialCameraType ~= nil then
			camera.CameraType = initialCameraType
		end
		camera.CameraSubject = initialCameraSubject
		if initialCameraCFrame ~= nil then
			camera.CFrame = initialCameraCFrame
		end
		baseFocused = false
		return true
	end
	local function applySettings(settings: SettingsProtocol.Settings)
		for name, volume in
			{
				Music = settings.masterVolume * settings.musicVolume,
				SFX = settings.masterVolume * settings.sfxVolume,
				UI = settings.masterVolume * settings.uiVolume,
			}
		do
			local group = SoundService:FindFirstChild(name)
			if group ~= nil and group:IsA("SoundGroup") then
				group.Volume = volume
			end
		end
	end

	return {
		localUserId = player.UserId,
		tracker = trackerResult.value,
		getSnapshot = getSnapshotEndpoint,
		submitReady = submitReadyEndpoint,
		submitPlacement = submitPlacementEndpoint,
		submitUpgrade = submitUpgradeEndpoint,
		submitSell = submitSellEndpoint,
		submitTargetMode = submitTargetModeEndpoint,
		submitReplay = submitReplayEndpoint,
		getTravelSnapshot = getTravelSnapshotEndpoint,
		requestReturn = requestReturnEndpoint,
		voteRematch = voteRematchEndpoint,
		replicationEvent = replicationEndpoint,
		attackEvent = attackEndpoint,
		travelReplicationEvent = travelReplicationEndpoint,
		view = viewResult.value,
		input = inputResult.value,
		connectWorldPointer = function(listener)
			return UserInputService.InputBegan:Connect(function(input, processed)
				if processed then
					return
				end
				local inputType = input.UserInputType
				if inputType == Enum.UserInputType.MouseButton1 then
					listener(Vector2.new(input.Position.X, input.Position.Y), "Desktop")
				elseif inputType == Enum.UserInputType.Touch then
					listener(Vector2.new(input.Position.X, input.Position.Y), "Touch")
				end
			end)
		end,
		connectRenderStep = function(listener)
			return RunService.RenderStepped:Connect(listener)
		end,
		now = os.clock,
		getPointerPosition = function()
			return UserInputService:GetMouseLocation()
		end,
		getViewportSize = function()
			local camera = Workspace.CurrentCamera
			return if camera == nil then Vector2.new(1280, 720) else camera.ViewportSize
		end,
		raycastPlacement = function(screenPosition)
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
			local resultValue = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH_STUDS, parameters)
			return if resultValue == nil then nil else resultValue.Position
		end,
		pickTower = function(screenPosition, towers, family)
			local camera = Workspace.CurrentCamera
			if camera == nil then
				return nil
			end
			local threshold = if family == "Touch" then 68 else 46
			local bestId: number? = nil
			local bestDistance = math.huge
			local bestDepth = math.huge
			for _, tower in towers do
				local projected, visible = camera:WorldToViewportPoint(tower.position)
				if visible and projected.Z > 0 then
					local distance = (Vector2.new(projected.X, projected.Y) - screenPosition).Magnitude
					if
						distance <= threshold
						and (distance < bestDistance or (distance == bestDistance and projected.Z < bestDepth))
					then
						bestId = tower.runtimeTowerId
						bestDistance = distance
						bestDepth = projected.Z
					end
				end
			end
			return bestId
		end,
		focusOverview = applyOverviewCamera,
		focusBase = function()
			if baseFocused then
				return applyOverviewCamera()
			end
			local camera = Workspace.CurrentCamera
			local _, markers, bounds = resolveMapFraming()
			if camera == nil or markers == nil or bounds == nil then
				return false
			end
			local base = markers:FindFirstChild("DefenderBase")
			if base == nil or not base:IsA("BasePart") then
				return false
			end
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = focusCFrame(bounds, base.Position, 0.24, 0.28)
			baseFocused = true
			return true
		end,
		focusSpectatorTarget = function(position)
			local camera = Workspace.CurrentCamera
			local _, _, bounds = resolveMapFraming()
			if camera == nil or bounds == nil then
				return false
			end
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = focusCFrame(bounds, position, 0.15, 0.18)
			baseFocused = false
			return true
		end,
		restoreCamera = function()
			restoreInitialCamera()
		end,
		applySettings = applySettings,
		newTransactionId = function()
			return `transaction:{string.lower(HttpService:GenerateGUID(false))}`
		end,
	}
end

function PlayableMatchController.new(logger: Log.Logger): ControllerResult
	return construct(logger, makeProductionDependencies)
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "PlayableMatchController" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionClientPlayable" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

if isExactTestModule() then
	PlayableMatchController.newForTests = function(logger: Log.Logger, dependencies: Dependencies): ControllerResult
		if not validateDependencies(dependencies) then
			return failure("INVALID_DEPENDENCIES")
		end
		return construct(logger, function(_viewCallback, _inputCallback)
			return dependencies
		end)
	end
	PlayableMatchController.invokeSemanticActionForTests = function(controller: Controller, action: unknown): boolean
		return onSemanticAction(requireData(controller), action)
	end
	PlayableMatchController.invokeWorldPointerForTests = function(
		controller: Controller,
		position: unknown,
		source: unknown
	)
		onWorldPointer(requireData(controller), position, source)
	end
end

table.freeze(ControllerMethods)
return table.freeze(PlayableMatchController)
