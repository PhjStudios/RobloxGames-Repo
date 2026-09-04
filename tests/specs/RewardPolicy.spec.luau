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

local function currentEvidence(difficultyId: string, modeKind: "Finite" | "Endless", waveNumber: number): any
	return evidence({
		resultVersion = 2,
		difficultyId = difficultyId,
		modeKind = modeKind,
		highestCompletedWave = waveNumber,
		wavesCompleted = waveNumber,
		outcome = if modeKind == "Endless" then "Defeat" else "Victory",
	})
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
	TestHarness.case("applies the locked finite reward table without changing v1 records", function(assertions)
		local expected = {
			["difficulty:easy-v1"] = { 50, 150, 150, 350 },
			["difficulty:normal-v1"] = { 65, 235, 225, 525 },
			["difficulty:hard-v1"] = { 85, 365, 325, 775 },
		}
		for difficultyId, amounts in expected do
			local evaluated = RewardPolicy.evaluate(currentEvidence(difficultyId, "Finite", 20), true)
			assertions.isTrue(evaluated.ok)
			assertions.equal(evaluated.value.participationGold, amounts[1])
			assertions.equal(evaluated.value.victoryGold, amounts[2])
			assertions.equal(evaluated.value.firstClearGold, amounts[3])
			assertions.equal(evaluated.value.totalGold, amounts[4])
		end
		local localFallback = RewardPolicy.evaluate(currentEvidence("difficulty:local", "Finite", 5), true)
		assertions.isTrue(localFallback.ok)
		assertions.equal(localFallback.value.totalGold, 0)
	end),
	TestHarness.case("uses only completed-wave milestones for one capped Endless terminal award", function(assertions)
		local expected = {
			[4] = 0,
			[5] = 25,
			[9] = 25,
			[10] = 50,
			[109] = 275,
			[110] = 300,
			[10_000] = 300,
		}
		for waveNumber, totalGold in expected do
			local evaluated =
				RewardPolicy.evaluate(currentEvidence("difficulty:endless-v1", "Endless", waveNumber), true)
			assertions.isTrue(evaluated.ok)
			assertions.equal(evaluated.value.totalGold, totalGold)
			assertions.equal(evaluated.value.victoryGold, 0)
			assertions.equal(evaluated.value.firstClearGold, 0)
			assertions.equal(evaluated.value.eligible, waveNumber >= 5)
		end
		local impossible = currentEvidence("difficulty:endless-v1", "Endless", 10)
		impossible.outcome = "Victory"
		assertions.isFalse(RewardPolicy.evaluate(impossible, true).ok)

		local earlyLeaver = currentEvidence("difficulty:endless-v1", "Endless", 110)
		earlyLeaver.wavesCompleted = 9
		earlyLeaver.connectedAtResults = false
		local earlyLeaverReward = RewardPolicy.evaluate(earlyLeaver, true)
		assertions.isTrue(earlyLeaverReward.ok)
		assertions.equal(earlyLeaverReward.value.totalGold, 25)
	end),
	TestHarness.case("fails closed on malformed evidence", function(assertions)
		assertions.isFalse(RewardPolicy.evaluate({}, true).ok)
		assertions.isFalse(RewardPolicy.evaluate(evidence({ placements = -1 }), true).ok)
		assertions.isFalse(RewardPolicy.evaluate(evidence(), "yes").ok)
	end),
})
