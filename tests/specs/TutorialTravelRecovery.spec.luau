--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local TutorialTravelRecovery = require(script.Parent.Parent.ProductionServerLobbyTravel.TutorialTravelRecovery)

local USER_ID = 101
local NOW = 1_700_100_000

local function makeRig(stepValue: number, routeValue: any?): any
	local rig: any = {
		step = stepValue,
		route = routeValue,
		routeUnavailable = false,
		currentChecks = 0,
		currentThroughCheck = math.huge,
		viewCalls = 0,
		routeCalls = 0,
		repairs = {},
		completions = {},
	}
	local activeRoutes = {}
	function activeRoutes:findConfirmed(userId: number, nowValue: number): any
		rig.routeCalls += 1
		if rig.routeUnavailable then
			return Result.err({ code = "STORE_UNAVAILABLE", operation = "find" })
		end
		local route = rig.route
		if route ~= nil and route.userId == userId and route.expiresAt > nowValue then
			return Result.ok(route)
		end
		return Result.ok(nil)
	end
	local tutorial = {}
	function tutorial:getView(_userId: number): any
		rig.viewCalls += 1
		return Result.ok({
			tutorial = {
				tutorialStep = rig.step,
				trackedMatchId = if rig.step == 8 then "match:tutorial-finished" else nil,
			},
		})
	end
	function tutorial:repairTravel(userId: number, eventId: string): any
		table.insert(rig.repairs, { userId = userId, eventId = eventId, step = rig.step })
		local advanced = rig.step >= 4 and rig.step <= 7
		if advanced then
			rig.step = 3
		end
		return Result.ok({ advanced = advanced, tutorial = { tutorialStep = rig.step } })
	end
	function tutorial:observeLobbyReturn(userId: number, matchId: string): any
		table.insert(rig.completions, { userId = userId, matchId = matchId, step = rig.step })
		local advanced = rig.step == 8 and matchId == "match:tutorial-finished"
		if advanced then
			rig.step = 9
		end
		return Result.ok({ advanced = advanced, tutorial = { tutorialStep = rig.step } })
	end
	rig.dependencies = {
		clock = function()
			return NOW
		end,
		activeRoutes = activeRoutes,
		tutorial = tutorial,
		isCurrent = function(userId: number): boolean
			rig.currentChecks += 1
			return userId == USER_ID and rig.currentChecks <= rig.currentThroughCheck
		end,
	}
	return rig
end

return TestHarness.suite("Lobby tutorial travel recovery", {
	TestHarness.case("repairs steps 4 through 7 after a lost route and confirmed absent Return", function(assertions)
		local rig = makeRig(5, nil)
		local recovered = TutorialTravelRecovery.recover(rig.dependencies, USER_ID, "lobby-ready-lost-route", false)
		assertions.isTrue(recovered.ok)
		assertions.isTrue(recovered.value)
		assertions.equal(rig.step, 3)
		assertions.equal(rig.routeCalls, 1)
		assertions.equal(#rig.repairs, 1)
		assertions.equal(rig.repairs[1].userId, USER_ID)
	end),

	TestHarness.case("repairs an expired route but preserves a live resumable route", function(assertions)
		local expired = makeRig(7, { userId = USER_ID, expiresAt = NOW })
		local recovered =
			TutorialTravelRecovery.recover(expired.dependencies, USER_ID, "lobby-ready-expired-route", false)
		assertions.isTrue(recovered.ok)
		assertions.isTrue(recovered.value)
		assertions.equal(expired.step, 3)
		assertions.equal(#expired.repairs, 1)

		local live = makeRig(6, { userId = USER_ID, expiresAt = NOW + 60 })
		local preserved = TutorialTravelRecovery.recover(live.dependencies, USER_ID, "lobby-ready-live-route", false)
		assertions.isTrue(preserved.ok)
		assertions.isFalse(preserved.value)
		assertions.equal(live.step, 6)
		assertions.equal(#live.repairs, 0)
	end),

	TestHarness.case("completes durable step 8 after its return route expires", function(assertions)
		local rig = makeRig(8, { userId = USER_ID, expiresAt = NOW })
		local recovered =
			TutorialTravelRecovery.recover(rig.dependencies, USER_ID, "lobby-ready-finished-route-expired", false)
		assertions.isTrue(recovered.ok)
		assertions.isTrue(recovered.value)
		assertions.equal(rig.step, 9)
		assertions.equal(#rig.repairs, 0)
		assertions.equal(#rig.completions, 1)
		assertions.equal(rig.completions[1].matchId, "match:tutorial-finished")
	end),

	TestHarness.case(
		"does not repair a valid Return or unconfirmed route state or replaced ready worker",
		function(assertions)
			local returned = makeRig(5, nil)
			local skipped =
				TutorialTravelRecovery.recover(returned.dependencies, USER_ID, "lobby-ready-valid-return", true)
			assertions.isTrue(skipped.ok)
			assertions.isFalse(skipped.value)
			assertions.equal(returned.viewCalls, 0)
			assertions.equal(returned.routeCalls, 0)

			local unavailable = makeRig(5, nil)
			unavailable.routeUnavailable = true
			local unconfirmed = TutorialTravelRecovery.recover(
				unavailable.dependencies,
				USER_ID,
				"lobby-ready-store-unavailable",
				false
			)
			assertions.isFalse(unconfirmed.ok)
			assertions.equal(unconfirmed.error.code, "UNAVAILABLE")
			assertions.equal(#unavailable.repairs, 0)

			local replaced = makeRig(4, nil)
			replaced.currentThroughCheck = 1
			local stale =
				TutorialTravelRecovery.recover(replaced.dependencies, USER_ID, "lobby-ready-replaced-worker", false)
			assertions.isTrue(stale.ok)
			assertions.isFalse(stale.value)
			assertions.equal(replaced.currentChecks, 2)
			assertions.equal(#replaced.repairs, 0)
		end
	),
})
