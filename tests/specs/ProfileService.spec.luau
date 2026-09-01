--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local IsolatedProfileStore = require(script.Parent.Parent.Fixtures.IsolatedProfileStore)
local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local ProfileSchema = require(script.Parent.Parent.ProductionServerProfile.ProfileSchema)
local ProfileService = require(script.Parent.Parent.ProductionServerProfile.ProfileService)

type Assertions = TestHarness.Assertions

local USER_ID = 101
local PROFILE_KEY = "profile:101"

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected profile service operation to succeed", 0)
	end
	return result.value
end

local function expectError(assertions: Assertions, result: any, code: string, reason: string?)
	assertions.isFalse(result.ok)
	if not result.ok then
		assertions.equal(result.error.code, code)
		assertions.equal(result.error.reason, reason)
	end
end

local function service(
	assertions: Assertions,
	store: IsolatedProfileStore.Store,
	sessionId: string,
	clock: () -> number,
	extra: { [string]: any }?
): any
	local dependencies = extra or {}
	dependencies.sessionId = sessionId
	dependencies.clock = clock
	dependencies.wait = dependencies.wait or function(_seconds: number) end
	return success(
		assertions,
		ProfileService.new(TowerFixtures.createAuthenticatedFixture().configuration.towers, store, dependencies)
	)
end

local function emptyResult(draft: any, code: string): any
	return {
		resultCode = code,
		goldBalance = draft.gold,
		unitIds = {},
		towerIds = {},
		newFlags = {},
		pityCount = 0,
	}
end

return TestHarness.suite("ProfileService", {
	TestHarness.case("loads a safe starter and exposes explicit bounded readiness views", function(assertions)
		local store = IsolatedProfileStore.new()
		local profileService = service(assertions, store, "session-first", function()
			return 1_000
		end)
		assertions.isNil(profileService:getState(USER_ID))
		local loading = success(assertions, profileService:getClientSnapshot(USER_ID))
		assertions.equal(loading.state, "Loading")
		assertions.isNil(loading.gold)

		local profile = success(assertions, profileService:load(USER_ID))
		assertions.equal(profile.gold, ProfileSchema.STARTER_GOLD)
		assertions.equal(profileService:getState(USER_ID), "Ready")
		local ready = success(assertions, profileService:getClientSnapshot(USER_ID))
		assertions.equal(ready.state, "Ready")
		assertions.equal(ready.migrationOutcome, "Created")
		assertions.equal(ready.gold, ProfileSchema.STARTER_GOLD)
		assertions.isNil((ready :: any).units)
		assertions.isNil((ready :: any).receipts)
		assertions.equal(store:getMetrics().keyCount, 1)
	end),

	TestHarness.case(
		"retries bounded store faults and never installs a writable blank failure profile",
		function(assertions)
			local store = IsolatedProfileStore.new()
			local delays: { number } = {}
			store:failNext(3)
			local profileService = service(assertions, store, "session-retry", function()
				return 2_000
			end, {
				maxAttempts = 3,
				baseBackoffSeconds = 0.1,
				wait = function(seconds: number)
					table.insert(delays, seconds)
				end,
			})
			expectError(assertions, profileService:load(USER_ID), "STORE_FAILED")
			assertions.equal(profileService:getState(USER_ID), "Failed")
			expectError(assertions, profileService:read(USER_ID), "NOT_READY")
			assertions.isNil(store:read(PROFILE_KEY))
			assertions.equal(#delays, 2)
			assertions.equal(delays[1], 0.1)
			assertions.equal(delays[2], 0.2)

			local recovered = success(assertions, profileService:retryLoad(USER_ID))
			assertions.equal(recovered.gold, ProfileSchema.STARTER_GOLD)
			assertions.equal(profileService:getState(USER_ID), "Ready")
		end
	),

	TestHarness.case("rejects malformed stored data without silently replacing it", function(assertions)
		local store = IsolatedProfileStore.new()
		store:seed(PROFILE_KEY, { schemaVersion = ProfileSchema.CURRENT_VERSION })
		local profileService = service(assertions, store, "session-malformed", function()
			return 3_000
		end)
		expectError(assertions, profileService:load(USER_ID), "PROFILE_REJECTED")
		assertions.equal(profileService:getState(USER_ID), "Failed")
		local retained = store:read(PROFILE_KEY) :: any
		assertions.equal(retained.schemaVersion, ProfileSchema.CURRENT_VERSION)
		assertions.isNil(retained.gold)
		assertions.isNil(retained.formatVersion)
	end),

	TestHarness.case("clears a failed unowned session on leave so same-server rejoin can load", function(assertions)
		local store = IsolatedProfileStore.new()
		store:failNext(3)
		local profileService = service(assertions, store, "session-failed-leave", function()
			return 3_500
		end)
		expectError(assertions, profileService:load(USER_ID), "STORE_FAILED")
		assertions.equal(profileService:getState(USER_ID), "Failed")
		assertions.isFalse(success(assertions, profileService:release(USER_ID)))
		assertions.isNil(profileService:getState(USER_ID))
		assertions.equal(success(assertions, profileService:load(USER_ID)).gold, ProfileSchema.STARTER_GOLD)
		assertions.isTrue(success(assertions, profileService:release(USER_ID)))
	end),

	TestHarness.case("protects sessions and detects a lock stolen only after bounded expiry", function(assertions)
		local now = 4_000
		local store = IsolatedProfileStore.new()
		local first = service(assertions, store, "session-owner", function()
			return now
		end, { autosaveSeconds = 15, lockTimeoutSeconds = 30 })
		success(assertions, first:load(USER_ID))

		local contender = service(assertions, store, "session-contender", function()
			return now
		end, { autosaveSeconds = 15, lockTimeoutSeconds = 30 })
		expectError(assertions, contender:load(USER_ID), "SESSION_LOCKED")
		assertions.equal(contender:getState(USER_ID), "Failed")

		now += 31
		local replacement = service(assertions, store, "session-replacement", function()
			return now
		end, { autosaveSeconds = 15, lockTimeoutSeconds = 30 })
		local returned = success(assertions, replacement:load(USER_ID))
		assertions.equal(returned.gold, ProfileSchema.STARTER_GOLD)
		expectError(
			assertions,
			first:transact(USER_ID, "transaction:expired-lease", 1, "InventoryLock", "expired", function(draft)
				return Result.ok(emptyResult(draft, "EXPIRED_REJECTED"))
			end),
			"SESSION_LOST"
		)
		expectError(assertions, first:flush(USER_ID), "NOT_READY")
		assertions.equal(first:getState(USER_ID), "Failed")
		assertions.isTrue(success(assertions, replacement:release(USER_ID)))
		assertions.isNil(replacement:getState(USER_ID))
	end),

	TestHarness.case("heartbeats clean sessions before their lock can expire", function(assertions)
		local now = 4_500
		local store = IsolatedProfileStore.new()
		local owner = service(assertions, store, "session-heartbeat", function()
			return now
		end, { autosaveSeconds = 15, lockTimeoutSeconds = 30 })
		success(assertions, owner:load(USER_ID))
		now += 16
		assertions.equal(success(assertions, owner:stepAutosave()), 1)
		assertions.equal(success(assertions, owner:stepAutosave()), 0)
		task.wait()
		local envelope = store:read(PROFILE_KEY) :: any
		assertions.equal(envelope.session.heartbeatAt, now)

		now += 20
		local contender = service(assertions, store, "session-heartbeat-contender", function()
			return now
		end, { autosaveSeconds = 15, lockTimeoutSeconds = 30 })
		expectError(assertions, contender:load(USER_ID), "SESSION_LOCKED")
		assertions.isTrue(success(assertions, owner:release(USER_ID)))
	end),

	TestHarness.case(
		"commits synchronous atomic mutations and replays receipts without double application",
		function(assertions)
			local store = IsolatedProfileStore.new()
			local profileService = service(assertions, store, "session-transact", function()
				return 5_000
			end)
			local initial = success(assertions, profileService:load(USER_ID))
			local callbackCount = 0
			local transactionId = "transaction:inventory-one"
			local committed = success(
				assertions,
				profileService:transact(
					USER_ID,
					transactionId,
					initial.revision,
					"InventoryFavorite",
					"favorite:on",
					function(draft)
						callbackCount += 1
						local unitId = draft.equippedUnitIds[1]
						draft.units[unitId].favorite = true
						return Result.ok(emptyResult(draft, "FAVORITE_OK"))
					end
				)
			)
			assertions.isTrue(committed.applied)
			assertions.equal(committed.profileRevision, 2)
			assertions.equal(committed.committedRevision, 2)
			assertions.equal(#committed.profile.receipts, 1)
			assertions.isTrue(committed.profile.units[committed.profile.equippedUnitIds[1]].favorite)

			local replay = success(
				assertions,
				profileService:transact(
					USER_ID,
					transactionId,
					initial.revision,
					"InventoryFavorite",
					"favorite:on",
					function(_draft)
						callbackCount += 1
						return Result.err("SHOULD_NOT_RUN")
					end
				)
			)
			assertions.isFalse(replay.applied)
			assertions.equal(replay.profileRevision, 2)
			assertions.equal(replay.committedRevision, 2)
			assertions.equal(replay.result.resultCode, "FAVORITE_OK")
			assertions.equal(callbackCount, 1)
			expectError(
				assertions,
				profileService:transact(USER_ID, transactionId, 2, "InventoryFavorite", "favorite:off", function(_draft)
					return Result.err("SHOULD_NOT_RUN")
				end),
				"TRANSACTION_CONFLICT"
			)
			expectError(
				assertions,
				profileService:transact(USER_ID, "transaction:stale", 1, "InventoryLock", "lock:on", function(draft)
					return Result.ok(emptyResult(draft, "LOCK_OK"))
				end),
				"STALE_REVISION"
			)
		end
	),

	TestHarness.case(
		"contains rejected throwing yielding and invalid mutations with no partial state",
		function(assertions)
			local store = IsolatedProfileStore.new()
			local profileService = service(assertions, store, "session-containment", function()
				return 6_000
			end)
			local initial = success(assertions, profileService:load(USER_ID))
			local initialUnitId = initial.equippedUnitIds[1]
			expectError(
				assertions,
				profileService:transact(USER_ID, "transaction:reject", 1, "InventoryLock", "reject", function(draft)
					draft.units[initialUnitId].locked = true
					return Result.err("UNIT_LOCKED")
				end),
				"MUTATION_REJECTED",
				"UNIT_LOCKED"
			)
			expectError(
				assertions,
				profileService:transact(USER_ID, "transaction:throw", 1, "InventoryLock", "throw", function(_draft)
					error("injected", 0)
				end),
				"CALLBACK_FAILED"
			)
			expectError(
				assertions,
				profileService:transact(USER_ID, "transaction:yield", 1, "InventoryLock", "yield", function(draft)
					coroutine.yield()
					return Result.ok(emptyResult(draft, "LOCK_OK"))
				end),
				"CALLBACK_FAILED"
			)
			expectError(
				assertions,
				profileService:transact(USER_ID, "transaction:invalid", 1, "InventoryLock", "invalid", function(draft)
					draft.gold -= 1
					local result = emptyResult(draft, "LOCK_OK")
					result.goldBalance += 1
					return Result.ok(result)
				end),
				"INVALID_MUTATION"
			)
			local retained = success(assertions, profileService:read(USER_ID))
			assertions.equal(retained.revision, 1)
			assertions.equal(retained.gold, ProfileSchema.STARTER_GOLD)
			assertions.isFalse(retained.units[initialUnitId].locked)
			assertions.equal(#retained.receipts, 0)
		end
	),

	TestHarness.case(
		"persists Gold settings inventory flags pity tutorial and receipts across rejoin",
		function(assertions)
			local now = 7_000
			local store = IsolatedProfileStore.new()
			local first = service(assertions, store, "session-save", function()
				return now
			end)
			local initial = success(assertions, first:load(USER_ID))
			local unitId = initial.equippedUnitIds[1]
			success(
				assertions,
				first:transact(USER_ID, "transaction:persist", 1, "AcquisitionPull", "banner-one:1", function(draft)
					draft.gold = 1_500
					draft.units[unitId].favorite = true
					draft.units[unitId].locked = true
					draft.settings.reducedMotionEnabled = true
					draft.settings.uiScale = 1.25
					draft.bannerPity["banner:starter"] = {
						bannerId = "banner:starter",
						bannerVersion = 1,
						count = 1,
					}
					draft.tutorial.firstJoin = false
					draft.tutorial.tutorialStep = 1
					return Result.ok({
						resultCode = "ACQUISITION_OK",
						goldBalance = draft.gold,
						unitIds = { unitId },
						towerIds = { draft.units[unitId].towerId },
						newFlags = { false },
						pityCount = 1,
					})
				end)
			)
			assertions.isTrue(success(assertions, first:flush(USER_ID)))
			assertions.isTrue(success(assertions, first:release(USER_ID)))

			now += 1
			local returnedService = service(assertions, store, "session-return", function()
				return now
			end)
			local returned = success(assertions, returnedService:load(USER_ID))
			assertions.equal(returned.gold, 1_500)
			assertions.isTrue(returned.units[unitId].favorite)
			assertions.isTrue(returned.units[unitId].locked)
			assertions.isTrue(returned.settings.reducedMotionEnabled)
			assertions.equal(returned.settings.uiScale, 1.25)
			assertions.equal(returned.bannerPity["banner:starter"].count, 1)
			assertions.isFalse(returned.tutorial.firstJoin)
			assertions.equal(returned.tutorial.tutorialStep, 1)
			assertions.equal(#returned.receipts, 1)
			assertions.equal(
				success(assertions, returnedService:getClientSnapshot(USER_ID)).migrationOutcome,
				"Current"
			)
		end
	),

	TestHarness.case("bounds receipt memory and retains newest replay records", function(assertions)
		local store = IsolatedProfileStore.new()
		local profileService = service(assertions, store, "session-receipts", function()
			return 8_000
		end)
		success(assertions, profileService:load(USER_ID))
		for index = 1, ProfileSchema.MAX_RECEIPTS + 1 do
			local profile = success(assertions, profileService:read(USER_ID))
			success(
				assertions,
				profileService:transact(
					USER_ID,
					`transaction:bounded-{index}`,
					profile.revision,
					"InventoryFavorite",
					`bounded:{index}`,
					function(draft)
						return Result.ok(emptyResult(draft, "BOUNDED_OK"))
					end
				)
			)
		end
		local profile = success(assertions, profileService:read(USER_ID))
		assertions.equal(#profile.receipts, ProfileSchema.MAX_RECEIPTS)
		assertions.equal(profile.receipts[1].transactionId, "transaction:bounded-2")
		assertions.equal(profile.receipts[#profile.receipts].transactionId, "transaction:bounded-65")
	end),

	TestHarness.case("closes and can safely cancel the synchronous travel mutation gate", function(assertions)
		local store = IsolatedProfileStore.new()
		local profileService = service(assertions, store, "session-transfer-gate", function()
			return 8_500
		end)
		local initial = success(assertions, profileService:load(USER_ID))
		local frozen = success(assertions, profileService:beginTransfer(USER_ID))
		assertions.equal(frozen.revision, initial.revision)
		assertions.equal(profileService:getState(USER_ID), "Releasing")
		expectError(assertions, profileService:read(USER_ID), "NOT_READY")
		expectError(
			assertions,
			profileService:transact(
				USER_ID,
				"transaction:blocked-during-transfer",
				initial.revision,
				"InventoryLock",
				"transfer-gate",
				function(draft)
					draft.units[draft.equippedUnitIds[1]].locked = true
					return Result.ok(emptyResult(draft, "LOCK_OK"))
				end
			),
			"NOT_READY"
		)
		assertions.isTrue(success(assertions, profileService:cancelTransfer(USER_ID)))
		assertions.equal(profileService:getState(USER_ID), "Ready")

		local committed = success(
			assertions,
			profileService:transact(
				USER_ID,
				"transaction:after-cancel",
				initial.revision,
				"InventoryLock",
				"transfer-cancelled",
				function(draft)
					draft.units[draft.equippedUnitIds[1]].locked = true
					return Result.ok(emptyResult(draft, "LOCK_OK"))
				end
			)
		)
		assertions.isTrue(committed.applied)
		assertions.equal(committed.profileRevision, initial.revision + 1)

		local secondFrozen = success(assertions, profileService:beginTransfer(USER_ID))
		assertions.equal(secondFrozen.revision, initial.revision + 1)
		assertions.isTrue(success(assertions, profileService:release(USER_ID)))
		assertions.isNil(profileService:getState(USER_ID))
	end),

	TestHarness.case(
		"keeps Releasing explicit and allows bounded release retry after store faults",
		function(assertions)
			local store = IsolatedProfileStore.new()
			local profileService = service(assertions, store, "session-release", function()
				return 9_000
			end)
			success(assertions, profileService:load(USER_ID))
			store:failNext(2)
			expectError(assertions, profileService:release(USER_ID), "STORE_FAILED")
			assertions.equal(profileService:getState(USER_ID), "Releasing")
			assertions.isTrue(success(assertions, profileService:release(USER_ID)))
			assertions.isNil(profileService:getState(USER_ID))
			assertions.isFalse(success(assertions, profileService:release(USER_ID)))
			local rejoined = success(assertions, profileService:load(USER_ID))
			assertions.equal(rejoined.gold, ProfileSchema.STARTER_GOLD)
			assertions.isTrue(success(assertions, profileService:release(USER_ID)))
		end
	),

	TestHarness.case("retries a departed dirty profile across the bounded release cycles", function(assertions)
		local store = IsolatedProfileStore.new()
		local profileService = service(assertions, store, "session-departed-retry", function()
			return 9_250
		end, { maxAttempts = 2 })
		local initial = success(assertions, profileService:load(USER_ID))
		success(
			assertions,
			profileService:transact(
				USER_ID,
				"transaction:departed-retry",
				initial.revision,
				"InventoryFavorite",
				"favorite:departed-retry",
				function(draft)
					draft.units[draft.equippedUnitIds[1]].favorite = true
					return Result.ok(emptyResult(draft, "FAVORITE_OK"))
				end
			)
		)
		store:failNext(4)
		local depart = ProfileService.departPlayerForTests
		assertions.isTrue(depart ~= nil and depart(profileService, USER_ID))
		for _ = 1, 20 do
			if profileService:getState(USER_ID) == nil then
				break
			end
			task.wait()
		end

		assertions.isNil(profileService:getState(USER_ID))
		assertions.equal(store:getMetrics().injectedFailureCount, 4)
		local envelope = store:read(PROFILE_KEY) :: any
		assertions.isNil(envelope.session)
		assertions.isTrue(envelope.profile.units[envelope.profile.equippedUnitIds[1]].favorite)
	end),

	TestHarness.case("honors a leave that races an in-flight important save", function(assertions)
		local backing = IsolatedProfileStore.new()
		local updateCount = 0
		local profileService: any = nil
		local racedRelease: any = nil
		local hookedStore = table.freeze({
			updateAsync = function(_self: any, key: string, transform: (unknown) -> unknown): unknown
				updateCount += 1
				if updateCount == 2 then
					racedRelease = profileService:release(USER_ID)
				end
				return backing:updateAsync(key, transform)
			end,
		}) :: any
		profileService = service(assertions, hookedStore, "session-save-leave-race", function()
			return 9_500
		end)
		local initial = success(assertions, profileService:load(USER_ID))
		success(
			assertions,
			profileService:transact(
				USER_ID,
				"transaction:save-leave-race",
				initial.revision,
				"InventoryFavorite",
				"favorite:race",
				function(draft)
					draft.units[draft.equippedUnitIds[1]].favorite = true
					return Result.ok(emptyResult(draft, "FAVORITE_OK"))
				end
			)
		)
		assertions.isTrue(success(assertions, profileService:flush(USER_ID)))
		expectError(assertions, racedRelease, "BUSY")
		assertions.isNil(profileService:getState(USER_ID))
		assertions.equal(updateCount, 3)
		local envelope = backing:read(PROFILE_KEY) :: any
		assertions.isNil(envelope.session)
		assertions.isTrue(envelope.profile.units[envelope.profile.equippedUnitIds[1]].favorite)
	end),

	TestHarness.case("releases owned locks during bounded idempotent lifecycle shutdown", function(assertions)
		local store = IsolatedProfileStore.new()
		local profileService = service(assertions, store, "session-shutdown", function()
			return 10_000
		end, { shutdownBudgetSeconds = 1 })
		local definition = profileService:getServiceDefinition()
		definition.initialize()
		success(assertions, profileService:load(USER_ID))
		definition.shutdown()
		definition.shutdown()
		assertions.isNil(profileService:getState(USER_ID))
		assertions.equal(profileService:getMetrics().lifecycleState, "Shutdown")
		local envelope = store:read(PROFILE_KEY) :: any
		assertions.equal(envelope.formatVersion, ProfileService.STORE_FORMAT_VERSION)
		assertions.isNil(envelope.session)
		expectError(assertions, profileService:load(202), "INVALID_STATE")
	end),

	TestHarness.case("releases a lock acquired after player leave races an in-flight load", function(assertions)
		local backing = IsolatedProfileStore.new()
		local profileService: any = nil
		local releaseResult: any = nil
		local updateCount = 0
		local hookedStore = table.freeze({
			updateAsync = function(_self: any, key: string, transform: (unknown) -> unknown): unknown
				updateCount += 1
				if updateCount == 1 then
					releaseResult = profileService:release(USER_ID)
				end
				return backing:updateAsync(key, transform)
			end,
		}) :: any
		profileService = service(assertions, hookedStore, "session-load-leave-race", function()
			return 10_500
		end)
		expectError(assertions, profileService:load(USER_ID), "INVALID_STATE")
		assertions.isFalse(success(assertions, releaseResult))
		assertions.equal(updateCount, 2)
		assertions.isNil(profileService:getState(USER_ID))
		local envelope = backing:read(PROFILE_KEY) :: any
		assertions.isNil(envelope.session)
	end),

	TestHarness.case("backs off failed autosaves before retrying the clean-session heartbeat", function(assertions)
		local now = 11_000
		local store = IsolatedProfileStore.new()
		local profileService = service(assertions, store, "session-autosave-backoff", function()
			return now
		end, { autosaveSeconds = 15, lockTimeoutSeconds = 60 })
		success(assertions, profileService:load(USER_ID))
		now += 16
		store:failNext(3)
		assertions.equal(success(assertions, profileService:stepAutosave()), 1)
		task.wait()
		assertions.equal(store:getMetrics().injectedFailureCount, 3)
		assertions.equal(success(assertions, profileService:stepAutosave()), 0)
		now += 4
		assertions.equal(success(assertions, profileService:stepAutosave()), 0)
		now += 1
		assertions.equal(success(assertions, profileService:stepAutosave()), 1)
		task.wait()
		local envelope = store:read(PROFILE_KEY) :: any
		assertions.equal(envelope.session.heartbeatAt, now)
		assertions.isTrue(success(assertions, profileService:release(USER_ID)))
	end),

	TestHarness.case(
		"hands a BUSY important save to the yielding autosave and persists the newer revision",
		function(assertions)
			local now = 12_000
			local backing = IsolatedProfileStore.new()
			local updateCount = 0
			local autosaveEntered = false
			local allowAutosave = false
			local hookedStore = table.freeze({
				updateAsync = function(_self: any, key: string, transform: (unknown) -> unknown): unknown
					updateCount += 1
					if updateCount == 2 then
						autosaveEntered = true
						while not allowAutosave do
							task.wait()
						end
					end
					return backing:updateAsync(key, transform)
				end,
			}) :: any
			local profileService = service(assertions, hookedStore, "session-important-autosave-race", function()
				return now
			end, { autosaveSeconds = 15, lockTimeoutSeconds = 60 })
			local initial = success(assertions, profileService:load(USER_ID))
			now += 16
			assertions.equal(success(assertions, profileService:stepAutosave()), 1)
			for _ = 1, 20 do
				if autosaveEntered then
					break
				end
				task.wait()
			end
			assertions.isTrue(autosaveEntered)

			local changed = success(
				assertions,
				profileService:transact(
					USER_ID,
					"transaction:important-autosave-race",
					initial.revision,
					"InventoryFavorite",
					"favorite:important-autosave-race",
					function(draft)
						draft.units[draft.equippedUnitIds[1]].favorite = true
						return Result.ok(emptyResult(draft, "FAVORITE_OK"))
					end
				)
			)
			assertions.equal(changed.profileRevision, initial.revision + 1)
			assertions.isTrue(success(assertions, profileService:queueImportantSave(USER_ID)))
			task.wait()
			allowAutosave = true

			for _ = 1, 40 do
				local stored = backing:read(PROFILE_KEY) :: any
				if stored ~= nil and stored.profile.revision == changed.profileRevision then
					break
				end
				task.wait()
			end
			local envelope = backing:read(PROFILE_KEY) :: any
			assertions.equal(updateCount, 3)
			assertions.equal(envelope.profile.revision, changed.profileRevision)
			assertions.isTrue(envelope.profile.units[envelope.profile.equippedUnitIds[1]].favorite)
			assertions.isTrue(success(assertions, profileService:release(USER_ID)))
		end
	),

	TestHarness.case("bounds shutdown while a yielding load releases its late-acquired lock", function(assertions)
		local backing = IsolatedProfileStore.new()
		local loadEntered = false
		local allowLoad = false
		local updateCount = 0
		local hookedStore = table.freeze({
			updateAsync = function(_self: any, key: string, transform: (unknown) -> unknown): unknown
				updateCount += 1
				if updateCount == 1 then
					loadEntered = true
					while not allowLoad do
						task.wait()
					end
				end
				return backing:updateAsync(key, transform)
			end,
		}) :: any
		local profileService = service(assertions, hookedStore, "session-shutdown-load-race", function()
			return 13_000
		end, { shutdownBudgetSeconds = 0.05 })
		local definition = profileService:getServiceDefinition()
		definition.initialize()
		local loadResult: any = nil
		task.spawn(function()
			loadResult = profileService:load(USER_ID)
		end)
		for _ = 1, 20 do
			if loadEntered then
				break
			end
			task.wait()
		end
		assertions.isTrue(loadEntered)

		local shutdownStartedAt = os.clock()
		definition.shutdown()
		local shutdownElapsed = os.clock() - shutdownStartedAt
		assertions.isTrue(shutdownElapsed < 0.5)
		assertions.equal(profileService:getMetrics().lifecycleState, "Shutdown")
		allowLoad = true

		for _ = 1, 40 do
			if loadResult ~= nil and profileService:getState(USER_ID) == nil then
				break
			end
			task.wait()
		end
		expectError(assertions, loadResult, "INVALID_STATE")
		assertions.equal(updateCount, 2)
		assertions.isNil(profileService:getState(USER_ID))
		local envelope = backing:read(PROFILE_KEY) :: any
		assertions.isNil(envelope.session)
	end),
})
