--!strict

local TestHarness = require(script.Parent.Parent.Parent.Parent.AutomatedTests.Support.TestHarness)

return TestHarness.suite("negative malformed root control", {
	TestHarness.case("would pass if a non Folder discovery root were accepted", function(assertions)
		assertions.isTrue(true)
	end),
})
