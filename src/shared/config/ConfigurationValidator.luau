--!strict

local AssetSchema = require(script.Parent.AssetSchema)
local BannerSchema = require(script.Parent.BannerSchema)
local DifficultySchema = require(script.Parent.DifficultySchema)
local EconomySchema = require(script.Parent.EconomySchema)
local EnemySchema = require(script.Parent.EnemySchema)
local MapSchema = require(script.Parent.MapSchema)
local SettingsSchema = require(script.Parent.SettingsSchema)
local TowerSchema = require(script.Parent.TowerSchema)
local WaveSchema = require(script.Parent.WaveSchema)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type Family =
	"Assets"
	| "Towers"
	| "Enemies"
	| "Difficulties"
	| "Maps"
	| "WaveSchedules"
	| "Economy"
	| "Banners"
	| "DefaultSettings"

export type Report = {
	firstIssue: Validation.Issue,
	issues: { Validation.Issue },
	blockedFamilies: { Family },
}

export type ValidationResult = Result.Result<ConfigTypes.CoreConfiguration, Report>

local ROOT_PATH: { Validation.PathSegment } = { "Configuration" }
local ALL_FAMILIES: { Family } = table.freeze({
	"Assets",
	"Towers",
	"Enemies",
	"Difficulties",
	"Maps",
	"WaveSchedules",
	"Economy",
	"Banners",
	"DefaultSettings",
})
local FAMILY_COUNT = #ALL_FAMILIES
local SOURCE_FIELDS: { [string]: boolean } = table.freeze({
	assets = true,
	banners = true,
	defaultSettings = true,
	difficulties = true,
	economy = true,
	enemies = true,
	maps = true,
	towers = true,
	waves = true,
})
local NO_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({})

local validatedConfigurations: { [ConfigTypes.CoreConfiguration]: boolean } = setmetatable({}, {
	__mode = "k",
}) :: any

local ConfigurationValidator = {
	FAMILY_COUNT = FAMILY_COUNT,
}

local function copyAndFreezeIssues(issues: { Validation.Issue }): { Validation.Issue }
	local copy: { Validation.Issue } = table.create(#issues)
	for index = 1, #issues do
		copy[index] = issues[index]
	end
	return table.freeze(copy)
end

local function copyAndFreezeFamilies(families: { Family }): { Family }
	local copy: { Family } = table.create(#families)
	for index = 1, #families do
		copy[index] = families[index]
	end
	return table.freeze(copy)
end

local function report(issues: { Validation.Issue }, blockedFamilies: { Family }): Report
	local firstIssue = issues[1]
	if firstIssue == nil then
		error("Configuration validation reports require at least one issue", 0)
	end

	return table.freeze({
		firstIssue = firstIssue,
		issues = copyAndFreezeIssues(issues),
		blockedFamilies = copyAndFreezeFamilies(blockedFamilies),
	})
end

local function loadSource(sourceName: string, family: Family): (unknown, Validation.Issue?)
	local source = script.Parent:FindFirstChild(sourceName)
	if source == nil or not source:IsA("ModuleScript") then
		return nil, Validation.issue("SOURCE_LOAD_FAILED", { family }, "Authored configuration source failed to load")
	end

	local succeeded, value = pcall(require, source)
	if not succeeded then
		return nil, Validation.issue("SOURCE_LOAD_FAILED", { family }, "Authored configuration source failed to load")
	end

	return value, nil
end

local function readSources(value: unknown): (ConfigTypes.AuthoredConfigurationSources?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, ROOT_PATH, SOURCE_FIELDS, NO_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local assets, assetsIssue = Validation.getRequiredField(record :: Validation.RawObject, "assets", ROOT_PATH)
	if assetsIssue ~= nil then
		return nil, assetsIssue
	end
	local towers, towersIssue = Validation.getRequiredField(record :: Validation.RawObject, "towers", ROOT_PATH)
	if towersIssue ~= nil then
		return nil, towersIssue
	end
	local enemies, enemiesIssue = Validation.getRequiredField(record :: Validation.RawObject, "enemies", ROOT_PATH)
	if enemiesIssue ~= nil then
		return nil, enemiesIssue
	end
	local difficulties, difficultiesIssue =
		Validation.getRequiredField(record :: Validation.RawObject, "difficulties", ROOT_PATH)
	if difficultiesIssue ~= nil then
		return nil, difficultiesIssue
	end
	local maps, mapsIssue = Validation.getRequiredField(record :: Validation.RawObject, "maps", ROOT_PATH)
	if mapsIssue ~= nil then
		return nil, mapsIssue
	end
	local waves, wavesIssue = Validation.getRequiredField(record :: Validation.RawObject, "waves", ROOT_PATH)
	if wavesIssue ~= nil then
		return nil, wavesIssue
	end
	local economy, economyIssue = Validation.getRequiredField(record :: Validation.RawObject, "economy", ROOT_PATH)
	if economyIssue ~= nil then
		return nil, economyIssue
	end
	local banners, bannersIssue = Validation.getRequiredField(record :: Validation.RawObject, "banners", ROOT_PATH)
	if bannersIssue ~= nil then
		return nil, bannersIssue
	end
	local defaultSettings, defaultSettingsIssue =
		Validation.getRequiredField(record :: Validation.RawObject, "defaultSettings", ROOT_PATH)
	if defaultSettingsIssue ~= nil then
		return nil, defaultSettingsIssue
	end

	local sources: ConfigTypes.AuthoredConfigurationSources = table.freeze({
		assets = assets,
		towers = towers,
		enemies = enemies,
		difficulties = difficulties,
		maps = maps,
		waves = waves,
		economy = economy,
		banners = banners,
		defaultSettings = defaultSettings,
	})
	return sources, nil
end

function ConfigurationValidator.validate(value: unknown): ValidationResult
	local sources, sourceIssue = readSources(value)
	if sourceIssue ~= nil then
		return Result.err(report({ sourceIssue }, ALL_FAMILIES))
	end

	local authored = sources :: ConfigTypes.AuthoredConfigurationSources
	local issues: { Validation.Issue } = {}
	local blockedFamilies: { Family } = {}

	local assets: ConfigTypes.AssetManifest? = nil
	local towers: ConfigTypes.TowerCatalog? = nil
	local enemies: ConfigTypes.EnemyCatalog? = nil
	local difficulties: ConfigTypes.DifficultyCatalog? = nil
	local maps: ConfigTypes.MapCatalog? = nil
	local waves: ConfigTypes.WaveCatalog? = nil
	local economy: ConfigTypes.EconomyConfiguration? = nil
	local banners: ConfigTypes.BannerCatalog? = nil
	local defaultSettings: ConfigTypes.PlayerSettingsDefaults? = nil

	local assetsResult = AssetSchema.validateManifest(authored.assets)
	if assetsResult.ok then
		assets = assetsResult.value
	else
		table.insert(issues, assetsResult.error)
	end

	if assets ~= nil then
		local towersResult = TowerSchema.validateCatalog(authored.towers, assets)
		if towersResult.ok then
			towers = towersResult.value
		else
			table.insert(issues, towersResult.error)
		end
	else
		table.insert(blockedFamilies, "Towers")
	end

	if assets ~= nil then
		local enemiesResult = EnemySchema.validateCatalog(authored.enemies, assets)
		if enemiesResult.ok then
			enemies = enemiesResult.value
		else
			table.insert(issues, enemiesResult.error)
		end
	else
		table.insert(blockedFamilies, "Enemies")
	end

	if assets ~= nil then
		local difficultiesResult = DifficultySchema.validateCatalog(authored.difficulties, assets)
		if difficultiesResult.ok then
			difficulties = difficultiesResult.value
		else
			table.insert(issues, difficultiesResult.error)
		end
	else
		table.insert(blockedFamilies, "Difficulties")
	end

	if assets ~= nil and difficulties ~= nil then
		local mapsResult = MapSchema.validateCatalog(authored.maps, assets, difficulties)
		if mapsResult.ok then
			maps = mapsResult.value
		else
			table.insert(issues, mapsResult.error)
		end
	else
		table.insert(blockedFamilies, "Maps")
	end

	if maps ~= nil and difficulties ~= nil and enemies ~= nil then
		local wavesResult = WaveSchema.validateCatalog(authored.waves, maps, difficulties, enemies)
		if wavesResult.ok then
			waves = wavesResult.value
		else
			table.insert(issues, wavesResult.error)
		end
	else
		table.insert(blockedFamilies, "WaveSchedules")
	end

	if difficulties ~= nil then
		local economyResult = EconomySchema.validateConfiguration(authored.economy, difficulties)
		if economyResult.ok then
			economy = economyResult.value
		else
			table.insert(issues, economyResult.error)
		end
	else
		table.insert(blockedFamilies, "Economy")
	end

	if towers ~= nil then
		local bannersResult = BannerSchema.validateCatalog(authored.banners, towers)
		if bannersResult.ok then
			banners = bannersResult.value
		else
			table.insert(issues, bannersResult.error)
		end
	else
		table.insert(blockedFamilies, "Banners")
	end

	local settingsResult = SettingsSchema.validateDefaults(authored.defaultSettings)
	if settingsResult.ok then
		defaultSettings = settingsResult.value
	else
		table.insert(issues, settingsResult.error)
	end

	if #issues > 0 then
		return Result.err(report(issues, blockedFamilies))
	end

	local configuration: ConfigTypes.CoreConfiguration = table.freeze({
		assets = assets :: ConfigTypes.AssetManifest,
		towers = towers :: ConfigTypes.TowerCatalog,
		enemies = enemies :: ConfigTypes.EnemyCatalog,
		difficulties = difficulties :: ConfigTypes.DifficultyCatalog,
		maps = maps :: ConfigTypes.MapCatalog,
		waves = waves :: ConfigTypes.WaveCatalog,
		economy = economy :: ConfigTypes.EconomyConfiguration,
		banners = banners :: ConfigTypes.BannerCatalog,
		defaultSettings = defaultSettings :: ConfigTypes.PlayerSettingsDefaults,
	})
	validatedConfigurations[configuration] = true
	return Result.ok(configuration)
end

function ConfigurationValidator.validateLoaded(): ValidationResult
	local issues: { Validation.Issue } = {}

	local assets, assetsIssue = loadSource("Assets", "Assets")
	if assetsIssue ~= nil then
		table.insert(issues, assetsIssue)
	end
	local towers, towersIssue = loadSource("Towers", "Towers")
	if towersIssue ~= nil then
		table.insert(issues, towersIssue)
	end
	local enemies, enemiesIssue = loadSource("Enemies", "Enemies")
	if enemiesIssue ~= nil then
		table.insert(issues, enemiesIssue)
	end
	local difficulties, difficultiesIssue = loadSource("Difficulties", "Difficulties")
	if difficultiesIssue ~= nil then
		table.insert(issues, difficultiesIssue)
	end
	local maps, mapsIssue = loadSource("Maps", "Maps")
	if mapsIssue ~= nil then
		table.insert(issues, mapsIssue)
	end
	local waves, wavesIssue = loadSource("Waves", "WaveSchedules")
	if wavesIssue ~= nil then
		table.insert(issues, wavesIssue)
	end
	local economy, economyIssue = loadSource("Economy", "Economy")
	if economyIssue ~= nil then
		table.insert(issues, economyIssue)
	end
	local banners, bannersIssue = loadSource("Banners", "Banners")
	if bannersIssue ~= nil then
		table.insert(issues, bannersIssue)
	end
	local defaultSettings, defaultSettingsIssue = loadSource("DefaultSettings", "DefaultSettings")
	if defaultSettingsIssue ~= nil then
		table.insert(issues, defaultSettingsIssue)
	end

	if #issues > 0 then
		local blockedFamilies: { Family } = {}
		if assetsIssue == nil then
			table.insert(blockedFamilies, "Assets")
		end
		if towersIssue == nil then
			table.insert(blockedFamilies, "Towers")
		end
		if enemiesIssue == nil then
			table.insert(blockedFamilies, "Enemies")
		end
		if difficultiesIssue == nil then
			table.insert(blockedFamilies, "Difficulties")
		end
		if mapsIssue == nil then
			table.insert(blockedFamilies, "Maps")
		end
		if wavesIssue == nil then
			table.insert(blockedFamilies, "WaveSchedules")
		end
		if economyIssue == nil then
			table.insert(blockedFamilies, "Economy")
		end
		if bannersIssue == nil then
			table.insert(blockedFamilies, "Banners")
		end
		if defaultSettingsIssue == nil then
			table.insert(blockedFamilies, "DefaultSettings")
		end
		return Result.err(report(issues, blockedFamilies))
	end

	local sources: ConfigTypes.AuthoredConfigurationSources = table.freeze({
		assets = assets,
		towers = towers,
		enemies = enemies,
		difficulties = difficulties,
		maps = maps,
		waves = waves,
		economy = economy,
		banners = banners,
		defaultSettings = defaultSettings,
	})
	return ConfigurationValidator.validate(sources)
end

function ConfigurationValidator.isValidatedConfiguration(value: unknown): boolean
	return type(value) == "table" and validatedConfigurations[value :: any] == true
end

return table.freeze(ConfigurationValidator)
