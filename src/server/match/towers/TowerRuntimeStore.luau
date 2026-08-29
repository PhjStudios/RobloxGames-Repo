--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local AssetSchema = require(ReplicatedStorage.Shared.config.AssetSchema)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local TowerSchema = require(ReplicatedStorage.Shared.config.TowerSchema)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type RuntimeTowerId = number
export type TowerEpoch = number
export type RuntimeTowerLifecycle = "Active"
export type RemovedTowerLifecycle = "Removed"
export type TargetEligibility = "AllEligibleEnemies"

export type RuntimeTowerSnapshot = {
	matchId: Ids.MatchId,
	towerEpoch: TowerEpoch,
	runtimeTowerId: RuntimeTowerId,
	ownerUserId: number,
	towerId: Ids.TowerId,
	unitId: Ids.UnitId,
	level: number,
	targetMode: ConfigTypes.TargetMode?,
	targetEligibility: TargetEligibility,
	placementCFrame: CFrame,
	totalInvestment: number,
	cooldownEndsServerTime: number,
	lifecycle: RuntimeTowerLifecycle,
}

export type RemovedTowerSnapshot = {
	matchId: Ids.MatchId,
	towerEpoch: TowerEpoch,
	runtimeTowerId: RuntimeTowerId,
	ownerUserId: number,
	towerId: Ids.TowerId,
	unitId: Ids.UnitId,
	level: number,
	targetMode: ConfigTypes.TargetMode?,
	targetEligibility: TargetEligibility,
	placementCFrame: CFrame,
	totalInvestment: number,
	cooldownEndsServerTime: number,
	lifecycle: RemovedTowerLifecycle,
}

export type StoreIdentity = {
	matchId: Ids.MatchId,
	towerEpoch: TowerEpoch,
}

export type PreparedCapabilityBinding = {
	matchId: Ids.MatchId,
	towerEpoch: TowerEpoch,
	userId: number,
	loadoutRevision: number,
	slot: number,
	towerId: Ids.TowerId,
	unitId: Ids.UnitId,
	definition: ConfigTypes.TowerDefinition,
}

export type PreparedCapabilityInspector = (token: unknown) -> unknown

export type PreparedCreateToken = {}

export type PreparedCreate = {
	token: PreparedCreateToken,
	plannedSnapshot: RuntimeTowerSnapshot,
}

export type StoreMetrics = {
	activeCount: number,
	lifetimeCount: number,
	nextRuntimeTowerId: number,
	issuedIdCount: number,
	activeOwnerCount: number,
	activeOwnerTowerCount: number,
	retainsIdentity: boolean,
	retainsConfiguration: boolean,
	retainsCapabilityInspector: boolean,
	retainsPreparedCreate: boolean,
	cleaned: boolean,
	faulted: boolean,
}

export type Operation =
	"new"
	| "prepareCreate"
	| "commitPreparedCreate"
	| "abortPreparedCreate"
	| "failPreparedCreate"
	| "get"
	| "list"
	| "remove"
	| "getIdentity"
	| "fault"
	| "getMetrics"
	| "cleanup"

export type ErrorCode =
	"INVALID_MATCH_ID"
	| "INVALID_EPOCH"
	| "UNAUTHENTICATED_CONFIGURATION"
	| "INVALID_DEPENDENCY"
	| "INVALID_TEST_OPTIONS"
	| "INVALID_CAPABILITY"
	| "INVALID_CAPABILITY_BINDING"
	| "WRONG_MATCH"
	| "WRONG_EPOCH"
	| "WRONG_OWNER"
	| "WRONG_SLOT"
	| "INVALID_USER_ID"
	| "INVALID_SLOT"
	| "INVALID_UNIT_ID"
	| "INVALID_TOWER_ID"
	| "INVALID_DEFINITION"
	| "INVALID_CFRAME"
	| "PLACEMENT_CAP_EXCEEDED"
	| "CAPACITY_EXCEEDED"
	| "ID_EXHAUSTED"
	| "ID_COLLISION"
	| "COUNTER_FAULT"
	| "INVALID_RUNTIME_ID"
	| "NOT_FOUND"
	| "STALE_RUNTIME_ID"
	| "INVALID_TOKEN"
	| "CALLBACK_FAILED"
	| "REENTRANT"
	| "FAULTED"
	| "CLEANED"

export type StoreError = {
	code: ErrorCode,
	operation: Operation,
}

type RuntimeTowerRecord = {
	matchId: Ids.MatchId,
	towerEpoch: TowerEpoch,
	runtimeTowerId: RuntimeTowerId,
	ownerUserId: number,
	towerId: Ids.TowerId,
	unitId: Ids.UnitId,
	level: number,
	targetMode: ConfigTypes.TargetMode?,
	targetEligibility: TargetEligibility,
	placementCFrame: CFrame,
	totalInvestment: number,
	cooldownEndsServerTime: number,
	lifecycle: RuntimeTowerLifecycle,
}

type PreparedCreateData = {
	token: PreparedCreateToken,
	record: RuntimeTowerRecord,
	plannedSnapshot: RuntimeTowerSnapshot,
	ownerCounts: { [Ids.TowerId]: number },
	ownerWasAbsent: boolean,
	ownerTowerCountAfter: number,
	activeCountAfter: number,
	lifetimeCountAfter: number,
	nextRuntimeTowerIdAfter: number,
	publicResult: Result.Success<PreparedCreate>,
	commitResult: Result.Success<RuntimeTowerSnapshot>,
}

type StoreData = {
	identity: StoreIdentity?,
	configuration: ConfigTypes.CoreConfiguration?,
	inspectPreparedCapability: PreparedCapabilityInspector?,
	activeById: { [RuntimeTowerId]: RuntimeTowerRecord },
	issuedIds: { [RuntimeTowerId]: boolean },
	activeByOwnerTower: { [number]: { [Ids.TowerId]: number } },
	activeCount: number,
	lifetimeCount: number,
	nextRuntimeTowerId: number,
	maxActive: number,
	maxLifetime: number,
	preparedCreate: PreparedCreateData?,
	busy: boolean,
	reentryViolation: boolean,
	cleanupRequested: boolean,
	cleaned: boolean,
	faulted: boolean,
}

type TestOptions = {
	inspectPreparedCapability: PreparedCapabilityInspector,
	maxActive: number?,
	maxLifetime: number?,
	nextRuntimeTowerId: number?,
	issuedRuntimeTowerIds: { number }?,
}

local MAX_ACTIVE = 128
local MAX_LIFETIME = 4_096
local MAX_EPOCH = 4_096
local MAX_COORDINATE = 100_000
local MAX_LOADOUT_SLOTS = 5
local TARGET_ELIGIBILITY: TargetEligibility = "AllEligibleEnemies"
local AVAILABLE_COOLDOWN_SERVER_TIME = 0

local BINDING_FIELDS = table.freeze({
	definition = true,
	loadoutRevision = true,
	matchId = true,
	slot = true,
	towerEpoch = true,
	towerId = true,
	unitId = true,
	userId = true,
})
local RESULT_FAILURE_FIELDS = table.freeze({ error = true, ok = true })
local RESULT_SUCCESS_FIELDS = table.freeze({ ok = true, value = true })
local TEST_OPTION_FIELDS = table.freeze({
	inspectPreparedCapability = true,
	issuedRuntimeTowerIds = true,
	maxActive = true,
	maxLifetime = true,
	nextRuntimeTowerId = true,
})

local StoreMethods = {}
StoreMethods.__index = StoreMethods

export type Store = typeof(setmetatable({} :: {}, StoreMethods))

local STORE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: StoreData }

local TowerRuntimeStore = {
	AVAILABLE_COOLDOWN_SERVER_TIME = AVAILABLE_COOLDOWN_SERVER_TIME,
	MAX_ACTIVE = MAX_ACTIVE,
	MAX_COORDINATE = MAX_COORDINATE,
	MAX_EPOCH = MAX_EPOCH,
	MAX_LIFETIME = MAX_LIFETIME,
	TARGET_ELIGIBILITY = TARGET_ELIGIBILITY,
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
		error("[ATD_TOWER_RUNTIME_STORE][code=INVALID_CONTEXT]", 0)
	end
	local data = STORE_DATA[value :: any]
	if data == nil then
		error("[ATD_TOWER_RUNTIME_STORE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function hasExactFields(value: { [any]: unknown }, expected: { [string]: boolean }): boolean
	for key in next, value do
		if type(key) ~= "string" or expected[key] ~= true then
			return false
		end
	end
	for key in expected do
		if rawget(value, key) == nil then
			return false
		end
	end
	return true
end

local function isNonzeroSafeInteger(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value) and value ~= 0
end

local function isValidSlot(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value) and value >= 1 and value <= MAX_LOADOUT_SLOTS
end

local function isFinitePlacementCFrame(value: unknown): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = (value :: CFrame):GetComponents()
	for _, component in { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 } do
		if not Validation.isFiniteNumber(component) then
			return false
		end
	end
	return math.abs(x) <= MAX_COORDINATE and math.abs(y) <= MAX_COORDINATE and math.abs(z) <= MAX_COORDINATE
end

local function callNonYielding(callback: PreparedCapabilityInspector, value: unknown): (boolean, unknown)
	local thread = coroutine.create(function()
		return callback(value)
	end)
	local resumed, resultValue = coroutine.resume(thread)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, resultValue
end

local function snapshotRecord(record: RuntimeTowerRecord): RuntimeTowerSnapshot
	return table.freeze({
		matchId = record.matchId,
		towerEpoch = record.towerEpoch,
		runtimeTowerId = record.runtimeTowerId,
		ownerUserId = record.ownerUserId,
		towerId = record.towerId,
		unitId = record.unitId,
		level = 1,
		targetMode = record.targetMode,
		targetEligibility = TARGET_ELIGIBILITY,
		placementCFrame = record.placementCFrame,
		totalInvestment = record.totalInvestment,
		cooldownEndsServerTime = AVAILABLE_COOLDOWN_SERVER_TIME,
		lifecycle = "Active",
	})
end

local function removedSnapshot(record: RuntimeTowerRecord): RemovedTowerSnapshot
	return table.freeze({
		matchId = record.matchId,
		towerEpoch = record.towerEpoch,
		runtimeTowerId = record.runtimeTowerId,
		ownerUserId = record.ownerUserId,
		towerId = record.towerId,
		unitId = record.unitId,
		level = 1,
		targetMode = record.targetMode,
		targetEligibility = TARGET_ELIGIBILITY,
		placementCFrame = record.placementCFrame,
		totalInvestment = record.totalInvestment,
		cooldownEndsServerTime = AVAILABLE_COOLDOWN_SERVER_TIME,
		lifecycle = "Removed",
	})
end

local function clearData(data: StoreData)
	table.clear(data.activeById)
	table.clear(data.issuedIds)
	for _, counts in data.activeByOwnerTower do
		table.clear(counts)
	end
	table.clear(data.activeByOwnerTower)
	data.identity = nil
	data.configuration = nil
	data.inspectPreparedCapability = nil
	data.activeCount = 0
	data.lifetimeCount = 0
	data.nextRuntimeTowerId = 1
	data.preparedCreate = nil
	data.busy = false
	data.reentryViolation = false
	data.cleanupRequested = false
	data.faulted = false
	data.cleaned = true
end

local function finishOperation(data: StoreData): boolean
	data.busy = false
	if data.cleanupRequested then
		clearData(data)
		return true
	end
	return false
end

local function finishFault(data: StoreData)
	data.preparedCreate = nil
	data.faulted = true
	finishOperation(data)
end

local function enterReadyOperation(data: StoreData, operation: Operation): StoreError?
	if data.cleaned then
		return makeError("CLEANED", operation)
	end
	if data.busy then
		data.reentryViolation = true
		return makeError("REENTRANT", operation)
	end
	if data.faulted then
		return makeError("FAULTED", operation)
	end
	if data.preparedCreate ~= nil then
		return makeError("REENTRANT", operation)
	end
	data.busy = true
	data.reentryViolation = false
	return nil
end

local function parseInspectorResult(value: unknown): (PreparedCapabilityBinding?, "Rejected" | "Malformed"?)
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return nil, "Malformed"
	end
	local record = value :: { [any]: unknown }
	local okValue = rawget(record, "ok")
	if okValue == false then
		if not hasExactFields(record, RESULT_FAILURE_FIELDS) then
			return nil, "Malformed"
		end
		return nil, "Rejected"
	end
	if okValue ~= true or not hasExactFields(record, RESULT_SUCCESS_FIELDS) then
		return nil, "Malformed"
	end
	local bindingValue = rawget(record, "value")
	if
		type(bindingValue) ~= "table"
		or getmetatable(bindingValue :: any) ~= nil
		or not table.isfrozen(bindingValue :: any)
		or not hasExactFields(bindingValue :: { [any]: unknown }, BINDING_FIELDS)
	then
		return nil, "Malformed"
	end
	return bindingValue :: any, nil
end

local function definitionIsCanonical(
	configuration: ConfigTypes.CoreConfiguration,
	towerId: Ids.TowerId,
	definitionValue: unknown
): boolean
	if type(definitionValue) ~= "table" or not table.isfrozen(definitionValue :: any) then
		return false
	end
	local definition = definitionValue :: ConfigTypes.TowerDefinition
	if configuration.towers.byId[towerId] ~= definition or definition.id ~= towerId then
		return false
	end
	local orderedIdentity = false
	for _, candidate in configuration.towers.ordered do
		if candidate == definition then
			orderedIdentity = true
			break
		end
	end
	if not orderedIdentity then
		return false
	end
	local asset = configuration.assets.byKey[definition.modelAssetKey]
	if asset == nil or asset.kind ~= "TowerModel" then
		return false
	end
	for _, candidate in configuration.assets.ordered do
		if candidate == asset then
			return true
		end
	end
	return false
end

local function canonicalTargetMode(definition: ConfigTypes.TowerDefinition): ConfigTypes.TargetMode?
	local level = definition.levels[1]
	if level == nil then
		return nil
	end
	if level.attack == nil then
		if #definition.supportedTargetModes ~= 0 or definition.defaultTargetMode ~= nil then
			return nil
		end
		return nil
	end
	local targetMode = definition.defaultTargetMode
	if targetMode == nil then
		return nil
	end
	for _, supported in definition.supportedTargetModes do
		if supported == targetMode then
			return targetMode
		end
	end
	return nil
end

local function validateCanonicalRuntimeValues(definition: ConfigTypes.TowerDefinition): boolean
	local level = definition.levels[1]
	if level == nil then
		return false
	end
	if
		not Validation.isSafeInteger(definition.placementCost)
		or definition.placementCost < 0
		or not Validation.isSafeInteger(definition.placementCap)
		or definition.placementCap < 1
	then
		return false
	end
	if level.attack ~= nil then
		return canonicalTargetMode(definition) ~= nil
	end
	return #definition.supportedTargetModes == 0 and definition.defaultTargetMode == nil
end

local function validateRuntimeTowerId(value: unknown, operation: Operation): (RuntimeTowerId?, StoreError?)
	if type(value) ~= "number" or not Validation.isSafeInteger(value) or value < 1 or value > MAX_LIFETIME then
		return nil, makeError("INVALID_RUNTIME_ID", operation)
	end
	return value, nil
end

local function construct(
	matchIdValue: unknown,
	towerEpochValue: unknown,
	configurationValue: unknown,
	inspectPreparedCapability: PreparedCapabilityInspector,
	maxActive: number,
	maxLifetime: number,
	nextRuntimeTowerId: number,
	issuedIds: { [RuntimeTowerId]: boolean },
	lifetimeCount: number
): Result.Result<Store, StoreError>
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if not matchIdResult.ok then
		return failure("INVALID_MATCH_ID", "new")
	end
	if
		type(towerEpochValue) ~= "number"
		or not Validation.isSafeInteger(towerEpochValue)
		or towerEpochValue < 1
		or towerEpochValue > MAX_EPOCH
	then
		return failure("INVALID_EPOCH", "new")
	end
	if
		not ConfigurationValidator.isValidatedConfiguration(configurationValue)
		or not AssetSchema.isValidatedManifest((configurationValue :: any).assets)
		or not TowerSchema.isValidatedCatalog((configurationValue :: any).towers)
	then
		return failure("UNAUTHENTICATED_CONFIGURATION", "new")
	end
	if type(inspectPreparedCapability) ~= "function" then
		return failure("INVALID_DEPENDENCY", "new")
	end

	local store = setmetatable({}, StoreMethods)
	table.freeze(store)
	STORE_DATA[store] = {
		identity = table.freeze({
			matchId = matchIdResult.value,
			towerEpoch = towerEpochValue,
		}),
		configuration = configurationValue :: ConfigTypes.CoreConfiguration,
		inspectPreparedCapability = inspectPreparedCapability,
		activeById = {},
		issuedIds = issuedIds,
		activeByOwnerTower = {},
		activeCount = 0,
		lifetimeCount = lifetimeCount,
		nextRuntimeTowerId = nextRuntimeTowerId,
		maxActive = maxActive,
		maxLifetime = maxLifetime,
		preparedCreate = nil,
		busy = false,
		reentryViolation = false,
		cleanupRequested = false,
		cleaned = false,
		faulted = false,
	}
	return Result.ok(store)
end

function StoreMethods.prepareCreate(
	self: Store,
	preparedCapabilityTokenValue: unknown,
	expectedOwnerUserIdValue: unknown,
	expectedSlotValue: unknown,
	placementCFrameValue: unknown
): Result.Result<PreparedCreate, StoreError>
	local operation: Operation = "prepareCreate"
	local data = requireData(self)
	local operationError = enterReadyOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if not isNonzeroSafeInteger(expectedOwnerUserIdValue) then
		finishOperation(data)
		return failure("INVALID_USER_ID", operation)
	end
	if not isValidSlot(expectedSlotValue) then
		finishOperation(data)
		return failure("INVALID_SLOT", operation)
	end
	if not isFinitePlacementCFrame(placementCFrameValue) then
		finishOperation(data)
		return failure("INVALID_CFRAME", operation)
	end

	local inspector = data.inspectPreparedCapability
	if inspector == nil then
		finishFault(data)
		return failure("CALLBACK_FAILED", operation)
	end
	local called, inspectedValue = callNonYielding(inspector, preparedCapabilityTokenValue)
	if data.cleanupRequested then
		finishOperation(data)
		return failure("CLEANED", operation)
	end
	if not called or data.reentryViolation then
		finishFault(data)
		return failure("CALLBACK_FAILED", operation)
	end
	local binding, inspectorError = parseInspectorResult(inspectedValue)
	if inspectorError == "Rejected" then
		finishOperation(data)
		return failure("INVALID_CAPABILITY", operation)
	elseif binding == nil then
		finishFault(data)
		return failure("CALLBACK_FAILED", operation)
	end

	local identity = data.identity
	local configuration = data.configuration
	if identity == nil or configuration == nil then
		finishFault(data)
		return failure("COUNTER_FAULT", operation)
	end
	if binding.matchId ~= identity.matchId then
		finishOperation(data)
		return failure("WRONG_MATCH", operation)
	end
	if binding.towerEpoch ~= identity.towerEpoch then
		finishOperation(data)
		return failure("WRONG_EPOCH", operation)
	end
	if
		not isNonzeroSafeInteger(binding.userId)
		or not Validation.isSafeInteger(binding.loadoutRevision)
		or binding.loadoutRevision < 1
	then
		finishOperation(data)
		return failure("INVALID_CAPABILITY_BINDING", operation)
	end
	if binding.userId ~= expectedOwnerUserIdValue then
		finishOperation(data)
		return failure("WRONG_OWNER", operation)
	end
	if not isValidSlot(binding.slot) then
		finishOperation(data)
		return failure("INVALID_CAPABILITY_BINDING", operation)
	end
	if binding.slot ~= expectedSlotValue then
		finishOperation(data)
		return failure("WRONG_SLOT", operation)
	end
	local towerIdResult = Ids.validateTowerId(binding.towerId)
	if not towerIdResult.ok then
		finishOperation(data)
		return failure("INVALID_TOWER_ID", operation)
	end
	local unitIdResult = Ids.validateUnitId(binding.unitId)
	if not unitIdResult.ok then
		finishOperation(data)
		return failure("INVALID_UNIT_ID", operation)
	end
	if not definitionIsCanonical(configuration, towerIdResult.value, binding.definition) then
		finishOperation(data)
		return failure("INVALID_DEFINITION", operation)
	end
	local definition = binding.definition
	if not validateCanonicalRuntimeValues(definition) then
		finishFault(data)
		return failure("INVALID_DEFINITION", operation)
	end

	if
		data.activeCount < 0
		or data.activeCount > data.maxActive
		or data.lifetimeCount < 0
		or data.lifetimeCount > data.maxLifetime
		or data.nextRuntimeTowerId < 1
		or data.nextRuntimeTowerId > data.maxLifetime + 1
	then
		finishFault(data)
		return failure("COUNTER_FAULT", operation)
	end
	local ownerCounts = data.activeByOwnerTower[binding.userId]
	local activeForDefinition = if ownerCounts == nil then 0 else ownerCounts[towerIdResult.value] or 0
	if
		not Validation.isSafeInteger(activeForDefinition)
		or activeForDefinition < 0
		or activeForDefinition > definition.placementCap
	then
		finishFault(data)
		return failure("COUNTER_FAULT", operation)
	end
	if activeForDefinition >= definition.placementCap then
		finishOperation(data)
		return failure("PLACEMENT_CAP_EXCEEDED", operation)
	end
	if data.activeCount >= data.maxActive then
		finishOperation(data)
		return failure("CAPACITY_EXCEEDED", operation)
	end
	if data.lifetimeCount >= data.maxLifetime or data.nextRuntimeTowerId > data.maxLifetime then
		finishOperation(data)
		return failure("ID_EXHAUSTED", operation)
	end
	local runtimeTowerId = data.nextRuntimeTowerId
	if data.issuedIds[runtimeTowerId] or data.activeById[runtimeTowerId] ~= nil then
		finishFault(data)
		return failure("ID_COLLISION", operation)
	end
	if
		data.activeCount >= Validation.MAX_SAFE_INTEGER
		or data.lifetimeCount >= Validation.MAX_SAFE_INTEGER
		or activeForDefinition >= Validation.MAX_SAFE_INTEGER
		or runtimeTowerId >= Validation.MAX_SAFE_INTEGER
	then
		finishFault(data)
		return failure("COUNTER_FAULT", operation)
	end

	local targetMode = canonicalTargetMode(definition)
	local record: RuntimeTowerRecord = {
		matchId = identity.matchId,
		towerEpoch = identity.towerEpoch,
		runtimeTowerId = runtimeTowerId,
		ownerUserId = binding.userId,
		towerId = towerIdResult.value,
		unitId = unitIdResult.value,
		level = 1,
		targetMode = targetMode,
		targetEligibility = TARGET_ELIGIBILITY,
		placementCFrame = placementCFrameValue :: CFrame,
		totalInvestment = definition.placementCost,
		cooldownEndsServerTime = AVAILABLE_COOLDOWN_SERVER_TIME,
		lifecycle = "Active",
	}
	local plannedSnapshot = snapshotRecord(record)
	local token = table.freeze({}) :: PreparedCreateToken
	local publicValue: PreparedCreate = table.freeze({
		token = token,
		plannedSnapshot = plannedSnapshot,
	})
	local prepared: PreparedCreateData = {
		token = token,
		record = record,
		plannedSnapshot = plannedSnapshot,
		ownerCounts = ownerCounts or {},
		ownerWasAbsent = ownerCounts == nil,
		ownerTowerCountAfter = activeForDefinition + 1,
		activeCountAfter = data.activeCount + 1,
		lifetimeCountAfter = data.lifetimeCount + 1,
		nextRuntimeTowerIdAfter = data.nextRuntimeTowerId + 1,
		publicResult = Result.ok(publicValue),
		commitResult = Result.ok(plannedSnapshot),
	}
	data.preparedCreate = prepared
	finishOperation(data)
	return prepared.publicResult
end

local function enterPreparedFinalizer(
	data: StoreData,
	tokenValue: unknown,
	operation: Operation
): (PreparedCreateData?, StoreError?)
	if data.cleaned then
		return nil, makeError("CLEANED", operation)
	end
	if data.busy then
		data.reentryViolation = true
		return nil, makeError("REENTRANT", operation)
	end
	if data.faulted then
		return nil, makeError("FAULTED", operation)
	end
	local prepared = data.preparedCreate
	if prepared == nil or tokenValue ~= prepared.token then
		return nil, makeError("INVALID_TOKEN", operation)
	end
	data.busy = true
	data.reentryViolation = false
	return prepared, nil
end

function StoreMethods.commitPreparedCreate(
	self: Store,
	tokenValue: unknown
): Result.Result<RuntimeTowerSnapshot, StoreError>
	local operation: Operation = "commitPreparedCreate"
	local data = requireData(self)
	local prepared, operationError = enterPreparedFinalizer(data, tokenValue, operation)
	if prepared == nil then
		return Result.err(operationError :: StoreError)
	end
	local record = prepared.record
	if prepared.ownerWasAbsent then
		data.activeByOwnerTower[record.ownerUserId] = prepared.ownerCounts
	end
	data.activeById[record.runtimeTowerId] = record
	data.issuedIds[record.runtimeTowerId] = true
	prepared.ownerCounts[record.towerId] = prepared.ownerTowerCountAfter
	data.activeCount = prepared.activeCountAfter
	data.lifetimeCount = prepared.lifetimeCountAfter
	data.nextRuntimeTowerId = prepared.nextRuntimeTowerIdAfter
	data.preparedCreate = nil
	local commitResult = prepared.commitResult
	finishOperation(data)
	return commitResult
end

function StoreMethods.abortPreparedCreate(self: Store, tokenValue: unknown): Result.Result<boolean, StoreError>
	local operation: Operation = "abortPreparedCreate"
	local data = requireData(self)
	local prepared, operationError = enterPreparedFinalizer(data, tokenValue, operation)
	if prepared == nil then
		return Result.err(operationError :: StoreError)
	end
	data.preparedCreate = nil
	finishOperation(data)
	return Result.ok(true)
end

function StoreMethods.failPreparedCreate(self: Store, tokenValue: unknown): Result.Result<boolean, StoreError>
	local operation: Operation = "failPreparedCreate"
	local data = requireData(self)
	local prepared, operationError = enterPreparedFinalizer(data, tokenValue, operation)
	if prepared == nil then
		return Result.err(operationError :: StoreError)
	end
	data.preparedCreate = nil
	data.faulted = true
	finishOperation(data)
	return Result.ok(true)
end

function StoreMethods.get(self: Store, runtimeTowerIdValue: unknown): Result.Result<RuntimeTowerSnapshot, StoreError>
	local operation: Operation = "get"
	local data = requireData(self)
	local operationError = enterReadyOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtimeTowerId, idError = validateRuntimeTowerId(runtimeTowerIdValue, operation)
	if runtimeTowerId == nil then
		finishOperation(data)
		return Result.err(idError :: StoreError)
	end
	local record = data.activeById[runtimeTowerId]
	if record == nil then
		local code: ErrorCode = if data.issuedIds[runtimeTowerId] then "STALE_RUNTIME_ID" else "NOT_FOUND"
		finishOperation(data)
		return failure(code, operation)
	end
	local snapshot = snapshotRecord(record)
	finishOperation(data)
	return Result.ok(snapshot)
end

function StoreMethods.list(self: Store): Result.Result<{ RuntimeTowerSnapshot }, StoreError>
	local operation: Operation = "list"
	local data = requireData(self)
	local operationError = enterReadyOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local ids: { RuntimeTowerId } = {}
	for runtimeTowerId in data.activeById do
		table.insert(ids, runtimeTowerId)
	end
	if #ids ~= data.activeCount or #ids > data.maxActive then
		finishFault(data)
		return failure("COUNTER_FAULT", operation)
	end
	table.sort(ids)
	local snapshots: { RuntimeTowerSnapshot } = table.create(#ids)
	for _, runtimeTowerId in ids do
		table.insert(snapshots, snapshotRecord(data.activeById[runtimeTowerId]))
	end
	table.freeze(snapshots)
	finishOperation(data)
	return Result.ok(snapshots)
end

function StoreMethods.remove(self: Store, runtimeTowerIdValue: unknown): Result.Result<RemovedTowerSnapshot, StoreError>
	local operation: Operation = "remove"
	local data = requireData(self)
	local operationError = enterReadyOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtimeTowerId, idError = validateRuntimeTowerId(runtimeTowerIdValue, operation)
	if runtimeTowerId == nil then
		finishOperation(data)
		return Result.err(idError :: StoreError)
	end
	local record = data.activeById[runtimeTowerId]
	if record == nil then
		local code: ErrorCode = if data.issuedIds[runtimeTowerId] then "STALE_RUNTIME_ID" else "NOT_FOUND"
		finishOperation(data)
		return failure(code, operation)
	end
	local ownerCounts = data.activeByOwnerTower[record.ownerUserId]
	local activeForDefinition = if ownerCounts == nil then nil else ownerCounts[record.towerId]
	if
		data.activeCount < 1
		or data.lifetimeCount < 1
		or data.issuedIds[runtimeTowerId] ~= true
		or activeForDefinition == nil
		or not Validation.isSafeInteger(activeForDefinition)
		or activeForDefinition < 1
	then
		finishFault(data)
		return failure("COUNTER_FAULT", operation)
	end
	local tombstone = removedSnapshot(record)
	data.activeById[runtimeTowerId] = nil
	data.activeCount -= 1
	if activeForDefinition == 1 then
		(ownerCounts :: { [Ids.TowerId]: number })[record.towerId] = nil
		if next(ownerCounts :: { [Ids.TowerId]: number }) == nil then
			data.activeByOwnerTower[record.ownerUserId] = nil
		end
	else
		(ownerCounts :: { [Ids.TowerId]: number })[record.towerId] = activeForDefinition - 1
	end
	finishOperation(data)
	return Result.ok(tombstone)
end

function StoreMethods.getIdentity(self: Store): Result.Result<StoreIdentity, StoreError>
	local operation: Operation = "getIdentity"
	local data = requireData(self)
	local operationError = enterReadyOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local identity = data.identity
	if identity == nil then
		finishFault(data)
		return failure("COUNTER_FAULT", operation)
	end
	finishOperation(data)
	return Result.ok(identity)
end

function StoreMethods.fault(self: Store): Result.Result<boolean, StoreError>
	local operation: Operation = "fault"
	local data = requireData(self)
	local operationError = enterReadyOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	data.faulted = true
	finishOperation(data)
	return Result.ok(true)
end

function StoreMethods.getMetrics(self: Store): StoreMetrics
	local data = requireData(self)
	local activeOwnerCount = 0
	local activeOwnerTowerCount = 0
	for _, counts in data.activeByOwnerTower do
		activeOwnerCount += 1
		for _ in counts do
			activeOwnerTowerCount += 1
		end
	end
	return table.freeze({
		activeCount = data.activeCount,
		lifetimeCount = data.lifetimeCount,
		nextRuntimeTowerId = data.nextRuntimeTowerId,
		issuedIdCount = data.lifetimeCount,
		activeOwnerCount = activeOwnerCount,
		activeOwnerTowerCount = activeOwnerTowerCount,
		retainsIdentity = data.identity ~= nil,
		retainsConfiguration = data.configuration ~= nil,
		retainsCapabilityInspector = data.inspectPreparedCapability ~= nil,
		retainsPreparedCreate = data.preparedCreate ~= nil,
		cleaned = data.cleaned,
		faulted = data.faulted,
	})
end

function StoreMethods.cleanup(self: Store): Result.Result<boolean, StoreError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	if data.busy then
		data.cleanupRequested = true
		return Result.ok(false)
	end
	data.busy = true
	clearData(data)
	return Result.ok(true)
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "TowerRuntimeStore" then
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
	if automatedTests.Parent ~= ServerStorage then
		return false
	end
	return ServerScriptService:FindFirstChild("Server") == nil
end

function TowerRuntimeStore.new(
	matchIdValue: unknown,
	towerEpochValue: unknown,
	configurationValue: unknown,
	inspectPreparedCapabilityValue: unknown
): Result.Result<Store, StoreError>
	if type(inspectPreparedCapabilityValue) ~= "function" then
		return failure("INVALID_DEPENDENCY", "new")
	end
	return construct(
		matchIdValue,
		towerEpochValue,
		configurationValue,
		inspectPreparedCapabilityValue :: PreparedCapabilityInspector,
		MAX_ACTIVE,
		MAX_LIFETIME,
		1,
		{},
		0
	)
end

function TowerRuntimeStore.newForTests(
	matchIdValue: unknown,
	towerEpochValue: unknown,
	configurationValue: unknown,
	optionsValue: unknown
): Result.Result<Store, StoreError>
	if not testModuleIdentityIsExact() then
		error("[ATD_TOWER_RUNTIME_STORE][code=TEST_CONSTRUCTOR_FORBIDDEN]", 0)
	end
	if type(optionsValue) ~= "table" or getmetatable(optionsValue :: any) ~= nil then
		return failure("INVALID_TEST_OPTIONS", "new")
	end
	for key in next, optionsValue :: { [any]: unknown } do
		if type(key) ~= "string" or TEST_OPTION_FIELDS[key] ~= true then
			return failure("INVALID_TEST_OPTIONS", "new")
		end
	end
	local options = optionsValue :: any
	if type(options.inspectPreparedCapability) ~= "function" then
		return failure("INVALID_DEPENDENCY", "new")
	end
	local maxActive = options.maxActive or MAX_ACTIVE
	local maxLifetime = options.maxLifetime or MAX_LIFETIME
	local nextRuntimeTowerId = options.nextRuntimeTowerId or 1
	if
		not Validation.isSafeInteger(maxActive)
		or maxActive < 1
		or maxActive > MAX_ACTIVE
		or not Validation.isSafeInteger(maxLifetime)
		or maxLifetime < 1
		or maxLifetime > MAX_LIFETIME
		or maxActive > maxLifetime
		or not Validation.isSafeInteger(nextRuntimeTowerId)
		or nextRuntimeTowerId < 1
		or nextRuntimeTowerId > maxLifetime + 1
	then
		return failure("INVALID_TEST_OPTIONS", "new")
	end

	local issuedIds: { [RuntimeTowerId]: boolean } = {}
	local lifetimeCount = 0
	local maximumIssuedId = 0
	local issuedValues = options.issuedRuntimeTowerIds
	if issuedValues ~= nil then
		if type(issuedValues) ~= "table" or getmetatable(issuedValues) ~= nil then
			return failure("INVALID_TEST_OPTIONS", "new")
		end
		local length = rawlen(issuedValues)
		local fieldCount = 0
		for key in next, issuedValues do
			if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
				return failure("INVALID_TEST_OPTIONS", "new")
			end
			fieldCount += 1
		end
		if fieldCount ~= length then
			return failure("INVALID_TEST_OPTIONS", "new")
		end
		for index = 1, length do
			local runtimeTowerId = issuedValues[index]
			if
				type(runtimeTowerId) ~= "number"
				or not Validation.isSafeInteger(runtimeTowerId)
				or runtimeTowerId < 1
				or runtimeTowerId > maxLifetime
				or issuedIds[runtimeTowerId]
			then
				return failure("INVALID_TEST_OPTIONS", "new")
			end
			issuedIds[runtimeTowerId] = true
			lifetimeCount += 1
			maximumIssuedId = math.max(maximumIssuedId, runtimeTowerId)
		end
	end
	if lifetimeCount > maxLifetime or maximumIssuedId > nextRuntimeTowerId then
		return failure("INVALID_TEST_OPTIONS", "new")
	end

	return construct(
		matchIdValue,
		towerEpochValue,
		configurationValue,
		options.inspectPreparedCapability,
		maxActive,
		maxLifetime,
		nextRuntimeTowerId,
		issuedIds,
		lifetimeCount
	)
end

table.freeze(StoreMethods)
return table.freeze(TowerRuntimeStore)
