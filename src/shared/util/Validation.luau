--!strict

local Ids = require(script.Parent.Ids)

export type PathSegment = string | number

export type Code =
	"INVALID_TYPE"
	| "INVALID_TABLE"
	| "INVALID_ARRAY"
	| "MISSING_FIELD"
	| "UNKNOWN_FIELD"
	| "RUNTIME_FIELD_FORBIDDEN"
	| "INVALID_ID"
	| "DUPLICATE_ID"
	| "INVALID_STRING"
	| "INVALID_ENUM"
	| "NON_FINITE_NUMBER"
	| "NOT_INTEGER"
	| "OUT_OF_RANGE"
	| "EMPTY_COLLECTION"
	| "DUPLICATE_VALUE"
	| "INVALID_ORDER"
	| "INVALID_ASSET_KEY"
	| "DUPLICATE_ASSET_KEY"
	| "UNKNOWN_ASSET_KEY"
	| "WRONG_ASSET_KIND"
	| "INVALID_REFERENCE"
	| "INVALID_TOTAL"
	| "SOURCE_LOAD_FAILED"
	| "UNSUPPORTED_VERSION"

export type Issue = {
	code: Code,
	path: string,
	pathSegments: { PathSegment },
	message: string,
	causeCode: Ids.ErrorCode?,
	relatedPath: string?,
	actualType: string?,
}

export type RawObject = { [string]: unknown }

local MAX_KEY_BYTES = 64
local MAX_NAME_CHARACTERS = 80
local MAX_DESCRIPTION_CHARACTERS = 500
local MAX_OBJECT_FIELDS = 64
local MAX_CATALOG_ENTRIES = 1_000
local MAX_ASSET_ENTRIES = 2_000
local MAX_LEVEL_ENTRIES = 32
local MAX_LIST_ENTRIES = 32
local MAX_MAP_LANES = 32
local MAX_WAVES_PER_SCHEDULE = 1_000
local MAX_AUTHORED_WAVES = 1_000
local MAX_BOSS_CADENCE_WAVES = 1_000
local MAX_WAVE_GROUPS = 128
local MAX_GROUP_SPAWN_COUNT = 10_000
local MAX_WAVE_SPAWN_COUNT = 100_000
local MAX_AUTHORED_WAVE_GROUPS = 10_000
local MAX_AUTHORED_SPAWN_COUNT = 1_000_000
local MAX_SIMULTANEOUS_GROUP_SPAWNS = 100
local MAX_SIMULTANEOUS_WAVE_SPAWNS = 1_000
local MAX_WAVE_TIME_SECONDS = 3_600
local MIN_DIFFICULTY_MULTIPLIER = 0.001
local MAX_DIFFICULTY_MULTIPLIER = 1_000
local MAX_SAFE_INTEGER = 9_007_199_254_740_991

local Validation = {
	MAX_KEY_BYTES = MAX_KEY_BYTES,
	MAX_NAME_CHARACTERS = MAX_NAME_CHARACTERS,
	MAX_DESCRIPTION_CHARACTERS = MAX_DESCRIPTION_CHARACTERS,
	MAX_CATALOG_ENTRIES = MAX_CATALOG_ENTRIES,
	MAX_ASSET_ENTRIES = MAX_ASSET_ENTRIES,
	MAX_LEVEL_ENTRIES = MAX_LEVEL_ENTRIES,
	MAX_LIST_ENTRIES = MAX_LIST_ENTRIES,
	MAX_MAP_LANES = MAX_MAP_LANES,
	MAX_WAVES_PER_SCHEDULE = MAX_WAVES_PER_SCHEDULE,
	MAX_AUTHORED_WAVES = MAX_AUTHORED_WAVES,
	MAX_BOSS_CADENCE_WAVES = MAX_BOSS_CADENCE_WAVES,
	MAX_WAVE_GROUPS = MAX_WAVE_GROUPS,
	MAX_GROUP_SPAWN_COUNT = MAX_GROUP_SPAWN_COUNT,
	MAX_WAVE_SPAWN_COUNT = MAX_WAVE_SPAWN_COUNT,
	MAX_AUTHORED_WAVE_GROUPS = MAX_AUTHORED_WAVE_GROUPS,
	MAX_AUTHORED_SPAWN_COUNT = MAX_AUTHORED_SPAWN_COUNT,
	MAX_SIMULTANEOUS_GROUP_SPAWNS = MAX_SIMULTANEOUS_GROUP_SPAWNS,
	MAX_SIMULTANEOUS_WAVE_SPAWNS = MAX_SIMULTANEOUS_WAVE_SPAWNS,
	MAX_WAVE_TIME_SECONDS = MAX_WAVE_TIME_SECONDS,
	MIN_DIFFICULTY_MULTIPLIER = MIN_DIFFICULTY_MULTIPLIER,
	MAX_DIFFICULTY_MULTIPLIER = MAX_DIFFICULTY_MULTIPLIER,
	MAX_SAFE_INTEGER = MAX_SAFE_INTEGER,
}

local function copyAndFreezePath(pathSegments: { PathSegment }): { PathSegment }
	local length = rawlen(pathSegments)
	local copy: { PathSegment } = table.create(length)
	for index = 1, length do
		local segment = rawget(pathSegments, index)
		if type(segment) == "string" or type(segment) == "number" then
			copy[index] = segment
		else
			copy[index] = "<invalid>"
		end
	end

	return table.freeze(copy)
end

function Validation.renderPath(pathSegments: { PathSegment }): string
	local rendered = ""
	for index = 1, rawlen(pathSegments) do
		local rawSegment = rawget(pathSegments, index)
		local segment: PathSegment = if type(rawSegment) == "string" or type(rawSegment) == "number"
			then rawSegment
			else "<invalid>"
		if type(segment) == "number" then
			rendered ..= `[{segment}]`
		elseif index == 1 then
			rendered = segment
		else
			rendered ..= `.{segment}`
		end
	end

	return rendered
end

function Validation.appendPath(pathSegments: { PathSegment }, segment: PathSegment): { PathSegment }
	local length = rawlen(pathSegments)
	local copy: { PathSegment } = table.create(length + 1)
	for index = 1, length do
		local existingSegment = rawget(pathSegments, index)
		if type(existingSegment) == "string" or type(existingSegment) == "number" then
			copy[index] = existingSegment
		else
			copy[index] = "<invalid>"
		end
	end
	copy[length + 1] = segment
	return copy
end

local function makeIssue(
	code: Code,
	pathSegments: { PathSegment },
	message: string,
	causeCode: Ids.ErrorCode?,
	relatedPath: string?,
	actualType: string?
): Issue
	local frozenPath = copyAndFreezePath(pathSegments)
	return table.freeze({
		code = code,
		path = Validation.renderPath(frozenPath),
		pathSegments = frozenPath,
		message = message,
		causeCode = causeCode,
		relatedPath = relatedPath,
		actualType = actualType,
	})
end

function Validation.issue(code: Code, pathSegments: { PathSegment }, message: string): Issue
	return makeIssue(code, pathSegments, message, nil, nil, nil)
end

function Validation.issueWithType(code: Code, pathSegments: { PathSegment }, message: string, value: unknown): Issue
	return makeIssue(code, pathSegments, message, nil, nil, typeof(value))
end

function Validation.issueWithCause(
	code: Code,
	pathSegments: { PathSegment },
	message: string,
	causeCode: Ids.ErrorCode
): Issue
	return makeIssue(code, pathSegments, message, causeCode, nil, nil)
end

function Validation.issueWithRelated(
	code: Code,
	pathSegments: { PathSegment },
	message: string,
	relatedPath: string
): Issue
	return makeIssue(code, pathSegments, message, nil, relatedPath, nil)
end

local function isSafeUnknownFieldName(value: string): boolean
	return #value <= MAX_KEY_BYTES and string.match(value, "^[A-Za-z][A-Za-z0-9_]*$") ~= nil
end

function Validation.readObject(
	value: unknown,
	pathSegments: { PathSegment },
	allowedFields: { [string]: boolean },
	forbiddenRuntimeFields: { [string]: boolean }
): (RawObject?, Issue?)
	if type(value) ~= "table" then
		return nil, Validation.issueWithType("INVALID_TYPE", pathSegments, "Expected a plain definition table", value)
	end

	if getmetatable(value :: any) ~= nil then
		return nil, Validation.issue("INVALID_TABLE", pathSegments, "Definition tables must not have metatables")
	end

	local rawTable = value :: { [any]: unknown }
	local forbiddenFields: { string } = {}
	local unknownFields: { string } = {}
	local fieldCount = 0
	local hasNonStringField = false
	local hasUnsafeUnknownField = false

	for rawKey in next, rawTable do
		fieldCount += 1
		if fieldCount > MAX_OBJECT_FIELDS then
			return nil, Validation.issue("INVALID_TABLE", pathSegments, "Definition table contains too many fields")
		end

		if type(rawKey) ~= "string" then
			hasNonStringField = true
		elseif forbiddenRuntimeFields[rawKey] == true then
			table.insert(forbiddenFields, rawKey)
		elseif allowedFields[rawKey] ~= true then
			if not isSafeUnknownFieldName(rawKey) then
				hasUnsafeUnknownField = true
			else
				table.insert(unknownFields, rawKey)
			end
		end
	end

	if hasNonStringField then
		return nil, Validation.issue("INVALID_TABLE", pathSegments, "Definition field names must be strings")
	end
	table.sort(forbiddenFields)
	if #forbiddenFields > 0 then
		return nil,
			Validation.issue(
				"RUNTIME_FIELD_FORBIDDEN",
				Validation.appendPath(pathSegments, forbiddenFields[1]),
				"Mutable runtime state is forbidden in an immutable definition"
			)
	end

	if hasUnsafeUnknownField then
		return nil, Validation.issue("UNKNOWN_FIELD", pathSegments, "Definition contains an unknown field")
	end

	table.sort(unknownFields)
	if #unknownFields > 0 then
		return nil,
			Validation.issue(
				"UNKNOWN_FIELD",
				Validation.appendPath(pathSegments, unknownFields[1]),
				"Definition contains an unknown field"
			)
	end

	return value :: RawObject, nil
end

function Validation.readArray(
	value: unknown,
	pathSegments: { PathSegment },
	maximumEntries: number
): ({ unknown }?, Issue?)
	if type(value) ~= "table" then
		return nil, Validation.issueWithType("INVALID_TYPE", pathSegments, "Expected a dense array", value)
	end

	if getmetatable(value :: any) ~= nil then
		return nil, Validation.issue("INVALID_ARRAY", pathSegments, "Arrays must not have metatables")
	end

	local rawTable = value :: { [any]: unknown }
	local entryCount = 0
	local rawFieldCount = 0
	local maximumIndex = 0
	local hasInvalidKey = false
	local exceedsLimit = false
	for rawKey in next, rawTable do
		rawFieldCount += 1
		if rawFieldCount > maximumEntries then
			return nil, Validation.issue("OUT_OF_RANGE", pathSegments, "Array exceeds its technical entry limit")
		end

		if type(rawKey) ~= "number" or rawKey < 1 or rawKey % 1 ~= 0 then
			hasInvalidKey = true
		else
			entryCount += 1
			if entryCount > maximumEntries or rawKey > maximumEntries then
				exceedsLimit = true
			end
			maximumIndex = math.max(maximumIndex, rawKey)
		end
	end

	if hasInvalidKey then
		return nil, Validation.issue("INVALID_ARRAY", pathSegments, "Expected a dense one-based array")
	end
	if exceedsLimit then
		return nil, Validation.issue("OUT_OF_RANGE", pathSegments, "Array exceeds its technical entry limit")
	end

	if maximumIndex ~= entryCount then
		return nil, Validation.issue("INVALID_ARRAY", pathSegments, "Expected a dense one-based array")
	end

	local copy: { unknown } = table.create(entryCount)
	for index = 1, entryCount do
		copy[index] = rawget(rawTable, index)
	end

	return copy, nil
end

function Validation.getField(record: RawObject, fieldName: string): unknown
	return rawget(record :: any, fieldName)
end

function Validation.getRequiredField(
	record: RawObject,
	fieldName: string,
	pathSegments: { PathSegment }
): (unknown, Issue?)
	local value = Validation.getField(record, fieldName)
	if value == nil then
		return nil,
			Validation.issue(
				"MISSING_FIELD",
				Validation.appendPath(pathSegments, fieldName),
				"Definition is missing a required field"
			)
	end

	return value, nil
end

function Validation.isFiniteNumber(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function Validation.isSafeInteger(value: number): boolean
	return Validation.isFiniteNumber(value) and value % 1 == 0 and math.abs(value) <= MAX_SAFE_INTEGER
end

function Validation.isSymbolicKey(value: string): boolean
	local length = #value
	if length < 1 or length > MAX_KEY_BYTES then
		return false
	end

	local previousWasSeparator = false
	for index = 1, length do
		local byte = string.byte(value, index)
		local isAlphaNumeric = (byte >= string.byte("a") and byte <= string.byte("z"))
			or (byte >= string.byte("0") and byte <= string.byte("9"))
		local isSeparator = byte == string.byte(".") or byte == string.byte("-") or byte == string.byte("_")

		if not isAlphaNumeric and not isSeparator then
			return false
		end
		if isSeparator and (index == 1 or index == length or previousWasSeparator) then
			return false
		end
		previousWasSeparator = isSeparator
	end

	return true
end

-- Unicode 17.0.0 Default_Ignorable_Code_Point ranges. These code points may
-- participate in valid rendered text (for example, emoji ZWJ sequences), so
-- they are allowed but do not count as standalone authored-text content.
local function isDefaultIgnorableCodepoint(codepoint: number): boolean
	return codepoint == 173
		or codepoint == 847
		or codepoint == 1_564
		or (codepoint >= 4_447 and codepoint <= 4_448)
		or (codepoint >= 6_068 and codepoint <= 6_069)
		or (codepoint >= 6_155 and codepoint <= 6_159)
		or (codepoint >= 8_203 and codepoint <= 8_207)
		or (codepoint >= 8_234 and codepoint <= 8_238)
		or (codepoint >= 8_288 and codepoint <= 8_303)
		or codepoint == 12_644
		or (codepoint >= 65_024 and codepoint <= 65_039)
		or codepoint == 65_279
		or codepoint == 65_440
		or (codepoint >= 65_520 and codepoint <= 65_528)
		or (codepoint >= 113_824 and codepoint <= 113_827)
		or (codepoint >= 119_155 and codepoint <= 119_162)
		or (codepoint >= 917_504 and codepoint <= 921_599)
end

local function isLayoutFormatCodepoint(codepoint: number): boolean
	return (codepoint >= 65_529 and codepoint <= 65_531) or (codepoint >= 78_896 and codepoint <= 78_914)
end

function Validation.isDisplayText(value: string, maximumCharacters: number): boolean
	if #value < 1 or #value > maximumCharacters * 4 then
		return false
	end

	local characterCount = utf8.len(value)
	if characterCount == nil or characterCount > maximumCharacters then
		return false
	end

	local hasVisibleCodepoint = false
	local ordinal = 0
	for _, codepoint in utf8.codes(value) do
		ordinal += 1
		local isWhitespace = codepoint == 32
			or codepoint == 160
			or codepoint == 5_760
			or (codepoint >= 8_192 and codepoint <= 8_202)
			or codepoint == 8_239
			or codepoint == 8_287
			or codepoint == 10_240
			or codepoint == 12_288
		local isCombiningMark = (codepoint >= 768 and codepoint <= 879)
			or (codepoint >= 6_832 and codepoint <= 6_911)
			or (codepoint >= 7_616 and codepoint <= 7_679)
			or (codepoint >= 8_400 and codepoint <= 8_447)
			or (codepoint >= 65_024 and codepoint <= 65_039)
			or (codepoint >= 65_056 and codepoint <= 65_071)
			or (codepoint >= 917_760 and codepoint <= 917_999)
		local isInvisibleControl = codepoint < 32
			or (codepoint >= 127 and codepoint <= 159)
			or codepoint == 1_564
			or codepoint == 8_203
			or codepoint == 8_206
			or codepoint == 8_207
			or (codepoint >= 8_232 and codepoint <= 8_238)
			or (codepoint >= 8_288 and codepoint <= 8_303)
			or codepoint == 65_279

		if isInvisibleControl or ((ordinal == 1 or ordinal == characterCount) and isWhitespace) then
			return false
		end
		if
			not isWhitespace
			and not isDefaultIgnorableCodepoint(codepoint)
			and not isLayoutFormatCodepoint(codepoint)
			and not isCombiningMark
		then
			hasVisibleCodepoint = true
		end
	end

	return hasVisibleCodepoint
end

return table.freeze(Validation)
