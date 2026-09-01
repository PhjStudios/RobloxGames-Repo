--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local LobbyReconnectService = require(ServerStorage.AutomatedTests.ProductionServerLobbyTravel.LobbyReconnectService)
local Result = require(ReplicatedStorage.Shared.util.Result)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

type Assertions = TestHarness.Assertions

type Rig = {
	service: LobbyReconnectService.Service,
	route: any?,
	teleportSucceeds: boolean,
	prepareSucceeds: boolean,
	transferState: string,
	rollbackFailuresRemaining: number,
	rollbackAttempts: number,
	commitFailuresRemaining: number,
	commitAttempts: number,
	teleports: { any },
	emitInitFailure: (any?) -> (),
	clock: { now: number },
}

local function makeRig(assertions: Assertions, developmentSimulation: boolean?): Rig
	local rig = {
		service = nil :: any,
		route = {
			routeId = "route:rejoin-one",
			userId = 10,
			matchId = "match:one",
			destinationPlaceId = 222,
			reservedServerAccessCode = "SERVER-ONLY-CODE",
			expiresAt = 2_000,
		},
		teleportSucceeds = true,
		prepareSucceeds = true,
		transferState = "Owned",
		rollbackFailuresRemaining = 0,
		rollbackAttempts = 0,
		commitFailuresRemaining = 0,
		commitAttempts = 0,
		teleports = {},
		clock = { now = 1_000 },
	} :: Rig
	local routes: any = {}
	local player = { UserId = 10 }
	local initFailed: ((any, string, any) -> ())? = nil
	local attemptCount = 0
	function routes:find(_userId: number, _now: number): any
		return Result.ok(rig.route)
	end
	local transfer: any = {}
	function transfer:prepare(userIds: { number }): any
		assertions.equal(userIds[1], 10)
		if not rig.prepareSucceeds then
			return Result.err({ code = "PROFILE_NOT_READY" })
		end
		rig.transferState = "Released"
		return Result.ok({ handle = "handle:rejoin" })
	end
	function transfer:rollback(_handle: unknown): any
		rig.rollbackAttempts += 1
		if rig.rollbackFailuresRemaining > 0 then
			rig.rollbackFailuresRemaining -= 1
			return Result.err({ code = "INJECTED" })
		end
		rig.transferState = "RolledBack"
		return Result.ok(true)
	end
	function transfer:commit(_handle: unknown): any
		rig.commitAttempts += 1
		if rig.commitFailuresRemaining > 0 then
			rig.commitFailuresRemaining -= 1
			return Result.err({ code = "INJECTED" })
		end
		rig.transferState = "Committed"
		return Result.ok(true)
	end
	local teleport: any = {}
	function teleport:teleportReserved(placeId: number, accessCode: string, players: { any }, data: any): any
		table.insert(rig.teleports, {
			placeId = placeId,
			accessCode = accessCode,
			players = players,
			data = data,
		})
		return if rig.teleportSucceeds then Result.ok(true) else Result.err({ code = "INJECTED" })
	end
	function teleport:connectInitFailed(listener): any
		initFailed = listener
		return { Disconnect = function() end }
	end
	local created = LobbyReconnectService.new({
		clock = function(): number
			return rig.clock.now
		end,
		activeRoutes = routes,
		teleportAdapter = teleport,
		profileTransfer = transfer,
		getPlayer = function(_userId: number): any
			return player
		end,
		isPresent = function(_userId: number): boolean
			return true
		end,
		makeAttemptId = function(): string
			attemptCount += 1
			return `attempt:rejoin-{attemptCount}`
		end,
		developmentSimulation = developmentSimulation,
	})
	assertions.isTrue(created.ok)
	rig.service = created.value
	rig.emitInitFailure = function(routingData)
		local currentRouting = routingData
		if currentRouting == nil then
			currentRouting = rig.teleports[#rig.teleports].data
		end
		(initFailed :: any)(player, "Terminal", { placeId = 222, routingData = currentRouting })
	end
	return rig
end

return TestHarness.suite("Lobby active-match reconnect", {
	TestHarness.case("releases the profile before initializing an opaque rejoin", function(assertions)
		local rig = makeRig(assertions)
		local view = rig.service:getView(10)
		assertions.isTrue(view.ok)
		assertions.equal(view.value.status, "Available")
		assertions.isNil((view.value :: any).reservedServerAccessCode)
		local result = rig.service:reconnect(10, "transaction:rejoin-one")
		assertions.isTrue(result.ok)
		assertions.equal(result.value.status, "Initializing")
		assertions.equal(rig.transferState, "Released")
		assertions.equal(#rig.teleports, 1)
		assertions.equal(rig.teleports[1].accessCode, "SERVER-ONLY-CODE")
		assertions.equal(rig.teleports[1].data.kind, "Rejoin")
		assertions.equal(rig.teleports[1].data.routeId, "route:rejoin-one")
		assertions.isNil((result.value.route :: any).reservedServerAccessCode)

		local replay = rig.service:reconnect(10, "transaction:rejoin-one")
		assertions.isTrue(replay.ok)
		assertions.equal(#rig.teleports, 1)
		rig.service:removePlayer(10)
		assertions.equal(rig.transferState, "Committed")
	end),

	TestHarness.case("retains a departed reconnect until profile transfer commit succeeds", function(assertions)
		local rig = makeRig(assertions)
		assertions.equal(rig.service:reconnect(10, "transaction:rejoin-commit-retry").value.status, "Initializing")
		rig.commitFailuresRemaining = 1
		rig.service:removePlayer(10)
		assertions.equal(rig.transferState, "Released")
		assertions.equal(rig.service:step(), 1)
		assertions.equal(rig.transferState, "Committed")
		assertions.equal(rig.commitAttempts, 2)
	end),

	TestHarness.case("reacquires ownership and updates the receipt after a late init failure", function(assertions)
		local rig = makeRig(assertions)
		local result = rig.service:reconnect(10, "transaction:rejoin-late-fail")
		assertions.isTrue(result.ok)
		assertions.equal(result.value.status, "Initializing")
		assertions.equal(rig.transferState, "Released")
		rig.emitInitFailure()
		assertions.equal(rig.transferState, "RolledBack")
		local replay = rig.service:reconnect(10, "transaction:rejoin-late-fail")
		assertions.isTrue(replay.ok)
		assertions.equal(replay.value.status, "Failed")
		assertions.equal(#rig.teleports, 1)
	end),

	TestHarness.case("times out a silent initialization and retains rollback until recovery", function(assertions)
		local rig = makeRig(assertions)
		local result = rig.service:reconnect(10, "transaction:rejoin-timeout")
		assertions.equal(result.value.status, "Initializing")
		rig.rollbackFailuresRemaining = 1
		rig.clock.now += LobbyReconnectService.INITIALIZATION_TIMEOUT_SECONDS
		assertions.equal(rig.service:step(), 0)
		assertions.equal(rig.transferState, "Released")
		assertions.equal(rig.service:step(), 1)
		assertions.equal(rig.transferState, "RolledBack")
		assertions.equal(rig.rollbackAttempts, 2)
		assertions.equal(rig.service:reconnect(10, "transaction:rejoin-timeout").value.status, "Failed")
	end),

	TestHarness.case("ignores a delayed failure from an older reconnect attempt", function(assertions)
		local rig = makeRig(assertions)
		assertions.equal(rig.service:reconnect(10, "transaction:rejoin-old").value.status, "Initializing")
		local oldRouting = rig.teleports[1].data
		rig.clock.now += LobbyReconnectService.INITIALIZATION_TIMEOUT_SECONDS
		assertions.equal(rig.service:step(), 1)
		assertions.equal(rig.rollbackAttempts, 1)

		assertions.equal(rig.service:reconnect(10, "transaction:rejoin-new").value.status, "Initializing")
		assertions.equal(rig.teleports[2].data.routeId, oldRouting.routeId)
		assertions.isTrue(rig.teleports[2].data.attemptId ~= oldRouting.attemptId)
		rig.emitInitFailure(oldRouting)
		assertions.equal(rig.transferState, "Released")
		assertions.equal(rig.rollbackAttempts, 1)
		rig.emitInitFailure(rig.teleports[2].data)
		assertions.equal(rig.transferState, "RolledBack")
		assertions.equal(rig.rollbackAttempts, 2)
	end),

	TestHarness.case("rolls profile ownership back when teleport initialization fails", function(assertions)
		local rig = makeRig(assertions)
		rig.teleportSucceeds = false
		local result = rig.service:reconnect(10, "transaction:rejoin-fail")
		assertions.isTrue(result.ok)
		assertions.equal(result.value.status, "Failed")
		assertions.equal(rig.transferState, "RolledBack")
	end),

	TestHarness.case("reacquires the profile after Studio simulated success", function(assertions)
		local rig = makeRig(assertions, true)
		local result = rig.service:reconnect(10, "transaction:rejoin-studio")
		assertions.isTrue(result.ok)
		assertions.equal(result.value.status, "Failed")
		assertions.equal(rig.transferState, "RolledBack")
		assertions.equal(#rig.teleports, 1)
	end),

	TestHarness.case("does not release a profile for a stale or unavailable route", function(assertions)
		local rig = makeRig(assertions)
		rig.route = nil
		local result = rig.service:reconnect(10, "transaction:rejoin-none")
		assertions.isTrue(result.ok)
		assertions.equal(result.value.status, "Unavailable")
		assertions.equal(rig.transferState, "Owned")
		assertions.equal(#rig.teleports, 0)
	end),
})
