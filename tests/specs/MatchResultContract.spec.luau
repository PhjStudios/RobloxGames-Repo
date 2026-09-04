--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local MatchResultContract = require(script.Parent.Parent.ProductionServerMatchRewards.MatchResultContract)

local function valid(): any
	return {
		version = 1,
		resultId = "result:11111111-1111-1111-1111-111111111111",
		matchId = "match:reward-one",
		ticketId = "ticket:travel-one",
		mapId = "map:phase07-graybox",
		difficultyId = "difficulty:local",
		outcome = "Victory",
		createdAt = 100,
		rewardingMatch = true,
		entries = {
			{
				userId = 10,
				authenticatedParticipant = true,
				spectator = false,
				submittedReady = true,
				placements = 1,
				wavesCompleted = 5,
				connectedAtResults = true,
				battleCashEarned = 500,
				battleCashSpent = 300,
			},
		},
	}
end

local function current(modeKind: "Finite" | "Endless"?): any
	local value = valid()
	value.version = MatchResultContract.CURRENT_VERSION
	value.modeKind = modeKind or "Finite"
	value.highestCompletedWave = 5
	value.elapsedSeconds = 640
	value.seed = 1_337
	value.contentVersion = 1
	value.terminationReason = "Victory"
	if value.modeKind == "Endless" then
		value.difficultyId = "difficulty:endless-v1"
		value.outcome = "Defeat"
		value.highestCompletedWave = 110
		value.terminationReason = "PlayerEnded"
		value.entries[1].wavesCompleted = 110
	end
	return value
end

return TestHarness.suite("server-only authoritative match result contract", {
	TestHarness.case("canonicalizes and freezes bounded roster evidence", function(assertions)
		local result = MatchResultContract.validate(valid())
		assertions.isTrue(result.ok)
		assertions.isTrue(table.isfrozen(result.value))
		assertions.isTrue(table.isfrozen(result.value.entries))
		assertions.isTrue(table.isfrozen(result.value.entries[1]))
	end),
	TestHarness.case("rejects unexpected duplicate and spectator participant records", function(assertions)
		local extra = valid()
		extra.secret = "no"
		assertions.isFalse(MatchResultContract.validate(extra).ok)
		local duplicate = valid()
		table.insert(duplicate.entries, table.clone(duplicate.entries[1]))
		assertions.isFalse(MatchResultContract.validate(duplicate).ok)
		local spectator = valid()
		spectator.entries[1].spectator = true
		assertions.isFalse(MatchResultContract.validate(spectator).ok)
	end),
	TestHarness.case("bounds IDs roster and authoritative counters", function(assertions)
		local malformed = valid()
		malformed.resultId = "result:UPPER"
		assertions.isFalse(MatchResultContract.validate(malformed).ok)
		malformed = valid()
		malformed.entries[1].placements = -1
		assertions.isFalse(MatchResultContract.validate(malformed).ok)
		malformed = valid()
		for userId = 11, 15 do
			local copy = table.clone(malformed.entries[1])
			copy.userId = userId
			table.insert(malformed.entries, copy)
		end
		assertions.isFalse(MatchResultContract.validate(malformed).ok)
	end),
	TestHarness.case("reads historical v1 and writes exact frozen v2 run evidence", function(assertions)
		assertions.equal(MatchResultContract.VERSION, 2)
		assertions.equal(MatchResultContract.LEGACY_VERSION, 1)
		assertions.isTrue(MatchResultContract.validate(valid()).ok)
		local endless = MatchResultContract.validate(current("Endless"))
		assertions.isTrue(endless.ok)
		if not endless.ok then
			return
		end
		assertions.isTrue(table.isfrozen(endless.value))
		assertions.equal(endless.value.modeKind, "Endless")
		assertions.equal(endless.value.highestCompletedWave, 110)
		assertions.equal(endless.value.elapsedSeconds, 640)
		assertions.equal(endless.value.seed, 1_337)
		assertions.equal(endless.value.contentVersion, 1)
		assertions.equal(endless.value.terminationReason, "PlayerEnded")
	end),
	TestHarness.case("rejects impossible or incomplete v2 termination evidence", function(assertions)
		local missing = current()
		missing.seed = nil
		assertions.isFalse(MatchResultContract.validate(missing).ok)

		local endlessVictory = current("Endless")
		endlessVictory.outcome = "Victory"
		endlessVictory.terminationReason = "Victory"
		assertions.isFalse(MatchResultContract.validate(endlessVictory).ok)

		local falseVictoryReason = current()
		falseVictoryReason.outcome = "Defeat"
		assertions.isFalse(MatchResultContract.validate(falseVictoryReason).ok)

		local impossibleParticipant = current()
		impossibleParticipant.highestCompletedWave = 4
		assertions.isFalse(MatchResultContract.validate(impossibleParticipant).ok)

		local extra = current()
		extra.untrusted = true
		assertions.isFalse(MatchResultContract.validate(extra).ok)
	end),
})
