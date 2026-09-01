--!strict

local ServerStorage = game:GetService("ServerStorage")

local PlatformInviteAdapter = require(ServerStorage.AutomatedTests.ProductionServerLobbyParty.PlatformInviteAdapter)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

return TestHarness.suite("bounded platform invite adapter", {
	TestHarness.case("round-trips only bounded supplementary launch hints", function(assertions)
		local built = PlatformInviteAdapter.buildLaunchData(42, "invitation:opaque-1")
		assertions.isTrue(built.ok)
		if built.ok then
			assertions.isFalse(string.find(built.value, "reserved", 1, true) ~= nil)
			local parsed = PlatformInviteAdapter.parseLaunchData(built.value)
			assertions.isTrue(parsed.ok)
			if parsed.ok then
				assertions.equal(parsed.value.inviterUserId, 42)
				assertions.equal(parsed.value.partyIntentId, "invitation:opaque-1")
				assertions.equal(parsed.value.version, 1)
			end
		end
		for _, invalid in
			{
				"",
				"party:opaque-1",
				"atd-party-v1|42|party:not-an-invitation",
				`atd-party-v1|42|invitation:{string.rep("x", 200)}`,
			}
		do
			assertions.isFalse(PlatformInviteAdapter.parseLaunchData(invalid).ok)
		end
	end),

	TestHarness.case("falls back safely when prompting is denied or unavailable", function(assertions)
		local player = Instance.new("Player")
		player.UserId = 42
		local denied = PlatformInviteAdapter.new({
			canPrompt = function(_player: Player): boolean
				return false
			end,
			prompt = function(_player: Player, _launchData: string): boolean
				error("must not prompt", 0)
			end,
		})
		assertions.isTrue(denied.ok)
		if denied.ok then
			local result = denied.value:prompt(player, 42, "invitation:opaque-1")
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.equal(result.value, "Denied")
			end
		end

		local unavailable = PlatformInviteAdapter.new({
			canPrompt = function(_player: Player): boolean
				error("platform unavailable", 0)
			end,
			prompt = function(_player: Player, _launchData: string): boolean
				return true
			end,
		})
		if unavailable.ok then
			local result = unavailable.value:prompt(player, 42, "invitation:opaque-1")
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.equal(result.value, "Unavailable")
			end
		end
		player:Destroy()
	end),
})
