--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local serverMaps = script.Parent.Parent.ProductionServerMaps
local MapContract = require(serverMaps.MapContract)

return TestHarness.suite("map tag and attribute contract", {
	TestHarness.case("publishes the exact fixed roots tags attributes and role order", function(assertions)
		assertions.equal(MapContract.CONTRACT_VERSION, 1)
		assertions.equal(MapContract.TRUSTED_CATALOG_NAME, "ATDMapTemplates")
		assertions.equal(MapContract.RUNTIME_ROOT_NAME, "ATDRuntimeMap")
		assertions.equal(MapContract.RESERVED_PREFIX, "ATD_")
		assertions.equal(MapContract.Tags.MapRoot, "ATD_MapRoot_v1")
		assertions.equal(MapContract.Attributes.MapId, "ATD_MapId")
		assertions.equal(MapContract.Attributes.NodeOrder, "ATD_NodeOrder")
		assertions.equal(MapContract.Attributes.SurfaceCategory, "ATD_SurfaceCategory")
		assertions.isTrue(MapContract.isSurfaceCategory("Land"))
		assertions.isTrue(MapContract.isSurfaceCategory("Elevated"))
		assertions.isTrue(MapContract.isSurfaceCategory("Water"))
		assertions.isFalse(MapContract.isSurfaceCategory("land"))
		assertions.isFalse(MapContract.isSurfaceCategory(nil))

		local roles = {}
		for _, definition in MapContract.listDefinitions() do
			table.insert(roles, definition.role)
		end
		assertions.equal(
			table.concat(roles, ","),
			"MapRoot,EnemySpawn,PathNode,DefenderBase,PlacementZone,NoPlacementZone,MapBounds,CameraAnchor,PlayerSpawn"
		)
	end),

	TestHarness.case("provides deterministic role and tag lookup identity", function(assertions)
		for _, definition in MapContract.listDefinitions() do
			assertions.equal(MapContract.getDefinition(definition.role), definition)
			assertions.equal(MapContract.getDefinitionByTag(definition.tag), definition)
		end
		assertions.isNil(MapContract.getDefinition("Unknown"))
		assertions.isNil(MapContract.getDefinitionByTag("ATD_Unknown_v1"))
		assertions.isNil(MapContract.getDefinition({}))
		assertions.isNil(MapContract.getDefinitionByTag(1))
	end),

	TestHarness.case("deeply freezes every canonical definition and lookup surface", function(assertions)
		assertions.isTrue(table.isfrozen(MapContract))
		assertions.isTrue(table.isfrozen(MapContract.Tags))
		assertions.isTrue(table.isfrozen(MapContract.Attributes))
		assertions.isTrue(table.isfrozen(MapContract.Names))
		assertions.isTrue(table.isfrozen(MapContract.Limits))
		assertions.isTrue(table.isfrozen(MapContract.listDefinitions()))
		for _, definition in MapContract.listDefinitions() do
			assertions.isTrue(table.isfrozen(definition))
			assertions.isTrue(table.isfrozen(definition.attributes))
			for _, attribute in definition.attributes do
				assertions.isTrue(table.isfrozen(attribute))
			end
		end
		local changed = pcall(function()
			(MapContract.Tags :: any).MapRoot = "changed"
		end)
		assertions.isFalse(changed)
	end),

	TestHarness.case("defines exact attribute types and numeric bounds", function(assertions)
		local root = MapContract.getDefinition("MapRoot")
		local node = MapContract.getDefinition("PathNode")
		local placement = MapContract.getDefinition("PlacementZone")
		assertions.isNotNil(root)
		assertions.isNotNil(node)
		assertions.isNotNil(placement)
		assertions.equal((root :: any).attributes[1].kind, "MapId")
		assertions.equal((root :: any).attributes[2].minimum, 1)
		assertions.equal((root :: any).attributes[2].maximum, 1)
		assertions.isTrue((root :: any).attributes[2].integer)
		assertions.equal((node :: any).attributes[2].kind, "NodeOrder")
		assertions.equal((node :: any).attributes[2].minimum, 1)
		assertions.equal((node :: any).attributes[2].maximum, 256)
		assertions.isTrue((node :: any).attributes[2].integer)
		assertions.equal((placement :: any).attributes[2].kind, "SurfaceCategory")
		assertions.isTrue((placement :: any).attributes[2].optional)
	end),

	TestHarness.case("formats only canonical map and marker names", function(assertions)
		assertions.equal(MapContract.formatMapName("map:phase07-graybox"), "Map_phase07-graybox")
		assertions.isNil(MapContract.formatMapName("phase07-graybox"))
		assertions.equal(MapContract.formatMemberName("EnemySpawn", "main", nil), "EnemySpawn_main")
		assertions.equal(MapContract.formatMemberName("PathNode", "main", 12), "PathNode_main_12")
		assertions.equal(MapContract.formatMemberName("DefenderBase", nil, nil), "DefenderBase")
		assertions.equal(MapContract.formatMemberName("MapBounds", nil, nil), "MapBounds")
		assertions.isNil(MapContract.formatMemberName("PathNode", "main", 0))
		assertions.isNil(MapContract.formatMemberName("PathNode", "main", 257))
		assertions.isNil(MapContract.formatMemberName("PlacementZone", "UPPERCASE", nil))
		assertions.isNil(MapContract.formatMemberName("CameraAnchor", "main", 1))
		assertions.isNil(MapContract.formatMemberName("MapRoot", "main", nil))
	end),

	TestHarness.case("separates runtime and stricter graybox geometry allowlists", function(assertions)
		assertions.isTrue(MapContract.isGeometryClass("Part"))
		assertions.isTrue(MapContract.isGeometryClass("MeshPart"))
		assertions.isTrue(MapContract.isGrayboxGeometryClass("Part"))
		assertions.isFalse(MapContract.isGrayboxGeometryClass("MeshPart"))
		assertions.isFalse(MapContract.isGeometryClass("Script"))
		assertions.isFalse(MapContract.isGeometryClass({}))
	end),

	TestHarness.case("publishes the reviewed traversal metadata and geometry limits", function(assertions)
		local limits = MapContract.Limits
		assertions.equal(limits.MAX_DESCENDANTS, 2_048)
		assertions.equal(limits.MAX_DEPTH, 32)
		assertions.equal(limits.MAX_CHILDREN, 2_048)
		assertions.equal(limits.MAX_TAGS_PER_INSTANCE, 8)
		assertions.equal(limits.MAX_ATTRIBUTES_PER_INSTANCE, 16)
		assertions.equal(limits.MAX_ISSUES, 256)
		assertions.equal(limits.MAX_LANES, 32)
		assertions.equal(limits.MAX_NODES_PER_LANE, 256)
		assertions.equal(limits.MAX_NODES_TOTAL, 1_024)
		assertions.equal(limits.MAX_SEGMENT_LENGTH, 512)
		assertions.equal(limits.MAX_LANE_LENGTH, 32_768)
		assertions.isTrue(limits.MIN_BEND_SINE > 0)
		assertions.isTrue(MapContract.isReservedName("ATD_MapId"))
		assertions.isFalse(MapContract.isReservedName("MapId"))
	end),
})
