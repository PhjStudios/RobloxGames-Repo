--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type RoutePointKind = "EnemySpawn" | "PathNode" | "DefenderBase"

export type RoutePointSnapshot = {
	kind: RoutePointKind,
	nodeOrder: number?,
	cframe: CFrame,
	position: Vector3,
	distance: number,
}

export type RuntimeLaneSnapshot = {
	id: string,
	totalDistance: number,
	points: { RoutePointSnapshot },
}

export type Sample = {
	worldCFrame: CFrame,
	segmentIndex: number,
	segmentStartDistance: number,
	segmentEndDistance: number,
	segmentStartPosition: Vector3,
	segmentEndPosition: Vector3,
}

export type ErrorCode = "INVALID_LANE" | "INVALID_PROGRESS" | "OUT_OF_RANGE"

export type SampleError = {
	code: ErrorCode,
}

export type SampleResult = Result.Result<Sample, SampleError>

local MAX_ROUTE_POINTS = 258
local MAX_LANE_DISTANCE = 32_768
local MAX_SEGMENT_DISTANCE = 512
local MAX_COORDINATE = 100_000
local MIN_SEGMENT_DISTANCE = 0.01
local PARALLEL_TOLERANCE = 1e-6
local POSITION_TOLERANCE = 1e-6

local LANE_FIELDS: { [string]: boolean } = table.freeze({
	id = true,
	points = true,
	totalDistance = true,
})

local POINT_FIELDS: { [string]: boolean } = table.freeze({
	cframe = true,
	distance = true,
	kind = true,
	nodeOrder = true,
	position = true,
})

local EnemyPath = {
	MAX_ROUTE_POINTS = MAX_ROUTE_POINTS,
}

local function failure(code: ErrorCode): Result.Failure<SampleError>
	return Result.err(table.freeze({
		code = code,
	}))
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and Validation.isFiniteNumber(value)
end

local function isFiniteVector3(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local vector = value :: Vector3
	return isFiniteNumber(vector.X)
		and isFiniteNumber(vector.Y)
		and isFiniteNumber(vector.Z)
		and math.abs(vector.X) <= MAX_COORDINATE
		and math.abs(vector.Y) <= MAX_COORDINATE
		and math.abs(vector.Z) <= MAX_COORDINATE
end

local function isFiniteCFrame(value: unknown): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	for _, component in { (value :: CFrame):GetComponents() } do
		if not isFiniteNumber(component) then
			return false
		end
	end
	return true
end

local function hasExactFields(value: { [any]: unknown }, fields: { [string]: boolean }): boolean
	for key in next, value do
		if type(key) ~= "string" or fields[key] ~= true then
			return false
		end
	end
	for key in fields do
		if key ~= "nodeOrder" and value[key] == nil then
			return false
		end
	end
	return true
end

local function isDenseFrozenArray(value: unknown, minimum: number, maximum: number): boolean
	if type(value) ~= "table" or not table.isfrozen(value :: any) or getmetatable(value :: any) ~= nil then
		return false
	end
	local length = rawlen(value :: { unknown })
	if length < minimum or length > maximum then
		return false
	end
	local count = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return false
		end
		count += 1
	end
	return count == length
end

local function validateLane(value: unknown): RuntimeLaneSnapshot?
	if
		type(value) ~= "table"
		or not table.isfrozen(value :: any)
		or getmetatable(value :: any) ~= nil
		or not hasExactFields(value :: { [any]: unknown }, LANE_FIELDS)
	then
		return nil
	end

	local lane = value :: any
	if
		type(lane.id) ~= "string"
		or not Validation.isSymbolicKey(lane.id)
		or not isFiniteNumber(lane.totalDistance)
		or lane.totalDistance < MIN_SEGMENT_DISTANCE
		or lane.totalDistance > MAX_LANE_DISTANCE
		or not isDenseFrozenArray(lane.points, 2, MAX_ROUTE_POINTS)
	then
		return nil
	end

	local previousDistance = -math.huge
	local previousPosition: Vector3? = nil
	local distanceTolerance = math.max(1, lane.totalDistance) * 1e-9
	local points = lane.points :: { unknown }
	for index = 1, #points do
		local pointValue = points[index]
		if
			type(pointValue) ~= "table"
			or not table.isfrozen(pointValue :: any)
			or getmetatable(pointValue :: any) ~= nil
			or not hasExactFields(pointValue :: { [any]: unknown }, POINT_FIELDS)
		then
			return nil
		end

		local point = pointValue :: any
		local expectedKind = if index == 1 then "EnemySpawn" elseif index == #points then "DefenderBase" else "PathNode"
		local expectedNodeOrder = if expectedKind == "PathNode" then index - 1 else nil
		if
			point.kind ~= expectedKind
			or point.nodeOrder ~= expectedNodeOrder
			or not isFiniteVector3(point.position)
			or not isFiniteCFrame(point.cframe)
			or ((point.cframe :: CFrame).Position - (point.position :: Vector3)).Magnitude > POSITION_TOLERANCE
			or not isFiniteNumber(point.distance)
			or point.distance < 0
			or point.distance > lane.totalDistance
		then
			return nil
		end

		if index == 1 then
			if point.distance ~= 0 then
				return nil
			end
		else
			local segmentDistance = ((point.position :: Vector3) - (previousPosition :: Vector3)).Magnitude
			local cumulativeDelta = point.distance - previousDistance
			if
				not isFiniteNumber(segmentDistance)
				or segmentDistance < MIN_SEGMENT_DISTANCE
				or segmentDistance > MAX_SEGMENT_DISTANCE
				or cumulativeDelta < MIN_SEGMENT_DISTANCE
				or cumulativeDelta > MAX_SEGMENT_DISTANCE
				or math.abs(cumulativeDelta - segmentDistance) > distanceTolerance
			then
				return nil
			end
		end

		previousDistance = point.distance
		previousPosition = point.position
	end

	if math.abs(previousDistance - lane.totalDistance) > distanceTolerance then
		return nil
	end
	return value :: RuntimeLaneSnapshot
end

local function canonicalCFrame(position: Vector3, tangent: Vector3): CFrame
	local direction = tangent.Unit
	local upHint = Vector3.yAxis
	if math.abs(direction:Dot(upHint)) >= 1 - PARALLEL_TOLERANCE then
		upHint = Vector3.xAxis
	end
	local right = direction:Cross(upHint).Unit
	local up = right:Cross(direction).Unit
	return CFrame.fromMatrix(position, right, up, -direction)
end

local function canonicalizeProgress(lane: RuntimeLaneSnapshot, progress: number): number
	local tolerance = math.max(1, lane.totalDistance) * 1e-9
	if progress <= 0 then
		return 0
	elseif lane.totalDistance - progress <= tolerance then
		return lane.totalDistance
	end

	local points = lane.points
	local low = 2
	local high = #points - 1
	local nextBoundary: number? = nil
	while low <= high do
		local middle = math.floor((low + high) / 2)
		local distance = points[middle].distance
		if progress <= distance then
			nextBoundary = distance
			high = middle - 1
		else
			low = middle + 1
		end
	end
	if nextBoundary ~= nil and nextBoundary - progress <= tolerance then
		return nextBoundary
	end
	return progress
end

local function locateSegment(lane: RuntimeLaneSnapshot, progress: number): number
	local points = lane.points
	local lastIndex = #points
	if progress == lane.totalDistance then
		return lastIndex - 1
	end

	local low = 2
	local high = lastIndex
	while low < high do
		local middle = math.floor((low + high) / 2)
		if points[middle].distance <= progress then
			low = middle + 1
		else
			high = middle
		end
	end
	return low - 1
end

local function sampleComponents(
	lane: RuntimeLaneSnapshot,
	progress: number
): (CFrame, number, RoutePointSnapshot, RoutePointSnapshot)
	local segmentIndex = locateSegment(lane, progress)
	local segmentStart = lane.points[segmentIndex]
	local segmentEnd = lane.points[segmentIndex + 1]
	local position: Vector3
	if progress == segmentStart.distance then
		position = segmentStart.position
	elseif progress == segmentEnd.distance then
		position = segmentEnd.position
	else
		local alpha = (progress - segmentStart.distance) / (segmentEnd.distance - segmentStart.distance)
		position = segmentStart.position:Lerp(segmentEnd.position, alpha)
	end
	return canonicalCFrame(position, segmentEnd.position - segmentStart.position),
		segmentIndex,
		segmentStart,
		segmentEnd
end

function EnemyPath.sampleTrusted(lane: RuntimeLaneSnapshot, progress: number): (CFrame, number)
	local canonicalProgress = canonicalizeProgress(lane, progress)
	local worldCFrame, segmentIndex = sampleComponents(lane, canonicalProgress)
	return worldCFrame, segmentIndex
end

function EnemyPath.canonicalizeProgressTrusted(lane: RuntimeLaneSnapshot, progress: number): number
	return canonicalizeProgress(lane, progress)
end

function EnemyPath.sample(laneValue: unknown, progressValue: unknown): SampleResult
	local lane = validateLane(laneValue)
	if lane == nil then
		return failure("INVALID_LANE")
	end
	if not isFiniteNumber(progressValue) then
		return failure("INVALID_PROGRESS")
	end
	local progress = progressValue :: number
	if progress < 0 or progress > lane.totalDistance then
		return failure("OUT_OF_RANGE")
	end

	local canonicalProgress = canonicalizeProgress(lane, progress)
	local worldCFrame, segmentIndex, segmentStart, segmentEnd = sampleComponents(lane, canonicalProgress)
	return Result.ok(table.freeze({
		worldCFrame = worldCFrame,
		segmentIndex = segmentIndex,
		segmentStartDistance = segmentStart.distance,
		segmentEndDistance = segmentEnd.distance,
		segmentStartPosition = segmentStart.position,
		segmentEndPosition = segmentEnd.position,
	}))
end

return table.freeze(EnemyPath)
