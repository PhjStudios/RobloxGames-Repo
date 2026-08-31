--!strict

local SchemaPrimitives = require(script.Parent.SchemaPrimitives)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

local ROOT_PATH: { Validation.PathSegment } = { "DefaultSettings" }

local SETTINGS_FIELDS: { [string]: boolean } = table.freeze({
	cameraShakeIntensity = true,
	damageNumbersEnabled = true,
	enemyHealthBarsEnabled = true,
	lowDetailEnabled = true,
	masterVolume = true,
	musicVolume = true,
	otherPlayerEffectsEnabled = true,
	reducedMotionEnabled = true,
	sfxVolume = true,
	towerRangeEnabled = true,
	uiScale = true,
	uiVolume = true,
	version = true,
})

local SETTINGS_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	connection = true,
	dirty = true,
	instance = true,
	player = true,
	profile = true,
	savedAt = true,
	userId = true,
})

local CURRENT_VERSION = 2
local MIN_VOLUME = 0
local MAX_VOLUME = 1
local MIN_CAMERA_SHAKE_INTENSITY = 0
local MAX_CAMERA_SHAKE_INTENSITY = 1
local MIN_UI_SCALE = 0.75
local MAX_UI_SCALE = 1.25

local validatedDefaults: { [ConfigTypes.PlayerSettingsDefaults]: boolean } = setmetatable({}, {
	__mode = "k",
}) :: any

local SettingsSchema = {
	CURRENT_VERSION = CURRENT_VERSION,
	MIN_VOLUME = MIN_VOLUME,
	MAX_VOLUME = MAX_VOLUME,
	MIN_CAMERA_SHAKE_INTENSITY = MIN_CAMERA_SHAKE_INTENSITY,
	MAX_CAMERA_SHAKE_INTENSITY = MAX_CAMERA_SHAKE_INTENSITY,
	MIN_UI_SCALE = MIN_UI_SCALE,
	MAX_UI_SCALE = MAX_UI_SCALE,
}

function SettingsSchema.validateDefaults(
	value: unknown
): Result.Result<ConfigTypes.PlayerSettingsDefaults, Validation.Issue>
	local record, recordIssue = Validation.readObject(value, ROOT_PATH, SETTINGS_FIELDS, SETTINGS_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return Result.err(recordIssue)
	end

	local version, versionIssue =
		SchemaPrimitives.supportedVersion(record :: Validation.RawObject, "version", ROOT_PATH, CURRENT_VERSION)
	if versionIssue ~= nil then
		return Result.err(versionIssue)
	end

	local masterVolume, masterVolumeIssue = SchemaPrimitives.boundedNumber(
		record :: Validation.RawObject,
		"masterVolume",
		ROOT_PATH,
		MIN_VOLUME,
		MAX_VOLUME
	)
	if masterVolumeIssue ~= nil then
		return Result.err(masterVolumeIssue)
	end

	local musicVolume, musicVolumeIssue =
		SchemaPrimitives.boundedNumber(record :: Validation.RawObject, "musicVolume", ROOT_PATH, MIN_VOLUME, MAX_VOLUME)
	if musicVolumeIssue ~= nil then
		return Result.err(musicVolumeIssue)
	end

	local sfxVolume, sfxVolumeIssue =
		SchemaPrimitives.boundedNumber(record :: Validation.RawObject, "sfxVolume", ROOT_PATH, MIN_VOLUME, MAX_VOLUME)
	if sfxVolumeIssue ~= nil then
		return Result.err(sfxVolumeIssue)
	end

	local uiVolume, uiVolumeIssue =
		SchemaPrimitives.boundedNumber(record :: Validation.RawObject, "uiVolume", ROOT_PATH, MIN_VOLUME, MAX_VOLUME)
	if uiVolumeIssue ~= nil then
		return Result.err(uiVolumeIssue)
	end

	local cameraShakeIntensity, cameraShakeIssue = SchemaPrimitives.boundedNumber(
		record :: Validation.RawObject,
		"cameraShakeIntensity",
		ROOT_PATH,
		MIN_CAMERA_SHAKE_INTENSITY,
		MAX_CAMERA_SHAKE_INTENSITY
	)
	if cameraShakeIssue ~= nil then
		return Result.err(cameraShakeIssue)
	end

	local damageNumbersEnabled, damageNumbersIssue =
		SchemaPrimitives.requiredBoolean(record :: Validation.RawObject, "damageNumbersEnabled", ROOT_PATH)
	if damageNumbersIssue ~= nil then
		return Result.err(damageNumbersIssue)
	end

	local enemyHealthBarsEnabled, enemyHealthBarsIssue =
		SchemaPrimitives.requiredBoolean(record :: Validation.RawObject, "enemyHealthBarsEnabled", ROOT_PATH)
	if enemyHealthBarsIssue ~= nil then
		return Result.err(enemyHealthBarsIssue)
	end

	local otherPlayerEffectsEnabled, otherPlayerEffectsIssue =
		SchemaPrimitives.requiredBoolean(record :: Validation.RawObject, "otherPlayerEffectsEnabled", ROOT_PATH)
	if otherPlayerEffectsIssue ~= nil then
		return Result.err(otherPlayerEffectsIssue)
	end

	local lowDetailEnabled, lowDetailIssue =
		SchemaPrimitives.requiredBoolean(record :: Validation.RawObject, "lowDetailEnabled", ROOT_PATH)
	if lowDetailIssue ~= nil then
		return Result.err(lowDetailIssue)
	end

	local reducedMotionEnabled, reducedMotionIssue =
		SchemaPrimitives.requiredBoolean(record :: Validation.RawObject, "reducedMotionEnabled", ROOT_PATH)
	if reducedMotionIssue ~= nil then
		return Result.err(reducedMotionIssue)
	end

	local towerRangeEnabled, towerRangeIssue =
		SchemaPrimitives.requiredBoolean(record :: Validation.RawObject, "towerRangeEnabled", ROOT_PATH)
	if towerRangeIssue ~= nil then
		return Result.err(towerRangeIssue)
	end

	local uiScale, uiScaleIssue =
		SchemaPrimitives.boundedNumber(record :: Validation.RawObject, "uiScale", ROOT_PATH, MIN_UI_SCALE, MAX_UI_SCALE)
	if uiScaleIssue ~= nil then
		return Result.err(uiScaleIssue)
	end

	local defaults: ConfigTypes.PlayerSettingsDefaults = table.freeze({
		version = version :: ConfigTypes.ConfigurationVersion,
		masterVolume = masterVolume :: number,
		musicVolume = musicVolume :: number,
		sfxVolume = sfxVolume :: number,
		uiVolume = uiVolume :: number,
		cameraShakeIntensity = cameraShakeIntensity :: number,
		damageNumbersEnabled = damageNumbersEnabled :: boolean,
		enemyHealthBarsEnabled = enemyHealthBarsEnabled :: boolean,
		otherPlayerEffectsEnabled = otherPlayerEffectsEnabled :: boolean,
		lowDetailEnabled = lowDetailEnabled :: boolean,
		reducedMotionEnabled = reducedMotionEnabled :: boolean,
		towerRangeEnabled = towerRangeEnabled :: boolean,
		uiScale = uiScale :: number,
	})
	validatedDefaults[defaults] = true
	return Result.ok(defaults)
end

function SettingsSchema.isValidatedDefaults(value: unknown): boolean
	return type(value) == "table" and validatedDefaults[value :: any] == true
end

return table.freeze(SettingsSchema)
