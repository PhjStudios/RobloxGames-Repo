--!strict

-- Runtime-only Packet 07.4 harness. Paste into the Match Studio command bar
-- while a single-server Play session is running. This file is never mapped by
-- a production Rojo project and owns every Instance that it creates.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local MapLoader = require(ServerScriptService.Server.match.maps.MapLoader)
local MapValidator = require(ServerScriptService.Server.match.maps.MapValidator)

local EXPECTED_PLACE_ID = 136401514513678
local EXPECTED_CREATOR_ID = 35420107
local MAP_ID = "map:phase07-graybox"
local LANE_ID = "main"
local CATALOG_NAME = "ATDMapTemplates"
local RUNTIME_NAME = "ATDRuntimeMap"

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

local catalog: Folder? = nil
local loader: any = nil
local checks = 0

local function expect(condition: boolean, code: string)
	if not condition then
		error(`[ATD_PHASE07_STUDIO][FAIL][code={code}]`, 0)
	end
	checks += 1
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
	local value = Instance.new("Folder")
	value.Name = name
	value.Parent = parent
	return value
end

local function configurePart(part: BasePart, cframe: CFrame, size: Vector3, collide: boolean)
	part.CFrame = cframe
	part.Size = size
	part.Anchored = true
	part.CanCollide = collide
	part.CanTouch = collide
	part.CanQuery = collide
	if not collide then
		part.Transparency = 0.65
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
	local value = Instance.new(className) :: BasePart
	value.Name = name
	configurePart(value, cframe, size, className == "SpawnLocation")
	value:AddTag(tag)
	value.Parent = parent
	return value
end

local function createTemplate(): (Model, Part, Part)
	local root = Instance.new("Model")
	root.Name = "Map_phase07-graybox"
	root:AddTag(Tags.MapRoot)
	root:SetAttribute(Attributes.MapId, MAP_ID)
	root:SetAttribute(Attributes.MapContractVersion, 1)

	local geometry = newFolder("Geometry", root)
	local floor = Instance.new("Part")
	floor.Name = "GrayboxFloor"
	configurePart(floor, CFrame.new(0, -5, 0), Vector3.new(100, 2, 80), true)
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
		Tags.EnemySpawn,
		enemySpawns,
		CFrame.new(-40, 5, -20),
		Vector3.new(2, 2, 2)
	)
	enemySpawn:SetAttribute(Attributes.LaneId, LANE_ID)

	local node1 = newTaggedPart(
		"Part",
		"PathNode_main_1",
		Tags.PathNode,
		pathNodes,
		CFrame.new(-15, 5, -20),
		Vector3.new(1, 1, 1)
	) :: Part
	node1:SetAttribute(Attributes.LaneId, LANE_ID)
	node1:SetAttribute(Attributes.NodeOrder, 1)

	local node2 = newTaggedPart(
		"Part",
		"PathNode_main_2",
		Tags.PathNode,
		pathNodes,
		CFrame.new(0, 5, 0),
		Vector3.new(1, 1, 1)
	) :: Part
	node2:SetAttribute(Attributes.LaneId, LANE_ID)
	node2:SetAttribute(Attributes.NodeOrder, 2)

	newTaggedPart("Part", "DefenderBase", Tags.DefenderBase, markers, CFrame.new(30, 5, 0), Vector3.new(3, 3, 3))

	local placement = newTaggedPart(
		"Part",
		"PlacementZone_land",
		Tags.PlacementZone,
		placementZones,
		CFrame.new(0, -3, 0),
		Vector3.new(90, 2, 70)
	)
	placement:SetAttribute(Attributes.ZoneId, "land")

	local noPlacement = newTaggedPart(
		"Part",
		"NoPlacementZone_lane",
		Tags.NoPlacementZone,
		noPlacementZones,
		CFrame.new(-25, -3, 0),
		Vector3.new(10, 2, 10)
	)
	noPlacement:SetAttribute(Attributes.ZoneId, "lane")

	newTaggedPart("Part", "MapBounds", Tags.MapBounds, markers, CFrame.new(0, 0, 0), Vector3.new(120, 40, 100))

	local cameraAnchor = newTaggedPart(
		"Part",
		"CameraAnchor_overview",
		Tags.CameraAnchor,
		cameraAnchors,
		CFrame.new(0, 15, 35),
		Vector3.new(1, 1, 1)
	)
	cameraAnchor:SetAttribute(Attributes.AnchorId, "overview")

	local playerSpawn = newTaggedPart(
		"SpawnLocation",
		"PlayerSpawn_primary",
		Tags.PlayerSpawn,
		playerSpawns,
		CFrame.new(35, 5, 25),
		Vector3.new(4, 1, 4)
	) :: SpawnLocation
	playerSpawn.Enabled = true
	playerSpawn.Neutral = true
	playerSpawn:SetAttribute(Attributes.SpawnId, "primary")

	return root, node1, node2
end

local function inventory(root: Instance): string
	local records = {}
	local values = { root }
	for _, descendant in root:GetDescendants() do
		table.insert(values, descendant)
	end
	for _, value in values do
		local tags = value:GetTags()
		table.sort(tags)
		local attributes = value:GetAttributes()
		local attributeRecords = {}
		for name, attributeValue in attributes do
			table.insert(attributeRecords, `{name}={typeof(attributeValue)}:{tostring(attributeValue)}`)
		end
		table.sort(attributeRecords)
		local geometry = ""
		if value:IsA("BasePart") then
			geometry = `{tostring(value.CFrame)}|{tostring(value.Size)}`
		end
		table.insert(
			records,
			table.concat({
				value:GetFullName(),
				value.ClassName,
				table.concat(tags, ","),
				table.concat(attributeRecords, ","),
				geometry,
			}, "|")
		)
	end
	table.sort(records)
	return table.concat(records, "\n")
end

local function expectSuccess(result: any, code: string): any
	expect(type(result) == "table" and result.ok == true and table.isfrozen(result), code)
	return result.value
end

local function expectDeepFrozenDetached(value: unknown, seen: { [any]: boolean }?)
	expect(typeof(value) ~= "Instance", "QUERY_EXPOSED_INSTANCE")
	if type(value) ~= "table" then
		return
	end
	local visited = seen or {}
	if visited[value] then
		return
	end
	visited[value] = true
	expect(table.isfrozen(value :: any), "QUERY_NOT_FROZEN")
	for key, child in next, value :: any do
		expectDeepFrozenDetached(key, visited)
		expectDeepFrozenDetached(child, visited)
	end
end

local function runtimeRoot(): Model?
	local roots = directNamedChildren(Workspace, RUNTIME_NAME)
	if #roots ~= 1 or not roots[1]:IsA("Model") then
		return nil
	end
	return roots[1] :: Model
end

local function cleanupOwned()
	if loader ~= nil then
		pcall(function()
			loader:cleanup()
		end)
	end
	if catalog ~= nil then
		catalog:Destroy()
	end
end

local succeeded, failureMessage = xpcall(function()
	expect(RunService:IsStudio(), "NOT_STUDIO")
	expect(RunService:IsRunning(), "NOT_RUNNING")
	expect(RunService:IsServer(), "NOT_SERVER")
	expect(game.PlaceId == EXPECTED_PLACE_ID, "PLACE_ID_MISMATCH")
	expect(game.CreatorType == Enum.CreatorType.Group, "CREATOR_TYPE_MISMATCH")
	expect(game.CreatorId == EXPECTED_CREATOR_ID, "CREATOR_ID_MISMATCH")
	expect(ReplicatedStorage:GetAttribute("ATDPlaceRole") == "Match", "PLACE_ROLE_MISMATCH")
	expect(#directNamedChildren(ServerStorage, CATALOG_NAME) == 0, "CATALOG_PREEXISTED")
	expect(#directNamedChildren(Workspace, RUNTIME_NAME) == 0, "RUNTIME_PREEXISTED")

	catalog = Instance.new("Folder")
	catalog.Name = CATALOG_NAME
	local template, templateNode1, templateNode2 = createTemplate()
	template.Parent = catalog
	catalog.Parent = ServerStorage
	local templateBefore = inventory(template)

	local validationResult = MapValidator.validate(template, MAP_ID)
	local validated = expectSuccess(validationResult, "VALIDATION_FAILED")
	expect(validated.mapId == MAP_ID and #validated.lanes == 1, "VALIDATION_SNAPSHOT_MISMATCH")
	expect(inventory(template) == templateBefore, "VALIDATOR_MUTATED_TEMPLATE")

	local logger = Log.new(EnvironmentContext.new("server", "Match", game.PlaceId, true))
	loader = MapLoader.new(logger)
	local firstSnapshot = expectSuccess(loader:load(MAP_ID), "FIRST_LOAD_FAILED")
	expect(loader:getState() == "Loaded", "FIRST_LOAD_STATE")
	expectDeepFrozenDetached(firstSnapshot)
	local firstLane = expectSuccess(loader:getLane(LANE_ID), "FIRST_QUERY_FAILED")
	expect(#firstLane.points == 4 and firstLane.totalDistance == 80, "LANE_DISTANCE_MISMATCH")
	expect(firstLane.points[1].kind == "EnemySpawn", "LANE_START_MISMATCH")
	expect(firstLane.points[4].kind == "DefenderBase", "LANE_END_MISMATCH")
	local firstDirection = (firstLane.points[2].position - firstLane.points[1].position).Unit
	local secondDirection = (firstLane.points[3].position - firstLane.points[2].position).Unit
	expect(firstDirection:Cross(secondDirection).Magnitude >= math.sin(math.rad(5)), "LANE_NOT_BENT")

	templateNode2.CFrame = CFrame.new(5, 5, 0)
	local detachedTemplateLane = expectSuccess(loader:getLane(LANE_ID), "TEMPLATE_ISOLATION_QUERY_FAILED")
	expect(detachedTemplateLane.points[3].position == Vector3.new(0, 5, 0), "TEMPLATE_MUTATED_QUERY")
	templateNode2.CFrame = CFrame.new(0, 5, 0)

	local active = runtimeRoot()
	expect(active ~= nil, "RUNTIME_ROOT_MISSING")
	local runtimeNode = (active :: Model):FindFirstChild(templateNode1.Name, true)
	expect(runtimeNode ~= nil and runtimeNode:IsA("BasePart"), "RUNTIME_NODE_MISSING")
	local runtimePart = runtimeNode :: BasePart
	runtimePart.CFrame = CFrame.new(-10, 5, -20)
	local detachedRuntimeLane = expectSuccess(loader:getLane(LANE_ID), "RUNTIME_ISOLATION_QUERY_FAILED")
	expect(detachedRuntimeLane.points[2].position == Vector3.new(-15, 5, -20), "RUNTIME_MUTATED_QUERY")

	local firstUnload = expectSuccess(loader:unload(), "FIRST_UNLOAD_FAILED")
	expect(firstUnload == true and loader:getState() == "Idle", "FIRST_UNLOAD_STATE")
	expect(#directNamedChildren(Workspace, RUNTIME_NAME) == 0, "FIRST_UNLOAD_LEAK")
	local repeatedUnload = expectSuccess(loader:unload(), "REPEATED_UNLOAD_FAILED")
	expect(repeatedUnload == false, "REPEATED_UNLOAD_NOT_IDEMPOTENT")

	local secondSnapshot = expectSuccess(loader:load(MAP_ID), "RELOAD_FAILED")
	local secondLane = expectSuccess(loader:getLane(LANE_ID), "RELOAD_QUERY_FAILED")
	expect(secondSnapshot.mapId == MAP_ID and secondLane.totalDistance == 80, "RELOAD_DATA_MISMATCH")
	local cleanupResult = expectSuccess(loader:cleanup(), "CLEANUP_FAILED")
	expect(cleanupResult == true and loader:getState() == "Cleaned", "CLEANUP_STATE")
	expect(#directNamedChildren(Workspace, RUNTIME_NAME) == 0, "CLEANUP_RUNTIME_LEAK")
	local repeatedCleanup = expectSuccess(loader:cleanup(), "REPEATED_CLEANUP_FAILED")
	expect(repeatedCleanup == false, "REPEATED_CLEANUP_NOT_IDEMPOTENT")
	local postCleanupQuery = loader:getSnapshot()
	expect(postCleanupQuery.ok == false and postCleanupQuery.error.code == "INVALID_STATE", "POST_CLEANUP_QUERY_STATE")
	expect(inventory(template) == templateBefore, "LOADER_MUTATED_TEMPLATE")
end, debug.traceback)

cleanupOwned()

if not succeeded then
	warn(`[ATD_PHASE07_STUDIO][FAIL][context=server][detail={tostring(failureMessage)}]`)
	error("[ATD_PHASE07_STUDIO_ABORT]", 0)
end

expect(#directNamedChildren(ServerStorage, CATALOG_NAME) == 0, "CATALOG_LEAK")
expect(#directNamedChildren(Workspace, RUNTIME_NAME) == 0, "FINAL_RUNTIME_LEAK")
print(
	`[ATD_PHASE07_STUDIO][PASS][context=server][checks={checks}][mapId={MAP_ID}][laneCount=1][pointCount=4][distance=80][cleanupState=Cleaned]`
)
