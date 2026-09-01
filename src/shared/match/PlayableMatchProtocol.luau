--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local SettingsProtocol = require(script.Parent.Parent.settings.SettingsProtocol)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)
local RewardProtocol = require(script.Parent.RewardProtocol)

export type MatchState = "Ready" | "Playing" | "Results"
export type MatchResult = "None" | "Victory" | "Defeat"
export type WavePhase = "Ready" | "Intermission" | "Spawning" | "Resolving" | "Results"
export type ViewerRole = "Participant" | "Spectator"
export type TargetMode = "First" | "Last" | "Strongest" | "Weakest" | "Closest"
export type ActionReason =
	"Accepted"
	| "WrongState"
	| "StaleMatch"
	| "StaleLoadout"
	| "StaleTower"
	| "NotParticipant"
	| "ParticipantDisconnected"
	| "UnequippedTower"
	| "InvalidPlacement"
	| "InsufficientCash"
	| "TowerCap"
	| "NotFound"
	| "NotOwner"
	| "MaxLevel"
	| "UnsupportedTargetMode"
	| "Busy"
	| "Unavailable"

export type ParticipantSummary = {
	readyCount: number,
	participantCount: number,
}

export type TowerOption = {
	slot: number,
	unitId: string,
	towerId: string,
	displayName: string,
	placementCost: number,
	description: string,
}

export type TowerSnapshot = {
	runtimeTowerId: number,
	revision: number,
	towerId: string,
	displayName: string,
	ownerUserId: number,
	level: number,
	targetMode: TargetMode,
	position: Vector3,
	rotationDegrees: number,
	totalInvestment: number,
	cooldownEndsServerTime: number,
	damage: number,
	cooldownSeconds: number,
	rangeStuds: number,
	upgradeCost: number,
	sellValue: number,
}

export type EnemySnapshot = {
	runtimeEnemyId: number,
	enemyId: string,
	displayName: string,
	currentHealth: number,
	maximumHealth: number,
	position: Vector3,
	pathProgress: number,
}

export type ResultStats = {
	durationSeconds: number,
	wavesCompleted: number,
	damageDealt: number,
	battleCashEarned: number,
	battleCashSpent: number,
	placements: number,
	upgrades: number,
	sells: number,
	baseHealthRemaining: number,
}

export type Snapshot = {
	matchId: string,
	viewerRole: ViewerRole,
	rewarding: boolean,
	revision: number,
	loadoutRevision: number,
	state: MatchState,
	result: MatchResult,
	mapId: string,
	mapDisplayName: string,
	difficultyId: string,
	difficultyDisplayName: string,
	serverTime: number,
	waveNumber: number,
	totalWaves: number,
	wavePhase: WavePhase,
	nextWaveServerTime: number,
	baseHealth: number,
	maximumBaseHealth: number,
	enemiesAlive: number,
	battleCash: number,
	participants: ParticipantSummary,
	towerOptions: { TowerOption },
	towers: { TowerSnapshot },
	enemies: { EnemySnapshot },
	stats: ResultStats,
	reward: RewardProtocol.RewardView?,
	settings: SettingsProtocol.Settings,
}

export type GetSnapshotPayload = {}
export type ReadyPayload = { matchId: string }
export type ReplayPayload = { matchId: string }
export type PlacementPayload = {
	matchId: string,
	loadoutRevision: number,
	slot: number,
	towerId: string,
	position: Vector3,
	rotationDegrees: number,
}
export type TowerPayload = {
	matchId: string,
	runtimeTowerId: number,
	towerRevision: number,
}
export type TargetModePayload = TowerPayload & { targetMode: TargetMode }

export type ActionReceipt = {
	accepted: boolean,
	reason: ActionReason,
	matchId: string,
	revision: number,
	battleCash: number,
}

export type AttackEvent = {
	matchId: string,
	sequence: number,
	runtimeTowerId: number,
	runtimeEnemyId: number,
	sourcePosition: Vector3,
	targetPosition: Vector3,
	actualDamage: number,
	killed: boolean,
	serverTime: number,
}

local MAX_COORDINATE = 100_000
-- Keep a worst-case snapshot within PayloadValidation's global 512-node budget.
local MAX_ACTIVE_TOWERS = 12
local MAX_ACTIVE_ENEMIES = 20
local MIN_TOWER_OPTIONS = 0
local MAX_TOWER_OPTIONS = 5
local MAX_LEVEL = 10
local MAX_WAVES = 1_000
local MAX_NAME_BYTES = 64
local MAX_DESCRIPTION_BYTES = 160
local MAX_FINITE_NUMBER = 1.7976931348623157e308

local ENDPOINTS = table.freeze({
	GET_SNAPSHOT = "GetPlayableMatchSnapshot",
	SUBMIT_READY = "SubmitPlayableReady",
	SUBMIT_PLACEMENT = "SubmitPlayablePlacement",
	SUBMIT_UPGRADE = "SubmitTowerUpgrade",
	SUBMIT_SELL = "SubmitTowerSell",
	SUBMIT_TARGET_MODE = "SubmitTowerTargetMode",
	SUBMIT_REPLAY = "SubmitPlayableReplay",
	REPLICATION = "PlayableMatchReplication",
	ATTACK_EVENT = "CombatAttackEvent",
})

local TARGET_MODES: { TargetMode } = table.freeze({
	"First",
	"Last",
	"Strongest",
	"Weakest",
	"Closest",
})

local ACTION_REASONS: { ActionReason } = table.freeze({
	"Accepted",
	"WrongState",
	"StaleMatch",
	"StaleLoadout",
	"StaleTower",
	"NotParticipant",
	"ParticipantDisconnected",
	"UnequippedTower",
	"InvalidPlacement",
	"InsufficientCash",
	"TowerCap",
	"NotFound",
	"NotOwner",
	"MaxLevel",
	"UnsupportedTargetMode",
	"Busy",
	"Unavailable",
})

local NONNEGATIVE_SAFE_INTEGER = PayloadValidation.integer(0, Validation.MAX_SAFE_INTEGER)
local POSITIVE_SAFE_INTEGER = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)
local NONNEGATIVE_NUMBER = PayloadValidation.number(0, MAX_FINITE_NUMBER)
local TARGET_MODE = PayloadValidation.enum(TARGET_MODES)

local PARTICIPANT_SUMMARY = PayloadValidation.record({
	readyCount = PayloadValidation.integer(0, 4),
	participantCount = PayloadValidation.integer(0, 4),
})

local TOWER_OPTION = PayloadValidation.record({
	slot = PayloadValidation.integer(1, MAX_TOWER_OPTIONS),
	unitId = PayloadValidation.id("unit"),
	towerId = PayloadValidation.id("tower"),
	displayName = PayloadValidation.string(MAX_NAME_BYTES, 1),
	placementCost = NONNEGATIVE_SAFE_INTEGER,
	description = PayloadValidation.string(MAX_DESCRIPTION_BYTES, 1),
})

local TOWER_SNAPSHOT = PayloadValidation.record({
	runtimeTowerId = POSITIVE_SAFE_INTEGER,
	revision = POSITIVE_SAFE_INTEGER,
	towerId = PayloadValidation.id("tower"),
	displayName = PayloadValidation.string(MAX_NAME_BYTES, 1),
	ownerUserId = PayloadValidation.integer(-Validation.MAX_SAFE_INTEGER, Validation.MAX_SAFE_INTEGER),
	level = PayloadValidation.integer(1, MAX_LEVEL),
	targetMode = TARGET_MODE,
	position = PayloadValidation.vector3(),
	rotationDegrees = PayloadValidation.number(-360, 360),
	totalInvestment = NONNEGATIVE_SAFE_INTEGER,
	cooldownEndsServerTime = NONNEGATIVE_NUMBER,
	damage = NONNEGATIVE_SAFE_INTEGER,
	cooldownSeconds = NONNEGATIVE_NUMBER,
	rangeStuds = NONNEGATIVE_NUMBER,
	upgradeCost = NONNEGATIVE_SAFE_INTEGER,
	sellValue = NONNEGATIVE_SAFE_INTEGER,
})

local ENEMY_SNAPSHOT = PayloadValidation.record({
	runtimeEnemyId = POSITIVE_SAFE_INTEGER,
	enemyId = PayloadValidation.id("enemy"),
	displayName = PayloadValidation.string(MAX_NAME_BYTES, 1),
	currentHealth = NONNEGATIVE_SAFE_INTEGER,
	maximumHealth = POSITIVE_SAFE_INTEGER,
	position = PayloadValidation.vector3(),
	pathProgress = NONNEGATIVE_NUMBER,
})

local RESULT_STATS = PayloadValidation.record({
	durationSeconds = NONNEGATIVE_NUMBER,
	wavesCompleted = PayloadValidation.integer(0, MAX_WAVES),
	damageDealt = NONNEGATIVE_SAFE_INTEGER,
	battleCashEarned = NONNEGATIVE_SAFE_INTEGER,
	battleCashSpent = NONNEGATIVE_SAFE_INTEGER,
	placements = NONNEGATIVE_SAFE_INTEGER,
	upgrades = NONNEGATIVE_SAFE_INTEGER,
	sells = NONNEGATIVE_SAFE_INTEGER,
	baseHealthRemaining = NONNEGATIVE_SAFE_INTEGER,
})

-- RewardProtocol exports a boundary Schema, while nested protocol fields need
-- a Validator. Keep this wire shape identical and apply RewardProtocol's
-- additional result/status invariants in validateSnapshot below.
local REWARD_VIEW = PayloadValidation.record({
	resultId = PayloadValidation.string(64, 8),
	status = PayloadValidation.enum({ "Granted", "Pending", "Ineligible", "Failed" }),
	persistentGoldAwarded = PayloadValidation.integer(0, 1_000_000_000_000),
	firstClearBonus = PayloadValidation.integer(0, 1_000_000_000_000),
	battleCashEarned = PayloadValidation.integer(0, 1_000_000_000_000),
	battleCashSpent = PayloadValidation.integer(0, 1_000_000_000_000),
	reason = PayloadValidation.string(48, 1),
})

local SNAPSHOT = PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	viewerRole = PayloadValidation.enum({ "Participant", "Spectator" }),
	rewarding = PayloadValidation.boolean(),
	revision = POSITIVE_SAFE_INTEGER,
	loadoutRevision = NONNEGATIVE_SAFE_INTEGER,
	state = PayloadValidation.enum({ "Ready", "Playing", "Results" }),
	result = PayloadValidation.enum({ "None", "Victory", "Defeat" }),
	mapId = PayloadValidation.id("map"),
	mapDisplayName = PayloadValidation.string(MAX_NAME_BYTES, 1),
	difficultyId = PayloadValidation.id("difficulty"),
	difficultyDisplayName = PayloadValidation.string(MAX_NAME_BYTES, 1),
	serverTime = NONNEGATIVE_NUMBER,
	waveNumber = PayloadValidation.integer(0, MAX_WAVES),
	totalWaves = PayloadValidation.integer(1, MAX_WAVES),
	wavePhase = PayloadValidation.enum({ "Ready", "Intermission", "Spawning", "Resolving", "Results" }),
	nextWaveServerTime = NONNEGATIVE_NUMBER,
	baseHealth = NONNEGATIVE_SAFE_INTEGER,
	maximumBaseHealth = POSITIVE_SAFE_INTEGER,
	enemiesAlive = PayloadValidation.integer(0, MAX_ACTIVE_ENEMIES),
	battleCash = NONNEGATIVE_SAFE_INTEGER,
	participants = PARTICIPANT_SUMMARY,
	towerOptions = PayloadValidation.array(TOWER_OPTION, MAX_TOWER_OPTIONS, MIN_TOWER_OPTIONS),
	towers = PayloadValidation.array(TOWER_SNAPSHOT, MAX_ACTIVE_TOWERS),
	enemies = PayloadValidation.array(ENEMY_SNAPSHOT, MAX_ACTIVE_ENEMIES),
	stats = RESULT_STATS,
	reward = PayloadValidation.optional(REWARD_VIEW),
	settings = SettingsProtocol.SettingsValidator,
})

local GetSnapshotPayloadSchema = PayloadValidation.schema(PayloadValidation.record({}))
local ReadyPayloadSchema = PayloadValidation.schema(PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
}))
local ReplayPayloadSchema = ReadyPayloadSchema
local PlacementPayloadSchema = PayloadValidation.schema(PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	loadoutRevision = POSITIVE_SAFE_INTEGER,
	slot = PayloadValidation.integer(1, MAX_TOWER_OPTIONS),
	towerId = PayloadValidation.id("tower"),
	position = PayloadValidation.vector3(),
	rotationDegrees = PayloadValidation.number(-360, 360),
}))
local TowerPayloadSchema = PayloadValidation.schema(PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	runtimeTowerId = POSITIVE_SAFE_INTEGER,
	towerRevision = POSITIVE_SAFE_INTEGER,
}))
local TargetModePayloadSchema = PayloadValidation.schema(PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	runtimeTowerId = POSITIVE_SAFE_INTEGER,
	towerRevision = POSITIVE_SAFE_INTEGER,
	targetMode = TARGET_MODE,
}))
local ActionReceiptSchema = PayloadValidation.schema(PayloadValidation.record({
	accepted = PayloadValidation.boolean(),
	reason = PayloadValidation.enum(ACTION_REASONS),
	matchId = PayloadValidation.id("match"),
	revision = POSITIVE_SAFE_INTEGER,
	battleCash = NONNEGATIVE_SAFE_INTEGER,
}))
local SnapshotSchema = PayloadValidation.schema(SNAPSHOT)
local AttackEventSchema = PayloadValidation.schema(PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	sequence = POSITIVE_SAFE_INTEGER,
	runtimeTowerId = POSITIVE_SAFE_INTEGER,
	runtimeEnemyId = POSITIVE_SAFE_INTEGER,
	sourcePosition = PayloadValidation.vector3(),
	targetPosition = PayloadValidation.vector3(),
	actualDamage = POSITIVE_SAFE_INTEGER,
	killed = PayloadValidation.boolean(),
	serverTime = NONNEGATIVE_NUMBER,
}))

local function withinWorldBounds(position: Vector3): boolean
	return math.abs(position.X) <= MAX_COORDINATE
		and math.abs(position.Y) <= MAX_COORDINATE
		and math.abs(position.Z) <= MAX_COORDINATE
end

local function validateWorldPositions(snapshot: Snapshot): Result.Failure<Validation.Issue>?
	for index, tower in snapshot.towers do
		if not withinWorldBounds(tower.position) then
			return Result.err(
				Validation.issue(
					"OUT_OF_RANGE",
					{ "payload", "towers", index, "position" },
					"Tower position exceeds world bounds"
				)
			)
		end
	end
	for index, enemy in snapshot.enemies do
		if not withinWorldBounds(enemy.position) then
			return Result.err(
				Validation.issue(
					"OUT_OF_RANGE",
					{ "payload", "enemies", index, "position" },
					"Enemy position exceeds world bounds"
				)
			)
		end
	end
	return nil
end

local PlayableMatchProtocol = {
	ENDPOINTS = ENDPOINTS,
	TARGET_MODES = TARGET_MODES,
	ACTION_REASONS = ACTION_REASONS,
	MAX_ACTIVE_TOWERS = MAX_ACTIVE_TOWERS,
	MAX_ACTIVE_ENEMIES = MAX_ACTIVE_ENEMIES,
	MIN_TOWER_OPTIONS = MIN_TOWER_OPTIONS,
	MAX_TOWER_OPTIONS = MAX_TOWER_OPTIONS,
	GetSnapshotPayloadSchema = GetSnapshotPayloadSchema,
	ReadyPayloadSchema = ReadyPayloadSchema,
	ReplayPayloadSchema = ReplayPayloadSchema,
	PlacementPayloadSchema = PlacementPayloadSchema,
	TowerPayloadSchema = TowerPayloadSchema,
	TargetModePayloadSchema = TargetModePayloadSchema,
	ActionReceiptSchema = ActionReceiptSchema,
	SnapshotSchema = SnapshotSchema,
	AttackEventSchema = AttackEventSchema,
}

function PlayableMatchProtocol.validateSnapshot(value: unknown): Result.Result<Snapshot, Validation.Issue>
	local result = SnapshotSchema:validate(value)
	if not result.ok then
		return Result.err(result.error)
	end
	local snapshot = result.value :: Snapshot
	if snapshot.baseHealth > snapshot.maximumBaseHealth then
		return Result.err(Validation.issue("INVALID_TOTAL", { "payload", "baseHealth" }, "Base health exceeds maximum"))
	end
	if snapshot.enemiesAlive ~= #snapshot.enemies then
		return Result.err(
			Validation.issue("INVALID_TOTAL", { "payload", "enemiesAlive" }, "Enemy count does not match entries")
		)
	end
	if snapshot.participants.readyCount > snapshot.participants.participantCount then
		return Result.err(
			Validation.issue(
				"INVALID_TOTAL",
				{ "payload", "participants", "readyCount" },
				"Ready count exceeds participant count"
			)
		)
	end
	if snapshot.viewerRole == "Participant" then
		if snapshot.loadoutRevision < 1 or #snapshot.towerOptions < 1 then
			return Result.err(
				Validation.issue(
					"INVALID_REFERENCE",
					{ "payload", "viewerRole" },
					"Participant snapshots require a frozen loadout"
				)
			)
		end
	elseif
		snapshot.loadoutRevision ~= 0
		or snapshot.battleCash ~= 0
		or #snapshot.towerOptions ~= 0
		or snapshot.stats.damageDealt ~= 0
		or snapshot.stats.battleCashEarned ~= 0
		or snapshot.stats.battleCashSpent ~= 0
		or snapshot.stats.placements ~= 0
		or snapshot.stats.upgrades ~= 0
		or snapshot.stats.sells ~= 0
	then
		return Result.err(
			Validation.issue(
				"INVALID_REFERENCE",
				{ "payload", "viewerRole" },
				"Spectator snapshots cannot contain participant-private match state"
			)
		)
	end
	if snapshot.reward ~= nil then
		local reward = RewardProtocol.validateRewardView(snapshot.reward)
		if not reward.ok or snapshot.state ~= "Results" or not snapshot.rewarding then
			return Result.err(
				Validation.issue(
					"INVALID_REFERENCE",
					{ "payload", "reward" },
					"Reward views require an authoritative rewarding result"
				)
			)
		end
		if
			snapshot.viewerRole == "Spectator"
			and (
				reward.value.status == "Granted"
				or reward.value.persistentGoldAwarded ~= 0
				or reward.value.firstClearBonus ~= 0
				or reward.value.battleCashEarned ~= 0
				or reward.value.battleCashSpent ~= 0
			)
		then
			return Result.err(
				Validation.issue(
					"INVALID_REFERENCE",
					{ "payload", "reward" },
					"Spectator reward status cannot grant Gold or expose participant Battle Cash"
				)
			)
		end
	end
	if snapshot.waveNumber > snapshot.totalWaves then
		return Result.err(
			Validation.issue("INVALID_TOTAL", { "payload", "waveNumber" }, "Wave number exceeds total waves")
		)
	end
	local seenTowerIds: { [string]: boolean } = {}
	local seenUnitIds: { [string]: boolean } = {}
	for index, option in snapshot.towerOptions do
		if option.slot ~= index then
			return Result.err(
				Validation.issue(
					"INVALID_ORDER",
					{ "payload", "towerOptions", index, "slot" },
					"Tower option slots must be dense and ordered"
				)
			)
		end
		if seenTowerIds[option.towerId] or seenUnitIds[option.unitId] then
			return Result.err(
				Validation.issue(
					"DUPLICATE_VALUE",
					{ "payload", "towerOptions", index },
					"Tower options must reference unique equipped towers and units"
				)
			)
		end
		seenTowerIds[option.towerId] = true
		seenUnitIds[option.unitId] = true
	end
	if
		(snapshot.state == "Results") ~= (snapshot.result ~= "None")
		or (snapshot.state == "Results") ~= (snapshot.wavePhase == "Results")
	then
		return Result.err(
			Validation.issue("INVALID_REFERENCE", { "payload", "result" }, "Result fields do not match state")
		)
	end
	for index, enemy in snapshot.enemies do
		if enemy.currentHealth > enemy.maximumHealth then
			return Result.err(
				Validation.issue(
					"INVALID_TOTAL",
					{ "payload", "enemies", index, "currentHealth" },
					"Enemy health exceeds maximum"
				)
			)
		end
	end
	local positionFailure = validateWorldPositions(snapshot)
	if positionFailure ~= nil then
		return positionFailure
	end
	return Result.ok(snapshot)
end

function PlayableMatchProtocol.validateActionReceipt(value: unknown): Result.Result<ActionReceipt, Validation.Issue>
	local result = ActionReceiptSchema:validate(value)
	if not result.ok then
		return Result.err(result.error)
	end
	local receipt = result.value :: ActionReceipt
	if receipt.accepted ~= (receipt.reason == "Accepted") then
		return Result.err(
			Validation.issue("INVALID_REFERENCE", { "payload", "reason" }, "Receipt reason does not match acceptance")
		)
	end
	return Result.ok(receipt)
end

function PlayableMatchProtocol.validateAttackEvent(value: unknown): Result.Result<AttackEvent, Validation.Issue>
	local result = AttackEventSchema:validate(value)
	if not result.ok then
		return Result.err(result.error)
	end
	local event = result.value :: AttackEvent
	if not withinWorldBounds(event.sourcePosition) or not withinWorldBounds(event.targetPosition) then
		return Result.err(
			Validation.issue("OUT_OF_RANGE", { "payload", "targetPosition" }, "Attack position exceeds world bounds")
		)
	end
	return Result.ok(event)
end

return table.freeze(PlayableMatchProtocol)
