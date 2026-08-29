--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local WaveFixtures = require(script.Parent.Parent.Fixtures.WaveFixtures)

local Shared = game:GetService("ReplicatedStorage").Shared
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local BaseProtocol = require(Shared.match.BaseProtocol)
local MatchProtocol = require(Shared.match.MatchProtocol)
local WaveProtocol = require(Shared.match.WaveProtocol)
local Result = require(Shared.util.Result)

local WaveReplicationPublisher = require(script.Parent.Parent.ProductionServerWaves.WaveReplicationPublisher)
local WaveRuntime = require(script.Parent.Parent.ProductionServerWaves.WaveRuntime)
local WaveRuntimeService = require(script.Parent.Parent.ProductionServerWaves.WaveRuntimeService)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase11-wave-service-spec"
local OTHER_MATCH_ID = "match:phase11-wave-service-other"
local ENEMY_EPOCH = 7
local GENERATION = 11
local fixture = WaveFixtures.createAuthenticatedFixture()
local newForTests = WaveRuntimeService.newForTests
local publisherNewForTests = WaveReplicationPublisher.newForTests

if newForTests == nil then
	error("WaveRuntimeService test constructor unavailable at exact Test location", 0)
end
if publisherNewForTests == nil then
	error("WaveReplicationPublisher test constructor unavailable at exact Test location", 0)
end

type Environment = {
	now: number,
	lifecycleState: string,
	lifecycleRevision: number,
	matchId: string,
	enemyIdentity: any,
	statusEpoch: number,
	identityMode: string,
	installMode: string,
	prepareMode: string,
	commitBindingMode: string,
	detachMode: string,
	createMode: string,
	stepMode: string,
	stepHook: (() -> ())?,
	runtimeStepCalls: number,
	spawnMode: string,
	order: { string },
	boundary: any?,
	handle: any,
	bindingToken: any,
	activationToken: any,
	boundaryStatus: string,
	difficultyId: string?,
	baseDifficulty: any?,
	boundConfiguration: any?,
	boundDifficulty: any?,
	nextRuntimeEnemyId: number,
	spawnEvents: { any },
	runtimeCleanupCount: number,
	runtimeCleanupMode: string,
	detachCount: number,
	createDependencies: any?,
	recipients: { any },
	recipientMode: string,
	recipientCalls: number,
	waveSends: { any },
	senderMode: string,
	publisherFactoryMode: string,
	publisherPreflightMode: string,
	publisherPreflightCalls: number,
	publisherQueueMode: string,
	publisherQueueCalls: number,
	publisherFlushMode: string,
	publisherFlushHook: (() -> ())?,
	publisherFlushCalls: number,
	publisherCleanupCount: number,
	publisherCleanupMode: string,
	publisherCreateIdentity: any?,
	publisherDependencies: any?,
	voteMode: string,
	voteCalls: number,
	voteRevision: number,
	voteSnapshot: any?,
	voteArguments: any?,
	voteHook: any?,
	reentryResult: any?,
	isStudio: boolean,
	studioCheckMode: string,
	triggerCreateMode: string,
	triggerCreateCalls: number,
	triggerHandler: any?,
	triggerDestroyCount: number,
	validationMode: string,
	validationCount: number,
	validationCompleted: boolean,
	validationHook: any?,
	validationSources: any?,
	readySubmissionCalls: number,
	readySubmissionMode: string,
	durationNow: number,
	baseCatalogInstallMode: string,
	baseCatalogInstallCalls: number,
	baseCatalog: any?,
	baseSnapshot: any?,
	activeEnemies: { any },
	despawnCalls: number,
	legacyTriggerRevoked: boolean,
}

local function expectSuccess(assertions: Assertions, resultValue: any): any
	assertions.isTrue(resultValue.ok)
	if not resultValue.ok then
		error("[ATD_TEST][code=WAVE_RUNTIME_SERVICE_EXPECTED_SUCCESS]", 0)
	end
	return resultValue.value
end

local function expectError(assertions: Assertions, resultValue: any, code: string, operation: string)
	assertions.isFalse(resultValue.ok)
	if resultValue.ok then
		error("[ATD_TEST][code=WAVE_RUNTIME_SERVICE_EXPECTED_ERROR]", 0)
	end
	assertions.equal(resultValue.error.code, code)
	assertions.equal(resultValue.error.operation, operation)
end

local function matchSnapshot(environment: Environment): any
	local validated = MatchProtocol.validateMatchSnapshot({
		matchId = environment.matchId,
		revision = environment.lifecycleRevision,
		state = environment.lifecycleState,
		deadlineServerTime = if environment.lifecycleState == "ReadyCheck" then environment.now + 30 else nil,
		participants = {},
	})
	if not validated.ok then
		error("[ATD_TEST][code=WAVE_RUNTIME_SERVICE_MATCH_SNAPSHOT_INVALID]", 0)
	end
	return validated.value
end

local function newEnvironment(): Environment
	return {
		now = 100,
		lifecycleState = "PreWave",
		lifecycleRevision = 3,
		matchId = MATCH_ID,
		enemyIdentity = table.freeze({
			matchId = MATCH_ID,
			enemyEpoch = ENEMY_EPOCH,
		}),
		statusEpoch = ENEMY_EPOCH,
		identityMode = "success",
		installMode = "success",
		prepareMode = "success",
		commitBindingMode = "success",
		detachMode = "success",
		createMode = "success",
		stepMode = "success",
		stepHook = nil,
		runtimeStepCalls = 0,
		spawnMode = "success",
		order = {},
		boundary = nil,
		handle = table.freeze({ kind = "WaveBoundaryHandle" }),
		bindingToken = table.freeze({ kind = "WaveBindingToken" }),
		activationToken = table.freeze({ kind = "WaveActivationToken" }),
		boundaryStatus = "Absent",
		difficultyId = nil,
		baseDifficulty = nil,
		boundConfiguration = nil,
		boundDifficulty = nil,
		nextRuntimeEnemyId = 1,
		spawnEvents = {},
		runtimeCleanupCount = 0,
		runtimeCleanupMode = "success",
		detachCount = 0,
		createDependencies = nil,
		recipients = {},
		recipientMode = "success",
		recipientCalls = 0,
		waveSends = {},
		senderMode = "success",
		publisherFactoryMode = "success",
		publisherPreflightMode = "success",
		publisherPreflightCalls = 0,
		publisherQueueMode = "success",
		publisherQueueCalls = 0,
		publisherFlushMode = "success",
		publisherFlushHook = nil,
		publisherFlushCalls = 0,
		publisherCleanupCount = 0,
		publisherCleanupMode = "success",
		publisherCreateIdentity = nil,
		publisherDependencies = nil,
		voteMode = "success",
		voteCalls = 0,
		voteRevision = 1,
		voteSnapshot = nil,
		voteArguments = nil,
		voteHook = nil,
		reentryResult = nil,
		isStudio = false,
		studioCheckMode = "success",
		triggerCreateMode = "success",
		triggerCreateCalls = 0,
		triggerHandler = nil,
		triggerDestroyCount = 0,
		validationMode = "success",
		validationCount = 0,
		validationCompleted = false,
		validationHook = nil,
		validationSources = nil,
		readySubmissionCalls = 0,
		readySubmissionMode = "success",
		durationNow = 0,
		baseCatalogInstallMode = "success",
		baseCatalogInstallCalls = 0,
		baseCatalog = nil,
		baseSnapshot = nil,
		activeEnemies = {},
		despawnCalls = 0,
		legacyTriggerRevoked = false,
	}
end

local function boundaryStatus(environment: Environment): any
	if environment.boundaryStatus == "Installed" then
		return table.freeze({
			matchId = MATCH_ID,
			enemyEpoch = environment.statusEpoch,
			generation = GENERATION,
			status = "Installed",
		})
	end
	return table.freeze({
		matchId = MATCH_ID,
		enemyEpoch = environment.statusEpoch,
		generation = GENERATION,
		status = environment.boundaryStatus,
		difficultyId = environment.difficultyId,
	})
end

local function makeRecipient(userId: number): (any, any)
	local token = {
		userId = userId,
		alive = true,
	}
	return token, table.freeze({
		recipient = token,
		userId = userId,
	})
end

local function makeVoteSnapshot(environment: Environment, runtime: any): any
	local currentResult = runtime:getSnapshot()
	if not currentResult.ok then
		error("[ATD_TEST][code=WAVE_RUNTIME_SERVICE_VOTE_SNAPSHOT_UNAVAILABLE]", 0)
	end
	local current = currentResult.value
	environment.voteRevision += if environment.voteMode == "jump-success"
			or environment.stepMode == "revision-jump"
		then 2
		else 1
	local yesVoteCount = math.min(environment.voteRevision - 1, 2)
	local validated = WaveProtocol.validateWaveSnapshot({
		matchId = current.matchId,
		enemyEpoch = current.enemyEpoch,
		mapId = current.mapId,
		difficultyId = current.difficultyId,
		state = current.state,
		waveRevision = environment.voteRevision,
		currentWaveNumber = current.currentWaveNumber,
		totalWaves = current.totalWaves,
		currentWaveId = current.currentWaveId,
		bossKind = current.bossKind,
		timerPhase = current.timerPhase,
		waveStartedServerTime = current.waveStartedServerTime,
		deadlineServerTime = current.deadlineServerTime,
		intermissionEndsServerTime = current.intermissionEndsServerTime,
		skipAvailableServerTime = current.skipAvailableServerTime,
		finiteCompleteServerTime = current.finiteCompleteServerTime,
		currentCounts = current.currentCounts,
		aggregateCounts = current.aggregateCounts,
		skipState = {
			available = true,
			activeParticipantCount = 3,
			yesVoteCount = yesVoteCount,
			requiredVoteCount = 2,
			quorumPending = yesVoteCount >= 2,
		},
	})
	if not validated.ok then
		error("[ATD_TEST][code=WAVE_RUNTIME_SERVICE_VOTE_SNAPSHOT_INVALID]", 0)
	end
	environment.voteSnapshot = validated.value
	return validated.value
end

local function makeTerminalVoteFailureSnapshot(environment: Environment, runtime: any, state: string): any
	local currentResult = runtime:getSnapshot()
	if not currentResult.ok then
		error("[ATD_TEST][code=WAVE_RUNTIME_SERVICE_TERMINAL_VOTE_SNAPSHOT_UNAVAILABLE]", 0)
	end
	local current = currentResult.value
	environment.voteRevision += 1
	local validated = WaveProtocol.validateWaveSnapshot({
		matchId = current.matchId,
		enemyEpoch = current.enemyEpoch,
		mapId = current.mapId,
		difficultyId = current.difficultyId,
		state = state,
		waveRevision = environment.voteRevision,
		currentWaveNumber = current.currentWaveNumber,
		totalWaves = current.totalWaves,
		currentWaveId = current.currentWaveId,
		bossKind = current.bossKind,
		timerPhase = "None",
		waveStartedServerTime = current.waveStartedServerTime,
		deadlineServerTime = current.deadlineServerTime,
		intermissionEndsServerTime = 0,
		skipAvailableServerTime = 0,
		finiteCompleteServerTime = 0,
		currentCounts = current.currentCounts,
		aggregateCounts = current.aggregateCounts,
		skipState = {
			available = false,
			activeParticipantCount = 0,
			yesVoteCount = 0,
			requiredVoteCount = 0,
			quorumPending = false,
		},
	})
	if not validated.ok then
		error("[ATD_TEST][code=WAVE_RUNTIME_SERVICE_TERMINAL_VOTE_SNAPSHOT_INVALID]", 0)
	end
	environment.voteSnapshot = validated.value
	return validated.value
end

local function wrapRuntime(environment: Environment, runtime: any): any
	local wrapper = {}
	function wrapper.initialize(_self: any): unknown
		return runtime:initialize()
	end
	function wrapper.step(_self: any, frame: unknown): unknown
		environment.runtimeStepCalls += 1
		if environment.stepHook ~= nil then
			environment.stepHook()
		end
		if environment.stepMode == "failure" then
			return Result.err(table.freeze({ code = "PRIVATE_STEP_FAILURE" }))
		elseif environment.stepMode == "faulted" then
			if environment.voteSnapshot == nil then
				makeTerminalVoteFailureSnapshot(environment, runtime, "Faulted")
			end
			return Result.ok(environment.voteSnapshot)
		elseif environment.stepMode == "revision-jump" then
			if environment.voteSnapshot == nil then
				makeVoteSnapshot(environment, runtime)
			end
			return Result.ok(environment.voteSnapshot)
		end
		if environment.voteSnapshot ~= nil then
			return Result.ok(environment.voteSnapshot)
		end
		return runtime:step(frame)
	end
	function wrapper.closeDependencyFault(_self: any, context: unknown): unknown
		if environment.voteSnapshot ~= nil and environment.voteSnapshot.state == "Faulted" then
			return Result.ok(environment.voteSnapshot)
		end
		return runtime:closeDependencyFault(context)
	end
	function wrapper.getSnapshot(_self: any): unknown
		if environment.voteSnapshot ~= nil then
			return Result.ok(environment.voteSnapshot)
		end
		return runtime:getSnapshot()
	end
	function wrapper.getStartingCashPlaceholder(_self: any): unknown
		return runtime:getStartingCashPlaceholder()
	end
	function wrapper.getCompletionState(_self: any): unknown
		return runtime:getCompletionState()
	end
	function wrapper.query(_self: any): unknown
		return runtime:query()
	end
	function wrapper.submitSkipVote(_self: any, userId: unknown, matchId: unknown, waveNumber: unknown): unknown
		environment.voteCalls += 1
		environment.voteArguments = table.freeze({
			userId = userId,
			matchId = matchId,
			waveNumber = waveNumber,
		})
		table.insert(environment.order, "runtimeVote")
		if matchId ~= MATCH_ID then
			return Result.err(table.freeze({
				code = "STALE_REQUEST",
				operation = "submitSkipVote",
			}))
		elseif environment.voteHook ~= nil then
			return environment.voteHook(runtime, userId, matchId, waveNumber)
		elseif environment.voteMode == "failure" then
			return Result.err(table.freeze({
				code = "UNAVAILABLE",
				operation = "submitSkipVote",
			}))
		elseif environment.voteMode == "running-failure-jump" then
			makeVoteSnapshot(environment, runtime)
			return Result.err(table.freeze({
				code = "UNAVAILABLE",
				operation = "submitSkipVote",
			}))
		elseif environment.voteMode == "defeat-failure" or environment.voteMode == "fault-failure" then
			makeTerminalVoteFailureSnapshot(
				environment,
				runtime,
				if environment.voteMode == "defeat-failure" then "DefeatClosed" else "Faulted"
			)
			return Result.err(table.freeze({
				code = "UNAVAILABLE",
				operation = "submitSkipVote",
			}))
		elseif environment.voteMode == "throw" then
			error("PRIVATE_VOTE_FAILURE", 0)
		elseif environment.voteMode == "yield" then
			coroutine.yield()
		elseif environment.voteMode == "malformed" then
			return Result.ok(table.freeze({ malformed = true }))
		elseif environment.voteMode == "arbitrary-error" then
			return Result.err(table.freeze({
				code = "PRIVATE_FAILURE",
				operation = "submitSkipVote",
			}))
		end
		return Result.ok(makeVoteSnapshot(environment, runtime))
	end
	function wrapper.cleanup(_self: any): unknown
		table.insert(environment.order, "runtimeCleanup")
		environment.runtimeCleanupCount += 1
		if environment.runtimeCleanupMode == "false" then
			return Result.ok(false)
		end
		return runtime:cleanup()
	end
	return wrapper
end

local function wrapPublisher(environment: Environment, publisher: any): any
	local wrapper = {}
	function wrapper.preflightPublication(_self: any): unknown
		environment.publisherPreflightCalls += 1
		if environment.publisherPreflightMode == "false" then
			return Result.ok(false)
		end
		return publisher:preflightPublication()
	end
	function wrapper.queueSnapshot(_self: any, snapshotValue: unknown): unknown
		environment.publisherQueueCalls += 1
		table.insert(environment.order, `publisherQueue:{tostring((snapshotValue :: any).waveRevision)}`)
		if environment.publisherQueueMode == "failure" and environment.publisherQueueCalls > 1 then
			return Result.err(table.freeze({ code = "PRIVATE_QUEUE_FAILURE" }))
		end
		return publisher:queueSnapshot(snapshotValue)
	end
	function wrapper.flush(_self: any, passOrdinal: unknown): unknown
		environment.publisherFlushCalls += 1
		table.insert(environment.order, `publisherFlush:{tostring(passOrdinal)}`)
		if environment.publisherFlushHook ~= nil then
			environment.publisherFlushHook()
		end
		if environment.publisherFlushMode == "failure" then
			return Result.err(table.freeze({ code = "PRIVATE_FLUSH_FAILURE" }))
		end
		return publisher:flush(passOrdinal)
	end
	function wrapper.getMetrics(_self: any): unknown
		return publisher:getMetrics()
	end
	function wrapper.cleanup(_self: any): unknown
		table.insert(environment.order, "publisherCleanup")
		environment.publisherCleanupCount += 1
		if environment.publisherCleanupMode == "false" then
			return Result.ok(false)
		end
		return publisher:cleanup()
	end
	return table.freeze(wrapper)
end

local function dependenciesFor(environment: Environment, selection: WaveRuntimeService.Selection): any
	local lifecycle = {}
	function lifecycle.getSnapshot(_self: any): unknown
		table.insert(environment.order, "lifecycleSnapshot")
		return Result.ok(matchSnapshot(environment))
	end
	function lifecycle.getRuntimeMapSnapshot(_self: any): unknown
		table.insert(environment.order, "runtimeMap")
		return Result.ok(fixture.runtimeMap)
	end
	function lifecycle.getConnectedRecipients(_self: any): unknown
		table.insert(environment.order, "connectedRecipients")
		environment.recipientCalls += 1
		if environment.recipientMode == "failure" then
			return Result.err(table.freeze({ code = "PRIVATE_RECIPIENT_FAILURE" }))
		elseif environment.recipientMode == "malformed" then
			return Result.ok({
				[1] = environment.recipients[1],
				extra = true,
			})
		end
		return Result.ok(environment.recipients)
	end
	function lifecycle.getCommittedBaseDefeatRecipients(_self: any): unknown
		table.insert(environment.order, "committedBaseDefeatRecipients")
		if environment.recipientMode == "committed-throw" then
			error("PRIVATE_COMMITTED_RECIPIENT_FAILURE", 0)
		elseif environment.recipientMode == "committed-malformed" then
			return Result.ok({ malformed = true })
		elseif environment.recipientMode ~= "committed-defeat" then
			return Result.err(table.freeze({ code = "UNAVAILABLE" }))
		end
		return Result.ok(environment.recipients)
	end
	function lifecycle.submitReady(
		_self: any,
		connection: unknown,
		matchId: unknown,
		observedRevision: unknown
	): unknown
		environment.readySubmissionCalls += 1
		table.insert(environment.order, `submitReady:{tostring((connection :: any).userId)}`)
		local before = matchSnapshot(environment)
		if
			not environment.validationCompleted
			or environment.lifecycleState ~= "ReadyCheck"
			or matchId ~= environment.matchId
			or observedRevision ~= before.revision
			or type(connection) ~= "table"
			or (connection :: any).alive ~= true
		then
			return Result.err(table.freeze({ code = "PRIVATE_READY_FAILURE" }))
		elseif environment.readySubmissionMode == "failure" then
			return Result.err(table.freeze({ code = "PRIVATE_READY_FAILURE" }))
		elseif environment.readySubmissionMode == "malformed" then
			return Result.ok(table.freeze({ malformed = true }))
		end
		environment.lifecycleRevision += 1
		if environment.readySubmissionCalls >= #environment.recipients then
			environment.lifecycleState = "PreWave"
		end
		return Result.ok(matchSnapshot(environment))
	end
	function lifecycle.isRuntimeMapSnapshot(_self: any, value: unknown): unknown
		return value == fixture.runtimeMap
	end
	function lifecycle.beginWaveActivation(_self: any, matchId: unknown): unknown
		table.insert(environment.order, "beginActivation")
		if matchId ~= MATCH_ID then
			return Result.err(table.freeze({ code = "PRIVATE_FAILURE" }))
		end
		return Result.ok(environment.activationToken)
	end
	function lifecycle.commitWaveActivation(_self: any, token: unknown): unknown
		table.insert(environment.order, "commitActivation")
		if token ~= environment.activationToken then
			return Result.err(table.freeze({ code = "PRIVATE_FAILURE" }))
		end
		environment.lifecycleState = "WaveActive"
		environment.lifecycleRevision += 1
		return Result.ok(table.freeze({
			committed = true,
			published = true,
			snapshot = matchSnapshot(environment),
		}))
	end
	function lifecycle.rollbackWaveActivation(_self: any, _token: unknown): unknown
		table.insert(environment.order, "rollbackActivation")
		return Result.ok(true)
	end

	local base = {}
	function base.installStudioCatalog(_self: any, catalog: unknown): unknown
		table.insert(environment.order, "installBaseStudioCatalog")
		environment.baseCatalogInstallCalls += 1
		if environment.baseCatalogInstallMode == "throw" then
			error("PRIVATE_BASE_CATALOG_FAILURE", 0)
		elseif environment.baseCatalogInstallMode == "yield" then
			coroutine.yield()
		elseif environment.baseCatalogInstallMode == "failure" then
			return Result.err(table.freeze({ code = "PRIVATE_FAILURE" }))
		elseif environment.baseCatalogInstallMode == "false" then
			return Result.ok(false)
		end
		environment.baseCatalog = catalog
		return Result.ok(true)
	end
	function base.initializeBase(_self: any, definition: unknown): unknown
		table.insert(environment.order, "initializeBase")
		environment.baseDifficulty = definition
		local difficulty = definition :: any
		local validated = BaseProtocol.validateBaseSnapshot({
			matchId = MATCH_ID,
			enemyEpoch = ENEMY_EPOCH,
			mapId = fixture.runtimeMap.mapId,
			difficultyId = difficulty.id,
			basePosition = fixture.runtimeMap.base.position,
			baseRevision = 1,
			status = "Active",
			currentHealth = difficulty.base.maxHealth,
			maximumHealth = difficulty.base.maxHealth,
			lowHealth = false,
			initializedServerTime = environment.now,
			updatedServerTime = environment.now,
		})
		if not validated.ok then
			return Result.err(table.freeze({ code = "PRIVATE_BASE_SNAPSHOT_INVALID" }))
		end
		environment.baseSnapshot = validated.value
		return Result.ok(true)
	end
	function base.getDefeatState(_self: any): unknown
		return table.freeze({
			defeatPending = false,
			defeated = false,
		})
	end
	function base.getSnapshot(_self: any): unknown
		if environment.baseSnapshot == nil then
			return Result.err(table.freeze({ code = "PRIVATE_UNAVAILABLE" }))
		end
		return Result.ok(environment.baseSnapshot)
	end
	function base.getMetrics(_self: any): unknown
		return table.freeze({
			lifecycleState = "Started",
			connectionCount = 0,
			publisher = table.freeze({ publicationCount = 0 }),
		})
	end

	local enemy = {}
	function enemy.getIdentity(_self: any): unknown
		table.insert(environment.order, "enemyIdentity")
		if environment.identityMode == "failure" then
			return Result.err(table.freeze({ code = "PRIVATE_FAILURE" }))
		elseif environment.identityMode == "malformed-result" then
			return table.freeze({ malformed = true })
		end
		return Result.ok(environment.enemyIdentity)
	end
	function enemy.installWaveBoundary(_self: any, adapter: unknown): unknown
		table.insert(environment.order, "installBoundary")
		if environment.installMode == "failure" then
			return Result.err(table.freeze({ code = "PRIVATE_FAILURE" }))
		end
		environment.boundary = adapter
		environment.boundaryStatus = "Installed"
		return Result.ok(environment.handle)
	end
	function enemy.prepareWaveBinding(_self: any, handle: unknown, configuration: unknown, difficulty: unknown): unknown
		table.insert(environment.order, "prepareBinding")
		if environment.prepareMode == "failure" or handle ~= environment.handle then
			return Result.err(table.freeze({ code = "PRIVATE_FAILURE" }))
		end
		environment.boundConfiguration = configuration
		environment.boundDifficulty = difficulty
		return Result.ok(environment.bindingToken)
	end
	function enemy.commitWaveBinding(_self: any, token: unknown): unknown
		table.insert(environment.order, "commitBinding")
		if environment.commitBindingMode == "failure" or token ~= environment.bindingToken then
			return Result.err(table.freeze({ code = "PRIVATE_FAILURE" }))
		end
		environment.legacyTriggerRevoked = true
		environment.boundaryStatus = "Active"
		environment.difficultyId = (environment.boundDifficulty :: any).id
		return Result.ok(boundaryStatus(environment))
	end
	function enemy.detachWaveBoundary(_self: any, handle: unknown): unknown
		table.insert(environment.order, "detachBoundary")
		environment.detachCount += 1
		if environment.detachMode == "failure" or handle ~= environment.handle then
			return Result.err(table.freeze({ code = "PRIVATE_FAILURE" }))
		elseif environment.detachMode == "false" then
			return Result.ok(false)
		end
		environment.boundaryStatus = "Detached"
		environment.boundary = nil
		return Result.ok(true)
	end
	function enemy.getWaveBoundaryStatus(_self: any, handle: unknown): unknown
		table.insert(environment.order, "boundaryStatus")
		if handle ~= environment.handle then
			return Result.err(table.freeze({ code = "PRIVATE_FAILURE" }))
		end
		return Result.ok(boundaryStatus(environment))
	end
	function enemy.isAuthenticatedTerminalOutcome(_self: any, handle: unknown, _outcome: unknown): unknown
		return handle == environment.handle
	end
	function enemy.list(_self: any): unknown
		return Result.ok(table.freeze(table.clone(environment.activeEnemies)))
	end
	function enemy.despawn(_self: any, runtimeEnemyId: unknown): unknown
		environment.despawnCalls += 1
		for index, snapshot in environment.activeEnemies do
			if snapshot.runtimeEnemyId == runtimeEnemyId then
				table.remove(environment.activeEnemies, index)
				return Result.ok(snapshot)
			end
		end
		return Result.err(table.freeze({ code = "PRIVATE_NOT_FOUND" }))
	end
	function enemy.getMetrics(_self: any): unknown
		return table.freeze({
			lifecycleState = "Started",
			stepConnectionCount = 1,
			playerRemovingConnectionCount = 1,
			publisher = table.freeze({
				deltaMessageCount = 0,
				snapshotMessageCount = 0,
			}),
		})
	end

	return {
		matchLifecycle = lifecycle,
		baseRuntime = base,
		enemySimulation = enemy,
		configuration = fixture.configuration,
		selection = selection,
		clock = function(): unknown
			table.insert(environment.order, "clock")
			return environment.now
		end,
		createRuntime = function(
			configuration: unknown,
			runtimeMap: unknown,
			matchId: unknown,
			enemyEpoch: unknown,
			difficultyId: unknown,
			dependencies: unknown
		): unknown
			table.insert(environment.order, "createRuntime")
			environment.createDependencies = dependencies
			if environment.createMode == "failure" then
				return Result.err(table.freeze({ code = "PRIVATE_FAILURE" }))
			elseif environment.createMode == "malformed" then
				return Result.ok(table.freeze({ malformed = true }))
			end
			local resultValue =
				WaveRuntime.new(configuration, runtimeMap, matchId, enemyEpoch, difficultyId, dependencies)
			if not resultValue.ok then
				return resultValue
			end
			return Result.ok(wrapRuntime(environment, resultValue.value))
		end,
		createPublisher = function(
			matchId: unknown,
			enemyEpoch: unknown,
			mapId: unknown,
			difficultyId: unknown,
			totalWaves: unknown,
			dependencies: unknown
		): unknown
			table.insert(environment.order, "createPublisher")
			environment.publisherCreateIdentity = table.freeze({
				matchId = matchId,
				enemyEpoch = enemyEpoch,
				mapId = mapId,
				difficultyId = difficultyId,
				totalWaves = totalWaves,
			})
			environment.publisherDependencies = dependencies
			if environment.publisherFactoryMode == "failure" then
				return Result.err(table.freeze({ code = "PRIVATE_PUBLISHER_FAILURE" }))
			elseif environment.publisherFactoryMode == "malformed" then
				return Result.ok(table.freeze({ malformed = true }))
			end
			local created = (publisherNewForTests :: any)(
				matchId,
				enemyEpoch,
				mapId,
				difficultyId,
				totalWaves,
				dependencies,
				{
					maxPublications = WaveReplicationPublisher.MAX_PUBLICATIONS,
					recipientValidator = function(recipientValue: unknown, userId: number): boolean
						return type(recipientValue) == "table"
							and (recipientValue :: any).alive == true
							and (recipientValue :: any).userId == userId
					end,
				}
			)
			if not created.ok then
				return created
			end
			return Result.ok(wrapPublisher(environment, created.value))
		end,
		sender = function(recipientValue: Player, snapshotValue: any): boolean
			table.insert(environment.order, `waveSender:{snapshotValue.waveRevision}`)
			table.insert(environment.waveSends, {
				recipient = recipientValue,
				snapshot = snapshotValue,
			})
			if environment.senderMode == "throw" then
				error("PRIVATE_WAVE_SEND_FAILURE", 0)
			elseif environment.senderMode == "false" then
				return false
			end
			return true
		end,
		isStudio = function(): unknown
			if environment.studioCheckMode == "throw" then
				error("PRIVATE_STUDIO_CHECK_FAILURE", 0)
			elseif environment.studioCheckMode == "yield" then
				coroutine.yield()
			elseif environment.studioCheckMode == "malformed" then
				return "yes"
			end
			return environment.isStudio
		end,
		createRuntimeTrigger = function(handler: any): unknown
			environment.triggerCreateCalls += 1
			if environment.triggerCreateMode == "throw" then
				error("PRIVATE_TRIGGER_CREATION_FAILURE", 0)
			elseif environment.triggerCreateMode == "yield" then
				coroutine.yield()
			elseif environment.triggerCreateMode == "malformed" then
				return table.freeze({ malformed = true })
			elseif environment.triggerCreateMode == "collision" then
				return nil
			end
			environment.triggerHandler = handler
			local trigger = {}
			function trigger.Destroy(_self: any)
				table.insert(environment.order, "destroyStudioTrigger")
				environment.triggerDestroyCount += 1
				environment.triggerHandler = nil
			end
			return trigger
		end,
		validateConfiguration = function(sources: unknown): unknown
			table.insert(environment.order, "validateConfiguration")
			environment.validationCount += 1
			environment.validationSources = sources
			if environment.validationHook ~= nil then
				environment.validationHook()
			end
			if environment.validationMode == "throw" then
				error("PRIVATE_VALIDATION_FAILURE", 0)
			elseif environment.validationMode == "yield" then
				coroutine.yield()
			elseif environment.validationMode == "failure" then
				return Result.err(table.freeze({ code = "PRIVATE_FAILURE" }))
			elseif environment.validationMode == "malformed" then
				return Result.ok(table.freeze({ malformed = true }))
			end
			local resultValue = ConfigurationValidator.validate(sources)
			environment.validationCompleted = resultValue.ok
			return resultValue
		end,
		durationClock = function(): unknown
			environment.durationNow += 0.001
			return environment.durationNow
		end,
	}
end

local function configuredSelection(): WaveRuntimeService.Selection
	return table.freeze({
		kind = "AuthoredFinite",
		difficultyId = WaveFixtures.PRIMARY_DIFFICULTY_ID,
	})
end

local function dormantSelection(): WaveRuntimeService.Selection
	return table.freeze({
		kind = "Dormant",
	})
end

local function createService(
	environment: Environment,
	selection: WaveRuntimeService.Selection
): WaveRuntimeService.Service
	return (newForTests :: WaveRuntimeService.TestConstructor)(dependenciesFor(environment, selection))
end

local function initializeService(service: WaveRuntimeService.Service)
	service:getServiceDefinition().initialize()
end

local function startService(service: WaveRuntimeService.Service)
	local definition = service:getServiceDefinition()
	definition.initialize()
	definition.start()
end

local function spawnCallback(environment: Environment): (any) -> unknown
	return function(event: any): unknown
		table.insert(environment.spawnEvents, event)
		if environment.spawnMode == "uncommitted" then
			return table.freeze({ committed = false })
		end
		local configuration = environment.boundConfiguration or fixture.configuration
		local definition = configuration.enemies.byId[event.enemyId]
		local difficulty = environment.boundDifficulty or fixture.primary.difficultyDefinition
		local runtimeEnemyId = environment.nextRuntimeEnemyId
		environment.nextRuntimeEnemyId += 1
		return table.freeze({
			committed = true,
			replicationCommitted = true,
			snapshot = table.freeze({
				runtimeEnemyId = runtimeEnemyId,
				enemyId = event.enemyId,
				laneId = event.laneId,
				currentHealth = definition.maxHealth * difficulty.modifiers.enemyHealthMultiplier,
				maximumHealth = definition.maxHealth * difficulty.modifiers.enemyHealthMultiplier,
				effectiveSpeed = definition.moveSpeedStudsPerSecond * difficulty.modifiers.enemyMoveSpeedMultiplier,
				spawnServerTime = environment.now,
			}),
		})
	end
end

local function healthyFrame(environment: Environment, passOrdinal: number): any
	return table.freeze({
		disposition = "Healthy",
		matchId = MATCH_ID,
		enemyEpoch = ENEMY_EPOCH,
		passOrdinal = passOrdinal,
		sampleServerTime = environment.now,
		terminalOutcomes = table.freeze({}),
		spawn = spawnCallback(environment),
	})
end

local function closedFrame(environment: Environment, disposition: string, passOrdinal: number): any
	return table.freeze({
		disposition = disposition,
		matchId = MATCH_ID,
		enemyEpoch = ENEMY_EPOCH,
		passOrdinal = passOrdinal,
		sampleServerTime = environment.now,
		terminalOutcomes = table.freeze({}),
	})
end

local function freezeTree(value: any): any
	if type(value) ~= "table" then
		return value
	end
	for _, child in value do
		freezeTree(child)
	end
	return table.freeze(value)
end

local function studioTowerFixtureSources(): any
	local raw = TowerFixtures.rawSources()
	return freezeTree({
		assets = raw.assets,
		towers = raw.towers,
	})
end

type TowerBoundaryRig = {
	order: { string },
	buildMode: string,
	prepareMode: string,
	commitMode: string,
	dispatchMode: string,
	diagnosticsMode: string,
	closeMode: string,
	buildCount: number,
	prepareCount: number,
	commitCount: number,
	dispatchCount: number,
	diagnosticsCount: number,
	closeCount: number,
	dispatches: { string },
	token: any,
	configuration: any?,
	matchId: any?,
	diagnostics: any,
	buildValue: any?,
	builtSources: any?,
	buildHook: (() -> ())?,
	prepareHook: (() -> ())?,
	commitHook: (() -> ())?,
	dispatchHook: ((string) -> ())?,
	diagnosticsHook: (() -> ())?,
	closeHook: (() -> ())?,
}

local function newTowerBoundaryRig(environment: Environment): TowerBoundaryRig
	return {
		order = environment.order,
		buildMode = "success",
		prepareMode = "success",
		commitMode = "success",
		dispatchMode = "success",
		diagnosticsMode = "success",
		closeMode = "success",
		buildCount = 0,
		prepareCount = 0,
		commitCount = 0,
		dispatchCount = 0,
		diagnosticsCount = 0,
		closeCount = 0,
		dispatches = {},
		token = table.freeze({}),
		configuration = nil,
		matchId = nil,
		diagnostics = freezeTree({
			state = "Active",
			runtimeTowers = {
				{
					runtimeTowerId = 1,
					placementCFrame = CFrame.new(12, 34, -56) * CFrame.Angles(0, math.rad(90), 0),
				},
			},
			metrics = {
				activeCount = 1,
			},
		}),
		buildValue = nil,
		builtSources = nil,
		buildHook = nil,
		prepareHook = nil,
		commitHook = nil,
		dispatchHook = nil,
		diagnosticsHook = nil,
		closeHook = nil,
	}
end

local function callbackMode(mode: string, failureCode: string): unknown?
	if mode == "throw" then
		error(`PRIVATE_TOWER_{failureCode}`, 0)
	elseif mode == "yield" then
		coroutine.yield()
	elseif mode == "failure" then
		return Result.err(table.freeze({ code = failureCode }))
	elseif mode == "malformed" then
		return table.freeze({ malformed = true })
	end
	return nil
end

local function cleanedTowerResidue(): any
	return table.freeze({
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
end

local function makeTowerBoundaryAdapter(rig: TowerBoundaryRig): any
	local adapter: any
	adapter = table.freeze({
		buildStudioFixtureSources = function(self: any): unknown
			if self ~= adapter then
				return Result.err(table.freeze({ code = "INVALID_SELF" }))
			end
			table.insert(rig.order, "towerBuild")
			rig.buildCount += 1
			if rig.buildHook ~= nil then
				rig.buildHook()
			end
			local fault = callbackMode(rig.buildMode, "BUILD_FAILED")
			if fault ~= nil then
				return fault
			end
			local sources = rig.buildValue or studioTowerFixtureSources()
			rig.builtSources = sources
			return Result.ok(sources)
		end,
		prepareStudioConfiguration = function(self: any, configuration: unknown, matchId: unknown): unknown
			if self ~= adapter then
				return Result.err(table.freeze({ code = "INVALID_SELF" }))
			end
			table.insert(rig.order, "towerPrepare")
			rig.prepareCount += 1
			rig.configuration = configuration
			rig.matchId = matchId
			if rig.prepareHook ~= nil then
				rig.prepareHook()
			end
			local fault = callbackMode(rig.prepareMode, "PREPARE_FAILED")
			if fault ~= nil then
				return fault
			end
			return Result.ok(rig.token)
		end,
		commitStudioConfiguration = function(self: any, token: unknown): unknown
			if self ~= adapter or token ~= rig.token then
				return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
			end
			table.insert(rig.order, "towerCommit")
			rig.commitCount += 1
			if rig.commitHook ~= nil then
				rig.commitHook()
			end
			local fault = callbackMode(rig.commitMode, "COMMIT_FAILED")
			if fault ~= nil then
				return fault
			end
			return Result.ok(true)
		end,
		dispatchStudioEvidence = function(self: any, operation: unknown): unknown
			if self ~= adapter or type(operation) ~= "string" then
				return Result.err(table.freeze({ code = "INVALID_OPERATION" }))
			end
			table.insert(rig.order, `towerDispatch:{operation}`)
			rig.dispatchCount += 1
			table.insert(rig.dispatches, operation)
			if rig.dispatchHook ~= nil then
				rig.dispatchHook(operation)
			end
			local fault = callbackMode(rig.dispatchMode, "DISPATCH_FAILED")
			if fault ~= nil then
				return fault
			end
			if operation == "TowerCleanup" then
				return Result.ok(cleanedTowerResidue())
			end
			return Result.ok(table.freeze({ operation = operation }))
		end,
		getStudioDiagnostics = function(self: any): unknown
			if self ~= adapter then
				return Result.err(table.freeze({ code = "INVALID_SELF" }))
			end
			table.insert(rig.order, "towerDiagnostics")
			rig.diagnosticsCount += 1
			if rig.diagnosticsHook ~= nil then
				rig.diagnosticsHook()
			end
			local fault = callbackMode(rig.diagnosticsMode, "DIAGNOSTICS_FAILED")
			if fault ~= nil then
				return fault
			end
			return Result.ok(rig.diagnostics)
		end,
		closeFromWave = function(self: any): unknown
			if self ~= adapter then
				return Result.err(table.freeze({ code = "INVALID_SELF" }))
			end
			table.insert(rig.order, "towerClose")
			rig.closeCount += 1
			if rig.closeHook ~= nil then
				rig.closeHook()
			end
			local fault = callbackMode(rig.closeMode, "CLOSE_FAILED")
			if fault ~= nil then
				return fault
			end
			return Result.ok(rig.closeMode ~= "false")
		end,
	})
	return adapter
end

local function findOrder(order: { string }, value: string): number
	local index = table.find(order, value)
	if index == nil then
		error(`[ATD_TEST][code=MISSING_ORDER_ENTRY][entry={value}]`, 0)
	end
	return index
end

return TestHarness.suite("WaveRuntimeService", {
	TestHarness.case("declares the exact dependency graph and remains production-dormant", function(assertions)
		local environment = newEnvironment()
		local service = createService(environment, dormantSelection())
		local definition = service:getServiceDefinition()
		assertions.equal(definition.name, "WaveRuntime")
		assertions.equal(
			table.concat(definition.dependencies :: { string }, ","),
			"NetworkRegistry,MatchLifecycle,BaseRuntime,EnemySimulation"
		)

		definition.initialize()
		definition.start()
		assertions.equal(#environment.order, 0)
		local query = expectSuccess(assertions, service:query())
		assertions.equal(query.state, "Uninitialized")
		assertions.isTrue(query.dormant)
		expectError(assertions, service:getSnapshot(), "UNAVAILABLE", "getSnapshot")
		local completion = expectSuccess(assertions, service:getCompletionState())
		assertions.equal(completion.state, "Uninitialized")
		expectError(assertions, service:submitSkipVote(91, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		local metrics = service:getMetrics()
		assertions.isTrue(metrics.dormant)
		assertions.equal(metrics.connectionCount, 0)
		assertions.equal(metrics.boundaryCallbackCount, 0)
		assertions.isFalse(metrics.retainsRuntime)
		assertions.isFalse(metrics.retainsPublisher)
		assertions.isFalse(metrics.retainsBoundary)
		assertions.isNil(metrics.publisher)
		assertions.equal(metrics.studioTriggerCount, 0)
		assertions.equal(environment.triggerCreateCalls, 0)

		definition.shutdown()
		definition.shutdown()
		assertions.equal(service:getMetrics().lifecycleState, "Shutdown")
		expectError(assertions, service:submitSkipVote(91, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		assertions.equal(#environment.order, 0)

		local studioEnvironment = newEnvironment()
		studioEnvironment.isStudio = true
		local studioService = createService(studioEnvironment, dormantSelection())
		startService(studioService)
		assertions.equal(WaveRuntimeService.STUDIO_TRIGGER_NAME, "_ATDPhase11WaveEvidence")
		assertions.equal(studioEnvironment.triggerCreateCalls, 1)
		assertions.equal(studioService:getMetrics().studioTriggerCount, 1)
		local invoke = studioEnvironment.triggerHandler :: any
		expectError(assertions, invoke(), "INVALID_ARGUMENT", "runtimeTrigger")
		expectError(
			assertions,
			invoke({ operation = "Activate", scenario = "Primary", extra = true }),
			"INVALID_ARGUMENT",
			"runtimeTrigger"
		)
		expectError(
			assertions,
			invoke(setmetatable({ operation = "Diagnostics" }, {})),
			"INVALID_ARGUMENT",
			"runtimeTrigger"
		)
		expectError(
			assertions,
			invoke({ operation = "Activate", scenario = "Unknown" }),
			"INVALID_ARGUMENT",
			"runtimeTrigger"
		)
		assertions.equal(studioEnvironment.validationCount, 0)

		local activation = expectSuccess(assertions, invoke({ operation = "Activate", scenario = "Primary" }))
		assertions.equal(activation.scenario, "Primary")
		assertions.equal(activation.matchId, MATCH_ID)
		assertions.equal(activation.enemyEpoch, ENEMY_EPOCH)
		assertions.equal(activation.mapId, WaveFixtures.MAP_ID)
		assertions.equal(activation.difficultyId, "difficulty:phase11-studio")
		assertions.equal(activation.totalWaves, 4)
		assertions.equal(activation.waveRevision, 1)
		assertions.equal(studioEnvironment.validationCount, 1)
		assertions.equal(studioEnvironment.baseCatalogInstallCalls, 1)
		assertions.isTrue(studioEnvironment.legacyTriggerRevoked)
		assertions.equal(studioEnvironment.lifecycleState, "WaveActive")
		local runtimeMapReadCount = 0
		for _, entry in studioEnvironment.order do
			if entry == "runtimeMap" then
				runtimeMapReadCount += 1
			end
		end
		assertions.equal(runtimeMapReadCount, 1)
		local studioMetrics = studioService:getMetrics()
		assertions.isFalse(studioMetrics.dormant)
		assertions.isTrue(studioMetrics.studioActivationAttempted)
		assertions.isTrue(studioMetrics.studioActivated)
		assertions.equal(studioMetrics.studioScenario, "Primary")
		assertions.equal(studioMetrics.studioValidationCount, 1)
		assertions.isTrue(studioMetrics.publisher.hasPending)

		local diagnostics = expectSuccess(assertions, invoke({ operation = "Diagnostics" }))
		assertions.equal(diagnostics.identities.matchId, MATCH_ID)
		assertions.equal(diagnostics.identities.enemyEpoch, ENEMY_EPOCH)
		assertions.equal(diagnostics.revisions.wave, 1)
		assertions.equal(diagnostics.revisions.base, 1)
		assertions.equal(diagnostics.matchSnapshot.state, "WaveActive")
		assertions.equal(diagnostics.waveSnapshot.bossKind, "None")
		assertions.equal(diagnostics.startingCash.startingBattleCash, 500)
		assertions.equal(diagnostics.baseSnapshot.maximumHealth, 1_000_000)
		assertions.isFalse(diagnostics.baseDefeatState.defeated)
		assertions.equal(diagnostics.enemyIdentity.matchId, MATCH_ID)
		assertions.equal(#diagnostics.activeEnemies, 0)
		assertions.equal(diagnostics.configuration.enemyHealthMultiplier, 1.25)
		assertions.equal(diagnostics.configuration.enemyMoveSpeedMultiplier, 0.8)
		assertions.equal(diagnostics.configuration.standardEnemy.maxHealth, 80)
		assertions.equal(diagnostics.configuration.standardEnemy.moveSpeedStudsPerSecond, 20)
		assertions.equal(diagnostics.completion.completionCount, 0)
		assertions.isTrue(table.isfrozen(diagnostics.runtime))
		assertions.isTrue(table.isfrozen(diagnostics.wavePublisher))
		assertions.isTrue(table.isfrozen(diagnostics.base))
		assertions.isTrue(table.isfrozen(diagnostics.enemy))
		assertions.equal(diagnostics.residue.activeEnemyCount, 0)
		assertions.equal(diagnostics.publications.enemy, 0)
		assertions.isTrue(diagnostics.scheduler.noEarlySpawns)
		studioEnvironment.activeEnemies = {
			table.freeze({
				runtimeEnemyId = 91,
				revision = 1,
			}),
		}
		local manualResolution = expectSuccess(assertions, invoke({ operation = "ResolveEnemies", reason = "Manual" }))
		assertions.equal(manualResolution.reason, "Manual")
		assertions.equal(manualResolution.count, 1)
		assertions.equal(studioEnvironment.despawnCalls, 1)
		assertions.equal(#studioEnvironment.activeEnemies, 0)
		local assertionReceipt = expectSuccess(assertions, invoke({ operation = "RecordAssertion", passed = false }))
		assertions.equal(assertionReceipt.count, 1)
		assertions.equal(assertionReceipt.failureCount, 1)
		expectError(
			assertions,
			invoke({ operation = "Activate", scenario = "Primary" }),
			"STUDIO_ONLY",
			"runtimeTrigger"
		)
		assertions.equal(studioEnvironment.validationCount, 1)
		studioService:getServiceDefinition().shutdown()
		studioService:getServiceDefinition().shutdown()
		assertions.equal(studioEnvironment.triggerDestroyCount, 1)
		assertions.equal(studioService:getMetrics().studioTriggerCount, 0)
		assertions.equal(studioService:getMetrics().studioValidationCount, 0)
		assertions.equal(studioService:getMetrics().studioSpawnEvidenceCount, 0)
		assertions.equal(studioService:getMetrics().lifecycleState, "Shutdown")

		local readyEnvironment = newEnvironment()
		readyEnvironment.isStudio = true
		readyEnvironment.lifecycleState = "ReadyCheck"
		local _firstConnection, firstRecipient = makeRecipient(17)
		local _secondConnection, secondRecipient = makeRecipient(29)
		readyEnvironment.recipients = table.freeze({ firstRecipient, secondRecipient })
		local readyService = createService(readyEnvironment, dormantSelection())
		startService(readyService)
		local readyActivation = expectSuccess(
			assertions,
			(readyEnvironment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" })
		)
		assertions.equal(readyActivation.matchId, MATCH_ID)
		assertions.isTrue(readyEnvironment.validationCompleted)
		assertions.equal(readyEnvironment.readySubmissionCalls, 2)
		assertions.equal(readyEnvironment.lifecycleState, "WaveActive")
		assertions.equal(readyEnvironment.baseCatalogInstallCalls, 1)
		assertions.isTrue(table.find(readyEnvironment.order, "submitReady:17") ~= nil)
		assertions.isTrue(table.find(readyEnvironment.order, "submitReady:29") ~= nil)
		readyService:getServiceDefinition().shutdown()
		assertions.equal(readyService:getMetrics().lifecycleState, "Shutdown")

		local scenarios = {
			Primary = 4,
			Empty = 2,
			Deadline = 2,
			Overlap = 2,
			Skip = 2,
			Ladder1 = 1,
			Ladder32 = 1,
			Ladder64 = 1,
			Ladder128 = 1,
			Defeat = 1,
		}
		for scenario, totalWaves in scenarios do
			local variantEnvironment = newEnvironment()
			variantEnvironment.isStudio = true
			local variantService = createService(variantEnvironment, dormantSelection())
			startService(variantService)
			local variantInvoke = variantEnvironment.triggerHandler :: any
			local variantResult = variantInvoke({ operation = "Activate", scenario = scenario })
			local receipt = expectSuccess(assertions, variantResult)
			assertions.equal(receipt.scenario, scenario)
			assertions.equal(receipt.totalWaves, totalWaves)
			assertions.equal(variantEnvironment.validationCount, 1)
			assertions.equal(variantEnvironment.baseCatalogInstallCalls, 1)
			if scenario == "Ladder1" then
				local boundary = variantEnvironment.boundary :: any
				assertions.isTrue(expectSuccess(assertions, boundary:onEnemyPass(healthyFrame(variantEnvironment, 1))))
				assertions.equal(#variantEnvironment.spawnEvents, 1)
				local measured = expectSuccess(assertions, variantInvoke({ operation = "Diagnostics" }))
				assertions.equal(measured.scheduler.sampleCount, 1)
				assertions.equal(measured.scheduler.maximumSpawnLatenessSeconds, 0)
				assertions.isTrue(measured.scheduler.noEarlySpawns)
				assertions.equal(#measured.spawnEvidence, 1)
				assertions.equal(measured.spawnEvidence[1].runtimeEnemyId, 1)
				assertions.equal(measured.spawnEvidence[1].originatingWaveIndex, 1)
				assertions.equal(measured.spawnEvidence[1].groupIndex, 1)
				assertions.equal(measured.spawnEvidence[1].spawnOrdinal, 0)
				assertions.equal(measured.spawnEvidence[1].latenessSeconds, 0)
				assertions.equal(measured.spawnEvidence[1].currentHealth, 100)
				assertions.equal(measured.spawnEvidence[1].effectiveSpeed, 16)
			elseif scenario == "Defeat" then
				variantEnvironment.recipientMode = "committed-defeat"
				local configuration = variantEnvironment.boundConfiguration
				local schedule = configuration.waves.byMapId[WaveFixtures.MAP_ID]["difficulty:phase11-studio"]
				local defeatWave = schedule.waves[1]
				assertions.equal(#defeatWave.groups, 2)
				assertions.equal(defeatWave.groups[1].enemyId, "enemy:phase11-studio-defeat")
				assertions.equal(defeatWave.groups[1].count, 1)
				assertions.equal(defeatWave.groups[1].startDelaySeconds, 0)
				assertions.equal(defeatWave.groups[2].enemyId, "enemy:phase11-studio")
				assertions.equal(defeatWave.groups[2].count, 2)
				assertions.equal(defeatWave.groups[2].startDelaySeconds, 2)
				assertions.equal(defeatWave.groups[2].spawnIntervalSeconds, 1)

				local boundary = variantEnvironment.boundary :: any
				assertions.isTrue(expectSuccess(assertions, boundary:onEnemyPass(healthyFrame(variantEnvironment, 1))))
				assertions.equal(#variantEnvironment.spawnEvents, 1)
				assertions.equal(variantEnvironment.spawnEvents[1].enemyId, "enemy:phase11-studio-defeat")
				local midSchedule = expectSuccess(assertions, variantService:getSnapshot())
				assertions.equal(midSchedule.state, "Running")
				assertions.equal(midSchedule.aggregateCounts.spawned, 1)
				assertions.equal(midSchedule.aggregateCounts.pending, 2)
				expectSuccess(assertions, boundary:flushEnemyPass(1))
				assertions.isFalse(
					expectSuccess(
						assertions,
						boundary:onEnemyPass(closedFrame(variantEnvironment, "DefeatCommitted", 2))
					)
				)
				local defeated = expectSuccess(assertions, variantService:getSnapshot())
				assertions.equal(defeated.state, "DefeatClosed")
				assertions.equal(defeated.aggregateCounts.pending, 2)
				expectSuccess(assertions, boundary:flushEnemyPass(2))
				expectError(
					assertions,
					boundary:onEnemyPass(healthyFrame(variantEnvironment, 3)),
					"INTERNAL_ERROR",
					"onEnemyPass"
				)
				assertions.equal(#variantEnvironment.spawnEvents, 1)
			end
			variantService:getServiceDefinition().shutdown()
			assertions.equal(variantEnvironment.triggerDestroyCount, 1)
		end

		local rejectedSpawnEnvironment = newEnvironment()
		rejectedSpawnEnvironment.isStudio = true
		rejectedSpawnEnvironment.spawnMode = "uncommitted"
		local rejectedSpawnService = createService(rejectedSpawnEnvironment, dormantSelection())
		startService(rejectedSpawnService)
		local rejectedSpawnInvoke = rejectedSpawnEnvironment.triggerHandler :: any
		expectSuccess(assertions, rejectedSpawnInvoke({ operation = "Activate", scenario = "Ladder1" }))
		local rejectedSpawnBoundary = rejectedSpawnEnvironment.boundary :: any
		assertions.isTrue(
			expectSuccess(assertions, rejectedSpawnBoundary:onEnemyPass(healthyFrame(rejectedSpawnEnvironment, 1)))
		)
		local rejectedSpawnDiagnostics = expectSuccess(assertions, rejectedSpawnInvoke({ operation = "Diagnostics" }))
		assertions.equal(#rejectedSpawnDiagnostics.spawnEvidence, 0)
		assertions.equal(rejectedSpawnDiagnostics.scheduler.earlySpawnCount, 0)
		assertions.isTrue(rejectedSpawnDiagnostics.scheduler.noEarlySpawns)
		expectError(assertions, rejectedSpawnBoundary:flushEnemyPass(1), "INTERNAL_ERROR", "flushEnemyPass")
		assertions.equal(rejectedSpawnService:getMetrics().studioSpawnEvidenceCount, 0)
		rejectedSpawnService:getServiceDefinition().shutdown()
	end),

	TestHarness.case(
		"constructs and activates the exact finite runtime through the installed boundary",
		function(assertions)
			local environment = newEnvironment()
			local service = createService(environment, configuredSelection())
			initializeService(service)

			assertions.equal(environment.baseDifficulty, fixture.primary.difficultyDefinition)
			assertions.equal(environment.boundConfiguration, fixture.configuration)
			assertions.equal(environment.boundDifficulty, fixture.primary.difficultyDefinition)
			assertions.isNotNil(environment.boundary)
			local snapshot = expectSuccess(assertions, service:getSnapshot())
			assertions.equal(snapshot.matchId, MATCH_ID)
			assertions.equal(snapshot.enemyEpoch, ENEMY_EPOCH)
			assertions.equal(snapshot.difficultyId, WaveFixtures.PRIMARY_DIFFICULTY_ID)
			assertions.equal(snapshot.state, "Running")
			assertions.equal(snapshot.currentWaveNumber, 1)
			assertions.equal(snapshot.totalWaves, 4)
			local publisherIdentity = environment.publisherCreateIdentity
			assertions.equal(publisherIdentity.matchId, MATCH_ID)
			assertions.equal(publisherIdentity.enemyEpoch, ENEMY_EPOCH)
			assertions.equal(publisherIdentity.mapId, WaveFixtures.MAP_ID)
			assertions.equal(publisherIdentity.difficultyId, WaveFixtures.PRIMARY_DIFFICULTY_ID)
			assertions.equal(publisherIdentity.totalWaves, 4)
			assertions.isTrue(table.isfrozen(environment.publisherDependencies))
			assertions.equal(environment.publisherQueueCalls, 1)
			assertions.equal(environment.recipientCalls, 0)
			assertions.equal(#environment.waveSends, 0)
			local publisherMetrics = service:getMetrics().publisher
			assertions.isNotNil(publisherMetrics)
			assertions.isTrue(publisherMetrics.hasPending)
			assertions.equal(publisherMetrics.latestWaveRevision, 1)
			assertions.equal(publisherMetrics.queueCount, 1)

			expectError(assertions, service:submitSkipVote(0, MATCH_ID, 1), "INVALID_ARGUMENT", "submitSkipVote")
			expectError(assertions, service:submitSkipVote(71, OTHER_MATCH_ID, 1), "STALE_REQUEST", "submitSkipVote")
			local firstVote = expectSuccess(assertions, service:submitSkipVote(71, MATCH_ID, 1))
			local secondVote = expectSuccess(assertions, service:submitSkipVote(72, MATCH_ID, 1))
			assertions.equal(firstVote.waveRevision, 2)
			assertions.equal(firstVote.skipState.yesVoteCount, 1)
			assertions.equal(secondVote.waveRevision, 3)
			assertions.equal(secondVote.skipState.yesVoteCount, 2)
			assertions.isTrue(secondVote.skipState.quorumPending)
			assertions.equal(environment.voteCalls, 3)
			assertions.equal(environment.voteArguments.userId, 72)
			assertions.equal(environment.voteArguments.matchId, MATCH_ID)
			assertions.equal(environment.voteArguments.waveNumber, 1)
			assertions.equal(environment.recipientCalls, 0)
			assertions.equal(#environment.waveSends, 0)
			local coalesced = service:getMetrics().publisher
			assertions.equal(coalesced.queueCount, 3)
			assertions.equal(coalesced.coalescedQueueCount, 2)
			assertions.equal(coalesced.latestWaveRevision, 3)
			assertions.isTrue(coalesced.hasPending)

			local _, recipientRecord = makeRecipient(71)
			environment.recipients = { recipientRecord }
			local boundary = environment.boundary :: any
			expectSuccess(assertions, boundary:onEnemyPass(healthyFrame(environment, 73)))
			table.insert(environment.order, "enemyPublisherAdvance")
			expectSuccess(assertions, boundary:flushEnemyPass(73))
			assertions.equal(environment.recipientCalls, 1)
			assertions.isTrue(table.find(environment.order, "connectedRecipients") ~= nil)
			assertions.isNil(table.find(environment.order, "committedBaseDefeatRecipients"))
			assertions.equal(#environment.waveSends, 1)
			assertions.equal(environment.waveSends[1].snapshot.waveRevision, 3)
			assertions.isFalse(service:getMetrics().publisher.hasPending)
			local placeholder = expectSuccess(assertions, service:getStartingCashPlaceholder())
			assertions.equal(placeholder.startingBattleCash, 375)
			assertions.isTrue(table.isfrozen(placeholder))

			local createIndex = table.find(environment.order, "createRuntime")
			local installIndex = table.find(environment.order, "installBoundary")
			local prepareIndex = table.find(environment.order, "prepareBinding")
			local publisherIndex = table.find(environment.order, "createPublisher")
			assertions.isTrue((createIndex :: number) < (installIndex :: number))
			assertions.isTrue((installIndex :: number) < (prepareIndex :: number))
			assertions.isTrue((prepareIndex :: number) < (publisherIndex :: number))
			assertions.equal(service:getMetrics().connectionCount, 0)
			service:getServiceDefinition().shutdown()
		end
	),

	TestHarness.case(
		"routes exact sampled boundary frames and scheduler spawns without another loop",
		function(assertions)
			local environment = newEnvironment()
			local service = createService(environment, configuredSelection())
			startService(service)
			local boundary = environment.boundary
			assertions.isNotNil(boundary)
			local _, recipientRecord = makeRecipient(31)
			environment.recipients = { recipientRecord }

			local stepped = (boundary :: any):onEnemyPass(healthyFrame(environment, 1))
			expectSuccess(assertions, stepped)
			table.insert(environment.order, "enemyPublisherAdvance")
			expectSuccess(assertions, (boundary :: any):flushEnemyPass(1))
			assertions.equal(#environment.spawnEvents, 3)
			for _, event in environment.spawnEvents do
				assertions.isTrue(table.isfrozen(event))
				assertions.equal(event.scheduledServerTime, 100)
			end
			local snapshot = expectSuccess(assertions, service:getSnapshot())
			assertions.equal(snapshot.aggregateCounts.spawned, 3)
			assertions.equal(snapshot.aggregateCounts.alive, 3)
			assertions.equal(environment.publisherQueueCalls, 2)
			assertions.equal(environment.publisherFlushCalls, 1)
			assertions.equal(environment.recipientCalls, 1)
			assertions.equal(#environment.waveSends, 1)
			assertions.equal(environment.waveSends[1].snapshot.waveRevision, 2)
			local advanceIndex = table.find(environment.order, "enemyPublisherAdvance")
			local waveFlushIndex = table.find(environment.order, "publisherFlush:1")
			local waveSendIndex = table.find(environment.order, "waveSender:2")
			assertions.isTrue((advanceIndex :: number) < (waveFlushIndex :: number))
			assertions.isTrue((waveFlushIndex :: number) < (waveSendIndex :: number))

			-- A pass with no semantic Wave change still advances the exact flush
			-- ordinal, without sampling recipients or emitting another event.
			expectSuccess(assertions, (boundary :: any):onEnemyPass(healthyFrame(environment, 2)))
			expectSuccess(assertions, (boundary :: any):flushEnemyPass(2))
			assertions.equal(environment.publisherQueueCalls, 2)
			assertions.equal(environment.publisherFlushCalls, 2)
			assertions.equal(environment.recipientCalls, 1)
			assertions.equal(#environment.waveSends, 1)
			local metrics = service:getMetrics()
			assertions.equal(metrics.connectionCount, 0)
			assertions.equal(metrics.boundaryCallbackCount, 1)
			assertions.equal(metrics.lastEnemyPassOrdinal, 2)
			assertions.equal(metrics.lastFlushedPassOrdinal, 2)
			assertions.equal(metrics.lastQueuedWaveRevision, 2)
			assertions.equal(metrics.publisher.publicationCount, 1)
			assertions.equal(metrics.publisher.coalescedQueueCount, 1)
			assertions.isFalse(metrics.publisher.hasPending)
			service:getServiceDefinition().shutdown()
		end
	),

	TestHarness.case("contains Wave sender false and throw outcomes without closing the boundary", function(assertions)
		for _, senderMode in { "false", "throw" } do
			local environment = newEnvironment()
			environment.senderMode = senderMode
			local _, recipientRecord = makeRecipient(42)
			environment.recipients = { recipientRecord }
			local service = createService(environment, configuredSelection())
			startService(service)
			local boundary = environment.boundary :: any
			expectSuccess(assertions, boundary:onEnemyPass(healthyFrame(environment, 1)))
			expectSuccess(assertions, boundary:flushEnemyPass(1))

			local metrics = service:getMetrics()
			assertions.equal(metrics.lifecycleState, "Started")
			assertions.isTrue(metrics.callbacksEnabled)
			assertions.equal(metrics.publisher.publicationCount, 1)
			assertions.equal(metrics.publisher.senderCallCount, 1)
			assertions.equal(metrics.publisher.senderFailureCount, 1)
			assertions.isFalse(metrics.publisher.faulted)
			assertions.equal(#environment.waveSends, 1)
			service:getServiceDefinition().shutdown()
		end

		local rejectedEnvironment = newEnvironment()
		rejectedEnvironment.voteMode = "failure"
		local rejectedService = createService(rejectedEnvironment, configuredSelection())
		startService(rejectedService)
		expectError(assertions, rejectedService:submitSkipVote(43, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		local rejectedMetrics = rejectedService:getMetrics()
		assertions.equal(rejectedMetrics.lifecycleState, "Started")
		assertions.isTrue(rejectedMetrics.callbacksEnabled)
		assertions.equal(rejectedMetrics.publisher.queueCount, 1)
		assertions.equal(rejectedEnvironment.publisherQueueCalls, 1)
		rejectedService:getServiceDefinition().shutdown()
	end),

	TestHarness.case("closes the boundary on structural publisher queue or flush faults", function(assertions)
		local preflightEnvironment = newEnvironment()
		preflightEnvironment.publisherPreflightMode = "false"
		local preflightService = createService(preflightEnvironment, configuredSelection())
		startService(preflightService)
		local preflightBoundary = preflightEnvironment.boundary :: any
		expectError(
			assertions,
			preflightBoundary:onEnemyPass(healthyFrame(preflightEnvironment, 1)),
			"INTERNAL_ERROR",
			"onEnemyPass"
		)
		assertions.equal(preflightEnvironment.publisherPreflightCalls, 1)
		assertions.equal(preflightEnvironment.runtimeStepCalls, 0)
		assertions.equal(preflightEnvironment.publisherQueueCalls, 1)
		assertions.equal(preflightEnvironment.publisherFlushCalls, 0)
		assertions.equal(#preflightEnvironment.spawnEvents, 0)
		assertions.equal(preflightService:getMetrics().lifecycleState, "Failed")
		preflightService:getServiceDefinition().shutdown()

		local passJumpEnvironment = newEnvironment()
		passJumpEnvironment.stepMode = "revision-jump"
		local passJumpService = createService(passJumpEnvironment, configuredSelection())
		startService(passJumpService)
		local passJumpBoundary = passJumpEnvironment.boundary :: any
		expectError(
			assertions,
			passJumpBoundary:onEnemyPass(healthyFrame(passJumpEnvironment, 1)),
			"INTERNAL_ERROR",
			"onEnemyPass"
		)
		local passJumpMetrics = passJumpService:getMetrics()
		assertions.equal(passJumpEnvironment.publisherPreflightCalls, 1)
		assertions.equal(passJumpEnvironment.runtimeStepCalls, 1)
		assertions.equal(passJumpEnvironment.publisherQueueCalls, 1)
		assertions.equal(passJumpEnvironment.publisherFlushCalls, 0)
		assertions.equal(#passJumpEnvironment.spawnEvents, 0)
		assertions.equal(passJumpMetrics.lifecycleState, "Failed")
		assertions.equal(passJumpMetrics.lastQueuedWaveRevision, 1)
		passJumpService:getServiceDefinition().shutdown()

		local queueEnvironment = newEnvironment()
		queueEnvironment.publisherQueueMode = "failure"
		local queueService = createService(queueEnvironment, configuredSelection())
		startService(queueService)
		local queueBoundary = queueEnvironment.boundary :: any
		expectError(
			assertions,
			queueBoundary:onEnemyPass(healthyFrame(queueEnvironment, 1)),
			"INTERNAL_ERROR",
			"onEnemyPass"
		)
		assertions.equal(queueEnvironment.publisherQueueCalls, 2)
		assertions.equal(queueEnvironment.publisherFlushCalls, 0)
		assertions.equal(queueService:getMetrics().lifecycleState, "Failed")
		assertions.equal(queueService:getMetrics().terminalState, "Faulted")
		queueService:getServiceDefinition().shutdown()

		local flushEnvironment = newEnvironment()
		flushEnvironment.recipientMode = "failure"
		local flushService = createService(flushEnvironment, configuredSelection())
		startService(flushService)
		local flushBoundary = flushEnvironment.boundary :: any
		expectSuccess(assertions, flushBoundary:onEnemyPass(healthyFrame(flushEnvironment, 1)))
		expectError(assertions, flushBoundary:flushEnemyPass(1), "INTERNAL_ERROR", "flushEnemyPass")
		local metrics = flushService:getMetrics()
		assertions.equal(metrics.lifecycleState, "Failed")
		assertions.equal(metrics.terminalState, "Faulted")
		assertions.equal(metrics.publisher.publicationCount, 0)
		assertions.isTrue(metrics.publisher.faulted)
		assertions.isFalse(metrics.publisher.hasPending)
		assertions.equal(flushEnvironment.publisherFlushCalls, 1)
		assertions.equal(flushEnvironment.recipientCalls, 1)
		flushService:getServiceDefinition().shutdown()

		local runtimeFaultEnvironment = newEnvironment()
		runtimeFaultEnvironment.stepMode = "faulted"
		local _, runtimeFaultRecipient = makeRecipient(86)
		runtimeFaultEnvironment.recipients = { runtimeFaultRecipient }
		local runtimeFaultService = createService(runtimeFaultEnvironment, configuredSelection())
		startService(runtimeFaultService)
		local runtimeFaultBoundary = runtimeFaultEnvironment.boundary :: any
		assertions.isTrue(
			expectSuccess(assertions, runtimeFaultBoundary:onEnemyPass(healthyFrame(runtimeFaultEnvironment, 1)))
		)
		local runtimeFaultQueuedMetrics = runtimeFaultService:getMetrics()
		assertions.equal(runtimeFaultQueuedMetrics.lifecycleState, "Started")
		assertions.equal(runtimeFaultQueuedMetrics.terminalState, "Faulted")
		assertions.isTrue(runtimeFaultQueuedMetrics.callbacksEnabled)
		assertions.isTrue(runtimeFaultQueuedMetrics.publisher.hasPending)
		assertions.equal(runtimeFaultQueuedMetrics.lastQueuedWaveRevision, 2)
		assertions.equal(runtimeFaultEnvironment.publisherQueueCalls, 2)
		assertions.equal(runtimeFaultEnvironment.publisherFlushCalls, 0)
		assertions.equal(#runtimeFaultEnvironment.waveSends, 0)
		assertions.equal(#runtimeFaultEnvironment.spawnEvents, 0)

		expectError(assertions, runtimeFaultBoundary:flushEnemyPass(1), "INTERNAL_ERROR", "flushEnemyPass")
		expectSuccess(
			assertions,
			runtimeFaultBoundary:close(table.freeze({
				disposition = "DependencyFault",
				matchId = MATCH_ID,
				enemyEpoch = ENEMY_EPOCH,
				passOrdinal = 1,
				sampleServerTime = runtimeFaultEnvironment.now,
			}))
		)
		runtimeFaultEnvironment.boundaryStatus = "Faulted"
		local runtimeFaultPublishedMetrics = runtimeFaultService:getMetrics()
		assertions.equal(runtimeFaultPublishedMetrics.lifecycleState, "Failed")
		assertions.equal(runtimeFaultPublishedMetrics.terminalState, "Faulted")
		assertions.isFalse(runtimeFaultPublishedMetrics.callbacksEnabled)
		assertions.isFalse(runtimeFaultPublishedMetrics.publisher.hasPending)
		assertions.equal(runtimeFaultPublishedMetrics.publisher.publicationCount, 1)
		assertions.equal(runtimeFaultPublishedMetrics.publisher.flushCount, 1)
		assertions.equal(runtimeFaultEnvironment.publisherFlushCalls, 1)
		assertions.equal(#runtimeFaultEnvironment.waveSends, 1)
		assertions.equal(runtimeFaultEnvironment.waveSends[1].snapshot.state, "Faulted")
		assertions.equal(#runtimeFaultEnvironment.spawnEvents, 0)
		assertions.equal(boundaryStatus(runtimeFaultEnvironment).status, "Faulted")
		expectError(
			assertions,
			runtimeFaultBoundary:onEnemyPass(healthyFrame(runtimeFaultEnvironment, 2)),
			"INTERNAL_ERROR",
			"onEnemyPass"
		)
		assertions.equal(runtimeFaultService:getMetrics().publisher.publicationCount, 1)
		assertions.equal(runtimeFaultEnvironment.publisherFlushCalls, 1)
		assertions.equal(#runtimeFaultEnvironment.waveSends, 1)
		runtimeFaultService:getServiceDefinition().shutdown()

		for _, voteMode in { "throw", "yield", "malformed", "arbitrary-error" } do
			local voteEnvironment = newEnvironment()
			voteEnvironment.voteMode = voteMode
			local voteService = createService(voteEnvironment, configuredSelection())
			startService(voteService)
			expectError(assertions, voteService:submitSkipVote(81, MATCH_ID, 1), "INTERNAL_ERROR", "submitSkipVote")
			assertions.equal(voteService:getMetrics().lifecycleState, "Failed")
			assertions.equal(voteService:getMetrics().terminalState, "Faulted")
			voteService:getServiceDefinition().shutdown()
		end

		local jumpEnvironment = newEnvironment()
		jumpEnvironment.voteMode = "jump-success"
		local jumpService = createService(jumpEnvironment, configuredSelection())
		startService(jumpService)
		expectError(assertions, jumpService:submitSkipVote(84, MATCH_ID, 1), "INTERNAL_ERROR", "submitSkipVote")
		local jumpMetrics = jumpService:getMetrics()
		assertions.equal(jumpMetrics.lifecycleState, "Failed")
		assertions.equal(jumpMetrics.lastQueuedWaveRevision, 1)
		assertions.equal(jumpEnvironment.publisherQueueCalls, 1)
		jumpService:getServiceDefinition().shutdown()

		local rejectedRunningEnvironment = newEnvironment()
		rejectedRunningEnvironment.voteMode = "running-failure-jump"
		local rejectedRunningService = createService(rejectedRunningEnvironment, configuredSelection())
		startService(rejectedRunningService)
		expectError(
			assertions,
			rejectedRunningService:submitSkipVote(87, MATCH_ID, 1),
			"INTERNAL_ERROR",
			"submitSkipVote"
		)
		local rejectedRunningMetrics = rejectedRunningService:getMetrics()
		assertions.equal(rejectedRunningEnvironment.voteRevision, 2)
		assertions.equal(rejectedRunningEnvironment.publisherQueueCalls, 1)
		assertions.equal(rejectedRunningMetrics.lifecycleState, "Failed")
		assertions.equal(rejectedRunningMetrics.terminalState, "Faulted")
		assertions.equal(rejectedRunningMetrics.lastQueuedWaveRevision, 1)
		rejectedRunningService:getServiceDefinition().shutdown()

		local defeatEnvironment = newEnvironment()
		defeatEnvironment.voteMode = "defeat-failure"
		local _, defeatRecipient = makeRecipient(82)
		defeatEnvironment.recipients = { defeatRecipient }
		defeatEnvironment.recipientMode = "committed-defeat"
		local defeatService = createService(defeatEnvironment, configuredSelection())
		startService(defeatService)
		expectError(assertions, defeatService:submitSkipVote(82, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		local defeatMetrics = defeatService:getMetrics()
		assertions.equal(defeatMetrics.lifecycleState, "Started")
		assertions.equal(defeatMetrics.terminalState, "DefeatClosed")
		assertions.equal(defeatMetrics.lastQueuedWaveRevision, 2)
		assertions.isTrue(defeatMetrics.publisher.hasPending)
		assertions.equal(defeatEnvironment.publisherQueueCalls, 2)
		local defeatBoundary = defeatEnvironment.boundary :: any
		assertions.isFalse(
			expectSuccess(assertions, defeatBoundary:onEnemyPass(closedFrame(defeatEnvironment, "DefeatCommitted", 1)))
		)
		defeatEnvironment.boundaryStatus = "DefeatClosed"
		expectSuccess(assertions, defeatBoundary:flushEnemyPass(1))
		assertions.equal(#defeatEnvironment.waveSends, 1)
		assertions.equal(defeatEnvironment.waveSends[1].snapshot.state, "DefeatClosed")
		assertions.equal(defeatEnvironment.waveSends[1].snapshot.waveRevision, 2)
		assertions.isNil(table.find(defeatEnvironment.order, "connectedRecipients"))
		assertions.isTrue(table.find(defeatEnvironment.order, "committedBaseDefeatRecipients") ~= nil)
		local defeatClosedMetrics = defeatService:getMetrics()
		assertions.isFalse(defeatClosedMetrics.publisher.hasPending)
		assertions.equal(defeatClosedMetrics.publisher.publicationCount, 1)
		assertions.equal(defeatClosedMetrics.publisher.flushCount, 1)
		assertions.equal(#defeatEnvironment.waveSends, 1)
		assertions.equal(#defeatEnvironment.spawnEvents, 0)
		assertions.equal(boundaryStatus(defeatEnvironment).status, "DefeatClosed")
		defeatService:getServiceDefinition().shutdown()

		for _, recipientMode in { "committed-failure", "committed-malformed", "committed-throw" } do
			local terminalRecipientEnvironment = newEnvironment()
			terminalRecipientEnvironment.voteMode = "defeat-failure"
			terminalRecipientEnvironment.recipientMode = recipientMode
			local _, terminalRecipient = makeRecipient(91)
			terminalRecipientEnvironment.recipients = { terminalRecipient }
			local terminalRecipientService = createService(terminalRecipientEnvironment, configuredSelection())
			startService(terminalRecipientService)
			expectError(
				assertions,
				terminalRecipientService:submitSkipVote(91, MATCH_ID, 1),
				"UNAVAILABLE",
				"submitSkipVote"
			)
			local terminalRecipientBoundary = terminalRecipientEnvironment.boundary :: any
			assertions.isFalse(
				expectSuccess(
					assertions,
					terminalRecipientBoundary:onEnemyPass(
						closedFrame(terminalRecipientEnvironment, "DefeatCommitted", 1)
					)
				)
			)
			terminalRecipientEnvironment.boundaryStatus = "DefeatClosed"
			expectError(assertions, terminalRecipientBoundary:flushEnemyPass(1), "INTERNAL_ERROR", "flushEnemyPass")
			local terminalRecipientMetrics = terminalRecipientService:getMetrics()
			assertions.equal(terminalRecipientMetrics.lifecycleState, "Failed")
			assertions.equal(terminalRecipientMetrics.terminalState, "Faulted")
			assertions.isFalse(terminalRecipientMetrics.publisher.hasPending)
			assertions.isTrue(table.find(terminalRecipientEnvironment.order, "committedBaseDefeatRecipients") ~= nil)
			assertions.isNil(table.find(terminalRecipientEnvironment.order, "connectedRecipients"))
			assertions.equal(#terminalRecipientEnvironment.waveSends, 0)
			terminalRecipientService:getServiceDefinition().shutdown()
		end

		local lateHealthyEnvironment = newEnvironment()
		lateHealthyEnvironment.voteMode = "defeat-failure"
		lateHealthyEnvironment.recipientMode = "committed-defeat"
		local _, lateHealthyRecipient = makeRecipient(85)
		lateHealthyEnvironment.recipients = { lateHealthyRecipient }
		local lateHealthyService = createService(lateHealthyEnvironment, configuredSelection())
		startService(lateHealthyService)
		expectError(assertions, lateHealthyService:submitSkipVote(85, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		local lateHealthyBoundary = lateHealthyEnvironment.boundary :: any
		assertions.isTrue(
			expectSuccess(assertions, lateHealthyBoundary:onEnemyPass(healthyFrame(lateHealthyEnvironment, 1)))
		)
		expectSuccess(assertions, lateHealthyBoundary:flushEnemyPass(1))
		expectError(
			assertions,
			lateHealthyBoundary:onEnemyPass(healthyFrame(lateHealthyEnvironment, 2)),
			"INTERNAL_ERROR",
			"onEnemyPass"
		)
		local lateHealthyMetrics = lateHealthyService:getMetrics()
		assertions.equal(lateHealthyMetrics.lifecycleState, "Failed")
		assertions.equal(lateHealthyMetrics.terminalState, "Faulted")
		assertions.equal(lateHealthyMetrics.publisher.publicationCount, 1)
		assertions.equal(lateHealthyMetrics.publisher.flushCount, 1)
		assertions.equal(#lateHealthyEnvironment.waveSends, 1)
		assertions.equal(#lateHealthyEnvironment.spawnEvents, 0)
		lateHealthyService:getServiceDefinition().shutdown()

		local faultEnvironment = newEnvironment()
		faultEnvironment.voteMode = "fault-failure"
		local _, faultRecipient = makeRecipient(83)
		faultEnvironment.recipients = { faultRecipient }
		local faultService = createService(faultEnvironment, configuredSelection())
		startService(faultService)
		expectError(assertions, faultService:submitSkipVote(83, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		local faultQueuedMetrics = faultService:getMetrics()
		assertions.equal(faultQueuedMetrics.lifecycleState, "Started")
		assertions.equal(faultQueuedMetrics.terminalState, "Faulted")
		assertions.isTrue(faultQueuedMetrics.callbacksEnabled)
		assertions.isTrue(faultQueuedMetrics.publisher.hasPending)
		local faultBoundary = faultEnvironment.boundary :: any
		assertions.isTrue(expectSuccess(assertions, faultBoundary:onEnemyPass(healthyFrame(faultEnvironment, 1))))
		expectError(assertions, faultBoundary:flushEnemyPass(1), "INTERNAL_ERROR", "flushEnemyPass")
		local faultPublishedMetrics = faultService:getMetrics()
		assertions.equal(faultPublishedMetrics.lifecycleState, "Failed")
		assertions.equal(faultPublishedMetrics.terminalState, "Faulted")
		assertions.isFalse(faultPublishedMetrics.callbacksEnabled)
		assertions.isFalse(faultPublishedMetrics.publisher.hasPending)
		assertions.equal(#faultEnvironment.waveSends, 1)
		assertions.equal(faultEnvironment.waveSends[1].snapshot.state, "Faulted")
		faultService:getServiceDefinition().shutdown()
	end),

	TestHarness.case("retains canonical Faulted truth after terminal sender failures", function(assertions)
		for _, senderMode in { "false", "throw" } do
			local environment = newEnvironment()
			environment.stepMode = "faulted"
			environment.senderMode = senderMode
			local _, recipient = makeRecipient(92)
			environment.recipients = { recipient }
			local service = createService(environment, configuredSelection())
			startService(service)
			local boundary = environment.boundary :: any
			assertions.isTrue(expectSuccess(assertions, boundary:onEnemyPass(healthyFrame(environment, 1))))
			expectError(assertions, boundary:flushEnemyPass(1), "INTERNAL_ERROR", "flushEnemyPass")

			local first = expectSuccess(assertions, service:getSnapshot())
			local second = expectSuccess(assertions, service:getSnapshot())
			assertions.equal(first.state, "Faulted")
			assertions.equal(second, first)
			assertions.equal(first.waveRevision, environment.waveSends[1].snapshot.waveRevision)
			assertions.equal(first.state, environment.waveSends[1].snapshot.state)
			assertions.equal(first.aggregateCounts.spawned, environment.waveSends[1].snapshot.aggregateCounts.spawned)
			assertions.equal(service:getMetrics().publisher.senderFailureCount, 1)
			expectError(assertions, service:submitSkipVote(92, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")

			expectSuccess(
				assertions,
				boundary:close(table.freeze({
					disposition = "DependencyFault",
					matchId = MATCH_ID,
					enemyEpoch = ENEMY_EPOCH,
					passOrdinal = 1,
					sampleServerTime = environment.now,
				}))
			)
			assertions.equal(service:getMetrics().publisher.publicationCount, 1)
			assertions.equal(environment.publisherFlushCalls, 1)
			assertions.equal(#environment.waveSends, 1)
			expectError(assertions, boundary:onEnemyPass(healthyFrame(environment, 2)), "INTERNAL_ERROR", "onEnemyPass")
			local afterReplay = expectSuccess(assertions, service:getSnapshot())
			assertions.equal(afterReplay.state, first.state)
			assertions.equal(afterReplay.waveRevision, first.waveRevision)

			service:getServiceDefinition().shutdown()
			expectError(assertions, service:getSnapshot(), "UNAVAILABLE", "getSnapshot")
		end
	end),

	TestHarness.case("fails closed when a scheduler spawn dependency rejects after activation", function(assertions)
		local environment = newEnvironment()
		environment.spawnMode = "uncommitted"
		local service = createService(environment, configuredSelection())
		startService(service)
		local boundary = environment.boundary :: any
		assertions.isTrue(expectSuccess(assertions, boundary:onEnemyPass(healthyFrame(environment, 1))))
		local queuedMetrics = service:getMetrics()
		assertions.equal(queuedMetrics.lifecycleState, "Started")
		assertions.equal(queuedMetrics.terminalState, "Faulted")
		assertions.isTrue(queuedMetrics.publisher.hasPending)
		expectError(assertions, boundary:flushEnemyPass(1), "INTERNAL_ERROR", "flushEnemyPass")
		assertions.equal(service:getMetrics().lifecycleState, "Failed")
		assertions.equal(service:getMetrics().terminalState, "Faulted")
		assertions.equal(service:getMetrics().publisher.publicationCount, 1)
		assertions.isFalse(service:getMetrics().publisher.hasPending)
		local recoverableFault = expectSuccess(assertions, service:getSnapshot())
		assertions.equal(recoverableFault.state, "Faulted")
		assertions.equal(recoverableFault.waveRevision, service:getMetrics().lastQueuedWaveRevision)
		expectError(assertions, service:submitSkipVote(51, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")

		local closeContext = table.freeze({
			disposition = "DependencyFault",
			matchId = MATCH_ID,
			enemyEpoch = ENEMY_EPOCH,
			passOrdinal = 1,
			sampleServerTime = environment.now,
		})
		expectSuccess(assertions, boundary:close(closeContext))
		assertions.equal(environment.runtimeCleanupCount, 0)
		service:getServiceDefinition().shutdown()
		assertions.equal(environment.detachCount, 1)
		assertions.equal(environment.runtimeCleanupCount, 1)
		expectError(assertions, service:getSnapshot(), "UNAVAILABLE", "getSnapshot")

		local terminalEnvironment = newEnvironment()
		local terminalService = createService(terminalEnvironment, configuredSelection())
		startService(terminalService)
		local terminalBoundary = terminalEnvironment.boundary :: any
		assertions.isFalse(
			expectSuccess(
				assertions,
				terminalBoundary:onEnemyPass(closedFrame(terminalEnvironment, "DefeatCommitted", 1))
			)
		)
		assertions.equal(terminalService:getMetrics().terminalState, "DefeatClosed")
		expectError(assertions, terminalService:submitSkipVote(52, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		terminalService:getServiceDefinition().shutdown()
	end),

	TestHarness.case("authenticates Enemy identity before runtime construction", function(assertions)
		local cases = {
			table.freeze({
				identity = table.freeze({ matchId = OTHER_MATCH_ID, enemyEpoch = ENEMY_EPOCH }),
			}),
			table.freeze({
				identity = table.freeze({ matchId = MATCH_ID, enemyEpoch = 0 }),
			}),
			table.freeze({
				identity = table.freeze({ matchId = MATCH_ID, enemyEpoch = ENEMY_EPOCH, extra = true }),
			}),
		}
		for _, caseValue in cases do
			local environment = newEnvironment()
			environment.enemyIdentity = caseValue.identity
			local service = createService(environment, configuredSelection())
			local ok, message = pcall(function()
				initializeService(service)
			end)
			assertions.isFalse(ok)
			assertions.contains(message, "ENEMY_IDENTITY_INVALID")
			assertions.isNil(table.find(environment.order, "createRuntime"))
			assertions.isNil(table.find(environment.order, "installBoundary"))
		end
	end),

	TestHarness.case(
		"rejects an installed boundary whose epoch differs from authenticated Enemy identity",
		function(assertions)
			local environment = newEnvironment()
			environment.statusEpoch = ENEMY_EPOCH + 1
			local service = createService(environment, configuredSelection())
			local ok, message = pcall(function()
				initializeService(service)
			end)
			assertions.isFalse(ok)
			assertions.contains(message, "BOUNDARY_STATUS_INVALID")
			assertions.equal(environment.detachCount, 1)
			assertions.equal(environment.runtimeCleanupCount, 1)
		end
	),

	TestHarness.case("detaches the callback before runtime cleanup and attempts both releases", function(assertions)
		local environment = newEnvironment()
		local service = createService(environment, configuredSelection())
		startService(service)
		table.clear(environment.order)
		service:getServiceDefinition().shutdown()
		assertions.equal(environment.order[1], "detachBoundary")
		assertions.equal(environment.order[2], "publisherCleanup")
		assertions.equal(environment.order[3], "runtimeCleanup")
		assertions.equal(environment.detachCount, 1)
		assertions.equal(environment.publisherCleanupCount, 1)
		assertions.equal(environment.runtimeCleanupCount, 1)
		service:getServiceDefinition().shutdown()
		assertions.equal(environment.detachCount, 1)
		assertions.equal(environment.publisherCleanupCount, 1)
		assertions.equal(environment.runtimeCleanupCount, 1)

		local failing = newEnvironment()
		failing.detachMode = "failure"
		local failingService = createService(failing, configuredSelection())
		startService(failingService)
		table.clear(failing.order)
		local ok, message = pcall(function()
			failingService:getServiceDefinition().shutdown()
		end)
		assertions.isFalse(ok)
		assertions.contains(message, "CLEANUP_FAILED")
		assertions.equal(failing.order[1], "detachBoundary")
		assertions.equal(failing.order[2], "publisherCleanup")
		assertions.equal(failing.order[3], "runtimeCleanup")
		assertions.equal(failing.publisherCleanupCount, 1)
		assertions.equal(failing.runtimeCleanupCount, 1)

		local falseCleanupCases = {
			{
				configure = function(targetEnvironment: Environment)
					targetEnvironment.detachMode = "false"
				end,
			},
			{
				configure = function(targetEnvironment: Environment)
					targetEnvironment.publisherCleanupMode = "false"
				end,
			},
			{
				configure = function(targetEnvironment: Environment)
					targetEnvironment.runtimeCleanupMode = "false"
				end,
			},
		}
		for _, definition in falseCleanupCases do
			local falseEnvironment = newEnvironment()
			definition.configure(falseEnvironment)
			local falseService = createService(falseEnvironment, configuredSelection())
			startService(falseService)
			table.clear(falseEnvironment.order)
			local falseOk, falseMessage = pcall(function()
				falseService:getServiceDefinition().shutdown()
			end)
			assertions.isFalse(falseOk)
			assertions.contains(falseMessage, "CLEANUP_FAILED")
			assertions.equal(falseEnvironment.order[1], "detachBoundary")
			assertions.equal(falseEnvironment.order[2], "publisherCleanup")
			assertions.equal(falseEnvironment.order[3], "runtimeCleanup")
			assertions.equal(falseEnvironment.detachCount, 1)
			assertions.equal(falseEnvironment.publisherCleanupCount, 1)
			assertions.equal(falseEnvironment.runtimeCleanupCount, 1)
			assertions.equal(falseService:getMetrics().lifecycleState, "Failed")
		end

		local stepShutdownEnvironment = newEnvironment()
		local stepShutdownService = createService(stepShutdownEnvironment, configuredSelection())
		local stepShutdownDefinition = stepShutdownService:getServiceDefinition()
		startService(stepShutdownService)
		local stepShutdownBoundary = stepShutdownEnvironment.boundary :: any
		stepShutdownEnvironment.stepHook = function()
			stepShutdownDefinition.shutdown()
		end
		assertions.isTrue(
			expectSuccess(assertions, stepShutdownBoundary:onEnemyPass(healthyFrame(stepShutdownEnvironment, 1)))
		)
		assertions.equal(stepShutdownService:getMetrics().lifecycleState, "ShuttingDown")
		assertions.isTrue(stepShutdownService:getMetrics().retainsBoundary)
		assertions.isFalse(expectSuccess(assertions, stepShutdownBoundary:flushEnemyPass(1)))
		table.insert(stepShutdownEnvironment.order, "enemyBoundaryClose")
		expectSuccess(
			assertions,
			stepShutdownBoundary:close(table.freeze({
				disposition = "Shutdown",
				matchId = MATCH_ID,
				enemyEpoch = ENEMY_EPOCH,
				passOrdinal = 1,
				sampleServerTime = stepShutdownEnvironment.now,
			}))
		)
		local stepShutdownMetrics = stepShutdownService:getMetrics()
		assertions.equal(stepShutdownMetrics.lifecycleState, "Shutdown")
		assertions.isFalse(stepShutdownMetrics.retainsBoundary)
		assertions.isFalse(stepShutdownMetrics.retainsPublisher)
		assertions.isFalse(stepShutdownMetrics.retainsRuntime)
		assertions.isFalse(stepShutdownMetrics.retainsConstructionDependencies)
		assertions.equal(stepShutdownEnvironment.detachCount, 0)
		assertions.isTrue(
			(table.find(stepShutdownEnvironment.order, "enemyBoundaryClose") :: number)
				< table.find(stepShutdownEnvironment.order, "publisherCleanup") :: number
		)
		assertions.isTrue(
			(table.find(stepShutdownEnvironment.order, "publisherCleanup") :: number)
				< table.find(stepShutdownEnvironment.order, "runtimeCleanup") :: number
		)
		stepShutdownDefinition.shutdown()
		assertions.equal(stepShutdownEnvironment.publisherCleanupCount, 1)
		assertions.equal(stepShutdownEnvironment.runtimeCleanupCount, 1)

		local flushShutdownEnvironment = newEnvironment()
		local flushShutdownService = createService(flushShutdownEnvironment, configuredSelection())
		local flushShutdownDefinition = flushShutdownService:getServiceDefinition()
		startService(flushShutdownService)
		local flushShutdownBoundary = flushShutdownEnvironment.boundary :: any
		assertions.isTrue(
			expectSuccess(assertions, flushShutdownBoundary:onEnemyPass(healthyFrame(flushShutdownEnvironment, 1)))
		)
		flushShutdownEnvironment.publisherFlushHook = function()
			flushShutdownDefinition.shutdown()
		end
		assertions.isFalse(expectSuccess(assertions, flushShutdownBoundary:flushEnemyPass(1)))
		assertions.equal(flushShutdownService:getMetrics().lifecycleState, "ShuttingDown")
		table.insert(flushShutdownEnvironment.order, "enemyBoundaryClose")
		expectSuccess(
			assertions,
			flushShutdownBoundary:close(table.freeze({
				disposition = "Shutdown",
				matchId = MATCH_ID,
				enemyEpoch = ENEMY_EPOCH,
				passOrdinal = 1,
				sampleServerTime = flushShutdownEnvironment.now,
			}))
		)
		local flushShutdownMetrics = flushShutdownService:getMetrics()
		assertions.equal(flushShutdownMetrics.lifecycleState, "Shutdown")
		assertions.isFalse(flushShutdownMetrics.retainsBoundary)
		assertions.isFalse(flushShutdownMetrics.retainsPublisher)
		assertions.isFalse(flushShutdownMetrics.retainsRuntime)
		assertions.equal(flushShutdownEnvironment.detachCount, 0)
		flushShutdownDefinition.shutdown()

		local failedStepShutdownEnvironment = newEnvironment()
		failedStepShutdownEnvironment.stepMode = "failure"
		local failedStepShutdownService = createService(failedStepShutdownEnvironment, configuredSelection())
		local failedStepShutdownDefinition = failedStepShutdownService:getServiceDefinition()
		startService(failedStepShutdownService)
		local failedStepShutdownBoundary = failedStepShutdownEnvironment.boundary :: any
		failedStepShutdownEnvironment.stepHook = function()
			failedStepShutdownDefinition.shutdown()
		end
		expectError(
			assertions,
			failedStepShutdownBoundary:onEnemyPass(healthyFrame(failedStepShutdownEnvironment, 1)),
			"INTERNAL_ERROR",
			"onEnemyPass"
		)
		assertions.equal(failedStepShutdownService:getMetrics().lifecycleState, "Failed")
		expectSuccess(
			assertions,
			failedStepShutdownBoundary:close(table.freeze({
				disposition = "DependencyFault",
				matchId = MATCH_ID,
				enemyEpoch = ENEMY_EPOCH,
				passOrdinal = 1,
				sampleServerTime = failedStepShutdownEnvironment.now,
			}))
		)
		local failedStepShutdownMetrics = failedStepShutdownService:getMetrics()
		assertions.equal(failedStepShutdownMetrics.lifecycleState, "Shutdown")
		assertions.isFalse(failedStepShutdownMetrics.retainsBoundary)
		assertions.isFalse(failedStepShutdownMetrics.retainsPublisher)
		assertions.isFalse(failedStepShutdownMetrics.retainsRuntime)
		assertions.equal(failedStepShutdownEnvironment.detachCount, 0)

		local failedFlushShutdownEnvironment = newEnvironment()
		failedFlushShutdownEnvironment.publisherFlushMode = "failure"
		local failedFlushShutdownService = createService(failedFlushShutdownEnvironment, configuredSelection())
		local failedFlushShutdownDefinition = failedFlushShutdownService:getServiceDefinition()
		startService(failedFlushShutdownService)
		local failedFlushShutdownBoundary = failedFlushShutdownEnvironment.boundary :: any
		assertions.isTrue(
			expectSuccess(
				assertions,
				failedFlushShutdownBoundary:onEnemyPass(healthyFrame(failedFlushShutdownEnvironment, 1))
			)
		)
		failedFlushShutdownEnvironment.publisherFlushHook = function()
			failedFlushShutdownDefinition.shutdown()
		end
		expectError(assertions, failedFlushShutdownBoundary:flushEnemyPass(1), "INTERNAL_ERROR", "flushEnemyPass")
		assertions.equal(failedFlushShutdownService:getMetrics().lifecycleState, "Failed")
		expectSuccess(
			assertions,
			failedFlushShutdownBoundary:close(table.freeze({
				disposition = "DependencyFault",
				matchId = MATCH_ID,
				enemyEpoch = ENEMY_EPOCH,
				passOrdinal = 1,
				sampleServerTime = failedFlushShutdownEnvironment.now,
			}))
		)
		local failedFlushShutdownMetrics = failedFlushShutdownService:getMetrics()
		assertions.equal(failedFlushShutdownMetrics.lifecycleState, "Shutdown")
		assertions.isFalse(failedFlushShutdownMetrics.retainsBoundary)
		assertions.isFalse(failedFlushShutdownMetrics.retainsPublisher)
		assertions.isFalse(failedFlushShutdownMetrics.retainsRuntime)
		assertions.equal(failedFlushShutdownEnvironment.detachCount, 0)
	end),

	TestHarness.case("requires an exact immutable test dependency record and selection", function(assertions)
		local environment = newEnvironment()
		local dependencies = dependenciesFor(environment, configuredSelection())
		dependencies.extra = true
		local ok, message = pcall(function()
			(newForTests :: WaveRuntimeService.TestConstructor)(dependencies)
		end)
		assertions.isFalse(ok)
		assertions.contains(message, "INVALID_DEPENDENCIES")

		local second = newEnvironment()
		local mutableSelectionDependencies = dependenciesFor(second, configuredSelection())
		mutableSelectionDependencies.selection = {
			kind = "AuthoredFinite",
			difficultyId = WaveFixtures.PRIMARY_DIFFICULTY_ID,
		}
		local selectionOk, selectionMessage = pcall(function()
			(newForTests :: WaveRuntimeService.TestConstructor)(mutableSelectionDependencies)
		end)
		assertions.isFalse(selectionOk)
		assertions.contains(selectionMessage, "INVALID_DEPENDENCIES")

		local reentryEnvironment = newEnvironment()
		local reentryService = createService(reentryEnvironment, configuredSelection())
		startService(reentryService)
		reentryEnvironment.voteHook = function(runtime: any): unknown
			reentryEnvironment.reentryResult = reentryService:submitSkipVote(92, MATCH_ID, 1)
			return Result.ok(makeVoteSnapshot(reentryEnvironment, runtime))
		end
		local outerVote = expectSuccess(assertions, reentryService:submitSkipVote(91, MATCH_ID, 1))
		assertions.equal(outerVote.waveRevision, 2)
		expectError(assertions, reentryEnvironment.reentryResult, "REENTRANT", "submitSkipVote")
		assertions.equal(reentryService:getMetrics().lifecycleState, "Started")
		assertions.isTrue(reentryService:getMetrics().callbacksEnabled)
		assertions.equal(reentryEnvironment.publisherQueueCalls, 2)
		reentryService:getServiceDefinition().shutdown()

		local triggerReentryEnvironment = newEnvironment()
		triggerReentryEnvironment.isStudio = true
		local triggerReentryService = createService(triggerReentryEnvironment, dormantSelection())
		startService(triggerReentryService)
		local triggerReentryHandler = triggerReentryEnvironment.triggerHandler :: any
		triggerReentryEnvironment.validationHook = function()
			triggerReentryEnvironment.reentryResult = triggerReentryHandler({ operation = "Diagnostics" })
		end
		expectSuccess(assertions, triggerReentryHandler({ operation = "Activate", scenario = "Empty" }))
		expectError(assertions, triggerReentryEnvironment.reentryResult, "REENTRANT", "runtimeTrigger")
		assertions.equal(triggerReentryEnvironment.validationCount, 1)
		triggerReentryService:getServiceDefinition().shutdown()

		local validationFaultEnvironment = newEnvironment()
		validationFaultEnvironment.isStudio = true
		validationFaultEnvironment.validationMode = "failure"
		local validationFaultService = createService(validationFaultEnvironment, dormantSelection())
		startService(validationFaultService)
		expectError(
			assertions,
			(validationFaultEnvironment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" }),
			"INTERNAL_ERROR",
			"runtimeTrigger"
		)
		assertions.equal(validationFaultEnvironment.validationCount, 1)
		assertions.equal(validationFaultEnvironment.baseCatalogInstallCalls, 0)
		assertions.equal(validationFaultEnvironment.triggerDestroyCount, 1)
		assertions.equal(validationFaultService:getMetrics().lifecycleState, "Failed")
		assertions.equal(validationFaultService:getMetrics().studioTriggerCount, 0)
		validationFaultService:getServiceDefinition().shutdown()

		local preflightFaultEnvironment = newEnvironment()
		preflightFaultEnvironment.isStudio = true
		preflightFaultEnvironment.lifecycleState = "Loading"
		preflightFaultEnvironment.recipients = table.freeze({})
		local preflightFaultService = createService(preflightFaultEnvironment, dormantSelection())
		startService(preflightFaultService)
		expectError(
			assertions,
			(preflightFaultEnvironment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" }),
			"UNAVAILABLE",
			"runtimeTrigger"
		)
		assertions.equal(preflightFaultEnvironment.validationCount, 0)
		assertions.equal(preflightFaultEnvironment.baseCatalogInstallCalls, 0)
		assertions.equal(preflightFaultEnvironment.triggerDestroyCount, 0)
		assertions.equal(preflightFaultService:getMetrics().lifecycleState, "Started")
		assertions.isFalse(preflightFaultService:getMetrics().studioActivationAttempted)
		preflightFaultEnvironment.lifecycleState = "ReadyCheck"
		expectError(
			assertions,
			(preflightFaultEnvironment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" }),
			"UNAVAILABLE",
			"runtimeTrigger"
		)
		assertions.equal(preflightFaultEnvironment.validationCount, 0)
		assertions.equal(preflightFaultEnvironment.triggerDestroyCount, 0)
		local retryConnection, retryRecipient = makeRecipient(41)
		preflightFaultEnvironment.recipients = table.freeze({ retryRecipient })
		local retried = expectSuccess(
			assertions,
			(preflightFaultEnvironment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" })
		)
		assertions.equal(retried.matchId, MATCH_ID)
		assertions.equal(preflightFaultEnvironment.readySubmissionCalls, 1)
		assertions.isTrue(retryConnection.alive)
		assertions.equal(preflightFaultEnvironment.lifecycleState, "WaveActive")
		preflightFaultService:getServiceDefinition().shutdown()

		local triggerFaultEnvironment = newEnvironment()
		triggerFaultEnvironment.isStudio = true
		triggerFaultEnvironment.triggerCreateMode = "malformed"
		local triggerFaultService = createService(triggerFaultEnvironment, dormantSelection())
		local triggerFaultDefinition = triggerFaultService:getServiceDefinition()
		triggerFaultDefinition.initialize()
		local triggerStarted, triggerMessage = pcall(function()
			triggerFaultDefinition.start()
		end)
		assertions.isFalse(triggerStarted)
		assertions.contains(triggerMessage, "STUDIO_TRIGGER_INSTALL_FAILED")
		assertions.equal(triggerFaultEnvironment.triggerCreateCalls, 1)
		assertions.equal(triggerFaultService:getMetrics().lifecycleState, "Failed")
		triggerFaultDefinition.shutdown()

		for _, studioCheckMode in { "throw", "yield", "malformed" } do
			local studioCheckEnvironment = newEnvironment()
			studioCheckEnvironment.isStudio = true
			studioCheckEnvironment.studioCheckMode = studioCheckMode
			local studioCheckService = createService(studioCheckEnvironment, dormantSelection())
			local studioCheckDefinition = studioCheckService:getServiceDefinition()
			studioCheckDefinition.initialize()
			local started, studioCheckMessage = pcall(function()
				studioCheckDefinition.start()
			end)
			assertions.isFalse(started)
			assertions.contains(studioCheckMessage, "STUDIO_TRIGGER_INSTALL_FAILED")
			assertions.equal(studioCheckEnvironment.triggerCreateCalls, 0)
			assertions.equal(studioCheckEnvironment.triggerDestroyCount, 0)
			studioCheckDefinition.shutdown()
		end

		for _, triggerCreateMode in { "throw", "yield", "malformed", "collision" } do
			local creatorEnvironment = newEnvironment()
			creatorEnvironment.isStudio = true
			creatorEnvironment.triggerCreateMode = triggerCreateMode
			local creatorService = createService(creatorEnvironment, dormantSelection())
			local creatorDefinition = creatorService:getServiceDefinition()
			creatorDefinition.initialize()
			local started, creatorMessage = pcall(function()
				creatorDefinition.start()
			end)
			assertions.isFalse(started)
			assertions.contains(creatorMessage, "STUDIO_TRIGGER_INSTALL_FAILED")
			assertions.equal(creatorEnvironment.triggerCreateCalls, 1)
			assertions.equal(creatorEnvironment.triggerDestroyCount, 0)
			assertions.equal(creatorService:getMetrics().studioTriggerCount, 0)
			creatorDefinition.shutdown()
		end

		local deferredEnvironment = newEnvironment()
		deferredEnvironment.isStudio = true
		local deferredService = createService(deferredEnvironment, dormantSelection())
		startService(deferredService)
		deferredEnvironment.validationHook = function()
			deferredService:getServiceDefinition().shutdown()
		end
		local deferredResult = (deferredEnvironment.triggerHandler :: any)({
			operation = "Activate",
			scenario = "Empty",
		})
		assertions.isTrue(deferredResult.ok)
		assertions.equal(deferredEnvironment.triggerDestroyCount, 1)
		local deferredMetrics = deferredService:getMetrics()
		assertions.equal(deferredMetrics.lifecycleState, "Shutdown")
		assertions.equal(deferredMetrics.studioTriggerCount, 0)
		assertions.equal(deferredMetrics.studioValidationCount, 0)
		assertions.equal(deferredMetrics.studioSpawnEvidenceCount, 0)
	end),

	TestHarness.case("authenticates the exact Studio Tower boundary and opaque handles", function(assertions)
		local productionEnvironment = newEnvironment()
		local productionService = createService(productionEnvironment, dormantSelection())
		startService(productionService)
		local productionRig = newTowerBoundaryRig(productionEnvironment)
		expectError(
			assertions,
			productionService:installStudioTowerBoundary(makeTowerBoundaryAdapter(productionRig)),
			"UNAVAILABLE",
			"installStudioTowerBoundary"
		)
		productionService:getServiceDefinition().shutdown()

		local environment = newEnvironment()
		environment.isStudio = true
		local service = createService(environment, dormantSelection())
		startService(service)
		local rig = newTowerBoundaryRig(environment)
		local adapter = makeTowerBoundaryAdapter(rig)

		local mutableAdapter = table.clone(adapter)
		expectError(
			assertions,
			service:installStudioTowerBoundary(mutableAdapter),
			"INVALID_ARGUMENT",
			"installStudioTowerBoundary"
		)
		local missingMethod = table.clone(adapter)
		missingMethod.closeFromWave = nil
		table.freeze(missingMethod)
		expectError(
			assertions,
			service:installStudioTowerBoundary(missingMethod),
			"INVALID_ARGUMENT",
			"installStudioTowerBoundary"
		)
		local wrongMethod = table.clone(adapter)
		wrongMethod.getStudioDiagnostics = true
		table.freeze(wrongMethod)
		expectError(
			assertions,
			service:installStudioTowerBoundary(wrongMethod),
			"INVALID_ARGUMENT",
			"installStudioTowerBoundary"
		)
		local extraMethod = table.clone(adapter)
		extraMethod.extra = function() end
		table.freeze(extraMethod)
		expectError(
			assertions,
			service:installStudioTowerBoundary(extraMethod),
			"INVALID_ARGUMENT",
			"installStudioTowerBoundary"
		)
		local metatableAdapter = table.clone(adapter)
		setmetatable(metatableAdapter, {})
		table.freeze(metatableAdapter)
		expectError(
			assertions,
			service:installStudioTowerBoundary(metatableAdapter),
			"INVALID_ARGUMENT",
			"installStudioTowerBoundary"
		)

		local handle = expectSuccess(assertions, service:installStudioTowerBoundary(adapter))
		assertions.isTrue(table.isfrozen(handle))
		assertions.equal(next(handle), nil)
		assertions.equal(service:getMetrics().studioTowerBoundaryCount, 1)
		expectError(
			assertions,
			service:installStudioTowerBoundary(adapter),
			"UNAVAILABLE",
			"installStudioTowerBoundary"
		)
		expectError(
			assertions,
			service:detachStudioTowerBoundary(table.freeze({})),
			"INVALID_ARGUMENT",
			"detachStudioTowerBoundary"
		)
		assertions.isTrue(expectSuccess(assertions, service:detachStudioTowerBoundary(handle)))
		assertions.isFalse(expectSuccess(assertions, service:detachStudioTowerBoundary(handle)))
		assertions.equal(service:getMetrics().studioTowerBoundaryCount, 0)

		local secondRig = newTowerBoundaryRig(environment)
		local secondHandle =
			expectSuccess(assertions, service:installStudioTowerBoundary(makeTowerBoundaryAdapter(secondRig)))
		assertions.notEqual(secondHandle, handle)
		service:getServiceDefinition().shutdown()
		assertions.equal(secondRig.closeCount, 1)
		assertions.equal(service:getMetrics().studioTowerBoundaryCount, 0)
		expectError(
			assertions,
			service:detachStudioTowerBoundary(handle),
			"INVALID_ARGUMENT",
			"detachStudioTowerBoundary"
		)
		expectError(
			assertions,
			service:detachStudioTowerBoundary(secondHandle),
			"INVALID_ARGUMENT",
			"detachStudioTowerBoundary"
		)
	end),

	TestHarness.case(
		"merges Tower fixtures once and routes fixed evidence with detached diagnostics",
		function(assertions)
			local environment = newEnvironment()
			environment.isStudio = true
			local service = createService(environment, dormantSelection())
			startService(service)
			local rig = newTowerBoundaryRig(environment)
			local handle = expectSuccess(assertions, service:installStudioTowerBoundary(makeTowerBoundaryAdapter(rig)))
			local invoke = environment.triggerHandler :: any

			local activation = expectSuccess(assertions, invoke({ operation = "Activate", scenario = "Primary" }))
			assertions.equal(activation.matchId, MATCH_ID)
			assertions.equal(environment.validationCount, 1)
			assertions.equal(rig.buildCount, 1)
			assertions.equal(rig.prepareCount, 1)
			assertions.equal(rig.commitCount, 1)
			assertions.equal(rig.matchId, MATCH_ID)
			assertions.equal(rig.configuration, environment.boundConfiguration)

			local sources = environment.validationSources
			assertions.equal(#sources.assets, 8)
			assertions.equal(#sources.towers, 3)
			assertions.equal(sources.towers[1].id, TowerFixtures.SINGLE_TOWER_ID)
			assertions.equal(sources.towers[2].id, TowerFixtures.SPLASH_TOWER_ID)
			assertions.equal(sources.towers[3].id, TowerFixtures.SUPPORT_TOWER_ID)
			assertions.notEqual(sources.assets[3], rig.builtSources.assets[1])
			assertions.notEqual(sources.towers[1], rig.builtSources.towers[1])
			assertions.isTrue(
				findOrder(environment.order, "towerBuild") < findOrder(environment.order, "validateConfiguration")
			)
			assertions.isTrue(
				findOrder(environment.order, "validateConfiguration") < findOrder(environment.order, "towerPrepare")
			)
			assertions.isTrue(
				findOrder(environment.order, "towerPrepare") < findOrder(environment.order, "beginActivation")
			)
			assertions.isTrue(
				findOrder(environment.order, "beginActivation") < findOrder(environment.order, "towerCommit")
			)
			assertions.isTrue(
				findOrder(environment.order, "towerCommit") < findOrder(environment.order, "initializeBase")
			)

			local fixedOperations = {
				"TowerCreateNext",
				"TowerRemoveVisualLast",
				"TowerRecreateVisualLast",
				"TowerRemoveLast",
				"TowerInvalidTemplate",
			}
			for _, operation in fixedOperations do
				local receipt = expectSuccess(assertions, invoke({ operation = operation }))
				assertions.equal(receipt.operation, operation)
			end
			assertions.equal(rig.dispatchCount, 5)
			expectError(assertions, invoke({ operation = "TowerUnknown" }), "INVALID_ARGUMENT", "runtimeTrigger")
			expectError(
				assertions,
				invoke({ operation = "TowerCreateNext", extra = true }),
				"INVALID_ARGUMENT",
				"runtimeTrigger"
			)
			expectError(
				assertions,
				invoke({ operation = "TowerCreateNext" }, true),
				"INVALID_ARGUMENT",
				"runtimeTrigger"
			)
			assertions.equal(rig.dispatchCount, 5)

			local diagnostics = expectSuccess(assertions, invoke({ operation = "Diagnostics" }))
			assertions.notEqual(diagnostics.tower, rig.diagnostics)
			assertions.isTrue(table.isfrozen(diagnostics.tower))
			local placement = diagnostics.tower.runtimeTowers[1].placementCFrame
			assertions.isTrue(table.isfrozen(placement))
			assertions.equal(placement.x, 12)
			assertions.equal(placement.y, 34)
			assertions.equal(placement.z, -56)
			local componentCount = 0
			for _ in placement do
				componentCount += 1
			end
			assertions.equal(componentCount, 12)
			local metrics = service:getMetrics()
			assertions.equal(metrics.studioTowerBoundaryCount, 1)
			assertions.equal(metrics.studioTowerPreparedTokenCount, 0)
			assertions.equal(metrics.studioTowerBuildCount, 1)
			assertions.equal(metrics.studioTowerPrepareCount, 1)
			assertions.equal(metrics.studioTowerCommitCount, 1)
			assertions.equal(metrics.studioTowerDispatchCount, 5)
			assertions.equal(metrics.studioTowerDiagnosticsCount, 1)

			local residue = expectSuccess(assertions, invoke({ operation = "TowerCleanup" }))
			assertions.equal(residue.state, "Cleaned")
			assertions.equal(residue.participantObserverCount, 0)
			assertions.equal(residue.runtimeTowerCount, 0)
			assertions.equal(residue.liveModelCount, 0)
			assertions.equal(residue.connectionCount, 0)
			assertions.equal(rig.dispatches[6], "TowerCleanup")
			assertions.equal(rig.dispatchCount, 6)
			assertions.equal(rig.closeCount, 0)
			assertions.equal(service:getMetrics().studioTowerBoundaryCount, 0)
			expectError(assertions, invoke({ operation = "TowerCreateNext" }), "UNAVAILABLE", "runtimeTrigger")
			expectError(
				assertions,
				service:detachStudioTowerBoundary(handle),
				"INVALID_ARGUMENT",
				"detachStudioTowerBoundary"
			)
			service:getServiceDefinition().shutdown()
			assertions.equal(rig.closeCount, 0)
		end
	),

	TestHarness.case(
		"orders Tower prepare and commit faults before Wave truth and closes in reverse order",
		function(assertions)
			local prepareEnvironment = newEnvironment()
			prepareEnvironment.isStudio = true
			local prepareService = createService(prepareEnvironment, dormantSelection())
			startService(prepareService)
			local prepareRig = newTowerBoundaryRig(prepareEnvironment)
			prepareRig.prepareMode = "failure"
			local prepareHandle = expectSuccess(
				assertions,
				prepareService:installStudioTowerBoundary(makeTowerBoundaryAdapter(prepareRig))
			)
			expectError(
				assertions,
				(prepareEnvironment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" }),
				"INTERNAL_ERROR",
				"runtimeTrigger"
			)
			assertions.equal(prepareEnvironment.validationCount, 1)
			assertions.equal(prepareRig.prepareCount, 1)
			assertions.equal(prepareRig.commitCount, 0)
			assertions.equal(prepareRig.closeCount, 1)
			assertions.isNil(table.find(prepareEnvironment.order, "beginActivation"))
			assertions.isNil(table.find(prepareEnvironment.order, "initializeBase"))
			assertions.equal(prepareService:getMetrics().lifecycleState, "Failed")
			expectError(
				assertions,
				prepareService:detachStudioTowerBoundary(prepareHandle),
				"INVALID_ARGUMENT",
				"detachStudioTowerBoundary"
			)
			prepareService:getServiceDefinition().shutdown()

			local commitEnvironment = newEnvironment()
			commitEnvironment.isStudio = true
			local commitService = createService(commitEnvironment, dormantSelection())
			startService(commitService)
			local commitRig = newTowerBoundaryRig(commitEnvironment)
			commitRig.commitMode = "failure"
			expectSuccess(assertions, commitService:installStudioTowerBoundary(makeTowerBoundaryAdapter(commitRig)))
			expectError(
				assertions,
				(commitEnvironment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" }),
				"INTERNAL_ERROR",
				"runtimeTrigger"
			)
			assertions.equal(commitRig.prepareCount, 1)
			assertions.equal(commitRig.commitCount, 1)
			assertions.equal(commitRig.closeCount, 1)
			assertions.equal(commitEnvironment.lifecycleState, "PreWave")
			assertions.isTrue(
				findOrder(commitEnvironment.order, "beginActivation")
					< findOrder(commitEnvironment.order, "towerCommit")
			)
			assertions.isTrue(
				findOrder(commitEnvironment.order, "towerCommit")
					< findOrder(commitEnvironment.order, "rollbackActivation")
			)
			assertions.isNil(table.find(commitEnvironment.order, "initializeBase"))
			assertions.isNil(table.find(commitEnvironment.order, "commitActivation"))
			commitService:getServiceDefinition().shutdown()

			local releaseEnvironment = newEnvironment()
			releaseEnvironment.isStudio = true
			local releaseService = createService(releaseEnvironment, dormantSelection())
			startService(releaseService)
			local releaseRig = newTowerBoundaryRig(releaseEnvironment)
			local releaseHandle = expectSuccess(
				assertions,
				releaseService:installStudioTowerBoundary(makeTowerBoundaryAdapter(releaseRig))
			)
			expectSuccess(
				assertions,
				(releaseEnvironment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" })
			)
			releaseService:getServiceDefinition().shutdown()
			assertions.equal(releaseRig.closeCount, 1)
			assertions.isTrue(
				findOrder(releaseEnvironment.order, "towerClose")
					< findOrder(releaseEnvironment.order, "destroyStudioTrigger")
			)
			assertions.isTrue(
				findOrder(releaseEnvironment.order, "towerClose")
					< findOrder(releaseEnvironment.order, "detachBoundary")
			)
			assertions.equal(releaseService:getMetrics().studioTowerBoundaryCount, 0)
			expectError(
				assertions,
				releaseService:detachStudioTowerBoundary(releaseHandle),
				"INVALID_ARGUMENT",
				"detachStudioTowerBoundary"
			)
		end
	),

	TestHarness.case("fails closed on Tower callback shape yield throw and reentry faults", function(assertions)
		for _, mode in { "wrong-shape", "yield" } do
			local environment = newEnvironment()
			environment.isStudio = true
			local service = createService(environment, dormantSelection())
			startService(service)
			local rig = newTowerBoundaryRig(environment)
			if mode == "wrong-shape" then
				rig.buildValue = freezeTree({ assets = {}, towers = {} })
			else
				rig.buildMode = mode
			end
			expectSuccess(assertions, service:installStudioTowerBoundary(makeTowerBoundaryAdapter(rig)))
			expectError(
				assertions,
				(environment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" }),
				"INTERNAL_ERROR",
				"runtimeTrigger"
			)
			assertions.equal(environment.validationCount, 0)
			assertions.equal(rig.closeCount, 1)
			assertions.equal(service:getMetrics().studioTowerBoundaryCount, 0)
			service:getServiceDefinition().shutdown()
		end

		local throwEnvironment = newEnvironment()
		throwEnvironment.isStudio = true
		local throwService = createService(throwEnvironment, dormantSelection())
		startService(throwService)
		local throwRig = newTowerBoundaryRig(throwEnvironment)
		throwRig.prepareMode = "throw"
		expectSuccess(assertions, throwService:installStudioTowerBoundary(makeTowerBoundaryAdapter(throwRig)))
		expectError(
			assertions,
			(throwEnvironment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" }),
			"INTERNAL_ERROR",
			"runtimeTrigger"
		)
		assertions.equal(throwRig.closeCount, 1)
		throwService:getServiceDefinition().shutdown()

		local reentryEnvironment = newEnvironment()
		reentryEnvironment.isStudio = true
		local reentryService = createService(reentryEnvironment, dormantSelection())
		startService(reentryService)
		local reentryRig = newTowerBoundaryRig(reentryEnvironment)
		local reentryHandle =
			expectSuccess(assertions, reentryService:installStudioTowerBoundary(makeTowerBoundaryAdapter(reentryRig)))
		expectSuccess(
			assertions,
			(reentryEnvironment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" })
		)
		local nestedResult: any = nil
		reentryRig.dispatchHook = function()
			nestedResult = reentryService:detachStudioTowerBoundary(reentryHandle)
		end
		expectError(
			assertions,
			(reentryEnvironment.triggerHandler :: any)({ operation = "TowerCreateNext" }),
			"INTERNAL_ERROR",
			"runtimeTrigger"
		)
		expectError(assertions, nestedResult, "REENTRANT", "detachStudioTowerBoundary")
		assertions.equal(reentryRig.closeCount, 1)
		assertions.equal(reentryService:getMetrics().studioTowerBoundaryCount, 0)
		reentryService:getServiceDefinition().shutdown()

		for _, mode in { "failure", "throw", "yield" } do
			local cleanupEnvironment = newEnvironment()
			cleanupEnvironment.isStudio = true
			local cleanupService = createService(cleanupEnvironment, dormantSelection())
			startService(cleanupService)
			local cleanupRig = newTowerBoundaryRig(cleanupEnvironment)
			local cleanupHandle = expectSuccess(
				assertions,
				cleanupService:installStudioTowerBoundary(makeTowerBoundaryAdapter(cleanupRig))
			)
			expectSuccess(
				assertions,
				(cleanupEnvironment.triggerHandler :: any)({ operation = "Activate", scenario = "Primary" })
			)
			cleanupRig.dispatchMode = mode
			local cleanupResult = (cleanupEnvironment.triggerHandler :: any)({ operation = "TowerCleanup" })
			if mode == "failure" then
				expectError(assertions, cleanupResult, "DISPATCH_FAILED", nil :: any)
			else
				expectError(assertions, cleanupResult, "INTERNAL_ERROR", "runtimeTrigger")
			end
			assertions.equal(cleanupService:getMetrics().studioTowerBoundaryCount, 0)
			assertions.equal(cleanupRig.closeCount, 0)
			expectError(
				assertions,
				cleanupService:detachStudioTowerBoundary(cleanupHandle),
				"INVALID_ARGUMENT",
				"detachStudioTowerBoundary"
			)
			cleanupService:getServiceDefinition().shutdown()
		end

		local closeEnvironment = newEnvironment()
		closeEnvironment.isStudio = true
		local closeService = createService(closeEnvironment, dormantSelection())
		startService(closeService)
		local closeRig = newTowerBoundaryRig(closeEnvironment)
		closeRig.closeMode = "throw"
		local closeHandle =
			expectSuccess(assertions, closeService:installStudioTowerBoundary(makeTowerBoundaryAdapter(closeRig)))
		local closed, closeMessage = pcall(function()
			closeService:getServiceDefinition().shutdown()
		end)
		assertions.isFalse(closed)
		assertions.contains(closeMessage, "CLEANUP_FAILED")
		assertions.equal(closeRig.closeCount, 1)
		assertions.equal(closeService:getMetrics().studioTowerBoundaryCount, 0)
		expectError(
			assertions,
			closeService:detachStudioTowerBoundary(closeHandle),
			"INVALID_ARGUMENT",
			"detachStudioTowerBoundary"
		)
	end),
})
