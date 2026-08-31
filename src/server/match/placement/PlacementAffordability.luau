--!strict

local Result = require(game:GetService("ReplicatedStorage").Shared.util.Result)
local Validation = require(game:GetService("ReplicatedStorage").Shared.util.Validation)

export type State = "Active" | "Cleaned"
export type Operation = "canAfford" | "prepare" | "commit" | "abort" | "cleanup"
export type ErrorCode = "INVALID_ARGUMENT" | "UNAFFORDABLE" | "CAPACITY" | "INVALID_TOKEN" | "UNAVAILABLE"
export type Error = {
	code: ErrorCode,
	operation: Operation,
}
export type ChargeToken = {}
export type Metrics = {
	state: State,
	threshold: number,
	checkCount: number,
	prepareCount: number,
	commitCount: number,
	abortCount: number,
	outstandingCount: number,
}

type TokenData = {
	owner: Data,
	active: boolean,
}

type Data = {
	state: State,
	threshold: number,
	checkCount: number,
	prepareCount: number,
	commitCount: number,
	abortCount: number,
	outstandingCount: number,
	tokens: { [any]: boolean },
}

local Methods = {}
Methods.__index = Methods

export type Placeholder = typeof(setmetatable({} :: {}, Methods))

local STATIC_THRESHOLD = 150
local MAX_OUTSTANDING = 4
local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: Data }
local TOKEN_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: TokenData }

local PlacementAffordability = {
	STATIC_THRESHOLD = STATIC_THRESHOLD,
	MAX_OUTSTANDING = MAX_OUTSTANDING,
}

local function makeError(code: ErrorCode, operation: Operation): Error
	return table.freeze({ code = code, operation = operation })
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<Error>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): Data
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_PLACEMENT_AFFORDABILITY][code=INVALID_CONTEXT]", 0)
	end
	return data :: Data
end

local function validUserAndCost(userId: unknown, cost: unknown): boolean
	return type(userId) == "number"
		and Validation.isSafeInteger(userId :: number)
		and userId ~= 0
		and type(cost) == "number"
		and Validation.isSafeInteger(cost :: number)
		and (cost :: number) >= 0
end

function Methods.canAfford(self: Placeholder, userId: unknown, cost: unknown): Result.Result<boolean, Error>
	local data = requireData(self)
	if data.state ~= "Active" then
		return failure("UNAVAILABLE", "canAfford")
	end
	if not validUserAndCost(userId, cost) then
		return failure("INVALID_ARGUMENT", "canAfford")
	end
	data.checkCount += 1
	return Result.ok((cost :: number) <= data.threshold)
end

function Methods.prepare(self: Placeholder, userId: unknown, cost: unknown): Result.Result<ChargeToken, Error>
	local data = requireData(self)
	if data.state ~= "Active" then
		return failure("UNAVAILABLE", "prepare")
	end
	if not validUserAndCost(userId, cost) then
		return failure("INVALID_ARGUMENT", "prepare")
	end
	if (cost :: number) > data.threshold then
		return failure("UNAFFORDABLE", "prepare")
	end
	if data.outstandingCount >= MAX_OUTSTANDING then
		return failure("CAPACITY", "prepare")
	end
	local token = table.freeze({}) :: ChargeToken
	TOKEN_DATA[token] = { owner = data, active = true }
	data.tokens[token] = true
	data.outstandingCount += 1
	data.prepareCount += 1
	return Result.ok(token)
end

local function finishToken(
	data: Data,
	tokenValue: unknown,
	operation: "commit" | "abort"
): Result.Result<boolean, Error>
	if data.state ~= "Active" then
		return failure("UNAVAILABLE", operation)
	end
	local tokenData = if type(tokenValue) == "table" then TOKEN_DATA[tokenValue :: any] else nil
	if
		tokenData == nil
		or tokenData.owner ~= data
		or not tokenData.active
		or data.tokens[tokenValue :: any] ~= true
	then
		return failure("INVALID_TOKEN", operation)
	end
	tokenData.active = false
	TOKEN_DATA[tokenValue :: any] = nil
	data.tokens[tokenValue :: any] = nil
	data.outstandingCount -= 1
	if operation == "commit" then
		data.commitCount += 1
	else
		data.abortCount += 1
	end
	return Result.ok(true)
end

function Methods.commit(self: Placeholder, token: unknown): Result.Result<boolean, Error>
	return finishToken(requireData(self), token, "commit")
end

function Methods.abort(self: Placeholder, token: unknown): Result.Result<boolean, Error>
	return finishToken(requireData(self), token, "abort")
end

function Methods.getMetrics(self: Placeholder): Metrics
	local data = requireData(self)
	return table.freeze({
		state = data.state,
		threshold = data.threshold,
		checkCount = data.checkCount,
		prepareCount = data.prepareCount,
		commitCount = data.commitCount,
		abortCount = data.abortCount,
		outstandingCount = data.outstandingCount,
	})
end

function Methods.cleanup(self: Placeholder): Result.Result<boolean, Error>
	local data = requireData(self)
	if data.state == "Cleaned" then
		return Result.ok(false)
	end
	for token in data.tokens do
		local tokenData = TOKEN_DATA[token]
		if tokenData ~= nil then
			tokenData.active = false
		end
		TOKEN_DATA[token] = nil
	end
	table.clear(data.tokens)
	data.outstandingCount = 0
	data.state = "Cleaned"
	return Result.ok(true)
end

function PlacementAffordability.new(): Placeholder
	local placeholder = setmetatable({}, Methods) :: Placeholder
	table.freeze(placeholder)
	DATA[placeholder] = {
		state = "Active",
		threshold = STATIC_THRESHOLD,
		checkCount = 0,
		prepareCount = 0,
		commitCount = 0,
		abortCount = 0,
		outstandingCount = 0,
		tokens = {},
	}
	return placeholder
end

table.freeze(Methods)
return table.freeze(PlacementAffordability)
