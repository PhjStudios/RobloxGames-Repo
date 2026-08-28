--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local EnemySimulationService = require(script.Parent.Parent.ProductionServerEnemies.EnemySimulationService)
local WaveFixtures = require(script.Parent.Parent.Fixtures.WaveFixtures)

local Shared = game:GetService("ReplicatedStorage").Shared
local AssetSchema = require(Shared.config.AssetSchema)
local DifficultySchema = require(Shared.config.DifficultySchema)
local EnemySchema = require(Shared.config.EnemySchema)
local Result = require(Shared.util.Result)
local Validation = require(Shared.util.Validation)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase09-simulation-service"

local newForTests = EnemySimulationService.newForTests
if newForTests == nil then
	error("EnemySimulationService test constructor unavailable at exact Test location", 0)
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
	assertions.contains(failure, `[ATD_ENEMY_SIMULATION_SERVICE][code={code}]`)
end

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected EnemySimulationService fixture operation to succeed", 0)
	end
	return result.value
end

local function freezeArray(values: { any }): { any }
	local result = table.clone(values)
	table.freeze(result)
	return result
end

local function snapshot(runtimeEnemyId: number, revision: number?, slowMultiplier: number?): any
	return table.freeze({
		runtimeEnemyId = runtimeEnemyId,
		revision = revision or 1,
		lifecycle = "Active",
		speedModifiers = table.freeze({
			slowMultiplier = slowMultiplier or 1,
		}),
	})
end

local function endpointResolution(runtimeEnemyId: number, callbackSucceeded: boolean?): any
	return table.freeze({
		endpoint = table.freeze({
			runtimeEnemyId = runtimeEnemyId,
			revision = 2,
			lifecycle = "EndpointResolved",
		}),
		despawn = table.freeze({
			runtimeEnemyId = runtimeEnemyId,
			revision = 3,
			lifecycle = "Despawned",
			reason = "Endpoint",
		}),
		callbackSucceeded = callbackSucceeded ~= false,
	})
end

local function makeStepResult(
	deltaSeconds: number,
	updatedIds: { number }?,
	endpointResolutions: { any }?,
	cleaned: boolean?,
	faulted: boolean?,
	schedulerSampleToken: unknown?,
	sampleServerTime: number?
): any
	local updates = freezeArray(updatedIds or {})
	local endpoints = freezeArray(endpointResolutions or {})
	return table.freeze({
		deltaSeconds = deltaSeconds,
		sampleServerTime = sampleServerTime or deltaSeconds,
		schedulerSampleToken = schedulerSampleToken,
		visitedCount = #updates + #endpoints,
		updatedCount = #updates + #endpoints,
		endpointCount = #endpoints,
		activeCountAfter = 0,
		cleaned = cleaned == true,
		faulted = faulted == true,
		updatedRuntimeEnemyIds = updates,
		endpointResolutions = endpoints,
	})
end

local function indexOf(values: { string }, expected: string): number
	for index, value in values do
		if value == expected then
			return index
		end
	end
	return 0
end

local function makeEnvironment(): any
	local environment: any = {
		runtimeMap = table.freeze({ marker = "detached-runtime-map" }),
		catalog = table.freeze({ marker = "authenticated-empty-catalog" }),
		activeSnapshots = {},
		terminalById = {},
		trace = {},
		stepCallbacks = {},
		removalCallbacks = {},
		stepCalls = 0,
		advanceCalls = 0,
		storeCleanupCalls = 0,
		publisherCleanupCalls = 0,
		stepDisconnectCalls = 0,
		removalDisconnectCalls = 0,
		publisherPending = 0,
		publisherDirty = 0,
		publisherDeltaMessages = 0,
		publisherReservedFutureMessages = 0,
		publisherReservedOrdinaryMessages = 0,
		publisherNextSequence = 1,
		publisherFaulted = false,
		publisherCleaned = false,
		preflightStepMode = "success",
		stepMode = "success",
		connectorMode = "success",
		inStep = false,
		storeCleanupDuringStep = false,
		nextRuntimeEnemyId = 1,
		studioCatalogInstallCalls = 0,
		studioLaneIds = freezeArray({ "alpha-bent" }),
		baseFinishResults = {},
		baseRecordLeakCalls = 0,
		baseFinishCalls = 0,
		baseCommitCalls = 0,
		baseFailCalls = 0,
		baseFaultCalls = 0,
		baseStudioCatalogInstallCalls = 0,
		baseInitializeCalls = 0,
		matchState = "WaveActive",
		matchRevision = 1,
		studioWaveActivationCalls = 0,
		lifecycleBeginCalls = 0,
		lifecycleCommitCalls = 0,
		lifecycleRollbackCalls = 0,
		difficultyBound = false,
		boundDifficultyId = nil,
		activeSchedulerToken = nil,
		terminalOutcomes = {},
		authenticatedTerminalOutcomes = {},
		terminalCount = 0,
	}

	local function activeList(): { any }
		local values = {}
		for _, value in environment.activeSnapshots do
			table.insert(values, value)
		end
		table.sort(values, function(left, right)
			return left.runtimeEnemyId < right.runtimeEnemyId
		end)
		table.freeze(values)
		return values
	end

	environment.matchLifecycle = {
		getRuntimeMapSnapshot = function(_self: unknown): unknown
			table.insert(environment.trace, "map")
			if environment.mapMode == "throw" then
				error("PRIVATE_MAP_FAILURE", 0)
			end
			return Result.ok(environment.runtimeMap)
		end,
		getSnapshot = function(_self: unknown): unknown
			table.insert(environment.trace, "match-snapshot")
			return Result.ok(table.freeze({
				matchId = MATCH_ID,
				state = environment.matchState,
				revision = environment.matchRevision,
			}))
		end,
		beginBaseDefeat = function(_self: unknown, matchId: unknown): unknown
			environment.lifecycleBeginCalls += 1
			table.insert(environment.trace, "lifecycle:begin-defeat")
			if environment.lifecycleBeginMode == "failure" or matchId ~= MATCH_ID then
				return Result.err(table.freeze({ code = "WRONG_STATE" }))
			end
			environment.lifecycleToken = table.freeze({})
			return Result.ok(environment.lifecycleToken)
		end,
		commitBaseDefeat = function(_self: unknown, token: unknown): unknown
			environment.lifecycleCommitCalls += 1
			table.insert(environment.trace, "lifecycle:commit-defeat")
			if environment.lifecycleCommitMode == "failure" or token ~= environment.lifecycleToken then
				return Result.err(table.freeze({ code = "INTERNAL_ERROR" }))
			end
			return Result.ok(table.freeze({
				committed = true,
				published = environment.lifecyclePublishMode ~= "failure",
				snapshot = table.freeze({ matchId = MATCH_ID, state = "Results", revision = 2 }),
			}))
		end,
		rollbackBaseDefeat = function(_self: unknown, token: unknown): unknown
			environment.lifecycleRollbackCalls += 1
			table.insert(environment.trace, "lifecycle:rollback-defeat")
			return Result.ok(token == environment.lifecycleToken)
		end,
		activateStudioWaveForEvidence = function(_self: unknown): unknown
			environment.studioWaveActivationCalls += 1
			if environment.matchState ~= "PreWave" then
				return Result.err(table.freeze({ code = "WRONG_STATE" }))
			end
			environment.matchState = "WaveActive"
			environment.matchRevision += 1
			return Result.ok(table.freeze({
				matchId = MATCH_ID,
				state = environment.matchState,
				revision = environment.matchRevision,
			}))
		end,
	}

	environment.baseRuntime = {
		installStudioCatalog = function(_self: unknown, catalog: unknown): unknown
			environment.baseStudioCatalogInstallCalls += 1
			environment.installedStudioDifficultyCatalog = catalog
			if environment.baseStudioCatalogHook ~= nil then
				environment.baseStudioCatalogHook()
			end
			if not DifficultySchema.isValidatedCatalog(catalog) then
				return Result.err(table.freeze({ code = "UNAUTHENTICATED_CATALOG" }))
			end
			if environment.baseStudioCatalogInstallMode == "false" then
				return Result.ok(false)
			end
			return Result.ok(true)
		end,
		initializeBase = function(_self: unknown, definition: unknown): unknown
			environment.baseInitializeCalls += 1
			environment.initializedDifficultyDefinition = definition
			local catalog = environment.installedStudioDifficultyCatalog
			if
				type(catalog) ~= "table"
				or type(definition) ~= "table"
				or (catalog :: any).byId[(definition :: any).id] ~= definition
			then
				return Result.err(table.freeze({ code = "UNAUTHENTICATED_DIFFICULTY" }))
			end
			local maximumHealth = (definition :: any).base.maxHealth
			environment.baseSnapshot = table.freeze({
				matchId = MATCH_ID,
				enemyEpoch = 1,
				mapId = "map:phase10-studio",
				difficultyId = (definition :: any).id,
				currentHealth = maximumHealth,
				maximumHealth = maximumHealth,
				baseRevision = 1,
				lowHealth = false,
				status = "Active",
				serverTime = 1,
			})
			return Result.ok(environment.baseSnapshot)
		end,
		recordLeak = function(_self: unknown, outcome: unknown): unknown
			environment.baseRecordLeakCalls += 1
			table.insert(environment.trace, "base:record-leak")
			environment.lastLeakOutcome = outcome
			if environment.baseRecordMode == "failure" then
				return Result.err(table.freeze({ code = "UNAVAILABLE" }))
			end
			return Result.ok(table.freeze({ kind = "Applied" }))
		end,
		finishEnemyPass = function(_self: unknown, passOrdinal: unknown): unknown
			environment.baseFinishCalls += 1
			table.insert(environment.trace, `base:finish:{tostring(passOrdinal)}`)
			local configured = environment.baseFinishResults[passOrdinal]
			if configured ~= nil then
				return configured
			end
			return Result.ok(table.freeze({ kind = "Noop", passOrdinal = passOrdinal }))
		end,
		commitPreparedDefeat = function(_self: unknown, token: unknown): unknown
			environment.baseCommitCalls += 1
			table.insert(environment.trace, "base:commit-defeat")
			if environment.baseCommitMode == "failure" or token ~= environment.basePreparedToken then
				return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
			end
			return Result.ok(table.freeze({
				committed = true,
				published = environment.basePublishMode ~= "failure",
				snapshot = table.freeze({ status = "Defeated" }),
				resultSeed = table.freeze({ outcome = "Defeat" }),
			}))
		end,
		failPreparedDefeat = function(_self: unknown, token: unknown): unknown
			environment.baseFailCalls += 1
			table.insert(environment.trace, "base:fail-defeat")
			return Result.ok(
				table.freeze({ failed = true, published = true, tokenMatched = token == environment.basePreparedToken })
			)
		end,
		fault = function(_self: unknown): unknown
			environment.baseFaultCalls += 1
			table.insert(environment.trace, "base:fault")
			return Result.ok(table.freeze({ status = "Faulted" }))
		end,
		getSnapshot = function(_self: unknown): unknown
			if environment.baseSnapshot == nil then
				return Result.err(table.freeze({ code = "UNAVAILABLE" }))
			end
			return Result.ok(environment.baseSnapshot)
		end,
		getResultSeed = function(_self: unknown): unknown
			if environment.resultSeed == nil then
				return Result.err(table.freeze({ code = "UNAVAILABLE" }))
			end
			return Result.ok(environment.resultSeed)
		end,
		getDefeatState = function(_self: unknown): unknown
			return table.freeze({ state = "Active", defeatPending = false })
		end,
		getMetrics = function(_self: unknown): unknown
			return table.freeze({
				initialized = environment.baseSnapshot ~= nil,
				publicationCount = environment.basePublicationCount or 0,
			})
		end,
	}

	environment.store = {
		spawn = function(_self: unknown, enemyId: unknown, laneId: unknown): unknown
			table.insert(environment.trace, "store:spawn")
			environment.lastSpawnEnemyId = enemyId
			environment.lastSpawnLaneId = laneId
			if environment.storeMutationMode == "failure" then
				return Result.err(table.freeze({ code = "CAPACITY_EXCEEDED", operation = "spawn" }))
			end
			local value = snapshot(environment.nextRuntimeEnemyId)
			environment.nextRuntimeEnemyId += 1
			table.insert(environment.activeSnapshots, value)
			return Result.ok(value)
		end,
		spawnScheduled = function(_self: unknown, token: unknown, enemyId: unknown, laneId: unknown): unknown
			table.insert(environment.trace, "store:spawn-scheduled")
			if token ~= environment.activeSchedulerToken or not environment.difficultyBound then
				return Result.err(table.freeze({ code = "INVALID_SCHEDULER_SAMPLE", operation = "spawnScheduled" }))
			end
			if environment.scheduledSpawnMode == "failure" then
				return Result.err(table.freeze({ code = "CAPACITY_EXCEEDED", operation = "spawnScheduled" }))
			end
			local value = table.freeze({
				runtimeEnemyId = environment.nextRuntimeEnemyId,
				enemyId = enemyId,
				laneId = laneId,
				currentHealth = 125,
				maximumHealth = 125,
				effectiveSpeed = 8,
				spawnServerTime = token.sampleServerTime,
				revision = 1,
				lifecycle = "Active",
				speedModifiers = table.freeze({ slowMultiplier = 1 }),
			})
			environment.nextRuntimeEnemyId += 1
			table.insert(environment.activeSnapshots, value)
			return Result.ok(value)
		end,
		despawnScheduledForFault = function(_self: unknown, token: unknown, expectedSnapshot: unknown): unknown
			local runtimeEnemyId = if type(expectedSnapshot) == "table"
				then (expectedSnapshot :: any).runtimeEnemyId
				else nil
			table.insert(environment.trace, `store:fault-despawn:{tostring(runtimeEnemyId)}`)
			if token ~= environment.activeSchedulerToken then
				return Result.err(table.freeze({ code = "INVALID_SCHEDULER_SAMPLE" }))
			end
			local found = false
			for index = #environment.activeSnapshots, 1, -1 do
				if environment.activeSnapshots[index] == expectedSnapshot then
					found = true
					table.remove(environment.activeSnapshots, index)
					break
				end
			end
			if not found then
				return Result.err(table.freeze({ code = "STALE_RUNTIME_ID" }))
			end
			local snapshotValue = expectedSnapshot :: any
			local despawn = table.freeze({
				runtimeEnemyId = snapshotValue.runtimeEnemyId,
				enemyId = snapshotValue.enemyId,
				laneId = snapshotValue.laneId,
				revision = snapshotValue.revision + 1,
				lifecycle = "Despawned",
				reason = "Manual",
				sampleServerTime = token.sampleServerTime,
			})
			local terminalOutcome = table.freeze({
				matchId = MATCH_ID,
				enemyEpoch = 1,
				runtimeEnemyId = snapshotValue.runtimeEnemyId,
				enemyId = snapshotValue.enemyId,
				reason = "Manual",
				serverTime = token.sampleServerTime,
			})
			environment.terminalById[runtimeEnemyId] = despawn
			environment.authenticatedTerminalOutcomes[terminalOutcome] = true
			table.insert(environment.terminalOutcomes, terminalOutcome)
			environment.terminalCount += 1
			environment.faultDespawn = despawn
			environment.faultTerminalOutcome = terminalOutcome
			return Result.ok(table.freeze({
				despawn = despawn,
				terminalOutcome = terminalOutcome,
			}))
		end,
		get = function(_self: unknown, runtimeEnemyId: unknown): unknown
			table.insert(environment.trace, `store:get:{tostring(runtimeEnemyId)}`)
			for _, value in environment.activeSnapshots do
				if value.runtimeEnemyId == runtimeEnemyId then
					return Result.ok(value)
				end
			end
			return Result.err(table.freeze({ code = "NOT_FOUND", operation = "get" }))
		end,
		list = function(_self: unknown): unknown
			table.insert(environment.trace, "store:list")
			return Result.ok(activeList())
		end,
		queryTerminal = function(_self: unknown, runtimeEnemyId: unknown): unknown
			return Result.ok(environment.terminalById[runtimeEnemyId])
		end,
		setSlowMultiplier = function(_self: unknown, runtimeEnemyId: unknown, multiplier: unknown): unknown
			table.insert(environment.trace, `store:slow:{tostring(runtimeEnemyId)}`)
			for index, value in environment.activeSnapshots do
				if value.runtimeEnemyId == runtimeEnemyId then
					if value.speedModifiers.slowMultiplier == multiplier then
						return Result.ok(value)
					end
					local changed = snapshot(runtimeEnemyId :: number, value.revision + 1, multiplier :: number)
					environment.activeSnapshots[index] = changed
					return Result.ok(changed)
				end
			end
			return Result.err(table.freeze({ code = "NOT_FOUND", operation = "setSlowMultiplier" }))
		end,
		resolveEndpoint = function(_self: unknown, runtimeEnemyId: unknown): unknown
			table.insert(environment.trace, `store:endpoint:{tostring(runtimeEnemyId)}`)
			local callbackSucceeded = environment.endpointCallbackSucceeded ~= false
			if callbackSucceeded and type(environment.endpointSink) == "function" then
				callbackSucceeded = pcall(
					environment.endpointSink,
					table.freeze({
						runtimeEnemyId = runtimeEnemyId,
					})
				)
			end
			local resolution = endpointResolution(runtimeEnemyId :: number, callbackSucceeded)
			environment.terminalById[runtimeEnemyId] = resolution.despawn
			for index = #environment.activeSnapshots, 1, -1 do
				if environment.activeSnapshots[index].runtimeEnemyId == runtimeEnemyId then
					table.remove(environment.activeSnapshots, index)
				end
			end
			return Result.ok(resolution)
		end,
		despawn = function(_self: unknown, runtimeEnemyId: unknown): unknown
			table.insert(environment.trace, `store:despawn:{tostring(runtimeEnemyId)}`)
			local value = table.freeze({
				runtimeEnemyId = runtimeEnemyId,
				revision = 2,
				lifecycle = "Despawned",
				reason = "Manual",
			})
			environment.terminalById[runtimeEnemyId] = value
			for index = #environment.activeSnapshots, 1, -1 do
				if environment.activeSnapshots[index].runtimeEnemyId == runtimeEnemyId then
					table.remove(environment.activeSnapshots, index)
				end
			end
			return Result.ok(value)
		end,
		despawnAllForDefeat = function(_self: unknown, runtimeEnemyIds: unknown, token: unknown?): unknown
			table.insert(environment.trace, "store:defeat-all")
			environment.defeatStoreIds = runtimeEnemyIds
			environment.defeatSchedulerToken = token
			if environment.defeatStoreHook ~= nil then
				environment.defeatStoreHook()
			end
			if environment.defeatStoreMode == "failure" then
				return Result.err(table.freeze({ code = "CLOCK_FAILED" }))
			end
			local despawns = {}
			for _, runtimeEnemyId in runtimeEnemyIds :: { number } do
				table.insert(
					despawns,
					table.freeze({
						runtimeEnemyId = runtimeEnemyId,
						revision = 2,
						lifecycle = "Despawned",
						reason = "Defeat",
					})
				)
				environment.terminalById[runtimeEnemyId] = despawns[#despawns]
			end
			table.clear(environment.activeSnapshots)
			table.freeze(despawns)
			return Result.ok(despawns)
		end,
		step = function(_self: unknown, deltaSeconds: unknown): unknown
			environment.stepCalls += 1
			environment.inStep = true
			table.insert(environment.trace, "store:step")
			if environment.stepHook ~= nil then
				local value = environment.stepHook(deltaSeconds)
				environment.inStep = false
				return value
			elseif environment.stepMode == "throw" then
				error("PRIVATE_STEP_FAILURE", 0)
			elseif environment.stepMode == "yield" then
				coroutine.yield()
			elseif environment.stepMode == "failure" then
				environment.inStep = false
				return Result.err(table.freeze({ code = "CLOCK_FAILED", operation = "step" }))
			end
			environment.inStep = false
			if environment.difficultyBound then
				local sampleServerTime = environment.stepSampleServerTime or deltaSeconds
				environment.activeSchedulerToken = table.freeze({
					matchId = MATCH_ID,
					enemyEpoch = 1,
					sampleServerTime = sampleServerTime,
				})
				return Result.ok(
					makeStepResult(
						deltaSeconds :: number,
						nil,
						nil,
						false,
						false,
						environment.activeSchedulerToken,
						sampleServerTime
					)
				)
			end
			return Result.ok(makeStepResult(deltaSeconds :: number))
		end,
		finishSchedulerSample = function(_self: unknown, token: unknown): unknown
			table.insert(environment.trace, "store:finish-scheduler-sample")
			if token ~= environment.activeSchedulerToken then
				return Result.err(table.freeze({ code = "INVALID_SCHEDULER_SAMPLE" }))
			end
			environment.activeSchedulerToken = nil
			return Result.ok(true)
		end,
		drainTerminalOutcomes = function(_self: unknown): unknown
			table.insert(environment.trace, "store:drain-terminal-outcomes")
			if environment.terminalDrainMode == "failure" then
				return Result.err(table.freeze({ code = "FAULTED" }))
			end
			local values = freezeArray(environment.terminalOutcomes)
			table.clear(environment.terminalOutcomes)
			return Result.ok(values)
		end,
		isAuthenticatedTerminalOutcome = function(_self: unknown, outcome: unknown): boolean
			return environment.authenticatedTerminalOutcomes[outcome] == true
		end,
		isAuthenticatedSchedulerSample = function(_self: unknown, token: unknown): boolean
			return token ~= nil and token == environment.activeSchedulerToken
		end,
		getIdentity = function(_self: unknown): unknown
			table.insert(environment.trace, "store:identity")
			return Result.ok(table.freeze({ matchId = MATCH_ID, enemyEpoch = 1 }))
		end,
		getMetrics = function(_self: unknown): unknown
			return table.freeze({
				activeCount = #environment.activeSnapshots,
				lifetimeCount = environment.nextRuntimeEnemyId - 1,
				terminalCount = environment.terminalCount,
				queuedTerminalOutcomeCount = #environment.terminalOutcomes,
				retainedTerminalOutcomeCount = 0,
				difficultyBound = environment.difficultyBound,
				boundDifficultyId = environment.boundDifficultyId,
				schedulerSampleActive = environment.activeSchedulerToken ~= nil,
				cleaned = environment.storeCleaned == true,
				faulted = false,
			})
		end,
		installStudioCatalog = function(_self: unknown, catalog: unknown): unknown
			environment.studioCatalogInstallCalls += 1
			environment.installedStudioCatalog = catalog
			if not EnemySchema.isValidatedCatalog(catalog) then
				return Result.err(table.freeze({
					code = "UNAUTHENTICATED_CATALOG",
					operation = "installStudioCatalog",
				}))
			end
			if environment.studioCatalogInstallMode == "false" then
				return Result.ok(false)
			end
			return Result.ok(true)
		end,
		bindDifficulty = function(_self: unknown, catalog: unknown, definition: unknown): unknown
			table.insert(environment.trace, "store:bind-difficulty")
			if environment.bindDifficultyMode == "failure" then
				return Result.err(table.freeze({ code = "INVALID_DIFFICULTY_DEFINITION" }))
			elseif environment.bindDifficultyMode == "false" then
				return Result.ok(false)
			end
			environment.boundDifficultyCatalog = catalog
			environment.boundDifficultyDefinition = definition
			environment.difficultyBound = true
			environment.boundDifficultyId = (definition :: any).id
			return Result.ok(true)
		end,
		listLaneIds = function(_self: unknown): unknown
			return Result.ok(environment.studioLaneIds)
		end,
		cleanup = function(_self: unknown): unknown
			environment.storeCleanupCalls += 1
			environment.storeCleanupDuringStep = environment.storeCleanupDuringStep or environment.inStep
			table.insert(environment.trace, "cleanup:store")
			if environment.storeCleanupMode == "false" then
				return Result.ok(false)
			end
			environment.storeCleaned = true
			return Result.ok(true)
		end,
	}

	local function publisherOk(name: string, runtimeEnemyId: unknown?): unknown
		table.insert(environment.trace, if runtimeEnemyId == nil then name else `{name}:{tostring(runtimeEnemyId)}`)
		return Result.ok(true)
	end

	environment.publisher = {
		preflightSpawn = function(_self: unknown): unknown
			if environment.preflightSpawnMode == "failure" then
				return Result.err(table.freeze({ code = "CAPACITY_EXCEEDED", operation = "preflightSpawn" }))
			elseif environment.preflightSpawnMode == "false" then
				return Result.ok(false)
			end
			return publisherOk("publisher:preflight-spawn")
		end,
		preflightStateChange = function(_self: unknown, runtimeEnemyId: unknown): unknown
			if environment.preflightStateChangeMode == "false" then
				return Result.ok(false)
			end
			return publisherOk("publisher:preflight-state", runtimeEnemyId)
		end,
		preflightEndpoint = function(_self: unknown, runtimeEnemyId: unknown): unknown
			if environment.preflightEndpointMode == "false" then
				return Result.ok(false)
			end
			return publisherOk("publisher:preflight-endpoint", runtimeEnemyId)
		end,
		preflightManualDespawn = function(_self: unknown, runtimeEnemyId: unknown): unknown
			if environment.preflightManualDespawnMode == "false" then
				return Result.ok(false)
			end
			return publisherOk("publisher:preflight-despawn", runtimeEnemyId)
		end,
		preflightDefeat = function(_self: unknown, runtimeEnemyIds: unknown): unknown
			environment.defeatPreflightIds = runtimeEnemyIds
			table.insert(environment.trace, "publisher:preflight-defeat")
			if environment.defeatPreflightMode == "failure" then
				return Result.err(table.freeze({ code = "CAPACITY_EXCEEDED" }))
			elseif environment.defeatPreflightMode == "false" then
				return Result.ok(false)
			end
			return Result.ok(true)
		end,
		preflightStep = function(_self: unknown, runtimeEnemyIds: unknown): unknown
			table.insert(environment.trace, "publisher:preflight-step")
			environment.preflightIds = runtimeEnemyIds
			if environment.preflightStepMode == "failure" then
				return Result.err(table.freeze({ code = "ILLEGAL_LIFECYCLE", operation = "preflightStep" }))
			elseif environment.preflightStepMode == "false" then
				return Result.ok(false)
			end
			return Result.ok(true)
		end,
		commitSpawn = function(_self: unknown, value: unknown): unknown
			environment.committedSpawn = value
			if environment.commitSpawnMode == "failure" then
				table.insert(environment.trace, "publisher:commit-spawn")
				return Result.err(table.freeze({ code = "INVALID_SNAPSHOT" }))
			end
			return publisherOk("publisher:commit-spawn")
		end,
		commitStateChange = function(_self: unknown, value: unknown): unknown
			environment.committedState = value
			return publisherOk("publisher:commit-state", (value :: any).runtimeEnemyId)
		end,
		commitEndpoint = function(_self: unknown, endpoint: unknown, despawn: unknown): unknown
			environment.committedEndpoint = endpoint
			environment.committedEndpointDespawn = despawn
			if environment.commitEndpointMode == "failure" then
				table.insert(
					environment.trace,
					`publisher:commit-endpoint:{tostring((endpoint :: any).runtimeEnemyId)}`
				)
				return Result.err(table.freeze({ code = "INVALID_SNAPSHOT", operation = "commitEndpoint" }))
			elseif environment.commitEndpointMode == "false" then
				table.insert(
					environment.trace,
					`publisher:commit-endpoint:{tostring((endpoint :: any).runtimeEnemyId)}`
				)
				return Result.ok(false)
			end
			return publisherOk("publisher:commit-endpoint", (endpoint :: any).runtimeEnemyId)
		end,
		commitManualDespawn = function(_self: unknown, value: unknown): unknown
			environment.committedDespawn = value
			if environment.commitManualDespawnMode == "failure" then
				table.insert(environment.trace, `publisher:commit-despawn:{tostring((value :: any).runtimeEnemyId)}`)
				return Result.err(table.freeze({ code = "INVALID_SNAPSHOT" }))
			end
			return publisherOk("publisher:commit-despawn", (value :: any).runtimeEnemyId)
		end,
		commitDefeat = function(_self: unknown, values: unknown): unknown
			environment.committedDefeat = values
			table.insert(environment.trace, "publisher:commit-defeat")
			if environment.defeatCommitMode == "failure" then
				return Result.err(table.freeze({ code = "INVALID_SNAPSHOT" }))
			end
			return Result.ok(values)
		end,
		observeCorrection = function(_self: unknown, runtimeEnemyId: unknown): unknown
			if environment.observeCorrectionMode == "false" then
				return Result.ok(false)
			end
			return publisherOk("publisher:correction", runtimeEnemyId)
		end,
		advance = function(_self: unknown, deltaSeconds: unknown, provider: unknown): unknown
			environment.advanceCalls += 1
			table.insert(environment.trace, "publisher:advance")
			environment.lastAdvanceDelta = deltaSeconds
			environment.lastProvider = provider
			if environment.advanceHook ~= nil then
				return environment.advanceHook(provider)
			elseif environment.advanceMode == "failure" then
				return Result.err(table.freeze({ code = "INVALID_PROVIDER" }))
			end
			return Result.ok(table.freeze({
				remainingPendingEntries = environment.publisherPending,
				remainingDirtyCorrections = environment.publisherDirty,
			}))
		end,
		requestSnapshot = function(_self: unknown, recipient: unknown, provider: unknown): unknown
			table.insert(environment.trace, "publisher:request-snapshot")
			environment.snapshotRecipient = recipient
			local providerResult = (provider :: any)(nil)
			environment.snapshotProviderResult = providerResult
			if environment.snapshotMode == "invalid-recipient" then
				return Result.err(table.freeze({ code = "INVALID_RECIPIENT", operation = "requestSnapshot" }))
			end
			return Result.ok(table.freeze({
				matchId = MATCH_ID,
				enemyEpoch = 1,
				baseSequence = 0,
				snapshotId = 1,
				chunkCount = 1,
				totalEntries = #providerResult.value,
			}))
		end,
		removePlayer = function(_self: unknown, recipient: unknown): unknown
			table.insert(environment.trace, "publisher:remove-player")
			environment.removedPlayer = recipient
			return Result.ok(true)
		end,
		getMetrics = function(_self: unknown): unknown
			return table.freeze({
				pendingEntryCount = environment.publisherPending,
				dirtyCorrectionCount = environment.publisherDirty,
				deltaMessageCount = environment.publisherDeltaMessages,
				reservedFutureMessageCount = environment.publisherReservedFutureMessages,
				reservedOrdinaryMessageCount = environment.publisherReservedOrdinaryMessages,
				nextSequence = environment.publisherNextSequence,
				faulted = environment.publisherFaulted,
				cleaned = environment.publisherCleaned,
			})
		end,
		cleanup = function(_self: unknown): unknown
			environment.publisherCleanupCalls += 1
			table.insert(environment.trace, "cleanup:publisher")
			if environment.publisherCleanupMode == "false" then
				return Result.ok(false)
			end
			environment.publisherCleaned = true
			return Result.ok(true)
		end,
	}

	environment.createStore = function(
		matchId: unknown,
		catalog: unknown,
		runtimeMap: unknown,
		endpointSink: unknown
	): unknown
		table.insert(environment.trace, "create:store")
		environment.factoryMatchId = matchId
		environment.factoryCatalog = catalog
		environment.factoryRuntimeMap = runtimeMap
		environment.endpointSink = endpointSink
		if environment.storeFactoryMode == "failure" then
			return Result.err(table.freeze({ code = "STORE_FAILED" }))
		end
		return Result.ok(environment.store)
	end

	environment.createPublisher = function(matchId: unknown, epoch: unknown, dependencies: unknown): unknown
		table.insert(environment.trace, "create:publisher")
		environment.publisherMatchId = matchId
		environment.publisherEpoch = epoch
		environment.publisherDependencies = dependencies
		if environment.publisherFactoryMode == "failure" then
			return Result.err(table.freeze({ code = "PUBLISHER_FAILED" }))
		end
		return Result.ok(environment.publisher)
	end

	local function connection(label: string): any
		local value: any = { connected = true }
		value.Disconnect = function(self: any)
			if not self.connected then
				return
			end
			self.connected = false
			if label == "step" then
				environment.stepDisconnectCalls += 1
			else
				environment.removalDisconnectCalls += 1
			end
			table.insert(environment.trace, `disconnect:{label}`)
		end
		return value
	end

	environment.connectStep = function(callback: EnemySimulationService.StepCallback): unknown
		table.insert(environment.trace, "connect:step")
		table.insert(environment.stepCallbacks, callback)
		if environment.connectorMode == "step-invalid" then
			return table.freeze({})
		elseif environment.connectorMode == "step-synchronous" then
			callback(9)
		end
		return connection("step")
	end

	environment.connectPlayerRemoving = function(callback: EnemySimulationService.PlayerRemovingCallback): unknown
		table.insert(environment.trace, "connect:removal")
		table.insert(environment.removalCallbacks, callback)
		if environment.connectorMode == "removal-invalid" then
			return table.freeze({})
		elseif environment.connectorMode == "removal-synchronous" then
			callback(table.freeze({ marker = "early" }))
		end
		return connection("removal")
	end

	environment.sender = function(_recipient: unknown, _message: unknown): boolean
		return true
	end
	environment.getRecipients = function(): unknown
		return {}
	end
	environment.dependencies = {
		matchLifecycle = environment.matchLifecycle,
		baseRuntime = environment.baseRuntime,
		catalog = environment.catalog,
		createStore = environment.createStore,
		createPublisher = environment.createPublisher,
		connectStep = environment.connectStep,
		connectPlayerRemoving = environment.connectPlayerRemoving,
		sender = environment.sender,
		getRecipients = environment.getRecipients,
	}
	return environment
end

local function createService(environment: any): EnemySimulationService.Service
	return (newForTests :: EnemySimulationService.TestConstructor)(environment.dependencies)
end

local function startService(environment: any): (EnemySimulationService.Service, any)
	local service = createService(environment)
	local definition = service:getServiceDefinition()
	invoke(definition.initialize)
	invoke(definition.start)
	return service, definition
end

local function configureDefeat(environment: any, passOrdinal: number?)
	local ordinal = passOrdinal or 1
	environment.basePreparedToken = table.freeze({})
	environment.baseFinishResults[ordinal] = Result.ok(table.freeze({
		kind = "DefeatPending",
		passOrdinal = ordinal,
		baseRevision = 2,
		appliedDamage = 100,
		leakCount = 1,
		lowHealthCrossed = true,
		preparedDefeat = environment.basePreparedToken,
	}))
end

local function waveSpawnEvent(environment: any, sampleServerTime: number): any
	return table.freeze({
		originatingWaveIndex = 1,
		waveId = "wave:phase11-service",
		groupIndex = 1,
		spawnOrdinal = 0,
		scheduledServerTime = sampleServerTime,
		enemyId = environment.waveFixture.primary.schedule.waves[1].groups[1].enemyId,
		laneId = "main",
	})
end

local function makeWaveBoundary(environment: any): any
	local adapter: any = {}
	adapter.onEnemyPass = function(_self: unknown, frame: any): unknown
		table.insert(environment.trace, `wave:pass:{frame.disposition}`)
		table.insert(environment.waveFrames, frame)
		environment.lastWaveFrame = frame
		if environment.wavePassMode == "throw" then
			error("PRIVATE_WAVE_FAILURE", 0)
		elseif environment.wavePassMode == "yield" then
			coroutine.yield()
		elseif environment.wavePassMode == "failure" then
			return Result.err(table.freeze({ code = "FAULTED" }))
		end
		if environment.authenticateTerminalDuringPass ~= nil then
			environment.terminalAuthenticatedDuringPass = environment.service:isAuthenticatedTerminalOutcome(
				environment.waveHandle,
				environment.authenticateTerminalDuringPass
			)
		end
		if environment.spawnDuringWavePass then
			environment.schedulerCapability = frame.spawn
			environment.schedulerSpawnEvent = waveSpawnEvent(environment, frame.sampleServerTime)
			environment.schedulerSpawnOutcome = frame.spawn(environment.schedulerSpawnEvent)
		end
		if environment.wavePassMode == "throw-after-spawn" then
			error("PRIVATE_WAVE_FAILURE_AFTER_SPAWN", 0)
		elseif environment.wavePassMode == "yield-after-spawn" then
			coroutine.yield()
		elseif environment.wavePassMode == "failure-after-spawn" then
			return Result.err(table.freeze({ code = "FAULTED" }))
		end
		if environment.wavePassTerminalNoop then
			return Result.ok(false)
		end
		return Result.ok(true)
	end
	adapter.flushEnemyPass = function(_self: unknown, passOrdinal: unknown): unknown
		table.insert(environment.trace, `wave:flush:{tostring(passOrdinal)}`)
		environment.waveFlushCalls += 1
		if environment.waveFlushMode == "failure" then
			return Result.err(table.freeze({ code = "FAULTED" }))
		elseif environment.waveFlushMode == "shutdown" then
			return Result.ok(false)
		end
		return Result.ok(true)
	end
	adapter.close = function(_self: unknown, context: unknown): unknown
		table.insert(environment.trace, "wave:close")
		environment.waveCloseCalls += 1
		environment.waveCloseContext = context
		if environment.readDuringWaveClose then
			environment.waveCloseListResult = environment.service:list()
			environment.waveCloseMutationResult = environment.service:spawn("enemy:late", "main")
		end
		if environment.waveCloseMode == "failure" then
			return Result.err(table.freeze({ code = "FAULTED" }))
		end
		return Result.ok(true)
	end
	table.freeze(adapter)
	return adapter
end

local function createBoundWaveService(
	assertions: Assertions,
	initialSpawnAdmissionClosed: boolean?
): (any, any, any, any)
	local environment = makeEnvironment()
	if initialSpawnAdmissionClosed == true then
		environment.dependencies.initialSpawnAdmissionClosed = true
	end
	environment.waveFixture = WaveFixtures.createAuthenticatedFixture()
	environment.catalog = environment.waveFixture.configuration.enemies
	environment.dependencies.catalog = environment.catalog
	environment.waveFrames = {}
	environment.waveFlushCalls = 0
	environment.waveCloseCalls = 0
	environment.triggerCreateCalls = 0
	environment.dependencies.createRuntimeTrigger = function(_handler: (unknown) -> unknown): unknown
		environment.triggerCreateCalls += 1
		return nil
	end
	local service = createService(environment)
	environment.service = service
	local definition = service:getServiceDefinition()
	invoke(definition.initialize)
	local identity = success(assertions, service:getIdentity())
	assertions.equal(identity.matchId, MATCH_ID)
	local adapter = makeWaveBoundary(environment)
	local handle = success(assertions, service:installWaveBoundary(adapter))
	environment.waveHandle = handle
	local installedStatus = success(assertions, service:getWaveBoundaryStatus(handle))
	assertions.equal(installedStatus.status, "Installed")
	assertions.equal(installedStatus.difficultyId, nil)
	invoke(definition.start)
	assertions.equal(environment.triggerCreateCalls, 0)
	local token = success(
		assertions,
		service:prepareWaveBinding(
			handle,
			environment.waveFixture.configuration,
			environment.waveFixture.primary.difficultyDefinition
		)
	)
	local receipt = success(assertions, service:commitWaveBinding(token))
	assertions.equal(receipt.matchId, MATCH_ID)
	assertions.equal(receipt.enemyEpoch, 1)
	assertions.equal(receipt.difficultyId, WaveFixtures.PRIMARY_DIFFICULTY_ID)
	assertions.equal(receipt.generation, 1)
	assertions.equal(receipt.status, "Active")
	assertions.equal(success(assertions, service:getWaveBoundaryStatus(handle)).status, "Active")
	return environment, service, definition, handle
end

return TestHarness.suite("server enemy simulation and replication service", {
	TestHarness.case("constructs store then publisher and owns exactly two service connections", function(assertions)
		local environment = makeEnvironment()
		local service = createService(environment)
		local definition = service:getServiceDefinition()
		assertions.isTrue(table.isfrozen(service))
		assertions.isTrue(table.isfrozen(definition))
		assertions.equal(definition.name, "EnemySimulation")
		assertions.equal(#definition.dependencies, 3)
		assertions.equal(definition.dependencies[1], "NetworkRegistry")
		assertions.equal(definition.dependencies[2], "MatchLifecycle")
		assertions.equal(definition.dependencies[3], "BaseRuntime")

		invoke(definition.initialize)
		assertions.equal(service:getLifecycleState(), "Initialized")
		assertions.isTrue(indexOf(environment.trace, "create:store") < indexOf(environment.trace, "store:identity"))
		assertions.isTrue(indexOf(environment.trace, "store:identity") < indexOf(environment.trace, "create:publisher"))
		assertions.equal(environment.publisherMatchId, MATCH_ID)
		assertions.equal(environment.publisherEpoch, 1)
		assertions.isTrue(table.isfrozen(environment.publisherDependencies))

		invoke(definition.start)
		local metrics = service:getMetrics()
		assertions.equal(metrics.stepConnectionCount, 1)
		assertions.equal(metrics.playerRemovingConnectionCount, 1)
		invoke(definition.shutdown)
		assertions.equal(service:getLifecycleState(), "Shutdown")
		assertions.equal(environment.stepDisconnectCalls, 1)
		assertions.equal(environment.removalDisconnectCalls, 1)
		assertions.isTrue(indexOf(environment.trace, "cleanup:publisher") < indexOf(environment.trace, "cleanup:store"))
		local cleanedMetrics = service:getMetrics()
		assertions.isFalse(cleanedMetrics.retainsPublisher)
		assertions.isFalse(cleanedMetrics.retainsStore)
		invoke(definition.shutdown)
		assertions.equal(environment.publisherCleanupCalls, 1)
		assertions.equal(environment.storeCleanupCalls, 1)

		for _, cleanupCase in
			{
				function(falseEnvironment: any)
					falseEnvironment.publisherCleanupMode = "false"
				end,
				function(falseEnvironment: any)
					falseEnvironment.storeCleanupMode = "false"
				end,
			}
		do
			local falseEnvironment = makeEnvironment()
			cleanupCase(falseEnvironment)
			local falseService, falseDefinition = startService(falseEnvironment)
			expectStaticFailure(assertions, function()
				invoke(falseDefinition.shutdown)
			end, "CLEANUP_FAILED")
			assertions.equal(falseService:getLifecycleState(), "Failed")
			assertions.equal(falseEnvironment.publisherCleanupCalls, 1)
			assertions.equal(falseEnvironment.storeCleanupCalls, 1)
			assertions.isTrue(
				indexOf(falseEnvironment.trace, "cleanup:publisher") < indexOf(falseEnvironment.trace, "cleanup:store")
			)
			assertions.isFalse(falseService:getMetrics().retainsPublisher)
			assertions.isFalse(falseService:getMetrics().retainsStore)
		end
	end),

	TestHarness.case("preflights the complete set and commits mixed step effects in store order", function(assertions)
		local environment = makeEnvironment()
		environment.activeSnapshots = { snapshot(1), snapshot(2), snapshot(3) }
		environment.stepHook = function(deltaSeconds: number): unknown
			return Result.ok(makeStepResult(deltaSeconds, { 1, 3 }, { endpointResolution(2) }))
		end
		local _service, definition = startService(environment)
		environment.stepCallbacks[1](0.25)
		assertions.isTrue(table.isfrozen(environment.preflightIds))
		assertions.equal(#environment.preflightIds, 3)
		assertions.equal(environment.preflightIds[1], 1)
		assertions.equal(environment.preflightIds[3], 3)
		assertions.isTrue(
			indexOf(environment.trace, "publisher:preflight-step") < indexOf(environment.trace, "store:step")
		)
		local correctionOne = indexOf(environment.trace, "publisher:correction:1")
		local endpointTwo = indexOf(environment.trace, "publisher:commit-endpoint:2")
		local correctionThree = indexOf(environment.trace, "publisher:correction:3")
		assertions.isTrue(correctionOne < endpointTwo and endpointTwo < correctionThree)
		assertions.isTrue(correctionThree < indexOf(environment.trace, "publisher:advance"))
		assertions.equal(environment.advanceCalls, 1)
		invoke(definition.shutdown)

		for _, commitCase in
			{
				{
					configure = function(falseEnvironment: any)
						falseEnvironment.commitEndpointMode = "false"
						falseEnvironment.stepHook = function(deltaSeconds: number): unknown
							return Result.ok(makeStepResult(deltaSeconds, {}, { endpointResolution(1) }))
						end
					end,
				},
				{
					configure = function(falseEnvironment: any)
						falseEnvironment.observeCorrectionMode = "false"
						falseEnvironment.stepHook = function(deltaSeconds: number): unknown
							return Result.ok(makeStepResult(deltaSeconds, { 1 }, {}))
						end
					end,
				},
			}
		do
			local falseEnvironment = makeEnvironment()
			falseEnvironment.activeSnapshots = { snapshot(1) }
			commitCase.configure(falseEnvironment)
			local falseService, falseDefinition = startService(falseEnvironment)
			assertions.isTrue(pcall(falseEnvironment.stepCallbacks[1], 0.25))
			assertions.equal(falseService:getLifecycleState(), "Failed")
			assertions.equal(falseEnvironment.advanceCalls, 0)
			assertions.equal(falseEnvironment.baseFaultCalls, 1)
			invoke(falseDefinition.shutdown)
		end
	end),

	TestHarness.case(
		"preflight rejection prevents store mutation and enters a cleanup-safe failure",
		function(assertions)
			for _, mode in { "failure", "false" } do
				local environment = makeEnvironment()
				environment.activeSnapshots = { snapshot(1), snapshot(2) }
				environment.preflightStepMode = mode
				local service, definition = startService(environment)
				environment.stepCallbacks[1](0.25)
				assertions.equal(environment.stepCalls, 0)
				assertions.equal(service:getLifecycleState(), "Failed")
				assertions.equal(environment.stepDisconnectCalls, 1)
				assertions.equal(environment.publisherCleanupCalls, 0)
				assertions.equal(environment.storeCleanupCalls, 0)
				invoke(definition.shutdown)
				assertions.equal(service:getLifecycleState(), "Shutdown")
				assertions.isTrue(
					indexOf(environment.trace, "cleanup:publisher") < indexOf(environment.trace, "cleanup:store")
				)
			end
		end
	),

	TestHarness.case("drains committed publisher work after a store fault without stepping again", function(assertions)
		local environment = makeEnvironment()
		environment.activeSnapshots = { snapshot(1) }
		environment.publisherPending = 1
		environment.stepHook = function(deltaSeconds: number): unknown
			return Result.ok(makeStepResult(deltaSeconds, { 1 }, {}, false, true))
		end
		local service, definition = startService(environment)
		environment.stepCallbacks[1](0.2)
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.isTrue(service:getMetrics().faultDrainActive)
		assertions.equal(environment.stepCalls, 1)
		environment.advanceHook = function(_provider: unknown): unknown
			environment.publisherPending = 0
			return Result.ok(table.freeze({ remainingPendingEntries = 0, remainingDirtyCorrections = 0 }))
		end
		environment.stepCallbacks[1](0.2)
		assertions.equal(environment.stepCalls, 1)
		assertions.equal(environment.advanceCalls, 2)
		assertions.isFalse(service:getMetrics().faultDrainActive)
		assertions.equal(environment.stepDisconnectCalls, 1)
		assertions.equal(environment.publisherCleanupCalls, 0)
		invoke(definition.shutdown)
		assertions.equal(environment.publisherCleanupCalls, 1)
		assertions.equal(environment.storeCleanupCalls, 1)
	end),

	TestHarness.case("never retains Heartbeat solely for an unfundable dirty correction", function(assertions)
		local environment = makeEnvironment()
		environment.activeSnapshots = { snapshot(1) }
		environment.publisherDirty = 1
		environment.publisherDeltaMessages = 131_072
		environment.stepHook = function(deltaSeconds: number): unknown
			return Result.ok(makeStepResult(deltaSeconds, { 1 }, {}, false, true))
		end
		local service, definition = startService(environment)
		environment.stepCallbacks[1](0.2)
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.isFalse(service:getMetrics().faultDrainActive)
		assertions.equal(environment.stepDisconnectCalls, 1)
		local advancesAfterFault = environment.advanceCalls
		environment.stepCallbacks[1](0.2)
		assertions.equal(environment.advanceCalls, advancesAfterFault)
		invoke(definition.shutdown)
	end),

	TestHarness.case("drains a dirty correction after funded publication releases final capacity", function(assertions)
		local environment = makeEnvironment()
		environment.activeSnapshots = { snapshot(1) }
		environment.publisherPending = 1
		environment.publisherDirty = 1
		environment.publisherDeltaMessages = 131_070
		environment.publisherReservedOrdinaryMessages = 1
		environment.stepHook = function(deltaSeconds: number): unknown
			return Result.ok(makeStepResult(deltaSeconds, { 1 }, {}, false, true))
		end
		environment.advanceHook = function(_provider: unknown): unknown
			if environment.advanceCalls == 2 then
				environment.publisherPending = 0
				environment.publisherReservedOrdinaryMessages = 0
				environment.publisherDeltaMessages = 131_071
			elseif environment.advanceCalls == 3 then
				environment.publisherDirty = 0
				environment.publisherDeltaMessages = 131_072
			end
			return Result.ok(table.freeze({
				remainingPendingEntries = environment.publisherPending,
				remainingDirtyCorrections = environment.publisherDirty,
			}))
		end
		local service, definition = startService(environment)
		environment.stepCallbacks[1](0.2)
		assertions.isTrue(service:getMetrics().faultDrainActive)
		environment.stepCallbacks[1](0.2)
		assertions.isTrue(service:getMetrics().faultDrainActive)
		assertions.equal(environment.stepDisconnectCalls, 0)
		environment.stepCallbacks[1](0.2)
		assertions.isFalse(service:getMetrics().faultDrainActive)
		assertions.equal(environment.stepCalls, 1)
		assertions.equal(environment.advanceCalls, 3)
		assertions.equal(environment.stepDisconnectCalls, 1)
		invoke(definition.shutdown)
	end),

	TestHarness.case(
		"facade performs exact preflight store commit transactions and skips no-op slow publication",
		function(assertions)
			local environment = makeEnvironment()
			local service, definition = startService(environment)
			local spawnResult = service:spawn("enemy:test", "lane:test")
			assertions.isTrue(spawnResult.ok)
			assertions.isTrue(
				indexOf(environment.trace, "publisher:preflight-spawn") < indexOf(environment.trace, "store:spawn")
			)
			assertions.isTrue(
				indexOf(environment.trace, "store:spawn") < indexOf(environment.trace, "publisher:commit-spawn")
			)

			local slowResult = service:setSlowMultiplier(1, 0.5)
			assertions.isTrue(slowResult.ok)
			assertions.isTrue(
				indexOf(environment.trace, "publisher:preflight-state:1") < indexOf(environment.trace, "store:slow:1")
			)
			assertions.isTrue(
				indexOf(environment.trace, "store:slow:1") < indexOf(environment.trace, "publisher:commit-state:1")
			)
			local stateCommitCount = 0
			for _, event in environment.trace do
				if event == "publisher:commit-state:1" then
					stateCommitCount += 1
				end
			end
			local unchangedResult = service:setSlowMultiplier(1, 0.5)
			assertions.isTrue(unchangedResult.ok)
			local stateCommitCountAfter = 0
			for _, event in environment.trace do
				if event == "publisher:commit-state:1" then
					stateCommitCountAfter += 1
				end
			end
			assertions.equal(stateCommitCountAfter, stateCommitCount)

			local endpointResult = service:resolveEndpoint(1)
			assertions.isTrue(endpointResult.ok)
			assertions.isTrue(
				indexOf(environment.trace, "publisher:preflight-endpoint:1")
					< indexOf(environment.trace, "store:endpoint:1")
			)
			assertions.isTrue(
				indexOf(environment.trace, "store:endpoint:1")
					< indexOf(environment.trace, "publisher:commit-endpoint:1")
			)
			invoke(definition.shutdown)

			for _, preflightCase in
				{
					{
						configure = function(falseEnvironment: any)
							falseEnvironment.preflightSpawnMode = "false"
						end,
						invoke = function(falseService: any): unknown
							return falseService:spawn("enemy:test", "lane:test")
						end,
						forbiddenTrace = "store:spawn",
					},
					{
						configure = function(falseEnvironment: any)
							falseEnvironment.activeSnapshots = { snapshot(1) }
							falseEnvironment.preflightStateChangeMode = "false"
						end,
						invoke = function(falseService: any): unknown
							return falseService:setSlowMultiplier(1, 0.5)
						end,
						forbiddenTrace = "store:slow:1",
					},
					{
						configure = function(falseEnvironment: any)
							falseEnvironment.activeSnapshots = { snapshot(1) }
							falseEnvironment.preflightEndpointMode = "false"
						end,
						invoke = function(falseService: any): unknown
							return falseService:resolveEndpoint(1)
						end,
						forbiddenTrace = "store:endpoint:1",
					},
					{
						configure = function(falseEnvironment: any)
							falseEnvironment.activeSnapshots = { snapshot(1) }
							falseEnvironment.preflightManualDespawnMode = "false"
						end,
						invoke = function(falseService: any): unknown
							return falseService:despawn(1)
						end,
						forbiddenTrace = "store:despawn:1",
					},
				}
			do
				local falseEnvironment = makeEnvironment()
				preflightCase.configure(falseEnvironment)
				local falseService, falseDefinition = startService(falseEnvironment)
				local falseResult = preflightCase.invoke(falseService) :: any
				assertions.isFalse(falseResult.ok)
				assertions.equal(falseResult.error.code, "INTERNAL_ERROR")
				assertions.equal(indexOf(falseEnvironment.trace, preflightCase.forbiddenTrace), 0)
				invoke(falseDefinition.shutdown)
			end
		end
	),

	TestHarness.case("coordinates one ordered defeat and closes every future gameplay admission", function(assertions)
		local environment = makeEnvironment()
		configureDefeat(environment)
		local service, definition = startService(environment)
		for index = 1, 3 do
			success(assertions, service:spawn(`enemy:{index}`, "lane:main"))
		end

		local endpoint = service:resolveEndpoint(1)
		assertions.isTrue(endpoint.ok)
		assertions.equal(environment.baseRecordLeakCalls, 1)
		assertions.equal(environment.baseFinishCalls, 1)
		assertions.equal(environment.lifecycleBeginCalls, 1)
		assertions.equal(environment.lifecycleCommitCalls, 1)
		assertions.equal(environment.lifecycleRollbackCalls, 0)
		assertions.equal(environment.baseCommitCalls, 1)
		assertions.equal(environment.baseFailCalls, 0)
		assertions.equal(#environment.defeatStoreIds, 2)
		assertions.equal(environment.defeatStoreIds[1], 2)
		assertions.equal(environment.defeatStoreIds[2], 3)
		assertions.equal(#environment.committedDefeat, 2)
		for _, despawn in environment.committedDefeat do
			assertions.equal(despawn.reason, "Defeat")
		end
		assertions.isTrue(
			indexOf(environment.trace, "publisher:commit-endpoint:1") < indexOf(environment.trace, "base:finish:1")
		)
		assertions.isTrue(
			indexOf(environment.trace, "publisher:preflight-defeat")
				< indexOf(environment.trace, "lifecycle:begin-defeat")
		)
		assertions.isTrue(
			indexOf(environment.trace, "store:defeat-all") < indexOf(environment.trace, "publisher:commit-defeat")
		)
		assertions.isTrue(
			indexOf(environment.trace, "publisher:commit-defeat")
				< indexOf(environment.trace, "lifecycle:commit-defeat")
		)
		assertions.isTrue(
			indexOf(environment.trace, "lifecycle:commit-defeat") < indexOf(environment.trace, "base:commit-defeat")
		)

		local metrics = service:getMetrics()
		assertions.isTrue(metrics.spawnAdmissionClosed)
		assertions.equal(metrics.defeatCount, 1)
		assertions.equal(metrics.resultsCommitCount, 1)
		assertions.equal(metrics.nextEnemyPassOrdinal, 2)
		local futureSpawn = service:spawn("enemy:late", "lane:main")
		assertions.isFalse(futureSpawn.ok)
		assertions.equal(futureSpawn.error.code, "UNAVAILABLE")
		local futureEndpoint = service:resolveEndpoint(2)
		assertions.isFalse(futureEndpoint.ok)
		assertions.equal(futureEndpoint.error.code, "UNAVAILABLE")
		local lateSnapshot = service:requestSnapshot(table.freeze({ player = true }))
		assertions.isTrue(lateSnapshot.ok)
		environment.stepCallbacks[1](0.1)
		assertions.equal(environment.baseFinishCalls, 1)
		assertions.equal(environment.lifecycleCommitCalls, 1)
		assertions.equal(environment.baseRecordLeakCalls, 1)
		invoke(definition.shutdown)
	end),

	TestHarness.case("faults the queued lethal base pass when direct endpoint publication fails", function(assertions)
		for _, commitCase in
			{
				{ mode = "failure", code = "INVALID_SNAPSHOT" },
				{ mode = "false", code = "INTERNAL_ERROR" },
			}
		do
			local environment = makeEnvironment()
			configureDefeat(environment)
			environment.commitEndpointMode = commitCase.mode
			local service, definition = startService(environment)
			success(assertions, service:spawn("enemy:lethal", "lane:main"))

			local resolved = service:resolveEndpoint(1)
			assertions.isFalse(resolved.ok)
			assertions.equal(resolved.error.code, commitCase.code)
			assertions.equal(environment.baseRecordLeakCalls, 1)
			assertions.equal(environment.baseFinishCalls, 0)
			assertions.equal(environment.baseFaultCalls, 1)
			assertions.equal(environment.lifecycleBeginCalls, 0)
			assertions.equal(service:getLifecycleState(), "Failed")
			assertions.isTrue(service:getMetrics().spawnAdmissionClosed)
			assertions.isTrue(
				indexOf(environment.trace, "store:endpoint:1")
					< indexOf(environment.trace, "publisher:commit-endpoint:1")
			)
			assertions.isTrue(
				indexOf(environment.trace, "publisher:commit-endpoint:1") < indexOf(environment.trace, "base:fault")
			)
			assertions.isFalse(service:spawn("enemy:late", "lane:main").ok)
			invoke(definition.shutdown)
		end
	end),

	TestHarness.case("faults the queued lethal base pass when batched endpoint publication fails", function(assertions)
		local environment = makeEnvironment()
		configureDefeat(environment)
		environment.activeSnapshots = { snapshot(1) }
		environment.commitEndpointMode = "failure"
		environment.stepHook = function(deltaSeconds: number): unknown
			local recorded = pcall(environment.endpointSink, table.freeze({ runtimeEnemyId = 1 }))
			if not recorded then
				error("failed to record batched endpoint fixture", 0)
			end
			table.clear(environment.activeSnapshots)
			return Result.ok(makeStepResult(deltaSeconds, {}, { endpointResolution(1) }))
		end
		local service, definition = startService(environment)

		assertions.isTrue(pcall(environment.stepCallbacks[1], 0.25))
		assertions.equal(environment.baseRecordLeakCalls, 1)
		assertions.equal(environment.baseFinishCalls, 0)
		assertions.equal(environment.baseFaultCalls, 1)
		assertions.equal(environment.lifecycleBeginCalls, 0)
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.isTrue(service:getMetrics().spawnAdmissionClosed)
		assertions.isTrue(
			indexOf(environment.trace, "store:step") < indexOf(environment.trace, "publisher:commit-endpoint:1")
		)
		assertions.isTrue(
			indexOf(environment.trace, "publisher:commit-endpoint:1") < indexOf(environment.trace, "base:fault")
		)
		invoke(definition.shutdown)
	end),

	TestHarness.case(
		"faults closed at pass ordinal exhaustion without retaining an unsafe successor",
		function(assertions)
			local environment = makeEnvironment()
			environment.dependencies.initialEnemyPassOrdinal = Validation.MAX_SAFE_INTEGER
			local service, definition = startService(environment)

			assertions.isTrue(pcall(environment.stepCallbacks[1], 0.25))
			assertions.equal(environment.baseFinishCalls, 1)
			assertions.equal(environment.baseFaultCalls, 1)
			assertions.equal(service:getLifecycleState(), "Failed")
			assertions.isTrue(service:getMetrics().spawnAdmissionClosed)
			assertions.equal(service:getMetrics().nextEnemyPassOrdinal, Validation.MAX_SAFE_INTEGER)
			assertions.isTrue(Validation.isSafeInteger(service:getMetrics().nextEnemyPassOrdinal))
			invoke(definition.shutdown)
		end
	),

	TestHarness.case("preserves committed defeat when match or base publication reports failure", function(assertions)
		local environment = makeEnvironment()
		configureDefeat(environment)
		environment.lifecyclePublishMode = "failure"
		environment.basePublishMode = "failure"
		local service, definition = startService(environment)
		success(assertions, service:spawn("enemy:lethal", "lane:main"))
		assertions.isTrue(service:resolveEndpoint(1).ok)
		assertions.equal(service:getLifecycleState(), "Started")
		assertions.equal(service:getMetrics().resultsCommitCount, 1)
		assertions.equal(environment.lifecycleCommitCalls, 1)
		assertions.equal(environment.baseCommitCalls, 1)
		assertions.equal(environment.baseFailCalls, 0)
		assertions.isFalse(service:spawn("enemy:late", "lane:main").ok)
		invoke(definition.shutdown)
	end),

	TestHarness.case("faults closed at every precommit defeat boundary without reopening spawns", function(assertions)
		local scenarios = {
			{ field = "defeatPreflightMode", value = "failure", began = 0, rolledBack = 0, baseFailed = 1 },
			{ field = "defeatPreflightMode", value = "false", began = 0, rolledBack = 0, baseFailed = 1 },
			{ field = "lifecycleBeginMode", value = "failure", began = 1, rolledBack = 0, baseFailed = 1 },
			{ field = "defeatStoreMode", value = "failure", began = 1, rolledBack = 1, baseFailed = 1 },
			{ field = "defeatCommitMode", value = "failure", began = 1, rolledBack = 1, baseFailed = 1 },
			{ field = "lifecycleCommitMode", value = "failure", began = 1, rolledBack = 1, baseFailed = 1 },
		}
		for _, scenario in scenarios do
			local environment = makeEnvironment()
			configureDefeat(environment)
			environment[scenario.field] = scenario.value
			local service, definition = startService(environment)
			success(assertions, service:spawn("enemy:lethal", "lane:main"))
			assertions.isTrue(service:resolveEndpoint(1).ok)
			assertions.equal(service:getLifecycleState(), "Failed")
			assertions.isTrue(service:getMetrics().spawnAdmissionClosed)
			assertions.equal(environment.lifecycleBeginCalls, scenario.began)
			assertions.equal(environment.lifecycleRollbackCalls, scenario.rolledBack)
			assertions.equal(environment.baseFailCalls, scenario.baseFailed)
			assertions.isFalse(service:spawn("enemy:late", "lane:main").ok)
			invoke(definition.shutdown)
		end
	end),

	TestHarness.case("contains endpoint callback failure after terminalizing the leaking enemy", function(assertions)
		local environment = makeEnvironment()
		environment.baseRecordMode = "failure"
		local service, definition = startService(environment)
		success(assertions, service:spawn("enemy:callback", "lane:main"))
		local resolved = service:resolveEndpoint(1)
		assertions.isTrue(resolved.ok)
		assertions.isFalse(resolved.value.callbackSucceeded)
		assertions.equal(environment.committedEndpoint.runtimeEnemyId, 1)
		assertions.equal(environment.committedEndpointDespawn.reason, "Endpoint")
		assertions.equal(environment.baseFinishCalls, 1)
		assertions.equal(service:getLifecycleState(), "Failed")
		invoke(definition.shutdown)
	end),

	TestHarness.case(
		"defers shutdown through the complete defeat boundary before reverse cleanup",
		function(assertions)
			local environment = makeEnvironment()
			configureDefeat(environment)
			local service, definition = startService(environment)
			success(assertions, service:spawn("enemy:lethal", "lane:main"))
			success(assertions, service:spawn("enemy:remaining", "lane:main"))
			environment.defeatStoreHook = function()
				invoke(definition.shutdown)
				assertions.equal(service:getLifecycleState(), "ShuttingDown")
				assertions.equal(environment.publisherCleanupCalls, 0)
			end
			assertions.isTrue(service:resolveEndpoint(1).ok)
			assertions.equal(environment.lifecycleCommitCalls, 1)
			assertions.equal(environment.baseCommitCalls, 1)
			assertions.equal(service:getLifecycleState(), "Shutdown")
			assertions.equal(environment.publisherCleanupCalls, 1)
			assertions.equal(environment.storeCleanupCalls, 1)
			assertions.isTrue(
				indexOf(environment.trace, "base:commit-defeat") < indexOf(environment.trace, "cleanup:publisher")
			)
		end
	),

	TestHarness.case("spawn preflight and store failures never create a publisher representation", function(assertions)
		local preflightEnvironment = makeEnvironment()
		preflightEnvironment.preflightSpawnMode = "failure"
		local preflightService, preflightDefinition = startService(preflightEnvironment)
		assertions.isFalse(preflightService:spawn("enemy:test", "lane:test").ok)
		assertions.equal(indexOf(preflightEnvironment.trace, "store:spawn"), 0)
		assertions.equal(indexOf(preflightEnvironment.trace, "publisher:commit-spawn"), 0)
		invoke(preflightDefinition.shutdown)

		local storeEnvironment = makeEnvironment()
		storeEnvironment.storeMutationMode = "failure"
		local storeService, storeDefinition = startService(storeEnvironment)
		assertions.isFalse(storeService:spawn("enemy:test", "lane:test").ok)
		assertions.isTrue(indexOf(storeEnvironment.trace, "publisher:preflight-spawn") > 0)
		assertions.equal(indexOf(storeEnvironment.trace, "publisher:commit-spawn"), 0)
		invoke(storeDefinition.shutdown)
	end),

	TestHarness.case(
		"snapshot request uses the synchronous all-active provider and removal forwards exact identity",
		function(assertions)
			local environment = makeEnvironment()
			environment.activeSnapshots = { snapshot(1), snapshot(2) }
			local service = createService(environment)
			assertions.isFalse(service:requestSnapshot(table.freeze({ marker = "early" })).ok)
			local definition = service:getServiceDefinition()
			invoke(definition.initialize)
			invoke(definition.start)
			local recipient = table.freeze({ marker = "player" })
			local receipt = service:requestSnapshot(recipient)
			assertions.isTrue(receipt.ok)
			assertions.equal(environment.snapshotRecipient, recipient)
			assertions.isTrue(environment.snapshotProviderResult.ok)
			assertions.equal(#environment.snapshotProviderResult.value, 2)
			environment.removalCallbacks[1](recipient)
			assertions.equal(environment.removedPlayer, recipient)
			invoke(definition.shutdown)
			environment.removalCallbacks[1](table.freeze({ marker = "late" }))
			assertions.equal(environment.removedPlayer, recipient)
			assertions.isFalse(service:requestSnapshot(recipient).ok)
		end
	),

	TestHarness.case(
		"shutdown during a step commits captured terminal state before publisher-first cleanup",
		function(assertions)
			local environment = makeEnvironment()
			environment.activeSnapshots = { snapshot(1), snapshot(2) }
			local service = createService(environment)
			local definition = service:getServiceDefinition()
			invoke(definition.initialize)
			invoke(definition.start)
			environment.stepHook = function(deltaSeconds: number): unknown
				invoke(definition.shutdown)
				return Result.ok(makeStepResult(deltaSeconds, { 1 }, { endpointResolution(2) }, true, false))
			end
			assertions.isTrue(pcall(environment.stepCallbacks[1], 0.1))
			assertions.equal(service:getLifecycleState(), "Shutdown")
			assertions.isFalse(environment.storeCleanupDuringStep)
			assertions.equal(indexOf(environment.trace, "publisher:correction:1"), 0)
			assertions.isTrue(indexOf(environment.trace, "publisher:commit-endpoint:2") > 0)
			assertions.equal(environment.advanceCalls, 0)
			assertions.isTrue(
				indexOf(environment.trace, "cleanup:publisher") < indexOf(environment.trace, "cleanup:store")
			)
		end
	),

	TestHarness.case("contains thrown failed yielding and malformed update results", function(assertions)
		for _, mode in { "throw", "failure", "yield" } do
			local environment = makeEnvironment()
			local service, definition = startService(environment)
			environment.stepMode = mode
			assertions.isTrue(pcall(environment.stepCallbacks[1], 0.25))
			assertions.equal(service:getLifecycleState(), "Failed")
			assertions.equal(environment.stepDisconnectCalls, 1)
			assertions.equal(environment.publisherCleanupCalls, 0)
			invoke(definition.shutdown)
		end

		local malformedEnvironment = makeEnvironment()
		local malformedService, malformedDefinition = startService(malformedEnvironment)
		malformedEnvironment.stepHook = function(_deltaSeconds: number): unknown
			return Result.ok(table.freeze({ cleaned = false, faulted = false }))
		end
		assertions.isTrue(pcall(malformedEnvironment.stepCallbacks[1], 0.25))
		assertions.equal(malformedService:getLifecycleState(), "Failed")
		invoke(malformedDefinition.shutdown)
	end),

	TestHarness.case(
		"suppresses synchronous connector callbacks and cleans partial start failure",
		function(assertions)
			local synchronous = makeEnvironment()
			synchronous.connectorMode = "step-synchronous"
			local _synchronousService, synchronousDefinition = startService(synchronous)
			assertions.equal(synchronous.stepCalls, 0)
			invoke(synchronousDefinition.shutdown)

			local failed = makeEnvironment()
			failed.connectorMode = "step-invalid"
			local failedService = createService(failed)
			local failedDefinition = failedService:getServiceDefinition()
			invoke(failedDefinition.initialize)
			expectStaticFailure(assertions, function()
				invoke(failedDefinition.start)
			end, "CONNECTION_FAILED")
			assertions.equal(failed.removalDisconnectCalls, 1)
			assertions.isTrue(indexOf(failed.trace, "cleanup:publisher") < indexOf(failed.trace, "cleanup:store"))
		end
	),

	TestHarness.case("owns one exact Studio-only trigger with bounded server-selected operations", function(assertions)
		local environment = makeEnvironment()
		environment.matchState = "PreWave"
		local triggerHandler: ((unknown) -> unknown)? = nil
		environment.triggerCreateCalls = 0
		environment.triggerDestroyCalls = 0
		environment.dependencies.isStudio = function(): unknown
			return true
		end
		environment.dependencies.createRuntimeTrigger = function(handler: (unknown) -> unknown): unknown
			environment.triggerCreateCalls += 1
			triggerHandler = handler
			return {
				Destroy = function(_self: unknown)
					environment.triggerDestroyCalls += 1
				end,
			}
		end

		local service, definition = startService(environment)
		assertions.equal(environment.triggerCreateCalls, 1)
		assertions.equal(service:getMetrics().studioTriggerCount, 1)
		local handler = triggerHandler :: (unknown) -> unknown
		assertions.isFalse((handler({ operation = "SpawnFixture", variant = "Measurement" }) :: any).ok)
		assertions.isFalse((handler({ operation = "InstallFixtures", extra = true }) :: any).ok)
		assertions.isFalse((handler({ operation = "SetSlow", runtimeEnemyId = 1, multiplier = 0.5 }) :: any).ok)
		assertions.isFalse((handler({ operation = "Despawn", runtimeEnemyId = 1 }) :: any).ok)
		assertions.isFalse((handler({ operation = "Snapshot" }) :: any).ok)
		assertions.isFalse((handler({ operation = "SpawnBatch", batch = 32 }) :: any).ok)
		assertions.isFalse((handler(setmetatable({ operation = "Diagnostics" }, {})) :: any).ok)

		local nestedResult: any = nil
		environment.baseStudioCatalogHook = function()
			nestedResult = handler({ operation = "Diagnostics" })
		end
		local installed = handler({ operation = "InstallFixtures" }) :: any
		assertions.isTrue(installed.ok)
		assertions.equal(nestedResult.error.code, "REENTRANT")
		assertions.equal(environment.baseStudioCatalogInstallCalls, 1)
		assertions.equal(environment.studioCatalogInstallCalls, 1)
		assertions.isTrue(EnemySchema.isValidatedCatalog(environment.installedStudioCatalog))
		assertions.isTrue(DifficultySchema.isValidatedCatalog(environment.installedStudioDifficultyCatalog))
		assertions.equal(installed.value.laneId, "alpha-bent")
		assertions.isTrue(table.isfrozen(installed.value.baseVariants))
		assertions.isTrue(table.isfrozen(installed.value.enemyVariants))
		assertions.isTrue(table.isfrozen(installed.value.batchVariants))
		assertions.equal(#installed.value.enemyVariants, 8)
		assertions.equal(environment.installedStudioCatalog.byId["enemy:phase10-studio-measurement"].leakDamage, 1)
		assertions.equal(environment.installedStudioCatalog.byId["enemy:phase10-studio-zero"].leakDamage, 0)
		assertions.equal(environment.installedStudioCatalog.byId["enemy:phase10-studio-ordinary"].leakDamage, 25)
		assertions.equal(environment.installedStudioCatalog.byId["enemy:phase10-studio-low"].leakDamage, 750_000)
		assertions.equal(environment.installedStudioCatalog.byId["enemy:phase10-studio-exact"].leakDamage, 100)
		assertions.equal(environment.installedStudioCatalog.byId["enemy:phase10-studio-overkill"].leakDamage, 101)
		assertions.equal(
			environment.installedStudioCatalog.byId["enemy:phase10-studio-high"].leakDamage,
			Validation.MAX_SAFE_INTEGER
		)
		assertions.equal(environment.installedStudioCatalog.byId["enemy:phase10-studio-survivor"].leakDamage, 25)
		assertions.equal(environment.installedStudioCatalog.byId["enemy:phase10-studio-survivor"].tags, nil)
		assertions.equal(
			environment.installedStudioDifficultyCatalog.byId["difficulty:phase10-studio-measurement"].base.maxHealth,
			1_000_000
		)
		assertions.equal(
			environment.installedStudioDifficultyCatalog.byId["difficulty:phase10-studio-defeat"].base.maxHealth,
			100
		)
		assertions.isTrue(service:getMetrics().studioCatalogInstalled)
		assertions.isFalse((handler({ operation = "InstallFixtures" }) :: any).ok)
		assertions.isFalse((handler({ operation = "ActivateWave" }) :: any).ok)

		local initialized = handler({ operation = "InitializeBase", variant = "Measurement" }) :: any
		assertions.isTrue(initialized.ok)
		assertions.equal(environment.baseInitializeCalls, 1)
		assertions.equal(
			environment.initializedDifficultyDefinition,
			environment.installedStudioDifficultyCatalog.byId["difficulty:phase10-studio-measurement"]
		)
		assertions.equal(initialized.value.maximumHealth, 1_000_000)
		assertions.isFalse((handler({ operation = "InitializeBase", variant = "Defeat" }) :: any).ok)
		local activated = handler({ operation = "ActivateWave" }) :: any
		assertions.isTrue(activated.ok)
		assertions.equal(environment.studioWaveActivationCalls, 1)
		assertions.equal(activated.value.state, "WaveActive")
		assertions.isFalse((handler({ operation = "ActivateWave" }) :: any).ok)
		assertions.isFalse((handler({ operation = "SpawnFixture", variant = "High" }) :: any).ok)

		local zero = handler({ operation = "SpawnFixture", variant = "Zero" }) :: any
		assertions.isTrue(zero.ok)
		assertions.equal(environment.lastSpawnEnemyId, "enemy:phase10-studio-zero")
		assertions.equal(environment.lastSpawnLaneId, "alpha-bent")
		local clearedZero = handler({ operation = "ClearEnemies" }) :: any
		assertions.isTrue(clearedZero.ok)
		assertions.equal(clearedZero.value.count, 1)
		for _, batchCase in
			{
				{ token = "One", count = 1 },
				{ token = "ThirtyTwo", count = 32 },
				{ token = "SixtyFour", count = 64 },
				{ token = "OneTwentyEight", count = 128 },
			}
		do
			local batchResult = handler({ operation = "SpawnBatch", batch = batchCase.token }) :: any
			assertions.isTrue(batchResult.ok)
			assertions.equal(batchResult.value.count, batchCase.count)
			assertions.equal(environment.lastSpawnEnemyId, "enemy:phase10-studio-measurement")
			local clearedBatch = handler({ operation = "ClearEnemies" }) :: any
			assertions.isTrue(clearedBatch.ok)
			assertions.equal(clearedBatch.value.count, batchCase.count)
		end
		assertions.isFalse((handler({ operation = "SpawnBatch", batch = "129" }) :: any).ok)
		local low = handler({ operation = "SpawnFixture", variant = "Low" }) :: any
		assertions.isTrue(low.ok)
		assertions.equal(environment.lastSpawnEnemyId, "enemy:phase10-studio-low")
		assertions.isFalse((handler({ operation = "SpawnFixture", variant = "Low", damage = 1 }) :: any).ok)
		environment.stepCallbacks[1](0.01)
		local diagnostics = handler({ operation = "Diagnostics" }) :: any
		assertions.isTrue(diagnostics.ok)
		assertions.isTrue(table.isfrozen(diagnostics.value))
		assertions.isTrue(table.isfrozen(diagnostics.value.match))
		assertions.equal(diagnostics.value.match.state, "WaveActive")
		assertions.equal(diagnostics.value.baseSnapshot.maximumHealth, 1_000_000)
		assertions.equal(diagnostics.value.activeEnemyCount, 1)
		assertions.equal(diagnostics.value.enemy.studioSpawnCount, 227)
		assertions.equal(diagnostics.value.enemy.studioBatchCount, 4)
		assertions.equal(diagnostics.value.enemy.passTiming.sampleCount, 1)
		assertions.isFalse((handler({ operation = "ResetTiming", extra = true }) :: any).ok)
		local resetTiming = handler({ operation = "ResetTiming" }) :: any
		assertions.isTrue(resetTiming.ok)
		assertions.isTrue(table.isfrozen(resetTiming))
		assertions.isTrue(table.isfrozen(resetTiming.value))
		assertions.isTrue(resetTiming.value.reset)
		local afterReset = (handler({ operation = "Diagnostics" }) :: any).value.enemy
		assertions.equal(afterReset.passTiming.sampleCount, 0)
		assertions.equal(afterReset.passTiming.totalSampleCount, 0)
		assertions.equal(afterReset.passTiming.lastSeconds, 0)
		assertions.equal(afterReset.passTiming.maximumSeconds, 0)
		assertions.equal(afterReset.stepConnectionCount, 1)
		assertions.equal(afterReset.playerRemovingConnectionCount, 1)
		assertions.equal(afterReset.studioTriggerCount, 1)
		environment.stepCallbacks[1](0.01)
		assertions.equal((handler({ operation = "Diagnostics" }) :: any).value.enemy.passTiming.sampleCount, 1)
		local cleared = handler({ operation = "ClearEnemies" }) :: any
		assertions.isTrue(cleared.ok)
		assertions.equal(cleared.value.count, 1)
		assertions.equal((handler({ operation = "Diagnostics" }) :: any).value.activeEnemyCount, 0)
		assertions.equal((handler({ operation = "Diagnostics" }) :: any).value.enemy.passTiming.sampleCount, 1)

		invoke(definition.shutdown)
		assertions.equal(environment.triggerDestroyCalls, 1)
		assertions.equal(service:getMetrics().studioTriggerCount, 0)
		assertions.isFalse(service:getMetrics().studioCatalogInstalled)
		assertions.isFalse(service:getMetrics().studioBaseInitialized)
		assertions.equal(service:getMetrics().studioBaseVariant, nil)
		assertions.equal(service:getMetrics().studioSpawnCount, 0)
		assertions.equal(service:getMetrics().studioBatchCount, 0)
		assertions.isFalse((handler({ operation = "Diagnostics" }) :: any).ok)
		invoke(definition.shutdown)
		assertions.equal(environment.triggerDestroyCalls, 1)

		for _, installCase in
			{
				{
					enemyInstallCalls = 0,
					configure = function(falseEnvironment: any)
						falseEnvironment.baseStudioCatalogInstallMode = "false"
					end,
				},
				{
					enemyInstallCalls = 1,
					configure = function(falseEnvironment: any)
						falseEnvironment.studioCatalogInstallMode = "false"
					end,
				},
			}
		do
			local falseEnvironment = makeEnvironment()
			installCase.configure(falseEnvironment)
			falseEnvironment.dependencies.isStudio = function(): unknown
				return true
			end
			falseEnvironment.dependencies.createRuntimeTrigger = function(_handler: (unknown) -> unknown): unknown
				return { Destroy = function(_self: unknown) end }
			end
			local falseService, falseDefinition = startService(falseEnvironment)
			local falseInstall = (falseService :: any):installStudioFixtures()
			assertions.isFalse(falseInstall.ok)
			assertions.equal(falseInstall.error.code, "INTERNAL_ERROR")
			assertions.equal(falseEnvironment.baseStudioCatalogInstallCalls, 1)
			assertions.equal(falseEnvironment.studioCatalogInstallCalls, installCase.enemyInstallCalls)
			assertions.equal(falseService:getLifecycleState(), "Failed")
			invoke(falseDefinition.shutdown)
		end

		local manifest = success(assertions, AssetSchema.validateManifest({}))
		local emptyCatalog = success(assertions, EnemySchema.validateCatalog({}, manifest))
		local migrationEnvironment = makeEnvironment()
		migrationEnvironment.waveFixture = WaveFixtures.createAuthenticatedFixture()
		migrationEnvironment.catalog = emptyCatalog
		migrationEnvironment.dependencies.catalog = emptyCatalog
		migrationEnvironment.waveFrames = {}
		migrationEnvironment.waveFlushCalls = 0
		migrationEnvironment.waveCloseCalls = 0
		migrationEnvironment.dependencies.isStudio = function(): unknown
			return true
		end
		local migrationHandler: ((unknown) -> unknown)? = nil
		migrationEnvironment.triggerDestroyCalls = 0
		migrationEnvironment.dependencies.createRuntimeTrigger = function(callback: (unknown) -> unknown): unknown
			migrationHandler = callback
			return {
				Destroy = function(_self: unknown)
					migrationEnvironment.triggerDestroyCalls += 1
				end,
			}
		end
		local migrationService, migrationDefinition = startService(migrationEnvironment)
		local migrationBoundary = makeWaveBoundary(migrationEnvironment)
		local migrationHandle = success(assertions, migrationService:installWaveBoundary(migrationBoundary))
		assertions.equal(migrationService:getMetrics().studioTriggerCount, 1)
		assertions.isFalse(
			migrationService:prepareWaveBinding(
				table.freeze({}),
				migrationEnvironment.waveFixture.configuration,
				migrationEnvironment.waveFixture.primary.difficultyDefinition
			).ok
		)
		assertions.equal(migrationEnvironment.studioCatalogInstallCalls, 0)
		assertions.equal(migrationService:getMetrics().studioTriggerCount, 1)
		local migrationToken = success(
			assertions,
			migrationService:prepareWaveBinding(
				migrationHandle,
				migrationEnvironment.waveFixture.configuration,
				migrationEnvironment.waveFixture.primary.difficultyDefinition
			)
		)
		assertions.equal(migrationService:getMetrics().studioTriggerCount, 1)
		assertions.isFalse(migrationService:commitWaveBinding(table.freeze({})).ok)
		assertions.equal(migrationEnvironment.triggerDestroyCalls, 0)
		assertions.equal(migrationService:getMetrics().studioTriggerCount, 1)
		assertions.isTrue(success(assertions, migrationService:commitWaveBinding(migrationToken)).status == "Active")
		assertions.equal(migrationEnvironment.studioCatalogInstallCalls, 1)
		assertions.equal(
			migrationEnvironment.installedStudioCatalog,
			migrationEnvironment.waveFixture.configuration.enemies
		)
		assertions.equal(migrationEnvironment.triggerDestroyCalls, 1)
		assertions.equal(migrationService:getMetrics().studioTriggerCount, 0)
		assertions.isFalse(((migrationHandler :: (unknown) -> unknown)({ operation = "Diagnostics" }) :: any).ok)
		invoke(migrationDefinition.shutdown)

		local productionEnvironment = makeEnvironment()
		productionEnvironment.waveFixture = WaveFixtures.createAuthenticatedFixture()
		productionEnvironment.catalog = emptyCatalog
		productionEnvironment.dependencies.catalog = emptyCatalog
		productionEnvironment.waveFrames = {}
		productionEnvironment.waveFlushCalls = 0
		productionEnvironment.waveCloseCalls = 0
		local productionService = createService(productionEnvironment)
		local productionDefinition = productionService:getServiceDefinition()
		invoke(productionDefinition.initialize)
		local productionHandle =
			success(assertions, productionService:installWaveBoundary(makeWaveBoundary(productionEnvironment)))
		invoke(productionDefinition.start)
		assertions.isFalse(
			productionService:prepareWaveBinding(
				productionHandle,
				productionEnvironment.waveFixture.configuration,
				productionEnvironment.waveFixture.primary.difficultyDefinition
			).ok
		)
		assertions.equal(productionEnvironment.studioCatalogInstallCalls, 0)
		assertions.equal(productionService:getMetrics().studioTriggerCount, 0)
		invoke(productionDefinition.shutdown)
	end),

	TestHarness.case("restricts fixed defeat fixtures to the authenticated defeat variant", function(assertions)
		local environment = makeEnvironment()
		environment.matchState = "PreWave"
		local triggerHandler: ((unknown) -> unknown)? = nil
		environment.dependencies.isStudio = function(): unknown
			return true
		end
		environment.dependencies.createRuntimeTrigger = function(handler: (unknown) -> unknown): unknown
			triggerHandler = handler
			return { Destroy = function(_self: unknown) end }
		end
		local _service, definition = startService(environment)
		local handler = triggerHandler :: (unknown) -> unknown
		assertions.isTrue((handler({ operation = "InstallFixtures" }) :: any).ok)
		assertions.isTrue((handler({ operation = "InitializeBase", variant = "Defeat" }) :: any).ok)
		assertions.equal(
			environment.initializedDifficultyDefinition,
			environment.installedStudioDifficultyCatalog.byId["difficulty:phase10-studio-defeat"]
		)
		assertions.isTrue((handler({ operation = "ActivateWave" }) :: any).ok)
		assertions.isFalse((handler({ operation = "SpawnFixture", variant = "Measurement" }) :: any).ok)
		assertions.isFalse((handler({ operation = "SpawnFixture", variant = "Low" }) :: any).ok)
		assertions.isFalse((handler({ operation = "SpawnBatch", batch = "One" }) :: any).ok)
		for _, variantCase in
			{
				{ variant = "Zero", enemyId = "enemy:phase10-studio-zero" },
				{ variant = "Exact", enemyId = "enemy:phase10-studio-exact" },
				{ variant = "Overkill", enemyId = "enemy:phase10-studio-overkill" },
				{ variant = "High", enemyId = "enemy:phase10-studio-high" },
				{ variant = "Survivor", enemyId = "enemy:phase10-studio-survivor" },
			}
		do
			assertions.isTrue((handler({ operation = "SpawnFixture", variant = variantCase.variant }) :: any).ok)
			assertions.equal(environment.lastSpawnEnemyId, variantCase.enemyId)
		end
		local diagnostics = handler({ operation = "Diagnostics" }) :: any
		assertions.isTrue(diagnostics.ok)
		assertions.equal(diagnostics.value.baseSnapshot.maximumHealth, 100)
		assertions.equal(diagnostics.value.activeEnemyCount, 5)
		assertions.equal((handler({ operation = "ClearEnemies" }) :: any).value.count, 5)
		invoke(definition.shutdown)
	end),

	TestHarness.case("omits the trigger outside Studio and retains bounded pass-time percentiles", function(assertions)
		local environment = makeEnvironment()
		local clockValue = 0
		environment.triggerCreateCalls = 0
		environment.dependencies.isStudio = function(): unknown
			return false
		end
		environment.dependencies.createRuntimeTrigger = function(_handler: (unknown) -> unknown): unknown
			environment.triggerCreateCalls += 1
			return nil
		end
		environment.dependencies.passClock = function(): unknown
			clockValue += 1
			return clockValue
		end
		local service, definition = startService(environment)
		assertions.equal(environment.triggerCreateCalls, 0)
		for _ = 1, 1_025 do
			environment.stepCallbacks[1](0.01)
		end
		local metrics = service:getMetrics()
		assertions.equal(metrics.studioTriggerCount, 0)
		assertions.equal(metrics.passTiming.capacity, 1_024)
		assertions.equal(metrics.passTiming.sampleCount, 1_024)
		assertions.equal(metrics.passTiming.totalSampleCount, 1_025)
		assertions.equal(metrics.passTiming.lastSeconds, 1)
		assertions.equal(metrics.passTiming.maximumSeconds, 1)
		assertions.equal(metrics.passTiming.p50Seconds, 1)
		assertions.equal(metrics.passTiming.p95Seconds, 1)
		assertions.isTrue(table.isfrozen(metrics.passTiming))
		assertions.equal(metrics.stepConnectionCount, 1)
		assertions.equal(metrics.playerRemovingConnectionCount, 1)
		invoke(definition.shutdown)
		assertions.equal(service:getMetrics().passTiming.sampleCount, 0)
	end),

	TestHarness.case(
		"fails closed without adopting or destroying a Studio trigger-name collision",
		function(assertions)
			local environment = makeEnvironment()
			local preexistingDestroyCalls = 0
			local preexisting = {
				Destroy = function(_self: unknown)
					preexistingDestroyCalls += 1
				end,
			}
			environment.dependencies.isStudio = function(): unknown
				return true
			end
			environment.dependencies.createRuntimeTrigger = function(_handler: (unknown) -> unknown): unknown
				environment.preexistingTrigger = preexisting
				return nil
			end
			local service = createService(environment)
			local definition = service:getServiceDefinition()
			invoke(definition.initialize)
			expectStaticFailure(assertions, function()
				invoke(definition.start)
			end, "RUNTIME_TRIGGER_CREATION_FAILED")
			assertions.equal(preexistingDestroyCalls, 0)
			assertions.equal(environment.stepDisconnectCalls, 1)
			assertions.equal(environment.removalDisconnectCalls, 1)
			assertions.equal(environment.publisherCleanupCalls, 1)
			assertions.equal(environment.storeCleanupCalls, 1)
			assertions.equal(service:getMetrics().studioTriggerCount, 0)
		end
	),

	TestHarness.case(
		"owns one authenticated Wave boundary and preserves exact sampled publication order",
		function(assertions)
			local environment, service, definition, handle = createBoundWaveService(assertions)
			table.clear(environment.trace)
			environment.stepSampleServerTime = 100
			environment.spawnDuringWavePass = true
			environment.stepCallbacks[1](0.25)

			assertions.equal(service:getLifecycleState(), "Started")
			assertions.equal(#environment.waveFrames, 1)
			local frame = environment.waveFrames[1]
			assertions.isTrue(table.isfrozen(frame))
			assertions.equal(frame.disposition, "Healthy")
			assertions.equal(frame.matchId, MATCH_ID)
			assertions.equal(frame.enemyEpoch, 1)
			assertions.equal(frame.passOrdinal, 1)
			assertions.equal(frame.sampleServerTime, 100)
			assertions.equal(#frame.terminalOutcomes, 0)
			assertions.equal(type(frame.spawn), "function")
			assertions.isTrue(environment.schedulerSpawnOutcome.committed)
			assertions.isTrue(environment.schedulerSpawnOutcome.replicationCommitted)
			assertions.equal(environment.schedulerSpawnOutcome.snapshot.spawnServerTime, 100)
			assertions.isFalse(environment.store:isAuthenticatedSchedulerSample(environment.activeSchedulerToken))

			assertions.isTrue(indexOf(environment.trace, "store:step") > 0)
			assertions.isTrue(indexOf(environment.trace, "store:step") < indexOf(environment.trace, "base:finish:1"))
			assertions.isTrue(
				indexOf(environment.trace, "base:finish:1")
					< indexOf(environment.trace, "store:drain-terminal-outcomes")
			)
			assertions.isTrue(
				indexOf(environment.trace, "store:drain-terminal-outcomes")
					< indexOf(environment.trace, "wave:pass:Healthy")
			)
			assertions.isTrue(
				indexOf(environment.trace, "publisher:preflight-spawn")
					< indexOf(environment.trace, "store:spawn-scheduled")
			)
			assertions.isTrue(
				indexOf(environment.trace, "store:spawn-scheduled")
					< indexOf(environment.trace, "publisher:commit-spawn")
			)
			assertions.isTrue(
				indexOf(environment.trace, "wave:pass:Healthy")
					< indexOf(environment.trace, "store:finish-scheduler-sample")
			)
			assertions.isTrue(
				indexOf(environment.trace, "store:finish-scheduler-sample")
					< indexOf(environment.trace, "publisher:advance")
			)
			assertions.isTrue(
				indexOf(environment.trace, "publisher:advance") < indexOf(environment.trace, "wave:flush:1")
			)

			local retainedResult = environment.schedulerCapability(waveSpawnEvent(environment, 100))
			assertions.isFalse(retainedResult.committed)
			local traceBeforeLegacyAttempts = #environment.trace
			assertions.isFalse(service:spawn("enemy:late", "main").ok)
			assertions.isFalse(service:resolveEndpoint(1).ok)
			assertions.equal(#environment.trace, traceBeforeLegacyAttempts)
			local metrics = service:getMetrics()
			assertions.equal(metrics.stepConnectionCount, 1)
			assertions.equal(metrics.playerRemovingConnectionCount, 1)
			assertions.equal(metrics.studioTriggerCount, 0)
			assertions.equal(metrics.waveBoundaryStatus, "Active")
			assertions.equal(metrics.waveBoundaryPassCount, 1)
			assertions.equal(metrics.waveBoundaryFlushCount, 1)

			assertions.isTrue(success(assertions, service:detachWaveBoundary(handle)))
			assertions.equal(success(assertions, service:getWaveBoundaryStatus(handle)).status, "Detached")
			assertions.isFalse(success(assertions, service:detachWaveBoundary(handle)))
			invoke(definition.shutdown)

			local shutdownEnvironment, shutdownService, shutdownDefinition, shutdownHandle =
				createBoundWaveService(assertions)
			shutdownEnvironment.stepSampleServerTime = 101
			shutdownEnvironment.waveFlushMode = "shutdown"
			table.clear(shutdownEnvironment.trace)
			shutdownEnvironment.stepCallbacks[1](0.25)
			assertions.equal(shutdownEnvironment.waveFlushCalls, 1)
			assertions.equal(shutdownEnvironment.waveCloseCalls, 1)
			assertions.equal(shutdownEnvironment.waveCloseContext.disposition, "Shutdown")
			assertions.equal(shutdownEnvironment.waveCloseContext.passOrdinal, 1)
			assertions.equal(shutdownEnvironment.waveCloseContext.sampleServerTime, 101)
			assertions.isTrue(
				indexOf(shutdownEnvironment.trace, "publisher:advance")
					< indexOf(shutdownEnvironment.trace, "wave:flush:1")
			)
			assertions.isTrue(
				indexOf(shutdownEnvironment.trace, "wave:flush:1") < indexOf(shutdownEnvironment.trace, "wave:close")
			)
			assertions.equal(shutdownService:getMetrics().waveBoundaryStatus, "Detached")
			assertions.isFalse(shutdownService:getWaveBoundaryStatus(shutdownHandle).ok)
			assertions.isFalse(shutdownService:detachWaveBoundary(shutdownHandle).ok)
			invoke(shutdownDefinition.shutdown)
		end
	),

	TestHarness.case(
		"drains only authentic terminal outcomes through the reentrant-safe predicate",
		function(assertions)
			local environment, service, definition, handle = createBoundWaveService(assertions)
			environment.stepSampleServerTime = 200
			local enemyId = environment.waveFixture.primary.schedule.waves[1].groups[1].enemyId
			local outcome = table.freeze({
				matchId = MATCH_ID,
				enemyEpoch = 1,
				runtimeEnemyId = 1,
				enemyId = enemyId,
				reason = "Manual",
				serverTime = 150,
			})
			environment.authenticatedTerminalOutcomes[outcome] = true
			table.insert(environment.terminalOutcomes, outcome)
			environment.authenticateTerminalDuringPass = outcome
			assertions.isTrue(service:isAuthenticatedTerminalOutcome(handle, outcome))
			environment.stepCallbacks[1](0.1)
			assertions.isTrue(environment.terminalAuthenticatedDuringPass)
			assertions.equal(#environment.lastWaveFrame.terminalOutcomes, 1)
			assertions.equal(environment.lastWaveFrame.terminalOutcomes[1], outcome)
			assertions.equal(#environment.terminalOutcomes, 0)
			local forged = table.freeze({
				matchId = MATCH_ID,
				enemyEpoch = 1,
				runtimeEnemyId = 1,
				enemyId = enemyId,
				reason = "Manual",
				serverTime = 150,
			})
			assertions.isFalse(service:isAuthenticatedTerminalOutcome(handle, forged))
			assertions.isTrue(success(assertions, service:detachWaveBoundary(handle)))
			assertions.isFalse(service:isAuthenticatedTerminalOutcome(handle, outcome))
			invoke(definition.shutdown)
		end
	),

	TestHarness.case("flushes one delivered already-closed Wave pass after Enemy publication", function(assertions)
		local environment, service, definition, handle = createBoundWaveService(assertions, true)
		table.clear(environment.trace)
		environment.stepCallbacks[1](0.25)

		assertions.equal(#environment.waveFrames, 1)
		assertions.equal(environment.lastWaveFrame.disposition, "DependencyFault")
		assertions.equal(environment.waveFlushCalls, 1)
		assertions.isTrue(
			indexOf(environment.trace, "wave:pass:DependencyFault") < indexOf(environment.trace, "publisher:advance")
		)
		assertions.isTrue(indexOf(environment.trace, "publisher:advance") < indexOf(environment.trace, "wave:flush:1"))
		local metrics = service:getMetrics()
		assertions.equal(metrics.waveBoundaryStatus, "Faulted")
		assertions.equal(metrics.waveBoundaryPassCount, 1)
		assertions.equal(metrics.waveBoundaryFlushCount, 1)

		environment.stepCallbacks[1](0.25)
		assertions.equal(#environment.waveFrames, 1)
		assertions.equal(environment.waveFlushCalls, 1)
		assertions.equal(service:getMetrics().waveBoundaryPassCount, 1)
		assertions.equal(service:getMetrics().waveBoundaryFlushCount, 1)
		assertions.isTrue(success(assertions, service:detachWaveBoundary(handle)))
		invoke(definition.shutdown)
	end),

	TestHarness.case(
		"uses the exact scheduler sample for defeat and closes Wave before later passes",
		function(assertions)
			local environment, service, definition, handle = createBoundWaveService(assertions)
			environment.activeSnapshots = { snapshot(1), snapshot(2) }
			environment.nextRuntimeEnemyId = 3
			environment.stepSampleServerTime = 300
			configureDefeat(environment)
			table.clear(environment.trace)
			environment.stepCallbacks[1](0.5)
			assertions.equal(service:getLifecycleState(), "Started")
			assertions.equal(environment.lastWaveFrame.disposition, "DefeatCommitted")
			assertions.equal(environment.defeatSchedulerToken.sampleServerTime, 300)
			assertions.equal(#environment.defeatStoreIds, 2)
			assertions.equal(success(assertions, service:getWaveBoundaryStatus(handle)).status, "DefeatClosed")
			assertions.isTrue(
				indexOf(environment.trace, "store:defeat-all")
					< indexOf(environment.trace, "store:drain-terminal-outcomes")
			)
			assertions.isTrue(
				indexOf(environment.trace, "store:finish-scheduler-sample")
					< indexOf(environment.trace, "wave:pass:DefeatCommitted")
			)
			assertions.isTrue(
				indexOf(environment.trace, "publisher:advance") < indexOf(environment.trace, "wave:flush:1")
			)
			local passCount = service:getMetrics().waveBoundaryPassCount
			environment.stepCallbacks[1](0.5)
			assertions.equal(service:getMetrics().waveBoundaryPassCount, passCount)
			assertions.equal(service:getMetrics().defeatCount, 1)
			assertions.isTrue(success(assertions, service:detachWaveBoundary(handle)))
			invoke(definition.shutdown)
		end
	),

	TestHarness.case(
		"accepts authenticated finite-complete no-op passes without reopening scheduler admission",
		function(assertions)
			local environment, service, definition, handle = createBoundWaveService(assertions)
			environment.wavePassTerminalNoop = true
			environment.stepSampleServerTime = 350
			environment.stepCallbacks[1](0.1)
			assertions.equal(service:getLifecycleState(), "Started")
			assertions.equal(success(assertions, service:getWaveBoundaryStatus(handle)).status, "FiniteComplete")
			assertions.equal(environment.waveCloseCalls, 0)
			assertions.equal(environment.lastWaveFrame.disposition, "Healthy")
			assertions.equal(type(environment.lastWaveFrame.spawn), "function")
			assertions.isTrue(
				indexOf(environment.trace, "store:finish-scheduler-sample")
					< indexOf(environment.trace, "publisher:advance")
			)
			assertions.isTrue(
				indexOf(environment.trace, "publisher:advance") < indexOf(environment.trace, "wave:flush:1")
			)

			table.clear(environment.trace)
			environment.stepSampleServerTime = 351
			environment.stepCallbacks[1](0.1)
			assertions.equal(service:getLifecycleState(), "Started")
			assertions.equal(success(assertions, service:getWaveBoundaryStatus(handle)).status, "FiniteComplete")
			assertions.equal(environment.waveCloseCalls, 0)
			assertions.equal(#environment.waveFrames, 2)
			assertions.equal(environment.lastWaveFrame.spawn, nil)
			assertions.isTrue(
				indexOf(environment.trace, "store:finish-scheduler-sample")
					< indexOf(environment.trace, "wave:pass:Healthy")
			)
			assertions.isTrue(
				indexOf(environment.trace, "wave:pass:Healthy") < indexOf(environment.trace, "publisher:advance")
			)
			assertions.isFalse(service:spawn("enemy:late", "main").ok)
			assertions.isTrue(success(assertions, service:detachWaveBoundary(handle)))
			invoke(definition.shutdown)
		end
	),

	TestHarness.case(
		"reconciles committed scheduler spawns and closes once across boundary failures",
		function(assertions)
			for _, failureCase in
				{
					{
						mode = "preflight-false",
						configure = function(environment: any)
							environment.preflightStepMode = "false"
						end,
					},
					{
						mode = "spawn-preflight-false",
						configure = function(environment: any)
							environment.spawnDuringWavePass = true
							environment.preflightSpawnMode = "false"
						end,
					},
					{
						mode = "wave",
						configure = function(environment: any)
							environment.wavePassMode = "throw"
						end,
					},
					{
						mode = "wave-after-spawn",
						configure = function(environment: any)
							environment.spawnDuringWavePass = true
							environment.wavePassMode = "throw-after-spawn"
							environment.readDuringWaveClose = true
						end,
					},
					{
						mode = "yield-after-spawn",
						configure = function(environment: any)
							environment.spawnDuringWavePass = true
							environment.wavePassMode = "yield-after-spawn"
							environment.readDuringWaveClose = true
						end,
					},
					{
						mode = "commit",
						configure = function(environment: any)
							environment.spawnDuringWavePass = true
							environment.commitSpawnMode = "failure"
							environment.readDuringWaveClose = true
						end,
					},
					{
						mode = "advance",
						configure = function(environment: any)
							environment.advanceMode = "failure"
						end,
					},
					{
						mode = "flush",
						configure = function(environment: any)
							environment.waveFlushMode = "failure"
						end,
					},
				}
			do
				local environment, service, definition, handle = createBoundWaveService(assertions)
				environment.stepSampleServerTime = 400
				failureCase.configure(environment)
				assertions.isTrue(pcall(environment.stepCallbacks[1], 0.1))
				assertions.equal(service:getLifecycleState(), "Failed")
				assertions.equal(environment.waveCloseCalls, 1)
				assertions.equal(environment.waveCloseContext.disposition, "DependencyFault")
				assertions.equal(environment.waveCloseContext.passOrdinal, 1)
				assertions.equal(environment.waveCloseContext.sampleServerTime, 400)
				assertions.isTrue(table.isfrozen(environment.waveCloseContext))
				assertions.equal(success(assertions, service:getWaveBoundaryStatus(handle)).status, "Faulted")
				if failureCase.mode == "preflight-false" then
					assertions.isTrue(
						indexOf(environment.trace, "publisher:preflight-step")
							< indexOf(environment.trace, "store:step")
					)
					assertions.isTrue(indexOf(environment.trace, "store:finish-scheduler-sample") > 0)
				else
					assertions.isTrue(indexOf(environment.trace, "store:finish-scheduler-sample") > 0)
				end
				if
					failureCase.mode == "commit"
					or failureCase.mode == "wave-after-spawn"
					or failureCase.mode == "yield-after-spawn"
				then
					assertions.isTrue(environment.schedulerSpawnOutcome.committed)
					assertions.equal(#environment.activeSnapshots, 0)
					assertions.equal(environment.terminalCount, 1)
					assertions.equal(#environment.terminalOutcomes, 1)
					assertions.equal(environment.waveCloseContext.committedSpawn.event, environment.schedulerSpawnEvent)
					assertions.equal(
						environment.waveCloseContext.committedSpawn.outcome,
						environment.schedulerSpawnOutcome
					)
					assertions.equal(
						environment.waveCloseContext.committedSpawn.outcome.snapshot.runtimeEnemyId,
						environment.schedulerSpawnOutcome.snapshot.runtimeEnemyId
					)
					assertions.equal(environment.waveCloseContext.terminalOutcome, environment.faultTerminalOutcome)
					assertions.isTrue(
						environment.authenticatedTerminalOutcomes[environment.waveCloseContext.terminalOutcome]
					)
					assertions.isTrue(
						indexOf(environment.trace, "store:fault-despawn:1")
							< indexOf(environment.trace, "store:finish-scheduler-sample")
					)
					assertions.isTrue(environment.waveCloseListResult.ok)
					assertions.equal(#environment.waveCloseListResult.value, 0)
					assertions.isFalse(environment.waveCloseMutationResult.ok)
					assertions.equal(environment.waveCloseMutationResult.error.code, "UNAVAILABLE")
					if failureCase.mode == "commit" then
						assertions.isFalse(environment.schedulerSpawnOutcome.replicationCommitted)
						assertions.equal(indexOf(environment.trace, "publisher:preflight-despawn:1"), 0)
						assertions.equal(indexOf(environment.trace, "publisher:commit-despawn:1"), 0)
					else
						assertions.isTrue(environment.schedulerSpawnOutcome.replicationCommitted)
						assertions.isTrue(
							indexOf(environment.trace, "publisher:preflight-despawn:1")
								< indexOf(environment.trace, "store:fault-despawn:1")
						)
						assertions.isTrue(
							indexOf(environment.trace, "store:fault-despawn:1")
								< indexOf(environment.trace, "publisher:commit-despawn:1")
						)
					end
				elseif failureCase.mode == "advance" then
					assertions.equal(indexOf(environment.trace, "wave:flush:1"), 0)
				end
				environment.stepCallbacks[1](0.1)
				assertions.equal(environment.waveCloseCalls, 1)
				assertions.isTrue(success(assertions, service:detachWaveBoundary(handle)))
				invoke(definition.shutdown)
			end
		end
	),

	TestHarness.case("does not report or retry an unsuccessful private Wave fault close", function(assertions)
		local environment, service, definition, handle = createBoundWaveService(assertions)
		environment.stepSampleServerTime = 401
		environment.preflightStepMode = "false"
		environment.waveCloseMode = "failure"
		environment.stepCallbacks[1](0.1)
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.equal(environment.waveCloseCalls, 1)
		assertions.equal(environment.waveCloseContext.passOrdinal, 1)
		assertions.equal(environment.waveCloseContext.sampleServerTime, 401)
		assertions.equal(success(assertions, service:getWaveBoundaryStatus(handle)).status, "Active")
		environment.stepCallbacks[1](0.1)
		assertions.equal(environment.waveCloseCalls, 1)
		local shutdownSucceeded, shutdownFailure = pcall(function()
			invoke(definition.shutdown)
		end)
		assertions.isFalse(shutdownSucceeded)
		assertions.contains(shutdownFailure, "[ATD_ENEMY_SIMULATION_SERVICE][code=CLEANUP_FAILED]")
		assertions.equal(environment.waveCloseCalls, 1)
	end),

	TestHarness.case("authenticates one mutation-free Wave binding transaction", function(assertions)
		local environment = makeEnvironment()
		environment.waveFixture = WaveFixtures.createAuthenticatedFixture()
		environment.catalog = environment.waveFixture.configuration.enemies
		environment.dependencies.catalog = environment.catalog
		environment.waveFrames = {}
		environment.waveFlushCalls = 0
		environment.waveCloseCalls = 0
		local service = createService(environment)
		environment.service = service
		local definition = service:getServiceDefinition()
		invoke(definition.initialize)
		local adapter = makeWaveBoundary(environment)
		local handle = success(assertions, service:installWaveBoundary(adapter))
		assertions.isFalse(service:installWaveBoundary(adapter).ok)
		assertions.isFalse(
			service:prepareWaveBinding(
				table.freeze({}),
				environment.waveFixture.configuration,
				environment.waveFixture.primary.difficultyDefinition
			).ok
		)
		local token = success(
			assertions,
			service:prepareWaveBinding(
				handle,
				environment.waveFixture.configuration,
				environment.waveFixture.primary.difficultyDefinition
			)
		)
		assertions.isFalse(service:commitWaveBinding(table.freeze({})).ok)
		assertions.isTrue(success(assertions, service:commitWaveBinding(token)).generation == 1)
		assertions.isFalse(service:commitWaveBinding(token).ok)
		assertions.isTrue(success(assertions, service:detachWaveBoundary(handle)))
		invoke(definition.shutdown)

		local falseBindEnvironment = makeEnvironment()
		falseBindEnvironment.waveFixture = WaveFixtures.createAuthenticatedFixture()
		falseBindEnvironment.catalog = falseBindEnvironment.waveFixture.configuration.enemies
		falseBindEnvironment.dependencies.catalog = falseBindEnvironment.catalog
		falseBindEnvironment.waveFrames = {}
		falseBindEnvironment.waveFlushCalls = 0
		falseBindEnvironment.waveCloseCalls = 0
		falseBindEnvironment.bindDifficultyMode = "false"
		local falseBindService = createService(falseBindEnvironment)
		falseBindEnvironment.service = falseBindService
		local falseBindDefinition = falseBindService:getServiceDefinition()
		invoke(falseBindDefinition.initialize)
		local falseBindHandle =
			success(assertions, falseBindService:installWaveBoundary(makeWaveBoundary(falseBindEnvironment)))
		local falseBindToken = success(
			assertions,
			falseBindService:prepareWaveBinding(
				falseBindHandle,
				falseBindEnvironment.waveFixture.configuration,
				falseBindEnvironment.waveFixture.primary.difficultyDefinition
			)
		)
		assertions.isFalse(falseBindService:commitWaveBinding(falseBindToken).ok)
		assertions.isFalse(falseBindEnvironment.difficultyBound)
		assertions.equal(falseBindService:getLifecycleState(), "Failed")
		assertions.equal(success(assertions, falseBindService:getWaveBoundaryStatus(falseBindHandle)).status, "Faulted")
		invoke(falseBindDefinition.shutdown)

		local manifest = success(assertions, AssetSchema.validateManifest({}))
		local emptyCatalog = success(assertions, EnemySchema.validateCatalog({}, manifest))
		local falseCatalogEnvironment = makeEnvironment()
		falseCatalogEnvironment.waveFixture = WaveFixtures.createAuthenticatedFixture()
		falseCatalogEnvironment.catalog = emptyCatalog
		falseCatalogEnvironment.dependencies.catalog = emptyCatalog
		falseCatalogEnvironment.waveFrames = {}
		falseCatalogEnvironment.waveFlushCalls = 0
		falseCatalogEnvironment.waveCloseCalls = 0
		falseCatalogEnvironment.studioCatalogInstallMode = "false"
		falseCatalogEnvironment.dependencies.isStudio = function(): unknown
			return true
		end
		falseCatalogEnvironment.dependencies.createRuntimeTrigger = function(_handler: (unknown) -> unknown): unknown
			return { Destroy = function(_self: unknown) end }
		end
		local falseCatalogService, falseCatalogDefinition = startService(falseCatalogEnvironment)
		falseCatalogEnvironment.service = falseCatalogService
		local falseCatalogHandle =
			success(assertions, falseCatalogService:installWaveBoundary(makeWaveBoundary(falseCatalogEnvironment)))
		local falseCatalogToken = success(
			assertions,
			falseCatalogService:prepareWaveBinding(
				falseCatalogHandle,
				falseCatalogEnvironment.waveFixture.configuration,
				falseCatalogEnvironment.waveFixture.primary.difficultyDefinition
			)
		)
		assertions.isFalse(falseCatalogService:commitWaveBinding(falseCatalogToken).ok)
		assertions.equal(falseCatalogEnvironment.studioCatalogInstallCalls, 1)
		assertions.isFalse(falseCatalogEnvironment.difficultyBound)
		assertions.equal(falseCatalogService:getLifecycleState(), "Failed")
		assertions.equal(
			success(assertions, falseCatalogService:getWaveBoundaryStatus(falseCatalogHandle)).status,
			"Faulted"
		)
		invoke(falseCatalogDefinition.shutdown)
	end),

	TestHarness.case("rejects invalid dependencies and lifecycle re-entry", function(assertions)
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
			(newForTests :: EnemySimulationService.TestConstructor)({
				matchLifecycle = environment.matchLifecycle,
				catalog = environment.catalog,
				createStore = environment.createStore,
				createPublisher = environment.createPublisher,
				connectStep = environment.connectStep,
				connectPlayerRemoving = environment.connectPlayerRemoving,
				sender = environment.sender,
				getRecipients = environment.getRecipients,
				extra = true,
			} :: any)
		end, "INVALID_DEPENDENCIES")
	end),
})
