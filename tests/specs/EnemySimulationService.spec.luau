--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local EnemySimulationService = require(script.Parent.Parent.ProductionServerEnemies.EnemySimulationService)

local Shared = game:GetService("ReplicatedStorage").Shared
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
	faulted: boolean?
): any
	local updates = freezeArray(updatedIds or {})
	local endpoints = freezeArray(endpointResolutions or {})
	return table.freeze({
		deltaSeconds = deltaSeconds,
		sampleServerTime = deltaSeconds,
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
		despawnAllForDefeat = function(_self: unknown, runtimeEnemyIds: unknown): unknown
			table.insert(environment.trace, "store:defeat-all")
			environment.defeatStoreIds = runtimeEnemyIds
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
			return Result.ok(makeStepResult(deltaSeconds :: number))
		end,
		getIdentity = function(_self: unknown): unknown
			table.insert(environment.trace, "store:identity")
			return Result.ok(table.freeze({ matchId = MATCH_ID, enemyEpoch = 1 }))
		end,
		getMetrics = function(_self: unknown): unknown
			return table.freeze({ cleaned = environment.storeCleaned == true, faulted = false })
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
			return Result.ok(true)
		end,
		listLaneIds = function(_self: unknown): unknown
			return Result.ok(environment.studioLaneIds)
		end,
		cleanup = function(_self: unknown): unknown
			environment.storeCleanupCalls += 1
			environment.storeCleanupDuringStep = environment.storeCleanupDuringStep or environment.inStep
			environment.storeCleaned = true
			table.insert(environment.trace, "cleanup:store")
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
			end
			return publisherOk("publisher:preflight-spawn")
		end,
		preflightStateChange = function(_self: unknown, runtimeEnemyId: unknown): unknown
			return publisherOk("publisher:preflight-state", runtimeEnemyId)
		end,
		preflightEndpoint = function(_self: unknown, runtimeEnemyId: unknown): unknown
			return publisherOk("publisher:preflight-endpoint", runtimeEnemyId)
		end,
		preflightManualDespawn = function(_self: unknown, runtimeEnemyId: unknown): unknown
			return publisherOk("publisher:preflight-despawn", runtimeEnemyId)
		end,
		preflightDefeat = function(_self: unknown, runtimeEnemyIds: unknown): unknown
			environment.defeatPreflightIds = runtimeEnemyIds
			table.insert(environment.trace, "publisher:preflight-defeat")
			if environment.defeatPreflightMode == "failure" then
				return Result.err(table.freeze({ code = "CAPACITY_EXCEEDED" }))
			end
			return Result.ok(true)
		end,
		preflightStep = function(_self: unknown, runtimeEnemyIds: unknown): unknown
			table.insert(environment.trace, "publisher:preflight-step")
			environment.preflightIds = runtimeEnemyIds
			if environment.preflightStepMode == "failure" then
				return Result.err(table.freeze({ code = "ILLEGAL_LIFECYCLE", operation = "preflightStep" }))
			end
			return Result.ok(true)
		end,
		commitSpawn = function(_self: unknown, value: unknown): unknown
			environment.committedSpawn = value
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
			end
			return publisherOk("publisher:commit-endpoint", (endpoint :: any).runtimeEnemyId)
		end,
		commitManualDespawn = function(_self: unknown, value: unknown): unknown
			environment.committedDespawn = value
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
			return publisherOk("publisher:correction", runtimeEnemyId)
		end,
		advance = function(_self: unknown, deltaSeconds: unknown, provider: unknown): unknown
			environment.advanceCalls += 1
			table.insert(environment.trace, "publisher:advance")
			environment.lastAdvanceDelta = deltaSeconds
			environment.lastProvider = provider
			if environment.advanceHook ~= nil then
				return environment.advanceHook(provider)
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
			environment.publisherCleaned = true
			table.insert(environment.trace, "cleanup:publisher")
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
	end),

	TestHarness.case(
		"preflight rejection prevents store mutation and enters a cleanup-safe failure",
		function(assertions)
			local environment = makeEnvironment()
			environment.activeSnapshots = { snapshot(1), snapshot(2) }
			environment.preflightStepMode = "failure"
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
		local environment = makeEnvironment()
		configureDefeat(environment)
		environment.commitEndpointMode = "failure"
		local service, definition = startService(environment)
		success(assertions, service:spawn("enemy:lethal", "lane:main"))

		local resolved = service:resolveEndpoint(1)
		assertions.isFalse(resolved.ok)
		assertions.equal(resolved.error.code, "INVALID_SNAPSHOT")
		assertions.equal(environment.baseRecordLeakCalls, 1)
		assertions.equal(environment.baseFinishCalls, 0)
		assertions.equal(environment.baseFaultCalls, 1)
		assertions.equal(environment.lifecycleBeginCalls, 0)
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.isTrue(service:getMetrics().spawnAdmissionClosed)
		assertions.isTrue(
			indexOf(environment.trace, "store:endpoint:1") < indexOf(environment.trace, "publisher:commit-endpoint:1")
		)
		assertions.isTrue(
			indexOf(environment.trace, "publisher:commit-endpoint:1") < indexOf(environment.trace, "base:fault")
		)
		assertions.isFalse(service:spawn("enemy:late", "lane:main").ok)
		invoke(definition.shutdown)
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
