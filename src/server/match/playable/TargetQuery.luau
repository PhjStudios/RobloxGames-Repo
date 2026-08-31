--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type TargetableEnemy = {
	runtimeEnemyId: number,
	pathProgress: number,
	currentHealth: number,
	lifecycle: "Active" | "EndpointResolved" | "Despawned" | "Killed",
	worldCFrame: CFrame,
}

export type Selection = {
	runtimeEnemyId: number,
	pathProgress: number,
	currentHealth: number,
	distanceSquared: number,
	worldCFrame: CFrame,
}

export type Operation = "select"
export type ErrorCode =
	"INVALID_TOWER_CFRAME"
	| "INVALID_RANGE"
	| "INVALID_TARGET_MODE"
	| "INVALID_ENEMY_ARRAY"
	| "INVALID_ENEMY"
	| "DUPLICATE_RUNTIME_ID"
	| "CAPACITY_EXCEEDED"

export type QueryError = {
	code: ErrorCode,
	operation: Operation,
	candidateIndex: number?,
}

type RankedCandidate = {
	runtimeEnemyId: number,
	pathProgress: number,
	currentHealth: number,
	distanceSquared: number,
	worldCFrame: CFrame,
}

local MAX_CANDIDATES = 128
local MAX_COORDINATE = 100_000
local VALID_TARGET_MODES: { [string]: boolean } = table.freeze({
	Closest = true,
	First = true,
	Last = true,
	Strongest = true,
	Weakest = true,
})
local VALID_LIFECYCLES: { [string]: boolean } = table.freeze({
	Active = true,
	Despawned = true,
	EndpointResolved = true,
	Killed = true,
})

local TargetQuery = {
	MAX_CANDIDATES = MAX_CANDIDATES,
	MAX_COORDINATE = MAX_COORDINATE,
}

local function failure(code: ErrorCode, candidateIndex: number?): Result.Failure<QueryError>
	return Result.err(table.freeze({
		code = code,
		operation = "select",
		candidateIndex = candidateIndex,
	}))
end

local function isFiniteCoordinate(value: number): boolean
	return Validation.isFiniteNumber(value) and math.abs(value) <= MAX_COORDINATE
end

local function isFiniteCFrame(value: unknown): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	local cframe = value :: CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cframe:GetComponents()
	if not isFiniteCoordinate(x) or not isFiniteCoordinate(y) or not isFiniteCoordinate(z) then
		return false
	end
	for _, component in { r00, r01, r02, r10, r11, r12, r20, r21, r22 } do
		if not Validation.isFiniteNumber(component) then
			return false
		end
	end
	return true
end

local function validateDenseArray(value: unknown): ({ unknown }?, ErrorCode?)
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil, "INVALID_ENEMY_ARRAY"
	end
	local array = value :: { [any]: unknown }
	local length = rawlen(array)
	if length > MAX_CANDIDATES then
		return nil, "CAPACITY_EXCEEDED"
	end
	local count = 0
	for key in next, array do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return nil, "INVALID_ENEMY_ARRAY"
		end
		count += 1
	end
	if count ~= length then
		return nil, "INVALID_ENEMY_ARRAY"
	end
	local detached: { unknown } = table.create(length)
	for index = 1, length do
		detached[index] = rawget(array, index)
	end
	return detached, nil
end

local function validateCandidate(value: unknown): TargetableEnemy?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local candidate = value :: any
	if
		type(candidate.runtimeEnemyId) ~= "number"
		or not Validation.isSafeInteger(candidate.runtimeEnemyId)
		or candidate.runtimeEnemyId < 1
		or type(candidate.pathProgress) ~= "number"
		or not Validation.isFiniteNumber(candidate.pathProgress)
		or candidate.pathProgress < 0
		or type(candidate.currentHealth) ~= "number"
		or not Validation.isFiniteNumber(candidate.currentHealth)
		or candidate.currentHealth < 0
		or type(candidate.lifecycle) ~= "string"
		or VALID_LIFECYCLES[candidate.lifecycle] ~= true
		or not isFiniteCFrame(candidate.worldCFrame)
	then
		return nil
	end
	return candidate :: TargetableEnemy
end

local function distanceSquared(from: Vector3, to: Vector3): number
	local x = to.X - from.X
	local y = to.Y - from.Y
	local z = to.Z - from.Z
	return x * x + y * y + z * z
end

local function compareDescending(left: number, right: number): boolean?
	if left > right then
		return true
	elseif left < right then
		return false
	end
	return nil
end

local function compareAscending(left: number, right: number): boolean?
	if left < right then
		return true
	elseif left > right then
		return false
	end
	return nil
end

-- Every mode has an explicit total ordering. The final runtime-ID comparison
-- makes the answer independent of the input array's iteration order.
local function ranksBefore(mode: ConfigTypes.TargetMode, left: RankedCandidate, right: RankedCandidate): boolean
	local decision: boolean?
	if mode == "First" then
		decision = compareDescending(left.pathProgress, right.pathProgress)
		if decision == nil then
			decision = compareDescending(left.currentHealth, right.currentHealth)
		end
		if decision == nil then
			decision = compareAscending(left.distanceSquared, right.distanceSquared)
		end
	elseif mode == "Last" then
		decision = compareAscending(left.pathProgress, right.pathProgress)
		if decision == nil then
			decision = compareDescending(left.currentHealth, right.currentHealth)
		end
		if decision == nil then
			decision = compareAscending(left.distanceSquared, right.distanceSquared)
		end
	elseif mode == "Strongest" then
		decision = compareDescending(left.currentHealth, right.currentHealth)
		if decision == nil then
			decision = compareDescending(left.pathProgress, right.pathProgress)
		end
		if decision == nil then
			decision = compareAscending(left.distanceSquared, right.distanceSquared)
		end
	elseif mode == "Weakest" then
		decision = compareAscending(left.currentHealth, right.currentHealth)
		if decision == nil then
			decision = compareDescending(left.pathProgress, right.pathProgress)
		end
		if decision == nil then
			decision = compareAscending(left.distanceSquared, right.distanceSquared)
		end
	else
		decision = compareAscending(left.distanceSquared, right.distanceSquared)
		if decision == nil then
			decision = compareDescending(left.pathProgress, right.pathProgress)
		end
		if decision == nil then
			decision = compareDescending(left.currentHealth, right.currentHealth)
		end
	end
	if decision ~= nil then
		return decision
	end
	return left.runtimeEnemyId < right.runtimeEnemyId
end

function TargetQuery.select(
	towerCFrameValue: unknown,
	rangeStudsValue: unknown,
	targetModeValue: unknown,
	enemiesValue: unknown
): Result.Result<Selection?, QueryError>
	if not isFiniteCFrame(towerCFrameValue) then
		return failure("INVALID_TOWER_CFRAME", nil)
	end
	if
		type(rangeStudsValue) ~= "number"
		or not Validation.isFiniteNumber(rangeStudsValue :: number)
		or (rangeStudsValue :: number) < 0
		or (rangeStudsValue :: number) > MAX_COORDINATE
	then
		return failure("INVALID_RANGE", nil)
	end
	if type(targetModeValue) ~= "string" or VALID_TARGET_MODES[targetModeValue :: string] ~= true then
		return failure("INVALID_TARGET_MODE", nil)
	end
	local enemies, arrayError = validateDenseArray(enemiesValue)
	if enemies == nil then
		return failure(arrayError :: ErrorCode, nil)
	end

	local towerPosition = (towerCFrameValue :: CFrame).Position
	local rangeSquared = (rangeStudsValue :: number) * (rangeStudsValue :: number)
	local mode = targetModeValue :: ConfigTypes.TargetMode
	local seenRuntimeIds: { [number]: boolean } = {}
	local best: RankedCandidate? = nil

	for index, candidateValue in enemies do
		local candidate = validateCandidate(candidateValue)
		if candidate == nil then
			return failure("INVALID_ENEMY", index)
		end
		if seenRuntimeIds[candidate.runtimeEnemyId] == true then
			return failure("DUPLICATE_RUNTIME_ID", index)
		end
		seenRuntimeIds[candidate.runtimeEnemyId] = true

		if candidate.lifecycle == "Active" and candidate.currentHealth > 0 then
			local squared = distanceSquared(towerPosition, candidate.worldCFrame.Position)
			if squared <= rangeSquared then
				local ranked: RankedCandidate = {
					runtimeEnemyId = candidate.runtimeEnemyId,
					pathProgress = candidate.pathProgress,
					currentHealth = candidate.currentHealth,
					distanceSquared = squared,
					worldCFrame = candidate.worldCFrame,
				}
				if best == nil or ranksBefore(mode, ranked, best :: RankedCandidate) then
					best = ranked
				end
			end
		end
	end

	if best == nil then
		return Result.ok(nil)
	end
	return Result.ok(table.freeze({
		runtimeEnemyId = best.runtimeEnemyId,
		pathProgress = best.pathProgress,
		currentHealth = best.currentHealth,
		distanceSquared = best.distanceSquared,
		worldCFrame = best.worldCFrame,
	}))
end

return table.freeze(TargetQuery)
