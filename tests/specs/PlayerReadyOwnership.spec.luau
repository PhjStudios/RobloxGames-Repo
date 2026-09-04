--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local PlayerReadyOwnership = require(script.Parent.Parent.ProductionServerLobbyTravel.PlayerReadyOwnership)

return TestHarness.suite("Lobby player-ready worker ownership", {
	TestHarness.case(
		"keeps a replacement join owned when the departed same-user waiter completes late",
		function(assertions)
			local ownershipByUserId: PlayerReadyOwnership.OwnershipByUserId = {}
			local userId = 11604687814
			local departedPlayer = { name = "A" }
			local replacementPlayer = { name = "B" }

			local departedToken = PlayerReadyOwnership.acquire(ownershipByUserId, userId, departedPlayer)
			assertions.isNotNil(departedToken)
			assertions.isNil(PlayerReadyOwnership.acquire(ownershipByUserId, userId, departedPlayer))

			-- Player A leaves while its profile-ready waiter is suspended. Removal may
			-- release only A's ownership so the same UserId can join again as Player B.
			assertions.isTrue(PlayerReadyOwnership.removePlayer(ownershipByUserId, userId, departedPlayer))
			local replacementToken = PlayerReadyOwnership.acquire(ownershipByUserId, userId, replacementPlayer)
			assertions.isNotNil(replacementToken)
			assertions.notEqual(replacementToken, departedToken)

			-- A stale removal or completion must not clear B's slot. A retry for B
			-- therefore cannot start a duplicate ready pipeline while B still owns it.
			assertions.isFalse(PlayerReadyOwnership.removePlayer(ownershipByUserId, userId, departedPlayer))
			assertions.isFalse(
				PlayerReadyOwnership.release(
					ownershipByUserId,
					userId,
					departedPlayer,
					departedToken :: PlayerReadyOwnership.Token
				)
			)
			assertions.isNil(PlayerReadyOwnership.acquire(ownershipByUserId, userId, replacementPlayer))
			assertions.equal(ownershipByUserId[userId].player, replacementPlayer)

			assertions.isTrue(
				PlayerReadyOwnership.release(
					ownershipByUserId,
					userId,
					replacementPlayer,
					replacementToken :: PlayerReadyOwnership.Token
				)
			)
			assertions.isNil(ownershipByUserId[userId])
		end
	),
	TestHarness.case("requires both the owning Player and token to release a run", function(assertions)
		local ownershipByUserId: PlayerReadyOwnership.OwnershipByUserId = {}
		local userId = 659984992
		local player = {}
		local token = PlayerReadyOwnership.acquire(ownershipByUserId, userId, player)
		assertions.isNotNil(token)

		assertions.isFalse(
			PlayerReadyOwnership.release(ownershipByUserId, userId, {}, token :: PlayerReadyOwnership.Token)
		)
		assertions.isFalse(PlayerReadyOwnership.release(ownershipByUserId, userId, player, {}))
		assertions.isNotNil(ownershipByUserId[userId])
		assertions.isTrue(
			PlayerReadyOwnership.release(ownershipByUserId, userId, player, token :: PlayerReadyOwnership.Token)
		)
	end),
})
