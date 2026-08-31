--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local NotificationStore = require(script.Parent.Parent.ProductionClientCommonUi.NotificationStore)

local function expectSuccess(value: any): any
	if not value.ok then
		error(`unexpected notification failure: {value.error.code}`, 0)
	end
	return value.value
end

return TestHarness.suite("bounded Lobby notification store", {
	TestHarness.case("deduplicates repeated network errors and extends one visible toast", function(assertions)
		local now = 10
		local store = expectSuccess(NotificationStore.new(function()
			return now
		end))
		local first = expectSuccess(store:push({
			kind = "Error",
			title = "Connection problem",
			message = "The profile request could not be completed.",
			dedupeKey = "network.profile",
			durationSeconds = 5,
		}))
		assertions.equal(first.kind, "Added")
		now = 12
		local repeated = expectSuccess(store:push({
			kind = "Error",
			title = "Hostile replacement ignored",
			message = "A repeated request failed.",
			dedupeKey = "network.profile",
			durationSeconds = 5,
		}))
		assertions.equal(repeated.kind, "Deduplicated")
		assertions.equal(repeated.id, first.id)
		local snapshot = expectSuccess(store:getSnapshot())
		assertions.equal(#snapshot, 1)
		assertions.equal(snapshot[1].repeatCount, 2)
		assertions.equal(snapshot[1].title, "Connection problem")
		assertions.equal(snapshot[1].expiresAt, 17)
		assertions.isTrue(table.isfrozen(snapshot))
		assertions.isTrue(table.isfrozen(snapshot[1]))
		store:cleanup()
	end),

	TestHarness.case("keeps a deterministic newest bounded queue", function(assertions)
		local store = expectSuccess(NotificationStore.new(function()
			return 0
		end))
		local ids = {}
		for index = 1, NotificationStore.MAX_NOTIFICATIONS + 2 do
			ids[index] = expectSuccess(store:push({
				kind = "Info",
				title = `Notice {index}`,
				message = "Bounded presentation record",
			})).id
		end
		local snapshot = expectSuccess(store:getSnapshot())
		assertions.equal(#snapshot, NotificationStore.MAX_NOTIFICATIONS)
		assertions.equal(snapshot[1].id, ids[3])
		assertions.equal(snapshot[#snapshot].id, ids[#ids])
		assertions.isTrue(expectSuccess(store:dismiss(ids[4])))
		assertions.isFalse(expectSuccess(store:dismiss(ids[1])))
		store:cleanup()
	end),

	TestHarness.case("expires entries only at bounded clock-driven ticks", function(assertions)
		local now = 0
		local store = expectSuccess(NotificationStore.new(function()
			return now
		end))
		store:push({ kind = "Success", title = "Saved", message = "Settings saved", durationSeconds = 2 })
		now = 1.999
		assertions.equal(expectSuccess(store:tick()), 0)
		now = 2
		assertions.equal(expectSuccess(store:tick()), 1)
		assertions.equal(#expectSuccess(store:getSnapshot()), 0)
		store:cleanup()
	end),

	TestHarness.case("rejects hostile payloads and contains clock failure", function(assertions)
		local store = expectSuccess(NotificationStore.new(function()
			return 1
		end))
		assertions.equal(store:push({ kind = "Private", title = "x", message = "y" }).error.code, "INVALID_ARGUMENT")
		assertions.equal(
			store:push({ kind = "Error", title = "x", message = "y", private = true }).error.code,
			"INVALID_ARGUMENT"
		)
		assertions.equal(
			store:push({ kind = "Error", title = "x", message = "y", durationSeconds = 30 }).error.code,
			"INVALID_ARGUMENT"
		)
		store:cleanup()
		assertions.equal(store:push({ kind = "Info", title = "x", message = "y" }).error.code, "CLEANED_UP")

		assertions.equal(
			NotificationStore.new(function()
				return 0 / 0
			end).error.code,
			"CLOCK_FAILED"
		)
	end),
})
