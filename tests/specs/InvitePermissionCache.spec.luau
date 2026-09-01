--!strict

local ServerStorage = game:GetService("ServerStorage")

local InvitePermissionCache = require(ServerStorage.AutomatedTests.ProductionServerLobbyParty.InvitePermissionCache)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local function makeCache(
	assertions: TestHarness.Assertions
): (InvitePermissionCache.Service, { () -> () }, { now: number })
	local scheduled: { () -> () } = {}
	local clock = { now = 1_000 }
	local created = InvitePermissionCache.new({
		clock = function(): number
			return clock.now
		end,
		schedule = function(callback: () -> ())
			table.insert(scheduled, callback)
		end,
		lookup = function(_inviterUserId: number, targetUserId: number): unknown
			if targetUserId == 99 then
				error("unavailable", 0)
			end
			return targetUserId == 20
		end,
		allowLifetimeSeconds = 20,
		denyLifetimeSeconds = 5,
		maxEntries = 4,
		requestLimit = 2,
		requestWindowSeconds = 10,
	})
	assertions.isTrue(created.ok)
	return created.value, scheduled, clock
end

return TestHarness.suite("bounded invite permission cache", {
	TestHarness.case("fails closed while friendship is unknown then caches the result", function(assertions)
		local cache, scheduled, clock = makeCache(assertions)
		assertions.isNil(cache:get(10, 20))
		assertions.isTrue(cache:request(10, 20).value)
		assertions.equal(#scheduled, 1)
		scheduled[1]()
		assertions.isTrue(cache:get(10, 20))
		assertions.isFalse(cache:request(10, 20).value)
		clock.now += 20
		assertions.isNil(cache:get(10, 20))
	end),

	TestHarness.case("caches a denial but never converts lookup failure into permission", function(assertions)
		local cache, scheduled = makeCache(assertions)
		assertions.isTrue(cache:request(10, 30).value)
		scheduled[1]()
		assertions.isFalse(cache:get(10, 30))
		assertions.isTrue(cache:request(10, 99).value)
		scheduled[2]()
		assertions.isNil(cache:get(10, 99))
		assertions.equal(cache:getMetrics().lookupFailureCount, 1)
	end),

	TestHarness.case("bounds request rate and clears private context on leave", function(assertions)
		local cache, scheduled = makeCache(assertions)
		assertions.isTrue(cache:request(10, 20).ok)
		assertions.isTrue(cache:request(10, 30).ok)
		assertions.isFalse(cache:request(10, 40).ok)
		scheduled[1]()
		scheduled[2]()
		assertions.isTrue(cache:removePlayer(10))
		assertions.isNil(cache:get(10, 20))
		assertions.equal(cache:getMetrics().entryCount, 0)
	end),
})
