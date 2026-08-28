--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local EnemyReplicationPublisher = require(script.Parent.Parent.ProductionServerEnemies.EnemyReplicationPublisher)

local Shared = game:GetService("ReplicatedStorage").Shared
local EnemyProtocol = require(Shared.match.EnemyProtocol)
local Result = require(Shared.util.Result)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase09-enemy-publisher"

local newForTests = EnemyReplicationPublisher.newForTests
if newForTests == nil then
	error("EnemyReplicationPublisher test constructor unavailable at exact Test location", 0)
end

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected enemy replication publisher operation to succeed", 0)
	end
	return result.value
end

local function expectError(assertions: Assertions, result: any, code: string, operation: string)
	assertions.isFalse(result.ok)
	if not result.ok then
		assertions.isTrue(table.isfrozen(result.error))
		assertions.equal(result.error.code, code)
		assertions.equal(result.error.operation, operation)
	end
end

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

local function stateSnapshot(
	runtimeEnemyId: number,
	revision: number,
	progress: number,
	slowMultiplier: number?,
	lifecycle: ("Active" | "EndpointResolved")?
): any
	local canonicalLifecycle = lifecycle or "Active"
	local canonicalProgress = if canonicalLifecycle == "EndpointResolved" then 10 else progress
	local startPosition = Vector3.new(0, 5, 0)
	local endPosition = Vector3.new(10, 5, 0)
	local position = startPosition:Lerp(endPosition, canonicalProgress / 10)
	local multiplier = slowMultiplier or 1
	return table.freeze({
		runtimeEnemyId = runtimeEnemyId,
		enemyId = "enemy:publisher-fixture",
		laneId = "fixture-lane",
		pathProgress = canonicalProgress,
		currentHealth = 100,
		maximumHealth = 100,
		speedModifiers = table.freeze({
			slowMultiplier = multiplier,
		}),
		spawnServerTime = 100,
		sampleServerTime = 100 + revision / 10,
		lifecycle = canonicalLifecycle,
		revision = revision,
		worldCFrame = canonicalCFrame(position, endPosition - startPosition),
		effectiveSpeed = 10 * multiplier,
		segmentIndex = 1,
		segmentStartDistance = 0,
		segmentEndDistance = 10,
		segmentStartPosition = startPosition,
		segmentEndPosition = endPosition,
	})
end

local function despawnSnapshot(runtimeEnemyId: number, revision: number, reason: "Manual" | "Endpoint" | "Defeat"): any
	return table.freeze({
		runtimeEnemyId = runtimeEnemyId,
		enemyId = "enemy:publisher-fixture",
		laneId = "fixture-lane",
		revision = revision,
		lifecycle = "Despawned",
		reason = reason,
		sampleServerTime = 100 + revision / 10,
	})
end

local function frozenSnapshots(values: { any }): any
	return Result.ok(table.freeze(values))
end

local function makeEnvironment(limits: { [string]: any }?): any
	local firstRecipient = {}
	local secondRecipient = {}
	local environment: any = {
		firstRecipient = firstRecipient,
		secondRecipient = secondRecipient,
		recipients = {
			{ recipient = secondRecipient, userId = 20 },
			{ recipient = firstRecipient, userId = 10 },
		},
		sends = {},
		states = {},
		senderMode = "success",
		senderBehavior = nil,
	}
	environment.sender = function(recipient: unknown, message: EnemyProtocol.EnemyReplicationMessage): boolean
		table.insert(environment.sends, {
			recipient = recipient,
			message = message,
		})
		if environment.senderBehavior ~= nil then
			return environment.senderBehavior(recipient, message)
		end
		return environment.senderMode ~= "failure"
	end
	environment.getRecipients = function(): unknown
		return environment.recipients
	end
	environment.provider = function(runtimeEnemyIds: { number }?): unknown
		if runtimeEnemyIds == nil then
			local all: { any } = {}
			for runtimeEnemyId, state in environment.states do
				table.insert(all, { runtimeEnemyId = runtimeEnemyId, state = state })
			end
			table.sort(all, function(left, right): boolean
				return left.runtimeEnemyId < right.runtimeEnemyId
			end)
			local snapshots: { any } = table.create(#all)
			for _, record in all do
				table.insert(snapshots, record.state)
			end
			return frozenSnapshots(snapshots)
		end
		local snapshots: { any } = table.create(#runtimeEnemyIds)
		for _, runtimeEnemyId in runtimeEnemyIds do
			local state = environment.states[runtimeEnemyId]
			if state == nil then
				return Result.err(table.freeze({ code = "MISSING" }))
			end
			table.insert(snapshots, state)
		end
		return frozenSnapshots(snapshots)
	end
	local result = (newForTests :: EnemyReplicationPublisher.TestConstructor)(MATCH_ID, 1, {
		sender = environment.sender,
		getRecipients = environment.getRecipients,
	}, limits)
	if not result.ok then
		error("publisher construction failed", 0)
	end
	environment.publisher = result.value
	return environment
end

local function newEnvironment(assertions: Assertions, limits: { [string]: any }?): any
	local environment = makeEnvironment(limits)
	assertions.isTrue(table.isfrozen(environment.publisher))
	return environment
end

local function messagesForRecipient(environment: any, recipient: unknown): { EnemyProtocol.EnemyReplicationMessage }
	local messages: { EnemyProtocol.EnemyReplicationMessage } = {}
	for _, send in environment.sends do
		if send.recipient == recipient then
			table.insert(messages, send.message)
		end
	end
	return messages
end

local function assertWireMessage(assertions: Assertions, message: unknown)
	local result = EnemyProtocol.validateEnemyReplication(message)
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(message :: any))
end

return TestHarness.suite("server enemy replication publisher", {
	TestHarness.case("batches spawns at cadence with deterministic recipient and entry order", function(assertions)
		local environment = newEnvironment(assertions, nil)
		local publisher = environment.publisher
		for runtimeEnemyId = 1, 10 do
			success(assertions, publisher:preflightSpawn())
			success(assertions, publisher:commitSpawn(stateSnapshot(runtimeEnemyId, 1, 0)))
			environment.states[runtimeEnemyId] = stateSnapshot(runtimeEnemyId, 1, 0)
		end

		local early = success(assertions, publisher:advance(0.05, environment.provider))
		assertions.isFalse(early.flushOccurred)
		assertions.equal(#environment.sends, 0)
		local flushed = success(assertions, publisher:advance(0.05, environment.provider))
		assertions.isTrue(flushed.flushOccurred)
		assertions.equal(flushed.batchCount, 2)
		assertions.equal(flushed.entryCount, 10)
		assertions.equal(#environment.sends, 4)
		assertions.equal(environment.sends[1].recipient, environment.firstRecipient)
		assertions.equal(environment.sends[2].recipient, environment.secondRecipient)

		local messages = messagesForRecipient(environment, environment.firstRecipient)
		assertions.equal(#messages, 2)
		assertions.equal(messages[1].kind, EnemyProtocol.SPAWN_BATCH_KIND)
		assertions.equal((messages[1] :: any).sequence, 1)
		assertions.equal(#(messages[1] :: any).entries, 8)
		assertions.equal((messages[1] :: any).entries[1].runtimeEnemyId, 1)
		assertions.equal((messages[1] :: any).entries[8].runtimeEnemyId, 8)
		assertions.equal((messages[2] :: any).sequence, 2)
		assertions.equal(#(messages[2] :: any).entries, 2)
		for _, message in messages do
			assertWireMessage(assertions, message)
		end

		local metrics = publisher:getMetrics()
		assertions.equal(metrics.pendingEntryCount, 0)
		assertions.equal(metrics.reservedFutureMessageCount, 20)
		assertions.equal(metrics.deltaMessageCount, 2)
		assertions.equal(metrics.nextSequence, 3)
	end),

	TestHarness.case("preflights one complete ordered store identity before an atomic step", function(assertions)
		local environment = newEnvironment(assertions, nil)
		local publisher = environment.publisher
		success(assertions, publisher:commitSpawn(stateSnapshot(1, 1, 0)))
		success(assertions, publisher:commitSpawn(stateSnapshot(2, 1, 0)))

		success(assertions, publisher:preflightStep(table.freeze({ 1, 2 })))
		expectError(assertions, publisher:preflightStep({ 1, 2 }), "INVALID_ARGUMENT", "preflightStep")
		expectError(assertions, publisher:preflightStep(table.freeze({ 1 })), "INVALID_ARGUMENT", "preflightStep")
		expectError(assertions, publisher:preflightStep(table.freeze({ 2, 1 })), "INVALID_ARGUMENT", "preflightStep")
		expectError(assertions, publisher:preflightStep(table.freeze({ 1, 3 })), "ILLEGAL_LIFECYCLE", "preflightStep")

		success(assertions, publisher:commitManualDespawn(despawnSnapshot(1, 2, "Manual")))
		success(assertions, publisher:preflightStep(table.freeze({ 2 })))
	end),

	TestHarness.case("preflights and commits one ordered atomic Defeat terminal set", function(assertions)
		local environment = newEnvironment(assertions, nil)
		local publisher = environment.publisher
		for runtimeEnemyId = 1, 3 do
			success(assertions, publisher:commitSpawn(stateSnapshot(runtimeEnemyId, 1, 0)))
			environment.states[runtimeEnemyId] = stateSnapshot(runtimeEnemyId, 1, 0)
		end

		local activeIds = table.freeze({ 1, 2, 3 })
		assertions.isTrue(success(assertions, publisher:preflightDefeat(activeIds)))
		expectError(assertions, publisher:preflightDefeat({ 1, 2, 3 }), "INVALID_ARGUMENT", "preflightDefeat")
		expectError(
			assertions,
			publisher:preflightDefeat(table.freeze({ 1, 3, 2 })),
			"INVALID_ARGUMENT",
			"preflightDefeat"
		)
		expectError(
			assertions,
			publisher:preflightDefeat(table.freeze({ 1, 2 })),
			"INVALID_ARGUMENT",
			"preflightDefeat"
		)

		local malformed = table.freeze({
			despawnSnapshot(1, 2, "Defeat"),
			despawnSnapshot(2, 2, "Manual"),
			despawnSnapshot(3, 2, "Defeat"),
		})
		expectError(assertions, publisher:commitDefeat(malformed), "INVALID_SNAPSHOT", "commitDefeat")
		assertions.equal(publisher:getMetrics().activeRepresentationCount, 3)
		success(assertions, publisher:observeCorrection(2))
		environment.states[2] = stateSnapshot(2, 2, 1)
		assertions.equal(publisher:getMetrics().dirtyCorrectionCount, 1)

		local committed = success(
			assertions,
			publisher:commitDefeat(table.freeze({
				despawnSnapshot(1, 2, "Defeat"),
				despawnSnapshot(2, 3, "Defeat"),
				despawnSnapshot(3, 2, "Defeat"),
			}))
		)
		assertions.isTrue(table.isfrozen(committed))
		assertions.equal(#committed, 3)
		for index, despawn in committed do
			assertions.equal(despawn.runtimeEnemyId, index)
			assertions.equal(despawn.reason, "Defeat")
			assertions.isTrue(table.isfrozen(despawn))
		end
		assertions.equal(publisher:getMetrics().activeRepresentationCount, 0)
		assertions.equal(publisher:getMetrics().terminalPendingCount, 3)
		assertions.equal(publisher:getMetrics().dirtyCorrectionCount, 0)

		local flushed = success(assertions, publisher:advance(0.1, environment.provider))
		assertions.equal(flushed.batchCount, 2)
		local messages = messagesForRecipient(environment, environment.firstRecipient)
		assertions.equal(messages[1].kind, EnemyProtocol.SPAWN_BATCH_KIND)
		assertions.equal(messages[2].kind, EnemyProtocol.DESPAWN_BATCH_KIND)
		for index, despawn in (messages[2] :: any).entries do
			assertions.equal(despawn.runtimeEnemyId, index)
			assertions.equal(despawn.reason, "Defeat")
		end
		assertions.equal(publisher:getMetrics().terminalPendingCount, 0)
	end),

	TestHarness.case(
		"preserves state then correction causality while coalescing repeated movement",
		function(assertions)
			local environment = newEnvironment(assertions, nil)
			local publisher = environment.publisher
			success(assertions, publisher:commitSpawn(stateSnapshot(1, 1, 0)))
			environment.states[1] = stateSnapshot(1, 1, 0)
			success(assertions, publisher:advance(0.1, environment.provider))
			table.clear(environment.sends)

			success(assertions, publisher:preflightStateChange(1))
			local slowed = stateSnapshot(1, 2, 0, 0.5)
			success(assertions, publisher:commitStateChange(slowed))
			success(assertions, publisher:observeCorrection(1))
			success(assertions, publisher:observeCorrection(1))
			environment.states[1] = stateSnapshot(1, 4, 2, 0.5)

			local flushed = success(assertions, publisher:advance(0.1, environment.provider))
			assertions.equal(flushed.batchCount, 2)
			assertions.equal(flushed.entryCount, 2)
			local messages = messagesForRecipient(environment, environment.firstRecipient)
			assertions.equal(messages[1].kind, EnemyProtocol.STATE_CHANGE_BATCH_KIND)
			assertions.equal((messages[1] :: any).entries[1].revision, 2)
			assertions.equal(messages[2].kind, EnemyProtocol.CORRECTION_BATCH_KIND)
			assertions.equal((messages[2] :: any).entries[1].revision, 4)
			assertions.equal(publisher:getMetrics().dirtyCorrectionCount, 0)
		end
	),

	TestHarness.case("absorbs unpublished active state into one spawn payload", function(assertions)
		local environment = newEnvironment(assertions, nil)
		local publisher = environment.publisher
		success(assertions, publisher:commitSpawn(stateSnapshot(1, 1, 0)))
		success(assertions, publisher:commitStateChange(stateSnapshot(1, 2, 0, 0.25)))
		success(assertions, publisher:observeCorrection(1))
		environment.states[1] = stateSnapshot(1, 3, 1, 0.25)

		local flushed = success(assertions, publisher:advance(0.1, environment.provider))
		assertions.equal(flushed.batchCount, 1)
		assertions.equal(flushed.entryCount, 1)
		local message = messagesForRecipient(environment, environment.firstRecipient)[1] :: any
		assertions.equal(message.kind, EnemyProtocol.SPAWN_BATCH_KIND)
		assertions.equal(message.entries[1].revision, 3)
		assertions.equal(message.entries[1].pathProgress, 1)
	end),

	TestHarness.case(
		"orders exact endpoint and manual terminal records and holds the spawn barrier",
		function(assertions)
			local environment = newEnvironment(assertions, nil)
			local publisher = environment.publisher
			for runtimeEnemyId = 1, 2 do
				success(assertions, publisher:commitSpawn(stateSnapshot(runtimeEnemyId, 1, 0)))
				environment.states[runtimeEnemyId] = stateSnapshot(runtimeEnemyId, 1, 0)
			end
			success(assertions, publisher:advance(0.1, environment.provider))
			table.clear(environment.sends)

			success(assertions, publisher:preflightEndpoint(1))
			success(
				assertions,
				publisher:commitEndpoint(
					stateSnapshot(1, 2, 10, 1, "EndpointResolved"),
					despawnSnapshot(1, 3, "Endpoint")
				)
			)
			success(assertions, publisher:preflightManualDespawn(2))
			success(assertions, publisher:commitManualDespawn(despawnSnapshot(2, 2, "Manual")))
			environment.states[1] = nil
			environment.states[2] = nil
			expectError(assertions, publisher:preflightSpawn(), "CAPACITY_EXCEEDED", "preflightSpawn")

			local flushed = success(assertions, publisher:advance(0.1, environment.provider))
			assertions.equal(flushed.batchCount, 2)
			assertions.equal(flushed.entryCount, 3)
			local messages = messagesForRecipient(environment, environment.firstRecipient)
			assertions.equal(messages[1].kind, EnemyProtocol.STATE_CHANGE_BATCH_KIND)
			assertions.equal((messages[1] :: any).entries[1].lifecycle, "EndpointResolved")
			assertions.equal(messages[2].kind, EnemyProtocol.DESPAWN_BATCH_KIND)
			assertions.equal(#(messages[2] :: any).entries, 2)
			assertions.equal((messages[2] :: any).entries[1].reason, "Endpoint")
			assertions.equal((messages[2] :: any).entries[2].reason, "Manual")
			assertions.equal(publisher:getMetrics().terminalPendingCount, 0)
			success(assertions, publisher:preflightSpawn())
		end
	),

	TestHarness.case(
		"keeps unfunded corrections dirty without blocking reserved terminal delivery",
		function(assertions)
			local environment = newEnvironment(assertions, {
				maxActive = 1,
				maxLifetime = 1,
				maxPendingEntries = 3,
				maxDeltaMessages = 3,
			})
			local publisher = environment.publisher
			success(assertions, publisher:commitSpawn(stateSnapshot(1, 1, 0)))
			environment.states[1] = stateSnapshot(1, 1, 0)
			success(assertions, publisher:advance(0.1, environment.provider))
			table.clear(environment.sends)

			success(assertions, publisher:observeCorrection(1))
			environment.states[1] = stateSnapshot(1, 2, 1)
			local correctionFlush = success(assertions, publisher:advance(0.1, environment.provider))
			assertions.equal(correctionFlush.batchCount, 0)
			assertions.equal(publisher:getMetrics().dirtyCorrectionCount, 1)

			success(
				assertions,
				publisher:commitEndpoint(
					stateSnapshot(1, 3, 10, 1, "EndpointResolved"),
					despawnSnapshot(1, 4, "Endpoint")
				)
			)
			environment.states[1] = nil
			local terminalFlush = success(assertions, publisher:advance(0.1, environment.provider))
			assertions.equal(terminalFlush.batchCount, 2)
			local messages = messagesForRecipient(environment, environment.firstRecipient)
			assertions.equal(messages[1].kind, EnemyProtocol.STATE_CHANGE_BATCH_KIND)
			assertions.equal(messages[2].kind, EnemyProtocol.DESPAWN_BATCH_KIND)
			assertions.equal(publisher:getMetrics().deltaMessageCount, 3)
			assertions.equal(publisher:getMetrics().terminalPendingCount, 0)
		end
	),

	TestHarness.case("rejects a new spawn when fewer than three delta slots remain", function(assertions)
		local environment = newEnvironment(assertions, {
			maxActive = 1,
			maxLifetime = 2,
			maxPendingEntries = 3,
			maxDeltaMessages = 3,
		})
		local publisher = environment.publisher
		success(assertions, publisher:commitSpawn(stateSnapshot(1, 1, 0)))
		environment.states[1] = stateSnapshot(1, 1, 0)
		success(assertions, publisher:advance(0.1, environment.provider))

		success(assertions, publisher:commitManualDespawn(despawnSnapshot(1, 2, "Manual")))
		environment.states[1] = nil
		success(assertions, publisher:advance(0.1, environment.provider))
		local metrics = publisher:getMetrics()
		assertions.equal(metrics.deltaMessageCount, 2)
		assertions.equal(metrics.reservedFutureMessageCount, 0)
		assertions.equal(metrics.lifetimeRepresentationCount, 1)

		expectError(assertions, publisher:preflightSpawn(), "CAPACITY_EXCEEDED", "preflightSpawn")
		expectError(assertions, publisher:commitSpawn(stateSnapshot(2, 1, 0)), "CAPACITY_EXCEEDED", "commitSpawn")
		assertions.equal(publisher:getMetrics().lifetimeRepresentationCount, 1)
	end),

	TestHarness.case("caps each flush at twelve eight-entry batches", function(assertions)
		local environment = newEnvironment(assertions, nil)
		local publisher = environment.publisher
		for runtimeEnemyId = 1, EnemyProtocol.MAX_ACTIVE_ENEMIES do
			success(assertions, publisher:commitSpawn(stateSnapshot(runtimeEnemyId, 1, 0)))
			environment.states[runtimeEnemyId] = stateSnapshot(runtimeEnemyId, 1, 0)
		end
		local first = success(assertions, publisher:advance(0.1, environment.provider))
		assertions.equal(first.batchCount, 12)
		assertions.equal(first.entryCount, 96)
		assertions.equal(first.remainingPendingEntries, 32)
		local second = success(assertions, publisher:advance(0.1, environment.provider))
		assertions.equal(second.batchCount, 4)
		assertions.equal(second.entryCount, 32)
		assertions.equal(second.remainingPendingEntries, 0)
		assertions.equal(publisher:getMetrics().activeRepresentationCount, 128)
	end),

	TestHarness.case("contains sender failures while consuming one logical sequence", function(assertions)
		local environment = newEnvironment(assertions, nil)
		environment.senderMode = "failure"
		local publisher = environment.publisher
		success(assertions, publisher:commitSpawn(stateSnapshot(1, 1, 0)))
		environment.states[1] = stateSnapshot(1, 1, 0)
		local flushed = success(assertions, publisher:advance(0.1, environment.provider))
		assertions.equal(flushed.batchCount, 1)
		local metrics = publisher:getMetrics()
		assertions.equal(metrics.deltaMessageCount, 1)
		assertions.equal(metrics.nextSequence, 2)
		assertions.equal(metrics.senderCallCount, 2)
		assertions.equal(metrics.senderFailureCount, 2)
		assertions.isFalse(metrics.faulted)
	end),

	TestHarness.case("continues after a throwing or yielding first recipient sender", function(assertions)
		for _, mode in { "throw", "yield" } do
			local environment = newEnvironment(assertions, nil)
			environment.senderBehavior = function(recipient: unknown, _message: unknown): boolean
				if recipient == environment.firstRecipient then
					if mode == "throw" then
						error("sender failure", 0)
					end
					coroutine.yield()
					return false
				end
				return true
			end
			local publisher = environment.publisher
			success(assertions, publisher:commitSpawn(stateSnapshot(1, 1, 0)))
			environment.states[1] = stateSnapshot(1, 1, 0)
			success(assertions, publisher:advance(0.1, environment.provider))

			local metrics = publisher:getMetrics()
			assertions.equal(metrics.senderCallCount, 2)
			assertions.equal(metrics.senderFailureCount, 1)
			assertions.equal(metrics.deltaMessageCount, 1)
			assertions.isFalse(metrics.faulted)
			assertions.equal(#environment.sends, 2)
			assertions.equal(environment.sends[1].recipient, environment.firstRecipient)
			assertions.equal(environment.sends[2].recipient, environment.secondRecipient)
		end
	end),

	TestHarness.case(
		"delivers bounded recipient-only snapshots and resets weak request state on removal",
		function(assertions)
			local environment = newEnvironment(assertions, nil)
			local publisher = environment.publisher
			for runtimeEnemyId = 1, 10 do
				success(assertions, publisher:commitSpawn(stateSnapshot(runtimeEnemyId, 1, 0)))
				environment.states[runtimeEnemyId] = stateSnapshot(runtimeEnemyId, 1, runtimeEnemyId / 10)
			end
			success(assertions, publisher:advance(0.1, environment.provider))
			table.clear(environment.sends)

			local receipt =
				success(assertions, publisher:requestSnapshot(environment.firstRecipient, environment.provider))
			assertions.equal(receipt.baseSequence, 2)
			assertions.equal(receipt.snapshotId, 1)
			assertions.equal(receipt.chunkCount, 2)
			assertions.equal(receipt.totalEntries, 10)
			assertions.equal(#environment.sends, 4)
			for _, send in environment.sends do
				assertions.equal(send.recipient, environment.firstRecipient)
				assertWireMessage(assertions, send.message)
			end
			assertions.equal(environment.sends[1].message.kind, EnemyProtocol.SNAPSHOT_BEGIN_KIND)
			assertions.equal(environment.sends[4].message.kind, EnemyProtocol.SNAPSHOT_END_KIND)

			success(assertions, publisher:requestSnapshot(environment.firstRecipient, environment.provider))
			expectError(
				assertions,
				publisher:requestSnapshot(environment.firstRecipient, environment.provider),
				"CAPACITY_EXCEEDED",
				"requestSnapshot"
			)
			assertions.equal(publisher:getMetrics().trackedRequestPlayerCount, 1)
			assertions.isTrue(success(assertions, publisher:removePlayer(environment.firstRecipient)))
			assertions.equal(publisher:getMetrics().trackedRequestPlayerCount, 0)
			success(assertions, publisher:requestSnapshot(environment.firstRecipient, environment.provider))
		end
	),

	TestHarness.case("anchors empty and pending-delta snapshots to the emitted base sequence", function(assertions)
		local environment = newEnvironment(assertions, nil)
		local publisher = environment.publisher
		local emptyReceipt =
			success(assertions, publisher:requestSnapshot(environment.firstRecipient, environment.provider))
		assertions.equal(emptyReceipt.baseSequence, 0)
		assertions.equal(emptyReceipt.chunkCount, 0)
		assertions.equal(emptyReceipt.totalEntries, 0)
		local emptyMessages = messagesForRecipient(environment, environment.firstRecipient)
		assertions.equal(#emptyMessages, 2)
		assertions.equal(emptyMessages[1].kind, EnemyProtocol.SNAPSHOT_BEGIN_KIND)
		assertions.equal(emptyMessages[2].kind, EnemyProtocol.SNAPSHOT_END_KIND)

		success(assertions, publisher:commitSpawn(stateSnapshot(1, 1, 0)))
		environment.states[1] = stateSnapshot(1, 1, 0)
		local pendingReceipt =
			success(assertions, publisher:requestSnapshot(environment.secondRecipient, environment.provider))
		assertions.equal(pendingReceipt.baseSequence, 0)
		assertions.equal(pendingReceipt.chunkCount, 1)
		assertions.equal(pendingReceipt.totalEntries, 1)
		local pendingMessages = messagesForRecipient(environment, environment.secondRecipient)
		assertions.equal(#pendingMessages, 3)
		assertions.equal(pendingMessages[2].kind, EnemyProtocol.SNAPSHOT_CHUNK_KIND)
		assertions.equal((pendingMessages[2] :: any).entries[1].runtimeEnemyId, 1)

		success(assertions, publisher:advance(0.1, environment.provider))
		local racedMessages = messagesForRecipient(environment, environment.secondRecipient)
		assertions.equal(#racedMessages, 4)
		assertions.equal(racedMessages[4].kind, EnemyProtocol.SPAWN_BATCH_KIND)
		assertions.equal((racedMessages[4] :: any).sequence, 1)
	end),

	TestHarness.case("consumes failed snapshot sends before ID and message-budget exhaustion", function(assertions)
		local idEnvironment = newEnvironment(assertions, {
			maxSnapshotIds = 2,
		})
		idEnvironment.senderMode = "failure"
		local thirdRecipient = {}
		table.insert(idEnvironment.recipients, {
			recipient = thirdRecipient,
			userId = 30,
		})
		local idPublisher = idEnvironment.publisher
		success(assertions, idPublisher:requestSnapshot(idEnvironment.firstRecipient, idEnvironment.provider))
		success(assertions, idPublisher:requestSnapshot(idEnvironment.secondRecipient, idEnvironment.provider))
		expectError(
			assertions,
			idPublisher:requestSnapshot(thirdRecipient, idEnvironment.provider),
			"CAPACITY_EXCEEDED",
			"requestSnapshot"
		)
		local idMetrics = idPublisher:getMetrics()
		assertions.equal(idMetrics.snapshotMessageCount, 4)
		assertions.equal(idMetrics.nextSnapshotId, 3)
		assertions.equal(idMetrics.senderCallCount, 4)
		assertions.equal(idMetrics.senderFailureCount, 4)

		local messageEnvironment = newEnvironment(assertions, {
			maxSnapshotMessages = 3,
		})
		messageEnvironment.senderMode = "failure"
		local messagePublisher = messageEnvironment.publisher
		success(
			assertions,
			messagePublisher:requestSnapshot(messageEnvironment.firstRecipient, messageEnvironment.provider)
		)
		expectError(
			assertions,
			messagePublisher:requestSnapshot(messageEnvironment.firstRecipient, messageEnvironment.provider),
			"CAPACITY_EXCEEDED",
			"requestSnapshot"
		)
		local messageMetrics = messagePublisher:getMetrics()
		assertions.equal(messageMetrics.snapshotMessageCount, 2)
		assertions.equal(messageMetrics.nextSnapshotId, 2)
		assertions.equal(messageMetrics.senderCallCount, 2)
		assertions.equal(messageMetrics.senderFailureCount, 2)
	end),

	TestHarness.case("rejects malformed correction and snapshot providers without sending", function(assertions)
		local correctionEnvironment = newEnvironment(assertions, nil)
		local correctionPublisher = correctionEnvironment.publisher
		success(assertions, correctionPublisher:commitSpawn(stateSnapshot(1, 1, 0)))
		correctionEnvironment.states[1] = stateSnapshot(1, 1, 0)
		success(assertions, correctionPublisher:advance(0.1, correctionEnvironment.provider))
		table.clear(correctionEnvironment.sends)
		success(assertions, correctionPublisher:observeCorrection(1))
		local malformedCorrectionProvider = function(): unknown
			return Result.ok({ stateSnapshot(1, 2, 1) })
		end
		expectError(
			assertions,
			correctionPublisher:advance(0.1, malformedCorrectionProvider),
			"INVALID_PROVIDER",
			"advance"
		)
		assertions.equal(#correctionEnvironment.sends, 0)
		assertions.isTrue(correctionPublisher:getMetrics().faulted)

		local snapshotEnvironment = newEnvironment(assertions, nil)
		local snapshotPublisher = snapshotEnvironment.publisher
		local malformedSnapshotProvider = function(): unknown
			return Result.ok({})
		end
		expectError(
			assertions,
			snapshotPublisher:requestSnapshot(snapshotEnvironment.firstRecipient, malformedSnapshotProvider),
			"INVALID_PROVIDER",
			"requestSnapshot"
		)
		local snapshotMetrics = snapshotPublisher:getMetrics()
		assertions.equal(#snapshotEnvironment.sends, 0)
		assertions.equal(snapshotMetrics.snapshotMessageCount, 0)
		assertions.equal(snapshotMetrics.nextSnapshotId, 1)
		assertions.isFalse(snapshotMetrics.faulted)
	end),

	TestHarness.case("faults on recipient overflow without publishing", function(assertions)
		local environment = newEnvironment(assertions, nil)
		local publisher = environment.publisher
		success(assertions, publisher:commitSpawn(stateSnapshot(1, 1, 0)))
		environment.states[1] = stateSnapshot(1, 1, 0)
		environment.recipients = {
			{ recipient = {}, userId = 1 },
			{ recipient = {}, userId = 2 },
			{ recipient = {}, userId = 3 },
			{ recipient = {}, userId = 4 },
			{ recipient = {}, userId = 5 },
		}
		expectError(assertions, publisher:advance(0.1, environment.provider), "INTERNAL_ERROR", "advance")
		assertions.equal(#environment.sends, 0)
		assertions.isTrue(publisher:getMetrics().faulted)
	end),

	TestHarness.case("defers cleanup during publication and stops later recipient callbacks", function(assertions)
		local environment = newEnvironment(assertions, nil)
		local publisher = environment.publisher
		local cleanupResult: any = nil
		environment.senderBehavior = function(_recipient: unknown, _message: unknown): boolean
			cleanupResult = publisher:cleanup()
			return true
		end
		success(assertions, publisher:commitSpawn(stateSnapshot(1, 1, 0)))
		environment.states[1] = stateSnapshot(1, 1, 0)
		expectError(assertions, publisher:advance(0.1, environment.provider), "CLEANED", "advance")

		assertions.equal(#environment.sends, 1)
		assertions.isTrue(cleanupResult.ok)
		assertions.isFalse(cleanupResult.value)
		local metrics = publisher:getMetrics()
		assertions.isTrue(metrics.cleaned)
		assertions.equal(metrics.pendingEntryCount, 0)
		assertions.equal(metrics.senderCallCount, 0)
		assertions.isFalse(metrics.retainsSender)
		assertions.isFalse(metrics.retainsRecipientProvider)
		expectError(assertions, publisher:advance(0.1, environment.provider), "CLEANED", "advance")
		assertions.equal(#environment.sends, 1)
	end),

	TestHarness.case("cleans queued state callbacks and weak counters exactly once", function(assertions)
		local environment = newEnvironment(assertions, nil)
		local publisher = environment.publisher
		success(assertions, publisher:commitSpawn(stateSnapshot(1, 1, 0)))
		environment.states[1] = stateSnapshot(1, 1, 0)
		success(assertions, publisher:requestSnapshot(environment.firstRecipient, environment.provider))
		assertions.isTrue(success(assertions, publisher:cleanup()))
		local metrics = publisher:getMetrics()
		assertions.isTrue(metrics.cleaned)
		assertions.isFalse(metrics.retainsSender)
		assertions.isFalse(metrics.retainsRecipientProvider)
		assertions.equal(metrics.pendingEntryCount, 0)
		assertions.equal(metrics.trackedRequestPlayerCount, 0)
		assertions.isFalse(success(assertions, publisher:cleanup()))
		expectError(assertions, publisher:advance(0.1, environment.provider), "CLEANED", "advance")
	end),
})
