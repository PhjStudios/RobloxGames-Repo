--!strict

-- EDIT MODE ONLY. This test-only repair command replaces the first garden
-- map's over-broad placement authority with four visible build pockets and a
-- single matching rock exclusion. The tracked copy is default-deny. An
-- operator may arm only an in-memory copy after re-verifying the exact private
-- staging identity. It never saves, publishes, or changes any Rojo source.

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
local REQUIRED_AUTHORIZATION = "CONTENT_ONBOARDING_PLACEMENT_REPAIR_AUTHORIZED"

local function fail(code: string): never
	error(`[ATD_PLACEMENT_REPAIR][code={code}]`, 0)
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
requireCondition(#mapCatalog:GetChildren() == 2, "MAP_CATALOG_INVENTORY_MISMATCH")
requireCondition(#playableCatalog:GetChildren() == 10, "PLAYABLE_CATALOG_INVENTORY_MISMATCH")
requireCondition(playableCatalog:GetAttribute("ATDContentContract") == CONTENT_CONTRACT, "CONTENT_CONTRACT_MISMATCH")
requireCondition(playableCatalog:GetAttribute("ContentVersion") == CONTENT_VERSION, "CONTENT_VERSION_MISMATCH")

local map = mapCatalog:FindFirstChild(MAP_NAME)
requireCondition(map ~= nil and map:IsA("Model"), "MAP_MISSING")
requireCondition(map:GetAttribute("ATD_MapId") == MAP_ID, "MAP_ID_MISMATCH")
requireCondition(map:GetAttribute("ATD_MapContractVersion") == 1, "MAP_CONTRACT_MISMATCH")

local geometry = map:FindFirstChild("Geometry")
local markers = map:FindFirstChild("Markers")
requireCondition(geometry ~= nil and geometry:IsA("Folder"), "GEOMETRY_MISSING")
requireCondition(markers ~= nil and markers:IsA("Folder"), "MARKERS_MISSING")
requireCondition(geometry:FindFirstChild("BuildPads") == nil, "BUILD_PADS_ALREADY_PRESENT")
requireCondition(geometry:FindFirstChild("PlacementObstructions") == nil, "OBSTRUCTION_ALREADY_PRESENT")

local oldPlacementZones = markers:FindFirstChild("PlacementZones")
local oldNoPlacementZones = markers:FindFirstChild("NoPlacementZones")
requireCondition(oldPlacementZones ~= nil and oldPlacementZones:IsA("Folder"), "PLACEMENT_ROOT_MISSING")
requireCondition(oldNoPlacementZones ~= nil and oldNoPlacementZones:IsA("Folder"), "EXCLUSION_ROOT_MISSING")
requireCondition(#oldPlacementZones:GetChildren() == 1, "PLACEMENT_SOURCE_INVENTORY_MISMATCH")
requireCondition(#oldNoPlacementZones:GetChildren() == 1, "EXCLUSION_SOURCE_INVENTORY_MISMATCH")

local oldLand = oldPlacementZones:FindFirstChild("PlacementZone_land")
local oldLane = oldNoPlacementZones:FindFirstChild("NoPlacementZone_lane")
requireCondition(oldLand ~= nil and oldLand:IsA("Part"), "LEGACY_LAND_MARKER_MISSING")
requireCondition(oldLane ~= nil and oldLane:IsA("Part"), "LEGACY_LANE_MARKER_MISSING")
requireCondition(oldLand:GetAttribute("ATD_ZoneId") == "land", "LEGACY_LAND_ID_MISMATCH")
requireCondition(oldLand:GetAttribute("ATD_SurfaceCategory") == "Land", "LEGACY_SURFACE_MISMATCH")
requireCondition(oldLand.CFrame == CFrame.new(0, 0, 0), "LEGACY_LAND_CFRAME_MISMATCH")
requireCondition(oldLand.Size == Vector3.new(160, 2, 130), "LEGACY_LAND_SIZE_MISMATCH")
requireCondition(oldLane:GetAttribute("ATD_ZoneId") == "lane", "LEGACY_LANE_ID_MISMATCH")
requireCondition(oldLane.CFrame == CFrame.new(0, 0, -14), "LEGACY_LANE_CFRAME_MISMATCH")
requireCondition(oldLane.Size == Vector3.new(150, 2, 64), "LEGACY_LANE_SIZE_MISMATCH")

local MapValidator = require(ServerScriptService.Server.match.maps.MapValidator)
local beforeValidation = MapValidator.validate(map, MAP_ID)
requireCondition(beforeValidation.ok, "SOURCE_MAP_INVALID")

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

local function folder(name: string, parent: Instance): Folder
	local value = Instance.new("Folder")
	value.Name = name
	value.Parent = parent
	return value
end

local function inertPart(
	name: string,
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
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
	value.CanCollide = false
	value.CanQuery = false
	value.CanTouch = false
	value.CastShadow = false
	value.TopSurface = Enum.SurfaceType.Smooth
	value.BottomSurface = Enum.SurfaceType.Smooth
	value.Parent = parent
	return value
end

local function marker(name: string, tag: string, parent: Instance, cframe: CFrame, size: Vector3): Part
	local value = inertPart(name, parent, size, cframe, Color3.fromRGB(255, 196, 64), Enum.Material.SmoothPlastic, nil)
	value.Transparency = 1
	value:AddTag(tag)
	return value
end

local staged = Instance.new("Folder")
staged.Name = "ATDPlacementRepairStaging"

local newPlacementZones = folder("PlacementZones", staged)
for _, pocket in placementPockets do
	local value = marker(
		`PlacementZone_{pocket.id}`,
		"ATD_PlacementZone_v1",
		newPlacementZones,
		CFrame.new(pocket.center),
		pocket.size
	)
	value:SetAttribute("ATD_ZoneId", pocket.id)
	value:SetAttribute("ATD_SurfaceCategory", "Land")
end

local newNoPlacementZones = folder("NoPlacementZones", staged)
local rockExclusion = marker(
	`NoPlacementZone_{obstruction.id}`,
	"ATD_NoPlacementZone_v1",
	newNoPlacementZones,
	CFrame.new(obstruction.center),
	obstruction.size
)
rockExclusion:SetAttribute("ATD_ZoneId", obstruction.id)

local newBuildPads = folder("BuildPads", staged)
for _, pocket in placementPockets do
	inertPart(
		`BuildPadBorder_{pocket.id}`,
		newBuildPads,
		Vector3.new(pocket.size.X, 0.12, pocket.size.Z),
		CFrame.new(pocket.center.X, 1.06, pocket.center.Z),
		Color3.fromRGB(118, 108, 91),
		Enum.Material.Slate,
		nil
	)
	local inset = inertPart(
		`BuildPadInset_{pocket.id}`,
		newBuildPads,
		Vector3.new(pocket.size.X - 1, 0.12, pocket.size.Z - 1),
		CFrame.new(pocket.center.X, 1.13, pocket.center.Z),
		Color3.fromRGB(125, 177, 103),
		Enum.Material.SmoothPlastic,
		nil
	)
	inset.Transparency = 0.15
end

local newObstructions = folder("PlacementObstructions", staged)
local westRock = inertPart(
	"WestPocketRock",
	newObstructions,
	Vector3.new(5, 3.5, 5),
	CFrame.new(obstruction.center.X, 2.75, obstruction.center.Z),
	Color3.fromRGB(118, 108, 91),
	Enum.Material.Rock,
	Enum.PartType.Ball
)
westRock.CastShadow = true

local candidateCatalog = Instance.new("Folder")
candidateCatalog.Name = "ATDMapTemplates"
local candidate = map:Clone()
candidate.Parent = candidateCatalog
local candidateMarkers = candidate:FindFirstChild("Markers") :: Folder
local candidateGeometry = candidate:FindFirstChild("Geometry") :: Folder
local candidatePlacementZones = candidateMarkers:FindFirstChild("PlacementZones") :: Instance
local candidateNoPlacementZones = candidateMarkers:FindFirstChild("NoPlacementZones") :: Instance
candidatePlacementZones:Destroy()
candidateNoPlacementZones:Destroy()
newPlacementZones:Clone().Parent = candidateMarkers
newNoPlacementZones:Clone().Parent = candidateMarkers
newBuildPads:Clone().Parent = candidateGeometry
newObstructions:Clone().Parent = candidateGeometry
local candidateValidation = MapValidator.validate(candidate, MAP_ID)
requireCondition(candidateValidation.ok, "REPAIRED_CANDIDATE_INVALID")

local beforeDescendants = #map:GetDescendants()
local commitOk = xpcall(function()
	oldPlacementZones.Parent = nil
	oldNoPlacementZones.Parent = nil
	newPlacementZones.Parent = markers
	newNoPlacementZones.Parent = markers
	newBuildPads.Parent = geometry
	newObstructions.Parent = geometry
	local committedValidation = MapValidator.validate(map, MAP_ID)
	requireCondition(committedValidation.ok, "COMMITTED_MAP_INVALID")
end, debug.traceback)

if not commitOk then
	local rollbackOk = pcall(function()
		newPlacementZones:Destroy()
		newNoPlacementZones:Destroy()
		newBuildPads:Destroy()
		newObstructions:Destroy()
		oldPlacementZones.Parent = markers
		oldNoPlacementZones.Parent = markers
	end)
	local rollbackValidation = MapValidator.validate(map, MAP_ID)
	candidateCatalog:Destroy()
	staged:Destroy()
	requireCondition(rollbackOk and rollbackValidation.ok, "ROLLBACK_FAILED")
	fail("COMMIT_FAILED_ROLLED_BACK")
end

oldPlacementZones:Destroy()
oldNoPlacementZones:Destroy()
candidateCatalog:Destroy()
staged:Destroy()

local afterValidation = MapValidator.validate(map, MAP_ID)
requireCondition(afterValidation.ok, "POSTCONDITION_MAP_INVALID")
requireCondition(#map:GetDescendants() == beforeDescendants + 14, "DESCENDANT_COUNT_POSTCONDITION")
requireCondition(
	#(markers:FindFirstChild("PlacementZones") :: Folder):GetChildren() == 4,
	"PLACEMENT_COUNT_POSTCONDITION"
)
requireCondition(
	#(markers:FindFirstChild("NoPlacementZones") :: Folder):GetChildren() == 1,
	"EXCLUSION_COUNT_POSTCONDITION"
)

local report = {
	status = "REPAIRED",
	gameId = game.GameId,
	placeId = game.PlaceId,
	creatorId = game.CreatorId,
	role = ReplicatedStorage:GetAttribute("ATDPlaceRole"),
	mapId = MAP_ID,
	beforeDescendants = beforeDescendants,
	afterDescendants = #map:GetDescendants(),
	placementZoneIds = {
		"west-overlook",
		"middle-bend",
		"upper-choke",
		"east-choke",
	},
	exclusionZoneId = obstruction.id,
}
print(`[ATD_PLACEMENT_REPAIR][status=REPAIRED][map={MAP_ID}][descendants={#map:GetDescendants()}]`)
return HttpService:JSONEncode(report)
