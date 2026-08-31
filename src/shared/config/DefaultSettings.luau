--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

-- Neutral, device-independent defaults. Roblox accessibility preferences are
-- dynamic runtime inputs and are intentionally not serialized here.
local DefaultSettings: ConfigTypes.PlayerSettingsDefaults = {
	version = 2,
	masterVolume = 1,
	musicVolume = 1,
	sfxVolume = 1,
	uiVolume = 1,
	cameraShakeIntensity = 1,
	damageNumbersEnabled = true,
	enemyHealthBarsEnabled = true,
	otherPlayerEffectsEnabled = true,
	lowDetailEnabled = false,
	reducedMotionEnabled = false,
	towerRangeEnabled = true,
	uiScale = 1,
}

return table.freeze(DefaultSettings)
