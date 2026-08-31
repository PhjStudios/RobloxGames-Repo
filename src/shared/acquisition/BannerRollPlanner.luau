--!strict

local AcquisitionProtocol = require(script.Parent.AcquisitionProtocol)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type RandomSource = {
	nextNumber: (self: RandomSource) -> unknown,
}

export type PlannedOutcome = {
	index: number,
	towerId: string,
	pityTriggered: boolean,
	pityBefore: number,
	pityAfter: number,
}

export type Plan = {
	bannerId: string,
	bannerVersion: number,
	quantity: number,
	pityBefore: number,
	pityAfter: number,
	outcomes: { PlannedOutcome },
}

export type ErrorCode =
	"INVALID_CONFIGURATION"
	| "INVALID_RANDOM_SOURCE"
	| "INVALID_BANNER"
	| "UNAVAILABLE"
	| "INVALID_PITY"
	| "INVALID_QUANTITY"
	| "RANDOM_FAILED"
	| "RANDOM_OUT_OF_RANGE"
	| "OUTCOME_NOT_FOUND"

export type PlannerError = {
	code: ErrorCode,
	operation: "new" | "plan",
}

type PlannerData = {
	configuration: AcquisitionProtocol.AuthenticatedConfiguration,
	random: RandomSource,
}

local Methods = {}
Methods.__index = Methods

export type Planner = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: PlannerData }

local BannerRollPlanner = {}

local function failure<T>(code: ErrorCode, operation: "new" | "plan"): Result.Failure<PlannerError>
	return Result.err(table.freeze({
		code = code,
		operation = operation,
	}))
end

local function requireData(value: unknown): PlannerData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_BANNER_ROLL_PLANNER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function weightedTowerId(
	data: PlannerData,
	policy: AcquisitionProtocol.AuthenticatedBannerPolicy
): Result.Result<string, PlannerError>
	local called, randomValue = callNonYielding(data.random.nextNumber, data.random)
	if not called then
		return failure("RANDOM_FAILED", "plan")
	end
	if
		type(randomValue) ~= "number"
		or not Validation.isFiniteNumber(randomValue :: number)
		or (randomValue :: number) < 0
		or (randomValue :: number) >= 1
	then
		return failure("RANDOM_OUT_OF_RANGE", "plan")
	end
	local point = (randomValue :: number) * 100
	local cumulative = 0
	for _, outcome in policy.definition.outcomes do
		cumulative += outcome.probabilityPercent
		if point < cumulative then
			return Result.ok(outcome.towerId)
		end
	end
	return failure("OUTCOME_NOT_FOUND", "plan")
end

function Methods.plan(
	self: Planner,
	bannerIdValue: unknown,
	currentPityValue: unknown,
	quantityValue: unknown
): Result.Result<Plan, PlannerError>
	local data = requireData(self)
	if type(bannerIdValue) ~= "string" then
		return failure("INVALID_BANNER", "plan")
	end
	local policy = data.configuration.byBannerId[bannerIdValue]
	if policy == nil then
		return failure("INVALID_BANNER", "plan")
	end
	if not policy.available then
		return failure("UNAVAILABLE", "plan")
	end
	local pityRule = policy.definition.pityRule
	if pityRule == nil then
		return failure("INVALID_CONFIGURATION", "plan")
	end
	if
		type(currentPityValue) ~= "number"
		or not Validation.isSafeInteger(currentPityValue :: number)
		or (currentPityValue :: number) < 0
		or (currentPityValue :: number) >= pityRule.hardPityPullCount
	then
		return failure("INVALID_PITY", "plan")
	end
	if quantityValue ~= 1 and quantityValue ~= 10 then
		return failure("INVALID_QUANTITY", "plan")
	end

	local currentPity = currentPityValue :: number
	local outcomes: { PlannedOutcome } = table.create(quantityValue :: number)
	for index = 1, quantityValue :: number do
		local pityBefore = currentPity
		local pityTriggered = currentPity + 1 >= pityRule.hardPityPullCount
		local towerId: string
		if pityTriggered then
			towerId = pityRule.guaranteedTowerId
		else
			local rolled = weightedTowerId(data, policy)
			if not rolled.ok then
				return Result.err(rolled.error)
			end
			towerId = rolled.value
		end
		-- The hard-pity target resets pity whether obtained naturally or by the
		-- forced boundary. Every other outcome advances it by one.
		currentPity = if towerId == pityRule.guaranteedTowerId then 0 else currentPity + 1
		outcomes[index] = table.freeze({
			index = index,
			towerId = towerId,
			pityTriggered = pityTriggered,
			pityBefore = pityBefore,
			pityAfter = currentPity,
		})
	end
	return Result.ok(table.freeze({
		bannerId = policy.bannerId,
		bannerVersion = policy.bannerVersion,
		quantity = quantityValue :: number,
		pityBefore = currentPityValue :: number,
		pityAfter = currentPity,
		outcomes = table.freeze(outcomes),
	}))
end

function BannerRollPlanner.new(configurationValue: unknown, randomValue: unknown): Result.Result<Planner, PlannerError>
	if not AcquisitionProtocol.isAuthenticatedConfiguration(configurationValue) then
		return failure("INVALID_CONFIGURATION", "new")
	end
	if type(randomValue) ~= "table" or type((randomValue :: any).nextNumber) ~= "function" then
		return failure("INVALID_RANDOM_SOURCE", "new")
	end
	local planner = setmetatable({}, Methods) :: Planner
	table.freeze(planner)
	DATA[planner] = {
		configuration = configurationValue :: AcquisitionProtocol.AuthenticatedConfiguration,
		random = randomValue :: RandomSource,
	}
	return Result.ok(planner)
end

table.freeze(Methods)
return table.freeze(BannerRollPlanner)
