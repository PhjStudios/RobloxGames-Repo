--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local MatchAdmissionService = require(script.Parent.Parent.ProductionServerMatchAdmission.MatchAdmissionService)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)

local NOW = 1_700_000_000

local function ticket(): any
	return {
		ticketId = "ticket:admission",
		matchId = "match:admission",
		claimedDestinationJobId = nil,
		claimedDestinationAt = nil,
		members = {
			{ userId = 101, admissionState = "Expected", loadout = { userId = 101, revision = 7 } },
			{ userId = 202, admissionState = "Expected", loadout = { userId = 202, revision = 8 } },
		},
	}
end

local function member(record, userId)
	for _, value in record.members do
		if value.userId == userId then
			return value
		end
	end
	return nil
end

local function store(): (any, any)
	local state = ticket()
	local adapter = {}
	function adapter:get(ticketId, nowValue)
		if ticketId ~= state.ticketId then
			return Result.err({ code = "NOT_FOUND" })
		end
		if nowValue > NOW + 600 then
			return Result.err({ code = "EXPIRED" })
		end
		return Result.ok(state)
	end
	function adapter:claimDestination(ticketId, jobId, nowValue)
		if ticketId ~= state.ticketId then
			return Result.err({ code = "NOT_FOUND" })
		end
		if state.claimedDestinationJobId ~= nil and state.claimedDestinationJobId ~= jobId then
			return Result.err({ code = "DESTINATION_CONFLICT" })
		end
		if state.claimedDestinationJobId == nil then
			state.claimedDestinationJobId = jobId
			state.claimedDestinationAt = nowValue
		end
		return Result.ok({ ticket = state, applied = true })
	end
	function adapter:markAdmission(ticketId, jobId, userId, admissionState, nowValue)
		if ticketId ~= state.ticketId or jobId ~= state.claimedDestinationJobId then
			return Result.err({ code = "DESTINATION_CONFLICT" })
		end
		local expected = member(state, userId)
		if expected == nil then
			return Result.err({ code = "UNEXPECTED_MEMBER" })
		end
		local current = expected.admissionState
		local valid = (current == "Expected" and (admissionState == "Admitted" or admissionState == "LateSpectator"))
			or ((current == "Admitted" or current == "LateSpectator") and admissionState == "Returned")
		if not valid then
			return Result.err({ code = "INVALID_STATE" })
		end
		expected.admissionState = admissionState
		expected.admittedAt = nowValue
		return Result.ok({ ticket = state, applied = true })
	end
	return adapter, state
end

local function routeService(state): any
	local adapter = {}
	function adapter:resolve(userId, routeId, _nowValue)
		if routeId ~= "route:admission" or member(state, userId) == nil then
			return Result.ok(nil)
		end
		return Result.ok({
			routeId = routeId,
			userId = userId,
			ticketId = state.ticketId,
			matchId = state.matchId,
			destinationJobId = state.claimedDestinationJobId,
		})
	end
	return adapter
end

local function player(userId: number): any
	return { userId = userId, live = true }
end

local function service(assertions, storeAdapter, state, profileValidator, rejoinProfileValidator): any
	local created = MatchAdmissionService.new(storeAdapter, routeService(state), {
		getUserId = function(candidate)
			return candidate.userId
		end,
		isLive = function(candidate)
			return candidate.live
		end,
		validateProfile = profileValidator or function(userId, loadout)
			return loadout.userId == userId and loadout.revision > 0
		end,
		validateRejoinProfile = rejoinProfileValidator,
	})
	assertions.isTrue(created.ok)
	return created.value
end

return TestHarness.suite("ticket-authorized match admission and rejoin", {
	TestHarness.case("admits an expected participant once and rebinds only through a valid route", function(assertions)
		local storeAdapter, state = store()
		local serviceValue = service(assertions, storeAdapter, state, nil)
		local original = player(101)
		local admitted = serviceValue:admit(
			original,
			TravelProtocol.match(state.ticketId, "attempt:admission").value,
			"match-job",
			NOW
		)
		assertions.isTrue(admitted.ok)
		assertions.equal(admitted.value.kind, "Participant")
		assertions.equal(admitted.value.loadout.revision, 7)
		assertions.equal(
			serviceValue:admit(
				original,
				TravelProtocol.match(state.ticketId, "attempt:admission").value,
				"match-job",
				NOW
			).error.code,
			"DUPLICATE_CONNECTION"
		)
		assertions.isTrue(serviceValue:disconnect(original).ok)
		assertions.equal(
			serviceValue:admit(
				player(101),
				TravelProtocol.match(state.ticketId, "attempt:admission").value,
				"match-job",
				NOW + 1
			).error.code,
			"ALREADY_CONSUMED"
		)

		local rejoined = serviceValue:admit(
			player(101),
			TravelProtocol.rejoin("route:admission", "attempt:admission").value,
			"match-job",
			NOW + 2
		)
		assertions.isTrue(rejoined.ok)
		assertions.equal(rejoined.value.kind, "Rejoined")
		assertions.equal(serviceValue:getMetrics().participantCount, 1)
	end),
	TestHarness.case(
		"retains authenticated identity after a server-owned profile revision advance",
		function(assertions)
			local storeAdapter, state = store()
			local currentRevision = 7
			local strictCalls, rejoinCalls = 0, 0
			local serviceValue = service(assertions, storeAdapter, state, function(userId, frozen)
				strictCalls += 1
				return userId == 101 and frozen.revision == currentRevision
			end, function(userId, frozen)
				rejoinCalls += 1
				return userId == 101 and currentRevision >= frozen.revision
			end)
			local original = player(101)
			assertions.isTrue(
				serviceValue:admit(
					original,
					TravelProtocol.match(state.ticketId, "attempt:admission").value,
					"match-job",
					NOW
				).ok
			)
			assertions.equal(strictCalls, 1)
			assertions.isTrue(serviceValue:disconnect(original).ok)
			currentRevision = 8 -- authoritative reward/profile mutation after admission
			local rejoined = serviceValue:admit(
				player(101),
				TravelProtocol.rejoin("route:admission", "attempt:admission").value,
				"match-job",
				NOW + 1
			)
			assertions.isTrue(rejoined.ok)
			assertions.equal(rejoined.value.kind, "Rejoined")
			assertions.equal(strictCalls, 1)
			assertions.equal(rejoinCalls, 1)
		end
	),
	TestHarness.case("converts a never-arrived member to a non-rewarding late spectator", function(assertions)
		local storeAdapter, state = store()
		local serviceValue = service(assertions, storeAdapter, state, nil)
		assertions.isTrue(
			serviceValue:admit(
				player(101),
				TravelProtocol.match(state.ticketId, "attempt:admission").value,
				"match-job",
				NOW
			).ok
		)
		local late = serviceValue:admit(
			player(202),
			TravelProtocol.match(state.ticketId, "attempt:admission").value,
			"match-job",
			NOW + 31
		)
		assertions.isTrue(late.ok)
		assertions.equal(late.value.kind, "LateSpectator")
		assertions.equal(member(state, 202).admissionState, "LateSpectator")
		assertions.equal(serviceValue:getMetrics().spectatorCount, 1)
	end),
	TestHarness.case(
		"retains an admitted participant beyond ticket TTL but never promotes a late route",
		function(assertions)
			local storeAdapter, state = store()
			local serviceValue = service(assertions, storeAdapter, state, nil)
			local original = player(101)
			assertions.isTrue(
				serviceValue:admit(
					original,
					TravelProtocol.match(state.ticketId, "attempt:admission").value,
					"match-job",
					NOW
				).ok
			)
			assertions.isTrue(serviceValue:disconnect(original).ok)
			local afterTicketExpiry = serviceValue:admit(
				player(101),
				TravelProtocol.rejoin("route:admission", "attempt:admission").value,
				"match-job",
				NOW + 601
			)
			assertions.isTrue(afterTicketExpiry.ok)
			assertions.equal(afterTicketExpiry.value.kind, "Rejoined")

			local latePlayer = player(202)
			local neverArrived = serviceValue:admit(
				latePlayer,
				TravelProtocol.rejoin("route:admission", "attempt:admission").value,
				"match-job",
				NOW + 602
			)
			assertions.isTrue(neverArrived.ok)
			assertions.equal(neverArrived.value.kind, "LateSpectator")
			assertions.isTrue(serviceValue:disconnect(latePlayer).ok)
			local replay = serviceValue:admit(
				player(202),
				TravelProtocol.rejoin("route:admission", "attempt:admission").value,
				"match-job",
				NOW + 603
			)
			assertions.isFalse(replay.ok)
			assertions.equal(replay.error.code, "STALE_ROUTE")
		end
	),
	TestHarness.case("rejects unexpected users before claiming a destination", function(assertions)
		local storeAdapter, state = store()
		local serviceValue = service(assertions, storeAdapter, state, nil)
		local unexpected = serviceValue:admit(
			player(999),
			TravelProtocol.match(state.ticketId, "attempt:admission").value,
			"match-job",
			NOW
		)
		assertions.isFalse(unexpected.ok)
		assertions.equal(unexpected.error.code, "UNEXPECTED_PLAYER")
		assertions.isNil(state.claimedDestinationJobId)
	end),
	TestHarness.case("rejects wrong jobs malformed data and profile conflicts", function(assertions)
		local storeAdapter, state = store()
		local serviceValue = service(assertions, storeAdapter, state, nil)
		assertions.isTrue(
			serviceValue:admit(
				player(101),
				TravelProtocol.match(state.ticketId, "attempt:admission").value,
				"match-job",
				NOW
			).ok
		)
		assertions.equal(
			serviceValue:admit(
				player(202),
				TravelProtocol.match(state.ticketId, "attempt:admission").value,
				"wrong-job",
				NOW + 1
			).error.code,
			"WRONG_DESTINATION"
		)
		assertions.equal(
			serviceValue:admit(player(202), { ticketId = state.ticketId }, "match-job", NOW).error.code,
			"MALFORMED_JOIN_DATA"
		)

		local otherStore, otherState = store()
		local conflicting = service(assertions, otherStore, otherState, function(_userId, _loadout)
			return false
		end)
		assertions.equal(
			conflicting:admit(
				player(101),
				TravelProtocol.match(otherState.ticketId, "attempt:admission").value,
				"match-job",
				NOW
			).error.code,
			"PROFILE_CONFLICT"
		)
		assertions.isNil(otherState.claimedDestinationJobId)
	end),
	TestHarness.case("reconciles committed destination and admission updates after response loss", function(assertions)
		local storeAdapter, state = store()
		local claimDestination = storeAdapter.claimDestination
		local markAdmission = storeAdapter.markAdmission
		local loseClaimResponse = true
		local loseInitialMarkResponse = true
		function storeAdapter:claimDestination(...)
			local result = claimDestination(self, ...)
			if loseClaimResponse then
				loseClaimResponse = false
				error("simulated destination response loss", 0)
			end
			return result
		end
		function storeAdapter:markAdmission(_ticketId, _jobId, userId, ...)
			local result = markAdmission(self, _ticketId, _jobId, userId, ...)
			if userId == 101 and loseInitialMarkResponse then
				loseInitialMarkResponse = false
				error("simulated admission response loss", 0)
			end
			return result
		end
		local serviceValue = service(assertions, storeAdapter, state, nil)
		local admitted = serviceValue:admit(
			player(101),
			TravelProtocol.match(state.ticketId, "attempt:admission").value,
			"match-job",
			NOW
		)
		assertions.isTrue(admitted.ok)
		assertions.equal(admitted.value.kind, "Participant")
		assertions.equal(state.claimedDestinationJobId, "match-job")
		assertions.equal(member(state, 101).admissionState, "Admitted")
	end),
	TestHarness.case("reconciles a committed late-route state after response loss", function(assertions)
		local storeAdapter, state = store()
		local serviceValue = service(assertions, storeAdapter, state, nil)
		assertions.isTrue(
			serviceValue:admit(
				player(101),
				TravelProtocol.match(state.ticketId, "attempt:admission").value,
				"match-job",
				NOW
			).ok
		)
		local markAdmission = storeAdapter.markAdmission
		function storeAdapter:markAdmission(_ticketId, _jobId, userId, ...)
			local result = markAdmission(self, _ticketId, _jobId, userId, ...)
			if userId == 202 then
				error("simulated late admission response loss", 0)
			end
			return result
		end
		local late = serviceValue:admit(
			player(202),
			TravelProtocol.rejoin("route:admission", "attempt:admission").value,
			"match-job",
			NOW + 31
		)
		assertions.isTrue(late.ok)
		assertions.equal(late.value.kind, "LateSpectator")
		assertions.equal(member(state, 202).admissionState, "LateSpectator")
	end),
	TestHarness.case(
		"tombstones an intentional return locally and retries its durable member state",
		function(assertions)
			local storeAdapter, state = store()
			local serviceValue = service(assertions, storeAdapter, state, nil)
			local original = player(101)
			assertions.isTrue(
				serviceValue:admit(
					original,
					TravelProtocol.match(state.ticketId, "attempt:admission").value,
					"match-job",
					NOW
				).ok
			)
			local markAdmission = storeAdapter.markAdmission
			local failFirstReturn = true
			function storeAdapter:markAdmission(ticketId, jobId, userId, admissionState, nowValue)
				if admissionState == "Returned" and failFirstReturn then
					failFirstReturn = false
					return Result.err({ code = "STORE_UNAVAILABLE" })
				end
				return markAdmission(self, ticketId, jobId, userId, admissionState, nowValue)
			end
			local returned = serviceValue:markReturned(original, NOW + 1)
			assertions.isTrue(returned.ok)
			assertions.isFalse(returned.value)
			local replay = serviceValue:admit(
				player(101),
				TravelProtocol.rejoin("route:admission", "attempt:admission").value,
				"match-job",
				NOW + 2
			)
			assertions.isFalse(replay.ok)
			assertions.equal(replay.error.code, "ALREADY_CONSUMED")
			local retried = serviceValue:retryReturns(NOW + 2)
			assertions.isTrue(retried.ok)
			assertions.equal(retried.value, 1)
			assertions.equal(member(state, 101).admissionState, "Returned")
		end
	),
})
