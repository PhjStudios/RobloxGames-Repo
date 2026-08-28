--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)
local BaseReplicationPublisher = require(script.Parent.BaseReplicationPublisher)
local BaseRuntime = require(script.Parent.BaseRuntime)

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
	"installStudioCatalog"
	| "initializeBase"
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

export type ErrorCode = "UNAVAILABLE" | "REENTRANT" | "INTERNAL_ERROR" | "INVALID_ARGUMENT"
export type ServiceError = {
	code: ErrorCode,
	operation: Operation,
}

export type PreparedDefeatCommitOutcome = {
	committed: true,
	published: boolean,
	snapshot: BaseProtocol.BaseSnapshot,
	resultSeed: BaseRuntime.BaseResultSeed,
}

export type PreparedDefeatFailureOutcome = {
	failed: true,
	published: boolean,
	snapshot: BaseProtocol.BaseSnapshot,
}

export type MatchLifecycleAdapter = {
	getSnapshot: (self: MatchLifecycleAdapter) -> unknown,
	getRuntimeMapSnapshot: (self: MatchLifecycleAdapter) -> unknown,
}

export type RuntimeAdapter = {
	installStudioCatalog: (self: RuntimeAdapter, catalog: unknown) -> unknown,
	initialize: (self: RuntimeAdapter, definition: unknown) -> unknown,
	recordLeak: (self: RuntimeAdapter, outcome: unknown) -> unknown,
	finishEnemyPass: (self: RuntimeAdapter, passOrdinal: unknown) -> unknown,
	commitPreparedDefeat: (self: RuntimeAdapter, token: unknown) -> unknown,
	failPreparedDefeat: (self: RuntimeAdapter, token: unknown) -> unknown,
	fault: (self: RuntimeAdapter) -> unknown,
	getSnapshot: (self: RuntimeAdapter) -> unknown,
	getResultSeed: (self: RuntimeAdapter) -> unknown,
	isTowerInputOpen: (self: RuntimeAdapter) -> boolean,
	query: (self: RuntimeAdapter) -> unknown,
	getDefeatState: (self: RuntimeAdapter) -> unknown,
	getMetrics: (self: RuntimeAdapter) -> unknown,
	cleanup: (self: RuntimeAdapter) -> unknown,
}

export type PublisherAdapter = {
	preflightPublication: (self: PublisherAdapter) -> unknown,
	queueState: (self: PublisherAdapter, snapshot: unknown) -> unknown,
	queueDamage: (
		self: PublisherAdapter,
		snapshot: unknown,
		appliedDamage: unknown,
		leakCount: unknown,
		lowHealthCrossed: unknown
	) -> unknown,
	flush: (self: PublisherAdapter) -> unknown,
	publishState: (self: PublisherAdapter, snapshot: unknown) -> unknown,
	getMetrics: (self: PublisherAdapter) -> unknown,
	cleanup: (self: PublisherAdapter) -> unknown,
}

export type RuntimeFactory = (
	matchId: unknown,
	enemyEpoch: unknown,
	difficultyCatalog: unknown,
	matchLifecycle: unknown
) -> unknown
export type PublisherFactory = (matchId: unknown, enemyEpoch: unknown, dependencies: unknown) -> unknown
export type BaseSender = (recipient: unknown, message: unknown) -> boolean
export type GetRecipients = () -> unknown

export type TestDependencies = {
	matchLifecycle: MatchLifecycleAdapter,
	difficultyCatalog: unknown,
	createRuntime: RuntimeFactory,
	createPublisher: PublisherFactory,
	sender: BaseSender,
	getRecipients: GetRecipients,
}

export type ServiceMetrics = {
	lifecycleState: LifecycleState,
	connectionCount: number,
	callbacksEnabled: boolean,
	operationActive: boolean,
	retainsRuntime: boolean,
	retainsPublisher: boolean,
	retainsConstructionDependencies: boolean,
	retainsCommittedDefeatOutcome: boolean,
	retainsFailedDefeatOutcome: boolean,
	lastFinishedEnemyPassOrdinal: number,
	runtime: unknown?,
	publisher: unknown?,
}

type ServiceData = {
	state: LifecycleState,
	matchLifecycle: MatchLifecycleAdapter?,
	difficultyCatalog: unknown,
	createRuntime: RuntimeFactory?,
	createPublisher: PublisherFactory?,
	sender: BaseSender?,
	getRecipients: GetRecipients?,
	runtime: RuntimeAdapter?,
	publisher: PublisherAdapter?,
	callbacksEnabled: boolean,
	operationActive: boolean,
	shutdownRequested: boolean,
	faultRequested: boolean,
	releasing: boolean,
	lastFinishedEnemyPassOrdinal: number,
	lastBoundaryOutcome: unknown?,
	committedDefeatToken: unknown?,
	committedDefeatOutcome: PreparedDefeatCommitOutcome?,
	failedDefeatToken: unknown?,
	failedDefeatOutcome: PreparedDefeatFailureOutcome?,
	serviceDefinition: ServiceLifecycle.ServiceDefinition?,
}

local SERVICE_NAME = "BaseRuntime"
local STATIC_ERROR_PREFIX = "[ATD_BASE_RUNTIME_SERVICE]"
local FIXED_ENEMY_EPOCH = 1

local RUNTIME_METHODS = table.freeze({
	"installStudioCatalog",
	"initialize",
	"recordLeak",
	"finishEnemyPass",
	"commitPreparedDefeat",
	"failPreparedDefeat",
	"fault",
	"getSnapshot",
	"getResultSeed",
	"isTowerInputOpen",
	"query",
	"getDefeatState",
	"getMetrics",
	"cleanup",
})

local PUBLISHER_METHODS = table.freeze({
	"preflightPublication",
	"queueState",
	"queueDamage",
	"flush",
	"publishState",
	"getMetrics",
	"cleanup",
})

local TEST_DEPENDENCY_FIELDS: { [string]: boolean } = table.freeze({
	matchLifecycle = true,
	difficultyCatalog = true,
	createRuntime = true,
	createPublisher = true,
	sender = true,
	getRecipients = true,
})

local COMPLETED_DEFEAT_FIELDS: { [string]: boolean } = table.freeze({
	committed = true,
	snapshot = true,
	resultSeed = true,
	appliedDamage = true,
	leakCount = true,
	lowHealthCrossed = true,
})

local RESULT_SEED_FIELDS: { [string]: boolean } = table.freeze({
	matchId = true,
	mapId = true,
	difficultyId = true,
	outcome = true,
	reason = true,
	completionServerTime = true,
	currentHealth = true,
	maximumHealth = true,
	baseRevision = true,
})

local ServiceMethods = {}
ServiceMethods.__index = ServiceMethods

export type Service = typeof(setmetatable({} :: {}, ServiceMethods))
export type TestConstructor = (dependencies: TestDependencies) -> Service

local SERVICE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local BaseRuntimeService = {
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

local function hasExactFields(value: { [any]: unknown }, fields: { [string]: boolean }): boolean
	local count = 0
	for fieldName in next, value do
		count += 1
		if type(fieldName) ~= "string" or fields[fieldName] ~= true then
			return false
		end
	end
	local expected = 0
	for _ in fields do
		expected += 1
	end
	return count == expected
end

local function isMatchLifecycleAdapter(value: unknown): boolean
	return type(value) == "table"
		and type((value :: any).getSnapshot) == "function"
		and type((value :: any).getRuntimeMapSnapshot) == "function"
end

local function isRuntimeAdapter(value: unknown): boolean
	return hasMethods(value, RUNTIME_METHODS)
end

local function isPublisherAdapter(value: unknown): boolean
	return hasMethods(value, PUBLISHER_METHODS)
end

local function clearConstructionDependencies(data: ServiceData)
	data.matchLifecycle = nil
	data.difficultyCatalog = nil
	data.createRuntime = nil
	data.createPublisher = nil
	data.sender = nil
	data.getRecipients = nil
end

local function cleanupPublisher(data: ServiceData): boolean
	local publisher = data.publisher
	data.publisher = nil
	if publisher == nil then
		return true
	end
	local called, cleanupResult = callResult(publisher.cleanup, publisher)
	return called and isSuccess(cleanupResult)
end

local function cleanupRuntime(data: ServiceData): boolean
	local runtime = data.runtime
	data.runtime = nil
	if runtime == nil then
		return true
	end
	local called, cleanupResult = callResult(runtime.cleanup, runtime)
	return called and isSuccess(cleanupResult)
end

local function releaseOwnedResources(data: ServiceData): boolean
	if data.releasing then
		return true
	end
	data.releasing = true
	data.callbacksEnabled = false
	data.shutdownRequested = false
	data.faultRequested = false
	data.lastFinishedEnemyPassOrdinal = 0
	data.lastBoundaryOutcome = nil
	data.committedDefeatToken = nil
	data.committedDefeatOutcome = nil
	data.failedDefeatToken = nil
	data.failedDefeatOutcome = nil
	local publisherCleaned = cleanupPublisher(data)
	local runtimeCleaned = cleanupRuntime(data)
	clearConstructionDependencies(data)
	data.releasing = false
	return publisherCleaned and runtimeCleaned
end

local function failInitialize(data: ServiceData, code: string): never
	data.state = "Failed"
	releaseOwnedResources(data)
	staticError(code)
end

local function markDependencyFailure(data: ServiceData)
	data.faultRequested = true
	data.callbacksEnabled = false
end

local function finishOperation(data: ServiceData)
	data.operationActive = false
	if data.shutdownRequested then
		data.shutdownRequested = false
		local cleaned = releaseOwnedResources(data)
		data.state = if cleaned then "Shutdown" else "Failed"
		return
	end
	if data.faultRequested then
		data.faultRequested = false
		data.state = "Failed"
		data.callbacksEnabled = false
	end
end

local function beginOperation(data: ServiceData, operation: Operation, mutation: boolean): ServiceError?
	if data.operationActive then
		return makeServiceError("REENTRANT", operation)
	end
	if mutation then
		if data.state ~= "Started" or not data.callbacksEnabled then
			return makeServiceError("UNAVAILABLE", operation)
		end
	elseif data.state ~= "Started" and data.state ~= "Failed" then
		return makeServiceError("UNAVAILABLE", operation)
	end
	data.operationActive = true
	return nil
end

local function finishAndReturn(data: ServiceData, resultValue: any): any
	finishOperation(data)
	return resultValue
end

local function malformedDependencyResult(data: ServiceData, operation: Operation): Result.Failure<ServiceError>
	markDependencyFailure(data)
	return serviceFailure("INTERNAL_ERROR", operation)
end

local function runtimeState(runtime: RuntimeAdapter): string?
	local called, value = callNonYielding(runtime.getDefeatState, runtime)
	if not called or type(value) ~= "table" or not table.isfrozen(value :: any) then
		return nil
	end
	return if type((value :: any).state) == "string" then (value :: any).state else nil
end

local function publishReadableFault(data: ServiceData)
	local runtime = data.runtime
	local publisher = data.publisher
	if runtime == nil or publisher == nil or runtimeState(runtime) ~= "Faulted" then
		return
	end
	local read, snapshotResult = callResult(runtime.getSnapshot, runtime)
	if not read or not isSuccess(snapshotResult) then
		return
	end
	-- This is the one bounded recovery attempt permitted for a runtime fault.
	-- Any publisher failure is contained; direct snapshot recovery remains.
	callResult(publisher.publishState, publisher, (snapshotResult :: any).value)
end

local function closeForRuntimeFault(data: ServiceData)
	local runtime = data.runtime
	if runtime ~= nil and runtimeState(runtime) == "Faulted" then
		publishReadableFault(data)
		markDependencyFailure(data)
	end
end

local function closeForPublisherFailure(data: ServiceData)
	local runtime = data.runtime
	if runtime ~= nil then
		callResult(runtime.fault, runtime)
	end
	markDependencyFailure(data)
end

local function validateCompletedDefeat(value: unknown): any?
	if
		type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
		or not hasExactFields(value :: { [any]: unknown }, COMPLETED_DEFEAT_FIELDS)
	then
		return nil
	end
	local completed = value :: any
	if
		completed.committed ~= true
		or type(completed.appliedDamage) ~= "number"
		or not Validation.isSafeInteger(completed.appliedDamage)
		or completed.appliedDamage < 1
		or type(completed.leakCount) ~= "number"
		or not Validation.isSafeInteger(completed.leakCount)
		or completed.leakCount < 1
		or completed.leakCount > BaseProtocol.MAX_LEAKS_PER_MESSAGE
		or type(completed.lowHealthCrossed) ~= "boolean"
	then
		return nil
	end
	local snapshotResult = BaseProtocol.validateBaseSnapshot(completed.snapshot)
	if not snapshotResult.ok or snapshotResult.value.status ~= "Defeated" then
		return nil
	end
	local snapshot = snapshotResult.value
	local seed = completed.resultSeed
	if
		type(seed) ~= "table"
		or getmetatable(seed :: any) ~= nil
		or not table.isfrozen(seed :: any)
		or not hasExactFields(seed :: { [any]: unknown }, RESULT_SEED_FIELDS)
		or (seed :: any).matchId ~= snapshot.matchId
		or (seed :: any).mapId ~= snapshot.mapId
		or (seed :: any).difficultyId ~= snapshot.difficultyId
		or (seed :: any).outcome ~= "Defeat"
		or (seed :: any).reason ~= "BaseHealthDepleted"
		or type((seed :: any).completionServerTime) ~= "number"
		or not Validation.isFiniteNumber((seed :: any).completionServerTime)
		or (seed :: any).completionServerTime < snapshot.updatedServerTime
		or (seed :: any).currentHealth ~= 0
		or (seed :: any).maximumHealth ~= snapshot.maximumHealth
		or (seed :: any).baseRevision ~= snapshot.baseRevision
		or completed.appliedDamage > snapshot.maximumHealth
		or completed.leakCount > completed.appliedDamage
		or (completed.lowHealthCrossed and not snapshot.lowHealth)
	then
		return nil
	end
	return table.freeze({
		snapshot = snapshot,
		resultSeed = seed,
		appliedDamage = completed.appliedDamage,
		leakCount = completed.leakCount,
		lowHealthCrossed = completed.lowHealthCrossed,
	})
end

local function canonicalFaultSnapshot(value: unknown): BaseProtocol.BaseSnapshot?
	local result = BaseProtocol.validateBaseSnapshot(value)
	if not result.ok or result.value.status ~= "Faulted" then
		return nil
	end
	return result.value
end

local function logicalPublicationSucceeded(value: unknown, expectedKind: string): boolean
	return type(value) == "table"
		and getmetatable(value :: any) == nil
		and table.isfrozen(value :: any)
		and (value :: any).published == true
		and (value :: any).kind == expectedKind
end

local function initialize(data: ServiceData)
	if data.state ~= "Constructed" then
		staticError("INVALID_STATE")
	end
	data.state = "Initializing"
	local matchLifecycle = data.matchLifecycle
	local createRuntime = data.createRuntime
	local createPublisher = data.createPublisher
	local sender = data.sender
	local getRecipients = data.getRecipients
	if
		matchLifecycle == nil
		or createRuntime == nil
		or createPublisher == nil
		or sender == nil
		or getRecipients == nil
	then
		failInitialize(data, "DEPENDENCY_MISSING")
	end

	local snapshotCalled, snapshotResult =
		callResult((matchLifecycle :: MatchLifecycleAdapter).getSnapshot, matchLifecycle)
	if not snapshotCalled or not isSuccess(snapshotResult) then
		failInitialize(data, "MATCH_SNAPSHOT_UNAVAILABLE")
	end
	local matchSnapshot = (snapshotResult :: any).value
	local matchId = if type(matchSnapshot) == "table" then (matchSnapshot :: any).matchId else nil
	if type(matchId) ~= "string" then
		failInitialize(data, "MATCH_SNAPSHOT_INVALID")
	end

	local runtimeCalled, runtimeResult =
		callResult(createRuntime :: RuntimeFactory, matchId, FIXED_ENEMY_EPOCH, data.difficultyCatalog, matchLifecycle)
	if not runtimeCalled or not isSuccess(runtimeResult) then
		failInitialize(data, "RUNTIME_CREATION_FAILED")
	end
	local runtime = (runtimeResult :: any).value
	if not isRuntimeAdapter(runtime) then
		if type(runtime) == "table" and type((runtime :: any).cleanup) == "function" then
			callNonYielding((runtime :: any).cleanup, runtime)
		end
		failInitialize(data, "RUNTIME_INVALID")
	end
	data.runtime = runtime :: RuntimeAdapter

	local publisherCalled, publisherResult = callResult(
		createPublisher :: PublisherFactory,
		matchId,
		FIXED_ENEMY_EPOCH,
		table.freeze({
			sender = sender,
			getRecipients = getRecipients,
		})
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
	data.callbacksEnabled = false
	if data.operationActive then
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

function ServiceMethods.installStudioCatalog(self: Service, catalog: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "installStudioCatalog"
	local operationError = beginOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime
	if runtime == nil then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end

	local installed, installResult = callResult(runtime.installStudioCatalog, runtime, catalog)
	if not installed then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	if not isSuccess(installResult) then
		closeForRuntimeFault(data)
		return finishAndReturn(data, installResult)
	end
	if (installResult :: any).value ~= true then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	return finishAndReturn(data, installResult)
end

function ServiceMethods.initializeBase(self: Service, definition: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "initializeBase"
	local operationError = beginOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime
	local publisher = data.publisher
	if runtime == nil or publisher == nil then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end

	local preflightCalled, preflightResult = callResult(publisher.preflightPublication, publisher)
	if not preflightCalled or not isSuccess(preflightResult) or (preflightResult :: any).value ~= true then
		closeForPublisherFailure(data)
		return finishAndReturn(data, serviceFailure("INTERNAL_ERROR", operation))
	end
	local initialized, initializeResult = callResult(runtime.initialize, runtime, definition)
	if not initialized then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	if not isSuccess(initializeResult) then
		closeForRuntimeFault(data)
		return finishAndReturn(data, initializeResult)
	end
	local published, publishResult = callResult(publisher.publishState, publisher, (initializeResult :: any).value)
	if not published or not isSuccess(publishResult) then
		closeForPublisherFailure(data)
		return finishAndReturn(data, serviceFailure("INTERNAL_ERROR", operation))
	end
	return finishAndReturn(data, initializeResult)
end

function ServiceMethods.recordLeak(self: Service, outcome: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "recordLeak"
	local operationError = beginOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime
	if runtime == nil then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	local called, resultValue = callResult(runtime.recordLeak, runtime, outcome)
	if not called then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	if not isSuccess(resultValue) then
		closeForRuntimeFault(data)
	end
	return finishAndReturn(data, resultValue)
end

function ServiceMethods.finishEnemyPass(self: Service, passOrdinal: unknown): unknown
	local data = requireData(self)
	local operation: Operation = "finishEnemyPass"
	local operationError = beginOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end

	if
		type(passOrdinal) == "number"
		and Validation.isSafeInteger(passOrdinal :: number)
		and (passOrdinal :: number) == data.lastFinishedEnemyPassOrdinal
		and data.lastBoundaryOutcome ~= nil
	then
		return finishAndReturn(data, Result.ok(data.lastBoundaryOutcome))
	end

	local runtime = data.runtime
	local publisher = data.publisher
	if runtime == nil or publisher == nil then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	local nextPassOrdinal = if data.lastFinishedEnemyPassOrdinal < Validation.MAX_SAFE_INTEGER
		then data.lastFinishedEnemyPassOrdinal + 1
		else nil
	if
		type(passOrdinal) == "number"
		and Validation.isSafeInteger(passOrdinal :: number)
		and nextPassOrdinal ~= nil
		and (passOrdinal :: number) == nextPassOrdinal
	then
		local metricsCalled, metrics = callNonYielding(runtime.getMetrics, runtime)
		if
			not metricsCalled
			or type(metrics) ~= "table"
			or not table.isfrozen(metrics :: any)
			or type((metrics :: any).pendingLeakCount) ~= "number"
		then
			closeForPublisherFailure(data)
			return finishAndReturn(data, serviceFailure("INTERNAL_ERROR", operation))
		end
		if (metrics :: any).pendingLeakCount > 0 then
			local preflightCalled, preflightResult = callResult(publisher.preflightPublication, publisher)
			if not preflightCalled or not isSuccess(preflightResult) or (preflightResult :: any).value ~= true then
				closeForPublisherFailure(data)
				return finishAndReturn(data, serviceFailure("INTERNAL_ERROR", operation))
			end
		end
	end
	local finished, boundaryResult = callResult(runtime.finishEnemyPass, runtime, passOrdinal)
	if not finished then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	if not isSuccess(boundaryResult) then
		closeForRuntimeFault(data)
		return finishAndReturn(data, boundaryResult)
	end

	local boundary = (boundaryResult :: any).value
	if type(boundary) ~= "table" or type((boundary :: any).kind) ~= "string" then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	local kind = (boundary :: any).kind
	if kind == "Damage" then
		local queued, queueResult = callResult(
			publisher.queueDamage,
			publisher,
			(boundary :: any).snapshot,
			(boundary :: any).appliedDamage,
			(boundary :: any).leakCount,
			(boundary :: any).lowHealthCrossed
		)
		if not queued or not isSuccess(queueResult) or (queueResult :: any).value ~= true then
			closeForPublisherFailure(data)
			return finishAndReturn(data, serviceFailure("INTERNAL_ERROR", operation))
		end
		local flushed, flushResult = callResult(publisher.flush, publisher)
		if not flushed or not isSuccess(flushResult) then
			closeForPublisherFailure(data)
			return finishAndReturn(data, serviceFailure("INTERNAL_ERROR", operation))
		end
	elseif kind ~= "Noop" and kind ~= "DefeatPending" then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end

	local ordinal = (boundary :: any).passOrdinal
	if type(ordinal) ~= "number" or not Validation.isSafeInteger(ordinal) or ordinal < 1 then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	data.lastFinishedEnemyPassOrdinal = ordinal
	data.lastBoundaryOutcome = boundary
	return finishAndReturn(data, boundaryResult)
end

function ServiceMethods.commitPreparedDefeat(self: Service, token: unknown): unknown
	local data = requireData(self)
	local cached = data.committedDefeatOutcome
	if cached ~= nil and token == data.committedDefeatToken then
		return Result.ok(cached)
	end

	local operation: Operation = "commitPreparedDefeat"
	local operationError = beginOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime
	local publisher = data.publisher
	if runtime == nil or publisher == nil then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end

	local committedCall, committedResult = callResult(runtime.commitPreparedDefeat, runtime, token)
	if not committedCall then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	if not isSuccess(committedResult) then
		closeForRuntimeFault(data)
		return finishAndReturn(data, committedResult)
	end
	local completed = validateCompletedDefeat((committedResult :: any).value)
	if completed == nil then
		-- The production runtime cannot return this shape. Do not call fault here:
		-- a successful runtime commit may already be irreversible terminal truth.
		markDependencyFailure(data)
		return finishAndReturn(data, serviceFailure("INTERNAL_ERROR", operation))
	end

	local published = false
	local queuedCall, queuedResult = callResult(
		publisher.queueDamage,
		publisher,
		completed.snapshot,
		completed.appliedDamage,
		completed.leakCount,
		completed.lowHealthCrossed
	)
	if queuedCall and isSuccess(queuedResult) and (queuedResult :: any).value == true then
		local flushCall, flushResult = callResult(publisher.flush, publisher)
		published = flushCall
			and isSuccess(flushResult)
			and logicalPublicationSucceeded((flushResult :: any).value, "Damage")
	end

	local outcome: PreparedDefeatCommitOutcome = table.freeze({
		committed = true,
		published = published,
		snapshot = completed.snapshot,
		resultSeed = completed.resultSeed,
	})
	data.committedDefeatToken = token
	data.committedDefeatOutcome = outcome
	if not published then
		-- Results/base terminal truth is already committed and must never be
		-- downgraded to Faulted because its reliable event publication failed.
		markDependencyFailure(data)
	end
	return finishAndReturn(data, Result.ok(outcome))
end

function ServiceMethods.failPreparedDefeat(self: Service, token: unknown): unknown
	local data = requireData(self)
	local cached = data.failedDefeatOutcome
	if cached ~= nil and token == data.failedDefeatToken then
		return Result.ok(cached)
	end

	local operation: Operation = "failPreparedDefeat"
	local operationError = beginOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime
	local publisher = data.publisher
	if runtime == nil or publisher == nil then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end

	local failedCall, failedResult = callResult(runtime.failPreparedDefeat, runtime, token)
	if not failedCall then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	if not isSuccess(failedResult) then
		closeForRuntimeFault(data)
		return finishAndReturn(data, failedResult)
	end
	local snapshot = canonicalFaultSnapshot((failedResult :: any).value)
	if snapshot == nil then
		markDependencyFailure(data)
		return finishAndReturn(data, serviceFailure("INTERNAL_ERROR", operation))
	end

	local publicationCall, publicationResult = callResult(publisher.publishState, publisher, snapshot)
	local published = publicationCall
		and isSuccess(publicationResult)
		and logicalPublicationSucceeded((publicationResult :: any).value, "State")
	local outcome: PreparedDefeatFailureOutcome = table.freeze({
		failed = true,
		published = published,
		snapshot = snapshot,
	})
	data.failedDefeatToken = token
	data.failedDefeatOutcome = outcome
	-- A failed prepared defeat always closes mutation admission. Publication is
	-- a single best-effort full-state recovery attempt and is never retried.
	markDependencyFailure(data)
	return finishAndReturn(data, Result.ok(outcome))
end

function ServiceMethods.fault(self: Service): unknown
	local data = requireData(self)
	local operation: Operation = "fault"
	local operationError = beginOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime
	local publisher = data.publisher
	if runtime == nil or publisher == nil then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end

	local faultCall, faultResult = callResult(runtime.fault, runtime)
	if not faultCall then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	if not isSuccess(faultResult) then
		closeForRuntimeFault(data)
		return finishAndReturn(data, faultResult)
	end
	local snapshotResult = BaseProtocol.validateBaseSnapshot((faultResult :: any).value)
	if not snapshotResult.ok then
		markDependencyFailure(data)
		return finishAndReturn(data, serviceFailure("INTERNAL_ERROR", operation))
	end
	local snapshot = snapshotResult.value
	if snapshot.status == "Faulted" then
		-- One bounded full-state attempt; a failed publisher cannot reopen the
		-- now-faulted server runtime.
		callResult(publisher.publishState, publisher, snapshot)
	elseif snapshot.status ~= "Defeated" then
		markDependencyFailure(data)
		return finishAndReturn(data, serviceFailure("INTERNAL_ERROR", operation))
	end
	markDependencyFailure(data)
	return finishAndReturn(data, Result.ok(snapshot))
end

local function readRuntimeResult(self: Service, operation: Operation, methodName: string): unknown
	local data = requireData(self)
	local operationError = beginOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime
	if runtime == nil then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	local called, resultValue = callResult((runtime :: any)[methodName], runtime)
	if not called then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	return finishAndReturn(data, resultValue)
end

function ServiceMethods.getSnapshot(self: Service): unknown
	return readRuntimeResult(self, "getSnapshot", "getSnapshot")
end

function ServiceMethods.getResultSeed(self: Service): unknown
	return readRuntimeResult(self, "getResultSeed", "getResultSeed")
end

function ServiceMethods.isTowerInputOpen(self: Service): boolean
	local data = requireData(self)
	local operation: Operation = "isTowerInputOpen"
	local operationError = beginOperation(data, operation, false)
	if operationError ~= nil then
		return false
	end
	local runtime = data.runtime
	if runtime == nil then
		markDependencyFailure(data)
		finishOperation(data)
		return false
	end
	local called, value = callNonYielding(runtime.isTowerInputOpen, runtime)
	if not called or type(value) ~= "boolean" then
		markDependencyFailure(data)
		finishOperation(data)
		return false
	end
	finishOperation(data)
	return value
end

local function readRuntimeValue(self: Service, operation: Operation, methodName: string): unknown
	local data = requireData(self)
	local operationError = beginOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local runtime = data.runtime
	if runtime == nil then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	local called, value = callNonYielding((runtime :: any)[methodName], runtime)
	if not called or type(value) ~= "table" or not table.isfrozen(value :: any) then
		return finishAndReturn(data, malformedDependencyResult(data, operation))
	end
	return finishAndReturn(data, value)
end

function ServiceMethods.query(self: Service): unknown
	return readRuntimeValue(self, "query", "query")
end

function ServiceMethods.getDefeatState(self: Service): unknown
	return readRuntimeValue(self, "getDefeatState", "getDefeatState")
end

function ServiceMethods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	return requireData(self).serviceDefinition :: ServiceLifecycle.ServiceDefinition
end

function ServiceMethods.getLifecycleState(self: Service): LifecycleState
	return requireData(self).state
end

local function readMetrics(adapter: unknown, methodName: string): unknown?
	if type(adapter) ~= "table" or type((adapter :: any)[methodName]) ~= "function" then
		return nil
	end
	local called, value = callNonYielding((adapter :: any)[methodName], adapter)
	if not called or type(value) ~= "table" or not table.isfrozen(value :: any) then
		return nil
	end
	return value
end

function ServiceMethods.getMetrics(self: Service): ServiceMetrics
	local data = requireData(self)
	return table.freeze({
		lifecycleState = data.state,
		connectionCount = 0,
		callbacksEnabled = data.callbacksEnabled,
		operationActive = data.operationActive,
		retainsRuntime = data.runtime ~= nil,
		retainsPublisher = data.publisher ~= nil,
		retainsConstructionDependencies = data.matchLifecycle ~= nil
			or data.difficultyCatalog ~= nil
			or data.createRuntime ~= nil
			or data.createPublisher ~= nil
			or data.sender ~= nil
			or data.getRecipients ~= nil,
		retainsCommittedDefeatOutcome = data.committedDefeatOutcome ~= nil or data.committedDefeatToken ~= nil,
		retainsFailedDefeatOutcome = data.failedDefeatOutcome ~= nil or data.failedDefeatToken ~= nil,
		lastFinishedEnemyPassOrdinal = data.lastFinishedEnemyPassOrdinal,
		runtime = readMetrics(data.runtime, "getMetrics"),
		publisher = readMetrics(data.publisher, "getMetrics"),
	})
end

local function construct(
	matchLifecycleValue: unknown,
	difficultyCatalog: unknown,
	createRuntimeValue: unknown,
	createPublisherValue: unknown,
	senderValue: unknown,
	getRecipientsValue: unknown
): Service
	if
		not isMatchLifecycleAdapter(matchLifecycleValue)
		or type(difficultyCatalog) ~= "table"
		or type(createRuntimeValue) ~= "function"
		or type(createPublisherValue) ~= "function"
		or type(senderValue) ~= "function"
		or type(getRecipientsValue) ~= "function"
	then
		staticError("INVALID_DEPENDENCIES")
	end

	local data: ServiceData = {
		state = "Constructed",
		matchLifecycle = matchLifecycleValue :: MatchLifecycleAdapter,
		difficultyCatalog = difficultyCatalog,
		createRuntime = createRuntimeValue :: RuntimeFactory,
		createPublisher = createPublisherValue :: PublisherFactory,
		sender = senderValue :: BaseSender,
		getRecipients = getRecipientsValue :: GetRecipients,
		runtime = nil,
		publisher = nil,
		callbacksEnabled = false,
		operationActive = false,
		shutdownRequested = false,
		faultRequested = false,
		releasing = false,
		lastFinishedEnemyPassOrdinal = 0,
		lastBoundaryOutcome = nil,
		committedDefeatToken = nil,
		committedDefeatOutcome = nil,
		failedDefeatToken = nil,
		failedDefeatOutcome = nil,
		serviceDefinition = nil,
	}
	local service = setmetatable({}, ServiceMethods) :: Service
	table.freeze(service)
	data.serviceDefinition = table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({ "NetworkRegistry", "MatchLifecycle" }),
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

local function productionCreateRuntime(
	matchId: unknown,
	enemyEpoch: unknown,
	difficultyCatalog: unknown,
	matchLifecycle: unknown
): unknown
	return BaseRuntime.new(matchId, enemyEpoch, difficultyCatalog, matchLifecycle)
end

local function productionCreatePublisher(matchId: unknown, enemyEpoch: unknown, dependencies: unknown): unknown
	return BaseReplicationPublisher.new(matchId, enemyEpoch, dependencies)
end

local function productionGetRecipients(): unknown
	local records = {}
	for _, player in Players:GetPlayers() do
		table.insert(
			records,
			table.freeze({
				recipient = player,
				userId = player.UserId,
			})
		)
	end
	table.sort(records, function(left, right)
		return left.userId < right.userId
	end)
	return records
end

function BaseRuntimeService.new(
	matchLifecycle: MatchLifecycleAdapter,
	difficultyCatalog: ConfigTypes.DifficultyCatalog,
	baseSender: BaseSender
): Service
	return construct(
		matchLifecycle,
		difficultyCatalog,
		productionCreateRuntime,
		productionCreatePublisher,
		baseSender,
		productionGetRecipients
	)
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "BaseRuntimeService" then
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

function BaseRuntimeService.newForTests(dependencies: TestDependencies): Service
	if not testModuleIdentityIsExact() then
		error("[ATD_BASE_RUNTIME_SERVICE][code=TEST_CONSTRUCTOR_FORBIDDEN]", 0)
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
		values.difficultyCatalog,
		values.createRuntime,
		values.createPublisher,
		values.sender,
		values.getRecipients
	)
end

return table.freeze(BaseRuntimeService)
