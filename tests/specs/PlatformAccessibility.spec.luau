--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Accessibility = require(ReplicatedStorage.Shared.settings.Accessibility)
local PlacementCursor = require(ReplicatedStorage.Shared.settings.PlacementCursor)
local FocusNavigation = require(script.Parent.Parent.ProductionClientCommonUi.FocusNavigation)
local TextLayout = require(script.Parent.Parent.ProductionClientCommonUi.TextLayout)
local Localization = require(ReplicatedStorage.Shared.localization.Localization)
local Theme = require(script.Parent.Parent.ProductionClientCommonUi.Theme)

return TestHarness.suite("platform accessibility and focus contracts", {
	TestHarness.case("physical text scale follows nested ancestor transforms", function(assertions)
		local root = Instance.new("Frame")
		local rootScale = Instance.new("UIScale")
		rootScale.Scale = 0.75
		rootScale.Parent = root
		local panel = Instance.new("Frame")
		panel.Size = UDim2.fromOffset(360, 200)
		panel.Parent = root
		local button = Instance.new("TextButton")
		button.Text = "OK"
		button.Size = UDim2.fromOffset(160, 24)
		button.Parent = panel
		assertions.equal(TextLayout.scale(button), 0.75)
		local innerScale = Instance.new("UIScale")
		innerScale.Scale = 1.25
		innerScale.Parent = panel
		assertions.equal(TextLayout.scale(button), 0.9375)
		root:Destroy()
	end),
	TestHarness.case("production preferred text is scaled once by the engine", function(assertions)
		local preferences = Accessibility.readPreferences()
		assertions.equal(preferences.textScale, 1)
		assertions.equal(type(preferences.textPreference), "string")
	end),
	TestHarness.case(
		"notification text and core body pairs meet the source palette contrast floor",
		function(assertions)
			local function luminance(color: Color3): number
				local function linear(channel: number): number
					return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
				end
				return 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
			end
			local function contrast(left: Color3, right: Color3): number
				local first, second = luminance(left), luminance(right)
				return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05)
			end
			for _, background in { Theme.Colors.Success, Theme.Colors.Warning, Theme.Colors.Error, Theme.Colors.Info } do
				assertions.isTrue(contrast(Theme.Colors.Backdrop, background) >= 4.5)
			end
			for _, background in
				{
					Theme.Colors.Surface,
					Theme.Colors.SurfaceRaised,
					Theme.Colors.SurfaceMuted,
					Theme.Colors.AccentStrong,
				}
			do
				assertions.isTrue(contrast(Theme.Colors.Text, background) >= 4.5)
			end
		end
	),
	TestHarness.case("keyboard and stick cursor movement is local bounded and rate independent", function(assertions)
		local viewport = Vector2.new(1000, 500)
		local start = PlacementCursor.step(nil, viewport, Vector2.zero, 0)
		assertions.equal(start, Vector2.new(500, 250))
		local once = PlacementCursor.step(start, viewport, Vector2.new(1, 0), 0.1)
		local twice = PlacementCursor.step(
			PlacementCursor.step(start, viewport, Vector2.new(1, 0), 0.05),
			viewport,
			Vector2.new(1, 0),
			0.05
		)
		assertions.equal(once, twice)
		assertions.equal(
			PlacementCursor.step(Vector2.new(1, 1), viewport, Vector2.new(-1, -1), 10),
			Vector2.new(20, 20)
		)
		assertions.equal(PlacementCursor.step(start, viewport, Vector2.new(0 / 0, 0), 0.1), start)
	end),
	TestHarness.case("Roblox motion preference cannot be overridden by saved effects settings", function(assertions)
		for _, savedMotion in { false, true } do
			for _, robloxMotion in { false, true } do
				local result = Accessibility.resolve({
					reducedMotionEnabled = savedMotion,
					cameraShakeIntensity = 1,
					lowDetailEnabled = false,
					uiScale = 1.25,
				}, { reducedMotion = robloxMotion, textScale = 1.5, transparency = 0 })
				assertions.equal(result.reducedMotion, savedMotion or robloxMotion)
				assertions.equal(result.cameraShakeIntensity, if savedMotion or robloxMotion then 0 else 1)
				assertions.equal(result.uiScale, 1.25)
				assertions.equal(result.textScale, 1.5)
				assertions.equal(result.transparency, 0)
				assertions.isFalse(result.lowDetail)
			end
		end
	end),
	TestHarness.case(
		"transparency follows Roblox opacity semantics and malformed preferences stay bounded",
		function(assertions)
			assertions.equal(Accessibility.resolve({}, { transparency = 1 }).transparency, 0.08)
			assertions.equal(Accessibility.resolve({}, { transparency = 0.5 }).transparency, 0.04)
			local result = Accessibility.resolve(
				{ uiScale = math.huge, cameraShakeIntensity = -1 },
				{ textScale = 0 / 0, transparency = -2 }
			)
			assertions.equal(result.uiScale, 1)
			assertions.equal(result.textScale, 1)
			assertions.equal(result.cameraShakeIntensity, 0)
		end
	),
	TestHarness.case(
		"focus traversal is deterministic skips hidden ancestors and contains the modal scope",
		function(assertions)
			local root = Instance.new("Folder")
			local panel = Instance.new("Frame")
			panel.Parent = root
			local modal = Instance.new("Frame")
			modal.Parent = root
			local first = Instance.new("TextButton")
			first.Name = "First"
			first.SelectionOrder = 1
			first.Active = true
			first.Selectable = true
			first.Parent = panel
			local second = Instance.new("TextButton")
			second.Name = "Second"
			second.SelectionOrder = 2
			second.Active = true
			second.Selectable = true
			second.Parent = panel
			local confirm = Instance.new("TextButton")
			confirm.Active = true
			confirm.Selectable = true
			confirm.Parent = modal
			local controls = FocusNavigation.controls(root, panel)
			assertions.equal(#controls, 2)
			assertions.equal(FocusNavigation.next(controls, first, 1), second)
			assertions.equal(FocusNavigation.next(controls, first, -1), second)
			assertions.equal(FocusNavigation.next(controls, second, 1), first)
			assertions.equal(#FocusNavigation.controls(root, modal), 1)
			panel.Visible = false
			assertions.equal(#FocusNavigation.controls(root), 1)
			confirm.Active = false
			assertions.equal(#FocusNavigation.controls(root), 0)
			assertions.isNil(FocusNavigation.next({}, nil, 1))
			root:Destroy()
		end
	),
	TestHarness.case(
		"expanded text reflows to scrollable rows without shrinking or overlapping controls",
		function(assertions)
			for _, width in { 480, 667, 844, 1024, 1280, 1920, 2560 } do
				for _, scale in { 1, 1.15, 1.5 } do
					for _, mode in { "pseudo30", "pseudo40", "pseudo50" } do
						local expanded = Localization.format(
							"lobby_controller.gold_is_permanent_and_opens_earn_only",
							{},
							mode
						).value
						local height = TextLayout.height(expanded, 16 * scale, math.min(width - 32, 420))
						local plan = TextLayout.plan({ { height = height }, { height = 44 }, { height = 44 } }, 280)
						assertions.isTrue(plan.height <= 280)
						assertions.isTrue(plan.offsets[2] >= plan.offsets[1] + height)
						assertions.isTrue(plan.offsets[3] >= plan.offsets[2] + 44)
						assertions.isTrue(plan.canvasHeight >= plan.offsets[3] + 44)
					end
				end
			end
		end
	),
})
