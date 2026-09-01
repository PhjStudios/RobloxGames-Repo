--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IsolatedTravelRecordStore = require(script.Parent.Parent.Fixtures.IsolatedTravelRecordStore)
local ReturnRecordService = require(script.Parent.Parent.ProductionServerTravel.ReturnRecordService)
local LobbyReturnCoordinator = require(script.Parent.Parent.ProductionServerLobbyTravel.LobbyReturnCoordinator)
local PendingClaimCoordinator = require(script.Parent.Parent.ProductionServerLobbyTravel.PendingClaimCoordinator)
local Result = require(ReplicatedStorage.Shared.util.Result)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

type Assertions = TestHarness.Assertions

local NOW = 1_700_000_000

local function record(returnId: string): any
	return {
		version = 1,
		revision = 1,
		returnId = returnId,
		matchId = "match:return-test",
		priorLeaderUserId = 20,
		expectedUserIds = { 10, 20 },
		members = {
			{ userId = 10, state = "Expected" },
			{ userId = 20, state = "Expected" },
		},
		createdAt = NOW,
		expiresAt = NOW + 300,
		state = "Active",
	}
end

local function returnRig(
	assertions: Assertions,
	sharedRecords: any?,
	claimId: string?
): (LobbyReturnCoordinator.Service, any, any, { now: number })
	local adapter = if sharedRecords == nil then IsolatedTravelRecordStore.new(NOW) else nil
	local recordsResult = ReturnRecordService.new(adapter)
	if sharedRecords == nil then
		assertions.isTrue(recordsResult.ok)
	end
	local records = sharedRecords or recordsResult.value
	local party = { calls = {} } :: any
	local clock = { now = NOW }
	function party:reconstruct(leader: number, members: { number }): any
		table.insert(self.calls, { leader = leader, members = table.clone(members) })
		return Result.ok({ partyId = "party:return", revision = 1, leaderUserId = leader, members = members })
	end
	local created = LobbyReturnCoordinator.new({
		clock = function(): number
			return clock.now
		end,
		returnRecords = records,
		party = party,
		isPresent = function(_userId: number): boolean
			return true
		end,
		isProfileReady = function(_userId: number): boolean
			return true
		end,
		reconstructionGraceSeconds = 10,
		lobbyClaimId = claimId or "lobby-one",
	})
	assertions.isTrue(created.ok)
	return created.value, records, party, clock
end

return TestHarness.suite("Lobby return and pending claim composition", {
	TestHarness.case(
		"admits authenticated return members then reconstructs the present prior roster",
		function(assertions)
			local coordinator, records, party = returnRig(assertions)
			assertions.isTrue(records:create(record("return:squad"), NOW).ok)
			local routing = TravelProtocol.returnToLobby("return:squad")
			assertions.isTrue(routing.ok)
			local first = coordinator:admitJoinData(10, routing.value)
			local second = coordinator:admitJoinData(20, routing.value)
			assertions.isTrue(first.ok)
			assertions.isTrue(second.ok)
			assertions.equal(second.value.arrivedCount, 2)
			assertions.isTrue(coordinator:reconstruct("return:squad").value)
			assertions.equal(#party.calls, 1)
			assertions.equal(party.calls[1].leader, 20)
			assertions.equal(party.calls[1].members[1], 10)
			assertions.equal(party.calls[1].members[2], 20)
			assertions.isFalse(coordinator:reconstruct("return:squad").value)
		end
	),

	TestHarness.case("waits for staggered arrivals before reconstructing", function(assertions)
		local coordinator, records, party = returnRig(assertions)
		assertions.isTrue(records:create(record("return:staggered"), NOW).ok)
		local routing = TravelProtocol.returnToLobby("return:staggered")
		assertions.isTrue(coordinator:admitJoinData(10, routing.value).ok)
		assertions.isFalse(coordinator:reconstruct("return:staggered").value)
		assertions.equal(#party.calls, 0)
		assertions.isTrue(coordinator:admitJoinData(20, routing.value).ok)
		assertions.isTrue(coordinator:reconstruct("return:staggered").value)
		assertions.equal(#party.calls, 1)
	end),

	TestHarness.case("only the atomic return claim winner may reconstruct", function(assertions)
		local first, records, firstParty = returnRig(assertions, nil, "lobby-first")
		local second, _, secondParty = returnRig(assertions, records, "lobby-second")
		assertions.isTrue(records:create(record("return:claim-race"), NOW).ok)
		local routing = TravelProtocol.returnToLobby("return:claim-race")
		assertions.isTrue(first:admitJoinData(10, routing.value).ok)
		assertions.isTrue(first:admitJoinData(20, routing.value).ok)
		assertions.isTrue(first:reconstruct("return:claim-race").value)
		assertions.isFalse(second:reconstruct("return:claim-race").value)
		assertions.equal(#firstParty.calls, 1)
		assertions.equal(#secondParty.calls, 0)
	end),

	TestHarness.case("fails malformed return data open to a safe solo fallback after grace", function(assertions)
		local coordinator, records, party, clock = returnRig(assertions)
		assertions.isTrue(records:create(record("return:solo"), NOW).ok)
		assertions.isFalse(coordinator:admitJoinData(10, { kind = "Return", returnId = "return:solo" }).ok)
		local routing = TravelProtocol.returnToLobby("return:solo")
		assertions.isTrue(coordinator:admitJoinData(10, routing.value).ok)
		clock.now += 10
		assertions.isFalse(coordinator:reconstruct("return:solo").value)
		assertions.equal(#party.calls, 0)
		assertions.equal(coordinator:getMetrics().soloFallbackCount, 1)
	end),

	TestHarness.case("retries transient reconstruction and bounds expired in-memory tracking", function(assertions)
		local coordinator, records, party, clock = returnRig(assertions)
		assertions.isTrue(records:create(record("return:retry"), NOW).ok)
		local routing = TravelProtocol.returnToLobby("return:retry")
		assertions.isTrue(coordinator:admitJoinData(10, routing.value).ok)
		clock.now += 10
		-- The other member has not arrived, so the periodic retry safely finalizes
		-- this return as a solo fallback when its reconstruction grace expires.
		assertions.equal(coordinator:step().value, 1)
		assertions.equal(#party.calls, 0)
		assertions.equal(coordinator:getMetrics().trackedAdmissionCount, 0)
		assertions.equal(coordinator:getMetrics().trackedFinalizedCount, 1)
		clock.now += 601
		assertions.equal(coordinator:step().value, 0)
		assertions.equal(coordinator:getMetrics().trackedFinalizedCount, 0)
	end),

	TestHarness.case("caps tracked staggered return admissions under load", function(assertions)
		local coordinator, records = returnRig(assertions)
		for index = 1, 129 do
			local returnId = `return:bounded-{index}`
			assertions.isTrue(records:create(record(returnId), NOW).ok)
			local routing = TravelProtocol.returnToLobby(returnId)
			assertions.isTrue(routing.ok)
			assertions.isTrue(coordinator:admitJoinData(10, routing.value).ok)
		end
		assertions.equal(coordinator:getMetrics().trackedAdmissionCount, 128)
	end),

	TestHarness.case("attempts each bounded pending claim without inventing a durable grant", function(assertions)
		local claims = {} :: any
		function claims:claim(_userId: number, resultId: string): any
			local status = if resultId == "result:grant" then "Granted" else "Pending"
			return Result.ok({ resultId = resultId, status = status })
		end
		local pending = {} :: any
		function pending:list(_userId: number): any
			return Result.ok({
				{ resultId = "result:grant", createdAt = NOW },
				{ resultId = "result:retry", createdAt = NOW },
			})
		end
		local published: { any } = {}
		local coordinator = PendingClaimCoordinator.new({
			pendingResults = pending,
			rewardClaims = claims,
			onClaim = function(_userId: number, view: any)
				table.insert(published, view)
			end,
		}).value
		local summary = coordinator:processReady(10)
		assertions.isTrue(summary.ok)
		assertions.equal(summary.value.attempted, 2)
		assertions.equal(summary.value.granted, 1)
		assertions.equal(summary.value.pending, 1)
		assertions.equal(#published, 2)
		assertions.equal(published[2].status, "Pending")
	end),
})
