--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local MatchTutorialObserver = require(script.Parent.Parent.ProductionServerMatchTravel.MatchTutorialObserver)

local MATCH_ID = "match:tutorial-result"
local USER_ID = 101

local function view(step: number, trackedMatchId: string?): any
	return table.freeze({
		version = 1,
		firstJoin = false,
		tutorialCompleted = step == 9,
		tutorialStep = step,
		attempt = 1,
		skipped = false,
		trackedMatchId = trackedMatchId,
	})
end

local function observation(step: number, trackedMatchId: string?, advanced: boolean?): any
	return Result.ok(table.freeze({
		advanced = advanced == true,
		revision = 7,
		tutorial = view(step, trackedMatchId),
	}))
end

local function evidence(): any
	return table.freeze({
		matchId = MATCH_ID,
		mapId = "map:backyard-garden-v1",
		difficultyId = "difficulty:easy-v1",
		authenticatedParticipant = true,
		spectator = false,
		durable = true,
	})
end

return TestHarness.suite("Match tutorial durable-result observer", {
	TestHarness.case("accepts the authoritative result transition without repair", function(assertions)
		local repairCalls = 0
		local tutorial = {}
		function tutorial.observeResult(_self, userId, received)
			assertions.equal(userId, USER_ID)
			assertions.equal(received.matchId, MATCH_ID)
			return observation(8, MATCH_ID, true)
		end
		function tutorial.repairTravel()
			repairCalls += 1
			return observation(3, nil, true)
		end

		local result = MatchTutorialObserver.observeDurableResult(tutorial, USER_ID, evidence())
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.equal(result.value.tutorial.tutorialStep, 8)
		end
		assertions.equal(repairCalls, 0)
	end),

	TestHarness.case("retries a failed-run repair until state is safely resumable", function(assertions)
		local repairCalls = 0
		local eventIds = {}
		local repaired = false
		local tutorial = {}
		function tutorial.observeResult()
			return if repaired then observation(3, nil, false) else observation(6, MATCH_ID, false)
		end
		function tutorial.repairTravel(_self, userId, eventId)
			assertions.equal(userId, USER_ID)
			repairCalls += 1
			table.insert(eventIds, eventId)
			if repairCalls == 1 then
				return Result.err({ code = "NOT_READY" })
			end
			repaired = true
			return observation(3, nil, true)
		end

		local first = MatchTutorialObserver.observeDurableResult(tutorial, USER_ID, evidence())
		assertions.isFalse(first.ok)
		local second = MatchTutorialObserver.observeDurableResult(tutorial, USER_ID, evidence())
		assertions.isTrue(second.ok)
		if second.ok then
			assertions.equal(second.value.tutorial.tutorialStep, 3)
		end
		assertions.equal(repairCalls, 2)
		assertions.equal(eventIds[1], eventIds[2])
		assertions.equal(eventIds[1], `durable-result-failure|{MATCH_ID}`)

		-- If success reached persistence but its response was lost, replay sees
		-- the already-repaired state and completes without another transaction.
		local replay = MatchTutorialObserver.observeDurableResult(tutorial, USER_ID, evidence())
		assertions.isTrue(replay.ok)
		assertions.equal(repairCalls, 2)
	end),

	TestHarness.case("does not repair a foreign tracked match", function(assertions)
		local repairCalls = 0
		local tutorial = {}
		function tutorial.observeResult()
			return observation(5, "match:foreign", false)
		end
		function tutorial.repairTravel()
			repairCalls += 1
			return observation(3, nil, true)
		end

		local result = MatchTutorialObserver.observeDurableResult(tutorial, USER_ID, evidence())
		assertions.isFalse(result.ok)
		assertions.equal(repairCalls, 0)
	end),
})
