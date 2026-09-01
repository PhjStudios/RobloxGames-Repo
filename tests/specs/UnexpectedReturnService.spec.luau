--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Result = require(game:GetService("ReplicatedStorage").Shared.util.Result)
local UnexpectedReturnService = require(script.Parent.Parent.ProductionServerMatchTravel.UnexpectedReturnService)

local function rig(
	assertions: TestHarness.Assertions,
	teleportFails: boolean?,
	loading: (boolean | string)?,
	rollbackFailures: number?,
	commitFailures: number?,
	prepareFails: boolean?,
	scheduleFails: boolean?
): any
	local nowValue = 10
	local player = { userId = 101, live = true }
	local prepared, rolledBack, committed = 0, 0, 0
	local teleportCalls = {}
	local rejectedReasons = {}
	local initFailed: ((any, string, any) -> ())? = nil
	local playerRemoving: ((any) -> ())? = nil
	local returnCount = 0
	local transfer = {}
	function transfer:prepare(userIds)
		prepared += 1
		if prepareFails then
			return Result.err({ code = "PREPARE_FAILED" })
		end
		return Result.ok({ handle = {}, orderedUserIds = userIds })
	end
	function transfer:rollback(_handle)
		rolledBack += 1
		if rolledBack <= (rollbackFailures or 0) then
			return Result.err({ code = "ROLLBACK_FAILED" })
		end
		return Result.ok(true)
	end
	function transfer:commit(_handle)
		committed += 1
		if committed <= (commitFailures or 0) then
			return Result.err({ code = "COMMIT_FAILED" })
		end
		return Result.ok(true)
	end
	local teleport = {}
	function teleport:teleportPublic(placeId, players, routing)
		table.insert(teleportCalls, { placeId = placeId, players = players, routing = routing })
		return if teleportFails then Result.err({ code = "TELEPORT_FAILED" }) else Result.ok(true)
	end
	function teleport:connectInitFailed(listener)
		initFailed = listener
		return { Disconnect = function() end }
	end
	local created = UnexpectedReturnService.new({
		ownershipTransfer = transfer,
		teleport = teleport,
		lobbyPlaceId = 100,
		getUserId = function(candidate)
			return candidate.userId
		end,
		isLive = function(candidate)
			return candidate.live
		end,
		getProfileState = function(_userId)
			return if type(loading) == "string" then loading else if loading then "Loading" else "Ready"
		end,
		rejectPlayer = function(candidate, publicReason)
			assertions.equal(candidate, player)
			table.insert(rejectedReasons, publicReason)
			candidate.live = false
		end,
		makeReturnId = function()
			returnCount += 1
			return `return:unexpected-test-{returnCount}`
		end,
		schedule = function(callback)
			if scheduleFails then
				return false
			end
			callback()
			return true
		end,
		connectPlayerRemoving = function(callback)
			playerRemoving = callback
			return { Disconnect = function() end }
		end,
		wait = function(seconds)
			nowValue += seconds
		end,
		monotonic = function()
			return nowValue
		end,
		timeoutSeconds = 1,
	})
	assertions.isTrue(created.ok)
	return {
		service = created.value,
		player = player,
		teleportCalls = teleportCalls,
		rejectedReasons = rejectedReasons,
		counts = function()
			return prepared, rolledBack, committed
		end,
		emitInitFailure = function(routingData)
			local routing = routingData
			if routing == nil then
				routing = teleportCalls[#teleportCalls].routing
			end
			(initFailed :: any)(player, "Terminal", { placeId = 100, routingData = routing })
		end,
		fireRemoving = function()
			player.live = false
			(playerRemoving :: any)(player)
		end,
		advance = function(seconds)
			nowValue += seconds
		end,
	}
end

return TestHarness.suite("safe unexpected Match return", {
	TestHarness.case("flushes and releases before opaque public return then commits", function(assertions)
		local context = rig(assertions)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 1)
		assertions.equal(rolledBack, 0)
		assertions.equal(committed, 0)
		assertions.equal(#context.rejectedReasons, 0)
		assertions.equal(#context.teleportCalls, 1)
		assertions.equal(context.teleportCalls[1].routing.kind, "Return")
		assertions.isNil((context.teleportCalls[1].routing :: any).accessCode)
		assertions.isNil((context.teleportCalls[1].routing :: any).ticketId)
		context.fireRemoving()
		prepared, rolledBack, committed = context.counts()
		assertions.equal(committed, 1)
	end),
	TestHarness.case("reacquires ownership after a late public teleport initialization failure", function(assertions)
		local context = rig(assertions)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		context.emitInitFailure()
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 1)
		assertions.equal(rolledBack, 1)
		assertions.equal(committed, 0)
		assertions.equal(#context.rejectedReasons, 1)
		context.emitInitFailure()
		assertions.equal(#context.rejectedReasons, 1)
	end),
	TestHarness.case("rolls profile ownership back when public travel fails", function(assertions)
		local context = rig(assertions, true)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 1)
		assertions.equal(rolledBack, 1)
		assertions.equal(committed, 0)
		assertions.equal(#context.rejectedReasons, 1)
	end),
	TestHarness.case("retains ownership context across a transient rollback failure", function(assertions)
		local context = rig(assertions, true, false, 1)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 1)
		assertions.equal(rolledBack, 2)
		assertions.equal(committed, 0)
	end),
	TestHarness.case("settles retained rollback context after coordinator recovery", function(assertions)
		local context = rig(assertions, true, false, 3)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 1)
		assertions.equal(rolledBack, 3)
		assertions.equal(committed, 0)
		assertions.equal(context.service:step(), 1)
		assertions.equal(#context.rejectedReasons, 1)
		assertions.equal(context.service:returnPlayer(context.player).error.code, "INVALID_PLAYER")
	end),
	TestHarness.case("times out an initialized unexpected return without an engine signal", function(assertions)
		local context = rig(assertions)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		context.advance(1)
		assertions.equal(context.service:step(), 1)
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 1)
		assertions.equal(rolledBack, 1)
		assertions.equal(committed, 0)
		assertions.equal(#context.rejectedReasons, 1)
	end),
	TestHarness.case("retains a departed return until transfer commit succeeds", function(assertions)
		local context = rig(assertions, false, false, 0, 1)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		context.fireRemoving()
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 1)
		assertions.equal(rolledBack, 0)
		assertions.equal(committed, 1)
		assertions.equal(context.service:step(), 1)
		local _, _, committedAfterRetry = context.counts()
		assertions.equal(committedAfterRetry, 2)
	end),
	TestHarness.case("times out without releasing an unready profile", function(assertions)
		local context = rig(assertions, false, true)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 0)
		assertions.equal(rolledBack, 0)
		assertions.equal(committed, 0)
		assertions.equal(#context.teleportCalls, 0)
		assertions.equal(#context.rejectedReasons, 1)
		assertions.isTrue(string.find(context.rejectedReasons[1], "authorized", 1, true) ~= nil)
	end),
	TestHarness.case(
		"rejects a failed profile and a failed ownership prepare without releasing either",
		function(assertions)
			local failed = rig(assertions, false, "Failed")
			assertions.isTrue(failed.service:returnPlayer(failed.player).ok)
			local prepared, rolledBack, committed = failed.counts()
			assertions.equal(prepared, 0)
			assertions.equal(rolledBack, 0)
			assertions.equal(committed, 0)
			assertions.equal(#failed.rejectedReasons, 1)

			local prepareFailed = rig(assertions, false, false, 0, 0, true)
			assertions.isTrue(prepareFailed.service:returnPlayer(prepareFailed.player).ok)
			prepared, rolledBack, committed = prepareFailed.counts()
			assertions.equal(prepared, 1)
			assertions.equal(rolledBack, 0)
			assertions.equal(committed, 0)
			assertions.equal(#prepareFailed.rejectedReasons, 1)
		end
	),
	TestHarness.case("rejects once when return scheduling cannot start", function(assertions)
		local context = rig(assertions, false, false, 0, 0, false, true)
		assertions.equal(context.service:returnPlayer(context.player).error.code, "BUSY")
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 0)
		assertions.equal(rolledBack, 0)
		assertions.equal(committed, 0)
		assertions.equal(#context.rejectedReasons, 1)
	end),
})
