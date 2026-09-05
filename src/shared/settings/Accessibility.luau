--!strict

export type Preferences = { textScale: number, textPreference: string, transparency: number, reducedMotion: boolean }
export type Effective = {
	textScale: number,
	uiScale: number,
	transparency: number,
	reducedMotion: boolean,
	cameraShakeIntensity: number,
	lowDetail: boolean,
}
local Accessibility = {}
local function bounded(value: unknown, minimum: number, maximum: number, fallback: number): number
	return if type(value) == "number"
			and value == value
			and value >= minimum
			and value <= maximum
		then value
		else fallback
end

function Accessibility.resolve(savedValue: unknown, preferencesValue: unknown): Effective
	local saved = if type(savedValue) == "table" then savedValue :: any else {}
	local preferences = if type(preferencesValue) == "table" then preferencesValue :: any else {}
	local reducedMotion = saved.reducedMotionEnabled == true or preferences.reducedMotion == true
	return table.freeze({
		textScale = bounded(preferences.textScale, 0.85, 1.5, 1),
		uiScale = bounded(saved.uiScale, 0.75, 1.25, 1),
		-- Roblox's zero preference means opaque; one retains authored transparency.
		transparency = 0.08 * bounded(preferences.transparency, 0, 1, 1),
		reducedMotion = reducedMotion,
		cameraShakeIntensity = if reducedMotion then 0 else bounded(saved.cameraShakeIntensity, 0, 1, 0),
		lowDetail = saved.lowDetailEnabled == true,
	})
end

function Accessibility.readPreferences(): Preferences
	local result = { textScale = 1, textPreference = "Medium", transparency = 1, reducedMotion = false }
	local succeeded, settings = pcall(function(): any
		return game:GetService("GuiService")
	end)
	if not succeeded then
		return result
	end
	pcall(function()
		local preferred = settings.PreferredTextSize
		local name = if typeof(preferred) == "EnumItem" then preferred.Name else "Medium"
		-- Roblox already scales unscaled text and client TextService measurements.
		-- Keep an independent token for reflow; multiplying TextSize here doubles it.
		result.textPreference = name
	end)
	pcall(function()
		result.transparency = bounded(settings.PreferredTransparency, 0, 1, 1)
	end)
	pcall(function()
		result.reducedMotion = settings.ReducedMotionEnabled == true
	end)
	return result
end

return table.freeze(Accessibility)
