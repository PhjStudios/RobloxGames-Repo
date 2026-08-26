--!strict

local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type Limits = {
	maxDepth: number,
	maxNodes: number,
	maxRecordFields: number,
	maxArrayItems: number,
	maxStringBytes: number,
}

export type LimitsOverride = {
	maxDepth: number?,
	maxNodes: number?,
	maxRecordFields: number?,
	maxArrayItems: number?,
	maxStringBytes: number?,
}

export type IdKind = Ids.IdKind

type Context = {
	limits: Limits,
	nodeBudget: {
		count: number,
		exceeded: boolean,
	},
	seenTables: { [any]: boolean },
}

type InternalValidator = (
	value: unknown,
	context: Context,
	path: { Validation.PathSegment },
	depth: number
) -> (unknown, Validation.Issue?)

local ValidatorMethods = {}
ValidatorMethods.__index = ValidatorMethods

export type Validator = typeof(setmetatable({} :: {}, ValidatorMethods))

local SchemaMethods = {}
SchemaMethods.__index = SchemaMethods

export type Schema = typeof(setmetatable({} :: {}, SchemaMethods))

local InstancePolicyMethods = {}
InstancePolicyMethods.__index = InstancePolicyMethods

export type InstancePolicy = typeof(setmetatable({} :: {}, InstancePolicyMethods))

type InstancePolicyData = {
	className: string,
	ancestor: Instance,
	allowSubclasses: boolean,
}

local MAX_DEPTH = 8
local MAX_NODES = 512
local MAX_RECORD_FIELDS = 64
local MAX_ARRAY_ITEMS = 128
local MAX_STRING_BYTES = 1_024
local MAX_ENUM_VALUES = 128
local MAX_UNION_BRANCHES = 8

local CFRAME_COMPONENT_NAMES: { string } = table.freeze({
	"X",
	"Y",
	"Z",
	"R00",
	"R01",
	"R02",
	"R10",
	"R11",
	"R12",
	"R20",
	"R21",
	"R22",
})

local ROOT_PATH: { Validation.PathSegment } = table.freeze({ "payload" })
local DEFAULT_LIMITS: Limits = table.freeze({
	maxDepth = MAX_DEPTH,
	maxNodes = MAX_NODES,
	maxRecordFields = MAX_RECORD_FIELDS,
	maxArrayItems = MAX_ARRAY_ITEMS,
	maxStringBytes = MAX_STRING_BYTES,
})

local LIMIT_FIELDS: { [string]: boolean } = table.freeze({
	maxDepth = true,
	maxNodes = true,
	maxRecordFields = true,
	maxArrayItems = true,
	maxStringBytes = true,
})

local VALID_ID_KINDS: { [string]: boolean } = table.freeze({
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

local VALIDATORS = setmetatable({}, { __mode = "k" }) :: { [any]: InternalValidator }
local OPTIONAL_VALIDATORS = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
local SCHEMA_VALIDATORS = setmetatable({}, { __mode = "k" }) :: { [any]: Validator }
local SCHEMA_LIMITS = setmetatable({}, { __mode = "k" }) :: { [any]: Limits }
local INSTANCE_POLICIES = setmetatable({}, { __mode = "k" }) :: { [any]: InstancePolicyData }

local PayloadValidation = {
	MAX_DEPTH = MAX_DEPTH,
	MAX_NODES = MAX_NODES,
	MAX_RECORD_FIELDS = MAX_RECORD_FIELDS,
	MAX_ARRAY_ITEMS = MAX_ARRAY_ITEMS,
	MAX_STRING_BYTES = MAX_STRING_BYTES,
	MAX_ENUM_VALUES = MAX_ENUM_VALUES,
	MAX_UNION_BRANCHES = MAX_UNION_BRANCHES,
	DEFAULT_LIMITS = DEFAULT_LIMITS,
}

local executeValidator: (
	validator: Validator,
	value: unknown,
	context: Context,
	path: { Validation.PathSegment },
	depth: number
) -> (unknown, Validation.Issue?)

local executeComposedValidator: (
	validator: Validator,
	value: unknown,
	context: Context,
	path: { Validation.PathSegment },
	depth: number
) -> (unknown, Validation.Issue?)

local function schemaAuthoringError(code: string): never
	error(`[ATD_PAYLOAD_SCHEMA][code={code}]`, 0)
end

local function isFiniteNumber(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isSafeInteger(value: number): boolean
	return isFiniteNumber(value) and value % 1 == 0 and math.abs(value) <= Validation.MAX_SAFE_INTEGER
end

local function isValidator(value: unknown): boolean
	return type(value) == "table" and VALIDATORS[value :: any] ~= nil
end

local function isSchema(value: unknown): boolean
	return type(value) == "table" and SCHEMA_VALIDATORS[value :: any] ~= nil and SCHEMA_LIMITS[value :: any] ~= nil
end

local function isInstancePolicy(value: unknown): boolean
	return type(value) == "table" and INSTANCE_POLICIES[value :: any] ~= nil
end

local function makeValidator(callback: InternalValidator, optional: boolean?): Validator
	local validator = setmetatable({}, ValidatorMethods) :: Validator
	table.freeze(validator)
	VALIDATORS[validator] = callback
	if optional == true then
		OPTIONAL_VALIDATORS[validator] = true
	end
	return validator
end

local function issue(code: Validation.Code, path: { Validation.PathSegment }, message: string): Validation.Issue
	return Validation.issue(code, path, message)
end

local function checkPlainSchemaTable(value: unknown, code: string): { [any]: unknown }
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		schemaAuthoringError(code)
	end
	return value :: { [any]: unknown }
end

local function readDenseSchemaArray(value: unknown, maximum: number, code: string): { unknown }
	local rawTable = checkPlainSchemaTable(value, code)
	local count = 0
	local maximumIndex = 0
	local hasInvalidKey = false
	for rawKey in next, rawTable do
		count += 1
		if count > maximum then
			schemaAuthoringError(code)
		end
		if type(rawKey) ~= "number" or not isSafeInteger(rawKey) or rawKey < 1 then
			hasInvalidKey = true
		else
			maximumIndex = math.max(maximumIndex, rawKey)
		end
	end
	if hasInvalidKey or maximumIndex ~= count then
		schemaAuthoringError(code)
	end

	local copy: { unknown } = table.create(count)
	for index = 1, count do
		copy[index] = rawget(rawTable, index)
	end
	return copy
end

local function requireBoundedInteger(value: unknown, minimum: number, maximum: number, code: string): number
	if type(value) ~= "number" or not isSafeInteger(value) or value < minimum or value > maximum then
		schemaAuthoringError(code)
	end
	return value
end

local function requireFiniteBound(value: unknown, code: string): number
	if type(value) ~= "number" or not isFiniteNumber(value) then
		schemaAuthoringError(code)
	end
	return value
end

local function usesSafeFieldName(value: string): boolean
	if #value < 1 or #value > Validation.MAX_KEY_BYTES then
		return false
	end
	return string.match(value, "^[A-Za-z][A-Za-z0-9_]*$") ~= nil
end

local function canonicalLimits(value: LimitsOverride?): Limits
	if value == nil then
		return DEFAULT_LIMITS
	end

	local rawLimits = checkPlainSchemaTable(value, "INVALID_LIMITS")
	for rawKey in next, rawLimits do
		if type(rawKey) ~= "string" or LIMIT_FIELDS[rawKey] ~= true then
			schemaAuthoringError("INVALID_LIMITS")
		end
	end

	local function readLimit(fieldName: string, minimumValue: number, defaultValue: number): number
		local rawValue = rawget(rawLimits, fieldName)
		if rawValue == nil then
			return defaultValue
		end
		return requireBoundedInteger(rawValue, minimumValue, defaultValue, "INVALID_LIMITS")
	end

	return table.freeze({
		maxDepth = readLimit("maxDepth", 0, MAX_DEPTH),
		maxNodes = readLimit("maxNodes", 1, MAX_NODES),
		maxRecordFields = readLimit("maxRecordFields", 0, MAX_RECORD_FIELDS),
		maxArrayItems = readLimit("maxArrayItems", 0, MAX_ARRAY_ITEMS),
		maxStringBytes = readLimit("maxStringBytes", 0, MAX_STRING_BYTES),
	})
end

local function cloneContext(context: Context): Context
	local seenTables: { [any]: boolean } = {}
	for seenTable in next, context.seenTables do
		rawset(seenTables, seenTable, true)
	end
	return {
		limits = context.limits,
		nodeBudget = context.nodeBudget,
		seenTables = seenTables,
	}
end

local function adoptContext(target: Context, source: Context)
	target.seenTables = source.seenTables
end

local function consumeNode(context: Context, path: { Validation.PathSegment }): Validation.Issue?
	context.nodeBudget.count += 1
	if context.nodeBudget.count > context.limits.maxNodes then
		context.nodeBudget.exceeded = true
		return issue("OUT_OF_RANGE", path, "Payload exceeds the maximum validation node count")
	end
	return nil
end

executeValidator = function(
	validator: Validator,
	value: unknown,
	context: Context,
	path: { Validation.PathSegment },
	depth: number
): (unknown, Validation.Issue?)
	local callback = VALIDATORS[validator]
	if callback == nil then
		return nil, issue("INVALID_REFERENCE", path, "Payload schema contains an unauthenticated validator")
	end
	if depth > context.limits.maxDepth then
		return nil, issue("OUT_OF_RANGE", path, "Payload exceeds the maximum validation depth")
	end

	local nodeIssue = consumeNode(context, path)
	if nodeIssue ~= nil then
		return nil, nodeIssue
	end

	if type(value) == "string" and #value > context.limits.maxStringBytes then
		return nil, issue("INVALID_STRING", path, "String exceeds the payload byte limit")
	end

	if type(value) == "table" then
		local rawTable = value :: { [any]: unknown }
		if getmetatable(rawTable) ~= nil then
			return nil, issue("INVALID_TABLE", path, "Payload tables must not have metatables")
		end
		if rawget(context.seenTables, rawTable) == true then
			return nil, issue("INVALID_TABLE", path, "Payload tables must not contain cycles or repeated references")
		end
		rawset(context.seenTables, rawTable, true)
	end

	return callback(value, context, path, depth)
end

executeComposedValidator = function(
	validator: Validator,
	value: unknown,
	context: Context,
	path: { Validation.PathSegment },
	depth: number
): (unknown, Validation.Issue?)
	local callback = VALIDATORS[validator]
	if callback == nil then
		return nil, issue("INVALID_REFERENCE", path, "Payload schema contains an unauthenticated validator")
	end
	local nodeIssue = consumeNode(context, path)
	if nodeIssue ~= nil then
		return nil, nodeIssue
	end
	return callback(value, context, path, depth)
end

local function runSchema(schema: Schema, value: unknown): Result.Result<unknown, Validation.Issue>
	local validator = SCHEMA_VALIDATORS[schema]
	local limits = SCHEMA_LIMITS[schema]
	if validator == nil or limits == nil then
		return Result.err(issue("INVALID_REFERENCE", ROOT_PATH, "Expected an authenticated payload schema"))
	end

	local context: Context = {
		limits = limits,
		nodeBudget = {
			count = 0,
			exceeded = false,
		},
		seenTables = {},
	}
	local canonical, validationIssue = executeValidator(validator, value, context, ROOT_PATH, 0)
	if validationIssue ~= nil then
		return Result.err(validationIssue)
	end
	return Result.ok(canonical)
end

function ValidatorMethods.validate(self: Validator, value: unknown): Result.Result<unknown, Validation.Issue>
	if not isValidator(self) then
		return Result.err(issue("INVALID_REFERENCE", ROOT_PATH, "Expected an authenticated payload validator"))
	end
	local schema = PayloadValidation.schema(self)
	return runSchema(schema, value)
end

function SchemaMethods.validate(self: Schema, value: unknown): Result.Result<unknown, Validation.Issue>
	return runSchema(self, value)
end

function PayloadValidation.string(maximumBytes: number, minimumBytes: number?): Validator
	local maximum = requireBoundedInteger(maximumBytes, 0, MAX_STRING_BYTES, "INVALID_STRING_LIMIT")
	local minimum = if minimumBytes == nil
		then 0
		else requireBoundedInteger(minimumBytes, 0, maximum, "INVALID_STRING_LIMIT")

	return makeValidator(function(value, context, path, _depth)
		if type(value) ~= "string" then
			return nil, issue("INVALID_TYPE", path, "Expected a string")
		end
		local byteLength = #value
		local effectiveMaximum = math.min(maximum, context.limits.maxStringBytes)
		if byteLength < minimum or byteLength > effectiveMaximum then
			return nil, issue("INVALID_STRING", path, "String is outside its allowed byte range")
		end
		return value, nil
	end)
end

function PayloadValidation.enum(values: { string }): Validator
	local rawValues = readDenseSchemaArray(values, MAX_ENUM_VALUES, "INVALID_ENUM_DEFINITION")
	if rawlen(rawValues) < 1 then
		schemaAuthoringError("INVALID_ENUM_DEFINITION")
	end

	local allowed: { [string]: boolean } = {}
	for index = 1, rawlen(rawValues) do
		local rawValue = rawget(rawValues, index)
		if type(rawValue) ~= "string" or #rawValue < 1 or #rawValue > MAX_STRING_BYTES then
			schemaAuthoringError("INVALID_ENUM_DEFINITION")
		end
		if rawget(allowed, rawValue) == true then
			schemaAuthoringError("INVALID_ENUM_DEFINITION")
		end
		allowed[rawValue] = true
	end
	local frozenAllowed = table.freeze(allowed)

	return makeValidator(function(value, context, path, _depth)
		if type(value) ~= "string" then
			return nil, issue("INVALID_TYPE", path, "Expected a bounded enumeration string")
		end
		if #value > context.limits.maxStringBytes or rawget(frozenAllowed, value) ~= true then
			return nil, issue("INVALID_ENUM", path, "String is not an allowed enumeration value")
		end
		return value, nil
	end)
end

function PayloadValidation.id(kind: IdKind): Validator
	if type(kind) ~= "string" or VALID_ID_KINDS[kind] ~= true then
		schemaAuthoringError("INVALID_ID_KIND")
	end

	return makeValidator(function(value, _context, path, _depth)
		local idResult
		if kind == "tower" then
			idResult = Ids.validateTowerId(value)
		elseif kind == "enemy" then
			idResult = Ids.validateEnemyId(value)
		elseif kind == "map" then
			idResult = Ids.validateMapId(value)
		elseif kind == "difficulty" then
			idResult = Ids.validateDifficultyId(value)
		elseif kind == "wave" then
			idResult = Ids.validateWaveId(value)
		elseif kind == "banner" then
			idResult = Ids.validateBannerId(value)
		elseif kind == "unit" then
			idResult = Ids.validateUnitId(value)
		elseif kind == "queue" then
			idResult = Ids.validateQueueId(value)
		elseif kind == "match" then
			idResult = Ids.validateMatchId(value)
		else
			idResult = Ids.validateTransactionId(value)
		end

		if not idResult.ok then
			return nil,
				Validation.issueWithCause(
					"INVALID_ID",
					path,
					"ID is not canonical for the required family",
					idResult.error.code
				)
		end
		return idResult.value, nil
	end)
end

function PayloadValidation.number(minimum: number, maximum: number): Validator
	local canonicalMinimum = requireFiniteBound(minimum, "INVALID_NUMBER_RANGE")
	local canonicalMaximum = requireFiniteBound(maximum, "INVALID_NUMBER_RANGE")
	if canonicalMinimum > canonicalMaximum then
		schemaAuthoringError("INVALID_NUMBER_RANGE")
	end

	return makeValidator(function(value, _context, path, _depth)
		if type(value) ~= "number" then
			return nil, issue("INVALID_TYPE", path, "Expected a number")
		end
		if not isFiniteNumber(value) then
			return nil, issue("NON_FINITE_NUMBER", path, "Number must be finite")
		end
		if value < canonicalMinimum or value > canonicalMaximum then
			return nil, issue("OUT_OF_RANGE", path, "Number is outside its allowed range")
		end
		return if value == 0 then 0 else value, nil
	end)
end

function PayloadValidation.integer(minimum: number, maximum: number): Validator
	local canonicalMinimum = requireFiniteBound(minimum, "INVALID_INTEGER_RANGE")
	local canonicalMaximum = requireFiniteBound(maximum, "INVALID_INTEGER_RANGE")
	if
		not isSafeInteger(canonicalMinimum)
		or not isSafeInteger(canonicalMaximum)
		or canonicalMinimum > canonicalMaximum
	then
		schemaAuthoringError("INVALID_INTEGER_RANGE")
	end

	return makeValidator(function(value, _context, path, _depth)
		if type(value) ~= "number" then
			return nil, issue("INVALID_TYPE", path, "Expected an integer")
		end
		if not isFiniteNumber(value) then
			return nil, issue("NON_FINITE_NUMBER", path, "Integer must be finite")
		end
		if not isSafeInteger(value) then
			return nil, issue("NOT_INTEGER", path, "Number must be an exact safe integer")
		end
		if value < canonicalMinimum or value > canonicalMaximum then
			return nil, issue("OUT_OF_RANGE", path, "Integer is outside its allowed range")
		end
		return if value == 0 then 0 else value, nil
	end)
end

function PayloadValidation.boolean(): Validator
	return makeValidator(function(value, _context, path, _depth)
		if type(value) ~= "boolean" then
			return nil, issue("INVALID_TYPE", path, "Expected a boolean")
		end
		return value, nil
	end)
end

function PayloadValidation.array(itemValidator: Validator, maximumItems: number, minimumItems: number?): Validator
	if not isValidator(itemValidator) then
		schemaAuthoringError("INVALID_ARRAY_VALIDATOR")
	end
	local maximum = requireBoundedInteger(maximumItems, 0, MAX_ARRAY_ITEMS, "INVALID_ARRAY_LIMIT")
	local minimum = if minimumItems == nil
		then 0
		else requireBoundedInteger(minimumItems, 0, maximum, "INVALID_ARRAY_LIMIT")

	return makeValidator(function(value, context, path, depth)
		if type(value) ~= "table" then
			return nil, issue("INVALID_TYPE", path, "Expected a dense one-based array")
		end
		local rawTable = value :: { [any]: unknown }
		local entryCount = 0
		local maximumIndex = 0
		local hasInvalidKey = false
		local effectiveMaximum = math.min(maximum, context.limits.maxArrayItems)
		for rawKey in next, rawTable do
			entryCount += 1
			if entryCount > effectiveMaximum then
				return nil, issue("OUT_OF_RANGE", path, "Array exceeds its allowed item count")
			end
			if type(rawKey) ~= "number" or not isSafeInteger(rawKey) or rawKey < 1 then
				hasInvalidKey = true
			else
				maximumIndex = math.max(maximumIndex, rawKey)
			end
		end
		if hasInvalidKey or maximumIndex ~= entryCount then
			return nil, issue("INVALID_ARRAY", path, "Expected a dense one-based array")
		end
		if entryCount < minimum then
			return nil, issue("OUT_OF_RANGE", path, "Array contains too few items")
		end

		local canonical: { unknown } = table.create(entryCount)
		for index = 1, entryCount do
			local itemPath = Validation.appendPath(path, index)
			local item, itemIssue =
				executeValidator(itemValidator, rawget(rawTable, index), context, itemPath, depth + 1)
			if itemIssue ~= nil then
				return nil, itemIssue
			end
			canonical[index] = item
		end
		return table.freeze(canonical), nil
	end)
end

function PayloadValidation.record(fields: { [string]: Validator }): Validator
	local rawFields = checkPlainSchemaTable(fields, "INVALID_RECORD_DEFINITION")
	local names: { string } = {}
	local validatorsByName: { [string]: Validator } = {}
	local fieldCount = 0
	for rawName, rawValidator in next, rawFields do
		fieldCount += 1
		if
			fieldCount > MAX_RECORD_FIELDS
			or type(rawName) ~= "string"
			or not usesSafeFieldName(rawName)
			or not isValidator(rawValidator)
		then
			schemaAuthoringError("INVALID_RECORD_DEFINITION")
		end
		table.insert(names, rawName)
		validatorsByName[rawName] = rawValidator :: Validator
	end
	table.sort(names)
	local frozenNames = table.freeze(names)
	local frozenValidatorsByName = table.freeze(validatorsByName)

	return makeValidator(function(value, context, path, depth)
		if type(value) ~= "table" then
			return nil, issue("INVALID_TYPE", path, "Expected an exact-key record")
		end
		local rawTable = value :: { [any]: unknown }
		local hasInvalidKey = false
		local hasUnknownField = false
		local rawPayloadFieldCount = 0
		for rawName in next, rawTable do
			rawPayloadFieldCount += 1
			if rawPayloadFieldCount > context.limits.maxRecordFields then
				return nil, issue("OUT_OF_RANGE", path, "Record exceeds the payload field count limit")
			end
			if type(rawName) ~= "string" then
				hasInvalidKey = true
			elseif rawget(frozenValidatorsByName, rawName) == nil then
				hasUnknownField = true
			end
		end
		if hasInvalidKey then
			return nil, issue("INVALID_TABLE", path, "Record field names must be strings")
		end
		if hasUnknownField then
			return nil, issue("UNKNOWN_FIELD", path, "Record contains an unexpected field")
		end

		local canonical: { [string]: unknown } = {}
		for index = 1, rawlen(frozenNames) do
			local fieldName = rawget(frozenNames, index) :: string
			local fieldValidator = rawget(frozenValidatorsByName, fieldName) :: Validator
			local rawValue = rawget(rawTable, fieldName)
			local fieldPath = Validation.appendPath(path, fieldName)
			if rawValue == nil then
				if OPTIONAL_VALIDATORS[fieldValidator] ~= true then
					return nil, issue("MISSING_FIELD", fieldPath, "Record is missing a required field")
				end
			else
				local fieldValue, fieldIssue = executeValidator(fieldValidator, rawValue, context, fieldPath, depth + 1)
				if fieldIssue ~= nil then
					return nil, fieldIssue
				end
				if fieldValue ~= nil then
					canonical[fieldName] = fieldValue
				end
			end
		end
		return table.freeze(canonical), nil
	end)
end

function PayloadValidation.optional(validator: Validator): Validator
	if not isValidator(validator) then
		schemaAuthoringError("INVALID_OPTIONAL_VALIDATOR")
	end

	return makeValidator(function(value, context, path, depth)
		if value == nil then
			return nil, nil
		end
		return executeComposedValidator(validator, value, context, path, depth)
	end, true)
end

function PayloadValidation.union(branches: { Validator }): Validator
	local rawBranches = readDenseSchemaArray(branches, MAX_UNION_BRANCHES, "INVALID_UNION_DEFINITION")
	if rawlen(rawBranches) < 2 then
		schemaAuthoringError("INVALID_UNION_DEFINITION")
	end
	local canonicalBranches: { Validator } = table.create(rawlen(rawBranches))
	for index = 1, rawlen(rawBranches) do
		local branch = rawget(rawBranches, index)
		if not isValidator(branch) then
			schemaAuthoringError("INVALID_UNION_DEFINITION")
		end
		canonicalBranches[index] = branch :: Validator
	end
	local frozenBranches = table.freeze(canonicalBranches)

	return makeValidator(function(value, context, path, depth)
		local successCount = 0
		local successfulValue: unknown = nil
		local successfulContext: Context? = nil
		for index = 1, rawlen(frozenBranches) do
			local branch = rawget(frozenBranches, index) :: Validator
			local branchContext = cloneContext(context)
			local branchValue, branchIssue = executeComposedValidator(branch, value, branchContext, path, depth)
			if context.nodeBudget.exceeded then
				return nil,
					if branchIssue ~= nil
						then branchIssue
						else issue("OUT_OF_RANGE", path, "Payload exceeds the maximum validation node count")
			end
			if branchIssue == nil then
				successCount += 1
				if successCount == 1 then
					successfulValue = branchValue
					successfulContext = branchContext
				end
			end
		end

		if successCount ~= 1 or successfulContext == nil then
			return nil, issue("INVALID_TYPE", path, "Payload must match exactly one allowed union branch")
		end
		adoptContext(context, successfulContext)
		return successfulValue, nil
	end)
end

local function finiteVectorComponent(value: number): boolean
	return isFiniteNumber(value)
end

function PayloadValidation.vector2(): Validator
	return makeValidator(function(value, _context, path, _depth)
		if typeof(value) ~= "Vector2" then
			return nil, issue("INVALID_TYPE", path, "Expected a Vector2")
		end
		local vector = value :: Vector2
		if not finiteVectorComponent(vector.X) then
			return nil,
				issue("NON_FINITE_NUMBER", Validation.appendPath(path, "X"), "Vector2 X component must be finite")
		end
		if not finiteVectorComponent(vector.Y) then
			return nil,
				issue("NON_FINITE_NUMBER", Validation.appendPath(path, "Y"), "Vector2 Y component must be finite")
		end
		return vector, nil
	end)
end

function PayloadValidation.vector3(): Validator
	return makeValidator(function(value, _context, path, _depth)
		if typeof(value) ~= "Vector3" then
			return nil, issue("INVALID_TYPE", path, "Expected a Vector3")
		end
		local vector = value :: Vector3
		if not finiteVectorComponent(vector.X) then
			return nil,
				issue("NON_FINITE_NUMBER", Validation.appendPath(path, "X"), "Vector3 X component must be finite")
		end
		if not finiteVectorComponent(vector.Y) then
			return nil,
				issue("NON_FINITE_NUMBER", Validation.appendPath(path, "Y"), "Vector3 Y component must be finite")
		end
		if not finiteVectorComponent(vector.Z) then
			return nil,
				issue("NON_FINITE_NUMBER", Validation.appendPath(path, "Z"), "Vector3 Z component must be finite")
		end
		return vector, nil
	end)
end

function PayloadValidation.cframe(): Validator
	return makeValidator(function(value, _context, path, _depth)
		if typeof(value) ~= "CFrame" then
			return nil, issue("INVALID_TYPE", path, "Expected a CFrame")
		end
		local components = table.pack((value :: CFrame):GetComponents())
		if components.n ~= 12 then
			return nil, issue("INVALID_TYPE", path, "CFrame must expose twelve numeric components")
		end
		for index = 1, components.n do
			local component = rawget(components, index)
			if type(component) ~= "number" or not finiteVectorComponent(component) then
				local componentName = rawget(CFRAME_COMPONENT_NAMES, index) :: string
				return nil,
					issue(
						"NON_FINITE_NUMBER",
						Validation.appendPath(path, componentName),
						"CFrame component must be finite"
					)
			end
		end
		return value, nil
	end)
end

function PayloadValidation.instancePolicy(
	className: string,
	ancestor: Instance,
	allowSubclasses: boolean?
): InstancePolicy
	if
		type(className) ~= "string"
		or not usesSafeFieldName(className)
		or typeof(ancestor) ~= "Instance"
		or (allowSubclasses ~= nil and type(allowSubclasses) ~= "boolean")
	then
		schemaAuthoringError("INVALID_INSTANCE_POLICY")
	end

	local policy = setmetatable({}, InstancePolicyMethods) :: InstancePolicy
	table.freeze(policy)
	INSTANCE_POLICIES[policy] = table.freeze({
		className = className,
		ancestor = ancestor,
		allowSubclasses = allowSubclasses == true,
	})
	return policy
end

local function isActualServerContext(): boolean
	local succeeded, liveServerResult = pcall(function(): boolean
		local runService = game:GetService("RunService")
		return runService:IsServer() and runService:IsRunning()
	end)
	if succeeded then
		return liveServerResult == true
	end

	-- The deterministic Lune place loader does not simulate RunService. This
	-- seam requires the exact test-project roots, whose production builds never
	-- contain ServerStorage.AutomatedTests.
	local testRuntimeSucceeded, isTestRuntime = pcall(function(): boolean
		local replicatedStorage = game:GetService("ReplicatedStorage")
		local shared = replicatedStorage:FindFirstChild("Shared")
		local network = if shared == nil then nil else shared:FindFirstChild("network")
		local automatedTests = game:GetService("ServerStorage"):FindFirstChild("AutomatedTests")
		local support = if automatedTests == nil then nil else automatedTests:FindFirstChild("Support")
		local runner = if support == nil then nil else support:FindFirstChild("TestRunner")
		local adapter = if support == nil then nil else support:FindFirstChild("RobloxAdapter")
		return automatedTests ~= nil
			and automatedTests.Parent == game:GetService("ServerStorage")
			and runner ~= nil
			and runner:IsA("ModuleScript")
			and adapter ~= nil
			and adapter:IsA("ModuleScript")
			and network ~= nil
			and script.Parent == network
			and script:IsDescendantOf(replicatedStorage)
	end)
	return testRuntimeSucceeded and isTestRuntime == true
end

function PayloadValidation.instance(policy: InstancePolicy): Validator
	if not isInstancePolicy(policy) then
		schemaAuthoringError("INVALID_INSTANCE_POLICY")
	end
	local policyData = INSTANCE_POLICIES[policy] :: InstancePolicyData

	return makeValidator(function(value, _context, path, _depth)
		if typeof(value) ~= "Instance" then
			return nil, issue("INVALID_TYPE", path, "Expected an explicitly permitted Instance")
		end
		if not isActualServerContext() then
			return nil, issue("INVALID_REFERENCE", path, "Instance payloads are permitted only in server context")
		end

		local instance = value :: Instance
		local classCheckSucceeded, classAllowed = pcall(function(): boolean
			return if policyData.allowSubclasses
				then instance:IsA(policyData.className)
				else instance.ClassName == policyData.className
		end)
		if not classCheckSucceeded then
			return nil, issue("INVALID_REFERENCE", path, "Instance policy could not be evaluated safely")
		end
		if classAllowed ~= true then
			return nil, issue("INVALID_TYPE", path, "Instance class is not permitted by this payload schema")
		end
		local ancestryCheckSucceeded, ancestryAllowed = pcall(function(): boolean
			return instance:IsDescendantOf(policyData.ancestor)
		end)
		if not ancestryCheckSucceeded then
			return nil, issue("INVALID_REFERENCE", path, "Instance policy could not be evaluated safely")
		end
		if ancestryAllowed ~= true then
			return nil, issue("INVALID_REFERENCE", path, "Instance is outside the permitted server ancestry")
		end
		return instance, nil
	end)
end

function PayloadValidation.schema(validator: Validator, limits: LimitsOverride?): Schema
	if not isValidator(validator) then
		schemaAuthoringError("INVALID_ROOT_VALIDATOR")
	end
	local schema = setmetatable({}, SchemaMethods) :: Schema
	table.freeze(schema)
	SCHEMA_VALIDATORS[schema] = validator
	SCHEMA_LIMITS[schema] = canonicalLimits(limits)
	return schema
end

function PayloadValidation.validate(schema: Schema, value: unknown): Result.Result<unknown, Validation.Issue>
	return runSchema(schema, value)
end

function PayloadValidation.isValidator(value: unknown): boolean
	return isValidator(value)
end

function PayloadValidation.isSchema(value: unknown): boolean
	return isSchema(value)
end

function PayloadValidation.isInstancePolicy(value: unknown): boolean
	return isInstancePolicy(value)
end

table.freeze(ValidatorMethods)
table.freeze(SchemaMethods)
table.freeze(InstancePolicyMethods)
return table.freeze(PayloadValidation)
