--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type RuntimeEnemyId = number
export type EnemyEpoch = number
export type EnemyLifecycle = "Active" | "EndpointResolved"
export type DespawnReason = "Manual" | "Endpoint"
export type StateBatchKind = "SpawnBatch" | "CorrectionBatch" | "StateChangeBatch"
export type SnapshotBoundaryKind = "SnapshotBegin" | "SnapshotEnd"
export type ReplicationKind = StateBatchKind | "DespawnBatch" | SnapshotBoundaryKind | "SnapshotChunk"

export type GetEnemySnapshotPayload = {}

export type EnemyStateEntry = {
	runtimeEnemyId: RuntimeEnemyId,
	enemyId: Ids.EnemyId,
	laneId: string,
	revision: number,
	lifecycle: EnemyLifecycle,
	pathProgress: number,
	currentHealth: number,
	maximumHealth: number,
	slowMultiplier: number,
	spawnServerTime: number,
	sampleServerTime: number,
	worldCFrame: CFrame,
	effectiveSpeed: number,
	segmentIndex: number,
	segmentStartDistance: number,
	segmentEndDistance: number,
	segmentStartPosition: Vector3,
	segmentEndPosition: Vector3,
}

export type DespawnEntry = {
	runtimeEnemyId: RuntimeEnemyId,
	revision: number,
	sampleServerTime: number,
	reason: DespawnReason,
}

export type StateBatchMessage = {
	kind: StateBatchKind,
	matchId: Ids.MatchId,
	enemyEpoch: EnemyEpoch,
	sequence: number,
	entries: { EnemyStateEntry },
}

export type SpawnBatchMessage = StateBatchMessage
export type CorrectionBatchMessage = StateBatchMessage
export type StateChangeBatchMessage = StateBatchMessage

export type DespawnBatchMessage = {
	kind: "DespawnBatch",
	matchId: Ids.MatchId,
	enemyEpoch: EnemyEpoch,
	sequence: number,
	entries: { DespawnEntry },
}

export type SnapshotBoundaryMessage = {
	kind: SnapshotBoundaryKind,
	matchId: Ids.MatchId,
	enemyEpoch: EnemyEpoch,
	baseSequence: number,
	snapshotId: number,
	chunkCount: number,
	totalEntries: number,
}

export type SnapshotBeginMessage = SnapshotBoundaryMessage
export type SnapshotEndMessage = SnapshotBoundaryMessage

export type SnapshotChunkMessage = {
	kind: "SnapshotChunk",
	matchId: Ids.MatchId,
	enemyEpoch: EnemyEpoch,
	baseSequence: number,
	snapshotId: number,
	chunkIndex: number,
	entries: { EnemyStateEntry },
}

export type EnemyReplicationMessage =
	StateBatchMessage
	| DespawnBatchMessage
	| SnapshotBoundaryMessage
	| SnapshotChunkMessage

export type EnemySnapshotReceipt = {
	matchId: Ids.MatchId,
	enemyEpoch: EnemyEpoch,
	baseSequence: number,
	snapshotId: number,
	chunkCount: number,
	totalEntries: number,
}

local GET_ENEMY_SNAPSHOT_ENDPOINT = "GetEnemySnapshot"
local ENEMY_REPLICATION_ENDPOINT = "EnemyReplication"

local SPAWN_BATCH_KIND = "SpawnBatch"
local CORRECTION_BATCH_KIND = "CorrectionBatch"
local STATE_CHANGE_BATCH_KIND = "StateChangeBatch"
local DESPAWN_BATCH_KIND = "DespawnBatch"
local SNAPSHOT_BEGIN_KIND = "SnapshotBegin"
local SNAPSHOT_CHUNK_KIND = "SnapshotChunk"
local SNAPSHOT_END_KIND = "SnapshotEnd"

local MAX_ACTIVE_ENEMIES = 128
local MAX_LIFETIME_ENEMIES = 4_096
local MAX_ENEMY_EPOCH = 4_096
local MAX_RUNTIME_ENEMY_ID = 4_096
local MAX_ENTRIES_PER_MESSAGE = 8
local MAX_SNAPSHOT_CHUNKS = 16
local MAX_SNAPSHOT_ENTRIES = 128
local MAX_SNAPSHOT_ID = 16
local MAX_CURRENT_SNAPSHOT_ASSEMBLIES = 1
local MAX_BUFFERED_DELTA_MESSAGES = 32
local MAX_PENDING_CAUSAL_ENTRIES_PER_ENEMY = 3
local MAX_PENDING_CAUSAL_ENTRIES = 384
local MAX_DELTA_MESSAGES_PER_FLUSH = 12
local MAX_BROADCAST_RECIPIENTS = 4
local MAX_LIFETIME_DELTA_MESSAGES = 131_072
local MAX_LIFETIME_SNAPSHOT_MESSAGES = 160
local MAX_SNAPSHOT_REQUESTS_PER_PLAYER = 2
local MAX_CLIENT_SNAPSHOT_ATTEMPTS = 2
local PUBLICATION_INTERVAL_SECONDS = 0.1
local SNAPSHOT_RECEIPT_TIMEOUT_SECONDS = 2
local MAX_LANE_ID_BYTES = 64
local MAX_PATH_DISTANCE = 32_768
local MAX_SEGMENT_INDEX = 257
local MAX_COORDINATE = 100_000
local MIN_SEGMENT_DISTANCE = 0.01
local MAX_SEGMENT_DISTANCE = 512
local POSITION_TOLERANCE = 1e-6
-- Reliable RemoteEvent transport quantizes arbitrary CFrame rotations. Accepted
-- wire drift is discarded by canonicalStateEntry before state reaches consumers.
local WIRE_CFRAME_COMPONENT_TOLERANCE = 1e-4
local PARALLEL_TOLERANCE = 1e-6
local MAX_FINITE_NUMBER = 1.7976931348623157e308
local MAX_ENEMY_REVISION = Validation.MAX_SAFE_INTEGER
local MAX_REPLICATION_SEQUENCE = Validation.MAX_SAFE_INTEGER
local MAX_SNAPSHOT_BASE_SEQUENCE = Validation.MAX_SAFE_INTEGER

local POSITIVE_SEQUENCE_VALIDATOR = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)
local BASE_SEQUENCE_VALIDATOR = PayloadValidation.integer(0, Validation.MAX_SAFE_INTEGER)
local ENEMY_EPOCH_VALIDATOR = PayloadValidation.integer(1, MAX_ENEMY_EPOCH)
local RUNTIME_ENEMY_ID_VALIDATOR = PayloadValidation.integer(1, MAX_RUNTIME_ENEMY_ID)
local SNAPSHOT_ID_VALIDATOR = PayloadValidation.integer(1, MAX_SNAPSHOT_ID)
local SNAPSHOT_CHUNK_COUNT_VALIDATOR = PayloadValidation.integer(0, MAX_SNAPSHOT_CHUNKS)
local SNAPSHOT_CHUNK_INDEX_VALIDATOR = PayloadValidation.integer(1, MAX_SNAPSHOT_CHUNKS)
local SNAPSHOT_ENTRY_COUNT_VALIDATOR = PayloadValidation.integer(0, MAX_SNAPSHOT_ENTRIES)
local NONNEGATIVE_FINITE_NUMBER_VALIDATOR = PayloadValidation.number(0, MAX_FINITE_NUMBER)
local PATH_DISTANCE_VALIDATOR = PayloadValidation.number(0, MAX_PATH_DISTANCE)

local STATE_BATCH_KIND_VALIDATOR = PayloadValidation.enum({
	SPAWN_BATCH_KIND,
	CORRECTION_BATCH_KIND,
	STATE_CHANGE_BATCH_KIND,
})
local SNAPSHOT_BOUNDARY_KIND_VALIDATOR = PayloadValidation.enum({
	SNAPSHOT_BEGIN_KIND,
	SNAPSHOT_END_KIND,
})

local ENEMY_STATE_ENTRY_VALIDATOR = PayloadValidation.record({
	runtimeEnemyId = RUNTIME_ENEMY_ID_VALIDATOR,
	enemyId = PayloadValidation.id("enemy"),
	laneId = PayloadValidation.string(MAX_LANE_ID_BYTES, 1),
	revision = POSITIVE_SEQUENCE_VALIDATOR,
	lifecycle = PayloadValidation.enum({ "Active", "EndpointResolved" }),
	pathProgress = PATH_DISTANCE_VALIDATOR,
	currentHealth = NONNEGATIVE_FINITE_NUMBER_VALIDATOR,
	maximumHealth = NONNEGATIVE_FINITE_NUMBER_VALIDATOR,
	slowMultiplier = PayloadValidation.number(0, 1),
	spawnServerTime = NONNEGATIVE_FINITE_NUMBER_VALIDATOR,
	sampleServerTime = NONNEGATIVE_FINITE_NUMBER_VALIDATOR,
	worldCFrame = PayloadValidation.cframe(),
	effectiveSpeed = NONNEGATIVE_FINITE_NUMBER_VALIDATOR,
	segmentIndex = PayloadValidation.integer(1, MAX_SEGMENT_INDEX),
	segmentStartDistance = PATH_DISTANCE_VALIDATOR,
	segmentEndDistance = PATH_DISTANCE_VALIDATOR,
	segmentStartPosition = PayloadValidation.vector3(),
	segmentEndPosition = PayloadValidation.vector3(),
})

local DESPAWN_ENTRY_VALIDATOR = PayloadValidation.record({
	runtimeEnemyId = RUNTIME_ENEMY_ID_VALIDATOR,
	revision = POSITIVE_SEQUENCE_VALIDATOR,
	sampleServerTime = NONNEGATIVE_FINITE_NUMBER_VALIDATOR,
	reason = PayloadValidation.enum({ "Manual", "Endpoint" }),
})

local STATE_ENTRY_ARRAY_VALIDATOR = PayloadValidation.array(ENEMY_STATE_ENTRY_VALIDATOR, MAX_ENTRIES_PER_MESSAGE)
local DESPAWN_ENTRY_ARRAY_VALIDATOR = PayloadValidation.array(DESPAWN_ENTRY_VALIDATOR, MAX_ENTRIES_PER_MESSAGE)

-- The wire has seven tags but only four structural shapes. Keeping the three
-- full-state delta tags in one branch prevents the shared union node budget
-- from walking an eight-entry state batch three times before checking `kind`.
local STATE_BATCH_VALIDATOR = PayloadValidation.record({
	kind = STATE_BATCH_KIND_VALIDATOR,
	matchId = PayloadValidation.id("match"),
	enemyEpoch = ENEMY_EPOCH_VALIDATOR,
	sequence = POSITIVE_SEQUENCE_VALIDATOR,
	entries = STATE_ENTRY_ARRAY_VALIDATOR,
})

local DESPAWN_BATCH_VALIDATOR = PayloadValidation.record({
	kind = PayloadValidation.enum({ DESPAWN_BATCH_KIND }),
	matchId = PayloadValidation.id("match"),
	enemyEpoch = ENEMY_EPOCH_VALIDATOR,
	sequence = POSITIVE_SEQUENCE_VALIDATOR,
	entries = DESPAWN_ENTRY_ARRAY_VALIDATOR,
})

local SNAPSHOT_CHUNK_VALIDATOR = PayloadValidation.record({
	kind = PayloadValidation.enum({ SNAPSHOT_CHUNK_KIND }),
	matchId = PayloadValidation.id("match"),
	enemyEpoch = ENEMY_EPOCH_VALIDATOR,
	baseSequence = BASE_SEQUENCE_VALIDATOR,
	snapshotId = SNAPSHOT_ID_VALIDATOR,
	chunkIndex = SNAPSHOT_CHUNK_INDEX_VALIDATOR,
	entries = STATE_ENTRY_ARRAY_VALIDATOR,
})

local SNAPSHOT_BOUNDARY_VALIDATOR = PayloadValidation.record({
	kind = SNAPSHOT_BOUNDARY_KIND_VALIDATOR,
	matchId = PayloadValidation.id("match"),
	enemyEpoch = ENEMY_EPOCH_VALIDATOR,
	baseSequence = BASE_SEQUENCE_VALIDATOR,
	snapshotId = SNAPSHOT_ID_VALIDATOR,
	chunkCount = SNAPSHOT_CHUNK_COUNT_VALIDATOR,
	totalEntries = SNAPSHOT_ENTRY_COUNT_VALIDATOR,
})

local GetEnemySnapshotPayloadSchema = PayloadValidation.schema(PayloadValidation.record({}))
local EnemyStateEntrySchema = PayloadValidation.schema(ENEMY_STATE_ENTRY_VALIDATOR)
local DespawnEntrySchema = PayloadValidation.schema(DESPAWN_ENTRY_VALIDATOR)
local EnemySnapshotReceiptSchema = PayloadValidation.schema(PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	enemyEpoch = ENEMY_EPOCH_VALIDATOR,
	baseSequence = BASE_SEQUENCE_VALIDATOR,
	snapshotId = SNAPSHOT_ID_VALIDATOR,
	chunkCount = SNAPSHOT_CHUNK_COUNT_VALIDATOR,
	totalEntries = SNAPSHOT_ENTRY_COUNT_VALIDATOR,
}))
local EnemyReplicationSchema = PayloadValidation.schema(PayloadValidation.union({
	STATE_BATCH_VALIDATOR,
	DESPAWN_BATCH_VALIDATOR,
	SNAPSHOT_CHUNK_VALIDATOR,
	SNAPSHOT_BOUNDARY_VALIDATOR,
}))

local function issue(
	code: Validation.Code,
	path: { Validation.PathSegment },
	message: string
): Result.Failure<Validation.Issue>
	return Result.err(Validation.issue(code, path, message))
end

local function entryPath(index: number?, fieldName: string): { Validation.PathSegment }
	if index == nil then
		return { "payload", fieldName }
	end
	return { "payload", "entries", index, fieldName }
end

local function isBoundedPosition(position: Vector3): boolean
	return math.abs(position.X) <= MAX_COORDINATE
		and math.abs(position.Y) <= MAX_COORDINATE
		and math.abs(position.Z) <= MAX_COORDINATE
end

local function canonicalCFrame(position: Vector3, tangent: Vector3): CFrame
	local direction = tangent.Unit
	local upHint = Vector3.yAxis
	if math.abs(direction:Dot(upHint)) >= 1 - PARALLEL_TOLERANCE then
		upHint = Vector3.xAxis
	end
	local right = direction:Cross(upHint).Unit
	local up = right:Cross(direction).Unit
	return CFrame.fromMatrix(position, right, up, -direction)
end

local function cframesWithinTolerance(left: CFrame, right: CFrame): boolean
	local leftComponents = table.pack(left:GetComponents())
	local rightComponents = table.pack(right:GetComponents())
	if leftComponents.n ~= 12 or rightComponents.n ~= 12 then
		return false
	end
	for index = 1, 12 do
		local tolerance = if index <= 3 then POSITION_TOLERANCE else WIRE_CFRAME_COMPONENT_TOLERANCE
		if math.abs((leftComponents[index] :: number) - (rightComponents[index] :: number)) > tolerance then
			return false
		end
	end
	return true
end

local function canonicalStateEntry(entry: EnemyStateEntry): EnemyStateEntry
	local segmentDistance = entry.segmentEndDistance - entry.segmentStartDistance
	local boundedProgress = math.clamp(entry.pathProgress, entry.segmentStartDistance, entry.segmentEndDistance)
	local alpha = (boundedProgress - entry.segmentStartDistance) / segmentDistance
	local position = entry.segmentStartPosition:Lerp(entry.segmentEndPosition, alpha)
	local worldCFrame = canonicalCFrame(position, entry.segmentEndPosition - entry.segmentStartPosition)
	return table.freeze({
		runtimeEnemyId = entry.runtimeEnemyId,
		enemyId = entry.enemyId,
		laneId = entry.laneId,
		revision = entry.revision,
		lifecycle = entry.lifecycle,
		pathProgress = entry.pathProgress,
		currentHealth = entry.currentHealth,
		maximumHealth = entry.maximumHealth,
		slowMultiplier = entry.slowMultiplier,
		spawnServerTime = entry.spawnServerTime,
		sampleServerTime = entry.sampleServerTime,
		worldCFrame = worldCFrame,
		effectiveSpeed = entry.effectiveSpeed,
		segmentIndex = entry.segmentIndex,
		segmentStartDistance = entry.segmentStartDistance,
		segmentEndDistance = entry.segmentEndDistance,
		segmentStartPosition = entry.segmentStartPosition,
		segmentEndPosition = entry.segmentEndPosition,
	})
end

local function canonicalStateEntries(entries: { EnemyStateEntry }): { EnemyStateEntry }
	local canonical = table.create(#entries)
	for index, entry in entries do
		canonical[index] = canonicalStateEntry(entry)
	end
	return table.freeze(canonical)
end

local function validateStateEntry(
	entry: EnemyStateEntry,
	index: number?,
	kind: StateBatchKind | "SnapshotChunk"
): Result.Failure<Validation.Issue>?
	if entry.maximumHealth <= 0 or entry.currentHealth > entry.maximumHealth then
		return issue(
			"INVALID_TOTAL",
			entryPath(index, "currentHealth"),
			"Current health must not exceed a positive authoritative maximum"
		)
	end
	if entry.sampleServerTime < entry.spawnServerTime then
		return issue(
			"INVALID_ORDER",
			entryPath(index, "sampleServerTime"),
			"Sample server time must not precede spawn server time"
		)
	end
	if entry.slowMultiplier == 0 and entry.effectiveSpeed ~= 0 then
		return issue(
			"INVALID_TOTAL",
			entryPath(index, "effectiveSpeed"),
			"A fully stopped enemy must have zero effective speed"
		)
	end

	local segmentDistance = entry.segmentEndDistance - entry.segmentStartDistance
	if segmentDistance <= 0 then
		return issue(
			"INVALID_ORDER",
			entryPath(index, "segmentEndDistance"),
			"Segment end distance must be strictly greater than segment start distance"
		)
	end
	local distanceTolerance = math.max(1, entry.segmentEndDistance) * 1e-9
	if
		entry.pathProgress < entry.segmentStartDistance - distanceTolerance
		or entry.pathProgress > entry.segmentEndDistance + distanceTolerance
	then
		return issue(
			"INVALID_REFERENCE",
			entryPath(index, "pathProgress"),
			"Path progress must lie inside the advertised authoritative segment"
		)
	end

	if not isBoundedPosition(entry.segmentStartPosition) then
		return issue(
			"OUT_OF_RANGE",
			entryPath(index, "segmentStartPosition"),
			"Segment start position exceeds the fixed world-coordinate bounds"
		)
	end
	if not isBoundedPosition(entry.segmentEndPosition) then
		return issue(
			"OUT_OF_RANGE",
			entryPath(index, "segmentEndPosition"),
			"Segment end position exceeds the fixed world-coordinate bounds"
		)
	end

	local tangent = entry.segmentEndPosition - entry.segmentStartPosition
	local tangentMagnitude = tangent.Magnitude
	if tangentMagnitude < MIN_SEGMENT_DISTANCE or tangentMagnitude > MAX_SEGMENT_DISTANCE then
		return issue(
			"OUT_OF_RANGE",
			entryPath(index, "segmentEndPosition"),
			"Segment geometry is outside the fixed detached-lane distance bounds"
		)
	end
	if math.abs(tangentMagnitude - segmentDistance) > distanceTolerance then
		return issue(
			"INVALID_TOTAL",
			entryPath(index, "segmentEndDistance"),
			"Segment cumulative distance must equal its Euclidean geometry"
		)
	end

	local boundedProgress = math.clamp(entry.pathProgress, entry.segmentStartDistance, entry.segmentEndDistance)
	local alpha = (boundedProgress - entry.segmentStartDistance) / segmentDistance
	local expectedPosition = entry.segmentStartPosition:Lerp(entry.segmentEndPosition, alpha)
	local expectedCFrame = canonicalCFrame(expectedPosition, tangent)
	if
		not isBoundedPosition(entry.worldCFrame.Position)
		or not cframesWithinTolerance(entry.worldCFrame, expectedCFrame)
	then
		return issue(
			"INVALID_REFERENCE",
			entryPath(index, "worldCFrame"),
			"World CFrame must be the canonical sample of the advertised segment"
		)
	end

	if entry.lifecycle == "EndpointResolved" then
		if math.abs(entry.pathProgress - entry.segmentEndDistance) > distanceTolerance then
			return issue(
				"INVALID_REFERENCE",
				entryPath(index, "lifecycle"),
				"Endpoint-resolved state must be sampled at the segment endpoint"
			)
		end
	end
	if kind == SNAPSHOT_CHUNK_KIND and entry.lifecycle ~= "Active" then
		return issue("INVALID_REFERENCE", entryPath(index, "lifecycle"), "Snapshots may contain only active enemies")
	end

	if (kind == SPAWN_BATCH_KIND or kind == CORRECTION_BATCH_KIND) and entry.lifecycle ~= "Active" then
		return issue(
			"INVALID_REFERENCE",
			entryPath(index, "lifecycle"),
			"Spawn and correction batches may contain only active enemies"
		)
	end
	return nil
end

local function validateStateEntries(
	entries: { EnemyStateEntry },
	kind: StateBatchKind | "SnapshotChunk"
): Result.Failure<Validation.Issue>?
	local seen: { [number]: boolean } = {}
	local previousRuntimeEnemyId: number? = nil
	for index, entry in entries do
		if seen[entry.runtimeEnemyId] then
			return issue(
				"DUPLICATE_VALUE",
				entryPath(index, "runtimeEnemyId"),
				"A replication message may represent one runtime enemy at most once"
			)
		end
		seen[entry.runtimeEnemyId] = true
		if
			kind == SNAPSHOT_CHUNK_KIND
			and previousRuntimeEnemyId ~= nil
			and entry.runtimeEnemyId < previousRuntimeEnemyId
		then
			return issue(
				"INVALID_ORDER",
				entryPath(index, "runtimeEnemyId"),
				"Snapshot entries must be ordered by increasing RuntimeEnemyId"
			)
		end
		previousRuntimeEnemyId = entry.runtimeEnemyId

		local entryFailure = validateStateEntry(entry, index, kind)
		if entryFailure ~= nil then
			return entryFailure
		end
	end
	return nil
end

local function validateDespawnEntries(entries: { DespawnEntry }): Result.Failure<Validation.Issue>?
	local seen: { [number]: boolean } = {}
	for index, entry in entries do
		if seen[entry.runtimeEnemyId] then
			return issue(
				"DUPLICATE_VALUE",
				entryPath(index, "runtimeEnemyId"),
				"A despawn batch may represent one runtime enemy at most once"
			)
		end
		seen[entry.runtimeEnemyId] = true
	end
	return nil
end

local function expectedChunkCount(totalEntries: number): number
	return math.ceil(totalEntries / MAX_ENTRIES_PER_MESSAGE)
end

local function validateSnapshotCounts(
	chunkCount: number,
	totalEntries: number,
	path: { Validation.PathSegment }
): Result.Failure<Validation.Issue>?
	if chunkCount ~= expectedChunkCount(totalEntries) then
		return issue("INVALID_TOTAL", path, "Snapshot chunk count must exactly cover the declared active entry count")
	end
	return nil
end

local EnemyProtocol = {
	GET_ENEMY_SNAPSHOT_ENDPOINT = GET_ENEMY_SNAPSHOT_ENDPOINT,
	ENEMY_REPLICATION_ENDPOINT = ENEMY_REPLICATION_ENDPOINT,
	SPAWN_BATCH_KIND = SPAWN_BATCH_KIND,
	CORRECTION_BATCH_KIND = CORRECTION_BATCH_KIND,
	STATE_CHANGE_BATCH_KIND = STATE_CHANGE_BATCH_KIND,
	DESPAWN_BATCH_KIND = DESPAWN_BATCH_KIND,
	SNAPSHOT_BEGIN_KIND = SNAPSHOT_BEGIN_KIND,
	SNAPSHOT_CHUNK_KIND = SNAPSHOT_CHUNK_KIND,
	SNAPSHOT_END_KIND = SNAPSHOT_END_KIND,
	REPLICATION_KINDS = table.freeze({
		SPAWN_BATCH_KIND,
		CORRECTION_BATCH_KIND,
		STATE_CHANGE_BATCH_KIND,
		DESPAWN_BATCH_KIND,
		SNAPSHOT_BEGIN_KIND,
		SNAPSHOT_CHUNK_KIND,
		SNAPSHOT_END_KIND,
	}),
	MAX_ACTIVE_ENEMIES = MAX_ACTIVE_ENEMIES,
	MAX_LIFETIME_ENEMIES = MAX_LIFETIME_ENEMIES,
	MAX_ENEMY_EPOCH = MAX_ENEMY_EPOCH,
	MAX_RUNTIME_ENEMY_ID = MAX_RUNTIME_ENEMY_ID,
	MAX_ENTRIES_PER_MESSAGE = MAX_ENTRIES_PER_MESSAGE,
	MAX_SNAPSHOT_CHUNKS = MAX_SNAPSHOT_CHUNKS,
	MAX_SNAPSHOT_ENTRIES = MAX_SNAPSHOT_ENTRIES,
	MAX_SNAPSHOT_ID = MAX_SNAPSHOT_ID,
	MAX_CURRENT_SNAPSHOT_ASSEMBLIES = MAX_CURRENT_SNAPSHOT_ASSEMBLIES,
	MAX_BUFFERED_DELTA_MESSAGES = MAX_BUFFERED_DELTA_MESSAGES,
	MAX_PENDING_CAUSAL_ENTRIES_PER_ENEMY = MAX_PENDING_CAUSAL_ENTRIES_PER_ENEMY,
	MAX_PENDING_CAUSAL_ENTRIES = MAX_PENDING_CAUSAL_ENTRIES,
	MAX_DELTA_MESSAGES_PER_FLUSH = MAX_DELTA_MESSAGES_PER_FLUSH,
	MAX_BROADCAST_RECIPIENTS = MAX_BROADCAST_RECIPIENTS,
	MAX_LIFETIME_DELTA_MESSAGES = MAX_LIFETIME_DELTA_MESSAGES,
	MAX_LIFETIME_SNAPSHOT_MESSAGES = MAX_LIFETIME_SNAPSHOT_MESSAGES,
	MAX_SNAPSHOT_REQUESTS_PER_PLAYER = MAX_SNAPSHOT_REQUESTS_PER_PLAYER,
	MAX_CLIENT_SNAPSHOT_ATTEMPTS = MAX_CLIENT_SNAPSHOT_ATTEMPTS,
	PUBLICATION_INTERVAL_SECONDS = PUBLICATION_INTERVAL_SECONDS,
	SNAPSHOT_RECEIPT_TIMEOUT_SECONDS = SNAPSHOT_RECEIPT_TIMEOUT_SECONDS,
	MAX_LANE_ID_BYTES = MAX_LANE_ID_BYTES,
	MAX_PATH_DISTANCE = MAX_PATH_DISTANCE,
	MAX_SEGMENT_INDEX = MAX_SEGMENT_INDEX,
	MAX_COORDINATE = MAX_COORDINATE,
	POSITION_TOLERANCE = POSITION_TOLERANCE,
	WIRE_CFRAME_COMPONENT_TOLERANCE = WIRE_CFRAME_COMPONENT_TOLERANCE,
	MAX_ENEMY_REVISION = MAX_ENEMY_REVISION,
	MAX_REPLICATION_SEQUENCE = MAX_REPLICATION_SEQUENCE,
	MAX_SNAPSHOT_BASE_SEQUENCE = MAX_SNAPSHOT_BASE_SEQUENCE,
	GetEnemySnapshotPayloadSchema = GetEnemySnapshotPayloadSchema,
	EnemyStateEntrySchema = EnemyStateEntrySchema,
	DespawnEntrySchema = DespawnEntrySchema,
	EnemySnapshotReceiptSchema = EnemySnapshotReceiptSchema,
	EnemyReplicationSchema = EnemyReplicationSchema,
}

function EnemyProtocol.validateEnemyStateEntry(value: unknown): Result.Result<EnemyStateEntry, Validation.Issue>
	local schemaResult = EnemyStateEntrySchema:validate(value)
	if not schemaResult.ok then
		return Result.err(schemaResult.error)
	end

	local entry = schemaResult.value :: EnemyStateEntry
	local entryFailure = validateStateEntry(entry, nil, STATE_CHANGE_BATCH_KIND)
	if entryFailure ~= nil then
		return entryFailure
	end
	return Result.ok(canonicalStateEntry(entry))
end

function EnemyProtocol.validateDespawnEntry(value: unknown): Result.Result<DespawnEntry, Validation.Issue>
	local schemaResult = DespawnEntrySchema:validate(value)
	if not schemaResult.ok then
		return Result.err(schemaResult.error)
	end
	return Result.ok(schemaResult.value :: DespawnEntry)
end

function EnemyProtocol.validateEnemyReplication(
	value: unknown
): Result.Result<EnemyReplicationMessage, Validation.Issue>
	local schemaResult = EnemyReplicationSchema:validate(value)
	if not schemaResult.ok then
		return Result.err(schemaResult.error)
	end

	local message = schemaResult.value :: EnemyReplicationMessage
	if
		message.kind == SPAWN_BATCH_KIND
		or message.kind == CORRECTION_BATCH_KIND
		or message.kind == STATE_CHANGE_BATCH_KIND
	then
		local stateMessage = message :: StateBatchMessage
		local entriesFailure = validateStateEntries(stateMessage.entries, stateMessage.kind)
		if entriesFailure ~= nil then
			return entriesFailure
		end
		return Result.ok(table.freeze({
			kind = stateMessage.kind,
			matchId = stateMessage.matchId,
			enemyEpoch = stateMessage.enemyEpoch,
			sequence = stateMessage.sequence,
			entries = canonicalStateEntries(stateMessage.entries),
		}))
	elseif message.kind == DESPAWN_BATCH_KIND then
		local entriesFailure = validateDespawnEntries((message :: DespawnBatchMessage).entries)
		if entriesFailure ~= nil then
			return entriesFailure
		end
	elseif message.kind == SNAPSHOT_CHUNK_KIND then
		local chunk = message :: SnapshotChunkMessage
		local entriesFailure = validateStateEntries(chunk.entries, SNAPSHOT_CHUNK_KIND)
		if entriesFailure ~= nil then
			return entriesFailure
		end
		return Result.ok(table.freeze({
			kind = SNAPSHOT_CHUNK_KIND,
			matchId = chunk.matchId,
			enemyEpoch = chunk.enemyEpoch,
			baseSequence = chunk.baseSequence,
			snapshotId = chunk.snapshotId,
			chunkIndex = chunk.chunkIndex,
			entries = canonicalStateEntries(chunk.entries),
		}))
	else
		local boundary = message :: SnapshotBoundaryMessage
		local countsFailure =
			validateSnapshotCounts(boundary.chunkCount, boundary.totalEntries, { "payload", "chunkCount" })
		if countsFailure ~= nil then
			return countsFailure
		end
	end

	return Result.ok(message)
end

function EnemyProtocol.validateEnemySnapshotReceipt(
	value: unknown
): Result.Result<EnemySnapshotReceipt, Validation.Issue>
	local schemaResult = EnemySnapshotReceiptSchema:validate(value)
	if not schemaResult.ok then
		return Result.err(schemaResult.error)
	end

	local receipt = schemaResult.value :: EnemySnapshotReceipt
	local countsFailure = validateSnapshotCounts(receipt.chunkCount, receipt.totalEntries, {
		"payload",
		"chunkCount",
	})
	if countsFailure ~= nil then
		return countsFailure
	end
	return Result.ok(receipt)
end

return table.freeze(EnemyProtocol)
