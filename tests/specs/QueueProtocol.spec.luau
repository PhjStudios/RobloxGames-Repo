--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QueueProtocol = require(ReplicatedStorage.Shared.queue.QueueProtocol)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local function snapshot(state: string, publicStatus: string?): any
	return {
		version = 1,
		queueId = "queue:alpha",
		revision = 5,
		state = state,
		publicStatus = publicStatus,
		captainUserId = 10,
		configuration = {
			mapId = "map:phase07-graybox",
			difficultyId = "difficulty:local",
			privacy = "Public",
			maxPlayers = 4,
		},
		members = {
			{ userId = 10, order = 1, isCaptain = true, readiness = "Ready" },
			{ userId = 20, order = 2, isCaptain = false, readiness = "Ready" },
		},
		enrollments = {
			{
				sequence = 1,
				kind = "Party",
				leaderUserId = 10,
				partyId = "party:alpha",
				partyRevision = 3,
				userIds = { 10, 20 },
				source = "UI",
			},
		},
		canStart = state == "Open",
	}
end

return TestHarness.suite("bounded queue protocol", {
	TestHarness.case("accepts immutable open and privacy-safe travel states", function(assertions)
		for _, candidate in
			{
				snapshot("Open", nil),
				snapshot("Starting", "TicketPending"),
				snapshot("Traveling", "TeleportInitializing"),
				snapshot("Traveling", "TeleportRetrying"),
				snapshot("Failed", "TicketFailed"),
				snapshot("Failed", "TeleportFailed"),
				snapshot("Failed", "PartialTeleportFailure"),
			}
		do
			local result = QueueProtocol.validateSnapshot(candidate)
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.isTrue(table.isfrozen(result.value))
			end
		end
	end),

	TestHarness.case("rejects roster ambiguity invalid transitions and secret-shaped status", function(assertions)
		local duplicate = snapshot("Open", nil)
		duplicate.members[2].userId = 10
		assertions.isFalse(QueueProtocol.validateSnapshot(duplicate).ok)

		assertions.isFalse(QueueProtocol.validateSnapshot(snapshot("Starting", nil)).ok)
		assertions.isFalse(QueueProtocol.validateSnapshot(snapshot("Traveling", "TicketFailed")).ok)
		assertions.isFalse(QueueProtocol.validateSnapshot(snapshot("Failed", "TeleportRetrying")).ok)

		local secret = snapshot("Traveling", "reserved-code:SECRET")
		assertions.isFalse(QueueProtocol.SnapshotSchema:validate(secret).ok)
		local extra = snapshot("Open", nil)
		extra.reservedServerAccessCode = "SECRET"
		assertions.isFalse(QueueProtocol.SnapshotSchema:validate(extra).ok)
	end),

	TestHarness.case("requires atomic party enrollment shape and bounded configuration intents", function(assertions)
		local invalid = snapshot("Open", nil)
		invalid.enrollments[1].userIds = { 10 }
		assertions.isFalse(QueueProtocol.validateSnapshot(invalid).ok)
		assertions.isFalse(QueueProtocol.ConfigureIntentSchema:validate({
			transactionId = "transaction:configuration",
			expectedRevision = 1,
			queueId = "queue:alpha",
			configuration = {
				mapId = "map:phase07-graybox",
				difficultyId = "difficulty:local",
				privacy = "Public",
				maxPlayers = 5,
			},
		}).ok)
	end),
})
