--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local MapContract = require(script.Parent.MapContract)

export type PointSnapshot = {
	cframe: CFrame,
	position: Vector3,
}

export type NodeSnapshot = {
	order: number,
	cframe: CFrame,
	position: Vector3,
}

export type RegionSnapshot = {
	id: string,
	cframe: CFrame,
	size: Vector3,
}

export type NamedPointSnapshot = {
	id: string,
	cframe: CFrame,
	position: Vector3,
}

export type LaneSnapshot = {
	id: string,
	spawn: PointSnapshot,
	nodes: { NodeSnapshot },
}

export type ValidatedMapSnapshot = {
	mapId: Ids.MapId,
	base: PointSnapshot,
	bounds: {
		cframe: CFrame,
		size: Vector3,
	},
	lanes: { LaneSnapshot },
	placementZones: { RegionSnapshot },
	noPlacementZones: { RegionSnapshot },
	cameraAnchors: { NamedPointSnapshot },
	playerSpawns: { NamedPointSnapshot },
}

export type MapValidationReport = {
	issues: { Validation.Issue },
}

type AttributeEntry = {
	name: string,
	value: unknown,
	valueType: string,
}

type InternalNode = {
	instance: Instance,
	parent: InternalNode?,
	children: { InternalNode },
	depth: number,
	name: string,
	className: string,
	archivable: boolean,
	tags: { string },
	attributes: { AttributeEntry },
	attributeValues: { [string]: unknown },
	cframe: CFrame?,
	size: Vector3?,
	anchored: boolean?,
	canCollide: boolean?,
	canTouch: boolean?,
	canQuery: boolean?,
	enabled: boolean?,
	neutral: boolean?,
	primaryPart: BasePart?,
	structuralKey: string,
	basicPartValid: boolean,
}

type DiscoveryState = {
	descendants: number,
	tags: number,
	attributes: number,
	limitPath: string?,
}

type CanonicalMember = {
	node: InternalNode,
	path: { Validation.PathSegment },
	key: string,
}

type InternalPoint = {
	point: PointSnapshot,
	path: { Validation.PathSegment },
}

type InternalNamedPoint = {
	id: string,
	point: NamedPointSnapshot,
	path: { Validation.PathSegment },
}

type InternalNodePoint = {
	laneId: string,
	order: number,
	node: NodeSnapshot,
	path: { Validation.PathSegment },
}

type InternalRegion = {
	region: RegionSnapshot,
	path: { Validation.PathSegment },
}

type InternalSpawn = {
	laneId: string,
	point: PointSnapshot,
	path: { Validation.PathSegment },
}

local ROOT_PATH: { Validation.PathSegment } = table.freeze({ "Map" })

local ROLE_RANK: { [string]: number } = table.freeze({
	MapRoot = 1,
	EnemySpawn = 2,
	PathNode = 3,
	DefenderBase = 4,
	PlacementZone = 5,
	NoPlacementZone = 6,
	MapBounds = 7,
	CameraAnchor = 8,
	PlayerSpawn = 9,
})

local CODE_RANK: { [string]: number } = table.freeze({
	INVALID_TYPE = 1,
	INVALID_TABLE = 2,
	INVALID_ARRAY = 3,
	MISSING_FIELD = 4,
	UNKNOWN_FIELD = 5,
	RUNTIME_FIELD_FORBIDDEN = 6,
	INVALID_ID = 7,
	DUPLICATE_ID = 8,
	INVALID_STRING = 9,
	INVALID_ENUM = 10,
	NON_FINITE_NUMBER = 11,
	NOT_INTEGER = 12,
	OUT_OF_RANGE = 13,
	EMPTY_COLLECTION = 14,
	DUPLICATE_VALUE = 15,
	INVALID_ORDER = 16,
	INVALID_ASSET_KEY = 17,
	DUPLICATE_ASSET_KEY = 18,
	UNKNOWN_ASSET_KEY = 19,
	WRONG_ASSET_KIND = 20,
	INVALID_REFERENCE = 21,
	INVALID_TOTAL = 22,
	SOURCE_LOAD_FAILED = 23,
	UNSUPPORTED_VERSION = 24,
})

local DISPATCH_CLASSES: { [string]: boolean } = table.freeze({
	Script = true,
	LocalScript = true,
	ModuleScript = true,
	RemoteEvent = true,
	RemoteFunction = true,
	UnreliableRemoteEvent = true,
	BindableEvent = true,
	BindableFunction = true,
})

local KNOWN_ATTRIBUTE_NAMES: { [string]: boolean } = {}
for _, attributeName in MapContract.Attributes do
	KNOWN_ATTRIBUTE_NAMES[attributeName] = true
end
table.freeze(KNOWN_ATTRIBUTE_NAMES)

local issues: { Validation.Issue } = {}

local function pathWith(path: { Validation.PathSegment }, segment: Validation.PathSegment): { Validation.PathSegment }
	return Validation.appendPath(path, segment)
end

local function addIssue(code: Validation.Code, path: { Validation.PathSegment }, message: string)
	table.insert(issues, Validation.issue(code, path, message))
end

local function addTypeIssue(code: Validation.Code, path: { Validation.PathSegment }, message: string, value: unknown)
	table.insert(issues, Validation.issueWithType(code, path, message, value))
end

local function addRelatedIssue(
	code: Validation.Code,
	path: { Validation.PathSegment },
	message: string,
	relatedPath: { Validation.PathSegment }
)
	table.insert(issues, Validation.issueWithRelated(code, path, message, Validation.renderPath(relatedPath)))
end

local function numberToken(value: number): string
	if value ~= value then
		return "nan"
	elseif value == -math.huge then
		return "-inf"
	elseif value == math.huge then
		return "+inf"
	end
	return string.format("%.17g", value)
end

local function stringToken(value: string): string
	return `{#value}:{value}`
end

local function vectorToken(value: Vector3): string
	return `{numberToken(value.X)},{numberToken(value.Y)},{numberToken(value.Z)}`
end

local function cframeToken(value: CFrame): string
	local components = { value:GetComponents() }
	local tokens: { string } = table.create(#components)
	for index, component in components do
		tokens[index] = numberToken(component)
	end
	return table.concat(tokens, ",")
end

local function attributeValueToken(entry: AttributeEntry): string
	local value = entry.value
	if type(value) == "string" then
		return if #value <= MapContract.Limits.MAX_METADATA_NAME_BYTES then stringToken(value) else `oversize:{#value}`
	elseif type(value) == "number" then
		return numberToken(value)
	elseif type(value) == "boolean" then
		return if value then "true" else "false"
	end
	return entry.valueType
end

local function roleForNode(node: InternalNode): string?
	local bestRole: string? = nil
	local bestRank = math.huge
	for _, tag in node.tags do
		local definition = MapContract.getDefinitionByTag(tag)
		if definition ~= nil then
			local rank = ROLE_RANK[definition.role]
			if rank < bestRank then
				bestRole = definition.role
				bestRank = rank
			end
		end
	end
	return bestRole
end

local function validSymbolicAttribute(node: InternalNode, attributeName: string): string?
	local value = node.attributeValues[attributeName]
	return if type(value) == "string" and Validation.isSymbolicKey(value) then value else nil
end

local function structuralKey(node: InternalNode): string
	local role = roleForNode(node)
	local rank = if role == nil then 99 else ROLE_RANK[role]
	local identity = ""
	local nodeOrder = 0
	if role == "EnemySpawn" or role == "PathNode" then
		identity = validSymbolicAttribute(node, MapContract.Attributes.LaneId) or ""
	elseif role == "PlacementZone" or role == "NoPlacementZone" then
		identity = validSymbolicAttribute(node, MapContract.Attributes.ZoneId) or ""
	elseif role == "CameraAnchor" then
		identity = validSymbolicAttribute(node, MapContract.Attributes.AnchorId) or ""
	elseif role == "PlayerSpawn" then
		identity = validSymbolicAttribute(node, MapContract.Attributes.SpawnId) or ""
	end
	if role == "PathNode" then
		local value = node.attributeValues[MapContract.Attributes.NodeOrder]
		if
			type(value) == "number"
			and Validation.isSafeInteger(value)
			and value >= 1
			and value <= MapContract.Limits.MAX_NODES_PER_LANE
		then
			nodeOrder = value
		end
	end

	local safeName = if #node.name <= MapContract.Limits.MAX_NAME_BYTES then node.name else ""
	local reservedTags: { string } = {}
	for _, tag in node.tags do
		if MapContract.isReservedName(tag) then
			table.insert(reservedTags, stringToken(tag))
		end
	end
	local reservedAttributes: { string } = {}
	for _, entry in node.attributes do
		if MapContract.isReservedName(entry.name) then
			table.insert(reservedAttributes, `{stringToken(entry.name)}/{entry.valueType}/{attributeValueToken(entry)}`)
		end
	end

	local geometry = ""
	if node.cframe ~= nil then
		geometry = cframeToken(node.cframe)
	end
	if node.size ~= nil then
		geometry ..= `/{vectorToken(node.size)}`
	end
	geometry ..= `/{tostring(node.anchored)}/{tostring(node.canCollide)}/{tostring(node.canTouch)}/{tostring(
		node.canQuery
	)}/{tostring(node.enabled)}/{tostring(node.neutral)}`

	return table.concat({
		string.format("%02d", rank),
		stringToken(identity),
		numberToken(nodeOrder),
		stringToken(safeName),
		stringToken(node.className),
		table.concat(reservedTags, ","),
		table.concat(reservedAttributes, ","),
		geometry,
	}, "|")
end

local function metadataNameIsWellFormed(value: string): boolean
	return #value >= 1
		and #value <= MapContract.Limits.MAX_METADATA_NAME_BYTES
		and string.match(value, "^[A-Za-z][A-Za-z0-9_.-]*$") ~= nil
end

local function instanceNameIsSafe(value: string): boolean
	if #value < 1 or #value > MapContract.Limits.MAX_NAME_BYTES then
		return false
	end
	for index = 1, #value do
		local byte = string.byte(value, index)
		if byte < 32 or byte > 126 then
			return false
		end
	end
	return true
end

local function shallowSnapshot(
	instance: Instance,
	parent: InternalNode?,
	depth: number,
	state: DiscoveryState
): InternalNode?
	local rawTags = instance:GetTags()
	if #rawTags > MapContract.Limits.MAX_TAGS_PER_INSTANCE then
		state.limitPath = "Map.metadata"
		return nil
	end
	state.tags += #rawTags
	if state.tags > MapContract.Limits.MAX_TAGS_TOTAL then
		state.limitPath = "Map.metadata"
		return nil
	end

	local tags: { string } = table.create(#rawTags)
	for _, tag in rawTags do
		if #tag > MapContract.Limits.MAX_METADATA_NAME_BYTES then
			state.limitPath = "Map.metadata"
			return nil
		end
		table.insert(tags, tag)
	end
	table.sort(tags)

	local rawAttributes = instance:GetAttributes()
	local attributeCount = 0
	local attributes: { AttributeEntry } = {}
	local attributeValues: { [string]: unknown } = {}
	for name, value in rawAttributes do
		attributeCount += 1
		if attributeCount > MapContract.Limits.MAX_ATTRIBUTES_PER_INSTANCE then
			state.limitPath = "Map.metadata"
			return nil
		end
		if #name > MapContract.Limits.MAX_METADATA_NAME_BYTES then
			state.limitPath = "Map.metadata"
			return nil
		end
		attributeValues[name] = value
		table.insert(attributes, {
			name = name,
			value = value,
			valueType = typeof(value),
		})
	end
	state.attributes += attributeCount
	if state.attributes > MapContract.Limits.MAX_ATTRIBUTES_TOTAL then
		state.limitPath = "Map.metadata"
		return nil
	end
	table.sort(attributes, function(left, right)
		if left.name ~= right.name then
			return left.name < right.name
		elseif left.valueType ~= right.valueType then
			return left.valueType < right.valueType
		end
		return attributeValueToken(left) < attributeValueToken(right)
	end)

	local cframe: CFrame? = nil
	local size: Vector3? = nil
	local anchored: boolean? = nil
	local canCollide: boolean? = nil
	local canTouch: boolean? = nil
	local canQuery: boolean? = nil
	if instance:IsA("BasePart") then
		local part = instance :: BasePart
		cframe = part.CFrame
		size = part.Size
		anchored = part.Anchored
		canCollide = part.CanCollide
		canTouch = part.CanTouch
		canQuery = part.CanQuery
	end

	local enabled: boolean? = nil
	local neutral: boolean? = nil
	if instance:IsA("SpawnLocation") then
		local spawn = instance :: SpawnLocation
		enabled = spawn.Enabled
		neutral = spawn.Neutral
	end

	local primaryPart: BasePart? = nil
	if instance:IsA("Model") then
		primaryPart = (instance :: Model).PrimaryPart
	end

	local node: InternalNode = {
		instance = instance,
		parent = parent,
		children = {},
		depth = depth,
		name = instance.Name,
		className = instance.ClassName,
		archivable = instance.Archivable,
		tags = tags,
		attributes = attributes,
		attributeValues = attributeValues,
		cframe = cframe,
		size = size,
		anchored = anchored,
		canCollide = canCollide,
		canTouch = canTouch,
		canQuery = canQuery,
		enabled = enabled,
		neutral = neutral,
		primaryPart = primaryPart,
		structuralKey = "",
		basicPartValid = false,
	}
	node.structuralKey = structuralKey(node)
	return node
end

local function discover(root: Instance): (InternalNode?, DiscoveryState)
	local state: DiscoveryState = {
		descendants = 0,
		tags = 0,
		attributes = 0,
		limitPath = nil,
	}
	local rootNode = shallowSnapshot(root, nil, 0, state)
	if rootNode == nil then
		return nil, state
	end

	local queue: { InternalNode } = { rootNode }
	local queueIndex = 1
	while queueIndex <= #queue do
		local node = queue[queueIndex]
		queueIndex += 1
		local rawChildren = node.instance:GetChildren()
		if #rawChildren > MapContract.Limits.MAX_CHILDREN then
			state.limitPath = "Map.traversal"
			return rootNode, state
		end
		if node.depth >= MapContract.Limits.MAX_DEPTH and #rawChildren > 0 then
			state.limitPath = "Map.traversal"
			return rootNode, state
		end

		local children: { InternalNode } = table.create(#rawChildren)
		for _, child in rawChildren do
			state.descendants += 1
			if state.descendants > MapContract.Limits.MAX_DESCENDANTS then
				state.limitPath = "Map.traversal"
				return rootNode, state
			end
			local childNode = shallowSnapshot(child, node, node.depth + 1, state)
			if childNode == nil then
				return rootNode, state
			end
			table.insert(children, childNode)
		end
		table.sort(children, function(left, right)
			return left.structuralKey < right.structuralKey
		end)
		node.children = children
		for _, child in children do
			table.insert(queue, child)
		end
	end

	return rootNode, state
end

local function sortedIssues(): { Validation.Issue }
	table.sort(issues, function(left, right)
		if left.path ~= right.path then
			return left.path < right.path
		end
		local leftRank = CODE_RANK[left.code] or 999
		local rightRank = CODE_RANK[right.code] or 999
		if leftRank ~= rightRank then
			return leftRank < rightRank
		end
		local leftRelated = left.relatedPath or ""
		local rightRelated = right.relatedPath or ""
		if leftRelated ~= rightRelated then
			return leftRelated < rightRelated
		end
		if left.message ~= right.message then
			return left.message < right.message
		end
		local leftType = left.actualType or ""
		local rightType = right.actualType or ""
		if leftType ~= rightType then
			return leftType < rightType
		end
		return (left.causeCode or "") < (right.causeCode or "")
	end)

	if #issues <= MapContract.Limits.MAX_ISSUES then
		return table.freeze(issues)
	end

	local limited: { Validation.Issue } = table.create(MapContract.Limits.MAX_ISSUES)
	for index = 1, MapContract.Limits.MAX_ISSUES - 1 do
		limited[index] = issues[index]
	end
	limited[MapContract.Limits.MAX_ISSUES] = Validation.issue(
		"OUT_OF_RANGE",
		{ "Map", "issues" },
		"Additional map validation issues were omitted at the fixed issue limit"
	)
	return table.freeze(limited)
end

local function failure(): Result.Failure<MapValidationReport>
	return Result.err(table.freeze({
		issues = sortedIssues(),
	}))
end

local function finiteVector(value: Vector3): boolean
	return Validation.isFiniteNumber(value.X)
		and Validation.isFiniteNumber(value.Y)
		and Validation.isFiniteNumber(value.Z)
end

local function finiteCFrame(value: CFrame): boolean
	local components = { value:GetComponents() }
	for _, component in components do
		if not Validation.isFiniteNumber(component) then
			return false
		end
	end
	return true
end

local function withinAbsoluteCoordinateLimit(position: Vector3): boolean
	local maximum = MapContract.Limits.MAX_COORDINATE
	return math.abs(position.X) <= maximum and math.abs(position.Y) <= maximum and math.abs(position.Z) <= maximum
end

local function withinSizeRange(size: Vector3, minimum: number, maximum: number): boolean
	return size.X >= minimum
		and size.X <= maximum
		and size.Y >= minimum
		and size.Y <= maximum
		and size.Z >= minimum
		and size.Z <= maximum
end

local function validateBasicPart(node: InternalNode, path: { Validation.PathSegment })
	if node.cframe == nil or node.size == nil then
		return
	end

	local valid = true
	if not finiteCFrame(node.cframe) then
		addIssue("NON_FINITE_NUMBER", pathWith(path, "CFrame"), "BasePart CFrame must contain only finite components")
		valid = false
	else
		local position = node.cframe.Position
		if not finiteVector(position) then
			addIssue("NON_FINITE_NUMBER", pathWith(path, "CFrame"), "BasePart position must be finite")
			valid = false
		elseif not withinAbsoluteCoordinateLimit(position) then
			addIssue("OUT_OF_RANGE", pathWith(path, "CFrame"), "BasePart position exceeds the map coordinate limit")
			valid = false
		end
	end

	if not finiteVector(node.size) then
		addIssue("NON_FINITE_NUMBER", pathWith(path, "Size"), "BasePart Size must contain only finite components")
		valid = false
	elseif not withinSizeRange(node.size, MapContract.Limits.MIN_PART_SIZE, MapContract.Limits.MAX_PART_SIZE) then
		addIssue("OUT_OF_RANGE", pathWith(path, "Size"), "BasePart Size is outside the map geometry limits")
		valid = false
	end

	if node.anchored ~= true then
		addIssue("INVALID_ENUM", pathWith(path, "Anchored"), "Every map BasePart must be anchored")
		valid = false
	end

	node.basicPartValid = valid
end

local function genericChildPaths(
	node: InternalNode,
	path: { Validation.PathSegment }
): { [InternalNode]: { Validation.PathSegment } }
	local paths: { [InternalNode]: { Validation.PathSegment } } = {}
	local ordinal = 0
	local previousKey: string? = nil
	for _, child in node.children do
		if previousKey ~= child.structuralKey then
			ordinal += 1
			previousKey = child.structuralKey
		end
		paths[child] = pathWith(pathWith(path, "children"), ordinal)
	end
	return paths
end

local function validateGlobalNode(node: InternalNode, root: InternalNode, path: { Validation.PathSegment })
	if not instanceNameIsSafe(node.name) then
		addIssue(
			"INVALID_STRING",
			pathWith(path, "Name"),
			"Instance Name must be printable ASCII within the fixed byte limit"
		)
	end
	if not node.archivable then
		addIssue("INVALID_ENUM", pathWith(path, "Archivable"), "Every map Instance must be Archivable")
	end
	if DISPATCH_CLASSES[node.className] == true or node.instance:IsA("LuaSourceContainer") then
		addIssue(
			"RUNTIME_FIELD_FORBIDDEN",
			pathWith(path, "ClassName"),
			"Map templates may not contain executable or dispatch Instances"
		)
	end

	local previousTag: string? = nil
	local semanticTagCount = 0
	for _, tag in node.tags do
		if not metadataNameIsWellFormed(tag) then
			addIssue("INVALID_STRING", pathWith(path, "tags"), "Tag names must use the fixed safe metadata syntax")
		end
		if tag == previousTag then
			addIssue("DUPLICATE_VALUE", pathWith(path, "tags"), "Duplicate tag entries are forbidden")
		end
		previousTag = tag

		local definition = MapContract.getDefinitionByTag(tag)
		if definition ~= nil then
			semanticTagCount += 1
			local parent = node.parent
			local ancestryValid = if definition.role == "MapRoot"
				then node == root
				else parent ~= nil and parent.name == definition.parentName
			if
				ancestryValid
				and definition.role ~= "MapRoot"
				and definition.role ~= "DefenderBase"
				and definition.role ~= "MapBounds"
			then
				ancestryValid = parent ~= nil
					and parent.parent ~= nil
					and parent.parent.name == MapContract.Names.Markers
			end
			if not ancestryValid then
				addIssue(
					"INVALID_REFERENCE",
					pathWith(path, "tags"),
					"Semantic map tag appears outside its fixed contract ancestry"
				)
			end
		elseif MapContract.isReservedName(tag) then
			addIssue("UNKNOWN_FIELD", pathWith(path, "tags"), "Unknown reserved map tags are forbidden")
		end
	end
	if semanticTagCount > 1 then
		addIssue("DUPLICATE_VALUE", pathWith(path, "tags"), "An Instance may carry at most one semantic map tag")
	end

	for _, entry in node.attributes do
		if not metadataNameIsWellFormed(entry.name) then
			addIssue(
				"INVALID_STRING",
				pathWith(path, "attributes"),
				"Attribute names must use the fixed safe metadata syntax"
			)
		end
		if MapContract.isReservedName(entry.name) and KNOWN_ATTRIBUTE_NAMES[entry.name] ~= true then
			local issuePath = if metadataNameIsWellFormed(entry.name)
				then pathWith(path, entry.name)
				else pathWith(path, "attributes")
			addIssue("UNKNOWN_FIELD", issuePath, "Unknown reserved map attributes are forbidden")
		end
	end

	if
		node.primaryPart ~= nil
		and node.primaryPart ~= root.instance
		and not node.primaryPart:IsDescendantOf(root.instance)
	then
		addIssue(
			"INVALID_REFERENCE",
			pathWith(path, "PrimaryPart"),
			"Model PrimaryPart must remain inside the selected map root"
		)
	end

	if node.instance:IsA("BasePart") then
		validateBasicPart(node, path)
	end

	local seenNames: { [string]: { Validation.PathSegment } } = {}
	local childPaths = genericChildPaths(node, path)
	for _, child in node.children do
		local childPath = childPaths[child]
		local previousPath = seenNames[child.name]
		if previousPath ~= nil then
			addRelatedIssue(
				"DUPLICATE_VALUE",
				pathWith(path, "children"),
				"Sibling Instance names must be unique",
				previousPath
			)
		else
			seenNames[child.name] = childPath
		end
		validateGlobalNode(child, root, childPath)
	end
end

local function roleAttributeSet(definition: MapContract.MarkerDefinition): { [string]: boolean }
	local allowed: { [string]: boolean } = {}
	for _, attribute in definition.attributes do
		allowed[attribute.name] = true
	end
	return allowed
end

local function validateAttributeValue(
	node: InternalNode,
	attribute: MapContract.AttributeDefinition,
	path: { Validation.PathSegment },
	expectedMapId: Ids.MapId
): unknown
	local value = node.attributeValues[attribute.name]
	local attributePath = pathWith(path, attribute.name)
	if value == nil then
		addIssue("MISSING_FIELD", attributePath, "Required map attribute is missing")
		return nil
	end

	if type(value) ~= attribute.valueType then
		addTypeIssue("INVALID_TYPE", attributePath, "Map attribute has the wrong value type", value)
		return nil
	end

	if attribute.kind == "MapId" then
		local result = Ids.validateMapId(value)
		if not result.ok then
			table.insert(
				issues,
				Validation.issueWithCause(
					"INVALID_ID",
					attributePath,
					"Map root has an invalid MapId",
					result.error.code
				)
			)
			return nil
		end
		if result.value ~= expectedMapId then
			addIssue("INVALID_ID", attributePath, "Map root MapId does not match the authenticated server selection")
			return nil
		end
		return result.value
	elseif attribute.kind == "SymbolicKey" then
		local symbolic = value :: string
		if not Validation.isSymbolicKey(symbolic) then
			addIssue("INVALID_STRING", attributePath, "Map identity attributes must use the symbolic-key contract")
			return nil
		end
		return symbolic
	end

	local numeric = value :: number
	if not Validation.isFiniteNumber(numeric) then
		addIssue("NON_FINITE_NUMBER", attributePath, "Numeric map attributes must be finite")
		return nil
	end
	if attribute.integer and not Validation.isSafeInteger(numeric) then
		addIssue("NOT_INTEGER", attributePath, "Numeric map attribute must be a safe integer")
		return nil
	end
	if
		attribute.minimum ~= nil and numeric < attribute.minimum
		or attribute.maximum ~= nil and numeric > attribute.maximum
	then
		if attribute.kind == "ContractVersion" then
			addIssue("UNSUPPORTED_VERSION", attributePath, "Map contract version is unsupported")
		else
			addIssue("OUT_OF_RANGE", attributePath, "Numeric map attribute is outside its fixed bounds")
		end
		return nil
	end
	return numeric
end

local function validateRoleMetadata(
	node: InternalNode,
	role: MapContract.Role,
	path: { Validation.PathSegment },
	expectedMapId: Ids.MapId
): { [string]: unknown }
	local definition = MapContract.getDefinition(role) :: MapContract.MarkerDefinition
	local expectedTagCount = 0
	for _, tag in node.tags do
		local tagDefinition = MapContract.getDefinitionByTag(tag)
		if tag == definition.tag then
			expectedTagCount += 1
		elseif tagDefinition ~= nil then
			addIssue("UNKNOWN_FIELD", pathWith(path, "tags"), "Semantic map tag conflicts with this authored role")
		end
	end
	if expectedTagCount == 0 then
		addIssue("MISSING_FIELD", pathWith(path, "tags"), "Required semantic map tag is missing")
	elseif expectedTagCount > 1 then
		addIssue("DUPLICATE_VALUE", pathWith(path, "tags"), "Required semantic map tag is duplicated")
	end

	local allowedAttributes = roleAttributeSet(definition)
	for _, entry in node.attributes do
		if KNOWN_ATTRIBUTE_NAMES[entry.name] == true and allowedAttributes[entry.name] ~= true then
			addIssue(
				"UNKNOWN_FIELD",
				pathWith(path, "attributes"),
				"Reserved map attribute conflicts with this authored role"
			)
		end
	end

	local values: { [string]: unknown } = {}
	for _, attribute in definition.attributes do
		values[attribute.name] = validateAttributeValue(node, attribute, path, expectedMapId)
	end
	return values
end

local function validateNoRoleMetadata(node: InternalNode, path: { Validation.PathSegment })
	for _, tag in node.tags do
		if MapContract.getDefinitionByTag(tag) ~= nil then
			addIssue("UNKNOWN_FIELD", pathWith(path, "tags"), "Semantic map tags are forbidden on this Instance")
		end
	end
	for _, entry in node.attributes do
		if KNOWN_ATTRIBUTE_NAMES[entry.name] == true then
			addIssue(
				"UNKNOWN_FIELD",
				pathWith(path, "attributes"),
				"Reserved map attributes are forbidden on this Instance"
			)
		end
	end
end

local function validateClass(node: InternalNode, expectedClass: string, path: { Validation.PathSegment }): boolean
	if node.className ~= expectedClass then
		addIssue("INVALID_TYPE", pathWith(path, "ClassName"), "Instance has the wrong class for its map role")
		return false
	end
	return true
end

local function validateExactName(node: InternalNode, expectedName: string?, path: { Validation.PathSegment }): boolean
	if expectedName == nil or node.name ~= expectedName then
		addIssue("INVALID_STRING", pathWith(path, "Name"), "Instance Name does not match its canonical map role name")
		return false
	end
	return true
end

local function canonicalMembers(
	folder: InternalNode,
	role: MapContract.Role,
	path: { Validation.PathSegment }
): { CanonicalMember }
	local members: { CanonicalMember } = table.create(#folder.children)
	for _, node in folder.children do
		local identity = ""
		local order = 0
		if role == "EnemySpawn" or role == "PathNode" then
			identity = validSymbolicAttribute(node, MapContract.Attributes.LaneId) or ""
		elseif role == "PlacementZone" or role == "NoPlacementZone" then
			identity = validSymbolicAttribute(node, MapContract.Attributes.ZoneId) or ""
		elseif role == "CameraAnchor" then
			identity = validSymbolicAttribute(node, MapContract.Attributes.AnchorId) or ""
		elseif role == "PlayerSpawn" then
			identity = validSymbolicAttribute(node, MapContract.Attributes.SpawnId) or ""
		end
		if role == "PathNode" then
			local value = node.attributeValues[MapContract.Attributes.NodeOrder]
			if type(value) == "number" and Validation.isSafeInteger(value) then
				order = value
			end
		end
		local key = `{stringToken(identity)}|{numberToken(order)}|{node.structuralKey}`
		table.insert(members, {
			node = node,
			path = {},
			key = key,
		})
	end
	table.sort(members, function(left, right)
		return left.key < right.key
	end)

	local ordinal = 0
	local previousKey: string? = nil
	for _, member in members do
		if member.key ~= previousKey then
			ordinal += 1
			previousKey = member.key
		end
		member.path = pathWith(path, ordinal)
	end
	return members
end

local function validateFolder(node: InternalNode, path: { Validation.PathSegment }): boolean
	local valid = validateClass(node, "Folder", path)
	validateNoRoleMetadata(node, path)
	return valid
end

local function findExactChild(parent: InternalNode, name: string, path: { Validation.PathSegment }): InternalNode?
	local matches: { InternalNode } = {}
	for _, child in parent.children do
		if child.name == name then
			table.insert(matches, child)
		end
	end
	if #matches == 0 then
		addIssue("MISSING_FIELD", path, "Required map hierarchy member is missing")
		return nil
	elseif #matches > 1 then
		addIssue("DUPLICATE_VALUE", path, "Required map hierarchy member is duplicated")
		return nil
	end
	return matches[1]
end

local function rejectUnexpectedChildren(
	parent: InternalNode,
	allowedNames: { [string]: boolean },
	path: { Validation.PathSegment }
)
	local unexpected: { InternalNode } = {}
	for _, child in parent.children do
		if allowedNames[child.name] ~= true then
			table.insert(unexpected, child)
		end
	end
	table.sort(unexpected, function(left, right)
		return left.structuralKey < right.structuralKey
	end)
	local ordinal = 0
	local previousKey: string? = nil
	for _, child in unexpected do
		if child.structuralKey ~= previousKey then
			ordinal += 1
			previousKey = child.structuralKey
		end
		addIssue(
			"UNKNOWN_FIELD",
			pathWith(pathWith(path, "children"), ordinal),
			"Map hierarchy contains an unexpected child"
		)
	end
end

local function validateLeaf(node: InternalNode, path: { Validation.PathSegment }): boolean
	if #node.children > 0 then
		addIssue("UNKNOWN_FIELD", pathWith(path, "children"), "Map marker Instances must be leaves")
		return false
	end
	return true
end

local function pointMarkerSnapshot(
	node: InternalNode,
	path: { Validation.PathSegment },
	isPlayerSpawn: boolean
): PointSnapshot?
	if not node.basicPartValid and node.instance:IsA("BasePart") then
		validateBasicPart(node, path)
	end
	local valid = node.basicPartValid
	if node.size == nil or node.cframe == nil then
		return nil
	end
	if not withinSizeRange(node.size, MapContract.Limits.MIN_PART_SIZE, MapContract.Limits.MAX_POINT_MARKER_SIZE) then
		addIssue("OUT_OF_RANGE", pathWith(path, "Size"), "Point marker Size is outside the fixed marker bounds")
		valid = false
	end

	if isPlayerSpawn then
		if node.enabled ~= true then
			addIssue("INVALID_ENUM", pathWith(path, "Enabled"), "Player spawn must be enabled")
			valid = false
		end
		if node.neutral ~= true then
			addIssue("INVALID_ENUM", pathWith(path, "Neutral"), "Player spawn must be neutral")
			valid = false
		end
	else
		if node.canCollide ~= false then
			addIssue("INVALID_ENUM", pathWith(path, "CanCollide"), "Non-player map markers must not collide")
			valid = false
		end
		if node.canTouch ~= false then
			addIssue(
				"INVALID_ENUM",
				pathWith(path, "CanTouch"),
				"Non-player map markers must not generate touch events"
			)
			valid = false
		end
		if node.canQuery ~= false then
			addIssue(
				"INVALID_ENUM",
				pathWith(path, "CanQuery"),
				"Non-player map markers must not participate in spatial queries"
			)
			valid = false
		end
	end

	if not valid then
		return nil
	end
	local cframe = node.cframe
	return table.freeze({
		cframe = cframe,
		position = cframe.Position,
	})
end

local function identityRotation(cframe: CFrame): boolean
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cframe:GetComponents()
	local tolerance = MapContract.Limits.ROTATION_TOLERANCE
	return math.abs(r00 - 1) <= tolerance
		and math.abs(r01) <= tolerance
		and math.abs(r02) <= tolerance
		and math.abs(r10) <= tolerance
		and math.abs(r11 - 1) <= tolerance
		and math.abs(r12) <= tolerance
		and math.abs(r20) <= tolerance
		and math.abs(r21) <= tolerance
		and math.abs(r22 - 1) <= tolerance
end

local function regionGeometry(
	node: InternalNode,
	path: { Validation.PathSegment },
	minimumSize: number
): (CFrame?, Vector3?)
	if not node.basicPartValid and node.instance:IsA("BasePart") then
		validateBasicPart(node, path)
	end
	local valid = node.basicPartValid
	if node.cframe == nil or node.size == nil then
		return nil, nil
	end
	if not withinSizeRange(node.size, minimumSize, MapContract.Limits.MAX_PART_SIZE) then
		addIssue("OUT_OF_RANGE", pathWith(path, "Size"), "Region Size is outside the fixed map bounds")
		valid = false
	end
	if finiteCFrame(node.cframe) and not identityRotation(node.cframe) then
		addIssue("INVALID_ENUM", pathWith(path, "CFrame"), "Authored map regions must use identity world rotation")
		valid = false
	end
	if node.canCollide ~= false then
		addIssue("INVALID_ENUM", pathWith(path, "CanCollide"), "Map regions must not collide")
		valid = false
	end
	if node.canTouch ~= false then
		addIssue("INVALID_ENUM", pathWith(path, "CanTouch"), "Map regions must not generate touch events")
		valid = false
	end
	if node.canQuery ~= false then
		addIssue("INVALID_ENUM", pathWith(path, "CanQuery"), "Map regions must not participate in spatial queries")
		valid = false
	end
	return if valid then node.cframe else nil, if valid then node.size else nil
end

local function validateGeometry(
	geometry: InternalNode,
	path: { Validation.PathSegment }
): { { cframe: CFrame, size: Vector3, path: { Validation.PathSegment } } }
	validateFolder(geometry, path)
	local parts: { { cframe: CFrame, size: Vector3, path: { Validation.PathSegment } } } = {}

	local function visit(node: InternalNode, nodePath: { Validation.PathSegment })
		validateNoRoleMetadata(node, nodePath)
		if not MapContract.isGeometryClass(node.className) then
			addIssue(
				"INVALID_TYPE",
				pathWith(nodePath, "ClassName"),
				"Geometry contains a class outside the reviewed allowlist"
			)
			return
		end
		if node.instance:IsA("BasePart") and not node.basicPartValid then
			validateBasicPart(node, nodePath)
		end
		if node.instance:IsA("BasePart") and node.basicPartValid and node.cframe ~= nil and node.size ~= nil then
			table.insert(parts, {
				cframe = node.cframe,
				size = node.size,
				path = nodePath,
			})
		end

		for _, child in node.children do
			local safeName = if string.match(child.name, "^[A-Za-z][A-Za-z0-9_.-]*$") ~= nil
				then child.name
				else "<invalid>"
			local segment = `{safeName}<{child.className}>`
			visit(child, pathWith(nodePath, segment))
		end
	end

	for _, child in geometry.children do
		local safeName = if string.match(child.name, "^[A-Za-z][A-Za-z0-9_.-]*$") ~= nil
			then child.name
			else "<invalid>"
		visit(child, pathWith(path, `{safeName}<{child.className}>`))
	end
	return parts
end

local function validateMemberShell(
	member: CanonicalMember,
	role: MapContract.Role,
	expectedMapId: Ids.MapId
): ({ [string]: unknown }, boolean)
	local node = member.node
	local definition = MapContract.getDefinition(role) :: MapContract.MarkerDefinition
	local issueCount = #issues
	local classValid = validateClass(node, definition.className, member.path)
	for _, tag in node.tags do
		local actualDefinition = MapContract.getDefinitionByTag(tag)
		if actualDefinition ~= nil and actualDefinition.role ~= role then
			addIssue(
				"INVALID_REFERENCE",
				{ "Map", "Markers", actualDefinition.parentName },
				"Semantic marker is authored under the wrong role Folder"
			)
		end
	end
	local values = validateRoleMetadata(node, role, member.path, expectedMapId)
	local leafValid = validateLeaf(node, member.path)
	return values, classValid and leafValid and #issues == issueCount
end

local function validateEnemySpawns(
	folder: InternalNode,
	path: { Validation.PathSegment },
	expectedMapId: Ids.MapId
): { InternalSpawn }
	validateFolder(folder, path)
	local count = #folder.children
	if count < 1 then
		addIssue("EMPTY_COLLECTION", path, "At least one enemy spawn is required")
	elseif count > MapContract.Limits.MAX_LANES then
		addIssue("OUT_OF_RANGE", path, "Enemy spawn collection exceeds the lane limit")
	end

	local output: { InternalSpawn } = {}
	for _, member in canonicalMembers(folder, "EnemySpawn", path) do
		local values, shellValid = validateMemberShell(member, "EnemySpawn", expectedMapId)
		local laneId = values[MapContract.Attributes.LaneId]
		local expectedName = MapContract.formatMemberName("EnemySpawn", laneId, nil)
		local nameValid = validateExactName(member.node, expectedName, member.path)
		local point = if member.node.className == "Part"
			then pointMarkerSnapshot(member.node, member.path, false)
			else nil
		if shellValid and nameValid and type(laneId) == "string" and point ~= nil then
			table.insert(output, {
				laneId = laneId,
				point = point,
				path = member.path,
			})
		end
	end
	return output
end

local function validatePathNodes(
	folder: InternalNode,
	path: { Validation.PathSegment },
	expectedMapId: Ids.MapId
): { InternalNodePoint }
	validateFolder(folder, path)
	local count = #folder.children
	if count < 1 then
		addIssue("EMPTY_COLLECTION", path, "At least one path node is required")
	elseif count > MapContract.Limits.MAX_NODES_TOTAL then
		addIssue("OUT_OF_RANGE", path, "Path node collection exceeds the map-wide limit")
	end

	local output: { InternalNodePoint } = {}
	for _, member in canonicalMembers(folder, "PathNode", path) do
		local values, shellValid = validateMemberShell(member, "PathNode", expectedMapId)
		local laneId = values[MapContract.Attributes.LaneId]
		local order = values[MapContract.Attributes.NodeOrder]
		local expectedName = MapContract.formatMemberName("PathNode", laneId, order)
		local nameValid = validateExactName(member.node, expectedName, member.path)
		local point = if member.node.className == "Part"
			then pointMarkerSnapshot(member.node, member.path, false)
			else nil
		if shellValid and nameValid and type(laneId) == "string" and type(order) == "number" and point ~= nil then
			table.insert(output, {
				laneId = laneId,
				order = order,
				node = table.freeze({
					order = order,
					cframe = point.cframe,
					position = point.position,
				}),
				path = member.path,
			})
		end
	end
	return output
end

local function validateRegions(
	folder: InternalNode,
	role: "PlacementZone" | "NoPlacementZone",
	path: { Validation.PathSegment },
	expectedMapId: Ids.MapId
): { InternalRegion }
	validateFolder(folder, path)
	local minimum = if role == "PlacementZone"
		then MapContract.Limits.MIN_PLACEMENT_ZONES
		else MapContract.Limits.MIN_NO_PLACEMENT_ZONES
	local maximum = if role == "PlacementZone"
		then MapContract.Limits.MAX_PLACEMENT_ZONES
		else MapContract.Limits.MAX_NO_PLACEMENT_ZONES
	if #folder.children < minimum then
		addIssue("EMPTY_COLLECTION", path, "Required map region collection is empty")
	elseif #folder.children > maximum then
		addIssue("OUT_OF_RANGE", path, "Map region collection exceeds its fixed limit")
	end

	local output: { InternalRegion } = {}
	for _, member in canonicalMembers(folder, role, path) do
		local values, shellValid = validateMemberShell(member, role, expectedMapId)
		local id = values[MapContract.Attributes.ZoneId]
		local expectedName = MapContract.formatMemberName(role, id, nil)
		local nameValid = validateExactName(member.node, expectedName, member.path)
		local cframe: CFrame? = nil
		local size: Vector3? = nil
		if member.node.className == "Part" then
			cframe, size = regionGeometry(member.node, member.path, MapContract.Limits.MIN_PART_SIZE)
		end
		if shellValid and nameValid and type(id) == "string" and cframe ~= nil and size ~= nil then
			table.insert(output, {
				region = table.freeze({
					id = id,
					cframe = cframe,
					size = size,
				}),
				path = member.path,
			})
		end
	end
	return output
end

local function validateNamedPoints(
	folder: InternalNode,
	role: "CameraAnchor" | "PlayerSpawn",
	path: { Validation.PathSegment },
	expectedMapId: Ids.MapId
): { InternalNamedPoint }
	validateFolder(folder, path)
	local minimum = if role == "CameraAnchor"
		then MapContract.Limits.MIN_CAMERA_ANCHORS
		else MapContract.Limits.MIN_PLAYER_SPAWNS
	local maximum = if role == "CameraAnchor"
		then MapContract.Limits.MAX_CAMERA_ANCHORS
		else MapContract.Limits.MAX_PLAYER_SPAWNS
	if #folder.children < minimum then
		addIssue("EMPTY_COLLECTION", path, "Required named point collection is empty")
	elseif #folder.children > maximum then
		addIssue("OUT_OF_RANGE", path, "Named point collection exceeds its fixed limit")
	end

	local output: { InternalNamedPoint } = {}
	for _, member in canonicalMembers(folder, role, path) do
		local values, shellValid = validateMemberShell(member, role, expectedMapId)
		local attributeName = if role == "CameraAnchor"
			then MapContract.Attributes.AnchorId
			else MapContract.Attributes.SpawnId
		local id = values[attributeName]
		local expectedName = MapContract.formatMemberName(role, id, nil)
		local nameValid = validateExactName(member.node, expectedName, member.path)
		local point = if member.node.className == (if role == "CameraAnchor" then "Part" else "SpawnLocation")
			then pointMarkerSnapshot(member.node, member.path, role == "PlayerSpawn")
			else nil
		if shellValid and nameValid and type(id) == "string" and point ~= nil then
			table.insert(output, {
				id = id,
				point = table.freeze({
					id = id,
					cframe = point.cframe,
					position = point.position,
				}),
				path = member.path,
			})
		end
	end
	return output
end

local function validateSingletonPoint(
	node: InternalNode,
	role: "DefenderBase",
	path: { Validation.PathSegment },
	expectedMapId: Ids.MapId
): InternalPoint?
	local values, shellValid = validateMemberShell({
		node = node,
		path = path,
		key = node.structuralKey,
	}, role, expectedMapId)
	local _ = values
	local nameValid = validateExactName(node, MapContract.formatMemberName(role, nil, nil), path)
	local point = if node.className == "Part" then pointMarkerSnapshot(node, path, false) else nil
	if shellValid and nameValid and point ~= nil then
		return {
			point = point,
			path = path,
		}
	end
	return nil
end

local function validateBounds(
	node: InternalNode,
	path: { Validation.PathSegment },
	expectedMapId: Ids.MapId
): { cframe: CFrame, size: Vector3 }?
	local values, shellValid = validateMemberShell({
		node = node,
		path = path,
		key = node.structuralKey,
	}, "MapBounds", expectedMapId)
	local _ = values
	local nameValid = validateExactName(node, MapContract.formatMemberName("MapBounds", nil, nil), path)
	local cframe: CFrame? = nil
	local size: Vector3? = nil
	if node.className == "Part" then
		cframe, size = regionGeometry(node, path, MapContract.Limits.MIN_MAP_BOUNDS_SIZE)
	end
	if shellValid and nameValid and cframe ~= nil and size ~= nil then
		return table.freeze({
			cframe = cframe,
			size = size,
		})
	end
	return nil
end

local function sortSpawns(values: { InternalSpawn })
	table.sort(values, function(left, right)
		if left.laneId ~= right.laneId then
			return left.laneId < right.laneId
		end
		return Validation.renderPath(left.path) < Validation.renderPath(right.path)
	end)
end

local function sortNodePoints(values: { InternalNodePoint })
	table.sort(values, function(left, right)
		if left.laneId ~= right.laneId then
			return left.laneId < right.laneId
		elseif left.order ~= right.order then
			return left.order < right.order
		end
		return Validation.renderPath(left.path) < Validation.renderPath(right.path)
	end)
end

local function sortRegions(values: { InternalRegion })
	table.sort(values, function(left, right)
		if left.region.id ~= right.region.id then
			return left.region.id < right.region.id
		end
		return Validation.renderPath(left.path) < Validation.renderPath(right.path)
	end)
end

local function sortNamedPoints(values: { InternalNamedPoint })
	table.sort(values, function(left, right)
		if left.id ~= right.id then
			return left.id < right.id
		end
		return Validation.renderPath(left.path) < Validation.renderPath(right.path)
	end)
end

local function rejectDuplicateSpawnIds(values: { InternalSpawn }): { InternalSpawn }
	sortSpawns(values)
	local output: { InternalSpawn } = {}
	local index = 1
	while index <= #values do
		local last = index
		while last + 1 <= #values and values[last + 1].laneId == values[index].laneId do
			last += 1
		end
		if last == index then
			table.insert(output, values[index])
		else
			for duplicateIndex = index + 1, last do
				addRelatedIssue(
					"DUPLICATE_ID",
					pathWith(values[duplicateIndex].path, MapContract.Attributes.LaneId),
					"Enemy spawn LaneId must be unique",
					pathWith(values[index].path, MapContract.Attributes.LaneId)
				)
			end
		end
		index = last + 1
	end
	return output
end

local function rejectDuplicateRegionIds(values: { InternalRegion }): { InternalRegion }
	sortRegions(values)
	local output: { InternalRegion } = {}
	local index = 1
	while index <= #values do
		local last = index
		while last + 1 <= #values and values[last + 1].region.id == values[index].region.id do
			last += 1
		end
		if last == index then
			table.insert(output, values[index])
		else
			for duplicateIndex = index + 1, last do
				addRelatedIssue(
					"DUPLICATE_ID",
					pathWith(values[duplicateIndex].path, MapContract.Attributes.ZoneId),
					"Map region ZoneId must be unique in its role",
					pathWith(values[index].path, MapContract.Attributes.ZoneId)
				)
			end
		end
		index = last + 1
	end
	return output
end

local function rejectDuplicateNamedPointIds(
	values: { InternalNamedPoint },
	attributeName: string
): { InternalNamedPoint }
	sortNamedPoints(values)
	local output: { InternalNamedPoint } = {}
	local index = 1
	while index <= #values do
		local last = index
		while last + 1 <= #values and values[last + 1].id == values[index].id do
			last += 1
		end
		if last == index then
			table.insert(output, values[index])
		else
			for duplicateIndex = index + 1, last do
				addRelatedIssue(
					"DUPLICATE_ID",
					pathWith(values[duplicateIndex].path, attributeName),
					"Named point identity must be unique in its role",
					pathWith(values[index].path, attributeName)
				)
			end
		end
		index = last + 1
	end
	return output
end

local function pointInsideBox(point: Vector3, boxCFrame: CFrame, boxSize: Vector3): boolean
	local localPoint = boxCFrame:PointToObjectSpace(point)
	local half = boxSize * 0.5
	local toleranceX = math.max(1, half.X) * MapContract.Limits.GEOMETRY_TOLERANCE
	local toleranceY = math.max(1, half.Y) * MapContract.Limits.GEOMETRY_TOLERANCE
	local toleranceZ = math.max(1, half.Z) * MapContract.Limits.GEOMETRY_TOLERANCE
	return math.abs(localPoint.X) <= half.X + toleranceX
		and math.abs(localPoint.Y) <= half.Y + toleranceY
		and math.abs(localPoint.Z) <= half.Z + toleranceZ
end

local function boxInsideBox(innerCFrame: CFrame, innerSize: Vector3, outerCFrame: CFrame, outerSize: Vector3): boolean
	local half = innerSize * 0.5
	for xIndex = -1, 1, 2 do
		for yIndex = -1, 1, 2 do
			for zIndex = -1, 1, 2 do
				local localCorner = Vector3.new(half.X * xIndex, half.Y * yIndex, half.Z * zIndex)
				local worldCorner = innerCFrame:PointToWorldSpace(localCorner)
				if not pointInsideBox(worldCorner, outerCFrame, outerSize) then
					return false
				end
			end
		end
	end
	return true
end

local function regionsOverlap(left: RegionSnapshot, right: RegionSnapshot): boolean
	local leftCenter = left.cframe.Position
	local rightCenter = right.cframe.Position
	local leftHalf = left.size * 0.5
	local rightHalf = right.size * 0.5
	local tolerance = MapContract.Limits.GEOMETRY_TOLERANCE

	local overlapX = math.min(leftCenter.X + leftHalf.X, rightCenter.X + rightHalf.X)
		- math.max(leftCenter.X - leftHalf.X, rightCenter.X - rightHalf.X)
	local overlapY = math.min(leftCenter.Y + leftHalf.Y, rightCenter.Y + rightHalf.Y)
		- math.max(leftCenter.Y - leftHalf.Y, rightCenter.Y - rightHalf.Y)
	local overlapZ = math.min(leftCenter.Z + leftHalf.Z, rightCenter.Z + rightHalf.Z)
		- math.max(leftCenter.Z - leftHalf.Z, rightCenter.Z - rightHalf.Z)

	return overlapX > math.max(1, leftHalf.X, rightHalf.X) * tolerance
		and overlapY > math.max(1, leftHalf.Y, rightHalf.Y) * tolerance
		and overlapZ > math.max(1, leftHalf.Z, rightHalf.Z) * tolerance
end

local function validateUniqueRegionOverlaps(values: { InternalRegion })
	for leftIndex = 1, #values do
		for rightIndex = leftIndex + 1, #values do
			if regionsOverlap(values[leftIndex].region, values[rightIndex].region) then
				addRelatedIssue(
					"DUPLICATE_VALUE",
					pathWith(values[rightIndex].path, "CFrame"),
					"Map regions in the same role may not overlap with positive volume",
					pathWith(values[leftIndex].path, "CFrame")
				)
			end
		end
	end
end

local function validateBoundsContainment(
	bounds: { cframe: CFrame, size: Vector3 },
	base: InternalPoint?,
	spawns: { InternalSpawn },
	nodes: { InternalNodePoint },
	placementZones: { InternalRegion },
	noPlacementZones: { InternalRegion },
	cameraAnchors: { InternalNamedPoint },
	playerSpawns: { InternalNamedPoint },
	geometryParts: { { cframe: CFrame, size: Vector3, path: { Validation.PathSegment } } }
)
	local function requirePoint(point: PointSnapshot, path: { Validation.PathSegment })
		if not pointInsideBox(point.position, bounds.cframe, bounds.size) then
			addIssue("INVALID_REFERENCE", pathWith(path, "CFrame"), "Point marker must lie inside MapBounds")
		end
	end
	if base ~= nil then
		requirePoint(base.point, base.path)
	end
	for _, spawn in spawns do
		requirePoint(spawn.point, spawn.path)
	end
	for _, node in nodes do
		requirePoint({ cframe = node.node.cframe, position = node.node.position }, node.path)
	end
	for _, anchor in cameraAnchors do
		requirePoint({ cframe = anchor.point.cframe, position = anchor.point.position }, anchor.path)
	end
	for _, spawn in playerSpawns do
		requirePoint({ cframe = spawn.point.cframe, position = spawn.point.position }, spawn.path)
	end

	for _, region in placementZones do
		if not boxInsideBox(region.region.cframe, region.region.size, bounds.cframe, bounds.size) then
			addIssue(
				"INVALID_REFERENCE",
				pathWith(region.path, "CFrame"),
				"Placement zone must be wholly inside MapBounds"
			)
		end
	end
	for _, region in noPlacementZones do
		if not boxInsideBox(region.region.cframe, region.region.size, bounds.cframe, bounds.size) then
			addIssue(
				"INVALID_REFERENCE",
				pathWith(region.path, "CFrame"),
				"No-placement zone must be wholly inside MapBounds"
			)
		end
	end
	for _, part in geometryParts do
		if not boxInsideBox(part.cframe, part.size, bounds.cframe, bounds.size) then
			addIssue(
				"INVALID_REFERENCE",
				pathWith(part.path, "CFrame"),
				"Geometry BasePart must be wholly inside MapBounds"
			)
		end
	end
end

local function validateNoPlacementContainment(placementZones: { InternalRegion }, noPlacementZones: { InternalRegion })
	for _, noPlacement in noPlacementZones do
		local containing: { InternalRegion } = {}
		for _, placement in placementZones do
			if
				boxInsideBox(
					noPlacement.region.cframe,
					noPlacement.region.size,
					placement.region.cframe,
					placement.region.size
				)
			then
				table.insert(containing, placement)
			end
		end
		if #containing == 0 then
			addIssue(
				"INVALID_REFERENCE",
				pathWith(noPlacement.path, "CFrame"),
				"No-placement zone must be wholly contained by one placement zone"
			)
		elseif #containing > 1 then
			addRelatedIssue(
				"DUPLICATE_VALUE",
				pathWith(noPlacement.path, "CFrame"),
				"No-placement zone must be contained by exactly one placement zone",
				pathWith(containing[1].path, "CFrame")
			)
		end
	end
end

local function buildLanes(
	spawns: { InternalSpawn },
	nodes: { InternalNodePoint },
	base: InternalPoint?
): { LaneSnapshot }
	local spawnByLane: { [string]: InternalSpawn } = {}
	for _, spawn in spawns do
		spawnByLane[spawn.laneId] = spawn
	end

	local nodesByLane: { [string]: { InternalNodePoint } } = {}
	for _, node in nodes do
		local laneNodes = nodesByLane[node.laneId]
		if laneNodes == nil then
			laneNodes = {}
			nodesByLane[node.laneId] = laneNodes
		end
		table.insert(laneNodes, node)
		if spawnByLane[node.laneId] == nil then
			addIssue(
				"INVALID_REFERENCE",
				pathWith(node.path, MapContract.Attributes.LaneId),
				"Path node LaneId does not resolve to one enemy spawn"
			)
		end
	end

	local output: { LaneSnapshot } = {}
	for laneIndex, spawn in spawns do
		local lanePath = { "Map", "lanes", laneIndex }
		local laneNodes = nodesByLane[spawn.laneId] or {}
		sortNodePoints(laneNodes)
		local laneValid = true
		if #laneNodes < MapContract.Limits.MIN_NODES_PER_LANE then
			addIssue("OUT_OF_RANGE", { "Map", "Markers", "PathNodes" }, "Every lane requires at least one path node")
			laneValid = false
		elseif #laneNodes > MapContract.Limits.MAX_NODES_PER_LANE then
			addIssue("OUT_OF_RANGE", lanePath, "Lane exceeds its path-node limit")
			laneValid = false
		end

		local previousOrder: number? = nil
		for index, node in laneNodes do
			if previousOrder ~= nil and node.order == previousOrder then
				addRelatedIssue(
					"DUPLICATE_VALUE",
					pathWith(node.path, MapContract.Attributes.NodeOrder),
					"NodeOrder must be unique within its lane",
					pathWith(laneNodes[index - 1].path, MapContract.Attributes.NodeOrder)
				)
				laneValid = false
			end
			if node.order ~= index then
				addIssue(
					"INVALID_ORDER",
					pathWith(node.path, MapContract.Attributes.NodeOrder),
					"Lane NodeOrder values must be contiguous starting at one"
				)
				laneValid = false
			end
			previousOrder = node.order
		end

		if base ~= nil and #laneNodes > 0 then
			local routePositions: { Vector3 } = table.create(#laneNodes + 2)
			local routePaths: { { Validation.PathSegment } } = table.create(#laneNodes + 2)
			table.insert(routePositions, spawn.point.position)
			table.insert(routePaths, spawn.path)
			for _, node in laneNodes do
				table.insert(routePositions, node.node.position)
				table.insert(routePaths, node.path)
			end
			table.insert(routePositions, base.point.position)
			table.insert(routePaths, base.path)

			local totalDistance = 0
			for index = 2, #routePositions do
				local distance = (routePositions[index] - routePositions[index - 1]).Magnitude
				if not Validation.isFiniteNumber(distance) then
					addIssue("NON_FINITE_NUMBER", pathWith(lanePath, "segments"), "Lane segment length must be finite")
					laneValid = false
				elseif distance < MapContract.Limits.MIN_SEGMENT_LENGTH then
					addRelatedIssue(
						"OUT_OF_RANGE",
						pathWith(pathWith(lanePath, "segments"), index - 1),
						"Lane segment is zero-length under the map contract",
						routePaths[index - 1]
					)
					laneValid = false
				elseif distance > MapContract.Limits.MAX_SEGMENT_LENGTH then
					addRelatedIssue(
						"INVALID_REFERENCE",
						pathWith(pathWith(lanePath, "segments"), index - 1),
						"Lane segment exceeds the connectivity limit",
						routePaths[index - 1]
					)
					laneValid = false
				end
				totalDistance += distance
			end
			if not Validation.isFiniteNumber(totalDistance) or totalDistance > MapContract.Limits.MAX_LANE_LENGTH then
				addIssue(
					"OUT_OF_RANGE",
					pathWith(lanePath, "totalDistance"),
					"Lane total distance exceeds its fixed limit"
				)
				laneValid = false
			end
		end

		if laneValid and base ~= nil then
			local frozenNodes: { NodeSnapshot } = table.create(#laneNodes)
			for _, node in laneNodes do
				table.insert(frozenNodes, node.node)
			end
			table.insert(
				output,
				table.freeze({
					id = spawn.laneId,
					spawn = spawn.point,
					nodes = table.freeze(frozenNodes),
				})
			)
		end
	end
	return output
end

local function frozenRegionArray(values: { InternalRegion }): { RegionSnapshot }
	local output: { RegionSnapshot } = table.create(#values)
	for _, value in values do
		table.insert(output, value.region)
	end
	return table.freeze(output)
end

local function frozenNamedPointArray(values: { InternalNamedPoint }): { NamedPointSnapshot }
	local output: { NamedPointSnapshot } = table.create(#values)
	for _, value in values do
		table.insert(output, value.point)
	end
	return table.freeze(output)
end

local MapValidator = {}

function MapValidator.validate(
	candidate: unknown,
	expectedMapIdValue: unknown
): Result.Result<ValidatedMapSnapshot, MapValidationReport>
	issues = {}

	local expectedMapIdResult = Ids.validateMapId(expectedMapIdValue)
	if not expectedMapIdResult.ok then
		table.insert(
			issues,
			Validation.issueWithCause(
				"INVALID_ID",
				{ "Map", MapContract.Attributes.MapId },
				"Server-selected MapId is invalid",
				expectedMapIdResult.error.code
			)
		)
		return failure()
	end
	local expectedMapId = expectedMapIdResult.value

	if typeof(candidate) ~= "Instance" then
		addTypeIssue("INVALID_TYPE", ROOT_PATH, "Map candidate must be an Instance", candidate)
		return failure()
	end
	local rootInstance = candidate :: Instance
	if not rootInstance:IsA("Model") then
		addIssue("INVALID_TYPE", pathWith(ROOT_PATH, "ClassName"), "Map root must be a Model")
		return failure()
	end

	local root, discovery = discover(rootInstance)
	if discovery.limitPath ~= nil then
		issues = {}
		local limitPath = if discovery.limitPath == "Map.metadata"
			then { "Map", "metadata" }
			else { "Map", "traversal" }
		addIssue("OUT_OF_RANGE", limitPath, "Map exceeds a fixed bounded-validation limit")
		return failure()
	end
	if root == nil then
		addIssue("INVALID_TYPE", ROOT_PATH, "Map root could not be inspected")
		return failure()
	end
	if discovery.descendants < MapContract.Limits.MIN_DESCENDANTS then
		addIssue("OUT_OF_RANGE", { "Map", "traversal" }, "Map has fewer descendants than the contract minimum")
	end

	validateGlobalNode(root, root, ROOT_PATH)
	validateClass(root, "Model", ROOT_PATH)
	local rootValues = validateRoleMetadata(root, "MapRoot", ROOT_PATH, expectedMapId)
	local mapId = rootValues[MapContract.Attributes.MapId]
	validateExactName(root, MapContract.formatMapName(mapId), ROOT_PATH)

	local rootAllowed = table.freeze({
		[MapContract.Names.Geometry] = true,
		[MapContract.Names.Markers] = true,
	})
	rejectUnexpectedChildren(root, rootAllowed, ROOT_PATH)
	local geometryPath = { "Map", MapContract.Names.Geometry }
	local markersPath = { "Map", MapContract.Names.Markers }
	local geometry = findExactChild(root, MapContract.Names.Geometry, geometryPath)
	local markers = findExactChild(root, MapContract.Names.Markers, markersPath)

	local geometryParts: { { cframe: CFrame, size: Vector3, path: { Validation.PathSegment } } } = {}
	if geometry ~= nil then
		geometryParts = validateGeometry(geometry, geometryPath)
	end

	local base: InternalPoint? = nil
	local bounds: { cframe: CFrame, size: Vector3 }? = nil
	local spawns: { InternalSpawn } = {}
	local nodes: { InternalNodePoint } = {}
	local placementZones: { InternalRegion } = {}
	local noPlacementZones: { InternalRegion } = {}
	local cameraAnchors: { InternalNamedPoint } = {}
	local playerSpawns: { InternalNamedPoint } = {}

	if markers ~= nil then
		validateFolder(markers, markersPath)
		local names = MapContract.Names
		local markerAllowed = table.freeze({
			[names.EnemySpawns] = true,
			[names.PathNodes] = true,
			[names.DefenderBase] = true,
			[names.PlacementZones] = true,
			[names.NoPlacementZones] = true,
			[names.MapBounds] = true,
			[names.CameraAnchors] = true,
			[names.PlayerSpawns] = true,
		})
		rejectUnexpectedChildren(markers, markerAllowed, markersPath)

		local enemySpawnsPath = { "Map", "Markers", names.EnemySpawns }
		local pathNodesPath = { "Map", "Markers", names.PathNodes }
		local defenderBasePath = { "Map", "Markers", names.DefenderBase }
		local placementPath = { "Map", "Markers", names.PlacementZones }
		local noPlacementPath = { "Map", "Markers", names.NoPlacementZones }
		local boundsPath = { "Map", "Markers", names.MapBounds }
		local cameraPath = { "Map", "Markers", names.CameraAnchors }
		local playerPath = { "Map", "Markers", names.PlayerSpawns }

		local enemyFolder = findExactChild(markers, names.EnemySpawns, enemySpawnsPath)
		local nodesFolder = findExactChild(markers, names.PathNodes, pathNodesPath)
		local baseNode = findExactChild(markers, names.DefenderBase, defenderBasePath)
		local placementFolder = findExactChild(markers, names.PlacementZones, placementPath)
		local noPlacementFolder = findExactChild(markers, names.NoPlacementZones, noPlacementPath)
		local boundsNode = findExactChild(markers, names.MapBounds, boundsPath)
		local cameraFolder = findExactChild(markers, names.CameraAnchors, cameraPath)
		local playerFolder = findExactChild(markers, names.PlayerSpawns, playerPath)

		if enemyFolder ~= nil then
			spawns = validateEnemySpawns(enemyFolder, enemySpawnsPath, expectedMapId)
		end
		if nodesFolder ~= nil then
			nodes = validatePathNodes(nodesFolder, pathNodesPath, expectedMapId)
		end
		if baseNode ~= nil then
			base = validateSingletonPoint(baseNode, "DefenderBase", defenderBasePath, expectedMapId)
		end
		if placementFolder ~= nil then
			placementZones = validateRegions(placementFolder, "PlacementZone", placementPath, expectedMapId)
		end
		if noPlacementFolder ~= nil then
			noPlacementZones = validateRegions(noPlacementFolder, "NoPlacementZone", noPlacementPath, expectedMapId)
		end
		if boundsNode ~= nil then
			bounds = validateBounds(boundsNode, boundsPath, expectedMapId)
		end
		if cameraFolder ~= nil then
			cameraAnchors = validateNamedPoints(cameraFolder, "CameraAnchor", cameraPath, expectedMapId)
		end
		if playerFolder ~= nil then
			playerSpawns = validateNamedPoints(playerFolder, "PlayerSpawn", playerPath, expectedMapId)
		end
	end

	spawns = rejectDuplicateSpawnIds(spawns)
	placementZones = rejectDuplicateRegionIds(placementZones)
	noPlacementZones = rejectDuplicateRegionIds(noPlacementZones)
	cameraAnchors = rejectDuplicateNamedPointIds(cameraAnchors, MapContract.Attributes.AnchorId)
	playerSpawns = rejectDuplicateNamedPointIds(playerSpawns, MapContract.Attributes.SpawnId)
	sortNodePoints(nodes)

	validateUniqueRegionOverlaps(placementZones)
	validateUniqueRegionOverlaps(noPlacementZones)
	validateNoPlacementContainment(placementZones, noPlacementZones)
	if bounds ~= nil then
		validateBoundsContainment(
			bounds,
			base,
			spawns,
			nodes,
			placementZones,
			noPlacementZones,
			cameraAnchors,
			playerSpawns,
			geometryParts
		)
	end

	local lanes = buildLanes(spawns, nodes, base)
	if #issues > 0 or type(mapId) ~= "string" or base == nil or bounds == nil then
		return failure()
	end

	return Result.ok(table.freeze({
		mapId = mapId,
		base = base.point,
		bounds = bounds,
		lanes = table.freeze(lanes),
		placementZones = frozenRegionArray(placementZones),
		noPlacementZones = frozenRegionArray(noPlacementZones),
		cameraAnchors = frozenNamedPointArray(cameraAnchors),
		playerSpawns = frozenNamedPointArray(playerSpawns),
	}))
end

return table.freeze(MapValidator)
