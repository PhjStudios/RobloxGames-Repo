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
})
