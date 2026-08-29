--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local TowerGrayboxFactory = require(script.Parent.Parent.ProductionServerTowers.TowerGrayboxFactory)
local TowerModelContract = require(script.Parent.Parent.ProductionServerTowers.TowerModelContract)
local TowerModelOwner = require(script.Parent.Parent.ProductionServerTowers.TowerModelOwner)

type Assertions = TestHarness.Assertions

type DependencyMode = "Normal" | "Throw" | "Yield" | "Nontrue" | "Malformed"

type ContractState = {
	method: string?,
	mode: DependencyMode,
	callCount: number,
	onCall: ((string) -> ())?,
}

type EngineState = {
	method: string?,
	mode: DependencyMode,
	callCount: number,
	cloneCount: number,
	destroyCount: number,
	onCall: ((string) -> ())?,
	pivots: { [Model]: CFrame },
	workspace: Folder,
}

type Scope = {
	factories: { TowerGrayboxFactory.Factory },
	owners: { TowerModelOwner.Owner },
	instances: { Instance },
}

local MATCH_ID = "match:phase12-model-owner"
local TOWER_EPOCH = 1
local UNIT_ID = "unit:p12-e1-p101-s1"

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		error("expected tower model owner operation to succeed", 0)
	end
	return result.value
end

local function expectError(assertions: Assertions, result: any, code: string, operation: string)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		assertions.isTrue(table.isfrozen(result.error))
		assertions.equal(result.error.code, code)
		assertions.equal(result.error.operation, operation)
	end
end

local function isolated(assertions: Assertions, callback: (Scope) -> ())
	local scope: Scope = {
		factories = {},
		owners = {},
		instances = {},
	}
	local completed, failureValue = pcall(callback, scope)
	for index = #scope.owners, 1, -1 do
		pcall(function()
			scope.owners[index]:cleanup()
		end)
	end
	for index = #scope.factories, 1, -1 do
		pcall(function()
			scope.factories[index]:cleanup()
		end)
	end
	for index = #scope.instances, 1, -1 do
		pcall(function()
			scope.instances[index]:Destroy()
		end)
	end
	if not completed then
		error(failureValue, 0)
	end
	assertions.equal(#scope.owners, #scope.owners)
end

local function intercept(state: any, methodName: string): boolean
	state.callCount += 1
	local callback = state.onCall
	if callback ~= nil then
		state.onCall = nil
		callback(methodName)
	end
	if state.method ~= methodName then
		return false
	elseif state.mode == "Throw" then
		error("injected tower model dependency failure", 0)
	elseif state.mode == "Yield" then
		coroutine.yield()
	end
	return state.mode == "Nontrue" or state.mode == "Malformed"
end

local function newContractAdapter(configuration: any): (TowerModelOwner.ContractAdapter, ContractState)
	local state: ContractState = {
		method = nil,
		mode = "Normal",
		callCount = 0,
		onCall = nil,
	}
	local function before(methodName: string): unknown?
		if not intercept(state, methodName) then
			return nil
		end
		if state.mode == "Malformed" then
			return true
		end
		return table.freeze({
			ok = false,
			error = table.freeze({ code = "INJECTED_REJECTION" }),
		})
	end
	local adapter: TowerModelOwner.ContractAdapter = table.freeze({
		validateTemplate = function(_self, definition, model)
			local injected = before("validateTemplate")
			return injected or TowerModelContract.validateTemplate(configuration, definition, model)
		end,
		selectLiveVariant = function(_self, definition, level, model)
			local injected = before("selectLiveVariant")
			return injected or TowerModelContract.selectLiveVariant(configuration, definition, level, model)
		end,
		validateLive = function(_self, definition, level, model)
			local injected = before("validateLive")
			return injected or TowerModelContract.validateLive(configuration, definition, level, model)
		end,
	})
	return adapter, state
end

local function newEngineAdapter(scope: Scope): (TowerModelOwner.EngineAdapter, EngineState)
	local workspace = Instance.new("Folder")
	workspace.Name = "TestWorkspace"
	table.insert(scope.instances, workspace)
	local state: EngineState = {
		method = nil,
		mode = "Normal",
		callCount = 0,
		cloneCount = 0,
		destroyCount = 0,
		onCall = nil,
		pivots = setmetatable({}, { __mode = "k" }) :: any,
		workspace = workspace,
	}
	local adapter: TowerModelOwner.EngineAdapter = table.freeze({
		workspace = workspace,
		cloneModel = function(_self, modelValue)
			if intercept(state, "cloneModel") then
				return false
			end
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
			if intercept(state, "getPivot") then
				return false
			end
			if typeof(modelValue) ~= "Instance" or not (modelValue :: Instance):IsA("Model") then
				return nil
			end
			return state.pivots[modelValue :: Model] or CFrame.new()
		end,
		pivotTo = function(_self, modelValue, placementValue)
			if intercept(state, "pivotTo") then
				return false
			end
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
			if intercept(state, "createFolder") or type(nameValue) ~= "string" then
				return false
			end
			local folder = Instance.new("Folder")
			folder.Name = nameValue
			return folder
		end,
		setParent = function(_self, instanceValue, parentValue)
			if intercept(state, "setParent") then
				return false
			end
			if typeof(instanceValue) ~= "Instance" or (parentValue ~= nil and typeof(parentValue) ~= "Instance") then
				return false
			end
			(instanceValue :: Instance).Parent = parentValue :: Instance?
			return (instanceValue :: Instance).Parent == parentValue
		end,
		destroy = function(_self, instanceValue)
			if intercept(state, "destroy") then
				return false
			end
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

local function newFactory(
	assertions: Assertions,
	scope: Scope,
	fixture: TowerFixtures.AuthenticatedFixture
): TowerGrayboxFactory.Factory
	local constructor = TowerGrayboxFactory.newForTests
	assertions.isNotNil(constructor)
	if constructor == nil then
		error("tower graybox test constructor unavailable", 0)
	end
	local factory = success(
		assertions,
		constructor(fixture.configuration, {
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
	) :: TowerGrayboxFactory.Factory
	table.insert(scope.factories, factory)
	return factory
end

local function newTemplate(
	assertions: Assertions,
	scope: Scope,
	fixture: TowerFixtures.AuthenticatedFixture,
	definition: any
): Model
	return success(assertions, newFactory(assertions, scope, fixture):createTemplate(definition)) :: Model
end

local function newOwner(
	assertions: Assertions,
	scope: Scope,
	fixture: TowerFixtures.AuthenticatedFixture
): (TowerModelOwner.Owner, ContractState, EngineState)
	local contract, contractState = newContractAdapter(fixture.configuration)
	local engine, engineState = newEngineAdapter(scope)
	local constructor = TowerModelOwner.newForTests
	assertions.isNotNil(constructor)
	if constructor == nil then
		error("tower model owner test constructor unavailable", 0)
	end
	local owner =
		success(assertions, constructor(fixture.configuration, MATCH_ID, TOWER_EPOCH, contract, engine)) :: TowerModelOwner.Owner
	table.insert(scope.owners, owner)
	return owner, contractState, engineState
end

local function snapshotTable(definition: any, runtimeTowerId: number, placementCFrame: CFrame): { [string]: any }
	local value: { [string]: any } = {
		matchId = MATCH_ID,
		towerEpoch = TOWER_EPOCH,
		runtimeTowerId = runtimeTowerId,
		ownerUserId = 101,
		towerId = definition.id,
		unitId = UNIT_ID,
		level = 1,
		targetEligibility = "AllEligibleEnemies",
		placementCFrame = placementCFrame,
		totalInvestment = definition.placementCost,
		cooldownEndsServerTime = 0,
		lifecycle = "Active",
	}
	if definition.levels[1].attack ~= nil then
		value.targetMode = definition.defaultTargetMode
	end
	return value
end

local function snapshot(definition: any, runtimeTowerId: number, placementCFrame: CFrame): any
	return table.freeze(snapshotTable(definition, runtimeTowerId, placementCFrame))
end

local function register(assertions: Assertions, owner: TowerModelOwner.Owner, definition: any, model: Model)
	assertions.isTrue(success(assertions, owner:registerTemplate(definition, model)))
end

local function prepareAndCommit(assertions: Assertions, owner: TowerModelOwner.Owner, snapshotValue: any): any
	local prepared = success(assertions, owner:prepareCreate(snapshotValue))
	return success(assertions, owner:commitPreparedCreate(prepared.token))
end

local function runtimeRoot(state: EngineState): Folder?
	local value = state.workspace:FindFirstChild(TowerModelOwner.RUNTIME_ROOT_NAME)
	return if value ~= nil and value:IsA("Folder") then value :: Folder else nil
end

local function assertFailedPrepareHasNoNewResidue(
	assertions: Assertions,
	owner: TowerModelOwner.Owner,
	engine: EngineState
)
	local metrics = owner:getMetrics()
	assertions.isTrue(metrics.faulted)
	assertions.equal(metrics.templateCount, 1)
	assertions.equal(metrics.preparedModelCount, 0)
	assertions.equal(metrics.liveModelCount, 0)
	assertions.equal(metrics.orphanModelCount, 0)
	assertions.isFalse(metrics.hasRuntimeRoot)
	assertions.equal(#engine.workspace:GetChildren(), 0)
end

local function cleanupAndAssertNoResidue(assertions: Assertions, owner: TowerModelOwner.Owner, engine: EngineState)
	assertions.isTrue(success(assertions, owner:cleanup()))
	local metrics = owner:getMetrics()
	assertions.isTrue(metrics.cleaned)
	assertions.isFalse(metrics.faulted)
	assertions.equal(metrics.templateCount, 0)
	assertions.equal(metrics.preparedModelCount, 0)
	assertions.equal(metrics.liveModelCount, 0)
	assertions.equal(metrics.orphanModelCount, 0)
	assertions.isFalse(metrics.hasRuntimeRoot)
	assertions.isFalse(metrics.retainsConfiguration)
	assertions.isFalse(metrics.retainsContractAdapter)
	assertions.isFalse(metrics.retainsEngineAdapter)
	assertions.equal(#engine.workspace:GetChildren(), 0)
end

return TestHarness.suite("TowerModelOwner", {
	TestHarness.case("gates construction on exact authenticated inputs and exact frozen adapters", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local contract = newContractAdapter(fixture.configuration)
			local engine = newEngineAdapter(scope)
			local constructor = TowerModelOwner.newForTests
			assertions.isNotNil(constructor)
			if constructor == nil then
				return
			end
			local copiedConfiguration = table.freeze(table.clone(fixture.configuration))
			expectError(
				assertions,
				constructor(copiedConfiguration, MATCH_ID, TOWER_EPOCH, contract, engine),
				"UNAUTHENTICATED_CONFIGURATION",
				"new"
			)
			expectError(
				assertions,
				constructor(fixture.configuration, "invalid", TOWER_EPOCH, contract, engine),
				"INVALID_MATCH_ID",
				"new"
			)
			expectError(
				assertions,
				constructor(fixture.configuration, MATCH_ID, 0, contract, engine),
				"INVALID_EPOCH",
				"new"
			)
			local mutableContract = table.clone(contract :: any)
			expectError(
				assertions,
				constructor(fixture.configuration, MATCH_ID, TOWER_EPOCH, mutableContract, engine),
				"INVALID_ADAPTER",
				"new"
			)
			assertions.equal(#(engine :: any).workspace:GetChildren(), 0)
		end)
	end),

	TestHarness.case("owns a private template and commits a prepared level-one visual atomically", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local owner, _, engine = newOwner(assertions, scope, fixture)
			local callerTemplate = newTemplate(assertions, scope, fixture, fixture.single)
			register(assertions, owner, fixture.single, callerTemplate)
			assertions.equal(engine.cloneCount, 1)
			callerTemplate:Destroy()

			local placement = CFrame.new(12, 3, -4)
			local record = snapshot(fixture.single, 1, placement)
			local prepared = success(assertions, owner:prepareCreate(record))
			assertions.isTrue(table.isfrozen(prepared))
			assertions.equal(prepared.runtimeTowerId, 1)
			assertions.isFalse(typeof(prepared.token) == "Instance")
			local preparedMetrics = owner:getMetrics()
			assertions.equal(preparedMetrics.preparedModelCount, 1)
			assertions.equal(preparedMetrics.liveModelCount, 0)
			assertions.isTrue(preparedMetrics.hasRuntimeRoot)

			local root = runtimeRoot(engine)
			assertions.isNotNil(root)
			local model = (root :: Folder):GetChildren()[1] :: Model
			assertions.equal(engine.pivots[model], placement)
			assertions.isTrue(
				TowerModelContract.validateLive(fixture.configuration, fixture.single, fixture.single.levels[1], model).ok
			)

			local receipt = success(assertions, owner:commitPreparedCreate(prepared.token))
			assertions.isTrue(table.isfrozen(receipt))
			assertions.equal(receipt.runtimeTowerId, 1)
			assertions.equal(receipt.status, "Live")
			assertions.isFalse(receipt.recreated)
			assertions.equal(owner:getMetrics().preparedModelCount, 0)
			assertions.equal(owner:getMetrics().liveModelCount, 1)
			expectError(assertions, owner:commitPreparedCreate(prepared.token), "INVALID_TOKEN", "commitPreparedCreate")
		end)
	end),

	TestHarness.case(
		"aborts prepared ownership without issuing the ID and drops a newly empty root",
		function(assertions)
			isolated(assertions, function(scope)
				local fixture = TowerFixtures.createAuthenticatedFixture()
				local owner, _, engine = newOwner(assertions, scope, fixture)
				register(assertions, owner, fixture.support, newTemplate(assertions, scope, fixture, fixture.support))
				local record = snapshot(fixture.support, 7, CFrame.new(1, 2, 3))
				local first = success(assertions, owner:prepareCreate(record))
				assertions.isTrue(success(assertions, owner:abortPreparedCreate(first.token)))
				assertions.isNil(runtimeRoot(engine))
				assertions.equal(owner:getMetrics().preparedModelCount, 0)
				expectError(assertions, owner:abortPreparedCreate(first.token), "INVALID_TOKEN", "abortPreparedCreate")

				local second = success(assertions, owner:prepareCreate(record))
				success(assertions, owner:commitPreparedCreate(second.token))
				assertions.equal(owner:getMetrics().liveModelCount, 1)
			end)
		end
	),

	TestHarness.case("accepts only exact initial bounded RuntimeTower snapshots", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local owner, _, engine = newOwner(assertions, scope, fixture)
			register(assertions, owner, fixture.single, newTemplate(assertions, scope, fixture, fixture.single))
			local baselineCloneCount = engine.cloneCount
			local invalidValues = {
				{ key = "level", value = 2 },
				{ key = "totalInvestment", value = fixture.single.placementCost + 1 },
				{ key = "cooldownEndsServerTime", value = 1 },
				{ key = "runtimeTowerId", value = 4_097 },
				{ key = "matchId", value = "match:foreign" },
				{ key = "towerEpoch", value = 2 },
				{ key = "targetMode", value = "Last" },
			}
			for _, invalid in invalidValues do
				local value = snapshotTable(fixture.single, 1, CFrame.new())
				value[invalid.key] = invalid.value
				expectError(
					assertions,
					owner:prepareCreate(table.freeze(value)),
					"INVALID_RUNTIME_SNAPSHOT",
					"prepareCreate"
				)
			end
			local extra = snapshotTable(fixture.single, 1, CFrame.new())
			extra.foreign = true
			expectError(
				assertions,
				owner:prepareCreate(table.freeze(extra)),
				"INVALID_RUNTIME_SNAPSHOT",
				"prepareCreate"
			)
			expectError(
				assertions,
				owner:prepareCreate(snapshotTable(fixture.single, 1, CFrame.new())),
				"INVALID_RUNTIME_SNAPSHOT",
				"prepareCreate"
			)
			assertions.equal(engine.cloneCount, baselineCloneCount)
			assertions.isFalse(owner:getMetrics().faulted)
		end)
	end),

	TestHarness.case("removes idempotently and recreates only a previously committed visual", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local owner, _, engine = newOwner(assertions, scope, fixture)
			register(assertions, owner, fixture.single, newTemplate(assertions, scope, fixture, fixture.single))
			local record = snapshot(fixture.single, 11, CFrame.new(9, 0, 2))
			prepareAndCommit(assertions, owner, record)
			assertions.isTrue(success(assertions, owner:removeVisual(11)))
			assertions.isFalse(success(assertions, owner:removeVisual(11)))
			local recreated = success(assertions, owner:recreateVisual(record))
			assertions.isTrue(recreated.recreated)
			assertions.equal(owner:getMetrics().liveModelCount, 1)
			assertions.equal(#(runtimeRoot(engine) :: Folder):GetChildren(), 1)
			expectError(assertions, owner:prepareCreate(record), "DUPLICATE_RUNTIME_ID", "prepareCreate")
			expectError(
				assertions,
				owner:recreateVisual(snapshot(fixture.single, 12, CFrame.new())),
				"INVALID_RUNTIME_ID",
				"recreateVisual"
			)
		end)
	end),

	TestHarness.case(
		"repairs an externally reparented owned model without mutating RuntimeTower truth",
		function(assertions)
			isolated(assertions, function(scope)
				local fixture = TowerFixtures.createAuthenticatedFixture()
				local owner, _, engine = newOwner(assertions, scope, fixture)
				register(assertions, owner, fixture.single, newTemplate(assertions, scope, fixture, fixture.single))
				local record = snapshot(fixture.single, 21, CFrame.new(4, 5, 6))
				prepareAndCommit(assertions, owner, record)
				local root = runtimeRoot(engine) :: Folder
				local oldModel = root:GetChildren()[1] :: Model
				oldModel.Parent = nil
				local receipt = success(assertions, owner:recreateVisual(record))
				assertions.isTrue(receipt.recreated)
				local newModel = root:GetChildren()[1] :: Model
				assertions.notEqual(newModel, oldModel)
				assertions.equal(engine.pivots[newModel], record.placementCFrame)
				assertions.equal(owner:getMetrics().liveModelCount, 1)
			end)
		end
	),

	TestHarness.case(
		"rejects foreign and duplicate Workspace roots without adopting or destroying them",
		function(assertions)
			isolated(assertions, function(scope)
				local fixture = TowerFixtures.createAuthenticatedFixture()
				local owner, _, engine = newOwner(assertions, scope, fixture)
				register(assertions, owner, fixture.support, newTemplate(assertions, scope, fixture, fixture.support))
				local foreign = Instance.new("Folder")
				foreign.Name = TowerModelOwner.RUNTIME_ROOT_NAME
				foreign.Parent = engine.workspace
				expectError(
					assertions,
					owner:prepareCreate(snapshot(fixture.support, 1, CFrame.new())),
					"FOREIGN_RUNTIME_ROOT",
					"prepareCreate"
				)
				assertions.equal(foreign.Parent, engine.workspace)
				assertions.equal(#engine.workspace:GetChildren(), 1)

				local secondOwner, _, secondEngine = newOwner(assertions, scope, fixture)
				register(
					assertions,
					secondOwner,
					fixture.support,
					newTemplate(assertions, scope, fixture, fixture.support)
				)
				local record = snapshot(fixture.support, 2, CFrame.new(2, 0, 0))
				prepareAndCommit(assertions, secondOwner, record)
				local ownedRoot = runtimeRoot(secondEngine) :: Folder
				local ownedModel = ownedRoot:GetChildren()[1]
				local duplicate = Instance.new("Model")
				duplicate.Name = TowerModelOwner.RUNTIME_ROOT_NAME
				duplicate.Parent = secondEngine.workspace
				expectError(assertions, secondOwner:recreateVisual(record), "FOREIGN_RUNTIME_ROOT", "recreateVisual")
				assertions.equal(ownedModel.Parent, ownedRoot)
				assertions.equal(duplicate.Parent, secondEngine.workspace)
			end)
		end
	),

	TestHarness.case(
		"contains thrown yielding and malformed contract dependencies with no prepared residue",
		function(assertions)
			isolated(assertions, function(scope)
				local fixture = TowerFixtures.createAuthenticatedFixture()
				for _, mode in { "Throw", "Yield", "Malformed" } do
					local owner, contract, engine = newOwner(assertions, scope, fixture)
					register(
						assertions,
						owner,
						fixture.support,
						newTemplate(assertions, scope, fixture, fixture.support)
					)
					contract.method = "validateTemplate"
					contract.mode = mode :: DependencyMode
					expectError(
						assertions,
						owner:prepareCreate(snapshot(fixture.support, 30, CFrame.new())),
						"DEPENDENCY_FAILED",
						"prepareCreate"
					)
					local metrics = owner:getMetrics()
					assertions.isTrue(metrics.faulted)
					assertions.equal(metrics.preparedModelCount, 0)
					assertions.equal(metrics.liveModelCount, 0)
					assertions.isFalse(metrics.hasRuntimeRoot)
					assertions.equal(#engine.workspace:GetChildren(), 0)
				end

				local recreateOwner, recreateContract, recreateEngine = newOwner(assertions, scope, fixture)
				register(
					assertions,
					recreateOwner,
					fixture.support,
					newTemplate(assertions, scope, fixture, fixture.support)
				)
				local recreateRecord = snapshot(fixture.support, 32, CFrame.new(3, 0, 0))
				prepareAndCommit(assertions, recreateOwner, recreateRecord)
				local root = runtimeRoot(recreateEngine) :: Folder
				local retainedModel = root:GetChildren()[1]
				recreateContract.method = "validateLive"
				recreateContract.mode = "Throw"
				expectError(
					assertions,
					recreateOwner:recreateVisual(recreateRecord),
					"DEPENDENCY_FAILED",
					"recreateVisual"
				)
				assertions.equal(retainedModel.Parent, root)
				assertions.equal(recreateOwner:getMetrics().liveModelCount, 1)
			end)
		end
	),

	TestHarness.case(
		"rolls back clone pivot root and first-parent dependency failures without residue",
		function(assertions)
			local methods = { "cloneModel", "getPivot", "pivotTo", "createFolder", "setParent" }
			local modes: { DependencyMode } = { "Throw", "Yield", "Nontrue", "Malformed" }
			local runtimeTowerId = 60
			for _, methodName in methods do
				for _, mode in modes do
					isolated(assertions, function(scope)
						local fixture = TowerFixtures.createAuthenticatedFixture()
						local owner, _, engine = newOwner(assertions, scope, fixture)
						register(
							assertions,
							owner,
							fixture.support,
							newTemplate(assertions, scope, fixture, fixture.support)
						)
						engine.method = methodName
						engine.mode = mode
						expectError(
							assertions,
							owner:prepareCreate(snapshot(fixture.support, runtimeTowerId, CFrame.new(4, 0, -3))),
							"DEPENDENCY_FAILED",
							"prepareCreate"
						)
						assertFailedPrepareHasNoNewResidue(assertions, owner, engine)
						cleanupAndAssertNoResidue(assertions, owner, engine)
					end)
					runtimeTowerId += 1
				end
			end
		end
	),

	TestHarness.case("rolls back model parenting against an existing owned root", function(assertions)
		local modes: { DependencyMode } = { "Throw", "Yield", "Nontrue", "Malformed" }
		for modeIndex, mode in modes do
			isolated(assertions, function(scope)
				local fixture = TowerFixtures.createAuthenticatedFixture()
				local owner, _, engine = newOwner(assertions, scope, fixture)
				register(assertions, owner, fixture.support, newTemplate(assertions, scope, fixture, fixture.support))

				local firstRuntimeTowerId = 90 + modeIndex * 2
				prepareAndCommit(
					assertions,
					owner,
					snapshot(fixture.support, firstRuntimeTowerId, CFrame.new(-5, 0, modeIndex))
				)
				assertions.isTrue(success(assertions, owner:removeVisual(firstRuntimeTowerId)))
				local retainedRoot = runtimeRoot(engine)
				assertions.isNotNil(retainedRoot)
				if retainedRoot == nil then
					error("expected the first visual to leave its authenticated empty runtime root", 0)
				end
				assertions.equal(#retainedRoot:GetChildren(), 0)

				engine.method = "setParent"
				engine.mode = mode
				expectError(
					assertions,
					owner:prepareCreate(
						snapshot(fixture.support, firstRuntimeTowerId + 1, CFrame.new(8, 0, -modeIndex))
					),
					"DEPENDENCY_FAILED",
					"prepareCreate"
				)
				local failedMetrics = owner:getMetrics()
				assertions.isTrue(failedMetrics.faulted)
				assertions.equal(failedMetrics.preparedModelCount, 0)
				assertions.equal(failedMetrics.liveModelCount, 0)
				assertions.equal(failedMetrics.orphanModelCount, 0)
				assertions.isTrue(failedMetrics.hasRuntimeRoot)
				assertions.equal(runtimeRoot(engine), retainedRoot)
				assertions.equal(retainedRoot.Parent, engine.workspace)
				assertions.equal(#retainedRoot:GetChildren(), 0)
				assertions.equal(#engine.workspace:GetChildren(), 1)

				cleanupAndAssertNoResidue(assertions, owner, engine)
			end)
		end
	end),

	TestHarness.case("defers reentrant cleanup and prevents all late engine work", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local owner, _, engine = newOwner(assertions, scope, fixture)
			register(assertions, owner, fixture.support, newTemplate(assertions, scope, fixture, fixture.support))
			local cleanupResult: any = nil
			engine.onCall = function(methodName)
				if methodName == "cloneModel" then
					cleanupResult = owner:cleanup()
				end
			end
			expectError(
				assertions,
				owner:prepareCreate(snapshot(fixture.support, 40, CFrame.new())),
				"CLEANED",
				"prepareCreate"
			)
			assertions.isTrue(cleanupResult.ok)
			assertions.isFalse(cleanupResult.value)
			local metrics = owner:getMetrics()
			assertions.isTrue(metrics.cleaned)
			assertions.isFalse(metrics.retainsConfiguration)
			assertions.isFalse(metrics.retainsContractAdapter)
			assertions.isFalse(metrics.retainsEngineAdapter)
			local callsAfterCleanup = engine.callCount
			expectError(
				assertions,
				owner:recreateVisual(snapshot(fixture.support, 40, CFrame.new())),
				"CLEANED",
				"recreateVisual"
			)
			assertions.equal(engine.callCount, callsAfterCleanup)
		end)
	end),

	TestHarness.case(
		"retries persistent exact-instance destruction and cleans active prepared and template state",
		function(assertions)
			isolated(assertions, function(scope)
				local fixture = TowerFixtures.createAuthenticatedFixture()
				local owner, _, engine = newOwner(assertions, scope, fixture)
				register(assertions, owner, fixture.single, newTemplate(assertions, scope, fixture, fixture.single))
				register(assertions, owner, fixture.splash, newTemplate(assertions, scope, fixture, fixture.splash))
				prepareAndCommit(assertions, owner, snapshot(fixture.single, 50, CFrame.new()))
				local pending =
					success(assertions, owner:prepareCreate(snapshot(fixture.splash, 51, CFrame.new(5, 0, 0))))
				engine.method = "destroy"
				engine.mode = "Nontrue"
				expectError(assertions, owner:cleanup(), "CLEANUP_FAILED", "cleanup")
				assertions.isTrue(owner:getMetrics().faulted)
				engine.method = nil
				engine.mode = "Normal"
				assertions.isTrue(success(assertions, owner:cleanup()))
				local metrics = owner:getMetrics()
				assertions.isTrue(metrics.cleaned)
				assertions.equal(metrics.templateCount, 0)
				assertions.equal(metrics.liveModelCount, 0)
				assertions.equal(metrics.preparedModelCount, 0)
				assertions.equal(metrics.orphanModelCount, 0)
				assertions.isFalse(metrics.hasRuntimeRoot)
				assertions.equal(#engine.workspace:GetChildren(), 0)
				expectError(assertions, owner:commitPreparedCreate(pending.token), "CLEANED", "commitPreparedCreate")
				assertions.isFalse(success(assertions, owner:cleanup()))
			end)
		end
	),

	TestHarness.case("uses a distinct active-capacity error without cloning beyond the bound", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local owner, _, engine = newOwner(assertions, scope, fixture)
			register(assertions, owner, fixture.support, newTemplate(assertions, scope, fixture, fixture.support))
			for runtimeTowerId = 1, TowerModelOwner.MAX_ACTIVE do
				prepareAndCommit(
					assertions,
					owner,
					snapshot(fixture.support, runtimeTowerId, CFrame.new(runtimeTowerId, 0, 0))
				)
			end
			local clonesAtCapacity = engine.cloneCount
			expectError(
				assertions,
				owner:prepareCreate(snapshot(fixture.support, TowerModelOwner.MAX_ACTIVE + 1, CFrame.new())),
				"CAPACITY_EXCEEDED",
				"prepareCreate"
			)
			assertions.equal(engine.cloneCount, clonesAtCapacity)
			assertions.equal(owner:getMetrics().liveModelCount, TowerModelOwner.MAX_ACTIVE)
		end)
	end),
})
