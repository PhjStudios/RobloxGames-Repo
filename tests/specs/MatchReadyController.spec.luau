--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local ClientRequestTracker = require(script.Parent.Parent.ProductionClientNetworking.ClientRequestTracker)
local MatchReadyController = require(script.Parent.Parent.ProductionClientMatch.MatchReadyController)
local MatchReadyView = require(script.Parent.Parent.ProductionClientMatch.MatchReadyView)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local ProductionRemotes = require(ReplicatedStorage.Shared.network.ProductionRemotes)

type Assertions = TestHarness.Assertions
type Controller = MatchReadyController.Controller
type ActionHandler = MatchReadyController.ActionHandler

type Signal = {
	connect: (self: Signal, listener: (unknown, ...unknown) -> ()) -> RBXScriptConnection,
	fire: (self: Signal, value: unknown, ...unknown) -> (),
	force: (self: Signal, value: unknown, ...unknown) -> (),
}

type Rig = {
	controller: Controller,
	definition: any,
	tracker: ClientRequestTracker.Tracker,
	parent: Folder,
	order: { string },
	getFires: { any },
	readyFires: { any },
	snapshotSignal: Signal,
	getResponseSignal: Signal,
	readyResponseSignal: Signal,
	activation: (() -> ())?,
	actionHandler: ActionHandler?,
	actionName: string?,
	createTouchButton: boolean?,
	keyboard: unknown,
	gamepad: unknown,
	renderStep: (() -> ())?,
	serverTime: unknown,
	timeThrows: boolean,
	unbindCount: number,
	disconnectCount: number,
}

local logger = Log.new(EnvironmentContext.new("client", "Match", 0, false))
local ACTION_BEGIN = "TestBegin"
local ACTION_END = "TestEnd"
local ACTION_PASS = "TestPass"
local ACTION_SINK = "TestSink"
local KEYBOARD_KEY = "TestR"
local GAMEPAD_KEY = "TestButtonA"
local newTrackerForTests = ClientRequestTracker.newForTests
local newControllerForTests = MatchReadyController.newForTests
local newViewForTests = MatchReadyView.newForTests
if newTrackerForTests == nil or newControllerForTests == nil or newViewForTests == nil then
	error("[ATD_TEST_FIXTURE][code=MATCH_READY_CONTROLLER_TEST_SEAM_MISSING]", 0)
end

local function makeSnapshot(
	revision: number,
	state: string,
	ready: boolean,
	matchId: string?,
	deadline: number?
): { [string]: unknown }
	local snapshot: { [string]: unknown } = {
		matchId = matchId or "match:controller-test",
		revision = revision,
		state = state,
		participants = {
			{ userId = 10, state = "Active", ready = ready },
			{ userId = 20, state = "Active", ready = false },
		},
	}
	if state == "ReadyCheck" then
		snapshot.deadlineServerTime = deadline or 145
	end
	return snapshot
end

local function successWire(request: any, payload: unknown): { [string]: unknown }
	return {
		requestId = request.requestId,
		state = "Success",
		payload = payload,
	}
end

local function rejectedWire(request: any, code: string): { [string]: unknown }
	return {
		requestId = request.requestId,
		state = "Rejected",
		error = { code = code },
	}
end

local function makeSignal(rig: Rig, orderName: string): Signal
	local listener: ((unknown, ...unknown) -> ())? = nil
	local active = false
	local signal = {} :: Signal
	function signal:connect(nextListener)
		table.insert(rig.order, orderName)
		listener = nextListener
		active = true
		return RobloxAdapter.createConnection(function()
			if active then
				active = false
				rig.disconnectCount += 1
			end
		end) :: RBXScriptConnection
	end
	function signal:fire(value, ...)
		if active and listener ~= nil then
			(listener :: (unknown, ...unknown) -> ())(value, ...)
		end
	end
	function signal:force(value, ...)
		if listener ~= nil then
			(listener :: (unknown, ...unknown) -> ())(value, ...)
		end
	end
	return signal
end

local function child(parent: Instance, name: string, className: string): Instance
	local value = parent:FindFirstChild(name)
	if value == nil or value.ClassName ~= className then
		error("[ATD_TEST_FIXTURE][code=MATCH_READY_CONTROLLER_VIEW_CHILD_MISSING]", 0)
	end
	return value
end

local function getPanel(rig: Rig): Frame
	local gui = child(rig.parent, MatchReadyView.GUI_NAME, "ScreenGui")
	return child(gui, "ReadyPanel", "Frame") :: Frame
end

local function labelText(rig: Rig, name: string): string
	return (child(getPanel(rig), name, "TextLabel") :: TextLabel).Text
end

local function button(rig: Rig): TextButton
	return child(getPanel(rig), "ReadyButton", "TextButton") :: TextButton
end

local function activate(rig: Rig)
	local callback = rig.activation
	if callback == nil then
		error("[ATD_TEST_FIXTURE][code=MATCH_READY_CONTROLLER_ACTIVATION_MISSING]", 0)
	end
	callback()
end

local function renderStep(rig: Rig)
	local callback = rig.renderStep
	if callback == nil then
		error("[ATD_TEST_FIXTURE][code=MATCH_READY_CONTROLLER_RENDER_STEP_MISSING]", 0)
	end
	callback()
end

local function beginAction(rig: Rig): unknown
	local callback = rig.actionHandler
	if callback == nil then
		error("[ATD_TEST_FIXTURE][code=MATCH_READY_CONTROLLER_ACTION_MISSING]", 0)
	end
	return callback("ignored", ACTION_BEGIN, nil)
end

local function makeRig(): Rig
	local requestCounter = 0
	local trackerResult = (newTrackerForTests :: ClientRequestTracker.TestConstructor)(
		ProductionRemotes,
		"Match",
		function(): string
			requestCounter += 1
			return `ctrl{string.format("%04d", requestCounter)}`
		end
	)
	if not trackerResult.ok then
		error("[ATD_TEST_FIXTURE][code=MATCH_READY_CONTROLLER_TRACKER_FAILED]", 0)
	end

	local rig = {
		controller = nil :: any,
		definition = nil,
		tracker = trackerResult.value,
		parent = Instance.new("Folder") :: Folder,
		order = {},
		getFires = {},
		readyFires = {},
		snapshotSignal = nil :: any,
		getResponseSignal = nil :: any,
		readyResponseSignal = nil :: any,
		activation = nil,
		actionHandler = nil,
		actionName = nil,
		createTouchButton = nil,
		keyboard = nil,
		gamepad = nil,
		renderStep = nil,
		serverTime = 100,
		timeThrows = false,
		unbindCount = 0,
		disconnectCount = 0,
	} :: Rig
	rig.parent.Name = "MatchReadyControllerTestParent"
	rig.snapshotSignal = makeSignal(rig, "snapshot-event")
	rig.getResponseSignal = makeSignal(rig, "get-response")
	rig.readyResponseSignal = makeSignal(rig, "ready-response")

	local viewResult = (newViewForTests :: MatchReadyView.TestConstructor)(rig.parent, function(_button, callback)
		table.insert(rig.order, "activated")
		rig.activation = callback
		local active = true
		return RobloxAdapter.createConnection(function()
			if active then
				active = false
				rig.disconnectCount += 1
			end
		end) :: RBXScriptConnection
	end)
	if not viewResult.ok then
		error("[ATD_TEST_FIXTURE][code=MATCH_READY_CONTROLLER_VIEW_FAILED]", 0)
	end

	local getDefinition = ProductionRemotes:get("GetMatchSnapshot")
	local readyDefinition = ProductionRemotes:get("SubmitReady")
	if getDefinition == nil or readyDefinition == nil then
		error("[ATD_TEST_FIXTURE][code=MATCH_READY_CONTROLLER_DEFINITION_MISSING]", 0)
	end
	local dependencies: MatchReadyController.Dependencies = {
		localUserId = 10,
		tracker = rig.tracker,
		getSnapshot = {
			definition = getDefinition,
			connectResponse = function(listener)
				return rig.getResponseSignal:connect(listener)
			end,
			fire = function(envelope)
				table.insert(rig.order, "fire-get")
				table.insert(rig.getFires, envelope)
			end,
		},
		submitReady = {
			definition = readyDefinition,
			connectResponse = function(listener)
				return rig.readyResponseSignal:connect(listener)
			end,
			fire = function(envelope)
				table.insert(rig.order, "fire-ready")
				table.insert(rig.readyFires, envelope)
			end,
		},
		snapshotEvent = {
			connectEvent = function(listener)
				return rig.snapshotSignal:connect(listener)
			end,
		},
		view = viewResult.value,
		bindAction = function(actionName, handler, createTouchButton, keyboard, gamepad)
			table.insert(rig.order, "bind-action")
			rig.actionName = actionName
			rig.actionHandler = handler
			rig.createTouchButton = createTouchButton
			rig.keyboard = keyboard
			rig.gamepad = gamepad
		end,
		unbindAction = function(actionName)
			if actionName ~= MatchReadyController.ACTION_NAME then
				error("[ATD_TEST_FIXTURE][code=MATCH_READY_CONTROLLER_WRONG_UNBIND]", 0)
			end
			rig.unbindCount += 1
		end,
		connectRenderStep = function(callback)
			table.insert(rig.order, "render-step")
			rig.renderStep = callback
			local active = true
			return RobloxAdapter.createConnection(function()
				if active then
					active = false
					rig.disconnectCount += 1
				end
			end) :: RBXScriptConnection
		end,
		getServerTimeNow = function(): unknown
			if rig.timeThrows then
				error("PRIVATE_MATCH_READY_CONTROLLER_TIME", 0)
			end
			return rig.serverTime
		end,
		actionBegin = ACTION_BEGIN,
		actionPass = ACTION_PASS,
		actionSink = ACTION_SINK,
		keyboardKey = KEYBOARD_KEY,
		gamepadKey = GAMEPAD_KEY,
	}
	local controllerResult = (newControllerForTests :: MatchReadyController.TestConstructor)(logger, dependencies)
	if not controllerResult.ok then
		error("[ATD_TEST_FIXTURE][code=MATCH_READY_CONTROLLER_CREATION_FAILED]", 0)
	end
	rig.controller = controllerResult.value
	rig.definition = rig.controller:getServiceDefinition()
	rig.definition.initialize()
	rig.definition.start()
	return rig
end

local function completeInitial(rig: Rig, snapshot: { [string]: unknown }?)
	local selected = snapshot or makeSnapshot(1, "ReadyCheck", false, nil, nil)
	rig.getResponseSignal:fire(successWire(rig.getFires[1], selected))
end

local function shutdown(rig: Rig)
	rig.definition.shutdown()
	rig.parent:Destroy()
end

local function keyCount(value: { [any]: unknown }): number
	local count = 0
	for _ in next, value do
		count += 1
	end
	return count
end

return TestHarness.suite("Match ready client controller", {
	TestHarness.case("connects every inbound listener before the exact initial recovery request", function(assertions)
		assertions.isTrue(table.isfrozen(MatchReadyController))
		assertions.equal(MatchReadyController.SERVICE_NAME, "MatchReadyController")
		assertions.equal(MatchReadyController.ACTION_NAME, "ATDMatchReady")
		local rig = makeRig()
		assertions.equal(rig.controller:getState(), "Started")
		assertions.equal(rig.definition.name, "MatchReadyController")
		assertions.equal(
			table.concat(rig.order, ","),
			"snapshot-event,get-response,ready-response,activated,bind-action,render-step,fire-get"
		)
		assertions.equal(#rig.getFires, 1)
		assertions.equal(keyCount(rig.getFires[1]), 2)
		assertions.equal(keyCount(rig.getFires[1].payload), 0)
		assertions.equal(rig.tracker:getStats().pendingCount, 1)
		assertions.equal(rig.actionName, "ATDMatchReady")
		assertions.isFalse(rig.createTouchButton)
		assertions.equal(rig.keyboard, KEYBOARD_KEY)
		assertions.equal(rig.gamepad, GAMEPAD_KEY)
		shutdown(rig)
	end),

	TestHarness.case(
		"handles the event-before-response race and terminalizes an equal Ready response",
		function(assertions)
			local rig = makeRig()
			local first = makeSnapshot(1, "ReadyCheck", false, nil, nil)
			rig.snapshotSignal:fire({ payload = first })
			assertions.equal(labelText(rig, "StateLabel"), "State: Ready check")
			rig.getResponseSignal:fire(successWire(rig.getFires[1], first))
			assertions.equal(rig.tracker:getStats().pendingCount, 0)
			activate(rig)
			assertions.equal(#rig.readyFires, 1)
			assertions.equal(labelText(rig, "RequestLabel"), "Request: Pending")
			assertions.equal(rig.tracker:getStats().pendingCount, 1)
			local accepted = makeSnapshot(2, "ReadyCheck", true, nil, nil)
			rig.snapshotSignal:fire({ payload = accepted })
			assertions.equal(labelText(rig, "RequestLabel"), "Request: Accepted")
			assertions.equal(rig.tracker:getStats().pendingCount, 1)
			rig.readyResponseSignal:fire(successWire(rig.readyFires[1], accepted))
			assertions.equal(rig.tracker:getStats().pendingCount, 0)
			assertions.equal(labelText(rig, "RequestLabel"), "Request: Accepted")
			shutdown(rig)
		end
	),

	TestHarness.case(
		"ignores duplicate stale and foreign snapshots and sends the smallest Ready payload",
		function(assertions)
			local rig = makeRig()
			local current = makeSnapshot(3, "ReadyCheck", false, nil, nil)
			completeInitial(rig, current)
			rig.snapshotSignal:fire({ payload = makeSnapshot(3, "ReadyCheck", true, nil, nil) })
			rig.snapshotSignal:fire({ payload = makeSnapshot(2, "ReadyCheck", true, nil, nil) })
			rig.snapshotSignal:fire({ payload = makeSnapshot(4, "ReadyCheck", true, "match:foreign", nil) })
			activate(rig)
			assertions.equal(#rig.readyFires, 1)
			local payload = rig.readyFires[1].payload
			assertions.equal(keyCount(payload), 2)
			assertions.equal(payload.matchId, "match:controller-test")
			assertions.equal(payload.observedRevision, 3)
			assertions.isNil(payload.userId)
			assertions.isNil(payload.ready)
			assertions.equal(labelText(rig, "PlayerRow1"), "Player 1 (You): Waiting")
			shutdown(rig)
		end
	),

	TestHarness.case("coalesces Activated keyboard and gamepad paths behind local Pending", function(assertions)
		local rig = makeRig()
		local handler = rig.actionHandler :: ActionHandler
		assertions.equal(handler("ignored", ACTION_END, nil), ACTION_PASS)
		assertions.equal(beginAction(rig), ACTION_PASS)
		assertions.equal(#rig.readyFires, 0)
		completeInitial(rig, nil)
		assertions.equal(beginAction(rig), ACTION_SINK)
		activate(rig)
		assertions.equal(handler("ignored", ACTION_BEGIN, nil), ACTION_PASS)
		assertions.equal(#rig.readyFires, 1)
		assertions.isFalse(button(rig).Active)
		assertions.isFalse(button(rig).Selectable)
		rig.snapshotSignal:fire({ payload = makeSnapshot(2, "PreWave", true, nil, nil) })
		assertions.equal(beginAction(rig), ACTION_PASS)
		assertions.equal(#rig.readyFires, 1)
		shutdown(rig)
	end),

	TestHarness.case("uses at most one recovery Get after malformed and stale traffic", function(assertions)
		local rig = makeRig()
		rig.snapshotSignal:fire({ payload = { private = true } })
		assertions.equal(#rig.getFires, 1)
		rig.getResponseSignal:fire({
			requestId = "unknown01",
			state = "Success",
			payload = makeSnapshot(1, "ReadyCheck", false, nil, nil),
		})
		assertions.equal(rig.tracker:getStats().pendingCount, 1)
		assertions.equal(#rig.getFires, 1)
		rig.getResponseSignal:fire({
			requestId = rig.getFires[1].requestId,
			state = "Success",
			payload = { malformed = true },
		})
		assertions.equal(#rig.getFires, 2)
		assertions.equal(rig.tracker:getStats().pendingCount, 1)
		rig.snapshotSignal:fire(42)
		rig.getResponseSignal:fire({ private = true })
		assertions.equal(#rig.getFires, 2)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		shutdown(rig)
	end),

	TestHarness.case("cancels malformed Ready responses and recovers without leaking details", function(assertions)
		local rig = makeRig()
		completeInitial(rig, nil)
		activate(rig)
		assertions.equal(rig.tracker:getStats().pendingCount, 1)
		rig.readyResponseSignal:fire({
			requestId = rig.readyFires[1].requestId,
			state = "Success",
			payload = { secret = "PRIVATE_MATCH_READY_CONTROLLER_SENTINEL" },
		})
		assertions.equal(labelText(rig, "RequestLabel"), "Request: Rejected")
		assertions.equal(rig.tracker:getStats().pendingCount, 1)
		assertions.equal(#rig.getFires, 2)
		rig.getResponseSignal:fire(successWire(rig.getFires[2], makeSnapshot(1, "ReadyCheck", false, nil, nil)))
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		assertions.isNil(string.find(labelText(rig, "RequestLabel"), "PRIVATE", 1, true))
		shutdown(rig)
	end),

	TestHarness.case(
		"projects protected synchronized time without treating countdown as authority",
		function(assertions)
			local rig = makeRig()
			completeInitial(rig, nil)
			assertions.equal(labelText(rig, "CountdownLabel"), "Countdown: 45s")
			rig.serverTime = 130
			renderStep(rig)
			assertions.equal(labelText(rig, "CountdownLabel"), "Countdown: 15s")
			rig.timeThrows = true
			renderStep(rig)
			assertions.equal(labelText(rig, "CountdownLabel"), "Countdown: --")
			rig.timeThrows = false
			rig.serverTime = 129
			renderStep(rig)
			assertions.equal(labelText(rig, "CountdownLabel"), "Countdown: --")
			rig.serverTime = 130
			rig.snapshotSignal:fire({ payload = makeSnapshot(2, "ReadyCheck", false, nil, 300) })
			assertions.equal(labelText(rig, "CountdownLabel"), "Countdown: --")
			assertions.isTrue(button(rig).Active)
			shutdown(rig)
		end
	),

	TestHarness.case(
		"cancels Ready on state exit and exposes only the authoritative state change",
		function(assertions)
			local rig = makeRig()
			completeInitial(rig, nil)
			activate(rig)
			assertions.equal(rig.tracker:getStats().pendingCount, 1)
			rig.snapshotSignal:fire({ payload = makeSnapshot(2, "PreWave", true, nil, nil) })
			assertions.equal(rig.tracker:getStats().pendingCount, 0)
			assertions.equal(labelText(rig, "StateLabel"), "State: Preparing wave")
			assertions.equal(labelText(rig, "RequestLabel"), "Request: State changed")
			assertions.isFalse(button(rig).Visible)
			rig.readyResponseSignal:fire(successWire(rig.readyFires[1], makeSnapshot(2, "PreWave", true, nil, nil)))
			assertions.equal(labelText(rig, "StateLabel"), "State: Preparing wave")
			shutdown(rig)
		end
	),

	TestHarness.case("cleans every binding pending request GUI and late callback exactly once", function(assertions)
		local rig = makeRig()
		local beforeFires = #rig.getFires
		assertions.equal(rig.tracker:getStats().pendingCount, 1)
		rig.definition.shutdown()
		assertions.equal(rig.controller:getState(), "Shutdown")
		assertions.equal(rig.unbindCount, 1)
		assertions.equal(rig.disconnectCount, 5)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		assertions.isNil(rig.parent:FindFirstChild(MatchReadyView.GUI_NAME))
		rig.definition.shutdown()
		assertions.equal(rig.unbindCount, 1)
		assertions.equal(rig.disconnectCount, 5)
		rig.snapshotSignal:force({ payload = makeSnapshot(2, "ReadyCheck", false, nil, nil) })
		rig.getResponseSignal:force(successWire(rig.getFires[1], makeSnapshot(2, "ReadyCheck", false, nil, nil)))
		activate(rig)
		beginAction(rig)
		renderStep(rig)
		assertions.equal(#rig.getFires, beforeFires)
		assertions.equal(#rig.readyFires, 0)
		rig.parent:Destroy()
	end),

	TestHarness.case("shows privacy-safe rejection codes and bounds rejection recovery", function(assertions)
		local rig = makeRig()
		completeInitial(rig, nil)
		activate(rig)
		rig.readyResponseSignal:fire(rejectedWire(rig.readyFires[1], "STALE_REQUEST"))
		assertions.equal(labelText(rig, "RequestLabel"), "Request: Rejected")
		assertions.equal(#rig.getFires, 2)
		rig.getResponseSignal:fire(rejectedWire(rig.getFires[2], "RATE_LIMITED"))
		assertions.equal(#rig.getFires, 2)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		shutdown(rig)
	end),
})
