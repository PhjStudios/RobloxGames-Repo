--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local InventoryProtocol = require(ReplicatedStorage.Shared.inventory.InventoryProtocol)

local function snapshot(): any
	return {
		revision = 7,
		units = {
			{
				unitId = "unit:a",
				towerId = "tower:dart-ant",
				favorite = true,
				locked = false,
				equippedSlot = 1,
			},
			{
				unitId = "unit:b",
				towerId = "tower:dart-ant",
				favorite = false,
				locked = true,
			},
			{
				unitId = "unit:c",
				towerId = "tower:guard-ant",
				favorite = false,
				locked = false,
				equippedSlot = 2,
			},
		},
		copyCounts = {
			{ towerId = "tower:dart-ant", copies = 2 },
			{ towerId = "tower:guard-ant", copies = 1 },
		},
		equipped = {
			{ slot = 1, unitId = "unit:a", towerId = "tower:dart-ant" },
			{ slot = 2, unitId = "unit:c", towerId = "tower:guard-ant" },
		},
	}
end

return TestHarness.suite("bounded inventory protocol", {
	TestHarness.case("accepts detached unit copy and loadout views", function(assertions)
		local raw = snapshot()
		local result = InventoryProtocol.validateSnapshot(raw)
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.notEqual(result.value, raw)
			assertions.isTrue(table.isfrozen(result.value))
			assertions.isTrue(table.isfrozen(result.value.units))
			assertions.equal(result.value.copyCounts[1].copies, 2)
			assertions.equal(result.value.equipped[2].towerId, "tower:guard-ant")
		end
	end),
	TestHarness.case("rejects mismatched counts duplicate towers and stale flags", function(assertions)
		local wrongCount = snapshot()
		wrongCount.copyCounts[1].copies = 1
		assertions.isFalse(InventoryProtocol.validateSnapshot(wrongCount).ok)
		local duplicateTower = snapshot()
		duplicateTower.equipped[2].towerId = "tower:dart-ant"
		duplicateTower.units[3].towerId = "tower:dart-ant"
		duplicateTower.copyCounts = { { towerId = "tower:dart-ant", copies = 3 } }
		assertions.isFalse(InventoryProtocol.validateSnapshot(duplicateTower).ok)
		local staleFlag = snapshot()
		staleFlag.units[1].equippedSlot = 2
		assertions.isFalse(InventoryProtocol.validateSnapshot(staleFlag).ok)
	end),
	TestHarness.case("rejects unordered sparse private and oversized snapshots", function(assertions)
		local unordered = snapshot()
		unordered.units[1], unordered.units[2] = unordered.units[2], unordered.units[1]
		assertions.isFalse(InventoryProtocol.validateSnapshot(unordered).ok)
		local sparse = snapshot()
		sparse.equipped[4] = sparse.equipped[2]
		sparse.equipped[2] = nil
		assertions.isFalse(InventoryProtocol.validateSnapshot(sparse).ok)
		local private = snapshot()
		private.rawProfile = {}
		assertions.isFalse(InventoryProtocol.validateSnapshot(private).ok)
	end),
	TestHarness.case("validates mutation intents and bounded slots", function(assertions)
		assertions.isTrue(InventoryProtocol.EquipIntentSchema:validate({
			transactionId = "transaction:equip-a",
			expectedRevision = 1,
			unitId = "unit:a",
			slot = 5,
		}).ok)
		assertions.isFalse(InventoryProtocol.EquipIntentSchema:validate({
			transactionId = "transaction:equip-a",
			expectedRevision = 1,
			unitId = "unit:a",
			slot = 6,
		}).ok)
		assertions.isTrue(InventoryProtocol.ToggleIntentSchema:validate({
			transactionId = "transaction:favorite-a",
			expectedRevision = 1,
			unitId = "unit:a",
			enabled = true,
		}).ok)
	end),
	TestHarness.case("validates coherent mutation receipts", function(assertions)
		local receipt = {
			transactionId = "transaction:equip-a",
			kind = "Equip",
			changed = true,
			revision = 7,
			snapshot = snapshot(),
		}
		assertions.isTrue(InventoryProtocol.validateMutationReceipt(receipt).ok)
		receipt.revision = 8
		assertions.isFalse(InventoryProtocol.validateMutationReceipt(receipt).ok)
	end),
})
