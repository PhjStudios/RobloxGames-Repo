--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Shared = game:GetService("ReplicatedStorage").Shared
local PayloadValidation = require(Shared.network.PayloadValidation)
local Validation = require(Shared.util.Validation)

type Assertions = TestHarness.Assertions

local function expectSuccess(
	assertions: Assertions,
	validator: PayloadValidation.Validator,
	value: unknown,
	limits: PayloadValidation.LimitsOverride?
): unknown
	local schema = PayloadValidation.schema(validator, limits)
	local result = schema:validate(value)
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return (result :: any).value
end

local function expectFailure(
	assertions: Assertions,
	validator: PayloadValidation.Validator,
	value: unknown,
	code: string,
	path: string,
	limits: PayloadValidation.LimitsOverride?
): any
	local schema = PayloadValidation.schema(validator, limits)
	local result = PayloadValidation.validate(schema, value)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local validationIssue = (result :: any).error
	assertions.equal(validationIssue.code, code)
	assertions.equal(validationIssue.path, path)
	assertions.isTrue(type(validationIssue.message) == "string" and #validationIssue.message > 0)
	assertions.isTrue(table.isfrozen(validationIssue))
	assertions.isTrue(table.isfrozen(validationIssue.pathSegments))
	return validationIssue
end

local function assertAuthoringFailure(assertions: Assertions, callback: () -> ())
	local succeeded, failure = pcall(callback)
	assertions.isFalse(succeeded)
	assertions.isTrue(type(failure) == "string")
	assertions.contains(failure, "[ATD_PAYLOAD_SCHEMA][code=")
end

local function assertGraphDoesNotRetain(assertions: Assertions, root: unknown, forbidden: unknown)
	local visited: { [any]: boolean } = {}
	local function visit(value: unknown)
		assertions.notEqual(value, forbidden)
		if type(value) ~= "table" or rawget(visited, value) == true then
			return
		end
		rawset(visited, value, true)
		for key, child in next, value :: { [any]: unknown } do
			assertions.notEqual(key, forbidden)
			visit(child)
		end
	end
	visit(root)
end

local function nestedRecord(depth: number): (PayloadValidation.Validator, unknown)
	local validator = PayloadValidation.string(8, 1)
	local value: unknown = "leaf"
	for _ = 1, depth do
		validator = PayloadValidation.record({ child = validator })
		value = { child = value }
	end
	return validator, value
end

local function cframeWithComponent(componentIndex: number, componentValue: number): CFrame
	local components: { number } = {
		0,
		0,
		0,
		1,
		0,
		0,
		0,
		1,
		0,
		0,
		0,
		1,
	}
	components[componentIndex] = componentValue
	return CFrame.new(
		components[1],
		components[2],
		components[3],
		components[4],
		components[5],
		components[6],
		components[7],
		components[8],
		components[9],
		components[10],
		components[11],
		components[12]
	)
end

return TestHarness.suite("network payload validation", {
	TestHarness.case("exports fixed frozen technical limits and authentic schema objects", function(assertions)
		assertions.equal(PayloadValidation.MAX_DEPTH, 8)
		assertions.equal(PayloadValidation.MAX_NODES, 512)
		assertions.equal(PayloadValidation.MAX_RECORD_FIELDS, 64)
		assertions.equal(PayloadValidation.MAX_ARRAY_ITEMS, 128)
		assertions.equal(PayloadValidation.MAX_STRING_BYTES, 1_024)
		assertions.equal(PayloadValidation.MAX_ENUM_VALUES, 128)
		assertions.equal(PayloadValidation.MAX_UNION_BRANCHES, 8)
		assertions.isTrue(table.isfrozen(PayloadValidation))
		assertions.isTrue(table.isfrozen(PayloadValidation.DEFAULT_LIMITS))

		local validator = PayloadValidation.boolean()
		local schema = PayloadValidation.schema(validator)
		assertions.isTrue(PayloadValidation.isValidator(validator))
		assertions.isTrue(PayloadValidation.isSchema(schema))
		assertions.isFalse(PayloadValidation.isValidator({}))
		assertions.isFalse(PayloadValidation.isSchema({}))
		assertions.isTrue(table.isfrozen(validator))
		assertions.isTrue(table.isfrozen(schema))

		local validateMethod = schema.validate :: any
		local counterfeitResult = validateMethod({}, true)
		assertions.isFalse(counterfeitResult.ok)
		assertions.equal(counterfeitResult.error.code, "INVALID_REFERENCE")
		assertions.equal(counterfeitResult.error.path, "payload")
	end),

	TestHarness.case("validates bounded strings without coercion or rejected-value echo", function(assertions)
		assertions.equal(expectSuccess(assertions, PayloadValidation.string(4, 2), "ab"), "ab")
		assertions.equal(expectSuccess(assertions, PayloadValidation.string(4, 2), "abcd"), "abcd")
		assertions.equal(expectSuccess(assertions, PayloadValidation.string(2), "\u{00E9}"), "\u{00E9}")
		expectFailure(assertions, PayloadValidation.string(4, 2), "a", "INVALID_STRING", "payload")
		expectFailure(assertions, PayloadValidation.string(4, 2), "abcde", "INVALID_STRING", "payload")
		expectFailure(assertions, PayloadValidation.string(1), "\u{00E9}", "INVALID_STRING", "payload")
		assertions.equal(
			expectSuccess(
				assertions,
				PayloadValidation.string(PayloadValidation.MAX_STRING_BYTES),
				string.rep("a", PayloadValidation.MAX_STRING_BYTES)
			),
			string.rep("a", PayloadValidation.MAX_STRING_BYTES)
		)
		expectFailure(
			assertions,
			PayloadValidation.string(PayloadValidation.MAX_STRING_BYTES),
			string.rep("a", PayloadValidation.MAX_STRING_BYTES + 1),
			"INVALID_STRING",
			"payload"
		)

		local coercionCount = 0
		local privateSentinel = "PRIVATE_STRING_SENTINEL_06_2"
		local hostile = setmetatable({}, {
			__tostring = function()
				coercionCount += 1
				return privateSentinel
			end,
		})
		local validationIssue =
			expectFailure(assertions, PayloadValidation.string(32), hostile, "INVALID_TABLE", "payload")
		assertions.equal(coercionCount, 0)
		assertions.isNil(string.find(validationIssue.message, privateSentinel, 1, true))
	end),

	TestHarness.case("validates bounded enumerations with private stable failures", function(assertions)
		local validator = PayloadValidation.enum({ "Alpha", "Beta", "Gamma" })
		assertions.equal(expectSuccess(assertions, validator, "Alpha"), "Alpha")
		expectFailure(assertions, validator, "Delta", "INVALID_ENUM", "payload")
		expectFailure(assertions, validator, 1, "INVALID_TYPE", "payload")

		assertAuthoringFailure(assertions, function()
			PayloadValidation.enum({})
		end)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.enum({ "Alpha", "Alpha" })
		end)
		local maximumValues = {}
		for index = 1, PayloadValidation.MAX_ENUM_VALUES do
			maximumValues[index] = `Value{index}`
		end
		assertions.equal(
			expectSuccess(assertions, PayloadValidation.enum(maximumValues), `Value{PayloadValidation.MAX_ENUM_VALUES}`),
			`Value{PayloadValidation.MAX_ENUM_VALUES}`
		)
		maximumValues[PayloadValidation.MAX_ENUM_VALUES + 1] = "TooMany"
		assertAuthoringFailure(assertions, function()
			PayloadValidation.enum(maximumValues)
		end)
	end),

	TestHarness.case("reuses every typed ID family and rejects cross-family values", function(assertions)
		local kinds = {
			"tower",
			"enemy",
			"map",
			"difficulty",
			"wave",
			"banner",
			"unit",
			"queue",
			"match",
			"transaction",
		}
		for _, rawKind in kinds do
			local kind = rawKind :: PayloadValidation.IdKind
			local canonical = `{kind}:fixture-1`
			local wrongFamily = if kind == "tower" then "enemy:wrong-family" else "tower:wrong-family"
			assertions.equal(expectSuccess(assertions, PayloadValidation.id(kind), canonical), canonical)
			local wrongFamilyIssue =
				expectFailure(assertions, PayloadValidation.id(kind), wrongFamily, "INVALID_ID", "payload")
			assertions.equal(wrongFamilyIssue.causeCode, "WRONG_KIND")
			local wrongTypeIssue = expectFailure(assertions, PayloadValidation.id(kind), 5, "INVALID_ID", "payload")
			assertions.equal(wrongTypeIssue.causeCode, "INVALID_TYPE")
		end

		assertAuthoringFailure(assertions, function()
			(PayloadValidation.id :: any)("player")
		end)
	end),

	TestHarness.case("validates finite bounded numbers and exact safe integers", function(assertions)
		local numberValidator = PayloadValidation.number(-10, 10)
		assertions.equal(expectSuccess(assertions, numberValidator, -10), -10)
		assertions.equal(expectSuccess(assertions, numberValidator, 10), 10)
		assertions.equal(expectSuccess(assertions, numberValidator, -0), 0)
		expectFailure(assertions, numberValidator, 11, "OUT_OF_RANGE", "payload")
		expectFailure(assertions, numberValidator, 0 / 0, "NON_FINITE_NUMBER", "payload")
		expectFailure(assertions, numberValidator, math.huge, "NON_FINITE_NUMBER", "payload")
		expectFailure(assertions, numberValidator, -math.huge, "NON_FINITE_NUMBER", "payload")
		expectFailure(assertions, numberValidator, "1", "INVALID_TYPE", "payload")

		local integerValidator = PayloadValidation.integer(-2, 2)
		assertions.equal(expectSuccess(assertions, integerValidator, -2), -2)
		assertions.equal(expectSuccess(assertions, integerValidator, 2), 2)
		expectFailure(assertions, integerValidator, 1.5, "NOT_INTEGER", "payload")
		expectFailure(assertions, integerValidator, math.huge, "NON_FINITE_NUMBER", "payload")
		expectFailure(assertions, integerValidator, 3, "OUT_OF_RANGE", "payload")
		expectFailure(
			assertions,
			PayloadValidation.integer(-Validation.MAX_SAFE_INTEGER, Validation.MAX_SAFE_INTEGER),
			Validation.MAX_SAFE_INTEGER + 1,
			"NOT_INTEGER",
			"payload"
		)
	end),

	TestHarness.case("validates booleans without accepting truthy coercions", function(assertions)
		assertions.equal(expectSuccess(assertions, PayloadValidation.boolean(), true), true)
		assertions.equal(expectSuccess(assertions, PayloadValidation.boolean(), false), false)
		expectFailure(assertions, PayloadValidation.boolean(), 1, "INVALID_TYPE", "payload")
		expectFailure(assertions, PayloadValidation.boolean(), "true", "INVALID_TYPE", "payload")
	end),

	TestHarness.case("canonicalizes dense arrays and rejects sparse or exotic keys", function(assertions)
		local authored = { "a", "bb", "ccc" }
		local canonical =
			expectSuccess(assertions, PayloadValidation.array(PayloadValidation.string(3, 1), 3, 1), authored)
		assertions.notEqual(canonical, authored)
		assertions.isTrue(table.isfrozen(canonical :: any))
		authored[1] = "changed"
		assertions.equal((canonical :: any)[1], "a")

		expectFailure(
			assertions,
			PayloadValidation.array(PayloadValidation.string(3), 3),
			{ [1] = "a", [3] = "c" },
			"INVALID_ARRAY",
			"payload"
		)
		expectFailure(
			assertions,
			PayloadValidation.array(PayloadValidation.string(3), 3),
			{ [0] = "a" },
			"INVALID_ARRAY",
			"payload"
		)
		expectFailure(
			assertions,
			PayloadValidation.array(PayloadValidation.string(3), 3),
			{ [1.5] = "a" },
			"INVALID_ARRAY",
			"payload"
		)
		expectFailure(
			assertions,
			PayloadValidation.array(PayloadValidation.string(3), 3),
			{ item = "a" },
			"INVALID_ARRAY",
			"payload"
		)
		expectFailure(
			assertions,
			PayloadValidation.array(PayloadValidation.string(3), 2),
			{ "a", "b", "c" },
			"OUT_OF_RANGE",
			"payload"
		)
		expectFailure(
			assertions,
			PayloadValidation.array(PayloadValidation.string(3), 3, 1),
			{},
			"OUT_OF_RANGE",
			"payload"
		)
	end),

	TestHarness.case("validates exact-key records in canonical field-name order", function(assertions)
		local validator = PayloadValidation.record({
			zeta = PayloadValidation.string(8, 1),
			alpha = PayloadValidation.integer(0, 10),
		})
		local authored = { zeta = "ok", alpha = 3 }
		local canonical = expectSuccess(assertions, validator, authored)
		assertions.notEqual(canonical, authored)
		assertions.equal((canonical :: any).alpha, 3)
		assertions.equal((canonical :: any).zeta, "ok")
		assertions.isTrue(table.isfrozen(canonical :: any))
		authored.alpha = 9
		assertions.equal((canonical :: any).alpha, 3)

		expectFailure(assertions, validator, {}, "MISSING_FIELD", "payload.alpha")
		expectFailure(assertions, validator, { alpha = 1 }, "MISSING_FIELD", "payload.zeta")
		expectFailure(assertions, validator, { alpha = 1, zeta = "ok", extra = true }, "UNKNOWN_FIELD", "payload")
		expectFailure(assertions, validator, { alpha = 1, zeta = "ok", [2] = true }, "INVALID_TABLE", "payload")
	end),

	TestHarness.case("supports omitted optional values without double-charging table traversal", function(assertions)
		local validator = PayloadValidation.record({
			required = PayloadValidation.boolean(),
			note = PayloadValidation.optional(PayloadValidation.string(8, 1)),
			details = PayloadValidation.optional(PayloadValidation.record({
				enabled = PayloadValidation.boolean(),
			})),
		})
		local omitted = expectSuccess(assertions, validator, { required = true })
		assertions.isNil((omitted :: any).note)
		assertions.isNil(expectSuccess(assertions, PayloadValidation.optional(PayloadValidation.string(8)), nil))
		local present =
			expectSuccess(assertions, validator, { required = false, note = "safe", details = { enabled = true } })
		assertions.equal((present :: any).note, "safe")
		assertions.equal((present :: any).details.enabled, true)
		assertions.isTrue(table.isfrozen((present :: any).details))
		expectFailure(assertions, validator, { required = true, note = 5 }, "INVALID_TYPE", "payload.note")
	end),

	TestHarness.case("requires exactly one authored union branch to succeed", function(assertions)
		local unique = PayloadValidation.union({
			PayloadValidation.enum({ "Alpha" }),
			PayloadValidation.integer(1, 2),
		})
		assertions.equal(expectSuccess(assertions, unique, "Alpha"), "Alpha")
		assertions.equal(expectSuccess(assertions, unique, 2), 2)
		expectFailure(assertions, unique, true, "INVALID_TYPE", "payload")

		local ambiguous = PayloadValidation.union({
			PayloadValidation.string(8, 1),
			PayloadValidation.enum({ "Alpha" }),
		})
		expectFailure(assertions, ambiguous, "Alpha", "INVALID_TYPE", "payload")

		assertAuthoringFailure(assertions, function()
			PayloadValidation.union({ PayloadValidation.boolean() })
		end)

		local maximumBranches = {}
		for index = 1, PayloadValidation.MAX_UNION_BRANCHES do
			maximumBranches[index] = PayloadValidation.enum({ `Branch{index}` })
		end
		local maximumUnion = PayloadValidation.union(maximumBranches)
		assertions.equal(
			expectSuccess(assertions, maximumUnion, `Branch{PayloadValidation.MAX_UNION_BRANCHES}`),
			`Branch{PayloadValidation.MAX_UNION_BRANCHES}`
		)
		expectFailure(
			assertions,
			maximumUnion,
			`Branch{PayloadValidation.MAX_UNION_BRANCHES}`,
			"OUT_OF_RANGE",
			"payload",
			{ maxNodes = PayloadValidation.MAX_UNION_BRANCHES }
		)
		maximumBranches[PayloadValidation.MAX_UNION_BRANCHES + 1] = PayloadValidation.boolean()
		assertAuthoringFailure(assertions, function()
			PayloadValidation.union(maximumBranches)
		end)
	end),

	TestHarness.case("charges nested speculative union work to one global budget", function(assertions)
		local nested = PayloadValidation.enum({ "Target" })
		for level = 1, 3 do
			local branches = {}
			for branch = 1, PayloadValidation.MAX_UNION_BRANCHES - 1 do
				branches[branch] = PayloadValidation.enum({ `Miss{level}_{branch}` })
			end
			branches[PayloadValidation.MAX_UNION_BRANCHES] = nested
			nested = PayloadValidation.union(branches)
		end

		local exactWorkUnits = 1 + 3 * PayloadValidation.MAX_UNION_BRANCHES
		assertions.equal(expectSuccess(assertions, nested, "Target", { maxNodes = exactWorkUnits }), "Target")
		expectFailure(assertions, nested, "Target", "OUT_OF_RANGE", "payload", { maxNodes = exactWorkUnits - 1 })
	end),

	TestHarness.case("isolates union branch traversal while preserving owned output", function(assertions)
		local alpha = PayloadValidation.record({
			kind = PayloadValidation.enum({ "Alpha" }),
			value = PayloadValidation.string(8, 1),
		})
		local beta = PayloadValidation.record({
			kind = PayloadValidation.enum({ "Beta" }),
			value = PayloadValidation.integer(0, 8),
		})
		local authored = { kind = "Beta", value = 5 }
		local canonical = expectSuccess(assertions, PayloadValidation.union({ alpha, beta }), authored)
		assertions.notEqual(canonical, authored)
		assertions.equal((canonical :: any).kind, "Beta")
		assertions.equal((canonical :: any).value, 5)
		assertions.isTrue(table.isfrozen(canonical :: any))
	end),

	TestHarness.case("enforces maximum depth and narrower schema depth", function(assertions)
		local acceptedValidator, acceptedValue = nestedRecord(PayloadValidation.MAX_DEPTH)
		expectSuccess(assertions, acceptedValidator, acceptedValue)

		local rejectedValidator, rejectedValue = nestedRecord(PayloadValidation.MAX_DEPTH + 1)
		expectFailure(
			assertions,
			rejectedValidator,
			rejectedValue,
			"OUT_OF_RANGE",
			"payload.child.child.child.child.child.child.child.child.child"
		)

		local narrowValidator, narrowValue = nestedRecord(3)
		expectFailure(
			assertions,
			narrowValidator,
			narrowValue,
			"OUT_OF_RANGE",
			"payload.child.child.child",
			{ maxDepth = 2 }
		)
	end),

	TestHarness.case("enforces total node and per-container field and item caps", function(assertions)
		local booleans = PayloadValidation.array(PayloadValidation.boolean(), 4)
		expectSuccess(assertions, booleans, { true, true }, { maxNodes = 3 })
		expectFailure(assertions, booleans, { true, true, true }, "OUT_OF_RANGE", "payload[3]", { maxNodes = 3 })

		local fieldValidator = PayloadValidation.record({
			alpha = PayloadValidation.boolean(),
			beta = PayloadValidation.boolean(),
			gamma = PayloadValidation.boolean(),
		})
		expectFailure(
			assertions,
			fieldValidator,
			{ alpha = true, beta = true, gamma = true },
			"OUT_OF_RANGE",
			"payload",
			{ maxRecordFields = 2 }
		)

		local itemValidator = PayloadValidation.array(PayloadValidation.boolean(), 4)
		expectFailure(assertions, itemValidator, { true, true, true }, "OUT_OF_RANGE", "payload", { maxArrayItems = 2 })

		local exactNodeFields = {}
		local exactNodeValue = {}
		for _, fieldName in { "a", "b", "c", "d" } do
			exactNodeFields[fieldName] = PayloadValidation.array(PayloadValidation.boolean(), 127)
			local itemCount = if fieldName == "d" then 126 else 127
			local items = {}
			for index = 1, itemCount do
				items[index] = true
			end
			exactNodeValue[fieldName] = items
		end
		expectSuccess(assertions, PayloadValidation.record(exactNodeFields), exactNodeValue)
		table.insert(exactNodeValue.d, true)
		expectFailure(
			assertions,
			PayloadValidation.record(exactNodeFields),
			exactNodeValue,
			"OUT_OF_RANGE",
			"payload.d[127]"
		)
	end),

	TestHarness.case("accepts exact fixed container caps and rejects cap plus one", function(assertions)
		local maximumArray = {}
		for index = 1, PayloadValidation.MAX_ARRAY_ITEMS do
			maximumArray[index] = true
		end
		expectSuccess(
			assertions,
			PayloadValidation.array(PayloadValidation.boolean(), PayloadValidation.MAX_ARRAY_ITEMS),
			maximumArray
		)
		maximumArray[PayloadValidation.MAX_ARRAY_ITEMS + 1] = true
		expectFailure(
			assertions,
			PayloadValidation.array(PayloadValidation.boolean(), PayloadValidation.MAX_ARRAY_ITEMS),
			maximumArray,
			"OUT_OF_RANGE",
			"payload"
		)

		local maximumFields = {}
		local maximumRecord = {}
		for index = 1, PayloadValidation.MAX_RECORD_FIELDS do
			local fieldName = `field{index}`
			maximumFields[fieldName] = PayloadValidation.boolean()
			maximumRecord[fieldName] = true
		end
		expectSuccess(assertions, PayloadValidation.record(maximumFields), maximumRecord)
		maximumFields.field65 = PayloadValidation.boolean()
		assertAuthoringFailure(assertions, function()
			PayloadValidation.record(maximumFields)
		end)
	end),

	TestHarness.case("rejects cycles and repeated table references at stable schema paths", function(assertions)
		local childValidator = PayloadValidation.record({ value = PayloadValidation.string(8, 1) })
		local repeatedValidator = PayloadValidation.record({
			left = childValidator,
			right = childValidator,
		})
		local child = { value = "safe" }
		expectFailure(assertions, repeatedValidator, { left = child, right = child }, "INVALID_TABLE", "payload.right")

		local cycleValidator = PayloadValidation.record({
			child = PayloadValidation.record({ value = PayloadValidation.string(8, 1) }),
		})
		local cycle: any = {}
		cycle.child = cycle
		expectFailure(assertions, cycleValidator, cycle, "INVALID_TABLE", "payload.child")

		local indirectCycleValidator = PayloadValidation.record({
			child = PayloadValidation.record({
				child = PayloadValidation.record({ value = PayloadValidation.boolean() }),
			}),
		})
		local first: any = {}
		local second: any = {}
		first.child = second
		second.child = first
		expectFailure(assertions, indirectCycleValidator, first, "INVALID_TABLE", "payload.child.child")
	end),

	TestHarness.case("rejects hostile tables without invoking attacker metamethods", function(assertions)
		local invocationCount = 0
		local hostileMetatable = {
			__index = function()
				invocationCount += 1
				return "PRIVATE_INDEX"
			end,
			__len = function()
				invocationCount += 1
				return 1
			end,
			__pairs = function()
				invocationCount += 1
				return next, {}, nil
			end,
			__iter = function()
				invocationCount += 1
				return next, {}, nil
			end,
			__eq = function()
				invocationCount += 1
				return true
			end,
			__tostring = function()
				invocationCount += 1
				return "PRIVATE_TOSTRING"
			end,
			__metatable = "locked",
		}
		local hostileRoot = setmetatable({ value = true }, hostileMetatable)
		expectFailure(
			assertions,
			PayloadValidation.record({ value = PayloadValidation.boolean() }),
			hostileRoot,
			"INVALID_TABLE",
			"payload"
		)

		local hostileChild = setmetatable({ value = true }, hostileMetatable)
		expectFailure(
			assertions,
			PayloadValidation.record({ child = PayloadValidation.record({ value = PayloadValidation.boolean() }) }),
			{ child = hostileChild },
			"INVALID_TABLE",
			"payload.child"
		)
		assertions.equal(invocationCount, 0)
	end),

	TestHarness.case("keeps unexpected keys and rejected values out of diagnostics", function(assertions)
		local privateSentinel = "PRIVATE_PAYLOAD_SENTINEL_9cc2"
		local validator = PayloadValidation.record({ allowed = PayloadValidation.string(8, 1) })
		local validationIssue = expectFailure(
			assertions,
			validator,
			{ allowed = "safe", [privateSentinel] = privateSentinel },
			"UNKNOWN_FIELD",
			"payload"
		)
		for _, fieldName in { "code", "path", "message" } do
			assertions.isNil(string.find(validationIssue[fieldName], privateSentinel, 1, true))
		end
		assertGraphDoesNotRetain(assertions, validationIssue, privateSentinel)

		local coercionCount = 0
		local hostileKey = setmetatable({}, {
			__tostring = function()
				coercionCount += 1
				return privateSentinel
			end,
		})
		local hostileIssue = expectFailure(
			assertions,
			validator,
			{ allowed = "safe", [hostileKey] = privateSentinel },
			"INVALID_TABLE",
			"payload"
		)
		assertions.equal(coercionCount, 0)
		assertions.isNil(string.find(hostileIssue.message, privateSentinel, 1, true))
		assertGraphDoesNotRetain(assertions, hostileIssue, hostileKey)

		local firstOrder: { [string]: unknown } = {}
		firstOrder.zeta = 5
		firstOrder.alpha = -1
		local secondOrder: { [string]: unknown } = {}
		secondOrder.alpha = -1
		secondOrder.zeta = 5
		local deterministicValidator = PayloadValidation.record({
			zeta = PayloadValidation.string(8, 1),
			alpha = PayloadValidation.integer(0, 10),
		})
		local firstIssue =
			expectFailure(assertions, deterministicValidator, firstOrder, "OUT_OF_RANGE", "payload.alpha")
		local secondIssue =
			expectFailure(assertions, deterministicValidator, secondOrder, "OUT_OF_RANGE", "payload.alpha")
		assertions.equal(firstIssue.code, secondIssue.code)
		assertions.equal(firstIssue.path, secondIssue.path)
		assertions.equal(firstIssue.message, secondIssue.message)
	end),

	TestHarness.case("validates finite Vector2 Vector3 and CFrame values", function(assertions)
		local vector2 = Vector2.new(1, -2)
		local vector3 = Vector3.new(1, -2, 3)
		local cframe = CFrame.new(1, 2, 3) * CFrame.Angles(0.1, 0.2, 0.3)
		assertions.equal(expectSuccess(assertions, PayloadValidation.vector2(), vector2), vector2)
		assertions.equal(expectSuccess(assertions, PayloadValidation.vector3(), vector3), vector3)
		assertions.equal(expectSuccess(assertions, PayloadValidation.cframe(), cframe), cframe)

		expectFailure(assertions, PayloadValidation.vector2(), vector3, "INVALID_TYPE", "payload")
		expectFailure(assertions, PayloadValidation.vector3(), vector2, "INVALID_TYPE", "payload")
		expectFailure(assertions, PayloadValidation.cframe(), vector3, "INVALID_TYPE", "payload")

		local nonFiniteValues = { 0 / 0, math.huge, -math.huge }
		for _, nonFinite in nonFiniteValues do
			expectFailure(
				assertions,
				PayloadValidation.vector2(),
				Vector2.new(nonFinite, 0),
				"NON_FINITE_NUMBER",
				"payload.X"
			)
			expectFailure(
				assertions,
				PayloadValidation.vector2(),
				Vector2.new(0, nonFinite),
				"NON_FINITE_NUMBER",
				"payload.Y"
			)
			expectFailure(
				assertions,
				PayloadValidation.vector3(),
				Vector3.new(nonFinite, 0, 0),
				"NON_FINITE_NUMBER",
				"payload.X"
			)
			expectFailure(
				assertions,
				PayloadValidation.vector3(),
				Vector3.new(0, nonFinite, 0),
				"NON_FINITE_NUMBER",
				"payload.Y"
			)
			expectFailure(
				assertions,
				PayloadValidation.vector3(),
				Vector3.new(0, 0, nonFinite),
				"NON_FINITE_NUMBER",
				"payload.Z"
			)
		end

		local cframeComponentNames = {
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
		}
		for componentIndex, componentName in cframeComponentNames do
			for _, nonFinite in nonFiniteValues do
				expectFailure(
					assertions,
					PayloadValidation.cframe(),
					cframeWithComponent(componentIndex, nonFinite),
					"NON_FINITE_NUMBER",
					`payload.{componentName}`
				)
			end
		end
	end),

	TestHarness.case("rejects Instances by default and requires an exact server-bound policy", function(assertions)
		local automatedTests = game:GetService("ServerStorage"):FindFirstChild("AutomatedTests")
		assertions.isNotNil(automatedTests)
		local ancestor = Instance.new("Folder")
		ancestor.Name = "PayloadInstancePolicyFixture"
		ancestor.Parent = automatedTests
		local exactTarget = Instance.new("Folder")
		exactTarget.Parent = ancestor
		local part = Instance.new("Part")
		part.Parent = ancestor
		local outsider = Instance.new("Folder")
		outsider.Parent = automatedTests

		expectFailure(assertions, PayloadValidation.string(8), exactTarget, "INVALID_TYPE", "payload")
		local exactPolicy = PayloadValidation.instancePolicy("Folder", ancestor)
		assertions.isTrue(PayloadValidation.isInstancePolicy(exactPolicy))
		assertions.isTrue(table.isfrozen(exactPolicy))
		assertions.equal(expectSuccess(assertions, PayloadValidation.instance(exactPolicy), exactTarget), exactTarget)
		exactTarget.Parent = automatedTests
		expectFailure(assertions, PayloadValidation.instance(exactPolicy), exactTarget, "INVALID_REFERENCE", "payload")
		exactTarget.Parent = ancestor
		expectFailure(assertions, PayloadValidation.instance(exactPolicy), part, "INVALID_TYPE", "payload")
		local outsiderIssue =
			expectFailure(assertions, PayloadValidation.instance(exactPolicy), outsider, "INVALID_REFERENCE", "payload")
		assertGraphDoesNotRetain(assertions, outsiderIssue, outsider)
		local destroyedTarget = Instance.new("Folder")
		destroyedTarget.Parent = ancestor
		destroyedTarget:Destroy()
		expectFailure(
			assertions,
			PayloadValidation.instance(exactPolicy),
			destroyedTarget,
			"INVALID_REFERENCE",
			"payload"
		)

		local subclassPolicy = PayloadValidation.instancePolicy("BasePart", ancestor, true)
		assertions.equal(expectSuccess(assertions, PayloadValidation.instance(subclassPolicy), part), part)
		local exactBasePolicy = PayloadValidation.instancePolicy("BasePart", ancestor)
		expectFailure(assertions, PayloadValidation.instance(exactBasePolicy), part, "INVALID_TYPE", "payload")
		assertAuthoringFailure(assertions, function()
			PayloadValidation.instance({} :: any)
		end)

		ancestor:Destroy()
		expectFailure(assertions, PayloadValidation.instance(exactPolicy), exactTarget, "INVALID_REFERENCE", "payload")
		outsider:Destroy()
	end),

	TestHarness.case("allows schema limits only to narrow fixed technical caps", function(assertions)
		local validator = PayloadValidation.string(PayloadValidation.MAX_STRING_BYTES)
		local narrowSchema = PayloadValidation.schema(validator, { maxStringBytes = 4 })
		assertions.isTrue(narrowSchema:validate("four").ok)
		local failure = narrowSchema:validate("fives")
		assertions.isFalse(failure.ok)
		assertions.equal((failure :: any).error.code, "INVALID_STRING")
		assertions.isTrue(PayloadValidation.schema(PayloadValidation.string(0), { maxStringBytes = 0 }):validate("").ok)
		assertions.isTrue(PayloadValidation.schema(PayloadValidation.array(PayloadValidation.boolean(), 0), {
			maxArrayItems = 0,
		})
			:validate({}).ok)
		assertions.isTrue(PayloadValidation.schema(PayloadValidation.record({}), {
			maxDepth = 0,
			maxRecordFields = 0,
		})
			:validate({}).ok)

		assertAuthoringFailure(assertions, function()
			PayloadValidation.schema(validator, { maxDepth = PayloadValidation.MAX_DEPTH + 1 })
		end)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.schema(validator, { maxNodes = 0 })
		end)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.schema(validator, { unknown = 1 } :: any)
		end)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.schema(
				validator,
				setmetatable({ maxDepth = 2 }, {
					__index = function()
						return 1
					end,
				}) :: any
			)
		end)
	end),

	TestHarness.case("rejects invalid schema composition at construction time", function(assertions)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.array({} :: any, 1)
		end)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.record({ value = {} :: any })
		end)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.optional({} :: any)
		end)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.schema({} :: any)
		end)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.string(PayloadValidation.MAX_STRING_BYTES + 1)
		end)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.array(PayloadValidation.boolean(), PayloadValidation.MAX_ARRAY_ITEMS + 1)
		end)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.enum({ [1] = "Alpha", [3] = "Gamma" } :: any)
		end)
		assertAuthoringFailure(assertions, function()
			PayloadValidation.union({ [1] = PayloadValidation.boolean(), [3] = PayloadValidation.string(8) } :: any)
		end)

		local schemaMetamethodCalls = 0
		local hostileDefinition = setmetatable({ "Alpha" }, {
			__iter = function()
				schemaMetamethodCalls += 1
				return next, {}, nil
			end,
			__index = function()
				schemaMetamethodCalls += 1
				return "PRIVATE_SCHEMA_VALUE"
			end,
		})
		assertAuthoringFailure(assertions, function()
			PayloadValidation.enum(hostileDefinition)
		end)
		assertions.equal(schemaMetamethodCalls, 0)
	end),
})
