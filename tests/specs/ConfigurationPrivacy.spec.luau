--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Fixtures = require(script.Parent.Parent.Fixtures.ConfigurationFixtures)

local Shared = game:GetService("ReplicatedStorage").Shared
local AssetSchema = require(Shared.config.AssetSchema)
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local SettingsSchema = require(Shared.config.SettingsSchema)
local Ids = require(Shared.util.Ids)

type Assertions = TestHarness.Assertions

local FAILURE_FIELDS = table.freeze({
	error = true,
	ok = true,
})
local ID_ERROR_FIELDS = table.freeze({
	code = true,
	expectedKind = true,
	message = true,
})
local ISSUE_FIELDS = table.freeze({
	actualType = true,
	causeCode = true,
	code = true,
	message = true,
	path = true,
	pathSegments = true,
	relatedPath = true,
})
local REPORT_FIELDS = table.freeze({
	blockedFamilies = true,
	firstIssue = true,
	issues = true,
})

local function assertOnlyFields(
	assertions: Assertions,
	value: any,
	allowedFields: { [string]: boolean },
	expectedCount: number
)
	assertions.equal(type(value), "table")
	if type(value) ~= "table" then
		return
	end
	assertions.isNil(getmetatable(value))

	local count = 0
	for key in next, value do
		count += 1
		assertions.equal(type(key), "string")
		if type(key) == "string" then
			assertions.isTrue(allowedFields[key] == true)
		end
	end
	assertions.equal(count, expectedCount)
end

local function recursivelyExcludes(
	value: unknown,
	forbiddenIdentities: { [any]: boolean },
	privateSentinel: string,
	seen: { [any]: boolean }
): boolean
	if type(value) == "string" then
		return string.find(value, privateSentinel, 1, true) == nil
	elseif type(value) ~= "table" then
		return true
	end

	local tableValue = value :: { [any]: unknown }
	if getmetatable(tableValue) ~= nil then
		return false
	end
	if rawget(forbiddenIdentities, tableValue) == true then
		return false
	end
	if rawget(seen, tableValue) == true then
		return true
	end
	seen[tableValue] = true
	for key, child in next, tableValue do
		if
			not recursivelyExcludes(key, forbiddenIdentities, privateSentinel, seen)
			or not recursivelyExcludes(child, forbiddenIdentities, privateSentinel, seen)
		then
			return false
		end
	end
	return true
end

local function assertPrivacySafe(
	assertions: Assertions,
	value: unknown,
	forbiddenIdentities: { [any]: boolean },
	privateSentinel: string
)
	assertions.isTrue(recursivelyExcludes(value, forbiddenIdentities, privateSentinel, {}))
end

local function expectIssue(assertions: Assertions, result: any, code: string, path: string): any
	assertions.isFalse(result.ok)
	if result.ok then
		return nil
	end
	assertOnlyFields(assertions, result, FAILURE_FIELDS, 2)
	local issue = result.error
	assertions.equal(issue.code, code)
	assertions.equal(issue.path, path)
	assertions.isTrue(table.isfrozen(result))
	assertions.isTrue(table.isfrozen(issue))
	assertions.isTrue(table.isfrozen(issue.pathSegments))
	return issue
end

local function runPrivateSourceFailure(fixtureName: string, privateSentinel: string): any
	local configClone = Shared.config:Clone()
	local completed, result = pcall(function()
		configClone.Name = fixtureName
		configClone.Parent = Shared

		local validatorSource = configClone:FindFirstChild("ConfigurationValidator")
		local assetsSource = configClone:FindFirstChild("Assets")
		if
			validatorSource == nil
			or not validatorSource:IsA("ModuleScript")
			or assetsSource == nil
			or not assetsSource:IsA("ModuleScript")
		then
			error("source privacy fixture unavailable", 0)
		end

		local clonedValidator = require(validatorSource)
		assetsSource.Source = `--!strict\nerror("{privateSentinel}", 0)`
		return (clonedValidator :: any).validateLoaded()
	end)
	local destroyed = pcall(function()
		configClone:Destroy()
	end)
	if not completed or not destroyed then
		error("disposable source privacy fixture failed", 0)
	end
	return result
end

return TestHarness.suite("configuration privacy and malformed boundaries", {
	TestHarness.case("restricts ID and ordinary issue shapes without retaining rejected values", function(assertions)
		local privateSentinel = "PRIVATE_REJECTED_VALUE_6301"
		local coercionCount = 0
		local privateValue = setmetatable({ secret = privateSentinel }, {
			__tostring = function()
				coercionCount += 1
				return privateSentinel
			end,
		})
		local forbiddenIdentities = { [privateValue] = true }

		local idResult = Ids.validateTowerId(privateValue)
		assertions.isFalse(idResult.ok)
		if idResult.ok then
			return
		end
		assertOnlyFields(assertions, idResult, FAILURE_FIELDS, 2)
		assertOnlyFields(assertions, idResult.error, ID_ERROR_FIELDS, 3)
		assertions.equal(idResult.error.code, "INVALID_TYPE")
		assertions.equal(idResult.error.expectedKind, "tower")
		assertPrivacySafe(assertions, idResult, forbiddenIdentities, privateSentinel)

		local settings = Fixtures.validSources().defaultSettings
		settings.masterVolume = privateValue
		local issueResult = SettingsSchema.validateDefaults(settings)
		local issue = expectIssue(assertions, issueResult, "INVALID_TYPE", "DefaultSettings.masterVolume")
		assertOnlyFields(assertions, issue, ISSUE_FIELDS, 5)
		assertions.equal(issue.actualType, "table")
		assertPrivacySafe(assertions, issueResult, forbiddenIdentities, privateSentinel)
		assertions.equal(coercionCount, 0)
	end),
	TestHarness.case("restricts aggregate report shapes without retaining rejected catalogs", function(assertions)
		local privateSentinel = "PRIVATE_REJECTED_CATALOG_9472"
		local privateValue = { secret = privateSentinel }
		local privateCatalog = {
			[2] = privateValue,
			privateEntry = privateSentinel,
		}
		local sources = Fixtures.validSources()
		sources.assets = privateCatalog
		sources.defaultSettings.masterVolume = privateValue
		local forbiddenIdentities = {
			[privateValue] = true,
			[privateCatalog] = true,
			[sources] = true,
		}

		local result = ConfigurationValidator.validate(sources)
		assertions.isFalse(result.ok)
		if result.ok then
			return
		end
		assertOnlyFields(assertions, result, FAILURE_FIELDS, 2)
		assertOnlyFields(assertions, result.error, REPORT_FIELDS, 3)
		assertions.isTrue(table.isfrozen(result))
		assertions.isTrue(table.isfrozen(result.error))
		assertions.isTrue(table.isfrozen(result.error.issues))
		assertions.isTrue(table.isfrozen(result.error.blockedFamilies))
		assertions.equal(#result.error.issues, 2)
		assertions.equal(result.error.firstIssue, result.error.issues[1])
		assertions.equal(result.error.issues[1].code, "INVALID_ARRAY")
		assertions.equal(result.error.issues[1].path, "Assets")
		assertions.equal(result.error.issues[2].code, "INVALID_TYPE")
		assertions.equal(result.error.issues[2].path, "DefaultSettings.masterVolume")
		assertOnlyFields(assertions, result.error.issues[1], ISSUE_FIELDS, 4)
		assertOnlyFields(assertions, result.error.issues[2], ISSUE_FIELDS, 5)
		assertPrivacySafe(assertions, result, forbiddenIdentities, privateSentinel)
	end),
	TestHarness.case("contains arbitrary source errors in an exact privacy-safe report", function(assertions)
		local fixtureName = "ConfigurationPrivateSourceFailureFixture"
		local privateSentinel = "PRIVATE_CAUGHT_SOURCE_ERROR_3187"
		local result = runPrivateSourceFailure(fixtureName, privateSentinel)
		assertions.isFalse(result.ok)
		if result.ok then
			return
		end

		assertOnlyFields(assertions, result, FAILURE_FIELDS, 2)
		assertOnlyFields(assertions, result.error, REPORT_FIELDS, 3)
		assertions.equal(#result.error.issues, 1)
		local issue = result.error.issues[1]
		assertOnlyFields(assertions, issue, ISSUE_FIELDS, 4)
		assertions.equal(issue.code, "SOURCE_LOAD_FAILED")
		assertions.equal(issue.path, "Assets")
		assertions.equal(issue.message, "Authored configuration source failed to load")
		assertions.equal(result.error.firstIssue, issue)
		assertions.isTrue(table.isfrozen(result))
		assertions.isTrue(table.isfrozen(result.error))
		assertions.isTrue(table.isfrozen(result.error.issues))
		assertions.isTrue(table.isfrozen(result.error.blockedFamilies))
		assertions.isTrue(table.isfrozen(issue))
		assertions.isTrue(table.isfrozen(issue.pathSegments))
		assertPrivacySafe(assertions, result, {}, privateSentinel)
		assertions.isNil(Shared:FindFirstChild(fixtureName))
	end),
	TestHarness.case("rejects metatable and sparse roots without invoking hooks", function(assertions)
		local privateSentinel = "PRIVATE_METATABLE_HOOK_4420"
		local hookCount = 0
		local metatableRoot = setmetatable({}, {
			__index = function()
				hookCount += 1
				return privateSentinel
			end,
			__pairs = function()
				hookCount += 1
				return next, {}, nil
			end,
		})
		local metatableIssue =
			expectIssue(assertions, AssetSchema.validateManifest(metatableRoot), "INVALID_ARRAY", "Assets")
		assertOnlyFields(assertions, metatableIssue, ISSUE_FIELDS, 4)
		assertPrivacySafe(assertions, metatableIssue, { [metatableRoot] = true }, privateSentinel)

		local sparseRoot = {
			[2] = { key = "fixture.asset", kind = "Icon" },
		}
		local sparseIssue = expectIssue(assertions, AssetSchema.validateManifest(sparseRoot), "INVALID_ARRAY", "Assets")
		assertOnlyFields(assertions, sparseIssue, ISSUE_FIELDS, 4)
		assertions.equal(hookCount, 0)
	end),
	TestHarness.case("rejects missing required and unknown fields with exact paths", function(assertions)
		local privateSentinel = "PRIVATE_UNKNOWN_FIELD_VALUE_1084"
		local settings = Fixtures.validSources().defaultSettings
		settings.version = nil
		local missingIssue = expectIssue(
			assertions,
			SettingsSchema.validateDefaults(settings),
			"MISSING_FIELD",
			"DefaultSettings.version"
		)
		assertOnlyFields(assertions, missingIssue, ISSUE_FIELDS, 4)

		settings = Fixtures.validSources().defaultSettings
		settings.privateData = privateSentinel
		local unknownIssue = expectIssue(
			assertions,
			SettingsSchema.validateDefaults(settings),
			"UNKNOWN_FIELD",
			"DefaultSettings.privateData"
		)
		assertOnlyFields(assertions, unknownIssue, ISSUE_FIELDS, 4)
		assertPrivacySafe(assertions, unknownIssue, {}, privateSentinel)
	end),
})
