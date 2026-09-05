--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local ResponsiveLayout = require(script.Parent.Parent.ProductionClientCommonUi.ResponsiveLayout)

return TestHarness.suite("responsive Lobby layout rules", {
	TestHarness.case("supports the usable safe area of the smallest landscape phone", function(assertions)
		local layout = ResponsiveLayout.resolve(Vector2.new(666, 316), 1, 1.5)
		assertions.isNotNil(layout)
		assertions.equal((layout :: any).mode, "Compact")
		assertions.equal((layout :: any).baseTextSize, 24)
		assertions.isTrue((layout :: any).touchTarget >= 44)
	end),
	TestHarness.case("resolves compact standard and ten-foot safe layouts", function(assertions)
		local compact = ResponsiveLayout.resolve(Vector2.new(375, 667), 1, 1)
		local standard = ResponsiveLayout.resolve(Vector2.new(1280, 720), 1, 1)
		local tenFoot = ResponsiveLayout.resolve(Vector2.new(1920, 1080), 1, 1)
		assertions.isNotNil(compact)
		assertions.isNotNil(standard)
		assertions.isNotNil(tenFoot)
		assertions.equal((compact :: any).mode, "Compact")
		assertions.equal((compact :: any).navigationWidth, 0)
		assertions.isTrue((compact :: any).touchTarget >= 48)
		assertions.equal((standard :: any).mode, "Standard")
		assertions.isTrue((standard :: any).inventoryColumns >= 2)
		assertions.equal((tenFoot :: any).mode, "TenFoot")
		assertions.isTrue((tenFoot :: any).touchTarget >= 64)
		assertions.isTrue((tenFoot :: any).baseTextSize > (standard :: any).baseTextSize)
		assertions.isTrue(table.isfrozen(tenFoot :: any))
	end),

	TestHarness.case("accounts for UI and preferred text scale without unbounded columns", function(assertions)
		local enlarged = ResponsiveLayout.resolve(Vector2.new(1280, 720), 1.25, 1.5)
		local baseline = ResponsiveLayout.resolve(Vector2.new(1280, 720), 1, 1)
		assertions.isNotNil(enlarged)
		assertions.isNotNil(baseline)
		assertions.isTrue((enlarged :: any).logicalWidth < (baseline :: any).logicalWidth)
		assertions.isTrue((enlarged :: any).baseTextSize > (baseline :: any).baseTextSize)
		assertions.isTrue((enlarged :: any).inventoryColumns <= ResponsiveLayout.MAX_COLUMNS)
		assertions.isTrue((enlarged :: any).cardWidth >= 132)
	end),

	TestHarness.case("fails closed for malformed viewports and accessibility scales", function(assertions)
		assertions.isNil(ResponsiveLayout.resolve(Vector2.new(120, 200), 1, 1))
		assertions.isNil(ResponsiveLayout.resolve(Vector2.new(1280, 720), 0.5, 1))
		assertions.isNil(ResponsiveLayout.resolve(Vector2.new(1280, 720), 1, 2))
		assertions.isNil(ResponsiveLayout.resolve({ X = 1280, Y = 720 }, 1, 1))
		assertions.isNil(ResponsiveLayout.resolve(Vector2.new(0 / 0, 720), 1, 1))
	end),
})
