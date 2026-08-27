--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local EnemyFixtures = require(script.Parent.Parent.Fixtures.EnemyFixtures)
local EnemyRuntimeStore = require(script.Parent.Parent.ProductionServerEnemies.EnemyRuntimeStore)
local EnemyReplicationPublisher = require(script.Parent.Parent.ProductionServerEnemies.EnemyReplicationPublisher)
local EnemyReplicationState = require(script.Parent.Parent.ProductionClientEnemies.EnemyReplicationState)
local EnemyPresentation = require(script.Parent.Parent.ProductionClientEnemies.EnemyPresentation)

local Shared = game:GetService("ReplicatedStorage").Shared
local EnemyProtocol = require(Shared.match.EnemyProtocol)
local Result = require(Shared.util.Result)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase09-integration"
local ENEMY_EPOCH = 1
local PUBLICATION_INTERVAL_SECONDS = EnemyProtocol.PUBLICATION_INTERVAL_SECONDS

local newPublisherForTests = EnemyReplicationPublisher.newForTests
if newPublisherForTests == nil then
	error("EnemyReplicationPublisher test constructor unavailable at exact Test location", 0)
end

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected Phase 09 integration operation to succeed", 0)
	end
	return result.value
end

local function assertClose(assertions: Assertions, actual: number, expected: number, tolerance: number)
	assertions.isTrue(math.abs(actual - expected) <= tolerance)
end

local function assertVectorClose(assertions: Assertions, actual: Vector3, expected: Vector3, tolerance: number)
	assertions.isTrue((actual - expected).Magnitude <= tolerance)
end

local function copySendsSince(rig: any, firstIndex: number): { any }
	local records = table.create(#rig.sends - firstIndex)
	for index = firstIndex + 1, #rig.sends do
		table.insert(records, rig.sends[index])
	end
	return records
end

local function recordsForRecipient(records: { any }, recipient: unknown): { any }
	local selected = {}
	for _, record in records do
		if record.recipient == recipient then
			table.insert(selected, record)
		end
	end
	return selected
end

local function stateSnapshot(assertions: Assertions, state: any): any
	return success(assertions, state:getSnapshot())
end

local function findEntry(snapshot: any, runtimeEnemyId: number): any
	for _, entry in snapshot.entries do
		if entry.runtimeEnemyId == runtimeEnemyId then
			return entry
		end
	end
	error("expected converged enemy entry", 0)
end

local function newRig(assertions: Assertions, recipientCount: number): any
	local rig: any = {
		clock = { now = 100 },
		endpointCallbacks = {},
		recipients = {},
		recipientRecords = {},
		states = {},
		sends = {},
	}

	local storeResult = EnemyRuntimeStore.newForTests(
		MATCH_ID,
		ENEMY_EPOCH,
		EnemyFixtures.createAuthenticatedCatalog(),
		EnemyFixtures.createRuntimeMapSnapshot(),
		{
			clock = function(): number
				return rig.clock.now
			end,
			endpointSink = function(snapshot: any)
				table.insert(rig.endpointCallbacks, snapshot)
			end,
		}
	)
	rig.store = success(assertions, storeResult)

	for index = 1, recipientCount do
		local recipient = table.freeze({ id = index })
		table.insert(rig.recipients, recipient)
		table.insert(rig.recipientRecords, {
			recipient = recipient,
			userId = 1_000 + index,
		})
		rig.states[recipient] = EnemyReplicationState.new()
	end

	rig.sender = function(recipient: unknown, message: EnemyProtocol.EnemyReplicationMessage): boolean
		table.insert(rig.sends, {
			recipient = recipient,
			message = message,
		})
		return true
	end
	rig.getRecipients = function(): unknown
		return rig.recipientRecords
	end
	rig.provider = function(runtimeEnemyIds: { number }?): unknown
		if runtimeEnemyIds == nil then
			return rig.store:list()
		end
		local snapshots = table.create(#runtimeEnemyIds)
		for _, runtimeEnemyId in runtimeEnemyIds do
			local snapshotResult = rig.store:get(runtimeEnemyId)
			if not snapshotResult.ok then
				return snapshotResult
			end
			table.insert(snapshots, snapshotResult.value)
		end
		return Result.ok(table.freeze(snapshots))
	end

	local publisherResult = (newPublisherForTests :: EnemyReplicationPublisher.TestConstructor)(MATCH_ID, ENEMY_EPOCH, {
		sender = rig.sender,
		getRecipients = rig.getRecipients,
	}, nil)
	rig.publisher = success(assertions, publisherResult)
	return rig
end

local function deliverRecords(assertions: Assertions, rig: any, records: { any }): { any }
	local outcomes = table.create(#records)
	for _, record in records do
		local state = rig.states[record.recipient]
		assertions.isNotNil(state)
		local outcome = success(assertions, state:observeMessage(record.message))
		table.insert(outcomes, outcome)
	end
	return outcomes
end

local function requestAndInstallSnapshot(
	assertions: Assertions,
	rig: any,
	recipient: unknown,
	now: number
): (any, { any })
	local firstIndex = #rig.sends
	local receipt = success(assertions, rig.publisher:requestSnapshot(recipient, rig.provider))
	local records = recordsForRecipient(copySendsSince(rig, firstIndex), recipient)
	assertions.isTrue(#records >= 2)
	deliverRecords(assertions, rig, records)
	local outcome = success(assertions, rig.states[recipient]:observeReceipt(receipt, now))
	return outcome, records
end

local function spawnEnemy(assertions: Assertions, rig: any, enemyId: string, laneId: string): any
	success(assertions, rig.publisher:preflightSpawn())
	local snapshot = success(assertions, rig.store:spawn(enemyId, laneId))
	success(assertions, rig.publisher:commitSpawn(snapshot))
	return snapshot
end

local function setSlow(assertions: Assertions, rig: any, runtimeEnemyId: number, multiplier: number): any
	success(assertions, rig.publisher:preflightStateChange(runtimeEnemyId))
	local snapshot = success(assertions, rig.store:setSlowMultiplier(runtimeEnemyId, multiplier))
	success(assertions, rig.publisher:commitStateChange(snapshot))
	return snapshot
end

local function stepSimulation(assertions: Assertions, rig: any, deltaSeconds: number): any
	local active = success(assertions, rig.store:list())
	local runtimeEnemyIds = table.create(#active)
	for _, snapshot in active do
		table.insert(runtimeEnemyIds, snapshot.runtimeEnemyId)
	end
	table.freeze(runtimeEnemyIds)
	success(assertions, rig.publisher:preflightStep(runtimeEnemyIds))

	rig.clock.now += deltaSeconds
	local step = success(assertions, rig.store:step(deltaSeconds))
	local updatedById: { [number]: boolean } = {}
	local endpointById: { [number]: any } = {}
	for _, runtimeEnemyId in step.updatedRuntimeEnemyIds do
		updatedById[runtimeEnemyId] = true
	end
	for _, resolution in step.endpointResolutions do
		endpointById[resolution.endpoint.runtimeEnemyId] = resolution
	end

	-- Mirror the service's deterministic RuntimeEnemyId merge rather than
	-- publishing every correction first or every terminal outcome first.
	for _, runtimeEnemyId in runtimeEnemyIds do
		local resolution = endpointById[runtimeEnemyId]
		if resolution ~= nil then
			success(assertions, rig.publisher:commitEndpoint(resolution.endpoint, resolution.despawn))
		elseif updatedById[runtimeEnemyId] then
			success(assertions, rig.publisher:observeCorrection(runtimeEnemyId))
		end
	end
	return step
end

local function manualDespawn(assertions: Assertions, rig: any, runtimeEnemyId: number): any
	success(assertions, rig.publisher:preflightManualDespawn(runtimeEnemyId))
	local snapshot = success(assertions, rig.store:despawn(runtimeEnemyId))
	success(assertions, rig.publisher:commitManualDespawn(snapshot))
	return snapshot
end

local function flushPending(assertions: Assertions, rig: any): { any }
	local firstIndex = #rig.sends
	for _ = 1, 4 do
		local metrics = rig.publisher:getMetrics()
		if metrics.pendingEntryCount == 0 and metrics.dirtyCorrectionCount == 0 then
			break
		end
		local outcome = success(assertions, rig.publisher:advance(PUBLICATION_INTERVAL_SECONDS, rig.provider))
		assertions.isTrue(outcome.batchCount <= EnemyProtocol.MAX_DELTA_MESSAGES_PER_FLUSH)
	end
	local metrics = rig.publisher:getMetrics()
	assertions.equal(metrics.pendingEntryCount, 0)
	assertions.equal(metrics.dirtyCorrectionCount, 0)
	return copySendsSince(rig, firstIndex)
end

local function assertClientsConverged(assertions: Assertions, rig: any)
	local first = stateSnapshot(assertions, rig.states[rig.recipients[1]])
	for index = 2, #rig.recipients do
		local other = stateSnapshot(assertions, rig.states[rig.recipients[index]])
		assertions.equal(other.matchId, first.matchId)
		assertions.equal(other.enemyEpoch, first.enemyEpoch)
		assertions.equal(other.lastSequence, first.lastSequence)
		assertions.equal(#other.entries, #first.entries)
		assertions.equal(#other.tombstones, #first.tombstones)
		for entryIndex, entry in first.entries do
			local comparison = other.entries[entryIndex]
			assertions.equal(comparison.runtimeEnemyId, entry.runtimeEnemyId)
			assertions.equal(comparison.revision, entry.revision)
			assertions.equal(comparison.pathProgress, entry.pathProgress)
			assertions.equal(comparison.lifecycle, entry.lifecycle)
		end
		for tombstoneIndex, tombstone in first.tombstones do
			local comparison = other.tombstones[tombstoneIndex]
			assertions.equal(comparison.runtimeEnemyId, tombstone.runtimeEnemyId)
			assertions.equal(comparison.revision, tombstone.revision)
		end
	end
end

local function cleanupRig(assertions: Assertions, rig: any)
	for _, recipient in rig.recipients do
		assertions.isTrue(success(assertions, rig.publisher:removePlayer(recipient)))
	end
	assertions.equal(rig.publisher:getMetrics().trackedRequestPlayerCount, 0)

	assertions.isTrue(success(assertions, rig.publisher:cleanup()))
	assertions.isFalse(success(assertions, rig.publisher:cleanup()))
	local publisherMetrics = rig.publisher:getMetrics()
	assertions.isTrue(publisherMetrics.cleaned)
	assertions.isFalse(publisherMetrics.retainsSender)
	assertions.isFalse(publisherMetrics.retainsRecipientProvider)
	assertions.equal(publisherMetrics.activeRepresentationCount, 0)
	assertions.equal(publisherMetrics.lifetimeRepresentationCount, 0)
	assertions.equal(publisherMetrics.pendingEntryCount, 0)
	assertions.equal(publisherMetrics.trackedRequestPlayerCount, 0)

	assertions.isTrue(success(assertions, rig.store:cleanup()))
	assertions.isFalse(success(assertions, rig.store:cleanup()))
	local storeMetrics = rig.store:getMetrics()
	assertions.isTrue(storeMetrics.cleaned)
	assertions.equal(storeMetrics.activeCount, 0)
	assertions.equal(storeMetrics.lifetimeCount, 0)
	assertions.equal(storeMetrics.terminalCount, 0)
	assertions.equal(storeMetrics.retainedLaneCount, 0)
	assertions.isFalse(storeMetrics.retainsCatalog)
	assertions.isFalse(storeMetrics.retainsClockCallback)
	assertions.isFalse(storeMetrics.retainsEndpointCallback)

	for _, recipient in rig.recipients do
		local state = rig.states[recipient]
		assertions.isTrue(success(assertions, state:cleanup()))
		assertions.isTrue(success(assertions, state:cleanup()))
		assertions.isFalse(state:getSnapshot().ok)
	end
end

return TestHarness.suite("enemy simulation deterministic headless integration", {
	TestHarness.case(
		"converges multiple lanes speeds slows corners and exact endpoints on two clients",
		function(assertions)
			local rig = newRig(assertions, 2)
			for _, recipient in rig.recipients do
				local initial = requestAndInstallSnapshot(assertions, rig, recipient, 1)
				assertions.equal(initial.kind, "SnapshotApplied")
				assertions.equal(#stateSnapshot(assertions, rig.states[recipient]).entries, 0)
			end

			local normal = spawnEnemy(assertions, rig, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID)
			local fast = spawnEnemy(assertions, rig, EnemyFixtures.FAST_ENEMY_ID, EnemyFixtures.BENT_LANE_ID)
			local slow = spawnEnemy(assertions, rig, EnemyFixtures.SLOW_ENEMY_ID, EnemyFixtures.STRAIGHT_LANE_ID)
			local spawnRecords = flushPending(assertions, rig)
			deliverRecords(assertions, rig, spawnRecords)
			assertClientsConverged(assertions, rig)
			local spawnEntry =
				findEntry(stateSnapshot(assertions, rig.states[rig.recipients[1]]), normal.runtimeEnemyId)

			local slowed = setSlow(assertions, rig, slow.runtimeEnemyId, 0.5)
			assertions.equal(slowed.effectiveSpeed, 2.5)
			local firstStep = stepSimulation(assertions, rig, 1.5)
			assertions.equal(firstStep.visitedCount, 3)
			assertions.equal(firstStep.updatedCount, 3)
			assertions.equal(firstStep.endpointCount, 0)
			local movementRecords = flushPending(assertions, rig)
			deliverRecords(assertions, rig, movementRecords)
			assertClientsConverged(assertions, rig)

			local movedState = stateSnapshot(assertions, rig.states[rig.recipients[1]])
			assertions.equal(findEntry(movedState, normal.runtimeEnemyId).pathProgress, 15)
			assertions.equal(findEntry(movedState, fast.runtimeEnemyId).pathProgress, 30)
			assertions.equal(findEntry(movedState, slow.runtimeEnemyId).pathProgress, 3.75)

			local currentEntry = findEntry(movedState, normal.runtimeEnemyId)
			local cornerRenderTime = spawnEntry.sampleServerTime
				+ (currentEntry.sampleServerTime - spawnEntry.sampleServerTime) * (10 / 15)
				+ EnemyPresentation.INTERPOLATION_DELAY_SECONDS
			local corner = success(assertions, EnemyPresentation.sample(spawnEntry, currentEntry, cornerRenderTime))
			assertClose(assertions, corner.pathProgress, 10, 1e-6)
			assertVectorClose(assertions, corner.worldCFrame.Position, Vector3.new(10, 5, 0), 1e-6)
			assertVectorClose(assertions, corner.worldCFrame.LookVector, Vector3.zAxis, 1e-6)
			assertions.isFalse(corner.snapped)

			local endpointById: { [number]: any } = {}
			for _, deltaSeconds in { 0.5, 2, 4 } do
				local step = stepSimulation(assertions, rig, deltaSeconds)
				for _, resolution in step.endpointResolutions do
					assertions.isTrue(resolution.callbackSucceeded)
					endpointById[resolution.endpoint.runtimeEnemyId] = resolution.endpoint
				end
				local records = flushPending(assertions, rig)
				deliverRecords(assertions, rig, records)
				assertClientsConverged(assertions, rig)
			end

			assertions.equal(#rig.endpointCallbacks, 3)
			assertions.equal(rig.endpointCallbacks[1].runtimeEnemyId, fast.runtimeEnemyId)
			assertions.equal(rig.endpointCallbacks[2].runtimeEnemyId, normal.runtimeEnemyId)
			assertions.equal(rig.endpointCallbacks[3].runtimeEnemyId, slow.runtimeEnemyId)
			assertClose(assertions, endpointById[fast.runtimeEnemyId].sampleServerTime - fast.spawnServerTime, 2, 1e-9)
			assertClose(
				assertions,
				endpointById[normal.runtimeEnemyId].sampleServerTime - normal.spawnServerTime,
				4,
				1e-9
			)
			assertClose(assertions, endpointById[slow.runtimeEnemyId].sampleServerTime - slow.spawnServerTime, 8, 1e-9)

			local terminalClient = stateSnapshot(assertions, rig.states[rig.recipients[1]])
			assertions.equal(#terminalClient.entries, 0)
			assertions.equal(#terminalClient.tombstones, 3)
			for runtimeEnemyId = 1, 3 do
				local terminal = success(assertions, rig.store:queryTerminal(runtimeEnemyId))
				assertions.equal(terminal.reason, "Endpoint")
			end

			local after = stepSimulation(assertions, rig, 1)
			assertions.equal(after.visitedCount, 0)
			assertions.equal(after.endpointCount, 0)
			assertions.equal(#rig.endpointCallbacks, 3)
			assertions.equal(#flushPending(assertions, rig), 0)

			local oldCorrection: any = nil
			for _, record in recordsForRecipient(movementRecords, rig.recipients[1]) do
				if record.message.kind == EnemyProtocol.CORRECTION_BATCH_KIND then
					oldCorrection = record
					break
				end
			end
			assertions.isNotNil(oldCorrection)
			local stale = deliverRecords(assertions, rig, { oldCorrection })[1]
			assertions.equal(stale.kind, "Stale")
			assertions.equal(#stateSnapshot(assertions, rig.states[rig.recipients[1]]).entries, 0)

			cleanupRig(assertions, rig)
		end
	),

	TestHarness.case(
		"repairs a real sequence gap with one late snapshot and never resurrects the despawned identity",
		function(assertions)
			local rig = newRig(assertions, 1)
			local recipient = rig.recipients[1]
			local initial = requestAndInstallSnapshot(assertions, rig, recipient, 1)
			assertions.equal(initial.kind, "SnapshotApplied")

			local spawned = spawnEnemy(assertions, rig, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID)
			local spawnRecords = flushPending(assertions, rig)
			deliverRecords(assertions, rig, spawnRecords)
			assertions.equal(stateSnapshot(assertions, rig.states[recipient]).lastSequence, 1)

			stepSimulation(assertions, rig, 0.5)
			local withheld = flushPending(assertions, rig)
			assertions.equal((withheld[1].message :: any).sequence, 2)
			stepSimulation(assertions, rig, 0.5)
			local later = flushPending(assertions, rig)
			assertions.equal((later[1].message :: any).sequence, 3)
			local gap = deliverRecords(assertions, rig, later)[1]
			assertions.equal(gap.kind, "Buffered")
			assertions.isTrue(gap.recoveryRequested)
			assertions.isTrue(stateSnapshot(assertions, rig.states[recipient]).recoveryRequired)

			local recovered = requestAndInstallSnapshot(assertions, rig, recipient, 2)
			assertions.equal(recovered.kind, "SnapshotApplied")
			local converged = stateSnapshot(assertions, rig.states[recipient])
			assertions.equal(converged.lastSequence, 3)
			assertions.equal(converged.bufferedCount, 0)
			assertions.isFalse(converged.recoveryRequired)
			assertions.equal(findEntry(converged, spawned.runtimeEnemyId).pathProgress, 10)

			local delayed = deliverRecords(assertions, rig, withheld)[1]
			assertions.equal(delayed.kind, "Stale")
			local duplicate = deliverRecords(assertions, rig, later)[1]
			assertions.equal(duplicate.kind, "Duplicate")
			assertions.equal(
				findEntry(stateSnapshot(assertions, rig.states[recipient]), spawned.runtimeEnemyId).pathProgress,
				10
			)

			local despawn = manualDespawn(assertions, rig, spawned.runtimeEnemyId)
			assertions.equal(despawn.reason, "Manual")
			local despawnRecords = flushPending(assertions, rig)
			deliverRecords(assertions, rig, despawnRecords)
			local terminal = stateSnapshot(assertions, rig.states[recipient])
			assertions.equal(#terminal.entries, 0)
			assertions.equal(#terminal.tombstones, 1)
			assertions.equal(terminal.tombstones[1].runtimeEnemyId, spawned.runtimeEnemyId)

			for _, oldRecords in { spawnRecords, withheld, later } do
				local stale = deliverRecords(assertions, rig, oldRecords)[1]
				assertions.isTrue(stale.kind == "Stale" or stale.kind == "Duplicate")
			end
			assertions.equal(#stateSnapshot(assertions, rig.states[recipient]).entries, 0)
			assertions.equal(rig.store:getMetrics().activeCount, 0)
			cleanupRig(assertions, rig)
		end
	),

	TestHarness.case("bounds centralized headless work at the declared 1 32 64 128 ladder", function(assertions)
		for _, enemyCount in { 1, 32, 64, 128 } do
			local rig = newRig(assertions, 1)
			local recipient = rig.recipients[1]
			requestAndInstallSnapshot(assertions, rig, recipient, 1)

			for _ = 1, enemyCount do
				spawnEnemy(assertions, rig, EnemyFixtures.NORMAL_ENEMY_ID, EnemyFixtures.BENT_LANE_ID)
			end
			local spawnRecords = flushPending(assertions, rig)
			deliverRecords(assertions, rig, spawnRecords)
			local spawned = stateSnapshot(assertions, rig.states[recipient])
			assertions.equal(#spawned.entries, enemyCount)
			assertions.equal(rig.store:getMetrics().activeCount, enemyCount)
			assertions.equal(rig.publisher:getMetrics().activeRepresentationCount, enemyCount)

			local serverSimulationPassCount = 0
			serverSimulationPassCount += 1
			local step = stepSimulation(assertions, rig, 0.1)
			assertions.equal(serverSimulationPassCount, 1)
			assertions.equal(step.visitedCount, enemyCount)
			assertions.equal(step.updatedCount, enemyCount)
			assertions.equal(step.endpointCount, 0)

			local correctionRecords = flushPending(assertions, rig)
			deliverRecords(assertions, rig, correctionRecords)
			local converged = stateSnapshot(assertions, rig.states[recipient])
			assertions.equal(#converged.entries, enemyCount)
			assertions.equal(converged.bufferedCount, 0)
			assertions.isFalse(converged.recoveryRequired)

			local clientPresentationPassCount = 0
			clientPresentationPassCount += 1
			for expectedRuntimeEnemyId, entry in converged.entries do
				assertions.equal(entry.runtimeEnemyId, expectedRuntimeEnemyId)
				assertions.equal(entry.revision, 2)
				assertions.equal(entry.pathProgress, 1)
				local sample = success(assertions, EnemyPresentation.sample(nil, entry, rig.clock.now))
				assertClose(assertions, sample.pathProgress, 1, 1e-9)
			end
			assertions.equal(clientPresentationPassCount, 1)

			for _, record in spawnRecords do
				local message = record.message :: any
				assertions.equal(message.kind, EnemyProtocol.SPAWN_BATCH_KIND)
				assertions.isTrue(#message.entries <= EnemyProtocol.MAX_ENTRIES_PER_MESSAGE)
			end
			for _, record in correctionRecords do
				local message = record.message :: any
				assertions.equal(message.kind, EnemyProtocol.CORRECTION_BATCH_KIND)
				assertions.isTrue(#message.entries <= EnemyProtocol.MAX_ENTRIES_PER_MESSAGE)
			end
			local expectedMessagesPerPass = math.ceil(enemyCount / EnemyProtocol.MAX_ENTRIES_PER_MESSAGE)
			local metrics = rig.publisher:getMetrics()
			assertions.equal(#spawnRecords, expectedMessagesPerPass)
			assertions.equal(#correctionRecords, expectedMessagesPerPass)
			assertions.equal(metrics.deltaMessageCount, expectedMessagesPerPass * 2)
			assertions.equal(metrics.senderCallCount, 2 + expectedMessagesPerPass * 2)
			assertions.equal(metrics.pendingEntryCount, 0)
			assertions.equal(metrics.dirtyCorrectionCount, 0)
			assertions.equal(metrics.senderFailureCount, 0)

			cleanupRig(assertions, rig)
		end
	end),
})
