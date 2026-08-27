--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local MatchReadyView = require(script.Parent.Parent.ProductionClientMatch.MatchReadyView)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Assertions = TestHarness.Assertions
type View = MatchReadyView.View
type RenderState = MatchReadyView.RenderState
type ActivationConnector = MatchReadyView.ActivationConnector

local PRIVATE_SENTINEL = "PRIVATE_MATCH_READY_VIEW_SENTINEL_8921"

local newForTests = MatchReadyView.newForTests
if newForTests == nil then
	error("[ATD_TEST_FIXTURE][code=MATCH_READY_VIEW_TEST_CONSTRUCTOR_MISSING]", 0)
end

local function child(parent: Instance, name: string, className: string): Instance
	local value = parent:FindFirstChild(name)
	if value == nil or value.ClassName ~= className then
		error("[ATD_TEST_FIXTURE][code=MATCH_READY_VIEW_CHILD_MISSING]", 0)
	end
	return value
end

local function makeParent(): Folder
	local parent = Instance.new("Folder")
	parent.Name = "MatchReadyViewTestParent"
	return parent
end

local function defaultRows(): { MatchReadyView.RenderRow }
	return {
		{ label = "Player 1", status = "Ready", isLocal = false },
		{ label = "Player 2", status = "Waiting", isLocal = true },
		{ label = "Player 3", status = "Disconnected", isLocal = false },
		{ label = "Player 4", status = "Returned", isLocal = false },
	}
end

local function renderState(selected: { [string]: unknown }?): RenderState
	local overrides = selected or {}
	return {
		matchState = (rawget(overrides, "matchState") or "ReadyCheck") :: string,
		countdownText = (rawget(overrides, "countdownText") or "45s") :: string,
		requestText = (rawget(overrides, "requestText") or "Idle") :: string,
		readyVisible = if rawget(overrides, "readyVisible") == nil
			then true
			else rawget(overrides, "readyVisible") :: boolean,
		readyEnabled = if rawget(overrides, "readyEnabled") == nil
			then true
			else rawget(overrides, "readyEnabled") :: boolean,
		rows = (rawget(overrides, "rows") or defaultRows()) :: { MatchReadyView.RenderRow },
	}
end

local function expectView(assertions: Assertions, parent: Instance, connector: ActivationConnector?): View
	local outcome = (newForTests :: MatchReadyView.TestConstructor)(parent, connector)
	assertions.isTrue(outcome.ok)
	if not outcome.ok then
		error("[ATD_TEST_FIXTURE][code=MATCH_READY_VIEW_CREATION_FAILED]", 0)
	end
	return outcome.value
end

local function expectFailure(assertions: Assertions, outcome: any, code: string)
	assertions.isFalse(outcome.ok)
	if outcome.ok then
		return
	end
	assertions.equal(outcome.error.code, code)
	assertions.isTrue(table.isfrozen(outcome))
	assertions.isTrue(table.isfrozen(outcome.error))
	assertions.isNil(string.find(outcome.error.message, PRIVATE_SENTINEL, 1, true))
end

local function getTree(parent: Instance): (ScreenGui, Frame, TextButton)
	local gui = child(parent, MatchReadyView.GUI_NAME, "ScreenGui") :: ScreenGui
	local panel = child(gui, "ReadyPanel", "Frame") :: Frame
	local button = child(panel, "ReadyButton", "TextButton") :: TextButton
	return gui, panel, button
end

local function baselineText(parent: Instance): string
	local _, panel = getTree(parent)
	local values = {
		(child(panel, "StateLabel", "TextLabel") :: TextLabel).Text,
		(child(panel, "CountdownLabel", "TextLabel") :: TextLabel).Text,
		(child(panel, "RequestLabel", "TextLabel") :: TextLabel).Text,
	}
	for index = 1, MatchReadyView.MAX_ROWS do
		table.insert(values, (child(panel, `PlayerRow{index}`, "TextLabel") :: TextLabel).Text)
	end
	return table.concat(values, "|")
end

return TestHarness.suite("minimal Match ready GUI view", {
	TestHarness.case("creates the one fixed owned GUI with exact minimal controls", function(assertions)
		assertions.isTrue(table.isfrozen(MatchReadyView))
		assertions.equal(MatchReadyView.GUI_NAME, "ATDMatchReadyGui")
		assertions.equal(MatchReadyView.MAX_ROWS, 4)

		local parent = makeParent()
		local view = expectView(assertions, parent, function(_button, _callback)
			return RobloxAdapter.createConnection(function() end) :: RBXScriptConnection
		end)
		assertions.isTrue(table.isfrozen(view))
		assertions.equal(#parent:GetChildren(), 1)

		local gui, panel, button = getTree(parent)
		assertions.equal(gui.Parent, parent)
		assertions.isTrue(gui.Enabled)
		assertions.isFalse(gui.ResetOnSpawn)
		assertions.equal(#gui:GetChildren(), 1)
		assertions.equal(panel.Parent, gui)
		assertions.equal(#panel:GetChildren(), 8)
		assertions.equal((child(panel, "StateLabel", "TextLabel") :: TextLabel).Text, "State: Loading")
		assertions.equal((child(panel, "CountdownLabel", "TextLabel") :: TextLabel).Text, "Countdown: --")
		assertions.equal((child(panel, "RequestLabel", "TextLabel") :: TextLabel).Text, "Request: Idle")
		for index = 1, MatchReadyView.MAX_ROWS do
			local row = child(panel, `PlayerRow{index}`, "TextLabel") :: TextLabel
			assertions.isFalse(row.Visible)
			assertions.equal(row.Text, "")
		end
		assertions.equal(button.Text, "Ready")
		assertions.isFalse(button.Visible)
		assertions.isFalse(button.Active)
		assertions.isFalse(button.Selectable)

		assertions.isTrue(view:destroy().ok)
		parent:Destroy()
	end),

	TestHarness.case("renders deterministic rows local marker and enabled Ready semantics", function(assertions)
		local parent = makeParent()
		local view = expectView(assertions, parent, function(_button, _callback)
			return RobloxAdapter.createConnection(function() end) :: RBXScriptConnection
		end)
		assertions.isTrue(view:render(renderState()).ok)

		local _, panel, button = getTree(parent)
		assertions.equal((child(panel, "StateLabel", "TextLabel") :: TextLabel).Text, "State: ReadyCheck")
		assertions.equal((child(panel, "CountdownLabel", "TextLabel") :: TextLabel).Text, "Countdown: 45s")
		assertions.equal((child(panel, "RequestLabel", "TextLabel") :: TextLabel).Text, "Request: Idle")
		assertions.equal((child(panel, "PlayerRow1", "TextLabel") :: TextLabel).Text, "Player 1: Ready")
		assertions.equal((child(panel, "PlayerRow2", "TextLabel") :: TextLabel).Text, "Player 2 (You): Waiting")
		assertions.equal((child(panel, "PlayerRow3", "TextLabel") :: TextLabel).Text, "Player 3: Disconnected")
		assertions.equal((child(panel, "PlayerRow4", "TextLabel") :: TextLabel).Text, "Player 4: Returned")
		for index = 1, MatchReadyView.MAX_ROWS do
			assertions.isTrue((child(panel, `PlayerRow{index}`, "TextLabel") :: TextLabel).Visible)
		end
		assertions.isTrue(button.Visible)
		assertions.isTrue(button.Active)
		assertions.isTrue(button.Selectable)
		assertions.isTrue(button.AutoButtonColor)

		assertions.isTrue(view:destroy().ok)
		parent:Destroy()
	end),

	TestHarness.case("clears unused rows and disables or hides Ready exactly as directed", function(assertions)
		local parent = makeParent()
		local view = expectView(assertions, parent, function(_button, _callback)
			return RobloxAdapter.createConnection(function() end) :: RBXScriptConnection
		end)
		local oneRow = {
			{ label = "Player 1", status = "Spectator", isLocal = true },
		}
		assertions.isTrue(
			view:render(renderState({ rows = oneRow, readyEnabled = false, requestText = "Rejected" })).ok
		)

		local _, panel, button = getTree(parent)
		assertions.equal((child(panel, "PlayerRow1", "TextLabel") :: TextLabel).Text, "Player 1 (You): Spectator")
		assertions.isTrue((child(panel, "PlayerRow1", "TextLabel") :: TextLabel).Visible)
		for index = 2, MatchReadyView.MAX_ROWS do
			local row = child(panel, `PlayerRow{index}`, "TextLabel") :: TextLabel
			assertions.equal(row.Text, "")
			assertions.isFalse(row.Visible)
		end
		assertions.isTrue(button.Visible)
		assertions.isFalse(button.Active)
		assertions.isFalse(button.Selectable)
		assertions.isFalse(button.AutoButtonColor)

		assertions.isTrue(view:render(renderState({ readyVisible = false, readyEnabled = false })).ok)
		assertions.isFalse(button.Visible)
		assertions.isFalse(button.Active)
		assertions.isFalse(button.Selectable)

		assertions.isTrue(view:destroy().ok)
		parent:Destroy()
	end),

	TestHarness.case("binds the one Activated path while leaving the connection caller-owned", function(assertions)
		local parent = makeParent()
		local connectedButton: TextButton? = nil
		local connectedCallback: (() -> ())? = nil
		local disconnectCount = 0
		local connector: ActivationConnector = function(button, callback)
			connectedButton = button
			connectedCallback = callback
			return RobloxAdapter.createConnection(function()
				disconnectCount += 1
			end) :: RBXScriptConnection
		end
		local view = expectView(assertions, parent, connector)
		local activationCount = 0
		local connectionResult = view:connectActivated(function()
			activationCount += 1
		end)
		assertions.isTrue(connectionResult.ok)
		if not connectionResult.ok then
			return
		end

		local _, _, button = getTree(parent)
		assertions.equal(connectedButton, button)
		assertions.equal(typeof(connectionResult.value), "RBXScriptConnection")
		assertions.isNotNil(connectedCallback)
		local activationCallback = connectedCallback
		if activationCallback ~= nil then
			activationCallback()
		end
		assertions.equal(activationCount, 1)
		assertions.equal(disconnectCount, 0)

		assertions.isTrue(view:destroy().ok)
		assertions.equal(disconnectCount, 0)
		connectionResult.value:Disconnect()
		assertions.equal(disconnectCount, 1)
		expectFailure(assertions, view:connectActivated(function() end), "DESTROYED")
		parent:Destroy()
	end),

	TestHarness.case("fails closed on duplicate GUI names without touching the occupant", function(assertions)
		local parent = makeParent()
		local conflict = Instance.new("Folder")
		conflict.Name = MatchReadyView.GUI_NAME
		local sentinel = Instance.new("StringValue")
		sentinel.Name = "UnrelatedSentinel"
		sentinel.Value = PRIVATE_SENTINEL
		sentinel.Parent = conflict
		conflict.Parent = parent

		local outcome = (newForTests :: MatchReadyView.TestConstructor)(parent, function(_button, _callback)
			return RobloxAdapter.createConnection(function() end) :: RBXScriptConnection
		end)
		expectFailure(assertions, outcome, "GUI_CONFLICT")
		assertions.equal(#parent:GetChildren(), 1)
		assertions.equal(conflict.Parent, parent)
		assertions.equal(sentinel.Parent, conflict)
		assertions.equal(sentinel.Value, PRIVATE_SENTINEL)
		parent:Destroy()
	end),

	TestHarness.case("destroys only its exact owned GUI and is idempotent", function(assertions)
		local parent = makeParent()
		local view = expectView(assertions, parent, function(_button, _callback)
			return RobloxAdapter.createConnection(function() end) :: RBXScriptConnection
		end)
		local gui = child(parent, MatchReadyView.GUI_NAME, "ScreenGui") :: ScreenGui
		gui.Name = "RenamedOwnedReadyGui"

		local unrelated = Instance.new("Folder")
		unrelated.Name = MatchReadyView.GUI_NAME
		unrelated.Parent = parent
		assertions.isTrue(view:destroy().ok)
		assertions.isNil(gui.Parent)
		assertions.equal(unrelated.Parent, parent)
		assertions.equal(parent:FindFirstChild(MatchReadyView.GUI_NAME), unrelated)
		assertions.isTrue(view:destroy().ok)
		assertions.equal(unrelated.Parent, parent)
		expectFailure(assertions, view:render(renderState()), "DESTROYED")
		parent:Destroy()
	end),

	TestHarness.case("rejects hostile render records atomically without private-value echo", function(assertions)
		local parent = makeParent()
		local view = expectView(assertions, parent, function(_button, _callback)
			return RobloxAdapter.createConnection(function() end) :: RBXScriptConnection
		end)
		assertions.isTrue(view:render(renderState()).ok)
		local before = baselineText(parent)
		expectFailure(assertions, view:render(nil), "INVALID_RENDER_STATE")
		assertions.equal(baselineText(parent), before)

		local invalidInstance = Instance.new("Folder")
		local invalidStates: { unknown } = {
			{},
			{
				matchState = PRIVATE_SENTINEL,
				countdownText = "45s",
				requestText = "Idle",
				readyVisible = true,
				readyEnabled = true,
				rows = defaultRows(),
			},
			{
				matchState = "ReadyCheck",
				countdownText = "46s",
				requestText = "Idle",
				readyVisible = true,
				readyEnabled = true,
				rows = defaultRows(),
			},
			{
				matchState = "ReadyCheck",
				countdownText = "045s",
				requestText = "Idle",
				readyVisible = true,
				readyEnabled = true,
				rows = defaultRows(),
			},
			{
				matchState = "Loading",
				countdownText = "1s",
				requestText = "Idle",
				readyVisible = false,
				readyEnabled = false,
				rows = {},
			},
			{
				matchState = "ReadyCheck",
				countdownText = "45s",
				requestText = PRIVATE_SENTINEL,
				readyVisible = true,
				readyEnabled = true,
				rows = defaultRows(),
			},
			{
				matchState = "ReadyCheck",
				countdownText = "45s",
				requestText = "Idle",
				readyVisible = false,
				readyEnabled = true,
				rows = defaultRows(),
			},
			{
				matchState = "ReadyCheck",
				countdownText = "45s",
				requestText = "Idle",
				readyVisible = true,
				readyEnabled = true,
				rows = {
					{ label = "Player 2", status = "Waiting", isLocal = true },
				},
			},
			{
				matchState = "ReadyCheck",
				countdownText = "45s",
				requestText = "Idle",
				readyVisible = true,
				readyEnabled = true,
				rows = {
					{ label = "Player 1", status = PRIVATE_SENTINEL, isLocal = true },
				},
			},
			{
				matchState = "ReadyCheck",
				countdownText = "45s",
				requestText = "Idle",
				readyVisible = true,
				readyEnabled = true,
				rows = {
					{ label = "Player 1", status = "Waiting", isLocal = true },
					{ label = "Player 2", status = "Ready", isLocal = true },
				},
			},
			{
				matchState = "ReadyCheck",
				countdownText = "45s",
				requestText = "Idle",
				readyVisible = true,
				readyEnabled = true,
				rows = { invalidInstance :: any },
			},
		}

		local extra = renderState() :: any
		extra.privateValue = PRIVATE_SENTINEL
		table.insert(invalidStates, extra)
		local metatableState = renderState() :: any
		setmetatable(metatableState, { __index = { privateValue = PRIVATE_SENTINEL } })
		table.insert(invalidStates, metatableState)
		local tooManyRows = defaultRows() :: any
		table.insert(tooManyRows, { label = "Player 4", status = "Waiting", isLocal = false })
		table.insert(invalidStates, renderState({ rows = tooManyRows }))
		local rowsWithHole = {
			[1] = { label = "Player 1", status = "Waiting", isLocal = true },
			[3] = { label = "Player 3", status = "Ready", isLocal = false },
		}
		table.insert(invalidStates, renderState({ rows = rowsWithHole }))

		for _, invalidState in invalidStates do
			expectFailure(assertions, view:render(invalidState), "INVALID_RENDER_STATE")
			assertions.equal(baselineText(parent), before)
			assertions.isNil(string.find(baselineText(parent), PRIVATE_SENTINEL, 1, true))
		end
		invalidInstance:Destroy()

		assertions.isTrue(view:destroy().ok)
		parent:Destroy()
	end),

	TestHarness.case("accepts every fixed state request status and participant status only", function(assertions)
		local parent = makeParent()
		local view = expectView(assertions, parent, function(_button, _callback)
			return RobloxAdapter.createConnection(function() end) :: RBXScriptConnection
		end)
		for _, matchState in { "Loading", "PreWave", "WaveActive", "Results", "Closing" } do
			for _, requestText in { "Idle", "Pending", "Accepted", "Rejected", "StateChanged" } do
				assertions.isTrue(view:render(renderState({
					matchState = matchState,
					countdownText = "--",
					requestText = requestText,
					readyVisible = false,
					readyEnabled = false,
					rows = {},
				})).ok)
			end
		end
		for _, status in { "Ready", "Waiting", "Disconnected", "Returned", "Spectator" } do
			assertions.isTrue(view:render(renderState({
				rows = { { label = "Player 1", status = status, isLocal = false } },
			})).ok)
		end
		for seconds = 0, 45 do
			assertions.isTrue(view:render(renderState({ countdownText = `{seconds}s` })).ok)
		end

		assertions.isTrue(view:destroy().ok)
		parent:Destroy()
	end),

	TestHarness.case("contains callback adapter failures and keeps test construction isolated", function(assertions)
		local parent = makeParent()
		local throwingView = expectView(assertions, parent, function(_button, _callback)
			error(PRIVATE_SENTINEL, 0)
		end)
		expectFailure(assertions, throwingView:connectActivated(function() end), "CONNECTION_FAILED")
		expectFailure(assertions, throwingView:connectActivated(PRIVATE_SENTINEL), "INVALID_CALLBACK")
		assertions.isTrue(throwingView:destroy().ok)

		local invalidParent = Instance.new("Model")
		expectFailure(
			assertions,
			(newForTests :: MatchReadyView.TestConstructor)(invalidParent, function(_button, _callback)
				return RobloxAdapter.createConnection(function() end) :: RBXScriptConnection
			end),
			"INVALID_PARENT"
		)
		expectFailure(assertions, MatchReadyView.new(parent), "INVALID_PARENT")
		expectFailure(assertions, (newForTests :: any)(parent, false), "INVALID_CONNECTOR")

		local productionClone = script.Parent.Parent.ProductionClientMatch.MatchReadyView:Clone()
		productionClone.Name = "MatchReadyViewProductionLocationProbe"
		productionClone.Parent = ReplicatedStorage
		local productionLocated = require(productionClone) :: any
		assertions.equal(type(productionLocated.new), "function")
		assertions.isNil(productionLocated.newForTests)
		assertions.isTrue(table.isfrozen(productionLocated))
		productionClone:Destroy()

		invalidParent:Destroy()
		parent:Destroy()
	end),
})
