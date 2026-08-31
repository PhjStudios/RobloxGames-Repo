--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

type Role = "Default" | "Lobby" | "Match" | "Test"

type BuildDefinition = {
	name: Role,
	project: string,
	output: string,
}

type SourceRecord = {
	className: string,
	source: string,
}

type ParsedArguments = {
	runTests: boolean,
	selectedProjects: { [Role]: boolean },
}

local BUILD_DIRECTORY = "build"
local ALL_BUILDS: { BuildDefinition } = {
	{ name = "Default", project = "default.project.json", output = "build/verify-default.rbxlx" },
	{ name = "Lobby", project = "lobby.project.json", output = "build/verify-lobby.rbxlx" },
	{ name = "Match", project = "match.project.json", output = "build/verify-match.rbxlx" },
	{ name = "Test", project = "test.project.json", output = "build/verify-test.rbxlx" },
}
local EXPECTED_PLACE_ROLES: { [Role]: string } = {
	Default = "Development",
	Lobby = "Lobby",
	Match = "Match",
	Test = "",
}
local REQUIRED_TEST_SUPPORT = table.freeze({
	RobloxAdapter = true,
	TestHarness = true,
	TestRunner = true,
})

local createdBuildDirectory = false
local ownedOutputs: { [string]: boolean } = {}
local currentStage = "startup"

local function emit(kind: string, buildName: string, code: string, path: string?)
	local output = `[ATD_BUILD][{kind}][build={buildName}][code={code}]`
	if path ~= nil then
		local safePath = if #path <= 512 and string.match(path, "^[A-Za-z0-9_./\\:-]+$") ~= nil
			then path
			else "<unsafe>"
		output ..= `[path={safePath}]`
	end
	print(output)
end

local function parseArguments(): ParsedArguments?
	local runTests = true
	local buildsOnlySeen = false
	local selectedProjects: { [Role]: boolean } = {}
	local hasProjectSelection = false
	local index = 1
	while index <= #process.args do
		local argument = process.args[index]
		if argument == "--builds-only" then
			if buildsOnlySeen then
				return nil
			end
			buildsOnlySeen = true
			runTests = false
			index += 1
		elseif argument == "--project" then
			local projectName = process.args[index + 1]
			if
				projectName ~= "Default"
				and projectName ~= "Lobby"
				and projectName ~= "Match"
				and projectName ~= "Test"
			then
				return nil
			end
			local role = projectName :: Role
			if selectedProjects[role] then
				return nil
			end
			selectedProjects[role] = true
			hasProjectSelection = true
			index += 2
		else
			return nil
		end
	end

	if runTests and hasProjectSelection then
		return nil
	end
	if not hasProjectSelection then
		for _, definition in ALL_BUILDS do
			selectedProjects[definition.name] = true
		end
	end

	return {
		runTests = runTests,
		selectedProjects = selectedProjects,
	}
end

local function cleanup(): boolean
	local cleaned = true
	for output in ownedOutputs do
		if fs.isFile(output) and not pcall(fs.removeFile, output) then
			cleaned = false
		end
	end
	if createdBuildDirectory and fs.isDir(BUILD_DIRECTORY) then
		local readSucceeded, entries = pcall(fs.readDir, BUILD_DIRECTORY)
		if readSucceeded and #(entries :: { string }) == 0 then
			if not pcall(fs.removeDir, BUILD_DIRECTORY) then
				cleaned = false
			end
		elseif not readSucceeded then
			cleaned = false
		end
	end
	return cleaned
end

local function normalizeNewlines(value: string): string
	return string.gsub(value, "\r\n", "\n")
end

local function normalizePath(value: string): string
	return string.gsub(value, "\\", "/")
end

local function countPlainOccurrences(value: string, needle: string): number
	local count = 0
	local cursor = 1
	while true do
		local _, occurrenceEnd = string.find(value, needle, cursor, true)
		if occurrenceEnd == nil then
			return count
		end
		count += 1
		cursor = occurrenceEnd + 1
	end
end

local function readSource(path: string): string?
	if not fs.isFile(path) then
		return nil
	end
	local succeeded, value = pcall(fs.readFile, path)
	if not succeeded or type(value) ~= "string" then
		return nil
	end
	return normalizeNewlines(value :: string)
end

local function quotedField(record: string, fieldName: string): string?
	if countPlainOccurrences(record, `{fieldName} =`) ~= 1 then
		return nil
	end
	return string.match(record, fieldName .. '%s*=%s*"([A-Za-z][A-Za-z0-9_]*)"')
end

local function hasSafeProductionPlaceRoles(record: string): boolean
	if countPlainOccurrences(record, "placeRoles =") ~= 1 then
		return false
	end
	local body = string.match(record, "placeRoles%s*=%s*%{([^}]*)%}")
	if body == nil then
		return false
	end

	local foundRoles: { [string]: boolean } = {}
	local roleCount = 0
	for role in string.gmatch(body, '"([A-Za-z]+)"') do
		if (role ~= "Lobby" and role ~= "Match") or foundRoles[role] then
			return false
		end
		foundRoles[role] = true
		roleCount += 1
	end
	local remaining = string.gsub(body, '"[A-Za-z]+"', "")
	remaining = string.gsub(remaining, "[%s,]", "")
	return roleCount > 0 and remaining == ""
end

local function verifyNetworkSecurityBoundary(): boolean
	local remotesSource = readSource("src/shared/network/ProductionRemotes.luau")
	local ratesSource = readSource("src/server/common/networking/ProductionRateLimits.luau")
	if remotesSource == nil or ratesSource == nil then
		emit("FAIL", "All", "NETWORK_SOURCE_MISSING")
		return false
	end

	local remoteNames: { [string]: boolean } = {}
	local clientRequests: { [string]: boolean } = {}
	local remoteCount = 0
	for record in string.gmatch(remotesSource, "\n\t%{(.-)\n\t%},") do
		local name = quotedField(record, "name")
		local transport = quotedField(record, "transport")
		local direction = quotedField(record, "direction")
		local kind = quotedField(record, "kind")
		local response = quotedField(record, "response")
		if name == nil or remoteNames[name] or not hasSafeProductionPlaceRoles(record) then
			emit("FAIL", "All", "REMOTE_SECURITY_RECORD_INVALID", name or "<unknown>")
			return false
		end
		if direction == "ClientToServer" then
			if kind ~= "Request" or response ~= "Required" or transport ~= "ReliableRemoteEvent" then
				emit("FAIL", "All", "CLIENT_REQUEST_SHAPE_INVALID", name)
				return false
			end
			clientRequests[name] = true
		elseif direction == "ServerToClient" then
			if
				kind ~= "Event"
				or response ~= "None"
				or (transport ~= "ReliableRemoteEvent" and transport ~= "UnreliableRemoteEvent")
			then
				emit("FAIL", "All", "SERVER_EVENT_SHAPE_INVALID", name)
				return false
			end
		else
			emit("FAIL", "All", "REMOTE_DIRECTION_INVALID", name)
			return false
		end
		remoteNames[name] = true
		remoteCount += 1
	end
	if remoteCount == 0 or remoteCount ~= countPlainOccurrences(remotesSource, "\n\t\tname =") then
		emit("FAIL", "All", "REMOTE_RECORD_DISCOVERY_INVALID")
		return false
	end

	local rateEndpoints: { [string]: boolean } = {}
	local rateCount = 0
	for record in string.gmatch(ratesSource, "table%.freeze%(%{(.-)%}%)") do
		local endpoint = quotedField(record, "endpoint")
		if
			endpoint == nil
			or rateEndpoints[endpoint]
			or not clientRequests[endpoint]
			or countPlainOccurrences(record, "policy = requirePolicy(") ~= 1
		then
			emit("FAIL", "All", "RATE_POLICY_RECORD_INVALID", endpoint or "<unknown>")
			return false
		end
		rateEndpoints[endpoint] = true
		rateCount += 1
	end
	if rateCount ~= countPlainOccurrences(ratesSource, "\n\t\tendpoint =") then
		emit("FAIL", "All", "RATE_POLICY_DISCOVERY_INVALID")
		return false
	end
	for endpoint in clientRequests do
		if not rateEndpoints[endpoint] then
			emit("FAIL", "All", "CLIENT_REQUEST_RATE_POLICY_MISSING", endpoint)
			return false
		end
	end

	emit("PASS", "All", `NETWORK_REMOTES_{remoteCount}_CLIENT_REQUESTS_{rateCount}`)
	return true
end

local function verifyProjectSourceIsolation(): boolean
	for _, definition in ALL_BUILDS do
		local projectSource = readSource(definition.project)
		if projectSource == nil then
			emit("FAIL", definition.name, "PROJECT_FILE_MISSING", definition.project)
			return false
		end
		local normalized = string.lower(normalizePath(projectSource))
		if definition.name == "Test" then
			if string.find(normalized, "tests/studio", 1, true) ~= nil then
				emit("FAIL", definition.name, "STUDIO_TEST_SOURCE_MAPPED", definition.project)
				return false
			end
		elseif string.find(normalized, '"tests/', 1, true) ~= nil then
			emit("FAIL", definition.name, "TEST_SOURCE_MAPPED_TO_PRODUCTION", definition.project)
			return false
		end
	end
	return true
end

local function isLuaSourceContainer(instance: Instance): boolean
	return instance.ClassName == "ModuleScript" or instance.ClassName == "Script" or instance.ClassName == "LocalScript"
end

local function collectDescendantsIncluding(root: Instance): { Instance }
	local descendants = { root }
	for _, descendant in root:GetDescendants() do
		table.insert(descendants, descendant)
	end
	return descendants
end

local function countClasses(dataModel: DataModel): (number, number, number)
	local moduleCount = 0
	local scriptCount = 0
	local localScriptCount = 0
	for _, descendant in dataModel:GetDescendants() do
		if descendant.ClassName == "ModuleScript" then
			moduleCount += 1
		elseif descendant.ClassName == "Script" then
			scriptCount += 1
		elseif descendant.ClassName == "LocalScript" then
			localScriptCount += 1
		end
	end
	return moduleCount, scriptCount, localScriptCount
end

local function hasTestLeak(dataModel: DataModel): boolean
	for _, descendant in dataModel:GetDescendants() do
		local path = descendant:GetFullName()
		if
			string.find(path, "AutomatedTests", 1, true) ~= nil
			or string.find(path, "NegativeControls", 1, true) ~= nil
			or string.sub(descendant.Name, -5) == ".spec"
		then
			return true
		end
		if isLuaSourceContainer(descendant) then
			local source = (descendant :: LuaSourceContainer).Source
			if
				string.find(source, "[ATD_TEST]", 1, true) ~= nil
				or string.find(source, "[ATD_PHASE", 1, true) ~= nil
				or string.find(source, "PRIVATE_MODULE_LOAD_VALUE", 1, true) ~= nil
			then
				return true
			end
		end
	end
	return false
end

local function hasChild(parent: Instance?, name: string): boolean
	return parent ~= nil and parent:FindFirstChild(name) ~= nil
end

local function verifyRoleLayers(dataModel: DataModel, role: "Default" | "Lobby" | "Match"): boolean
	local serverContainer = dataModel:GetService("ServerScriptService"):FindFirstChild("Server")
	local starterPlayerScripts = dataModel:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local clientContainer = if starterPlayerScripts == nil then nil else starterPlayerScripts:FindFirstChild("Client")
	if
		serverContainer == nil
		or serverContainer.ClassName ~= "Folder"
		or clientContainer == nil
		or clientContainer.ClassName ~= "Folder"
	then
		return false
	end

	local expectedLobby = role ~= "Match"
	local expectedMatch = role ~= "Lobby"
	return hasChild(serverContainer, "common")
		and hasChild(clientContainer, "common")
		and hasChild(serverContainer, "lobby") == expectedLobby
		and hasChild(clientContainer, "lobby") == expectedLobby
		and hasChild(serverContainer, "match") == expectedMatch
		and hasChild(clientContainer, "match") == expectedMatch
end

local function collectSources(root: Instance): { [string]: SourceRecord }?
	local records: { [string]: SourceRecord } = {}
	local rootPath = root:GetFullName()
	for _, instance in collectDescendantsIncluding(root) do
		if isLuaSourceContainer(instance) then
			local path = instance:GetFullName()
			local relativePath = if path == rootPath then "<root>" else string.sub(path, #rootPath + 2)
			if records[relativePath] ~= nil then
				return nil
			end
			records[relativePath] = {
				className = instance.ClassName,
				source = (instance :: LuaSourceContainer).Source,
			}
		end
	end
	return records
end

local function sourceSignature(record: SourceRecord): string
	return record.className .. "\0" .. record.source
end

local function verifyProduction(dataModel: DataModel, definition: BuildDefinition): boolean
	local modules, scripts, localScripts = countClasses(dataModel)
	if modules == 0 or scripts ~= 1 or localScripts ~= 1 then
		emit("FAIL", definition.name, `PRODUCTION_CLASS_COUNTS_{modules}_{scripts}_{localScripts}`)
		return false
	end
	local expectedRole = EXPECTED_PLACE_ROLES[definition.name]
	local actualRole = dataModel:GetService("ReplicatedStorage"):GetAttribute("ATDPlaceRole")
	if actualRole ~= expectedRole then
		emit("FAIL", definition.name, "PLACE_ROLE_MISMATCH")
		return false
	end
	local shared = dataModel:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	if shared == nil or shared.ClassName ~= "Folder" or collectSources(shared) == nil then
		emit("FAIL", definition.name, "SHARED_SOURCE_STRUCTURE")
		return false
	end
	if hasTestLeak(dataModel) then
		emit("FAIL", definition.name, "TEST_CONTENT_LEAK")
		return false
	end
	if not verifyRoleLayers(dataModel, definition.name :: "Default" | "Lobby" | "Match") then
		emit("FAIL", definition.name, "ROLE_LAYER_ISOLATION")
		return false
	end

	emit("PASS", definition.name, `MODULES_{modules}_SCRIPTS_{scripts}_LOCALSCRIPTS_{localScripts}`)
	return true
end

local function verifySpecs(specs: Instance): (boolean, number)
	local specCount = 0
	for _, descendant in specs:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			if string.sub(descendant.Name, -5) ~= ".spec" then
				return false, specCount
			end
			specCount += 1
		elseif not descendant:IsA("Folder") then
			return false, specCount
		end
	end
	return specCount > 0, specCount
end

local function verifyTest(
	dataModel: DataModel,
	definition: BuildDefinition,
	productionSourceSignatures: { [string]: boolean }
): boolean
	local modules, scripts, localScripts = countClasses(dataModel)
	if modules == 0 or scripts ~= 0 or localScripts ~= 0 then
		emit("FAIL", definition.name, `TEST_CLASS_COUNTS_{modules}_{scripts}_{localScripts}`)
		return false
	end
	local serverStorage = dataModel:GetService("ServerStorage")
	local automatedTests = serverStorage:FindFirstChild("AutomatedTests")
	local negativeControls = serverStorage:FindFirstChild("NegativeControls")
	local specs = if automatedTests == nil then nil else automatedTests:FindFirstChild("Specs")
	local fixtures = if automatedTests == nil then nil else automatedTests:FindFirstChild("Fixtures")
	local support = if automatedTests == nil then nil else automatedTests:FindFirstChild("Support")
	if
		automatedTests == nil
		or automatedTests.ClassName ~= "Folder"
		or negativeControls == nil
		or specs == nil
		or specs.ClassName ~= "Folder"
		or fixtures == nil
		or fixtures.ClassName ~= "Folder"
		or support == nil
		or support.ClassName ~= "Folder"
	then
		emit("FAIL", definition.name, "TEST_BOUNDARY_STRUCTURE")
		return false
	end
	local starterPlayerScripts = dataModel:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	if
		dataModel:GetService("ServerScriptService"):FindFirstChild("Server") ~= nil
		or (starterPlayerScripts ~= nil and starterPlayerScripts:FindFirstChild("Client") ~= nil)
	then
		emit("FAIL", definition.name, "PRODUCTION_RUNTIME_PRESENT")
		return false
	end
	for supportName in REQUIRED_TEST_SUPPORT do
		local supportModule = support:FindFirstChild(supportName)
		if supportModule == nil or supportModule.ClassName ~= "ModuleScript" then
			emit("FAIL", definition.name, "TEST_SUPPORT_MISSING", supportName)
			return false
		end
	end
	local specsValid, specCount = verifySpecs(specs)
	if not specsValid then
		emit("FAIL", definition.name, "SPEC_STRUCTURE_INVALID")
		return false
	end

	local mirroredCount = 0
	for _, child in automatedTests:GetChildren() do
		if string.sub(child.Name, 1, 10) == "Production" then
			for _, instance in collectDescendantsIncluding(child) do
				if isLuaSourceContainer(instance) then
					if instance.ClassName ~= "ModuleScript" then
						emit("FAIL", definition.name, "MIRRORED_RUNNABLE_SOURCE", instance:GetFullName())
						return false
					end
					local signature = sourceSignature({
						className = instance.ClassName,
						source = (instance :: LuaSourceContainer).Source,
					})
					if next(productionSourceSignatures) ~= nil and not productionSourceSignatures[signature] then
						emit("FAIL", definition.name, "MIRRORED_SOURCE_MISMATCH", instance:GetFullName())
						return false
					end
					mirroredCount += 1
				end
			end
		end
	end
	if mirroredCount == 0 then
		emit("FAIL", definition.name, "MIRRORED_SOURCE_MISSING")
		return false
	end

	emit("PASS", definition.name, `MODULES_{modules}_SPECS_{specCount}_MIRRORED_{mirroredCount}_RUNNABLE_SCRIPTS_0`)
	return true
end

local function sameSourceRecords(left: { [string]: SourceRecord }, right: { [string]: SourceRecord }): boolean
	local leftCount = 0
	local rightCount = 0
	for path, leftRecord in left do
		leftCount += 1
		local rightRecord = right[path]
		if
			rightRecord == nil
			or rightRecord.className ~= leftRecord.className
			or rightRecord.source ~= leftRecord.source
		then
			return false
		end
	end
	for _ in right do
		rightCount += 1
	end
	return leftCount == rightCount
end

local function verifySharedConsistency(dataModels: { [Role]: DataModel }): boolean
	local baselineName: Role? = nil
	local baseline: { [string]: SourceRecord }? = nil
	for _, definition in ALL_BUILDS do
		local dataModel = dataModels[definition.name]
		if dataModel ~= nil then
			local shared = dataModel:GetService("ReplicatedStorage"):FindFirstChild("Shared")
			if shared == nil then
				emit("FAIL", definition.name, "SHARED_SOURCE_MISSING")
				return false
			end
			local records = collectSources(shared)
			if records == nil then
				emit("FAIL", definition.name, "SHARED_SOURCE_DUPLICATE")
				return false
			end
			if baseline == nil then
				baselineName = definition.name
				baseline = records
			elseif not sameSourceRecords(baseline, records) then
				emit("FAIL", definition.name, "SHARED_SOURCE_DIVERGENCE", baselineName :: Role)
				return false
			end
		end
	end
	return true
end

local function collectProductionSignatures(dataModels: { [Role]: DataModel }): { [string]: boolean }
	local signatures: { [string]: boolean } = {}
	for _, role: Role in { "Default", "Lobby", "Match" } do
		local dataModel = dataModels[role]
		if dataModel ~= nil then
			for _, descendant in dataModel:GetDescendants() do
				if isLuaSourceContainer(descendant) then
					signatures[sourceSignature({
						className = descendant.ClassName,
						source = (descendant :: LuaSourceContainer).Source,
					})] =
						true
				end
			end
		end
	end
	return signatures
end

local function printCapturedOutput(value: unknown)
	if type(value) == "string" and #value > 0 then
		local trimmed = string.gsub(value, "%s+$", "")
		if #trimmed > 0 then
			print(trimmed)
		end
	end
end

local function runHeadlessSuite(testPlacePath: string): boolean
	local executed, result = pcall(process.exec, "lune", {
		"run",
		"tests/run.luau",
		"--built-place",
		testPlacePath,
	})
	if executed and type(result) == "table" then
		printCapturedOutput((result :: any).stdout)
		printCapturedOutput((result :: any).stderr)
	end
	if not executed or type(result) ~= "table" or not (result :: any).ok then
		emit("FAIL", "Test", "HEADLESS_SUITE_FAILED")
		return false
	end
	return true
end

local function prepareBuildDirectory(): boolean
	if fs.isFile(BUILD_DIRECTORY) then
		emit("FAIL", "All", "BUILD_PATH_NOT_DIRECTORY", BUILD_DIRECTORY)
		return false
	end
	if not fs.isDir(BUILD_DIRECTORY) then
		if not pcall(fs.writeDir, BUILD_DIRECTORY) then
			emit("FAIL", "All", "BUILD_DIRECTORY_CREATE_FAILED", BUILD_DIRECTORY)
			return false
		end
		createdBuildDirectory = true
	end
	return true
end

local function buildAndDeserialize(definition: BuildDefinition): DataModel?
	if not fs.isFile(definition.project) then
		emit("FAIL", definition.name, "PROJECT_FILE_MISSING", definition.project)
		return nil
	end
	if fs.isFile(definition.output) then
		emit("FAIL", definition.name, "OUTPUT_ALREADY_EXISTS", definition.output)
		return nil
	end
	ownedOutputs[definition.output] = true
	local executed, result = pcall(process.exec, "rojo", {
		"build",
		definition.project,
		"--output",
		definition.output,
	})
	if not executed or type(result) ~= "table" or not (result :: any).ok or not fs.isFile(definition.output) then
		emit("FAIL", definition.name, "BUILD_FAILED", definition.project)
		return nil
	end
	local readSucceeded, contents = pcall(fs.readFile, definition.output)
	if not readSucceeded then
		emit("FAIL", definition.name, "BUILD_READ_FAILED", definition.output)
		return nil
	end
	local deserialized, dataModel = pcall(roblox.deserializePlace, contents)
	if not deserialized then
		emit("FAIL", definition.name, "BUILD_DESERIALIZE_FAILED", definition.output)
		return nil
	end
	return dataModel :: DataModel
end

local function run(): boolean
	local arguments = parseArguments()
	if arguments == nil then
		emit("FAIL", "All", "INVALID_ARGUMENTS", "tests/verify-builds.luau")
		return false
	end
	currentStage = "security"
	if not verifyNetworkSecurityBoundary() or not verifyProjectSourceIsolation() then
		return false
	end
	currentStage = "build_directory"
	if not prepareBuildDirectory() then
		return false
	end

	local dataModels: { [Role]: DataModel } = {}
	for _, definition in ALL_BUILDS do
		if arguments.selectedProjects[definition.name] then
			currentStage = `build_{definition.name}`
			local dataModel = buildAndDeserialize(definition)
			if dataModel == nil then
				return false
			end
			dataModels[definition.name] = dataModel
		end
	end

	currentStage = "verify_production"
	for _, definition in ALL_BUILDS do
		local dataModel = dataModels[definition.name]
		if dataModel ~= nil and definition.name ~= "Test" and not verifyProduction(dataModel, definition) then
			return false
		end
	end
	currentStage = "verify_shared"
	if not verifySharedConsistency(dataModels) then
		return false
	end
	local testDataModel = dataModels.Test
	if testDataModel ~= nil then
		currentStage = "verify_test"
		if not verifyTest(testDataModel, ALL_BUILDS[4], collectProductionSignatures(dataModels)) then
			return false
		end
	end
	if arguments.runTests then
		currentStage = "headless_suite"
		if testDataModel == nil or not runHeadlessSuite(ALL_BUILDS[4].output) then
			return false
		end
	end

	return true
end

local completed, verified = xpcall(run, function()
	return false
end)
local cleaned = cleanup()
if not completed then
	emit("FAIL", "All", `VERIFIER_CRASH_{currentStage}`)
end
if not cleaned then
	emit("FAIL", "All", "OUTPUT_CLEANUP_FAILED")
end

if completed and verified and cleaned then
	process.exit(0)
else
	process.exit(1)
end
