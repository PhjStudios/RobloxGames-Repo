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

local function coordinator(assertions, rosterProvider, factory, timeout): any
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
		}
	)
	assertions.isTrue(created.ok)
	return created.value
end

return TestHarness.suite("unanimous fresh-ticket rematch coordination", {
	TestHarness.case("creates one fresh rematch only after every active participant approves", function(assertions)
		local calls = 0
		local service = coordinator(assertions, function()
			return { 101, 202 }
		end, function(roster)
			calls += 1
			assertions.equal(roster[1], 101)
			assertions.equal(roster[2], 202)
			return fresh()
		end, nil)
		local begun = service:begin().value
		assertions.equal(begun.state, "Pending")
		local first = service:vote(101, true, begun.revision)
		assertions.isTrue(first.ok)
		assertions.equal(first.value.state, "Pending")

		local duplicate = service:vote(101, true, begun.revision)
		assertions.isTrue(duplicate.ok)
		assertions.equal(duplicate.value.revision, first.value.revision)

		local approved = service:vote(202, true, first.value.revision)
		assertions.isTrue(approved.ok)
		assertions.equal(approved.value.state, "Approved")
		assertions.equal(calls, 1)
		assertions.notEqual(approved.value.rematch.matchId, "match:previous")
		assertions.notEqual(approved.value.rematch.resultId, "result:previous")
		assertions.notEqual(approved.value.rematch.ticketId, "ticket:previous")
		assertions.equal(#approved.value.rematch.resultId, 43)

		local finalDuplicate = service:vote(202, true, first.value.revision)
		assertions.isTrue(finalDuplicate.ok)
		assertions.equal(finalDuplicate.value.state, "Approved")
		assertions.equal(calls, 1)
	end),
	TestHarness.case("decline disconnect and timeout each resolve to no rematch", function(assertions)
		local factoryCalls = 0
		local function make(): any
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
		assertions.equal(first.votes[1].choice, "Approve")

		active = { 101 }
		local changed = service:vote(202, true, first.revision)
		assertions.isFalse(changed.ok)
		assertions.equal(changed.error.code, "ROSTER_CHANGED")
		assertions.equal(service:step(NOW).value.state, "Declined")
	end),
	TestHarness.case("fails closed when the factory reuses IDs or exceeds the result bound", function(assertions)
		local service = coordinator(assertions, function()
			return { 101, 202 }
		end, function(_roster)
			local invalid = fresh()
			invalid.matchId = "match:previous"
			invalid.resultId ..= "x"
			return invalid
		end, nil)
		local begun = service:begin().value
		local first = service:vote(101, true, begun.revision).value
		local failed = service:vote(202, true, first.revision)
		assertions.isFalse(failed.ok)
		assertions.equal(failed.error.code, "FACTORY_FAILED")
		assertions.equal(service:vote(202, true, first.revision).value.state, "Failed")
	end),
})
