--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local WaveFixtures = require(script.Parent.Parent.Fixtures.WaveFixtures)

local ClientRequestTracker = require(script.Parent.Parent.ProductionClientNetworking.ClientRequestTracker)
local WaveController = require(script.Parent.Parent.ProductionClientWaves.WaveController)
local WaveStateReducer = require(script.Parent.Parent.ProductionClientWaves.WaveStateReducer)
local BaseReplicationPublisher = require(script.Parent.Parent.ProductionServerBase.BaseReplicationPublisher)
local BaseRuntime = require(script.Parent.Parent.ProductionServerBase.BaseRuntime)
local BaseRuntimeService = require(script.Parent.Parent.ProductionServerBase.BaseRuntimeService)
local EnemyReplicationPublisher = require(script.Parent.Parent.ProductionServerEnemies.EnemyReplicationPublisher)
local EnemyRuntimeStore = require(script.Parent.Parent.ProductionServerEnemies.EnemyRuntimeStore)
local EnemySimulationService = require(script.Parent.Parent.ProductionServerEnemies.EnemySimulationService)
local WaveReplicationPublisher = require(script.Parent.Parent.ProductionServerWaves.WaveReplicationPublisher)
local WaveRuntime = require(script.Parent.Parent.ProductionServerWaves.WaveRuntime)
local WaveRuntimeService = require(script.Parent.Parent.ProductionServerWaves.WaveRuntimeService)

local Shared = game:GetService("ReplicatedStorage").Shared
local BaseProtocol = require(Shared.match.BaseProtocol)
local MatchProtocol = require(Shared.match.MatchProtocol)
local WaveProtocol = require(Shared.match.WaveProtocol)
local EnvironmentContext = require(Shared.logging.EnvironmentContext)
local Log = require(Shared.logging.Log)
local ProductionRemotes = require(Shared.network.ProductionRemotes)
local Result = require(Shared.util.Result)

type Assertions = TestHarness.Assertions

local ENEMY_EPOCH = 1
local FIRST_USER_ID = 10_001
local newBaseRuntime = BaseRuntime.newForTests
local newBasePublisher = BaseReplicationPublisher.newForTests
local newBaseService = BaseRuntimeService.newForTests
local newEnemyPublisher = EnemyReplicationPublisher.newForTests
local newEnemyService = EnemySimulationService.newForTests
local newWavePublisher = WaveReplicationPublisher.newForTests
local newWaveService = WaveRuntimeService.newForTests
local newTracker = ClientRequestTracker.newForTests
local newWaveController = WaveController.newForTests
local invokeWaveDiagnostics = WaveController.invokeStudioDiagnosticsForTests

if
	newBaseRuntime == nil
	or newBasePublisher == nil
	or newBaseService == nil
	or newEnemyPublisher == nil
	or newEnemyService == nil
	or newWavePublisher == nil
	or newWaveService == nil
	or newTracker == nil
	or newWaveController == nil
	or invokeWaveDiagnostics == nil
then
	error("Phase 11 real-stack test constructors unavailable at exact Test location", 0)
end

local nextRigId = 0
local clientLogger = Log.new(EnvironmentContext.new("client", "Match", 0, false))

type Signal = {
	connect: (self: Signal, listener: (unknown, ...unknown) -> ()) -> RBXScriptConnection,
	fire: (self: Signal, value: unknown, ...unknown) -> (),
	force: (self: Signal, value: unknown, ...unknown) -> (),
}

local function success(assertions: Assertions, resultValue: any): any
	assertions.isTrue(resultValue.ok)
	if not resultValue.ok then
		error("expected integrated operation to succeed", 0)
	end
	return resultValue.value
end

local function expectError(assertions: Assertions, resultValue: any, code: string)
	assertions.isFalse(resultValue.ok)
	if resultValue.ok then
		error("expected integrated operation to fail", 0)
	end
	assertions.equal(resultValue.error.code, code)
end

local function invoke(callback: (() -> ())?)
	if callback == nil then
		error("expected service lifecycle callback", 0)
	end
	(callback :: () -> ())()
end

local function deepEqual(left: unknown, right: unknown, seen: { [any]: any }?): boolean
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
	local visited = seen or {}
	if visited[left :: any] ~= nil then
		return visited[left :: any] == right
	end
	visited[left :: any] = right
	local leftCount = 0
	for key, leftValue in next, left :: any do
		leftCount += 1
		if not deepEqual(leftValue, (right :: any)[key], visited) then
			return false
		end
	end
	local rightCount = 0
	for _ in next, right :: any do
		rightCount += 1
	end
	return leftCount == rightCount
end

local function resultWire(envelope: any, payload: unknown): { [string]: unknown }
	return {
		requestId = envelope.requestId,
		state = "Success",
		payload = payload,
	}
end

local function makeSignal(onDisconnect: (() -> ())?): Signal
	local listener: ((unknown, ...unknown) -> ())? = nil
	local active = false
	local signal = {} :: Signal
	function signal:connect(nextListener)
		listener = nextListener
		active = true
		return RobloxAdapter.createConnection(function()
			if active then
				active = false
				if onDisconnect ~= nil then
					onDisconnect()
				end
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

local function copyFrame(frameValue: unknown, terminalOutcomes: { unknown }): unknown
	local frame = frameValue :: any
	local copy: { [string]: unknown } = {
		disposition = frame.disposition,
		matchId = frame.matchId,
		enemyEpoch = frame.enemyEpoch,
		passOrdinal = frame.passOrdinal,
		sampleServerTime = frame.sampleServerTime,
		terminalOutcomes = table.freeze(terminalOutcomes),
	}
	if frame.spawn ~= nil then
		copy.spawn = frame.spawn
	end
	return table.freeze(copy)
end

local function authenticatedFixture(mutator: ((WaveFixtures.RawSources) -> ())?): WaveFixtures.AuthenticatedFixture
	local raw = WaveFixtures.rawSources()
	if mutator ~= nil then
		mutator(raw)
	end
	return WaveFixtures.authenticateSources(raw)
end

local function participant(userId: number, state: string): any
	return {
		userId = userId,
		state = state,
		ready = state == "Active",
	}
end

local function canonicalMatchSnapshot(control: any): any
	local validated = MatchProtocol.validateMatchSnapshot({
		matchId = control.matchId,
		revision = control.revision,
		state = control.state,
		deadlineServerTime = nil,
		participants = control.participants,
	})
	if not validated.ok then
		error("integrated lifecycle produced an invalid MatchSnapshot", 0)
	end
	return validated.value
end

local function makeLifecycle(rig: any, participantCount: number): (any, any)
	local participants = {}
	for index = 1, participantCount do
		table.insert(participants, participant(FIRST_USER_ID + index - 1, "Active"))
	end
	local control: any = {
		matchId = rig.matchId,
		state = "PreWave",
		revision = 3,
		participants = participants,
		waveToken = nil,
		defeatToken = nil,
		waveBeginCount = 0,
		waveCommitCount = 0,
		waveRollbackCount = 0,
		defeatBeginCount = 0,
		defeatCommitCount = 0,
		defeatRollbackCount = 0,
		terminalRecipients = nil,
		connectedRecipientReadCount = 0,
		committedRecipientReadCount = 0,
	}
	local lifecycle = {}
	local function currentRecipientRecords(): { any }
		local records = {}
		for _, current in control.participants do
			local token = rig.recipientByUserId[current.userId]
			if current.state == "Active" and token ~= nil and token.alive then
				table.insert(records, table.freeze({ recipient = token, userId = current.userId }))
			end
		end
		return table.freeze(records)
	end

	function lifecycle.getSnapshot(_self: unknown): unknown
		if rig.lifecycleSnapshotFailure then
			error("PRIVATE_INTEGRATION_LIFECYCLE_SNAPSHOT_FAILURE", 0)
		end
		table.insert(rig.order, `lifecycle:{control.state}:{control.revision}`)
		return Result.ok(canonicalMatchSnapshot(control))
	end

	function lifecycle.getRuntimeMapSnapshot(_self: unknown): unknown
		return Result.ok(rig.fixture.runtimeMap)
	end

	function lifecycle.isRuntimeMapSnapshot(_self: unknown, value: unknown): boolean
		return value == rig.fixture.runtimeMap
	end

	function lifecycle.getConnectedRecipients(_self: unknown): unknown
		control.connectedRecipientReadCount += 1
		if rig.lifecycleRecipientsFailure then
			error("PRIVATE_INTEGRATION_RECIPIENT_CALLBACK_FAILURE", 0)
		end
		if control.defeatToken ~= nil or control.state == "Results" then
			return Result.err(table.freeze({ code = "UNAVAILABLE" }))
		end
		return Result.ok(currentRecipientRecords())
	end

	function lifecycle.getCommittedBaseDefeatRecipients(_self: unknown): unknown
		control.committedRecipientReadCount += 1
		if control.state ~= "Results" or control.defeatCommitCount ~= 1 or control.terminalRecipients == nil then
			return Result.err(table.freeze({ code = "UNAVAILABLE" }))
		end
		return Result.ok(control.terminalRecipients)
	end

	function lifecycle.beginWaveActivation(_self: unknown, matchId: unknown): unknown
		if matchId ~= control.matchId or control.state ~= "PreWave" or control.waveToken ~= nil then
			return Result.err(table.freeze({ code = "INVALID_STATE" }))
		end
		local token = table.freeze({})
		control.waveToken = token
		control.waveBeginCount += 1
		table.insert(rig.order, "lifecycle:begin-wave")
		return Result.ok(token)
	end

	function lifecycle.commitWaveActivation(_self: unknown, token: unknown): unknown
		if token ~= control.waveToken or control.state ~= "PreWave" then
			return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
		end
		control.waveToken = nil
		control.state = "WaveActive"
		control.revision += 1
		control.waveCommitCount += 1
		local baseSnapshot = rig.baseService:getSnapshot()
		rig.baseWasActiveAtWaveCommit = baseSnapshot.ok and baseSnapshot.value.status == "Active"
		table.insert(rig.order, "lifecycle:commit-wave")
		return Result.ok(table.freeze({
			committed = true,
			published = true,
			snapshot = canonicalMatchSnapshot(control),
		}))
	end

	function lifecycle.rollbackWaveActivation(_self: unknown, token: unknown): unknown
		if token ~= control.waveToken then
			return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
		end
		control.waveToken = nil
		control.waveRollbackCount += 1
		return Result.ok(true)
	end

	function lifecycle.beginBaseDefeat(_self: unknown, matchId: unknown): unknown
		if matchId ~= control.matchId or control.state ~= "WaveActive" or control.defeatToken ~= nil then
			return Result.err(table.freeze({ code = "INVALID_STATE" }))
		end
		local token = table.freeze({})
		control.defeatToken = token
		control.terminalRecipients = currentRecipientRecords()
		control.defeatBeginCount += 1
		table.insert(rig.order, "lifecycle:begin-defeat")
		return Result.ok(token)
	end

	function lifecycle.commitBaseDefeat(_self: unknown, token: unknown): unknown
		if token ~= control.defeatToken or control.state ~= "WaveActive" then
			return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
		end
		control.state = "Results"
		control.revision += 1
		control.defeatCommitCount += 1
		table.insert(rig.order, "lifecycle:commit-defeat")
		return Result.ok(table.freeze({
			committed = true,
			published = true,
			snapshot = canonicalMatchSnapshot(control),
		}))
	end

	function lifecycle.rollbackBaseDefeat(_self: unknown, token: unknown): unknown
		if token ~= control.defeatToken then
			return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
		end
		control.defeatToken = nil
		control.terminalRecipients = nil
		control.defeatRollbackCount += 1
		return Result.ok(true)
	end

	function lifecycle.activateStudioWaveForEvidence(_self: unknown): unknown
		return Result.err(table.freeze({ code = "NOT_STUDIO" }))
	end

	return lifecycle, control
end

local function makeConnection(rig: any, label: string): any
	local connection: any = { connected = true }
	function connection.Disconnect(self: any)
		if self.connected then
			self.connected = false
			rig.connections[label] = false
		end
	end
	rig.connections[label] = true
	return connection
end

local function newRig(assertions: Assertions, options: any?): any
	local resolved = options or {}
	nextRigId += 1
	local rig: any = {
		matchId = `match:phase11-integration-{nextRigId}`,
		clock = { now = 100 },
		order = {},
		connections = {},
		stepCallbacks = {},
		playerRemovingCallbacks = {},
		baseMessages = {},
		enemyMessages = {},
		waveMessages = {},
		leakOutcomes = {},
		waveSendFailure = false,
		enemySendFailure = false,
		baseSendFailure = false,
		passCount = 0,
		cleaned = false,
		lifecycleSnapshotFailure = false,
		lifecycleRecipientsFailure = false,
		withholdTerminalOutcomes = false,
		withheldTerminalOutcomes = {},
		injectedTerminalOutcomes = {},
		capturedTerminalOutcomes = {},
		lastEnemyFrame = nil,
		installedWaveBoundary = nil,
		committedFaultInjected = false,
		forcedCommittedSpawn = nil,
	}
	rig.fixture = resolved.fixture or WaveFixtures.createAuthenticatedFixture()
	rig.waveConfiguration = resolved.waveConfiguration or rig.fixture.configuration
	rig.difficultyId = resolved.difficultyId or WaveFixtures.PRIMARY_DIFFICULTY_ID
	rig.selection = if rig.difficultyId == WaveFixtures.OVERLAP_DIFFICULTY_ID
		then rig.fixture.overlap
		else rig.fixture.primary
	rig.recipientByUserId = {}
	for index = 1, (resolved.participantCount or 4) do
		rig.recipientByUserId[FIRST_USER_ID + index - 1] = {
			alive = true,
			userId = FIRST_USER_ID + index - 1,
		}
	end
	rig.lifecycle, rig.lifecycleControl = makeLifecycle(rig, resolved.participantCount or 4)

	local recipientRecords = {}
	for userId, token in rig.recipientByUserId do
		table.insert(recipientRecords, table.freeze({ recipient = token, userId = userId }))
	end
	table.sort(recipientRecords, function(left: any, right: any): boolean
		return left.userId < right.userId
	end)
	table.freeze(recipientRecords)

	local function createBaseRuntime(
		matchId: unknown,
		enemyEpoch: unknown,
		catalog: unknown,
		lifecycle: unknown
	): unknown
		table.insert(rig.order, "base:create-runtime")
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
					local token = rig.recipientByUserId[userId]
					return recipientValue == token and token ~= nil and token.alive
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
		difficultyCatalog = rig.fixture.configuration.difficulties,
		createRuntime = createBaseRuntime,
		createPublisher = createBasePublisher,
		sender = function(recipientValue: unknown, message: unknown): boolean
			table.insert(rig.baseMessages, table.freeze({ recipient = recipientValue, message = message }))
			return not rig.baseSendFailure
		end,
		getRecipients = function(): unknown
			return recipientRecords
		end,
	})
	rig.baseDefinition = rig.baseService:getServiceDefinition()
	invoke(rig.baseDefinition.initialize)
	invoke(rig.baseDefinition.start)

	local function createStore(matchId: unknown, catalog: unknown, runtimeMap: unknown, endpointSink: unknown): unknown
		table.insert(rig.order, "enemy:create-store")
		local created = EnemyRuntimeStore.newForTests(matchId, ENEMY_EPOCH, catalog, runtimeMap, {
			clock = function(): number
				return rig.clock.now
			end,
			maxActive = resolved.enemyMaxActive,
			maxLifetime = resolved.enemyMaxLifetime,
			endpointSink = function(outcome: any)
				table.insert(rig.leakOutcomes, outcome)
				local sink = endpointSink :: any
				sink(outcome)
			end,
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

	rig.enemyService = (newEnemyService :: EnemySimulationService.TestConstructor)({
		matchLifecycle = rig.lifecycle,
		baseRuntime = rig.baseService,
		catalog = rig.fixture.configuration.enemies,
		createStore = createStore,
		createPublisher = createEnemyPublisher,
		connectStep = function(callback: EnemySimulationService.StepCallback): unknown
			table.insert(rig.stepCallbacks, callback)
			return makeConnection(rig, "enemyStep")
		end,
		connectPlayerRemoving = function(callback: EnemySimulationService.PlayerRemovingCallback): unknown
			table.insert(rig.playerRemovingCallbacks, callback)
			return makeConnection(rig, "playerRemoving")
		end,
		sender = function(recipientValue: unknown, message: unknown): boolean
			table.insert(rig.enemyMessages, table.freeze({ recipient = recipientValue, message = message }))
			return not rig.enemySendFailure
		end,
		getRecipients = function(): unknown
			return {}
		end,
		isStudio = function(): unknown
			return false
		end,
		passClock = function(): unknown
			return rig.clock.now
		end,
		createRuntimeTrigger = function(_handler: unknown): unknown
			return nil
		end,
	})
	rig.enemyDefinition = rig.enemyService:getServiceDefinition()
	invoke(rig.enemyDefinition.initialize)
	local enemyAdapter = {}
	function enemyAdapter.getIdentity(_self: unknown): unknown
		return rig.enemyService:getIdentity()
	end
	function enemyAdapter.installWaveBoundary(_self: unknown, boundary: unknown): unknown
		rig.installedWaveBoundary = boundary
		local forwarding = {}
		function forwarding.onEnemyPass(_forwardingSelf: unknown, frame: unknown): unknown
			rig.lastEnemyFrame = frame
			return (boundary :: any):onEnemyPass(frame)
		end
		function forwarding.flushEnemyPass(_forwardingSelf: unknown, passOrdinal: unknown): unknown
			return (boundary :: any):flushEnemyPass(passOrdinal)
		end
		function forwarding.close(_forwardingSelf: unknown, context: unknown): unknown
			return (boundary :: any):close(context)
		end
		rig.forwardingWaveBoundary = table.freeze(forwarding)
		local installed = rig.enemyService:installWaveBoundary(rig.forwardingWaveBoundary)
		if installed.ok then
			rig.waveBoundaryHandle = installed.value
		end
		return installed
	end
	function enemyAdapter.prepareWaveBinding(
		_self: unknown,
		handle: unknown,
		configuration: unknown,
		difficulty: unknown
	): unknown
		return rig.enemyService:prepareWaveBinding(handle, configuration, difficulty)
	end
	function enemyAdapter.commitWaveBinding(_self: unknown, token: unknown): unknown
		return rig.enemyService:commitWaveBinding(token)
	end
	function enemyAdapter.detachWaveBoundary(_self: unknown, handle: unknown): unknown
		return rig.enemyService:detachWaveBoundary(handle)
	end
	function enemyAdapter.getWaveBoundaryStatus(_self: unknown, handle: unknown): unknown
		return rig.enemyService:getWaveBoundaryStatus(handle)
	end
	function enemyAdapter.isAuthenticatedTerminalOutcome(_self: unknown, handle: unknown, outcome: unknown): unknown
		return rig.enemyService:isAuthenticatedTerminalOutcome(handle, outcome)
	end
	function enemyAdapter.list(_self: unknown): unknown
		return rig.enemyService:list()
	end
	function enemyAdapter.resolveEndpoint(_self: unknown, runtimeEnemyId: unknown): unknown
		return rig.enemyService:resolveEndpoint(runtimeEnemyId)
	end
	function enemyAdapter.despawn(_self: unknown, runtimeEnemyId: unknown): unknown
		return rig.enemyService:despawn(runtimeEnemyId)
	end
	function enemyAdapter.getMetrics(_self: unknown): unknown
		return rig.enemyService:getMetrics()
	end
	rig.enemyAdapter = table.freeze(enemyAdapter)

	local function createWaveRuntime(
		configuration: unknown,
		runtimeMap: unknown,
		matchId: unknown,
		enemyEpoch: unknown,
		difficultyId: unknown,
		dependencies: unknown
	): unknown
		table.insert(rig.order, "wave:create-runtime")
		local runtimeDependencies = dependencies
		if resolved.allowGlobalTerminalAuthentication then
			local original = (dependencies :: any).isAuthenticatedTerminalOutcome
			local copiedDependencies = table.clone(dependencies :: any)
			copiedDependencies.isAuthenticatedTerminalOutcome = function(value: unknown): unknown
				local called, authentic = pcall(original, value)
				if called and authentic == true then
					return true
				end
				return EnemyRuntimeStore.isAuthenticatedTerminalOutcome(value)
			end
			runtimeDependencies = copiedDependencies
		end
		local created =
			WaveRuntime.new(configuration, runtimeMap, matchId, enemyEpoch, difficultyId, runtimeDependencies)
		if created.ok then
			rig.waveRuntime = created.value
			if resolved.instrumentRuntimeFrames or resolved.throwAfterCommittedSpawn then
				local runtime = created.value
				local proxy = {}
				function proxy.initialize(_self: unknown): unknown
					return runtime:initialize()
				end
				function proxy.step(_self: unknown, frameValue: unknown): unknown
					local frame = frameValue :: any
					rig.lastEnemyFrame = frameValue
					if resolved.throwAfterCommittedSpawn and not rig.committedFaultInjected then
						local wave = rig.selection.schedule.waves[1]
						local group = wave.groups[1]
						local scheduledServerTime = 100 + group.startDelaySeconds
						assert(
							scheduledServerTime == frame.sampleServerTime,
							"expected first authored spawn at sampled time"
						)
						assert(frame.spawn ~= nil, "expected authenticated scheduler spawn capability")
						local event = table.freeze({
							originatingWaveIndex = 1,
							waveId = wave.id,
							groupIndex = 1,
							spawnOrdinal = 0,
							scheduledServerTime = scheduledServerTime,
							enemyId = group.enemyId,
							laneId = group.laneId,
						})
						local outcome = frame.spawn(event)
						assert(type(outcome) == "table" and outcome.committed == true, "expected committed Store spawn")
						rig.committedFaultInjected = true
						rig.forcedCommittedSpawn = table.freeze({ event = event, outcome = outcome })
						error("PRIVATE_INTEGRATION_COMMITTED_SPAWN_CALLBACK_FAILURE", 0)
					end
					local outcomes = {}
					for _, outcome in frame.terminalOutcomes do
						table.insert(rig.capturedTerminalOutcomes, outcome)
						if rig.withholdTerminalOutcomes then
							table.insert(rig.withheldTerminalOutcomes, outcome)
						else
							table.insert(outcomes, outcome)
						end
					end
					for _, outcome in rig.injectedTerminalOutcomes do
						table.insert(outcomes, outcome)
					end
					table.clear(rig.injectedTerminalOutcomes)
					return runtime:step(copyFrame(frameValue, outcomes))
				end
				function proxy.closeDependencyFault(_self: unknown, context: unknown): unknown
					return runtime:closeDependencyFault(context)
				end
				function proxy.getSnapshot(_self: unknown): unknown
					return runtime:getSnapshot()
				end
				function proxy.getStartingCashPlaceholder(_self: unknown): unknown
					return runtime:getStartingCashPlaceholder()
				end
				function proxy.getCompletionState(_self: unknown): unknown
					return runtime:getCompletionState()
				end
				function proxy.query(_self: unknown): unknown
					return runtime:query()
				end
				function proxy.submitSkipVote(
					_self: unknown,
					userId: unknown,
					requestMatchId: unknown,
					waveNumber: unknown
				): unknown
					return runtime:submitSkipVote(userId, requestMatchId, waveNumber)
				end
				function proxy.cleanup(_self: unknown): unknown
					return runtime:cleanup()
				end
				rig.waveRuntimeAdapter = table.freeze(proxy)
				return Result.ok(rig.waveRuntimeAdapter)
			end
		end
		return created
	end

	local function createWavePublisher(
		matchId: unknown,
		enemyEpoch: unknown,
		mapId: unknown,
		difficultyId: unknown,
		totalWaves: unknown,
		dependencies: unknown
	): unknown
		local created = (newWavePublisher :: WaveReplicationPublisher.TestConstructor)(
			matchId,
			enemyEpoch,
			mapId,
			difficultyId,
			totalWaves,
			dependencies,
			{
				maxPublications = resolved.waveMaxPublications or WaveReplicationPublisher.MAX_PUBLICATIONS,
				recipientValidator = function(recipientValue: unknown, userId: number): boolean
					local token = rig.recipientByUserId[userId]
					return recipientValue == token and token ~= nil and token.alive
				end,
			}
		)
		if created.ok then
			rig.wavePublisher = created.value
		end
		return created
	end

	local waveDependencies: WaveRuntimeService.TestDependencies = {
		matchLifecycle = rig.lifecycle,
		baseRuntime = rig.baseService,
		enemySimulation = rig.enemyAdapter,
		configuration = rig.waveConfiguration,
		selection = table.freeze({ kind = "AuthoredFinite", difficultyId = rig.difficultyId }),
		clock = function(): unknown
			return rig.clock.now
		end,
		createRuntime = createWaveRuntime,
		createPublisher = createWavePublisher,
		sender = function(recipientValue: Player, snapshot: any): boolean
			table.insert(rig.waveMessages, table.freeze({ recipient = recipientValue, snapshot = snapshot }))
			return not rig.waveSendFailure
		end,
		isStudio = function(): unknown
			return false
		end,
		createRuntimeTrigger = function(_handler: unknown): unknown
			return nil
		end,
		validateConfiguration = function(_sources: unknown): unknown
			return Result.err(table.freeze({ code = "NOT_STUDIO" }))
		end,
		durationClock = function(): unknown
			return rig.clock.now
		end,
	}
	local waveConstructed, waveService = pcall(function(): WaveRuntimeService.Service
		return (newWaveService :: WaveRuntimeService.TestConstructor)(waveDependencies)
	end)
	if resolved.expectWaveConstructionFailure then
		rig.waveConstructSucceeded = waveConstructed
		rig.waveConstructError = waveService
		return rig
	end
	if not waveConstructed then
		error("expected integrated Wave service construction", 0)
	end
	rig.waveService = waveService
	rig.waveDefinition = rig.waveService:getServiceDefinition()
	if resolved.expectWaveInitializeFailure then
		local initialized, initializeError = pcall(function()
			invoke(rig.waveDefinition.initialize)
		end)
		rig.waveInitializeSucceeded = initialized
		rig.waveInitializeError = initializeError
		return rig
	end
	invoke(rig.waveDefinition.initialize)
	invoke(rig.enemyDefinition.start)
	invoke(rig.waveDefinition.start)

	assertions.isTrue(rig.baseWasActiveAtWaveCommit)
	assertions.equal(rig.lifecycleControl.state, "WaveActive")
	assertions.equal(rig.lifecycleControl.waveBeginCount, 1)
	assertions.equal(rig.lifecycleControl.waveCommitCount, 1)
	return rig
end

local function driveTo(rig: any, serverTime: number)
	if serverTime < rig.clock.now then
		error("integrated clock cannot move backwards through driveTo", 0)
	end
	local deltaSeconds = serverTime - rig.clock.now
	rig.clock.now = serverTime
	local callback = rig.stepCallbacks[1]
	if callback == nil then
		error("expected real EnemySimulation step callback", 0)
	end
	rig.passCount += 1
	(callback :: EnemySimulationService.StepCallback)(deltaSeconds)
end

local function driveToMeasured(assertions: Assertions, rig: any, serverTime: number)
	local before = rig.wavePublisher:getMetrics().publicationCount
	driveTo(rig, serverTime)
	local after = rig.wavePublisher:getMetrics().publicationCount
	assertions.isTrue(after - before <= 1)
end

local function waveSnapshot(assertions: Assertions, rig: any): any
	return success(assertions, rig.waveService:getSnapshot())
end

local function enemyList(assertions: Assertions, rig: any): { any }
	return success(assertions, rig.enemyService:list())
end

local function setParticipantState(rig: any, userId: number, state: string)
	for _, current in rig.lifecycleControl.participants do
		if current.userId == userId then
			current.state = state
			current.ready = state == "Active"
			rig.lifecycleControl.revision += 1
			local token = rig.recipientByUserId[userId]
			if token ~= nil then
				token.alive = state == "Active"
			end
			return
		end
	end
	error("participant not found", 0)
end

local function latestWaveMessage(rig: any, userId: number): any?
	for index = #rig.waveMessages, 1, -1 do
		local delivery = rig.waveMessages[index]
		if delivery.recipient.userId == userId then
			return delivery.snapshot
		end
	end
	return nil
end

local function makeIntegratedClient(assertions: Assertions, rig: any, userId: number, eventBeforeGet: boolean): any
	local requestCounter = 0
	local trackerResult = (newTracker :: ClientRequestTracker.TestConstructor)(
		ProductionRemotes,
		"Match",
		function(): string
			requestCounter += 1
			return `waveint{userId}{string.format("%04d", requestCounter)}`
		end
	)
	local tracker = success(assertions, trackerResult)
	local reducer = success(assertions, WaveStateReducer.new())
	local client: any = {
		userId = userId,
		tracker = tracker,
		reducer = reducer,
		getRequests = {},
		skipRequests = {},
		disconnectCount = 0,
		eventBeforeGet = eventBeforeGet,
		eventBeforeGetUsed = false,
		nextWaveMessageIndex = #rig.waveMessages + 1,
	}
	client.eventSignal = makeSignal(function()
		client.disconnectCount += 1
	end)
	client.getResponseSignal = makeSignal(function()
		client.disconnectCount += 1
	end)
	client.skipResponseSignal = makeSignal(function()
		client.disconnectCount += 1
	end)

	local getDefinition = ProductionRemotes:get(WaveProtocol.GET_WAVE_SNAPSHOT_ENDPOINT)
	local skipDefinition = ProductionRemotes:get(WaveProtocol.SUBMIT_SKIP_VOTE_ENDPOINT)
	local eventDefinition = ProductionRemotes:get(WaveProtocol.WAVE_REPLICATION_ENDPOINT)
	if getDefinition == nil or skipDefinition == nil or eventDefinition == nil then
		error("integrated client remote definitions unavailable", 0)
	end
	local dependencies: WaveController.Dependencies = {
		tracker = tracker,
		getSnapshot = {
			definition = getDefinition,
			connectResponse = function(listener)
				return client.getResponseSignal:connect(listener)
			end,
			fire = function(envelope)
				table.insert(client.getRequests, envelope)
				if client.eventBeforeGet and not client.eventBeforeGetUsed then
					local eventSnapshot = latestWaveMessage(rig, userId)
					if eventSnapshot == nil then
						error("expected an actual WaveReplication publication before Get response", 0)
					end
					client.eventBeforeGetUsed = true
					client.eventSignal:fire({ payload = eventSnapshot })
				end
				client.getResponseSignal:fire(resultWire(envelope, waveSnapshot(assertions, rig)))
			end,
		},
		submitSkipVote = {
			definition = skipDefinition,
			connectResponse = function(listener)
				return client.skipResponseSignal:connect(listener)
			end,
			fire = function(envelope)
				table.insert(client.skipRequests, envelope)
				local response =
					rig.waveService:submitSkipVote(userId, envelope.payload.matchId, envelope.payload.waveNumber)
				if response.ok then
					client.skipResponseSignal:fire(resultWire(envelope, response.value))
				end
			end,
		},
		replicationEvent = {
			definition = eventDefinition,
			connectEvent = function(listener)
				return client.eventSignal:connect(listener)
			end,
		},
		reducer = reducer :: any,
	}
	local controllerResult = (newWaveController :: WaveController.TestConstructor)(clientLogger, dependencies)
	client.controller = success(assertions, controllerResult)
	client.definition = client.controller:getServiceDefinition()
	invoke(client.definition.initialize)
	invoke(client.definition.start)
	return client
end

local function deliverWaveMessages(client: any, rig: any, onlyLatest: boolean): number
	local deliveries = {}
	for index = client.nextWaveMessageIndex, #rig.waveMessages do
		local delivery = rig.waveMessages[index]
		if delivery.recipient.userId == client.userId then
			table.insert(deliveries, delivery.snapshot)
		end
	end
	client.nextWaveMessageIndex = #rig.waveMessages + 1
	if onlyLatest and #deliveries > 0 then
		client.eventSignal:fire({ payload = deliveries[#deliveries] })
		return 1
	end
	for _, snapshot in deliveries do
		client.eventSignal:fire({ payload = snapshot })
	end
	return #deliveries
end

local function integratedClientSnapshot(assertions: Assertions, client: any): any
	local state = success(assertions, client.reducer:getState())
	if state.snapshot == nil then
		error("integrated client did not retain a Wave snapshot", 0)
	end
	return state.snapshot
end

local function cleanupIntegratedClient(assertions: Assertions, client: any, staleSnapshot: any)
	invoke(client.definition.shutdown)
	invoke(client.definition.shutdown)
	local metrics = client.controller:getMetrics()
	assertions.equal(metrics.lifecycleState, "Shutdown")
	assertions.equal(metrics.connectionCount, 0)
	assertions.equal(client.disconnectCount, 3)
	local accepted = metrics.acceptedStateCount
	client.eventSignal:force({ payload = staleSnapshot })
	if #client.getRequests > 0 then
		client.getResponseSignal:force(resultWire(client.getRequests[1], staleSnapshot))
		client.skipResponseSignal:force(resultWire(client.getRequests[1], staleSnapshot))
	end
	assertions.equal(client.controller:getMetrics().acceptedStateCount, accepted)
end

local function makeForeignTerminalOutcome(
	assertions: Assertions,
	fixture: WaveFixtures.AuthenticatedFixture,
	matchId: string,
	enemyEpoch: number,
	serverTime: number?
): (EnemyRuntimeStore.Store, unknown)
	local outcomeServerTime = serverTime or 100
	local created =
		EnemyRuntimeStore.newForTests(matchId, enemyEpoch, fixture.configuration.enemies, fixture.runtimeMap, {
			clock = function(): number
				return outcomeServerTime
			end,
			endpointSink = function(_outcome: unknown) end,
		})
	local store = success(assertions, created)
	success(assertions, store:spawn(WaveFixtures.WORKER_ENEMY_ID, WaveFixtures.MAIN_LANE_ID))
	success(assertions, store:despawn(1))
	local outcomes = success(assertions, store:drainTerminalOutcomes())
	assertions.equal(#outcomes, 1)
	assertions.isTrue(EnemyRuntimeStore.isAuthenticatedTerminalOutcome(outcomes[1]))
	return store, outcomes[1]
end

local function cleanup(assertions: Assertions, rig: any)
	if rig.cleaned then
		return
	end
	local oldStep = rig.stepCallbacks[1]
	local oldPlayerRemoving = rig.playerRemovingCallbacks[1]
	local oldBoundary = rig.installedWaveBoundary
	local oldFrame = rig.lastEnemyFrame
	if rig.waveDefinition ~= nil then
		invoke(rig.waveDefinition.shutdown)
	end
	invoke(rig.enemyDefinition.shutdown)
	invoke(rig.baseDefinition.shutdown)
	if rig.waveDefinition ~= nil then
		invoke(rig.waveDefinition.shutdown)
	end
	invoke(rig.enemyDefinition.shutdown)
	invoke(rig.baseDefinition.shutdown)
	rig.cleaned = true

	if rig.waveService ~= nil then
		local waveMetrics = rig.waveService:getMetrics()
		assertions.equal(waveMetrics.connectionCount, 0)
		assertions.isFalse(waveMetrics.retainsRuntime)
		assertions.isFalse(waveMetrics.retainsPublisher)
		assertions.isFalse(waveMetrics.retainsBoundary)
	end
	local enemyMetrics = rig.enemyService:getMetrics()
	assertions.equal(enemyMetrics.stepConnectionCount, 0)
	assertions.equal(enemyMetrics.playerRemovingConnectionCount, 0)
	assertions.isFalse(enemyMetrics.retainsStore)
	assertions.isFalse(enemyMetrics.retainsPublisher)
	local baseMetrics = rig.baseService:getMetrics()
	assertions.isFalse(baseMetrics.retainsRuntime)
	assertions.isFalse(baseMetrics.retainsPublisher)
	assertions.isTrue(rig.connections.enemyStep ~= true)
	assertions.isTrue(rig.connections.playerRemoving ~= true)

	local messageCount = #rig.waveMessages + #rig.enemyMessages + #rig.baseMessages
	if oldStep ~= nil then
		(oldStep :: EnemySimulationService.StepCallback)(1)
	end
	if oldPlayerRemoving ~= nil then
		(oldPlayerRemoving :: EnemySimulationService.PlayerRemovingCallback)(
			rig.recipientByUserId[FIRST_USER_ID] :: any
		)
	end
	if oldBoundary ~= nil and oldFrame ~= nil then
		local frame = oldFrame :: any
		assertions.isTrue(pcall(function()
			(oldBoundary :: any):onEnemyPass(oldFrame)
		end))
		assertions.isTrue(pcall(function()
			(oldBoundary :: any):flushEnemyPass(frame.passOrdinal)
		end))
		assertions.isTrue(pcall(function()
			(oldBoundary :: any):close({})
		end))
	end
	assertions.equal(#rig.waveMessages + #rig.enemyMessages + #rig.baseMessages, messageCount)
	if rig.waveService ~= nil then
		local waveMetrics = rig.waveService:getMetrics()
		assertions.equal(waveMetrics.connectionCount, 0)
		assertions.isFalse(waveMetrics.retainsRuntime)
		assertions.isFalse(waveMetrics.retainsPublisher)
		assertions.isFalse(waveMetrics.retainsBoundary)
	end
	local finalEnemyMetrics = rig.enemyService:getMetrics()
	assertions.equal(finalEnemyMetrics.stepConnectionCount, 0)
	assertions.equal(finalEnemyMetrics.playerRemovingConnectionCount, 0)
	assertions.isFalse(finalEnemyMetrics.retainsStore)
	assertions.isFalse(finalEnemyMetrics.retainsPublisher)
	local finalBaseMetrics = rig.baseService:getMetrics()
	assertions.isFalse(finalBaseMetrics.retainsRuntime)
	assertions.isFalse(finalBaseMetrics.retainsPublisher)
end

local function expectAuthenticTerminalFault(assertions: Assertions, kind: "Stale" | "WrongMatch" | "WrongEpoch")
	local rig = newRig(assertions, {
		instrumentRuntimeFrames = true,
		allowGlobalTerminalAuthentication = true,
	})
	driveTo(rig, 100)
	local before = success(assertions, rig.waveRuntime:getSnapshot())
	local matchId = if kind == "WrongMatch" then `match:phase11-foreign-{nextRigId}` else rig.matchId
	local enemyEpoch = if kind == "WrongEpoch" then ENEMY_EPOCH + 1 else ENEMY_EPOCH
	local serverTime = if kind == "Stale" then 99 else 100
	local store, outcome = makeForeignTerminalOutcome(assertions, rig.fixture, matchId, enemyEpoch, serverTime)
	table.insert(rig.injectedTerminalOutcomes, outcome)
	driveTo(rig, 101)
	assertions.equal(rig.waveService:getMetrics().terminalState, "Faulted")
	local faulted = success(assertions, rig.waveRuntime:getSnapshot())
	assertions.equal(faulted.state, "Faulted")
	assertions.isTrue(deepEqual(faulted.aggregateCounts, before.aggregateCounts))
	local runtimeMetrics = rig.waveRuntime:query()
	assertions.equal(runtimeMetrics.faultCode, "INVALID_OUTCOME")
	assertions.equal(runtimeMetrics.processedTerminalCount, 0)
	success(assertions, store:cleanup())
	assertions.isFalse(EnemyRuntimeStore.isAuthenticatedTerminalOutcome(outcome))
	cleanup(assertions, rig)
end

return TestHarness.suite("Phase 11 authored-wave real-stack integration", {
	TestHarness.case(
		"authenticates configuration before WaveActive and preserves exact schedule order",
		function(assertions)
			local rig = newRig(assertions)
			local initial = waveSnapshot(assertions, rig)
			assertions.equal(initial.state, "Running")
			assertions.equal(initial.currentWaveNumber, 1)
			assertions.equal(initial.currentCounts.totalScheduled, 8)
			assertions.equal(success(assertions, rig.baseService:getSnapshot()).maximumHealth, 250)

			-- The canonical configuration is detached from its now-hostile raw input.
			rig.fixture.rawSources.enemies[1].maxHealth = 1
			rig.fixture.rawSources.enemies[1].moveSpeedStudsPerSecond = 100
			rig.fixture.rawSources.economy.difficultyRules[1].startingBattleCash = 1
			assertions.equal(success(assertions, rig.waveService:getStartingCashPlaceholder()).startingBattleCash, 375)
			driveTo(rig, 100)
			local spawned = enemyList(assertions, rig)
			assertions.equal(#spawned, 3)
			for index = 1, 3 do
				assertions.equal(spawned[index].runtimeEnemyId, index)
				assertions.equal(spawned[index].enemyId, WaveFixtures.WORKER_ENEMY_ID)
				assertions.equal(spawned[index].laneId, WaveFixtures.MAIN_LANE_ID)
				assertions.equal(spawned[index].maximumHealth, 100)
				assertions.equal(spawned[index].effectiveSpeed, 4)
			end

			driveTo(rig, 102)
			driveTo(rig, 104)
			driveTo(rig, 106)
			driveTo(rig, 109)
			spawned = enemyList(assertions, rig)
			assertions.equal(#spawned, 8)
			assertions.equal(spawned[4].enemyId, WaveFixtures.SCOUT_ENEMY_ID)
			assertions.equal(spawned[4].laneId, WaveFixtures.ALTERNATE_LANE_ID)
			assertions.equal(spawned[5].enemyId, WaveFixtures.SCOUT_ENEMY_ID)
			assertions.equal(spawned[6].enemyId, WaveFixtures.SCOUT_ENEMY_ID)
			assertions.equal(spawned[7].enemyId, WaveFixtures.WORKER_ENEMY_ID)
			assertions.equal(spawned[8].enemyId, WaveFixtures.WORKER_ENEMY_ID)
			assertions.equal(spawned[6].spawnServerTime, 106)
			assertions.equal(spawned[7].spawnServerTime, 106)

			cleanup(assertions, rig)
		end
	),

	TestHarness.case("routes real endpoints into Base and attributes current counters", function(assertions)
		local fixture = authenticatedFixture(function(raw)
			raw.enemies[1].moveSpeedStudsPerSecond = 100
		end)
		local rig = newRig(assertions, { fixture = fixture })
		driveTo(rig, 100)
		driveTo(rig, 101)

		assertions.equal(#rig.leakOutcomes, 3)
		for index, outcome in rig.leakOutcomes do
			assertions.equal(outcome.runtimeEnemyId, index)
			assertions.equal(outcome.leakDamage, 3)
			assertions.equal(outcome.matchId, rig.matchId)
			assertions.equal(outcome.enemyEpoch, ENEMY_EPOCH)
		end
		local base = success(assertions, rig.baseService:getSnapshot())
		assertions.equal(base.status, "Active")
		assertions.equal(base.currentHealth, 241)
		local wave = waveSnapshot(assertions, rig)
		assertions.equal(wave.aggregateCounts.leaked, 3)
		assertions.equal(wave.aggregateCounts.alive, wave.aggregateCounts.spawned - 3)
		assertions.equal(success(assertions, rig.enemyService:queryTerminal(1)).reason, "Endpoint")

		cleanup(assertions, rig)
	end),

	TestHarness.case("uses exact five-second intermission for empty and cleared waves", function(assertions)
		local emptyFixture = authenticatedFixture(function(raw)
			raw.waves[1].waves[1].groups = {}
		end)
		local emptyRig = newRig(assertions, { fixture = emptyFixture })
		driveTo(emptyRig, 100)
		local empty = waveSnapshot(assertions, emptyRig)
		assertions.equal(empty.state, "Intermission")
		assertions.equal(empty.intermissionEndsServerTime, 105)
		driveTo(emptyRig, 104.999)
		assertions.equal(waveSnapshot(assertions, emptyRig).currentWaveNumber, 1)
		driveTo(emptyRig, 105)
		assertions.equal(waveSnapshot(assertions, emptyRig).currentWaveNumber, 2)
		cleanup(assertions, emptyRig)

		local clearRig = newRig(assertions)
		for _, time in { 100, 102, 104, 106, 109 } do
			driveTo(clearRig, time)
		end
		for _, enemy in enemyList(assertions, clearRig) do
			success(assertions, clearRig.enemyService:despawn(enemy.runtimeEnemyId))
		end
		driveTo(clearRig, 110)
		local cleared = waveSnapshot(assertions, clearRig)
		assertions.equal(cleared.state, "Intermission")
		assertions.equal(cleared.intermissionEndsServerTime, 115)
		driveTo(clearRig, 114.999)
		assertions.equal(waveSnapshot(assertions, clearRig).currentWaveNumber, 1)
		driveTo(clearRig, 115)
		assertions.equal(waveSnapshot(assertions, clearRig).currentWaveNumber, 2)
		cleanup(assertions, clearRig)
	end),

	TestHarness.case("orders deadline ties and attributes overlap to the originating wave", function(assertions)
		local rig = newRig(assertions, { difficultyId = WaveFixtures.OVERLAP_DIFFICULTY_ID })
		driveTo(rig, 102)
		assertions.equal(#enemyList(assertions, rig), 1)
		driveTo(rig, 105)
		local atDeadline = enemyList(assertions, rig)
		assertions.equal(#atDeadline, 4)
		assertions.equal(atDeadline[1].enemyId, WaveFixtures.WORKER_ENEMY_ID)
		assertions.equal(atDeadline[2].enemyId, WaveFixtures.WORKER_ENEMY_ID)
		assertions.equal(atDeadline[3].enemyId, WaveFixtures.SCOUT_ENEMY_ID)
		assertions.equal(atDeadline[4].enemyId, WaveFixtures.SCOUT_ENEMY_ID)
		local waveTwo = waveSnapshot(assertions, rig)
		assertions.equal(waveTwo.currentWaveNumber, 2)
		assertions.equal(waveTwo.currentCounts.spawned, 2)
		assertions.equal(waveTwo.aggregateCounts.spawned, 4)
		driveTo(rig, 108)
		assertions.equal(#enemyList(assertions, rig), 5)
		for _, runtimeEnemyId in { 1, 2, 5 } do
			success(assertions, rig.enemyService:despawn(runtimeEnemyId))
		end
		driveTo(rig, 109)
		local attributed = waveSnapshot(assertions, rig)
		assertions.equal(attributed.aggregateCounts.otherwiseResolved, 3)
		assertions.equal(attributed.currentCounts.otherwiseResolved, 0)
		assertions.equal(attributed.currentCounts.alive, 2)
		cleanup(assertions, rig)
	end),

	TestHarness.case("recomputes disconnect quorum while an exact deadline still wins the tie", function(assertions)
		local skipRig = newRig(assertions, { difficultyId = WaveFixtures.OVERLAP_DIFFICULTY_ID })
		driveTo(skipRig, 101)
		success(assertions, skipRig.waveService:submitSkipVote(FIRST_USER_ID, skipRig.matchId, 1))
		success(assertions, skipRig.waveService:submitSkipVote(FIRST_USER_ID + 1, skipRig.matchId, 1))
		assertions.isFalse(waveSnapshot(assertions, skipRig).skipState.quorumPending)
		setParticipantState(skipRig, FIRST_USER_ID + 3, "Disconnected")
		driveTo(skipRig, 103)
		local skipped = waveSnapshot(assertions, skipRig)
		assertions.equal(skipped.currentWaveNumber, 2)
		assertions.equal(skipped.waveStartedServerTime, 103)
		assertions.equal(skipped.aggregateCounts.pending, 2)
		assertions.equal(skipped.aggregateCounts.spawned, 3)
		cleanup(assertions, skipRig)

		local deadlineRig = newRig(assertions, { difficultyId = WaveFixtures.OVERLAP_DIFFICULTY_ID })
		driveTo(deadlineRig, 101)
		success(assertions, deadlineRig.waveService:submitSkipVote(FIRST_USER_ID, deadlineRig.matchId, 1))
		success(assertions, deadlineRig.waveService:submitSkipVote(FIRST_USER_ID + 1, deadlineRig.matchId, 1))
		setParticipantState(deadlineRig, FIRST_USER_ID + 3, "Disconnected")
		driveTo(deadlineRig, 105)
		local deadline = waveSnapshot(assertions, deadlineRig)
		assertions.equal(deadline.currentWaveNumber, 2)
		assertions.equal(deadline.waveStartedServerTime, 105)
		assertions.equal(deadline.aggregateCounts.spawned, 4)
		assertions.equal(deadline.aggregateCounts.pending, 1)
		cleanup(assertions, deadlineRig)
	end),

	TestHarness.case("bounds a large pass and rejects wrong match wave and epoch authority", function(assertions)
		local rig = newRig(assertions)
		expectError(assertions, rig.waveService:submitSkipVote(FIRST_USER_ID, "match:wrong", 1), "STALE_REQUEST")
		expectError(assertions, rig.waveService:submitSkipVote(FIRST_USER_ID, rig.matchId, 2), "STALE_REQUEST")
		driveTo(rig, 10_000)
		local wave = waveSnapshot(assertions, rig)
		assertions.equal(wave.aggregateCounts.totalScheduled, WaveFixtures.PRIMARY_SCHEDULED_SPAWNS)
		assertions.equal(wave.aggregateCounts.spawned, WaveFixtures.PRIMARY_SCHEDULED_SPAWNS)
		assertions.equal(wave.aggregateCounts.pending, 0)
		assertions.isTrue(wave.aggregateCounts.alive <= 128)
		assertions.equal(rig.enemyStore:getMetrics().lifetimeCount, WaveFixtures.PRIMARY_SCHEDULED_SPAWNS)
		expectError(
			assertions,
			rig.enemyStore:finishSchedulerSample(table.freeze({
				matchId = rig.matchId,
				enemyEpoch = ENEMY_EPOCH + 1,
				passOrdinal = rig.passCount,
				sampleServerTime = rig.clock.now,
			})),
			"INVALID_SCHEDULER_SAMPLE"
		)
		assertions.isFalse(rig.enemyService:spawn(WaveFixtures.WORKER_ENEMY_ID, WaveFixtures.MAIN_LANE_ID).ok)
		cleanup(assertions, rig)
	end),

	TestHarness.case("completes finite content once without Results and closes spawn and vote", function(assertions)
		local rig = newRig(assertions)
		for _, time in { 100, 102, 104, 106, 109 } do
			driveTo(rig, time)
		end
		for _, enemy in enemyList(assertions, rig) do
			success(assertions, rig.enemyService:despawn(enemy.runtimeEnemyId))
		end
		driveTo(rig, 110)
		driveTo(rig, 115)
		driveTo(rig, 116)
		driveTo(rig, 118)
		for _, enemy in enemyList(assertions, rig) do
			success(assertions, rig.enemyService:despawn(enemy.runtimeEnemyId))
		end
		driveTo(rig, 119)
		driveTo(rig, 124)
		driveTo(rig, 129)
		for _, time in { 135, 137, 139 } do
			driveTo(rig, time)
		end
		for _, enemy in enemyList(assertions, rig) do
			success(assertions, rig.enemyService:despawn(enemy.runtimeEnemyId))
		end
		driveTo(rig, 140)
		local completed = waveSnapshot(assertions, rig)
		assertions.equal(completed.state, "FiniteComplete")
		assertions.equal(completed.aggregateCounts.spawned, WaveFixtures.PRIMARY_SCHEDULED_SPAWNS)
		assertions.equal(completed.aggregateCounts.alive, 0)
		assertions.equal(rig.lifecycleControl.state, "WaveActive")
		assertions.equal(rig.lifecycleControl.defeatCommitCount, 0)
		local completion = success(assertions, rig.waveService:getCompletionState())
		assertions.equal(completion.state, "FiniteComplete")
		assertions.equal(completion.completionCount, 1)
		driveTo(rig, 200)
		assertions.equal(success(assertions, rig.waveService:getCompletionState()).completionCount, 1)
		expectError(assertions, rig.waveService:submitSkipVote(FIRST_USER_ID, rig.matchId, 4), "UNAVAILABLE")
		assertions.isFalse(rig.enemyService:spawn(WaveFixtures.WORKER_ENEMY_ID, WaveFixtures.MAIN_LANE_ID).ok)
		cleanup(assertions, rig)
	end),

	TestHarness.case("coalesces an empty final wave directly from intermission for two clients", function(assertions)
		local fixture = authenticatedFixture(function(raw)
			raw.difficulties[1].waveCount = 2
			raw.difficulties[1].timing.bossCadenceWaves = 3
			raw.waves[1].waves = {
				{
					id = "wave:phase11-empty-final-1",
					deadlineSeconds = 10,
					deadlinePolicy = "AllSpawnsByDeadline",
					bossKind = "None",
					rewardClass = "Standard",
					groups = {},
				},
				{
					id = "wave:phase11-empty-final-2",
					deadlineSeconds = 10,
					deadlinePolicy = "AllSpawnsByDeadline",
					bossKind = "None",
					rewardClass = "Final",
					groups = {},
				},
			}
		end)
		local rig = newRig(assertions, { fixture = fixture, participantCount = 2 })
		local clientOne = makeIntegratedClient(assertions, rig, FIRST_USER_ID, false)
		local clientTwo = makeIntegratedClient(assertions, rig, FIRST_USER_ID + 1, false)
		local initial = waveSnapshot(assertions, rig)

		driveTo(rig, 100)
		assertions.equal(deliverWaveMessages(clientOne, rig, false), 1)
		assertions.equal(deliverWaveMessages(clientTwo, rig, false), 1)
		assertions.equal(integratedClientSnapshot(assertions, clientOne).state, "Intermission")
		assertions.equal(integratedClientSnapshot(assertions, clientTwo).state, "Intermission")
		local publicationsBeforeFinal = rig.wavePublisher:getMetrics().publicationCount

		driveTo(rig, 105)
		local completed = waveSnapshot(assertions, rig)
		assertions.equal(completed.state, "FiniteComplete")
		assertions.equal(completed.currentWaveNumber, 2)
		assertions.equal(completed.finiteCompleteServerTime, 105)
		assertions.equal(rig.wavePublisher:getMetrics().publicationCount, publicationsBeforeFinal + 1)
		assertions.equal(deliverWaveMessages(clientOne, rig, false), 1)
		assertions.equal(deliverWaveMessages(clientTwo, rig, false), 1)
		assertions.isTrue(deepEqual(integratedClientSnapshot(assertions, clientOne), completed))
		assertions.isTrue(deepEqual(integratedClientSnapshot(assertions, clientTwo), completed))
		assertions.equal(rig.lifecycleControl.state, "WaveActive")
		assertions.equal(rig.lifecycleControl.defeatCommitCount, 0)
		assertions.equal(success(assertions, rig.waveService:getCompletionState()).completionCount, 1)

		driveTo(rig, 106)
		assertions.equal(rig.wavePublisher:getMetrics().publicationCount, publicationsBeforeFinal + 1)
		cleanupIntegratedClient(assertions, clientOne, initial)
		cleanupIntegratedClient(assertions, clientTwo, initial)
		cleanup(assertions, rig)
	end),

	TestHarness.case("commits one Results transition for same-pass Base defeat", function(assertions)
		local fixture = authenticatedFixture(function(raw)
			raw.enemies[1].moveSpeedStudsPerSecond = 1_000_000
			raw.enemies[1].leakDamage = 250
		end)
		local rig = newRig(assertions, { fixture = fixture })
		driveTo(rig, 100)
		driveTo(rig, 101)
		local base = success(assertions, rig.baseService:getSnapshot())
		assertions.equal(base.status, "Defeated")
		assertions.equal(base.currentHealth, 0)
		assertions.equal(rig.lifecycleControl.state, "Results")
		assertions.equal(rig.lifecycleControl.defeatBeginCount, 1)
		assertions.equal(rig.lifecycleControl.defeatCommitCount, 1)
		assertions.equal(rig.enemyService:getMetrics().defeatCount, 1)
		assertions.equal(rig.enemyService:getMetrics().resultsCommitCount, 1)
		assertions.equal(waveSnapshot(assertions, rig).state, "DefeatClosed")
		driveTo(rig, 102)
		assertions.equal(rig.lifecycleControl.defeatCommitCount, 1)
		assertions.equal(rig.enemyStore:getMetrics().lifetimeCount, 3)
		cleanup(assertions, rig)
	end),

	TestHarness.case("converges reducers across gaps and contains publisher and clock faults", function(assertions)
		local rig = newRig(assertions, { participantCount = 2 })
		driveTo(rig, 100)
		driveTo(rig, 102)
		driveTo(rig, 104)
		assertions.isTrue(#rig.waveMessages >= 6)

		local ordered = success(assertions, WaveStateReducer.new())
		local gapped = success(assertions, WaveStateReducer.new())
		local snapshots = {}
		for _, delivery in rig.waveMessages do
			if delivery.recipient.userId == FIRST_USER_ID then
				table.insert(snapshots, delivery.snapshot)
			end
		end
		for _, snapshot in snapshots do
			success(assertions, ordered:observeEvent(snapshot))
		end
		assertions.equal(success(assertions, gapped:observeEvent(snapshots[1])).kind, "Applied")
		assertions.equal(success(assertions, gapped:observeEvent(snapshots[#snapshots])).kind, "Skipped")
		assertions.isTrue(success(assertions, gapped:getState()).recoveryRequired)
		local current = waveSnapshot(assertions, rig)
		assertions.equal(success(assertions, gapped:observeGetResponse(current, false)).kind, "Applied")
		assertions.equal(success(assertions, gapped:observeEvent(snapshots[1])).kind, "Stale")
		assertions.equal(
			success(assertions, gapped:getState()).snapshot.waveRevision,
			success(assertions, ordered:getState()).snapshot.waveRevision
		)
		success(assertions, ordered:cleanup())
		success(assertions, gapped:cleanup())

		rig.waveSendFailure = true
		driveTo(rig, 106)
		assertions.isTrue(rig.wavePublisher:getMetrics().senderFailureCount > 0)
		assertions.equal(waveSnapshot(assertions, rig).state, "Running")
		local oldStep = rig.stepCallbacks[1]
		rig.clock.now = 105
		(oldStep :: EnemySimulationService.StepCallback)(1)
		assertions.equal(rig.enemyService:getMetrics().lifecycleState, "Failed")
		assertions.equal(rig.waveService:getMetrics().terminalState, "Faulted")
		cleanup(assertions, rig)
	end),

	TestHarness.case("rejects unauthenticated and over-capacity schedules before activation", function(assertions)
		local fixture = WaveFixtures.createAuthenticatedFixture()
		local unauthenticated = WaveFixtures.rawSources()
		local unauthenticatedRig = newRig(assertions, {
			fixture = fixture,
			waveConfiguration = unauthenticated,
			expectWaveConstructionFailure = true,
		})
		assertions.isFalse(unauthenticatedRig.waveConstructSucceeded)
		assertions.contains(
			tostring(unauthenticatedRig.waveConstructError),
			"[ATD_WAVE_RUNTIME_SERVICE][code=INVALID_DEPENDENCIES]"
		)
		assertions.equal(unauthenticatedRig.lifecycleControl.state, "PreWave")
		assertions.equal(unauthenticatedRig.lifecycleControl.waveBeginCount, 0)
		assertions.equal(unauthenticatedRig.lifecycleControl.waveCommitCount, 0)
		assertions.equal(unauthenticatedRig.baseRuntime:query().state, "Uninitialized")
		assertions.equal(unauthenticatedRig.enemyStore:getMetrics().lifetimeCount, 0)
		assertions.isNil(unauthenticatedRig.waveService)
		cleanup(assertions, unauthenticatedRig)

		local overCapacity = authenticatedFixture(function(raw)
			local schedule = raw.waves[2]
			local group = schedule.waves[1].groups[1]
			group.count = 4_095
			group.startDelaySeconds = 0
			group.spawnIntervalSeconds = 0.5
			schedule.waves[1].deadlinePolicy = "AllowScheduledOverlap"
		end)
		local scheduledEventCount = 0
		for _, wave in overCapacity.overlap.schedule.waves do
			for _, group in wave.groups do
				scheduledEventCount += group.count
			end
		end
		assertions.equal(scheduledEventCount, WaveRuntime.MAX_TOTAL_EVENTS + 1)
		local capacityRig = newRig(assertions, {
			fixture = overCapacity,
			difficultyId = WaveFixtures.OVERLAP_DIFFICULTY_ID,
			expectWaveInitializeFailure = true,
		})
		assertions.isFalse(capacityRig.waveInitializeSucceeded)
		assertions.contains(
			tostring(capacityRig.waveInitializeError),
			"[ATD_WAVE_RUNTIME_SERVICE][code=RUNTIME_CREATION_FAILED]"
		)
		assertions.equal(capacityRig.lifecycleControl.state, "PreWave")
		assertions.equal(capacityRig.lifecycleControl.waveBeginCount, 0)
		assertions.equal(capacityRig.lifecycleControl.waveCommitCount, 0)
		assertions.equal(capacityRig.baseRuntime:query().state, "Uninitialized")
		assertions.equal(capacityRig.enemyStore:getMetrics().lifetimeCount, 0)
		assertions.isFalse(capacityRig.waveService:getMetrics().retainsRuntime)
		assertions.isFalse(capacityRig.waveService:getMetrics().retainsPublisher)
		assertions.isFalse(capacityRig.waveService:getMetrics().retainsBoundary)
		cleanup(assertions, capacityRig)
	end),

	TestHarness.case("makes deadline win an exact clear tie and closes the finite boundary", function(assertions)
		local tieRig = newRig(assertions)
		for _, serverTime in { 100, 102, 104, 106, 109 } do
			driveToMeasured(assertions, tieRig, serverTime)
		end
		for _, enemy in enemyList(assertions, tieRig) do
			success(assertions, tieRig.enemyService:despawn(enemy.runtimeEnemyId))
		end
		driveToMeasured(assertions, tieRig, 112)
		local tied = waveSnapshot(assertions, tieRig)
		assertions.equal(tied.state, "Running")
		assertions.equal(tied.currentWaveNumber, 2)
		assertions.equal(tied.waveStartedServerTime, 112)
		assertions.equal(tieRig.lifecycleControl.state, "WaveActive")
		cleanup(assertions, tieRig)

		local finiteFixture = authenticatedFixture(function(raw)
			raw.difficulties[1].waveCount = 1
			local finalWave = raw.waves[1].waves[1]
			finalWave.groups = { finalWave.groups[1] }
			finalWave.groups[1].count = 1
			finalWave.groups[1].startDelaySeconds = 0
			finalWave.groups[1].spawnIntervalSeconds = 0
			finalWave.rewardClass = "Final"
			raw.waves[1].waves = { finalWave }
		end)
		local finiteRig = newRig(assertions, { fixture = finiteFixture })
		driveToMeasured(assertions, finiteRig, 100)
		success(assertions, finiteRig.enemyService:despawn(1))
		driveToMeasured(assertions, finiteRig, 101)
		local complete = waveSnapshot(assertions, finiteRig)
		assertions.equal(complete.state, "FiniteComplete")
		assertions.equal(success(assertions, finiteRig.waveService:getCompletionState()).completionCount, 1)
		assertions.equal(finiteRig.lifecycleControl.state, "WaveActive")
		local enemyMetrics = finiteRig.enemyService:getMetrics()
		assertions.equal(enemyMetrics.waveBoundaryStatus, "FiniteComplete")
		local lifetime = finiteRig.enemyStore:getMetrics().lifetimeCount
		local publicationCount = finiteRig.wavePublisher:getMetrics().publicationCount
		local revision = complete.waveRevision
		driveToMeasured(assertions, finiteRig, 200)
		assertions.equal(finiteRig.enemyStore:getMetrics().lifetimeCount, lifetime)
		assertions.equal(finiteRig.wavePublisher:getMetrics().publicationCount, publicationCount)
		assertions.equal(waveSnapshot(assertions, finiteRig).waveRevision, revision)
		assertions.equal(finiteRig.lifecycleControl.state, "WaveActive")
		cleanup(assertions, finiteRig)
	end),

	TestHarness.case(
		"handles authentic delayed duplicate and foreign terminal outcomes and defeat races",
		function(assertions)
			local terminalRig = newRig(assertions, {
				instrumentRuntimeFrames = true,
			})
			driveTo(terminalRig, 100)
			success(assertions, terminalRig.enemyService:despawn(1))
			terminalRig.withholdTerminalOutcomes = true
			driveTo(terminalRig, 101)
			assertions.equal(#terminalRig.withheldTerminalOutcomes, 1)
			assertions.isTrue(
				terminalRig.enemyService:isAuthenticatedTerminalOutcome(
					terminalRig.waveBoundaryHandle,
					terminalRig.withheldTerminalOutcomes[1]
				)
			)
			assertions.equal(waveSnapshot(assertions, terminalRig).aggregateCounts.otherwiseResolved, 0)
			terminalRig.withholdTerminalOutcomes = false
			table.insert(terminalRig.injectedTerminalOutcomes, terminalRig.withheldTerminalOutcomes[1])
			driveTo(terminalRig, 102)
			local delayed = waveSnapshot(assertions, terminalRig)
			assertions.equal(delayed.aggregateCounts.otherwiseResolved, 1)
			local delayedRevision = delayed.waveRevision
			table.insert(terminalRig.injectedTerminalOutcomes, terminalRig.withheldTerminalOutcomes[1])
			driveTo(terminalRig, 103)
			assertions.equal(waveSnapshot(assertions, terminalRig).aggregateCounts.otherwiseResolved, 1)
			assertions.equal(waveSnapshot(assertions, terminalRig).waveRevision, delayedRevision)

			cleanup(assertions, terminalRig)
			expectAuthenticTerminalFault(assertions, "Stale")
			expectAuthenticTerminalFault(assertions, "WrongMatch")
			expectAuthenticTerminalFault(assertions, "WrongEpoch")

			local lethalFixture = authenticatedFixture(function(raw)
				raw.difficulties[1].base.maxHealth = 1
				raw.enemies[1].moveSpeedStudsPerSecond = 1_000_000
			end)
			local lethalRig = newRig(assertions, { fixture = lethalFixture, participantCount = 2 })
			driveTo(lethalRig, 100)
			local lethalInitial = waveSnapshot(assertions, lethalRig)
			local lethalClientOne = makeIntegratedClient(assertions, lethalRig, FIRST_USER_ID, false)
			local lethalClientTwo = makeIntegratedClient(assertions, lethalRig, FIRST_USER_ID + 1, false)
			assertions.equal(lethalRig.enemyStore:getMetrics().lifetimeCount, 3)
			driveTo(lethalRig, 102)
			assertions.equal(lethalRig.enemyStore:getMetrics().lifetimeCount, 3)
			local lethalClosed = waveSnapshot(assertions, lethalRig)
			assertions.equal(lethalClosed.state, "DefeatClosed")
			assertions.equal(deliverWaveMessages(lethalClientOne, lethalRig, false), 1)
			assertions.equal(deliverWaveMessages(lethalClientTwo, lethalRig, false), 1)
			assertions.isTrue(deepEqual(integratedClientSnapshot(assertions, lethalClientOne), lethalClosed))
			assertions.isTrue(deepEqual(integratedClientSnapshot(assertions, lethalClientTwo), lethalClosed))
			assertions.equal(lethalClientOne.controller:getMetrics().connectionCount, 3)
			assertions.equal(lethalClientTwo.controller:getMetrics().connectionCount, 3)
			assertions.equal(lethalRig.lifecycleControl.defeatCommitCount, 1)
			assertions.equal(lethalRig.lifecycleControl.state, "Results")
			assertions.equal(lethalRig.lifecycleControl.committedRecipientReadCount, 1)
			local retainedRecipients = lethalRig.lifecycleControl.terminalRecipients
			assertions.equal(type(retainedRecipients), "table")
			if type(retainedRecipients) ~= "table" then
				error("[ATD_TEST][code=TERMINAL_RECIPIENTS_MISSING]", 0)
			end
			assertions.isTrue(table.isfrozen(retainedRecipients :: any))
			assertions.equal(#(retainedRecipients :: any), 2)
			local exposedRecipients = success(assertions, lethalRig.lifecycle:getCommittedBaseDefeatRecipients())
			assertions.equal(exposedRecipients, retainedRecipients)
			cleanupIntegratedClient(assertions, lethalClientOne, lethalInitial)
			cleanupIntegratedClient(assertions, lethalClientTwo, lethalInitial)
			cleanup(assertions, lethalRig)

			local raceFixture = authenticatedFixture(function(raw)
				raw.difficulties[1].waveCount = 1
				raw.difficulties[1].base.maxHealth = 1
				raw.enemies[1].moveSpeedStudsPerSecond = 1_000_000
				local finalWave = raw.waves[1].waves[1]
				finalWave.groups = { finalWave.groups[1] }
				finalWave.groups[1].count = 1
				finalWave.groups[1].startDelaySeconds = 0
				finalWave.groups[1].spawnIntervalSeconds = 0
				finalWave.deadlineSeconds = 2
				finalWave.rewardClass = "Final"
				raw.waves[1].waves = { finalWave }
			end)
			local raceRig = newRig(assertions, { fixture = raceFixture })
			driveTo(raceRig, 100)
			driveTo(raceRig, 102)
			assertions.equal(waveSnapshot(assertions, raceRig).state, "DefeatClosed")
			assertions.equal(success(assertions, raceRig.waveService:getCompletionState()).completionCount, 0)
			assertions.equal(raceRig.lifecycleControl.defeatCommitCount, 1)
			assertions.equal(raceRig.lifecycleControl.state, "Results")
			cleanup(assertions, raceRig)
		end
	),

	TestHarness.case(
		"reconciles a Store-committed spawn before one-shot dependency-fault publication",
		function(assertions)
			local rig = newRig(assertions, {
				participantCount = 2,
				throwAfterCommittedSpawn = true,
			})
			local waveMessageCount = #rig.waveMessages
			local senderFailureCount = rig.wavePublisher:getMetrics().senderFailureCount
			rig.waveSendFailure = true

			driveTo(rig, 100)
			assertions.isTrue(rig.committedFaultInjected)
			assertions.equal(type(rig.forcedCommittedSpawn), "table")
			local enemyMetrics = rig.enemyService:getMetrics()
			assertions.equal(enemyMetrics.lifecycleState, "Failed")
			assertions.equal(enemyMetrics.waveBoundaryStatus, "Faulted")
			local storeMetrics = rig.enemyStore:getMetrics()
			assertions.equal(storeMetrics.activeCount, 0)
			assertions.equal(storeMetrics.lifetimeCount, 1)
			assertions.equal(storeMetrics.terminalCount, 1)

			local faulted = waveSnapshot(assertions, rig)
			assertions.equal(faulted.state, "Faulted")
			assertions.equal(faulted.aggregateCounts.spawned, 1)
			assertions.equal(faulted.aggregateCounts.pending, 7)
			assertions.equal(faulted.aggregateCounts.alive, 0)
			assertions.equal(faulted.aggregateCounts.otherwiseResolved, 1)
			assertions.equal(faulted.currentCounts.spawned, 1)
			assertions.equal(faulted.currentCounts.pending, 7)
			assertions.equal(faulted.currentCounts.alive, 0)
			assertions.equal(faulted.currentCounts.otherwiseResolved, 1)
			local runtimeMetrics = rig.waveRuntime:query()
			assertions.equal(runtimeMetrics.faultCloseCount, 1)
			assertions.equal(runtimeMetrics.retainedOwnershipCount, 1)
			assertions.equal(runtimeMetrics.processedTerminalCount, 1)
			assertions.equal(#rig.waveMessages, waveMessageCount + 2)
			assertions.equal(rig.wavePublisher:getMetrics().senderFailureCount, senderFailureCount + 2)
			assertions.isTrue(deepEqual(rig.waveMessages[#rig.waveMessages - 1].snapshot, faulted))
			assertions.isTrue(deepEqual(rig.waveMessages[#rig.waveMessages].snapshot, faulted))

			expectError(assertions, rig.waveService:submitSkipVote(FIRST_USER_ID, rig.matchId, 1), "UNAVAILABLE")
			local beforeSecondPassMessages = #rig.waveMessages
			driveTo(rig, 101)
			assertions.equal(rig.waveRuntime:query().faultCloseCount, 1)
			assertions.equal(#rig.waveMessages, beforeSecondPassMessages)
			assertions.isTrue(deepEqual(waveSnapshot(assertions, rig), faulted))

			cleanup(assertions, rig)
			expectError(assertions, rig.waveService:getSnapshot(), "UNAVAILABLE")
		end
	),

	TestHarness.case("contains lifecycle callback publication capacity and clock faults", function(assertions)
		local lifecycleRig = newRig(assertions)
		lifecycleRig.lifecycleSnapshotFailure = true
		driveTo(lifecycleRig, 100)
		assertions.equal(lifecycleRig.waveService:getMetrics().terminalState, "Faulted")
		assertions.equal(lifecycleRig.waveRuntime:query().faultCode, "LIFECYCLE_FAILED")
		cleanup(assertions, lifecycleRig)

		local callbackRig = newRig(assertions)
		callbackRig.lifecycleRecipientsFailure = true
		driveTo(callbackRig, 100)
		assertions.equal(callbackRig.waveService:getMetrics().terminalState, "Faulted")
		assertions.isTrue(callbackRig.wavePublisher:getMetrics().faulted)
		cleanup(assertions, callbackRig)

		local capacityFaultRig = newRig(assertions, { enemyMaxActive = 1 })
		driveTo(capacityFaultRig, 100)
		assertions.equal(capacityFaultRig.waveService:getMetrics().terminalState, "Faulted")
		assertions.equal(capacityFaultRig.waveRuntime:query().faultCode, "CAPACITY_EXCEEDED")
		assertions.equal(capacityFaultRig.enemyStore:getMetrics().lifetimeCount, 1)
		cleanup(assertions, capacityFaultRig)

		local publicationRig = newRig(assertions, { waveMaxPublications = 1 })
		driveTo(publicationRig, 100)
		driveTo(publicationRig, 102)
		assertions.equal(publicationRig.waveService:getMetrics().terminalState, "Faulted")
		assertions.equal(publicationRig.wavePublisher:getMetrics().publicationCount, 1)
		assertions.isTrue(publicationRig.wavePublisher:getMetrics().faulted)
		cleanup(assertions, publicationRig)

		local clockRig = newRig(assertions)
		local clockCallback = clockRig.stepCallbacks[1]
		clockRig.clock.now = 99
		(clockCallback :: EnemySimulationService.StepCallback)(1)
		assertions.equal(clockRig.enemyService:getMetrics().lifecycleState, "Failed")
		assertions.equal(clockRig.waveService:getMetrics().terminalState, "Faulted")
		cleanup(assertions, clockRig)
	end),

	TestHarness.case("converges two real controllers through races gaps and delayed bootstrap", function(assertions)
		local rig = newRig(assertions, { participantCount = 2 })
		local clientOne = makeIntegratedClient(assertions, rig, FIRST_USER_ID, false)
		driveToMeasured(assertions, rig, 100)
		assertions.isTrue(deliverWaveMessages(clientOne, rig, false) >= 1)
		local clientTwo = makeIntegratedClient(assertions, rig, FIRST_USER_ID + 1, true)
		assertions.equal(clientOne.controller:getMetrics().connectionCount, 3)
		assertions.equal(clientTwo.controller:getMetrics().connectionCount, 3)
		assertions.isTrue(clientTwo.eventBeforeGetUsed)
		local initialServer = waveSnapshot(assertions, rig)
		assertions.isTrue(deepEqual(integratedClientSnapshot(assertions, clientOne), initialServer))
		assertions.isTrue(deepEqual(integratedClientSnapshot(assertions, clientTwo), initialServer))

		driveToMeasured(assertions, rig, 102)
		driveToMeasured(assertions, rig, 104)
		assertions.isTrue(deliverWaveMessages(clientOne, rig, false) >= 2)
		assertions.equal(deliverWaveMessages(clientTwo, rig, true), 1)
		local afterGap = waveSnapshot(assertions, rig)
		assertions.equal(clientTwo.controller:getMetrics().recoveryRequestCount, 1)
		assertions.equal(clientTwo.controller:getMetrics().getRequestCount, 2)
		assertions.isTrue(deepEqual(integratedClientSnapshot(assertions, clientOne), afterGap))
		assertions.isTrue(deepEqual(integratedClientSnapshot(assertions, clientTwo), afterGap))

		local diagnostics = invokeWaveDiagnostics :: (WaveController.Controller, ...unknown) -> any
		local suspended = diagnostics(clientTwo.controller, { operation = "SuspendRecovery" })
		assertions.isTrue(suspended.ok)
		assertions.isFalse(suspended.value.state.locked)
		driveToMeasured(assertions, rig, 106)
		driveToMeasured(assertions, rig, 109)
		assertions.isTrue(deliverWaveMessages(clientOne, rig, false) >= 2)
		local resumed = diagnostics(clientTwo.controller, { operation = "ResumeRecovery" })
		assertions.isTrue(resumed.ok)
		local recovered = waveSnapshot(assertions, rig)
		assertions.isTrue(deepEqual(integratedClientSnapshot(assertions, clientOne), recovered))
		assertions.isTrue(deepEqual(integratedClientSnapshot(assertions, clientTwo), recovered))
		local acceptedBeforeReplay = clientTwo.controller:getMetrics().acceptedStateCount
		assertions.isTrue(deliverWaveMessages(clientTwo, rig, false) >= 2)
		clientTwo.eventSignal:fire({ payload = recovered })
		assertions.equal(clientTwo.controller:getMetrics().acceptedStateCount, acceptedBeforeReplay)
		assertions.isTrue(deepEqual(integratedClientSnapshot(assertions, clientTwo), recovered))
		assertions.isTrue(clientTwo.controller:getMetrics().studioRecoveryUsed)
		assertions.equal(clientOne.controller:getMetrics().connectionCount, 3)
		assertions.equal(clientTwo.controller:getMetrics().connectionCount, 3)

		cleanupIntegratedClient(assertions, clientOne, initialServer)
		cleanupIntegratedClient(assertions, clientTwo, initialServer)
		cleanup(assertions, rig)
	end),
})
