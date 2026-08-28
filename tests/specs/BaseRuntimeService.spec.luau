--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local BaseRuntimeService = require(script.Parent.Parent.ProductionServerBase.BaseRuntimeService)

local Shared = game:GetService("ReplicatedStorage").Shared
local Result = require(Shared.util.Result)
local Validation = require(Shared.util.Validation)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase10-base-service"
local DEFINITION = table.freeze({ marker = "canonical-difficulty" })
local CATALOG = table.freeze({ marker = "authenticated-catalog" })
local STUDIO_CATALOG = table.freeze({ marker = "authenticated-studio-catalog" })
local SNAPSHOT = table.freeze({
	matchId = MATCH_ID,
	enemyEpoch = 1,
	mapId = "map:phase07-graybox",
	difficultyId = "difficulty:phase10-test",
	basePosition = Vector3.new(0, 4, 0),
	baseRevision = 1,
	status = "Active",
	currentHealth = 100,
	maximumHealth = 100,
	lowHealth = false,
	initializedServerTime = 10,
	updatedServerTime = 10,
})
local PREPARED_DEFEAT = table.freeze({})
local DEFEATED_SNAPSHOT = table.freeze({
	matchId = MATCH_ID,
	enemyEpoch = 1,
	mapId = "map:phase07-graybox",
	difficultyId = "difficulty:phase10-test",
	basePosition = Vector3.new(0, 4, 0),
	baseRevision = 3,
	status = "Defeated",
	currentHealth = 0,
	maximumHealth = 100,
	lowHealth = true,
	initializedServerTime = 10,
	updatedServerTime = 12,
})
local FAULTED_SNAPSHOT = table.freeze({
	matchId = MATCH_ID,
	enemyEpoch = 1,
	mapId = "map:phase07-graybox",
	difficultyId = "difficulty:phase10-test",
	basePosition = Vector3.new(0, 4, 0),
	baseRevision = 3,
	status = "Faulted",
	currentHealth = 0,
	maximumHealth = 100,
	lowHealth = true,
	initializedServerTime = 10,
	updatedServerTime = 12,
})
local RESULT_SEED = table.freeze({
	matchId = MATCH_ID,
	mapId = "map:phase07-graybox",
	difficultyId = "difficulty:phase10-test",
	outcome = "Defeat",
	reason = "BaseHealthDepleted",
	completionServerTime = 12,
	currentHealth = 0,
	maximumHealth = 100,
	baseRevision = 3,
})

local function preparedBoundary(passOrdinal: number): any
	return table.freeze({
		kind = "DefeatPending",
		passOrdinal = passOrdinal,
		baseRevision = 2,
		appliedDamage = 100,
		leakCount = 2,
		lowHealthCrossed = true,
		preparedDefeat = PREPARED_DEFEAT,
	})
end

local newForTests = BaseRuntimeService.newForTests
if newForTests == nil then
	error("BaseRuntimeService test constructor unavailable at exact Test location", 0)
end

local function invoke(callback: (() -> ())?)
	if callback == nil then
		error("expected lifecycle callback", 0)
	end
	(callback :: () -> ())()
end

local function expectStaticFailure(assertions: Assertions, callback: () -> (), code: string)
	local succeeded, failure = pcall(callback)
	assertions.isFalse(succeeded)
	assertions.contains(failure, `[ATD_BASE_RUNTIME_SERVICE][code={code}]`)
end

local function indexOf(values: { string }, expected: string): number
	for index, value in values do
		if value == expected then
			return index
		end
	end
	return 0
end

local function damageBoundary(passOrdinal: number): any
	return table.freeze({
		kind = "Damage",
		passOrdinal = passOrdinal,
		snapshot = table.freeze({
			matchId = MATCH_ID,
			enemyEpoch = 1,
			mapId = "map:phase07-graybox",
			difficultyId = "difficulty:phase10-test",
			basePosition = Vector3.new(0, 4, 0),
			baseRevision = passOrdinal + 1,
			status = "Active",
			currentHealth = 90,
			maximumHealth = 100,
			lowHealth = false,
			initializedServerTime = 10,
			updatedServerTime = 11,
		}),
		appliedDamage = 10,
		leakCount = 2,
		lowHealthCrossed = false,
	})
end

local function makeEnvironment(): any
	local environment: any = {
		trace = {},
		installStudioCatalogCalls = 0,
		initializeCalls = 0,
		recordLeakCalls = 0,
		finishCalls = 0,
		getSnapshotCalls = 0,
		runtimeCleanupCalls = 0,
		runtimeFaultCalls = 0,
		runtimeState = "Active",
		currentSnapshot = SNAPSHOT,
		commitPreparedCalls = 0,
		failPreparedCalls = 0,
		pendingLeakCount = 0,
		publisherCleanupCalls = 0,
		preflightCalls = 0,
		publishStateCalls = 0,
		queueDamageCalls = 0,
		flushCalls = 0,
		finishResults = {},
	}

	environment.matchLifecycle = {
		getSnapshot = function(_self: unknown): unknown
			table.insert(environment.trace, "lifecycle:snapshot")
			if environment.matchSnapshotMode == "yield" then
				coroutine.yield()
			elseif environment.matchSnapshotMode == "failure" then
				return Result.err(table.freeze({ code = "UNAVAILABLE" }))
			elseif environment.matchSnapshotMode == "invalid" then
				return Result.ok(table.freeze({}))
			end
			return Result.ok(table.freeze({ matchId = MATCH_ID }))
		end,
		getRuntimeMapSnapshot = function(_self: unknown): unknown
			return Result.ok(table.freeze({ marker = "runtime-map" }))
		end,
	}

	environment.runtime = {
		installStudioCatalog = function(_self: unknown, catalog: unknown): unknown
			environment.installStudioCatalogCalls += 1
			environment.installedStudioCatalog = catalog
			table.insert(environment.trace, "runtime:install-studio-catalog")
			if environment.installStudioCatalogMode == "yield" then
				coroutine.yield()
			elseif environment.installStudioCatalogMode == "failure" then
				return Result.err(
					table.freeze({ code = "UNAUTHENTICATED_CATALOG", operation = "installStudioCatalog" })
				)
			elseif environment.installStudioCatalogMode == "malformed" then
				return Result.ok(false)
			end
			return Result.ok(true)
		end,
		initialize = function(_self: unknown, definition: unknown): unknown
			environment.initializeCalls += 1
			environment.initializedDefinition = definition
			table.insert(environment.trace, "runtime:initialize")
			if environment.runtimeInitializeMode == "failure" then
				return Result.err(table.freeze({ code = "INVALID_DEFINITION", operation = "initialize" }))
			end
			return Result.ok(SNAPSHOT)
		end,
		recordLeak = function(_self: unknown, outcome: unknown): unknown
			environment.recordLeakCalls += 1
			environment.recordedOutcome = outcome
			if environment.recordLeakMode == "yield" then
				coroutine.yield()
			elseif environment.recordLeakMode == "fault" then
				environment.runtimeState = "Faulted"
				environment.currentSnapshot = FAULTED_SNAPSHOT
				return Result.err(table.freeze({ code = "DEPENDENCY_FAILED", operation = "recordLeak" }))
			elseif environment.recordLeakMode == "failure" then
				return Result.err(table.freeze({ code = "WRONG_MATCH", operation = "recordLeak" }))
			end
			return Result.ok(table.freeze({ kind = "Applied", baseRevision = 2 }))
		end,
		finishEnemyPass = function(_self: unknown, passOrdinal: unknown): unknown
			environment.finishCalls += 1
			environment.finishedPassOrdinal = passOrdinal
			local configured = environment.finishResults[passOrdinal]
			environment.pendingLeakCount = 0
			if configured ~= nil then
				if configured.ok and configured.value.kind == "DefeatPending" then
					environment.runtimeState = "DefeatPending"
				end
				return configured
			end
			return Result.ok(table.freeze({ kind = "Noop", passOrdinal = passOrdinal }))
		end,
		commitPreparedDefeat = function(_self: unknown, token: unknown): unknown
			environment.commitPreparedCalls += 1
			environment.committedToken = token
			table.insert(environment.trace, "runtime:commit-defeat")
			if environment.commitPreparedMode == "yield" then
				coroutine.yield()
			elseif environment.commitPreparedMode == "failure" or token ~= PREPARED_DEFEAT then
				return Result.err(table.freeze({ code = "INVALID_TOKEN", operation = "commitPreparedDefeat" }))
			elseif environment.commitPreparedMode == "malformed" then
				environment.runtimeState = "Defeated"
				environment.currentSnapshot = DEFEATED_SNAPSHOT
				return Result.ok(table.freeze({ committed = true }))
			end
			environment.runtimeState = "Defeated"
			environment.currentSnapshot = DEFEATED_SNAPSHOT
			return Result.ok(table.freeze({
				committed = true,
				snapshot = DEFEATED_SNAPSHOT,
				resultSeed = RESULT_SEED,
				appliedDamage = 100,
				leakCount = 2,
				lowHealthCrossed = true,
			}))
		end,
		failPreparedDefeat = function(_self: unknown, token: unknown): unknown
			environment.failPreparedCalls += 1
			environment.failedToken = token
			table.insert(environment.trace, "runtime:fail-defeat")
			if environment.failPreparedMode == "yield" then
				coroutine.yield()
			elseif environment.failPreparedMode == "failure" or token ~= PREPARED_DEFEAT then
				return Result.err(table.freeze({ code = "INVALID_TOKEN", operation = "failPreparedDefeat" }))
			end
			environment.runtimeState = "Faulted"
			environment.currentSnapshot = FAULTED_SNAPSHOT
			return Result.ok(FAULTED_SNAPSHOT)
		end,
		fault = function(_self: unknown): unknown
			environment.runtimeFaultCalls += 1
			if environment.runtimeState == "Defeated" then
				return Result.ok(DEFEATED_SNAPSHOT)
			end
			environment.runtimeState = "Faulted"
			environment.currentSnapshot = FAULTED_SNAPSHOT
			return Result.ok(FAULTED_SNAPSHOT)
		end,
		getSnapshot = function(_self: unknown): unknown
			environment.getSnapshotCalls += 1
			return Result.ok(environment.currentSnapshot)
		end,
		getResultSeed = function(_self: unknown): unknown
			if environment.runtimeState == "Defeated" then
				return Result.ok(RESULT_SEED)
			end
			return Result.err(table.freeze({ code = "UNAVAILABLE", operation = "getResultSeed" }))
		end,
		isTowerInputOpen = function(_self: unknown): boolean
			return environment.runtimeState == "Active"
		end,
		query = function(_self: unknown): unknown
			return table.freeze({
				state = environment.runtimeState,
				currentHealth = environment.currentSnapshot.currentHealth,
			})
		end,
		getDefeatState = function(_self: unknown): unknown
			return table.freeze({ state = environment.runtimeState, defeatPending = false })
		end,
		getMetrics = function(_self: unknown): unknown
			return table.freeze({
				cleaned = false,
				processedOutcomeCount = environment.recordLeakCalls,
				pendingLeakCount = environment.pendingLeakCount,
			})
		end,
		cleanup = function(_self: unknown): unknown
			environment.runtimeCleanupCalls += 1
			table.insert(environment.trace, "cleanup:runtime")
			if environment.runtimeCleanupMode == "failure" then
				return Result.err(table.freeze({ code = "CLEANUP_FAILED" }))
			end
			return Result.ok(environment.runtimeCleanupCalls == 1)
		end,
	}

	environment.publisher = {
		preflightPublication = function(_self: unknown): unknown
			environment.preflightCalls += 1
			table.insert(environment.trace, "publisher:preflight")
			if environment.preflightMode == "failure" then
				return Result.err(table.freeze({ code = "CAPACITY_EXCEEDED" }))
			end
			return Result.ok(true)
		end,
		queueState = function(_self: unknown, _snapshot: unknown): unknown
			return Result.ok(true)
		end,
		queueDamage = function(
			_self: unknown,
			snapshot: unknown,
			appliedDamage: unknown,
			leakCount: unknown,
			lowHealthCrossed: unknown
		): unknown
			environment.queueDamageCalls += 1
			environment.queuedDamage = table.freeze({
				snapshot = snapshot,
				appliedDamage = appliedDamage,
				leakCount = leakCount,
				lowHealthCrossed = lowHealthCrossed,
			})
			table.insert(environment.trace, "publisher:queue-damage")
			if environment.queueMode == "failure" then
				return Result.err(table.freeze({ code = "INVALID_MESSAGE" }))
			end
			return Result.ok(true)
		end,
		flush = function(_self: unknown): unknown
			environment.flushCalls += 1
			table.insert(environment.trace, "publisher:flush")
			if environment.flushHook ~= nil then
				environment.flushHook()
			end
			if environment.flushMode == "failure" then
				return Result.err(table.freeze({ code = "SEND_FAILED" }))
			end
			return Result.ok(table.freeze({
				published = true,
				kind = "Damage",
				recipientCount = 2,
				senderFailureCount = 0,
			}))
		end,
		publishState = function(_self: unknown, snapshot: unknown): unknown
			environment.publishStateCalls += 1
			environment.publishedState = snapshot
			table.insert(environment.trace, "publisher:publish-state")
			if environment.publishStateHook ~= nil then
				environment.publishStateHook()
			end
			if environment.publishStateMode == "failure" then
				return Result.err(table.freeze({ code = "CAPACITY_EXCEEDED" }))
			end
			return Result.ok(table.freeze({
				published = true,
				kind = "State",
				recipientCount = 2,
				senderFailureCount = 0,
			}))
		end,
		getMetrics = function(_self: unknown): unknown
			return table.freeze({
				cleaned = false,
				publicationCount = environment.publishStateCalls + environment.flushCalls,
			})
		end,
		cleanup = function(_self: unknown): unknown
			environment.publisherCleanupCalls += 1
			table.insert(environment.trace, "cleanup:publisher")
			if environment.publisherCleanupMode == "failure" then
				return Result.err(table.freeze({ code = "CLEANUP_FAILED" }))
			end
			return Result.ok(environment.publisherCleanupCalls == 1)
		end,
	}

	environment.createRuntime = function(
		matchId: unknown,
		enemyEpoch: unknown,
		difficultyCatalog: unknown,
		matchLifecycle: unknown
	): unknown
		table.insert(environment.trace, "create:runtime")
		environment.runtimeMatchId = matchId
		environment.runtimeEnemyEpoch = enemyEpoch
		environment.runtimeCatalog = difficultyCatalog
		environment.runtimeLifecycle = matchLifecycle
		if environment.runtimeFactoryMode == "failure" then
			return Result.err(table.freeze({ code = "RUNTIME_FAILED" }))
		elseif environment.runtimeFactoryMode == "invalid" then
			return Result.ok(table.freeze({}))
		end
		return Result.ok(environment.runtime)
	end

	environment.createPublisher = function(matchId: unknown, enemyEpoch: unknown, dependencies: unknown): unknown
		table.insert(environment.trace, "create:publisher")
		environment.publisherMatchId = matchId
		environment.publisherEnemyEpoch = enemyEpoch
		environment.publisherDependencies = dependencies
		if environment.publisherFactoryMode == "failure" then
			return Result.err(table.freeze({ code = "PUBLISHER_FAILED" }))
		elseif environment.publisherFactoryMode == "invalid" then
			return Result.ok(table.freeze({ cleanup = environment.publisher.cleanup }))
		end
		return Result.ok(environment.publisher)
	end

	environment.sender = function(_recipient: unknown, _message: unknown): boolean
		return true
	end
	environment.getRecipients = function(): unknown
		return {}
	end
	environment.dependencies = {
		matchLifecycle = environment.matchLifecycle,
		difficultyCatalog = CATALOG,
		createRuntime = environment.createRuntime,
		createPublisher = environment.createPublisher,
		sender = environment.sender,
		getRecipients = environment.getRecipients,
	}
	return environment
end

local function createService(environment: any): BaseRuntimeService.Service
	return (newForTests :: BaseRuntimeService.TestConstructor)(environment.dependencies)
end

local function startService(environment: any): (BaseRuntimeService.Service, any)
	local service = createService(environment)
	local definition = service:getServiceDefinition()
	invoke(definition.initialize)
	invoke(definition.start)
	return service, definition
end

local function prepareDefeat(environment: any): (BaseRuntimeService.Service, any, any)
	environment.pendingLeakCount = 2
	environment.finishResults[1] = Result.ok(preparedBoundary(1))
	local service, definition = startService(environment)
	local boundaryResult = service:finishEnemyPass(1)
	if not boundaryResult.ok or boundaryResult.value.kind ~= "DefeatPending" then
		error("failed to prepare service defeat fixture", 0)
	end
	return service, definition, boundaryResult.value
end

return TestHarness.suite("server base runtime service", {
	TestHarness.case("constructs dormant runtime and publisher with no loop or connection", function(assertions)
		local environment = makeEnvironment()
		local service = createService(environment)
		local definition = service:getServiceDefinition()
		assertions.isTrue(table.isfrozen(service))
		assertions.isTrue(table.isfrozen(definition))
		assertions.equal(definition.name, "BaseRuntime")
		assertions.equal(#definition.dependencies, 2)
		assertions.equal(definition.dependencies[1], "NetworkRegistry")
		assertions.equal(definition.dependencies[2], "MatchLifecycle")

		invoke(definition.initialize)
		assertions.equal(service:getLifecycleState(), "Initialized")
		assertions.equal(environment.runtimeMatchId, MATCH_ID)
		assertions.equal(environment.runtimeEnemyEpoch, 1)
		assertions.equal(environment.runtimeCatalog, CATALOG)
		assertions.equal(environment.runtimeLifecycle, environment.matchLifecycle)
		assertions.equal(environment.publisherMatchId, MATCH_ID)
		assertions.equal(environment.publisherEnemyEpoch, 1)
		assertions.isTrue(table.isfrozen(environment.publisherDependencies))
		assertions.equal(environment.publishStateCalls, 0)

		invoke(definition.start)
		local metrics = service:getMetrics()
		assertions.equal(metrics.lifecycleState, "Started")
		assertions.equal(metrics.connectionCount, 0)
		assertions.isTrue(metrics.callbacksEnabled)
		assertions.isTrue(metrics.retainsRuntime)
		assertions.isTrue(metrics.retainsPublisher)
		assertions.isFalse(metrics.retainsConstructionDependencies)

		invoke(definition.shutdown)
		assertions.equal(service:getLifecycleState(), "Shutdown")
		assertions.equal(environment.publisherCleanupCalls, 1)
		assertions.equal(environment.runtimeCleanupCalls, 1)
		assertions.isTrue(
			indexOf(environment.trace, "cleanup:publisher") < indexOf(environment.trace, "cleanup:runtime")
		)
		local cleanedMetrics = service:getMetrics()
		assertions.isFalse(cleanedMetrics.retainsRuntime)
		assertions.isFalse(cleanedMetrics.retainsPublisher)
		assertions.isFalse(cleanedMetrics.callbacksEnabled)
		assertions.equal(cleanedMetrics.lastFinishedEnemyPassOrdinal, 0)
		invoke(definition.shutdown)
		assertions.equal(environment.publisherCleanupCalls, 1)
		assertions.equal(environment.runtimeCleanupCalls, 1)
	end),

	TestHarness.case("initializes once from the server definition and publishes one full state", function(assertions)
		local environment = makeEnvironment()
		local service = startService(environment)
		local initialized = service:initializeBase(DEFINITION)
		assertions.isTrue(initialized.ok)
		assertions.equal(initialized.value, SNAPSHOT)
		assertions.equal(environment.initializedDefinition, DEFINITION)
		assertions.equal(environment.preflightCalls, 1)
		assertions.equal(environment.publishStateCalls, 1)
		assertions.equal(environment.publishedState, SNAPSHOT)
		assertions.isTrue(
			indexOf(environment.trace, "publisher:preflight") < indexOf(environment.trace, "runtime:initialize")
		)
		assertions.isTrue(
			indexOf(environment.trace, "runtime:initialize") < indexOf(environment.trace, "publisher:publish-state")
		)

		environment.runtimeInitializeMode = "failure"
		local duplicate = service:initializeBase(DEFINITION)
		assertions.isFalse(duplicate.ok)
		assertions.equal(duplicate.error.code, "INVALID_DEFINITION")
		assertions.equal(environment.publishStateCalls, 1)
	end),

	TestHarness.case("exposes only the started server Studio catalog facade", function(assertions)
		local environment = makeEnvironment()
		local service = createService(environment)
		local definition = service:getServiceDefinition()
		local beforeInitialize = service:installStudioCatalog(STUDIO_CATALOG)
		assertions.isFalse(beforeInitialize.ok)
		assertions.equal(beforeInitialize.error.code, "UNAVAILABLE")
		assertions.equal(environment.installStudioCatalogCalls, 0)

		invoke(definition.initialize)
		local beforeStart = service:installStudioCatalog(STUDIO_CATALOG)
		assertions.isFalse(beforeStart.ok)
		assertions.equal(beforeStart.error.code, "UNAVAILABLE")
		assertions.equal(environment.installStudioCatalogCalls, 0)
		invoke(definition.start)

		local installed = service:installStudioCatalog(STUDIO_CATALOG)
		assertions.isTrue(installed.ok)
		assertions.isTrue(installed.value)
		assertions.equal(environment.installedStudioCatalog, STUDIO_CATALOG)
		assertions.equal(environment.installStudioCatalogCalls, 1)
		assertions.equal(environment.preflightCalls, 0)
		assertions.equal(environment.publishStateCalls, 0)
		assertions.equal(environment.queueDamageCalls, 0)
		assertions.equal(environment.flushCalls, 0)

		environment.installStudioCatalogMode = "failure"
		local rejected = service:installStudioCatalog(table.freeze({ marker = "raw" }))
		assertions.isFalse(rejected.ok)
		assertions.equal(rejected.error.code, "UNAUTHENTICATED_CATALOG")
		assertions.equal(service:getLifecycleState(), "Started")
		assertions.equal(environment.installStudioCatalogCalls, 2)

		invoke(definition.shutdown)
		local afterCleanup = service:installStudioCatalog(STUDIO_CATALOG)
		assertions.isFalse(afterCleanup.ok)
		assertions.equal(afterCleanup.error.code, "UNAVAILABLE")
		assertions.equal(environment.installStudioCatalogCalls, 2)
		assertions.isFalse(service:getMetrics().retainsRuntime)
	end),

	TestHarness.case("delegates authenticated leak recording synchronously without publication", function(assertions)
		local environment = makeEnvironment()
		local service = startService(environment)
		local outcome = table.freeze({ marker = "authenticated-outcome" })
		local recorded = service:recordLeak(outcome)
		assertions.isTrue(recorded.ok)
		assertions.equal(environment.recordedOutcome, outcome)
		assertions.equal(environment.recordLeakCalls, 1)
		assertions.equal(environment.publishStateCalls, 0)
		assertions.equal(environment.queueDamageCalls, 0)
		assertions.equal(environment.flushCalls, 0)

		environment.recordLeakMode = "failure"
		local rejected = service:recordLeak(outcome)
		assertions.isFalse(rejected.ok)
		assertions.equal(rejected.error.code, "WRONG_MATCH")
		assertions.equal(service:getLifecycleState(), "Started")
	end),

	TestHarness.case("publishes one readable runtime fault and closes admission", function(assertions)
		local environment = makeEnvironment()
		environment.recordLeakMode = "fault"
		local service = startService(environment)
		local failed = service:recordLeak(table.freeze({ marker = "authenticated-outcome" }))
		assertions.isFalse(failed.ok)
		assertions.equal(failed.error.code, "DEPENDENCY_FAILED")
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.equal(environment.publishStateCalls, 1)
		assertions.equal(environment.publishedState.status, "Faulted")
		assertions.equal(service:getSnapshot().value.status, "Faulted")
		assertions.isFalse(service:isTowerInputOpen())
	end),

	TestHarness.case("preflights damage capacity before finalizing the pass", function(assertions)
		local environment = makeEnvironment()
		environment.pendingLeakCount = 2
		environment.finishResults[1] = Result.ok(damageBoundary(1))
		environment.preflightMode = "failure"
		local service = startService(environment)
		local failed = service:finishEnemyPass(1)
		assertions.isFalse(failed.ok)
		assertions.equal(failed.error.code, "INTERNAL_ERROR")
		assertions.equal(environment.preflightCalls, 1)
		assertions.equal(environment.finishCalls, 0)
		assertions.equal(environment.queueDamageCalls, 0)
		assertions.equal(environment.flushCalls, 0)
		assertions.equal(environment.runtimeFaultCalls, 1)
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.equal(service:getSnapshot().value.status, "Faulted")
	end),

	TestHarness.case("exposes one fail closed server fault seam", function(assertions)
		local environment = makeEnvironment()
		local service = startService(environment)
		local faulted = service:fault()
		assertions.isTrue(faulted.ok)
		assertions.equal(faulted.value.status, "Faulted")
		assertions.equal(environment.runtimeFaultCalls, 1)
		assertions.equal(environment.publishStateCalls, 1)
		assertions.equal(environment.publishedState.status, "Faulted")
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.isFalse(service:isTowerInputOpen())
		local duplicate = service:fault()
		assertions.isFalse(duplicate.ok)
		assertions.equal(duplicate.error.code, "UNAVAILABLE")
		assertions.equal(environment.runtimeFaultCalls, 1)
		assertions.equal(environment.publishStateCalls, 1)
	end),

	TestHarness.case(
		"coalesces one normal pass Damage publication and never replays a cached boundary",
		function(assertions)
			local environment = makeEnvironment()
			environment.finishResults[1] = Result.ok(damageBoundary(1))
			environment.pendingLeakCount = 2
			environment.finishResults[2] = Result.ok(table.freeze({ kind = "Noop", passOrdinal = 2 }))
			environment.finishResults[3] = Result.ok(preparedBoundary(3))
			local service = startService(environment)

			local first = service:finishEnemyPass(1)
			assertions.isTrue(first.ok)
			assertions.equal(first.value.kind, "Damage")
			assertions.equal(environment.queueDamageCalls, 1)
			assertions.equal(environment.flushCalls, 1)
			assertions.equal(environment.queuedDamage.snapshot, first.value.snapshot)
			assertions.equal(environment.queuedDamage.appliedDamage, 10)
			assertions.equal(environment.queuedDamage.leakCount, 2)
			assertions.isFalse(environment.queuedDamage.lowHealthCrossed)

			local duplicate = service:finishEnemyPass(1)
			assertions.isTrue(duplicate.ok)
			assertions.equal(duplicate.value, first.value)
			assertions.equal(environment.finishCalls, 1)
			assertions.equal(environment.queueDamageCalls, 1)
			assertions.equal(environment.flushCalls, 1)

			local noop = service:finishEnemyPass(2)
			assertions.isTrue(noop.ok)
			assertions.equal(noop.value.kind, "Noop")
			local defeat = service:finishEnemyPass(3)
			assertions.isTrue(defeat.ok)
			assertions.equal(defeat.value.kind, "DefeatPending")
			assertions.equal(environment.queueDamageCalls, 1)
			assertions.equal(environment.flushCalls, 1)
			assertions.equal(service:getMetrics().lastFinishedEnemyPassOrdinal, 3)
		end
	),

	TestHarness.case("guards the pass successor comparison at the safe-integer boundary", function(assertions)
		local environment = makeEnvironment()
		environment.finishResults[Validation.MAX_SAFE_INTEGER] = Result.ok(table.freeze({
			kind = "Noop",
			passOrdinal = Validation.MAX_SAFE_INTEGER,
		}))
		environment.finishResults[1] = Result.err(table.freeze({
			code = "STALE_PASS",
			operation = "finishEnemyPass",
		}))
		local service = startService(environment)

		local maximum = service:finishEnemyPass(Validation.MAX_SAFE_INTEGER)
		assertions.isTrue(maximum.ok)
		assertions.equal(service:getMetrics().lastFinishedEnemyPassOrdinal, Validation.MAX_SAFE_INTEGER)
		local stale = service:finishEnemyPass(1)
		assertions.isFalse(stale.ok)
		assertions.equal(stale.error.code, "STALE_PASS")
		assertions.equal(environment.preflightCalls, 0)
		assertions.equal(service:getMetrics().lastFinishedEnemyPassOrdinal, Validation.MAX_SAFE_INTEGER)
	end),

	TestHarness.case("commits prepared defeat before one terminal Damage publication", function(assertions)
		local environment = makeEnvironment()
		local service, _definition, boundary = prepareDefeat(environment)
		assertions.equal(environment.preflightCalls, 1)
		assertions.equal(environment.queueDamageCalls, 0)
		assertions.equal(environment.flushCalls, 0)

		local committed = service:commitPreparedDefeat(boundary.preparedDefeat)
		assertions.isTrue(committed.ok)
		assertions.isTrue(table.isfrozen(committed.value))
		assertions.isTrue(committed.value.committed)
		assertions.isTrue(committed.value.published)
		assertions.equal(committed.value.snapshot.status, "Defeated")
		assertions.equal(committed.value.resultSeed, RESULT_SEED)
		assertions.equal(environment.commitPreparedCalls, 1)
		assertions.equal(environment.queueDamageCalls, 1)
		assertions.equal(environment.flushCalls, 1)
		assertions.equal(environment.queuedDamage.snapshot.status, "Defeated")
		assertions.equal(environment.queuedDamage.appliedDamage, 100)
		assertions.equal(environment.queuedDamage.leakCount, 2)
		assertions.isTrue(environment.queuedDamage.lowHealthCrossed)
		assertions.isTrue(
			indexOf(environment.trace, "runtime:commit-defeat") < indexOf(environment.trace, "publisher:queue-damage")
		)
		assertions.isTrue(
			indexOf(environment.trace, "publisher:queue-damage") < indexOf(environment.trace, "publisher:flush")
		)
		assertions.equal(service:getLifecycleState(), "Started")
		assertions.equal(service:getSnapshot().value.status, "Defeated")
		assertions.equal(service:getResultSeed().value, RESULT_SEED)
		assertions.isFalse(service:isTowerInputOpen())

		local duplicate = service:commitPreparedDefeat(boundary.preparedDefeat)
		assertions.isTrue(duplicate.ok)
		assertions.equal(duplicate.value, committed.value)
		assertions.equal(environment.commitPreparedCalls, 1)
		assertions.equal(environment.queueDamageCalls, 1)
		assertions.equal(environment.flushCalls, 1)
		assertions.isTrue(service:getMetrics().retainsCommittedDefeatOutcome)
		assertions.isFalse(service:getMetrics().retainsFailedDefeatOutcome)
	end),

	TestHarness.case("preserves committed terminal truth when publication fails", function(assertions)
		local environment = makeEnvironment()
		environment.flushMode = "failure"
		local service, _definition, boundary = prepareDefeat(environment)
		local committed = service:commitPreparedDefeat(boundary.preparedDefeat)
		assertions.isTrue(committed.ok)
		assertions.isTrue(committed.value.committed)
		assertions.isFalse(committed.value.published)
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.equal(environment.commitPreparedCalls, 1)
		assertions.equal(environment.queueDamageCalls, 1)
		assertions.equal(environment.flushCalls, 1)
		assertions.equal(environment.runtimeFaultCalls, 0)
		assertions.equal(service:getSnapshot().value.status, "Defeated")
		assertions.equal(service:getResultSeed().value, RESULT_SEED)
		assertions.isFalse(service:isTowerInputOpen())

		local duplicate = service:commitPreparedDefeat(boundary.preparedDefeat)
		assertions.isTrue(duplicate.ok)
		assertions.equal(duplicate.value, committed.value)
		assertions.equal(environment.commitPreparedCalls, 1)
		assertions.equal(environment.queueDamageCalls, 1)
		assertions.equal(environment.flushCalls, 1)
	end),

	TestHarness.case("faults a failed prepared defeat with one full State attempt", function(assertions)
		local environment = makeEnvironment()
		local service, _definition, boundary = prepareDefeat(environment)
		local failed = service:failPreparedDefeat(boundary.preparedDefeat)
		assertions.isTrue(failed.ok)
		assertions.isTrue(table.isfrozen(failed.value))
		assertions.isTrue(failed.value.failed)
		assertions.isTrue(failed.value.published)
		assertions.equal(failed.value.snapshot.status, "Faulted")
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.equal(environment.failPreparedCalls, 1)
		assertions.equal(environment.publishStateCalls, 1)
		assertions.equal(environment.publishedState.status, "Faulted")
		assertions.equal(environment.runtimeFaultCalls, 0)
		assertions.equal(service:getSnapshot().value.status, "Faulted")
		assertions.isFalse(service:getResultSeed().ok)
		assertions.isFalse(service:isTowerInputOpen())

		local duplicate = service:failPreparedDefeat(boundary.preparedDefeat)
		assertions.isTrue(duplicate.ok)
		assertions.equal(duplicate.value, failed.value)
		assertions.equal(environment.failPreparedCalls, 1)
		assertions.equal(environment.publishStateCalls, 1)
		assertions.isTrue(service:getMetrics().retainsFailedDefeatOutcome)
		assertions.isFalse(service:getMetrics().retainsCommittedDefeatOutcome)
	end),

	TestHarness.case("contains failed defeat State publication without retry", function(assertions)
		local environment = makeEnvironment()
		environment.publishStateMode = "failure"
		local service, _definition, boundary = prepareDefeat(environment)
		local failed = service:failPreparedDefeat(boundary.preparedDefeat)
		assertions.isTrue(failed.ok)
		assertions.isTrue(failed.value.failed)
		assertions.isFalse(failed.value.published)
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.equal(environment.publishStateCalls, 1)
		assertions.equal(environment.runtimeFaultCalls, 0)
		assertions.equal(service:getSnapshot().value.status, "Faulted")

		local duplicate = service:failPreparedDefeat(boundary.preparedDefeat)
		assertions.isTrue(duplicate.ok)
		assertions.equal(duplicate.value, failed.value)
		assertions.equal(environment.failPreparedCalls, 1)
		assertions.equal(environment.publishStateCalls, 1)
	end),

	TestHarness.case("defers shutdown through terminal commit and rejects reentry", function(assertions)
		local environment = makeEnvironment()
		local service, definition, boundary = prepareDefeat(environment)
		environment.flushHook = function()
			local reentrant = service:commitPreparedDefeat(boundary.preparedDefeat)
			environment.reentrantCommitError = reentrant.error
			invoke(definition.shutdown)
			assertions.equal(service:getLifecycleState(), "ShuttingDown")
			assertions.equal(environment.publisherCleanupCalls, 0)
		end

		local committed = service:commitPreparedDefeat(boundary.preparedDefeat)
		assertions.isTrue(committed.ok)
		assertions.isTrue(committed.value.committed)
		assertions.isTrue(committed.value.published)
		assertions.equal(environment.reentrantCommitError.code, "REENTRANT")
		assertions.equal(service:getLifecycleState(), "Shutdown")
		assertions.equal(environment.publisherCleanupCalls, 1)
		assertions.equal(environment.runtimeCleanupCalls, 1)
		assertions.isFalse(service:getMetrics().retainsCommittedDefeatOutcome)
		assertions.isFalse(service:getMetrics().retainsFailedDefeatOutcome)
		local afterCleanup = service:commitPreparedDefeat(boundary.preparedDefeat)
		assertions.isFalse(afterCleanup.ok)
		assertions.equal(afterCleanup.error.code, "UNAVAILABLE")
	end),

	TestHarness.case("rejects wrong or yielding prepared defeat operations", function(assertions)
		local wrongEnvironment = makeEnvironment()
		local wrongService = prepareDefeat(wrongEnvironment)
		local wrongToken = table.freeze({})
		local rejected = wrongService:commitPreparedDefeat(wrongToken)
		assertions.isFalse(rejected.ok)
		assertions.equal(rejected.error.code, "INVALID_TOKEN")
		assertions.equal(wrongService:getLifecycleState(), "Started")
		assertions.equal(wrongEnvironment.queueDamageCalls, 0)
		assertions.equal(wrongEnvironment.flushCalls, 0)

		local yieldingEnvironment = makeEnvironment()
		yieldingEnvironment.commitPreparedMode = "yield"
		local yieldingService, _definition, boundary = prepareDefeat(yieldingEnvironment)
		local yielding = yieldingService:commitPreparedDefeat(boundary.preparedDefeat)
		assertions.isFalse(yielding.ok)
		assertions.equal(yielding.error.code, "INTERNAL_ERROR")
		assertions.equal(yieldingService:getLifecycleState(), "Failed")
		assertions.equal(yieldingEnvironment.queueDamageCalls, 0)
		assertions.equal(yieldingEnvironment.flushCalls, 0)
	end),

	TestHarness.case("exposes only detached runtime snapshot and query reads", function(assertions)
		local environment = makeEnvironment()
		local service = startService(environment)
		local snapshotResult = service:getSnapshot()
		assertions.isTrue(snapshotResult.ok)
		assertions.equal(snapshotResult.value, SNAPSHOT)
		assertions.equal(service:query().state, "Active")
		assertions.isFalse(service:getDefeatState().defeatPending)
		assertions.isTrue(table.isfrozen(service:getMetrics()))
		assertions.isTrue(table.isfrozen(service:getMetrics().runtime))
		assertions.isTrue(table.isfrozen(service:getMetrics().publisher))
	end),

	TestHarness.case("contains publisher and callback faults and closes mutation admission", function(assertions)
		local environment = makeEnvironment()
		environment.publishStateMode = "failure"
		local service, definition = startService(environment)
		local publicationFailure = service:initializeBase(DEFINITION)
		assertions.isFalse(publicationFailure.ok)
		assertions.equal(publicationFailure.error.code, "INTERNAL_ERROR")
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.isFalse(service:getMetrics().callbacksEnabled)
		local closed = service:recordLeak(table.freeze({}))
		assertions.isFalse(closed.ok)
		assertions.equal(closed.error.code, "UNAVAILABLE")
		local recovery = service:getSnapshot()
		assertions.isTrue(recovery.ok)
		invoke(definition.shutdown)
		assertions.equal(environment.publisherCleanupCalls, 1)
		assertions.equal(environment.runtimeCleanupCalls, 1)

		local yieldingEnvironment = makeEnvironment()
		yieldingEnvironment.recordLeakMode = "yield"
		local yieldingService = startService(yieldingEnvironment)
		local yielding = yieldingService:recordLeak(table.freeze({}))
		assertions.isFalse(yielding.ok)
		assertions.equal(yielding.error.code, "INTERNAL_ERROR")
		assertions.equal(yieldingService:getLifecycleState(), "Failed")
	end),

	TestHarness.case("rejects reentry and defers shutdown until the publication boundary", function(assertions)
		local environment = makeEnvironment()
		local service, definition = startService(environment)
		environment.publishStateHook = function()
			local reentrant = service:recordLeak(table.freeze({}))
			environment.reentrantError = reentrant.error
		end
		local initialized = service:initializeBase(DEFINITION)
		assertions.isTrue(initialized.ok)
		assertions.equal(environment.reentrantError.code, "REENTRANT")
		assertions.equal(environment.recordLeakCalls, 0)

		environment.finishResults[1] = Result.ok(damageBoundary(1))
		environment.flushHook = function()
			invoke(definition.shutdown)
			assertions.equal(service:getLifecycleState(), "ShuttingDown")
			assertions.equal(environment.publisherCleanupCalls, 0)
		end
		local boundary = service:finishEnemyPass(1)
		assertions.isTrue(boundary.ok)
		assertions.equal(service:getLifecycleState(), "Shutdown")
		assertions.equal(environment.publisherCleanupCalls, 1)
		assertions.equal(environment.runtimeCleanupCalls, 1)
	end),

	TestHarness.case("unwinds partial initialization and attempts both cleanup operations", function(assertions)
		local publisherFailure = makeEnvironment()
		publisherFailure.publisherFactoryMode = "failure"
		local publisherService = createService(publisherFailure)
		local publisherDefinition = publisherService:getServiceDefinition()
		expectStaticFailure(assertions, function()
			invoke(publisherDefinition.initialize)
		end, "PUBLISHER_CREATION_FAILED")
		assertions.equal(publisherFailure.runtimeCleanupCalls, 1)
		assertions.equal(publisherFailure.publisherCleanupCalls, 0)

		local cleanupFailure = makeEnvironment()
		cleanupFailure.publisherCleanupMode = "failure"
		local cleanupService, cleanupDefinition = startService(cleanupFailure)
		expectStaticFailure(assertions, function()
			invoke(cleanupDefinition.shutdown)
		end, "CLEANUP_FAILED")
		assertions.equal(cleanupFailure.publisherCleanupCalls, 1)
		assertions.equal(cleanupFailure.runtimeCleanupCalls, 1)
		assertions.equal(cleanupService:getLifecycleState(), "Failed")
	end),

	TestHarness.case("rejects malformed factories dependencies and lifecycle order", function(assertions)
		local invalidRuntime = makeEnvironment()
		invalidRuntime.runtimeFactoryMode = "invalid"
		local invalidRuntimeService = createService(invalidRuntime)
		expectStaticFailure(assertions, function()
			invoke(invalidRuntimeService:getServiceDefinition().initialize)
		end, "RUNTIME_INVALID")

		local invalidPublisher = makeEnvironment()
		invalidPublisher.publisherFactoryMode = "invalid"
		local invalidPublisherService = createService(invalidPublisher)
		expectStaticFailure(assertions, function()
			invoke(invalidPublisherService:getServiceDefinition().initialize)
		end, "PUBLISHER_INVALID")
		assertions.equal(invalidPublisher.runtimeCleanupCalls, 1)

		local invalidLifecycle = makeEnvironment()
		invalidLifecycle.matchSnapshotMode = "invalid"
		local invalidLifecycleService = createService(invalidLifecycle)
		expectStaticFailure(assertions, function()
			invoke(invalidLifecycleService:getServiceDefinition().initialize)
		end, "MATCH_SNAPSHOT_INVALID")

		local environment = makeEnvironment()
		local service = createService(environment)
		local definition = service:getServiceDefinition()
		expectStaticFailure(assertions, function()
			invoke(definition.start)
		end, "INVALID_STATE")
		invoke(definition.initialize)
		expectStaticFailure(assertions, function()
			invoke(definition.initialize)
		end, "INVALID_STATE")
		invoke(definition.start)
		expectStaticFailure(assertions, function()
			invoke(definition.start)
		end, "INVALID_STATE")
		invoke(definition.shutdown)

		expectStaticFailure(assertions, function()
			(newForTests :: BaseRuntimeService.TestConstructor)({} :: any)
		end, "INVALID_DEPENDENCIES")
		local extraDependencies = table.clone(environment.dependencies)
		extraDependencies.extra = true
		expectStaticFailure(assertions, function()
			(newForTests :: BaseRuntimeService.TestConstructor)(extraDependencies :: any)
		end, "INVALID_DEPENDENCIES")
	end),
})
