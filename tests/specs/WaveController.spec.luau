--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local ClientRequestTracker = require(script.Parent.Parent.ProductionClientNetworking.ClientRequestTracker)
local WaveController = require(script.Parent.Parent.ProductionClientWaves.WaveController)
local WaveStateReducer = require(script.Parent.Parent.ProductionClientWaves.WaveStateReducer)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local WaveProtocol = require(ReplicatedStorage.Shared.match.WaveProtocol)
local ProductionRemotes = require(ReplicatedStorage.Shared.network.ProductionRemotes)

type Assertions = TestHarness.Assertions

type Signal = {
	connect: (self: Signal, listener: (unknown, ...unknown) -> ()) -> RBXScriptConnection,
	fire: (self: Signal, value: unknown, ...unknown) -> (),
	force: (self: Signal, value: unknown, ...unknown) -> (),
}

type Options = {
	respondDuringInitialFire: boolean?,
	getFireThrows: boolean?,
	skipFireThrows: boolean?,
}

type Rig = {
	controller: WaveController.Controller,
	definition: any,
	tracker: ClientRequestTracker.Tracker,
	reducer: WaveStateReducer.Reducer,
	order: { string },
	getFires: { any },
	skipFires: { any },
	eventSignal: Signal,
	getResponseSignal: Signal,
	skipResponseSignal: Signal,
	disconnectCount: number,
	reducerCleanupCount: number,
}

local MATCH_A = "match:phase11-wave-controller-a"
local MATCH_B = "match:phase11-wave-controller-b"
local logger = Log.new(EnvironmentContext.new("client", "Match", 0, false))
local newTrackerForTests = ClientRequestTracker.newForTests
local newControllerForTests = WaveController.newForTests
local invokeStudioDiagnosticsForTests = WaveController.invokeStudioDiagnosticsForTests

if newTrackerForTests == nil or newControllerForTests == nil or invokeStudioDiagnosticsForTests == nil then
	error("[ATD_TEST_FIXTURE][code=WAVE_CONTROLLER_TEST_SEAM_MISSING]", 0)
end

local function keyCount(value: { [any]: unknown }): number
	local count = 0
	for _ in next, value do
		count += 1
	end
	return count
end

local function counts(total: number, spawned: number): any
	return {
		totalScheduled = total,
		pending = total - spawned,
		spawned = spawned,
		alive = spawned,
		leaked = 0,
		otherwiseResolved = 0,
	}
end

local function snapshot(matchId: string, revision: number, available: boolean?): WaveProtocol.WaveSnapshot
	local spawned = math.min(revision - 1, 3)
	local raw = {
		matchId = matchId,
		enemyEpoch = 1,
		mapId = "map:phase11-wave-controller",
		difficultyId = "difficulty:phase11-wave-controller",
		state = "Running",
		waveRevision = revision,
		currentWaveNumber = 1,
		totalWaves = 3,
		currentWaveId = "wave:phase11-wave-controller-1",
		bossKind = "None",
		timerPhase = "WaveDeadline",
		waveStartedServerTime = 100,
		deadlineServerTime = 110,
		intermissionEndsServerTime = 0,
		skipAvailableServerTime = 102,
		finiteCompleteServerTime = 0,
		currentCounts = counts(3, spawned),
		aggregateCounts = counts(3, spawned),
		skipState = {
			available = available == true,
			activeParticipantCount = 2,
			yesVoteCount = 0,
			requiredVoteCount = 2,
			quorumPending = false,
		},
	}
	local validated = WaveProtocol.validateWaveSnapshot(raw)
	if not validated.ok then
		error(`[ATD_TEST_FIXTURE][code=WAVE_CONTROLLER_SNAPSHOT_INVALID][path={validated.error.path}]`, 0)
	end
	return validated.value
end

local function successWire(request: any, payload: unknown): { [string]: unknown }
	return {
		requestId = request.requestId,
		state = "Success",
		payload = payload,
	}
end

local function rejectedWire(request: any, code: string): { [string]: unknown }
	return {
		requestId = request.requestId,
		state = "Rejected",
		error = { code = code },
	}
end

local function makeSignal(rig: Rig, orderName: string): Signal
	local listener: ((unknown, ...unknown) -> ())? = nil
	local active = false
	local signal = {} :: Signal
	function signal:connect(nextListener)
		table.insert(rig.order, orderName)
		listener = nextListener
		active = true
		return RobloxAdapter.createConnection(function()
			if active then
				active = false
				rig.disconnectCount += 1
			end
		end) :: RBXScriptConnection
	end
	function signal:fire(value, ...)
		if active and listener ~= nil then
			(listener :: (unknown, ...unknown) -> ())(value, ...)
		end
	end
	function signal:force(value, ...)
		if listener ~= nil then
			(listener :: (unknown, ...unknown) -> ())(value, ...)
		end
	end
	return signal
end

local function makeRig(options: Options?): Rig
	local requestCounter = 0
	local trackerResult = (newTrackerForTests :: ClientRequestTracker.TestConstructor)(
		ProductionRemotes,
		"Match",
		function(): string
			requestCounter += 1
			return `wavectrl{string.format("%04d", requestCounter)}`
		end
	)
	if not trackerResult.ok then
		error("[ATD_TEST_FIXTURE][code=WAVE_CONTROLLER_TRACKER_FAILED]", 0)
	end
	local reducerResult = WaveStateReducer.new()
	if not reducerResult.ok then
		error("[ATD_TEST_FIXTURE][code=WAVE_CONTROLLER_REDUCER_FAILED]", 0)
	end
	local rig = {
		controller = nil :: any,
		definition = nil,
		tracker = trackerResult.value,
		reducer = reducerResult.value,
		order = {},
		getFires = {},
		skipFires = {},
		eventSignal = nil :: any,
		getResponseSignal = nil :: any,
		skipResponseSignal = nil :: any,
		disconnectCount = 0,
		reducerCleanupCount = 0,
	} :: Rig
	rig.eventSignal = makeSignal(rig, "wave-event")
	rig.getResponseSignal = makeSignal(rig, "get-response")
	rig.skipResponseSignal = makeSignal(rig, "skip-response")
	local reducerAdapter = {
		observeEvent = function(_self, value)
			return rig.reducer:observeEvent(value)
		end,
		observeGetResponse = function(_self, value, allowReplacement)
			return rig.reducer:observeGetResponse(value, allowReplacement)
		end,
		observeSubmitResponse = function(_self, value)
			return rig.reducer:observeSubmitResponse(value)
		end,
		getState = function(_self)
			return rig.reducer:getState()
		end,
		reset = function(_self)
			return rig.reducer:reset()
		end,
		cleanup = function(_self)
			rig.reducerCleanupCount += 1
			return rig.reducer:cleanup()
		end,
	}
	local getDefinition = ProductionRemotes:get(WaveProtocol.GET_WAVE_SNAPSHOT_ENDPOINT)
	local skipDefinition = ProductionRemotes:get(WaveProtocol.SUBMIT_SKIP_VOTE_ENDPOINT)
	local eventDefinition = ProductionRemotes:get(WaveProtocol.WAVE_REPLICATION_ENDPOINT)
	if getDefinition == nil or skipDefinition == nil or eventDefinition == nil then
		error("[ATD_TEST_FIXTURE][code=WAVE_CONTROLLER_DEFINITION_MISSING]", 0)
	end
	local selectedOptions = options or {}
	local dependencies: WaveController.Dependencies = {
		tracker = rig.tracker :: any,
		getSnapshot = {
			definition = getDefinition,
			connectResponse = function(listener)
				return rig.getResponseSignal:connect(listener)
			end,
			fire = function(envelope)
				table.insert(rig.order, "fire-get")
				table.insert(rig.getFires, envelope)
				if selectedOptions.respondDuringInitialFire and #rig.getFires == 1 then
					rig.eventSignal:fire({ payload = snapshot(MATCH_A, 2) })
					rig.getResponseSignal:fire(successWire(envelope, snapshot(MATCH_A, 1)))
				end
				if selectedOptions.getFireThrows then
					error("PRIVATE_WAVE_CONTROLLER_GET_FIRE_FAILURE", 0)
				end
			end,
		},
		submitSkipVote = {
			definition = skipDefinition,
			connectResponse = function(listener)
				return rig.skipResponseSignal:connect(listener)
			end,
			fire = function(envelope)
				table.insert(rig.order, "fire-skip")
				table.insert(rig.skipFires, envelope)
				if selectedOptions.skipFireThrows then
					error("PRIVATE_WAVE_CONTROLLER_SKIP_FIRE_FAILURE", 0)
				end
			end,
		},
		replicationEvent = {
			definition = eventDefinition,
			connectEvent = function(listener)
				return rig.eventSignal:connect(listener)
			end,
		},
		reducer = reducerAdapter :: any,
	}
	local controllerResult = (newControllerForTests :: WaveController.TestConstructor)(logger, dependencies)
	if not controllerResult.ok then
		error("[ATD_TEST_FIXTURE][code=WAVE_CONTROLLER_CREATION_FAILED]", 0)
	end
	rig.controller = controllerResult.value
	rig.definition = rig.controller:getServiceDefinition()
	rig.definition.initialize()
	rig.definition.start()
	return rig
end

local function sendEvent(rig: Rig, value: WaveProtocol.WaveSnapshot)
	rig.eventSignal:fire({ payload = value })
end

local function sendGetResponse(rig: Rig, requestIndex: number, value: WaveProtocol.WaveSnapshot)
	rig.getResponseSignal:fire(successWire(rig.getFires[requestIndex], value))
end

local function current(rig: Rig): WaveProtocol.WaveSnapshot?
	local resultValue = rig.reducer:getState()
	return if resultValue.ok then resultValue.value.snapshot else nil
end

local function expectSuccess(assertions: Assertions, resultValue: any): any
	assertions.isTrue(resultValue.ok)
	if not resultValue.ok then
		error("[ATD_TEST][code=WAVE_CONTROLLER_EXPECTED_SUCCESS]", 0)
	end
	return resultValue.value
end

local function expectError(assertions: Assertions, resultValue: any, code: string)
	assertions.isFalse(resultValue.ok)
	if resultValue.ok then
		error("[ATD_TEST][code=WAVE_CONTROLLER_EXPECTED_ERROR]", 0)
	end
	assertions.equal(resultValue.error.code, code)
end

return TestHarness.suite("WaveController", {
	TestHarness.case("connects exactly three listeners before the initial empty Get race", function(assertions)
		local rig = makeRig({ respondDuringInitialFire = true })
		assertions.isTrue(table.isfrozen(WaveController))
		assertions.equal(rig.controller:getState(), "Started")
		assertions.equal(rig.definition.dependencies[1], "EnemyController")
		assertions.equal(table.concat(rig.order, ","), "wave-event,get-response,skip-response,fire-get")
		assertions.equal(#rig.getFires, 1)
		assertions.equal(keyCount(rig.getFires[1]), 2)
		assertions.equal(keyCount(rig.getFires[1].payload), 0)
		assertions.equal((current(rig) :: WaveProtocol.WaveSnapshot).waveRevision, 2)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		assertions.equal(rig.controller:getMetrics().connectionCount, 3)
		rig.definition.shutdown()
	end),

	TestHarness.case("coalesces repeated revision gaps into one bounded recovery Get", function(assertions)
		local rig = makeRig()
		sendGetResponse(rig, 1, snapshot(MATCH_A, 1))
		sendEvent(rig, snapshot(MATCH_A, 3))
		assertions.equal(#rig.getFires, 2)
		sendEvent(rig, snapshot(MATCH_A, 4))
		assertions.equal(#rig.getFires, 2)
		assertions.isTrue(rig.controller:getMetrics().recoveryUsed)
		assertions.isTrue(rig.controller:getMetrics().getRequestPending)

		sendGetResponse(rig, 2, snapshot(MATCH_A, 4))
		assertions.equal((current(rig) :: WaveProtocol.WaveSnapshot).waveRevision, 4)
		assertions.isFalse(rig.controller:getMetrics().recoveryRequired)
		sendEvent(rig, snapshot(MATCH_A, 6))
		assertions.equal(#rig.getFires, 2)
		assertions.equal(rig.controller:getMetrics().recoveryRequestCount, 1)
		rig.definition.shutdown()
	end),

	TestHarness.case(
		"replaces Match only from the current Get generation and cancels old skip state",
		function(assertions)
			local rig = makeRig()
			sendGetResponse(rig, 1, snapshot(MATCH_A, 1, true))
			expectSuccess(assertions, rig.controller:submitSkipVote())
			assertions.equal(#rig.skipFires, 1)
			sendEvent(rig, snapshot(MATCH_B, 1))
			assertions.equal(#rig.getFires, 2)
			sendGetResponse(rig, 2, snapshot(MATCH_B, 2))
			assertions.equal((current(rig) :: WaveProtocol.WaveSnapshot).matchId, MATCH_B)
			local metrics = rig.controller:getMetrics()
			assertions.equal(metrics.matchGeneration, 2)
			assertions.equal(metrics.matchReplacementCount, 1)
			assertions.isFalse(metrics.skipRequestPending)
			assertions.equal(rig.tracker:getStats().pendingCount, 0)

			rig.skipResponseSignal:force(successWire(rig.skipFires[1], snapshot(MATCH_A, 2)))
			assertions.equal((current(rig) :: WaveProtocol.WaveSnapshot).matchId, MATCH_B)
			sendEvent(rig, snapshot(MATCH_B, 4))
			assertions.equal(#rig.getFires, 3)
			assertions.equal(rig.controller:getMetrics().recoveryRequestCount, 2)
			rig.definition.shutdown()
		end
	),

	TestHarness.case("derives the exact bounded skip payload only from cached Wave state", function(assertions)
		local rig = makeRig()
		sendGetResponse(rig, 1, snapshot(MATCH_A, 1, true))
		expectError(assertions, rig.controller:submitSkipVote("forged"), "INVALID_ARGUMENT")
		expectSuccess(assertions, rig.controller:submitSkipVote())
		assertions.equal(#rig.skipFires, 1)
		assertions.equal(keyCount(rig.skipFires[1].payload), 2)
		assertions.equal(rig.skipFires[1].payload.matchId, MATCH_A)
		assertions.equal(rig.skipFires[1].payload.waveNumber, 1)
		expectError(assertions, rig.controller:submitSkipVote(), "REQUEST_PENDING")

		rig.skipResponseSignal:fire(successWire(rig.skipFires[1], snapshot(MATCH_A, 2)))
		assertions.equal((current(rig) :: WaveProtocol.WaveSnapshot).waveRevision, 2)
		assertions.isFalse(rig.controller:getMetrics().skipRequestPending)
		rig.definition.shutdown()

		local unavailable = makeRig()
		sendGetResponse(unavailable, 1, snapshot(MATCH_A, 1, false))
		expectError(assertions, unavailable.controller:submitSkipVote(), "UNAVAILABLE")
		assertions.equal(#unavailable.skipFires, 0)
		unavailable.definition.shutdown()
	end),

	TestHarness.case("allows a correlated skip response to heal a gap without rollback", function(assertions)
		local rig = makeRig()
		sendGetResponse(rig, 1, snapshot(MATCH_A, 1, true))
		expectSuccess(assertions, rig.controller:submitSkipVote())
		sendEvent(rig, snapshot(MATCH_A, 3))
		assertions.equal(#rig.getFires, 2)
		rig.skipResponseSignal:fire(successWire(rig.skipFires[1], snapshot(MATCH_A, 3)))
		assertions.equal((current(rig) :: WaveProtocol.WaveSnapshot).waveRevision, 3)
		assertions.isFalse(rig.controller:getMetrics().recoveryRequired)
		sendGetResponse(rig, 2, snapshot(MATCH_A, 2))
		assertions.equal((current(rig) :: WaveProtocol.WaveSnapshot).waveRevision, 3)
		rig.definition.shutdown()
	end),

	TestHarness.case("bounds rejected initial recovery and sender failures", function(assertions)
		local rig = makeRig()
		rig.getResponseSignal:fire(rejectedWire(rig.getFires[1], "UNAVAILABLE"))
		assertions.equal(#rig.getFires, 2)
		rig.getResponseSignal:fire(rejectedWire(rig.getFires[2], "INTERNAL_ERROR"))
		assertions.equal(#rig.getFires, 2)
		assertions.equal(rig.controller:getMetrics().recoveryRequestCount, 1)
		rig.definition.shutdown()

		local throwingGet = makeRig({ getFireThrows = true })
		assertions.equal(#throwingGet.getFires, 2)
		assertions.equal(throwingGet.tracker:getStats().pendingCount, 0)
		throwingGet.definition.shutdown()

		local throwingSkip = makeRig({ skipFireThrows = true })
		sendGetResponse(throwingSkip, 1, snapshot(MATCH_A, 1, true))
		expectError(assertions, throwingSkip.controller:submitSkipVote(), "INTERNAL_ERROR")
		assertions.isFalse(throwingSkip.controller:getMetrics().skipRequestPending)
		throwingSkip.definition.shutdown()
	end),

	TestHarness.case("exposes bounded Studio diagnostics and one delayed-bootstrap recovery", function(assertions)
		local rig = makeRig()
		local invokeDiagnostics = invokeStudioDiagnosticsForTests :: (WaveController.Controller, ...unknown) -> any
		sendGetResponse(rig, 1, snapshot(MATCH_A, 1, true))

		local initial = invokeDiagnostics(rig.controller, { operation = "Diagnostics" })
		assertions.isTrue(initial.ok)
		assertions.isTrue(table.isfrozen(initial))
		assertions.isTrue(table.isfrozen(initial.value))
		assertions.isTrue(initial.value.state.locked)
		assertions.equal(initial.value.state.snapshot.waveRevision, 1)
		assertions.equal(initial.value.controller.connectionCount, 3)
		assertions.equal(initial.value.controller.studioDiagnosticsBridgeCount, 0)

		local invalid = invokeDiagnostics(rig.controller, { operation = "Diagnostics", extra = true })
		assertions.isFalse(invalid.ok)
		assertions.equal(invalid.error.code, "INVALID_REQUEST")

		local suspended = invokeDiagnostics(rig.controller, { operation = "SuspendRecovery" })
		assertions.isTrue(suspended.ok)
		assertions.isFalse(suspended.value.state.locked)
		assertions.isTrue(suspended.value.controller.studioRecoverySuspended)
		assertions.isTrue(suspended.value.controller.studioRecoveryUsed)
		expectError(assertions, rig.controller:submitSkipVote(), "UNAVAILABLE")
		rig.eventSignal:fire({ payload = snapshot(MATCH_A, 3, true) })
		assertions.isNil(current(rig))

		local resumed = invokeDiagnostics(rig.controller, { operation = "ResumeRecovery" })
		assertions.isTrue(resumed.ok)
		assertions.isFalse(resumed.value.controller.studioRecoverySuspended)
		assertions.equal(#rig.getFires, 2)
		sendGetResponse(rig, 2, snapshot(MATCH_A, 4, true))
		assertions.equal((current(rig) :: WaveProtocol.WaveSnapshot).waveRevision, 4)

		local submitted = invokeDiagnostics(rig.controller, { operation = "SubmitSkipVote" })
		assertions.isTrue(submitted.ok)
		assertions.equal(#rig.skipFires, 1)
		assertions.equal(rig.skipFires[1].payload.matchId, MATCH_A)
		assertions.equal(rig.skipFires[1].payload.waveNumber, 1)

		local reused = invokeDiagnostics(rig.controller, { operation = "SuspendRecovery" })
		assertions.isFalse(reused.ok)
		assertions.equal(reused.error.code, "INTERNAL_ERROR")
		rig.definition.shutdown()
		local afterCleanup = invokeDiagnostics(rig.controller, { operation = "Diagnostics" })
		assertions.isFalse(afterCleanup.ok)
		assertions.equal(afterCleanup.error.code, "UNAVAILABLE")
	end),

	TestHarness.case(
		"cleans listeners pending requests reducer and late callback generations once",
		function(assertions)
			local rig = makeRig()
			local getEnvelope = rig.getFires[1]
			local generationBefore = rig.controller:getMetrics().callbackGeneration
			rig.definition.shutdown()
			rig.definition.shutdown()
			local metrics = rig.controller:getMetrics()
			assertions.equal(metrics.lifecycleState, "Shutdown")
			assertions.equal(metrics.connectionCount, 0)
			assertions.equal(metrics.callbackGeneration, generationBefore + 1)
			assertions.equal(rig.disconnectCount, 3)
			assertions.equal(rig.reducerCleanupCount, 1)
			assertions.equal(rig.tracker:getStats().pendingCount, 0)

			rig.eventSignal:force({ payload = snapshot(MATCH_A, 3) })
			rig.getResponseSignal:force(successWire(getEnvelope, snapshot(MATCH_A, 2)))
			assertions.equal(rig.controller:getMetrics().acceptedStateCount, 0)
			assertions.equal(#rig.getFires, 1)
			expectError(assertions, rig.controller:submitSkipVote(), "UNAVAILABLE")
		end
	),

	TestHarness.case("rejects inexact dependencies through the test constructor", function(assertions)
		local rig = makeRig()
		rig.definition.shutdown()
		local getDefinition = ProductionRemotes:get(WaveProtocol.GET_WAVE_SNAPSHOT_ENDPOINT)
		local skipDefinition = ProductionRemotes:get(WaveProtocol.SUBMIT_SKIP_VOTE_ENDPOINT)
		local eventDefinition = ProductionRemotes:get(WaveProtocol.WAVE_REPLICATION_ENDPOINT)
		local invalid = {
			tracker = rig.tracker,
			getSnapshot = {
				definition = getDefinition,
				connectResponse = function(_listener: any)
					return RobloxAdapter.createConnection(function() end)
				end,
				fire = function(_envelope: any) end,
			},
			submitSkipVote = {
				definition = skipDefinition,
				connectResponse = function(_listener: any)
					return RobloxAdapter.createConnection(function() end)
				end,
				fire = function(_envelope: any) end,
			},
			replicationEvent = {
				definition = eventDefinition,
				connectEvent = function(_listener: any)
					return RobloxAdapter.createConnection(function() end)
				end,
			},
			reducer = {},
			extra = true,
		}
		local resultValue = (newControllerForTests :: WaveController.TestConstructor)(logger, invalid :: any)
		expectError(assertions, resultValue, "INVALID_DEPENDENCIES")
	end),
})
