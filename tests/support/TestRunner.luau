--!strict

local TestHarness = require(script.Parent.TestHarness)
local RobloxAdapter = require(script.Parent.RobloxAdapter)

export type Selection = "normal" | "assertion" | "malformed" | "malformed-root" | "module-load" | "zero"

export type RunResult = {
	exitCode: number,
	suiteCount: number,
	testCount: number,
	passedCount: number,
	failedCount: number,
}

type LoadedSuite = {
	definition: TestHarness.Suite,
	modulePath: string,
}

local TestRunner = {}

local SPEC_SUFFIX = ".spec"
local SAFE_NAME_PATTERN = "^[A-Za-z0-9][A-Za-z0-9 _.:-]*$"
local MAX_NAME_BYTES = 120

local function record(kind: string, fields: { [string]: string | number })
	local names = {}
	for name in fields do
		table.insert(names, name)
	end
	table.sort(names)

	local output = `[ATD_TEST][{kind}]`
	for _, name in names do
		output ..= `[{name}={fields[name]}]`
	end
	print(output)
end

local function isSafeName(value: unknown): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= MAX_NAME_BYTES
		and string.match(value, SAFE_NAME_PATTERN) ~= nil
end

local function safePath(instance: Instance): string
	local path = instance:GetFullName()
	if #path > 512 or string.match(path, "^[A-Za-z0-9_.:-]+$") == nil then
		return "<unsafe>"
	end
	return path
end

local function isDenseArray(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end

	local count = 0
	local maximumIndex = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end
		count += 1
		maximumIndex = math.max(maximumIndex, key)
	end

	return maximumIndex == count
end

local function hasOnlyFields(value: { [any]: unknown }, allowedFields: { [string]: boolean }): boolean
	for key in next, value do
		if type(key) ~= "string" or allowedFields[key] ~= true then
			return false
		end
	end
	return true
end

local function validateSuite(value: unknown): (TestHarness.Suite?, string?)
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil, "MALFORMED_SUITE"
	end

	local suite = value :: { [any]: unknown }
	if not hasOnlyFields(suite, { name = true, cases = true }) or not isSafeName(suite.name) then
		return nil, "MALFORMED_SUITE"
	end
	if not isDenseArray(suite.cases) or rawlen(suite.cases :: { unknown }) == 0 then
		return nil, "MALFORMED_CASES"
	end

	local caseNames: { [string]: boolean } = {}
	for index = 1, rawlen(suite.cases :: { unknown }) do
		local rawCase = rawget(suite.cases :: { unknown }, index)
		if type(rawCase) ~= "table" or getmetatable(rawCase :: any) ~= nil then
			return nil, "MALFORMED_CASE"
		end
		local testCase = rawCase :: { [any]: unknown }
		if
			not hasOnlyFields(testCase, { name = true, run = true })
			or not isSafeName(testCase.name)
			or type(testCase.run) ~= "function"
		then
			return nil, "MALFORMED_CASE"
		end
		local caseName = testCase.name :: string
		if caseNames[caseName] then
			return nil, "DUPLICATE_CASE"
		end
		caseNames[caseName] = true
	end

	return value :: TestHarness.Suite, nil
end

local function getRoot(dataModel: DataModel, selection: Selection): Instance?
	local serverStorage = dataModel:GetService("ServerStorage")
	if selection == "normal" then
		local automatedTests = serverStorage:FindFirstChild("AutomatedTests")
		return if automatedTests == nil then nil else automatedTests:FindFirstChild("Specs")
	end

	local controls = serverStorage:FindFirstChild("NegativeControls")
	if controls == nil then
		return nil
	end
	if selection == "assertion" then
		return controls:FindFirstChild("Assertion")
	elseif selection == "malformed" then
		return controls:FindFirstChild("MalformedDiscovery")
	elseif selection == "malformed-root" then
		return controls:FindFirstChild("MalformedRoot")
	elseif selection == "module-load" then
		return controls:FindFirstChild("ModuleLoad")
	else
		return controls:FindFirstChild("ZeroDiscovery")
	end
end

local function discover(root: Instance): ({ ModuleScript }?, string?, string?)
	local modules: { ModuleScript } = {}
	local descendants = root:GetDescendants()
	table.sort(descendants, function(left, right)
		local leftPath = left:GetFullName()
		local rightPath = right:GetFullName()
		if leftPath == rightPath then
			return left.ClassName < right.ClassName
		end
		return leftPath < rightPath
	end)

	local previousPath: string? = nil
	for _, descendant in descendants do
		local path = safePath(descendant)
		if path == previousPath then
			return nil, "DUPLICATE_DISCOVERY_PATH", path
		end
		previousPath = path

		if descendant:IsA("ModuleScript") then
			if string.sub(descendant.Name, -#SPEC_SUFFIX) ~= SPEC_SUFFIX then
				return nil, "MISNAMED_SPEC", path
			end
			table.insert(modules, descendant :: ModuleScript)
		elseif not descendant:IsA("Folder") then
			local code = if descendant:IsA("Script") or descendant:IsA("LocalScript")
				then "UNEXPECTED_SOURCE_CONTAINER"
				else "UNEXPECTED_DISCOVERY_INSTANCE"
			return nil, code, path
		end
	end
	table.sort(modules, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)
	return modules, nil, nil
end

function TestRunner.run(dataModel: DataModel, selection: Selection): RunResult
	local root = getRoot(dataModel, selection)
	if root == nil then
		record("FAIL", {
			category = "discovery",
			code = "ROOT_MISSING",
			path = "ServerStorage",
		})
		return { exitCode = 2, suiteCount = 0, testCount = 0, passedCount = 0, failedCount = 0 }
	end
	if not root:IsA("Folder") then
		record("FAIL", {
			category = "discovery",
			code = "ROOT_WRONG_CLASS",
			path = safePath(root),
		})
		return { exitCode = 2, suiteCount = 0, testCount = 0, passedCount = 0, failedCount = 0 }
	end

	local modules, discoveryError, discoveryPath = discover(root)
	if modules == nil then
		record("FAIL", {
			category = "discovery",
			code = discoveryError :: string,
			path = discoveryPath :: string,
		})
		return { exitCode = 2, suiteCount = 0, testCount = 0, passedCount = 0, failedCount = 0 }
	end
	if #modules == 0 then
		record("FAIL", {
			category = "discovery",
			code = "ZERO_TESTS",
			path = safePath(root),
		})
		return { exitCode = 2, suiteCount = 0, testCount = 0, passedCount = 0, failedCount = 0 }
	end

	local loadedSuites: { LoadedSuite } = {}
	local suiteNames: { [string]: boolean } = {}
	local testCount = 0
	for _, module in modules do
		local loaded, rawSuite = pcall(require, module)
		local modulePath = safePath(module)
		if not loaded then
			local loaderFailure = RobloxAdapter.getLoaderFailure(rawSuite)
			record("FAIL", {
				category = "module-load",
				code = if loaderFailure == nil then "MODULE_LOAD_FAILED" else loaderFailure.code,
				path = if loaderFailure == nil then modulePath else loaderFailure.path,
			})
			return { exitCode = 2, suiteCount = 0, testCount = 0, passedCount = 0, failedCount = 0 }
		end

		local suite, suiteError = validateSuite(rawSuite)
		if suite == nil then
			record("FAIL", {
				category = "discovery",
				code = suiteError :: string,
				path = modulePath,
			})
			return { exitCode = 2, suiteCount = 0, testCount = 0, passedCount = 0, failedCount = 0 }
		end
		if suiteNames[suite.name] then
			record("FAIL", {
				category = "discovery",
				code = "DUPLICATE_SUITE",
				path = modulePath,
			})
			return { exitCode = 2, suiteCount = 0, testCount = 0, passedCount = 0, failedCount = 0 }
		end
		suiteNames[suite.name] = true
		testCount += #suite.cases
		table.insert(loadedSuites, { definition = suite, modulePath = modulePath })
		record("DISCOVER", {
			cases = #suite.cases,
			path = modulePath,
			suite = suite.name,
		})
	end

	local passedCount = 0
	local failedCount = 0
	local assertions = TestHarness.getAssertions()
	for _, loadedSuite in loadedSuites do
		for _, testCase in loadedSuite.definition.cases do
			local passed, failureValue = pcall(testCase.run, assertions)
			if passed then
				passedCount += 1
				record("PASS", {
					case = testCase.name,
					path = loadedSuite.modulePath,
					suite = loadedSuite.definition.name,
				})
			else
				failedCount += 1
				local assertionFailure = TestHarness.getFailure(failureValue)
				if assertionFailure == nil then
					record("FAIL", {
						case = testCase.name,
						category = "case",
						code = "CASE_ERROR",
						path = loadedSuite.modulePath,
						suite = loadedSuite.definition.name,
					})
				else
					record("FAIL", {
						assertion = assertionFailure.assertion,
						case = testCase.name,
						category = "assertion",
						code = assertionFailure.code,
						path = loadedSuite.modulePath,
						suite = loadedSuite.definition.name,
					})
				end
			end
		end
	end

	local exitCode = if failedCount == 0 then 0 else 1
	record("SUMMARY", {
		failed = failedCount,
		passed = passedCount,
		status = if exitCode == 0 then "PASS" else "FAIL",
		suites = #loadedSuites,
		tests = testCount,
	})
	return {
		exitCode = exitCode,
		suiteCount = #loadedSuites,
		testCount = testCount,
		passedCount = passedCount,
		failedCount = failedCount,
	}
end

return table.freeze(TestRunner)
