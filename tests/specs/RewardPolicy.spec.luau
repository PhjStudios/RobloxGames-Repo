--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RewardPolicy = require(script.Parent.Parent.ProductionServerMatchRewards.RewardPolicy)

local function evidence(overrides: { [string]: any }?): any
	local value = {
		rewardingMatch = true,
		authenticatedParticipant = true,
		spectator = false,
		submittedReady = true,
		placements = 1,
		wavesCompleted = 2,
		connectedAtResults = true,
		outcome = "Victory",
	}
	for key, override in overrides or {} do
		value[key] = override
	end
	return value
end

return TestHarness.suite("authoritative persistent Gold reward policy", {
	TestHarness.case("awards exact victory and one-time first-clear amounts", function(assertions)
		local first = RewardPolicy.evaluate(evidence(), true)
		local repeatResult = RewardPolicy.evaluate(evidence(), false)
		assertions.isTrue(first.ok)
		assertions.equal(first.value.participationGold, 50)
		assertions.equal(first.value.victoryGold, 200)
		assertions.equal(first.value.firstClearGold, 250)
		assertions.equal(first.value.totalGold, 500)
		assertions.equal(repeatResult.value.totalGold, 250)
	end),
	TestHarness.case("awards eligible defeat participation only", function(assertions)
		local evaluated = RewardPolicy.evaluate(evidence({ outcome = "Defeat" }), true)
		assertions.isTrue(evaluated.ok)
		assertions.isTrue(evaluated.value.eligible)
		assertions.equal(evaluated.value.totalGold, 50)
		assertions.equal(evaluated.value.firstClearGold, 0)
	end),
	TestHarness.case("allows an early defeat only when connected at Results", function(assertions)
		local present = RewardPolicy.evaluate(evidence({ outcome = "Defeat", wavesCompleted = 0 }), true)
		local leaver = RewardPolicy.evaluate(
			evidence({ outcome = "Defeat", wavesCompleted = 1, connectedAtResults = false }),
			true
		)
		assertions.isTrue(present.value.eligible)
		assertions.isFalse(leaver.value.eligible)
		assertions.equal(leaver.value.reason, "PARTICIPATION_TOO_SHORT")
	end),
	TestHarness.case("rejects spectators unticketed matches missing Ready and no placement", function(assertions)
		for _, overrides in
			{
				{ spectator = true, authenticatedParticipant = false },
				{ rewardingMatch = false },
				{ submittedReady = false },
				{ placements = 0 },
			}
		do
			local evaluated = RewardPolicy.evaluate(evidence(overrides), true)
			assertions.isTrue(evaluated.ok)
			assertions.isFalse(evaluated.value.eligible)
			assertions.equal(evaluated.value.totalGold, 0)
		end
	end),
	TestHarness.case("accepts disconnected participants after two completed waves", function(assertions)
		local evaluated = RewardPolicy.evaluate(evidence({ connectedAtResults = false, wavesCompleted = 2 }), false)
		assertions.isTrue(evaluated.value.eligible)
		assertions.equal(evaluated.value.totalGold, 250)
	end),
	TestHarness.case("fails closed on malformed evidence", function(assertions)
		assertions.isFalse(RewardPolicy.evaluate({}, true).ok)
		assertions.isFalse(RewardPolicy.evaluate(evidence({ placements = -1 }), true).ok)
		assertions.isFalse(RewardPolicy.evaluate(evidence(), "yes").ok)
	end),
})
