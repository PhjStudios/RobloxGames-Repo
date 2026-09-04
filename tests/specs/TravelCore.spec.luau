--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local IsolatedTravelRecordStore = require(script.Parent.Parent.Fixtures.IsolatedTravelRecordStore)
local MatchTicketContract = require(script.Parent.Parent.ProductionServerTravel.MatchTicketContract)
local TravelRecordStore = require(script.Parent.Parent.ProductionServerTravel.TravelRecordStore)
local ActiveMatchRouteService = require(script.Parent.Parent.ProductionServerTravel.ActiveMatchRouteService)
local ReturnRecordService = require(script.Parent.Parent.ProductionServerTravel.ReturnRecordService)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)

local NOW = 1_700_000_000

local function settings(): any
	return {
		version = 2,
		masterVolume = 1,
		musicVolume = 0.8,
		sfxVolume = 0.9,
		uiVolume = 1,
		cameraShakeIntensity = 0.5,
		damageNumbersEnabled = true,
		enemyHealthBarsEnabled = true,
		otherPlayerEffectsEnabled = true,
		lowDetailEnabled = false,
		towerRangeEnabled = true,
		uiScale = 1,
		reducedMotionEnabled = false,
	}
end

local function member(userId: number): any
	return {
		userId = userId,
		admissionState = "Expected",
		loadout = {
			userId = userId,
			revision = 3,
			slots = {
				{ slot = 1, unitId = `unit:{userId}`, towerId = `tower:{userId}` },
			},
			settings = settings(),
		},
	}
end

local function ticket(): any
	return {
		version = 1,
		revision = 1,
		ticketId = "ticket:travel-core",
		matchId = "match:travel-core",
		resultId = "result:11111111-1111-1111-1111-111111111111",
		expectedUserIds = { 101, 202 },
		captainUserId = 101,
		mapId = "map:phase07-graybox",
		difficultyId = "difficulty:local",
		privacy = "Public",
		lobbyOrigin = { placeId = 1001, jobId = "lobby-job" },
		members = { member(101), member(202) },
		createdAt = NOW,
		expiresAt = NOW + 600,
		state = "Created",
		retryCount = 0,
	}
end

local function ticketStore(assertions): (any, any)
	local adapter = IsolatedTravelRecordStore.new(NOW)
	local created = TravelRecordStore.new(adapter, {
		clock = function()
			return NOW
		end,
	})
	assertions.isTrue(created.ok)
	return created.value, adapter
end

local function returnRecord(): any
	return {
		version = 1,
		revision = 1,
		returnId = "return:travel-core",
		matchId = "match:travel-core",
		priorLeaderUserId = 101,
		expectedUserIds = { 101, 202 },
		members = {
			{ userId = 101, state = "Expected" },
			{ userId = 202, state = "Expected" },
		},
		createdAt = NOW,
		expiresAt = NOW + 600,
		state = "Active",
	}
end

local function route(): any
	return {
		version = 1,
		revision = 1,
		routeId = "route:travel-core",
		userId = 101,
		ticketId = "ticket:travel-core",
		matchId = "match:travel-core",
		destinationPlaceId = 2002,
		reservedServerAccessCode = "server-secret-access-code",
		createdAt = NOW,
		expiresAt = NOW + 2_700,
	}
end

return TestHarness.suite("bounded server-only travel records", {
	TestHarness.case("accepts only exact frozen tickets with bounded result IDs and privacy", function(assertions)
		local public = MatchTicketContract.validate(ticket())
		assertions.isTrue(public.ok)
		assertions.isTrue(table.isfrozen(public.value))
		assertions.equal(public.value.privacy, "Public")

		local partyOnly = ticket()
		partyOnly.privacy = "PartyOnly"
		assertions.isTrue(MatchTicketContract.validate(partyOnly).ok)

		local longResult = ticket()
		longResult.resultId ..= "x"
		assertions.equal(#longResult.resultId, 44)
		assertions.isFalse(MatchTicketContract.validate(longResult).ok)

		local invalidPrivacy = ticket()
		invalidPrivacy.privacy = "Friends"
		assertions.isFalse(MatchTicketContract.validate(invalidPrivacy).ok)

		local secret = ticket()
		secret.reservedServerAccessCode = "must-not-fit-ticket"
		assertions.isFalse(MatchTicketContract.validate(secret).ok)
	end),
	TestHarness.case("allows only opaque routing metadata and rejects secret expansion", function(assertions)
		local match = TravelProtocol.match("ticket:travel-core", "attempt:travel-core")
		assertions.isTrue(match.ok)
		assertions.equal(match.value.kind, "Match")
		assertions.equal(match.value.attemptId, "attempt:travel-core")
		assertions.isNil((match.value :: any).accessCode)

		local expanded = {
			version = 1,
			kind = "Match",
			ticketId = "ticket:travel-core",
			attemptId = "attempt:travel-core",
			roster = { 101 },
		}
		assertions.isFalse(TravelProtocol.validateRoutingData(expanded).ok)
		assertions.isFalse(TravelProtocol.match("ticket:UPPER", "attempt:travel-core").ok)
		assertions.isFalse(TravelProtocol.match("ticket:travel-core", "attempt:UPPER").ok)
		assertions.isTrue(TravelProtocol.rejoin("route:travel-core", "attempt:travel-core").ok)
		assertions.isTrue(TravelProtocol.returnToLobby("return:travel-core").ok)
	end),
	TestHarness.case("atomically claims one destination and admits each expected member once", function(assertions)
		local store = ticketStore(assertions)
		assertions.isTrue(store:create(ticket()).ok)
		assertions.equal(store:create(ticket()).error.code, "CONFLICT")

		local traveling = store:markTeleporting("ticket:travel-core", NOW)
		assertions.isTrue(traveling.ok)
		assertions.isTrue(traveling.value.applied)
		assertions.isFalse(store:markTeleporting("ticket:travel-core", NOW).value.applied)

		local claimed = store:claimDestination("ticket:travel-core", "match-job", NOW + 1)
		assertions.isTrue(claimed.ok)
		assertions.equal(claimed.value.ticket.claimedDestinationJobId, "match-job")
		assertions.isFalse(store:claimDestination("ticket:travel-core", "match-job", NOW + 1).value.applied)
		assertions.equal(
			store:claimDestination("ticket:travel-core", "other-job", NOW + 1).error.code,
			"DESTINATION_CONFLICT"
		)

		local admitted = store:markAdmission("ticket:travel-core", "match-job", 101, "Admitted", NOW + 2)
		assertions.isTrue(admitted.ok)
		assertions.isFalse(
			store:markAdmission("ticket:travel-core", "match-job", 101, "Admitted", NOW + 2).value.applied
		)
		assertions.equal(
			store:markAdmission("ticket:travel-core", "match-job", 999, "Admitted", NOW + 2).error.code,
			"UNEXPECTED_MEMBER"
		)
	end),
	TestHarness.case("expires tickets and preserves injected store failures", function(assertions)
		local store, adapter = ticketStore(assertions)
		assertions.isTrue(store:create(ticket()).ok)
		assertions.equal(store:get("ticket:travel-core", NOW + 600).error.code, "EXPIRED")
		adapter:failNext(1)
		assertions.equal(store:get("ticket:travel-core", NOW).error.code, "STORE_UNAVAILABLE")
	end),
	TestHarness.case("binds pending routes once and fails Lobby lookup open", function(assertions)
		local adapter = IsolatedTravelRecordStore.new(NOW)
		local created = ActiveMatchRouteService.new(adapter)
		assertions.isTrue(created.ok)
		local service = created.value
		assertions.isTrue(service:create(route(), NOW).value.applied)
		assertions.isFalse(service:create(route(), NOW).value.applied)
		assertions.isNil(service:find(101, NOW).value)
		assertions.isNil(service:resolve(101, "route:travel-core", NOW).value)

		local bound = service:bindDestination(101, "match:travel-core", "match-job", NOW + 1)
		assertions.isTrue(bound.ok)
		assertions.isTrue(bound.value.applied)
		assertions.isFalse(service:bindDestination(101, "match:travel-core", "match-job", NOW + 1).value.applied)
		assertions.equal(service:bindDestination(101, "match:travel-core", "other-job", NOW + 1).error.code, "CONFLICT")
		assertions.equal(service:find(101, NOW + 1).value.reservedServerAccessCode, "server-secret-access-code")
		assertions.equal(service:resolve(101, "route:travel-core", NOW).value.destinationJobId, "match-job")
		assertions.isNil(
			(TravelProtocol.rejoin("route:travel-core", "attempt:travel-core").value :: any).reservedServerAccessCode
		)

		adapter:failNext(1)
		local unavailable = service:resolve(101, "route:travel-core", NOW)
		assertions.isTrue(unavailable.ok)
		assertions.isNil(unavailable.value)
		assertions.isNil(service:resolve(101, "route:travel-core", NOW + 2_700).value)
	end),
	TestHarness.case("uses only the final create retry outcome across a cleared-route race", function(assertions)
		local state: any = route()
		local replacement = route()
		replacement.routeId = "route:travel-replacement"
		replacement.ticketId = "ticket:travel-replacement"
		replacement.matchId = "match:travel-replacement"
		local updateCount = 0
		local adapter = {} :: any
		function adapter:getAsync(_key: string): unknown
			return state
		end
		function adapter:updateAsync(_key: string, _expiration: number, transform: (unknown) -> unknown): unknown
			updateCount += 1
			local firstAttempt = transform(state)
			assertions.isNil(firstAttempt)
			state = { cleared = true }
			local clearedAttempt = transform(state)
			assertions.equal((clearedAttempt :: any).routeId, replacement.routeId)
			state = clearedAttempt
			local finalAttempt = transform(state)
			if finalAttempt ~= nil then
				state = finalAttempt
			end
			return state
		end
		function adapter:removeAsync(_key: string): unknown
			state = nil
			return nil
		end

		local service = ActiveMatchRouteService.new(adapter).value
		local created = service:create(replacement, NOW)
		assertions.isTrue(created.ok)
		assertions.isFalse(created.value.applied)
		assertions.equal(updateCount, 1)
		assertions.equal(state.routeId, replacement.routeId)
	end),
	TestHarness.case(
		"uses only the final bind retry outcome across conflict and idempotent races",
		function(assertions)
			local state: any = route()
			state.matchId = "match:other"
			local updateCount = 0
			local adapter = {} :: any
			function adapter:getAsync(_key: string): unknown
				return state
			end
			function adapter:updateAsync(_key: string, _expiration: number, transform: (unknown) -> unknown): unknown
				updateCount += 1
				local firstAttempt = transform(state)
				assertions.isNil(firstAttempt)
				state = route()
				local unboundAttempt = transform(state)
				assertions.equal((unboundAttempt :: any).destinationJobId, "match-job")
				state = unboundAttempt
				local finalAttempt = transform(state)
				if finalAttempt ~= nil then
					state = finalAttempt
				end
				return state
			end
			function adapter:removeAsync(_key: string): unknown
				state = nil
				return nil
			end

			local service = ActiveMatchRouteService.new(adapter).value
			local bound = service:bindDestination(101, "match:travel-core", "match-job", NOW + 1)
			assertions.isTrue(bound.ok)
			assertions.isFalse(bound.value.applied)
			assertions.equal(updateCount, 1)
			assertions.equal(state.destinationJobId, "match-job")
		end
	),
	TestHarness.case("atomically takes a known rematch route without erasing it on store failure", function(assertions)
		local adapter = IsolatedTravelRecordStore.new(NOW)
		local service = ActiveMatchRouteService.new(adapter).value
		assertions.isTrue(service:create(route(), NOW).ok)
		assertions.isTrue(service:bindDestination(101, "match:travel-core", "match-job", NOW + 1).ok)

		adapter:failNext(1)
		assertions.equal(service:takeForMatch(101, "match:travel-core", NOW + 2).error.code, "STORE_UNAVAILABLE")
		assertions.equal(service:find(101, NOW + 2).value.routeId, "route:travel-core")
		assertions.equal(service:takeForMatch(101, "match:other", NOW + 2).error.code, "CONFLICT")
		assertions.equal(service:find(101, NOW + 2).value.matchId, "match:travel-core")

		local taken = service:takeForMatch(101, "match:travel-core", NOW + 2)
		assertions.isTrue(taken.ok)
		assertions.equal(taken.value.reservedServerAccessCode, "server-secret-access-code")
		assertions.isNil(service:find(101, NOW + 2).value)
		assertions.equal(service:takeForMatch(101, "match:travel-core", NOW + 2).error.code, "NOT_FOUND")
	end),
	TestHarness.case("uses only the final callback attempt when a route is replaced during take", function(assertions)
		local previous = route()
		previous.destinationJobId = "match-job"
		local replacement = route()
		replacement.routeId = "route:travel-replacement"
		replacement.ticketId = "ticket:travel-replacement"
		replacement.matchId = "match:travel-replacement"
		replacement.destinationJobId = "replacement-job"
		local state: any = previous
		local updateCount = 0
		local adapter = {} :: any
		function adapter:getAsync(_key: string): unknown
			return state
		end
		function adapter:updateAsync(_key: string, _expiration: number, transform: (unknown) -> unknown): unknown
			updateCount += 1
			local firstAttempt = transform(state)
			assertions.isTrue((firstAttempt :: any).cleared)
			state = replacement
			local finalAttempt = transform(state)
			if finalAttempt ~= nil then
				state = finalAttempt
			end
			return state
		end
		function adapter:removeAsync(_key: string): unknown
			state = nil
			return nil
		end

		local service = ActiveMatchRouteService.new(adapter).value
		local taken = service:takeForMatch(101, previous.matchId, NOW + 2)
		assertions.equal(taken.error.code, "CONFLICT")
		assertions.equal(updateCount, 1)
		assertions.equal(state.routeId, replacement.routeId)
		assertions.equal(service:find(101, NOW + 2).value.matchId, replacement.matchId)
	end),
	TestHarness.case("fails a take closed after the store loses its post-transform response", function(assertions)
		local previous = route()
		previous.destinationJobId = "match-job"
		local state: any = previous
		local updateCount = 0
		local adapter = {} :: any
		function adapter:getAsync(_key: string): unknown
			return state
		end
		function adapter:updateAsync(_key: string, _expiration: number, transform: (unknown) -> unknown): unknown
			updateCount += 1
			state = transform(state)
			if updateCount == 1 then
				error("lost response after transform", 0)
			end
			return state
		end
		function adapter:removeAsync(_key: string): unknown
			state = nil
			return nil
		end

		local service = ActiveMatchRouteService.new(adapter).value
		local taken = service:takeForMatch(101, previous.matchId, NOW + 2)
		assertions.equal(taken.error.code, "STORE_UNAVAILABLE")
		assertions.equal(updateCount, 1)
		assertions.isTrue(state.cleared)
		assertions.isNil(service:find(101, NOW + 2).value)
	end),
	TestHarness.case("uses only the final clear retry outcome after a terminal-clear race", function(assertions)
		local state: any = route()
		local updateCount = 0
		local adapter = {} :: any
		function adapter:getAsync(_key: string): unknown
			return state
		end
		function adapter:updateAsync(_key: string, _expiration: number, transform: (unknown) -> unknown): unknown
			updateCount += 1
			local firstAttempt = transform(state)
			assertions.isTrue((firstAttempt :: any).cleared)
			state = firstAttempt
			local finalAttempt = transform(state)
			if finalAttempt ~= nil then
				state = finalAttempt
			end
			return state
		end
		function adapter:removeAsync(_key: string): unknown
			state = nil
			return nil
		end

		local service = ActiveMatchRouteService.new(adapter).value
		local cleared = service:clear(101, "match:travel-core")
		assertions.isTrue(cleared.ok)
		assertions.isFalse(cleared.value)
		assertions.equal(updateCount, 1)
		assertions.isTrue(state.cleared)
	end),
	TestHarness.case("atomically tombstones cleared routes under published MemoryStore semantics", function(assertions)
		local adapter = IsolatedTravelRecordStore.new(NOW)
		adapter:seed("nil-aborts", { retained = true })
		adapter:updateAsync("nil-aborts", 60, function()
			return nil
		end)
		assertions.isTrue(adapter:read("nil-aborts").retained)

		local service = ActiveMatchRouteService.new(adapter).value
		assertions.isTrue(service:create(route(), NOW).ok)
		assertions.isTrue(service:bindDestination(101, "match:travel-core", "match-job", NOW + 1).ok)
		assertions.isFalse(service:clear(101, "match:other").value)
		assertions.equal(service:find(101, NOW + 2).value.matchId, "match:travel-core")
		assertions.isTrue(service:clear(101, "match:travel-core").value)
		assertions.isNil(service:find(101, NOW + 2).value)

		local replacement = route()
		replacement.routeId = "route:travel-replacement"
		replacement.ticketId = "ticket:travel-replacement"
		replacement.matchId = "match:travel-replacement"
		assertions.isTrue(service:create(replacement, NOW + 2).value.applied)
		assertions.isTrue(service:bindDestination(101, replacement.matchId, "replacement-job", NOW + 3).ok)
		assertions.equal(service:find(101, NOW + 3).value.routeId, replacement.routeId)
	end),
	TestHarness.case("tracks bounded idempotent return admissions", function(assertions)
		local adapter = IsolatedTravelRecordStore.new(NOW)
		local created = ReturnRecordService.new(adapter)
		assertions.isTrue(created.ok)
		local service = created.value
		assertions.isTrue(service:create(returnRecord(), NOW).value.applied)
		assertions.isTrue(service:admit("return:travel-core", 101, NOW + 1).value.applied)
		assertions.isFalse(service:admit("return:travel-core", 101, NOW + 1).value.applied)
		assertions.equal(service:admit("return:travel-core", 999, NOW + 1).error.code, "UNEXPECTED_MEMBER")
		assertions.isTrue(service:markTerminal("return:travel-core", "SAFE_RETURN", NOW + 2).value.applied)
		assertions.isFalse(service:markTerminal("return:travel-core", "SAFE_RETURN", NOW + 2).value.applied)
	end),
})
