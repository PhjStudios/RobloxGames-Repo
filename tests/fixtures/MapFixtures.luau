--!strict

-- Fresh, detached, test-only Studio-style maps for the Phase 07 validator.
-- Nothing in this module is mapped into a production catalog.
local MapFixtures = {}

export type Fixture = {
	root: Model,
	geometry: Folder,
	markers: Folder,
	enemySpawns: Folder,
	pathNodes: Folder,
	defenderBase: Part,
	placementZones: Folder,
	noPlacementZones: Folder,
	mapBounds: Part,
	cameraAnchors: Folder,
	playerSpawns: Folder,
	enemySpawn: Part,
	nodes: { Part },
	placementZone: Part,
	noPlacementZone: Part,
	cameraAnchor: Part,
	playerSpawn: SpawnLocation,
}

MapFixtures.MAP_ID = "map:phase07-graybox"
MapFixtures.LANE_ID = "main"
MapFixtures.MAX_HELPER_CHILDREN = 2_048

MapFixtures.Tags = table.freeze({
	MapRoot = "ATD_MapRoot_v1",
	EnemySpawn = "ATD_EnemySpawn_v1",
	PathNode = "ATD_PathNode_v1",
	DefenderBase = "ATD_DefenderBase_v1",
	PlacementZone = "ATD_PlacementZone_v1",
	NoPlacementZone = "ATD_NoPlacementZone_v1",
	MapBounds = "ATD_MapBounds_v1",
	CameraAnchor = "ATD_CameraAnchor_v1",
	PlayerSpawn = "ATD_PlayerSpawn_v1",
})

MapFixtures.Attributes = table.freeze({
	MapId = "ATD_MapId",
	MapContractVersion = "ATD_MapContractVersion",
	LaneId = "ATD_LaneId",
	NodeOrder = "ATD_NodeOrder",
	ZoneId = "ATD_ZoneId",
	SurfaceCategory = "ATD_SurfaceCategory",
	AnchorId = "ATD_AnchorId",
	SpawnId = "ATD_SpawnId",
})

MapFixtures.Positions = table.freeze({
	EnemySpawn = Vector3.new(-40, 5, -20),
	Node1 = Vector3.new(-15, 5, -20),
	Node2 = Vector3.new(0, 5, 0),
	DefenderBase = Vector3.new(30, 5, 0),
	CameraAnchor = Vector3.new(0, 15, 35),
	PlayerSpawn = Vector3.new(35, 5, 25),
})

local function newFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function configurePart(part: BasePart, cframe: CFrame, size: Vector3, isPlayerSpawn: boolean?)
	part.CFrame = cframe
	part.Size = size
	part.Anchored = true
	if not isPlayerSpawn then
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
	end
end

local function newTaggedPart(
	className: "Part" | "SpawnLocation",
	name: string,
	tag: string,
	parent: Instance,
	cframe: CFrame,
	size: Vector3
): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	configurePart(part, cframe, size, className == "SpawnLocation")
	part:AddTag(tag)
	part.Parent = parent
	return part
end

local function assertHelperCapacity(parent: Instance)
	assert(#parent:GetChildren() < MapFixtures.MAX_HELPER_CHILDREN, "map fixture helper child limit exceeded")
end

function MapFixtures.createValidMap(): Fixture
	local root = Instance.new("Model")
	root.Name = "Map_phase07-graybox"
	root:AddTag(MapFixtures.Tags.MapRoot)
	root:SetAttribute(MapFixtures.Attributes.MapId, MapFixtures.MAP_ID)
	root:SetAttribute(MapFixtures.Attributes.MapContractVersion, 1)

	local geometry = newFolder("Geometry", root)
	local floor = Instance.new("Part")
	floor.Name = "GrayboxFloor"
	configurePart(floor, CFrame.new(0, -5, 0), Vector3.new(100, 2, 80))
	floor.Parent = geometry

	local markers = newFolder("Markers", root)
	local enemySpawns = newFolder("EnemySpawns", markers)
	local pathNodes = newFolder("PathNodes", markers)
	local placementZones = newFolder("PlacementZones", markers)
	local noPlacementZones = newFolder("NoPlacementZones", markers)
	local cameraAnchors = newFolder("CameraAnchors", markers)
	local playerSpawns = newFolder("PlayerSpawns", markers)

	local enemySpawn = newTaggedPart(
		"Part",
		"EnemySpawn_main",
		MapFixtures.Tags.EnemySpawn,
		enemySpawns,
		CFrame.new(MapFixtures.Positions.EnemySpawn),
		Vector3.new(2, 2, 2)
	) :: Part
	enemySpawn:SetAttribute(MapFixtures.Attributes.LaneId, MapFixtures.LANE_ID)

	local node1 = newTaggedPart(
		"Part",
		"PathNode_main_1",
		MapFixtures.Tags.PathNode,
		pathNodes,
		CFrame.new(MapFixtures.Positions.Node1),
		Vector3.new(1, 1, 1)
	) :: Part
	node1:SetAttribute(MapFixtures.Attributes.LaneId, MapFixtures.LANE_ID)
	node1:SetAttribute(MapFixtures.Attributes.NodeOrder, 1)

	local node2 = newTaggedPart(
		"Part",
		"PathNode_main_2",
		MapFixtures.Tags.PathNode,
		pathNodes,
		CFrame.new(MapFixtures.Positions.Node2),
		Vector3.new(1, 1, 1)
	) :: Part
	node2:SetAttribute(MapFixtures.Attributes.LaneId, MapFixtures.LANE_ID)
	node2:SetAttribute(MapFixtures.Attributes.NodeOrder, 2)

	local defenderBase = newTaggedPart(
		"Part",
		"DefenderBase",
		MapFixtures.Tags.DefenderBase,
		markers,
		CFrame.new(MapFixtures.Positions.DefenderBase),
		Vector3.new(3, 3, 3)
	) :: Part

	local placementZone = newTaggedPart(
		"Part",
		"PlacementZone_land",
		MapFixtures.Tags.PlacementZone,
		placementZones,
		CFrame.new(0, -3, 0),
		Vector3.new(90, 2, 70)
	) :: Part
	placementZone:SetAttribute(MapFixtures.Attributes.ZoneId, "land")
	placementZone:SetAttribute(MapFixtures.Attributes.SurfaceCategory, "Land")

	local noPlacementZone = newTaggedPart(
		"Part",
		"NoPlacementZone_lane",
		MapFixtures.Tags.NoPlacementZone,
		noPlacementZones,
		CFrame.new(-25, -3, 0),
		Vector3.new(10, 2, 10)
	) :: Part
	noPlacementZone:SetAttribute(MapFixtures.Attributes.ZoneId, "lane")

	local mapBounds = newTaggedPart(
		"Part",
		"MapBounds",
		MapFixtures.Tags.MapBounds,
		markers,
		CFrame.new(0, 0, 0),
		Vector3.new(120, 40, 100)
	) :: Part

	local cameraAnchor = newTaggedPart(
		"Part",
		"CameraAnchor_overview",
		MapFixtures.Tags.CameraAnchor,
		cameraAnchors,
		CFrame.new(MapFixtures.Positions.CameraAnchor),
		Vector3.new(1, 1, 1)
	) :: Part
	cameraAnchor:SetAttribute(MapFixtures.Attributes.AnchorId, "overview")

	local playerSpawn = newTaggedPart(
		"SpawnLocation",
		"PlayerSpawn_primary",
		MapFixtures.Tags.PlayerSpawn,
		playerSpawns,
		CFrame.new(MapFixtures.Positions.PlayerSpawn),
		Vector3.new(4, 1, 4)
	) :: SpawnLocation
	playerSpawn.Enabled = true
	playerSpawn.Neutral = true
	playerSpawn:SetAttribute(MapFixtures.Attributes.SpawnId, "primary")

	return {
		root = root,
		geometry = geometry,
		markers = markers,
		enemySpawns = enemySpawns,
		pathNodes = pathNodes,
		defenderBase = defenderBase,
		placementZones = placementZones,
		noPlacementZones = noPlacementZones,
		mapBounds = mapBounds,
		cameraAnchors = cameraAnchors,
		playerSpawns = playerSpawns,
		enemySpawn = enemySpawn,
		nodes = { node1, node2 },
		placementZone = placementZone,
		noPlacementZone = noPlacementZone,
		cameraAnchor = cameraAnchor,
		playerSpawn = playerSpawn,
	}
end

function MapFixtures.addPathNode(fixture: Fixture, laneId: string, order: number, position: Vector3): Part
	assertHelperCapacity(fixture.pathNodes)
	local node = newTaggedPart(
		"Part",
		`PathNode_{laneId}_{order}`,
		MapFixtures.Tags.PathNode,
		fixture.pathNodes,
		CFrame.new(position),
		Vector3.new(1, 1, 1)
	) :: Part
	node:SetAttribute(MapFixtures.Attributes.LaneId, laneId)
	node:SetAttribute(MapFixtures.Attributes.NodeOrder, order)
	return node
end

function MapFixtures.addEnemySpawn(fixture: Fixture, laneId: string, position: Vector3): Part
	assertHelperCapacity(fixture.enemySpawns)
	local spawn = newTaggedPart(
		"Part",
		`EnemySpawn_{laneId}`,
		MapFixtures.Tags.EnemySpawn,
		fixture.enemySpawns,
		CFrame.new(position),
		Vector3.new(2, 2, 2)
	) :: Part
	spawn:SetAttribute(MapFixtures.Attributes.LaneId, laneId)
	return spawn
end

function MapFixtures.addPlacementZone(
	fixture: Fixture,
	zoneId: string,
	cframe: CFrame,
	size: Vector3,
	surfaceCategory: string?
): Part
	assertHelperCapacity(fixture.placementZones)
	local zone = newTaggedPart(
		"Part",
		`PlacementZone_{zoneId}`,
		MapFixtures.Tags.PlacementZone,
		fixture.placementZones,
		cframe,
		size
	) :: Part
	zone:SetAttribute(MapFixtures.Attributes.ZoneId, zoneId)
	zone:SetAttribute(MapFixtures.Attributes.SurfaceCategory, surfaceCategory or "Land")
	return zone
end

function MapFixtures.addNoPlacementZone(fixture: Fixture, zoneId: string, cframe: CFrame, size: Vector3): Part
	assertHelperCapacity(fixture.noPlacementZones)
	local zone = newTaggedPart(
		"Part",
		`NoPlacementZone_{zoneId}`,
		MapFixtures.Tags.NoPlacementZone,
		fixture.noPlacementZones,
		cframe,
		size
	) :: Part
	zone:SetAttribute(MapFixtures.Attributes.ZoneId, zoneId)
	return zone
end

function MapFixtures.addUnexpectedMarkerChild(fixture: Fixture, name: string): Folder
	assertHelperCapacity(fixture.markers)
	return newFolder(name, fixture.markers)
end

function MapFixtures.destroy(fixture: Fixture)
	fixture.root:Destroy()
end

function MapFixtures.withValidMap(callback: (Fixture) -> ())
	local fixture = MapFixtures.createValidMap()
	local succeeded, failure = pcall(callback, fixture)
	MapFixtures.destroy(fixture)
	if not succeeded then
		error(failure, 0)
	end
end

local function serializeNumber(value: number): string
	if value ~= value then
		return "nan"
	elseif value == math.huge then
		return "+inf"
	elseif value == -math.huge then
		return "-inf"
	end
	return string.format("%.17g", value)
end

local function serializeValue(value: any): string
	local valueType = typeof(value)
	if valueType == "number" then
		return serializeNumber(value)
	elseif valueType == "string" or valueType == "boolean" then
		return tostring(value)
	elseif valueType == "Vector3" then
		return table.concat({
			serializeNumber(value.X),
			serializeNumber(value.Y),
			serializeNumber(value.Z),
		}, ",")
	elseif valueType == "CFrame" then
		local components = { value:GetComponents() }
		for index, component in components do
			components[index] = serializeNumber(component)
		end
		return table.concat(components, ",")
	end
	return valueType
end

local function relativePath(root: Instance, instance: Instance): string
	local segments = {}
	local cursor: Instance? = instance
	while cursor ~= nil and cursor ~= root do
		table.insert(segments, 1, cursor.Name)
		cursor = cursor.Parent
	end
	return if #segments == 0 then "Map" else `Map.{table.concat(segments, ".")}`
end

function MapFixtures.inventory(root: Instance): string
	local instances = { root }
	local nextIndex = 1
	while nextIndex <= #instances do
		local children = instances[nextIndex]:GetChildren()
		assert(#children <= MapFixtures.MAX_HELPER_CHILDREN, "map fixture inventory child limit exceeded")
		for _, child in children do
			assert(#instances < 4_096, "map fixture inventory traversal limit exceeded")
			table.insert(instances, child)
		end
		nextIndex += 1
	end

	local records = {}
	for _, instance in instances do
		local tags = instance:GetTags()
		table.sort(tags)
		local attributeRecords = {}
		for name, value in instance:GetAttributes() do
			table.insert(attributeRecords, `{name}:{typeof(value)}:{serializeValue(value)}`)
		end
		table.sort(attributeRecords)

		local properties = ""
		if instance:IsA("BasePart") then
			properties = table.concat({
				serializeValue(instance.CFrame),
				serializeValue(instance.Size),
				tostring(instance.Anchored),
				tostring(instance.CanCollide),
				tostring(instance.CanTouch),
				tostring(instance.CanQuery),
			}, ":")
		end
		if instance:IsA("SpawnLocation") then
			properties ..= `:{tostring(instance.Enabled)}:{tostring(instance.Neutral)}`
		end

		table.insert(
			records,
			table.concat({
				relativePath(root, instance),
				instance.ClassName,
				tostring(instance.Archivable),
				table.concat(tags, ","),
				table.concat(attributeRecords, ","),
				properties,
			}, "|")
		)
	end
	table.sort(records)
	return table.concat(records, "\n")
end

return table.freeze(MapFixtures)
