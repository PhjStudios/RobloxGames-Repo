--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type ParticipantState = "Active" | "Disconnected" | "Returned" | "Spectator"
export type AdmissionState = "Loading" | "ReadyCheck" | "PreWave" | "WaveActive" | "Results" | "Closing"

export type ParticipantSnapshot = {
	userId: number,
	state: ParticipantState,
	ready: boolean,
}

export type ConnectKind = "Admitted" | "Reactivated" | "Spectator" | "Returned" | "UntrackedSpectator"

export type ConnectOutcome = {
	kind: ConnectKind,
	changed: boolean,
	participant: ParticipantSnapshot?,
}

export type ReadinessSnapshot = {
	activeCount: number,
	readyActiveCount: number,
	allActiveReady: boolean,
}

export type ReturnBatchOutcome = {
	changedCount: number,
}

export type Operation =
	"connect"
	| "disconnect"
	| "resolveConnection"
	| "setReadyForConnection"
	| "getSnapshot"
	| "getReadiness"
	| "markUnreadyActiveReturned"
	| "cleanup"

export type ErrorCode =
	"INVALID_CONNECTION"
	| "INVALID_USER_ID"
	| "INVALID_MATCH_STATE"
	| "EPOCH_EXHAUSTED"
	| "DUPLICATE_CONNECTION"
	| "UNKNOWN_CONNECTION"
	| "STALE_CONNECTION"
	| "UNTRACKED_SPECTATOR"
	| "INACTIVE_PARTICIPANT"
	| "ALREADY_DISCONNECTED"
	| "ALREADY_READY"
	| "CLEANED"

export type RosterError = {
	code: ErrorCode,
	operation: Operation,
}

type ParticipantRecord = {
	state: ParticipantState,
	ready: boolean,
}

type ConnectionBinding = {
	userId: number,
	epoch: number,
	tracked: boolean,
}

type ConnectionTable = { [any]: ConnectionBinding }

type RosterData = {
	records: { [number]: ParticipantRecord },
	epochs: { [number]: number },
	connections: ConnectionTable,
	admittedCount: number,
	orderedUserIds: { number }?,
	cleaned: boolean,
}

local RosterMethods = {}
RosterMethods.__index = RosterMethods

export type Roster = typeof(setmetatable({} :: {}, RosterMethods))

local MAX_PARTICIPANTS = 4

local ADMISSION_STATES: { [string]: boolean } = table.freeze({
	Loading = true,
	ReadyCheck = true,
})

local MATCH_STATES: { [string]: boolean } = table.freeze({
	Loading = true,
	ReadyCheck = true,
	PreWave = true,
	WaveActive = true,
	Results = true,
	Closing = true,
})

local ROSTER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: RosterData }

local ParticipantRoster = {
	MAX_PARTICIPANTS = MAX_PARTICIPANTS,
}

local function weakConnectionTable(): ConnectionTable
	return setmetatable({}, { __mode = "k" }) :: ConnectionTable
end

local function makeError(code: ErrorCode, operation: Operation): RosterError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<RosterError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): RosterData
	if type(value) ~= "table" then
		error("[ATD_PARTICIPANT_ROSTER][code=INVALID_CONTEXT]", 0)
	end

	local data = ROSTER_DATA[value :: any]
	if data == nil then
		error("[ATD_PARTICIPANT_ROSTER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function isConnectionKey(value: unknown): boolean
	if type(value) == "table" then
		return true
	end
	if typeof(value) ~= "Instance" then
		return false
	end
	return (value :: Instance):IsA("Player")
end

local function isUserId(value: unknown): boolean
	return type(value) == "number" and value ~= 0 and Validation.isSafeInteger(value)
end

local function isMatchState(value: unknown): boolean
	return type(value) == "string" and MATCH_STATES[value] == true
end

local function participantSnapshot(userId: number, record: ParticipantRecord): ParticipantSnapshot
	return table.freeze({
		userId = userId,
		state = record.state,
		ready = record.ready,
	})
end

local function connectOutcome(kind: ConnectKind, changed: boolean, participant: ParticipantSnapshot?): ConnectOutcome
	return table.freeze({
		kind = kind,
		changed = changed,
		participant = participant,
	})
end

local function invalidateOrdering(data: RosterData)
	data.orderedUserIds = nil
end

local function orderedUserIds(data: RosterData): { number }
	local cached = data.orderedUserIds
	if cached ~= nil then
		return cached
	end

	local userIds: { number } = table.create(data.admittedCount)
	for userId in data.records do
		table.insert(userIds, userId)
	end
	table.sort(userIds)
	data.orderedUserIds = table.freeze(userIds)
	return data.orderedUserIds :: { number }
end

local function resolveBinding(
	data: RosterData,
	connectionValue: unknown,
	operation: Operation
): (number?, ParticipantRecord?, RosterError?)
	if data.cleaned then
		return nil, nil, makeError("CLEANED", operation)
	end
	if not isConnectionKey(connectionValue) then
		return nil, nil, makeError("INVALID_CONNECTION", operation)
	end

	local binding = data.connections[connectionValue :: any]
	if binding == nil then
		return nil, nil, makeError("UNKNOWN_CONNECTION", operation)
	end
	if not binding.tracked then
		return nil, nil, makeError("UNTRACKED_SPECTATOR", operation)
	end

	local currentEpoch = data.epochs[binding.userId]
	if currentEpoch == nil or currentEpoch ~= binding.epoch then
		return nil, nil, makeError("STALE_CONNECTION", operation)
	end

	local record = data.records[binding.userId]
	if record == nil then
		return nil, nil, makeError("UNKNOWN_CONNECTION", operation)
	end
	return binding.userId, record, nil
end

function RosterMethods.connect(
	self: Roster,
	connectionValue: unknown,
	userIdValue: unknown,
	matchStateValue: unknown
): Result.Result<ConnectOutcome, RosterError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "connect")
	end
	if not isConnectionKey(connectionValue) then
		return failure("INVALID_CONNECTION", "connect")
	end
	if not isUserId(userIdValue) then
		return failure("INVALID_USER_ID", "connect")
	end
	if not isMatchState(matchStateValue) then
		return failure("INVALID_MATCH_STATE", "connect")
	end
	if data.connections[connectionValue :: any] ~= nil then
		return failure("DUPLICATE_CONNECTION", "connect")
	end

	local userId = userIdValue :: number
	local matchState = matchStateValue :: AdmissionState
	local record = data.records[userId]
	if record ~= nil then
		if record.state == "Active" or record.state == "Spectator" then
			return failure("DUPLICATE_CONNECTION", "connect")
		end

		local currentEpoch = data.epochs[userId] or 0
		if currentEpoch >= Validation.MAX_SAFE_INTEGER then
			return failure("EPOCH_EXHAUSTED", "connect")
		end
		local nextEpoch = currentEpoch + 1
		data.epochs[userId] = nextEpoch
		data.connections[connectionValue :: any] = {
			userId = userId,
			epoch = nextEpoch,
			tracked = true,
		}

		if record.state == "Returned" then
			return Result.ok(connectOutcome("Returned", false, participantSnapshot(userId, record)))
		end

		if ADMISSION_STATES[matchState] == true then
			record.state = "Active"
			record.ready = false
			return Result.ok(connectOutcome("Reactivated", true, participantSnapshot(userId, record)))
		end

		record.state = "Spectator"
		record.ready = false
		return Result.ok(connectOutcome("Spectator", true, participantSnapshot(userId, record)))
	end

	if ADMISSION_STATES[matchState] ~= true or data.admittedCount >= MAX_PARTICIPANTS then
		data.connections[connectionValue :: any] = {
			userId = userId,
			epoch = 0,
			tracked = false,
		}
		return Result.ok(connectOutcome("UntrackedSpectator", false, nil))
	end

	data.records[userId] = {
		state = "Active",
		ready = false,
	}
	data.epochs[userId] = 1
	data.connections[connectionValue :: any] = {
		userId = userId,
		epoch = 1,
		tracked = true,
	}
	data.admittedCount += 1
	invalidateOrdering(data)
	return Result.ok(connectOutcome("Admitted", true, participantSnapshot(userId, data.records[userId])))
end

function RosterMethods.disconnect(
	self: Roster,
	connectionValue: unknown
): Result.Result<ParticipantSnapshot, RosterError>
	local data = requireData(self)
	local userId, record, resolveError = resolveBinding(data, connectionValue, "disconnect")
	if record == nil then
		return Result.err(resolveError :: RosterError)
	end

	if record.state == "Disconnected" then
		return failure("ALREADY_DISCONNECTED", "disconnect")
	end
	if record.state ~= "Active" then
		return failure("INACTIVE_PARTICIPANT", "disconnect")
	end

	record.state = "Disconnected"
	record.ready = false
	return Result.ok(participantSnapshot(userId :: number, record))
end

function RosterMethods.resolveConnection(
	self: Roster,
	connectionValue: unknown
): Result.Result<ParticipantSnapshot, RosterError>
	local data = requireData(self)
	local userId, record, resolveError = resolveBinding(data, connectionValue, "resolveConnection")
	if record == nil then
		return Result.err(resolveError :: RosterError)
	end
	return Result.ok(participantSnapshot(userId :: number, record))
end

function RosterMethods.setReadyForConnection(
	self: Roster,
	connectionValue: unknown
): Result.Result<ParticipantSnapshot, RosterError>
	local data = requireData(self)
	local userId, record, resolveError = resolveBinding(data, connectionValue, "setReadyForConnection")
	if record == nil then
		return Result.err(resolveError :: RosterError)
	end
	if record.state ~= "Active" then
		return failure("INACTIVE_PARTICIPANT", "setReadyForConnection")
	end
	if record.ready then
		return failure("ALREADY_READY", "setReadyForConnection")
	end

	record.ready = true
	return Result.ok(participantSnapshot(userId :: number, record))
end

function RosterMethods.getSnapshot(self: Roster): Result.Result<{ ParticipantSnapshot }, RosterError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "getSnapshot")
	end

	local participants: { ParticipantSnapshot } = table.create(data.admittedCount)
	for _, userId in orderedUserIds(data) do
		local record = data.records[userId]
		if record ~= nil then
			table.insert(participants, participantSnapshot(userId, record))
		end
	end
	return Result.ok(table.freeze(participants))
end

function RosterMethods.getReadiness(self: Roster): Result.Result<ReadinessSnapshot, RosterError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "getReadiness")
	end

	local activeCount = 0
	local readyActiveCount = 0
	for _, record in data.records do
		if record.state == "Active" then
			activeCount += 1
			if record.ready then
				readyActiveCount += 1
			end
		end
	end

	return Result.ok(table.freeze({
		activeCount = activeCount,
		readyActiveCount = readyActiveCount,
		allActiveReady = activeCount > 0 and activeCount == readyActiveCount,
	}))
end

function RosterMethods.markUnreadyActiveReturned(self: Roster): Result.Result<ReturnBatchOutcome, RosterError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "markUnreadyActiveReturned")
	end

	local changedCount = 0
	for _, record in data.records do
		if record.state == "Active" and not record.ready then
			record.state = "Returned"
			record.ready = false
			changedCount += 1
		end
	end
	return Result.ok(table.freeze({
		changedCount = changedCount,
	}))
end

function RosterMethods.isCleaned(self: Roster): boolean
	return requireData(self).cleaned
end

function RosterMethods.cleanup(self: Roster): Result.Result<boolean, RosterError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end

	data.cleaned = true
	data.records = {}
	data.epochs = {}
	data.connections = weakConnectionTable()
	data.admittedCount = 0
	data.orderedUserIds = nil
	return Result.ok(true)
end

function ParticipantRoster.new(): Result.Result<Roster, RosterError>
	local roster = setmetatable({}, RosterMethods) :: Roster
	table.freeze(roster)
	ROSTER_DATA[roster] = {
		records = {},
		epochs = {},
		connections = weakConnectionTable(),
		admittedCount = 0,
		orderedUserIds = nil,
		cleaned = false,
	}
	return Result.ok(roster)
end

table.freeze(RosterMethods)
return table.freeze(ParticipantRoster)
