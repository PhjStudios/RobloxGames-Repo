--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local MapFixtures = require(script.Parent.Parent.Fixtures.MapFixtures)
local MapLoader = require(script.Parent.Parent.ProductionServerMaps.MapLoader)

local Shared = game:GetService("ReplicatedStorage").Shared
local EnvironmentContext = require(Shared.logging.EnvironmentContext)
local Log = require(Shared.logging.Log)

type Assertions = TestHarness.Assertions
type Fixture = MapFixtures.Fixture

type CaseScope = {
	owned: { Instance },
	loaders: { any },
}

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local logger = Log.new(EnvironmentContext.new("server", "Match", 0, false))

local CATALOG_NAME = "ATDMapTemplates"
local RUNTIME_NAME = "ATDRuntimeMap"
local OTHER_MAP_ID = "map:other"
local PRIVATE_CLONE_SENTINEL = "PRIVATE_MAP_CLONE_FAILURE_64d20c"

local ERROR_FIELDS: { [string]: boolean } = table.freeze({
	code = true,
	operation = true,
	state = true,
	validationReport = true,
})

local function directChildrenNamed(parent: Instance, name: string): { Instance }
	local matches = {}
	for _, child in parent:GetChildren() do
		if child.Name == name then
			table.insert(matches, child)
		end
	end
	return matches
end

local function destroyAll(instances: { Instance })
	for index = #instances, 1, -1 do
		instances[index]:Destroy()
	end
end

local function isolated(assertions: Assertions, callback: (CaseScope) -> ())
	assertions.equal(#directChildrenNamed(ServerStorage, CATALOG_NAME), 0)
	assertions.equal(#directChildrenNamed(Workspace, RUNTIME_NAME), 0)

	local scope: CaseScope = {
		owned = {},
		loaders = {},
	}
	local succeeded, failure = pcall(callback, scope)

	for index = #scope.loaders, 1, -1 do
		pcall(function()
			scope.loaders[index]:cleanup()
		end)
	end
	destroyAll(scope.owned)

	local leakedCatalogs = directChildrenNamed(ServerStorage, CATALOG_NAME)
	local leakedRuntimeRoots = directChildrenNamed(Workspace, RUNTIME_NAME)
	destroyAll(leakedCatalogs)
	destroyAll(leakedRuntimeRoots)

	if not succeeded then
		error(failure, 0)
	end
	assertions.equal(#leakedCatalogs, 0)
	assertions.equal(#leakedRuntimeRoots, 0)
end

local function own<T>(scope: CaseScope, instance: T): T
	table.insert(scope.owned, instance :: any)
	return instance
end

local function newCatalog(scope: CaseScope): Folder
	local catalog = own(scope, Instance.new("Folder"))
	catalog.Name = CATALOG_NAME
	catalog.Parent = ServerStorage
	return catalog
end

local function setMapIdentity(fixture: Fixture, mapId: string)
	fixture.root.Name = `Map_{string.sub(mapId, #"map:" + 1)}`
	fixture.root:SetAttribute(MapFixtures.Attributes.MapId, mapId)
end

local function addTemplate(catalog: Folder, mapId: string?): Fixture
	local fixture = MapFixtures.createValidMap()
	if mapId ~= nil then
		setMapIdentity(fixture, mapId)
	end
	fixture.root.Parent = catalog
	return fixture
end

local function trackLoader(scope: CaseScope, loader: any): any
	table.insert(scope.loaders, loader)
	return loader
end

local function newLoader(scope: CaseScope): any
	return trackLoader(scope, MapLoader.new(logger))
end

local function newLoaderForTests(scope: CaseScope, cloneTemplate: any): any
	return trackLoader(scope, MapLoader.newForTests(logger, cloneTemplate))
end

local function expectSuccess(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return result.value
end

local function expectError(
	assertions: Assertions,
	result: any,
	code: string,
	operation: string,
	state: string,
	expectValidationReport: boolean?
): any
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local errorValue = result.error
	assertions.isTrue(table.isfrozen(errorValue))
	assertions.equal(errorValue.code, code)
	assertions.equal(errorValue.operation, operation)
	assertions.equal(errorValue.state, state)

	local fieldCount = 0
	for fieldName in next, errorValue do
		fieldCount += 1
		assertions.isTrue(ERROR_FIELDS[fieldName] == true)
	end
	if expectValidationReport then
		assertions.equal(fieldCount, 4)
		assertions.isNotNil(errorValue.validationReport)
		assertions.isTrue(table.isfrozen(errorValue.validationReport))
		assertions.isTrue(table.isfrozen(errorValue.validationReport.issues))
	else
		assertions.equal(fieldCount, 3)
		assertions.isNil(errorValue.validationReport)
	end
	return errorValue
end

local function assertDeepFrozen(assertions: Assertions, value: unknown, seen: { [any]: boolean }?)
	if type(value) ~= "table" then
		return
	end

	local visited = seen or {}
	if visited[value] then
		return
	end
	visited[value] = true
	assertions.isTrue(table.isfrozen(value :: any))
	for key, child in next, value :: any do
		assertDeepFrozen(assertions, key, visited)
		assertDeepFrozen(assertions, child, visited)
	end
end

local function assertContainsNoInstance(assertions: Assertions, value: unknown, seen: { [any]: boolean }?)
	assertions.isFalse(typeof(value) == "Instance")
	if type(value) ~= "table" then
		return
	end

	local visited = seen or {}
	if visited[value] then
		return
	end
	visited[value] = true
	for key, child in next, value :: any do
		assertContainsNoInstance(assertions, key, visited)
		assertContainsNoInstance(assertions, child, visited)
	end
end

local function issueSignature(report: any): string
	local records = {}
	for _, issue in report.issues do
		table.insert(
			records,
			table.concat({
				tostring(issue.path),
				tostring(issue.code),
				tostring(issue.relatedPath),
				tostring(issue.message),
			}, "|")
		)
	end
	return table.concat(records, "\n")
end

local function runtimeRoot(): Instance?
	local roots = directChildrenNamed(Workspace, RUNTIME_NAME)
	if #roots ~= 1 then
		return nil
	end
	return roots[1]
end

local function assertNoRuntime(assertions: Assertions)
	assertions.equal(#directChildrenNamed(Workspace, RUNTIME_NAME), 0)
end

local function assertReleasedInstance(assertions: Assertions, instance: Instance)
	local readable, parent = pcall(function()
		return instance.Parent
	end)
	if readable then
		assertions.isNil(parent)
	end
end

local function assertMainLane(assertions: Assertions, lane: any)
	assertions.equal(lane.id, MapFixtures.LANE_ID)
	assertions.equal(lane.totalDistance, 80)
	assertions.equal(#lane.points, 4)

	local spawn = lane.points[1]
	local node1 = lane.points[2]
	local node2 = lane.points[3]
	local base = lane.points[4]
	assertions.equal(spawn.kind, "EnemySpawn")
	assertions.isNil(spawn.nodeOrder)
	assertions.equal(spawn.position, MapFixtures.Positions.EnemySpawn)
	assertions.equal(spawn.distance, 0)
	assertions.equal(node1.kind, "PathNode")
	assertions.equal(node1.nodeOrder, 1)
	assertions.equal(node1.position, MapFixtures.Positions.Node1)
	assertions.equal(node1.distance, 25)
	assertions.equal(node2.kind, "PathNode")
	assertions.equal(node2.nodeOrder, 2)
	assertions.equal(node2.position, MapFixtures.Positions.Node2)
	assertions.equal(node2.distance, 50)
	assertions.equal(base.kind, "DefenderBase")
	assertions.isNil(base.nodeOrder)
	assertions.equal(base.position, MapFixtures.Positions.DefenderBase)
	assertions.equal(base.distance, 80)

	local firstDirection = (node1.position - spawn.position).Unit
	local secondDirection = (node2.position - node1.position).Unit
	assertions.isTrue(firstDirection:Cross(secondDirection).Magnitude >= math.sin(math.rad(5)))
end

local function assertSnapshot(assertions: Assertions, snapshot: any)
	assertions.equal(snapshot.mapId, MapFixtures.MAP_ID)
	assertions.equal(snapshot.base.position, MapFixtures.Positions.DefenderBase)
	assertions.equal(snapshot.bounds.cframe, CFrame.new(0, 0, 0))
	assertions.equal(snapshot.bounds.size, Vector3.new(120, 40, 100))
	assertions.equal(#snapshot.lanes, 1)
	assertMainLane(assertions, snapshot.lanes[1])
	assertions.equal(#snapshot.placementZones, 1)
	assertions.equal(snapshot.placementZones[1].id, "land")
	assertions.equal(#snapshot.noPlacementZones, 1)
	assertions.equal(snapshot.noPlacementZones[1].id, "lane")
	assertions.equal(#snapshot.cameraAnchors, 1)
	assertions.equal(snapshot.cameraAnchors[1].id, "overview")
	assertions.equal(#snapshot.playerSpawns, 1)
	assertions.equal(snapshot.playerSpawns[1].id, "primary")
	assertDeepFrozen(assertions, snapshot)
	assertContainsNoInstance(assertions, snapshot)
end

return TestHarness.suite("server map loader transaction", {
	TestHarness.case("selects only the fixed trusted catalog by exact MapId", function(assertions)
		isolated(assertions, function(scope)
			local decoyCatalog = own(scope, Instance.new("Folder"))
			decoyCatalog.Name = "UntrustedMapTemplates"
			decoyCatalog.Parent = ServerStorage
			local decoy = addTemplate(decoyCatalog, MapFixtures.MAP_ID)
			local decoyBefore = MapFixtures.inventory(decoy.root)

			local catalog = newCatalog(scope)
			local other = addTemplate(catalog, OTHER_MAP_ID)
			local selected = addTemplate(catalog, MapFixtures.MAP_ID)
			local otherBefore = MapFixtures.inventory(other.root)
			local selectedBefore = MapFixtures.inventory(selected.root)
			local loader = newLoader(scope)

			local snapshot = expectSuccess(assertions, loader:load(MapFixtures.MAP_ID))
			assertions.equal(snapshot.mapId, MapFixtures.MAP_ID)
			assertions.equal(loader:getState(), "Loaded")
			assertions.equal(MapFixtures.inventory(decoy.root), decoyBefore)
			assertions.equal(MapFixtures.inventory(other.root), otherBefore)
			assertions.equal(MapFixtures.inventory(selected.root), selectedBefore)
			expectSuccess(assertions, loader:unload())
			assertNoRuntime(assertions)
		end)
	end),

	TestHarness.case("rejects invalid IDs missing roots and missing templates without publishing", function(assertions)
		isolated(assertions, function(scope)
			local loader = newLoader(scope)
			expectError(assertions, loader:load(17), "INVALID_MAP_ID", "load", "Idle")
			expectError(assertions, loader:load("enemy:wrong"), "INVALID_MAP_ID", "load", "Idle")
			expectError(assertions, loader:load(MapFixtures.MAP_ID), "CATALOG_ROOT_MISSING", "load", "Idle")
			assertions.equal(loader:getState(), "Idle")
			assertNoRuntime(assertions)

			local catalog = newCatalog(scope)
			local other = addTemplate(catalog, OTHER_MAP_ID)
			local before = MapFixtures.inventory(other.root)
			expectError(assertions, loader:load(MapFixtures.MAP_ID), "TEMPLATE_NOT_FOUND", "load", "Idle")
			assertions.equal(MapFixtures.inventory(other.root), before)
			assertNoRuntime(assertions)
		end)
	end),

	TestHarness.case("rejects conflicting and excessive catalog roots without changing them", function(assertions)
		isolated(assertions, function(scope)
			local wrongRoot = own(scope, Instance.new("Model"))
			wrongRoot.Name = CATALOG_NAME
			wrongRoot.Parent = ServerStorage
			local loader = newLoader(scope)
			expectError(assertions, loader:load(MapFixtures.MAP_ID), "CATALOG_ROOT_CONFLICT", "load", "Idle")
			assertions.equal(wrongRoot.Parent, ServerStorage)
			assertNoRuntime(assertions)
		end)

		isolated(assertions, function(scope)
			local first = newCatalog(scope)
			local second = newCatalog(scope)
			local loader = newLoader(scope)
			expectError(assertions, loader:load(MapFixtures.MAP_ID), "CATALOG_ROOT_CONFLICT", "load", "Idle")
			assertions.equal(first.Parent, ServerStorage)
			assertions.equal(second.Parent, ServerStorage)
			assertNoRuntime(assertions)
		end)

		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			for index = 1, 33 do
				local child = Instance.new("Model")
				child.Name = string.format("CatalogChild%02d", index)
				child.Parent = catalog
			end
			local loader = newLoader(scope)
			expectError(assertions, loader:load(MapFixtures.MAP_ID), "CATALOG_LIMIT_EXCEEDED", "load", "Idle")
			assertions.equal(#catalog:GetChildren(), 33)
			assertNoRuntime(assertions)
		end)
	end),

	TestHarness.case("rejects malformed and duplicate catalog definitions deterministically", function(assertions)
		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local malformed = Instance.new("Folder")
			malformed.Name = "NotAMapModel"
			malformed.Parent = catalog
			local loader = newLoader(scope)
			expectError(assertions, loader:load(MapFixtures.MAP_ID), "TEMPLATE_INVALID", "load", "Idle")
			assertions.equal(malformed.Parent, catalog)
			assertNoRuntime(assertions)
		end)

		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local first = addTemplate(catalog, MapFixtures.MAP_ID)
			local second = addTemplate(catalog, MapFixtures.MAP_ID)
			local firstBefore = MapFixtures.inventory(first.root)
			local secondBefore = MapFixtures.inventory(second.root)
			local loader = newLoader(scope)
			expectError(assertions, loader:load(MapFixtures.MAP_ID), "TEMPLATE_DUPLICATE", "load", "Idle")
			assertions.equal(MapFixtures.inventory(first.root), firstBefore)
			assertions.equal(MapFixtures.inventory(second.root), secondBefore)
			assertNoRuntime(assertions)
		end)
	end),

	TestHarness.case("validates the original before cloning and never mutates it", function(assertions)
		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local fixture = addTemplate(catalog, MapFixtures.MAP_ID)
			fixture.nodes[1].Archivable = false
			local before = MapFixtures.inventory(fixture.root)
			local cloneCalls = 0
			local loader = newLoaderForTests(scope, function(template: Model): Model?
				cloneCalls += 1
				return template:Clone()
			end)

			local errorValue =
				expectError(assertions, loader:load(MapFixtures.MAP_ID), "TEMPLATE_INVALID", "load", "Idle", true)
			assertions.isTrue(#errorValue.validationReport.issues >= 1)
			assertions.equal(cloneCalls, 0)
			assertions.equal(MapFixtures.inventory(fixture.root), before)
			assertNoRuntime(assertions)
			expectError(assertions, loader:getSnapshot(), "NOT_LOADED", "getSnapshot", "Idle")
		end)
	end),

	TestHarness.case("publishes parent last and derives one immutable bent route", function(assertions)
		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local fixture = addTemplate(catalog, MapFixtures.MAP_ID)
			local before = MapFixtures.inventory(fixture.root)
			local staged: Model? = nil
			local loader = newLoaderForTests(scope, function(template: Model): Model?
				staged = template:Clone()
				assertions.isNotNil(staged)
				assertions.isNil((staged :: Model).Parent)
				return staged
			end)
			assertions.isTrue(table.isfrozen(loader))

			local loadedSnapshot = expectSuccess(assertions, loader:load(MapFixtures.MAP_ID))
			assertSnapshot(assertions, loadedSnapshot)
			assertions.equal(loader:getState(), "Loaded")
			assertions.equal(runtimeRoot(), staged)
			assertions.equal((staged :: Model).Name, RUNTIME_NAME)
			assertions.equal((staged :: Model).Parent, Workspace)
			assertions.equal(MapFixtures.inventory(fixture.root), before)

			local queriedSnapshot = expectSuccess(assertions, loader:getSnapshot())
			assertSnapshot(assertions, queriedSnapshot)
			local queriedLane = expectSuccess(assertions, loader:getLane(MapFixtures.LANE_ID))
			assertMainLane(assertions, queriedLane)
			assertDeepFrozen(assertions, queriedLane)
			assertContainsNoInstance(assertions, queriedLane)

			assertions.isTrue(expectSuccess(assertions, loader:unload()))
			assertions.equal(loader:getState(), "Idle")
			assertReleasedInstance(assertions, staged :: Model)
			assertNoRuntime(assertions)
			assertions.isFalse(expectSuccess(assertions, loader:unload()))
		end)
	end),

	TestHarness.case("keeps snapshots detached from template and runtime mutation", function(assertions)
		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local fixture = addTemplate(catalog, MapFixtures.MAP_ID)
			local before = MapFixtures.inventory(fixture.root)
			local loader = newLoader(scope)
			local snapshot = expectSuccess(assertions, loader:load(MapFixtures.MAP_ID))
			local lane = expectSuccess(assertions, loader:getLane(MapFixtures.LANE_ID))

			local snapshotMutationSucceeded = pcall(function()
				local mutableSnapshot = snapshot :: any
				mutableSnapshot.mapId = OTHER_MAP_ID
			end)
			local laneMutationSucceeded = pcall(function()
				(lane.points :: any)[1] = lane.points[2]
			end)
			assertions.isFalse(snapshotMutationSucceeded)
			assertions.isFalse(laneMutationSucceeded)

			local originalTemplateCFrame = fixture.nodes[1].CFrame
			fixture.nodes[1].CFrame = CFrame.new(10, 5, 10)
			local runtime = runtimeRoot() :: Model
			local runtimeNode = runtime:FindFirstChild("PathNode_main_1", true) :: Part
			assertions.isNotNil(runtimeNode)
			runtimeNode.CFrame = CFrame.new(20, 5, 20)
			assertions.equal(snapshot.lanes[1].points[2].position, MapFixtures.Positions.Node1)
			assertions.equal(
				expectSuccess(assertions, loader:getSnapshot()).lanes[1].points[2].position,
				MapFixtures.Positions.Node1
			)
			fixture.nodes[1].CFrame = originalTemplateCFrame

			assertions.isTrue(expectSuccess(assertions, loader:unload()))
			assertions.equal(MapFixtures.inventory(fixture.root), before)
			assertions.equal(snapshot.lanes[1].points[4].distance, 80)
			assertContainsNoInstance(assertions, snapshot)
			assertNoRuntime(assertions)
		end)
	end),

	TestHarness.case("rolls back clone and staged validation failures with stable reports", function(assertions)
		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local fixture = addTemplate(catalog, MapFixtures.MAP_ID)
			local before = MapFixtures.inventory(fixture.root)
			local loader = newLoaderForTests(scope, function(_template: Model): Model?
				error(PRIVATE_CLONE_SENTINEL, 0)
			end)

			local cloneError = expectError(assertions, loader:load(MapFixtures.MAP_ID), "CLONE_FAILED", "load", "Idle")
			assertions.isNil(string.find(tostring(cloneError.code), PRIVATE_CLONE_SENTINEL, 1, true))
			assertions.equal(loader:getState(), "Idle")
			assertions.equal(MapFixtures.inventory(fixture.root), before)
			assertNoRuntime(assertions)
			expectError(assertions, loader:getSnapshot(), "NOT_LOADED", "getSnapshot", "Idle")
		end)

		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local fixture = addTemplate(catalog, MapFixtures.MAP_ID)
			local before = MapFixtures.inventory(fixture.root)
			local stagedRoots = {}
			local loader = newLoaderForTests(scope, function(template: Model): Model?
				local staged = template:Clone()
				local node = staged:FindFirstChild("PathNode_main_2", true) :: Part
				node:SetAttribute(MapFixtures.Attributes.NodeOrder, 4)
				node.Name = "PathNode_main_4"
				table.insert(stagedRoots, staged)
				return staged
			end)

			local first =
				expectError(assertions, loader:load(MapFixtures.MAP_ID), "TEMPLATE_INVALID", "load", "Idle", true)
			local second =
				expectError(assertions, loader:load(MapFixtures.MAP_ID), "TEMPLATE_INVALID", "load", "Idle", true)
			assertions.equal(issueSignature(first.validationReport), issueSignature(second.validationReport))
			assertions.equal(#stagedRoots, 2)
			for _, staged in stagedRoots do
				assertReleasedInstance(assertions, staged)
			end
			assertions.equal(MapFixtures.inventory(fixture.root), before)
			assertions.equal(loader:getState(), "Idle")
			assertNoRuntime(assertions)
		end)
	end),

	TestHarness.case("preserves early and late runtime-root conflicts", function(assertions)
		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local fixture = addTemplate(catalog, MapFixtures.MAP_ID)
			local templateBefore = MapFixtures.inventory(fixture.root)
			local conflict = own(scope, Instance.new("Model"))
			conflict.Name = RUNTIME_NAME
			local sentinel = Instance.new("Folder")
			sentinel.Name = "PreserveMe"
			sentinel.Parent = conflict
			conflict.Parent = Workspace
			local conflictBefore = MapFixtures.inventory(conflict)
			local loader = newLoader(scope)

			expectError(assertions, loader:load(MapFixtures.MAP_ID), "RUNTIME_ROOT_CONFLICT", "load", "Idle")
			assertions.equal(conflict.Parent, Workspace)
			assertions.equal(MapFixtures.inventory(conflict), conflictBefore)
			assertions.equal(MapFixtures.inventory(fixture.root), templateBefore)
			assertions.equal(#directChildrenNamed(Workspace, RUNTIME_NAME), 1)
		end)

		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local fixture = addTemplate(catalog, MapFixtures.MAP_ID)
			local templateBefore = MapFixtures.inventory(fixture.root)
			local lateConflict: Model? = nil
			local staged: Model? = nil
			local loader = newLoaderForTests(scope, function(template: Model): Model?
				local createdConflict = own(scope, Instance.new("Model"))
				createdConflict.Name = RUNTIME_NAME
				createdConflict.Parent = Workspace
				lateConflict = createdConflict
				staged = template:Clone()
				return staged
			end)

			expectError(assertions, loader:load(MapFixtures.MAP_ID), "RUNTIME_ROOT_CONFLICT", "load", "Idle")
			assertions.equal((lateConflict :: Model).Parent, Workspace)
			assertions.equal(runtimeRoot(), lateConflict)
			assertReleasedInstance(assertions, staged :: Model)
			assertions.equal(MapFixtures.inventory(fixture.root), templateBefore)
			assertions.equal(loader:getState(), "Idle")
		end)
	end),

	TestHarness.case("rejects duplicate load and every loading re-entry without corrupting state", function(assertions)
		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local fixture = addTemplate(catalog, MapFixtures.MAP_ID)
			local before = MapFixtures.inventory(fixture.root)
			local duringState: string? = nil
			local reentryResults = {}
			local loader: any = nil
			loader = newLoaderForTests(scope, function(template: Model): Model?
				duringState = loader:getState()
				table.insert(reentryResults, loader:load(MapFixtures.MAP_ID))
				table.insert(reentryResults, loader:getSnapshot())
				table.insert(reentryResults, loader:getLane(MapFixtures.LANE_ID))
				table.insert(reentryResults, loader:unload())
				table.insert(reentryResults, loader:cleanup())
				return template:Clone()
			end)

			local snapshot = expectSuccess(assertions, loader:load(MapFixtures.MAP_ID))
			assertions.equal(duringState, "Loading")
			local operations = { "load", "getSnapshot", "getLane", "unload", "cleanup" }
			assertions.equal(#reentryResults, #operations)
			for index, operation in operations do
				expectError(assertions, reentryResults[index], "INVALID_STATE", operation, "Loading")
			end
			assertions.equal(loader:getState(), "Loaded")
			local published = runtimeRoot()
			local duplicate =
				expectError(assertions, loader:load(MapFixtures.MAP_ID), "INVALID_STATE", "load", "Loaded")
			assertions.isNil(duplicate.validationReport)
			assertions.equal(runtimeRoot(), published)
			assertions.equal(expectSuccess(assertions, loader:getSnapshot()), snapshot)
			assertions.equal(MapFixtures.inventory(fixture.root), before)
			assertions.isTrue(expectSuccess(assertions, loader:unload()))
			assertNoRuntime(assertions)
		end)
	end),

	TestHarness.case("returns typed query errors without leaking or changing loaded data", function(assertions)
		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local fixture = addTemplate(catalog, MapFixtures.MAP_ID)
			local before = MapFixtures.inventory(fixture.root)
			local loader = newLoader(scope)

			expectError(assertions, loader:getSnapshot(), "NOT_LOADED", "getSnapshot", "Idle")
			expectError(assertions, loader:getLane(MapFixtures.LANE_ID), "NOT_LOADED", "getLane", "Idle")
			local snapshot = expectSuccess(assertions, loader:load(MapFixtures.MAP_ID))
			expectError(assertions, loader:getLane(7), "INVALID_LANE_ID", "getLane", "Loaded")
			expectError(assertions, loader:getLane("Bad Lane"), "INVALID_LANE_ID", "getLane", "Loaded")
			expectError(assertions, loader:getLane("missing"), "LANE_NOT_FOUND", "getLane", "Loaded")
			assertions.equal(expectSuccess(assertions, loader:getSnapshot()), snapshot)
			assertions.equal(MapFixtures.inventory(fixture.root), before)
			assertions.isTrue(expectSuccess(assertions, loader:unload()))
			expectError(assertions, loader:getSnapshot(), "NOT_LOADED", "getSnapshot", "Idle")
			assertNoRuntime(assertions)
		end)
	end),

	TestHarness.case("unloads reloads and cleans fresh roots with no retained query state", function(assertions)
		isolated(assertions, function(scope)
			local catalog = newCatalog(scope)
			local fixture = addTemplate(catalog, MapFixtures.MAP_ID)
			local before = MapFixtures.inventory(fixture.root)
			local loader = newLoader(scope)

			local firstSnapshot = expectSuccess(assertions, loader:load(MapFixtures.MAP_ID))
			local firstRoot = runtimeRoot() :: Model
			assertions.isTrue(expectSuccess(assertions, loader:unload()))
			assertReleasedInstance(assertions, firstRoot)
			assertNoRuntime(assertions)

			local secondSnapshot = expectSuccess(assertions, loader:load(MapFixtures.MAP_ID))
			local secondRoot = runtimeRoot() :: Model
			assertions.notEqual(secondRoot, firstRoot)
			assertions.notEqual(secondSnapshot, firstSnapshot)
			assertions.notEqual(secondSnapshot.lanes[1], firstSnapshot.lanes[1])
			assertSnapshot(assertions, firstSnapshot)
			assertSnapshot(assertions, secondSnapshot)
			assertions.equal(MapFixtures.inventory(fixture.root), before)

			assertions.isTrue(expectSuccess(assertions, loader:cleanup()))
			assertions.equal(loader:getState(), "Cleaned")
			assertReleasedInstance(assertions, secondRoot)
			assertNoRuntime(assertions)
			assertions.isFalse(expectSuccess(assertions, loader:cleanup()))
			assertions.equal(MapFixtures.inventory(fixture.root), before)

			expectError(assertions, loader:load(MapFixtures.MAP_ID), "INVALID_STATE", "load", "Cleaned")
			expectError(assertions, loader:getSnapshot(), "INVALID_STATE", "getSnapshot", "Cleaned")
			expectError(assertions, loader:getLane(MapFixtures.LANE_ID), "INVALID_STATE", "getLane", "Cleaned")
			expectError(assertions, loader:unload(), "INVALID_STATE", "unload", "Cleaned")
		end)

		isolated(assertions, function(scope)
			local loader = newLoader(scope)
			assertions.isFalse(expectSuccess(assertions, loader:unload()))
			assertions.isTrue(expectSuccess(assertions, loader:cleanup()))
			assertions.equal(loader:getState(), "Cleaned")
			assertions.isFalse(expectSuccess(assertions, loader:cleanup()))
			assertNoRuntime(assertions)
		end)
	end),
})
