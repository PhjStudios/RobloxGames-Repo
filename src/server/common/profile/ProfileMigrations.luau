--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local ProfileSchema = require(script.Parent.ProfileSchema)

export type Outcome = "Created" | "Migrated" | "Current"

export type MigrationResult = {
	profile: ProfileSchema.Profile,
	outcome: Outcome,
	fromVersion: number,
	appliedVersions: { number },
}

export type ErrorCode =
	"INVALID_TIMESTAMP"
	| "MALFORMED_PROFILE"
	| "MISSING_VERSION"
	| "UNSUPPORTED_VERSION"
	| "FUTURE_VERSION"
	| "MIGRATION_FAILED"

export type MigrationError = {
	code: ErrorCode,
	path: string,
	message: string,
}

local MAX_CLONE_DEPTH = 12
local MAX_CLONE_NODES = 4_096

local ProfileMigrations = {
	MAX_CLONE_DEPTH = MAX_CLONE_DEPTH,
	MAX_CLONE_NODES = MAX_CLONE_NODES,
}

local function failure(code: ErrorCode, path: string, message: string): Result.Failure<MigrationError>
	return Result.err(table.freeze({
		code = code,
		path = path,
		message = message,
	}))
end

local function cloneBounded(value: unknown): unknown?
	local seen: { [any]: boolean } = {}
	local nodeCount = 0
	local function visit(current: unknown, depth: number): unknown?
		nodeCount += 1
		if nodeCount > MAX_CLONE_NODES then
			return nil
		end
		if type(current) ~= "table" then
			return current
		end
		if depth > MAX_CLONE_DEPTH or getmetatable(current :: any) ~= nil or seen[current :: any] then
			return nil
		end
		seen[current :: any] = true
		local output = {}
		for key, child in next, current :: { [any]: unknown } do
			local copiedKey = visit(key, depth + 1)
			local copiedChild = visit(child, depth + 1)
			if copiedKey == nil or copiedChild == nil then
				seen[current :: any] = nil
				return nil
			end
			output[copiedKey] = copiedChild
		end
		seen[current :: any] = nil
		return output
	end
	return visit(value, 0)
end

local function countUnits(value: unknown): number?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local count = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "string" then
			return nil
		end
		count += 1
		if count > ProfileSchema.MAX_UNITS then
			return nil
		end
	end
	return count
end

local function migrateOneToTwo(profile: { [any]: any }): boolean
	if profile.stats ~= nil or profile.receipts ~= nil then
		return false
	end
	local unitCount = countUnits(profile.units)
	if unitCount == nil or unitCount < 1 then
		return false
	end
	profile.stats = ProfileSchema.clone(ProfileSchema.defaultStatistics(unitCount))
	profile.receipts = {}
	profile.schemaVersion = 2
	return true
end

local LEGACY_SETTING_FIELDS = table.freeze({
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
})

local function validLegacySettings(settings: unknown): boolean
	if type(settings) ~= "table" or getmetatable(settings :: any) ~= nil then
		return false
	end
	local count = 0
	for key in next, settings :: { [any]: unknown } do
		if type(key) ~= "string" or LEGACY_SETTING_FIELDS[key] ~= true then
			return false
		end
		count += 1
	end
	if count ~= 12 or rawget(settings :: any, "version") ~= 1 then
		return false
	end
	for key in LEGACY_SETTING_FIELDS do
		if rawget(settings :: any, key) == nil then
			return false
		end
	end
	return true
end

local function migrateTwoToThree(profile: { [any]: any }, originalVersion: number, now: number): boolean
	if profile.migration ~= nil or not validLegacySettings(profile.settings) then
		return false
	end
	local settings = profile.settings :: { [any]: any }
	settings.version = ProfileSchema.SETTINGS_VERSION
	settings.reducedMotionEnabled = false
	profile.migration = {
		createdAt = now,
		lastMigratedAt = now,
		migratedFromVersion = originalVersion,
		migrationCount = 3 - originalVersion,
	}
	profile.schemaVersion = 3
	return true
end

local function migrateThreeToFour(profile: { [any]: any }, now: number): boolean
	if profile.firstClears ~= nil or profile.claimedResults ~= nil then
		return false
	end
	local migration = profile.migration
	if
		type(migration) ~= "table"
		or getmetatable(migration) ~= nil
		or type(migration.migrationCount) ~= "number"
		or not Validation.isSafeInteger(migration.migrationCount)
		or migration.migrationCount < 0
	then
		return false
	end
	profile.firstClears = {}
	profile.claimedResults = {}
	migration.lastMigratedAt = now
	migration.migrationCount += 1
	profile.schemaVersion = 4
	return true
end

local function migrateFourToFive(profile: { [any]: any }, now: number): boolean
	if profile.pendingResults ~= nil then
		return false
	end
	local migration = profile.migration
	if
		type(migration) ~= "table"
		or getmetatable(migration) ~= nil
		or type(migration.migrationCount) ~= "number"
		or not Validation.isSafeInteger(migration.migrationCount)
		or migration.migrationCount < 0
	then
		return false
	end
	profile.pendingResults = {}
	migration.lastMigratedAt = now
	migration.migrationCount += 1
	profile.schemaVersion = 5
	return true
end

local LEGACY_TUTORIAL_FIELDS = table.freeze({
	firstJoin = true,
	tutorialCompleted = true,
	tutorialStep = true,
})

local function validLegacyTutorial(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local count = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "string" or LEGACY_TUTORIAL_FIELDS[key] ~= true then
			return false
		end
		count += 1
	end
	return count == 3
		and type((value :: any).firstJoin) == "boolean"
		and type((value :: any).tutorialCompleted) == "boolean"
		and type((value :: any).tutorialStep) == "number"
		and Validation.isSafeInteger((value :: any).tutorialStep)
		and (value :: any).tutorialStep >= 0
		and (value :: any).tutorialStep <= 20
end

local function tutorialStartersExceedCapacity(profile: { [any]: any }): boolean?
	local unitCount = countUnits(profile.units)
	if unitCount == nil then
		return nil
	end
	local ownsDart = false
	local ownsBombardier = false
	for _, unit in profile.units do
		if type(unit) ~= "table" or getmetatable(unit) ~= nil then
			return nil
		end
		local towerId = rawget(unit, "towerId")
		ownsDart = ownsDart or towerId == ProfileSchema.DART_STARTER_TOWER_ID
		ownsBombardier = ownsBombardier or towerId == ProfileSchema.BOMBARDIER_STARTER_TOWER_ID
	end
	local missingStarterCount = (if ownsDart then 0 else 1) + (if ownsBombardier then 0 else 1)
	return unitCount + missingStarterCount > ProfileSchema.MAX_UNITS
end

local function migrateFiveToSix(profile: { [any]: any }, now: number): boolean
	if not validLegacyTutorial(profile.tutorial) then
		return false
	end
	local migration = profile.migration
	local stats = profile.stats
	local startersExceedCapacity = tutorialStartersExceedCapacity(profile)
	if
		type(migration) ~= "table"
		or getmetatable(migration) ~= nil
		or type(migration.migrationCount) ~= "number"
		or not Validation.isSafeInteger(migration.migrationCount)
		or migration.migrationCount < 0
		or type(stats) ~= "table"
		or getmetatable(stats) ~= nil
		or type(stats.matchesPlayed) ~= "number"
		or not Validation.isSafeInteger(stats.matchesPlayed)
		or stats.matchesPlayed < 0
		or startersExceedCapacity == nil
	then
		return false
	end
	local legacy = profile.tutorial
	-- A legacy inventory is never discarded or replaced to make room for the
	-- tutorial starters. Profiles that cannot fit every missing starter are
	-- grandfathered past onboarding instead of being stranded at step zero.
	local grandfathered = legacy.tutorialCompleted == true or stats.matchesPlayed > 0 or startersExceedCapacity
	profile.tutorial = {
		version = ProfileSchema.TUTORIAL_VERSION,
		firstJoin = not grandfathered,
		tutorialCompleted = grandfathered,
		tutorialStep = if grandfathered then ProfileSchema.MAX_TUTORIAL_STEP else 0,
		attempt = 1,
		skipped = false,
		trackedMatchId = "",
	}
	migration.lastMigratedAt = now
	migration.migrationCount += 1
	profile.schemaVersion = 6
	return true
end

function ProfileMigrations.migrate(
	rawProfile: unknown,
	towers: ConfigTypes.TowerCatalog,
	nowValue: unknown
): Result.Result<MigrationResult, MigrationError | ProfileSchema.ProfileError>
	if type(nowValue) ~= "number" or not Validation.isSafeInteger(nowValue) or (nowValue :: number) < 0 then
		return failure("INVALID_TIMESTAMP", "now", "Migration timestamp must be a nonnegative safe integer")
	end
	local now = nowValue :: number
	if rawProfile == nil then
		local starter = ProfileSchema.createStarter(towers, now)
		if not starter.ok then
			return starter
		end
		return Result.ok(table.freeze({
			profile = starter.value,
			outcome = "Created",
			fromVersion = 0,
			appliedVersions = table.freeze({}),
		}))
	end
	if type(rawProfile) ~= "table" or getmetatable(rawProfile :: any) ~= nil then
		return failure("MALFORMED_PROFILE", "profile", "Stored profile must be a plain table")
	end
	local rawVersion = rawget(rawProfile :: any, "schemaVersion")
	if rawVersion == nil then
		return failure("MISSING_VERSION", "profile.schemaVersion", "Stored profile has no schema version")
	end
	if type(rawVersion) ~= "number" or not Validation.isSafeInteger(rawVersion) then
		return failure("MALFORMED_PROFILE", "profile.schemaVersion", "Stored profile version is malformed")
	end
	local version = rawVersion :: number
	if version > ProfileSchema.CURRENT_VERSION then
		return failure("FUTURE_VERSION", "profile.schemaVersion", "Stored profile was written by a newer schema")
	end
	if version < 1 then
		return failure("UNSUPPORTED_VERSION", "profile.schemaVersion", "Stored profile version cannot be migrated")
	end
	if version == ProfileSchema.CURRENT_VERSION then
		local current = ProfileSchema.validate(rawProfile, towers)
		if not current.ok then
			return current
		end
		return Result.ok(table.freeze({
			profile = current.value,
			outcome = "Current",
			fromVersion = version,
			appliedVersions = table.freeze({}),
		}))
	end

	local cloned = cloneBounded(rawProfile)
	if type(cloned) ~= "table" then
		return failure("MALFORMED_PROFILE", "profile", "Stored profile cannot be copied within migration bounds")
	end
	local working = cloned :: { [any]: any }
	local originalVersion = version
	local appliedVersions: { number } = {}
	while version < ProfileSchema.CURRENT_VERSION do
		local migrated = false
		if version == 1 then
			migrated = migrateOneToTwo(working)
			version = 2
		elseif version == 2 then
			migrated = migrateTwoToThree(working, originalVersion, now)
			version = 3
		elseif version == 3 then
			migrated = migrateThreeToFour(working, now)
			version = 4
		elseif version == 4 then
			migrated = migrateFourToFive(working, now)
			version = 5
		elseif version == 5 then
			migrated = migrateFiveToSix(working, now)
			version = 6
		end
		if not migrated then
			return failure("MIGRATION_FAILED", "profile", "Stored profile failed a deterministic migration step")
		end
		table.insert(appliedVersions, version)
	end

	local validated = ProfileSchema.validate(working, towers)
	if not validated.ok then
		return validated
	end
	return Result.ok(table.freeze({
		profile = validated.value,
		outcome = "Migrated",
		fromVersion = originalVersion,
		appliedVersions = table.freeze(appliedVersions),
	}))
end

return table.freeze(ProfileMigrations)
