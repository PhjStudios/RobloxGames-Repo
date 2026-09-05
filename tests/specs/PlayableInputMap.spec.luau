--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)

local PlayableInputMap = require(script.Parent.Parent.ProductionClientPlayable.PlayableInputMap)

local newForTests = PlayableInputMap.newForTests
if newForTests == nil then
	error("[ATD_TEST_FIXTURE][code=PLAYABLE_INPUT_CONSTRUCTOR_MISSING]", 0)
end

local function withInput(
	callback: (any, { any }, ((any, boolean) -> ())?, ((string) -> ())?, { number }) -> (),
	actionCallback: ((any) -> ())?
)
	local actions = {}
	local inputListener: ((any, boolean) -> ())? = nil
	local preferredListener: ((string) -> ())? = nil
	local disconnects = { 0, 0 }
	local connectionIndex = 0
	local result = (newForTests :: any)(actionCallback or function(action)
		table.insert(actions, action)
	end, {
		initialPreferredInput = "Desktop",
		connectInputBegan = function(listener)
			inputListener = listener
			connectionIndex += 1
			local ownIndex = connectionIndex
			return RobloxAdapter.createConnection(function()
				disconnects[ownIndex] += 1
			end) :: RBXScriptConnection
		end,
		connectPreferredInputChanged = function(listener)
			preferredListener = listener
			connectionIndex += 1
			local ownIndex = connectionIndex
			return RobloxAdapter.createConnection(function()
				disconnects[ownIndex] += 1
			end) :: RBXScriptConnection
		end,
	})
	if not result.ok then
		error("playable input fixture failed", 0)
	end
	local succeeded, problem = pcall(callback, result.value, actions, inputListener, preferredListener, disconnects)
	pcall(function()
		result.value:cleanup()
	end)
	if not succeeded then
		error(problem, 0)
	end
end

return TestHarness.suite("playable Match semantic input map", {
	TestHarness.case("starts with bounded production connections and desktop Match hints", function(assertions)
		withInput(function(inputMap)
			local metrics = inputMap:getMetrics()
			assertions.isTrue(table.isfrozen(PlayableInputMap))
			assertions.isTrue(table.isfrozen(metrics))
			assertions.equal(metrics.context, "Match")
			assertions.equal(metrics.preferredInput, "Desktop")
			assertions.equal(metrics.connectionCount, 2)
			assertions.contains(metrics.hint, "1–5")
			assertions.equal(metrics.actionCount, 0)
		end)
	end),

	TestHarness.case("normalizes ready and replay without sharing gameplay authority", function(assertions)
		withInput(function(inputMap, actions, inputListener)
			local listener = inputListener :: any
			assertions.isTrue(inputMap:setContext("Ready").ok)
			listener({ keyCode = "R", inputType = "Keyboard" }, false)
			assertions.equal(#actions, 1)
			assertions.equal(actions[1].kind, "Ready")
			assertions.equal(actions[1].source, "Desktop")
			assertions.isNil(actions[1].slot)
			listener({ keyCode = "ButtonA", inputType = "Gamepad1" }, false)
			assertions.equal(#actions, 2)
			assertions.equal(actions[2].kind, "Ready")
			assertions.equal(actions[2].source, "Gamepad")
			listener({ keyCode = "Return", inputType = "Keyboard" }, true)
			assertions.equal(#actions, 2)
			inputMap:setContext("Results")
			listener({ keyCode = "ButtonA", inputType = "Gamepad1" }, false)
			assertions.equal(actions[3].kind, "Replay")
			assertions.equal(actions[3].source, "Gamepad")
			assertions.equal(inputMap:getMetrics().preferredInput, "Gamepad")
		end)
	end),

	TestHarness.case("maps desktop placement hotbar confirm rotate and cancel semantics", function(assertions)
		withInput(function(inputMap, actions)
			inputMap:setContext("Placement")
			local first = inputMap:handleRaw({ keyCode = "One", inputType = "Keyboard" }, false)
			assertions.isTrue(first.ok)
			assertions.equal(first.value.kind, "SelectHotbar")
			assertions.equal(first.value.slot, 1)

			local confirm = inputMap:handleRaw({
				keyCode = "Unknown",
				inputType = "MouseButton1",
				position = Vector2.new(120, 240),
			}, false)
			assertions.equal(confirm.value.kind, "Confirm")
			assertions.equal(confirm.value.screenPosition, Vector2.new(120, 240))
			assertions.equal(inputMap:handleRaw({ keyCode = "R", inputType = "Keyboard" }, false).value.kind, "Rotate")
			assertions.equal(inputMap:handleRaw({ keyCode = "Q", inputType = "Keyboard" }, false).value.kind, "Cancel")
			assertions.equal(#actions, 4)
		end)
	end),

	TestHarness.case("accepts numpad Enter for ready placement and replay", function(assertions)
		withInput(function(inputMap, actions)
			inputMap:setContext("Ready")
			assertions.equal(
				inputMap:handleRaw({ keyCode = "KeypadEnter", inputType = "Keyboard" }, false).value.kind,
				"Ready"
			)
			inputMap:setContext("Placement")
			local keypadConfirm = inputMap:handleRaw({
				keyCode = "KeypadEnter",
				inputType = "Keyboard",
				position = Vector2.zero,
			}, false).value
			assertions.equal(keypadConfirm.kind, "Confirm")
			assertions.isNil(keypadConfirm.screenPosition)
			local returnConfirm = inputMap:handleRaw({
				keyCode = "Return",
				inputType = "Keyboard",
				position = Vector2.zero,
			}, false).value
			assertions.equal(returnConfirm.kind, "Confirm")
			assertions.isNil(returnConfirm.screenPosition)
			inputMap:setContext("Results")
			assertions.equal(
				inputMap:handleRaw({ keyCode = "KeypadEnter", inputType = "Keyboard" }, false).value.kind,
				"Replay"
			)
			assertions.equal(#actions, 4)
		end)
	end),

	TestHarness.case("reserves Match ButtonA for focused UI and maps gamepad control paths", function(assertions)
		withInput(function(inputMap, actions)
			local focusedActivation = inputMap:handleRaw({ keyCode = "ButtonA", inputType = "Gamepad1" }, false)
			assertions.isTrue(focusedActivation.ok)
			assertions.isNil(focusedActivation.value)
			assertions.equal(#actions, 0)
			assertions.equal(
				inputMap:handleRaw({ keyCode = "DPadLeft", inputType = "Gamepad1" }, false).value.direction,
				-1
			)
			assertions.equal(
				inputMap:handleRaw({ keyCode = "DPadRight", inputType = "Gamepad1" }, false).value.kind,
				"CycleTower"
			)
			inputMap:setContext("Placement")
			assertions.equal(
				inputMap:handleRaw({ keyCode = "ButtonL1", inputType = "Gamepad1" }, false).value.direction,
				-1
			)
			assertions.equal(
				inputMap:handleRaw({ keyCode = "ButtonR1", inputType = "Gamepad1" }, false).value.direction,
				1
			)
			assertions.equal(
				inputMap:handleRaw({ keyCode = "ButtonR2", inputType = "Gamepad1" }, false).value.kind,
				"Rotate"
			)
			local gamepadConfirm = inputMap:handleRaw({
				keyCode = "ButtonA",
				inputType = "Gamepad1",
				position = Vector2.zero,
			}, false).value
			assertions.equal(gamepadConfirm.kind, "Confirm")
			assertions.isNil(gamepadConfirm.screenPosition)
			assertions.equal(
				inputMap:handleRaw({ keyCode = "ButtonB", inputType = "Gamepad1" }, false).value.kind,
				"Cancel"
			)

			inputMap:setContext("Tower")
			assertions.equal(
				inputMap:handleRaw({ keyCode = "DPadLeft", inputType = "Gamepad1" }, false).value.direction,
				-1
			)
			assertions.equal(
				inputMap:handleRaw({ keyCode = "ButtonY", inputType = "Gamepad1" }, false).value.kind,
				"Upgrade"
			)
			assertions.equal(
				inputMap:handleRaw({ keyCode = "ButtonX", inputType = "Gamepad1" }, false).value.kind,
				"Sell"
			)
			assertions.equal(
				inputMap:handleRaw({ keyCode = "ButtonR1", inputType = "Gamepad1" }, false).value.kind,
				"Retarget"
			)
			assertions.equal(
				inputMap:handleRaw({ keyCode = "DPadDown", inputType = "Gamepad1" }, false).value.kind,
				"FocusBase"
			)
		end)
	end),

	TestHarness.case("lets touch UI emit only actions available in the current context", function(assertions)
		withInput(function(inputMap, actions)
			inputMap:setPreferredInput("Touch")
			inputMap:setContext("Match")
			local slot = inputMap:emit("SelectHotbar", { slot = 3 })
			assertions.isTrue(slot.ok)
			assertions.equal(slot.value.source, "Touch")
			assertions.equal(slot.value.slot, 3)
			assertions.isTrue(inputMap:emit("SelectHotbar", { slot = 5 }).ok)
			assertions.isFalse(inputMap:emit("Confirm").ok)

			inputMap:setContext("Tower")
			assertions.equal(inputMap:emit("Upgrade").value.kind, "Upgrade")
			assertions.equal(inputMap:emit("Retarget").value.kind, "Retarget")
			assertions.equal(inputMap:emit("Sell").value.kind, "Sell")
			assertions.equal(inputMap:emit("Cancel").value.kind, "Cancel")
			assertions.equal(#actions, 6)
		end)
	end),

	TestHarness.case("keyboard brackets inspect owned towers without a pointing device", function(assertions)
		withInput(function(inputMap)
			inputMap:setContext("Match")
			local nextTower = inputMap:handleRaw({ keyCode = "RightBracket", inputType = "Keyboard" }, false)
			assertions.equal(nextTower.value.kind, "CycleTower")
			assertions.equal(nextTower.value.direction, 1)
			inputMap:setContext("Tower")
			assertions.equal(
				inputMap:handleRaw({ keyCode = "LeftBracket", inputType = "Keyboard" }, false).value.direction,
				-1
			)
		end)
	end),

	TestHarness.case("updates concise device and context hints without emitting an action", function(assertions)
		withInput(function(inputMap, actions, _inputListener, preferredListener)
			local listener = preferredListener :: any
			inputMap:setContext("Placement")
			assertions.contains(inputMap:getHints().value, "Click/Enter")
			listener("Touch")
			assertions.contains(inputMap:getHints().value, "Tap position")
			listener("Gamepad")
			assertions.contains(inputMap:getHints().value, "A Confirm")
			inputMap:setContext("Results")
			assertions.contains(inputMap:getHints().value, "A Play Again")
			assertions.equal(#actions, 0)
		end)
	end),

	TestHarness.case("rejects malformed records and contains callback failures", function(assertions)
		withInput(function(inputMap)
			assertions.isFalse(inputMap:setContext("PrivateAdmin").ok)
			assertions.isFalse(inputMap:setPreferredInput("Voice").ok)
			assertions.isFalse(inputMap:handleRaw(false, false).ok)
			assertions.isFalse(inputMap:emit("SelectHotbar", { slot = 0 }).ok)
			assertions.isTrue(inputMap:handleRaw({ keyCode = 4 }, false).ok)
		end)

		withInput(function(inputMap)
			assertions.isFalse(inputMap:emit("FocusBase").ok)
			assertions.equal(inputMap:getMetrics().actionCount, 0)
		end, function()
			error("private callback failure", 0)
		end)
	end),

	TestHarness.case("disconnects both listeners and becomes inert on idempotent cleanup", function(assertions)
		withInput(function(inputMap, actions, inputListener, preferredListener, disconnects)
			local rawListener = inputListener :: any
			local preferred = preferredListener :: any
			assertions.isTrue(inputMap:cleanup().ok)
			assertions.isTrue(inputMap:getMetrics().cleaned)
			assertions.equal(inputMap:getMetrics().connectionCount, 0)
			assertions.equal(disconnects[1], 1)
			assertions.equal(disconnects[2], 1)
			rawListener({ keyCode = "One", inputType = "Keyboard" }, false)
			preferred("Touch")
			assertions.equal(#actions, 0)
			assertions.isFalse(inputMap:emit("FocusBase").ok)
			assertions.isTrue(inputMap:cleanup().ok)
		end)
	end),
})
