--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Window = require(script.Parent.Parent.Support.PerformanceWindow)

return TestHarness.suite("PerformanceWindow", {
	TestHarness.case("empty observations cannot pass a timing budget", function(a)
		local window = Window.new()
		window:add(0 / 0)
		local summary = window:summary()
		a.isFalse(summary.available)
		a.equal(summary.count, 0)
		a.isNil(summary.mean)
		a.isNil(summary.maximum)
		a.isNil(summary.p95)
		a.equal(Window.classify(summary.p95, 10, 15, 20), "Unavailable")
		window:add(0)
		a.isTrue(window:summary().available)
		a.equal(Window.classify(window:summary().p95, 10, 15, 20), "Target")
	end),
	TestHarness.case("bounded retention labels percentiles without losing lifetime maximum", function(a)
		local window = Window.new(4)
		window:add(100)
		for value = 1, 8 do
			window:add(value)
		end
		local summary = window:summary()
		a.equal(summary.count, 9)
		a.equal(summary.retained, 4)
		a.equal(summary.maximum, 100)
		a.equal(summary.p50, 6)
		a.equal(summary.p95, 8)
		a.equal(summary.percentileScope, "LatestWindow")
	end),
	TestHarness.case("rejects nonfinite and negative samples without poisoning reports", function(a)
		local window = Window.new()
		for _, value in { -1, math.huge, 0 / 0, "16" } do
			a.isFalse(window:add(value))
		end
		window:add(16)
		a.equal(window:summary().rejected, 4)
		a.equal(window:summary().mean, 16)
	end),
	TestHarness.case("payload estimates include named keys escaped strings and vectors", function(a)
		a.equal(Window.payloadEstimate({ x = 1 }), 7)
		a.equal(Window.payloadEstimate({ x = "\n" }), 14)
		a.equal(Window.payloadEstimate(Vector3.new(1, 2, 3)), 7)
		local bytes = Window.payloadEstimate({ point = Vector3.new(1, 2, 3), value = "example" })
		a.isTrue(bytes ~= nil and bytes > 30)
	end),
	TestHarness.case("rejects cycles huge graphs and unsupported payloads", function(a)
		local cycle = {}
		cycle.self = cycle
		a.isNil(Window.payloadEstimate(cycle))
		a.isNil(Window.payloadEstimate(table.create(5000, 1)))
		a.isNil(Window.payloadEstimate(function() end))
		a.isNil(Window.payloadEstimate(math.huge))
		local iterated = false
		a.isNil(Window.payloadEstimate(setmetatable({}, {
			__iter = function()
				iterated = true
				error("must not invoke payload code")
			end,
		})))
		a.isFalse(iterated)
	end),
	TestHarness.case("budget classification does not convert missing measurements to success", function(a)
		a.equal(Window.classify(0 / 0, 10, 15, 20), "Unavailable")
		a.equal(Window.classify(10, 10, 15, 20), "Target")
		a.equal(Window.classify(12, 10, 15, 20), "AboveTarget")
		a.equal(Window.classify(17, 10, 15, 20), "Warning")
		a.equal(Window.classify(21, 10, 15, 20), "Fail")
	end),
})
