--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Role =
	"MapRoot"
	| "EnemySpawn"
	| "PathNode"
	| "DefenderBase"
	| "PlacementZone"
	| "NoPlacementZone"
	| "MapBounds"
	| "CameraAnchor"
	| "PlayerSpawn"

export type AttributeValueType = "string" | "number"
export type AttributeKind = "MapId" | "SymbolicKey" | "ContractVersion" | "NodeOrder"

export type AttributeDefinition = {
	name: string,
	valueType: AttributeValueType,
	kind: AttributeKind,
	minimum: number?,
	maximum: number?,
	integer: boolean,
}

export type MarkerDefinition = {
	role: Role,
	tag: string,
	className: string,
	parentName: string,
	attributes: { AttributeDefinition },
}

local CONTRACT_VERSION = 1
local RESERVED_PREFIX = "ATD_"
local TRUSTED_CATALOG_NAME = "ATDMapTemplates"
local RUNTIME_ROOT_NAME = "ATDRuntimeMap"

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

local Names = table.freeze({
	Geometry = "Geometry",
	Markers = "Markers",
	EnemySpawns = "EnemySpawns",
	PathNodes = "PathNodes",
	DefenderBase = "DefenderBase",
	PlacementZones = "PlacementZones",
	NoPlacementZones = "NoPlacementZones",
	MapBounds = "MapBounds",
	CameraAnchors = "CameraAnchors",
	PlayerSpawns = "PlayerSpawns",
})

local Limits = table.freeze({
	MAX_CATALOG_TEMPLATES = 32,
	MIN_DESCENDANTS = 10,
	MAX_DESCENDANTS = 2_048,
	MAX_DEPTH = 32,
	MAX_CHILDREN = 2_048,
	MAX_TAGS_PER_INSTANCE = 8,
	MAX_TAGS_TOTAL = 4_096,
	MAX_ATTRIBUTES_PER_INSTANCE = 16,
	MAX_ATTRIBUTES_TOTAL = 8_192,
	MAX_METADATA_NAME_BYTES = 100,
	MAX_ISSUES = 256,
	MAX_LANES = 32,
	MIN_NODES_PER_LANE = 1,
	MAX_NODES_PER_LANE = 256,
	MAX_NODES_TOTAL = 1_024,
	MIN_PLACEMENT_ZONES = 1,
	MAX_PLACEMENT_ZONES = 64,
	MIN_NO_PLACEMENT_ZONES = 1,
	MAX_NO_PLACEMENT_ZONES = 64,
	MIN_CAMERA_ANCHORS = 1,
	MAX_CAMERA_ANCHORS = 16,
	MIN_PLAYER_SPAWNS = 1,
	MAX_PLAYER_SPAWNS = 4,
	MAX_NAME_BYTES = 100,
	MAX_COORDINATE = 100_000,
	MIN_PART_SIZE = 0.1,
	MAX_POINT_MARKER_SIZE = 64,
	MAX_PART_SIZE = 4_096,
	MIN_MAP_BOUNDS_SIZE = 1,
	ROTATION_TOLERANCE = 1e-6,
	GEOMETRY_TOLERANCE = 1e-6,
	MIN_SEGMENT_LENGTH = 0.01,
	MAX_SEGMENT_LENGTH = 512,
	MAX_LANE_LENGTH = 32_768,
	MIN_BEND_SINE = math.sin(math.rad(5)),
})

local GeometryClasses = table.freeze({
	Folder = true,
	Model = true,
	Part = true,
	WedgePart = true,
	CornerWedgePart = true,
	TrussPart = true,
	MeshPart = true,
	UnionOperation = true,
	Decal = true,
	Texture = true,
	SurfaceAppearance = true,
})

local GrayboxGeometryClasses = table.freeze({
	Folder = true,
	Model = true,
	Part = true,
})

local function attribute(
	name: string,
	valueType: AttributeValueType,
	kind: AttributeKind,
	minimum: number?,
	maximum: number?,
	integer: boolean
): AttributeDefinition
	return table.freeze({
		name = name,
		valueType = valueType,
		kind = kind,
		minimum = minimum,
		maximum = maximum,
		integer = integer,
	})
end

local function frozenAttributes(values: { AttributeDefinition }): { AttributeDefinition }
	return table.freeze(values)
end

local definitions: { MarkerDefinition } = table.freeze({
	table.freeze({
		role = "MapRoot",
		tag = Tags.MapRoot,
		className = "Model",
		parentName = TRUSTED_CATALOG_NAME,
		attributes = frozenAttributes({
			attribute(Attributes.MapId, "string", "MapId", nil, nil, false),
			attribute(
				Attributes.MapContractVersion,
				"number",
				"ContractVersion",
				CONTRACT_VERSION,
				CONTRACT_VERSION,
				true
			),
		}),
	}),
	table.freeze({
		role = "EnemySpawn",
		tag = Tags.EnemySpawn,
		className = "Part",
		parentName = Names.EnemySpawns,
		attributes = frozenAttributes({ attribute(Attributes.LaneId, "string", "SymbolicKey", nil, nil, false) }),
	}),
	table.freeze({
		role = "PathNode",
		tag = Tags.PathNode,
		className = "Part",
		parentName = Names.PathNodes,
		attributes = frozenAttributes({
			attribute(Attributes.LaneId, "string", "SymbolicKey", nil, nil, false),
			attribute(Attributes.NodeOrder, "number", "NodeOrder", 1, Limits.MAX_NODES_PER_LANE, true),
		}),
	}),
	table.freeze({
		role = "DefenderBase",
		tag = Tags.DefenderBase,
		className = "Part",
		parentName = Names.Markers,
		attributes = frozenAttributes({}),
	}),
	table.freeze({
		role = "PlacementZone",
		tag = Tags.PlacementZone,
		className = "Part",
		parentName = Names.PlacementZones,
		attributes = frozenAttributes({ attribute(Attributes.ZoneId, "string", "SymbolicKey", nil, nil, false) }),
	}),
	table.freeze({
		role = "NoPlacementZone",
		tag = Tags.NoPlacementZone,
		className = "Part",
		parentName = Names.NoPlacementZones,
		attributes = frozenAttributes({ attribute(Attributes.ZoneId, "string", "SymbolicKey", nil, nil, false) }),
	}),
	table.freeze({
		role = "MapBounds",
		tag = Tags.MapBounds,
		className = "Part",
		parentName = Names.Markers,
		attributes = frozenAttributes({}),
	}),
	table.freeze({
		role = "CameraAnchor",
		tag = Tags.CameraAnchor,
		className = "Part",
		parentName = Names.CameraAnchors,
		attributes = frozenAttributes({ attribute(Attributes.AnchorId, "string", "SymbolicKey", nil, nil, false) }),
	}),
	table.freeze({
		role = "PlayerSpawn",
		tag = Tags.PlayerSpawn,
		className = "SpawnLocation",
		parentName = Names.PlayerSpawns,
		attributes = frozenAttributes({ attribute(Attributes.SpawnId, "string", "SymbolicKey", nil, nil, false) }),
	}),
})

local byRole: { [Role]: MarkerDefinition } = {}
local byTag: { [string]: MarkerDefinition } = {}
for _, definition in definitions do
	byRole[definition.role] = definition
	byTag[definition.tag] = definition
end
table.freeze(byRole)
table.freeze(byTag)

local MapContract = {
	CONTRACT_VERSION = CONTRACT_VERSION,
	RESERVED_PREFIX = RESERVED_PREFIX,
	TRUSTED_CATALOG_NAME = TRUSTED_CATALOG_NAME,
	RUNTIME_ROOT_NAME = RUNTIME_ROOT_NAME,
	Tags = Tags,
	Attributes = Attributes,
	Names = Names,
	Limits = Limits,
	GeometryClasses = GeometryClasses,
	GrayboxGeometryClasses = GrayboxGeometryClasses,
}

function MapContract.listDefinitions(): { MarkerDefinition }
	return definitions
end

function MapContract.getDefinition(role: unknown): MarkerDefinition?
	if type(role) ~= "string" then
		return nil
	end
	return byRole[role :: Role]
end

function MapContract.getDefinitionByTag(tag: unknown): MarkerDefinition?
	if type(tag) ~= "string" then
		return nil
	end
	return byTag[tag]
end

function MapContract.isReservedName(value: unknown): boolean
	return type(value) == "string" and string.sub(value, 1, #RESERVED_PREFIX) == RESERVED_PREFIX
end

function MapContract.isGeometryClass(className: unknown): boolean
	return type(className) == "string" and GeometryClasses[className] == true
end

function MapContract.isGrayboxGeometryClass(className: unknown): boolean
	return type(className) == "string" and GrayboxGeometryClasses[className] == true
end

function MapContract.formatMapName(mapIdValue: unknown): string?
	local result = Ids.validateMapId(mapIdValue)
	if not result.ok then
		return nil
	end
	local body = string.sub(result.value, #"map:" + 1)
	local name = `Map_{body}`
	return if #name <= Limits.MAX_NAME_BYTES then name else nil
end

function MapContract.formatMemberName(role: unknown, identityValue: unknown, nodeOrderValue: unknown): string?
	if role == "DefenderBase" then
		return if identityValue == nil and nodeOrderValue == nil then Names.DefenderBase else nil
	elseif role == "MapBounds" then
		return if identityValue == nil and nodeOrderValue == nil then Names.MapBounds else nil
	end

	if type(identityValue) ~= "string" or not Validation.isSymbolicKey(identityValue) then
		return nil
	end

	local prefix: string
	if role == "EnemySpawn" then
		prefix = "EnemySpawn"
	elseif role == "PathNode" then
		if
			type(nodeOrderValue) ~= "number"
			or not Validation.isSafeInteger(nodeOrderValue)
			or nodeOrderValue < 1
			or nodeOrderValue > Limits.MAX_NODES_PER_LANE
		then
			return nil
		end
		prefix = "PathNode"
	elseif role == "PlacementZone" then
		prefix = "PlacementZone"
	elseif role == "NoPlacementZone" then
		prefix = "NoPlacementZone"
	elseif role == "CameraAnchor" then
		prefix = "CameraAnchor"
	elseif role == "PlayerSpawn" then
		prefix = "PlayerSpawn"
	else
		return nil
	end

	if role ~= "PathNode" and nodeOrderValue ~= nil then
		return nil
	end
	local name = if role == "PathNode"
		then `{prefix}_{identityValue}_{nodeOrderValue :: number}`
		else `{prefix}_{identityValue}`
	return if #name <= Limits.MAX_NAME_BYTES then name else nil
end

return table.freeze(MapContract)
