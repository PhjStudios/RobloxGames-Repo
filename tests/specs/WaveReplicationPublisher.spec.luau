--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaveProtocol = require(ReplicatedStorage.Shared.match.WaveProtocol)
local WaveReplicationPublisher = require(script.Parent.Parent.ProductionServerWaves.WaveReplicationPublisher)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:wave-publisher-test"
local ENEMY_EPOCH = 7
local MAP_ID = "map:wave-publisher-test"
local DIFFICULTY_ID = "difficulty:wave-publisher-test"
local TOTAL_WAVES = 2

local ERROR_FIELDS: { [string]: boolean } = table.freeze({
	code = true,
	operation = true,
})

local function counts(totalScheduled: number, spawned: number, leaked: number, otherwiseResolved: number): any
	return {
		totalScheduled = totalScheduled,
		pending = totalScheduled - spawned,
		spawned = spawned,
		alive = spawned - leaked - otherwiseResolved,
		leaked = leaked,
		otherwiseResolved = otherwiseResolved,
	}
end

local function snapshot(waveRevision: number): any
	return {
		matchId = MATCH_ID,
		enemyEpoch = ENEMY_EPOCH,
		mapId = MAP_ID,
		difficultyId = DIFFICULTY_ID,
		state = "Running",
		waveRevision = waveRevision,
		currentWaveNumber = 1,
		totalWaves = TOTAL_WAVES,
		currentWaveId = "wave:publisher-one",
		bossKind = "None",
		timerPhase = "WaveDeadline",
		waveStartedServerTime = 10,
		deadlineServerTime = 30,
		intermissionEndsServerTime = 0,
		skipAvailableServerTime = 15,
		finiteCompleteServerTime = 0,
		currentCounts = counts(2, 0, 0, 0),
		aggregateCounts = counts(2, 0, 0, 0),
		skipState = {
			available = false,
			activeParticipantCount = 0,
			yesVoteCount = 0,
			requiredVoteCount = 0,
			quorumPending = false,
		},
	}
end

local function expectSuccess(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return result.value
end

local function expectFailure(
	assertions: Assertions,
	result: any,
	code: WaveReplicationPublisher.ErrorCode,
	operation: WaveReplicationPublisher.Operation
): any
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local errorValue = result.error
	assertions.isTrue(table.isfrozen(errorValue))
	assertions.equal(errorValue.code, code)
	assertions.equal(errorValue.operation, operation)
	local fieldCount = 0
	for fieldName in next, errorValue do
		fieldCount += 1
		assertions.isTrue(ERROR_FIELDS[fieldName] == true)
	end
	assertions.equal(fieldCount, 2)
	return errorValue
end

local function recipient(token: unknown, userId: number): { [string]: unknown }
	return {
		recipient = token,
		userId = userId,
	}
end

local function makeToken(userId: number): any
	return {
		userId = userId,
		alive = true,
	}
end

local function makeEnvironment(): any
	local environment: any = {
		recipients = {},
		sends = {},
		providerMode = "value",
		senderBehavior = nil,
		providerCalls = 0,
		recipientValidationCalls = 0,
	}
	environment.dependencies = {
		sender = function(recipientValue: unknown, snapshotValue: WaveProtocol.WaveSnapshot): boolean
			table.insert(environment.sends, {
				recipient = recipientValue,
				snapshot = snapshotValue,
			})
			if environment.senderBehavior ~= nil then
				return environment.senderBehavior(recipientValue, snapshotValue)
			end
			return true
		end,
		getRecipients = function(): unknown
			environment.providerCalls += 1
			if environment.providerMode == "throw" then
				error("PRIVATE_PROVIDER_FAILURE", 0)
			elseif environment.providerMode == "yield" then
				coroutine.yield()
			elseif environment.providerMode == "custom" then
				return environment.providerValue
			end
			return environment.recipients
		end,
	}
	environment.recipientValidator = function(recipientValue: unknown, userId: number): boolean
		environment.recipientValidationCalls += 1
		return type(recipientValue) == "table"
			and (recipientValue :: any).alive == true
			and (recipientValue :: any).userId == userId
	end
	return environment
end

local function newPublisher(assertions: Assertions, environment: any, maxPublications: number?): any
	local constructor = WaveReplicationPublisher.newForTests
	assertions.isNotNil(constructor)
	local publisher = expectSuccess(
		assertions,
		(constructor :: any)(MATCH_ID, ENEMY_EPOCH, MAP_ID, DIFFICULTY_ID, TOTAL_WAVES, environment.dependencies, {
			maxPublications = maxPublications or WaveReplicationPublisher.MAX_PUBLICATIONS,
			recipientValidator = environment.recipientValidator,
		})
	)
	assertions.isTrue(table.isfrozen(publisher))
	return publisher
end

return TestHarness.suite("bounded full-state wave replication publisher", {
	TestHarness.case("exports exact bounds and rejects malformed construction", function(assertions)
		assertions.equal(WaveReplicationPublisher.MAX_BROADCAST_RECIPIENTS, 4)
		assertions.equal(WaveReplicationPublisher.MAX_PUBLICATIONS, 16_384)
		assertions.isTrue(table.isfrozen(WaveReplicationPublisher))
		assertions.isNotNil(WaveReplicationPublisher.newForTests)

		local environment = makeEnvironment()
		expectFailure(
			assertions,
			WaveReplicationPublisher.new(nil, ENEMY_EPOCH, MAP_ID, DIFFICULTY_ID, TOTAL_WAVES, environment.dependencies),
			"INVALID_ARGUMENT",
			"new"
		)
		expectFailure(
			assertions,
			WaveReplicationPublisher.new(MATCH_ID, 0, MAP_ID, DIFFICULTY_ID, TOTAL_WAVES, environment.dependencies),
			"INVALID_ARGUMENT",
			"new"
		)
		expectFailure(
			assertions,
			WaveReplicationPublisher.new(MATCH_ID, ENEMY_EPOCH, "map:wrong", DIFFICULTY_ID, 0, environment.dependencies),
			"INVALID_ARGUMENT",
			"new"
		)
		expectFailure(
			assertions,
			WaveReplicationPublisher.new(MATCH_ID, ENEMY_EPOCH, MAP_ID, DIFFICULTY_ID, TOTAL_WAVES, {
				sender = function() end,
				getRecipients = function() end,
				extra = true,
			}),
			"INVALID_ARGUMENT",
			"new"
		)
		local constructor = WaveReplicationPublisher.newForTests :: any
		expectFailure(
			assertions,
			constructor(MATCH_ID, ENEMY_EPOCH, MAP_ID, DIFFICULTY_ID, TOTAL_WAVES, environment.dependencies, {
				maxPublications = WaveReplicationPublisher.MAX_PUBLICATIONS + 1,
				recipientValidator = environment.recipientValidator,
			}),
			"INVALID_ARGUMENT",
			"new"
		)
	end),

	TestHarness.case("publishes one detached canonical snapshot to fresh sorted recipients", function(assertions)
		local environment = makeEnvironment()
		local negative = makeToken(-4)
		local positive = makeToken(11)
		environment.recipients = {
			recipient(positive, 11),
			recipient(negative, -4),
		}
		local publisher = newPublisher(assertions, environment)
		local authored = snapshot(1)
		assertions.isTrue(expectSuccess(assertions, publisher:queueSnapshot(authored)))
		authored.currentWaveId = "wave:mutated"
		authored.currentCounts.totalScheduled = 4_096

		local outcome = expectSuccess(assertions, publisher:flush(1))
		assertions.isTrue(outcome.published)
		assertions.equal(outcome.passOrdinal, 1)
		assertions.equal(outcome.waveRevision, 1)
		assertions.equal(outcome.recipientCount, 2)
		assertions.equal(outcome.senderFailureCount, 0)
		assertions.equal(environment.providerCalls, 1)
		assertions.equal(#environment.sends, 2)
		assertions.equal(environment.sends[1].recipient, negative)
		assertions.equal(environment.sends[2].recipient, positive)
		local sent = environment.sends[1].snapshot
		assertions.equal(environment.sends[2].snapshot, sent)
		assertions.isTrue(table.isfrozen(sent))
		assertions.isTrue(table.isfrozen(sent.currentCounts))
		assertions.isTrue(table.isfrozen(sent.skipState))
		assertions.equal(sent.currentWaveId, "wave:publisher-one")
		assertions.equal(sent.currentCounts.totalScheduled, 2)
		assertions.isTrue(WaveProtocol.validateWaveSnapshot(sent).ok)

		local metrics = publisher:getMetrics()
		assertions.isTrue(table.isfrozen(metrics))
		assertions.equal(metrics.publicationCount, 1)
		assertions.equal(metrics.flushCount, 1)
		assertions.equal(metrics.queueCount, 1)
		assertions.equal(metrics.senderCallCount, 2)
		assertions.isFalse(metrics.hasPending)
		assertions.equal(metrics.latestWaveRevision, 1)
		assertions.equal(metrics.lastPassOrdinal, 1)
		assertions.isTrue(metrics.retainsSender)
		assertions.isTrue(metrics.retainsRecipientProvider)
	end),

	TestHarness.case("coalesces every pre-pass semantic change into only the newest full state", function(assertions)
		local environment = makeEnvironment()
		local publisher = newPublisher(assertions, environment)
		assertions.isTrue(expectSuccess(assertions, publisher:queueSnapshot(snapshot(1))))
		assertions.isTrue(expectSuccess(assertions, publisher:queueSnapshot(snapshot(2))))
		assertions.isTrue(expectSuccess(assertions, publisher:queueSnapshot(snapshot(5))))
		assertions.isFalse(expectSuccess(assertions, publisher:queueSnapshot(snapshot(5))))
		local metrics = publisher:getMetrics()
		assertions.equal(metrics.queueCount, 3)
		assertions.equal(metrics.coalescedQueueCount, 2)
		assertions.equal(metrics.duplicateQueueCount, 1)
		assertions.equal(metrics.latestWaveRevision, 5)

		local outcome = expectSuccess(assertions, publisher:flush(1))
		assertions.isTrue(outcome.published)
		assertions.equal(outcome.waveRevision, 5)
		assertions.equal(environment.providerCalls, 1)
		assertions.equal(publisher:getMetrics().publicationCount, 1)
	end),

	TestHarness.case("adopts the current Enemy pass then enforces exactly one contiguous flush", function(assertions)
		local environment = makeEnvironment()
		local publisher = newPublisher(assertions, environment)
		local empty = expectSuccess(assertions, publisher:flush(73))
		assertions.isFalse(empty.published)
		assertions.isNil(empty.waveRevision)
		assertions.equal(environment.providerCalls, 0)

		assertions.isTrue(expectSuccess(assertions, publisher:queueSnapshot(snapshot(1))))
		local second = expectSuccess(assertions, publisher:flush(74))
		assertions.isTrue(second.published)
		assertions.equal(second.passOrdinal, 74)
		assertions.equal(publisher:getMetrics().flushCount, 2)

		local duplicateEnvironment = makeEnvironment()
		local duplicate = newPublisher(assertions, duplicateEnvironment)
		expectSuccess(assertions, duplicate:flush(73))
		expectFailure(assertions, duplicate:flush(73), "INVALID_PASS", "flush")
		assertions.isTrue(duplicate:getMetrics().faulted)

		local skippedEnvironment = makeEnvironment()
		local skipped = newPublisher(assertions, skippedEnvironment)
		expectSuccess(assertions, skipped:flush(73))
		expectFailure(assertions, skipped:flush(75), "INVALID_PASS", "flush")
		assertions.isTrue(skipped:getMetrics().faulted)
	end),

	TestHarness.case("faults closed on malformed snapshots and pinned identity changes", function(assertions)
		local malformedEnvironment = makeEnvironment()
		local malformed = newPublisher(assertions, malformedEnvironment)
		local impossible = snapshot(1)
		impossible.currentCounts.pending = 1
		expectFailure(assertions, malformed:queueSnapshot(impossible), "INVALID_SNAPSHOT", "queueSnapshot")
		assertions.isTrue(malformed:getMetrics().faulted)
		assertions.isFalse(malformed:getMetrics().hasPending)
		expectFailure(assertions, malformed:flush(1), "FAULTED", "flush")

		for _, fieldName in { "matchId", "enemyEpoch", "mapId", "difficultyId", "totalWaves" } do
			local environment = makeEnvironment()
			local publisher = newPublisher(assertions, environment)
			local changed = snapshot(1)
			if fieldName == "matchId" then
				changed.matchId = "match:wrong"
			elseif fieldName == "enemyEpoch" then
				changed.enemyEpoch = ENEMY_EPOCH + 1
			elseif fieldName == "mapId" then
				changed.mapId = "map:wrong"
			elseif fieldName == "difficultyId" then
				changed.difficultyId = "difficulty:wrong"
			else
				changed.totalWaves = TOTAL_WAVES + 1
			end
			expectFailure(assertions, publisher:queueSnapshot(changed), "WRONG_IDENTITY", "queueSnapshot")
			assertions.isTrue(publisher:getMetrics().faulted)
		end
	end),

	TestHarness.case("faults closed on missing stale or same-revision-mutated state", function(assertions)
		local firstEnvironment = makeEnvironment()
		local first = newPublisher(assertions, firstEnvironment)
		expectFailure(assertions, first:queueSnapshot(snapshot(2)), "INVALID_REVISION", "queueSnapshot")
		assertions.isTrue(first:getMetrics().faulted)

		local staleEnvironment = makeEnvironment()
		local stale = newPublisher(assertions, staleEnvironment)
		expectSuccess(assertions, stale:queueSnapshot(snapshot(1)))
		expectSuccess(assertions, stale:flush(1))
		expectSuccess(assertions, stale:queueSnapshot(snapshot(3)))
		expectFailure(assertions, stale:queueSnapshot(snapshot(2)), "INVALID_REVISION", "queueSnapshot")
		assertions.isTrue(stale:getMetrics().faulted)
		assertions.isFalse(stale:getMetrics().hasPending)

		local mutationEnvironment = makeEnvironment()
		local mutation = newPublisher(assertions, mutationEnvironment)
		expectSuccess(assertions, mutation:queueSnapshot(snapshot(1)))
		local changed = snapshot(1)
		changed.bossKind = "MiniBoss"
		expectFailure(assertions, mutation:queueSnapshot(changed), "INVALID_REVISION", "queueSnapshot")
		assertions.isTrue(mutation:getMetrics().faulted)
	end),

	TestHarness.case("contains each sender failure and irreversibly consumes the event", function(assertions)
		local environment = makeEnvironment()
		local tokens = {
			makeToken(1),
			makeToken(2),
			makeToken(3),
			makeToken(4),
		}
		environment.recipients = {
			recipient(tokens[4], 4),
			recipient(tokens[2], 2),
			recipient(tokens[1], 1),
			recipient(tokens[3], 3),
		}
		environment.senderBehavior = function(recipientValue: any): boolean
			if recipientValue.userId == 2 then
				error("PRIVATE_SEND_FAILURE", 0)
			elseif recipientValue.userId == 3 then
				coroutine.yield()
			elseif recipientValue.userId == 4 then
				return false
			end
			return true
		end
		local publisher = newPublisher(assertions, environment)
		expectSuccess(assertions, publisher:queueSnapshot(snapshot(1)))
		local outcome = expectSuccess(assertions, publisher:flush(1))
		assertions.equal(outcome.recipientCount, 4)
		assertions.equal(outcome.senderFailureCount, 3)
		assertions.equal(#environment.sends, 4)
		for index = 1, 4 do
			assertions.equal(environment.sends[index].recipient, tokens[index])
		end
		local metrics = publisher:getMetrics()
		assertions.equal(metrics.senderCallCount, 4)
		assertions.equal(metrics.senderFailureCount, 3)
		assertions.equal(metrics.publicationCount, 1)
		assertions.isFalse(metrics.hasPending)
		assertions.isFalse(metrics.faulted)
	end),

	TestHarness.case(
		"faults before sending for malformed stale duplicate or excessive recipients",
		function(assertions)
			local shared = makeToken(1)
			local variants = {
				{
					recipient(makeToken(1), 1),
					recipient(makeToken(2), 2),
					recipient(makeToken(3), 3),
					recipient(makeToken(4), 4),
					recipient(makeToken(5), 5),
				},
				{ recipient(shared, 1), recipient(shared, 1) },
				{ recipient(makeToken(1), 1), recipient(makeToken(1), 1) },
				{ { recipient = makeToken(1), userId = 1, extra = true } },
				{ recipient({ userId = 1, alive = false }, 1) },
				{ recipient(makeToken(1), 0) },
			}

			for _, records in variants do
				local environment = makeEnvironment()
				environment.recipients = records
				local publisher = newPublisher(assertions, environment)
				expectSuccess(assertions, publisher:queueSnapshot(snapshot(1)))
				expectFailure(assertions, publisher:flush(1), "INTERNAL_ERROR", "flush")
				assertions.equal(#environment.sends, 0)
				assertions.equal(publisher:getMetrics().publicationCount, 0)
				assertions.isTrue(publisher:getMetrics().faulted)
				assertions.isFalse(publisher:getMetrics().hasPending)
			end

			local environment = makeEnvironment()
			environment.providerValue = {
				[1] = recipient(makeToken(1), 1),
				extra = true,
			}
			environment.providerMode = "custom"
			local publisher = newPublisher(assertions, environment)
			expectSuccess(assertions, publisher:queueSnapshot(snapshot(1)))
			expectFailure(assertions, publisher:flush(1), "INTERNAL_ERROR", "flush")
			assertions.isTrue(publisher:getMetrics().faulted)
		end
	),

	TestHarness.case("faults once for throwing or yielding recipient providers", function(assertions)
		for _, mode in { "throw", "yield" } do
			local environment = makeEnvironment()
			environment.providerMode = mode
			local publisher = newPublisher(assertions, environment)
			expectSuccess(assertions, publisher:queueSnapshot(snapshot(1)))
			expectFailure(assertions, publisher:flush(1), "INTERNAL_ERROR", "flush")
			assertions.equal(environment.providerCalls, 1)
			assertions.equal(#environment.sends, 0)
			assertions.isTrue(publisher:getMetrics().faulted)
			expectFailure(assertions, publisher:flush(2), "FAULTED", "flush")
			assertions.equal(environment.providerCalls, 1)
		end
	end),

	TestHarness.case("the public constructor accepts only actual live Player recipients", function(assertions)
		local token = makeToken(1)
		local environment = makeEnvironment()
		environment.recipients = { recipient(token, 1) }
		local publisher = expectSuccess(
			assertions,
			WaveReplicationPublisher.new(
				MATCH_ID,
				ENEMY_EPOCH,
				MAP_ID,
				DIFFICULTY_ID,
				TOTAL_WAVES,
				environment.dependencies
			)
		)
		expectSuccess(assertions, publisher:queueSnapshot(snapshot(1)))
		expectFailure(assertions, publisher:flush(1), "INTERNAL_ERROR", "flush")
		assertions.equal(environment.recipientValidationCalls, 0)
		assertions.equal(#environment.sends, 0)
		assertions.isTrue(publisher:getMetrics().faulted)
	end),

	TestHarness.case("hard-stops at the lifetime publication cap without retaining a queue", function(assertions)
		local environment = makeEnvironment()
		local publisher = newPublisher(assertions, environment, 2)
		assertions.isTrue(expectSuccess(assertions, publisher:preflightPublication()))
		expectSuccess(assertions, publisher:queueSnapshot(snapshot(1)))
		expectSuccess(assertions, publisher:flush(1))
		expectSuccess(assertions, publisher:queueSnapshot(snapshot(2)))
		expectSuccess(assertions, publisher:flush(2))
		expectFailure(assertions, publisher:preflightPublication(), "CAPACITY_EXCEEDED", "preflightPublication")
		local metrics = publisher:getMetrics()
		assertions.equal(metrics.publicationCount, 2)
		assertions.equal(metrics.flushCount, 2)
		assertions.equal(metrics.latestWaveRevision, 2)
		assertions.isFalse(metrics.hasPending)
		assertions.isTrue(metrics.faulted)
		expectFailure(assertions, publisher:queueSnapshot(snapshot(3)), "FAULTED", "queueSnapshot")
	end),

	TestHarness.case("defers cleanup during a send and rejects callback re-entry", function(assertions)
		local environment = makeEnvironment()
		local first = makeToken(1)
		local second = makeToken(2)
		environment.recipients = { recipient(first, 1), recipient(second, 2) }
		local publisher = newPublisher(assertions, environment)
		local reentryResult: any = nil
		local cleanupResult: any = nil
		environment.senderBehavior = function(): boolean
			reentryResult = publisher:queueSnapshot(snapshot(2))
			cleanupResult = publisher:cleanup()
			return true
		end

		expectSuccess(assertions, publisher:queueSnapshot(snapshot(1)))
		expectFailure(assertions, publisher:flush(1), "CLEANED", "flush")
		expectFailure(assertions, reentryResult, "REENTRANT", "queueSnapshot")
		assertions.isFalse(expectSuccess(assertions, cleanupResult))
		assertions.equal(#environment.sends, 1)
		local metrics = publisher:getMetrics()
		assertions.isTrue(metrics.cleaned)
		assertions.equal(metrics.publicationCount, 0)
		assertions.equal(metrics.senderCallCount, 0)
		assertions.isFalse(metrics.retainsSender)
		assertions.isFalse(metrics.retainsRecipientProvider)
		assertions.isFalse(metrics.retainsTestRecipientValidator)
	end),

	TestHarness.case("cleans pending state dependencies and metrics idempotently", function(assertions)
		local environment = makeEnvironment()
		local publisher = newPublisher(assertions, environment)
		expectSuccess(assertions, publisher:queueSnapshot(snapshot(1)))
		assertions.isTrue(publisher:getMetrics().hasPending)
		assertions.isTrue(expectSuccess(assertions, publisher:cleanup()))
		local metrics = publisher:getMetrics()
		assertions.isTrue(metrics.cleaned)
		assertions.isFalse(metrics.hasPending)
		assertions.isNil(metrics.latestWaveRevision)
		assertions.isNil(metrics.lastPassOrdinal)
		assertions.equal(metrics.queueCount, 0)
		assertions.equal(metrics.coalescedQueueCount, 0)
		assertions.equal(metrics.duplicateQueueCount, 0)
		assertions.isFalse(metrics.retainsSender)
		assertions.isFalse(metrics.retainsRecipientProvider)
		assertions.isFalse(metrics.retainsTestRecipientValidator)
		assertions.isFalse(expectSuccess(assertions, publisher:cleanup()))
		expectFailure(assertions, publisher:flush(1), "CLEANED", "flush")
	end),
})
