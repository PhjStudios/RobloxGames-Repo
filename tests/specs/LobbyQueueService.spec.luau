--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local LobbyQueueService = require(ServerStorage.AutomatedTests.ProductionServerLobbyQueue.LobbyQueueService)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

type Assertions = TestHarness.Assertions

type Rig = {
	service: LobbyQueueService.Service,
	present: { [number]: boolean },
	parties: { [number]: any },
	eligibility: { [number]: any },
	starts: { LobbyQueueService.LockedStart },
	beginAccepted: boolean,
	changes: { any },
}

local function success(assertions: Assertions, value: any): any
	assertions.isTrue(value.ok)
	if not value.ok then
		error("expected queue operation to succeed", 0)
	end
	return value.value
end

local function makeRig(assertions: Assertions): Rig
	local loaded = ConfigurationValidator.validateLoaded()
	assertions.isTrue(loaded.ok)
	if not loaded.ok then
		error("expected authenticated configuration", 0)
	end
	local rig = {
		service = nil :: any,
		present = {},
		parties = {},
		eligibility = {},
		starts = {},
		beginAccepted = true,
		changes = {},
	} :: Rig
	for userId = 10, 60, 10 do
		rig.present[userId] = true
		rig.eligibility[userId] = {
			profileReady = true,
			sessionOwned = true,
			loadoutReady = true,
			ticketEligible = true,
			loadout = {
				userId = userId,
				revision = 1,
				slots = { { slot = 1, unitId = `unit:u{userId}`, towerId = "tower:dart-ant" } },
				settings = { reducedMotionEnabled = false },
			},
		}
	end
	rig.service = success(
		assertions,
		LobbyQueueService.new(loaded.value, {
			{ queueId = "queue:one" },
			{ queueId = "queue:two" },
		}, {
			isPresent = function(userId: number): boolean
				return rig.present[userId] == true
			end,
			getParty = function(userId: number): unknown
				return rig.parties[userId]
			end,
			getEligibility = function(userId: number): unknown
				return rig.eligibility[userId]
			end,
			beginStart = function(locked: LobbyQueueService.LockedStart): unknown
				table.insert(rig.starts, locked)
				return rig.beginAccepted
			end,
			onChanged = function(queueId: string, snapshot: any)
				table.insert(rig.changes, { queueId = queueId, snapshot = snapshot })
			end,
		})
	)
	return rig
end

local function setParty(rig: Rig, partyId: string, revision: number, members: { number })
	local party = {
		partyId = partyId,
		revision = revision,
		leaderUserId = members[1],
		members = table.clone(members),
	}
	for _, userId in members do
		rig.parties[userId] = party
	end
end

local function join(
	assertions: Assertions,
	rig: Rig,
	queueId: string,
	userId: number,
	suffix: string,
	source: string?
): any
	local before = success(assertions, rig.service:getSnapshot(queueId))
	return success(
		assertions,
		rig.service:join(userId, {
			transactionId = `transaction:join-{suffix}`,
			expectedRevision = before.revision,
			queueId = queueId,
			source = source or "UI",
		})
	)
end

return TestHarness.suite("server-owned lobby queue", {
	TestHarness.case("keeps an accepted StartQueue handoff locked instead of reopening", function(assertions)
		local rig = makeRig(assertions)
		local joined = join(assertions, rig, "queue:one", 10, "deferred-handoff")
		local started = success(
			assertions,
			rig.service:start(10, {
				transactionId = "transaction:start-deferred-handoff",
				expectedRevision = joined.revision,
				queueId = "queue:one",
			})
		)
		assertions.equal(started.kind, "Start")
		assertions.isTrue(started.changed)
		assertions.equal(started.revision, joined.revision + 1)
		assertions.equal(started.snapshot.revision, started.revision)
		assertions.equal(started.snapshot.state, "Starting")
		assertions.equal(started.snapshot.publicStatus, "TicketPending")
		assertions.equal(#rig.starts, 1)
		assertions.equal(rig.starts[1].queueId, "queue:one")
	end),

	TestHarness.case("enrolls parties atomically and transfers captain by enrollment order", function(assertions)
		local rig = makeRig(assertions)
		setParty(rig, "party:squad", 3, { 10, 20 })
		local partyJoin = join(assertions, rig, "queue:one", 10, "party")
		assertions.equal(#partyJoin.snapshot.members, 2)
		assertions.equal(#partyJoin.snapshot.enrollments, 1)
		assertions.equal(partyJoin.snapshot.captainUserId, 10)
		assertions.equal(rig.service:getQueueForUser(20), "queue:one")

		local soloJoin = join(assertions, rig, "queue:one", 30, "solo")
		assertions.equal(#soloJoin.snapshot.members, 3)
		local left = success(
			assertions,
			rig.service:leave(20, {
				transactionId = "transaction:party-unit-leave",
				expectedRevision = soloJoin.revision,
				queueId = "queue:one",
			})
		)
		assertions.equal(#left.snapshot.members, 1)
		assertions.equal(left.snapshot.members[1].userId, 30)
		assertions.equal(left.snapshot.captainUserId, 30)
		assertions.isNil(rig.service:getQueueForUser(10))
		assertions.isNil(rig.service:getQueueForUser(20))
	end),

	TestHarness.case("enforces profile readiness one queue capacity and party leadership", function(assertions)
		local rig = makeRig(assertions)
		rig.eligibility[10].profileReady = false
		local blocked = rig.service:join(10, {
			transactionId = "transaction:not-ready",
			expectedRevision = 1,
			queueId = "queue:one",
			source = "UI",
		})
		assertions.isFalse(blocked.ok)
		if not blocked.ok then
			assertions.equal(blocked.error.code, "PROFILE_NOT_READY")
		end
		rig.eligibility[10].profileReady = true
		setParty(rig, "party:leader-check", 1, { 10, 20, 30 })
		local nonleader = rig.service:join(20, {
			transactionId = "transaction:nonleader",
			expectedRevision = 1,
			queueId = "queue:one",
			source = "UI",
		})
		assertions.isFalse(nonleader.ok)
		if not nonleader.ok then
			assertions.equal(nonleader.error.code, "NOT_PARTY_LEADER")
		end

		rig.parties[40] = nil
		join(assertions, rig, "queue:one", 40, "captain")
		local partyJoin = join(assertions, rig, "queue:one", 10, "three")
		assertions.equal(#partyJoin.snapshot.members, 4)
		local full = rig.service:join(50, {
			transactionId = "transaction:full",
			expectedRevision = partyJoin.revision,
			queueId = "queue:one",
			source = "UI",
		})
		assertions.isFalse(full.ok)
		if not full.ok then
			assertions.equal(full.error.code, "QUEUE_FULL")
		end
		assertions.isNil(rig.service:getQueueForUser(50))

		local otherQueue = rig.service:join(10, {
			transactionId = "transaction:other-queue",
			expectedRevision = 1,
			queueId = "queue:two",
			source = "UI",
		})
		assertions.isFalse(otherQueue.ok)
		if not otherQueue.ok then
			assertions.equal(otherQueue.error.code, "ALREADY_QUEUED")
		end
	end),

	TestHarness.case(
		"locks authenticated loadouts and exposes bounded travel failure transitions",
		function(assertions)
			local rig = makeRig(assertions)
			local joined = join(assertions, rig, "queue:one", 10, "start")
			local started = success(
				assertions,
				rig.service:start(10, {
					transactionId = "transaction:start",
					expectedRevision = joined.revision,
					queueId = "queue:one",
				})
			)
			assertions.equal(started.snapshot.state, "Starting")
			assertions.equal(started.snapshot.publicStatus, "TicketPending")
			assertions.isFalse(started.snapshot.canStart)
			assertions.equal(#rig.starts, 1)
			assertions.isTrue(table.isfrozen(rig.starts[1]))
			assertions.isTrue(table.isfrozen(rig.starts[1].members[1].loadout :: any))
			assertions.isFalse(success(assertions, rig.service:setTravelStatus("queue:one", "TicketPending")))

			assertions.isTrue(rig.service:markTraveling("queue:one", "TeleportInitializing").ok)
			local traveling = success(assertions, rig.service:getSnapshot("queue:one"))
			assertions.equal(traveling.state, "Traveling")
			assertions.equal(traveling.publicStatus, "TeleportInitializing")
			assertions.isTrue(rig.service:markTraveling("queue:one", "TeleportRetrying").ok)
			assertions.isTrue(rig.service:markFailed("queue:one", "PartialTeleportFailure").ok)
			local failed = success(assertions, rig.service:getSnapshot("queue:one"))
			assertions.equal(failed.state, "Failed")
			assertions.equal(failed.publicStatus, "PartialTeleportFailure")
			assertions.isFalse(success(assertions, rig.service:setTravelStatus("queue:one", "PartialTeleportFailure")))
			assertions.isFalse(rig.service:setTravelStatus("queue:one", "TeleportFailed").ok)
			assertions.isFalse(rig.service:setTravelStatus("queue:one", "TicketPending").ok)
			assertions.isFalse(rig.service:setTravelStatus("queue:one", "access-code:SECRET").ok)
			assertions.isFalse(rig.service:markTraveling("queue:one", "reserved-code:SECRET").ok)

			assertions.isTrue(rig.service:recover("queue:one").ok)
			local recovered = success(assertions, rig.service:getSnapshot("queue:one"))
			assertions.equal(recovered.state, "Open")
			assertions.isNil(recovered.publicStatus)
			assertions.equal(#recovered.members, 1)
			assertions.isFalse(rig.service:markFailed("queue:one", "TeleportFailed").ok)

			rig.beginAccepted = false
			local startFailure = rig.service:start(10, {
				transactionId = "transaction:start-fails",
				expectedRevision = recovered.revision,
				queueId = "queue:one",
			})
			assertions.isFalse(startFailure.ok)
			if not startFailure.ok then
				assertions.equal(startFailure.error.code, "START_FAILED")
			end
			local afterFailure = success(assertions, rig.service:getSnapshot("queue:one"))
			assertions.equal(afterFailure.state, "Open")
			assertions.equal(#afterFailure.members, 1)
		end
	),

	TestHarness.case("removes stale party units before start and replays mutations idempotently", function(assertions)
		local rig = makeRig(assertions)
		setParty(rig, "party:mutable", 1, { 10, 20 })
		local joined = join(assertions, rig, "queue:one", 10, "mutable")
		local replayed = rig.service:join(10, {
			transactionId = "transaction:join-mutable",
			expectedRevision = 1,
			queueId = "queue:one",
			source = "UI",
		})
		assertions.isTrue(replayed.ok)
		if replayed.ok then
			assertions.equal(replayed.value, joined)
		end
		setParty(rig, "party:mutable", 2, { 10 })
		rig.parties[20] = nil
		local stale = rig.service:start(10, {
			transactionId = "transaction:stale-party-start",
			expectedRevision = joined.revision,
			queueId = "queue:one",
		})
		assertions.isFalse(stale.ok)
		if not stale.ok then
			assertions.equal(stale.error.code, "PARTY_CHANGED")
		end
		local clean = success(assertions, rig.service:getSnapshot("queue:one"))
		assertions.equal(#clean.members, 0)
		assertions.isNil(clean.captainUserId)
		assertions.equal(clean.configuration.maxPlayers, 4)
	end),

	TestHarness.case(
		"serializes captain configuration stale revisions privacy and roster capacity",
		function(assertions)
			local rig = makeRig(assertions)
			join(assertions, rig, "queue:one", 10, "config-captain")
			local joined = join(assertions, rig, "queue:one", 20, "config-member")
			local original = joined.snapshot.configuration
			local nonCaptain = rig.service:configure(20, {
				transactionId = "transaction:configure-noncaptain",
				expectedRevision = joined.revision,
				queueId = "queue:one",
				configuration = original,
			})
			assertions.isFalse(nonCaptain.ok)
			if not nonCaptain.ok then
				assertions.equal(nonCaptain.error.code, "NOT_CAPTAIN")
			end
			local belowRoster = rig.service:configure(10, {
				transactionId = "transaction:configure-small",
				expectedRevision = joined.revision,
				queueId = "queue:one",
				configuration = {
					mapId = original.mapId,
					difficultyId = original.difficultyId,
					privacy = "PartyOnly",
					maxPlayers = 1,
				},
			})
			assertions.isFalse(belowRoster.ok)
			if not belowRoster.ok then
				assertions.equal(belowRoster.error.code, "INVALID_SELECTION")
			end

			local mixedPrivacy = rig.service:configure(10, {
				transactionId = "transaction:configure-mixed-party-only",
				expectedRevision = joined.revision,
				queueId = "queue:one",
				configuration = {
					mapId = original.mapId,
					difficultyId = original.difficultyId,
					privacy = "PartyOnly",
					maxPlayers = 3,
				},
			})
			assertions.isFalse(mixedPrivacy.ok)
			if not mixedPrivacy.ok then
				assertions.equal(mixedPrivacy.error.code, "INVALID_SELECTION")
			end
			local left = success(
				assertions,
				rig.service:leave(20, {
					transactionId = "transaction:leave-before-party-only",
					expectedRevision = joined.revision,
					queueId = "queue:one",
				})
			)
			local configured = success(
				assertions,
				rig.service:configure(10, {
					transactionId = "transaction:configure-party-only",
					expectedRevision = left.revision,
					queueId = "queue:one",
					configuration = {
						mapId = original.mapId,
						difficultyId = original.difficultyId,
						privacy = "PartyOnly",
						maxPlayers = 3,
					},
				})
			)
			assertions.equal(configured.snapshot.configuration.privacy, "PartyOnly")
			local stale = rig.service:configure(10, {
				transactionId = "transaction:configure-stale",
				expectedRevision = joined.revision,
				queueId = "queue:one",
				configuration = configured.snapshot.configuration,
			})
			assertions.isFalse(stale.ok)
			if not stale.ok then
				assertions.equal(stale.error.code, "STALE_REVISION")
			end
			local privateJoin = rig.service:join(30, {
				transactionId = "transaction:join-private",
				expectedRevision = configured.revision,
				queueId = "queue:one",
				source = "UI",
			})
			assertions.isFalse(privateJoin.ok)
			if not privateJoin.ok then
				assertions.equal(privateJoin.error.code, "PRIVACY_RESTRICTED")
			end
		end
	),

	TestHarness.case("freezes locked membership across disconnect and party invalidation races", function(assertions)
		local rig = makeRig(assertions)
		setParty(rig, "party:locked", 1, { 10, 20 })
		local joined = join(assertions, rig, "queue:one", 10, "locked-party")
		local started = success(
			assertions,
			rig.service:start(10, {
				transactionId = "transaction:locked-start",
				expectedRevision = joined.revision,
				queueId = "queue:one",
			})
		)
		assertions.equal(started.snapshot.state, "Starting")
		assertions.equal(success(assertions, rig.service:invalidateParty("party:locked", { 10, 20 })), 0)
		assertions.isFalse(success(assertions, rig.service:removePlayer(20)))

		local duringStarting = success(assertions, rig.service:getSnapshot("queue:one"))
		assertions.equal(duringStarting.state, "Starting")
		assertions.equal(duringStarting.revision, started.revision)
		assertions.equal(#duringStarting.members, 2)
		assertions.equal(rig.service:getQueueForUser(20), "queue:one")
		local leave = rig.service:leave(10, {
			transactionId = "transaction:locked-leave",
			expectedRevision = duringStarting.revision,
			queueId = "queue:one",
		})
		assertions.isFalse(leave.ok)
		if not leave.ok then
			assertions.equal(leave.error.code, "QUEUE_LOCKED")
		end

		assertions.isTrue(rig.service:markTraveling("queue:one", "TeleportInitializing").ok)
		local traveling = success(assertions, rig.service:getSnapshot("queue:one"))
		assertions.equal(success(assertions, rig.service:invalidateParty("party:locked", { 10, 20 })), 0)
		assertions.isFalse(success(assertions, rig.service:removePlayer(10)))
		local stillTraveling = success(assertions, rig.service:getSnapshot("queue:one"))
		assertions.equal(stillTraveling.state, "Traveling")
		assertions.equal(stillTraveling.revision, traveling.revision)
		assertions.equal(#stillTraveling.members, 2)

		assertions.isTrue(rig.service:markFailed("queue:one", "PartialTeleportFailure").ok)
		assertions.isTrue(rig.service:recover("queue:one").ok)
		assertions.equal(success(assertions, rig.service:invalidateParty("party:locked", { 10, 20 })), 1)
		local open = success(assertions, rig.service:getSnapshot("queue:one"))
		assertions.equal(open.state, "Open")
		assertions.equal(#open.members, 0)
	end),

	TestHarness.case("reconciles a queued solo when party membership changes", function(assertions)
		local rig = makeRig(assertions)
		local joined = join(assertions, rig, "queue:one", 20, "solo-before-accept")
		assertions.equal(joined.snapshot.enrollments[1].kind, "Solo")

		setParty(rig, "party:destination", 2, { 10, 20 })
		local removed = success(assertions, rig.service:invalidateParty("party:destination", { 10, 20 }))
		assertions.equal(removed, 1)
		assertions.isNil(rig.service:getQueueForUser(20))
		local snapshot = success(assertions, rig.service:getSnapshot("queue:one"))
		assertions.equal(snapshot.state, "Open")
		assertions.equal(#snapshot.enrollments, 0)
		assertions.equal(snapshot.configuration.maxPlayers, 4)
	end),
})
