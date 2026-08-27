--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type ErrorCode = "INVALID_SAMPLE" | "INVALID_TIME"

export type Error = {
	code: ErrorCode,
}

export type Sample = {
	worldCFrame: CFrame,
	pathProgress: number,
	extrapolated: boolean,
	snapped: boolean,
	segmentGap: boolean,
}

export type Correction = {
	mode: "Accept" | "Smooth" | "Snap",
	offset: Vector3,
	errorStuds: number,
}

local INTERPOLATION_DELAY_SECONDS = 0.15
local MAX_EXTRAPOLATION_SECONDS = 0.1
local SMOOTH_CORRECTION_SECONDS = 0.2
local CORRECTION_THRESHOLD_STUDS = 0.25
local SNAP_THRESHOLD_STUDS = 8
local DISTANCE_TOLERANCE = 1e-6
local PARALLEL_TOLERANCE = 1e-6

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_SAMPLE = table.freeze({ code = "INVALID_SAMPLE" :: "INVALID_SAMPLE" }),
	INVALID_TIME = table.freeze({ code = "INVALID_TIME" :: "INVALID_TIME" }),
})

local EnemyPresentation = {
	INTERPOLATION_DELAY_SECONDS = INTERPOLATION_DELAY_SECONDS,
	MAX_EXTRAPOLATION_SECONDS = MAX_EXTRAPOLATION_SECONDS,
	SMOOTH_CORRECTION_SECONDS = SMOOTH_CORRECTION_SECONDS,
	CORRECTION_THRESHOLD_STUDS = CORRECTION_THRESHOLD_STUDS,
	SNAP_THRESHOLD_STUDS = SNAP_THRESHOLD_STUDS,
}

local function failure(code: ErrorCode)
	return Result.err(ERRORS[code])
end

local function canonicalCFrame(position: Vector3, tangent: Vector3): CFrame?
	if tangent.Magnitude <= DISTANCE_TOLERANCE then
		return nil
	end
	local direction = tangent.Unit
	local upHint = Vector3.yAxis
	if math.abs(direction:Dot(upHint)) >= 1 - PARALLEL_TOLERANCE then
		upHint = Vector3.xAxis
	end
	local right = direction:Cross(upHint).Unit
	local up = right:Cross(direction).Unit
	return CFrame.fromMatrix(position, right, up, -direction)
end

local function isFiniteVector3(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local vector = value :: Vector3
	return Validation.isFiniteNumber(vector.X)
		and Validation.isFiniteNumber(vector.Y)
		and Validation.isFiniteNumber(vector.Z)
end

local function isFiniteCFrame(value: unknown): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	for _, component in { (value :: CFrame):GetComponents() } do
		if not Validation.isFiniteNumber(component) then
			return false
		end
	end
	return true
end

local function isUsableEntry(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local entry = value :: any
	return type(entry.runtimeEnemyId) == "number"
		and Validation.isSafeInteger(entry.runtimeEnemyId)
		and entry.runtimeEnemyId >= 1
		and type(entry.laneId) == "string"
		and type(entry.sampleServerTime) == "number"
		and Validation.isFiniteNumber(entry.sampleServerTime)
		and entry.sampleServerTime >= 0
		and type(entry.pathProgress) == "number"
		and Validation.isFiniteNumber(entry.pathProgress)
		and type(entry.effectiveSpeed) == "number"
		and Validation.isFiniteNumber(entry.effectiveSpeed)
		and entry.effectiveSpeed >= 0
		and type(entry.segmentStartDistance) == "number"
		and Validation.isFiniteNumber(entry.segmentStartDistance)
		and type(entry.segmentEndDistance) == "number"
		and Validation.isFiniteNumber(entry.segmentEndDistance)
		and entry.segmentEndDistance - entry.segmentStartDistance > DISTANCE_TOLERANCE
		and entry.pathProgress >= entry.segmentStartDistance - DISTANCE_TOLERANCE
		and entry.pathProgress <= entry.segmentEndDistance + DISTANCE_TOLERANCE
		and isFiniteVector3(entry.segmentStartPosition)
		and isFiniteVector3(entry.segmentEndPosition)
		and ((entry.segmentEndPosition :: Vector3) - (entry.segmentStartPosition :: Vector3)).Magnitude > DISTANCE_TOLERANCE
		and isFiniteCFrame(entry.worldCFrame)
end

local function sampleWindow(entry: any, progress: number): CFrame?
	if
		progress < entry.segmentStartDistance - DISTANCE_TOLERANCE
		or progress > entry.segmentEndDistance + DISTANCE_TOLERANCE
	then
		return nil
	end
	local clampedProgress = math.clamp(progress, entry.segmentStartDistance, entry.segmentEndDistance)
	local alpha = (clampedProgress - entry.segmentStartDistance)
		/ (entry.segmentEndDistance - entry.segmentStartDistance)
	local startPosition = entry.segmentStartPosition :: Vector3
	local endPosition = entry.segmentEndPosition :: Vector3
	return canonicalCFrame(startPosition:Lerp(endPosition, alpha), endPosition - startPosition)
end

local function makeSample(
	worldCFrame: CFrame,
	pathProgress: number,
	extrapolated: boolean,
	snapped: boolean,
	segmentGap: boolean
): Sample
	return table.freeze({
		worldCFrame = worldCFrame,
		pathProgress = pathProgress,
		extrapolated = extrapolated,
		snapped = snapped,
		segmentGap = segmentGap,
	})
end

local function snapTo(entry: any, segmentGap: boolean): Sample
	return makeSample(entry.worldCFrame, entry.pathProgress, false, true, segmentGap)
end

local function samplesHaveKnownBridge(previous: any, current: any): boolean
	if
		current.pathProgress < previous.pathProgress - DISTANCE_TOLERANCE
		or current.sampleServerTime <= previous.sampleServerTime
	then
		return false
	end
	if current.segmentIndex == previous.segmentIndex then
		return math.abs(current.segmentStartDistance - previous.segmentStartDistance) <= DISTANCE_TOLERANCE
			and math.abs(current.segmentEndDistance - previous.segmentEndDistance) <= DISTANCE_TOLERANCE
			and (current.segmentStartPosition - previous.segmentStartPosition).Magnitude <= DISTANCE_TOLERANCE
			and (current.segmentEndPosition - previous.segmentEndPosition).Magnitude <= DISTANCE_TOLERANCE
	end
	return current.segmentIndex == previous.segmentIndex + 1
		and math.abs(previous.segmentEndDistance - current.segmentStartDistance) <= DISTANCE_TOLERANCE
		and (previous.segmentEndPosition - current.segmentStartPosition).Magnitude <= DISTANCE_TOLERANCE
end

function EnemyPresentation.sample(
	previousValue: EnemyProtocol.EnemyStateEntry?,
	currentValue: EnemyProtocol.EnemyStateEntry,
	serverTimeValue: unknown
): Result.Result<Sample, Error>
	if type(serverTimeValue) ~= "number" or not Validation.isFiniteNumber(serverTimeValue) or serverTimeValue < 0 then
		return failure("INVALID_TIME")
	end
	if not isUsableEntry(currentValue) or (previousValue ~= nil and not isUsableEntry(previousValue)) then
		return failure("INVALID_SAMPLE")
	end

	local current = currentValue :: any
	local previous = previousValue :: any
	if previous ~= nil and (previous.runtimeEnemyId ~= current.runtimeEnemyId or previous.laneId ~= current.laneId) then
		return Result.ok(snapTo(current, true))
	end
	if previous ~= nil and not samplesHaveKnownBridge(previous, current) then
		return Result.ok(snapTo(current, true))
	end

	local renderTime = serverTimeValue - INTERPOLATION_DELAY_SECONDS
	if previous ~= nil and renderTime <= previous.sampleServerTime then
		return Result.ok(makeSample(previous.worldCFrame, previous.pathProgress, false, false, false))
	end

	if previous ~= nil and renderTime < current.sampleServerTime then
		local alpha = (renderTime - previous.sampleServerTime) / (current.sampleServerTime - previous.sampleServerTime)
		local progress = previous.pathProgress + (current.pathProgress - previous.pathProgress) * alpha

		-- Prefer the newer segment at a shared boundary, so an exact corner faces
		-- along the outgoing route tangent rather than the incoming tangent.
		local sampled = sampleWindow(current, progress) or sampleWindow(previous, progress)
		if sampled == nil then
			return Result.ok(snapTo(current, true))
		end
		return Result.ok(makeSample(sampled, progress, false, false, false))
	end

	local elapsed = math.max(0, renderTime - current.sampleServerTime)
	local extrapolationSeconds = math.min(elapsed, MAX_EXTRAPOLATION_SECONDS)
	local progress =
		math.min(current.segmentEndDistance, current.pathProgress + current.effectiveSpeed * extrapolationSeconds)
	local sampled = sampleWindow(current, progress)
	if sampled == nil then
		return Result.ok(snapTo(current, true))
	end
	return Result.ok(makeSample(sampled, progress, extrapolationSeconds > 0, false, false))
end

function EnemyPresentation.classifyCorrection(
	displayedValue: unknown,
	targetValue: unknown
): Result.Result<Correction, Error>
	if not isFiniteVector3(displayedValue) or not isFiniteVector3(targetValue) then
		return failure("INVALID_SAMPLE")
	end
	local offset = (displayedValue :: Vector3) - (targetValue :: Vector3)
	local errorStuds = offset.Magnitude
	local mode: "Accept" | "Smooth" | "Snap"
	if errorStuds < CORRECTION_THRESHOLD_STUDS then
		mode = "Accept"
	elseif errorStuds < SNAP_THRESHOLD_STUDS then
		mode = "Smooth"
	else
		mode = "Snap"
	end
	return Result.ok(table.freeze({
		mode = mode,
		offset = if mode == "Smooth" then offset else Vector3.zero,
		errorStuds = errorStuds,
	}))
end

return table.freeze(EnemyPresentation)
