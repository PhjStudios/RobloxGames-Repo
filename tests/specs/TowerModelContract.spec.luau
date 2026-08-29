--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
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
		error("expected tower model contract operation to succeed", 0)
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
		assertions.isTrue(type(result.error.path) == "string")
	end
end

local function isolated(_assertions: Assertions, callback: (Scope) -> ())
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
	local factory = newFactory(assertions, scope, fixture)
	local model = success(assertions, factory:createTemplate(definition)) :: Model
	table.insert(scope.instances, model)
	return model
end

local function child(parent: Instance, name: string): Instance
	local value = parent:FindFirstChild(name)
	if value == nil then
		error(`missing test child {name}`, 0)
	end
	return value
end

local function bodyAt(model: Model, levelIndex: number): Part
	local variants = child(model, "UpgradeVariants")
	local variant = child(variants, string.format("Level%02d", levelIndex))
	return child(variant, "Body") :: Part
end

return TestHarness.suite("TowerModelContract", {
	TestHarness.case("accepts the three exact v1 templates with bounded detached snapshots", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local expected = {
				{ definition = fixture.single, descendants = 27, attachments = 6, muzzles = 3, hooks = 3 },
				{ definition = fixture.splash, descendants = 30, attachments = 9, muzzles = 6, hooks = 3 },
				{ definition = fixture.support, descendants = 20, attachments = 0, muzzles = 0, hooks = 2 },
			}
			for _, item in expected do
				local model = newTemplate(assertions, scope, fixture, item.definition)
				local snapshot = success(
					assertions,
					TowerModelContract.validateTemplate(fixture.configuration, item.definition, model)
				)
				assertions.isTrue(table.isfrozen(snapshot))
				assertions.equal(snapshot.contractVersion, 1)
				assertions.equal(snapshot.mode, "Template")
				assertions.equal(snapshot.towerId, item.definition.id)
				assertions.equal(snapshot.modelAssetKey, item.definition.modelAssetKey)
				assertions.equal(snapshot.levelCount, 3)
				assertions.equal(snapshot.descendantCount, item.descendants)
				assertions.equal(snapshot.basePartCount, 4)
				assertions.equal(snapshot.attachmentCount, item.attachments)
				assertions.equal(snapshot.muzzleCount, item.muzzles)
				assertions.equal(snapshot.hookCount, item.hooks)
				assertions.isNil(snapshot.selectedLevelIndex)
				assertions.isFalse(typeof(snapshot) == "Instance")
			end
		end)
	end),

	TestHarness.case("selects one exact canonical live level and stays parent agnostic", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local model = newTemplate(assertions, scope, fixture, fixture.single)
			local selected = success(
				assertions,
				TowerModelContract.selectLiveVariant(
					fixture.configuration,
					fixture.single,
					fixture.single.levels[2],
					model
				)
			)
			assertions.equal(selected.mode, "Live")
			assertions.equal(selected.selectedLevelIndex, 2)
			assertions.equal(bodyAt(model, 1).Transparency, 1)
			assertions.equal(bodyAt(model, 2).Transparency, 0)
			assertions.equal(bodyAt(model, 3).Transparency, 1)

			local parent = Instance.new("Folder")
			table.insert(scope.instances, parent)
			model.Parent = parent
			local live = success(
				assertions,
				TowerModelContract.validateLive(fixture.configuration, fixture.single, fixture.single.levels[2], model)
			)
			assertions.equal(live.selectedLevelIndex, 2)
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.single, model),
				"INVALID_ROOT",
				"validateTemplate"
			)
		end)
	end),

	TestHarness.case("authenticates the complete root definition asset and level identities", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local other = TowerFixtures.createAuthenticatedFixture()
			local model = newTemplate(assertions, scope, fixture, fixture.single)
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.rawSources, fixture.single, model),
				"UNAUTHENTICATED_CONFIGURATION",
				"validateTemplate"
			)
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, other.single, model),
				"INVALID_DEFINITION",
				"validateTemplate"
			)
			expectError(
				assertions,
				TowerModelContract.validateLive(
					fixture.configuration,
					fixture.single,
					table.clone(fixture.single.levels[1]),
					model
				),
				"INVALID_LEVEL",
				"validateLive"
			)
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.single, {}),
				"INVALID_MODEL",
				"validateTemplate"
			)
		end)
	end),

	TestHarness.case("rejects unexpected missing and misnamed hierarchy nodes", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()

			local unexpected = newTemplate(assertions, scope, fixture, fixture.support)
			local foreign = Instance.new("Folder")
			foreign.Name = "Foreign"
			foreign.Parent = unexpected
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.support, unexpected),
				"INVALID_HIERARCHY",
				"validateTemplate"
			)

			local missing = newTemplate(assertions, scope, fixture, fixture.single)
			child(child(missing, "Animation"), "Hooks"):FindFirstChild("Attack"):Destroy()
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.single, missing),
				"INVALID_HIERARCHY",
				"validateTemplate"
			)

			local sparse = newTemplate(assertions, scope, fixture, fixture.splash)
			child(child(bodyAt(sparse, 1), "Muzzles"), "Muzzle01").Name = "Muzzle03"
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.splash, sparse),
				"INVALID_HIERARCHY",
				"validateTemplate"
			)

			local primary = newTemplate(assertions, scope, fixture, fixture.single)
			primary.PrimaryPart = bodyAt(primary, 1)
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.single, primary),
				"INVALID_PRIMARY_PART",
				"validateTemplate"
			)
		end)
	end),

	TestHarness.case("rejects attacking markers on support and missing attacking markers", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local support = newTemplate(assertions, scope, fixture, fixture.support)
			local marker = Instance.new("Attachment")
			marker.Name = "AimPivot"
			marker.Parent = child(bodyAt(support, 1), "Aim")
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.support, support),
				"INVALID_HIERARCHY",
				"validateTemplate"
			)

			local single = newTemplate(assertions, scope, fixture, fixture.single)
			child(child(bodyAt(single, 1), "Aim"), "AimPivot"):Destroy()
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.single, single),
				"INVALID_HIERARCHY",
				"validateTemplate"
			)
		end)
	end),

	TestHarness.case("rejects duplicate aim and muzzle markers", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()

			local duplicateAim = newTemplate(assertions, scope, fixture, fixture.single)
			local aimPivot = Instance.new("Attachment")
			aimPivot.Name = "AimPivot"
			aimPivot.Parent = child(bodyAt(duplicateAim, 1), "Aim")
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.single, duplicateAim),
				"INVALID_HIERARCHY",
				"validateTemplate"
			)

			local duplicateMuzzle = newTemplate(assertions, scope, fixture, fixture.single)
			local muzzle = Instance.new("Attachment")
			muzzle.Name = "Muzzle01"
			muzzle.Parent = child(bodyAt(duplicateMuzzle, 1), "Muzzles")
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.single, duplicateMuzzle),
				"INVALID_HIERARCHY",
				"validateTemplate"
			)
		end)
	end),

	TestHarness.case("rejects wrong upgrade variant names and counts", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()

			local wrongName = newTemplate(assertions, scope, fixture, fixture.support)
			child(child(wrongName, "UpgradeVariants"), "Level01").Name = "Level04"
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.support, wrongName),
				"INVALID_HIERARCHY",
				"validateTemplate"
			)

			local wrongCount = newTemplate(assertions, scope, fixture, fixture.support)
			child(child(wrongCount, "UpgradeVariants"), "Level03"):Destroy()
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.support, wrongCount),
				"INVALID_HIERARCHY",
				"validateTemplate"
			)
		end)
	end),

	TestHarness.case("rejects executable network bindable and constraint descendants", function(assertions)
		for _, className in { "Script", "RemoteEvent", "BindableEvent", "WeldConstraint" } do
			isolated(assertions, function(scope)
				local fixture = TowerFixtures.createAuthenticatedFixture()
				local model = newTemplate(assertions, scope, fixture, fixture.support)
				local prohibited = Instance.new(className)
				prohibited.Parent = model
				expectError(
					assertions,
					TowerModelContract.validateTemplate(fixture.configuration, fixture.support, model),
					"INVALID_CLASS",
					"validateTemplate"
				)
			end)
		end
	end),

	TestHarness.case("enforces inert Part size transform PivotOffset and visibility properties", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local mutations = {
				function(model: Model)
					bodyAt(model, 1).CanQuery = true
				end,
				function(model: Model)
					bodyAt(model, 1).Anchored = false
				end,
				function(model: Model)
					bodyAt(model, 1).Size = Vector3.new(65, 1, 1)
				end,
				function(model: Model)
					bodyAt(model, 1).CFrame = CFrame.new(100_001, 0, 0)
				end,
				function(model: Model)
					bodyAt(model, 1).PivotOffset = CFrame.new(100_001, 0, 0)
				end,
				function(model: Model)
					bodyAt(model, 1).Transparency = 1
				end,
			}
			for _, mutate in mutations do
				local model = newTemplate(assertions, scope, fixture, fixture.single)
				mutate(model)
				expectError(
					assertions,
					TowerModelContract.validateTemplate(fixture.configuration, fixture.single, model),
					"INVALID_PROPERTY",
					"validateTemplate"
				)
			end

			local shiftedPivot = newTemplate(assertions, scope, fixture, fixture.single)
			local shiftedRoot = child(shiftedPivot, "Root") :: Part
			shiftedRoot.PivotOffset = CFrame.new(1, 0, 0)
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.single, shiftedPivot),
				"INVALID_TEMPLATE_PIVOT",
				"validateTemplate"
			)
		end)
	end),

	TestHarness.case("rejects all extra attributes and CollectionService tags", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local wrongVersion = newTemplate(assertions, scope, fixture, fixture.support)
			wrongVersion:SetAttribute(TowerModelContract.CONTRACT_ATTRIBUTE, 2)
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.support, wrongVersion),
				"INVALID_ATTRIBUTE",
				"validateTemplate"
			)

			local descendantAttribute = newTemplate(assertions, scope, fixture, fixture.support)
			bodyAt(descendantAttribute, 1):SetAttribute("Foreign", true)
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.support, descendantAttribute),
				"INVALID_ATTRIBUTE",
				"validateTemplate"
			)

			local tagged = newTemplate(assertions, scope, fixture, fixture.support)
			bodyAt(tagged, 1):AddTag("Foreign")
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.support, tagged),
				"INVALID_TAG",
				"validateTemplate"
			)
		end)
	end),

	TestHarness.case("fails closed before traversing an over-broad node", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local model = newTemplate(assertions, scope, fixture, fixture.support)
			local variants = child(model, "UpgradeVariants")
			for index = 1, 30 do
				local extra = Instance.new("Folder")
				extra.Name = `Extra{index}`
				extra.Parent = variants
			end
			expectError(
				assertions,
				TowerModelContract.validateTemplate(fixture.configuration, fixture.support, model),
				"BOUND_EXCEEDED",
				"validateTemplate"
			)
		end)
	end),

	TestHarness.case("live validation rechecks exactly one visible selected Body", function(assertions)
		isolated(assertions, function(scope)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			local model = newTemplate(assertions, scope, fixture, fixture.splash)
			success(
				assertions,
				TowerModelContract.selectLiveVariant(
					fixture.configuration,
					fixture.splash,
					fixture.splash.levels[3],
					model
				)
			)
			bodyAt(model, 1).Transparency = 0
			expectError(
				assertions,
				TowerModelContract.validateLive(fixture.configuration, fixture.splash, fixture.splash.levels[3], model),
				"INVALID_PROPERTY",
				"validateLive"
			)
		end)
	end),
})
