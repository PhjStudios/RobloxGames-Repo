--!strict

local Validation = require(script.Parent.Parent.util.Validation)

export type SurfaceCategory = "Land" | "Elevated" | "Water"
export type InvalidReason = "InvalidPosition" | "InvalidSurface" | "OutsideZone" | "Excluded" | "Occupied"

export type Bounds = {
	cframe: CFrame,
	size: Vector3,
}

export type PlacementZone = {
	cframe: CFrame,
	size: Vector3,
	surfaceCategory: SurfaceCategory,
}

export type Exclusion = {
	cframe: CFrame,
	size: Vector3,
}

export type Evaluation = {
	valid: boolean,
	reason: "Valid" | InvalidReason,
	position: Vector3?,
	surfaceCategory: SurfaceCategory?,
	zoneIndex: number?,
}

local MAX_COORDINATE = 100_000
local MAX_RADIUS = 4_096
local ROTATION_TOLERANCE = 1e-6
local GEOMETRY_TOLERANCE = 1e-6

local SURFACE_CATEGORIES: { [string]: boolean } = table.freeze({
	Land = true,
	Elevated = true,
	Water = true,
})

local APPROVED_SURFACES: { [string]: boolean } = table.freeze({
	Land = true,
	Elevated = true,
})

local PlacementGeometry = {
	MAX_COORDINATE = MAX_COORDINATE,
	MAX_RADIUS = MAX_RADIUS,
	ROTATION_TOLERANCE = ROTATION_TOLERANCE,
	GEOMETRY_TOLERANCE = GEOMETRY_TOLERANCE,
}

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and Validation.isFiniteNumber(value :: number)
end

local function boundedCoordinate(value: unknown): boolean
	return isFiniteNumber(value) and math.abs(value :: number) <= MAX_COORDINATE
end

local function validSize(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local size = value :: Vector3
	return isFiniteNumber(size.X)
		and isFiniteNumber(size.Y)
		and isFiniteNumber(size.Z)
		and size.X > 0
		and size.Y > 0
		and size.Z > 0
		and size.X <= MAX_RADIUS * 2
		and size.Y <= MAX_RADIUS * 2
		and size.Z <= MAX_RADIUS * 2
end

local function validRadius(value: unknown): boolean
	return isFiniteNumber(value) and (value :: number) > 0 and (value :: number) <= MAX_RADIUS
end

local function validPositionXZ(value: unknown): boolean
	if typeof(value) ~= "Vector2" then
		return false
	end
	local position = value :: Vector2
	return boundedCoordinate(position.X) and boundedCoordinate(position.Y)
end

local function finiteCFrame(value: unknown): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	local components = table.pack((value :: CFrame):GetComponents())
	if components.n ~= 12 then
		return false
	end
	for index = 1, components.n do
		if not isFiniteNumber(rawget(components, index)) then
			return false
		end
	end
	return boundedCoordinate(rawget(components, 1))
		and boundedCoordinate(rawget(components, 2))
		and boundedCoordinate(rawget(components, 3))
end

local function approximately(value: number, expected: number): boolean
	return math.abs(value - expected) <= ROTATION_TOLERANCE
end

local function validRegion(region: unknown, requireSurface: boolean): boolean
	if type(region) ~= "table" then
		return false
	end
	local record = region :: any
	if not PlacementGeometry.isUprightYawCFrame(record.cframe) or not validSize(record.size) then
		return false
	end
	if requireSurface and not PlacementGeometry.isSurfaceCategory(record.surfaceCategory) then
		return false
	end
	return true
end

local function geometryTolerance(radius: number, halfX: number, halfZ: number): number
	return math.max(1, radius, halfX, halfZ) * GEOMETRY_TOLERANCE
end

local function localXZ(positionXZ: Vector2, cframe: CFrame): Vector2
	local localPoint = cframe:PointToObjectSpace(Vector3.new(positionXZ.X, cframe.Position.Y, positionXZ.Y))
	return Vector2.new(localPoint.X, localPoint.Z)
end

local function invalid(reason: InvalidReason): Evaluation
	return table.freeze({
		valid = false,
		reason = reason,
		position = nil,
		surfaceCategory = nil,
		zoneIndex = nil,
	})
end

function PlacementGeometry.isSurfaceCategory(value: unknown): boolean
	return type(value) == "string" and SURFACE_CATEGORIES[value :: string] == true
end

function PlacementGeometry.isApprovedSurface(value: unknown): boolean
	return type(value) == "string" and APPROVED_SURFACES[value :: string] == true
end

function PlacementGeometry.isUprightYawCFrame(value: unknown): boolean
	if not finiteCFrame(value) then
		return false
	end
	local cframe = value :: CFrame
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cframe:GetComponents()
	if
		not approximately(r01, 0)
		or not approximately(r10, 0)
		or not approximately(r11, 1)
		or not approximately(r12, 0)
		or not approximately(r21, 0)
	then
		return false
	end
	local firstLength = r00 * r00 + r02 * r02
	local secondLength = r20 * r20 + r22 * r22
	local dot = r00 * r20 + r02 * r22
	local determinant = r00 * r22 - r02 * r20
	return approximately(firstLength, 1)
		and approximately(secondLength, 1)
		and approximately(dot, 0)
		and approximately(determinant, 1)
end

function PlacementGeometry.normalizeYawDegrees(value: unknown): number?
	if not isFiniteNumber(value) or (value :: number) < -360 or (value :: number) > 360 then
		return nil
	end
	local normalized = (value :: number) % 360
	if normalized < 0 then
		normalized += 360
	end
	return if normalized == 0 then 0 else normalized
end

function PlacementGeometry.groundHeight(region: unknown): number?
	if not validRegion(region, false) then
		return nil
	end
	local record = region :: any
	local height = record.cframe.Position.Y + record.size.Y * 0.5
	return if boundedCoordinate(height) then height else nil
end

function PlacementGeometry.circleInsideRegion(positionXZValue: unknown, radiusValue: unknown, region: unknown): boolean
	if not validPositionXZ(positionXZValue) or not validRadius(radiusValue) or not validRegion(region, false) then
		return false
	end
	local positionXZ = positionXZValue :: Vector2
	local radius = radiusValue :: number
	local record = region :: any
	local half = record.size * 0.5
	local point = localXZ(positionXZ, record.cframe)
	local tolerance = geometryTolerance(radius, half.X, half.Z)
	return math.abs(point.X) + radius <= half.X + tolerance and math.abs(point.Y) + radius <= half.Z + tolerance
end

function PlacementGeometry.circleIntersectsRegion(
	positionXZValue: unknown,
	radiusValue: unknown,
	region: unknown
): boolean
	if not validPositionXZ(positionXZValue) or not validRadius(radiusValue) or not validRegion(region, false) then
		return true
	end
	local positionXZ = positionXZValue :: Vector2
	local radius = radiusValue :: number
	local record = region :: any
	local half = record.size * 0.5
	local point = localXZ(positionXZ, record.cframe)
	local outsideX = math.max(math.abs(point.X) - half.X, 0)
	local outsideZ = math.max(math.abs(point.Y) - half.Z, 0)
	local distanceSquared = outsideX * outsideX + outsideZ * outsideZ
	local tolerance = geometryTolerance(radius, half.X, half.Z)
	local positiveRadius = math.max(0, radius - tolerance)
	return distanceSquared < positiveRadius * positiveRadius
end

function PlacementGeometry.circlesOverlap(
	leftPositionValue: unknown,
	leftRadiusValue: unknown,
	rightPositionValue: unknown,
	rightRadiusValue: unknown
): boolean
	if
		not validPositionXZ(leftPositionValue)
		or not validPositionXZ(rightPositionValue)
		or not validRadius(leftRadiusValue)
		or not validRadius(rightRadiusValue)
	then
		return true
	end
	local left = leftPositionValue :: Vector2
	local right = rightPositionValue :: Vector2
	local leftRadius = leftRadiusValue :: number
	local rightRadius = rightRadiusValue :: number
	local delta = left - right
	local combined = leftRadius + rightRadius
	local tolerance = math.max(1, leftRadius, rightRadius, combined) * GEOMETRY_TOLERANCE
	local positiveCombined = math.max(0, combined - tolerance)
	return delta:Dot(delta) < positiveCombined * positiveCombined
end

function PlacementGeometry.decodeFootprint(value: unknown): (Vector2?, number?)
	if typeof(value) ~= "Vector3" then
		return nil, nil
	end
	local footprint = value :: Vector3
	if not boundedCoordinate(footprint.X) or not validRadius(footprint.Y) or not boundedCoordinate(footprint.Z) then
		return nil, nil
	end
	return Vector2.new(footprint.X, footprint.Z), footprint.Y
end

function PlacementGeometry.encodeFootprint(positionXZValue: unknown, radiusValue: unknown): Vector3?
	if not validPositionXZ(positionXZValue) or not validRadius(radiusValue) then
		return nil
	end
	local position = positionXZValue :: Vector2
	return Vector3.new(position.X, radiusValue :: number, position.Y)
end

function PlacementGeometry.evaluate(
	positionXZValue: unknown,
	radiusValue: unknown,
	boundsValue: unknown,
	placementZonesValue: unknown,
	exclusionsValue: unknown,
	footprintsValue: unknown
): Evaluation
	if
		not validPositionXZ(positionXZValue)
		or not validRadius(radiusValue)
		or not validRegion(boundsValue, false)
		or type(placementZonesValue) ~= "table"
		or type(exclusionsValue) ~= "table"
		or type(footprintsValue) ~= "table"
	then
		return invalid("InvalidPosition")
	end
	local positionXZ = positionXZValue :: Vector2
	local radius = radiusValue :: number
	local placementZones = placementZonesValue :: { PlacementZone }
	local exclusions = exclusionsValue :: { Exclusion }
	local footprints = footprintsValue :: { Vector3 }

	if not PlacementGeometry.circleInsideRegion(positionXZ, radius, boundsValue) then
		return invalid("InvalidPosition")
	end

	local selectedZone: PlacementZone? = nil
	local selectedIndex: number? = nil
	for index, zone in placementZones do
		if not validRegion(zone, true) then
			return invalid("InvalidPosition")
		end
		if PlacementGeometry.circleInsideRegion(positionXZ, radius, zone) then
			if selectedZone ~= nil then
				return invalid("OutsideZone")
			end
			selectedZone = zone
			selectedIndex = index
		end
	end
	if selectedZone == nil then
		return invalid("OutsideZone")
	end
	if not PlacementGeometry.isApprovedSurface(selectedZone.surfaceCategory) then
		return invalid("InvalidSurface")
	end

	for _, exclusion in exclusions do
		if not validRegion(exclusion, false) then
			return invalid("InvalidPosition")
		end
		if PlacementGeometry.circleIntersectsRegion(positionXZ, radius, exclusion) then
			return invalid("Excluded")
		end
	end

	for _, footprint in footprints do
		local existingPosition, existingRadius = PlacementGeometry.decodeFootprint(footprint)
		if existingPosition == nil or existingRadius == nil then
			return invalid("InvalidPosition")
		end
		if PlacementGeometry.circlesOverlap(positionXZ, radius, existingPosition, existingRadius) then
			return invalid("Occupied")
		end
	end

	local height = PlacementGeometry.groundHeight(selectedZone)
	if height == nil then
		return invalid("InvalidPosition")
	end
	return table.freeze({
		valid = true,
		reason = "Valid",
		position = Vector3.new(positionXZ.X, height, positionXZ.Y),
		surfaceCategory = selectedZone.surfaceCategory,
		zoneIndex = selectedIndex,
	})
end

return table.freeze(PlacementGeometry)
