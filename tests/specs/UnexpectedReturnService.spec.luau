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
	scheduleFails: boolean?,
	prepareYields: boolean?,
	queueSchedule: boolean?,
	rejectYields: boolean?,
	commitYields: boolean?,
	scheduleYields: boolean?
): any
	local nowValue = 10
	local player = { userId = 101, live = true }
	local prepared, rolledBack, committed = 0, 0, 0
	local teleportCalls = {}
	local rejectedReasons = {}
	local initFailed: ((any, string, any) -> ())? = nil
	local playerRemoving: ((any) -> ())? = nil
	local returnCount = 0
	local scheduledThreads = {}
	local yieldNextReject = rejectYields == true
	local yieldNextCommit = commitYields == true
	local yieldNextSchedule = scheduleYields == true
	local transfer = {}
	function transfer:prepare(userIds)
		prepared += 1
		if prepareYields then
			coroutine.yield()
		end
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
		if yieldNextCommit then
			yieldNextCommit = false
			coroutine.yield()
		end
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
			if yieldNextReject then
				yieldNextReject = false
				coroutine.yield()
			end
			table.insert(rejectedReasons, publicReason)
			candidate.live = false
		end,
		makeReturnId = function()
			returnCount += 1
			return `return:unexpected-test-{returnCount}`
		end,
		schedule = function(callback)
			if yieldNextSchedule then
				yieldNextSchedule = false
				coroutine.yield()
			end
			if scheduleFails then
				return false
			end
			if queueSchedule then
				local thread = coroutine.create(callback)
				table.insert(scheduledThreads, thread)
				return thread
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
		resumeScheduled = function(index)
			local thread = scheduledThreads[index]
			assert(thread ~= nil, "expected scheduled thread")
			local resumed, resumeError = coroutine.resume(thread)
			if not resumed then
				error(resumeError, 0)
			end
			return coroutine.status(thread)
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
	TestHarness.case("joins a yielding init-failure rejection before cleanup", function(assertions)
		local context = rig(assertions, false, false, 0, 0, false, false, false, false, true)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		local callbackThread = coroutine.create(context.emitInitFailure)
		assertions.isTrue(coroutine.resume(callbackThread))
		assertions.equal(coroutine.status(callbackThread), "suspended")
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 1)
		assertions.equal(rolledBack, 1)
		assertions.equal(committed, 0)
		assertions.equal(#context.rejectedReasons, 0)
		assertions.isTrue(context.service:isBusy())
		local blocked = context.service:cleanup()
		assertions.isFalse(blocked.ok)
		assertions.equal(blocked.error.code, "BUSY")
		context.emitInitFailure()
		_, rolledBack = context.counts()
		assertions.equal(rolledBack, 1)

		assertions.isTrue(coroutine.resume(callbackThread))
		assertions.equal(coroutine.status(callbackThread), "dead")
		assertions.equal(#context.rejectedReasons, 1)
		assertions.isFalse(context.service:isBusy())
		assertions.isTrue(context.service:cleanup().ok)
	end),
	TestHarness.case("joins a yielding removal commit before cleanup", function(assertions)
		local context = rig(assertions, false, false, 0, 0, false, false, false, false, false, true)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		local callbackThread = coroutine.create(context.fireRemoving)
		assertions.isTrue(coroutine.resume(callbackThread))
		assertions.equal(coroutine.status(callbackThread), "suspended")
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 1)
		assertions.equal(rolledBack, 0)
		assertions.equal(committed, 1)
		assertions.isTrue(context.service:isBusy())
		local blocked = context.service:cleanup()
		assertions.isFalse(blocked.ok)
		assertions.equal(blocked.error.code, "BUSY")

		assertions.isTrue(coroutine.resume(callbackThread))
		assertions.equal(coroutine.status(callbackThread), "dead")
		assertions.isFalse(context.service:isBusy())
		assertions.isTrue(context.service:cleanup().ok)
		_, _, committed = context.counts()
		assertions.equal(committed, 1)
	end),
	TestHarness.case("joins yielding scheduler failure and rejection tails before cleanup", function(assertions)
		local context = rig(assertions, false, false, 0, 0, false, true, false, false, true, false, true)
		local returnResult = nil
		local requestThread = coroutine.create(function()
			returnResult = context.service:returnPlayer(context.player)
		end)
		assertions.isTrue(coroutine.resume(requestThread))
		assertions.equal(coroutine.status(requestThread), "suspended")
		assertions.isTrue(context.service:isBusy())
		assertions.equal(context.service:cleanup().error.code, "BUSY")
		assertions.equal(#context.rejectedReasons, 0)

		assertions.isTrue(coroutine.resume(requestThread))
		assertions.equal(coroutine.status(requestThread), "suspended")
		assertions.isTrue(context.service:isBusy())
		assertions.equal(context.service:cleanup().error.code, "BUSY")
		assertions.equal(#context.rejectedReasons, 0)

		assertions.isTrue(coroutine.resume(requestThread))
		assertions.equal(coroutine.status(requestThread), "dead")
		assertions.equal(returnResult.error.code, "BUSY")
		assertions.equal(#context.rejectedReasons, 1)
		assertions.isFalse(context.service:isBusy())
		assertions.isTrue(context.service:cleanup().ok)
	end),
	TestHarness.case(
		"joins a worker yielding in ownership prepare before cleanup settles dependencies",
		function(assertions)
			local context = rig(assertions, false, false, 0, 0, false, false, true, true)
			assertions.isTrue(context.service:returnPlayer(context.player).ok)
			assertions.isTrue(context.service:isBusy())
			assertions.equal(context.resumeScheduled(1), "suspended")
			local prepared, rolledBack, committed = context.counts()
			assertions.equal(prepared, 1)
			assertions.equal(rolledBack, 0)
			assertions.equal(committed, 0)

			local blocked = context.service:cleanup()
			assertions.isFalse(blocked.ok)
			assertions.equal(blocked.error.code, "BUSY")
			assertions.equal(#context.teleportCalls, 0)
			assertions.equal(context.resumeScheduled(1), "dead")
			assertions.isFalse(context.service:isBusy())
			assertions.isTrue(context.service:cleanup().ok)
			prepared, rolledBack, committed = context.counts()
			assertions.equal(prepared, 1)
			assertions.equal(rolledBack, 1)
			assertions.equal(committed, 0)
			assertions.equal(#context.teleportCalls, 0)
		end
	),
	TestHarness.case("cancels queued return work before it can release ownership", function(assertions)
		local context = rig(assertions, false, false, 0, 0, false, false, false, true)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		assertions.isTrue(context.service:isBusy())
		assertions.isTrue(context.service:cleanup().ok)
		assertions.equal(context.resumeScheduled(1), "dead")
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 0)
		assertions.equal(rolledBack, 0)
		assertions.equal(committed, 0)
		assertions.equal(#context.teleportCalls, 0)
	end),
	TestHarness.case("retains cleanup ownership until a pending transfer settles", function(assertions)
		local context = rig(assertions, false, false, 1)
		assertions.isTrue(context.service:returnPlayer(context.player).ok)
		local first = context.service:cleanup()
		assertions.isFalse(first.ok)
		assertions.equal(first.error.code, "BUSY")
		local prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 1)
		assertions.equal(rolledBack, 1)
		assertions.equal(committed, 0)

		assertions.isTrue(context.service:cleanup().ok)
		prepared, rolledBack, committed = context.counts()
		assertions.equal(prepared, 1)
		assertions.equal(rolledBack, 2)
		assertions.equal(committed, 0)
	end),
})
