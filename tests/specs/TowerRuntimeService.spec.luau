--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local TemporaryLoadoutStore = require(script.Parent.Parent.ProductionServerTowers.TemporaryLoadoutStore)
local TowerGrayboxFactory = require(script.Parent.Parent.ProductionServerTowers.TowerGrayboxFactory)
local TowerModelContract = require(script.Parent.Parent.ProductionServerTowers.TowerModelContract)
local TowerModelOwner = require(script.Parent.Parent.ProductionServerTowers.TowerModelOwner)
local TowerRuntimeService = require(script.Parent.Parent.ProductionServerTowers.TowerRuntimeService)
local TowerRuntimeStore = require(script.Parent.Parent.ProductionServerTowers.TowerRuntimeStore)

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase12-runtime-service"
local TOWER_EPOCH = 1

local function success(assertions: Assertions, resultValue: any): any
	assertions.isTrue(resultValue.ok)
	assertions.isTrue(table.isfrozen(resultValue))
	if not resultValue.ok then
		error("expected TowerRuntimeService operation to succeed", 0)
	end
	return resultValue.value
end

local function expectError(assertions: Assertions, resultValue: any, code: string, operation: string)
	assertions.isFalse(resultValue.ok)
	assertions.isTrue(table.isfrozen(resultValue))
	if not resultValue.ok then
		assertions.isTrue(table.isfrozen(resultValue.error))
		assertions.equal(resultValue.error.code, code)
		assertions.equal(resultValue.error.operation, operation)
	end
end

local function productionConfiguration(): any
	local loaded = ConfigurationValidator.validateLoaded()
	if not loaded.ok then
		error("production configuration did not validate for TowerRuntimeService tests", 0)
	end
	return loaded.value
end

local function canonicalSnapshot(revision: number, userIds: { number }?): any
	local participants = {}
	for _, userId in userIds or { 101 } do
		table.insert(participants, {
			userId = userId,
			state = "Active",
			ready = false,
		})
	end
	local validated = MatchProtocol.validateMatchSnapshot({
		matchId = MATCH_ID,
		revision = revision,
		state = "PreWave",
		participants = participants,
	})
	if not validated.ok then
		error("test participant snapshot did not validate", 0)
	end
	return validated.value
end

local function isDeepFrozen(value: unknown, seen: { [any]: boolean }?): boolean
	if type(value) ~= "table" then
		return true
	end
	if not table.isfrozen(value :: any) or getmetatable(value :: any) ~= nil then
		return false
	end
	local visited = seen or {}
	if visited[value :: any] then
		return true
	end
	visited[value :: any] = true
	for key, child in next, value :: any do
		if not isDeepFrozen(key, visited) or not isDeepFrozen(child, visited) then
			return false
		end
	end
	return true
end

local function newMatchLifecycle(): (any, any)
	local state: any = {
		snapshot = canonicalSnapshot(1, { 101 }),
		observer = nil,
		handle = nil,
		status = "Idle",
		reservationMode = "Normal",
		refreshMode = "Normal",
		activateValue = true,
		detachReturnsFalse = false,
		reserveCount = 0,
		refreshCount = 0,
		activateCount = 0,
		detachCount = 0,
	}
	local adapter: any = {}

	function adapter:reserveParticipantObserver(observer: unknown): unknown
		state.reserveCount += 1
		local handle = table.freeze({})
		state.observer = observer
		state.handle = handle
		state.status = "Reserved"
		local reservation: any = {
			handle = handle,
			snapshot = canonicalSnapshot(
				state.snapshot.revision,
				(function(): { number }
					local users = {}
					for _, participant in state.snapshot.participants do
						table.insert(users, participant.userId)
					end
					return users
				end)()
			),
		}
		if state.reservationMode == "ExtraField" then
			reservation.extra = true
		elseif state.reservationMode == "Mutable" then
			return Result.ok(reservation)
		elseif state.reservationMode == "InexactHandle" then
			reservation.handle = table.freeze({ extra = true })
			state.handle = reservation.handle
		end
		return Result.ok(table.freeze(reservation))
	end

	function adapter:refreshParticipantObserver(handle: unknown): unknown
		state.refreshCount += 1
		if state.refreshMode == "Malformed" then
			return Result.ok("malformed")
		elseif state.refreshMode == "Throw" then
			error("injected participant refresh failure", 0)
		end
		if handle ~= state.handle or state.status ~= "Reserved" then
			return Result.err(table.freeze({ code = "INVALID_HANDLE" }))
		end
		local users = {}
		for _, participant in state.snapshot.participants do
			table.insert(users, participant.userId)
		end
		-- A fresh canonical object with the same revision is intentional: Tower
		-- must not feed it to TemporaryLoadoutStore a second time.
		state.snapshot = canonicalSnapshot(state.snapshot.revision, users)
		return Result.ok(state.snapshot)
	end

	function adapter:activateParticipantObserver(handle: unknown, expectedRevision: unknown): unknown
		state.activateCount += 1
		if handle ~= state.handle or state.status ~= "Reserved" or expectedRevision ~= state.snapshot.revision then
			return Result.err(table.freeze({ code = "REVISION_MISMATCH" }))
		end
		state.status = "Active"
		return Result.ok(state.activateValue)
	end

	function adapter:detachParticipantObserver(handle: unknown): unknown
		state.detachCount += 1
		if handle ~= state.handle then
			return Result.err(table.freeze({ code = "INVALID_HANDLE" }))
		end
		local detached = state.status == "Reserved" or state.status == "Active"
		state.status = "Detached"
		state.observer = nil
		return Result.ok(if state.detachReturnsFalse then false else detached)
	end

	function state:publish(revision: number, userIds: { number }): boolean
		self.snapshot = canonicalSnapshot(revision, userIds)
		if self.status ~= "Active" or self.observer == nil then
			return false
		end
		local accepted = self.observer:onSnapshot(self.snapshot)
		if accepted ~= true then
			self.status = "Detached"
			self.observer = nil
		end
		return accepted == true
	end

	return adapter, state
end

local function newWaveRuntime(): (any, any)
	local state: any = {
		adapter = nil,
		handle = nil,
		installCount = 0,
		detachCount = 0,
		detachValue = true,
	}
	local wave: any = {}

	function wave:installStudioTowerBoundary(boundary: unknown): unknown
		state.installCount += 1
		state.adapter = boundary
		state.handle = table.freeze({})
		return Result.ok(state.handle)
	end

	function wave:detachStudioTowerBoundary(handle: unknown): unknown
		state.detachCount += 1
		if handle ~= state.handle then
			return Result.err(table.freeze({ code = "INVALID_HANDLE" }))
		end
		if state.detachValue == true then
			state.adapter = nil
			state.handle = nil
		end
		return Result.ok(state.detachValue)
	end

	return wave, state
end

local function lifecycleStart(service: any): any
	local definition = service:getServiceDefinition()
	definition.initialize()
	definition.start()
	return definition
end

local function actualCreators(): (any, any, any, any)
	local function createFactory(configuration: unknown): unknown
		local constructor = (TowerGrayboxFactory :: any).newForTests
		if constructor == nil then
			error("TowerGrayboxFactory test constructor unavailable", 0)
		end
		return constructor(configuration, {
			isStudio = function(): unknown
				return true
			end,
			createInstance = function(className: string): unknown
				return Instance.new(className)
			end,
			destroyInstance = function(instance: Instance): unknown
				instance:Destroy()
				return true
			end,
		})
	end

	local function createOwner(configuration: any, matchId: unknown, towerEpoch: unknown): unknown
		local constructor = (TowerModelOwner :: any).newForTests
		if constructor == nil then
			error("TowerModelOwner test constructor unavailable", 0)
		end
		local isolatedWorkspace = Instance.new("Folder")
		isolatedWorkspace.Name = "TowerRuntimeServiceWorkspace"
		local pivots = setmetatable({}, { __mode = "k" }) :: { [Model]: CFrame }
		local contract = table.freeze({
			validateTemplate = function(_self: unknown, definition: unknown, model: unknown): unknown
				return TowerModelContract.validateTemplate(configuration, definition, model)
			end,
			selectLiveVariant = function(_self: unknown, definition: unknown, level: unknown, model: unknown): unknown
				return TowerModelContract.selectLiveVariant(configuration, definition, level, model)
			end,
			validateLive = function(_self: unknown, definition: unknown, level: unknown, model: unknown): unknown
				return TowerModelContract.validateLive(configuration, definition, level, model)
			end,
		})
		local engine = table.freeze({
			workspace = isolatedWorkspace,
			cloneModel = function(_self: unknown, modelValue: unknown): unknown
				if typeof(modelValue) ~= "Instance" or not (modelValue :: Instance):IsA("Model") then
					return nil
				end
				local model = modelValue :: Model
				local clone = model:Clone()
				pivots[clone] = pivots[model] or CFrame.new()
				return clone
			end,
			getPivot = function(_self: unknown, modelValue: unknown): unknown
				if typeof(modelValue) ~= "Instance" or not (modelValue :: Instance):IsA("Model") then
					return nil
				end
				return pivots[modelValue :: Model] or CFrame.new()
			end,
			pivotTo = function(_self: unknown, modelValue: unknown, placementValue: unknown): unknown
				if
					typeof(modelValue) ~= "Instance"
					or not (modelValue :: Instance):IsA("Model")
					or typeof(placementValue) ~= "CFrame"
				then
					return false
				end
				pivots[modelValue :: Model] = placementValue :: CFrame
				return true
			end,
			createFolder = function(_self: unknown, nameValue: unknown): unknown
				if type(nameValue) ~= "string" then
					return nil
				end
				local folder = Instance.new("Folder")
				folder.Name = nameValue
				return folder
			end,
			setParent = function(_self: unknown, instanceValue: unknown, parentValue: unknown): unknown
				if
					typeof(instanceValue) ~= "Instance"
					or (parentValue ~= nil and typeof(parentValue) ~= "Instance")
				then
					return false
				end
				(instanceValue :: Instance).Parent = parentValue :: Instance?
				return (instanceValue :: Instance).Parent == parentValue
			end,
			destroy = function(_self: unknown, instanceValue: unknown): unknown
				if typeof(instanceValue) ~= "Instance" then
					return false
				end
				pivots[instanceValue :: any] = nil
				(instanceValue :: Instance):Destroy()
				return true
			end,
		})
		return constructor(configuration, matchId, towerEpoch, contract, engine)
	end

	return createFactory, createOwner, TemporaryLoadoutStore.new, TowerRuntimeStore.new
end

local function newService(matchLifecycle: any, waveRuntime: any, isStudio: boolean, creators: { any }?): any
	local selected = creators or { actualCreators() }
	return TowerRuntimeService.newForTests({
		matchLifecycle = matchLifecycle,
		waveRuntime = waveRuntime,
		productionConfiguration = productionConfiguration(),
		isStudio = function(): unknown
			return isStudio
		end,
		createGrayboxFactory = selected[1],
		createModelOwner = selected[2],
		createLoadoutStore = selected[3],
		createRuntimeStore = selected[4],
	})
end

local function configure(service: any, waveState: any, fixture: any): any
	local definition = lifecycleStart(service)
	local boundary = waveState.adapter
	if boundary == nil then
		error("TowerRuntimeService did not install its Studio boundary", 0)
	end
	local sources = boundary:buildStudioFixtureSources()
	if not sources.ok then
		error("TowerRuntimeService fixture build failed", 0)
	end
	local prepared = boundary:prepareStudioConfiguration(fixture.configuration, MATCH_ID)
	if not prepared.ok then
		error("TowerRuntimeService configuration prepare failed", 0)
	end
	local committed = boundary:commitStudioConfiguration(prepared.value)
	if not committed.ok or committed.value ~= true then
		error("TowerRuntimeService configuration commit failed", 0)
	end
	return definition
end

local function containsCall(log: { string }, expected: string): boolean
	for _, value in log do
		if value == expected then
			return true
		end
	end
	return false
end

local function fakeCreators(fixture: any): ({ any }, any)
	local state: any = {
		log = {},
		triggerName = nil,
		triggerCallback = nil,
		factoryMode = "Normal",
		factoryCleanupCount = 0,
		trackingFolder = Instance.new("Folder"),
		nextRuntimeTowerId = 1,
		preparedCapability = nil,
		preparedRuntime = nil,
		preparedVisual = nil,
		records = {},
		faulted = false,
		cleaned = false,
		loadoutSyncValue = true,
		loadoutSyncFails = false,
		loadoutActivateValue = true,
		loadoutProbeMode = "ExactNotFound",
		loadoutUserIds = {},
		childFailureTrigger = nil,
		childFailureMode = nil,
		loadoutAbortFailureMode = nil,
		loadoutChildFaulted = false,
		runtimeChildFaulted = false,
		loadoutCleaned = false,
		runtimeCleaned = false,
	}

	local function mark(name: string)
		table.insert(state.log, name)
		if state.triggerName == name and state.triggerCallback ~= nil then
			local callback = state.triggerCallback
			state.triggerName = nil
			state.triggerCallback = nil
			callback()
		end
	end

	local function injectedChildFailure(name: string, child: "Loadout" | "Runtime", operation: string): unknown?
		if state.childFailureTrigger ~= name then
			return nil
		end
		local mode = state.childFailureMode
		if mode == "Throw" then
			error("injected child throw", 0)
		elseif mode == "Yield" then
			coroutine.yield()
			return nil
		elseif mode == "Fatal" then
			if child == "Loadout" then
				state.loadoutChildFaulted = true
			else
				state.runtimeChildFaulted = true
			end
			return Result.err(table.freeze({ code = "COUNTER_FAULT", operation = operation }))
		elseif mode == "Recoverable" then
			return Result.err(table.freeze({ code = "INVALID_CFRAME", operation = operation }))
		end
		return nil
	end

	local factory: any = {}
	function factory:createAllTemplates(): unknown
		mark("factory.createAll")
		local ordered = {}
		local byTowerId = {}
		for index, definition in fixture.configuration.towers.ordered do
			local model = Instance.new("Model")
			model.Name = `FakeTemplate{index}`
			if state.factoryMode ~= "Normal" then
				model.Parent = state.trackingFolder
			end
			ordered[index] = model
			byTowerId[definition.id] = model
		end
		if state.factoryMode == "SparseOrdered" then
			ordered[2] = nil
		elseif state.factoryMode == "ExtraById" then
			byTowerId.extra = ordered[1]
		end
		local value: any = {
			ordered = table.freeze(ordered),
			byTowerId = table.freeze(byTowerId),
		}
		if state.factoryMode == "ExtraTop" then
			value.extra = true
		end
		return Result.ok(table.freeze(value))
	end
	function factory:cleanup(): unknown
		mark("factory.cleanup")
		state.factoryCleanupCount += 1
		return Result.ok(true)
	end
	function factory:getState(): unknown
		return "Ready"
	end

	local owner: any = {}
	function owner:registerTemplate(_definition: unknown, _model: unknown): unknown
		mark("owner.register")
		return Result.ok(true)
	end
	function owner:prepareCreate(snapshot: unknown): unknown
		mark("owner.prepare")
		local token = table.freeze({})
		state.preparedVisual = { token = token, snapshot = snapshot }
		return Result.ok(table.freeze({
			token = token,
			runtimeTowerId = (snapshot :: any).runtimeTowerId,
		}))
	end
	function owner:commitPreparedCreate(token: unknown): unknown
		mark("owner.commit")
		if state.preparedVisual == nil or token ~= state.preparedVisual.token then
			return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
		end
		local snapshot = state.preparedVisual.snapshot
		state.preparedVisual = nil
		return Result.ok(table.freeze({
			runtimeTowerId = snapshot.runtimeTowerId,
			status = "Live",
			recreated = false,
		}))
	end
	function owner:abortPreparedCreate(_token: unknown): unknown
		mark("owner.abort")
		state.preparedVisual = nil
		return Result.ok(true)
	end
	function owner:removeVisual(_runtimeTowerId: unknown): unknown
		mark("owner.remove")
		return Result.ok(true)
	end
	function owner:recreateVisual(snapshot: unknown): unknown
		mark("owner.recreate")
		return Result.ok(table.freeze({
			runtimeTowerId = (snapshot :: any).runtimeTowerId,
			status = "Live",
			recreated = true,
		}))
	end
	function owner:getMetrics(): unknown
		mark("owner.metrics")
		return table.freeze({ templateCount = 3, liveModelCount = 0, runtimeRootCount = 0 })
	end
	function owner:cleanup(): unknown
		mark("owner.cleanup")
		state.cleaned = true
		return Result.ok(true)
	end

	local loadout: any = {}
	function loadout:synchronizeParticipants(snapshot: unknown): unknown
		mark("loadout.sync")
		if state.loadoutSyncFails then
			return Result.err(table.freeze({ code = "INJECTED_FAILURE" }))
		end
		if type(snapshot) == "table" and type((snapshot :: any).participants) == "table" then
			for _, participant in (snapshot :: any).participants do
				if type(participant) == "table" and (participant :: any).state == "Active" then
					state.loadoutUserIds[(participant :: any).userId] = true
				end
			end
		end
		return Result.ok(state.loadoutSyncValue)
	end
	function loadout:activate(): unknown
		mark("loadout.activate")
		return Result.ok(state.loadoutActivateValue)
	end
	function loadout:getLoadout(userId: unknown): unknown
		mark("loadout.get")
		local injected = injectedChildFailure("loadout.get", "Loadout", "getLoadout")
		if injected ~= nil then
			return injected
		end
		if state.loadoutUserIds[userId] == true then
			return Result.ok(table.freeze({ userId = userId, revision = 1, slots = table.freeze({}) }))
		end
		local exactError = table.freeze({ code = "NOT_FOUND", operation = "getLoadout" })
		if state.loadoutProbeMode == "ExactNotFound" then
			return Result.err(exactError)
		elseif state.loadoutProbeMode == "Accepted" then
			return Result.ok(table.freeze({ userId = userId, revision = 1, slots = table.freeze({}) }))
		elseif state.loadoutProbeMode == "WrongCode" then
			return Result.err(table.freeze({ code = "UNAVAILABLE", operation = "getLoadout" }))
		elseif state.loadoutProbeMode == "WrongOperation" then
			return Result.err(table.freeze({ code = "NOT_FOUND", operation = "issueCreationCapability" }))
		elseif state.loadoutProbeMode == "ExtraErrorField" then
			return Result.err(table.freeze({ code = "NOT_FOUND", operation = "getLoadout", extra = true }))
		elseif state.loadoutProbeMode == "MutableError" then
			return Result.err({ code = "NOT_FOUND", operation = "getLoadout" })
		elseif state.loadoutProbeMode == "ExtraResultField" then
			return table.freeze({ ok = false, error = exactError, extra = true })
		elseif state.loadoutProbeMode == "Yield" then
			coroutine.yield()
			return Result.err(exactError)
		end
		error("unknown fake loadout probe mode", 0)
	end
	function loadout:issueCreationCapability(_userId: unknown, _slot: unknown): unknown
		mark("loadout.issue")
		local injected = injectedChildFailure("loadout.issue", "Loadout", "issueCreationCapability")
		if injected ~= nil then
			return injected
		end
		return Result.ok(table.freeze({}))
	end
	function loadout:prepareCreationCapability(capability: unknown): unknown
		mark("loadout.prepare")
		local injected = injectedChildFailure("loadout.prepare", "Loadout", "prepareCreationCapability")
		if injected ~= nil then
			return injected
		end
		local token = table.freeze({})
		state.preparedCapability = { token = token, capability = capability }
		return Result.ok(token)
	end
	function loadout:commitPreparedCapability(token: unknown): unknown
		mark("loadout.commit")
		if state.preparedCapability == nil or token ~= state.preparedCapability.token then
			return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
		end
		state.preparedCapability = nil
		return Result.ok(true)
	end
	function loadout:abortPreparedCapability(_token: unknown): unknown
		mark("loadout.abort")
		local mode = state.loadoutAbortFailureMode
		if mode == "Throw" then
			error("injected abort throw", 0)
		elseif mode == "Yield" then
			coroutine.yield()
			return nil
		elseif mode == "Fatal" then
			state.loadoutChildFaulted = true
			return Result.err(table.freeze({ code = "COUNTER_FAULT", operation = "abortPreparedCapability" }))
		end
		state.preparedCapability = nil
		return Result.ok(true)
	end
	function loadout:getPreparedCapabilityInspector(): unknown
		mark("loadout.inspector")
		return Result.ok(function(): unknown
			return Result.err(table.freeze({ code = "UNUSED" }))
		end)
	end
	function loadout:fault(): unknown
		mark("loadout.fault")
		state.faulted = true
		state.loadoutChildFaulted = true
		state.preparedCapability = nil
		return Result.ok(true)
	end
	function loadout:getMetrics(): unknown
		mark("loadout.metrics")
		return table.freeze({
			loadoutCount = 1,
			capabilityCount = 0,
			faulted = state.loadoutChildFaulted,
			cleaned = state.loadoutCleaned,
		})
	end
	function loadout:cleanup(): unknown
		mark("loadout.cleanup")
		state.cleaned = true
		state.loadoutCleaned = true
		return Result.ok(true)
	end

	local runtime: any = {}
	function runtime:prepareCreate(
		_preparedCapability: unknown,
		expectedOwnerUserId: unknown,
		expectedSlot: unknown,
		placementCFrame: unknown
	): unknown
		mark("runtime.prepare")
		local injected = injectedChildFailure("runtime.prepare", "Runtime", "prepareCreate")
		if injected ~= nil then
			return injected
		end
		local slot = expectedSlot :: number
		local definition = fixture.configuration.towers.ordered[slot]
		local runtimeTowerId = state.nextRuntimeTowerId
		local record: any = {
			matchId = MATCH_ID,
			towerEpoch = TOWER_EPOCH,
			runtimeTowerId = runtimeTowerId,
			ownerUserId = expectedOwnerUserId,
			towerId = definition.id,
			unitId = `unit:p12-e1-p{expectedOwnerUserId}-s{slot}`,
			level = 1,
			targetEligibility = "AllEligibleEnemies",
			placementCFrame = placementCFrame,
			totalInvestment = definition.placementCost,
			cooldownEndsServerTime = 0,
			lifecycle = "Active",
		}
		if definition.levels[1].attack ~= nil then
			record.targetMode = definition.defaultTargetMode
		end
		local token = table.freeze({})
		state.preparedRuntime = {
			token = token,
			snapshot = table.freeze(record),
		}
		return Result.ok(table.freeze({
			token = token,
			plannedSnapshot = state.preparedRuntime.snapshot,
		}))
	end
	function runtime:commitPreparedCreate(token: unknown): unknown
		mark("runtime.commit")
		if state.preparedRuntime == nil or token ~= state.preparedRuntime.token then
			return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
		end
		local snapshot = state.preparedRuntime.snapshot
		state.records[snapshot.runtimeTowerId] = snapshot
		state.nextRuntimeTowerId += 1
		state.preparedRuntime = nil
		return Result.ok(snapshot)
	end
	function runtime:abortPreparedCreate(_token: unknown): unknown
		mark("runtime.abort")
		state.preparedRuntime = nil
		return Result.ok(true)
	end
	function runtime:failPreparedCreate(_token: unknown): unknown
		mark("runtime.fail")
		state.preparedRuntime = nil
		return Result.ok(true)
	end
	function runtime:get(runtimeTowerId: unknown): unknown
		mark("runtime.get")
		local injected = injectedChildFailure("runtime.get", "Runtime", "get")
		if injected ~= nil then
			return injected
		end
		local record = state.records[runtimeTowerId]
		return if record == nil then Result.err(table.freeze({ code = "NOT_FOUND" })) else Result.ok(record)
	end
	function runtime:list(): unknown
		mark("runtime.list")
		local injected = injectedChildFailure("runtime.list", "Runtime", "list")
		if injected ~= nil then
			return injected
		end
		local values = {}
		for runtimeTowerId = 1, state.nextRuntimeTowerId - 1 do
			local record = state.records[runtimeTowerId]
			if record ~= nil then
				table.insert(values, record)
			end
		end
		return Result.ok(table.freeze(values))
	end
	function runtime:remove(runtimeTowerId: unknown): unknown
		mark("runtime.remove")
		local record = state.records[runtimeTowerId]
		if record == nil then
			return Result.err(table.freeze({ code = "NOT_FOUND" }))
		end
		state.records[runtimeTowerId] = nil
		return Result.ok(record)
	end
	function runtime:getIdentity(): unknown
		return Result.ok(table.freeze({ matchId = MATCH_ID, towerEpoch = TOWER_EPOCH }))
	end
	function runtime:fault(): unknown
		mark("runtime.fault")
		state.faulted = true
		state.runtimeChildFaulted = true
		return Result.ok(true)
	end
	function runtime:getMetrics(): unknown
		mark("runtime.metrics")
		local count = 0
		for _ in state.records do
			count += 1
		end
		return table.freeze({
			runtimeTowerCount = count,
			faulted = state.runtimeChildFaulted,
			cleaned = state.runtimeCleaned,
		})
	end
	function runtime:cleanup(): unknown
		mark("runtime.cleanup")
		state.cleaned = true
		state.runtimeCleaned = true
		table.clear(state.records)
		return Result.ok(true)
	end

	local creators = {
		function(_configuration: unknown): unknown
			mark("factory.new")
			return Result.ok(factory)
		end,
		function(_configuration: unknown, _matchId: unknown, _towerEpoch: unknown): unknown
			mark("owner.new")
			return Result.ok(owner)
		end,
		function(_configuration: unknown, _matchId: unknown, _towerEpoch: unknown, _definitions: unknown): unknown
			mark("loadout.new")
			return Result.ok(loadout)
		end,
		function(_matchId: unknown, _towerEpoch: unknown, _configuration: unknown, _inspector: unknown): unknown
			mark("runtime.new")
			return Result.ok(runtime)
		end,
	}
	return creators, state
end

local function configureFake(assertions: Assertions, userIds: { number }?): any
	local fixture = TowerFixtures.createAuthenticatedFixture()
	local matchLifecycle, matchState = newMatchLifecycle()
	if userIds ~= nil then
		matchState.snapshot = canonicalSnapshot(1, userIds)
	end
	local waveRuntime, waveState = newWaveRuntime()
	local creators, componentState = fakeCreators(fixture)
	local service = newService(matchLifecycle, waveRuntime, true, creators)
	local definition = configure(service, waveState, fixture)
	assertions.equal(service:getMetrics().ownershipState, "Configured")
	return {
		fixture = fixture,
		matchState = matchState,
		waveState = waveState,
		componentState = componentState,
		service = service,
		definition = definition,
	}
end

local function cleanupContext(context: any)
	pcall(context.definition.shutdown)
	pcall(function()
		context.componentState.trackingFolder:Destroy()
	end)
end

local function fakeCreate(assertions: Assertions, context: any): any
	local capability = success(assertions, context.service:resolveOccupiedSlot(101, 1))
	return success(assertions, context.service:trustedCreate(capability, CFrame.new(1, 0, 2)))
end

return TestHarness.suite("TowerRuntimeService", {
	TestHarness.case("declares exact lifecycle dependencies and remains dormant in production", function(assertions)
		local matchLifecycle = newMatchLifecycle()
		local waveRuntime, waveState = newWaveRuntime()
		local creators, componentState = fakeCreators(TowerFixtures.createAuthenticatedFixture())
		local service = newService(matchLifecycle, waveRuntime, false, creators)
		local definition = service:getServiceDefinition()
		assertions.equal(definition.name, "TowerRuntime")
		assertions.equal(#definition.dependencies, 3)
		assertions.equal(definition.dependencies[1], "NetworkRegistry")
		assertions.equal(definition.dependencies[2], "MatchLifecycle")
		assertions.equal(definition.dependencies[3], "WaveRuntime")
		definition.initialize()
		definition.start()
		local metrics = service:getMetrics()
		assertions.equal(metrics.ownershipState, "Dormant")
		assertions.equal(metrics.waveBoundaryCount, 0)
		assertions.isFalse(metrics.retainsConstructionDependencies)
		assertions.equal(waveState.installCount, 0)
		expectError(assertions, service:list(), "UNAVAILABLE", "list")
		definition.shutdown()
		assertions.equal(service:getLifecycleState(), "Shutdown")
		assertions.equal(waveState.detachCount, 0)
		componentState.trackingFolder:Destroy()
	end),

	TestHarness.case("runs the real canonical transaction and trusted runtime surface", function(assertions)
		local fixture = TowerFixtures.createAuthenticatedFixture()
		local matchLifecycle, matchState = newMatchLifecycle()
		local waveRuntime, waveState = newWaveRuntime()
		local service = newService(matchLifecycle, waveRuntime, true)
		local definition = lifecycleStart(service)
		local boundary = waveState.adapter
		assertions.isTrue(table.isfrozen(boundary))
		local fieldCount = 0
		for _ in boundary do
			fieldCount += 1
		end
		assertions.equal(fieldCount, 6)
		local built = success(assertions, boundary:buildStudioFixtureSources())
		assertions.equal(#built.assets, 6)
		assertions.equal(#built.towers, 3)
		assertions.isTrue(isDeepFrozen(built))
		expectError(assertions, boundary:buildStudioFixtureSources(), "WRONG_STATE", "buildStudioFixtureSources")
		local prepared = success(assertions, boundary:prepareStudioConfiguration(fixture.configuration, MATCH_ID))
		assertions.isTrue(table.isfrozen(prepared))
		assertions.equal(matchState.reserveCount, 1)
		assertions.isTrue(success(assertions, boundary:commitStudioConfiguration(prepared)))
		assertions.equal(matchState.refreshCount, 1)
		assertions.equal(matchState.activateCount, 1)
		assertions.equal(service:getMetrics().participantRevision, 1)
		local discardedCapability = success(assertions, service:resolveOccupiedSlot(101, 1))
		assertions.isTrue(success(assertions, service:trustedDiscardCapability(discardedCapability)))
		assertions.equal(service:getMetrics().capabilityExpectationCount, 0)
		expectError(
			assertions,
			service:trustedCreate(discardedCapability, CFrame.new()),
			"INVALID_CAPABILITY",
			"trustedCreate"
		)

		local firstLoadout = success(assertions, service:getLoadout(101))
		assertions.equal(firstLoadout.userId, 101)
		assertions.equal(#firstLoadout.slots, 5)
		assertions.isTrue(matchState:publish(2, { 101, 202 }))
		assertions.equal(success(assertions, service:getLoadout(202)).userId, 202)

		local capability = success(assertions, service:resolveOccupiedSlot(101, 1))
		local created = success(assertions, service:trustedCreate(capability, CFrame.new(3, 0, 4)))
		assertions.equal(created.ownerUserId, 101)
		assertions.equal(created.towerId, fixture.single.id)
		local queried = success(assertions, service:get(created.runtimeTowerId))
		assertions.notEqual(queried, created)
		assertions.equal(queried.runtimeTowerId, created.runtimeTowerId)
		assertions.equal(queried.ownerUserId, created.ownerUserId)
		assertions.equal(queried.towerId, created.towerId)
		assertions.equal(queried.placementCFrame, created.placementCFrame)
		assertions.equal(#success(assertions, service:list()), 1)
		local placementView = success(assertions, service:getPlacementView(101))
		assertions.equal(placementView.matchId, MATCH_ID)
		assertions.equal(placementView.towerEpoch, 1)
		assertions.equal(placementView.userId, 101)
		assertions.equal(placementView.loadoutRevision, firstLoadout.revision)
		assertions.equal(#placementView.slots, 5)
		assertions.equal(placementView.slots[1].towerId, fixture.single.id)
		assertions.equal(placementView.slots[1].footprintRadiusStuds, fixture.single.footprintRadiusStuds)
		assertions.equal(placementView.slots[1].rangeStuds, fixture.single.levels[1].rangeStuds)
		assertions.isNil((placementView.slots[1] :: any).unitId)
		assertions.isNil((placementView.slots[1] :: any).modelAssetKey)
		assertions.equal(#placementView.towers, 1)
		assertions.equal(placementView.towers[1].runtimeTowerId, created.runtimeTowerId)
		assertions.equal(placementView.towers[1].placementCFrame, created.placementCFrame)
		assertions.equal(placementView.towers[1].footprintRadiusStuds, fixture.single.footprintRadiusStuds)
		assertions.isTrue(isDeepFrozen(placementView))
		assertions.isTrue(success(assertions, service:removeVisual(created.runtimeTowerId)))
		local recreated = success(assertions, service:recreateVisual(created.runtimeTowerId))
		assertions.isTrue(recreated.recreated)
		assertions.equal(
			success(assertions, service:trustedRemove(created.runtimeTowerId)).runtimeTowerId,
			created.runtimeTowerId
		)
		assertions.equal(#success(assertions, service:getPlacementView(101)).towers, 0)
		expectError(assertions, service:trustedCreate(capability, CFrame.new()), "INVALID_CAPABILITY", "trustedCreate")

		assertions.isTrue(success(assertions, boundary:dispatchStudioEvidence("TowerCreateNext")).accepted)
		assertions.isTrue(success(assertions, boundary:dispatchStudioEvidence("TowerRemoveVisualLast")))
		assertions.isTrue(success(assertions, boundary:dispatchStudioEvidence("TowerRecreateVisualLast")).recreated)
		local invalidTemplate = success(assertions, boundary:dispatchStudioEvidence("TowerInvalidTemplate"))
		assertions.isFalse(invalidTemplate.accepted)
		expectError(
			assertions,
			boundary:dispatchStudioEvidence("TowerUpgradeLast"),
			"INVALID_ARGUMENT",
			"dispatchStudioEvidence"
		)
		local diagnostics = success(assertions, boundary:getStudioDiagnostics())
		assertions.equal(diagnostics.state, "Configured")
		assertions.equal(diagnostics.participantRevision, 2)
		assertions.equal(#diagnostics.participantUserIds, 2)
		assertions.equal(diagnostics.unauthorizedLoadout.userId, Validation.MAX_SAFE_INTEGER)
		assertions.isFalse(diagnostics.unauthorizedLoadout.accepted)
		assertions.equal(diagnostics.unauthorizedLoadout.code, "NOT_FOUND")
		assertions.equal(diagnostics.unauthorizedLoadout.operation, "getLoadout")
		assertions.equal(diagnostics.connectionCount, 0)
		assertions.equal(diagnostics.participantObserverCount, 1)
		assertions.equal(diagnostics.waveBoundaryCount, 1)
		assertions.isTrue(isDeepFrozen(diagnostics))
		local residue = success(assertions, boundary:dispatchStudioEvidence("TowerCleanup"))
		assertions.equal(residue.state, "Cleaned")
		assertions.equal(residue.runtimeTowerCount, 0)
		assertions.equal(residue.participantObserverCount, 0)
		local cleanedMetrics = service:getMetrics()
		assertions.equal(cleanedMetrics.ownershipState, "Cleaned")
		assertions.isFalse(cleanedMetrics.retainsConstructionDependencies)
		assertions.isFalse(cleanedMetrics.retainsConfiguration)
		definition.shutdown()
		assertions.equal(service:getLifecycleState(), "Shutdown")
		assertions.equal(waveState.detachCount, 0)
	end),

	TestHarness.case(
		"selects a bounded nonparticipant probe and rejects inexact loadout evidence",
		function(assertions)
			local maximum = Validation.MAX_SAFE_INTEGER
			local selectedContext = configureFake(assertions, {
				maximum - 3,
				maximum - 2,
				maximum - 1,
				maximum,
			})
			local selectedBoundary = selectedContext.waveState.adapter
			local diagnostics = success(assertions, selectedBoundary:getStudioDiagnostics())
			assertions.equal(diagnostics.unauthorizedLoadout.userId, maximum - 4)
			assertions.isFalse(diagnostics.unauthorizedLoadout.accepted)
			assertions.equal(diagnostics.unauthorizedLoadout.code, "NOT_FOUND")
			assertions.equal(diagnostics.unauthorizedLoadout.operation, "getLoadout")
			assertions.isTrue(table.isfrozen(diagnostics.unauthorizedLoadout))
			assertions.equal(diagnostics.participantObserverCount, 1)
			assertions.equal(diagnostics.waveBoundaryCount, 1)
			cleanupContext(selectedContext)

			for _, mode in
				{
					"Accepted",
					"WrongCode",
					"WrongOperation",
					"ExtraErrorField",
					"MutableError",
					"ExtraResultField",
					"Yield",
				}
			do
				local context = configureFake(assertions)
				context.componentState.loadoutProbeMode = mode
				expectError(
					assertions,
					context.waveState.adapter:getStudioDiagnostics(),
					"DIAGNOSTICS_FAILED",
					"getStudioDiagnostics"
				)
				assertions.equal(context.service:getMetrics().ownershipState, "Faulted")
				assertions.isTrue(context.componentState.faulted)
				assertions.isFalse(context.service:getMetrics().operationActive)
				cleanupContext(context)
			end

			local reentrant = configureFake(assertions)
			reentrant.componentState.triggerName = "loadout.get"
			reentrant.componentState.triggerCallback = function()
				expectError(assertions, reentrant.service:list(), "REENTRANT", "list")
			end
			expectError(
				assertions,
				reentrant.waveState.adapter:getStudioDiagnostics(),
				"REENTRANT",
				"getStudioDiagnostics"
			)
			assertions.equal(reentrant.service:getMetrics().ownershipState, "Faulted")
			assertions.isFalse(reentrant.service:getMetrics().operationActive)
			cleanupContext(reentrant)
		end
	),

	TestHarness.case(
		"rejects malformed reservations and exact factory result shapes without residue",
		function(assertions)
			for _, reservationMode in { "ExtraField", "Mutable", "InexactHandle" } do
				local fixture = TowerFixtures.createAuthenticatedFixture()
				local matchLifecycle, matchState = newMatchLifecycle()
				matchState.reservationMode = reservationMode
				local waveRuntime, waveState = newWaveRuntime()
				local creators, componentState = fakeCreators(fixture)
				local service = newService(matchLifecycle, waveRuntime, true, creators)
				local definition = lifecycleStart(service)
				local boundary = waveState.adapter
				success(assertions, boundary:buildStudioFixtureSources())
				expectError(
					assertions,
					boundary:prepareStudioConfiguration(fixture.configuration, MATCH_ID),
					"OBSERVER_RESERVATION_FAILED",
					"prepareStudioConfiguration"
				)
				assertions.equal(service:getMetrics().ownershipState, "Faulted")
				assertions.equal(service:getMetrics().participantObserverCount, 0)
				if reservationMode ~= "InexactHandle" then
					assertions.equal(matchState.detachCount, 1)
				end
				definition.shutdown()
				componentState.trackingFolder:Destroy()
			end

			for _, factoryMode in { "ExtraTop", "SparseOrdered", "ExtraById" } do
				local fixture = TowerFixtures.createAuthenticatedFixture()
				local matchLifecycle = newMatchLifecycle()
				local waveRuntime, waveState = newWaveRuntime()
				local creators, componentState = fakeCreators(fixture)
				componentState.factoryMode = factoryMode
				local service = newService(matchLifecycle, waveRuntime, true, creators)
				local definition = lifecycleStart(service)
				local boundary = waveState.adapter
				success(assertions, boundary:buildStudioFixtureSources())
				expectError(
					assertions,
					boundary:prepareStudioConfiguration(fixture.configuration, MATCH_ID),
					"TEMPLATE_CREATION_FAILED",
					"prepareStudioConfiguration"
				)
				assertions.equal(componentState.factoryCleanupCount, 1)
				assertions.equal(#componentState.trackingFolder:GetChildren(), 0)
				assertions.isFalse(service:getMetrics().retainsConfiguration)
				definition.shutdown()
				componentState.trackingFolder:Destroy()
			end
		end
	),

	TestHarness.case(
		"attributes every configuration commit fault and removes all prepared residue",
		function(assertions)
			local faultCases = {
				{
					code = "OBSERVER_REFRESH_FAILED",
					arm = function(matchState: any, _componentState: any)
						matchState.refreshMode = "Malformed"
					end,
				},
				{
					code = "PARTICIPANT_SYNCHRONIZATION_FAILED",
					arm = function(matchState: any, componentState: any)
						matchState.snapshot = canonicalSnapshot(2, { 101, 202 })
						componentState.loadoutSyncFails = true
					end,
				},
				{
					code = "LOADOUT_ACTIVATION_FAILED",
					arm = function(_matchState: any, componentState: any)
						componentState.loadoutActivateValue = false
					end,
				},
				{
					code = "OBSERVER_ACTIVATION_FAILED",
					arm = function(matchState: any, _componentState: any)
						matchState.activateValue = false
					end,
				},
			}

			for _, faultCase in faultCases do
				local fixture = TowerFixtures.createAuthenticatedFixture()
				local matchLifecycle, matchState = newMatchLifecycle()
				local waveRuntime, waveState = newWaveRuntime()
				local creators, componentState = fakeCreators(fixture)
				local service = newService(matchLifecycle, waveRuntime, true, creators)
				local definition = lifecycleStart(service)
				local boundary = waveState.adapter
				success(assertions, boundary:buildStudioFixtureSources())
				local token = success(assertions, boundary:prepareStudioConfiguration(fixture.configuration, MATCH_ID))
				faultCase.arm(matchState, componentState)
				expectError(
					assertions,
					boundary:commitStudioConfiguration(token),
					faultCase.code,
					"commitStudioConfiguration"
				)
				local metrics = service:getMetrics()
				assertions.equal(metrics.ownershipState, "Faulted")
				assertions.equal(metrics.participantObserverCount, 0)
				assertions.equal(metrics.capabilityExpectationCount, 0)
				assertions.isFalse(metrics.retainsConfiguration)
				assertions.isTrue(componentState.cleaned)
				assertions.equal(matchState.detachCount, 1)
				definition.shutdown()
				componentState.trackingFolder:Destroy()
			end
		end
	),

	TestHarness.case(
		"adopts thrown yielding and fatal child-store failures before any repeated admission",
		function(assertions)
			local entries = {
				{
					trigger = "loadout.get",
					operation = "getLoadout",
					invoke = function(context: any, mode: string): unknown
						context.componentState.childFailureTrigger = "loadout.get"
						context.componentState.childFailureMode = mode
						return context.service:getLoadout(101)
					end,
				},
				{
					trigger = "loadout.issue",
					operation = "resolveOccupiedSlot",
					invoke = function(context: any, mode: string): unknown
						context.componentState.childFailureTrigger = "loadout.issue"
						context.componentState.childFailureMode = mode
						return context.service:resolveOccupiedSlot(101, 1)
					end,
				},
				{
					trigger = "loadout.prepare",
					operation = "trustedCreate",
					invoke = function(context: any, mode: string): unknown
						local capability = success(assertions, context.service:resolveOccupiedSlot(101, 1))
						context.componentState.childFailureTrigger = "loadout.prepare"
						context.componentState.childFailureMode = mode
						return context.service:trustedCreate(capability, CFrame.new())
					end,
				},
				{
					trigger = "runtime.prepare",
					operation = "trustedCreate",
					invoke = function(context: any, mode: string): unknown
						local capability = success(assertions, context.service:resolveOccupiedSlot(101, 1))
						context.componentState.childFailureTrigger = "runtime.prepare"
						context.componentState.childFailureMode = mode
						return context.service:trustedCreate(capability, CFrame.new())
					end,
				},
				{
					trigger = "runtime.get",
					operation = "get",
					invoke = function(context: any, mode: string): unknown
						context.componentState.childFailureTrigger = "runtime.get"
						context.componentState.childFailureMode = mode
						return context.service:get(1)
					end,
				},
				{
					trigger = "runtime.list",
					operation = "list",
					invoke = function(context: any, mode: string): unknown
						context.componentState.childFailureTrigger = "runtime.list"
						context.componentState.childFailureMode = mode
						return context.service:list()
					end,
				},
			}

			for _, entry in entries do
				for _, mode in { "Throw", "Yield", "Fatal" } do
					local context = configureFake(assertions)
					local resultValue = entry.invoke(context, mode)
					expectError(
						assertions,
						resultValue,
						if mode == "Fatal" then "COUNTER_FAULT" else "INTERNAL_ERROR",
						entry.operation
					)
					local metrics = context.service:getMetrics()
					assertions.equal(metrics.ownershipState, "Faulted")
					assertions.isFalse(metrics.admissionOpen)
					assertions.equal(metrics.capabilityExpectationCount, 0)
					expectError(
						assertions,
						context.service:resolveOccupiedSlot(101, 1),
						"UNAVAILABLE",
						"resolveOccupiedSlot"
					)
					assertions.isFalse(context.service:getMetrics().operationActive)
					cleanupContext(context)
				end
			end

			for _, abortMode in { "Throw", "Yield", "Fatal" } do
				local context = configureFake(assertions)
				local capability = success(assertions, context.service:resolveOccupiedSlot(101, 1))
				context.componentState.childFailureTrigger = "runtime.prepare"
				context.componentState.childFailureMode = "Recoverable"
				context.componentState.loadoutAbortFailureMode = abortMode
				expectError(
					assertions,
					context.service:trustedCreate(capability, CFrame.new()),
					"CAPABILITY_ABORT_FAILED",
					"trustedCreate"
				)
				local metrics = context.service:getMetrics()
				assertions.equal(metrics.ownershipState, "Faulted")
				assertions.isFalse(metrics.admissionOpen)
				assertions.equal(metrics.capabilityExpectationCount, 0)
				expectError(
					assertions,
					context.service:resolveOccupiedSlot(101, 1),
					"UNAVAILABLE",
					"resolveOccupiedSlot"
				)
				cleanupContext(context)
			end
		end
	),

	TestHarness.case(
		"commits creation in the locked finalizer order and blocks all late work on reentry",
		function(assertions)
			local orderedContext = configureFake(assertions)
			table.clear(orderedContext.componentState.log)
			fakeCreate(assertions, orderedContext)
			local log = orderedContext.componentState.log
			local loadoutCommitIndex: number? = nil
			local ownerCommitIndex: number? = nil
			local runtimeCommitIndex: number? = nil
			for index, name in log do
				if name == "loadout.commit" then
					loadoutCommitIndex = index
				elseif name == "owner.commit" then
					ownerCommitIndex = index
				elseif name == "runtime.commit" then
					runtimeCommitIndex = index
				end
			end
			assertions.isNotNil(loadoutCommitIndex)
			assertions.isNotNil(ownerCommitIndex)
			assertions.isNotNil(runtimeCommitIndex)
			if loadoutCommitIndex ~= nil and ownerCommitIndex ~= nil and runtimeCommitIndex ~= nil then
				assertions.isTrue(loadoutCommitIndex < ownerCommitIndex)
				assertions.isTrue(ownerCommitIndex < runtimeCommitIndex)
			end
			cleanupContext(orderedContext)

			local matrix = {
				{
					trigger = "loadout.get",
					operation = "getLoadout",
					invoke = function(context: any): unknown
						return context.service:getLoadout(101)
					end,
				},
				{
					trigger = "loadout.issue",
					operation = "resolveOccupiedSlot",
					invoke = function(context: any): unknown
						return context.service:resolveOccupiedSlot(101, 1)
					end,
				},
				{
					trigger = "runtime.prepare",
					operation = "trustedCreate",
					invoke = function(context: any): unknown
						local capability = success(assertions, context.service:resolveOccupiedSlot(101, 1))
						context.componentState.triggerName = "runtime.prepare"
						return context.service:trustedCreate(capability, CFrame.new())
					end,
					forbidden = "owner.prepare",
				},
				{
					trigger = "runtime.get",
					operation = "get",
					invoke = function(context: any): unknown
						return context.service:get(99)
					end,
				},
				{
					trigger = "runtime.list",
					operation = "list",
					invoke = function(context: any): unknown
						return context.service:list()
					end,
				},
				{
					trigger = "owner.remove",
					operation = "trustedRemove",
					invoke = function(context: any): unknown
						local record = fakeCreate(assertions, context)
						table.clear(context.componentState.log)
						context.componentState.triggerName = "owner.remove"
						return context.service:trustedRemove(record.runtimeTowerId)
					end,
					forbidden = "runtime.remove",
				},
				{
					trigger = "runtime.get",
					operation = "recreateVisual",
					invoke = function(context: any): unknown
						local record = fakeCreate(assertions, context)
						table.clear(context.componentState.log)
						context.componentState.triggerName = "runtime.get"
						return context.service:recreateVisual(record.runtimeTowerId)
					end,
					forbidden = "owner.recreate",
				},
			}

			for _, entry in matrix do
				local context = configureFake(assertions)
				context.componentState.triggerCallback = function()
					local nested = context.service:list()
					expectError(assertions, nested, "REENTRANT", "list")
				end
				if entry.trigger ~= "runtime.prepare" and entry.trigger ~= "owner.remove" then
					context.componentState.triggerName = entry.trigger
				end
				local outer = entry.invoke(context)
				expectError(assertions, outer, "REENTRANT", entry.operation)
				assertions.equal(context.service:getMetrics().ownershipState, "Faulted")
				if entry.operation == "resolveOccupiedSlot" then
					assertions.equal(context.service:getMetrics().capabilityExpectationCount, 0)
				end
				if entry.forbidden ~= nil then
					assertions.isFalse(containsCall(context.componentState.log, entry.forbidden))
				end
				cleanupContext(context)
			end
		end
	),

	TestHarness.case(
		"finishes deferred shutdown only after rollback and retries exact Wave detachment",
		function(assertions)
			local preparationContext = configureFake(assertions)
			cleanupContext(preparationContext)

			local fixture = TowerFixtures.createAuthenticatedFixture()
			local matchLifecycle = newMatchLifecycle()
			local waveRuntime, waveState = newWaveRuntime()
			local creators, componentState = fakeCreators(fixture)
			local service = newService(matchLifecycle, waveRuntime, true, creators)
			local definition = lifecycleStart(service)
			local boundary = waveState.adapter
			success(assertions, boundary:buildStudioFixtureSources())
			componentState.triggerName = "factory.createAll"
			componentState.triggerCallback = function()
				definition.shutdown()
			end
			expectError(
				assertions,
				boundary:prepareStudioConfiguration(fixture.configuration, MATCH_ID),
				"TEMPLATE_CREATION_FAILED",
				"prepareStudioConfiguration"
			)
			assertions.equal(service:getLifecycleState(), "Shutdown")
			assertions.equal(service:getMetrics().ownershipState, "Cleaned")
			assertions.isFalse(service:getMetrics().retainsConstructionDependencies)
			componentState.trackingFolder:Destroy()

			local deferred = configureFake(assertions)
			deferred.componentState.triggerName = "loadout.get"
			deferred.componentState.triggerCallback = function()
				deferred.definition.shutdown()
			end
			expectError(assertions, deferred.service:getLoadout(101), "UNAVAILABLE", "getLoadout")
			assertions.equal(deferred.service:getLifecycleState(), "Shutdown")
			assertions.equal(deferred.service:getMetrics().ownershipState, "Cleaned")
			assertions.equal(deferred.waveState.detachCount, 1)
			deferred.componentState.trackingFolder:Destroy()

			local retryMatch = newMatchLifecycle()
			local retryWave, retryWaveState = newWaveRuntime()
			local retryCreators, retryComponents = fakeCreators(fixture)
			local retryService = newService(retryMatch, retryWave, true, retryCreators)
			local retryDefinition = lifecycleStart(retryService)
			retryWaveState.detachValue = false
			local firstShutdown, firstError = pcall(retryDefinition.shutdown)
			assertions.isFalse(firstShutdown)
			assertions.contains(firstError, "CLEANUP_FAILED")
			assertions.equal(retryService:getLifecycleState(), "Failed")
			assertions.equal(retryService:getMetrics().waveBoundaryCount, 1)
			retryWaveState.detachValue = true
			retryDefinition.shutdown()
			assertions.equal(retryService:getLifecycleState(), "Shutdown")
			assertions.equal(retryWaveState.detachCount, 2)
			retryComponents.trackingFolder:Destroy()
		end
	),

	TestHarness.case(
		"accepts an authentic already-detached participant handle during aggregate cleanup",
		function(assertions)
			local context = configureFake(assertions)
			context.matchState.detachReturnsFalse = true
			local boundary = context.waveState.adapter
			local residue = success(assertions, boundary:dispatchStudioEvidence("TowerCleanup"))
			assertions.equal(residue.state, "Cleaned")
			assertions.equal(context.matchState.detachCount, 1)
			context.definition.shutdown()
			context.componentState.trackingFolder:Destroy()
		end
	),
})
