--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RematchRecoveryScope = require(script.Parent.Parent.ProductionServerMatchTravel.RematchRecoveryScope)

type Scheduled = {
	callback: () -> (),
	cancelled: boolean,
}

return TestHarness.suite("rematch recovery callback ownership", {
	TestHarness.case("keeps a yielding scheduled recovery busy until it returns", function(assertions)
		local scheduled: { Scheduled } = {}
		local settled = 0
		local scope = RematchRecoveryScope.new(function(_delaySeconds, callback)
			local handle = { callback = callback, cancelled = false }
			table.insert(scheduled, handle)
			return handle
		end, function() end)
		local context = {}
		assertions.isTrue(scope:register("ticket:yielding-scheduled", context))
		assertions.isTrue(scope:schedule("ticket:yielding-scheduled", 0, function(recovered)
			assertions.equal(recovered, context)
			coroutine.yield()
		end))

		local callbackThread = coroutine.create(scheduled[1].callback)
		assertions.isTrue(coroutine.resume(callbackThread))
		assertions.equal(coroutine.status(callbackThread), "suspended")
		assertions.isTrue(scope:isBusy())
		assertions.equal(scope:getMetrics().scheduledCount, 0)
		assertions.equal(scope:getMetrics().runningCount, 1)
		assertions.isFalse(scope:cleanup(function()
			settled += 1
		end))
		assertions.isTrue(scope:getMetrics().closing)
		assertions.equal(settled, 0)

		assertions.isTrue(coroutine.resume(callbackThread))
		assertions.equal(coroutine.status(callbackThread), "dead")
		assertions.isFalse(scope:isBusy())
		assertions.isTrue(scope:cleanup(function()
			settled += 1
		end))
		assertions.equal(settled, 1)
	end),
	TestHarness.case("keeps a yielding direct recovery under the same ownership boundary", function(assertions)
		local scope = RematchRecoveryScope.new(function()
			return {}
		end, function() end)
		local context = {}
		assertions.isTrue(scope:register("ticket:yielding-direct", context))
		local runThread = coroutine.create(function()
			assertions.isTrue(scope:run("ticket:yielding-direct", function(recovered)
				assertions.equal(recovered, context)
				coroutine.yield()
			end))
		end)
		assertions.isTrue(coroutine.resume(runThread))
		assertions.equal(coroutine.status(runThread), "suspended")
		assertions.isTrue(scope:isBusy())
		assertions.isFalse(scope:cleanup())
		assertions.isTrue(coroutine.resume(runThread))
		assertions.equal(coroutine.status(runThread), "dead")
		assertions.isTrue(scope:cleanup())
	end),
	TestHarness.case("cleanup clears contexts and leaves even an uncancelled queued retry inert", function(assertions)
		local scheduled: { Scheduled } = {}
		local cancelCalls = 0
		local scope = RematchRecoveryScope.new(function(_delaySeconds, callback)
			local handle = { callback = callback, cancelled = false }
			table.insert(scheduled, handle)
			return handle
		end, function(_handle)
			cancelCalls += 1
			-- Simulate a scheduler whose cancellation throws after the callback was
			-- already queued. The scope generation guard must still make it inert.
			error("cancel unavailable")
		end)
		local context = { settled = false }
		local retryCalls = 0
		assertions.isTrue(scope:register("ticket:cleanup-race", context))
		assertions.isTrue(scope:schedule("ticket:cleanup-race", 5, function(recovered)
			retryCalls += 1
			assertions.equal(recovered, context)
		end))
		assertions.equal(scope:getMetrics().contextCount, 1)
		assertions.equal(scope:getMetrics().scheduledCount, 1)

		assertions.isTrue(scope:cleanup(function(recovered)
			(recovered :: any).settled = true
		end))
		assertions.isTrue(context.settled)
		assertions.equal(cancelCalls, 1)
		assertions.isTrue(scope:getMetrics().cleaned)
		assertions.equal(scope:getMetrics().contextCount, 0)
		assertions.equal(scope:getMetrics().scheduledCount, 0)

		-- Deliberately execute the captured callback even though cleanup tried to
		-- cancel it. No profile, pending-result, route, or ledger retry may run.
		scheduled[1].callback()
		assertions.equal(retryCalls, 0)
		assertions.isNil(scope:get("ticket:cleanup-race"))
		assertions.isFalse(scope:register("ticket:after-cleanup", {}))
		assertions.isFalse(scope:schedule("ticket:cleanup-race", 5, function()
			retryCalls += 1
		end))
		assertions.isFalse(scope:cleanup())
	end),
	TestHarness.case("removing a settled context cancels only its owned retry", function(assertions)
		local scheduled: { Scheduled } = {}
		local cancelCalls = 0
		local scope = RematchRecoveryScope.new(function(_delaySeconds, callback)
			local handle = { callback = callback, cancelled = false }
			table.insert(scheduled, handle)
			return handle
		end, function(handleValue)
			cancelCalls += 1
			(handleValue :: Scheduled).cancelled = true
		end)
		local first = {}
		local second = {}
		local retryCalls = 0
		assertions.isTrue(scope:register("ticket:first", first))
		assertions.isTrue(scope:register("ticket:second", second))
		assertions.isTrue(scope:schedule("ticket:first", 0.5, function()
			retryCalls += 1
		end))
		assertions.isTrue(scope:schedule("ticket:second", 0.5, function()
			retryCalls += 1
		end))
		assertions.equal(scope:remove("ticket:first"), first)
		assertions.equal(cancelCalls, 1)
		assertions.isTrue(scheduled[1].cancelled)
		scheduled[1].callback()
		assertions.equal(retryCalls, 0)
		assertions.equal(scope:getMetrics().contextCount, 1)
		assertions.equal(scope:getMetrics().scheduledCount, 1)
		assertions.isTrue(scope:cleanup())
		assertions.equal(cancelCalls, 2)
	end),
})
