--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TowerSchema = require(ReplicatedStorage.Shared.config.TowerSchema)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Settings = {
	version: number,
	masterVolume: number,
	musicVolume: number,
	sfxVolume: number,
	uiVolume: number,
	cameraShakeIntensity: number,
	damageNumbersEnabled: boolean,
	enemyHealthBarsEnabled: boolean,
	otherPlayerEffectsEnabled: boolean,
	lowDetailEnabled: boolean,
	towerRangeEnabled: boolean,
	uiScale: number,
	reducedMotionEnabled: boolean,
}

export type UnitRecord = {
	unitId: Ids.UnitId,
	towerId: Ids.TowerId,
	favorite: boolean,
	locked: boolean,
	acquiredAt: number,
	acquisitionSequence: number,
}

export type BannerPityRecord = {
	bannerId: Ids.BannerId,
	bannerVersion: number,
	count: number,
}

export type TutorialState = {
	firstJoin: boolean,
	tutorialCompleted: boolean,
	tutorialStep: number,
}

export type Statistics = {
	matchesPlayed: number,
	victories: number,
	defeats: number,
	towersAcquired: number,
	chestsOpened: number,
}

export type MigrationMetadata = {
	createdAt: number,
	lastMigratedAt: number,
	migratedFromVersion: number,
	migrationCount: number,
}

export type ReceiptResult = {
	resultCode: string,
	goldBalance: number,
	unitIds: { Ids.UnitId },
	towerIds: { Ids.TowerId },
	newFlags: { boolean },
	pityCount: number,
}

export type TransactionReceipt = {
	transactionId: Ids.TransactionId,
	kind: string,
	fingerprint: string,
	committedRevision: number,
	createdAt: number,
	result: ReceiptResult,
}

export type Profile = {
	schemaVersion: number,
	revision: number,
	gold: number,
	units: { [Ids.UnitId]: UnitRecord },
	equippedUnitIds: { Ids.UnitId },
	bannerPity: { [Ids.BannerId]: BannerPityRecord },
	settings: Settings,
	tutorial: TutorialState,
	stats: Statistics,
	migration: MigrationMetadata,
	receipts: { TransactionReceipt },
}

export type ErrorCode =
	"INVALID_TOWER_CATALOG"
	| "INVALID_PROFILE"
	| "INVALID_FIELD"
	| "INVALID_REFERENCE"
	| "INVALID_LOADOUT"
	| "CAPACITY_EXCEEDED"
	| "NO_ATTACKING_TOWER"
	| "INVALID_RECEIPT_RESULT"
	| "NO_STARTER_TOWER"

export type ProfileError = {
	code: ErrorCode,
	path: string,
	message: string,
}

local CURRENT_VERSION = 3
local SETTINGS_VERSION = 2
local STARTER_GOLD = 2_000
local MAX_GOLD = 1_000_000_000_000
-- A full client-safe inventory snapshot must fit the shared 512-node payload
-- budget without pagination. Sixty-four unique unit records leave bounded room
-- for copy-count and equipped-slot views.
local MAX_UNITS = 64
local MAX_EQUIPPED_UNITS = 5
local MAX_BANNER_PITY_RECORDS = 32
local MAX_PITY_COUNT = 1_000_000
local MAX_STATISTIC = 1_000_000_000_000
local MAX_TUTORIAL_STEP = 20
local MAX_RECEIPTS = 64
local MAX_RECEIPT_OUTCOMES = 10
local MAX_RECEIPT_KIND_BYTES = 48
local MAX_FINGERPRINT_BYTES = 160
local MAX_RESULT_CODE_BYTES = 48

local PROFILE_FIELDS = table.freeze({
	schemaVersion = true,
	revision = true,
	gold = true,
	units = true,
	equippedUnitIds = true,
	bannerPity = true,
	settings = true,
	tutorial = true,
	stats = true,
	migration = true,
	receipts = true,
})

local UNIT_FIELDS = table.freeze({
	unitId = true,
	towerId = true,
	favorite = true,
	locked = true,
	acquiredAt = true,
	acquisitionSequence = true,
})

local PITY_FIELDS = table.freeze({
	bannerId = true,
	bannerVersion = true,
	count = true,
})

local SETTINGS_FIELDS = table.freeze({
	version = true,
	masterVolume = true,
	musicVolume = true,
	sfxVolume = true,
	uiVolume = true,
	cameraShakeIntensity = true,
	damageNumbersEnabled = true,
	enemyHealthBarsEnabled = true,
	otherPlayerEffectsEnabled = true,
	lowDetailEnabled = true,
	towerRangeEnabled = true,
	uiScale = true,
	reducedMotionEnabled = true,
})

local TUTORIAL_FIELDS = table.freeze({
	firstJoin = true,
	tutorialCompleted = true,
	tutorialStep = true,
})

local STAT_FIELDS = table.freeze({
	matchesPlayed = true,
	victories = true,
	defeats = true,
	towersAcquired = true,
	chestsOpened = true,
})

local MIGRATION_FIELDS = table.freeze({
	createdAt = true,
	lastMigratedAt = true,
	migratedFromVersion = true,
	migrationCount = true,
})

local RECEIPT_FIELDS = table.freeze({
	transactionId = true,
	kind = true,
	fingerprint = true,
	committedRevision = true,
	createdAt = true,
	result = true,
})

local RECEIPT_RESULT_FIELDS = table.freeze({
	resultCode = true,
	goldBalance = true,
	unitIds = true,
	towerIds = true,
	newFlags = true,
	pityCount = true,
})

local ProfileSchema = {
	CURRENT_VERSION = CURRENT_VERSION,
	SETTINGS_VERSION = SETTINGS_VERSION,
	STARTER_GOLD = STARTER_GOLD,
	MAX_GOLD = MAX_GOLD,
	MAX_UNITS = MAX_UNITS,
	MAX_EQUIPPED_UNITS = MAX_EQUIPPED_UNITS,
	MAX_BANNER_PITY_RECORDS = MAX_BANNER_PITY_RECORDS,
	MAX_PITY_COUNT = MAX_PITY_COUNT,
	MAX_STATISTIC = MAX_STATISTIC,
	MAX_TUTORIAL_STEP = MAX_TUTORIAL_STEP,
	MAX_RECEIPTS = MAX_RECEIPTS,
	MAX_RECEIPT_OUTCOMES = MAX_RECEIPT_OUTCOMES,
}

local function failure(code: ErrorCode, path: string, message: string): Result.Failure<ProfileError>
	return Result.err(table.freeze({
		code = code,
		path = path,
		message = message,
	}))
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

local function freezeDeep(value: any): any
	if type(value) ~= "table" or table.isfrozen(value) then
		return value
	end
	for key, child in next, value do
		if type(key) == "table" then
			freezeDeep(key)
		end
		freezeDeep(child)
	end
	return table.freeze(value)
end

local function isPlainTable(value: unknown): boolean
	return type(value) == "table" and getmetatable(value :: any) == nil
end

local function exactRecord(value: unknown, fields: { [string]: boolean }): { [string]: unknown }?
	if not isPlainTable(value) then
		return nil
	end
	local seen = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "string" or fields[key] ~= true then
			return nil
		end
		seen += 1
	end
	local required = 0
	for field in fields do
		required += 1
		if rawget(value :: any, field) == nil then
			return nil
		end
	end
	return if seen == required then value :: { [string]: unknown } else nil
end

local function integerIn(value: unknown, minimum: number, maximum: number): number?
	if type(value) == "number" and Validation.isSafeInteger(value) and value >= minimum and value <= maximum then
		return value
	end
	return nil
end

local function numberIn(value: unknown, minimum: number, maximum: number): number?
	if type(value) == "number" and Validation.isFiniteNumber(value) and value >= minimum and value <= maximum then
		return value
	end
	return nil
end

local function boundedToken(value: unknown, maximumBytes: number): string?
	if type(value) ~= "string" or #value < 1 or #value > maximumBytes then
		return nil
	end
	for index = 1, #value do
		local byte = string.byte(value, index)
		if byte == nil or byte < 33 or byte > 126 then
			return nil
		end
	end
	return value
end

local function denseArray(value: unknown, maximum: number, minimum: number): { unknown }?
	if not isPlainTable(value) then
		return nil
	end
	local count = 0
	local maximumIndex = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > maximum then
			return nil
		end
		count += 1
		maximumIndex = math.max(maximumIndex, key)
	end
	if count < minimum or count > maximum or maximumIndex ~= count then
		return nil
	end
	local output: { unknown } = table.create(count)
	for index = 1, count do
		output[index] = rawget(value :: any, index)
	end
	return output
end

local function attacks(definition: ConfigTypes.TowerDefinition): boolean
	for _, level in definition.levels do
		if level.attack ~= nil then
			return true
		end
	end
	return false
end

local function validateSettings(value: unknown): Settings?
	local record = exactRecord(value, SETTINGS_FIELDS)
	if record == nil or integerIn(record.version, SETTINGS_VERSION, SETTINGS_VERSION) == nil then
		return nil
	end
	local masterVolume = numberIn(record.masterVolume, 0, 1)
	local musicVolume = numberIn(record.musicVolume, 0, 1)
	local sfxVolume = numberIn(record.sfxVolume, 0, 1)
	local uiVolume = numberIn(record.uiVolume, 0, 1)
	local cameraShakeIntensity = numberIn(record.cameraShakeIntensity, 0, 1)
	local uiScale = numberIn(record.uiScale, 0.75, 1.25)
	if
		masterVolume == nil
		or musicVolume == nil
		or sfxVolume == nil
		or uiVolume == nil
		or cameraShakeIntensity == nil
		or uiScale == nil
		or type(record.damageNumbersEnabled) ~= "boolean"
		or type(record.enemyHealthBarsEnabled) ~= "boolean"
		or type(record.otherPlayerEffectsEnabled) ~= "boolean"
		or type(record.lowDetailEnabled) ~= "boolean"
		or type(record.towerRangeEnabled) ~= "boolean"
		or type(record.reducedMotionEnabled) ~= "boolean"
	then
		return nil
	end
	return {
		version = SETTINGS_VERSION,
		masterVolume = masterVolume,
		musicVolume = musicVolume,
		sfxVolume = sfxVolume,
		uiVolume = uiVolume,
		cameraShakeIntensity = cameraShakeIntensity,
		damageNumbersEnabled = record.damageNumbersEnabled :: boolean,
		enemyHealthBarsEnabled = record.enemyHealthBarsEnabled :: boolean,
		otherPlayerEffectsEnabled = record.otherPlayerEffectsEnabled :: boolean,
		lowDetailEnabled = record.lowDetailEnabled :: boolean,
		towerRangeEnabled = record.towerRangeEnabled :: boolean,
		uiScale = uiScale,
		reducedMotionEnabled = record.reducedMotionEnabled :: boolean,
	}
end

local function validateReceiptResultInternal(value: unknown): ReceiptResult?
	local record = exactRecord(value, RECEIPT_RESULT_FIELDS)
	if record == nil then
		return nil
	end
	local resultCode = boundedToken(record.resultCode, MAX_RESULT_CODE_BYTES)
	local goldBalance = integerIn(record.goldBalance, 0, MAX_GOLD)
	local pityCount = integerIn(record.pityCount, 0, MAX_PITY_COUNT)
	local rawUnitIds = denseArray(record.unitIds, MAX_RECEIPT_OUTCOMES, 0)
	local rawTowerIds = denseArray(record.towerIds, MAX_RECEIPT_OUTCOMES, 0)
	local rawNewFlags = denseArray(record.newFlags, MAX_RECEIPT_OUTCOMES, 0)
	if
		resultCode == nil
		or goldBalance == nil
		or pityCount == nil
		or rawUnitIds == nil
		or rawTowerIds == nil
		or rawNewFlags == nil
		or #rawUnitIds ~= #rawTowerIds
		or #rawUnitIds ~= #rawNewFlags
	then
		return nil
	end
	local unitIds: { Ids.UnitId } = table.create(#rawUnitIds)
	local towerIds: { Ids.TowerId } = table.create(#rawTowerIds)
	local newFlags: { boolean } = table.create(#rawNewFlags)
	for index = 1, #rawUnitIds do
		local unitResult = Ids.validateUnitId(rawUnitIds[index])
		local towerResult = Ids.validateTowerId(rawTowerIds[index])
		if not unitResult.ok or not towerResult.ok or type(rawNewFlags[index]) ~= "boolean" then
			return nil
		end
		unitIds[index] = unitResult.value
		towerIds[index] = towerResult.value
		newFlags[index] = rawNewFlags[index] :: boolean
	end
	return {
		resultCode = resultCode,
		goldBalance = goldBalance,
		unitIds = unitIds,
		towerIds = towerIds,
		newFlags = newFlags,
		pityCount = pityCount,
	}
end

function ProfileSchema.validateReceiptResult(value: unknown): Result.Result<ReceiptResult, ProfileError>
	local canonical = validateReceiptResultInternal(value)
	if canonical == nil then
		return failure("INVALID_RECEIPT_RESULT", "result", "Transaction result is malformed or exceeds its bounds")
	end
	return Result.ok(freezeDeep(canonical) :: ReceiptResult)
end

function ProfileSchema.defaultSettings(): Settings
	return freezeDeep({
		version = SETTINGS_VERSION,
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
	}) :: Settings
end

function ProfileSchema.defaultStatistics(towersAcquired: number?): Statistics
	return freezeDeep({
		matchesPlayed = 0,
		victories = 0,
		defeats = 0,
		towersAcquired = towersAcquired or 0,
		chestsOpened = 0,
	}) :: Statistics
end

function ProfileSchema.clone<T>(value: T): T
	return copy(value)
end

function ProfileSchema.validate(value: unknown, towers: ConfigTypes.TowerCatalog): Result.Result<Profile, ProfileError>
	if not TowerSchema.isValidatedCatalog(towers) then
		return failure("INVALID_TOWER_CATALOG", "towers", "Profile validation requires an authenticated tower catalog")
	end
	local record = exactRecord(value, PROFILE_FIELDS)
	if record == nil then
		return failure("INVALID_PROFILE", "profile", "Profile must be one exact plain record")
	end
	local schemaVersion = integerIn(record.schemaVersion, CURRENT_VERSION, CURRENT_VERSION)
	local revision = integerIn(record.revision, 1, Validation.MAX_SAFE_INTEGER)
	local gold = integerIn(record.gold, 0, MAX_GOLD)
	if schemaVersion == nil or revision == nil or gold == nil then
		return failure("INVALID_FIELD", "profile", "Profile version, revision, or Gold is invalid")
	end

	if not isPlainTable(record.units) then
		return failure("INVALID_FIELD", "profile.units", "Units must be a bounded UnitId dictionary")
	end
	local unitKeys: { string } = {}
	for key in next, record.units :: { [any]: unknown } do
		if type(key) ~= "string" then
			return failure("INVALID_FIELD", "profile.units", "Unit dictionary keys must be UnitIds")
		end
		table.insert(unitKeys, key)
		if #unitKeys > MAX_UNITS then
			return failure("CAPACITY_EXCEEDED", "profile.units", "Unit capacity is exceeded")
		end
	end
	table.sort(unitKeys)
	if #unitKeys == 0 then
		return failure("INVALID_LOADOUT", "profile.units", "A profile must own at least one tower")
	end
	local units: { [Ids.UnitId]: UnitRecord } = {}
	local sequences: { [number]: boolean } = {}
	for _, key in unitKeys do
		local keyResult = Ids.validateUnitId(key)
		local unit = exactRecord(rawget(record.units :: any, key), UNIT_FIELDS)
		if not keyResult.ok or unit == nil then
			return failure("INVALID_FIELD", `profile.units.{key}`, "Unit record is malformed")
		end
		local unitIdResult = Ids.validateUnitId(unit.unitId)
		local towerIdResult = Ids.validateTowerId(unit.towerId)
		local acquiredAt = integerIn(unit.acquiredAt, 0, Validation.MAX_SAFE_INTEGER)
		local sequence = integerIn(unit.acquisitionSequence, 1, Validation.MAX_SAFE_INTEGER)
		if
			not unitIdResult.ok
			or unitIdResult.value ~= keyResult.value
			or not towerIdResult.ok
			or towers.byId[towerIdResult.value] == nil
			or type(unit.favorite) ~= "boolean"
			or type(unit.locked) ~= "boolean"
			or acquiredAt == nil
			or sequence == nil
			or sequences[sequence]
		then
			return failure("INVALID_REFERENCE", `profile.units.{key}`, "Unit identity or tower reference is invalid")
		end
		sequences[sequence] = true
		units[keyResult.value] = {
			unitId = unitIdResult.value,
			towerId = towerIdResult.value,
			favorite = unit.favorite :: boolean,
			locked = unit.locked :: boolean,
			acquiredAt = acquiredAt,
			acquisitionSequence = sequence,
		}
	end

	local rawEquipped = denseArray(record.equippedUnitIds, MAX_EQUIPPED_UNITS, 1)
	if rawEquipped == nil then
		return failure("INVALID_LOADOUT", "profile.equippedUnitIds", "Loadout must contain one through five units")
	end
	local equippedUnitIds: { Ids.UnitId } = table.create(#rawEquipped)
	local equippedUnits: { [Ids.UnitId]: boolean } = {}
	local equippedTowers: { [Ids.TowerId]: boolean } = {}
	local hasAttacker = false
	for index, rawUnitId in rawEquipped do
		local unitIdResult = Ids.validateUnitId(rawUnitId)
		local unit = if unitIdResult.ok then units[unitIdResult.value] else nil
		if unit == nil or equippedUnits[unit.unitId] or equippedTowers[unit.towerId] then
			return failure(
				"INVALID_LOADOUT",
				`profile.equippedUnitIds[{index}]`,
				"Equipped unit is invalid or duplicated"
			)
		end
		equippedUnits[unit.unitId] = true
		equippedTowers[unit.towerId] = true
		hasAttacker = hasAttacker or attacks(towers.byId[unit.towerId])
		equippedUnitIds[index] = unit.unitId
	end
	if not hasAttacker then
		return failure("NO_ATTACKING_TOWER", "profile.equippedUnitIds", "Loadout must contain an attacking tower")
	end

	if not isPlainTable(record.bannerPity) then
		return failure("INVALID_FIELD", "profile.bannerPity", "Banner pity must be a bounded dictionary")
	end
	local pityKeys: { string } = {}
	for key in next, record.bannerPity :: { [any]: unknown } do
		if type(key) ~= "string" then
			return failure("INVALID_FIELD", "profile.bannerPity", "Pity keys must be BannerIds")
		end
		table.insert(pityKeys, key)
		if #pityKeys > MAX_BANNER_PITY_RECORDS then
			return failure("CAPACITY_EXCEEDED", "profile.bannerPity", "Pity-record capacity is exceeded")
		end
	end
	table.sort(pityKeys)
	local bannerPity: { [Ids.BannerId]: BannerPityRecord } = {}
	for _, key in pityKeys do
		local keyResult = Ids.validateBannerId(key)
		local pity = exactRecord(rawget(record.bannerPity :: any, key), PITY_FIELDS)
		if not keyResult.ok or pity == nil then
			return failure("INVALID_FIELD", `profile.bannerPity.{key}`, "Pity record is malformed")
		end
		local bannerIdResult = Ids.validateBannerId(pity.bannerId)
		local bannerVersion = integerIn(pity.bannerVersion, 1, Validation.MAX_SAFE_INTEGER)
		local count = integerIn(pity.count, 0, MAX_PITY_COUNT)
		if not bannerIdResult.ok or bannerIdResult.value ~= keyResult.value or bannerVersion == nil or count == nil then
			return failure("INVALID_REFERENCE", `profile.bannerPity.{key}`, "Pity identity or value is invalid")
		end
		bannerPity[keyResult.value] = {
			bannerId = bannerIdResult.value,
			bannerVersion = bannerVersion,
			count = count,
		}
	end

	local settings = validateSettings(record.settings)
	if settings == nil then
		return failure("INVALID_FIELD", "profile.settings", "Persistent settings are malformed")
	end
	local tutorialRecord = exactRecord(record.tutorial, TUTORIAL_FIELDS)
	local tutorialStep = if tutorialRecord == nil
		then nil
		else integerIn(tutorialRecord.tutorialStep, 0, MAX_TUTORIAL_STEP)
	if
		tutorialRecord == nil
		or type(tutorialRecord.firstJoin) ~= "boolean"
		or type(tutorialRecord.tutorialCompleted) ~= "boolean"
		or tutorialStep == nil
	then
		return failure("INVALID_FIELD", "profile.tutorial", "Tutorial state is malformed")
	end
	local tutorial: TutorialState = {
		firstJoin = tutorialRecord.firstJoin :: boolean,
		tutorialCompleted = tutorialRecord.tutorialCompleted :: boolean,
		tutorialStep = tutorialStep,
	}

	local statsRecord = exactRecord(record.stats, STAT_FIELDS)
	if statsRecord == nil then
		return failure("INVALID_FIELD", "profile.stats", "Statistics are malformed")
	end
	local stats: Statistics = {
		matchesPlayed = integerIn(statsRecord.matchesPlayed, 0, MAX_STATISTIC) or -1,
		victories = integerIn(statsRecord.victories, 0, MAX_STATISTIC) or -1,
		defeats = integerIn(statsRecord.defeats, 0, MAX_STATISTIC) or -1,
		towersAcquired = integerIn(statsRecord.towersAcquired, 0, MAX_STATISTIC) or -1,
		chestsOpened = integerIn(statsRecord.chestsOpened, 0, MAX_STATISTIC) or -1,
	}
	for _, field in { "matchesPlayed", "victories", "defeats", "towersAcquired", "chestsOpened" } do
		if (stats :: any)[field] < 0 then
			return failure("INVALID_FIELD", `profile.stats.{field}`, "Statistic is outside its bound")
		end
	end

	local migrationRecord = exactRecord(record.migration, MIGRATION_FIELDS)
	if migrationRecord == nil then
		return failure("INVALID_FIELD", "profile.migration", "Migration metadata is malformed")
	end
	local migration: MigrationMetadata = {
		createdAt = integerIn(migrationRecord.createdAt, 0, Validation.MAX_SAFE_INTEGER) or -1,
		lastMigratedAt = integerIn(migrationRecord.lastMigratedAt, 0, Validation.MAX_SAFE_INTEGER) or -1,
		migratedFromVersion = integerIn(migrationRecord.migratedFromVersion, 0, CURRENT_VERSION) or -1,
		migrationCount = integerIn(migrationRecord.migrationCount, 0, 1_000) or -1,
	}
	if
		migration.createdAt < 0
		or migration.lastMigratedAt < migration.createdAt
		or migration.migratedFromVersion < 0
		or migration.migrationCount < 0
	then
		return failure("INVALID_FIELD", "profile.migration", "Migration metadata values are invalid")
	end

	local rawReceipts = denseArray(record.receipts, MAX_RECEIPTS, 0)
	if rawReceipts == nil then
		return failure("INVALID_FIELD", "profile.receipts", "Receipt ring is malformed")
	end
	local receipts: { TransactionReceipt } = table.create(#rawReceipts)
	local receiptIds: { [Ids.TransactionId]: boolean } = {}
	local previousRevision = 0
	for index, rawReceipt in rawReceipts do
		local receipt = exactRecord(rawReceipt, RECEIPT_FIELDS)
		if receipt == nil then
			return failure("INVALID_FIELD", `profile.receipts[{index}]`, "Transaction receipt is malformed")
		end
		local transactionId = Ids.validateTransactionId(receipt.transactionId)
		local kind = boundedToken(receipt.kind, MAX_RECEIPT_KIND_BYTES)
		local fingerprint = boundedToken(receipt.fingerprint, MAX_FINGERPRINT_BYTES)
		local committedRevision = integerIn(receipt.committedRevision, 1, revision)
		local createdAt = integerIn(receipt.createdAt, 0, Validation.MAX_SAFE_INTEGER)
		local receiptResult = validateReceiptResultInternal(receipt.result)
		if
			not transactionId.ok
			or receiptIds[transactionId.value]
			or kind == nil
			or fingerprint == nil
			or committedRevision == nil
			or committedRevision <= previousRevision
			or createdAt == nil
			or receiptResult == nil
		then
			return failure("INVALID_FIELD", `profile.receipts[{index}]`, "Transaction receipt fields are invalid")
		end
		receiptIds[transactionId.value] = true
		previousRevision = committedRevision
		receipts[index] = {
			transactionId = transactionId.value,
			kind = kind,
			fingerprint = fingerprint,
			committedRevision = committedRevision,
			createdAt = createdAt,
			result = receiptResult,
		}
	end

	local profile: Profile = {
		schemaVersion = schemaVersion,
		revision = revision,
		gold = gold,
		units = units,
		equippedUnitIds = equippedUnitIds,
		bannerPity = bannerPity,
		settings = settings,
		tutorial = tutorial,
		stats = stats,
		migration = migration,
		receipts = receipts,
	}
	return Result.ok(freezeDeep(profile) :: Profile)
end

function ProfileSchema.createStarter(
	towers: ConfigTypes.TowerCatalog,
	createdAtValue: unknown
): Result.Result<Profile, ProfileError>
	if not TowerSchema.isValidatedCatalog(towers) then
		return failure("INVALID_TOWER_CATALOG", "towers", "Starter creation requires an authenticated tower catalog")
	end
	local createdAt = integerIn(createdAtValue, 0, Validation.MAX_SAFE_INTEGER)
	if createdAt == nil then
		return failure("INVALID_FIELD", "createdAt", "Starter timestamp must be a nonnegative safe integer")
	end
	local starterTower: ConfigTypes.TowerDefinition? = nil
	for _, definition in towers.ordered do
		if attacks(definition) then
			starterTower = definition
			break
		end
	end
	if starterTower == nil then
		return failure("NO_STARTER_TOWER", "towers", "Tower catalog has no usable attacking starter")
	end
	local unitIdResult = Ids.makeUnitId("starter-1")
	if not unitIdResult.ok then
		return failure("INVALID_REFERENCE", "profile.units", "Starter UnitId construction failed")
	end
	local unitId = unitIdResult.value
	local rawProfile = {
		schemaVersion = CURRENT_VERSION,
		revision = 1,
		gold = STARTER_GOLD,
		units = {
			[unitId] = {
				unitId = unitId,
				towerId = starterTower.id,
				favorite = false,
				locked = false,
				acquiredAt = createdAt,
				acquisitionSequence = 1,
			},
		},
		equippedUnitIds = { unitId },
		bannerPity = {},
		settings = ProfileSchema.defaultSettings(),
		tutorial = {
			firstJoin = true,
			tutorialCompleted = false,
			tutorialStep = 0,
		},
		stats = ProfileSchema.defaultStatistics(1),
		migration = {
			createdAt = createdAt,
			lastMigratedAt = createdAt,
			migratedFromVersion = 0,
			migrationCount = 0,
		},
		receipts = {},
	}
	return ProfileSchema.validate(rawProfile, towers)
end

return table.freeze(ProfileSchema)
