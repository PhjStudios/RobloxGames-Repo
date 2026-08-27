--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local EnemySimulationService = require(script.Parent.Parent.ProductionServerEnemies.EnemySimulationService)

local Shared = game:GetService("ReplicatedStorage").Shared
local EnemySchema = require(Shared.config.EnemySchema)
local Result = require(Shared.util.Result)

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
			return Result.ok(table.freeze({ matchId = MATCH_ID }))
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
			local resolution = endpointResolution(runtimeEnemyId :: number, environment.endpointCallbackSucceeded)
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
			return publisherOk("publisher:commit-endpoint", (endpoint :: any).runtimeEnemyId)
		end,
		commitManualDespawn = function(_self: unknown, value: unknown): unknown
			environment.committedDespawn = value
			return publisherOk("publisher:commit-despawn", (value :: any).runtimeEnemyId)
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

	environment.createStore = function(matchId: unknown, catalog: unknown, runtimeMap: unknown): unknown
		table.insert(environment.trace, "create:store")
		environment.factoryMatchId = matchId
		environment.factoryCatalog = catalog
		environment.factoryRuntimeMap = runtimeMap
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

return TestHarness.suite("server enemy simulation and replication service", {
	TestHarness.case("constructs store then publisher and owns exactly two service connections", function(assertions)
		local environment = makeEnvironment()
		local service = createService(environment)
		local definition = service:getServiceDefinition()
		assertions.isTrue(table.isfrozen(service))
		assertions.isTrue(table.isfrozen(definition))
		assertions.equal(definition.name, "EnemySimulation")
		assertions.equal(#definition.dependencies, 2)
		assertions.equal(definition.dependencies[1], "NetworkRegistry")
		assertions.equal(definition.dependencies[2], "MatchLifecycle")

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
		assertions.isFalse((handler({ operation = "Spawn", variant = "Stress" }) :: any).ok)
		assertions.isFalse((handler({ operation = "InstallCatalog", extra = true }) :: any).ok)

		local installed = handler({ operation = "InstallCatalog" }) :: any
		assertions.isTrue(installed.ok)
		assertions.equal(environment.studioCatalogInstallCalls, 1)
		assertions.isTrue(EnemySchema.isValidatedCatalog(environment.installedStudioCatalog))
		assertions.equal(installed.value.laneId, "alpha-bent")
		assertions.isTrue(table.isfrozen(installed.value.enemyIds))
		assertions.isTrue(service:getMetrics().studioCatalogInstalled)
		assertions.isFalse((handler({ operation = "InstallCatalog" }) :: any).ok)

		local stress = handler({ operation = "Spawn", variant = "Stress" }) :: any
		assertions.isTrue(stress.ok)
		assertions.equal(environment.lastSpawnEnemyId, "enemy:phase09-studio-stress")
		assertions.equal(environment.lastSpawnLaneId, "alpha-bent")
		local slowed =
			handler({ operation = "SetSlow", runtimeEnemyId = stress.value.runtimeEnemyId, multiplier = 0.5 })
		assertions.isTrue((slowed :: any).ok)
		assertions.isFalse((handler({
			operation = "SetSlow",
			runtimeEnemyId = stress.value.runtimeEnemyId,
			multiplier = 0 / 0,
		}) :: any).ok)
		local snapshots = handler({ operation = "Snapshot" }) :: any
		assertions.isTrue(snapshots.ok)
		assertions.equal(#snapshots.value, 1)
		local metrics = handler({ operation = "Metrics" }) :: any
		assertions.isTrue(metrics.ok)
		assertions.equal(metrics.value.studioTriggerCount, 1)

		local endpoint = handler({ operation = "Spawn", variant = "Endpoint" }) :: any
		assertions.isTrue(endpoint.ok)
		assertions.equal(environment.lastSpawnEnemyId, "enemy:phase09-studio-endpoint")
		local despawned = handler({ operation = "Despawn", runtimeEnemyId = endpoint.value.runtimeEnemyId }) :: any
		assertions.isTrue(despawned.ok)
		local another = handler({ operation = "Spawn", variant = "Stress" }) :: any
		assertions.isTrue(another.ok)
		environment.stepCallbacks[1](0.01)
		assertions.equal((handler({ operation = "Metrics" }) :: any).value.passTiming.sampleCount, 1)
		local cleared = handler({ operation = "Clear" }) :: any
		assertions.isTrue(cleared.ok)
		assertions.equal(#cleared.value, 2)
		assertions.equal(#(handler({ operation = "Snapshot" }) :: any).value, 0)
		assertions.equal((handler({ operation = "Metrics" }) :: any).value.passTiming.sampleCount, 0)

		invoke(definition.shutdown)
		assertions.equal(environment.triggerDestroyCalls, 1)
		assertions.equal(service:getMetrics().studioTriggerCount, 0)
		assertions.isFalse((handler({ operation = "Snapshot" }) :: any).ok)
		invoke(definition.shutdown)
		assertions.equal(environment.triggerDestroyCalls, 1)
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
