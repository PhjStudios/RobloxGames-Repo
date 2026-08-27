--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type MatchState = "Loading" | "ReadyCheck" | "PreWave" | "WaveActive" | "Results" | "Closing"

export type Operation = "new" | "enterReadyCheck" | "submitReady" | "onRosterChanged" | "timer" | "cleanup"

export type ErrorCode = "STALE_REQUEST" | "DUPLICATE_REQUEST" | "NOT_AUTHORIZED" | "UNAVAILABLE" | "INTERNAL_ERROR"

export type CoordinatorError = {
	code: ErrorCode,
	operation: Operation,
}

export type Outcome = {
	changed: boolean,
	state: MatchState,
	revision: number,
	deadlineServerTime: number?,
}

export type StateMachineAdapter = {
	getSnapshot: (self: StateMachineAdapter) -> unknown,
	beginTransition: (self: StateMachineAdapter, targetState: unknown, expectedRevision: unknown) -> unknown,
	commitTransition: (self: StateMachineAdapter, token: unknown) -> unknown,
	rollbackTransition: (self: StateMachineAdapter, token: unknown) -> unknown,
	touch: (self: StateMachineAdapter, expectedRevision: unknown) -> unknown,
}

export type RosterAdapter = {
	resolveConnection: (self: RosterAdapter, connection: unknown) -> unknown,
	setReadyForConnection: (self: RosterAdapter, connection: unknown) -> unknown,
	getReadiness: (self: RosterAdapter) -> unknown,
	markUnreadyActiveReturned: (self: RosterAdapter) -> unknown,
}

export type Clock = () -> unknown
export type TimerCallback = () -> ()
export type Schedule = (delaySeconds: number, callback: TimerCallback) -> unknown
export type Cancel = (handle: unknown) -> ()
export type OnChanged = (outcome: Outcome) -> ()

export type Dependencies = {
	machine: StateMachineAdapter,
	roster: RosterAdapter,
	clock: Clock,
	schedule: Schedule,
	cancel: Cancel,
	onChanged: OnChanged?,
}

local CoordinatorMethods = {}
CoordinatorMethods.__index = CoordinatorMethods

export type Coordinator = typeof(setmetatable({} :: {}, CoordinatorMethods))

type StateSnapshot = {
	matchId: Ids.MatchId,
	revision: number,
	state: MatchState,
}

type ReadinessSnapshot = {
	activeCount: number,
	readyActiveCount: number,
	allActiveReady: boolean,
}

type CoordinatorData = {
	machine: StateMachineAdapter,
	roster: RosterAdapter,
	clock: Clock,
	schedule: Schedule,
	cancel: Cancel,
	onChanged: OnChanged?,
	matchId: Ids.MatchId,
	deadlineServerTime: number?,
	entryRevision: number?,
	lastClockSample: number?,
	timerGeneration: number,
	timerHandle: unknown?,
	active: boolean,
	busy: boolean,
	cleaned: boolean,
}

local READY_CHECK_SECONDS = 45

local MATCH_STATES: { [string]: boolean } = table.freeze({
	Loading = true,
	ReadyCheck = true,
	PreWave = true,
	WaveActive = true,
	Results = true,
	Closing = true,
})

local PARTICIPANT_STATES: { [string]: boolean } = table.freeze({
	Active = true,
	Disconnected = true,
	Returned = true,
	Spectator = true,
})

local COORDINATOR_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: CoordinatorData }

local ReadyCheckCoordinator = {
	READY_CHECK_SECONDS = READY_CHECK_SECONDS,
}

local function makeError(code: ErrorCode, operation: Operation): CoordinatorError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<CoordinatorError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): CoordinatorData
	if type(value) ~= "table" then
		error("[ATD_READY_CHECK][code=INVALID_CONTEXT]", 0)
	end
	local data = COORDINATOR_DATA[value :: any]
	if data == nil then
		error("[ATD_READY_CHECK][code=INVALID_CONTEXT]", 0)
	end
	return data
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

local function parseStateSnapshot(value: unknown): StateSnapshot?
	if type(value) ~= "table" then
		return nil
	end
	local matchIdResult = Ids.validateMatchId((value :: any).matchId)
	local revision = (value :: any).revision
	local state = (value :: any).state
	if
		not matchIdResult.ok
		or type(revision) ~= "number"
		or not Validation.isSafeInteger(revision)
		or revision < 1
		or type(state) ~= "string"
		or MATCH_STATES[state] ~= true
	then
		return nil
	end
	return table.freeze({
		matchId = matchIdResult.value,
		revision = revision,
		state = state :: MatchState,
	})
end

local function readState(data: CoordinatorData): StateSnapshot?
	local called, resultValue = pcall(data.machine.getSnapshot, data.machine)
	if not called or not isSuccess(resultValue) then
		return nil
	end
	local snapshot = parseStateSnapshot((resultValue :: any).value)
	if snapshot == nil or snapshot.matchId ~= data.matchId then
		return nil
	end
	return snapshot
end

local function parseReturnedState(value: unknown, expectedMatchId: Ids.MatchId): StateSnapshot?
	if not isSuccess(value) then
		return nil
	end
	local snapshot = parseStateSnapshot((value :: any).value)
	if snapshot == nil or snapshot.matchId ~= expectedMatchId then
		return nil
	end
	return snapshot
end

local function rollback(machine: StateMachineAdapter, token: unknown)
	pcall(machine.rollbackTransition, machine, token)
end

local function transitionRaw(data: CoordinatorData, targetState: MatchState): StateSnapshot?
	local before = readState(data)
	if before == nil or before.state == "Closing" or before.revision >= Validation.MAX_SAFE_INTEGER then
		return nil
	end

	local began, beginResult = pcall(data.machine.beginTransition, data.machine, targetState, before.revision)
	if not began or not isSuccess(beginResult) then
		return nil
	end
	local token = (beginResult :: any).value
	local committed, commitResult = pcall(data.machine.commitTransition, data.machine, token)
	if not committed then
		rollback(data.machine, token)
		return nil
	end
	local after = parseReturnedState(commitResult, data.matchId)
	if
		after == nil
		or after.state ~= targetState
		or after.revision ~= before.revision + 1
		or before.matchId ~= after.matchId
	then
		rollback(data.machine, token)
		return nil
	end
	return after
end

local function touchRaw(data: CoordinatorData): StateSnapshot?
	local before = readState(data)
	if before == nil or before.state ~= "ReadyCheck" or before.revision >= Validation.MAX_SAFE_INTEGER then
		return nil
	end
	local called, resultValue = pcall(data.machine.touch, data.machine, before.revision)
	if not called then
		return nil
	end
	local after = parseReturnedState(resultValue, data.matchId)
	if after == nil or after.state ~= before.state or after.revision ~= before.revision + 1 then
		return nil
	end
	return after
end

local function outcomeFrom(data: CoordinatorData, snapshot: StateSnapshot, changed: boolean): Outcome
	local deadline = if data.active and snapshot.state == "ReadyCheck" then data.deadlineServerTime else nil
	return table.freeze({
		changed = changed,
		state = snapshot.state,
		revision = snapshot.revision,
		deadlineServerTime = deadline,
	})
end

local function notify(data: CoordinatorData, outcome: Outcome)
	local callback = data.onChanged
	if callback ~= nil then
		-- Notification is downstream of the authority mutation. Contain a faulty
		-- observer so it cannot roll back or re-enter the coordinator.
		pcall(callback, outcome)
	end
end

local function sampleClock(data: CoordinatorData): number?
	local called, value = pcall(data.clock)
	if
		not called
		or type(value) ~= "number"
		or not Validation.isFiniteNumber(value)
		or value < 0
		or (data.lastClockSample ~= nil and value < data.lastClockSample)
	then
		return nil
	end
	data.lastClockSample = value
	return value
end

local function invalidateTimer(data: CoordinatorData): boolean
	data.active = false
	data.deadlineServerTime = nil
	data.entryRevision = nil
	if data.timerGeneration >= Validation.MAX_SAFE_INTEGER then
		return false
	end
	data.timerGeneration += 1

	local handle = data.timerHandle
	data.timerHandle = nil
	if handle == nil then
		return true
	end
	local cancelled = pcall(data.cancel, handle)
	return cancelled
end

local function failClosed(data: CoordinatorData): StateSnapshot?
	local _ = invalidateTimer(data)
	local current = readState(data)
	if current == nil or current.state == "Closing" then
		return current
	end
	return transitionRaw(data, "Closing")
end

local function failClosedAndNotify(data: CoordinatorData)
	local closed = failClosed(data)
	if closed ~= nil then
		notify(data, outcomeFrom(data, closed, true))
	end
end

local function parseReadiness(value: unknown): ReadinessSnapshot?
	if type(value) ~= "table" then
		return nil
	end
	local activeCount = (value :: any).activeCount
	local readyActiveCount = (value :: any).readyActiveCount
	local allActiveReady = (value :: any).allActiveReady
	if
		type(activeCount) ~= "number"
		or not Validation.isSafeInteger(activeCount)
		or activeCount < 0
		or activeCount > 4
		or type(readyActiveCount) ~= "number"
		or not Validation.isSafeInteger(readyActiveCount)
		or readyActiveCount < 0
		or readyActiveCount > activeCount
		or type(allActiveReady) ~= "boolean"
		or allActiveReady ~= (activeCount > 0 and activeCount == readyActiveCount)
	then
		return nil
	end
	return table.freeze({
		activeCount = activeCount,
		readyActiveCount = readyActiveCount,
		allActiveReady = allActiveReady,
	})
end

local function readReadiness(data: CoordinatorData): ReadinessSnapshot?
	local called, resultValue = pcall(data.roster.getReadiness, data.roster)
	if not called or not isSuccess(resultValue) then
		return nil
	end
	return parseReadiness((resultValue :: any).value)
end

local function leaveReadyCheck(data: CoordinatorData, targetState: "PreWave" | "Closing"): StateSnapshot?
	if not invalidateTimer(data) then
		failClosed(data)
		return nil
	end
	local transitioned = transitionRaw(data, targetState)
	if transitioned == nil then
		failClosed(data)
		return nil
	end
	return transitioned
end

local function resolveTimeout(data: CoordinatorData): Outcome?
	local readiness = readReadiness(data)
	if readiness == nil then
		failClosedAndNotify(data)
		return nil
	end

	if readiness.readyActiveCount == 0 then
		local closed = leaveReadyCheck(data, "Closing")
		if closed == nil then
			failClosedAndNotify(data)
			return nil
		end
		return outcomeFrom(data, closed, true)
	end

	local marked, markResult = pcall(data.roster.markUnreadyActiveReturned, data.roster)
	if not marked or not isSuccess(markResult) then
		failClosedAndNotify(data)
		return nil
	end
	local batch = (markResult :: any).value
	local changedCount = if type(batch) == "table" then (batch :: any).changedCount else nil
	if
		type(changedCount) ~= "number"
		or not Validation.isSafeInteger(changedCount)
		or changedCount < 0
		or changedCount > 4
	then
		failClosedAndNotify(data)
		return nil
	end

	if changedCount > 0 and touchRaw(data) == nil then
		failClosedAndNotify(data)
		return nil
	end
	local afterBatch = readReadiness(data)
	if afterBatch == nil or not afterBatch.allActiveReady or afterBatch.readyActiveCount < 1 then
		failClosedAndNotify(data)
		return nil
	end

	local preWave = leaveReadyCheck(data, "PreWave")
	if preWave == nil then
		failClosedAndNotify(data)
		return nil
	end
	return outcomeFrom(data, preWave, true)
end

local processTimer: (CoordinatorData, number, Ids.MatchId) -> ()

local function armTimer(data: CoordinatorData, delaySeconds: number, generation: number): boolean
	if
		not Validation.isFiniteNumber(delaySeconds)
		or delaySeconds < 0
		or data.cleaned
		or not data.active
		or generation ~= data.timerGeneration
		or data.timerHandle ~= nil
	then
		return false
	end

	local capturedHandle: unknown? = nil
	local armed = false
	local firedBeforeArmed = false
	local capturedMatchId = data.matchId
	local callback = function()
		if not armed then
			firedBeforeArmed = true
			return
		end
		if
			data.cleaned
			or not data.active
			or generation ~= data.timerGeneration
			or data.timerHandle ~= capturedHandle
		then
			return
		end
		data.timerHandle = nil
		processTimer(data, generation, capturedMatchId)
	end

	local scheduled, handle = pcall(data.schedule, delaySeconds, callback)
	if not scheduled or handle == nil then
		return false
	end
	capturedHandle = handle
	if firedBeforeArmed then
		pcall(data.cancel, handle)
		return false
	end
	if data.cleaned or not data.active or generation ~= data.timerGeneration then
		pcall(data.cancel, handle)
		return false
	end
	data.timerHandle = handle
	armed = true
	return true
end

processTimer = function(data: CoordinatorData, generation: number, capturedMatchId: Ids.MatchId)
	if data.busy then
		failClosedAndNotify(data)
		return
	end
	data.busy = true

	local current = readState(data)
	if data.cleaned or not data.active or generation ~= data.timerGeneration then
		data.busy = false
		return
	end
	if current == nil or capturedMatchId ~= data.matchId or current.matchId ~= capturedMatchId then
		failClosedAndNotify(data)
		data.busy = false
		return
	elseif current.state ~= "ReadyCheck" then
		if not invalidateTimer(data) then
			failClosedAndNotify(data)
		end
		data.busy = false
		return
	end

	local now = sampleClock(data)
	local deadline = data.deadlineServerTime
	if now == nil or deadline == nil then
		failClosedAndNotify(data)
		data.busy = false
		return
	end
	if now < deadline then
		if not armTimer(data, deadline - now, generation) then
			failClosedAndNotify(data)
		end
		data.busy = false
		return
	end

	local outcome = resolveTimeout(data)
	if outcome ~= nil then
		notify(data, outcome)
	end
	data.busy = false
end

local function mapRosterError(errorCode: string?): ErrorCode
	if errorCode == "ALREADY_READY" then
		return "DUPLICATE_REQUEST"
	elseif
		errorCode == "INVALID_CONNECTION"
		or errorCode == "UNKNOWN_CONNECTION"
		or errorCode == "STALE_CONNECTION"
		or errorCode == "UNTRACKED_SPECTATOR"
		or errorCode == "INACTIVE_PARTICIPANT"
	then
		return "NOT_AUTHORIZED"
	end
	return "INTERNAL_ERROR"
end

local function validateResolvedParticipant(value: unknown): ("Active"?, boolean?)
	if type(value) ~= "table" then
		return nil, nil
	end
	local state = (value :: any).state
	local ready = (value :: any).ready
	if type(state) ~= "string" or PARTICIPANT_STATES[state] ~= true or type(ready) ~= "boolean" then
		return nil, nil
	end
	if state ~= "Active" then
		return nil, ready
	end
	return "Active", ready
end

function CoordinatorMethods.enterReadyCheck(self: Coordinator): Result.Result<Outcome, CoordinatorError>
	local data = requireData(self)
	if data.cleaned or data.busy or data.active then
		return failure("UNAVAILABLE", "enterReadyCheck")
	end
	data.busy = true

	local before = readState(data)
	if before == nil or before.state ~= "Loading" then
		data.busy = false
		return failure("UNAVAILABLE", "enterReadyCheck")
	end
	local startTime = sampleClock(data)
	local deadline = if startTime == nil then nil else startTime + READY_CHECK_SECONDS
	if deadline == nil or not Validation.isFiniteNumber(deadline) or deadline < startTime then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "enterReadyCheck")
	end

	local readyCheck = transitionRaw(data, "ReadyCheck")
	if readyCheck == nil then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "enterReadyCheck")
	end
	if data.timerGeneration >= Validation.MAX_SAFE_INTEGER then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "enterReadyCheck")
	end
	data.timerGeneration += 1
	data.active = true
	data.deadlineServerTime = deadline
	data.entryRevision = readyCheck.revision
	if not armTimer(data, READY_CHECK_SECONDS, data.timerGeneration) then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "enterReadyCheck")
	end

	local outcome = outcomeFrom(data, readyCheck, true)
	notify(data, outcome)
	data.busy = false
	return Result.ok(outcome)
end

function CoordinatorMethods.submitReady(
	self: Coordinator,
	connection: unknown,
	matchIdValue: unknown,
	observedRevisionValue: unknown
): Result.Result<Outcome, CoordinatorError>
	local data = requireData(self)
	if data.cleaned or data.busy or not data.active then
		return failure("UNAVAILABLE", "submitReady")
	end
	data.busy = true

	local current = readState(data)
	if current == nil then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "submitReady")
	elseif current.state ~= "ReadyCheck" then
		if not invalidateTimer(data) then
			failClosedAndNotify(data)
			data.busy = false
			return failure("INTERNAL_ERROR", "submitReady")
		end
		data.busy = false
		return failure("UNAVAILABLE", "submitReady")
	end
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	local entryRevision = data.entryRevision
	if
		not matchIdResult.ok
		or matchIdResult.value ~= data.matchId
		or entryRevision == nil
		or type(observedRevisionValue) ~= "number"
		or not Validation.isSafeInteger(observedRevisionValue)
		or observedRevisionValue < entryRevision
		or observedRevisionValue > current.revision
	then
		data.busy = false
		return failure("STALE_REQUEST", "submitReady")
	end

	local now = sampleClock(data)
	local deadline = data.deadlineServerTime
	if now == nil or deadline == nil then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "submitReady")
	elseif now >= deadline then
		local timeoutOutcome = resolveTimeout(data)
		if timeoutOutcome == nil then
			data.busy = false
			return failure("INTERNAL_ERROR", "submitReady")
		end
		notify(data, timeoutOutcome)
		data.busy = false
		return failure("UNAVAILABLE", "submitReady")
	end

	local resolved, resolvedResult = pcall(data.roster.resolveConnection, data.roster, connection)
	if not resolved or not isSuccess(resolvedResult) then
		local mappedCode = if resolved then mapRosterError(resultErrorCode(resolvedResult)) else "INTERNAL_ERROR"
		if mappedCode == "INTERNAL_ERROR" then
			failClosedAndNotify(data)
		end
		data.busy = false
		return failure(mappedCode, "submitReady")
	end
	local participantState, alreadyReady = validateResolvedParticipant((resolvedResult :: any).value)
	if participantState == nil then
		if alreadyReady == nil then
			failClosedAndNotify(data)
		end
		data.busy = false
		return failure(if alreadyReady == nil then "INTERNAL_ERROR" else "NOT_AUTHORIZED", "submitReady")
	elseif alreadyReady then
		data.busy = false
		return failure("DUPLICATE_REQUEST", "submitReady")
	end

	local set, setResult = pcall(data.roster.setReadyForConnection, data.roster, connection)
	if not set or not isSuccess(setResult) then
		local mappedCode = if set then mapRosterError(resultErrorCode(setResult)) else "INTERNAL_ERROR"
		if mappedCode == "INTERNAL_ERROR" then
			failClosedAndNotify(data)
		end
		data.busy = false
		return failure(mappedCode, "submitReady")
	end
	local setState, setReady = validateResolvedParticipant((setResult :: any).value)
	if setState ~= "Active" or setReady ~= true then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "submitReady")
	end

	local touched = touchRaw(data)
	if touched == nil then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "submitReady")
	end
	local readiness = readReadiness(data)
	if readiness == nil then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "submitReady")
	end

	local finalSnapshot = touched
	if readiness.allActiveReady then
		local preWave = leaveReadyCheck(data, "PreWave")
		if preWave == nil then
			failClosedAndNotify(data)
			data.busy = false
			return failure("INTERNAL_ERROR", "submitReady")
		end
		finalSnapshot = preWave
	end
	local outcome = outcomeFrom(data, finalSnapshot, true)
	notify(data, outcome)
	data.busy = false
	return Result.ok(outcome)
end

function CoordinatorMethods.onRosterChanged(self: Coordinator): Result.Result<Outcome, CoordinatorError>
	local data = requireData(self)
	if data.cleaned or data.busy or not data.active then
		return failure("UNAVAILABLE", "onRosterChanged")
	end
	data.busy = true

	local current = readState(data)
	if current == nil then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "onRosterChanged")
	elseif current.state ~= "ReadyCheck" then
		if not invalidateTimer(data) then
			failClosedAndNotify(data)
			data.busy = false
			return failure("INTERNAL_ERROR", "onRosterChanged")
		end
		data.busy = false
		return failure("UNAVAILABLE", "onRosterChanged")
	end
	local now = sampleClock(data)
	local deadline = data.deadlineServerTime
	if now == nil or deadline == nil then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "onRosterChanged")
	elseif now >= deadline then
		local timeoutOutcome = resolveTimeout(data)
		if timeoutOutcome == nil then
			data.busy = false
			return failure("INTERNAL_ERROR", "onRosterChanged")
		end
		notify(data, timeoutOutcome)
		data.busy = false
		return Result.ok(timeoutOutcome)
	end

	local readiness = readReadiness(data)
	if readiness == nil then
		failClosedAndNotify(data)
		data.busy = false
		return failure("INTERNAL_ERROR", "onRosterChanged")
	end
	local finalSnapshot = current
	if readiness.allActiveReady then
		local preWave = leaveReadyCheck(data, "PreWave")
		if preWave == nil then
			failClosedAndNotify(data)
			data.busy = false
			return failure("INTERNAL_ERROR", "onRosterChanged")
		end
		finalSnapshot = preWave
	end
	local outcome = outcomeFrom(data, finalSnapshot, true)
	notify(data, outcome)
	data.busy = false
	return Result.ok(outcome)
end

function CoordinatorMethods.getDeadlineServerTime(self: Coordinator): number?
	local data = requireData(self)
	if data.cleaned or not data.active then
		return nil
	end
	local current = readState(data)
	if current == nil or current.state ~= "ReadyCheck" then
		return nil
	end
	return data.deadlineServerTime
end

function CoordinatorMethods.getEntryRevision(self: Coordinator): number?
	local data = requireData(self)
	if data.cleaned or not data.active then
		return nil
	end
	local current = readState(data)
	if current == nil or current.state ~= "ReadyCheck" then
		return nil
	end
	return data.entryRevision
end

function CoordinatorMethods.cleanup(self: Coordinator): Result.Result<boolean, CoordinatorError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	elseif data.busy then
		return failure("UNAVAILABLE", "cleanup")
	end
	data.busy = true
	data.cleaned = true
	local cancelled = invalidateTimer(data)
	data.onChanged = nil
	data.busy = false
	if not cancelled then
		failClosed(data)
		return failure("INTERNAL_ERROR", "cleanup")
	end
	return Result.ok(true)
end

function ReadyCheckCoordinator.new(dependenciesValue: unknown): Result.Result<Coordinator, CoordinatorError>
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return failure("INTERNAL_ERROR", "new")
	end
	local allowedFields = table.freeze({
		machine = true,
		roster = true,
		clock = true,
		schedule = true,
		cancel = true,
		onChanged = true,
	})
	for fieldName in next, dependenciesValue :: any do
		if type(fieldName) ~= "string" or allowedFields[fieldName] ~= true then
			return failure("INTERNAL_ERROR", "new")
		end
	end

	local dependencies = dependenciesValue :: any
	if
		not isAdapter(dependencies.machine, {
			"getSnapshot",
			"beginTransition",
			"commitTransition",
			"rollbackTransition",
			"touch",
		})
		or not isAdapter(dependencies.roster, {
			"resolveConnection",
			"setReadyForConnection",
			"getReadiness",
			"markUnreadyActiveReturned",
		})
		or type(dependencies.clock) ~= "function"
		or type(dependencies.schedule) ~= "function"
		or type(dependencies.cancel) ~= "function"
		or (dependencies.onChanged ~= nil and type(dependencies.onChanged) ~= "function")
	then
		return failure("INTERNAL_ERROR", "new")
	end

	local machine = dependencies.machine :: StateMachineAdapter
	local called, resultValue = pcall(machine.getSnapshot, machine)
	local initial = if called and isSuccess(resultValue) then parseStateSnapshot((resultValue :: any).value) else nil
	if initial == nil then
		return failure("INTERNAL_ERROR", "new")
	end

	local coordinator = setmetatable({}, CoordinatorMethods) :: Coordinator
	table.freeze(coordinator)
	COORDINATOR_DATA[coordinator] = {
		machine = machine,
		roster = dependencies.roster :: RosterAdapter,
		clock = dependencies.clock :: Clock,
		schedule = dependencies.schedule :: Schedule,
		cancel = dependencies.cancel :: Cancel,
		onChanged = dependencies.onChanged :: OnChanged?,
		matchId = initial.matchId,
		deadlineServerTime = nil,
		entryRevision = nil,
		lastClockSample = nil,
		timerGeneration = 0,
		timerHandle = nil,
		active = false,
		busy = false,
		cleaned = false,
	}
	return Result.ok(coordinator)
end

table.freeze(CoordinatorMethods)
return table.freeze(ReadyCheckCoordinator)
