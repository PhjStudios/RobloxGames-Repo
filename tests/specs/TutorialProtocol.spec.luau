--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialProtocol = require(ReplicatedStorage.Shared.profile.TutorialProtocol)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

return TestHarness.suite("Tutorial protocol", {
	TestHarness.case("accepts bounded revision-bound actions with no claimed step", function(assertions)
		local result = TutorialProtocol.ActionIntentSchema:validate({
			transactionId = "transaction:tutorial-advance",
			expectedRevision = 7,
		})
		assertions.isTrue(result.ok)
		assertions.isFalse(TutorialProtocol.ActionIntentSchema:validate({
			transactionId = "transaction:tutorial-advance",
			expectedRevision = 7,
			tutorialStep = 9,
		}).ok)
	end),

	TestHarness.case("binds Match steps exactly to an authoritative tracked match", function(assertions)
		for step = 5, 8 do
			assertions.isTrue(TutorialProtocol.validateView({
				version = 1,
				firstJoin = false,
				tutorialCompleted = false,
				tutorialStep = step,
				attempt = 2,
				skipped = false,
				trackedMatchId = "match:tutorial-run",
			}).ok)
		end
		assertions.isFalse(TutorialProtocol.validateView({
			version = 1,
			firstJoin = false,
			tutorialCompleted = false,
			tutorialStep = 6,
			attempt = 1,
			skipped = false,
		}).ok)
	end),

	TestHarness.case("requires completion and skip flags to agree with the terminal state", function(assertions)
		assertions.isTrue(TutorialProtocol.validateView({
			version = 1,
			firstJoin = false,
			tutorialCompleted = true,
			tutorialStep = TutorialProtocol.COMPLETE_STEP,
			attempt = 1,
			skipped = true,
		}).ok)
		assertions.isFalse(TutorialProtocol.validateView({
			version = 1,
			firstJoin = false,
			tutorialCompleted = true,
			tutorialStep = 8,
			attempt = 1,
			skipped = false,
			trackedMatchId = "match:tutorial-run",
		}).ok)
	end),
})
