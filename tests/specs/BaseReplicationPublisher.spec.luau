--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local BaseReplicationPublisher = require(script.Parent.Parent.ProductionServerBase.BaseReplicationPublisher)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:base-publisher-test"
local ENEMY_EPOCH = 7
local MAXIMUM_HEALTH = 100
local BASE_POSITION = Vector3.new(12, 4, -9)

local ERROR_FIELDS: { [string]: boolean } = table.freeze({
	code = true,
	operation = true,
})

local function snapshot(
	baseRevision: number,
	currentHealth: number,
	status: BaseProtocol.BaseStatus?,
	updatedServerTime: number?
): { [string]: unknown }
	return {
		matchId = MATCH_ID,
		enemyEpoch = ENEMY_EPOCH,
		mapId = "map:base-publisher-test",
		difficultyId = "difficulty:base-publisher-test",
		basePosition = BASE_POSITION,
		baseRevision = baseRevision,
		status = status or "Active",
		currentHealth = currentHealth,
		maximumHealth = MAXIMUM_HEALTH,
		lowHealth = currentHealth <= MAXIMUM_HEALTH / 4,
		initializedServerTime = 1,
		updatedServerTime = updatedServerTime or baseRevision,
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
	code: BaseReplicationPublisher.ErrorCode,
	operation: BaseReplicationPublisher.Operation
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
		sender = function(recipientValue: unknown, message: BaseProtocol.BaseReplicationMessage): boolean
			table.insert(environment.sends, {
				recipient = recipientValue,
				message = message,
			})
			if environment.senderBehavior ~= nil then
				return environment.senderBehavior(recipientValue, message)
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
	local constructor = BaseReplicationPublisher.newForTests
	assertions.isNotNil(constructor)
	local publisher = expectSuccess(
		assertions,
		(constructor :: any)(MATCH_ID, ENEMY_EPOCH, environment.dependencies, {
			maxPublications = maxPublications or BaseProtocol.MAX_LIFETIME_PUBLICATIONS,
			recipientValidator = environment.recipientValidator,
		})
	)
	assertions.isTrue(table.isfrozen(publisher))
	return publisher
end

return TestHarness.suite("bounded base replication publisher", {
	TestHarness.case("exports exact production bounds and rejects malformed construction", function(assertions)
		assertions.equal(BaseReplicationPublisher.MAX_BROADCAST_RECIPIENTS, 4)
		assertions.equal(BaseReplicationPublisher.MAX_LEAKS_PER_MESSAGE, 128)
		assertions.equal(BaseReplicationPublisher.MAX_LIFETIME_PUBLICATIONS, 4_098)
		assertions.isTrue(table.isfrozen(BaseReplicationPublisher))
		assertions.isNotNil(BaseReplicationPublisher.newForTests)

		expectFailure(assertions, BaseReplicationPublisher.new(nil, 1, {}), "INVALID_ARGUMENT", "new")
		expectFailure(assertions, BaseReplicationPublisher.new(MATCH_ID, 0, {}), "INVALID_ARGUMENT", "new")
		expectFailure(assertions, BaseReplicationPublisher.new(MATCH_ID, 1, {}), "INVALID_ARGUMENT", "new")
		expectFailure(
			assertions,
			BaseReplicationPublisher.new(MATCH_ID, 1, {
				sender = function() end,
				getRecipients = function() end,
				extra = true,
			}),
			"INVALID_ARGUMENT",
			"new"
		)

		local environment = makeEnvironment()
		local constructor = BaseReplicationPublisher.newForTests :: any
		expectFailure(
			assertions,
			constructor(MATCH_ID, ENEMY_EPOCH, environment.dependencies, {
				maxPublications = 0,
				recipientValidator = environment.recipientValidator,
			}),
			"INVALID_ARGUMENT",
			"new"
		)
	end),

	TestHarness.case("publishes one detached canonical state to sorted live recipients", function(assertions)
		local environment = makeEnvironment()
		local negative = makeToken(-4)
		local positive = makeToken(11)
		environment.recipients = {
			recipient(positive, 11),
			recipient(negative, -4),
		}
		local publisher = newPublisher(assertions, environment)
		local authored = snapshot(1, 100)
		local outcome = expectSuccess(assertions, publisher:publishState(authored))
		assertions.isTrue(table.isfrozen(outcome))
		assertions.isTrue(outcome.published)
		assertions.equal(outcome.kind, "State")
		assertions.equal(outcome.recipientCount, 2)
		assertions.equal(outcome.senderFailureCount, 0)
		assertions.equal(environment.providerCalls, 1)
		assertions.equal(#environment.sends, 2)
		assertions.equal(environment.sends[1].recipient, negative)
		assertions.equal(environment.sends[2].recipient, positive)
		local message = environment.sends[1].message
		assertions.equal(environment.sends[2].message, message)
		assertions.isTrue(table.isfrozen(message))
		assertions.isTrue(table.isfrozen(message.snapshot))
		assertions.notEqual(message.snapshot, authored)
		assertions.isTrue(BaseProtocol.validateBaseReplicationMessage(message).ok)

		authored.currentHealth = 1
		authored.baseRevision = 99
		assertions.equal(message.snapshot.currentHealth, 100)
		assertions.equal(message.snapshot.baseRevision, 1)

		local metrics = publisher:getMetrics()
		assertions.isTrue(table.isfrozen(metrics))
		assertions.equal(metrics.publicationCount, 1)
		assertions.equal(metrics.flushCount, 1)
		assertions.equal(metrics.stateQueueCount, 1)
		assertions.equal(metrics.senderCallCount, 2)
		assertions.isFalse(metrics.hasPending)
		assertions.equal(metrics.latestBaseRevision, 1)
		assertions.isTrue(metrics.retainsSender)
		assertions.isTrue(metrics.retainsRecipientProvider)
	end),

	TestHarness.case("keeps only the latest state and suppresses an exact duplicate", function(assertions)
		local environment = makeEnvironment()
		local publisher = newPublisher(assertions, environment)
		assertions.isTrue(expectSuccess(assertions, publisher:queueState(snapshot(1, 100))))
		assertions.isTrue(expectSuccess(assertions, publisher:queueState(snapshot(2, 100))))
		assertions.equal(publisher:getMetrics().stateQueueCount, 2)
		assertions.equal(publisher:getMetrics().latestBaseRevision, 2)

		local flushed = expectSuccess(assertions, publisher:flush())
		assertions.isTrue(flushed.published)
		assertions.equal(flushed.kind, "State")
		assertions.equal(flushed.recipientCount, 0)
		assertions.equal(publisher:getMetrics().publicationCount, 1)

		assertions.isFalse(expectSuccess(assertions, publisher:queueState(snapshot(2, 100))))
		local empty = expectSuccess(assertions, publisher:flush())
		assertions.isFalse(empty.published)
		assertions.isNil(empty.kind)
		assertions.equal(environment.providerCalls, 1)
		assertions.equal(publisher:getMetrics().publicationCount, 1)
	end),

	TestHarness.case("coalesces sequential damage and lets damage win over later state", function(assertions)
		local environment = makeEnvironment()
		local token = makeToken(8)
		environment.recipients = { recipient(token, 8) }
		local publisher = newPublisher(assertions, environment)
		expectSuccess(assertions, publisher:publishState(snapshot(1, 100)))
		table.clear(environment.sends)

		assertions.isTrue(expectSuccess(assertions, publisher:queueDamage(snapshot(2, 90), 10, 2, false)))
		assertions.isTrue(expectSuccess(assertions, publisher:queueDamage(snapshot(3, 70), 20, 3, false)))
		assertions.isTrue(expectSuccess(assertions, publisher:queueState(snapshot(4, 70))))
		local metrics = publisher:getMetrics()
		assertions.equal(metrics.pendingKind, "Damage")
		assertions.equal(metrics.damageQueueCount, 2)
		assertions.equal(metrics.coalescedDamageCount, 1)

		local outcome = expectSuccess(assertions, publisher:flush())
		assertions.equal(outcome.kind, "Damage")
		assertions.equal(#environment.sends, 1)
		local damage = environment.sends[1].message
		assertions.equal(damage.kind, "Damage")
		assertions.equal(damage.snapshot.baseRevision, 4)
		assertions.equal((damage :: any).appliedDamage, 30)
		assertions.equal((damage :: any).leakCount, 5)
		assertions.isFalse((damage :: any).lowHealthCrossed)
		assertions.isTrue(BaseProtocol.validateBaseReplicationMessage(damage).ok)
	end),

	TestHarness.case("preserves one textual low-health crossing across a damage aggregate", function(assertions)
		local environment = makeEnvironment()
		local token = makeToken(5)
		environment.recipients = { recipient(token, 5) }
		local publisher = newPublisher(assertions, environment)
		expectSuccess(assertions, publisher:publishState(snapshot(1, 30)))
		table.clear(environment.sends)
		assertions.isTrue(expectSuccess(assertions, publisher:queueDamage(snapshot(2, 25), 5, 1, true)))
		assertions.isTrue(expectSuccess(assertions, publisher:queueDamage(snapshot(3, 20), 5, 1, false)))
		expectSuccess(assertions, publisher:flush())
		local message = environment.sends[1].message :: any
		assertions.equal(message.kind, "Damage")
		assertions.equal(message.appliedDamage, 10)
		assertions.equal(message.leakCount, 2)
		assertions.isTrue(message.lowHealthCrossed)

		expectFailure(assertions, publisher:queueDamage(snapshot(4, 15), 5, 1, true), "INVALID_DAMAGE", "queueDamage")
		assertions.isTrue(expectSuccess(assertions, publisher:queueDamage(snapshot(4, 15), 5, 1, false)))
	end),

	TestHarness.case("rejects stale identity mutation and invalid damage without queue rollback", function(assertions)
		local environment = makeEnvironment()
		local publisher = newPublisher(assertions, environment)
		expectSuccess(assertions, publisher:publishState(snapshot(1, 100)))

		local wrongMatch = snapshot(2, 90)
		wrongMatch.matchId = "match:wrong"
		expectFailure(assertions, publisher:queueState(wrongMatch), "WRONG_IDENTITY", "queueState")
		local wrongEpoch = snapshot(2, 90)
		wrongEpoch.enemyEpoch = ENEMY_EPOCH + 1
		expectFailure(assertions, publisher:queueState(wrongEpoch), "WRONG_IDENTITY", "queueState")

		local changedMap = snapshot(2, 90)
		changedMap.mapId = "map:wrong"
		expectFailure(assertions, publisher:queueState(changedMap), "INVALID_SNAPSHOT", "queueState")
		local increased = snapshot(2, 100)
		increased.maximumHealth = 101
		expectFailure(assertions, publisher:queueState(increased), "INVALID_SNAPSHOT", "queueState")
		local sameRevisionMutation = snapshot(1, 99)
		expectFailure(assertions, publisher:queueState(sameRevisionMutation), "INVALID_SNAPSHOT", "queueState")

		expectFailure(assertions, publisher:queueDamage(snapshot(2, 90), 0, 1, false), "INVALID_DAMAGE", "queueDamage")
		expectFailure(assertions, publisher:queueDamage(snapshot(2, 90), 9, 1, false), "INVALID_DAMAGE", "queueDamage")
		expectFailure(assertions, publisher:queueDamage(snapshot(2, 90), 10, 0, false), "INVALID_DAMAGE", "queueDamage")
		assertions.isTrue(expectSuccess(assertions, publisher:queueDamage(snapshot(2, 90), 10, 1, false)))
		expectFailure(
			assertions,
			publisher:queueDamage(snapshot(3, 80), 10, BaseProtocol.MAX_LEAKS_PER_MESSAGE, false),
			"INVALID_DAMAGE",
			"queueDamage"
		)
		local metrics = publisher:getMetrics()
		assertions.equal(metrics.pendingKind, "Damage")
		assertions.equal(metrics.latestBaseRevision, 2)
		assertions.equal(metrics.damageQueueCount, 1)
	end),

	TestHarness.case("contains each failed sender once and continues in UserId order", function(assertions)
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
		local outcome = expectSuccess(assertions, publisher:publishState(snapshot(1, 100)))
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
		assertions.isFalse(metrics.faulted)
	end),

	TestHarness.case("faults closed for malformed duplicate stale or excessive recipient sets", function(assertions)
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
			expectFailure(assertions, publisher:publishState(snapshot(1, 100)), "INTERNAL_ERROR", "publishState")
			assertions.equal(#environment.sends, 0)
			assertions.isTrue(publisher:getMetrics().faulted)
			assertions.isFalse(publisher:getMetrics().hasPending)
			expectFailure(assertions, publisher:flush(), "FAULTED", "flush")
		end

		local environment = makeEnvironment()
		environment.providerValue = {
			[1] = recipient(makeToken(1), 1),
			extra = true,
		}
		environment.providerMode = "custom"
		local publisher = newPublisher(assertions, environment)
		expectFailure(assertions, publisher:publishState(snapshot(1, 100)), "INTERNAL_ERROR", "publishState")
		assertions.isTrue(publisher:getMetrics().faulted)
	end),

	TestHarness.case("faults once for throwing or yielding recipient providers", function(assertions)
		for _, mode in { "throw", "yield" } do
			local environment = makeEnvironment()
			environment.providerMode = mode
			local publisher = newPublisher(assertions, environment)
			expectFailure(assertions, publisher:publishState(snapshot(1, 100)), "INTERNAL_ERROR", "publishState")
			assertions.equal(environment.providerCalls, 1)
			assertions.equal(#environment.sends, 0)
			assertions.isTrue(publisher:getMetrics().faulted)
			expectFailure(assertions, publisher:publishState(snapshot(2, 100)), "FAULTED", "publishState")
			assertions.equal(environment.providerCalls, 1)
		end
	end),

	TestHarness.case("the public constructor accepts only actual live Player recipients", function(assertions)
		local token = makeToken(1)
		local environment = makeEnvironment()
		environment.recipients = { recipient(token, 1) }
		local publisher =
			expectSuccess(assertions, BaseReplicationPublisher.new(MATCH_ID, ENEMY_EPOCH, environment.dependencies))
		expectFailure(assertions, publisher:publishState(snapshot(1, 100)), "INTERNAL_ERROR", "publishState")
		assertions.equal(environment.recipientValidationCalls, 0)
		assertions.equal(#environment.sends, 0)
		assertions.isTrue(publisher:getMetrics().faulted)
	end),

	TestHarness.case("hard-stops at the publication cap without retaining a new queue", function(assertions)
		local environment = makeEnvironment()
		local publisher = newPublisher(assertions, environment, 2)
		assertions.isTrue(expectSuccess(assertions, publisher:preflightPublication()))
		expectSuccess(assertions, publisher:publishState(snapshot(1, 100)))
		expectSuccess(assertions, publisher:publishState(snapshot(2, 100)))
		expectFailure(assertions, publisher:preflightPublication(), "CAPACITY_EXCEEDED", "preflightPublication")
		expectFailure(assertions, publisher:queueState(snapshot(3, 100)), "CAPACITY_EXCEEDED", "queueState")
		local metrics = publisher:getMetrics()
		assertions.equal(metrics.publicationCount, 2)
		assertions.equal(metrics.flushCount, 2)
		assertions.equal(metrics.latestBaseRevision, 2)
		assertions.isFalse(metrics.hasPending)
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
			reentryResult = publisher:queueState(snapshot(2, 100))
			cleanupResult = publisher:cleanup()
			return true
		end

		expectFailure(assertions, publisher:publishState(snapshot(1, 100)), "CLEANED", "publishState")
		expectFailure(assertions, reentryResult, "REENTRANT", "queueState")
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

	TestHarness.case("cleans pending state callbacks and metrics idempotently", function(assertions)
		local environment = makeEnvironment()
		local publisher = newPublisher(assertions, environment)
		expectSuccess(assertions, publisher:queueState(snapshot(1, 100)))
		assertions.isTrue(publisher:getMetrics().hasPending)
		assertions.isTrue(expectSuccess(assertions, publisher:cleanup()))
		local metrics = publisher:getMetrics()
		assertions.isTrue(metrics.cleaned)
		assertions.isFalse(metrics.hasPending)
		assertions.isNil(metrics.latestBaseRevision)
		assertions.equal(metrics.stateQueueCount, 0)
		assertions.equal(metrics.damageQueueCount, 0)
		assertions.equal(metrics.coalescedDamageCount, 0)
		assertions.isFalse(metrics.retainsSender)
		assertions.isFalse(metrics.retainsRecipientProvider)
		assertions.isFalse(metrics.retainsTestRecipientValidator)
		assertions.isFalse(expectSuccess(assertions, publisher:cleanup()))
		expectFailure(assertions, publisher:flush(), "CLEANED", "flush")
	end),
})
