--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local BaseFixtures = require(script.Parent.Parent.Fixtures.BaseFixtures)
local EnemyFixtures = require(script.Parent.Parent.Fixtures.EnemyFixtures)
local BaseReplicationPublisher = require(script.Parent.Parent.ProductionServerBase.BaseReplicationPublisher)
local BaseRuntime = require(script.Parent.Parent.ProductionServerBase.BaseRuntime)
local BaseRuntimeService = require(script.Parent.Parent.ProductionServerBase.BaseRuntimeService)
local EnemyReplicationPublisher = require(script.Parent.Parent.ProductionServerEnemies.EnemyReplicationPublisher)
local EnemyRuntimeStore = require(script.Parent.Parent.ProductionServerEnemies.EnemyRuntimeStore)
local EnemySimulationService = require(script.Parent.Parent.ProductionServerEnemies.EnemySimulationService)

local Shared = game:GetService("ReplicatedStorage").Shared
local BaseProtocol = require(Shared.match.BaseProtocol)
local Result = require(Shared.util.Result)

type Assertions = TestHarness.Assertions

local MATCH_ID = BaseFixtures.MATCH_ID
local ENEMY_EPOCH = 1
local ZERO_ID = "enemy:phase10-zero"
local TWENTY_ID = "enemy:phase10-twenty"
local THIRTY_ID = "enemy:phase10-thirty"
local EXACT_ID = "enemy:phase10-exact"
local OVERKILL_ID = "enemy:phase10-overkill"
local MODEL_KEY = "test.phase09.enemy-model"

local newBaseRuntime = BaseRuntime.newForTests
local newBasePublisher = BaseReplicationPublisher.newForTests
local newBaseService = BaseRuntimeService.newForTests
local newEnemyPublisher = EnemyReplicationPublisher.newForTests
local newEnemyService = EnemySimulationService.newForTests

if
	newBaseRuntime == nil
	or newBasePublisher == nil
	or newBaseService == nil
	or newEnemyPublisher == nil
	or newEnemyService == nil
then
	error("Phase 10 integration test constructors unavailable at exact Test location", 0)
end

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected Phase 10 integrated operation to succeed", 0)
	end
	return result.value
end

local function invoke(callback: (() -> ())?)
	if callback == nil then
		error("expected service lifecycle callback", 0)
	end
	(callback :: () -> ())()
end

local function rawEnemy(id: string, leakDamage: number): any
	return {
		id = id,
		displayName = `Phase 10 {id}`,
		modelAssetKey = MODEL_KEY,
		maxHealth = 100,
		moveSpeedStudsPerSecond = 20,
		leakDamage = leakDamage,
		damageIncomeClass = "None",
	}
end

local function createEnemyFixture(): any
	local rawEnemies = {
		rawEnemy(ZERO_ID, 0),
		rawEnemy(TWENTY_ID, 20),
		rawEnemy(THIRTY_ID, 30),
		rawEnemy(EXACT_ID, 50),
		rawEnemy(OVERKILL_ID, 999),
	}
	local authenticated = EnemyFixtures.authenticateCatalog(EnemyFixtures.rawAssets(), rawEnemies)
	return table.freeze({
		catalog = authenticated.catalog,
		rawEnemies = rawEnemies,
	})
end

local function makeLifecycle(mapSnapshot: unknown): (any, any)
	local control: any = {
		state = "ReadyCheck",
		revision = 1,
		beginCount = 0,
		commitCount = 0,
		rollbackCount = 0,
		pendingToken = nil,
	}
	local lifecycle = {}

	function lifecycle.getSnapshot(_self: unknown): unknown
		return Result.ok(table.freeze({
			matchId = MATCH_ID,
			revision = control.revision,
			state = control.state,
			participants = table.freeze({}),
		}))
	end

	function lifecycle.getRuntimeMapSnapshot(_self: unknown): unknown
		return Result.ok(mapSnapshot)
	end

	function lifecycle.beginBaseDefeat(_self: unknown, matchId: unknown): unknown
		if matchId ~= MATCH_ID or control.state ~= "WaveActive" or control.pendingToken ~= nil then
			return Result.err(table.freeze({ code = "INVALID_STATE" }))
		end
		local token = table.freeze({})
		control.pendingToken = token
		control.beginCount += 1
		return Result.ok(token)
	end

	function lifecycle.commitBaseDefeat(_self: unknown, token: unknown): unknown
		if token ~= control.pendingToken or control.state ~= "WaveActive" then
			return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
		end
		control.pendingToken = nil
		control.state = "Results"
		control.revision += 1
		control.commitCount += 1
		local snapshot = table.freeze({
			matchId = MATCH_ID,
			revision = control.revision,
			state = "Results",
			participants = table.freeze({}),
		})
		return Result.ok(table.freeze({
			committed = true,
			published = true,
			snapshot = snapshot,
		}))
	end

	function lifecycle.rollbackBaseDefeat(_self: unknown, token: unknown): unknown
		if token ~= control.pendingToken then
			return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
		end
		control.pendingToken = nil
		control.rollbackCount += 1
		return Result.ok(true)
	end

	function lifecycle.activateStudioWaveForEvidence(_self: unknown): unknown
		return Result.err(table.freeze({ code = "NOT_STUDIO" }))
	end

	return lifecycle, control
end

local function newRig(assertions: Assertions, maximumHealth: number, failedRecipientReadAttempt: number?): any
	local rig: any = {
		clock = { now = 100 },
		baseMessages = {},
		baseSendAttemptCount = 0,
		baseRecipientReadCount = 0,
		leakOutcomes = {},
		stepCallbacks = {},
		connections = {},
	}
	local runtimeMap = EnemyFixtures.createRuntimeMapSnapshot()
	local difficulty = BaseFixtures.createDifficultyFixture(maximumHealth)
	local enemyFixture = createEnemyFixture()
	rig.rawEnemies = enemyFixture.rawEnemies
	rig.lifecycle, rig.lifecycleControl = makeLifecycle(runtimeMap)

	local recipient = table.freeze({ alive = true, userId = 10_001 })
	local recipients = table.freeze({
		table.freeze({ recipient = recipient, userId = 10_001 }),
	})
	local function baseSender(_recipient: unknown, message: unknown): boolean
		rig.baseSendAttemptCount += 1
		table.insert(rig.baseMessages, message)
		return true
	end
	local function getBaseRecipients(): unknown
		rig.baseRecipientReadCount += 1
		if rig.baseRecipientReadCount == failedRecipientReadAttempt then
			return nil
		end
		return recipients
	end

	local function createRuntime(matchId: unknown, enemyEpoch: unknown, catalog: unknown, lifecycle: unknown): unknown
		local created = (newBaseRuntime :: BaseRuntime.TestConstructor)(matchId, enemyEpoch, catalog, lifecycle, {
			clock = function(): number
				return rig.clock.now
			end,
		})
		if created.ok then
			rig.baseRuntime = created.value
		end
		return created
	end
	local function createBasePublisher(matchId: unknown, enemyEpoch: unknown, dependencies: unknown): unknown
		local created = (newBasePublisher :: BaseReplicationPublisher.TestConstructor)(
			matchId,
			enemyEpoch,
			dependencies,
			{
				maxPublications = BaseProtocol.MAX_LIFETIME_PUBLICATIONS,
				recipientValidator = function(recipientValue: unknown, userId: number): boolean
					return recipientValue == recipient and userId == 10_001
				end,
			}
		)
		if created.ok then
			rig.basePublisher = created.value
		end
		return created
	end

	rig.baseService = (newBaseService :: BaseRuntimeService.TestConstructor)({
		matchLifecycle = rig.lifecycle,
		difficultyCatalog = difficulty.catalog,
		createRuntime = createRuntime,
		createPublisher = createBasePublisher,
		sender = baseSender,
		getRecipients = getBaseRecipients,
	})
	rig.baseDefinition = rig.baseService:getServiceDefinition()
	invoke(rig.baseDefinition.initialize)
	invoke(rig.baseDefinition.start)
	local initialized = success(assertions, rig.baseService:initializeBase(difficulty.definition))
	assertions.equal(initialized.currentHealth, maximumHealth)
	assertions.equal(initialized.maximumHealth, maximumHealth)
	assertions.equal(initialized.baseRevision, 1)
	rig.lifecycleControl.state = "WaveActive"
	rig.lifecycleControl.revision = 2

	local baseAdapter = {
		installStudioCatalog = function(_self: unknown, catalog: unknown): unknown
			return rig.baseService:installStudioCatalog(catalog)
		end,
		initializeBase = function(_self: unknown, definition: unknown): unknown
			return rig.baseService:initializeBase(definition)
		end,
		recordLeak = function(_self: unknown, outcome: unknown): unknown
			table.insert(rig.leakOutcomes, outcome)
			return rig.baseService:recordLeak(outcome)
		end,
		finishEnemyPass = function(_self: unknown, passOrdinal: unknown): unknown
			return rig.baseService:finishEnemyPass(passOrdinal)
		end,
		commitPreparedDefeat = function(_self: unknown, token: unknown): unknown
			return rig.baseService:commitPreparedDefeat(token)
		end,
		failPreparedDefeat = function(_self: unknown, token: unknown): unknown
			return rig.baseService:failPreparedDefeat(token)
		end,
		fault = function(_self: unknown): unknown
			return rig.baseService:fault()
		end,
		getSnapshot = function(_self: unknown): unknown
			return rig.baseService:getSnapshot()
		end,
		getResultSeed = function(_self: unknown): unknown
			return rig.baseService:getResultSeed()
		end,
		getDefeatState = function(_self: unknown): unknown
			return rig.baseService:getDefeatState()
		end,
		getMetrics = function(_self: unknown): unknown
			return rig.baseService:getMetrics()
		end,
	}

	local function createStore(matchId: unknown, catalog: unknown, mapSnapshot: unknown, endpointSink: unknown): unknown
		local created = EnemyRuntimeStore.newForTests(matchId, ENEMY_EPOCH, catalog, mapSnapshot, {
			clock = function(): number
				return rig.clock.now
			end,
			endpointSink = endpointSink,
		})
		if created.ok then
			rig.enemyStore = created.value
		end
		return created
	end
	local function createEnemyPublisher(matchId: unknown, enemyEpoch: unknown, dependencies: unknown): unknown
		local created = (newEnemyPublisher :: EnemyReplicationPublisher.TestConstructor)(
			matchId,
			enemyEpoch,
			dependencies,
			nil
		)
		if created.ok then
			rig.enemyPublisher = created.value
		end
		return created
	end
	local function connection(label: string): any
		local value: any = { connected = true }
		value.Disconnect = function(self: any)
			if self.connected then
				self.connected = false
				rig.connections[label] = false
			end
		end
		rig.connections[label] = true
		return value
	end
	local function connectStep(callback: EnemySimulationService.StepCallback): unknown
		table.insert(rig.stepCallbacks, callback)
		return connection("step")
	end
	local function connectPlayerRemoving(_callback: EnemySimulationService.PlayerRemovingCallback): unknown
		return connection("playerRemoving")
	end

	rig.enemyService = (newEnemyService :: EnemySimulationService.TestConstructor)({
		matchLifecycle = rig.lifecycle,
		baseRuntime = baseAdapter,
		catalog = enemyFixture.catalog,
		createStore = createStore,
		createPublisher = createEnemyPublisher,
		connectStep = connectStep,
		connectPlayerRemoving = connectPlayerRemoving,
		sender = function(_recipient: unknown, _message: unknown): boolean
			return true
		end,
		getRecipients = function(): unknown
			return {}
		end,
		passClock = function(): unknown
			return rig.clock.now
		end,
	})
	rig.enemyDefinition = rig.enemyService:getServiceDefinition()
	invoke(rig.enemyDefinition.initialize)
	invoke(rig.enemyDefinition.start)
	return rig
end

local function spawn(assertions: Assertions, rig: any, enemyId: string): any
	return success(assertions, rig.enemyService:spawn(enemyId, EnemyFixtures.STRAIGHT_LANE_ID))
end

local function step(rig: any, deltaSeconds: number)
	rig.clock.now += deltaSeconds
	local callback = rig.stepCallbacks[1]
	if callback == nil then
		error("expected integrated EnemySimulation step callback", 0)
	end
	(callback :: EnemySimulationService.StepCallback)(deltaSeconds)
end

local function assertResidueFree(assertions: Assertions, rig: any)
	invoke(rig.enemyDefinition.shutdown)
	local enemyMetrics = rig.enemyService:getMetrics()
	assertions.equal(enemyMetrics.stepConnectionCount, 0)
	assertions.equal(enemyMetrics.playerRemovingConnectionCount, 0)
	assertions.isFalse(enemyMetrics.retainsStore)
	assertions.isFalse(enemyMetrics.retainsPublisher)
	assertions.isFalse(rig.connections.step)
	assertions.isFalse(rig.connections.playerRemoving)
	local storeMetrics = rig.enemyStore:getMetrics()
	assertions.isTrue(storeMetrics.cleaned)
	assertions.equal(storeMetrics.activeCount, 0)
	assertions.equal(storeMetrics.terminalCount, 0)
	assertions.equal(storeMetrics.retainedLeakOutcomeCount, 0)
	assertions.isFalse(storeMetrics.retainsCatalog)
	assertions.isFalse(storeMetrics.retainsClockCallback)
	assertions.isFalse(storeMetrics.retainsEndpointCallback)
	local enemyPublisherMetrics = rig.enemyPublisher:getMetrics()
	assertions.isTrue(enemyPublisherMetrics.cleaned)
	assertions.equal(enemyPublisherMetrics.activeRepresentationCount, 0)
	assertions.equal(enemyPublisherMetrics.lifetimeRepresentationCount, 0)

	invoke(rig.baseDefinition.shutdown)
	local baseServiceMetrics = rig.baseService:getMetrics()
	assertions.equal(baseServiceMetrics.connectionCount, 0)
	assertions.isFalse(baseServiceMetrics.callbacksEnabled)
	assertions.isFalse(baseServiceMetrics.retainsRuntime)
	assertions.isFalse(baseServiceMetrics.retainsPublisher)
	assertions.isFalse(baseServiceMetrics.retainsCommittedDefeatOutcome)
	local baseMetrics = rig.baseRuntime:getMetrics()
	assertions.isTrue(baseMetrics.cleaned)
	assertions.equal(baseMetrics.processedOutcomeCount, 0)
	assertions.equal(baseMetrics.pendingLeakCount, 0)
	assertions.isFalse(baseMetrics.retainsIdentity)
	assertions.isFalse(baseMetrics.retainsCatalog)
	assertions.isFalse(baseMetrics.retainsLifecycle)
	assertions.isFalse(baseMetrics.retainsClock)
	assertions.isFalse(baseMetrics.retainsAuthenticator)
	assertions.isFalse(baseMetrics.retainsMapBinding)
	assertions.isFalse(baseMetrics.retainsPreparedDefeat)
	assertions.isFalse(baseMetrics.retainsResultSeed)
	local basePublisherMetrics = rig.basePublisher:getMetrics()
	assertions.isTrue(basePublisherMetrics.cleaned)
	assertions.isFalse(basePublisherMetrics.retainsSender)
	assertions.isFalse(basePublisherMetrics.retainsRecipientProvider)
	assertions.isFalse(basePublisherMetrics.retainsTestRecipientValidator)

	invoke(rig.enemyDefinition.shutdown)
	invoke(rig.baseDefinition.shutdown)
end

return TestHarness.suite("Phase 09 endpoint to Phase 10 defeat integration", {
	TestHarness.case(
		"coalesces ordered zero and simultaneous leaks then commits one exact defeat",
		function(assertions)
			local rig = newRig(assertions, 100, nil)
			local zero = spawn(assertions, rig, ZERO_ID)
			local twenty = spawn(assertions, rig, TWENTY_ID)
			local thirty = spawn(assertions, rig, THIRTY_ID)
			step(rig, 1)

			assertions.equal(#rig.leakOutcomes, 3)
			assertions.equal(rig.leakOutcomes[1].runtimeEnemyId, zero.runtimeEnemyId)
			assertions.equal(rig.leakOutcomes[1].leakDamage, 0)
			assertions.equal(rig.leakOutcomes[2].runtimeEnemyId, twenty.runtimeEnemyId)
			assertions.equal(rig.leakOutcomes[2].leakDamage, 20)
			assertions.equal(rig.leakOutcomes[3].runtimeEnemyId, thirty.runtimeEnemyId)
			assertions.equal(rig.leakOutcomes[3].leakDamage, 30)
			for _, outcome in rig.leakOutcomes do
				assertions.isTrue(table.isfrozen(outcome))
				assertions.equal(outcome.matchId, MATCH_ID)
				assertions.equal(outcome.enemyEpoch, ENEMY_EPOCH)
			end

			local active = success(assertions, rig.baseService:getSnapshot())
			assertions.equal(active.status, "Active")
			assertions.equal(active.currentHealth, 50)
			assertions.equal(active.baseRevision, 3)
			assertions.equal(#rig.baseMessages, 2)
			local coalesced = rig.baseMessages[2]
			assertions.equal(coalesced.kind, BaseProtocol.DAMAGE_KIND)
			assertions.equal(coalesced.appliedDamage, 50)
			assertions.equal(coalesced.leakCount, 2)
			assertions.equal(coalesced.snapshot.baseRevision, 3)
			assertions.equal(rig.basePublisher:getMetrics().damageQueueCount, 1)
			assertions.equal(rig.basePublisher:getMetrics().publicationCount, 2)

			local exact = spawn(assertions, rig, EXACT_ID)
			local survivor = spawn(assertions, rig, TWENTY_ID)
			rig.clock.now += 1
			success(assertions, rig.enemyService:resolveEndpoint(exact.runtimeEnemyId))

			local defeated = success(assertions, rig.baseService:getSnapshot())
			assertions.equal(defeated.status, "Defeated")
			assertions.equal(defeated.currentHealth, 0)
			assertions.equal(defeated.maximumHealth, 100)
			assertions.equal(defeated.baseRevision, 5)
			assertions.equal(rig.lifecycleControl.state, "Results")
			assertions.equal(rig.lifecycleControl.beginCount, 1)
			assertions.equal(rig.lifecycleControl.commitCount, 1)
			assertions.equal(rig.lifecycleControl.rollbackCount, 0)
			local serviceMetrics = rig.enemyService:getMetrics()
			assertions.isTrue(serviceMetrics.spawnAdmissionClosed)
			assertions.equal(serviceMetrics.defeatCount, 1)
			assertions.equal(serviceMetrics.resultsCommitCount, 1)
			assertions.equal(
				success(assertions, rig.enemyService:queryTerminal(exact.runtimeEnemyId)).reason,
				"Endpoint"
			)
			assertions.equal(
				success(assertions, rig.enemyService:queryTerminal(survivor.runtimeEnemyId)).reason,
				"Defeat"
			)
			assertions.equal(#rig.leakOutcomes, 4)
			assertions.equal(rig.leakOutcomes[4].enemyId, EXACT_ID)
			assertions.equal(rig.leakOutcomes[4].leakDamage, 50)
			assertions.equal(#rig.baseMessages, 3)
			local terminal = rig.baseMessages[3]
			assertions.equal(terminal.kind, BaseProtocol.DAMAGE_KIND)
			assertions.equal(terminal.appliedDamage, 50)
			assertions.equal(terminal.leakCount, 1)
			assertions.isTrue(terminal.lowHealthCrossed)
			assertions.equal(terminal.snapshot.status, "Defeated")

			local resultSeed = success(assertions, rig.baseService:getResultSeed())
			assertions.isTrue(table.isfrozen(resultSeed))
			assertions.equal(resultSeed.outcome, "Defeat")
			assertions.equal(resultSeed.reason, "BaseHealthDepleted")
			assertions.equal(resultSeed.baseRevision, 5)
			local duplicate = success(assertions, rig.baseService:recordLeak(rig.leakOutcomes[4]))
			assertions.equal(duplicate.kind, "Ignored")
			assertions.equal(duplicate.reason, "Duplicate")
			assertions.equal(success(assertions, rig.baseService:getSnapshot()).baseRevision, 5)
			assertions.isFalse(rig.enemyService:spawn(TWENTY_ID, EnemyFixtures.STRAIGHT_LANE_ID).ok)
			step(rig, 1)
			assertions.equal(#rig.leakOutcomes, 4)
			assertions.equal(rig.baseRuntime:getMetrics().processedOutcomeCount, 4)

			assertResidueFree(assertions, rig)
		end
	),

	TestHarness.case("derives immutable overkill damage and clamps it to one terminal defeat", function(assertions)
		local rig = newRig(assertions, 100, nil)
		-- Mutating the unauthenticated input after validation cannot change the
		-- detached catalog definition consumed by the server-owned store.
		rig.rawEnemies[5].leakDamage = 1
		local overkill = spawn(assertions, rig, OVERKILL_ID)
		local survivor = spawn(assertions, rig, ZERO_ID)
		rig.clock.now += 1
		success(assertions, rig.enemyService:resolveEndpoint(overkill.runtimeEnemyId))

		assertions.equal(#rig.leakOutcomes, 1)
		local outcome = rig.leakOutcomes[1]
		assertions.equal(outcome.enemyId, OVERKILL_ID)
		assertions.equal(outcome.leakDamage, 999)
		assertions.isTrue(EnemyRuntimeStore.isAuthenticatedLeakOutcome(outcome))
		local defeated = success(assertions, rig.baseService:getSnapshot())
		assertions.equal(defeated.currentHealth, 0)
		assertions.equal(defeated.maximumHealth, 100)
		assertions.equal(defeated.baseRevision, 3)
		assertions.equal(rig.lifecycleControl.commitCount, 1)
		assertions.equal(success(assertions, rig.enemyService:queryTerminal(survivor.runtimeEnemyId)).reason, "Defeat")
		assertions.equal(#rig.baseMessages, 2)
		local terminal = rig.baseMessages[2]
		assertions.equal(terminal.kind, BaseProtocol.DAMAGE_KIND)
		assertions.equal(terminal.appliedDamage, 100)
		assertions.equal(terminal.leakCount, 1)
		assertions.equal(terminal.snapshot.currentHealth, 0)

		local duplicate = success(assertions, rig.baseService:recordLeak(outcome))
		assertions.equal(duplicate.reason, "Duplicate")
		step(rig, 1)
		assertions.equal(#rig.leakOutcomes, 1)
		assertions.equal(success(assertions, rig.baseService:getSnapshot()).baseRevision, 3)
		assertions.equal(rig.enemyService:getMetrics().defeatCount, 1)
		assertions.equal(rig.enemyService:getMetrics().resultsCommitCount, 1)

		assertResidueFree(assertions, rig)
	end),

	TestHarness.case("keeps the Defeated seed after terminal publication failure", function(assertions)
		local rig = newRig(assertions, 100, 2)
		local overkill = spawn(assertions, rig, OVERKILL_ID)
		rig.clock.now += 1
		success(assertions, rig.enemyService:resolveEndpoint(overkill.runtimeEnemyId))

		assertions.equal(rig.lifecycleControl.state, "Results")
		assertions.equal(rig.lifecycleControl.commitCount, 1)
		assertions.equal(rig.baseRecipientReadCount, 2)
		assertions.equal(rig.baseSendAttemptCount, 1)
		assertions.equal(rig.baseService:getLifecycleState(), "Failed")
		local snapshot = success(assertions, rig.baseService:getSnapshot())
		assertions.equal(snapshot.status, "Defeated")
		assertions.equal(snapshot.currentHealth, 0)
		local resultSeed = success(assertions, rig.baseService:getResultSeed())
		assertions.equal(resultSeed.outcome, "Defeat")
		assertions.equal(resultSeed.reason, "BaseHealthDepleted")
		assertions.equal(resultSeed.baseRevision, snapshot.baseRevision)
		assertions.isTrue(rig.enemyService:getMetrics().spawnAdmissionClosed)
		assertions.equal(rig.enemyService:getMetrics().resultsCommitCount, 1)
		assertions.isFalse(rig.enemyService:spawn(TWENTY_ID, EnemyFixtures.STRAIGHT_LANE_ID).ok)

		assertResidueFree(assertions, rig)
	end),
})
