--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local PlacementGeometry = require(ReplicatedStorage.Shared.match.PlacementGeometry)
local PlacementProtocol = require(ReplicatedStorage.Shared.match.PlacementProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local PlacementAffordability = require(script.Parent.PlacementAffordability)

export type LifecycleState =
	"Constructed"
	| "Initializing"
	| "Initialized"
	| "Starting"
	| "Started"
	| "ShuttingDown"
	| "Shutdown"
	| "Failed"

export type Operation = "getQuery" | "submitPlacement" | "studioEvidence" | "cleanup"
export type ErrorCode =
	"INVALID_ARGUMENT"
	| "NOT_ELIGIBLE"
	| "STALE"
	| "INVALID_SLOT"
	| "INVALID_POSITION"
	| "INVALID_SURFACE"
	| "OUTSIDE_ZONE"
	| "EXCLUDED"
	| "OCCUPIED"
	| "CAPPED"
	| "UNAFFORDABLE"
	| "UNAVAILABLE"
	| "INTERNAL_ERROR"

export type ServiceError = {
	code: ErrorCode,
	operation: Operation,
}

export type MatchLifecycleAdapter = {
	getSnapshot: (self: MatchLifecycleAdapter) -> unknown,
	getRuntimeMapSnapshot: (self: MatchLifecycleAdapter) -> unknown,
	isRuntimeMapSnapshot: (self: MatchLifecycleAdapter, snapshot: unknown) -> unknown,
}

export type TowerRuntimeAdapter = {
	getPlacementView: (self: TowerRuntimeAdapter, userId: unknown) -> unknown,
	resolveOccupiedSlot: (self: TowerRuntimeAdapter, userId: unknown, slot: unknown) -> unknown,
	trustedDiscardCapability: (self: TowerRuntimeAdapter, capability: unknown) -> unknown,
	trustedCreate: (self: TowerRuntimeAdapter, capability: unknown, placementCFrame: unknown) -> unknown,
	trustedRemove: (self: TowerRuntimeAdapter, runtimeTowerId: unknown) -> unknown,
}

export type AffordabilityAdapter = {
	canAfford: (self: AffordabilityAdapter, userId: unknown, cost: unknown) -> unknown,
	prepare: (self: AffordabilityAdapter, userId: unknown, cost: unknown) -> unknown,
	commit: (self: AffordabilityAdapter, token: unknown) -> unknown,
	abort: (self: AffordabilityAdapter, token: unknown) -> unknown,
	getMetrics: (self: AffordabilityAdapter) -> unknown,
	cleanup: (self: AffordabilityAdapter) -> unknown,
}

export type PublishRevision = (matchId: unknown, queryRevision: unknown) -> unknown
export type RuntimeTriggerHandler = (...unknown) -> unknown
export type CreateRuntimeTrigger = (handler: RuntimeTriggerHandler) -> unknown
export type IsStudio = () -> unknown
export type MatchSnapshotSender = (recipient: unknown, snapshot: MatchProtocol.MatchSnapshot) -> boolean
export type PlacementRevisionSender = (recipient: unknown, payload: unknown) -> boolean
export type QueryRevisionProvider = () -> unknown

export type TestDependencies = {
	matchLifecycle: MatchLifecycleAdapter,
	towerRuntime: TowerRuntimeAdapter,
	affordability: AffordabilityAdapter,
	publishRevision: PublishRevision,
	isStudio: IsStudio,
	createRuntimeTrigger: CreateRuntimeTrigger,
}

export type Metrics = {
	lifecycleState: LifecycleState,
	queryRevision: number,
	queryCount: number,
	rejectedQueryCount: number,
	placementCount: number,
	rejectedPlacementCount: number,
	publicationCount: number,
	publicationFailureCount: number,
	reservationCount: number,
	operationActive: boolean,
	connectionCount: number,
	studioTriggerCount: number,
	studioOperationCount: number,
	studioRefreshCount: number,
	affordability: unknown?,
}

type Reservation = {
	id: number,
	userId: number,
	matchId: string,
	towerId: string,
	positionXZ: Vector2,
	radius: number,
}

type NormalizedMap = {
	mapId: string,
	bounds: PlacementProtocol.Bounds,
	placementZones: { PlacementProtocol.PlacementZone },
	exclusions: { PlacementProtocol.Exclusion },
}

type ViewAnalysis = {
	view: any,
	slots: { any },
	towers: { any },
	footprints: { Vector3 },
	countByTowerId: { [string]: number },
	totalOwned: number,
	globalCount: number,
}

type ServiceData = {
	state: LifecycleState,
	matchLifecycle: MatchLifecycleAdapter?,
	towerRuntime: TowerRuntimeAdapter?,
	affordability: AffordabilityAdapter?,
	publishRevision: PublishRevision?,
	isStudio: IsStudio?,
	createRuntimeTrigger: CreateRuntimeTrigger?,
	queryRevision: number,
	queryCount: number,
	rejectedQueryCount: number,
	placementCount: number,
	rejectedPlacementCount: number,
	publicationCount: number,
	publicationFailureCount: number,
	reservations: { [number]: Reservation },
	reservationCount: number,
	nextReservationId: number,
	operationActive: boolean,
	reentryViolation: boolean,
	shutdownRequested: boolean,
	cleanupCompleted: boolean,
	boundMatchId: string?,
	boundRuntimeMap: unknown,
	studioTrigger: unknown?,
	studioOperationCount: number,
	studioRefreshCount: number,
	serviceDefinition: ServiceLifecycle.ServiceDefinition?,
}

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))
export type TestConstructor = (dependencies: TestDependencies) -> Service

local SERVICE_NAME = "TowerPlacement"
local STATIC_ERROR_PREFIX = "[ATD_TOWER_PLACEMENT_SERVICE]"
local STUDIO_TRIGGER_NAME = "_ATDPhase13PlacementEvidence"
local MATCH_METHODS = table.freeze({ "getSnapshot", "getRuntimeMapSnapshot", "isRuntimeMapSnapshot" })
local TOWER_METHODS = table.freeze({
	"getPlacementView",
	"resolveOccupiedSlot",
	"trustedDiscardCapability",
	"trustedCreate",
	"trustedRemove",
})
local AFFORDABILITY_METHODS = table.freeze({ "canAfford", "prepare", "commit", "abort", "getMetrics", "cleanup" })
local SERVICE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local TowerPlacementService = {
	STUDIO_TRIGGER_NAME = STUDIO_TRIGGER_NAME,
	newForTests = nil :: TestConstructor?,
}

local completeDeferredShutdown: ((ServiceData) -> ())? = nil

local function staticError(code: string): never
	error(`{STATIC_ERROR_PREFIX}[code={code}]`, 0)
end

local function makeError(code: ErrorCode, operation: Operation): ServiceError
	return table.freeze({ code = code, operation = operation })
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<ServiceError>
	return Result.err(makeError(code, operation))
end

function TowerPlacementService.createRevisionAwareSnapshotSender(
	snapshotSender: MatchSnapshotSender,
	revisionSender: PlacementRevisionSender,
	queryRevisionProvider: QueryRevisionProvider
): MatchSnapshotSender
	if
		type(snapshotSender) ~= "function"
		or type(revisionSender) ~= "function"
		or type(queryRevisionProvider) ~= "function"
	then
		staticError("INVALID_REVISION_BRIDGE_DEPENDENCIES")
	end
	return function(recipient: unknown, snapshotValue: MatchProtocol.MatchSnapshot): boolean
		local snapshotValidation = MatchProtocol.validateMatchSnapshot(snapshotValue)
		if not snapshotValidation.ok then
			return false
		end
		local snapshot = snapshotValidation.value
		local snapshotCalled, snapshotSent = pcall(snapshotSender, recipient, snapshot)
		if not snapshotCalled or snapshotSent ~= true then
			return false
		end
		if snapshot.state ~= "PreWave" and snapshot.state ~= "WaveActive" then
			return true
		end

		local revisionCalled, queryRevision = pcall(queryRevisionProvider)
		if not revisionCalled then
			return false
		end
		local revisionValidation = PlacementProtocol.RevisionEventSchema:validate({
			matchId = snapshot.matchId,
			queryRevision = queryRevision,
		})
		if not revisionValidation.ok then
			return false
		end
		local publicationCalled, published = pcall(revisionSender, recipient, revisionValidation.value)
		return publicationCalled and published == true
	end
end

local function requireData(service: Service): ServiceData
	local data = SERVICE_DATA[service]
	if data == nil then
		staticError("INVALID_SERVICE")
	end
	return data :: ServiceData
end

local function hasMethods(value: unknown, names: { string }): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, name in names do
		if type((value :: any)[name]) ~= "function" then
			return false
		end
	end
	return true
end

local function callNonYielding(callback: (...any) -> unknown, ...: any): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function callResult(callback: (...any) -> unknown, ...: any): (boolean, unknown)
	local called, value = callNonYielding(callback, ...)
	if not called or type(value) ~= "table" or not table.isfrozen(value :: any) then
		return false, nil
	end
	return true, value
end

local function isRuntimeTriggerAdapter(value: unknown): boolean
	return (typeof(value) == "Instance" and (value :: Instance):IsA("BindableFunction"))
		or (type(value) == "table" and type((value :: any).Destroy) == "function")
end

local function isSuccess(value: unknown): boolean
	return type(value) == "table"
		and table.isfrozen(value :: any)
		and (value :: any).ok == true
		and (value :: any).value ~= nil
end

local function resultSucceeded(value: unknown, expected: unknown?): boolean
	return isSuccess(value) and (expected == nil or (value :: any).value == expected)
end

local function resultErrorCode(value: unknown): string?
	if type(value) ~= "table" or not table.isfrozen(value :: any) or (value :: any).ok ~= false then
		return nil
	end
	local errorValue = (value :: any).error
	return if type(errorValue) == "table"
			and table.isfrozen(errorValue :: any)
			and type((errorValue :: any).code) == "string"
		then (errorValue :: any).code
		else nil
end

local function faultData(data: ServiceData)
	if data.state ~= "Shutdown" and data.state ~= "ShuttingDown" then
		data.state = "Failed"
	end
	data.shutdownRequested = true
end

local function beginOperation(data: ServiceData, operation: Operation): ServiceError?
	if data.operationActive then
		data.reentryViolation = true
		faultData(data)
		return makeError("UNAVAILABLE", operation)
	end
	if data.state ~= "Started" or data.shutdownRequested then
		return makeError("UNAVAILABLE", operation)
	end
	data.operationActive = true
	data.reentryViolation = false
	return nil
end

local function operationIntact(data: ServiceData): boolean
	return data.operationActive and not data.reentryViolation and not data.shutdownRequested and data.state == "Started"
end

local function finishOperation(data: ServiceData): boolean
	local intact = operationIntact(data)
	data.operationActive = false
	data.reentryViolation = false
	if data.shutdownRequested then
		local finalizer = completeDeferredShutdown
		if finalizer ~= nil then
			finalizer(data)
		end
	end
	return intact
end

local function collectMetrics(data: ServiceData): Metrics
	local affordabilityMetrics: unknown? = nil
	local affordability = data.affordability
	if affordability ~= nil then
		local called, value = callNonYielding(affordability.getMetrics, affordability)
		if called and type(value) == "table" and table.isfrozen(value :: any) then
			affordabilityMetrics = value
		end
	end
	return table.freeze({
		lifecycleState = data.state,
		queryRevision = data.queryRevision,
		queryCount = data.queryCount,
		rejectedQueryCount = data.rejectedQueryCount,
		placementCount = data.placementCount,
		rejectedPlacementCount = data.rejectedPlacementCount,
		publicationCount = data.publicationCount,
		publicationFailureCount = data.publicationFailureCount,
		reservationCount = data.reservationCount,
		operationActive = data.operationActive,
		connectionCount = 0,
		studioTriggerCount = if data.studioTrigger == nil then 0 else 1,
		studioOperationCount = data.studioOperationCount,
		studioRefreshCount = data.studioRefreshCount,
		affordability = affordabilityMetrics,
	})
end

local function isPositiveSafeInteger(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and (value :: number) > 0
end

local function isNonzeroSafeInteger(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and (value :: number) ~= 0
end

local function isNonnegativeSafeInteger(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and (value :: number) >= 0
end

local function boundedText(value: unknown, maximumBytes: number): boolean
	return type(value) == "string" and #value >= 1 and #value <= maximumBytes
end

local function towerId(value: unknown): boolean
	return boundedText(value, 100) and string.match(value :: string, "^tower:[a-z0-9][a-z0-9%-]*$") ~= nil
end

local function validOccupiedSlot(value: unknown, index: number): boolean
	if type(value) ~= "table" or not table.isfrozen(value :: any) then
		return false
	end
	local slot = value :: any
	return slot.kind == "Occupied"
		and slot.slot == index
		and towerId(slot.towerId)
		and boundedText(slot.displayName, 100)
		and (slot.iconAssetKey == nil or boundedText(slot.iconAssetKey, 100))
		and isNonnegativeSafeInteger(slot.placementCost)
		and type(slot.footprintRadiusStuds) == "number"
		and PlacementGeometry.encodeFootprint(Vector2.zero, slot.footprintRadiusStuds) ~= nil
		and isPositiveSafeInteger(slot.placementCap)
		and type(slot.rangeStuds) == "number"
		and Validation.isFiniteNumber(slot.rangeStuds)
		and slot.rangeStuds >= 0
		and slot.rangeStuds <= PlacementGeometry.MAX_COORDINATE
end

local function analyzeTowerView(
	viewValue: unknown,
	snapshot: MatchProtocol.MatchSnapshot,
	userId: number
): ViewAnalysis?
	if type(viewValue) ~= "table" or not table.isfrozen(viewValue :: any) then
		return nil
	end
	local view = viewValue :: any
	if
		view.matchId ~= snapshot.matchId
		or view.userId ~= userId
		or not isPositiveSafeInteger(view.towerEpoch)
		or not isPositiveSafeInteger(view.loadoutRevision)
		or type(view.slots) ~= "table"
		or #view.slots ~= PlacementProtocol.MAX_LOADOUT_SLOTS
		or type(view.towers) ~= "table"
		or #view.towers > PlacementProtocol.MAX_QUERY_FOOTPRINTS
	then
		return nil
	end

	local slots = table.create(PlacementProtocol.MAX_LOADOUT_SLOTS)
	for index = 1, PlacementProtocol.MAX_LOADOUT_SLOTS do
		local source = view.slots[index]
		if type(source) ~= "table" or not table.isfrozen(source) or source.slot ~= index then
			return nil
		end
		if source.kind ~= "Empty" and not validOccupiedSlot(source, index) then
			return nil
		end
		table.insert(slots, source)
	end

	local footprints = table.create(#view.towers)
	local towers = table.create(#view.towers)
	local countByTowerId: { [string]: number } = {}
	local totalOwned = 0
	local seenRuntimeIds: { [number]: boolean } = {}
	for _, source in view.towers do
		if
			type(source) ~= "table"
			or not table.isfrozen(source)
			or not isPositiveSafeInteger(source.runtimeTowerId)
			or source.runtimeTowerId > PlacementProtocol.MAX_RUNTIME_TOWER_ID
			or seenRuntimeIds[source.runtimeTowerId] == true
			or not isNonzeroSafeInteger(source.ownerUserId)
			or not towerId(source.towerId)
			or not PlacementGeometry.isUprightYawCFrame(source.placementCFrame)
		then
			return nil
		end
		local position = source.placementCFrame.Position
		local footprint =
			PlacementGeometry.encodeFootprint(Vector2.new(position.X, position.Z), source.footprintRadiusStuds)
		if footprint == nil then
			return nil
		end
		seenRuntimeIds[source.runtimeTowerId] = true
		table.insert(towers, source)
		table.insert(footprints, footprint)
		if source.ownerUserId == userId then
			totalOwned += 1
			countByTowerId[source.towerId] = (countByTowerId[source.towerId] or 0) + 1
		end
	end

	return {
		view = view,
		slots = slots,
		towers = towers,
		footprints = footprints,
		countByTowerId = countByTowerId,
		totalOwned = totalOwned,
		globalCount = #towers,
	}
end

local function normalizeRuntimeMap(value: unknown): NormalizedMap?
	if type(value) ~= "table" or not table.isfrozen(value :: any) then
		return nil
	end
	local source = value :: any
	if
		not boundedText(source.mapId, 100)
		or string.sub(source.mapId, 1, 4) ~= "map:"
		or type(source.bounds) ~= "table"
		or type(source.placementZones) ~= "table"
		or #source.placementZones < 1
		or #source.placementZones > PlacementProtocol.MAX_QUERY_PLACEMENT_ZONES
		or type(source.noPlacementZones) ~= "table"
		or #source.noPlacementZones > PlacementProtocol.MAX_QUERY_EXCLUSIONS
	then
		return nil
	end

	local bounds = table.freeze({ cframe = source.bounds.cframe, size = source.bounds.size })
	if
		not PlacementGeometry.isUprightYawCFrame(bounds.cframe)
		or PlacementGeometry.groundHeight(bounds) == nil
		or not PlacementGeometry.circleInsideRegion(Vector2.new(bounds.cframe.X, bounds.cframe.Z), 0.000001, bounds)
	then
		return nil
	end

	local placementZones: { PlacementProtocol.PlacementZone } = table.create(#source.placementZones)
	for _, zone in source.placementZones do
		if type(zone) ~= "table" then
			return nil
		end
		local surface = if zone.surfaceCategory == nil then "Land" else zone.surfaceCategory
		local normalized = table.freeze({
			cframe = zone.cframe,
			size = zone.size,
			surfaceCategory = surface,
		})
		if
			not PlacementGeometry.isUprightYawCFrame(normalized.cframe)
			or not PlacementGeometry.isSurfaceCategory(normalized.surfaceCategory)
			or PlacementGeometry.groundHeight(normalized) == nil
		then
			return nil
		end
		table.insert(placementZones, normalized :: PlacementProtocol.PlacementZone)
	end

	local exclusions: { PlacementProtocol.Exclusion } = table.create(#source.noPlacementZones)
	for _, exclusion in source.noPlacementZones do
		if type(exclusion) ~= "table" then
			return nil
		end
		local normalized = table.freeze({ cframe = exclusion.cframe, size = exclusion.size })
		if
			not PlacementGeometry.isUprightYawCFrame(normalized.cframe)
			or PlacementGeometry.groundHeight(normalized) == nil
		then
			return nil
		end
		table.insert(exclusions, normalized)
	end

	return {
		mapId = source.mapId,
		bounds = bounds,
		placementZones = placementZones,
		exclusions = exclusions,
	}
end

local function activeParticipant(snapshot: MatchProtocol.MatchSnapshot, userId: number): boolean
	for _, participant in snapshot.participants do
		if participant.userId == userId then
			return participant.state == "Active"
		end
	end
	return false
end

local function readMatchAndMap(
	data: ServiceData,
	userId: number,
	operation: Operation
): (MatchProtocol.MatchSnapshot?, any?, ServiceError?)
	local lifecycle = data.matchLifecycle
	if lifecycle == nil then
		return nil, nil, makeError("UNAVAILABLE", operation)
	end
	local snapshotCalled, snapshotResult = callResult(lifecycle.getSnapshot, lifecycle)
	if not operationIntact(data) then
		return nil, nil, makeError("UNAVAILABLE", operation)
	end
	if not snapshotCalled then
		faultData(data)
		return nil, nil, makeError("INTERNAL_ERROR", operation)
	end
	if not isSuccess(snapshotResult) then
		return nil, nil, makeError("UNAVAILABLE", operation)
	end
	local snapshotValidation = MatchProtocol.validateMatchSnapshot((snapshotResult :: any).value)
	if not snapshotValidation.ok then
		faultData(data)
		return nil, nil, makeError("INTERNAL_ERROR", operation)
	end
	local snapshot = snapshotValidation.value
	if snapshot.state ~= "PreWave" and snapshot.state ~= "WaveActive" then
		return nil, nil, makeError("NOT_ELIGIBLE", operation)
	end
	if not activeParticipant(snapshot, userId) then
		return nil, nil, makeError("NOT_ELIGIBLE", operation)
	end

	local mapCalled, mapResult = callResult(lifecycle.getRuntimeMapSnapshot, lifecycle)
	if not operationIntact(data) then
		return nil, nil, makeError("UNAVAILABLE", operation)
	end
	if not mapCalled then
		faultData(data)
		return nil, nil, makeError("INTERNAL_ERROR", operation)
	end
	if not isSuccess(mapResult) then
		return nil, nil, makeError("UNAVAILABLE", operation)
	end
	local runtimeMap = (mapResult :: any).value
	local identityCalled, identityValue = callNonYielding(lifecycle.isRuntimeMapSnapshot, lifecycle, runtimeMap)
	if not operationIntact(data) then
		return nil, nil, makeError("UNAVAILABLE", operation)
	end
	if not identityCalled or identityValue ~= true then
		faultData(data)
		return nil, nil, makeError("INTERNAL_ERROR", operation)
	end
	return snapshot, runtimeMap, nil
end

local function bindRuntimeIdentity(
	data: ServiceData,
	snapshot: MatchProtocol.MatchSnapshot,
	runtimeMap: unknown
): boolean
	if data.boundMatchId == nil and data.boundRuntimeMap == nil then
		data.boundMatchId = snapshot.matchId
		data.boundRuntimeMap = runtimeMap
		return true
	end
	if data.boundMatchId ~= snapshot.matchId or data.boundRuntimeMap ~= runtimeMap then
		faultData(data)
		return false
	end
	return true
end

local function readTowerView(data: ServiceData, userId: number, operation: Operation): (any?, ServiceError?)
	local towerRuntime = data.towerRuntime
	if towerRuntime == nil then
		return nil, makeError("UNAVAILABLE", operation)
	end
	local called, resultValue = callResult(towerRuntime.getPlacementView, towerRuntime, userId)
	if not operationIntact(data) then
		return nil, makeError("UNAVAILABLE", operation)
	end
	if not called then
		faultData(data)
		return nil, makeError("INTERNAL_ERROR", operation)
	end
	if not isSuccess(resultValue) then
		local code = resultErrorCode(resultValue)
		return nil, makeError(if code == "NOT_FOUND" then "NOT_ELIGIBLE" else "UNAVAILABLE", operation)
	end
	return (resultValue :: any).value, nil
end

local function affordabilityState(
	data: ServiceData,
	userId: number,
	cost: number,
	operation: Operation
): (PlacementProtocol.AffordabilityState?, ServiceError?)
	local affordability = data.affordability
	if affordability == nil then
		return nil, makeError("UNAVAILABLE", operation)
	end
	local called, resultValue = callResult(affordability.canAfford, affordability, userId, cost)
	if not operationIntact(data) then
		return nil, makeError("UNAVAILABLE", operation)
	end
	if not called or not isSuccess(resultValue) or type((resultValue :: any).value) ~= "boolean" then
		faultData(data)
		return nil, makeError("INTERNAL_ERROR", operation)
	end
	return if (resultValue :: any).value then "Affordable" else "Unaffordable", nil
end

local function buildQuery(
	data: ServiceData,
	userId: number,
	snapshot: MatchProtocol.MatchSnapshot,
	runtimeMap: NormalizedMap,
	analysis: ViewAnalysis
): Result.Result<PlacementProtocol.QuerySnapshot, ServiceError>
	local slots: { PlacementProtocol.QuerySlot } = table.create(PlacementProtocol.MAX_LOADOUT_SLOTS)
	for index, sourceSlot in analysis.slots do
		if sourceSlot.kind == "Empty" then
			table.insert(slots, table.freeze({ kind = "Empty", slot = index }))
		else
			local placementCount = analysis.countByTowerId[sourceSlot.towerId] or 0
			local capState: PlacementProtocol.CapState = if analysis.totalOwned
						>= PlacementProtocol.MAX_TOTAL_ACTIVE_PER_OWNER
					or analysis.globalCount >= PlacementProtocol.MAX_QUERY_FOOTPRINTS
				then "TotalCapped"
				elseif placementCount >= sourceSlot.placementCap then "PerTypeCapped"
				else "Available"
			local affordable, affordabilityError =
				affordabilityState(data, userId, sourceSlot.placementCost, "getQuery")
			if affordable == nil then
				return Result.err(affordabilityError :: ServiceError)
			end
			table.insert(
				slots,
				table.freeze({
					kind = "Occupied",
					slot = index,
					towerId = sourceSlot.towerId,
					displayName = sourceSlot.displayName,
					iconAssetKey = sourceSlot.iconAssetKey,
					rangeStuds = sourceSlot.rangeStuds,
					footprintRadiusStuds = sourceSlot.footprintRadiusStuds,
					placementCost = sourceSlot.placementCost,
					placementCount = placementCount,
					placementCap = sourceSlot.placementCap,
					totalCount = analysis.totalOwned,
					totalCap = PlacementProtocol.MAX_TOTAL_ACTIVE_PER_OWNER,
					globalCount = analysis.globalCount,
					globalCap = PlacementProtocol.MAX_QUERY_FOOTPRINTS,
					affordability = affordable,
					capState = capState,
				})
			)
		end
	end

	local candidate = {
		contractVersion = PlacementProtocol.CONTRACT_VERSION,
		matchId = snapshot.matchId,
		mapId = runtimeMap.mapId,
		queryRevision = data.queryRevision,
		loadoutRevision = analysis.view.loadoutRevision,
		bounds = runtimeMap.bounds,
		placementZones = table.freeze(runtimeMap.placementZones),
		exclusions = table.freeze(runtimeMap.exclusions),
		footprints = table.freeze(analysis.footprints),
		slots = table.freeze(slots),
	}
	local queryValidation = PlacementProtocol.validateQuerySnapshot(candidate)
	if not queryValidation.ok then
		faultData(data)
		return failure("INTERNAL_ERROR", "getQuery")
	end
	return Result.ok(queryValidation.value)
end

local function reservationCounts(
	data: ServiceData,
	userId: number,
	selectedTowerId: string,
	excludedReservationId: number?
): (number, number, number)
	local ownerCount = 0
	local typeCount = 0
	local globalCount = 0
	for id, reservation in data.reservations do
		if id ~= excludedReservationId then
			globalCount += 1
			if reservation.userId == userId then
				ownerCount += 1
				if reservation.towerId == selectedTowerId then
					typeCount += 1
				end
			end
		end
	end
	return ownerCount, typeCount, globalCount
end

local function footprintsWithReservations(
	data: ServiceData,
	committed: { Vector3 },
	excludedReservationId: number?
): { Vector3 }?
	local footprints = table.create(#committed + data.reservationCount)
	for _, footprint in committed do
		table.insert(footprints, footprint)
	end
	for id, reservation in data.reservations do
		if id ~= excludedReservationId then
			local encoded = PlacementGeometry.encodeFootprint(reservation.positionXZ, reservation.radius)
			if encoded == nil then
				return nil
			end
			table.insert(footprints, encoded)
		end
	end
	return footprints
end

local function capAvailable(
	data: ServiceData,
	analysis: ViewAnalysis,
	userId: number,
	selectedSlot: any,
	excludedReservationId: number?
): boolean
	local reservedOwner, reservedType, reservedGlobal =
		reservationCounts(data, userId, selectedSlot.towerId, excludedReservationId)
	return analysis.totalOwned + reservedOwner < PlacementProtocol.MAX_TOTAL_ACTIVE_PER_OWNER
		and (analysis.countByTowerId[selectedSlot.towerId] or 0) + reservedType < selectedSlot.placementCap
		and analysis.globalCount + reservedGlobal < PlacementProtocol.MAX_QUERY_FOOTPRINTS
end

local function revisionAccepted(data: ServiceData, observedRevision: number): boolean
	return observedRevision <= data.queryRevision
		and data.queryRevision - observedRevision <= PlacementProtocol.MAX_QUERY_REVISION_LAG
end

local function rejection(
	data: ServiceData,
	reason: PlacementProtocol.PlacementRejectionReason
): Result.Success<PlacementProtocol.PlacementReceipt>
	return Result.ok(table.freeze({
		state = "Rejected",
		reason = reason,
		queryRevision = data.queryRevision,
	}))
end

local function geometryReason(reason: string): PlacementProtocol.PlacementRejectionReason
	if reason == "InvalidSurface" then
		return "InvalidSurface"
	elseif reason == "OutsideZone" then
		return "OutsideZone"
	elseif reason == "Excluded" then
		return "Excluded"
	elseif reason == "Occupied" then
		return "Occupied"
	end
	return "InvalidPosition"
end

local function reserveFootprint(
	data: ServiceData,
	userId: number,
	matchId: string,
	towerIdValue: string,
	positionXZ: Vector2,
	radius: number
): number?
	if data.reservationCount ~= 0 or data.nextReservationId >= Validation.MAX_SAFE_INTEGER then
		return nil
	end
	data.nextReservationId += 1
	local id = data.nextReservationId
	data.reservations[id] = {
		id = id,
		userId = userId,
		matchId = matchId,
		towerId = towerIdValue,
		positionXZ = positionXZ,
		radius = radius,
	}
	data.reservationCount = 1
	return id
end

local function releaseReservation(data: ServiceData, reservationId: number): boolean
	if data.reservations[reservationId] == nil or data.reservationCount ~= 1 then
		faultData(data)
		return false
	end
	data.reservations[reservationId] = nil
	data.reservationCount = 0
	return true
end

local function rollback(
	data: ServiceData,
	reservationId: number?,
	chargeToken: unknown,
	capability: unknown,
	createdRuntimeTowerId: number?,
	commitAttempted: boolean
): boolean
	local clean = true
	local towerRuntime = data.towerRuntime
	local affordability = data.affordability
	if createdRuntimeTowerId ~= nil and towerRuntime ~= nil then
		local called, resultValue = callResult(towerRuntime.trustedRemove, towerRuntime, createdRuntimeTowerId)
		if not called or not isSuccess(resultValue) then
			clean = false
		end
	end
	if capability ~= nil and towerRuntime ~= nil then
		local called, resultValue = callResult(towerRuntime.trustedDiscardCapability, towerRuntime, capability)
		if
			not called
			or (not resultSucceeded(resultValue, true) and resultErrorCode(resultValue) ~= "INVALID_CAPABILITY")
		then
			clean = false
		end
	end
	if chargeToken ~= nil and affordability ~= nil then
		local called, resultValue = callResult(affordability.abort, affordability, chargeToken)
		if
			not called
			or (
				not resultSucceeded(resultValue, true)
				and not (commitAttempted and resultErrorCode(resultValue) == "INVALID_TOKEN")
			)
		then
			clean = false
		end
	end
	if reservationId ~= nil and not releaseReservation(data, reservationId) then
		clean = false
	end
	if not clean then
		faultData(data)
	end
	return clean
end

local function mapContextError(
	data: ServiceData,
	contextError: ServiceError?
): PlacementProtocol.PlacementRejectionReason
	if contextError ~= nil and contextError.code == "NOT_ELIGIBLE" then
		return "NotEligible"
	end
	if contextError ~= nil and contextError.code == "INTERNAL_ERROR" then
		faultData(data)
	end
	return "Unavailable"
end

local function validateCreatedTower(
	value: unknown,
	snapshot: MatchProtocol.MatchSnapshot,
	userId: number,
	selectedSlot: any,
	placementCFrame: CFrame
): number?
	if type(value) ~= "table" or not table.isfrozen(value :: any) then
		return nil
	end
	local tower = value :: any
	if
		tower.matchId ~= snapshot.matchId
		or tower.ownerUserId ~= userId
		or tower.towerId ~= selectedSlot.towerId
		or tower.placementCFrame ~= placementCFrame
		or not isPositiveSafeInteger(tower.runtimeTowerId)
		or tower.runtimeTowerId > PlacementProtocol.MAX_RUNTIME_TOWER_ID
	then
		return nil
	end
	return tower.runtimeTowerId
end

local function reconcilesCreatedTower(
	analysis: ViewAnalysis,
	runtimeTowerId: number,
	userId: number,
	towerIdValue: string,
	placementCFrame: CFrame
): boolean
	local count = 0
	for _, tower in analysis.towers do
		if tower.runtimeTowerId == runtimeTowerId then
			count += 1
			if
				tower.ownerUserId ~= userId
				or tower.towerId ~= towerIdValue
				or tower.placementCFrame ~= placementCFrame
			then
				return false
			end
		end
	end
	return count == 1
end

local function submitCore(
	data: ServiceData,
	userId: number,
	intent: PlacementProtocol.PlacementIntent
): (Result.Result<PlacementProtocol.PlacementReceipt, ServiceError>, boolean)
	local snapshot, runtimeMapValue, contextError = readMatchAndMap(data, userId, "submitPlacement")
	if snapshot == nil or runtimeMapValue == nil then
		return rejection(data, mapContextError(data, contextError)), false
	end
	if intent.matchId ~= snapshot.matchId then
		return rejection(data, "NotEligible"), false
	end
	if not bindRuntimeIdentity(data, snapshot, runtimeMapValue) then
		return rejection(data, "Unavailable"), false
	end
	local runtimeMap = normalizeRuntimeMap(runtimeMapValue)
	if runtimeMap == nil then
		faultData(data)
		return rejection(data, "Unavailable"), false
	end

	local viewValue, towerError = readTowerView(data, userId, "submitPlacement")
	if viewValue == nil then
		return rejection(data, mapContextError(data, towerError)), false
	end
	local analysis = analyzeTowerView(viewValue, snapshot, userId)
	if analysis == nil then
		faultData(data)
		return rejection(data, "Unavailable"), false
	end
	if analysis.view.loadoutRevision ~= intent.loadoutRevision then
		return rejection(data, "Stale"), false
	end
	local selectedSlot = analysis.slots[intent.slot]
	if selectedSlot == nil or selectedSlot.kind ~= "Occupied" then
		return rejection(data, "InvalidSlot"), false
	end
	if not revisionAccepted(data, intent.observedQueryRevision) then
		return rejection(data, "Stale"), false
	end

	local normalizedYaw = PlacementGeometry.normalizeYawDegrees(intent.yawDegrees)
	if normalizedYaw == nil then
		return rejection(data, "InvalidPosition"), false
	end
	local footprints = footprintsWithReservations(data, analysis.footprints, nil)
	if footprints == nil then
		faultData(data)
		return rejection(data, "Unavailable"), false
	end
	local geometry = PlacementGeometry.evaluate(
		intent.positionXZ,
		selectedSlot.footprintRadiusStuds,
		runtimeMap.bounds,
		runtimeMap.placementZones,
		runtimeMap.exclusions,
		footprints
	)
	if not geometry.valid then
		return rejection(data, geometryReason(geometry.reason)), false
	end
	if not capAvailable(data, analysis, userId, selectedSlot, nil) then
		return rejection(data, "Capped"), false
	end
	local affordability, affordabilityError =
		affordabilityState(data, userId, selectedSlot.placementCost, "submitPlacement")
	if affordability == nil then
		return rejection(data, mapContextError(data, affordabilityError)), false
	elseif affordability ~= "Affordable" then
		return rejection(data, "Unaffordable"), false
	end

	local reservationId = reserveFootprint(
		data,
		userId,
		snapshot.matchId,
		selectedSlot.towerId,
		intent.positionXZ,
		selectedSlot.footprintRadiusStuds
	)
	if reservationId == nil then
		faultData(data)
		return rejection(data, "Unavailable"), false
	end
	local chargeToken: unknown = nil
	local capability: unknown = nil
	local createdRuntimeTowerId: number? = nil
	local commitAttempted = false

	local affordabilityAdapter = data.affordability :: AffordabilityAdapter
	local prepared, prepareResult =
		callResult(affordabilityAdapter.prepare, affordabilityAdapter, userId, selectedSlot.placementCost)
	local preparedChargeToken = if prepared and isSuccess(prepareResult) then (prepareResult :: any).value else nil
	if not operationIntact(data) or not prepared or not isSuccess(prepareResult) then
		local reason: PlacementProtocol.PlacementRejectionReason = if resultErrorCode(prepareResult)
				== "UNAFFORDABLE"
			then "Unaffordable"
			else "Unavailable"
		if not prepared then
			faultData(data)
		end
		rollback(data, reservationId, preparedChargeToken, nil, nil, false)
		return rejection(data, reason), false
	end
	chargeToken = preparedChargeToken

	-- The reservation is private and atomic. Re-read all authoritative inputs
	-- immediately before capability consumption and exclude only this reservation.
	local currentSnapshot, currentMapValue, currentError = readMatchAndMap(data, userId, "submitPlacement")
	if
		currentSnapshot == nil
		or currentMapValue == nil
		or currentSnapshot.matchId ~= snapshot.matchId
		or currentMapValue ~= runtimeMapValue
	then
		rollback(data, reservationId, chargeToken, nil, nil, false)
		return rejection(data, mapContextError(data, currentError)), false
	end
	local currentMap = normalizeRuntimeMap(currentMapValue)
	local currentViewValue, currentTowerError = readTowerView(data, userId, "submitPlacement")
	local currentAnalysis = if currentViewValue ~= nil
		then analyzeTowerView(currentViewValue, currentSnapshot, userId)
		else nil
	if currentMap == nil or currentAnalysis == nil then
		faultData(data)
		rollback(data, reservationId, chargeToken, nil, nil, false)
		return rejection(data, mapContextError(data, currentTowerError)), false
	end
	local currentSlot = currentAnalysis.slots[intent.slot]
	if
		currentAnalysis.view.loadoutRevision ~= intent.loadoutRevision
		or currentSlot == nil
		or currentSlot.kind ~= "Occupied"
		or currentSlot.towerId ~= selectedSlot.towerId
		or currentSlot.placementCost ~= selectedSlot.placementCost
		or currentSlot.footprintRadiusStuds ~= selectedSlot.footprintRadiusStuds
		or currentSlot.placementCap ~= selectedSlot.placementCap
		or not revisionAccepted(data, intent.observedQueryRevision)
	then
		rollback(data, reservationId, chargeToken, nil, nil, false)
		return rejection(data, "Stale"), false
	end
	local currentFootprints = footprintsWithReservations(data, currentAnalysis.footprints, reservationId)
	if currentFootprints == nil then
		faultData(data)
		rollback(data, reservationId, chargeToken, nil, nil, false)
		return rejection(data, "Unavailable"), false
	end
	local currentGeometry = PlacementGeometry.evaluate(
		intent.positionXZ,
		currentSlot.footprintRadiusStuds,
		currentMap.bounds,
		currentMap.placementZones,
		currentMap.exclusions,
		currentFootprints
	)
	if not currentGeometry.valid or not capAvailable(data, currentAnalysis, userId, currentSlot, reservationId) then
		rollback(data, reservationId, chargeToken, nil, nil, false)
		return rejection(data, if currentGeometry.valid then "Capped" else geometryReason(currentGeometry.reason)),
			false
	end

	local towerRuntime = data.towerRuntime :: TowerRuntimeAdapter
	local resolved, resolveResult = callResult(towerRuntime.resolveOccupiedSlot, towerRuntime, userId, intent.slot)
	local issuedCapability = if resolved and isSuccess(resolveResult) then (resolveResult :: any).value else nil
	if not operationIntact(data) or not resolved or not isSuccess(resolveResult) then
		if not resolved then
			faultData(data)
		end
		rollback(data, reservationId, chargeToken, issuedCapability, nil, false)
		return rejection(
			data,
			if resultErrorCode(resolveResult) == "EMPTY_SLOT"
					or resultErrorCode(resolveResult) == "INVALID_SLOT"
				then "InvalidSlot"
				else "Unavailable"
		),
			false
	end
	capability = issuedCapability
	if type(capability) ~= "table" or not table.isfrozen(capability :: any) then
		faultData(data)
		rollback(data, reservationId, chargeToken, capability, nil, false)
		return rejection(data, "Unavailable"), false
	end

	local groundPosition = currentGeometry.position :: Vector3
	local placementCFrame = CFrame.new(groundPosition) * CFrame.Angles(0, math.rad(normalizedYaw), 0)
	if not PlacementGeometry.isUprightYawCFrame(placementCFrame) then
		faultData(data)
		rollback(data, reservationId, chargeToken, capability, nil, false)
		return rejection(data, "Unavailable"), false
	end
	local created, createResult = callResult(towerRuntime.trustedCreate, towerRuntime, capability, placementCFrame)
	if created and isSuccess(createResult) then
		capability = nil
		local rawCreated = (createResult :: any).value
		if type(rawCreated) == "table" and isPositiveSafeInteger((rawCreated :: any).runtimeTowerId) then
			createdRuntimeTowerId = (rawCreated :: any).runtimeTowerId
		end
	end
	if not operationIntact(data) or not created or not isSuccess(createResult) then
		if not created then
			faultData(data)
		end
		rollback(data, reservationId, chargeToken, capability, createdRuntimeTowerId, false)
		return rejection(data, "Unavailable"), false
	end
	local validatedRuntimeTowerId =
		validateCreatedTower((createResult :: any).value, currentSnapshot, userId, currentSlot, placementCFrame)
	if validatedRuntimeTowerId == nil then
		faultData(data)
		rollback(data, reservationId, chargeToken, nil, createdRuntimeTowerId, false)
		return rejection(data, "Unavailable"), false
	end
	createdRuntimeTowerId = validatedRuntimeTowerId

	local finalSnapshot, finalMapValue, finalError = readMatchAndMap(data, userId, "submitPlacement")
	local finalViewValue: any? = nil
	local finalTowerError: ServiceError? = nil
	if finalSnapshot ~= nil and finalMapValue == runtimeMapValue and finalSnapshot.matchId == snapshot.matchId then
		finalViewValue, finalTowerError = readTowerView(data, userId, "submitPlacement")
	end
	local finalAnalysis = if finalSnapshot ~= nil and finalViewValue ~= nil
		then analyzeTowerView(finalViewValue, finalSnapshot, userId)
		else nil
	local finalSlot = if finalAnalysis ~= nil then finalAnalysis.slots[intent.slot] else nil
	if
		finalSnapshot == nil
		or finalMapValue ~= runtimeMapValue
		or finalSnapshot.matchId ~= snapshot.matchId
		or finalAnalysis == nil
		or finalAnalysis.view.loadoutRevision ~= intent.loadoutRevision
		or finalSlot == nil
		or finalSlot.kind ~= "Occupied"
		or finalSlot.towerId ~= currentSlot.towerId
		or not reconcilesCreatedTower(
			finalAnalysis,
			createdRuntimeTowerId,
			userId,
			currentSlot.towerId,
			placementCFrame
		)
	then
		if finalSnapshot ~= nil and finalAnalysis == nil and finalViewValue ~= nil then
			faultData(data)
		end
		rollback(data, reservationId, chargeToken, nil, createdRuntimeTowerId, false)
		return rejection(data, mapContextError(data, if finalSnapshot == nil then finalError else finalTowerError)),
			false
	end

	commitAttempted = true
	local chargeCommitted, chargeCommitResult =
		callResult(affordabilityAdapter.commit, affordabilityAdapter, chargeToken)
	if not operationIntact(data) or not chargeCommitted or not resultSucceeded(chargeCommitResult, true) then
		if not chargeCommitted then
			faultData(data)
		end
		rollback(data, reservationId, chargeToken, nil, createdRuntimeTowerId, commitAttempted)
		return rejection(data, "Unavailable"), false
	end
	chargeToken = nil
	if not releaseReservation(data, reservationId) then
		-- The tower and placeholder token are committed. An impossible private-ledger
		-- failure is fatal; retain the accepted result because lying would invite replay.
		faultData(data)
	end
	if data.queryRevision >= Validation.MAX_SAFE_INTEGER then
		faultData(data)
		return failure("INTERNAL_ERROR", "submitPlacement"), true
	end
	data.queryRevision += 1
	local receipt = table.freeze({
		state = "Accepted",
		runtimeTowerId = createdRuntimeTowerId,
		placementCFrame = placementCFrame,
		queryRevision = data.queryRevision,
	})
	local receiptValidation = PlacementProtocol.validateReceipt(receipt)
	if not receiptValidation.ok then
		faultData(data)
		return failure("INTERNAL_ERROR", "submitPlacement"), true
	end

	local publisher = data.publishRevision
	if publisher ~= nil then
		local published, publishValue = callNonYielding(publisher, snapshot.matchId, data.queryRevision)
		if published and publishValue == true then
			data.publicationCount += 1
		else
			data.publicationFailureCount += 1
		end
	end
	return Result.ok(receiptValidation.value), true
end

local function destroyStudioTrigger(data: ServiceData): boolean
	local trigger = data.studioTrigger
	data.studioTrigger = nil
	data.studioOperationCount = 0
	data.studioRefreshCount = 0
	if trigger == nil then
		return true
	end
	if typeof(trigger) == "Instance" and (trigger :: Instance):IsA("BindableFunction") then
		local detached = pcall(function()
			(trigger :: BindableFunction).OnInvoke = nil
		end)
		local destroyed = callNonYielding((trigger :: Instance).Destroy, trigger)
		return detached and destroyed
	end
	return callNonYielding((trigger :: any).Destroy, trigger)
end

local function parseStudioOperation(argumentCount: number, request: unknown): string?
	if argumentCount ~= 1 or type(request) ~= "table" or getmetatable(request :: any) ~= nil then
		return nil
	end
	local fieldCount = 0
	for key in next, request :: any do
		fieldCount += 1
		if key ~= "operation" then
			return nil
		end
	end
	local operation = (request :: any).operation
	if fieldCount ~= 1 or (operation ~= "Refresh" and operation ~= "Diagnostics") then
		return nil
	end
	return operation
end

local function finishStudioFailure(data: ServiceData, code: ErrorCode): Result.Failure<ServiceError>
	if not finishOperation(data) then
		return failure("UNAVAILABLE", "studioEvidence")
	end
	return failure(code, "studioEvidence")
end

local function dispatchStudioEvidence(data: ServiceData, argumentCount: number, request: unknown): unknown
	local operationError = beginOperation(data, "studioEvidence")
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local operation = parseStudioOperation(argumentCount, request)
	if operation == nil then
		return finishStudioFailure(data, "INVALID_ARGUMENT")
	end
	data.studioOperationCount = math.min(data.studioOperationCount + 1, Validation.MAX_SAFE_INTEGER)
	if operation == "Diagnostics" then
		if not finishOperation(data) then
			return failure("UNAVAILABLE", "studioEvidence")
		end
		return Result.ok(collectMetrics(data))
	end

	local lifecycle = data.matchLifecycle
	local publisher = data.publishRevision
	if lifecycle == nil or publisher == nil then
		return finishStudioFailure(data, "UNAVAILABLE")
	end
	local snapshotCalled, snapshotResult = callResult(lifecycle.getSnapshot, lifecycle)
	if not operationIntact(data) then
		return finishStudioFailure(data, "UNAVAILABLE")
	end
	if not snapshotCalled then
		faultData(data)
		return finishStudioFailure(data, "INTERNAL_ERROR")
	end
	if not isSuccess(snapshotResult) then
		return finishStudioFailure(data, "UNAVAILABLE")
	end
	local snapshotValidation = MatchProtocol.validateMatchSnapshot((snapshotResult :: any).value)
	if not snapshotValidation.ok then
		faultData(data)
		return finishStudioFailure(data, "INTERNAL_ERROR")
	end
	local snapshot = snapshotValidation.value
	if snapshot.state ~= "PreWave" and snapshot.state ~= "WaveActive" then
		return finishStudioFailure(data, "NOT_ELIGIBLE")
	end
	local published, publishValue = callNonYielding(publisher, snapshot.matchId, data.queryRevision)
	if not operationIntact(data) then
		return finishStudioFailure(data, "UNAVAILABLE")
	end
	if not published or publishValue ~= true then
		data.publicationFailureCount += 1
		return finishStudioFailure(data, "UNAVAILABLE")
	end
	data.publicationCount += 1
	data.studioRefreshCount = math.min(data.studioRefreshCount + 1, Validation.MAX_SAFE_INTEGER)
	local receipt = table.freeze({
		matchId = snapshot.matchId,
		queryRevision = data.queryRevision,
		published = true,
	})
	if not finishOperation(data) then
		return failure("UNAVAILABLE", "studioEvidence")
	end
	return Result.ok(receipt)
end

local function installStudioTrigger(data: ServiceData): boolean
	local isStudio = data.isStudio
	local createRuntimeTrigger = data.createRuntimeTrigger
	if isStudio == nil or createRuntimeTrigger == nil then
		return false
	end
	local studioCalled, studioValue = callNonYielding(isStudio)
	if not studioCalled or type(studioValue) ~= "boolean" then
		return false
	end
	if not studioValue then
		data.isStudio = nil
		data.createRuntimeTrigger = nil
		return true
	end
	local handler = function(...: unknown): unknown
		local called, resultValue = callNonYielding(dispatchStudioEvidence, data, select("#", ...), select(1, ...))
		if called then
			return resultValue
		end
		data.operationActive = false
		data.reentryViolation = false
		faultData(data)
		local finalizer = completeDeferredShutdown
		if finalizer ~= nil then
			finalizer(data)
		end
		return failure("INTERNAL_ERROR", "studioEvidence")
	end
	local created, trigger = callNonYielding(createRuntimeTrigger, handler)
	if not created or not isRuntimeTriggerAdapter(trigger) then
		if isRuntimeTriggerAdapter(trigger) then
			callNonYielding((trigger :: any).Destroy, trigger)
		end
		return false
	end
	data.studioTrigger = trigger
	data.isStudio = nil
	data.createRuntimeTrigger = nil
	return true
end

local function cleanupData(data: ServiceData): boolean
	if data.cleanupCompleted then
		return true
	end
	local triggerCleaned = destroyStudioTrigger(data)
	table.clear(data.reservations)
	data.reservationCount = 0
	data.boundMatchId = nil
	data.boundRuntimeMap = nil
	local affordability = data.affordability
	local cleaned = triggerCleaned
	if affordability ~= nil then
		local called, resultValue = callResult(affordability.cleanup, affordability)
		cleaned = called and resultSucceeded(resultValue, true)
	end
	if not cleaned then
		return false
	end
	data.matchLifecycle = nil
	data.towerRuntime = nil
	data.affordability = nil
	data.publishRevision = nil
	data.isStudio = nil
	data.createRuntimeTrigger = nil
	data.cleanupCompleted = true
	return true
end

completeDeferredShutdown = function(data: ServiceData)
	local target: LifecycleState = if data.state == "ShuttingDown" then "Shutdown" else "Failed"
	data.shutdownRequested = false
	if not cleanupData(data) then
		data.state = "Failed"
		return
	end
	data.state = target
end

local function initialize(data: ServiceData)
	if data.state ~= "Constructed" then
		staticError("INVALID_STATE")
	end
	data.state = "Initializing"
	data.state = "Initialized"
end

local function start(data: ServiceData)
	if data.state ~= "Initialized" then
		staticError("INVALID_STATE")
	end
	data.state = "Starting"
	if not installStudioTrigger(data) then
		data.state = "Failed"
		cleanupData(data)
		staticError("STUDIO_TRIGGER_INSTALL_FAILED")
	end
	data.state = "Started"
end

local function shutdown(data: ServiceData)
	if data.state == "Shutdown" then
		return
	end
	if data.state == "ShuttingDown" then
		data.shutdownRequested = true
		return
	end
	if data.state ~= "Initialized" and data.state ~= "Started" and data.state ~= "Failed" then
		staticError("INVALID_STATE")
	end
	data.state = "ShuttingDown"
	data.shutdownRequested = true
	if data.operationActive then
		return
	end
	completeDeferredShutdown(data)
	if data.state ~= "Shutdown" then
		staticError("CLEANUP_FAILED")
	end
end

function Methods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	return requireData(self).serviceDefinition :: ServiceLifecycle.ServiceDefinition
end

function Methods.getLifecycleState(self: Service): LifecycleState
	return requireData(self).state
end

function Methods.getQuery(
	self: Service,
	userIdValue: unknown
): Result.Result<PlacementProtocol.QuerySnapshot, ServiceError>
	local data = requireData(self)
	local operationError = beginOperation(data, "getQuery")
	if operationError ~= nil then
		data.rejectedQueryCount += 1
		return Result.err(operationError)
	end
	if type(userIdValue) ~= "number" or not Validation.isSafeInteger(userIdValue) or userIdValue == 0 then
		data.rejectedQueryCount += 1
		finishOperation(data)
		return failure("INVALID_ARGUMENT", "getQuery")
	end
	local userId = userIdValue :: number
	local snapshot, runtimeMapValue, contextError = readMatchAndMap(data, userId, "getQuery")
	if snapshot == nil or runtimeMapValue == nil then
		data.rejectedQueryCount += 1
		finishOperation(data)
		return Result.err(contextError :: ServiceError)
	end
	local runtimeMap = normalizeRuntimeMap(runtimeMapValue)
	if runtimeMap == nil then
		data.rejectedQueryCount += 1
		finishOperation(data)
		return failure("UNAVAILABLE", "getQuery")
	end
	if not bindRuntimeIdentity(data, snapshot, runtimeMapValue) then
		data.rejectedQueryCount += 1
		finishOperation(data)
		return failure("INTERNAL_ERROR", "getQuery")
	end
	local towerView, towerError = readTowerView(data, userId, "getQuery")
	if towerView == nil then
		data.rejectedQueryCount += 1
		finishOperation(data)
		return Result.err(towerError :: ServiceError)
	end
	local analysis = analyzeTowerView(towerView, snapshot, userId)
	if analysis == nil then
		data.rejectedQueryCount += 1
		finishOperation(data)
		return failure("UNAVAILABLE", "getQuery")
	end
	local resultValue = buildQuery(data, userId, snapshot, runtimeMap, analysis)
	if resultValue.ok then
		data.queryCount += 1
	else
		data.rejectedQueryCount += 1
	end
	if not finishOperation(data) then
		return failure("INTERNAL_ERROR", "getQuery")
	end
	return resultValue
end

function Methods.submitPlacement(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<PlacementProtocol.PlacementReceipt, ServiceError>
	local data = requireData(self)
	local operationError = beginOperation(data, "submitPlacement")
	if operationError ~= nil then
		data.rejectedPlacementCount += 1
		return Result.err(operationError)
	end
	if type(userIdValue) ~= "number" or not Validation.isSafeInteger(userIdValue) or userIdValue == 0 then
		data.rejectedPlacementCount += 1
		finishOperation(data)
		return failure("INVALID_ARGUMENT", "submitPlacement")
	end
	local intentValidation = PlacementProtocol.validatePlacementIntent(intentValue)
	if not intentValidation.ok then
		data.rejectedPlacementCount += 1
		finishOperation(data)
		return failure("INVALID_ARGUMENT", "submitPlacement")
	end
	local resultValue, committed = submitCore(data, userIdValue :: number, intentValidation.value)
	if resultValue.ok and resultValue.value.state == "Accepted" then
		data.placementCount += 1
	else
		data.rejectedPlacementCount += 1
	end
	local intact = finishOperation(data)
	if not intact and not committed then
		return failure("UNAVAILABLE", "submitPlacement")
	end
	return resultValue
end

function Methods.getMetrics(self: Service): Metrics
	return collectMetrics(requireData(self))
end

local function construct(dependencies: TestDependencies): Service
	if
		type(dependencies) ~= "table"
		or getmetatable(dependencies :: any) ~= nil
		or not hasMethods(dependencies.matchLifecycle, MATCH_METHODS)
		or not hasMethods(dependencies.towerRuntime, TOWER_METHODS)
		or not hasMethods(dependencies.affordability, AFFORDABILITY_METHODS)
		or type(dependencies.publishRevision) ~= "function"
		or type(dependencies.isStudio) ~= "function"
		or type(dependencies.createRuntimeTrigger) ~= "function"
	then
		staticError("INVALID_DEPENDENCIES")
	end
	local data: ServiceData = {
		state = "Constructed",
		matchLifecycle = dependencies.matchLifecycle,
		towerRuntime = dependencies.towerRuntime,
		affordability = dependencies.affordability,
		publishRevision = dependencies.publishRevision,
		isStudio = dependencies.isStudio,
		createRuntimeTrigger = dependencies.createRuntimeTrigger,
		queryRevision = 1,
		queryCount = 0,
		rejectedQueryCount = 0,
		placementCount = 0,
		rejectedPlacementCount = 0,
		publicationCount = 0,
		publicationFailureCount = 0,
		reservations = {},
		reservationCount = 0,
		nextReservationId = 0,
		operationActive = false,
		reentryViolation = false,
		shutdownRequested = false,
		cleanupCompleted = false,
		boundMatchId = nil,
		boundRuntimeMap = nil,
		studioTrigger = nil,
		studioOperationCount = 0,
		studioRefreshCount = 0,
		serviceDefinition = nil,
	}
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	data.serviceDefinition = table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({ "NetworkRegistry", "MatchLifecycle", "WaveRuntime", "TowerRuntime" }),
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

local function productionPublishRevision(_matchId: unknown, _queryRevision: unknown): boolean
	return true
end

local function productionIsStudio(): unknown
	return RunService:IsStudio()
end

local function productionCreateRuntimeTrigger(handler: RuntimeTriggerHandler): unknown
	if not RunService:IsStudio() or ServerStorage:FindFirstChild(STUDIO_TRIGGER_NAME) ~= nil then
		return nil
	end
	local trigger = Instance.new("BindableFunction")
	local configured = pcall(function()
		trigger.Name = STUDIO_TRIGGER_NAME
		trigger.OnInvoke = handler
		trigger.Parent = ServerStorage
	end)
	if not configured then
		pcall(function()
			trigger.OnInvoke = nil
			trigger:Destroy()
		end)
		return nil
	end
	return trigger
end

function TowerPlacementService.new(
	matchLifecycle: MatchLifecycleAdapter,
	towerRuntime: TowerRuntimeAdapter,
	publishRevision: PublishRevision?
): Service
	return construct({
		matchLifecycle = matchLifecycle,
		towerRuntime = towerRuntime,
		affordability = PlacementAffordability.new(),
		publishRevision = publishRevision or productionPublishRevision,
		isStudio = productionIsStudio,
		createRuntimeTrigger = productionCreateRuntimeTrigger,
	})
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "TowerPlacementService" then
		return false
	end
	local folder = script.Parent
	if folder == nil or not folder:IsA("Folder") or folder.Name ~= "ProductionServerPlacement" then
		return false
	end
	local automatedTests = folder.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
		and automatedTests:FindFirstChild("Support") ~= nil
end

if isExactTestModule() then
	TowerPlacementService.newForTests = construct
end

table.freeze(Methods)
return table.freeze(TowerPlacementService)
