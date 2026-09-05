--!strict

local Harness = require(script.Parent.Parent.Support.TestHarness)
local Navigation = require(script.Parent.Parent.ProductionClientCommonUi.FocusNavigation)

return Harness.suite("production focus target validation", {
	Harness.case("only visible enabled controls in the owned GUI may be selected", function(a)
		local root = Instance.new("ScreenGui")
		local panel = Instance.new("Frame")
		panel.Parent = root
		local button = Instance.new("TextButton")
		button.Active = true
		button.Selectable = true
		button.Parent = panel
		a.equal(Navigation.validSelection(root, button), button)
		panel.Visible = false
		a.isNil(Navigation.validSelection(root, button))
		panel.Visible = true
		button.Active = false
		a.isNil(Navigation.validSelection(root, button))
		button.Active = true
		button.Selectable = false
		a.isNil(Navigation.validSelection(root, button))
		button.Selectable = true
		root.Enabled = false
		a.isNil(Navigation.validSelection(root, button))
		root.Enabled = true
		button.Parent = nil
		a.isNil(Navigation.validSelection(root, button))
		button:Destroy()
		root:Destroy()
	end),
	Harness.case("nil detached and destroyed targets clear selection without throwing", function(a)
		local root = Instance.new("ScreenGui")
		local button = Instance.new("TextButton")
		button.Parent = root
		a.isNil(Navigation.validSelection(root, nil))
		a.isNil(Navigation.validSelection(nil, button))
		a.isNil(Navigation.validSelection(root, {}))
		button:Destroy()
		a.isNil(Navigation.validSelection(root, button))
		root:Destroy()
		a.isNil(Navigation.validSelection(root, button))
	end),
})
