--!strict

local Harness = require(script.Parent.Parent.Support.TestHarness)
local ProfileScope = require(game:GetService("ReplicatedStorage").Shared.util.ProfileScope)

return Harness.suite("safe static engine profiler scopes", {
	Harness.case("missing engine profiling is a direct no-op and preserves results", function(a)
		local profiler = ProfileScope.create({})
		local expected = {}
		a.isFalse(profiler.begin("ATD.Runtime.Step"))
		a.equal(
			profiler.call("ATD.Runtime.Step", function(value)
				return value
			end, expected),
			expected
		)
		a.isTrue(pcall(profiler.finish, false))
	end),
	Harness.case("all static labels begin and finish exactly once including empty results", function(a)
		local beginCount, endCount = 0, 0
		local profiler = ProfileScope.create({
			beginScope = function(label)
				a.isTrue(ProfileScope.LABELS[label])
				beginCount += 1
			end,
			endScope = function()
				endCount += 1
			end,
		})
		for label in ProfileScope.LABELS do
			a.isNil(profiler.call(label, function() end))
		end
		a.equal(beginCount, 18)
		a.equal(endCount, beginCount)
		a.isFalse(profiler.begin("ATD.Runtime.player-123"))
		a.equal(beginCount, 18)
	end),
	Harness.case("early failure values and thrown authority errors end the matching scope", function(a)
		local beginCount, endCount = 0, 0
		local profiler = ProfileScope.create({
			beginScope = function()
				beginCount += 1
			end,
			endScope = function()
				endCount += 1
			end,
		})
		local failed = { ok = false }
		a.equal(
			profiler.call("ATD.Runtime.Step", function()
				return failed
			end),
			failed
		)
		local expectedError = {}
		local succeeded, actualError = pcall(profiler.call, "ATD.Runtime.Step", function()
			error(expectedError, 0)
		end)
		a.isFalse(succeeded)
		a.equal(actualError, expectedError)
		a.equal(beginCount, 2)
		a.equal(endCount, 2)
	end),
	Harness.case("nested scopes end in stack order even when work fails", function(a)
		local events = {}
		local profiler = ProfileScope.create({
			beginScope = function(label)
				table.insert(events, label)
			end,
			endScope = function()
				table.insert(events, "end")
			end,
		})
		local success = pcall(profiler.call, "ATD.Runtime.Step", function()
			profiler.call("ATD.Runtime.Spawn", function()
				error("expected failure")
			end)
		end)
		a.isFalse(success)
		a.equal(table.concat(events, ","), "ATD.Runtime.Step,ATD.Runtime.Spawn,end,end")
	end),
	Harness.case("engine begin failure disables repeated attempts without blocking work", function(a)
		local begins, ends, calls = 0, 0, 0
		local profiler = ProfileScope.create({
			beginScope = function()
				begins += 1
				error("engine unavailable")
			end,
			endScope = function()
				ends += 1
			end,
		})
		for _ = 1, 3 do
			profiler.call("ATD.Runtime.Step", function()
				calls += 1
			end)
		end
		a.equal(begins, 1)
		a.equal(ends, 0)
		a.equal(calls, 3)
	end),
	Harness.case("engine end failure is isolated and preserves successful work identity", function(a)
		local begins, ends = 0, 0
		local expected = {}
		local profiler = ProfileScope.create({
			beginScope = function()
				begins += 1
			end,
			endScope = function()
				ends += 1
				error("engine unavailable")
			end,
		})
		for _ = 1, 2 do
			a.equal(
				profiler.call("ATD.Runtime.Step", function()
					return expected
				end),
				expected
			)
		end
		a.equal(begins, 1)
		a.equal(ends, 1)
	end),
})
