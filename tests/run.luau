--!strict

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local taskLibrary = require("@lune/task")

type Selection = "normal" | "assertion" | "malformed" | "malformed-root" | "module-load" | "zero"

type SelectionFilter = {
	specs: { string },
	groups: { string },
}

type RunOptions = {
	selection: Selection,
	simulateCrash: boolean,
	filter: SelectionFilter?,
	builtPlacePath: string?,
}

type ModuleRecord = {
	state: "Loading" | "Loaded" | "Failed",
	value: unknown,
}

type LoaderFailure = {
	code: string,
	path: string,
}

local EXIT_RUNNER_FAILURE = 3
local PROJECT_PATH = "test.project.json"
local BUILD_DIRECTORY = "build"
local OUTPUT_PATH = "build/phase05-test-runtime.rbxlx"
local MAX_SELECTOR_BYTES = 64
local MAX_BUILT_PLACE_PATH_BYTES = 240

local ownsOutput = false
local createdBuildDirectory = false

local function hasRequiredLoaderGlobals(): boolean
	for _, value in
		{
			roblox.CFrame,
			roblox.Color3,
			roblox.Enum,
			roblox.Instance,
			roblox.UDim,
			roblox.UDim2,
			roblox.Vector2,
			roblox.Vector3,
		}
	do
		if value == nil then
			return false
		end
	end
	return true
end

local function record(code: string, category: string, path: string)
	print(`[ATD_TEST][FAIL][category={category}][code={code}][path={path}]`)
end

local function isSafeSelector(value: unknown): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= MAX_SELECTOR_BYTES
		and string.match(value, "^[A-Za-z][A-Za-z0-9]*$") ~= nil
end

local function isSafeBuiltPlacePath(value: unknown): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= MAX_BUILT_PLACE_PATH_BYTES
		and string.match(value, "^build/[A-Za-z0-9][A-Za-z0-9_./-]*%.rbxlx$") ~= nil
		and string.find(value, "..", 1, true) == nil
		and string.find(value, "//", 1, true) == nil
end

local function parseSelection(): RunOptions?
	if #process.args == 0 then
		return {
			selection = "normal",
			simulateCrash = false,
			filter = nil,
			builtPlacePath = nil,
		}
	end

	if process.args[1] == "--control" then
		if #process.args ~= 2 then
			return nil
		end
		local control = process.args[2]
		if
			control == "zero"
			or control == "assertion"
			or control == "malformed"
			or control == "malformed-root"
			or control == "module-load"
		then
			return {
				selection = control :: Selection,
				simulateCrash = false,
				filter = nil,
				builtPlacePath = nil,
			}
		elseif control == "runner-crash" then
			return {
				selection = "normal",
				simulateCrash = true,
				filter = nil,
				builtPlacePath = nil,
			}
		end
		return nil
	end

	local specs: { string } = {}
	local groups: { string } = {}
	local seenSpecs: { [string]: boolean } = {}
	local seenGroups: { [string]: boolean } = {}
	local builtPlacePath: string? = nil
	local argumentIndex = 1
	while argumentIndex <= #process.args do
		local option = process.args[argumentIndex]
		local value = process.args[argumentIndex + 1]
		if value == nil then
			return nil
		end

		if option == "--spec" then
			if not isSafeSelector(value) or seenSpecs[value] then
				return nil
			end
			seenSpecs[value] = true
			table.insert(specs, value)
		elseif option == "--group" then
			if not isSafeSelector(value) or seenGroups[value] then
				return nil
			end
			seenGroups[value] = true
			table.insert(groups, value)
		elseif option == "--built-place" then
			if builtPlacePath ~= nil or not isSafeBuiltPlacePath(value) then
				return nil
			end
			builtPlacePath = value
		else
			return nil
		end
		argumentIndex += 2
	end

	local filter: SelectionFilter? = nil
	if #specs > 0 or #groups > 0 then
		filter = {
			specs = specs,
			groups = groups,
		}
	end
	return {
		selection = "normal",
		simulateCrash = false,
		filter = filter,
		builtPlacePath = builtPlacePath,
	}
end

local function cleanupGeneratedOutput(): boolean
	local cleaned = true
	if ownsOutput and fs.isFile(OUTPUT_PATH) then
		local removed = pcall(fs.removeFile, OUTPUT_PATH)
		if not removed then
			cleaned = false
		end
	end

	if createdBuildDirectory and fs.isDir(BUILD_DIRECTORY) then
		local readSucceeded, entries = pcall(fs.readDir, BUILD_DIRECTORY)
		if readSucceeded and #(entries :: { string }) == 0 then
			local removed = pcall(fs.removeDir, BUILD_DIRECTORY)
			if not removed then
				cleaned = false
			end
		elseif not readSucceeded then
			cleaned = false
		end
	end

	return cleaned
end

local function buildTestPlace(): boolean
	if not fs.isFile(PROJECT_PATH) or not fs.isFile("rokit.toml") or not fs.isDir("src/shared") then
		record("INVALID_WORKING_DIRECTORY", "runner", "tests/run.luau")
		return false
	end
	if fs.isFile(OUTPUT_PATH) then
		record("OUTPUT_ALREADY_EXISTS", "runner", OUTPUT_PATH)
		return false
	end
	if fs.isFile(BUILD_DIRECTORY) then
		record("BUILD_PATH_NOT_DIRECTORY", "runner", BUILD_DIRECTORY)
		return false
	end
	if not fs.isDir(BUILD_DIRECTORY) then
		local created = pcall(fs.writeDir, BUILD_DIRECTORY)
		if not created then
			record("BUILD_DIRECTORY_CREATE_FAILED", "runner", BUILD_DIRECTORY)
			return false
		end
		createdBuildDirectory = true
	end

	ownsOutput = true
	local executed, result = pcall(process.exec, "rojo", {
		"build",
		PROJECT_PATH,
		"--output",
		OUTPUT_PATH,
	})
	if not executed or not (result :: any).ok then
		record("TEST_BUILD_FAILED", "runner", PROJECT_PATH)
		return false
	end

	return true
end

local function createModuleLoader(dataModel: DataModel): (ModuleScript) -> unknown
	local nativeTypeof = typeof
	local cache: { [Instance]: ModuleRecord } = setmetatable({}, { __mode = "k" }) :: any
	local connectionRegistry: { [any]: boolean } = setmetatable({}, { __mode = "k" })
	local failureRegistry: { [any]: boolean } = setmetatable({}, { __mode = "k" })
	local loadModule: (ModuleScript) -> unknown

	local function canonicalPath(target: Instance): string
		local path = target:GetFullName()
		if #path > 512 or string.match(path, "^[A-Za-z0-9_.:-]+$") == nil then
			return "<unsafe>"
		end
		return path
	end

	local function loaderFailure(target: Instance, code: string): never
		local failure = table.freeze({
			code = code,
			path = canonicalPath(target),
		})
		failureRegistry[failure] = true
		error(failure, 0)
	end

	local function getLoaderFailure(value: unknown): LoaderFailure?
		if type(value) ~= "table" or failureRegistry[value] ~= true then
			return nil
		end
		return value :: LoaderFailure
	end

	local function adaptedTypeof(value: unknown): string
		if type(value) == "table" and connectionRegistry[value] == true then
			return "RBXScriptConnection"
		end
		return nativeTypeof(value)
	end

	local function createConnection(disconnectCallback: () -> ()): unknown
		if type(disconnectCallback) ~= "function" then
			error("[ATD_TEST_ADAPTER][code=INVALID_DISCONNECT_CALLBACK]", 0)
		end

		local proxy = table.freeze({
			Disconnect = function(_self: unknown)
				disconnectCallback()
			end,
		})
		connectionRegistry[proxy] = true
		return proxy
	end

	local serverStorage = dataModel:GetService("ServerStorage")
	local automatedTests = serverStorage:FindFirstChild("AutomatedTests")
	local support = if automatedTests == nil then nil else automatedTests:FindFirstChild("Support")
	local adapterModule = if support == nil then nil else support:FindFirstChild("RobloxAdapter")
	if adapterModule == nil or not adapterModule:IsA("ModuleScript") then
		error("[ATD_TEST_LOADER][code=ADAPTER_MODULE_MISSING][path=<unsafe>]", 0)
	end
	local hostAdapter = table.freeze({
		createConnection = createConnection,
		getLoaderFailure = getLoaderFailure,
	})

	loadModule = function(target: ModuleScript): unknown
		if nativeTypeof(target) ~= "Instance" or not (target :: Instance):IsA("ModuleScript") then
			error("[ATD_TEST_LOADER][code=INVALID_REQUIRE_TARGET][path=<unknown>]", 0)
		end

		local existing = cache[target]
		if existing ~= nil then
			if existing.state == "Loaded" then
				return existing.value
			elseif existing.state == "Loading" then
				loaderFailure(target, "DEPENDENCY_CYCLE")
			else
				loaderFailure(target, "CACHED_MODULE_FAILURE")
			end
		end

		local recordValue: ModuleRecord = {
			state = "Loading",
			value = nil,
		}
		cache[target] = recordValue
		if target == adapterModule then
			recordValue.state = "Loaded"
			recordValue.value = hostAdapter
			return hostAdapter
		end

		local environment = {
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Enum = roblox.Enum,
			Instance = roblox.Instance,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
			Vector2 = roblox.Vector2,
			Vector3 = roblox.Vector3,
			game = dataModel,
			require = loadModule,
			script = target,
			task = taskLibrary,
			typeof = adaptedTypeof,
		}
		local compiled, chunk = pcall(luau.load, target.Source, {
			debugName = target:GetFullName(),
			environment = environment,
			injectGlobals = true,
		})
		if not compiled or type(chunk) ~= "function" then
			recordValue.state = "Failed"
			loaderFailure(target, "MODULE_COMPILE_FAILED")
		end

		local executed, packedResult = pcall(function()
			return table.pack((chunk :: () -> ...unknown)())
		end)
		if not executed then
			recordValue.state = "Failed"
			local nestedFailure = getLoaderFailure(packedResult)
			if nestedFailure ~= nil then
				error(nestedFailure, 0)
			end
			loaderFailure(target, "MODULE_EXECUTION_FAILED")
		end

		local results = packedResult :: { [number]: unknown, n: number }
		if results.n ~= 1 or results[1] == nil then
			recordValue.state = "Failed"
			loaderFailure(target, "INVALID_MODULE_RETURN")
		end

		recordValue.state = "Loaded"
		recordValue.value = results[1]
		return results[1]
	end

	return loadModule
end

local function main(): number
	local options = parseSelection()
	if options == nil then
		record("INVALID_ARGUMENTS", "runner", "tests/run.luau")
		return EXIT_RUNNER_FAILURE
	end
	if not hasRequiredLoaderGlobals() then
		record("LOADER_GLOBALS_MISSING", "runner", "tests/run.luau")
		return EXIT_RUNNER_FAILURE
	end

	local placePath = options.builtPlacePath
	if placePath == nil then
		if not buildTestPlace() then
			return EXIT_RUNNER_FAILURE
		end
		placePath = OUTPUT_PATH
	elseif not fs.isFile(placePath) then
		record("BUILT_PLACE_MISSING", "runner", placePath)
		return EXIT_RUNNER_FAILURE
	end

	local readSucceeded, placeContents = pcall(fs.readFile, placePath)
	if not readSucceeded then
		record("TEST_BUILD_READ_FAILED", "runner", placePath)
		return EXIT_RUNNER_FAILURE
	end
	local deserialized, dataModel = pcall(roblox.deserializePlace, placeContents)
	if not deserialized then
		record("TEST_BUILD_DESERIALIZE_FAILED", "runner", placePath)
		return EXIT_RUNNER_FAILURE
	end

	if options.simulateCrash then
		error("INTENTIONAL_RUNNER_CRASH_PRIVATE_VALUE", 0)
	end

	local game = dataModel :: DataModel
	local serverStorage = game:GetService("ServerStorage")
	local automatedTests = serverStorage:FindFirstChild("AutomatedTests")
	local support = if automatedTests == nil then nil else automatedTests:FindFirstChild("Support")
	local runnerModule = if support == nil then nil else support:FindFirstChild("TestRunner")
	if runnerModule == nil or not runnerModule:IsA("ModuleScript") then
		record("ENTRYPOINT_MISSING", "runner", "ServerStorage.AutomatedTests.Support.TestRunner")
		return EXIT_RUNNER_FAILURE
	end

	local loadModule = createModuleLoader(game)
	local loaded, testRunner = pcall(loadModule, runnerModule :: ModuleScript)
	if not loaded or type(testRunner) ~= "table" or type((testRunner :: any).run) ~= "function" then
		record("ENTRYPOINT_LOAD_FAILED", "runner", runnerModule:GetFullName())
		return EXIT_RUNNER_FAILURE
	end

	local ran, result = pcall((testRunner :: any).run, game, options.selection, options.filter)
	if
		not ran
		or type(result) ~= "table"
		or type((result :: any).exitCode) ~= "number"
		or (result :: any).exitCode % 1 ~= 0
	then
		record("ENTRYPOINT_EXECUTION_FAILED", "runner", runnerModule:GetFullName())
		return EXIT_RUNNER_FAILURE
	end

	local runResult = result :: any
	local validExitCode = runResult.exitCode == 0 or runResult.exitCode == 1 or runResult.exitCode == 2
	local countsAreValid = true
	for _, fieldName in { "suiteCount", "testCount", "passedCount", "failedCount" } do
		local value = runResult[fieldName]
		if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then
			countsAreValid = false
		end
	end
	local countsAreCoherent = countsAreValid and runResult.passedCount + runResult.failedCount == runResult.testCount
	local outcomeIsCoherent = countsAreCoherent
		and (
			(runResult.exitCode == 0 and runResult.testCount > 0 and runResult.failedCount == 0)
			or (runResult.exitCode == 1 and runResult.failedCount > 0)
			or runResult.exitCode == 2
		)
	if not validExitCode or not outcomeIsCoherent then
		record("ENTRYPOINT_RESULT_INVALID", "runner", runnerModule:GetFullName())
		return EXIT_RUNNER_FAILURE
	end

	return runResult.exitCode
end

local completed, exitCode = xpcall(main, function()
	return EXIT_RUNNER_FAILURE
end)

local cleaned = cleanupGeneratedOutput()
if not cleaned then
	record("GENERATED_OUTPUT_CLEANUP_FAILED", "runner", OUTPUT_PATH)
	process.exit(EXIT_RUNNER_FAILURE)
end
if not completed then
	record("RUNNER_CRASH", "runner", "tests/run.luau")
	process.exit(EXIT_RUNNER_FAILURE)
end

process.exit(exitCode :: number)
