--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local Shared = game:GetService("ReplicatedStorage").Shared
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)

type Assertions = TestHarness.Assertions

local function fieldCount(value: { [any]: unknown }): number
	local count = 0
	for _ in next, value do
		count += 1
	end
	return count
end

local function runLoadedClone(fixtureName: string, mutate: (Folder) -> ()): any
	local configClone = Shared.config:Clone()
	local completed, result = pcall(function()
		configClone.Name = fixtureName
		configClone.Parent = Shared

		local validatorSource = configClone:FindFirstChild("ConfigurationValidator")
		if validatorSource == nil or not validatorSource:IsA("ModuleScript") then
			error("fixture validator unavailable", 0)
		end
		local clonedValidator = require(validatorSource)
		mutate(configClone)
		return (clonedValidator :: any).validateLoaded()
	end)
	local destroyed = pcall(function()
		configClone:Destroy()
	end)
	if not completed or not destroyed then
		error("disposable configuration fixture failed", 0)
	end
	return result
end

local function expectSourceReport(
	assertions: Assertions,
	result: any,
	expectedIssuePaths: { string },
	expectedBlockedFamilies: { string }
)
	assertions.isFalse(result.ok)
	if result.ok then
		return
	end

	local report = result.error
	assertions.equal(report.firstIssue, report.issues[1])
	assertions.equal(#report.issues, #expectedIssuePaths)
	assertions.equal(#report.blockedFamilies, #expectedBlockedFamilies)
	assertions.isTrue(table.isfrozen(result))
	assertions.isTrue(table.isfrozen(report))
	assertions.isTrue(table.isfrozen(report.issues))
	assertions.isTrue(table.isfrozen(report.blockedFamilies))
	for index, expectedPath in expectedIssuePaths do
		local issue = report.issues[index]
		assertions.equal(issue.code, "SOURCE_LOAD_FAILED")
		assertions.equal(issue.path, expectedPath)
		assertions.equal(issue.message, "Authored configuration source failed to load")
		assertions.isTrue(table.isfrozen(issue))
		assertions.isTrue(table.isfrozen(issue.pathSegments))
	end
	for index, expectedFamily in expectedBlockedFamilies do
		assertions.equal(report.blockedFamilies[index], expectedFamily)
	end
end

return TestHarness.suite("lasting and loaded configuration", {
	TestHarness.case("loads the bounded playable local-match production catalog", function(assertions)
		local Assets = require(Shared.config.Assets)
		local Banners = require(Shared.config.Banners)
		local DefaultSettings = require(Shared.config.DefaultSettings)
		local Difficulties = require(Shared.config.Difficulties)
		local Economy = require(Shared.config.Economy)
		local Enemies = require(Shared.config.Enemies)
		local Maps = require(Shared.config.Maps)
		local Towers = require(Shared.config.Towers)
		local Waves = require(Shared.config.Waves)

		assertions.equal(#Assets, 16)
		assertions.equal(#Towers, 3)
		assertions.equal(#Enemies, 4)
		assertions.equal(#Difficulties, 1)
		assertions.equal(#Maps, 1)
		assertions.equal(#Waves, 1)
		assertions.equal(#Banners, 1)
		assertions.equal(Towers[1].id, "tower:dart-ant")
		assertions.equal(Towers[2].id, "tower:rapid-ant")
		assertions.equal(Towers[3].id, "tower:guard-ant")
		assertions.equal(Enemies[4].id, "enemy:garden-queen")
		assertions.equal(Difficulties[1].waveCount, 5)
		assertions.equal(Maps[1].id, "map:phase07-graybox")
		assertions.equal(Waves[1].difficultyId, "difficulty:local")
		assertions.equal(Banners[1].id, "banner:starter")
		assertions.equal(Banners[1].pullOptions.onePull.goldCost, 250)
		assertions.equal(Banners[1].pullOptions.tenPull.goldCost, 2_250)
		assertions.equal(Banners[1].outcomes[1].probabilityPercent, 60)
		assertions.equal(Banners[1].outcomes[2].probabilityPercent, 30)
		assertions.equal(Banners[1].outcomes[3].probabilityPercent, 10)
		assertions.equal(Banners[1].pityRule.hardPityPullCount, 10)
		assertions.equal(Economy.version, 1)
		assertions.equal(Economy.sellRefund.basisPoints, 7_000)
		assertions.equal(Economy.sellRefund.rounding, "Floor")
		assertions.equal(#Economy.difficultyRules, 1)
		assertions.equal(Economy.difficultyRules[1].startingBattleCash, 500)
		assertions.equal(Economy.difficultyRules[1].damageIncome.healthRemovedDenominator, 4)
		assertions.equal(fieldCount(Economy), 3)
		assertions.equal(fieldCount(Economy.sellRefund), 2)
		assertions.equal(DefaultSettings.version, 2)
		assertions.equal(DefaultSettings.masterVolume, 1)
		assertions.equal(DefaultSettings.musicVolume, 1)
		assertions.equal(DefaultSettings.sfxVolume, 1)
		assertions.equal(DefaultSettings.uiVolume, 1)
		assertions.equal(DefaultSettings.cameraShakeIntensity, 1)
		assertions.isTrue(DefaultSettings.damageNumbersEnabled)
		assertions.isTrue(DefaultSettings.enemyHealthBarsEnabled)
		assertions.isTrue(DefaultSettings.otherPlayerEffectsEnabled)
		assertions.isFalse(DefaultSettings.lowDetailEnabled)
		assertions.isFalse(DefaultSettings.reducedMotionEnabled)
		assertions.isTrue(DefaultSettings.towerRangeEnabled)
		assertions.equal(DefaultSettings.uiScale, 1)
		assertions.equal(fieldCount(DefaultSettings), 13)
		assertions.isTrue(table.isfrozen(Assets))
		assertions.isTrue(table.isfrozen(Towers))
		assertions.isTrue(table.isfrozen(Enemies))
		assertions.isTrue(table.isfrozen(Difficulties))
		assertions.isTrue(table.isfrozen(Maps))
		assertions.isTrue(table.isfrozen(Waves))
		assertions.isTrue(table.isfrozen(Banners))
		assertions.isTrue(table.isfrozen(Economy))
		assertions.isTrue(table.isfrozen(Economy.sellRefund))
		assertions.isTrue(table.isfrozen(Economy.difficultyRules))
		assertions.isTrue(table.isfrozen(DefaultSettings))
	end),
	TestHarness.case("authenticates the playable catalog and every cross-reference", function(assertions)
		local result = ConfigurationValidator.validateLoaded()
		assertions.isTrue(result.ok)
		if not result.ok then
			return
		end

		local configuration = result.value
		assertions.isTrue(ConfigurationValidator.isValidatedConfiguration(configuration))
		assertions.equal(#configuration.assets.ordered, 16)
		assertions.equal(#configuration.towers.ordered, 3)
		assertions.equal(#configuration.enemies.ordered, 4)
		assertions.equal(#configuration.difficulties.ordered, 1)
		assertions.equal(#configuration.maps.ordered, 1)
		assertions.equal(#configuration.waves.ordered, 1)
		assertions.equal(#configuration.economy.ordered, 1)
		assertions.equal(#configuration.banners.ordered, 1)
		assertions.equal(configuration.towers.byId["tower:dart-ant"], configuration.towers.ordered[1])
		assertions.equal(configuration.enemies.byId["enemy:garden-queen"], configuration.enemies.ordered[4])
		assertions.equal(configuration.maps.byId["map:phase07-graybox"], configuration.maps.ordered[1])
		assertions.equal(configuration.difficulties.byId["difficulty:local"], configuration.difficulties.ordered[1])
		assertions.equal(
			configuration.waves.byMapId["map:phase07-graybox"]["difficulty:local"],
			configuration.waves.ordered[1]
		)
		assertions.equal(configuration.economy.byDifficultyId["difficulty:local"], configuration.economy.ordered[1])
		assertions.equal(configuration.banners.byId["banner:starter"], configuration.banners.ordered[1])
		assertions.equal(configuration.economy.sellRefund.basisPoints, 7_000)
		assertions.isTrue(table.isfrozen(configuration))
		assertions.isTrue(table.isfrozen(configuration.assets.ordered))
		assertions.isTrue(table.isfrozen(configuration.assets.byKey))
		assertions.isTrue(table.isfrozen(configuration.towers.ordered))
		assertions.isTrue(table.isfrozen(configuration.towers.byId))
		assertions.isTrue(table.isfrozen(configuration.enemies.ordered))
		assertions.isTrue(table.isfrozen(configuration.enemies.byId))
		assertions.isTrue(table.isfrozen(configuration.difficulties.ordered))
		assertions.isTrue(table.isfrozen(configuration.difficulties.byId))
		assertions.isTrue(table.isfrozen(configuration.maps.ordered))
		assertions.isTrue(table.isfrozen(configuration.maps.byId))
		assertions.isTrue(table.isfrozen(configuration.waves.ordered))
		assertions.isTrue(table.isfrozen(configuration.waves.byId))
		assertions.isTrue(table.isfrozen(configuration.waves.byMapId))
		assertions.isTrue(table.isfrozen(configuration.economy.ordered))
		assertions.isTrue(table.isfrozen(configuration.economy.byDifficultyId))
		assertions.isTrue(table.isfrozen(configuration.banners.ordered))
		assertions.isTrue(table.isfrozen(configuration.banners.byId))
	end),
	TestHarness.case("contains a missing authored source with fixed blocked order", function(assertions)
		local fixtureName = "ConfigurationMissingSourceFixture"
		local result = runLoadedClone(fixtureName, function(configClone)
			local source = configClone:FindFirstChild("Assets")
			if source ~= nil then
				source:Destroy()
			end
		end)
		expectSourceReport(assertions, result, { "Assets" }, {
			"Towers",
			"Enemies",
			"Difficulties",
			"Maps",
			"WaveSchedules",
			"Economy",
			"Banners",
			"DefaultSettings",
		})
		assertions.isNil(Shared:FindFirstChild(fixtureName))
	end),
	TestHarness.case("contains a wrong-class authored source with fixed blocked order", function(assertions)
		local fixtureName = "ConfigurationWrongClassSourceFixture"
		local result = runLoadedClone(fixtureName, function(configClone)
			local source = configClone:FindFirstChild("Towers")
			if source ~= nil then
				source:Destroy()
			end
			local replacement = Instance.new("Folder")
			replacement.Name = "Towers"
			replacement.Parent = configClone
		end)
		expectSourceReport(assertions, result, { "Towers" }, {
			"Assets",
			"Enemies",
			"Difficulties",
			"Maps",
			"WaveSchedules",
			"Economy",
			"Banners",
			"DefaultSettings",
		})
		assertions.isNil(Shared:FindFirstChild(fixtureName))
	end),
	TestHarness.case("reports multiple source failures in fixed family order", function(assertions)
		local fixtureName = "ConfigurationMultipleSourceFailureFixture"
		local privateValue = "PRIVATE_SOURCE_LOAD_SENTINEL_7319"
		local result = runLoadedClone(fixtureName, function(configClone)
			local assets = configClone:FindFirstChild("Assets")
			if assets ~= nil and assets:IsA("ModuleScript") then
				assets.Source = `--!strict\nerror("{privateValue}", 0)`
			end

			local maps = configClone:FindFirstChild("Maps")
			if maps ~= nil then
				maps:Destroy()
			end

			local settings = configClone:FindFirstChild("DefaultSettings")
			if settings ~= nil then
				settings:Destroy()
			end
			local wrongClassSettings = Instance.new("Folder")
			wrongClassSettings.Name = "DefaultSettings"
			wrongClassSettings.Parent = configClone
		end)
		expectSourceReport(assertions, result, { "Assets", "Maps", "DefaultSettings" }, {
			"Towers",
			"Enemies",
			"Difficulties",
			"WaveSchedules",
			"Economy",
			"Banners",
		})
		if result.ok then
			return
		end
		for _, issue in result.error.issues do
			assertions.isFalse(string.find(issue.message, privateValue, 1, true) ~= nil)
		end
		assertions.isNil(Shared:FindFirstChild(fixtureName))
	end),
	TestHarness.case("destroys disposable clones even when fixture setup fails", function(assertions)
		local fixtureName = "ConfigurationCleanupFailureFixture"
		local privateValue = "PRIVATE_FIXTURE_SETUP_ERROR_2846"
		local completed, failure = pcall(runLoadedClone, fixtureName, function()
			error(privateValue, 0)
		end)
		assertions.isFalse(completed)
		assertions.isFalse(string.find(tostring(failure), privateValue, 1, true) ~= nil)
		assertions.isNil(Shared:FindFirstChild(fixtureName))
	end),
})
