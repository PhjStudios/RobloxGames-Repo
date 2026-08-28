--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local EnemySchema = require(ReplicatedStorage.Shared.config.EnemySchema)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local EnemyPath = require(script.Parent.EnemyPath)

export type RuntimeEnemyId = number
export type EnemyEpoch = number
export type EnemyLifecycle = "Active" | "EndpointResolved" | "Despawned"
export type DespawnReason = "Manual" | "Endpoint" | "Defeat"

export type SpeedModifiers = {
	slowMultiplier: number,
}

export type RuntimeEnemySnapshot = {
	runtimeEnemyId: RuntimeEnemyId,
	enemyId: Ids.EnemyId,
	laneId: string,
	pathProgress: number,
	currentHealth: number,
	maximumHealth: number,
	speedModifiers: SpeedModifiers,
	spawnServerTime: number,
	sampleServerTime: number,
	lifecycle: EnemyLifecycle,
	revision: number,
	worldCFrame: CFrame,
	effectiveSpeed: number,
	segmentIndex: number,
	segmentStartDistance: number,
	segmentEndDistance: number,
	segmentStartPosition: Vector3,
	segmentEndPosition: Vector3,
}

export type DespawnSnapshot = {
	runtimeEnemyId: RuntimeEnemyId,
	enemyId: Ids.EnemyId,
	laneId: string,
	revision: number,
	lifecycle: "Despawned",
	reason: DespawnReason,
	sampleServerTime: number,
}

export type EndpointResolution = {
	endpoint: RuntimeEnemySnapshot,
	despawn: DespawnSnapshot,
	callbackSucceeded: boolean,
}

export type StepResult = {
	deltaSeconds: number,
	sampleServerTime: number?,
	visitedCount: number,
	updatedCount: number,
	endpointCount: number,
	activeCountAfter: number,
	cleaned: boolean,
	faulted: boolean,
	updatedRuntimeEnemyIds: { RuntimeEnemyId },
	endpointResolutions: { EndpointResolution },
}

export type StoreIdentity = {
	matchId: Ids.MatchId,
	enemyEpoch: EnemyEpoch,
}

export type AuthenticatedLeakOutcome = {
	matchId: Ids.MatchId,
	enemyEpoch: EnemyEpoch,
	runtimeEnemyId: RuntimeEnemyId,
	enemyId: Ids.EnemyId,
	leakDamage: number,
	serverTime: number,
}

export type EndpointSink = (outcome: AuthenticatedLeakOutcome) -> ()

export type StoreMetrics = {
	activeCount: number,
	lifetimeCount: number,
	nextRuntimeEnemyId: number,
	terminalCount: number,
	retainedLeakOutcomeCount: number,
	retainedLaneCount: number,
	retainsCatalog: boolean,
	retainsClockCallback: boolean,
	retainsEndpointCallback: boolean,
	cleaned: boolean,
	faulted: boolean,
}

export type Operation =
	"new"
	| "spawn"
	| "get"
	| "list"
	| "queryTerminal"
	| "setSlowMultiplier"
	| "step"
	| "resolveEndpoint"
	| "despawn"
	| "despawnAllForDefeat"
	| "getIdentity"
	| "getMetrics"
	| "installStudioCatalog"
	| "listLaneIds"
	| "cleanup"

export type ErrorCode =
	"INVALID_MATCH_ID"
	| "INVALID_EPOCH"
	| "UNAUTHENTICATED_CATALOG"
	| "INVALID_RUNTIME_MAP"
	| "INVALID_RUNTIME_ID"
	| "INVALID_ENEMY_ID"
	| "INVALID_LANE_ID"
	| "DEFINITION_NOT_FOUND"
	| "LANE_NOT_FOUND"
	| "INVALID_SLOW_MULTIPLIER"
	| "INVALID_DELTA"
	| "CAPACITY_EXCEEDED"
	| "ID_EXHAUSTED"
	| "ID_COLLISION"
	| "NOT_FOUND"
	| "STALE_RUNTIME_ID"
	| "REVISION_EXHAUSTED"
	| "ILLEGAL_LIFECYCLE"
	| "CLOCK_FAILED"
	| "CALLBACK_FAILED"
	| "STUDIO_ONLY"
	| "REENTRANT"
	| "FAULTED"
	| "CLEANED"

export type StoreError = {
	code: ErrorCode,
	operation: Operation,
}

type RoutePointSnapshot = {
	kind: "EnemySpawn" | "PathNode" | "DefenderBase",
	nodeOrder: number?,
	cframe: CFrame,
	position: Vector3,
	distance: number,
}

type RuntimeLaneSnapshot = {
	id: string,
	totalDistance: number,
	points: { RoutePointSnapshot },
}

type RuntimeMapSnapshot = {
	mapId: Ids.MapId,
	lanes: { RuntimeLaneSnapshot },
}

type RuntimeEnemyRecord = {
	runtimeEnemyId: RuntimeEnemyId,
	enemyId: Ids.EnemyId,
	laneId: string,
	pathProgress: number,
	currentHealth: number,
	maximumHealth: number,
	slowMultiplier: number,
	spawnServerTime: number,
	sampleServerTime: number,
	lifecycle: "Active" | "EndpointResolved",
	revision: number,
	worldCFrame: CFrame,
	segmentIndex: number,
	definition: ConfigTypes.EnemyDefinition,
	lane: RuntimeLaneSnapshot,
}

type TerminalRecord = {
	despawn: DespawnSnapshot,
	endpoint: RuntimeEnemySnapshot?,
}

type Clock = () -> unknown

type TestOptions = {
	clock: Clock,
	endpointSink: EndpointSink?,
	maxActive: number?,
	maxLifetime: number?,
	nextRuntimeEnemyId: number?,
	issuedRuntimeEnemyIds: { number }?,
	studioCatalogInstallEnabled: boolean?,
}

type StoreData = {
	identity: StoreIdentity,
	catalog: ConfigTypes.EnemyCatalog?,
	laneById: { [string]: RuntimeLaneSnapshot },
	activeById: { [RuntimeEnemyId]: RuntimeEnemyRecord },
	issuedIds: { [RuntimeEnemyId]: boolean },
	terminalById: { [RuntimeEnemyId]: TerminalRecord },
	authenticatedLeakOutcomeById: { [RuntimeEnemyId]: AuthenticatedLeakOutcome },
	activeCount: number,
	lifetimeCount: number,
	terminalCount: number,
	nextRuntimeEnemyId: number,
	maxActive: number,
	maxLifetime: number,
	clock: Clock,
	lastServerTime: number,
	endpointSink: EndpointSink,
	mutating: boolean,
	reentryViolation: boolean,
	cleanupRequested: boolean,
	cleaned: boolean,
	faulted: boolean,
	studioCatalogInstallEnabled: boolean,
}

local MAX_ACTIVE = 128
local MAX_LIFETIME = 4_096
local MAX_EPOCH = 4_096
local MAX_LANES = 32
local MAX_ROUTE_POINTS = 258
local MAX_LANE_DISTANCE = 32_768
local MAX_SEGMENT_DISTANCE = 512
local MAX_COORDINATE = 100_000
local MIN_SEGMENT_DISTANCE = 0.01
local POSITION_TOLERANCE = 1e-6

local StoreMethods = {}
StoreMethods.__index = StoreMethods

export type Store = typeof(setmetatable({} :: {}, StoreMethods))

local STORE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: StoreData }
local AUTHENTICATED_LEAK_OUTCOMES = setmetatable({}, { __mode = "k" }) :: { [AuthenticatedLeakOutcome]: StoreData }

local EnemyRuntimeStore = {
	MAX_ACTIVE = MAX_ACTIVE,
	MAX_LIFETIME = MAX_LIFETIME,
	MAX_EPOCH = MAX_EPOCH,
}

local function makeError(code: ErrorCode, operation: Operation): StoreError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<StoreError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): StoreData
	if type(value) ~= "table" then
		error("[ATD_ENEMY_RUNTIME_STORE][code=INVALID_CONTEXT]", 0)
	end
	local data = STORE_DATA[value :: any]
	if data == nil then
		error("[ATD_ENEMY_RUNTIME_STORE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and Validation.isFiniteNumber(value)
end

local function isFiniteVector3(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local vector = value :: Vector3
	return isFiniteNumber(vector.X)
		and isFiniteNumber(vector.Y)
		and isFiniteNumber(vector.Z)
		and math.abs(vector.X) <= MAX_COORDINATE
		and math.abs(vector.Y) <= MAX_COORDINATE
		and math.abs(vector.Z) <= MAX_COORDINATE
end

local function isFiniteCFrame(value: unknown): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	for _, component in { (value :: CFrame):GetComponents() } do
		if not isFiniteNumber(component) then
			return false
		end
	end
	return true
end

local function hasExactFields(value: { [any]: unknown }, fields: { [string]: boolean }): boolean
	for key in next, value do
		if type(key) ~= "string" or fields[key] ~= true then
			return false
		end
	end
	for key in fields do
		if value[key] == nil and key ~= "nodeOrder" then
			return false
		end
	end
	return true
end

local function isDenseFrozenArray(value: unknown, minimum: number, maximum: number): boolean
	if type(value) ~= "table" or not table.isfrozen(value :: any) or getmetatable(value :: any) ~= nil then
		return false
	end
	local length = rawlen(value :: { unknown })
	if length < minimum or length > maximum then
		return false
	end
	local count = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return false
		end
		count += 1
	end
	return count == length
end

local LANE_FIELDS = table.freeze({
	id = true,
	totalDistance = true,
	points = true,
})

local POINT_FIELDS = table.freeze({
	kind = true,
	nodeOrder = true,
	cframe = true,
	position = true,
	distance = true,
})

local function validateLane(value: unknown): RuntimeLaneSnapshot?
	if
		type(value) ~= "table"
		or not table.isfrozen(value :: any)
		or getmetatable(value :: any) ~= nil
		or not hasExactFields(value :: { [any]: unknown }, LANE_FIELDS)
	then
		return nil
	end
	local lane = value :: any
	if
		type(lane.id) ~= "string"
		or not Validation.isSymbolicKey(lane.id)
		or not isFiniteNumber(lane.totalDistance)
		or lane.totalDistance < MIN_SEGMENT_DISTANCE
		or lane.totalDistance > MAX_LANE_DISTANCE
		or not isDenseFrozenArray(lane.points, 2, MAX_ROUTE_POINTS)
	then
		return nil
	end

	local previousDistance = -math.huge
	local previousPosition: Vector3? = nil
	local distanceTolerance = math.max(1, lane.totalDistance) * 1e-9
	local points = lane.points :: { unknown }
	for index = 1, #points do
		local pointValue = points[index]
		if
			type(pointValue) ~= "table"
			or not table.isfrozen(pointValue :: any)
			or getmetatable(pointValue :: any) ~= nil
			or not hasExactFields(pointValue :: { [any]: unknown }, POINT_FIELDS)
		then
			return nil
		end
		local point = pointValue :: any
		local expectedKind = if index == 1 then "EnemySpawn" elseif index == #points then "DefenderBase" else "PathNode"
		local expectedNodeOrder = if expectedKind == "PathNode" then index - 1 else nil
		if
			point.kind ~= expectedKind
			or point.nodeOrder ~= expectedNodeOrder
			or not isFiniteVector3(point.position)
			or not isFiniteCFrame(point.cframe)
			or ((point.cframe :: CFrame).Position - (point.position :: Vector3)).Magnitude > POSITION_TOLERANCE
			or not isFiniteNumber(point.distance)
			or point.distance < 0
			or point.distance > lane.totalDistance
		then
			return nil
		end
		if index == 1 then
			if point.distance ~= 0 then
				return nil
			end
		else
			local segmentDistance = ((point.position :: Vector3) - (previousPosition :: Vector3)).Magnitude
			local cumulativeDelta = point.distance - previousDistance
			if
				not isFiniteNumber(segmentDistance)
				or segmentDistance < MIN_SEGMENT_DISTANCE
				or segmentDistance > MAX_SEGMENT_DISTANCE
				or cumulativeDelta < MIN_SEGMENT_DISTANCE
				or cumulativeDelta > MAX_SEGMENT_DISTANCE
				or math.abs(cumulativeDelta - segmentDistance) > distanceTolerance
			then
				return nil
			end
		end
		previousDistance = point.distance
		previousPosition = point.position
	end
	if math.abs(previousDistance - lane.totalDistance) > distanceTolerance then
		return nil
	end
	return value :: RuntimeLaneSnapshot
end

local function validateRuntimeMap(value: unknown): { [string]: RuntimeLaneSnapshot }?
	if type(value) ~= "table" or not table.isfrozen(value :: any) or getmetatable(value :: any) ~= nil then
		return nil
	end
	local map = value :: any
	local mapIdResult = Ids.validateMapId(map.mapId)
	if not mapIdResult.ok or not isDenseFrozenArray(map.lanes, 1, MAX_LANES) then
		return nil
	end

	local byId: { [string]: RuntimeLaneSnapshot } = {}
	for _, laneValue in map.lanes :: { unknown } do
		local lane = validateLane(laneValue)
		if lane == nil or byId[lane.id] ~= nil then
			return nil
		end
		byId[lane.id] = lane
	end
	return byId
end

local function effectiveSpeed(record: RuntimeEnemyRecord): number
	return record.definition.moveSpeedStudsPerSecond * record.slowMultiplier
end

local function snapshotRecord(record: RuntimeEnemyRecord): RuntimeEnemySnapshot
	local segmentStart = record.lane.points[record.segmentIndex]
	local segmentEnd = record.lane.points[record.segmentIndex + 1]
	return table.freeze({
		runtimeEnemyId = record.runtimeEnemyId,
		enemyId = record.enemyId,
		laneId = record.laneId,
		pathProgress = record.pathProgress,
		currentHealth = record.currentHealth,
		maximumHealth = record.maximumHealth,
		speedModifiers = table.freeze({
			slowMultiplier = record.slowMultiplier,
		}),
		spawnServerTime = record.spawnServerTime,
		sampleServerTime = record.sampleServerTime,
		lifecycle = record.lifecycle,
		revision = record.revision,
		worldCFrame = record.worldCFrame,
		effectiveSpeed = effectiveSpeed(record),
		segmentIndex = record.segmentIndex,
		segmentStartDistance = segmentStart.distance,
		segmentEndDistance = segmentEnd.distance,
		segmentStartPosition = segmentStart.position,
		segmentEndPosition = segmentEnd.position,
	})
end

local function terminalSnapshot(
	record: RuntimeEnemyRecord,
	reason: DespawnReason,
	sampleServerTime: number
): DespawnSnapshot
	return table.freeze({
		runtimeEnemyId = record.runtimeEnemyId,
		enemyId = record.enemyId,
		laneId = record.laneId,
		revision = record.revision,
		lifecycle = "Despawned",
		reason = reason,
		sampleServerTime = sampleServerTime,
	})
end

local function defaultClock(): unknown
	return Workspace:GetServerTimeNow()
end

local function noEndpointOutcome(_outcome: AuthenticatedLeakOutcome) end

local function closedClock(): unknown
	return 0
end

local function callClockNonYielding(clock: Clock): (boolean, unknown)
	local thread = coroutine.create(function()
		return clock()
	end)
	local resumed, value = coroutine.resume(thread)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function readClock(data: StoreData, operation: Operation): (number?, StoreError?)
	local called, value = callClockNonYielding(data.clock)
	if not called or not isFiniteNumber(value) or (value :: number) < 0 or (value :: number) < data.lastServerTime then
		return nil, makeError("CLOCK_FAILED", operation)
	end
	data.lastServerTime = value :: number
	return value :: number, nil
end

local function validateLive(data: StoreData, operation: Operation, mutation: boolean): StoreError?
	if data.cleaned then
		return makeError("CLEANED", operation)
	end
	if mutation and data.mutating then
		data.reentryViolation = true
		return makeError("REENTRANT", operation)
	end
	if mutation and data.faulted then
		return makeError("FAULTED", operation)
	end
	return nil
end

local function validateRuntimeEnemyId(value: unknown, operation: Operation): (RuntimeEnemyId?, StoreError?)
	if type(value) ~= "number" or not Validation.isSafeInteger(value) or value < 1 or value > MAX_LIFETIME then
		return nil, makeError("INVALID_RUNTIME_ID", operation)
	end
	return value, nil
end

local function lookupActive(
	data: StoreData,
	runtimeEnemyIdValue: unknown,
	operation: Operation
): (RuntimeEnemyRecord?, StoreError?)
	local runtimeEnemyId, idError = validateRuntimeEnemyId(runtimeEnemyIdValue, operation)
	if runtimeEnemyId == nil then
		return nil, idError
	end
	local record = data.activeById[runtimeEnemyId]
	if record ~= nil then
		return record, nil
	end
	if data.issuedIds[runtimeEnemyId] then
		return nil, makeError("STALE_RUNTIME_ID", operation)
	end
	return nil, makeError("NOT_FOUND", operation)
end

local function clearData(data: StoreData)
	for _, outcome in data.authenticatedLeakOutcomeById do
		AUTHENTICATED_LEAK_OUTCOMES[outcome] = nil
	end
	table.clear(data.authenticatedLeakOutcomeById)
	table.clear(data.activeById)
	table.clear(data.issuedIds)
	table.clear(data.terminalById)
	table.clear(data.laneById)
	data.catalog = nil
	data.clock = closedClock
	data.endpointSink = noEndpointOutcome
	data.activeCount = 0
	data.lifetimeCount = 0
	data.terminalCount = 0
	data.nextRuntimeEnemyId = 1
	data.lastServerTime = 0
	data.cleanupRequested = false
	data.cleaned = true
	data.studioCatalogInstallEnabled = false
end

local function finishMutation(data: StoreData)
	data.mutating = false
	if data.cleanupRequested then
		clearData(data)
	end
end

local function beginTimedMutation(data: StoreData, operation: Operation): (number?, StoreError?)
	data.mutating = true
	data.reentryViolation = false
	local serverTime, clockError = readClock(data, operation)
	if serverTime == nil then
		data.faulted = true
		finishMutation(data)
		return nil, clockError
	end
	if data.reentryViolation then
		data.faulted = true
		finishMutation(data)
		return nil, makeError("CLOCK_FAILED", operation)
	end
	if data.cleanupRequested then
		finishMutation(data)
		return nil, makeError("CLEANED", operation)
	end
	return serverTime, nil
end

local function invokeEndpointSink(data: StoreData, outcome: AuthenticatedLeakOutcome): boolean
	local thread = coroutine.create(function()
		data.endpointSink(outcome)
	end)
	local resumed = coroutine.resume(thread)
	if not resumed then
		return false
	end
	if coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)
		return false
	end
	return not data.reentryViolation
end

local function terminalizeEndpoint(data: StoreData, record: RuntimeEnemyRecord, serverTime: number): EndpointResolution
	local endpointCFrame, endpointSegmentIndex = EnemyPath.sampleTrusted(record.lane, record.lane.totalDistance)
	record.pathProgress = record.lane.totalDistance
	record.worldCFrame = endpointCFrame
	record.segmentIndex = endpointSegmentIndex
	record.sampleServerTime = serverTime
	record.lifecycle = "EndpointResolved"
	record.revision += 1
	local endpoint = snapshotRecord(record)
	local outcome = table.freeze({
		matchId = data.identity.matchId,
		enemyEpoch = data.identity.enemyEpoch,
		runtimeEnemyId = record.runtimeEnemyId,
		enemyId = record.definition.id,
		leakDamage = record.definition.leakDamage,
		serverTime = serverTime,
	})
	data.authenticatedLeakOutcomeById[record.runtimeEnemyId] = outcome
	AUTHENTICATED_LEAK_OUTCOMES[outcome] = data
	local callbackSucceeded = invokeEndpointSink(data, outcome)

	record.revision += 1
	local despawn = terminalSnapshot(record, "Endpoint", serverTime)
	data.activeById[record.runtimeEnemyId] = nil
	data.activeCount -= 1
	data.terminalById[record.runtimeEnemyId] = {
		endpoint = endpoint,
		despawn = despawn,
	}
	data.terminalCount += 1
	if not callbackSucceeded then
		data.faulted = true
	end
	return table.freeze({
		endpoint = endpoint,
		despawn = despawn,
		callbackSucceeded = callbackSucceeded,
	})
end

local function makeStore(
	matchId: Ids.MatchId,
	enemyEpoch: number,
	catalog: ConfigTypes.EnemyCatalog,
	laneById: { [string]: RuntimeLaneSnapshot },
	clock: Clock,
	endpointSink: EndpointSink,
	maxActive: number,
	maxLifetime: number,
	nextRuntimeEnemyId: number,
	issuedIds: { [RuntimeEnemyId]: boolean },
	lifetimeCount: number,
	initialServerTime: number,
	studioCatalogInstallEnabled: boolean
): Store
	local store = setmetatable({}, StoreMethods) :: Store
	table.freeze(store)
	STORE_DATA[store] = {
		identity = table.freeze({
			matchId = matchId,
			enemyEpoch = enemyEpoch,
		}),
		catalog = catalog,
		laneById = laneById,
		activeById = {},
		issuedIds = issuedIds,
		terminalById = {},
		authenticatedLeakOutcomeById = {},
		activeCount = 0,
		lifetimeCount = lifetimeCount,
		terminalCount = 0,
		nextRuntimeEnemyId = nextRuntimeEnemyId,
		maxActive = maxActive,
		maxLifetime = maxLifetime,
		clock = clock,
		lastServerTime = initialServerTime,
		endpointSink = endpointSink,
		mutating = false,
		reentryViolation = false,
		cleanupRequested = false,
		cleaned = false,
		faulted = false,
		studioCatalogInstallEnabled = studioCatalogInstallEnabled,
	}
	return store
end

local function construct(
	matchIdValue: unknown,
	enemyEpochValue: unknown,
	catalogValue: unknown,
	runtimeMapValue: unknown,
	clock: Clock,
	endpointSink: EndpointSink,
	maxActive: number,
	maxLifetime: number,
	nextRuntimeEnemyId: number,
	issuedIds: { [RuntimeEnemyId]: boolean },
	lifetimeCount: number,
	studioCatalogInstallEnabled: boolean
): Result.Result<Store, StoreError>
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if not matchIdResult.ok then
		return failure("INVALID_MATCH_ID", "new")
	end
	if
		type(enemyEpochValue) ~= "number"
		or not Validation.isSafeInteger(enemyEpochValue)
		or enemyEpochValue < 1
		or enemyEpochValue > MAX_EPOCH
	then
		return failure("INVALID_EPOCH", "new")
	end
	if not EnemySchema.isValidatedCatalog(catalogValue) then
		return failure("UNAUTHENTICATED_CATALOG", "new")
	end
	local laneById = validateRuntimeMap(runtimeMapValue)
	if laneById == nil then
		return failure("INVALID_RUNTIME_MAP", "new")
	end
	local called, initialTime = callClockNonYielding(clock)
	if not called or not isFiniteNumber(initialTime) or (initialTime :: number) < 0 then
		return failure("CLOCK_FAILED", "new")
	end

	return Result.ok(
		makeStore(
			matchIdResult.value,
			enemyEpochValue,
			catalogValue :: ConfigTypes.EnemyCatalog,
			laneById,
			clock,
			endpointSink,
			maxActive,
			maxLifetime,
			nextRuntimeEnemyId,
			issuedIds,
			lifetimeCount,
			initialTime :: number,
			studioCatalogInstallEnabled
		)
	)
end

function StoreMethods.installStudioCatalog(self: Store, catalogValue: unknown): Result.Result<boolean, StoreError>
	local data = requireData(self)
	local liveError = validateLive(data, "installStudioCatalog", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	if not data.studioCatalogInstallEnabled then
		return failure("STUDIO_ONLY", "installStudioCatalog")
	end
	if not EnemySchema.isValidatedCatalog(catalogValue) then
		return failure("UNAUTHENTICATED_CATALOG", "installStudioCatalog")
	end
	local currentCatalog = data.catalog
	if
		currentCatalog == nil
		or #currentCatalog.ordered ~= 0
		or data.activeCount ~= 0
		or data.lifetimeCount ~= 0
		or data.terminalCount ~= 0
		or data.nextRuntimeEnemyId ~= 1
		or next(data.issuedIds) ~= nil
	then
		return failure("ILLEGAL_LIFECYCLE", "installStudioCatalog")
	end
	data.mutating = true
	data.catalog = catalogValue :: ConfigTypes.EnemyCatalog
	data.studioCatalogInstallEnabled = false
	finishMutation(data)
	return Result.ok(true)
end

function StoreMethods.listLaneIds(self: Store): Result.Result<{ string }, StoreError>
	local data = requireData(self)
	local liveError = validateLive(data, "listLaneIds", false)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local laneIds: { string } = {}
	for laneId in data.laneById do
		table.insert(laneIds, laneId)
	end
	table.sort(laneIds)
	return Result.ok(table.freeze(laneIds))
end

function StoreMethods.spawn(
	self: Store,
	enemyIdValue: unknown,
	laneIdValue: unknown
): Result.Result<RuntimeEnemySnapshot, StoreError>
	local data = requireData(self)
	local liveError = validateLive(data, "spawn", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local enemyIdResult = Ids.validateEnemyId(enemyIdValue)
	if not enemyIdResult.ok then
		return failure("INVALID_ENEMY_ID", "spawn")
	end
	if type(laneIdValue) ~= "string" or not Validation.isSymbolicKey(laneIdValue) then
		return failure("INVALID_LANE_ID", "spawn")
	end
	local catalog = data.catalog
	if catalog == nil then
		return failure("CLEANED", "spawn")
	end
	local definition = catalog.byId[enemyIdResult.value]
	if definition == nil then
		return failure("DEFINITION_NOT_FOUND", "spawn")
	end
	local lane = data.laneById[laneIdValue]
	if lane == nil then
		return failure("LANE_NOT_FOUND", "spawn")
	end
	if data.activeCount >= data.maxActive then
		return failure("CAPACITY_EXCEEDED", "spawn")
	end
	if data.lifetimeCount >= data.maxLifetime or data.nextRuntimeEnemyId > data.maxLifetime then
		return failure("ID_EXHAUSTED", "spawn")
	end
	if data.issuedIds[data.nextRuntimeEnemyId] then
		return failure("ID_COLLISION", "spawn")
	end
	local serverTime, clockError = beginTimedMutation(data, "spawn")
	if serverTime == nil then
		return Result.err(clockError :: StoreError)
	end

	local runtimeEnemyId = data.nextRuntimeEnemyId
	local worldCFrame, segmentIndex = EnemyPath.sampleTrusted(lane, 0)
	local record: RuntimeEnemyRecord = {
		runtimeEnemyId = runtimeEnemyId,
		enemyId = definition.id,
		laneId = lane.id,
		pathProgress = 0,
		currentHealth = definition.maxHealth,
		maximumHealth = definition.maxHealth,
		slowMultiplier = 1,
		spawnServerTime = serverTime,
		sampleServerTime = serverTime,
		lifecycle = "Active",
		revision = 1,
		worldCFrame = worldCFrame,
		segmentIndex = segmentIndex,
		definition = definition,
		lane = lane,
	}
	data.activeById[runtimeEnemyId] = record
	data.issuedIds[runtimeEnemyId] = true
	data.activeCount += 1
	data.lifetimeCount += 1
	data.nextRuntimeEnemyId += 1
	local result = snapshotRecord(record)
	finishMutation(data)
	return Result.ok(result)
end

function StoreMethods.get(self: Store, runtimeEnemyIdValue: unknown): Result.Result<RuntimeEnemySnapshot, StoreError>
	local data = requireData(self)
	local liveError = validateLive(data, "get", false)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local record, lookupError = lookupActive(data, runtimeEnemyIdValue, "get")
	if record == nil then
		return Result.err(lookupError :: StoreError)
	end
	return Result.ok(snapshotRecord(record))
end

function StoreMethods.list(self: Store): Result.Result<{ RuntimeEnemySnapshot }, StoreError>
	local data = requireData(self)
	local liveError = validateLive(data, "list", false)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local ids: { number } = {}
	for runtimeEnemyId in data.activeById do
		table.insert(ids, runtimeEnemyId)
	end
	table.sort(ids)
	local snapshots: { RuntimeEnemySnapshot } = table.create(#ids)
	for _, runtimeEnemyId in ids do
		table.insert(snapshots, snapshotRecord(data.activeById[runtimeEnemyId]))
	end
	return Result.ok(table.freeze(snapshots))
end

function StoreMethods.queryTerminal(
	self: Store,
	runtimeEnemyIdValue: unknown
): Result.Result<DespawnSnapshot, StoreError>
	local data = requireData(self)
	local liveError = validateLive(data, "queryTerminal", false)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local runtimeEnemyId, idError = validateRuntimeEnemyId(runtimeEnemyIdValue, "queryTerminal")
	if runtimeEnemyId == nil then
		return Result.err(idError :: StoreError)
	end
	local terminal = data.terminalById[runtimeEnemyId]
	if terminal ~= nil then
		return Result.ok(terminal.despawn)
	end
	if data.issuedIds[runtimeEnemyId] then
		return failure("ILLEGAL_LIFECYCLE", "queryTerminal")
	end
	return failure("NOT_FOUND", "queryTerminal")
end

function StoreMethods.setSlowMultiplier(
	self: Store,
	runtimeEnemyIdValue: unknown,
	multiplierValue: unknown
): Result.Result<RuntimeEnemySnapshot, StoreError>
	local data = requireData(self)
	local liveError = validateLive(data, "setSlowMultiplier", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	if not isFiniteNumber(multiplierValue) or (multiplierValue :: number) < 0 or (multiplierValue :: number) > 1 then
		return failure("INVALID_SLOW_MULTIPLIER", "setSlowMultiplier")
	end
	local record, lookupError = lookupActive(data, runtimeEnemyIdValue, "setSlowMultiplier")
	if record == nil then
		return Result.err(lookupError :: StoreError)
	end
	if record.slowMultiplier == multiplierValue then
		return Result.ok(snapshotRecord(record))
	end
	if record.revision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", "setSlowMultiplier")
	end
	local serverTime, clockError = beginTimedMutation(data, "setSlowMultiplier")
	if serverTime == nil then
		return Result.err(clockError :: StoreError)
	end

	record.slowMultiplier = multiplierValue :: number
	record.sampleServerTime = serverTime
	record.revision += 1
	local result = snapshotRecord(record)
	finishMutation(data)
	return Result.ok(result)
end

function StoreMethods.resolveEndpoint(
	self: Store,
	runtimeEnemyIdValue: unknown
): Result.Result<EndpointResolution, StoreError>
	local data = requireData(self)
	local liveError = validateLive(data, "resolveEndpoint", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local record, lookupError = lookupActive(data, runtimeEnemyIdValue, "resolveEndpoint")
	if record == nil then
		return Result.err(lookupError :: StoreError)
	end
	if record.lifecycle ~= "Active" then
		return failure("ILLEGAL_LIFECYCLE", "resolveEndpoint")
	end
	if record.revision > Validation.MAX_SAFE_INTEGER - 2 then
		return failure("REVISION_EXHAUSTED", "resolveEndpoint")
	end
	local serverTime, clockError = beginTimedMutation(data, "resolveEndpoint")
	if serverTime == nil then
		return Result.err(clockError :: StoreError)
	end

	local resolution = terminalizeEndpoint(data, record, serverTime)
	finishMutation(data)
	return Result.ok(resolution)
end

function StoreMethods.despawn(self: Store, runtimeEnemyIdValue: unknown): Result.Result<DespawnSnapshot, StoreError>
	local data = requireData(self)
	local liveError = validateLive(data, "despawn", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local record, lookupError = lookupActive(data, runtimeEnemyIdValue, "despawn")
	if record == nil then
		return Result.err(lookupError :: StoreError)
	end
	if record.lifecycle ~= "Active" then
		return failure("ILLEGAL_LIFECYCLE", "despawn")
	end
	if record.revision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", "despawn")
	end
	local serverTime, clockError = beginTimedMutation(data, "despawn")
	if serverTime == nil then
		return Result.err(clockError :: StoreError)
	end

	record.sampleServerTime = serverTime
	record.revision += 1
	local despawn = terminalSnapshot(record, "Manual", serverTime)
	data.activeById[record.runtimeEnemyId] = nil
	data.activeCount -= 1
	data.terminalById[record.runtimeEnemyId] = {
		despawn = despawn,
	}
	data.terminalCount += 1
	finishMutation(data)
	return Result.ok(despawn)
end

function StoreMethods.despawnAllForDefeat(
	self: Store,
	expectedActiveIdsValue: unknown
): Result.Result<{ DespawnSnapshot }, StoreError>
	local operation: Operation = "despawnAllForDefeat"
	local data = requireData(self)
	local liveError = validateLive(data, operation, true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	if type(expectedActiveIdsValue) ~= "table" or getmetatable(expectedActiveIdsValue :: any) ~= nil then
		return failure("INVALID_RUNTIME_ID", operation)
	end

	local expectedActiveIds = expectedActiveIdsValue :: { [any]: unknown }
	local expectedCount = rawlen(expectedActiveIds :: { unknown })
	if expectedCount > MAX_ACTIVE then
		return failure("INVALID_RUNTIME_ID", operation)
	end
	local fieldCount = 0
	for key in next, expectedActiveIds do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > expectedCount then
			return failure("INVALID_RUNTIME_ID", operation)
		end
		fieldCount += 1
	end
	if fieldCount ~= expectedCount then
		return failure("INVALID_RUNTIME_ID", operation)
	end

	local records: { RuntimeEnemyRecord } = table.create(expectedCount)
	local previousRuntimeEnemyId = 0
	for index = 1, expectedCount do
		local runtimeEnemyId, idError = validateRuntimeEnemyId(expectedActiveIds[index], operation)
		if runtimeEnemyId == nil then
			return Result.err(idError :: StoreError)
		end
		if runtimeEnemyId <= previousRuntimeEnemyId then
			return failure("INVALID_RUNTIME_ID", operation)
		end
		local record = data.activeById[runtimeEnemyId]
		if record == nil then
			return failure("STALE_RUNTIME_ID", operation)
		end
		if record.lifecycle ~= "Active" then
			return failure("ILLEGAL_LIFECYCLE", operation)
		end
		if record.revision >= Validation.MAX_SAFE_INTEGER then
			return failure("REVISION_EXHAUSTED", operation)
		end
		table.insert(records, record)
		previousRuntimeEnemyId = runtimeEnemyId
	end
	if expectedCount ~= data.activeCount then
		return failure("STALE_RUNTIME_ID", operation)
	end

	local serverTime, clockError = beginTimedMutation(data, operation)
	if serverTime == nil then
		return Result.err(clockError :: StoreError)
	end

	local despawns: { DespawnSnapshot } = table.create(expectedCount)
	for _, record in records do
		record.sampleServerTime = serverTime
		record.revision += 1
		local despawn = terminalSnapshot(record, "Defeat", serverTime)
		data.activeById[record.runtimeEnemyId] = nil
		data.activeCount -= 1
		data.terminalById[record.runtimeEnemyId] = {
			despawn = despawn,
		}
		data.terminalCount += 1
		table.insert(despawns, despawn)
	end
	table.freeze(despawns)
	finishMutation(data)
	return Result.ok(despawns)
end

function StoreMethods.step(self: Store, deltaSecondsValue: unknown): Result.Result<StepResult, StoreError>
	local data = requireData(self)
	local liveError = validateLive(data, "step", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	if
		type(deltaSecondsValue) ~= "number"
		or not Validation.isFiniteNumber(deltaSecondsValue)
		or deltaSecondsValue < 0
	then
		return failure("INVALID_DELTA", "step")
	end
	local deltaSeconds = deltaSecondsValue :: number
	if deltaSeconds == 0 then
		return Result.ok(table.freeze({
			deltaSeconds = 0,
			sampleServerTime = nil,
			visitedCount = 0,
			updatedCount = 0,
			endpointCount = 0,
			activeCountAfter = data.activeCount,
			cleaned = false,
			faulted = data.faulted,
			updatedRuntimeEnemyIds = table.freeze({}),
			endpointResolutions = table.freeze({}),
		}))
	end

	local startIds: { number } = {}
	for runtimeEnemyId in data.activeById do
		table.insert(startIds, runtimeEnemyId)
	end
	table.sort(startIds)
	for _, runtimeEnemyId in startIds do
		local record = data.activeById[runtimeEnemyId]
		if record ~= nil and effectiveSpeed(record) > 0 then
			if record.revision > Validation.MAX_SAFE_INTEGER - 2 then
				data.faulted = true
				return failure("REVISION_EXHAUSTED", "step")
			end
		end
	end

	local serverTime, clockError = beginTimedMutation(data, "step")
	if serverTime == nil then
		return Result.err(clockError :: StoreError)
	end
	local endpointResolutions: { EndpointResolution } = {}
	local updatedRuntimeEnemyIds: { RuntimeEnemyId } = {}
	local visitedCount = 0
	local updatedCount = 0
	for _, runtimeEnemyId in startIds do
		if data.cleanupRequested or data.faulted then
			break
		end
		local record = data.activeById[runtimeEnemyId]
		if record == nil or record.lifecycle ~= "Active" then
			continue
		end
		visitedCount += 1
		local speed = effectiveSpeed(record)
		if speed <= 0 then
			continue
		end
		local remaining = record.lane.totalDistance - record.pathProgress
		if remaining <= 0 or deltaSeconds >= remaining / speed then
			local resolution = terminalizeEndpoint(data, record, serverTime)
			table.insert(endpointResolutions, resolution)
			updatedCount += 1
			continue
		end

		local distance = speed * deltaSeconds
		if not Validation.isFiniteNumber(distance) or distance < 0 then
			data.faulted = true
			break
		end
		if distance >= remaining then
			local resolution = terminalizeEndpoint(data, record, serverTime)
			table.insert(endpointResolutions, resolution)
			updatedCount += 1
			continue
		end
		if distance == 0 then
			continue
		end
		local nextProgress = record.pathProgress + distance
		local sampledProgress = EnemyPath.canonicalizeProgressTrusted(record.lane, nextProgress)
		if sampledProgress >= record.lane.totalDistance then
			local resolution = terminalizeEndpoint(data, record, serverTime)
			table.insert(endpointResolutions, resolution)
			updatedCount += 1
			continue
		end
		record.pathProgress = nextProgress
		record.worldCFrame, record.segmentIndex = EnemyPath.sampleTrusted(record.lane, record.pathProgress)
		record.sampleServerTime = serverTime
		record.revision += 1
		table.insert(updatedRuntimeEnemyIds, record.runtimeEnemyId)
		updatedCount += 1
	end

	table.freeze(updatedRuntimeEnemyIds)
	table.freeze(endpointResolutions)
	finishMutation(data)
	return Result.ok(table.freeze({
		deltaSeconds = deltaSeconds,
		sampleServerTime = serverTime,
		visitedCount = visitedCount,
		updatedCount = updatedCount,
		endpointCount = #endpointResolutions,
		activeCountAfter = data.activeCount,
		cleaned = data.cleaned,
		faulted = data.faulted,
		updatedRuntimeEnemyIds = updatedRuntimeEnemyIds,
		endpointResolutions = endpointResolutions,
	}))
end

function StoreMethods.getIdentity(self: Store): Result.Result<StoreIdentity, StoreError>
	local data = requireData(self)
	local liveError = validateLive(data, "getIdentity", false)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	return Result.ok(data.identity)
end

function StoreMethods.getMetrics(self: Store): StoreMetrics
	local data = requireData(self)
	local retainedLaneCount = 0
	for _ in data.laneById do
		retainedLaneCount += 1
	end
	local retainedLeakOutcomeCount = 0
	for _ in data.authenticatedLeakOutcomeById do
		retainedLeakOutcomeCount += 1
	end
	return table.freeze({
		activeCount = data.activeCount,
		lifetimeCount = data.lifetimeCount,
		nextRuntimeEnemyId = data.nextRuntimeEnemyId,
		terminalCount = data.terminalCount,
		retainedLeakOutcomeCount = retainedLeakOutcomeCount,
		retainedLaneCount = retainedLaneCount,
		retainsCatalog = data.catalog ~= nil,
		retainsClockCallback = data.clock ~= closedClock,
		retainsEndpointCallback = data.endpointSink ~= noEndpointOutcome,
		cleaned = data.cleaned,
		faulted = data.faulted,
	})
end

function StoreMethods.cleanup(self: Store): Result.Result<boolean, StoreError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	if data.mutating then
		data.cleanupRequested = true
		return Result.ok(false)
	end
	clearData(data)
	return Result.ok(true)
end

function StoreMethods.isAuthenticatedLeakOutcome(self: Store, value: unknown): boolean
	local data = requireData(self)
	if type(value) ~= "table" then
		return false
	end
	local outcome = value :: AuthenticatedLeakOutcome
	if AUTHENTICATED_LEAK_OUTCOMES[outcome] ~= data or data.cleaned then
		return false
	end
	return data.authenticatedLeakOutcomeById[outcome.runtimeEnemyId] == outcome
end

function EnemyRuntimeStore.isAuthenticatedLeakOutcome(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local outcome = value :: AuthenticatedLeakOutcome
	local data = AUTHENTICATED_LEAK_OUTCOMES[outcome]
	if data == nil or data.cleaned then
		return false
	end
	return data.authenticatedLeakOutcomeById[outcome.runtimeEnemyId] == outcome
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "EnemyRuntimeStore" then
		return false
	end
	local productionServerEnemies = script.Parent
	if
		productionServerEnemies == nil
		or not productionServerEnemies:IsA("Folder")
		or productionServerEnemies.Name ~= "ProductionServerEnemies"
	then
		return false
	end
	local automatedTests = productionServerEnemies.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	if automatedTests.Parent ~= ServerStorage then
		return false
	end
	return ServerScriptService:FindFirstChild("Server") == nil
end

function EnemyRuntimeStore.new(
	matchIdValue: unknown,
	catalogValue: unknown,
	runtimeMapValue: unknown,
	endpointSinkValue: unknown?
): Result.Result<Store, StoreError>
	local endpointSink = if endpointSinkValue == nil then noEndpointOutcome else endpointSinkValue
	if type(endpointSink) ~= "function" then
		return failure("CALLBACK_FAILED", "new")
	end
	return construct(
		matchIdValue,
		1,
		catalogValue,
		runtimeMapValue,
		defaultClock,
		endpointSink :: EndpointSink,
		MAX_ACTIVE,
		MAX_LIFETIME,
		1,
		{},
		0,
		RunService:IsStudio()
	)
end

function EnemyRuntimeStore.newForTests(
	matchIdValue: unknown,
	enemyEpochValue: unknown,
	catalogValue: unknown,
	runtimeMapValue: unknown,
	optionsValue: unknown
): Result.Result<Store, StoreError>
	if not testModuleIdentityIsExact() then
		error("[ATD_ENEMY_RUNTIME_STORE][code=TEST_CONSTRUCTOR_FORBIDDEN]", 0)
	end
	if type(optionsValue) ~= "table" or getmetatable(optionsValue :: any) ~= nil then
		return failure("CLOCK_FAILED", "new")
	end
	local options = optionsValue :: TestOptions
	if
		type(options.clock) ~= "function"
		or (options.endpointSink ~= nil and type(options.endpointSink) ~= "function")
		or (options.studioCatalogInstallEnabled ~= nil and type(options.studioCatalogInstallEnabled) ~= "boolean")
	then
		return failure("CLOCK_FAILED", "new")
	end
	local maxActive = options.maxActive or MAX_ACTIVE
	local maxLifetime = options.maxLifetime or MAX_LIFETIME
	local nextRuntimeEnemyId = options.nextRuntimeEnemyId or 1
	if
		not Validation.isSafeInteger(maxActive)
		or maxActive < 1
		or maxActive > MAX_ACTIVE
		or not Validation.isSafeInteger(maxLifetime)
		or maxLifetime < 1
		or maxLifetime > MAX_LIFETIME
		or not Validation.isSafeInteger(nextRuntimeEnemyId)
		or nextRuntimeEnemyId < 1
		or nextRuntimeEnemyId > maxLifetime + 1
	then
		return failure("ID_EXHAUSTED", "new")
	end

	local issuedIds: { [RuntimeEnemyId]: boolean } = {}
	local lifetimeCount = 0
	if options.issuedRuntimeEnemyIds ~= nil then
		if type(options.issuedRuntimeEnemyIds) ~= "table" or getmetatable(options.issuedRuntimeEnemyIds) ~= nil then
			return failure("ID_COLLISION", "new")
		end
		for _, runtimeEnemyIdValue in options.issuedRuntimeEnemyIds do
			if
				type(runtimeEnemyIdValue) ~= "number"
				or not Validation.isSafeInteger(runtimeEnemyIdValue)
				or runtimeEnemyIdValue < 1
				or runtimeEnemyIdValue > maxLifetime
				or issuedIds[runtimeEnemyIdValue] == true
			then
				return failure("ID_COLLISION", "new")
			end
			issuedIds[runtimeEnemyIdValue] = true
			lifetimeCount += 1
		end
	end
	if lifetimeCount > maxLifetime then
		return failure("ID_EXHAUSTED", "new")
	end

	return construct(
		matchIdValue,
		enemyEpochValue,
		catalogValue,
		runtimeMapValue,
		options.clock,
		options.endpointSink or noEndpointOutcome,
		maxActive,
		maxLifetime,
		nextRuntimeEnemyId,
		issuedIds,
		lifetimeCount,
		options.studioCatalogInstallEnabled == true
	)
end

table.freeze(StoreMethods)
return table.freeze(EnemyRuntimeStore)
