--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local AssetSchema = require(ReplicatedStorage.Shared.config.AssetSchema)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local TowerSchema = require(ReplicatedStorage.Shared.config.TowerSchema)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local TemporaryLoadoutStore = require(script.Parent.TemporaryLoadoutStore)
local TowerGrayboxFactory = require(script.Parent.TowerGrayboxFactory)
local TowerModelContract = require(script.Parent.TowerModelContract)
local TowerModelOwner = require(script.Parent.TowerModelOwner)
local TowerRuntimeStore = require(script.Parent.TowerRuntimeStore)

export type LifecycleState =
	"Constructed"
	| "Initializing"
	| "Initialized"
	| "Starting"
	| "Started"
	| "ShuttingDown"
	| "Shutdown"
	| "Failed"

export type OwnershipState =
	"Dormant"
	| "AwaitingFixture"
	| "Preparing"
	| "Prepared"
	| "Configured"
	| "Faulted"
	| "Cleaned"

export type Operation =
	"buildStudioFixtureSources"
	| "prepareStudioConfiguration"
	| "commitStudioConfiguration"
	| "dispatchStudioEvidence"
	| "getStudioDiagnostics"
	| "closeFromWave"
	| "getLoadout"
	| "resolveOccupiedSlot"
	| "trustedCreate"
	| "get"
	| "list"
	| "trustedRemove"
	| "removeVisual"
	| "recreateVisual"
	| "cleanup"

export type ServiceError = {
	code: string,
	operation: Operation,
}

export type ParticipantObserverAdapter = {
	onSnapshot: (self: ParticipantObserverAdapter, snapshot: MatchProtocol.MatchSnapshot) -> unknown,
}

export type MatchLifecycleAdapter = {
	reserveParticipantObserver: (self: MatchLifecycleAdapter, adapter: unknown) -> unknown,
	refreshParticipantObserver: (self: MatchLifecycleAdapter, handle: unknown) -> unknown,
	activateParticipantObserver: (self: MatchLifecycleAdapter, handle: unknown, expectedRevision: unknown) -> unknown,
	detachParticipantObserver: (self: MatchLifecycleAdapter, handle: unknown) -> unknown,
}

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

export type WaveRuntimeAdapter = {
	installStudioTowerBoundary: (self: WaveRuntimeAdapter, adapter: unknown) -> unknown,
	detachStudioTowerBoundary: (self: WaveRuntimeAdapter, handle: unknown) -> unknown,
}

export type GrayboxFactoryAdapter = {
	createAllTemplates: (self: GrayboxFactoryAdapter) -> unknown,
	cleanup: (self: GrayboxFactoryAdapter) -> unknown,
	getState: (self: GrayboxFactoryAdapter) -> unknown,
}

export type ModelOwnerAdapter = {
	registerTemplate: (self: ModelOwnerAdapter, definition: unknown, model: unknown) -> unknown,
	prepareCreate: (self: ModelOwnerAdapter, snapshot: unknown) -> unknown,
	commitPreparedCreate: (self: ModelOwnerAdapter, token: unknown) -> unknown,
	abortPreparedCreate: (self: ModelOwnerAdapter, token: unknown) -> unknown,
	removeVisual: (self: ModelOwnerAdapter, runtimeTowerId: unknown) -> unknown,
	recreateVisual: (self: ModelOwnerAdapter, snapshot: unknown) -> unknown,
	getMetrics: (self: ModelOwnerAdapter) -> unknown,
	cleanup: (self: ModelOwnerAdapter) -> unknown,
}

export type LoadoutStoreAdapter = {
	synchronizeParticipants: (self: LoadoutStoreAdapter, snapshot: unknown) -> unknown,
	activate: (self: LoadoutStoreAdapter) -> unknown,
	getLoadout: (self: LoadoutStoreAdapter, userId: unknown) -> unknown,
	issueCreationCapability: (self: LoadoutStoreAdapter, userId: unknown, slot: unknown) -> unknown,
	prepareCreationCapability: (self: LoadoutStoreAdapter, capability: unknown) -> unknown,
	commitPreparedCapability: (self: LoadoutStoreAdapter, token: unknown) -> unknown,
	abortPreparedCapability: (self: LoadoutStoreAdapter, token: unknown) -> unknown,
	getPreparedCapabilityInspector: (self: LoadoutStoreAdapter) -> unknown,
	fault: (self: LoadoutStoreAdapter) -> unknown,
	getMetrics: (self: LoadoutStoreAdapter) -> unknown,
	cleanup: (self: LoadoutStoreAdapter) -> unknown,
}

export type RuntimeStoreAdapter = {
	prepareCreate: (
		self: RuntimeStoreAdapter,
		preparedCapability: unknown,
		expectedOwnerUserId: unknown,
		expectedSlot: unknown,
		placementCFrame: unknown
	) -> unknown,
	commitPreparedCreate: (self: RuntimeStoreAdapter, token: unknown) -> unknown,
	abortPreparedCreate: (self: RuntimeStoreAdapter, token: unknown) -> unknown,
	failPreparedCreate: (self: RuntimeStoreAdapter, token: unknown) -> unknown,
	get: (self: RuntimeStoreAdapter, runtimeTowerId: unknown) -> unknown,
	list: (self: RuntimeStoreAdapter) -> unknown,
	remove: (self: RuntimeStoreAdapter, runtimeTowerId: unknown) -> unknown,
	getIdentity: (self: RuntimeStoreAdapter) -> unknown,
	fault: (self: RuntimeStoreAdapter) -> unknown,
	getMetrics: (self: RuntimeStoreAdapter) -> unknown,
	cleanup: (self: RuntimeStoreAdapter) -> unknown,
}

export type CreateGrayboxFactory = (configuration: unknown) -> unknown
export type CreateModelOwner = (configuration: unknown, matchId: unknown, towerEpoch: unknown) -> unknown
export type CreateLoadoutStore = (
	configuration: unknown,
	matchId: unknown,
	towerEpoch: unknown,
	definitions: unknown
) -> unknown
export type CreateRuntimeStore = (
	matchId: unknown,
	towerEpoch: unknown,
	configuration: unknown,
	inspector: unknown
) -> unknown
export type IsStudio = () -> unknown

export type TestDependencies = {
	matchLifecycle: MatchLifecycleAdapter,
	waveRuntime: WaveRuntimeAdapter,
	productionConfiguration: ConfigTypes.CoreConfiguration,
	isStudio: IsStudio,
	createGrayboxFactory: CreateGrayboxFactory,
	createModelOwner: CreateModelOwner,
	createLoadoutStore: CreateLoadoutStore,
	createRuntimeStore: CreateRuntimeStore,
}

export type FixtureSources = {
	assets: { { [string]: any } },
	towers: { { [string]: any } },
}

export type ServiceMetrics = {
	lifecycleState: LifecycleState,
	ownershipState: OwnershipState,
	connectionCount: number,
	participantObserverCount: number,
	waveBoundaryCount: number,
	operationActive: boolean,
	admissionOpen: boolean,
	fixtureBuilt: boolean,
	configurationCommitted: boolean,
	participantRevision: number,
	capabilityExpectationCount: number,
	evidenceOperationCount: number,
	evidencePlacementCapRejectionCount: number,
	lastRuntimeTowerId: number?,
	retainsConstructionDependencies: boolean,
	retainsConfiguration: boolean,
	loadout: unknown?,
	runtime: unknown?,
	model: unknown?,
}

type PreparedConfigurationToken = {}

type PreparedConfiguration = {
	token: PreparedConfigurationToken,
	configuration: ConfigTypes.CoreConfiguration,
	matchId: Ids.MatchId,
	loadout: LoadoutStoreAdapter,
	runtime: RuntimeStoreAdapter,
	modelOwner: ModelOwnerAdapter,
	participantAdapter: ParticipantObserverAdapter,
	observerHandle: unknown,
	initialSnapshot: MatchProtocol.MatchSnapshot,
	initialRevision: number,
	prepareResult: Result.Success<PreparedConfigurationToken>,
	commitResult: Result.Success<boolean>,
}

type PreparationResources = {
	factory: GrayboxFactoryAdapter?,
	templates: { Model },
	loadout: LoadoutStoreAdapter?,
	runtime: RuntimeStoreAdapter?,
	modelOwner: ModelOwnerAdapter?,
	participantAdapter: ParticipantObserverAdapter?,
	observerHandle: unknown,
}

type CapabilityExpectation = {
	owner: ServiceData,
	generation: number,
	userId: number,
	slot: number,
}

type ServiceData = {
	state: LifecycleState,
	ownershipState: OwnershipState,
	matchLifecycle: MatchLifecycleAdapter?,
	waveRuntime: WaveRuntimeAdapter?,
	productionConfiguration: ConfigTypes.CoreConfiguration?,
	isStudio: IsStudio?,
	createGrayboxFactory: CreateGrayboxFactory?,
	createModelOwner: CreateModelOwner?,
	createLoadoutStore: CreateLoadoutStore?,
	createRuntimeStore: CreateRuntimeStore?,
	waveBoundaryAdapter: StudioTowerBoundaryAdapter?,
	waveBoundaryHandle: unknown,
	fixtureSources: FixtureSources?,
	fixtureBuilt: boolean,
	preparing: PreparationResources?,
	pending: PreparedConfiguration?,
	configuration: ConfigTypes.CoreConfiguration?,
	matchId: Ids.MatchId?,
	loadout: LoadoutStoreAdapter?,
	runtime: RuntimeStoreAdapter?,
	modelOwner: ModelOwnerAdapter?,
	participantAdapter: ParticipantObserverAdapter?,
	observerHandle: unknown,
	lastParticipantSnapshot: MatchProtocol.MatchSnapshot?,
	lastParticipantRevision: number,
	capabilityGeneration: number,
	capabilities: { [any]: boolean },
	capabilityExpectationCount: number,
	lastRuntimeTowerId: number?,
	evidenceOperationCount: number,
	evidenceCreateOrdinal: number,
	evidencePlacementCapRejectionCount: number,
	operationActive: boolean,
	reentryViolation: boolean,
	admissionOpen: boolean,
	shutdownRequested: boolean,
	releasing: boolean,
	serviceDefinition: ServiceLifecycle.ServiceDefinition?,
}

local SERVICE_NAME = "TowerRuntime"
local STATIC_ERROR_PREFIX = "[ATD_TOWER_RUNTIME_SERVICE]"
local TOWER_EPOCH = 1
local MAX_CAPABILITY_GENERATION = 4_096
local MAX_EVIDENCE_OPERATIONS = 10_000
local OCCUPIED_SLOT_COUNT = 3

local SINGLE_TOWER_ID = "tower:phase12-single"
local SPLASH_TOWER_ID = "tower:phase12-splash"
local SUPPORT_TOWER_ID = "tower:phase12-support"

local SINGLE_MODEL_ASSET_KEY = "test.phase12.single-model"
local SINGLE_ICON_ASSET_KEY = "test.phase12.single-icon"
local SPLASH_MODEL_ASSET_KEY = "test.phase12.splash-model"
local SPLASH_ICON_ASSET_KEY = "test.phase12.splash-icon"
local SUPPORT_MODEL_ASSET_KEY = "test.phase12.support-model"
local SUPPORT_ICON_ASSET_KEY = "test.phase12.support-icon"

local MATCH_METHODS = table.freeze({
	"reserveParticipantObserver",
	"refreshParticipantObserver",
	"activateParticipantObserver",
	"detachParticipantObserver",
})
local WAVE_METHODS = table.freeze({ "installStudioTowerBoundary", "detachStudioTowerBoundary" })
local FACTORY_METHODS = table.freeze({ "createAllTemplates", "cleanup", "getState" })
local MODEL_OWNER_METHODS = table.freeze({
	"registerTemplate",
	"prepareCreate",
	"commitPreparedCreate",
	"abortPreparedCreate",
	"removeVisual",
	"recreateVisual",
	"getMetrics",
	"cleanup",
})
local LOADOUT_METHODS = table.freeze({
	"synchronizeParticipants",
	"activate",
	"getLoadout",
	"issueCreationCapability",
	"prepareCreationCapability",
	"commitPreparedCapability",
	"abortPreparedCapability",
	"getPreparedCapabilityInspector",
	"fault",
	"getMetrics",
	"cleanup",
})
local RUNTIME_METHODS = table.freeze({
	"prepareCreate",
	"commitPreparedCreate",
	"abortPreparedCreate",
	"failPreparedCreate",
	"get",
	"list",
	"remove",
	"getIdentity",
	"fault",
	"getMetrics",
	"cleanup",
})

local TEST_DEPENDENCY_FIELDS = table.freeze({
	matchLifecycle = true,
	waveRuntime = true,
	productionConfiguration = true,
	isStudio = true,
	createGrayboxFactory = true,
	createModelOwner = true,
	createLoadoutStore = true,
	createRuntimeStore = true,
})
local PARTICIPANT_RESERVATION_FIELDS = table.freeze({
	handle = true,
	snapshot = true,
})
local TEMPLATE_SET_FIELDS = table.freeze({
	ordered = true,
	byTowerId = true,
})
local RESULT_FAILURE_FIELDS = table.freeze({
	ok = true,
	error = true,
})
local LOADOUT_ERROR_FIELDS = table.freeze({
	code = true,
	operation = true,
})

local FIXED_EVIDENCE_OPERATIONS = table.freeze({
	TowerCreateNext = true,
	TowerRemoveVisualLast = true,
	TowerRecreateVisualLast = true,
	TowerRemoveLast = true,
	TowerInvalidTemplate = true,
	TowerCleanup = true,
})

local ServiceMethods = {}
ServiceMethods.__index = ServiceMethods

export type Service = typeof(setmetatable({} :: {}, ServiceMethods))
export type TestConstructor = (dependencies: TestDependencies) -> Service

local SERVICE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local PREPARED_CONFIGURATION_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local CAPABILITY_EXPECTATIONS = setmetatable({}, { __mode = "k" }) :: { [any]: CapabilityExpectation }

local completeShutdown: ((data: ServiceData, raiseOnFailure: boolean) -> boolean)?

local CLOSE_TRUE: Result.Success<boolean> = Result.ok(true)
local CLOSE_FALSE: Result.Success<boolean> = Result.ok(false)
local CLEANED_RESIDUE = table.freeze({
	state = "Cleaned",
	participantObserverCount = 0,
	waveBoundaryCount = 0,
	loadoutCount = 0,
	unitIdCount = 0,
	runtimeTowerCount = 0,
	templateCount = 0,
	liveModelCount = 0,
	runtimeRootCount = 0,
	capabilityCount = 0,
	connectionCount = 0,
})
local CLEANED_RESIDUE_RESULT = Result.ok(CLEANED_RESIDUE)

local function staticError(code: string): never
	error(`{STATIC_ERROR_PREFIX}[code={code}]`, 0)
end

local function makeError(code: string, operation: Operation): ServiceError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: string, operation: Operation): Result.Failure<ServiceError>
	return Result.err(makeError(code, operation))
end

local function requireData(service: Service): ServiceData
	local data = SERVICE_DATA[service]
	if data == nil then
		staticError("INVALID_SERVICE")
	end
	return data :: ServiceData
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
	if (value :: any).ok == true and rawget(value :: any, "value") ~= nil then
		return true, value
	elseif (value :: any).ok == false and rawget(value :: any, "error") ~= nil then
		return true, value
	end
	return false, nil
end

local function isSuccess(value: unknown): boolean
	return type(value) == "table" and table.isfrozen(value :: any) and (value :: any).ok == true
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

local function hasExactFields(value: { [any]: unknown }, expected: { [string]: boolean }): boolean
	local count = 0
	for key in next, value do
		if type(key) ~= "string" or expected[key] ~= true then
			return false
		end
		count += 1
	end
	local expectedCount = 0
	for _ in expected do
		expectedCount += 1
	end
	return count == expectedCount
end

local function isOpaqueHandle(value: unknown): boolean
	return type(value) == "table"
		and table.isfrozen(value :: any)
		and getmetatable(value :: any) == nil
		and next(value :: any) == nil
end

local function deepFreeze(value: any, seen: { [any]: boolean }?)
	if type(value) ~= "table" or table.isfrozen(value) then
		return
	end
	local visited = seen or {}
	if visited[value] then
		return
	end
	visited[value] = true
	for key, child in next, value do
		deepFreeze(key, visited)
		deepFreeze(child, visited)
	end
	table.freeze(value)
end

local function deepEquivalent(left: any, right: any, seen: { [any]: any }?): boolean
	if left == right then
		return true
	end
	if type(left) ~= type(right) or type(left) ~= "table" then
		return false
	end
	local visited = seen or {}
	if visited[left] ~= nil then
		return visited[left] == right
	end
	visited[left] = right
	local count = 0
	for key, value in next, left do
		count += 1
		if not deepEquivalent(value, right[key], visited) then
			return false
		end
	end
	local rightCount = 0
	for _ in next, right do
		rightCount += 1
	end
	return count == rightCount
end

local function singleTower(): { [string]: any }
	return {
		id = SINGLE_TOWER_ID,
		displayName = "Phase 12 Single",
		description = "Authenticated single-target runtime fixture.",
		modelAssetKey = SINGLE_MODEL_ASSET_KEY,
		iconAssetKey = SINGLE_ICON_ASSET_KEY,
		placementCost = 125,
		footprintRadiusStuds = 1.5,
		placementCap = 2,
		supportedTargetModes = { "First", "Last" },
		defaultTargetMode = "First",
		levels = {
			{
				upgradeCost = 0,
				rangeStuds = 10,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-single" },
					damage = 8,
					cooldownSeconds = 1.25,
				},
			},
			{
				upgradeCost = 100,
				rangeStuds = 12,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-single" },
					damage = 14,
					cooldownSeconds = 0.75,
					statusEffects = { { kind = "StatusEffect", key = "status.phase12-marked" } },
				},
			},
			{
				upgradeCost = 0,
				rangeStuds = 11,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-single" },
					damage = 0,
					cooldownSeconds = 1,
				},
			},
		},
		tags = { "fixture.phase12", "role.single" },
		mergeProgression = { kind = "MergeProgression", key = "merge.phase12-single" },
	}
end

local function splashTower(): { [string]: any }
	return {
		id = SPLASH_TOWER_ID,
		displayName = "Phase 12 Splash",
		description = "Authenticated splash-capable metadata fixture.",
		modelAssetKey = SPLASH_MODEL_ASSET_KEY,
		iconAssetKey = SPLASH_ICON_ASSET_KEY,
		placementCost = 200,
		footprintRadiusStuds = 2.25,
		placementCap = 3,
		supportedTargetModes = { "Strongest", "Closest", "First" },
		defaultTargetMode = "Strongest",
		levels = {
			{
				upgradeCost = 0,
				rangeStuds = 8,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-splash" },
					damage = 12,
					cooldownSeconds = 2,
				},
			},
			{
				upgradeCost = 150,
				rangeStuds = 10,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-splash" },
					damage = 20,
					cooldownSeconds = 1.5,
				},
			},
			{
				upgradeCost = 250,
				rangeStuds = 13,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.phase12-splash" },
					damage = 35,
					cooldownSeconds = 1.25,
					statusEffects = { { kind = "StatusEffect", key = "status.phase12-slow" } },
				},
			},
		},
		tags = { "fixture.phase12", "role.splash" },
		mergeProgression = { kind = "MergeProgression", key = "merge.phase12-splash" },
	}
end

local function supportTower(): { [string]: any }
	return {
		id = SUPPORT_TOWER_ID,
		displayName = "Phase 12 Support",
		description = "Non-attacking support and economy metadata placeholder.",
		modelAssetKey = SUPPORT_MODEL_ASSET_KEY,
		iconAssetKey = SUPPORT_ICON_ASSET_KEY,
		placementCost = 100,
		footprintRadiusStuds = 1.75,
		placementCap = 1,
		supportedTargetModes = {},
		levels = {
			{ upgradeCost = 0, rangeStuds = 6 },
			{ upgradeCost = 75, rangeStuds = 8 },
			{ upgradeCost = 125, rangeStuds = 10 },
		},
		tags = { "fixture.phase12", "support.phase12", "economy.phase12" },
		mergeProgression = { kind = "MergeProgression", key = "merge.phase12-support" },
	}
end

local function makeFixtureSources(): FixtureSources
	local value: FixtureSources = {
		assets = {
			{ key = SINGLE_MODEL_ASSET_KEY, kind = "TowerModel" },
			{ key = SINGLE_ICON_ASSET_KEY, kind = "Icon" },
			{ key = SPLASH_MODEL_ASSET_KEY, kind = "TowerModel" },
			{ key = SPLASH_ICON_ASSET_KEY, kind = "Icon" },
			{ key = SUPPORT_MODEL_ASSET_KEY, kind = "TowerModel" },
			{ key = SUPPORT_ICON_ASSET_KEY, kind = "Icon" },
		},
		towers = { singleTower(), splashTower(), supportTower() },
	}
	deepFreeze(value)
	return value
end

local function canonicalFixtureConfiguration(
	configurationValue: unknown,
	fixtureSources: FixtureSources
): ConfigTypes.CoreConfiguration?
	if
		not ConfigurationValidator.isValidatedConfiguration(configurationValue)
		or not AssetSchema.isValidatedManifest((configurationValue :: any).assets)
		or not TowerSchema.isValidatedCatalog((configurationValue :: any).towers)
	then
		return nil
	end
	local configuration = configurationValue :: ConfigTypes.CoreConfiguration
	if #configuration.towers.ordered ~= OCCUPIED_SLOT_COUNT then
		return nil
	end
	for index, rawDefinition in fixtureSources.towers do
		local definition = configuration.towers.ordered[index]
		if
			definition == nil
			or configuration.towers.byId[definition.id] ~= definition
			or not deepEquivalent(rawDefinition, definition)
		then
			return nil
		end
	end
	for _, rawAsset in fixtureSources.assets do
		local asset = configuration.assets.byKey[rawAsset.key]
		if asset == nil or not deepEquivalent(rawAsset, asset) then
			return nil
		end
		local found = false
		for _, orderedAsset in configuration.assets.ordered do
			if orderedAsset == asset then
				found = true
				break
			end
		end
		if not found then
			return nil
		end
	end
	return configuration
end

local function beginOperation(data: ServiceData, operation: Operation, requireConfigured: boolean): ServiceError?
	if data.operationActive then
		data.reentryViolation = true
		return makeError("REENTRANT", operation)
	end
	if
		data.state ~= "Started"
		or data.ownershipState == "Faulted"
		or data.ownershipState == "Cleaned"
		or (requireConfigured and (data.ownershipState ~= "Configured" or not data.admissionOpen))
	then
		return makeError("UNAVAILABLE", operation)
	end
	data.operationActive = true
	data.reentryViolation = false
	return nil
end

local function operationIntact(data: ServiceData): boolean
	return data.operationActive and not data.reentryViolation and not data.shutdownRequested
end

local function finishOperation(data: ServiceData)
	data.operationActive = false
	data.reentryViolation = false
	if data.shutdownRequested then
		data.shutdownRequested = false
		local finalizer = completeShutdown
		if finalizer ~= nil then
			finalizer(data, false)
		end
	end
end

local function clearCapabilityExpectations(data: ServiceData)
	for capability in data.capabilities do
		local expectation = CAPABILITY_EXPECTATIONS[capability]
		if expectation ~= nil and expectation.owner == data then
			CAPABILITY_EXPECTATIONS[capability] = nil
		end
	end
	table.clear(data.capabilities)
	data.capabilityExpectationCount = 0
end

local function resultSucceeded(value: unknown, expectedBoolean: boolean?): boolean
	if not isSuccess(value) then
		return false
	end
	return expectedBoolean == nil or (value :: any).value == expectedBoolean
end

local function cleanupAdapter(adapter: unknown): boolean
	if type(adapter) ~= "table" or type((adapter :: any).cleanup) ~= "function" then
		return true
	end
	local called, resultValue = callResult((adapter :: any).cleanup, adapter)
	return called and isSuccess(resultValue) and type((resultValue :: any).value) == "boolean"
end

local function faultAdapter(adapter: unknown)
	if type(adapter) == "table" and type((adapter :: any).fault) == "function" then
		callResult((adapter :: any).fault, adapter)
	end
end

local function destroyTemplates(templates: { Model }): boolean
	local retainedCount = 0
	for _, model in templates do
		local called = callNonYielding(model.Destroy, model)
		if not called then
			retainedCount += 1
			templates[retainedCount] = model
		end
	end
	for index = #templates, retainedCount + 1, -1 do
		templates[index] = nil
	end
	return retainedCount == 0
end

local function runtimeResources(data: ServiceData): (
	LoadoutStoreAdapter?,
	RuntimeStoreAdapter?,
	ModelOwnerAdapter?,
	GrayboxFactoryAdapter?,
	{ Model },
	unknown
)
	local preparing = data.preparing
	local pending = data.pending
	local loadout = data.loadout
		or (if pending == nil then nil else pending.loadout)
		or (if preparing == nil then nil else preparing.loadout)
	local runtime = data.runtime
		or (if pending == nil then nil else pending.runtime)
		or (if preparing == nil then nil else preparing.runtime)
	local modelOwner = data.modelOwner
		or (if pending == nil then nil else pending.modelOwner)
		or (if preparing == nil then nil else preparing.modelOwner)
	local factory = if preparing == nil then nil else preparing.factory
	local templates = if preparing == nil then {} else preparing.templates
	local observerHandle = data.observerHandle
		or (if pending == nil then nil else pending.observerHandle)
		or (if preparing == nil then nil else preparing.observerHandle)
	return loadout, runtime, modelOwner, factory, templates, observerHandle
end

local function cleanupRuntimeResources(data: ServiceData): boolean
	if data.releasing then
		return false
	end
	data.releasing = true
	data.admissionOpen = false
	clearCapabilityExpectations(data)
	local loadout, runtime, modelOwner, factory, templates, observerHandle = runtimeResources(data)
	local allCleaned = true

	if observerHandle ~= nil then
		local matchLifecycle = data.matchLifecycle
		local detached = false
		local detachResult: unknown = nil
		if matchLifecycle ~= nil then
			detached, detachResult =
				callResult(matchLifecycle.detachParticipantObserver, matchLifecycle, observerHandle)
		end
		if not detached or not isSuccess(detachResult) or type((detachResult :: any).value) ~= "boolean" then
			allCleaned = false
		else
			data.observerHandle = nil
			if data.preparing ~= nil then
				(data.preparing :: PreparationResources).observerHandle = nil
			end
		end
	end

	faultAdapter(loadout)
	faultAdapter(runtime)
	if not cleanupAdapter(modelOwner) then
		allCleaned = false
	end
	if not cleanupAdapter(runtime) then
		allCleaned = false
	end
	if not cleanupAdapter(loadout) then
		allCleaned = false
	end
	if not cleanupAdapter(factory) then
		allCleaned = false
	end
	if not destroyTemplates(templates) then
		allCleaned = false
	end

	if allCleaned then
		local pending = data.pending
		if pending ~= nil then
			PREPARED_CONFIGURATION_DATA[pending.token] = nil
		end
		data.preparing = nil
		data.pending = nil
		data.configuration = nil
		data.matchId = nil
		data.loadout = nil
		data.runtime = nil
		data.modelOwner = nil
		data.participantAdapter = nil
		data.observerHandle = nil
		data.lastParticipantSnapshot = nil
		data.lastParticipantRevision = 0
		data.lastRuntimeTowerId = nil
	end
	data.releasing = false
	return allCleaned
end

local function clearConstructionDependencies(data: ServiceData)
	data.matchLifecycle = nil
	data.waveRuntime = nil
	data.productionConfiguration = nil
	data.isStudio = nil
	data.createGrayboxFactory = nil
	data.createModelOwner = nil
	data.createLoadoutStore = nil
	data.createRuntimeStore = nil
	data.fixtureSources = nil
	data.waveBoundaryAdapter = nil
	data.waveBoundaryHandle = nil
end

completeShutdown = function(data: ServiceData, raiseOnFailure: boolean): boolean
	data.state = "ShuttingDown"
	data.admissionOpen = false
	local boundaryDetached = true
	local waveHandle = data.waveBoundaryHandle
	local waveRuntime = data.waveRuntime
	if waveHandle ~= nil then
		local called = false
		local resultValue: unknown = nil
		if waveRuntime ~= nil then
			called, resultValue = callResult(waveRuntime.detachStudioTowerBoundary, waveRuntime, waveHandle)
		end
		boundaryDetached = called and resultSucceeded(resultValue, true)
		if boundaryDetached then
			data.waveBoundaryHandle = nil
			data.waveBoundaryAdapter = nil
		end
	end
	local cleaned = cleanupRuntimeResources(data)
	if not boundaryDetached or not cleaned then
		data.state = "Failed"
		data.ownershipState = "Faulted"
		if raiseOnFailure then
			staticError("CLEANUP_FAILED")
		end
		return false
	end
	clearConstructionDependencies(data)
	data.ownershipState = "Cleaned"
	data.state = "Shutdown"
	return true
end

local function faultRuntime(data: ServiceData)
	data.admissionOpen = false
	data.ownershipState = "Faulted"
	clearCapabilityExpectations(data)
	faultAdapter(data.loadout)
	faultAdapter(data.runtime)
end

local function operationInterruptedFailure(data: ServiceData, operation: Operation): Result.Failure<ServiceError>
	local code = if data.reentryViolation then "REENTRANT" else "UNAVAILABLE"
	faultRuntime(data)
	return failure(code, operation)
end

local function closeFromWaveData(data: ServiceData): Result.Result<boolean, ServiceError>
	-- Wave invalidates its retained handle on every close response, including a
	-- malformed or failed response. Mirror that invalidation before doing work.
	data.waveBoundaryHandle = nil
	data.waveBoundaryAdapter = nil
	if data.ownershipState == "Cleaned" then
		return CLOSE_FALSE
	end
	if data.operationActive then
		data.reentryViolation = true
		return failure("REENTRANT", "closeFromWave")
	end
	data.operationActive = true
	data.reentryViolation = false
	data.admissionOpen = false
	local cleaned = cleanupRuntimeResources(data)
	if not cleaned then
		data.ownershipState = "Faulted"
		local resultValue = failure("CLEANUP_FAILED", "closeFromWave")
		finishOperation(data)
		return resultValue
	end
	clearConstructionDependencies(data)
	data.ownershipState = "Cleaned"
	finishOperation(data)
	return CLOSE_TRUE
end

local function participantSnapshot(value: unknown, expectedMatchId: Ids.MatchId): MatchProtocol.MatchSnapshot?
	local resultValue = MatchProtocol.validateMatchSnapshot(value)
	if not resultValue.ok then
		return nil
	end
	local snapshot = resultValue.value
	if snapshot.matchId ~= expectedMatchId then
		return nil
	end
	return snapshot
end

local function handleParticipantSnapshot(data: ServiceData, value: unknown): boolean
	if data.operationActive then
		data.reentryViolation = true
		faultRuntime(data)
		return false
	end
	if data.state ~= "Started" or data.ownershipState ~= "Configured" or not data.admissionOpen then
		return false
	end
	local matchId = data.matchId
	local loadout = data.loadout
	if matchId == nil or loadout == nil then
		faultRuntime(data)
		return false
	end
	data.operationActive = true
	data.reentryViolation = false
	local snapshot = participantSnapshot(value, matchId)
	if snapshot == nil or snapshot.revision <= data.lastParticipantRevision then
		faultRuntime(data)
		finishOperation(data)
		return false
	end
	local called, syncResult = callResult(loadout.synchronizeParticipants, loadout, snapshot)
	if not called or not isSuccess(syncResult) or not operationIntact(data) then
		faultRuntime(data)
		finishOperation(data)
		return false
	end
	data.lastParticipantSnapshot = snapshot
	data.lastParticipantRevision = snapshot.revision
	finishOperation(data)
	return true
end

local function makeParticipantAdapter(data: ServiceData): ParticipantObserverAdapter
	local adapter: ParticipantObserverAdapter
	adapter = table.freeze({
		onSnapshot = function(self: ParticipantObserverAdapter, snapshot: MatchProtocol.MatchSnapshot): unknown
			if self ~= adapter then
				return false
			end
			return handleParticipantSnapshot(data, snapshot)
		end,
	})
	return adapter
end

local function failPreparation(data: ServiceData, code: string, operation: Operation): Result.Failure<ServiceError>
	cleanupRuntimeResources(data)
	data.fixtureSources = nil
	data.fixtureBuilt = false
	if not data.shutdownRequested then
		data.ownershipState = "Faulted"
	end
	return failure(code, operation)
end

local function finishFailedPreparation(
	data: ServiceData,
	code: string,
	operation: Operation
): Result.Failure<ServiceError>
	local resultValue = failPreparation(data, code, operation)
	finishOperation(data)
	return resultValue
end

local function templateSet(value: unknown, configuration: ConfigTypes.CoreConfiguration): ({ Model }?, { Model })
	local owned: { Model } = {}
	local seen: { [Instance]: boolean } = {}
	local ordered = if type(value) == "table" and getmetatable(value :: any) == nil
		then rawget(value :: any, "ordered")
		else nil
	local byTowerId = if type(value) == "table" and getmetatable(value :: any) == nil
		then rawget(value :: any, "byTowerId")
		else nil
	local function collectOwned(collection: unknown)
		if type(collection) == "table" and getmetatable(collection :: any) == nil then
			for _, candidate in next, collection :: any do
				if
					typeof(candidate) == "Instance"
					and (candidate :: Instance):IsA("Model")
					and seen[candidate :: Instance] ~= true
				then
					seen[candidate :: Instance] = true
					table.insert(owned, candidate :: Model)
				end
			end
		end
	end
	collectOwned(ordered)
	collectOwned(byTowerId)
	if
		type(value) ~= "table"
		or not table.isfrozen(value :: any)
		or getmetatable(value :: any) ~= nil
		or not hasExactFields(value :: { [any]: unknown }, TEMPLATE_SET_FIELDS)
		or type(ordered) ~= "table"
		or not table.isfrozen(ordered)
		or getmetatable(ordered) ~= nil
		or type(byTowerId) ~= "table"
		or not table.isfrozen(byTowerId)
		or getmetatable(byTowerId) ~= nil
		or #ordered ~= OCCUPIED_SLOT_COUNT
	then
		return nil, owned
	end
	local orderedCount = 0
	for key in next, ordered do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > OCCUPIED_SLOT_COUNT then
			return nil, owned
		end
		orderedCount += 1
	end
	if orderedCount ~= OCCUPIED_SLOT_COUNT then
		return nil, owned
	end
	local byIdCount = 0
	for key in next, byTowerId do
		if type(key) ~= "string" or configuration.towers.byId[key] == nil then
			return nil, owned
		end
		byIdCount += 1
	end
	if byIdCount ~= OCCUPIED_SLOT_COUNT then
		return nil, owned
	end
	local templates: { Model } = {}
	for index, definition in configuration.towers.ordered do
		local model = rawget(ordered, index)
		if
			typeof(model) ~= "Instance"
			or not (model :: Instance):IsA("Model")
			or rawget(byTowerId, definition.id) ~= model
		then
			return nil, owned
		end
		templates[index] = model :: Model
	end
	return templates, owned
end

local function prepareStudioConfiguration(
	data: ServiceData,
	configurationValue: unknown,
	matchIdValue: unknown
): unknown
	local operation: Operation = "prepareStudioConfiguration"
	local operationError = beginOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if data.ownershipState ~= "AwaitingFixture" or not data.fixtureBuilt or data.fixtureSources == nil then
		finishOperation(data)
		return failure("WRONG_STATE", operation)
	end
	data.ownershipState = "Preparing"
	local context: PreparationResources = {
		factory = nil,
		templates = {},
		loadout = nil,
		runtime = nil,
		modelOwner = nil,
		participantAdapter = nil,
		observerHandle = nil,
	}
	data.preparing = context
	local configuration = canonicalFixtureConfiguration(configurationValue, data.fixtureSources :: FixtureSources)
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if configuration == nil or not matchIdResult.ok then
		return finishFailedPreparation(data, "UNAUTHENTICATED_CONFIGURATION", operation)
	end
	local matchId = matchIdResult.value

	local createFactory = data.createGrayboxFactory :: CreateGrayboxFactory
	local factoryCalled, factoryResult = callResult(createFactory, configuration)
	local factory = if factoryCalled and isSuccess(factoryResult) then (factoryResult :: any).value else nil
	if not hasMethods(factory, FACTORY_METHODS) or not operationIntact(data) then
		return finishFailedPreparation(data, "FACTORY_FAILED", operation)
	end
	context.factory = factory :: GrayboxFactoryAdapter
	local templatesCalled, templatesResult = callResult((factory :: any).createAllTemplates, factory)
	local templates: { Model }? = nil
	local ownedTemplates: { Model } = {}
	if templatesCalled and isSuccess(templatesResult) then
		templates, ownedTemplates = templateSet((templatesResult :: any).value, configuration)
	end
	context.templates = ownedTemplates
	if templates == nil or not operationIntact(data) then
		return finishFailedPreparation(data, "TEMPLATE_CREATION_FAILED", operation)
	end

	local createOwner = data.createModelOwner :: CreateModelOwner
	local ownerCalled, ownerResult = callResult(createOwner, configuration, matchId, TOWER_EPOCH)
	local owner = if ownerCalled and isSuccess(ownerResult) then (ownerResult :: any).value else nil
	if not hasMethods(owner, MODEL_OWNER_METHODS) or not operationIntact(data) then
		return finishFailedPreparation(data, "MODEL_OWNER_FAILED", operation)
	end
	context.modelOwner = owner :: ModelOwnerAdapter
	for index, definition in configuration.towers.ordered do
		local registered, registerResult =
			callResult((owner :: any).registerTemplate, owner, definition, templates[index])
		if not registered or not resultSucceeded(registerResult, true) or not operationIntact(data) then
			return finishFailedPreparation(data, "TEMPLATE_REGISTRATION_FAILED", operation)
		end
	end
	local templatesDestroyed = destroyTemplates(context.templates)
	local factoryCleaned = cleanupAdapter(factory)
	if not templatesDestroyed or not factoryCleaned or not operationIntact(data) then
		return finishFailedPreparation(data, "TEMPLATE_RELEASE_FAILED", operation)
	end
	context.factory = nil

	local createLoadout = data.createLoadoutStore :: CreateLoadoutStore
	local loadoutCalled, loadoutResult =
		callResult(createLoadout, configuration, matchId, TOWER_EPOCH, configuration.towers.ordered)
	local loadout = if loadoutCalled and isSuccess(loadoutResult) then (loadoutResult :: any).value else nil
	if not hasMethods(loadout, LOADOUT_METHODS) or not operationIntact(data) then
		return finishFailedPreparation(data, "LOADOUT_CREATION_FAILED", operation)
	end
	context.loadout = loadout :: LoadoutStoreAdapter
	local inspectorCalled, inspectorResult = callResult((loadout :: any).getPreparedCapabilityInspector, loadout)
	local inspector = if inspectorCalled and isSuccess(inspectorResult) then (inspectorResult :: any).value else nil
	if type(inspector) ~= "function" or not operationIntact(data) then
		return finishFailedPreparation(data, "CAPABILITY_INSPECTOR_FAILED", operation)
	end

	local createRuntime = data.createRuntimeStore :: CreateRuntimeStore
	local runtimeCalled, runtimeResult = callResult(createRuntime, matchId, TOWER_EPOCH, configuration, inspector)
	local runtime = if runtimeCalled and isSuccess(runtimeResult) then (runtimeResult :: any).value else nil
	if not hasMethods(runtime, RUNTIME_METHODS) or not operationIntact(data) then
		return finishFailedPreparation(data, "RUNTIME_CREATION_FAILED", operation)
	end
	context.runtime = runtime :: RuntimeStoreAdapter

	local participantAdapter = makeParticipantAdapter(data)
	context.participantAdapter = participantAdapter
	local matchLifecycle = data.matchLifecycle :: MatchLifecycleAdapter
	local reserved, reservationResult =
		callResult(matchLifecycle.reserveParticipantObserver, matchLifecycle, participantAdapter)
	local reservation = if reserved and isSuccess(reservationResult) then (reservationResult :: any).value else nil
	local reservationValid = type(reservation) == "table"
		and table.isfrozen(reservation :: any)
		and getmetatable(reservation :: any) == nil
		and hasExactFields(reservation :: { [any]: unknown }, PARTICIPANT_RESERVATION_FIELDS)
	local rawObserverHandle = if type(reservation) == "table" and getmetatable(reservation :: any) == nil
		then rawget(reservation :: any, "handle")
		else nil
	local observerHandle = if isOpaqueHandle(rawObserverHandle) then rawObserverHandle else nil
	context.observerHandle = observerHandle
	local initialSnapshot = if reservationValid
		then participantSnapshot(rawget(reservation :: any, "snapshot"), matchId)
		else nil
	if
		not reservationValid
		or initialSnapshot == nil
		or not isOpaqueHandle(observerHandle)
		or not operationIntact(data)
	then
		return finishFailedPreparation(data, "OBSERVER_RESERVATION_FAILED", operation)
	end
	local synchronized, synchronizeResult =
		callResult((loadout :: any).synchronizeParticipants, loadout, initialSnapshot)
	if not synchronized or not isSuccess(synchronizeResult) or not operationIntact(data) then
		return finishFailedPreparation(data, "PARTICIPANT_SYNCHRONIZATION_FAILED", operation)
	end

	local token = table.freeze({}) :: PreparedConfigurationToken
	local prepareResult = Result.ok(token)
	local commitResult: Result.Success<boolean> = Result.ok(true)
	local pending: PreparedConfiguration = table.freeze({
		token = token,
		configuration = configuration,
		matchId = matchId,
		loadout = loadout :: LoadoutStoreAdapter,
		runtime = runtime :: RuntimeStoreAdapter,
		modelOwner = owner :: ModelOwnerAdapter,
		participantAdapter = participantAdapter,
		observerHandle = observerHandle,
		initialSnapshot = initialSnapshot,
		initialRevision = initialSnapshot.revision,
		prepareResult = prepareResult,
		commitResult = commitResult,
	})
	data.preparing = nil
	data.pending = pending
	data.fixtureSources = nil
	data.ownershipState = "Prepared"
	PREPARED_CONFIGURATION_DATA[token] = data
	finishOperation(data)
	return pending.prepareResult
end

local function commitStudioConfiguration(data: ServiceData, tokenValue: unknown): unknown
	local operation: Operation = "commitStudioConfiguration"
	local operationError = beginOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local pending = data.pending
	if
		data.ownershipState ~= "Prepared"
		or pending == nil
		or tokenValue ~= pending.token
		or PREPARED_CONFIGURATION_DATA[pending.token] ~= data
	then
		finishOperation(data)
		return failure("INVALID_TOKEN", operation)
	end
	local matchLifecycle = data.matchLifecycle :: MatchLifecycleAdapter
	local refreshed, refreshResult =
		callResult(matchLifecycle.refreshParticipantObserver, matchLifecycle, pending.observerHandle)
	local snapshot = if refreshed and isSuccess(refreshResult)
		then participantSnapshot((refreshResult :: any).value, pending.matchId)
		else nil
	if snapshot == nil or snapshot.revision < pending.initialRevision or not operationIntact(data) then
		return finishFailedPreparation(data, "OBSERVER_REFRESH_FAILED", operation)
	end
	if snapshot.revision > pending.initialRevision then
		local synchronized, synchronizeResult =
			callResult(pending.loadout.synchronizeParticipants, pending.loadout, snapshot)
		if not synchronized or not isSuccess(synchronizeResult) or not operationIntact(data) then
			return finishFailedPreparation(data, "PARTICIPANT_SYNCHRONIZATION_FAILED", operation)
		end
	end
	local loadoutActivated, loadoutActivationResult = callResult(pending.loadout.activate, pending.loadout)
	if not loadoutActivated or not resultSucceeded(loadoutActivationResult, true) or not operationIntact(data) then
		return finishFailedPreparation(data, "LOADOUT_ACTIVATION_FAILED", operation)
	end
	local observerActivated, observerActivationResult = callResult(
		matchLifecycle.activateParticipantObserver,
		matchLifecycle,
		pending.observerHandle,
		snapshot.revision
	)
	if not observerActivated or not resultSucceeded(observerActivationResult, true) or not operationIntact(data) then
		return finishFailedPreparation(data, "OBSERVER_ACTIVATION_FAILED", operation)
	end

	-- Everything below this line is the pre-reserved, no-fail local configuration
	-- commit. Its public Result was allocated before observer reservation.
	PREPARED_CONFIGURATION_DATA[pending.token] = nil
	data.configuration = pending.configuration
	data.matchId = pending.matchId
	data.loadout = pending.loadout
	data.runtime = pending.runtime
	data.modelOwner = pending.modelOwner
	data.participantAdapter = pending.participantAdapter
	data.observerHandle = pending.observerHandle
	data.lastParticipantSnapshot = snapshot
	data.lastParticipantRevision = snapshot.revision
	data.pending = nil
	data.ownershipState = "Configured"
	data.admissionOpen = true
	finishOperation(data)
	return pending.commitResult
end

local function buildStudioFixtureSources(data: ServiceData): unknown
	local operation: Operation = "buildStudioFixtureSources"
	local operationError = beginOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if data.ownershipState ~= "AwaitingFixture" or data.fixtureBuilt then
		finishOperation(data)
		return failure("WRONG_STATE", operation)
	end
	local sources = makeFixtureSources()
	local resultValue = Result.ok(sources)
	data.fixtureSources = sources
	data.fixtureBuilt = true
	finishOperation(data)
	return resultValue
end

local function beginConfiguredOperation(data: ServiceData, operation: Operation): ServiceError?
	return beginOperation(data, operation, true)
end

local function serviceStoreFailure(
	data: ServiceData,
	adapter: unknown,
	called: boolean,
	storeResult: unknown,
	operation: Operation
): Result.Failure<ServiceError>
	if not called then
		faultRuntime(data)
		return failure("INTERNAL_ERROR", operation)
	end
	local errorValue = if type(storeResult) == "table" and (storeResult :: any).ok == false
		then (storeResult :: any).error
		else nil
	local code = if type(errorValue) == "table" and table.isfrozen(errorValue :: any)
		then (errorValue :: any).code
		else nil
	if type(code) ~= "string" then
		faultRuntime(data)
		return failure("INTERNAL_ERROR", operation)
	end

	local metricsMethod = if type(adapter) == "table" then (adapter :: any).getMetrics else nil
	if type(metricsMethod) ~= "function" then
		faultRuntime(data)
		return failure("INTERNAL_ERROR", operation)
	end
	local metricsCalled, metricsValue = callNonYielding(metricsMethod, adapter)
	if not operationIntact(data) then
		return operationInterruptedFailure(data, operation)
	end
	if
		not metricsCalled
		or type(metricsValue) ~= "table"
		or not table.isfrozen(metricsValue :: any)
		or type((metricsValue :: any).faulted) ~= "boolean"
		or type((metricsValue :: any).cleaned) ~= "boolean"
	then
		faultRuntime(data)
		return failure("INTERNAL_ERROR", operation)
	end
	if (metricsValue :: any).faulted or (metricsValue :: any).cleaned then
		-- A child store may discover a fatal callback/counter/identity fault before
		-- returning its bounded error. Adopt that state immediately so no sibling
		-- store or previously issued capability remains usable.
		faultRuntime(data)
	end
	return failure(code, operation)
end

local function issueCapabilityCore(data: ServiceData, userId: unknown, slot: unknown): unknown
	local loadout = data.loadout :: LoadoutStoreAdapter
	if data.capabilityGeneration >= MAX_CAPABILITY_GENERATION then
		faultRuntime(data)
		return failure("CAPABILITY_EXHAUSTED", "resolveOccupiedSlot")
	end
	local called, resultValue = callResult(loadout.issueCreationCapability, loadout, userId, slot)
	if not operationIntact(data) then
		return operationInterruptedFailure(data, "resolveOccupiedSlot")
	end
	if not called or not isSuccess(resultValue) then
		return serviceStoreFailure(data, loadout, called, resultValue, "resolveOccupiedSlot")
	end
	local capability = (resultValue :: any).value
	if type(capability) ~= "table" or not table.isfrozen(capability) then
		faultRuntime(data)
		return failure("INTERNAL_ERROR", "resolveOccupiedSlot")
	end
	data.capabilityGeneration += 1
	CAPABILITY_EXPECTATIONS[capability] = {
		owner = data,
		generation = data.capabilityGeneration,
		userId = userId :: number,
		slot = slot :: number,
	}
	data.capabilities[capability] = true
	data.capabilityExpectationCount += 1
	return resultValue
end

local function consumeExpectation(data: ServiceData, capability: unknown): CapabilityExpectation?
	if type(capability) ~= "table" then
		return nil
	end
	local expectation = CAPABILITY_EXPECTATIONS[capability :: any]
	if expectation == nil or expectation.owner ~= data or data.capabilities[capability :: any] ~= true then
		return nil
	end
	CAPABILITY_EXPECTATIONS[capability :: any] = nil
	data.capabilities[capability :: any] = nil
	data.capabilityExpectationCount -= 1
	return expectation
end

local function impossibleFinalizerFailure(data: ServiceData): Result.Failure<ServiceError>
	faultRuntime(data)
	cleanupRuntimeResources(data)
	data.ownershipState = "Faulted"
	return failure("FINALIZER_FAILED", "trustedCreate")
end

local function trustedCreateCore(data: ServiceData, capability: unknown, placementCFrame: unknown): unknown
	local expectation = consumeExpectation(data, capability)
	if expectation == nil then
		return failure("INVALID_CAPABILITY", "trustedCreate")
	end
	local loadout = data.loadout :: LoadoutStoreAdapter
	local runtime = data.runtime :: RuntimeStoreAdapter
	local modelOwner = data.modelOwner :: ModelOwnerAdapter
	local capPrepared, capPrepareResult = callResult(loadout.prepareCreationCapability, loadout, capability)
	if not operationIntact(data) then
		if capPrepared and isSuccess(capPrepareResult) then
			callResult(loadout.abortPreparedCapability, loadout, (capPrepareResult :: any).value)
		end
		return operationInterruptedFailure(data, "trustedCreate")
	end
	if not capPrepared or not isSuccess(capPrepareResult) then
		return serviceStoreFailure(data, loadout, capPrepared, capPrepareResult, "trustedCreate")
	end
	local capabilityToken = (capPrepareResult :: any).value
	local runtimePrepared, runtimePrepareResult = callResult(
		runtime.prepareCreate,
		runtime,
		capabilityToken,
		expectation.userId,
		expectation.slot,
		placementCFrame
	)
	if not operationIntact(data) then
		if runtimePrepared and isSuccess(runtimePrepareResult) then
			local interruptedRuntime = (runtimePrepareResult :: any).value
			if type(interruptedRuntime) == "table" and (interruptedRuntime :: any).token ~= nil then
				callResult(runtime.failPreparedCreate, runtime, (interruptedRuntime :: any).token)
			end
		end
		callResult(loadout.abortPreparedCapability, loadout, capabilityToken)
		return operationInterruptedFailure(data, "trustedCreate")
	end
	if not runtimePrepared or not isSuccess(runtimePrepareResult) then
		local aborted, abortResult = callResult(loadout.abortPreparedCapability, loadout, capabilityToken)
		if not operationIntact(data) then
			return operationInterruptedFailure(data, "trustedCreate")
		end
		if not aborted or not resultSucceeded(abortResult, true) then
			faultRuntime(data)
			return failure("CAPABILITY_ABORT_FAILED", "trustedCreate")
		end
		return serviceStoreFailure(data, runtime, runtimePrepared, runtimePrepareResult, "trustedCreate")
	end
	local preparedRuntime = (runtimePrepareResult :: any).value
	local runtimeToken = if type(preparedRuntime) == "table" then (preparedRuntime :: any).token else nil
	local plannedSnapshot = if type(preparedRuntime) == "table" then (preparedRuntime :: any).plannedSnapshot else nil
	if runtimeToken == nil or plannedSnapshot == nil then
		callResult(loadout.abortPreparedCapability, loadout, capabilityToken)
		faultRuntime(data)
		return failure("INTERNAL_ERROR", "trustedCreate")
	end
	local visualPrepared, visualPrepareResult = callResult(modelOwner.prepareCreate, modelOwner, plannedSnapshot)
	if not operationIntact(data) then
		if visualPrepared and isSuccess(visualPrepareResult) then
			local interruptedVisual = (visualPrepareResult :: any).value
			if type(interruptedVisual) == "table" and (interruptedVisual :: any).token ~= nil then
				callResult(modelOwner.abortPreparedCreate, modelOwner, (interruptedVisual :: any).token)
			end
		end
		callResult(runtime.failPreparedCreate, runtime, runtimeToken)
		callResult(loadout.abortPreparedCapability, loadout, capabilityToken)
		return operationInterruptedFailure(data, "trustedCreate")
	end
	if not visualPrepared or not isSuccess(visualPrepareResult) then
		callResult(runtime.failPreparedCreate, runtime, runtimeToken)
		callResult(loadout.abortPreparedCapability, loadout, capabilityToken)
		faultRuntime(data)
		return failure("MODEL_PREPARE_FAILED", "trustedCreate")
	end
	local preparedVisual = (visualPrepareResult :: any).value
	local visualToken = if type(preparedVisual) == "table" then (preparedVisual :: any).token else nil
	if visualToken == nil then
		callResult(runtime.failPreparedCreate, runtime, runtimeToken)
		callResult(loadout.abortPreparedCapability, loadout, capabilityToken)
		faultRuntime(data)
		return failure("MODEL_PREPARE_FAILED", "trustedCreate")
	end

	-- The accepted RuntimeTower record is committed last. All three results were
	-- allocated by their prepare steps; successful finalizers perform no engine work.
	local capabilityCommitted, capabilityCommitResult =
		callResult(loadout.commitPreparedCapability, loadout, capabilityToken)
	if not operationIntact(data) or not capabilityCommitted or not resultSucceeded(capabilityCommitResult, true) then
		callResult(modelOwner.abortPreparedCreate, modelOwner, visualToken)
		callResult(runtime.failPreparedCreate, runtime, runtimeToken)
		return impossibleFinalizerFailure(data)
	end
	local visualCommitted, visualCommitResult = callResult(modelOwner.commitPreparedCreate, modelOwner, visualToken)
	if not operationIntact(data) then
		callResult(modelOwner.removeVisual, modelOwner, (plannedSnapshot :: any).runtimeTowerId)
		callResult(runtime.failPreparedCreate, runtime, runtimeToken)
		return impossibleFinalizerFailure(data)
	elseif not visualCommitted or not isSuccess(visualCommitResult) then
		callResult(runtime.failPreparedCreate, runtime, runtimeToken)
		return impossibleFinalizerFailure(data)
	end
	local runtimeCommitted, runtimeCommitResult = callResult(runtime.commitPreparedCreate, runtime, runtimeToken)
	if not operationIntact(data) then
		callResult(modelOwner.removeVisual, modelOwner, (plannedSnapshot :: any).runtimeTowerId)
		if runtimeCommitted and isSuccess(runtimeCommitResult) then
			callResult(runtime.remove, runtime, (plannedSnapshot :: any).runtimeTowerId)
		else
			callResult(runtime.failPreparedCreate, runtime, runtimeToken)
		end
		return impossibleFinalizerFailure(data)
	elseif not runtimeCommitted or not isSuccess(runtimeCommitResult) then
		callResult(modelOwner.removeVisual, modelOwner, (plannedSnapshot :: any).runtimeTowerId)
		callResult(runtime.failPreparedCreate, runtime, runtimeToken)
		return impossibleFinalizerFailure(data)
	end
	local snapshot = (runtimeCommitResult :: any).value
	data.lastRuntimeTowerId = if type(snapshot) == "table" then (snapshot :: any).runtimeTowerId else nil
	return runtimeCommitResult
end

local function configuredStoreRead(data: ServiceData, methodName: string, argument: unknown?): unknown
	local runtime = data.runtime :: any
	local called = false
	local resultValue: unknown = nil
	if argument == nil then
		called, resultValue = callResult(runtime[methodName], runtime)
	else
		called, resultValue = callResult(runtime[methodName], runtime, argument)
	end
	local operation: Operation = if methodName == "list" then "list" else "get"
	if not operationIntact(data) then
		return operationInterruptedFailure(data, operation)
	elseif not called or not isSuccess(resultValue) then
		return serviceStoreFailure(data, runtime, called, resultValue, operation)
	end
	return resultValue
end

local function removeVisualCore(data: ServiceData, runtimeTowerId: unknown): unknown
	local runtime = data.runtime :: RuntimeStoreAdapter
	local modelOwner = data.modelOwner :: ModelOwnerAdapter
	local found, getResult = callResult(runtime.get, runtime, runtimeTowerId)
	if not operationIntact(data) then
		return operationInterruptedFailure(data, "removeVisual")
	end
	if not found or not isSuccess(getResult) then
		return serviceStoreFailure(data, runtime, found, getResult, "removeVisual")
	end
	local removed, removeResult = callResult(modelOwner.removeVisual, modelOwner, runtimeTowerId)
	if not operationIntact(data) then
		return operationInterruptedFailure(data, "removeVisual")
	end
	if not removed or not isSuccess(removeResult) then
		faultRuntime(data)
		return failure("MODEL_REMOVE_FAILED", "removeVisual")
	end
	return removeResult
end

local function recreateVisualCore(data: ServiceData, runtimeTowerId: unknown): unknown
	local runtime = data.runtime :: RuntimeStoreAdapter
	local modelOwner = data.modelOwner :: ModelOwnerAdapter
	local found, getResult = callResult(runtime.get, runtime, runtimeTowerId)
	if not operationIntact(data) then
		return operationInterruptedFailure(data, "recreateVisual")
	end
	if not found or not isSuccess(getResult) then
		return serviceStoreFailure(data, runtime, found, getResult, "recreateVisual")
	end
	local recreated, recreateResult = callResult(modelOwner.recreateVisual, modelOwner, (getResult :: any).value)
	if not operationIntact(data) then
		return operationInterruptedFailure(data, "recreateVisual")
	end
	if not recreated or not isSuccess(recreateResult) then
		faultRuntime(data)
		return failure("MODEL_RECREATE_FAILED", "recreateVisual")
	end
	return recreateResult
end

local function trustedRemoveCore(data: ServiceData, runtimeTowerId: unknown): unknown
	local runtime = data.runtime :: RuntimeStoreAdapter
	local modelOwner = data.modelOwner :: ModelOwnerAdapter
	local found, getResult = callResult(runtime.get, runtime, runtimeTowerId)
	if not operationIntact(data) then
		return operationInterruptedFailure(data, "trustedRemove")
	end
	if not found or not isSuccess(getResult) then
		return serviceStoreFailure(data, runtime, found, getResult, "trustedRemove")
	end
	local visualRemoved, visualResult = callResult(modelOwner.removeVisual, modelOwner, runtimeTowerId)
	if not operationIntact(data) then
		return operationInterruptedFailure(data, "trustedRemove")
	end
	local visualAccepted = visualRemoved and isSuccess(visualResult)
	local removed, removeResult = callResult(runtime.remove, runtime, runtimeTowerId)
	if not operationIntact(data) then
		return operationInterruptedFailure(data, "trustedRemove")
	end
	if not removed or not isSuccess(removeResult) then
		faultRuntime(data)
		return failure("RUNTIME_REMOVE_FAILED", "trustedRemove")
	end
	if data.lastRuntimeTowerId == runtimeTowerId then
		data.lastRuntimeTowerId = nil
	end
	if not visualAccepted then
		faultRuntime(data)
		return failure("MODEL_REMOVE_FAILED", "trustedRemove")
	end
	return removeResult
end

local function activeParticipantUserIds(data: ServiceData): { number }
	local snapshot = data.lastParticipantSnapshot
	local users: { number } = {}
	if snapshot ~= nil then
		for _, participant in snapshot.participants do
			if participant.state == "Active" then
				table.insert(users, participant.userId)
			end
		end
	end
	table.sort(users)
	return users
end

local function selectUnauthorizedLoadoutUserId(data: ServiceData): number?
	local snapshot = data.lastParticipantSnapshot
	if snapshot == nil then
		return nil
	end
	local participantUserIds: { [number]: boolean } = {}
	for _, participant in snapshot.participants do
		participantUserIds[participant.userId] = true
	end
	-- MatchSnapshot bounds participants to four entries. Checking one more
	-- candidate than the participant count guarantees an absent safe UserId.
	for offset = 0, #snapshot.participants do
		local userId = Validation.MAX_SAFE_INTEGER - offset
		if userId ~= 0 and Validation.isSafeInteger(userId) and participantUserIds[userId] ~= true then
			return userId
		end
	end
	return nil
end

local function isExactUnauthorizedLoadoutFailure(value: unknown): boolean
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
		and hasExactFields(errorValue :: any, LOADOUT_ERROR_FIELDS)
		and (errorValue :: any).code == "NOT_FOUND"
		and (errorValue :: any).operation == "getLoadout"
end

local function createNextEvidence(data: ServiceData): unknown
	local users = activeParticipantUserIds(data)
	if #users == 0 then
		return failure("NO_ACTIVE_PARTICIPANT", "dispatchStudioEvidence")
	end
	if data.evidenceCreateOrdinal >= MAX_EVIDENCE_OPERATIONS then
		return failure("EVIDENCE_EXHAUSTED", "dispatchStudioEvidence")
	end
	data.evidenceCreateOrdinal += 1
	local ordinal = data.evidenceCreateOrdinal
	local slot = ((ordinal - 1) % OCCUPIED_SLOT_COUNT) + 1
	local userIndex = (math.floor((ordinal - 1) / OCCUPIED_SLOT_COUNT) % #users) + 1
	local userId = users[userIndex]
	local issued = issueCapabilityCore(data, userId, slot)
	if not isSuccess(issued) then
		return issued
	end
	local x = ((ordinal - 1) % 16) * 6
	local z = math.floor((ordinal - 1) / 16) * 6
	local created = trustedCreateCore(data, (issued :: any).value, CFrame.new(x, 0, z))
	if not isSuccess(created) then
		local errorCode = if type(created) == "table" and type((created :: any).error) == "table"
			then (created :: any).error.code
			else nil
		if errorCode == "PLACEMENT_CAP_EXCEEDED" then
			data.evidencePlacementCapRejectionCount += 1
			return Result.ok(table.freeze({
				operation = "TowerCreateNext",
				accepted = false,
				reason = "PlacementCapExceeded",
				attempt = ordinal,
				userId = userId,
				slot = slot,
			}))
		end
		return created
	end
	return Result.ok(table.freeze({
		operation = "TowerCreateNext",
		accepted = true,
		attempt = ordinal,
		userId = userId,
		slot = slot,
		runtimeTower = (created :: any).value,
	}))
end

local function invalidTemplateEvidence(data: ServiceData): unknown
	local configuration = data.configuration :: ConfigTypes.CoreConfiguration
	local definition = configuration.towers.ordered[1]
	local model = Instance.new("Model")
	model.Name = "Tower"
	local called, validationResult =
		callNonYielding(TowerModelContract.validateTemplate, configuration, definition, model)
	local destroyed = callNonYielding(model.Destroy, model)
	if
		not called
		or not destroyed
		or type(validationResult) ~= "table"
		or (validationResult :: any).ok ~= false
		or type((validationResult :: any).error) ~= "table"
	then
		faultRuntime(data)
		return failure("INVALID_TEMPLATE_PROBE_FAILED", "dispatchStudioEvidence")
	end
	return Result.ok(table.freeze({
		operation = "TowerInvalidTemplate",
		accepted = false,
		code = (validationResult :: any).error.code,
	}))
end

local function studioDiagnostics(data: ServiceData): unknown
	local operation: Operation = "getStudioDiagnostics"
	local operationError = beginConfiguredOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime :: RuntimeStoreAdapter
	local loadout = data.loadout :: LoadoutStoreAdapter
	local modelOwner = data.modelOwner :: ModelOwnerAdapter
	local listed, listResult = callResult(runtime.list, runtime)
	if not operationIntact(data) then
		local interrupted = operationInterruptedFailure(data, operation)
		finishOperation(data)
		return interrupted
	end
	local runtimeMetricsCalled, runtimeMetrics = callNonYielding(runtime.getMetrics, runtime)
	if not operationIntact(data) then
		local interrupted = operationInterruptedFailure(data, operation)
		finishOperation(data)
		return interrupted
	end
	local loadoutMetricsCalled, loadoutMetrics = callNonYielding(loadout.getMetrics, loadout)
	if not operationIntact(data) then
		local interrupted = operationInterruptedFailure(data, operation)
		finishOperation(data)
		return interrupted
	end
	local modelMetricsCalled, modelMetrics = callNonYielding(modelOwner.getMetrics, modelOwner)
	if not operationIntact(data) then
		local interrupted = operationInterruptedFailure(data, operation)
		finishOperation(data)
		return interrupted
	end
	local users = activeParticipantUserIds(data)
	local loadouts = {}
	for _, userId in users do
		local called, loadoutResult = callResult(loadout.getLoadout, loadout, userId)
		if not operationIntact(data) then
			local interrupted = operationInterruptedFailure(data, operation)
			finishOperation(data)
			return interrupted
		elseif not called or not isSuccess(loadoutResult) then
			faultRuntime(data)
			finishOperation(data)
			return failure("DIAGNOSTICS_FAILED", operation)
		end
		table.insert(loadouts, (loadoutResult :: any).value)
	end
	local unauthorizedUserId = selectUnauthorizedLoadoutUserId(data)
	if unauthorizedUserId == nil then
		faultRuntime(data)
		finishOperation(data)
		return failure("DIAGNOSTICS_FAILED", operation)
	end
	local unauthorizedCalled, unauthorizedResult = callResult(loadout.getLoadout, loadout, unauthorizedUserId)
	if not operationIntact(data) then
		local interrupted = operationInterruptedFailure(data, operation)
		finishOperation(data)
		return interrupted
	elseif not unauthorizedCalled or not isExactUnauthorizedLoadoutFailure(unauthorizedResult) then
		faultRuntime(data)
		finishOperation(data)
		return failure("DIAGNOSTICS_FAILED", operation)
	end
	local unauthorizedLoadout = table.freeze({
		userId = unauthorizedUserId,
		accepted = false,
		code = "NOT_FOUND",
		operation = "getLoadout",
	})
	table.freeze(users)
	table.freeze(loadouts)
	if
		not listed
		or not isSuccess(listResult)
		or not runtimeMetricsCalled
		or type(runtimeMetrics) ~= "table"
		or not table.isfrozen(runtimeMetrics :: any)
		or not loadoutMetricsCalled
		or type(loadoutMetrics) ~= "table"
		or not table.isfrozen(loadoutMetrics :: any)
		or not modelMetricsCalled
		or type(modelMetrics) ~= "table"
		or not table.isfrozen(modelMetrics :: any)
		or not operationIntact(data)
	then
		faultRuntime(data)
		finishOperation(data)
		return failure("DIAGNOSTICS_FAILED", operation)
	end
	local diagnostics = table.freeze({
		state = data.ownershipState,
		matchId = data.matchId,
		towerEpoch = TOWER_EPOCH,
		participantRevision = data.lastParticipantRevision,
		participantUserIds = users,
		loadouts = loadouts,
		unauthorizedLoadout = unauthorizedLoadout,
		runtimeTowers = (listResult :: any).value,
		loadout = loadoutMetrics,
		runtime = runtimeMetrics,
		model = modelMetrics,
		lastRuntimeTowerId = data.lastRuntimeTowerId,
		capabilityCount = data.capabilityExpectationCount,
		connectionCount = 0,
		participantObserverCount = if data.observerHandle == nil then 0 else 1,
		waveBoundaryCount = if data.waveBoundaryHandle == nil then 0 else 1,
		evidenceOperationCount = data.evidenceOperationCount,
		evidencePlacementCapRejectionCount = data.evidencePlacementCapRejectionCount,
	})
	local resultValue = Result.ok(diagnostics)
	finishOperation(data)
	return resultValue
end

local function dispatchStudioEvidence(data: ServiceData, fixedOperation: unknown): unknown
	local operation: Operation = "dispatchStudioEvidence"
	if type(fixedOperation) ~= "string" or FIXED_EVIDENCE_OPERATIONS[fixedOperation] ~= true then
		return failure("INVALID_ARGUMENT", operation)
	end
	if fixedOperation == "TowerCleanup" then
		if data.state ~= "Started" or data.ownershipState == "Cleaned" then
			return failure("UNAVAILABLE", operation)
		end
		data.evidenceOperationCount += 1
		local closed = closeFromWaveData(data)
		return if closed.ok then CLEANED_RESIDUE_RESULT else closed
	end
	local operationError = beginConfiguredOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if data.evidenceOperationCount >= MAX_EVIDENCE_OPERATIONS then
		finishOperation(data)
		return failure("EVIDENCE_EXHAUSTED", operation)
	end
	data.evidenceOperationCount += 1
	local resultValue: unknown
	if fixedOperation == "TowerCreateNext" then
		resultValue = createNextEvidence(data)
	elseif fixedOperation == "TowerRemoveVisualLast" then
		local runtimeTowerId = data.lastRuntimeTowerId
		resultValue = if runtimeTowerId == nil
			then failure("NOT_FOUND", operation)
			else removeVisualCore(data, runtimeTowerId)
	elseif fixedOperation == "TowerRecreateVisualLast" then
		local runtimeTowerId = data.lastRuntimeTowerId
		resultValue = if runtimeTowerId == nil
			then failure("NOT_FOUND", operation)
			else recreateVisualCore(data, runtimeTowerId)
	elseif fixedOperation == "TowerRemoveLast" then
		local runtimeTowerId = data.lastRuntimeTowerId
		resultValue = if runtimeTowerId == nil
			then failure("NOT_FOUND", operation)
			else trustedRemoveCore(data, runtimeTowerId)
	else
		resultValue = invalidTemplateEvidence(data)
	end
	finishOperation(data)
	return resultValue
end

local function makeWaveBoundaryAdapter(data: ServiceData): StudioTowerBoundaryAdapter
	local adapter: StudioTowerBoundaryAdapter
	adapter = table.freeze({
		buildStudioFixtureSources = function(self: StudioTowerBoundaryAdapter): unknown
			if self ~= adapter then
				return failure("INVALID_ADAPTER", "buildStudioFixtureSources")
			end
			return buildStudioFixtureSources(data)
		end,
		prepareStudioConfiguration = function(
			self: StudioTowerBoundaryAdapter,
			canonicalRoot: unknown,
			matchId: unknown
		): unknown
			if self ~= adapter then
				return failure("INVALID_ADAPTER", "prepareStudioConfiguration")
			end
			return prepareStudioConfiguration(data, canonicalRoot, matchId)
		end,
		commitStudioConfiguration = function(self: StudioTowerBoundaryAdapter, token: unknown): unknown
			if self ~= adapter then
				return failure("INVALID_ADAPTER", "commitStudioConfiguration")
			end
			return commitStudioConfiguration(data, token)
		end,
		dispatchStudioEvidence = function(self: StudioTowerBoundaryAdapter, fixedOperation: unknown): unknown
			if self ~= adapter then
				return failure("INVALID_ADAPTER", "dispatchStudioEvidence")
			end
			return dispatchStudioEvidence(data, fixedOperation)
		end,
		getStudioDiagnostics = function(self: StudioTowerBoundaryAdapter): unknown
			if self ~= adapter then
				return failure("INVALID_ADAPTER", "getStudioDiagnostics")
			end
			return studioDiagnostics(data)
		end,
		closeFromWave = function(self: StudioTowerBoundaryAdapter): unknown
			if self ~= adapter then
				return failure("INVALID_ADAPTER", "closeFromWave")
			end
			return closeFromWaveData(data)
		end,
	})
	return adapter
end

local function initialize(data: ServiceData)
	if data.state ~= "Constructed" then
		staticError("INVALID_STATE")
	end
	data.state = "Initializing"
	local configuration = data.productionConfiguration
	if
		configuration == nil
		or not ConfigurationValidator.isValidatedConfiguration(configuration)
		or not AssetSchema.isValidatedManifest(configuration.assets)
		or not TowerSchema.isValidatedCatalog(configuration.towers)
		or #configuration.assets.ordered ~= 0
		or #configuration.towers.ordered ~= 0
	then
		data.state = "Failed"
		data.ownershipState = "Faulted"
		staticError("PRODUCTION_CONFIGURATION_INVALID")
	end
	data.state = "Initialized"
end

local function start(data: ServiceData)
	if data.state ~= "Initialized" then
		staticError("INVALID_STATE")
	end
	data.state = "Starting"
	local isStudio = data.isStudio :: IsStudio
	local studioCalled, studioValue = callNonYielding(isStudio)
	if not studioCalled or type(studioValue) ~= "boolean" then
		data.state = "Failed"
		data.ownershipState = "Faulted"
		staticError("STUDIO_CHECK_FAILED")
	end
	data.isStudio = nil
	if not studioValue then
		clearConstructionDependencies(data)
		data.ownershipState = "Dormant"
		data.state = "Started"
		return
	end
	local adapter = makeWaveBoundaryAdapter(data)
	local waveRuntime = data.waveRuntime :: WaveRuntimeAdapter
	local installed, installResult = callResult(waveRuntime.installStudioTowerBoundary, waveRuntime, adapter)
	local handle = if installed and isSuccess(installResult) then (installResult :: any).value else nil
	if not isOpaqueHandle(handle) then
		data.state = "Failed"
		data.ownershipState = "Faulted"
		staticError("WAVE_BOUNDARY_INSTALL_FAILED")
	end
	data.waveBoundaryAdapter = adapter
	data.waveBoundaryHandle = handle
	data.ownershipState = "AwaitingFixture"
	data.state = "Started"
end

local function shutdown(data: ServiceData)
	if data.state == "Shutdown" then
		return
	end
	if data.state == "ShuttingDown" then
		if data.operationActive then
			data.shutdownRequested = true
		end
		return
	end
	if data.state ~= "Initialized" and data.state ~= "Started" and data.state ~= "Failed" then
		staticError("INVALID_STATE")
	end
	data.state = "ShuttingDown"
	data.admissionOpen = false
	if data.operationActive then
		data.shutdownRequested = true
		return
	end
	local finalizer = completeShutdown
	if finalizer == nil then
		staticError("CLEANUP_FAILED")
	end
	(finalizer :: (ServiceData, boolean) -> boolean)(data, true)
end

function ServiceMethods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	return requireData(self).serviceDefinition :: ServiceLifecycle.ServiceDefinition
end

function ServiceMethods.getLifecycleState(self: Service): LifecycleState
	return requireData(self).state
end

function ServiceMethods.getLoadout(self: Service, userId: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "getLoadout"
	local operationError = beginConfiguredOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local loadout = data.loadout :: LoadoutStoreAdapter
	local called, resultValue = callResult(loadout.getLoadout, loadout, userId)
	if not operationIntact(data) then
		local interrupted = operationInterruptedFailure(data, operation)
		finishOperation(data)
		return interrupted
	end
	local response = if called and isSuccess(resultValue)
		then resultValue
		else serviceStoreFailure(data, loadout, called, resultValue, operation)
	finishOperation(data)
	return response
end

function ServiceMethods.resolveOccupiedSlot(self: Service, userId: unknown, slot: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "resolveOccupiedSlot"
	local operationError = beginConfiguredOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local resultValue = issueCapabilityCore(data, userId, slot)
	finishOperation(data)
	return resultValue
end

function ServiceMethods.trustedCreate(self: Service, capability: unknown, placementCFrame: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "trustedCreate"
	local operationError = beginConfiguredOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local resultValue = trustedCreateCore(data, capability, placementCFrame)
	finishOperation(data)
	return resultValue
end

function ServiceMethods.get(self: Service, runtimeTowerId: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "get"
	local operationError = beginConfiguredOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local resultValue = configuredStoreRead(data, "get", runtimeTowerId)
	finishOperation(data)
	return resultValue
end

function ServiceMethods.list(self: Service): unknown
	local data = requireData(self)
	local operation: Operation = "list"
	local operationError = beginConfiguredOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local resultValue = configuredStoreRead(data, "list", nil)
	finishOperation(data)
	return resultValue
end

function ServiceMethods.trustedRemove(self: Service, runtimeTowerId: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "trustedRemove"
	local operationError = beginConfiguredOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local resultValue = trustedRemoveCore(data, runtimeTowerId)
	finishOperation(data)
	return resultValue
end

function ServiceMethods.removeVisual(self: Service, runtimeTowerId: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "removeVisual"
	local operationError = beginConfiguredOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local resultValue = removeVisualCore(data, runtimeTowerId)
	finishOperation(data)
	return resultValue
end

function ServiceMethods.recreateVisual(self: Service, runtimeTowerId: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "recreateVisual"
	local operationError = beginConfiguredOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local resultValue = recreateVisualCore(data, runtimeTowerId)
	finishOperation(data)
	return resultValue
end

local function readMetrics(adapter: unknown): unknown?
	if type(adapter) ~= "table" or type((adapter :: any).getMetrics) ~= "function" then
		return nil
	end
	local called, value = callNonYielding((adapter :: any).getMetrics, adapter)
	if not called or type(value) ~= "table" or not table.isfrozen(value :: any) then
		return nil
	end
	return value
end

function ServiceMethods.getMetrics(self: Service): ServiceMetrics
	local data = requireData(self)
	local pending = data.pending
	local preparing = data.preparing
	local loadout = data.loadout
		or (if pending == nil then nil else pending.loadout)
		or (if preparing == nil then nil else preparing.loadout)
	local runtime = data.runtime
		or (if pending == nil then nil else pending.runtime)
		or (if preparing == nil then nil else preparing.runtime)
	local modelOwner = data.modelOwner
		or (if pending == nil then nil else pending.modelOwner)
		or (if preparing == nil then nil else preparing.modelOwner)
	return table.freeze({
		lifecycleState = data.state,
		ownershipState = data.ownershipState,
		connectionCount = 0,
		participantObserverCount = if data.observerHandle ~= nil
				or (pending ~= nil and pending.observerHandle ~= nil)
			then 1
			else 0,
		waveBoundaryCount = if data.waveBoundaryHandle == nil then 0 else 1,
		operationActive = data.operationActive,
		admissionOpen = data.admissionOpen,
		fixtureBuilt = data.fixtureBuilt,
		configurationCommitted = data.ownershipState == "Configured",
		participantRevision = data.lastParticipantRevision,
		capabilityExpectationCount = data.capabilityExpectationCount,
		evidenceOperationCount = data.evidenceOperationCount,
		evidencePlacementCapRejectionCount = data.evidencePlacementCapRejectionCount,
		lastRuntimeTowerId = data.lastRuntimeTowerId,
		retainsConstructionDependencies = data.matchLifecycle ~= nil
			or data.waveRuntime ~= nil
			or data.productionConfiguration ~= nil
			or data.createGrayboxFactory ~= nil
			or data.createModelOwner ~= nil
			or data.createLoadoutStore ~= nil
			or data.createRuntimeStore ~= nil,
		retainsConfiguration = data.configuration ~= nil or pending ~= nil,
		loadout = readMetrics(loadout),
		runtime = readMetrics(runtime),
		model = readMetrics(modelOwner),
	})
end

local function construct(
	matchLifecycleValue: unknown,
	waveRuntimeValue: unknown,
	productionConfigurationValue: unknown,
	isStudioValue: unknown,
	createGrayboxFactoryValue: unknown,
	createModelOwnerValue: unknown,
	createLoadoutStoreValue: unknown,
	createRuntimeStoreValue: unknown
): Service
	if
		not hasMethods(matchLifecycleValue, MATCH_METHODS)
		or not hasMethods(waveRuntimeValue, WAVE_METHODS)
		or not ConfigurationValidator.isValidatedConfiguration(productionConfigurationValue)
		or type(isStudioValue) ~= "function"
		or type(createGrayboxFactoryValue) ~= "function"
		or type(createModelOwnerValue) ~= "function"
		or type(createLoadoutStoreValue) ~= "function"
		or type(createRuntimeStoreValue) ~= "function"
	then
		staticError("INVALID_DEPENDENCIES")
	end
	local data: ServiceData = {
		state = "Constructed",
		ownershipState = "Dormant",
		matchLifecycle = matchLifecycleValue :: MatchLifecycleAdapter,
		waveRuntime = waveRuntimeValue :: WaveRuntimeAdapter,
		productionConfiguration = productionConfigurationValue :: ConfigTypes.CoreConfiguration,
		isStudio = isStudioValue :: IsStudio,
		createGrayboxFactory = createGrayboxFactoryValue :: CreateGrayboxFactory,
		createModelOwner = createModelOwnerValue :: CreateModelOwner,
		createLoadoutStore = createLoadoutStoreValue :: CreateLoadoutStore,
		createRuntimeStore = createRuntimeStoreValue :: CreateRuntimeStore,
		waveBoundaryAdapter = nil,
		waveBoundaryHandle = nil,
		fixtureSources = nil,
		fixtureBuilt = false,
		preparing = nil,
		pending = nil,
		configuration = nil,
		matchId = nil,
		loadout = nil,
		runtime = nil,
		modelOwner = nil,
		participantAdapter = nil,
		observerHandle = nil,
		lastParticipantSnapshot = nil,
		lastParticipantRevision = 0,
		capabilityGeneration = 0,
		capabilities = {},
		capabilityExpectationCount = 0,
		lastRuntimeTowerId = nil,
		evidenceOperationCount = 0,
		evidenceCreateOrdinal = 0,
		evidencePlacementCapRejectionCount = 0,
		operationActive = false,
		reentryViolation = false,
		admissionOpen = false,
		shutdownRequested = false,
		releasing = false,
		serviceDefinition = nil,
	}
	local service = setmetatable({}, ServiceMethods) :: Service
	table.freeze(service)
	data.serviceDefinition = table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({ "NetworkRegistry", "MatchLifecycle", "WaveRuntime" }),
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

local function productionIsStudio(): unknown
	return RunService:IsStudio()
end

local function productionCreateGrayboxFactory(configuration: unknown): unknown
	return TowerGrayboxFactory.new(configuration)
end

local function productionCreateModelOwner(configuration: unknown, matchId: unknown, towerEpoch: unknown): unknown
	return TowerModelOwner.new(configuration, matchId, towerEpoch)
end

local function productionCreateLoadoutStore(
	configuration: unknown,
	matchId: unknown,
	towerEpoch: unknown,
	definitions: unknown
): unknown
	return TemporaryLoadoutStore.new(configuration, matchId, towerEpoch, definitions)
end

local function productionCreateRuntimeStore(
	matchId: unknown,
	towerEpoch: unknown,
	configuration: unknown,
	inspector: unknown
): unknown
	return TowerRuntimeStore.new(matchId, towerEpoch, configuration, inspector)
end

local TowerRuntimeService = {}

function TowerRuntimeService.new(
	matchLifecycle: MatchLifecycleAdapter,
	waveRuntime: WaveRuntimeAdapter,
	productionConfiguration: ConfigTypes.CoreConfiguration
): Service
	return construct(
		matchLifecycle,
		waveRuntime,
		productionConfiguration,
		productionIsStudio,
		productionCreateGrayboxFactory,
		productionCreateModelOwner,
		productionCreateLoadoutStore,
		productionCreateRuntimeStore
	)
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "TowerRuntimeService" then
		return false
	end
	local productionServerTowers = script.Parent
	if
		productionServerTowers == nil
		or not productionServerTowers:IsA("Folder")
		or productionServerTowers.Name ~= "ProductionServerTowers"
	then
		return false
	end
	local automatedTests = productionServerTowers.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	return automatedTests.Parent == ServerStorage
		and automatedTests:FindFirstChild("Support") ~= nil
		and ServerScriptService:FindFirstChild("Server") == nil
end

function TowerRuntimeService.newForTests(dependencies: TestDependencies): Service
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
		values.waveRuntime,
		values.productionConfiguration,
		values.isStudio,
		values.createGrayboxFactory,
		values.createModelOwner,
		values.createLoadoutStore,
		values.createRuntimeStore
	)
end

return table.freeze(TowerRuntimeService)
