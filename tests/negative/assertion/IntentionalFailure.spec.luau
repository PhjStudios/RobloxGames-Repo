--!strict

local TestHarness = require(script.Parent.Parent.Parent.AutomatedTests.Support.TestHarness)

return TestHarness.suite("negative assertion control", {
	TestHarness.case("reports a controlled assertion failure", function(assertions)
		assertions.equal("PRIVATE_ACTUAL_VALUE", "PRIVATE_EXPECTED_VALUE")
	end),
})
