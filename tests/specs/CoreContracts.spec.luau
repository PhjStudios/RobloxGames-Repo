--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Ids = require(game:GetService("ReplicatedStorage").Shared.util.Ids)
local Result = require(game:GetService("ReplicatedStorage").Shared.util.Result)
local Validation = require(game:GetService("ReplicatedStorage").Shared.util.Validation)

type Family = {
	kind: string,
	make: (unknown) -> any,
	validate: (unknown) -> any,
}

local FAMILIES: { Family } = table.freeze({
	{ kind = "tower", make = Ids.makeTowerId, validate = Ids.validateTowerId },
	{ kind = "enemy", make = Ids.makeEnemyId, validate = Ids.validateEnemyId },
	{ kind = "map", make = Ids.makeMapId, validate = Ids.validateMapId },
	{ kind = "difficulty", make = Ids.makeDifficultyId, validate = Ids.validateDifficultyId },
	{ kind = "wave", make = Ids.makeWaveId, validate = Ids.validateWaveId },
	{ kind = "banner", make = Ids.makeBannerId, validate = Ids.validateBannerId },
	{ kind = "unit", make = Ids.makeUnitId, validate = Ids.validateUnitId },
	{ kind = "queue", make = Ids.makeQueueId, validate = Ids.validateQueueId },
	{ kind = "match", make = Ids.makeMatchId, validate = Ids.validateMatchId },
	{ kind = "transaction", make = Ids.makeTransactionId, validate = Ids.validateTransactionId },
})

local ID_ERROR_MESSAGES = table.freeze({
	INVALID_TYPE_BODY = "ID body must be a string",
	INVALID_TYPE_COMPLETE = "ID must be a string",
	INVALID_LENGTH_BODY = "ID body must contain at least one character and keep the complete ID within 50 bytes",
	INVALID_LENGTH_COMPLETE = "Complete ID must contain between 1 and 50 bytes",
	INVALID_FORMAT_BODY = "ID body must use lowercase ASCII letters, digits, and separators",
	INVALID_FORMAT_SEPARATOR = "ID separators must appear singly between alphanumeric characters",
	INVALID_FORMAT_PREFIX = "ID must contain its category prefix",
	INVALID_FORMAT_KIND = "ID category prefix is not recognized",
	WRONG_KIND = "ID belongs to a different category",
})

local VALIDATION_CODES = table.freeze({
	"INVALID_TYPE",
	"INVALID_TABLE",
	"INVALID_ARRAY",
	"MISSING_FIELD",
	"UNKNOWN_FIELD",
	"RUNTIME_FIELD_FORBIDDEN",
	"INVALID_ID",
	"DUPLICATE_ID",
	"INVALID_STRING",
	"INVALID_ENUM",
	"NON_FINITE_NUMBER",
	"NOT_INTEGER",
	"OUT_OF_RANGE",
	"EMPTY_COLLECTION",
	"DUPLICATE_VALUE",
	"INVALID_ORDER",
	"INVALID_ASSET_KEY",
	"DUPLICATE_ASSET_KEY",
	"UNKNOWN_ASSET_KEY",
	"WRONG_ASSET_KIND",
	"INVALID_REFERENCE",
	"INVALID_TOTAL",
	"SOURCE_LOAD_FAILED",
	"UNSUPPORTED_VERSION",
})

return TestHarness.suite("core ID Result and Validation contracts", {
	TestHarness.case("constructs and validates every ID family in declared order", function(assertions)
		for _, family in FAMILIES do
			local expected = `{family.kind}:a`
			local made = family.make("a")
			assertions.isTrue(made.ok)
			assertions.equal(made.value, expected)
			assertions.isTrue(table.isfrozen(made))

			local validated = family.validate(expected)
			assertions.isTrue(validated.ok)
			assertions.equal(validated.value, expected)
			assertions.isTrue(table.isfrozen(validated))

			local separated = family.make("alpha.beta-gamma_delta9")
			assertions.isTrue(separated.ok)
			assertions.equal(separated.value, `{family.kind}:alpha.beta-gamma_delta9`)
		end
	end),

	TestHarness.case("enforces exact ID byte limits for every family", function(assertions)
		assertions.equal(Ids.MAX_ID_LENGTH, 50)
		for _, family in FAMILIES do
			local maximumBodyLength = Ids.MAX_ID_LENGTH - #family.kind - 1
			local maximumBody = string.rep("a", maximumBodyLength)
			local exactId = `{family.kind}:{maximumBody}`
			assertions.equal(#exactId, Ids.MAX_ID_LENGTH)

			local exactConstruction = family.make(maximumBody)
			assertions.isTrue(exactConstruction.ok)
			assertions.equal(exactConstruction.value, exactId)
			assertions.isTrue(family.validate(exactId).ok)

			local oversizedConstruction = family.make(maximumBody .. "a")
			assertions.isFalse(oversizedConstruction.ok)
			assertions.equal(oversizedConstruction.error.code, "INVALID_LENGTH")
			assertions.equal(oversizedConstruction.error.expectedKind, family.kind)
			assertions.equal(oversizedConstruction.error.message, ID_ERROR_MESSAGES.INVALID_LENGTH_BODY)

			local oversizedValidation = family.validate(exactId .. "a")
			assertions.isFalse(oversizedValidation.ok)
			assertions.equal(oversizedValidation.error.code, "INVALID_LENGTH")
			assertions.equal(oversizedValidation.error.expectedKind, family.kind)
			assertions.equal(oversizedValidation.error.message, ID_ERROR_MESSAGES.INVALID_LENGTH_COMPLETE)
		end
	end),

	TestHarness.case("rejects malformed ID types without disclosing values", function(assertions)
		local privateSentinel = "PRIVATE_SENTINEL_8f41"
		local values: { unknown } = {
			true,
			42,
			{},
			setmetatable({}, {
				__tostring = function()
					return privateSentinel
				end,
			}),
			function() end,
			coroutine.create(function() end),
		}

		for _, family in FAMILIES do
			local nilBody = family.make(nil)
			assertions.isFalse(nilBody.ok)
			assertions.equal(nilBody.error.code, "INVALID_TYPE")
			assertions.equal(nilBody.error.message, ID_ERROR_MESSAGES.INVALID_TYPE_BODY)
			assertions.notEqual(nilBody.error.message, privateSentinel)

			local nilId = family.validate(nil)
			assertions.isFalse(nilId.ok)
			assertions.equal(nilId.error.code, "INVALID_TYPE")
			assertions.equal(nilId.error.message, ID_ERROR_MESSAGES.INVALID_TYPE_COMPLETE)

			for _, value in values do
				local made = family.make(value)
				assertions.isFalse(made.ok)
				assertions.equal(made.error.code, "INVALID_TYPE")
				assertions.equal(made.error.expectedKind, family.kind)
				assertions.equal(made.error.message, ID_ERROR_MESSAGES.INVALID_TYPE_BODY)
				assertions.notEqual(made.error.message, privateSentinel)

				local validated = family.validate(value)
				assertions.isFalse(validated.ok)
				assertions.equal(validated.error.code, "INVALID_TYPE")
				assertions.equal(validated.error.expectedKind, family.kind)
				assertions.equal(validated.error.message, ID_ERROR_MESSAGES.INVALID_TYPE_COMPLETE)
				assertions.notEqual(validated.error.message, privateSentinel)
			end
		end
	end),

	TestHarness.case("rejects malformed ID grammar with stable errors", function(assertions)
		local family = FAMILIES[1]
		local invalidBodies = {
			{ value = "", code = "INVALID_LENGTH", message = ID_ERROR_MESSAGES.INVALID_LENGTH_BODY },
			{ value = "Upper", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_BODY },
			{ value = "ant bee", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_BODY },
			{ value = "caf\u{00E9}", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_BODY },
			{ value = "a:b", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_BODY },
			{ value = "-ant", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_SEPARATOR },
			{ value = "ant_", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_SEPARATOR },
			{ value = "ant..bee", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_SEPARATOR },
			{ value = "ant-_bee", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_SEPARATOR },
		}
		for _, fixture in invalidBodies do
			local result = family.make(fixture.value)
			assertions.isFalse(result.ok)
			assertions.equal(result.error.code, fixture.code)
			assertions.equal(result.error.message, fixture.message)
			assertions.equal(result.error.expectedKind, family.kind)
		end

		local malformedIds = {
			{ value = "", code = "INVALID_LENGTH", message = ID_ERROR_MESSAGES.INVALID_LENGTH_COMPLETE },
			{ value = "tower", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_PREFIX },
			{ value = "unknown:ant", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_KIND },
			{ value = "Tower:ant", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_KIND },
			{ value = "tower:", code = "INVALID_LENGTH", message = ID_ERROR_MESSAGES.INVALID_LENGTH_BODY },
			{ value = "tower:ant:bee", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_BODY },
			{ value = "tower:ant__bee", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_SEPARATOR },
			{ value = "enemy:Upper", code = "INVALID_FORMAT", message = ID_ERROR_MESSAGES.INVALID_FORMAT_BODY },
		}
		for _, fixture in malformedIds do
			local result = family.validate(fixture.value)
			assertions.isFalse(result.ok)
			assertions.equal(result.error.code, fixture.code)
			assertions.equal(result.error.message, fixture.message)
			assertions.equal(result.error.expectedKind, family.kind)
		end
	end),

	TestHarness.case("rejects every cross family ID pairing", function(assertions)
		for sourceIndex, sourceFamily in FAMILIES do
			local foreignId = `{sourceFamily.kind}:valid`
			for targetIndex, targetFamily in FAMILIES do
				local result = targetFamily.validate(foreignId)
				if sourceIndex == targetIndex then
					assertions.isTrue(result.ok)
					assertions.equal(result.value, foreignId)
				else
					assertions.isFalse(result.ok)
					assertions.equal(result.error.code, "WRONG_KIND")
					assertions.equal(result.error.expectedKind, targetFamily.kind)
					assertions.equal(result.error.message, ID_ERROR_MESSAGES.WRONG_KIND)
				end
			end
		end
	end),

	TestHarness.case("freezes ID modules failures and error records", function(assertions)
		assertions.isTrue(table.isfrozen(Ids))
		local failure = Ids.validateTowerId("enemy:valid")
		assertions.isFalse(failure.ok)
		assertions.isTrue(table.isfrozen(failure))
		assertions.isTrue(table.isfrozen(failure.error))

		local changedEnvelope = pcall(function()
			(failure :: any).ok = true
		end)
		local changedError = pcall(function()
			(failure.error :: any).message = "changed"
		end)
		local changedModule = pcall(function()
			(Ids :: any).MAX_ID_LENGTH = 100
		end)
		assertions.isFalse(changedEnvelope)
		assertions.isFalse(changedError)
		assertions.isFalse(changedModule)
	end),

	TestHarness.case("constructs immutable Result branches with owned payloads", function(assertions)
		assertions.isTrue(table.isfrozen(Result))
		local successPayload = { count = 1 }
		local failurePayload = { code = "EXPECTED" }
		local success = Result.ok(successPayload)
		local failure = Result.err(failurePayload)

		assertions.isTrue(success.ok)
		assertions.equal(success.value, successPayload)
		assertions.isFalse(failure.ok)
		assertions.equal(failure.error, failurePayload)
		assertions.isTrue(table.isfrozen(success))
		assertions.isTrue(table.isfrozen(failure))
		assertions.isFalse(table.isfrozen(successPayload))
		assertions.isFalse(table.isfrozen(failurePayload))

		successPayload.count = 2
		failurePayload.code = "CALLER_OWNED"
		assertions.equal(success.value.count, 2)
		assertions.equal(failure.error.code, "CALLER_OWNED")

		local changedSuccess = pcall(function()
			(success :: any).ok = false
		end)
		local changedFailure = pcall(function()
			(failure :: any).error = nil
		end)
		local changedModule = pcall(function()
			(Result :: any).ok = nil
		end)
		assertions.isFalse(changedSuccess)
		assertions.isFalse(changedFailure)
		assertions.isFalse(changedModule)
	end),

	TestHarness.case("keeps Result branch semantics for nil and repeated construction", function(assertions)
		local nilSuccess = Result.ok(nil)
		local nilFailure = Result.err(nil)
		assertions.isTrue(nilSuccess.ok)
		assertions.isNil(nilSuccess.value)
		assertions.isFalse(nilFailure.ok)
		assertions.isNil(nilFailure.error)

		local first = Result.ok("same")
		local second = Result.ok("same")
		assertions.notEqual(first, second)
		assertions.equal(first.value, second.value)
		assertions.isTrue(if first.ok then first.value == "same" else false)
		assertions.isTrue(if nilFailure.ok then false else nilFailure.error == nil)
	end),

	TestHarness.case("constructs every Validation issue code with stable fields", function(assertions)
		assertions.isTrue(table.isfrozen(Validation))
		for _, code in VALIDATION_CODES do
			local issue = Validation.issue(code :: any, { "catalogs", "entries", 2 }, "Static diagnostic")
			assertions.equal(issue.code, code)
			assertions.equal(issue.path, "catalogs.entries[2]")
			assertions.equal(issue.pathSegments[1], "catalogs")
			assertions.equal(issue.pathSegments[2], "entries")
			assertions.equal(issue.pathSegments[3], 2)
			assertions.equal(issue.message, "Static diagnostic")
			assertions.isNil(issue.causeCode)
			assertions.isNil(issue.relatedPath)
			assertions.isNil(issue.actualType)
			assertions.isTrue(table.isfrozen(issue))
			assertions.isTrue(table.isfrozen(issue.pathSegments))
		end
	end),

	TestHarness.case("constructs typed caused and related Validation issues", function(assertions)
		local typed = Validation.issueWithType("INVALID_TYPE", { "tower", "levels", 1 }, "Expected table", {})
		assertions.equal(typed.code, "INVALID_TYPE")
		assertions.equal(typed.path, "tower.levels[1]")
		assertions.equal(typed.message, "Expected table")
		assertions.equal(typed.actualType, "table")
		assertions.isNil(typed.causeCode)
		assertions.isNil(typed.relatedPath)

		local caused = Validation.issueWithCause("INVALID_ID", { "tower", "id" }, "Invalid ID", "WRONG_KIND")
		assertions.equal(caused.code, "INVALID_ID")
		assertions.equal(caused.path, "tower.id")
		assertions.equal(caused.causeCode, "WRONG_KIND")
		assertions.isNil(caused.actualType)
		assertions.isNil(caused.relatedPath)

		local related =
			Validation.issueWithRelated("DUPLICATE_ID", { "towers", 2, "id" }, "Duplicate ID", "towers[1].id")
		assertions.equal(related.code, "DUPLICATE_ID")
		assertions.equal(related.path, "towers[2].id")
		assertions.equal(related.relatedPath, "towers[1].id")
		assertions.isNil(related.actualType)
		assertions.isNil(related.causeCode)
	end),

	TestHarness.case("renders appends and sanitizes Validation paths", function(assertions)
		local original = { "catalogs", "towers", 2 }
		local appended = Validation.appendPath(original, "levels")
		assertions.equal(Validation.renderPath({}), "")
		assertions.equal(Validation.renderPath({ 1, "field", 3 }), "[1].field[3]")
		assertions.equal(Validation.renderPath(appended), "catalogs.towers[2].levels")
		assertions.equal(#original, 3)
		assertions.equal(original[3], 2)

		local invalidExisting = { "root", {} } :: any
		local sanitizedAppend = Validation.appendPath(invalidExisting, "leaf")
		assertions.equal(sanitizedAppend[2], "<invalid>")
		assertions.equal(Validation.renderPath(sanitizedAppend), "root.<invalid>.leaf")

		local invalidIssuePath = { "root", {}, true, "leaf" } :: any
		local issue = Validation.issue("INVALID_TYPE", invalidIssuePath, "Static diagnostic")
		assertions.equal(issue.path, "root.<invalid>.<invalid>.leaf")
		assertions.equal(issue.pathSegments[2], "<invalid>")
		assertions.equal(issue.pathSegments[3], "<invalid>")
		invalidIssuePath[1] = "changed"
		assertions.equal(issue.pathSegments[1], "root")

		local changedIssue = pcall(function()
			(issue :: any).path = "changed"
		end)
		local changedPath = pcall(function()
			(issue.pathSegments :: any)[1] = "changed"
		end)
		assertions.isFalse(changedIssue)
		assertions.isFalse(changedPath)
	end),

	TestHarness.case("reports Validation types without coercing private values", function(assertions)
		local privateSentinel = "PRIVATE_SENTINEL_d917"
		local coercionCount = 0
		local privateValue = setmetatable({}, {
			__tostring = function()
				coercionCount += 1
				return privateSentinel
			end,
		})
		local issue = Validation.issueWithType(
			"INVALID_TYPE",
			{ "definitions", "value" },
			"Expected a supported type",
			privateValue
		)
		assertions.equal(issue.actualType, "table")
		assertions.equal(issue.message, "Expected a supported type")
		assertions.equal(issue.path, "definitions.value")
		assertions.equal(coercionCount, 0)
		assertions.notEqual(issue.message, privateSentinel)
		assertions.notEqual(issue.path, privateSentinel)
	end),
})
