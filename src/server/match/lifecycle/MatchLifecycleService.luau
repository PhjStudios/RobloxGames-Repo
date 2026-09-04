--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Log = require(ReplicatedStorage.Shared.logging.Log)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local Cleanup = require(ReplicatedStorage.Shared.util.Cleanup)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local MatchStateMachine = require(script.Parent.MatchStateMachine)

export type LifecycleState =
	"Constructed"
	| "Initializing"
	| "Initialized"
	| "Starting"
	| "Started"
	| "ShuttingDown"
	| "Shutdown"
	| "Failed"

export type ParticipantState = "Active" | "Disconnected" | "Returned" | "Spectator"

export type ParticipantSnapshot = {
	userId: number,
	state: ParticipantState,
	ready: boolean,
}

export type MatchSnapshot = {
	matchId: Ids.MatchId,
	revision: number,
	state: MatchStateMachine.MatchState,
	deadlineServerTime: number?,
	participants: { ParticipantSnapshot },
}

export type ParticipantObserverHandle = {}

export type ParticipantObserverAdapter = {
	onSnapshot: (self: ParticipantObserverAdapter, snapshot: MatchSnapshot) -> unknown,
}

export type ParticipantObserverReservation = {
	handle: ParticipantObserverHandle,
	snapshot: MatchSnapshot,
}

export type ParticipantObserverOperation =
	"reserveParticipantObserver"
	| "refreshParticipantObserver"
	| "activateParticipantObserver"
	| "detachParticipantObserver"

export type ParticipantObserverErrorCode =
	"UNAVAILABLE"
	| "INVALID_ARGUMENT"
	| "INVALID_HANDLE"
	| "WRONG_STATE"
	| "REVISION_MISMATCH"
	| "REENTRANT"
	| "INTERNAL_ERROR"

export type ParticipantObserverError = {
	code: ParticipantObserverErrorCode,
	operation: ParticipantObserverOperation,
}

export type RuntimeRoutePointKind = "EnemySpawn" | "PathNode" | "DefenderBase"

export type RuntimeRoutePointSnapshot = {
	kind: RuntimeRoutePointKind,
	nodeOrder: number?,
	cframe: CFrame,
	position: Vector3,
	distance: number,
}

export type RuntimeLaneSnapshot = {
	id: string,
	totalDistance: number,
	points: { RuntimeRoutePointSnapshot },
}

export type RuntimeRegionSnapshot = {
	id: string,
	cframe: CFrame,
	size: Vector3,
}

export type RuntimeNamedPointSnapshot = {
	id: string,
	cframe: CFrame,
	position: Vector3,
}

export type RuntimeMapSnapshot = {
	mapId: Ids.MapId,
	base: {
		cframe: CFrame,
		position: Vector3,
	},
	bounds: {
		cframe: CFrame,
		size: Vector3,
	},
	lanes: { RuntimeLaneSnapshot },
	placementZones: { RuntimeRegionSnapshot },
	noPlacementZones: { RuntimeRegionSnapshot },
	cameraAnchors: { RuntimeNamedPointSnapshot },
	playerSpawns: { RuntimeNamedPointSnapshot },
}

export type SnapshotErrorCode = "UNAVAILABLE" | "INTERNAL_ERROR"

export type SnapshotError = {
	code: SnapshotErrorCode,
	operation: "getSnapshot",
}

export type RuntimeMapSnapshotError = {
	code: SnapshotErrorCode,
	operation: "getRuntimeMapSnapshot",
}

export type MapSelectionError = {
	code: SnapshotErrorCode,
	operation: "selectMap",
}

export type ConnectedRecipient = {
	recipient: unknown,
	userId: number,
}

export type ConnectedRecipientsError = {
	code: SnapshotErrorCode,
	operation: "getConnectedRecipients",
}

export type CommittedBaseDefeatRecipientsError = {
	code: SnapshotErrorCode,
	operation: "getCommittedBaseDefeatRecipients",
}

export type ReadyErrorCode = "STALE_REQUEST" | "DUPLICATE_REQUEST" | "NOT_AUTHORIZED" | "UNAVAILABLE" | "INTERNAL_ERROR"

export type ReadyError = {
	code: ReadyErrorCode,
	operation: "submitReady",
}

export type BaseDefeatOperation = "beginBaseDefeat" | "commitBaseDefeat" | "rollbackBaseDefeat"

export type BaseDefeatErrorCode =
	"UNAVAILABLE"
	| "NOT_AUTHORIZED"
	| "WRONG_STATE"
	| "INVALID_TOKEN"
	| "REENTRANT"
	| "INTERNAL_ERROR"

export type BaseDefeatError = {
	code: BaseDefeatErrorCode,
	operation: BaseDefeatOperation,
}

export type BaseDefeatToken = {}

export type BaseDefeatCommitOutcome = {
	committed: true,
	published: boolean,
	snapshot: MatchSnapshot,
}

export type WaveActivationOperation = "beginWaveActivation" | "commitWaveActivation" | "rollbackWaveActivation"

export type WaveActivationErrorCode =
	"UNAVAILABLE"
	| "NOT_AUTHORIZED"
	| "WRONG_STATE"
	| "INVALID_TOKEN"
	| "REENTRANT"
	| "INTERNAL_ERROR"

export type WaveActivationError = {
	code: WaveActivationErrorCode,
	operation: WaveActivationOperation,
}

export type WaveActivationToken = {}

export type WaveActivationCommitOutcome = {
	committed: true,
	published: boolean,
	snapshot: MatchSnapshot,
}

export type StudioWaveErrorCode = "UNAVAILABLE" | "NOT_STUDIO" | "WRONG_STATE" | "REENTRANT" | "INTERNAL_ERROR"

export type StudioWaveError = {
	code: StudioWaveErrorCode,
	operation: "activateStudioWaveForEvidence",
}

export type MapLoaderAdapter = {
	load: (self: MapLoaderAdapter, mapId: unknown) -> unknown,
	unload: ((self: MapLoaderAdapter) -> unknown)?,
	cleanup: (self: MapLoaderAdapter) -> unknown,
}

export type StateMachineAdapter = {
	getSnapshot: (self: StateMachineAdapter) -> unknown,
	beginTransition: (self: StateMachineAdapter, targetState: unknown, expectedRevision: unknown) -> unknown,
	commitTransition: (self: StateMachineAdapter, token: unknown) -> unknown,
	rollbackTransition: (self: StateMachineAdapter, token: unknown) -> unknown,
	touch: (self: StateMachineAdapter, expectedRevision: unknown) -> unknown,
	cleanup: (self: StateMachineAdapter) -> unknown,
}

export type RosterAdapter = {
	connect: (self: RosterAdapter, connection: unknown, userId: unknown, matchState: unknown) -> unknown,
	disconnect: (self: RosterAdapter, connection: unknown) -> unknown,
	resolveConnection: (self: RosterAdapter, connection: unknown) -> unknown,
	setReadyForConnection: (self: RosterAdapter, connection: unknown) -> unknown,
	getSnapshot: (self: RosterAdapter) -> unknown,
	getReadiness: (self: RosterAdapter) -> unknown,
	markUnreadyActiveReturned: (self: RosterAdapter) -> unknown,
	cleanup: (self: RosterAdapter) -> unknown,
}

export type PlayerListener = (connection: unknown) -> ()

export type PlayerSource = {
	getPlayers: (self: PlayerSource) -> unknown,
	getUserId: (self: PlayerSource, connection: unknown) -> unknown,
	connectAdded: (self: PlayerSource, listener: PlayerListener) -> unknown,
	connectRemoving: (self: PlayerSource, listener: PlayerListener) -> unknown,
}

export type ReadyCoordinatorAdapter = {
	enterReadyCheck: (self: ReadyCoordinatorAdapter) -> unknown,
	submitReady: (
		self: ReadyCoordinatorAdapter,
		connection: unknown,
		matchId: unknown,
		observedRevision: unknown
	) -> unknown,
	onRosterChanged: (self: ReadyCoordinatorAdapter) -> unknown,
	getDeadlineServerTime: (self: ReadyCoordinatorAdapter) -> unknown,
	cleanup: (self: ReadyCoordinatorAdapter) -> unknown,
}

export type SnapshotBroadcasterAdapter = {
	publish: (self: SnapshotBroadcasterAdapter, snapshot: unknown) -> unknown,
	cleanup: (self: SnapshotBroadcasterAdapter) -> unknown,
}

export type Clock = () -> unknown
export type TimerCallback = () -> ()
export type Schedule = (delaySeconds: number, callback: TimerCallback) -> unknown
export type Cancel = (handle: unknown) -> ()
export type SnapshotSender = (recipient: unknown, snapshot: MatchSnapshot) -> boolean
export type AdapterFactory = (dependencies: unknown) -> unknown
export type IsStudio = () -> unknown

export type TestDependencies = {
	mapLoader: MapLoaderAdapter,
	generateMatchId: () -> unknown,
	initialMapId: string?,
	roster: RosterAdapter,
	playerSource: PlayerSource,
	createStateMachine: ((matchId: unknown) -> unknown)?,
	createReadyCoordinator: AdapterFactory?,
	createSnapshotBroadcaster: AdapterFactory?,
	clock: Clock?,
	schedule: Schedule?,
	cancel: Cancel?,
	snapshotSender: SnapshotSender?,
	isStudio: IsStudio?,
}

type ServiceData = {
	logger: Log.Logger,
	state: LifecycleState,
	mapLoader: MapLoaderAdapter?,
	machine: StateMachineAdapter?,
	roster: RosterAdapter?,
	playerSource: PlayerSource?,
	readyCoordinator: ReadyCoordinatorAdapter?,
	snapshotBroadcaster: SnapshotBroadcasterAdapter?,
	cleanup: Cleanup.Container?,
	mapLoaded: boolean,
	callbacksEnabled: boolean,
	available: boolean,
	shutdownFailure: string?,
	serviceDefinition: ServiceLifecycle.ServiceDefinition?,
	runtimeMapSnapshot: RuntimeMapSnapshot?,
	selectedMapId: Ids.MapId,
	waveActivationToken: WaveActivationToken?,
	waveActivationOperationActive: boolean,
	waveActivationReentryViolation: boolean,
	waveActivationCommitted: boolean,
	waveActivationShutdownRequested: boolean,
	baseDefeatToken: BaseDefeatToken?,
	baseDefeatOperationActive: boolean,
	baseDefeatReentryViolation: boolean,
	baseDefeatCommitted: boolean,
	baseDefeatShutdownRequested: boolean,
	isStudio: IsStudio?,
	studioWaveOperationActive: boolean,
	studioWaveReentryViolation: boolean,
	studioWaveActivated: boolean,
	studioWaveShutdownRequested: boolean,
	participantObserverAdapter: ParticipantObserverAdapter?,
	participantObserverHandle: ParticipantObserverHandle?,
	participantObserverStatus: ParticipantObserverStatus?,
	participantObserverPendingSnapshot: MatchSnapshot?,
	participantObserverGeneration: number,
	participantObserverOperationActive: boolean,
	participantObserverReentryViolation: boolean,
	participantObserverShutdownRequested: boolean,
}

type BaseDefeatTokenState = "Prepared" | "Committed" | "RolledBack"
type WaveActivationTokenState = "Prepared" | "Committed" | "RolledBack"
type ParticipantObserverStatus = "Reserved" | "Active" | "Detached"

type ExistingPlayer = {
	connection: unknown,
	userId: number,
	index: number,
}

type SnapshotRecipientRecord = ConnectedRecipient

local ServiceMethods = {}
ServiceMethods.__index = ServiceMethods

export type Service = typeof(setmetatable({} :: {}, ServiceMethods))
export type TestConstructor = (logger: Log.Logger, dependencies: TestDependencies) -> Service

type BaseDefeatTokenData = {
	owner: ServiceData,
	state: BaseDefeatTokenState,
	machineToken: unknown?,
	preparedSnapshot: MatchSnapshot,
	terminalRecipients: { SnapshotRecipientRecord },
	outcome: BaseDefeatCommitOutcome?,
}

type WaveActivationTokenData = {
	owner: ServiceData,
	state: WaveActivationTokenState,
	machineToken: unknown?,
	preparedSnapshot: MatchSnapshot,
	preparedRevision: number,
	outcome: WaveActivationCommitOutcome?,
}

type ParticipantObserverHandleData = {
	owner: ServiceData,
	generation: number,
	status: ParticipantObserverStatus,
}

local FIXED_MAP_ID = "map:phase07-graybox"
local SERVICE_NAME = "MatchLifecycle"
local CLEANUP_LABEL = "match-lifecycle"
local STATIC_ERROR_PREFIX = "[ATD_MATCH_LIFECYCLE]"
local MAX_PARTICIPANTS = 4
local MAX_RUNTIME_SNAPSHOT_NODES = 20_000

local PARTICIPANT_STATES: { [string]: boolean } = table.freeze({
	Active = true,
	Disconnected = true,
	Returned = true,
	Spectator = true,
})

local BENIGN_CONNECT_ERRORS: { [string]: boolean } = table.freeze({
	DUPLICATE_CONNECTION = true,
	INVALID_USER_ID = true,
})

local BENIGN_DISCONNECT_ERRORS: { [string]: boolean } = table.freeze({
	ALREADY_DISCONNECTED = true,
	INACTIVE_PARTICIPANT = true,
	INVALID_CONNECTION = true,
	STALE_CONNECTION = true,
	UNKNOWN_CONNECTION = true,
	UNTRACKED_SPECTATOR = true,
})

local BENIGN_RESOLVE_ERRORS: { [string]: boolean } = table.freeze({
	INVALID_CONNECTION = true,
	STALE_CONNECTION = true,
	UNKNOWN_CONNECTION = true,
	UNTRACKED_SPECTATOR = true,
})

local SERVICE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local BASE_DEFEAT_TOKEN_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: BaseDefeatTokenData }
local WAVE_ACTIVATION_TOKEN_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: WaveActivationTokenData }
local PARTICIPANT_OBSERVER_HANDLE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ParticipantObserverHandleData }
local PARTICIPANT_OBSERVER_ACTIVATION_SUCCESS: Result.Success<boolean> = Result.ok(true)

local MatchLifecycleService = {
	FIXED_MAP_ID = FIXED_MAP_ID,
	newForTests = nil :: TestConstructor?,
}

local shutdown: (ServiceData) -> ()
local clearParticipantObserver: (ServiceData) -> ()

local function staticError(code: string): never
	error(`{STATIC_ERROR_PREFIX}[code={code}]`, 0)
end

local function makeSnapshotError(code: SnapshotErrorCode): SnapshotError
	return table.freeze({
		code = code,
		operation = "getSnapshot",
	})
end

local function snapshotFailure(code: SnapshotErrorCode): Result.Failure<SnapshotError>
	return Result.err(makeSnapshotError(code))
end

local function runtimeMapSnapshotFailure(code: SnapshotErrorCode): Result.Failure<RuntimeMapSnapshotError>
	return Result.err(table.freeze({
		code = code,
		operation = "getRuntimeMapSnapshot",
	}))
end

local function connectedRecipientsFailure(code: SnapshotErrorCode): Result.Failure<ConnectedRecipientsError>
	return Result.err(table.freeze({
		code = code,
		operation = "getConnectedRecipients",
	}))
end

local function committedBaseDefeatRecipientsFailure(
	code: SnapshotErrorCode
): Result.Failure<CommittedBaseDefeatRecipientsError>
	return Result.err(table.freeze({
		code = code,
		operation = "getCommittedBaseDefeatRecipients",
	}))
end

local function readyFailure(code: ReadyErrorCode): Result.Failure<ReadyError>
	return Result.err(table.freeze({
		code = code,
		operation = "submitReady",
	}))
end

local function makeBaseDefeatError(code: BaseDefeatErrorCode, operation: BaseDefeatOperation): BaseDefeatError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function baseDefeatFailure(
	code: BaseDefeatErrorCode,
	operation: BaseDefeatOperation
): Result.Failure<BaseDefeatError>
	return Result.err(makeBaseDefeatError(code, operation))
end

local function makeWaveActivationError(
	code: WaveActivationErrorCode,
	operation: WaveActivationOperation
): WaveActivationError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function waveActivationFailure(
	code: WaveActivationErrorCode,
	operation: WaveActivationOperation
): Result.Failure<WaveActivationError>
	return Result.err(makeWaveActivationError(code, operation))
end

local function studioWaveFailure(code: StudioWaveErrorCode): Result.Failure<StudioWaveError>
	return Result.err(table.freeze({
		code = code,
		operation = "activateStudioWaveForEvidence",
	}))
end

local function makeParticipantObserverError(
	code: ParticipantObserverErrorCode,
	operation: ParticipantObserverOperation
): ParticipantObserverError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function participantObserverFailure(
	code: ParticipantObserverErrorCode,
	operation: ParticipantObserverOperation
): Result.Failure<ParticipantObserverError>
	return Result.err(makeParticipantObserverError(code, operation))
end

local function requireData(value: unknown): ServiceData
	if type(value) ~= "table" then
		staticError("INVALID_CONTEXT")
	end
	local data = SERVICE_DATA[value :: any]
	if data == nil then
		staticError("INVALID_CONTEXT")
	end
	return data
end

local function isSuccess(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, any)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function isDetachedFrozenValue(
	value: unknown,
	visiting: { [any]: boolean },
	visited: { [any]: boolean },
	nodeCount: { value: number }
): boolean
	if typeof(value) == "Instance" then
		return false
	end
	if type(value) ~= "table" then
		local valueType = typeof(value)
		return value == nil
			or valueType == "boolean"
			or valueType == "number"
			or valueType == "string"
			or valueType == "Vector3"
			or valueType == "CFrame"
	end
	local tableValue = value :: { [any]: unknown }
	if getmetatable(tableValue) ~= nil or not table.isfrozen(tableValue) or visiting[tableValue] then
		return false
	end
	if visited[tableValue] then
		return true
	end
	nodeCount.value += 1
	if nodeCount.value > MAX_RUNTIME_SNAPSHOT_NODES then
		return false
	end
	visiting[tableValue] = true
	for key, child in next, tableValue do
		if
			not isDetachedFrozenValue(key, visiting, visited, nodeCount)
			or not isDetachedFrozenValue(child, visiting, visited, nodeCount)
		then
			visiting[tableValue] = nil
			return false
		end
	end
	visiting[tableValue] = nil
	visited[tableValue] = true
	return true
end

local function validateRuntimeMapSnapshot(value: unknown, expectedMapId: Ids.MapId): RuntimeMapSnapshot?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return nil
	end
	local snapshot = value :: any
	if
		snapshot.mapId ~= expectedMapId
		or type(snapshot.lanes) ~= "table"
		or not table.isfrozen(snapshot.lanes)
		or rawlen(snapshot.lanes) < 1
		or rawlen(snapshot.lanes) > 32
	then
		return nil
	end
	if not isDetachedFrozenValue(value, {}, {}, { value = 0 }) then
		return nil
	end
	return value :: RuntimeMapSnapshot
end

local function resultErrorCode(value: unknown): string?
	if type(value) ~= "table" or (value :: any).ok ~= false then
		return nil
	end
	local errorValue = (value :: any).error
	if type(errorValue) ~= "table" or type((errorValue :: any).code) ~= "string" then
		return nil
	end
	return (errorValue :: any).code
end

local function isAdapter(value: unknown, requiredMethods: { string }): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, methodName in requiredMethods do
		if type((value :: any)[methodName]) ~= "function" then
			return false
		end
	end
	return true
end

local function isParticipantObserverAdapter(value: unknown): boolean
	if
		type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
		or type((value :: any).onSnapshot) ~= "function"
	then
		return false
	end
	local fieldCount = 0
	for fieldName in next, value :: any do
		if fieldName ~= "onSnapshot" then
			return false
		end
		fieldCount += 1
	end
	return fieldCount == 1
end

local function isUserId(value: unknown): boolean
	return type(value) == "number" and value ~= 0 and Validation.isSafeInteger(value)
end

local function isDenseArray(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local array = value :: { [any]: unknown }
	local length = #array
	local count = 0
	for key in next, array do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
			return false
		end
		count += 1
	end
	return count == length
end

local function requireState(data: ServiceData, expectedState: LifecycleState)
	if data.state ~= expectedState then
		staticError("INVALID_STATE")
	end
end

local function detachedStateSnapshot(machine: StateMachineAdapter): MatchStateMachine.StateSnapshot?
	local called, resultValue = pcall(machine.getSnapshot, machine)
	if not called or not isSuccess(resultValue) then
		return nil
	end
	local value = (resultValue :: any).value
	if type(value) ~= "table" then
		return nil
	end
	local matchIdResult = Ids.validateMatchId((value :: any).matchId)
	if
		not matchIdResult.ok
		or not Validation.isSafeInteger((value :: any).revision)
		or (value :: any).revision < MatchStateMachine.INITIAL_REVISION
		or not MatchStateMachine.isMatchState((value :: any).state)
	then
		return nil
	end
	return table.freeze({
		matchId = matchIdResult.value,
		revision = (value :: any).revision,
		state = (value :: any).state,
	}) :: MatchStateMachine.StateSnapshot
end

local function detachedParticipants(roster: RosterAdapter): { ParticipantSnapshot }?
	local called, resultValue = pcall(roster.getSnapshot, roster)
	if not called or not isSuccess(resultValue) then
		return nil
	end
	local rawParticipants = (resultValue :: any).value
	if not isDenseArray(rawParticipants) or #rawParticipants > MAX_PARTICIPANTS then
		return nil
	end

	local participants: { ParticipantSnapshot } = table.create(#rawParticipants)
	local previousUserId: number? = nil
	for index = 1, #rawParticipants do
		local rawParticipant = rawParticipants[index]
		if type(rawParticipant) ~= "table" or getmetatable(rawParticipant) ~= nil then
			return nil
		end
		local fieldCount = 0
		for fieldName in next, rawParticipant :: any do
			if fieldName ~= "userId" and fieldName ~= "state" and fieldName ~= "ready" then
				return nil
			end
			fieldCount += 1
		end
		local userId = (rawParticipant :: any).userId
		local participantState = (rawParticipant :: any).state
		local ready = (rawParticipant :: any).ready
		if
			fieldCount ~= 3
			or not isUserId(userId)
			or type(participantState) ~= "string"
			or PARTICIPANT_STATES[participantState] ~= true
			or type(ready) ~= "boolean"
			or (ready and participantState ~= "Active")
			or (previousUserId ~= nil and userId <= previousUserId)
		then
			return nil
		end
		previousUserId = userId
		table.insert(
			participants,
			table.freeze({
				userId = userId,
				state = participantState,
				ready = ready,
			}) :: ParticipantSnapshot
		)
	end
	return table.freeze(participants)
end

local function rollbackToken(machine: StateMachineAdapter, token: unknown): boolean
	local called, resultValue = callNonYielding(machine.rollbackTransition, machine, token)
	return called and isSuccess(resultValue)
end

local function transition(machine: StateMachineAdapter, targetState: MatchStateMachine.MatchState): boolean
	local current = detachedStateSnapshot(machine)
	if current == nil then
		return false
	end

	local began, beginValue = callNonYielding(machine.beginTransition, machine, targetState, current.revision)
	if not began or not isSuccess(beginValue) then
		return false
	end
	local token = (beginValue :: any).value

	local committed, commitValue = callNonYielding(machine.commitTransition, machine, token)
	if committed and isSuccess(commitValue) then
		return true
	end

	rollbackToken(machine, token)
	return false
end

local function touchRevision(machine: StateMachineAdapter): boolean
	local before = detachedStateSnapshot(machine)
	if before == nil or before.state == "Closing" then
		return false
	end
	local called, resultValue = pcall(machine.touch, machine, before.revision)
	if not called or not isSuccess(resultValue) then
		return false
	end
	local after = detachedStateSnapshot(machine)
	return after ~= nil
		and after.matchId == before.matchId
		and after.state == before.state
		and after.revision == before.revision + 1
end

local function cleanupMapLoader(mapLoader: MapLoaderAdapter)
	local called, resultValue = pcall(mapLoader.cleanup, mapLoader)
	if not called or not isSuccess(resultValue) then
		staticError("MAP_CLEANUP_FAILED")
	end
end

local function cleanupStateMachine(machine: StateMachineAdapter)
	local called, resultValue = pcall(machine.cleanup, machine)
	if not called or not isSuccess(resultValue) then
		staticError("STATE_CLEANUP_FAILED")
	end
end

local function cleanupRoster(roster: RosterAdapter)
	local called, resultValue = pcall(roster.cleanup, roster)
	if not called or not isSuccess(resultValue) then
		staticError("ROSTER_CLEANUP_FAILED")
	end
end

local function cleanupReadyCoordinator(coordinator: ReadyCoordinatorAdapter)
	local called, resultValue = pcall(coordinator.cleanup, coordinator)
	if not called or not isSuccess(resultValue) then
		staticError("READY_CLEANUP_FAILED")
	end
end

local function cleanupSnapshotBroadcaster(broadcaster: SnapshotBroadcasterAdapter)
	local called, resultValue = pcall(broadcaster.cleanup, broadcaster)
	if not called or not isSuccess(resultValue) then
		staticError("SNAPSHOT_CLEANUP_FAILED")
	end
end

local function clearBaseDefeatClaim(data: ServiceData, rollbackPrepared: boolean): boolean
	local token = data.baseDefeatToken
	data.baseDefeatToken = nil
	data.baseDefeatOperationActive = false
	data.baseDefeatReentryViolation = false
	data.baseDefeatShutdownRequested = false
	if token == nil then
		return true
	end

	local tokenData = BASE_DEFEAT_TOKEN_DATA[token]
	BASE_DEFEAT_TOKEN_DATA[token] = nil
	if tokenData == nil or tokenData.owner ~= data then
		return false
	end
	if tokenData.state ~= "Prepared" or not rollbackPrepared then
		tokenData.machineToken = nil
		return true
	end

	local machine = data.machine
	local machineToken = tokenData.machineToken
	tokenData.machineToken = nil
	tokenData.state = "RolledBack"
	if machine == nil or machineToken == nil then
		return false
	end
	local called, resultValue = callNonYielding(machine.rollbackTransition, machine, machineToken)
	return called and isSuccess(resultValue)
end

local function clearWaveActivationClaim(data: ServiceData, rollbackPrepared: boolean): boolean
	local token = data.waveActivationToken
	data.waveActivationToken = nil
	data.waveActivationOperationActive = false
	data.waveActivationReentryViolation = false
	data.waveActivationShutdownRequested = false
	if token == nil then
		return true
	end

	local tokenData = WAVE_ACTIVATION_TOKEN_DATA[token]
	WAVE_ACTIVATION_TOKEN_DATA[token] = nil
	if tokenData == nil or tokenData.owner ~= data then
		return false
	end
	if tokenData.state ~= "Prepared" or not rollbackPrepared then
		tokenData.machineToken = nil
		return true
	end

	local machine = data.machine
	local machineToken = tokenData.machineToken
	tokenData.machineToken = nil
	tokenData.state = "RolledBack"
	if machine == nil or machineToken == nil then
		return false
	end
	local called, resultValue = callNonYielding(machine.rollbackTransition, machine, machineToken)
	return called and isSuccess(resultValue)
end

local function releaseOwnedResources(data: ServiceData): (boolean, string?)
	data.callbacksEnabled = false
	data.available = false
	clearParticipantObserver(data)
	data.isStudio = nil
	data.studioWaveOperationActive = false
	data.studioWaveReentryViolation = false
	data.studioWaveActivated = false
	data.studioWaveShutdownRequested = false
	local waveActivationClaimReleased = clearWaveActivationClaim(data, true)
	data.waveActivationCommitted = false
	local defeatClaimReleased = clearBaseDefeatClaim(data, true)
	data.baseDefeatCommitted = false
	local cleanup = data.cleanup
	data.cleanup = nil
	data.mapLoaded = false
	data.runtimeMapSnapshot = nil

	if cleanup == nil then
		data.mapLoader = nil
		data.machine = nil
		data.roster = nil
		data.playerSource = nil
		data.readyCoordinator = nil
		data.snapshotBroadcaster = nil
		local claimsReleased = waveActivationClaimReleased and defeatClaimReleased
		return claimsReleased, if claimsReleased then nil else `{STATIC_ERROR_PREFIX}[code=CLEANUP_FAILED]`
	end

	local cleaned, failureValue = pcall(function()
		cleanup:cleanup()
	end)
	data.mapLoader = nil
	data.machine = nil
	data.roster = nil
	data.playerSource = nil
	data.readyCoordinator = nil
	data.snapshotBroadcaster = nil
	if cleaned and waveActivationClaimReleased and defeatClaimReleased then
		return true, nil
	end
	if type(failureValue) == "string" then
		return false, failureValue
	end
	return false, `{STATIC_ERROR_PREFIX}[code=CLEANUP_FAILED]`
end

local function failAfterRollback(data: ServiceData, code: string): never
	local cleaned, cleanupFailure = releaseOwnedResources(data)
	data.state = "Failed"
	if not cleaned then
		data.shutdownFailure = cleanupFailure
		error(cleanupFailure :: string, 0)
	end
	staticError(code)
end

local function failClosedAtRuntime(data: ServiceData, code: string)
	if not data.available then
		return
	end
	data.callbacksEnabled = false
	if data.baseDefeatCommitted or data.waveActivationCommitted then
		data.logger:warn("lifecycle", "match_failed_closed", "Match lifecycle failed closed", {
			code = code,
			service = SERVICE_NAME,
			state = data.state,
		})
		return
	end
	data.available = false
	local machine = data.machine
	if machine ~= nil then
		local current = detachedStateSnapshot(machine)
		if current ~= nil and current.state ~= "Closing" then
			transition(machine, "Closing")
		end
	end
	data.logger:warn("lifecycle", "match_failed_closed", "Match lifecycle failed closed", {
		code = code,
		service = SERVICE_NAME,
		state = data.state,
	})
end

local function readUserId(playerSource: PlayerSource, connection: unknown): number?
	local called, userIdValue = pcall(playerSource.getUserId, playerSource, connection)
	if not called or not isUserId(userIdValue) then
		return nil
	end
	return userIdValue :: number
end

local function composeSnapshot(data: ServiceData): MatchSnapshot?
	local machine = data.machine
	local roster = data.roster
	local coordinator = data.readyCoordinator
	if machine == nil or roster == nil or coordinator == nil then
		return nil
	end

	local stateSnapshot = detachedStateSnapshot(machine)
	local participants = detachedParticipants(roster)
	if stateSnapshot == nil or participants == nil then
		return nil
	end

	local deadlineRead, deadlineValue = pcall(coordinator.getDeadlineServerTime, coordinator)
	if not deadlineRead then
		return nil
	end
	local deadlineServerTime = deadlineValue
	if
		deadlineServerTime ~= nil
		and (type(deadlineServerTime) ~= "number" or not Validation.isFiniteNumber(deadlineServerTime))
	then
		return nil
	end

	local validated = MatchProtocol.validateMatchSnapshot({
		matchId = stateSnapshot.matchId,
		revision = stateSnapshot.revision,
		state = stateSnapshot.state,
		deadlineServerTime = deadlineServerTime,
		participants = participants,
	})
	if not validated.ok then
		return nil
	end
	return validated.value
end

local function participantObserverHandleMatches(data: ServiceData, value: unknown): boolean
	if type(value) ~= "table" or data.participantObserverHandle ~= value then
		return false
	end
	local handleData = PARTICIPANT_OBSERVER_HANDLE_DATA[value :: any]
	return handleData ~= nil
		and handleData.owner == data
		and handleData.generation == data.participantObserverGeneration
		and handleData.status == data.participantObserverStatus
end

local function detachParticipantObserverState(data: ServiceData): boolean
	local handle = data.participantObserverHandle
	local status = data.participantObserverStatus
	if handle == nil or status == nil or status == "Detached" then
		return false
	end
	data.participantObserverAdapter = nil
	data.participantObserverPendingSnapshot = nil
	data.participantObserverStatus = "Detached"
	local handleData = PARTICIPANT_OBSERVER_HANDLE_DATA[handle]
	if
		handleData ~= nil
		and handleData.owner == data
		and handleData.generation == data.participantObserverGeneration
	then
		handleData.status = "Detached"
	end
	return true
end

clearParticipantObserver = function(data: ServiceData)
	local handle = data.participantObserverHandle
	if handle ~= nil then
		PARTICIPANT_OBSERVER_HANDLE_DATA[handle] = nil
	end
	data.participantObserverAdapter = nil
	data.participantObserverHandle = nil
	data.participantObserverStatus = nil
	data.participantObserverPendingSnapshot = nil
	data.participantObserverOperationActive = false
	data.participantObserverReentryViolation = false
	data.participantObserverShutdownRequested = false
end

local function beginParticipantObserverOperation(
	data: ServiceData,
	operation: ParticipantObserverOperation
): ParticipantObserverError?
	if data.participantObserverOperationActive then
		data.participantObserverReentryViolation = true
		return makeParticipantObserverError("REENTRANT", operation)
	end
	-- BaseDefeat closes ordinary callbacks before it commits Results, but owners
	-- must still be able to revoke an authentic participant-observer handle.
	-- Detach is cleanup-only: it neither composes nor dispatches a snapshot.
	local detachOnly = operation == "detachParticipantObserver"
	if
		not data.available
		or (not detachOnly and not data.callbacksEnabled)
		or (data.state ~= "Initialized" and data.state ~= "Started")
	then
		return makeParticipantObserverError("UNAVAILABLE", operation)
	end
	data.participantObserverOperationActive = true
	data.participantObserverReentryViolation = false
	data.participantObserverShutdownRequested = false
	return nil
end

local function participantObserverOperationIntact(data: ServiceData): boolean
	return data.participantObserverOperationActive
		and not data.participantObserverReentryViolation
		and not data.participantObserverShutdownRequested
		and data.available
		and data.callbacksEnabled
		and (data.state == "Initialized" or data.state == "Started")
end

local function endParticipantObserverOperation(data: ServiceData): boolean
	local intact = not data.participantObserverReentryViolation and not data.participantObserverShutdownRequested
	local shutdownRequested = data.participantObserverShutdownRequested
	data.participantObserverOperationActive = false
	data.participantObserverReentryViolation = false
	data.participantObserverShutdownRequested = false
	if shutdownRequested then
		callNonYielding(shutdown, data)
		return false
	end
	return intact
end

local function participantObserverSnapshotAdvances(data: ServiceData, snapshot: MatchSnapshot): boolean
	local previous = data.participantObserverPendingSnapshot
	return previous ~= nil and snapshot.matchId == previous.matchId and snapshot.revision > previous.revision
end

local function dispatchParticipantObserver(data: ServiceData)
	local status = data.participantObserverStatus
	if status ~= "Reserved" and status ~= "Active" then
		return
	end
	if data.participantObserverOperationActive then
		data.participantObserverReentryViolation = true
		detachParticipantObserverState(data)
		return
	end

	data.participantObserverOperationActive = true
	data.participantObserverReentryViolation = false
	data.participantObserverShutdownRequested = false
	local composed, snapshotValue = callNonYielding(composeSnapshot, data)
	local snapshot = if composed then snapshotValue :: MatchSnapshot? else nil
	if
		snapshot == nil
		or not participantObserverSnapshotAdvances(data, snapshot)
		or not participantObserverOperationIntact(data)
	then
		detachParticipantObserverState(data)
		endParticipantObserverOperation(data)
		return
	end

	data.participantObserverPendingSnapshot = snapshot
	if status == "Active" then
		local adapter = data.participantObserverAdapter
		local handle = data.participantObserverHandle
		local callbackCalled = false
		local callbackValue: unknown = nil
		if adapter ~= nil then
			callbackCalled, callbackValue = callNonYielding(adapter.onSnapshot, adapter, snapshot)
		end
		if
			not callbackCalled
			or callbackValue ~= true
			or handle == nil
			or not participantObserverHandleMatches(data, handle)
			or data.participantObserverStatus ~= "Active"
			or not participantObserverOperationIntact(data)
		then
			detachParticipantObserverState(data)
		end
	end
	endParticipantObserverOperation(data)
end

local function publishCurrentSnapshot(data: ServiceData): boolean
	if not data.callbacksEnabled or not data.available then
		return false
	end
	local broadcaster = data.snapshotBroadcaster
	local snapshot = composeSnapshot(data)
	if broadcaster == nil or snapshot == nil then
		failClosedAtRuntime(data, "SNAPSHOT_COMPOSITION_FAILED")
		return false
	end

	local published, publishResult = pcall(broadcaster.publish, broadcaster, snapshot)
	if not published or not isSuccess(publishResult) or not data.available then
		failClosedAtRuntime(data, "SNAPSHOT_PUBLICATION_FAILED")
		return false
	end
	return true
end

local function collectRecipients(data: ServiceData): { SnapshotRecipientRecord }?
	local playerSource = data.playerSource
	local roster = data.roster
	if not data.callbacksEnabled or playerSource == nil or roster == nil then
		return nil
	end

	local called, playersValue = pcall(playerSource.getPlayers, playerSource)
	if not called or not isDenseArray(playersValue) then
		return nil
	end
	local recipients: { SnapshotRecipientRecord } = {}
	local seenUserIds: { [number]: boolean } = {}
	local seenConnections: { [any]: boolean } = {}
	for _, connection in playersValue :: { unknown } do
		local userId = readUserId(playerSource, connection)
		if userId ~= nil then
			local resolved, resolveResult = pcall(roster.resolveConnection, roster, connection)
			if not resolved then
				return nil
			elseif isSuccess(resolveResult) then
				local participant = (resolveResult :: any).value
				if
					type(participant) ~= "table"
					or (participant :: any).userId ~= userId
					or seenUserIds[userId] == true
					or seenConnections[connection :: any] == true
					or #recipients >= MAX_PARTICIPANTS
				then
					return nil
				end
				seenUserIds[userId] = true
				seenConnections[connection :: any] = true
				table.insert(
					recipients,
					table.freeze({
						recipient = connection,
						userId = userId,
					})
				)
			else
				local errorCode = resultErrorCode(resolveResult)
				if errorCode == nil or BENIGN_RESOLVE_ERRORS[errorCode] ~= true then
					return nil
				end
			end
		end
	end

	table.sort(recipients, function(left, right)
		return left.userId < right.userId
	end)
	return table.freeze(recipients)
end

local function currentBaseDefeatTokenData(data: ServiceData): BaseDefeatTokenData?
	local token = data.baseDefeatToken
	local tokenData = if token == nil then nil else BASE_DEFEAT_TOKEN_DATA[token]
	if tokenData == nil or tokenData.owner ~= data then
		return nil
	end
	return tokenData
end

local function committedBaseDefeatRecipients(data: ServiceData): { SnapshotRecipientRecord }?
	local tokenData = currentBaseDefeatTokenData(data)
	if data.baseDefeatCommitted and tokenData ~= nil and tokenData.state == "Committed" then
		return tokenData.terminalRecipients
	end
	return nil
end

local function afterRosterMutation(data: ServiceData): boolean
	local machine = data.machine
	if machine == nil or not touchRevision(machine) then
		return false
	end
	local stateSnapshot = detachedStateSnapshot(machine)
	if stateSnapshot == nil then
		return false
	end
	if stateSnapshot.state == "ReadyCheck" then
		local coordinator = data.readyCoordinator
		if coordinator == nil then
			return false
		end
		local coordinated, coordinatorResult = pcall(coordinator.onRosterChanged, coordinator)
		if not coordinated or not isSuccess(coordinatorResult) or not data.available then
			return false
		end
	elseif data.state == "Started" then
		if not publishCurrentSnapshot(data) then
			return false
		end
	end
	dispatchParticipantObserver(data)
	return true
end

local function connectParticipant(data: ServiceData, connection: unknown, capturedUserId: number?): boolean
	if not data.callbacksEnabled then
		return true
	end
	local machine = data.machine
	local roster = data.roster
	local playerSource = data.playerSource
	if machine == nil or roster == nil or playerSource == nil then
		return false
	end
	local stateSnapshot = detachedStateSnapshot(machine)
	if stateSnapshot == nil then
		return false
	elseif stateSnapshot.state == "Closing" then
		return true
	end
	local userId = capturedUserId or readUserId(playerSource, connection)
	if userId == nil then
		return true
	end

	local called, resultValue = pcall(roster.connect, roster, connection, userId, stateSnapshot.state)
	if not called then
		return false
	elseif not isSuccess(resultValue) then
		local errorCode = resultErrorCode(resultValue)
		return errorCode ~= nil and BENIGN_CONNECT_ERRORS[errorCode] == true
	end
	local outcome = (resultValue :: any).value
	if type(outcome) ~= "table" or type((outcome :: any).changed) ~= "boolean" then
		return false
	end
	if not (outcome :: any).changed then
		return true
	end
	return afterRosterMutation(data)
end

local function disconnectParticipant(data: ServiceData, connection: unknown): boolean
	if not data.callbacksEnabled then
		return true
	end
	local machine = data.machine
	local roster = data.roster
	if machine == nil or roster == nil then
		return false
	end
	local stateSnapshot = detachedStateSnapshot(machine)
	if stateSnapshot == nil then
		return false
	elseif stateSnapshot.state == "Closing" then
		return true
	end

	local called, resultValue = pcall(roster.disconnect, roster, connection)
	if not called then
		return false
	elseif not isSuccess(resultValue) then
		local errorCode = resultErrorCode(resultValue)
		return errorCode ~= nil and BENIGN_DISCONNECT_ERRORS[errorCode] == true
	end
	return afterRosterMutation(data)
end

local function ownPlayerConnection(
	cleanup: Cleanup.Container,
	playerSource: PlayerSource,
	connector: (PlayerSource, PlayerListener) -> unknown,
	listener: PlayerListener
): boolean
	local connected, connectionValue = pcall(connector, playerSource, listener)
	if not connected or typeof(connectionValue) ~= "RBXScriptConnection" then
		return false
	end
	local owned = pcall(function()
		cleanup:add(connectionValue :: RBXScriptConnection)
	end)
	if not owned then
		pcall(function()
			(connectionValue :: RBXScriptConnection):Disconnect()
		end)
		return false
	end
	return true
end

local function processExistingPlayers(data: ServiceData): boolean
	local playerSource = data.playerSource
	if playerSource == nil then
		return false
	end
	local called, playersValue = pcall(playerSource.getPlayers, playerSource)
	if not called or not isDenseArray(playersValue) then
		return false
	end

	local players = playersValue :: { unknown }
	local existing: { ExistingPlayer } = {}
	for index, connection in players do
		local userId = readUserId(playerSource, connection)
		if userId ~= nil then
			table.insert(existing, {
				connection = connection,
				userId = userId,
				index = index,
			})
		end
	end
	table.sort(existing, function(left, right)
		if left.userId ~= right.userId then
			return left.userId < right.userId
		end
		return left.index < right.index
	end)
	for _, entry in existing do
		if not connectParticipant(data, entry.connection, entry.userId) then
			return false
		end
	end
	return true
end

local function initialize(data: ServiceData)
	requireState(data, "Constructed")
	data.state = "Initializing"

	local mapLoader = data.mapLoader
	local machine = data.machine
	local roster = data.roster
	local playerSource = data.playerSource
	local coordinator = data.readyCoordinator
	local broadcaster = data.snapshotBroadcaster
	if
		mapLoader == nil
		or machine == nil
		or roster == nil
		or playerSource == nil
		or coordinator == nil
		or broadcaster == nil
	then
		failAfterRollback(data, "DEPENDENCY_MISSING")
	end

	local cleanup = Cleanup.new(data.logger, CLEANUP_LABEL)
	data.cleanup = cleanup

	-- Registration order is ownership order; Cleanup releases it in reverse.
	cleanup:add(function()
		cleanupMapLoader(mapLoader :: MapLoaderAdapter)
	end)
	cleanup:add(function()
		cleanupStateMachine(machine :: StateMachineAdapter)
	end)
	cleanup:add(function()
		cleanupRoster(roster :: RosterAdapter)
	end)

	local addedListener: PlayerListener = function(connection)
		if data.callbacksEnabled and not connectParticipant(data, connection, nil) then
			failClosedAtRuntime(data, "PLAYER_ADDED_FAILED")
		end
	end
	local removingListener: PlayerListener = function(connection)
		if data.callbacksEnabled and not disconnectParticipant(data, connection) then
			failClosedAtRuntime(data, "PLAYER_REMOVING_FAILED")
		end
	end
	if
		not ownPlayerConnection(cleanup, playerSource :: PlayerSource, playerSource.connectAdded, addedListener)
		or not ownPlayerConnection(
			cleanup,
			playerSource :: PlayerSource,
			playerSource.connectRemoving,
			removingListener
		)
	then
		failAfterRollback(data, "PLAYER_TRACKING_FAILED")
	end
	cleanup:add(function()
		cleanupSnapshotBroadcaster(broadcaster :: SnapshotBroadcasterAdapter)
	end)
	cleanup:add(function()
		cleanupReadyCoordinator(coordinator :: ReadyCoordinatorAdapter)
	end)
	data.callbacksEnabled = true
	if not processExistingPlayers(data) then
		failAfterRollback(data, "PLAYER_SNAPSHOT_FAILED")
	end

	local loaded, loadResult = pcall((mapLoader :: MapLoaderAdapter).load, mapLoader, data.selectedMapId)
	local loadedSnapshot = if loaded and isSuccess(loadResult) then (loadResult :: any).value else nil
	data.runtimeMapSnapshot = validateRuntimeMapSnapshot(loadedSnapshot, data.selectedMapId)
	data.mapLoaded = data.runtimeMapSnapshot ~= nil
	if not data.mapLoaded and not transition(machine :: StateMachineAdapter, "Closing") then
		failAfterRollback(data, "TRANSITION_FAILED")
	end

	data.state = "Initialized"
end

local function start(data: ServiceData)
	requireState(data, "Initialized")
	data.state = "Starting"

	if data.mapLoaded then
		local coordinator = data.readyCoordinator
		local entered = false
		local enterResult: unknown = nil
		if coordinator ~= nil then
			entered, enterResult = pcall(coordinator.enterReadyCheck, coordinator)
		end
		if not entered or not isSuccess(enterResult) or not data.available then
			failAfterRollback(data, "TRANSITION_FAILED")
		end
	end

	data.state = "Started"
end

shutdown = function(data: ServiceData)
	if data.state == "Shutdown" then
		return
	elseif data.state == "Failed" and data.cleanup == nil then
		if data.shutdownFailure ~= nil then
			error(data.shutdownFailure, 0)
		end
		return
	end
	if data.state ~= "Initialized" and data.state ~= "Started" then
		staticError("INVALID_STATE")
	end
	if
		data.waveActivationOperationActive
		or data.baseDefeatOperationActive
		or data.studioWaveOperationActive
		or data.participantObserverOperationActive
	then
		data.callbacksEnabled = false
		if data.waveActivationOperationActive then
			data.waveActivationShutdownRequested = true
		end
		if data.baseDefeatOperationActive then
			data.baseDefeatShutdownRequested = true
		end
		if data.studioWaveOperationActive then
			data.studioWaveShutdownRequested = true
		end
		if data.participantObserverOperationActive then
			data.participantObserverShutdownRequested = true
		end
		return
	end
	data.state = "ShuttingDown"
	data.callbacksEnabled = false

	local transitionSucceeded = clearWaveActivationClaim(data, true)
	if not clearBaseDefeatClaim(data, true) then
		transitionSucceeded = false
	end
	local machine = data.machine
	if machine == nil then
		transitionSucceeded = false
	else
		local current = detachedStateSnapshot(machine)
		if current == nil then
			transitionSucceeded = false
		elseif transitionSucceeded and current.state ~= "Closing" then
			transitionSucceeded = transition(machine, "Closing")
		end
	end

	local cleaned, cleanupFailure = releaseOwnedResources(data)
	if not cleaned then
		data.state = "Failed"
		data.shutdownFailure = cleanupFailure
		error(cleanupFailure :: string, 0)
	elseif not transitionSucceeded then
		data.state = "Failed"
		data.shutdownFailure = `{STATIC_ERROR_PREFIX}[code=TRANSITION_FAILED]`
		error(data.shutdownFailure, 0)
	end

	data.state = "Shutdown"
end

local function beginStudioWaveOperation(data: ServiceData): StudioWaveError?
	if data.waveActivationOperationActive then
		data.waveActivationReentryViolation = true
		return table.freeze({
			code = "REENTRANT",
			operation = "activateStudioWaveForEvidence",
		})
	end
	if data.studioWaveOperationActive then
		data.studioWaveReentryViolation = true
		return table.freeze({
			code = "REENTRANT",
			operation = "activateStudioWaveForEvidence",
		})
	end
	if data.baseDefeatOperationActive then
		data.baseDefeatReentryViolation = true
		return table.freeze({
			code = "REENTRANT",
			operation = "activateStudioWaveForEvidence",
		})
	end
	if data.state ~= "Started" or not data.available or not data.callbacksEnabled then
		return table.freeze({
			code = "UNAVAILABLE",
			operation = "activateStudioWaveForEvidence",
		})
	end
	data.studioWaveOperationActive = true
	data.studioWaveReentryViolation = false
	data.studioWaveShutdownRequested = false
	return nil
end

local function endStudioWaveOperation(data: ServiceData): boolean
	data.studioWaveOperationActive = false
	data.studioWaveReentryViolation = false
	if not data.studioWaveShutdownRequested then
		return true
	end
	data.studioWaveShutdownRequested = false
	local shutdownCalled = callNonYielding(shutdown, data)
	return shutdownCalled
end

local function failStudioWaveOperation(data: ServiceData, code: string): Result.Failure<StudioWaveError>
	endStudioWaveOperation(data)
	callNonYielding(failClosedAtRuntime, data, code)
	return studioWaveFailure("INTERNAL_ERROR")
end

local function studioWaveOperationIntact(data: ServiceData): boolean
	return data.studioWaveOperationActive
		and not data.studioWaveReentryViolation
		and not data.studioWaveShutdownRequested
		and data.state == "Started"
		and data.available
		and data.callbacksEnabled
end

local function matchesStateSnapshot(
	value: unknown,
	matchId: Ids.MatchId,
	revision: number,
	state: MatchStateMachine.MatchState
): boolean
	if type(value) ~= "table" or not table.isfrozen(value :: any) then
		return false
	end
	local snapshot = value :: any
	local fieldCount = 0
	for fieldName in next, snapshot do
		if fieldName ~= "matchId" and fieldName ~= "revision" and fieldName ~= "state" then
			return false
		end
		fieldCount += 1
	end
	return fieldCount == 3 and snapshot.matchId == matchId and snapshot.revision == revision and snapshot.state == state
end

local function isAcceptedSnapshotPublishResult(value: unknown): boolean
	if type(value) ~= "table" or not table.isfrozen(value :: any) then
		return false
	end
	local resultValue = value :: any
	local resultFieldCount = 0
	for fieldName in next, resultValue do
		if fieldName ~= "ok" and fieldName ~= "value" then
			return false
		end
		resultFieldCount += 1
	end
	local outcome = resultValue.value
	if resultFieldCount ~= 2 or resultValue.ok ~= true or type(outcome) ~= "table" or not table.isfrozen(outcome) then
		return false
	end
	local outcomeFieldCount = 0
	for fieldName in next, outcome do
		if fieldName ~= "kind" then
			return false
		end
		outcomeFieldCount += 1
	end
	return outcomeFieldCount == 1 and (outcome.kind == "Sent" or outcome.kind == "Queued" or outcome.kind == "Replaced")
end

function ServiceMethods.activateStudioWaveForEvidence(self: Service): Result.Result<MatchSnapshot, StudioWaveError>
	local data = requireData(self)
	local operationError = beginStudioWaveOperation(data)
	if operationError ~= nil then
		return Result.err(operationError)
	end

	local isStudio = data.isStudio
	if isStudio == nil then
		return failStudioWaveOperation(data, "STUDIO_WAVE_PREDICATE_MISSING")
	end
	local studioCalled, studioValue = callNonYielding(isStudio)
	if not studioCalled or type(studioValue) ~= "boolean" or not studioWaveOperationIntact(data) then
		return failStudioWaveOperation(data, "STUDIO_WAVE_PREDICATE_FAILED")
	end
	if studioValue ~= true then
		endStudioWaveOperation(data)
		return studioWaveFailure("NOT_STUDIO")
	end
	if
		data.studioWaveActivated
		or data.waveActivationToken ~= nil
		or data.waveActivationCommitted
		or data.baseDefeatToken ~= nil
		or data.baseDefeatCommitted
	then
		endStudioWaveOperation(data)
		return studioWaveFailure("REENTRANT")
	end

	local machine = data.machine
	if machine == nil then
		return failStudioWaveOperation(data, "STUDIO_WAVE_MACHINE_MISSING")
	end
	local stateCalled, currentValue = callNonYielding(detachedStateSnapshot, machine)
	local current = if stateCalled then currentValue :: MatchStateMachine.StateSnapshot? else nil
	if current == nil or not studioWaveOperationIntact(data) then
		return failStudioWaveOperation(data, "STUDIO_WAVE_STATE_FAILED")
	end
	if current.state ~= "PreWave" then
		endStudioWaveOperation(data)
		return studioWaveFailure("WRONG_STATE")
	end
	if current.revision >= Validation.MAX_SAFE_INTEGER then
		return failStudioWaveOperation(data, "STUDIO_WAVE_REVISION_EXHAUSTED")
	end

	local snapshotCalled, beforeValue = callNonYielding(composeSnapshot, data)
	local before = if snapshotCalled then beforeValue :: MatchSnapshot? else nil
	if
		before == nil
		or before.matchId ~= current.matchId
		or before.revision ~= current.revision
		or before.state ~= "PreWave"
		or before.deadlineServerTime ~= nil
		or not studioWaveOperationIntact(data)
	then
		return failStudioWaveOperation(data, "STUDIO_WAVE_PREFLIGHT_FAILED")
	end

	local began, beginResult = callNonYielding(machine.beginTransition, machine, "WaveActive", current.revision)
	local machineToken = if began and isSuccess(beginResult) then (beginResult :: any).value else nil
	if
		not began
		or not isSuccess(beginResult)
		or not table.isfrozen(beginResult :: any)
		or type(machineToken) ~= "table"
		or not studioWaveOperationIntact(data)
	then
		if machineToken ~= nil then
			callNonYielding(machine.rollbackTransition, machine, machineToken)
		end
		return failStudioWaveOperation(data, "STUDIO_WAVE_BEGIN_FAILED")
	end

	local committed, commitResult = callNonYielding(machine.commitTransition, machine, machineToken)
	local committedValue = if committed and isSuccess(commitResult) then (commitResult :: any).value else nil
	local currentCalled, afterStateValue = callNonYielding(detachedStateSnapshot, machine)
	local afterState = if currentCalled then afterStateValue :: MatchStateMachine.StateSnapshot? else nil
	local expectedRevision = current.revision + 1
	if
		not committed
		or not isSuccess(commitResult)
		or not table.isfrozen(commitResult :: any)
		or not matchesStateSnapshot(committedValue, current.matchId, expectedRevision, "WaveActive")
		or afterState == nil
		or afterState.matchId ~= current.matchId
		or afterState.revision ~= expectedRevision
		or afterState.state ~= "WaveActive"
		or not studioWaveOperationIntact(data)
	then
		callNonYielding(machine.rollbackTransition, machine, machineToken)
		return failStudioWaveOperation(data, "STUDIO_WAVE_COMMIT_FAILED")
	end

	local composed, snapshotValue = callNonYielding(composeSnapshot, data)
	local snapshot = if composed then snapshotValue :: MatchSnapshot? else nil
	if
		snapshot == nil
		or snapshot.matchId ~= current.matchId
		or snapshot.revision ~= expectedRevision
		or snapshot.state ~= "WaveActive"
		or snapshot.deadlineServerTime ~= nil
		or not studioWaveOperationIntact(data)
	then
		return failStudioWaveOperation(data, "STUDIO_WAVE_POSTCONDITION_FAILED")
	end

	data.studioWaveActivated = true
	local broadcaster = data.snapshotBroadcaster
	if broadcaster == nil then
		return failStudioWaveOperation(data, "STUDIO_WAVE_PUBLISHER_MISSING")
	end
	local publishCalled, publishResult = callNonYielding(broadcaster.publish, broadcaster, snapshot)
	if
		not publishCalled
		or not isAcceptedSnapshotPublishResult(publishResult)
		or not studioWaveOperationIntact(data)
	then
		return failStudioWaveOperation(data, "STUDIO_WAVE_PUBLICATION_FAILED")
	end

	if not endStudioWaveOperation(data) then
		return studioWaveFailure("INTERNAL_ERROR")
	end
	return Result.ok(snapshot)
end

function ServiceMethods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	local data = requireData(self)
	return data.serviceDefinition :: ServiceLifecycle.ServiceDefinition
end

function ServiceMethods.getLifecycleState(self: Service): LifecycleState
	return requireData(self).state
end

function ServiceMethods.getSnapshot(self: Service): Result.Result<MatchSnapshot, SnapshotError>
	local data = requireData(self)
	if not data.available or data.state == "ShuttingDown" or data.state == "Shutdown" or data.state == "Failed" then
		return snapshotFailure("UNAVAILABLE")
	end
	local snapshot = composeSnapshot(data)
	if snapshot == nil then
		return snapshotFailure("INTERNAL_ERROR")
	end
	return Result.ok(snapshot)
end

function ServiceMethods.reserveParticipantObserver(
	self: Service,
	adapterValue: unknown
): Result.Result<
	ParticipantObserverReservation,
	ParticipantObserverError
>
	local data = requireData(self)
	local operation: ParticipantObserverOperation = "reserveParticipantObserver"
	local operationError = beginParticipantObserverOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if data.participantObserverStatus == "Reserved" or data.participantObserverStatus == "Active" then
		endParticipantObserverOperation(data)
		return participantObserverFailure("UNAVAILABLE", operation)
	end
	if
		not isParticipantObserverAdapter(adapterValue)
		or data.participantObserverGeneration >= Validation.MAX_SAFE_INTEGER
	then
		endParticipantObserverOperation(data)
		return participantObserverFailure("INVALID_ARGUMENT", operation)
	end

	local composed, snapshotValue = callNonYielding(composeSnapshot, data)
	local snapshot = if composed then snapshotValue :: MatchSnapshot? else nil
	if snapshot == nil or not participantObserverOperationIntact(data) then
		endParticipantObserverOperation(data)
		return participantObserverFailure("INTERNAL_ERROR", operation)
	end

	local handle = table.freeze({}) :: ParticipantObserverHandle
	local generation = data.participantObserverGeneration + 1
	local previousHandle = data.participantObserverHandle
	if previousHandle ~= nil then
		PARTICIPANT_OBSERVER_HANDLE_DATA[previousHandle] = nil
	end
	data.participantObserverAdapter = adapterValue :: ParticipantObserverAdapter
	data.participantObserverHandle = handle
	data.participantObserverStatus = "Reserved"
	data.participantObserverPendingSnapshot = snapshot
	data.participantObserverGeneration = generation
	PARTICIPANT_OBSERVER_HANDLE_DATA[handle] = {
		owner = data,
		generation = generation,
		status = "Reserved",
	}
	local reservation: ParticipantObserverReservation = table.freeze({
		handle = handle,
		snapshot = snapshot,
	})
	if not endParticipantObserverOperation(data) then
		clearParticipantObserver(data)
		return participantObserverFailure("INTERNAL_ERROR", operation)
	end
	return Result.ok(reservation)
end

function ServiceMethods.refreshParticipantObserver(
	self: Service,
	handleValue: unknown
): Result.Result<MatchSnapshot, ParticipantObserverError>
	local data = requireData(self)
	local operation: ParticipantObserverOperation = "refreshParticipantObserver"
	local operationError = beginParticipantObserverOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if not participantObserverHandleMatches(data, handleValue) then
		endParticipantObserverOperation(data)
		return participantObserverFailure("INVALID_HANDLE", operation)
	end
	if data.participantObserverStatus ~= "Reserved" then
		endParticipantObserverOperation(data)
		return participantObserverFailure("WRONG_STATE", operation)
	end

	local previous = data.participantObserverPendingSnapshot
	local composed, snapshotValue = callNonYielding(composeSnapshot, data)
	local snapshot = if composed then snapshotValue :: MatchSnapshot? else nil
	if
		previous == nil
		or snapshot == nil
		or snapshot.matchId ~= previous.matchId
		or snapshot.revision < previous.revision
		or not participantObserverOperationIntact(data)
	then
		detachParticipantObserverState(data)
		endParticipantObserverOperation(data)
		return participantObserverFailure("INTERNAL_ERROR", operation)
	end
	data.participantObserverPendingSnapshot = snapshot
	if not endParticipantObserverOperation(data) then
		detachParticipantObserverState(data)
		return participantObserverFailure("INTERNAL_ERROR", operation)
	end
	return Result.ok(snapshot)
end

function ServiceMethods.activateParticipantObserver(
	self: Service,
	handleValue: unknown,
	expectedRevision: unknown
): Result.Result<boolean, ParticipantObserverError>
	local data = requireData(self)
	local operation: ParticipantObserverOperation = "activateParticipantObserver"
	local operationError = beginParticipantObserverOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if not participantObserverHandleMatches(data, handleValue) then
		endParticipantObserverOperation(data)
		return participantObserverFailure("INVALID_HANDLE", operation)
	end
	if data.participantObserverStatus ~= "Reserved" then
		endParticipantObserverOperation(data)
		return participantObserverFailure("WRONG_STATE", operation)
	end
	if
		type(expectedRevision) ~= "number"
		or not Validation.isSafeInteger(expectedRevision)
		or expectedRevision < MatchStateMachine.INITIAL_REVISION
	then
		endParticipantObserverOperation(data)
		return participantObserverFailure("INVALID_ARGUMENT", operation)
	end
	local pending = data.participantObserverPendingSnapshot
	if pending == nil or pending.revision ~= expectedRevision then
		endParticipantObserverOperation(data)
		return participantObserverFailure("REVISION_MISMATCH", operation)
	end

	local handleData = PARTICIPANT_OBSERVER_HANDLE_DATA[handleValue :: any]
	if handleData == nil then
		endParticipantObserverOperation(data)
		return participantObserverFailure("INVALID_HANDLE", operation)
	end
	data.participantObserverStatus = "Active"
	handleData.status = "Active"
	if not endParticipantObserverOperation(data) then
		detachParticipantObserverState(data)
		return participantObserverFailure("INTERNAL_ERROR", operation)
	end
	return PARTICIPANT_OBSERVER_ACTIVATION_SUCCESS
end

function ServiceMethods.detachParticipantObserver(
	self: Service,
	handleValue: unknown
): Result.Result<boolean, ParticipantObserverError>
	local data = requireData(self)
	local operation: ParticipantObserverOperation = "detachParticipantObserver"
	local operationError = beginParticipantObserverOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if not participantObserverHandleMatches(data, handleValue) then
		endParticipantObserverOperation(data)
		return participantObserverFailure("INVALID_HANDLE", operation)
	end
	local detached = detachParticipantObserverState(data)
	if not endParticipantObserverOperation(data) then
		return participantObserverFailure("INTERNAL_ERROR", operation)
	end
	return Result.ok(detached)
end

function ServiceMethods.getRuntimeMapSnapshot(self: Service): Result.Result<RuntimeMapSnapshot, RuntimeMapSnapshotError>
	local data = requireData(self)
	if not data.available or (data.state ~= "Initialized" and data.state ~= "Started") or not data.mapLoaded then
		return runtimeMapSnapshotFailure("UNAVAILABLE")
	end

	local snapshot = data.runtimeMapSnapshot
	if snapshot == nil then
		return runtimeMapSnapshotFailure("INTERNAL_ERROR")
	end
	return Result.ok(snapshot)
end

function ServiceMethods.selectMap(self: Service, mapIdValue: unknown): Result.Result<boolean, MapSelectionError>
	local data = requireData(self)
	local validatedId = Ids.validateMapId(mapIdValue)
	local mapLoader = data.mapLoader
	if
		not validatedId.ok
		or not data.available
		or (data.state ~= "Initialized" and data.state ~= "Started")
		or data.waveActivationCommitted
		or data.baseDefeatCommitted
		or data.studioWaveActivated
		or mapLoader == nil
		or type((mapLoader :: any).unload) ~= "function"
	then
		return Result.err(table.freeze({ code = "UNAVAILABLE", operation = "selectMap" }))
	end
	if data.runtimeMapSnapshot ~= nil and data.runtimeMapSnapshot.mapId == validatedId.value then
		return Result.ok(false)
	end

	local previousMapId = data.selectedMapId
	local unloaded, unloadResult = pcall((mapLoader :: any).unload, mapLoader)
	if not unloaded or not isSuccess(unloadResult) then
		return Result.err(table.freeze({ code = "INTERNAL_ERROR", operation = "selectMap" }))
	end
	data.mapLoaded = false
	data.runtimeMapSnapshot = nil
	local loaded, loadResult = pcall((mapLoader :: MapLoaderAdapter).load, mapLoader, validatedId.value)
	local loadedSnapshot = if loaded and isSuccess(loadResult) then (loadResult :: any).value else nil
	local snapshot = validateRuntimeMapSnapshot(loadedSnapshot, validatedId.value)
	if snapshot ~= nil then
		data.selectedMapId = validatedId.value
		data.runtimeMapSnapshot = snapshot
		data.mapLoaded = true
		return Result.ok(true)
	end

	-- Restore the development map when selection fails so direct Studio work and
	-- a later authenticated arrival never inherit a half-loaded lifecycle.
	local rollbackLoaded, rollbackResult = pcall((mapLoader :: MapLoaderAdapter).load, mapLoader, previousMapId)
	local rollbackValue = if rollbackLoaded and isSuccess(rollbackResult) then (rollbackResult :: any).value else nil
	local rollbackSnapshot = validateRuntimeMapSnapshot(rollbackValue, previousMapId)
	if rollbackSnapshot ~= nil then
		data.runtimeMapSnapshot = rollbackSnapshot
		data.mapLoaded = true
	else
		data.available = false
	end
	return Result.err(table.freeze({ code = "UNAVAILABLE", operation = "selectMap" }))
end

function ServiceMethods.isRuntimeMapSnapshot(self: Service, value: unknown): boolean
	local data = requireData(self)
	local retained = data.runtimeMapSnapshot
	return data.available and data.mapLoaded and retained ~= nil and value == retained
end

function ServiceMethods.getConnectedRecipients(
	self: Service
): Result.Result<{ ConnectedRecipient }, ConnectedRecipientsError>
	local data = requireData(self)
	if not data.available or not data.callbacksEnabled or (data.state ~= "Initialized" and data.state ~= "Started") then
		return connectedRecipientsFailure("UNAVAILABLE")
	end

	local recipients = collectRecipients(data)
	if recipients == nil then
		return connectedRecipientsFailure("INTERNAL_ERROR")
	end
	return Result.ok(recipients)
end

function ServiceMethods.getCommittedBaseDefeatRecipients(self: Service): Result.Result<
	{ ConnectedRecipient },
	CommittedBaseDefeatRecipientsError
>
	local data = requireData(self)
	if not data.available or data.state ~= "Started" or data.baseDefeatOperationActive then
		return committedBaseDefeatRecipientsFailure("UNAVAILABLE")
	end
	if not data.baseDefeatCommitted then
		return committedBaseDefeatRecipientsFailure("UNAVAILABLE")
	end

	local tokenData = currentBaseDefeatTokenData(data)
	local recipients = committedBaseDefeatRecipients(data)
	if
		data.callbacksEnabled
		or tokenData == nil
		or tokenData.state ~= "Committed"
		or tokenData.outcome == nil
		or recipients == nil
	then
		return committedBaseDefeatRecipientsFailure("INTERNAL_ERROR")
	end
	return Result.ok(recipients)
end

function ServiceMethods.submitReady(
	self: Service,
	connection: unknown,
	matchId: unknown,
	observedRevision: unknown
): Result.Result<MatchSnapshot, ReadyError>
	local data = requireData(self)
	if not data.available or not data.callbacksEnabled or data.state ~= "Started" then
		return readyFailure("UNAVAILABLE")
	end
	local coordinator = data.readyCoordinator
	if coordinator == nil then
		return readyFailure("UNAVAILABLE")
	end

	local submitted, resultValue = pcall(coordinator.submitReady, coordinator, connection, matchId, observedRevision)
	if not submitted or not isSuccess(resultValue) then
		local rawCode = if submitted then resultErrorCode(resultValue) else nil
		local code: ReadyErrorCode = if rawCode == "STALE_REQUEST"
				or rawCode == "DUPLICATE_REQUEST"
				or rawCode == "NOT_AUTHORIZED"
				or rawCode == "UNAVAILABLE"
			then rawCode
			else "INTERNAL_ERROR"
		if code == "INTERNAL_ERROR" then
			failClosedAtRuntime(data, "READY_SUBMISSION_FAILED")
		end
		return readyFailure(code)
	end
	if not data.available then
		return readyFailure("INTERNAL_ERROR")
	end
	local snapshot = composeSnapshot(data)
	if snapshot == nil then
		failClosedAtRuntime(data, "READY_SNAPSHOT_FAILED")
		return readyFailure("INTERNAL_ERROR")
	end
	return Result.ok(snapshot)
end

local function beginWaveActivationOperation(data: ServiceData, operation: WaveActivationOperation): WaveActivationError?
	if data.waveActivationOperationActive then
		data.waveActivationReentryViolation = true
		return makeWaveActivationError("REENTRANT", operation)
	end
	if data.studioWaveOperationActive then
		data.studioWaveReentryViolation = true
		return makeWaveActivationError("REENTRANT", operation)
	end
	if data.baseDefeatOperationActive then
		data.baseDefeatReentryViolation = true
		return makeWaveActivationError("REENTRANT", operation)
	end
	if data.state ~= "Started" or not data.available then
		return makeWaveActivationError("UNAVAILABLE", operation)
	end
	data.waveActivationOperationActive = true
	data.waveActivationReentryViolation = false
	return nil
end

local function endWaveActivationOperation(data: ServiceData)
	data.waveActivationOperationActive = false
	data.waveActivationReentryViolation = false
	if data.waveActivationShutdownRequested then
		data.waveActivationShutdownRequested = false
		shutdown(data)
	end
end

local function failWaveActivationOperation(
	data: ServiceData,
	operation: WaveActivationOperation,
	code: string
): Result.Failure<WaveActivationError>
	endWaveActivationOperation(data)
	failClosedAtRuntime(data, code)
	return waveActivationFailure("INTERNAL_ERROR", operation)
end

local function waveActivationOperationIntact(data: ServiceData): boolean
	return data.waveActivationOperationActive
		and not data.waveActivationReentryViolation
		and not data.waveActivationShutdownRequested
		and data.state == "Started"
		and data.available
		and data.callbacksEnabled
end

local function prepareWaveActiveSnapshot(
	data: ServiceData,
	stateSnapshot: MatchStateMachine.StateSnapshot
): MatchSnapshot?
	if stateSnapshot.revision >= Validation.MAX_SAFE_INTEGER then
		return nil
	end
	local current = composeSnapshot(data)
	if
		current == nil
		or current.matchId ~= stateSnapshot.matchId
		or current.revision ~= stateSnapshot.revision
		or current.state ~= "PreWave"
		or current.deadlineServerTime ~= nil
	then
		return nil
	end
	local validated = MatchProtocol.validateMatchSnapshot({
		matchId = current.matchId,
		revision = current.revision + 1,
		state = "WaveActive",
		deadlineServerTime = nil,
		participants = current.participants,
	})
	return if validated.ok then validated.value else nil
end

local function waveActivationTokenDataFor(data: ServiceData, tokenValue: unknown): WaveActivationTokenData?
	if type(tokenValue) ~= "table" then
		return nil
	end
	local tokenData = WAVE_ACTIVATION_TOKEN_DATA[tokenValue :: any]
	if tokenData == nil or tokenData.owner ~= data or data.waveActivationToken ~= tokenValue then
		return nil
	end
	return tokenData
end

local function revokeWaveActivationToken(data: ServiceData, tokenValue: unknown, tokenData: WaveActivationTokenData)
	tokenData.machineToken = nil
	tokenData.state = "RolledBack"
	WAVE_ACTIVATION_TOKEN_DATA[tokenValue :: any] = nil
	data.waveActivationToken = nil
end

function ServiceMethods.beginWaveActivation(
	self: Service,
	matchIdValue: unknown
): Result.Result<WaveActivationToken, WaveActivationError>
	local data = requireData(self)
	local operation: WaveActivationOperation = "beginWaveActivation"
	local operationError = beginWaveActivationOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if
		data.waveActivationToken ~= nil
		or data.waveActivationCommitted
		or data.studioWaveActivated
		or data.baseDefeatToken ~= nil
		or data.baseDefeatCommitted
	then
		endWaveActivationOperation(data)
		return waveActivationFailure("REENTRANT", operation)
	end
	if not data.callbacksEnabled then
		endWaveActivationOperation(data)
		return waveActivationFailure("UNAVAILABLE", operation)
	end

	local matchIdResult = Ids.validateMatchId(matchIdValue)
	local machine = data.machine
	if not matchIdResult.ok or machine == nil then
		endWaveActivationOperation(data)
		return waveActivationFailure(if machine == nil then "UNAVAILABLE" else "NOT_AUTHORIZED", operation)
	end
	local current = detachedStateSnapshot(machine)
	if current == nil or not waveActivationOperationIntact(data) then
		return failWaveActivationOperation(data, operation, "WAVE_ACTIVATION_SNAPSHOT_FAILED")
	end
	if current.matchId ~= matchIdResult.value then
		endWaveActivationOperation(data)
		return waveActivationFailure("NOT_AUTHORIZED", operation)
	end
	if current.state ~= "PreWave" then
		endWaveActivationOperation(data)
		return waveActivationFailure("WRONG_STATE", operation)
	end

	local preparedSnapshot = prepareWaveActiveSnapshot(data, current)
	if preparedSnapshot == nil or not waveActivationOperationIntact(data) then
		return failWaveActivationOperation(data, operation, "WAVE_ACTIVATION_PREFLIGHT_FAILED")
	end
	local began, beginResult = callNonYielding(machine.beginTransition, machine, "WaveActive", current.revision)
	local machineToken = if began and isSuccess(beginResult) then (beginResult :: any).value else nil
	local afterBegin = detachedStateSnapshot(machine)
	if
		not began
		or not isSuccess(beginResult)
		or type(machineToken) ~= "table"
		or afterBegin == nil
		or afterBegin.matchId ~= current.matchId
		or afterBegin.revision ~= current.revision
		or afterBegin.state ~= "PreWave"
		or not waveActivationOperationIntact(data)
	then
		if machineToken ~= nil then
			callNonYielding(machine.rollbackTransition, machine, machineToken)
		end
		return failWaveActivationOperation(data, operation, "WAVE_ACTIVATION_BEGIN_FAILED")
	end

	local token = table.freeze({}) :: WaveActivationToken
	WAVE_ACTIVATION_TOKEN_DATA[token] = {
		owner = data,
		state = "Prepared",
		machineToken = machineToken,
		preparedSnapshot = preparedSnapshot,
		preparedRevision = current.revision,
		outcome = nil,
	}
	data.waveActivationToken = token
	endWaveActivationOperation(data)
	return Result.ok(token)
end

function ServiceMethods.commitWaveActivation(
	self: Service,
	tokenValue: unknown
): Result.Result<WaveActivationCommitOutcome, WaveActivationError>
	local data = requireData(self)
	local operation: WaveActivationOperation = "commitWaveActivation"
	local operationError = beginWaveActivationOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local tokenData = waveActivationTokenDataFor(data, tokenValue)
	if tokenData == nil then
		endWaveActivationOperation(data)
		return waveActivationFailure("INVALID_TOKEN", operation)
	end
	if tokenData.state == "Committed" then
		local outcome = tokenData.outcome
		endWaveActivationOperation(data)
		if outcome == nil then
			return waveActivationFailure("INTERNAL_ERROR", operation)
		end
		return Result.ok(outcome)
	elseif tokenData.state ~= "Prepared" then
		endWaveActivationOperation(data)
		return waveActivationFailure("INVALID_TOKEN", operation)
	end

	local machine = data.machine
	local machineToken = tokenData.machineToken
	if machine == nil or machineToken == nil then
		return failWaveActivationOperation(data, operation, "WAVE_ACTIVATION_COMMIT_MISSING")
	end
	local before = detachedStateSnapshot(machine)
	if
		before == nil
		or before.matchId ~= tokenData.preparedSnapshot.matchId
		or before.revision ~= tokenData.preparedRevision
		or before.state ~= "PreWave"
		or not waveActivationOperationIntact(data)
	then
		callNonYielding(machine.rollbackTransition, machine, machineToken)
		revokeWaveActivationToken(data, tokenValue, tokenData)
		return failWaveActivationOperation(data, operation, "WAVE_ACTIVATION_STALE_PREPARE")
	end

	local committedCall, commitResult = callNonYielding(machine.commitTransition, machine, machineToken)
	local committedValue = if committedCall and isSuccess(commitResult) then (commitResult :: any).value else nil
	local current = detachedStateSnapshot(machine)
	local expected = tokenData.preparedSnapshot
	local transitionCommitted = current ~= nil
		and current.matchId == expected.matchId
		and current.revision == expected.revision
		and current.state == "WaveActive"
	if not transitionCommitted then
		callNonYielding(machine.rollbackTransition, machine, machineToken)
		revokeWaveActivationToken(data, tokenValue, tokenData)
		return failWaveActivationOperation(data, operation, "WAVE_ACTIVATION_COMMIT_FAILED")
	end

	tokenData.machineToken = nil
	tokenData.state = "Committed"
	data.waveActivationCommitted = true
	local composed = composeSnapshot(data)
	local snapshotMatches = composed ~= nil
		and composed.matchId == expected.matchId
		and composed.revision == expected.revision
		and composed.state == "WaveActive"
		and composed.deadlineServerTime == nil
	local published = false
	local broadcaster = data.snapshotBroadcaster
	if
		committedCall
		and isSuccess(commitResult)
		and matchesStateSnapshot(committedValue, expected.matchId, expected.revision, "WaveActive")
		and snapshotMatches
		and waveActivationOperationIntact(data)
		and broadcaster ~= nil
	then
		local publishCalled, publishResult = callNonYielding(broadcaster.publish, broadcaster, expected)
		published = publishCalled
			and isAcceptedSnapshotPublishResult(publishResult)
			and waveActivationOperationIntact(data)
	end
	local outcome: WaveActivationCommitOutcome = table.freeze({
		committed = true,
		published = published,
		snapshot = expected,
	})
	tokenData.outcome = outcome
	endWaveActivationOperation(data)
	return Result.ok(outcome)
end

function ServiceMethods.rollbackWaveActivation(
	self: Service,
	tokenValue: unknown
): Result.Result<boolean, WaveActivationError>
	local data = requireData(self)
	local operation: WaveActivationOperation = "rollbackWaveActivation"
	local operationError = beginWaveActivationOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local tokenData = waveActivationTokenDataFor(data, tokenValue)
	if tokenData == nil or tokenData.state ~= "Prepared" then
		endWaveActivationOperation(data)
		return waveActivationFailure("INVALID_TOKEN", operation)
	end

	local machine = data.machine
	local machineToken = tokenData.machineToken
	if machine == nil or machineToken == nil then
		return failWaveActivationOperation(data, operation, "WAVE_ACTIVATION_ROLLBACK_MISSING")
	end
	local rolledBack, rollbackResult = callNonYielding(machine.rollbackTransition, machine, machineToken)
	local current = detachedStateSnapshot(machine)
	local rollbackConfirmed = current ~= nil
		and current.matchId == tokenData.preparedSnapshot.matchId
		and current.revision == tokenData.preparedRevision
		and current.state == "PreWave"
	if
		not rolledBack
		or not isSuccess(rollbackResult)
		or not rollbackConfirmed
		or data.waveActivationReentryViolation
	then
		revokeWaveActivationToken(data, tokenValue, tokenData)
		return failWaveActivationOperation(data, operation, "WAVE_ACTIVATION_ROLLBACK_FAILED")
	end

	revokeWaveActivationToken(data, tokenValue, tokenData)
	endWaveActivationOperation(data)
	return Result.ok(true)
end

local function beginBaseDefeatOperation(data: ServiceData, operation: BaseDefeatOperation): BaseDefeatError?
	if data.waveActivationOperationActive then
		data.waveActivationReentryViolation = true
		return makeBaseDefeatError("REENTRANT", operation)
	end
	if data.studioWaveOperationActive then
		data.studioWaveReentryViolation = true
		return makeBaseDefeatError("REENTRANT", operation)
	end
	if data.baseDefeatOperationActive then
		data.baseDefeatReentryViolation = true
		return makeBaseDefeatError("REENTRANT", operation)
	end
	if data.state ~= "Started" or not data.available then
		return makeBaseDefeatError("UNAVAILABLE", operation)
	end
	data.baseDefeatOperationActive = true
	data.baseDefeatReentryViolation = false
	return nil
end

local function endBaseDefeatOperation(data: ServiceData)
	data.baseDefeatOperationActive = false
	if data.baseDefeatShutdownRequested then
		data.baseDefeatShutdownRequested = false
		shutdown(data)
	end
end

local function failBaseDefeatOperation(
	data: ServiceData,
	operation: BaseDefeatOperation,
	code: string
): Result.Failure<BaseDefeatError>
	endBaseDefeatOperation(data)
	failClosedAtRuntime(data, code)
	return baseDefeatFailure("INTERNAL_ERROR", operation)
end

local function prepareResultsSnapshot(data: ServiceData, stateSnapshot: MatchStateMachine.StateSnapshot): MatchSnapshot?
	if stateSnapshot.revision >= Validation.MAX_SAFE_INTEGER then
		return nil
	end
	local current = composeSnapshot(data)
	if
		current == nil
		or current.matchId ~= stateSnapshot.matchId
		or current.revision ~= stateSnapshot.revision
		or current.state ~= "WaveActive"
		or current.deadlineServerTime ~= nil
	then
		return nil
	end
	local validated = MatchProtocol.validateMatchSnapshot({
		matchId = current.matchId,
		revision = current.revision + 1,
		state = "Results",
		deadlineServerTime = nil,
		participants = current.participants,
	})
	return if validated.ok then validated.value else nil
end

local function tokenDataFor(data: ServiceData, tokenValue: unknown): BaseDefeatTokenData?
	if type(tokenValue) ~= "table" then
		return nil
	end
	local tokenData = BASE_DEFEAT_TOKEN_DATA[tokenValue :: any]
	if tokenData == nil or tokenData.owner ~= data or data.baseDefeatToken ~= tokenValue then
		return nil
	end
	return tokenData
end

function ServiceMethods.beginBaseDefeat(
	self: Service,
	matchIdValue: unknown
): Result.Result<BaseDefeatToken, BaseDefeatError>
	local data = requireData(self)
	local operation: BaseDefeatOperation = "beginBaseDefeat"
	local operationError = beginBaseDefeatOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if data.baseDefeatToken ~= nil or data.baseDefeatCommitted or not data.callbacksEnabled then
		endBaseDefeatOperation(data)
		return baseDefeatFailure("REENTRANT", operation)
	end

	local matchIdResult = Ids.validateMatchId(matchIdValue)
	local machine = data.machine
	if not matchIdResult.ok or machine == nil then
		endBaseDefeatOperation(data)
		return baseDefeatFailure(if machine == nil then "UNAVAILABLE" else "NOT_AUTHORIZED", operation)
	end
	local current = detachedStateSnapshot(machine)
	if current == nil then
		return failBaseDefeatOperation(data, operation, "BASE_DEFEAT_SNAPSHOT_FAILED")
	end
	if current.matchId ~= matchIdResult.value then
		endBaseDefeatOperation(data)
		return baseDefeatFailure("NOT_AUTHORIZED", operation)
	end
	if current.state ~= "WaveActive" then
		endBaseDefeatOperation(data)
		return baseDefeatFailure("WRONG_STATE", operation)
	end

	local terminalRecipients = collectRecipients(data)
	if terminalRecipients == nil then
		return failBaseDefeatOperation(data, operation, "BASE_DEFEAT_RECIPIENTS_FAILED")
	end
	data.callbacksEnabled = false
	local preparedSnapshot = prepareResultsSnapshot(data, current)
	if preparedSnapshot == nil then
		return failBaseDefeatOperation(data, operation, "BASE_DEFEAT_PREFLIGHT_FAILED")
	end
	local began, beginResult = callNonYielding(machine.beginTransition, machine, "Results", current.revision)
	if not began or not isSuccess(beginResult) or data.baseDefeatReentryViolation then
		local machineToken = if began and isSuccess(beginResult) then (beginResult :: any).value else nil
		if machineToken ~= nil then
			callNonYielding(machine.rollbackTransition, machine, machineToken)
		end
		return failBaseDefeatOperation(data, operation, "BASE_DEFEAT_BEGIN_FAILED")
	end

	local token = table.freeze({}) :: BaseDefeatToken
	BASE_DEFEAT_TOKEN_DATA[token] = {
		owner = data,
		state = "Prepared",
		machineToken = (beginResult :: any).value,
		preparedSnapshot = preparedSnapshot,
		terminalRecipients = terminalRecipients,
		outcome = nil,
	}
	data.baseDefeatToken = token
	endBaseDefeatOperation(data)
	return Result.ok(token)
end

function ServiceMethods.commitBaseDefeat(
	self: Service,
	tokenValue: unknown
): Result.Result<BaseDefeatCommitOutcome, BaseDefeatError>
	local data = requireData(self)
	local operation: BaseDefeatOperation = "commitBaseDefeat"
	local operationError = beginBaseDefeatOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local tokenData = tokenDataFor(data, tokenValue)
	if tokenData == nil then
		endBaseDefeatOperation(data)
		return baseDefeatFailure("INVALID_TOKEN", operation)
	end
	if tokenData.state == "Committed" then
		local outcome = tokenData.outcome
		endBaseDefeatOperation(data)
		if outcome == nil then
			return baseDefeatFailure("INTERNAL_ERROR", operation)
		end
		return Result.ok(outcome)
	elseif tokenData.state ~= "Prepared" then
		endBaseDefeatOperation(data)
		return baseDefeatFailure("INVALID_TOKEN", operation)
	end

	local machine = data.machine
	local machineToken = tokenData.machineToken
	if machine == nil or machineToken == nil then
		return failBaseDefeatOperation(data, operation, "BASE_DEFEAT_COMMIT_MISSING")
	end
	local committedCall, commitResult = callNonYielding(machine.commitTransition, machine, machineToken)
	local current = detachedStateSnapshot(machine)
	local expected = tokenData.preparedSnapshot
	local transitionCommitted = current ~= nil
		and current.matchId == expected.matchId
		and current.revision == expected.revision
		and current.state == "Results"
	if not transitionCommitted then
		callNonYielding(machine.rollbackTransition, machine, machineToken)
		tokenData.machineToken = nil
		tokenData.state = "RolledBack"
		BASE_DEFEAT_TOKEN_DATA[tokenValue :: any] = nil
		data.baseDefeatToken = nil
		return failBaseDefeatOperation(data, operation, "BASE_DEFEAT_COMMIT_FAILED")
	end

	tokenData.machineToken = nil
	tokenData.state = "Committed"
	data.baseDefeatCommitted = true
	data.callbacksEnabled = false
	local published = false
	local broadcaster = data.snapshotBroadcaster
	if committedCall and isSuccess(commitResult) and not data.baseDefeatReentryViolation and broadcaster ~= nil then
		local publishCalled, publishResult = callNonYielding(broadcaster.publish, broadcaster, expected)
		published = publishCalled
			and isAcceptedSnapshotPublishResult(publishResult)
			and not data.baseDefeatReentryViolation
			and data.available
	end
	local outcome: BaseDefeatCommitOutcome = table.freeze({
		committed = true,
		published = published,
		snapshot = expected,
	})
	tokenData.outcome = outcome
	endBaseDefeatOperation(data)
	return Result.ok(outcome)
end

function ServiceMethods.rollbackBaseDefeat(self: Service, tokenValue: unknown): Result.Result<boolean, BaseDefeatError>
	local data = requireData(self)
	local operation: BaseDefeatOperation = "rollbackBaseDefeat"
	local operationError = beginBaseDefeatOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local tokenData = tokenDataFor(data, tokenValue)
	if tokenData == nil or tokenData.state ~= "Prepared" then
		endBaseDefeatOperation(data)
		return baseDefeatFailure("INVALID_TOKEN", operation)
	end

	local machine = data.machine
	local machineToken = tokenData.machineToken
	if machine == nil or machineToken == nil then
		return failBaseDefeatOperation(data, operation, "BASE_DEFEAT_ROLLBACK_MISSING")
	end
	local rolledBack, rollbackResult = callNonYielding(machine.rollbackTransition, machine, machineToken)
	local current = detachedStateSnapshot(machine)
	local expectedRevision = tokenData.preparedSnapshot.revision - 1
	local rollbackConfirmed = current ~= nil
		and current.matchId == tokenData.preparedSnapshot.matchId
		and current.revision == expectedRevision
		and current.state == "WaveActive"
	if not rolledBack or not isSuccess(rollbackResult) or not rollbackConfirmed or data.baseDefeatReentryViolation then
		tokenData.machineToken = nil
		tokenData.state = "RolledBack"
		BASE_DEFEAT_TOKEN_DATA[tokenValue :: any] = nil
		data.baseDefeatToken = nil
		return failBaseDefeatOperation(data, operation, "BASE_DEFEAT_ROLLBACK_FAILED")
	end

	tokenData.machineToken = nil
	tokenData.state = "RolledBack"
	BASE_DEFEAT_TOKEN_DATA[tokenValue :: any] = nil
	data.baseDefeatToken = nil
	data.callbacksEnabled = true
	endBaseDefeatOperation(data)
	return Result.ok(true)
end

local function defaultMatchIdGenerator(): unknown
	local generated, guidValue = pcall(HttpService.GenerateGUID, HttpService, false)
	if not generated or type(guidValue) ~= "string" then
		staticError("MATCH_ID_GENERATION_FAILED")
	end
	local matchIdResult = Ids.makeMatchId(string.lower(guidValue :: string))
	if not matchIdResult.ok then
		staticError("MATCH_ID_GENERATION_FAILED")
	end
	return matchIdResult.value
end

local DefaultPlayerSource = {} :: any

function DefaultPlayerSource.getPlayers(_self: PlayerSource): unknown
	return Players:GetPlayers()
end

function DefaultPlayerSource.getUserId(_self: PlayerSource, connection: unknown): unknown
	if typeof(connection) ~= "Instance" or not (connection :: Instance):IsA("Player") then
		return nil
	end
	return (connection :: Player).UserId
end

function DefaultPlayerSource.connectAdded(_self: PlayerSource, listener: PlayerListener): unknown
	return Players.PlayerAdded:Connect(function(player)
		listener(player)
	end)
end

function DefaultPlayerSource.connectRemoving(_self: PlayerSource, listener: PlayerListener): unknown
	return Players.PlayerRemoving:Connect(function(player)
		listener(player)
	end)
end

table.freeze(DefaultPlayerSource)

local function construct(
	logger: Log.Logger,
	mapLoader: MapLoaderAdapter,
	generateMatchId: () -> unknown,
	createStateMachine: (matchId: unknown) -> unknown,
	roster: RosterAdapter,
	playerSource: PlayerSource,
	createReadyCoordinator: AdapterFactory,
	createSnapshotBroadcaster: AdapterFactory,
	clock: Clock,
	schedule: Schedule,
	cancel: Cancel,
	snapshotSender: SnapshotSender,
	isStudio: IsStudio,
	initialMapIdValue: unknown?
): Service
	if not Log.isLogger(logger) then
		staticError("INVALID_LOGGER")
	end
	if not isAdapter(mapLoader, { "load", "cleanup" }) then
		staticError("INVALID_MAP_LOADER")
	end
	if
		type(generateMatchId) ~= "function"
		or type(createStateMachine) ~= "function"
		or type(createReadyCoordinator) ~= "function"
		or type(createSnapshotBroadcaster) ~= "function"
		or type(clock) ~= "function"
		or type(schedule) ~= "function"
		or type(cancel) ~= "function"
		or type(snapshotSender) ~= "function"
		or type(isStudio) ~= "function"
	then
		staticError("INVALID_DEPENDENCIES")
	end
	if
		not isAdapter(roster, {
			"connect",
			"disconnect",
			"resolveConnection",
			"setReadyForConnection",
			"getSnapshot",
			"getReadiness",
			"markUnreadyActiveReturned",
			"cleanup",
		})
	then
		staticError("INVALID_ROSTER")
	end
	if not isAdapter(playerSource, { "getPlayers", "getUserId", "connectAdded", "connectRemoving" }) then
		staticError("INVALID_PLAYER_SOURCE")
	end

	local generated, matchIdValue = pcall(generateMatchId)
	if not generated then
		staticError("MATCH_ID_GENERATION_FAILED")
	end
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if not matchIdResult.ok then
		staticError("INVALID_MATCH_ID")
	end
	local requestedInitialMapId = if initialMapIdValue == nil then FIXED_MAP_ID else initialMapIdValue
	local initialMapId = Ids.validateMapId(requestedInitialMapId)
	if not initialMapId.ok then
		staticError("INVALID_MAP_ID")
	end

	local created, machineResult = pcall(createStateMachine, matchIdResult.value)
	if not created or not isSuccess(machineResult) then
		staticError("STATE_MACHINE_CREATION_FAILED")
	end
	local machine = (machineResult :: any).value
	if
		not isAdapter(machine, {
			"getSnapshot",
			"beginTransition",
			"commitTransition",
			"rollbackTransition",
			"touch",
			"cleanup",
		})
	then
		staticError("INVALID_STATE_MACHINE")
	end

	local data: ServiceData = {
		logger = logger,
		state = "Constructed",
		mapLoader = mapLoader,
		machine = machine :: StateMachineAdapter,
		roster = roster,
		playerSource = playerSource,
		readyCoordinator = nil,
		snapshotBroadcaster = nil,
		cleanup = nil,
		mapLoaded = false,
		callbacksEnabled = false,
		available = true,
		shutdownFailure = nil,
		serviceDefinition = nil,
		runtimeMapSnapshot = nil,
		selectedMapId = initialMapId.value,
		waveActivationToken = nil,
		waveActivationOperationActive = false,
		waveActivationReentryViolation = false,
		waveActivationCommitted = false,
		waveActivationShutdownRequested = false,
		baseDefeatToken = nil,
		baseDefeatOperationActive = false,
		baseDefeatReentryViolation = false,
		baseDefeatCommitted = false,
		baseDefeatShutdownRequested = false,
		isStudio = isStudio,
		studioWaveOperationActive = false,
		studioWaveReentryViolation = false,
		studioWaveActivated = false,
		studioWaveShutdownRequested = false,
		participantObserverAdapter = nil,
		participantObserverHandle = nil,
		participantObserverStatus = nil,
		participantObserverPendingSnapshot = nil,
		participantObserverGeneration = 0,
		participantObserverOperationActive = false,
		participantObserverReentryViolation = false,
		participantObserverShutdownRequested = false,
	}

	local coordinatorCreated, coordinatorResult = pcall(createReadyCoordinator, {
		machine = machine,
		roster = roster,
		clock = clock,
		schedule = schedule,
		cancel = cancel,
		onChanged = function(_outcome: unknown)
			if data.callbacksEnabled then
				publishCurrentSnapshot(data)
			end
		end,
	})
	if not coordinatorCreated or not isSuccess(coordinatorResult) then
		staticError("READY_COORDINATOR_CREATION_FAILED")
	end
	local coordinator = (coordinatorResult :: any).value
	if
		not isAdapter(coordinator, {
			"enterReadyCheck",
			"submitReady",
			"onRosterChanged",
			"getDeadlineServerTime",
			"cleanup",
		})
	then
		staticError("INVALID_READY_COORDINATOR")
	end
	data.readyCoordinator = coordinator :: ReadyCoordinatorAdapter

	local broadcasterCreated, broadcasterResult = pcall(createSnapshotBroadcaster, {
		clock = clock,
		schedule = schedule,
		cancel = cancel,
		sender = function(recipient: unknown, snapshot: MatchSnapshot)
			if snapshotSender(recipient, snapshot) ~= true then
				staticError("SNAPSHOT_SEND_FAILED")
			end
		end,
		getRecipients = function()
			if data.callbacksEnabled then
				return collectRecipients(data)
			end
			return committedBaseDefeatRecipients(data)
		end,
		onFault = function()
			failClosedAtRuntime(data, "SNAPSHOT_BROADCAST_FAULT")
		end,
	})
	if not broadcasterCreated or not isSuccess(broadcasterResult) then
		staticError("SNAPSHOT_BROADCASTER_CREATION_FAILED")
	end
	local broadcaster = (broadcasterResult :: any).value
	if not isAdapter(broadcaster, { "publish", "cleanup" }) then
		staticError("INVALID_SNAPSHOT_BROADCASTER")
	end
	data.snapshotBroadcaster = broadcaster :: SnapshotBroadcasterAdapter

	local service = setmetatable({}, ServiceMethods) :: Service
	table.freeze(service)
	data.serviceDefinition = table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({ "NetworkRegistry" }),
		initialize = function()
			initialize(data)
		end,
		start = function()
			start(data)
		end,
		shutdown = function()
			shutdown(data)
		end,
	})
	SERVICE_DATA[service] = data
	return service
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "MatchLifecycleService" then
		return false
	end
	local lifecycleFolder = script.Parent
	if
		lifecycleFolder == nil
		or not lifecycleFolder:IsA("Folder")
		or lifecycleFolder.Name ~= "ProductionServerMatchLifecycle"
	then
		return false
	end
	local automatedTests = lifecycleFolder.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	if automatedTests.Parent ~= ServerStorage then
		return false
	end
	local support = automatedTests:FindFirstChild("Support")
	return support ~= nil
		and support:IsA("Folder")
		and support:FindFirstChild("TestRunner") ~= nil
		and ServerScriptService:FindFirstChild("Server") == nil
end

local function productionClock(): unknown
	return Workspace:GetServerTimeNow()
end

local function productionSchedule(delaySeconds: number, callback: TimerCallback): unknown
	return task.delay(delaySeconds, callback)
end

local function productionCancel(handle: unknown)
	task.cancel(handle :: thread)
end

local function inertTestClock(): unknown
	return 100
end

local function inertTestSchedule(_delaySeconds: number, _callback: TimerCallback): unknown
	return table.freeze({})
end

local function inertTestCancel(_handle: unknown) end

local function inertTestSnapshotSender(_recipient: unknown, _snapshot: MatchSnapshot): boolean
	return true
end

local function inertTestIsStudio(): unknown
	return false
end

local function productionIsStudio(): unknown
	return RunService:IsStudio()
end

function MatchLifecycleService.new(logger: Log.Logger, snapshotSender: SnapshotSender, initialMapId: string?): Service
	local mapLoaderModule = require(script.Parent.Parent.maps.MapLoader)
	local rosterModule = require(script.Parent.Parent.roster.ParticipantRoster)
	local readyCoordinatorModule = require(script.Parent.Parent.ready.ReadyCheckCoordinator)
	local snapshotBroadcasterModule = require(script.Parent.Parent.ready.SnapshotBroadcaster)
	local rosterResult = (rosterModule :: any).new()
	if not isSuccess(rosterResult) then
		staticError("ROSTER_CREATION_FAILED")
	end
	local mapLoader = (mapLoaderModule :: any).new(logger)
	return construct(
		logger,
		mapLoader,
		defaultMatchIdGenerator,
		MatchStateMachine.new,
		(rosterResult :: any).value,
		DefaultPlayerSource :: PlayerSource,
		(readyCoordinatorModule :: any).new,
		(snapshotBroadcasterModule :: any).new,
		productionClock,
		productionSchedule,
		productionCancel,
		snapshotSender,
		productionIsStudio,
		initialMapId
	)
end

if isExactTestModule() then
	MatchLifecycleService.newForTests = function(logger: Log.Logger, dependencies: TestDependencies): Service
		if type(dependencies) ~= "table" or getmetatable(dependencies :: any) ~= nil then
			staticError("INVALID_DEPENDENCIES")
		end
		local allowedFields = {
			mapLoader = true,
			generateMatchId = true,
			initialMapId = true,
			createStateMachine = true,
			roster = true,
			playerSource = true,
			createReadyCoordinator = true,
			createSnapshotBroadcaster = true,
			clock = true,
			schedule = true,
			cancel = true,
			snapshotSender = true,
			isStudio = true,
		}
		for key in next, dependencies :: any do
			if type(key) ~= "string" or allowedFields[key] ~= true then
				staticError("INVALID_DEPENDENCIES")
			end
		end
		local dependencyValue = dependencies :: any
		local createStateMachine = dependencyValue.createStateMachine or MatchStateMachine.new
		local testReadyFolder = script.Parent.Parent:FindFirstChild("ProductionServerMatchReady")
		if testReadyFolder == nil or not testReadyFolder:IsA("Folder") then
			staticError("TEST_READY_MODULES_MISSING")
		end
		local readyCoordinatorScript = (testReadyFolder :: Folder):FindFirstChild("ReadyCheckCoordinator")
		local snapshotBroadcasterScript = (testReadyFolder :: Folder):FindFirstChild("SnapshotBroadcaster")
		if
			readyCoordinatorScript == nil
			or not readyCoordinatorScript:IsA("ModuleScript")
			or snapshotBroadcasterScript == nil
			or not snapshotBroadcasterScript:IsA("ModuleScript")
		then
			staticError("TEST_READY_MODULES_MISSING")
		end
		local readyCoordinatorModule = require(readyCoordinatorScript :: ModuleScript)
		local snapshotBroadcasterModule = require(snapshotBroadcasterScript :: ModuleScript)
		return construct(
			logger,
			dependencyValue.mapLoader,
			dependencyValue.generateMatchId,
			createStateMachine,
			dependencyValue.roster,
			dependencyValue.playerSource,
			dependencyValue.createReadyCoordinator or (readyCoordinatorModule :: any).new,
			dependencyValue.createSnapshotBroadcaster or (snapshotBroadcasterModule :: any).new,
			dependencyValue.clock or inertTestClock,
			dependencyValue.schedule or inertTestSchedule,
			dependencyValue.cancel or inertTestCancel,
			dependencyValue.snapshotSender or inertTestSnapshotSender,
			dependencyValue.isStudio or inertTestIsStudio,
			dependencyValue.initialMapId
		)
	end
end

table.freeze(ServiceMethods)
return table.freeze(MatchLifecycleService)
