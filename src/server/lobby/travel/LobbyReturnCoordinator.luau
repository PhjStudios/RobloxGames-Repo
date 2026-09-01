--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Dependencies = {
	clock: () -> unknown,
	returnRecords: any,
	party: any,
	isPresent: (number) -> unknown,
	isProfileReady: (number) -> unknown,
	reconstructionGraceSeconds: number?,
	lobbyClaimId: string,
}

export type Admission = {
	returnId: string,
	matchId: string,
	expectedCount: number,
	arrivedCount: number,
}

export type ErrorCode =
	"INVALID_DEPENDENCIES"
	| "INVALID_JOIN_DATA"
	| "RETURN_UNAVAILABLE"
	| "RETURN_FINALIZED"
	| "CLEANED"
export type ReturnCoordinatorError = { code: ErrorCode, operation: string }

type ServiceData = {
	dependencies: Dependencies,
	finalized: { [string]: number },
	firstAdmissionAt: { [string]: number },
	reconstructionGraceSeconds: number,
	nextStepAt: number,
	cleaned: boolean,
	admissionCount: number,
	reconstructionCount: number,
	soloFallbackCount: number,
}

local Methods = {}
Methods.__index = Methods
export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local LobbyReturnCoordinator = {}
local DEFAULT_RECONSTRUCTION_GRACE_SECONDS = 10
local MAX_RECONSTRUCTION_GRACE_SECONDS = 30
local MAX_TRACKED_RETURNS = 128
local RETURN_TRACKING_TTL_SECONDS = 600
local STEP_INTERVAL_SECONDS = 1

local function failure<T>(code: ErrorCode, operation: string): Result.Failure<ReturnCoordinatorError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_LOBBY_RETURN][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and value > 0
end

local function validClaimId(value: unknown): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 60
		and string.match(value :: string, "^[A-Za-z0-9_.:-]+$") ~= nil
end

local function currentTime(data: ServiceData): number?
	local called, value = pcall(data.dependencies.clock)
	return if called
			and type(value) == "number"
			and Validation.isSafeInteger(value :: number)
			and value >= 0
		then value :: number
		else nil
end

local function resultOk(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function admissionView(record: any): Admission
	local arrived = 0
	for _, member in record.members do
		arrived += if member.state == "Arrived" then 1 else 0
	end
	return table.freeze({
		returnId = record.returnId,
		matchId = record.matchId,
		expectedCount = #record.expectedUserIds,
		arrivedCount = arrived,
	})
end

local function countEntries(values: { [string]: number }): number
	local count = 0
	for _ in values do
		count += 1
	end
	return count
end

local function sweepTracking(data: ServiceData, nowValue: number)
	for returnId, expiresAt in data.finalized do
		if expiresAt <= nowValue then
			data.finalized[returnId] = nil
		end
	end
	for returnId, admittedAt in data.firstAdmissionAt do
		if admittedAt + RETURN_TRACKING_TTL_SECONDS <= nowValue then
			data.firstAdmissionAt[returnId] = nil
		end
	end
end

local function makeRoom(values: { [string]: number })
	if countEntries(values) < MAX_TRACKED_RETURNS then
		return
	end
	local oldestId: string? = nil
	local oldestTime = math.huge
	for returnId, trackedAt in values do
		if trackedAt < oldestTime or (trackedAt == oldestTime and (oldestId == nil or returnId < oldestId)) then
			oldestId = returnId
			oldestTime = trackedAt
		end
	end
	if oldestId ~= nil then
		values[oldestId] = nil
	end
end

local function rememberFinalized(data: ServiceData, returnId: string, nowValue: number)
	makeRoom(data.finalized)
	data.finalized[returnId] = nowValue + RETURN_TRACKING_TTL_SECONDS
end

function Methods.admitJoinData(
	self: Service,
	userIdValue: unknown,
	teleportDataValue: unknown
): Result.Result<Admission, ReturnCoordinatorError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "admitJoinData")
	end
	if not validUserId(userIdValue) then
		return failure("INVALID_JOIN_DATA", "admitJoinData")
	end
	local routing = TravelProtocol.validateRoutingData(teleportDataValue)
	if not routing.ok or routing.value.kind ~= "Return" then
		return failure("INVALID_JOIN_DATA", "admitJoinData")
	end
	local returnId = routing.value.returnId
	local nowValue = currentTime(data)
	if nowValue == nil then
		return failure("RETURN_UNAVAILABLE", "admitJoinData")
	end
	sweepTracking(data, nowValue)
	if data.finalized[returnId] ~= nil then
		return failure("RETURN_FINALIZED", "admitJoinData")
	end
	local called, admitted =
		pcall(data.dependencies.returnRecords.admit, data.dependencies.returnRecords, returnId, userIdValue, nowValue)
	if not called or not resultOk(admitted) then
		return failure("RETURN_UNAVAILABLE", "admitJoinData")
	end
	if data.firstAdmissionAt[returnId] == nil then
		makeRoom(data.firstAdmissionAt)
		data.firstAdmissionAt[returnId] = nowValue
	end
	data.admissionCount += 1
	return Result.ok(admissionView((admitted :: any).value.record))
end

function Methods.reconstruct(self: Service, returnIdValue: unknown): Result.Result<boolean, ReturnCoordinatorError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "reconstruct")
	end
	local returnId = TravelProtocol.validateOpaqueId(returnIdValue, "return")
	if not returnId.ok then
		return failure("INVALID_JOIN_DATA", "reconstruct")
	end
	local nowValue = currentTime(data)
	if nowValue == nil then
		return failure("RETURN_UNAVAILABLE", "reconstruct")
	end
	sweepTracking(data, nowValue)
	if data.finalized[returnId.value] ~= nil then
		return Result.ok(false)
	end
	local called, fetched =
		pcall(data.dependencies.returnRecords.get, data.dependencies.returnRecords, returnId.value, nowValue)
	if not called or not resultOk(fetched) then
		return failure("RETURN_UNAVAILABLE", "reconstruct")
	end
	local record = (fetched :: any).value
	local arrivedCount = 0
	for _, member in record.members do
		arrivedCount += if member.state == "Arrived" then 1 else 0
	end
	local firstAdmissionAt = data.firstAdmissionAt[returnId.value]
	local graceExpired = firstAdmissionAt ~= nil and nowValue - firstAdmissionAt >= data.reconstructionGraceSeconds
	if arrivedCount < #record.expectedUserIds and not graceExpired then
		return Result.ok(false)
	end
	local present: { number } = {}
	local leaderPresent = false
	for _, member in record.members do
		if member.state == "Arrived" then
			local presentCalled, isPresent = pcall(data.dependencies.isPresent, member.userId)
			local readyCalled, isReady = pcall(data.dependencies.isProfileReady, member.userId)
			if presentCalled and isPresent == true and readyCalled and isReady == true then
				table.insert(present, member.userId)
				leaderPresent = leaderPresent or member.userId == record.priorLeaderUserId
			end
		end
	end
	local reconstructed = false
	local claimReason = `LOBBY_CLAIM:{data.dependencies.lobbyClaimId}`
	local claimedCalled, claimed = pcall(
		data.dependencies.returnRecords.markTerminal,
		data.dependencies.returnRecords,
		returnId.value,
		claimReason,
		nowValue
	)
	local wonClaim = claimedCalled
		and resultOk(claimed)
		and type((claimed :: any).value) == "table"
		and (claimed :: any).value.applied == true
	if not wonClaim then
		rememberFinalized(data, returnId.value, nowValue)
		data.firstAdmissionAt[returnId.value] = nil
		data.soloFallbackCount += 1
		return Result.ok(false)
	end
	if #present >= 2 and leaderPresent then
		local partyCalled, partyResult =
			pcall(data.dependencies.party.reconstruct, data.dependencies.party, record.priorLeaderUserId, present)
		reconstructed = partyCalled and resultOk(partyResult)
	end
	rememberFinalized(data, returnId.value, nowValue)
	data.firstAdmissionAt[returnId.value] = nil
	if reconstructed then
		data.reconstructionCount += 1
	else
		data.soloFallbackCount += 1
	end
	return Result.ok(reconstructed)
end

function Methods.step(self: Service): Result.Result<number, ReturnCoordinatorError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "step")
	end
	local nowValue = currentTime(data)
	if nowValue == nil then
		return failure("RETURN_UNAVAILABLE", "step")
	end
	sweepTracking(data, nowValue)
	if nowValue < data.nextStepAt then
		return Result.ok(0)
	end
	data.nextStepAt = nowValue + STEP_INTERVAL_SECONDS
	local due: { string } = {}
	for returnId, admittedAt in data.firstAdmissionAt do
		if nowValue - admittedAt >= data.reconstructionGraceSeconds then
			table.insert(due, returnId)
		end
	end
	table.sort(due)
	for _, returnId in due do
		self:reconstruct(returnId)
	end
	return Result.ok(#due)
end

function Methods.cleanup(self: Service): Result.Result<boolean, ReturnCoordinatorError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	data.cleaned = true
	table.clear(data.finalized)
	table.clear(data.firstAdmissionAt)
	return Result.ok(true)
end

function Methods.getMetrics(self: Service): { [string]: number | boolean }
	local data = requireData(self)
	return table.freeze({
		admissionCount = data.admissionCount,
		reconstructionCount = data.reconstructionCount,
		soloFallbackCount = data.soloFallbackCount,
		trackedFinalizedCount = countEntries(data.finalized),
		trackedAdmissionCount = countEntries(data.firstAdmissionAt),
		cleaned = data.cleaned,
	})
end

function Methods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	return table.freeze({
		name = "LobbyReturnCoordinator",
		dependencies = table.freeze({}),
		initialize = function() end,
		start = function() end,
		shutdown = function()
			self:cleanup()
		end,
	})
end

function LobbyReturnCoordinator.new(dependenciesValue: unknown): Result.Result<Service, ReturnCoordinatorError>
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local dependencies = dependenciesValue :: any
	local graceSeconds = dependencies.reconstructionGraceSeconds or DEFAULT_RECONSTRUCTION_GRACE_SECONDS
	if
		type(dependencies.clock) ~= "function"
		or type(dependencies.returnRecords) ~= "table"
		or type(dependencies.returnRecords.admit) ~= "function"
		or type(dependencies.returnRecords.get) ~= "function"
		or type(dependencies.returnRecords.markTerminal) ~= "function"
		or type(dependencies.party) ~= "table"
		or type(dependencies.party.reconstruct) ~= "function"
		or type(dependencies.isPresent) ~= "function"
		or type(dependencies.isProfileReady) ~= "function"
		or not validClaimId(dependencies.lobbyClaimId)
		or type(graceSeconds) ~= "number"
		or not Validation.isSafeInteger(graceSeconds)
		or graceSeconds < 1
		or graceSeconds > MAX_RECONSTRUCTION_GRACE_SECONDS
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		dependencies = dependenciesValue :: Dependencies,
		finalized = {},
		firstAdmissionAt = {},
		reconstructionGraceSeconds = graceSeconds,
		nextStepAt = 0,
		cleaned = false,
		admissionCount = 0,
		reconstructionCount = 0,
		soloFallbackCount = 0,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(LobbyReturnCoordinator)
