--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local IsolatedProfileStore = require(script.Parent.Parent.Fixtures.IsolatedProfileStore)
local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local ProfileService = require(script.Parent.Parent.ProductionServerProfile.ProfileService)
local SettingsService = require(script.Parent.Parent.ProductionServerLobbySettings.SettingsService)

local USER_ID = 802

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local output = {}
	for key, child in next, value do
		output[copy(key)] = copy(child)
	end
	return output
end

local function defaultSettings(): any
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
		reducedMotionEnabled = false,
		towerRangeEnabled = true,
		uiScale = 1,
	}
end

local function profile(): any
	return {
		revision = 1,
		gold = 2_000,
		settings = defaultSettings(),
	}
end

local function updateIntent(transactionId: string, revision: number): any
	return {
		transactionId = transactionId,
		expectedRevision = revision,
		version = 2,
		masterVolume = 0.9,
		musicVolume = 0.8,
		sfxVolume = 0.7,
		uiVolume = 0.6,
		cameraShakeIntensity = 0.4,
		damageNumbersEnabled = false,
		enemyHealthBarsEnabled = false,
		otherPlayerEffectsEnabled = false,
		lowDetailEnabled = true,
		reducedMotionEnabled = true,
		towerRangeEnabled = false,
		uiScale = 1.2,
	}
end

local function fakeOwner(initial: any): (any, () -> any, () -> number)
	local current = copy(initial)
	local state = "Ready"
	local callbacks = 0
	local receipts: { [string]: any } = {}
	local owner = {}

	function owner:getState(_userId: number): string
		return state
	end

	function owner:read(_userId: number): any
		if state ~= "Ready" then
			return Result.err({ code = "NOT_READY" })
		end
		return Result.ok(copy(current))
	end

	function owner:transact(
		_userId: number,
		transactionId: string,
		expectedRevision: number,
		kind: string,
		fingerprint: string,
		callback: (any) -> any
	): any
		if state ~= "Ready" then
			return Result.err({ code = "NOT_READY" })
		end
		local stored = receipts[transactionId]
		if stored ~= nil then
			if stored.kind ~= kind or stored.fingerprint ~= fingerprint then
				return Result.err({ code = "RECEIPT_CONFLICT" })
			end
			return Result.ok({
				applied = false,
				profileRevision = current.revision,
				committedRevision = stored.committedRevision,
				result = copy(stored.result),
				profile = copy(current),
			})
		end
		if expectedRevision ~= current.revision then
			return Result.err({ code = "STALE_REVISION" })
		end
		callbacks += 1
		local staged = copy(current)
		local outcome = callback(staged)
		if outcome.ok ~= true then
			return Result.err({ code = "MUTATION_REJECTED", reason = outcome.error })
		end
		staged.revision += 1
		current = staged
		local receipt = {
			kind = kind,
			fingerprint = fingerprint,
			committedRevision = current.revision,
			result = copy(outcome.value),
		}
		receipts[transactionId] = receipt
		return Result.ok({
			applied = true,
			profileRevision = current.revision,
			committedRevision = current.revision,
			result = copy(receipt.result),
			profile = copy(current),
		})
	end

	function owner:setState(nextState: string)
		state = nextState
	end

	return owner, function(): any
		return current
	end, function(): number
		return callbacks
	end
end

local function realProfileService(
	assertions: TestHarness.Assertions,
	store: IsolatedProfileStore.Store,
	session: string
): any
	local created = ProfileService.new(TowerFixtures.createAuthenticatedFixture().configuration.towers, store, {
		sessionId = session,
		clock = function(): number
			return 50_000
		end,
		wait = function(_seconds: number) end,
	})
	assertions.isTrue(created.ok)
	if not created.ok then
		error("expected isolated profile service", 0)
	end
	return created.value
end

return TestHarness.suite("persistent settings service", {
	TestHarness.case("gates reads and mutations on an explicitly Ready profile", function(assertions)
		local owner, current, callbacks = fakeOwner(profile())
		owner:setState("Loading")
		local service = SettingsService.new(owner)
		assertions.isTrue(service.ok)
		if service.ok then
			local read = service.value:getSettings(USER_ID)
			local update = service.value:update(USER_ID, updateIntent("transaction:loading", 1))
			assertions.isFalse(read.ok)
			assertions.isFalse(update.ok)
			if not read.ok then
				assertions.equal(read.error.code, "NOT_READY")
			end
			if not update.ok then
				assertions.equal(update.error.code, "NOT_READY")
			end
		end
		assertions.equal(current().revision, 1)
		assertions.equal(callbacks(), 0)
	end),
	TestHarness.case("applies every validated setting in one revision", function(assertions)
		local owner, current, callbacks = fakeOwner(profile())
		local service = SettingsService.new(owner)
		assertions.isTrue(service.ok)
		if not service.ok then
			return
		end
		local result = service.value:update(USER_ID, updateIntent("transaction:full", 1))
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.isTrue(result.value.changed)
			assertions.equal(result.value.revision, 2)
			assertions.equal(result.value.settings.masterVolume, 0.9)
			assertions.equal(result.value.settings.musicVolume, 0.8)
			assertions.equal(result.value.settings.sfxVolume, 0.7)
			assertions.equal(result.value.settings.uiVolume, 0.6)
			assertions.equal(result.value.settings.cameraShakeIntensity, 0.4)
			assertions.isFalse(result.value.settings.damageNumbersEnabled)
			assertions.isFalse(result.value.settings.enemyHealthBarsEnabled)
			assertions.isFalse(result.value.settings.otherPlayerEffectsEnabled)
			assertions.isTrue(result.value.settings.lowDetailEnabled)
			assertions.isTrue(result.value.settings.reducedMotionEnabled)
			assertions.isFalse(result.value.settings.towerRangeEnabled)
			assertions.equal(result.value.settings.uiScale, 1.2)
		end
		assertions.equal(current().revision, 2)
		assertions.equal(callbacks(), 1)
	end),
	TestHarness.case("enforces revision CAS before invoking the mutation", function(assertions)
		local owner, current, callbacks = fakeOwner(profile())
		local service = SettingsService.new(owner)
		assertions.isTrue(service.ok)
		if service.ok then
			local stale = service.value:update(USER_ID, updateIntent("transaction:stale", 2))
			assertions.isFalse(stale.ok)
			if not stale.ok then
				assertions.equal(stale.error.code, "STALE_REVISION")
			end
		end
		assertions.equal(current().revision, 1)
		assertions.equal(callbacks(), 0)
	end),
	TestHarness.case("replays an identical request and conflicts changed intent reuse", function(assertions)
		local owner, current, callbacks = fakeOwner(profile())
		local service = SettingsService.new(owner)
		assertions.isTrue(service.ok)
		if not service.ok then
			return
		end
		local request = updateIntent("transaction:replay", 1)
		local first = service.value:update(USER_ID, request)
		local replay = service.value:update(USER_ID, request)
		assertions.isTrue(first.ok)
		assertions.isTrue(replay.ok)
		if first.ok and replay.ok then
			assertions.isTrue(replay.value.changed)
			assertions.equal(replay.value.revision, first.value.revision)
			assertions.equal(replay.value.settings.uiScale, first.value.settings.uiScale)
		end
		local conflictRequest = updateIntent("transaction:replay", 2)
		conflictRequest.musicVolume = 0.1
		local conflict = service.value:update(USER_ID, conflictRequest)
		assertions.isFalse(conflict.ok)
		if not conflict.ok then
			assertions.equal(conflict.error.code, "TRANSACTION_CONFLICT")
		end
		assertions.equal(current().revision, 2)
		assertions.equal(callbacks(), 1)
	end),
	TestHarness.case("records an unchanged full request as a replay-safe no-op", function(assertions)
		local owner, current, callbacks = fakeOwner(profile())
		local service = SettingsService.new(owner)
		assertions.isTrue(service.ok)
		if not service.ok then
			return
		end
		local request = defaultSettings()
		request.transactionId = "transaction:no-op"
		request.expectedRevision = 1
		local first = service.value:update(USER_ID, request)
		local replay = service.value:update(USER_ID, request)
		assertions.isTrue(first.ok)
		assertions.isTrue(replay.ok)
		if first.ok and replay.ok then
			assertions.isFalse(first.value.changed)
			assertions.isFalse(replay.value.changed)
			assertions.equal(replay.value.revision, first.value.revision)
		end
		assertions.equal(current().revision, 2)
		assertions.equal(callbacks(), 1)
	end),
	TestHarness.case("rejects malformed hostile and authority-bearing inputs", function(assertions)
		local owner, current, callbacks = fakeOwner(profile())
		local service = SettingsService.new(owner)
		assertions.isTrue(service.ok)
		if not service.ok then
			return
		end
		local partial = updateIntent("transaction:partial", 1)
		partial.musicVolume = nil
		assertions.isFalse(service.value:update(USER_ID, partial).ok)

		local forged = updateIntent("transaction:forged", 1)
		forged.gold = 999_999
		assertions.isFalse(service.value:update(USER_ID, forged).ok)

		local nonFinite = updateIntent("transaction:nan", 1)
		nonFinite.uiScale = 0 / 0
		assertions.isFalse(service.value:update(USER_ID, nonFinite).ok)

		local cyclic = updateIntent("transaction:cyclic", 1)
		cyclic.extra = cyclic
		assertions.isFalse(service.value:update(USER_ID, cyclic).ok)
		assertions.isFalse(service.value:update(0, updateIntent("transaction:user", 1)).ok)
		assertions.equal(current().revision, 1)
		assertions.equal(callbacks(), 0)
	end),
	TestHarness.case("rejects malformed persistent settings without exposing defaults", function(assertions)
		local rawProfile = profile()
		rawProfile.settings.reducedMotionEnabled = nil
		local owner = fakeOwner(rawProfile)
		local service = SettingsService.new(owner)
		assertions.isTrue(service.ok)
		if service.ok then
			local result = service.value:getSettings(USER_ID)
			assertions.isFalse(result.ok)
			if not result.ok then
				assertions.equal(result.error.code, "PROFILE_INVALID")
			end
		end
	end),
	TestHarness.case("persists a generic receipt and settings across isolated rejoin", function(assertions)
		local store = IsolatedProfileStore.new()
		local firstProfile = realProfileService(assertions, store, "settings-session-first")
		local loadedFirst = firstProfile:load(USER_ID)
		assertions.isTrue(loadedFirst.ok)
		if not loadedFirst.ok then
			return
		end
		local firstSettings = SettingsService.new(firstProfile)
		assertions.isTrue(firstSettings.ok)
		if not firstSettings.ok then
			return
		end
		local request = updateIntent("transaction:persistent-settings", loadedFirst.value.revision)
		local updated = firstSettings.value:update(USER_ID, request)
		assertions.isTrue(updated.ok)
		if updated.ok then
			assertions.isTrue(updated.value.changed)
			assertions.equal(updated.value.settings.uiScale, 1.2)
		end
		assertions.isTrue(firstProfile:flush(USER_ID).ok)
		assertions.isTrue(firstProfile:release(USER_ID).ok)

		local secondProfile = realProfileService(assertions, store, "settings-session-second")
		local loadedSecond = secondProfile:load(USER_ID)
		assertions.isTrue(loadedSecond.ok)
		if not loadedSecond.ok then
			return
		end
		local secondSettings = SettingsService.new(secondProfile)
		assertions.isTrue(secondSettings.ok)
		if not secondSettings.ok then
			return
		end
		local restored = secondSettings.value:getSettings(USER_ID)
		assertions.isTrue(restored.ok)
		if restored.ok then
			assertions.equal(restored.value.masterVolume, 0.9)
			assertions.equal(restored.value.uiScale, 1.2)
			assertions.isTrue(restored.value.reducedMotionEnabled)
		end

		local replay = secondSettings.value:update(USER_ID, request)
		assertions.isTrue(replay.ok)
		if replay.ok and updated.ok then
			assertions.isTrue(replay.value.changed)
			assertions.equal(replay.value.revision, updated.value.revision)
			assertions.equal(replay.value.settings.uiScale, 1.2)
		end
		local afterReplay = secondProfile:read(USER_ID)
		assertions.isTrue(afterReplay.ok)
		if afterReplay.ok then
			assertions.equal(afterReplay.value.revision, loadedSecond.value.revision)
		end
		assertions.isTrue(secondProfile:release(USER_ID).ok)
	end),
})
