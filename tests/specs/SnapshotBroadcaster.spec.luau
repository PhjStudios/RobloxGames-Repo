--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local SnapshotBroadcaster = require(script.Parent.Parent.ProductionServerMatchReady.SnapshotBroadcaster)

type Assertions = TestHarness.Assertions

type Handle = {
	id: number,
	delay: number,
	callback: () -> (),
	cancelled: boolean,
}

local ERROR_FIELDS: { [string]: boolean } = table.freeze({
	code = true,
	operation = true,
})

local function participant(userId: number): { [string]: unknown }
	return {
		userId = userId,
		state = "Active",
		ready = false,
	}
end

local function snapshot(revision: number, userIds: { number }?): { [string]: unknown }
	local participants = {}
	for _, userId in userIds or {} do
		table.insert(participants, participant(userId))
	end
	return {
		matchId = "match:broadcaster-test",
		revision = revision,
		state = "ReadyCheck",
		deadlineServerTime = 45,
		participants = participants,
	}
end

local function recipient(token: unknown, userId: number): { [string]: unknown }
	return {
		recipient = token,
		userId = userId,
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
	code: SnapshotBroadcaster.ErrorCode,
	operation: SnapshotBroadcaster.Operation
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

local function makeEnvironment(): any
	local environment: any = {
		now = 0,
		clockMode = "value",
		scheduleMode = "value",
		cancelMode = "value",
		recipientsMode = "value",
		senderFailureLabels = {},
		onFaultThrows = false,
		recipients = {},
		handles = {},
		sends = {},
		clockCalls = 0,
		scheduleCalls = 0,
		cancelCalls = 0,
		recipientCalls = 0,
		faultCalls = 0,
	}

	environment.dependencies = {
		clock = function(): unknown
			environment.clockCalls += 1
			if environment.clockMode == "throw" then
				error("PRIVATE_CLOCK_FAILURE", 0)
			elseif environment.clockMode == "custom" then
				return environment.clockValue
			end
			return environment.now
		end,
		schedule = function(delaySeconds: number, callback: () -> ()): unknown
			environment.scheduleCalls += 1
			if environment.scheduleMode == "throw" then
				error("PRIVATE_SCHEDULE_FAILURE", 0)
			elseif environment.scheduleMode == "nil" then
				return nil
			end
			local handle: Handle = {
				id = #environment.handles + 1,
				delay = delaySeconds,
				callback = callback,
				cancelled = false,
			}
			table.insert(environment.handles, handle)
			if environment.scheduleMode == "synchronous" then
				callback()
			end
			return handle
		end,
		cancel = function(handleValue: unknown)
			environment.cancelCalls += 1
			if environment.cancelMode == "throw" then
				error("PRIVATE_CANCEL_FAILURE", 0)
			end
			(handleValue :: Handle).cancelled = true
		end,
		sender = function(token: unknown, canonicalSnapshot: any)
			local send = {
				recipient = token,
				snapshot = canonicalSnapshot,
			}
			table.insert(environment.sends, send)
			local label = if type(token) == "table" then (token :: any).label else nil
			if type(label) == "string" and environment.senderFailureLabels[label] == true then
				error("PRIVATE_SEND_FAILURE", 0)
			end
		end,
		getRecipients = function(): unknown
			environment.recipientCalls += 1
			if environment.recipientsMode == "throw" then
				error("PRIVATE_RECIPIENT_FAILURE", 0)
			end
			return environment.recipients
		end,
		onFault = function()
			environment.faultCalls += 1
			if environment.onFaultThrows then
				error("PRIVATE_FAULT_FAILURE", 0)
			end
		end,
	}
	return environment
end

local function newBroadcaster(assertions: Assertions, environment: any): any
	local broadcaster = expectSuccess(assertions, SnapshotBroadcaster.new(environment.dependencies))
	assertions.isTrue(table.isfrozen(broadcaster))
	return broadcaster
end

local function latestHandle(environment: any): Handle
	return environment.handles[#environment.handles]
end

local function expectKind(assertions: Assertions, result: any, kind: SnapshotBroadcaster.PublishKind)
	local outcome = expectSuccess(assertions, result)
	assertions.isTrue(table.isfrozen(outcome))
	assertions.equal(outcome.kind, kind)
end

return TestHarness.suite("bounded match snapshot broadcaster", {
	TestHarness.case("exports exact bounds and rejects malformed dependency records", function(assertions)
		assertions.equal(SnapshotBroadcaster.SNAPSHOT_MIN_INTERVAL_SECONDS, 0.1)
		assertions.equal(SnapshotBroadcaster.MAX_SNAPSHOT_EVENT_BATCHES, 64)
		assertions.equal(SnapshotBroadcaster.MAX_RECIPIENTS_PER_BATCH, 4)
		assertions.isTrue(table.isfrozen(SnapshotBroadcaster))

		expectFailure(assertions, SnapshotBroadcaster.new(nil), "INVALID_ARGUMENT", "new")
		expectFailure(assertions, SnapshotBroadcaster.new({}), "INVALID_ARGUMENT", "new")
		local environment = makeEnvironment()
		local missing = environment.dependencies
		missing.onFault = nil
		expectFailure(assertions, SnapshotBroadcaster.new(missing), "INVALID_ARGUMENT", "new")

		environment = makeEnvironment()
		environment.dependencies.extra = true
		expectFailure(assertions, SnapshotBroadcaster.new(environment.dependencies), "INVALID_ARGUMENT", "new")
		environment = makeEnvironment()
		setmetatable(environment.dependencies, {})
		expectFailure(assertions, SnapshotBroadcaster.new(environment.dependencies), "INVALID_ARGUMENT", "new")
	end),

	TestHarness.case("sends the first canonical snapshot immediately in sorted recipient order", function(assertions)
		local environment = makeEnvironment()
		local negative = { label = "negative" }
		local positive = { label = "positive" }
		environment.recipients = {
			recipient(positive, 4),
			recipient(negative, -3),
		}
		local broadcaster = newBroadcaster(assertions, environment)
		local authored = snapshot(1, { -3, 4 })
		expectKind(assertions, broadcaster:publish(authored), "Sent")

		assertions.equal(environment.clockCalls, 1)
		assertions.equal(environment.recipientCalls, 1)
		assertions.equal(#environment.sends, 2)
		assertions.equal(environment.sends[1].recipient, negative)
		assertions.equal(environment.sends[2].recipient, positive)
		local canonical = environment.sends[1].snapshot
		assertions.equal(environment.sends[2].snapshot, canonical)
		assertions.notEqual(canonical, authored)
		assertions.notEqual(canonical.participants, authored.participants)
		assertions.notEqual(canonical.participants[1], (authored.participants :: any)[1])
		assertions.isTrue(table.isfrozen(canonical))
		assertions.isTrue(table.isfrozen(canonical.participants))
		assertions.isTrue(table.isfrozen(canonical.participants[1]))

		authored.revision = 9
		(authored.participants :: any)[1].userId = -2
		assertions.equal(canonical.revision, 1)
		assertions.equal(canonical.participants[1].userId, -3)

		local stats = broadcaster:getStats()
		assertions.isTrue(table.isfrozen(stats))
		assertions.equal(stats.batchesSent, 1)
		assertions.equal(stats.senderCalls, 2)
		assertions.equal(stats.senderFailures, 0)
		assertions.isFalse(stats.hasPending)
		assertions.isFalse(stats.hasLiveFlush)
	end),

	TestHarness.case("coalesces to one latest snapshot and resolves recipients only when flushed", function(assertions)
		local environment = makeEnvironment()
		local firstToken = { label = "first" }
		local currentToken = { label = "current" }
		environment.recipients = { recipient(firstToken, 1) }
		local broadcaster = newBroadcaster(assertions, environment)
		expectKind(assertions, broadcaster:publish(snapshot(1, { 1, 2 })), "Sent")

		environment.now = 0.02
		expectKind(assertions, broadcaster:publish(snapshot(2, { 1, 2 })), "Queued")
		assertions.equal(environment.scheduleCalls, 1)
		assertions.isTrue(math.abs(latestHandle(environment).delay - 0.08) < 0.000001)
		environment.now = 0.03
		expectKind(assertions, broadcaster:publish(snapshot(3, { 1, 2 })), "Replaced")
		assertions.equal(environment.scheduleCalls, 1)
		assertions.equal(environment.recipientCalls, 1)
		assertions.equal(#environment.sends, 1)

		environment.recipients = { recipient(currentToken, 2) }
		environment.now = 0.2
		latestHandle(environment).callback()
		assertions.equal(environment.recipientCalls, 2)
		assertions.equal(#environment.sends, 2)
		assertions.equal(environment.sends[2].recipient, currentToken)
		assertions.equal(environment.sends[2].snapshot.revision, 3)
		local stats = broadcaster:getStats()
		assertions.equal(stats.batchesSent, 2)
		assertions.isFalse(stats.hasPending)
		assertions.isFalse(stats.hasLiveFlush)
		assertions.equal(environment.faultCalls, 0)
	end),

	TestHarness.case("reschedules an early flush only for the remaining interval", function(assertions)
		local environment = makeEnvironment()
		environment.now = 10
		environment.recipients = {}
		local broadcaster = newBroadcaster(assertions, environment)
		expectKind(assertions, broadcaster:publish(snapshot(1)), "Sent")
		environment.now = 10.01
		expectKind(assertions, broadcaster:publish(snapshot(2)), "Queued")
		local firstHandle = latestHandle(environment)

		environment.now = 10.04
		firstHandle.callback()
		assertions.equal(environment.scheduleCalls, 2)
		local replacementHandle = latestHandle(environment)
		assertions.notEqual(replacementHandle, firstHandle)
		assertions.isTrue(math.abs(replacementHandle.delay - 0.06) < 0.000001)
		assertions.equal(broadcaster:getStats().batchesSent, 1)

		firstHandle.callback()
		assertions.equal(environment.scheduleCalls, 2)
		environment.now = 10.2
		replacementHandle.callback()
		assertions.equal(broadcaster:getStats().batchesSent, 2)
		assertions.equal(environment.scheduleCalls, 2)
		assertions.equal(environment.faultCalls, 0)
	end),

	TestHarness.case("hard-stops at sixty-four lifetime batches without hiding invalid input", function(assertions)
		local environment = makeEnvironment()
		environment.recipients = {}
		local broadcaster = newBroadcaster(assertions, environment)
		for revision = 1, SnapshotBroadcaster.MAX_SNAPSHOT_EVENT_BATCHES do
			environment.now = revision
			expectKind(assertions, broadcaster:publish(snapshot(revision)), "Sent")
		end
		assertions.equal(broadcaster:getStats().batchesSent, 64)
		assertions.equal(environment.recipientCalls, 64)
		local clockCalls = environment.clockCalls
		expectKind(assertions, broadcaster:publish(snapshot(65)), "BudgetExhausted")
		assertions.equal(environment.clockCalls, clockCalls)
		assertions.equal(environment.recipientCalls, 64)
		assertions.isFalse(broadcaster:getStats().hasPending)

		local invalid = snapshot(66)
		invalid.deadlineServerTime = nil
		expectFailure(assertions, broadcaster:publish(invalid), "INVALID_SNAPSHOT", "publish")
	end),

	TestHarness.case("accepts at most four current sorted unique in-snapshot recipients", function(assertions)
		local environment = makeEnvironment()
		local tokens = {
			{ label = "one" },
			{ label = "two" },
			{ label = "three" },
			{ label = "four" },
		}
		environment.recipients = {
			recipient(tokens[4], 4),
			recipient(tokens[2], 2),
			recipient(tokens[1], 1),
			recipient(tokens[3], 3),
		}
		local broadcaster = newBroadcaster(assertions, environment)
		expectKind(assertions, broadcaster:publish(snapshot(1, { 1, 2, 3, 4 })), "Sent")
		assertions.equal(#environment.sends, 4)
		for index = 1, 4 do
			assertions.equal(environment.sends[index].recipient, tokens[index])
		end
		assertions.equal(broadcaster:getStats().senderCalls, 4)
	end),

	TestHarness.case("faults once for malformed excessive duplicate or unknown recipients", function(assertions)
		local token = { label = "shared" }
		local variants = {
			{
				recipient({ label = "1" }, 1),
				recipient({ label = "2" }, 2),
				recipient({ label = "3" }, 3),
				recipient({ label = "4" }, 4),
				recipient({ label = "5" }, 5),
			},
			{
				recipient({ label = "first" }, 1),
				recipient({ label = "duplicate-id" }, 1),
			},
			{ recipient({ label = "unknown" }, 99) },
			{
				recipient(token, 1),
				recipient(token, 2),
			},
			{ { recipient = token, userId = 1, extra = true } },
		}

		for _, recipients in variants do
			local environment = makeEnvironment()
			environment.recipients = recipients
			environment.onFaultThrows = true
			local broadcaster = newBroadcaster(assertions, environment)
			expectFailure(assertions, broadcaster:publish(snapshot(1, { 1, 2, 3, 4 })), "INTERNAL_ERROR", "publish")
			assertions.equal(environment.faultCalls, 1)
			assertions.equal(#environment.sends, 0)
			assertions.isTrue(broadcaster:getStats().faulted)
			expectFailure(assertions, broadcaster:publish(snapshot(2)), "UNAVAILABLE", "publish")
			assertions.equal(environment.faultCalls, 1)
		end

		local environment = makeEnvironment()
		environment.recipientsMode = "throw"
		local broadcaster = newBroadcaster(assertions, environment)
		expectFailure(assertions, broadcaster:publish(snapshot(1)), "INTERNAL_ERROR", "publish")
		assertions.equal(environment.faultCalls, 1)
	end),

	TestHarness.case("contains individual sender failures without retries or broadcaster faults", function(assertions)
		local environment = makeEnvironment()
		local tokens = {
			{ label = "one" },
			{ label = "two" },
			{ label = "three" },
			{ label = "four" },
		}
		environment.senderFailureLabels.two = true
		environment.senderFailureLabels.four = true
		environment.recipients = {
			recipient(tokens[1], 1),
			recipient(tokens[2], 2),
			recipient(tokens[3], 3),
			recipient(tokens[4], 4),
		}
		local broadcaster = newBroadcaster(assertions, environment)
		expectKind(assertions, broadcaster:publish(snapshot(1, { 1, 2, 3, 4 })), "Sent")
		assertions.equal(#environment.sends, 4)
		local stats = broadcaster:getStats()
		assertions.equal(stats.batchesSent, 1)
		assertions.equal(stats.senderCalls, 4)
		assertions.equal(stats.senderFailures, 2)
		assertions.equal(environment.scheduleCalls, 0)
		assertions.equal(environment.faultCalls, 0)
		assertions.isFalse(stats.faulted)
	end),

	TestHarness.case("fails closed once for throwing nonfinite negative and backwards clocks", function(assertions)
		local clockModes = {
			{ mode = "throw" },
			{ mode = "custom", value = "zero" },
			{ mode = "custom", value = -1 },
			{ mode = "custom", value = math.huge },
			{ mode = "custom", value = -math.huge },
			{ mode = "custom", value = 0 / 0 },
		}
		for _, selected in clockModes do
			local environment = makeEnvironment()
			environment.clockMode = selected.mode
			environment.clockValue = selected.value
			local broadcaster = newBroadcaster(assertions, environment)
			expectFailure(assertions, broadcaster:publish(snapshot(1)), "INTERNAL_ERROR", "publish")
			assertions.equal(environment.faultCalls, 1)
			assertions.equal(environment.recipientCalls, 0)
			expectFailure(assertions, broadcaster:publish(snapshot(2)), "UNAVAILABLE", "publish")
			assertions.equal(environment.faultCalls, 1)
		end

		local environment = makeEnvironment()
		environment.now = 2
		local broadcaster = newBroadcaster(assertions, environment)
		expectKind(assertions, broadcaster:publish(snapshot(1)), "Sent")
		environment.now = 1
		expectFailure(assertions, broadcaster:publish(snapshot(2)), "INTERNAL_ERROR", "publish")
		assertions.equal(environment.faultCalls, 1)
		assertions.equal(broadcaster:getStats().batchesSent, 1)
	end),

	TestHarness.case(
		"fails closed for schedule and cancel anomalies including synchronous callbacks",
		function(assertions)
			for _, scheduleMode in { "throw", "nil", "synchronous" } do
				local environment = makeEnvironment()
				environment.scheduleMode = scheduleMode
				local broadcaster = newBroadcaster(assertions, environment)
				expectKind(assertions, broadcaster:publish(snapshot(1)), "Sent")
				environment.now = 0.01
				expectFailure(assertions, broadcaster:publish(snapshot(2)), "INTERNAL_ERROR", "publish")
				assertions.equal(environment.faultCalls, 1)
				assertions.isFalse(broadcaster:getStats().hasPending)
				assertions.isFalse(broadcaster:getStats().hasLiveFlush)
				if #environment.handles > 0 then
					latestHandle(environment).callback()
				end
				assertions.equal(broadcaster:getStats().batchesSent, 1)
				assertions.equal(environment.faultCalls, 1)
			end

			local environment = makeEnvironment()
			local broadcaster = newBroadcaster(assertions, environment)
			expectKind(assertions, broadcaster:publish(snapshot(1)), "Sent")
			environment.now = 0.01
			expectKind(assertions, broadcaster:publish(snapshot(2)), "Queued")
			environment.cancelMode = "throw"
			environment.now = 1
			expectFailure(assertions, broadcaster:publish(snapshot(3)), "INTERNAL_ERROR", "publish")
			assertions.equal(environment.faultCalls, 1)
			assertions.equal(broadcaster:getStats().batchesSent, 1)
			latestHandle(environment).callback()
			assertions.equal(broadcaster:getStats().batchesSent, 1)
		end
	),

	TestHarness.case("cleanup clears the sole timer slot counters and closures exactly once", function(assertions)
		local environment = makeEnvironment()
		local token = { label = "one" }
		environment.recipients = { recipient(token, 1) }
		local broadcaster = newBroadcaster(assertions, environment)
		expectKind(assertions, broadcaster:publish(snapshot(1, { 1 })), "Sent")
		environment.now = 0.01
		expectKind(assertions, broadcaster:publish(snapshot(2, { 1 })), "Queued")
		local staleCallback = latestHandle(environment).callback
		assertions.isTrue(expectSuccess(assertions, broadcaster:cleanup()))
		assertions.equal(environment.cancelCalls, 1)
		local stats = broadcaster:getStats()
		assertions.isTrue(stats.cleaned)
		assertions.equal(stats.batchesSent, 0)
		assertions.equal(stats.senderCalls, 0)
		assertions.equal(stats.senderFailures, 0)
		assertions.isFalse(stats.hasPending)
		assertions.isFalse(stats.hasLiveFlush)

		staleCallback()
		assertions.equal(#environment.sends, 1)
		assertions.equal(environment.recipientCalls, 1)
		assertions.equal(environment.faultCalls, 0)
		assertions.isFalse(expectSuccess(assertions, broadcaster:cleanup()))
		expectFailure(assertions, broadcaster:publish(snapshot(3)), "UNAVAILABLE", "publish")
		assertions.equal(environment.clockCalls, 2)
	end),

	TestHarness.case("reports cleanup cancellation failure once while leaving callbacks inert", function(assertions)
		local environment = makeEnvironment()
		local broadcaster = newBroadcaster(assertions, environment)
		expectKind(assertions, broadcaster:publish(snapshot(1)), "Sent")
		environment.now = 0.01
		expectKind(assertions, broadcaster:publish(snapshot(2)), "Queued")
		local staleCallback = latestHandle(environment).callback
		environment.cancelMode = "throw"
		expectFailure(assertions, broadcaster:cleanup(), "INTERNAL_ERROR", "cleanup")
		assertions.equal(environment.faultCalls, 1)
		staleCallback()
		assertions.equal(broadcaster:getStats().batchesSent, 0)
		assertions.equal(environment.faultCalls, 1)
		assertions.isFalse(expectSuccess(assertions, broadcaster:cleanup()))
	end),
})
