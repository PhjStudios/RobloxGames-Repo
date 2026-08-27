--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type MatchState = "Loading" | "ReadyCheck" | "PreWave" | "WaveActive" | "Results" | "Closing"

export type StateSnapshot = {
	matchId: Ids.MatchId,
	revision: number,
	state: MatchState,
}

export type Operation =
	"new"
	| "beginTransition"
	| "commitTransition"
	| "rollbackTransition"
	| "touch"
	| "getSnapshot"
	| "cleanup"

export type ErrorCode =
	"INVALID_MATCH_ID"
	| "INVALID_TARGET"
	| "INVALID_REVISION"
	| "STALE_REVISION"
	| "REVISION_EXHAUSTED"
	| "DUPLICATE_TRANSITION"
	| "ILLEGAL_TRANSITION"
	| "TRANSITION_IN_PROGRESS"
	| "TERMINAL_STATE"
	| "INVALID_TOKEN"
	| "CLEANED"

export type StateMachineError = {
	code: ErrorCode,
	operation: Operation,
}

export type TransitionToken = {}

local StateMachineMethods = {}
StateMachineMethods.__index = StateMachineMethods

export type StateMachine = typeof(setmetatable({} :: {}, StateMachineMethods))

type TokenData = {
	machine: StateMachine,
	fromState: MatchState,
	targetState: MatchState,
	expectedRevision: number,
}

type StateMachineData = {
	matchId: Ids.MatchId,
	state: MatchState,
	revision: number,
	activeToken: TransitionToken?,
	cleaned: boolean,
}

local INITIAL_REVISION = 1

local MATCH_STATES: { MatchState } = table.freeze({
	"Loading",
	"ReadyCheck",
	"PreWave",
	"WaveActive",
	"Results",
	"Closing",
})

local MATCH_STATE_SET: { [string]: boolean } = table.freeze({
	Loading = true,
	ReadyCheck = true,
	PreWave = true,
	WaveActive = true,
	Results = true,
	Closing = true,
})

local LEGAL_TRANSITIONS: { [MatchState]: { [MatchState]: boolean } } = table.freeze({
	Loading = table.freeze({
		ReadyCheck = true,
		Closing = true,
	}),
	ReadyCheck = table.freeze({
		PreWave = true,
		Closing = true,
	}),
	PreWave = table.freeze({
		WaveActive = true,
		Closing = true,
	}),
	WaveActive = table.freeze({
		Results = true,
		Closing = true,
	}),
	Results = table.freeze({
		Closing = true,
	}),
	Closing = table.freeze({}),
})

local STATE_MACHINE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: StateMachineData }
local TOKEN_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: TokenData }

local MatchStateMachine = {
	INITIAL_REVISION = INITIAL_REVISION,
	STATES = MATCH_STATES,
}

local function makeError(code: ErrorCode, operation: Operation): StateMachineError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<StateMachineError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): StateMachineData
	if type(value) ~= "table" then
		error("[ATD_MATCH_STATE_MACHINE][code=INVALID_CONTEXT]", 0)
	end

	local data = STATE_MACHINE_DATA[value :: any]
	if data == nil then
		error("[ATD_MATCH_STATE_MACHINE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function isMatchState(value: unknown): boolean
	return type(value) == "string" and MATCH_STATE_SET[value] == true
end

local function isExpectedRevision(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value) and value >= INITIAL_REVISION
end

local function snapshot(data: StateMachineData): StateSnapshot
	return table.freeze({
		matchId = data.matchId,
		revision = data.revision,
		state = data.state,
	})
end

local function validateLiveRevision(
	data: StateMachineData,
	expectedRevisionValue: unknown,
	operation: Operation
): StateMachineError?
	if data.cleaned then
		return makeError("CLEANED", operation)
	end
	if not isExpectedRevision(expectedRevisionValue) then
		return makeError("INVALID_REVISION", operation)
	end
	if expectedRevisionValue ~= data.revision then
		return makeError("STALE_REVISION", operation)
	end
	return nil
end

local function validateToken(
	self: StateMachine,
	data: StateMachineData,
	tokenValue: unknown,
	operation: Operation
): (TokenData?, StateMachineError?)
	if data.cleaned then
		return nil, makeError("CLEANED", operation)
	end
	if type(tokenValue) ~= "table" then
		return nil, makeError("INVALID_TOKEN", operation)
	end

	local tokenData = TOKEN_DATA[tokenValue :: any]
	if tokenData == nil or tokenData.machine ~= self or data.activeToken ~= tokenValue then
		return nil, makeError("INVALID_TOKEN", operation)
	end
	if tokenData.fromState ~= data.state or tokenData.expectedRevision ~= data.revision then
		return nil, makeError("INVALID_TOKEN", operation)
	end
	return tokenData, nil
end

function StateMachineMethods.beginTransition(
	self: StateMachine,
	targetStateValue: unknown,
	expectedRevisionValue: unknown
): Result.Result<TransitionToken, StateMachineError>
	local data = requireData(self)
	local revisionError = validateLiveRevision(data, expectedRevisionValue, "beginTransition")
	if revisionError ~= nil then
		return Result.err(revisionError)
	end
	if not isMatchState(targetStateValue) then
		return failure("INVALID_TARGET", "beginTransition")
	end
	if data.activeToken ~= nil then
		return failure("TRANSITION_IN_PROGRESS", "beginTransition")
	end
	if data.state == "Closing" then
		return failure("TERMINAL_STATE", "beginTransition")
	end

	local targetState = targetStateValue :: MatchState
	if targetState == data.state then
		return failure("DUPLICATE_TRANSITION", "beginTransition")
	end
	if LEGAL_TRANSITIONS[data.state][targetState] ~= true then
		return failure("ILLEGAL_TRANSITION", "beginTransition")
	end
	if data.revision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", "beginTransition")
	end

	local token = table.freeze({}) :: TransitionToken
	TOKEN_DATA[token] = {
		machine = self,
		fromState = data.state,
		targetState = targetState,
		expectedRevision = data.revision,
	}
	data.activeToken = token
	return Result.ok(token)
end

function StateMachineMethods.commitTransition(
	self: StateMachine,
	tokenValue: unknown
): Result.Result<StateSnapshot, StateMachineError>
	local data = requireData(self)
	local tokenData, tokenError = validateToken(self, data, tokenValue, "commitTransition")
	if tokenData == nil then
		return Result.err(tokenError :: StateMachineError)
	end

	TOKEN_DATA[tokenValue :: any] = nil
	data.activeToken = nil
	data.state = tokenData.targetState
	data.revision += 1
	return Result.ok(snapshot(data))
end

function StateMachineMethods.rollbackTransition(
	self: StateMachine,
	tokenValue: unknown
): Result.Result<StateSnapshot, StateMachineError>
	local data = requireData(self)
	local tokenData, tokenError = validateToken(self, data, tokenValue, "rollbackTransition")
	if tokenData == nil then
		return Result.err(tokenError :: StateMachineError)
	end
	local _ = tokenData

	TOKEN_DATA[tokenValue :: any] = nil
	data.activeToken = nil
	return Result.ok(snapshot(data))
end

function StateMachineMethods.touch(
	self: StateMachine,
	expectedRevisionValue: unknown
): Result.Result<StateSnapshot, StateMachineError>
	local data = requireData(self)
	local revisionError = validateLiveRevision(data, expectedRevisionValue, "touch")
	if revisionError ~= nil then
		return Result.err(revisionError)
	end
	if data.activeToken ~= nil then
		return failure("TRANSITION_IN_PROGRESS", "touch")
	end
	if data.state == "Closing" then
		return failure("TERMINAL_STATE", "touch")
	end
	if data.revision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", "touch")
	end

	data.revision += 1
	return Result.ok(snapshot(data))
end

function StateMachineMethods.getSnapshot(self: StateMachine): Result.Result<StateSnapshot, StateMachineError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "getSnapshot")
	end
	return Result.ok(snapshot(data))
end

function StateMachineMethods.getMatchId(self: StateMachine): Ids.MatchId
	return requireData(self).matchId
end

function StateMachineMethods.getState(self: StateMachine): MatchState
	return requireData(self).state
end

function StateMachineMethods.getRevision(self: StateMachine): number
	return requireData(self).revision
end

function StateMachineMethods.isCleaned(self: StateMachine): boolean
	return requireData(self).cleaned
end

function StateMachineMethods.cleanup(self: StateMachine): Result.Result<boolean, StateMachineError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end

	local activeToken = data.activeToken
	if activeToken ~= nil then
		TOKEN_DATA[activeToken] = nil
	end
	data.activeToken = nil
	data.cleaned = true
	return Result.ok(true)
end

function MatchStateMachine.isMatchState(value: unknown): boolean
	return isMatchState(value)
end

function MatchStateMachine.isLegalTransition(fromStateValue: unknown, targetStateValue: unknown): boolean
	if not isMatchState(fromStateValue) or not isMatchState(targetStateValue) then
		return false
	end
	return LEGAL_TRANSITIONS[fromStateValue :: MatchState][targetStateValue :: MatchState] == true
end

function MatchStateMachine.new(matchIdValue: unknown): Result.Result<StateMachine, StateMachineError>
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if not matchIdResult.ok then
		return failure("INVALID_MATCH_ID", "new")
	end

	local machine = setmetatable({}, StateMachineMethods) :: StateMachine
	table.freeze(machine)
	STATE_MACHINE_DATA[machine] = {
		matchId = matchIdResult.value,
		state = "Loading",
		revision = INITIAL_REVISION,
		activeToken = nil,
		cleaned = false,
	}
	return Result.ok(machine)
end

table.freeze(StateMachineMethods)
return table.freeze(MatchStateMachine)
