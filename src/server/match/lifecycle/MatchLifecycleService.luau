--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

export type SnapshotErrorCode = "UNAVAILABLE" | "INTERNAL_ERROR"

export type SnapshotError = {
	code: SnapshotErrorCode,
	operation: "getSnapshot",
}

export type ReadyErrorCode = "STALE_REQUEST" | "DUPLICATE_REQUEST" | "NOT_AUTHORIZED" | "UNAVAILABLE" | "INTERNAL_ERROR"

export type ReadyError = {
	code: ReadyErrorCode,
	operation: "submitReady",
}

export type MapLoaderAdapter = {
	load: (self: MapLoaderAdapter, mapId: unknown) -> unknown,
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

export type TestDependencies = {
	mapLoader: MapLoaderAdapter,
	generateMatchId: () -> unknown,
	roster: RosterAdapter,
	playerSource: PlayerSource,
	createStateMachine: ((matchId: unknown) -> unknown)?,
	createReadyCoordinator: AdapterFactory?,
	createSnapshotBroadcaster: AdapterFactory?,
	clock: Clock?,
	schedule: Schedule?,
	cancel: Cancel?,
	snapshotSender: SnapshotSender?,
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
}

type ExistingPlayer = {
	connection: unknown,
	userId: number,
	index: number,
}

local ServiceMethods = {}
ServiceMethods.__index = ServiceMethods

export type Service = typeof(setmetatable({} :: {}, ServiceMethods))
export type TestConstructor = (logger: Log.Logger, dependencies: TestDependencies) -> Service

local FIXED_MAP_ID = "map:phase07-graybox"
local SERVICE_NAME = "MatchLifecycle"
local CLEANUP_LABEL = "match-lifecycle"
local STATIC_ERROR_PREFIX = "[ATD_MATCH_LIFECYCLE]"
local MAX_PARTICIPANTS = 4

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

local MatchLifecycleService = {
	FIXED_MAP_ID = FIXED_MAP_ID,
	newForTests = nil :: TestConstructor?,
}

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

local function readyFailure(code: ReadyErrorCode): Result.Failure<ReadyError>
	return Result.err(table.freeze({
		code = code,
		operation = "submitReady",
	}))
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
	local called, resultValue = pcall(machine.rollbackTransition, machine, token)
	return called and isSuccess(resultValue)
end

local function transition(machine: StateMachineAdapter, targetState: MatchStateMachine.MatchState): boolean
	local current = detachedStateSnapshot(machine)
	if current == nil then
		return false
	end

	local began, beginValue = pcall(machine.beginTransition, machine, targetState, current.revision)
	if not began or not isSuccess(beginValue) then
		return false
	end
	local token = (beginValue :: any).value

	local committed, commitValue = pcall(machine.commitTransition, machine, token)
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

local function releaseOwnedResources(data: ServiceData): (boolean, string?)
	data.callbacksEnabled = false
	data.available = false
	local cleanup = data.cleanup
	data.cleanup = nil
	data.mapLoaded = false

	if cleanup == nil then
		data.mapLoader = nil
		data.machine = nil
		data.roster = nil
		data.playerSource = nil
		data.readyCoordinator = nil
		data.snapshotBroadcaster = nil
		return true, nil
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
	if cleaned then
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

local function collectRecipients(data: ServiceData): unknown
	local playerSource = data.playerSource
	local roster = data.roster
	if not data.callbacksEnabled or playerSource == nil or roster == nil then
		return nil
	end

	local called, playersValue = pcall(playerSource.getPlayers, playerSource)
	if not called or not isDenseArray(playersValue) then
		return nil
	end
	local recipients = {}
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
				table.insert(recipients, {
					recipient = connection,
					userId = userId,
				})
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
	return recipients
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
		return coordinated and isSuccess(coordinatorResult) and data.available
	elseif data.state == "Started" then
		return publishCurrentSnapshot(data)
	end
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

	local loaded, loadResult = pcall((mapLoader :: MapLoaderAdapter).load, mapLoader, FIXED_MAP_ID)
	data.mapLoaded = loaded and isSuccess(loadResult)
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

local function shutdown(data: ServiceData)
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
	data.state = "ShuttingDown"
	data.callbacksEnabled = false

	local transitionSucceeded = true
	local machine = data.machine
	if machine == nil then
		transitionSucceeded = false
	else
		local current = detachedStateSnapshot(machine)
		if current == nil then
			transitionSucceeded = false
		elseif current.state ~= "Closing" then
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

function ServiceMethods.submitReady(
	self: Service,
	connection: unknown,
	matchId: unknown,
	observedRevision: unknown
): Result.Result<MatchSnapshot, ReadyError>
	local data = requireData(self)
	if not data.available or data.state ~= "Started" then
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
	snapshotSender: SnapshotSender
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
			return collectRecipients(data)
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

function MatchLifecycleService.new(logger: Log.Logger, snapshotSender: SnapshotSender): Service
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
		snapshotSender
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
			createStateMachine = true,
			roster = true,
			playerSource = true,
			createReadyCoordinator = true,
			createSnapshotBroadcaster = true,
			clock = true,
			schedule = true,
			cancel = true,
			snapshotSender = true,
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
			dependencyValue.snapshotSender or inertTestSnapshotSender
		)
	end
end

table.freeze(ServiceMethods)
return table.freeze(MatchLifecycleService)
