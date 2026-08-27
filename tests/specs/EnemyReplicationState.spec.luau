--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local EnemyReplicationState = require(script.Parent.Parent.ProductionClientEnemies.EnemyReplicationState)

local Shared = game:GetService("ReplicatedStorage").Shared
local EnemyProtocol = require(Shared.match.EnemyProtocol)

type Assertions = TestHarness.Assertions
type State = EnemyReplicationState.State

local MATCH_A = "match:enemy-state-a"
local MATCH_B = "match:enemy-state-b"

local function canonicalCFrame(position: Vector3): CFrame
	local direction = Vector3.xAxis
	local right = direction:Cross(Vector3.yAxis).Unit
	local up = right:Cross(direction).Unit
	return CFrame.fromMatrix(position, right, up, -direction)
end

local function stateEntry(
	runtimeEnemyId: number,
	revision: number,
	lifecycle: "Active" | "EndpointResolved"?
): { [string]: unknown }
	local selectedLifecycle = lifecycle or "Active"
	local progress = if selectedLifecycle == "EndpointResolved" then 10 else math.min(9, revision)
	local startPosition = Vector3.new(0, 2, 0)
	local endPosition = Vector3.new(10, 2, 0)
	local position = startPosition:Lerp(endPosition, progress / 10)
	return {
		runtimeEnemyId = runtimeEnemyId,
		enemyId = "enemy:phase09-test",
		laneId = "lane:alpha",
		revision = revision,
		lifecycle = selectedLifecycle,
		pathProgress = progress,
		currentHealth = 100,
		maximumHealth = 100,
		slowMultiplier = 1,
		spawnServerTime = 100,
		sampleServerTime = 100 + revision,
		worldCFrame = canonicalCFrame(position),
		effectiveSpeed = 4,
		segmentIndex = 1,
		segmentStartDistance = 0,
		segmentEndDistance = 10,
		segmentStartPosition = startPosition,
		segmentEndPosition = endPosition,
	}
end

local function despawnEntry(runtimeEnemyId: number, revision: number): { [string]: unknown }
	return {
		runtimeEnemyId = runtimeEnemyId,
		revision = revision,
		sampleServerTime = 100 + revision,
		reason = "Endpoint",
	}
end

local function canonicalMessage(value: unknown): EnemyProtocol.EnemyReplicationMessage
	local result = EnemyProtocol.validateEnemyReplication(value)
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=ENEMY_MESSAGE_INVALID][path={result.error.path}]`, 0)
	end
	return result.value
end

local function canonicalReceipt(value: unknown): EnemyProtocol.EnemySnapshotReceipt
	local result = EnemyProtocol.validateEnemySnapshotReceipt(value)
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=ENEMY_RECEIPT_INVALID][path={result.error.path}]`, 0)
	end
	return result.value
end

local function delta(
	kind: "SpawnBatch" | "CorrectionBatch" | "StateChangeBatch" | "DespawnBatch",
	matchId: string,
	enemyEpoch: number,
	sequence: number,
	entries: { { [string]: unknown } }
): EnemyProtocol.EnemyReplicationMessage
	return canonicalMessage({
		kind = kind,
		matchId = matchId,
		enemyEpoch = enemyEpoch,
		sequence = sequence,
		entries = entries,
	})
end

local function boundary(
	kind: "SnapshotBegin" | "SnapshotEnd",
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	chunkCount: number,
	totalEntries: number
): EnemyProtocol.EnemyReplicationMessage
	return canonicalMessage({
		kind = kind,
		matchId = matchId,
		enemyEpoch = enemyEpoch,
		baseSequence = baseSequence,
		snapshotId = snapshotId,
		chunkCount = chunkCount,
		totalEntries = totalEntries,
	})
end

local function chunk(
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	chunkIndex: number,
	entries: { { [string]: unknown } }
): EnemyProtocol.EnemyReplicationMessage
	return canonicalMessage({
		kind = "SnapshotChunk",
		matchId = matchId,
		enemyEpoch = enemyEpoch,
		baseSequence = baseSequence,
		snapshotId = snapshotId,
		chunkIndex = chunkIndex,
		entries = entries,
	})
end

local function receipt(
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	chunkCount: number,
	totalEntries: number
): EnemyProtocol.EnemySnapshotReceipt
	return canonicalReceipt({
		matchId = matchId,
		enemyEpoch = enemyEpoch,
		baseSequence = baseSequence,
		snapshotId = snapshotId,
		chunkCount = chunkCount,
		totalEntries = totalEntries,
	})
end

local function success<T>(result: any): T
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=ENEMY_STATE_FAILURE][detail={result.error.code}]`, 0)
	end
	return result.value :: T
end

local function snapshot(state: State): EnemyReplicationState.ConvergedSnapshot
	return success(state:getSnapshot())
end

local function installSnapshot(
	state: State,
	matchId: string,
	enemyEpoch: number,
	baseSequence: number,
	snapshotId: number,
	entries: { { [string]: unknown } },
	now: number,
	receiptFirst: boolean?
): EnemyReplicationState.ApplyOutcome
	local chunkCount = math.ceil(#entries / EnemyProtocol.MAX_ENTRIES_PER_MESSAGE)
	local snapshotReceipt = receipt(matchId, enemyEpoch, baseSequence, snapshotId, chunkCount, #entries)
	if receiptFirst then
		success(state:observeReceipt(snapshotReceipt, now))
	end
	success(
		state:observeMessage(
			boundary("SnapshotBegin", matchId, enemyEpoch, baseSequence, snapshotId, chunkCount, #entries)
		)
	)
	for chunkIndex = 1, chunkCount do
		local first = (chunkIndex - 1) * EnemyProtocol.MAX_ENTRIES_PER_MESSAGE + 1
		local last = math.min(first + EnemyProtocol.MAX_ENTRIES_PER_MESSAGE - 1, #entries)
		local chunkEntries = {}
		for entryIndex = first, last do
			table.insert(chunkEntries, entries[entryIndex])
		end
		success(state:observeMessage(chunk(matchId, enemyEpoch, baseSequence, snapshotId, chunkIndex, chunkEntries)))
	end
	local endOutcome: EnemyReplicationState.ApplyOutcome = success(
		state:observeMessage(
			boundary("SnapshotEnd", matchId, enemyEpoch, baseSequence, snapshotId, chunkCount, #entries)
		)
	)
	if receiptFirst then
		return endOutcome
	end
	return success(state:observeReceipt(snapshotReceipt, now))
end

local function expectError(assertions: Assertions, result: any, code: EnemyReplicationState.ErrorCode)
	assertions.isFalse(result.ok)
	assertions.equal(result.error.code, code)
end

return TestHarness.suite("pure enemy replication convergence state", {
	TestHarness.case("locks from event-first recovery and drains only contiguous buffered deltas", function(assertions)
		local state = EnemyReplicationState.new()
		success(state:observeMessage(delta("CorrectionBatch", MATCH_A, 1, 7, { stateEntry(1, 3) })))
		success(state:observeMessage(delta("CorrectionBatch", MATCH_A, 1, 4, { stateEntry(1, 1) })))
		success(state:observeMessage(delta("CorrectionBatch", MATCH_A, 1, 6, { stateEntry(1, 2) })))

		local outcome = installSnapshot(state, MATCH_A, 1, 5, 1, { stateEntry(1, 1) }, 10, false)
		assertions.equal(outcome.kind, "SnapshotApplied")
		assertions.equal(outcome.appliedMessageCount, 2)
		assertions.equal(outcome.appliedEntryCount, 3)
		local current = snapshot(state)
		assertions.isTrue(current.locked)
		assertions.equal(current.lastSequence, 7)
		assertions.equal(current.entries[1].revision, 3)
		assertions.equal(current.bufferedCount, 0)

		local receiptFirstState = EnemyReplicationState.new()
		local receiptFirst = installSnapshot(receiptFirstState, MATCH_A, 1, 0, 1, {}, 4, true)
		assertions.equal(receiptFirst.kind, "SnapshotApplied")
		assertions.equal(snapshot(receiptFirstState).lastSequence, 0)
	end),

	TestHarness.case("ignores duplicate and stale sequences then self-heals one bounded gap", function(assertions)
		local state = EnemyReplicationState.new()
		installSnapshot(state, MATCH_A, 1, 0, 1, {}, 1, true)
		local spawn = delta("SpawnBatch", MATCH_A, 1, 1, { stateEntry(1, 1) })
		assertions.equal(success(state:observeMessage(spawn)).kind, "Applied")
		assertions.equal(success(state:observeMessage(spawn)).kind, "Duplicate")

		local gap: EnemyReplicationState.ApplyOutcome =
			success(state:observeMessage(delta("CorrectionBatch", MATCH_A, 1, 3, { stateEntry(1, 3) })))
		assertions.equal(gap.kind, "Buffered")
		assertions.isTrue(gap.recoveryRequested)
		local later: EnemyReplicationState.ApplyOutcome =
			success(state:observeMessage(delta("CorrectionBatch", MATCH_A, 1, 4, { stateEntry(1, 4) })))
		assertions.isFalse(later.recoveryRequested)

		local healed: EnemyReplicationState.ApplyOutcome =
			success(state:observeMessage(delta("CorrectionBatch", MATCH_A, 1, 2, { stateEntry(1, 2) })))
		assertions.equal(healed.appliedMessageCount, 3)
		assertions.equal(healed.appliedEntryCount, 3)
		assertions.isFalse(healed.recoveryRequired)
		local current = snapshot(state)
		assertions.equal(current.lastSequence, 4)
		assertions.equal(current.entries[1].revision, 4)
		assertions.equal(
			success(state:observeMessage(delta("CorrectionBatch", MATCH_A, 1, 2, { stateEntry(1, 5) }))).kind,
			"Stale"
		)
	end),

	TestHarness.case("consumes snapshot-covered spawn sequences without rollback or resurrection", function(assertions)
		local state = EnemyReplicationState.new()
		installSnapshot(state, MATCH_A, 1, 0, 1, { stateEntry(1, 2) }, 1, true)

		local covered: EnemyReplicationState.ApplyOutcome =
			success(state:observeMessage(delta("SpawnBatch", MATCH_A, 1, 1, { stateEntry(1, 1), stateEntry(2, 1) })))
		assertions.equal(covered.kind, "Applied")
		assertions.equal(covered.appliedEntryCount, 1)
		assertions.isFalse(covered.recoveryRequired)
		local afterCovered = snapshot(state)
		assertions.equal(afterCovered.lastSequence, 1)
		assertions.equal(#afterCovered.entries, 2)
		assertions.equal(afterCovered.entries[1].runtimeEnemyId, 1)
		assertions.equal(afterCovered.entries[1].revision, 2)
		assertions.equal(afterCovered.entries[2].runtimeEnemyId, 2)

		local newer: EnemyReplicationState.ApplyOutcome =
			success(state:observeMessage(delta("SpawnBatch", MATCH_A, 1, 2, { stateEntry(1, 3) })))
		assertions.equal(newer.kind, "Applied")
		assertions.equal(newer.appliedEntryCount, 1)
		assertions.equal(snapshot(state).entries[1].revision, 3)

		success(state:observeMessage(delta("DespawnBatch", MATCH_A, 1, 3, { despawnEntry(1, 4) })))
		local resurrection: EnemyReplicationState.ApplyOutcome =
			success(state:observeMessage(delta("SpawnBatch", MATCH_A, 1, 4, { stateEntry(1, 5) })))
		assertions.equal(resurrection.kind, "RecoveryRequired")
		assertions.equal(snapshot(state).lastSequence, 3)
		assertions.equal(#snapshot(state).tombstones, 1)
		assertions.equal(snapshot(state).entries[1].runtimeEnemyId, 2)
	end),

	TestHarness.case(
		"clears the thirty-third unique buffered delta without rolling back converged state",
		function(assertions)
			local state = EnemyReplicationState.new()
			installSnapshot(state, MATCH_A, 1, 0, 1, {}, 1, false)
			for sequence = 2, 33 do
				success(
					state:observeMessage(delta("SpawnBatch", MATCH_A, 1, sequence, { stateEntry(sequence - 1, 1) }))
				)
			end
			assertions.equal(snapshot(state).bufferedCount, EnemyProtocol.MAX_BUFFERED_DELTA_MESSAGES)
			local overflow: EnemyReplicationState.ApplyOutcome =
				success(state:observeMessage(delta("SpawnBatch", MATCH_A, 1, 34, { stateEntry(33, 1) })))
			assertions.equal(overflow.kind, "RecoveryRequired")
			assertions.equal(overflow.bufferedCount, 0)
			assertions.isTrue(overflow.recoveryRequired)
			local preserved = snapshot(state)
			assertions.equal(preserved.lastSequence, 0)
			assertions.equal(#preserved.entries, 0)

			local recovered = installSnapshot(state, MATCH_A, 1, 34, 2, {}, 2, false)
			assertions.equal(recovered.kind, "SnapshotApplied")
			assertions.isFalse(recovered.recoveryRequired)
		end
	),

	TestHarness.case(
		"applies strict revisions and never resurrects a tombstoned runtime identity",
		function(assertions)
			local state = EnemyReplicationState.new()
			installSnapshot(state, MATCH_A, 1, 0, 1, {}, 1, true)
			success(state:observeMessage(delta("SpawnBatch", MATCH_A, 1, 1, { stateEntry(1, 1) })))
			local equalRevision: EnemyReplicationState.ApplyOutcome =
				success(state:observeMessage(delta("CorrectionBatch", MATCH_A, 1, 2, { stateEntry(1, 1) })))
			assertions.equal(equalRevision.appliedEntryCount, 0)
			success(state:observeMessage(delta("StateChangeBatch", MATCH_A, 1, 3, { stateEntry(1, 2) })))
			success(state:observeMessage(delta("DespawnBatch", MATCH_A, 1, 4, { despawnEntry(1, 3) })))
			success(state:observeMessage(delta("CorrectionBatch", MATCH_A, 1, 5, { stateEntry(1, 4) })))
			local terminal = snapshot(state)
			assertions.equal(terminal.lastSequence, 5)
			assertions.equal(#terminal.entries, 0)
			assertions.equal(#terminal.tombstones, 1)
			assertions.equal(terminal.tombstones[1].runtimeEnemyId, 1)

			local respawn: EnemyReplicationState.ApplyOutcome =
				success(state:observeMessage(delta("SpawnBatch", MATCH_A, 1, 6, { stateEntry(1, 5) })))
			assertions.equal(respawn.kind, "RecoveryRequired")
			assertions.equal(snapshot(state).lastSequence, 5)
			assertions.equal(#snapshot(state).entries, 0)

			local absent = EnemyReplicationState.new()
			installSnapshot(absent, MATCH_A, 1, 0, 1, {}, 1, true)
			success(absent:observeMessage(delta("DespawnBatch", MATCH_A, 1, 1, { despawnEntry(7, 2) })))
			success(absent:observeMessage(delta("CorrectionBatch", MATCH_A, 1, 2, { stateEntry(7, 3) })))
			assertions.equal(#snapshot(absent).entries, 0)
			assertions.equal(snapshot(absent).tombstones[1].runtimeEnemyId, 7)
		end
	),

	TestHarness.case(
		"preserves same-epoch tombstones and clears them only for an authorized new identity",
		function(assertions)
			local state = EnemyReplicationState.new()
			installSnapshot(state, MATCH_A, 1, 5, 1, { stateEntry(1, 1), stateEntry(2, 1) }, 1, false)
			success(state:observeMessage(delta("DespawnBatch", MATCH_A, 1, 6, { despawnEntry(1, 2) })))

			local resurrection =
				installSnapshot(state, MATCH_A, 1, 6, 2, { stateEntry(1, 3), stateEntry(2, 2) }, 2, false)
			assertions.equal(resurrection.kind, "RecoveryRequired")
			local preserved = snapshot(state)
			assertions.equal(preserved.lastSequence, 6)
			assertions.equal(#preserved.entries, 1)
			assertions.equal(preserved.entries[1].runtimeEnemyId, 2)
			assertions.equal(#preserved.tombstones, 1)

			local sameEpoch = installSnapshot(state, MATCH_A, 1, 7, 3, { stateEntry(2, 2) }, 3, false)
			assertions.equal(sameEpoch.kind, "SnapshotApplied")
			assertions.equal(#snapshot(state).tombstones, 1)
			assertions.equal(
				success(state:observeMessage(boundary("SnapshotBegin", MATCH_A, 1, 7, 3, 1, 1))).kind,
				"Duplicate"
			)
			assertions.equal(success(state:observeReceipt(receipt(MATCH_A, 1, 7, 2, 1, 1), 3.5)).kind, "Stale")
			assertions.isFalse(snapshot(state).assemblingSnapshot)
			local nextEpoch = installSnapshot(state, MATCH_A, 2, 0, 1, { stateEntry(1, 1) }, 4, false)
			assertions.equal(nextEpoch.kind, "SnapshotApplied")
			assertions.isTrue(nextEpoch.identityChanged)
			assertions.equal(#snapshot(state).tombstones, 0)
			assertions.equal(snapshot(state).entries[1].runtimeEnemyId, 1)
		end
	),

	TestHarness.case(
		"requires a despawn revision newer than state retained across a snapshot omission",
		function(assertions)
			local state = EnemyReplicationState.new()
			installSnapshot(state, MATCH_A, 1, 0, 1, { stateEntry(1, 5) }, 1, false)
			installSnapshot(state, MATCH_A, 1, 1, 2, {}, 2, false)
			assertions.equal(#snapshot(state).entries, 0)

			local stale: EnemyReplicationState.ApplyOutcome =
				success(state:observeMessage(delta("DespawnBatch", MATCH_A, 1, 2, { despawnEntry(1, 4) })))
			assertions.equal(stale.appliedEntryCount, 0)
			assertions.equal(#snapshot(state).tombstones, 0)

			local newer: EnemyReplicationState.ApplyOutcome =
				success(state:observeMessage(delta("DespawnBatch", MATCH_A, 1, 3, { despawnEntry(1, 6) })))
			assertions.equal(newer.appliedEntryCount, 1)
			assertions.equal(snapshot(state).tombstones[1].revision, 6)
		end
	),

	TestHarness.case(
		"rejects a lower epoch for the same match without clearing terminal identity history",
		function(assertions)
			local state = EnemyReplicationState.new()
			installSnapshot(state, MATCH_A, 2, 0, 1, { stateEntry(1, 1) }, 1, false)
			success(state:observeMessage(delta("DespawnBatch", MATCH_A, 2, 1, { despawnEntry(1, 2) })))

			local stale = installSnapshot(state, MATCH_A, 1, 0, 2, { stateEntry(1, 3) }, 2, false)
			assertions.equal(stale.kind, "Stale")
			local preserved = snapshot(state)
			assertions.equal(preserved.matchId, MATCH_A)
			assertions.equal(preserved.enemyEpoch, 2)
			assertions.equal(preserved.lastSequence, 1)
			assertions.equal(#preserved.entries, 0)
			assertions.equal(#preserved.tombstones, 1)
			assertions.equal(preserved.tombstones[1].runtimeEnemyId, 1)
			assertions.equal(preserved.tombstones[1].revision, 2)
			assertions.isFalse(preserved.assemblingSnapshot)
			assertions.isFalse(preserved.receiptPending)

			success(state:observeMessage(boundary("SnapshotBegin", MATCH_A, 3, 0, 1, 1, 1)))
			success(state:observeMessage(chunk(MATCH_A, 3, 0, 1, 1, { stateEntry(2, 1) })))
			success(state:observeMessage(boundary("SnapshotEnd", MATCH_A, 3, 0, 1, 1, 1)))
			local delayedCurrentEpoch: EnemyReplicationState.ApplyOutcome =
				success(state:observeReceipt(receipt(MATCH_A, 2, 1, 2, 1, 1), 3))
			assertions.equal(delayedCurrentEpoch.kind, "Stale")
			assertions.isTrue(snapshot(state).assemblingSnapshot)
			local promoted: EnemyReplicationState.ApplyOutcome =
				success(state:observeReceipt(receipt(MATCH_A, 3, 0, 1, 1, 1), 3.1))
			assertions.equal(promoted.kind, "SnapshotApplied")
			assertions.equal(snapshot(state).enemyEpoch, 3)
			assertions.equal(snapshot(state).entries[1].runtimeEnemyId, 2)
		end
	),

	TestHarness.case(
		"arbitrates delayed receipts without discarding the newer same-identity exchange",
		function(assertions)
			local eventFirst = EnemyReplicationState.new()
			installSnapshot(eventFirst, MATCH_A, 1, 0, 1, {}, 1, false)
			success(eventFirst:observeMessage(boundary("SnapshotBegin", MATCH_A, 1, 0, 3, 1, 1)))
			success(eventFirst:observeMessage(chunk(MATCH_A, 1, 0, 3, 1, { stateEntry(3, 1) })))
			success(eventFirst:observeMessage(boundary("SnapshotEnd", MATCH_A, 1, 0, 3, 1, 1)))

			local delayed: EnemyReplicationState.ApplyOutcome =
				success(eventFirst:observeReceipt(receipt(MATCH_A, 1, 0, 2, 1, 1), 2))
			assertions.equal(delayed.kind, "Stale")
			assertions.isTrue(snapshot(eventFirst).assemblingSnapshot)
			assertions.isFalse(snapshot(eventFirst).receiptPending)

			local applied: EnemyReplicationState.ApplyOutcome =
				success(eventFirst:observeReceipt(receipt(MATCH_A, 1, 0, 3, 1, 1), 2.1))
			assertions.equal(applied.kind, "SnapshotApplied")
			assertions.equal(snapshot(eventFirst).entries[1].runtimeEnemyId, 3)

			local receiptFirst = EnemyReplicationState.new()
			installSnapshot(receiptFirst, MATCH_A, 1, 0, 1, {}, 1, false)
			success(receiptFirst:observeMessage(boundary("SnapshotBegin", MATCH_A, 1, 0, 2, 1, 1)))
			success(receiptFirst:observeMessage(chunk(MATCH_A, 1, 0, 2, 1, { stateEntry(2, 1) })))
			success(receiptFirst:observeMessage(boundary("SnapshotEnd", MATCH_A, 1, 0, 2, 1, 1)))
			local newer: EnemyReplicationState.ApplyOutcome =
				success(receiptFirst:observeReceipt(receipt(MATCH_A, 1, 0, 3, 1, 1), 2))
			assertions.equal(newer.kind, "SnapshotProgress")
			assertions.isFalse(snapshot(receiptFirst).assemblingSnapshot)
			assertions.isTrue(snapshot(receiptFirst).receiptPending)
			success(receiptFirst:observeMessage(boundary("SnapshotBegin", MATCH_A, 1, 0, 3, 1, 1)))
			success(receiptFirst:observeMessage(chunk(MATCH_A, 1, 0, 3, 1, { stateEntry(3, 1) })))
			local replacement: EnemyReplicationState.ApplyOutcome =
				success(receiptFirst:observeMessage(boundary("SnapshotEnd", MATCH_A, 1, 0, 3, 1, 1)))
			assertions.equal(replacement.kind, "SnapshotApplied")
			assertions.equal(snapshot(receiptFirst).entries[1].runtimeEnemyId, 3)
		end
	),

	TestHarness.case("clears a matching event-first assembly when its base becomes stale", function(assertions)
		local state = EnemyReplicationState.new()
		installSnapshot(state, MATCH_A, 1, 5, 1, { stateEntry(1, 1) }, 1, false)
		success(state:observeMessage(boundary("SnapshotBegin", MATCH_A, 1, 5, 2, 1, 1)))
		success(state:observeMessage(chunk(MATCH_A, 1, 5, 2, 1, { stateEntry(1, 2) })))
		success(state:observeMessage(boundary("SnapshotEnd", MATCH_A, 1, 5, 2, 1, 1)))
		assertions.isTrue(snapshot(state).assemblingSnapshot)

		success(state:observeMessage(delta("CorrectionBatch", MATCH_A, 1, 6, { stateEntry(1, 3) })))
		local stale: EnemyReplicationState.ApplyOutcome =
			success(state:observeReceipt(receipt(MATCH_A, 1, 5, 2, 1, 1), 2))
		assertions.equal(stale.kind, "Stale")
		local current = snapshot(state)
		assertions.isFalse(current.assemblingSnapshot)
		assertions.isFalse(current.receiptPending)
		assertions.equal(current.lastSequence, 6)
		assertions.equal(current.entries[1].revision, 3)
	end),

	TestHarness.case(
		"assembles chunks out of order and expires one incomplete receipt at exactly two seconds",
		function(assertions)
			local state = EnemyReplicationState.new()
			local entries = {}
			for runtimeEnemyId = 1, 9 do
				table.insert(entries, stateEntry(runtimeEnemyId, 1))
			end
			local expectedReceipt = receipt(MATCH_A, 1, 0, 1, 2, 9)
			success(state:observeReceipt(expectedReceipt, 10))
			success(state:observeMessage(boundary("SnapshotBegin", MATCH_A, 1, 0, 1, 2, 9)))
			local secondChunk = chunk(MATCH_A, 1, 0, 1, 2, { entries[9] })
			assertions.equal(success(state:observeMessage(secondChunk)).kind, "SnapshotProgress")
			assertions.equal(success(state:observeMessage(secondChunk)).kind, "Duplicate")
			success(state:observeMessage(boundary("SnapshotEnd", MATCH_A, 1, 0, 1, 2, 9)))
			assertions.equal(success(state:advance(11.999)).kind, "Noop")
			local firstChunk = {}
			for index = 1, 8 do
				table.insert(firstChunk, entries[index])
			end
			local applied: EnemyReplicationState.ApplyOutcome =
				success(state:observeMessage(chunk(MATCH_A, 1, 0, 1, 1, firstChunk)))
			assertions.equal(applied.kind, "SnapshotApplied")
			assertions.equal(#snapshot(state).entries, 9)

			local incomplete = EnemyReplicationState.new()
			success(incomplete:observeReceipt(receipt(MATCH_B, 1, 0, 1, 1, 1), 20))
			success(incomplete:observeMessage(boundary("SnapshotBegin", MATCH_B, 1, 0, 1, 1, 1)))
			local expired: EnemyReplicationState.ApplyOutcome = success(incomplete:advance(22))
			assertions.equal(expired.kind, "RecoveryRequired")
			assertions.isTrue(expired.recoveryRequested)
			local expiredSnapshot = snapshot(incomplete)
			assertions.isFalse(expiredSnapshot.assemblingSnapshot)
			assertions.isFalse(expiredSnapshot.receiptPending)
			expectError(assertions, incomplete:advance(21), "INVALID_TIME")
		end
	),

	TestHarness.case(
		"ignores foreign deltas and requires a matching receipt before identity replacement",
		function(assertions)
			local state = EnemyReplicationState.new()
			installSnapshot(state, MATCH_A, 1, 0, 1, {}, 1, true)
			local foreign: EnemyReplicationState.ApplyOutcome =
				success(state:observeMessage(delta("SpawnBatch", MATCH_B, 1, 1, { stateEntry(1, 1) })))
			assertions.equal(foreign.kind, "Foreign")
			assertions.equal(snapshot(state).matchId, MATCH_A)

			success(state:observeMessage(boundary("SnapshotBegin", MATCH_B, 1, 0, 1, 1, 1)))
			success(state:observeMessage(chunk(MATCH_B, 1, 0, 1, 1, { stateEntry(1, 1) })))
			success(state:observeMessage(boundary("SnapshotEnd", MATCH_B, 1, 0, 1, 1, 1)))
			assertions.equal(snapshot(state).matchId, MATCH_A)
			local replaced: EnemyReplicationState.ApplyOutcome =
				success(state:observeReceipt(receipt(MATCH_B, 1, 0, 1, 1, 1), 2))
			assertions.equal(replaced.kind, "SnapshotApplied")
			assertions.isTrue(replaced.identityChanged)
			assertions.equal(snapshot(state).matchId, MATCH_B)
		end
	),

	TestHarness.case(
		"returns deterministic frozen snapshots and clears lifecycle state idempotently",
		function(assertions)
			local state = EnemyReplicationState.new()
			installSnapshot(state, MATCH_A, 1, 0, 1, {}, 1, true)
			success(state:observeMessage(delta("SpawnBatch", MATCH_A, 1, 1, { stateEntry(2, 1), stateEntry(1, 1) })))
			local current = snapshot(state)
			assertions.isTrue(table.isfrozen(current))
			assertions.isTrue(table.isfrozen(current.entries))
			assertions.equal(current.entries[1].runtimeEnemyId, 1)
			assertions.equal(current.entries[2].runtimeEnemyId, 2)
			assertions.isFalse(pcall(function()
				(current.entries :: any)[1] = nil
			end))

			assertions.isTrue(success(state:reset()))
			local reset = snapshot(state)
			assertions.isFalse(reset.locked)
			assertions.equal(#reset.entries, 0)
			installSnapshot(state, MATCH_B, 1, 0, 1, {}, 2, false)
			assertions.equal(snapshot(state).matchId, MATCH_B)
			assertions.isTrue(success(state:cleanup()))
			assertions.isTrue(success(state:cleanup()))
			expectError(assertions, state:getSnapshot(), "CLEANED_UP")
			expectError(assertions, state:reset(), "CLEANED_UP")
			expectError(
				assertions,
				state:observeMessage(delta("SpawnBatch", MATCH_B, 1, 1, {
					stateEntry(1, 1),
				})),
				"CLEANED_UP"
			)
		end
	),

	TestHarness.case(
		"validates protocol semantics at the boundary and enforces the active cap atomically",
		function(assertions)
			local state = EnemyReplicationState.new()
			local incompleteEntry = table.freeze({
				runtimeEnemyId = 1,
				revision = 1,
			})
			expectError(
				assertions,
				state:observeMessage(table.freeze({
					kind = "SpawnBatch",
					matchId = MATCH_A,
					enemyEpoch = 1,
					sequence = 1,
					entries = table.freeze({ incompleteEntry }),
				}) :: any),
				"INVALID_MESSAGE"
			)
			local stateEntryInDespawnBatch = table.freeze(stateEntry(1, 1))
			expectError(
				assertions,
				state:observeMessage(table.freeze({
					kind = "DespawnBatch",
					matchId = MATCH_A,
					enemyEpoch = 1,
					sequence = 1,
					entries = table.freeze({ stateEntryInDespawnBatch }),
				}) :: any),
				"INVALID_MESSAGE"
			)
			expectError(assertions, state:observeReceipt({} :: any, 0), "INVALID_RECEIPT")

			local retainedInstance = Instance.new("Folder")
			local hostileEntry = table.freeze({
				runtimeEnemyId = 1,
				revision = 1,
				private = retainedInstance,
			})
			local hostile = table.freeze({
				kind = "SpawnBatch",
				matchId = MATCH_A,
				enemyEpoch = 1,
				sequence = 1,
				entries = table.freeze({ hostileEntry }),
			})
			expectError(assertions, state:observeMessage(hostile :: any), "INVALID_MESSAGE")
			retainedInstance:Destroy()

			installSnapshot(state, MATCH_A, 1, 0, 1, {}, 1, true)
			for runtimeEnemyId = 1, EnemyProtocol.MAX_ACTIVE_ENEMIES do
				success(
					state:observeMessage(
						delta("SpawnBatch", MATCH_A, 1, runtimeEnemyId, { stateEntry(runtimeEnemyId, 1) })
					)
				)
			end
			local overCap: EnemyReplicationState.ApplyOutcome = success(
				state:observeMessage(
					delta(
						"SpawnBatch",
						MATCH_A,
						1,
						EnemyProtocol.MAX_ACTIVE_ENEMIES + 1,
						{ stateEntry(EnemyProtocol.MAX_ACTIVE_ENEMIES + 1, 1) }
					)
				)
			)
			assertions.equal(overCap.kind, "RecoveryRequired")
			local bounded = snapshot(state)
			assertions.equal(#bounded.entries, EnemyProtocol.MAX_ACTIVE_ENEMIES)
			assertions.equal(bounded.lastSequence, EnemyProtocol.MAX_ACTIVE_ENEMIES)
		end
	),
})
