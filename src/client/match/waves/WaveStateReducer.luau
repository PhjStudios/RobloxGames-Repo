--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaveProtocol = require(ReplicatedStorage.Shared.match.WaveProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)

export type ApplyKind = "Applied" | "Replaced" | "Duplicate" | "Stale" | "Skipped" | "WrongMatch" | "Rejected"

export type ApplyOutcome = {
	kind: ApplyKind,
	stateChanged: boolean,
	recoveryRequired: boolean,
	recoveryRequested: boolean,
	matchReplaced: boolean,
}

export type ConvergedState = {
	locked: boolean,
	snapshot: WaveProtocol.WaveSnapshot?,
	recoveryRequired: boolean,
}

export type ErrorCode = "INVALID_SNAPSHOT" | "INVALID_ARGUMENT" | "CLEANED_UP"

export type Error = {
	code: ErrorCode,
}

type Source = "Event" | "GetResponse" | "SubmitResponse"

type ReducerData = {
	snapshot: WaveProtocol.WaveSnapshot?,
	recoveryRequired: boolean,
	cleaned: boolean,
}

local ReducerMethods = {}
ReducerMethods.__index = ReducerMethods

export type Reducer = typeof(setmetatable({} :: {}, ReducerMethods))
export type ReducerResult = Result.Result<Reducer, Error>
export type ApplyResult = Result.Result<ApplyOutcome, Error>
export type StateResult = Result.Result<ConvergedState, Error>

local REDUCER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ReducerData }

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_SNAPSHOT = table.freeze({ code = "INVALID_SNAPSHOT" :: "INVALID_SNAPSHOT" }),
	INVALID_ARGUMENT = table.freeze({ code = "INVALID_ARGUMENT" :: "INVALID_ARGUMENT" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local CLEANUP_RESULT = Result.ok(true)

local function failure(code: ErrorCode)
	return Result.err(ERRORS[code])
end

local function requireData(value: unknown): ReducerData
	if type(value) ~= "table" then
		error("[ATD_WAVE_STATE_REDUCER][code=INVALID_CONTEXT]", 0)
	end
	local data = REDUCER_DATA[value :: any]
	if data == nil then
		error("[ATD_WAVE_STATE_REDUCER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function deepEqual(left: unknown, right: unknown, seen: { [any]: any }?): boolean
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
	local visited = seen or {}
	if visited[left :: any] ~= nil then
		return visited[left :: any] == right
	end
	visited[left :: any] = right
	local leftCount = 0
	for key, leftValue in next, left :: any do
		leftCount += 1
		if not deepEqual(leftValue, (right :: any)[key], visited) then
			return false
		end
	end
	local rightCount = 0
	for _ in next, right :: any do
		rightCount += 1
	end
	return leftCount == rightCount
end

local function sameMatch(left: WaveProtocol.WaveSnapshot, right: WaveProtocol.WaveSnapshot): boolean
	return left.matchId == right.matchId
end

local function samePinnedIdentity(left: WaveProtocol.WaveSnapshot, right: WaveProtocol.WaveSnapshot): boolean
	return sameMatch(left, right)
		and left.enemyEpoch == right.enemyEpoch
		and left.mapId == right.mapId
		and left.difficultyId == right.difficultyId
		and left.totalWaves == right.totalWaves
end

local function isTerminal(state: string): boolean
	return state == "FiniteComplete" or state == "DefeatClosed" or state == "Faulted"
end

local function legalStateTransition(previous: string, nextState: string): boolean
	if isTerminal(previous) then
		return nextState == previous
	elseif previous == "Intermission" then
		return nextState == "Intermission"
			or nextState == "Running"
			or nextState == "FiniteComplete"
			or nextState == "DefeatClosed"
			or nextState == "Faulted"
	end
	return nextState == "Running"
		or nextState == "Intermission"
		or nextState == "FiniteComplete"
		or nextState == "DefeatClosed"
		or nextState == "Faulted"
end

local function monotonicAggregate(previous: any, nextCounts: any): boolean
	return nextCounts.totalScheduled >= previous.totalScheduled
		and nextCounts.spawned >= previous.spawned
		and nextCounts.leaked >= previous.leaked
		and nextCounts.otherwiseResolved >= previous.otherwiseResolved
end

local function monotonicCurrent(previous: any, nextCounts: any): boolean
	return nextCounts.totalScheduled == previous.totalScheduled
		and nextCounts.pending <= previous.pending
		and nextCounts.spawned >= previous.spawned
		and nextCounts.leaked >= previous.leaked
		and nextCounts.otherwiseResolved >= previous.otherwiseResolved
end

local function canAdvance(previous: WaveProtocol.WaveSnapshot, nextSnapshot: WaveProtocol.WaveSnapshot): boolean
	if
		not samePinnedIdentity(previous, nextSnapshot)
		or not legalStateTransition(previous.state, nextSnapshot.state)
		or nextSnapshot.currentWaveNumber < previous.currentWaveNumber
		or not monotonicAggregate(previous.aggregateCounts, nextSnapshot.aggregateCounts)
	then
		return false
	end

	if nextSnapshot.currentWaveNumber == previous.currentWaveNumber then
		return nextSnapshot.currentWaveId == previous.currentWaveId
			and nextSnapshot.bossKind == previous.bossKind
			and nextSnapshot.waveStartedServerTime == previous.waveStartedServerTime
			and nextSnapshot.deadlineServerTime == previous.deadlineServerTime
			and nextSnapshot.aggregateCounts.totalScheduled == previous.aggregateCounts.totalScheduled
			and monotonicCurrent(previous.currentCounts, nextSnapshot.currentCounts)
	end

	return not isTerminal(previous.state) and nextSnapshot.waveStartedServerTime >= previous.waveStartedServerTime
end

local function makeOutcome(
	kind: ApplyKind,
	stateChanged: boolean,
	recoveryRequired: boolean,
	recoveryRequested: boolean,
	matchReplaced: boolean
): ApplyOutcome
	return table.freeze({
		kind = kind,
		stateChanged = stateChanged,
		recoveryRequired = recoveryRequired,
		recoveryRequested = recoveryRequested,
		matchReplaced = matchReplaced,
	})
end

local function latchRecovery(data: ReducerData): boolean
	if data.recoveryRequired then
		return false
	end
	data.recoveryRequired = true
	return true
end

local function observeCanonical(
	data: ReducerData,
	nextSnapshot: WaveProtocol.WaveSnapshot,
	source: Source,
	allowMatchReplacement: boolean
): ApplyOutcome
	local previous = data.snapshot
	if previous == nil then
		data.snapshot = nextSnapshot
		data.recoveryRequired = false
		return makeOutcome("Applied", true, false, false, false)
	end

	if not sameMatch(previous, nextSnapshot) then
		if source == "GetResponse" and allowMatchReplacement then
			data.snapshot = nextSnapshot
			data.recoveryRequired = false
			return makeOutcome("Replaced", true, false, false, true)
		end
		local requested = if source == "Event" then latchRecovery(data) else false
		return makeOutcome("WrongMatch", false, data.recoveryRequired, requested, false)
	end

	if not samePinnedIdentity(previous, nextSnapshot) then
		return makeOutcome("Rejected", false, data.recoveryRequired, false, false)
	end

	if nextSnapshot.waveRevision < previous.waveRevision then
		return makeOutcome("Stale", false, data.recoveryRequired, false, false)
	elseif nextSnapshot.waveRevision == previous.waveRevision then
		local kind: ApplyKind = if deepEqual(previous, nextSnapshot) then "Duplicate" else "Rejected"
		return makeOutcome(kind, false, data.recoveryRequired, false, false)
	end

	if source == "Event" and nextSnapshot.waveRevision ~= previous.waveRevision + 1 then
		local requested = latchRecovery(data)
		return makeOutcome("Skipped", false, true, requested, false)
	end
	if not canAdvance(previous, nextSnapshot) then
		return makeOutcome("Rejected", false, data.recoveryRequired, false, false)
	end

	data.snapshot = nextSnapshot
	data.recoveryRequired = false
	return makeOutcome("Applied", true, false, false, false)
end

local function validateSnapshot(value: unknown): WaveProtocol.WaveSnapshot?
	local validationResult = WaveProtocol.validateWaveSnapshot(value)
	return if validationResult.ok then validationResult.value else nil
end

function ReducerMethods.observeEvent(self: Reducer, value: unknown): ApplyResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local snapshot = validateSnapshot(value)
	if snapshot == nil then
		return failure("INVALID_SNAPSHOT")
	end
	return Result.ok(observeCanonical(data, snapshot, "Event", false))
end

function ReducerMethods.observeGetResponse(
	self: Reducer,
	value: unknown,
	allowMatchReplacement: unknown,
	confirmRecoveryEpisode: unknown?
): ApplyResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if
		type(allowMatchReplacement) ~= "boolean"
		or (confirmRecoveryEpisode ~= nil and type(confirmRecoveryEpisode) ~= "boolean")
	then
		return failure("INVALID_ARGUMENT")
	end
	local snapshot = validateSnapshot(value)
	if snapshot == nil then
		return failure("INVALID_SNAPSHOT")
	end
	local outcome = observeCanonical(data, snapshot, "GetResponse", allowMatchReplacement :: boolean)
	if confirmRecoveryEpisode == true and outcome.kind == "Duplicate" and data.recoveryRequired then
		data.recoveryRequired = false
		outcome = makeOutcome("Duplicate", false, false, false, false)
	end
	return Result.ok(outcome)
end

function ReducerMethods.observeSubmitResponse(self: Reducer, value: unknown): ApplyResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local snapshot = validateSnapshot(value)
	if snapshot == nil then
		return failure("INVALID_SNAPSHOT")
	end
	return Result.ok(observeCanonical(data, snapshot, "SubmitResponse", false))
end

function ReducerMethods.getState(self: Reducer): StateResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	return Result.ok(table.freeze({
		locked = data.snapshot ~= nil,
		snapshot = data.snapshot,
		recoveryRequired = data.recoveryRequired,
	}))
end

function ReducerMethods.reset(self: Reducer): Result.Result<boolean, Error>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local changed = data.snapshot ~= nil or data.recoveryRequired
	data.snapshot = nil
	data.recoveryRequired = false
	return Result.ok(changed)
end

function ReducerMethods.cleanup(self: Reducer): Result.Success<boolean>
	local data = requireData(self)
	if data.cleaned then
		return CLEANUP_RESULT
	end
	data.cleaned = true
	data.snapshot = nil
	data.recoveryRequired = false
	return CLEANUP_RESULT
end

local WaveStateReducer = {}

function WaveStateReducer.new(): ReducerResult
	local reducer = setmetatable({}, ReducerMethods) :: Reducer
	table.freeze(reducer)
	REDUCER_DATA[reducer] = {
		snapshot = nil,
		recoveryRequired = false,
		cleaned = false,
	}
	return Result.ok(reducer)
end

table.freeze(ReducerMethods)
return table.freeze(WaveStateReducer)
