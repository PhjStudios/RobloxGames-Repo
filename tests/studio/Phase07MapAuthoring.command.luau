--!strict

-- EDIT MODE ONLY. This file is intentionally unmapped.
--
-- Do not execute without explicit transaction-scoped persistence authorization.
-- This tracked source fails closed. If active Team Create is explicitly
-- authorized for the exact catalog, load this committed source and arm only the
-- executing in-memory copy after completing the identity and inventory preflight.
-- Parenting may synchronize immediately in Team Create. This command itself
-- never saves, publishes, changes settings, or invokes external services.
-- Before execution, the operator must also confirm that Studio visibly names
-- PHJGAMES as owner; the command independently verifies its fixed group ID.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

type ManifestRecord = {
	path: string,
	className: string,
	archivable: boolean,
	tags: { string },
	attributes: { [string]: unknown },
	properties: { [string]: unknown },
}

local PLACE_ID = 136401514513678
local CREATOR_ID = 35420107
local MAP_ID = "map:phase07-graybox"
local LANE_ID = "main"
local CATALOG_NAME = "ATDMapTemplates"
local MAP_NAME = "Map_phase07-graybox"
local RUNTIME_NAME = "ATDRuntimeMap"
local ABORT_TOKEN = "[ATD_PHASE07_AUTHORING_ABORT]"
-- Fail closed. Do not change the tracked value; an explicitly authorized
-- operator must arm only a reviewed in-memory copy for one exact transaction.
local EXECUTION_AUTHORIZATION = "BLOCKED_NO_PERSISTENCE_AUTHORIZATION"
local REQUIRED_EXECUTION_AUTHORIZATION = "IN_MEMORY_EXPLICIT_AUTHORIZATION_REQUIRED"
local MAX_INVENTORY_INSTANCES = 50_000
local MAX_INVENTORY_CHILDREN = 4_096
local MAX_INVENTORY_DEPTH = 128

local Tags = table.freeze({
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

local Attributes = table.freeze({
	MapId = "ATD_MapId",
	MapContractVersion = "ATD_MapContractVersion",
	LaneId = "ATD_LaneId",
	NodeOrder = "ATD_NodeOrder",
	ZoneId = "ATD_ZoneId",
	AnchorId = "ATD_AnchorId",
	SpawnId = "ATD_SpawnId",
})

local Positions = table.freeze({
	EnemySpawn = Vector3.new(-50, 2, -25),
	Node1 = Vector3.new(-20, 2, -25),
	Node2 = Vector3.new(-5, 2, 0),
	Node3 = Vector3.new(20, 2, 0),
	DefenderBase = Vector3.new(50, 2, 0),
	CameraAnchor = Vector3.new(0, 40, 40),
	PlayerSpawn = Vector3.new(40, 2, 30),
})

local GROUND_COLOR = Color3.fromRGB(92, 128, 74)
local ROAD_COLOR = Color3.fromRGB(72, 72, 78)
local MARKER_COLOR = Color3.fromRGB(255, 196, 64)
local PLAYER_SPAWN_COLOR = Color3.fromRGB(70, 150, 255)
local GROUND_CFRAME = CFrame.new(0, -2, 0)
local GROUND_SIZE = Vector3.new(130, 4, 110)
local BOUNDS_CFRAME = CFrame.new(0, 15, 0)
local BOUNDS_SIZE = Vector3.new(140, 60, 120)
local PLACEMENT_CFRAME = CFrame.new(0, -1, 0)
local PLACEMENT_SIZE = Vector3.new(130, 2, 110)
local NO_PLACEMENT_CFRAME = CFrame.new(0, -1, -12.5)
local NO_PLACEMENT_SIZE = Vector3.new(110, 2, 50)

local function roadGeometry(startPosition: Vector3, endPosition: Vector3): (CFrame, Vector3)
	local start = Vector3.new(startPosition.X, 0.25, startPosition.Z)
	local finish = Vector3.new(endPosition.X, 0.25, endPosition.Z)
	local midpoint = (start + finish) * 0.5
	return CFrame.lookAt(midpoint, finish), Vector3.new(8, 0.5, (finish - start).Magnitude)
end

local ROAD_1_CFRAME, ROAD_1_SIZE = roadGeometry(Positions.EnemySpawn, Positions.Node1)
local ROAD_2_CFRAME, ROAD_2_SIZE = roadGeometry(Positions.Node1, Positions.Node2)
local ROAD_3_CFRAME, ROAD_3_SIZE = roadGeometry(Positions.Node2, Positions.Node3)
local ROAD_4_CFRAME, ROAD_4_SIZE = roadGeometry(Positions.Node3, Positions.DefenderBase)

local failureCode = "UNEXPECTED_FAILURE"
local candidateCatalog: Folder? = nil
local loader: any = nil
local beforeInventory: { string }? = nil

local function abort(code: string): never
	failureCode = code
	error(ABORT_TOKEN, 0)
end

local function requireCondition(condition: boolean, code: string)
	if not condition then
		abort(code)
	end
end

local function frozenArray(values: { string }): { string }
	return table.freeze(values)
end

local function frozenDictionary(values: { [string]: unknown }): { [string]: unknown }
	return table.freeze(values)
end

local EMPTY_TAGS = frozenArray({})
local EMPTY_FIELDS = frozenDictionary({})

local function oneTag(tag: string): { string }
	return frozenArray({ tag })
end

local function basePartProperties(
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	transparency: number,
	canCollide: boolean,
	canTouch: boolean,
	canQuery: boolean
): { [string]: unknown }
	return frozenDictionary({
		Anchored = true,
		CanCollide = canCollide,
		CanQuery = canQuery,
		CanTouch = canTouch,
		CastShadow = true,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Size = size,
		Transparency = transparency,
	})
end

local function spawnProperties(cframe: CFrame, size: Vector3): { [string]: unknown }
	local properties = {
		Anchored = true,
		CanCollide = true,
		CanQuery = true,
		CanTouch = true,
		CastShadow = true,
		CFrame = cframe,
		Color = PLAYER_SPAWN_COLOR,
		Enabled = true,
		Material = Enum.Material.SmoothPlastic,
		Neutral = true,
		Size = size,
		Transparency = 0.25,
	}
	return frozenDictionary(properties)
end

local function manifestRecord(
	path: string,
	className: string,
	tags: { string }?,
	attributes: { [string]: unknown }?,
	properties: { [string]: unknown }?
): ManifestRecord
	return table.freeze({
		path = path,
		className = className,
		archivable = true,
		tags = tags or EMPTY_TAGS,
		attributes = attributes or EMPTY_FIELDS,
		properties = properties or EMPTY_FIELDS,
	})
end

local CATALOG_PATH = "ServerStorage.ATDMapTemplates"
local MAP_PATH = `{CATALOG_PATH}.Map_phase07-graybox`
local GEOMETRY_PATH = `{MAP_PATH}.Geometry`
local MARKERS_PATH = `{MAP_PATH}.Markers`
local POINT_PROPERTIES = function(position: Vector3, size: Vector3): { [string]: unknown }
	return basePartProperties(CFrame.new(position), size, MARKER_COLOR, 1, false, false, false)
end
local REGION_PROPERTIES = function(cframe: CFrame, size: Vector3): { [string]: unknown }
	return basePartProperties(cframe, size, MARKER_COLOR, 1, false, false, false)
end

-- This frozen manifest is the only persistent delta this command accepts.
local EXPECTED_MANIFEST: { ManifestRecord } = table.freeze({
	manifestRecord(CATALOG_PATH, "Folder"),
	manifestRecord(
		MAP_PATH,
		"Model",
		oneTag(Tags.MapRoot),
		frozenDictionary({
			[Attributes.MapContractVersion] = 1,
			[Attributes.MapId] = MAP_ID,
		})
	),
	manifestRecord(GEOMETRY_PATH, "Folder"),
	manifestRecord(
		`{GEOMETRY_PATH}.Ground`,
		"Part",
		nil,
		nil,
		basePartProperties(GROUND_CFRAME, GROUND_SIZE, GROUND_COLOR, 0, true, true, true)
	),
	manifestRecord(
		`{GEOMETRY_PATH}.Road_01`,
		"Part",
		nil,
		nil,
		basePartProperties(ROAD_1_CFRAME, ROAD_1_SIZE, ROAD_COLOR, 0, true, true, true)
	),
	manifestRecord(
		`{GEOMETRY_PATH}.Road_02`,
		"Part",
		nil,
		nil,
		basePartProperties(ROAD_2_CFRAME, ROAD_2_SIZE, ROAD_COLOR, 0, true, true, true)
	),
	manifestRecord(
		`{GEOMETRY_PATH}.Road_03`,
		"Part",
		nil,
		nil,
		basePartProperties(ROAD_3_CFRAME, ROAD_3_SIZE, ROAD_COLOR, 0, true, true, true)
	),
	manifestRecord(
		`{GEOMETRY_PATH}.Road_04`,
		"Part",
		nil,
		nil,
		basePartProperties(ROAD_4_CFRAME, ROAD_4_SIZE, ROAD_COLOR, 0, true, true, true)
	),
	manifestRecord(MARKERS_PATH, "Folder"),
	manifestRecord(`{MARKERS_PATH}.EnemySpawns`, "Folder"),
	manifestRecord(
		`{MARKERS_PATH}.EnemySpawns.EnemySpawn_main`,
		"Part",
		oneTag(Tags.EnemySpawn),
		frozenDictionary({ [Attributes.LaneId] = LANE_ID }),
		POINT_PROPERTIES(Positions.EnemySpawn, Vector3.new(2, 2, 2))
	),
	manifestRecord(`{MARKERS_PATH}.PathNodes`, "Folder"),
	manifestRecord(
		`{MARKERS_PATH}.PathNodes.PathNode_main_1`,
		"Part",
		oneTag(Tags.PathNode),
		frozenDictionary({ [Attributes.LaneId] = LANE_ID, [Attributes.NodeOrder] = 1 }),
		POINT_PROPERTIES(Positions.Node1, Vector3.new(1, 1, 1))
	),
	manifestRecord(
		`{MARKERS_PATH}.PathNodes.PathNode_main_2`,
		"Part",
		oneTag(Tags.PathNode),
		frozenDictionary({ [Attributes.LaneId] = LANE_ID, [Attributes.NodeOrder] = 2 }),
		POINT_PROPERTIES(Positions.Node2, Vector3.new(1, 1, 1))
	),
	manifestRecord(
		`{MARKERS_PATH}.PathNodes.PathNode_main_3`,
		"Part",
		oneTag(Tags.PathNode),
		frozenDictionary({ [Attributes.LaneId] = LANE_ID, [Attributes.NodeOrder] = 3 }),
		POINT_PROPERTIES(Positions.Node3, Vector3.new(1, 1, 1))
	),
	manifestRecord(
		`{MARKERS_PATH}.DefenderBase`,
		"Part",
		oneTag(Tags.DefenderBase),
		nil,
		POINT_PROPERTIES(Positions.DefenderBase, Vector3.new(3, 3, 3))
	),
	manifestRecord(`{MARKERS_PATH}.PlacementZones`, "Folder"),
	manifestRecord(
		`{MARKERS_PATH}.PlacementZones.PlacementZone_land`,
		"Part",
		oneTag(Tags.PlacementZone),
		frozenDictionary({ [Attributes.ZoneId] = "land" }),
		REGION_PROPERTIES(PLACEMENT_CFRAME, PLACEMENT_SIZE)
	),
	manifestRecord(`{MARKERS_PATH}.NoPlacementZones`, "Folder"),
	manifestRecord(
		`{MARKERS_PATH}.NoPlacementZones.NoPlacementZone_lane`,
		"Part",
		oneTag(Tags.NoPlacementZone),
		frozenDictionary({ [Attributes.ZoneId] = "lane" }),
		REGION_PROPERTIES(NO_PLACEMENT_CFRAME, NO_PLACEMENT_SIZE)
	),
	manifestRecord(
		`{MARKERS_PATH}.MapBounds`,
		"Part",
		oneTag(Tags.MapBounds),
		nil,
		REGION_PROPERTIES(BOUNDS_CFRAME, BOUNDS_SIZE)
	),
	manifestRecord(`{MARKERS_PATH}.CameraAnchors`, "Folder"),
	manifestRecord(
		`{MARKERS_PATH}.CameraAnchors.CameraAnchor_overview`,
		"Part",
		oneTag(Tags.CameraAnchor),
		frozenDictionary({ [Attributes.AnchorId] = "overview" }),
		POINT_PROPERTIES(Positions.CameraAnchor, Vector3.new(1, 1, 1))
	),
	manifestRecord(`{MARKERS_PATH}.PlayerSpawns`, "Folder"),
	manifestRecord(
		`{MARKERS_PATH}.PlayerSpawns.PlayerSpawn_primary`,
		"SpawnLocation",
		oneTag(Tags.PlayerSpawn),
		frozenDictionary({ [Attributes.SpawnId] = "primary" }),
		spawnProperties(CFrame.new(Positions.PlayerSpawn), Vector3.new(4, 1, 4))
	),
})

local PERSISTENT_ROOT_CLASSES: { [string]: boolean } = table.freeze({
	Lighting = true,
	MaterialService = true,
	ReplicatedFirst = true,
	ReplicatedStorage = true,
	ServerScriptService = true,
	ServerStorage = true,
	SoundService = true,
	StarterGui = true,
	StarterPack = true,
	StarterPlayer = true,
	Teams = true,
	TextChatService = true,
	Workspace = true,
})

local function persistentRoots(): { Instance }
	local roots = {}
	for _, child in game:GetChildren() do
		if PERSISTENT_ROOT_CLASSES[child.ClassName] == true then
			table.insert(roots, child)
		end
	end
	table.sort(roots, function(left, right)
		if left.Name == right.Name then
			return left.ClassName < right.ClassName
		end
		return left.Name < right.Name
	end)
	return roots
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

local function lengthPrefix(value: string): string
	return `{#value}:{value}`
end

local function serializeValue(value: unknown): string
	local valueType = typeof(value)
	if valueType == "nil" then
		return "nil"
	elseif valueType == "number" then
		return `number:{serializeNumber(value :: number)}`
	elseif valueType == "string" then
		return `string:{lengthPrefix(value :: string)}`
	elseif valueType == "boolean" then
		return `boolean:{tostring(value)}`
	elseif valueType == "Vector2" then
		local vector = value :: Vector2
		return `Vector2:{serializeNumber(vector.X)},{serializeNumber(vector.Y)}`
	elseif valueType == "Vector3" then
		local vector = value :: Vector3
		return `Vector3:{serializeNumber(vector.X)},{serializeNumber(vector.Y)},{serializeNumber(vector.Z)}`
	elseif valueType == "Color3" then
		local color = value :: Color3
		return `Color3:{serializeNumber(color.R)},{serializeNumber(color.G)},{serializeNumber(color.B)}`
	elseif valueType == "CFrame" then
		local components = { (value :: CFrame):GetComponents() }
		local serialized = {}
		for _, component in components do
			table.insert(serialized, serializeNumber(component))
		end
		return `CFrame:{table.concat(serialized, ",")}`
	elseif valueType == "UDim" then
		local dimension = value :: UDim
		return `UDim:{serializeNumber(dimension.Scale)},{dimension.Offset}`
	elseif valueType == "UDim2" then
		local dimension = value :: UDim2
		return `UDim2:{serializeValue(dimension.X)},{serializeValue(dimension.Y)}`
	elseif valueType == "Rect" then
		local rectangle = value :: Rect
		return `Rect:{serializeValue(rectangle.Min)},{serializeValue(rectangle.Max)}`
	elseif valueType == "NumberRange" then
		local range = value :: NumberRange
		return `NumberRange:{serializeNumber(range.Min)},{serializeNumber(range.Max)}`
	elseif valueType == "BrickColor" then
		return `BrickColor:{(value :: BrickColor).Number}`
	elseif valueType == "EnumItem" then
		return `EnumItem:{tostring(value)}`
	end
	return `{valueType}:{lengthPrefix(tostring(value))}`
end

local function serializeTags(tags: { string }): string
	local copy = table.clone(tags)
	table.sort(copy)
	local records = {}
	for _, tag in copy do
		table.insert(records, lengthPrefix(tag))
	end
	return table.concat(records, ",")
end

local function serializeDictionary(values: { [string]: unknown }): string
	local names = {}
	for name in values do
		table.insert(names, name)
	end
	table.sort(names)
	local records = {}
	for _, name in names do
		table.insert(records, `{lengthPrefix(name)}={lengthPrefix(serializeValue(values[name]))}`)
	end
	return table.concat(records, ",")
end

local function propertiesFor(instance: Instance): { [string]: unknown }
	local properties: { [string]: unknown } = {}
	if instance:IsA("BasePart") then
		local part = instance :: BasePart
		properties.Anchored = part.Anchored
		properties.CanCollide = part.CanCollide
		properties.CanQuery = part.CanQuery
		properties.CanTouch = part.CanTouch
		properties.CastShadow = part.CastShadow
		properties.CFrame = part.CFrame
		properties.Color = part.Color
		properties.Material = part.Material
		properties.Size = part.Size
		properties.Transparency = part.Transparency
	end
	if instance:IsA("SpawnLocation") then
		local spawn = instance :: SpawnLocation
		properties.Enabled = spawn.Enabled
		properties.Neutral = spawn.Neutral
	end
	if instance:IsA("LuaSourceContainer") then
		local readable, source = pcall(function()
			return (instance :: LuaSourceContainer).Source
		end)
		if not readable or type(source) ~= "string" then
			abort("SOURCE_INVENTORY_UNREADABLE")
		end
		properties.Source = source
	end
	if instance:IsA("BaseScript") then
		properties.Disabled = (instance :: BaseScript).Disabled
	end
	return properties
end

local function recordString(record: ManifestRecord): string
	return table.concat({
		lengthPrefix(record.path),
		lengthPrefix(record.className),
		tostring(record.archivable),
		lengthPrefix(serializeTags(record.tags)),
		lengthPrefix(serializeDictionary(record.attributes)),
		lengthPrefix(serializeDictionary(record.properties)),
	}, "|")
end

local function instanceRecord(instance: Instance, path: string): string
	return recordString({
		path = path,
		className = instance.ClassName,
		archivable = instance.Archivable,
		tags = instance:GetTags(),
		attributes = instance:GetAttributes(),
		properties = propertiesFor(instance),
	})
end

local function inventorySubtrees(roots: { { instance: Instance, path: string } }): { string }
	local records = {}
	local queue: { { instance: Instance, path: string, depth: number } } = {}
	for _, root in roots do
		table.insert(queue, { instance = root.instance, path = root.path, depth = 0 })
	end

	local nextIndex = 1
	while nextIndex <= #queue do
		local current = queue[nextIndex]
		nextIndex += 1
		requireCondition(current.depth <= MAX_INVENTORY_DEPTH, "INVENTORY_DEPTH_EXCEEDED")
		requireCondition(#records < MAX_INVENTORY_INSTANCES, "INVENTORY_INSTANCE_LIMIT_EXCEEDED")
		table.insert(records, instanceRecord(current.instance, current.path))

		local children = current.instance:GetChildren()
		requireCondition(#children <= MAX_INVENTORY_CHILDREN, "INVENTORY_CHILD_LIMIT_EXCEEDED")
		for _, child in children do
			table.insert(queue, {
				instance = child,
				path = `{current.path}.{child.Name}`,
				depth = current.depth + 1,
			})
		end
	end
	table.sort(records)
	return records
end

local function persistentInventory(): { string }
	local roots = {}
	for _, root in persistentRoots() do
		table.insert(roots, { instance = root, path = root.Name })
	end
	return inventorySubtrees(roots)
end

local function expectedRecords(): { string }
	local records = {}
	for _, record in EXPECTED_MANIFEST do
		table.insert(records, recordString(record))
	end
	table.sort(records)
	return records
end

local function arraysEqual(left: { string }, right: { string }): boolean
	if #left ~= #right then
		return false
	end
	for index, value in left do
		if value ~= right[index] then
			return false
		end
	end
	return true
end

local function inventoryDelta(after: { string }, before: { string }): ({ string }, { string })
	local counts: { [string]: number } = {}
	for _, record in before do
		counts[record] = (counts[record] or 0) + 1
	end
	local added = {}
	for _, record in after do
		local remaining = counts[record] or 0
		if remaining > 0 then
			counts[record] = remaining - 1
		else
			table.insert(added, record)
		end
	end
	local removed = {}
	for record, count in counts do
		for _ = 1, count do
			table.insert(removed, record)
		end
	end
	table.sort(added)
	table.sort(removed)
	return added, removed
end

local function directNamedChildren(parent: Instance, name: string): { Instance }
	local matches = {}
	for _, child in parent:GetChildren() do
		if child.Name == name then
			table.insert(matches, child)
		end
	end
	return matches
end

local function newFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function configurePart(
	part: BasePart,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	transparency: number,
	canCollide: boolean,
	canTouch: boolean,
	canQuery: boolean
)
	part.CFrame = cframe
	part.Size = size
	part.Color = color
	part.Transparency = transparency
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = canCollide
	part.CanTouch = canTouch
	part.CanQuery = canQuery
	part.CastShadow = true
end

local function newGeometryPart(name: string, parent: Instance, cframe: CFrame, size: Vector3, color: Color3)
	local part = Instance.new("Part")
	part.Name = name
	configurePart(part, cframe, size, color, 0, true, true, true)
	part.Parent = parent
end

local function newMarkerPart(name: string, tag: string, parent: Instance, cframe: CFrame, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	configurePart(part, cframe, size, MARKER_COLOR, 1, false, false, false)
	part:AddTag(tag)
	part.Parent = parent
	return part
end

local function buildDetachedCandidate(): (Folder, Model)
	local catalog = Instance.new("Folder")
	catalog.Name = CATALOG_NAME

	local map = Instance.new("Model")
	map.Name = MAP_NAME
	map:AddTag(Tags.MapRoot)
	map:SetAttribute(Attributes.MapId, MAP_ID)
	map:SetAttribute(Attributes.MapContractVersion, 1)
	map.Parent = catalog

	local geometry = newFolder("Geometry", map)
	newGeometryPart("Ground", geometry, GROUND_CFRAME, GROUND_SIZE, GROUND_COLOR)
	newGeometryPart("Road_01", geometry, ROAD_1_CFRAME, ROAD_1_SIZE, ROAD_COLOR)
	newGeometryPart("Road_02", geometry, ROAD_2_CFRAME, ROAD_2_SIZE, ROAD_COLOR)
	newGeometryPart("Road_03", geometry, ROAD_3_CFRAME, ROAD_3_SIZE, ROAD_COLOR)
	newGeometryPart("Road_04", geometry, ROAD_4_CFRAME, ROAD_4_SIZE, ROAD_COLOR)

	local markers = newFolder("Markers", map)
	local enemySpawns = newFolder("EnemySpawns", markers)
	local pathNodes = newFolder("PathNodes", markers)
	local placementZones = newFolder("PlacementZones", markers)
	local noPlacementZones = newFolder("NoPlacementZones", markers)
	local cameraAnchors = newFolder("CameraAnchors", markers)
	local playerSpawns = newFolder("PlayerSpawns", markers)

	local enemySpawn = newMarkerPart(
		"EnemySpawn_main",
		Tags.EnemySpawn,
		enemySpawns,
		CFrame.new(Positions.EnemySpawn),
		Vector3.new(2, 2, 2)
	)
	enemySpawn:SetAttribute(Attributes.LaneId, LANE_ID)

	for order, position in { Positions.Node1, Positions.Node2, Positions.Node3 } do
		local node =
			newMarkerPart(`PathNode_main_{order}`, Tags.PathNode, pathNodes, CFrame.new(position), Vector3.new(1, 1, 1))
		node:SetAttribute(Attributes.LaneId, LANE_ID)
		node:SetAttribute(Attributes.NodeOrder, order)
	end

	newMarkerPart("DefenderBase", Tags.DefenderBase, markers, CFrame.new(Positions.DefenderBase), Vector3.new(3, 3, 3))

	local placementZone =
		newMarkerPart("PlacementZone_land", Tags.PlacementZone, placementZones, PLACEMENT_CFRAME, PLACEMENT_SIZE)
	placementZone:SetAttribute(Attributes.ZoneId, "land")
	local noPlacementZone = newMarkerPart(
		"NoPlacementZone_lane",
		Tags.NoPlacementZone,
		noPlacementZones,
		NO_PLACEMENT_CFRAME,
		NO_PLACEMENT_SIZE
	)
	noPlacementZone:SetAttribute(Attributes.ZoneId, "lane")
	newMarkerPart("MapBounds", Tags.MapBounds, markers, BOUNDS_CFRAME, BOUNDS_SIZE)

	local cameraAnchor = newMarkerPart(
		"CameraAnchor_overview",
		Tags.CameraAnchor,
		cameraAnchors,
		CFrame.new(Positions.CameraAnchor),
		Vector3.new(1, 1, 1)
	)
	cameraAnchor:SetAttribute(Attributes.AnchorId, "overview")

	local playerSpawn = Instance.new("SpawnLocation")
	playerSpawn.Name = "PlayerSpawn_primary"
	configurePart(
		playerSpawn,
		CFrame.new(Positions.PlayerSpawn),
		Vector3.new(4, 1, 4),
		PLAYER_SPAWN_COLOR,
		0.25,
		true,
		true,
		true
	)
	playerSpawn.Enabled = true
	playerSpawn.Neutral = true
	playerSpawn:AddTag(Tags.PlayerSpawn)
	playerSpawn:SetAttribute(Attributes.SpawnId, "primary")
	playerSpawn.Parent = playerSpawns

	return catalog, map
end

local function assertContract(MapContract: any)
	requireCondition(MapContract.CONTRACT_VERSION == 1, "CONTRACT_VERSION_MISMATCH")
	requireCondition(MapContract.TRUSTED_CATALOG_NAME == CATALOG_NAME, "CATALOG_NAME_MISMATCH")
	requireCondition(MapContract.RUNTIME_ROOT_NAME == RUNTIME_NAME, "RUNTIME_NAME_MISMATCH")
	for name, value in Tags do
		requireCondition(MapContract.Tags[name] == value, "TAG_CONTRACT_MISMATCH")
	end
	for name, value in Attributes do
		requireCondition(MapContract.Attributes[name] == value, "ATTRIBUTE_CONTRACT_MISMATCH")
	end
end

local function requireValidMap(MapValidator: any, map: Model): any
	local called, result = pcall(MapValidator.validate, map, MAP_ID)
	requireCondition(called and result.ok, "MAP_VALIDATION_FAILED")
	return result.value
end

local function requireRuntimeRegression(MapLoader: any, MapValidator: any, logger: any, map: Model): (number, number)
	loader = MapLoader.new(logger)
	local loadResult = loader:load(MAP_ID)
	requireCondition(loadResult.ok and loader:getState() == "Loaded", "INITIAL_LOAD_FAILED")
	local firstRoot = directNamedChildren(Workspace, RUNTIME_NAME)
	requireCondition(#firstRoot == 1 and firstRoot[1]:IsA("Model"), "INITIAL_RUNTIME_ROOT_INVALID")

	local snapshot = loadResult.value
	requireCondition(snapshot.mapId == MAP_ID and #snapshot.lanes == 1, "INITIAL_SNAPSHOT_INVALID")
	local laneResult = loader:getLane(LANE_ID)
	requireCondition(laneResult.ok, "INITIAL_LANE_QUERY_FAILED")
	local lane = laneResult.value
	requireCondition(lane.id == LANE_ID and #lane.points == 5, "INITIAL_LANE_SHAPE_INVALID")
	requireCondition(lane.points[1].position == Positions.EnemySpawn, "INITIAL_SPAWN_QUERY_INVALID")
	requireCondition(lane.points[2].position == Positions.Node1, "INITIAL_NODE1_QUERY_INVALID")
	requireCondition(lane.points[3].position == Positions.Node2, "INITIAL_NODE2_QUERY_INVALID")
	requireCondition(lane.points[4].position == Positions.Node3, "INITIAL_NODE3_QUERY_INVALID")
	requireCondition(lane.points[5].position == Positions.DefenderBase, "INITIAL_BASE_QUERY_INVALID")
	for index = 2, #lane.points do
		requireCondition(lane.points[index].distance > lane.points[index - 1].distance, "LANE_DISTANCE_INVALID")
	end
	local firstDirection = (lane.points[2].position - lane.points[1].position).Unit
	local secondDirection = (lane.points[3].position - lane.points[2].position).Unit
	requireCondition(firstDirection:Cross(secondDirection).Magnitude >= math.sin(math.rad(5)), "LANE_BEND_MISSING")
	local snapshotResult = loader:getSnapshot()
	requireCondition(snapshotResult.ok and snapshotResult.value == snapshot, "SNAPSHOT_QUERY_INVALID")

	local unloadResult = loader:unload()
	requireCondition(unloadResult.ok and unloadResult.value and loader:getState() == "Idle", "UNLOAD_FAILED")
	requireCondition(#directNamedChildren(Workspace, RUNTIME_NAME) == 0, "UNLOAD_RUNTIME_RETAINED")
	requireValidMap(MapValidator, map)

	local reloadResult = loader:load(MAP_ID)
	requireCondition(reloadResult.ok and loader:getState() == "Loaded", "RELOAD_FAILED")
	local secondRoot = directNamedChildren(Workspace, RUNTIME_NAME)
	requireCondition(#secondRoot == 1 and secondRoot[1] ~= firstRoot[1], "RELOAD_ROOT_NOT_FRESH")
	local reloadedLane = loader:getLane(LANE_ID)
	requireCondition(reloadedLane.ok and reloadedLane.value.totalDistance == lane.totalDistance, "RELOAD_QUERY_INVALID")

	local cleanupResult = loader:cleanup()
	requireCondition(cleanupResult.ok and cleanupResult.value and loader:getState() == "Cleaned", "CLEANUP_FAILED")
	requireCondition(#directNamedChildren(Workspace, RUNTIME_NAME) == 0, "CLEANUP_RUNTIME_RETAINED")
	requireValidMap(MapValidator, map)
	return #snapshot.lanes, #lane.points
end

local function runAuthoringTransaction()
	requireCondition(EXECUTION_AUTHORIZATION == REQUIRED_EXECUTION_AUTHORIZATION, "PERSISTENCE_AUTHORIZATION_REQUIRED")
	requireCondition(RunService:IsStudio() and not RunService:IsRunning(), "EDIT_MODE_REQUIRED")
	requireCondition(game.PlaceId == PLACE_ID, "PLACE_ID_MISMATCH")
	requireCondition(game.CreatorType == Enum.CreatorType.Group and game.CreatorId == CREATOR_ID, "OWNER_MISMATCH")
	requireCondition(#directNamedChildren(ServerStorage, CATALOG_NAME) == 0, "CATALOG_ALREADY_EXISTS")
	requireCondition(#directNamedChildren(Workspace, RUNTIME_NAME) == 0, "RUNTIME_ALREADY_EXISTS")

	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local server = ServerScriptService:FindFirstChild("Server")
	local starterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	local client = if starterPlayerScripts == nil then nil else starterPlayerScripts:FindFirstChild("Client")
	requireCondition(shared ~= nil and shared:IsA("Folder"), "SHARED_SOURCE_MISSING")
	requireCondition(server ~= nil and server:IsA("Folder"), "SERVER_SOURCE_MISSING")
	requireCondition(client ~= nil and client:IsA("Folder"), "CLIENT_SOURCE_MISSING")
	requireCondition((server :: Folder):FindFirstChild("lobby") == nil, "LOBBY_SERVER_SOURCE_PRESENT")
	requireCondition((client :: Folder):FindFirstChild("lobby") == nil, "LOBBY_CLIENT_SOURCE_PRESENT")
	local match = (server :: Folder):FindFirstChild("match")
	requireCondition(match ~= nil and match:IsA("Folder"), "MATCH_SOURCE_MISSING")
	local maps = (match :: Folder):FindFirstChild("maps")
	requireCondition(maps ~= nil and maps:IsA("Folder"), "MAP_SOURCE_MISSING")

	failureCode = "SOURCE_LOAD_FAILED"
	local loaded, modules = pcall(function()
		local PlaceRoles = require((shared :: Folder).config.PlaceRoles)
		local EnvironmentContext = require((shared :: Folder).logging.EnvironmentContext)
		local Log = require((shared :: Folder).logging.Log)
		local MapContract = require((maps :: Folder).MapContract)
		local MapValidator = require((maps :: Folder).MapValidator)
		local MapLoader = require((maps :: Folder).MapLoader)
		return {
			PlaceRoles = PlaceRoles,
			EnvironmentContext = EnvironmentContext,
			Log = Log,
			MapContract = MapContract,
			MapValidator = MapValidator,
			MapLoader = MapLoader,
		}
	end)
	requireCondition(loaded, "SOURCE_LOAD_FAILED")
	local Modules = modules :: any
	local roleResult = Modules.PlaceRoles.resolve(
		ReplicatedStorage:GetAttribute(Modules.PlaceRoles.ATTRIBUTE_NAME),
		game.PlaceId,
		true
	)
	requireCondition(roleResult.ok and roleResult.role == "Match", "MATCH_ROLE_MISMATCH")
	assertContract(Modules.MapContract)

	failureCode = "BEFORE_INVENTORY_FAILED"
	beforeInventory = persistentInventory()

	local catalog, map = buildDetachedCandidate()
	candidateCatalog = catalog
	requireCondition(catalog.Parent == nil and map.Parent == catalog, "DETACHED_BUILD_FAILED")
	local validated = requireValidMap(Modules.MapValidator, map)
	requireCondition(validated.mapId == MAP_ID and #validated.lanes == 1, "DETACHED_SNAPSHOT_INVALID")

	local proposed = inventorySubtrees({ { instance = catalog, path = CATALOG_PATH } })
	local expected = expectedRecords()
	requireCondition(arraysEqual(proposed, expected), "PROPOSED_MANIFEST_MISMATCH")
	print(
		`[ATD_PHASE07_AUTHORING][PREVIEW][placeId={PLACE_ID}][creatorId={CREATOR_ID}][beforeRecords={#(beforeInventory :: { string })}][expectedDeltaRecords={#expected}][laneCount={#validated.lanes}]`
	)

	-- The complete detached catalog receives its only DataModel parent here.
	catalog.Parent = ServerStorage
	local afterPublish = persistentInventory()
	local added, removed = inventoryDelta(afterPublish, beforeInventory :: { string })
	requireCondition(#removed == 0, "UNRELATED_INVENTORY_CHANGED")
	requireCondition(arraysEqual(added, expected), "ACTUAL_DELTA_MISMATCH")
	requireCondition(arraysEqual(proposed, added), "PROPOSED_ACTUAL_DELTA_MISMATCH")
	print(
		`[ATD_PHASE07_AUTHORING][DELTA][added={#added}][removed={#removed}][unrelatedChanged=0][persistentRecords={#afterPublish}]`
	)

	requireValidMap(Modules.MapValidator, map)
	local logger = Modules.Log.new(Modules.EnvironmentContext.new("server", "Match", PLACE_ID, true))
	local laneCount, routePointCount = requireRuntimeRegression(Modules.MapLoader, Modules.MapValidator, logger, map)
	local afterRegression = persistentInventory()
	requireCondition(arraysEqual(afterRegression, afterPublish), "REGRESSION_INVENTORY_CHANGED")
	requireCondition(#directNamedChildren(ServerStorage, CATALOG_NAME) == 1, "FINAL_CATALOG_INVALID")
	requireCondition(#catalog:GetChildren() == 1 and catalog:GetChildren()[1] == map, "FINAL_TEMPLATE_INVALID")
	requireCondition(#directNamedChildren(Workspace, RUNTIME_NAME) == 0, "FINAL_RUNTIME_RETAINED")
	print(
		`[ATD_PHASE07_AUTHORING][PASS][catalogCount=1][templateCount=1][runtimeCount=0][laneCount={laneCount}][routePointCount={routePointCount}][deltaRecords={#expected}]`
	)
end

local succeeded = pcall(runAuthoringTransaction)
if not succeeded then
	if loader ~= nil then
		pcall(function()
			loader:cleanup()
		end)
	end
	local catalog = candidateCatalog
	if catalog ~= nil then
		pcall(function()
			catalog:Destroy()
		end)
	end

	local runtimeCount = #directNamedChildren(Workspace, RUNTIME_NAME)
	local catalogRemoved = catalog == nil or #directNamedChildren(ServerStorage, CATALOG_NAME) == 0
	local inventoryRestored = false
	if beforeInventory ~= nil and runtimeCount == 0 and catalogRemoved then
		local inventoried, current = pcall(persistentInventory)
		inventoryRestored = inventoried and arraysEqual(current :: { string }, beforeInventory :: { string })
	end
	print(
		`[ATD_PHASE07_AUTHORING][FAIL][code={failureCode}][catalogRemoved={tostring(catalogRemoved)}][runtimeCount={runtimeCount}][inventoryRestored={tostring(
			inventoryRestored
		)}]`
	)
end
