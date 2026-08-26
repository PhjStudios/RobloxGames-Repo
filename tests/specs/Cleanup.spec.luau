--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)

local Shared = game:GetService("ReplicatedStorage").Shared
local EnvironmentContext = require(Shared.logging.EnvironmentContext)
local Log = require(Shared.logging.Log)
local Cleanup = require(Shared.util.Cleanup)

type Assertions = TestHarness.Assertions

local PRIVATE_SENTINEL = "PRIVATE_CLEANUP_SENTINEL_7f86c5"
local logger = Log.new(EnvironmentContext.new("server", "Development", 0, false))

local function newContainer(label: string): Cleanup.Container
	return Cleanup.new(logger, label)
end

local function captureError(assertions: Assertions, callback: () -> ()): string
	local succeeded, value = pcall(callback)
	assertions.isFalse(succeeded)
	assertions.equal(type(value), "string")
	if type(value) ~= "string" then
		return ""
	end
	return value
end

local function assertCode(assertions: Assertions, value: string, code: string)
	assertions.contains(value, `[code={code}]`)
end

return TestHarness.suite("cleanup ownership contract", {
	TestHarness.case(
		"cleans callbacks in strict LIFO order and preserves duplicate registrations",
		function(assertions)
			local container = newContainer("lifo")
			local order = {}
			local duplicate = function()
				table.insert(order, "duplicate")
			end

			container:add(function()
				table.insert(order, "first")
			end)
			container:add(duplicate)
			container:add(duplicate)

			container:cleanup()

			assertions.equal(table.concat(order, ","), "duplicate,duplicate,first")
			assertions.equal(container:getState(), "Cleaned")
			assertions.equal(container:getTaskCount(), 0)
		end
	),

	TestHarness.case("successful cleanup is idempotent and rejects post-clean registration", function(assertions)
		local container = newContainer("idempotent")
		local cleanupCount = 0
		container:add(function()
			cleanupCount += 1
		end)

		container:cleanup()
		container:cleanup()

		assertions.equal(cleanupCount, 1)
		assertions.equal(container:getState(), "Cleaned")
		local rejection = captureError(assertions, function()
			container:add(function() end)
		end)
		assertCode(assertions, rejection, "INVALID_STATE")
		assertions.contains(rejection, "[event=add_rejected]")
		assertions.contains(rejection, "[container=idempotent]")
		assertions.contains(rejection, "[state=Cleaned]")
		assertions.equal(container:getTaskCount(), 0)
	end),

	TestHarness.case("cleans every supported task form and returns exact registered identities", function(assertions)
		local container = newContainer("supported")
		local child = newContainer("supported-child")
		local callbackCount = 0
		local childCount = 0
		local disconnectCount = 0
		local callback = function()
			callbackCount += 1
		end
		local connection = RobloxAdapter.createConnection(function()
			disconnectCount += 1
		end)
		assertions.equal(typeof(connection), "RBXScriptConnection")
		assertions.equal(typeof({ Disconnect = function() end }), "table")
		local instanceRoot = Instance.new("Folder")
		local ownedInstance = Instance.new("Folder")
		ownedInstance.Name = "Owned"
		ownedInstance.Parent = instanceRoot
		local ownedThread = coroutine.create(function()
			coroutine.yield()
		end)
		local resumed = coroutine.resume(ownedThread)
		assertions.isTrue(resumed)
		assertions.equal(coroutine.status(ownedThread), "suspended")
		child:add(function()
			childCount += 1
		end)

		assertions.equal(container:add(callback), callback)
		assertions.equal(container:add(connection :: any), connection)
		assertions.equal(container:add(ownedInstance), ownedInstance)
		assertions.equal(container:add(ownedThread), ownedThread)
		assertions.equal(container:add(child), child)
		assertions.equal(container:getTaskCount(), 5)

		container:cleanup()

		assertions.equal(callbackCount, 1)
		assertions.equal(disconnectCount, 1)
		assertions.equal(childCount, 1)
		assertions.isNil(instanceRoot:FindFirstChild("Owned"))
		assertions.equal(coroutine.status(ownedThread), "dead")
		assertions.equal(child:getState(), "Cleaned")
		assertions.equal(container:getState(), "Cleaned")
		instanceRoot:Destroy()
	end),

	TestHarness.case("rejects unsupported and method-shaped tasks without retaining ownership", function(assertions)
		local container = newContainer("unsupported")
		local unsupportedValue = {
			Disconnect = function() end,
			private = PRIVATE_SENTINEL,
		}
		local rejection = captureError(assertions, function()
			container:add(unsupportedValue :: any)
		end)

		assertCode(assertions, rejection, "UNSUPPORTED_TASK")
		assertions.contains(rejection, "received table")
		assertions.isNil(string.find(rejection, PRIVATE_SENTINEL, 1, true))
		assertions.equal(container:getState(), "Active")
		assertions.equal(container:getTaskCount(), 0)
	end),

	TestHarness.case("requires a genuine logger and a valid privacy-safe label", function(assertions)
		local contextRejection = captureError(assertions, function()
			Cleanup.new({ private = PRIVATE_SENTINEL } :: any, "invalid-context")
		end)
		assertCode(assertions, contextRejection, "INVALID_CONTEXT")
		assertions.isNil(string.find(contextRejection, PRIVATE_SENTINEL, 1, true))

		local labelRejection = captureError(assertions, function()
			Cleanup.new(logger, PRIVATE_SENTINEL .. " invalid")
		end)
		assertCode(assertions, labelRejection, "INVALID_LABEL")
		assertions.isNil(string.find(labelRejection, PRIVATE_SENTINEL, 1, true))
	end),

	TestHarness.case("accepts an already dead thread as a harmless terminal task", function(assertions)
		local container = newContainer("dead-thread")
		local deadThread = coroutine.create(function() end)
		local resumed = coroutine.resume(deadThread)
		assertions.isTrue(resumed)
		assertions.equal(coroutine.status(deadThread), "dead")

		container:add(deadThread)
		container:cleanup()

		assertions.equal(container:getState(), "Cleaned")
		assertions.equal(container:getTaskCount(), 0)
	end),

	TestHarness.case("nested ownership cleans the child before earlier parent siblings", function(assertions)
		local parent = newContainer("nested-parent")
		local child = newContainer("nested-child")
		local order = {}
		parent:add(function()
			table.insert(order, "parent")
		end)
		child:add(function()
			table.insert(order, "child-first")
		end)
		child:add(function()
			table.insert(order, "child-last")
		end)
		parent:add(child)

		parent:cleanup()

		assertions.equal(table.concat(order, ","), "child-last,child-first,parent")
		assertions.equal(child:getState(), "Cleaned")
		assertions.equal(parent:getState(), "Cleaned")
	end),

	TestHarness.case("independently cleaned child remains an idempotent parent-owned task", function(assertions)
		local parent = newContainer("independent-parent")
		local child = newContainer("independent-child")
		local cleanupCount = 0
		child:add(function()
			cleanupCount += 1
		end)
		parent:add(child)

		child:cleanup()
		parent:cleanup()
		parent:cleanup()

		assertions.equal(cleanupCount, 1)
		assertions.equal(child:getState(), "Cleaned")
		assertions.equal(parent:getState(), "Cleaned")
	end),

	TestHarness.case("rejects direct and indirect nested ownership cycles without mutation", function(assertions)
		local alpha = newContainer("cycle-alpha")
		local beta = newContainer("cycle-beta")
		local gamma = newContainer("cycle-gamma")

		local directRejection = captureError(assertions, function()
			alpha:add(alpha)
		end)
		assertCode(assertions, directRejection, "NESTING_CYCLE")
		assertions.equal(alpha:getTaskCount(), 0)

		alpha:add(beta)
		beta:add(gamma)
		local indirectRejection = captureError(assertions, function()
			gamma:add(alpha)
		end)
		assertCode(assertions, indirectRejection, "NESTING_CYCLE")
		assertions.equal(alpha:getTaskCount(), 1)
		assertions.equal(beta:getTaskCount(), 1)
		assertions.equal(gamma:getTaskCount(), 0)
		assertions.equal(alpha:getState(), "Active")
		assertions.equal(beta:getState(), "Active")
		assertions.equal(gamma:getState(), "Active")
	end),

	TestHarness.case("rejects cleaned and cleaning nested containers without parent mutation", function(assertions)
		local parent = newContainer("nested-state-parent")
		local cleanedChild = newContainer("nested-state-cleaned")
		cleanedChild:cleanup()
		local cleanedRejection = captureError(assertions, function()
			parent:add(cleanedChild)
		end)
		assertCode(assertions, cleanedRejection, "INVALID_NESTED_STATE")
		assertions.contains(cleanedRejection, "received Cleaned")

		local cleaningChild = newContainer("nested-state-cleaning")
		local cleaningWasRejected = false
		local cleaningRejection: string? = nil
		cleaningChild:add(function()
			local succeeded, value = pcall(function()
				parent:add(cleaningChild)
			end)
			cleaningWasRejected = not succeeded
			if type(value) == "string" then
				cleaningRejection = value
			end
		end)
		cleaningChild:cleanup()

		assertions.isTrue(cleaningWasRejected)
		assertions.isNotNil(cleaningRejection)
		assertCode(assertions, cleaningRejection or "", "INVALID_NESTED_STATE")
		assertions.contains(cleaningRejection or "", "received Cleaning")
		assertions.equal(parent:getTaskCount(), 0)
		assertions.equal(parent:getState(), "Active")
	end),

	TestHarness.case("isolates callback failure and completes the remaining reverse sweep", function(assertions)
		local container = newContainer("failure-isolation")
		local order = {}
		container:add(function()
			table.insert(order, "earlier")
		end)
		container:add(function()
			error(PRIVATE_SENTINEL, 0)
		end)
		container:add(function()
			table.insert(order, "later")
		end)

		local aggregate = captureError(assertions, function()
			container:cleanup()
		end)

		assertions.equal(table.concat(order, ","), "later,earlier")
		assertCode(assertions, aggregate, "CLEANUP_FAILED")
		assertions.contains(aggregate, "1 failed task(s)")
		assertions.contains(aggregate, "task 2 (Callback/function)")
		assertions.isNil(string.find(aggregate, PRIVATE_SENTINEL, 1, true))
		assertions.equal(container:getState(), "Cleaned")
		assertions.equal(container:getTaskCount(), 0)
	end),

	TestHarness.case("isolates a failing child container and cleans parent siblings", function(assertions)
		local parent = newContainer("nested-failure-parent")
		local child = newContainer("nested-failure-child")
		local order = {}
		child:add(function()
			error(PRIVATE_SENTINEL, 0)
		end)
		parent:add(function()
			table.insert(order, "earlier")
		end)
		parent:add(child)
		parent:add(function()
			table.insert(order, "later")
		end)

		local aggregate = captureError(assertions, function()
			parent:cleanup()
		end)

		assertions.equal(table.concat(order, ","), "later,earlier")
		assertCode(assertions, aggregate, "CLEANUP_FAILED")
		assertions.contains(aggregate, "task 2 (Container/table)")
		assertions.isNil(string.find(aggregate, PRIVATE_SENTINEL, 1, true))
		assertions.equal(child:getState(), "Cleaned")
		assertions.equal(parent:getState(), "Cleaned")
	end),

	TestHarness.case("repeats the exact cached failure without retrying completed tasks", function(assertions)
		local container = newContainer("cached-failure")
		local attemptCount = 0
		container:add(function()
			attemptCount += 1
			error(PRIVATE_SENTINEL, 0)
		end)

		local firstFailure = captureError(assertions, function()
			container:cleanup()
		end)
		local repeatedFailure = captureError(assertions, function()
			container:cleanup()
		end)

		assertions.equal(repeatedFailure, firstFailure)
		assertions.equal(attemptCount, 1)
		assertions.isNil(string.find(firstFailure, PRIVATE_SENTINEL, 1, true))
		assertions.equal(container:getState(), "Cleaned")
		assertions.equal(container:getTaskCount(), 0)
	end),

	TestHarness.case("rejects add and cleanup reentry while the outer sweep continues", function(assertions)
		local container = newContainer("reentrant")
		local laterTaskRan = false
		local addWasRejected = false
		local reentryWasRejected = false
		local addRejection: string? = nil
		local reentryRejection: string? = nil
		container:add(function()
			laterTaskRan = true
		end)
		container:add(function()
			local addSucceeded, addValue = pcall(function()
				container:add(function() end)
			end)
			addWasRejected = not addSucceeded
			if type(addValue) == "string" then
				addRejection = addValue
			end

			local reentrySucceeded, reentryValue = pcall(function()
				container:cleanup()
			end)
			reentryWasRejected = not reentrySucceeded
			if type(reentryValue) == "string" then
				reentryRejection = reentryValue
			end
		end)

		container:cleanup()

		assertions.isTrue(addWasRejected)
		assertions.isTrue(reentryWasRejected)
		assertions.isTrue(laterTaskRan)
		assertCode(assertions, addRejection or "", "INVALID_STATE")
		assertions.contains(addRejection or "", "[event=add_rejected]")
		assertions.contains(addRejection or "", "[state=Cleaning]")
		assertCode(assertions, reentryRejection or "", "INVALID_STATE")
		assertions.contains(reentryRejection or "", "[event=cleanup_rejected]")
		assertions.contains(reentryRejection or "", "[state=Cleaning]")
		assertions.equal(container:getState(), "Cleaned")
		assertions.equal(container:getTaskCount(), 0)
	end),
})
