--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local ClientRequestTracker = require(script.Parent.Parent.ProductionClientNetworking.ClientRequestTracker)
local EnemyController = require(script.Parent.Parent.ProductionClientEnemies.EnemyController)
local EnemyReplicationState = require(script.Parent.Parent.ProductionClientEnemies.EnemyReplicationState)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local ProductionRemotes = require(ReplicatedStorage.Shared.network.ProductionRemotes)
local Result = require(ReplicatedStorage.Shared.util.Result)

type Assertions = TestHarness.Assertions
type Controller = EnemyController.Controller
type ReplicationState = EnemyReplicationState.State

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
	controller: Controller,
	definition: any,
	tracker: ClientRequestTracker.Tracker,
	replicationState: ReplicationState,
	order: { string },
	cleanupOrder: { string },
	requestFires: { any },
	eventSignal: Signal,
	responseSignal: Signal,
	preRender: (() -> ())?,
	serverTime: unknown,
	timeThrows: boolean,
	renderSnapshots: { any },
	renderTimes: { number },
	disconnectCount: number,
	preRenderConnectionCount: number,
	stateCleanupCount: number,
	rendererResetCount: number,
	rendererVisualCount: number,
	rendererCleanupCount: number,
	stateSnapshotCallCount: number,
}

local MATCH_A = "match:enemy-controller-a"
local MATCH_B = "match:enemy-controller-b"
local logger = Log.new(EnvironmentContext.new("client", "Match", 0, false))
local newTrackerForTests = ClientRequestTracker.newForTests
local newControllerForTests = EnemyController.newForTests
local invokeStudioDiagnosticsForTests = EnemyController.invokeStudioDiagnosticsForTests
if newTrackerForTests == nil or newControllerForTests == nil or invokeStudioDiagnosticsForTests == nil then
	error("[ATD_TEST_FIXTURE][code=ENEMY_CONTROLLER_TEST_SEAM_MISSING]", 0)
end

local function keyCount(value: { [any]: unknown }): number
	local count = 0
	for _ in next, value do
		count += 1
	end
	return count
end

local function canonicalCFrame(position: Vector3): CFrame
	local direction = Vector3.xAxis
	local right = direction:Cross(Vector3.yAxis).Unit
	local up = right:Cross(direction).Unit
	return CFrame.fromMatrix(position, right, up, -direction)
end

local function stateEntry(runtimeEnemyId: number, revision: number): { [string]: unknown }
	local progress = math.min(9, revision)
	local startPosition = Vector3.new(0, 2, 0)
	local endPosition = Vector3.new(10, 2, 0)
	return {
		runtimeEnemyId = runtimeEnemyId,
		enemyId = "enemy:phase09-controller-test",
		laneId = "lane:controller",
		revision = revision,
		lifecycle = "Active",
		pathProgress = progress,
		currentHealth = 100,
		maximumHealth = 100,
		slowMultiplier = 1,
		spawnServerTime = 100,
		sampleServerTime = 100 + revision,
		worldCFrame = canonicalCFrame(startPosition:Lerp(endPosition, progress / 10)),
		effectiveSpeed = 4,
		segmentIndex = 1,
		segmentStartDistance = 0,
		segmentEndDistance = 10,
		segmentStartPosition = startPosition,
		segmentEndPosition = endPosition,
	}
end

local function canonicalMessage(value: unknown): EnemyProtocol.EnemyReplicationMessage
	local validated = EnemyProtocol.validateEnemyReplication(value)
	if not validated.ok then
		error(`[ATD_TEST_FIXTURE][code=ENEMY_CONTROLLER_MESSAGE_INVALID][path={validated.error.path}]`, 0)
	end
	return validated.value
end

local function canonicalReceipt(
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	chunkCount: number,
	totalEntries: number
): EnemyProtocol.EnemySnapshotReceipt
	local validated = EnemyProtocol.validateEnemySnapshotReceipt({
		matchId = matchId,
		enemyEpoch = enemyEpoch,
		baseSequence = baseSequence,
		snapshotId = snapshotId,
		chunkCount = chunkCount,
		totalEntries = totalEntries,
	})
	if not validated.ok then
		error(`[ATD_TEST_FIXTURE][code=ENEMY_CONTROLLER_RECEIPT_INVALID][path={validated.error.path}]`, 0)
	end
	return validated.value
end

local function boundary(
	kind: "SnapshotBegin" | "SnapshotEnd",
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	chunkCount: number,
	totalEntries: number
): EnemyProtocol.EnemyReplicationMessage
	return canonicalMessage({
		kind = kind,
		matchId = matchId,
		enemyEpoch = enemyEpoch,
		baseSequence = baseSequence,
		snapshotId = snapshotId,
		chunkCount = chunkCount,
		totalEntries = totalEntries,
	})
end

local function chunk(
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	entries: { { [string]: unknown } }
): EnemyProtocol.EnemyReplicationMessage
	return canonicalMessage({
		kind = "SnapshotChunk",
		matchId = matchId,
		enemyEpoch = enemyEpoch,
		baseSequence = baseSequence,
		snapshotId = snapshotId,
		chunkIndex = 1,
		entries = entries,
	})
end

local function delta(
	kind: "SpawnBatch" | "CorrectionBatch",
	matchId: string,
	enemyEpoch: number,
	sequence: number,
	entries: { { [string]: unknown } }
): EnemyProtocol.EnemyReplicationMessage
	return canonicalMessage({
		kind = kind,
		matchId = matchId,
		enemyEpoch = enemyEpoch,
		sequence = sequence,
		entries = entries,
	})
end

local function successWire(request: any, payload: unknown): { [string]: unknown }
	return {
		requestId = request.requestId,
		state = "Success",
		payload = payload,
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

local function sendEvent(rig: Rig, message: EnemyProtocol.EnemyReplicationMessage)
	rig.eventSignal:fire({ payload = message })
end

local function sendSnapshotEvents(
	rig: Rig,
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	entries: { { [string]: unknown } }
)
	local chunkCount = if #entries == 0 then 0 else 1
	sendEvent(rig, boundary("SnapshotBegin", matchId, enemyEpoch, baseSequence, snapshotId, chunkCount, #entries))
	if chunkCount == 1 then
		sendEvent(rig, chunk(matchId, enemyEpoch, baseSequence, snapshotId, entries))
	end
	sendEvent(rig, boundary("SnapshotEnd", matchId, enemyEpoch, baseSequence, snapshotId, chunkCount, #entries))
end

local function sendReceipt(
	rig: Rig,
	requestIndex: number,
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	totalEntries: number
)
	local chunkCount = if totalEntries == 0 then 0 else 1
	rig.responseSignal:fire(
		successWire(
			rig.requestFires[requestIndex],
			canonicalReceipt(matchId, enemyEpoch, baseSequence, snapshotId, chunkCount, totalEntries)
		)
	)
end

local function makeRig(options: Options?): Rig
	local requestCounter = 0
	local trackerResult = (newTrackerForTests :: ClientRequestTracker.TestConstructor)(
		ProductionRemotes,
		"Match",
		function(): string
			requestCounter += 1
			return `enemyctrl{string.format("%04d", requestCounter)}`
		end
	)
	if not trackerResult.ok then
		error("[ATD_TEST_FIXTURE][code=ENEMY_CONTROLLER_TRACKER_FAILED]", 0)
	end

	local rig = {
		controller = nil :: any,
		definition = nil,
		tracker = trackerResult.value,
		replicationState = EnemyReplicationState.new(),
		order = {},
		cleanupOrder = {},
		requestFires = {},
		eventSignal = nil :: any,
		responseSignal = nil :: any,
		preRender = nil,
		serverTime = 100,
		timeThrows = false,
		renderSnapshots = {},
		renderTimes = {},
		disconnectCount = 0,
		preRenderConnectionCount = 0,
		stateCleanupCount = 0,
		rendererResetCount = 0,
		rendererVisualCount = 0,
		rendererCleanupCount = 0,
		stateSnapshotCallCount = 0,
	} :: Rig
	rig.eventSignal = makeSignal(rig, "replication-event")
	rig.responseSignal = makeSignal(rig, "snapshot-response")

	local stateAdapter = {
		observeMessage = function(_self, message)
			return rig.replicationState:observeMessage(message)
		end,
		observeReceipt = function(_self, receipt, now)
			return rig.replicationState:observeReceipt(receipt, now)
		end,
		advance = function(_self, now)
			return rig.replicationState:advance(now)
		end,
		getSnapshot = function(_self)
			rig.stateSnapshotCallCount += 1
			return rig.replicationState:getSnapshot()
		end,
		cleanup = function(_self)
			rig.stateCleanupCount += 1
			table.insert(rig.cleanupOrder, "state")
			return rig.replicationState:cleanup()
		end,
	}
	local rendererAdapter = {
		render = function(_self, snapshot, now)
			table.insert(rig.renderSnapshots, snapshot)
			table.insert(rig.renderTimes, now)
			rig.rendererVisualCount = #(snapshot :: any).entries
			return Result.ok(true)
		end,
		reset = function(_self)
			rig.rendererResetCount += 1
			rig.rendererVisualCount = 0
			return Result.ok(true)
		end,
		cleanup = function(_self)
			rig.rendererCleanupCount += 1
			table.insert(rig.cleanupOrder, "renderer")
			return Result.ok(true)
		end,
	}

	local getDefinition = ProductionRemotes:get(EnemyProtocol.GET_ENEMY_SNAPSHOT_ENDPOINT)
	local eventDefinition = ProductionRemotes:get(EnemyProtocol.ENEMY_REPLICATION_ENDPOINT)
	if getDefinition == nil or eventDefinition == nil then
		error("[ATD_TEST_FIXTURE][code=ENEMY_CONTROLLER_DEFINITION_MISSING]", 0)
	end
	local selectedOptions = options or {}
	local dependencies: EnemyController.Dependencies = {
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
					sendSnapshotEvents(rig, MATCH_A, 1, 0, 1, {})
					sendReceipt(rig, 1, MATCH_A, 1, 0, 1, 0)
				end
				if selectedOptions.fireAlwaysThrows then
					error("PRIVATE_ENEMY_CONTROLLER_FIRE_FAILURE", 0)
				end
			end,
		},
		replicationEvent = {
			definition = eventDefinition,
			connectEvent = function(listener)
				return rig.eventSignal:connect(listener)
			end,
		},
		state = stateAdapter :: any,
		renderer = rendererAdapter :: any,
		connectPreRender = function(callback)
			table.insert(rig.order, "pre-render")
			rig.preRenderConnectionCount += 1
			rig.preRender = callback
			local active = true
			return RobloxAdapter.createConnection(function()
				if active then
					active = false
					rig.disconnectCount += 1
				end
			end) :: RBXScriptConnection
		end,
		getServerTimeNow = function(): unknown
			if rig.timeThrows then
				error("PRIVATE_ENEMY_CONTROLLER_TIME_FAILURE", 0)
			end
			return rig.serverTime
		end,
	}
	local controllerResult = (newControllerForTests :: EnemyController.TestConstructor)(logger, dependencies)
	if not controllerResult.ok then
		error("[ATD_TEST_FIXTURE][code=ENEMY_CONTROLLER_CREATION_FAILED]", 0)
	end
	rig.controller = controllerResult.value
	rig.definition = rig.controller:getServiceDefinition()
	rig.definition.initialize()
	rig.definition.start()
	return rig
end

local function preRender(rig: Rig)
	local callback = rig.preRender
	if callback == nil then
		error("[ATD_TEST_FIXTURE][code=ENEMY_CONTROLLER_PRE_RENDER_MISSING]", 0)
	end
	callback()
end

local function shutdown(rig: Rig)
	rig.definition.shutdown()
end

local function snapshot(rig: Rig): EnemyReplicationState.ConvergedSnapshot
	local result = rig.replicationState:getSnapshot()
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=ENEMY_CONTROLLER_STATE_READ_FAILED]", 0)
	end
	return result.value
end

return TestHarness.suite("enemy replication client controller", {
	TestHarness.case(
		"connects both listeners and one PreRender before the exact initial request race",
		function(assertions)
			local rig = makeRig({ respondDuringFirstFire = true })
			assertions.isTrue(table.isfrozen(EnemyController))
			assertions.equal(EnemyController.SERVICE_NAME, "EnemyController")
			assertions.isNil(EnemyController.getStudioDiagnostics)
			assertions.equal(rig.controller:getState(), "Started")
			assertions.equal(rig.definition.name, "EnemyController")
			assertions.equal(#rig.definition.dependencies, 1)
			assertions.equal(rig.definition.dependencies[1], "BaseController")
			assertions.equal(
				table.concat(rig.order, ","),
				"replication-event,snapshot-response,pre-render,fire-snapshot"
			)
			assertions.equal(#rig.requestFires, 1)
			assertions.equal(keyCount(rig.requestFires[1]), 2)
			assertions.equal(keyCount(rig.requestFires[1].payload), 0)
			assertions.equal(rig.tracker:getStats().pendingCount, 0)
			assertions.isTrue(snapshot(rig).locked)
			assertions.equal(snapshot(rig).matchId, MATCH_A)
			shutdown(rig)
		end
	),

	TestHarness.case("converges deltas and stale duplicates never roll authoritative state back", function(assertions)
		local rig = makeRig()
		sendSnapshotEvents(rig, MATCH_A, 1, 0, 1, {})
		sendReceipt(rig, 1, MATCH_A, 1, 0, 1, 0)
		sendEvent(rig, delta("SpawnBatch", MATCH_A, 1, 1, { stateEntry(1, 1) }))
		sendEvent(rig, delta("CorrectionBatch", MATCH_A, 1, 1, { stateEntry(1, 7) }))
		assertions.equal(snapshot(rig).lastSequence, 1)
		assertions.equal(snapshot(rig).entries[1].revision, 1)
		preRender(rig)
		assertions.equal(#rig.renderSnapshots, 1)
		assertions.equal(rig.renderSnapshots[1].entries[1].revision, 1)
		shutdown(rig)
	end),

	TestHarness.case(
		"uses the second request for a live sequence gap and passes replacement identity",
		function(assertions)
			local rig = makeRig()
			sendSnapshotEvents(rig, MATCH_A, 1, 0, 1, {})
			sendReceipt(rig, 1, MATCH_A, 1, 0, 1, 0)
			sendEvent(rig, delta("CorrectionBatch", MATCH_A, 1, 2, { stateEntry(1, 2) }))
			assertions.equal(#rig.requestFires, 2)
			sendSnapshotEvents(rig, MATCH_B, 2, 0, 1, { stateEntry(2, 1) })
			sendReceipt(rig, 2, MATCH_B, 2, 0, 1, 1)
			assertions.equal(snapshot(rig).matchId, MATCH_B)
			assertions.equal(snapshot(rig).enemyEpoch, 2)
			assertions.equal(snapshot(rig).entries[1].runtimeEnemyId, 2)
			preRender(rig)
			assertions.equal(rig.renderSnapshots[#rig.renderSnapshots].matchId, MATCH_B)
			assertions.equal(rig.renderSnapshots[#rig.renderSnapshots].enemyEpoch, 2)
			shutdown(rig)
		end
	),

	TestHarness.case("times out two incomplete recoveries and exhausts the fixed attempt bound", function(assertions)
		local rig = makeRig()
		sendReceipt(rig, 1, MATCH_A, 1, 0, 1, 0)
		rig.serverTime = 102
		preRender(rig)
		assertions.equal(#rig.requestFires, 2)
		sendReceipt(rig, 2, MATCH_A, 1, 0, 2, 0)
		rig.serverTime = 104
		preRender(rig)
		assertions.equal(#rig.requestFires, EnemyController.MAX_SNAPSHOT_ATTEMPTS)
		assertions.isTrue(snapshot(rig).recoveryRequired)
		shutdown(rig)
	end),

	TestHarness.case("bounds malformed and throwing sender recovery without exposing failures", function(assertions)
		local malformed = makeRig()
		malformed.responseSignal:fire({
			requestId = malformed.requestFires[1].requestId,
			state = "Success",
			payload = { private = "PRIVATE_ENEMY_CONTROLLER_RESPONSE" },
		})
		assertions.equal(#malformed.requestFires, 2)
		assertions.equal(malformed.tracker:getStats().pendingCount, 1)
		malformed.eventSignal:fire({ payload = { private = "PRIVATE_ENEMY_CONTROLLER_EVENT" } })
		malformed.responseSignal:fire(42)
		assertions.equal(#malformed.requestFires, EnemyController.MAX_SNAPSHOT_ATTEMPTS)
		shutdown(malformed)

		local throwing = makeRig({ fireAlwaysThrows = true })
		assertions.equal(#throwing.requestFires, EnemyController.MAX_SNAPSHOT_ATTEMPTS)
		assertions.equal(throwing.tracker:getStats().pendingCount, 0)
		preRender(throwing)
		assertions.equal(#throwing.requestFires, EnemyController.MAX_SNAPSHOT_ATTEMPTS)
		shutdown(throwing)
	end),

	TestHarness.case("keeps synchronized time protected and monotonically nondecreasing", function(assertions)
		local rig = makeRig({ respondDuringFirstFire = true })
		preRender(rig)
		assertions.equal(#rig.renderTimes, 1)
		assertions.equal(rig.renderTimes[1], 100)
		rig.serverTime = 99
		preRender(rig)
		assertions.equal(#rig.renderTimes, 1)
		rig.timeThrows = true
		preRender(rig)
		assertions.equal(#rig.renderTimes, 1)
		rig.timeThrows = false
		rig.serverTime = 101
		preRender(rig)
		assertions.equal(#rig.renderTimes, 2)
		assertions.equal(rig.renderTimes[2], 101)
		shutdown(rig)
	end),

	TestHarness.case("holds one render connection while enemy count grows", function(assertions)
		local rig = makeRig()
		sendSnapshotEvents(rig, MATCH_A, 1, 0, 1, {})
		sendReceipt(rig, 1, MATCH_A, 1, 0, 1, 0)
		for runtimeEnemyId = 1, 24 do
			sendEvent(rig, delta("SpawnBatch", MATCH_A, 1, runtimeEnemyId, { stateEntry(runtimeEnemyId, 1) }))
		end
		assertions.equal(rig.preRenderConnectionCount, 1)
		assertions.equal(#snapshot(rig).entries, 24)
		local snapshotCallsBeforeRender = rig.stateSnapshotCallCount
		preRender(rig)
		assertions.equal(#rig.renderSnapshots[#rig.renderSnapshots].entries, 24)
		assertions.equal(rig.preRenderConnectionCount, 1)
		assertions.equal(rig.stateSnapshotCallCount, snapshotCallsBeforeRender)
		local metrics = rig.controller:getMetrics()
		assertions.equal(metrics.renderConnectionCount, 1)
		assertions.equal(metrics.renderPassCount, 1)
		assertions.equal(metrics.renderDurationSampleCount, 1)
		assertions.equal(metrics.cachedEntryCount, 24)
		local diagnostics = rig.controller:getStudioDiagnostics()
		assertions.equal(diagnostics.controller.renderPassCount, metrics.renderPassCount)
		assertions.equal(diagnostics.controller.cachedLastSequence, metrics.cachedLastSequence)
		assertions.equal(#(diagnostics.replication :: any).entries, 24)
		assertions.isNil(diagnostics.renderer)
		assertions.isTrue(table.isfrozen(diagnostics))
		shutdown(rig)
	end),

	TestHarness.case("strictly validates Studio diagnostics and resets only render timing", function(assertions)
		local rig = makeRig({ respondDuringFirstFire = true })
		preRender(rig)
		preRender(rig)
		local before = rig.controller:getMetrics()
		assertions.equal(before.renderPassCount, 2)
		assertions.equal(before.renderDurationSampleCount, 2)

		local invoke = invokeStudioDiagnosticsForTests :: (Controller, ...unknown) -> unknown
		local diagnostics = invoke(rig.controller, { operation = "Diagnostics" }) :: any
		assertions.isTrue(diagnostics.ok)
		assertions.equal(diagnostics.value.controller.renderPassCount, 2)
		assertions.isTrue(table.isfrozen(diagnostics))

		local malformed = {
			invoke(rig.controller),
			invoke(rig.controller, 42),
			invoke(rig.controller, {}),
			invoke(rig.controller, { operation = "Unknown" }),
			invoke(rig.controller, { operation = "Diagnostics", extra = true }),
			invoke(rig.controller, setmetatable({ operation = "Diagnostics" }, {})),
			invoke(rig.controller, { operation = "Diagnostics" }, "extra"),
		}
		for _, response in malformed do
			assertions.isFalse((response :: any).ok)
			assertions.equal((response :: any).error.code, "INVALID_REQUEST")
			assertions.isTrue(table.isfrozen(response :: any))
		end

		local reset = invoke(rig.controller, { operation = "ResetTiming" }) :: any
		assertions.isTrue(reset.ok)
		assertions.equal(reset.value.controller.renderPassCount, 0)
		assertions.equal(reset.value.controller.renderDurationSampleCount, 0)
		assertions.equal(reset.value.controller.renderDurationP50Milliseconds, 0)
		assertions.equal(reset.value.controller.renderDurationP95Milliseconds, 0)
		assertions.equal(reset.value.controller.renderDurationMaximumMilliseconds, 0)
		local after = rig.controller:getMetrics()
		assertions.equal(after.renderConnectionCount, before.renderConnectionCount)
		assertions.equal(after.snapshotRefreshCount, before.snapshotRefreshCount)
		assertions.equal(after.cachedMatchId, before.cachedMatchId)
		assertions.equal(after.cachedEnemyEpoch, before.cachedEnemyEpoch)
		assertions.equal(after.cachedLastSequence, before.cachedLastSequence)
		assertions.equal(after.cachedEntryCount, before.cachedEntryCount)
		assertions.equal(#rig.renderSnapshots, 2)
		preRender(rig)
		assertions.equal(rig.controller:getMetrics().renderPassCount, 1)

		shutdown(rig)
		local unavailable = invoke(rig.controller, { operation = "Diagnostics" }) :: any
		assertions.isFalse(unavailable.ok)
		assertions.equal(unavailable.error.code, "UNAVAILABLE")
	end),

	TestHarness.case("suspends callbacks and resumes through the existing bounded snapshot path", function(assertions)
		local rig = makeRig()
		local invoke = invokeStudioDiagnosticsForTests :: (Controller, ...unknown) -> unknown
		local before = rig.controller:getMetrics()
		assertions.equal(before.snapshotAttemptCount, 1)
		assertions.isTrue(before.snapshotRequestPending)
		assertions.isFalse(before.studioRecoverySuspended)

		local suspended = invoke(rig.controller, { operation = "SuspendRecovery" }) :: any
		assertions.isTrue(suspended.ok)
		assertions.isTrue(suspended.value.controller.studioRecoverySuspended)
		assertions.equal(suspended.value.controller.snapshotAttemptCount, 1)
		assertions.isFalse(suspended.value.controller.snapshotRequestPending)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		assertions.equal(rig.rendererResetCount, 1)
		assertions.equal(rig.rendererVisualCount, 0)

		local suspendedAgain = invoke(rig.controller, { operation = "SuspendRecovery" }) :: any
		assertions.isTrue(suspendedAgain.ok)
		assertions.equal(rig.rendererResetCount, 1)
		assertions.equal(#rig.requestFires, 1)

		sendEvent(rig, delta("SpawnBatch", MATCH_A, 1, 1, { stateEntry(1, 1) }))
		rig.responseSignal:force(successWire(rig.requestFires[1], canonicalReceipt(MATCH_A, 1, 0, 1, 0, 0)))
		preRender(rig)
		assertions.equal(#snapshot(rig).entries, 0)
		assertions.equal(#rig.renderSnapshots, 0)
		assertions.equal(rig.rendererVisualCount, 0)
		assertions.equal(rig.preRenderConnectionCount, 1)
		assertions.equal(rig.controller:getMetrics().renderConnectionCount, 1)

		local resumed = invoke(rig.controller, { operation = "ResumeRecovery" }) :: any
		assertions.isTrue(resumed.ok)
		assertions.isFalse(resumed.value.controller.studioRecoverySuspended)
		assertions.equal(resumed.value.controller.snapshotAttemptCount, 2)
		assertions.isTrue(resumed.value.controller.snapshotRequestPending)
		assertions.equal(#rig.requestFires, 2)
		assertions.equal(rig.tracker:getStats().pendingCount, 1)

		-- A canceled request may have a response already queued when suspension
		-- begins. Its old request ID cannot consume or replace the resumed request.
		rig.responseSignal:force(successWire(rig.requestFires[1], canonicalReceipt(MATCH_A, 1, 0, 1, 0, 0)))
		assertions.equal(rig.tracker:getStats().pendingCount, 1)
		assertions.equal(#rig.requestFires, 2)

		sendSnapshotEvents(rig, MATCH_A, 1, 1, 2, { stateEntry(1, 1) })
		sendReceipt(rig, 2, MATCH_A, 1, 1, 2, 1)
		assertions.equal(#snapshot(rig).entries, 1)
		assertions.equal(snapshot(rig).entries[1].runtimeEnemyId, 1)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		preRender(rig)
		assertions.equal(rig.rendererVisualCount, 1)
		assertions.equal(#rig.renderSnapshots, 1)

		local resumedAgain = invoke(rig.controller, { operation = "ResumeRecovery" }) :: any
		assertions.isTrue(resumedAgain.ok)
		assertions.equal(#rig.requestFires, 2)
		assertions.equal(rig.preRenderConnectionCount, 1)
		assertions.equal(rig.disconnectCount, 0)

		local capturedRender = rig.preRender :: () -> ()
		shutdown(rig)
		assertions.equal(rig.disconnectCount, 3)
		assertions.equal(rig.stateCleanupCount, 1)
		assertions.equal(rig.rendererCleanupCount, 1)
		assertions.isFalse(rig.controller:getMetrics().studioRecoverySuspended)
		local firesBeforeLateCallbacks = #rig.requestFires
		rig.eventSignal:force({ payload = delta("SpawnBatch", MATCH_A, 1, 2, { stateEntry(2, 1) }) })
		rig.responseSignal:force(successWire(rig.requestFires[2], canonicalReceipt(MATCH_A, 1, 1, 2, 0, 0)))
		capturedRender()
		assertions.equal(#rig.requestFires, firesBeforeLateCallbacks)
	end),

	TestHarness.case("keeps recovery suspended when the fixed request budget is exhausted", function(assertions)
		local rig = makeRig({ fireAlwaysThrows = true })
		local invoke = invokeStudioDiagnosticsForTests :: (Controller, ...unknown) -> unknown
		assertions.equal(#rig.requestFires, EnemyController.MAX_SNAPSHOT_ATTEMPTS)
		local suspended = invoke(rig.controller, { operation = "SuspendRecovery" }) :: any
		assertions.isTrue(suspended.ok)
		assertions.isTrue(suspended.value.controller.studioRecoverySuspended)
		local resumed = invoke(rig.controller, { operation = "ResumeRecovery" }) :: any
		assertions.isFalse(resumed.ok)
		assertions.equal(resumed.error.code, "UNAVAILABLE")
		assertions.isTrue(rig.controller:getMetrics().studioRecoverySuspended)
		assertions.equal(#rig.requestFires, EnemyController.MAX_SNAPSHOT_ATTEMPTS)
		shutdown(rig)
	end),

	TestHarness.case("disables captured callbacks and cleans state before renderer exactly once", function(assertions)
		local rig = makeRig()
		local capturedRender = rig.preRender :: () -> ()
		local firesBefore = #rig.requestFires
		shutdown(rig)
		assertions.equal(rig.controller:getState(), "Shutdown")
		assertions.equal(rig.disconnectCount, 3)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		assertions.equal(table.concat(rig.cleanupOrder, ","), "state,renderer")
		assertions.equal(rig.stateCleanupCount, 1)
		assertions.equal(rig.rendererCleanupCount, 1)
		shutdown(rig)
		assertions.equal(rig.disconnectCount, 3)
		assertions.equal(rig.stateCleanupCount, 1)
		assertions.equal(rig.rendererCleanupCount, 1)
		rig.eventSignal:force({ payload = boundary("SnapshotBegin", MATCH_A, 1, 0, 1, 0, 0) })
		rig.responseSignal:force({ private = "PRIVATE_ENEMY_CONTROLLER_LATE_RESPONSE" })
		capturedRender()
		assertions.equal(#rig.requestFires, firesBefore)
		assertions.equal(#rig.renderSnapshots, 0)
	end),
})
