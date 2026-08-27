--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local MatchStateMachine = require(script.Parent.Parent.ProductionServerMatchLifecycle.MatchStateMachine)
local ParticipantRoster = require(script.Parent.Parent.ProductionServerMatchRoster.ParticipantRoster)
local ReadyCheckCoordinator = require(script.Parent.Parent.ProductionServerMatchReady.ReadyCheckCoordinator)

type Assertions = TestHarness.Assertions

type TimerHandle = {
	delaySeconds: number,
	callback: () -> (),
	cancelled: boolean,
}

type ClockState = {
	now: unknown,
	throws: boolean,
}

type Scheduler = {
	handles: { TimerHandle },
	scheduleCalls: number,
	cancelCalls: number,
	failScheduleAt: number?,
	failCancel: boolean,
	fireSynchronouslyAt: number?,
	schedule: (delaySeconds: number, callback: () -> ()) -> unknown,
	cancel: (handle: unknown) -> (),
}

type Runtime = {
	machine: any,
	roster: any,
	coordinator: any,
	clock: ClockState,
	scheduler: Scheduler,
	notifications: { any },
}

local MATCH_ID = "match:ready-check-spec"
local OTHER_MATCH_ID = "match:ready-check-other"

local function expectSuccess(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return result.value
end

local function expectError(assertions: Assertions, result: any, code: string, operation: string): any
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local errorValue = result.error
	assertions.isTrue(table.isfrozen(errorValue))
	assertions.equal(errorValue.code, code)
	assertions.equal(errorValue.operation, operation)

	local fieldCount = 0
	for fieldName in next, errorValue do
		fieldCount += 1
		assertions.isTrue(fieldName == "code" or fieldName == "operation")
	end
	assertions.equal(fieldCount, 2)
	return errorValue
end

local function makeScheduler(): Scheduler
	local scheduler = {} :: any
	scheduler.handles = {}
	scheduler.scheduleCalls = 0
	scheduler.cancelCalls = 0
	scheduler.failScheduleAt = nil
	scheduler.failCancel = false
	scheduler.fireSynchronouslyAt = nil
	scheduler.schedule = function(delaySeconds: number, callback: () -> ()): unknown
		scheduler.scheduleCalls += 1
		if scheduler.failScheduleAt == scheduler.scheduleCalls then
			error("PRIVATE_SCHEDULE_FAILURE", 0)
		end
		local handle: TimerHandle = {
			delaySeconds = delaySeconds,
			callback = callback,
			cancelled = false,
		}
		table.insert(scheduler.handles, handle)
		if scheduler.fireSynchronouslyAt == scheduler.scheduleCalls then
			callback()
		end
		return handle
	end
	scheduler.cancel = function(handleValue: unknown)
		scheduler.cancelCalls += 1
		if scheduler.failCancel then
			error("PRIVATE_CANCEL_FAILURE", 0)
		end
		local handle = handleValue :: TimerHandle
		handle.cancelled = true
	end
	return scheduler :: Scheduler
end

local function newRuntime(assertions: Assertions, onChanged: ((outcome: any) -> ())?): Runtime
	local machine = expectSuccess(assertions, MatchStateMachine.new(MATCH_ID))
	local roster = expectSuccess(assertions, ParticipantRoster.new())
	local clock: ClockState = {
		now = 100,
		throws = false,
	}
	local scheduler = makeScheduler()
	local notifications = {}
	local callback = onChanged or function(outcome: any)
		table.insert(notifications, outcome)
	end
	local coordinator = expectSuccess(
		assertions,
		ReadyCheckCoordinator.new({
			machine = machine,
			roster = roster,
			clock = function(): unknown
				if clock.throws then
					error("PRIVATE_CLOCK_FAILURE", 0)
				end
				return clock.now
			end,
			schedule = scheduler.schedule,
			cancel = scheduler.cancel,
			onChanged = callback,
		})
	)
	assertions.isTrue(table.isfrozen(coordinator))
	return {
		machine = machine,
		roster = roster,
		coordinator = coordinator,
		clock = clock,
		scheduler = scheduler,
		notifications = notifications,
	}
end

local function machineSnapshot(assertions: Assertions, runtime: Runtime): any
	return expectSuccess(assertions, runtime.machine:getSnapshot())
end

local function runtimeState(runtime: Runtime): string
	return runtime.machine:getState()
end

local function rosterSnapshot(assertions: Assertions, runtime: Runtime): { any }
	return expectSuccess(assertions, runtime.roster:getSnapshot())
end

local function touchMachine(assertions: Assertions, runtime: Runtime)
	local before = machineSnapshot(assertions, runtime)
	local after = expectSuccess(assertions, runtime.machine:touch(before.revision))
	assertions.equal(after.revision, before.revision + 1)
end

local function admit(assertions: Assertions, runtime: Runtime, connection: any, userId: number)
	local outcome = expectSuccess(assertions, runtime.roster:connect(connection, userId, "Loading"))
	assertions.isTrue(outcome.changed)
	touchMachine(assertions, runtime)
end

local function enter(assertions: Assertions, runtime: Runtime): any
	local outcome = expectSuccess(assertions, runtime.coordinator:enterReadyCheck())
	assertions.isTrue(table.isfrozen(outcome))
	return outcome
end

local function fire(handle: TimerHandle)
	handle.callback()
end

return TestHarness.suite("match ready check coordinator", {
	TestHarness.case("records the exact deadline and ReadyCheck entry revision with one timer", function(assertions)
		local runtime = newRuntime(assertions, nil)
		local first = {}
		local second = {}
		admit(assertions, runtime, first, 20)
		admit(assertions, runtime, second, 10)
		local beforeRevision = runtime.machine:getRevision()

		local outcome = enter(assertions, runtime)
		assertions.equal(outcome.state, "ReadyCheck")
		assertions.equal(outcome.revision, beforeRevision + 1)
		assertions.equal(outcome.deadlineServerTime, 145)
		assertions.equal(runtime.coordinator:getDeadlineServerTime(), 145)
		assertions.equal(runtime.coordinator:getEntryRevision(), outcome.revision)
		assertions.equal(runtime.scheduler.scheduleCalls, 1)
		assertions.equal(#runtime.scheduler.handles, 1)
		assertions.equal(runtime.scheduler.handles[1].delaySeconds, 45)
		assertions.equal(#runtime.notifications, 1)
		assertions.equal(runtime.notifications[1].revision, outcome.revision)
	end),

	TestHarness.case("accepts each authenticated participant once across the revision window", function(assertions)
		local runtime = newRuntime(assertions, nil)
		local first = {}
		local second = {}
		admit(assertions, runtime, first, 1)
		admit(assertions, runtime, second, 2)
		local readyCheck = enter(assertions, runtime)

		expectError(
			assertions,
			runtime.coordinator:submitReady(first, OTHER_MATCH_ID, readyCheck.revision),
			"STALE_REQUEST",
			"submitReady"
		)
		expectError(
			assertions,
			runtime.coordinator:submitReady(first, MATCH_ID, readyCheck.revision - 1),
			"STALE_REQUEST",
			"submitReady"
		)
		expectError(
			assertions,
			runtime.coordinator:submitReady(first, MATCH_ID, readyCheck.revision + 1),
			"STALE_REQUEST",
			"submitReady"
		)

		local accepted =
			expectSuccess(assertions, runtime.coordinator:submitReady(first, MATCH_ID, readyCheck.revision))
		assertions.equal(accepted.state, "ReadyCheck")
		assertions.equal(accepted.revision, readyCheck.revision + 1)
		expectError(
			assertions,
			runtime.coordinator:submitReady(first, MATCH_ID, readyCheck.revision),
			"DUPLICATE_REQUEST",
			"submitReady"
		)

		-- The peer's original ReadyCheck revision remains valid even after the
		-- first participant's acceptance advanced the global revision.
		local final = expectSuccess(assertions, runtime.coordinator:submitReady(second, MATCH_ID, readyCheck.revision))
		assertions.equal(final.state, "PreWave")
		assertions.equal(final.revision, readyCheck.revision + 3)
		assertions.isNil(final.deadlineServerTime)
		assertions.isNil(runtime.coordinator:getDeadlineServerTime())
		assertions.isNil(runtime.coordinator:getEntryRevision())
		assertions.equal(runtime.scheduler.cancelCalls, 1)
		assertions.isTrue(runtime.scheduler.handles[1].cancelled)

		local finalRevision = runtime.machine:getRevision()
		fire(runtime.scheduler.handles[1])
		assertions.equal(runtime.machine:getRevision(), finalRevision)
	end),

	TestHarness.case("denies untracked and inactive connections without exposing roster details", function(assertions)
		local runtime = newRuntime(assertions, nil)
		local connections = {}
		for userId = 1, 4 do
			local connection = {}
			connections[userId] = connection
			admit(assertions, runtime, connection, userId)
		end
		local excess = {}
		local excessOutcome = expectSuccess(assertions, runtime.roster:connect(excess, 5, "Loading"))
		assertions.equal(excessOutcome.kind, "UntrackedSpectator")
		local readyCheck = enter(assertions, runtime)

		expectError(
			assertions,
			runtime.coordinator:submitReady(excess, MATCH_ID, readyCheck.revision),
			"NOT_AUTHORIZED",
			"submitReady"
		)
		local disconnected = expectSuccess(assertions, runtime.roster:disconnect(connections[1]))
		assertions.equal(disconnected.state, "Disconnected")
		touchMachine(assertions, runtime)
		expectError(
			assertions,
			runtime.coordinator:submitReady(connections[1], MATCH_ID, readyCheck.revision),
			"NOT_AUTHORIZED",
			"submitReady"
		)
	end),

	TestHarness.case("recalculates the active threshold immediately after disconnect", function(assertions)
		local runtime = newRuntime(assertions, nil)
		local readyConnection = {}
		local leavingConnection = {}
		admit(assertions, runtime, readyConnection, 1)
		admit(assertions, runtime, leavingConnection, 2)
		local readyCheck = enter(assertions, runtime)
		expectSuccess(assertions, runtime.coordinator:submitReady(readyConnection, MATCH_ID, readyCheck.revision))

		expectSuccess(assertions, runtime.roster:disconnect(leavingConnection))
		touchMachine(assertions, runtime)
		local threshold = expectSuccess(assertions, runtime.coordinator:onRosterChanged())
		assertions.equal(threshold.state, "PreWave")
		assertions.isNil(threshold.deadlineServerTime)
		assertions.equal(runtime.scheduler.cancelCalls, 1)
		local participants = rosterSnapshot(assertions, runtime)
		assertions.equal(participants[1].state, "Active")
		assertions.isTrue(participants[1].ready)
		assertions.equal(participants[2].state, "Disconnected")
		assertions.isFalse(participants[2].ready)
	end),

	TestHarness.case("uses strict before-deadline acceptance and resolves at the exact boundary", function(assertions)
		local beforeRuntime = newRuntime(assertions, nil)
		local beforeFirst = {}
		local beforeSecond = {}
		admit(assertions, beforeRuntime, beforeFirst, 1)
		admit(assertions, beforeRuntime, beforeSecond, 2)
		local beforeEntry = enter(assertions, beforeRuntime)
		beforeRuntime.clock.now = 144.999
		local accepted = expectSuccess(
			assertions,
			beforeRuntime.coordinator:submitReady(beforeFirst, MATCH_ID, beforeEntry.revision)
		)
		assertions.equal(accepted.state, "ReadyCheck")

		local exactRuntime = newRuntime(assertions, nil)
		local exactConnection = {}
		admit(assertions, exactRuntime, exactConnection, 1)
		local exactEntry = enter(assertions, exactRuntime)
		exactRuntime.clock.now = 145
		expectError(
			assertions,
			exactRuntime.coordinator:submitReady(exactConnection, MATCH_ID, exactEntry.revision),
			"UNAVAILABLE",
			"submitReady"
		)
		assertions.equal(runtimeState(exactRuntime), "Closing")
		assertions.isNil(exactRuntime.coordinator:getDeadlineServerTime())

		local afterRuntime = newRuntime(assertions, nil)
		local afterConnection = {}
		admit(assertions, afterRuntime, afterConnection, 1)
		local afterEntry = enter(assertions, afterRuntime)
		afterRuntime.clock.now = 145.001
		expectError(
			assertions,
			afterRuntime.coordinator:submitReady(afterConnection, MATCH_ID, afterEntry.revision),
			"UNAVAILABLE",
			"submitReady"
		)
		assertions.equal(runtimeState(afterRuntime), "Closing")
	end),

	TestHarness.case("reschedules an early callback only for the remaining duration", function(assertions)
		local runtime = newRuntime(assertions, nil)
		enter(assertions, runtime)
		local first = runtime.scheduler.handles[1]
		runtime.clock.now = 144.999
		fire(first)
		assertions.equal(runtimeState(runtime), "ReadyCheck")
		assertions.equal(runtime.scheduler.scheduleCalls, 2)
		assertions.equal(runtime.scheduler.cancelCalls, 0)
		local second = runtime.scheduler.handles[2]
		assertions.isTrue(second.delaySeconds > 0)
		assertions.isTrue(second.delaySeconds < 0.01)

		runtime.clock.now = 145
		fire(second)
		assertions.equal(runtimeState(runtime), "Closing")
		assertions.isNil(runtime.coordinator:getDeadlineServerTime())
		local finalRevision = runtime.machine:getRevision()
		fire(first)
		fire(second)
		assertions.equal(runtime.machine:getRevision(), finalRevision)
	end),

	TestHarness.case("applies the mixed timeout batch once before entering PreWave", function(assertions)
		local runtime = newRuntime(assertions, nil)
		local first = {}
		local second = {}
		local third = {}
		admit(assertions, runtime, first, 1)
		admit(assertions, runtime, second, 2)
		admit(assertions, runtime, third, 3)
		local readyCheck = enter(assertions, runtime)
		expectSuccess(assertions, runtime.coordinator:submitReady(first, MATCH_ID, readyCheck.revision))
		local beforeTimeoutRevision = runtime.machine:getRevision()

		runtime.clock.now = 145
		fire(runtime.scheduler.handles[1])
		assertions.equal(runtimeState(runtime), "PreWave")
		assertions.equal(runtime.machine:getRevision(), beforeTimeoutRevision + 2)
		assertions.isNil(runtime.coordinator:getDeadlineServerTime())
		local participants = rosterSnapshot(assertions, runtime)
		assertions.equal(participants[1].state, "Active")
		assertions.isTrue(participants[1].ready)
		assertions.equal(participants[2].state, "Returned")
		assertions.isFalse(participants[2].ready)
		assertions.equal(participants[3].state, "Returned")
		assertions.isFalse(participants[3].ready)
		assertions.equal(runtime.scheduler.cancelCalls, 0)
	end),

	TestHarness.case("closes with zero ready participants including a zero-active roster", function(assertions)
		local emptyRuntime = newRuntime(assertions, nil)
		enter(assertions, emptyRuntime)
		emptyRuntime.clock.now = 145
		fire(emptyRuntime.scheduler.handles[1])
		assertions.equal(runtimeState(emptyRuntime), "Closing")

		local disconnectedRuntime = newRuntime(assertions, nil)
		local connection = {}
		admit(assertions, disconnectedRuntime, connection, 1)
		enter(assertions, disconnectedRuntime)
		expectSuccess(assertions, disconnectedRuntime.roster:disconnect(connection))
		touchMachine(assertions, disconnectedRuntime)
		disconnectedRuntime.clock.now = 145
		local outcome = expectSuccess(assertions, disconnectedRuntime.coordinator:onRosterChanged())
		assertions.equal(outcome.state, "Closing")
		assertions.equal(rosterSnapshot(assertions, disconnectedRuntime)[1].state, "Disconnected")
	end),

	TestHarness.case("fails closed on clock scheduler and cancellation anomalies", function(assertions)
		local initialClockFailure = newRuntime(assertions, nil)
		initialClockFailure.clock.throws = true
		expectError(assertions, initialClockFailure.coordinator:enterReadyCheck(), "INTERNAL_ERROR", "enterReadyCheck")
		assertions.equal(runtimeState(initialClockFailure), "Closing")

		local backwards = newRuntime(assertions, nil)
		local first = {}
		local second = {}
		admit(assertions, backwards, first, 1)
		admit(assertions, backwards, second, 2)
		local entry = enter(assertions, backwards)
		backwards.clock.now = 99
		expectError(
			assertions,
			backwards.coordinator:submitReady(first, MATCH_ID, entry.revision),
			"INTERNAL_ERROR",
			"submitReady"
		)
		assertions.equal(runtimeState(backwards), "Closing")
		assertions.isNil(backwards.coordinator:getDeadlineServerTime())

		local scheduleFailure = newRuntime(assertions, nil)
		scheduleFailure.scheduler.failScheduleAt = 1
		expectError(assertions, scheduleFailure.coordinator:enterReadyCheck(), "INTERNAL_ERROR", "enterReadyCheck")
		assertions.equal(runtimeState(scheduleFailure), "Closing")

		local cancelFailure = newRuntime(assertions, nil)
		local onlyConnection = {}
		admit(assertions, cancelFailure, onlyConnection, 1)
		local cancelEntry = enter(assertions, cancelFailure)
		cancelFailure.scheduler.failCancel = true
		expectError(
			assertions,
			cancelFailure.coordinator:submitReady(onlyConnection, MATCH_ID, cancelEntry.revision),
			"INTERNAL_ERROR",
			"submitReady"
		)
		assertions.equal(runtimeState(cancelFailure), "Closing")
		assertions.isNil(cancelFailure.coordinator:getDeadlineServerTime())
	end),

	TestHarness.case("fails closed when an early callback cannot schedule its replacement", function(assertions)
		local runtime = newRuntime(assertions, nil)
		enter(assertions, runtime)
		runtime.scheduler.failScheduleAt = 2
		runtime.clock.now = 120
		fire(runtime.scheduler.handles[1])
		assertions.equal(runtimeState(runtime), "Closing")
		assertions.isNil(runtime.coordinator:getDeadlineServerTime())
		assertions.equal(runtime.scheduler.scheduleCalls, 2)
	end),

	TestHarness.case("cleanup cancels only the live handle and invalidates every callback", function(assertions)
		local runtime = newRuntime(assertions, nil)
		enter(assertions, runtime)
		local first = runtime.scheduler.handles[1]
		runtime.clock.now = 110
		fire(first)
		local second = runtime.scheduler.handles[2]
		assertions.isFalse(first.cancelled)
		assertions.isFalse(second.cancelled)

		assertions.isTrue(expectSuccess(assertions, runtime.coordinator:cleanup()))
		assertions.isFalse(expectSuccess(assertions, runtime.coordinator:cleanup()))
		assertions.isTrue(second.cancelled)
		assertions.equal(runtime.scheduler.cancelCalls, 1)
		assertions.isNil(runtime.coordinator:getDeadlineServerTime())
		assertions.isNil(runtime.coordinator:getEntryRevision())
		local beforeCallbacks = runtime.machine:getRevision()
		fire(first)
		fire(second)
		assertions.equal(runtime.machine:getRevision(), beforeCallbacks)
		expectError(
			assertions,
			runtime.coordinator:submitReady({}, MATCH_ID, beforeCallbacks),
			"UNAVAILABLE",
			"submitReady"
		)
	end),

	TestHarness.case("contains a throwing change observer after authority commits", function(assertions)
		local callbackCount = 0
		local runtime = newRuntime(assertions, function(_outcome)
			callbackCount += 1
			error("PRIVATE_OBSERVER_FAILURE", 0)
		end)
		local connection = {}
		admit(assertions, runtime, connection, 1)
		local entered = enter(assertions, runtime)
		assertions.equal(callbackCount, 1)
		local accepted =
			expectSuccess(assertions, runtime.coordinator:submitReady(connection, MATCH_ID, entered.revision))
		assertions.equal(callbackCount, 2)
		assertions.equal(accepted.state, "PreWave")
		assertions.equal(runtimeState(runtime), "PreWave")
	end),
})
