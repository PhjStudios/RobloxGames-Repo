--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local DifficultySchema = require(ReplicatedStorage.Shared.config.DifficultySchema)
local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local function resolveEnemyRuntimeStore(): ModuleScript
	local matchRoot = script.Parent.Parent
	local productionFolder = matchRoot:FindFirstChild("enemies")
	if productionFolder ~= nil and productionFolder:IsA("Folder") then
		local module = productionFolder:FindFirstChild("EnemyRuntimeStore")
		if module ~= nil and module:IsA("ModuleScript") then
			return module
		end
	end
	if matchRoot == ServerStorage:FindFirstChild("AutomatedTests") then
		local testFolder = matchRoot:FindFirstChild("ProductionServerEnemies")
		if testFolder ~= nil and testFolder:IsA("Folder") then
			local module = testFolder:FindFirstChild("EnemyRuntimeStore")
			if module ~= nil and module:IsA("ModuleScript") then
				return module
			end
		end
	end
	error("[ATD_BASE_RUNTIME][code=ENEMY_RUNTIME_STORE_MISSING]", 0)
end

local EnemyRuntimeStore = require(resolveEnemyRuntimeStore())

export type RuntimeState = "Uninitialized" | "Active" | "DefeatPending" | "Defeated" | "Faulted" | "Cleaned"
export type VisibleStatus = BaseProtocol.BaseStatus
export type MatchState = "Loading" | "ReadyCheck" | "PreWave" | "WaveActive" | "Results" | "Closing"
export type BaseSnapshot = BaseProtocol.BaseSnapshot

export type AuthenticatedLeakOutcome = {
	matchId: Ids.MatchId,
	enemyEpoch: number,
	runtimeEnemyId: number,
	enemyId: Ids.EnemyId,
	leakDamage: number,
	serverTime: number,
}

export type AppliedLeak = {
	kind: "Applied",
	appliedDamage: number,
	baseRevision: number,
	defeatPending: boolean,
}

export type IgnoredReason =
	"Duplicate"
	| "ConflictingReplay"
	| "Uninitialized"
	| "WrongLifecycle"
	| "PostDefeat"
	| "ZeroDamage"

export type IgnoredLeak = {
	kind: "Ignored",
	reason: IgnoredReason,
	outcomeConsumed: boolean,
}

export type LeakResult = AppliedLeak | IgnoredLeak

export type BoundaryNoop = {
	kind: "Noop",
	passOrdinal: number,
}

export type BoundaryDamage = {
	kind: "Damage",
	passOrdinal: number,
	snapshot: BaseSnapshot,
	appliedDamage: number,
	leakCount: number,
	lowHealthCrossed: boolean,
}

export type BoundaryDefeatPending = {
	kind: "DefeatPending",
	passOrdinal: number,
	baseRevision: number,
	appliedDamage: number,
	leakCount: number,
	lowHealthCrossed: boolean,
	preparedDefeat: PreparedDefeatToken,
}

export type EnemyPassBoundaryOutcome = BoundaryNoop | BoundaryDamage | BoundaryDefeatPending

export type PreparedDefeatToken = {}

export type BaseResultSeed = {
	matchId: Ids.MatchId,
	mapId: Ids.MapId,
	difficultyId: Ids.DifficultyId,
	outcome: "Defeat",
	reason: "BaseHealthDepleted",
	completionServerTime: number,
	currentHealth: number,
	maximumHealth: number,
	baseRevision: number,
}

export type CompletedDefeat = {
	committed: true,
	snapshot: BaseSnapshot,
	resultSeed: BaseResultSeed,
	appliedDamage: number,
	leakCount: number,
	lowHealthCrossed: boolean,
}

export type Operation =
	"new"
	| "installStudioCatalog"
	| "initialize"
	| "recordLeak"
	| "finishEnemyPass"
	| "commitPreparedDefeat"
	| "failPreparedDefeat"
	| "fault"
	| "getSnapshot"
	| "getResultSeed"
	| "isTowerInputOpen"
	| "query"
	| "getDefeatState"
	| "getMetrics"
	| "cleanup"

export type ErrorCode =
	"INVALID_MATCH_ID"
	| "INVALID_EPOCH"
	| "UNAUTHENTICATED_CATALOG"
	| "INVALID_DEPENDENCY"
	| "INVALID_RUNTIME_MAP"
	| "INVALID_DEFINITION"
	| "INVALID_LIFECYCLE"
	| "DUPLICATE_INITIALIZATION"
	| "UNAUTHENTICATED_OUTCOME"
	| "INVALID_OUTCOME"
	| "WRONG_MATCH"
	| "WRONG_EPOCH"
	| "STALE_OUTCOME"
	| "INVALID_PASS"
	| "INVALID_TOKEN"
	| "PASS_EXHAUSTED"
	| "CAPACITY_EXCEEDED"
	| "REVISION_EXHAUSTED"
	| "CLOCK_FAILED"
	| "DEPENDENCY_FAILED"
	| "STUDIO_ONLY"
	| "UNAVAILABLE"
	| "REENTRANT"
	| "FAULTED"
	| "CLEANED"

export type RuntimeError = {
	code: ErrorCode,
	operation: Operation,
}

export type MatchLifecycleAdapter = {
	getSnapshot: (self: MatchLifecycleAdapter) -> unknown,
	getRuntimeMapSnapshot: (self: MatchLifecycleAdapter) -> unknown,
}

export type Query = {
	state: RuntimeState,
	matchId: Ids.MatchId?,
	enemyEpoch: number?,
	mapId: Ids.MapId?,
	difficultyId: Ids.DifficultyId?,
	maximumHealth: number?,
	currentHealth: number?,
	baseRevision: number?,
	lowHealth: boolean?,
	lowHealthCrossingIssued: boolean?,
	processedOutcomeCount: number,
	lastObservedOutcomeServerTime: number?,
	initializedServerTime: number?,
	updatedServerTime: number?,
	towerInputAdmissionClosed: boolean,
	lastFinishedEnemyPassOrdinal: number,
}

export type DefeatState = {
	state: RuntimeState,
	defeatPending: boolean,
	defeated: boolean,
	towerInputAdmissionClosed: boolean,
	baseRevision: number?,
}

export type Metrics = {
	processedOutcomeCount: number,
	pendingLeakCount: number,
	pendingAppliedDamage: number,
	lastFinishedEnemyPassOrdinal: number,
	retainsBoundaryOutcome: boolean,
	retainsIdentity: boolean,
	retainsCatalog: boolean,
	retainsLifecycle: boolean,
	retainsClock: boolean,
	retainsAuthenticator: boolean,
	retainsMapBinding: boolean,
	retainsPreparedDefeat: boolean,
	retainsResultSeed: boolean,
	busy: boolean,
	faulted: boolean,
	cleaned: boolean,
}

type ProcessedLeakIdentity = {
	matchId: Ids.MatchId,
	enemyEpoch: number,
	runtimeEnemyId: number,
	enemyId: Ids.EnemyId,
	leakDamage: number,
	serverTime: number,
}

type PendingFeedback = {
	appliedDamage: number,
	leakCount: number,
	lowHealthCrossed: boolean,
}

type PreparedDefeat = {
	token: PreparedDefeatToken,
	snapshot: BaseSnapshot,
	resultSeed: BaseResultSeed,
	appliedDamage: number,
	leakCount: number,
	lowHealthCrossed: boolean,
}

type Clock = () -> number
type AuthenticateLeakOutcome = (value: unknown) -> boolean

type BasePayload = {
	matchId: Ids.MatchId,
	enemyEpoch: number,
	mapId: Ids.MapId,
	baseCFrame: CFrame,
	basePosition: Vector3,
	difficultyCatalog: ConfigTypes.DifficultyCatalog?,
	difficultyId: Ids.DifficultyId?,
	maximumHealth: number?,
	currentHealth: number?,
	baseRevision: number,
	initialBaseRevision: number,
	initializedServerTime: number?,
	updatedServerTime: number?,
	lastObservedOutcomeServerTime: number?,
	lowHealth: boolean,
	lowHealthCrossingIssued: boolean,
	processedByRuntimeEnemyId: { [number]: ProcessedLeakIdentity },
	processedOutcomeCount: number,
	maxProcessedOutcomes: number,
	pendingFeedback: PendingFeedback?,
	lastFinishedEnemyPassOrdinal: number,
	lastBoundaryOutcome: EnemyPassBoundaryOutcome?,
	preparedDefeat: PreparedDefeat?,
	completedDefeatToken: PreparedDefeatToken?,
	completedDefeat: CompletedDefeat?,
	failedDefeatToken: PreparedDefeatToken?,
	failedDefeatSnapshot: BaseSnapshot?,
	terminalResultSeed: BaseResultSeed?,
	towerInputAdmissionClosed: boolean,
	lifecycle: MatchLifecycleAdapter?,
	clock: Clock?,
	authenticateLeakOutcome: AuthenticateLeakOutcome?,
	studioCatalogInstallEnabled: boolean,
	snapshotAvailable: boolean,
	busy: boolean,
}

type BaseRuntimeRecord = {
	state: RuntimeState,
	payload: BasePayload?,
}

type TestOptions = {
	clock: Clock?,
	authenticateLeakOutcome: AuthenticateLeakOutcome?,
	initialBaseRevision: number?,
	maxProcessedOutcomes: number?,
	studioCatalogInstallEnabled: boolean?,
}

local RuntimeMethods = {}
RuntimeMethods.__index = RuntimeMethods

export type Runtime = typeof(setmetatable({} :: {}, RuntimeMethods))

local BaseRuntime = {}
local RUNTIME_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: BaseRuntimeRecord }

local MAX_DETACHED_NODES = 8_192
local MATCH_STATES: { [string]: boolean } = table.freeze({
	Loading = true,
	ReadyCheck = true,
	PreWave = true,
	WaveActive = true,
	Results = true,
	Closing = true,
})
local MAP_FIELDS: { [string]: boolean } = table.freeze({
	mapId = true,
	base = true,
	bounds = true,
	lanes = true,
	placementZones = true,
	noPlacementZones = true,
	cameraAnchors = true,
	playerSpawns = true,
})
local BASE_FIELDS: { [string]: boolean } = table.freeze({
	cframe = true,
	position = true,
})
local OUTCOME_FIELDS: { [string]: boolean } = table.freeze({
	matchId = true,
	enemyEpoch = true,
	runtimeEnemyId = true,
	enemyId = true,
	leakDamage = true,
	serverTime = true,
})

local function makeError(code: ErrorCode, operation: Operation): RuntimeError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function fail<T>(code: ErrorCode, operation: Operation): Result.Failure<RuntimeError>
	return Result.err(makeError(code, operation))
end

local function getRecord(self: Runtime): BaseRuntimeRecord
	local record = RUNTIME_DATA[self]
	if record == nil then
		error("BaseRuntime method called with an invalid receiver", 2)
	end
	return record
end

local function requirePayload(record: BaseRuntimeRecord): BasePayload
	local payload = record.payload
	if payload == nil then
		error("BaseRuntime non-cleaned record is missing its payload", 2)
	end
	return payload
end

local function hasExactFields(value: { [any]: unknown }, fields: { [string]: boolean }): boolean
	for key in next, value do
		if type(key) ~= "string" or fields[key] ~= true then
			return false
		end
	end
	for field in fields do
		if rawget(value, field) == nil then
			return false
		end
	end
	return true
end

local function isFiniteVector3(value: unknown): boolean
	return typeof(value) == "Vector3"
		and Validation.isFiniteNumber((value :: Vector3).X)
		and Validation.isFiniteNumber((value :: Vector3).Y)
		and Validation.isFiniteNumber((value :: Vector3).Z)
end

local function isFiniteCFrame(value: unknown): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	for _, component in { (value :: CFrame):GetComponents() } do
		if not Validation.isFiniteNumber(component) then
			return false
		end
	end
	return true
end

local function isDetachedDeepFrozen(value: unknown, seen: { [any]: boolean }, count: { number }): boolean
	if typeof(value) == "Instance" then
		return false
	end
	if type(value) == "table" then
		if seen[value :: any] or not table.isfrozen(value :: any) or getmetatable(value :: any) ~= nil then
			return false
		end
		count[1] += 1
		if count[1] > MAX_DETACHED_NODES then
			return false
		end
		seen[value :: any] = true
		for key, child in next, value :: { [any]: unknown } do
			if not isDetachedDeepFrozen(key, seen, count) or not isDetachedDeepFrozen(child, seen, count) then
				return false
			end
		end
		seen[value :: any] = nil
		return true
	end
	if type(value) == "number" then
		return Validation.isFiniteNumber(value :: number)
	end
	if type(value) == "string" or type(value) == "boolean" or value == nil then
		return true
	end
	if typeof(value) == "Vector3" then
		return isFiniteVector3(value)
	end
	if typeof(value) == "CFrame" then
		return isFiniteCFrame(value)
	end
	return false
end

local function invokeNonYielding(callback: (...any) -> ...any, ...: any): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed or coroutine.status(thread) ~= "dead" then
		return false, nil
	end
	return true, value
end

local function validateMatchSnapshot(value: unknown, matchId: Ids.MatchId): MatchState?
	if type(value) ~= "table" or not table.isfrozen(value :: any) or getmetatable(value :: any) ~= nil then
		return nil
	end
	local result = value :: any
	if result.ok ~= true or type(result.value) ~= "table" then
		return nil
	end
	local snapshot = result.value
	if
		not table.isfrozen(snapshot)
		or getmetatable(snapshot) ~= nil
		or snapshot.matchId ~= matchId
		or type(snapshot.state) ~= "string"
		or MATCH_STATES[snapshot.state] ~= true
		or not Validation.isSafeInteger(snapshot.revision)
		or snapshot.revision < 1
	then
		return nil
	end
	return snapshot.state :: MatchState
end

local function readMatchState(data: BasePayload): MatchState?
	local lifecycle = data.lifecycle
	if lifecycle == nil or data.matchId == nil then
		return nil
	end
	local called, value = invokeNonYielding(lifecycle.getSnapshot, lifecycle)
	if not called then
		return nil
	end
	return validateMatchSnapshot(value, data.matchId)
end

local function validateRuntimeMapResult(value: unknown): (Ids.MapId?, CFrame?, Vector3?)
	if type(value) ~= "table" or not table.isfrozen(value :: any) or getmetatable(value :: any) ~= nil then
		return nil, nil, nil
	end
	local result = value :: any
	if result.ok ~= true or type(result.value) ~= "table" then
		return nil, nil, nil
	end
	local map = result.value :: { [any]: unknown }
	if
		not table.isfrozen(map)
		or getmetatable(map) ~= nil
		or not hasExactFields(map, MAP_FIELDS)
		or not isDetachedDeepFrozen(map, {}, { 0 })
	then
		return nil, nil, nil
	end
	local mapIdResult = Ids.validateMapId(map.mapId)
	local base = map.base
	if
		not mapIdResult.ok
		or type(base) ~= "table"
		or not table.isfrozen(base :: any)
		or getmetatable(base :: any) ~= nil
		or not hasExactFields(base :: { [any]: unknown }, BASE_FIELDS)
		or not isFiniteCFrame((base :: any).cframe)
		or not isFiniteVector3((base :: any).position)
		or ((base :: any).cframe :: CFrame).Position ~= ((base :: any).position :: Vector3)
	then
		return nil, nil, nil
	end
	return mapIdResult.value, (base :: any).cframe, (base :: any).position
end

local function readRuntimeMap(lifecycle: MatchLifecycleAdapter): (Ids.MapId?, CFrame?, Vector3?)
	local called, value = invokeNonYielding(lifecycle.getRuntimeMapSnapshot, lifecycle)
	if not called then
		return nil, nil, nil
	end
	return validateRuntimeMapResult(value)
end

local function sampleClock(data: BasePayload): number?
	local clock = data.clock
	if clock == nil then
		return nil
	end
	local called, value = invokeNonYielding(clock)
	if
		not called
		or type(value) ~= "number"
		or not Validation.isFiniteNumber(value :: number)
		or (value :: number) < 0
	then
		return nil
	end
	return value :: number
end

local function validateDefinition(data: BasePayload, value: unknown): ConfigTypes.DifficultyDefinition?
	local catalog = data.difficultyCatalog
	if
		catalog == nil
		or not DifficultySchema.isValidatedCatalog(catalog)
		or type(value) ~= "table"
		or not table.isfrozen(value :: any)
		or getmetatable(value :: any) ~= nil
	then
		return nil
	end
	local definition = value :: any
	local idResult = Ids.validateDifficultyId(definition.id)
	if not idResult.ok or rawget(catalog.byId, idResult.value) ~= value then
		return nil
	end
	local base = definition.base
	if
		type(base) ~= "table"
		or not table.isfrozen(base)
		or getmetatable(base) ~= nil
		or not Validation.isSafeInteger(base.maxHealth)
		or base.maxHealth < 1
	then
		return nil
	end
	return value :: ConfigTypes.DifficultyDefinition
end

local function composeSnapshot(data: BasePayload, status: VisibleStatus): BaseSnapshot?
	if
		data.matchId == nil
		or data.enemyEpoch == nil
		or data.mapId == nil
		or data.difficultyId == nil
		or data.basePosition == nil
		or data.maximumHealth == nil
		or data.currentHealth == nil
		or data.initializedServerTime == nil
		or data.updatedServerTime == nil
	then
		return nil
	end
	local validated = BaseProtocol.validateBaseSnapshot({
		matchId = data.matchId,
		enemyEpoch = data.enemyEpoch,
		mapId = data.mapId,
		difficultyId = data.difficultyId,
		basePosition = data.basePosition,
		baseRevision = data.baseRevision,
		status = status,
		currentHealth = data.currentHealth,
		maximumHealth = data.maximumHealth,
		lowHealth = data.lowHealth,
		initializedServerTime = data.initializedServerTime,
		updatedServerTime = data.updatedServerTime,
	})
	if not validated.ok then
		return nil
	end
	return validated.value
end

local function prepareDefeat(record: BaseRuntimeRecord, data: BasePayload): PreparedDefeat?
	local pending = data.pendingFeedback
	local updatedServerTime = data.updatedServerTime
	if
		record.state ~= "DefeatPending"
		or pending == nil
		or data.matchId == nil
		or data.enemyEpoch == nil
		or data.mapId == nil
		or data.difficultyId == nil
		or data.basePosition == nil
		or data.maximumHealth == nil
		or data.currentHealth ~= 0
		or data.initializedServerTime == nil
		or updatedServerTime == nil
		or data.baseRevision >= Validation.MAX_SAFE_INTEGER
	then
		return nil
	end
	local completionServerTime = sampleClock(data)
	if completionServerTime == nil or completionServerTime < updatedServerTime then
		return nil
	end
	local finalRevision = data.baseRevision + 1
	local snapshotResult = BaseProtocol.validateBaseSnapshot({
		matchId = data.matchId,
		enemyEpoch = data.enemyEpoch,
		mapId = data.mapId,
		difficultyId = data.difficultyId,
		basePosition = data.basePosition,
		baseRevision = finalRevision,
		status = "Defeated",
		currentHealth = 0,
		maximumHealth = data.maximumHealth,
		lowHealth = true,
		initializedServerTime = data.initializedServerTime,
		updatedServerTime = completionServerTime,
	})
	if not snapshotResult.ok then
		return nil
	end
	local resultSeed: BaseResultSeed = table.freeze({
		matchId = data.matchId,
		mapId = data.mapId,
		difficultyId = data.difficultyId,
		outcome = "Defeat",
		reason = "BaseHealthDepleted",
		completionServerTime = completionServerTime,
		currentHealth = 0,
		maximumHealth = data.maximumHealth,
		baseRevision = finalRevision,
	})
	local token = table.freeze({}) :: PreparedDefeatToken
	return {
		token = token,
		snapshot = snapshotResult.value,
		resultSeed = resultSeed,
		appliedDamage = pending.appliedDamage,
		leakCount = pending.leakCount,
		lowHealthCrossed = pending.lowHealthCrossed,
	}
end

local function faultRuntime(record: BaseRuntimeRecord, data: BasePayload, updateTime: number?)
	if record.state == "Cleaned" or record.state == "Defeated" then
		return
	end
	data.pendingFeedback = nil
	data.preparedDefeat = nil
	data.completedDefeatToken = nil
	data.completedDefeat = nil
	data.terminalResultSeed = nil
	data.lastBoundaryOutcome = nil
	data.towerInputAdmissionClosed = true
	if data.maximumHealth ~= nil and data.baseRevision < Validation.MAX_SAFE_INTEGER then
		data.baseRevision += 1
		if updateTime ~= nil and data.updatedServerTime ~= nil and updateTime >= data.updatedServerTime then
			data.updatedServerTime = updateTime
		end
		data.snapshotAvailable = true
	elseif data.maximumHealth ~= nil then
		data.snapshotAvailable = false
	end
	record.state = "Faulted"
end

local function enterOperation(record: BaseRuntimeRecord, data: BasePayload, operation: Operation): RuntimeError?
	if record.state == "Cleaned" then
		return makeError("CLEANED", operation)
	end
	if data.busy then
		return makeError("REENTRANT", operation)
	end
	if record.state == "Faulted" then
		return makeError("FAULTED", operation)
	end
	data.busy = true
	return nil
end

local function exactProcessedMatch(left: ProcessedLeakIdentity, right: AuthenticatedLeakOutcome): boolean
	return left.matchId == right.matchId
		and left.enemyEpoch == right.enemyEpoch
		and left.runtimeEnemyId == right.runtimeEnemyId
		and left.enemyId == right.enemyId
		and left.leakDamage == right.leakDamage
		and left.serverTime == right.serverTime
end

local function validateOutcomeShape(value: unknown): AuthenticatedLeakOutcome?
	if
		type(value) ~= "table"
		or not table.isfrozen(value :: any)
		or getmetatable(value :: any) ~= nil
		or not hasExactFields(value :: { [any]: unknown }, OUTCOME_FIELDS)
	then
		return nil
	end
	local outcome = value :: any
	local enemyIdResult = Ids.validateEnemyId(outcome.enemyId)
	if
		type(outcome.matchId) ~= "string"
		or not Validation.isSafeInteger(outcome.enemyEpoch)
		or outcome.enemyEpoch < 1
		or outcome.enemyEpoch > EnemyProtocol.MAX_ENEMY_EPOCH
		or not Validation.isSafeInteger(outcome.runtimeEnemyId)
		or outcome.runtimeEnemyId < 1
		or outcome.runtimeEnemyId > EnemyProtocol.MAX_LIFETIME_ENEMIES
		or not enemyIdResult.ok
		or not Validation.isSafeInteger(outcome.leakDamage)
		or outcome.leakDamage < 0
		or type(outcome.serverTime) ~= "number"
		or not Validation.isFiniteNumber(outcome.serverTime)
		or outcome.serverTime < 0
	then
		return nil
	end
	return value :: AuthenticatedLeakOutcome
end

local function ignored(reason: IgnoredReason, outcomeConsumed: boolean): Result.Success<LeakResult>
	return Result.ok(table.freeze({
		kind = "Ignored",
		reason = reason,
		outcomeConsumed = outcomeConsumed,
	}) :: IgnoredLeak)
end

local function clearRecord(record: BaseRuntimeRecord)
	record.state, record.payload = "Cleaned", nil
end

function RuntimeMethods.installStudioCatalog(self: Runtime, catalogValue: unknown): Result.Result<boolean, RuntimeError>
	local record = getRecord(self)
	local operation: Operation = "installStudioCatalog"
	if record.state == "Cleaned" then
		return fail("CLEANED", operation)
	end
	local data = requirePayload(record)
	local operationError = enterOperation(record, data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end

	if not data.studioCatalogInstallEnabled then
		data.busy = false
		return fail("STUDIO_ONLY", operation)
	end
	if not DifficultySchema.isValidatedCatalog(catalogValue) then
		data.busy = false
		return fail("UNAUTHENTICATED_CATALOG", operation)
	end

	local currentCatalog = data.difficultyCatalog
	if
		record.state ~= "Uninitialized"
		or currentCatalog == nil
		or not DifficultySchema.isValidatedCatalog(currentCatalog)
		or #currentCatalog.ordered ~= 0
		or next(currentCatalog.byId) ~= nil
		or catalogValue == currentCatalog
		or data.difficultyId ~= nil
		or data.maximumHealth ~= nil
		or data.currentHealth ~= nil
		or data.baseRevision ~= 0
		or data.initializedServerTime ~= nil
		or data.updatedServerTime ~= nil
		or data.lastObservedOutcomeServerTime ~= nil
		or data.lowHealth
		or data.lowHealthCrossingIssued
		or data.processedOutcomeCount ~= 0
		or next(data.processedByRuntimeEnemyId) ~= nil
		or data.pendingFeedback ~= nil
		or data.preparedDefeat ~= nil
		or data.completedDefeatToken ~= nil
		or data.completedDefeat ~= nil
		or data.failedDefeatToken ~= nil
		or data.failedDefeatSnapshot ~= nil
		or data.terminalResultSeed ~= nil
		or not data.towerInputAdmissionClosed
		or data.snapshotAvailable
	then
		data.busy = false
		return fail("INVALID_LIFECYCLE", operation)
	end

	data.difficultyCatalog = catalogValue :: ConfigTypes.DifficultyCatalog
	data.studioCatalogInstallEnabled = false
	data.busy = false
	return Result.ok(true)
end

function RuntimeMethods.initialize(self: Runtime, definitionValue: unknown): Result.Result<BaseSnapshot, RuntimeError>
	local record = getRecord(self)
	local operation: Operation = "initialize"
	if record.state == "Cleaned" then
		return fail("CLEANED", operation)
	end
	local data = requirePayload(record)
	local operationError = enterOperation(record, data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end

	if record.state ~= "Uninitialized" then
		data.busy = false
		return fail("DUPLICATE_INITIALIZATION", operation)
	end
	local definition = validateDefinition(data, definitionValue)
	if definition == nil then
		data.busy = false
		return fail("INVALID_DEFINITION", operation)
	end
	local matchState = readMatchState(data)
	if matchState == nil then
		faultRuntime(record, data, nil)
		data.busy = false
		return fail("DEPENDENCY_FAILED", operation)
	end
	if matchState ~= "ReadyCheck" and matchState ~= "PreWave" then
		data.busy = false
		return fail("INVALID_LIFECYCLE", operation)
	end
	local now = sampleClock(data)
	if now == nil then
		faultRuntime(record, data, nil)
		data.busy = false
		return fail("CLOCK_FAILED", operation)
	end

	data.difficultyId = definition.id
	data.maximumHealth = definition.base.maxHealth
	data.currentHealth = definition.base.maxHealth
	data.baseRevision = data.initialBaseRevision
	data.initializedServerTime = now
	data.updatedServerTime = now
	data.lowHealth = false
	data.lowHealthCrossingIssued = false
	data.towerInputAdmissionClosed = false
	record.state = "Active"
	data.snapshotAvailable = true
	local snapshot = composeSnapshot(data, "Active")
	if snapshot == nil then
		faultRuntime(record, data, now)
		data.busy = false
		return fail("UNAVAILABLE", operation)
	end
	data.busy = false
	return Result.ok(snapshot)
end

function RuntimeMethods.recordLeak(self: Runtime, outcomeValue: unknown): Result.Result<LeakResult, RuntimeError>
	local record = getRecord(self)
	local operation: Operation = "recordLeak"
	if record.state == "Cleaned" then
		return fail("CLEANED", operation)
	end
	local data = requirePayload(record)
	local operationError = enterOperation(record, data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end

	local authenticate = data.authenticateLeakOutcome
	if authenticate == nil then
		faultRuntime(record, data, nil)
		data.busy = false
		return fail("DEPENDENCY_FAILED", operation)
	end
	local authenticatedCall, authenticated = invokeNonYielding(authenticate, outcomeValue)
	if not authenticatedCall then
		faultRuntime(record, data, nil)
		data.busy = false
		return fail("DEPENDENCY_FAILED", operation)
	end
	if authenticated ~= true then
		data.busy = false
		return fail("UNAUTHENTICATED_OUTCOME", operation)
	end

	local outcome = validateOutcomeShape(outcomeValue)
	if outcome == nil then
		faultRuntime(record, data, nil)
		data.busy = false
		return fail("INVALID_OUTCOME", operation)
	end
	if outcome.matchId ~= data.matchId then
		data.busy = false
		return fail("WRONG_MATCH", operation)
	end
	if outcome.enemyEpoch ~= data.enemyEpoch then
		data.busy = false
		return fail("WRONG_EPOCH", operation)
	end

	local existing = data.processedByRuntimeEnemyId[outcome.runtimeEnemyId]
	if existing ~= nil then
		data.busy = false
		if exactProcessedMatch(existing, outcome) then
			return ignored("Duplicate", true)
		end
		return ignored("ConflictingReplay", false)
	end
	local minimumOutcomeTime = data.lastObservedOutcomeServerTime
	if
		data.initializedServerTime ~= nil
		and (minimumOutcomeTime == nil or data.initializedServerTime > minimumOutcomeTime)
	then
		minimumOutcomeTime = data.initializedServerTime
	end
	if minimumOutcomeTime ~= nil and outcome.serverTime < minimumOutcomeTime then
		data.busy = false
		return fail("STALE_OUTCOME", operation)
	end
	if data.processedOutcomeCount >= data.maxProcessedOutcomes then
		faultRuntime(record, data, outcome.serverTime)
		data.busy = false
		return fail("CAPACITY_EXCEEDED", operation)
	end

	local copiedIdentity: ProcessedLeakIdentity = table.freeze({
		matchId = outcome.matchId,
		enemyEpoch = outcome.enemyEpoch,
		runtimeEnemyId = outcome.runtimeEnemyId,
		enemyId = outcome.enemyId,
		leakDamage = outcome.leakDamage,
		serverTime = outcome.serverTime,
	})
	data.processedByRuntimeEnemyId[outcome.runtimeEnemyId] = copiedIdentity
	data.processedOutcomeCount += 1
	data.lastObservedOutcomeServerTime = outcome.serverTime

	if record.state == "Uninitialized" then
		data.busy = false
		return ignored("Uninitialized", true)
	end
	if record.state == "DefeatPending" or record.state == "Defeated" then
		data.busy = false
		return ignored("PostDefeat", true)
	end
	if record.state ~= "Active" then
		faultRuntime(record, data, outcome.serverTime)
		data.busy = false
		return fail("UNAVAILABLE", operation)
	end

	local matchState = readMatchState(data)
	if matchState == nil then
		faultRuntime(record, data, outcome.serverTime)
		data.busy = false
		return fail("DEPENDENCY_FAILED", operation)
	end
	if matchState ~= "WaveActive" then
		data.busy = false
		return ignored("WrongLifecycle", true)
	end
	if outcome.leakDamage == 0 then
		data.busy = false
		return ignored("ZeroDamage", true)
	end

	local currentHealth = data.currentHealth
	local maximumHealth = data.maximumHealth
	if
		currentHealth == nil
		or maximumHealth == nil
		or not Validation.isSafeInteger(currentHealth)
		or not Validation.isSafeInteger(maximumHealth)
		or currentHealth < 1
		or currentHealth > maximumHealth
	then
		faultRuntime(record, data, outcome.serverTime)
		data.busy = false
		return fail("UNAVAILABLE", operation)
	end

	local lethal = outcome.leakDamage >= currentHealth
	local requiredRevisionSlots = if lethal then 2 else 1
	if data.baseRevision > Validation.MAX_SAFE_INTEGER - requiredRevisionSlots then
		faultRuntime(record, data, outcome.serverTime)
		data.busy = false
		return fail("REVISION_EXHAUSTED", operation)
	end

	local appliedDamage = if lethal then currentHealth else outcome.leakDamage
	local nextHealth = if lethal then 0 else currentHealth - outcome.leakDamage
	data.currentHealth = nextHealth
	data.baseRevision += 1
	data.updatedServerTime = outcome.serverTime
	local lowHealthCrossed = false
	if not data.lowHealth and nextHealth <= maximumHealth / 4 then
		data.lowHealth = true
		if not data.lowHealthCrossingIssued then
			data.lowHealthCrossingIssued = true
			lowHealthCrossed = true
		end
	end
	local pending = data.pendingFeedback
	if pending == nil then
		data.pendingFeedback = {
			appliedDamage = appliedDamage,
			leakCount = 1,
			lowHealthCrossed = lowHealthCrossed,
		}
	else
		pending.appliedDamage = if appliedDamage >= maximumHealth - pending.appliedDamage
			then maximumHealth
			else pending.appliedDamage + appliedDamage
		pending.leakCount = math.min(EnemyProtocol.MAX_ACTIVE_ENEMIES, pending.leakCount + 1)
		pending.lowHealthCrossed = pending.lowHealthCrossed or lowHealthCrossed
	end
	if lethal then
		record.state = "DefeatPending"
		data.towerInputAdmissionClosed = true
		data.snapshotAvailable = false
	end

	local applied: AppliedLeak = table.freeze({
		kind = "Applied",
		appliedDamage = appliedDamage,
		baseRevision = data.baseRevision,
		defeatPending = lethal,
	})
	data.busy = false
	return Result.ok(applied)
end

function RuntimeMethods.finishEnemyPass(
	self: Runtime,
	passOrdinalValue: unknown
): Result.Result<EnemyPassBoundaryOutcome, RuntimeError>
	local record = getRecord(self)
	local operation: Operation = "finishEnemyPass"
	if record.state == "Cleaned" then
		return fail("CLEANED", operation)
	end
	local data = requirePayload(record)
	local operationError = enterOperation(record, data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if
		type(passOrdinalValue) ~= "number"
		or not Validation.isSafeInteger(passOrdinalValue :: number)
		or (passOrdinalValue :: number) < 1
	then
		data.busy = false
		return fail("INVALID_PASS", operation)
	end

	local passOrdinal = passOrdinalValue :: number
	if passOrdinal == data.lastFinishedEnemyPassOrdinal then
		local cached = data.lastBoundaryOutcome
		data.busy = false
		if cached == nil then
			return fail("INVALID_PASS", operation)
		end
		return Result.ok(cached)
	end
	if data.lastFinishedEnemyPassOrdinal >= Validation.MAX_SAFE_INTEGER then
		faultRuntime(record, data, data.updatedServerTime)
		data.busy = false
		return fail("PASS_EXHAUSTED", operation)
	end
	if passOrdinal ~= data.lastFinishedEnemyPassOrdinal + 1 then
		data.busy = false
		return fail("INVALID_PASS", operation)
	end

	local pending = data.pendingFeedback
	local outcome: EnemyPassBoundaryOutcome
	if pending == nil then
		if record.state == "DefeatPending" then
			faultRuntime(record, data, data.updatedServerTime)
			data.busy = false
			return fail("UNAVAILABLE", operation)
		end
		outcome = table.freeze({
			kind = "Noop",
			passOrdinal = passOrdinal,
		})
	elseif record.state == "Active" then
		local snapshot = composeSnapshot(data, "Active")
		if snapshot == nil then
			faultRuntime(record, data, data.updatedServerTime)
			data.busy = false
			return fail("UNAVAILABLE", operation)
		end
		outcome = table.freeze({
			kind = "Damage",
			passOrdinal = passOrdinal,
			snapshot = snapshot,
			appliedDamage = pending.appliedDamage,
			leakCount = pending.leakCount,
			lowHealthCrossed = pending.lowHealthCrossed,
		})
		data.pendingFeedback = nil
	elseif record.state == "DefeatPending" then
		local prepared = data.preparedDefeat
		if prepared == nil then
			prepared = prepareDefeat(record, data)
			if prepared == nil then
				faultRuntime(record, data, data.updatedServerTime)
				data.busy = false
				return fail("CLOCK_FAILED", operation)
			end
			data.preparedDefeat = prepared
		end
		outcome = table.freeze({
			kind = "DefeatPending",
			passOrdinal = passOrdinal,
			baseRevision = data.baseRevision,
			appliedDamage = pending.appliedDamage,
			leakCount = pending.leakCount,
			lowHealthCrossed = pending.lowHealthCrossed,
			preparedDefeat = prepared.token,
		})
	else
		faultRuntime(record, data, data.updatedServerTime)
		data.busy = false
		return fail("UNAVAILABLE", operation)
	end

	data.lastFinishedEnemyPassOrdinal = passOrdinal
	data.lastBoundaryOutcome = outcome
	data.busy = false
	return Result.ok(outcome)
end

function RuntimeMethods.commitPreparedDefeat(
	self: Runtime,
	tokenValue: unknown
): Result.Result<CompletedDefeat, RuntimeError>
	local record = getRecord(self)
	local operation: Operation = "commitPreparedDefeat"
	if record.state == "Cleaned" then
		return fail("CLEANED", operation)
	end
	local data = requirePayload(record)
	if tokenValue == data.completedDefeatToken and data.completedDefeat ~= nil then
		return Result.ok(data.completedDefeat)
	end
	local operationError = enterOperation(record, data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local prepared = data.preparedDefeat
	if record.state ~= "DefeatPending" or prepared == nil or tokenValue ~= prepared.token then
		data.busy = false
		return fail("INVALID_TOKEN", operation)
	end

	local snapshot = prepared.snapshot
	data.baseRevision = snapshot.baseRevision
	data.updatedServerTime = snapshot.updatedServerTime
	data.pendingFeedback = nil
	data.preparedDefeat = nil
	data.terminalResultSeed = prepared.resultSeed
	record.state = "Defeated"
	data.snapshotAvailable = true
	data.towerInputAdmissionClosed = true
	local completed: CompletedDefeat = table.freeze({
		committed = true,
		snapshot = snapshot,
		resultSeed = prepared.resultSeed,
		appliedDamage = prepared.appliedDamage,
		leakCount = prepared.leakCount,
		lowHealthCrossed = prepared.lowHealthCrossed,
	})
	data.completedDefeatToken = prepared.token
	data.completedDefeat = completed
	data.busy = false
	return Result.ok(completed)
end

function RuntimeMethods.failPreparedDefeat(
	self: Runtime,
	tokenValue: unknown
): Result.Result<BaseSnapshot, RuntimeError>
	local record = getRecord(self)
	local operation: Operation = "failPreparedDefeat"
	if record.state == "Cleaned" then
		return fail("CLEANED", operation)
	end
	local data = requirePayload(record)
	if tokenValue == data.failedDefeatToken and data.failedDefeatSnapshot ~= nil then
		return Result.ok(data.failedDefeatSnapshot)
	end
	local operationError = enterOperation(record, data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local prepared = data.preparedDefeat
	if record.state ~= "DefeatPending" or prepared == nil or tokenValue ~= prepared.token then
		data.busy = false
		return fail("INVALID_TOKEN", operation)
	end

	data.preparedDefeat = nil
	data.pendingFeedback = nil
	data.terminalResultSeed = nil
	data.failedDefeatToken = prepared.token
	faultRuntime(record, data, prepared.snapshot.updatedServerTime)
	local snapshot = composeSnapshot(data, "Faulted")
	if snapshot == nil then
		data.snapshotAvailable = false
		data.busy = false
		return fail("UNAVAILABLE", operation)
	end
	data.failedDefeatSnapshot = snapshot
	data.busy = false
	return Result.ok(snapshot)
end

function RuntimeMethods.fault(self: Runtime): Result.Result<BaseSnapshot, RuntimeError>
	local record = getRecord(self)
	local operation: Operation = "fault"
	if record.state == "Cleaned" then
		return fail("CLEANED", operation)
	end
	local data = requirePayload(record)
	local operationError = enterOperation(record, data, operation)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if record.state == "Defeated" then
		local snapshot = composeSnapshot(data, "Defeated")
		data.busy = false
		if snapshot == nil then
			return fail("UNAVAILABLE", operation)
		end
		return Result.ok(snapshot)
	end
	local now = sampleClock(data)
	if now == nil then
		now = data.updatedServerTime
	end
	faultRuntime(record, data, now)
	local snapshot = composeSnapshot(data, "Faulted")
	data.busy = false
	if snapshot == nil then
		return fail("UNAVAILABLE", operation)
	end
	return Result.ok(snapshot)
end

function RuntimeMethods.getResultSeed(self: Runtime): Result.Result<BaseResultSeed, RuntimeError>
	local record = getRecord(self)
	local operation: Operation = "getResultSeed"
	if record.state == "Cleaned" then
		return fail("CLEANED", operation)
	end
	local data = requirePayload(record)
	if record.state ~= "Defeated" or data.terminalResultSeed == nil then
		return fail("UNAVAILABLE", operation)
	end
	return Result.ok(data.terminalResultSeed)
end

function RuntimeMethods.isTowerInputOpen(self: Runtime): boolean
	local record = getRecord(self)
	if record.state ~= "Active" then
		return false
	end
	local data = requirePayload(record)
	if data.towerInputAdmissionClosed then
		return false
	end
	return readMatchState(data) == "WaveActive"
end

function RuntimeMethods.getSnapshot(self: Runtime): Result.Result<BaseSnapshot, RuntimeError>
	local record = getRecord(self)
	local operation: Operation = "getSnapshot"
	if record.state == "Cleaned" then
		return fail("CLEANED", operation)
	end
	local data = requirePayload(record)
	if not data.snapshotAvailable or record.state == "Uninitialized" or record.state == "DefeatPending" then
		return fail("UNAVAILABLE", operation)
	end
	local status: VisibleStatus = if record.state == "Defeated"
		then "Defeated"
		elseif record.state == "Faulted" then "Faulted"
		else "Active"
	local snapshot = composeSnapshot(data, status)
	if snapshot == nil then
		return fail("UNAVAILABLE", operation)
	end
	return Result.ok(snapshot)
end

function RuntimeMethods.query(self: Runtime): Query
	local record = getRecord(self)
	if record.state == "Cleaned" then
		return table.freeze({
			state = "Cleaned",
			processedOutcomeCount = 0,
			towerInputAdmissionClosed = true,
			lastFinishedEnemyPassOrdinal = 0,
		})
	end
	local data = requirePayload(record)
	return table.freeze({
		state = record.state,
		matchId = data.matchId,
		enemyEpoch = data.enemyEpoch,
		mapId = data.mapId,
		difficultyId = data.difficultyId,
		maximumHealth = data.maximumHealth,
		currentHealth = data.currentHealth,
		baseRevision = data.baseRevision,
		lowHealth = data.lowHealth,
		lowHealthCrossingIssued = data.lowHealthCrossingIssued,
		processedOutcomeCount = data.processedOutcomeCount,
		lastObservedOutcomeServerTime = data.lastObservedOutcomeServerTime,
		initializedServerTime = data.initializedServerTime,
		updatedServerTime = data.updatedServerTime,
		towerInputAdmissionClosed = data.towerInputAdmissionClosed,
		lastFinishedEnemyPassOrdinal = data.lastFinishedEnemyPassOrdinal,
	})
end

function RuntimeMethods.getDefeatState(self: Runtime): DefeatState
	local record = getRecord(self)
	if record.state == "Cleaned" then
		return table.freeze({
			state = "Cleaned",
			defeatPending = false,
			defeated = false,
			towerInputAdmissionClosed = true,
		})
	end
	local data = requirePayload(record)
	return table.freeze({
		state = record.state,
		defeatPending = record.state == "DefeatPending",
		defeated = record.state == "Defeated",
		towerInputAdmissionClosed = data.towerInputAdmissionClosed,
		baseRevision = data.baseRevision,
	})
end

function RuntimeMethods.getMetrics(self: Runtime): Metrics
	local record = getRecord(self)
	if record.state == "Cleaned" then
		return table.freeze({
			processedOutcomeCount = 0,
			pendingLeakCount = 0,
			pendingAppliedDamage = 0,
			lastFinishedEnemyPassOrdinal = 0,
			retainsBoundaryOutcome = false,
			retainsIdentity = false,
			retainsCatalog = false,
			retainsLifecycle = false,
			retainsClock = false,
			retainsAuthenticator = false,
			retainsMapBinding = false,
			retainsPreparedDefeat = false,
			retainsResultSeed = false,
			busy = false,
			faulted = false,
			cleaned = true,
		})
	end
	local data = requirePayload(record)
	local pending = data.pendingFeedback
	return table.freeze({
		processedOutcomeCount = data.processedOutcomeCount,
		pendingLeakCount = if pending == nil then 0 else pending.leakCount,
		pendingAppliedDamage = if pending == nil then 0 else pending.appliedDamage,
		lastFinishedEnemyPassOrdinal = data.lastFinishedEnemyPassOrdinal,
		retainsBoundaryOutcome = data.lastBoundaryOutcome ~= nil,
		retainsIdentity = data.matchId ~= nil or data.enemyEpoch ~= nil,
		retainsCatalog = data.difficultyCatalog ~= nil,
		retainsLifecycle = data.lifecycle ~= nil,
		retainsClock = data.clock ~= nil,
		retainsAuthenticator = data.authenticateLeakOutcome ~= nil,
		retainsMapBinding = data.mapId ~= nil or data.baseCFrame ~= nil or data.basePosition ~= nil,
		retainsPreparedDefeat = data.preparedDefeat ~= nil,
		retainsResultSeed = data.terminalResultSeed ~= nil,
		busy = data.busy,
		faulted = record.state == "Faulted",
		cleaned = false,
	})
end

function RuntimeMethods.cleanup(self: Runtime): Result.Result<boolean, RuntimeError>
	local record = getRecord(self)
	local operation: Operation = "cleanup"
	if record.state == "Cleaned" then
		return Result.ok(false)
	end
	local data = requirePayload(record)
	if data.busy then
		return fail("REENTRANT", operation)
	end
	data.busy = true
	clearRecord(record)
	return Result.ok(true)
end

local function construct(
	matchIdValue: unknown,
	enemyEpochValue: unknown,
	difficultyCatalogValue: unknown,
	lifecycleValue: unknown,
	options: TestOptions
): Result.Result<Runtime, RuntimeError>
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if not matchIdResult.ok then
		return fail("INVALID_MATCH_ID", "new")
	end
	if
		type(enemyEpochValue) ~= "number"
		or not Validation.isSafeInteger(enemyEpochValue :: number)
		or (enemyEpochValue :: number) < 1
		or (enemyEpochValue :: number) > EnemyProtocol.MAX_ENEMY_EPOCH
	then
		return fail("INVALID_EPOCH", "new")
	end
	if type(difficultyCatalogValue) ~= "table" or not DifficultySchema.isValidatedCatalog(difficultyCatalogValue) then
		return fail("UNAUTHENTICATED_CATALOG", "new")
	end
	if
		type(lifecycleValue) ~= "table"
		or type((lifecycleValue :: any).getSnapshot) ~= "function"
		or type((lifecycleValue :: any).getRuntimeMapSnapshot) ~= "function"
	then
		return fail("INVALID_DEPENDENCY", "new")
	end
	local lifecycle = lifecycleValue :: MatchLifecycleAdapter
	local matchStateCall, matchSnapshot = invokeNonYielding(lifecycle.getSnapshot, lifecycle)
	if not matchStateCall or validateMatchSnapshot(matchSnapshot, matchIdResult.value) == nil then
		return fail("INVALID_DEPENDENCY", "new")
	end
	local mapId, baseCFrame, basePosition = readRuntimeMap(lifecycle)
	if mapId == nil or baseCFrame == nil or basePosition == nil then
		return fail("INVALID_RUNTIME_MAP", "new")
	end

	local initialBaseRevision = options.initialBaseRevision or 1
	local maxProcessedOutcomes = options.maxProcessedOutcomes or EnemyProtocol.MAX_LIFETIME_ENEMIES
	local clock = options.clock or function(): number
		return Workspace:GetServerTimeNow()
	end
	local authenticate = options.authenticateLeakOutcome or EnemyRuntimeStore.isAuthenticatedLeakOutcome
	if
		not Validation.isSafeInteger(initialBaseRevision)
		or initialBaseRevision < 1
		or not Validation.isSafeInteger(maxProcessedOutcomes)
		or maxProcessedOutcomes < 1
		or maxProcessedOutcomes > EnemyProtocol.MAX_LIFETIME_ENEMIES
		or type(clock) ~= "function"
		or type(authenticate) ~= "function"
		or (options.studioCatalogInstallEnabled ~= nil and type(options.studioCatalogInstallEnabled) ~= "boolean")
	then
		return fail("INVALID_DEPENDENCY", "new")
	end

	local runtime = setmetatable({}, RuntimeMethods) :: Runtime
	table.freeze(runtime)
	local payload: BasePayload = {
		matchId = matchIdResult.value,
		enemyEpoch = enemyEpochValue :: number,
		mapId = mapId,
		baseCFrame = baseCFrame,
		basePosition = basePosition,
		difficultyCatalog = difficultyCatalogValue :: ConfigTypes.DifficultyCatalog,
		difficultyId = nil,
		maximumHealth = nil,
		currentHealth = nil,
		baseRevision = 0,
		initialBaseRevision = initialBaseRevision,
		initializedServerTime = nil,
		updatedServerTime = nil,
		lastObservedOutcomeServerTime = nil,
		lowHealth = false,
		lowHealthCrossingIssued = false,
		processedByRuntimeEnemyId = {},
		processedOutcomeCount = 0,
		maxProcessedOutcomes = maxProcessedOutcomes,
		pendingFeedback = nil,
		lastFinishedEnemyPassOrdinal = 0,
		lastBoundaryOutcome = nil,
		preparedDefeat = nil,
		completedDefeatToken = nil,
		completedDefeat = nil,
		failedDefeatToken = nil,
		failedDefeatSnapshot = nil,
		terminalResultSeed = nil,
		towerInputAdmissionClosed = true,
		lifecycle = lifecycle,
		clock = clock,
		authenticateLeakOutcome = authenticate,
		studioCatalogInstallEnabled = options.studioCatalogInstallEnabled == true,
		snapshotAvailable = false,
		busy = false,
	}
	RUNTIME_DATA[runtime] = {
		state = "Uninitialized",
		payload = payload,
	}
	return Result.ok(runtime)
end

function BaseRuntime.new(
	matchIdValue: unknown,
	enemyEpochValue: unknown,
	difficultyCatalogValue: unknown,
	lifecycleValue: unknown
): Result.Result<Runtime, RuntimeError>
	return construct(matchIdValue, enemyEpochValue, difficultyCatalogValue, lifecycleValue, {
		studioCatalogInstallEnabled = RunService:IsStudio(),
	})
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "BaseRuntime" then
		return false
	end
	local productionServerBase = script.Parent
	if
		productionServerBase == nil
		or not productionServerBase:IsA("Folder")
		or productionServerBase.Name ~= "ProductionServerBase"
	then
		return false
	end
	local automatedTests = productionServerBase.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	if automatedTests.Parent ~= ServerStorage then
		return false
	end
	return ServerScriptService:FindFirstChild("Server") == nil
end

function BaseRuntime.newForTests(
	matchIdValue: unknown,
	enemyEpochValue: unknown,
	difficultyCatalogValue: unknown,
	lifecycleValue: unknown,
	options: TestOptions?
): Result.Result<Runtime, RuntimeError>
	if not testModuleIdentityIsExact() then
		error("[ATD_BASE_RUNTIME][code=TEST_CONSTRUCTOR_FORBIDDEN]", 0)
	end
	return construct(matchIdValue, enemyEpochValue, difficultyCatalogValue, lifecycleValue, options or {})
end

return table.freeze(BaseRuntime)
