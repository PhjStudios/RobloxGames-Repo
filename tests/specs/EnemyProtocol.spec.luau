--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Shared = game:GetService("ReplicatedStorage").Shared
local EnemyProtocol = require(Shared.match.EnemyProtocol)
local PayloadValidation = require(Shared.network.PayloadValidation)
local Validation = require(Shared.util.Validation)

type Assertions = TestHarness.Assertions

local function canonicalCFrame(position: Vector3, tangent: Vector3): CFrame
	local direction = tangent.Unit
	local upHint = Vector3.yAxis
	if math.abs(direction:Dot(upHint)) >= 1 - 1e-6 then
		upHint = Vector3.xAxis
	end
	local right = direction:Cross(upHint).Unit
	local up = right:Cross(direction).Unit
	return CFrame.fromMatrix(position, right, up, -direction)
end

local function maxCFrameComponentError(left: CFrame, right: CFrame): number
	local leftComponents = table.pack(left:GetComponents())
	local rightComponents = table.pack(right:GetComponents())
	local maximum = 0
	for index = 1, 12 do
		maximum = math.max(maximum, math.abs((leftComponents[index] :: number) - (rightComponents[index] :: number)))
	end
	return maximum
end

local function stateEntry(runtimeEnemyId: number): { [string]: unknown }
	local progress = runtimeEnemyId
	local startPosition = Vector3.new(0, 2, 0)
	local endPosition = Vector3.new(10, 2, 0)
	local position = startPosition:Lerp(endPosition, progress / 10)
	return {
		runtimeEnemyId = runtimeEnemyId,
		enemyId = "enemy:phase09-test",
		laneId = "lane:alpha",
		revision = runtimeEnemyId,
		lifecycle = "Active",
		pathProgress = progress,
		currentHealth = 100,
		maximumHealth = 100,
		slowMultiplier = 1,
		spawnServerTime = 100,
		sampleServerTime = 100 + progress,
		worldCFrame = canonicalCFrame(position, endPosition - startPosition),
		effectiveSpeed = 4,
		segmentIndex = 1,
		segmentStartDistance = 0,
		segmentEndDistance = 10,
		segmentStartPosition = startPosition,
		segmentEndPosition = endPosition,
	}
end

local function endpointEntry(runtimeEnemyId: number): { [string]: unknown }
	local entry = stateEntry(runtimeEnemyId)
	entry.revision = runtimeEnemyId + 1
	entry.lifecycle = "EndpointResolved"
	entry.pathProgress = 10
	entry.sampleServerTime = 120
	entry.worldCFrame = canonicalCFrame(Vector3.new(10, 2, 0), Vector3.new(10, 0, 0))
	return entry
end

local function stateBatch(kind: string, entries: { { [string]: unknown } }): { [string]: unknown }
	return {
		kind = kind,
		matchId = "match:phase09-test",
		enemyEpoch = 1,
		sequence = 7,
		entries = entries,
	}
end

local function snapshotChunk(entries: { { [string]: unknown } }): { [string]: unknown }
	return {
		kind = "SnapshotChunk",
		matchId = "match:phase09-test",
		enemyEpoch = 1,
		baseSequence = 6,
		snapshotId = 2,
		chunkIndex = 1,
		entries = entries,
	}
end

local function snapshotBoundary(kind: string, chunkCount: number, totalEntries: number): { [string]: unknown }
	return {
		kind = kind,
		matchId = "match:phase09-test",
		enemyEpoch = 1,
		baseSequence = 6,
		snapshotId = 2,
		chunkCount = chunkCount,
		totalEntries = totalEntries,
	}
end

local function receipt(chunkCount: number, totalEntries: number): { [string]: unknown }
	return {
		matchId = "match:phase09-test",
		enemyEpoch = 1,
		baseSequence = 6,
		snapshotId = 2,
		chunkCount = chunkCount,
		totalEntries = totalEntries,
	}
end

local function despawnEntry(runtimeEnemyId: number): { [string]: unknown }
	return {
		runtimeEnemyId = runtimeEnemyId,
		revision = runtimeEnemyId + 2,
		sampleServerTime = 125,
		reason = "Endpoint",
	}
end

local function expectMessageSuccess(assertions: Assertions, value: unknown): EnemyProtocol.EnemyReplicationMessage
	local result = EnemyProtocol.validateEnemyReplication(value)
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return (result :: any).value :: EnemyProtocol.EnemyReplicationMessage
end

local function expectMessageFailure(
	assertions: Assertions,
	value: unknown,
	code: Validation.Code?,
	path: string?
): Validation.Issue
	local result = EnemyProtocol.validateEnemyReplication(value)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local problem = (result :: any).error :: Validation.Issue
	assertions.isTrue(table.isfrozen(problem))
	assertions.isTrue(table.isfrozen(problem.pathSegments))
	if code ~= nil then
		assertions.equal(problem.code, code)
	end
	if path ~= nil then
		assertions.equal(problem.path, path)
	end
	return problem
end

local function expectReceiptSuccess(assertions: Assertions, value: unknown): EnemyProtocol.EnemySnapshotReceipt
	local result = EnemyProtocol.validateEnemySnapshotReceipt(value)
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return (result :: any).value :: EnemyProtocol.EnemySnapshotReceipt
end

local function expectReceiptFailure(assertions: Assertions, value: unknown, code: Validation.Code?): Validation.Issue
	local result = EnemyProtocol.validateEnemySnapshotReceipt(value)
	assertions.isFalse(result.ok)
	local problem = (result :: any).error :: Validation.Issue
	assertions.isTrue(table.isfrozen(problem))
	if code ~= nil then
		assertions.equal(problem.code, code)
	end
	return problem
end

local function graphContains(root: unknown, target: unknown, seen: { [any]: boolean }?): boolean
	if root == target then
		return true
	end
	if type(root) ~= "table" then
		return false
	end
	local visited = seen or {}
	if visited[root] then
		return false
	end
	visited[root] = true
	for key, value in next, root :: any do
		if graphContains(key, target, visited) or graphContains(value, target, visited) then
			return true
		end
	end
	return false
end

return TestHarness.suite("enemy replication wire contract", {
	TestHarness.case("exports exact endpoints kinds schemas and bounded protocol constants", function(assertions)
		assertions.equal(EnemyProtocol.GET_ENEMY_SNAPSHOT_ENDPOINT, "GetEnemySnapshot")
		assertions.equal(EnemyProtocol.ENEMY_REPLICATION_ENDPOINT, "EnemyReplication")
		assertions.equal(EnemyProtocol.SPAWN_BATCH_KIND, "SpawnBatch")
		assertions.equal(EnemyProtocol.CORRECTION_BATCH_KIND, "CorrectionBatch")
		assertions.equal(EnemyProtocol.STATE_CHANGE_BATCH_KIND, "StateChangeBatch")
		assertions.equal(EnemyProtocol.DESPAWN_BATCH_KIND, "DespawnBatch")
		assertions.equal(EnemyProtocol.SNAPSHOT_BEGIN_KIND, "SnapshotBegin")
		assertions.equal(EnemyProtocol.SNAPSHOT_CHUNK_KIND, "SnapshotChunk")
		assertions.equal(EnemyProtocol.SNAPSHOT_END_KIND, "SnapshotEnd")
		assertions.equal(
			table.concat(EnemyProtocol.REPLICATION_KINDS, ","),
			"SpawnBatch,CorrectionBatch,StateChangeBatch,DespawnBatch,SnapshotBegin,SnapshotChunk,SnapshotEnd"
		)
		assertions.equal(EnemyProtocol.MAX_ACTIVE_ENEMIES, 128)
		assertions.equal(EnemyProtocol.MAX_LIFETIME_ENEMIES, 4_096)
		assertions.equal(EnemyProtocol.MAX_ENEMY_EPOCH, 4_096)
		assertions.equal(EnemyProtocol.MAX_RUNTIME_ENEMY_ID, 4_096)
		assertions.equal(EnemyProtocol.MAX_ENTRIES_PER_MESSAGE, 8)
		assertions.equal(EnemyProtocol.MAX_SNAPSHOT_CHUNKS, 16)
		assertions.equal(EnemyProtocol.MAX_SNAPSHOT_ENTRIES, 128)
		assertions.equal(EnemyProtocol.MAX_SNAPSHOT_ID, 16)
		assertions.equal(EnemyProtocol.MAX_CURRENT_SNAPSHOT_ASSEMBLIES, 1)
		assertions.equal(EnemyProtocol.MAX_BUFFERED_DELTA_MESSAGES, 32)
		assertions.equal(EnemyProtocol.MAX_PENDING_CAUSAL_ENTRIES_PER_ENEMY, 3)
		assertions.equal(EnemyProtocol.MAX_PENDING_CAUSAL_ENTRIES, 384)
		assertions.equal(EnemyProtocol.MAX_DELTA_MESSAGES_PER_FLUSH, 12)
		assertions.equal(EnemyProtocol.MAX_BROADCAST_RECIPIENTS, 4)
		assertions.equal(EnemyProtocol.MAX_LIFETIME_DELTA_MESSAGES, 131_072)
		assertions.equal(EnemyProtocol.MAX_LIFETIME_SNAPSHOT_MESSAGES, 160)
		assertions.equal(EnemyProtocol.MAX_SNAPSHOT_REQUESTS_PER_PLAYER, 2)
		assertions.equal(EnemyProtocol.MAX_CLIENT_SNAPSHOT_ATTEMPTS, 2)
		assertions.equal(EnemyProtocol.PUBLICATION_INTERVAL_SECONDS, 0.1)
		assertions.equal(EnemyProtocol.SNAPSHOT_RECEIPT_TIMEOUT_SECONDS, 2)
		assertions.equal(EnemyProtocol.MAX_LANE_ID_BYTES, 64)
		assertions.equal(EnemyProtocol.MAX_PATH_DISTANCE, 32_768)
		assertions.equal(EnemyProtocol.MAX_SEGMENT_INDEX, 257)
		assertions.equal(EnemyProtocol.MAX_COORDINATE, 100_000)
		assertions.equal(EnemyProtocol.POSITION_TOLERANCE, 1e-6)
		assertions.equal(EnemyProtocol.WIRE_CFRAME_COMPONENT_TOLERANCE, 1e-4)
		assertions.equal(EnemyProtocol.MAX_ENEMY_REVISION, Validation.MAX_SAFE_INTEGER)
		assertions.equal(EnemyProtocol.MAX_REPLICATION_SEQUENCE, Validation.MAX_SAFE_INTEGER)
		assertions.equal(EnemyProtocol.MAX_SNAPSHOT_BASE_SEQUENCE, Validation.MAX_SAFE_INTEGER)
		assertions.isTrue(table.isfrozen(EnemyProtocol))
		assertions.isTrue(table.isfrozen(EnemyProtocol.REPLICATION_KINDS))
		assertions.isTrue(PayloadValidation.isSchema(EnemyProtocol.GetEnemySnapshotPayloadSchema))
		assertions.isTrue(PayloadValidation.isSchema(EnemyProtocol.EnemyStateEntrySchema))
		assertions.isTrue(PayloadValidation.isSchema(EnemyProtocol.DespawnEntrySchema))
		assertions.isTrue(PayloadValidation.isSchema(EnemyProtocol.EnemySnapshotReceiptSchema))
		assertions.isTrue(PayloadValidation.isSchema(EnemyProtocol.EnemyReplicationSchema))
	end),

	TestHarness.case("accepts only the exact detached empty recovery request", function(assertions)
		local authored = {}
		local result = EnemyProtocol.GetEnemySnapshotPayloadSchema:validate(authored)
		assertions.isTrue(result.ok)
		assertions.notEqual((result :: any).value, authored)
		assertions.isTrue(table.isfrozen((result :: any).value))
		assertions.isFalse(EnemyProtocol.GetEnemySnapshotPayloadSchema:validate({ extra = true }).ok)
		assertions.isFalse(EnemyProtocol.GetEnemySnapshotPayloadSchema:validate(setmetatable({}, {})).ok)
		assertions.isFalse(EnemyProtocol.GetEnemySnapshotPayloadSchema:validate(Instance.new("Folder")).ok)
	end),

	TestHarness.case(
		"validates all seven tagged messages through four bounded structural branches",
		function(assertions)
			for _, kind in { "SpawnBatch", "CorrectionBatch" } do
				local message = expectMessageSuccess(assertions, stateBatch(kind, { stateEntry(1) }))
				assertions.equal(message.kind, kind)
			end
			expectMessageSuccess(assertions, stateBatch("StateChangeBatch", { endpointEntry(1) }))
			expectMessageSuccess(assertions, {
				kind = "DespawnBatch",
				matchId = "match:phase09-test",
				enemyEpoch = 1,
				sequence = 8,
				entries = { despawnEntry(1) },
			})
			expectMessageSuccess(assertions, snapshotBoundary("SnapshotBegin", 1, 8))
			expectMessageSuccess(assertions, snapshotChunk({ stateEntry(1), stateEntry(2) }))
			expectMessageSuccess(assertions, snapshotBoundary("SnapshotEnd", 1, 8))

			local maximumEntries = {}
			for runtimeEnemyId = 1, EnemyProtocol.MAX_ENTRIES_PER_MESSAGE do
				table.insert(maximumEntries, stateEntry(runtimeEnemyId))
			end
			local maximum = expectMessageSuccess(assertions, stateBatch("CorrectionBatch", maximumEntries))
			assertions.equal(#(maximum :: EnemyProtocol.StateBatchMessage).entries, 8)
		end
	),

	TestHarness.case("detaches and deeply freezes messages entries arrays and receipts", function(assertions)
		local authoredEntry = stateEntry(1)
		local authoredEntries = { authoredEntry }
		local authoredMessage = stateBatch("CorrectionBatch", authoredEntries)
		local canonical = expectMessageSuccess(assertions, authoredMessage) :: EnemyProtocol.StateBatchMessage
		assertions.notEqual(canonical, authoredMessage)
		assertions.notEqual(canonical.entries, authoredEntries)
		assertions.notEqual(canonical.entries[1], authoredEntry)
		assertions.isTrue(table.isfrozen(canonical))
		assertions.isTrue(table.isfrozen(canonical.entries))
		assertions.isTrue(table.isfrozen(canonical.entries[1]))
		authoredMessage.sequence = 99
		authoredEntry.pathProgress = 9
		assertions.equal(canonical.sequence, 7)
		assertions.equal(canonical.entries[1].pathProgress, 1)

		local authoredReceipt = receipt(1, 8)
		local canonicalReceipt = expectReceiptSuccess(assertions, authoredReceipt)
		assertions.notEqual(canonicalReceipt, authoredReceipt)
		assertions.isTrue(table.isfrozen(canonicalReceipt))
	end),

	TestHarness.case("enforces health time slow and segment cross-field invariants", function(assertions)
		local invalidMaximum = stateEntry(1)
		invalidMaximum.maximumHealth = 0
		expectMessageFailure(
			assertions,
			stateBatch("CorrectionBatch", { invalidMaximum }),
			"INVALID_TOTAL",
			"payload.entries[1].currentHealth"
		)

		local excessiveHealth = stateEntry(1)
		excessiveHealth.currentHealth = 101
		expectMessageFailure(assertions, stateBatch("CorrectionBatch", { excessiveHealth }), "INVALID_TOTAL", nil)

		local backwardsTime = stateEntry(1)
		backwardsTime.sampleServerTime = 99
		expectMessageFailure(
			assertions,
			stateBatch("CorrectionBatch", { backwardsTime }),
			"INVALID_ORDER",
			"payload.entries[1].sampleServerTime"
		)

		local stopped = stateEntry(1)
		stopped.slowMultiplier = 0
		expectMessageFailure(
			assertions,
			stateBatch("StateChangeBatch", { stopped }),
			"INVALID_TOTAL",
			"payload.entries[1].effectiveSpeed"
		)
		stopped.effectiveSpeed = 0
		expectMessageSuccess(assertions, stateBatch("StateChangeBatch", { stopped }))

		local reversed = stateEntry(1)
		reversed.segmentEndDistance = 0
		expectMessageFailure(
			assertions,
			stateBatch("CorrectionBatch", { reversed }),
			"INVALID_ORDER",
			"payload.entries[1].segmentEndDistance"
		)

		local outside = stateEntry(1)
		outside.pathProgress = 11
		expectMessageFailure(
			assertions,
			stateBatch("CorrectionBatch", { outside }),
			"INVALID_REFERENCE",
			"payload.entries[1].pathProgress"
		)

		local wrongDistance = stateEntry(1)
		wrongDistance.segmentEndDistance = 9
		expectMessageFailure(
			assertions,
			stateBatch("CorrectionBatch", { wrongDistance }),
			"INVALID_TOTAL",
			"payload.entries[1].segmentEndDistance"
		)
	end),

	TestHarness.case("requires bounded canonical CFrames and the outgoing exact-corner tangent", function(assertions)
		local corner = stateEntry(1)
		corner.pathProgress = 10
		corner.segmentIndex = 2
		corner.segmentStartDistance = 10
		corner.segmentEndDistance = 20
		corner.segmentStartPosition = Vector3.new(10, 2, 0)
		corner.segmentEndPosition = Vector3.new(10, 2, 10)
		corner.worldCFrame = canonicalCFrame(Vector3.new(10, 2, 0), Vector3.new(0, 0, 10))
		expectMessageSuccess(assertions, stateBatch("CorrectionBatch", { corner }))

		corner.worldCFrame = canonicalCFrame(Vector3.new(10, 2, 0), Vector3.new(10, 0, 0))
		expectMessageFailure(
			assertions,
			stateBatch("CorrectionBatch", { corner }),
			"INVALID_REFERENCE",
			"payload.entries[1].worldCFrame"
		)

		local vertical = stateEntry(1)
		vertical.pathProgress = 5
		vertical.segmentEndDistance = 10
		vertical.segmentStartPosition = Vector3.new(0, 0, 0)
		vertical.segmentEndPosition = Vector3.new(0, 10, 0)
		vertical.worldCFrame = canonicalCFrame(Vector3.new(0, 5, 0), Vector3.new(0, 10, 0))
		expectMessageSuccess(assertions, stateBatch("CorrectionBatch", { vertical }))

		local unbounded = stateEntry(1)
		unbounded.segmentStartPosition = Vector3.new(100_001, 0, 0)
		unbounded.segmentEndPosition = Vector3.new(100_011, 0, 0)
		unbounded.worldCFrame = canonicalCFrame(Vector3.new(100_002, 0, 0), Vector3.new(10, 0, 0))
		expectMessageFailure(
			assertions,
			stateBatch("CorrectionBatch", { unbounded }),
			"OUT_OF_RANGE",
			"payload.entries[1].segmentStartPosition"
		)
	end),

	TestHarness.case("accepts wire-sized diagonal CFrame drift and returns only canonical state", function(assertions)
		local segmentStart = Vector3.new(-20, 2, -25)
		local segmentEnd = Vector3.new(-5, 2, 0)
		local tangent = segmentEnd - segmentStart
		local segmentStartDistance = 30
		local segmentEndDistance = segmentStartDistance + tangent.Magnitude
		local progress = segmentStartDistance + tangent.Magnitude * 0.4
		local position = segmentStart:Lerp(segmentEnd, 0.4)
		local canonical = canonicalCFrame(position, tangent)
		local liveMeasuredRotationError = 0.00003069639205932617
		local transported = canonical * CFrame.Angles(0, liveMeasuredRotationError, 0)
		local transportedError = maxCFrameComponentError(transported, canonical)
		assertions.isTrue(transportedError > EnemyProtocol.POSITION_TOLERANCE)
		assertions.isTrue(transportedError < EnemyProtocol.WIRE_CFRAME_COMPONENT_TOLERANCE)

		local diagonal = stateEntry(1)
		diagonal.pathProgress = progress
		diagonal.sampleServerTime = 104
		diagonal.worldCFrame = transported
		diagonal.segmentIndex = 2
		diagonal.segmentStartDistance = segmentStartDistance
		diagonal.segmentEndDistance = segmentEndDistance
		diagonal.segmentStartPosition = segmentStart
		diagonal.segmentEndPosition = segmentEnd

		local direct = EnemyProtocol.validateEnemyStateEntry(diagonal)
		assertions.isTrue(direct.ok)
		if direct.ok then
			assertions.isTrue(table.isfrozen(direct.value))
			assertions.equal(maxCFrameComponentError(direct.value.worldCFrame, canonical), 0)
			assertions.notEqual(direct.value.worldCFrame, transported)
		end

		local correction = expectMessageSuccess(assertions, stateBatch("CorrectionBatch", { diagonal }))
		local correctionEntry = (correction :: EnemyProtocol.StateBatchMessage).entries[1]
		assertions.equal(maxCFrameComponentError(correctionEntry.worldCFrame, canonical), 0)
		local snapshot = expectMessageSuccess(assertions, snapshotChunk({ diagonal }))
		local snapshotEntry = (snapshot :: EnemyProtocol.SnapshotChunkMessage).entries[1]
		assertions.equal(maxCFrameComponentError(snapshotEntry.worldCFrame, canonical), 0)

		local beyondWireBound = table.clone(diagonal)
		beyondWireBound.worldCFrame = canonical * CFrame.Angles(0, EnemyProtocol.WIRE_CFRAME_COMPONENT_TOLERANCE * 4, 0)
		expectMessageFailure(
			assertions,
			stateBatch("CorrectionBatch", { beyondWireBound }),
			"INVALID_REFERENCE",
			"payload.entries[1].worldCFrame"
		)

		local beyondPositionBound = table.clone(diagonal)
		beyondPositionBound.worldCFrame = transported + Vector3.new(EnemyProtocol.POSITION_TOLERANCE * 2, 0, 0)
		expectMessageFailure(
			assertions,
			stateBatch("CorrectionBatch", { beyondPositionBound }),
			"INVALID_REFERENCE",
			"payload.entries[1].worldCFrame"
		)

		local wrongTangent = table.clone(diagonal)
		wrongTangent.worldCFrame = canonicalCFrame(position, Vector3.xAxis)
		expectMessageFailure(
			assertions,
			stateBatch("CorrectionBatch", { wrongTangent }),
			"INVALID_REFERENCE",
			"payload.entries[1].worldCFrame"
		)
	end),

	TestHarness.case("permits endpoint state only at its advertised segment end", function(assertions)
		local endpoint = endpointEntry(1)
		expectMessageSuccess(assertions, stateBatch("StateChangeBatch", { endpoint }))
		expectMessageFailure(
			assertions,
			stateBatch("CorrectionBatch", { endpoint }),
			"INVALID_REFERENCE",
			"payload.entries[1].lifecycle"
		)
		expectMessageFailure(
			assertions,
			snapshotChunk({ endpoint }),
			"INVALID_REFERENCE",
			"payload.entries[1].lifecycle"
		)

		endpoint.pathProgress = 9
		endpoint.worldCFrame = canonicalCFrame(Vector3.new(9, 2, 0), Vector3.new(10, 0, 0))
		expectMessageFailure(
			assertions,
			stateBatch("StateChangeBatch", { endpoint }),
			"INVALID_REFERENCE",
			"payload.entries[1].lifecycle"
		)
	end),

	TestHarness.case(
		"preserves causal delta order while bounding duplicates and sorting snapshots",
		function(assertions)
			expectMessageSuccess(assertions, stateBatch("CorrectionBatch", { stateEntry(2), stateEntry(1) }))
			expectMessageFailure(
				assertions,
				stateBatch("CorrectionBatch", { stateEntry(1), stateEntry(1) }),
				"DUPLICATE_VALUE",
				"payload.entries[2].runtimeEnemyId"
			)
			expectMessageFailure(
				assertions,
				snapshotChunk({ stateEntry(2), stateEntry(1) }),
				"INVALID_ORDER",
				"payload.entries[2].runtimeEnemyId"
			)
			expectMessageFailure(assertions, snapshotChunk({ stateEntry(1), stateEntry(1) }), "DUPLICATE_VALUE", nil)

			expectMessageFailure(assertions, {
				kind = "DespawnBatch",
				matchId = "match:phase09-test",
				enemyEpoch = 1,
				sequence = 8,
				entries = { despawnEntry(1), despawnEntry(1) },
			}, "DUPLICATE_VALUE", "payload.entries[2].runtimeEnemyId")
		end
	),

	TestHarness.case("requires exact snapshot chunk totals in boundaries and receipts", function(assertions)
		for _, counts in { { 0, 0 }, { 1, 1 }, { 1, 8 }, { 2, 9 }, { 16, 128 } } do
			expectMessageSuccess(assertions, snapshotBoundary("SnapshotBegin", counts[1], counts[2]))
			expectMessageSuccess(assertions, snapshotBoundary("SnapshotEnd", counts[1], counts[2]))
			expectReceiptSuccess(assertions, receipt(counts[1], counts[2]))
		end
		expectMessageFailure(assertions, snapshotBoundary("SnapshotBegin", 0, 1), "INVALID_TOTAL", "payload.chunkCount")
		expectMessageFailure(assertions, snapshotBoundary("SnapshotEnd", 15, 128), "INVALID_TOTAL", nil)
		expectReceiptFailure(assertions, receipt(1, 9), "INVALID_TOTAL")
	end),

	TestHarness.case("rejects oversized malformed nonfinite hostile and extra-field payloads", function(assertions)
		local excessiveEntries = {}
		for runtimeEnemyId = 1, EnemyProtocol.MAX_ENTRIES_PER_MESSAGE + 1 do
			table.insert(excessiveEntries, stateEntry(runtimeEnemyId))
		end
		expectMessageFailure(assertions, stateBatch("CorrectionBatch", excessiveEntries), nil, nil)

		for _, invalid in { 0, 4_097, 1.5, math.huge, -math.huge, 0 / 0 } do
			local entry = stateEntry(1)
			entry.runtimeEnemyId = invalid
			expectMessageFailure(assertions, stateBatch("CorrectionBatch", { entry }), nil, nil)
		end
		for _, invalid in { -1, math.huge, -math.huge, 0 / 0 } do
			local entry = stateEntry(1)
			entry.sampleServerTime = invalid
			expectMessageFailure(assertions, stateBatch("CorrectionBatch", { entry }), nil, nil)
		end

		local extra = stateBatch("CorrectionBatch", { stateEntry(1) })
		extra.private = "not-on-wire"
		expectMessageFailure(assertions, extra, nil, nil)
		expectMessageFailure(assertions, setmetatable(stateBatch("CorrectionBatch", {}), {}), nil, nil)
		local metatableEntry = stateEntry(1)
		setmetatable(metatableEntry, {})
		expectMessageFailure(assertions, stateBatch("CorrectionBatch", { metatableEntry }), nil, nil)
		local metatableEntries = { stateEntry(1) }
		setmetatable(metatableEntries, {})
		expectMessageFailure(assertions, stateBatch("CorrectionBatch", metatableEntries), nil, nil)
		expectMessageFailure(assertions, Instance.new("Folder"), nil, nil)
		expectMessageFailure(assertions, stateBatch("Unknown", {}), nil, nil)

		local cyclic = stateBatch("CorrectionBatch", {})
		cyclic.entries = { cyclic :: any }
		expectMessageFailure(assertions, cyclic, nil, nil)
	end),

	TestHarness.case("exports focused entry validators for trusted publisher conversion", function(assertions)
		local authoredState = stateEntry(1)
		local stateResult = EnemyProtocol.validateEnemyStateEntry(authoredState)
		assertions.isTrue(stateResult.ok)
		assertions.notEqual((stateResult :: any).value, authoredState)
		assertions.isTrue(table.isfrozen((stateResult :: any).value))

		local badState = stateEntry(1)
		badState.currentHealth = 101
		assertions.isFalse(EnemyProtocol.validateEnemyStateEntry(badState).ok)

		local authoredDespawn = despawnEntry(1)
		local despawnResult = EnemyProtocol.validateDespawnEntry(authoredDespawn)
		assertions.isTrue(despawnResult.ok)
		assertions.notEqual((despawnResult :: any).value, authoredDespawn)
		assertions.isTrue(table.isfrozen((despawnResult :: any).value))
		assertions.isFalse(EnemyProtocol.validateDespawnEntry({ runtimeEnemyId = 1 }).ok)
	end),

	TestHarness.case("returns static privacy-safe failures without retaining rejected graphs", function(assertions)
		local privateValue = { secret = "PRIVATE_ENEMY_PROTOCOL_SENTINEL" }
		local invalid = stateBatch("CorrectionBatch", { stateEntry(1) })
		invalid.private = privateValue
		local problem = expectMessageFailure(assertions, invalid, nil, nil)
		assertions.isFalse(graphContains(problem, privateValue))
		for _, fieldName in { "code", "path", "message" } do
			assertions.isNil(string.find((problem :: any)[fieldName], privateValue.secret, 1, true))
		end
	end),
})
