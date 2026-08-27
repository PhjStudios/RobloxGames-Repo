--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

type BuildDefinition = {
	name: string,
	project: string,
	output: string,
	role: "Default" | "Lobby" | "Match" | "Test",
}

type SourceDefinition = {
	dataModelPath: string,
	className: "ModuleScript" | "Script" | "LocalScript",
	sourcePath: string,
}

local BUILD_DIRECTORY = "build"
local BUILDS: { BuildDefinition } = {
	{ name = "Default", project = "default.project.json", output = "build/verify-default.rbxlx", role = "Default" },
	{ name = "Lobby", project = "lobby.project.json", output = "build/verify-lobby.rbxlx", role = "Lobby" },
	{ name = "Match", project = "match.project.json", output = "build/verify-match.rbxlx", role = "Match" },
	{ name = "Test", project = "test.project.json", output = "build/verify-test.rbxlx", role = "Test" },
}
local EXPECTED_PRODUCTION_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Assets",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Assets.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.AssetSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/AssetSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Banners",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Banners.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.BannerSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/BannerSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.ConfigurationValidator",
		className = "ModuleScript",
		sourcePath = "src/shared/config/ConfigurationValidator.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.DefaultSettings",
		className = "ModuleScript",
		sourcePath = "src/shared/config/DefaultSettings.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Difficulties",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Difficulties.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.DifficultySchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/DifficultySchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Economy",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Economy.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.EconomySchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/EconomySchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Enemies",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Enemies.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.EnemySchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/EnemySchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Maps",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Maps.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.MapSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/MapSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.PlaceRoles",
		className = "ModuleScript",
		sourcePath = "src/shared/config/PlaceRoles.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.SchemaPrimitives",
		className = "ModuleScript",
		sourcePath = "src/shared/config/SchemaPrimitives.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.SettingsSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/SettingsSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Towers",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Towers.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.TowerSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/TowerSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Waves",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Waves.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.WaveSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/WaveSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.lifecycle.ServiceLifecycle",
		className = "ModuleScript",
		sourcePath = "src/shared/lifecycle/ServiceLifecycle.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.logging.EnvironmentContext",
		className = "ModuleScript",
		sourcePath = "src/shared/logging/EnvironmentContext.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.logging.Log",
		className = "ModuleScript",
		sourcePath = "src/shared/logging/Log.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.network.ProductionRemotes",
		className = "ModuleScript",
		sourcePath = "src/shared/network/ProductionRemotes.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.network.PayloadValidation",
		className = "ModuleScript",
		sourcePath = "src/shared/network/PayloadValidation.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.network.RemoteRegistry",
		className = "ModuleScript",
		sourcePath = "src/shared/network/RemoteRegistry.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.network.RequestProtocol",
		className = "ModuleScript",
		sourcePath = "src/shared/network/RequestProtocol.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.types.ConfigTypes",
		className = "ModuleScript",
		sourcePath = "src/shared/types/ConfigTypes.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.util.Cleanup",
		className = "ModuleScript",
		sourcePath = "src/shared/util/Cleanup.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.util.Ids",
		className = "ModuleScript",
		sourcePath = "src/shared/util/Ids.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.util.Result",
		className = "ModuleScript",
		sourcePath = "src/shared/util/Result.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.util.Validation",
		className = "ModuleScript",
		sourcePath = "src/shared/util/Validation.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.bootstrap.Main",
		className = "Script",
		sourcePath = "src/server/common/bootstrap/Main.server.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.bootstrap.Shutdown",
		className = "ModuleScript",
		sourcePath = "src/server/common/bootstrap/Shutdown.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.networking.ProductionRateLimits",
		className = "ModuleScript",
		sourcePath = "src/server/common/networking/ProductionRateLimits.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.networking.ServerRemoteRegistry",
		className = "ModuleScript",
		sourcePath = "src/server/common/networking/ServerRemoteRegistry.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.networking.ServerRateLimiter",
		className = "ModuleScript",
		sourcePath = "src/server/common/networking/ServerRateLimiter.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.networking.ServerRequestDispatcher",
		className = "ModuleScript",
		sourcePath = "src/server/common/networking/ServerRequestDispatcher.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.common.bootstrap.Main",
		className = "LocalScript",
		sourcePath = "src/client/common/bootstrap/Main.client.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.common.networking.ClientRemoteLookup",
		className = "ModuleScript",
		sourcePath = "src/client/common/networking/ClientRemoteLookup.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.common.networking.ClientRequestTracker",
		className = "ModuleScript",
		sourcePath = "src/client/common/networking/ClientRequestTracker.luau",
	},
})
local EXPECTED_MATCH_SERVER_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ServerScriptService.Server.match.maps.MapContract",
		className = "ModuleScript",
		sourcePath = "src/server/match/maps/MapContract.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.maps.MapLoader",
		className = "ModuleScript",
		sourcePath = "src/server/match/maps/MapLoader.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.maps.MapValidator",
		className = "ModuleScript",
		sourcePath = "src/server/match/maps/MapValidator.luau",
	},
})
local EXPECTED_TEST_OWNED_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ServerStorage.AutomatedTests.Fixtures.ConfigurationFixtures",
		className = "ModuleScript",
		sourcePath = "tests/fixtures/ConfigurationFixtures.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Fixtures.MapFixtures",
		className = "ModuleScript",
		sourcePath = "tests/fixtures/MapFixtures.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Fixtures.NetworkFixtures",
		className = "ModuleScript",
		sourcePath = "tests/fixtures/NetworkFixtures.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.Cleanup.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/Cleanup.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ClientRequestTracker.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ClientRequestTracker.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ConfigurationContractEdges.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ConfigurationContractEdges.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ConfigurationFailures.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ConfigurationFailures.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ConfigurationLoaded.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ConfigurationLoaded.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ConfigurationPrivacy.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ConfigurationPrivacy.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ConfigurationSchemas.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ConfigurationSchemas.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.CoreContracts.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/CoreContracts.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MapContract.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MapContract.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MapLoader.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MapLoader.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MapValidator.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MapValidator.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.NetworkSecurity.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/NetworkSecurity.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.PayloadValidation.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/PayloadValidation.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.RemoteRegistry.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/RemoteRegistry.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.RemoteRuntime.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/RemoteRuntime.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.RequestProtocol.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/RequestProtocol.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ServerRateLimiter.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ServerRateLimiter.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ServerRequestDispatcher.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ServerRequestDispatcher.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.Smoke.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/Smoke.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Support.RobloxAdapter",
		className = "ModuleScript",
		sourcePath = "tests/support/RobloxAdapter.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Support.TestHarness",
		className = "ModuleScript",
		sourcePath = "tests/support/TestHarness.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Support.TestRunner",
		className = "ModuleScript",
		sourcePath = "tests/support/TestRunner.luau",
	},
	{
		dataModelPath = "ServerStorage.NegativeControls.Assertion.IntentionalFailure.spec",
		className = "ModuleScript",
		sourcePath = "tests/negative/assertion/IntentionalFailure.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.NegativeControls.Dependencies.BrokenDependency",
		className = "ModuleScript",
		sourcePath = "tests/negative/dependencies/BrokenDependency.luau",
	},
	{
		dataModelPath = "ServerStorage.NegativeControls.MalformedDiscovery.Misnamed",
		className = "ModuleScript",
		sourcePath = "tests/negative/malformed-discovery/Misnamed.luau",
	},
	{
		dataModelPath = "ServerStorage.NegativeControls.MalformedRoot.Specs.WouldPass.spec",
		className = "ModuleScript",
		sourcePath = "tests/negative/malformed-root/WouldPass.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.NegativeControls.ModuleLoad.IntentionalLoadFailure.spec",
		className = "ModuleScript",
		sourcePath = "tests/negative/module-load/IntentionalLoadFailure.spec.luau",
	},
})

local createdBuildDirectory = false
local ownedOutputs: { [string]: boolean } = {}
local currentStage = "startup"

local function safeLogPath(path: string): string
	if #path > 512 or string.match(path, "^[A-Za-z0-9_.:-]+$") == nil then
		return "<unsafe>"
	end
	return path
end

local function emit(kind: string, buildName: string, code: string, path: string?)
	local pathField = if path == nil then "" else `[path={safeLogPath(path)}]`
	print(`[ATD_BUILD_CHECK][{kind}][build={buildName}][code={code}]{pathField}`)
end

local function cleanup(): boolean
	local succeeded = true
	for _, definition in BUILDS do
		if ownedOutputs[definition.output] and fs.isFile(definition.output) then
			if not pcall(fs.removeFile, definition.output) then
				succeeded = false
			end
		end
	end

	if createdBuildDirectory and fs.isDir(BUILD_DIRECTORY) then
		local readSucceeded, entries = pcall(fs.readDir, BUILD_DIRECTORY)
		if readSucceeded and #(entries :: { string }) == 0 then
			if not pcall(fs.removeDir, BUILD_DIRECTORY) then
				succeeded = false
			end
		elseif not readSucceeded then
			succeeded = false
		end
	end

	return succeeded
end

local function collectDescendants(root: Instance): { Instance }
	local descendants: { Instance } = {}
	local function visit(parent: Instance)
		for _, child in parent:GetChildren() do
			table.insert(descendants, child)
			visit(child)
		end
	end
	visit(root)
	return descendants
end

local function countClasses(dataModel: DataModel): (number, number, number)
	local moduleCount = 0
	local scriptCount = 0
	local localScriptCount = 0
	currentStage = "count_get_descendants"
	local descendants = dataModel:GetDescendants()
	currentStage = "count_iterate_descendants"
	for index, descendant in descendants do
		currentStage = `count_descendant_{index}`
		local className = descendant.ClassName
		if className == "ModuleScript" then
			moduleCount += 1
		elseif className == "Script" then
			scriptCount += 1
		elseif className == "LocalScript" then
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
		if
			descendant.ClassName == "ModuleScript"
			or descendant.ClassName == "Script"
			or descendant.ClassName == "LocalScript"
		then
			local source = (descendant :: LuaSourceContainer).Source
			if
				string.find(source, "ATD_TEST", 1, true) ~= nil
				or string.find(source, "ATD_PHASE06_STUDIO", 1, true) ~= nil
				or string.find(source, "ATD_PHASE07_STUDIO", 1, true) ~= nil
				or string.find(source, "PRIVATE_MODULE_LOAD_VALUE", 1, true) ~= nil
			then
				return true
			end
		end
	end
	return false
end

local function isLuaSourceContainer(instance: Instance): boolean
	return instance.ClassName == "ModuleScript" or instance.ClassName == "Script" or instance.ClassName == "LocalScript"
end

local function expectedProductionSources(role: "Default" | "Lobby" | "Match"): { SourceDefinition }
	local expected: { SourceDefinition } = {}
	for _, source in EXPECTED_PRODUCTION_SOURCES do
		table.insert(expected, source)
	end
	if role ~= "Lobby" then
		for _, source in EXPECTED_MATCH_SERVER_SOURCES do
			table.insert(expected, source)
		end
	end
	return expected
end

local function verifyProductionSources(dataModel: DataModel, definition: BuildDefinition): boolean
	local expectedSources = expectedProductionSources(definition.role :: "Default" | "Lobby" | "Match")
	local expectedByPath: { [string]: SourceDefinition } = {}
	for _, expected in expectedSources do
		if expectedByPath[expected.dataModelPath] ~= nil then
			emit("FAIL", definition.name, "EXPECTED_SOURCE_PATH_DUPLICATE", expected.dataModelPath)
			return false
		end
		expectedByPath[expected.dataModelPath] = expected
	end

	local actualSources: { LuaSourceContainer } = {}
	for _, descendant in dataModel:GetDescendants() do
		if isLuaSourceContainer(descendant) then
			table.insert(actualSources, descendant :: LuaSourceContainer)
		end
	end
	table.sort(actualSources, function(left, right)
		local leftPath = left:GetFullName()
		local rightPath = right:GetFullName()
		if leftPath ~= rightPath then
			return leftPath < rightPath
		end
		if left.ClassName ~= right.ClassName then
			return left.ClassName < right.ClassName
		end
		return left.Source < right.Source
	end)

	local actualByPath: { [string]: LuaSourceContainer } = {}
	local actualPaths: { string } = {}
	local previousPath: string? = nil
	for _, actual in actualSources do
		local path = actual:GetFullName()
		if path == previousPath then
			emit("FAIL", definition.name, "PRODUCTION_SOURCE_PATH_DUPLICATE", path)
			return false
		end
		previousPath = path
		actualByPath[path] = actual
		table.insert(actualPaths, path)
	end

	if #actualPaths ~= #expectedSources then
		emit("FAIL", definition.name, `PRODUCTION_SOURCE_COUNT_{#actualPaths}`)
		return false
	end
	for _, path in actualPaths do
		if expectedByPath[path] == nil then
			emit("FAIL", definition.name, "PRODUCTION_SOURCE_UNEXPECTED", path)
			return false
		end
	end

	for _, expected in expectedSources do
		local actual = actualByPath[expected.dataModelPath]
		if actual == nil then
			emit("FAIL", definition.name, "PRODUCTION_SOURCE_MISSING", expected.dataModelPath)
			return false
		end
		if actual.ClassName ~= expected.className then
			emit("FAIL", definition.name, "PRODUCTION_SOURCE_CLASS_MISMATCH", expected.dataModelPath)
			return false
		end
		if not fs.isFile(expected.sourcePath) then
			emit("FAIL", definition.name, "AUTHORITATIVE_SOURCE_MISSING", expected.dataModelPath)
			return false
		end
		local readSucceeded, expectedSource = pcall(fs.readFile, expected.sourcePath)
		if not readSucceeded then
			emit("FAIL", definition.name, "AUTHORITATIVE_SOURCE_READ_FAILED", expected.dataModelPath)
			return false
		end
		if actual.Source ~= expectedSource then
			emit("FAIL", definition.name, "PRODUCTION_SOURCE_CONTENT_MISMATCH", expected.dataModelPath)
			return false
		end
	end

	return true
end

local function hasChild(parent: Instance?, name: string): boolean
	return parent ~= nil and parent:FindFirstChild(name) ~= nil
end

local function verifyRoleLayers(dataModel: DataModel, role: "Default" | "Lobby" | "Match"): boolean
	local serverContainer = dataModel:GetService("ServerScriptService"):FindFirstChild("Server")
	local starterPlayerScripts = dataModel:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local clientContainer = if starterPlayerScripts == nil then nil else starterPlayerScripts:FindFirstChild("Client")
	if serverContainer == nil or clientContainer == nil then
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

local function hasAncestor(instance: Instance, ancestor: Instance): boolean
	local current = instance.Parent
	while current ~= nil do
		if current == ancestor then
			return true
		end
		current = current.Parent
	end
	return false
end

local function verifyTestOwnedSources(
	dataModel: DataModel,
	definition: BuildDefinition,
	shared: Instance,
	productionServerNetworking: Instance,
	productionClientNetworking: Instance,
	productionServerMaps: Instance
): boolean
	local expectedByPath: { [string]: SourceDefinition } = {}
	for _, expected in EXPECTED_TEST_OWNED_SOURCES do
		if expectedByPath[expected.dataModelPath] ~= nil then
			emit("FAIL", definition.name, "EXPECTED_TEST_SOURCE_PATH_DUPLICATE", expected.dataModelPath)
			return false
		end
		expectedByPath[expected.dataModelPath] = expected
	end

	local actualSources: { ModuleScript } = {}
	for _, descendant in dataModel:GetDescendants() do
		if
			descendant.ClassName == "ModuleScript"
			and not hasAncestor(descendant, shared)
			and not hasAncestor(descendant, productionServerNetworking)
			and not hasAncestor(descendant, productionClientNetworking)
			and not hasAncestor(descendant, productionServerMaps)
		then
			table.insert(actualSources, descendant :: ModuleScript)
		end
	end
	table.sort(actualSources, function(left, right)
		local leftPath = left:GetFullName()
		local rightPath = right:GetFullName()
		if leftPath ~= rightPath then
			return leftPath < rightPath
		end
		return left.Source < right.Source
	end)

	if #actualSources ~= #EXPECTED_TEST_OWNED_SOURCES then
		emit("FAIL", definition.name, `TEST_OWNED_SOURCE_COUNT_{#actualSources}`)
		return false
	end

	local actualByPath: { [string]: ModuleScript } = {}
	local previousPath: string? = nil
	for _, actual in actualSources do
		local path = actual:GetFullName()
		if path == previousPath then
			emit("FAIL", definition.name, "TEST_OWNED_SOURCE_PATH_DUPLICATE", path)
			return false
		end
		previousPath = path
		if expectedByPath[path] == nil then
			emit("FAIL", definition.name, "TEST_OWNED_SOURCE_UNEXPECTED", path)
			return false
		end
		actualByPath[path] = actual
	end

	for _, expected in EXPECTED_TEST_OWNED_SOURCES do
		local actual = actualByPath[expected.dataModelPath]
		if actual == nil then
			emit("FAIL", definition.name, "TEST_OWNED_SOURCE_MISSING", expected.dataModelPath)
			return false
		end
		if actual.ClassName ~= expected.className then
			emit("FAIL", definition.name, "TEST_OWNED_SOURCE_CLASS_MISMATCH", expected.dataModelPath)
			return false
		end
		if not fs.isFile(expected.sourcePath) then
			emit("FAIL", definition.name, "TEST_OWNED_AUTHORITATIVE_SOURCE_MISSING", expected.dataModelPath)
			return false
		end
		local readSucceeded, expectedSource = pcall(fs.readFile, expected.sourcePath)
		if not readSucceeded or actual.Source ~= expectedSource then
			emit("FAIL", definition.name, "TEST_OWNED_SOURCE_CONTENT_MISMATCH", expected.dataModelPath)
			return false
		end
	end

	return true
end

local function verifyProduction(dataModel: DataModel, definition: BuildDefinition): boolean
	currentStage = `verify_counts_{definition.name}`
	local modules, scripts, localScripts = countClasses(dataModel)
	local expectedModules = if definition.role == "Lobby" then 40 else 43
	if modules ~= expectedModules or scripts ~= 1 or localScripts ~= 1 then
		emit("FAIL", definition.name, `PRODUCTION_CLASS_COUNTS_{modules}_{scripts}_{localScripts}`)
		return false
	end
	currentStage = `verify_sources_{definition.name}`
	if not verifyProductionSources(dataModel, definition) then
		return false
	end
	currentStage = `verify_leaks_{definition.name}`
	if hasTestLeak(dataModel) then
		emit("FAIL", definition.name, "TEST_CONTENT_LEAK")
		return false
	end
	currentStage = `verify_layers_{definition.name}`
	if not verifyRoleLayers(dataModel, definition.role :: "Default" | "Lobby" | "Match") then
		emit("FAIL", definition.name, "ROLE_LAYER_ISOLATION")
		return false
	end

	emit("PASS", definition.name, `MODULES_{modules}_SCRIPTS_{scripts}_LOCALSCRIPTS_{localScripts}`)
	return true
end

local function verifyTest(dataModel: DataModel, definition: BuildDefinition): boolean
	local modules, scripts, localScripts = countClasses(dataModel)
	if modules ~= 72 then
		emit("FAIL", definition.name, `TEST_MODULE_COUNT_{modules}`)
		return false
	end
	if scripts ~= 0 or localScripts ~= 0 then
		emit("FAIL", definition.name, "RUNNABLE_SCRIPT_PRESENT")
		return false
	end

	local replicatedStorage = dataModel:GetService("ReplicatedStorage")
	local shared = replicatedStorage:FindFirstChild("Shared")
	local sharedModules = 0
	if shared ~= nil then
		for _, descendant in collectDescendants(shared) do
			if descendant.ClassName == "ModuleScript" then
				sharedModules += 1
			end
		end
	end
	if sharedModules ~= 33 then
		emit("FAIL", definition.name, "SHARED_MODULE_COUNT")
		return false
	end

	local serverStorage = dataModel:GetService("ServerStorage")
	local automatedTests = serverStorage:FindFirstChild("AutomatedTests")
	local productionServerNetworking = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionServerNetworking")
	local productionClientNetworking = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionClientNetworking")
	local productionServerMaps = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionServerMaps")
	local starterPlayerScripts = dataModel:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	if
		automatedTests == nil
		or serverStorage:FindFirstChild("NegativeControls") == nil
		or dataModel:GetService("ServerScriptService"):FindFirstChild("Server") ~= nil
		or (starterPlayerScripts ~= nil and starterPlayerScripts:FindFirstChild("Client") ~= nil)
	then
		emit("FAIL", definition.name, "TEST_BOUNDARY_STRUCTURE")
		return false
	end

	local expectedNetworkingContainers = {
		{
			container = productionServerNetworking,
			sources = {
				{
					moduleName = "ProductionRateLimits",
					sourcePath = "src/server/common/networking/ProductionRateLimits.luau",
				},
				{
					moduleName = "ServerRemoteRegistry",
					sourcePath = "src/server/common/networking/ServerRemoteRegistry.luau",
				},
				{
					moduleName = "ServerRateLimiter",
					sourcePath = "src/server/common/networking/ServerRateLimiter.luau",
				},
				{
					moduleName = "ServerRequestDispatcher",
					sourcePath = "src/server/common/networking/ServerRequestDispatcher.luau",
				},
			},
		},
		{
			container = productionClientNetworking,
			sources = {
				{
					moduleName = "ClientRemoteLookup",
					sourcePath = "src/client/common/networking/ClientRemoteLookup.luau",
				},
				{
					moduleName = "ClientRequestTracker",
					sourcePath = "src/client/common/networking/ClientRequestTracker.luau",
				},
			},
		},
	}
	for _, expectedContainer in expectedNetworkingContainers do
		local container = expectedContainer.container
		if container == nil or container.ClassName ~= "Folder" then
			emit("FAIL", definition.name, "TEST_NETWORKING_CONTAINER_MISSING")
			return false
		end

		local descendants = collectDescendants(container)
		if #descendants ~= #expectedContainer.sources then
			emit("FAIL", definition.name, "TEST_NETWORKING_SOURCE_COUNT")
			return false
		end

		for _, expectedSourceDefinition in expectedContainer.sources do
			local module = container:FindFirstChild(expectedSourceDefinition.moduleName)
			if module == nil or module.ClassName ~= "ModuleScript" then
				emit("FAIL", definition.name, "TEST_NETWORKING_SOURCE_MISMATCH", container:GetFullName())
				return false
			end

			if not fs.isFile(expectedSourceDefinition.sourcePath) then
				emit("FAIL", definition.name, "TEST_NETWORKING_AUTHORITATIVE_SOURCE_MISSING", module:GetFullName())
				return false
			end

			local readSucceeded, expectedSource = pcall(fs.readFile, expectedSourceDefinition.sourcePath)
			if not readSucceeded or (module :: ModuleScript).Source ~= expectedSource then
				emit("FAIL", definition.name, "TEST_NETWORKING_SOURCE_CONTENT_MISMATCH", module:GetFullName())
				return false
			end
		end
	end
	local networkingModules = 6
	if productionServerMaps == nil or productionServerMaps.ClassName ~= "Folder" then
		emit("FAIL", definition.name, "TEST_MAP_CONTAINER_MISSING")
		return false
	end
	local mapDescendants = collectDescendants(productionServerMaps)
	if #mapDescendants ~= #EXPECTED_MATCH_SERVER_SOURCES then
		emit("FAIL", definition.name, "TEST_MAP_SOURCE_COUNT")
		return false
	end
	for _, expectedSourceDefinition in EXPECTED_MATCH_SERVER_SOURCES do
		local moduleName = string.match(expectedSourceDefinition.dataModelPath, "([^.]+)$")
		local module = if moduleName == nil then nil else productionServerMaps:FindFirstChild(moduleName)
		if module == nil or module.ClassName ~= "ModuleScript" then
			emit("FAIL", definition.name, "TEST_MAP_SOURCE_MISMATCH", productionServerMaps:GetFullName())
			return false
		end

		if not fs.isFile(expectedSourceDefinition.sourcePath) then
			emit("FAIL", definition.name, "TEST_MAP_AUTHORITATIVE_SOURCE_MISSING", module:GetFullName())
			return false
		end

		local readSucceeded, expectedSource = pcall(fs.readFile, expectedSourceDefinition.sourcePath)
		if not readSucceeded or (module :: ModuleScript).Source ~= expectedSource then
			emit("FAIL", definition.name, "TEST_MAP_SOURCE_CONTENT_MISMATCH", module:GetFullName())
			return false
		end
	end
	local mapModules = #EXPECTED_MATCH_SERVER_SOURCES
	if
		not verifyTestOwnedSources(
			dataModel,
			definition,
			shared :: Instance,
			productionServerNetworking :: Instance,
			productionClientNetworking :: Instance,
			productionServerMaps :: Instance
		)
	then
		return false
	end
	local testOwnedModules = #EXPECTED_TEST_OWNED_SOURCES

	emit(
		"PASS",
		definition.name,
		`MODULES_{modules}_SHARED_{sharedModules}_NETWORKING_{networkingModules}_MAPS_{mapModules}_TEST_OWNED_{testOwnedModules}_RUNNABLE_SCRIPTS_0`
	)
	return true
end

local function run(): boolean
	currentStage = "build_directory"
	if fs.isFile(BUILD_DIRECTORY) then
		emit("FAIL", "All", "BUILD_PATH_NOT_DIRECTORY")
		return false
	end
	if not fs.isDir(BUILD_DIRECTORY) then
		if not pcall(fs.writeDir, BUILD_DIRECTORY) then
			emit("FAIL", "All", "BUILD_DIRECTORY_CREATE_FAILED")
			return false
		end
		createdBuildDirectory = true
	end

	for _, definition in BUILDS do
		currentStage = `build_{definition.name}`
		if fs.isFile(definition.output) then
			emit("FAIL", definition.name, "OUTPUT_ALREADY_EXISTS")
			return false
		end
		ownedOutputs[definition.output] = true
		local executed, result = pcall(process.exec, "rojo", {
			"build",
			definition.project,
			"--output",
			definition.output,
		})
		if not executed or not (result :: any).ok or not fs.isFile(definition.output) then
			emit("FAIL", definition.name, "BUILD_FAILED")
			return false
		end

		local readSucceeded, contents = pcall(fs.readFile, definition.output)
		if not readSucceeded then
			emit("FAIL", definition.name, "READ_FAILED")
			return false
		end
		currentStage = `deserialize_{definition.name}`
		local parsed, dataModel = pcall(roblox.deserializePlace, contents)
		if not parsed then
			emit("FAIL", definition.name, "DESERIALIZE_FAILED")
			return false
		end

		currentStage = `verify_{definition.name}`
		local verified = if definition.role == "Test"
			then verifyTest(dataModel :: DataModel, definition)
			else verifyProduction(dataModel :: DataModel, definition)
		if not verified then
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
