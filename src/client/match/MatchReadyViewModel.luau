--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type RequestPresentationState = "Idle" | "Pending" | "Accepted" | "Rejected" | "StateChanged"
export type ParticipantRowStatus = "Ready" | "Waiting" | "Disconnected" | "Returned" | "Spectator"
export type ApplyKind = "Applied" | "Duplicate" | "Stale" | "WrongMatch"

export type ParticipantRow = {
	label: string,
	status: ParticipantRowStatus,
	isLocal: boolean,
}

export type RenderState = {
	matchId: string?,
	revision: number?,
	matchState: MatchProtocol.MatchState?,
	participantRows: { ParticipantRow },
	requestState: RequestPresentationState,
	rejectionCode: RequestProtocol.PublicErrorCode?,
	readyAvailable: boolean,
	countdownKnown: boolean,
	countdownSeconds: number?,
}

export type ApplyOutcome = {
	kind: ApplyKind,
}

export type ReadySubmission = {
	matchId: string,
	observedRevision: number,
}

export type ErrorCode =
	"INVALID_LOCAL_USER_ID"
	| "INVALID_SNAPSHOT"
	| "NO_SNAPSHOT"
	| "NOT_ELIGIBLE"
	| "REQUEST_PENDING"
	| "INVALID_REQUEST_STATE"
	| "INVALID_PUBLIC_ERROR"
	| "CLEANED_UP"

export type Error = {
	code: ErrorCode,
}

type ModelData = {
	localUserId: number,
	matchId: string?,
	snapshot: MatchProtocol.MatchSnapshot?,
	requestState: RequestPresentationState,
	rejectionCode: RequestProtocol.PublicErrorCode?,
	lastServerTime: number?,
	cleaned: boolean,
}

local ModelMethods = {}
ModelMethods.__index = ModelMethods

export type Model = typeof(setmetatable({} :: {}, ModelMethods))
export type ModelResult = Result.Result<Model, Error>
export type ApplyResult = Result.Result<ApplyOutcome, Error>
export type BeginReadyResult = Result.Result<ReadySubmission, Error>
export type RequestStateResult = Result.Result<RequestPresentationState, Error>
export type RenderResult = Result.Result<RenderState, Error>

local MODEL_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ModelData }

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_LOCAL_USER_ID = table.freeze({ code = "INVALID_LOCAL_USER_ID" :: "INVALID_LOCAL_USER_ID" }),
	INVALID_SNAPSHOT = table.freeze({ code = "INVALID_SNAPSHOT" :: "INVALID_SNAPSHOT" }),
	NO_SNAPSHOT = table.freeze({ code = "NO_SNAPSHOT" :: "NO_SNAPSHOT" }),
	NOT_ELIGIBLE = table.freeze({ code = "NOT_ELIGIBLE" :: "NOT_ELIGIBLE" }),
	REQUEST_PENDING = table.freeze({ code = "REQUEST_PENDING" :: "REQUEST_PENDING" }),
	INVALID_REQUEST_STATE = table.freeze({ code = "INVALID_REQUEST_STATE" :: "INVALID_REQUEST_STATE" }),
	INVALID_PUBLIC_ERROR = table.freeze({ code = "INVALID_PUBLIC_ERROR" :: "INVALID_PUBLIC_ERROR" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local APPLY_OUTCOMES: { [ApplyKind]: ApplyOutcome } = table.freeze({
	Applied = table.freeze({ kind = "Applied" :: "Applied" }),
	Duplicate = table.freeze({ kind = "Duplicate" :: "Duplicate" }),
	Stale = table.freeze({ kind = "Stale" :: "Stale" }),
	WrongMatch = table.freeze({ kind = "WrongMatch" :: "WrongMatch" }),
})

local CLEANUP_RESULT = Result.ok(true)

local function failure(code: ErrorCode)
	return Result.err(ERRORS[code])
end

local function requireData(value: unknown): ModelData
	if type(value) ~= "table" then
		error("[ATD_MATCH_READY_VIEW_MODEL][code=INVALID_CONTEXT]", 0)
	end
	local data = MODEL_DATA[value :: any]
	if data == nil then
		error("[ATD_MATCH_READY_VIEW_MODEL][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function findLocalParticipant(
	snapshot: MatchProtocol.MatchSnapshot,
	localUserId: number
): MatchProtocol.ParticipantSnapshot?
	for _, participant in snapshot.participants do
		if participant.userId == localUserId then
			return participant
		end
	end
	return nil
end

local function isReadyAvailable(data: ModelData): boolean
	local snapshot = data.snapshot
	if snapshot == nil or snapshot.state ~= "ReadyCheck" or data.requestState == "Pending" then
		return false
	end
	local participant = findLocalParticipant(snapshot, data.localUserId)
	return participant ~= nil and participant.state == "Active" and not participant.ready
end

local function statusFor(participant: MatchProtocol.ParticipantSnapshot): ParticipantRowStatus
	if participant.state == "Active" then
		return if participant.ready then "Ready" else "Waiting"
	elseif participant.state == "Disconnected" then
		return "Disconnected"
	elseif participant.state == "Returned" then
		return "Returned"
	else
		return "Spectator"
	end
end

local function updateRequestStateForSnapshot(
	data: ModelData,
	previous: MatchProtocol.MatchSnapshot?,
	nextSnapshot: MatchProtocol.MatchSnapshot
)
	if previous ~= nil and previous.state ~= nextSnapshot.state and data.requestState ~= "Idle" then
		data.requestState = "StateChanged"
		data.rejectionCode = nil
		return
	end

	if data.requestState ~= "Pending" then
		return
	end
	local participant = findLocalParticipant(nextSnapshot, data.localUserId)
	if participant ~= nil and participant.state == "Active" and participant.ready then
		data.requestState = "Accepted"
		data.rejectionCode = nil
	elseif participant == nil or participant.state ~= "Active" then
		data.requestState = "StateChanged"
		data.rejectionCode = nil
	end
end

function ModelMethods.applySnapshot(self: Model, value: unknown): ApplyResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end

	local validationResult = MatchProtocol.validateMatchSnapshot(value)
	if not validationResult.ok then
		return failure("INVALID_SNAPSHOT")
	end
	local nextSnapshot = validationResult.value
	local lockedMatchId = data.matchId
	if lockedMatchId ~= nil then
		if nextSnapshot.matchId ~= lockedMatchId then
			return Result.ok(APPLY_OUTCOMES.WrongMatch)
		end
		local currentSnapshot = data.snapshot :: MatchProtocol.MatchSnapshot
		if nextSnapshot.revision == currentSnapshot.revision then
			return Result.ok(APPLY_OUTCOMES.Duplicate)
		elseif nextSnapshot.revision < currentSnapshot.revision then
			return Result.ok(APPLY_OUTCOMES.Stale)
		end
	end

	local previous = data.snapshot
	data.matchId = nextSnapshot.matchId
	data.snapshot = nextSnapshot
	updateRequestStateForSnapshot(data, previous, nextSnapshot)
	return Result.ok(APPLY_OUTCOMES.Applied)
end

function ModelMethods.beginReady(self: Model): BeginReadyResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if data.requestState == "Pending" then
		return failure("REQUEST_PENDING")
	end
	local snapshot = data.snapshot
	if snapshot == nil then
		return failure("NO_SNAPSHOT")
	end
	if not isReadyAvailable(data) then
		return failure("NOT_ELIGIBLE")
	end

	data.requestState = "Pending"
	data.rejectionCode = nil
	return Result.ok(table.freeze({
		matchId = snapshot.matchId,
		observedRevision = snapshot.revision,
	}))
end

function ModelMethods.acceptReady(self: Model): RequestStateResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if data.requestState == "Pending" then
		data.requestState = "Accepted"
		data.rejectionCode = nil
	elseif data.requestState ~= "Accepted" and data.requestState ~= "StateChanged" then
		return failure("INVALID_REQUEST_STATE")
	end
	return Result.ok(data.requestState)
end

function ModelMethods.rejectReady(self: Model, code: unknown): RequestStateResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not RequestProtocol.isPublicErrorCode(code) then
		return failure("INVALID_PUBLIC_ERROR")
	end
	local publicCode = code :: RequestProtocol.PublicErrorCode
	if data.requestState == "Pending" then
		data.requestState = "Rejected"
		data.rejectionCode = publicCode
	elseif
		data.requestState ~= "StateChanged"
		and not (data.requestState == "Rejected" and data.rejectionCode == publicCode)
	then
		return failure("INVALID_REQUEST_STATE")
	end
	return Result.ok(data.requestState)
end

function ModelMethods.getRenderState(self: Model, serverTime: unknown): RenderResult
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end

	local participantRows: { ParticipantRow } = {}
	local snapshot = data.snapshot
	if snapshot ~= nil then
		for index, participant in snapshot.participants do
			local isLocal = participant.userId == data.localUserId
			participantRows[index] = table.freeze({
				label = `Player {index}`,
				status = statusFor(participant),
				isLocal = isLocal,
			})
		end
	end
	table.freeze(participantRows)

	local countdownKnown = false
	local countdownSeconds: number? = nil
	if snapshot ~= nil and snapshot.state == "ReadyCheck" and snapshot.deadlineServerTime ~= nil then
		if
			type(serverTime) == "number"
			and Validation.isFiniteNumber(serverTime)
			and serverTime >= 0
			and (data.lastServerTime == nil or serverTime >= data.lastServerTime)
		then
			data.lastServerTime = serverTime
			countdownKnown = true
			countdownSeconds = math.ceil(math.max(snapshot.deadlineServerTime - serverTime, 0))
		end
	end

	return Result.ok(table.freeze({
		matchId = if snapshot == nil then nil else snapshot.matchId,
		revision = if snapshot == nil then nil else snapshot.revision,
		matchState = if snapshot == nil then nil else snapshot.state,
		participantRows = participantRows,
		requestState = data.requestState,
		rejectionCode = data.rejectionCode,
		readyAvailable = isReadyAvailable(data),
		countdownKnown = countdownKnown,
		countdownSeconds = countdownSeconds,
	}))
end

function ModelMethods.cleanup(self: Model): Result.Success<boolean>
	local data = requireData(self)
	if data.cleaned then
		return CLEANUP_RESULT
	end
	data.cleaned = true
	data.localUserId = 0
	data.matchId = nil
	data.snapshot = nil
	data.requestState = "Idle"
	data.rejectionCode = nil
	data.lastServerTime = nil
	return CLEANUP_RESULT
end

local MatchReadyViewModel = {}

function MatchReadyViewModel.new(localUserId: unknown): ModelResult
	if type(localUserId) ~= "number" or not Validation.isSafeInteger(localUserId) or (localUserId :: number) == 0 then
		return failure("INVALID_LOCAL_USER_ID")
	end

	local model = setmetatable({}, ModelMethods) :: Model
	table.freeze(model)
	MODEL_DATA[model] = {
		localUserId = localUserId :: number,
		matchId = nil,
		snapshot = nil,
		requestState = "Idle",
		rejectionCode = nil,
		lastServerTime = nil,
		cleaned = false,
	}
	return Result.ok(model)
end

table.freeze(ModelMethods)
return table.freeze(MatchReadyViewModel)
