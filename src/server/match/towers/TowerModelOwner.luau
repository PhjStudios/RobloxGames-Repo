--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local AssetSchema = require(ReplicatedStorage.Shared.config.AssetSchema)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local TowerSchema = require(ReplicatedStorage.Shared.config.TowerSchema)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type RuntimeTowerId = number
export type TowerEpoch = number
export type PreparedVisualToken = {}

export type RuntimeTowerSnapshot = {
	matchId: Ids.MatchId,
	towerEpoch: TowerEpoch,
	runtimeTowerId: RuntimeTowerId,
	ownerUserId: number,
	towerId: Ids.TowerId,
	unitId: Ids.UnitId,
	level: number,
	targetMode: ConfigTypes.TargetMode?,
	targetEligibility: "AllEligibleEnemies",
	placementCFrame: CFrame,
	totalInvestment: number,
	cooldownEndsServerTime: number,
	lifecycle: "Active",
}

export type ContractAdapter = {
	validateTemplate: (self: ContractAdapter, definition: unknown, model: unknown) -> unknown,
	selectLiveVariant: (self: ContractAdapter, definition: unknown, level: unknown, model: unknown) -> unknown,
	validateLive: (self: ContractAdapter, definition: unknown, level: unknown, model: unknown) -> unknown,
}

export type EngineAdapter = {
	workspace: Instance,
	cloneModel: (self: EngineAdapter, model: unknown) -> unknown,
	getPivot: (self: EngineAdapter, model: unknown) -> unknown,
	pivotTo: (self: EngineAdapter, model: unknown, placementCFrame: unknown) -> unknown,
	createFolder: (self: EngineAdapter, name: unknown) -> unknown,
	setParent: (self: EngineAdapter, instance: unknown, parent: unknown) -> unknown,
	destroy: (self: EngineAdapter, instance: unknown) -> unknown,
}

export type PreparedVisual = {
	token: PreparedVisualToken,
	runtimeTowerId: RuntimeTowerId,
}

export type VisualReceipt = {
	runtimeTowerId: RuntimeTowerId,
	status: "Live",
	recreated: boolean,
}

export type Metrics = {
	templateCount: number,
	liveModelCount: number,
	preparedModelCount: number,
	orphanModelCount: number,
	hasRuntimeRoot: boolean,
	retainsConfiguration: boolean,
	retainsContractAdapter: boolean,
	retainsEngineAdapter: boolean,
	faulted: boolean,
	cleaned: boolean,
}

export type Operation =
	"new"
	| "registerTemplate"
	| "prepareCreate"
	| "commitPreparedCreate"
	| "abortPreparedCreate"
	| "removeVisual"
	| "recreateVisual"
	| "getMetrics"
	| "cleanup"

export type ErrorCode =
	"UNAUTHENTICATED_CONFIGURATION"
	| "INVALID_MATCH_ID"
	| "INVALID_EPOCH"
	| "INVALID_ADAPTER"
	| "INVALID_DEFINITION"
	| "INVALID_TEMPLATE"
	| "DUPLICATE_TEMPLATE"
	| "TEMPLATE_CAPACITY_EXCEEDED"
	| "MISSING_TEMPLATE"
	| "INVALID_RUNTIME_SNAPSHOT"
	| "INVALID_RUNTIME_ID"
	| "DUPLICATE_RUNTIME_ID"
	| "CAPACITY_EXCEEDED"
	| "INVALID_TOKEN"
	| "FOREIGN_RUNTIME_ROOT"
	| "FOREIGN_MODEL"
	| "DEPENDENCY_FAILED"
	| "REENTRANT"
	| "FAULTED"
	| "CLEANED"
	| "CLEANUP_FAILED"

export type OwnerError = {
	code: ErrorCode,
	operation: Operation,
}

type TemplateEntry = {
	definition: ConfigTypes.TowerDefinition,
	model: Model,
}

type PreparedVisualData = {
	token: PreparedVisualToken,
	runtimeTowerId: RuntimeTowerId,
	model: Model?,
	createdRoot: boolean,
	ownedModelData: OwnedModelData,
	publicResult: Result.Success<PreparedVisual>,
	commitResult: Result.Success<VisualReceipt>,
}

type OwnerData = {
	matchId: Ids.MatchId,
	towerEpoch: TowerEpoch,
	configuration: ConfigTypes.CoreConfiguration?,
	contract: ContractAdapter?,
	engine: EngineAdapter?,
	templatesByTowerId: { [Ids.TowerId]: TemplateEntry },
	templateCount: number,
	liveById: { [RuntimeTowerId]: Model },
	issuedRuntimeIds: { [RuntimeTowerId]: boolean },
	liveCount: number,
	runtimeRoot: Folder?,
	prepared: PreparedVisualData?,
	orphanModels: { Model },
	busy: boolean,
	reentryViolation: boolean,
	cleanupRequested: boolean,
	faulted: boolean,
	cleaned: boolean,
}

type OwnedModelData = {
	owner: OwnerData,
	runtimeTowerId: RuntimeTowerId?,
	status: "Template" | "Prepared" | "Live" | "Orphan",
}

export type TestConstructor = (
	configuration: unknown,
	matchId: unknown,
	towerEpoch: unknown,
	contractAdapter: unknown,
	engineAdapter: unknown
) -> Result.Result<Owner, OwnerError>

local RUNTIME_ROOT_NAME = "ATDTowerRuntime"
local MAX_ACTIVE = 128
local MAX_RUNTIME_ID = 4_096
local MAX_TEMPLATES = Validation.MAX_CATALOG_ENTRIES
local MAX_EPOCH = 4_096
local MAX_COORDINATE = 100_000
local MAX_DETACHED_NODES = 2_048
local MAX_WORKSPACE_CHILDREN = 4_096

local CONTRACT_ADAPTER_FIELDS = table.freeze({
	selectLiveVariant = true,
	validateLive = true,
	validateTemplate = true,
})

local ENGINE_ADAPTER_FIELDS = table.freeze({
	cloneModel = true,
	createFolder = true,
	destroy = true,
	getPivot = true,
	pivotTo = true,
	setParent = true,
	workspace = true,
})

local SNAPSHOT_FIELDS = table.freeze({
	cooldownEndsServerTime = true,
	level = true,
	lifecycle = true,
	matchId = true,
	ownerUserId = true,
	placementCFrame = true,
	runtimeTowerId = true,
	targetEligibility = true,
	targetMode = true,
	totalInvestment = true,
	towerEpoch = true,
	towerId = true,
	unitId = true,
})

local OwnerMethods = {}
OwnerMethods.__index = OwnerMethods

export type Owner = typeof(setmetatable({} :: {}, OwnerMethods))

local OWNER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: OwnerData }
local PREPARED_TOKEN_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: OwnerData }
local OWNED_ROOT_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: OwnerData }
local OWNED_MODEL_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: OwnedModelData }

local TowerModelOwner = {
	MAX_ACTIVE = MAX_ACTIVE,
	MAX_TEMPLATES = MAX_TEMPLATES,
	RUNTIME_ROOT_NAME = RUNTIME_ROOT_NAME,
	newForTests = nil :: TestConstructor?,
}

local performCleanup: (OwnerData) -> boolean

local function makeError(code: ErrorCode, operation: Operation): OwnerError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<OwnerError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): OwnerData
	if type(value) ~= "table" then
		error("[ATD_TOWER_MODEL_OWNER][code=INVALID_CONTEXT]", 0)
	end
	local data = OWNER_DATA[value :: any]
	if data == nil then
		error("[ATD_TOWER_MODEL_OWNER][code=INVALID_CONTEXT]", 0)
	end
	return data
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

local function hasExactSnapshotFields(value: { [any]: unknown }): boolean
	local count = 0
	for key in next, value do
		if type(key) ~= "string" or SNAPSHOT_FIELDS[key] ~= true then
			return false
		end
		count += 1
	end
	return count == if rawget(value, "targetMode") == nil then 12 else 13
end

local function callNonYielding(callback: (...unknown) -> unknown, ...: unknown): (boolean, unknown)
	local arguments = table.pack(...)
	local thread = coroutine.create(function()
		return callback(table.unpack(arguments, 1, arguments.n))
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

local function isExactFrozenAdapter(value: unknown, fields: { [string]: boolean }): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return false
	end
	return hasExactFields(value :: { [any]: unknown }, fields)
end

local function isContractAdapter(value: unknown): boolean
	return isExactFrozenAdapter(value, CONTRACT_ADAPTER_FIELDS)
		and type((value :: any).validateTemplate) == "function"
		and type((value :: any).selectLiveVariant) == "function"
		and type((value :: any).validateLive) == "function"
end

local function isEngineAdapter(value: unknown): boolean
	if not isExactFrozenAdapter(value, ENGINE_ADAPTER_FIELDS) then
		return false
	end
	local adapter = value :: any
	return typeof(adapter.workspace) == "Instance"
		and type(adapter.cloneModel) == "function"
		and type(adapter.getPivot) == "function"
		and type(adapter.pivotTo) == "function"
		and type(adapter.createFolder) == "function"
		and type(adapter.setParent) == "function"
		and type(adapter.destroy) == "function"
end

local function isDetachedFrozen(
	value: unknown,
	visiting: { [any]: boolean }?,
	visited: { [any]: boolean }?,
	nodeCount: { value: number }?
): boolean
	if typeof(value) == "Instance" then
		return false
	end
	if type(value) ~= "table" then
		local valueType = typeof(value)
		return value == nil
			or valueType == "boolean"
			or valueType == "number"
			or valueType == "string"
			or valueType == "Vector3"
			or valueType == "CFrame"
	end
	local active = visiting or {}
	local complete = visited or {}
	local count = nodeCount or { value = 0 }
	local tableValue = value :: { [any]: unknown }
	if getmetatable(tableValue) ~= nil or not table.isfrozen(tableValue) or active[tableValue] then
		return false
	end
	if complete[tableValue] then
		return true
	end
	count.value += 1
	if count.value > MAX_DETACHED_NODES then
		return false
	end
	active[tableValue] = true
	for key, child in next, tableValue do
		count.value += 1
		if
			count.value > MAX_DETACHED_NODES
			or not isDetachedFrozen(key, active, complete, count)
			or not isDetachedFrozen(child, active, complete, count)
		then
			active[tableValue] = nil
			return false
		end
	end
	active[tableValue] = nil
	complete[tableValue] = true
	return true
end

local function parseContractResult(value: unknown): "Accepted" | "Rejected" | "Malformed"
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return "Malformed"
	end
	local resultValue = value :: { [any]: unknown }
	if rawget(resultValue, "ok") == true then
		if not hasExactFields(resultValue, { ok = true, value = true }) then
			return "Malformed"
		end
		return if isDetachedFrozen(rawget(resultValue, "value")) then "Accepted" else "Malformed"
	elseif rawget(resultValue, "ok") == false then
		if not hasExactFields(resultValue, { error = true, ok = true }) then
			return "Malformed"
		end
		return if isDetachedFrozen(rawget(resultValue, "error")) then "Rejected" else "Malformed"
	end
	return "Malformed"
end

local function callContract(
	data: OwnerData,
	methodName: "validateTemplate" | "selectLiveVariant" | "validateLive",
	definition: ConfigTypes.TowerDefinition,
	level: ConfigTypes.TowerLevelDefinition?,
	model: Model
): "Accepted" | "Rejected" | "Malformed"
	local contract = data.contract
	if contract == nil then
		return "Malformed"
	end
	local called, resultValue
	if methodName == "validateTemplate" then
		called, resultValue = callNonYielding(contract.validateTemplate, contract, definition, model)
	elseif methodName == "selectLiveVariant" then
		called, resultValue = callNonYielding(contract.selectLiveVariant, contract, definition, level, model)
	else
		called, resultValue = callNonYielding(contract.validateLive, contract, definition, level, model)
	end
	if not called then
		return "Malformed"
	end
	return parseContractResult(resultValue)
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

local function isCanonicalDefinition(data: OwnerData, value: unknown): ConfigTypes.TowerDefinition?
	local configuration = data.configuration
	if
		configuration == nil
		or type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
	then
		return nil
	end
	local definition = value :: any
	if type(definition.id) ~= "string" or configuration.towers.byId[definition.id] ~= value then
		return nil
	end
	local orderedIdentity = false
	for _, orderedDefinition in configuration.towers.ordered do
		if orderedDefinition == value then
			orderedIdentity = true
			break
		end
	end
	local declaration = configuration.assets.byKey[definition.modelAssetKey]
	if not orderedIdentity or declaration == nil or declaration.kind ~= "TowerModel" then
		return nil
	end
	return value :: ConfigTypes.TowerDefinition
end

local function validateRuntimeSnapshot(
	data: OwnerData,
	value: unknown
): (RuntimeTowerSnapshot?, ConfigTypes.TowerDefinition?)
	if
		type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
		or not hasExactSnapshotFields(value :: { [any]: unknown })
	then
		return nil, nil
	end
	local snapshot = value :: any
	local configuration = data.configuration
	if configuration == nil then
		return nil, nil
	end
	local definition = configuration.towers.byId[snapshot.towerId]
	local matchIdResult = Ids.validateMatchId(snapshot.matchId)
	local towerIdResult = Ids.validateTowerId(snapshot.towerId)
	local unitIdResult = Ids.validateUnitId(snapshot.unitId)
	if
		not matchIdResult.ok
		or not towerIdResult.ok
		or not unitIdResult.ok
		or snapshot.matchId ~= data.matchId
		or snapshot.towerEpoch ~= data.towerEpoch
		or type(snapshot.runtimeTowerId) ~= "number"
		or not Validation.isSafeInteger(snapshot.runtimeTowerId)
		or snapshot.runtimeTowerId < 1
		or snapshot.runtimeTowerId > MAX_RUNTIME_ID
		or type(snapshot.ownerUserId) ~= "number"
		or not Validation.isSafeInteger(snapshot.ownerUserId)
		or snapshot.ownerUserId == 0
		or definition == nil
		or snapshot.level ~= 1
		or snapshot.targetEligibility ~= "AllEligibleEnemies"
		or not isFinitePlacementCFrame(snapshot.placementCFrame)
		or snapshot.totalInvestment ~= definition.placementCost
		or snapshot.cooldownEndsServerTime ~= 0
		or snapshot.lifecycle ~= "Active"
	then
		return nil, nil
	end
	local level = definition.levels[snapshot.level]
	local expectedTargetMode = if level.attack == nil then nil else definition.defaultTargetMode
	if snapshot.targetMode ~= expectedTargetMode then
		return nil, nil
	end
	return value :: RuntimeTowerSnapshot, definition
end

local function beginOperation(data: OwnerData, operation: Operation, allowFaulted: boolean?): OwnerError?
	if data.cleaned then
		return makeError("CLEANED", operation)
	end
	if data.busy then
		data.reentryViolation = true
		return makeError("REENTRANT", operation)
	end
	if data.faulted and not allowFaulted then
		return makeError("FAULTED", operation)
	end
	data.busy = true
	data.reentryViolation = false
	return nil
end

local function operationIntact(data: OwnerData): boolean
	return data.busy and not data.reentryViolation and not data.cleanupRequested and not data.cleaned
end

local function finishOperation(data: OwnerData): boolean
	data.busy = false
	if data.cleanupRequested then
		data.cleanupRequested = false
		return performCleanup(data)
	end
	return false
end

local function faultAndFinish(data: OwnerData)
	data.faulted = true
	finishOperation(data)
end

local function callEngine(data: OwnerData, methodName: string, ...: unknown): (boolean, unknown)
	local engine = data.engine
	if engine == nil then
		return false, nil
	end
	local method = (engine :: any)[methodName]
	if type(method) ~= "function" then
		return false, nil
	end
	return callNonYielding(method, engine, ...)
end

local function inspectRuntimeRoot(data: OwnerData): ("Ok" | "Foreign" | "Failed", Instance?)
	local engine = data.engine
	if engine == nil then
		return "Failed", nil
	end
	local called, childrenValue = callNonYielding(function(parent: Instance): { Instance }
		return parent:GetChildren()
	end, engine.workspace)
	if not called or type(childrenValue) ~= "table" or #childrenValue > MAX_WORKSPACE_CHILDREN then
		return "Failed", nil
	end
	local found: Instance? = nil
	for _, child in childrenValue :: { Instance } do
		if child.Name == RUNTIME_ROOT_NAME then
			if found ~= nil then
				return "Foreign", nil
			end
			found = child
		end
	end
	return "Ok", found
end

local function rootChildrenAreOwned(data: OwnerData, ignoredModel: Model?): boolean
	local root = data.runtimeRoot
	if root == nil then
		return true
	end
	local called, childrenValue = callNonYielding(function(parent: Instance): { Instance }
		return parent:GetChildren()
	end, root)
	if not called or type(childrenValue) ~= "table" or #childrenValue > MAX_ACTIVE + 1 then
		return false
	end
	for _, child in childrenValue :: { Instance } do
		if child ~= ignoredModel then
			local owned = OWNED_MODEL_DATA[child]
			if owned == nil or owned.owner ~= data or (owned.status ~= "Live" and owned.status ~= "Prepared") then
				return false
			end
		end
	end
	return true
end

local function rootIsEmpty(root: Folder): boolean
	local called, childrenValue = callNonYielding(function(parent: Instance): { Instance }
		return parent:GetChildren()
	end, root)
	return called and type(childrenValue) == "table" and #childrenValue == 0
end

local function validateOwnedRoot(data: OwnerData): boolean
	local root = data.runtimeRoot
	local engine = data.engine
	if root == nil or engine == nil then
		return false
	end
	local inspection, existing = inspectRuntimeRoot(data)
	return inspection == "Ok"
		and existing == root
		and root.Name == RUNTIME_ROOT_NAME
		and root.Parent == engine.workspace
		and root:IsA("Folder")
		and OWNED_ROOT_DATA[root] == data
		and rootChildrenAreOwned(data, nil)
end

local function runtimeRootError(data: OwnerData): ErrorCode?
	local engine = data.engine
	if engine == nil then
		return "DEPENDENCY_FAILED"
	end
	local inspection, existing = inspectRuntimeRoot(data)
	if inspection == "Failed" then
		return "DEPENDENCY_FAILED"
	elseif inspection == "Foreign" then
		return "FOREIGN_RUNTIME_ROOT"
	end
	local root = data.runtimeRoot
	if root == nil then
		return if existing == nil then nil else "FOREIGN_RUNTIME_ROOT"
	end
	if
		existing ~= root
		or root.Name ~= RUNTIME_ROOT_NAME
		or root.Parent ~= engine.workspace
		or not root:IsA("Folder")
		or OWNED_ROOT_DATA[root] ~= data
	then
		return "FOREIGN_RUNTIME_ROOT"
	end
	return if rootChildrenAreOwned(data, nil) then nil else "FOREIGN_MODEL"
end

local function ensureRuntimeRoot(data: OwnerData): (Folder?, boolean, ErrorCode?)
	if data.runtimeRoot ~= nil then
		if validateOwnedRoot(data) then
			return data.runtimeRoot, false, nil
		end
		return nil, false, "FOREIGN_RUNTIME_ROOT"
	end
	local inspection, existing = inspectRuntimeRoot(data)
	if inspection == "Failed" then
		return nil, false, "DEPENDENCY_FAILED"
	elseif inspection == "Foreign" or existing ~= nil then
		return nil, false, "FOREIGN_RUNTIME_ROOT"
	end
	local created, folderValue = callEngine(data, "createFolder", RUNTIME_ROOT_NAME)
	if
		not created
		or typeof(folderValue) ~= "Instance"
		or not (folderValue :: Instance):IsA("Folder")
		or (folderValue :: Instance).Name ~= RUNTIME_ROOT_NAME
		or (folderValue :: Instance).Parent ~= nil
		or not operationIntact(data)
	then
		if typeof(folderValue) == "Instance" and (folderValue :: Instance):IsA("Folder") then
			callEngine(data, "destroy", folderValue)
		end
		return nil, false, "DEPENDENCY_FAILED"
	end
	local folder = folderValue :: Folder
	local parented, parentResult = callEngine(data, "setParent", folder, (data.engine :: EngineAdapter).workspace)
	local afterInspection, afterParent = inspectRuntimeRoot(data)
	if
		not parented
		or parentResult ~= true
		or afterInspection ~= "Ok"
		or afterParent ~= folder
		or folder.Parent ~= data.engine.workspace
		or not operationIntact(data)
	then
		callEngine(data, "destroy", folder)
		return nil, false, "DEPENDENCY_FAILED"
	end
	data.runtimeRoot = folder
	OWNED_ROOT_DATA[folder] = data
	return folder, true, nil
end

local function destroyExact(data: OwnerData, instance: Instance): boolean
	local destroyed, destroyValue = callEngine(data, "destroy", instance)
	if destroyed and destroyValue == true and instance.Parent == nil then
		return true
	end
	callEngine(data, "setParent", instance, nil)
	return false
end

local function discardEmptyNewRoot(data: OwnerData, createdRoot: boolean): boolean
	if not createdRoot then
		return true
	end
	local root = data.runtimeRoot
	if root == nil or not rootChildrenAreOwned(data, nil) or not rootIsEmpty(root) then
		return false
	end
	if not destroyExact(data, root) then
		return false
	end
	OWNED_ROOT_DATA[root] = nil
	data.runtimeRoot = nil
	return true
end

local function retainOrphan(data: OwnerData, model: Model, runtimeTowerId: number?, ownedModelData: OwnedModelData?)
	if #data.orphanModels < MAX_ACTIVE + 1 then
		table.insert(data.orphanModels, model)
	end
	local owned = ownedModelData or OWNED_MODEL_DATA[model]
	if owned == nil then
		owned = {
			owner = data,
			runtimeTowerId = runtimeTowerId,
			status = "Orphan",
		}
	else
		owned.status = "Orphan"
	end
	OWNED_MODEL_DATA[model] = owned
end

local function discardPreparedModel(
	data: OwnerData,
	model: Model,
	runtimeTowerId: number?,
	createdRoot: boolean,
	ownedModelData: OwnedModelData?
): boolean
	local owned = ownedModelData or OWNED_MODEL_DATA[model]
	if owned == nil then
		owned = {
			owner = data,
			runtimeTowerId = runtimeTowerId,
			status = "Orphan",
		}
	else
		owned.status = "Orphan"
	end
	OWNED_MODEL_DATA[model] = owned
	local destroyed = destroyExact(data, model)
	if destroyed then
		OWNED_MODEL_DATA[model] = nil
	else
		retainOrphan(data, model, runtimeTowerId, owned)
	end
	return destroyed and discardEmptyNewRoot(data, createdRoot)
end

local function prepareLiveModel(
	data: OwnerData,
	entry: TemplateEntry,
	snapshot: RuntimeTowerSnapshot,
	ownedModelData: OwnedModelData
): (Model?, boolean, ErrorCode?)
	local cloned, cloneValue = callEngine(data, "cloneModel", entry.model)
	if
		not cloned
		or typeof(cloneValue) ~= "Instance"
		or not (cloneValue :: Instance):IsA("Model")
		or cloneValue == entry.model
		or (cloneValue :: Instance).Parent ~= nil
		or not operationIntact(data)
	then
		if typeof(cloneValue) == "Instance" and (cloneValue :: Instance):IsA("Model") and cloneValue ~= entry.model then
			discardPreparedModel(data, cloneValue :: Model, snapshot.runtimeTowerId, false, ownedModelData)
		end
		return nil, false, "DEPENDENCY_FAILED"
	end
	local model = cloneValue :: Model
	OWNED_MODEL_DATA[model] = ownedModelData
	if
		callContract(data, "validateTemplate", entry.definition, nil, model) ~= "Accepted" or not operationIntact(data)
	then
		discardPreparedModel(data, model, snapshot.runtimeTowerId, false, ownedModelData)
		return nil, false, "DEPENDENCY_FAILED"
	end
	local level = entry.definition.levels[snapshot.level]
	if
		callContract(data, "selectLiveVariant", entry.definition, level, model) ~= "Accepted"
		or not operationIntact(data)
	then
		discardPreparedModel(data, model, snapshot.runtimeTowerId, false, ownedModelData)
		return nil, false, "DEPENDENCY_FAILED"
	end
	local pivoted, pivotValue = callEngine(data, "pivotTo", model, snapshot.placementCFrame)
	local pivotRead, pivot = callEngine(data, "getPivot", model)
	if
		not pivoted
		or pivotValue ~= true
		or not pivotRead
		or pivot ~= snapshot.placementCFrame
		or not operationIntact(data)
	then
		discardPreparedModel(data, model, snapshot.runtimeTowerId, false, ownedModelData)
		return nil, false, "DEPENDENCY_FAILED"
	end

	local root, createdRoot, rootError = ensureRuntimeRoot(data)
	if root == nil then
		discardPreparedModel(data, model, snapshot.runtimeTowerId, false, ownedModelData)
		return nil, false, rootError or "DEPENDENCY_FAILED"
	end
	local parented, parentValue = callEngine(data, "setParent", model, root)
	local finalPivotRead, finalPivot = callEngine(data, "getPivot", model)
	if
		not parented
		or parentValue ~= true
		or model.Parent ~= root
		or not finalPivotRead
		or finalPivot ~= snapshot.placementCFrame
		or callContract(data, "validateLive", entry.definition, level, model) ~= "Accepted"
		or not validateOwnedRoot(data)
		or not operationIntact(data)
	then
		discardPreparedModel(data, model, snapshot.runtimeTowerId, createdRoot, ownedModelData)
		return nil, false, "DEPENDENCY_FAILED"
	end
	return model, createdRoot, nil
end

function OwnerMethods.registerTemplate(
	self: Owner,
	definitionValue: unknown,
	modelValue: unknown
): Result.Result<boolean, OwnerError>
	local data = requireData(self)
	local operation: Operation = "registerTemplate"
	local operationError = beginOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local definition = isCanonicalDefinition(data, definitionValue)
	if definition == nil then
		finishOperation(data)
		return failure("INVALID_DEFINITION", operation)
	end
	if data.templatesByTowerId[definition.id] ~= nil then
		finishOperation(data)
		return failure("DUPLICATE_TEMPLATE", operation)
	elseif data.templateCount >= MAX_TEMPLATES then
		finishOperation(data)
		return failure("TEMPLATE_CAPACITY_EXCEEDED", operation)
	end
	if typeof(modelValue) ~= "Instance" or not (modelValue :: Instance):IsA("Model") then
		finishOperation(data)
		return failure("INVALID_TEMPLATE", operation)
	end
	local model = modelValue :: Model
	local successResult = Result.ok(true)
	local templateEntry: TemplateEntry = {
		definition = definition,
		model = model,
	}
	local ownedModelData: OwnedModelData = {
		owner = data,
		runtimeTowerId = nil,
		status = "Template",
	}
	local callerContract = callContract(data, "validateTemplate", definition, nil, model)
	if callerContract == "Rejected" and operationIntact(data) then
		finishOperation(data)
		return failure("INVALID_TEMPLATE", operation)
	elseif callerContract ~= "Accepted" or not operationIntact(data) then
		faultAndFinish(data)
		return failure(if data.cleaned then "CLEANED" else "DEPENDENCY_FAILED", operation)
	end

	local cloned, cloneValue = callEngine(data, "cloneModel", model)
	if
		not cloned
		or typeof(cloneValue) ~= "Instance"
		or not (cloneValue :: Instance):IsA("Model")
		or cloneValue == model
		or (cloneValue :: Instance).Parent ~= nil
		or not operationIntact(data)
	then
		if typeof(cloneValue) == "Instance" and (cloneValue :: Instance):IsA("Model") and cloneValue ~= model then
			discardPreparedModel(data, cloneValue :: Model, nil, false, ownedModelData)
		end
		faultAndFinish(data)
		return failure(if data.cleaned then "CLEANED" else "DEPENDENCY_FAILED", operation)
	end
	local privateTemplate = cloneValue :: Model
	OWNED_MODEL_DATA[privateTemplate] = ownedModelData
	if
		callContract(data, "validateTemplate", definition, nil, privateTemplate) ~= "Accepted"
		or not operationIntact(data)
	then
		discardPreparedModel(data, privateTemplate, nil, false, ownedModelData)
		faultAndFinish(data)
		return failure(if data.cleaned then "CLEANED" else "DEPENDENCY_FAILED", operation)
	end

	templateEntry.model = privateTemplate
	data.templatesByTowerId[definition.id] = templateEntry
	data.templateCount += 1
	finishOperation(data)
	return successResult
end

function OwnerMethods.prepareCreate(self: Owner, snapshotValue: unknown): Result.Result<PreparedVisual, OwnerError>
	local data = requireData(self)
	local operation: Operation = "prepareCreate"
	local operationError = beginOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if data.prepared ~= nil then
		finishOperation(data)
		return failure("REENTRANT", operation)
	end
	local snapshot, definition = validateRuntimeSnapshot(data, snapshotValue)
	if snapshot == nil or definition == nil then
		finishOperation(data)
		return failure("INVALID_RUNTIME_SNAPSHOT", operation)
	end
	if data.liveById[snapshot.runtimeTowerId] ~= nil or data.issuedRuntimeIds[snapshot.runtimeTowerId] == true then
		finishOperation(data)
		return failure("DUPLICATE_RUNTIME_ID", operation)
	elseif data.liveCount >= MAX_ACTIVE then
		finishOperation(data)
		return failure("CAPACITY_EXCEEDED", operation)
	end
	local entry = data.templatesByTowerId[definition.id]
	if entry == nil or entry.definition ~= definition then
		finishOperation(data)
		return failure("MISSING_TEMPLATE", operation)
	end
	local token = table.freeze({}) :: PreparedVisualToken
	local publicValue: PreparedVisual = table.freeze({
		token = token,
		runtimeTowerId = snapshot.runtimeTowerId,
	})
	local receipt: VisualReceipt = table.freeze({
		runtimeTowerId = snapshot.runtimeTowerId,
		status = "Live",
		recreated = false,
	})
	local publicResult = Result.ok(publicValue)
	local commitResult = Result.ok(receipt)
	local ownedModelData: OwnedModelData = {
		owner = data,
		runtimeTowerId = snapshot.runtimeTowerId,
		status = "Prepared",
	}
	local prepared: PreparedVisualData = {
		token = token,
		runtimeTowerId = snapshot.runtimeTowerId,
		model = nil,
		createdRoot = false,
		ownedModelData = ownedModelData,
		publicResult = publicResult,
		commitResult = commitResult,
	}
	local model, createdRoot, prepareError = prepareLiveModel(data, entry, snapshot, ownedModelData)
	if model == nil then
		faultAndFinish(data)
		return failure(if data.cleaned then "CLEANED" else prepareError or "DEPENDENCY_FAILED", operation)
	end
	prepared.model = model
	prepared.createdRoot = createdRoot
	data.prepared = prepared
	PREPARED_TOKEN_DATA[token] = data
	finishOperation(data)
	return prepared.publicResult
end

local function preparedForToken(
	data: OwnerData,
	tokenValue: unknown,
	operation: Operation
): (PreparedVisualData?, OwnerError?)
	local operationError = beginOperation(data, operation)
	if operationError ~= nil then
		return nil, operationError
	end
	local prepared = data.prepared
	if
		type(tokenValue) ~= "table"
		or prepared == nil
		or prepared.token ~= tokenValue
		or PREPARED_TOKEN_DATA[tokenValue :: any] ~= data
	then
		finishOperation(data)
		return nil, makeError("INVALID_TOKEN", operation)
	end
	return prepared, nil
end

function OwnerMethods.commitPreparedCreate(self: Owner, tokenValue: unknown): Result.Result<VisualReceipt, OwnerError>
	local data = requireData(self)
	local operation: Operation = "commitPreparedCreate"
	local prepared, operationError = preparedForToken(data, tokenValue, operation)
	if prepared == nil then
		return Result.err(operationError :: OwnerError)
	end
	local model = prepared.model :: Model
	data.liveById[prepared.runtimeTowerId] = model
	data.issuedRuntimeIds[prepared.runtimeTowerId] = true
	data.liveCount += 1
	prepared.ownedModelData.status = "Live"
	PREPARED_TOKEN_DATA[prepared.token] = nil
	data.prepared = nil
	local commitResult = prepared.commitResult
	finishOperation(data)
	return commitResult
end

function OwnerMethods.abortPreparedCreate(self: Owner, tokenValue: unknown): Result.Result<boolean, OwnerError>
	local data = requireData(self)
	local operation: Operation = "abortPreparedCreate"
	local prepared, operationError = preparedForToken(data, tokenValue, operation)
	if prepared == nil then
		return Result.err(operationError :: OwnerError)
	end
	local successResult = Result.ok(true)
	local model = prepared.model :: Model
	PREPARED_TOKEN_DATA[prepared.token] = nil
	data.prepared = nil
	if
		not discardPreparedModel(data, model, prepared.runtimeTowerId, prepared.createdRoot, prepared.ownedModelData)
		or not operationIntact(data)
	then
		faultAndFinish(data)
		return failure(if data.cleaned then "CLEANED" else "DEPENDENCY_FAILED", operation)
	end
	finishOperation(data)
	return successResult
end

function OwnerMethods.removeVisual(self: Owner, runtimeTowerIdValue: unknown): Result.Result<boolean, OwnerError>
	local data = requireData(self)
	local operation: Operation = "removeVisual"
	local operationError = beginOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if
		type(runtimeTowerIdValue) ~= "number"
		or not Validation.isSafeInteger(runtimeTowerIdValue)
		or runtimeTowerIdValue < 1
		or runtimeTowerIdValue > MAX_RUNTIME_ID
	then
		finishOperation(data)
		return failure("INVALID_RUNTIME_ID", operation)
	end
	local runtimeTowerId = runtimeTowerIdValue :: number
	local model = data.liveById[runtimeTowerId]
	if model == nil then
		finishOperation(data)
		return Result.ok(false)
	end
	local owned = OWNED_MODEL_DATA[model]
	if owned == nil or owned.owner ~= data or owned.runtimeTowerId ~= runtimeTowerId or owned.status ~= "Live" then
		faultAndFinish(data)
		return failure("FOREIGN_MODEL", operation)
	end
	local successResult = Result.ok(true)
	if not destroyExact(data, model) or not operationIntact(data) then
		faultAndFinish(data)
		return failure(if data.cleaned then "CLEANED" else "DEPENDENCY_FAILED", operation)
	end
	OWNED_MODEL_DATA[model] = nil
	data.liveById[runtimeTowerId] = nil
	data.liveCount -= 1
	finishOperation(data)
	return successResult
end

function OwnerMethods.recreateVisual(self: Owner, snapshotValue: unknown): Result.Result<VisualReceipt, OwnerError>
	local data = requireData(self)
	local operation: Operation = "recreateVisual"
	local operationError = beginOperation(data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local snapshot, definition = validateRuntimeSnapshot(data, snapshotValue)
	if snapshot == nil or definition == nil then
		finishOperation(data)
		return failure("INVALID_RUNTIME_SNAPSHOT", operation)
	end
	if data.issuedRuntimeIds[snapshot.runtimeTowerId] ~= true then
		finishOperation(data)
		return failure("INVALID_RUNTIME_ID", operation)
	end
	local entry = data.templatesByTowerId[definition.id]
	if entry == nil or entry.definition ~= definition then
		finishOperation(data)
		return failure("MISSING_TEMPLATE", operation)
	end
	local rootError = runtimeRootError(data)
	if rootError ~= nil then
		faultAndFinish(data)
		return failure(if data.cleaned then "CLEANED" else rootError, operation)
	end
	local recreatedReceipt: VisualReceipt = table.freeze({
		runtimeTowerId = snapshot.runtimeTowerId,
		status = "Live",
		recreated = true,
	})
	local recreatedResult = Result.ok(recreatedReceipt)
	local retainedReceipt: VisualReceipt = table.freeze({
		runtimeTowerId = snapshot.runtimeTowerId,
		status = "Live",
		recreated = false,
	})
	local retainedResult = Result.ok(retainedReceipt)
	local ownedModelData: OwnedModelData = {
		owner = data,
		runtimeTowerId = snapshot.runtimeTowerId,
		status = "Prepared",
	}
	local current = data.liveById[snapshot.runtimeTowerId]
	if current ~= nil then
		local owned = OWNED_MODEL_DATA[current]
		if
			owned == nil
			or owned.owner ~= data
			or owned.runtimeTowerId ~= snapshot.runtimeTowerId
			or owned.status ~= "Live"
		then
			faultAndFinish(data)
			return failure("FOREIGN_MODEL", operation)
		end
		local root = data.runtimeRoot
		local pivotRead, pivot = callEngine(data, "getPivot", current)
		if not pivotRead or not operationIntact(data) then
			faultAndFinish(data)
			return failure(if data.cleaned then "CLEANED" else "DEPENDENCY_FAILED", operation)
		end
		local liveContract = callContract(data, "validateLive", definition, definition.levels[snapshot.level], current)
		if liveContract == "Malformed" or not operationIntact(data) then
			faultAndFinish(data)
			return failure(if data.cleaned then "CLEANED" else "DEPENDENCY_FAILED", operation)
		end
		local validCurrent = root ~= nil
			and validateOwnedRoot(data)
			and current.Parent == root
			and pivot == snapshot.placementCFrame
			and liveContract == "Accepted"
		if validCurrent then
			finishOperation(data)
			return retainedResult
		end
		if not operationIntact(data) then
			faultAndFinish(data)
			return failure(if data.cleaned then "CLEANED" else "DEPENDENCY_FAILED", operation)
		end
		if not destroyExact(data, current) or not operationIntact(data) then
			faultAndFinish(data)
			return failure(if data.cleaned then "CLEANED" else "DEPENDENCY_FAILED", operation)
		end
		OWNED_MODEL_DATA[current] = nil
		data.liveById[snapshot.runtimeTowerId] = nil
		data.liveCount -= 1
	end

	local model, _, prepareError = prepareLiveModel(data, entry, snapshot, ownedModelData)
	if model == nil then
		faultAndFinish(data)
		return failure(if data.cleaned then "CLEANED" else prepareError or "DEPENDENCY_FAILED", operation)
	end
	data.liveById[snapshot.runtimeTowerId] = model
	data.liveCount += 1
	ownedModelData.status = "Live"
	finishOperation(data)
	return recreatedResult
end

function OwnerMethods.getMetrics(self: Owner): Metrics
	local data = requireData(self)
	return table.freeze({
		templateCount = data.templateCount,
		liveModelCount = data.liveCount,
		preparedModelCount = if data.prepared == nil then 0 else 1,
		orphanModelCount = #data.orphanModels,
		hasRuntimeRoot = data.runtimeRoot ~= nil,
		retainsConfiguration = data.configuration ~= nil,
		retainsContractAdapter = data.contract ~= nil,
		retainsEngineAdapter = data.engine ~= nil,
		faulted = data.faulted,
		cleaned = data.cleaned,
	})
end

performCleanup = function(data: OwnerData): boolean
	local allCleaned = true
	local prepared = data.prepared
	if prepared ~= nil then
		local model = prepared.model :: Model
		PREPARED_TOKEN_DATA[prepared.token] = nil
		if destroyExact(data, model) then
			OWNED_MODEL_DATA[model] = nil
			data.prepared = nil
		else
			allCleaned = false
		end
	end

	local runtimeIds = {}
	for runtimeTowerId in data.liveById do
		table.insert(runtimeIds, runtimeTowerId)
	end
	table.sort(runtimeIds)
	for _, runtimeTowerId in runtimeIds do
		local model = data.liveById[runtimeTowerId]
		if model ~= nil then
			local owned = OWNED_MODEL_DATA[model]
			if
				owned ~= nil
				and owned.owner == data
				and owned.runtimeTowerId == runtimeTowerId
				and owned.status == "Live"
				and destroyExact(data, model)
			then
				OWNED_MODEL_DATA[model] = nil
				data.liveById[runtimeTowerId] = nil
				data.liveCount -= 1
			else
				allCleaned = false
			end
		end
	end

	for index = #data.orphanModels, 1, -1 do
		local model = data.orphanModels[index]
		local owned = OWNED_MODEL_DATA[model]
		if owned ~= nil and owned.owner == data and owned.status == "Orphan" and destroyExact(data, model) then
			OWNED_MODEL_DATA[model] = nil
			table.remove(data.orphanModels, index)
		else
			allCleaned = false
		end
	end

	for towerId, entry in data.templatesByTowerId do
		local owned = OWNED_MODEL_DATA[entry.model]
		if owned ~= nil and owned.owner == data and owned.status == "Template" and destroyExact(data, entry.model) then
			OWNED_MODEL_DATA[entry.model] = nil
			data.templatesByTowerId[towerId] = nil
			data.templateCount -= 1
		else
			allCleaned = false
		end
	end

	local root = data.runtimeRoot
	if root ~= nil then
		if OWNED_ROOT_DATA[root] ~= data or not rootChildrenAreOwned(data, nil) or not rootIsEmpty(root) then
			callEngine(data, "setParent", root, nil)
			allCleaned = false
		elseif destroyExact(data, root) then
			OWNED_ROOT_DATA[root] = nil
			data.runtimeRoot = nil
		else
			allCleaned = false
		end
	end

	if not allCleaned then
		data.faulted = true
		return false
	end
	data.configuration = nil
	data.contract = nil
	data.engine = nil
	data.prepared = nil
	table.clear(data.issuedRuntimeIds)
	data.liveCount = 0
	data.templateCount = 0
	data.busy = false
	data.reentryViolation = false
	data.cleanupRequested = false
	data.faulted = false
	data.cleaned = true
	return true
end

function OwnerMethods.cleanup(self: Owner): Result.Result<boolean, OwnerError>
	local data = requireData(self)
	local operation: Operation = "cleanup"
	local inactiveResult = Result.ok(false)
	if data.cleaned then
		return inactiveResult
	end
	if data.busy then
		data.reentryViolation = true
		data.cleanupRequested = true
		return inactiveResult
	end
	local successResult = Result.ok(true)
	local cleanupFailure = failure("CLEANUP_FAILED", operation)
	data.busy = true
	data.cleanupRequested = false
	local cleaned = performCleanup(data)
	if not cleaned then
		data.busy = false
		return cleanupFailure
	end
	return successResult
end

local function construct(
	configurationValue: unknown,
	matchIdValue: unknown,
	towerEpochValue: unknown,
	contractValue: unknown,
	engineValue: unknown
): Result.Result<Owner, OwnerError>
	local operation: Operation = "new"
	if
		not ConfigurationValidator.isValidatedConfiguration(configurationValue)
		or not AssetSchema.isValidatedManifest((configurationValue :: any).assets)
		or not TowerSchema.isValidatedCatalog((configurationValue :: any).towers)
	then
		return failure("UNAUTHENTICATED_CONFIGURATION", operation)
	end
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if not matchIdResult.ok then
		return failure("INVALID_MATCH_ID", operation)
	end
	if
		type(towerEpochValue) ~= "number"
		or not Validation.isSafeInteger(towerEpochValue)
		or towerEpochValue < 1
		or towerEpochValue > MAX_EPOCH
	then
		return failure("INVALID_EPOCH", operation)
	end
	if not isContractAdapter(contractValue) or not isEngineAdapter(engineValue) then
		return failure("INVALID_ADAPTER", operation)
	end

	local data: OwnerData = {
		matchId = matchIdResult.value,
		towerEpoch = towerEpochValue,
		configuration = configurationValue :: ConfigTypes.CoreConfiguration,
		contract = contractValue :: ContractAdapter,
		engine = engineValue :: EngineAdapter,
		templatesByTowerId = {},
		templateCount = 0,
		liveById = {},
		issuedRuntimeIds = {},
		liveCount = 0,
		runtimeRoot = nil,
		prepared = nil,
		orphanModels = {},
		busy = false,
		reentryViolation = false,
		cleanupRequested = false,
		faulted = false,
		cleaned = false,
	}
	local owner = setmetatable({}, OwnerMethods) :: Owner
	table.freeze(owner)
	OWNER_DATA[owner] = data
	return Result.ok(owner)
end

local DefaultEngineAdapter = table.freeze({
	workspace = Workspace,
	cloneModel = function(_self: EngineAdapter, modelValue: unknown): unknown
		if typeof(modelValue) ~= "Instance" or not (modelValue :: Instance):IsA("Model") then
			return nil
		end
		return (modelValue :: Model):Clone()
	end,
	getPivot = function(_self: EngineAdapter, modelValue: unknown): unknown
		if typeof(modelValue) ~= "Instance" or not (modelValue :: Instance):IsA("Model") then
			return nil
		end
		return (modelValue :: Model):GetPivot()
	end,
	pivotTo = function(_self: EngineAdapter, modelValue: unknown, placementValue: unknown): unknown
		if
			typeof(modelValue) ~= "Instance"
			or not (modelValue :: Instance):IsA("Model")
			or typeof(placementValue) ~= "CFrame"
		then
			return false
		end
		(modelValue :: Model):PivotTo(placementValue :: CFrame)
		return true
	end,
	createFolder = function(_self: EngineAdapter, nameValue: unknown): unknown
		if type(nameValue) ~= "string" then
			return nil
		end
		local folder = Instance.new("Folder")
		folder.Name = nameValue
		return folder
	end,
	setParent = function(_self: EngineAdapter, instanceValue: unknown, parentValue: unknown): unknown
		if typeof(instanceValue) ~= "Instance" or (parentValue ~= nil and typeof(parentValue) ~= "Instance") then
			return false
		end
		(instanceValue :: Instance).Parent = parentValue :: Instance?
		return (instanceValue :: Instance).Parent == parentValue
	end,
	destroy = function(_self: EngineAdapter, instanceValue: unknown): unknown
		if typeof(instanceValue) ~= "Instance" then
			return false
		end
		(instanceValue :: Instance):Destroy()
		return true
	end,
}) :: EngineAdapter

local function productionContractAdapter(configuration: ConfigTypes.CoreConfiguration): ContractAdapter
	local contractModule = require(script.Parent.TowerModelContract)
	return table.freeze({
		validateTemplate = function(_self: ContractAdapter, definition: unknown, model: unknown): unknown
			return (contractModule :: any).validateTemplate(configuration, definition, model)
		end,
		selectLiveVariant = function(
			_self: ContractAdapter,
			definition: unknown,
			level: unknown,
			model: unknown
		): unknown
			return (contractModule :: any).selectLiveVariant(configuration, definition, level, model)
		end,
		validateLive = function(_self: ContractAdapter, definition: unknown, level: unknown, model: unknown): unknown
			return (contractModule :: any).validateLive(configuration, definition, level, model)
		end,
	}) :: ContractAdapter
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "TowerModelOwner" then
		return false
	end
	local towersFolder = script.Parent
	if towersFolder == nil or not towersFolder:IsA("Folder") or towersFolder.Name ~= "ProductionServerTowers" then
		return false
	end
	local automatedTests = towersFolder.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	return automatedTests.Parent == ServerStorage
		and automatedTests:FindFirstChild("Support") ~= nil
		and ServerScriptService:FindFirstChild("Server") == nil
end

function TowerModelOwner.new(
	configurationValue: unknown,
	matchIdValue: unknown,
	towerEpochValue: unknown
): Result.Result<Owner, OwnerError>
	if not ConfigurationValidator.isValidatedConfiguration(configurationValue) then
		return failure("UNAUTHENTICATED_CONFIGURATION", "new")
	end
	local configuration = configurationValue :: ConfigTypes.CoreConfiguration
	return construct(
		configuration,
		matchIdValue,
		towerEpochValue,
		productionContractAdapter(configuration),
		DefaultEngineAdapter
	)
end

if isExactTestModule() then
	TowerModelOwner.newForTests = construct
end

table.freeze(OwnerMethods)
return table.freeze(TowerModelOwner)
