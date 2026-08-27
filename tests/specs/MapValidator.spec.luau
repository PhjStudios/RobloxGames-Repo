--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local MapFixtures = require(script.Parent.Parent.Fixtures.MapFixtures)
local MapValidator = require(script.Parent.Parent.ProductionServerMaps.MapValidator)

local function hasIssue(issues: { any }, code: string?, pathFragment: string?): boolean
	for _, issue in issues do
		local codeMatches = code == nil or issue.code == code
		local pathMatches = pathFragment == nil
			or (type(issue.path) == "string" and string.find(issue.path, pathFragment, 1, true) ~= nil)
		if codeMatches and pathMatches then
			return true
		end
	end
	return false
end

local function expectRejected(
	assertions: any,
	fixture: MapFixtures.Fixture,
	expectedCode: string?,
	pathFragment: string?
)
	local result = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
	assertions.isFalse(result.ok)
	if result.ok then
		return
	end
	assertions.isTrue(table.isfrozen(result))
	assertions.isTrue(table.isfrozen(result.error))
	assertions.isTrue(table.isfrozen(result.error.issues))
	assertions.isTrue(#result.error.issues >= 1)
	assertions.isTrue(hasIssue(result.error.issues, expectedCode, pathFragment))
end

local function rejectedAfter(
	assertions: any,
	mutate: (MapFixtures.Fixture) -> (),
	expectedCode: string?,
	pathFragment: string?
)
	MapFixtures.withValidMap(function(fixture)
		mutate(fixture)
		expectRejected(assertions, fixture, expectedCode, pathFragment)
	end)
end

local function assertFrozenDetached(assertions: any, value: any, seen: { [any]: boolean })
	assertions.isFalse(typeof(value) == "Instance")
	if type(value) ~= "table" or seen[value] then
		return
	end
	seen[value] = true
	assertions.isTrue(table.isfrozen(value))
	for key, child in value do
		assertFrozenDetached(assertions, key, seen)
		assertFrozenDetached(assertions, child, seen)
	end
end

local function issueSignature(issues: { any }): string
	local records = {}
	for _, issue in issues do
		table.insert(
			records,
			table.concat({
				tostring(issue.path),
				tostring(issue.code),
				tostring(issue.relatedPath),
				tostring(issue.causeCode),
				tostring(issue.actualType),
				tostring(issue.message),
			}, "|")
		)
	end
	return table.concat(records, "\n")
end

local function collectIssues(fixture: MapFixtures.Fixture): { any }
	local result = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
	if result.ok then
		return {}
	end
	return result.error.issues
end

return TestHarness.suite("deterministic server map validator", {
	TestHarness.case(
		"returns the exact deeply frozen detached snapshot without mutating the candidate",
		function(assertions)
			local fixture = MapFixtures.createValidMap()
			local before = MapFixtures.inventory(fixture.root)
			local result = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
			local after = MapFixtures.inventory(fixture.root)

			assertions.isTrue(result.ok)
			assertions.equal(after, before)
			if not result.ok then
				MapFixtures.destroy(fixture)
				return
			end

			local snapshot = result.value
			assertFrozenDetached(assertions, result, {})
			assertions.equal(snapshot.mapId, MapFixtures.MAP_ID)
			assertions.equal(snapshot.base.position, MapFixtures.Positions.DefenderBase)
			assertions.equal(snapshot.bounds.cframe, fixture.mapBounds.CFrame)
			assertions.equal(snapshot.bounds.size, fixture.mapBounds.Size)
			assertions.equal(#snapshot.lanes, 1)
			assertions.equal(snapshot.lanes[1].id, MapFixtures.LANE_ID)
			assertions.equal(snapshot.lanes[1].spawn.position, MapFixtures.Positions.EnemySpawn)
			assertions.equal(#snapshot.lanes[1].nodes, 2)
			assertions.equal(snapshot.lanes[1].nodes[1].order, 1)
			assertions.equal(snapshot.lanes[1].nodes[1].position, MapFixtures.Positions.Node1)
			assertions.equal(snapshot.lanes[1].nodes[2].order, 2)
			assertions.equal(snapshot.lanes[1].nodes[2].position, MapFixtures.Positions.Node2)
			assertions.equal(#snapshot.placementZones, 1)
			assertions.equal(snapshot.placementZones[1].id, "land")
			assertions.equal(#snapshot.noPlacementZones, 1)
			assertions.equal(snapshot.noPlacementZones[1].id, "lane")
			assertions.equal(snapshot.cameraAnchors[1].id, "overview")
			assertions.equal(snapshot.playerSpawns[1].id, "primary")

			fixture.nodes[1].CFrame = CFrame.new(55, 5, 0)
			fixture.nodes[1]:SetAttribute(MapFixtures.Attributes.NodeOrder, 99)
			fixture.mapBounds.Size = Vector3.new(10, 10, 10)
			assertions.equal(snapshot.lanes[1].nodes[1].order, 1)
			assertions.equal(snapshot.lanes[1].nodes[1].position, MapFixtures.Positions.Node1)
			assertions.equal(snapshot.bounds.size, Vector3.new(120, 40, 100))

			MapFixtures.destroy(fixture)
			assertions.equal(snapshot.base.position, MapFixtures.Positions.DefenderBase)
			assertions.equal(snapshot.lanes[1].nodes[2].position, MapFixtures.Positions.Node2)
		end
	),

	TestHarness.case(
		"scopes discovery to the selected root and ignores unrelated parent siblings",
		function(assertions)
			local fixture = MapFixtures.createValidMap()
			local outside = Instance.new("Folder")
			outside.Name = "Outside"
			fixture.root.Parent = outside
			local privateSibling = Instance.new("Script")
			privateSibling.Name = "PRIVATE_OUTSIDE_SOURCE"
			privateSibling:AddTag(MapFixtures.Tags.PathNode)
			privateSibling:SetAttribute("ATD_PRIVATE_SENTINEL", "PRIVATE_ATTRIBUTE_VALUE")
			privateSibling.Parent = outside
			local before = MapFixtures.inventory(outside)

			local succeeded, failure = pcall(function()
				local result = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
				assertions.isTrue(result.ok)
				assertions.equal(MapFixtures.inventory(outside), before)
			end)
			outside:Destroy()
			if not succeeded then
				error(failure, 0)
			end
		end
	),

	TestHarness.case("allows bounded nonreserved metadata without copying it into the snapshot", function(assertions)
		MapFixtures.withValidMap(function(fixture)
			fixture.geometry:AddTag("BuilderOwned")
			fixture.geometry:SetAttribute("BuilderHint", CFrame.new(1, 2, 3))
			local result = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.isNil((result.value :: any).BuilderHint)
			end
		end)
	end),

	TestHarness.case("rejects invalid expected IDs without inspecting outside state", function(assertions)
		MapFixtures.withValidMap(function(fixture)
			local wrongType = MapValidator.validate(fixture.root, nil) :: any
			local mismatch = MapValidator.validate(fixture.root, "map:another") :: any
			assertions.isFalse(wrongType.ok)
			assertions.isFalse(mismatch.ok)
			if not wrongType.ok then
				assertions.isTrue(hasIssue(wrongType.error.issues, "INVALID_ID", "Map.ATD_MapId"))
			end
			if not mismatch.ok then
				assertions.isTrue(hasIssue(mismatch.error.issues, "INVALID_ID", "Map.ATD_MapId"))
			end
		end)
	end),

	TestHarness.case("rejects missing hierarchy wrong classes and wrong marker ancestry", function(assertions)
		local wrongRoot = Instance.new("Folder")
		local wrongRootResult = MapValidator.validate(wrongRoot, MapFixtures.MAP_ID) :: any
		wrongRoot:Destroy()
		assertions.isFalse(wrongRootResult.ok)
		if not wrongRootResult.ok then
			assertions.isTrue(hasIssue(wrongRootResult.error.issues, "INVALID_TYPE", "Map.ClassName"))
		end

		rejectedAfter(assertions, function(fixture)
			fixture.geometry:Destroy()
		end, "MISSING_FIELD", "Map.Geometry")

		rejectedAfter(assertions, function(fixture)
			local oldFolder = fixture.pathNodes
			local replacement = Instance.new("Model")
			replacement.Name = oldFolder.Name
			replacement.Parent = fixture.markers
			oldFolder:Destroy()
		end, "INVALID_TYPE", "Map.Markers.PathNodes")

		rejectedAfter(assertions, function(fixture)
			fixture.nodes[1].Parent = fixture.cameraAnchors
		end, "INVALID_REFERENCE", nil)
	end),

	TestHarness.case("rejects missing tags attributes and singleton cardinality", function(assertions)
		rejectedAfter(assertions, function(fixture)
			fixture.enemySpawn:RemoveTag(MapFixtures.Tags.EnemySpawn)
		end, "MISSING_FIELD", "EnemySpawns")

		rejectedAfter(assertions, function(fixture)
			fixture.nodes[1]:SetAttribute(MapFixtures.Attributes.NodeOrder, nil)
		end, "MISSING_FIELD", "ATD_NodeOrder")

		rejectedAfter(assertions, function(fixture)
			fixture.defenderBase:Destroy()
		end, "MISSING_FIELD", "DefenderBase")

		rejectedAfter(assertions, function(fixture)
			local duplicate = fixture.mapBounds:Clone()
			duplicate.Parent = fixture.markers
		end, "DUPLICATE_VALUE", "MapBounds")
	end),

	TestHarness.case("rejects unknown conflicting and malformed reserved metadata", function(assertions)
		rejectedAfter(assertions, function(fixture)
			fixture.root:AddTag("ATD_Unknown_v1")
		end, "UNKNOWN_FIELD", "tags")

		rejectedAfter(assertions, function(fixture)
			fixture.enemySpawn:AddTag(MapFixtures.Tags.PathNode)
		end, "UNKNOWN_FIELD", "tags")

		rejectedAfter(assertions, function(fixture)
			fixture.root:AddTag(MapFixtures.Tags.MapRoot)
		end, "DUPLICATE_VALUE", "tags")

		rejectedAfter(assertions, function(fixture)
			fixture.root:AddTag("Builder Tag")
		end, "INVALID_STRING", "tags")

		rejectedAfter(assertions, function(fixture)
			fixture.nodes[1]:SetAttribute("ATD_UnknownAttribute", true)
		end, "UNKNOWN_FIELD", "ATD_UnknownAttribute")

		rejectedAfter(assertions, function(fixture)
			fixture.nodes[1]:SetAttribute(MapFixtures.Attributes.NodeOrder, "1")
		end, "INVALID_TYPE", "ATD_NodeOrder")
	end),

	TestHarness.case("rejects malformed names map IDs versions and symbolic IDs", function(assertions)
		rejectedAfter(assertions, function(fixture)
			fixture.root.Name = "WrongMapName"
		end, "INVALID_STRING", "Map.Name")

		rejectedAfter(assertions, function(fixture)
			fixture.root:SetAttribute(MapFixtures.Attributes.MapId, "enemy:not-a-map")
		end, "INVALID_ID", "ATD_MapId")

		rejectedAfter(assertions, function(fixture)
			fixture.root:SetAttribute(MapFixtures.Attributes.MapId, string.rep("a", 10_000))
		end, "INVALID_ID", "ATD_MapId")

		rejectedAfter(assertions, function(fixture)
			fixture.root:SetAttribute(MapFixtures.Attributes.MapContractVersion, 2)
		end, "UNSUPPORTED_VERSION", "ATD_MapContractVersion")

		rejectedAfter(assertions, function(fixture)
			fixture.cameraAnchor:SetAttribute(MapFixtures.Attributes.AnchorId, "Bad Id")
		end, "INVALID_STRING", "ATD_AnchorId")
	end),

	TestHarness.case("rejects duplicate semantic IDs names and node orders", function(assertions)
		rejectedAfter(assertions, function(fixture)
			local duplicateSpawn = fixture.enemySpawn:Clone()
			duplicateSpawn.Parent = fixture.enemySpawns
		end, "DUPLICATE_ID", "EnemySpawns")

		rejectedAfter(assertions, function(fixture)
			fixture.nodes[2]:SetAttribute(MapFixtures.Attributes.NodeOrder, 1)
			fixture.nodes[2].Name = "PathNode_main_1"
		end, "DUPLICATE_VALUE", "PathNodes")

		rejectedAfter(assertions, function(fixture)
			local duplicateZone = fixture.placementZone:Clone()
			duplicateZone.Parent = fixture.placementZones
		end, "DUPLICATE_ID", "PlacementZones")
	end),

	TestHarness.case("sorts valid lanes lexically and nodes numerically", function(assertions)
		MapFixtures.withValidMap(function(fixture)
			MapFixtures.addEnemySpawn(fixture, "alpha", Vector3.new(-35, 5, 20))
			MapFixtures.addPathNode(fixture, "alpha", 1, Vector3.new(-5, 5, 20))
			local result = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.equal(#result.value.lanes, 2)
				assertions.equal(result.value.lanes[1].id, "alpha")
				assertions.equal(result.value.lanes[2].id, "main")
				assertions.equal(result.value.lanes[2].nodes[1].order, 1)
				assertions.equal(result.value.lanes[2].nodes[2].order, 2)
			end
		end)
	end),

	TestHarness.case("rejects lane order gaps fractional orders and unknown lanes", function(assertions)
		rejectedAfter(assertions, function(fixture)
			fixture.nodes[2]:SetAttribute(MapFixtures.Attributes.NodeOrder, 3)
			fixture.nodes[2].Name = "PathNode_main_3"
		end, "INVALID_ORDER", "PathNodes")

		rejectedAfter(assertions, function(fixture)
			fixture.nodes[1]:SetAttribute(MapFixtures.Attributes.NodeOrder, 1.5)
			fixture.nodes[1].Name = "PathNode_main_1.5"
		end, "NOT_INTEGER", "ATD_NodeOrder")

		rejectedAfter(assertions, function(fixture)
			fixture.nodes[2]:SetAttribute(MapFixtures.Attributes.LaneId, "ghost")
			fixture.nodes[2].Name = "PathNode_ghost_2"
		end, "INVALID_REFERENCE", "ATD_LaneId")

		rejectedAfter(assertions, function(fixture)
			MapFixtures.addEnemySpawn(fixture, "empty", Vector3.new(-35, 5, 20))
		end, "OUT_OF_RANGE", "PathNodes")
	end),

	TestHarness.case("rejects zero length disconnected and nonfinite path segments", function(assertions)
		rejectedAfter(assertions, function(fixture)
			fixture.nodes[1].CFrame = fixture.enemySpawn.CFrame
		end, nil, nil)

		rejectedAfter(assertions, function(fixture)
			fixture.mapBounds.Size = Vector3.new(2_000, 40, 100)
			fixture.nodes[2].CFrame = CFrame.new(600, 5, 0)
		end, "INVALID_REFERENCE", nil)

		rejectedAfter(assertions, function(fixture)
			local nan = 0 / 0
			fixture.nodes[1].CFrame = CFrame.new(nan, 5, 0)
		end, "NON_FINITE_NUMBER", nil)
	end),

	TestHarness.case("rejects nonfinite out of range rotated and unsafe BasePart geometry", function(assertions)
		rejectedAfter(assertions, function(fixture)
			fixture.cameraAnchor.CFrame = CFrame.new(100_001, 0, 0)
		end, "OUT_OF_RANGE", nil)

		rejectedAfter(assertions, function(fixture)
			fixture.enemySpawn.Size = Vector3.new(65, 1, 1)
		end, "OUT_OF_RANGE", "EnemySpawns")

		rejectedAfter(assertions, function(fixture)
			fixture.placementZone.CFrame = fixture.placementZone.CFrame * CFrame.Angles(0, math.rad(10), 0)
		end, "INVALID_ENUM", "PlacementZones")

		rejectedAfter(assertions, function(fixture)
			fixture.mapBounds.Size = Vector3.new(0.5, 40, 100)
		end, "OUT_OF_RANGE", "MapBounds")

		rejectedAfter(assertions, function(fixture)
			fixture.noPlacementZone.Size = Vector3.new(0.05, 1, 1)
		end, "OUT_OF_RANGE", "NoPlacementZones")

		rejectedAfter(assertions, function(fixture)
			local floor = fixture.geometry:FindFirstChild("GrayboxFloor") :: BasePart
			floor.Anchored = false
		end, nil, "Geometry")
	end),

	TestHarness.case("rejects executable unsafe or nonarchivable authored descendants", function(assertions)
		rejectedAfter(assertions, function(fixture)
			local source = Instance.new("Script")
			source.Name = "ForbiddenSource"
			source.Parent = fixture.geometry
		end, "INVALID_TYPE", "Geometry")

		rejectedAfter(assertions, function(fixture)
			fixture.nodes[1].Archivable = false
		end, nil, "Archivable")

		rejectedAfter(assertions, function(fixture)
			local child = Instance.new("Folder")
			child.Name = "UnexpectedChild"
			child.Parent = fixture.nodes[1]
		end, "UNKNOWN_FIELD", "children")

		local fixture = MapFixtures.createValidMap()
		local outside = Instance.new("Part")
		outside.Name = "OutsidePrimaryPart"
		fixture.root.PrimaryPart = outside
		local succeeded, failure = pcall(function()
			expectRejected(assertions, fixture, "INVALID_REFERENCE", "PrimaryPart")
		end)
		MapFixtures.destroy(fixture)
		outside:Destroy()
		if not succeeded then
			error(failure, 0)
		end
	end),

	TestHarness.case("enforces map containment and region overlap rules", function(assertions)
		rejectedAfter(assertions, function(fixture)
			fixture.placementZone.CFrame = CFrame.new(60, -3, 0)
		end, "INVALID_REFERENCE", "PlacementZones")

		rejectedAfter(assertions, function(fixture)
			fixture.noPlacementZone.CFrame = CFrame.new(50, -3, 40)
		end, "INVALID_REFERENCE", "NoPlacementZones")

		rejectedAfter(assertions, function(fixture)
			local floor = fixture.geometry:FindFirstChild("GrayboxFloor") :: BasePart
			floor.CFrame = CFrame.new(100, -5, 0)
		end, "INVALID_REFERENCE", "Geometry")

		rejectedAfter(assertions, function(fixture)
			MapFixtures.addPlacementZone(fixture, "overlap", CFrame.new(20, -3, 0), Vector3.new(30, 2, 30))
		end, "DUPLICATE_VALUE", "PlacementZones")

		rejectedAfter(assertions, function(fixture)
			MapFixtures.addNoPlacementZone(fixture, "blocked", CFrame.new(-25, -3, 2), Vector3.new(10, 2, 10))
		end, "DUPLICATE_VALUE", "NoPlacementZones")
	end),

	TestHarness.case("allows boundary contact without positive volume overlap", function(assertions)
		MapFixtures.withValidMap(function(fixture)
			fixture.placementZone.CFrame = CFrame.new(-20, -3, 0)
			fixture.placementZone.Size = Vector3.new(40, 2, 40)
			fixture.noPlacementZone.CFrame = CFrame.new(-25, -3, 0)
			MapFixtures.addPlacementZone(fixture, "right", CFrame.new(20, -3, 0), Vector3.new(40, 2, 40))
			local result = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
			assertions.isTrue(result.ok)
		end)
	end),

	TestHarness.case("enforces authored lane region and traversal limits", function(assertions)
		MapFixtures.withValidMap(function(fixture)
			for index = 1, 32 do
				local laneId = string.format("lane%02d", index)
				MapFixtures.addEnemySpawn(fixture, laneId, Vector3.new(-35, 5, 20))
				MapFixtures.addPathNode(fixture, laneId, 1, Vector3.new(-5, 5, 20))
			end
			expectRejected(assertions, fixture, "OUT_OF_RANGE", "EnemySpawns")
		end)

		MapFixtures.withValidMap(function(fixture)
			fixture.placementZone.CFrame = CFrame.new(-50, -3, -35)
			fixture.placementZone.Size = Vector3.new(0.2, 0.2, 0.2)
			fixture.noPlacementZone.CFrame = fixture.placementZone.CFrame
			fixture.noPlacementZone.Size = Vector3.new(0.1, 0.1, 0.1)
			for index = 1, 64 do
				local x = -48 + (index % 16) * 2
				local z = -32 + math.floor(index / 16) * 2
				MapFixtures.addPlacementZone(
					fixture,
					string.format("z%02d", index),
					CFrame.new(x, -3, z),
					Vector3.new(0.2, 0.2, 0.2)
				)
			end
			expectRejected(assertions, fixture, "OUT_OF_RANGE", "PlacementZones")
		end)

		MapFixtures.withValidMap(function(fixture)
			local parent: Instance = fixture.geometry
			for index = 1, 33 do
				local folder = Instance.new("Folder")
				folder.Name = string.format("Depth%02d", index)
				folder.Parent = parent
				parent = folder
			end
			expectRejected(assertions, fixture, "OUT_OF_RANGE", "Map.traversal")
		end)

		MapFixtures.withValidMap(function(fixture)
			for index = 1, 16 do
				fixture.root:SetAttribute(string.format("BuilderAttribute%02d", index), index)
			end
			expectRejected(assertions, fixture, "OUT_OF_RANGE", "Map.metadata")
		end)
	end),

	TestHarness.case("accepts the exact map-wide node limit and rejects one more", function(assertions)
		MapFixtures.withValidMap(function(fixture)
			fixture.enemySpawn:Destroy()
			for _, node in fixture.nodes do
				node:Destroy()
			end

			for laneIndex = 1, 4 do
				local laneId = `limit{laneIndex}`
				local z = -20 + laneIndex * 8
				MapFixtures.addEnemySpawn(fixture, laneId, Vector3.new(-50, 5, z))
				for order = 1, 256 do
					MapFixtures.addPathNode(fixture, laneId, order, Vector3.new(-50 + order * 0.3, 5, z))
				end
			end

			local boundary = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
			assertions.isTrue(boundary.ok)
			if not boundary.ok then
				return
			end
			assertions.equal(#boundary.value.lanes, 4)
			for _, lane in boundary.value.lanes do
				assertions.equal(#lane.nodes, 256)
			end

			MapFixtures.addEnemySpawn(fixture, "overflow", Vector3.new(-50, 5, 20))
			MapFixtures.addPathNode(fixture, "overflow", 1, Vector3.new(-49, 5, 20))
			expectRejected(assertions, fixture, "OUT_OF_RANGE", "PathNodes")
		end)
	end),

	TestHarness.case("produces identical issue order for opposite authored insertion order", function(assertions)
		local left = MapFixtures.createValidMap()
		local right = MapFixtures.createValidMap()

		MapFixtures.addUnexpectedMarkerChild(left, "ZedUnexpected")
		MapFixtures.addUnexpectedMarkerChild(left, "AlphaUnexpected")
		left.nodes[2]:SetAttribute(MapFixtures.Attributes.NodeOrder, 4)
		left.nodes[2].Name = "PathNode_main_4"

		MapFixtures.addUnexpectedMarkerChild(right, "AlphaUnexpected")
		MapFixtures.addUnexpectedMarkerChild(right, "ZedUnexpected")
		right.nodes[2]:SetAttribute(MapFixtures.Attributes.NodeOrder, 4)
		right.nodes[2].Name = "PathNode_main_4"

		local succeeded, failure = pcall(function()
			local leftIssues = collectIssues(left)
			local rightIssues = collectIssues(right)
			assertions.isTrue(#leftIssues >= 3)
			assertions.equal(issueSignature(leftIssues), issueSignature(rightIssues))
		end)
		MapFixtures.destroy(left)
		MapFixtures.destroy(right)
		if not succeeded then
			error(failure, 0)
		end
	end),

	TestHarness.case("caps comprehensive diagnostics with one deterministic terminal issue", function(assertions)
		MapFixtures.withValidMap(function(fixture)
			for index = 1, 300 do
				MapFixtures.addUnexpectedMarkerChild(fixture, string.format("Unexpected%03d", index))
			end
			local result = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
			assertions.isFalse(result.ok)
			if result.ok then
				return
			end
			local issues = result.error.issues
			assertions.equal(#issues, 256)
			assertions.equal(issues[256].code, "OUT_OF_RANGE")
			assertions.equal(issues[256].path, "Map.issues")
			assertions.isTrue(table.isfrozen(issues[256]))
		end)
	end),

	TestHarness.case("keeps diagnostics privacy safe for malformed authored values", function(assertions)
		MapFixtures.withValidMap(function(fixture)
			local privateValue = "PRIVATE_ATTRIBUTE_VALUE_91a7"
			local privateName = "PRIVATE UNSAFE INSTANCE NAME"
			fixture.enemySpawn.Name = privateName
			fixture.enemySpawn:SetAttribute("ATD_UnknownAttribute", privateValue)
			local result = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
			assertions.isFalse(result.ok)
			if result.ok then
				return
			end
			for _, issue in result.error.issues do
				local rendered = table.concat({
					tostring(issue.path),
					tostring(issue.relatedPath),
					tostring(issue.message),
				}, "|")
				assertions.isNil(string.find(rendered, privateName, 1, true))
				assertions.isNil(string.find(rendered, privateValue, 1, true))
			end
		end)
	end),

	TestHarness.case("bounds long geometry names out of deterministic diagnostics", function(assertions)
		MapFixtures.withValidMap(function(fixture)
			local privateName = `PRIVATE_GEOMETRY_NAME_5d73_{string.rep("A", 160)}`
			local floor = fixture.geometry:FindFirstChild("GrayboxFloor") :: BasePart
			floor.Name = privateName
			floor.Anchored = false

			local first = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
			local second = MapValidator.validate(fixture.root, MapFixtures.MAP_ID) :: any
			assertions.isFalse(first.ok)
			assertions.isFalse(second.ok)
			if first.ok or second.ok then
				return
			end
			assertions.equal(issueSignature(first.error.issues), issueSignature(second.error.issues))
			for _, issue in first.error.issues do
				local rendered = table.concat({
					tostring(issue.path),
					tostring(issue.relatedPath),
					tostring(issue.message),
				}, "|")
				assertions.isNil(string.find(rendered, privateName, 1, true))
				assertions.isTrue(#tostring(issue.path) <= 512)
				assertions.isTrue(#tostring(issue.relatedPath) <= 512)
			end
		end)
	end),
})
