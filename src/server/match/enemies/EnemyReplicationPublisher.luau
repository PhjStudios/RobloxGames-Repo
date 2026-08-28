--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type RuntimeEnemyId = number
export type CommitKind = "Spawn" | "Correction" | "StateChange" | "Despawn"
export type Operation =
	"new"
	| "preflightSpawn"
	| "preflightStateChange"
	| "preflightEndpoint"
	| "preflightManualDespawn"
	| "preflightDefeat"
	| "preflightStep"
	| "commitSpawn"
	| "commitStateChange"
	| "commitEndpoint"
	| "commitManualDespawn"
	| "commitDefeat"
	| "observeCorrection"
	| "advance"
	| "requestSnapshot"
	| "removePlayer"
	| "getMetrics"
	| "cleanup"

export type ErrorCode =
	"INVALID_ARGUMENT"
	| "INVALID_SNAPSHOT"
	| "INVALID_RECIPIENT"
	| "INVALID_PROVIDER"
	| "CAPACITY_EXCEEDED"
	| "ID_COLLISION"
	| "STALE_RUNTIME_ID"
	| "ILLEGAL_LIFECYCLE"
	| "REVISION_EXHAUSTED"
	| "SEQUENCE_EXHAUSTED"
	| "REENTRANT"
	| "FAULTED"
	| "CLEANED"
	| "INTERNAL_ERROR"

export type PublisherError = {
	code: ErrorCode,
	operation: Operation,
}

export type RecipientRecord = {
	recipient: unknown,
	userId: number,
}

export type Sender = (recipient: unknown, message: EnemyProtocol.EnemyReplicationMessage) -> boolean
export type GetRecipients = () -> unknown
export type SnapshotProvider = (runtimeEnemyIds: { RuntimeEnemyId }?) -> unknown

export type Dependencies = {
	sender: Sender,
	getRecipients: GetRecipients,
}

export type AdvanceOutcome = {
	flushOccurred: boolean,
	batchCount: number,
	entryCount: number,
	remainingPendingEntries: number,
	remainingDirtyCorrections: number,
}

export type Metrics = {
	activeRepresentationCount: number,
	lifetimeRepresentationCount: number,
	pendingEntryCount: number,
	dirtyCorrectionCount: number,
	terminalPendingCount: number,
	reservedFutureMessageCount: number,
	reservedOrdinaryMessageCount: number,
	deltaMessageCount: number,
	snapshotMessageCount: number,
	nextSequence: number,
	nextMutationOrdinal: number,
	nextSnapshotId: number,
	trackedRequestPlayerCount: number,
	senderCallCount: number,
	senderFailureCount: number,
	flushCount: number,
	retainsSender: boolean,
	retainsRecipientProvider: boolean,
	faulted: boolean,
	cleaned: boolean,
}

type RuntimeStateSnapshot = {
	runtimeEnemyId: RuntimeEnemyId,
	enemyId: Ids.EnemyId,
	laneId: string,
	pathProgress: number,
	currentHealth: number,
	maximumHealth: number,
	speedModifiers: {
		slowMultiplier: number,
	},
	spawnServerTime: number,
	sampleServerTime: number,
	lifecycle: "Active" | "EndpointResolved",
	revision: number,
	worldCFrame: CFrame,
	effectiveSpeed: number,
	segmentIndex: number,
	segmentStartDistance: number,
	segmentEndDistance: number,
	segmentStartPosition: Vector3,
	segmentEndPosition: Vector3,
}

type RuntimeDespawnSnapshot = {
	runtimeEnemyId: RuntimeEnemyId,
	enemyId: Ids.EnemyId,
	laneId: string,
	revision: number,
	lifecycle: "Despawned",
	reason: "Manual" | "Endpoint" | "Defeat",
	sampleServerTime: number,
}

type FundingKind = "Spawn" | "Endpoint" | "Despawn" | "Ordinary"

type PendingEntry = {
	kind: CommitKind,
	ordinal: number,
	runtimeEnemyId: RuntimeEnemyId,
	revision: number,
	state: EnemyProtocol.EnemyStateEntry?,
	despawn: EnemyProtocol.DespawnEntry?,
	funding: FundingKind,
}

type DirtyCorrection = {
	ordinal: number,
	state: EnemyProtocol.EnemyStateEntry?,
}

type Representation = {
	runtimeEnemyId: RuntimeEnemyId,
	lastRevision: number,
	active: boolean,
	spawnEmitted: boolean,
	spawnReserved: boolean,
	endpointReserved: boolean,
	despawnReserved: boolean,
	chain: { PendingEntry },
}

type Limits = {
	maxActive: number,
	maxLifetime: number,
	maxPendingEntries: number,
	maxEntriesPerMessage: number,
	maxBatchesPerFlush: number,
	maxRecipients: number,
	maxDeltaMessages: number,
	maxSnapshotMessages: number,
	maxSnapshotIds: number,
	maxSnapshotRequestsPerPlayer: number,
	publicationIntervalSeconds: number,
}

type LimitsOverride = {
	maxActive: number?,
	maxLifetime: number?,
	maxPendingEntries: number?,
	maxEntriesPerMessage: number?,
	maxBatchesPerFlush: number?,
	maxRecipients: number?,
	maxDeltaMessages: number?,
	maxSnapshotMessages: number?,
	maxSnapshotIds: number?,
	maxSnapshotRequestsPerPlayer: number?,
	publicationIntervalSeconds: number?,
}

type PublisherData = {
	matchId: Ids.MatchId?,
	enemyEpoch: number,
	sender: Sender?,
	getRecipients: GetRecipients?,
	limits: Limits,
	representations: { [RuntimeEnemyId]: Representation },
	dirtyCorrections: { [RuntimeEnemyId]: DirtyCorrection },
	requestCounts: { [any]: number },
	activeRepresentationCount: number,
	lifetimeRepresentationCount: number,
	pendingEntryCount: number,
	dirtyCorrectionCount: number,
	terminalPendingCount: number,
	reservedFutureMessageCount: number,
	reservedOrdinaryMessageCount: number,
	deltaMessageCount: number,
	snapshotMessageCount: number,
	nextSequence: number,
	nextMutationOrdinal: number,
	nextSnapshotId: number,
	elapsedSinceFlush: number,
	senderCallCount: number,
	senderFailureCount: number,
	flushCount: number,
	busy: boolean,
	cleanupRequested: boolean,
	faulted: boolean,
	cleaned: boolean,
}

local PublisherMethods = {}
PublisherMethods.__index = PublisherMethods

export type Publisher = typeof(setmetatable({} :: {}, PublisherMethods))
export type TestConstructor = (
	matchId: unknown,
	enemyEpoch: unknown,
	dependencies: unknown,
	limits: LimitsOverride?
) -> Result.Result<Publisher, PublisherError>

local DEFAULT_LIMITS: Limits = table.freeze({
	maxActive = EnemyProtocol.MAX_ACTIVE_ENEMIES,
	maxLifetime = EnemyProtocol.MAX_LIFETIME_ENEMIES,
	maxPendingEntries = EnemyProtocol.MAX_PENDING_CAUSAL_ENTRIES,
	maxEntriesPerMessage = EnemyProtocol.MAX_ENTRIES_PER_MESSAGE,
	maxBatchesPerFlush = EnemyProtocol.MAX_DELTA_MESSAGES_PER_FLUSH,
	maxRecipients = EnemyProtocol.MAX_BROADCAST_RECIPIENTS,
	maxDeltaMessages = EnemyProtocol.MAX_LIFETIME_DELTA_MESSAGES,
	maxSnapshotMessages = EnemyProtocol.MAX_LIFETIME_SNAPSHOT_MESSAGES,
	maxSnapshotIds = EnemyProtocol.MAX_SNAPSHOT_ID,
	maxSnapshotRequestsPerPlayer = EnemyProtocol.MAX_SNAPSHOT_REQUESTS_PER_PLAYER,
	publicationIntervalSeconds = EnemyProtocol.PUBLICATION_INTERVAL_SECONDS,
})

local STATE_INPUT_FIELDS: { [string]: boolean } = table.freeze({
	runtimeEnemyId = true,
	enemyId = true,
	laneId = true,
	pathProgress = true,
	currentHealth = true,
	maximumHealth = true,
	speedModifiers = true,
	spawnServerTime = true,
	sampleServerTime = true,
	lifecycle = true,
	revision = true,
	worldCFrame = true,
	effectiveSpeed = true,
	segmentIndex = true,
	segmentStartDistance = true,
	segmentEndDistance = true,
	segmentStartPosition = true,
	segmentEndPosition = true,
})

local SPEED_MODIFIER_FIELDS: { [string]: boolean } = table.freeze({
	slowMultiplier = true,
})

local DESPAWN_INPUT_FIELDS: { [string]: boolean } = table.freeze({
	runtimeEnemyId = true,
	enemyId = true,
	laneId = true,
	revision = true,
	lifecycle = true,
	reason = true,
	sampleServerTime = true,
})

local DEPENDENCY_FIELDS: { [string]: boolean } = table.freeze({
	sender = true,
	getRecipients = true,
})

local RECIPIENT_FIELDS: { [string]: boolean } = table.freeze({
	recipient = true,
	userId = true,
})

local LIMIT_FIELDS: { [string]: boolean } = table.freeze({
	maxActive = true,
	maxLifetime = true,
	maxPendingEntries = true,
	maxEntriesPerMessage = true,
	maxBatchesPerFlush = true,
	maxRecipients = true,
	maxDeltaMessages = true,
	maxSnapshotMessages = true,
	maxSnapshotIds = true,
	maxSnapshotRequestsPerPlayer = true,
	publicationIntervalSeconds = true,
})

local KIND_ORDER: { [CommitKind]: number } = table.freeze({
	Spawn = 1,
	Correction = 2,
	StateChange = 3,
	Despawn = 4,
})

local PUBLISHER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: PublisherData }

local EnemyReplicationPublisher = {
	MAX_ACTIVE_ENEMIES = EnemyProtocol.MAX_ACTIVE_ENEMIES,
	MAX_LIFETIME_ENEMIES = EnemyProtocol.MAX_LIFETIME_ENEMIES,
	MAX_PENDING_CAUSAL_ENTRIES = EnemyProtocol.MAX_PENDING_CAUSAL_ENTRIES,
	MAX_ENTRIES_PER_MESSAGE = EnemyProtocol.MAX_ENTRIES_PER_MESSAGE,
	MAX_DELTA_MESSAGES_PER_FLUSH = EnemyProtocol.MAX_DELTA_MESSAGES_PER_FLUSH,
	MAX_BROADCAST_RECIPIENTS = EnemyProtocol.MAX_BROADCAST_RECIPIENTS,
	MAX_LIFETIME_DELTA_MESSAGES = EnemyProtocol.MAX_LIFETIME_DELTA_MESSAGES,
	MAX_LIFETIME_SNAPSHOT_MESSAGES = EnemyProtocol.MAX_LIFETIME_SNAPSHOT_MESSAGES,
	MAX_SNAPSHOT_REQUESTS_PER_PLAYER = EnemyProtocol.MAX_SNAPSHOT_REQUESTS_PER_PLAYER,
	PUBLICATION_INTERVAL_SECONDS = EnemyProtocol.PUBLICATION_INTERVAL_SECONDS,
	newForTests = nil :: TestConstructor?,
}

local function makeError(code: ErrorCode, operation: Operation): PublisherError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<PublisherError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): PublisherData
	if type(value) ~= "table" then
		error("[ATD_ENEMY_REPLICATION_PUBLISHER][code=INVALID_CONTEXT]", 0)
	end
	local data = PUBLISHER_DATA[value :: any]
	if data == nil then
		error("[ATD_ENEMY_REPLICATION_PUBLISHER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and Validation.isFiniteNumber(value :: number)
end

local function isSafePositiveInteger(value: unknown, maximum: number): boolean
	return type(value) == "number"
		and Validation.isSafeInteger(value :: number)
		and (value :: number) >= 1
		and (value :: number) <= maximum
end

local function hasExactFields(value: { [any]: unknown }, fields: { [string]: boolean }): boolean
	local count = 0
	for fieldName in next, value do
		count += 1
		if type(fieldName) ~= "string" or fields[fieldName] ~= true then
			return false
		end
	end
	local expected = 0
	for _ in fields do
		expected += 1
	end
	return count == expected
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, any)
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

local function successValue(value: unknown): unknown?
	if type(value) ~= "table" or (value :: any).ok ~= true then
		return nil
	end
	return (value :: any).value
end

local function validateLive(data: PublisherData, operation: Operation, mutation: boolean): PublisherError?
	if data.cleaned then
		return makeError("CLEANED", operation)
	end
	if mutation and data.busy then
		return makeError("REENTRANT", operation)
	end
	if mutation and data.faulted then
		return makeError("FAULTED", operation)
	end
	return nil
end

local function failClosed(data: PublisherData)
	data.faulted = true
end

local function validateRuntimeStateInput(value: unknown): RuntimeStateSnapshot?
	if
		type(value) ~= "table"
		or not table.isfrozen(value :: any)
		or getmetatable(value :: any) ~= nil
		or not hasExactFields(value :: { [any]: unknown }, STATE_INPUT_FIELDS)
	then
		return nil
	end
	local snapshot = value :: any
	local modifiers = snapshot.speedModifiers
	if
		type(modifiers) ~= "table"
		or not table.isfrozen(modifiers)
		or getmetatable(modifiers) ~= nil
		or not hasExactFields(modifiers, SPEED_MODIFIER_FIELDS)
	then
		return nil
	end
	return snapshot :: RuntimeStateSnapshot
end

local function validateRuntimeDespawnInput(value: unknown): RuntimeDespawnSnapshot?
	if
		type(value) ~= "table"
		or not table.isfrozen(value :: any)
		or getmetatable(value :: any) ~= nil
		or not hasExactFields(value :: { [any]: unknown }, DESPAWN_INPUT_FIELDS)
	then
		return nil
	end
	return value :: RuntimeDespawnSnapshot
end

local function canonicalState(value: unknown): EnemyProtocol.EnemyStateEntry?
	local snapshot = validateRuntimeStateInput(value)
	if snapshot == nil then
		return nil
	end
	local candidate = table.freeze({
		runtimeEnemyId = snapshot.runtimeEnemyId,
		enemyId = snapshot.enemyId,
		laneId = snapshot.laneId,
		revision = snapshot.revision,
		lifecycle = snapshot.lifecycle,
		pathProgress = snapshot.pathProgress,
		currentHealth = snapshot.currentHealth,
		maximumHealth = snapshot.maximumHealth,
		slowMultiplier = snapshot.speedModifiers.slowMultiplier,
		spawnServerTime = snapshot.spawnServerTime,
		sampleServerTime = snapshot.sampleServerTime,
		worldCFrame = snapshot.worldCFrame,
		effectiveSpeed = snapshot.effectiveSpeed,
		segmentIndex = snapshot.segmentIndex,
		segmentStartDistance = snapshot.segmentStartDistance,
		segmentEndDistance = snapshot.segmentEndDistance,
		segmentStartPosition = snapshot.segmentStartPosition,
		segmentEndPosition = snapshot.segmentEndPosition,
	})
	local result = EnemyProtocol.validateEnemyStateEntry(candidate)
	if not result.ok then
		return nil
	end
	return result.value
end

local function canonicalDespawn(value: unknown): EnemyProtocol.DespawnEntry?
	local snapshot = validateRuntimeDespawnInput(value)
	if snapshot == nil or snapshot.lifecycle ~= "Despawned" then
		return nil
	end
	local candidate = table.freeze({
		runtimeEnemyId = snapshot.runtimeEnemyId,
		revision = snapshot.revision,
		sampleServerTime = snapshot.sampleServerTime,
		reason = snapshot.reason,
	})
	local result = EnemyProtocol.validateDespawnEntry(candidate)
	if not result.ok then
		return nil
	end
	return result.value
end

local function unusedMessageCapacity(data: PublisherData): number
	return data.limits.maxDeltaMessages
		- data.deltaMessageCount
		- data.reservedFutureMessageCount
		- data.reservedOrdinaryMessageCount
end

local function unusedSequenceCapacity(data: PublisherData): number
	return Validation.MAX_SAFE_INTEGER
		- (data.nextSequence - 1)
		- data.reservedFutureMessageCount
		- data.reservedOrdinaryMessageCount
end

local function canAdvanceOrdinal(data: PublisherData, count: number): boolean
	return count >= 0 and data.nextMutationOrdinal <= Validation.MAX_SAFE_INTEGER - count
end

local function takeOrdinal(data: PublisherData): number
	local ordinal = data.nextMutationOrdinal
	data.nextMutationOrdinal += 1
	return ordinal
end

local function findEntry(record: Representation, kind: CommitKind): (PendingEntry?, number?)
	for index, entry in record.chain do
		if entry.kind == kind then
			return entry, index
		end
	end
	return nil, nil
end

local function insertEntry(data: PublisherData, record: Representation, entry: PendingEntry)
	table.insert(record.chain, entry)
	data.pendingEntryCount += 1
	table.sort(record.chain, function(left: PendingEntry, right: PendingEntry): boolean
		return left.ordinal < right.ordinal
	end)
end

local function releaseFunding(data: PublisherData, record: Representation, entry: PendingEntry)
	if entry.funding == "Ordinary" then
		data.reservedOrdinaryMessageCount -= 1
	elseif entry.funding == "Spawn" then
		if record.spawnReserved then
			record.spawnReserved = false
			data.reservedFutureMessageCount -= 1
		end
	elseif entry.funding == "Endpoint" then
		if record.endpointReserved then
			record.endpointReserved = false
			data.reservedFutureMessageCount -= 1
		end
	elseif entry.funding == "Despawn" and record.despawnReserved then
		record.despawnReserved = false
		data.reservedFutureMessageCount -= 1
	end
end

local function removeEntryAt(
	data: PublisherData,
	record: Representation,
	index: number,
	releaseReservation: boolean
): PendingEntry
	local entry = table.remove(record.chain, index) :: PendingEntry
	data.pendingEntryCount -= 1
	if releaseReservation then
		releaseFunding(data, record, entry)
	end
	return entry
end

local function removeEntryObject(
	data: PublisherData,
	record: Representation,
	target: PendingEntry,
	releaseReservation: boolean
): boolean
	for index, entry in record.chain do
		if entry == target then
			removeEntryAt(data, record, index, releaseReservation)
			return true
		end
	end
	return false
end

local function removeActiveEntries(data: PublisherData, record: Representation)
	local index = #record.chain
	while index >= 1 do
		local entry = record.chain[index]
		if entry.kind == "StateChange" or entry.kind == "Correction" then
			removeEntryAt(data, record, index, true)
		end
		index -= 1
	end
end

local function clearDirty(data: PublisherData, runtimeEnemyId: RuntimeEnemyId)
	if data.dirtyCorrections[runtimeEnemyId] ~= nil then
		data.dirtyCorrections[runtimeEnemyId] = nil
		data.dirtyCorrectionCount -= 1
	end
end

local function reserveOrdinary(data: PublisherData): boolean
	if unusedMessageCapacity(data) < 1 or unusedSequenceCapacity(data) < 1 then
		return false
	end
	data.reservedOrdinaryMessageCount += 1
	return true
end

local function validateRecordForActiveOperation(
	data: PublisherData,
	runtimeEnemyId: unknown,
	operation: Operation
): (Representation?, PublisherError?)
	if not isSafePositiveInteger(runtimeEnemyId, data.limits.maxLifetime) then
		return nil, makeError("INVALID_ARGUMENT", operation)
	end
	local record = data.representations[runtimeEnemyId :: number]
	if record == nil then
		return nil, makeError("STALE_RUNTIME_ID", operation)
	end
	if not record.active then
		return nil, makeError("ILLEGAL_LIFECYCLE", operation)
	end
	return record, nil
end

local function canRetainStateChange(data: PublisherData, record: Representation): boolean
	local spawn = findEntry(record, "Spawn")
	if spawn ~= nil then
		return true
	end
	local state = findEntry(record, "StateChange")
	local correction = findEntry(record, "Correction")
	return state ~= nil or correction ~= nil or unusedMessageCapacity(data) >= 1
end

local function preflightSpawnData(data: PublisherData): PublisherError?
	if
		data.terminalPendingCount > 0
		or data.activeRepresentationCount >= data.limits.maxActive
		or data.lifetimeRepresentationCount >= data.limits.maxLifetime
		or data.pendingEntryCount >= data.limits.maxPendingEntries
	then
		return makeError("CAPACITY_EXCEEDED", "preflightSpawn")
	end
	if not canAdvanceOrdinal(data, 1) then
		return makeError("REVISION_EXHAUSTED", "preflightSpawn")
	end
	if unusedMessageCapacity(data) < 3 then
		return makeError("CAPACITY_EXCEEDED", "preflightSpawn")
	end
	if unusedSequenceCapacity(data) < 3 then
		return makeError("SEQUENCE_EXHAUSTED", "preflightSpawn")
	end
	return nil
end

function PublisherMethods.preflightSpawn(self: Publisher): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "preflightSpawn", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local preflightError = preflightSpawnData(data)
	if preflightError ~= nil then
		return Result.err(preflightError)
	end
	return Result.ok(true)
end

function PublisherMethods.preflightStateChange(
	self: Publisher,
	runtimeEnemyId: unknown
): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "preflightStateChange", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local record, recordError = validateRecordForActiveOperation(data, runtimeEnemyId, "preflightStateChange")
	if record == nil then
		return Result.err(recordError :: PublisherError)
	end
	if not canAdvanceOrdinal(data, 1) then
		return failure("REVISION_EXHAUSTED", "preflightStateChange")
	end
	if not canRetainStateChange(data, record) then
		return failure("CAPACITY_EXCEEDED", "preflightStateChange")
	end
	return Result.ok(true)
end

function PublisherMethods.preflightEndpoint(
	self: Publisher,
	runtimeEnemyId: unknown
): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "preflightEndpoint", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local record, recordError = validateRecordForActiveOperation(data, runtimeEnemyId, "preflightEndpoint")
	if record == nil then
		return Result.err(recordError :: PublisherError)
	end
	if not record.endpointReserved or not record.despawnReserved then
		return failure("CAPACITY_EXCEEDED", "preflightEndpoint")
	end
	if not canAdvanceOrdinal(data, 2) then
		return failure("REVISION_EXHAUSTED", "preflightEndpoint")
	end
	return Result.ok(true)
end

function PublisherMethods.preflightManualDespawn(
	self: Publisher,
	runtimeEnemyId: unknown
): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "preflightManualDespawn", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local record, recordError = validateRecordForActiveOperation(data, runtimeEnemyId, "preflightManualDespawn")
	if record == nil then
		return Result.err(recordError :: PublisherError)
	end
	if not record.despawnReserved then
		return failure("CAPACITY_EXCEEDED", "preflightManualDespawn")
	end
	if not canAdvanceOrdinal(data, 1) then
		return failure("REVISION_EXHAUSTED", "preflightManualDespawn")
	end
	return Result.ok(true)
end

local function validateDefeatIdSet(
	data: PublisherData,
	runtimeEnemyIdsValue: unknown,
	operation: Operation
): ({ RuntimeEnemyId }?, PublisherError?)
	if
		type(runtimeEnemyIdsValue) ~= "table"
		or not table.isfrozen(runtimeEnemyIdsValue :: any)
		or getmetatable(runtimeEnemyIdsValue :: any) ~= nil
	then
		return nil, makeError("INVALID_ARGUMENT", operation)
	end
	local runtimeEnemyIds = runtimeEnemyIdsValue :: { unknown }
	local length = #runtimeEnemyIds
	if length > data.limits.maxActive or length ~= data.activeRepresentationCount then
		return nil, makeError("INVALID_ARGUMENT", operation)
	end
	local count = 0
	for key in next, runtimeEnemyIds :: any do
		count += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return nil, makeError("INVALID_ARGUMENT", operation)
		end
	end
	if count ~= length then
		return nil, makeError("INVALID_ARGUMENT", operation)
	end
	local previousId: number? = nil
	for _, runtimeEnemyId in runtimeEnemyIds do
		if
			not isSafePositiveInteger(runtimeEnemyId, data.limits.maxLifetime)
			or (previousId ~= nil and (runtimeEnemyId :: number) <= previousId)
		then
			return nil, makeError("INVALID_ARGUMENT", operation)
		end
		local record = data.representations[runtimeEnemyId :: number]
		if record == nil or not record.active or not record.despawnReserved then
			return nil, makeError("ILLEGAL_LIFECYCLE", operation)
		end
		if record.lastRevision >= Validation.MAX_SAFE_INTEGER then
			return nil, makeError("REVISION_EXHAUSTED", operation)
		end
		previousId = runtimeEnemyId :: number
	end
	return runtimeEnemyIds :: any, nil
end

function PublisherMethods.preflightDefeat(
	self: Publisher,
	runtimeEnemyIdsValue: unknown
): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "preflightDefeat", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local runtimeEnemyIds, idError = validateDefeatIdSet(data, runtimeEnemyIdsValue, "preflightDefeat")
	if runtimeEnemyIds == nil then
		return Result.err(idError :: PublisherError)
	end
	if not canAdvanceOrdinal(data, #runtimeEnemyIds) then
		return failure("REVISION_EXHAUSTED", "preflightDefeat")
	end
	return Result.ok(true)
end

function PublisherMethods.preflightStep(
	self: Publisher,
	runtimeEnemyIdsValue: unknown
): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "preflightStep", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	if
		type(runtimeEnemyIdsValue) ~= "table"
		or not table.isfrozen(runtimeEnemyIdsValue :: any)
		or getmetatable(runtimeEnemyIdsValue :: any) ~= nil
	then
		return failure("INVALID_ARGUMENT", "preflightStep")
	end
	local runtimeEnemyIds = runtimeEnemyIdsValue :: { unknown }
	local length = #runtimeEnemyIds
	if length > data.limits.maxActive or length ~= data.activeRepresentationCount then
		return failure("INVALID_ARGUMENT", "preflightStep")
	end
	local count = 0
	local previousId: number? = nil
	for key in next, runtimeEnemyIds :: any do
		count += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return failure("INVALID_ARGUMENT", "preflightStep")
		end
	end
	if count ~= length then
		return failure("INVALID_ARGUMENT", "preflightStep")
	end
	for _, runtimeEnemyId in runtimeEnemyIds do
		if
			not isSafePositiveInteger(runtimeEnemyId, data.limits.maxLifetime)
			or (previousId ~= nil and (runtimeEnemyId :: number) <= previousId)
		then
			return failure("INVALID_ARGUMENT", "preflightStep")
		end
		local record = data.representations[runtimeEnemyId :: number]
		if record == nil or not record.active or not record.endpointReserved or not record.despawnReserved then
			return failure("ILLEGAL_LIFECYCLE", "preflightStep")
		end
		previousId = runtimeEnemyId :: number
	end
	if not canAdvanceOrdinal(data, 2 * length) then
		return failure("REVISION_EXHAUSTED", "preflightStep")
	end
	return Result.ok(true)
end

function PublisherMethods.commitSpawn(
	self: Publisher,
	snapshotValue: unknown
): Result.Result<EnemyProtocol.EnemyStateEntry, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "commitSpawn", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local state = canonicalState(snapshotValue)
	if state == nil or state.lifecycle ~= "Active" or state.revision ~= 1 then
		return failure("INVALID_SNAPSHOT", "commitSpawn")
	end
	local expectedId = data.lifetimeRepresentationCount + 1
	if state.runtimeEnemyId ~= expectedId or data.representations[state.runtimeEnemyId] ~= nil then
		return failure("ID_COLLISION", "commitSpawn")
	end
	local preflightError = preflightSpawnData(data)
	if preflightError ~= nil then
		return failure(preflightError.code, "commitSpawn")
	end

	local ordinal = takeOrdinal(data)
	local record: Representation = {
		runtimeEnemyId = state.runtimeEnemyId,
		lastRevision = state.revision,
		active = true,
		spawnEmitted = false,
		spawnReserved = true,
		endpointReserved = true,
		despawnReserved = true,
		chain = {},
	}
	data.representations[state.runtimeEnemyId] = record
	data.activeRepresentationCount += 1
	data.lifetimeRepresentationCount += 1
	data.reservedFutureMessageCount += 3
	insertEntry(data, record, {
		kind = "Spawn",
		ordinal = ordinal,
		runtimeEnemyId = state.runtimeEnemyId,
		revision = state.revision,
		state = state,
		despawn = nil,
		funding = "Spawn",
	})
	return Result.ok(state)
end

function PublisherMethods.commitStateChange(
	self: Publisher,
	snapshotValue: unknown
): Result.Result<EnemyProtocol.EnemyStateEntry, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "commitStateChange", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local state = canonicalState(snapshotValue)
	if state == nil or state.lifecycle ~= "Active" then
		return failure("INVALID_SNAPSHOT", "commitStateChange")
	end
	local record, recordError = validateRecordForActiveOperation(data, state.runtimeEnemyId, "commitStateChange")
	if record == nil then
		return Result.err(recordError :: PublisherError)
	end
	if state.revision <= record.lastRevision then
		return failure("INVALID_SNAPSHOT", "commitStateChange")
	end
	if not canAdvanceOrdinal(data, 1) then
		return failure("REVISION_EXHAUSTED", "commitStateChange")
	end
	if not canRetainStateChange(data, record) then
		return failure("CAPACITY_EXCEEDED", "commitStateChange")
	end

	local ordinal = takeOrdinal(data)
	clearDirty(data, state.runtimeEnemyId)
	local spawn = findEntry(record, "Spawn")
	if spawn ~= nil then
		spawn.state = state
		spawn.revision = state.revision
	else
		local reusableFunding = false
		local index = #record.chain
		while index >= 1 do
			local entry = record.chain[index]
			if entry.kind == "StateChange" or entry.kind == "Correction" then
				removeEntryAt(data, record, index, true)
				reusableFunding = true
			end
			index -= 1
		end
		if not reserveOrdinary(data) then
			if reusableFunding then
				-- Removing at least one ordinary entry released the replacement token.
				if not reserveOrdinary(data) then
					failClosed(data)
					return failure("INTERNAL_ERROR", "commitStateChange")
				end
			else
				failClosed(data)
				return failure("INTERNAL_ERROR", "commitStateChange")
			end
		end
		insertEntry(data, record, {
			kind = "StateChange",
			ordinal = ordinal,
			runtimeEnemyId = state.runtimeEnemyId,
			revision = state.revision,
			state = state,
			despawn = nil,
			funding = "Ordinary",
		})
	end
	record.lastRevision = state.revision
	return Result.ok(state)
end

function PublisherMethods.commitEndpoint(
	self: Publisher,
	endpointValue: unknown,
	despawnValue: unknown
): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "commitEndpoint", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local endpoint = canonicalState(endpointValue)
	local despawn = canonicalDespawn(despawnValue)
	if
		endpoint == nil
		or despawn == nil
		or endpoint.lifecycle ~= "EndpointResolved"
		or despawn.reason ~= "Endpoint"
		or endpoint.runtimeEnemyId ~= despawn.runtimeEnemyId
		or despawn.revision ~= endpoint.revision + 1
	then
		return failure("INVALID_SNAPSHOT", "commitEndpoint")
	end
	local record, recordError = validateRecordForActiveOperation(data, endpoint.runtimeEnemyId, "commitEndpoint")
	if record == nil then
		return Result.err(recordError :: PublisherError)
	end
	if endpoint.revision <= record.lastRevision or not record.endpointReserved or not record.despawnReserved then
		return failure("INVALID_SNAPSHOT", "commitEndpoint")
	end
	if not canAdvanceOrdinal(data, 2) then
		return failure("REVISION_EXHAUSTED", "commitEndpoint")
	end

	clearDirty(data, endpoint.runtimeEnemyId)
	removeActiveEntries(data, record)
	insertEntry(data, record, {
		kind = "StateChange",
		ordinal = takeOrdinal(data),
		runtimeEnemyId = endpoint.runtimeEnemyId,
		revision = endpoint.revision,
		state = endpoint,
		despawn = nil,
		funding = "Endpoint",
	})
	insertEntry(data, record, {
		kind = "Despawn",
		ordinal = takeOrdinal(data),
		runtimeEnemyId = despawn.runtimeEnemyId,
		revision = despawn.revision,
		state = nil,
		despawn = despawn,
		funding = "Despawn",
	})
	record.lastRevision = despawn.revision
	record.active = false
	data.activeRepresentationCount -= 1
	data.terminalPendingCount += 1
	return Result.ok(true)
end

local function commitDespawn(data: PublisherData, record: Representation, despawn: EnemyProtocol.DespawnEntry)
	clearDirty(data, despawn.runtimeEnemyId)
	removeActiveEntries(data, record)
	if record.endpointReserved then
		record.endpointReserved = false
		data.reservedFutureMessageCount -= 1
	end
	insertEntry(data, record, {
		kind = "Despawn",
		ordinal = takeOrdinal(data),
		runtimeEnemyId = despawn.runtimeEnemyId,
		revision = despawn.revision,
		state = nil,
		despawn = despawn,
		funding = "Despawn",
	})
	record.lastRevision = despawn.revision
	record.active = false
	data.activeRepresentationCount -= 1
	data.terminalPendingCount += 1
end

function PublisherMethods.commitManualDespawn(
	self: Publisher,
	despawnValue: unknown
): Result.Result<EnemyProtocol.DespawnEntry, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "commitManualDespawn", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local despawn = canonicalDespawn(despawnValue)
	if despawn == nil or despawn.reason ~= "Manual" then
		return failure("INVALID_SNAPSHOT", "commitManualDespawn")
	end
	local record, recordError = validateRecordForActiveOperation(data, despawn.runtimeEnemyId, "commitManualDespawn")
	if record == nil then
		return Result.err(recordError :: PublisherError)
	end
	if despawn.revision <= record.lastRevision or not record.despawnReserved then
		return failure("INVALID_SNAPSHOT", "commitManualDespawn")
	end
	if not canAdvanceOrdinal(data, 1) then
		return failure("REVISION_EXHAUSTED", "commitManualDespawn")
	end

	commitDespawn(data, record, despawn)
	return Result.ok(despawn)
end

function PublisherMethods.commitDefeat(
	self: Publisher,
	despawnValues: unknown
): Result.Result<{ EnemyProtocol.DespawnEntry }, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "commitDefeat", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	if
		type(despawnValues) ~= "table"
		or not table.isfrozen(despawnValues :: any)
		or getmetatable(despawnValues :: any) ~= nil
	then
		return failure("INVALID_ARGUMENT", "commitDefeat")
	end
	local values = despawnValues :: { unknown }
	local length = #values
	if length ~= data.activeRepresentationCount or length > data.limits.maxActive then
		return failure("INVALID_ARGUMENT", "commitDefeat")
	end
	local keyCount = 0
	for key in next, values :: any do
		keyCount += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return failure("INVALID_ARGUMENT", "commitDefeat")
		end
	end
	if keyCount ~= length or not canAdvanceOrdinal(data, length) then
		return failure(if keyCount ~= length then "INVALID_ARGUMENT" else "REVISION_EXHAUSTED", "commitDefeat")
	end

	local despawns: { EnemyProtocol.DespawnEntry } = table.create(length)
	local records: { Representation } = table.create(length)
	local previousId: number? = nil
	for index, value in values do
		local despawn = canonicalDespawn(value)
		if
			despawn == nil
			or despawn.reason ~= "Defeat"
			or (previousId ~= nil and despawn.runtimeEnemyId <= previousId)
		then
			return failure("INVALID_SNAPSHOT", "commitDefeat")
		end
		local record = data.representations[despawn.runtimeEnemyId]
		if
			record == nil
			or not record.active
			or not record.despawnReserved
			or despawn.revision <= record.lastRevision
		then
			return failure("INVALID_SNAPSHOT", "commitDefeat")
		end
		despawns[index] = despawn
		records[index] = record
		previousId = despawn.runtimeEnemyId
	end

	for index, despawn in despawns do
		commitDespawn(data, records[index], despawn)
	end
	table.freeze(despawns)
	return Result.ok(despawns)
end

function PublisherMethods.observeCorrection(
	self: Publisher,
	runtimeEnemyId: unknown
): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "observeCorrection", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local record, recordError = validateRecordForActiveOperation(data, runtimeEnemyId, "observeCorrection")
	if record == nil then
		return Result.err(recordError :: PublisherError)
	end
	if not canAdvanceOrdinal(data, 1) then
		return failure("REVISION_EXHAUSTED", "observeCorrection")
	end
	local ordinal = takeOrdinal(data)
	local existing = data.dirtyCorrections[record.runtimeEnemyId]
	if existing == nil then
		data.dirtyCorrections[record.runtimeEnemyId] = {
			ordinal = ordinal,
			state = nil,
		}
		data.dirtyCorrectionCount += 1
	else
		existing.ordinal = ordinal
		existing.state = nil
	end
	return Result.ok(true)
end

local function readProviderResult(value: unknown): { unknown }?
	local snapshots = successValue(value)
	if type(snapshots) ~= "table" or not table.isfrozen(snapshots :: any) or getmetatable(snapshots :: any) ~= nil then
		return nil
	end
	local length = #snapshots
	local count = 0
	for key in next, snapshots :: any do
		count += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return nil
		end
	end
	if count ~= length then
		return nil
	end
	return snapshots :: { unknown }
end

local function materializeOneCorrection(
	data: PublisherData,
	runtimeEnemyId: RuntimeEnemyId,
	dirty: DirtyCorrection,
	state: EnemyProtocol.EnemyStateEntry
): boolean
	local record = data.representations[runtimeEnemyId]
	if record == nil or not record.active or state.runtimeEnemyId ~= runtimeEnemyId or state.lifecycle ~= "Active" then
		return false
	end
	if state.revision <= record.lastRevision then
		return false
	end
	dirty.state = state
	record.lastRevision = state.revision

	local spawn = findEntry(record, "Spawn")
	if spawn ~= nil then
		spawn.state = state
		spawn.revision = state.revision
		clearDirty(data, runtimeEnemyId)
		return true
	end

	local correction = findEntry(record, "Correction")
	if correction ~= nil then
		correction.ordinal = dirty.ordinal
		correction.revision = state.revision
		correction.state = state
		table.sort(record.chain, function(left: PendingEntry, right: PendingEntry): boolean
			return left.ordinal < right.ordinal
		end)
		clearDirty(data, runtimeEnemyId)
		return true
	end

	if not reserveOrdinary(data) then
		return true
	end
	insertEntry(data, record, {
		kind = "Correction",
		ordinal = dirty.ordinal,
		runtimeEnemyId = runtimeEnemyId,
		revision = state.revision,
		state = state,
		despawn = nil,
		funding = "Ordinary",
	})
	clearDirty(data, runtimeEnemyId)
	return true
end

local function queryDirtyCorrections(data: PublisherData, provider: SnapshotProvider): boolean
	if data.dirtyCorrectionCount == 0 then
		return true
	end
	local ids: { RuntimeEnemyId } = {}
	for runtimeEnemyId, dirty in data.dirtyCorrections do
		if dirty.state == nil then
			table.insert(ids, runtimeEnemyId)
		end
	end
	if #ids == 0 then
		return true
	end
	table.sort(ids)
	table.freeze(ids)
	local called, providerResult = callNonYielding(provider, ids)
	if not called or data.cleanupRequested then
		return false
	end
	local snapshots = readProviderResult(providerResult)
	if snapshots == nil or #snapshots ~= #ids then
		return false
	end
	for index, runtimeEnemyId in ids do
		local state = canonicalState(snapshots[index])
		local dirty = data.dirtyCorrections[runtimeEnemyId]
		if state == nil or dirty == nil or not materializeOneCorrection(data, runtimeEnemyId, dirty, state) then
			return false
		end
	end
	return true
end

local function promoteRetainedDirtyCorrections(data: PublisherData)
	if unusedMessageCapacity(data) < 1 or data.dirtyCorrectionCount == 0 then
		return
	end
	local candidates: { { id: RuntimeEnemyId, dirty: DirtyCorrection } } = {}
	for runtimeEnemyId, dirty in data.dirtyCorrections do
		if dirty.state ~= nil then
			table.insert(candidates, { id = runtimeEnemyId, dirty = dirty })
		end
	end
	table.sort(candidates, function(left, right): boolean
		if left.dirty.ordinal == right.dirty.ordinal then
			return left.id < right.id
		end
		return left.dirty.ordinal < right.dirty.ordinal
	end)
	for _, candidate in candidates do
		if unusedMessageCapacity(data) < 1 then
			break
		end
		local state = candidate.dirty.state
		if state ~= nil then
			materializeOneCorrection(data, candidate.id, candidate.dirty, state)
		end
	end
end

local function readRecipients(data: PublisherData): { RecipientRecord }?
	local provider = data.getRecipients
	if provider == nil then
		return nil
	end
	local called, value = callNonYielding(provider)
	if not called or type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local length = #value
	if length > data.limits.maxRecipients then
		return nil
	end
	local recipients: { RecipientRecord } = table.create(length)
	local keyCount = 0
	for key in next, value :: any do
		keyCount += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return nil
		end
	end
	if keyCount ~= length then
		return nil
	end
	for index = 1, length do
		local record = rawget(value :: any, index)
		if
			type(record) ~= "table"
			or getmetatable(record) ~= nil
			or not hasExactFields(record, RECIPIENT_FIELDS)
			or (type(record.recipient) ~= "table" and typeof(record.recipient) ~= "Instance")
			or type(record.userId) ~= "number"
			or not isSafePositiveInteger(math.abs(record.userId), Validation.MAX_SAFE_INTEGER)
			or record.userId == 0
		then
			return nil
		end
		for previousIndex = 1, index - 1 do
			local previous = recipients[previousIndex]
			if previous.recipient == record.recipient or previous.userId == record.userId then
				return nil
			end
		end
		recipients[index] = {
			recipient = record.recipient,
			userId = record.userId,
		}
	end
	table.sort(recipients, function(left: RecipientRecord, right: RecipientRecord): boolean
		return left.userId < right.userId
	end)
	return recipients
end

local function entryLess(left: PendingEntry, right: PendingEntry): boolean
	if left.ordinal ~= right.ordinal then
		return left.ordinal < right.ordinal
	end
	if left.runtimeEnemyId ~= right.runtimeEnemyId then
		return left.runtimeEnemyId < right.runtimeEnemyId
	end
	return KIND_ORDER[left.kind] < KIND_ORDER[right.kind]
end

local function sortedPendingEntries(data: PublisherData): { PendingEntry }
	local entries: { PendingEntry } = table.create(data.pendingEntryCount)
	for _, record in data.representations do
		for _, entry in record.chain do
			table.insert(entries, entry)
		end
	end
	table.sort(entries, entryLess)
	return entries
end

local function messageKind(commitKind: CommitKind): string
	if commitKind == "Spawn" then
		return EnemyProtocol.SPAWN_BATCH_KIND
	elseif commitKind == "Correction" then
		return EnemyProtocol.CORRECTION_BATCH_KIND
	elseif commitKind == "StateChange" then
		return EnemyProtocol.STATE_CHANGE_BATCH_KIND
	end
	return EnemyProtocol.DESPAWN_BATCH_KIND
end

local function buildBatch(data: PublisherData, entries: { PendingEntry }): EnemyProtocol.EnemyReplicationMessage?
	local wireEntries: { any } = table.create(#entries)
	for index, entry in entries do
		wireEntries[index] = if entry.kind == "Despawn" then entry.despawn else entry.state
		if wireEntries[index] == nil then
			return nil
		end
	end
	table.freeze(wireEntries)
	local candidate = table.freeze({
		kind = messageKind(entries[1].kind),
		matchId = data.matchId,
		enemyEpoch = data.enemyEpoch,
		sequence = data.nextSequence,
		entries = wireEntries,
	})
	local result = EnemyProtocol.validateEnemyReplication(candidate)
	if not result.ok then
		return nil
	end
	return result.value
end

local function finishEmittedEntry(data: PublisherData, entry: PendingEntry): boolean
	local record = data.representations[entry.runtimeEnemyId]
	if record == nil or not removeEntryObject(data, record, entry, true) then
		return false
	end
	if entry.kind == "Spawn" then
		record.spawnEmitted = true
	elseif entry.kind == "Despawn" and #record.chain == 0 then
		if record.spawnReserved or record.endpointReserved or record.despawnReserved then
			return false
		end
		data.representations[record.runtimeEnemyId] = nil
		data.terminalPendingCount -= 1
	end
	return true
end

local function sendToRecipients(
	data: PublisherData,
	recipients: { RecipientRecord },
	message: EnemyProtocol.EnemyReplicationMessage
)
	local sender = data.sender
	if sender == nil then
		failClosed(data)
		return
	end
	for _, record in recipients do
		if data.cleanupRequested then
			break
		end
		data.senderCallCount += 1
		local called, sent = callNonYielding(sender, record.recipient, message)
		if not called or sent ~= true then
			data.senderFailureCount += 1
		end
	end
end

local function flush(data: PublisherData): (boolean, number, number)
	if data.pendingEntryCount == 0 then
		return true, 0, 0
	end
	local recipients = readRecipients(data)
	if recipients == nil then
		return false, 0, 0
	end
	local batchCount = 0
	local entryCount = 0
	while batchCount < data.limits.maxBatchesPerFlush and data.pendingEntryCount > 0 and not data.cleanupRequested do
		promoteRetainedDirtyCorrections(data)
		local sorted = sortedPendingEntries(data)
		local first = sorted[1]
		if first == nil then
			return false, batchCount, entryCount
		end
		local selected: { PendingEntry } = {}
		for _, entry in sorted do
			if entry.kind ~= first.kind or #selected >= data.limits.maxEntriesPerMessage then
				break
			end
			table.insert(selected, entry)
		end
		if #selected == 0 or data.deltaMessageCount >= data.limits.maxDeltaMessages then
			return false, batchCount, entryCount
		end
		if data.nextSequence > Validation.MAX_SAFE_INTEGER then
			return false, batchCount, entryCount
		end
		local message = buildBatch(data, selected)
		if message == nil then
			return false, batchCount, entryCount
		end

		data.nextSequence += 1
		data.deltaMessageCount += 1
		for _, entry in selected do
			if not finishEmittedEntry(data, entry) then
				return false, batchCount, entryCount
			end
		end
		batchCount += 1
		entryCount += #selected
		sendToRecipients(data, recipients, message)
	end
	return true, batchCount, entryCount
end

local function clearData(data: PublisherData)
	data.sender = nil
	data.getRecipients = nil
	data.matchId = nil
	table.clear(data.representations)
	table.clear(data.dirtyCorrections)
	table.clear(data.requestCounts)
	data.activeRepresentationCount = 0
	data.lifetimeRepresentationCount = 0
	data.pendingEntryCount = 0
	data.dirtyCorrectionCount = 0
	data.terminalPendingCount = 0
	data.reservedFutureMessageCount = 0
	data.reservedOrdinaryMessageCount = 0
	data.deltaMessageCount = 0
	data.snapshotMessageCount = 0
	data.nextSequence = 1
	data.nextMutationOrdinal = 1
	data.nextSnapshotId = 1
	data.elapsedSinceFlush = 0
	data.senderCallCount = 0
	data.senderFailureCount = 0
	data.flushCount = 0
	data.cleanupRequested = false
	data.cleaned = true
end

local function finalizeBusy(data: PublisherData)
	data.busy = false
	if data.cleanupRequested then
		clearData(data)
	end
end

function PublisherMethods.advance(
	self: Publisher,
	deltaSecondsValue: unknown,
	snapshotProviderValue: unknown
): Result.Result<AdvanceOutcome, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "advance", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	if
		not isFiniteNumber(deltaSecondsValue)
		or (deltaSecondsValue :: number) < 0
		or type(snapshotProviderValue) ~= "function"
	then
		return failure("INVALID_ARGUMENT", "advance")
	end
	local deltaSeconds = deltaSecondsValue :: number
	if deltaSeconds == 0 then
		return Result.ok(table.freeze({
			flushOccurred = false,
			batchCount = 0,
			entryCount = 0,
			remainingPendingEntries = data.pendingEntryCount,
			remainingDirtyCorrections = data.dirtyCorrectionCount,
		}))
	end
	data.elapsedSinceFlush += deltaSeconds
	if data.elapsedSinceFlush < data.limits.publicationIntervalSeconds then
		return Result.ok(table.freeze({
			flushOccurred = false,
			batchCount = 0,
			entryCount = 0,
			remainingPendingEntries = data.pendingEntryCount,
			remainingDirtyCorrections = data.dirtyCorrectionCount,
		}))
	end

	data.elapsedSinceFlush = 0
	data.busy = true
	local correctionsReady = queryDirtyCorrections(data, snapshotProviderValue :: SnapshotProvider)
	if not correctionsReady or data.cleanupRequested then
		finalizeBusy(data)
		if data.cleaned then
			return failure("CLEANED", "advance")
		end
		failClosed(data)
		return failure("INVALID_PROVIDER", "advance")
	end
	promoteRetainedDirtyCorrections(data)
	local flushed, batchCount, entryCount = flush(data)
	if not flushed then
		finalizeBusy(data)
		if data.cleaned then
			return failure("CLEANED", "advance")
		end
		failClosed(data)
		return failure("INTERNAL_ERROR", "advance")
	end
	if batchCount > 0 then
		data.flushCount += 1
	end
	local outcome = table.freeze({
		flushOccurred = true,
		batchCount = batchCount,
		entryCount = entryCount,
		remainingPendingEntries = data.pendingEntryCount,
		remainingDirtyCorrections = data.dirtyCorrectionCount,
	})
	finalizeBusy(data)
	if data.cleaned then
		return failure("CLEANED", "advance")
	end
	return Result.ok(outcome)
end

local function canonicalSnapshotEntries(value: unknown, maximum: number): { EnemyProtocol.EnemyStateEntry }?
	local snapshots = readProviderResult(value)
	if snapshots == nil or #snapshots > maximum then
		return nil
	end
	local entries: { EnemyProtocol.EnemyStateEntry } = table.create(#snapshots)
	local previousId: number? = nil
	for index, snapshotValue in snapshots do
		local state = canonicalState(snapshotValue)
		if
			state == nil
			or state.lifecycle ~= "Active"
			or (previousId ~= nil and state.runtimeEnemyId <= previousId)
		then
			return nil
		end
		entries[index] = state
		previousId = state.runtimeEnemyId
	end
	table.freeze(entries)
	return entries
end

local function validatedMessage(value: unknown): EnemyProtocol.EnemyReplicationMessage?
	local result = EnemyProtocol.validateEnemyReplication(value)
	return if result.ok then result.value else nil
end

local function buildSnapshotMessages(
	data: PublisherData,
	snapshotId: number,
	baseSequence: number,
	entries: { EnemyProtocol.EnemyStateEntry }
): ({ EnemyProtocol.EnemyReplicationMessage }?, EnemyProtocol.EnemySnapshotReceipt?)
	local chunkCount = math.ceil(#entries / data.limits.maxEntriesPerMessage)
	if chunkCount > EnemyProtocol.MAX_SNAPSHOT_CHUNKS then
		return nil, nil
	end
	local boundaryFields = {
		matchId = data.matchId,
		enemyEpoch = data.enemyEpoch,
		baseSequence = baseSequence,
		snapshotId = snapshotId,
		chunkCount = chunkCount,
		totalEntries = #entries,
	}
	local messages: { EnemyProtocol.EnemyReplicationMessage } = {}
	local begin = validatedMessage(table.freeze({
		kind = EnemyProtocol.SNAPSHOT_BEGIN_KIND,
		matchId = boundaryFields.matchId,
		enemyEpoch = boundaryFields.enemyEpoch,
		baseSequence = boundaryFields.baseSequence,
		snapshotId = boundaryFields.snapshotId,
		chunkCount = boundaryFields.chunkCount,
		totalEntries = boundaryFields.totalEntries,
	}))
	if begin == nil then
		return nil, nil
	end
	table.insert(messages, begin)
	for chunkIndex = 1, chunkCount do
		local firstIndex = (chunkIndex - 1) * data.limits.maxEntriesPerMessage + 1
		local lastIndex = math.min(#entries, firstIndex + data.limits.maxEntriesPerMessage - 1)
		local chunkEntries: { EnemyProtocol.EnemyStateEntry } = table.create(lastIndex - firstIndex + 1)
		for index = firstIndex, lastIndex do
			table.insert(chunkEntries, entries[index])
		end
		table.freeze(chunkEntries)
		local chunk = validatedMessage(table.freeze({
			kind = EnemyProtocol.SNAPSHOT_CHUNK_KIND,
			matchId = boundaryFields.matchId,
			enemyEpoch = boundaryFields.enemyEpoch,
			baseSequence = boundaryFields.baseSequence,
			snapshotId = boundaryFields.snapshotId,
			chunkIndex = chunkIndex,
			entries = chunkEntries,
		}))
		if chunk == nil then
			return nil, nil
		end
		table.insert(messages, chunk)
	end
	local finish = validatedMessage(table.freeze({
		kind = EnemyProtocol.SNAPSHOT_END_KIND,
		matchId = boundaryFields.matchId,
		enemyEpoch = boundaryFields.enemyEpoch,
		baseSequence = boundaryFields.baseSequence,
		snapshotId = boundaryFields.snapshotId,
		chunkCount = boundaryFields.chunkCount,
		totalEntries = boundaryFields.totalEntries,
	}))
	if finish == nil then
		return nil, nil
	end
	table.insert(messages, finish)
	table.freeze(messages)
	local receiptResult = EnemyProtocol.validateEnemySnapshotReceipt(table.freeze(boundaryFields))
	if not receiptResult.ok then
		return nil, nil
	end
	return messages, receiptResult.value
end

function PublisherMethods.requestSnapshot(
	self: Publisher,
	recipient: unknown,
	snapshotProviderValue: unknown
): Result.Result<EnemyProtocol.EnemySnapshotReceipt, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "requestSnapshot", true)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	if
		(type(recipient) ~= "table" and typeof(recipient) ~= "Instance")
		or type(snapshotProviderValue) ~= "function"
	then
		return failure("INVALID_ARGUMENT", "requestSnapshot")
	end
	data.busy = true
	local recipients = readRecipients(data)
	if recipients == nil then
		finalizeBusy(data)
		if data.cleaned then
			return failure("CLEANED", "requestSnapshot")
		end
		failClosed(data)
		return failure("INTERNAL_ERROR", "requestSnapshot")
	end
	if data.cleanupRequested then
		finalizeBusy(data)
		return failure("CLEANED", "requestSnapshot")
	end
	local activeRecipient = false
	for _, record in recipients do
		if record.recipient == recipient then
			activeRecipient = true
			break
		end
	end
	if not activeRecipient then
		finalizeBusy(data)
		return failure("INVALID_RECIPIENT", "requestSnapshot")
	end
	local requestCount = rawget(data.requestCounts, recipient) or 0
	if requestCount >= data.limits.maxSnapshotRequestsPerPlayer then
		finalizeBusy(data)
		return failure("CAPACITY_EXCEEDED", "requestSnapshot")
	end
	if data.nextSnapshotId > data.limits.maxSnapshotIds then
		finalizeBusy(data)
		return failure("CAPACITY_EXCEEDED", "requestSnapshot")
	end

	local called, providerResult = callNonYielding(snapshotProviderValue :: SnapshotProvider, nil)
	if not called or data.cleanupRequested then
		finalizeBusy(data)
		if data.cleaned then
			return failure("CLEANED", "requestSnapshot")
		end
		return failure("INVALID_PROVIDER", "requestSnapshot")
	end
	local entries = canonicalSnapshotEntries(providerResult, data.limits.maxActive)
	if entries == nil then
		finalizeBusy(data)
		return failure("INVALID_PROVIDER", "requestSnapshot")
	end
	local messageCount = 2 + math.ceil(#entries / data.limits.maxEntriesPerMessage)
	if data.snapshotMessageCount > data.limits.maxSnapshotMessages - messageCount then
		finalizeBusy(data)
		return failure("CAPACITY_EXCEEDED", "requestSnapshot")
	end
	local snapshotId = data.nextSnapshotId
	local baseSequence = data.nextSequence - 1
	local messages, receipt = buildSnapshotMessages(data, snapshotId, baseSequence, entries)
	if messages == nil or receipt == nil or #messages ~= messageCount then
		finalizeBusy(data)
		failClosed(data)
		return failure("INTERNAL_ERROR", "requestSnapshot")
	end

	data.nextSnapshotId += 1
	data.snapshotMessageCount += messageCount
	rawset(data.requestCounts, recipient, requestCount + 1)
	local sender = data.sender
	if sender == nil then
		finalizeBusy(data)
		failClosed(data)
		return failure("INTERNAL_ERROR", "requestSnapshot")
	end
	for _, message in messages do
		if data.cleanupRequested then
			break
		end
		data.senderCallCount += 1
		local sentCalled, sent = callNonYielding(sender, recipient, message)
		if not sentCalled or sent ~= true then
			data.senderFailureCount += 1
		end
	end
	finalizeBusy(data)
	if data.cleaned then
		return failure("CLEANED", "requestSnapshot")
	end
	return Result.ok(receipt)
end

function PublisherMethods.removePlayer(self: Publisher, recipient: unknown): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "removePlayer", false)
	if liveError ~= nil then
		return Result.err(liveError)
	end
	if type(recipient) ~= "table" and typeof(recipient) ~= "Instance" then
		return failure("INVALID_ARGUMENT", "removePlayer")
	end
	local existed = rawget(data.requestCounts, recipient) ~= nil
	rawset(data.requestCounts, recipient, nil)
	return Result.ok(existed)
end

function PublisherMethods.getMetrics(self: Publisher): Metrics
	local data = requireData(self)
	local trackedPlayers = 0
	for _ in data.requestCounts do
		trackedPlayers += 1
	end
	return table.freeze({
		activeRepresentationCount = data.activeRepresentationCount,
		lifetimeRepresentationCount = data.lifetimeRepresentationCount,
		pendingEntryCount = data.pendingEntryCount,
		dirtyCorrectionCount = data.dirtyCorrectionCount,
		terminalPendingCount = data.terminalPendingCount,
		reservedFutureMessageCount = data.reservedFutureMessageCount,
		reservedOrdinaryMessageCount = data.reservedOrdinaryMessageCount,
		deltaMessageCount = data.deltaMessageCount,
		snapshotMessageCount = data.snapshotMessageCount,
		nextSequence = data.nextSequence,
		nextMutationOrdinal = data.nextMutationOrdinal,
		nextSnapshotId = data.nextSnapshotId,
		trackedRequestPlayerCount = trackedPlayers,
		senderCallCount = data.senderCallCount,
		senderFailureCount = data.senderFailureCount,
		flushCount = data.flushCount,
		retainsSender = data.sender ~= nil,
		retainsRecipientProvider = data.getRecipients ~= nil,
		faulted = data.faulted,
		cleaned = data.cleaned,
	})
end

function PublisherMethods.cleanup(self: Publisher): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	if data.busy then
		data.cleanupRequested = true
		return Result.ok(false)
	end
	clearData(data)
	return Result.ok(true)
end

local function canonicalLimits(value: LimitsOverride?): Limits?
	if value == nil then
		return DEFAULT_LIMITS
	end
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	for fieldName in next, value :: any do
		if type(fieldName) ~= "string" or LIMIT_FIELDS[fieldName] ~= true then
			return nil
		end
	end
	local function boundedInteger(fieldName: string, default: number, minimum: number): number?
		local candidate = rawget(value :: any, fieldName)
		if candidate == nil then
			return default
		end
		if not isSafePositiveInteger(candidate, default) or (candidate :: number) < minimum then
			return nil
		end
		return candidate :: number
	end
	local maxActive = boundedInteger("maxActive", DEFAULT_LIMITS.maxActive, 1)
	local maxLifetime = boundedInteger("maxLifetime", DEFAULT_LIMITS.maxLifetime, maxActive or 1)
	local maxPendingEntries = boundedInteger("maxPendingEntries", DEFAULT_LIMITS.maxPendingEntries, 3)
	local maxEntriesPerMessage = boundedInteger("maxEntriesPerMessage", DEFAULT_LIMITS.maxEntriesPerMessage, 1)
	local maxBatchesPerFlush = boundedInteger("maxBatchesPerFlush", DEFAULT_LIMITS.maxBatchesPerFlush, 1)
	local maxRecipients = boundedInteger("maxRecipients", DEFAULT_LIMITS.maxRecipients, 1)
	local maxDeltaMessages = boundedInteger("maxDeltaMessages", DEFAULT_LIMITS.maxDeltaMessages, 3)
	local maxSnapshotMessages = boundedInteger("maxSnapshotMessages", DEFAULT_LIMITS.maxSnapshotMessages, 2)
	local maxSnapshotIds = boundedInteger("maxSnapshotIds", DEFAULT_LIMITS.maxSnapshotIds, 1)
	local maxSnapshotRequestsPerPlayer =
		boundedInteger("maxSnapshotRequestsPerPlayer", DEFAULT_LIMITS.maxSnapshotRequestsPerPlayer, 1)
	local interval = rawget(value :: any, "publicationIntervalSeconds")
	if interval == nil then
		interval = DEFAULT_LIMITS.publicationIntervalSeconds
	end
	if
		maxActive == nil
		or maxLifetime == nil
		or maxPendingEntries == nil
		or maxEntriesPerMessage == nil
		or maxBatchesPerFlush == nil
		or maxRecipients == nil
		or maxDeltaMessages == nil
		or maxSnapshotMessages == nil
		or maxSnapshotIds == nil
		or maxSnapshotRequestsPerPlayer == nil
		or not isFiniteNumber(interval)
		or (interval :: number) <= 0
		or (interval :: number) > DEFAULT_LIMITS.publicationIntervalSeconds
		or (maxLifetime :: number) < (maxActive :: number)
		or (maxPendingEntries :: number) < (maxActive :: number) * 3
	then
		return nil
	end
	return table.freeze({
		maxActive = maxActive :: number,
		maxLifetime = maxLifetime :: number,
		maxPendingEntries = maxPendingEntries :: number,
		maxEntriesPerMessage = maxEntriesPerMessage :: number,
		maxBatchesPerFlush = maxBatchesPerFlush :: number,
		maxRecipients = maxRecipients :: number,
		maxDeltaMessages = maxDeltaMessages :: number,
		maxSnapshotMessages = maxSnapshotMessages :: number,
		maxSnapshotIds = maxSnapshotIds :: number,
		maxSnapshotRequestsPerPlayer = maxSnapshotRequestsPerPlayer :: number,
		publicationIntervalSeconds = interval :: number,
	})
end

local function construct(
	matchIdValue: unknown,
	enemyEpochValue: unknown,
	dependenciesValue: unknown,
	limitsOverride: LimitsOverride?
): Result.Result<Publisher, PublisherError>
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if not matchIdResult.ok then
		return failure("INVALID_ARGUMENT", "new")
	end
	if not isSafePositiveInteger(enemyEpochValue, EnemyProtocol.MAX_ENEMY_EPOCH) then
		return failure("INVALID_ARGUMENT", "new")
	end
	if
		type(dependenciesValue) ~= "table"
		or getmetatable(dependenciesValue :: any) ~= nil
		or not hasExactFields(dependenciesValue :: { [any]: unknown }, DEPENDENCY_FIELDS)
	then
		return failure("INVALID_ARGUMENT", "new")
	end
	local dependencies = dependenciesValue :: any
	if type(dependencies.sender) ~= "function" or type(dependencies.getRecipients) ~= "function" then
		return failure("INVALID_ARGUMENT", "new")
	end
	local limits = canonicalLimits(limitsOverride)
	if limits == nil then
		return failure("INVALID_ARGUMENT", "new")
	end

	local publisher = setmetatable({}, PublisherMethods) :: Publisher
	table.freeze(publisher)
	PUBLISHER_DATA[publisher] = {
		matchId = matchIdResult.value,
		enemyEpoch = enemyEpochValue :: number,
		sender = dependencies.sender :: Sender,
		getRecipients = dependencies.getRecipients :: GetRecipients,
		limits = limits,
		representations = {},
		dirtyCorrections = {},
		requestCounts = setmetatable({}, { __mode = "k" }),
		activeRepresentationCount = 0,
		lifetimeRepresentationCount = 0,
		pendingEntryCount = 0,
		dirtyCorrectionCount = 0,
		terminalPendingCount = 0,
		reservedFutureMessageCount = 0,
		reservedOrdinaryMessageCount = 0,
		deltaMessageCount = 0,
		snapshotMessageCount = 0,
		nextSequence = 1,
		nextMutationOrdinal = 1,
		nextSnapshotId = 1,
		elapsedSinceFlush = 0,
		senderCallCount = 0,
		senderFailureCount = 0,
		flushCount = 0,
		busy = false,
		cleanupRequested = false,
		faulted = false,
		cleaned = false,
	}
	return Result.ok(publisher)
end

function EnemyReplicationPublisher.new(
	matchId: unknown,
	enemyEpoch: unknown,
	dependencies: unknown
): Result.Result<Publisher, PublisherError>
	return construct(matchId, enemyEpoch, dependencies, nil)
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "EnemyReplicationPublisher" then
		return false
	end
	local productionServerEnemies = script.Parent
	if
		productionServerEnemies == nil
		or not productionServerEnemies:IsA("Folder")
		or productionServerEnemies.Name ~= "ProductionServerEnemies"
	then
		return false
	end
	local automatedTests = productionServerEnemies.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	return automatedTests.Parent == ServerStorage and ServerScriptService:FindFirstChild("Server") == nil
end

if testModuleIdentityIsExact() then
	EnemyReplicationPublisher.newForTests = function(
		matchId: unknown,
		enemyEpoch: unknown,
		dependencies: unknown,
		limits: LimitsOverride?
	): Result.Result<Publisher, PublisherError>
		return construct(matchId, enemyEpoch, dependencies, limits)
	end
end

table.freeze(PublisherMethods)
return table.freeze(EnemyReplicationPublisher)
