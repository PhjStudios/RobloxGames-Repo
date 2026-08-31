--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type ProfileState = "Loading" | "Ready" | "Failed" | "Releasing"
export type MigrationOutcome = "Created" | "Migrated" | "Current"

export type SettingsView = {
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

export type TutorialView = {
	firstJoin: boolean,
	tutorialCompleted: boolean,
	tutorialStep: number,
}

export type StatisticsView = {
	matchesPlayed: number,
	victories: number,
	defeats: number,
	towersAcquired: number,
	chestsOpened: number,
}

export type Snapshot = {
	state: ProfileState,
	retryable: boolean,
	revision: number?,
	gold: number?,
	settings: SettingsView?,
	tutorial: TutorialView?,
	stats: StatisticsView?,
	migrationOutcome: MigrationOutcome?,
}

local MAX_SAFE_INTEGER = Validation.MAX_SAFE_INTEGER
local SETTINGS = PayloadValidation.record({
	version = PayloadValidation.integer(2, 2),
	masterVolume = PayloadValidation.number(0, 1),
	musicVolume = PayloadValidation.number(0, 1),
	sfxVolume = PayloadValidation.number(0, 1),
	uiVolume = PayloadValidation.number(0, 1),
	cameraShakeIntensity = PayloadValidation.number(0, 1),
	damageNumbersEnabled = PayloadValidation.boolean(),
	enemyHealthBarsEnabled = PayloadValidation.boolean(),
	otherPlayerEffectsEnabled = PayloadValidation.boolean(),
	lowDetailEnabled = PayloadValidation.boolean(),
	towerRangeEnabled = PayloadValidation.boolean(),
	uiScale = PayloadValidation.number(0.75, 1.25),
	reducedMotionEnabled = PayloadValidation.boolean(),
})

local TUTORIAL = PayloadValidation.record({
	firstJoin = PayloadValidation.boolean(),
	tutorialCompleted = PayloadValidation.boolean(),
	tutorialStep = PayloadValidation.integer(0, 20),
})

local STATISTICS = PayloadValidation.record({
	matchesPlayed = PayloadValidation.integer(0, 1_000_000_000_000),
	victories = PayloadValidation.integer(0, 1_000_000_000_000),
	defeats = PayloadValidation.integer(0, 1_000_000_000_000),
	towersAcquired = PayloadValidation.integer(0, 1_000_000_000_000),
	chestsOpened = PayloadValidation.integer(0, 1_000_000_000_000),
})

local SnapshotSchema = PayloadValidation.schema(PayloadValidation.record({
	state = PayloadValidation.enum({ "Loading", "Ready", "Failed", "Releasing" }),
	retryable = PayloadValidation.boolean(),
	revision = PayloadValidation.optional(PayloadValidation.integer(1, MAX_SAFE_INTEGER)),
	gold = PayloadValidation.optional(PayloadValidation.integer(0, 1_000_000_000_000)),
	settings = PayloadValidation.optional(SETTINGS),
	tutorial = PayloadValidation.optional(TUTORIAL),
	stats = PayloadValidation.optional(STATISTICS),
	migrationOutcome = PayloadValidation.optional(PayloadValidation.enum({ "Created", "Migrated", "Current" })),
}))

local ProfileProtocol = {
	SnapshotSchema = SnapshotSchema,
}

local function issue(path: { Validation.PathSegment }, message: string)
	return Result.err(Validation.issue("INVALID_REFERENCE", path, message))
end

function ProfileProtocol.validateSnapshot(value: unknown): Result.Result<Snapshot, Validation.Issue>
	local result = SnapshotSchema:validate(value)
	if not result.ok then
		return Result.err(result.error)
	end
	local snapshot = result.value :: Snapshot
	local hasReadyFields = snapshot.revision ~= nil
		and snapshot.gold ~= nil
		and snapshot.settings ~= nil
		and snapshot.tutorial ~= nil
		and snapshot.stats ~= nil
		and snapshot.migrationOutcome ~= nil
	if snapshot.state == "Ready" then
		if not hasReadyFields or snapshot.retryable then
			return issue({ "payload" }, "Ready profile snapshot is incomplete or retryable")
		end
	elseif
		hasReadyFields
		or snapshot.revision ~= nil
		or snapshot.gold ~= nil
		or snapshot.settings ~= nil
		or snapshot.tutorial ~= nil
		or snapshot.stats ~= nil
		or snapshot.migrationOutcome ~= nil
	then
		return issue({ "payload" }, "Non-ready profile snapshot contains private ready-state fields")
	elseif snapshot.retryable ~= (snapshot.state == "Failed") then
		return issue({ "payload", "retryable" }, "Only Failed profile state may be retryable")
	end
	return Result.ok(snapshot)
end

function ProfileProtocol.status(state: ProfileState): Snapshot
	return table.freeze({
		state = state,
		retryable = state == "Failed",
	})
end

function ProfileProtocol.ready(profile: any, migrationOutcome: MigrationOutcome): Snapshot
	local snapshot = {
		state = "Ready",
		retryable = false,
		revision = profile.revision,
		gold = profile.gold,
		settings = {
			version = profile.settings.version,
			masterVolume = profile.settings.masterVolume,
			musicVolume = profile.settings.musicVolume,
			sfxVolume = profile.settings.sfxVolume,
			uiVolume = profile.settings.uiVolume,
			cameraShakeIntensity = profile.settings.cameraShakeIntensity,
			damageNumbersEnabled = profile.settings.damageNumbersEnabled,
			enemyHealthBarsEnabled = profile.settings.enemyHealthBarsEnabled,
			otherPlayerEffectsEnabled = profile.settings.otherPlayerEffectsEnabled,
			lowDetailEnabled = profile.settings.lowDetailEnabled,
			towerRangeEnabled = profile.settings.towerRangeEnabled,
			uiScale = profile.settings.uiScale,
			reducedMotionEnabled = profile.settings.reducedMotionEnabled,
		},
		tutorial = {
			firstJoin = profile.tutorial.firstJoin,
			tutorialCompleted = profile.tutorial.tutorialCompleted,
			tutorialStep = profile.tutorial.tutorialStep,
		},
		stats = {
			matchesPlayed = profile.stats.matchesPlayed,
			victories = profile.stats.victories,
			defeats = profile.stats.defeats,
			towersAcquired = profile.stats.towersAcquired,
			chestsOpened = profile.stats.chestsOpened,
		},
		migrationOutcome = migrationOutcome,
	}
	local result = ProfileProtocol.validateSnapshot(snapshot)
	if not result.ok then
		error("[ATD_PROFILE_PROTOCOL][code=INVALID_READY_VIEW]", 0)
	end
	return result.value
end

return table.freeze(ProfileProtocol)
