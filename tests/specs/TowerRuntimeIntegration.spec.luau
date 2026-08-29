--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)

local Shared = game:GetService("ReplicatedStorage").Shared
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local MatchProtocol = require(Shared.match.MatchProtocol)
local Result = require(Shared.util.Result)
local Validation = require(Shared.util.Validation)

local TemporaryLoadoutStore = require(script.Parent.Parent.ProductionServerTowers.TemporaryLoadoutStore)
local TowerGrayboxFactory = require(script.Parent.Parent.ProductionServerTowers.TowerGrayboxFactory)
local TowerModelContract = require(script.Parent.Parent.ProductionServerTowers.TowerModelContract)
local TowerModelOwner = require(script.Parent.Parent.ProductionServerTowers.TowerModelOwner)
local TowerRuntimeService = require(script.Parent.Parent.ProductionServerTowers.TowerRuntimeService)
local TowerRuntimeStore = require(script.Parent.Parent.ProductionServerTowers.TowerRuntimeStore)

type Assertions = TestHarness.Assertions

type CanonicalFixture = {
	configuration: any,
	single: any,
	splash: any,
	support: any,
}

type ObserverState = {
	adapter: TowerRuntimeService.ParticipantObserverAdapter?,
	capturedAdapter: TowerRuntimeService.ParticipantObserverAdapter?,
	detachCount: number,
	handle: {},
	reserveCount: number,
	refreshCount: number,
	activateCount: number,
	snapshot: MatchProtocol.MatchSnapshot,
	status: "Idle" | "Reserved" | "Active" | "Detached",
	order: { string },
	setSnapshot: (self: ObserverState, snapshot: MatchProtocol.MatchSnapshot) -> (),
	advance: (self: ObserverState, snapshot: MatchProtocol.MatchSnapshot) -> unknown,
}

type WaveState = {
	boundary: TowerRuntimeService.StudioTowerBoundaryAdapter?,
	capturedBoundary: TowerRuntimeService.StudioTowerBoundaryAdapter?,
	detachCount: number,
	handle: {},
	installCount: number,
	active: boolean,
	order: { string },
	invalidateLocalClose: (self: WaveState) -> (),
}

type EngineState = {
	cloneCount: number,
	destroyCount: number,
	pivots: { [Model]: CFrame },
	workspace: Folder,
}

type Rig = {
	service: TowerRuntimeService.Service,
	definition: any,
	observer: ObserverState,
	wave: WaveState,
	engine: EngineState?,
	fixture: CanonicalFixture?,
	order: { string },
	constructorCount: number,
}

type Scope = {
	rigs: { Rig },
}

local MATCH_ID = "match:phase12-runtime-integration"
local NEGATIVE_USER_ID = -7
local POSITIVE_USER_ID = 40
local LATER_USER_ID = 90
local TOWER_EPOCH = 1

local MODEL_METHODS = table.freeze({
	"registerTemplate",
	"prepareCreate",
	"commitPreparedCreate",
	"abortPreparedCreate",
	"removeVisual",
	"recreateVisual",
	"getMetrics",
	"cleanup",
})

local LOADOUT_METHODS = table.freeze({
	"synchronizeParticipants",
	"activate",
	"getLoadout",
	"issueCreationCapability",
	"prepareCreationCapability",
	"commitPreparedCapability",
	"abortPreparedCapability",
	"getPreparedCapabilityInspector",
	"fault",
	"getMetrics",
	"cleanup",
})

local RUNTIME_METHODS = table.freeze({
	"prepareCreate",
	"commitPreparedCreate",
	"abortPreparedCreate",
	"failPreparedCreate",
	"get",
	"list",
	"remove",
	"getIdentity",
	"fault",
	"getMetrics",
	"cleanup",
})

local function success(assertions: Assertions, resultValue: any): any
	assertions.isTrue(resultValue.ok)
	assertions.isTrue(table.isfrozen(resultValue))
	if not resultValue.ok then
		error("expected integrated Phase 12 operation to succeed", 0)
	end
	return resultValue.value
end

local function expectError(assertions: Assertions, resultValue: any, code: string, operation: string?)
	assertions.isFalse(resultValue.ok)
	assertions.isTrue(table.isfrozen(resultValue))
	if not resultValue.ok then
		assertions.isTrue(table.isfrozen(resultValue.error))
		assertions.equal(resultValue.error.code, code)
		if operation ~= nil then
			assertions.equal(resultValue.error.operation, operation)
		end
	end
end

local function invoke(callback: (() -> ())?)
	if callback == nil then
		error("expected lifecycle callback", 0)
	end
	(callback :: () -> ())()
end

local function detachedFrozen(assertions: Assertions, value: unknown, visited: { [any]: boolean }?)
	assertions.isFalse(typeof(value) == "Instance")
	if type(value) ~= "table" then
		return
	end
	local seen = visited or {}
	if seen[value :: any] then
		return
	end
	seen[value :: any] = true
	assertions.isTrue(table.isfrozen(value :: any))
	for key, child in next, value :: { [any]: unknown } do
		detachedFrozen(assertions, key, seen)
		detachedFrozen(assertions, child, seen)
	end
end

local function deepEqual(left: unknown, right: unknown, visited: { [any]: any }?): boolean
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
	local seen = visited or {}
	if seen[left :: any] ~= nil then
		return seen[left :: any] == right
	end
	seen[left :: any] = right
	local leftCount = 0
	for key, child in next, left :: any do
		leftCount += 1
		if not deepEqual(child, (right :: any)[key], seen) then
			return false
		end
	end
	local rightCount = 0
	for _ in next, right :: any do
		rightCount += 1
	end
	return leftCount == rightCount
end

local function participant(userId: number, state: MatchProtocol.ParticipantState): any
	return {
		userId = userId,
		state = state,
		ready = state == "Active",
	}
end

local function matchSnapshot(revision: number, participantsValue: { any }): MatchProtocol.MatchSnapshot
	local validated = MatchProtocol.validateMatchSnapshot({
		matchId = MATCH_ID,
		revision = revision,
		state = "PreWave",
		participants = participantsValue,
	})
	if not validated.ok then
		error("failed to construct canonical integration MatchSnapshot", 0)
	end
	return validated.value
end

local function activeParticipants(): { any }
	return {
		participant(NEGATIVE_USER_ID, "Active"),
		participant(POSITIVE_USER_ID, "Active"),
	}
end

local function emptyProductionConfiguration(): any
	local raw = TowerFixtures.rawSources()
	raw.assets = {}
	raw.towers = {}
	local validated = ConfigurationValidator.validate(raw)
	if not validated.ok then
		error("failed to construct empty authenticated production root", 0)
	end
	return validated.value
end

local function fixtureFromSources(sources: any): CanonicalFixture
	local raw = TowerFixtures.rawSources()
	raw.assets = sources.assets
	raw.towers = sources.towers
	local validated = ConfigurationValidator.validate(raw)
	if not validated.ok then
		error("Wave-owned Phase 12 canonical validation failed", 0)
	end
	local configuration = validated.value
	local single = configuration.towers.byId[TowerFixtures.SINGLE_TOWER_ID]
	local splash = configuration.towers.byId[TowerFixtures.SPLASH_TOWER_ID]
	local support = configuration.towers.byId[TowerFixtures.SUPPORT_TOWER_ID]
	if
		single == nil
		or splash == nil
		or support == nil
		or configuration.towers.ordered[1] ~= single
		or configuration.towers.ordered[2] ~= splash
		or configuration.towers.ordered[3] ~= support
	then
		error("canonical Phase 12 definition identity selection failed", 0)
	end
	return table.freeze({
		configuration = configuration,
		single = single,
		splash = splash,
		support = support,
	})
end

local function newObserverAdapter(
	initialSnapshot: MatchProtocol.MatchSnapshot,
	order: { string }
): (TowerRuntimeService.MatchLifecycleAdapter, ObserverState)
	local handle = table.freeze({})
	local state = {
		adapter = nil,
		capturedAdapter = nil,
		detachCount = 0,
		handle = handle,
		reserveCount = 0,
		refreshCount = 0,
		activateCount = 0,
		snapshot = initialSnapshot,
		status = "Idle",
		order = order,
	} :: any

	function state:setSnapshot(snapshotValue: MatchProtocol.MatchSnapshot)
		self.snapshot = snapshotValue
	end

	function state:advance(snapshotValue: MatchProtocol.MatchSnapshot): unknown
		self.snapshot = snapshotValue
		local adapter = self.adapter
		if self.status ~= "Active" or adapter == nil then
			return false
		end
		return adapter:onSnapshot(snapshotValue)
	end

	local lifecycle: TowerRuntimeService.MatchLifecycleAdapter
	lifecycle = table.freeze({
		reserveParticipantObserver = function(_self, adapterValue)
			state.reserveCount += 1
			if
				state.status ~= "Idle"
				or type(adapterValue) ~= "table"
				or not table.isfrozen(adapterValue :: any)
				or type((adapterValue :: any).onSnapshot) ~= "function"
			then
				return Result.err(table.freeze({ code = "UNAVAILABLE" }))
			end
			state.adapter = adapterValue :: TowerRuntimeService.ParticipantObserverAdapter
			state.capturedAdapter = state.adapter
			state.status = "Reserved"
			return Result.ok(table.freeze({
				handle = handle,
				snapshot = state.snapshot,
			}))
		end,
		refreshParticipantObserver = function(_self, handleValue)
			state.refreshCount += 1
			if handleValue ~= handle or state.status ~= "Reserved" then
				return Result.err(table.freeze({ code = "INVALID_HANDLE" }))
			end
			return Result.ok(state.snapshot)
		end,
		activateParticipantObserver = function(_self, handleValue, expectedRevision)
			state.activateCount += 1
			if handleValue ~= handle or state.status ~= "Reserved" or expectedRevision ~= state.snapshot.revision then
				return Result.err(table.freeze({ code = "REVISION_MISMATCH" }))
			end
			state.status = "Active"
			return Result.ok(true)
		end,
		detachParticipantObserver = function(_self, handleValue)
			if handleValue ~= handle then
				return Result.err(table.freeze({ code = "INVALID_HANDLE" }))
			end
			if state.status == "Detached" then
				return Result.ok(false)
			end
			state.detachCount += 1
			table.insert(order, "observer-detach")
			state.status = "Detached"
			state.adapter = nil
			return Result.ok(true)
		end,
	})
	return lifecycle, state :: ObserverState
end

local function newWaveAdapter(order: { string }): (TowerRuntimeService.WaveRuntimeAdapter, WaveState)
	local handle = table.freeze({})
	local state = {
		boundary = nil,
		capturedBoundary = nil,
		detachCount = 0,
		handle = handle,
		installCount = 0,
		active = false,
		order = order,
	} :: any

	function state:invalidateLocalClose()
		self.active = false
		self.boundary = nil
	end

	local wave: TowerRuntimeService.WaveRuntimeAdapter
	wave = table.freeze({
		installStudioTowerBoundary = function(_self, adapterValue)
			state.installCount += 1
			if state.active or type(adapterValue) ~= "table" or not table.isfrozen(adapterValue :: any) then
				return Result.err(table.freeze({ code = "UNAVAILABLE" }))
			end
			state.boundary = adapterValue :: TowerRuntimeService.StudioTowerBoundaryAdapter
			state.capturedBoundary = state.boundary
			state.active = true
			return Result.ok(handle)
		end,
		detachStudioTowerBoundary = function(_self, handleValue)
			if handleValue ~= handle then
				return Result.err(table.freeze({ code = "INVALID_HANDLE" }))
			end
			if not state.active then
				return Result.ok(false)
			end
			state.detachCount += 1
			table.insert(order, "wave-detach")
			state.active = false
			state.boundary = nil
			return Result.ok(true)
		end,
	})
	return wave, state :: WaveState
end

local function newEngineState(): (TowerModelOwner.EngineAdapter, EngineState)
	local workspace = Instance.new("Folder")
	workspace.Name = "TowerIntegrationWorkspace"
	local state: EngineState = {
		cloneCount = 0,
		destroyCount = 0,
		pivots = setmetatable({}, { __mode = "k" }) :: any,
		workspace = workspace,
	}
	local adapter: TowerModelOwner.EngineAdapter = table.freeze({
		workspace = workspace,
		cloneModel = function(_self, modelValue)
			if typeof(modelValue) ~= "Instance" or not (modelValue :: Instance):IsA("Model") then
				return nil
			end
			local source = modelValue :: Model
			local clone = source:Clone()
			state.cloneCount += 1
			state.pivots[clone] = state.pivots[source] or CFrame.new()
			return clone
		end,
		getPivot = function(_self, modelValue)
			if typeof(modelValue) ~= "Instance" or not (modelValue :: Instance):IsA("Model") then
				return nil
			end
			return state.pivots[modelValue :: Model] or CFrame.new()
		end,
		pivotTo = function(_self, modelValue, placementValue)
			if
				typeof(modelValue) ~= "Instance"
				or not (modelValue :: Instance):IsA("Model")
				or typeof(placementValue) ~= "CFrame"
			then
				return false
			end
			state.pivots[modelValue :: Model] = placementValue :: CFrame
			return true
		end,
		createFolder = function(_self, nameValue)
			if type(nameValue) ~= "string" then
				return nil
			end
			local folder = Instance.new("Folder")
			folder.Name = nameValue
			return folder
		end,
		setParent = function(_self, instanceValue, parentValue)
			if typeof(instanceValue) ~= "Instance" or (parentValue ~= nil and typeof(parentValue) ~= "Instance") then
				return false
			end
			(instanceValue :: Instance).Parent = parentValue :: Instance?
			return (instanceValue :: Instance).Parent == parentValue
		end,
		destroy = function(_self, instanceValue)
			if typeof(instanceValue) ~= "Instance" then
				return false
			end
			(instanceValue :: Instance):Destroy()
			state.destroyCount += 1
			return true
		end,
	})
	return adapter, state
end

local function contractAdapter(configuration: any): TowerModelOwner.ContractAdapter
	return table.freeze({
		validateTemplate = function(_self, definition, model)
			return TowerModelContract.validateTemplate(configuration, definition, model)
		end,
		selectLiveVariant = function(_self, definition, level, model)
			return TowerModelContract.selectLiveVariant(configuration, definition, level, model)
		end,
		validateLive = function(_self, definition, level, model)
			return TowerModelContract.validateLive(configuration, definition, level, model)
		end,
	})
end

local function trackedAdapter(real: any, methods: { string }, kind: string, order: { string }): any
	local proxy: { [string]: any } = {}
	for _, methodNameValue in methods do
		local methodName = methodNameValue
		proxy[methodName] = function(_self: unknown, ...: any): unknown
			if methodName == "fault" then
				table.insert(order, `{kind}-fault`)
			elseif methodName == "cleanup" then
				table.insert(order, `{kind}-cleanup`)
			end
			return real[methodName](real, ...)
		end
	end
	return table.freeze(proxy)
end

local function newRig(scope: Scope, studio: boolean): Rig
	local order: { string } = {}
	local observerAdapter, observer = newObserverAdapter(matchSnapshot(1, activeParticipants()), order)
	local waveAdapter, wave = newWaveAdapter(order)
	local rig: Rig = {
		service = nil :: any,
		definition = nil,
		observer = observer,
		wave = wave,
		engine = nil,
		fixture = nil,
		order = order,
		constructorCount = 0,
	}
	local factoryConstructor = TowerGrayboxFactory.newForTests
	local ownerConstructor = TowerModelOwner.newForTests
	if factoryConstructor == nil or ownerConstructor == nil then
		error("real Phase 12 test constructors unavailable at exact Test mapping", 0)
	end

	local dependencies: TowerRuntimeService.TestDependencies = {
		matchLifecycle = observerAdapter,
		waveRuntime = waveAdapter,
		productionConfiguration = emptyProductionConfiguration(),
		isStudio = function(): unknown
			return studio
		end,
		createGrayboxFactory = function(configuration): unknown
			rig.constructorCount += 1
			return (factoryConstructor :: TowerGrayboxFactory.TestConstructor)(configuration, {
				isStudio = function()
					return true
				end,
				createInstance = function(className: string)
					return Instance.new(className)
				end,
				destroyInstance = function(instance: Instance)
					instance:Destroy()
					return true
				end,
			})
		end,
		createModelOwner = function(configuration, matchId, towerEpoch): unknown
			rig.constructorCount += 1
			local engineAdapter, engineState = newEngineState()
			rig.engine = engineState
			local resultValue = (ownerConstructor :: TowerModelOwner.TestConstructor)(
				configuration,
				matchId,
				towerEpoch,
				contractAdapter(configuration),
				engineAdapter
			)
			if not resultValue.ok then
				return resultValue
			end
			return Result.ok(trackedAdapter(resultValue.value, MODEL_METHODS, "model", order))
		end,
		createLoadoutStore = function(configuration, matchId, towerEpoch, definitions): unknown
			rig.constructorCount += 1
			local resultValue = TemporaryLoadoutStore.new(configuration, matchId, towerEpoch, definitions)
			if not resultValue.ok then
				return resultValue
			end
			return Result.ok(trackedAdapter(resultValue.value, LOADOUT_METHODS, "loadout", order))
		end,
		createRuntimeStore = function(matchId, towerEpoch, configuration, inspector): unknown
			rig.constructorCount += 1
			local resultValue = TowerRuntimeStore.new(matchId, towerEpoch, configuration, inspector)
			if not resultValue.ok then
				return resultValue
			end
			return Result.ok(trackedAdapter(resultValue.value, RUNTIME_METHODS, "runtime", order))
		end,
	}
	local service = TowerRuntimeService.newForTests(dependencies)
	rig.service = service
	rig.definition = service:getServiceDefinition()
	table.insert(scope.rigs, rig)
	invoke(rig.definition.initialize)
	invoke(rig.definition.start)
	return rig
end

local function configureStudio(assertions: Assertions, rig: Rig): CanonicalFixture
	local boundary = rig.wave.boundary
	assertions.isNotNil(boundary)
	if boundary == nil then
		error("Studio Tower boundary was not installed", 0)
	end
	table.insert(rig.order, "wave-begin")
	local sources = success(assertions, boundary:buildStudioFixtureSources())
	assertions.isTrue(table.isfrozen(sources))
	table.insert(rig.order, "tower-fixture-built")
	local fixture = fixtureFromSources(sources)
	table.insert(rig.order, "canonical-root-validated")
	local token = success(assertions, boundary:prepareStudioConfiguration(fixture.configuration, MATCH_ID))
	table.insert(rig.order, "tower-configuration-prepared")
	rig.observer:setSnapshot(matchSnapshot(2, activeParticipants()))
	assertions.isTrue(success(assertions, boundary:commitStudioConfiguration(token)))
	table.insert(rig.order, "tower-configuration-committed")
	table.insert(rig.order, "wave-commit")
	rig.fixture = fixture
	return fixture
end

local function isolated(assertions: Assertions, callback: (Scope) -> ())
	local scope: Scope = { rigs = {} }
	local completed, failureValue = pcall(callback, scope)
	for index = #scope.rigs, 1, -1 do
		local rig = scope.rigs[index]
		pcall(function()
			invoke(rig.definition.shutdown)
		end)
		if rig.engine ~= nil then
			pcall(function()
				(rig.engine :: EngineState).workspace:Destroy()
			end)
		end
	end
	if not completed then
		error(failureValue, 0)
	end
	assertions.equal(#scope.rigs, #scope.rigs)
end

local function assertLoadout(
	assertions: Assertions,
	loadout: any,
	fixture: CanonicalFixture,
	userId: number,
	identityPrefix: string
)
	detachedFrozen(assertions, loadout)
	assertions.equal(loadout.matchId, MATCH_ID)
	assertions.equal(loadout.userId, userId)
	assertions.equal(#loadout.slots, 5)
	local definitions = { fixture.single, fixture.splash, fixture.support }
	for index = 1, 5 do
		local slot = loadout.slots[index]
		assertions.equal(slot.slot, index)
		if index <= 3 then
			assertions.equal(slot.kind, "Occupied")
			assertions.equal(slot.towerId, definitions[index].id)
			assertions.equal(slot.unitId, `unit:p12-e1-{identityPrefix}-s{index}`)
		else
			assertions.equal(slot.kind, "Empty")
			assertions.isNil(slot.towerId)
			assertions.isNil(slot.unitId)
		end
	end
end

local function createTower(
	assertions: Assertions,
	service: TowerRuntimeService.Service,
	userId: number,
	slot: number,
	placementCFrame: CFrame
): any
	local capability = success(assertions, service:resolveOccupiedSlot(userId, slot))
	return success(assertions, service:trustedCreate(capability, placementCFrame))
end

local function assertInitialRuntimeTower(
	assertions: Assertions,
	snapshot: any,
	definition: any,
	userId: number,
	slot: number,
	runtimeTowerId: number,
	placementCFrame: CFrame
)
	detachedFrozen(assertions, snapshot)
	assertions.equal(snapshot.matchId, MATCH_ID)
	assertions.equal(snapshot.towerEpoch, TOWER_EPOCH)
	assertions.equal(snapshot.runtimeTowerId, runtimeTowerId)
	assertions.equal(snapshot.ownerUserId, userId)
	assertions.equal(snapshot.towerId, definition.id)
	local identityPrefix = if userId < 0 then `n{math.abs(userId)}` else `p{userId}`
	assertions.equal(snapshot.unitId, `unit:p12-e1-{identityPrefix}-s{slot}`)
	assertions.equal(snapshot.level, 1)
	assertions.equal(snapshot.targetEligibility, "AllEligibleEnemies")
	assertions.equal(snapshot.placementCFrame, placementCFrame)
	assertions.equal(snapshot.totalInvestment, definition.placementCost)
	assertions.equal(snapshot.cooldownEndsServerTime, 0)
	assertions.equal(snapshot.lifecycle, "Active")
	local expectedMode = if definition.levels[1].attack == nil then nil else definition.defaultTargetMode
	assertions.equal(snapshot.targetMode, expectedMode)
end

local function findRuntimeModel(engine: EngineState, placementCFrame: CFrame): Model?
	local root = engine.workspace:FindFirstChild(TowerModelOwner.RUNTIME_ROOT_NAME)
	if root == nil then
		return nil
	end
	for _, child in root:GetChildren() do
		if child:IsA("Model") and engine.pivots[child :: Model] == placementCFrame then
			return child :: Model
		end
	end
	return nil
end

return TestHarness.suite("TowerRuntimeIntegration", {
	TestHarness.case("keeps production dormant with only the exact lifecycle graph dependencies", function(assertions)
		isolated(assertions, function(scope)
			local rig = newRig(scope, false)
			assertions.equal(rig.definition.name, "TowerRuntime")
			assertions.equal(#rig.definition.dependencies, 3)
			assertions.equal(rig.definition.dependencies[1], "NetworkRegistry")
			assertions.equal(rig.definition.dependencies[2], "MatchLifecycle")
			assertions.equal(rig.definition.dependencies[3], "WaveRuntime")
			local metrics = rig.service:getMetrics()
			assertions.equal(metrics.lifecycleState, "Started")
			assertions.equal(metrics.ownershipState, "Dormant")
			assertions.equal(metrics.connectionCount, 0)
			assertions.equal(metrics.participantObserverCount, 0)
			assertions.equal(metrics.waveBoundaryCount, 0)
			assertions.isFalse(metrics.retainsConstructionDependencies)
			assertions.isFalse(metrics.retainsConfiguration)
			assertions.equal(rig.constructorCount, 0)
			assertions.equal(rig.wave.installCount, 0)
			assertions.equal(rig.observer.reserveCount, 0)
			expectError(assertions, rig.service:list(), "UNAVAILABLE", "list")
			assertions.isNil((rig.service :: any).registerRequest)
			assertions.isNil((rig.service :: any).registerRatePolicy)
			assertions.isNil((rig.service :: any).clientController)
		end)
	end),

	TestHarness.case("commits one Studio canonical root and deterministic five-slot loadouts", function(assertions)
		isolated(assertions, function(scope)
			local rig = newRig(scope, true)
			local fixture = configureStudio(assertions, rig)
			assertions.equal(rig.wave.installCount, 1)
			assertions.equal(rig.observer.reserveCount, 1)
			assertions.equal(rig.observer.refreshCount, 1)
			assertions.equal(rig.observer.activateCount, 1)
			assertions.equal(rig.observer.status, "Active")
			assertions.equal(rig.constructorCount, 4)
			local metrics = rig.service:getMetrics()
			assertions.equal(metrics.lifecycleState, "Started")
			assertions.equal(metrics.ownershipState, "Configured")
			assertions.isTrue(metrics.admissionOpen)
			assertions.equal(metrics.participantRevision, 2)
			assertions.equal(metrics.participantObserverCount, 1)
			assertions.equal(metrics.waveBoundaryCount, 1)
			assertions.equal(metrics.loadout.loadoutCount, 2)
			assertions.equal(metrics.loadout.occupiedSlotCount, 6)
			assertions.equal(metrics.loadout.emptySlotCount, 4)
			assertions.equal(metrics.runtime.activeCount, 0)
			assertions.equal(metrics.model.templateCount, 3)
			assertions.isFalse(metrics.model.hasRuntimeRoot)
			assertions.equal(#(rig.engine :: EngineState).workspace:GetChildren(), 0)

			assertLoadout(
				assertions,
				success(assertions, rig.service:getLoadout(NEGATIVE_USER_ID)),
				fixture,
				NEGATIVE_USER_ID,
				"n7"
			)
			assertLoadout(
				assertions,
				success(assertions, rig.service:getLoadout(POSITIVE_USER_ID)),
				fixture,
				POSITIVE_USER_ID,
				"p40"
			)
			assertions.equal(rig.order[1], "wave-begin")
			assertions.equal(rig.order[2], "tower-fixture-built")
			assertions.equal(rig.order[3], "canonical-root-validated")
			assertions.equal(rig.order[4], "tower-configuration-prepared")
			assertions.equal(rig.order[5], "tower-configuration-committed")
			assertions.equal(rig.order[6], "wave-commit")
		end)
	end),

	TestHarness.case(
		"creates all three tower domains and rejects foreign user slot capability and cap misuse",
		function(assertions)
			isolated(assertions, function(scope)
				local rig = newRig(scope, true)
				local fixture = configureStudio(assertions, rig)
				local singlePlacement = CFrame.new(1, 0, 11)
				local splashPlacement = CFrame.new(2, 0, 12)
				local supportPlacement = CFrame.new(3, 0, 13)
				local single = createTower(assertions, rig.service, NEGATIVE_USER_ID, 1, singlePlacement)
				local splash = createTower(assertions, rig.service, NEGATIVE_USER_ID, 2, splashPlacement)
				local support = createTower(assertions, rig.service, NEGATIVE_USER_ID, 3, supportPlacement)
				assertInitialRuntimeTower(assertions, single, fixture.single, NEGATIVE_USER_ID, 1, 1, singlePlacement)
				assertInitialRuntimeTower(assertions, splash, fixture.splash, NEGATIVE_USER_ID, 2, 2, splashPlacement)
				assertInitialRuntimeTower(
					assertions,
					support,
					fixture.support,
					NEGATIVE_USER_ID,
					3,
					3,
					supportPlacement
				)
				assertions.notEqual(single.runtimeTowerId, splash.runtimeTowerId)
				assertions.notEqual(single.unitId, splash.unitId)
				assertions.notEqual(single.towerId, splash.towerId)

				expectError(assertions, rig.service:resolveOccupiedSlot(999, 1), "NOT_FOUND", "resolveOccupiedSlot")
				expectError(
					assertions,
					rig.service:resolveOccupiedSlot(NEGATIVE_USER_ID, 4),
					"EMPTY_SLOT",
					"resolveOccupiedSlot"
				)
				expectError(
					assertions,
					rig.service:trustedCreate(table.freeze({}), CFrame.new()),
					"INVALID_CAPABILITY",
					"trustedCreate"
				)
				local consumed = success(assertions, rig.service:resolveOccupiedSlot(POSITIVE_USER_ID, 1))
				local positiveSingle = success(assertions, rig.service:trustedCreate(consumed, CFrame.new(20, 0, 0)))
				assertInitialRuntimeTower(
					assertions,
					positiveSingle,
					fixture.single,
					POSITIVE_USER_ID,
					1,
					4,
					CFrame.new(20, 0, 0)
				)
				expectError(
					assertions,
					rig.service:trustedCreate(consumed, CFrame.new(21, 0, 0)),
					"INVALID_CAPABILITY",
					"trustedCreate"
				)

				local supportCap = success(assertions, rig.service:resolveOccupiedSlot(NEGATIVE_USER_ID, 3))
				expectError(
					assertions,
					rig.service:trustedCreate(supportCap, CFrame.new(30, 0, 0)),
					"PLACEMENT_CAP_EXCEEDED",
					"trustedCreate"
				)
				local isolatedSupport = createTower(assertions, rig.service, POSITIVE_USER_ID, 3, CFrame.new(31, 0, 0))
				assertions.equal(isolatedSupport.ownerUserId, POSITIVE_USER_ID)
				assertions.equal(isolatedSupport.towerId, fixture.support.id)
				assertions.notEqual(isolatedSupport.unitId, support.unitId)
				assertions.equal(#success(assertions, rig.service:list()), 5)
			end)
		end
	),

	TestHarness.case(
		"keeps authoritative records stable across visual removal tamper and recreation",
		function(assertions)
			isolated(assertions, function(scope)
				local rig = newRig(scope, true)
				configureStudio(assertions, rig)
				local placement = CFrame.new(8, 1, -3)
				local created = createTower(assertions, rig.service, NEGATIVE_USER_ID, 1, placement)
				local before = success(assertions, rig.service:get(created.runtimeTowerId))
				assertions.isTrue(success(assertions, rig.service:removeVisual(created.runtimeTowerId)))
				local afterVisualRemoval = success(assertions, rig.service:get(created.runtimeTowerId))
				assertions.isTrue(deepEqual(before, afterVisualRemoval))
				local firstRecreation = success(assertions, rig.service:recreateVisual(created.runtimeTowerId))
				assertions.isTrue(firstRecreation.recreated)

				local engine = rig.engine :: EngineState
				local tampered = findRuntimeModel(engine, placement)
				assertions.isNotNil(tampered)
				if tampered == nil then
					error("expected integrated runtime model", 0)
				end
				tampered.Parent = nil
				local secondRecreation = success(assertions, rig.service:recreateVisual(created.runtimeTowerId))
				assertions.isTrue(secondRecreation.recreated)
				local replacement = findRuntimeModel(engine, placement)
				assertions.isNotNil(replacement)
				assertions.notEqual(replacement, tampered)
				assertions.isTrue(deepEqual(before, success(assertions, rig.service:get(created.runtimeTowerId))))
				expectError(assertions, rig.service:removeVisual(4_096), "NOT_FOUND", "removeVisual")
				expectError(assertions, rig.service:recreateVisual(4_096), "NOT_FOUND", "recreateVisual")
				assertions.equal(rig.service:getMetrics().runtime.activeCount, 1)
			end)
		end
	),

	TestHarness.case(
		"advances participant revisions while preserving disconnected and returned loadouts",
		function(assertions)
			isolated(assertions, function(scope)
				local rig = newRig(scope, true)
				local fixture = configureStudio(assertions, rig)
				local original = success(assertions, rig.service:getLoadout(NEGATIVE_USER_ID))
				local disconnected = matchSnapshot(3, {
					participant(NEGATIVE_USER_ID, "Disconnected"),
					participant(POSITIVE_USER_ID, "Active"),
				})
				assertions.isTrue(rig.observer:advance(disconnected))
				local retainedDisconnected = success(assertions, rig.service:getLoadout(NEGATIVE_USER_ID))
				assertions.equal(retainedDisconnected.revision, original.revision)
				assertions.equal(retainedDisconnected.slots[1].unitId, original.slots[1].unitId)

				local returned = matchSnapshot(4, {
					participant(NEGATIVE_USER_ID, "Returned"),
					participant(POSITIVE_USER_ID, "Active"),
					participant(LATER_USER_ID, "Active"),
				})
				assertions.isTrue(rig.observer:advance(returned))
				local retainedReturned = success(assertions, rig.service:getLoadout(NEGATIVE_USER_ID))
				assertions.equal(retainedReturned.revision, original.revision)
				assertions.equal(retainedReturned.slots[3].unitId, original.slots[3].unitId)
				assertLoadout(
					assertions,
					success(assertions, rig.service:getLoadout(LATER_USER_ID)),
					fixture,
					LATER_USER_ID,
					"p90"
				)
				assertions.equal(rig.service:getMetrics().participantRevision, 4)
				assertions.equal(rig.service:getMetrics().loadout.loadoutCount, 3)
			end)
		end
	),

	TestHarness.case(
		"routes only fixed Studio evidence and rejects invalid templates without runtime acceptance",
		function(assertions)
			isolated(assertions, function(scope)
				local rig = newRig(scope, true)
				configureStudio(assertions, rig)
				local boundary = rig.wave.boundary :: TowerRuntimeService.StudioTowerBoundaryAdapter
				local created = success(assertions, boundary:dispatchStudioEvidence("TowerCreateNext"))
				assertions.equal(created.operation, "TowerCreateNext")
				assertions.isTrue(created.accepted)
				local invalid = success(assertions, boundary:dispatchStudioEvidence("TowerInvalidTemplate"))
				assertions.equal(invalid.operation, "TowerInvalidTemplate")
				assertions.isFalse(invalid.accepted)
				assertions.isTrue(type(invalid.code) == "string")
				assertions.isTrue(success(assertions, boundary:dispatchStudioEvidence("TowerRemoveVisualLast")))
				local recreated = success(assertions, boundary:dispatchStudioEvidence("TowerRecreateVisualLast"))
				assertions.isTrue(recreated.recreated)
				local removed = success(assertions, boundary:dispatchStudioEvidence("TowerRemoveLast"))
				assertions.equal(removed.lifecycle, "Removed")
				expectError(
					assertions,
					boundary:dispatchStudioEvidence("TowerUpgrade"),
					"INVALID_ARGUMENT",
					"dispatchStudioEvidence"
				)
				assertions.isTrue(rig.observer:advance(matchSnapshot(3, {
					participant(NEGATIVE_USER_ID, "Active"),
					participant(POSITIVE_USER_ID, "Active"),
					participant(Validation.MAX_SAFE_INTEGER, "Spectator"),
				})))
				expectError(assertions, rig.service:getLoadout(Validation.MAX_SAFE_INTEGER), "NOT_FOUND", "getLoadout")

				local diagnostics = success(assertions, boundary:getStudioDiagnostics())
				detachedFrozen(assertions, diagnostics)
				assertions.equal(diagnostics.state, "Configured")
				assertions.equal(diagnostics.matchId, MATCH_ID)
				assertions.equal(diagnostics.towerEpoch, TOWER_EPOCH)
				assertions.equal(diagnostics.participantRevision, 3)
				assertions.equal(#diagnostics.participantUserIds, 2)
				assertions.equal(#diagnostics.loadouts, 2)
				assertions.equal(diagnostics.unauthorizedLoadout.userId, Validation.MAX_SAFE_INTEGER - 1)
				assertions.isFalse(diagnostics.unauthorizedLoadout.accepted)
				assertions.equal(diagnostics.unauthorizedLoadout.code, "NOT_FOUND")
				assertions.equal(diagnostics.unauthorizedLoadout.operation, "getLoadout")
				assertions.isTrue(table.isfrozen(diagnostics.unauthorizedLoadout))
				assertions.equal(#diagnostics.runtimeTowers, 0)
				assertions.equal(diagnostics.connectionCount, 0)
				assertions.equal(diagnostics.participantObserverCount, 1)
				assertions.equal(diagnostics.waveBoundaryCount, 1)
				assertions.equal(diagnostics.evidenceOperationCount, 5)
				assertions.equal(diagnostics.evidencePlacementCapRejectionCount, 0)
				assertions.isNil((rig.service :: any).upgrade)
				assertions.isNil((rig.service :: any).sell)
				assertions.isNil((rig.service :: any).setTargetMode)
				assertions.isNil((rig.service :: any).attack)
				assertions.isNil((rig.service :: any).damage)
				assertions.isNil((rig.service :: any).validatePlacement)
			end)
		end
	),

	TestHarness.case(
		"shuts down in reverse graph order and makes late capabilities and callbacks inert",
		function(assertions)
			isolated(assertions, function(scope)
				local rig = newRig(scope, true)
				configureStudio(assertions, rig)
				createTower(assertions, rig.service, NEGATIVE_USER_ID, 1, CFrame.new(1, 0, 0))
				local lateCapability = success(assertions, rig.service:resolveOccupiedSlot(POSITIVE_USER_ID, 2))
				local lateObserver = rig.observer.capturedAdapter :: TowerRuntimeService.ParticipantObserverAdapter
				local lateBoundary = rig.wave.capturedBoundary :: TowerRuntimeService.StudioTowerBoundaryAdapter
				table.clear(rig.order)
				invoke(rig.definition.shutdown)
				assertions.equal(rig.service:getLifecycleState(), "Shutdown")
				local expectedOrder = {
					"wave-detach",
					"observer-detach",
					"loadout-fault",
					"runtime-fault",
					"model-cleanup",
					"runtime-cleanup",
					"loadout-cleanup",
				}
				assertions.equal(#rig.order, #expectedOrder)
				for index, expected in expectedOrder do
					assertions.equal(rig.order[index], expected)
				end
				assertions.equal(rig.wave.detachCount, 1)
				assertions.equal(rig.observer.detachCount, 1)
				local metrics = rig.service:getMetrics()
				assertions.equal(metrics.ownershipState, "Cleaned")
				assertions.isFalse(metrics.admissionOpen)
				assertions.equal(metrics.participantObserverCount, 0)
				assertions.equal(metrics.waveBoundaryCount, 0)
				assertions.equal(metrics.capabilityExpectationCount, 0)
				assertions.isFalse(metrics.retainsConstructionDependencies)
				assertions.isFalse(metrics.retainsConfiguration)
				assertions.isNil(metrics.loadout)
				assertions.isNil(metrics.runtime)
				assertions.isNil(metrics.model)
				assertions.equal(#(rig.engine :: EngineState).workspace:GetChildren(), 0)

				expectError(
					assertions,
					rig.service:trustedCreate(lateCapability, CFrame.new()),
					"UNAVAILABLE",
					"trustedCreate"
				)
				assertions.isFalse(lateObserver:onSnapshot(matchSnapshot(3, activeParticipants())))
				expectError(
					assertions,
					lateBoundary:dispatchStudioEvidence("TowerCreateNext"),
					"UNAVAILABLE",
					"dispatchStudioEvidence"
				)
				local orderCount = #rig.order
				invoke(rig.definition.shutdown)
				assertions.equal(#rig.order, orderCount)
			end)
		end
	),

	TestHarness.case(
		"supports Wave-originated fixed cleanup with exact zero residue and idempotent late close",
		function(assertions)
			isolated(assertions, function(scope)
				local rig = newRig(scope, true)
				configureStudio(assertions, rig)
				createTower(assertions, rig.service, POSITIVE_USER_ID, 2, CFrame.new(7, 0, 7))
				local boundary = rig.wave.boundary :: TowerRuntimeService.StudioTowerBoundaryAdapter
				local residue = success(assertions, boundary:dispatchStudioEvidence("TowerCleanup"))
				detachedFrozen(assertions, residue)
				assertions.equal(residue.state, "Cleaned")
				assertions.equal(residue.participantObserverCount, 0)
				assertions.equal(residue.waveBoundaryCount, 0)
				assertions.equal(residue.loadoutCount, 0)
				assertions.equal(residue.unitIdCount, 0)
				assertions.equal(residue.runtimeTowerCount, 0)
				assertions.equal(residue.templateCount, 0)
				assertions.equal(residue.liveModelCount, 0)
				assertions.equal(residue.runtimeRootCount, 0)
				assertions.equal(residue.capabilityCount, 0)
				assertions.equal(residue.connectionCount, 0)
				assertions.equal(rig.wave.detachCount, 0)
				rig.wave:invalidateLocalClose()
				expectError(
					assertions,
					boundary:dispatchStudioEvidence("TowerCleanup"),
					"UNAVAILABLE",
					"dispatchStudioEvidence"
				)
				assertions.isFalse(success(assertions, boundary:closeFromWave()))
				assertions.equal(#(rig.engine :: EngineState).workspace:GetChildren(), 0)
				invoke(rig.definition.shutdown)
				assertions.equal(rig.service:getLifecycleState(), "Shutdown")
				assertions.equal(rig.wave.detachCount, 0)
			end)
		end
	),
})
