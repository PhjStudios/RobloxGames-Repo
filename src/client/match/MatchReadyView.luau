--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)

export type ErrorCode =
	"INVALID_CONTEXT"
	| "INVALID_PARENT"
	| "INVALID_CONNECTOR"
	| "GUI_CONFLICT"
	| "CREATION_FAILED"
	| "DESTROYED"
	| "INVALID_CALLBACK"
	| "CONNECTION_FAILED"
	| "INVALID_RENDER_STATE"
	| "RENDER_FAILED"
	| "DESTROY_FAILED"

export type ViewError = {
	code: ErrorCode,
	path: string,
	message: string,
}

export type RenderRow = {
	label: string,
	status: string,
	isLocal: boolean,
}

export type RenderState = {
	matchState: string,
	countdownText: string,
	requestText: string,
	readyVisible: boolean,
	readyEnabled: boolean,
	rows: { RenderRow },
}

export type ActivationConnector = (TextButton, () -> ()) -> RBXScriptConnection

type ViewData = {
	gui: ScreenGui,
	stateLabel: TextLabel,
	countdownLabel: TextLabel,
	requestLabel: TextLabel,
	rowLabels: { TextLabel },
	readyButton: TextButton,
	connectActivation: ActivationConnector,
	destroyed: boolean,
}

type CanonicalRenderState = {
	matchState: string,
	countdownText: string,
	requestText: string,
	readyVisible: boolean,
	readyEnabled: boolean,
	rows: { RenderRow },
}

local ViewMethods = {}
ViewMethods.__index = ViewMethods

export type View = typeof(setmetatable({} :: {}, ViewMethods))
export type ViewResult = Result.Result<View, ViewError>
export type ConnectionResult = Result.Result<RBXScriptConnection, ViewError>
export type OperationResult = Result.Result<boolean, ViewError>
export type TestConstructor = (Instance, ActivationConnector?) -> ViewResult

local GUI_NAME = "ATDMatchReadyGui"
local MAX_ROWS = 4

local MATCH_STATES: { [string]: boolean } = table.freeze({
	Loading = true,
	ReadyCheck = true,
	PreWave = true,
	WaveActive = true,
	Results = true,
	Closing = true,
})

local REQUEST_TEXTS: { [string]: boolean } = table.freeze({
	Idle = true,
	Pending = true,
	Accepted = true,
	Rejected = true,
	StateChanged = true,
})

local ROW_STATUSES: { [string]: boolean } = table.freeze({
	Ready = true,
	Waiting = true,
	Disconnected = true,
	Returned = true,
	Spectator = true,
})

local VIEW_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ViewData }

local MatchReadyView = {
	GUI_NAME = GUI_NAME,
	MAX_ROWS = MAX_ROWS,
	newForTests = nil :: TestConstructor?,
}

local function failure(code: ErrorCode, path: string, message: string)
	return Result.err(table.freeze({
		code = code,
		path = path,
		message = message,
	}))
end

local function requireData(value: unknown): ViewData
	if type(value) ~= "table" then
		error("[ATD_MATCH_READY_VIEW][code=INVALID_CONTEXT]", 0)
	end
	local data = VIEW_DATA[value :: any]
	if data == nil then
		error("[ATD_MATCH_READY_VIEW][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function hasExactKeys(value: { [any]: unknown }, expected: { [string]: boolean }): boolean
	local count = 0
	for key in next, value do
		if type(key) ~= "string" or rawget(expected, key) ~= true then
			return false
		end
		count += 1
	end

	local expectedCount = 0
	for _ in next, expected do
		expectedCount += 1
	end
	return count == expectedCount
end

local function hasNoMetatable(value: { [any]: unknown }): boolean
	return getmetatable(value) == nil
end

local function isCountdownText(value: unknown): boolean
	if value == "--" then
		return true
	end
	if type(value) ~= "string" then
		return false
	end

	local digits = string.match(value, "^(%d+)s$")
	if digits == nil then
		return false
	end
	local seconds = tonumber(digits)
	return seconds ~= nil and seconds >= 0 and seconds <= 45 and tostring(seconds) == digits
end

local function canonicalizeRenderState(value: unknown): CanonicalRenderState?
	if type(value) ~= "table" or not hasNoMetatable(value :: { [any]: unknown }) then
		return nil
	end
	local record = value :: { [any]: unknown }
	if
		not hasExactKeys(record, {
			matchState = true,
			countdownText = true,
			requestText = true,
			readyVisible = true,
			readyEnabled = true,
			rows = true,
		})
	then
		return nil
	end

	local matchState = rawget(record, "matchState")
	local countdownText = rawget(record, "countdownText")
	local requestText = rawget(record, "requestText")
	local readyVisible = rawget(record, "readyVisible")
	local readyEnabled = rawget(record, "readyEnabled")
	local rows = rawget(record, "rows")
	if
		type(matchState) ~= "string"
		or rawget(MATCH_STATES, matchState) ~= true
		or not isCountdownText(countdownText)
		or type(requestText) ~= "string"
		or rawget(REQUEST_TEXTS, requestText) ~= true
		or type(readyVisible) ~= "boolean"
		or type(readyEnabled) ~= "boolean"
		or (readyEnabled and not readyVisible)
		or type(rows) ~= "table"
		or not hasNoMetatable(rows :: { [any]: unknown })
	then
		return nil
	end

	if matchState ~= "ReadyCheck" and countdownText ~= "--" then
		return nil
	end
	if readyVisible and matchState ~= "ReadyCheck" then
		return nil
	end

	local rowArray = rows :: { [any]: unknown }
	local rowCount = 0
	for key in next, rowArray do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > MAX_ROWS then
			return nil
		end
		rowCount += 1
	end
	if rowCount > MAX_ROWS then
		return nil
	end

	local canonicalRows = table.create(rowCount) :: { RenderRow }
	local localCount = 0
	for index = 1, rowCount do
		local rowValue = rawget(rowArray, index)
		if type(rowValue) ~= "table" or not hasNoMetatable(rowValue :: { [any]: unknown }) then
			return nil
		end
		local row = rowValue :: { [any]: unknown }
		if not hasExactKeys(row, { label = true, status = true, isLocal = true }) then
			return nil
		end

		local label = rawget(row, "label")
		local status = rawget(row, "status")
		local isLocal = rawget(row, "isLocal")
		if
			label ~= `Player {index}`
			or type(status) ~= "string"
			or rawget(ROW_STATUSES, status) ~= true
			or type(isLocal) ~= "boolean"
		then
			return nil
		end
		if isLocal then
			localCount += 1
			if localCount > 1 then
				return nil
			end
		end

		canonicalRows[index] = table.freeze({
			label = label,
			status = status,
			isLocal = isLocal,
		})
	end
	if rowCount > 0 and rawget(rowArray, rowCount + 1) ~= nil then
		return nil
	end

	return {
		matchState = matchState,
		countdownText = countdownText :: string,
		requestText = requestText,
		readyVisible = readyVisible,
		readyEnabled = readyEnabled,
		rows = canonicalRows,
	}
end

local function configureTextLabel(label: TextLabel, name: string, initialText: string)
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = initialText
	label.TextWrapped = false
end

local function applyLayout(data: ViewData)
	local panel = data.stateLabel.Parent :: Frame
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 24)
	panel.Size = UDim2.fromOffset(360, 286)
	panel.BackgroundTransparency = 0.2

	local left = 16
	local width = 328
	data.stateLabel.Position = UDim2.fromOffset(left, 12)
	data.stateLabel.Size = UDim2.fromOffset(width, 24)
	data.countdownLabel.Position = UDim2.fromOffset(left, 40)
	data.countdownLabel.Size = UDim2.fromOffset(width, 24)
	data.requestLabel.Position = UDim2.fromOffset(left, 68)
	data.requestLabel.Size = UDim2.fromOffset(width, 24)

	for index, rowLabel in data.rowLabels do
		rowLabel.Position = UDim2.fromOffset(left, 96 + ((index - 1) * 28))
		rowLabel.Size = UDim2.fromOffset(width, 24)
	end

	data.readyButton.Position = UDim2.fromOffset(left, 220)
	data.readyButton.Size = UDim2.fromOffset(width, 48)

	for _, label in { data.stateLabel, data.countdownLabel, data.requestLabel } do
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
	end
	for _, label in data.rowLabels do
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
	end
end

local function defaultActivationConnector(button: TextButton, callback: () -> ()): RBXScriptConnection
	return button.Activated:Connect(callback)
end

local function createView(
	parent: Instance,
	connectActivation: ActivationConnector,
	applyProductionLayout: boolean
): ViewResult
	if typeof(parent) ~= "Instance" then
		return failure("INVALID_PARENT", "parent", "The ready view requires an approved GUI parent")
	end
	if type(connectActivation) ~= "function" then
		return failure("INVALID_CONNECTOR", "connector", "The ready view activation adapter is invalid")
	end
	if parent:FindFirstChild(GUI_NAME) ~= nil then
		return failure("GUI_CONFLICT", "parent", "The fixed ready GUI name is already occupied")
	end

	local gui: ScreenGui? = nil
	local created, viewOrError = pcall(function(): View
		local nextGui = Instance.new("ScreenGui")
		gui = nextGui
		nextGui.Name = GUI_NAME
		nextGui.Enabled = true
		nextGui.ResetOnSpawn = false
		nextGui.DisplayOrder = 10

		local panel = Instance.new("Frame")
		panel.Name = "ReadyPanel"
		panel.BorderSizePixel = 0
		panel.Parent = nextGui

		local stateLabel = Instance.new("TextLabel")
		configureTextLabel(stateLabel, "StateLabel", "State: Loading")
		stateLabel.Parent = panel

		local countdownLabel = Instance.new("TextLabel")
		configureTextLabel(countdownLabel, "CountdownLabel", "Countdown: --")
		countdownLabel.Parent = panel

		local requestLabel = Instance.new("TextLabel")
		configureTextLabel(requestLabel, "RequestLabel", "Request: Idle")
		requestLabel.Parent = panel

		local rowLabels = table.create(MAX_ROWS) :: { TextLabel }
		for index = 1, MAX_ROWS do
			local rowLabel = Instance.new("TextLabel")
			configureTextLabel(rowLabel, `PlayerRow{index}`, "")
			rowLabel.Visible = false
			rowLabel.Parent = panel
			rowLabels[index] = rowLabel
		end

		local readyButton = Instance.new("TextButton")
		readyButton.Name = "ReadyButton"
		readyButton.Text = "Ready"
		readyButton.Visible = false
		readyButton.Active = false
		readyButton.Selectable = false
		readyButton.AutoButtonColor = false
		readyButton.SelectionOrder = 1
		readyButton.Parent = panel

		local view = setmetatable({}, ViewMethods)
		local data: ViewData = {
			gui = nextGui,
			stateLabel = stateLabel,
			countdownLabel = countdownLabel,
			requestLabel = requestLabel,
			rowLabels = rowLabels,
			readyButton = readyButton,
			connectActivation = connectActivation,
			destroyed = false,
		}
		VIEW_DATA[view] = data
		if applyProductionLayout then
			applyLayout(data)
		end

		nextGui.Parent = parent
		return table.freeze(view)
	end)
	if not created then
		if gui ~= nil then
			pcall(function()
				(gui :: ScreenGui):Destroy()
			end)
		end
		return failure("CREATION_FAILED", "view", "The fixed ready GUI could not be created")
	end

	return Result.ok(viewOrError :: View)
end

function ViewMethods.connectActivated(self: View, callback: unknown): ConnectionResult
	local data = requireData(self)
	if data.destroyed then
		return failure("DESTROYED", "view", "The ready view has already been destroyed")
	end
	if type(callback) ~= "function" then
		return failure("INVALID_CALLBACK", "callback", "The Ready activation callback must be a function")
	end

	local connected, connection = pcall(data.connectActivation, data.readyButton, callback :: () -> ())
	if not connected or typeof(connection) ~= "RBXScriptConnection" then
		return failure("CONNECTION_FAILED", "activation", "The Ready activation binding failed")
	end
	return Result.ok(connection :: RBXScriptConnection)
end

function ViewMethods.render(self: View, renderState: unknown): OperationResult
	local data = requireData(self)
	if data.destroyed then
		return failure("DESTROYED", "view", "The ready view has already been destroyed")
	end

	local canonical = canonicalizeRenderState(renderState)
	if canonical == nil then
		return failure("INVALID_RENDER_STATE", "renderState", "The ready view render state is invalid")
	end

	local rendered = pcall(function()
		data.stateLabel.Text = `State: {canonical.matchState}`
		data.countdownLabel.Text = `Countdown: {canonical.countdownText}`
		data.requestLabel.Text = `Request: {canonical.requestText}`

		for index, label in data.rowLabels do
			local row = canonical.rows[index]
			if row == nil then
				label.Text = ""
				label.Visible = false
			else
				local localSuffix = if row.isLocal then " (You)" else ""
				label.Text = `{row.label}{localSuffix}: {row.status}`
				label.Visible = true
			end
		end

		local enabled = canonical.readyVisible and canonical.readyEnabled
		data.readyButton.Visible = canonical.readyVisible
		data.readyButton.Active = enabled
		data.readyButton.Selectable = enabled
		data.readyButton.AutoButtonColor = enabled
	end)
	if not rendered then
		return failure("RENDER_FAILED", "view", "The ready GUI could not render its canonical state")
	end
	return Result.ok(true)
end

function ViewMethods.destroy(self: View): OperationResult
	local data = requireData(self)
	if data.destroyed then
		return Result.ok(true)
	end
	data.destroyed = true

	local destroyed = pcall(function()
		data.gui:Destroy()
	end)
	if not destroyed then
		return failure("DESTROY_FAILED", "view", "The owned ready GUI could not be destroyed")
	end
	return Result.ok(true)
end

function MatchReadyView.new(parent: unknown): ViewResult
	if typeof(parent) ~= "Instance" or not (parent :: Instance):IsA("PlayerGui") then
		return failure("INVALID_PARENT", "parent", "The ready view requires a PlayerGui parent")
	end
	return createView(parent :: Instance, defaultActivationConnector, true)
end

local serverStorage = game:GetService("ServerStorage")
local testContainer = script.Parent
local automatedTests = testContainer.Parent
if
	script.Name == "MatchReadyView"
	and testContainer.ClassName == "Folder"
	and testContainer.Name == "ProductionClientMatch"
	and automatedTests.ClassName == "Folder"
	and automatedTests.Name == "AutomatedTests"
	and automatedTests.Parent == serverStorage
then
	MatchReadyView.newForTests = function(parent: Instance, connector: ActivationConnector?): ViewResult
		if typeof(parent) ~= "Instance" or parent.ClassName ~= "Folder" then
			return failure("INVALID_PARENT", "parent", "The test ready view requires an isolated Folder parent")
		end
		local selectedConnector = connector
		if selectedConnector == nil then
			selectedConnector = defaultActivationConnector
		end
		return createView(parent, selectedConnector, false)
	end
end

table.freeze(ViewMethods)
return table.freeze(MatchReadyView)
