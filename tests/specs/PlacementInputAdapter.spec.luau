--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local PlacementInputAdapter = require(script.Parent.Parent.ProductionClientPlacement.PlacementInputAdapter)

local function adapter(): any
	local result = PlacementInputAdapter.new()
	if not result.ok then
		error("input adapter fixture failed", 0)
	end
	return result.value
end

return TestHarness.suite("Phase 13 cross-platform placement input adapter", {
	TestHarness.case("starts with deterministic desktop and centered reticle state", function(assertions)
		local value = adapter()
		local metrics = value:getMetrics()
		assertions.isTrue(table.isfrozen(metrics))
		assertions.equal(metrics.preferredInput, "Desktop")
		assertions.equal(metrics.viewport, Vector2.new(1280, 720))
		assertions.equal(metrics.reticle, Vector2.new(640, 360))
		assertions.equal(metrics.activeTouchCount, 0)
	end),

	TestHarness.case("emits desktop pointer confirm cancel rotate and slot actions", function(assertions)
		local value = adapter()
		local positioned = value:desktopPointer(Vector2.new(100, 200))
		assertions.isTrue(positioned.ok)
		assertions.equal(positioned.value.kind, "Position")
		assertions.equal(positioned.value.screenPosition, Vector2.new(100, 200))
		assertions.equal(value:confirm("Desktop").value.kind, "Confirm")
		assertions.equal(value:cancel("Desktop").value.kind, "Cancel")
		assertions.equal(value:rotate("Desktop", -1).value.rotationDegrees, -15)
		assertions.equal(value:selectSlot("Desktop", 5).value.slot, 5)
		assertions.isFalse(value:confirm("Gamepad").ok)
	end),

	TestHarness.case("turns a completed single touch tap into position only", function(assertions)
		local value = adapter()
		value:setPreferredInput("Touch")
		assertions.isTrue(value:touchBegan(1, Vector2.new(30, 40), false).ok)
		local ended = value:touchEnded(1, Vector2.new(35, 45))
		assertions.isTrue(ended.ok)
		assertions.equal(ended.value.kind, "Position")
		assertions.equal(ended.value.source, "Touch")
		assertions.equal(value:getMetrics().confirmActionCount, 0)
		assertions.equal(value:confirm("Touch").value.kind, "Confirm")
		assertions.equal(value:getMetrics().confirmActionCount, 1)
	end),

	TestHarness.case("never positions or confirms from touch camera drag", function(assertions)
		local value = adapter()
		value:setPreferredInput("Touch")
		value:touchBegan(1, Vector2.new(10, 10), false)
		value:touchChanged(1, Vector2.new(40, 10))
		local ended = value:touchEnded(1, Vector2.new(50, 10))
		assertions.isTrue(ended.ok)
		assertions.isNil(ended.value)
		assertions.equal(value:getMetrics().positionActionCount, 0)
		assertions.equal(value:getMetrics().confirmActionCount, 0)
	end),

	TestHarness.case("never positions or confirms from pinch or multitouch gestures", function(assertions)
		local value = adapter()
		value:setPreferredInput("Touch")
		value:touchBegan(1, Vector2.new(10, 10), false)
		value:touchBegan(2, Vector2.new(20, 20), false)
		assertions.equal(value:getMetrics().gestureTouchCount, 2)
		assertions.isNil(value:touchEnded(1, Vector2.new(10, 10)).value)
		assertions.isNil(value:touchEnded(2, Vector2.new(20, 20)).value)
		assertions.equal(value:getMetrics().actionCount, 0)
	end),

	TestHarness.case("ignores UI-processed and cancelled touches", function(assertions)
		local value = adapter()
		value:setPreferredInput("Touch")
		value:touchBegan(1, Vector2.new(10, 10), true)
		assertions.isNil(value:touchEnded(1, Vector2.new(10, 10)).value)
		value:touchBegan(2, Vector2.new(20, 20), false)
		assertions.isTrue(value:touchCancelled(2).ok)
		assertions.equal(value:getMetrics().activeTouchCount, 0)
		assertions.equal(value:getMetrics().actionCount, 0)
	end),

	TestHarness.case("bounds active touches and rejects duplicate identities", function(assertions)
		local value = adapter()
		value:setPreferredInput("Touch")
		for touchId = 1, PlacementInputAdapter.MAX_ACTIVE_TOUCHES do
			assertions.isTrue(value:touchBegan(touchId, Vector2.new(touchId, touchId), false).ok)
		end
		assertions.isFalse(value:touchBegan(5, Vector2.new(), false).ok)
		assertions.isFalse(value:touchBegan(1, Vector2.new(), false).ok)
		assertions.equal(value:getMetrics().activeTouchCount, 4)
	end),

	TestHarness.case("moves a deterministic bounded gamepad reticle", function(assertions)
		local value = adapter()
		value:setViewport(Vector2.new(100, 80))
		value:setPreferredInput("Gamepad")
		local initial = value:getReticle().value
		assertions.equal(initial, Vector2.new(100, 80))
		assertions.isNil(value:gamepadStep(Vector2.new(0.1, 0), 0.05).value)
		local moved = value:gamepadStep(Vector2.new(-1, -1), 0.1)
		assertions.isTrue(moved.ok)
		assertions.equal(moved.value.kind, "Position")
		assertions.isTrue(moved.value.screenPosition.X < initial.X)
		assertions.isTrue(moved.value.screenPosition.Y < initial.Y)

		for _ = 1, 20 do
			value:gamepadStep(Vector2.new(-1, -1), 0.1)
		end
		assertions.equal(value:getReticle().value, Vector2.new(0, 0))
		assertions.equal(value:cycleSlot(1).value.kind, "CycleSlot")
		assertions.equal(value:confirm("Gamepad").value.kind, "Confirm")
	end),

	TestHarness.case(
		"changes preferred-device hints without resetting reticle or emitting actions",
		function(assertions)
			local value = adapter()
			value:setPreferredInput("Gamepad")
			value:gamepadStep(Vector2.new(1, 0), 0.05)
			local reticle = value:getReticle().value
			local actions = value:getMetrics().actionCount
			assertions.isTrue(value:setPreferredInput("Touch").ok)
			assertions.equal(value:getReticle().value, reticle)
			assertions.equal(value:getMetrics().actionCount, actions)
			assertions.isTrue(value:setPreferredInput("Desktop").ok)
		end
	),

	TestHarness.case("rejects malformed numeric input and cleans all touch state", function(assertions)
		local value = adapter()
		assertions.isFalse(value:setViewport(Vector2.new(0, 10)).ok)
		assertions.isFalse(value:desktopPointer(Vector2.new(0 / 0, 0)).ok)
		assertions.isFalse(value:rotate("Desktop", 0).ok)
		assertions.isFalse(value:selectSlot("Desktop", 6).ok)
		value:setPreferredInput("Touch")
		value:touchBegan(1, Vector2.new(), false)
		assertions.isTrue(value:cleanup().ok)
		assertions.equal(value:getMetrics().activeTouchCount, 0)
		assertions.isTrue(value:getMetrics().cleaned)
		assertions.isFalse(value:touchEnded(1, Vector2.new()).ok)
		assertions.isTrue(value:cleanup().ok)
	end),
})
