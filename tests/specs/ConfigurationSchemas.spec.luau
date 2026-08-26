--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Fixtures = require(script.Parent.Parent.Fixtures.ConfigurationFixtures)

local Shared = game:GetService("ReplicatedStorage").Shared
local AssetSchema = require(Shared.config.AssetSchema)
local BannerSchema = require(Shared.config.BannerSchema)
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local DifficultySchema = require(Shared.config.DifficultySchema)
local EconomySchema = require(Shared.config.EconomySchema)
local EnemySchema = require(Shared.config.EnemySchema)
local MapSchema = require(Shared.config.MapSchema)
local SettingsSchema = require(Shared.config.SettingsSchema)
local TowerSchema = require(Shared.config.TowerSchema)
local WaveSchema = require(Shared.config.WaveSchema)

local function validateDependencies(sources: { [string]: any }): { [string]: any }
	local assets = AssetSchema.validateManifest(sources.assets)
	if not assets.ok then
		error("fixture assets failed validation", 0)
	end
	local towers = TowerSchema.validateCatalog(sources.towers, assets.value)
	if not towers.ok then
		error("fixture towers failed validation", 0)
	end
	local enemies = EnemySchema.validateCatalog(sources.enemies, assets.value)
	if not enemies.ok then
		error("fixture enemies failed validation", 0)
	end
	local difficulties = DifficultySchema.validateCatalog(sources.difficulties, assets.value)
	if not difficulties.ok then
		error("fixture difficulties failed validation", 0)
	end
	local maps = MapSchema.validateCatalog(sources.maps, assets.value, difficulties.value)
	if not maps.ok then
		error("fixture maps failed validation", 0)
	end
	local waves = WaveSchema.validateCatalog(sources.waves, maps.value, difficulties.value, enemies.value)
	if not waves.ok then
		error("fixture waves failed validation", 0)
	end
	local economy = EconomySchema.validateConfiguration(sources.economy, difficulties.value)
	if not economy.ok then
		error("fixture economy failed validation", 0)
	end
	local banners = BannerSchema.validateCatalog(sources.banners, towers.value)
	if not banners.ok then
		error("fixture banners failed validation", 0)
	end
	local settings = SettingsSchema.validateDefaults(sources.defaultSettings)
	if not settings.ok then
		error("fixture settings failed validation", 0)
	end

	return {
		assets = assets.value,
		towers = towers.value,
		enemies = enemies.value,
		difficulties = difficulties.value,
		maps = maps.value,
		waves = waves.value,
		economy = economy.value,
		banners = banners.value,
		settings = settings.value,
	}
end

return TestHarness.suite("configuration schemas valid fixtures", {
	TestHarness.case("validates every Phase 04 schema with finite and Endless fixtures", function(assertions)
		local sources = Fixtures.validSources()
		local canonical = validateDependencies(sources)

		assertions.equal(#canonical.assets.ordered, 5)
		assertions.equal(#canonical.towers.ordered, 2)
		assertions.equal(#canonical.enemies.ordered, 1)
		assertions.equal(#canonical.difficulties.ordered, 2)
		assertions.equal(#canonical.maps.ordered, 1)
		assertions.equal(#canonical.waves.ordered, 2)
		assertions.equal(#canonical.economy.ordered, 2)
		assertions.equal(#canonical.banners.ordered, 1)
		assertions.equal(canonical.settings.version, 1)

		assertions.equal(canonical.waves.ordered[1].kind, "AuthoredFinite")
		assertions.equal(canonical.waves.ordered[2].kind, "GeneratedEndless")
		assertions.equal(canonical.waves.byId["wave:normal-2"].rewardClass, "Final")
		assertions.equal(canonical.waves.byId["wave:endless-1"].bossKind, "None")
		assertions.equal(canonical.waves.byMapId["map:garden"]["difficulty:endless"].kind, "GeneratedEndless")
	end),
	TestHarness.case("supports the public single-definition schema entrypoints", function(assertions)
		local sources = Fixtures.validSources()
		local canonical = validateDependencies(sources)
		sources.towers[1].placementCost = -1

		assertions.isTrue(TowerSchema.validateDefinition(sources.towers[1], canonical.assets).ok)
		assertions.isTrue(EnemySchema.validateDefinition(sources.enemies[1], canonical.assets).ok)
		assertions.isTrue(DifficultySchema.validateDefinition(sources.difficulties[1], canonical.assets).ok)
		assertions.isTrue(MapSchema.validateDefinition(sources.maps[1], canonical.assets, canonical.difficulties).ok)
		assertions.isTrue(BannerSchema.validateDefinition(sources.banners[1], canonical.towers).ok)
	end),
	TestHarness.case("authenticates and deeply freezes canonical roots", function(assertions)
		local canonical = validateDependencies(Fixtures.validSources())

		assertions.isTrue(AssetSchema.isValidatedManifest(canonical.assets))
		assertions.isTrue(TowerSchema.isValidatedCatalog(canonical.towers))
		assertions.isTrue(EnemySchema.isValidatedCatalog(canonical.enemies))
		assertions.isTrue(DifficultySchema.isValidatedCatalog(canonical.difficulties))
		assertions.isTrue(MapSchema.isValidatedCatalog(canonical.maps))
		assertions.isTrue(WaveSchema.isValidatedCatalog(canonical.waves))
		assertions.isTrue(EconomySchema.isValidatedConfiguration(canonical.economy))
		assertions.isTrue(BannerSchema.isValidatedCatalog(canonical.banners))
		assertions.isTrue(SettingsSchema.isValidatedDefaults(canonical.settings))
		assertions.isFalse(TowerSchema.isValidatedCatalog({ ordered = {}, byId = {} }))

		assertions.isTrue(table.isfrozen(canonical.assets))
		assertions.isTrue(table.isfrozen(canonical.assets.ordered[1]))
		assertions.isTrue(table.isfrozen(canonical.towers.ordered[1].levels[1].attack))
		assertions.isTrue(table.isfrozen(canonical.waves.byMapId["map:garden"]))
		assertions.isTrue(table.isfrozen(canonical.economy.ordered[1].waveRewards.final.persistentGold))
		assertions.isTrue(table.isfrozen(canonical.banners.ordered[1].pityRule))
	end),
	TestHarness.case("validates the complete representative configuration and detaches raw input", function(assertions)
		local sources = Fixtures.validSources()
		local result = ConfigurationValidator.validate(sources)
		assertions.isTrue(result.ok)
		if not result.ok then
			return
		end

		local configuration = result.value
		assertions.isTrue(ConfigurationValidator.isValidatedConfiguration(configuration))
		assertions.isTrue(table.isfrozen(configuration))
		assertions.isTrue(table.isfrozen(configuration.towers.ordered))
		assertions.equal(configuration.towers.ordered[1].displayName, "Worker Ant")
		sources.towers[1].displayName = "Mutated raw input"
		assertions.equal(configuration.towers.ordered[1].displayName, "Worker Ant")
	end),
})
