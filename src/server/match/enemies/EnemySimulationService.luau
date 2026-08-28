--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local AssetSchema = require(ReplicatedStorage.Shared.config.AssetSchema)
local DifficultySchema = require(ReplicatedStorage.Shared.config.DifficultySchema)
local EnemySchema = require(ReplicatedStorage.Shared.config.EnemySchema)
local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)
local EnemyReplicationPublisher = require(script.Parent.EnemyReplicationPublisher)
local EnemyRuntimeStore = require(script.Parent.EnemyRuntimeStore)

export type LifecycleState =
	"Constructed"
	| "Initializing"
	| "Initialized"
	| "Starting"
	| "Started"
	| "ShuttingDown"
	| "Shutdown"
	| "Failed"

export type Operation =
	"spawn"
	| "get"
	| "list"
	| "queryTerminal"
	| "setSlowMultiplier"
	| "resolveEndpoint"
	| "despawn"
	| "requestSnapshot"
	| "getIdentity"
	| "installStudioFixtures"
	| "initializeStudioBase"
	| "activateStudioWave"
	| "runtimeTrigger"

export type ErrorCode = "UNAVAILABLE" | "REENTRANT" | "INTERNAL_ERROR" | "INVALID_ARGUMENT" | "STUDIO_ONLY"
export type ServiceError = {
	code: ErrorCode,
	operation: Operation,
}

export type MatchLifecycleAdapter = {
	getSnapshot: (self: MatchLifecycleAdapter) -> unknown,
	getRuntimeMapSnapshot: (self: MatchLifecycleAdapter) -> unknown,
	beginBaseDefeat: (self: MatchLifecycleAdapter, matchId: unknown) -> unknown,
	commitBaseDefeat: (self: MatchLifecycleAdapter, token: unknown) -> unknown,
	rollbackBaseDefeat: (self: MatchLifecycleAdapter, token: unknown) -> unknown,
	activateStudioWaveForEvidence: (self: MatchLifecycleAdapter) -> unknown,
}

export type BaseRuntimeAdapter = {
	installStudioCatalog: (self: BaseRuntimeAdapter, catalog: unknown) -> unknown,
	initializeBase: (self: BaseRuntimeAdapter, definition: unknown) -> unknown,
	recordLeak: (self: BaseRuntimeAdapter, outcome: unknown) -> unknown,
	finishEnemyPass: (self: BaseRuntimeAdapter, passOrdinal: unknown) -> unknown,
	commitPreparedDefeat: (self: BaseRuntimeAdapter, token: unknown) -> unknown,
	failPreparedDefeat: (self: BaseRuntimeAdapter, token: unknown) -> unknown,
	fault: (self: BaseRuntimeAdapter) -> unknown,
	getSnapshot: (self: BaseRuntimeAdapter) -> unknown,
	getResultSeed: (self: BaseRuntimeAdapter) -> unknown,
	getDefeatState: (self: BaseRuntimeAdapter) -> unknown,
	getMetrics: (self: BaseRuntimeAdapter) -> unknown,
}

export type RuntimeStoreAdapter = {
	spawn: (self: RuntimeStoreAdapter, enemyId: unknown, laneId: unknown) -> unknown,
	get: (self: RuntimeStoreAdapter, runtimeEnemyId: unknown) -> unknown,
	list: (self: RuntimeStoreAdapter) -> unknown,
	queryTerminal: (self: RuntimeStoreAdapter, runtimeEnemyId: unknown) -> unknown,
	setSlowMultiplier: (self: RuntimeStoreAdapter, runtimeEnemyId: unknown, multiplier: unknown) -> unknown,
	resolveEndpoint: (self: RuntimeStoreAdapter, runtimeEnemyId: unknown) -> unknown,
	despawn: (self: RuntimeStoreAdapter, runtimeEnemyId: unknown) -> unknown,
	despawnAllForDefeat: (self: RuntimeStoreAdapter, runtimeEnemyIds: unknown) -> unknown,
	step: (self: RuntimeStoreAdapter, deltaSeconds: unknown) -> unknown,
	getIdentity: (self: RuntimeStoreAdapter) -> unknown,
	getMetrics: (self: RuntimeStoreAdapter) -> unknown,
	installStudioCatalog: (self: RuntimeStoreAdapter, catalog: unknown) -> unknown,
	listLaneIds: (self: RuntimeStoreAdapter) -> unknown,
	cleanup: (self: RuntimeStoreAdapter) -> unknown,
}

export type PublisherAdapter = {
	preflightSpawn: (self: PublisherAdapter) -> unknown,
	preflightStateChange: (self: PublisherAdapter, runtimeEnemyId: unknown) -> unknown,
	preflightEndpoint: (self: PublisherAdapter, runtimeEnemyId: unknown) -> unknown,
	preflightManualDespawn: (self: PublisherAdapter, runtimeEnemyId: unknown) -> unknown,
	preflightDefeat: (self: PublisherAdapter, runtimeEnemyIds: unknown) -> unknown,
	preflightStep: (self: PublisherAdapter, runtimeEnemyIds: unknown) -> unknown,
	commitSpawn: (self: PublisherAdapter, snapshot: unknown) -> unknown,
	commitStateChange: (self: PublisherAdapter, snapshot: unknown) -> unknown,
	commitEndpoint: (self: PublisherAdapter, endpoint: unknown, despawn: unknown) -> unknown,
	commitManualDespawn: (self: PublisherAdapter, despawn: unknown) -> unknown,
	commitDefeat: (self: PublisherAdapter, despawns: unknown) -> unknown,
	observeCorrection: (self: PublisherAdapter, runtimeEnemyId: unknown) -> unknown,
	advance: (self: PublisherAdapter, deltaSeconds: unknown, snapshotProvider: unknown) -> unknown,
	requestSnapshot: (self: PublisherAdapter, recipient: unknown, snapshotProvider: unknown) -> unknown,
	removePlayer: (self: PublisherAdapter, recipient: unknown) -> unknown,
	getMetrics: (self: PublisherAdapter) -> unknown,
	cleanup: (self: PublisherAdapter) -> unknown,
}

export type RuntimeStoreFactory = (
	matchId: unknown,
	catalog: unknown,
	runtimeMapSnapshot: unknown,
	endpointSink: unknown
) -> unknown
export type PublisherFactory = (matchId: unknown, enemyEpoch: unknown, dependencies: unknown) -> unknown
export type StepCallback = (deltaSeconds: number) -> ()
export type ConnectStep = (callback: StepCallback) -> unknown
export type PlayerRemovingCallback = (player: unknown, ...unknown) -> ()
export type ConnectPlayerRemoving = (callback: PlayerRemovingCallback) -> unknown
export type EnemySender = (recipient: unknown, message: unknown) -> boolean
export type GetRecipients = () -> unknown
export type IsStudio = () -> unknown
export type PassClock = () -> unknown
export type RuntimeTriggerHandler = (request: unknown) -> unknown
export type CreateRuntimeTrigger = (handler: RuntimeTriggerHandler) -> unknown

export type TestDependencies = {
	matchLifecycle: MatchLifecycleAdapter,
	baseRuntime: BaseRuntimeAdapter,
	catalog: unknown,
	createStore: RuntimeStoreFactory,
	createPublisher: PublisherFactory,
	connectStep: ConnectStep,
	connectPlayerRemoving: ConnectPlayerRemoving,
	sender: EnemySender,
	getRecipients: GetRecipients,
	isStudio: IsStudio?,
	passClock: PassClock?,
	createRuntimeTrigger: CreateRuntimeTrigger?,
	initialEnemyPassOrdinal: number?,
}

export type PassTimingMetrics = {
	capacity: number,
	sampleCount: number,
	totalSampleCount: number,
	lastSeconds: number,
	maximumSeconds: number,
	p50Seconds: number,
	p95Seconds: number,
}

export type ServiceMetrics = {
	lifecycleState: LifecycleState,
	stepConnectionCount: number,
	playerRemovingConnectionCount: number,
	faultDrainActive: boolean,
	retainsStore: boolean,
	retainsPublisher: boolean,
	store: unknown?,
	publisher: unknown?,
	studioTriggerCount: number,
	studioCatalogInstalled: boolean,
	studioBaseInitialized: boolean,
	studioBaseVariant: string?,
	studioWaveActivated: boolean,
	studioSpawnCount: number,
	studioBatchCount: number,
	spawnAdmissionClosed: boolean,
	nextEnemyPassOrdinal: number,
	defeatCount: number,
	resultsCommitCount: number,
	passTiming: PassTimingMetrics,
}

type ServiceData = {
	state: LifecycleState,
	matchLifecycle: MatchLifecycleAdapter?,
	baseRuntime: BaseRuntimeAdapter?,
	catalog: unknown,
	createStore: RuntimeStoreFactory?,
	createPublisher: PublisherFactory?,
	connectStep: ConnectStep?,
	connectPlayerRemoving: ConnectPlayerRemoving?,
	sender: EnemySender?,
	getRecipients: GetRecipients?,
	isStudio: IsStudio?,
	passClock: PassClock?,
	createRuntimeTrigger: CreateRuntimeTrigger?,
	store: RuntimeStoreAdapter?,
	publisher: PublisherAdapter?,
	stepConnection: unknown?,
	playerRemovingConnection: unknown?,
	callbacksEnabled: boolean,
	operationActive: boolean,
	shutdownRequested: boolean,
	faultRequested: boolean,
	faultDrainActive: boolean,
	releasing: boolean,
	deferredDisconnectFailed: boolean,
	studioTrigger: unknown?,
	studioTriggerOperationActive: boolean,
	studioCatalogInstalled: boolean,
	studioLaneId: string?,
	studioDifficultyDefinitions: { [string]: ConfigTypes.DifficultyDefinition }?,
	studioBaseInitialized: boolean,
	studioBaseVariant: string?,
	studioWaveActivated: boolean,
	studioSpawnCount: number,
	studioBatchCount: number,
	spawnAdmissionClosed: boolean,
	nextEnemyPassOrdinal: number,
	defeatCount: number,
	resultsCommitCount: number,
	passDurationSamples: { number },
	nextPassDurationIndex: number,
	totalPassDurationCount: number,
	lastPassDurationSeconds: number,
	maximumPassDurationSeconds: number,
	service: any?,
	serviceDefinition: ServiceLifecycle.ServiceDefinition?,
}

type CommittedStepResult = {
	deltaSeconds: number,
	visitedCount: number,
	updatedCount: number,
	endpointCount: number,
	activeCountAfter: number,
	cleaned: boolean,
	faulted: boolean,
	updatedRuntimeEnemyIds: { number },
	endpointResolutions: { any },
}

local SERVICE_NAME = "EnemySimulation"
local STATIC_ERROR_PREFIX = "[ATD_ENEMY_SIMULATION_SERVICE]"
local STUDIO_TRIGGER_NAME = "ATDPhase10BaseRuntime"
local STUDIO_MODEL_ASSET_KEY = "test.phase10.enemy-model"
local STUDIO_MEASUREMENT_ENEMY_ID = "enemy:phase10-studio-measurement"
local STUDIO_ZERO_ENEMY_ID = "enemy:phase10-studio-zero"
local STUDIO_ORDINARY_ENEMY_ID = "enemy:phase10-studio-ordinary"
local STUDIO_LOW_ENEMY_ID = "enemy:phase10-studio-low"
local STUDIO_EXACT_ENEMY_ID = "enemy:phase10-studio-exact"
local STUDIO_OVERKILL_ENEMY_ID = "enemy:phase10-studio-overkill"
local STUDIO_HIGH_ENEMY_ID = "enemy:phase10-studio-high"
local STUDIO_SURVIVOR_ENEMY_ID = "enemy:phase10-studio-survivor"
local STUDIO_MEASUREMENT_DIFFICULTY_ID = "difficulty:phase10-studio-measurement"
local STUDIO_DEFEAT_DIFFICULTY_ID = "difficulty:phase10-studio-defeat"
local STUDIO_MEASUREMENT_MAX_HEALTH = 1_000_000
local STUDIO_DEFEAT_MAX_HEALTH = 100
local STUDIO_FAST_SPEED = 1_000_000
local STUDIO_SURVIVOR_SPEED = 1
local STUDIO_BATCH_COUNTS = table.freeze({
	One = 1,
	ThirtyTwo = 32,
	SixtyFour = 64,
	OneTwentyEight = 128,
})
local STUDIO_ENEMY_IDS = table.freeze({
	Measurement = STUDIO_MEASUREMENT_ENEMY_ID,
	Zero = STUDIO_ZERO_ENEMY_ID,
	Ordinary = STUDIO_ORDINARY_ENEMY_ID,
	Low = STUDIO_LOW_ENEMY_ID,
	Exact = STUDIO_EXACT_ENEMY_ID,
	Overkill = STUDIO_OVERKILL_ENEMY_ID,
	High = STUDIO_HIGH_ENEMY_ID,
	Survivor = STUDIO_SURVIVOR_ENEMY_ID,
})
local PASS_DURATION_CAPACITY = 1_024
local MAX_STUDIO_LANES = 32

local ServiceMethods = {}
ServiceMethods.__index = ServiceMethods

export type Service = typeof(setmetatable({} :: {}, ServiceMethods))
export type TestConstructor = (dependencies: TestDependencies) -> Service

local SERVICE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local EnemySimulationService = {
	newForTests = nil :: TestConstructor?,
}

local function staticError(code: string): never
	error(`{STATIC_ERROR_PREFIX}[code={code}]`, 0)
end

local function requireData(value: unknown): ServiceData
	if type(value) ~= "table" then
		staticError("INVALID_CONTEXT")
	end
	local data = SERVICE_DATA[value :: any]
	if data == nil then
		staticError("INVALID_CONTEXT")
	end
	return data
end

local function makeServiceError(code: ErrorCode, operation: Operation): ServiceError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function serviceFailure(code: ErrorCode, operation: Operation): Result.Failure<ServiceError>
	return Result.err(makeServiceError(code, operation))
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, any)
	local callbackThread = coroutine.create(callback)
	local resumed, value = coroutine.resume(callbackThread, ...)
	if not resumed then
		return false, nil
	end
	if coroutine.status(callbackThread) ~= "dead" then
		pcall(coroutine.close, callbackThread)
		return false, nil
	end
	return true, value
end

local function isResult(value: unknown): boolean
	return type(value) == "table" and type((value :: any).ok) == "boolean"
end

local function isSuccess(value: unknown): boolean
	return isResult(value) and (value :: any).ok == true
end

local function callResult(callback: (...any) -> any, ...: any): (boolean, any)
	local called, value = callNonYielding(callback, ...)
	return called and isResult(value), value
end

local function isMatchLifecycleAdapter(value: unknown): boolean
	return type(value) == "table"
		and type((value :: any).getSnapshot) == "function"
		and type((value :: any).getRuntimeMapSnapshot) == "function"
		and type((value :: any).beginBaseDefeat) == "function"
		and type((value :: any).commitBaseDefeat) == "function"
		and type((value :: any).rollbackBaseDefeat) == "function"
		and type((value :: any).activateStudioWaveForEvidence) == "function"
end

local function isBaseRuntimeAdapter(value: unknown): boolean
	return type(value) == "table"
		and type((value :: any).installStudioCatalog) == "function"
		and type((value :: any).initializeBase) == "function"
		and type((value :: any).recordLeak) == "function"
		and type((value :: any).finishEnemyPass) == "function"
		and type((value :: any).commitPreparedDefeat) == "function"
		and type((value :: any).failPreparedDefeat) == "function"
		and type((value :: any).fault) == "function"
		and type((value :: any).getSnapshot) == "function"
		and type((value :: any).getResultSeed) == "function"
		and type((value :: any).getDefeatState) == "function"
		and type((value :: any).getMetrics) == "function"
end

local STORE_METHODS = table.freeze({
	"spawn",
	"get",
	"list",
	"queryTerminal",
	"setSlowMultiplier",
	"resolveEndpoint",
	"despawn",
	"despawnAllForDefeat",
	"step",
	"getIdentity",
	"getMetrics",
	"installStudioCatalog",
	"listLaneIds",
	"cleanup",
})

local PUBLISHER_METHODS = table.freeze({
	"preflightSpawn",
	"preflightStateChange",
	"preflightEndpoint",
	"preflightManualDespawn",
	"preflightDefeat",
	"preflightStep",
	"commitSpawn",
	"commitStateChange",
	"commitEndpoint",
	"commitManualDespawn",
	"commitDefeat",
	"observeCorrection",
	"advance",
	"requestSnapshot",
	"removePlayer",
	"getMetrics",
	"cleanup",
})

local function hasMethods(value: unknown, methodNames: { string }): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, methodName in methodNames do
		if type((value :: any)[methodName]) ~= "function" then
			return false
		end
	end
	return true
end

local function hasExactFields(value: { [any]: unknown }, allowedFields: { [string]: boolean }): boolean
	for fieldName in next, value do
		if type(fieldName) ~= "string" or allowedFields[fieldName] ~= true then
			return false
		end
	end
	for fieldName in allowedFields do
		if rawget(value, fieldName) == nil then
			return false
		end
	end
	return true
end

local function isStoreAdapter(value: unknown): boolean
	return hasMethods(value, STORE_METHODS)
end

local function isPublisherAdapter(value: unknown): boolean
	return hasMethods(value, PUBLISHER_METHODS)
end

local function isConnectionAdapter(value: unknown): boolean
	return typeof(value) == "RBXScriptConnection"
		or (type(value) == "table" and type((value :: any).Disconnect) == "function")
end

local function isRuntimeTriggerAdapter(value: unknown): boolean
	return typeof(value) == "Instance" and (value :: Instance):IsA("BindableFunction")
		or (type(value) == "table" and type((value :: any).Destroy) == "function")
end

local function clearConstructionDependencies(data: ServiceData)
	data.catalog = nil
	data.createStore = nil
	data.createPublisher = nil
	data.sender = nil
	data.getRecipients = nil
end

local function disconnectConnection(connection: unknown?): boolean
	if connection == nil then
		return true
	end
	local disconnected = callNonYielding((connection :: any).Disconnect, connection)
	return disconnected
end

local function disconnectStep(data: ServiceData): boolean
	local connection = data.stepConnection
	data.stepConnection = nil
	return disconnectConnection(connection)
end

local function disconnectPlayerRemoving(data: ServiceData): boolean
	local connection = data.playerRemovingConnection
	data.playerRemovingConnection = nil
	return disconnectConnection(connection)
end

local function cleanupPublisher(data: ServiceData): boolean
	local publisher = data.publisher
	data.publisher = nil
	if publisher == nil then
		return true
	end
	local called, resultValue = callResult(publisher.cleanup, publisher)
	return called and isSuccess(resultValue)
end

local function cleanupStore(data: ServiceData): boolean
	local store = data.store
	data.store = nil
	if store == nil then
		return true
	end
	local called, resultValue = callResult(store.cleanup, store)
	return called and isSuccess(resultValue)
end

local function destroyRuntimeTrigger(data: ServiceData): boolean
	local trigger = data.studioTrigger
	data.studioTrigger = nil
	data.studioTriggerOperationActive = false
	data.studioCatalogInstalled = false
	data.studioLaneId = nil
	data.studioDifficultyDefinitions = nil
	data.studioBaseInitialized = false
	data.studioBaseVariant = nil
	data.studioWaveActivated = false
	data.studioSpawnCount = 0
	data.studioBatchCount = 0
	data.service = nil
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

local function resetPassTiming(data: ServiceData)
	table.clear(data.passDurationSamples)
	data.nextPassDurationIndex = 1
	data.totalPassDurationCount = 0
	data.lastPassDurationSeconds = 0
	data.maximumPassDurationSeconds = 0
end

local function clearPassTiming(data: ServiceData)
	resetPassTiming(data)
	data.passClock = nil
end

local function releaseOwnedResources(data: ServiceData): boolean
	if data.releasing then
		return true
	end
	data.releasing = true
	data.callbacksEnabled = false
	data.faultDrainActive = false
	data.connectStep = nil
	data.connectPlayerRemoving = nil
	local stepDisconnected = disconnectStep(data)
	local removalDisconnected = disconnectPlayerRemoving(data)
	local triggerDestroyed = destroyRuntimeTrigger(data)
	local publisherCleaned = cleanupPublisher(data)
	local storeCleaned = cleanupStore(data)
	clearPassTiming(data)
	data.isStudio = nil
	data.createRuntimeTrigger = nil
	clearConstructionDependencies(data)
	data.matchLifecycle = nil
	data.baseRuntime = nil
	data.spawnAdmissionClosed = true
	data.nextEnemyPassOrdinal = 1
	data.defeatCount = 0
	data.resultsCommitCount = 0
	data.releasing = false
	return stepDisconnected and removalDisconnected and triggerDestroyed and publisherCleaned and storeCleaned
end

local function requestShutdownDuringOperation(data: ServiceData)
	data.shutdownRequested = true
	data.callbacksEnabled = false
	data.connectStep = nil
	data.connectPlayerRemoving = nil
	if not disconnectStep(data) then
		data.deferredDisconnectFailed = true
	end
	if not disconnectPlayerRemoving(data) then
		data.deferredDisconnectFailed = true
	end
end

local function finishDeferredShutdown(data: ServiceData): boolean
	if not data.shutdownRequested then
		return false
	end
	data.shutdownRequested = false
	local released = releaseOwnedResources(data)
	if released and not data.deferredDisconnectFailed then
		data.state = "Shutdown"
	else
		data.state = "Failed"
	end
	return true
end

local function stopFaultDrain(data: ServiceData)
	data.faultDrainActive = false
	if not disconnectStep(data) then
		data.deferredDisconnectFailed = true
	end
end

local function publisherMetrics(data: ServiceData): any?
	local publisher = data.publisher
	if publisher == nil then
		return nil
	end
	local called, metrics = callNonYielding(publisher.getMetrics, publisher)
	if not called or type(metrics) ~= "table" then
		return nil
	end
	return metrics
end

local function nonnegativeSafeMetric(metrics: any, fieldName: string): number?
	local value = metrics[fieldName]
	if type(value) ~= "number" or not Validation.isSafeInteger(value) or value < 0 then
		return nil
	end
	return value
end

local function hasDrainablePublication(metrics: any): boolean
	local pendingEntryCount = nonnegativeSafeMetric(metrics, "pendingEntryCount")
	if pendingEntryCount == nil then
		return false
	end
	if pendingEntryCount > 0 then
		return true
	end
	local dirtyCorrectionCount = nonnegativeSafeMetric(metrics, "dirtyCorrectionCount")
	if dirtyCorrectionCount == nil or dirtyCorrectionCount == 0 then
		return false
	end
	local deltaMessageCount = nonnegativeSafeMetric(metrics, "deltaMessageCount")
	local reservedFutureMessageCount = nonnegativeSafeMetric(metrics, "reservedFutureMessageCount")
	local reservedOrdinaryMessageCount = nonnegativeSafeMetric(metrics, "reservedOrdinaryMessageCount")
	local nextSequence = nonnegativeSafeMetric(metrics, "nextSequence")
	if
		deltaMessageCount == nil
		or reservedFutureMessageCount == nil
		or reservedOrdinaryMessageCount == nil
		or nextSequence == nil
		or nextSequence < 1
	then
		return false
	end
	local reservedMessages = reservedFutureMessageCount + reservedOrdinaryMessageCount
	local ordinaryMessageCapacity = EnemyProtocol.MAX_LIFETIME_DELTA_MESSAGES - deltaMessageCount - reservedMessages
	local sequenceCapacity = Validation.MAX_SAFE_INTEGER - (nextSequence - 1) - reservedMessages
	return ordinaryMessageCapacity >= 1 and sequenceCapacity >= 1
end

local function beginRuntimeFault(data: ServiceData)
	data.faultRequested = false
	data.state = "Failed"
	local metrics = publisherMetrics(data)
	if
		metrics ~= nil
		and (metrics :: any).faulted == false
		and (metrics :: any).cleaned == false
		and data.stepConnection ~= nil
		and hasDrainablePublication(metrics)
	then
		data.faultDrainActive = true
	else
		stopFaultDrain(data)
	end
end

local function finishOperation(data: ServiceData)
	data.operationActive = false
	if finishDeferredShutdown(data) then
		return
	end
	if data.faultRequested then
		beginRuntimeFault(data)
	end
end

local function beginPublicOperation(data: ServiceData, operation: Operation, mutation: boolean): ServiceError?
	if data.operationActive then
		return makeServiceError("REENTRANT", operation)
	end
	if mutation then
		if
			data.state ~= "Started"
			or (data.spawnAdmissionClosed and operation ~= "requestSnapshot" and operation ~= "runtimeTrigger")
		then
			return makeServiceError("UNAVAILABLE", operation)
		end
	elseif data.state ~= "Started" and data.state ~= "Failed" then
		return makeServiceError("UNAVAILABLE", operation)
	end
	data.operationActive = true
	return nil
end

local function snapshotProvider(data: ServiceData, runtimeEnemyIds: { number }?): unknown
	local store = data.store
	if store == nil then
		return serviceFailure("UNAVAILABLE", "list")
	end
	if runtimeEnemyIds == nil then
		local called, resultValue = callResult(store.list, store)
		return if called then resultValue else serviceFailure("INTERNAL_ERROR", "list")
	end
	local snapshots: { unknown } = table.create(#runtimeEnemyIds)
	for _, runtimeEnemyId in runtimeEnemyIds do
		local called, resultValue = callResult(store.get, store, runtimeEnemyId)
		if not called then
			return serviceFailure("INTERNAL_ERROR", "get")
		end
		if not isSuccess(resultValue) then
			return resultValue
		end
		table.insert(snapshots, (resultValue :: any).value)
	end
	table.freeze(snapshots)
	return Result.ok(snapshots)
end

local function denseFrozenAscendingIdsFromSnapshots(value: unknown): { number }?
	if
		type(value) ~= "table"
		or not table.isfrozen(value :: any)
		or getmetatable(value :: any) ~= nil
		or #value > EnemyProtocol.MAX_ACTIVE_ENEMIES
	then
		return nil
	end
	local length = #value
	local count = 0
	for key in next, value :: any do
		count += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return nil
		end
	end
	if count ~= length then
		return nil
	end
	local ids: { number } = table.create(length)
	local previousId: number? = nil
	for _, snapshotValue in value :: { unknown } do
		local runtimeEnemyId = if type(snapshotValue) == "table" then (snapshotValue :: any).runtimeEnemyId else nil
		if
			type(snapshotValue) ~= "table"
			or not table.isfrozen(snapshotValue :: any)
			or type(runtimeEnemyId) ~= "number"
			or not Validation.isSafeInteger(runtimeEnemyId)
			or runtimeEnemyId < 1
			or runtimeEnemyId > EnemyProtocol.MAX_RUNTIME_ENEMY_ID
			or (previousId ~= nil and runtimeEnemyId <= previousId)
		then
			return nil
		end
		previousId = runtimeEnemyId
		table.insert(ids, runtimeEnemyId)
	end
	table.freeze(ids)
	return ids
end

local function validateIdArray(value: unknown, maximum: number): { number }?
	if type(value) ~= "table" or not table.isfrozen(value :: any) or getmetatable(value :: any) ~= nil then
		return nil
	end
	local length = #value
	if length > maximum then
		return nil
	end
	local count = 0
	for key in next, value :: any do
		count += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return nil
		end
	end
	if count ~= length then
		return nil
	end
	local previousId: number? = nil
	for _, runtimeEnemyId in value :: { unknown } do
		if
			type(runtimeEnemyId) ~= "number"
			or not Validation.isSafeInteger(runtimeEnemyId)
			or runtimeEnemyId < 1
			or runtimeEnemyId > EnemyProtocol.MAX_RUNTIME_ENEMY_ID
			or (previousId ~= nil and runtimeEnemyId <= previousId)
		then
			return nil
		end
		previousId = runtimeEnemyId
	end
	return value :: { number }
end

local function validateEndpointResolutions(value: unknown): { any }?
	if type(value) ~= "table" or not table.isfrozen(value :: any) or getmetatable(value :: any) ~= nil then
		return nil
	end
	local length = #value
	if length > EnemyProtocol.MAX_ACTIVE_ENEMIES then
		return nil
	end
	local count = 0
	for key in next, value :: any do
		count += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return nil
		end
	end
	if count ~= length then
		return nil
	end
	local previousId: number? = nil
	for _, resolutionValue in value :: { unknown } do
		local endpoint = if type(resolutionValue) == "table" then (resolutionValue :: any).endpoint else nil
		local despawn = if type(resolutionValue) == "table" then (resolutionValue :: any).despawn else nil
		local endpointId = if type(endpoint) == "table" then (endpoint :: any).runtimeEnemyId else nil
		local despawnId = if type(despawn) == "table" then (despawn :: any).runtimeEnemyId else nil
		if
			type(resolutionValue) ~= "table"
			or not table.isfrozen(resolutionValue :: any)
			or getmetatable(resolutionValue :: any) ~= nil
			or type((resolutionValue :: any).callbackSucceeded) ~= "boolean"
			or type(endpointId) ~= "number"
			or not Validation.isSafeInteger(endpointId)
			or endpointId < 1
			or endpointId > EnemyProtocol.MAX_RUNTIME_ENEMY_ID
			or endpointId ~= despawnId
			or (previousId ~= nil and endpointId <= previousId)
		then
			return nil
		end
		previousId = endpointId
	end
	return value :: { any }
end

local function getCommittedStepResult(value: unknown, deltaSeconds: number, activeIds: { number }): CommittedStepResult?
	if not isSuccess(value) then
		return nil
	end
	local stepResult = (value :: any).value
	if
		type(stepResult) ~= "table"
		or not table.isfrozen(stepResult :: any)
		or getmetatable(stepResult :: any) ~= nil
		or (stepResult :: any).deltaSeconds ~= deltaSeconds
		or type((stepResult :: any).cleaned) ~= "boolean"
		or type((stepResult :: any).faulted) ~= "boolean"
	then
		return nil
	end
	for _, fieldName in { "visitedCount", "updatedCount", "endpointCount", "activeCountAfter" } do
		local fieldValue = (stepResult :: any)[fieldName]
		if
			type(fieldValue) ~= "number"
			or not Validation.isSafeInteger(fieldValue)
			or fieldValue < 0
			or fieldValue > EnemyProtocol.MAX_ACTIVE_ENEMIES
		then
			return nil
		end
	end
	local updatedIds = validateIdArray((stepResult :: any).updatedRuntimeEnemyIds, #activeIds)
	local endpointResolutions = validateEndpointResolutions((stepResult :: any).endpointResolutions)
	if
		updatedIds == nil
		or endpointResolutions == nil
		or (stepResult :: any).updatedCount ~= #updatedIds + #endpointResolutions
		or (stepResult :: any).endpointCount ~= #endpointResolutions
		or (stepResult :: any).visitedCount > #activeIds
	then
		return nil
	end
	local activeSet: { [number]: boolean } = {}
	for _, runtimeEnemyId in activeIds do
		activeSet[runtimeEnemyId] = true
	end
	local represented: { [number]: boolean } = {}
	for _, runtimeEnemyId in updatedIds do
		if not activeSet[runtimeEnemyId] or represented[runtimeEnemyId] then
			return nil
		end
		represented[runtimeEnemyId] = true
	end
	for _, resolution in endpointResolutions do
		local runtimeEnemyId = resolution.endpoint.runtimeEnemyId
		if not activeSet[runtimeEnemyId] or represented[runtimeEnemyId] then
			return nil
		end
		represented[runtimeEnemyId] = true
	end
	return stepResult :: CommittedStepResult
end

local function abortCurrentBasePass(data: ServiceData)
	-- The store has already committed this simulation pass. If its matching
	-- publisher transaction cannot complete, no later call may finish or reuse
	-- the leak outcomes queued synchronously by the endpoint callback.
	data.spawnAdmissionClosed = true
	local baseRuntime = data.baseRuntime
	if baseRuntime ~= nil then
		callResult(baseRuntime.fault, baseRuntime)
	end
	data.faultRequested = true
end

local function commitStepResult(data: ServiceData, activeIds: { number }, stepResult: CommittedStepResult): boolean
	local publisher = data.publisher
	if publisher == nil then
		abortCurrentBasePass(data)
		return false
	end
	local updatedIndex = 1
	local endpointIndex = 1
	for _, runtimeEnemyId in activeIds do
		local resolution = stepResult.endpointResolutions[endpointIndex]
		if resolution ~= nil and resolution.endpoint.runtimeEnemyId == runtimeEnemyId then
			local called, resultValue =
				callResult(publisher.commitEndpoint, publisher, resolution.endpoint, resolution.despawn)
			if not called or not isSuccess(resultValue) then
				abortCurrentBasePass(data)
				return false
			end
			endpointIndex += 1
		elseif stepResult.updatedRuntimeEnemyIds[updatedIndex] == runtimeEnemyId then
			if not stepResult.cleaned then
				local called, resultValue = callResult(publisher.observeCorrection, publisher, runtimeEnemyId)
				if not called or not isSuccess(resultValue) then
					abortCurrentBasePass(data)
					return false
				end
			end
			updatedIndex += 1
		end
	end
	if updatedIndex <= #stepResult.updatedRuntimeEnemyIds or endpointIndex <= #stepResult.endpointResolutions then
		abortCurrentBasePass(data)
		return false
	end
	return true
end

local function failPreparedDefeat(data: ServiceData, lifecycleToken: unknown?, baseToken: unknown)
	local lifecycle = data.matchLifecycle
	local baseRuntime = data.baseRuntime
	if lifecycleToken ~= nil and lifecycle ~= nil then
		callResult(lifecycle.rollbackBaseDefeat, lifecycle, lifecycleToken)
	end
	if baseRuntime ~= nil then
		callResult(baseRuntime.failPreparedDefeat, baseRuntime, baseToken)
	end
	data.spawnAdmissionClosed = true
end

local function coordinateDefeat(data: ServiceData, boundary: any): boolean
	local store = data.store
	local publisher = data.publisher
	local lifecycle = data.matchLifecycle
	local baseRuntime = data.baseRuntime
	local baseToken = if type(boundary) == "table" then boundary.preparedDefeat else nil
	if
		store == nil
		or publisher == nil
		or lifecycle == nil
		or baseRuntime == nil
		or type(baseToken) ~= "table"
		or not table.isfrozen(baseToken)
		or data.defeatCount ~= 0
	then
		return false
	end
	data.defeatCount = 1

	local listed, listResult = callResult(store.list, store)
	local activeIds = if listed and isSuccess(listResult)
		then denseFrozenAscendingIdsFromSnapshots((listResult :: any).value)
		else nil
	if activeIds == nil then
		failPreparedDefeat(data, nil, baseToken)
		return false
	end
	local preflighted, preflightResult = callResult(publisher.preflightDefeat, publisher, activeIds)
	if not preflighted or not isSuccess(preflightResult) then
		failPreparedDefeat(data, nil, baseToken)
		return false
	end
	local identityCalled, identityResult = callResult(store.getIdentity, store)
	local identity = if identityCalled and isSuccess(identityResult) then (identityResult :: any).value else nil
	local matchId = if type(identity) == "table" then (identity :: any).matchId else nil
	if type(matchId) ~= "string" then
		failPreparedDefeat(data, nil, baseToken)
		return false
	end
	local began, beginResult = callResult(lifecycle.beginBaseDefeat, lifecycle, matchId)
	if not began or not isSuccess(beginResult) then
		failPreparedDefeat(data, nil, baseToken)
		return false
	end
	local lifecycleToken = (beginResult :: any).value
	if type(lifecycleToken) ~= "table" or not table.isfrozen(lifecycleToken) then
		failPreparedDefeat(data, lifecycleToken, baseToken)
		return false
	end

	-- This is the first irreversible gameplay closure. Every preflight above is
	-- complete, and no public mutation can re-enter the active service operation.
	data.spawnAdmissionClosed = true
	local despawned, despawnResult = callResult(store.despawnAllForDefeat, store, activeIds)
	if not despawned or not isSuccess(despawnResult) then
		failPreparedDefeat(data, lifecycleToken, baseToken)
		return false
	end
	local committedEnemies, enemyCommitResult =
		callResult(publisher.commitDefeat, publisher, (despawnResult :: any).value)
	if not committedEnemies or not isSuccess(enemyCommitResult) then
		failPreparedDefeat(data, lifecycleToken, baseToken)
		return false
	end

	local transitioned, transitionResult = callResult(lifecycle.commitBaseDefeat, lifecycle, lifecycleToken)
	if not transitioned or not isSuccess(transitionResult) then
		failPreparedDefeat(data, lifecycleToken, baseToken)
		return false
	end
	local transition = (transitionResult :: any).value
	if
		type(transition) ~= "table"
		or not table.isfrozen(transition)
		or transition.committed ~= true
		or type(transition.published) ~= "boolean"
		or type(transition.snapshot) ~= "table"
		or transition.snapshot.state ~= "Results"
	then
		failPreparedDefeat(data, nil, baseToken)
		return false
	end
	data.resultsCommitCount = 1

	-- The production BaseRuntimeService makes this a trusted total postcondition:
	-- the prepared token was authenticated and all terminal/publication capacity
	-- was reserved before Results committed. A returned failure is contained as
	-- an adapter-contract invariant violation, not a recoverable transaction.
	local baseCommitted, baseCommitResult = callResult(baseRuntime.commitPreparedDefeat, baseRuntime, baseToken)
	if not baseCommitted or not isSuccess(baseCommitResult) then
		return false
	end
	local baseOutcome = (baseCommitResult :: any).value
	return type(baseOutcome) == "table"
		and table.isfrozen(baseOutcome)
		and baseOutcome.committed == true
		and type(baseOutcome.published) == "boolean"
end

local function finishBasePass(data: ServiceData): boolean
	local baseRuntime = data.baseRuntime
	local passOrdinal = data.nextEnemyPassOrdinal
	if baseRuntime == nil or passOrdinal > Validation.MAX_SAFE_INTEGER then
		return false
	end
	local called, boundaryResult = callResult(baseRuntime.finishEnemyPass, baseRuntime, passOrdinal)
	if not called or not isSuccess(boundaryResult) then
		callResult(baseRuntime.fault, baseRuntime)
		return false
	end
	local boundary = (boundaryResult :: any).value
	if
		type(boundary) ~= "table"
		or not table.isfrozen(boundary)
		or boundary.passOrdinal ~= passOrdinal
		or (boundary.kind ~= "Noop" and boundary.kind ~= "Damage" and boundary.kind ~= "DefeatPending")
	then
		callResult(baseRuntime.fault, baseRuntime)
		return false
	end
	if passOrdinal < Validation.MAX_SAFE_INTEGER then
		data.nextEnemyPassOrdinal = passOrdinal + 1
	else
		-- A terminal defeat needs no successor. A nonterminal pass cannot be
		-- represented safely and therefore faults closed without ever retaining
		-- MAX_SAFE_INTEGER + 1.
		data.nextEnemyPassOrdinal = Validation.MAX_SAFE_INTEGER
	end
	if boundary.kind == "DefeatPending" then
		return coordinateDefeat(data, boundary)
	end
	if passOrdinal == Validation.MAX_SAFE_INTEGER then
		abortCurrentBasePass(data)
		return false
	end
	return true
end

local function advancePublisher(data: ServiceData, deltaSeconds: number): boolean
	local publisher = data.publisher
	if publisher == nil then
		return false
	end
	local provider = function(runtimeEnemyIds: { number }?): unknown
		return snapshotProvider(data, runtimeEnemyIds)
	end
	local called, resultValue = callResult(publisher.advance, publisher, deltaSeconds, provider)
	return called and isSuccess(resultValue)
end

local function drainFault(data: ServiceData, deltaSeconds: number)
	if data.operationActive then
		stopFaultDrain(data)
		return
	end
	data.operationActive = true
	local advanced = advancePublisher(data, deltaSeconds)
	data.operationActive = false
	if finishDeferredShutdown(data) then
		return
	end
	local metrics = publisherMetrics(data)
	if
		not advanced
		or metrics == nil
		or (metrics :: any).faulted ~= false
		or (metrics :: any).cleaned ~= false
		or not hasDrainablePublication(metrics)
	then
		stopFaultDrain(data)
	end
end

local function update(data: ServiceData, deltaSeconds: number)
	if not data.callbacksEnabled then
		return
	end
	if data.state == "Failed" and data.faultDrainActive then
		drainFault(data, deltaSeconds)
		return
	end
	if data.state ~= "Started" then
		return
	end
	if data.operationActive or not Validation.isFiniteNumber(deltaSeconds) or deltaSeconds < 0 then
		beginRuntimeFault(data)
		return
	end
	local store = data.store
	local publisher = data.publisher
	if store == nil or publisher == nil then
		beginRuntimeFault(data)
		return
	end

	data.operationActive = true
	if data.spawnAdmissionClosed then
		local advanced = advancePublisher(data, deltaSeconds)
		data.faultRequested = not advanced
		finishOperation(data)
		return
	end
	local listed, listResult = callResult(store.list, store)
	local activeIds = if listed and isSuccess(listResult)
		then denseFrozenAscendingIdsFromSnapshots((listResult :: any).value)
		else nil
	if activeIds == nil then
		data.faultRequested = true
	else
		local preflightCalled, preflightResult = callResult(publisher.preflightStep, publisher, activeIds)
		if not preflightCalled or not isSuccess(preflightResult) then
			data.faultRequested = true
		else
			local stepped, stepResultValue = callResult(store.step, store, deltaSeconds)
			local stepResult = if stepped then getCommittedStepResult(stepResultValue, deltaSeconds, activeIds) else nil
			if stepResult == nil or not commitStepResult(data, activeIds, stepResult) then
				data.faultRequested = true
			else
				local baseFinished = finishBasePass(data)
				local requestedShutdown = data.shutdownRequested or stepResult.cleaned
				local advanced = requestedShutdown or advancePublisher(data, deltaSeconds)
				data.shutdownRequested = requestedShutdown
				data.faultRequested = not requestedShutdown and (not baseFinished or not advanced or stepResult.faulted)
			end
		end
	end
	finishOperation(data)
end

local function profiledUpdate(data: ServiceData, deltaSeconds: number)
	local passClock = data.passClock
	local startedAt: number? = nil
	if passClock ~= nil then
		local clockCalled, clockValue = callNonYielding(passClock)
		if
			clockCalled
			and type(clockValue) == "number"
			and Validation.isFiniteNumber(clockValue)
			and clockValue >= 0
		then
			startedAt = clockValue
		end
	end
	local profileBegin = (debug :: any).profilebegin
	local profileEnd = (debug :: any).profileend
	local profileStarted = false
	if type(profileBegin) == "function" and type(profileEnd) == "function" then
		profileStarted = pcall(profileBegin, "ATDEnemySimulation")
	end
	local updated = pcall(update, data, deltaSeconds)
	if profileStarted then
		pcall(profileEnd)
	end
	if startedAt ~= nil and passClock ~= nil then
		local clockCalled, clockValue = callNonYielding(passClock)
		if
			clockCalled
			and type(clockValue) == "number"
			and Validation.isFiniteNumber(clockValue)
			and clockValue >= startedAt
		then
			local duration = clockValue - startedAt
			local samples = data.passDurationSamples
			if #samples < PASS_DURATION_CAPACITY then
				table.insert(samples, duration)
			else
				samples[data.nextPassDurationIndex] = duration
				data.nextPassDurationIndex = if data.nextPassDurationIndex == PASS_DURATION_CAPACITY
					then 1
					else data.nextPassDurationIndex + 1
			end
			data.totalPassDurationCount = math.min(data.totalPassDurationCount + 1, Validation.MAX_SAFE_INTEGER)
			data.lastPassDurationSeconds = duration
			data.maximumPassDurationSeconds = math.max(data.maximumPassDurationSeconds, duration)
		end
	end
	if not updated then
		data.operationActive = false
		data.faultRequested = false
		beginRuntimeFault(data)
	end
end

local function removePlayer(data: ServiceData, player: unknown)
	if not data.callbacksEnabled or (data.state ~= "Started" and data.state ~= "Failed") then
		return
	end
	local publisher = data.publisher
	if publisher == nil then
		return
	end
	local called, resultValue = callResult(publisher.removePlayer, publisher, player)
	if not called or not isSuccess(resultValue) then
		if data.operationActive then
			data.faultRequested = true
		else
			beginRuntimeFault(data)
		end
	end
end

type StudioFixtures = {
	enemyCatalog: ConfigTypes.EnemyCatalog,
	difficultyCatalog: ConfigTypes.DifficultyCatalog,
	difficultyDefinitions: { [string]: ConfigTypes.DifficultyDefinition },
}

local function studioEnemyDefinition(
	id: string,
	displayName: string,
	moveSpeedStudsPerSecond: number,
	leakDamage: number
): { [string]: unknown }
	return {
		id = id,
		displayName = displayName,
		modelAssetKey = STUDIO_MODEL_ASSET_KEY,
		maxHealth = 100,
		moveSpeedStudsPerSecond = moveSpeedStudsPerSecond,
		leakDamage = leakDamage,
		damageIncomeClass = "None",
	}
end

local function studioDifficultyDefinition(id: string, displayName: string, maxHealth: number): { [string]: unknown }
	return {
		id = id,
		displayName = displayName,
		kind = "Finite",
		waveCount = 1,
		base = {
			maxHealth = maxHealth,
		},
		modifiers = {
			enemyHealthMultiplier = 1,
			enemyMoveSpeedMultiplier = 1,
		},
		timing = {
			earlyClearIntermissionSeconds = 0,
			bossCadenceWaves = 1,
			skipVoteMinimumDelaySeconds = 0,
		},
	}
end

local function createFreshStudioFixtures(): StudioFixtures?
	local manifestResult = AssetSchema.validateManifest({
		{
			key = STUDIO_MODEL_ASSET_KEY,
			kind = "EnemyModel",
		},
	})
	if not manifestResult.ok or not AssetSchema.isValidatedManifest(manifestResult.value) then
		return nil
	end
	local enemyCatalogResult = EnemySchema.validateCatalog({
		studioEnemyDefinition(STUDIO_MEASUREMENT_ENEMY_ID, "Phase 10 Studio Measurement Enemy", STUDIO_FAST_SPEED, 1),
		studioEnemyDefinition(STUDIO_ZERO_ENEMY_ID, "Phase 10 Studio Zero Enemy", STUDIO_FAST_SPEED, 0),
		studioEnemyDefinition(STUDIO_ORDINARY_ENEMY_ID, "Phase 10 Studio Ordinary Enemy", STUDIO_FAST_SPEED, 25),
		studioEnemyDefinition(STUDIO_LOW_ENEMY_ID, "Phase 10 Studio Low Enemy", STUDIO_FAST_SPEED, 750_000),
		studioEnemyDefinition(STUDIO_EXACT_ENEMY_ID, "Phase 10 Studio Exact Enemy", STUDIO_FAST_SPEED, 100),
		studioEnemyDefinition(STUDIO_OVERKILL_ENEMY_ID, "Phase 10 Studio Overkill Enemy", STUDIO_FAST_SPEED, 101),
		studioEnemyDefinition(
			STUDIO_HIGH_ENEMY_ID,
			"Phase 10 Studio High Enemy",
			STUDIO_FAST_SPEED,
			Validation.MAX_SAFE_INTEGER
		),
		studioEnemyDefinition(STUDIO_SURVIVOR_ENEMY_ID, "Phase 10 Studio Survivor Enemy", STUDIO_SURVIVOR_SPEED, 25),
	}, manifestResult.value)
	if not enemyCatalogResult.ok or not EnemySchema.isValidatedCatalog(enemyCatalogResult.value) then
		return nil
	end
	local difficultyCatalogResult = DifficultySchema.validateCatalog({
		studioDifficultyDefinition(
			STUDIO_MEASUREMENT_DIFFICULTY_ID,
			"Phase 10 Studio Measurement Difficulty",
			STUDIO_MEASUREMENT_MAX_HEALTH
		),
		studioDifficultyDefinition(
			STUDIO_DEFEAT_DIFFICULTY_ID,
			"Phase 10 Studio Defeat Difficulty",
			STUDIO_DEFEAT_MAX_HEALTH
		),
	}, manifestResult.value)
	if not difficultyCatalogResult.ok or not DifficultySchema.isValidatedCatalog(difficultyCatalogResult.value) then
		return nil
	end
	local measurementDefinition = difficultyCatalogResult.value.byId[STUDIO_MEASUREMENT_DIFFICULTY_ID]
	local defeatDefinition = difficultyCatalogResult.value.byId[STUDIO_DEFEAT_DIFFICULTY_ID]
	if measurementDefinition == nil or defeatDefinition == nil then
		return nil
	end
	return table.freeze({
		enemyCatalog = enemyCatalogResult.value,
		difficultyCatalog = difficultyCatalogResult.value,
		difficultyDefinitions = table.freeze({
			Measurement = measurementDefinition,
			Defeat = defeatDefinition,
		}),
	})
end

local function invalidTriggerRequest(): Result.Failure<ServiceError>
	return serviceFailure("INVALID_ARGUMENT", "runtimeTrigger")
end

local function studioVariantAllowed(baseVariant: string?, enemyVariant: string): boolean
	if baseVariant == "Measurement" then
		return enemyVariant == "Measurement"
			or enemyVariant == "Zero"
			or enemyVariant == "Ordinary"
			or enemyVariant == "Low"
	end
	return baseVariant == "Defeat"
		and (
			enemyVariant == "Zero"
			or enemyVariant == "Exact"
			or enemyVariant == "Overkill"
			or enemyVariant == "High"
			or enemyVariant == "Survivor"
		)
end

local function dispatchRuntimeTrigger(data: ServiceData, request: unknown): unknown
	local service = data.service
	if data.studioTrigger == nil or service == nil or not data.callbacksEnabled or data.state ~= "Started" then
		return serviceFailure("UNAVAILABLE", "runtimeTrigger")
	end
	if
		type(request) ~= "table"
		or getmetatable(request :: any) ~= nil
		or type((request :: any).operation) ~= "string"
	then
		return invalidTriggerRequest()
	end
	local operation = (request :: any).operation
	if operation == "InstallFixtures" then
		if not hasExactFields(request :: any, { operation = true }) then
			return invalidTriggerRequest()
		end
		return (service :: any):installStudioFixtures()
	elseif operation == "InitializeBase" then
		if not hasExactFields(request :: any, { operation = true, variant = true }) then
			return invalidTriggerRequest()
		end
		local variant = (request :: any).variant
		if variant ~= "Measurement" and variant ~= "Defeat" then
			return invalidTriggerRequest()
		end
		return (service :: any):initializeStudioBase(variant)
	elseif operation == "ActivateWave" then
		if not hasExactFields(request :: any, { operation = true }) then
			return invalidTriggerRequest()
		end
		return (service :: any):activateStudioWave()
	elseif operation == "SpawnFixture" then
		if not hasExactFields(request :: any, { operation = true, variant = true }) then
			return invalidTriggerRequest()
		end
		local variant = (request :: any).variant
		if type(variant) ~= "string" or STUDIO_ENEMY_IDS[variant] == nil then
			return invalidTriggerRequest()
		end
		local enemyId = STUDIO_ENEMY_IDS[variant]
		local laneId = data.studioLaneId
		if
			not data.studioWaveActivated
			or not studioVariantAllowed(data.studioBaseVariant, variant)
			or laneId == nil
		then
			return serviceFailure("UNAVAILABLE", "runtimeTrigger")
		end
		local spawnResult = (service :: any):spawn(enemyId, laneId)
		if isSuccess(spawnResult) then
			data.studioSpawnCount = math.min(data.studioSpawnCount + 1, Validation.MAX_SAFE_INTEGER)
		end
		return spawnResult
	elseif operation == "SpawnBatch" then
		if not hasExactFields(request :: any, { operation = true, batch = true }) then
			return invalidTriggerRequest()
		end
		local batch = (request :: any).batch
		if type(batch) ~= "string" or STUDIO_BATCH_COUNTS[batch] == nil then
			return invalidTriggerRequest()
		end
		return (service :: any):spawnStudioBatch(batch)
	elseif operation == "Diagnostics" then
		if not hasExactFields(request :: any, { operation = true }) then
			return invalidTriggerRequest()
		end
		return (service :: any):getStudioDiagnostics()
	elseif operation == "ResetTiming" then
		if not hasExactFields(request :: any, { operation = true }) then
			return invalidTriggerRequest()
		end
		resetPassTiming(data)
		return Result.ok(table.freeze({ reset = true }))
	elseif operation == "ClearEnemies" then
		if not hasExactFields(request :: any, { operation = true }) then
			return invalidTriggerRequest()
		end
		return (service :: any):clearStudioEnemies()
	end
	return invalidTriggerRequest()
end

local function installRuntimeTrigger(data: ServiceData): boolean
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
	local handler = function(request: unknown): unknown
		if data.studioTriggerOperationActive then
			return serviceFailure("REENTRANT", "runtimeTrigger")
		end
		data.studioTriggerOperationActive = true
		local called, resultValue = callNonYielding(dispatchRuntimeTrigger, data, request)
		data.studioTriggerOperationActive = false
		if not called then
			if data.operationActive then
				data.faultRequested = true
			else
				beginRuntimeFault(data)
			end
			return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
		end
		return resultValue
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

local function isValidLaneIdList(value: unknown): boolean
	if
		type(value) ~= "table"
		or not table.isfrozen(value :: any)
		or getmetatable(value :: any) ~= nil
		or #value < 1
		or #value > MAX_STUDIO_LANES
	then
		return false
	end
	local length = #value
	local count = 0
	for key in next, value :: any do
		count += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return false
		end
	end
	if count ~= length then
		return false
	end
	local previous: string? = nil
	for _, laneId in value :: { unknown } do
		if
			type(laneId) ~= "string"
			or not Validation.isSymbolicKey(laneId)
			or (previous ~= nil and laneId <= previous)
		then
			return false
		end
		previous = laneId
	end
	return true
end

local function failInitialize(data: ServiceData, code: string): never
	data.state = "Failed"
	releaseOwnedResources(data)
	staticError(code)
end

local function initialize(data: ServiceData)
	if data.state ~= "Constructed" then
		staticError("INVALID_STATE")
	end
	data.state = "Initializing"
	local matchLifecycle = data.matchLifecycle
	local baseRuntime = data.baseRuntime
	local createStore = data.createStore
	local createPublisher = data.createPublisher
	local sender = data.sender
	local getRecipients = data.getRecipients
	if
		matchLifecycle == nil
		or baseRuntime == nil
		or createStore == nil
		or createPublisher == nil
		or sender == nil
		or getRecipients == nil
	then
		failInitialize(data, "DEPENDENCY_MISSING")
	end

	local mapCalled, mapResult =
		callResult((matchLifecycle :: MatchLifecycleAdapter).getRuntimeMapSnapshot, matchLifecycle)
	if not mapCalled or not isSuccess(mapResult) then
		failInitialize(data, "RUNTIME_MAP_UNAVAILABLE")
	end
	local snapshotCalled, snapshotResult =
		callResult((matchLifecycle :: MatchLifecycleAdapter).getSnapshot, matchLifecycle)
	if not snapshotCalled or not isSuccess(snapshotResult) then
		failInitialize(data, "MATCH_SNAPSHOT_UNAVAILABLE")
	end
	local matchSnapshot = (snapshotResult :: any).value
	if type(matchSnapshot) ~= "table" or (matchSnapshot :: any).matchId == nil then
		failInitialize(data, "MATCH_SNAPSHOT_INVALID")
	end
	local endpointSink = function(outcome: unknown)
		local recorded, recordResult = callResult((baseRuntime :: BaseRuntimeAdapter).recordLeak, baseRuntime, outcome)
		if not recorded or not isSuccess(recordResult) then
			staticError("BASE_ENDPOINT_CALLBACK_FAILED")
		end
	end

	local storeCalled, storeResult = callResult(
		createStore :: RuntimeStoreFactory,
		(matchSnapshot :: any).matchId,
		data.catalog,
		(mapResult :: any).value,
		endpointSink
	)
	if not storeCalled or not isSuccess(storeResult) then
		failInitialize(data, "STORE_CREATION_FAILED")
	end
	local store = (storeResult :: any).value
	if not isStoreAdapter(store) then
		if type(store) == "table" and type((store :: any).cleanup) == "function" then
			callNonYielding((store :: any).cleanup, store)
		end
		failInitialize(data, "STORE_INVALID")
	end
	data.store = store :: RuntimeStoreAdapter

	local identityCalled, identityResult = callResult((store :: RuntimeStoreAdapter).getIdentity, store)
	if not identityCalled or not isSuccess(identityResult) then
		failInitialize(data, "STORE_IDENTITY_UNAVAILABLE")
	end
	local identity = (identityResult :: any).value
	if
		type(identity) ~= "table"
		or (identity :: any).matchId ~= (matchSnapshot :: any).matchId
		or type((identity :: any).enemyEpoch) ~= "number"
		or not Validation.isSafeInteger((identity :: any).enemyEpoch)
		or (identity :: any).enemyEpoch < 1
		or (identity :: any).enemyEpoch > EnemyProtocol.MAX_ENEMY_EPOCH
	then
		failInitialize(data, "STORE_IDENTITY_INVALID")
	end

	local publisherCalled, publisherResult = callResult(
		createPublisher :: PublisherFactory,
		(identity :: any).matchId,
		(identity :: any).enemyEpoch,
		table.freeze({ sender = sender, getRecipients = getRecipients })
	)
	if not publisherCalled or not isSuccess(publisherResult) then
		failInitialize(data, "PUBLISHER_CREATION_FAILED")
	end
	local publisher = (publisherResult :: any).value
	if not isPublisherAdapter(publisher) then
		if type(publisher) == "table" and type((publisher :: any).cleanup) == "function" then
			callNonYielding((publisher :: any).cleanup, publisher)
		end
		failInitialize(data, "PUBLISHER_INVALID")
	end
	data.publisher = publisher :: PublisherAdapter
	clearConstructionDependencies(data)
	data.state = "Initialized"
end

local function start(data: ServiceData)
	if data.state ~= "Initialized" then
		staticError("INVALID_STATE")
	end
	data.state = "Starting"
	local connectStep = data.connectStep
	local connectPlayerRemoving = data.connectPlayerRemoving
	if connectStep == nil or connectPlayerRemoving == nil then
		data.state = "Failed"
		releaseOwnedResources(data)
		staticError("CONNECTOR_MISSING")
	end

	local removalCalled, removalConnection = callNonYielding(
		connectPlayerRemoving :: ConnectPlayerRemoving,
		function(player)
			removePlayer(data, player)
		end
	)
	if not removalCalled or not isConnectionAdapter(removalConnection) then
		data.state = "Failed"
		releaseOwnedResources(data)
		staticError("PLAYER_REMOVING_CONNECTION_FAILED")
	end
	data.playerRemovingConnection = removalConnection

	local stepCalled, stepConnection = callNonYielding(connectStep :: ConnectStep, function(deltaSeconds)
		profiledUpdate(data, deltaSeconds)
	end)
	if not stepCalled or not isConnectionAdapter(stepConnection) then
		data.state = "Failed"
		releaseOwnedResources(data)
		staticError("CONNECTION_FAILED")
	end
	data.stepConnection = stepConnection
	if not installRuntimeTrigger(data) then
		data.state = "Failed"
		releaseOwnedResources(data)
		staticError("RUNTIME_TRIGGER_CREATION_FAILED")
	end
	data.connectStep = nil
	data.connectPlayerRemoving = nil
	data.callbacksEnabled = true
	data.state = "Started"
end

local function shutdown(data: ServiceData)
	if data.state == "Shutdown" or data.state == "ShuttingDown" then
		return
	end
	if data.state ~= "Initialized" and data.state ~= "Started" and data.state ~= "Failed" then
		staticError("INVALID_STATE")
	end
	data.state = "ShuttingDown"
	if data.operationActive then
		requestShutdownDuringOperation(data)
		return
	end
	local released = releaseOwnedResources(data)
	if not released or data.deferredDisconnectFailed then
		data.state = "Failed"
		staticError("CLEANUP_FAILED")
	end
	data.state = "Shutdown"
end

local function requireFacade(data: ServiceData, operation: Operation, mutation: boolean): any?
	local operationError = beginPublicOperation(data, operation, mutation)
	return if operationError == nil then nil else Result.err(operationError)
end

local function malformedDependencyResult(data: ServiceData, operation: Operation): Result.Failure<ServiceError>
	data.faultRequested = true
	return serviceFailure("INTERNAL_ERROR", operation)
end

local function finishAndReturn(data: ServiceData, resultValue: any): any
	finishOperation(data)
	return resultValue
end

function ServiceMethods.installStudioFixtures(self: Service): unknown
	local data = requireData(self)
	local operation: Operation = "installStudioFixtures"
	local unavailable = requireFacade(data, operation, true)
	if unavailable ~= nil then
		return unavailable
	end
	if data.studioTrigger == nil or data.studioCatalogInstalled then
		return finishAndReturn(data, serviceFailure("STUDIO_ONLY", operation))
	end
	local fixtures = createFreshStudioFixtures()
	local store = data.store
	local baseRuntime = data.baseRuntime
	if fixtures == nil or store == nil or baseRuntime == nil then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	local baseInstalled, baseInstallResult =
		callResult(baseRuntime.installStudioCatalog, baseRuntime, fixtures.difficultyCatalog)
	if not baseInstalled then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	if not isSuccess(baseInstallResult) then
		return finishAndReturn(data, baseInstallResult)
	end
	local enemyInstalled, enemyInstallResult = callResult(store.installStudioCatalog, store, fixtures.enemyCatalog)
	if not enemyInstalled or not isSuccess(enemyInstallResult) then
		data.faultRequested = true
		return finishAndReturn(
			data,
			if enemyInstalled then enemyInstallResult else serviceFailure("INTERNAL_ERROR", operation)
		)
	end
	local listed, laneResult = callResult(store.listLaneIds, store)
	local laneIds = if listed and isSuccess(laneResult) then (laneResult :: any).value else nil
	if not isValidLaneIdList(laneIds) then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	data.studioCatalogInstalled = true
	data.studioLaneId = laneIds[1]
	data.studioDifficultyDefinitions = fixtures.difficultyDefinitions
	return finishAndReturn(
		data,
		Result.ok(table.freeze({
			baseVariants = table.freeze({ "Measurement", "Defeat" }),
			enemyVariants = table.freeze({
				"Measurement",
				"Zero",
				"Ordinary",
				"Low",
				"Exact",
				"Overkill",
				"High",
				"Survivor",
			}),
			batchVariants = table.freeze({ "One", "ThirtyTwo", "SixtyFour", "OneTwentyEight" }),
			laneId = laneIds[1],
		}))
	)
end

function ServiceMethods.initializeStudioBase(self: Service, variant: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "initializeStudioBase"
	local unavailable = requireFacade(data, operation, true)
	if unavailable ~= nil then
		return unavailable
	end
	local definitions = data.studioDifficultyDefinitions
	local baseRuntime = data.baseRuntime
	local definition = if definitions ~= nil and type(variant) == "string" then definitions[variant] else nil
	if
		data.studioTrigger == nil
		or not data.studioCatalogInstalled
		or data.studioBaseInitialized
		or definition == nil
		or baseRuntime == nil
	then
		return finishAndReturn(data, serviceFailure("STUDIO_ONLY", operation))
	end
	local called, resultValue = callResult(baseRuntime.initializeBase, baseRuntime, definition)
	if not called then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	if isSuccess(resultValue) then
		data.studioBaseInitialized = true
		data.studioBaseVariant = variant :: string
		data.studioDifficultyDefinitions = nil
	end
	return finishAndReturn(data, resultValue)
end

function ServiceMethods.activateStudioWave(self: Service): unknown
	local data = requireData(self)
	local operation: Operation = "activateStudioWave"
	local unavailable = requireFacade(data, operation, true)
	if unavailable ~= nil then
		return unavailable
	end
	local matchLifecycle = data.matchLifecycle
	if
		data.studioTrigger == nil
		or not data.studioBaseInitialized
		or data.studioWaveActivated
		or matchLifecycle == nil
	then
		return finishAndReturn(data, serviceFailure("STUDIO_ONLY", operation))
	end
	local called, resultValue = callResult(matchLifecycle.activateStudioWaveForEvidence, matchLifecycle)
	if not called then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	if isSuccess(resultValue) then
		data.studioWaveActivated = true
	end
	return finishAndReturn(data, resultValue)
end

function ServiceMethods.spawnStudioBatch(self: Service, batch: unknown): unknown
	local data = requireData(self)
	local count = if type(batch) == "string" then STUDIO_BATCH_COUNTS[batch] else nil
	local laneId = data.studioLaneId
	if
		data.studioTrigger == nil
		or not data.studioWaveActivated
		or data.studioBaseVariant ~= "Measurement"
		or type(count) ~= "number"
		or laneId == nil
	then
		return serviceFailure("STUDIO_ONLY", "runtimeTrigger")
	end
	local listed = (self :: any):list()
	local activeSnapshots = if isSuccess(listed) then (listed :: any).value else nil
	if
		type(activeSnapshots) ~= "table"
		or getmetatable(activeSnapshots :: any) ~= nil
		or #activeSnapshots > EnemyProtocol.MAX_ACTIVE_ENEMIES - count
	then
		return serviceFailure("UNAVAILABLE", "runtimeTrigger")
	end
	for _ = 1, count do
		local spawned = (self :: any):spawn(STUDIO_MEASUREMENT_ENEMY_ID, laneId)
		if not isSuccess(spawned) then
			return spawned
		end
		data.studioSpawnCount = math.min(data.studioSpawnCount + 1, Validation.MAX_SAFE_INTEGER)
	end
	data.studioBatchCount = math.min(data.studioBatchCount + 1, Validation.MAX_SAFE_INTEGER)
	return Result.ok(table.freeze({
		batch = batch,
		count = count,
	}))
end

function ServiceMethods.clearStudioEnemies(self: Service): unknown
	local data = requireData(self)
	if data.studioTrigger == nil then
		return serviceFailure("STUDIO_ONLY", "runtimeTrigger")
	end
	local listed = (self :: any):list()
	if not isSuccess(listed) then
		return listed
	end
	local clearedCount = 0
	for _, enemySnapshot in (listed :: any).value do
		local despawned = (self :: any):despawn(enemySnapshot.runtimeEnemyId)
		if not isSuccess(despawned) then
			return despawned
		end
		clearedCount += 1
	end
	return Result.ok(table.freeze({ count = clearedCount }))
end

function ServiceMethods.getStudioDiagnostics(self: Service): unknown
	local data = requireData(self)
	local matchLifecycle = data.matchLifecycle
	local baseRuntime = data.baseRuntime
	if data.studioTrigger == nil or matchLifecycle == nil or baseRuntime == nil then
		return serviceFailure("UNAVAILABLE", "runtimeTrigger")
	end
	local matchCalled, matchResult = callResult(matchLifecycle.getSnapshot, matchLifecycle)
	local baseCalled, baseResult = callResult(baseRuntime.getSnapshot, baseRuntime)
	local seedCalled, seedResult = callResult(baseRuntime.getResultSeed, baseRuntime)
	local listed = (self :: any):list()
	local metricsCalled, baseMetrics = callNonYielding(baseRuntime.getMetrics, baseRuntime)
	local defeatCalled, defeatState = callNonYielding(baseRuntime.getDefeatState, baseRuntime)
	local matchSnapshot = if isSuccess(matchResult) then (matchResult :: any).value else nil
	local baseSnapshot = if isSuccess(baseResult) then (baseResult :: any).value else nil
	local resultSeed = if isSuccess(seedResult) then (seedResult :: any).value else nil
	local activeSnapshots = if isSuccess(listed) then (listed :: any).value else nil
	if
		not matchCalled
		or not isSuccess(matchResult)
		or not baseCalled
		or not seedCalled
		or not isSuccess(listed)
		or not metricsCalled
		or type(baseMetrics) ~= "table"
		or not table.isfrozen(baseMetrics :: any)
		or not defeatCalled
		or type(defeatState) ~= "table"
		or not table.isfrozen(defeatState :: any)
		or type(matchSnapshot) ~= "table"
		or not table.isfrozen(matchSnapshot :: any)
		or type((matchSnapshot :: any).matchId) ~= "string"
		or type((matchSnapshot :: any).state) ~= "string"
		or type((matchSnapshot :: any).revision) ~= "number"
		or not Validation.isSafeInteger((matchSnapshot :: any).revision)
		or (baseSnapshot ~= nil and (type(baseSnapshot) ~= "table" or not table.isfrozen(baseSnapshot :: any)))
		or (resultSeed ~= nil and (type(resultSeed) ~= "table" or not table.isfrozen(resultSeed :: any)))
		or type(activeSnapshots) ~= "table"
		or not table.isfrozen(activeSnapshots :: any)
		or #activeSnapshots > EnemyProtocol.MAX_ACTIVE_ENEMIES
	then
		return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
	end
	return Result.ok(table.freeze({
		activeEnemyCount = #activeSnapshots,
		enemy = self:getMetrics(),
		base = baseMetrics,
		baseSnapshotAvailable = baseSnapshot ~= nil,
		baseSnapshot = baseSnapshot,
		defeatState = defeatState,
		match = table.freeze({
			matchId = (matchSnapshot :: any).matchId,
			state = (matchSnapshot :: any).state,
			revision = (matchSnapshot :: any).revision,
		}),
		resultSeedAvailable = resultSeed ~= nil,
		resultSeed = resultSeed,
	}))
end

function ServiceMethods.spawn(self: Service, enemyId: unknown, laneId: unknown): unknown
	local data = requireData(self)
	local unavailable = requireFacade(data, "spawn", true)
	if unavailable ~= nil then
		return unavailable
	end
	local publisher = data.publisher :: PublisherAdapter
	local store = data.store :: RuntimeStoreAdapter
	local preflightCalled, preflightResult = callResult(publisher.preflightSpawn, publisher)
	if not preflightCalled then
		return finishAndReturn(data, malformedDependencyResult(data, "spawn"))
	end
	if not isSuccess(preflightResult) then
		return finishAndReturn(data, preflightResult)
	end
	local storeCalled, storeResult = callResult(store.spawn, store, enemyId, laneId)
	if not storeCalled then
		return finishAndReturn(data, malformedDependencyResult(data, "spawn"))
	end
	if not isSuccess(storeResult) then
		return finishAndReturn(data, storeResult)
	end
	local commitCalled, commitResult = callResult(publisher.commitSpawn, publisher, (storeResult :: any).value)
	if not commitCalled or not isSuccess(commitResult) then
		data.faultRequested = true
		return finishAndReturn(data, if commitCalled then commitResult else serviceFailure("INTERNAL_ERROR", "spawn"))
	end
	return finishAndReturn(data, storeResult)
end

local function readStore(data: ServiceData, operation: Operation, methodName: string, ...: any): unknown
	local unavailable = requireFacade(data, operation, false)
	if unavailable ~= nil then
		return unavailable
	end
	local store = data.store
	if store == nil then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	local called, resultValue = callResult((store :: any)[methodName], store, ...)
	return finishAndReturn(data, if called then resultValue else malformedDependencyResult(data, operation))
end

function ServiceMethods.get(self: Service, runtimeEnemyId: unknown): unknown
	return readStore(requireData(self), "get", "get", runtimeEnemyId)
end

function ServiceMethods.list(self: Service): unknown
	return readStore(requireData(self), "list", "list")
end

function ServiceMethods.queryTerminal(self: Service, runtimeEnemyId: unknown): unknown
	return readStore(requireData(self), "queryTerminal", "queryTerminal", runtimeEnemyId)
end

function ServiceMethods.getIdentity(self: Service): unknown
	return readStore(requireData(self), "getIdentity", "getIdentity")
end

function ServiceMethods.setSlowMultiplier(self: Service, runtimeEnemyId: unknown, multiplier: unknown): unknown
	local data = requireData(self)
	local unavailable = requireFacade(data, "setSlowMultiplier", true)
	if unavailable ~= nil then
		return unavailable
	end
	local publisher = data.publisher :: PublisherAdapter
	local store = data.store :: RuntimeStoreAdapter
	local beforeCalled, beforeResult = callResult(store.get, store, runtimeEnemyId)
	if not beforeCalled then
		return finishAndReturn(data, malformedDependencyResult(data, "setSlowMultiplier"))
	end
	if not isSuccess(beforeResult) then
		return finishAndReturn(data, beforeResult)
	end
	local before = (beforeResult :: any).value
	local unchanged = type(before) == "table"
		and type((before :: any).speedModifiers) == "table"
		and (before :: any).speedModifiers.slowMultiplier == multiplier
	if not unchanged then
		local preflightCalled, preflightResult = callResult(publisher.preflightStateChange, publisher, runtimeEnemyId)
		if not preflightCalled then
			return finishAndReturn(data, malformedDependencyResult(data, "setSlowMultiplier"))
		end
		if not isSuccess(preflightResult) then
			return finishAndReturn(data, preflightResult)
		end
	end
	local storeCalled, storeResult = callResult(store.setSlowMultiplier, store, runtimeEnemyId, multiplier)
	if not storeCalled then
		return finishAndReturn(data, malformedDependencyResult(data, "setSlowMultiplier"))
	end
	if not isSuccess(storeResult) or unchanged then
		return finishAndReturn(data, storeResult)
	end
	local commitCalled, commitResult = callResult(publisher.commitStateChange, publisher, (storeResult :: any).value)
	if not commitCalled or not isSuccess(commitResult) then
		data.faultRequested = true
		return finishAndReturn(
			data,
			if commitCalled then commitResult else serviceFailure("INTERNAL_ERROR", "setSlowMultiplier")
		)
	end
	return finishAndReturn(data, storeResult)
end

function ServiceMethods.resolveEndpoint(self: Service, runtimeEnemyId: unknown): unknown
	local data = requireData(self)
	local unavailable = requireFacade(data, "resolveEndpoint", true)
	if unavailable ~= nil then
		return unavailable
	end
	local publisher = data.publisher :: PublisherAdapter
	local store = data.store :: RuntimeStoreAdapter
	local preflightCalled, preflightResult = callResult(publisher.preflightEndpoint, publisher, runtimeEnemyId)
	if not preflightCalled then
		return finishAndReturn(data, malformedDependencyResult(data, "resolveEndpoint"))
	end
	if not isSuccess(preflightResult) then
		return finishAndReturn(data, preflightResult)
	end
	local storeCalled, storeResult = callResult(store.resolveEndpoint, store, runtimeEnemyId)
	if not storeCalled then
		return finishAndReturn(data, malformedDependencyResult(data, "resolveEndpoint"))
	end
	if not isSuccess(storeResult) then
		return finishAndReturn(data, storeResult)
	end
	local resolution = (storeResult :: any).value
	local commitCalled, commitResult =
		callResult(publisher.commitEndpoint, publisher, (resolution :: any).endpoint, (resolution :: any).despawn)
	if not commitCalled or not isSuccess(commitResult) then
		abortCurrentBasePass(data)
		return finishAndReturn(
			data,
			if commitCalled then commitResult else serviceFailure("INTERNAL_ERROR", "resolveEndpoint")
		)
	end
	local baseFinished = finishBasePass(data)
	if (resolution :: any).callbackSucceeded ~= true or not baseFinished then
		data.faultRequested = true
	end
	return finishAndReturn(data, storeResult)
end

function ServiceMethods.despawn(self: Service, runtimeEnemyId: unknown): unknown
	local data = requireData(self)
	local unavailable = requireFacade(data, "despawn", true)
	if unavailable ~= nil then
		return unavailable
	end
	local publisher = data.publisher :: PublisherAdapter
	local store = data.store :: RuntimeStoreAdapter
	local preflightCalled, preflightResult = callResult(publisher.preflightManualDespawn, publisher, runtimeEnemyId)
	if not preflightCalled then
		return finishAndReturn(data, malformedDependencyResult(data, "despawn"))
	end
	if not isSuccess(preflightResult) then
		return finishAndReturn(data, preflightResult)
	end
	local storeCalled, storeResult = callResult(store.despawn, store, runtimeEnemyId)
	if not storeCalled then
		return finishAndReturn(data, malformedDependencyResult(data, "despawn"))
	end
	if not isSuccess(storeResult) then
		return finishAndReturn(data, storeResult)
	end
	local commitCalled, commitResult = callResult(publisher.commitManualDespawn, publisher, (storeResult :: any).value)
	if not commitCalled or not isSuccess(commitResult) then
		data.faultRequested = true
		return finishAndReturn(data, if commitCalled then commitResult else serviceFailure("INTERNAL_ERROR", "despawn"))
	end
	return finishAndReturn(data, storeResult)
end

function ServiceMethods.requestSnapshot(self: Service, recipient: unknown): unknown
	local data = requireData(self)
	local unavailable = requireFacade(data, "requestSnapshot", true)
	if unavailable ~= nil then
		return unavailable
	end
	local publisher = data.publisher :: PublisherAdapter
	local provider = function(runtimeEnemyIds: { number }?): unknown
		return snapshotProvider(data, runtimeEnemyIds)
	end
	local called, resultValue = callResult(publisher.requestSnapshot, publisher, recipient, provider)
	if not called then
		return finishAndReturn(data, malformedDependencyResult(data, "requestSnapshot"))
	end
	if not isSuccess(resultValue) then
		local errorValue = (resultValue :: any).error
		local code = if type(errorValue) == "table" then (errorValue :: any).code else nil
		if code ~= "INVALID_RECIPIENT" and code ~= "CAPACITY_EXCEEDED" then
			data.faultRequested = true
		end
	end
	return finishAndReturn(data, resultValue)
end

function ServiceMethods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	return requireData(self).serviceDefinition :: ServiceLifecycle.ServiceDefinition
end

function ServiceMethods.getLifecycleState(self: Service): LifecycleState
	return requireData(self).state
end

function ServiceMethods.getMetrics(self: Service): ServiceMetrics
	local data = requireData(self)
	local storeMetrics: unknown? = nil
	if data.store ~= nil then
		local called, value = callNonYielding((data.store :: RuntimeStoreAdapter).getMetrics, data.store)
		if called and type(value) == "table" and table.isfrozen(value :: any) then
			storeMetrics = value
		end
	end
	local timingSamples = table.clone(data.passDurationSamples)
	table.sort(timingSamples)
	local sampleCount = #timingSamples
	local p50Seconds = if sampleCount == 0 then 0 else timingSamples[math.ceil(sampleCount * 0.5)]
	local p95Seconds = if sampleCount == 0 then 0 else timingSamples[math.ceil(sampleCount * 0.95)]
	local passTiming = table.freeze({
		capacity = PASS_DURATION_CAPACITY,
		sampleCount = sampleCount,
		totalSampleCount = data.totalPassDurationCount,
		lastSeconds = data.lastPassDurationSeconds,
		maximumSeconds = data.maximumPassDurationSeconds,
		p50Seconds = p50Seconds,
		p95Seconds = p95Seconds,
	})
	return table.freeze({
		lifecycleState = data.state,
		stepConnectionCount = if data.stepConnection == nil then 0 else 1,
		playerRemovingConnectionCount = if data.playerRemovingConnection == nil then 0 else 1,
		faultDrainActive = data.faultDrainActive,
		retainsStore = data.store ~= nil,
		retainsPublisher = data.publisher ~= nil,
		store = storeMetrics,
		publisher = publisherMetrics(data),
		studioTriggerCount = if data.studioTrigger == nil then 0 else 1,
		studioCatalogInstalled = data.studioCatalogInstalled,
		studioBaseInitialized = data.studioBaseInitialized,
		studioBaseVariant = data.studioBaseVariant,
		studioWaveActivated = data.studioWaveActivated,
		studioSpawnCount = data.studioSpawnCount,
		studioBatchCount = data.studioBatchCount,
		spawnAdmissionClosed = data.spawnAdmissionClosed,
		nextEnemyPassOrdinal = data.nextEnemyPassOrdinal,
		defeatCount = data.defeatCount,
		resultsCommitCount = data.resultsCommitCount,
		passTiming = passTiming,
	})
end

local function construct(
	matchLifecycleValue: unknown,
	baseRuntimeValue: unknown,
	catalog: unknown,
	createStoreValue: unknown,
	createPublisherValue: unknown,
	connectStepValue: unknown,
	connectPlayerRemovingValue: unknown,
	senderValue: unknown,
	getRecipientsValue: unknown,
	isStudioValue: unknown,
	passClockValue: unknown,
	createRuntimeTriggerValue: unknown,
	initialEnemyPassOrdinalValue: unknown
): Service
	if
		not isMatchLifecycleAdapter(matchLifecycleValue)
		or not isBaseRuntimeAdapter(baseRuntimeValue)
		or type(createStoreValue) ~= "function"
		or type(createPublisherValue) ~= "function"
		or type(connectStepValue) ~= "function"
		or type(connectPlayerRemovingValue) ~= "function"
		or type(senderValue) ~= "function"
		or type(getRecipientsValue) ~= "function"
		or type(isStudioValue) ~= "function"
		or type(passClockValue) ~= "function"
		or type(createRuntimeTriggerValue) ~= "function"
		or not (
			initialEnemyPassOrdinalValue == nil
			or (
				type(initialEnemyPassOrdinalValue) == "number"
				and Validation.isSafeInteger(initialEnemyPassOrdinalValue :: number)
				and (initialEnemyPassOrdinalValue :: number) >= 1
			)
		)
	then
		staticError("INVALID_DEPENDENCIES")
	end

	local data: ServiceData = {
		state = "Constructed",
		matchLifecycle = matchLifecycleValue :: MatchLifecycleAdapter,
		baseRuntime = baseRuntimeValue :: BaseRuntimeAdapter,
		catalog = catalog,
		createStore = createStoreValue :: RuntimeStoreFactory,
		createPublisher = createPublisherValue :: PublisherFactory,
		connectStep = connectStepValue :: ConnectStep,
		connectPlayerRemoving = connectPlayerRemovingValue :: ConnectPlayerRemoving,
		sender = senderValue :: EnemySender,
		getRecipients = getRecipientsValue :: GetRecipients,
		isStudio = isStudioValue :: IsStudio,
		passClock = passClockValue :: PassClock,
		createRuntimeTrigger = createRuntimeTriggerValue :: CreateRuntimeTrigger,
		store = nil,
		publisher = nil,
		stepConnection = nil,
		playerRemovingConnection = nil,
		callbacksEnabled = false,
		operationActive = false,
		shutdownRequested = false,
		faultRequested = false,
		faultDrainActive = false,
		releasing = false,
		deferredDisconnectFailed = false,
		studioTrigger = nil,
		studioTriggerOperationActive = false,
		studioCatalogInstalled = false,
		studioLaneId = nil,
		studioDifficultyDefinitions = nil,
		studioBaseInitialized = false,
		studioBaseVariant = nil,
		studioWaveActivated = false,
		studioSpawnCount = 0,
		studioBatchCount = 0,
		spawnAdmissionClosed = false,
		nextEnemyPassOrdinal = if initialEnemyPassOrdinalValue == nil
			then 1
			else initialEnemyPassOrdinalValue :: number,
		defeatCount = 0,
		resultsCommitCount = 0,
		passDurationSamples = {},
		nextPassDurationIndex = 1,
		totalPassDurationCount = 0,
		lastPassDurationSeconds = 0,
		maximumPassDurationSeconds = 0,
		service = nil,
		serviceDefinition = nil,
	}
	local service = setmetatable({}, ServiceMethods) :: Service
	table.freeze(service)
	data.service = service
	data.serviceDefinition = table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({ "NetworkRegistry", "MatchLifecycle", "BaseRuntime" }),
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

local function productionCreateStore(
	matchId: unknown,
	catalog: unknown,
	runtimeMapSnapshot: unknown,
	endpointSink: unknown
): unknown
	return EnemyRuntimeStore.new(matchId, catalog, runtimeMapSnapshot, endpointSink)
end

local function productionCreatePublisher(matchId: unknown, enemyEpoch: unknown, dependencies: unknown): unknown
	return EnemyReplicationPublisher.new(matchId, enemyEpoch, dependencies)
end

local function productionConnectStep(callback: StepCallback): unknown
	return RunService.Heartbeat:Connect(callback)
end

local function productionConnectPlayerRemoving(callback: PlayerRemovingCallback): unknown
	return Players.PlayerRemoving:Connect(callback :: any)
end

local function productionGetRecipients(): unknown
	local records = {}
	for _, player in Players:GetPlayers() do
		table.insert(records, {
			recipient = player,
			userId = player.UserId,
		})
	end
	return records
end

local function productionIsStudio(): unknown
	return RunService:IsStudio()
end

local function productionPassClock(): unknown
	return os.clock()
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

function EnemySimulationService.new(
	matchLifecycle: MatchLifecycleAdapter,
	baseRuntime: BaseRuntimeAdapter,
	catalog: ConfigTypes.EnemyCatalog,
	enemySender: EnemySender
): Service
	return construct(
		matchLifecycle,
		baseRuntime,
		catalog,
		productionCreateStore,
		productionCreatePublisher,
		productionConnectStep,
		productionConnectPlayerRemoving,
		enemySender,
		productionGetRecipients,
		productionIsStudio,
		productionPassClock,
		productionCreateRuntimeTrigger,
		nil
	)
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "EnemySimulationService" then
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
	local support = automatedTests:FindFirstChild("Support")
	return support ~= nil
		and support:IsA("Folder")
		and support:FindFirstChild("TestRunner") ~= nil
		and ServerScriptService:FindFirstChild("Server") == nil
end

if testModuleIdentityIsExact() then
	EnemySimulationService.newForTests = function(dependencies: TestDependencies): Service
		if type(dependencies) ~= "table" or getmetatable(dependencies :: any) ~= nil then
			staticError("INVALID_DEPENDENCIES")
		end
		local allowedFields = {
			matchLifecycle = true,
			baseRuntime = true,
			catalog = true,
			createStore = true,
			createPublisher = true,
			connectStep = true,
			connectPlayerRemoving = true,
			sender = true,
			getRecipients = true,
			isStudio = true,
			passClock = true,
			createRuntimeTrigger = true,
			initialEnemyPassOrdinal = true,
		}
		for key in next, dependencies :: any do
			if type(key) ~= "string" or allowedFields[key] ~= true then
				staticError("INVALID_DEPENDENCIES")
			end
		end
		local dependencyValue = dependencies :: any
		local isStudio = dependencyValue.isStudio
		local passClock = dependencyValue.passClock
		local createRuntimeTrigger = dependencyValue.createRuntimeTrigger
		if isStudio == nil then
			isStudio = function(): unknown
				return false
			end
		end
		if passClock == nil then
			passClock = function(): unknown
				return 0
			end
		end
		if createRuntimeTrigger == nil then
			createRuntimeTrigger = function(_handler: RuntimeTriggerHandler): unknown
				return nil
			end
		end
		return construct(
			dependencyValue.matchLifecycle,
			dependencyValue.baseRuntime,
			dependencyValue.catalog,
			dependencyValue.createStore,
			dependencyValue.createPublisher,
			dependencyValue.connectStep,
			dependencyValue.connectPlayerRemoving,
			dependencyValue.sender,
			dependencyValue.getRecipients,
			isStudio,
			passClock,
			createRuntimeTrigger,
			dependencyValue.initialEnemyPassOrdinal
		)
	end
end

table.freeze(ServiceMethods)
return table.freeze(EnemySimulationService)
