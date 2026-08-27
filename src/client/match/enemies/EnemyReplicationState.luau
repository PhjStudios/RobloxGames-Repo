--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type ApplyKind =
	"Applied"
	| "Buffered"
	| "Duplicate"
	| "Stale"
	| "Foreign"
	| "SnapshotProgress"
	| "SnapshotApplied"
	| "RecoveryRequired"
	| "Reset"
	| "Noop"

export type ErrorCode = "INVALID_CONTEXT" | "INVALID_MESSAGE" | "INVALID_RECEIPT" | "INVALID_TIME" | "CLEANED_UP"

export type Error = {
	code: ErrorCode,
}

export type ApplyOutcome = {
	kind: ApplyKind,
	appliedMessageCount: number,
	appliedEntryCount: number,
	identityChanged: boolean,
	recoveryRequested: boolean,
	recoveryRequired: boolean,
	bufferedCount: number,
}

export type TombstoneSnapshot = {
	runtimeEnemyId: number,
	revision: number,
}

export type ConvergedSnapshot = {
	locked: boolean,
	matchId: string?,
	enemyEpoch: number?,
	lastSequence: number?,
	entries: { any },
	tombstones: { TombstoneSnapshot },
	seenCount: number,
	bufferedCount: number,
	assemblingSnapshot: boolean,
	receiptPending: boolean,
	recoveryRequired: boolean,
}

export type State = {
	observeMessage: (self: State, message: EnemyProtocol.EnemyReplicationMessage) -> Result.Result<ApplyOutcome, Error>,
	observeReceipt: (
		self: State,
		receipt: EnemyProtocol.EnemySnapshotReceipt,
		now: unknown
	) -> Result.Result<ApplyOutcome, Error>,
	advance: (self: State, now: unknown) -> Result.Result<ApplyOutcome, Error>,
	getSnapshot: (self: State) -> Result.Result<ConvergedSnapshot, Error>,
	reset: (self: State) -> Result.Result<boolean, Error>,
	cleanup: (self: State) -> Result.Result<boolean, Error>,
}

type DeltaMessage = {
	kind: "SpawnBatch" | "CorrectionBatch" | "StateChangeBatch" | "DespawnBatch",
	matchId: string,
	enemyEpoch: number,
	sequence: number,
	entries: { any },
}

type SnapshotBegin = {
	kind: "SnapshotBegin",
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	chunkCount: number,
	totalEntries: number,
}

type SnapshotChunk = {
	kind: "SnapshotChunk",
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	chunkIndex: number,
	entries: { any },
}

type SnapshotEnd = {
	kind: "SnapshotEnd",
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	chunkCount: number,
	totalEntries: number,
}

type SnapshotReceipt = {
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	chunkCount: number,
	totalEntries: number,
}

type SnapshotAssembly = {
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	chunkCount: number,
	totalEntries: number,
	chunks: { [number]: { any } },
	receivedChunkCount: number,
	endSeen: boolean,
}

type ReceiptState = SnapshotReceipt & {
	deadline: number,
}

type StateData = {
	cleaned: boolean,
	matchId: string?,
	enemyEpoch: number?,
	lastSequence: number?,
	lastSnapshotId: number?,
	activeById: { [number]: any },
	revisionById: { [number]: number },
	seenById: { [number]: boolean },
	seenCount: number,
	tombstoneById: { [number]: any },
	buffered: { DeltaMessage },
	assembly: SnapshotAssembly?,
	receipt: ReceiptState?,
	recoveryRequired: boolean,
	recoverySticky: boolean,
	lastNow: number?,
}

local MAX_ACTIVE_ENEMIES = EnemyProtocol.MAX_ACTIVE_ENEMIES
local MAX_LIFETIME_ENEMIES = EnemyProtocol.MAX_LIFETIME_ENEMIES
local MAX_BUFFERED_DELTAS = EnemyProtocol.MAX_BUFFERED_DELTA_MESSAGES
local MAX_SNAPSHOT_CHUNKS = EnemyProtocol.MAX_SNAPSHOT_CHUNKS
local MAX_SNAPSHOT_ENTRIES = EnemyProtocol.MAX_SNAPSHOT_ENTRIES
local MAX_SNAPSHOT_ID = EnemyProtocol.MAX_SNAPSHOT_ID
local SNAPSHOT_TIMEOUT_SECONDS = EnemyProtocol.SNAPSHOT_RECEIPT_TIMEOUT_SECONDS
local MAX_ENTRIES_PER_MESSAGE = EnemyProtocol.MAX_ENTRIES_PER_MESSAGE
local MAX_ENEMY_EPOCH = EnemyProtocol.MAX_ENEMY_EPOCH
local MAX_CANONICAL_DEPTH = 8
local MAX_CANONICAL_NODES = 512

local StateMethods = {}
StateMethods.__index = StateMethods

local STATE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: StateData }

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_CONTEXT = table.freeze({ code = "INVALID_CONTEXT" :: "INVALID_CONTEXT" }),
	INVALID_MESSAGE = table.freeze({ code = "INVALID_MESSAGE" :: "INVALID_MESSAGE" }),
	INVALID_RECEIPT = table.freeze({ code = "INVALID_RECEIPT" :: "INVALID_RECEIPT" }),
	INVALID_TIME = table.freeze({ code = "INVALID_TIME" :: "INVALID_TIME" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local function failure(code: ErrorCode)
	return Result.err(ERRORS[code])
end

local function requireData(value: unknown): StateData
	if type(value) ~= "table" then
		error("[ATD_ENEMY_REPLICATION_STATE][code=INVALID_CONTEXT]", 0)
	end
	local data = STATE_DATA[value :: any]
	if data == nil then
		error("[ATD_ENEMY_REPLICATION_STATE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function isSafeIntegerInRange(value: unknown, minimum: number, maximum: number): boolean
	return type(value) == "number"
		and Validation.isSafeInteger(value)
		and (value :: number) >= minimum
		and (value :: number) <= maximum
end

local function isIdentity(matchId: unknown, enemyEpoch: unknown): boolean
	return type(matchId) == "string"
		and #matchId >= 1
		and #matchId <= 128
		and isSafeIntegerInRange(enemyEpoch, 1, MAX_ENEMY_EPOCH)
end

local function sameIdentity(
	leftMatchId: string,
	leftEnemyEpoch: number,
	rightMatchId: string,
	rightEnemyEpoch: number
): boolean
	return leftMatchId == rightMatchId and leftEnemyEpoch == rightEnemyEpoch
end

local function isCanonicalGraph(root: unknown): boolean
	local visiting: { [any]: boolean } = {}
	local visited: { [any]: boolean } = {}
	local nodeCount = 0
	local visit: (unknown, number) -> boolean
	visit = function(value: unknown, depth: number): boolean
		nodeCount += 1
		if nodeCount > MAX_CANONICAL_NODES or depth > MAX_CANONICAL_DEPTH then
			return false
		end
		local valueType = typeof(value)
		if valueType == "number" then
			return Validation.isFiniteNumber(value :: number)
		elseif valueType == "string" or valueType == "boolean" or valueType == "nil" then
			return true
		elseif valueType == "Vector3" then
			local vector = value :: Vector3
			return Validation.isFiniteNumber(vector.X)
				and Validation.isFiniteNumber(vector.Y)
				and Validation.isFiniteNumber(vector.Z)
		elseif valueType == "CFrame" then
			local components = { (value :: CFrame):GetComponents() }
			for _, component in components do
				if not Validation.isFiniteNumber(component) then
					return false
				end
			end
			return true
		elseif valueType ~= "table" then
			return false
		end

		local tableValue = value :: { [any]: any }
		if not table.isfrozen(tableValue) or getmetatable(tableValue) ~= nil then
			return false
		end
		if visiting[tableValue] then
			return false
		end
		if visited[tableValue] then
			return true
		end
		visiting[tableValue] = true
		for key, child in next, tableValue do
			local keyType = type(key)
			if
				(keyType ~= "string" and keyType ~= "number")
				or not visit(key, depth + 1)
				or not visit(child, depth + 1)
			then
				visiting[tableValue] = nil
				return false
			end
		end
		visiting[tableValue] = nil
		visited[tableValue] = true
		return true
	end
	return visit(root, 1)
end

local function isExactArray(value: unknown, minimum: number, maximum: number): boolean
	if type(value) ~= "table" or not table.isfrozen(value :: any) then
		return false
	end
	local array = value :: { [any]: any }
	local length = #array
	if length < minimum or length > maximum then
		return false
	end
	local count = 0
	for key in next, array do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return false
		end
		count += 1
	end
	return count == length
end

local function isEntry(value: unknown): boolean
	if type(value) ~= "table" or not table.isfrozen(value :: any) then
		return false
	end
	local entry = value :: any
	return isSafeIntegerInRange(entry.runtimeEnemyId, 1, MAX_LIFETIME_ENEMIES)
		and isSafeIntegerInRange(entry.revision, 1, Validation.MAX_SAFE_INTEGER)
end

local function entriesAreCanonical(entries: unknown, minimum: number, requireSorted: boolean): boolean
	if not isExactArray(entries, minimum, MAX_ENTRIES_PER_MESSAGE) then
		return false
	end
	local seen: { [number]: boolean } = {}
	local previousRuntimeEnemyId: number? = nil
	for _, entry in entries :: { any } do
		if
			not isEntry(entry)
			or seen[entry.runtimeEnemyId]
			or (requireSorted and previousRuntimeEnemyId ~= nil and entry.runtimeEnemyId <= previousRuntimeEnemyId)
		then
			return false
		end
		seen[entry.runtimeEnemyId] = true
		previousRuntimeEnemyId = entry.runtimeEnemyId
	end
	return true
end

local function snapshotCountsAreValid(chunkCount: unknown, totalEntries: unknown): boolean
	if
		not isSafeIntegerInRange(chunkCount, 0, MAX_SNAPSHOT_CHUNKS)
		or not isSafeIntegerInRange(totalEntries, 0, MAX_SNAPSHOT_ENTRIES)
	then
		return false
	end
	local expectedChunkCount = if totalEntries == 0
		then 0
		else math.ceil((totalEntries :: number) / MAX_ENTRIES_PER_MESSAGE)
	return chunkCount == expectedChunkCount
end

local function isDeltaMessage(value: unknown): boolean
	if type(value) ~= "table" or not isCanonicalGraph(value) then
		return false
	end
	local message = value :: any
	local kind = message.kind
	return (kind == "SpawnBatch" or kind == "CorrectionBatch" or kind == "StateChangeBatch" or kind == "DespawnBatch")
		and isIdentity(message.matchId, message.enemyEpoch)
		and isSafeIntegerInRange(message.sequence, 1, Validation.MAX_SAFE_INTEGER)
		and entriesAreCanonical(message.entries, 0, false)
end

local function isSnapshotBegin(value: unknown): boolean
	if type(value) ~= "table" or not isCanonicalGraph(value) then
		return false
	end
	local message = value :: any
	return message.kind == "SnapshotBegin"
		and isIdentity(message.matchId, message.enemyEpoch)
		and isSafeIntegerInRange(message.baseSequence, 0, Validation.MAX_SAFE_INTEGER)
		and isSafeIntegerInRange(message.snapshotId, 1, MAX_SNAPSHOT_ID)
		and snapshotCountsAreValid(message.chunkCount, message.totalEntries)
end

local function isSnapshotChunk(value: unknown): boolean
	if type(value) ~= "table" or not isCanonicalGraph(value) then
		return false
	end
	local message = value :: any
	return message.kind == "SnapshotChunk"
		and isIdentity(message.matchId, message.enemyEpoch)
		and isSafeIntegerInRange(message.baseSequence, 0, Validation.MAX_SAFE_INTEGER)
		and isSafeIntegerInRange(message.snapshotId, 1, MAX_SNAPSHOT_ID)
		and isSafeIntegerInRange(message.chunkIndex, 1, MAX_SNAPSHOT_CHUNKS)
		and entriesAreCanonical(message.entries, 1, true)
end

local function isSnapshotEnd(value: unknown): boolean
	if type(value) ~= "table" or not isCanonicalGraph(value) then
		return false
	end
	local message = value :: any
	return message.kind == "SnapshotEnd"
		and isIdentity(message.matchId, message.enemyEpoch)
		and isSafeIntegerInRange(message.baseSequence, 0, Validation.MAX_SAFE_INTEGER)
		and isSafeIntegerInRange(message.snapshotId, 1, MAX_SNAPSHOT_ID)
		and snapshotCountsAreValid(message.chunkCount, message.totalEntries)
end

local function makeOutcome(
	data: StateData,
	kind: ApplyKind,
	appliedMessageCount: number?,
	appliedEntryCount: number?,
	identityChanged: boolean?,
	recoveryRequested: boolean?
): ApplyOutcome
	return table.freeze({
		kind = kind,
		appliedMessageCount = appliedMessageCount or 0,
		appliedEntryCount = appliedEntryCount or 0,
		identityChanged = identityChanged == true,
		recoveryRequested = recoveryRequested == true,
		recoveryRequired = data.recoveryRequired,
		bufferedCount = #data.buffered,
	})
end

local function latchRecovery(data: StateData, sticky: boolean): boolean
	local requested = not data.recoveryRequired
	data.recoveryRequired = true
	data.recoverySticky = data.recoverySticky or sticky
	return requested
end

local function clearSnapshotExchange(data: StateData)
	data.assembly = nil
	data.receipt = nil
end

local function identityMatchesLock(data: StateData, matchId: string, enemyEpoch: number): boolean
	return data.matchId ~= nil and sameIdentity(data.matchId :: string, data.enemyEpoch :: number, matchId, enemyEpoch)
end

local function appliedSnapshotOrder(
	data: StateData,
	matchId: string,
	enemyEpoch: number,
	snapshotId: number
): ApplyKind?
	if data.matchId == matchId and data.enemyEpoch ~= nil and enemyEpoch < (data.enemyEpoch :: number) then
		return "Stale"
	end
	if not identityMatchesLock(data, matchId, enemyEpoch) or data.lastSnapshotId == nil then
		return nil
	elseif snapshotId == data.lastSnapshotId then
		return "Duplicate"
	elseif snapshotId < data.lastSnapshotId then
		return "Stale"
	end
	return nil
end

local function sameDelta(left: DeltaMessage, right: DeltaMessage): boolean
	return sameIdentity(left.matchId, left.enemyEpoch, right.matchId, right.enemyEpoch)
		and left.sequence == right.sequence
end

local function findBuffered(data: StateData, matchId: string, enemyEpoch: number, sequence: number): number?
	for index, message in data.buffered do
		if sameIdentity(message.matchId, message.enemyEpoch, matchId, enemyEpoch) and message.sequence == sequence then
			return index
		end
	end
	return nil
end

local function bufferDelta(data: StateData, message: DeltaMessage): (ApplyKind, boolean)
	for _, buffered in data.buffered do
		if sameDelta(buffered, message) then
			return "Duplicate", false
		end
	end
	if #data.buffered >= MAX_BUFFERED_DELTAS then
		table.clear(data.buffered)
		return "RecoveryRequired", latchRecovery(data, true)
	end
	table.insert(data.buffered, message)
	return "Buffered", false
end

local function preflightDelta(data: StateData, message: DeltaMessage): boolean
	if message.kind == "SpawnBatch" then
		local additionCount = 0
		for _, entry in message.entries do
			local runtimeEnemyId = entry.runtimeEnemyId
			local active = data.activeById[runtimeEnemyId]
			local seen = data.seenById[runtimeEnemyId] == true
			if seen then
				-- A snapshot can include an active record whose queued SpawnBatch
				-- has not received a sequence yet. That later contiguous spawn is
				-- idempotent for the still-active identity, but a terminal or
				-- snapshot-omitted identity may never be resurrected.
				if active == nil or data.tombstoneById[runtimeEnemyId] ~= nil then
					return false
				end
			elseif active ~= nil or data.tombstoneById[runtimeEnemyId] ~= nil then
				return false
			else
				additionCount += 1
			end
		end
		local activeCount = 0
		for _ in data.activeById do
			activeCount += 1
		end
		return additionCount <= MAX_ACTIVE_ENEMIES - activeCount
	elseif message.kind == "CorrectionBatch" or message.kind == "StateChangeBatch" then
		for _, entry in message.entries do
			local runtimeEnemyId = entry.runtimeEnemyId
			if data.activeById[runtimeEnemyId] == nil and not data.seenById[runtimeEnemyId] then
				return false
			end
		end
	end
	return true
end

local function applyDeltaNow(data: StateData, message: DeltaMessage): (boolean, number)
	if not preflightDelta(data, message) then
		return false, 0
	end
	local appliedEntryCount = 0
	if message.kind == "SpawnBatch" then
		for _, entry in message.entries do
			local runtimeEnemyId = entry.runtimeEnemyId
			local current = data.activeById[runtimeEnemyId]
			if current ~= nil then
				local currentRevision = data.revisionById[runtimeEnemyId] or 0
				if entry.revision > currentRevision then
					data.activeById[runtimeEnemyId] = entry
					data.revisionById[runtimeEnemyId] = entry.revision
					appliedEntryCount += 1
				end
			else
				data.activeById[runtimeEnemyId] = entry
				data.revisionById[runtimeEnemyId] = entry.revision
				data.seenById[runtimeEnemyId] = true
				data.seenCount += 1
				appliedEntryCount += 1
			end
		end
	elseif message.kind == "CorrectionBatch" or message.kind == "StateChangeBatch" then
		for _, entry in message.entries do
			local runtimeEnemyId = entry.runtimeEnemyId
			local current = data.activeById[runtimeEnemyId]
			if current ~= nil and data.tombstoneById[runtimeEnemyId] == nil then
				local currentRevision = data.revisionById[runtimeEnemyId] or 0
				if entry.revision > currentRevision then
					data.activeById[runtimeEnemyId] = entry
					data.revisionById[runtimeEnemyId] = entry.revision
					appliedEntryCount += 1
				end
			end
		end
	else
		for _, entry in message.entries do
			local runtimeEnemyId = entry.runtimeEnemyId
			if data.tombstoneById[runtimeEnemyId] == nil then
				local currentRevision = data.revisionById[runtimeEnemyId] or 0
				if entry.revision > currentRevision then
					data.activeById[runtimeEnemyId] = nil
					data.tombstoneById[runtimeEnemyId] = entry
					data.revisionById[runtimeEnemyId] = math.max(currentRevision, entry.revision)
					if not data.seenById[runtimeEnemyId] then
						data.seenById[runtimeEnemyId] = true
						data.seenCount += 1
					end
					appliedEntryCount += 1
				end
			end
		end
	end
	data.lastSequence = message.sequence
	return true, appliedEntryCount
end

local function hasLockedBuffer(data: StateData): boolean
	for _, message in data.buffered do
		if identityMatchesLock(data, message.matchId, message.enemyEpoch) then
			return true
		end
	end
	return false
end

local function drainBuffered(data: StateData): (number, number, boolean)
	local appliedMessageCount = 0
	local appliedEntryCount = 0
	local recoveryRequested = false
	while data.lastSequence ~= nil and data.lastSequence < Validation.MAX_SAFE_INTEGER do
		local index =
			findBuffered(data, data.matchId :: string, data.enemyEpoch :: number, (data.lastSequence :: number) + 1)
		if index == nil then
			break
		end
		local message = table.remove(data.buffered, index)
		local applied, entryCount = applyDeltaNow(data, message)
		if not applied then
			table.insert(data.buffered, message)
			recoveryRequested = latchRecovery(data, true) or recoveryRequested
			break
		end
		appliedMessageCount += 1
		appliedEntryCount += entryCount
	end
	if hasLockedBuffer(data) then
		recoveryRequested = latchRecovery(data, false) or recoveryRequested
	elseif not data.recoverySticky then
		data.recoveryRequired = false
	end
	return appliedMessageCount, appliedEntryCount, recoveryRequested
end

local function processLockedDelta(data: StateData, message: DeltaMessage): ApplyOutcome
	if not identityMatchesLock(data, message.matchId, message.enemyEpoch) then
		return makeOutcome(data, "Foreign", nil, nil, nil, nil)
	end
	local lastSequence = data.lastSequence :: number
	if message.sequence < lastSequence then
		return makeOutcome(data, "Stale", nil, nil, nil, nil)
	elseif message.sequence == lastSequence then
		return makeOutcome(data, "Duplicate", nil, nil, nil, nil)
	elseif message.sequence > lastSequence + 1 then
		local kind, overflowRequested = bufferDelta(data, message)
		local gapRequested = if kind == "Buffered" then latchRecovery(data, false) else false
		return makeOutcome(data, kind, nil, nil, nil, overflowRequested or gapRequested)
	end

	local applied, appliedEntryCount = applyDeltaNow(data, message)
	if not applied then
		local _, overflowRequested = bufferDelta(data, message)
		local requested = latchRecovery(data, true) or overflowRequested
		return makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested)
	end
	local drainedMessages, drainedEntries, recoveryRequested = drainBuffered(data)
	return makeOutcome(
		data,
		"Applied",
		1 + drainedMessages,
		appliedEntryCount + drainedEntries,
		false,
		recoveryRequested
	)
end

local function metadataMatchesReceipt(
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	chunkCount: number,
	totalEntries: number,
	receipt: SnapshotReceipt
): boolean
	return sameIdentity(matchId, enemyEpoch, receipt.matchId, receipt.enemyEpoch)
		and baseSequence == receipt.baseSequence
		and snapshotId == receipt.snapshotId
		and chunkCount == receipt.chunkCount
		and totalEntries == receipt.totalEntries
end

local function assemblyMatchesMessage(assembly: SnapshotAssembly, message: any): boolean
	return sameIdentity(assembly.matchId, assembly.enemyEpoch, message.matchId, message.enemyEpoch)
		and assembly.baseSequence == message.baseSequence
		and assembly.snapshotId == message.snapshotId
end

local function compareSnapshotIds(
	leftMatchId: string,
	leftEnemyEpoch: number,
	leftSnapshotId: number,
	rightMatchId: string,
	rightEnemyEpoch: number,
	rightSnapshotId: number
): number?
	if leftMatchId ~= rightMatchId then
		return nil
	elseif leftEnemyEpoch < rightEnemyEpoch then
		return -1
	elseif leftEnemyEpoch > rightEnemyEpoch then
		return 1
	elseif leftSnapshotId < rightSnapshotId then
		return -1
	elseif leftSnapshotId > rightSnapshotId then
		return 1
	end
	return 0
end

local function clearMatchingSnapshotExchange(data: StateData, message: any)
	local assembly = data.assembly
	if assembly ~= nil and assemblyMatchesMessage(assembly, message) then
		data.assembly = nil
	end
	local receipt = data.receipt
	if
		receipt ~= nil
		and sameIdentity(receipt.matchId, receipt.enemyEpoch, message.matchId, message.enemyEpoch)
		and receipt.baseSequence == message.baseSequence
		and receipt.snapshotId == message.snapshotId
	then
		data.receipt = nil
	end
end

local function hasStaleSnapshotBase(data: StateData, message: any): boolean
	return identityMatchesLock(data, message.matchId, message.enemyEpoch)
		and data.lastSequence ~= nil
		and message.baseSequence < (data.lastSequence :: number)
end

local function installSnapshot(data: StateData, assembly: SnapshotAssembly, entries: { any }): ApplyOutcome
	local identityChanged = not identityMatchesLock(data, assembly.matchId, assembly.enemyEpoch)
	local previousLastSequence = data.lastSequence
	local snapshotOrder = appliedSnapshotOrder(data, assembly.matchId, assembly.enemyEpoch, assembly.snapshotId)
	if snapshotOrder ~= nil then
		clearSnapshotExchange(data)
		return makeOutcome(data, snapshotOrder, nil, nil, nil, nil)
	end
	if not identityChanged and previousLastSequence ~= nil and assembly.baseSequence < previousLastSequence then
		clearSnapshotExchange(data)
		return makeOutcome(data, "Stale", nil, nil, nil, nil)
	end

	if not identityChanged then
		for _, entry in entries do
			local runtimeEnemyId = entry.runtimeEnemyId
			if
				data.tombstoneById[runtimeEnemyId] ~= nil
				or (data.seenById[runtimeEnemyId] and data.activeById[runtimeEnemyId] == nil)
			then
				clearSnapshotExchange(data)
				local requested = latchRecovery(data, true)
				return makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested)
			end
		end
	else
		table.clear(data.activeById)
		table.clear(data.revisionById)
		table.clear(data.seenById)
		table.clear(data.tombstoneById)
		data.seenCount = 0
	end

	local nextActiveById: { [number]: any } = {}
	for _, entry in entries do
		local runtimeEnemyId = entry.runtimeEnemyId
		local selected = entry
		if not identityChanged then
			local existing = data.activeById[runtimeEnemyId]
			local currentRevision = data.revisionById[runtimeEnemyId] or 0
			if existing ~= nil and entry.revision <= currentRevision then
				selected = existing
			end
		end
		nextActiveById[runtimeEnemyId] = selected
		local selectedRevision = selected.revision
		data.revisionById[runtimeEnemyId] = math.max(data.revisionById[runtimeEnemyId] or 0, selectedRevision)
		if not data.seenById[runtimeEnemyId] then
			data.seenById[runtimeEnemyId] = true
			data.seenCount += 1
		end
	end
	table.clear(data.activeById)
	for runtimeEnemyId, entry in nextActiveById do
		data.activeById[runtimeEnemyId] = entry
	end

	data.matchId = assembly.matchId
	data.enemyEpoch = assembly.enemyEpoch
	data.lastSequence = assembly.baseSequence
	data.lastSnapshotId = assembly.snapshotId
	local retainedBuffer: { DeltaMessage } = {}
	for _, message in data.buffered do
		if
			sameIdentity(message.matchId, message.enemyEpoch, assembly.matchId, assembly.enemyEpoch)
			and message.sequence > assembly.baseSequence
		then
			table.insert(retainedBuffer, message)
		end
	end
	data.buffered = retainedBuffer
	clearSnapshotExchange(data)
	data.recoveryRequired = false
	data.recoverySticky = false
	local drainedMessages, drainedEntries, recoveryRequested = drainBuffered(data)
	return makeOutcome(
		data,
		"SnapshotApplied",
		drainedMessages,
		#entries + drainedEntries,
		identityChanged,
		recoveryRequested
	)
end

local function tryCommitSnapshot(data: StateData): ApplyOutcome?
	local assembly = data.assembly
	local receipt = data.receipt
	if assembly == nil or receipt == nil or not assembly.endSeen then
		return nil
	end
	if
		not metadataMatchesReceipt(
			assembly.matchId,
			assembly.enemyEpoch,
			assembly.baseSequence,
			assembly.snapshotId,
			assembly.chunkCount,
			assembly.totalEntries,
			receipt
		)
	then
		clearSnapshotExchange(data)
		local requested = latchRecovery(data, true)
		return makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested)
	end
	if assembly.receivedChunkCount < assembly.chunkCount then
		return nil
	end

	local entries = table.create(assembly.totalEntries)
	local previousRuntimeEnemyId = 0
	for chunkIndex = 1, assembly.chunkCount do
		local chunk = assembly.chunks[chunkIndex]
		if chunk == nil then
			return nil
		end
		local expectedLength = if chunkIndex < assembly.chunkCount
			then MAX_ENTRIES_PER_MESSAGE
			else assembly.totalEntries - MAX_ENTRIES_PER_MESSAGE * (assembly.chunkCount - 1)
		if #chunk ~= expectedLength then
			clearSnapshotExchange(data)
			local requested = latchRecovery(data, true)
			return makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested)
		end
		for _, entry in chunk do
			if entry.runtimeEnemyId <= previousRuntimeEnemyId then
				clearSnapshotExchange(data)
				local requested = latchRecovery(data, true)
				return makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested)
			end
			previousRuntimeEnemyId = entry.runtimeEnemyId
			table.insert(entries, entry)
		end
	end
	if #entries ~= assembly.totalEntries then
		clearSnapshotExchange(data)
		local requested = latchRecovery(data, true)
		return makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested)
	end
	return installSnapshot(data, assembly, entries)
end

local function observeBegin(data: StateData, message: SnapshotBegin): ApplyOutcome
	local receipt = data.receipt
	if
		receipt ~= nil
		and not metadataMatchesReceipt(
			message.matchId,
			message.enemyEpoch,
			message.baseSequence,
			message.snapshotId,
			message.chunkCount,
			message.totalEntries,
			receipt
		)
	then
		local order = compareSnapshotIds(
			message.matchId,
			message.enemyEpoch,
			message.snapshotId,
			receipt.matchId,
			receipt.enemyEpoch,
			receipt.snapshotId
		)
		if order == -1 then
			return makeOutcome(data, "Stale", nil, nil, nil, nil)
		elseif order == 1 then
			data.receipt = nil
		elseif order == 0 then
			clearSnapshotExchange(data)
			local requested = latchRecovery(data, true)
			return makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested)
		else
			return makeOutcome(data, "Foreign", nil, nil, nil, nil)
		end
	end
	local assembly = data.assembly
	if assembly ~= nil then
		if
			metadataMatchesReceipt(
				message.matchId,
				message.enemyEpoch,
				message.baseSequence,
				message.snapshotId,
				message.chunkCount,
				message.totalEntries,
				assembly
			)
		then
			return makeOutcome(data, "Duplicate", nil, nil, nil, nil)
		end
		local order = compareSnapshotIds(
			message.matchId,
			message.enemyEpoch,
			message.snapshotId,
			assembly.matchId,
			assembly.enemyEpoch,
			assembly.snapshotId
		)
		if order == -1 then
			return makeOutcome(data, "Stale", nil, nil, nil, nil)
		elseif order == 0 then
			clearSnapshotExchange(data)
			local requested = latchRecovery(data, true)
			return makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested)
		end
	end
	data.assembly = {
		matchId = message.matchId,
		enemyEpoch = message.enemyEpoch,
		baseSequence = message.baseSequence,
		snapshotId = message.snapshotId,
		chunkCount = message.chunkCount,
		totalEntries = message.totalEntries,
		chunks = {},
		receivedChunkCount = 0,
		endSeen = false,
	}
	local committed = tryCommitSnapshot(data)
	return committed or makeOutcome(data, "SnapshotProgress", nil, nil, nil, nil)
end

local function observeChunk(data: StateData, message: SnapshotChunk): ApplyOutcome
	local assembly = data.assembly
	if assembly == nil or not assemblyMatchesMessage(assembly, message) then
		local requested = latchRecovery(data, true)
		return makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested)
	end
	if message.chunkIndex > assembly.chunkCount then
		clearSnapshotExchange(data)
		local requested = latchRecovery(data, true)
		return makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested)
	end
	if assembly.chunks[message.chunkIndex] ~= nil then
		return makeOutcome(data, "Duplicate", nil, nil, nil, nil)
	end
	assembly.chunks[message.chunkIndex] = message.entries
	assembly.receivedChunkCount += 1
	local committed = tryCommitSnapshot(data)
	return committed or makeOutcome(data, "SnapshotProgress", nil, nil, nil, nil)
end

local function observeEnd(data: StateData, message: SnapshotEnd): ApplyOutcome
	local assembly = data.assembly
	if
		assembly == nil
		or not assemblyMatchesMessage(assembly, message)
		or assembly.chunkCount ~= message.chunkCount
		or assembly.totalEntries ~= message.totalEntries
	then
		clearSnapshotExchange(data)
		local requested = latchRecovery(data, true)
		return makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested)
	end
	if assembly.endSeen then
		return makeOutcome(data, "Duplicate", nil, nil, nil, nil)
	end
	assembly.endSeen = true
	local committed = tryCommitSnapshot(data)
	return committed or makeOutcome(data, "SnapshotProgress", nil, nil, nil, nil)
end

local function clearState(data: StateData)
	data.matchId = nil
	data.enemyEpoch = nil
	data.lastSequence = nil
	data.lastSnapshotId = nil
	table.clear(data.activeById)
	table.clear(data.revisionById)
	table.clear(data.seenById)
	table.clear(data.tombstoneById)
	table.clear(data.buffered)
	data.seenCount = 0
	data.assembly = nil
	data.receipt = nil
	data.recoveryRequired = false
	data.recoverySticky = false
	data.lastNow = nil
end

function StateMethods.observeMessage(
	self: State,
	messageValue: EnemyProtocol.EnemyReplicationMessage
): Result.Result<ApplyOutcome, Error>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local protocolResult = EnemyProtocol.validateEnemyReplication(messageValue)
	if not protocolResult.ok then
		return failure("INVALID_MESSAGE")
	end
	local value = protocolResult.value :: unknown
	if isDeltaMessage(value) then
		local message = value :: DeltaMessage
		if data.matchId == nil then
			local kind, recoveryRequested = bufferDelta(data, message)
			return Result.ok(makeOutcome(data, kind, nil, nil, nil, recoveryRequested))
		end
		return Result.ok(processLockedDelta(data, message))
	elseif isSnapshotBegin(value) then
		local message = value :: SnapshotBegin
		local snapshotOrder = appliedSnapshotOrder(data, message.matchId, message.enemyEpoch, message.snapshotId)
		if snapshotOrder ~= nil then
			return Result.ok(makeOutcome(data, snapshotOrder))
		elseif hasStaleSnapshotBase(data, message) then
			clearMatchingSnapshotExchange(data, message)
			return Result.ok(makeOutcome(data, "Stale"))
		end
		return Result.ok(observeBegin(data, message))
	elseif isSnapshotChunk(value) then
		local message = value :: SnapshotChunk
		local snapshotOrder = appliedSnapshotOrder(data, message.matchId, message.enemyEpoch, message.snapshotId)
		if snapshotOrder ~= nil then
			return Result.ok(makeOutcome(data, snapshotOrder))
		elseif hasStaleSnapshotBase(data, message) then
			clearMatchingSnapshotExchange(data, message)
			return Result.ok(makeOutcome(data, "Stale"))
		end
		return Result.ok(observeChunk(data, message))
	elseif isSnapshotEnd(value) then
		local message = value :: SnapshotEnd
		local snapshotOrder = appliedSnapshotOrder(data, message.matchId, message.enemyEpoch, message.snapshotId)
		if snapshotOrder ~= nil then
			return Result.ok(makeOutcome(data, snapshotOrder))
		elseif hasStaleSnapshotBase(data, message) then
			clearMatchingSnapshotExchange(data, message)
			return Result.ok(makeOutcome(data, "Stale"))
		end
		return Result.ok(observeEnd(data, message))
	end
	return failure("INVALID_MESSAGE")
end

function StateMethods.observeReceipt(
	self: State,
	receiptValue: EnemyProtocol.EnemySnapshotReceipt,
	nowValue: unknown
): Result.Result<ApplyOutcome, Error>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local protocolResult = EnemyProtocol.validateEnemySnapshotReceipt(receiptValue)
	if not protocolResult.ok then
		return failure("INVALID_RECEIPT")
	end
	if
		type(nowValue) ~= "number"
		or not Validation.isFiniteNumber(nowValue)
		or nowValue < 0
		or (data.lastNow ~= nil and nowValue < data.lastNow)
		or not Validation.isFiniteNumber(nowValue + SNAPSHOT_TIMEOUT_SECONDS)
	then
		return failure("INVALID_TIME")
	end
	local receipt = (protocolResult.value :: any) :: SnapshotReceipt
	data.lastNow = nowValue
	local snapshotOrder = appliedSnapshotOrder(data, receipt.matchId, receipt.enemyEpoch, receipt.snapshotId)
	if snapshotOrder ~= nil then
		return Result.ok(makeOutcome(data, snapshotOrder, nil, nil, nil, nil))
	end
	if
		identityMatchesLock(data, receipt.matchId, receipt.enemyEpoch)
		and data.lastSequence ~= nil
		and receipt.baseSequence < data.lastSequence
	then
		clearMatchingSnapshotExchange(data, receipt)
		return Result.ok(makeOutcome(data, "Stale", nil, nil, nil, nil))
	end
	local current = data.receipt
	if
		current ~= nil
		and metadataMatchesReceipt(
			receipt.matchId,
			receipt.enemyEpoch,
			receipt.baseSequence,
			receipt.snapshotId,
			receipt.chunkCount,
			receipt.totalEntries,
			current
		)
	then
		return Result.ok(makeOutcome(data, "Duplicate", nil, nil, nil, nil))
	end
	if current ~= nil then
		local order = compareSnapshotIds(
			receipt.matchId,
			receipt.enemyEpoch,
			receipt.snapshotId,
			current.matchId,
			current.enemyEpoch,
			current.snapshotId
		)
		if order == -1 then
			return Result.ok(makeOutcome(data, "Stale", nil, nil, nil, nil))
		elseif order == 0 then
			clearSnapshotExchange(data)
			local requested = latchRecovery(data, true)
			return Result.ok(makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested))
		end
	end
	local assembly = data.assembly
	if
		assembly ~= nil
		and not metadataMatchesReceipt(
			assembly.matchId,
			assembly.enemyEpoch,
			assembly.baseSequence,
			assembly.snapshotId,
			assembly.chunkCount,
			assembly.totalEntries,
			receipt
		)
	then
		local order = compareSnapshotIds(
			receipt.matchId,
			receipt.enemyEpoch,
			receipt.snapshotId,
			assembly.matchId,
			assembly.enemyEpoch,
			assembly.snapshotId
		)
		if order == -1 then
			return Result.ok(makeOutcome(data, "Stale", nil, nil, nil, nil))
		elseif order == 0 then
			clearSnapshotExchange(data)
			local requested = latchRecovery(data, true)
			return Result.ok(makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested))
		end
		data.assembly = nil
	end
	data.receipt = {
		matchId = receipt.matchId,
		enemyEpoch = receipt.enemyEpoch,
		baseSequence = receipt.baseSequence,
		snapshotId = receipt.snapshotId,
		chunkCount = receipt.chunkCount,
		totalEntries = receipt.totalEntries,
		deadline = nowValue + SNAPSHOT_TIMEOUT_SECONDS,
	}
	local committed = tryCommitSnapshot(data)
	return Result.ok(committed or makeOutcome(data, "SnapshotProgress", nil, nil, nil, nil))
end

function StateMethods.advance(self: State, nowValue: unknown): Result.Result<ApplyOutcome, Error>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if
		type(nowValue) ~= "number"
		or not Validation.isFiniteNumber(nowValue)
		or nowValue < 0
		or (data.lastNow ~= nil and nowValue < data.lastNow)
	then
		return failure("INVALID_TIME")
	end
	data.lastNow = nowValue
	local receipt = data.receipt
	if receipt ~= nil and nowValue >= receipt.deadline then
		clearSnapshotExchange(data)
		local requested = latchRecovery(data, true)
		return Result.ok(makeOutcome(data, "RecoveryRequired", nil, nil, nil, requested))
	end
	return Result.ok(makeOutcome(data, "Noop", nil, nil, nil, nil))
end

function StateMethods.getSnapshot(self: State): Result.Result<ConvergedSnapshot, Error>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local activeIds = {}
	for runtimeEnemyId in data.activeById do
		table.insert(activeIds, runtimeEnemyId)
	end
	table.sort(activeIds)
	local entries = table.create(#activeIds)
	for index, runtimeEnemyId in activeIds do
		entries[index] = data.activeById[runtimeEnemyId]
	end
	table.freeze(entries)

	local tombstoneIds = {}
	for runtimeEnemyId in data.tombstoneById do
		table.insert(tombstoneIds, runtimeEnemyId)
	end
	table.sort(tombstoneIds)
	local tombstones = table.create(#tombstoneIds)
	for index, runtimeEnemyId in tombstoneIds do
		tombstones[index] = table.freeze({
			runtimeEnemyId = runtimeEnemyId,
			revision = data.revisionById[runtimeEnemyId],
		})
	end
	table.freeze(tombstones)

	return Result.ok(table.freeze({
		locked = data.matchId ~= nil,
		matchId = data.matchId,
		enemyEpoch = data.enemyEpoch,
		lastSequence = data.lastSequence,
		entries = entries,
		tombstones = tombstones,
		seenCount = data.seenCount,
		bufferedCount = #data.buffered,
		assemblingSnapshot = data.assembly ~= nil,
		receiptPending = data.receipt ~= nil,
		recoveryRequired = data.recoveryRequired,
	}))
end

function StateMethods.reset(self: State): Result.Result<boolean, Error>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	clearState(data)
	return Result.ok(true)
end

function StateMethods.cleanup(self: State): Result.Result<boolean, Error>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(true)
	end
	clearState(data)
	data.cleaned = true
	return Result.ok(true)
end

local EnemyReplicationState = {}

function EnemyReplicationState.new(): State
	local state = setmetatable({}, StateMethods) :: any
	table.freeze(state)
	STATE_DATA[state] = {
		cleaned = false,
		matchId = nil,
		enemyEpoch = nil,
		lastSequence = nil,
		lastSnapshotId = nil,
		activeById = {},
		revisionById = {},
		seenById = {},
		seenCount = 0,
		tombstoneById = {},
		buffered = {},
		assembly = nil,
		receipt = nil,
		recoveryRequired = false,
		recoverySticky = false,
		lastNow = nil,
	}
	return state :: State
end

table.freeze(StateMethods)
return table.freeze(EnemyReplicationState)
