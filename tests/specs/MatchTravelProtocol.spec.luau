--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Shared = game:GetService("ReplicatedStorage").Shared
local MatchTravelProtocol = require(Shared.match.MatchTravelProtocol)

return TestHarness.suite("client-safe Match return and rematch protocol", {
	TestHarness.case("accepts a bounded unanimous rematch without secure routing state", function(assertions)
		local snapshot = {
			version = 1,
			matchId = "match:ticketed-a",
			revision = 7,
			viewerRole = "Participant",
			returnStatus = "Idle",
			rematch = {
				revision = 3,
				state = "Approved",
				deadline = 500,
				votes = {
					{ userId = 11, choice = "Approve" },
					{ userId = 22, choice = "Approve" },
				},
			},
		}
		local result = MatchTravelProtocol.validateSnapshot(snapshot)
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.isTrue(table.isfrozen(result.value))
			assertions.equal(result.value.rematch.votes[2].userId, 22)
		end
		assertions.isNil((snapshot :: any).ticketId)
		assertions.isNil((snapshot :: any).accessCode)
		assertions.isNil((snapshot :: any).resultId)
	end),

	TestHarness.case("rejects non-unanimous approval duplicate voters and unbounded failures", function(assertions)
		local base = {
			version = 1,
			matchId = "match:ticketed-a",
			revision = 7,
			viewerRole = "Participant",
			returnStatus = "Idle",
			rematch = {
				revision = 3,
				state = "Approved",
				deadline = 500,
				votes = {
					{ userId = 11, choice = "Approve" },
					{ userId = 22, choice = "Pending" },
				},
			},
		}
		assertions.isFalse(MatchTravelProtocol.validateSnapshot(base).ok)
		base.rematch.state = "Pending"
		base.rematch.votes[2].userId = 11
		assertions.isFalse(MatchTravelProtocol.validateSnapshot(base).ok)
		base.rematch = nil
		base.returnStatus = "Failed"
		assertions.isFalse(MatchTravelProtocol.validateSnapshot(base).ok)
		base.publicFailure = "PRIVATE_ACCESS_CODE"
		assertions.isFalse(MatchTravelProtocol.validateSnapshot(base).ok)
	end),

	TestHarness.case("validates exact mutation intents and receipts", function(assertions)
		assertions.isTrue(MatchTravelProtocol.ReturnIntentSchema:validate({
			transactionId = "transaction:return-a",
			matchId = "match:ticketed-a",
			observedRevision = 1,
		}).ok)
		assertions.isTrue(MatchTravelProtocol.RematchVoteIntentSchema:validate({
			transactionId = "transaction:vote-a",
			matchId = "match:ticketed-a",
			observedRevision = 1,
			observedRematchRevision = 2,
			approve = true,
		}).ok)
		assertions.isFalse(MatchTravelProtocol.ReturnIntentSchema:validate({
			transactionId = "transaction:return-a",
			matchId = "match:ticketed-a",
			observedRevision = 1,
			ticketId = "ticket:secret",
		}).ok)
		local receipt = MatchTravelProtocol.validateMutationReceipt({
			transactionId = "transaction:return-a",
			changed = true,
			snapshot = {
				version = 1,
				matchId = "match:ticketed-a",
				revision = 2,
				viewerRole = "Spectator",
				returnStatus = "Pending",
			},
		})
		assertions.isTrue(receipt.ok)
	end),
})
