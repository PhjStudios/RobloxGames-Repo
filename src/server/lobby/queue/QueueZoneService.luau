--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type ZoneDefinition = {
	queueId: string,
	sampleUserIds: () -> unknown,
}

export type QueueOwner = {
	enterPhysical: (self: QueueOwner, string, number) -> unknown,
	leavePhysical: (self: QueueOwner, string, number) -> unknown,
}

export type Dependencies = {
	clock: () -> unknown,
	connectStep: ((() -> ()) -> RBXScriptConnection)?,
	sampleIntervalSeconds: number?,
}

export type ErrorCode =
	"INVALID_QUEUE_OWNER"
	| "INVALID_ZONES"
	| "INVALID_DEPENDENCIES"
	| "INVALID_TIME"
	| "WRONG_STATE"
	| "REENTRANT"
	| "CLEANED"

export type ServiceError = { code: ErrorCode, operation: string }

type ZoneState = {
	queueId: string,
	sampleUserIds: () -> unknown,
	previous: { [number]: boolean },
}

type LifecycleState = "Constructed" | "Initialized" | "Started" | "Shutdown"

type ServiceData = {
	queueOwner: QueueOwner,
	zones: { ZoneState },
	clock: () -> unknown,
	connectStep: ((() -> ()) -> RBXScriptConnection)?,
	sampleIntervalSeconds: number,
	lastSampleAt: number?,
	lastClock: number?,
	connection: RBXScriptConnection?,
	state: LifecycleState,
	busy: boolean,
	sampleCount: number,
	sampleFailureCount: number,
	enterAttemptCount: number,
	leaveAttemptCount: number,
	ownerFailureCount: number,
}

local Methods = {}
Methods.__index = Methods
export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local SERVICE_NAME = "QueueZoneService"
local DEFAULT_SAMPLE_INTERVAL_SECONDS = 0.15
local MIN_SAMPLE_INTERVAL_SECONDS = 0.05
local MAX_SAMPLE_INTERVAL_SECONDS = 1
local MAX_ZONES = 16
local MAX_SAMPLED_USERS = 128
local MAX_QUERY_PARTS = 512

local QueueZoneService = {
	MAX_ZONES = MAX_ZONES,
	MAX_SAMPLED_USERS = MAX_SAMPLED_USERS,
	MAX_QUERY_PARTS = MAX_QUERY_PARTS,
}

local function failure<T>(code: ErrorCode, operation: string): Result.Failure<ServiceError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_QUEUE_ZONE_SERVICE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed or coroutine.status(thread) ~= "dead" then
		if resumed then
			pcall(coroutine.close, thread)
		end
		return false, nil
	end
	return true, value
end

local function readTime(data: ServiceData): number?
	local called, value = callNonYielding(data.clock)
	if
		not called
		or type(value) ~= "number"
		or not Validation.isFiniteNumber(value)
		or (value :: number) < 0
		or (data.lastClock ~= nil and (value :: number) < data.lastClock)
	then
		return nil
	end
	data.lastClock = value :: number
	return value :: number
end

local function parseSample(value: unknown): { number }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local raw = value :: { [any]: unknown }
	local maximum = 0
	local keyCount = 0
	for key in raw do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > MAX_SAMPLED_USERS then
			return nil
		end
		keyCount += 1
		maximum = math.max(maximum, key)
	end
	if maximum ~= keyCount then
		return nil
	end
	local seen: { [number]: boolean } = {}
	local output: { number } = {}
	for index = 1, maximum do
		local userId = raw[index]
		if type(userId) ~= "number" or not Validation.isSafeInteger(userId) or userId <= 0 then
			return nil
		end
		if not seen[userId] then
			seen[userId] = true
			table.insert(output, userId)
		end
	end
	table.sort(output)
	return output
end

local function ownerCall(data: ServiceData, method: (...any) -> unknown, ...: any)
	local called, value = callNonYielding(method, data.queueOwner, ...)
	if not called or (type(value) == "table" and (value :: any).ok == false) then
		data.ownerFailureCount += 1
	end
end

local function reconcile(data: ServiceData, zone: ZoneState): boolean
	local called, sampledValue = callNonYielding(zone.sampleUserIds)
	if not called then
		data.sampleFailureCount += 1
		return false
	end
	local sampled = parseSample(sampledValue)
	if sampled == nil then
		data.sampleFailureCount += 1
		return false
	end
	local current: { [number]: boolean } = {}
	-- Retry every current occupant on every sample. This lets someone observed in
	-- two zones enter the deterministic surviving zone after leaving the first.
	for _, userId in sampled do
		current[userId] = true
		data.enterAttemptCount += 1
		ownerCall(data, data.queueOwner.enterPhysical, zone.queueId, userId)
	end
	local departed: { number } = {}
	for userId in zone.previous do
		if not current[userId] then
			table.insert(departed, userId)
		end
	end
	table.sort(departed)
	for _, userId in departed do
		data.leaveAttemptCount += 1
		ownerCall(data, data.queueOwner.leavePhysical, zone.queueId, userId)
	end
	zone.previous = current
	return true
end

function Methods.step(self: Service, forceValue: unknown?): Result.Result<number, ServiceError>
	local data = requireData(self)
	if data.state == "Shutdown" then
		return failure("CLEANED", "step")
	end
	if data.busy then
		return failure("REENTRANT", "step")
	end
	if forceValue ~= nil and type(forceValue) ~= "boolean" then
		return failure("INVALID_DEPENDENCIES", "step")
	end
	local currentTime = readTime(data)
	if currentTime == nil then
		return failure("INVALID_TIME", "step")
	end
	if
		forceValue ~= true
		and data.lastSampleAt ~= nil
		and currentTime - data.lastSampleAt < data.sampleIntervalSeconds
	then
		return Result.ok(0)
	end
	data.busy = true
	data.lastSampleAt = currentTime
	local succeeded = 0
	for _, zone in data.zones do
		if reconcile(data, zone) then
			succeeded += 1
		end
	end
	data.sampleCount += 1
	data.busy = false
	return Result.ok(succeeded)
end

local function initialize(data: ServiceData)
	if data.state ~= "Constructed" then
		error("[ATD_QUEUE_ZONE_SERVICE][code=INVALID_INITIALIZE_STATE]", 0)
	end
	data.state = "Initialized"
end

local function start(service: Service, data: ServiceData)
	if data.state ~= "Initialized" then
		error("[ATD_QUEUE_ZONE_SERVICE][code=INVALID_START_STATE]", 0)
	end
	if data.connectStep ~= nil then
		local connected, connection = pcall(data.connectStep, function()
			service:step(false)
		end)
		if not connected or typeof(connection) ~= "RBXScriptConnection" then
			error("[ATD_QUEUE_ZONE_SERVICE][code=CONNECTION_FAILED]", 0)
		end
		data.connection = connection :: RBXScriptConnection
	end
	data.state = "Started"
end

function Methods.cleanup(self: Service): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	if data.state == "Shutdown" then
		return Result.ok(true)
	end
	if data.busy then
		return failure("REENTRANT", "cleanup")
	end
	data.busy = true
	local connection = data.connection
	data.connection = nil
	if connection ~= nil then
		pcall(function()
			connection:Disconnect()
		end)
	end
	for _, zone in data.zones do
		local users: { number } = {}
		for userId in zone.previous do
			table.insert(users, userId)
		end
		table.sort(users)
		for _, userId in users do
			data.leaveAttemptCount += 1
			ownerCall(data, data.queueOwner.leavePhysical, zone.queueId, userId)
		end
		table.clear(zone.previous)
	end
	data.lastSampleAt = nil
	data.lastClock = nil
	data.state = "Shutdown"
	data.busy = false
	return Result.ok(true)
end

function Methods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	local data = requireData(self)
	return table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({}),
		initialize = function()
			initialize(data)
		end,
		start = function()
			start(self, data)
		end,
		shutdown = function()
			local cleaned = self:cleanup()
			if not cleaned.ok then
				error("[ATD_QUEUE_ZONE_SERVICE][code=CLEANUP_FAILED]", 0)
			end
		end,
	})
end

function Methods.getMetrics(self: Service): { [string]: number | string }
	local data = requireData(self)
	local tracked = 0
	for _, zone in data.zones do
		for _ in zone.previous do
			tracked += 1
		end
	end
	return table.freeze({
		state = data.state,
		zoneCount = #data.zones,
		trackedOccupantCount = tracked,
		sampleCount = data.sampleCount,
		sampleFailureCount = data.sampleFailureCount,
		enterAttemptCount = data.enterAttemptCount,
		leaveAttemptCount = data.leaveAttemptCount,
		ownerFailureCount = data.ownerFailureCount,
	})
end

function QueueZoneService.createWorkspaceSampler(
	queueIdValue: unknown,
	zonePartValue: unknown,
	workspaceValue: unknown,
	playersValue: unknown
): Result.Result<ZoneDefinition, ServiceError>
	local queueId = Ids.validateQueueId(queueIdValue)
	local zoneValid = typeof(zonePartValue) == "Instance" and (zonePartValue :: Instance):IsA("BasePart")
	local workspaceValid = typeof(workspaceValue) == "Instance" and (workspaceValue :: Instance):IsA("Workspace")
	local playersValid = typeof(playersValue) == "Instance" and (playersValue :: Instance):IsA("Players")
	if not queueId.ok or not zoneValid or not workspaceValid or not playersValid then
		return failure("INVALID_ZONES", "createWorkspaceSampler")
	end
	local zonePart = zonePartValue :: BasePart
	local workspace = workspaceValue :: Workspace
	local players = playersValue :: Players
	return Result.ok(table.freeze({
		queueId = queueId.value,
		sampleUserIds = function(): unknown
			if not zonePart:IsDescendantOf(workspace) then
				return {}
			end
			local characters: { Instance } = {}
			for _, player in players:GetPlayers() do
				local character = player.Character
				local humanoid = if character == nil then nil else character:FindFirstChildOfClass("Humanoid")
				if character ~= nil and character.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0 then
					table.insert(characters, character)
				end
			end
			if #characters == 0 then
				return {}
			end
			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Include
			overlap.FilterDescendantsInstances = characters
			overlap.MaxParts = MAX_QUERY_PARTS
			overlap.RespectCanCollide = false
			local parts = workspace:GetPartBoundsInBox(zonePart.CFrame, zonePart.Size, overlap)
			local seen: { [number]: boolean } = {}
			local userIds: { number } = {}
			for _, part in parts do
				local character = part:FindFirstAncestorOfClass("Model")
				local player = if character == nil then nil else players:GetPlayerFromCharacter(character)
				if
					player ~= nil
					and player.Parent == players
					and player.Character == character
					and not seen[player.UserId]
				then
					seen[player.UserId] = true
					table.insert(userIds, player.UserId)
				end
			end
			table.sort(userIds)
			return userIds
		end,
	}))
end

function QueueZoneService.new(
	queueOwnerValue: unknown,
	zonesValue: unknown,
	dependenciesValue: unknown
): Result.Result<Service, ServiceError>
	if
		type(queueOwnerValue) ~= "table"
		or type((queueOwnerValue :: any).enterPhysical) ~= "function"
		or type((queueOwnerValue :: any).leavePhysical) ~= "function"
	then
		return failure("INVALID_QUEUE_OWNER", "new")
	end
	if type(zonesValue) ~= "table" or getmetatable(zonesValue :: any) ~= nil then
		return failure("INVALID_ZONES", "new")
	end
	local rawZones = zonesValue :: { [any]: unknown }
	local count = 0
	local maximum = 0
	for key in rawZones do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > MAX_ZONES then
			return failure("INVALID_ZONES", "new")
		end
		count += 1
		maximum = math.max(maximum, key)
	end
	if count < 1 or maximum ~= count then
		return failure("INVALID_ZONES", "new")
	end
	local zones: { ZoneState } = table.create(count)
	local seenQueues: { [string]: boolean } = {}
	for index = 1, count do
		local zone = rawZones[index]
		if type(zone) ~= "table" or getmetatable(zone :: any) ~= nil then
			return failure("INVALID_ZONES", "new")
		end
		local rawZone = zone :: { [any]: unknown }
		for key in rawZone do
			if key ~= "queueId" and key ~= "sampleUserIds" then
				return failure("INVALID_ZONES", "new")
			end
		end
		local queueId = Ids.validateQueueId(rawZone.queueId)
		if not queueId.ok or seenQueues[queueId.value] or type(rawZone.sampleUserIds) ~= "function" then
			return failure("INVALID_ZONES", "new")
		end
		seenQueues[queueId.value] = true
		zones[index] = {
			queueId = queueId.value,
			sampleUserIds = rawZone.sampleUserIds :: () -> unknown,
			previous = {},
		}
	end
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local dependencies = dependenciesValue :: any
	if
		type(dependencies.clock) ~= "function"
		or (dependencies.connectStep ~= nil and type(dependencies.connectStep) ~= "function")
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local interval = dependencies.sampleIntervalSeconds or DEFAULT_SAMPLE_INTERVAL_SECONDS
	if
		type(interval) ~= "number"
		or not Validation.isFiniteNumber(interval)
		or interval < MIN_SAMPLE_INTERVAL_SECONDS
		or interval > MAX_SAMPLE_INTERVAL_SECONDS
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		queueOwner = queueOwnerValue :: QueueOwner,
		zones = zones,
		clock = dependencies.clock,
		connectStep = dependencies.connectStep,
		sampleIntervalSeconds = interval,
		lastSampleAt = nil,
		lastClock = nil,
		connection = nil,
		state = "Constructed",
		busy = false,
		sampleCount = 0,
		sampleFailureCount = 0,
		enterAttemptCount = 0,
		leaveAttemptCount = 0,
		ownerFailureCount = 0,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(QueueZoneService)
