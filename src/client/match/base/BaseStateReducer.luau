--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)

export type ApplyKind = "Applied" | "Feedback" | "Duplicate" | "Stale" | "Foreign" | "Rejected"

export type DamageFeedback = {
	baseRevision: number,
	appliedDamage: number,
	leakCount: number,
	lowHealthCrossed: boolean,
}

export type ApplyOutcome = {
	kind: ApplyKind,
	stateChanged: boolean,
	feedback: DamageFeedback?,
}

export type ConvergedState = {
	locked: boolean,
	snapshot: BaseProtocol.BaseSnapshot?,
	lastFeedbackRevision: number?,
}

export type ErrorCode = "INVALID_SNAPSHOT" | "INVALID_MESSAGE" | "CLEANED_UP"

export type Error = {
	code: ErrorCode,
}

type ReducerData = {
	snapshot: BaseProtocol.BaseSnapshot?,
	lastFeedbackRevision: number?,
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
	INVALID_MESSAGE = table.freeze({ code = "INVALID_MESSAGE" :: "INVALID_MESSAGE" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local CLEANUP_RESULT = Result.ok(true)

local function failure(code: ErrorCode)
	return Result.err(ERRORS[code])
end

local function requireData(value: unknown): ReducerData
	if type(value) ~= "table" then
		error("[ATD_BASE_STATE_REDUCER][code=INVALID_CONTEXT]", 0)
	end
	local data = REDUCER_DATA[value :: any]
	if data == nil then
		error("[ATD_BASE_STATE_REDUCER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function samePosition(left: Vector3, right: Vector3): boolean
	return left.X == right.X and left.Y == right.Y and left.Z == right.Z
end

local function sameIdentity(left: BaseProtocol.BaseSnapshot, right: BaseProtocol.BaseSnapshot): boolean
	return left.matchId == right.matchId and left.enemyEpoch == right.enemyEpoch
end

local function samePinnedIdentity(left: BaseProtocol.BaseSnapshot, right: BaseProtocol.BaseSnapshot): boolean
	return sameIdentity(left, right)
		and left.mapId == right.mapId
		and left.difficultyId == right.difficultyId
		and samePosition(left.basePosition, right.basePosition)
		and left.maximumHealth == right.maximumHealth
		and left.initializedServerTime == right.initializedServerTime
end

local function sameSnapshot(left: BaseProtocol.BaseSnapshot, right: BaseProtocol.BaseSnapshot): boolean
	return samePinnedIdentity(left, right)
		and left.baseRevision == right.baseRevision
		and left.status == right.status
		and left.currentHealth == right.currentHealth
		and left.lowHealth == right.lowHealth
		and left.updatedServerTime == right.updatedServerTime
end

local function isLegalStatusTransition(previous: string, nextStatus: string): boolean
	if previous == "Active" then
		return nextStatus == "Active" or nextStatus == "Defeated" or nextStatus == "Faulted"
	elseif previous == "Defeated" then
		return nextStatus == "Defeated"
	end
	return nextStatus == "Faulted"
end

local function canAdvance(previous: BaseProtocol.BaseSnapshot, nextSnapshot: BaseProtocol.BaseSnapshot): boolean
	return samePinnedIdentity(previous, nextSnapshot)
		and nextSnapshot.updatedServerTime >= previous.updatedServerTime
		and nextSnapshot.currentHealth <= previous.currentHealth
		and (not previous.lowHealth or nextSnapshot.lowHealth)
		and isLegalStatusTransition(previous.status, nextSnapshot.status)
end

local function outcome(kind: ApplyKind, stateChanged: boolean, feedback: DamageFeedback?): ApplyOutcome
	return table.freeze({
		kind = kind,
		stateChanged = stateChanged,
		feedback = feedback,
	})
end

local function makeFeedback(message: BaseProtocol.BaseDamageMessage): DamageFeedback
	return table.freeze({
		baseRevision = message.snapshot.baseRevision,
		appliedDamage = message.appliedDamage,
		leakCount = message.leakCount,
		lowHealthCrossed = message.lowHealthCrossed,
	})
end

local function observeCanonical(
	data: ReducerData,
	nextSnapshot: BaseProtocol.BaseSnapshot,
	damageMessage: BaseProtocol.BaseDamageMessage?
): ApplyOutcome
	local previous = data.snapshot
	if previous == nil then
		data.snapshot = nextSnapshot
		if damageMessage ~= nil then
			local feedback = makeFeedback(damageMessage)
			data.lastFeedbackRevision = nextSnapshot.baseRevision
			return outcome("Applied", true, feedback)
		end
		return outcome("Applied", true, nil)
	end

	if not sameIdentity(previous, nextSnapshot) then
		return outcome("Foreign", false, nil)
	end
	if not samePinnedIdentity(previous, nextSnapshot) then
		return outcome("Rejected", false, nil)
	end

	if nextSnapshot.baseRevision < previous.baseRevision then
		return outcome("Stale", false, nil)
	elseif nextSnapshot.baseRevision == previous.baseRevision then
		if not sameSnapshot(previous, nextSnapshot) then
			return outcome("Rejected", false, nil)
		end
		if damageMessage ~= nil and data.lastFeedbackRevision ~= nextSnapshot.baseRevision then
			local feedback = makeFeedback(damageMessage)
			data.lastFeedbackRevision = nextSnapshot.baseRevision
			return outcome("Feedback", false, feedback)
		end
		return outcome("Duplicate", false, nil)
	end

	if not canAdvance(previous, nextSnapshot) then
		return outcome("Rejected", false, nil)
	end
	if damageMessage ~= nil and nextSnapshot.currentHealth >= previous.currentHealth then
		return outcome("Rejected", false, nil)
	end

	data.snapshot = nextSnapshot
	if damageMessage ~= nil then
		local feedback = makeFeedback(damageMessage)
		data.lastFeedbackRevision = nextSnapshot.baseRevision
		return outcome("Applied", true, feedback)
	end
	return outcome("Applied", true, nil)
end

function ReducerMethods.observeSnapshot(self: Reducer, value: unknown): ApplyResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end

	local validationResult = BaseProtocol.validateBaseSnapshot(value)
	if not validationResult.ok then
		return failure("INVALID_SNAPSHOT")
	end
	return Result.ok(observeCanonical(data, validationResult.value, nil))
end

function ReducerMethods.observeMessage(self: Reducer, value: unknown): ApplyResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end

	local validationResult = BaseProtocol.validateBaseReplicationMessage(value)
	if not validationResult.ok then
		return failure("INVALID_MESSAGE")
	end
	local message = validationResult.value
	if message.kind == "Damage" then
		return Result.ok(observeCanonical(data, message.snapshot, message))
	end
	return Result.ok(observeCanonical(data, message.snapshot, nil))
end

function ReducerMethods.getState(self: Reducer): StateResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end

	return Result.ok(table.freeze({
		locked = data.snapshot ~= nil,
		snapshot = data.snapshot,
		lastFeedbackRevision = data.lastFeedbackRevision,
	}))
end

function ReducerMethods.cleanup(self: Reducer): Result.Success<boolean>
	local data = requireData(self)
	if data.cleaned then
		return CLEANUP_RESULT
	end
	data.cleaned = true
	data.snapshot = nil
	data.lastFeedbackRevision = nil
	return CLEANUP_RESULT
end

local BaseStateReducer = {}

function BaseStateReducer.new(): ReducerResult
	local reducer = setmetatable({}, ReducerMethods) :: Reducer
	table.freeze(reducer)
	REDUCER_DATA[reducer] = {
		snapshot = nil,
		lastFeedbackRevision = nil,
		cleaned = false,
	}
	return Result.ok(reducer)
end

table.freeze(ReducerMethods)
return table.freeze(BaseStateReducer)
