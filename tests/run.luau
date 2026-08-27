--!strict

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local taskLibrary = require("@lune/task")

type Selection = "normal" | "assertion" | "malformed" | "malformed-root" | "module-load" | "zero"

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

local ownsOutput = false
local createdBuildDirectory = false

local function record(code: string, category: string, path: string)
	print(`[ATD_TEST][FAIL][category={category}][code={code}][path={path}]`)
end

local function parseSelection(): (Selection?, boolean, string?)
	if #process.args == 0 then
		return "normal", false, nil
	end
	if #process.args ~= 2 then
		return nil, false, nil
	end
	if process.args[1] == "--spec" then
		local specName = process.args[2]
		if #specName < 1 or #specName > 64 or string.match(specName, "^[A-Za-z][A-Za-z0-9]*$") == nil then
			return nil, false, nil
		end
		return "normal", false, specName
	elseif process.args[1] ~= "--control" then
		return nil, false, nil
	end

	local control = process.args[2]
	if
		control == "zero"
		or control == "assertion"
		or control == "malformed"
		or control == "malformed-root"
		or control == "module-load"
	then
		return control :: Selection, false, nil
	elseif control == "runner-crash" then
		return "normal", true, nil
	end

	return nil, false, nil
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
			Instance = roblox.Instance,
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
	local selection, simulateCrash, specName = parseSelection()
	if selection == nil then
		record("INVALID_ARGUMENTS", "runner", "tests/run.luau")
		return EXIT_RUNNER_FAILURE
	end
	if not buildTestPlace() then
		return EXIT_RUNNER_FAILURE
	end

	local readSucceeded, placeContents = pcall(fs.readFile, OUTPUT_PATH)
	if not readSucceeded then
		record("TEST_BUILD_READ_FAILED", "runner", OUTPUT_PATH)
		return EXIT_RUNNER_FAILURE
	end
	local deserialized, dataModel = pcall(roblox.deserializePlace, placeContents)
	if not deserialized then
		record("TEST_BUILD_DESERIALIZE_FAILED", "runner", OUTPUT_PATH)
		return EXIT_RUNNER_FAILURE
	end

	if simulateCrash then
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

	local ran, result = pcall((testRunner :: any).run, game, selection, specName)
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
