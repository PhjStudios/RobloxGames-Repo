--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local ClientRequestTracker = require(script.Parent.Parent.ProductionClientNetworking.ClientRequestTracker)
local BaseController = require(script.Parent.Parent.ProductionClientBase.BaseController)
local BaseStateReducer = require(script.Parent.Parent.ProductionClientBase.BaseStateReducer)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local ProductionRemotes = require(ReplicatedStorage.Shared.network.ProductionRemotes)
local Result = require(ReplicatedStorage.Shared.util.Result)

type Signal = {
	connect: (self: Signal, listener: (unknown, ...unknown) -> ()) -> RBXScriptConnection,
	fire: (self: Signal, value: unknown, ...unknown) -> (),
	force: (self: Signal, value: unknown, ...unknown) -> (),
}

type Options = {
	respondDuringFirstFire: boolean?,
	fireAlwaysThrows: boolean?,
}

type Rig = {
	controller: BaseController.Controller,
	definition: any,
	tracker: ClientRequestTracker.Tracker,
	reducer: BaseStateReducer.Reducer,
	order: { string },
	cleanupOrder: { string },
	requestFires: { any },
	eventSignal: Signal,
	responseSignal: Signal,
	renderStates: { any },
	disconnectCount: number,
	viewCleanupCount: number,
	reducerCleanupCount: number,
}

local MATCH_A = "match:base-controller-a"
local MATCH_B = "match:base-controller-b"
local MAP_A = "map:base-controller-a"
local DIFFICULTY_A = "difficulty:base-controller-a"
local logger = Log.new(EnvironmentContext.new("client", "Match", 0, false))
local newTrackerForTests = ClientRequestTracker.newForTests
local newControllerForTests = BaseController.newForTests
local invokeStudioDiagnosticsForTests = BaseController.invokeStudioDiagnosticsForTests
if newTrackerForTests == nil or newControllerForTests == nil or invokeStudioDiagnosticsForTests == nil then
	error("[ATD_TEST_FIXTURE][code=BASE_CONTROLLER_TEST_SEAM_MISSING]", 0)
end

local function keyCount(value: { [any]: unknown }): number
	local count = 0
	for _ in next, value do
		count += 1
	end
	return count
end

local function snapshot(
	revision: number,
	currentHealth: number,
	status: "Active" | "Defeated" | "Faulted"?,
	overrides: { [string]: unknown }?
): BaseProtocol.BaseSnapshot
	local selectedStatus = status or "Active"
	local raw: { [string]: unknown } = {
		matchId = MATCH_A,
		enemyEpoch = 1,
		mapId = MAP_A,
		difficultyId = DIFFICULTY_A,
		basePosition = Vector3.new(10, 4, -8),
		baseRevision = revision,
		status = selectedStatus,
		currentHealth = currentHealth,
		maximumHealth = 100,
		lowHealth = currentHealth <= 25,
		initializedServerTime = 100,
		updatedServerTime = 100 + revision,
	}
	if overrides ~= nil then
		for key, value in overrides do
			raw[key] = value
		end
	end
	local validated = BaseProtocol.validateBaseSnapshot(raw)
	if not validated.ok then
		error(`[ATD_TEST_FIXTURE][code=BASE_CONTROLLER_SNAPSHOT_INVALID][path={validated.error.path}]`, 0)
	end
	return validated.value
end

local function message(
	baseSnapshot: BaseProtocol.BaseSnapshot,
	appliedDamage: number?,
	lowHealthCrossed: boolean?
): BaseProtocol.BaseReplicationMessage
	local raw: unknown
	if appliedDamage == nil then
		raw = { kind = "State", snapshot = baseSnapshot }
	else
		raw = {
			kind = "Damage",
			snapshot = baseSnapshot,
			appliedDamage = appliedDamage,
			leakCount = 1,
			lowHealthCrossed = lowHealthCrossed == true,
		}
	end
	local validated = BaseProtocol.validateBaseReplicationMessage(raw)
	if not validated.ok then
		error(`[ATD_TEST_FIXTURE][code=BASE_CONTROLLER_MESSAGE_INVALID][path={validated.error.path}]`, 0)
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
			return `basectrl{string.format("%04d", requestCounter)}`
		end
	)
	if not trackerResult.ok then
		error("[ATD_TEST_FIXTURE][code=BASE_CONTROLLER_TRACKER_FAILED]", 0)
	end
	local reducerResult = BaseStateReducer.new()
	if not reducerResult.ok then
		error("[ATD_TEST_FIXTURE][code=BASE_CONTROLLER_REDUCER_FAILED]", 0)
	end

	local rig = {
		controller = nil :: any,
		definition = nil,
		tracker = trackerResult.value,
		reducer = reducerResult.value,
		order = {},
		cleanupOrder = {},
		requestFires = {},
		eventSignal = nil :: any,
		responseSignal = nil :: any,
		renderStates = {},
		disconnectCount = 0,
		viewCleanupCount = 0,
		reducerCleanupCount = 0,
	} :: Rig
	rig.eventSignal = makeSignal(rig, "base-event")
	rig.responseSignal = makeSignal(rig, "base-response")

	local reducerAdapter = {
		observeSnapshot = function(_self, value)
			return rig.reducer:observeSnapshot(value)
		end,
		observeMessage = function(_self, value)
			return rig.reducer:observeMessage(value)
		end,
		getState = function(_self)
			return rig.reducer:getState()
		end,
		cleanup = function(_self)
			rig.reducerCleanupCount += 1
			table.insert(rig.cleanupOrder, "reducer")
			return rig.reducer:cleanup()
		end,
	}
	local viewAdapter = {
		render = function(_self, value)
			table.insert(rig.renderStates, value)
			return Result.ok(true)
		end,
		getMetrics = function(_self)
			return Result.ok(table.freeze({ renderCount = #rig.renderStates }))
		end,
		cleanup = function(_self)
			rig.viewCleanupCount += 1
			table.insert(rig.cleanupOrder, "view")
			return Result.ok(true)
		end,
	}

	local getDefinition = ProductionRemotes:get(BaseProtocol.GET_BASE_SNAPSHOT_ENDPOINT)
	local eventDefinition = ProductionRemotes:get(BaseProtocol.BASE_REPLICATION_ENDPOINT)
	if getDefinition == nil or eventDefinition == nil then
		error("[ATD_TEST_FIXTURE][code=BASE_CONTROLLER_DEFINITION_MISSING]", 0)
	end
	local selectedOptions = options or {}
	local dependencies: BaseController.Dependencies = {
		tracker = rig.tracker :: any,
		getSnapshot = {
			definition = getDefinition,
			connectResponse = function(listener)
				return rig.responseSignal:connect(listener)
			end,
			fire = function(envelope)
				table.insert(rig.order, "fire-snapshot")
				table.insert(rig.requestFires, envelope)
				if selectedOptions.respondDuringFirstFire and #rig.requestFires == 1 then
					rig.eventSignal:fire({ payload = message(snapshot(2, 80), 20, false) })
					rig.responseSignal:fire(successWire(envelope, snapshot(1, 100)))
				end
				if selectedOptions.fireAlwaysThrows then
					error("PRIVATE_BASE_CONTROLLER_FIRE_FAILURE", 0)
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
		view = viewAdapter :: any,
		projectView = require(script.Parent.Parent.ProductionClientBase.BaseViewModel).project,
	}
	local controllerResult = (newControllerForTests :: BaseController.TestConstructor)(logger, dependencies)
	if not controllerResult.ok then
		error("[ATD_TEST_FIXTURE][code=BASE_CONTROLLER_CREATION_FAILED]", 0)
	end
	rig.controller = controllerResult.value
	rig.definition = rig.controller:getServiceDefinition()
	rig.definition.initialize()
	rig.definition.start()
	return rig
end

local function sendEvent(rig: Rig, value: BaseProtocol.BaseReplicationMessage)
	rig.eventSignal:fire({ payload = value })
end

local function sendResponse(rig: Rig, requestIndex: number, value: BaseProtocol.BaseSnapshot)
	rig.responseSignal:fire(successWire(rig.requestFires[requestIndex], value))
end

local function current(rig: Rig): BaseProtocol.BaseSnapshot?
	local result = rig.reducer:getState()
	if not result.ok then
		return nil
	end
	return result.value.snapshot
end

local function shutdown(rig: Rig)
	rig.definition.shutdown()
end

return TestHarness.suite("BaseController", {
	TestHarness.case("installs event then response listeners before the exact empty request", function(assertions)
		local rig = makeRig({ respondDuringFirstFire = true })
		assertions.isTrue(table.isfrozen(BaseController))
		assertions.equal(BaseController.SERVICE_NAME, "BaseController")
		assertions.equal(rig.controller:getState(), "Started")
		assertions.equal(rig.definition.dependencies[1], "MatchReadyController")
		assertions.equal(table.concat(rig.order, ","), "base-event,base-response,fire-snapshot")
		assertions.equal(#rig.requestFires, 1)
		assertions.equal(keyCount(rig.requestFires[1]), 2)
		assertions.equal(keyCount(rig.requestFires[1].payload), 0)
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).baseRevision, 2)
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).currentHealth, 80)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		assertions.equal(rig.controller:getMetrics().connectionCount, 2)
		shutdown(rig)
	end),

	TestHarness.case("converges response-event races and emits equal-revision feedback once", function(assertions)
		local rig = makeRig()
		sendResponse(rig, 1, snapshot(1, 100))
		sendEvent(rig, message(snapshot(2, 80), nil, nil))
		local rendersBeforeFeedback = #rig.renderStates
		sendEvent(rig, message(snapshot(2, 80), 20, false))
		sendEvent(rig, message(snapshot(2, 80), 20, false))
		sendEvent(rig, message(snapshot(1, 100), nil, nil))
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).baseRevision, 2)
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).currentHealth, 80)
		assertions.equal(#rig.renderStates, rendersBeforeFeedback + 1)
		assertions.isTrue(rig.renderStates[#rig.renderStates].damageVisible)
		assertions.equal(rig.renderStates[#rig.renderStates].damageText, "-20")
		assertions.equal(rig.controller:getMetrics().feedbackCount, 1)
		shutdown(rig)
	end),

	TestHarness.case("accepts skipped full state without rollback and rejects foreign identity", function(assertions)
		local rig = makeRig()
		sendResponse(rig, 1, snapshot(1, 100))
		sendEvent(rig, message(snapshot(8, 25), 75, true))
		sendEvent(rig, message(snapshot(9, 20, "Active", { matchId = MATCH_B }), nil, nil))
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).baseRevision, 8)
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).currentHealth, 25)
		assertions.isTrue(rig.renderStates[#rig.renderStates].lowVisible)
		assertions.equal(rig.renderStates[#rig.renderStates].lowText, "LOW")
		shutdown(rig)
	end),

	TestHarness.case("bounds malformed recovery and throwing sends to two attempts", function(assertions)
		local malformed = makeRig()
		malformed.responseSignal:fire({
			requestId = malformed.requestFires[1].requestId,
			state = "Success",
			payload = { private = "PRIVATE_BASE_RESPONSE" },
		})
		assertions.equal(#malformed.requestFires, 2)
		malformed.eventSignal:fire({ payload = { private = "PRIVATE_BASE_EVENT" } })
		malformed.responseSignal:fire(42)
		assertions.equal(#malformed.requestFires, BaseController.MAX_SNAPSHOT_ATTEMPTS)
		shutdown(malformed)

		local throwing = makeRig({ fireAlwaysThrows = true })
		assertions.equal(#throwing.requestFires, BaseController.MAX_SNAPSHOT_ATTEMPTS)
		assertions.equal(throwing.tracker:getStats().pendingCount, 0)
		shutdown(throwing)
	end),

	TestHarness.case("recovers a delayed bootstrap after one retryable response", function(assertions)
		local rig = makeRig()
		rig.responseSignal:fire(rejectedWire(rig.requestFires[1], "UNAVAILABLE"))
		assertions.equal(#rig.requestFires, 2)
		assertions.isTrue(rig.controller:getMetrics().snapshotRequestPending)

		sendResponse(rig, 2, snapshot(6, 40))
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).baseRevision, 6)
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).currentHealth, 40)
		assertions.isFalse(rig.controller:getMetrics().snapshotRequestPending)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)

		sendEvent(rig, message(snapshot(5, 50), nil, nil))
		rig.eventSignal:fire({ payload = { private = "PRIVATE_DELAYED_BASE_EVENT" } })
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).baseRevision, 6)
		assertions.equal(#rig.requestFires, BaseController.MAX_SNAPSHOT_ATTEMPTS)
		shutdown(rig)
	end),

	TestHarness.case("reconnects with a fresh controller and cannot revive the old match", function(assertions)
		local oldRig = makeRig()
		sendResponse(oldRig, 1, snapshot(3, 70))
		local oldRenderCount = #oldRig.renderStates
		shutdown(oldRig)

		local replacement = makeRig()
		local replacementSnapshot = snapshot(1, 100, "Active", {
			matchId = MATCH_B,
			enemyEpoch = 2,
			mapId = "map:base-controller-b",
			difficultyId = "difficulty:base-controller-b",
			initializedServerTime = 200,
			updatedServerTime = 201,
		})
		sendResponse(replacement, 1, replacementSnapshot)
		assertions.equal(replacement.controller:getMetrics().matchId, MATCH_B)
		assertions.equal(replacement.controller:getMetrics().enemyEpoch, 2)
		assertions.equal(replacement.controller:getMetrics().baseRevision, 1)

		oldRig.eventSignal:force({ payload = message(snapshot(4, 60), 10, false) })
		oldRig.responseSignal:force(successWire(oldRig.requestFires[1], snapshot(4, 60)))
		assertions.equal(#oldRig.renderStates, oldRenderCount)
		assertions.equal(replacement.controller:getMetrics().matchId, MATCH_B)
		shutdown(replacement)
	end),

	TestHarness.case("exposes bounded Studio diagnostics and rejects hostile bridge requests", function(assertions)
		local rig = makeRig()
		local invoke = invokeStudioDiagnosticsForTests :: (BaseController.Controller, ...unknown) -> unknown
		assertions.equal(BaseController.STUDIO_DIAGNOSTICS_BRIDGE_NAME, "_ATDPhase10BaseDiagnostics")

		local diagnostics = invoke(rig.controller, { operation = "Diagnostics" }) :: any
		assertions.isTrue(diagnostics.ok)
		assertions.isTrue(table.isfrozen(diagnostics))
		assertions.isTrue(table.isfrozen(diagnostics.value))
		assertions.equal(diagnostics.value.controller.connectionCount, 2)
		assertions.equal(diagnostics.value.controller.snapshotAttemptCount, 1)
		assertions.isTrue(diagnostics.value.controller.snapshotRequestPending)
		assertions.isFalse(diagnostics.value.controller.studioRecoverySuspended)
		assertions.isFalse(diagnostics.value.controller.studioRecoveryUsed)
		assertions.equal(diagnostics.value.controller.studioRecoveryAttemptCount, 0)
		assertions.equal(diagnostics.value.view.renderCount, #rig.renderStates)

		local withMetatable = setmetatable({ operation = "Diagnostics" }, {})
		local malformed = {
			invoke(rig.controller),
			invoke(rig.controller, nil),
			invoke(rig.controller, {}),
			invoke(rig.controller, { operation = "Unknown" }),
			invoke(rig.controller, { operation = "Diagnostics", private = true }),
			invoke(rig.controller, withMetatable),
			invoke(rig.controller, { operation = "Diagnostics" }, "extra"),
		}
		for _, response in malformed do
			assertions.isFalse((response :: any).ok)
			assertions.equal((response :: any).error.code, "INVALID_REQUEST")
			assertions.isTrue(table.isfrozen(response :: any))
		end

		shutdown(rig)
		local unavailable = invoke(rig.controller, { operation = "Diagnostics" }) :: any
		assertions.isFalse(unavailable.ok)
		assertions.equal(unavailable.error.code, "UNAVAILABLE")

		local productionFolder = script.Parent.Parent.ProductionClientBase:Clone()
		productionFolder.Name = "BaseControllerProductionLocationProbe"
		productionFolder.Parent = ReplicatedStorage
		local productionLocated = require(productionFolder.BaseController)
		assertions.isNil(productionLocated.newForTests)
		assertions.isNil(productionLocated.invokeStudioDiagnosticsForTests)
		productionFolder:Destroy()
	end),

	TestHarness.case("suspends presentation and resumes through one bounded full snapshot", function(assertions)
		local rig = makeRig()
		local invoke = invokeStudioDiagnosticsForTests :: (BaseController.Controller, ...unknown) -> unknown
		assertions.equal(#rig.requestFires, 1)
		assertions.isTrue(rig.controller:getMetrics().snapshotRequestPending)

		local renderCountBeforeSuspend = #rig.renderStates
		local suspended = invoke(rig.controller, { operation = "SuspendRecovery" }) :: any
		assertions.isTrue(suspended.ok)
		assertions.isTrue(suspended.value.controller.studioRecoverySuspended)
		assertions.isTrue(suspended.value.controller.studioRecoveryUsed)
		assertions.isFalse(suspended.value.controller.snapshotRequestPending)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		assertions.equal(#rig.renderStates, renderCountBeforeSuspend + 1)
		assertions.isFalse(rig.renderStates[#rig.renderStates].visible)

		local suspendedAgain = invoke(rig.controller, { operation = "SuspendRecovery" }) :: any
		assertions.isTrue(suspendedAgain.ok)
		assertions.equal(#rig.renderStates, renderCountBeforeSuspend + 1)
		assertions.equal(#rig.requestFires, 1)

		sendEvent(rig, message(snapshot(3, 70), 30, false))
		rig.responseSignal:force(successWire(rig.requestFires[1], snapshot(2, 80)))
		assertions.isNil(current(rig))
		assertions.equal(#rig.renderStates, renderCountBeforeSuspend + 1)

		local resumed = invoke(rig.controller, { operation = "ResumeRecovery" }) :: any
		assertions.isTrue(resumed.ok)
		assertions.isFalse(resumed.value.controller.studioRecoverySuspended)
		assertions.isTrue(resumed.value.controller.snapshotRequestPending)
		assertions.equal(resumed.value.controller.studioRecoveryAttemptCount, 1)
		assertions.equal(#rig.requestFires, 2)
		assertions.equal(rig.tracker:getStats().pendingCount, 1)

		-- The canceled response cannot consume the one resumed request.
		rig.responseSignal:force(successWire(rig.requestFires[1], snapshot(2, 80)))
		assertions.isTrue(rig.controller:getMetrics().snapshotRequestPending)
		sendResponse(rig, 2, snapshot(4, 60))
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).baseRevision, 4)
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).currentHealth, 60)
		assertions.isTrue(rig.renderStates[#rig.renderStates].visible)
		assertions.isFalse(rig.controller:getMetrics().snapshotRequestPending)

		local resumedAgain = invoke(rig.controller, { operation = "ResumeRecovery" }) :: any
		assertions.isTrue(resumedAgain.ok)
		assertions.equal(#rig.requestFires, 2)
		local secondCycle = invoke(rig.controller, { operation = "SuspendRecovery" }) :: any
		assertions.isFalse(secondCycle.ok)
		assertions.equal(secondCycle.error.code, "INTERNAL_ERROR")
		assertions.isFalse(rig.controller:getMetrics().studioRecoverySuspended)
		shutdown(rig)
		assertions.isFalse(rig.controller:getMetrics().studioRecoverySuspended)
	end),

	TestHarness.case("restores active-session presentation from an equal-revision recovery", function(assertions)
		local rig = makeRig()
		local invoke = invokeStudioDiagnosticsForTests :: (BaseController.Controller, ...unknown) -> unknown
		local authoritative = snapshot(5, 55)
		sendResponse(rig, 1, authoritative)
		assertions.isTrue(rig.renderStates[#rig.renderStates].visible)
		local acceptedBefore = rig.controller:getMetrics().acceptedStateCount

		local suspended = invoke(rig.controller, { operation = "SuspendRecovery" }) :: any
		assertions.isTrue(suspended.ok)
		assertions.isFalse(rig.renderStates[#rig.renderStates].visible)
		local resumed = invoke(rig.controller, { operation = "ResumeRecovery" }) :: any
		assertions.isTrue(resumed.ok)
		sendResponse(rig, 2, authoritative)

		assertions.equal(rig.controller:getMetrics().acceptedStateCount, acceptedBefore)
		assertions.equal((current(rig) :: BaseProtocol.BaseSnapshot).baseRevision, 5)
		assertions.isTrue(rig.renderStates[#rig.renderStates].visible)
		assertions.equal(rig.renderStates[#rig.renderStates].healthText, "55 / 100")
		assertions.isFalse(rig.controller:getMetrics().snapshotRequestPending)
		shutdown(rig)
	end),

	TestHarness.case("keeps Studio recovery suspended when the request cap is exhausted", function(assertions)
		local rig = makeRig({ fireAlwaysThrows = true })
		local invoke = invokeStudioDiagnosticsForTests :: (BaseController.Controller, ...unknown) -> unknown
		assertions.equal(#rig.requestFires, BaseController.MAX_SNAPSHOT_ATTEMPTS)
		local suspended = invoke(rig.controller, { operation = "SuspendRecovery" }) :: any
		assertions.isTrue(suspended.ok)
		assertions.isTrue(suspended.value.controller.studioRecoverySuspended)
		local resumed = invoke(rig.controller, { operation = "ResumeRecovery" }) :: any
		assertions.isFalse(resumed.ok)
		assertions.equal(resumed.error.code, "UNAVAILABLE")
		assertions.isTrue(rig.controller:getMetrics().studioRecoverySuspended)
		assertions.equal(rig.controller:getMetrics().studioRecoveryAttemptCount, BaseController.MAX_SNAPSHOT_ATTEMPTS)
		assertions.equal(#rig.requestFires, BaseController.MAX_SNAPSHOT_ATTEMPTS * 2)
		shutdown(rig)
	end),

	TestHarness.case("cleans presentation before reducer and disables captured callbacks", function(assertions)
		local rig = makeRig()
		local firesBefore = #rig.requestFires
		shutdown(rig)
		assertions.equal(rig.controller:getState(), "Shutdown")
		assertions.equal(rig.disconnectCount, 2)
		assertions.equal(table.concat(rig.cleanupOrder, ","), "view,reducer")
		assertions.equal(rig.viewCleanupCount, 1)
		assertions.equal(rig.reducerCleanupCount, 1)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		rig.eventSignal:force({ payload = message(snapshot(2, 80), 20, false) })
		rig.responseSignal:force(successWire(rig.requestFires[1], snapshot(1, 100)))
		assertions.equal(#rig.requestFires, firesBefore)
		shutdown(rig)
		assertions.equal(rig.disconnectCount, 2)
		assertions.equal(rig.viewCleanupCount, 1)
		assertions.equal(rig.reducerCleanupCount, 1)
	end),
})
