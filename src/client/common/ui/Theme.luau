--!strict

local function color(red: number, green: number, blue: number): Color3
	local succeeded, value = pcall(function(): Color3
		return Color3.fromRGB(red, green, blue)
	end)
	if succeeded then
		return value
	end
	local proxy = Instance.new("Part")
	local fallback = proxy.Color
	proxy:Destroy()
	return fallback
end

local Theme = {
	Colors = table.freeze({
		Backdrop = color(12, 16, 24),
		Surface = color(25, 32, 45),
		SurfaceRaised = color(36, 46, 63),
		SurfaceMuted = color(63, 74, 94),
		Accent = color(70, 137, 220),
		AccentStrong = color(45, 104, 184),
		Success = color(62, 194, 112),
		Warning = color(244, 178, 61),
		Error = color(229, 83, 83),
		Info = color(91, 174, 238),
		Text = color(247, 249, 252),
		TextMuted = color(173, 184, 203),
		Focus = color(255, 224, 102),
		Scrim = color(4, 7, 12),
	}),
	Spacing = table.freeze({
		Tiny = 4,
		Small = 8,
		Medium = 12,
		Large = 18,
		Huge = 28,
	}),
	Radii = table.freeze({
		Small = 6,
		Medium = 10,
		Large = 16,
	}),
	Stroke = table.freeze({
		Normal = 1,
		Focus = 3,
	}),
	Motion = table.freeze({
		FastSeconds = 0.12,
		NormalSeconds = 0.2,
	}),
	ZIndex = table.freeze({
		Content = 10,
		Navigation = 20,
		Toast = 60,
		ModalScrim = 80,
		Modal = 90,
		Blocking = 100,
	}),
}

return table.freeze(Theme)
