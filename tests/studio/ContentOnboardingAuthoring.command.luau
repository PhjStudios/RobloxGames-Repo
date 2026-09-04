--!strict

-- EDIT MODE ONLY. This test-only authoring command creates the additive,
-- primitive-only production content locked for the Content and Onboarding
-- outcome. The tracked copy is default-deny. An operator may arm only an
-- in-memory copy after verifying the exact private staging identity and the
-- authorized roots. Team Create parenting can persist immediately; this command
-- never saves, publishes, changes settings, or creates scripts in the place.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local STAGING_GAME_ID = 10764687717
local STAGING_MATCH_PLACE_ID = 104415140644510
local OWNER_GROUP_ID = 35420107
local REQUIRED_ROLE = "Match"
local MAP_ID = "map:backyard-garden-v1"
local MAP_NAME = "Map_backyard-garden-v1"
local CONTENT_CONTRACT = "playable-local-match-v1"
local CONTENT_VERSION = 1
local AUTHORIZATION = "BLOCKED_NO_PERSISTENCE_AUTHORIZATION"
local REQUIRED_AUTHORIZATION = "CONTENT_ONBOARDING_PRIVATE_STAGING_AUTHORIZED"

local function fail(code: string): never
	error(`[ATD_CONTENT_AUTHORING][code={code}]`, 0)
end

local function requireCondition(condition: boolean, code: string)
	if not condition then
		fail(code)
	end
end

requireCondition(AUTHORIZATION == REQUIRED_AUTHORIZATION, "NOT_AUTHORIZED")
requireCondition(not RunService:IsRunning(), "EDIT_MODE_REQUIRED")
requireCondition(game.GameId == STAGING_GAME_ID, "GAME_ID_MISMATCH")
requireCondition(game.PlaceId == STAGING_MATCH_PLACE_ID, "PLACE_ID_MISMATCH")
requireCondition(game.CreatorType == Enum.CreatorType.Group, "OWNER_TYPE_MISMATCH")
requireCondition(game.CreatorId == OWNER_GROUP_ID, "OWNER_ID_MISMATCH")
requireCondition(ReplicatedStorage:GetAttribute("ATDPlaceRole") == REQUIRED_ROLE, "ROLE_MISMATCH")
requireCondition(Workspace:FindFirstChild("ATDRuntimeMap") == nil, "RUNTIME_MAP_PRESENT")

local mapCatalog = ServerStorage:FindFirstChild("ATDMapTemplates")
local playableCatalog = ReplicatedStorage:FindFirstChild("ATDPlayableTemplates")
requireCondition(mapCatalog ~= nil and mapCatalog:IsA("Folder"), "MAP_CATALOG_MISSING")
requireCondition(playableCatalog ~= nil and playableCatalog:IsA("Folder"), "PLAYABLE_CATALOG_MISSING")
requireCondition(mapCatalog:FindFirstChild(MAP_NAME) == nil, "MAP_ALREADY_EXISTS")
requireCondition(playableCatalog:FindFirstChild("tower.bombardier-ant-model") == nil, "TOWER_ALREADY_EXISTS")
requireCondition(playableCatalog:FindFirstChild("enemy.broodling-ant-model") == nil, "SWARM_ALREADY_EXISTS")
requireCondition(playableCatalog:FindFirstChild("enemy.royal-guard-ant-model") == nil, "ELITE_ALREADY_EXISTS")
requireCondition(playableCatalog:GetAttribute("ATDContentContract") == CONTENT_CONTRACT, "CONTENT_CONTRACT_MISMATCH")
requireCondition(playableCatalog:GetAttribute("ContentVersion") == CONTENT_VERSION, "CONTENT_VERSION_MISMATCH")

local legacyMap = mapCatalog:FindFirstChild("Map_phase07-graybox")
requireCondition(legacyMap ~= nil and legacyMap:IsA("Model"), "LEGACY_MAP_MISSING")
requireCondition(legacyMap:GetAttribute("ATD_MapId") == "map:phase07-graybox", "LEGACY_MAP_CHANGED")

local legacyTemplates = table.freeze({
	["tower.dart-ant-model"] = true,
	["tower.rapid-ant-model"] = true,
	["tower.guard-ant-model"] = true,
	["enemy.worker-ant-model"] = true,
	["enemy.scout-ant-model"] = true,
	["enemy.soldier-ant-model"] = true,
	["enemy.queen-ant-model"] = true,
})
local legacyTemplateCount = 0
for _, child in playableCatalog:GetChildren() do
	requireCondition(legacyTemplates[child.Name] == true, "UNEXPECTED_PLAYABLE_TEMPLATE")
	requireCondition(child:IsA("Model"), "PLAYABLE_TEMPLATE_CLASS_MISMATCH")
	legacyTemplateCount += 1
end
requireCondition(legacyTemplateCount == 7, "LEGACY_PLAYABLE_INVENTORY_MISMATCH")

local before = table.freeze({
	mapTemplates = #mapCatalog:GetChildren(),
	mapDescendants = #mapCatalog:GetDescendants(),
	playableTemplates = #playableCatalog:GetChildren(),
	playableDescendants = #playableCatalog:GetDescendants(),
})

local function folder(name: string, parent: Instance): Folder
	local value = Instance.new("Folder")
	value.Name = name
	value.Parent = parent
	return value
end

local function part(
	name: string,
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean,
	canQuery: boolean,
	shape: Enum.PartType?
): Part
	local value = Instance.new("Part")
	value.Name = name
	value.Size = size
	value.CFrame = cframe
	value.Color = color
	value.Material = material
	value.Shape = shape or Enum.PartType.Block
	value.Anchored = true
	value.CanCollide = canCollide
	value.CanQuery = canQuery
	value.CanTouch = false
	value.CastShadow = canCollide
	value.TopSurface = Enum.SurfaceType.Smooth
	value.BottomSurface = Enum.SurfaceType.Smooth
	value.Parent = parent
	return value
end

local function marker(name: string, tag: string, parent: Instance, cframe: CFrame, size: Vector3): Part
	local value =
		part(name, parent, size, cframe, Color3.fromRGB(255, 196, 64), Enum.Material.SmoothPlastic, false, false)
	value.Transparency = 1
	value.CastShadow = false
	value:AddTag(tag)
	return value
end

local function roadFrame(startPosition: Vector3, endPosition: Vector3, y: number): (CFrame, number)
	local start = Vector3.new(startPosition.X, y, startPosition.Z)
	local finish = Vector3.new(endPosition.X, y, endPosition.Z)
	return CFrame.lookAt((start + finish) * 0.5, finish), (finish - start).Magnitude
end

local GRASS = Color3.fromRGB(91, 148, 75)
local SOIL = Color3.fromRGB(112, 76, 48)
local SOIL_DARK = Color3.fromRGB(69, 45, 32)
local STONE = Color3.fromRGB(190, 170, 133)
local STONE_DARK = Color3.fromRGB(118, 108, 91)
local WOOD = Color3.fromRGB(132, 83, 45)
local WOOD_LIGHT = Color3.fromRGB(184, 128, 70)
local LEAF = Color3.fromRGB(52, 133, 67)
local LEAF_LIGHT = Color3.fromRGB(92, 180, 82)
local FLOWER = Color3.fromRGB(255, 115, 151)
local FLOWER_ALT = Color3.fromRGB(255, 210, 74)
local GOAL = Color3.fromRGB(62, 171, 181)

local enemySpawn = Vector3.new(-70, 3, -40)
local pathNodes = table.freeze({
	Vector3.new(-42, 3, -40),
	Vector3.new(-28, 3, -18),
	Vector3.new(8, 3, -18),
	Vector3.new(24, 3, 10),
	Vector3.new(48, 3, 10),
})
local defenderBase = Vector3.new(70, 3, 10)
local route = { enemySpawn }
for _, point in pathNodes do
	table.insert(route, point)
end
table.insert(route, defenderBase)

-- Placement is deliberately granted through small, readable build pockets
-- rather than the whole lawn. Keeping the lane and scenery outside placement
-- authority makes the visible pads an honest preview of where a tower fits.
local placementPockets = table.freeze({
	table.freeze({ id = "west-overlook", center = Vector3.new(-45, 0, -54), size = Vector3.new(34, 2, 12) }),
	table.freeze({ id = "middle-bend", center = Vector3.new(-12, 0, -5), size = Vector3.new(36, 2, 12) }),
	table.freeze({ id = "upper-choke", center = Vector3.new(30, 0, 23), size = Vector3.new(38, 2, 12) }),
	table.freeze({ id = "east-choke", center = Vector3.new(51, 0, -5), size = Vector3.new(26, 2, 10) }),
})
local obstruction = table.freeze({
	id = "west-rock",
	center = Vector3.new(-45, 0, -54),
	size = Vector3.new(7, 2, 7),
})

local detachedCatalog = Instance.new("Folder")
detachedCatalog.Name = "ATDMapTemplates"
local map = Instance.new("Model")
map.Name = MAP_NAME
map:SetAttribute("ATD_MapId", MAP_ID)
map:SetAttribute("ATD_MapContractVersion", 1)
map:AddTag("ATD_MapRoot_v1")
map.Parent = detachedCatalog

local geometry = folder("Geometry", map)
part("GardenGround", geometry, Vector3.new(160, 2, 130), CFrame.new(0, 0, 0), GRASS, Enum.Material.Grass, true, true)

local buildPads = folder("BuildPads", geometry)
for _, pocket in placementPockets do
	local border = part(
		`BuildPadBorder_{pocket.id}`,
		buildPads,
		Vector3.new(pocket.size.X, 0.12, pocket.size.Z),
		CFrame.new(pocket.center.X, 1.06, pocket.center.Z),
		STONE_DARK,
		Enum.Material.Slate,
		false,
		false
	)
	border.CastShadow = false
	local inset = part(
		`BuildPadInset_{pocket.id}`,
		buildPads,
		Vector3.new(pocket.size.X - 1, 0.12, pocket.size.Z - 1),
		CFrame.new(pocket.center.X, 1.13, pocket.center.Z),
		Color3.fromRGB(125, 177, 103),
		Enum.Material.SmoothPlastic,
		false,
		false
	)
	inset.CastShadow = false
	inset.Transparency = 0.15
end

local placementObstructions = folder("PlacementObstructions", geometry)
local westRock = part(
	"WestPocketRock",
	placementObstructions,
	Vector3.new(5, 3.5, 5),
	CFrame.new(obstruction.center.X, 2.75, obstruction.center.Z),
	STONE_DARK,
	Enum.Material.Rock,
	false,
	false,
	Enum.PartType.Ball
)
westRock.CastShadow = true

local pathGeometry = folder("StoneLane", geometry)
for index = 1, #route - 1 do
	local segmentCFrame, length = roadFrame(route[index], route[index + 1], 1.42)
	part(
		string.format("Lane_%02d", index),
		pathGeometry,
		Vector3.new(11, 0.8, length),
		segmentCFrame,
		SOIL,
		Enum.Material.Ground,
		true,
		true
	)
	local stoneCount = math.max(2, math.floor(length / 6))
	for stoneIndex = 0, stoneCount do
		local alpha = stoneIndex / stoneCount
		local center = route[index]:Lerp(route[index + 1], alpha)
		local right = segmentCFrame.RightVector
		for _, side in { -1, 1 } do
			part(
				string.format("Edge_%02d_%02d_%s", index, stoneIndex, if side < 0 then "L" else "R"),
				pathGeometry,
				Vector3.new(1.8, 0.8, 3.4),
				CFrame.new(Vector3.new(center.X, 1.9, center.Z) + right * (side * 6.2)) * segmentCFrame.Rotation,
				if stoneIndex % 2 == 0 then STONE else STONE_DARK,
				Enum.Material.Slate,
				false,
				false
			)
		end
	end
end

local borders = folder("GardenBorder", geometry)
part(
	"NorthMulch",
	borders,
	Vector3.new(160, 1.2, 5),
	CFrame.new(0, 1.1, -62.5),
	SOIL_DARK,
	Enum.Material.Ground,
	true,
	true
)
part(
	"SouthMulch",
	borders,
	Vector3.new(160, 1.2, 5),
	CFrame.new(0, 1.1, 62.5),
	SOIL_DARK,
	Enum.Material.Ground,
	true,
	true
)
part(
	"WestMulch",
	borders,
	Vector3.new(5, 1.2, 120),
	CFrame.new(-77.5, 1.1, 0),
	SOIL_DARK,
	Enum.Material.Ground,
	true,
	true
)
part(
	"EastMulch",
	borders,
	Vector3.new(5, 1.2, 120),
	CFrame.new(77.5, 1.1, 0),
	SOIL_DARK,
	Enum.Material.Ground,
	true,
	true
)

for postIndex = -7, 7 do
	local x = postIndex * 10
	part(
		string.format("FencePost_%02d", postIndex + 8),
		borders,
		Vector3.new(1.2, 8, 1.2),
		CFrame.new(x, 4.5, 61),
		WOOD,
		Enum.Material.Wood,
		false,
		false
	)
end
part(
	"FenceRailLow",
	borders,
	Vector3.new(148, 1, 1),
	CFrame.new(0, 3, 61),
	WOOD_LIGHT,
	Enum.Material.WoodPlanks,
	false,
	false
)
part(
	"FenceRailHigh",
	borders,
	Vector3.new(148, 1, 1),
	CFrame.new(0, 6, 61),
	WOOD_LIGHT,
	Enum.Material.WoodPlanks,
	false,
	false
)

local beds = folder("RaisedBeds", geometry)
local bedCenters = table.freeze({
	Vector3.new(-50, 1.7, 29),
	Vector3.new(-12, 1.7, 43),
	Vector3.new(27, 1.7, 38),
})
for bedIndex, center in bedCenters do
	local bed = folder(string.format("Bed_%02d", bedIndex), beds)
	part("Soil", bed, Vector3.new(24, 2.2, 12), CFrame.new(center), SOIL, Enum.Material.Ground, false, false)
	part(
		"North",
		bed,
		Vector3.new(26, 2.8, 1.3),
		CFrame.new(center + Vector3.new(0, 0.3, -6.5)),
		WOOD,
		Enum.Material.WoodPlanks,
		false,
		false
	)
	part(
		"South",
		bed,
		Vector3.new(26, 2.8, 1.3),
		CFrame.new(center + Vector3.new(0, 0.3, 6.5)),
		WOOD,
		Enum.Material.WoodPlanks,
		false,
		false
	)
	part(
		"West",
		bed,
		Vector3.new(1.3, 2.8, 12),
		CFrame.new(center + Vector3.new(-12.5, 0.3, 0)),
		WOOD,
		Enum.Material.WoodPlanks,
		false,
		false
	)
	part(
		"East",
		bed,
		Vector3.new(1.3, 2.8, 12),
		CFrame.new(center + Vector3.new(12.5, 0.3, 0)),
		WOOD,
		Enum.Material.WoodPlanks,
		false,
		false
	)
	for plantIndex = -2, 2 do
		local plantPosition = center + Vector3.new(plantIndex * 4, 2.2, if plantIndex % 2 == 0 then -1.8 else 1.8)
		part(
			`Stem_{plantIndex + 3}`,
			bed,
			Vector3.new(0.5, 4, 0.5),
			CFrame.new(plantPosition),
			LEAF,
			Enum.Material.SmoothPlastic,
			false,
			false
		)
		part(
			`Leaves_{plantIndex + 3}`,
			bed,
			Vector3.new(3.3, 1.1, 2.2),
			CFrame.new(plantPosition + Vector3.new(0, 2, 0)),
			LEAF_LIGHT,
			Enum.Material.SmoothPlastic,
			false,
			false,
			Enum.PartType.Ball
		)
	end
end

local landmarks = folder("Landmarks", geometry)
local flowerPositions = table.freeze({
	Vector3.new(-67, 2, 7),
	Vector3.new(-55, 2, 12),
	Vector3.new(-39, 2, 10),
	Vector3.new(4, 2, 15),
	Vector3.new(42, 2, -44),
	Vector3.new(57, 2, -34),
})
for index, position in flowerPositions do
	part(
		string.format("FlowerStem_%02d", index),
		landmarks,
		Vector3.new(0.7, 5, 0.7),
		CFrame.new(position),
		LEAF,
		Enum.Material.SmoothPlastic,
		false,
		false
	)
	part(
		string.format("FlowerHead_%02d", index),
		landmarks,
		Vector3.new(3.8, 1.4, 3.8),
		CFrame.new(position + Vector3.new(0, 3, 0)),
		if index % 2 == 0 then FLOWER else FLOWER_ALT,
		Enum.Material.SmoothPlastic,
		false,
		false,
		Enum.PartType.Ball
	)
end

local mushroomPositions = table.freeze({
	Vector3.new(-67, 2, 50),
	Vector3.new(62, 2, -48),
	Vector3.new(72, 2, -32),
})
for index, position in mushroomPositions do
	part(
		`MushroomStem_{index}`,
		landmarks,
		Vector3.new(1.5, 4, 1.5),
		CFrame.new(position),
		Color3.fromRGB(232, 221, 190),
		Enum.Material.SmoothPlastic,
		false,
		false
	)
	part(
		`MushroomCap_{index}`,
		landmarks,
		Vector3.new(5.5, 2.1, 5.5),
		CFrame.new(position + Vector3.new(0, 2.6, 0)),
		Color3.fromRGB(210, 75, 67),
		Enum.Material.SmoothPlastic,
		false,
		false,
		Enum.PartType.Ball
	)
end

local nest = folder("EnemyNest", geometry)
for index, offset in
	{
		Vector3.new(-4, 0, 0),
		Vector3.new(0, 1, -3),
		Vector3.new(4, 0, 1),
		Vector3.new(1, 0, 4),
	}
do
	part(
		`Mound_{index}`,
		nest,
		Vector3.new(10, 6, 9),
		CFrame.new(enemySpawn + offset - Vector3.new(0, 0.5, 0)),
		SOIL,
		Enum.Material.Ground,
		false,
		false,
		Enum.PartType.Ball
	)
end
part(
	"Entrance",
	nest,
	Vector3.new(7, 5, 2.2),
	CFrame.new(enemySpawn + Vector3.new(0, 1, -5)),
	Color3.fromRGB(31, 24, 20),
	Enum.Material.Slate,
	false,
	false,
	Enum.PartType.Ball
)
part(
	"NestBeacon",
	nest,
	Vector3.new(3, 9, 3),
	CFrame.new(enemySpawn + Vector3.new(0, 7, 2)),
	Color3.fromRGB(235, 112, 55),
	Enum.Material.Neon,
	false,
	false
)

local seedStore = folder("DefenderSeedStore", geometry)
part(
	"Foundation",
	seedStore,
	Vector3.new(18, 2, 18),
	CFrame.new(defenderBase + Vector3.new(0, -1, 0)),
	STONE_DARK,
	Enum.Material.Cobblestone,
	false,
	false
)
part(
	"Shop",
	seedStore,
	Vector3.new(14, 11, 12),
	CFrame.new(defenderBase + Vector3.new(0, 5, 0)),
	GOAL,
	Enum.Material.WoodPlanks,
	false,
	false
)
part(
	"Roof",
	seedStore,
	Vector3.new(17, 3, 15),
	CFrame.new(defenderBase + Vector3.new(0, 11.5, 0)) * CFrame.Angles(0, 0, math.rad(8)),
	Color3.fromRGB(210, 78, 62),
	Enum.Material.Brick,
	false,
	false
)
part(
	"Door",
	seedStore,
	Vector3.new(4, 7, 0.8),
	CFrame.new(defenderBase + Vector3.new(0, 3.5, -6.4)),
	WOOD,
	Enum.Material.WoodPlanks,
	false,
	false
)
part(
	"GoalBeacon",
	seedStore,
	Vector3.new(2.5, 8, 2.5),
	CFrame.new(defenderBase + Vector3.new(0, 17, 0)),
	Color3.fromRGB(83, 229, 231),
	Enum.Material.Neon,
	false,
	false
)

local markers = folder("Markers", map)
local enemySpawns = folder("EnemySpawns", markers)
local spawnMarker =
	marker("EnemySpawn_main", "ATD_EnemySpawn_v1", enemySpawns, CFrame.new(enemySpawn), Vector3.new(2, 2, 2))
spawnMarker:SetAttribute("ATD_LaneId", "main")

local pathNodeFolder = folder("PathNodes", markers)
for index, position in pathNodes do
	local node =
		marker(`PathNode_main_{index}`, "ATD_PathNode_v1", pathNodeFolder, CFrame.new(position), Vector3.new(1, 1, 1))
	node:SetAttribute("ATD_LaneId", "main")
	node:SetAttribute("ATD_NodeOrder", index)
end

marker("DefenderBase", "ATD_DefenderBase_v1", markers, CFrame.new(defenderBase), Vector3.new(3, 3, 3))
local placementZones = folder("PlacementZones", markers)
for _, pocket in placementPockets do
	local placement = marker(
		`PlacementZone_{pocket.id}`,
		"ATD_PlacementZone_v1",
		placementZones,
		CFrame.new(pocket.center),
		pocket.size
	)
	placement:SetAttribute("ATD_ZoneId", pocket.id)
	placement:SetAttribute("ATD_SurfaceCategory", "Land")
end
local exclusions = folder("NoPlacementZones", markers)
local rockExclusion = marker(
	`NoPlacementZone_{obstruction.id}`,
	"ATD_NoPlacementZone_v1",
	exclusions,
	CFrame.new(obstruction.center),
	obstruction.size
)
rockExclusion:SetAttribute("ATD_ZoneId", obstruction.id)
marker("MapBounds", "ATD_MapBounds_v1", markers, CFrame.new(0, 25, 0), Vector3.new(170, 90, 150))

local cameras = folder("CameraAnchors", markers)
local overview = marker(
	"CameraAnchor_overview",
	"ATD_CameraAnchor_v1",
	cameras,
	CFrame.lookAt(Vector3.new(0, 68, 66), Vector3.new(0, 0, -4)),
	Vector3.new(1, 1, 1)
)
overview:SetAttribute("ATD_AnchorId", "overview")
local playerSpawns = folder("PlayerSpawns", markers)
for index, position in
	{
		Vector3.new(42, 2, 39),
		Vector3.new(55, 2, 39),
		Vector3.new(42, 2, 52),
		Vector3.new(55, 2, 52),
	}
do
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = `PlayerSpawn_player-{index}`
	spawn.Size = Vector3.new(5, 1, 5)
	spawn.CFrame = CFrame.new(position)
	spawn.Color = Color3.fromRGB(86, 191, 213)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Transparency = 0.7
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.CanQuery = true
	spawn.CanTouch = false
	spawn.Neutral = true
	spawn:AddTag("ATD_PlayerSpawn_v1")
	spawn:SetAttribute("ATD_SpawnId", `player-{index}`)
	spawn.Parent = playerSpawns
end

local MapValidator = require(ServerScriptService.Server.match.maps.MapValidator)
local validatedMap = MapValidator.validate(map, MAP_ID)
requireCondition(validatedMap.ok, "MAP_VALIDATION_FAILED")

local stagedContent = Instance.new("Folder")
stagedContent.Name = "ATDContentAdditions"

local function modelPart(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	shape: Enum.PartType?,
	transparency: number?
): Part
	local value = part(name, model, size, cframe, color, Enum.Material.SmoothPlastic, false, false, shape)
	value.CastShadow = false
	value.Transparency = transparency or 0
	return value
end

local function beginModel(assetKey: string, contentKind: string, definitionId: string): Model
	local value = Instance.new("Model")
	value.Name = assetKey
	value:SetAttribute("ATDContentContract", CONTENT_CONTRACT)
	value:SetAttribute("AssetKey", assetKey)
	value:SetAttribute("ContentKind", contentKind)
	value:SetAttribute("DefinitionId", definitionId)
	value.Parent = stagedContent
	return value
end

local bombardier = beginModel("tower.bombardier-ant-model", "TowerModel", "tower:bombardier-ant")
local bombardierRoot = modelPart(
	bombardier,
	"Root",
	Vector3.new(3.4, 0.7, 3.4),
	CFrame.new(0, 0.35, 0),
	Color3.fromRGB(126, 91, 62),
	nil,
	0
)
modelPart(
	bombardier,
	"Body",
	Vector3.new(2.2, 1.8, 2.4),
	CFrame.new(0, 1.5, 0),
	Color3.fromRGB(184, 105, 57),
	Enum.PartType.Ball
)
modelPart(
	bombardier,
	"Head",
	Vector3.new(1.5, 1.25, 1.5),
	CFrame.new(0, 2.2, -1.35),
	Color3.fromRGB(225, 151, 63),
	Enum.PartType.Ball
)
modelPart(
	bombardier,
	"Mortar",
	Vector3.new(1.25, 1.25, 3.4),
	CFrame.new(0, 2.7, 0.2) * CFrame.Angles(math.rad(-32), 0, 0),
	Color3.fromRGB(76, 72, 74)
)
local muzzle = modelPart(
	bombardier,
	"Muzzle1",
	Vector3.new(0.45, 0.45, 0.45),
	CFrame.new(0, 3.65, -1.15),
	Color3.fromRGB(255, 221, 114),
	Enum.PartType.Ball,
	0.15
)
muzzle:SetAttribute("MuzzleIndex", 1)
bombardier.PrimaryPart = bombardierRoot
bombardier:PivotTo(CFrame.new())

local function antModel(assetKey: string, definitionId: string, role: string, color: Color3, scale: number): Model
	local model = beginModel(assetKey, "EnemyModel", definitionId)
	model:SetAttribute("Role", role)
	local thorax =
		modelPart(model, "Thorax", Vector3.new(1.2, 1, 1.45) * scale, CFrame.new(), color, Enum.PartType.Ball)
	modelPart(
		model,
		"Head",
		Vector3.new(0.9, 0.8, 0.9) * scale,
		CFrame.new(0, 0, -1.05 * scale),
		color,
		Enum.PartType.Ball
	)
	modelPart(
		model,
		"Abdomen",
		Vector3.new(1.35, 1.1, 1.65) * scale,
		CFrame.new(0, 0, 1.25 * scale),
		color,
		Enum.PartType.Ball
	)
	for side = -1, 1, 2 do
		for row = -1, 1 do
			modelPart(
				model,
				`Leg{side}_{row}`,
				Vector3.new(0.16, 0.16, 1.05) * scale,
				CFrame.new(0.58 * side * scale, -0.38 * scale, row * 0.55 * scale)
					* CFrame.Angles(0, 0, math.rad(55 * side)),
				color
			)
		end
	end
	model.PrimaryPart = thorax
	model:PivotTo(CFrame.new())
	return model
end

antModel("enemy.broodling-ant-model", "enemy:broodling-ant", "Swarm", Color3.fromRGB(171, 118, 76), 0.52)
local royalGuard =
	antModel("enemy.royal-guard-ant-model", "enemy:royal-guard-ant", "MiniBoss", Color3.fromRGB(72, 52, 83), 1.7)
modelPart(royalGuard, "Crown", Vector3.new(2.2, 0.55, 1.2), CFrame.new(0, 1.25, -1.7), Color3.fromRGB(239, 184, 61))

for _, candidate in stagedContent:GetChildren() do
	requireCondition(candidate:IsA("Model") and candidate.PrimaryPart ~= nil, "CONTENT_MODEL_INVALID")
	requireCondition(candidate:GetAttribute("ATDContentContract") == CONTENT_CONTRACT, "CONTENT_MODEL_CONTRACT_INVALID")
	local partCount = 0
	for _, descendant in candidate:GetDescendants() do
		requireCondition(not descendant:IsA("LuaSourceContainer"), "CONTENT_SCRIPT_REJECTED")
		if descendant:IsA("BasePart") then
			partCount += 1
			requireCondition(descendant.Anchored, "CONTENT_PART_UNANCHORED")
			requireCondition(
				not descendant.CanCollide and not descendant.CanTouch and not descendant.CanQuery,
				"CONTENT_PART_INTERACTIVE"
			)
		end
	end
	requireCondition(partCount > 0, "CONTENT_MODEL_EMPTY")
end
requireCondition(#stagedContent:GetChildren() == 3, "CONTENT_ADDITION_COUNT_MISMATCH")

local additions = stagedContent:GetChildren()
local committed = pcall(function()
	map.Parent = mapCatalog
	for _, addition in additions do
		addition.Parent = playableCatalog
	end
end)
if not committed then
	if map.Parent == mapCatalog then
		map:Destroy()
	end
	for _, addition in additions do
		if addition.Parent == playableCatalog then
			addition:Destroy()
		end
	end
	detachedCatalog:Destroy()
	stagedContent:Destroy()
	fail("COMMIT_FAILED")
end

detachedCatalog:Destroy()
stagedContent:Destroy()
local afterValidation = MapValidator.validate(map, MAP_ID)
requireCondition(afterValidation.ok, "COMMITTED_MAP_INVALID")
requireCondition(#mapCatalog:GetChildren() == before.mapTemplates + 1, "MAP_COUNT_POSTCONDITION")
requireCondition(#playableCatalog:GetChildren() == before.playableTemplates + 3, "CONTENT_COUNT_POSTCONDITION")

local after = table.freeze({
	mapTemplates = #mapCatalog:GetChildren(),
	mapDescendants = #mapCatalog:GetDescendants(),
	playableTemplates = #playableCatalog:GetChildren(),
	playableDescendants = #playableCatalog:GetDescendants(),
	productionMapDescendants = #map:GetDescendants(),
})
local report = {
	status = "AUTHORED",
	gameId = game.GameId,
	placeId = game.PlaceId,
	creatorId = game.CreatorId,
	role = ReplicatedStorage:GetAttribute("ATDPlaceRole"),
	mapId = MAP_ID,
	before = before,
	after = after,
	addedTemplates = {
		"tower.bombardier-ant-model",
		"enemy.broodling-ant-model",
		"enemy.royal-guard-ant-model",
	},
}
print(`[ATD_CONTENT_AUTHORING][status=AUTHORED][map={MAP_ID}][mapDescendants={after.productionMapDescendants}]`)
return HttpService:JSONEncode(report)
