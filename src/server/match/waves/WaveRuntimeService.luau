--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local WaveProtocol = require(ReplicatedStorage.Shared.match.WaveProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)
local WaveReplicationPublisher = require(script.Parent.WaveReplicationPublisher)
local WaveRuntime = require(script.Parent.WaveRuntime)

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
	"getSnapshot"
	| "getStartingCashPlaceholder"
	| "getCompletionState"
	| "query"
	| "submitSkipVote"
	| "onEnemyPass"
	| "flushEnemyPass"
	| "close"
	| "installStudioTowerBoundary"
	| "detachStudioTowerBoundary"
	| "runtimeTrigger"

export type ErrorCode =
	"UNAVAILABLE"
	| "REENTRANT"
	| "INTERNAL_ERROR"
	| "INVALID_ARGUMENT"
	| "STALE_REQUEST"
	| "DUPLICATE_REQUEST"
	| "NOT_AUTHORIZED"
	| "STUDIO_ONLY"
export type ServiceError = {
	code: ErrorCode,
	operation: Operation,
}

export type DormantSelection = {
	kind: "Dormant",
}

export type AuthoredFiniteSelection = {
	kind: "AuthoredFinite",
	difficultyId: Ids.DifficultyId,
}

export type Selection = DormantSelection | AuthoredFiniteSelection

export type MatchLifecycleAdapter = {
	getSnapshot: (self: MatchLifecycleAdapter) -> unknown,
	getRuntimeMapSnapshot: (self: MatchLifecycleAdapter) -> unknown,
	getConnectedRecipients: (self: MatchLifecycleAdapter) -> unknown,
	getCommittedBaseDefeatRecipients: (self: MatchLifecycleAdapter) -> unknown,
	submitReady: ((
		self: MatchLifecycleAdapter,
		connection: unknown,
		matchId: unknown,
		observedRevision: unknown
	) -> unknown)?,
	isRuntimeMapSnapshot: (self: MatchLifecycleAdapter, value: unknown) -> unknown,
	beginWaveActivation: (self: MatchLifecycleAdapter, matchId: unknown) -> unknown,
	commitWaveActivation: (self: MatchLifecycleAdapter, token: unknown) -> unknown,
	rollbackWaveActivation: (self: MatchLifecycleAdapter, token: unknown) -> unknown,
}

export type BaseRuntimeAdapter = {
	installStudioCatalog: (self: BaseRuntimeAdapter, catalog: unknown) -> unknown,
	initializeBase: (self: BaseRuntimeAdapter, definition: unknown) -> unknown,
	getDefeatState: (self: BaseRuntimeAdapter) -> unknown,
	getSnapshot: (self: BaseRuntimeAdapter) -> unknown,
	getMetrics: (self: BaseRuntimeAdapter) -> unknown,
}

export type WaveBoundaryAdapter = {
	onEnemyPass: (self: WaveBoundaryAdapter, frame: unknown) -> unknown,
	flushEnemyPass: (self: WaveBoundaryAdapter, passOrdinal: unknown) -> unknown,
	close: (self: WaveBoundaryAdapter, context: unknown) -> unknown,
}

export type EnemySimulationAdapter = {
	getIdentity: (self: EnemySimulationAdapter) -> unknown,
	installWaveBoundary: (self: EnemySimulationAdapter, adapter: unknown) -> unknown,
	prepareWaveBinding: (
		self: EnemySimulationAdapter,
		handle: unknown,
		configuration: unknown,
		difficulty: unknown
	) -> unknown,
	commitWaveBinding: (self: EnemySimulationAdapter, token: unknown) -> unknown,
	detachWaveBoundary: (self: EnemySimulationAdapter, handle: unknown) -> unknown,
	getWaveBoundaryStatus: (self: EnemySimulationAdapter, handle: unknown) -> unknown,
	isAuthenticatedTerminalOutcome: (self: EnemySimulationAdapter, handle: unknown, outcome: unknown) -> unknown,
	list: (self: EnemySimulationAdapter) -> unknown,
	despawn: (self: EnemySimulationAdapter, runtimeEnemyId: unknown) -> unknown,
	getMetrics: (self: EnemySimulationAdapter) -> unknown,
}

export type RuntimeAdapter = {
	initialize: (self: RuntimeAdapter) -> unknown,
	step: (self: RuntimeAdapter, frame: unknown) -> unknown,
	closeDependencyFault: (self: RuntimeAdapter, context: unknown) -> unknown,
	getSnapshot: (self: RuntimeAdapter) -> unknown,
	getStartingCashPlaceholder: (self: RuntimeAdapter) -> unknown,
	getCompletionState: (self: RuntimeAdapter) -> unknown,
	query: (self: RuntimeAdapter) -> unknown,
	submitSkipVote: (self: RuntimeAdapter, userId: unknown, matchId: unknown, waveNumber: unknown) -> unknown,
	cleanup: (self: RuntimeAdapter) -> unknown,
}

export type RuntimeFactory = (
	configuration: unknown,
	runtimeMap: unknown,
	matchId: unknown,
	enemyEpoch: unknown,
	difficultyId: unknown,
	dependencies: unknown
) -> unknown

export type PublisherAdapter = {
	preflightPublication: (self: PublisherAdapter) -> unknown,
	queueSnapshot: (self: PublisherAdapter, snapshot: unknown) -> unknown,
	flush: (self: PublisherAdapter, passOrdinal: unknown) -> unknown,
	getMetrics: (self: PublisherAdapter) -> unknown,
	cleanup: (self: PublisherAdapter) -> unknown,
}

export type WaveSender = (recipient: Player, snapshot: WaveProtocol.WaveSnapshot) -> boolean

export type PublisherFactory = (
	matchId: unknown,
	enemyEpoch: unknown,
	mapId: unknown,
	difficultyId: unknown,
	totalWaves: unknown,
	dependencies: unknown
) -> unknown

export type Clock = () -> unknown
export type RuntimeTriggerHandler = (...unknown) -> unknown
export type CreateRuntimeTrigger = (handler: RuntimeTriggerHandler) -> unknown
export type IsStudio = () -> unknown
export type ValidateConfiguration = (sources: unknown) -> unknown

export type StudioTowerBoundaryAdapter = {
	buildStudioFixtureSources: (self: StudioTowerBoundaryAdapter) -> unknown,
	prepareStudioConfiguration: (
		self: StudioTowerBoundaryAdapter,
		canonicalRoot: unknown,
		matchId: unknown
	) -> unknown,
	commitStudioConfiguration: (self: StudioTowerBoundaryAdapter, token: unknown) -> unknown,
	dispatchStudioEvidence: (self: StudioTowerBoundaryAdapter, fixedOperation: unknown) -> unknown,
	getStudioDiagnostics: (self: StudioTowerBoundaryAdapter) -> unknown,
	closeFromWave: (self: StudioTowerBoundaryAdapter) -> unknown,
}

export type TestDependencies = {
	matchLifecycle: MatchLifecycleAdapter,
	baseRuntime: BaseRuntimeAdapter,
	enemySimulation: EnemySimulationAdapter,
	configuration: ConfigTypes.CoreConfiguration,
	selection: Selection,
	clock: Clock,
	createRuntime: RuntimeFactory,
	createPublisher: PublisherFactory,
	sender: WaveSender,
	isStudio: IsStudio,
	createRuntimeTrigger: CreateRuntimeTrigger,
	validateConfiguration: ValidateConfiguration,
	durationClock: Clock,
}

export type ServiceMetrics = {
	lifecycleState: LifecycleState,
	dormant: boolean,
	connectionCount: number,
	boundaryCallbackCount: number,
	callbacksEnabled: boolean,
	operationActive: boolean,
	retainsRuntime: boolean,
	retainsPublisher: boolean,
	retainsBoundary: boolean,
	retainsConstructionDependencies: boolean,
	boundaryGeneration: number,
	lastEnemyPassOrdinal: number,
	lastFlushedPassOrdinal: number,
	terminalState: string?,
	runtime: unknown?,
	publisher: unknown?,
	lastQueuedWaveRevision: number,
	studioTriggerCount: number,
	studioActivationAttempted: boolean,
	studioActivated: boolean,
	studioScenario: string?,
	studioValidationCount: number,
	studioOperationCount: number,
	studioAssertionCount: number,
	studioAssertionFailureCount: number,
	studioSchedulerSampleCount: number,
	studioLastSchedulerSeconds: number,
	studioMaximumSchedulerSeconds: number,
	studioMaximumSpawnLatenessSeconds: number,
	studioEarlySpawnCount: number,
	studioSpawnEvidenceCount: number,
	studioTowerBoundaryCount: number,
	studioTowerPreparedTokenCount: number,
	studioTowerBuildCount: number,
	studioTowerPrepareCount: number,
	studioTowerCommitCount: number,
	studioTowerDispatchCount: number,
	studioTowerDiagnosticsCount: number,
	studioTowerCloseCount: number,
}

type BoundaryStatus = {
	matchId: Ids.MatchId,
	enemyEpoch: number,
	generation: number,
	status: "Installed" | "Active" | "DefeatClosed" | "Faulted" | "ShutdownClosed" | "Detached",
	difficultyId: Ids.DifficultyId?,
}

type ServiceData = {
	state: LifecycleState,
	matchLifecycle: MatchLifecycleAdapter?,
	baseRuntime: BaseRuntimeAdapter?,
	enemySimulation: EnemySimulationAdapter?,
	configuration: ConfigTypes.CoreConfiguration?,
	selection: Selection?,
	clock: Clock?,
	createRuntime: RuntimeFactory?,
	createPublisher: PublisherFactory?,
	sender: WaveSender?,
	isStudio: IsStudio?,
	createRuntimeTrigger: CreateRuntimeTrigger?,
	validateConfiguration: ValidateConfiguration?,
	durationClock: Clock?,
	runtime: RuntimeAdapter?,
	publisher: PublisherAdapter?,
	boundaryAdapter: WaveBoundaryAdapter?,
	boundaryHandle: unknown,
	matchId: Ids.MatchId?,
	enemyEpoch: number,
	mapId: Ids.MapId?,
	difficultyId: Ids.DifficultyId?,
	totalWaves: number,
	boundaryGeneration: number,
	callbacksEnabled: boolean,
	operationActive: boolean,
	shutdownRequested: boolean,
	releasing: boolean,
	lastEnemyPassOrdinal: number,
	lastFlushedPassOrdinal: number,
	lastSampleServerTime: number,
	lastQueuedWaveRevision: number,
	terminalPublicationPending: boolean,
	terminalState: string?,
	recoverableFaultSnapshot: WaveProtocol.WaveSnapshot?,
	studioTrigger: unknown?,
	studioTriggerOperationActive: boolean,
	studioActivationAttempted: boolean,
	studioActivated: boolean,
	studioScenario: string?,
	studioValidationCount: number,
	studioOperationCount: number,
	studioAssertionCount: number,
	studioAssertionFailureCount: number,
	studioSchedulerSampleCount: number,
	studioLastSchedulerSeconds: number,
	studioMaximumSchedulerSeconds: number,
	studioMaximumSpawnLatenessSeconds: number,
	studioEarlySpawnCount: number,
	studioBaseCatalogPending: unknown?,
	studioRuntimeMapPending: unknown?,
	studioSpawnEvidence: { unknown },
	studioTowerBoundaryAdapter: StudioTowerBoundaryAdapter?,
	studioTowerBoundaryHandle: unknown,
	studioTowerOwnerToken: unknown,
	studioTowerIssuedHandles: { [any]: boolean },
	studioTowerPreparedToken: unknown,
	studioTowerCallbackActive: boolean,
	studioTowerReentryViolation: boolean,
	studioTowerBuildCount: number,
	studioTowerPrepareCount: number,
	studioTowerCommitCount: number,
	studioTowerDispatchCount: number,
	studioTowerDiagnosticsCount: number,
	studioTowerCloseCount: number,
	service: any?,
	serviceDefinition: ServiceLifecycle.ServiceDefinition?,
}

local SERVICE_NAME = "WaveRuntime"
local STATIC_ERROR_PREFIX = "[ATD_WAVE_RUNTIME_SERVICE]"
local STUDIO_TRIGGER_NAME = "_ATDPhase11WaveEvidence"
local STUDIO_DIFFICULTY_ID = "difficulty:phase11-studio"
local STUDIO_ENEMY_ID = "enemy:phase11-studio"
local STUDIO_DEFEAT_ENEMY_ID = "enemy:phase11-studio-defeat"
local STUDIO_ENEMY_MODEL_ASSET_KEY = "test.phase11.studio.enemy-model"
local STUDIO_MAP_MODEL_ASSET_KEY = "test.phase11.studio.map-model"
local MAX_STUDIO_LANES = 32
local MAX_STUDIO_OPERATIONS = 10_000
local MAX_STUDIO_ASSERTIONS = 10_000
local MAX_STUDIO_TOWER_DIAGNOSTIC_NODES = 256
local MAX_STUDIO_TOWER_DIAGNOSTIC_DEPTH = 6
local MAX_STUDIO_TOWER_DIAGNOSTIC_STRING = 256
local MAX_STUDIO_TOWER_CFRAME_POSITION = 100_000
local MAX_STUDIO_TOWER_FIXTURE_NODES = 512
local MAX_STUDIO_TOWER_FIXTURE_DEPTH = 10
local MAX_STUDIO_TOWER_RECORD_FIELDS = 32
local STUDIO_SCENARIOS = table.freeze({
	Primary = true,
	Empty = true,
	Deadline = true,
	Overlap = true,
	Skip = true,
	Ladder1 = true,
	Ladder32 = true,
	Ladder64 = true,
	Ladder128 = true,
	Defeat = true,
})

local STUDIO_ACTIVATE_FIELDS = table.freeze({
	operation = true,
	scenario = true,
})

local STUDIO_DIAGNOSTICS_FIELDS = table.freeze({
	operation = true,
})

local STUDIO_RESOLVE_FIELDS = table.freeze({
	operation = true,
	reason = true,
})

local STUDIO_SKIP_FIELDS = table.freeze({
	operation = true,
	userId = true,
	waveNumber = true,
})

local STUDIO_ASSERTION_FIELDS = table.freeze({
	operation = true,
	passed = true,
})

local STUDIO_TOWER_REQUEST_FIELDS = table.freeze({
	operation = true,
})

local STUDIO_TOWER_OPERATIONS: { [string]: boolean } = table.freeze({
	TowerCreateNext = true,
	TowerRemoveVisualLast = true,
	TowerRecreateVisualLast = true,
	TowerRemoveLast = true,
	TowerInvalidTemplate = true,
	TowerCleanup = true,
})

local STUDIO_TOWER_BOUNDARY_METHODS: { [string]: boolean } = table.freeze({
	buildStudioFixtureSources = true,
	prepareStudioConfiguration = true,
	commitStudioConfiguration = true,
	dispatchStudioEvidence = true,
	getStudioDiagnostics = true,
	closeFromWave = true,
})

local STUDIO_TOWER_FIXTURE_FIELDS: { [string]: boolean } = table.freeze({
	assets = true,
	towers = true,
})

local STUDIO_TOWER_ASSET_FIELDS: { [string]: boolean } = table.freeze({
	key = true,
	kind = true,
})

local STUDIO_TOWER_DEFINITION_FIELDS: { [string]: boolean } = table.freeze({
	id = true,
	displayName = true,
	description = true,
	modelAssetKey = true,
	iconAssetKey = true,
	placementCost = true,
	footprintRadiusStuds = true,
	placementCap = true,
	supportedTargetModes = true,
	defaultTargetMode = true,
	levels = true,
	tags = true,
	mergeProgression = true,
})

local EXPECTED_STUDIO_TOWER_IDS = table.freeze({
	"tower:phase12-single",
	"tower:phase12-splash",
	"tower:phase12-support",
})

local LIFECYCLE_METHODS = table.freeze({
	"getSnapshot",
	"getRuntimeMapSnapshot",
	"getConnectedRecipients",
	"getCommittedBaseDefeatRecipients",
	"isRuntimeMapSnapshot",
	"beginWaveActivation",
	"commitWaveActivation",
	"rollbackWaveActivation",
})

local BASE_METHODS = table.freeze({
	"installStudioCatalog",
	"initializeBase",
	"getDefeatState",
	"getSnapshot",
	"getMetrics",
})

local ENEMY_METHODS = table.freeze({
	"getIdentity",
	"installWaveBoundary",
	"prepareWaveBinding",
	"commitWaveBinding",
	"detachWaveBoundary",
	"getWaveBoundaryStatus",
	"isAuthenticatedTerminalOutcome",
	"list",
	"despawn",
	"getMetrics",
})

local RUNTIME_METHODS = table.freeze({
	"initialize",
	"step",
	"closeDependencyFault",
	"getSnapshot",
	"getStartingCashPlaceholder",
	"getCompletionState",
	"query",
	"submitSkipVote",
	"cleanup",
})

local PUBLISHER_METHODS = table.freeze({
	"preflightPublication",
	"queueSnapshot",
	"flush",
	"getMetrics",
	"cleanup",
})

local TEST_DEPENDENCY_FIELDS: { [string]: boolean } = table.freeze({
	matchLifecycle = true,
	baseRuntime = true,
	enemySimulation = true,
	configuration = true,
	selection = true,
	clock = true,
	createRuntime = true,
	createPublisher = true,
	sender = true,
	isStudio = true,
	createRuntimeTrigger = true,
	validateConfiguration = true,
	durationClock = true,
})

local DORMANT_SELECTION_FIELDS = table.freeze({
	kind = true,
})

local AUTHORED_SELECTION_FIELDS = table.freeze({
	kind = true,
	difficultyId = true,
})

local HEALTHY_FRAME_FIELDS = table.freeze({
	disposition = true,
	matchId = true,
	enemyEpoch = true,
	passOrdinal = true,
	sampleServerTime = true,
	terminalOutcomes = true,
	spawn = true,
})

local CLOSED_FRAME_FIELDS = table.freeze({
	disposition = true,
	matchId = true,
	enemyEpoch = true,
	passOrdinal = true,
	sampleServerTime = true,
	terminalOutcomes = true,
})

local CLOSE_CONTEXT_FIELDS = table.freeze({
	disposition = true,
	matchId = true,
	enemyEpoch = true,
	passOrdinal = true,
	sampleServerTime = true,
})

local CLOSE_CONTEXT_WITH_SPAWN_FIELDS = table.freeze({
	disposition = true,
	matchId = true,
	enemyEpoch = true,
	passOrdinal = true,
	sampleServerTime = true,
	committedSpawn = true,
	terminalOutcome = true,
})

local ENEMY_IDENTITY_FIELDS = table.freeze({
	matchId = true,
	enemyEpoch = true,
})

local CONNECTED_RECIPIENT_FIELDS = table.freeze({
	recipient = true,
	userId = true,
})

local RESULT_FAILURE_FIELDS = table.freeze({
	ok = true,
	error = true,
})

local RUNTIME_ERROR_FIELDS = table.freeze({
	code = true,
	operation = true,
})

local PUBLIC_VOTE_FAILURE_CODES = table.freeze({
	STALE_REQUEST = true,
	DUPLICATE_REQUEST = true,
	NOT_AUTHORIZED = true,
	UNAVAILABLE = true,
})

local ServiceMethods = {}
ServiceMethods.__index = ServiceMethods

export type Service = typeof(setmetatable({} :: {}, ServiceMethods))
export type TestConstructor = (dependencies: TestDependencies) -> Service

local SERVICE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local STUDIO_TOWER_HANDLE_OWNERS = setmetatable({}, { __mode = "k" }) :: { [any]: unknown }
local STUDIO_TOWER_ACTIVE_HANDLES = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }

local WaveRuntimeService = {
	STUDIO_TRIGGER_NAME = STUDIO_TRIGGER_NAME,
	newForTests = nil :: TestConstructor?,
}

local STUDIO_TOWER_DETACH_TRUE = Result.ok(true)
local STUDIO_TOWER_DETACH_FALSE = Result.ok(false)

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

local function hasExactFields(value: { [any]: unknown }, fields: { [string]: boolean }): boolean
	local count = 0
	for fieldName in next, value do
		count += 1
		if type(fieldName) ~= "string" or fields[fieldName] ~= true then
			return false
		end
	end
	local expectedCount = 0
	for _ in fields do
		expectedCount += 1
	end
	return count == expectedCount
end

local function hasMethods(value: unknown, methods: { string }): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, methodName in methods do
		if type((value :: any)[methodName]) ~= "function" then
			return false
		end
	end
	return true
end

local function isExactStudioTowerBoundaryAdapter(value: unknown): boolean
	if
		type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
		or not hasExactFields(value :: any, STUDIO_TOWER_BOUNDARY_METHODS)
	then
		return false
	end
	for methodName in STUDIO_TOWER_BOUNDARY_METHODS do
		if type((value :: any)[methodName]) ~= "function" then
			return false
		end
	end
	return true
end

local function isExactSuccessResult(value: unknown): boolean
	return type(value) == "table"
		and getmetatable(value :: any) == nil
		and table.isfrozen(value :: any)
		and (value :: any).ok == true
		and hasExactFields(value :: any, { ok = true, value = true })
end

local function callStudioTower(data: ServiceData, callback: (...any) -> any, ...: any): (boolean, unknown)
	if data.studioTowerCallbackActive then
		data.studioTowerReentryViolation = true
		return false, nil
	end
	data.studioTowerCallbackActive = true
	data.studioTowerReentryViolation = false
	local called, value = callNonYielding(callback, ...)
	data.studioTowerCallbackActive = false
	if data.studioTowerReentryViolation then
		return false, nil
	end
	return called, value
end

local function denseFrozenArray(value: unknown, exactLength: number): boolean
	if
		type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
		or #value ~= exactLength
	then
		return false
	end
	local count = 0
	for key in next, value :: any do
		count += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > exactLength then
			return false
		end
	end
	return count == exactLength
end

type FrozenTreeBudget = {
	nodes: number,
	maximumNodes: number,
	maximumDepth: number,
	seen: { [any]: boolean },
}

local function copyFrozenTree(
	value: unknown,
	budget: FrozenTreeBudget,
	depth: number,
	freezeOutput: boolean
): (unknown, boolean)
	local valueType = type(value)
	if typeof(value) == "CFrame" then
		if not freezeOutput or depth > budget.maximumDepth then
			return nil, false
		end
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = (value :: CFrame):GetComponents()
		local components = { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
		for _, component in components do
			if not Validation.isFiniteNumber(component) or math.abs(component) > Validation.MAX_SAFE_INTEGER then
				return nil, false
			end
		end
		if
			math.abs(x) > MAX_STUDIO_TOWER_CFRAME_POSITION
			or math.abs(y) > MAX_STUDIO_TOWER_CFRAME_POSITION
			or math.abs(z) > MAX_STUDIO_TOWER_CFRAME_POSITION
		then
			return nil, false
		end
		budget.nodes += 1
		if budget.nodes > budget.maximumNodes then
			return nil, false
		end
		return table.freeze({
			x = x,
			y = y,
			z = z,
			r00 = r00,
			r01 = r01,
			r02 = r02,
			r10 = r10,
			r11 = r11,
			r12 = r12,
			r20 = r20,
			r21 = r21,
			r22 = r22,
		}),
			true
	end
	if valueType == "nil" or valueType == "boolean" then
		return value, true
	elseif valueType == "number" then
		local numberValue = value :: number
		return value,
			numberValue == numberValue and numberValue > -math.huge and numberValue < math.huge and math.abs(
				numberValue
			) <= Validation.MAX_SAFE_INTEGER
	elseif valueType == "string" then
		return value, #(value :: string) <= MAX_STUDIO_TOWER_DIAGNOSTIC_STRING
	elseif valueType ~= "table" or depth > budget.maximumDepth then
		return nil, false
	end
	local source = value :: { [any]: unknown }
	if getmetatable(source) ~= nil or not table.isfrozen(source) or budget.seen[source] then
		return nil, false
	end
	budget.seen[source] = true
	budget.nodes += 1
	if budget.nodes > budget.maximumNodes then
		return nil, false
	end

	local entryCount = 0
	local numericCount = 0
	local stringCount = 0
	for key in next, source do
		entryCount += 1
		if entryCount > MAX_STUDIO_TOWER_RECORD_FIELDS then
			return nil, false
		elseif type(key) == "number" then
			if not Validation.isSafeInteger(key) or key < 1 then
				return nil, false
			end
			numericCount += 1
		elseif type(key) == "string" then
			if #key < 1 or #key > 64 or string.match(key, "^[A-Za-z][A-Za-z0-9]*$") == nil then
				return nil, false
			end
			stringCount += 1
		else
			return nil, false
		end
	end
	if numericCount > 0 and stringCount > 0 then
		return nil, false
	elseif numericCount > 0 and (#source ~= numericCount or entryCount ~= numericCount) then
		return nil, false
	end

	local copy: { [any]: unknown } = table.create(if numericCount > 0 then numericCount else 0)
	for key, child in source do
		local childCopy, copied = copyFrozenTree(child, budget, depth + 1, freezeOutput)
		if not copied then
			return nil, false
		end
		copy[key] = childCopy
	end
	if freezeOutput then
		table.freeze(copy)
	end
	return copy, true
end

local function detachedStudioTowerResult(value: unknown): unknown?
	if
		type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
		or type((value :: any).ok) ~= "boolean"
	then
		return nil
	end
	local succeeded = (value :: any).ok == true
	local payloadField = if succeeded then "value" else "error"
	if
		not hasExactFields(value :: any, if succeeded then { ok = true, value = true } else { ok = true, error = true })
	then
		return nil
	end
	local budget: FrozenTreeBudget = {
		nodes = 0,
		maximumNodes = MAX_STUDIO_TOWER_DIAGNOSTIC_NODES,
		maximumDepth = MAX_STUDIO_TOWER_DIAGNOSTIC_DEPTH,
		seen = {},
	}
	local detached, copied = copyFrozenTree((value :: any)[payloadField], budget, 0, true)
	if not copied then
		return nil
	end
	return if succeeded then Result.ok(detached) else Result.err(detached)
end

local function validateAndCopyStudioTowerFixtures(value: unknown): { [string]: any }?
	if
		type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
		or not hasExactFields(value :: any, STUDIO_TOWER_FIXTURE_FIELDS)
		or not denseFrozenArray((value :: any).assets, 6)
		or not denseFrozenArray((value :: any).towers, 3)
	then
		return nil
	end

	local assetsByKey: { [string]: string } = {}
	local towerModelCount = 0
	local iconCount = 0
	for _, record in (value :: any).assets do
		if
			type(record) ~= "table"
			or getmetatable(record) ~= nil
			or not table.isfrozen(record)
			or not hasExactFields(record, STUDIO_TOWER_ASSET_FIELDS)
			or type(record.key) ~= "string"
			or not Validation.isSymbolicKey(record.key)
			or assetsByKey[record.key] ~= nil
			or (record.kind ~= "TowerModel" and record.kind ~= "Icon")
		then
			return nil
		end
		assetsByKey[record.key] = record.kind
		if record.kind == "TowerModel" then
			towerModelCount += 1
		else
			iconCount += 1
		end
	end
	if towerModelCount ~= 3 or iconCount ~= 3 then
		return nil
	end

	local usedAssets: { [string]: boolean } = {}
	for index, definition in (value :: any).towers do
		if type(definition) ~= "table" or getmetatable(definition) ~= nil or not table.isfrozen(definition) then
			return nil
		end
		local fieldCount = 0
		for fieldName in next, definition do
			fieldCount += 1
			if type(fieldName) ~= "string" or STUDIO_TOWER_DEFINITION_FIELDS[fieldName] ~= true then
				return nil
			end
		end
		local expectsDefaultTargetMode = index ~= 3
		for fieldName in STUDIO_TOWER_DEFINITION_FIELDS do
			local required = fieldName ~= "defaultTargetMode" or expectsDefaultTargetMode
			if (rawget(definition, fieldName) ~= nil) ~= required then
				return nil
			end
		end
		if
			fieldCount ~= (if expectsDefaultTargetMode then 13 else 12)
			or definition.id ~= EXPECTED_STUDIO_TOWER_IDS[index]
			or not Ids.validateTowerId(definition.id).ok
			or type(definition.modelAssetKey) ~= "string"
			or assetsByKey[definition.modelAssetKey] ~= "TowerModel"
			or type(definition.iconAssetKey) ~= "string"
			or assetsByKey[definition.iconAssetKey] ~= "Icon"
			or usedAssets[definition.modelAssetKey]
			or usedAssets[definition.iconAssetKey]
			or not denseFrozenArray(definition.levels, 3)
		then
			return nil
		end
		usedAssets[definition.modelAssetKey] = true
		usedAssets[definition.iconAssetKey] = true
	end

	local budget: FrozenTreeBudget = {
		nodes = 0,
		maximumNodes = MAX_STUDIO_TOWER_FIXTURE_NODES,
		maximumDepth = MAX_STUDIO_TOWER_FIXTURE_DEPTH,
		seen = {},
	}
	local copied, success = copyFrozenTree(value, budget, 0, false)
	return if success then copied :: { [string]: any } else nil
end

local function isRuntimeTriggerAdapter(value: unknown): boolean
	return (typeof(value) == "Instance" and (value :: Instance):IsA("BindableFunction"))
		or (type(value) == "table" and type((value :: any).Destroy) == "function")
end

local function isSelection(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return false
	end
	local selection = value :: any
	if selection.kind == "Dormant" then
		return hasExactFields(selection, DORMANT_SELECTION_FIELDS)
	elseif selection.kind == "AuthoredFinite" then
		return hasExactFields(selection, AUTHORED_SELECTION_FIELDS)
			and Ids.validateDifficultyId(selection.difficultyId).ok
	end
	return false
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isUserId(value: unknown): boolean
	return type(value) == "number" and value ~= 0 and Validation.isSafeInteger(value :: number)
end

local function validRuntimeVoteFailure(value: unknown): boolean
	if
		type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
		or not hasExactFields(value :: any, RESULT_FAILURE_FIELDS)
		or (value :: any).ok ~= false
	then
		return false
	end
	local errorValue = (value :: any).error
	return type(errorValue) == "table"
		and getmetatable(errorValue :: any) == nil
		and table.isfrozen(errorValue :: any)
		and hasExactFields(errorValue :: any, RUNTIME_ERROR_FIELDS)
		and type(errorValue.code) == "string"
		and PUBLIC_VOTE_FAILURE_CODES[errorValue.code] == true
		and errorValue.operation == "submitSkipVote"
end

local function canonicalRuntimeSnapshot(value: unknown, data: ServiceData): WaveProtocol.WaveSnapshot?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return nil
	end
	local snapshotResult = WaveProtocol.validateWaveSnapshot(value)
	if not snapshotResult.ok then
		return nil
	end
	local snapshot = snapshotResult.value
	if
		snapshot.matchId ~= data.matchId
		or snapshot.enemyEpoch ~= data.enemyEpoch
		or snapshot.difficultyId ~= data.difficultyId
		or (data.mapId ~= nil and snapshot.mapId ~= data.mapId)
		or (data.totalWaves ~= 0 and snapshot.totalWaves ~= data.totalWaves)
	then
		return nil
	end
	return snapshot
end

local function waveCountsEqual(left: WaveProtocol.WaveCounts, right: WaveProtocol.WaveCounts): boolean
	return left.totalScheduled == right.totalScheduled
		and left.pending == right.pending
		and left.spawned == right.spawned
		and left.alive == right.alive
		and left.leaked == right.leaked
		and left.otherwiseResolved == right.otherwiseResolved
end

local function waveSnapshotsEqual(left: WaveProtocol.WaveSnapshot, right: WaveProtocol.WaveSnapshot): boolean
	return left.matchId == right.matchId
		and left.enemyEpoch == right.enemyEpoch
		and left.mapId == right.mapId
		and left.difficultyId == right.difficultyId
		and left.state == right.state
		and left.waveRevision == right.waveRevision
		and left.currentWaveNumber == right.currentWaveNumber
		and left.totalWaves == right.totalWaves
		and left.currentWaveId == right.currentWaveId
		and left.bossKind == right.bossKind
		and left.timerPhase == right.timerPhase
		and left.waveStartedServerTime == right.waveStartedServerTime
		and left.deadlineServerTime == right.deadlineServerTime
		and left.intermissionEndsServerTime == right.intermissionEndsServerTime
		and left.skipAvailableServerTime == right.skipAvailableServerTime
		and left.finiteCompleteServerTime == right.finiteCompleteServerTime
		and waveCountsEqual(left.currentCounts, right.currentCounts)
		and waveCountsEqual(left.aggregateCounts, right.aggregateCounts)
		and left.skipState.available == right.skipState.available
		and left.skipState.activeParticipantCount == right.skipState.activeParticipantCount
		and left.skipState.yesVoteCount == right.skipState.yesVoteCount
		and left.skipState.requiredVoteCount == right.skipState.requiredVoteCount
		and left.skipState.quorumPending == right.skipState.quorumPending
end

local function parseBoundaryStatus(value: unknown, data: ServiceData, expectedStatus: string): BoundaryStatus?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return nil
	end
	local status = value :: any
	local expectedFields = if expectedStatus == "Installed"
		then {
			matchId = true,
			enemyEpoch = true,
			generation = true,
			status = true,
		}
		else {
			matchId = true,
			enemyEpoch = true,
			generation = true,
			status = true,
			difficultyId = true,
		}
	if
		not hasExactFields(status, expectedFields)
		or status.matchId ~= data.matchId
		or status.enemyEpoch ~= data.enemyEpoch
		or status.status ~= expectedStatus
		or type(status.generation) ~= "number"
		or not Validation.isSafeInteger(status.generation)
		or status.generation < 1
		or (expectedStatus ~= "Installed" and status.difficultyId ~= data.difficultyId)
	then
		return nil
	end
	return status :: BoundaryStatus
end

local function cleanupRuntime(data: ServiceData): boolean
	local runtime = data.runtime
	data.runtime = nil
	if runtime == nil then
		return true
	end
	local called, cleanupResult = callResult(runtime.cleanup, runtime)
	return called and isSuccess(cleanupResult) and (cleanupResult :: any).value == true
end

local function cleanupPublisher(data: ServiceData): boolean
	local publisher = data.publisher
	data.publisher = nil
	if publisher == nil then
		return true
	end
	local called, cleanupResult = callResult(publisher.cleanup, publisher)
	return called and isSuccess(cleanupResult) and (cleanupResult :: any).value == true
end

local function detachBoundary(data: ServiceData): boolean
	local enemySimulation = data.enemySimulation
	local handle = data.boundaryHandle
	data.boundaryHandle = nil
	data.boundaryAdapter = nil
	data.boundaryGeneration = 0
	if enemySimulation == nil or handle == nil then
		return true
	end
	local called, detachResult = callResult(enemySimulation.detachWaveBoundary, enemySimulation, handle)
	return called and isSuccess(detachResult) and (detachResult :: any).value == true
end

local function invalidateStudioTowerBoundary(data: ServiceData)
	local handle = data.studioTowerBoundaryHandle
	data.studioTowerBoundaryAdapter = nil
	data.studioTowerBoundaryHandle = nil
	data.studioTowerPreparedToken = nil
	data.studioTowerCallbackActive = false
	data.studioTowerReentryViolation = false
	if handle ~= nil then
		STUDIO_TOWER_ACTIVE_HANDLES[handle] = nil
	end
end

local function revokeStudioTowerHandles(data: ServiceData)
	for handle in data.studioTowerIssuedHandles do
		STUDIO_TOWER_ACTIVE_HANDLES[handle] = nil
		STUDIO_TOWER_HANDLE_OWNERS[handle] = nil
	end
	table.clear(data.studioTowerIssuedHandles)
end

local function closeStudioTowerBoundary(data: ServiceData): boolean
	local adapter = data.studioTowerBoundaryAdapter
	if adapter == nil then
		invalidateStudioTowerBoundary(data)
		revokeStudioTowerHandles(data)
		return true
	end
	data.studioTowerCloseCount = math.min(data.studioTowerCloseCount + 1, Validation.MAX_SAFE_INTEGER)
	local called, resultValue = callStudioTower(data, adapter.closeFromWave, adapter)
	local accepted = called and isExactSuccessResult(resultValue) and type((resultValue :: any).value) == "boolean"
	invalidateStudioTowerBoundary(data)
	revokeStudioTowerHandles(data)
	return accepted
end

local function clearConstructionDependencies(data: ServiceData)
	data.matchLifecycle = nil
	data.baseRuntime = nil
	data.enemySimulation = nil
	data.configuration = nil
	data.selection = nil
	data.clock = nil
	data.createRuntime = nil
	data.createPublisher = nil
	data.sender = nil
	data.isStudio = nil
	data.createRuntimeTrigger = nil
	data.validateConfiguration = nil
	data.durationClock = nil
	data.matchId = nil
	data.enemyEpoch = 0
	data.mapId = nil
	data.difficultyId = nil
	data.totalWaves = 0
	data.lastQueuedWaveRevision = 0
	data.terminalPublicationPending = false
	data.recoverableFaultSnapshot = nil
	data.studioBaseCatalogPending = nil
	data.studioRuntimeMapPending = nil
	data.studioTowerBoundaryAdapter = nil
	data.studioTowerBoundaryHandle = nil
	revokeStudioTowerHandles(data)
	data.studioTowerOwnerToken = nil
	data.studioTowerPreparedToken = nil
	data.studioTowerCallbackActive = false
	data.studioTowerReentryViolation = false
end

local function destroyStudioTrigger(data: ServiceData): boolean
	local trigger = data.studioTrigger
	data.studioTrigger = nil
	data.studioTriggerOperationActive = false
	data.studioActivationAttempted = false
	data.studioActivated = false
	data.studioScenario = nil
	data.studioValidationCount = 0
	data.studioOperationCount = 0
	data.studioAssertionCount = 0
	data.studioAssertionFailureCount = 0
	data.studioSchedulerSampleCount = 0
	data.studioLastSchedulerSeconds = 0
	data.studioMaximumSchedulerSeconds = 0
	data.studioMaximumSpawnLatenessSeconds = 0
	data.studioEarlySpawnCount = 0
	data.studioBaseCatalogPending = nil
	data.studioRuntimeMapPending = nil
	data.studioTowerBuildCount = 0
	data.studioTowerPrepareCount = 0
	data.studioTowerCommitCount = 0
	data.studioTowerDispatchCount = 0
	data.studioTowerDiagnosticsCount = 0
	data.studioTowerCloseCount = 0
	table.clear(data.studioSpawnEvidence)
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

local function releaseOwnedResources(data: ServiceData): boolean
	if data.releasing then
		return true
	end
	data.releasing = true
	data.callbacksEnabled = false
	data.shutdownRequested = false
	data.operationActive = false
	data.terminalState = "Cleaned"
	local towerClosed = closeStudioTowerBoundary(data)
	local triggerDestroyed = destroyStudioTrigger(data)
	local boundaryDetached = detachBoundary(data)
	local publisherCleaned = cleanupPublisher(data)
	local runtimeCleaned = cleanupRuntime(data)
	clearConstructionDependencies(data)
	data.releasing = false
	return towerClosed and triggerDestroyed and boundaryDetached and publisherCleaned and runtimeCleaned
end

local function releaseAfterEnemyBoundaryClose(data: ServiceData): boolean
	if data.releasing then
		return true
	end
	data.releasing = true
	data.callbacksEnabled = false
	data.shutdownRequested = false
	data.operationActive = false
	data.terminalState = "Cleaned"
	data.boundaryHandle = nil
	data.boundaryAdapter = nil
	data.boundaryGeneration = 0
	local towerClosed = closeStudioTowerBoundary(data)
	local triggerDestroyed = destroyStudioTrigger(data)
	local publisherCleaned = cleanupPublisher(data)
	local runtimeCleaned = cleanupRuntime(data)
	clearConstructionDependencies(data)
	data.releasing = false
	return towerClosed and triggerDestroyed and publisherCleaned and runtimeCleaned
end

local function failInitialize(data: ServiceData, code: string): never
	data.state = "Failed"
	releaseOwnedResources(data)
	staticError(code)
end

local function boundaryFailure(data: ServiceData, operation: Operation): Result.Failure<ServiceError>
	data.callbacksEnabled = false
	data.terminalState = "Faulted"
	data.state = "Failed"
	return serviceFailure("INTERNAL_ERROR", operation)
end

local function validBoundaryFrame(data: ServiceData, value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return false
	end
	local frame = value :: any
	local healthy = frame.disposition == "Healthy"
	local terminalNoOp = data.terminalState == "FiniteComplete"
		or data.terminalState == "DefeatClosed"
		or data.terminalState == "Faulted"
	local hasSpawn = rawget(frame, "spawn") ~= nil
	if
		(
			not healthy
			and frame.disposition ~= "DefeatCommitted"
			and frame.disposition ~= "DependencyFault"
			and frame.disposition ~= "Shutdown"
		)
		or not hasExactFields(frame, if hasSpawn then HEALTHY_FRAME_FIELDS else CLOSED_FRAME_FIELDS)
		or frame.matchId ~= data.matchId
		or frame.enemyEpoch ~= data.enemyEpoch
		or type(frame.passOrdinal) ~= "number"
		or not Validation.isSafeInteger(frame.passOrdinal)
		or ((data.lastEnemyPassOrdinal == 0 and frame.passOrdinal < 1) or (data.lastEnemyPassOrdinal > 0 and frame.passOrdinal ~= data.lastEnemyPassOrdinal + 1))
		or not isFiniteNumber(frame.sampleServerTime)
		or frame.sampleServerTime < data.lastSampleServerTime
		or type(frame.terminalOutcomes) ~= "table"
		or getmetatable(frame.terminalOutcomes) ~= nil
		or not table.isfrozen(frame.terminalOutcomes)
		or (not healthy and hasSpawn)
		or (healthy and not terminalNoOp and not hasSpawn)
		or (hasSpawn and type(frame.spawn) ~= "function")
	then
		return false
	end
	return true
end

local function validCloseContext(data: ServiceData, value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return false
	end
	local context = value :: any
	local hasCommittedSpawn = context.committedSpawn ~= nil
	local hasTerminalOutcome = context.terminalOutcome ~= nil
	if hasCommittedSpawn ~= hasTerminalOutcome then
		return false
	end
	local fields = if hasCommittedSpawn then CLOSE_CONTEXT_WITH_SPAWN_FIELDS else CLOSE_CONTEXT_FIELDS
	return hasExactFields(context, fields)
		and (context.disposition == "DependencyFault" or context.disposition == "Shutdown")
		and context.matchId == data.matchId
		and context.enemyEpoch == data.enemyEpoch
		and type(context.passOrdinal) == "number"
		and Validation.isSafeInteger(context.passOrdinal)
		and context.passOrdinal >= data.lastEnemyPassOrdinal
		and isFiniteNumber(context.sampleServerTime)
		and context.sampleServerTime >= data.lastSampleServerTime
end

local function readBoundaryStatus(data: ServiceData, expectedStatus: string): BoundaryStatus?
	local enemySimulation = data.enemySimulation
	local handle = data.boundaryHandle
	if enemySimulation == nil or handle == nil then
		return nil
	end
	local called, statusResult = callResult(enemySimulation.getWaveBoundaryStatus, enemySimulation, handle)
	if not called or not isSuccess(statusResult) then
		return nil
	end
	return parseBoundaryStatus((statusResult :: any).value, data, expectedStatus)
end

local function runtimeDependencies(data: ServiceData): WaveRuntime.Dependencies
	local matchLifecycle = data.matchLifecycle :: MatchLifecycleAdapter
	local baseRuntime = data.baseRuntime :: BaseRuntimeAdapter
	local enemySimulation = data.enemySimulation :: EnemySimulationAdapter
	local clock = data.clock :: Clock
	return table.freeze({
		clock = function(): unknown
			local called, value = callNonYielding(clock)
			return if called then value else nil
		end,
		isRuntimeMapSnapshot = function(value: unknown): unknown
			local called, accepted = callNonYielding(matchLifecycle.isRuntimeMapSnapshot, matchLifecycle, value)
			return called and accepted == true
		end,
		initializeBase = function(difficulty: ConfigTypes.FiniteDifficultyDefinition): unknown
			local pendingCatalog = data.studioBaseCatalogPending
			if pendingCatalog ~= nil then
				local installed, installResult =
					callResult(baseRuntime.installStudioCatalog, baseRuntime, pendingCatalog)
				if not installed or not isSuccess(installResult) or (installResult :: any).value ~= true then
					return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
				end
				data.studioBaseCatalogPending = nil
			end
			local called, resultValue = callResult(baseRuntime.initializeBase, baseRuntime, difficulty)
			return if called then resultValue else serviceFailure("INTERNAL_ERROR", "query")
		end,
		bindDifficulty = function(
			configuration: ConfigTypes.CoreConfiguration,
			difficulty: ConfigTypes.FiniteDifficultyDefinition
		): unknown
			local handle = data.boundaryHandle
			if handle == nil then
				return serviceFailure("INTERNAL_ERROR", "query")
			end
			local prepared, prepareResult =
				callResult(enemySimulation.prepareWaveBinding, enemySimulation, handle, configuration, difficulty)
			if not prepared or not isSuccess(prepareResult) then
				return serviceFailure("INTERNAL_ERROR", "query")
			end
			local committed, commitResult =
				callResult(enemySimulation.commitWaveBinding, enemySimulation, (prepareResult :: any).value)
			if not committed or not isSuccess(commitResult) then
				return serviceFailure("INTERNAL_ERROR", "query")
			end
			local status = parseBoundaryStatus((commitResult :: any).value, data, "Active")
			if status == nil or status.generation ~= data.boundaryGeneration then
				return serviceFailure("INTERNAL_ERROR", "query")
			end
			return Result.ok(true)
		end,
		beginWaveActivation = function(matchId: Ids.MatchId): unknown
			local called, resultValue = callResult(matchLifecycle.beginWaveActivation, matchLifecycle, matchId)
			if not called then
				return serviceFailure("INTERNAL_ERROR", "query")
			end
			if not isSuccess(resultValue) then
				return resultValue
			end
			local towerToken = data.studioTowerPreparedToken
			if towerToken ~= nil then
				local towerAdapter = data.studioTowerBoundaryAdapter
				local towerHandle = data.studioTowerBoundaryHandle
				data.studioTowerPreparedToken = nil
				local towerCommitted = false
				local towerCommitResult: unknown = nil
				if towerAdapter ~= nil and towerHandle ~= nil and STUDIO_TOWER_ACTIVE_HANDLES[towerHandle] == true then
					towerCommitted, towerCommitResult =
						callStudioTower(data, towerAdapter.commitStudioConfiguration, towerAdapter, towerToken)
				end
				if
					not towerCommitted
					or not isExactSuccessResult(towerCommitResult)
					or (towerCommitResult :: any).value ~= true
				then
					callResult(matchLifecycle.rollbackWaveActivation, matchLifecycle, (resultValue :: any).value)
					return serviceFailure("INTERNAL_ERROR", "query")
				end
				data.studioTowerCommitCount = math.min(data.studioTowerCommitCount + 1, Validation.MAX_SAFE_INTEGER)
			end
			return resultValue
		end,
		commitWaveActivation = function(token: unknown): unknown
			local called, resultValue = callResult(matchLifecycle.commitWaveActivation, matchLifecycle, token)
			return if called then resultValue else serviceFailure("INTERNAL_ERROR", "query")
		end,
		rollbackWaveActivation = function(token: unknown): unknown
			local called, resultValue = callResult(matchLifecycle.rollbackWaveActivation, matchLifecycle, token)
			return if called then resultValue else serviceFailure("INTERNAL_ERROR", "query")
		end,
		getLifecycleSnapshot = function(): unknown
			local called, resultValue = callResult(matchLifecycle.getSnapshot, matchLifecycle)
			return if called then resultValue else serviceFailure("INTERNAL_ERROR", "query")
		end,
		getBaseDefeatState = function(): unknown
			local called, value = callNonYielding(baseRuntime.getDefeatState, baseRuntime)
			return if called then value else nil
		end,
		isAuthenticatedTerminalOutcome = function(outcome: unknown): unknown
			local handle = data.boundaryHandle
			if handle == nil then
				return false
			end
			local called, accepted =
				callNonYielding(enemySimulation.isAuthenticatedTerminalOutcome, enemySimulation, handle, outcome)
			return called and accepted == true
		end,
	})
end

local function publisherDependencies(data: ServiceData): WaveReplicationPublisher.Dependencies
	local matchLifecycle = data.matchLifecycle :: MatchLifecycleAdapter
	local sender = data.sender :: WaveSender
	return table.freeze({
		sender = sender,
		getRecipients = function(): unknown
			-- MatchLifecycle intentionally closes ordinary transient recipient reads
			-- while BaseDefeat owns the WaveActive -> Results transaction. DefeatClosed
			-- therefore uses only that transaction's exact preflighted terminal set;
			-- every other Wave state uses only the live connected-recipient capability.
			local provider = if data.terminalState == "DefeatClosed"
				then matchLifecycle.getCommittedBaseDefeatRecipients
				else matchLifecycle.getConnectedRecipients
			local called, resultValue = callResult(provider, matchLifecycle)
			if not called or not isSuccess(resultValue) then
				return nil
			end
			return (resultValue :: any).value
		end,
	})
end

local function validFlushOutcome(value: unknown, passOrdinal: number, expectedWaveRevision: number): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return false
	end
	local outcome = value :: any
	local fields = if outcome.published == true
		then {
			published = true,
			passOrdinal = true,
			waveRevision = true,
			recipientCount = true,
			senderFailureCount = true,
		}
		else {
			published = true,
			passOrdinal = true,
			recipientCount = true,
			senderFailureCount = true,
		}
	return hasExactFields(outcome, fields)
		and type(outcome.published) == "boolean"
		and outcome.passOrdinal == passOrdinal
		and type(outcome.recipientCount) == "number"
		and Validation.isSafeInteger(outcome.recipientCount)
		and outcome.recipientCount >= 0
		and outcome.recipientCount <= WaveProtocol.MAX_BROADCAST_RECIPIENTS
		and type(outcome.senderFailureCount) == "number"
		and Validation.isSafeInteger(outcome.senderFailureCount)
		and outcome.senderFailureCount >= 0
		and outcome.senderFailureCount <= outcome.recipientCount
		and (
			(
				outcome.published
				and type(outcome.waveRevision) == "number"
				and Validation.isSafeInteger(outcome.waveRevision)
				and outcome.waveRevision == expectedWaveRevision
			)
			or (
				not outcome.published
				and outcome.waveRevision == nil
				and outcome.recipientCount == 0
				and outcome.senderFailureCount == 0
			)
		)
end

local function reconcileVoteFailureSnapshot(
	data: ServiceData,
	runtime: RuntimeAdapter,
	publisher: PublisherAdapter
): boolean
	local read, snapshotResult = callResult(runtime.getSnapshot, runtime)
	if not read or not isSuccess(snapshotResult) then
		return false
	end
	local snapshot = canonicalRuntimeSnapshot((snapshotResult :: any).value, data)
	if snapshot == nil then
		return false
	end

	local revision = snapshot.waveRevision
	local sameRevision = revision == data.lastQueuedWaveRevision
	local expectedRevision = if data.lastQueuedWaveRevision < WaveProtocol.MAX_WAVE_REVISION
		then data.lastQueuedWaveRevision + 1
		else nil
	local terminalFailure = snapshot.state == "DefeatClosed" or snapshot.state == "Faulted"
	local newer = expectedRevision ~= nil and revision == expectedRevision and terminalFailure
	if not sameRevision and not newer then
		return false
	end
	if newer then
		local queued, queueResult = callResult(publisher.queueSnapshot, publisher, snapshot)
		if not queued or not isSuccess(queueResult) or (queueResult :: any).value ~= true then
			return false
		end
		data.lastQueuedWaveRevision = snapshot.waveRevision
	end

	if snapshot.state == "DefeatClosed" or snapshot.state == "Faulted" then
		data.terminalState = snapshot.state
		data.terminalPublicationPending = newer
		if snapshot.state == "Faulted" then
			data.recoverableFaultSnapshot = snapshot
		end
		if snapshot.state == "Faulted" and not newer then
			data.callbacksEnabled = false
			data.state = "Failed"
		end
	elseif snapshot.state == "FiniteComplete" then
		data.terminalState = "FiniteComplete"
		data.terminalPublicationPending = newer
	end
	return true
end

local function closeRuntimeDependencyFault(data: ServiceData, context: any): (boolean, boolean)
	local runtime = data.runtime
	local publisher = data.publisher
	if runtime == nil or publisher == nil then
		return false, false
	end

	-- Preflight before the irreversible runtime close when possible. A failed
	-- preflight cannot keep authoritative Wave truth Running; the exact Faulted
	-- snapshot is still retained for Get recovery even if publication is lost.
	local preflighted, preflightResult = callResult(publisher.preflightPublication, publisher)
	local publicationReady = preflighted and isSuccess(preflightResult) and (preflightResult :: any).value == true
	local closed, closeResult = callResult(runtime.closeDependencyFault, runtime, context)
	local snapshot = if closed and isSuccess(closeResult)
		then canonicalRuntimeSnapshot((closeResult :: any).value, data)
		else nil
	if snapshot == nil or (snapshot :: WaveProtocol.WaveSnapshot).state ~= "Faulted" then
		return false, false
	end

	local faultSnapshot = snapshot :: WaveProtocol.WaveSnapshot
	local previouslyRetained = data.recoverableFaultSnapshot
	if
		faultSnapshot.waveRevision == data.lastQueuedWaveRevision
		and (previouslyRetained == nil or not waveSnapshotsEqual(previouslyRetained, faultSnapshot))
	then
		return false, false
	end
	data.recoverableFaultSnapshot = faultSnapshot
	data.terminalState = "Faulted"
	data.lastEnemyPassOrdinal = math.max(data.lastEnemyPassOrdinal, context.passOrdinal)
	data.lastSampleServerTime = math.max(data.lastSampleServerTime, context.sampleServerTime)

	local revision = faultSnapshot.waveRevision
	local newlyQueued = revision > data.lastQueuedWaveRevision
	if revision < data.lastQueuedWaveRevision then
		return true, false
	end
	if newlyQueued then
		if not publicationReady then
			data.terminalPublicationPending = false
			return true, false
		end
		local queued, queueResult = callResult(publisher.queueSnapshot, publisher, faultSnapshot)
		if not queued or not isSuccess(queueResult) or (queueResult :: any).value ~= true then
			data.terminalPublicationPending = false
			return true, false
		end
		data.lastQueuedWaveRevision = revision
		data.terminalPublicationPending = true
	end

	if not data.terminalPublicationPending then
		return true, true
	end
	local flushed, flushResult = callResult(publisher.flush, publisher, context.passOrdinal)
	local flushOutcome = if flushed and isSuccess(flushResult) then (flushResult :: any).value else nil
	local publicationSucceeded = flushed
		and isSuccess(flushResult)
		and validFlushOutcome(flushOutcome, context.passOrdinal, data.lastQueuedWaveRevision)
		and (flushOutcome :: any).published == true
	data.terminalPublicationPending = false
	if publicationSucceeded then
		data.lastFlushedPassOrdinal = context.passOrdinal
	end
	return true, publicationSucceeded
end

local function makeBoundaryAdapter(data: ServiceData): WaveBoundaryAdapter
	local adapter: WaveBoundaryAdapter
	adapter = table.freeze({
		onEnemyPass = function(self: WaveBoundaryAdapter, frameValue: unknown): unknown
			if self ~= adapter then
				return serviceFailure("INVALID_ARGUMENT", "onEnemyPass")
			end
			if
				(data.state ~= "Initialized" and data.state ~= "Started")
				or not data.callbacksEnabled
				or data.operationActive
				or not validBoundaryFrame(data, frameValue)
			then
				return boundaryFailure(data, "onEnemyPass")
			end
			data.operationActive = true
			local frame = frameValue :: any
			if
				data.terminalState == "FiniteComplete"
				or data.terminalState == "DefeatClosed"
				or data.terminalState == "Faulted"
			then
				data.lastEnemyPassOrdinal = frame.passOrdinal
				data.lastSampleServerTime = frame.sampleServerTime
				data.operationActive = false
				if frame.disposition == "DefeatCommitted" then
					return Result.ok(false)
				end
				if frame.disposition == "Healthy" then
					if data.terminalState == "FiniteComplete" then
						return Result.ok(false)
					end
					if data.terminalPublicationPending then
						return Result.ok(true)
					end
					return boundaryFailure(data, "onEnemyPass")
				end
				return Result.ok(false)
			end
			local runtime = data.runtime
			local publisher = data.publisher
			if runtime == nil or publisher == nil then
				data.operationActive = false
				return boundaryFailure(data, "onEnemyPass")
			end
			local preflighted, preflightResult = callResult(publisher.preflightPublication, publisher)
			if not preflighted or not isSuccess(preflightResult) or (preflightResult :: any).value ~= true then
				data.operationActive = false
				return boundaryFailure(data, "onEnemyPass")
			end
			local runtimeFrame = frame
			local durationStarted: number? = nil
			if data.studioActivated then
				local durationClock = data.durationClock
				if durationClock ~= nil then
					local called, value = callNonYielding(durationClock)
					if called and isFiniteNumber(value) then
						durationStarted = value :: number
					end
				end
				if frame.disposition == "Healthy" and type(frame.spawn) == "function" then
					local originalSpawn = frame.spawn
					runtimeFrame = table.freeze({
						disposition = frame.disposition,
						matchId = frame.matchId,
						enemyEpoch = frame.enemyEpoch,
						passOrdinal = frame.passOrdinal,
						sampleServerTime = frame.sampleServerTime,
						terminalOutcomes = frame.terminalOutcomes,
						spawn = function(event: unknown): unknown
							local outcome = originalSpawn(event)
							local eventRecord = if type(event) == "table" then event :: any else nil
							local snapshot = if type(outcome) == "table" then (outcome :: any).snapshot else nil
							if
								type(eventRecord) == "table"
								and type(snapshot) == "table"
								and (outcome :: any).committed == true
								and (outcome :: any).replicationCommitted == true
								and isFiniteNumber(eventRecord.scheduledServerTime)
								and isFiniteNumber((snapshot :: any).spawnServerTime)
								and type((snapshot :: any).runtimeEnemyId) == "number"
								and Validation.isSafeInteger((snapshot :: any).runtimeEnemyId)
								and (snapshot :: any).runtimeEnemyId >= 1
								and type(eventRecord.originatingWaveIndex) == "number"
								and Validation.isSafeInteger(eventRecord.originatingWaveIndex)
								and eventRecord.originatingWaveIndex >= 1
								and eventRecord.originatingWaveIndex <= data.totalWaves
								and type(eventRecord.groupIndex) == "number"
								and Validation.isSafeInteger(eventRecord.groupIndex)
								and eventRecord.groupIndex >= 1
								and eventRecord.groupIndex <= Validation.MAX_WAVE_GROUPS
								and type(eventRecord.spawnOrdinal) == "number"
								and Validation.isSafeInteger(eventRecord.spawnOrdinal)
								and eventRecord.spawnOrdinal >= 0
								and eventRecord.spawnOrdinal < Validation.MAX_GROUP_SPAWN_COUNT
								and Ids.validateWaveId(eventRecord.waveId).ok
								and Ids.validateEnemyId(eventRecord.enemyId).ok
								and type(eventRecord.laneId) == "string"
								and Validation.isSymbolicKey(eventRecord.laneId)
								and eventRecord.scheduledServerTime >= 0
								and (snapshot :: any).spawnServerTime >= 0
								and isFiniteNumber((snapshot :: any).currentHealth)
								and (snapshot :: any).currentHealth >= 0
								and isFiniteNumber((snapshot :: any).maximumHealth)
								and (snapshot :: any).maximumHealth >= 0
								and isFiniteNumber((snapshot :: any).effectiveSpeed)
								and (snapshot :: any).effectiveSpeed >= 0
							then
								local lateness = (snapshot :: any).spawnServerTime - eventRecord.scheduledServerTime
								if lateness < 0 then
									data.studioEarlySpawnCount =
										math.min(data.studioEarlySpawnCount + 1, Validation.MAX_SAFE_INTEGER)
								elseif lateness > data.studioMaximumSpawnLatenessSeconds then
									data.studioMaximumSpawnLatenessSeconds = lateness
								end
								if #data.studioSpawnEvidence < WaveProtocol.MAX_TOTAL_SCHEDULED then
									table.insert(
										data.studioSpawnEvidence,
										table.freeze({
											runtimeEnemyId = (snapshot :: any).runtimeEnemyId,
											originatingWaveIndex = eventRecord.originatingWaveIndex,
											waveId = eventRecord.waveId,
											groupIndex = eventRecord.groupIndex,
											spawnOrdinal = eventRecord.spawnOrdinal,
											enemyId = eventRecord.enemyId,
											laneId = eventRecord.laneId,
											scheduledServerTime = eventRecord.scheduledServerTime,
											spawnServerTime = (snapshot :: any).spawnServerTime,
											latenessSeconds = lateness,
											currentHealth = (snapshot :: any).currentHealth,
											maximumHealth = (snapshot :: any).maximumHealth,
											effectiveSpeed = (snapshot :: any).effectiveSpeed,
										})
									)
								end
							end
							return outcome
						end,
					})
				end
			end
			local stepped, stepResult = callResult(runtime.step, runtime, runtimeFrame)
			if durationStarted ~= nil and data.durationClock ~= nil then
				local called, value = callNonYielding(data.durationClock :: Clock)
				if called and isFiniteNumber(value) and (value :: number) >= durationStarted then
					local duration = (value :: number) - durationStarted
					data.studioSchedulerSampleCount =
						math.min(data.studioSchedulerSampleCount + 1, Validation.MAX_SAFE_INTEGER)
					data.studioLastSchedulerSeconds = duration
					data.studioMaximumSchedulerSeconds = math.max(data.studioMaximumSchedulerSeconds, duration)
				end
			end
			local snapshot = if stepped and isSuccess(stepResult)
				then canonicalRuntimeSnapshot((stepResult :: any).value, data)
				else nil
			if snapshot == nil then
				data.operationActive = false
				return boundaryFailure(data, "onEnemyPass")
			end
			local revision = (snapshot :: WaveProtocol.WaveSnapshot).waveRevision
			local sameRevision = revision == data.lastQueuedWaveRevision
			local expectedRevision = if data.lastQueuedWaveRevision < WaveProtocol.MAX_WAVE_REVISION
				then data.lastQueuedWaveRevision + 1
				else nil
			local newer = expectedRevision ~= nil and revision == expectedRevision
			if not sameRevision and not newer then
				data.operationActive = false
				return boundaryFailure(data, "onEnemyPass")
			end
			if newer then
				local queued, queueResult = callResult(publisher.queueSnapshot, publisher, snapshot)
				if not queued or not isSuccess(queueResult) or (queueResult :: any).value ~= true then
					data.operationActive = false
					return boundaryFailure(data, "onEnemyPass")
				end
				data.lastQueuedWaveRevision = (snapshot :: WaveProtocol.WaveSnapshot).waveRevision
			end
			data.lastEnemyPassOrdinal = frame.passOrdinal
			data.lastSampleServerTime = frame.sampleServerTime
			local snapshotState = (snapshot :: WaveProtocol.WaveSnapshot).state
			local terminalSnapshot = snapshotState == "FiniteComplete"
				or snapshotState == "DefeatClosed"
				or snapshotState == "Faulted"
			data.terminalState = if terminalSnapshot then snapshotState else nil
			data.terminalPublicationPending = terminalSnapshot and newer
			if snapshotState == "Faulted" then
				data.recoverableFaultSnapshot = snapshot
			end
			data.operationActive = false
			if data.shutdownRequested then
				return Result.ok(true)
			end
			if snapshotState == "Faulted" then
				if data.terminalPublicationPending then
					return Result.ok(true)
				end
				return boundaryFailure(data, "onEnemyPass")
			end
			return Result.ok(snapshotState ~= "FiniteComplete" and snapshotState ~= "DefeatClosed")
		end,
		flushEnemyPass = function(self: WaveBoundaryAdapter, passOrdinal: unknown): unknown
			if self ~= adapter then
				return serviceFailure("INVALID_ARGUMENT", "flushEnemyPass")
			end
			local pendingShutdown = data.shutdownRequested
			if
				(
					not pendingShutdown
					and ((data.state ~= "Initialized" and data.state ~= "Started") or not data.callbacksEnabled)
				)
				or data.operationActive
				or type(passOrdinal) ~= "number"
				or not Validation.isSafeInteger(passOrdinal)
				or passOrdinal ~= data.lastEnemyPassOrdinal
				or passOrdinal <= data.lastFlushedPassOrdinal
			then
				return boundaryFailure(data, "flushEnemyPass")
			end
			local publisher = data.publisher
			if publisher == nil then
				return boundaryFailure(data, "flushEnemyPass")
			end
			data.operationActive = true
			local flushed, flushResult = callResult(publisher.flush, publisher, passOrdinal)
			local flushOutcome = if flushed and isSuccess(flushResult) then (flushResult :: any).value else nil
			if
				not flushed
				or not isSuccess(flushResult)
				or not validFlushOutcome(flushOutcome, passOrdinal :: number, data.lastQueuedWaveRevision)
				or (data.terminalPublicationPending and not (flushOutcome :: any).published)
			then
				data.operationActive = false
				return boundaryFailure(data, "flushEnemyPass")
			end
			data.lastFlushedPassOrdinal = passOrdinal :: number
			data.operationActive = false
			if data.terminalPublicationPending then
				data.terminalPublicationPending = false
				if data.terminalState == "Faulted" then
					data.callbacksEnabled = false
					data.state = "Failed"
					return serviceFailure("INTERNAL_ERROR", "flushEnemyPass")
				end
			end
			if data.shutdownRequested then
				return Result.ok(false)
			end
			return Result.ok(true)
		end,
		close = function(self: WaveBoundaryAdapter, contextValue: unknown): unknown
			if self ~= adapter then
				return serviceFailure("INVALID_ARGUMENT", "close")
			end
			if data.state == "Shutdown" or data.terminalState == "Cleaned" then
				return Result.ok(false)
			end
			if data.operationActive or not validCloseContext(data, contextValue) then
				return boundaryFailure(data, "close")
			end
			if data.shutdownRequested then
				local cleaned = releaseAfterEnemyBoundaryClose(data)
				data.state = if cleaned then "Shutdown" else "Failed"
				return if cleaned then Result.ok(true) else serviceFailure("INTERNAL_ERROR", "close")
			end
			local context = contextValue :: any
			data.callbacksEnabled = false
			if context.disposition == "Shutdown" then
				data.terminalState = "ShutdownClosed"
				data.state = "Failed"
				return Result.ok(true)
			end
			if data.terminalState == "FiniteComplete" or data.terminalState == "DefeatClosed" then
				-- A downstream dependency fault cannot rewrite an already committed
				-- Wave terminal. The Enemy boundary still closes and service mutation
				-- admission remains permanently disabled.
				data.state = "Failed"
				return Result.ok(true)
			end

			data.operationActive = true
			local runtimeClosed, _published = closeRuntimeDependencyFault(data, context)
			data.operationActive = false
			data.callbacksEnabled = false
			data.state = "Failed"
			if not runtimeClosed then
				data.terminalState = "Faulted"
				return serviceFailure("INTERNAL_ERROR", "close")
			end
			return Result.ok(true)
		end,
	})
	return adapter
end

type StudioMapIdentity = {
	runtimeMap: unknown,
	mapId: Ids.MapId,
	laneIds: { string },
}

local function studioGroup(
	enemyId: string,
	laneId: string,
	count: number,
	startDelaySeconds: number,
	spawnIntervalSeconds: number
): { [string]: unknown }
	return {
		enemyId = enemyId,
		laneId = laneId,
		count = count,
		startDelaySeconds = startDelaySeconds,
		spawnIntervalSeconds = spawnIntervalSeconds,
	}
end

local function studioWave(
	scenario: string,
	waveIndex: number,
	totalWaves: number,
	deadlineSeconds: number,
	deadlinePolicy: string,
	groups: { { [string]: unknown } },
	bossKind: string?
): { [string]: unknown }
	local final = waveIndex == totalWaves
	local resolvedBossKind = bossKind or if final then "Boss" else "None"
	local rewardClass = if final then "Final" elseif resolvedBossKind == "None" then "Standard" else "Milestone"
	return {
		id = `wave:phase11-studio-{string.lower(scenario)}-{waveIndex}`,
		deadlineSeconds = deadlineSeconds,
		deadlinePolicy = deadlinePolicy,
		bossKind = resolvedBossKind,
		rewardClass = rewardClass,
		groups = groups,
	}
end

local function studioWaves(scenario: string, laneIds: { string }): { { [string]: unknown } }?
	local firstLane = laneIds[1]
	if firstLane == nil then
		return nil
	end
	local secondLane = laneIds[2] or firstLane
	if scenario == "Primary" then
		local total = 4
		return {
			studioWave(scenario, 1, total, 8, "AllSpawnsByDeadline", {
				studioGroup(STUDIO_ENEMY_ID, firstLane, 3, 0, 0),
				studioGroup(STUDIO_ENEMY_ID, secondLane, 3, 1, 1),
			}),
			studioWave(scenario, 2, total, 6, "AllSpawnsByDeadline", {
				studioGroup(STUDIO_ENEMY_ID, secondLane, 2, 0.5, 1),
			}, "MiniBoss"),
			studioWave(scenario, 3, total, 6, "AllSpawnsByDeadline", {}),
			studioWave(scenario, 4, total, 6, "AllSpawnsByDeadline", {
				studioGroup(STUDIO_ENEMY_ID, firstLane, 2, 0, 1),
			}),
		}
	elseif scenario == "Empty" then
		local total = 2
		return {
			studioWave(scenario, 1, total, 10, "AllSpawnsByDeadline", {}),
			studioWave(scenario, 2, total, 10, "AllSpawnsByDeadline", {
				studioGroup(STUDIO_ENEMY_ID, firstLane, 1, 0, 0),
			}),
		}
	elseif scenario == "Deadline" then
		local total = 2
		return {
			studioWave(scenario, 1, total, 2, "AllSpawnsByDeadline", {
				studioGroup(STUDIO_ENEMY_ID, firstLane, 1, 2, 0),
			}),
			studioWave(scenario, 2, total, 4, "AllSpawnsByDeadline", {
				studioGroup(STUDIO_ENEMY_ID, secondLane, 1, 0, 0),
			}),
		}
	elseif scenario == "Overlap" then
		local total = 2
		return {
			studioWave(scenario, 1, total, 1, "AllowScheduledOverlap", {
				studioGroup(STUDIO_ENEMY_ID, firstLane, 2, 0, 2),
			}),
			studioWave(scenario, 2, total, 6, "AllSpawnsByDeadline", {
				studioGroup(STUDIO_ENEMY_ID, secondLane, 2, 0, 0),
			}),
		}
	elseif scenario == "Skip" then
		local total = 2
		return {
			studioWave(scenario, 1, total, 20, "AllSpawnsByDeadline", {
				studioGroup(STUDIO_ENEMY_ID, firstLane, 1, 10, 0),
			}),
			studioWave(scenario, 2, total, 10, "AllSpawnsByDeadline", {
				studioGroup(STUDIO_ENEMY_ID, secondLane, 1, 0, 0),
			}),
		}
	elseif scenario == "Defeat" then
		return {
			studioWave(scenario, 1, 1, 10, "AllSpawnsByDeadline", {
				studioGroup(STUDIO_DEFEAT_ENEMY_ID, firstLane, 1, 0, 0),
				studioGroup(STUDIO_ENEMY_ID, secondLane, 2, 2, 1),
			}),
		}
	end
	local ladderCounts = {
		Ladder1 = 1,
		Ladder32 = 32,
		Ladder64 = 64,
		Ladder128 = 128,
	}
	local count = ladderCounts[scenario]
	if count == nil then
		return nil
	end
	local groups = {}
	local remaining = count
	while remaining > 0 do
		local groupCount = math.min(remaining, Validation.MAX_SIMULTANEOUS_GROUP_SPAWNS)
		table.insert(groups, studioGroup(STUDIO_ENEMY_ID, firstLane, groupCount, 0, 0))
		remaining -= groupCount
	end
	return {
		studioWave(scenario, 1, 1, 20, "AllSpawnsByDeadline", groups),
	}
end

local function readStudioMapIdentity(data: ServiceData): StudioMapIdentity?
	local matchLifecycle = data.matchLifecycle
	if matchLifecycle == nil then
		return nil
	end
	local called, mapResult = callResult(matchLifecycle.getRuntimeMapSnapshot, matchLifecycle)
	if not called or not isSuccess(mapResult) then
		return nil
	end
	local runtimeMap = (mapResult :: any).value
	local authenticated, accepted = callNonYielding(matchLifecycle.isRuntimeMapSnapshot, matchLifecycle, runtimeMap)
	if
		not authenticated
		or accepted ~= true
		or type(runtimeMap) ~= "table"
		or not table.isfrozen(runtimeMap :: any)
	then
		return nil
	end
	local mapIdResult = Ids.validateMapId((runtimeMap :: any).mapId)
	local lanes = (runtimeMap :: any).lanes
	if
		not mapIdResult.ok
		or type(lanes) ~= "table"
		or getmetatable(lanes :: any) ~= nil
		or not table.isfrozen(lanes :: any)
		or #lanes < 1
		or #lanes > MAX_STUDIO_LANES
	then
		return nil
	end
	local laneIds: { string } = {}
	local seen: { [string]: boolean } = {}
	local count = 0
	for key in next, lanes :: any do
		count += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > #lanes then
			return nil
		end
	end
	if count ~= #lanes then
		return nil
	end
	for _, lane in lanes :: { unknown } do
		local laneId = if type(lane) == "table" then (lane :: any).id else nil
		if type(laneId) ~= "string" or not Validation.isSymbolicKey(laneId) or seen[laneId] then
			return nil
		end
		seen[laneId] = true
		table.insert(laneIds, laneId)
	end
	return table.freeze({
		runtimeMap = runtimeMap,
		mapId = mapIdResult.value,
		laneIds = table.freeze(laneIds),
	})
end

local function studioReward(battleCash: number, gold: number): { [string]: unknown }
	return {
		battleCashStipendPerActivePlayer = battleCash,
		persistentGold = { baseAmountPerEligiblePlayer = gold },
	}
end

local function buildStudioSources(scenario: string, mapIdentity: StudioMapIdentity): ({ [string]: unknown }?, number?)
	local waves = studioWaves(scenario, mapIdentity.laneIds)
	if waves == nil then
		return nil, nil
	end
	local rawLanes = {}
	for _, laneId in mapIdentity.laneIds do
		table.insert(rawLanes, { id = laneId })
	end
	local waveCount = #waves
	local baseMaximumHealth = if scenario == "Defeat" then 10 else 1_000_000
	return {
		assets = {
			{ key = STUDIO_ENEMY_MODEL_ASSET_KEY, kind = "EnemyModel" },
			{ key = STUDIO_MAP_MODEL_ASSET_KEY, kind = "MapModel" },
		},
		towers = {},
		enemies = {
			{
				id = STUDIO_ENEMY_ID,
				displayName = "Phase 11 Studio Enemy",
				modelAssetKey = STUDIO_ENEMY_MODEL_ASSET_KEY,
				maxHealth = 80,
				moveSpeedStudsPerSecond = 20,
				leakDamage = 1,
				damageIncomeClass = "EligibleHealthRemoved",
			},
			{
				id = STUDIO_DEFEAT_ENEMY_ID,
				displayName = "Phase 11 Studio Defeat Enemy",
				modelAssetKey = STUDIO_ENEMY_MODEL_ASSET_KEY,
				maxHealth = 1,
				moveSpeedStudsPerSecond = 1_000_000,
				leakDamage = 10,
				damageIncomeClass = "None",
			},
		},
		difficulties = {
			{
				id = STUDIO_DIFFICULTY_ID,
				displayName = "Phase 11 Studio Evidence",
				kind = "Finite",
				waveCount = waveCount,
				base = { maxHealth = baseMaximumHealth },
				modifiers = {
					enemyHealthMultiplier = 1.25,
					enemyMoveSpeedMultiplier = 0.8,
				},
				timing = {
					earlyClearIntermissionSeconds = 5,
					bossCadenceWaves = waveCount,
					skipVoteMinimumDelaySeconds = 1,
				},
			},
		},
		maps = {
			{
				id = mapIdentity.mapId,
				displayName = "Phase 11 Studio Runtime Map",
				modelAssetKey = STUDIO_MAP_MODEL_ASSET_KEY,
				lanes = rawLanes,
				supportedDifficultyIds = { STUDIO_DIFFICULTY_ID },
			},
		},
		waves = {
			{
				kind = "AuthoredFinite",
				mapId = mapIdentity.mapId,
				difficultyId = STUDIO_DIFFICULTY_ID,
				waves = waves,
			},
		},
		economy = {
			version = 1,
			sellRefund = { basisPoints = 7_000, rounding = "Floor" },
			difficultyRules = {
				{
					difficultyId = STUDIO_DIFFICULTY_ID,
					startingBattleCash = 500,
					damageIncome = {
						battleCashNumerator = 1,
						healthRemovedDenominator = 10,
						rounding = "Floor",
						accrualScope = "PerPlayerMatch",
					},
					waveRewards = {
						standard = studioReward(0, 0),
						milestone = studioReward(0, 0),
						final = studioReward(0, 0),
					},
				},
			},
		},
		banners = {},
		defaultSettings = {
			version = 1,
			masterVolume = 1,
			musicVolume = 0.75,
			sfxVolume = 0.8,
			uiVolume = 0.9,
			cameraShakeIntensity = 0.5,
			damageNumbersEnabled = true,
			enemyHealthBarsEnabled = true,
			otherPlayerEffectsEnabled = true,
			lowDetailEnabled = false,
			towerRangeEnabled = true,
			uiScale = 1,
		},
	},
		waveCount
end

local function canonicalMatchSnapshot(value: unknown): MatchProtocol.MatchSnapshot?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return nil
	end
	local validated = MatchProtocol.validateMatchSnapshot(value)
	return if validated.ok then validated.value else nil
end

local function readStudioMatchSnapshot(matchLifecycle: MatchLifecycleAdapter): MatchProtocol.MatchSnapshot?
	local called, resultValue = callResult(matchLifecycle.getSnapshot, matchLifecycle)
	if not called or not isSuccess(resultValue) then
		return nil
	end
	return canonicalMatchSnapshot((resultValue :: any).value)
end

local function readStudioRecipients(matchLifecycle: MatchLifecycleAdapter): { any }?
	local called, resultValue = callResult(matchLifecycle.getConnectedRecipients, matchLifecycle)
	local recipients = if called and isSuccess(resultValue) then (resultValue :: any).value else nil
	if
		type(recipients) ~= "table"
		or getmetatable(recipients :: any) ~= nil
		or not table.isfrozen(recipients :: any)
		or #recipients > WaveProtocol.MAX_BROADCAST_RECIPIENTS
	then
		return nil
	end
	local count = 0
	for key in next, recipients :: any do
		count += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > #recipients then
			return nil
		end
	end
	if count ~= #recipients then
		return nil
	end
	local seenUserIds: { [number]: boolean } = {}
	for _, record in recipients :: { unknown } do
		if
			type(record) ~= "table"
			or getmetatable(record :: any) ~= nil
			or not table.isfrozen(record :: any)
			or not hasExactFields(record :: any, CONNECTED_RECIPIENT_FIELDS)
			or (record :: any).recipient == nil
			or not isUserId((record :: any).userId)
			or seenUserIds[(record :: any).userId] == true
		then
			return nil
		end
		seenUserIds[(record :: any).userId] = true
	end
	return recipients :: { any }
end

local function studioPreWaveAvailability(data: ServiceData): boolean?
	local matchLifecycle = data.matchLifecycle
	if matchLifecycle == nil then
		return nil
	end
	local snapshot = readStudioMatchSnapshot(matchLifecycle)
	if snapshot == nil then
		return nil
	elseif snapshot.state == "PreWave" then
		return true
	elseif snapshot.state == "Loading" then
		return false
	elseif snapshot.state ~= "ReadyCheck" then
		return nil
	end
	local recipients = readStudioRecipients(matchLifecycle)
	if recipients == nil then
		return nil
	end
	return #recipients > 0
end

local function prepareStudioPreWave(data: ServiceData): boolean
	local matchLifecycle = data.matchLifecycle
	if matchLifecycle == nil then
		return false
	end
	local snapshot = readStudioMatchSnapshot(matchLifecycle)
	if snapshot == nil then
		return false
	elseif snapshot.state == "PreWave" then
		return true
	elseif snapshot.state ~= "ReadyCheck" then
		return false
	end
	local submitReady = matchLifecycle.submitReady
	if type(submitReady) ~= "function" then
		return false
	end
	local recipients = readStudioRecipients(matchLifecycle)
	if recipients == nil then
		return false
	end
	local matchId = snapshot.matchId
	for _, record in recipients do
		if snapshot.state == "PreWave" then
			break
		end
		local called, resultValue =
			callResult(submitReady, matchLifecycle, record.recipient, matchId, snapshot.revision)
		local nextSnapshot = if called and isSuccess(resultValue)
			then canonicalMatchSnapshot((resultValue :: any).value)
			else nil
		if
			nextSnapshot == nil
			or nextSnapshot.matchId ~= matchId
			or nextSnapshot.revision <= snapshot.revision
			or (nextSnapshot.state ~= "ReadyCheck" and nextSnapshot.state ~= "PreWave")
		then
			local refreshed = readStudioMatchSnapshot(matchLifecycle)
			return refreshed ~= nil and refreshed.matchId == matchId and refreshed.state == "PreWave"
		end
		snapshot = nextSnapshot
	end
	local finalSnapshot = readStudioMatchSnapshot(matchLifecycle)
	return finalSnapshot ~= nil and finalSnapshot.matchId == matchId and finalSnapshot.state == "PreWave"
end

local function initializeFinite(data: ServiceData)
	local selection = data.selection :: Selection
	if selection.kind ~= "AuthoredFinite" then
		failInitialize(data, "SELECTION_INVALID")
	end

	local matchLifecycle = data.matchLifecycle
	local enemySimulation = data.enemySimulation
	local createRuntime = data.createRuntime
	local createPublisher = data.createPublisher
	if matchLifecycle == nil or enemySimulation == nil or createRuntime == nil or createPublisher == nil then
		failInitialize(data, "DEPENDENCY_MISSING")
	end
	local snapshotCalled, snapshotResult =
		callResult((matchLifecycle :: MatchLifecycleAdapter).getSnapshot, matchLifecycle)
	if not snapshotCalled or not isSuccess(snapshotResult) then
		failInitialize(data, "MATCH_SNAPSHOT_UNAVAILABLE")
	end
	local matchSnapshot = (snapshotResult :: any).value
	local matchIdResult = Ids.validateMatchId(if type(matchSnapshot) == "table" then matchSnapshot.matchId else nil)
	if not matchIdResult.ok or matchSnapshot.state ~= "PreWave" then
		failInitialize(data, "MATCH_SNAPSHOT_INVALID")
	end
	data.matchId = matchIdResult.value
	data.difficultyId = selection.difficultyId
	local identityCalled, identityResult =
		callResult((enemySimulation :: EnemySimulationAdapter).getIdentity, enemySimulation)
	if not identityCalled or not isSuccess(identityResult) then
		failInitialize(data, "ENEMY_IDENTITY_UNAVAILABLE")
	end
	local enemyIdentity = (identityResult :: any).value
	if
		type(enemyIdentity) ~= "table"
		or getmetatable(enemyIdentity :: any) ~= nil
		or not table.isfrozen(enemyIdentity :: any)
		or not hasExactFields(enemyIdentity :: any, ENEMY_IDENTITY_FIELDS)
		or enemyIdentity.matchId ~= data.matchId
		or type(enemyIdentity.enemyEpoch) ~= "number"
		or not Validation.isSafeInteger(enemyIdentity.enemyEpoch)
		or enemyIdentity.enemyEpoch < 1
	then
		failInitialize(data, "ENEMY_IDENTITY_INVALID")
	end
	data.enemyEpoch = enemyIdentity.enemyEpoch

	local runtimeMap = data.studioRuntimeMapPending
	data.studioRuntimeMapPending = nil
	if runtimeMap == nil then
		local mapCalled, mapResult =
			callResult((matchLifecycle :: MatchLifecycleAdapter).getRuntimeMapSnapshot, matchLifecycle)
		if not mapCalled or not isSuccess(mapResult) then
			failInitialize(data, "RUNTIME_MAP_UNAVAILABLE")
		end
		runtimeMap = (mapResult :: any).value
	end
	local dependencies = runtimeDependencies(data)
	local created, runtimeResult = callResult(
		createRuntime :: RuntimeFactory,
		data.configuration,
		runtimeMap,
		data.matchId,
		data.enemyEpoch,
		data.difficultyId,
		dependencies
	)
	if not created or not isSuccess(runtimeResult) then
		failInitialize(data, "RUNTIME_CREATION_FAILED")
	end
	local runtime = (runtimeResult :: any).value
	if not hasMethods(runtime, RUNTIME_METHODS) then
		if type(runtime) == "table" and type((runtime :: any).cleanup) == "function" then
			callNonYielding((runtime :: any).cleanup, runtime)
		end
		failInitialize(data, "RUNTIME_INVALID")
	end
	data.runtime = runtime :: RuntimeAdapter
	data.boundaryAdapter = makeBoundaryAdapter(data)
	local installed, installResult = callResult(
		(enemySimulation :: EnemySimulationAdapter).installWaveBoundary,
		enemySimulation,
		data.boundaryAdapter
	)
	if not installed or not isSuccess(installResult) then
		failInitialize(data, "BOUNDARY_INSTALL_FAILED")
	end
	data.boundaryHandle = (installResult :: any).value
	local installedStatus = readBoundaryStatus(data, "Installed")
	if installedStatus == nil then
		failInitialize(data, "BOUNDARY_STATUS_INVALID")
	end
	data.boundaryGeneration = (installedStatus :: BoundaryStatus).generation

	local initialized, initializeResult = callResult((runtime :: RuntimeAdapter).initialize, runtime)
	local initialSnapshot = if initialized and isSuccess(initializeResult)
		then canonicalRuntimeSnapshot((initializeResult :: any).value, data)
		else nil
	if
		initialSnapshot == nil
		or (initialSnapshot :: WaveProtocol.WaveSnapshot).state ~= "Running"
		or (initialSnapshot :: WaveProtocol.WaveSnapshot).waveRevision ~= 1
	then
		failInitialize(data, "RUNTIME_INITIALIZATION_FAILED")
	end
	local activeStatus = readBoundaryStatus(data, "Active")
	if activeStatus == nil or (activeStatus :: BoundaryStatus).generation ~= data.boundaryGeneration then
		failInitialize(data, "BOUNDARY_ACTIVATION_INVALID")
	end
	data.mapId = (initialSnapshot :: WaveProtocol.WaveSnapshot).mapId
	data.totalWaves = (initialSnapshot :: WaveProtocol.WaveSnapshot).totalWaves

	local publisherCalled, publisherResult = callResult(
		createPublisher :: PublisherFactory,
		data.matchId,
		data.enemyEpoch,
		(initialSnapshot :: WaveProtocol.WaveSnapshot).mapId,
		data.difficultyId,
		(initialSnapshot :: WaveProtocol.WaveSnapshot).totalWaves,
		publisherDependencies(data)
	)
	if not publisherCalled or not isSuccess(publisherResult) then
		failInitialize(data, "PUBLISHER_CREATION_FAILED")
	end
	local publisher = (publisherResult :: any).value
	if not hasMethods(publisher, PUBLISHER_METHODS) then
		if type(publisher) == "table" and type((publisher :: any).cleanup) == "function" then
			callNonYielding((publisher :: any).cleanup, publisher)
		end
		failInitialize(data, "PUBLISHER_INVALID")
	end
	data.publisher = publisher :: PublisherAdapter
	local queued, queueResult = callResult((publisher :: PublisherAdapter).queueSnapshot, publisher, initialSnapshot)
	if not queued or not isSuccess(queueResult) or (queueResult :: any).value ~= true then
		failInitialize(data, "PUBLISHER_INITIAL_QUEUE_FAILED")
	end
	data.lastQueuedWaveRevision = 1
	data.callbacksEnabled = true
	data.state = "Initialized"
end

local function initialize(data: ServiceData)
	if data.state ~= "Constructed" then
		staticError("INVALID_STATE")
	end
	data.state = "Initializing"
	local selection = data.selection :: Selection
	if selection.kind == "Dormant" then
		data.state = "Initialized"
		return
	end
	initializeFinite(data)
end

local function appendStudioTowerFixtures(data: ServiceData, rawSources: { [string]: unknown }): boolean
	local adapter = data.studioTowerBoundaryAdapter
	local handle = data.studioTowerBoundaryHandle
	if adapter == nil and handle == nil then
		return true
	end
	if adapter == nil or handle == nil or STUDIO_TOWER_ACTIVE_HANDLES[handle] ~= true then
		return false
	end
	local called, buildResult = callStudioTower(data, adapter.buildStudioFixtureSources, adapter)
	if not called or not isExactSuccessResult(buildResult) then
		return false
	end
	local additions = validateAndCopyStudioTowerFixtures((buildResult :: any).value)
	local existingAssets = rawSources.assets
	local existingTowers = rawSources.towers
	if additions == nil or type(existingAssets) ~= "table" or type(existingTowers) ~= "table" then
		return false
	end
	local mergedAssets = table.create(#(existingAssets :: { unknown }) + 6)
	for _, record in existingAssets :: { unknown } do
		table.insert(mergedAssets, record)
	end
	for _, record in additions.assets do
		table.insert(mergedAssets, record)
	end
	local mergedTowers = table.create(#(existingTowers :: { unknown }) + 3)
	for _, definition in existingTowers :: { unknown } do
		table.insert(mergedTowers, definition)
	end
	for _, definition in additions.towers do
		table.insert(mergedTowers, definition)
	end
	rawSources.assets = mergedAssets
	rawSources.towers = mergedTowers
	data.studioTowerBuildCount = math.min(data.studioTowerBuildCount + 1, Validation.MAX_SAFE_INTEGER)
	return true
end

local function prepareStudioTowerConfiguration(
	data: ServiceData,
	configuration: ConfigTypes.CoreConfiguration,
	matchId: Ids.MatchId
): boolean
	local adapter = data.studioTowerBoundaryAdapter
	local handle = data.studioTowerBoundaryHandle
	if adapter == nil and handle == nil then
		return true
	end
	if
		adapter == nil
		or handle == nil
		or STUDIO_TOWER_ACTIVE_HANDLES[handle] ~= true
		or data.studioTowerPreparedToken ~= nil
	then
		return false
	end
	local called, prepareResult =
		callStudioTower(data, adapter.prepareStudioConfiguration, adapter, configuration, matchId)
	local token = if called and isExactSuccessResult(prepareResult) then (prepareResult :: any).value else nil
	if type(token) ~= "table" or getmetatable(token) ~= nil or not table.isfrozen(token) then
		return false
	end
	data.studioTowerPreparedToken = token
	data.studioTowerPrepareCount = math.min(data.studioTowerPrepareCount + 1, Validation.MAX_SAFE_INTEGER)
	return true
end

local function studioFailure(data: ServiceData): Result.Failure<ServiceError>
	data.callbacksEnabled = false
	data.terminalState = "Faulted"
	data.state = "Failed"
	releaseOwnedResources(data)
	data.terminalState = "Faulted"
	return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
end

local function activateStudioScenario(data: ServiceData, scenario: string): unknown
	local baseRuntime = data.baseRuntime
	local validateConfiguration = data.validateConfiguration
	if
		data.studioTrigger == nil
		or data.state ~= "Started"
		or data.studioActivationAttempted
		or data.studioActivated
		or data.runtime ~= nil
		or data.publisher ~= nil
		or data.boundaryHandle ~= nil
		or data.selection == nil
		or (data.selection :: Selection).kind ~= "Dormant"
		or baseRuntime == nil
		or validateConfiguration == nil
	then
		return serviceFailure("STUDIO_ONLY", "runtimeTrigger")
	end
	local preWaveAvailable = studioPreWaveAvailability(data)
	if preWaveAvailable == false then
		return serviceFailure("UNAVAILABLE", "runtimeTrigger")
	elseif preWaveAvailable == nil then
		data.studioActivationAttempted = true
		data.studioScenario = scenario
		return studioFailure(data)
	end
	data.studioActivationAttempted = true
	data.studioScenario = scenario
	local mapIdentity = readStudioMapIdentity(data)
	local rawSources: { [string]: unknown }? = nil
	local expectedWaveCount: number? = nil
	if mapIdentity ~= nil then
		rawSources, expectedWaveCount = buildStudioSources(scenario, mapIdentity :: StudioMapIdentity)
	end
	if rawSources == nil or expectedWaveCount == nil then
		return studioFailure(data)
	end
	if not appendStudioTowerFixtures(data, rawSources) then
		return studioFailure(data)
	end

	data.validateConfiguration = nil
	data.studioValidationCount = math.min(data.studioValidationCount + 1, Validation.MAX_SAFE_INTEGER)
	local validated, validationResult = callResult(validateConfiguration, rawSources)
	local configuration = if validated and isSuccess(validationResult) then (validationResult :: any).value else nil
	if not ConfigurationValidator.isValidatedConfiguration(configuration) then
		return studioFailure(data)
	end
	local difficulty = (configuration :: ConfigTypes.CoreConfiguration).difficulties.byId[STUDIO_DIFFICULTY_ID]
	local schedule = (configuration :: ConfigTypes.CoreConfiguration).waves.byMapId[(mapIdentity :: StudioMapIdentity).mapId]
	local finiteSchedule = if schedule == nil then nil else schedule[STUDIO_DIFFICULTY_ID]
	if
		difficulty == nil
		or difficulty.kind ~= "Finite"
		or difficulty.waveCount ~= expectedWaveCount
		or finiteSchedule == nil
		or finiteSchedule.kind ~= "AuthoredFinite"
		or #finiteSchedule.waves ~= expectedWaveCount
	then
		return studioFailure(data)
	end
	if not prepareStudioPreWave(data) then
		return studioFailure(data)
	end
	if data.studioTowerBoundaryAdapter ~= nil or data.studioTowerBoundaryHandle ~= nil then
		local matchLifecycle = data.matchLifecycle
		local currentMatchSnapshot = if matchLifecycle == nil then nil else readStudioMatchSnapshot(matchLifecycle)
		if
			currentMatchSnapshot == nil
			or currentMatchSnapshot.state ~= "PreWave"
			or not prepareStudioTowerConfiguration(
				data,
				configuration :: ConfigTypes.CoreConfiguration,
				currentMatchSnapshot.matchId
			)
		then
			return studioFailure(data)
		end
	end

	data.configuration = configuration :: ConfigTypes.CoreConfiguration
	data.selection = table.freeze({
		kind = "AuthoredFinite",
		difficultyId = STUDIO_DIFFICULTY_ID,
	})
	data.studioBaseCatalogPending = (configuration :: ConfigTypes.CoreConfiguration).difficulties
	data.studioRuntimeMapPending = (mapIdentity :: StudioMapIdentity).runtimeMap
	data.state = "Initializing"
	initializeFinite(data)
	if data.state ~= "Initialized" or data.lastQueuedWaveRevision ~= 1 then
		return studioFailure(data)
	end
	data.state = "Started"
	data.studioActivated = true
	return Result.ok(table.freeze({
		scenario = scenario,
		matchId = data.matchId,
		enemyEpoch = data.enemyEpoch,
		mapId = data.mapId,
		difficultyId = data.difficultyId,
		totalWaves = data.totalWaves,
		waveRevision = data.lastQueuedWaveRevision,
	}))
end

local function readNonnegativeMetric(record: unknown, fieldName: string): number?
	if type(record) ~= "table" or not table.isfrozen(record :: any) then
		return nil
	end
	local value = (record :: any)[fieldName]
	if type(value) ~= "number" or not Validation.isSafeInteger(value) or value < 0 then
		return nil
	end
	return value
end

local function readPublicationCount(metrics: unknown): number?
	if type(metrics) ~= "table" or not table.isfrozen(metrics :: any) then
		return nil
	end
	return readNonnegativeMetric((metrics :: any).publisher, "publicationCount")
end

local function readEnemyPublicationCount(metrics: unknown): number?
	if type(metrics) ~= "table" or not table.isfrozen(metrics :: any) then
		return nil
	end
	local publisher = (metrics :: any).publisher
	local deltaCount = readNonnegativeMetric(publisher, "deltaMessageCount")
	local snapshotCount = readNonnegativeMetric(publisher, "snapshotMessageCount")
	if deltaCount == nil or snapshotCount == nil or deltaCount > Validation.MAX_SAFE_INTEGER - snapshotCount then
		return nil
	end
	return deltaCount + snapshotCount
end

local function readStudioTowerDiagnostics(data: ServiceData): (unknown, boolean)
	local adapter = data.studioTowerBoundaryAdapter
	local handle = data.studioTowerBoundaryHandle
	if adapter == nil and handle == nil then
		return nil, true
	end
	if adapter == nil or handle == nil or STUDIO_TOWER_ACTIVE_HANDLES[handle] ~= true then
		return nil, false
	end
	local called, resultValue = callStudioTower(data, adapter.getStudioDiagnostics, adapter)
	local detachedResult = if called then detachedStudioTowerResult(resultValue) else nil
	if detachedResult == nil or not isSuccess(detachedResult) then
		return nil, false
	end
	local diagnostics = (detachedResult :: any).value
	if type(diagnostics) ~= "table" or not table.isfrozen(diagnostics) then
		return nil, false
	end
	data.studioTowerDiagnosticsCount = math.min(data.studioTowerDiagnosticsCount + 1, Validation.MAX_SAFE_INTEGER)
	return diagnostics, true
end

local function getStudioDiagnostics(data: ServiceData): unknown
	local matchLifecycle = data.matchLifecycle
	local baseRuntime = data.baseRuntime
	local enemySimulation = data.enemySimulation
	local runtime = data.runtime
	local publisher = data.publisher
	if
		data.studioTrigger == nil
		or not data.studioActivated
		or data.state ~= "Started"
		or matchLifecycle == nil
		or baseRuntime == nil
		or enemySimulation == nil
		or runtime == nil
		or publisher == nil
	then
		return serviceFailure("UNAVAILABLE", "runtimeTrigger")
	end
	local towerDiagnostics, towerDiagnosticsValid = readStudioTowerDiagnostics(data)
	if not towerDiagnosticsValid then
		return studioFailure(data)
	end

	local matchCalled, matchResult = callResult(matchLifecycle.getSnapshot, matchLifecycle)
	local waveCalled, waveResult = callResult(runtime.getSnapshot, runtime)
	local cashCalled, cashResult = callResult(runtime.getStartingCashPlaceholder, runtime)
	local baseCalled, baseResult = callResult(baseRuntime.getSnapshot, baseRuntime)
	local identityCalled, identityResult = callResult(enemySimulation.getIdentity, enemySimulation)
	local listCalled, listResult = callResult(enemySimulation.list, enemySimulation)
	local completionCalled, completionState = callNonYielding(runtime.getCompletionState, runtime)
	local defeatCalled, defeatState = callNonYielding(baseRuntime.getDefeatState, baseRuntime)
	local runtimeMetricsCalled, runtimeMetrics = callNonYielding(runtime.query, runtime)
	local waveMetricsCalled, waveMetrics = callNonYielding(publisher.getMetrics, publisher)
	local baseMetricsCalled, baseMetrics = callNonYielding(baseRuntime.getMetrics, baseRuntime)
	local enemyMetricsCalled, enemyMetrics = callNonYielding(enemySimulation.getMetrics, enemySimulation)
	local matchSnapshot = if matchCalled and isSuccess(matchResult) then (matchResult :: any).value else nil
	local waveSnapshot = if waveCalled and isSuccess(waveResult)
		then canonicalRuntimeSnapshot((waveResult :: any).value, data)
		else nil
	local baseSnapshotResult = if baseCalled and isSuccess(baseResult)
		then BaseProtocol.validateBaseSnapshot((baseResult :: any).value)
		else nil
	local baseSnapshot = if baseSnapshotResult ~= nil and (baseSnapshotResult :: any).ok
		then (baseSnapshotResult :: any).value
		else nil
	local identity = if identityCalled and isSuccess(identityResult) then (identityResult :: any).value else nil
	local activeEnemies = if listCalled and isSuccess(listResult) then (listResult :: any).value else nil
	local startingCash = if cashCalled and isSuccess(cashResult) then (cashResult :: any).value else nil
	local wavePublicationCount = readNonnegativeMetric(waveMetrics, "publicationCount")
	local basePublicationCount = readPublicationCount(baseMetrics)
	local enemyPublicationCount = readEnemyPublicationCount(enemyMetrics)
	local enemyStepConnections = readNonnegativeMetric(enemyMetrics, "stepConnectionCount")
	local enemyRemovingConnections = readNonnegativeMetric(enemyMetrics, "playerRemovingConnectionCount")
	if
		type(matchSnapshot) ~= "table"
		or not table.isfrozen(matchSnapshot :: any)
		or (matchSnapshot :: any).matchId ~= data.matchId
		or type((matchSnapshot :: any).revision) ~= "number"
		or not Validation.isSafeInteger((matchSnapshot :: any).revision)
		or waveSnapshot == nil
		or type(startingCash) ~= "table"
		or not table.isfrozen(startingCash :: any)
		or (startingCash :: any).difficultyId ~= data.difficultyId
		or baseSnapshot == nil
		or (baseSnapshot :: any).matchId ~= data.matchId
		or (baseSnapshot :: any).enemyEpoch ~= data.enemyEpoch
		or type(identity) ~= "table"
		or not table.isfrozen(identity :: any)
		or (identity :: any).matchId ~= data.matchId
		or (identity :: any).enemyEpoch ~= data.enemyEpoch
		or type(activeEnemies) ~= "table"
		or not table.isfrozen(activeEnemies :: any)
		or #activeEnemies > 128
		or not runtimeMetricsCalled
		or type(runtimeMetrics) ~= "table"
		or not table.isfrozen(runtimeMetrics :: any)
		or not waveMetricsCalled
		or not baseMetricsCalled
		or not enemyMetricsCalled
		or not completionCalled
		or type(completionState) ~= "table"
		or not table.isfrozen(completionState :: any)
		or type((completionState :: any).completionCount) ~= "number"
		or not Validation.isSafeInteger((completionState :: any).completionCount)
		or not defeatCalled
		or type(defeatState) ~= "table"
		or not table.isfrozen(defeatState :: any)
		or wavePublicationCount == nil
		or basePublicationCount == nil
		or enemyPublicationCount == nil
		or enemyStepConnections == nil
		or enemyRemovingConnections == nil
	then
		return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
	end
	local maximumEnemyRevision = 0
	local activeEnemyCount = 0
	for key, enemySnapshot in activeEnemies :: any do
		activeEnemyCount += 1
		if
			type(key) ~= "number"
			or key ~= activeEnemyCount
			or type(enemySnapshot) ~= "table"
			or not table.isfrozen(enemySnapshot :: any)
			or type((enemySnapshot :: any).revision) ~= "number"
			or not Validation.isSafeInteger((enemySnapshot :: any).revision)
			or (enemySnapshot :: any).revision < 1
		then
			return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
		end
		maximumEnemyRevision = math.max(maximumEnemyRevision, (enemySnapshot :: any).revision)
	end
	if activeEnemyCount ~= #activeEnemies then
		return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
	end
	local configuration = data.configuration
	local difficulty = if configuration == nil or data.difficultyId == nil
		then nil
		else configuration.difficulties.byId[data.difficultyId]
	local economyRule = if configuration == nil or data.difficultyId == nil
		then nil
		else configuration.economy.byDifficultyId[data.difficultyId]
	local standardEnemy = if configuration == nil then nil else configuration.enemies.byId[STUDIO_ENEMY_ID]
	local defeatEnemy = if configuration == nil then nil else configuration.enemies.byId[STUDIO_DEFEAT_ENEMY_ID]
	if difficulty == nil or economyRule == nil or standardEnemy == nil or defeatEnemy == nil then
		return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
	end
	local detachedActiveEnemies = table.clone(activeEnemies :: any)
	table.freeze(detachedActiveEnemies)
	local detachedSpawnEvidence = table.clone(data.studioSpawnEvidence)
	table.freeze(detachedSpawnEvidence)

	return Result.ok(table.freeze({
		scenario = data.studioScenario,
		validationCount = data.studioValidationCount,
		operationCount = data.studioOperationCount,
		matchSnapshot = matchSnapshot,
		waveSnapshot = waveSnapshot,
		startingCash = startingCash,
		completion = completionState,
		runtime = runtimeMetrics,
		wavePublisher = waveMetrics,
		baseSnapshot = baseSnapshot,
		baseDefeatState = defeatState,
		base = baseMetrics,
		enemy = enemyMetrics,
		enemyIdentity = identity,
		activeEnemies = detachedActiveEnemies,
		spawnEvidence = detachedSpawnEvidence,
		tower = towerDiagnostics,
		configuration = table.freeze({
			baseMaximumHealth = (difficulty :: any).base.maxHealth,
			enemyHealthMultiplier = (difficulty :: any).modifiers.enemyHealthMultiplier,
			enemyMoveSpeedMultiplier = (difficulty :: any).modifiers.enemyMoveSpeedMultiplier,
			startingBattleCash = (economyRule :: any).startingBattleCash,
			standardEnemy = table.freeze({
				maxHealth = (standardEnemy :: any).maxHealth,
				moveSpeedStudsPerSecond = (standardEnemy :: any).moveSpeedStudsPerSecond,
				leakDamage = (standardEnemy :: any).leakDamage,
			}),
			defeatEnemy = table.freeze({
				maxHealth = (defeatEnemy :: any).maxHealth,
				moveSpeedStudsPerSecond = (defeatEnemy :: any).moveSpeedStudsPerSecond,
				leakDamage = (defeatEnemy :: any).leakDamage,
			}),
		}),
		identities = table.freeze({
			matchId = data.matchId,
			enemyEpoch = data.enemyEpoch,
			mapId = data.mapId,
			difficultyId = data.difficultyId,
		}),
		states = table.freeze({
			match = (matchSnapshot :: any).state,
			wave = (waveSnapshot :: WaveProtocol.WaveSnapshot).state,
			base = (baseSnapshot :: any).status,
		}),
		revisions = table.freeze({
			match = (matchSnapshot :: any).revision,
			wave = (waveSnapshot :: WaveProtocol.WaveSnapshot).waveRevision,
			base = (baseSnapshot :: any).baseRevision,
			maximumActiveEnemy = maximumEnemyRevision,
		}),
		publications = table.freeze({
			wave = wavePublicationCount,
			base = basePublicationCount,
			enemy = enemyPublicationCount,
		}),
		connections = table.freeze({
			wave = 0,
			enemyStep = enemyStepConnections,
			enemyPlayerRemoving = enemyRemovingConnections,
		}),
		scheduler = table.freeze({
			sampleCount = data.studioSchedulerSampleCount,
			lastSeconds = data.studioLastSchedulerSeconds,
			maximumSeconds = data.studioMaximumSchedulerSeconds,
			maximumSpawnLatenessSeconds = data.studioMaximumSpawnLatenessSeconds,
			earlySpawnCount = data.studioEarlySpawnCount,
			noEarlySpawns = data.studioEarlySpawnCount == 0,
		}),
		assertions = table.freeze({
			count = data.studioAssertionCount,
			failureCount = data.studioAssertionFailureCount,
		}),
		residue = table.freeze({
			activeEnemyCount = activeEnemyCount,
			spawnEvidenceCount = #detachedSpawnEvidence,
			retainedWaveHeapCount = (runtimeMetrics :: any).retainedHeapCount,
			retainedWaveOwnershipCount = (runtimeMetrics :: any).retainedOwnershipCount,
			terminalState = data.terminalState,
		}),
	}))
end

local function resolveStudioEnemies(data: ServiceData): unknown
	local enemySimulation = data.enemySimulation
	if not data.studioActivated or enemySimulation == nil then
		return serviceFailure("UNAVAILABLE", "runtimeTrigger")
	end
	local listed, listResult = callResult(enemySimulation.list, enemySimulation)
	local activeEnemies = if listed and isSuccess(listResult) then (listResult :: any).value else nil
	if type(activeEnemies) ~= "table" or not table.isfrozen(activeEnemies :: any) or #activeEnemies > 128 then
		return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
	end
	local resolvedCount = 0
	for key, enemySnapshot in activeEnemies :: any do
		local runtimeEnemyId = if type(enemySnapshot) == "table" then (enemySnapshot :: any).runtimeEnemyId else nil
		if
			type(key) ~= "number"
			or key ~= resolvedCount + 1
			or type(runtimeEnemyId) ~= "number"
			or not Validation.isSafeInteger(runtimeEnemyId)
			or runtimeEnemyId < 1
		then
			return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
		end
		local called, resultValue = callResult(enemySimulation.despawn, enemySimulation, runtimeEnemyId)
		if not called then
			return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
		end
		if not isSuccess(resultValue) then
			return serviceFailure("UNAVAILABLE", "runtimeTrigger")
		end
		resolvedCount += 1
	end
	if resolvedCount ~= #activeEnemies then
		return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
	end
	return Result.ok(table.freeze({
		reason = "Manual",
		count = resolvedCount,
	}))
end

local function invalidStudioRequest(): Result.Failure<ServiceError>
	return serviceFailure("INVALID_ARGUMENT", "runtimeTrigger")
end

local function dispatchStudioTrigger(data: ServiceData, argumentCount: number, request: unknown): unknown
	if argumentCount ~= 1 or type(request) ~= "table" or getmetatable(request :: any) ~= nil then
		return invalidStudioRequest()
	end
	if data.studioTrigger == nil or data.service == nil or data.state ~= "Started" then
		return serviceFailure("UNAVAILABLE", "runtimeTrigger")
	end
	local operation = (request :: any).operation
	local valid = (operation == "Activate" and hasExactFields(request :: any, STUDIO_ACTIVATE_FIELDS))
		or (operation == "Diagnostics" and hasExactFields(request :: any, STUDIO_DIAGNOSTICS_FIELDS))
		or (operation == "ResolveEnemies" and hasExactFields(request :: any, STUDIO_RESOLVE_FIELDS))
		or (operation == "SubmitSkipVote" and hasExactFields(request :: any, STUDIO_SKIP_FIELDS))
		or (operation == "RecordAssertion" and hasExactFields(request :: any, STUDIO_ASSERTION_FIELDS))
		or (
			type(operation) == "string"
			and STUDIO_TOWER_OPERATIONS[operation] == true
			and hasExactFields(request :: any, STUDIO_TOWER_REQUEST_FIELDS)
		)
	if not valid then
		return invalidStudioRequest()
	end
	if data.studioOperationCount >= MAX_STUDIO_OPERATIONS then
		return serviceFailure("UNAVAILABLE", "runtimeTrigger")
	end
	if operation == "Activate" then
		local scenario = (request :: any).scenario
		if type(scenario) ~= "string" or STUDIO_SCENARIOS[scenario] ~= true then
			return invalidStudioRequest()
		end
		data.studioOperationCount += 1
		return activateStudioScenario(data, scenario)
	elseif operation == "Diagnostics" then
		data.studioOperationCount += 1
		return getStudioDiagnostics(data)
	elseif operation == "ResolveEnemies" then
		local reason = (request :: any).reason
		if reason ~= "Manual" then
			return invalidStudioRequest()
		end
		data.studioOperationCount += 1
		return resolveStudioEnemies(data)
	elseif operation == "SubmitSkipVote" then
		local userId = (request :: any).userId
		local waveNumber = (request :: any).waveNumber
		if
			not isUserId(userId)
			or type(waveNumber) ~= "number"
			or not Validation.isSafeInteger(waveNumber)
			or waveNumber < 1
			or waveNumber > data.totalWaves
			or not data.studioActivated
			or data.matchId == nil
		then
			return invalidStudioRequest()
		end
		data.studioOperationCount += 1
		return (data.service :: any):submitSkipVote(userId, data.matchId, waveNumber)
	elseif type(operation) == "string" and STUDIO_TOWER_OPERATIONS[operation] == true then
		local adapter = data.studioTowerBoundaryAdapter
		local handle = data.studioTowerBoundaryHandle
		if adapter == nil or handle == nil or STUDIO_TOWER_ACTIVE_HANDLES[handle] ~= true then
			return serviceFailure("UNAVAILABLE", "runtimeTrigger")
		end
		data.studioOperationCount += 1
		if operation == "TowerCleanup" then
			data.studioTowerCloseCount = math.min(data.studioTowerCloseCount + 1, Validation.MAX_SAFE_INTEGER)
			data.studioTowerDispatchCount = math.min(data.studioTowerDispatchCount + 1, Validation.MAX_SAFE_INTEGER)
			local called, closeResult = callStudioTower(data, adapter.dispatchStudioEvidence, adapter, operation)
			invalidateStudioTowerBoundary(data)
			revokeStudioTowerHandles(data)
			local detachedResult = if called then detachedStudioTowerResult(closeResult) else nil
			return detachedResult or serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
		end
		data.studioTowerDispatchCount = math.min(data.studioTowerDispatchCount + 1, Validation.MAX_SAFE_INTEGER)
		local called, dispatchResult = callStudioTower(data, adapter.dispatchStudioEvidence, adapter, operation)
		local detachedResult = if called then detachedStudioTowerResult(dispatchResult) else nil
		if detachedResult == nil then
			return studioFailure(data)
		end
		return detachedResult
	end
	local passed = (request :: any).passed
	if type(passed) ~= "boolean" then
		return invalidStudioRequest()
	end
	if not data.studioActivated or data.studioAssertionCount >= MAX_STUDIO_ASSERTIONS then
		return serviceFailure("UNAVAILABLE", "runtimeTrigger")
	end
	data.studioOperationCount += 1
	data.studioAssertionCount += 1
	if not passed then
		data.studioAssertionFailureCount += 1
	end
	return Result.ok(table.freeze({
		count = data.studioAssertionCount,
		failureCount = data.studioAssertionFailureCount,
	}))
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
		data.validateConfiguration = nil
		data.durationClock = nil
		data.service = nil
		return true
	end
	local handler = function(...: unknown): unknown
		if data.studioTriggerOperationActive then
			if data.studioTowerCallbackActive then
				data.studioTowerReentryViolation = true
			end
			return serviceFailure("REENTRANT", "runtimeTrigger")
		end
		data.studioTriggerOperationActive = true
		local called, resultValue = callNonYielding(dispatchStudioTrigger, data, select("#", ...), select(1, ...))
		data.studioTriggerOperationActive = false
		if not called then
			return studioFailure(data)
		end
		if data.shutdownRequested then
			data.shutdownRequested = false
			local cleaned = releaseOwnedResources(data)
			data.state = if cleaned then "Shutdown" else "Failed"
			if not cleaned then
				return serviceFailure("INTERNAL_ERROR", "runtimeTrigger")
			end
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

local function start(data: ServiceData)
	if data.state ~= "Initialized" then
		staticError("INVALID_STATE")
	end
	data.state = "Starting"
	local selection = data.selection :: Selection
	if selection.kind == "Dormant" then
		if not installStudioTrigger(data) then
			data.state = "Failed"
			releaseOwnedResources(data)
			staticError("STUDIO_TRIGGER_INSTALL_FAILED")
		end
	else
		data.isStudio = nil
		data.createRuntimeTrigger = nil
		data.validateConfiguration = nil
		data.durationClock = nil
		data.service = nil
	end
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
	data.callbacksEnabled = false
	if data.operationActive or data.studioTriggerOperationActive then
		data.shutdownRequested = true
		return
	end
	local cleaned = releaseOwnedResources(data)
	if not cleaned then
		data.state = "Failed"
		staticError("CLEANUP_FAILED")
	end
	data.state = "Shutdown"
end

local function beginRead(data: ServiceData, operation: Operation): ServiceError?
	if data.operationActive then
		return makeServiceError("REENTRANT", operation)
	end
	if
		(data.state ~= "Initialized" and data.state ~= "Started")
		or data.runtime == nil
		or not data.callbacksEnabled
	then
		return makeServiceError("UNAVAILABLE", operation)
	end
	data.operationActive = true
	return nil
end

local function finishRead(data: ServiceData, resultValue: any): any
	data.operationActive = false
	if data.shutdownRequested then
		data.shutdownRequested = false
		local cleaned = releaseOwnedResources(data)
		data.state = if cleaned then "Shutdown" else "Failed"
	end
	return resultValue
end

local function readRuntimeResult(self: Service, operation: Operation, methodName: string): unknown
	local data = requireData(self)
	local operationError = beginRead(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime :: any
	local called, runtimeResult = callResult(runtime[methodName], runtime)
	if not called or not isResult(runtimeResult) then
		data.callbacksEnabled = false
		data.terminalState = "Faulted"
		data.state = "Failed"
		return finishRead(data, serviceFailure("INTERNAL_ERROR", operation))
	end
	return finishRead(data, runtimeResult)
end

function ServiceMethods.installStudioTowerBoundary(self: Service, adapterValue: unknown): unknown
	local operation: Operation = "installStudioTowerBoundary"
	local data = requireData(self)
	if data.studioTowerCallbackActive then
		data.studioTowerReentryViolation = true
		return serviceFailure("REENTRANT", operation)
	end
	if not isExactStudioTowerBoundaryAdapter(adapterValue) then
		return serviceFailure("INVALID_ARGUMENT", operation)
	end
	if data.studioTriggerOperationActive or data.operationActive or data.releasing then
		return serviceFailure("REENTRANT", operation)
	end
	if
		data.state ~= "Started"
		or data.studioTrigger == nil
		or data.selection == nil
		or (data.selection :: Selection).kind ~= "Dormant"
		or data.studioActivationAttempted
		or data.studioActivated
		or data.studioTowerBoundaryAdapter ~= nil
		or data.studioTowerBoundaryHandle ~= nil
	then
		return serviceFailure("UNAVAILABLE", operation)
	end

	local handle = table.freeze({})
	local successResult = Result.ok(handle)
	STUDIO_TOWER_HANDLE_OWNERS[handle] = data.studioTowerOwnerToken
	STUDIO_TOWER_ACTIVE_HANDLES[handle] = true
	data.studioTowerIssuedHandles[handle] = true
	data.studioTowerBoundaryAdapter = adapterValue :: StudioTowerBoundaryAdapter
	data.studioTowerBoundaryHandle = handle
	return successResult
end

function ServiceMethods.detachStudioTowerBoundary(self: Service, handleValue: unknown): unknown
	local operation: Operation = "detachStudioTowerBoundary"
	local data = requireData(self)
	if data.studioTowerCallbackActive then
		data.studioTowerReentryViolation = true
		return serviceFailure("REENTRANT", operation)
	end
	if
		type(handleValue) ~= "table"
		or data.studioTowerOwnerToken == nil
		or STUDIO_TOWER_HANDLE_OWNERS[handleValue :: any] ~= data.studioTowerOwnerToken
	then
		return serviceFailure("INVALID_ARGUMENT", operation)
	end
	if data.studioTriggerOperationActive or data.operationActive or data.releasing then
		return serviceFailure("REENTRANT", operation)
	end
	if STUDIO_TOWER_ACTIVE_HANDLES[handleValue :: any] ~= true then
		return STUDIO_TOWER_DETACH_FALSE
	end
	if data.studioTowerBoundaryHandle ~= handleValue then
		return serviceFailure("INVALID_ARGUMENT", operation)
	end
	invalidateStudioTowerBoundary(data)
	return STUDIO_TOWER_DETACH_TRUE
end

function ServiceMethods.getSnapshot(self: Service): unknown
	local data = requireData(self)
	local retained = data.recoverableFaultSnapshot
	if data.state == "Failed" and data.terminalState == "Faulted" and retained ~= nil then
		if data.operationActive then
			return serviceFailure("REENTRANT", "getSnapshot")
		elseif data.runtime == nil then
			return serviceFailure("UNAVAILABLE", "getSnapshot")
		end
		-- Fault recovery is deliberately read-only. The exact validated terminal
		-- full state survives a contained FireClient failure, while callbacks,
		-- votes, spawns, boundary admission, and every other public read stay shut.
		return Result.ok(retained)
	end
	return readRuntimeResult(self, "getSnapshot", "getSnapshot")
end

function ServiceMethods.getStartingCashPlaceholder(self: Service): unknown
	return readRuntimeResult(self, "getStartingCashPlaceholder", "getStartingCashPlaceholder")
end

function ServiceMethods.getCompletionState(self: Service): unknown
	local data = requireData(self)
	if data.selection ~= nil and (data.selection :: Selection).kind == "Dormant" then
		return Result.ok(table.freeze({
			state = "Uninitialized",
			completionCount = 0,
		}))
	end
	local operationError = beginRead(data, "getCompletionState")
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime :: any
	local called, value = callNonYielding(runtime.getCompletionState, runtime)
	if
		not called
		or type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
		or type((value :: any).state) ~= "string"
		or type((value :: any).completionCount) ~= "number"
	then
		data.callbacksEnabled = false
		data.terminalState = "Faulted"
		data.state = "Failed"
		return finishRead(data, serviceFailure("INTERNAL_ERROR", "getCompletionState"))
	end
	return finishRead(data, Result.ok(value))
end

function ServiceMethods.submitSkipVote(
	self: Service,
	userIdValue: unknown,
	matchIdValue: unknown,
	waveNumberValue: unknown
): unknown
	local data = requireData(self)
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if
		not isUserId(userIdValue)
		or not matchIdResult.ok
		or type(waveNumberValue) ~= "number"
		or not Validation.isSafeInteger(waveNumberValue :: number)
		or (waveNumberValue :: number) < 1
		or (waveNumberValue :: number) > WaveProtocol.MAX_TOTAL_WAVES
	then
		return serviceFailure("INVALID_ARGUMENT", "submitSkipVote")
	end
	if data.terminalState ~= nil then
		return serviceFailure("UNAVAILABLE", "submitSkipVote")
	end
	local operationError = beginRead(data, "submitSkipVote")
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local status = readBoundaryStatus(data, "Active")
	local runtime = data.runtime
	local publisher = data.publisher
	if
		status == nil
		or (status :: BoundaryStatus).generation ~= data.boundaryGeneration
		or runtime == nil
		or publisher == nil
	then
		return finishRead(data, boundaryFailure(data, "submitSkipVote"))
	end
	local preflighted, preflightResult = callResult(publisher.preflightPublication, publisher)
	if not preflighted or not isSuccess(preflightResult) or (preflightResult :: any).value ~= true then
		return finishRead(data, boundaryFailure(data, "submitSkipVote"))
	end

	local called, runtimeResult = callResult(
		(runtime :: RuntimeAdapter).submitSkipVote,
		runtime,
		userIdValue,
		matchIdResult.value,
		waveNumberValue
	)
	if not called then
		return finishRead(data, boundaryFailure(data, "submitSkipVote"))
	end
	if not isSuccess(runtimeResult) then
		if not validRuntimeVoteFailure(runtimeResult) then
			return finishRead(data, boundaryFailure(data, "submitSkipVote"))
		end
		if not reconcileVoteFailureSnapshot(data, runtime :: RuntimeAdapter, publisher :: PublisherAdapter) then
			return finishRead(data, boundaryFailure(data, "submitSkipVote"))
		end
		return finishRead(data, runtimeResult)
	end

	local snapshot = canonicalRuntimeSnapshot((runtimeResult :: any).value, data)
	local expectedRevision = if data.lastQueuedWaveRevision < WaveProtocol.MAX_WAVE_REVISION
		then data.lastQueuedWaveRevision + 1
		else nil
	if
		snapshot == nil
		or expectedRevision == nil
		or (snapshot :: WaveProtocol.WaveSnapshot).waveRevision ~= expectedRevision
	then
		return finishRead(data, boundaryFailure(data, "submitSkipVote"))
	end
	local queued, queueResult = callResult(publisher.queueSnapshot, publisher, snapshot)
	if not queued or not isSuccess(queueResult) or (queueResult :: any).value ~= true then
		return finishRead(data, boundaryFailure(data, "submitSkipVote"))
	end
	data.lastQueuedWaveRevision = (snapshot :: WaveProtocol.WaveSnapshot).waveRevision
	return finishRead(data, Result.ok(snapshot))
end

function ServiceMethods.query(self: Service): unknown
	local data = requireData(self)
	if data.selection ~= nil and (data.selection :: Selection).kind == "Dormant" then
		return Result.ok(table.freeze({
			state = "Uninitialized",
			dormant = true,
			connectionCount = 0,
			boundaryCallbackCount = 0,
		}))
	end
	local operationError = beginRead(data, "query")
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime :: any
	local called, value = callNonYielding(runtime.query, runtime)
	if
		not called
		or type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
	then
		data.callbacksEnabled = false
		data.terminalState = "Faulted"
		data.state = "Failed"
		return finishRead(data, serviceFailure("INTERNAL_ERROR", "query"))
	end
	return finishRead(data, Result.ok(value))
end

function ServiceMethods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	local data = requireData(self)
	return data.serviceDefinition :: ServiceLifecycle.ServiceDefinition
end

function ServiceMethods.getMetrics(self: Service): ServiceMetrics
	local data = requireData(self)
	local runtimeMetrics = nil
	local runtime = data.runtime
	if runtime ~= nil then
		local called, value = callNonYielding(runtime.query, runtime)
		if called and type(value) == "table" and table.isfrozen(value :: any) then
			runtimeMetrics = value
		end
	end
	local publisherMetrics = nil
	local publisher = data.publisher
	if publisher ~= nil then
		local called, value = callNonYielding(publisher.getMetrics, publisher)
		if called and type(value) == "table" and table.isfrozen(value :: any) then
			publisherMetrics = value
		end
	end
	local dormant = data.selection ~= nil and (data.selection :: Selection).kind == "Dormant"
	return table.freeze({
		lifecycleState = data.state,
		dormant = dormant,
		connectionCount = 0,
		boundaryCallbackCount = if data.boundaryAdapter == nil then 0 else 1,
		callbacksEnabled = data.callbacksEnabled,
		operationActive = data.operationActive,
		retainsRuntime = data.runtime ~= nil,
		retainsPublisher = data.publisher ~= nil,
		retainsBoundary = data.boundaryHandle ~= nil or data.boundaryAdapter ~= nil,
		retainsConstructionDependencies = data.matchLifecycle ~= nil
			or data.baseRuntime ~= nil
			or data.enemySimulation ~= nil
			or data.configuration ~= nil
			or data.selection ~= nil
			or data.clock ~= nil
			or data.createRuntime ~= nil
			or data.createPublisher ~= nil
			or data.sender ~= nil
			or data.isStudio ~= nil
			or data.createRuntimeTrigger ~= nil
			or data.validateConfiguration ~= nil
			or data.durationClock ~= nil,
		boundaryGeneration = data.boundaryGeneration,
		lastEnemyPassOrdinal = data.lastEnemyPassOrdinal,
		lastFlushedPassOrdinal = data.lastFlushedPassOrdinal,
		terminalState = data.terminalState,
		runtime = runtimeMetrics,
		publisher = publisherMetrics,
		lastQueuedWaveRevision = data.lastQueuedWaveRevision,
		studioTriggerCount = if data.studioTrigger == nil then 0 else 1,
		studioActivationAttempted = data.studioActivationAttempted,
		studioActivated = data.studioActivated,
		studioScenario = data.studioScenario,
		studioValidationCount = data.studioValidationCount,
		studioOperationCount = data.studioOperationCount,
		studioAssertionCount = data.studioAssertionCount,
		studioAssertionFailureCount = data.studioAssertionFailureCount,
		studioSchedulerSampleCount = data.studioSchedulerSampleCount,
		studioLastSchedulerSeconds = data.studioLastSchedulerSeconds,
		studioMaximumSchedulerSeconds = data.studioMaximumSchedulerSeconds,
		studioMaximumSpawnLatenessSeconds = data.studioMaximumSpawnLatenessSeconds,
		studioEarlySpawnCount = data.studioEarlySpawnCount,
		studioSpawnEvidenceCount = #data.studioSpawnEvidence,
		studioTowerBoundaryCount = if data.studioTowerBoundaryAdapter == nil then 0 else 1,
		studioTowerPreparedTokenCount = if data.studioTowerPreparedToken == nil then 0 else 1,
		studioTowerBuildCount = data.studioTowerBuildCount,
		studioTowerPrepareCount = data.studioTowerPrepareCount,
		studioTowerCommitCount = data.studioTowerCommitCount,
		studioTowerDispatchCount = data.studioTowerDispatchCount,
		studioTowerDiagnosticsCount = data.studioTowerDiagnosticsCount,
		studioTowerCloseCount = data.studioTowerCloseCount,
	})
end

local function construct(
	matchLifecycleValue: unknown,
	baseRuntimeValue: unknown,
	enemySimulationValue: unknown,
	configurationValue: unknown,
	selectionValue: unknown,
	clockValue: unknown,
	createRuntimeValue: unknown,
	createPublisherValue: unknown,
	senderValue: unknown,
	isStudioValue: unknown,
	createRuntimeTriggerValue: unknown,
	validateConfigurationValue: unknown,
	durationClockValue: unknown
): Service
	if
		not hasMethods(matchLifecycleValue, LIFECYCLE_METHODS)
		or not hasMethods(baseRuntimeValue, BASE_METHODS)
		or not hasMethods(enemySimulationValue, ENEMY_METHODS)
		or not ConfigurationValidator.isValidatedConfiguration(configurationValue)
		or not isSelection(selectionValue)
		or type(clockValue) ~= "function"
		or type(createRuntimeValue) ~= "function"
		or type(createPublisherValue) ~= "function"
		or type(senderValue) ~= "function"
		or type(isStudioValue) ~= "function"
		or type(createRuntimeTriggerValue) ~= "function"
		or type(validateConfigurationValue) ~= "function"
		or type(durationClockValue) ~= "function"
	then
		staticError("INVALID_DEPENDENCIES")
	end

	local data: ServiceData = {
		state = "Constructed",
		matchLifecycle = matchLifecycleValue :: MatchLifecycleAdapter,
		baseRuntime = baseRuntimeValue :: BaseRuntimeAdapter,
		enemySimulation = enemySimulationValue :: EnemySimulationAdapter,
		configuration = configurationValue :: ConfigTypes.CoreConfiguration,
		selection = selectionValue :: Selection,
		clock = clockValue :: Clock,
		createRuntime = createRuntimeValue :: RuntimeFactory,
		createPublisher = createPublisherValue :: PublisherFactory,
		sender = senderValue :: WaveSender,
		isStudio = isStudioValue :: IsStudio,
		createRuntimeTrigger = createRuntimeTriggerValue :: CreateRuntimeTrigger,
		validateConfiguration = validateConfigurationValue :: ValidateConfiguration,
		durationClock = durationClockValue :: Clock,
		runtime = nil,
		publisher = nil,
		boundaryAdapter = nil,
		boundaryHandle = nil,
		matchId = nil,
		enemyEpoch = 0,
		mapId = nil,
		difficultyId = nil,
		totalWaves = 0,
		boundaryGeneration = 0,
		callbacksEnabled = false,
		operationActive = false,
		shutdownRequested = false,
		releasing = false,
		lastEnemyPassOrdinal = 0,
		lastFlushedPassOrdinal = 0,
		lastSampleServerTime = 0,
		lastQueuedWaveRevision = 0,
		terminalPublicationPending = false,
		terminalState = nil,
		recoverableFaultSnapshot = nil,
		studioTrigger = nil,
		studioTriggerOperationActive = false,
		studioActivationAttempted = false,
		studioActivated = false,
		studioScenario = nil,
		studioValidationCount = 0,
		studioOperationCount = 0,
		studioAssertionCount = 0,
		studioAssertionFailureCount = 0,
		studioSchedulerSampleCount = 0,
		studioLastSchedulerSeconds = 0,
		studioMaximumSchedulerSeconds = 0,
		studioMaximumSpawnLatenessSeconds = 0,
		studioEarlySpawnCount = 0,
		studioBaseCatalogPending = nil,
		studioRuntimeMapPending = nil,
		studioSpawnEvidence = {},
		studioTowerBoundaryAdapter = nil,
		studioTowerBoundaryHandle = nil,
		studioTowerOwnerToken = table.freeze({}),
		studioTowerIssuedHandles = setmetatable({}, { __mode = "k" }),
		studioTowerPreparedToken = nil,
		studioTowerCallbackActive = false,
		studioTowerReentryViolation = false,
		studioTowerBuildCount = 0,
		studioTowerPrepareCount = 0,
		studioTowerCommitCount = 0,
		studioTowerDispatchCount = 0,
		studioTowerDiagnosticsCount = 0,
		studioTowerCloseCount = 0,
		service = nil,
		serviceDefinition = nil,
	}
	local service = setmetatable({}, ServiceMethods) :: Service
	table.freeze(service)
	data.serviceDefinition = table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({ "NetworkRegistry", "MatchLifecycle", "BaseRuntime", "EnemySimulation" }),
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
	data.service = service
	return service
end

local function productionClock(): unknown
	return Workspace:GetServerTimeNow()
end

local function productionDurationClock(): unknown
	return os.clock()
end

local function productionIsStudio(): unknown
	return RunService:IsStudio()
end

local function productionValidateConfiguration(sources: unknown): unknown
	return ConfigurationValidator.validate(sources)
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

local function productionCreateRuntime(
	configuration: unknown,
	runtimeMap: unknown,
	matchId: unknown,
	enemyEpoch: unknown,
	difficultyId: unknown,
	dependencies: unknown
): unknown
	return WaveRuntime.new(configuration, runtimeMap, matchId, enemyEpoch, difficultyId, dependencies)
end

local function productionCreatePublisher(
	matchId: unknown,
	enemyEpoch: unknown,
	mapId: unknown,
	difficultyId: unknown,
	totalWaves: unknown,
	dependencies: unknown
): unknown
	return WaveReplicationPublisher.new(matchId, enemyEpoch, mapId, difficultyId, totalWaves, dependencies)
end

function WaveRuntimeService.new(
	matchLifecycle: MatchLifecycleAdapter,
	baseRuntime: BaseRuntimeAdapter,
	enemySimulation: EnemySimulationAdapter,
	configuration: ConfigTypes.CoreConfiguration,
	selectedDifficultyId: Ids.DifficultyId?,
	sender: WaveSender
): Service
	local selection: Selection = if selectedDifficultyId == nil
		then table.freeze({
			kind = "Dormant",
		})
		else table.freeze({
			kind = "AuthoredFinite",
			difficultyId = selectedDifficultyId,
		})
	return construct(
		matchLifecycle,
		baseRuntime,
		enemySimulation,
		configuration,
		selection,
		productionClock,
		productionCreateRuntime,
		productionCreatePublisher,
		sender,
		productionIsStudio,
		productionCreateRuntimeTrigger,
		productionValidateConfiguration,
		productionDurationClock
	)
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "WaveRuntimeService" then
		return false
	end
	local productionServerWaves = script.Parent
	if
		productionServerWaves == nil
		or not productionServerWaves:IsA("Folder")
		or productionServerWaves.Name ~= "ProductionServerWaves"
	then
		return false
	end
	local automatedTests = productionServerWaves.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	if automatedTests.Parent ~= ServerStorage then
		return false
	end
	return ServerScriptService:FindFirstChild("Server") == nil
end

function WaveRuntimeService.newForTests(dependencies: TestDependencies): Service
	if not testModuleIdentityIsExact() then
		staticError("TEST_CONSTRUCTOR_FORBIDDEN")
	end
	if
		type(dependencies) ~= "table"
		or getmetatable(dependencies :: any) ~= nil
		or not hasExactFields(dependencies :: { [any]: unknown }, TEST_DEPENDENCY_FIELDS)
	then
		staticError("INVALID_DEPENDENCIES")
	end
	local values = dependencies :: any
	return construct(
		values.matchLifecycle,
		values.baseRuntime,
		values.enemySimulation,
		values.configuration,
		values.selection,
		values.clock,
		values.createRuntime,
		values.createPublisher,
		values.sender,
		values.isStudio,
		values.createRuntimeTrigger,
		values.validateConfiguration,
		values.durationClock
	)
end

return table.freeze(WaveRuntimeService)
