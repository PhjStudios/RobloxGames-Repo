--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type UnitView = {
	unitId: string,
	towerId: string,
	favorite: boolean,
	locked: boolean,
	equippedSlot: number?,
}

export type CopyCount = {
	towerId: string,
	copies: number,
}

export type EquippedSlot = {
	slot: number,
	unitId: string,
	towerId: string,
}

export type Snapshot = {
	revision: number,
	units: { UnitView },
	copyCounts: { CopyCount },
	equipped: { EquippedSlot },
}

export type EquipIntent = {
	transactionId: string,
	expectedRevision: number,
	unitId: string,
	slot: number,
}

export type UnitMutationIntent = {
	transactionId: string,
	expectedRevision: number,
	unitId: string,
}

export type ToggleIntent = UnitMutationIntent & {
	enabled: boolean,
}

export type MutationKind = "Equip" | "Unequip" | "Favorite" | "Lock"

export type MutationReceipt = {
	transactionId: string,
	kind: MutationKind,
	changed: boolean,
	revision: number,
	snapshot: Snapshot,
}

local MAX_UNITS = 64
local MAX_LOADOUT_SLOTS = 5
local MAX_COPY_COUNTS = 64

local POSITIVE_SAFE_INTEGER = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)

local UNIT_VIEW = PayloadValidation.record({
	unitId = PayloadValidation.id("unit"),
	towerId = PayloadValidation.id("tower"),
	favorite = PayloadValidation.boolean(),
	locked = PayloadValidation.boolean(),
	equippedSlot = PayloadValidation.optional(PayloadValidation.integer(1, MAX_LOADOUT_SLOTS)),
})

local COPY_COUNT = PayloadValidation.record({
	towerId = PayloadValidation.id("tower"),
	copies = PayloadValidation.integer(1, MAX_UNITS),
})

local EQUIPPED_SLOT = PayloadValidation.record({
	slot = PayloadValidation.integer(1, MAX_LOADOUT_SLOTS),
	unitId = PayloadValidation.id("unit"),
	towerId = PayloadValidation.id("tower"),
})

local SNAPSHOT = PayloadValidation.record({
	revision = POSITIVE_SAFE_INTEGER,
	units = PayloadValidation.array(UNIT_VIEW, MAX_UNITS, 1),
	copyCounts = PayloadValidation.array(COPY_COUNT, MAX_COPY_COUNTS, 1),
	equipped = PayloadValidation.array(EQUIPPED_SLOT, MAX_LOADOUT_SLOTS, 1),
})

local EQUIP_INTENT = PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	expectedRevision = POSITIVE_SAFE_INTEGER,
	unitId = PayloadValidation.id("unit"),
	slot = PayloadValidation.integer(1, MAX_LOADOUT_SLOTS),
})

local UNIT_MUTATION_INTENT = PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	expectedRevision = POSITIVE_SAFE_INTEGER,
	unitId = PayloadValidation.id("unit"),
})

local TOGGLE_INTENT = PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	expectedRevision = POSITIVE_SAFE_INTEGER,
	unitId = PayloadValidation.id("unit"),
	enabled = PayloadValidation.boolean(),
})

local MUTATION_RECEIPT = PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	kind = PayloadValidation.enum({ "Equip", "Unequip", "Favorite", "Lock" }),
	changed = PayloadValidation.boolean(),
	revision = POSITIVE_SAFE_INTEGER,
	snapshot = SNAPSHOT,
})

local SnapshotSchema = PayloadValidation.schema(SNAPSHOT)
local EquipIntentSchema = PayloadValidation.schema(EQUIP_INTENT)
local UnitMutationIntentSchema = PayloadValidation.schema(UNIT_MUTATION_INTENT)
local ToggleIntentSchema = PayloadValidation.schema(TOGGLE_INTENT)
local MutationReceiptSchema = PayloadValidation.schema(MUTATION_RECEIPT)

local InventoryProtocol = {
	MAX_UNITS = MAX_UNITS,
	MAX_LOADOUT_SLOTS = MAX_LOADOUT_SLOTS,
	MAX_COPY_COUNTS = MAX_COPY_COUNTS,
	SnapshotSchema = SnapshotSchema,
	EquipIntentSchema = EquipIntentSchema,
	UnitMutationIntentSchema = UnitMutationIntentSchema,
	ToggleIntentSchema = ToggleIntentSchema,
	MutationReceiptSchema = MutationReceiptSchema,
}

local function failure(
	code: Validation.Code,
	path: { Validation.PathSegment },
	message: string
): Result.Failure<Validation.Issue>
	return Result.err(Validation.issue(code, path, message))
end

function InventoryProtocol.validateSnapshot(value: unknown): Result.Result<Snapshot, Validation.Issue>
	local result = SnapshotSchema:validate(value)
	if not result.ok then
		return Result.err(result.error)
	end
	local snapshot = result.value :: Snapshot
	local unitsById: { [string]: UnitView } = {}
	local expectedCounts: { [string]: number } = {}
	local previousUnitId: string? = nil
	for index, unit in snapshot.units do
		if previousUnitId ~= nil and unit.unitId <= previousUnitId then
			return failure(
				"INVALID_ORDER",
				{ "payload", "units", index, "unitId" },
				"Inventory units must be uniquely ordered by unit ID"
			)
		end
		previousUnitId = unit.unitId
		unitsById[unit.unitId] = unit
		expectedCounts[unit.towerId] = (expectedCounts[unit.towerId] or 0) + 1
	end

	local observedCounts: { [string]: boolean } = {}
	local previousTowerId: string? = nil
	for index, entry in snapshot.copyCounts do
		if previousTowerId ~= nil and entry.towerId <= previousTowerId then
			return failure(
				"INVALID_ORDER",
				{ "payload", "copyCounts", index, "towerId" },
				"Copy counts must be uniquely ordered by tower ID"
			)
		end
		previousTowerId = entry.towerId
		if expectedCounts[entry.towerId] ~= entry.copies then
			return failure(
				"INVALID_TOTAL",
				{ "payload", "copyCounts", index, "copies" },
				"Copy count does not match unique unit records"
			)
		end
		observedCounts[entry.towerId] = true
	end
	for towerId in expectedCounts do
		if not observedCounts[towerId] then
			return failure("INVALID_TOTAL", { "payload", "copyCounts" }, "Copy counts omit an owned tower definition")
		end
	end

	local equippedUnits: { [string]: boolean } = {}
	local equippedTowers: { [string]: boolean } = {}
	for index, slot in snapshot.equipped do
		if slot.slot ~= index then
			return failure(
				"INVALID_ORDER",
				{ "payload", "equipped", index, "slot" },
				"Equipped slots must be dense and ordered"
			)
		end
		local unit = unitsById[slot.unitId]
		if unit == nil or unit.towerId ~= slot.towerId or unit.equippedSlot ~= index then
			return failure(
				"INVALID_REFERENCE",
				{ "payload", "equipped", index },
				"Equipped slot does not reference its exact owned unit"
			)
		end
		if equippedUnits[slot.unitId] or equippedTowers[slot.towerId] then
			return failure(
				"DUPLICATE_VALUE",
				{ "payload", "equipped", index },
				"Equipped loadout duplicates a unit or tower definition"
			)
		end
		equippedUnits[slot.unitId] = true
		equippedTowers[slot.towerId] = true
	end
	for index, unit in snapshot.units do
		if (unit.equippedSlot ~= nil) ~= (equippedUnits[unit.unitId] == true) then
			return failure(
				"INVALID_REFERENCE",
				{ "payload", "units", index, "equippedSlot" },
				"Unit equipped state does not match the loadout"
			)
		end
	end
	return Result.ok(snapshot)
end

function InventoryProtocol.validateMutationReceipt(value: unknown): Result.Result<MutationReceipt, Validation.Issue>
	local result = MutationReceiptSchema:validate(value)
	if not result.ok then
		return Result.err(result.error)
	end
	local receipt = result.value :: MutationReceipt
	if receipt.revision ~= receipt.snapshot.revision then
		return failure(
			"INVALID_REFERENCE",
			{ "payload", "revision" },
			"Mutation receipt revision must match its snapshot"
		)
	end
	local snapshotResult = InventoryProtocol.validateSnapshot(receipt.snapshot)
	if not snapshotResult.ok then
		return Result.err(snapshotResult.error)
	end
	return Result.ok(receipt)
end

return table.freeze(InventoryProtocol)
