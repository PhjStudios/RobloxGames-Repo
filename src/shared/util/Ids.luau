--!strict

local Result = require(script.Parent.Result)

export type IdKind =
	"tower"
	| "enemy"
	| "map"
	| "difficulty"
	| "wave"
	| "banner"
	| "unit"
	| "queue"
	| "match"
	| "transaction"

export type TowerId = string
export type EnemyId = string
export type MapId = string
export type DifficultyId = string
export type WaveId = string
export type BannerId = string
export type UnitId = string
export type QueueId = string
export type MatchId = string
export type TransactionId = string

export type ErrorCode = "INVALID_TYPE" | "INVALID_LENGTH" | "INVALID_FORMAT" | "WRONG_KIND"

export type IdError = {
	code: ErrorCode,
	message: string,
	expectedKind: IdKind,
}

local MAX_ID_LENGTH = 50
local SEPARATORS: { [string]: boolean } = table.freeze({
	["."] = true,
	["-"] = true,
	["_"] = true,
})

local VALID_KINDS: { [string]: boolean } = table.freeze({
	banner = true,
	difficulty = true,
	enemy = true,
	map = true,
	match = true,
	queue = true,
	transaction = true,
	tower = true,
	unit = true,
	wave = true,
})

local Ids = {
	MAX_ID_LENGTH = MAX_ID_LENGTH,
}

local function idError(kind: IdKind, code: ErrorCode, message: string): IdError
	return table.freeze({
		code = code,
		message = message,
		expectedKind = kind,
	})
end

local function fail(kind: IdKind, code: ErrorCode, message: string): Result.Failure<IdError>
	return Result.err(idError(kind, code, message))
end

local function isLowercaseLetterOrDigit(character: string): boolean
	local byte = string.byte(character)
	return (byte >= string.byte("a") and byte <= string.byte("z"))
		or (byte >= string.byte("0") and byte <= string.byte("9"))
end

local function validateBody(kind: IdKind, bodyValue: unknown): Result.Result<string, IdError>
	if type(bodyValue) ~= "string" then
		return fail(kind, "INVALID_TYPE", "ID body must be a string")
	end

	local body = bodyValue :: string
	local bodyLength = #body
	local maximumBodyLength = MAX_ID_LENGTH - #kind - 1
	if bodyLength < 1 or bodyLength > maximumBodyLength then
		return fail(
			kind,
			"INVALID_LENGTH",
			`ID body must contain at least one character and keep the complete ID within {MAX_ID_LENGTH} bytes`
		)
	end

	local previousWasSeparator = false
	for index = 1, bodyLength do
		local character = string.sub(body, index, index)
		local isSeparator = SEPARATORS[character] == true

		if not isLowercaseLetterOrDigit(character) and not isSeparator then
			return fail(kind, "INVALID_FORMAT", "ID body must use lowercase ASCII letters, digits, and separators")
		end

		if isSeparator and (index == 1 or index == bodyLength or previousWasSeparator) then
			return fail(kind, "INVALID_FORMAT", "ID separators must appear singly between alphanumeric characters")
		end

		previousWasSeparator = isSeparator
	end

	return Result.ok(body)
end

local function construct(kind: IdKind, bodyValue: unknown): Result.Result<string, IdError>
	local bodyResult = validateBody(kind, bodyValue)
	if not bodyResult.ok then
		return bodyResult
	end

	return Result.ok(`{kind}:{bodyResult.value}`)
end

local function validate(kind: IdKind, idValue: unknown): Result.Result<string, IdError>
	if type(idValue) ~= "string" then
		return fail(kind, "INVALID_TYPE", "ID must be a string")
	end

	local id = idValue :: string
	local idLength = #id
	if idLength < 1 or idLength > MAX_ID_LENGTH then
		return fail(kind, "INVALID_LENGTH", `Complete ID must contain between 1 and {MAX_ID_LENGTH} bytes`)
	end

	local separatorStart = string.find(id, ":", 1, true)
	if separatorStart == nil then
		return fail(kind, "INVALID_FORMAT", "ID must contain its category prefix")
	end

	local actualKind = string.sub(id, 1, separatorStart - 1)
	if VALID_KINDS[actualKind] ~= true then
		return fail(kind, "INVALID_FORMAT", "ID category prefix is not recognized")
	end

	local body = string.sub(id, separatorStart + 1)
	local bodyResult = validateBody(actualKind :: IdKind, body)
	if not bodyResult.ok then
		return fail(kind, bodyResult.error.code, bodyResult.error.message)
	end

	if actualKind ~= kind then
		return fail(kind, "WRONG_KIND", "ID belongs to a different category")
	end

	return Result.ok(id)
end

function Ids.makeTowerId(body: unknown): Result.Result<TowerId, IdError>
	return construct("tower", body)
end

function Ids.validateTowerId(value: unknown): Result.Result<TowerId, IdError>
	return validate("tower", value)
end

function Ids.makeEnemyId(body: unknown): Result.Result<EnemyId, IdError>
	return construct("enemy", body)
end

function Ids.validateEnemyId(value: unknown): Result.Result<EnemyId, IdError>
	return validate("enemy", value)
end

function Ids.makeMapId(body: unknown): Result.Result<MapId, IdError>
	return construct("map", body)
end

function Ids.validateMapId(value: unknown): Result.Result<MapId, IdError>
	return validate("map", value)
end

function Ids.makeDifficultyId(body: unknown): Result.Result<DifficultyId, IdError>
	return construct("difficulty", body)
end

function Ids.validateDifficultyId(value: unknown): Result.Result<DifficultyId, IdError>
	return validate("difficulty", value)
end

function Ids.makeWaveId(body: unknown): Result.Result<WaveId, IdError>
	return construct("wave", body)
end

function Ids.validateWaveId(value: unknown): Result.Result<WaveId, IdError>
	return validate("wave", value)
end

function Ids.makeBannerId(body: unknown): Result.Result<BannerId, IdError>
	return construct("banner", body)
end

function Ids.validateBannerId(value: unknown): Result.Result<BannerId, IdError>
	return validate("banner", value)
end

function Ids.makeUnitId(body: unknown): Result.Result<UnitId, IdError>
	return construct("unit", body)
end

function Ids.validateUnitId(value: unknown): Result.Result<UnitId, IdError>
	return validate("unit", value)
end

function Ids.makeQueueId(body: unknown): Result.Result<QueueId, IdError>
	return construct("queue", body)
end

function Ids.validateQueueId(value: unknown): Result.Result<QueueId, IdError>
	return validate("queue", value)
end

function Ids.makeMatchId(body: unknown): Result.Result<MatchId, IdError>
	return construct("match", body)
end

function Ids.validateMatchId(value: unknown): Result.Result<MatchId, IdError>
	return validate("match", value)
end

function Ids.makeTransactionId(body: unknown): Result.Result<TransactionId, IdError>
	return construct("transaction", body)
end

function Ids.validateTransactionId(value: unknown): Result.Result<TransactionId, IdError>
	return validate("transaction", value)
end

return table.freeze(Ids)
