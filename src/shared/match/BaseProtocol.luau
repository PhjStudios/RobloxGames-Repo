--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type BaseStatus = "Active" | "Defeated" | "Faulted"
export type BaseReplicationKind = "State" | "Damage"

export type GetBaseSnapshotPayload = {}

export type BaseSnapshot = {
	matchId: Ids.MatchId,
	enemyEpoch: number,
	mapId: Ids.MapId,
	difficultyId: Ids.DifficultyId,
	basePosition: Vector3,
	baseRevision: number,
	status: BaseStatus,
	currentHealth: number,
	maximumHealth: number,
	lowHealth: boolean,
	initializedServerTime: number,
	updatedServerTime: number,
}

export type BaseStateMessage = {
	kind: "State",
	snapshot: BaseSnapshot,
}

export type BaseDamageMessage = {
	kind: "Damage",
	snapshot: BaseSnapshot,
	appliedDamage: number,
	leakCount: number,
	lowHealthCrossed: boolean,
}

export type BaseReplicationMessage = BaseStateMessage | BaseDamageMessage

local GET_BASE_SNAPSHOT_ENDPOINT = "GetBaseSnapshot"
local BASE_REPLICATION_ENDPOINT = "BaseReplication"
local STATE_KIND = "State"
local DAMAGE_KIND = "Damage"

local MAX_ENEMY_EPOCH = 4_096
local MAX_BASE_COORDINATE = 100_000
local MAX_LEAKS_PER_MESSAGE = 128
local MAX_BROADCAST_RECIPIENTS = 4
local MAX_LIFETIME_PUBLICATIONS = 4_098
local MAX_BASE_REVISION = Validation.MAX_SAFE_INTEGER
local MAX_FINITE_NUMBER = 1.7976931348623157e308

local POSITIVE_SAFE_INTEGER_VALIDATOR = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)
local NONNEGATIVE_SAFE_INTEGER_VALIDATOR = PayloadValidation.integer(0, Validation.MAX_SAFE_INTEGER)
local NONNEGATIVE_FINITE_NUMBER_VALIDATOR = PayloadValidation.number(0, MAX_FINITE_NUMBER)

local BASE_SNAPSHOT_VALIDATOR = PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	enemyEpoch = PayloadValidation.integer(1, MAX_ENEMY_EPOCH),
	mapId = PayloadValidation.id("map"),
	difficultyId = PayloadValidation.id("difficulty"),
	basePosition = PayloadValidation.vector3(),
	baseRevision = POSITIVE_SAFE_INTEGER_VALIDATOR,
	status = PayloadValidation.enum({ "Active", "Defeated", "Faulted" }),
	currentHealth = NONNEGATIVE_SAFE_INTEGER_VALIDATOR,
	maximumHealth = POSITIVE_SAFE_INTEGER_VALIDATOR,
	lowHealth = PayloadValidation.boolean(),
	initializedServerTime = NONNEGATIVE_FINITE_NUMBER_VALIDATOR,
	updatedServerTime = NONNEGATIVE_FINITE_NUMBER_VALIDATOR,
})

local STATE_MESSAGE_VALIDATOR = PayloadValidation.record({
	kind = PayloadValidation.enum({ STATE_KIND }),
	snapshot = BASE_SNAPSHOT_VALIDATOR,
})

local DAMAGE_MESSAGE_VALIDATOR = PayloadValidation.record({
	kind = PayloadValidation.enum({ DAMAGE_KIND }),
	snapshot = BASE_SNAPSHOT_VALIDATOR,
	appliedDamage = POSITIVE_SAFE_INTEGER_VALIDATOR,
	leakCount = PayloadValidation.integer(1, MAX_LEAKS_PER_MESSAGE),
	lowHealthCrossed = PayloadValidation.boolean(),
})

local GetBaseSnapshotPayloadSchema = PayloadValidation.schema(PayloadValidation.record({}))
local BaseSnapshotSchema = PayloadValidation.schema(BASE_SNAPSHOT_VALIDATOR)
local BaseReplicationSchema = PayloadValidation.schema(PayloadValidation.union({
	STATE_MESSAGE_VALIDATOR,
	DAMAGE_MESSAGE_VALIDATOR,
}))

local function issue(
	code: Validation.Code,
	path: { Validation.PathSegment },
	message: string
): Result.Failure<Validation.Issue>
	return Result.err(Validation.issue(code, path, message))
end

local function fieldPath(prefix: { Validation.PathSegment }, fieldName: string): { Validation.PathSegment }
	return Validation.appendPath(prefix, fieldName)
end

local function isBoundedPosition(position: Vector3): boolean
	return math.abs(position.X) <= MAX_BASE_COORDINATE
		and math.abs(position.Y) <= MAX_BASE_COORDINATE
		and math.abs(position.Z) <= MAX_BASE_COORDINATE
end

local function validateSnapshotSemantics(
	snapshot: BaseSnapshot,
	prefix: { Validation.PathSegment }
): Result.Failure<Validation.Issue>?
	if snapshot.currentHealth > snapshot.maximumHealth then
		return issue(
			"INVALID_TOTAL",
			fieldPath(prefix, "currentHealth"),
			"Current base health must not exceed the authoritative maximum"
		)
	end
	if not isBoundedPosition(snapshot.basePosition) then
		return issue(
			"OUT_OF_RANGE",
			fieldPath(prefix, "basePosition"),
			"Base position exceeds the fixed world-coordinate bounds"
		)
	end
	if snapshot.updatedServerTime < snapshot.initializedServerTime then
		return issue(
			"INVALID_ORDER",
			fieldPath(prefix, "updatedServerTime"),
			"Base update time must not precede initialization time"
		)
	end

	local expectedLowHealth = snapshot.currentHealth <= snapshot.maximumHealth / 4
	if snapshot.lowHealth ~= expectedLowHealth then
		return issue(
			"INVALID_REFERENCE",
			fieldPath(prefix, "lowHealth"),
			"Low-health state must equal the fixed one-quarter threshold policy"
		)
	end
	if snapshot.status == "Active" and snapshot.currentHealth == 0 then
		return issue(
			"INVALID_REFERENCE",
			fieldPath(prefix, "status"),
			"An Active base must have positive current health"
		)
	end
	if snapshot.status == "Defeated" and snapshot.currentHealth ~= 0 then
		return issue("INVALID_REFERENCE", fieldPath(prefix, "status"), "A Defeated base must have zero current health")
	end
	return nil
end

local function canonicalSnapshot(snapshot: BaseSnapshot): BaseSnapshot
	return table.freeze({
		matchId = snapshot.matchId,
		enemyEpoch = snapshot.enemyEpoch,
		mapId = snapshot.mapId,
		difficultyId = snapshot.difficultyId,
		basePosition = snapshot.basePosition,
		baseRevision = snapshot.baseRevision,
		status = snapshot.status,
		currentHealth = snapshot.currentHealth,
		maximumHealth = snapshot.maximumHealth,
		lowHealth = snapshot.lowHealth,
		initializedServerTime = snapshot.initializedServerTime,
		updatedServerTime = snapshot.updatedServerTime,
	})
end

local BaseProtocol = {
	GET_BASE_SNAPSHOT_ENDPOINT = GET_BASE_SNAPSHOT_ENDPOINT,
	BASE_REPLICATION_ENDPOINT = BASE_REPLICATION_ENDPOINT,
	STATE_KIND = STATE_KIND,
	DAMAGE_KIND = DAMAGE_KIND,
	REPLICATION_KINDS = table.freeze({ STATE_KIND, DAMAGE_KIND }),
	MAX_ENEMY_EPOCH = MAX_ENEMY_EPOCH,
	MAX_BASE_COORDINATE = MAX_BASE_COORDINATE,
	MAX_LEAKS_PER_MESSAGE = MAX_LEAKS_PER_MESSAGE,
	MAX_BROADCAST_RECIPIENTS = MAX_BROADCAST_RECIPIENTS,
	MAX_LIFETIME_PUBLICATIONS = MAX_LIFETIME_PUBLICATIONS,
	MAX_BASE_REVISION = MAX_BASE_REVISION,
	GetBaseSnapshotPayloadSchema = GetBaseSnapshotPayloadSchema,
	BaseSnapshotSchema = BaseSnapshotSchema,
	BaseReplicationSchema = BaseReplicationSchema,
}

function BaseProtocol.validateBaseSnapshot(value: unknown): Result.Result<BaseSnapshot, Validation.Issue>
	local schemaResult = BaseSnapshotSchema:validate(value)
	if not schemaResult.ok then
		return Result.err(schemaResult.error)
	end

	local snapshot = schemaResult.value :: BaseSnapshot
	local semanticFailure = validateSnapshotSemantics(snapshot, { "payload" })
	if semanticFailure ~= nil then
		return semanticFailure
	end
	return Result.ok(canonicalSnapshot(snapshot))
end

function BaseProtocol.validateBaseReplicationMessage(
	value: unknown
): Result.Result<BaseReplicationMessage, Validation.Issue>
	local schemaResult = BaseReplicationSchema:validate(value)
	if not schemaResult.ok then
		return Result.err(schemaResult.error)
	end

	local message = schemaResult.value :: BaseReplicationMessage
	local snapshotFailure = validateSnapshotSemantics(message.snapshot, { "payload", "snapshot" })
	if snapshotFailure ~= nil then
		return snapshotFailure
	end
	local snapshot = canonicalSnapshot(message.snapshot)

	if message.kind == STATE_KIND then
		return Result.ok(table.freeze({
			kind = STATE_KIND,
			snapshot = snapshot,
		}))
	end

	local damage = message :: BaseDamageMessage
	if damage.snapshot.status == "Faulted" then
		return issue(
			"INVALID_REFERENCE",
			{ "payload", "snapshot", "status" },
			"Damage feedback cannot publish a fault transition"
		)
	end
	if damage.appliedDamage > damage.snapshot.maximumHealth then
		return issue(
			"INVALID_TOTAL",
			{ "payload", "appliedDamage" },
			"Applied damage must not exceed maximum base health"
		)
	end
	if damage.appliedDamage > damage.snapshot.maximumHealth - damage.snapshot.currentHealth then
		return issue(
			"INVALID_TOTAL",
			{ "payload", "appliedDamage" },
			"Applied damage must fit the health change represented by the full snapshot"
		)
	end
	if damage.leakCount > damage.appliedDamage then
		return issue(
			"INVALID_TOTAL",
			{ "payload", "leakCount" },
			"Each health-changing leak must contribute at least one applied health point"
		)
	end
	if damage.lowHealthCrossed and not damage.snapshot.lowHealth then
		return issue(
			"INVALID_REFERENCE",
			{ "payload", "lowHealthCrossed" },
			"A low-health crossing requires a low-health full snapshot"
		)
	end

	return Result.ok(table.freeze({
		kind = DAMAGE_KIND,
		snapshot = snapshot,
		appliedDamage = damage.appliedDamage,
		leakCount = damage.leakCount,
		lowHealthCrossed = damage.lowHealthCrossed,
	}))
end

return table.freeze(BaseProtocol)
