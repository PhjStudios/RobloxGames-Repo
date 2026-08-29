--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local AssetSchema = require(ReplicatedStorage.Shared.config.AssetSchema)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local TowerSchema = require(ReplicatedStorage.Shared.config.TowerSchema)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type StoreState = "Prepared" | "Active" | "Faulted" | "Cleaned"

export type OccupiedSlotSnapshot = {
	kind: "Occupied",
	slot: number,
	towerId: Ids.TowerId,
	unitId: Ids.UnitId,
}

export type EmptySlotSnapshot = {
	kind: "Empty",
	slot: number,
}

export type SlotSnapshot = OccupiedSlotSnapshot | EmptySlotSnapshot

export type LoadoutSnapshot = {
	matchId: Ids.MatchId,
	userId: number,
	revision: number,
	slots: { SlotSnapshot },
}

export type CreationCapability = {}
export type PreparedCapability = {}

export type PreparedCapabilityBinding = {
	matchId: Ids.MatchId,
	towerEpoch: number,
	userId: number,
	loadoutRevision: number,
	slot: number,
	towerId: Ids.TowerId,
	unitId: Ids.UnitId,
	definition: ConfigTypes.TowerDefinition,
}

export type PreparedCapabilityInspector = (token: unknown) -> unknown

export type StoreMetrics = {
	state: StoreState,
	loadoutCount: number,
	unitIdCount: number,
	occupiedSlotCount: number,
	emptySlotCount: number,
	nextLoadoutRevision: number,
	lastParticipantRevision: number,
	capabilityGeneration: number,
	issuedCapabilityCount: number,
	reservedCapabilityCount: number,
	retainsIdentity: boolean,
	retainsConfiguration: boolean,
	retainsDefinitions: boolean,
	retainsParticipantSnapshot: boolean,
	retainsInspector: boolean,
	faulted: boolean,
	cleaned: boolean,
}

export type Operation =
	"new"
	| "synchronizeParticipants"
	| "activate"
	| "getLoadout"
	| "issueCreationCapability"
	| "prepareCreationCapability"
	| "inspectPreparedCapability"
	| "commitPreparedCapability"
	| "abortPreparedCapability"
	| "getPreparedCapabilityInspector"
	| "fault"
	| "getMetrics"
	| "cleanup"

export type ErrorCode =
	"INVALID_MATCH_ID"
	| "INVALID_EPOCH"
	| "UNAUTHENTICATED_CONFIGURATION"
	| "INVALID_DEFINITIONS"
	| "INVALID_TEST_OPTIONS"
	| "INVALID_PARTICIPANT_SNAPSHOT"
	| "WRONG_MATCH"
	| "STALE_PARTICIPANT_SNAPSHOT"
	| "INVALID_USER_ID"
	| "INVALID_SLOT"
	| "EMPTY_SLOT"
	| "NOT_FOUND"
	| "CAPACITY_EXCEEDED"
	| "REVISION_EXHAUSTED"
	| "UNIT_ID_EXHAUSTED"
	| "UNIT_ID_FAILED"
	| "UNIT_ID_COLLISION"
	| "CAPABILITY_ACTIVE"
	| "CAPABILITY_EXHAUSTED"
	| "INVALID_CAPABILITY"
	| "INVALID_TOKEN"
	| "COUNTER_FAULT"
	| "CALLBACK_FAILED"
	| "WRONG_STATE"
	| "REENTRANT"
	| "FAULTED"
	| "CLEANED"

export type StoreError = {
	code: ErrorCode,
	operation: Operation,
}

type InternalOccupiedSlot = {
	slot: number,
	towerId: Ids.TowerId,
	unitId: Ids.UnitId,
	definition: ConfigTypes.TowerDefinition,
}

type LoadoutRecord = {
	userId: number,
	revision: number,
	slots: { InternalOccupiedSlot },
}

type UnitOwner = {
	userId: number,
	slot: number,
}

type CapabilityState = "Issued" | "Reserved"

type CapabilityData = {
	owner: StoreData,
	generation: number,
	state: CapabilityState,
	userId: number,
	loadoutRevision: number,
	slot: number,
	towerId: Ids.TowerId,
	unitId: Ids.UnitId,
	definition: ConfigTypes.TowerDefinition,
	preparedToken: PreparedCapability?,
}

type PreparedCapabilityData = {
	owner: StoreData,
	source: CreationCapability,
	inspected: boolean,
	binding: PreparedCapabilityBinding,
}

type MakeUnitId = (towerEpoch: number, userId: number, slot: number) -> unknown

type StoreData = {
	state: StoreState,
	matchId: Ids.MatchId?,
	towerEpoch: number?,
	configuration: ConfigTypes.CoreConfiguration?,
	definitions: { ConfigTypes.TowerDefinition }?,
	loadoutsByUserId: { [number]: LoadoutRecord },
	unitOwners: { [Ids.UnitId]: UnitOwner },
	loadoutCount: number,
	unitIdCount: number,
	nextLoadoutRevision: number,
	lastParticipantRevision: number,
	lastParticipantSnapshot: MatchProtocol.MatchSnapshot?,
	lastParticipantSource: unknown?,
	capabilitiesByUserSlot: { [number]: { [number]: CreationCapability } },
	currentPreparedCapability: PreparedCapability?,
	capabilityGeneration: number,
	issuedCapabilityCount: number,
	reservedCapabilityCount: number,
	inspector: PreparedCapabilityInspector?,
	makeUnitId: MakeUnitId?,
	maxLoadouts: number,
	maxUnitIds: number,
	maxCapabilityGeneration: number,
	busy: boolean,
	reentryViolation: boolean,
	cleanupRequested: boolean,
}

type TestOptions = {
	makeUnitId: MakeUnitId?,
	maxLoadouts: number?,
	maxUnitIds: number?,
	maxCapabilityGeneration: number?,
	nextLoadoutRevision: number?,
	nextCapabilityGeneration: number?,
}

local MAX_LOADOUTS = 4
local SLOT_COUNT = 5
local OCCUPIED_SLOT_COUNT = 3
local MAX_UNIT_IDS = MAX_LOADOUTS * OCCUPIED_SLOT_COUNT
local MAX_CAPABILITY_GENERATION = 4_096
local MAX_TOWER_EPOCH = 4_096
local ASSIGNMENT_SUCCESS: Result.Success<boolean> = Result.ok(true)

local EXPECTED_TOWER_IDS: { Ids.TowerId } = table.freeze({
	"tower:phase12-single",
	"tower:phase12-splash",
	"tower:phase12-support",
})

local TEST_OPTION_FIELDS = table.freeze({
	makeUnitId = true,
	maxCapabilityGeneration = true,
	maxLoadouts = true,
	maxUnitIds = true,
	nextCapabilityGeneration = true,
	nextLoadoutRevision = true,
})

local StoreMethods = {}
StoreMethods.__index = StoreMethods

export type Store = typeof(setmetatable({} :: {}, StoreMethods))
export type TestConstructor = (
	configurationValue: unknown,
	matchIdValue: unknown,
	towerEpochValue: unknown,
	definitionsValue: unknown,
	optionsValue: unknown
) -> Result.Result<Store, StoreError>

local STORE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: StoreData }
local CAPABILITY_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: CapabilityData }
local PREPARED_CAPABILITY_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: PreparedCapabilityData }

local TemporaryLoadoutStore = {
	MAX_CAPABILITY_GENERATION = MAX_CAPABILITY_GENERATION,
	MAX_LOADOUTS = MAX_LOADOUTS,
	MAX_TOWER_EPOCH = MAX_TOWER_EPOCH,
	MAX_UNIT_IDS = MAX_UNIT_IDS,
	OCCUPIED_SLOT_COUNT = OCCUPIED_SLOT_COUNT,
	SLOT_COUNT = SLOT_COUNT,
	newForTests = nil :: TestConstructor?,
}

local function makeError(code: ErrorCode, operation: Operation): StoreError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<StoreError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): StoreData
	if type(value) ~= "table" then
		error("[ATD_TEMPORARY_LOADOUT_STORE][code=INVALID_CONTEXT]", 0)
	end
	local data = STORE_DATA[value :: any]
	if data == nil then
		error("[ATD_TEMPORARY_LOADOUT_STORE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function isNonzeroSafeInteger(value: unknown): boolean
	return type(value) == "number" and value ~= 0 and Validation.isSafeInteger(value)
end

local function isSlot(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value) and value >= 1 and value <= SLOT_COUNT
end

local function isDenseArrayOfLength(value: unknown, expectedLength: number): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or rawlen(value :: any) ~= expectedLength then
		return false
	end
	local fieldCount = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > expectedLength then
			return false
		end
		fieldCount += 1
	end
	return fieldCount == expectedLength
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, resultValue = coroutine.resume(thread, ...)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, resultValue
end

local function defaultMakeUnitId(towerEpoch: number, userId: number, slot: number): unknown
	local magnitude = math.abs(userId)
	local magnitudeText = string.format("%.0f", magnitude)
	local sign = if userId > 0 then "p" else "n"
	local body = `p12-e{towerEpoch}-{sign}{magnitudeText}-s{slot}`
	local made = Ids.makeUnitId(body)
	if not made.ok then
		return nil
	end
	local validated = Ids.validateUnitId(made.value)
	if not validated.ok or validated.value ~= `unit:{body}` then
		return nil
	end
	return validated.value
end

local function definitionsAreCanonical(
	configuration: ConfigTypes.CoreConfiguration,
	definitionsValue: unknown
): { ConfigTypes.TowerDefinition }?
	if
		not isDenseArrayOfLength(definitionsValue, OCCUPIED_SLOT_COUNT)
		or #configuration.towers.ordered ~= OCCUPIED_SLOT_COUNT
	then
		return nil
	end

	local definitions: { ConfigTypes.TowerDefinition } = table.create(OCCUPIED_SLOT_COUNT)
	local seenTowerIds: { [Ids.TowerId]: boolean } = {}
	for index = 1, OCCUPIED_SLOT_COUNT do
		local definitionValue = (definitionsValue :: { any })[index]
		if type(definitionValue) ~= "table" or not table.isfrozen(definitionValue) then
			return nil
		end
		local definition = definitionValue :: ConfigTypes.TowerDefinition
		local expectedTowerId = EXPECTED_TOWER_IDS[index]
		if
			definition.id ~= expectedTowerId
			or seenTowerIds[definition.id]
			or configuration.towers.byId[definition.id] ~= definition
			or configuration.towers.ordered[index] ~= definition
		then
			return nil
		end
		seenTowerIds[definition.id] = true

		local modelAsset = configuration.assets.byKey[definition.modelAssetKey]
		if modelAsset == nil or modelAsset.kind ~= "TowerModel" then
			return nil
		end
		local retainsAsset = false
		for _, candidate in configuration.assets.ordered do
			if candidate == modelAsset then
				retainsAsset = true
				break
			end
		end
		if not retainsAsset then
			return nil
		end
		definitions[index] = definition
	end
	return table.freeze(definitions)
end

local function participantSourceIsDetached(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return false
	end
	local participants = (value :: any).participants
	if type(participants) ~= "table" or getmetatable(participants) ~= nil or not table.isfrozen(participants) then
		return false
	end
	for _, participant in participants do
		if type(participant) ~= "table" or getmetatable(participant) ~= nil or not table.isfrozen(participant) then
			return false
		end
	end
	return true
end

local function revokeAllCapabilities(data: StoreData)
	for _, bySlot in data.capabilitiesByUserSlot do
		for _, capability in bySlot do
			local capabilityData = CAPABILITY_DATA[capability]
			if capabilityData ~= nil then
				local preparedToken = capabilityData.preparedToken
				if preparedToken ~= nil then
					PREPARED_CAPABILITY_DATA[preparedToken] = nil
				end
				CAPABILITY_DATA[capability] = nil
			end
		end
		table.clear(bySlot)
	end
	table.clear(data.capabilitiesByUserSlot)
	local currentPrepared = data.currentPreparedCapability
	if currentPrepared ~= nil then
		PREPARED_CAPABILITY_DATA[currentPrepared] = nil
	end
	data.currentPreparedCapability = nil
	data.issuedCapabilityCount = 0
	data.reservedCapabilityCount = 0
end

local function clearData(data: StoreData)
	revokeAllCapabilities(data)
	for _, record in data.loadoutsByUserId do
		table.clear(record.slots)
	end
	table.clear(data.loadoutsByUserId)
	table.clear(data.unitOwners)
	data.matchId = nil
	data.towerEpoch = nil
	data.configuration = nil
	data.definitions = nil
	data.loadoutCount = 0
	data.unitIdCount = 0
	data.nextLoadoutRevision = 1
	data.lastParticipantRevision = 0
	data.lastParticipantSnapshot = nil
	data.lastParticipantSource = nil
	data.capabilityGeneration = 0
	data.inspector = nil
	data.makeUnitId = nil
	data.busy = false
	data.reentryViolation = false
	data.cleanupRequested = false
	data.state = "Cleaned"
end

local function finishOperation(data: StoreData): boolean
	data.busy = false
	if data.cleanupRequested then
		clearData(data)
		return true
	end
	return false
end

local function faultData(data: StoreData): boolean
	revokeAllCapabilities(data)
	data.state = "Faulted"
	return finishOperation(data)
end

local function enterOperation(data: StoreData, operation: Operation, allowPrepared: boolean): StoreError?
	if data.state == "Cleaned" then
		return makeError("CLEANED", operation)
	end
	if data.busy then
		data.reentryViolation = true
		return makeError("REENTRANT", operation)
	end
	if data.state == "Faulted" then
		return makeError("FAULTED", operation)
	end
	if not allowPrepared and data.state ~= "Active" then
		return makeError("WRONG_STATE", operation)
	end
	data.busy = true
	data.reentryViolation = false
	return nil
end

local function snapshotLoadout(data: StoreData, record: LoadoutRecord): LoadoutSnapshot
	local slots: { SlotSnapshot } = table.create(SLOT_COUNT)
	for index = 1, OCCUPIED_SLOT_COUNT do
		local occupied = record.slots[index]
		slots[index] = table.freeze({
			kind = "Occupied",
			slot = occupied.slot,
			towerId = occupied.towerId,
			unitId = occupied.unitId,
		})
	end
	for index = OCCUPIED_SLOT_COUNT + 1, SLOT_COUNT do
		slots[index] = table.freeze({
			kind = "Empty",
			slot = index,
		})
	end
	table.freeze(slots)
	return table.freeze({
		matchId = data.matchId :: Ids.MatchId,
		userId = record.userId,
		revision = record.revision,
		slots = slots,
	})
end

local function currentSlotMatches(data: StoreData, capabilityData: CapabilityData): boolean
	local record = data.loadoutsByUserId[capabilityData.userId]
	if record == nil or record.revision ~= capabilityData.loadoutRevision then
		return false
	end
	local slot = record.slots[capabilityData.slot]
	return slot ~= nil
		and slot.slot == capabilityData.slot
		and slot.towerId == capabilityData.towerId
		and slot.unitId == capabilityData.unitId
		and slot.definition == capabilityData.definition
end

local function consumePreparedCapability(
	data: StoreData,
	preparedToken: PreparedCapability,
	preparedData: PreparedCapabilityData
): boolean
	local capability = preparedData.source
	local capabilityData = CAPABILITY_DATA[capability]
	if
		capabilityData == nil
		or capabilityData.owner ~= data
		or capabilityData.state ~= "Reserved"
		or capabilityData.preparedToken ~= preparedToken
		or data.currentPreparedCapability ~= preparedToken
		or data.reservedCapabilityCount ~= 1
		or data.issuedCapabilityCount < 0
	then
		return false
	end
	local bySlot = data.capabilitiesByUserSlot[capabilityData.userId]
	if bySlot == nil or bySlot[capabilityData.slot] ~= capability then
		return false
	end
	bySlot[capabilityData.slot] = nil
	if next(bySlot) == nil then
		data.capabilitiesByUserSlot[capabilityData.userId] = nil
	end
	CAPABILITY_DATA[capability] = nil
	PREPARED_CAPABILITY_DATA[preparedToken] = nil
	data.currentPreparedCapability = nil
	data.reservedCapabilityCount = 0
	return true
end

local function inspectPreparedCapability(data: StoreData, tokenValue: unknown): unknown
	local operation: Operation = "inspectPreparedCapability"
	local operationError = enterOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if type(tokenValue) ~= "table" then
		finishOperation(data)
		return failure("INVALID_CAPABILITY", operation)
	end
	local preparedData = PREPARED_CAPABILITY_DATA[tokenValue :: any]
	if
		preparedData == nil
		or preparedData.owner ~= data
		or preparedData.inspected
		or data.currentPreparedCapability ~= tokenValue
	then
		finishOperation(data)
		return failure("INVALID_CAPABILITY", operation)
	end
	local capabilityData = CAPABILITY_DATA[preparedData.source]
	if
		capabilityData == nil
		or capabilityData.owner ~= data
		or capabilityData.state ~= "Reserved"
		or capabilityData.preparedToken ~= tokenValue
		or not currentSlotMatches(data, capabilityData)
	then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "COUNTER_FAULT", operation)
	end
	preparedData.inspected = true
	local binding = preparedData.binding
	finishOperation(data)
	return Result.ok(binding)
end

local function construct(
	configurationValue: unknown,
	matchIdValue: unknown,
	towerEpochValue: unknown,
	definitionsValue: unknown,
	makeUnitId: MakeUnitId,
	maxLoadouts: number,
	maxUnitIds: number,
	maxCapabilityGeneration: number,
	nextLoadoutRevision: number,
	nextCapabilityGeneration: number
): Result.Result<Store, StoreError>
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if not matchIdResult.ok then
		return failure("INVALID_MATCH_ID", "new")
	end
	if
		type(towerEpochValue) ~= "number"
		or not Validation.isSafeInteger(towerEpochValue)
		or towerEpochValue < 1
		or towerEpochValue > MAX_TOWER_EPOCH
	then
		return failure("INVALID_EPOCH", "new")
	end
	if
		not ConfigurationValidator.isValidatedConfiguration(configurationValue)
		or not AssetSchema.isValidatedManifest((configurationValue :: any).assets)
		or not TowerSchema.isValidatedCatalog((configurationValue :: any).towers)
	then
		return failure("UNAUTHENTICATED_CONFIGURATION", "new")
	end
	local configuration = configurationValue :: ConfigTypes.CoreConfiguration
	local definitions = definitionsAreCanonical(configuration, definitionsValue)
	if definitions == nil then
		return failure("INVALID_DEFINITIONS", "new")
	end

	local store = setmetatable({}, StoreMethods) :: Store
	table.freeze(store)
	local data: StoreData = {
		state = "Prepared",
		matchId = matchIdResult.value,
		towerEpoch = towerEpochValue,
		configuration = configuration,
		definitions = definitions,
		loadoutsByUserId = {},
		unitOwners = {},
		loadoutCount = 0,
		unitIdCount = 0,
		nextLoadoutRevision = nextLoadoutRevision,
		lastParticipantRevision = 0,
		lastParticipantSnapshot = nil,
		lastParticipantSource = nil,
		capabilitiesByUserSlot = {},
		currentPreparedCapability = nil,
		capabilityGeneration = nextCapabilityGeneration,
		issuedCapabilityCount = 0,
		reservedCapabilityCount = 0,
		inspector = nil,
		makeUnitId = makeUnitId,
		maxLoadouts = maxLoadouts,
		maxUnitIds = maxUnitIds,
		maxCapabilityGeneration = maxCapabilityGeneration,
		busy = false,
		reentryViolation = false,
		cleanupRequested = false,
	}
	local inspector: PreparedCapabilityInspector = function(token: unknown): unknown
		return inspectPreparedCapability(data, token)
	end
	data.inspector = inspector
	STORE_DATA[store] = data
	return Result.ok(store)
end

function StoreMethods.synchronizeParticipants(self: Store, snapshotValue: unknown): Result.Result<boolean, StoreError>
	local operation: Operation = "synchronizeParticipants"
	local data = requireData(self)
	local operationError = enterOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if data.state ~= "Prepared" and data.state ~= "Active" then
		finishOperation(data)
		return failure("WRONG_STATE", operation)
	end
	if snapshotValue == data.lastParticipantSource and data.lastParticipantRevision > 0 then
		finishOperation(data)
		return Result.ok(false)
	end
	if not participantSourceIsDetached(snapshotValue) then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "INVALID_PARTICIPANT_SNAPSHOT", operation)
	end
	local validation = MatchProtocol.validateMatchSnapshot(snapshotValue)
	if not validation.ok then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "INVALID_PARTICIPANT_SNAPSHOT", operation)
	end
	local snapshot = validation.value
	local matchId = data.matchId
	if matchId == nil or snapshot.matchId ~= matchId then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "WRONG_MATCH", operation)
	end
	if snapshot.revision <= data.lastParticipantRevision then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "STALE_PARTICIPANT_SNAPSHOT", operation)
	end

	local presentUsers: { [number]: boolean } = {}
	local newUsers: { number } = {}
	for _, participant in snapshot.participants do
		presentUsers[participant.userId] = true
		if participant.state == "Active" and data.loadoutsByUserId[participant.userId] == nil then
			table.insert(newUsers, participant.userId)
		end
	end
	for userId in data.loadoutsByUserId do
		if presentUsers[userId] ~= true then
			local cleaned = faultData(data)
			return failure(if cleaned then "CLEANED" else "INVALID_PARTICIPANT_SNAPSHOT", operation)
		end
	end
	if data.loadoutCount + #newUsers > data.maxLoadouts then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "CAPACITY_EXCEEDED", operation)
	end
	local addedUnitIdCount = #newUsers * OCCUPIED_SLOT_COUNT
	if data.unitIdCount + addedUnitIdCount > data.maxUnitIds then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "UNIT_ID_EXHAUSTED", operation)
	end
	if #newUsers > 0 and data.nextLoadoutRevision > Validation.MAX_SAFE_INTEGER - #newUsers then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "REVISION_EXHAUSTED", operation)
	end

	local definitions = data.definitions
	local makeUnitId = data.makeUnitId
	local towerEpoch = data.towerEpoch
	if definitions == nil or makeUnitId == nil or towerEpoch == nil then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "COUNTER_FAULT", operation)
	end
	local stagedRecords: { LoadoutRecord } = table.create(#newUsers)
	local stagedUnitIds: { [Ids.UnitId]: boolean } = {}
	local nextRevision = data.nextLoadoutRevision
	for _, userId in newUsers do
		local slots: { InternalOccupiedSlot } = table.create(OCCUPIED_SLOT_COUNT)
		for slotIndex = 1, OCCUPIED_SLOT_COUNT do
			local called, unitIdValue = callNonYielding(makeUnitId, towerEpoch, userId, slotIndex)
			if data.cleanupRequested then
				finishOperation(data)
				return failure("CLEANED", operation)
			end
			if not called or data.reentryViolation then
				local cleaned = faultData(data)
				return failure(if cleaned then "CLEANED" else "CALLBACK_FAILED", operation)
			end
			local unitIdResult = Ids.validateUnitId(unitIdValue)
			if not unitIdResult.ok then
				local cleaned = faultData(data)
				return failure(if cleaned then "CLEANED" else "UNIT_ID_FAILED", operation)
			end
			local unitId = unitIdResult.value
			if data.unitOwners[unitId] ~= nil or stagedUnitIds[unitId] then
				local cleaned = faultData(data)
				return failure(if cleaned then "CLEANED" else "UNIT_ID_COLLISION", operation)
			end
			stagedUnitIds[unitId] = true
			local definition = definitions[slotIndex]
			slots[slotIndex] = {
				slot = slotIndex,
				towerId = definition.id,
				unitId = unitId,
				definition = definition,
			}
		end
		table.insert(stagedRecords, {
			userId = userId,
			revision = nextRevision,
			slots = slots,
		})
		nextRevision += 1
	end

	for _, record in stagedRecords do
		data.loadoutsByUserId[record.userId] = record
		data.loadoutCount += 1
		for _, slot in record.slots do
			data.unitOwners[slot.unitId] = {
				userId = record.userId,
				slot = slot.slot,
			}
			data.unitIdCount += 1
		end
	end
	data.nextLoadoutRevision = nextRevision
	data.lastParticipantRevision = snapshot.revision
	data.lastParticipantSnapshot = snapshot
	data.lastParticipantSource = snapshotValue
	finishOperation(data)
	return Result.ok(#stagedRecords > 0)
end

function StoreMethods.activate(self: Store): Result.Result<boolean, StoreError>
	local operation: Operation = "activate"
	local data = requireData(self)
	local operationError = enterOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if data.state ~= "Prepared" or data.lastParticipantRevision < 1 then
		finishOperation(data)
		return failure("WRONG_STATE", operation)
	end
	data.state = "Active"
	finishOperation(data)
	return ASSIGNMENT_SUCCESS
end

function StoreMethods.getLoadout(self: Store, userIdValue: unknown): Result.Result<LoadoutSnapshot, StoreError>
	local operation: Operation = "getLoadout"
	local data = requireData(self)
	local operationError = enterOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if not isNonzeroSafeInteger(userIdValue) then
		finishOperation(data)
		return failure("INVALID_USER_ID", operation)
	end
	local record = data.loadoutsByUserId[userIdValue :: number]
	if record == nil then
		finishOperation(data)
		return failure("NOT_FOUND", operation)
	end
	local snapshot = snapshotLoadout(data, record)
	finishOperation(data)
	return Result.ok(snapshot)
end

function StoreMethods.issueCreationCapability(
	self: Store,
	userIdValue: unknown,
	slotValue: unknown
): Result.Result<CreationCapability, StoreError>
	local operation: Operation = "issueCreationCapability"
	local data = requireData(self)
	local operationError = enterOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if not isNonzeroSafeInteger(userIdValue) then
		finishOperation(data)
		return failure("INVALID_USER_ID", operation)
	end
	if not isSlot(slotValue) then
		finishOperation(data)
		return failure("INVALID_SLOT", operation)
	end
	local userId = userIdValue :: number
	local slotIndex = slotValue :: number
	local record = data.loadoutsByUserId[userId]
	if record == nil then
		finishOperation(data)
		return failure("NOT_FOUND", operation)
	end
	local slot = record.slots[slotIndex]
	if slot == nil then
		finishOperation(data)
		return failure("EMPTY_SLOT", operation)
	end
	local bySlot = data.capabilitiesByUserSlot[userId]
	if bySlot ~= nil and bySlot[slotIndex] ~= nil then
		finishOperation(data)
		return failure("CAPABILITY_ACTIVE", operation)
	end
	if data.capabilityGeneration >= data.maxCapabilityGeneration then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "CAPABILITY_EXHAUSTED", operation)
	end
	if data.issuedCapabilityCount < 0 or data.reservedCapabilityCount < 0 then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "COUNTER_FAULT", operation)
	end

	local capability = table.freeze({}) :: CreationCapability
	data.capabilityGeneration += 1
	CAPABILITY_DATA[capability] = {
		owner = data,
		generation = data.capabilityGeneration,
		state = "Issued",
		userId = userId,
		loadoutRevision = record.revision,
		slot = slotIndex,
		towerId = slot.towerId,
		unitId = slot.unitId,
		definition = slot.definition,
		preparedToken = nil,
	}
	if bySlot == nil then
		bySlot = {}
		data.capabilitiesByUserSlot[userId] = bySlot
	end
	bySlot[slotIndex] = capability
	data.issuedCapabilityCount += 1
	finishOperation(data)
	return Result.ok(capability)
end

function StoreMethods.prepareCreationCapability(
	self: Store,
	capabilityValue: unknown
): Result.Result<PreparedCapability, StoreError>
	local operation: Operation = "prepareCreationCapability"
	local data = requireData(self)
	local operationError = enterOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if type(capabilityValue) ~= "table" then
		finishOperation(data)
		return failure("INVALID_CAPABILITY", operation)
	end
	local capability = capabilityValue :: CreationCapability
	local capabilityData = CAPABILITY_DATA[capability]
	if
		capabilityData == nil
		or capabilityData.owner ~= data
		or capabilityData.state ~= "Issued"
		or capabilityData.preparedToken ~= nil
		or not currentSlotMatches(data, capabilityData)
	then
		finishOperation(data)
		return failure("INVALID_CAPABILITY", operation)
	end
	if data.currentPreparedCapability ~= nil or data.reservedCapabilityCount ~= 0 then
		finishOperation(data)
		return failure("CAPABILITY_ACTIVE", operation)
	end
	if data.issuedCapabilityCount < 1 then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "COUNTER_FAULT", operation)
	end

	local preparedToken = table.freeze({}) :: PreparedCapability
	local matchId = data.matchId
	local towerEpoch = data.towerEpoch
	if matchId == nil or towerEpoch == nil then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "COUNTER_FAULT", operation)
	end
	local binding: PreparedCapabilityBinding = table.freeze({
		matchId = matchId,
		towerEpoch = towerEpoch,
		userId = capabilityData.userId,
		loadoutRevision = capabilityData.loadoutRevision,
		slot = capabilityData.slot,
		towerId = capabilityData.towerId,
		unitId = capabilityData.unitId,
		definition = capabilityData.definition,
	})
	capabilityData.state = "Reserved"
	capabilityData.preparedToken = preparedToken
	PREPARED_CAPABILITY_DATA[preparedToken] = {
		owner = data,
		source = capability,
		inspected = false,
		binding = binding,
	}
	data.currentPreparedCapability = preparedToken
	data.issuedCapabilityCount -= 1
	data.reservedCapabilityCount = 1
	finishOperation(data)
	return Result.ok(preparedToken)
end

function StoreMethods.commitPreparedCapability(
	self: Store,
	preparedTokenValue: unknown
): Result.Result<boolean, StoreError>
	local operation: Operation = "commitPreparedCapability"
	local data = requireData(self)
	local operationError = enterOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if type(preparedTokenValue) ~= "table" then
		finishOperation(data)
		return failure("INVALID_TOKEN", operation)
	end
	local preparedToken = preparedTokenValue :: PreparedCapability
	local preparedData = PREPARED_CAPABILITY_DATA[preparedToken]
	if preparedData == nil or preparedData.owner ~= data or not preparedData.inspected then
		finishOperation(data)
		return failure("INVALID_TOKEN", operation)
	end
	if not consumePreparedCapability(data, preparedToken, preparedData) then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "COUNTER_FAULT", operation)
	end
	finishOperation(data)
	return ASSIGNMENT_SUCCESS
end

function StoreMethods.abortPreparedCapability(
	self: Store,
	preparedTokenValue: unknown
): Result.Result<boolean, StoreError>
	local operation: Operation = "abortPreparedCapability"
	local data = requireData(self)
	local operationError = enterOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if type(preparedTokenValue) ~= "table" then
		finishOperation(data)
		return failure("INVALID_TOKEN", operation)
	end
	local preparedToken = preparedTokenValue :: PreparedCapability
	local preparedData = PREPARED_CAPABILITY_DATA[preparedToken]
	if preparedData == nil or preparedData.owner ~= data then
		finishOperation(data)
		return failure("INVALID_TOKEN", operation)
	end
	if not consumePreparedCapability(data, preparedToken, preparedData) then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "COUNTER_FAULT", operation)
	end
	finishOperation(data)
	return Result.ok(true)
end

function StoreMethods.getPreparedCapabilityInspector(
	self: Store
): Result.Result<PreparedCapabilityInspector, StoreError>
	local operation: Operation = "getPreparedCapabilityInspector"
	local data = requireData(self)
	local operationError = enterOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local inspector = data.inspector
	if inspector == nil then
		local cleaned = faultData(data)
		return failure(if cleaned then "CLEANED" else "COUNTER_FAULT", operation)
	end
	finishOperation(data)
	return Result.ok(inspector)
end

function StoreMethods.fault(self: Store): Result.Result<boolean, StoreError>
	local operation: Operation = "fault"
	local data = requireData(self)
	local operationError = enterOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	faultData(data)
	return Result.ok(true)
end

function StoreMethods.getMetrics(self: Store): StoreMetrics
	local data = requireData(self)
	return table.freeze({
		state = data.state,
		loadoutCount = data.loadoutCount,
		unitIdCount = data.unitIdCount,
		occupiedSlotCount = data.unitIdCount,
		emptySlotCount = data.loadoutCount * (SLOT_COUNT - OCCUPIED_SLOT_COUNT),
		nextLoadoutRevision = data.nextLoadoutRevision,
		lastParticipantRevision = data.lastParticipantRevision,
		capabilityGeneration = data.capabilityGeneration,
		issuedCapabilityCount = data.issuedCapabilityCount,
		reservedCapabilityCount = data.reservedCapabilityCount,
		retainsIdentity = data.matchId ~= nil and data.towerEpoch ~= nil,
		retainsConfiguration = data.configuration ~= nil,
		retainsDefinitions = data.definitions ~= nil,
		retainsParticipantSnapshot = data.lastParticipantSnapshot ~= nil,
		retainsInspector = data.inspector ~= nil,
		faulted = data.state == "Faulted",
		cleaned = data.state == "Cleaned",
	})
end

function StoreMethods.cleanup(self: Store): Result.Result<boolean, StoreError>
	local data = requireData(self)
	if data.state == "Cleaned" then
		return Result.ok(false)
	end
	if data.busy then
		data.cleanupRequested = true
		return Result.ok(false)
	end
	data.busy = true
	clearData(data)
	return Result.ok(true)
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "TemporaryLoadoutStore" then
		return false
	end
	local productionServerTowers = script.Parent
	if
		productionServerTowers == nil
		or not productionServerTowers:IsA("Folder")
		or productionServerTowers.Name ~= "ProductionServerTowers"
	then
		return false
	end
	local automatedTests = productionServerTowers.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	if automatedTests.Parent ~= ServerStorage then
		return false
	end
	return ServerScriptService:FindFirstChild("Server") == nil
end

function TemporaryLoadoutStore.new(
	configurationValue: unknown,
	matchIdValue: unknown,
	towerEpochValue: unknown,
	definitionsValue: unknown
): Result.Result<Store, StoreError>
	return construct(
		configurationValue,
		matchIdValue,
		towerEpochValue,
		definitionsValue,
		defaultMakeUnitId,
		MAX_LOADOUTS,
		MAX_UNIT_IDS,
		MAX_CAPABILITY_GENERATION,
		1,
		0
	)
end

if testModuleIdentityIsExact() then
	TemporaryLoadoutStore.newForTests = function(
		configurationValue: unknown,
		matchIdValue: unknown,
		towerEpochValue: unknown,
		definitionsValue: unknown,
		optionsValue: unknown
	): Result.Result<Store, StoreError>
		if type(optionsValue) ~= "table" or getmetatable(optionsValue :: any) ~= nil then
			return failure("INVALID_TEST_OPTIONS", "new")
		end
		for key in next, optionsValue :: { [any]: unknown } do
			if type(key) ~= "string" or TEST_OPTION_FIELDS[key] ~= true then
				return failure("INVALID_TEST_OPTIONS", "new")
			end
		end
		local options = optionsValue :: TestOptions
		local makeUnitId = options.makeUnitId or defaultMakeUnitId
		local maxLoadouts = options.maxLoadouts or MAX_LOADOUTS
		local maxUnitIds = options.maxUnitIds or MAX_UNIT_IDS
		local maxCapabilityGeneration = options.maxCapabilityGeneration or MAX_CAPABILITY_GENERATION
		local nextLoadoutRevision = options.nextLoadoutRevision or 1
		local nextCapabilityGeneration = options.nextCapabilityGeneration or 0
		if
			type(makeUnitId) ~= "function"
			or not Validation.isSafeInteger(maxLoadouts)
			or maxLoadouts < 1
			or maxLoadouts > MAX_LOADOUTS
			or not Validation.isSafeInteger(maxUnitIds)
			or maxUnitIds < 1
			or maxUnitIds > MAX_UNIT_IDS
			or not Validation.isSafeInteger(maxCapabilityGeneration)
			or maxCapabilityGeneration < 1
			or maxCapabilityGeneration > MAX_CAPABILITY_GENERATION
			or not Validation.isSafeInteger(nextLoadoutRevision)
			or nextLoadoutRevision < 1
			or not Validation.isSafeInteger(nextCapabilityGeneration)
			or nextCapabilityGeneration < 0
			or nextCapabilityGeneration > maxCapabilityGeneration
		then
			return failure("INVALID_TEST_OPTIONS", "new")
		end
		return construct(
			configurationValue,
			matchIdValue,
			towerEpochValue,
			definitionsValue,
			makeUnitId,
			maxLoadouts,
			maxUnitIds,
			maxCapabilityGeneration,
			nextLoadoutRevision,
			nextCapabilityGeneration
		)
	end
end

table.freeze(StoreMethods)
return table.freeze(TemporaryLoadoutStore)
