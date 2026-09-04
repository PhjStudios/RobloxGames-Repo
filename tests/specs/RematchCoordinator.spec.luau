--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RematchCoordinator = require(script.Parent.Parent.ProductionServerMatchAdmission.RematchCoordinator)

local NOW = 1_700_000_000

local function fresh(): any
	return {
		matchId = "match:fresh-rematch",
		resultId = "result:22222222-2222-2222-2222-222222222222",
		ticketId = "ticket:fresh-rematch",
		loadouts = {
			{ userId = 101, revision = 11 },
			{ userId = 202, revision = 12 },
		},
	}
end

local function coordinator(assertions, rosterProvider, factory, timeout, schedulerModeValue): (any, any)
	local schedulerMode = schedulerModeValue or "Queued"
	local scheduleCalls = 0
	local pending = {}
	local lastThread = nil
	local created = RematchCoordinator.new(
		{
			matchId = "match:previous",
			resultId = "result:previous",
			ticketId = "ticket:previous",
		},
		rosterProvider,
		factory,
		{
			clock = function()
				return NOW
			end,
			timeoutSeconds = timeout or 20,
			schedule = function(callback)
				scheduleCalls += 1
				if schedulerMode == "Throw" then
					error("REMATCH_SCHEDULER_FAILED", 0)
				end
				if schedulerMode == "False" then
					return false
				end
				local thread = coroutine.create(callback)
				lastThread = thread
				if schedulerMode == "Inline" then
					local resumed, resumeError = coroutine.resume(thread)
					if not resumed then
						error(resumeError, 0)
					end
				else
					table.insert(pending, thread)
				end
				return thread
			end,
		}
	)
	assertions.isTrue(created.ok)
	return created.value,
		{
			flush = function()
				local queued = pending
				pending = {}
				for _, thread in queued do
					local resumed, resumeError = coroutine.resume(thread)
					if not resumed then
						error(resumeError, 0)
					end
				end
			end,
			resumeLast = function()
				assert(lastThread ~= nil, "expected a scheduled rematch thread")
				local resumed, resumeError = coroutine.resume(lastThread)
				if not resumed then
					error(resumeError, 0)
				end
			end,
			lastStatus = function()
				return if lastThread == nil then nil else coroutine.status(lastThread)
			end,
			scheduleCalls = function()
				return scheduleCalls
			end,
			pendingCount = function()
				return #pending
			end,
		}
end

local function rejectsReusedCanonicalId(field: string, previousId: string)
	return TestHarness.case(`rejects the previous {field} with otherwise valid fresh output`, function(assertions)
		local factoryCalls = 0
		local service, scheduler = coordinator(assertions, function()
			return { 101, 202 }
		end, function(_roster)
			factoryCalls += 1
			local candidate = fresh()
			candidate[field] = previousId
			return candidate
		end, nil)
		local begun = service:begin().value
		local first = service:vote(101, true, begun.revision).value
		assertions.equal(service:vote(202, true, first.revision).value.state, "Starting")
		assertions.equal(factoryCalls, 0)
		scheduler.flush()
		local resolved = service:getSnapshot().value
		assertions.equal(resolved.state, "Failed")
		assertions.isNil(resolved.rematch)
		assertions.equal(factoryCalls, 1)
		assertions.equal(scheduler.scheduleCalls(), 1)
		assertions.isTrue(service:cleanup().value)
	end)
end

return TestHarness.suite("unanimous fresh-ticket rematch coordination", {
	TestHarness.case("defers one fresh rematch beyond the final request coroutine", function(assertions)
		local calls = 0
		local service, scheduler = coordinator(assertions, function()
			return { 101, 202 }
		end, function(roster)
			calls += 1
			assertions.equal(roster[1], 101)
			assertions.equal(roster[2], 202)
			return fresh()
		end, nil)
		local begun = service:begin().value
		local first = service:vote(101, true, begun.revision).value
		local requestResult = nil
		local requestThread = coroutine.create(function()
			requestResult = service:vote(202, true, first.revision)
		end)
		assertions.isTrue(coroutine.resume(requestThread))
		assertions.equal(coroutine.status(requestThread), "dead")
		assertions.isTrue(requestResult.ok)
		assertions.equal(requestResult.value.state, "Starting")
		assertions.equal(calls, 0)
		assertions.equal(scheduler.scheduleCalls(), 1)

		local duplicate = service:vote(202, true, first.revision)
		assertions.isTrue(duplicate.ok)
		assertions.equal(duplicate.value.state, "Starting")
		assertions.equal(scheduler.scheduleCalls(), 1)

		scheduler.flush()
		local approved = service:getSnapshot().value
		assertions.equal(approved.state, "Approved")
		assertions.equal(calls, 1)
		assertions.notEqual(approved.rematch.matchId, "match:previous")
		assertions.notEqual(approved.rematch.resultId, "result:previous")
		assertions.notEqual(approved.rematch.ticketId, "ticket:previous")
		assertions.equal(#approved.rematch.resultId, 43)
	end),
	TestHarness.case("decline disconnect and timeout resolve without a factory", function(assertions)
		local factoryCalls = 0
		local function make(): (any, any)
			return coordinator(assertions, function()
				return { 101, 202 }
			end, function(_roster)
				factoryCalls += 1
				return fresh()
			end, 5)
		end

		local declined = make()
		local declineStart = declined:begin().value
		assertions.equal(declined:vote(101, false, declineStart.revision).value.state, "Declined")

		local disconnected = make()
		disconnected:begin()
		assertions.equal(disconnected:disconnect(202).value.state, "Declined")

		local timedOut = make()
		timedOut:begin()
		assertions.equal(timedOut:step(NOW + 5).value.state, "Declined")
		assertions.equal(factoryCalls, 0)
	end),
	TestHarness.case("rejects roster changes and stale conflicting votes", function(assertions)
		local active = { 101, 202 }
		local service = coordinator(assertions, function()
			return active
		end, function(_roster)
			return fresh()
		end, nil)
		local begun = service:begin().value
		local first = service:vote(101, true, begun.revision).value
		assertions.equal(service:vote(101, false, begun.revision).error.code, "STALE_REVISION")
		active = { 101 }
		local changed = service:vote(202, true, first.revision)
		assertions.isFalse(changed.ok)
		assertions.equal(changed.error.code, "ROSTER_CHANGED")
		assertions.equal(service:getSnapshot().value.state, "Declined")
	end),
	TestHarness.case("fails closed for invalid output and unsafe schedulers", function(assertions)
		local invalidService, invalidScheduler = coordinator(assertions, function()
			return { 101, 202 }
		end, function(_roster)
			local invalid = fresh()
			invalid.matchId = "match:previous"
			invalid.resultId ..= "x"
			return invalid
		end, nil)
		local invalidBegin = invalidService:begin().value
		local invalidFirst = invalidService:vote(101, true, invalidBegin.revision).value
		assertions.equal(invalidService:vote(202, true, invalidFirst.revision).value.state, "Starting")
		invalidScheduler.flush()
		assertions.equal(invalidService:getSnapshot().value.state, "Failed")

		for _, schedulerMode in { "Inline", "False", "Throw" } do
			local factoryCalls = 0
			local service, scheduler = coordinator(assertions, function()
				return { 101, 202 }
			end, function(_roster)
				factoryCalls += 1
				return fresh()
			end, nil, schedulerMode)
			local begun = service:begin().value
			local first = service:vote(101, true, begun.revision).value
			local failed = service:vote(202, true, first.revision)
			assertions.isFalse(failed.ok)
			assertions.equal(failed.error.code, "FACTORY_FAILED")
			assertions.equal(service:getSnapshot().value.state, "Failed")
			assertions.equal(factoryCalls, 0)
			assertions.equal(scheduler.scheduleCalls(), 1)
		end
	end),
	rejectsReusedCanonicalId("ticketId", "ticket:previous"),
	rejectsReusedCanonicalId("matchId", "match:previous"),
	rejectsReusedCanonicalId("resultId", "result:previous"),
	TestHarness.case("cancels queued work on disconnect or cleanup", function(assertions)
		local factoryCalls = 0
		local function make(): (any, any)
			return coordinator(assertions, function()
				return { 101, 202 }
			end, function(_roster)
				factoryCalls += 1
				return fresh()
			end, nil)
		end

		local disconnected, disconnectScheduler = make()
		local disconnectBegin = disconnected:begin().value
		local disconnectFirst = disconnected:vote(101, true, disconnectBegin.revision).value
		assertions.equal(disconnected:vote(202, true, disconnectFirst.revision).value.state, "Starting")
		assertions.equal(disconnected:disconnect(202).value.state, "Declined")
		disconnectScheduler.flush()

		local cleaned, cleanupScheduler = make()
		local cleanupBegin = cleaned:begin().value
		local cleanupFirst = cleaned:vote(101, true, cleanupBegin.revision).value
		assertions.equal(cleaned:vote(202, true, cleanupFirst.revision).value.state, "Starting")
		assertions.isTrue(cleaned:cleanup().value)
		cleanupScheduler.flush()
		assertions.equal(factoryCalls, 0)
	end),
	TestHarness.case("never cancels a factory that has started yielding", function(assertions)
		local factoryCalls = 0
		local service, scheduler = coordinator(assertions, function()
			return { 101, 202 }
		end, function(_roster)
			factoryCalls += 1
			coroutine.yield()
			return fresh()
		end, nil)
		local begun = service:begin().value
		local first = service:vote(101, true, begun.revision).value
		assertions.equal(service:vote(202, true, first.revision).value.state, "Starting")
		scheduler.flush()
		assertions.equal(scheduler.lastStatus(), "suspended")
		assertions.equal(service:getSnapshot().value.state, "Starting")
		assertions.isFalse(service:cancelFactory().ok)
		assertions.isFalse(service:cleanup().ok)
		assertions.equal(service:getSnapshot().value.state, "Starting")
		scheduler.resumeLast()
		assertions.equal(scheduler.lastStatus(), "dead")
		assertions.equal(factoryCalls, 1)
		assertions.equal(service:getSnapshot().value.state, "Approved")
		assertions.isTrue(service:cleanup().value)
	end),
})
