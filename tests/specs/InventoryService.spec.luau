--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local Result = require(ReplicatedStorage.Shared.util.Result)
local InventoryService = require(ServerStorage.AutomatedTests.ProductionServerLobbyInventory.InventoryService)

local loaded = ConfigurationValidator.validateLoaded()
if not loaded.ok then
	error("expected production configuration", 0)
end

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

local function profile(): any
	return {
		schemaVersion = 3,
		revision = 1,
		gold = 2_000,
		units = {
			["unit:a"] = {
				unitId = "unit:a",
				towerId = "tower:dart-ant",
				favorite = false,
				locked = false,
				acquiredAt = 1,
				acquisitionSequence = 1,
			},
			["unit:b"] = {
				unitId = "unit:b",
				towerId = "tower:dart-ant",
				favorite = false,
				locked = false,
				acquiredAt = 2,
				acquisitionSequence = 2,
			},
			["unit:c"] = {
				unitId = "unit:c",
				towerId = "tower:rapid-ant",
				favorite = false,
				locked = false,
				acquiredAt = 3,
				acquisitionSequence = 3,
			},
			["unit:d"] = {
				unitId = "unit:d",
				towerId = "tower:guard-ant",
				favorite = false,
				locked = false,
				acquiredAt = 4,
				acquisitionSequence = 4,
			},
		},
		equippedUnitIds = { "unit:a" },
		bannerPity = {},
		stats = { towersAcquired = 4, chestsOpened = 0 },
	}
end

local function owner(initial: any): (any, () -> any, () -> number)
	local current = copy(initial)
	local state = "Ready"
	local callbacks = 0
	local receipts: { [string]: any } = {}
	local value = {}
	function value:getState(_userId: number): string
		return state
	end
	function value:read(_userId: number): any
		return Result.ok(copy(current))
	end
	function value:transact(
		_userId: number,
		transactionId: string,
		expectedRevision: number,
		kind: string,
		fingerprint: string,
		callback: (any) -> any
	): any
		local stored = receipts[transactionId]
		if stored ~= nil then
			if stored.kind ~= kind or stored.fingerprint ~= fingerprint then
				return Result.err({ code = "TRANSACTION_CONFLICT" })
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
		local staged = copy(current)
		callbacks += 1
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
	function value:setState(nextState: string)
		state = nextState
	end
	return value, function(): any
		return current
	end, function(): number
		return callbacks
	end
end

local function equipIntent(transactionId: string, revision: number, unitId: string, slot: number): any
	return {
		transactionId = transactionId,
		expectedRevision = revision,
		unitId = unitId,
		slot = slot,
	}
end

local function unitIntent(transactionId: string, revision: number, unitId: string): any
	return {
		transactionId = transactionId,
		expectedRevision = revision,
		unitId = unitId,
	}
end

return TestHarness.suite("server-owned inventory transactions", {
	TestHarness.case("derives bounded copy counts and equipped state", function(assertions)
		local fake = owner(profile())
		local service = InventoryService.new(fake, loaded.value)
		assertions.isTrue(service.ok)
		if service.ok then
			local result = service.value:getSnapshot(42)
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.equal(result.value.revision, 1)
				assertions.equal(#result.value.units, 4)
				assertions.equal(result.value.copyCounts[1].copies, 2)
				assertions.equal(result.value.equipped[1].unitId, "unit:a")
			end
		end
	end),
	TestHarness.case("equips atomically and replays without a second mutation", function(assertions)
		local fake, current, callbacks = owner(profile())
		local service = InventoryService.new(fake, loaded.value)
		assertions.isTrue(service.ok)
		if not service.ok then
			return
		end
		local intent = equipIntent("transaction:equip-c", 1, "unit:c", 2)
		local first = service.value:equip(42, intent)
		local replay = service.value:equip(42, intent)
		assertions.isTrue(first.ok)
		assertions.isTrue(replay.ok)
		if first.ok and replay.ok then
			assertions.isTrue(first.value.changed)
			assertions.equal(first.value.revision, 2)
			assertions.equal(replay.value.revision, 2)
			assertions.equal(replay.value.snapshot.equipped[2].unitId, "unit:c")
		end
		assertions.equal(callbacks(), 1)
		assertions.equal(#current().equippedUnitIds, 2)
	end),
	TestHarness.case("rejects stale duplicate unowned and invalid slot mutations", function(assertions)
		local fake = owner(profile())
		local service = InventoryService.new(fake, loaded.value)
		assertions.isTrue(service.ok)
		if not service.ok then
			return
		end
		local stale = service.value:equip(42, equipIntent("transaction:stale", 2, "unit:c", 2))
		assertions.isFalse(stale.ok)
		if not stale.ok then
			assertions.equal(stale.error.code, "STALE_REVISION")
		end
		local duplicate = service.value:equip(42, equipIntent("transaction:duplicate", 1, "unit:b", 2))
		assertions.isFalse(duplicate.ok)
		if not duplicate.ok then
			assertions.equal(duplicate.error.code, "DUPLICATE_TOWER")
		end
		assertions.isFalse(service.value:equip(42, equipIntent("transaction:missing", 1, "unit:missing", 2)).ok)
		assertions.isFalse(service.value:equip(42, equipIntent("transaction:slot", 1, "unit:c", 3)).ok)
	end),
	TestHarness.case("allows one duplicate record to replace the same tower slot", function(assertions)
		local fake, current = owner(profile())
		local service = InventoryService.new(fake, loaded.value)
		assertions.isTrue(service.ok)
		if service.ok then
			local result = service.value:equip(42, equipIntent("transaction:replace-copy", 1, "unit:b", 1))
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.equal(result.value.snapshot.equipped[1].unitId, "unit:b")
			end
		end
		assertions.equal(current().equippedUnitIds[1], "unit:b")
	end),
	TestHarness.case("never allows an unusable zero-attacker loadout", function(assertions)
		local fake = owner(profile())
		local service = InventoryService.new(fake, loaded.value)
		assertions.isTrue(service.ok)
		if service.ok then
			local result = service.value:unequip(42, unitIntent("transaction:unequip-only", 1, "unit:a"))
			assertions.isFalse(result.ok)
			if not result.ok then
				assertions.equal(result.error.code, "ZERO_ATTACKING_TOWERS")
			end
		end
	end),
	TestHarness.case("favorites and locks are idempotent revisioned mutations", function(assertions)
		local fake, current = owner(profile())
		local service = InventoryService.new(fake, loaded.value)
		assertions.isTrue(service.ok)
		if not service.ok then
			return
		end
		local favorite = service.value:favorite(42, {
			transactionId = "transaction:favorite",
			expectedRevision = 1,
			unitId = "unit:c",
			enabled = true,
		})
		local locked = service.value:lock(42, {
			transactionId = "transaction:lock",
			expectedRevision = 2,
			unitId = "unit:c",
			enabled = true,
		})
		assertions.isTrue(favorite.ok)
		assertions.isTrue(locked.ok)
		assertions.isTrue(current().units["unit:c"].favorite)
		assertions.isTrue(current().units["unit:c"].locked)
		assertions.equal(current().revision, 3)
	end),
	TestHarness.case("blocks every read and mutation before readiness", function(assertions)
		local fake = owner(profile())
		fake:setState("Loading")
		local service = InventoryService.new(fake, loaded.value)
		assertions.isTrue(service.ok)
		if service.ok then
			assertions.isFalse(service.value:getSnapshot(42).ok)
			assertions.isFalse(service.value:equip(42, equipIntent("transaction:not-ready", 1, "unit:c", 2)).ok)
		end
	end),
})
