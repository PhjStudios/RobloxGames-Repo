--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)

local Shared = game:GetService("ReplicatedStorage").Shared
local EnvironmentContext = require(Shared.logging.EnvironmentContext)
local Log = require(Shared.logging.Log)
local ServiceLifecycle = require(Shared.lifecycle.ServiceLifecycle)
local Result = require(Shared.util.Result)
local Validation = require(Shared.util.Validation)

local MatchModules = script.Parent.Parent.ProductionServerMatchLifecycle
local MatchLifecycleService = require(MatchModules.MatchLifecycleService)
local MatchStateMachine = require(MatchModules.MatchStateMachine)
local ParticipantRoster = require(script.Parent.Parent.ProductionServerMatchRoster.ParticipantRoster)

type Assertions = TestHarness.Assertions

type FakePlayer = {
	userId: number,
}

type FakePlayerSource = MatchLifecycleService.PlayerSource & {
	existing: { FakePlayer },
	addedListener: MatchLifecycleService.PlayerListener?,
	removingListener: MatchLifecycleService.PlayerListener?,
	order: { string },
	disconnectOrder: { string },
}

type FakeLoader = MatchLifecycleService.MapLoaderAdapter & {
	loadCount: number,
	cleanupCount: number,
	snapshotOverride: MatchStateMachine.StateSnapshot?,
	lastMapId: unknown,
	loadResult: unknown,
	cleanupResult: unknown,
	loadCallback: (() -> ())?,
	cleanupCallback: (() -> ())?,
}

type TimerHandle = {
	delaySeconds: number,
	callback: MatchLifecycleService.TimerCallback,
	cancelled: boolean,
}

type SentSnapshot = {
	recipient: unknown,
	snapshot: MatchLifecycleService.MatchSnapshot,
}

type DeterministicRuntime = {
	now: number,
	handles: { TimerHandle },
	cancelCount: number,
	sent: { SentSnapshot },
	clock: MatchLifecycleService.Clock,
	schedule: MatchLifecycleService.Schedule,
	cancel: MatchLifecycleService.Cancel,
	snapshotSender: MatchLifecycleService.SnapshotSender,
}

type RuntimeOverrides = {
	clock: MatchLifecycleService.Clock?,
	schedule: MatchLifecycleService.Schedule?,
	cancel: MatchLifecycleService.Cancel?,
	snapshotSender: MatchLifecycleService.SnapshotSender?,
}

local PRIVATE_SENTINEL = "PRIVATE_MATCH_LIFECYCLE_SENTINEL_0f26b8"
local MATCH_ID = "match:phase08-service-test"
local logger = Log.new(EnvironmentContext.new("server", "Development", 0, false))
local RUNTIME_MAP_SNAPSHOT: MatchLifecycleService.RuntimeMapSnapshot = table.freeze({
	mapId = MatchLifecycleService.FIXED_MAP_ID,
	base = table.freeze({
		cframe = CFrame.new(10, 0, 0),
		position = Vector3.new(10, 0, 0),
	}),
	bounds = table.freeze({
		cframe = CFrame.new(5, 0, 0),
		size = Vector3.new(20, 10, 20),
	}),
	lanes = table.freeze({
		table.freeze({
			id = "lane.main",
			totalDistance = 10,
			points = table.freeze({
				table.freeze({
					kind = "EnemySpawn",
					cframe = CFrame.new(0, 0, 0),
					position = Vector3.new(0, 0, 0),
					distance = 0,
				}),
				table.freeze({
					kind = "DefenderBase",
					cframe = CFrame.new(10, 0, 0),
					position = Vector3.new(10, 0, 0),
					distance = 10,
				}),
			}),
		}),
	}),
	placementZones = table.freeze({}),
	noPlacementZones = table.freeze({}),
	cameraAnchors = table.freeze({}),
	playerSpawns = table.freeze({}),
})

local newForTests = MatchLifecycleService.newForTests
if newForTests == nil then
	error("[ATD_TEST][code=MATCH_LIFECYCLE_TEST_CONSTRUCTOR_MISSING]", 0)
end

local function deterministicRuntime(startTime: number): DeterministicRuntime
	local runtime = {
		now = startTime,
		handles = {},
		cancelCount = 0,
		sent = {},
	} :: any
	runtime.clock = function(): unknown
		return runtime.now
	end
	runtime.schedule = function(delaySeconds: number, callback: MatchLifecycleService.TimerCallback): unknown
		local handle: TimerHandle = {
			delaySeconds = delaySeconds,
			callback = callback,
			cancelled = false,
		}
		table.insert(runtime.handles, handle)
		return handle
	end
	runtime.cancel = function(handleValue: unknown)
		local handle = handleValue :: TimerHandle
		if not handle.cancelled then
			handle.cancelled = true
			runtime.cancelCount += 1
		end
	end
	runtime.snapshotSender = function(recipient: unknown, snapshot: MatchLifecycleService.MatchSnapshot): boolean
		table.insert(runtime.sent, {
			recipient = recipient,
			snapshot = snapshot,
		})
		return true
	end
	return runtime :: DeterministicRuntime
end

local function fakeLoader(loadResult: unknown, cleanupResult: unknown): FakeLoader
	local loader = {
		loadCount = 0,
		cleanupCount = 0,
		snapshotOverride = nil,
		lastMapId = nil,
		loadResult = loadResult,
		cleanupResult = cleanupResult,
		loadCallback = nil,
		cleanupCallback = nil,
	} :: any
	function loader.load(self: FakeLoader, mapId: unknown): unknown
		self.loadCount += 1
		self.lastMapId = mapId
		local callback = self.loadCallback
		if callback ~= nil then
			callback()
		end
		return self.loadResult
	end
	function loader.cleanup(self: FakeLoader): unknown
		self.cleanupCount += 1
		local callback = self.cleanupCallback
		if callback ~= nil then
			callback()
		end
		return self.cleanupResult
	end
	return loader :: FakeLoader
end

local function fakePlayerSource(existing: { FakePlayer }?): FakePlayerSource
	local source = {
		existing = existing or {},
		addedListener = nil,
		removingListener = nil,
		order = {},
		disconnectOrder = {},
	} :: any
	function source.getPlayers(self: FakePlayerSource): unknown
		table.insert(self.order, "get-players")
		local copied = {}
		for _, player in self.existing do
			table.insert(copied, player)
		end
		return copied
	end
	function source.getUserId(_self: FakePlayerSource, connection: unknown): unknown
		if type(connection) ~= "table" then
			return nil
		end
		return (connection :: any).userId
	end
	function source.connectAdded(self: FakePlayerSource, listener: MatchLifecycleService.PlayerListener): unknown
		table.insert(self.order, "connect-added")
		self.addedListener = listener
		return RobloxAdapter.createConnection(function()
			table.insert(self.disconnectOrder, "added")
		end)
	end
	function source.connectRemoving(self: FakePlayerSource, listener: MatchLifecycleService.PlayerListener): unknown
		table.insert(self.order, "connect-removing")
		self.removingListener = listener
		return RobloxAdapter.createConnection(function()
			table.insert(self.disconnectOrder, "removing")
		end)
	end
	return source :: FakePlayerSource
end

local function newRoster(): ParticipantRoster.Roster
	local result = ParticipantRoster.new()
	if not result.ok then
		error("[ATD_TEST][code=ROSTER_CREATION_FAILED]", 0)
	end
	return result.value
end

local function newService(
	loader: FakeLoader,
	createStateMachine: ((unknown) -> unknown)?,
	roster: ParticipantRoster.Roster?,
	playerSource: FakePlayerSource?,
	runtimeOverrides: RuntimeOverrides?
): MatchLifecycleService.Service
	local dependencies = {
		mapLoader = loader,
		generateMatchId = function()
			return MATCH_ID
		end,
		createStateMachine = createStateMachine,
		roster = roster or newRoster(),
		playerSource = playerSource or fakePlayerSource(),
	} :: any
	if runtimeOverrides ~= nil then
		dependencies.clock = runtimeOverrides.clock
		dependencies.schedule = runtimeOverrides.schedule
		dependencies.cancel = runtimeOverrides.cancel
		dependencies.snapshotSender = runtimeOverrides.snapshotSender
	end
	return (newForTests :: MatchLifecycleService.TestConstructor)(logger, dependencies)
end

local function captureError(assertions: Assertions, callback: () -> ()): string
	local succeeded, value = pcall(callback)
	assertions.isFalse(succeeded)
	assertions.equal(type(value), "string")
	return if type(value) == "string" then value else ""
end

local function assertDetachedAndFrozen(assertions: Assertions, value: unknown, seen: { [any]: boolean }?)
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
		assertDetachedAndFrozen(assertions, key, visited)
		assertDetachedAndFrozen(assertions, child, visited)
	end
end

local function invoke(method: (() -> ())?)
	if method == nil then
		error("[ATD_TEST][code=LIFECYCLE_METHOD_MISSING]", 0)
	end
	method()
end

local function successSnapshot(
	assertions: Assertions,
	service: MatchLifecycleService.Service
): MatchLifecycleService.MatchSnapshot
	local result = service:getSnapshot()
	assertions.isTrue(result.ok)
	if not result.ok then
		error("[ATD_TEST][code=EXPECTED_MATCH_SNAPSHOT]", 0)
	end
	return result.value
end

type DefeatTestEnvironment = {
	service: MatchLifecycleService.Service?,
	machine: MatchStateMachine.StateMachine?,
	commitMode: "success" | "failure" | "throw" | "yield" | "commit-then-throw" | "commit-then-yield",
	publishMode: "success" | "failure" | "throw" | "yield" | "malformed" | "budget" | "reenter" | "shutdown",
	publishCount: number,
	publishedSnapshots: { MatchLifecycleService.MatchSnapshot },
	readRecipients: (() -> unknown)?,
	reentryResult: unknown?,
	reentryToken: MatchLifecycleService.BaseDefeatToken?,
	cleanupCount: number,
}

local function newWaveActiveDefeatService(
	assertions: Assertions
): (MatchLifecycleService.Service, DefeatTestEnvironment)
	local environment: DefeatTestEnvironment = {
		service = nil,
		machine = nil,
		commitMode = "success",
		publishMode = "success",
		publishCount = 0,
		publishedSnapshots = {},
		readRecipients = nil,
		reentryResult = nil,
		reentryToken = nil,
		cleanupCount = 0,
	}

	local function createMachine(matchId: unknown): unknown
		local created = MatchStateMachine.new(matchId)
		if not created.ok then
			return created
		end
		local real = created.value
		environment.machine = real
		local adapter = {} :: any
		function adapter.getSnapshot(_self: unknown): unknown
			if environment.snapshotOverride ~= nil then
				return Result.ok(environment.snapshotOverride)
			end
			return real:getSnapshot()
		end
		function adapter.beginTransition(_self: unknown, target: unknown, revision: unknown): unknown
			return real:beginTransition(target, revision)
		end
		function adapter.commitTransition(_self: unknown, token: unknown): unknown
			if environment.commitMode == "failure" then
				return Result.err({ code = PRIVATE_SENTINEL })
			elseif environment.commitMode == "throw" then
				error(PRIVATE_SENTINEL, 0)
			elseif environment.commitMode == "yield" then
				coroutine.yield()
			elseif environment.commitMode == "commit-then-throw" then
				real:commitTransition(token)
				error(PRIVATE_SENTINEL, 0)
			elseif environment.commitMode == "commit-then-yield" then
				real:commitTransition(token)
				coroutine.yield()
			end
			return real:commitTransition(token)
		end
		function adapter.rollbackTransition(_self: unknown, token: unknown): unknown
			return real:rollbackTransition(token)
		end
		function adapter.touch(_self: unknown, revision: unknown): unknown
			return real:touch(revision)
		end
		function adapter.cleanup(_self: unknown): unknown
			return real:cleanup()
		end
		return Result.ok(adapter)
	end

	local function createBroadcaster(dependenciesValue: unknown): unknown
		local dependencies = dependenciesValue :: any
		environment.readRecipients = dependencies.getRecipients
		local adapter = {} :: any
		function adapter.publish(_self: unknown, snapshot: unknown): unknown
			environment.publishCount += 1
			if environment.publishMode == "reenter" then
				local service = environment.service :: MatchLifecycleService.Service
				environment.reentryResult = service:commitBaseDefeat(environment.reentryToken)
			elseif environment.publishMode == "shutdown" then
				invoke((environment.service :: MatchLifecycleService.Service):getServiceDefinition().shutdown)
			elseif environment.publishMode == "failure" then
				return Result.err({ code = PRIVATE_SENTINEL })
			elseif environment.publishMode == "throw" then
				error(PRIVATE_SENTINEL, 0)
			elseif environment.publishMode == "yield" then
				coroutine.yield()
			elseif environment.publishMode == "malformed" then
				return Result.ok(table.freeze({ kind = "Sent", extra = PRIVATE_SENTINEL }))
			elseif environment.publishMode == "budget" then
				return Result.ok(table.freeze({ kind = "BudgetExhausted" }))
			end
			if environment.publishMode == "success" then
				local recipientsRead, recipients = pcall(dependencies.getRecipients)
				if not recipientsRead or type(recipients) ~= "table" then
					return Result.err({ code = PRIVATE_SENTINEL })
				end
			end
			table.insert(environment.publishedSnapshots, snapshot :: MatchLifecycleService.MatchSnapshot)
			return Result.ok(table.freeze({ kind = "Sent" }))
		end
		function adapter.cleanup(_self: unknown): unknown
			environment.cleanupCount += 1
			return Result.ok(true)
		end
		return Result.ok(adapter)
	end

	local service = (newForTests :: MatchLifecycleService.TestConstructor)(
		logger,
		{
			mapLoader = fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true)),
			generateMatchId = function()
				return MATCH_ID
			end,
			createStateMachine = createMachine,
			roster = newRoster(),
			playerSource = fakePlayerSource(),
			createSnapshotBroadcaster = createBroadcaster,
		} :: any
	)
	environment.service = service
	local definition = service:getServiceDefinition()
	invoke(definition.initialize)
	invoke(definition.start)

	local machine = environment.machine :: MatchStateMachine.StateMachine
	local ready = machine:getSnapshot()
	assertions.isTrue(ready.ok)
	if not ready.ok then
		error("[ATD_TEST][code=DEFEAT_READY_STATE_MISSING]", 0)
	end
	local preWave = machine:beginTransition("PreWave", ready.value.revision)
	assertions.isTrue(preWave.ok)
	if not preWave.ok then
		error("[ATD_TEST][code=DEFEAT_PREWAVE_BEGIN_FAILED]", 0)
	end
	assertions.isTrue(machine:commitTransition(preWave.value).ok)
	local beforeWave = machine:getSnapshot()
	assertions.isTrue(beforeWave.ok)
	if not beforeWave.ok then
		error("[ATD_TEST][code=DEFEAT_PREWAVE_STATE_MISSING]", 0)
	end
	local wave = machine:beginTransition("WaveActive", beforeWave.value.revision)
	assertions.isTrue(wave.ok)
	if not wave.ok then
		error("[ATD_TEST][code=DEFEAT_WAVE_BEGIN_FAILED]", 0)
	end
	assertions.isTrue(machine:commitTransition(wave.value).ok)
	return service, environment
end

type StudioTestMode = "success" | "false" | "failure" | "throw" | "yield" | "malformed" | "commit-then-throw"

type StudioPublishMode = "success" | "failure" | "throw" | "yield" | "malformed" | "budget" | "reenter" | "shutdown"

type StudioTestEnvironment = {
	service: MatchLifecycleService.Service?,
	machine: MatchStateMachine.StateMachine?,
	faultsEnabled: boolean,
	isStudioMode: StudioTestMode,
	snapshotMode: StudioTestMode,
	beginMode: StudioTestMode,
	commitMode: StudioTestMode,
	publishMode: StudioPublishMode,
	publishCount: number,
	publishedSnapshots: { MatchLifecycleService.MatchSnapshot },
	reentryResult: unknown?,
	cleanupCount: number,
}

local function studioFailure(mode: StudioTestMode): unknown
	if mode == "failure" then
		return Result.err(table.freeze({ code = PRIVATE_SENTINEL }))
	elseif mode == "throw" then
		error(PRIVATE_SENTINEL, 0)
	elseif mode == "yield" then
		coroutine.yield()
	elseif mode == "malformed" then
		return table.freeze({ ok = true, value = PRIVATE_SENTINEL })
	end
	return nil
end

local function advanceMachine(
	assertions: Assertions,
	machine: MatchStateMachine.StateMachine,
	targetState: MatchStateMachine.MatchState
)
	local before = machine:getSnapshot()
	assertions.isTrue(before.ok)
	if not before.ok then
		error("[ATD_TEST][code=STUDIO_STATE_SNAPSHOT_MISSING]", 0)
	end
	local began = machine:beginTransition(targetState, before.value.revision)
	assertions.isTrue(began.ok)
	if not began.ok then
		error("[ATD_TEST][code=STUDIO_STATE_BEGIN_FAILED]", 0)
	end
	assertions.isTrue(machine:commitTransition(began.value).ok)
end

local function newStudioEvidenceService(
	assertions: Assertions,
	advanceToPreWave: boolean?
): (MatchLifecycleService.Service, StudioTestEnvironment)
	local environment: StudioTestEnvironment = {
		service = nil,
		machine = nil,
		faultsEnabled = false,
		isStudioMode = "success",
		snapshotMode = "success",
		beginMode = "success",
		commitMode = "success",
		publishMode = "success",
		publishCount = 0,
		publishedSnapshots = {},
		reentryResult = nil,
		cleanupCount = 0,
	}

	local function createMachine(matchId: unknown): unknown
		local created = MatchStateMachine.new(matchId)
		if not created.ok then
			return created
		end
		local real = created.value
		environment.machine = real
		local adapter = {} :: any
		function adapter.getSnapshot(_self: unknown): unknown
			if environment.faultsEnabled and environment.snapshotMode ~= "success" then
				return studioFailure(environment.snapshotMode)
			end
			return real:getSnapshot()
		end
		function adapter.beginTransition(_self: unknown, target: unknown, revision: unknown): unknown
			if environment.faultsEnabled and environment.beginMode ~= "success" then
				return studioFailure(environment.beginMode)
			end
			return real:beginTransition(target, revision)
		end
		function adapter.commitTransition(_self: unknown, token: unknown): unknown
			if environment.faultsEnabled and environment.commitMode ~= "success" then
				if environment.commitMode == "commit-then-throw" then
					real:commitTransition(token)
					error(PRIVATE_SENTINEL, 0)
				elseif environment.commitMode == "malformed" then
					real:commitTransition(token)
					return table.freeze({
						ok = true,
						value = table.freeze({
							matchId = MATCH_ID,
							revision = 1,
							state = "Loading",
						}),
					})
				end
				return studioFailure(environment.commitMode)
			end
			return real:commitTransition(token)
		end
		function adapter.rollbackTransition(_self: unknown, token: unknown): unknown
			return real:rollbackTransition(token)
		end
		function adapter.touch(_self: unknown, revision: unknown): unknown
			return real:touch(revision)
		end
		function adapter.cleanup(_self: unknown): unknown
			return real:cleanup()
		end
		return Result.ok(adapter)
	end

	local function createBroadcaster(_dependencies: unknown): unknown
		local adapter = {} :: any
		function adapter.publish(_self: unknown, snapshot: unknown): unknown
			environment.publishCount += 1
			if environment.publishMode == "failure" then
				return Result.err(table.freeze({ code = PRIVATE_SENTINEL }))
			elseif environment.publishMode == "throw" then
				error(PRIVATE_SENTINEL, 0)
			elseif environment.publishMode == "yield" then
				coroutine.yield()
			elseif environment.publishMode == "malformed" then
				return Result.ok(table.freeze({ kind = "Sent", extra = PRIVATE_SENTINEL }))
			elseif environment.publishMode == "budget" then
				return Result.ok(table.freeze({ kind = "BudgetExhausted" }))
			elseif environment.publishMode == "reenter" then
				environment.reentryResult = (environment.service :: MatchLifecycleService.Service):activateStudioWaveForEvidence()
			elseif environment.publishMode == "shutdown" then
				invoke((environment.service :: MatchLifecycleService.Service):getServiceDefinition().shutdown)
			end
			table.insert(environment.publishedSnapshots, snapshot :: MatchLifecycleService.MatchSnapshot)
			return Result.ok(table.freeze({ kind = "Sent" }))
		end
		function adapter.cleanup(_self: unknown): unknown
			environment.cleanupCount += 1
			return Result.ok(true)
		end
		return Result.ok(adapter)
	end

	local function isStudio(): unknown
		if environment.isStudioMode == "success" then
			return true
		elseif environment.isStudioMode == "false" then
			return false
		end
		return studioFailure(environment.isStudioMode)
	end

	local service = (newForTests :: MatchLifecycleService.TestConstructor)(
		logger,
		{
			mapLoader = fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true)),
			generateMatchId = function()
				return MATCH_ID
			end,
			createStateMachine = createMachine,
			roster = newRoster(),
			playerSource = fakePlayerSource(),
			createSnapshotBroadcaster = createBroadcaster,
			isStudio = isStudio,
		} :: any
	)
	environment.service = service
	local definition = service:getServiceDefinition()
	invoke(definition.initialize)
	invoke(definition.start)
	if advanceToPreWave ~= false then
		advanceMachine(assertions, environment.machine :: MatchStateMachine.StateMachine, "PreWave")
	end
	environment.faultsEnabled = true
	return service, environment
end

return TestHarness.suite("match lifecycle service", {
	TestHarness.case("loads the fixed map and follows lifecycle dependency order", function(assertions)
		local loader = fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true))
		local service = newService(loader, nil)
		local definition = service:getServiceDefinition()

		assertions.equal(service:getLifecycleState(), "Constructed")
		local beforeInitialize = service:getRuntimeMapSnapshot()
		assertions.isFalse(beforeInitialize.ok)
		assertions.isTrue(table.isfrozen(beforeInitialize))
		if not beforeInitialize.ok then
			assertions.isTrue(table.isfrozen(beforeInitialize.error))
			assertions.equal(beforeInitialize.error.code, "UNAVAILABLE")
			assertions.equal(beforeInitialize.error.operation, "getRuntimeMapSnapshot")
		end
		assertions.equal(definition.name, "MatchLifecycle")
		assertions.isTrue(table.isfrozen(definition))
		assertions.isTrue(table.isfrozen(definition.dependencies :: { string }))
		assertions.equal(table.concat(definition.dependencies :: { string }, ","), "NetworkRegistry")
		invoke(definition.initialize)
		assertions.equal(service:getLifecycleState(), "Initialized")
		assertions.equal(loader.loadCount, 1)
		assertions.equal(loader.lastMapId, MatchLifecycleService.FIXED_MAP_ID)
		local runtimeMap = service:getRuntimeMapSnapshot()
		assertions.isTrue(runtimeMap.ok)
		if runtimeMap.ok then
			assertions.equal(runtimeMap.value, RUNTIME_MAP_SNAPSHOT)
			assertDetachedAndFrozen(assertions, runtimeMap.value)
		end
		local loading = successSnapshot(assertions, service)
		local loadingAgain = successSnapshot(assertions, service)
		assertions.equal(loading.matchId, MATCH_ID)
		assertions.equal(loading.revision, 1)
		assertions.equal(loading.state, "Loading")
		assertions.notEqual(loading, loadingAgain)
		assertions.isTrue(table.isfrozen(loading))
		invoke(definition.start)
		assertions.equal(service:getLifecycleState(), "Started")
		local startedRuntimeMap = service:getRuntimeMapSnapshot()
		assertions.isTrue(startedRuntimeMap.ok)
		if startedRuntimeMap.ok then
			assertions.equal(startedRuntimeMap.value, RUNTIME_MAP_SNAPSHOT)
		end
		local readyCheck = successSnapshot(assertions, service)
		assertions.equal(readyCheck.revision, 2)
		assertions.equal(readyCheck.state, "ReadyCheck")
		invoke(definition.shutdown)
		invoke(definition.shutdown)
		assertions.equal(service:getLifecycleState(), "Shutdown")
		assertions.equal(loader.cleanupCount, 1)
		local runtimeMapAfterShutdown = service:getRuntimeMapSnapshot()
		assertions.isFalse(runtimeMapAfterShutdown.ok)
		assertions.isTrue(table.isfrozen(runtimeMapAfterShutdown))
		if not runtimeMapAfterShutdown.ok then
			assertions.isTrue(table.isfrozen(runtimeMapAfterShutdown.error))
			assertions.equal(runtimeMapAfterShutdown.error.code, "UNAVAILABLE")
			assertions.equal(runtimeMapAfterShutdown.error.operation, "getRuntimeMapSnapshot")
		end
		local afterShutdown = service:getSnapshot()
		assertions.isFalse(afterShutdown.ok)
		if not afterShutdown.ok then
			assertions.equal(afterShutdown.error.code, "UNAVAILABLE")
		end
	end),

	TestHarness.case("integrates the exact deadline revision window and coalesced final snapshot", function(assertions)
		local runtime = deterministicRuntime(100)
		local lower = { userId = 10 }
		local higher = { userId = 20 }
		local source = fakePlayerSource({ higher, lower })
		local service =
			newService(fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true)), nil, nil, source, runtime)
		local definition = service:getServiceDefinition()
		invoke(definition.initialize)
		invoke(definition.start)

		local initial = successSnapshot(assertions, service)
		assertions.equal(initial.state, "ReadyCheck")
		assertions.equal(initial.revision, 4)
		assertions.equal(initial.deadlineServerTime, 145)
		assertions.equal(#runtime.handles, 1)
		assertions.equal(runtime.handles[1].delaySeconds, 45)
		assertions.equal(#runtime.sent, 2)
		assertions.equal(runtime.sent[1].recipient, lower)
		assertions.equal(runtime.sent[2].recipient, higher)
		assertions.equal(runtime.sent[1].snapshot.revision, 4)

		local stale = service:submitReady(lower, MATCH_ID, initial.revision - 1)
		assertions.isFalse(stale.ok)
		if not stale.ok then
			assertions.equal(stale.error.code, "STALE_REQUEST")
		end
		local wrongMatch = service:submitReady(lower, "match:other-service-test", initial.revision)
		assertions.isFalse(wrongMatch.ok)
		if not wrongMatch.ok then
			assertions.equal(wrongMatch.error.code, "STALE_REQUEST")
		end

		local first = service:submitReady(higher, MATCH_ID, initial.revision)
		assertions.isTrue(first.ok)
		if not first.ok then
			error("[ATD_TEST][code=FIRST_READY_REJECTED]", 0)
		end
		assertions.equal(first.value.revision, 5)
		assertions.equal(first.value.state, "ReadyCheck")
		local duplicate = service:submitReady(higher, MATCH_ID, initial.revision)
		assertions.isFalse(duplicate.ok)
		if not duplicate.ok then
			assertions.equal(duplicate.error.code, "DUPLICATE_REQUEST")
		end

		local final = service:submitReady(lower, MATCH_ID, initial.revision)
		assertions.isTrue(final.ok)
		if not final.ok then
			error("[ATD_TEST][code=SECOND_READY_REJECTED]", 0)
		end
		assertions.equal(final.value.revision, 7)
		assertions.equal(final.value.state, "PreWave")
		assertions.isNil(final.value.deadlineServerTime)
		assertions.isTrue(runtime.handles[1].cancelled)
		assertions.equal(#runtime.handles, 2)
		assertions.equal(runtime.handles[2].delaySeconds, 0.1)

		runtime.now = 100.2
		runtime.handles[2].callback()
		assertions.equal(#runtime.sent, 4)
		assertions.equal(runtime.sent[3].recipient, lower)
		assertions.equal(runtime.sent[4].recipient, higher)
		assertions.equal(runtime.sent[3].snapshot.revision, 7)
		assertions.equal(runtime.sent[4].snapshot.state, "PreWave")

		invoke(definition.shutdown)
		local sentBeforeStaleTimer = #runtime.sent
		runtime.now = 145
		runtime.handles[1].callback()
		assertions.equal(#runtime.sent, sentBeforeStaleTimer)
		assertions.equal(runtime.cancelCount, 1)
	end),

	TestHarness.case("applies mixed and zero-ready timeout policy at the exact boundary", function(assertions)
		local readyPlayer = { userId = 1 }
		local returnedPlayer = { userId = 2 }
		local mixedSource = fakePlayerSource({ readyPlayer, returnedPlayer })
		local mixedRuntime = deterministicRuntime(200)
		local mixedService = newService(
			fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true)),
			nil,
			nil,
			mixedSource,
			mixedRuntime
		)
		local mixedDefinition = mixedService:getServiceDefinition()
		invoke(mixedDefinition.initialize)
		invoke(mixedDefinition.start)
		local entry = successSnapshot(assertions, mixedService)
		assertions.equal(entry.deadlineServerTime, 245)
		local readyResult = mixedService:submitReady(readyPlayer, MATCH_ID, entry.revision)
		assertions.isTrue(readyResult.ok)

		mixedRuntime.now = 245
		mixedRuntime.handles[1].callback()
		local mixedFinal = successSnapshot(assertions, mixedService)
		assertions.equal(mixedFinal.state, "PreWave")
		assertions.equal(mixedFinal.revision, 7)
		assertions.isTrue(mixedFinal.participants[1].ready)
		assertions.equal(mixedFinal.participants[2].state, "Returned")
		assertions.isFalse(mixedFinal.participants[2].ready)
		assertions.isNil(mixedFinal.deadlineServerTime)
		assertions.equal(#mixedRuntime.sent, 4)

		local removing = mixedSource.removingListener :: MatchLifecycleService.PlayerListener
		removing(returnedPlayer)
		local returnedReconnect = { userId = 2 }
		mixedSource.existing = { readyPlayer, returnedReconnect }
		local added = mixedSource.addedListener :: MatchLifecycleService.PlayerListener
		added(returnedReconnect)
		local afterReconnect = successSnapshot(assertions, mixedService)
		assertions.equal(afterReconnect.revision, mixedFinal.revision)
		assertions.equal(afterReconnect.participants[2].state, "Returned")
		invoke(mixedDefinition.shutdown)

		local zeroRuntime = deterministicRuntime(300)
		local zeroSource = fakePlayerSource({ { userId = 11 }, { userId = 12 } })
		local zeroService =
			newService(fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true)), nil, nil, zeroSource, zeroRuntime)
		local zeroDefinition = zeroService:getServiceDefinition()
		invoke(zeroDefinition.initialize)
		invoke(zeroDefinition.start)
		zeroRuntime.now = 345
		zeroRuntime.handles[1].callback()
		local zeroFinal = successSnapshot(assertions, zeroService)
		assertions.equal(zeroFinal.state, "Closing")
		assertions.equal(zeroFinal.revision, 5)
		assertions.isNil(zeroFinal.deadlineServerTime)
		assertions.equal(zeroFinal.participants[1].state, "Active")
		assertions.equal(zeroFinal.participants[2].state, "Active")
		invoke(zeroDefinition.shutdown)
	end),

	TestHarness.case(
		"recalculates readiness on disconnect and rejects stale removal after reconnect",
		function(assertions)
			local first = { userId = 1 }
			local second = { userId = 2 }
			local departing = { userId = 3 }
			local source = fakePlayerSource({ first, second, departing })
			local runtime = deterministicRuntime(400)
			local service =
				newService(fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true)), nil, nil, source, runtime)
			local definition = service:getServiceDefinition()
			invoke(definition.initialize)
			invoke(definition.start)
			local entry = successSnapshot(assertions, service)
			assertions.equal(entry.revision, 5)
			assertions.isTrue(service:submitReady(first, MATCH_ID, entry.revision).ok)
			assertions.isTrue(service:submitReady(second, MATCH_ID, entry.revision).ok)

			source.existing = { first, second }
			local removing = source.removingListener :: MatchLifecycleService.PlayerListener
			removing(departing)
			local afterDisconnect = successSnapshot(assertions, service)
			assertions.equal(afterDisconnect.state, "PreWave")
			assertions.equal(afterDisconnect.revision, 9)
			assertions.equal(afterDisconnect.participants[3].state, "Disconnected")

			local reconnected = { userId = 3 }
			source.existing = { first, second, reconnected }
			local added = source.addedListener :: MatchLifecycleService.PlayerListener
			added(reconnected)
			local spectator = successSnapshot(assertions, service)
			assertions.equal(spectator.revision, 10)
			assertions.equal(spectator.participants[3].state, "Spectator")
			removing(departing)
			assertions.equal(successSnapshot(assertions, service).revision, spectator.revision)
			invoke(definition.shutdown)
		end
	),

	TestHarness.case("cleanup invalidates the ready timer and every post-clean callback", function(assertions)
		local runtime = deterministicRuntime(500)
		local player = { userId = 1 }
		local source = fakePlayerSource({ player })
		local service =
			newService(fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true)), nil, nil, source, runtime)
		local definition = service:getServiceDefinition()
		invoke(definition.initialize)
		invoke(definition.start)
		assertions.equal(#runtime.handles, 1)
		assertions.equal(#runtime.sent, 1)
		local timer = runtime.handles[1]
		invoke(definition.shutdown)
		assertions.isTrue(timer.cancelled)
		assertions.equal(runtime.cancelCount, 1)
		local sentBeforeCallback = #runtime.sent
		runtime.now = 545
		timer.callback()
		assertions.equal(#runtime.sent, sentBeforeCallback)
		assertions.isFalse(service:submitReady(player, MATCH_ID, 3).ok)
		assertions.isFalse(service:getSnapshot().ok)
	end),

	TestHarness.case("fails closed to Closing for failed malformed and throwing map loads", function(assertions)
		local throwingLoader = fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true))
		throwingLoader.loadCallback = function()
			error(PRIVATE_SENTINEL, 0)
		end
		local loaders = {
			fakeLoader(Result.err({ code = PRIVATE_SENTINEL }), Result.ok(true)),
			fakeLoader(Result.ok(true), Result.ok(true)),
			fakeLoader(
				Result.ok(table.freeze({
					mapId = MatchLifecycleService.FIXED_MAP_ID,
					lanes = table.freeze({ { id = "mutable-nested" } }),
				})),
				Result.ok(true)
			),
			throwingLoader,
		}

		for _, loader in loaders do
			local service = newService(loader, nil)
			local definition = service:getServiceDefinition()
			invoke(definition.initialize)
			local runtimeMap = service:getRuntimeMapSnapshot()
			assertions.isFalse(runtimeMap.ok)
			if not runtimeMap.ok then
				assertions.equal(runtimeMap.error.code, "UNAVAILABLE")
			end
			local closing = successSnapshot(assertions, service)
			assertions.equal(closing.state, "Closing")
			assertions.equal(closing.revision, 2)
			invoke(definition.start)
			local stillClosing = successSnapshot(assertions, service)
			assertions.equal(stillClosing.state, "Closing")
			assertions.equal(stillClosing.revision, 2)
			invoke(definition.shutdown)
			assertions.equal(loader.loadCount, 1)
			assertions.equal(loader.cleanupCount, 1)
		end
	end),

	TestHarness.case("rejects lifecycle reentry without repeating map work", function(assertions)
		local loader = fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true))
		local service = newService(loader, nil)
		local definition = service:getServiceDefinition()
		local reentryFailure = ""
		loader.loadCallback = function()
			reentryFailure = captureError(assertions, function()
				invoke(definition.initialize)
			end)
		end

		local startBeforeInitialize = captureError(assertions, function()
			invoke(definition.start)
		end)
		assertions.contains(startBeforeInitialize, "[code=INVALID_STATE]")
		invoke(definition.initialize)
		assertions.contains(reentryFailure, "[code=INVALID_STATE]")
		local repeatedInitialize = captureError(assertions, function()
			invoke(definition.initialize)
		end)
		assertions.contains(repeatedInitialize, "[code=INVALID_STATE]")
		invoke(definition.start)
		local repeatedStart = captureError(assertions, function()
			invoke(definition.start)
		end)
		assertions.contains(repeatedStart, "[code=INVALID_STATE]")
		assertions.equal(loader.loadCount, 1)
		invoke(definition.shutdown)
	end),

	TestHarness.case("runs after NetworkRegistry and cleans before it", function(assertions)
		local order = {}
		local loader = fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true))
		loader.loadCallback = function()
			table.insert(order, "match-initialize")
		end
		loader.cleanupCallback = function()
			table.insert(order, "match-cleanup")
		end

		local function createTrackingMachine(matchId: unknown): unknown
			local created = MatchStateMachine.new(matchId)
			if not created.ok then
				return created
			end
			local real = created.value
			local adapter = {} :: any
			function adapter.getSnapshot(_self: unknown): unknown
				return real:getSnapshot()
			end
			function adapter.beginTransition(_self: unknown, target: unknown, revision: unknown): unknown
				table.insert(order, `match-{target :: any}`)
				return real:beginTransition(target, revision)
			end
			function adapter.commitTransition(_self: unknown, token: unknown): unknown
				return real:commitTransition(token)
			end
			function adapter.rollbackTransition(_self: unknown, token: unknown): unknown
				return real:rollbackTransition(token)
			end
			function adapter.touch(_self: unknown, revision: unknown): unknown
				return real:touch(revision)
			end
			function adapter.cleanup(_self: unknown): unknown
				return real:cleanup()
			end
			return Result.ok(adapter)
		end

		local service = newService(loader, createTrackingMachine)
		local runner = ServiceLifecycle.new(logger)
		runner:register(table.freeze({
			name = "NetworkRegistry",
			initialize = function()
				table.insert(order, "network-initialize")
			end,
			start = function()
				table.insert(order, "network-start")
			end,
			shutdown = function()
				table.insert(order, "network-shutdown")
			end,
		}))
		runner:register(service:getServiceDefinition())
		runner:initialize()
		assertions.equal(table.concat(runner:getServiceOrder(), ","), "NetworkRegistry,MatchLifecycle")
		runner:start()
		runner:shutdown()

		assertions.equal(
			table.concat(order, ","),
			"network-initialize,match-initialize,network-start,match-ReadyCheck,match-Closing,match-cleanup,network-shutdown"
		)
		assertions.equal(runner:getState(), "Shutdown")
	end),

	TestHarness.case(
		"tracks sorted existing players and revisions every public roster mutation once",
		function(assertions)
			local forty = { userId = 40 }
			local minusSeven = { userId = -7 }
			local ten = { userId = 10 }
			local source = fakePlayerSource({ forty, minusSeven, ten })
			local roster = newRoster()
			local loader = fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true))
			local service = newService(loader, nil, roster, source)
			local definition = service:getServiceDefinition()

			invoke(definition.initialize)
			assertions.equal(table.concat(source.order, ","), "connect-added,connect-removing,get-players")
			local loading = successSnapshot(assertions, service)
			assertions.equal(loading.state, "Loading")
			assertions.equal(loading.revision, 4)
			assertions.equal(#loading.participants, 3)
			assertions.equal(loading.participants[1].userId, -7)
			assertions.equal(loading.participants[2].userId, 10)
			assertions.equal(loading.participants[3].userId, 40)
			assertions.isNil(loading.deadlineServerTime)
			assertions.isTrue(table.isfrozen(loading.participants))
			for _, participant in loading.participants do
				assertions.isTrue(table.isfrozen(participant))
			end

			invoke(definition.start)
			assertions.equal(successSnapshot(assertions, service).revision, 5)
			local addedListener = source.addedListener :: MatchLifecycleService.PlayerListener
			local removingListener = source.removingListener :: MatchLifecycleService.PlayerListener
			addedListener(forty)
			assertions.equal(successSnapshot(assertions, service).revision, 5)

			local twenty = { userId = 20 }
			addedListener(twenty)
			local added = successSnapshot(assertions, service)
			assertions.equal(added.revision, 6)
			assertions.equal(#added.participants, 4)
			assertions.equal(added.participants[3].userId, 20)

			removingListener(ten)
			local disconnected = successSnapshot(assertions, service)
			assertions.equal(disconnected.revision, 7)
			assertions.equal(disconnected.participants[2].state, "Disconnected")
			removingListener(ten)
			assertions.equal(successSnapshot(assertions, service).revision, 7)

			local tenReconnected = { userId = 10 }
			addedListener(tenReconnected)
			local reconnected = successSnapshot(assertions, service)
			assertions.equal(reconnected.revision, 8)
			assertions.equal(reconnected.participants[2].state, "Active")
			removingListener(ten)
			assertions.equal(successSnapshot(assertions, service).revision, 8)

			local outerMutation = pcall(function()
				(reconnected :: any).revision = 900
			end)
			local participantMutation = pcall(function()
				(reconnected.participants :: any)[1].userId = 900
			end)
			assertions.isFalse(outerMutation)
			assertions.isFalse(participantMutation)

			invoke(definition.shutdown)
			assertions.isTrue(roster:isCleaned())
			assertions.equal(table.concat(source.disconnectOrder, ","), "removing,added")
			addedListener({ userId = 99 })
			removingListener(tenReconnected)
			assertions.equal(table.concat(source.disconnectOrder, ","), "removing,added")
		end
	),

	TestHarness.case("keeps cap excess and duplicate callbacks revision neutral", function(assertions)
		local existing = {}
		for userId = 1, 5 do
			table.insert(existing, { userId = userId })
		end
		local source = fakePlayerSource(existing)
		local service = newService(fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true)), nil, nil, source)
		local definition = service:getServiceDefinition()
		invoke(definition.initialize)
		invoke(definition.start)
		local snapshot = successSnapshot(assertions, service)
		assertions.equal(#snapshot.participants, 4)
		assertions.equal(snapshot.revision, 6)

		local addedListener = source.addedListener :: MatchLifecycleService.PlayerListener
		addedListener({ userId = 6 })
		addedListener(existing[1])
		assertions.equal(successSnapshot(assertions, service).revision, 6)
		invoke(definition.shutdown)
	end),

	TestHarness.case("rolls back owned tracking when the initial player snapshot fails", function(assertions)
		local loader = fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true))
		local roster = newRoster()
		local source = fakePlayerSource()
		function source.getPlayers(_self: FakePlayerSource): unknown
			error(PRIVATE_SENTINEL, 0)
		end
		local service = newService(loader, nil, roster, source)
		local failure = captureError(assertions, function()
			invoke(service:getServiceDefinition().initialize)
		end)

		assertions.contains(failure, "[code=PLAYER_SNAPSHOT_FAILED]")
		assertions.isNil(string.find(failure, PRIVATE_SENTINEL, 1, true))
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.equal(loader.loadCount, 0)
		assertions.equal(loader.cleanupCount, 1)
		assertions.isTrue(roster:isCleaned())
		assertions.equal(table.concat(source.disconnectOrder, ","), "removing,added")
	end),

	TestHarness.case("rolls back a begun transition before cleaning initialization failure", function(assertions)
		local loader = fakeLoader(Result.err({ code = "LOAD_FAILED" }), Result.ok(true))
		local rollbackCount = 0
		local machineCleanupCount = 0
		local cleanupOrder = {}
		loader.cleanupCallback = function()
			table.insert(cleanupOrder, "map")
		end
		local function createFailingCommitMachine(matchId: unknown): unknown
			local created = MatchStateMachine.new(matchId)
			if not created.ok then
				return created
			end
			local real = created.value
			local adapter = {} :: any
			function adapter.getSnapshot(_self: unknown): unknown
				return real:getSnapshot()
			end
			function adapter.beginTransition(_self: unknown, target: unknown, revision: unknown): unknown
				return real:beginTransition(target, revision)
			end
			function adapter.commitTransition(_self: unknown, _token: unknown): unknown
				return Result.err({ code = "COMMIT_FAILED" })
			end
			function adapter.rollbackTransition(_self: unknown, token: unknown): unknown
				rollbackCount += 1
				return real:rollbackTransition(token)
			end
			function adapter.touch(_self: unknown, revision: unknown): unknown
				return real:touch(revision)
			end
			function adapter.cleanup(_self: unknown): unknown
				machineCleanupCount += 1
				table.insert(cleanupOrder, "machine")
				return real:cleanup()
			end
			return Result.ok(adapter)
		end

		local service = newService(loader, createFailingCommitMachine)
		local definition = service:getServiceDefinition()
		local failure = captureError(assertions, function()
			invoke(definition.initialize)
		end)
		assertions.contains(failure, "[code=TRANSITION_FAILED]")
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.equal(rollbackCount, 1)
		assertions.equal(machineCleanupCount, 1)
		assertions.equal(loader.cleanupCount, 1)
		assertions.equal(table.concat(cleanupOrder, ","), "machine,map")
		assertions.isNil(string.find(failure, PRIVATE_SENTINEL, 1, true))
	end),

	TestHarness.case("surfaces one privacy safe cached cleanup failure", function(assertions)
		local loader = fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.err({ private = PRIVATE_SENTINEL }))
		local service = newService(loader, nil)
		local definition = service:getServiceDefinition()
		invoke(definition.initialize)
		invoke(definition.start)

		local firstFailure = captureError(assertions, function()
			invoke(definition.shutdown)
		end)
		local repeatedFailure = captureError(assertions, function()
			invoke(definition.shutdown)
		end)
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.equal(loader.cleanupCount, 1)
		assertions.equal(repeatedFailure, firstFailure)
		assertions.contains(firstFailure, "[code=CLEANUP_FAILED]")
		assertions.isNil(string.find(firstFailure, PRIVATE_SENTINEL, 1, true))
	end),

	TestHarness.case("commits one authenticated base defeat and never republishes its token", function(assertions)
		local service, environment = newWaveActiveDefeatService(assertions)
		local wrongMatch = service:beginBaseDefeat("match:other-defeat-test")
		assertions.isFalse(wrongMatch.ok)
		if not wrongMatch.ok then
			assertions.equal(wrongMatch.error.code, "NOT_AUTHORIZED")
			assertions.equal(wrongMatch.error.operation, "beginBaseDefeat")
			assertDetachedAndFrozen(assertions, wrongMatch.error)
		end

		local before = successSnapshot(assertions, service)
		assertions.equal(before.state, "WaveActive")
		local began = service:beginBaseDefeat(MATCH_ID)
		assertions.isTrue(began.ok)
		if not began.ok then
			error("[ATD_TEST][code=BASE_DEFEAT_BEGIN_REJECTED]", 0)
		end
		assertDetachedAndFrozen(assertions, began.value)
		local secondClaim = service:beginBaseDefeat(MATCH_ID)
		assertions.isFalse(secondClaim.ok)
		if not secondClaim.ok then
			assertions.equal(secondClaim.error.code, "REENTRANT")
		end

		local publicationsBeforeCommit = environment.publishCount
		local committed = service:commitBaseDefeat(began.value)
		assertions.isTrue(committed.ok)
		if not committed.ok then
			error("[ATD_TEST][code=BASE_DEFEAT_COMMIT_REJECTED]", 0)
		end
		assertions.isTrue(committed.value.committed)
		assertions.isTrue(committed.value.published)
		assertions.equal(committed.value.snapshot.matchId, MATCH_ID)
		assertions.equal(committed.value.snapshot.state, "Results")
		assertions.equal(committed.value.snapshot.revision, before.revision + 1)
		assertDetachedAndFrozen(assertions, committed.value)
		assertions.equal(environment.publishCount, publicationsBeforeCommit + 1)
		local terminalRecipients = (environment.readRecipients :: () -> unknown)()
		assertions.equal(type(terminalRecipients), "table")
		assertions.isTrue(table.isfrozen(terminalRecipients :: any))

		local duplicate = service:commitBaseDefeat(began.value)
		assertions.isTrue(duplicate.ok)
		if duplicate.ok then
			assertions.equal(duplicate.value, committed.value)
		end
		assertions.equal(environment.publishCount, publicationsBeforeCommit + 1)
		local lateRollback = service:rollbackBaseDefeat(began.value)
		assertions.isFalse(lateRollback.ok)
		if not lateRollback.ok then
			assertions.equal(lateRollback.error.code, "INVALID_TOKEN")
		end
		assertions.equal(successSnapshot(assertions, service).state, "Results")
		invoke(service:getServiceDefinition().shutdown)
		assertions.equal(service:getLifecycleState(), "Shutdown")
	end),

	TestHarness.case("rolls back only a prepared base defeat and clears it during shutdown", function(assertions)
		local service, _environment = newWaveActiveDefeatService(assertions)
		local before = successSnapshot(assertions, service)
		local began = service:beginBaseDefeat(MATCH_ID)
		assertions.isTrue(began.ok)
		if not began.ok then
			error("[ATD_TEST][code=BASE_DEFEAT_BEGIN_REJECTED]", 0)
		end
		local rolledBack = service:rollbackBaseDefeat(began.value)
		assertions.isTrue(rolledBack.ok)
		if rolledBack.ok then
			assertions.isTrue(rolledBack.value)
		end
		local after = successSnapshot(assertions, service)
		assertions.equal(after.state, "WaveActive")
		assertions.equal(after.revision, before.revision)
		assertions.isFalse(service:rollbackBaseDefeat(began.value).ok)
		assertions.isFalse(service:commitBaseDefeat(began.value).ok)

		local replacement = service:beginBaseDefeat(MATCH_ID)
		assertions.isTrue(replacement.ok)
		if not replacement.ok then
			error("[ATD_TEST][code=BASE_DEFEAT_REPLACEMENT_REJECTED]", 0)
		end
		invoke(service:getServiceDefinition().shutdown)
		assertions.equal(service:getLifecycleState(), "Shutdown")
		local afterCleanup = service:commitBaseDefeat(replacement.value)
		assertions.isFalse(afterCleanup.ok)
		if not afterCleanup.ok then
			assertions.equal(afterCleanup.error.code, "UNAVAILABLE")
		end
	end),

	TestHarness.case("rejects base defeat outside the exact WaveActive identity", function(assertions)
		local service = newService(fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true)), nil)
		local beforeStart = service:beginBaseDefeat(MATCH_ID)
		assertions.isFalse(beforeStart.ok)
		if not beforeStart.ok then
			assertions.equal(beforeStart.error.code, "UNAVAILABLE")
		end
		local definition = service:getServiceDefinition()
		invoke(definition.initialize)
		invoke(definition.start)
		local readyCheck = service:beginBaseDefeat(MATCH_ID)
		assertions.isFalse(readyCheck.ok)
		if not readyCheck.ok then
			assertions.equal(readyCheck.error.code, "WRONG_STATE")
		end
		local hostile = service:beginBaseDefeat(0 / 0)
		assertions.isFalse(hostile.ok)
		if not hostile.ok then
			assertions.equal(hostile.error.code, "NOT_AUTHORIZED")
		end
		invoke(definition.shutdown)
	end),

	TestHarness.case("fails closed before claiming exhausted Results revision space", function(assertions)
		local service, environment = newWaveActiveDefeatService(assertions)
		environment.snapshotOverride = table.freeze({
			matchId = MATCH_ID,
			revision = Validation.MAX_SAFE_INTEGER,
			state = "WaveActive",
		})
		local exhausted = service:beginBaseDefeat(MATCH_ID)
		assertions.isFalse(exhausted.ok)
		if not exhausted.ok then
			assertions.equal(exhausted.error.code, "INTERNAL_ERROR")
			assertions.equal(exhausted.error.operation, "beginBaseDefeat")
		end
		assertions.isFalse(service:getSnapshot().ok)
		environment.snapshotOverride = nil
		invoke(service:getServiceDefinition().shutdown)
		assertions.equal(service:getLifecycleState(), "Shutdown")
	end),

	TestHarness.case("fails closed when the Results transition throws fails or yields", function(assertions)
		for _, mode in { "failure", "throw", "yield" } do
			local service, environment = newWaveActiveDefeatService(assertions)
			local began = service:beginBaseDefeat(MATCH_ID)
			assertions.isTrue(began.ok)
			if not began.ok then
				error("[ATD_TEST][code=BASE_DEFEAT_BEGIN_REJECTED]", 0)
			end
			environment.commitMode = mode :: any
			local committed = service:commitBaseDefeat(began.value)
			assertions.isFalse(committed.ok)
			if not committed.ok then
				assertions.equal(committed.error.code, "INTERNAL_ERROR")
				assertions.equal(committed.error.operation, "commitBaseDefeat")
			end
			local machineSnapshot = (environment.machine :: MatchStateMachine.StateMachine):getSnapshot()
			assertions.isTrue(machineSnapshot.ok)
			if machineSnapshot.ok then
				assertions.equal(machineSnapshot.value.state, "WaveActive")
			end
			assertions.isFalse(service:getSnapshot().ok)
			environment.commitMode = "success"
			invoke(service:getServiceDefinition().shutdown)
			assertions.equal(service:getLifecycleState(), "Shutdown")
		end
	end),

	TestHarness.case("preserves committed Results across publication and reentry faults", function(assertions)
		for _, mode in { "failure", "throw", "yield", "malformed", "budget", "reenter" } do
			local service, environment = newWaveActiveDefeatService(assertions)
			local began = service:beginBaseDefeat(MATCH_ID)
			assertions.isTrue(began.ok)
			if not began.ok then
				error("[ATD_TEST][code=BASE_DEFEAT_BEGIN_REJECTED]", 0)
			end
			environment.publishMode = mode :: any
			environment.reentryToken = began.value
			local publicationsBeforeCommit = environment.publishCount
			local committed = service:commitBaseDefeat(began.value)
			assertions.isTrue(committed.ok)
			if not committed.ok then
				error("[ATD_TEST][code=COMMITTED_RESULTS_LOST]", 0)
			end
			assertions.isTrue(committed.value.committed)
			assertions.isFalse(committed.value.published)
			assertions.equal(committed.value.snapshot.state, "Results")
			assertions.equal(environment.publishCount, publicationsBeforeCommit + 1)
			if mode == "reenter" then
				local reentry = environment.reentryResult :: any
				assertions.isFalse(reentry.ok)
				assertions.equal(reentry.error.code, "REENTRANT")
			end
			local duplicate = service:commitBaseDefeat(began.value)
			assertions.isTrue(duplicate.ok)
			if duplicate.ok then
				assertions.equal(duplicate.value, committed.value)
			end
			assertions.equal(environment.publishCount, publicationsBeforeCommit + 1)
			assertions.equal(successSnapshot(assertions, service).state, "Results")
			invoke(service:getServiceDefinition().shutdown)
		end
	end),

	TestHarness.case("preserves terminal truth when a commit faults after changing state", function(assertions)
		for _, mode in { "commit-then-throw", "commit-then-yield" } do
			local service, environment = newWaveActiveDefeatService(assertions)
			local began = service:beginBaseDefeat(MATCH_ID)
			assertions.isTrue(began.ok)
			if not began.ok then
				error("[ATD_TEST][code=BASE_DEFEAT_BEGIN_REJECTED]", 0)
			end
			environment.commitMode = mode :: any
			local publicationsBeforeCommit = environment.publishCount
			local committed = service:commitBaseDefeat(began.value)
			assertions.isTrue(committed.ok)
			if not committed.ok then
				error("[ATD_TEST][code=COMMITTED_RESULTS_LOST]", 0)
			end
			assertions.isTrue(committed.value.committed)
			assertions.isFalse(committed.value.published)
			assertions.equal(committed.value.snapshot.state, "Results")
			assertions.equal(environment.publishCount, publicationsBeforeCommit)
			assertions.equal(successSnapshot(assertions, service).state, "Results")
			environment.commitMode = "success"
			invoke(service:getServiceDefinition().shutdown)
		end
	end),

	TestHarness.case("defers synchronous shutdown through the committed publication boundary", function(assertions)
		local service, environment = newWaveActiveDefeatService(assertions)
		local began = service:beginBaseDefeat(MATCH_ID)
		assertions.isTrue(began.ok)
		if not began.ok then
			error("[ATD_TEST][code=BASE_DEFEAT_BEGIN_REJECTED]", 0)
		end
		environment.publishMode = "shutdown"
		local committed = service:commitBaseDefeat(began.value)
		assertions.isTrue(committed.ok)
		if not committed.ok then
			error("[ATD_TEST][code=COMMITTED_RESULTS_LOST]", 0)
		end
		assertions.isTrue(committed.value.committed)
		assertions.isTrue(committed.value.published)
		assertions.equal(committed.value.snapshot.state, "Results")
		assertions.equal(service:getLifecycleState(), "Shutdown")
		assertions.equal(environment.cleanupCount, 1)
		local lateCommit = service:commitBaseDefeat(began.value)
		assertions.isFalse(lateCommit.ok)
		if not lateCommit.ok then
			assertions.equal(lateCommit.error.code, "UNAVAILABLE")
		end
	end),

	TestHarness.case("rejects foreign defeat tokens without consuming either claim", function(assertions)
		local first, _firstEnvironment = newWaveActiveDefeatService(assertions)
		local second, _secondEnvironment = newWaveActiveDefeatService(assertions)
		local firstToken = first:beginBaseDefeat(MATCH_ID)
		local secondToken = second:beginBaseDefeat(MATCH_ID)
		assertions.isTrue(firstToken.ok)
		assertions.isTrue(secondToken.ok)
		if not firstToken.ok or not secondToken.ok then
			error("[ATD_TEST][code=BASE_DEFEAT_CLAIM_MISSING]", 0)
		end
		local foreign = second:commitBaseDefeat(firstToken.value)
		assertions.isFalse(foreign.ok)
		if not foreign.ok then
			assertions.equal(foreign.error.code, "INVALID_TOKEN")
		end
		assertions.isTrue(first:rollbackBaseDefeat(firstToken.value).ok)
		assertions.isTrue(second:rollbackBaseDefeat(secondToken.value).ok)
		invoke(first:getServiceDefinition().shutdown)
		invoke(second:getServiceDefinition().shutdown)
	end),

	TestHarness.case(
		"activates one exact Studio evidence wave and publishes its authoritative snapshot",
		function(assertions)
			local service, environment = newStudioEvidenceService(assertions)
			local before = (environment.machine :: MatchStateMachine.StateMachine):getSnapshot()
			assertions.isTrue(before.ok)
			if not before.ok then
				error("[ATD_TEST][code=STUDIO_PREWAVE_SNAPSHOT_MISSING]", 0)
			end
			assertions.equal(before.value.state, "PreWave")
			local publicationsBefore = environment.publishCount

			local activated = service:activateStudioWaveForEvidence()
			assertions.isTrue(activated.ok)
			if not activated.ok then
				error("[ATD_TEST][code=STUDIO_WAVE_ACTIVATION_FAILED]", 0)
			end
			assertions.equal(activated.value.matchId, MATCH_ID)
			assertions.equal(activated.value.revision, before.value.revision + 1)
			assertions.equal(activated.value.state, "WaveActive")
			assertions.isNil(activated.value.deadlineServerTime)
			assertDetachedAndFrozen(assertions, activated.value)
			assertions.equal(environment.publishCount, publicationsBefore + 1)
			assertions.equal(#environment.publishedSnapshots, publicationsBefore + 1)
			assertions.equal(environment.publishedSnapshots[#environment.publishedSnapshots], activated.value)

			local duplicate = service:activateStudioWaveForEvidence()
			assertions.isFalse(duplicate.ok)
			if not duplicate.ok then
				assertions.equal(duplicate.error.code, "REENTRANT")
				assertions.equal(duplicate.error.operation, "activateStudioWaveForEvidence")
				assertions.isNil(string.find(tostring(duplicate.error), PRIVATE_SENTINEL, 1, true))
			end
			assertions.equal(environment.publishCount, publicationsBefore + 1)

			invoke(service:getServiceDefinition().shutdown)
			assertions.equal(environment.cleanupCount, 1)
			local afterCleanup = service:activateStudioWaveForEvidence()
			assertions.isFalse(afterCleanup.ok)
			if not afterCleanup.ok then
				assertions.equal(afterCleanup.error.code, "UNAVAILABLE")
			end
		end
	),

	TestHarness.case(
		"keeps the Studio wave seam closed outside Studio and every disallowed lifecycle state",
		function(assertions)
			local constructed = newService(fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true)), nil)
			local beforeStart = constructed:activateStudioWaveForEvidence()
			assertions.isFalse(beforeStart.ok)
			if not beforeStart.ok then
				assertions.equal(beforeStart.error.code, "UNAVAILABLE")
			end

			local readyService, readyEnvironment = newStudioEvidenceService(assertions, false)
			local readyResult = readyService:activateStudioWaveForEvidence()
			assertions.isFalse(readyResult.ok)
			if not readyResult.ok then
				assertions.equal(readyResult.error.code, "WRONG_STATE")
			end
			invoke(readyService:getServiceDefinition().shutdown)

			local nonStudioService, nonStudioEnvironment = newStudioEvidenceService(assertions)
			nonStudioEnvironment.isStudioMode = "false"
			local nonStudio = nonStudioService:activateStudioWaveForEvidence()
			assertions.isFalse(nonStudio.ok)
			if not nonStudio.ok then
				assertions.equal(nonStudio.error.code, "NOT_STUDIO")
			end
			local stillPreWave = (nonStudioEnvironment.machine :: MatchStateMachine.StateMachine):getSnapshot()
			assertions.isTrue(stillPreWave.ok)
			if stillPreWave.ok then
				assertions.equal(stillPreWave.value.state, "PreWave")
			end
			invoke(nonStudioService:getServiceDefinition().shutdown)

			local terminalService, terminalEnvironment = newStudioEvidenceService(assertions)
			local terminalMachine = terminalEnvironment.machine :: MatchStateMachine.StateMachine
			advanceMachine(assertions, terminalMachine, "WaveActive")
			local waveActiveAttempt = terminalService:activateStudioWaveForEvidence()
			assertions.isFalse(waveActiveAttempt.ok)
			if not waveActiveAttempt.ok then
				assertions.equal(waveActiveAttempt.error.code, "WRONG_STATE")
			end
			advanceMachine(assertions, terminalMachine, "Results")
			local resultsAttempt = terminalService:activateStudioWaveForEvidence()
			assertions.isFalse(resultsAttempt.ok)
			if not resultsAttempt.ok then
				assertions.equal(resultsAttempt.error.code, "WRONG_STATE")
			end
			advanceMachine(assertions, terminalMachine, "Closing")
			local closingAttempt = terminalService:activateStudioWaveForEvidence()
			assertions.isFalse(closingAttempt.ok)
			if not closingAttempt.ok then
				assertions.equal(closingAttempt.error.code, "WRONG_STATE")
			end
			invoke(terminalService:getServiceDefinition().shutdown)

			local definition = constructed:getServiceDefinition()
			invoke(definition.initialize)
			invoke(definition.start)
			invoke(definition.shutdown)
			local cleaned = constructed:activateStudioWaveForEvidence()
			assertions.isFalse(cleaned.ok)
			if not cleaned.ok then
				assertions.equal(cleaned.error.code, "UNAVAILABLE")
			end
			assertions.equal(readyEnvironment.cleanupCount, 1)
		end
	),

	TestHarness.case("contains throwing yielding and malformed Studio predicates", function(assertions)
		for _, mode in { "throw", "yield", "malformed" } do
			local service, environment = newStudioEvidenceService(assertions)
			environment.isStudioMode = mode :: StudioTestMode
			local activated = service:activateStudioWaveForEvidence()
			assertions.isFalse(activated.ok)
			if not activated.ok then
				assertions.equal(activated.error.code, "INTERNAL_ERROR")
				assertions.equal(activated.error.operation, "activateStudioWaveForEvidence")
			end
			assertions.isFalse(service:getSnapshot().ok)
			local machineSnapshot = (environment.machine :: MatchStateMachine.StateMachine):getSnapshot()
			assertions.isTrue(machineSnapshot.ok)
			if machineSnapshot.ok then
				assertions.equal(machineSnapshot.value.state, "Closing")
			end
			invoke(service:getServiceDefinition().shutdown)
			assertions.equal(environment.cleanupCount, 1)
		end
	end),

	TestHarness.case(
		"contains Studio wave state transition faults without exposing an active wave",
		function(assertions)
			local cases = {
				{ field = "snapshotMode", mode = "throw" },
				{ field = "snapshotMode", mode = "yield" },
				{ field = "snapshotMode", mode = "malformed" },
				{ field = "beginMode", mode = "failure" },
				{ field = "beginMode", mode = "throw" },
				{ field = "beginMode", mode = "yield" },
				{ field = "beginMode", mode = "malformed" },
				{ field = "commitMode", mode = "failure" },
				{ field = "commitMode", mode = "throw" },
				{ field = "commitMode", mode = "yield" },
				{ field = "commitMode", mode = "malformed" },
				{ field = "commitMode", mode = "commit-then-throw" },
			}
			for _, case in cases do
				local service, environment = newStudioEvidenceService(assertions)
				local mutableEnvironment = environment :: any
				mutableEnvironment[case.field] = case.mode
				local activated = service:activateStudioWaveForEvidence()
				assertions.isFalse(activated.ok)
				if not activated.ok then
					assertions.equal(activated.error.code, "INTERNAL_ERROR")
				end
				assertions.isFalse(service:getSnapshot().ok)
				environment.snapshotMode = "success"
				environment.beginMode = "success"
				environment.commitMode = "success"
				invoke(service:getServiceDefinition().shutdown)
				assertions.equal(environment.cleanupCount, 1)
			end
		end
	),

	TestHarness.case("fails closed across Studio wave publication reentry and shutdown faults", function(assertions)
		for _, mode in { "failure", "throw", "yield", "malformed", "budget", "reenter", "shutdown" } do
			local service, environment = newStudioEvidenceService(assertions)
			environment.publishMode = mode :: StudioPublishMode
			local activated = service:activateStudioWaveForEvidence()
			assertions.isFalse(activated.ok)
			if not activated.ok then
				assertions.equal(activated.error.code, "INTERNAL_ERROR")
			end
			if mode == "reenter" then
				local reentry = environment.reentryResult :: any
				assertions.isFalse(reentry.ok)
				assertions.equal(reentry.error.code, "REENTRANT")
			end
			assertions.isFalse(service:getSnapshot().ok)
			environment.publishMode = "success"
			invoke(service:getServiceDefinition().shutdown)
			assertions.equal(environment.cleanupCount, 1)
		end
	end),

	TestHarness.case("rejects invalid generated identities without touching the loader", function(assertions)
		local loader = fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true))
		local failure = captureError(assertions, function()
			(newForTests :: MatchLifecycleService.TestConstructor)(logger, {
				mapLoader = loader,
				generateMatchId = function()
					return "map:not-a-match"
				end,
				roster = newRoster(),
				playerSource = fakePlayerSource(),
			})
		end)
		assertions.contains(failure, "[code=INVALID_MATCH_ID]")
		assertions.equal(loader.loadCount, 0)
		assertions.equal(loader.cleanupCount, 0)
	end),

	TestHarness.case("rejects inexact test dependency records", function(assertions)
		local loader = fakeLoader(Result.ok(RUNTIME_MAP_SNAPSHOT), Result.ok(true))
		local extraFieldFailure = captureError(assertions, function()
			(newForTests :: MatchLifecycleService.TestConstructor)(
				logger,
				{
					mapLoader = loader,
					generateMatchId = function()
						return MATCH_ID
					end,
					unexpected = PRIVATE_SENTINEL,
				} :: any
			)
		end)
		assertions.contains(extraFieldFailure, "[code=INVALID_DEPENDENCIES]")
		assertions.isNil(string.find(extraFieldFailure, PRIVATE_SENTINEL, 1, true))

		local metatableDependencies = setmetatable({
			mapLoader = loader,
			generateMatchId = function()
				return MATCH_ID
			end,
		}, {})
		local metatableFailure = captureError(assertions, function()
			(newForTests :: MatchLifecycleService.TestConstructor)(logger, metatableDependencies :: any)
		end)
		assertions.contains(metatableFailure, "[code=INVALID_DEPENDENCIES]")
		assertions.equal(loader.loadCount, 0)
		assertions.equal(loader.cleanupCount, 0)
	end),
})
