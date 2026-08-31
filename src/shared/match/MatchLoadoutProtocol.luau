--!strict

local ConfigurationValidator = require(script.Parent.Parent.config.ConfigurationValidator)
local SettingsProtocol = require(script.Parent.Parent.settings.SettingsProtocol)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type Slot = {
	slot: number,
	unitId: Ids.UnitId,
	towerId: Ids.TowerId,
}

export type Snapshot = {
	userId: number,
	revision: number,
	slots: { Slot },
	settings: SettingsProtocol.Settings,
}

export type ErrorCode =
	"INVALID_SNAPSHOT"
	| "UNAUTHENTICATED_CONFIGURATION"
	| "UNKNOWN_TOWER"
	| "DUPLICATE_TOWER"
	| "DUPLICATE_UNIT"

export type LoadoutError = {
	code: ErrorCode,
	path: string,
}

local MIN_SLOTS = 1
local MAX_SLOTS = 5
local ROOT_FIELDS: { [string]: boolean } = table.freeze({
	revision = true,
	settings = true,
	slots = true,
	userId = true,
})
local SLOT_FIELDS: { [string]: boolean } = table.freeze({
	slot = true,
	towerId = true,
	unitId = true,
})

local MatchLoadoutProtocol = {
	MIN_SLOTS = MIN_SLOTS,
	MAX_SLOTS = MAX_SLOTS,
}

local function failure(code: ErrorCode, path: string): Result.Failure<LoadoutError>
	return Result.err(table.freeze({
		code = code,
		path = path,
	}))
end

local function hasExactFields(value: { [any]: unknown }, fields: { [string]: boolean }): boolean
	local count = 0
	for key in next, value do
		if type(key) ~= "string" or rawget(fields, key) ~= true then
			return false
		end
		count += 1
	end
	local expected = 0
	for _ in next, fields do
		expected += 1
	end
	return count == expected
end

local function isDenseArray(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local count = 0
	local maximum = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 then
			return false
		end
		count += 1
		maximum = math.max(maximum, key)
	end
	return count == maximum
end

function MatchLoadoutProtocol.validate(
	value: unknown,
	configuration: ConfigTypes.CoreConfiguration
): Result.Result<Snapshot, LoadoutError>
	if not ConfigurationValidator.isValidatedConfiguration(configuration) then
		return failure("UNAUTHENTICATED_CONFIGURATION", "configuration")
	end
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return failure("INVALID_SNAPSHOT", "loadout")
	end
	local record = value :: { [any]: unknown }
	if not hasExactFields(record, ROOT_FIELDS) then
		return failure("INVALID_SNAPSHOT", "loadout")
	end
	local userId = rawget(record, "userId")
	local revision = rawget(record, "revision")
	local rawSlots = rawget(record, "slots")
	local settingsResult = SettingsProtocol.SettingsSchema:validate(rawget(record, "settings"))
	if
		type(userId) ~= "number"
		or not Validation.isSafeInteger(userId)
		or userId < 1
		or type(revision) ~= "number"
		or not Validation.isSafeInteger(revision)
		or revision < 1
		or not isDenseArray(rawSlots)
		or not settingsResult.ok
	then
		return failure("INVALID_SNAPSHOT", "loadout")
	end
	local source = rawSlots :: { [any]: unknown }
	local slotCount = #source
	if slotCount < MIN_SLOTS or slotCount > MAX_SLOTS then
		return failure("INVALID_SNAPSHOT", "loadout.slots")
	end

	local seenUnits: { [string]: boolean } = {}
	local seenTowers: { [string]: boolean } = {}
	local slots: { Slot } = table.create(slotCount)
	for index = 1, slotCount do
		local rawSlot = source[index]
		if
			type(rawSlot) ~= "table"
			or getmetatable(rawSlot :: any) ~= nil
			or not hasExactFields(rawSlot :: { [any]: unknown }, SLOT_FIELDS)
		then
			return failure("INVALID_SNAPSHOT", `loadout.slots[{index}]`)
		end
		local slotRecord = rawSlot :: { [any]: unknown }
		local slot = rawget(slotRecord, "slot")
		local unitResult = Ids.validateUnitId(rawget(slotRecord, "unitId"))
		local towerResult = Ids.validateTowerId(rawget(slotRecord, "towerId"))
		if slot ~= index or not unitResult.ok or not towerResult.ok then
			return failure("INVALID_SNAPSHOT", `loadout.slots[{index}]`)
		end
		local unitId = unitResult.value
		local towerId = towerResult.value
		if configuration.towers.byId[towerId] == nil then
			return failure("UNKNOWN_TOWER", `loadout.slots[{index}].towerId`)
		end
		if seenUnits[unitId] then
			return failure("DUPLICATE_UNIT", `loadout.slots[{index}].unitId`)
		end
		if seenTowers[towerId] then
			return failure("DUPLICATE_TOWER", `loadout.slots[{index}].towerId`)
		end
		seenUnits[unitId] = true
		seenTowers[towerId] = true
		slots[index] = table.freeze({
			slot = index,
			unitId = unitId,
			towerId = towerId,
		})
	end

	return Result.ok(table.freeze({
		userId = userId :: number,
		revision = revision :: number,
		slots = table.freeze(slots),
		settings = settingsResult.value :: SettingsProtocol.Settings,
	}))
end

return table.freeze(MatchLoadoutProtocol)
