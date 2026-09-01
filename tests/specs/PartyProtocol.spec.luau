--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartyProtocol = require(ReplicatedStorage.Shared.party.PartyProtocol)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local function partySnapshot(): any
	return {
		version = 1,
		party = {
			version = 1,
			partyId = "party:alpha",
			revision = 4,
			leaderUserId = 10,
			privacy = "InviteOnly",
			queueState = "Idle",
			members = {
				{ userId = 10, order = 1, isLeader = true, profileReady = true },
				{ userId = 20, order = 2, isLeader = false, profileReady = false },
			},
			pendingInvitationCount = 1,
		},
		incomingInvitations = {
			{
				invitationId = "invitation:one",
				partyId = "party:beta",
				partyRevision = 2,
				inviterUserId = 30,
				targetUserId = 10,
				createdAt = 100,
				expiresAt = 160,
			},
		},
	}
end

return TestHarness.suite("bounded party protocol", {
	TestHarness.case("canonicalizes ordered client-safe party and invitation state", function(assertions)
		local raw = partySnapshot()
		local result = PartyProtocol.validateViewerSnapshot(raw)
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.notEqual(result.value, raw)
			assertions.isTrue(table.isfrozen(result.value))
			assertions.isTrue(table.isfrozen(result.value.party :: any))
			assertions.equal((result.value.party :: any).leaderUserId, 10)
		end
		assertions.isTrue(PartyProtocol.isPartyId("party:opaque-1"))
		assertions.isFalse(PartyProtocol.isPartyId("queue:opaque-1"))
		assertions.isTrue(PartyProtocol.isInvitationId("invitation:opaque_1"))
		assertions.isFalse(PartyProtocol.isInvitationId("invitation:bad value"))
		assertions.equal(PartyProtocol.MAX_MEMBERS, 4)
		assertions.equal(#PartyProtocol.DISBAND_REASONS, 3)
		assertions.equal(#PartyProtocol.PUBLIC_REASONS, 18)
	end),

	TestHarness.case("rejects ambiguous leaders malformed IDs ordering and private fields", function(assertions)
		local wrongLeader = partySnapshot()
		wrongLeader.party.members[2].isLeader = true
		assertions.isFalse(PartyProtocol.validateViewerSnapshot(wrongLeader).ok)

		local wrongOrder = partySnapshot()
		wrongOrder.party.members[2].order = 1
		assertions.isFalse(PartyProtocol.validateViewerSnapshot(wrongOrder).ok)

		local malformed = partySnapshot()
		malformed.incomingInvitations[1].invitationId = "party:not-an-invite"
		assertions.isFalse(PartyProtocol.validateViewerSnapshot(malformed).ok)

		local private = partySnapshot()
		private.party.platformPartyId = "PRIVATE"
		assertions.isFalse(PartyProtocol.ViewerSnapshotSchema:validate(private).ok)
		assertions.isFalse(PartyProtocol.InviteIntentSchema:validate({
			transactionId = "transaction:invite",
			expectedRevision = 1,
			targetUserId = 20,
			launchData = "PRIVATE",
		}).ok)
	end),

	TestHarness.case("binds client-safe mutation reasons to the matching operation", function(assertions)
		local receipt = {
			transactionId = "transaction:create-reason",
			kind = "Create",
			reason = "PartyCreated",
			changed = true,
			partyRevision = 4,
			snapshot = partySnapshot(),
		}
		assertions.isTrue(PartyProtocol.validateMutationReceipt(receipt).ok)
		receipt.reason = "MemberKicked"
		assertions.isFalse(PartyProtocol.validateMutationReceipt(receipt).ok)
		receipt.reason = "PartyCreated"
		receipt.internalDisbandMetadata = "PRIVATE"
		assertions.isFalse(PartyProtocol.MutationReceiptSchema:validate(receipt).ok)
	end),
})
