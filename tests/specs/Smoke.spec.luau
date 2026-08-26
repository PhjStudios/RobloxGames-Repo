--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local Result = require(game:GetService("ReplicatedStorage").Shared.util.Result)
local intentionalUnusedLintControl = true

return TestHarness.suite("runner smoke", {
	TestHarness.case("loads one harmless production Result module", function(assertions)
		local result = Result.ok("smoke")
		assertions.isTrue(result.ok)
		assertions.equal(result.value, "smoke")
		assertions.isTrue(table.isfrozen(result))
	end),
	TestHarness.case("keeps connection type adaptation identity scoped", function(assertions)
		local disconnectCount = 0
		local created, connection = pcall(RobloxAdapter.createConnection, function()
			disconnectCount += 1
		end)
		assertions.isTrue(created)
		local connectionType = typeof(connection)
		local ordinaryTableType = typeof({})
		assertions.equal(connectionType, "RBXScriptConnection")
		assertions.equal(ordinaryTableType, "table")
		local disconnected = pcall(function()
			(connection :: any):Disconnect()
		end)
		assertions.isTrue(disconnected)
		assertions.equal(disconnectCount, 1)
	end),
})
