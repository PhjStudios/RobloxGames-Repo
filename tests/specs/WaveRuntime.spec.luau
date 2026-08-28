--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local WaveFixtures = require(script.Parent.Parent.Fixtures.WaveFixtures)

local Shared = game:GetService("ReplicatedStorage").Shared
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local MatchProtocol = require(Shared.match.MatchProtocol)
local WaveProtocol = require(Shared.match.WaveProtocol)
local Result = require(Shared.util.Result)

local WaveRuntime = require(script.Parent.Parent.ProductionServerWaves.WaveRuntime)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase11-wave-runtime-spec"
local OTHER_MATCH_ID = "match:phase11-wave-runtime-other"
local ENEMY_EPOCH = 1
local PRIVATE_FAILURE = table.freeze({ code = "PRIVATE_WAVE_RUNTIME_SPEC_FAILURE" })
local DEFAULT_FIXTURE = WaveFixtures.createAuthenticatedFixture()

type Mode = "success" | "failure" | "false" | "throw" | "yield" | "malformed"
type SpawnMode =
	"success"
	| "replication-failure"
	| "uncommitted"
	| "throw"
	| "yield"
	| "malformed"
	| "reenter"
	| "cleanup"

type Environment = {
	runtime: any?,
	configuration: any,
	runtimeMap: any,
	difficultyId: string,
	now: number,
	lifecycleState: string,
	lifecycleRevision: number,
	lifecycleMode: Mode,
	participants: { any },
	lifecycleReadCount: number,
	lifecycleReadHook: ((Environment, number) -> ())?,
	baseInitializeMode: Mode,
	baseStateMode: Mode,
	bindMode: Mode,
	beginMode: Mode,
	commitMode: Mode,
	commitRevisionDelta: number,
	commitParticipants: { any }?,
	rollbackMode: Mode,
	clockMode: Mode,
	commitPublished: boolean,
	baseDefeatPending: boolean,
	baseDefeated: boolean,
	order: { string },
	recordAuthorityReads: boolean,
	activationToken: any,
	rollbackCount: number,
	baseDifficulty: any?,
	boundConfiguration: any?,
	boundDifficulty: any?,
	passOrdinal: number,
	spawnMode: SpawnMode,
	nextRuntimeEnemyId: number,
	spawnEvents: { any },
	spawnRecords: { [number]: any },
	authenticatedOutcomes: { [any]: boolean },
	innerResult: any?,
}

local function expectSuccess(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("[ATD_TEST][code=WAVE_RUNTIME_EXPECTED_SUCCESS]", 0)
	end
	return result.value
end

local function expectError(assertions: Assertions, result: any, code: string, operation: string)
	assertions.isFalse(result.ok)
	if result.ok then
		error("[ATD_TEST][code=WAVE_RUNTIME_EXPECTED_ERROR]", 0)
	end
	assertions.equal(result.error.code, code)
	assertions.equal(result.error.operation, operation)
end

local function assertDeepFrozen(assertions: Assertions, value: unknown, seen: { [any]: boolean }?)
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
		assertDeepFrozen(assertions, key, visited)
		assertDeepFrozen(assertions, child, visited)
	end
end

local function frozenClone(value: any, seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end
	local visited = seen or {}
	local existing = visited[value]
	if existing ~= nil then
		return existing
	end
	local copy = {}
	visited[value] = copy
	for key, child in next, value do
		copy[frozenClone(key, visited)] = frozenClone(child, visited)
	end
	return table.freeze(copy)
end

local function validateConfiguration(assertions: Assertions, rawSources: any): any
	local result = ConfigurationValidator.validate(rawSources)
	assertions.isTrue(result.ok)
	if not result.ok then
		error("[ATD_TEST][code=WAVE_RUNTIME_FIXTURE_VALIDATION_FAILED]", 0)
	end
	assertions.isTrue(ConfigurationValidator.isValidatedConfiguration(result.value))
	return result.value
end

local function capacityConfiguration(assertions: Assertions, totalEvents: number): any
	local rawSources = WaveFixtures.rawSources()
	local overlap = rawSources.waves[2]
	local largeGroup = overlap.waves[1].groups[1]
	largeGroup.count = totalEvents - 2
	largeGroup.startDelaySeconds = 0
	largeGroup.spawnIntervalSeconds = 0.5
	overlap.waves[1].deadlinePolicy = "AllowScheduledOverlap"
	return validateConfiguration(assertions, rawSources)
end

local function finalOverlapConfiguration(assertions: Assertions): any
	local rawSources = WaveFixtures.rawSources()
	local finalWave = rawSources.waves[2].waves[2]
	finalWave.deadlinePolicy = "AllowScheduledOverlap"
	finalWave.groups[1].count = 2
	finalWave.groups[1].startDelaySeconds = 0
	finalWave.groups[1].spawnIntervalSeconds = 10
	return validateConfiguration(assertions, rawSources)
end

local function emptyFirstWaveConfiguration(assertions: Assertions): any
	local rawSources = WaveFixtures.rawSources()
	local firstWave = rawSources.waves[2].waves[1]
	firstWave.deadlinePolicy = "AllSpawnsByDeadline"
	firstWave.groups = {}
	return validateConfiguration(assertions, rawSources)
end

local function zeroDelayConfiguration(assertions: Assertions): any
	local rawSources = WaveFixtures.rawSources()
	rawSources.difficulties[1].timing.skipVoteMinimumDelaySeconds = 0
	rawSources.difficulties[2].timing.skipVoteMinimumDelaySeconds = 0
	return validateConfiguration(assertions, rawSources)
end

local function resultForMode(mode: Mode, value: any): any
	if mode == "failure" then
		return Result.err(PRIVATE_FAILURE)
	elseif mode == "false" then
		return Result.ok(false)
	elseif mode == "throw" then
		error("PRIVATE_WAVE_RUNTIME_SPEC_FAILURE", 0)
	elseif mode == "yield" then
		coroutine.yield()
	elseif mode == "malformed" then
		return table.freeze({ malformed = true })
	end
	return Result.ok(value)
end

local function currentMatchSnapshot(environment: Environment): any
	local deadline = if environment.lifecycleState == "ReadyCheck" then environment.now + 45 else nil
	local validated = MatchProtocol.validateMatchSnapshot({
		matchId = MATCH_ID,
		revision = environment.lifecycleRevision,
		state = environment.lifecycleState,
		deadlineServerTime = deadline,
		participants = environment.participants,
	})
	if not validated.ok then
		error("[ATD_TEST][code=WAVE_RUNTIME_MATCH_SNAPSHOT_INVALID]", 0)
	end
	return validated.value
end

local function newEnvironment(
	configuration: any,
	runtimeMap: any,
	difficultyId: string,
	options: { [string]: any }?
): Environment
	local overrides = options or {}
	return {
		runtime = nil,
		configuration = configuration,
		runtimeMap = runtimeMap,
		difficultyId = difficultyId,
		now = overrides.now or 100,
		lifecycleState = overrides.lifecycleState or "PreWave",
		lifecycleRevision = 3,
		lifecycleMode = overrides.lifecycleMode or "success",
		participants = overrides.participants or {},
		lifecycleReadCount = 0,
		lifecycleReadHook = nil,
		baseInitializeMode = overrides.baseInitializeMode or "success",
		baseStateMode = overrides.baseStateMode or "success",
		bindMode = overrides.bindMode or "success",
		beginMode = overrides.beginMode or "success",
		commitMode = overrides.commitMode or "success",
		commitRevisionDelta = if overrides.commitRevisionDelta == nil then 1 else overrides.commitRevisionDelta,
		commitParticipants = overrides.commitParticipants,
		rollbackMode = overrides.rollbackMode or "success",
		clockMode = overrides.clockMode or "success",
		commitPublished = if overrides.commitPublished == nil then true else overrides.commitPublished,
		baseDefeatPending = overrides.baseDefeatPending == true,
		baseDefeated = overrides.baseDefeated == true,
		order = {},
		recordAuthorityReads = overrides.recordAuthorityReads == true,
		activationToken = table.freeze({ kind = "WaveActivationToken" }),
		rollbackCount = 0,
		baseDifficulty = nil,
		boundConfiguration = nil,
		boundDifficulty = nil,
		passOrdinal = 0,
		spawnMode = overrides.spawnMode or "success",
		nextRuntimeEnemyId = 1,
		spawnEvents = {},
		spawnRecords = {},
		authenticatedOutcomes = {},
		innerResult = nil,
	}
end

local function dependenciesFor(environment: Environment): any
	return {
		clock = function(): unknown
			table.insert(environment.order, "clock")
			if environment.clockMode == "failure" then
				return 0 / 0
			elseif environment.clockMode == "throw" then
				error("PRIVATE_WAVE_RUNTIME_SPEC_FAILURE", 0)
			elseif environment.clockMode == "yield" then
				coroutine.yield()
			elseif environment.clockMode == "malformed" then
				return "not-a-clock"
			end
			return environment.now
		end,
		isRuntimeMapSnapshot = function(value: unknown): unknown
			return value == environment.runtimeMap
		end,
		initializeBase = function(difficulty: any): unknown
			table.insert(environment.order, "base")
			environment.baseDifficulty = difficulty
			return resultForMode(environment.baseInitializeMode, true)
		end,
		bindDifficulty = function(configuration: any, difficulty: any): unknown
			table.insert(environment.order, "bind")
			environment.boundConfiguration = configuration
			environment.boundDifficulty = difficulty
			return resultForMode(environment.bindMode, true)
		end,
		beginWaveActivation = function(matchId: string): unknown
			table.insert(environment.order, "begin")
			if matchId ~= MATCH_ID then
				return Result.err(PRIVATE_FAILURE)
			end
			return resultForMode(environment.beginMode, environment.activationToken)
		end,
		commitWaveActivation = function(token: unknown): unknown
			table.insert(environment.order, "commit")
			if token ~= environment.activationToken then
				return Result.err(PRIVATE_FAILURE)
			end
			if environment.commitMode ~= "success" then
				return resultForMode(environment.commitMode, nil)
			end
			environment.lifecycleState = "WaveActive"
			environment.lifecycleRevision += environment.commitRevisionDelta
			if environment.commitParticipants ~= nil then
				environment.participants = environment.commitParticipants
			end
			return Result.ok(table.freeze({
				committed = true,
				published = environment.commitPublished,
				snapshot = currentMatchSnapshot(environment),
			}))
		end,
		rollbackWaveActivation = function(token: unknown): unknown
			table.insert(environment.order, "rollback")
			if token == environment.activationToken then
				environment.rollbackCount += 1
			end
			return resultForMode(environment.rollbackMode, true)
		end,
		getLifecycleSnapshot = function(): unknown
			environment.lifecycleReadCount += 1
			if environment.lifecycleReadHook ~= nil then
				environment.lifecycleReadHook(environment, environment.lifecycleReadCount)
			end
			if environment.recordAuthorityReads then
				table.insert(environment.order, "lifecycle")
			end
			return resultForMode(environment.lifecycleMode, currentMatchSnapshot(environment))
		end,
		getBaseDefeatState = function(): unknown
			if environment.baseStateMode == "failure" then
				return nil
			elseif environment.baseStateMode == "throw" then
				error("PRIVATE_WAVE_RUNTIME_SPEC_FAILURE", 0)
			elseif environment.baseStateMode == "yield" then
				coroutine.yield()
			elseif environment.baseStateMode == "malformed" then
				return table.freeze({ defeatPending = false })
			end
			return table.freeze({
				defeatPending = environment.baseDefeatPending,
				defeated = environment.baseDefeated,
			})
		end,
		isAuthenticatedTerminalOutcome = function(value: unknown): unknown
			return environment.authenticatedOutcomes[value] == true
		end,
	}
end

local function createRig(
	assertions: Assertions,
	configurationValue: any?,
	runtimeMapValue: any?,
	difficultyIdValue: string?,
	options: { [string]: any }?
): (any, Environment)
	local configuration = configurationValue or DEFAULT_FIXTURE.configuration
	local runtimeMap = runtimeMapValue or DEFAULT_FIXTURE.runtimeMap
	local difficultyId = difficultyIdValue or WaveFixtures.PRIMARY_DIFFICULTY_ID
	local environment = newEnvironment(configuration, runtimeMap, difficultyId, options)
	local created =
		WaveRuntime.new(configuration, runtimeMap, MATCH_ID, ENEMY_EPOCH, difficultyId, dependenciesFor(environment))
	local runtime = expectSuccess(assertions, created)
	environment.runtime = runtime
	return runtime, environment
end

local function spawnCallback(environment: Environment, sampleServerTime: number): (any) -> unknown
	return function(event: any): unknown
		table.insert(environment.spawnEvents, event)
		local mode = environment.spawnMode
		if mode == "throw" then
			error("PRIVATE_WAVE_RUNTIME_SPEC_FAILURE", 0)
		elseif mode == "yield" then
			coroutine.yield()
		elseif mode == "uncommitted" then
			return table.freeze({ committed = false })
		elseif mode == "malformed" then
			return table.freeze({ committed = true })
		end

		local configuration = environment.configuration
		local difficulty = configuration.difficulties.byId[environment.difficultyId]
		local definition = configuration.enemies.byId[event.enemyId]
		local runtimeEnemyId = environment.nextRuntimeEnemyId
		environment.nextRuntimeEnemyId += 1
		local record = table.freeze({
			runtimeEnemyId = runtimeEnemyId,
			enemyId = event.enemyId,
			laneId = event.laneId,
			currentHealth = definition.maxHealth * difficulty.modifiers.enemyHealthMultiplier,
			maximumHealth = definition.maxHealth * difficulty.modifiers.enemyHealthMultiplier,
			effectiveSpeed = definition.moveSpeedStudsPerSecond * difficulty.modifiers.enemyMoveSpeedMultiplier,
			spawnServerTime = sampleServerTime,
		})
		environment.spawnRecords[runtimeEnemyId] = record
		if mode == "reenter" then
			environment.innerResult = (environment.runtime :: any):step({})
		elseif mode == "cleanup" then
			environment.innerResult = (environment.runtime :: any):cleanup()
		end
		return table.freeze({
			committed = true,
			replicationCommitted = mode ~= "replication-failure",
			snapshot = record,
		})
	end
end

local function makeFrame(
	environment: Environment,
	sampleServerTime: number,
	terminalOutcomes: { any }?,
	disposition: string?,
	overrides: { [string]: any }?
): any
	local values = overrides or {}
	local ordinal = values.passOrdinal or (environment.passOrdinal + 1)
	if values.retainOrdinal ~= true then
		environment.passOrdinal = ordinal
	end
	return {
		disposition = disposition or "Healthy",
		matchId = values.matchId or MATCH_ID,
		enemyEpoch = values.enemyEpoch or ENEMY_EPOCH,
		passOrdinal = ordinal,
		sampleServerTime = sampleServerTime,
		terminalOutcomes = terminalOutcomes or {},
		spawn = if values.omitSpawn == true then nil else spawnCallback(environment, sampleServerTime),
	}
end

local function initialize(assertions: Assertions, runtime: any): any
	return expectSuccess(assertions, runtime:initialize())
end

local function issueTerminal(
	environment: Environment,
	runtimeEnemyId: number,
	reason: string,
	serverTime: number,
	overrides: { [string]: any }?
): any
	local values = overrides or {}
	local record = environment.spawnRecords[runtimeEnemyId]
	local outcome = table.freeze({
		matchId = values.matchId or MATCH_ID,
		enemyEpoch = values.enemyEpoch or ENEMY_EPOCH,
		runtimeEnemyId = runtimeEnemyId,
		enemyId = values.enemyId or (record and record.enemyId) or WaveFixtures.WORKER_ENEMY_ID,
		reason = reason,
		serverTime = serverTime,
	})
	if values.authenticated ~= false then
		environment.authenticatedOutcomes[outcome] = true
	end
	return outcome
end

local function spawnedIds(environment: Environment, firstId: number, lastId: number): { number }
	local ids = {}
	for runtimeEnemyId = firstId, lastId do
		if environment.spawnRecords[runtimeEnemyId] ~= nil then
			table.insert(ids, runtimeEnemyId)
		end
	end
	return ids
end

local function participant(userId: number, state: string?): any
	return {
		userId = userId,
		state = state or "Active",
		ready = false,
	}
end

local function setParticipants(environment: Environment, participants: { any })
	environment.participants = participants
	environment.lifecycleRevision += 1
end

local function terminalsFor(environment: Environment, ids: { number }, reason: string, serverTime: number): { any }
	local outcomes = {}
	for _, runtimeEnemyId in ids do
		table.insert(outcomes, issueTerminal(environment, runtimeEnemyId, reason, serverTime))
	end
	return outcomes
end

local function eventsAreStable(events: { any }): boolean
	for index = 2, #events do
		local previous = events[index - 1]
		local current = events[index]
		if current.scheduledServerTime < previous.scheduledServerTime then
			return false
		end
		if current.scheduledServerTime == previous.scheduledServerTime then
			if current.originatingWaveIndex < previous.originatingWaveIndex then
				return false
			elseif current.originatingWaveIndex == previous.originatingWaveIndex then
				if current.groupIndex < previous.groupIndex then
					return false
				elseif current.groupIndex == previous.groupIndex and current.spawnOrdinal < previous.spawnOrdinal then
					return false
				end
			end
		end
	end
	return true
end

return TestHarness.suite("wave runtime", {
	TestHarness.case(
		"authenticates constructor configuration map identity difficulty and dependencies",
		function(assertions)
			assertions.isTrue(table.isfrozen(WaveRuntime))
			assertions.equal(WaveRuntime.MAX_TOTAL_EVENTS, 4_096)
			assertions.equal(WaveRuntime.MAX_ACTIVE, 128)
			assertions.equal(WaveRuntime.MAX_WORK_PER_PASS, 256)
			local runtime, environment = createRig(assertions)
			local query = runtime:query()
			assertions.equal(query.state, "Uninitialized")
			assertions.equal(query.retainedOriginCount, 0)
			assertions.equal(query.retainedHeapCount, 0)

			local forgedConfiguration = frozenClone(DEFAULT_FIXTURE.configuration)
			expectError(
				assertions,
				WaveRuntime.new(
					forgedConfiguration,
					DEFAULT_FIXTURE.runtimeMap,
					MATCH_ID,
					ENEMY_EPOCH,
					WaveFixtures.PRIMARY_DIFFICULTY_ID,
					dependenciesFor(environment)
				),
				"INVALID_CONFIGURATION",
				"new"
			)
			local detachedMap = frozenClone(DEFAULT_FIXTURE.runtimeMap)
			expectError(
				assertions,
				WaveRuntime.new(
					DEFAULT_FIXTURE.configuration,
					detachedMap,
					MATCH_ID,
					ENEMY_EPOCH,
					WaveFixtures.PRIMARY_DIFFICULTY_ID,
					dependenciesFor(environment)
				),
				"INVALID_RUNTIME_MAP",
				"new"
			)
			expectError(
				assertions,
				WaveRuntime.new(
					DEFAULT_FIXTURE.configuration,
					DEFAULT_FIXTURE.runtimeMap,
					MATCH_ID,
					ENEMY_EPOCH,
					"difficulty:phase11-missing",
					dependenciesFor(environment)
				),
				"INVALID_DIFFICULTY",
				"new"
			)
			expectError(
				assertions,
				WaveRuntime.new(
					DEFAULT_FIXTURE.configuration,
					DEFAULT_FIXTURE.runtimeMap,
					"not-a-match-id",
					ENEMY_EPOCH,
					WaveFixtures.PRIMARY_DIFFICULTY_ID,
					dependenciesFor(environment)
				),
				"INVALID_MATCH_ID",
				"new"
			)
			expectError(
				assertions,
				WaveRuntime.new(
					DEFAULT_FIXTURE.configuration,
					DEFAULT_FIXTURE.runtimeMap,
					MATCH_ID,
					0,
					WaveFixtures.PRIMARY_DIFFICULTY_ID,
					dependenciesFor(environment)
				),
				"INVALID_EPOCH",
				"new"
			)
			local invalidDependencies = dependenciesFor(environment)
			invalidDependencies.extra = true
			expectError(
				assertions,
				WaveRuntime.new(
					DEFAULT_FIXTURE.configuration,
					DEFAULT_FIXTURE.runtimeMap,
					MATCH_ID,
					ENEMY_EPOCH,
					WaveFixtures.PRIMARY_DIFFICULTY_ID,
					invalidDependencies
				),
				"INVALID_DEPENDENCIES",
				"new"
			)

			local endlessFixture = WaveFixtures.authenticateSources(WaveFixtures.rawSources(true))
			local endlessEnvironment = newEnvironment(
				endlessFixture.configuration,
				endlessFixture.runtimeMap,
				WaveFixtures.ENDLESS_DIFFICULTY_ID,
				nil
			)
			expectError(
				assertions,
				WaveRuntime.new(
					endlessFixture.configuration,
					endlessFixture.runtimeMap,
					MATCH_ID,
					ENEMY_EPOCH,
					WaveFixtures.ENDLESS_DIFFICULTY_ID,
					dependenciesFor(endlessEnvironment)
				),
				"INVALID_DIFFICULTY",
				"new"
			)
		end
	),

	TestHarness.case("preflattens the exact lifetime cap and rejects one event beyond it", function(assertions)
		local exactConfiguration = capacityConfiguration(assertions, 4_096)
		local exactRuntime = createRig(
			assertions,
			exactConfiguration,
			WaveFixtures.createRuntimeMapSnapshot(),
			WaveFixtures.OVERLAP_DIFFICULTY_ID
		)
		local initialized = initialize(assertions, exactRuntime)
		assertions.equal(initialized.aggregateCounts.totalScheduled, 4_094)
		assertions.equal(exactRuntime:query().retainedHeapCount, 1)

		local overConfiguration = capacityConfiguration(assertions, 4_097)
		local overMap = WaveFixtures.createRuntimeMapSnapshot()
		local overEnvironment = newEnvironment(overConfiguration, overMap, WaveFixtures.OVERLAP_DIFFICULTY_ID, nil)
		expectError(
			assertions,
			WaveRuntime.new(
				overConfiguration,
				overMap,
				MATCH_ID,
				ENEMY_EPOCH,
				WaveFixtures.OVERLAP_DIFFICULTY_ID,
				dependenciesFor(overEnvironment)
			),
			"CAPACITY_EXCEEDED",
			"new"
		)
	end),

	TestHarness.case("reserves activation before Base and Enemy bind and commits WaveActive last", function(assertions)
		local runtime, environment = createRig(assertions, nil, nil, nil, {
			recordAuthorityReads = true,
			commitPublished = false,
		})
		table.clear(environment.order)
		local initialized = initialize(assertions, runtime)
		assertions.equal(#environment.order, 6)
		assertions.equal(environment.order[1], "lifecycle")
		assertions.equal(environment.order[2], "begin")
		assertions.equal(environment.order[3], "base")
		assertions.equal(environment.order[4], "bind")
		assertions.equal(environment.order[5], "clock")
		assertions.equal(environment.order[6], "commit")
		assertions.equal(environment.lifecycleState, "WaveActive")
		assertions.equal(environment.baseDifficulty, DEFAULT_FIXTURE.primary.difficultyDefinition)
		assertions.equal(environment.boundConfiguration, DEFAULT_FIXTURE.configuration)
		assertions.equal(environment.boundDifficulty, DEFAULT_FIXTURE.primary.difficultyDefinition)
		assertions.equal(initialized.state, "Running")
		assertions.equal(initialized.waveRevision, 1)
		assertions.equal(initialized.currentWaveNumber, 1)
		assertions.equal(initialized.totalWaves, 4)
		assertions.equal(initialized.waveStartedServerTime, 100)
		assertions.equal(initialized.deadlineServerTime, 112)
		assertions.equal(initialized.skipAvailableServerTime, 102)
		assertions.isFalse(initialized.skipState.available)
		assertions.equal(initialized.skipState.activeParticipantCount, 0)
		assertions.equal(initialized.skipState.yesVoteCount, 0)
		assertions.equal(initialized.skipState.requiredVoteCount, 0)
		assertions.isFalse(initialized.skipState.quorumPending)
		assertions.equal(initialized.aggregateCounts.totalScheduled, 8)
		assertions.isTrue(WaveProtocol.validateWaveSnapshot(initialized).ok)
		assertDeepFrozen(assertions, initialized)

		local placeholder = expectSuccess(assertions, runtime:getStartingCashPlaceholder())
		assertions.equal(placeholder.configurationVersion, 1)
		assertions.equal(placeholder.difficultyId, WaveFixtures.PRIMARY_DIFFICULTY_ID)
		assertions.equal(placeholder.startingBattleCash, 375)
		assertDeepFrozen(assertions, placeholder)
		DEFAULT_FIXTURE.rawSources.economy.difficultyRules[1].startingBattleCash = 999_999
		assertions.equal(expectSuccess(assertions, runtime:getStartingCashPlaceholder()).startingBattleCash, 375)
		expectError(assertions, runtime:initialize(), "WRONG_STATE", "initialize")
	end),

	TestHarness.case("rolls back activation and faults closed across initialization failures", function(assertions)
		local cases = {
			{ options = { lifecycleState = "Results" }, code = "LIFECYCLE_FAILED", rollback = 0 },
			{ options = { beginMode = "failure" }, code = "LIFECYCLE_FAILED", rollback = 0 },
			{ options = { baseInitializeMode = "failure" }, code = "BASE_FAILED", rollback = 1 },
			{ options = { baseInitializeMode = "yield" }, code = "BASE_FAILED", rollback = 1 },
			{ options = { bindMode = "throw" }, code = "ENEMY_FAILED", rollback = 1 },
			{ options = { bindMode = "false" }, code = "ENEMY_FAILED", rollback = 1 },
			{ options = { clockMode = "failure" }, code = "CLOCK_FAILED", rollback = 1 },
			{ options = { commitMode = "failure" }, code = "LIFECYCLE_FAILED", rollback = 1 },
			{ options = { commitMode = "malformed" }, code = "LIFECYCLE_FAILED", rollback = 1 },
			{ options = { commitRevisionDelta = 0 }, code = "LIFECYCLE_FAILED", rollback = 1 },
			{ options = { commitRevisionDelta = -1 }, code = "LIFECYCLE_FAILED", rollback = 1 },
			{
				options = {
					participants = { participant(1), participant(2) },
					commitParticipants = { participant(1), participant(3, "Spectator") },
				},
				code = "LIFECYCLE_FAILED",
				rollback = 1,
			},
			{
				options = {
					participants = { participant(1), participant(2) },
					commitParticipants = { participant(1), participant(2, "Disconnected") },
				},
				code = "LIFECYCLE_FAILED",
				rollback = 1,
			},
		}
		for _, definition in cases do
			local runtime, environment = createRig(assertions, nil, nil, nil, definition.options)
			expectError(assertions, runtime:initialize(), definition.code, "initialize")
			assertions.equal(runtime:query().state, "Faulted")
			assertions.equal(environment.rollbackCount, definition.rollback)
		end
	end),

	TestHarness.case("emits zero and nonzero intervals in stable authored order across lanes", function(assertions)
		local runtime, environment = createRig(assertions)
		initialize(assertions, runtime)
		local atStart = expectSuccess(assertions, runtime:step(makeFrame(environment, 100)))
		assertions.equal(atStart.currentCounts.spawned, 3)
		assertions.equal(#environment.spawnEvents, 3)
		for ordinal = 0, 2 do
			local event = environment.spawnEvents[ordinal + 1]
			assertions.equal(event.groupIndex, 1)
			assertions.equal(event.spawnOrdinal, ordinal)
			assertions.equal(event.laneId, WaveFixtures.MAIN_LANE_ID)
			assertions.equal(event.scheduledServerTime, 100)
		end

		expectSuccess(assertions, runtime:step(makeFrame(environment, 102)))
		expectSuccess(assertions, runtime:step(makeFrame(environment, 106)))
		local allDue = expectSuccess(assertions, runtime:step(makeFrame(environment, 109)))
		assertions.equal(allDue.currentCounts.spawned, 8)
		assertions.equal(allDue.currentCounts.pending, 0)
		assertions.equal(#environment.spawnEvents, 8)
		assertions.isTrue(eventsAreStable(environment.spawnEvents))
		assertions.equal(environment.spawnEvents[4].laneId, WaveFixtures.ALTERNATE_LANE_ID)
		assertions.equal(environment.spawnEvents[5].scheduledServerTime, 104)
		assertions.equal(environment.spawnEvents[6].groupIndex, 2)
		assertions.equal(environment.spawnEvents[7].groupIndex, 3)
		assertions.equal(environment.spawnEvents[8].scheduledServerTime, 109)
		assertions.equal(environment.spawnRecords[1].maximumHealth, 100)
		assertions.equal(environment.spawnRecords[1].effectiveSpeed, 4)
		assertions.equal(environment.spawnRecords[4].maximumHealth, 50)
		assertions.equal(environment.spawnRecords[4].effectiveSpeed, 6)
		for _, event in environment.spawnEvents do
			assertions.isTrue(event.scheduledServerTime <= environment.spawnRecords[_].spawnServerTime)
		end
	end),

	TestHarness.case("runs the full five second intermission after a nonempty early clear", function(assertions)
		local runtime, environment = createRig(assertions)
		initialize(assertions, runtime)
		expectSuccess(assertions, runtime:step(makeFrame(environment, 110)))
		local ids = spawnedIds(environment, 1, 8)
		local cleared = expectSuccess(
			assertions,
			runtime:step(makeFrame(environment, 110, terminalsFor(environment, ids, "Manual", 110)))
		)
		assertions.equal(cleared.state, "Intermission")
		assertions.equal(cleared.timerPhase, "EarlyClearIntermission")
		assertions.isTrue(WaveProtocol.validateWaveSnapshot(cleared).ok)
		assertions.equal(cleared.intermissionEndsServerTime, 115)
		assertions.equal(cleared.deadlineServerTime, 112)
		local pastDeadline = expectSuccess(assertions, runtime:step(makeFrame(environment, 113)))
		assertions.equal(pastDeadline.state, "Intermission")
		assertions.equal(pastDeadline.currentWaveNumber, 1)
		local almostDone = expectSuccess(assertions, runtime:step(makeFrame(environment, 114.999)))
		assertions.equal(almostDone.state, "Intermission")
		local nextWave = expectSuccess(assertions, runtime:step(makeFrame(environment, 115)))
		assertions.equal(nextWave.state, "Running")
		assertions.equal(nextWave.currentWaveNumber, 2)
		assertions.equal(nextWave.waveStartedServerTime, 115)
		assertions.equal(#environment.spawnEvents, 8)
	end),

	TestHarness.case("holds an empty wave intermission past its old deadline", function(assertions)
		local configuration = emptyFirstWaveConfiguration(assertions)
		local runtime, environment = createRig(
			assertions,
			configuration,
			WaveFixtures.createRuntimeMapSnapshot(),
			WaveFixtures.OVERLAP_DIFFICULTY_ID
		)
		initialize(assertions, runtime)
		local intermission = expectSuccess(assertions, runtime:step(makeFrame(environment, 102)))
		assertions.equal(intermission.state, "Intermission")
		assertions.equal(intermission.intermissionEndsServerTime, 107)
		assertions.equal(intermission.deadlineServerTime, 105)
		local afterOldDeadline = expectSuccess(assertions, runtime:step(makeFrame(environment, 106)))
		assertions.equal(afterOldDeadline.state, "Intermission")
		assertions.equal(#environment.spawnEvents, 0)
		local finalStarted = expectSuccess(assertions, runtime:step(makeFrame(environment, 107)))
		assertions.equal(finalStarted.currentWaveNumber, 2)
		assertions.equal(finalStarted.waveStartedServerTime, 107)
		assertions.equal(finalStarted.currentCounts.spawned, 2)
		assertions.equal(#environment.spawnEvents, 2)
	end),

	TestHarness.case(
		"emits the inclusive deadline before the next wave and preserves overlap ownership",
		function(assertions)
			local runtime, environment = createRig(
				assertions,
				DEFAULT_FIXTURE.configuration,
				DEFAULT_FIXTURE.runtimeMap,
				WaveFixtures.OVERLAP_DIFFICULTY_ID
			)
			initialize(assertions, runtime)
			expectSuccess(assertions, runtime:step(makeFrame(environment, 102)))
			local boundary = expectSuccess(assertions, runtime:step(makeFrame(environment, 105)))
			assertions.equal(boundary.currentWaveNumber, 2)
			assertions.equal(boundary.waveStartedServerTime, 105)
			assertions.equal(boundary.currentCounts.spawned, 2)
			assertions.equal(boundary.aggregateCounts.spawned, 4)
			assertions.equal(environment.spawnEvents[2].originatingWaveIndex, 1)
			assertions.equal(environment.spawnEvents[2].scheduledServerTime, 105)
			assertions.equal(environment.spawnEvents[3].originatingWaveIndex, 2)
			assertions.equal(environment.spawnEvents[3].scheduledServerTime, 105)
			assertions.equal(environment.spawnEvents[4].originatingWaveIndex, 2)

			local late = expectSuccess(assertions, runtime:step(makeFrame(environment, 108)))
			assertions.equal(environment.spawnEvents[5].originatingWaveIndex, 1)
			assertions.equal(environment.spawnEvents[5].scheduledServerTime, 108)
			assertions.equal(late.currentCounts.spawned, 2)
			assertions.equal(late.aggregateCounts.spawned, 5)
			local attributed = expectSuccess(
				assertions,
				runtime:step(makeFrame(environment, 109, { issueTerminal(environment, 5, "Endpoint", 109) }))
			)
			assertions.equal(attributed.currentCounts.leaked, 0)
			assertions.equal(attributed.aggregateCounts.leaked, 1)
			assertions.equal(attributed.currentCounts.alive, 2)
			assertions.equal(attributed.aggregateCounts.alive, 4)
		end
	),

	TestHarness.case(
		"revisions exact-minimum availability and exposes zero-delay starts immediately",
		function(assertions)
			local minimumRuntime, minimumEnvironment = createRig(
				assertions,
				DEFAULT_FIXTURE.configuration,
				DEFAULT_FIXTURE.runtimeMap,
				WaveFixtures.OVERLAP_DIFFICULTY_ID
			)
			local initialized = initialize(assertions, minimumRuntime)
			assertions.isFalse(initialized.skipState.available)
			local exactMinimum = expectSuccess(assertions, minimumRuntime:step(makeFrame(minimumEnvironment, 101)))
			assertions.isTrue(exactMinimum.skipState.available)
			assertions.equal(exactMinimum.waveRevision, initialized.waveRevision + 1)
			assertions.equal(exactMinimum.currentCounts.spawned, 0)
			assertions.equal(#minimumEnvironment.spawnEvents, 0)

			local zeroConfiguration = zeroDelayConfiguration(assertions)
			local zeroRuntime, zeroEnvironment = createRig(assertions, zeroConfiguration, nil, nil, {
				participants = { participant(1) },
			})
			local zeroInitialized = initialize(assertions, zeroRuntime)
			assertions.isTrue(zeroInitialized.skipState.available)
			assertions.equal(zeroInitialized.skipState.activeParticipantCount, 1)
			assertions.equal(zeroInitialized.skipState.requiredVoteCount, 1)
			local nextWave = expectSuccess(assertions, zeroRuntime:step(makeFrame(zeroEnvironment, 112)))
			assertions.equal(nextWave.currentWaveNumber, 2)
			assertions.isTrue(nextWave.skipState.available)
			assertions.equal(nextWave.skipAvailableServerTime, nextWave.waveStartedServerTime)
			assertions.isTrue(WaveProtocol.validateWaveSnapshot(nextWave).ok)
		end
	),

	TestHarness.case("records strict-majority votes and applies skip only at the next safe pass", function(assertions)
		local runtime, environment = createRig(
			assertions,
			DEFAULT_FIXTURE.configuration,
			DEFAULT_FIXTURE.runtimeMap,
			WaveFixtures.OVERLAP_DIFFICULTY_ID,
			{
				participants = { participant(1), participant(2), participant(3) },
			}
		)
		local initialized = initialize(assertions, runtime)
		environment.now = 101
		local first = expectSuccess(assertions, runtime:submitSkipVote(1, MATCH_ID, 1))
		assertions.equal(first.waveRevision, initialized.waveRevision + 1)
		assertions.equal(first.currentWaveNumber, 1)
		assertions.isTrue(first.skipState.available)
		assertions.equal(first.skipState.activeParticipantCount, 3)
		assertions.equal(first.skipState.yesVoteCount, 1)
		assertions.equal(first.skipState.requiredVoteCount, 2)
		assertions.isFalse(first.skipState.quorumPending)

		local second = expectSuccess(assertions, runtime:submitSkipVote(2, MATCH_ID, 1))
		assertions.equal(second.waveRevision, first.waveRevision + 1)
		assertions.equal(second.currentWaveNumber, 1)
		assertions.equal(second.skipState.yesVoteCount, 2)
		assertions.isTrue(second.skipState.quorumPending)
		assertions.equal(#environment.spawnEvents, 0)
		assertions.equal(runtime:query().retainedVoteCount, 2)
		assertions.equal(runtime:query().retainedCastHistoryCount, 2)

		local skipped = expectSuccess(assertions, runtime:step(makeFrame(environment, 101)))
		assertions.equal(skipped.currentWaveNumber, 2)
		assertions.equal(skipped.waveStartedServerTime, 101)
		assertions.equal(skipped.currentCounts.totalScheduled, 2)
		assertions.equal(skipped.currentCounts.spawned, 2)
		assertions.equal(skipped.aggregateCounts.totalScheduled, 5)
		assertions.equal(skipped.aggregateCounts.pending, 3)
		assertions.equal(#environment.spawnEvents, 2)
		assertions.equal(environment.spawnEvents[1].originatingWaveIndex, 2)
		assertions.equal(environment.spawnEvents[2].originatingWaveIndex, 2)
		assertions.equal(runtime:query().retainedVoteCount, 0)
		assertions.equal(runtime:query().retainedCastHistoryCount, 0)
		assertions.isTrue(WaveProtocol.validateWaveSnapshot(skipped).ok)
		expectError(assertions, runtime:submitSkipVote(3, MATCH_ID, 2), "UNAVAILABLE", "submitSkipVote")
		assertions.equal(expectSuccess(assertions, runtime:getSnapshot()).waveRevision, skipped.waveRevision)

		local oldWork = expectSuccess(assertions, runtime:step(makeFrame(environment, 102)))
		assertions.equal(oldWork.currentWaveNumber, 2)
		assertions.equal(environment.spawnEvents[3].originatingWaveIndex, 1)
		assertions.equal(environment.spawnEvents[3].scheduledServerTime, 102)
		assertions.equal(oldWork.aggregateCounts.pending, 2)
	end),

	TestHarness.case(
		"rejects stale early unauthorized duplicate and deadline-tied requests without mutation",
		function(assertions)
			local runtime, environment = createRig(assertions, nil, nil, nil, {
				participants = { participant(1), participant(2) },
			})
			local initialized = initialize(assertions, runtime)
			setParticipants(environment, { participant(1, "Disconnected"), participant(2) })
			expectError(assertions, runtime:submitSkipVote(1, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
			local afterEarly = expectSuccess(assertions, runtime:getSnapshot())
			assertions.equal(afterEarly.waveRevision, initialized.waveRevision)
			assertions.equal(afterEarly.skipState.activeParticipantCount, 2)
			assertions.equal(runtime:query().lastServerTime, 100)

			environment.now = 102
			expectError(assertions, runtime:submitSkipVote(1, OTHER_MATCH_ID, 1), "STALE_REQUEST", "submitSkipVote")
			expectError(assertions, runtime:submitSkipVote(1, MATCH_ID, 2), "STALE_REQUEST", "submitSkipVote")

			expectError(assertions, runtime:submitSkipVote(1, MATCH_ID, 1), "NOT_AUTHORIZED", "submitSkipVote")
			local afterUnauthorized = expectSuccess(assertions, runtime:getSnapshot())
			assertions.equal(afterUnauthorized.waveRevision, initialized.waveRevision)
			assertions.equal(afterUnauthorized.skipState.activeParticipantCount, 2)

			local accepted = expectSuccess(assertions, runtime:submitSkipVote(2, MATCH_ID, 1))
			assertions.equal(accepted.waveRevision, initialized.waveRevision + 1)
			assertions.equal(accepted.skipState.activeParticipantCount, 1)
			assertions.equal(accepted.skipState.yesVoteCount, 1)
			expectError(assertions, runtime:submitSkipVote(2, MATCH_ID, 1), "DUPLICATE_REQUEST", "submitSkipVote")
			assertions.equal(expectSuccess(assertions, runtime:getSnapshot()).waveRevision, accepted.waveRevision)

			environment.now = 112
			expectError(assertions, runtime:submitSkipVote(1, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
			local afterDeadlineTie = expectSuccess(assertions, runtime:getSnapshot())
			assertions.equal(afterDeadlineTie.waveRevision, accepted.waveRevision)
			assertions.equal(runtime:query().lastServerTime, 102)
		end
	),

	TestHarness.case("removes disconnected votes but preserves per-wave cast history", function(assertions)
		local runtime, environment = createRig(assertions, nil, nil, nil, {
			participants = { participant(1), participant(2), participant(3) },
		})
		initialize(assertions, runtime)
		environment.now = 102
		local accepted = expectSuccess(assertions, runtime:submitSkipVote(1, MATCH_ID, 1))
		assertions.equal(accepted.skipState.yesVoteCount, 1)
		assertions.equal(runtime:query().retainedCastHistoryCount, 1)

		setParticipants(environment, {
			participant(1, "Disconnected"),
			participant(2),
			participant(3),
		})
		local disconnected = expectSuccess(assertions, runtime:step(makeFrame(environment, 102)))
		assertions.equal(disconnected.currentWaveNumber, 1)
		assertions.equal(disconnected.skipState.activeParticipantCount, 2)
		assertions.equal(disconnected.skipState.yesVoteCount, 0)
		assertions.equal(disconnected.skipState.requiredVoteCount, 2)
		assertions.isFalse(disconnected.skipState.quorumPending)
		assertions.equal(runtime:query().retainedVoteCount, 0)
		assertions.equal(runtime:query().retainedCastHistoryCount, 1)

		environment.now = 103
		setParticipants(environment, {
			participant(1, "Spectator"),
			participant(2),
			participant(3),
		})
		expectError(assertions, runtime:submitSkipVote(1, MATCH_ID, 1), "NOT_AUTHORIZED", "submitSkipVote")
		setParticipants(environment, { participant(1), participant(2), participant(3) })
		expectError(assertions, runtime:submitSkipVote(1, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		local afterRejectedReconnect = expectSuccess(assertions, runtime:getSnapshot())
		assertions.equal(afterRejectedReconnect.state, "Faulted")
		assertions.equal(afterRejectedReconnect.skipState.activeParticipantCount, 2)
		assertions.equal(afterRejectedReconnect.skipState.yesVoteCount, 0)
		assertions.equal(afterRejectedReconnect.waveRevision, disconnected.waveRevision + 1)
		assertions.equal(runtime:query().faultCode, "LIFECYCLE_FAILED")
		assertions.equal(runtime:query().retainedCastHistoryCount, 1)
	end),

	TestHarness.case(
		"pins lifecycle revision participant identities and monotonic roster transitions",
		function(assertions)
			local function expectPinnedFault(participants: { any }, mutate: (Environment) -> ())
				local runtime, environment = createRig(assertions, nil, nil, nil, {
					participants = participants,
				})
				local initialized = initialize(assertions, runtime)
				mutate(environment)
				local faulted = expectSuccess(assertions, runtime:step(makeFrame(environment, 101)))
				assertions.equal(faulted.state, "Faulted")
				assertions.equal(faulted.waveRevision, initialized.waveRevision + 1)
				assertions.equal(runtime:query().faultCode, "LIFECYCLE_FAILED")
			end

			expectPinnedFault({ participant(1), participant(2) }, function(environment)
				environment.lifecycleRevision -= 1
			end)
			expectPinnedFault({ participant(1), participant(2) }, function(environment)
				environment.participants = { participant(1), participant(2, "Disconnected") }
			end)
			expectPinnedFault({ participant(1), participant(2) }, function(environment)
				setParticipants(environment, { participant(1), participant(3, "Spectator") })
			end)
			expectPinnedFault({ participant(1), participant(2) }, function(environment)
				setParticipants(environment, { participant(1) })
			end)
			expectPinnedFault({ participant(1), participant(2, "Spectator") }, function(environment)
				setParticipants(environment, { participant(1), participant(2) })
			end)
			expectPinnedFault({ participant(1), participant(2) }, function(environment)
				environment.lifecycleState = "Results"
			end)

			local intraPassRuntime, intraPassEnvironment = createRig(assertions, nil, nil, nil, {
				participants = { participant(1), participant(2) },
			})
			initialize(assertions, intraPassRuntime)
			intraPassEnvironment.lifecycleReadCount = 0
			intraPassEnvironment.lifecycleReadHook = function(environment, readCount)
				if readCount == 2 then
					environment.participants = { participant(1), participant(2, "Disconnected") }
				end
			end
			local coherentPass = expectSuccess(assertions, intraPassRuntime:step(makeFrame(intraPassEnvironment, 101)))
			assertions.equal(coherentPass.state, "Running")
			assertions.equal(coherentPass.skipState.activeParticipantCount, 2)
			assertions.equal(intraPassEnvironment.lifecycleReadCount, 1)

			local replayRuntime, replayEnvironment = createRig(assertions, nil, nil, nil, {
				participants = { participant(1), participant(2) },
			})
			initialize(assertions, replayRuntime)
			local activationRevision = replayEnvironment.lifecycleRevision
			setParticipants(replayEnvironment, { participant(1), participant(2, "Disconnected") })
			assertions.equal(replayEnvironment.lifecycleRevision, activationRevision + 1)
			local higherRevisionDisconnect =
				expectSuccess(assertions, replayRuntime:step(makeFrame(replayEnvironment, 101)))
			assertions.equal(higherRevisionDisconnect.state, "Running")
			assertions.equal(higherRevisionDisconnect.skipState.activeParticipantCount, 1)
			assertions.equal(replayRuntime:query().lastLifecycleRevision, replayEnvironment.lifecycleRevision)
			replayEnvironment.participants = { participant(1), participant(2) }
			local staleActiveReplay = expectSuccess(assertions, replayRuntime:step(makeFrame(replayEnvironment, 102)))
			assertions.equal(staleActiveReplay.state, "Faulted")
			assertions.equal(replayRuntime:query().faultCode, "LIFECYCLE_FAILED")

			local transitiveRuntime, transitiveEnvironment = createRig(assertions, nil, nil, nil, {
				participants = { participant(1), participant(2) },
			})
			initialize(assertions, transitiveRuntime)
			setParticipants(transitiveEnvironment, { participant(1), participant(2, "Spectator") })
			local transitiveShrink =
				expectSuccess(assertions, transitiveRuntime:step(makeFrame(transitiveEnvironment, 101)))
			assertions.equal(transitiveShrink.state, "Running")
			assertions.equal(transitiveShrink.skipState.activeParticipantCount, 1)

			local shrinkingRuntime, shrinkingEnvironment = createRig(assertions, nil, nil, nil, {
				participants = { participant(1), participant(2) },
			})
			initialize(assertions, shrinkingRuntime)
			shrinkingEnvironment.lifecycleRevision += 7
			shrinkingEnvironment.participants = { participant(1), participant(2, "Disconnected") }
			local shrunk = expectSuccess(assertions, shrinkingRuntime:step(makeFrame(shrinkingEnvironment, 101)))
			assertions.equal(shrunk.state, "Running")
			assertions.equal(shrunk.skipState.activeParticipantCount, 1)
			setParticipants(shrinkingEnvironment, { participant(1), participant(2, "Spectator") })
			local spectator = expectSuccess(assertions, shrinkingRuntime:step(makeFrame(shrinkingEnvironment, 102)))
			assertions.equal(spectator.state, "Running")
			assertions.equal(spectator.skipState.activeParticipantCount, 1)
			assertions.equal(shrinkingRuntime:query().lastLifecycleRevision, shrinkingEnvironment.lifecycleRevision)

			local resultsRuntime, resultsEnvironment = createRig(assertions, nil, nil, nil, {
				participants = { participant(1), participant(2) },
			})
			initialize(assertions, resultsRuntime)
			resultsEnvironment.lifecycleRevision += 7
			resultsEnvironment.lifecycleState = "Results"
			local results = expectSuccess(assertions, resultsRuntime:step(makeFrame(resultsEnvironment, 101)))
			assertions.equal(results.state, "DefeatClosed")
		end
	),

	TestHarness.case("lets a disconnect arm quorum and gives the exact deadline path precedence", function(assertions)
		local directRuntime, directEnvironment = createRig(assertions, nil, nil, nil, {
			participants = { participant(1), participant(2), participant(3), participant(4) },
		})
		initialize(assertions, directRuntime)
		directEnvironment.now = 102
		expectSuccess(assertions, directRuntime:submitSkipVote(1, MATCH_ID, 1))
		expectSuccess(assertions, directRuntime:submitSkipVote(2, MATCH_ID, 1))
		local directQuorum = expectSuccess(assertions, directRuntime:submitSkipVote(3, MATCH_ID, 1))
		assertions.equal(directQuorum.skipState.activeParticipantCount, 4)
		assertions.equal(directQuorum.skipState.requiredVoteCount, 3)
		assertions.equal(directQuorum.skipState.yesVoteCount, 3)
		assertions.isTrue(directQuorum.skipState.quorumPending)

		local quorumRuntime, quorumEnvironment = createRig(assertions, nil, nil, nil, {
			participants = { participant(1), participant(2), participant(3), participant(4) },
		})
		initialize(assertions, quorumRuntime)
		quorumEnvironment.now = 102
		expectSuccess(assertions, quorumRuntime:submitSkipVote(1, MATCH_ID, 1))
		local belowQuorum = expectSuccess(assertions, quorumRuntime:submitSkipVote(2, MATCH_ID, 1))
		assertions.equal(belowQuorum.skipState.requiredVoteCount, 3)
		assertions.isFalse(belowQuorum.skipState.quorumPending)
		setParticipants(quorumEnvironment, {
			participant(1),
			participant(2),
			participant(3),
			participant(4, "Disconnected"),
		})
		local disconnectedSkip = expectSuccess(assertions, quorumRuntime:step(makeFrame(quorumEnvironment, 103)))
		assertions.equal(disconnectedSkip.currentWaveNumber, 2)
		assertions.equal(disconnectedSkip.waveStartedServerTime, 103)
		assertions.equal(disconnectedSkip.skipState.yesVoteCount, 0)

		local tieRuntime, tieEnvironment = createRig(
			assertions,
			DEFAULT_FIXTURE.configuration,
			DEFAULT_FIXTURE.runtimeMap,
			WaveFixtures.OVERLAP_DIFFICULTY_ID,
			{
				participants = { participant(1), participant(2) },
			}
		)
		initialize(assertions, tieRuntime)
		tieEnvironment.now = 104.999
		expectSuccess(assertions, tieRuntime:submitSkipVote(1, MATCH_ID, 1))
		local pending = expectSuccess(assertions, tieRuntime:submitSkipVote(2, MATCH_ID, 1))
		assertions.isTrue(pending.skipState.quorumPending)
		local deadline = expectSuccess(assertions, tieRuntime:step(makeFrame(tieEnvironment, 105)))
		assertions.equal(deadline.currentWaveNumber, 2)
		assertions.equal(deadline.waveStartedServerTime, 105)
		assertions.equal(#tieEnvironment.spawnEvents, 4)
		assertions.equal(tieEnvironment.spawnEvents[1].originatingWaveIndex, 1)
		assertions.equal(tieEnvironment.spawnEvents[1].scheduledServerTime, 102)
		assertions.equal(tieEnvironment.spawnEvents[2].originatingWaveIndex, 1)
		assertions.equal(tieEnvironment.spawnEvents[2].scheduledServerTime, 105)
		assertions.equal(tieEnvironment.spawnEvents[3].originatingWaveIndex, 2)
		assertions.equal(tieEnvironment.spawnEvents[4].originatingWaveIndex, 2)
	end),

	TestHarness.case("never passes with zero Active participants and protects vote clock order", function(assertions)
		local soloRuntime, soloEnvironment = createRig(assertions, nil, nil, nil, {
			participants = { participant(1) },
		})
		initialize(assertions, soloRuntime)
		soloEnvironment.now = 102
		local soloVote = expectSuccess(assertions, soloRuntime:submitSkipVote(1, MATCH_ID, 1))
		assertions.equal(soloVote.skipState.requiredVoteCount, 1)
		assertions.equal(soloVote.skipState.yesVoteCount, 1)
		assertions.isTrue(soloVote.skipState.quorumPending)
		assertions.equal(soloVote.currentWaveNumber, 1)
		local soloSkipped = expectSuccess(assertions, soloRuntime:step(makeFrame(soloEnvironment, 102)))
		assertions.equal(soloSkipped.currentWaveNumber, 2)
		assertions.equal(soloSkipped.waveStartedServerTime, 102)

		local zeroRuntime, zeroEnvironment = createRig(assertions)
		initialize(assertions, zeroRuntime)
		local zeroActive = expectSuccess(assertions, zeroRuntime:step(makeFrame(zeroEnvironment, 102)))
		assertions.equal(zeroActive.currentWaveNumber, 1)
		assertions.isTrue(zeroActive.skipState.available)
		assertions.equal(zeroActive.skipState.activeParticipantCount, 0)
		assertions.equal(zeroActive.skipState.requiredVoteCount, 0)
		assertions.isFalse(zeroActive.skipState.quorumPending)
		zeroEnvironment.now = 102
		expectError(assertions, zeroRuntime:submitSkipVote(1, MATCH_ID, 1), "NOT_AUTHORIZED", "submitSkipVote")

		local clockRuntime, clockEnvironment = createRig(assertions, nil, nil, nil, {
			participants = { participant(1) },
		})
		initialize(assertions, clockRuntime)
		clockEnvironment.now = 102
		local accepted = expectSuccess(assertions, clockRuntime:submitSkipVote(1, MATCH_ID, 1))
		assertions.equal(clockRuntime:query().lastServerTime, 102)
		local backward = expectSuccess(assertions, clockRuntime:step(makeFrame(clockEnvironment, 101)))
		assertions.equal(backward.state, "Faulted")
		assertions.equal(clockRuntime:query().faultCode, "CLOCK_FAILED")
		assertions.equal(backward.waveRevision, accepted.waveRevision + 1)

		local lifecycleRuntime, lifecycleEnvironment = createRig(assertions, nil, nil, nil, {
			participants = { participant(1) },
		})
		initialize(assertions, lifecycleRuntime)
		local lifecycleBeforeFailure = expectSuccess(assertions, lifecycleRuntime:getSnapshot())
		lifecycleEnvironment.now = 102
		lifecycleEnvironment.lifecycleMode = "failure"
		expectError(assertions, lifecycleRuntime:submitSkipVote(1, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		local lifecycleFailure = expectSuccess(assertions, lifecycleRuntime:getSnapshot())
		assertions.equal(lifecycleFailure.state, "Faulted")
		assertions.equal(lifecycleFailure.waveRevision, lifecycleBeforeFailure.waveRevision + 1)
		assertions.equal(lifecycleRuntime:query().faultCode, "LIFECYCLE_FAILED")

		local clockFailureRuntime, clockFailureEnvironment = createRig(assertions, nil, nil, nil, {
			participants = { participant(1) },
		})
		local clockFailureInitial = initialize(assertions, clockFailureRuntime)
		clockFailureEnvironment.now = 102
		clockFailureEnvironment.clockMode = "malformed"
		expectError(assertions, clockFailureRuntime:submitSkipVote(1, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		local clockFailure = expectSuccess(assertions, clockFailureRuntime:getSnapshot())
		assertions.equal(clockFailure.state, "Faulted")
		assertions.equal(clockFailure.waveRevision, clockFailureInitial.waveRevision + 1)
		assertions.equal(clockFailureRuntime:query().faultCode, "CLOCK_FAILED")
	end),

	TestHarness.case("rejects votes during intermission defeat fault and cleanup without residue", function(assertions)
		local intermissionConfiguration = emptyFirstWaveConfiguration(assertions)
		local intermissionRuntime, intermissionEnvironment = createRig(
			assertions,
			intermissionConfiguration,
			WaveFixtures.createRuntimeMapSnapshot(),
			WaveFixtures.OVERLAP_DIFFICULTY_ID,
			{
				participants = { participant(1) },
			}
		)
		initialize(assertions, intermissionRuntime)
		local intermission =
			expectSuccess(assertions, intermissionRuntime:step(makeFrame(intermissionEnvironment, 100)))
		assertions.equal(intermission.state, "Intermission")
		intermissionEnvironment.now = 101
		expectError(assertions, intermissionRuntime:submitSkipVote(1, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")

		local defeatRuntime, defeatEnvironment = createRig(assertions, nil, nil, nil, {
			participants = { participant(1) },
		})
		local defeatInitial = initialize(assertions, defeatRuntime)
		defeatEnvironment.now = 102
		defeatEnvironment.baseDefeatPending = true
		expectError(assertions, defeatRuntime:submitSkipVote(1, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		local defeated = expectSuccess(assertions, defeatRuntime:getSnapshot())
		assertions.equal(defeated.state, "DefeatClosed")
		assertions.equal(defeated.waveRevision, defeatInitial.waveRevision + 1)
		expectError(assertions, defeatRuntime:submitSkipVote(1, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")

		local cleanedRuntime, cleanedEnvironment = createRig(assertions, nil, nil, nil, {
			participants = { participant(1) },
		})
		initialize(assertions, cleanedRuntime)
		cleanedEnvironment.now = 102
		expectSuccess(assertions, cleanedRuntime:submitSkipVote(1, MATCH_ID, 1))
		assertions.equal(cleanedRuntime:query().retainedVoteCount, 1)
		assertions.equal(cleanedRuntime:query().retainedCastHistoryCount, 1)
		expectSuccess(assertions, cleanedRuntime:cleanup())
		expectError(assertions, cleanedRuntime:submitSkipVote(1, MATCH_ID, 1), "UNAVAILABLE", "submitSkipVote")
		local cleaned = cleanedRuntime:query()
		assertions.equal(cleaned.retainedActiveUserIdCount, 0)
		assertions.equal(cleaned.retainedVoteCount, 0)
		assertions.equal(cleaned.retainedCastHistoryCount, 0)
	end),

	TestHarness.case(
		"uses one final PostDeadline and completes only after its late event resolves",
		function(assertions)
			local configuration = finalOverlapConfiguration(assertions)
			local runtime, environment = createRig(
				assertions,
				configuration,
				WaveFixtures.createRuntimeMapSnapshot(),
				WaveFixtures.OVERLAP_DIFFICULTY_ID
			)
			initialize(assertions, runtime)
			expectSuccess(assertions, runtime:step(makeFrame(environment, 105)))
			local postDeadline = expectSuccess(assertions, runtime:step(makeFrame(environment, 113)))
			assertions.equal(postDeadline.currentWaveNumber, 2)
			assertions.equal(postDeadline.timerPhase, "PostDeadline")
			assertions.equal(postDeadline.currentCounts.pending, 1)
			assertions.equal(postDeadline.state, "Running")
			local late = expectSuccess(assertions, runtime:step(makeFrame(environment, 115)))
			assertions.equal(late.timerPhase, "PostDeadline")
			assertions.equal(late.currentCounts.pending, 0)
			assertions.equal(environment.spawnEvents[#environment.spawnEvents].originatingWaveIndex, 2)
			assertions.equal(environment.spawnEvents[#environment.spawnEvents].scheduledServerTime, 115)
			local ids = spawnedIds(environment, 1, environment.nextRuntimeEnemyId - 1)
			local completed = expectSuccess(
				assertions,
				runtime:step(makeFrame(environment, 115, terminalsFor(environment, ids, "Manual", 115)))
			)
			assertions.equal(completed.state, "FiniteComplete")
			assertions.equal(completed.timerPhase, "None")
			assertions.equal(completed.finiteCompleteServerTime, 115)
			assertions.isTrue(WaveProtocol.validateWaveSnapshot(completed).ok)
			assertions.equal(runtime:getCompletionState().completionCount, 1)
			assertions.equal(environment.lifecycleState, "WaveActive")
			local spawnCount = #environment.spawnEvents
			expectError(assertions, runtime:step(makeFrame(environment, 116)), "WRONG_STATE", "step")
			assertions.equal(#environment.spawnEvents, spawnCount)
			assertions.equal(runtime:getCompletionState().completionCount, 1)
		end
	),

	TestHarness.case("drains an exact 4096 event large delta in bounded stable batches", function(assertions)
		local configuration = capacityConfiguration(assertions, 4_096)
		local runtime, environment = createRig(
			assertions,
			configuration,
			WaveFixtures.createRuntimeMapSnapshot(),
			WaveFixtures.OVERLAP_DIFFICULTY_ID
		)
		initialize(assertions, runtime)
		local activeIds = {}
		local maximumBatch = 0
		for _ = 1, 32 do
			local firstNewId = environment.nextRuntimeEnemyId
			local terminals = terminalsFor(environment, activeIds, "Manual", 5_000)
			local value = expectSuccess(assertions, runtime:step(makeFrame(environment, 5_000, terminals)))
			assertions.notEqual(value.state, "Faulted")
			local lastNewId = environment.nextRuntimeEnemyId - 1
			activeIds = spawnedIds(environment, firstNewId, lastNewId)
			maximumBatch = math.max(maximumBatch, #activeIds)
		end
		assertions.equal(#environment.spawnEvents, 4_096)
		assertions.equal(maximumBatch, 128)
		assertions.isTrue(eventsAreStable(environment.spawnEvents))
		assertions.isTrue(environment.spawnEvents[1].scheduledServerTime <= 5_000)
		assertions.isTrue(environment.spawnEvents[4_096].scheduledServerTime <= 5_000)
		local completed = expectSuccess(
			assertions,
			runtime:step(makeFrame(environment, 5_000, terminalsFor(environment, activeIds, "Manual", 5_000)))
		)
		assertions.equal(completed.state, "FiniteComplete")
		assertions.equal(completed.aggregateCounts.totalScheduled, 4_096)
		assertions.equal(completed.aggregateCounts.spawned, 4_096)
		assertions.equal(completed.aggregateCounts.otherwiseResolved, 4_096)
		assertions.isTrue(WaveProtocol.validateWaveSnapshot(completed).ok)
		local query = runtime:query()
		assertions.equal(query.lastPassOrdinal, 33)
		assertions.equal(query.processedTerminalCount, 4_096)
		assertions.equal(query.retainedOwnershipCount, 4_096)
		assertions.equal(query.retainedHeapCount, 0)
	end),

	TestHarness.case("accepts authenticated terminals once and attributes endpoint separately", function(assertions)
		local runtime, environment = createRig(assertions)
		initialize(assertions, runtime)
		expectSuccess(assertions, runtime:step(makeFrame(environment, 100)))
		local endpoint = issueTerminal(environment, 1, "Endpoint", 101)
		local manual = issueTerminal(environment, 2, "Manual", 101)
		local resolved =
			expectSuccess(assertions, runtime:step(makeFrame(environment, 101, { endpoint, endpoint, manual })))
		assertions.equal(resolved.currentCounts.alive, 1)
		assertions.equal(resolved.currentCounts.leaked, 1)
		assertions.equal(resolved.currentCounts.otherwiseResolved, 1)
		assertions.equal(runtime:query().processedTerminalCount, 2)
		local duplicateOnly = expectSuccess(assertions, runtime:step(makeFrame(environment, 101, { endpoint })))
		assertions.equal(duplicateOnly.waveRevision, resolved.waveRevision)
		assertions.equal(runtime:query().processedTerminalCount, 2)
	end),

	TestHarness.case("faults forged wrong identity unknown stale and conflicting terminals", function(assertions)
		local variants = { "forged", "wrong-match", "wrong-epoch", "unknown", "stale" }
		for _, variant in variants do
			local runtime, environment = createRig(assertions)
			initialize(assertions, runtime)
			expectSuccess(assertions, runtime:step(makeFrame(environment, 100)))
			local overrides = {}
			local runtimeEnemyId = 1
			local serverTime = 101
			if variant == "forged" then
				overrides.authenticated = false
			elseif variant == "wrong-match" then
				overrides.matchId = OTHER_MATCH_ID
			elseif variant == "wrong-epoch" then
				overrides.enemyEpoch = ENEMY_EPOCH + 1
			elseif variant == "unknown" then
				runtimeEnemyId = 4_096
			elseif variant == "stale" then
				serverTime = 99
			end
			local outcome = issueTerminal(environment, runtimeEnemyId, "Manual", serverTime, overrides)
			local faulted = expectSuccess(assertions, runtime:step(makeFrame(environment, 101, { outcome })))
			assertions.equal(faulted.state, "Faulted")
			assertions.equal(runtime:query().faultCode, "INVALID_OUTCOME")
		end

		local runtime, environment = createRig(assertions)
		initialize(assertions, runtime)
		expectSuccess(assertions, runtime:step(makeFrame(environment, 100)))
		local first = issueTerminal(environment, 1, "Manual", 101)
		expectSuccess(assertions, runtime:step(makeFrame(environment, 101, { first })))
		local conflicting = issueTerminal(environment, 1, "Endpoint", 102)
		local faulted = expectSuccess(assertions, runtime:step(makeFrame(environment, 102, { conflicting })))
		assertions.equal(faulted.state, "Faulted")
		assertions.equal(runtime:query().faultCode, "INVALID_OUTCOME")
	end),

	TestHarness.case("accounts a committed spawn before replication failure faults the runtime", function(assertions)
		local runtime, environment = createRig(assertions, nil, nil, nil, {
			spawnMode = "replication-failure",
		})
		initialize(assertions, runtime)
		local faulted = expectSuccess(assertions, runtime:step(makeFrame(environment, 100)))
		assertions.equal(faulted.state, "Faulted")
		assertions.equal(faulted.currentCounts.spawned, 1)
		assertions.equal(faulted.currentCounts.pending, 7)
		assertions.equal(faulted.currentCounts.alive, 1)
		assertions.equal(runtime:query().retainedOwnershipCount, 1)
		assertions.equal(runtime:query().faultCode, "ENEMY_FAILED")
		assertions.equal(#environment.spawnEvents, 1)
		expectError(assertions, runtime:step(makeFrame(environment, 101)), "FAULTED", "step")
	end),

	TestHarness.case(
		"reconciles committed callback throws and yields exactly once through dependency-fault close",
		function(assertions)
			for _, mode in { "throw", "yield" } do
				local runtime, environment = createRig(assertions)
				local initialized = initialize(assertions, runtime)
				local frame = makeFrame(environment, 100)
				local commitSpawn = frame.spawn
				local attemptedEvent: any = nil
				local committedOutcome: any = nil
				frame.spawn = function(event: any): unknown
					attemptedEvent = event
					committedOutcome = commitSpawn(event)
					if mode == "throw" then
						error("PRIVATE_WAVE_RUNTIME_COMMITTED_CALLBACK_FAILURE", 0)
					else
						coroutine.yield()
					end
					return committedOutcome
				end

				local callbackFault = expectSuccess(assertions, runtime:step(frame))
				assertions.equal(callbackFault.state, "Faulted")
				assertions.equal(callbackFault.waveRevision, initialized.waveRevision + 1)
				assertions.equal(callbackFault.currentCounts.spawned, 0)
				assertions.equal(callbackFault.currentCounts.pending, 8)
				assertions.equal(callbackFault.currentCounts.alive, 0)
				assertions.equal(callbackFault.currentCounts.otherwiseResolved, 0)
				assertions.equal(runtime:query().faultCode, "CALLBACK_FAILED")
				assertions.equal(#environment.spawnEvents, 1)
				assertions.equal((committedOutcome :: any).committed, true)

				local runtimeEnemyId = (committedOutcome :: any).snapshot.runtimeEnemyId
				local terminalOutcome = issueTerminal(environment, runtimeEnemyId, "Manual", 100)
				local committedSpawn = table.freeze({
					event = attemptedEvent,
					outcome = committedOutcome,
				})
				local closeContext = table.freeze({
					disposition = "DependencyFault",
					matchId = MATCH_ID,
					enemyEpoch = ENEMY_EPOCH,
					passOrdinal = environment.passOrdinal,
					sampleServerTime = 100,
					committedSpawn = committedSpawn,
					terminalOutcome = terminalOutcome,
				})
				assertDeepFrozen(assertions, closeContext)
				local unauthenticatedContext = table.freeze({
					disposition = "DependencyFault",
					matchId = MATCH_ID,
					enemyEpoch = ENEMY_EPOCH,
					passOrdinal = environment.passOrdinal,
					sampleServerTime = 100,
					committedSpawn = committedSpawn,
					terminalOutcome = frozenClone(terminalOutcome),
				})
				expectError(
					assertions,
					runtime:closeDependencyFault(unauthenticatedContext),
					"INVALID_OUTCOME",
					"closeDependencyFault"
				)
				local malformedWrapperContext = table.freeze({
					disposition = "DependencyFault",
					matchId = MATCH_ID,
					enemyEpoch = ENEMY_EPOCH,
					passOrdinal = environment.passOrdinal,
					sampleServerTime = 100,
					committedSpawn = {
						event = attemptedEvent,
						outcome = committedOutcome,
					},
					terminalOutcome = terminalOutcome,
				})
				expectError(
					assertions,
					runtime:closeDependencyFault(malformedWrapperContext),
					"INVALID_OUTCOME",
					"closeDependencyFault"
				)
				local rejectedQuery = runtime:query()
				assertions.equal(rejectedQuery.faultCloseCount, 0)
				assertions.equal(rejectedQuery.retainedOwnershipCount, 0)
				assertions.equal(rejectedQuery.processedTerminalCount, 0)
				assertions.equal(rejectedQuery.faultCode, "CALLBACK_FAILED")
				assertions.equal(
					expectSuccess(assertions, runtime:getSnapshot()).waveRevision,
					callbackFault.waveRevision
				)

				local closed = expectSuccess(assertions, runtime:closeDependencyFault(closeContext))
				assertions.equal(closed.state, "Faulted")
				assertions.equal(closed.waveRevision, callbackFault.waveRevision + 1)
				assertions.equal(closed.currentCounts.spawned, 1)
				assertions.equal(closed.currentCounts.pending, 7)
				assertions.equal(closed.currentCounts.alive, 0)
				assertions.equal(closed.currentCounts.otherwiseResolved, 1)
				assertions.equal(closed.aggregateCounts.spawned, 1)
				assertions.equal(closed.aggregateCounts.pending, 7)
				assertions.equal(closed.aggregateCounts.alive, 0)
				assertions.equal(closed.aggregateCounts.otherwiseResolved, 1)
				local closedQuery = runtime:query()
				assertions.equal(closedQuery.faultCloseCount, 1)
				assertions.equal(closedQuery.retainedOwnershipCount, 1)
				assertions.equal(closedQuery.processedTerminalCount, 1)
				assertions.equal(closedQuery.faultCode, "CALLBACK_FAILED")

				local replayContext = frozenClone(closeContext)
				assertDeepFrozen(assertions, replayContext)
				local replayed = expectSuccess(assertions, runtime:closeDependencyFault(replayContext))
				assertions.equal(replayed.waveRevision, closed.waveRevision)
				assertions.equal(replayed.currentCounts.spawned, closed.currentCounts.spawned)
				assertions.equal(replayed.currentCounts.pending, closed.currentCounts.pending)
				assertions.equal(replayed.currentCounts.alive, closed.currentCounts.alive)
				assertions.equal(replayed.currentCounts.otherwiseResolved, closed.currentCounts.otherwiseResolved)
				assertions.equal(runtime:query().faultCloseCount, 1)
				assertions.equal(runtime:query().processedTerminalCount, 1)

				local mutableOutcome = table.clone(committedOutcome)
				local mutableNestedReplay = table.freeze({
					disposition = "DependencyFault",
					matchId = MATCH_ID,
					enemyEpoch = ENEMY_EPOCH,
					passOrdinal = environment.passOrdinal,
					sampleServerTime = 100,
					committedSpawn = table.freeze({
						event = attemptedEvent,
						outcome = mutableOutcome,
					}),
					terminalOutcome = terminalOutcome,
				})
				expectError(
					assertions,
					runtime:closeDependencyFault(mutableNestedReplay),
					"INVALID_OUTCOME",
					"closeDependencyFault"
				)

				local missingTerminal = table.freeze({
					disposition = "DependencyFault",
					matchId = MATCH_ID,
					enemyEpoch = ENEMY_EPOCH,
					passOrdinal = environment.passOrdinal,
					sampleServerTime = 100,
					committedSpawn = committedSpawn,
				})
				expectError(
					assertions,
					runtime:closeDependencyFault(missingTerminal),
					"INVALID_PASS",
					"closeDependencyFault"
				)
				local conflictingTerminal = issueTerminal(environment, runtimeEnemyId, "Manual", 101)
				local conflictingContext = table.freeze({
					disposition = "DependencyFault",
					matchId = MATCH_ID,
					enemyEpoch = ENEMY_EPOCH,
					passOrdinal = environment.passOrdinal + 1,
					sampleServerTime = 101,
					committedSpawn = committedSpawn,
					terminalOutcome = conflictingTerminal,
				})
				expectError(
					assertions,
					runtime:closeDependencyFault(conflictingContext),
					"INVALID_OUTCOME",
					"closeDependencyFault"
				)
				local retained = expectSuccess(assertions, runtime:getSnapshot())
				assertions.equal(retained.state, "Faulted")
				assertions.equal(retained.waveRevision, closed.waveRevision)
				assertions.equal(retained.currentCounts.spawned, 1)
				assertions.equal(retained.currentCounts.pending, 7)
				assertions.equal(retained.currentCounts.alive, 0)
				assertions.equal(retained.currentCounts.otherwiseResolved, 1)
				assertions.equal(runtime:query().faultCloseCount, 1)
				assertions.equal(runtime:query().processedTerminalCount, 1)

				assertions.isTrue(expectSuccess(assertions, runtime:cleanup()))
				local cleaned = runtime:query()
				assertions.equal(cleaned.state, "Cleaned")
				assertions.equal(cleaned.retainedOriginCount, 0)
				assertions.equal(cleaned.retainedOwnershipCount, 0)
				assertions.equal(cleaned.retainedHeapCount, 0)
				assertions.equal(cleaned.processedTerminalCount, 0)
				assertions.equal(cleaned.faultCloseCount, 0)
				assertions.isFalse(cleaned.busy)
				expectError(assertions, runtime:closeDependencyFault(closeContext), "CLEANED", "closeDependencyFault")
			end
		end
	),

	TestHarness.case("gives committed terminal states precedence over dependency-fault close", function(assertions)
		local defeatRuntime, defeatEnvironment = createRig(assertions)
		initialize(assertions, defeatRuntime)
		local defeated = expectSuccess(
			assertions,
			defeatRuntime:step(makeFrame(defeatEnvironment, 100, nil, "DefeatCommitted", {
				omitSpawn = true,
			}))
		)
		local defeatContext = table.freeze({
			disposition = "DependencyFault",
			matchId = MATCH_ID,
			enemyEpoch = ENEMY_EPOCH,
			passOrdinal = defeatEnvironment.passOrdinal,
			sampleServerTime = 100,
		})
		local retainedDefeat = expectSuccess(assertions, defeatRuntime:closeDependencyFault(defeatContext))
		assertions.equal(retainedDefeat.state, "DefeatClosed")
		assertions.equal(retainedDefeat.waveRevision, defeated.waveRevision)
		assertions.equal(defeatRuntime:query().faultCloseCount, 0)
		assertions.isNil(defeatRuntime:query().faultCode)
		assertions.isTrue(expectSuccess(assertions, defeatRuntime:cleanup()))

		local rawSources = WaveFixtures.rawSources()
		local emptySchedule = rawSources.waves[2]
		emptySchedule.waves[1].groups = {}
		emptySchedule.waves[2].groups[1].count = 1
		local emptyConfiguration = validateConfiguration(assertions, rawSources)
		local finiteRuntime, finiteEnvironment = createRig(
			assertions,
			emptyConfiguration,
			WaveFixtures.createRuntimeMapSnapshot(),
			WaveFixtures.OVERLAP_DIFFICULTY_ID
		)
		initialize(assertions, finiteRuntime)
		local intermission = expectSuccess(assertions, finiteRuntime:step(makeFrame(finiteEnvironment, 100)))
		assertions.equal(intermission.state, "Intermission")
		local finalRunning = expectSuccess(
			assertions,
			finiteRuntime:step(makeFrame(finiteEnvironment, intermission.intermissionEndsServerTime))
		)
		assertions.equal(finalRunning.state, "Running")
		assertions.equal(finalRunning.currentCounts.alive, 1)
		local finalTerminal = issueTerminal(finiteEnvironment, 1, "Manual", intermission.intermissionEndsServerTime)
		local completed = expectSuccess(
			assertions,
			finiteRuntime:step(makeFrame(finiteEnvironment, intermission.intermissionEndsServerTime, { finalTerminal }))
		)
		assertions.equal(completed.state, "FiniteComplete")
		local finiteContext = table.freeze({
			disposition = "DependencyFault",
			matchId = MATCH_ID,
			enemyEpoch = ENEMY_EPOCH,
			passOrdinal = finiteEnvironment.passOrdinal,
			sampleServerTime = completed.finiteCompleteServerTime,
		})
		local retainedFinite = expectSuccess(assertions, finiteRuntime:closeDependencyFault(finiteContext))
		assertions.equal(retainedFinite.state, "FiniteComplete")
		assertions.equal(retainedFinite.waveRevision, completed.waveRevision)
		assertions.equal(finiteRuntime:getCompletionState().completionCount, 1)
		assertions.equal(finiteRuntime:query().faultCloseCount, 0)
		assertions.isNil(finiteRuntime:query().faultCode)
		assertions.isTrue(expectSuccess(assertions, finiteRuntime:cleanup()))
	end),

	TestHarness.case("classifies uncommitted malformed throwing and yielding spawn failures", function(assertions)
		local definitions = {
			{ mode = "uncommitted", code = "CAPACITY_EXCEEDED" },
			{ mode = "malformed", code = "ENEMY_FAILED" },
			{ mode = "throw", code = "CALLBACK_FAILED" },
			{ mode = "yield", code = "CALLBACK_FAILED" },
		}
		for _, definition in definitions do
			local runtime, environment = createRig(assertions, nil, nil, nil, {
				spawnMode = definition.mode,
			})
			initialize(assertions, runtime)
			local faulted = expectSuccess(assertions, runtime:step(makeFrame(environment, 100)))
			assertions.equal(faulted.state, "Faulted")
			assertions.equal(runtime:query().faultCode, definition.code)
		end

		local runtime, environment = createRig(assertions, nil, nil, nil, {
			baseStateMode = "malformed",
		})
		initialize(assertions, runtime)
		local baseFault = expectSuccess(assertions, runtime:step(makeFrame(environment, 100)))
		assertions.equal(baseFault.state, "Faulted")
		assertions.equal(runtime:query().faultCode, "BASE_FAILED")
		assertions.equal(#environment.spawnEvents, 0)
	end),

	TestHarness.case(
		"closes on lifecycle Results Base defeat and Enemy dispositions at every boundary",
		function(assertions)
			local resultsRuntime, resultsEnvironment = createRig(assertions)
			initialize(assertions, resultsRuntime)
			resultsEnvironment.lifecycleState = "Results"
			resultsEnvironment.lifecycleRevision += 1
			local resultsClosed = expectSuccess(assertions, resultsRuntime:step(makeFrame(resultsEnvironment, 100)))
			assertions.equal(resultsClosed.state, "DefeatClosed")
			assertions.equal(#resultsEnvironment.spawnEvents, 0)

			local lifecycleFaultRuntime, lifecycleFaultEnvironment = createRig(assertions)
			initialize(assertions, lifecycleFaultRuntime)
			lifecycleFaultEnvironment.lifecycleMode = "failure"
			local lifecycleFault =
				expectSuccess(assertions, lifecycleFaultRuntime:step(makeFrame(lifecycleFaultEnvironment, 100)))
			assertions.equal(lifecycleFault.state, "Faulted")
			assertions.equal(lifecycleFaultRuntime:query().faultCode, "LIFECYCLE_FAILED")

			local baseRuntime, baseEnvironment = createRig(assertions)
			initialize(assertions, baseRuntime)
			baseEnvironment.baseDefeatPending = true
			local baseClosed = expectSuccess(assertions, baseRuntime:step(makeFrame(baseEnvironment, 100)))
			assertions.equal(baseClosed.state, "DefeatClosed")
			assertions.equal(#baseEnvironment.spawnEvents, 0)

			local dispositionRuntime, dispositionEnvironment = createRig(assertions)
			initialize(assertions, dispositionRuntime)
			local dispositionClosed = expectSuccess(
				assertions,
				dispositionRuntime:step(makeFrame(dispositionEnvironment, 100, nil, "DefeatCommitted", {
					omitSpawn = true,
				}))
			)
			assertions.equal(dispositionClosed.state, "DefeatClosed")

			local dependencyRuntime, dependencyEnvironment = createRig(assertions)
			initialize(assertions, dependencyRuntime)
			local dependencyFault = expectSuccess(
				assertions,
				dependencyRuntime:step(makeFrame(dependencyEnvironment, 100, nil, "DependencyFault", {
					omitSpawn = true,
				}))
			)
			assertions.equal(dependencyFault.state, "Faulted")
			assertions.equal(dependencyRuntime:query().faultCode, "ENEMY_FAILED")

			local shutdownRuntime, shutdownEnvironment = createRig(assertions)
			initialize(assertions, shutdownRuntime)
			local shutdown = expectSuccess(
				assertions,
				shutdownRuntime:step(makeFrame(shutdownEnvironment, 100, nil, "Shutdown", {
					omitSpawn = true,
				}))
			)
			assertions.equal(shutdown.state, "Faulted")
			assertions.equal(shutdownRuntime:query().faultCode, "CLEANED")

			local missingSpawnRuntime, missingSpawnEnvironment = createRig(assertions)
			initialize(assertions, missingSpawnRuntime)
			local missingSpawn = expectSuccess(
				assertions,
				missingSpawnRuntime:step(makeFrame(missingSpawnEnvironment, 100, nil, "Healthy", {
					omitSpawn = true,
				}))
			)
			assertions.equal(missingSpawn.state, "Faulted")
			assertions.equal(missingSpawnRuntime:query().faultCode, "INVALID_PASS")

			local closedSpawnRuntime, closedSpawnEnvironment = createRig(assertions)
			initialize(assertions, closedSpawnRuntime)
			local closedWithSpawn = expectSuccess(
				assertions,
				closedSpawnRuntime:step(makeFrame(closedSpawnEnvironment, 100, nil, "DefeatCommitted"))
			)
			assertions.equal(closedWithSpawn.state, "Faulted")
			assertions.equal(closedSpawnRuntime:query().faultCode, "INVALID_PASS")
		end
	),

	TestHarness.case("gives authoritative defeat precedence over oversized terminal batches", function(assertions)
		for _, authority in { "Base", "Results" } do
			local runtime, environment = createRig(assertions)
			initialize(assertions, runtime)
			local spawned = expectSuccess(assertions, runtime:step(makeFrame(environment, 100)))
			assertions.isTrue(spawned.currentCounts.alive > 0)

			local repeatedOutcome = issueTerminal(environment, 1, "Manual", 101)
			local oversizedOtherwiseValid = table.create(129, repeatedOutcome)
			if authority == "Base" then
				environment.baseDefeatPending = true
			else
				environment.lifecycleRevision += 1
				environment.lifecycleState = "Results"
			end

			local closed = expectSuccess(assertions, runtime:step(makeFrame(environment, 101, oversizedOtherwiseValid)))
			assertions.equal(closed.state, "DefeatClosed")
			assertions.equal(closed.waveRevision, spawned.waveRevision + 1)
			assertions.equal(runtime:query().processedTerminalCount, 0)
			assertions.isNil(runtime:query().faultCode)
		end
	end),

	TestHarness.case("distinguishes clock failures from malformed pass identity", function(assertions)
		local backwardRuntime, backwardEnvironment = createRig(assertions)
		initialize(assertions, backwardRuntime)
		local backward = expectSuccess(assertions, backwardRuntime:step(makeFrame(backwardEnvironment, 99)))
		assertions.equal(backward.state, "Faulted")
		assertions.equal(backwardRuntime:query().faultCode, "CLOCK_FAILED")

		local nonfiniteRuntime, nonfiniteEnvironment = createRig(assertions)
		initialize(assertions, nonfiniteRuntime)
		local nonfinite = expectSuccess(assertions, nonfiniteRuntime:step(makeFrame(nonfiniteEnvironment, 0 / 0)))
		assertions.equal(nonfinite.state, "Faulted")
		assertions.equal(nonfiniteRuntime:query().faultCode, "CLOCK_FAILED")

		local ordinalRuntime, ordinalEnvironment = createRig(assertions)
		initialize(assertions, ordinalRuntime)
		expectSuccess(
			assertions,
			ordinalRuntime:step(makeFrame(ordinalEnvironment, 100, nil, nil, {
				passOrdinal = 73,
			}))
		)
		local wrongOrdinal = expectSuccess(
			assertions,
			ordinalRuntime:step(makeFrame(ordinalEnvironment, 101, nil, nil, {
				passOrdinal = 75,
			}))
		)
		assertions.equal(wrongOrdinal.state, "Faulted")
		assertions.equal(ordinalRuntime:query().faultCode, "INVALID_PASS")

		local identityRuntime, identityEnvironment = createRig(assertions)
		initialize(assertions, identityRuntime)
		local wrongIdentity = expectSuccess(
			assertions,
			identityRuntime:step(makeFrame(identityEnvironment, 100, nil, nil, {
				matchId = OTHER_MATCH_ID,
			}))
		)
		assertions.equal(wrongIdentity.state, "Faulted")
		assertions.equal(identityRuntime:query().faultCode, "INVALID_PASS")

		local shapeRuntime, shapeEnvironment = createRig(assertions)
		initialize(assertions, shapeRuntime)
		local inexactFrame = makeFrame(shapeEnvironment, 100)
		inexactFrame.clientAuthority = true
		local wrongShape = expectSuccess(assertions, shapeRuntime:step(inexactFrame))
		assertions.equal(wrongShape.state, "Faulted")
		assertions.equal(shapeRuntime:query().faultCode, "INVALID_PASS")
	end),

	TestHarness.case("accounts committed truth before a reentrant callback fault", function(assertions)
		local reentrantRuntime, reentrantEnvironment = createRig(assertions, nil, nil, nil, {
			spawnMode = "reenter",
		})
		initialize(assertions, reentrantRuntime)
		local reentrant = expectSuccess(assertions, reentrantRuntime:step(makeFrame(reentrantEnvironment, 100)))
		expectError(assertions, reentrantEnvironment.innerResult, "REENTRANT", "step")
		assertions.equal(reentrant.state, "Faulted")
		assertions.equal(reentrant.currentCounts.spawned, 1)
		assertions.equal(reentrantRuntime:query().retainedOwnershipCount, 1)
		assertions.equal(reentrantRuntime:query().faultCode, "REENTRANT")
	end),

	TestHarness.case("cleans a deferred callback request without residue", function(assertions)
		local cleanupRuntime, cleanupEnvironment = createRig(assertions, nil, nil, nil, {
			spawnMode = "cleanup",
		})
		initialize(assertions, cleanupRuntime)
		expectError(assertions, cleanupRuntime:step(makeFrame(cleanupEnvironment, 100)), "CLEANED", "step")
		assertions.isTrue((cleanupEnvironment.innerResult :: any).ok)
		assertions.isFalse((cleanupEnvironment.innerResult :: any).value)
		local cleaned = cleanupRuntime:query()
		assertions.equal(cleaned.state, "Cleaned")
		assertions.equal(cleaned.retainedOriginCount, 0)
		assertions.equal(cleaned.retainedOwnershipCount, 0)
		assertions.equal(cleaned.retainedHeapCount, 0)
		assertions.equal(cleaned.processedTerminalCount, 0)
		assertions.isFalse(cleaned.busy)
		assertions.isFalse(expectSuccess(assertions, cleanupRuntime:cleanup()))
		expectError(assertions, cleanupRuntime:getSnapshot(), "CLEANED", "getSnapshot")
	end),

	TestHarness.case("cleans directly and idempotently", function(assertions)
		local directRuntime = createRig(assertions)
		initialize(assertions, directRuntime)
		assertions.isTrue(expectSuccess(assertions, directRuntime:cleanup()))
		assertions.isFalse(expectSuccess(assertions, directRuntime:cleanup()))
		assertions.equal(directRuntime:query().state, "Cleaned")
	end),
})
