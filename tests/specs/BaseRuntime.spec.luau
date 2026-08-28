--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local BaseFixtures = require(script.Parent.Parent.Fixtures.BaseFixtures)
local EnemyFixtures = require(script.Parent.Parent.Fixtures.EnemyFixtures)
local BaseRuntime = require(script.Parent.Parent.ProductionServerBase.BaseRuntime)
local EnemyRuntimeStore = require(script.Parent.Parent.ProductionServerEnemies.EnemyRuntimeStore)
local AssetSchema = require(ReplicatedStorage.Shared.config.AssetSchema)
local DifficultySchema = require(ReplicatedStorage.Shared.config.DifficultySchema)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

type Assertions = TestHarness.Assertions

type ClockState = {
	now: number,
}

type OutcomeStore = {
	store: EnemyRuntimeStore.Store,
	clock: ClockState,
	outcomes: { EnemyRuntimeStore.AuthenticatedLeakOutcome },
}

local function expectError(assertions: Assertions, result: any, code: string, operation: string)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		assertions.isTrue(table.isfrozen(result.error))
		assertions.equal(result.error.code, code)
		assertions.equal(result.error.operation, operation)
	end
end

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected Phase 10 fixture operation to succeed", 0)
	end
	return result.value
end

local function authenticateEmptyDifficultyCatalog(assertions: Assertions): any
	local fixture = BaseFixtures.createDifficultyFixture()
	local manifest = success(assertions, AssetSchema.validateManifest(fixture.rawSources.assets))
	return success(assertions, DifficultySchema.validateCatalog({}, manifest))
end

local function assertDetachedFrozen(assertions: Assertions, value: unknown, seen: { [any]: boolean }?)
	assertions.isFalse(typeof(value) == "Instance")
	if type(value) ~= "table" then
		return
	end
	local visited = seen or {}
	if visited[value :: any] then
		return
	end
	visited[value :: any] = true
	assertions.isTrue(table.isfrozen(value :: any))
	for key, child in next, value :: { [any]: unknown } do
		assertDetachedFrozen(assertions, key, visited)
		assertDetachedFrozen(assertions, child, visited)
	end
end

local function newRuntime(
	assertions: Assertions,
	state: string?,
	maximumHealth: number?,
	optionOverrides: { [string]: any }?
): (
	BaseRuntime.Runtime,
	BaseFixtures.LifecycleControl,
	BaseFixtures.DifficultyFixture,
	ClockState
)
	local fixture = BaseFixtures.createDifficultyFixture(maximumHealth)
	local lifecycle, control = BaseFixtures.createLifecycle(state)
	local clock = { now = 100 }
	local options: { [string]: any } = {
		clock = function()
			return clock.now
		end,
	}
	if optionOverrides ~= nil then
		for key, value in optionOverrides do
			options[key] = value
		end
	end
	local runtime = success(
		assertions,
		BaseRuntime.newForTests(BaseFixtures.MATCH_ID, BaseFixtures.ENEMY_EPOCH, fixture.catalog, lifecycle, options)
	)
	return runtime, control, fixture, clock
end

local function newOutcomeStore(
	assertions: Assertions,
	matchId: string?,
	epoch: number?,
	leakDamageByEnemyId: { [string]: number }?,
	nextRuntimeEnemyId: number?
): OutcomeStore
	local rawEnemies = EnemyFixtures.rawEnemies()
	for _, definition in rawEnemies do
		local damage = if leakDamageByEnemyId == nil then nil else leakDamageByEnemyId[definition.id]
		if damage ~= nil then
			definition.leakDamage = damage
		end
	end
	local catalog = EnemyFixtures.authenticateCatalog(EnemyFixtures.rawAssets(), rawEnemies).catalog
	local clock = { now = 10 }
	local outcomes: { EnemyRuntimeStore.AuthenticatedLeakOutcome } = {}
	local options: { [string]: any } = {
		clock = function()
			return clock.now
		end,
		endpointSink = function(outcome: EnemyRuntimeStore.AuthenticatedLeakOutcome)
			table.insert(outcomes, outcome)
		end,
	}
	if nextRuntimeEnemyId ~= nil then
		options.nextRuntimeEnemyId = nextRuntimeEnemyId
	end
	local store = success(
		assertions,
		EnemyRuntimeStore.newForTests(
			matchId or BaseFixtures.MATCH_ID,
			epoch or BaseFixtures.ENEMY_EPOCH,
			catalog,
			EnemyFixtures.createRuntimeMapSnapshot(),
			options
		)
	)
	return {
		store = store,
		clock = clock,
		outcomes = outcomes,
	}
end

local function issueOutcome(
	assertions: Assertions,
	fixture: OutcomeStore,
	enemyId: string,
	serverTime: number
): EnemyRuntimeStore.AuthenticatedLeakOutcome
	fixture.clock.now = serverTime
	local spawned = success(assertions, fixture.store:spawn(enemyId, EnemyFixtures.BENT_LANE_ID))
	fixture.clock.now = serverTime
	success(assertions, fixture.store:resolveEndpoint(spawned.runtimeEnemyId))
	local outcome = fixture.outcomes[#fixture.outcomes]
	assertions.isNotNil(outcome)
	return outcome
end

return TestHarness.suite("server base runtime", {
	TestHarness.case("authenticates construction identity map catalog and dependencies", function(assertions)
		local runtime, _, fixture = newRuntime(assertions)
		local query = runtime:query()
		assertions.equal(query.state, "Uninitialized")
		assertions.equal(query.matchId, BaseFixtures.MATCH_ID)
		assertions.equal(query.enemyEpoch, BaseFixtures.ENEMY_EPOCH)
		assertions.equal(query.mapId, EnemyFixtures.MAP_ID)
		assertions.isNil(query.maximumHealth)
		assertions.equal(query.processedOutcomeCount, 0)
		assertDetachedFrozen(assertions, query)

		local lifecycle = BaseFixtures.createLifecycle()
		expectError(
			assertions,
			BaseRuntime.newForTests("bad", 1, fixture.catalog, lifecycle, {}),
			"INVALID_MATCH_ID",
			"new"
		)
		expectError(
			assertions,
			BaseRuntime.newForTests(BaseFixtures.MATCH_ID, 0, fixture.catalog, lifecycle, {}),
			"INVALID_EPOCH",
			"new"
		)
		expectError(
			assertions,
			BaseRuntime.newForTests(BaseFixtures.MATCH_ID, 1, {}, lifecycle, {}),
			"UNAUTHENTICATED_CATALOG",
			"new"
		)
		expectError(
			assertions,
			BaseRuntime.newForTests(BaseFixtures.MATCH_ID, 1, fixture.catalog, {}, {}),
			"INVALID_DEPENDENCY",
			"new"
		)
		expectError(
			assertions,
			BaseRuntime.newForTests(BaseFixtures.MATCH_ID, 1, fixture.catalog, lifecycle, {
				studioCatalogInstallEnabled = "yes",
			}),
			"INVALID_DEPENDENCY",
			"new"
		)

		local invalidMapLifecycle, invalidMapControl = BaseFixtures.createLifecycle()
		invalidMapControl.mapSnapshot = table.freeze({
			mapId = EnemyFixtures.MAP_ID,
			base = table.freeze({
				cframe = CFrame.new(),
				position = Vector3.new(1, 0, 0),
			}),
		})
		expectError(
			assertions,
			BaseRuntime.newForTests(BaseFixtures.MATCH_ID, 1, fixture.catalog, invalidMapLifecycle, {}),
			"INVALID_RUNTIME_MAP",
			"new"
		)
	end),

	TestHarness.case(
		"installs one fresh authenticated Studio difficulty catalog before initialization",
		function(assertions)
			local emptyCatalog = authenticateEmptyDifficultyCatalog(assertions)
			local fixture = BaseFixtures.createDifficultyFixture(250)
			local replacement = BaseFixtures.createDifficultyFixture(500)
			local lifecycle = BaseFixtures.createLifecycle("ReadyCheck")
			local runtime = success(
				assertions,
				BaseRuntime.newForTests(BaseFixtures.MATCH_ID, BaseFixtures.ENEMY_EPOCH, emptyCatalog, lifecycle, {
					clock = function()
						return 100
					end,
					studioCatalogInstallEnabled = true,
				})
			)

			expectError(assertions, runtime:installStudioCatalog({}), "UNAUTHENTICATED_CATALOG", "installStudioCatalog")
			local clonedCatalog = table.clone(fixture.catalog :: any)
			table.freeze(clonedCatalog)
			expectError(
				assertions,
				runtime:installStudioCatalog(clonedCatalog),
				"UNAUTHENTICATED_CATALOG",
				"installStudioCatalog"
			)
			expectError(
				assertions,
				runtime:installStudioCatalog(emptyCatalog),
				"INVALID_LIFECYCLE",
				"installStudioCatalog"
			)

			assertions.isTrue(success(assertions, runtime:installStudioCatalog(fixture.catalog)))
			assertions.equal(runtime:query().state, "Uninitialized")
			assertions.equal(runtime:query().processedOutcomeCount, 0)
			expectError(
				assertions,
				runtime:installStudioCatalog(replacement.catalog),
				"STUDIO_ONLY",
				"installStudioCatalog"
			)

			local initialized = success(assertions, runtime:initialize(fixture.definition))
			assertions.equal(initialized.maximumHealth, 250)
			assertions.equal(initialized.currentHealth, 250)
			expectError(
				assertions,
				runtime:initialize(replacement.definition),
				"DUPLICATE_INITIALIZATION",
				"initialize"
			)
		end
	),

	TestHarness.case(
		"rejects Studio catalog replacement outside the pristine outcome-free runtime boundary",
		function(assertions)
			local emptyCatalog = authenticateEmptyDifficultyCatalog(assertions)
			local fixture = BaseFixtures.createDifficultyFixture(100)
			local replacement = BaseFixtures.createDifficultyFixture(200)
			local lifecycle = BaseFixtures.createLifecycle("ReadyCheck")
			local function construct(catalog: unknown, enabled: boolean): BaseRuntime.Runtime
				return success(
					assertions,
					BaseRuntime.newForTests(BaseFixtures.MATCH_ID, BaseFixtures.ENEMY_EPOCH, catalog, lifecycle, {
						clock = function()
							return 100
						end,
						studioCatalogInstallEnabled = enabled,
					})
				)
			end

			local disabled = construct(emptyCatalog, false)
			expectError(
				assertions,
				disabled:installStudioCatalog(fixture.catalog),
				"STUDIO_ONLY",
				"installStudioCatalog"
			)

			local productionCatalog = construct(fixture.catalog, true)
			expectError(
				assertions,
				productionCatalog:installStudioCatalog(replacement.catalog),
				"INVALID_LIFECYCLE",
				"installStudioCatalog"
			)
			assertions.equal(success(assertions, productionCatalog:initialize(fixture.definition)).maximumHealth, 100)

			local processedOutcome = construct(authenticateEmptyDifficultyCatalog(assertions), true)
			local outcomeStore = newOutcomeStore(assertions, nil, nil, nil, nil)
			local outcome = issueOutcome(assertions, outcomeStore, EnemyFixtures.NORMAL_ENEMY_ID, 110)
			local ignored = success(assertions, processedOutcome:recordLeak(outcome))
			assertions.equal(ignored.reason, "Uninitialized")
			expectError(
				assertions,
				processedOutcome:installStudioCatalog(fixture.catalog),
				"INVALID_LIFECYCLE",
				"installStudioCatalog"
			)

			local finishedPass = construct(authenticateEmptyDifficultyCatalog(assertions), true)
			assertions.equal(success(assertions, finishedPass:finishEnemyPass(1)).kind, "Noop")
			assertions.isTrue(success(assertions, finishedPass:installStudioCatalog(fixture.catalog)))
			local initializedAfterPass = success(assertions, finishedPass:initialize(fixture.definition))
			assertions.equal(initializedAfterPass.maximumHealth, 100)
			assertions.equal(finishedPass:query().lastFinishedEnemyPassOrdinal, 1)

			local cleaned = construct(authenticateEmptyDifficultyCatalog(assertions), true)
			assertions.isTrue(success(assertions, cleaned:cleanup()))
			expectError(assertions, cleaned:installStudioCatalog(fixture.catalog), "CLEANED", "installStudioCatalog")
			local metrics = cleaned:getMetrics()
			assertions.isFalse(metrics.retainsCatalog)
			assertions.isTrue(metrics.cleaned)
		end
	),

	TestHarness.case(
		"initializes once from the exact canonical difficulty without retaining raw mutation",
		function(assertions)
			local runtime, _, fixture, clock = newRuntime(assertions, "ReadyCheck", 100)
			fixture.rawSources.difficulties[1].base.maxHealth = 9_999
			clock.now = 125
			local snapshot = success(assertions, runtime:initialize(fixture.definition))
			assertions.equal(snapshot.maximumHealth, 100)
			assertions.equal(snapshot.currentHealth, 100)
			assertions.equal(snapshot.baseRevision, 1)
			assertions.equal(snapshot.status, "Active")
			assertions.equal(snapshot.initializedServerTime, 125)
			assertions.equal(snapshot.updatedServerTime, 125)
			assertions.equal(snapshot.basePosition, Vector3.new(20, 5, 20))
			assertions.isFalse(snapshot.lowHealth)
			assertDetachedFrozen(assertions, snapshot)

			local cloned = table.clone(fixture.definition :: any)
			cloned.base = fixture.definition.base
			table.freeze(cloned)
			local otherRuntime = newRuntime(assertions)
			expectError(assertions, otherRuntime:initialize(cloned), "INVALID_DEFINITION", "initialize")
			expectError(assertions, runtime:initialize(fixture.definition), "DUPLICATE_INITIALIZATION", "initialize")
		end
	),

	TestHarness.case("permits initialization only in ReadyCheck or PreWave", function(assertions)
		for _, state in { "Loading", "ReadyCheck", "PreWave", "WaveActive", "Results", "Closing" } do
			local runtime, _, fixture = newRuntime(assertions, state)
			local result = runtime:initialize(fixture.definition)
			if state == "ReadyCheck" or state == "PreWave" then
				assertions.isTrue(result.ok)
				assertions.equal(runtime:query().currentHealth, 100)
			else
				expectError(assertions, result, "INVALID_LIFECYCLE", "initialize")
				assertions.equal(runtime:query().state, "Uninitialized")
			end
		end
	end),

	TestHarness.case("consumes every non-WaveActive outcome without mutating initialized health", function(assertions)
		for _, state in { "Loading", "ReadyCheck", "PreWave", "Results", "Closing" } do
			local runtime, control, fixture = newRuntime(assertions, "PreWave")
			success(assertions, runtime:initialize(fixture.definition))
			control.state = state
			control.revision += 1
			local store = newOutcomeStore(assertions, nil, nil, {
				[EnemyFixtures.NORMAL_ENEMY_ID] = 10,
			})
			local outcome = issueOutcome(assertions, store, EnemyFixtures.NORMAL_ENEMY_ID, 110)
			local ignoredResult = success(assertions, runtime:recordLeak(outcome))
			assertions.equal(ignoredResult.kind, "Ignored")
			assertions.equal(ignoredResult.reason, "WrongLifecycle")
			assertions.isTrue(ignoredResult.outcomeConsumed)
			local query = runtime:query()
			assertions.equal(query.currentHealth, 100)
			assertions.equal(query.baseRevision, 1)
			assertions.equal(query.processedOutcomeCount, 1)
			success(assertions, store.store:cleanup())
		end
	end),

	TestHarness.case("applies zero normal exact overkill and maximum-safe damage exactly", function(assertions)
		local zeroRuntime, zeroControl, zeroDifficulty = newRuntime(assertions, "PreWave")
		success(assertions, zeroRuntime:initialize(zeroDifficulty.definition))
		zeroControl.state = "WaveActive"
		local zeroStore = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 0,
		})
		local zero = success(
			assertions,
			zeroRuntime:recordLeak(issueOutcome(assertions, zeroStore, EnemyFixtures.NORMAL_ENEMY_ID, 110))
		)
		assertions.equal(zero.kind, "Ignored")
		assertions.equal(zero.reason, "ZeroDamage")
		assertions.equal(zeroRuntime:query().currentHealth, 100)
		assertions.equal(zeroRuntime:query().baseRevision, 1)
		assertions.equal(zeroRuntime:getMetrics().pendingLeakCount, 0)

		for _, requestedDamage in { 100, 101, Validation.MAX_SAFE_INTEGER } do
			local runtime, control, difficulty = newRuntime(assertions, "PreWave")
			success(assertions, runtime:initialize(difficulty.definition))
			control.state = "WaveActive"
			local store = newOutcomeStore(assertions, nil, nil, {
				[EnemyFixtures.NORMAL_ENEMY_ID] = requestedDamage,
			})
			local applied = success(
				assertions,
				runtime:recordLeak(issueOutcome(assertions, store, EnemyFixtures.NORMAL_ENEMY_ID, 110))
			)
			assertions.equal(applied.kind, "Applied")
			assertions.equal(applied.appliedDamage, 100)
			assertions.equal(applied.baseRevision, 2)
			assertions.isTrue(applied.defeatPending)
			assertions.equal(runtime:query().currentHealth, 0)
			assertions.equal(runtime:getMetrics().pendingAppliedDamage, 100)
		end
	end),

	TestHarness.case("orders simultaneous leaks deterministically and crosses low health once", function(assertions)
		local runtime, control, difficulty = newRuntime(assertions, "PreWave")
		success(assertions, runtime:initialize(difficulty.definition))
		control.state = "WaveActive"
		local store = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 40,
			[EnemyFixtures.FAST_ENEMY_ID] = 35,
			[EnemyFixtures.SLOW_ENEMY_ID] = 1,
		})
		local first = issueOutcome(assertions, store, EnemyFixtures.NORMAL_ENEMY_ID, 110)
		local second = issueOutcome(assertions, store, EnemyFixtures.FAST_ENEMY_ID, 110)
		local third = issueOutcome(assertions, store, EnemyFixtures.SLOW_ENEMY_ID, 110)
		success(assertions, runtime:recordLeak(first))
		assertions.equal(runtime:query().currentHealth, 60)
		assertions.isFalse(runtime:query().lowHealth)
		success(assertions, runtime:recordLeak(second))
		assertions.equal(runtime:query().currentHealth, 25)
		assertions.isTrue(runtime:query().lowHealth)
		assertions.isTrue(runtime:query().lowHealthCrossingIssued)
		success(assertions, runtime:recordLeak(third))
		local query = runtime:query()
		assertions.equal(query.currentHealth, 24)
		assertions.equal(query.baseRevision, 4)
		local metrics = runtime:getMetrics()
		assertions.equal(metrics.pendingLeakCount, 3)
		assertions.equal(metrics.pendingAppliedDamage, 76)
		local boundary = success(assertions, runtime:finishEnemyPass(1))
		assertions.equal(boundary.kind, "Damage")
		assertions.equal(boundary.snapshot.currentHealth, 24)
		assertions.equal(boundary.snapshot.baseRevision, 4)
		assertions.equal(boundary.appliedDamage, 76)
		assertions.equal(boundary.leakCount, 3)
		assertions.isTrue(boundary.lowHealthCrossed)
		assertions.equal(success(assertions, runtime:finishEnemyPass(1)), boundary)
		expectError(assertions, runtime:finishEnemyPass(3), "INVALID_PASS", "finishEnemyPass")
		local noChange = success(assertions, runtime:finishEnemyPass(2))
		assertions.equal(noChange.kind, "Noop")
		assertions.equal(runtime:getMetrics().pendingLeakCount, 0)
		assertions.equal(runtime:getMetrics().lastFinishedEnemyPassOrdinal, 2)
	end),

	TestHarness.case("rejects forged wrong identity duplicate conflicting and stale outcomes", function(assertions)
		local runtime, control, difficulty = newRuntime(assertions, "PreWave")
		success(assertions, runtime:initialize(difficulty.definition))
		control.state = "WaveActive"

		local primary = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 10,
		})
		local outcome = issueOutcome(assertions, primary, EnemyFixtures.NORMAL_ENEMY_ID, 120)
		success(assertions, runtime:recordLeak(outcome))
		local duplicate = success(assertions, runtime:recordLeak(outcome))
		assertions.equal(duplicate.kind, "Ignored")
		assertions.equal(duplicate.reason, "Duplicate")
		assertions.equal(runtime:query().currentHealth, 90)

		local conflictingStore = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.FAST_ENEMY_ID] = 11,
		})
		local conflicting = issueOutcome(assertions, conflictingStore, EnemyFixtures.FAST_ENEMY_ID, 121)
		local conflictResult = success(assertions, runtime:recordLeak(conflicting))
		assertions.equal(conflictResult.kind, "Ignored")
		assertions.equal(conflictResult.reason, "ConflictingReplay")
		assertions.isFalse(conflictResult.outcomeConsumed)

		local wrongMatchStore = newOutcomeStore(assertions, BaseFixtures.OTHER_MATCH_ID, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 1,
		})
		expectError(
			assertions,
			runtime:recordLeak(issueOutcome(assertions, wrongMatchStore, EnemyFixtures.NORMAL_ENEMY_ID, 122)),
			"WRONG_MATCH",
			"recordLeak"
		)
		local wrongEpochStore = newOutcomeStore(assertions, nil, BaseFixtures.ENEMY_EPOCH + 1, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 1,
		})
		expectError(
			assertions,
			runtime:recordLeak(issueOutcome(assertions, wrongEpochStore, EnemyFixtures.NORMAL_ENEMY_ID, 122)),
			"WRONG_EPOCH",
			"recordLeak"
		)
		expectError(
			assertions,
			runtime:recordLeak(table.freeze({
				matchId = BaseFixtures.MATCH_ID,
				enemyEpoch = BaseFixtures.ENEMY_EPOCH,
				runtimeEnemyId = 2,
				enemyId = EnemyFixtures.NORMAL_ENEMY_ID,
				leakDamage = 1,
				serverTime = 123,
			})),
			"UNAUTHENTICATED_OUTCOME",
			"recordLeak"
		)

		local lateStore = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 1,
		}, 2)
		local earlyStore = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 1,
		}, 3)
		success(assertions, runtime:recordLeak(issueOutcome(assertions, lateStore, EnemyFixtures.NORMAL_ENEMY_ID, 130)))
		expectError(
			assertions,
			runtime:recordLeak(issueOutcome(assertions, earlyStore, EnemyFixtures.NORMAL_ENEMY_ID, 129)),
			"STALE_OUTCOME",
			"recordLeak"
		)
		assertions.equal(runtime:query().currentHealth, 89)
	end),

	TestHarness.case("consumes uninitialized and late post-defeat identities at most once", function(assertions)
		local runtime, control, difficulty = newRuntime(assertions, "PreWave", 10)
		local store = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 1,
			[EnemyFixtures.FAST_ENEMY_ID] = 10,
			[EnemyFixtures.SLOW_ENEMY_ID] = 5,
		})
		local beforeInitialization = issueOutcome(assertions, store, EnemyFixtures.NORMAL_ENEMY_ID, 90)
		local ignored = success(assertions, runtime:recordLeak(beforeInitialization))
		assertions.equal(ignored.reason, "Uninitialized")
		assertions.isTrue(ignored.outcomeConsumed)
		success(assertions, runtime:initialize(difficulty.definition))
		control.state = "WaveActive"
		local replay = success(assertions, runtime:recordLeak(beforeInitialization))
		assertions.equal(replay.reason, "Duplicate")
		assertions.equal(runtime:query().currentHealth, 10)

		local lethal = issueOutcome(assertions, store, EnemyFixtures.FAST_ENEMY_ID, 110)
		local applied = success(assertions, runtime:recordLeak(lethal))
		assertions.isTrue(applied.defeatPending)
		assertions.equal(runtime:getDefeatState().state, "DefeatPending")
		assertions.isTrue(runtime:getDefeatState().towerInputAdmissionClosed)
		local late = issueOutcome(assertions, store, EnemyFixtures.SLOW_ENEMY_ID, 111)
		local lateResult = success(assertions, runtime:recordLeak(late))
		assertions.equal(lateResult.reason, "PostDefeat")
		assertions.isTrue(lateResult.outcomeConsumed)
		assertions.equal(runtime:query().currentHealth, 0)
		assertions.equal(runtime:query().baseRevision, 2)
		expectError(assertions, runtime:getSnapshot(), "UNAVAILABLE", "getSnapshot")
	end),

	TestHarness.case("prepares and commits or faults one authenticated terminal defeat", function(assertions)
		local runtime, control, difficulty, clock = newRuntime(assertions, "PreWave", 100)
		success(assertions, runtime:initialize(difficulty.definition))
		control.state = "WaveActive"
		local store = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 100,
		})
		success(assertions, runtime:recordLeak(issueOutcome(assertions, store, EnemyFixtures.NORMAL_ENEMY_ID, 110)))
		assertions.isFalse(runtime:isTowerInputOpen())
		clock.now = 120
		local boundary = success(assertions, runtime:finishEnemyPass(1))
		assertions.equal(boundary.kind, "DefeatPending")
		assertions.equal(boundary.baseRevision, 2)
		assertions.equal(boundary.appliedDamage, 100)
		assertions.equal(boundary.leakCount, 1)
		assertions.isTrue(table.isfrozen(boundary.preparedDefeat))
		assertions.isTrue(runtime:getMetrics().retainsPreparedDefeat)
		expectError(assertions, runtime:commitPreparedDefeat(table.freeze({})), "INVALID_TOKEN", "commitPreparedDefeat")

		local completed = success(assertions, runtime:commitPreparedDefeat(boundary.preparedDefeat))
		assertions.isTrue(completed.committed)
		assertions.equal(completed.snapshot.status, "Defeated")
		assertions.equal(completed.snapshot.currentHealth, 0)
		assertions.equal(completed.snapshot.baseRevision, 3)
		assertions.equal(completed.snapshot.updatedServerTime, 120)
		assertions.equal(completed.resultSeed.outcome, "Defeat")
		assertions.equal(completed.resultSeed.reason, "BaseHealthDepleted")
		assertions.equal(completed.resultSeed.baseRevision, 3)
		assertions.equal(completed.resultSeed.currentHealth, 0)
		assertDetachedFrozen(assertions, completed)
		assertions.equal(success(assertions, runtime:commitPreparedDefeat(boundary.preparedDefeat)), completed)
		local recoveredSnapshot = success(assertions, runtime:getSnapshot())
		assertions.equal(recoveredSnapshot.status, completed.snapshot.status)
		assertions.equal(recoveredSnapshot.baseRevision, completed.snapshot.baseRevision)
		assertions.equal(recoveredSnapshot.currentHealth, completed.snapshot.currentHealth)
		assertions.equal(success(assertions, runtime:getResultSeed()), completed.resultSeed)
		assertions.isTrue(runtime:getDefeatState().defeated)
		assertions.isTrue(runtime:getMetrics().retainsResultSeed)

		local faulted, faultControl, faultDifficulty, faultClock = newRuntime(assertions, "PreWave", 100)
		success(assertions, faulted:initialize(faultDifficulty.definition))
		faultControl.state = "WaveActive"
		local faultStore = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 100,
		})
		success(
			assertions,
			faulted:recordLeak(issueOutcome(assertions, faultStore, EnemyFixtures.NORMAL_ENEMY_ID, 110))
		)
		faultClock.now = 121
		local faultBoundary = success(assertions, faulted:finishEnemyPass(1))
		local faultSnapshot = success(assertions, faulted:failPreparedDefeat(faultBoundary.preparedDefeat))
		assertions.equal(faultSnapshot.status, "Faulted")
		assertions.equal(faultSnapshot.currentHealth, 0)
		assertions.equal(faultSnapshot.baseRevision, 3)
		assertions.equal(success(assertions, faulted:failPreparedDefeat(faultBoundary.preparedDefeat)), faultSnapshot)
		expectError(assertions, faulted:getResultSeed(), "UNAVAILABLE", "getResultSeed")
		assertions.isFalse(faulted:getMetrics().retainsPreparedDefeat)
		assertions.isFalse(faulted:getMetrics().retainsResultSeed)
	end),

	TestHarness.case("fails closed when terminal defeat time cannot follow the lethal outcome", function(assertions)
		local runtime, control, difficulty, clock = newRuntime(assertions, "PreWave", 100)
		success(assertions, runtime:initialize(difficulty.definition))
		control.state = "WaveActive"
		local store = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 100,
		})
		success(assertions, runtime:recordLeak(issueOutcome(assertions, store, EnemyFixtures.NORMAL_ENEMY_ID, 110)))
		clock.now = 109
		expectError(assertions, runtime:finishEnemyPass(1), "CLOCK_FAILED", "finishEnemyPass")
		assertions.equal(runtime:query().state, "Faulted")
		assertions.equal(runtime:query().currentHealth, 0)
		assertions.isTrue(runtime:getDefeatState().towerInputAdmissionClosed)
		assertions.equal(success(assertions, runtime:getSnapshot()).status, "Faulted")
	end),

	TestHarness.case("fails closed at ledger and revision limits without corrupting health", function(assertions)
		local capped, _, _ = newRuntime(assertions, "PreWave", 100, {
			maxProcessedOutcomes = 2,
		})
		local capStore = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 0,
			[EnemyFixtures.FAST_ENEMY_ID] = 0,
			[EnemyFixtures.SLOW_ENEMY_ID] = 0,
		})
		success(assertions, capped:recordLeak(issueOutcome(assertions, capStore, EnemyFixtures.NORMAL_ENEMY_ID, 10)))
		success(assertions, capped:recordLeak(issueOutcome(assertions, capStore, EnemyFixtures.FAST_ENEMY_ID, 11)))
		expectError(
			assertions,
			capped:recordLeak(issueOutcome(assertions, capStore, EnemyFixtures.SLOW_ENEMY_ID, 12)),
			"CAPACITY_EXCEEDED",
			"recordLeak"
		)
		assertions.equal(capped:query().state, "Faulted")
		assertions.equal(capped:query().processedOutcomeCount, 2)

		local exhausted, exhaustedControl, exhaustedDifficulty = newRuntime(assertions, "PreWave", 100, {
			initialBaseRevision = Validation.MAX_SAFE_INTEGER - 1,
		})
		success(assertions, exhausted:initialize(exhaustedDifficulty.definition))
		exhaustedControl.state = "WaveActive"
		local revisionStore = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 1,
			[EnemyFixtures.FAST_ENEMY_ID] = 1,
		})
		success(
			assertions,
			exhausted:recordLeak(issueOutcome(assertions, revisionStore, EnemyFixtures.NORMAL_ENEMY_ID, 110))
		)
		assertions.equal(exhausted:query().baseRevision, Validation.MAX_SAFE_INTEGER)
		expectError(
			assertions,
			exhausted:recordLeak(issueOutcome(assertions, revisionStore, EnemyFixtures.FAST_ENEMY_ID, 111)),
			"REVISION_EXHAUSTED",
			"recordLeak"
		)
		assertions.equal(exhausted:query().currentHealth, 99)
		assertions.equal(exhausted:query().state, "Faulted")
		expectError(assertions, exhausted:getSnapshot(), "UNAVAILABLE", "getSnapshot")

		local lethalExhausted, lethalControl, lethalDifficulty = newRuntime(assertions, "PreWave", 100, {
			initialBaseRevision = Validation.MAX_SAFE_INTEGER - 1,
		})
		success(assertions, lethalExhausted:initialize(lethalDifficulty.definition))
		lethalControl.state = "WaveActive"
		local lethalStore = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 100,
		})
		expectError(
			assertions,
			lethalExhausted:recordLeak(issueOutcome(assertions, lethalStore, EnemyFixtures.NORMAL_ENEMY_ID, 110)),
			"REVISION_EXHAUSTED",
			"recordLeak"
		)
		assertions.equal(lethalExhausted:query().currentHealth, 100)
		assertions.equal(lethalExhausted:query().baseRevision, Validation.MAX_SAFE_INTEGER)
		assertions.equal(success(assertions, lethalExhausted:getSnapshot()).status, "Faulted")
	end),

	TestHarness.case("contains hostile data clock dependency and mutation re-entry failures", function(assertions)
		local hostile, hostileControl, hostileDifficulty = newRuntime(assertions, "PreWave", 100, {
			authenticateLeakOutcome = function(_value: unknown)
				return true
			end,
		})
		success(assertions, hostile:initialize(hostileDifficulty.definition))
		hostileControl.state = "WaveActive"
		expectError(
			assertions,
			hostile:recordLeak(table.freeze({
				matchId = BaseFixtures.MATCH_ID,
				enemyEpoch = BaseFixtures.ENEMY_EPOCH,
				runtimeEnemyId = 1,
				enemyId = EnemyFixtures.NORMAL_ENEMY_ID,
				leakDamage = 0 / 0,
				serverTime = math.huge,
			})),
			"INVALID_OUTCOME",
			"recordLeak"
		)
		assertions.equal(hostile:query().state, "Faulted")
		assertions.equal(hostile:query().currentHealth, 100)

		local badClock, _, badClockDifficulty = newRuntime(assertions, "PreWave", 100, {
			clock = function()
				return 0 / 0
			end,
		})
		expectError(assertions, badClock:initialize(badClockDifficulty.definition), "CLOCK_FAILED", "initialize")
		assertions.equal(badClock:query().state, "Faulted")

		local unavailable, unavailableControl, unavailableDifficulty = newRuntime(assertions, "PreWave")
		success(assertions, unavailable:initialize(unavailableDifficulty.definition))
		unavailableControl.state = "WaveActive"
		unavailableControl.snapshotAvailable = false
		local unavailableStore = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 1,
		})
		expectError(
			assertions,
			unavailable:recordLeak(issueOutcome(assertions, unavailableStore, EnemyFixtures.NORMAL_ENEMY_ID, 110)),
			"DEPENDENCY_FAILED",
			"recordLeak"
		)
		assertions.equal(unavailable:query().state, "Faulted")
		assertions.equal(unavailable:query().currentHealth, 100)

		local reentrant: BaseRuntime.Runtime? = nil
		local innerResult: any = nil
		local reentrantRuntime, reentrantControl, reentrantDifficulty = newRuntime(assertions, "PreWave", 100, {
			authenticateLeakOutcome = function(value: unknown)
				innerResult = (reentrant :: BaseRuntime.Runtime):recordLeak(value)
				return EnemyRuntimeStore.isAuthenticatedLeakOutcome(value)
			end,
		})
		reentrant = reentrantRuntime
		success(assertions, reentrantRuntime:initialize(reentrantDifficulty.definition))
		reentrantControl.state = "WaveActive"
		local reentrantStore = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 1,
		})
		success(
			assertions,
			reentrantRuntime:recordLeak(issueOutcome(assertions, reentrantStore, EnemyFixtures.NORMAL_ENEMY_ID, 110))
		)
		expectError(assertions, innerResult, "REENTRANT", "recordLeak")
		assertions.equal(reentrantRuntime:query().currentHealth, 99)
	end),

	TestHarness.case("cleans large ledgers and all retained dependencies idempotently", function(assertions)
		local runtime = newRuntime(assertions)
		local store = newOutcomeStore(assertions, nil, nil, {
			[EnemyFixtures.NORMAL_ENEMY_ID] = 0,
		})
		for index = 1, 128 do
			local outcome = issueOutcome(assertions, store, EnemyFixtures.NORMAL_ENEMY_ID, 10 + index)
			local result = success(assertions, runtime:recordLeak(outcome))
			assertions.equal(result.reason, "Uninitialized")
		end
		assertions.equal(runtime:getMetrics().processedOutcomeCount, 128)
		assertions.isTrue(success(assertions, runtime:cleanup()))
		assertions.isFalse(success(assertions, runtime:cleanup()))
		local metrics = runtime:getMetrics()
		assertions.isTrue(metrics.cleaned)
		assertions.isFalse(metrics.faulted)
		assertions.equal(metrics.processedOutcomeCount, 0)
		assertions.equal(metrics.pendingLeakCount, 0)
		assertions.equal(metrics.pendingAppliedDamage, 0)
		assertions.equal(metrics.lastFinishedEnemyPassOrdinal, 0)
		assertions.isFalse(metrics.retainsBoundaryOutcome)
		assertions.isFalse(metrics.retainsIdentity)
		assertions.isFalse(metrics.retainsCatalog)
		assertions.isFalse(metrics.retainsLifecycle)
		assertions.isFalse(metrics.retainsClock)
		assertions.isFalse(metrics.retainsAuthenticator)
		assertions.isFalse(metrics.retainsMapBinding)
		assertions.isFalse(metrics.retainsPreparedDefeat)
		assertions.isFalse(metrics.retainsResultSeed)
		assertions.isFalse(metrics.busy)
		local cleanedQuery = runtime:query()
		assertions.equal(cleanedQuery.state, "Cleaned")
		assertions.isNil(cleanedQuery.matchId)
		assertions.isNil(cleanedQuery.currentHealth)
		expectError(assertions, runtime:getSnapshot(), "CLEANED", "getSnapshot")
		assertions.isTrue(success(assertions, store.store:cleanup()))
		assertions.isFalse(EnemyRuntimeStore.isAuthenticatedLeakOutcome(store.outcomes[1]))
	end),
})
