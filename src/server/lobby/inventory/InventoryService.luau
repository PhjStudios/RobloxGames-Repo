--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local InventoryProtocol = require(ReplicatedStorage.Shared.inventory.InventoryProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type ProfileOwner = {
	getState: (self: ProfileOwner, userId: number) -> unknown,
	read: (self: ProfileOwner, userId: number) -> unknown,
	transact: (
		self: ProfileOwner,
		userId: number,
		transactionId: string,
		expectedRevision: number,
		kind: string,
		fingerprint: string,
		callback: (profile: any) -> unknown
	) -> unknown,
}

export type Operation = "new" | "getSnapshot" | "equip" | "unequip" | "favorite" | "lock"
export type ErrorCode =
	"INVALID_DEPENDENCIES"
	| "INVALID_USER_ID"
	| "INVALID_INTENT"
	| "NOT_READY"
	| "PROFILE_INVALID"
	| "UNIT_NOT_FOUND"
	| "TOWER_NOT_FOUND"
	| "DUPLICATE_TOWER"
	| "INVALID_SLOT"
	| "LOADOUT_FULL"
	| "ZERO_ATTACKING_TOWERS"
	| "STALE_REVISION"
	| "TRANSACTION_CONFLICT"
	| "REVISION_EXHAUSTED"
	| "CALLBACK_FAILED"
	| "UNAVAILABLE"

export type ServiceError = {
	code: ErrorCode,
	operation: Operation,
}

type ProfileUnit = {
	unitId: string,
	towerId: string,
	favorite: boolean,
	locked: boolean,
}

type ServiceData = {
	profileOwner: ProfileOwner,
	configuration: ConfigTypes.CoreConfiguration,
}

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local InventoryService = {}

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<ServiceError>
	return Result.err(table.freeze({
		code = code,
		operation = operation,
	}))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_INVENTORY_SERVICE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and value > 0 and Validation.isSafeInteger(value :: number)
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function ownerErrorCode(value: unknown): ErrorCode
	local code = if type(value) == "table"
		then (rawget(value :: any, "reason") or rawget(value :: any, "code"))
		else value
	if code == "NOT_READY" or code == "PROFILE_NOT_READY" then
		return "NOT_READY"
	elseif code == "STALE_REVISION" or code == "STALE" then
		return "STALE_REVISION"
	elseif code == "RECEIPT_CONFLICT" or code == "TRANSACTION_CONFLICT" then
		return "TRANSACTION_CONFLICT"
	elseif code == "REVISION_EXHAUSTED" then
		return "REVISION_EXHAUSTED"
	elseif code == "PROFILE_INVALID" then
		return "PROFILE_INVALID"
	elseif code == "UNIT_NOT_FOUND" then
		return "UNIT_NOT_FOUND"
	elseif code == "TOWER_NOT_FOUND" then
		return "TOWER_NOT_FOUND"
	elseif code == "DUPLICATE_TOWER" then
		return "DUPLICATE_TOWER"
	elseif code == "INVALID_SLOT" then
		return "INVALID_SLOT"
	elseif code == "LOADOUT_FULL" then
		return "LOADOUT_FULL"
	elseif code == "ZERO_ATTACKING_TOWERS" then
		return "ZERO_ATTACKING_TOWERS"
	end
	return "UNAVAILABLE"
end

local function ownerReady(data: ServiceData, userId: number): boolean
	local called, state = callNonYielding(data.profileOwner.getState, data.profileOwner, userId)
	return called and state == "Ready"
end

local function isAttacking(definition: ConfigTypes.TowerDefinition): boolean
	for _, level in definition.levels do
		if level.attack ~= nil then
			return true
		end
	end
	return false
end

local function denseEquipped(value: unknown): { string }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local raw = value :: { [any]: unknown }
	local count = 0
	local maximum = 0
	for key in next, raw do
		if
			type(key) ~= "number"
			or not Validation.isSafeInteger(key :: number)
			or (key :: number) < 1
			or (key :: number) > InventoryProtocol.MAX_LOADOUT_SLOTS
		then
			return nil
		end
		count += 1
		maximum = math.max(maximum, key :: number)
	end
	if count < 1 or maximum ~= count then
		return nil
	end
	local output: { string } = table.create(count)
	for index = 1, count do
		local unitId = rawget(raw, index)
		local validated = Ids.validateUnitId(unitId)
		if not validated.ok then
			return nil
		end
		output[index] = validated.value
	end
	return output
end

local function profileUnits(
	data: ServiceData,
	profile: any
): ({ [string]: ProfileUnit }?, { string }?, { [string]: number }?)
	if type(profile) ~= "table" or getmetatable(profile) ~= nil then
		return nil, nil, nil
	end
	local revision = rawget(profile, "revision")
	local unitsValue = rawget(profile, "units")
	if
		type(revision) ~= "number"
		or not Validation.isSafeInteger(revision)
		or revision < 1
		or type(unitsValue) ~= "table"
		or getmetatable(unitsValue) ~= nil
	then
		return nil, nil, nil
	end
	local units: { [string]: ProfileUnit } = {}
	local unitIds: { string } = {}
	local copyCounts: { [string]: number } = {}
	local count = 0
	for key, rawUnit in next, unitsValue :: { [any]: unknown } do
		count += 1
		if
			count > InventoryProtocol.MAX_UNITS
			or type(key) ~= "string"
			or type(rawUnit) ~= "table"
			or getmetatable(rawUnit :: any) ~= nil
		then
			return nil, nil, nil
		end
		local record = rawUnit :: { [any]: unknown }
		local unitIdResult = Ids.validateUnitId(rawget(record, "unitId"))
		local towerIdResult = Ids.validateTowerId(rawget(record, "towerId"))
		local favorite = rawget(record, "favorite")
		local locked = rawget(record, "locked")
		if
			not unitIdResult.ok
			or unitIdResult.value ~= key
			or not towerIdResult.ok
			or type(favorite) ~= "boolean"
			or type(locked) ~= "boolean"
			or data.configuration.towers.byId[towerIdResult.value] == nil
		then
			return nil, nil, nil
		end
		units[key] = {
			unitId = key,
			towerId = towerIdResult.value,
			favorite = favorite :: boolean,
			locked = locked :: boolean,
		}
		table.insert(unitIds, key)
		copyCounts[towerIdResult.value] = (copyCounts[towerIdResult.value] or 0) + 1
	end
	if count < 1 then
		return nil, nil, nil
	end
	table.sort(unitIds)
	return units, unitIds, copyCounts
end

local function snapshotFromProfile(
	data: ServiceData,
	profile: any,
	revisionOverride: number?
): Result.Result<InventoryProtocol.Snapshot, ServiceError>
	local units, orderedUnitIds, copyCounts = profileUnits(data, profile)
	local equippedIds = denseEquipped(if type(profile) == "table" then rawget(profile, "equippedUnitIds") else nil)
	if units == nil or orderedUnitIds == nil or copyCounts == nil or equippedIds == nil then
		return failure("PROFILE_INVALID", "getSnapshot")
	end
	local equippedByUnit: { [string]: number } = {}
	local equippedTowerIds: { [string]: boolean } = {}
	local equipped: { InventoryProtocol.EquippedSlot } = table.create(#equippedIds)
	local attackingCount = 0
	for slot, unitId in equippedIds do
		local unit = units[unitId]
		if unit == nil or equippedByUnit[unitId] ~= nil or equippedTowerIds[unit.towerId] then
			return failure("PROFILE_INVALID", "getSnapshot")
		end
		equippedByUnit[unitId] = slot
		equippedTowerIds[unit.towerId] = true
		local definition = data.configuration.towers.byId[unit.towerId]
		if definition == nil then
			return failure("PROFILE_INVALID", "getSnapshot")
		end
		if isAttacking(definition) then
			attackingCount += 1
		end
		equipped[slot] = table.freeze({
			slot = slot,
			unitId = unitId,
			towerId = unit.towerId,
		})
	end
	if attackingCount < 1 then
		return failure("ZERO_ATTACKING_TOWERS", "getSnapshot")
	end

	local unitViews: { InventoryProtocol.UnitView } = table.create(#orderedUnitIds)
	for index, unitId in orderedUnitIds do
		local unit = units[unitId]
		unitViews[index] = table.freeze({
			unitId = unit.unitId,
			towerId = unit.towerId,
			favorite = unit.favorite,
			locked = unit.locked,
			equippedSlot = equippedByUnit[unitId],
		})
	end
	local towerIds: { string } = {}
	for towerId in copyCounts do
		table.insert(towerIds, towerId)
	end
	table.sort(towerIds)
	local countViews: { InventoryProtocol.CopyCount } = table.create(#towerIds)
	for index, towerId in towerIds do
		countViews[index] = table.freeze({
			towerId = towerId,
			copies = copyCounts[towerId],
		})
	end
	local revision = revisionOverride or rawget(profile, "revision")
	local snapshot: InventoryProtocol.Snapshot = table.freeze({
		revision = revision,
		units = table.freeze(unitViews),
		copyCounts = table.freeze(countViews),
		equipped = table.freeze(equipped),
	})
	local validated = InventoryProtocol.validateSnapshot(snapshot)
	if not validated.ok then
		return failure("PROFILE_INVALID", "getSnapshot")
	end
	return Result.ok(validated.value)
end

local function transact(
	data: ServiceData,
	userId: number,
	transactionId: string,
	expectedRevision: number,
	kind: InventoryProtocol.MutationKind,
	fingerprint: string,
	operation: Operation,
	callback: (profile: any) -> Result.Result<{ changed: boolean }, ServiceError>
): Result.Result<InventoryProtocol.MutationReceipt, ServiceError>
	if expectedRevision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", operation)
	end
	local called, transaction = callNonYielding(
		data.profileOwner.transact,
		data.profileOwner,
		userId,
		transactionId,
		expectedRevision,
		`Inventory{kind}`,
		fingerprint,
		function(profile: any): unknown
			local outcome = callback(profile)
			if not outcome.ok then
				return Result.err(outcome.error.code)
			end
			local snapshotResult = snapshotFromProfile(data, profile, nil)
			if not snapshotResult.ok then
				return Result.err(snapshotResult.error.code)
			end
			return Result.ok(table.freeze({
				resultCode = if outcome.value.changed then "INVENTORY_CHANGED" else "INVENTORY_UNCHANGED",
				goldBalance = rawget(profile, "gold"),
				unitIds = table.freeze({}),
				towerIds = table.freeze({}),
				newFlags = table.freeze({}),
				pityCount = 0,
			}))
		end
	)
	if not called or type(transaction) ~= "table" then
		return failure("CALLBACK_FAILED", operation)
	end
	local transactionResult = transaction :: any
	if transactionResult.ok ~= true then
		return failure(ownerErrorCode(transactionResult.error), operation)
	end
	local ownerValue = transactionResult.value
	if type(ownerValue) ~= "table" then
		return failure("UNAVAILABLE", operation)
	end
	local ownerResult = rawget(ownerValue, "result")
	local profile = rawget(ownerValue, "profile")
	local profileRevision = rawget(ownerValue, "profileRevision")
	if
		type(ownerResult) ~= "table"
		or (rawget(ownerResult, "resultCode") ~= "INVENTORY_CHANGED" and rawget(ownerResult, "resultCode") ~= "INVENTORY_UNCHANGED")
		or type(profileRevision) ~= "number"
		or not Validation.isSafeInteger(profileRevision)
		or profileRevision < 1
	then
		return failure("UNAVAILABLE", operation)
	end
	local snapshotResult = snapshotFromProfile(data, profile, nil)
	if not snapshotResult.ok or snapshotResult.value.revision ~= profileRevision then
		return failure("PROFILE_INVALID", operation)
	end
	local receiptValue: InventoryProtocol.MutationReceipt = table.freeze({
		transactionId = transactionId,
		kind = kind,
		changed = rawget(ownerResult, "resultCode") == "INVENTORY_CHANGED",
		revision = profileRevision :: number,
		snapshot = snapshotResult.value,
	})
	local receiptResult = InventoryProtocol.validateMutationReceipt(receiptValue)
	if not receiptResult.ok then
		return failure("UNAVAILABLE", operation)
	end
	return Result.ok(receiptResult.value)
end

function Methods.getSnapshot(
	self: Service,
	userIdValue: unknown
): Result.Result<InventoryProtocol.Snapshot, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "getSnapshot")
	end
	local userId = userIdValue :: number
	if not ownerReady(data, userId) then
		return failure("NOT_READY", "getSnapshot")
	end
	local called, readResult = callNonYielding(data.profileOwner.read, data.profileOwner, userId)
	if not called or type(readResult) ~= "table" then
		return failure("UNAVAILABLE", "getSnapshot")
	end
	if (readResult :: any).ok ~= true then
		return failure(ownerErrorCode((readResult :: any).error), "getSnapshot")
	end
	return snapshotFromProfile(data, (readResult :: any).value, nil)
end

function Methods.equip(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<InventoryProtocol.MutationReceipt, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "equip")
	end
	local intentResult = InventoryProtocol.EquipIntentSchema:validate(intentValue)
	if not intentResult.ok then
		return failure("INVALID_INTENT", "equip")
	end
	local intent = intentResult.value :: InventoryProtocol.EquipIntent
	local userId = userIdValue :: number
	if not ownerReady(data, userId) then
		return failure("NOT_READY", "equip")
	end
	return transact(
		data,
		userId,
		intent.transactionId,
		intent.expectedRevision,
		"Equip",
		`equip|{intent.unitId}|{intent.slot}`,
		"equip",
		function(profile)
			local before = snapshotFromProfile(data, profile, nil)
			if not before.ok then
				return failure(before.error.code, "equip")
			end
			local units = rawget(profile, "units") :: { [string]: any }
			local unit = units[intent.unitId]
			if unit == nil then
				return failure("UNIT_NOT_FOUND", "equip")
			end
			local equipped = rawget(profile, "equippedUnitIds") :: { string }
			if intent.slot > #equipped + 1 then
				return failure("INVALID_SLOT", "equip")
			end
			local existingSlot: number? = nil
			for slot, equippedUnitId in equipped do
				local equippedUnit = units[equippedUnitId]
				if equippedUnitId == intent.unitId then
					existingSlot = slot
				elseif equippedUnit ~= nil and equippedUnit.towerId == unit.towerId and slot ~= intent.slot then
					return failure("DUPLICATE_TOWER", "equip")
				end
			end
			if existingSlot == intent.slot then
				return Result.ok({ changed = false })
			end
			if existingSlot ~= nil then
				table.remove(equipped, existingSlot)
			end
			local targetSlot = math.min(intent.slot, #equipped + 1)
			if existingSlot == nil and #equipped >= InventoryProtocol.MAX_LOADOUT_SLOTS and targetSlot > #equipped then
				return failure("LOADOUT_FULL", "equip")
			end
			if existingSlot == nil and targetSlot <= #equipped then
				equipped[targetSlot] = intent.unitId
			else
				table.insert(equipped, targetSlot, intent.unitId)
			end
			return Result.ok({ changed = true })
		end
	)
end

function Methods.unequip(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<InventoryProtocol.MutationReceipt, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "unequip")
	end
	local intentResult = InventoryProtocol.UnitMutationIntentSchema:validate(intentValue)
	if not intentResult.ok then
		return failure("INVALID_INTENT", "unequip")
	end
	local intent = intentResult.value :: InventoryProtocol.UnitMutationIntent
	local userId = userIdValue :: number
	if not ownerReady(data, userId) then
		return failure("NOT_READY", "unequip")
	end
	return transact(
		data,
		userId,
		intent.transactionId,
		intent.expectedRevision,
		"Unequip",
		`unequip|{intent.unitId}`,
		"unequip",
		function(profile)
			local before = snapshotFromProfile(data, profile, nil)
			if not before.ok then
				return failure(before.error.code, "unequip")
			end
			local units = rawget(profile, "units") :: { [string]: any }
			if units[intent.unitId] == nil then
				return failure("UNIT_NOT_FOUND", "unequip")
			end
			local equipped = rawget(profile, "equippedUnitIds") :: { string }
			local found: number? = nil
			for slot, unitId in equipped do
				if unitId == intent.unitId then
					found = slot
					break
				end
			end
			if found == nil then
				return Result.ok({ changed = false })
			end
			if #equipped <= 1 then
				return failure("ZERO_ATTACKING_TOWERS", "unequip")
			end
			table.remove(equipped, found)
			local attacking = false
			for _, unitId in equipped do
				local unit = units[unitId]
				local definition = if unit == nil then nil else data.configuration.towers.byId[unit.towerId]
				attacking = attacking or (definition ~= nil and isAttacking(definition))
			end
			if not attacking then
				table.insert(equipped, found, intent.unitId)
				return failure("ZERO_ATTACKING_TOWERS", "unequip")
			end
			return Result.ok({ changed = true })
		end
	)
end

local function toggle(
	data: ServiceData,
	userIdValue: unknown,
	intentValue: unknown,
	kind: "Favorite" | "Lock",
	operation: "favorite" | "lock"
): Result.Result<InventoryProtocol.MutationReceipt, ServiceError>
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", operation)
	end
	local intentResult = InventoryProtocol.ToggleIntentSchema:validate(intentValue)
	if not intentResult.ok then
		return failure("INVALID_INTENT", operation)
	end
	local intent = intentResult.value :: InventoryProtocol.ToggleIntent
	local userId = userIdValue :: number
	if not ownerReady(data, userId) then
		return failure("NOT_READY", operation)
	end
	local field = if kind == "Favorite" then "favorite" else "locked"
	return transact(
		data,
		userId,
		intent.transactionId,
		intent.expectedRevision,
		kind,
		`{string.lower(kind)}|{intent.unitId}|{if intent.enabled then "1" else "0"}`,
		operation,
		function(profile)
			local before = snapshotFromProfile(data, profile, nil)
			if not before.ok then
				return failure(before.error.code, operation)
			end
			local unit = (rawget(profile, "units") :: { [string]: any })[intent.unitId]
			if unit == nil then
				return failure("UNIT_NOT_FOUND", operation)
			end
			local changed = rawget(unit, field) ~= intent.enabled
			if changed then
				rawset(unit, field, intent.enabled)
			end
			return Result.ok({ changed = changed })
		end
	)
end

function Methods.favorite(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<InventoryProtocol.MutationReceipt, ServiceError>
	return toggle(requireData(self), userIdValue, intentValue, "Favorite", "favorite")
end

function Methods.lock(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<InventoryProtocol.MutationReceipt, ServiceError>
	return toggle(requireData(self), userIdValue, intentValue, "Lock", "lock")
end

function InventoryService.new(
	profileOwnerValue: unknown,
	configurationValue: unknown
): Result.Result<Service, ServiceError>
	if
		type(profileOwnerValue) ~= "table"
		or type((profileOwnerValue :: any).getState) ~= "function"
		or type((profileOwnerValue :: any).read) ~= "function"
		or type((profileOwnerValue :: any).transact) ~= "function"
		or not ConfigurationValidator.isValidatedConfiguration(configurationValue)
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		profileOwner = profileOwnerValue :: ProfileOwner,
		configuration = configurationValue :: ConfigTypes.CoreConfiguration,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(InventoryService)
