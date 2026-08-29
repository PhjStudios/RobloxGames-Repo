--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local TowerGrayboxFactory = require(script.Parent.Parent.ProductionServerTowers.TowerGrayboxFactory)
local TowerModelContract = require(script.Parent.Parent.ProductionServerTowers.TowerModelContract)

type Assertions = TestHarness.Assertions

type Scope = {
	factories: { TowerGrayboxFactory.Factory },
	instances: { Instance },
}

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		error("expected tower graybox factory operation to succeed", 0)
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

local function isolated(callback: (Scope) -> ())
	local scope: Scope = {
		factories = {},
		instances = {},
	}
	local completed, failureValue = pcall(callback, scope)
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
end

local function defaultDependencies(): TowerGrayboxFactory.TestDependencies
	return {
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
	}
end

local function newFactory(
	assertions: Assertions,
	scope: Scope,
	configuration: unknown,
	dependencies: TowerGrayboxFactory.TestDependencies?
): TowerGrayboxFactory.Factory
	local constructor = TowerGrayboxFactory.newForTests
	assertions.isNotNil(constructor)
	if constructor == nil then
		error("tower graybox test constructor unavailable", 0)
	end
	local factory = success(assertions, constructor(configuration, dependencies or defaultDependencies()))
	table.insert(scope.factories, factory)
	return factory
end

local function own(scope: Scope, instance: Instance): Instance
	table.insert(scope.instances, instance)
	return instance
end

local function countNamedChildren(parent: Instance, namePattern: string): number
	local count = 0
	for _, child in parent:GetChildren() do
		if string.match(child.Name, namePattern) ~= nil then
			count += 1
		end
	end
	return count
end

local function emptyAuthenticatedConfiguration(assertions: Assertions): any
	local sources = TowerFixtures.rawSources()
	sources.towers = {}
	local result = ConfigurationValidator.validate(sources)
	return success(assertions, result)
end

return TestHarness.suite("TowerGrayboxFactory", {
	TestHarness.case("authenticates construction and exact-gates the test adapter", function(assertions)
		isolated(function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			expectError(assertions, TowerGrayboxFactory.new(fixture.rawSources), "UNAUTHENTICATED_CONFIGURATION", "new")
			local productionFactory = success(assertions, TowerGrayboxFactory.new(fixture.configuration))
			table.insert(scope.factories, productionFactory)
			assertions.equal(productionFactory:getState(), "Ready")

			local constructor = TowerGrayboxFactory.newForTests
			assertions.isNotNil(constructor)
			if constructor == nil then
				error("tower graybox test constructor unavailable", 0)
			end
			for _, dependencies in
				{
					{},
					{ isStudio = function() end, createInstance = Instance.new },
					{
						isStudio = function() end,
						createInstance = Instance.new,
						destroyInstance = function() end,
						foreign = true,
					},
					setmetatable(defaultDependencies(), {}),
				}
			do
				expectError(assertions, constructor(fixture.configuration, dependencies), "INVALID_DEPENDENCIES", "new")
			end

			local relocatedFolder = script.Parent.Parent.ProductionServerTowers:Clone()
			own(scope, relocatedFolder)
			relocatedFolder.Name = "TowerFactoryProductionLocationProbe"
			relocatedFolder.Parent = ReplicatedStorage
			local productionLocated = require(relocatedFolder.TowerGrayboxFactory)
			assertions.isNil(productionLocated.newForTests)
		end)
	end),

	TestHarness.case("creates one exact frozen three-template ownership result", function(assertions)
		isolated(function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local factory = newFactory(assertions, scope, fixture.configuration)
			local templates = success(assertions, factory:createAllTemplates())
			assertions.isTrue(table.isfrozen(templates))
			assertions.isTrue(table.isfrozen(templates.ordered))
			assertions.isTrue(table.isfrozen(templates.byTowerId))
			assertions.equal(#templates.ordered, 3)
			local rootFieldCount = 0
			for field in templates do
				assertions.isTrue(field == "ordered" or field == "byTowerId")
				rootFieldCount += 1
			end
			assertions.equal(rootFieldCount, 2)

			local definitions = { fixture.single, fixture.splash, fixture.support }
			local expectedMuzzles = { 3, 6, 0 }
			for index, definition in definitions do
				local model = templates.ordered[index]
				own(scope, model)
				assertions.equal(model.Parent, nil)
				assertions.equal(model.Name, "Tower")
				assertions.equal(templates.byTowerId[definition.id], model)
				local snapshot =
					success(assertions, TowerModelContract.validateTemplate(fixture.configuration, definition, model))
				assertions.equal(snapshot.muzzleCount, expectedMuzzles[index])
			end
			assertions.notEqual(templates.ordered[1], templates.ordered[2])
			assertions.notEqual(templates.ordered[2], templates.ordered[3])
			assertions.equal(factory:getState(), "Ready")
		end)
	end),

	TestHarness.case("returns fresh deterministic models and never retains transferred ownership", function(assertions)
		isolated(function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local factory = newFactory(assertions, scope, fixture.configuration)
			local first = success(assertions, factory:createAllTemplates())
			local second = success(assertions, factory:createAllTemplates())
			for index = 1, 3 do
				own(scope, first.ordered[index])
				own(scope, second.ordered[index])
				assertions.notEqual(first.ordered[index], second.ordered[index])
				assertions.equal(first.ordered[index].Name, second.ordered[index].Name)
			end

			first.ordered[1].Name = "CallerMutation"
			assertions.equal(second.ordered[1].Name, "Tower")
			assertions.isTrue(success(assertions, factory:cleanup()))
			assertions.equal(factory:getState(), "Cleaned")
			local stillOwned = success(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.splash, second.ordered[2])
			)
			assertions.equal(stillOwned.towerId, fixture.splash.id)
		end)
	end),

	TestHarness.case("creates exact symbolic inert hooks variants and marker counts", function(assertions)
		isolated(function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local factory = newFactory(assertions, scope, fixture.configuration)
			local single = own(scope, success(assertions, factory:createTemplate(fixture.single))) :: Model
			local splash = own(scope, success(assertions, factory:createTemplate(fixture.splash))) :: Model
			local support = own(scope, success(assertions, factory:createTemplate(fixture.support))) :: Model

			for _, model in { single, splash, support } do
				local animation = model:FindFirstChild("Animation") :: Folder
				local hooks = animation:FindFirstChild("Hooks") :: Folder
				local controller = animation:FindFirstChild("Controller") :: AnimationController
				assertions.isNotNil(controller:FindFirstChild("Animator"))
				assertions.equal((hooks:FindFirstChild("Idle") :: StringValue).Value, "hook.idle")
				assertions.equal((hooks:FindFirstChild("Upgrade") :: StringValue).Value, "hook.upgrade")
				assertions.equal(
					countNamedChildren(model:FindFirstChild("UpgradeVariants") :: Folder, "^Level%d%d$"),
					3
				)
			end
			assertions.isNotNil((single.Animation.Hooks :: Folder):FindFirstChild("Attack"))
			assertions.isNotNil((splash.Animation.Hooks :: Folder):FindFirstChild("Attack"))
			assertions.isNil((support.Animation.Hooks :: Folder):FindFirstChild("Attack"))
		end)
	end),

	TestHarness.case("gates creation on an exact non-yielding Studio decision", function(assertions)
		isolated(function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local notStudioDependencies = defaultDependencies()
			notStudioDependencies.isStudio = function()
				return false
			end
			local notStudio = newFactory(assertions, scope, fixture.configuration, notStudioDependencies)
			expectError(assertions, notStudio:createTemplate(fixture.single), "NOT_STUDIO", "createTemplate")
			assertions.equal(notStudio:getState(), "Ready")

			for _, predicate in
				{
					function()
						return "yes"
					end,
					function()
						error("studio failure", 0)
					end,
					function()
						coroutine.yield()
						return true
					end,
				}
			do
				local dependencies = defaultDependencies()
				dependencies.isStudio = predicate
				local factory = newFactory(assertions, scope, fixture.configuration, dependencies)
				expectError(assertions, factory:createTemplate(fixture.single), "STUDIO_CHECK_FAILED", "createTemplate")
				assertions.equal(factory:getState(), "Faulted")
			end
		end)
	end),

	TestHarness.case("faults on malformed throwing yielding and reused instance adapters", function(assertions)
		isolated(function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local callbacks = {
				function(_className: string): unknown
					error("creation failure", 0)
				end,
				function(_className: string): unknown
					coroutine.yield()
					return nil
				end,
				function(_className: string): unknown
					return {}
				end,
				function(_className: string): unknown
					return Instance.new("Folder")
				end,
			}
			for _, callback in callbacks do
				local dependencies = defaultDependencies()
				dependencies.createInstance = callback
				local factory = newFactory(assertions, scope, fixture.configuration, dependencies)
				expectError(
					assertions,
					factory:createTemplate(fixture.single),
					"TEMPLATE_CREATION_FAILED",
					"createTemplate"
				)
				assertions.equal(factory:getState(), "Faulted")
			end

			local sharedModel = own(scope, Instance.new("Model")) :: Model
			local dependencies = defaultDependencies()
			dependencies.createInstance = function(_className: string)
				return sharedModel
			end
			local reused = newFactory(assertions, scope, fixture.configuration, dependencies)
			expectError(assertions, reused:createTemplate(fixture.single), "TEMPLATE_CREATION_FAILED", "createTemplate")
			assertions.equal(reused:getState(), "Faulted")
		end)
	end),

	TestHarness.case("detects reentry and atomically honors nested cleanup", function(assertions)
		isolated(function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local reentryFactory: TowerGrayboxFactory.Factory? = nil
			local nestedReentry: any = nil
			local reentryDependencies = defaultDependencies()
			reentryDependencies.isStudio = function()
				nestedReentry = (reentryFactory :: TowerGrayboxFactory.Factory):createTemplate(fixture.single)
				return true
			end
			reentryFactory = newFactory(assertions, scope, fixture.configuration, reentryDependencies)
			expectError(
				assertions,
				(reentryFactory :: TowerGrayboxFactory.Factory):createTemplate(fixture.single),
				"STUDIO_CHECK_FAILED",
				"createTemplate"
			)
			expectError(assertions, nestedReentry, "REENTRANT", "createTemplate")
			assertions.equal((reentryFactory :: TowerGrayboxFactory.Factory):getState(), "Faulted")

			local cleanupFactory: TowerGrayboxFactory.Factory? = nil
			local nestedCleanup: any = nil
			local cleanupDependencies = defaultDependencies()
			cleanupDependencies.isStudio = function()
				nestedCleanup = (cleanupFactory :: TowerGrayboxFactory.Factory):cleanup()
				return true
			end
			cleanupFactory = newFactory(assertions, scope, fixture.configuration, cleanupDependencies)
			expectError(
				assertions,
				(cleanupFactory :: TowerGrayboxFactory.Factory):createTemplate(fixture.single),
				"CLEANED",
				"createTemplate"
			)
			assertions.isFalse(success(assertions, nestedCleanup))
			assertions.equal((cleanupFactory :: TowerGrayboxFactory.Factory):getState(), "Cleaned")
		end)
	end),

	TestHarness.case("retains failed intermediate destruction for retryable cleanup", function(assertions)
		isolated(function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local createCount = 0
			local allowDestroy = false
			local destroyAttempts = 0
			local dependencies = defaultDependencies()
			dependencies.createInstance = function(className: string): unknown
				createCount += 1
				if createCount == 2 then
					return nil
				end
				return Instance.new(className)
			end
			dependencies.destroyInstance = function(instance: Instance): unknown
				destroyAttempts += 1
				if not allowDestroy then
					return false
				end
				instance:Destroy()
				return true
			end
			local factory = newFactory(assertions, scope, fixture.configuration, dependencies)
			expectError(
				assertions,
				factory:createTemplate(fixture.single),
				"TEMPLATE_CREATION_FAILED",
				"createTemplate"
			)
			assertions.equal(factory:getState(), "Faulted")
			expectError(assertions, factory:cleanup(), "CLEANUP_FAILED", "cleanup")
			assertions.equal(factory:getState(), "Faulted")
			assertions.isTrue(destroyAttempts >= 2)
			allowDestroy = true
			assertions.isTrue(success(assertions, factory:cleanup()))
			assertions.equal(factory:getState(), "Cleaned")
			assertions.isFalse(success(assertions, factory:cleanup()))
		end)
	end),

	TestHarness.case("rejects empty subset and reordered catalogs for bulk synthesis", function(assertions)
		isolated(function(scope)
			local empty = emptyAuthenticatedConfiguration(assertions)
			local emptyFactory = newFactory(assertions, scope, empty)
			expectError(assertions, emptyFactory:createAllTemplates(), "UNSUPPORTED_CATALOG", "createAllTemplates")
			assertions.equal(emptyFactory:getState(), "Ready")

			local reorderedSources = TowerFixtures.rawSources()
			local first = reorderedSources.towers[1]
			reorderedSources.towers[1] = reorderedSources.towers[2]
			reorderedSources.towers[2] = first
			local reordered = success(assertions, ConfigurationValidator.validate(reorderedSources))
			local reorderedFactory = newFactory(assertions, scope, reordered)
			expectError(assertions, reorderedFactory:createAllTemplates(), "UNSUPPORTED_CATALOG", "createAllTemplates")
		end)
	end),
})
