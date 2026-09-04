--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local LobbyTravelCoordinator = require(ServerStorage.AutomatedTests.ProductionServerLobbyTravel.LobbyTravelCoordinator)
local Result = require(ReplicatedStorage.Shared.util.Result)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

type Assertions = TestHarness.Assertions

local function settings(): any
	return {
		version = 2,
		masterVolume = 1,
		musicVolume = 1,
		sfxVolume = 1,
		uiVolume = 1,
		cameraShakeIntensity = 1,
		damageNumbersEnabled = true,
		enemyHealthBarsEnabled = true,
		otherPlayerEffectsEnabled = true,
		lowDetailEnabled = false,
		towerRangeEnabled = true,
		uiScale = 1,
		reducedMotionEnabled = false,
	}
end

local function loadout(userId: number, revision: number?): any
	return {
		userId = userId,
		revision = revision or 5,
		slots = { { slot = 1, unitId = `unit:u{userId}`, towerId = `tower:t{userId}` } },
		settings = settings(),
	}
end

local function locked(): any
	return {
		queueId = "queue:backyard-squad",
		revision = 7,
		captainUserId = 10,
		configuration = {
			mapId = "map:phase07-graybox",
			difficultyId = "difficulty:local",
			privacy = "Public",
			maxPlayers = 4,
		},
		orderedUserIds = { 10, 20 },
		members = {
			{ userId = 10, loadout = loadout(10) },
			{ userId = 20, loadout = loadout(20) },
		},
	}
end

type Rig = {
	coordinator: LobbyTravelCoordinator.Service,
	scheduled: { () -> () },
	mode: string,
	failTicket: boolean,
	failComplete: boolean,
	terminalFailuresRemaining: number,
	terminalAttemptCount: number,
	reacquireFailuresRemaining: number,
	reacquireYieldsRemaining: number,
	pendingReleaseFailuresRemaining: number,
	routeClearFailuresRemaining: number,
	tickets: { any },
	routes: { [number]: any },
	pendingReserved: number,
	pendingReleased: number,
	resultIntents: { any },
	cancelledIntents: number,
	transferState: string,
	statuses: { string },
	recoverCount: number,
	completeCount: number,
	reacquired: { number },
	teleportCount: number,
	terminalReasons: { string },
	finishCount: number,
	finishFailuresRemaining: number,
	mutatePreparedLoadout: boolean,
	yieldPrepare: boolean,
	yieldComplete: boolean,
	clock: { now: number },
	present: { [number]: boolean },
	departDuringReacquireUserId: number?,
	committedReleases: { number },
	events: { string },
}

local function makeRig(assertions: Assertions, developmentSimulation: boolean?): Rig
	local rig = {
		coordinator = nil :: any,
		scheduled = {},
		mode = "Success",
		failTicket = false,
		failComplete = false,
		terminalFailuresRemaining = 0,
		terminalAttemptCount = 0,
		reacquireFailuresRemaining = 0,
		reacquireYieldsRemaining = 0,
		pendingReleaseFailuresRemaining = 0,
		routeClearFailuresRemaining = 0,
		tickets = {},
		routes = {},
		pendingReserved = 0,
		pendingReleased = 0,
		resultIntents = {},
		cancelledIntents = 0,
		transferState = "Owned",
		statuses = {},
		recoverCount = 0,
		completeCount = 0,
		reacquired = {},
		teleportCount = 0,
		terminalReasons = {},
		finishCount = 0,
		finishFailuresRemaining = 0,
		mutatePreparedLoadout = false,
		yieldPrepare = false,
		yieldComplete = false,
		clock = { now = 1_000 },
		present = { [10] = true, [20] = true },
		departDuringReacquireUserId = nil,
		committedReleases = {},
		events = {},
	} :: Rig
	local counters = { ticket = 0, match = 0, result = 0, route = 0 }
	local ticketStore: any = {}
	function ticketStore:create(ticket: any): any
		table.insert(rig.tickets, ticket)
		return if rig.failTicket then Result.err({ code = "INJECTED" }) else Result.ok(true)
	end
	function ticketStore:markTerminal(_ticketId: string, reason: string, _now: number): any
		rig.terminalAttemptCount += 1
		if rig.terminalFailuresRemaining > 0 then
			rig.terminalFailuresRemaining -= 1
			return Result.err({ code = "INJECTED" })
		end
		table.insert(rig.terminalReasons, reason)
		return Result.ok(true)
	end
	local pending: any = {}
	function pending:reserve(_users: { number }, _resultId: string, _now: number): any
		table.insert(rig.events, "pending-reserve")
		rig.pendingReserved += 1
		return Result.ok(true)
	end
	function pending:release(_users: { number }, _resultId: string, _now: number): any
		rig.pendingReleased += 1
		if rig.pendingReleaseFailuresRemaining > 0 then
			rig.pendingReleaseFailuresRemaining -= 1
			return Result.err({ code = "INJECTED" })
		end
		return Result.ok(true)
	end
	local resultLedger: any = {}
	function resultLedger:createIntent(intent: any): any
		table.insert(rig.events, "result-intent")
		table.insert(rig.resultIntents, intent)
		return Result.ok(true)
	end
	function resultLedger:cancelIntent(
		_resultId: string,
		_matchId: string,
		_ticketId: string,
		_reason: string,
		_now: number
	): any
		rig.cancelledIntents += 1
		return Result.ok(true)
	end
	local transfer: any = {}
	function transfer:prepare(_users: { number }): any
		table.insert(rig.events, "profile-freeze")
		if rig.yieldPrepare then
			coroutine.yield()
		end
		rig.transferState = "Released"
		local first = loadout(10, 6)
		if rig.mutatePreparedLoadout then
			first.slots[1].towerId = "tower:changed-after-lock"
		end
		return Result.ok({ handle = "handle:one", loadouts = { first, loadout(20, 6) } })
	end
	function transfer:rollback(_handle: unknown): any
		rig.transferState = "RolledBack"
		return Result.ok(true)
	end
	function transfer:recoverCommitted(userId: number): any
		if rig.reacquireYieldsRemaining > 0 then
			rig.reacquireYieldsRemaining -= 1
			coroutine.yield()
		end
		table.insert(rig.reacquired, userId)
		if rig.reacquireFailuresRemaining > 0 then
			rig.reacquireFailuresRemaining -= 1
			return Result.err({ code = "INJECTED" })
		end
		local presentBefore = rig.present[userId] == true
		if rig.departDuringReacquireUserId == userId then
			rig.present[userId] = false
		end
		if presentBefore and rig.present[userId] ~= true then
			table.insert(rig.committedReleases, userId)
		end
		return Result.ok(true)
	end
	function transfer:commit(_handle: unknown): any
		rig.transferState = "Committed"
		return Result.ok(true)
	end
	local queue: any = {}
	function queue:setTravelStatus(_queueId: string, status: string): any
		table.insert(rig.statuses, status)
		return Result.ok(true)
	end
	function queue:recover(_queueId: string): any
		rig.recoverCount += 1
		return Result.ok(true)
	end
	function queue:completeStart(_queueId: string): any
		rig.completeCount += 1
		if rig.yieldComplete then
			coroutine.yield()
		end
		return if rig.failComplete then Result.err({ code = "INJECTED" }) else Result.ok(true)
	end
	local routes: any = {}
	function routes:create(route: any, _now: number): any
		rig.routes[route.userId] = route
		return Result.ok(true)
	end
	function routes:clear(userId: number, _matchId: string): any
		if rig.routeClearFailuresRemaining > 0 then
			rig.routeClearFailuresRemaining -= 1
			return Result.err({ code = "INJECTED" })
		end
		rig.routes[userId] = nil
		return Result.ok(true)
	end
	local teleport: any = {}
	function teleport:start(ticketId: string, _placeId: number, _players: { any }): any
		rig.teleportCount += 1
		local reserved = rig.coordinator:onReserved({
			ticketId = ticketId,
			placeId = 222,
			privateServerId = "private:one",
			accessCode = "SERVER-ONLY-CODE",
			orderedUserIds = { 10, 20 },
		})
		if not reserved then
			return Result.err({ code = "CALLBACK" })
		end
		if rig.mode == "FullFailure" then
			rig.coordinator:onRollback({
				ticketId = ticketId,
				failedUserIds = { 10, 20 },
				presentUserIds = { 10, 20 },
				departedUserIds = {},
				partial = false,
			})
			return Result.err({ code = "TELEPORT" })
		elseif rig.mode == "PartialFailure" then
			rig.coordinator:onRollback({
				ticketId = ticketId,
				failedUserIds = { 10 },
				presentUserIds = { 10 },
				departedUserIds = { 20 },
				partial = true,
			})
			return Result.err({ code = "TELEPORT" })
		elseif rig.mode == "ShutdownDuringTeleport" then
			rig.coordinator:cleanup()
			return Result.err({ code = "SHUTDOWN" })
		end
		return Result.ok(true)
	end
	function teleport:finish(_ticketId: string): any
		rig.finishCount += 1
		if rig.finishFailuresRemaining > 0 then
			rig.finishFailuresRemaining -= 1
			return Result.err({ code = "INJECTED" })
		end
		return Result.ok(true)
	end
	local created = LobbyTravelCoordinator.new({
		clock = function(): number
			return rig.clock.now
		end,
		schedule = function(callback: () -> ())
			table.insert(rig.scheduled, callback)
		end,
		makeId = function(kind: LobbyTravelCoordinator.IdKind): string
			counters[kind] += 1
			return `{kind}:{string.sub(kind, 1, 1)}{counters[kind]}`
		end,
		ticketStore = ticketStore,
		pendingResults = pending,
		resultLedger = resultLedger,
		profileTransfer = transfer,
		safeTeleport = teleport,
		activeRoutes = routes,
		queue = queue,
		getPlayer = function(userId: number): any
			return { userId = userId }
		end,
		isPresent = function(userId: number): boolean
			return rig.present[userId] == true
		end,
		lobbyPlaceId = 111,
		matchPlaceId = 222,
		lobbyJobId = "lobby-job",
		developmentSimulation = developmentSimulation,
	})
	assertions.isTrue(created.ok)
	if not created.ok then
		error("coordinator construction failed", 0)
	end
	rig.coordinator = created.value
	return rig
end

local function runScheduled(assertions: Assertions, rig: Rig)
	assertions.equal(#rig.scheduled, 1)
	local callback = table.remove(rig.scheduled, 1)
	callback()
end

return TestHarness.suite("Lobby squad travel coordinator", {
	TestHarness.case("schedules before durable work and initializes one privacy-safe ticket", function(assertions)
		local rig = makeRig(assertions)
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		assertions.equal(rig.pendingReserved, 0)
		assertions.equal(rig.teleportCount, 0)
		runScheduled(assertions, rig)
		assertions.equal(#rig.tickets, 1)
		assertions.equal(#rig.resultIntents, 1)
		assertions.equal(rig.events[1], "result-intent")
		assertions.equal(rig.events[2], "pending-reserve")
		assertions.equal(rig.events[3], "profile-freeze")
		assertions.equal(rig.pendingReserved, 1)
		assertions.equal(rig.pendingReleased, 0)
		assertions.equal(rig.transferState, "Committed")
		assertions.equal(rig.completeCount, 1)
		assertions.equal(rig.statuses[1], "TeleportInitializing")
		assertions.equal(rig.routes[10].reservedServerAccessCode, "SERVER-ONLY-CODE")
		assertions.isNil(rig.tickets[1].reservedServerAccessCode)
		local summary = rig.coordinator:getContextSummary("queue:backyard-squad")
		assertions.equal((summary :: any).phase, "Initialized")
	end),

	TestHarness.case("joins a yielding start worker before shutdown recovery and cleanup", function(assertions)
		local rig = makeRig(assertions)
		rig.yieldPrepare = true
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		assertions.equal(#rig.scheduled, 1)
		local callback = table.remove(rig.scheduled, 1)
		local worker = coroutine.create(callback)
		local resumed, resumeError = coroutine.resume(worker)
		if not resumed then
			error(resumeError, 0)
		end
		assertions.equal(coroutine.status(worker), "suspended")
		assertions.equal(rig.pendingReserved, 1)
		assertions.equal(rig.transferState, "Owned")

		local blocked = rig.coordinator:cleanup()
		assertions.isFalse(blocked.ok)
		assertions.equal(blocked.error.code, "BUSY")
		assertions.equal(rig.cancelledIntents, 0)
		assertions.equal(rig.pendingReleased, 0)
		assertions.equal(rig.recoverCount, 0)
		assertions.isFalse(rig.coordinator:beginStart(locked()))

		resumed, resumeError = coroutine.resume(worker)
		if not resumed then
			error(resumeError, 0)
		end
		assertions.equal(coroutine.status(worker), "dead")
		assertions.equal(rig.transferState, "RolledBack")
		assertions.equal(rig.cancelledIntents, 1)
		assertions.equal(rig.pendingReleased, 2)
		assertions.equal(rig.recoverCount, 1)
		assertions.equal(#rig.tickets, 0)
		assertions.equal(rig.teleportCount, 0)
		assertions.isTrue(rig.coordinator:cleanup().ok)
		assertions.isTrue(rig.coordinator:getMetrics().cleaned)
	end),

	TestHarness.case("joins a yielding maintenance step before clearing its context", function(assertions)
		local rig = makeRig(assertions)
		rig.failComplete = true
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.equal(
			(rig.coordinator:getContextSummary("queue:backyard-squad") :: any).phase,
			"QueueCompletionPending"
		)

		rig.failComplete = false
		rig.yieldComplete = true
		local progressed = nil
		local worker = coroutine.create(function()
			progressed = rig.coordinator:step()
		end)
		assertions.isTrue(coroutine.resume(worker))
		assertions.equal(coroutine.status(worker), "suspended")
		local blocked = rig.coordinator:cleanup()
		assertions.isFalse(blocked.ok)
		assertions.equal(blocked.error.code, "BUSY")
		assertions.isNotNil(rig.coordinator:getContextSummary("queue:backyard-squad"))

		assertions.isTrue(coroutine.resume(worker))
		assertions.equal(coroutine.status(worker), "dead")
		assertions.equal(progressed, 1)
		assertions.equal((rig.coordinator:getContextSummary("queue:backyard-squad") :: any).phase, "Initialized")
		assertions.isTrue(rig.coordinator:cleanup().ok)
	end),

	TestHarness.case(
		"retries queue finalization and removes an all-departed enrollment only after success",
		function(assertions)
			local rig = makeRig(assertions)
			rig.failComplete = true
			assertions.isTrue(rig.coordinator:beginStart(locked()))
			runScheduled(assertions, rig)
			assertions.equal(
				(rig.coordinator:getContextSummary("queue:backyard-squad") :: any).phase,
				"QueueCompletionPending"
			)
			rig.present[10] = false
			rig.present[20] = false
			rig.coordinator:removePlayer(10)
			rig.coordinator:removePlayer(20)
			rig.failComplete = false
			assertions.equal(rig.coordinator:step(), 2)
			assertions.equal(rig.completeCount, 2)
			assertions.isNil(rig.coordinator:getContextSummary("queue:backyard-squad"))
		end
	),

	TestHarness.case(
		"finishes an initialized original roster after a transient failure even when a member rejoins",
		function(assertions)
			local rig = makeRig(assertions)
			assertions.isTrue(rig.coordinator:beginStart(locked()))
			runScheduled(assertions, rig)
			assertions.equal((rig.coordinator:getContextSummary("queue:backyard-squad") :: any).phase, "Initialized")

			rig.present[10] = false
			assertions.isTrue(rig.coordinator:removePlayer(10))
			rig.present[10] = true
			assertions.equal(rig.coordinator:step(), 0)
			assertions.equal(rig.finishCount, 0)
			assertions.isNotNil(rig.coordinator:getContextSummary("queue:backyard-squad"))

			rig.present[20] = false
			assertions.isTrue(rig.coordinator:removePlayer(20))
			rig.finishFailuresRemaining = 1
			assertions.equal(rig.coordinator:step(), 0)
			assertions.equal(rig.finishCount, 1)
			assertions.isNotNil(rig.coordinator:getContextSummary("queue:backyard-squad"))
			assertions.isTrue(rig.coordinator:isUserTravelPending(10))

			assertions.equal(rig.coordinator:step(), 1)
			assertions.equal(rig.finishCount, 2)
			assertions.isNil(rig.coordinator:getContextSummary("queue:backyard-squad"))
			assertions.isFalse(rig.coordinator:isUserTravelPending(10))
			assertions.isFalse(rig.coordinator:isUserTravelPending(20))
		end
	),

	TestHarness.case("rolls back profiles and pending inboxes when ticket creation fails", function(assertions)
		local rig = makeRig(assertions)
		rig.failTicket = true
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.equal(rig.transferState, "RolledBack")
		assertions.equal(rig.pendingReleased, 2)
		assertions.equal(rig.teleportCount, 0)
		assertions.equal(rig.statuses[1], "TicketFailed")
		assertions.equal(rig.recoverCount, 1)
		assertions.equal(rig.terminalReasons[1], "TICKET_CREATE_FAILED")
		assertions.equal(rig.cancelledIntents, 1)
		rig.failTicket = false
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.equal(#rig.tickets, 2)
	end),

	TestHarness.case("rejects a loadout mutation between queue lock and profile release", function(assertions)
		local rig = makeRig(assertions)
		rig.mutatePreparedLoadout = true
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.equal(rig.transferState, "RolledBack")
		assertions.equal(rig.pendingReleased, 2)
		assertions.equal(#rig.tickets, 0)
		assertions.equal(rig.teleportCount, 0)
		assertions.equal(rig.statuses[1], "TicketFailed")
		assertions.equal(rig.recoverCount, 1)
	end),

	TestHarness.case("restores the complete roster after pre-departure teleport rollback", function(assertions)
		local rig = makeRig(assertions)
		rig.mode = "FullFailure"
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.equal(rig.transferState, "RolledBack")
		assertions.equal(rig.pendingReleased, 2)
		assertions.equal(rig.statuses[#rig.statuses], "TeleportFailed")
		assertions.equal(rig.recoverCount, 1)
		assertions.isNil(rig.routes[10])
	end),

	TestHarness.case(
		"reacquires every present profile after a late all-member initialization failure",
		function(assertions)
			local rig = makeRig(assertions)
			assertions.isTrue(rig.coordinator:beginStart(locked()))
			runScheduled(assertions, rig)
			assertions.equal(rig.transferState, "Committed")
			assertions.equal(rig.pendingReleased, 0)
			assertions.equal(rig.completeCount, 1)

			rig.coordinator:onRollback({
				ticketId = rig.tickets[1].ticketId,
				failedUserIds = { 10, 20 },
				presentUserIds = { 10, 20 },
				departedUserIds = {},
				partial = false,
			})

			assertions.equal(#rig.reacquired, 2)
			assertions.equal(rig.reacquired[1], 10)
			assertions.equal(rig.reacquired[2], 20)
			assertions.equal(rig.pendingReleased, 2)
			assertions.equal(rig.statuses[#rig.statuses], "TeleportFailed")
			assertions.equal(rig.recoverCount, 1)
			assertions.isNil(rig.routes[10])
			assertions.isNil(rig.routes[20])
			assertions.equal(rig.terminalReasons[#rig.terminalReasons], "TELEPORT_ROLLBACK")
		end
	),
	TestHarness.case("joins a yielding rollback callback before shutdown cleanup", function(assertions)
		local rig = makeRig(assertions)
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.equal(rig.transferState, "Committed")
		rig.reacquireYieldsRemaining = 1

		local callback = coroutine.create(function()
			rig.coordinator:onRollback({
				ticketId = rig.tickets[1].ticketId,
				failedUserIds = { 10, 20 },
				presentUserIds = { 10, 20 },
				departedUserIds = {},
				partial = false,
			})
		end)
		assertions.isTrue(coroutine.resume(callback))
		assertions.equal(coroutine.status(callback), "suspended")
		assertions.equal(#rig.reacquired, 0)

		local blocked = rig.coordinator:cleanup()
		assertions.isFalse(blocked.ok)
		assertions.equal(blocked.error.code, "BUSY")
		assertions.equal(rig.recoverCount, 0)
		assertions.equal(rig.pendingReleased, 0)

		assertions.isTrue(coroutine.resume(callback))
		assertions.equal(coroutine.status(callback), "dead")
		assertions.equal(#rig.reacquired, 2)
		assertions.equal(rig.pendingReleased, 2)
		assertions.equal(rig.recoverCount, 1)
		assertions.isTrue(rig.coordinator:cleanup().ok)
		assertions.isTrue(rig.coordinator:getMetrics().cleaned)
	end),
	TestHarness.case("retries committed profile reacquisition before exposing a recovered queue", function(assertions)
		local rig = makeRig(assertions)
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		rig.reacquireFailuresRemaining = 1
		rig.coordinator:onRollback({
			ticketId = rig.tickets[1].ticketId,
			presentUserIds = { 10, 20 },
			departedUserIds = {},
			partial = false,
		})
		assertions.equal(rig.recoverCount, 0)
		assertions.equal((rig.coordinator:getContextSummary("queue:backyard-squad") :: any).phase, "RecoveryPending")
		assertions.equal(rig.coordinator:step(), 1)
		assertions.equal(rig.recoverCount, 1)
		assertions.equal(rig.pendingReleased, 2)
	end),
	TestHarness.case("settles a player who departs during committed Lobby reacquisition", function(assertions)
		local rig = makeRig(assertions)
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		rig.departDuringReacquireUserId = 10
		rig.coordinator:onRollback({
			ticketId = rig.tickets[1].ticketId,
			presentUserIds = { 10, 20 },
			departedUserIds = {},
			partial = false,
		})
		assertions.isFalse(rig.present[10])
		assertions.equal(rig.committedReleases[1], 10)
		assertions.equal(rig.recoverCount, 1)
		assertions.equal(rig.pendingReleased, 1)
	end),

	TestHarness.case(
		"retries partial-failure reacquisition without canceling the live reward intent",
		function(assertions)
			local rig = makeRig(assertions)
			rig.mode = "PartialFailure"
			rig.reacquireFailuresRemaining = 1
			assertions.isTrue(rig.coordinator:beginStart(locked()))
			runScheduled(assertions, rig)
			assertions.equal(rig.recoverCount, 0)
			assertions.equal(rig.cancelledIntents, 0)
			assertions.equal(rig.coordinator:step(), 1)
			assertions.equal(rig.recoverCount, 1)
			assertions.equal(rig.pendingReleased, 0)
			assertions.equal(rig.cancelledIntents, 0)
		end
	),

	TestHarness.case("retries only unfinished pending cleanup after profile reacquisition", function(assertions)
		local rig = makeRig(assertions)
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		rig.pendingReleaseFailuresRemaining = 1
		rig.coordinator:onRollback({
			ticketId = rig.tickets[1].ticketId,
			presentUserIds = { 10, 20 },
			departedUserIds = {},
			partial = false,
		})
		assertions.equal(rig.recoverCount, 0)
		assertions.equal(#rig.reacquired, 2)
		assertions.equal(rig.coordinator:step(), 1)
		assertions.equal(#rig.reacquired, 2)
		assertions.equal(rig.pendingReleased, 3)
	end),

	TestHarness.case("retries privacy-safe route cleanup before queue recovery", function(assertions)
		local rig = makeRig(assertions)
		rig.mode = "FullFailure"
		rig.routeClearFailuresRemaining = 1
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.equal(rig.recoverCount, 0)
		assertions.equal(rig.coordinator:step(), 1)
		assertions.equal(rig.recoverCount, 1)
		assertions.isNil(rig.routes[10])
	end),

	TestHarness.case(
		"keeps a live ticket reconcilable when queue finalization fails after commit",
		function(assertions)
			local rig = makeRig(assertions)
			rig.failComplete = true
			assertions.isTrue(rig.coordinator:beginStart(locked()))
			runScheduled(assertions, rig)

			local summary = rig.coordinator:getContextSummary("queue:backyard-squad")
			assertions.equal((summary :: any).phase, "QueueCompletionPending")
			assertions.isTrue((summary :: any).initialized)
			assertions.isFalse((summary :: any).settled)
			assertions.equal(rig.pendingReleased, 0)
			assertions.equal(#rig.terminalReasons, 0)

			rig.coordinator:onRollback({
				ticketId = rig.tickets[1].ticketId,
				failedUserIds = { 10, 20 },
				presentUserIds = { 10, 20 },
				departedUserIds = {},
				partial = false,
			})
			assertions.equal(#rig.reacquired, 2)
			assertions.equal(rig.pendingReleased, 2)
			assertions.equal(rig.recoverCount, 1)
			assertions.equal(rig.terminalReasons[#rig.terminalReasons], "TELEPORT_ROLLBACK")
		end
	),

	TestHarness.case("does not terminalize an initialized ticket on coordinator shutdown", function(assertions)
		local rig = makeRig(assertions)
		rig.failComplete = true
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.isTrue(rig.coordinator:cleanup().ok)
		assertions.equal(#rig.terminalReasons, 0)
		assertions.equal(rig.pendingReleased, 0)
		assertions.equal(rig.finishCount, 0)
	end),

	TestHarness.case("bounds shutdown retries and recovers a transient cleanup failure", function(assertions)
		local rig = makeRig(assertions)
		rig.mode = "FullFailure"
		rig.terminalFailuresRemaining = LobbyTravelCoordinator.SHUTDOWN_DURABILITY_ATTEMPTS
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.equal((rig.coordinator:getContextSummary("queue:backyard-squad") :: any).phase, "RecoveryPending")

		rig.coordinator:getServiceDefinition().shutdown()

		assertions.equal(rig.terminalAttemptCount, LobbyTravelCoordinator.SHUTDOWN_DURABILITY_ATTEMPTS + 1)
		assertions.equal(rig.terminalReasons[1], "TELEPORT_ROLLBACK")
		assertions.equal(rig.pendingReleased, 2)
		assertions.equal(rig.finishCount, 1)
		assertions.equal(rig.recoverCount, 1)
		assertions.isTrue(rig.coordinator:getMetrics().cleaned)
		assertions.equal(rig.coordinator:getMetrics().contextCount, 0)
		assertions.isNil(rig.coordinator:getContextSummary("queue:backyard-squad"))
	end),

	TestHarness.case("surfaces persistent cleanup failure and retains it for later recovery", function(assertions)
		local rig = makeRig(assertions)
		rig.mode = "FullFailure"
		rig.terminalFailuresRemaining = LobbyTravelCoordinator.SHUTDOWN_DURABILITY_ATTEMPTS + 10
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)

		local shutdownSucceeded, shutdownError = pcall(rig.coordinator:getServiceDefinition().shutdown)
		assertions.isFalse(shutdownSucceeded)
		assertions.isTrue(
			string.find(tostring(shutdownError), "[ATD_LOBBY_TRAVEL][code=SHUTDOWN_DURABILITY_FAILED]", 1, true) ~= nil
		)
		assertions.equal(rig.terminalAttemptCount, LobbyTravelCoordinator.SHUTDOWN_DURABILITY_ATTEMPTS + 1)
		assertions.equal(#rig.terminalReasons, 0)
		assertions.equal(rig.pendingReleased, 2)
		assertions.equal(rig.finishCount, 1)
		assertions.equal(rig.recoverCount, 0)
		assertions.isFalse(rig.coordinator:getMetrics().cleaned)
		assertions.equal(rig.coordinator:getMetrics().contextCount, 1)
		assertions.equal((rig.coordinator:getContextSummary("queue:backyard-squad") :: any).phase, "RecoveryPending")

		rig.terminalFailuresRemaining = 0
		assertions.isTrue(rig.coordinator:cleanup().ok)
		assertions.equal(rig.terminalAttemptCount, LobbyTravelCoordinator.SHUTDOWN_DURABILITY_ATTEMPTS + 2)
		assertions.equal(rig.terminalReasons[1], "TELEPORT_ROLLBACK")
		assertions.equal(rig.pendingReleased, 2)
		assertions.equal(rig.finishCount, 1)
		assertions.equal(rig.recoverCount, 1)
		assertions.isTrue(rig.coordinator:getMetrics().cleaned)
		assertions.equal(rig.coordinator:getMetrics().contextCount, 0)
	end),

	TestHarness.case("retains the reward ticket and never restarts after partial departure", function(assertions)
		local rig = makeRig(assertions)
		rig.mode = "PartialFailure"
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.equal(rig.transferState, "Committed")
		assertions.equal(rig.pendingReleased, 0)
		assertions.equal(rig.reacquired[1], 10)
		assertions.equal(rig.statuses[#rig.statuses], "PartialTeleportFailure")
		assertions.equal(rig.coordinator:getMetrics().partialFailureCount, 1)
		assertions.isTrue(rig.coordinator:isUserTravelPending(10))
		assertions.isTrue(rig.coordinator:isUserTravelPending(20))
		assertions.equal(rig.routes[10].reservedServerAccessCode, "SERVER-ONLY-CODE")
		assertions.isFalse(rig.coordinator:beginStart(locked()))
		assertions.equal(#rig.tickets, 1)
		assertions.isTrue(rig.coordinator:resolveTicket(rig.tickets[1].ticketId))
		assertions.isFalse(rig.coordinator:isUserTravelPending(10))
	end),

	TestHarness.case("retains partial ticket resolution until teleport cleanup succeeds", function(assertions)
		local rig = makeRig(assertions)
		rig.mode = "PartialFailure"
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		local ticketId = rig.tickets[1].ticketId
		rig.finishFailuresRemaining = 1

		assertions.isFalse(rig.coordinator:resolveTicket(ticketId))
		assertions.equal(rig.finishCount, 1)
		assertions.isNotNil(rig.coordinator:getContextSummary("queue:backyard-squad"))
		assertions.isTrue(rig.coordinator:isUserTravelPending(10))
		assertions.equal(rig.pendingReleased, 0)
		assertions.equal(rig.cancelledIntents, 0)

		assertions.isTrue(rig.coordinator:resolveTicket(ticketId))
		assertions.equal(rig.finishCount, 2)
		assertions.isNil(rig.coordinator:getContextSummary("queue:backyard-squad"))
		assertions.isFalse(rig.coordinator:isUserTravelPending(10))
		assertions.equal(rig.pendingReleased, 0)
		assertions.equal(rig.cancelledIntents, 0)
	end),

	TestHarness.case(
		"expires an unreconciled partial guard without dropping pending reward state",
		function(assertions)
			local rig = makeRig(assertions)
			rig.mode = "PartialFailure"
			assertions.isTrue(rig.coordinator:beginStart(locked()))
			runScheduled(assertions, rig)
			assertions.isTrue(rig.coordinator:isUserTravelPending(10))
			rig.clock.now += 2_700
			assertions.equal(rig.coordinator:step(), 1)
			assertions.isFalse(rig.coordinator:isUserTravelPending(10))
			assertions.equal(rig.pendingReleased, 0)
			assertions.equal(rig.terminalReasons[#rig.terminalReasons], "LOBBY_RECONCILE_EXPIRED")
			assertions.isNil(rig.routes[10])
			assertions.isNil(rig.coordinator:getContextSummary("queue:backyard-squad"))
		end
	),

	TestHarness.case("rolls Studio simulated success back into an owned Lobby profile", function(assertions)
		local rig = makeRig(assertions, true)
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.equal(rig.transferState, "RolledBack")
		assertions.equal(rig.pendingReleased, 2)
		assertions.equal(rig.recoverCount, 1)
		assertions.equal(rig.completeCount, 0)
		assertions.equal(rig.terminalReasons[1], "STUDIO_SIMULATED")
		assertions.equal(rig.finishCount, 1)
		assertions.equal(rig.coordinator:getMetrics().simulatedCount, 1)
		assertions.isNil(rig.routes[10])
		assertions.isNil(rig.coordinator:getContextSummary("queue:backyard-squad"))
	end),

	TestHarness.case("shutdown terminals the ticket and leaves no route or pending orphan", function(assertions)
		local rig = makeRig(assertions)
		rig.mode = "ShutdownDuringTeleport"
		assertions.isTrue(rig.coordinator:beginStart(locked()))
		runScheduled(assertions, rig)
		assertions.equal(rig.terminalReasons[1], "LOBBY_SHUTDOWN")
		assertions.equal(#rig.terminalReasons, 1)
		assertions.equal(rig.pendingReleased, 2)
		assertions.equal(rig.transferState, "RolledBack")
		assertions.isNil(rig.routes[10])
		assertions.isNil(rig.routes[20])
		assertions.equal(rig.finishCount, 1)
		assertions.equal(rig.coordinator:getMetrics().contextCount, 0)
	end),
})
