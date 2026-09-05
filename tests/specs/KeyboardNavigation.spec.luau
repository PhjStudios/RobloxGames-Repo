--!strict

local Harness = require(script.Parent.Parent.Support.TestHarness)
local Navigation = require(script.Parent.Parent.ProductionClientCommonUi.KeyboardNavigation)

return Harness.suite("keyboard application navigation", {
	Harness.case("Lobby opts into Backspace while Escape remains engine owned", function(a)
		a.isTrue(Navigation.ownsKey(Enum.KeyCode.Tab))
		a.isTrue(Navigation.ownsKey(Enum.KeyCode.F6))
		a.isFalse(Navigation.ownsKey(Enum.KeyCode.Backspace))
		a.isTrue(Navigation.ownsKey(Enum.KeyCode.Backspace, true))
		a.isFalse(Navigation.ownsKey(Enum.KeyCode.Escape, true))
	end),
	Harness.case("app Back passes through for Roblox menus and all focused text boxes", function(a)
		local owned = Instance.new("TextBox")
		local foreign = Instance.new("TextBox")
		a.isTrue(Navigation.appBackAllowed(false, nil))
		a.isFalse(Navigation.appBackAllowed(true, nil))
		for _, focused in { owned, foreign } do
			a.isFalse(Navigation.appBackAllowed(false, focused))
			a.isFalse(Navigation.appBackAllowed(true, focused))
		end
		owned:Destroy()
		foreign:Destroy()
	end),
})
