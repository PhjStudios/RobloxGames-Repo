--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local IsolatedTeleportAdapter = require(script.Parent.Parent.Fixtures.IsolatedTeleportAdapter)
local SafeTeleportService = require(script.Parent.Parent.ProductionServerTravel.SafeTeleportService)
local Result = require(ReplicatedStorage.Shared.util.Result)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)

local NOW = 1_700_000_000

local function store(): (any, any)
	local state = {
		marking = 0,
		retries = 0,
		terminals = {},
	}
	local adapter = {}
	function adapter:markTeleporting(_ticketId, _nowValue)
		state.marking += 1
		return Result.ok(true)
	end
	function adapter:recordRetry(_ticketId, _nowValue)
		state.retries += 1
		return Result.ok(true)
	end
	function adapter:markTerminal(ticketId, reason, _nowValue)
		table.insert(state.terminals, { ticketId = ticketId, reason = reason })
		return Result.ok(true)
	end
	return adapter, state
end

local function player(userId: number): any
	return { userId = userId, present = true }
end

local function service(assertions, teleport, storeAdapter, overrides): any
	local scheduled = {}
	local dependencies = {
		now = function()
			return NOW
		end,
		wait = function(_seconds) end,
		schedule = function(callback)
			table.insert(scheduled, callback)
			return true
		end,
		getUserId = function(candidate)
			return candidate.userId
		end,
		isPresent = function(candidate)
			return candidate.present
		end,
		maxAttempts = 3,
		baseBackoffSeconds = 0,
		reconciliationSeconds = 1,
	}
	if overrides ~= nil then
		for key, value in overrides do
			dependencies[key] = value
		end
	end
	local created = SafeTeleportService.new(storeAdapter, teleport, dependencies)
	assertions.isTrue(created.ok)
	return created.value,
		function()
			while #scheduled > 0 do
				local callback = table.remove(scheduled, 1)
				callback()
			end
		end
end

return TestHarness.suite("isolated safe group teleport boundary", {
	TestHarness.case("accepts only bounded Return data for public-place travel", function(assertions)
		local teleport = IsolatedTeleportAdapter.new()
		local routing = TravelProtocol.returnToLobby("return:safe-public").value
		assertions.isTrue(teleport:teleportPublic(1001, { player(101), player(202) }, routing).ok)
		local captured = teleport:getCalls().publicTeleports[1]
		assertions.equal(captured.routingData.kind, "Return")
		assertions.equal(captured.routingData.returnId, "return:safe-public")
		assertions.isNil(captured.routingData.accessCode)
		assertions.isNil(captured.routingData.roster)
		assertions.isFalse(
			teleport:teleportPublic(
				1001,
				{ player(101) },
				TravelProtocol.match("ticket:not-return", "attempt:not-return").value
			).ok
		)
		assertions.isFalse(teleport:teleportPublic(1001, {}, routing).ok)
		assertions.isFalse(teleport:teleportPublic(1001, { player(101), player(101) }, routing).ok)
	end),
	TestHarness.case("delivers a server-only reservation before bounded TeleportData", function(assertions)
		local storeAdapter = store()
		local teleport = IsolatedTeleportAdapter.new()
		local reserved = nil
		local serviceValue = service(assertions, teleport, storeAdapter, {
			onReserved = function(snapshot)
				assertions.equal(teleport:getCalls().teleportCount, 0)
				reserved = snapshot
				return Result.ok(true)
			end,
		})
		local first = player(101)
		local second = player(202)
		local started = serviceValue:start("ticket:safe-success", 2002, { first, second })
		assertions.isTrue(started.ok)
		assertions.equal(started.value.memberCount, 2)
		assertions.isNil((started.value :: any).accessCode)
		assertions.isTrue(table.isfrozen(reserved))
		assertions.isTrue(table.isfrozen(reserved.orderedUserIds))
		assertions.equal(reserved.accessCode, "isolated-access-1")
		assertions.equal(reserved.privateServerId, "isolated-private-1")

		local call = teleport:getCalls().teleports[1]
		assertions.equal(call.routingData.ticketId, "ticket:safe-success")
		assertions.equal(call.routingData.attemptId, "attempt:1")
		assertions.isNil(call.routingData.accessCode)
		assertions.isNil(call.routingData.expectedUserIds)
		assertions.equal(call.accessCode, "isolated-access-1")
		assertions.isTrue(serviceValue:finish("ticket:safe-success").value)
	end),
	TestHarness.case("aborts before teleport when the reserved-route callback fails", function(assertions)
		local storeAdapter, storeState = store()
		local teleport = IsolatedTeleportAdapter.new()
		local rollbacks = {}
		local serviceValue, flush = service(assertions, teleport, storeAdapter, {
			onReserved = function(_snapshot)
				return false
			end,
			onRollback = function(snapshot)
				table.insert(rollbacks, snapshot)
			end,
		})
		local started = serviceValue:start("ticket:callback-failure", 2002, { player(101) })
		flush()
		assertions.isFalse(started.ok)
		assertions.equal(started.error.code, "RESERVATION_CALLBACK_FAILED")
		assertions.equal(teleport:getCalls().teleportCount, 0)
		assertions.equal(storeState.terminals[1].reason, "RESERVATION_CALLBACK_FAILED")
		assertions.equal(#rollbacks, 1)
		assertions.isNil(rollbacks[1].accessCode)
		assertions.equal(serviceValue:getMetrics().activeSessionCount, 0)
	end),
	TestHarness.case("retries bounded reserve and teleport failures", function(assertions)
		local storeAdapter, storeState = store()
		local teleport = IsolatedTeleportAdapter.new()
		teleport:queueReserveFailure("Retryable")
		teleport:queueTeleportFailure("Retryable")
		local serviceValue = service(assertions, teleport, storeAdapter, nil)
		assertions.isTrue(serviceValue:start("ticket:retry", 2002, { player(101) }).ok)
		local calls = teleport:getCalls()
		assertions.equal(calls.reserveCount, 2)
		assertions.equal(calls.teleportCount, 2)
		assertions.equal(storeState.retries, 2)
	end),
	TestHarness.case(
		"watches a successful initialization and rolls back members still present at deadline",
		function(assertions)
			local storeAdapter, storeState = store()
			local teleport = IsolatedTeleportAdapter.new()
			local rollbacks = {}
			local serviceValue, flush = service(assertions, teleport, storeAdapter, {
				onRollback = function(snapshot)
					table.insert(rollbacks, snapshot)
				end,
			})
			assertions.isTrue(serviceValue:start("ticket:success-timeout", 2002, { player(101) }).ok)
			assertions.equal(#rollbacks, 0)
			flush()
			assertions.equal(#rollbacks, 1)
			assertions.equal(rollbacks[1].failedUserIds[1], 101)
			assertions.isFalse(rollbacks[1].partial)
			assertions.equal(storeState.terminals[1].reason, "TELEPORT_INIT_FAILED")
			assertions.equal(serviceValue:getMetrics().activeSessionCount, 0)
		end
	),
	TestHarness.case("completes without rollback when every initialized member departs", function(assertions)
		local storeAdapter, storeState = store()
		local teleport = IsolatedTeleportAdapter.new()
		local rollbacks = {}
		local completions = {}
		local first = player(101)
		local second = player(202)
		local serviceValue, flush = service(assertions, teleport, storeAdapter, {
			wait = function(_seconds)
				first.present = false
			end,
			onRollback = function(snapshot)
				table.insert(rollbacks, snapshot)
			end,
			onComplete = function(snapshot)
				table.insert(completions, snapshot)
			end,
		})
		assertions.isTrue(serviceValue:start("ticket:failed-then-departed", 2002, { first, second }).ok)
		second.present = false
		teleport:emitInitFailure(first, "Terminal")
		flush()
		assertions.equal(#rollbacks, 0)
		assertions.equal(#completions, 1)
		assertions.equal(completions[1].ticketId, "ticket:failed-then-departed")
		assertions.equal(#completions[1].departedUserIds, 2)
		assertions.equal(#storeState.terminals, 0)
		assertions.equal(serviceValue:getMetrics().activeSessionCount, 0)
		assertions.isFalse(serviceValue:finish("ticket:failed-then-departed").value)
	end),
	TestHarness.case("rolls back terminal initialization failure without a ghost session", function(assertions)
		local storeAdapter, storeState = store()
		local teleport = IsolatedTeleportAdapter.new()
		teleport:queueTeleportFailure("Terminal")
		local rollbacks = {}
		local serviceValue, flush = service(assertions, teleport, storeAdapter, {
			onRollback = function(snapshot)
				table.insert(rollbacks, snapshot)
			end,
		})
		local started = serviceValue:start("ticket:terminal", 2002, { player(101), player(202) })
		flush()
		assertions.isFalse(started.ok)
		assertions.equal(started.error.failureClass, "Terminal")
		assertions.equal(storeState.terminals[1].reason, "TELEPORT_FAILED")
		assertions.isFalse(rollbacks[1].partial)
		assertions.equal(serviceValue:getMetrics().activeMemberCount, 0)
	end),
	TestHarness.case("retains reconciliation state after a partial departure", function(assertions)
		local storeAdapter, storeState = store()
		local teleport = IsolatedTeleportAdapter.new()
		local rollbacks = {}
		local serviceValue, flush = service(assertions, teleport, storeAdapter, {
			onRollback = function(snapshot)
				table.insert(rollbacks, snapshot)
			end,
		})
		local first = player(101)
		local second = player(202)
		assertions.isTrue(serviceValue:start("ticket:partial", 2002, { first, second }).ok)
		second.present = false
		teleport:emitInitFailure(first, "Terminal")
		flush()
		assertions.equal(#rollbacks, 1)
		assertions.isTrue(rollbacks[1].partial)
		assertions.equal(rollbacks[1].departedUserIds[1], 202)
		assertions.equal(#storeState.terminals, 0)
		assertions.equal(serviceValue:getMetrics().activeSessionCount, 1)
		assertions.isTrue(serviceValue:finish("ticket:partial").value)
	end),
	TestHarness.case("waits for a stable failed-or-departed partition before rollback", function(assertions)
		local storeAdapter, storeState = store()
		local teleport = IsolatedTeleportAdapter.new()
		local rollbacks = {}
		local first = player(101)
		local second = player(202)
		local observedWait = false
		local serviceValue, flush = service(assertions, teleport, storeAdapter, {
			wait = function(_seconds)
				if not observedWait then
					observedWait = true
					second.present = false
				end
			end,
			onRollback = function(snapshot)
				table.insert(rollbacks, snapshot)
			end,
		})
		assertions.isTrue(serviceValue:start("ticket:stable-partition", 2002, { first, second }).ok)
		teleport:emitInitFailure(first, "Terminal")
		flush()
		assertions.equal(#rollbacks, 1)
		assertions.equal(rollbacks[1].failedUserIds[1], 101)
		assertions.equal(#rollbacks[1].failedUserIds, 1)
		assertions.equal(rollbacks[1].departedUserIds[1], 202)
		assertions.equal(#rollbacks[1].presentUserIds, 1)
		assertions.equal(rollbacks[1].presentUserIds[1], 101)
		assertions.isTrue(rollbacks[1].partial)
		assertions.equal(#storeState.terminals, 0)
		assertions.isTrue(serviceValue:finish("ticket:stable-partition").value)
	end),
	TestHarness.case("deduplicates concurrent initialization failures and keeps retries bounded", function(assertions)
		local storeAdapter = store()
		local teleport = IsolatedTeleportAdapter.new()
		local rollbacks = {}
		local first = player(101)
		local injectedDuplicate = false
		local serviceValue, flush = service(assertions, teleport, storeAdapter, {
			wait = function(_seconds)
				if not injectedDuplicate then
					injectedDuplicate = true
					teleport:emitInitFailure(first, "Retryable")
				end
			end,
			onRollback = function(snapshot)
				table.insert(rollbacks, snapshot)
			end,
		})
		assertions.isTrue(serviceValue:start("ticket:duplicate-init", 2002, { first }).ok)
		teleport:queueTeleportFailure("Retryable", 2)
		teleport:emitInitFailure(first, "Retryable")
		flush()
		assertions.equal(teleport:getCalls().teleportCount, 3)
		assertions.equal(#rollbacks, 1)
		assertions.equal(serviceValue:getMetrics().activeSessionCount, 0)
	end),
	TestHarness.case("ignores a delayed initialization failure from a settled ticket", function(assertions)
		local storeAdapter = store()
		local teleport = IsolatedTeleportAdapter.new()
		local rollbacks = {}
		local first = player(101)
		local serviceValue, flush = service(assertions, teleport, storeAdapter, {
			onRollback = function(snapshot)
				table.insert(rollbacks, snapshot)
			end,
		})
		assertions.isTrue(serviceValue:start("ticket:old-attempt", 2002, { first }).ok)
		local oldRouting = teleport:getCalls().teleports[1].routingData
		assertions.isTrue(serviceValue:finish("ticket:old-attempt").value)
		assertions.isTrue(serviceValue:start("ticket:new-attempt", 2002, { first }).ok)
		local newRouting = teleport:getCalls().teleports[2].routingData

		teleport:emitInitFailure(first, "Terminal", 2002, oldRouting)
		assertions.equal(serviceValue:getMetrics().activeSessionCount, 1)
		assertions.equal(#rollbacks, 0)
		teleport:emitInitFailure(first, "Terminal", 2002, newRouting)
		flush()
		assertions.equal(#rollbacks, 1)
		assertions.equal(rollbacks[1].ticketId, "ticket:new-attempt")
	end),
	TestHarness.case("ignores a delayed failure from an older retry of the same ticket", function(assertions)
		local storeAdapter = store()
		local teleport = IsolatedTeleportAdapter.new()
		local rollbacks = {}
		local first = player(101)
		local serviceValue, flush = service(assertions, teleport, storeAdapter, {
			onRollback = function(snapshot)
				table.insert(rollbacks, snapshot)
			end,
		})
		assertions.isTrue(serviceValue:start("ticket:retry-correlation", 2002, { first }).ok)
		local oldRouting = teleport:getCalls().teleports[1].routingData

		teleport:emitInitFailure(first, "Retryable", 2002, oldRouting)
		local calls = teleport:getCalls()
		assertions.equal(calls.teleportCount, 2)
		local currentRouting = calls.teleports[2].routingData
		assertions.isTrue(currentRouting.attemptId ~= oldRouting.attemptId)

		teleport:emitInitFailure(first, "Terminal", 2002, oldRouting)
		assertions.equal(teleport:getCalls().teleportCount, 2)
		assertions.equal(#rollbacks, 0)

		teleport:emitInitFailure(first, "Terminal", 2002, currentRouting)
		flush()
		assertions.equal(#rollbacks, 1)
		assertions.equal(rollbacks[1].ticketId, "ticket:retry-correlation")
	end),
})
