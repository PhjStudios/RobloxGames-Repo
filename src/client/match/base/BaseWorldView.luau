--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)
local Localization = require(ReplicatedStorage.Shared.localization.Localization)

local BaseViewModel = require(script.Parent.BaseViewModel)

export type ErrorCode =
	"INVALID_CONTEXT"
	| "INVALID_DEPENDENCIES"
	| "INVALID_PARENT"
	| "INVALID_RENDER_STATE"
	| "CONNECTION_FAILED"
	| "CREATION_FAILED"
	| "RENDER_FAILED"
	| "CLEANUP_FAILED"
	| "CLEANED_UP"

export type Error = {
	code: ErrorCode,
}

export type Metrics = {
	bound: boolean,
	visible: boolean,
	renderCount: number,
	viewRecreationCount: number,
	markerRebindCount: number,
	fixedConnectionCount: number,
	markerWatcherConnectionCount: number,
	viewWatcherConnectionCount: number,
	connectionCount: number,
	activeTweenCount: number,
	tweenCreationCount: number,
	callbackFailureCount: number,
	renderedFillScale: number,
}

export type PulseTween = {
	play: () -> (),
	cancel: () -> (),
	destroy: () -> (),
}

export type Connector = (() -> ()) -> RBXScriptConnection
export type TargetConnector = (Instance, () -> ()) -> RBXScriptConnection
export type PropertyConnector = (Instance, string, () -> ()) -> RBXScriptConnection
export type PulseTweenFactory = (TextLabel) -> PulseTween
export type GuiBindingSetter = (BillboardGui, Part?, boolean) -> ()

export type TestDependencies = {
	connectWorkspaceDescendantAdded: Connector,
	connectWorkspaceDescendantRemoving: Connector,
	connectPlayerGuiChildAdded: Connector,
	connectPlayerGuiChildRemoved: Connector,
	connectAncestryChanged: TargetConnector,
	connectPropertyChanged: PropertyConnector,
	createPulseTween: PulseTweenFactory,
	setGuiBinding: GuiBindingSetter,
}

export type View = {
	render: (self: View, renderState: unknown) -> Result.Result<Metrics, Error>,
	getMetrics: (self: View) -> Result.Result<Metrics, Error>,
	cleanup: (self: View) -> Result.Result<boolean, Error>,
}

export type TestConstructor = (
	playerGuiParent: Instance,
	workspaceRoot: Instance,
	dependencies: TestDependencies
) -> Result.Result<View, Error>

type CanonicalRenderState = BaseViewModel.RenderState

type ViewInstances = {
	gui: BillboardGui,
	panel: Frame,
	background: Frame,
	fill: Frame,
	healthLabel: TextLabel,
	statusLabel: TextLabel,
	lowLabel: TextLabel,
	damageLabel: TextLabel,
}

type MarkerPath = {
	runtimeRoot: Model?,
	markers: Folder?,
	marker: Part?,
}

type ViewData = {
	playerGuiParent: Instance,
	workspaceRoot: Instance,
	dependencies: TestDependencies,
	instances: ViewInstances?,
	boundMarker: Part?,
	markerPath: MarkerPath,
	cachedState: CanonicalRenderState?,
	activeTween: PulseTween?,
	lastPulseRevision: number?,
	fixedConnections: { RBXScriptConnection },
	markerWatcherConnections: { RBXScriptConnection },
	viewWatcherConnections: { RBXScriptConnection },
	callbacksEnabled: boolean,
	reconcilingMarker: boolean,
	reconcilingView: boolean,
	suppressViewCallbacks: boolean,
	cleaned: boolean,
	renderCount: number,
	viewRecreationCount: number,
	markerRebindCount: number,
	tweenCreationCount: number,
	callbackFailureCount: number,
	renderedFillScale: number,
	applyProductionLayout: boolean,
}

local GUI_NAME = "ATDDefenderBaseGui"
local PANEL_NAME = "BasePanel"
local BACKGROUND_NAME = "HealthBackground"
local FILL_NAME = "HealthFill"
local HEALTH_LABEL_NAME = "HealthText"
local STATUS_LABEL_NAME = "StatusText"
local LOW_LABEL_NAME = "LowLabel"
local DAMAGE_LABEL_NAME = "DamageLabel"
local RUNTIME_ROOT_NAME = "ATDRuntimeMap"
local MARKERS_NAME = "Markers"
local MARKER_NAME = "DefenderBase"
local POSITION_TOLERANCE = 1e-3
local MAX_BASE_COORDINATE = 100_000
local FIXED_CONNECTION_COUNT = 4
local MAX_MARKER_WATCHER_CONNECTIONS = 10
local VIEW_INSTANCE_COUNT = 8
local MAX_VIEW_WATCHER_CONNECTIONS = VIEW_INSTANCE_COUNT * 3
local MAX_CONNECTION_COUNT = FIXED_CONNECTION_COUNT + MAX_MARKER_WATCHER_CONNECTIONS + MAX_VIEW_WATCHER_CONNECTIONS

local ViewMethods = {}
ViewMethods.__index = ViewMethods

local VIEW_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ViewData }

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_CONTEXT = table.freeze({ code = "INVALID_CONTEXT" :: "INVALID_CONTEXT" }),
	INVALID_DEPENDENCIES = table.freeze({ code = "INVALID_DEPENDENCIES" :: "INVALID_DEPENDENCIES" }),
	INVALID_PARENT = table.freeze({ code = "INVALID_PARENT" :: "INVALID_PARENT" }),
	INVALID_RENDER_STATE = table.freeze({ code = "INVALID_RENDER_STATE" :: "INVALID_RENDER_STATE" }),
	CONNECTION_FAILED = table.freeze({ code = "CONNECTION_FAILED" :: "CONNECTION_FAILED" }),
	CREATION_FAILED = table.freeze({ code = "CREATION_FAILED" :: "CREATION_FAILED" }),
	RENDER_FAILED = table.freeze({ code = "RENDER_FAILED" :: "RENDER_FAILED" }),
	CLEANUP_FAILED = table.freeze({ code = "CLEANUP_FAILED" :: "CLEANUP_FAILED" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local BaseWorldView = {
	GUI_NAME = GUI_NAME,
	PANEL_NAME = PANEL_NAME,
	BACKGROUND_NAME = BACKGROUND_NAME,
	FILL_NAME = FILL_NAME,
	HEALTH_LABEL_NAME = HEALTH_LABEL_NAME,
	STATUS_LABEL_NAME = STATUS_LABEL_NAME,
	LOW_LABEL_NAME = LOW_LABEL_NAME,
	DAMAGE_LABEL_NAME = DAMAGE_LABEL_NAME,
	RUNTIME_ROOT_NAME = RUNTIME_ROOT_NAME,
	MARKERS_NAME = MARKERS_NAME,
	MARKER_NAME = MARKER_NAME,
	POSITION_TOLERANCE = POSITION_TOLERANCE,
	FIXED_CONNECTION_COUNT = FIXED_CONNECTION_COUNT,
	MAX_MARKER_WATCHER_CONNECTIONS = MAX_MARKER_WATCHER_CONNECTIONS,
	MAX_VIEW_WATCHER_CONNECTIONS = MAX_VIEW_WATCHER_CONNECTIONS,
	MAX_CONNECTION_COUNT = MAX_CONNECTION_COUNT,
	newForTests = nil :: TestConstructor?,
}

local reconcileMarker: (ViewData) -> boolean
local reconcileView: (ViewData) -> boolean

local function failure(code: ErrorCode)
	return Result.err(ERRORS[code])
end

local function requireData(value: unknown): ViewData
	if type(value) ~= "table" then
		error("[ATD_BASE_WORLD_VIEW][code=INVALID_CONTEXT]", 0)
	end
	local data = VIEW_DATA[value :: any]
	if data == nil then
		error("[ATD_BASE_WORLD_VIEW][code=INVALID_CONTEXT]", 0)
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
	for _ in expected do
		expectedCount += 1
	end
	return count == expectedCount
end

local VISIBLE_RENDER_KEYS = table.freeze({
	visible = true,
	basePosition = true,
	baseRevision = true,
	fillScale = true,
	healthText = true,
	statusText = true,
	lowVisible = true,
	lowText = true,
	damageVisible = true,
	damageText = true,
})

-- Luau tables cannot retain keys whose values are nil. The canonical hidden
-- bootstrap state therefore has eight keys rather than carrying placeholder
-- basePosition/baseRevision entries.
local HIDDEN_RENDER_KEYS = table.freeze({
	visible = true,
	fillScale = true,
	healthText = true,
	statusText = true,
	lowVisible = true,
	lowText = true,
	damageVisible = true,
	damageText = true,
})

local function isBoundedPosition(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local position = value :: Vector3
	return Validation.isFiniteNumber(position.X)
		and Validation.isFiniteNumber(position.Y)
		and Validation.isFiniteNumber(position.Z)
		and math.abs(position.X) <= MAX_BASE_COORDINATE
		and math.abs(position.Y) <= MAX_BASE_COORDINATE
		and math.abs(position.Z) <= MAX_BASE_COORDINATE
end

local function parseHealthText(value: unknown): (number?, number?)
	if type(value) ~= "string" or #value > 48 then
		return nil, nil
	end
	local currentText, maximumText = string.match(value, "^(%d+) / (%d+)$")
	if currentText == nil or maximumText == nil then
		return nil, nil
	end
	local current = tonumber(currentText)
	local maximum = tonumber(maximumText)
	if
		current == nil
		or maximum == nil
		or not Validation.isSafeInteger(current)
		or not Validation.isSafeInteger(maximum)
		or current < 0
		or maximum < 1
		or current > maximum
		or string.format("%.0f / %.0f", current, maximum) ~= value
	then
		return nil, nil
	end
	return current, maximum
end

local function isDamageText(value: unknown, maximumHealth: number): boolean
	if type(value) ~= "string" or #value > 32 then
		return false
	end
	local digits = string.match(value, "^%-(%d+)$")
	if digits == nil then
		return false
	end
	local damage = tonumber(digits)
	return damage ~= nil
		and Validation.isSafeInteger(damage)
		and damage >= 1
		and damage <= maximumHealth
		and string.format("-%.0f", damage) == value
end

local function canonicalizeRenderState(value: unknown): CanonicalRenderState?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return nil
	end

	local state = value :: any
	if type(state.visible) ~= "boolean" then
		return nil
	end
	local expectedKeys = if state.visible then VISIBLE_RENDER_KEYS else HIDDEN_RENDER_KEYS
	if not hasExactKeys(value :: { [any]: unknown }, expectedKeys) then
		return nil
	end
	if
		type(state.lowVisible) ~= "boolean"
		or type(state.damageVisible) ~= "boolean"
		or type(state.fillScale) ~= "number"
		or not Validation.isFiniteNumber(state.fillScale)
		or state.fillScale < 0
		or state.fillScale > 1
		or type(state.healthText) ~= "string"
		or type(state.statusText) ~= "string"
		or type(state.lowText) ~= "string"
		or type(state.damageText) ~= "string"
	then
		return nil
	end

	if not state.visible then
		if
			state.basePosition ~= nil
			or state.baseRevision ~= nil
			or state.fillScale ~= 0
			or state.healthText ~= ""
			or state.statusText ~= ""
			or state.lowVisible
			or state.lowText ~= ""
			or state.damageVisible
			or state.damageText ~= ""
		then
			return nil
		end
		return table.freeze({
			visible = false,
			basePosition = nil,
			baseRevision = nil,
			fillScale = 0,
			healthText = "",
			statusText = "",
			lowVisible = false,
			lowText = "",
			damageVisible = false,
			damageText = "",
		})
	end

	if
		not isBoundedPosition(state.basePosition)
		or type(state.baseRevision) ~= "number"
		or not Validation.isSafeInteger(state.baseRevision)
		or state.baseRevision < 1
		or (state.statusText ~= "ACTIVE" and state.statusText ~= "DEFEATED" and state.statusText ~= "UNAVAILABLE")
	then
		return nil
	end

	local currentHealth, maximumHealth = parseHealthText(state.healthText)
	if currentHealth == nil or maximumHealth == nil then
		return nil
	end
	local expectedFill = math.clamp((currentHealth :: number) / (maximumHealth :: number), 0, 1)
	if math.abs(state.fillScale - expectedFill) > 1e-9 then
		return nil
	end
	if state.statusText == "ACTIVE" and currentHealth == 0 then
		return nil
	elseif state.statusText == "DEFEATED" and currentHealth ~= 0 then
		return nil
	end

	local expectedLow = currentHealth <= (maximumHealth :: number) / 4
	if state.lowVisible ~= expectedLow or state.lowText ~= (if expectedLow then "LOW" else "") then
		return nil
	end
	if state.damageVisible then
		if not isDamageText(state.damageText, maximumHealth :: number) then
			return nil
		end
	elseif state.damageText ~= "" then
		return nil
	end

	return table.freeze({
		visible = true,
		basePosition = state.basePosition :: Vector3,
		baseRevision = state.baseRevision :: number,
		fillScale = state.fillScale :: number,
		healthText = state.healthText :: string,
		statusText = state.statusText :: string,
		lowVisible = state.lowVisible :: boolean,
		lowText = state.lowText :: string,
		damageVisible = state.damageVisible :: boolean,
		damageText = state.damageText :: string,
	})
end

local function disconnectAll(connections: { RBXScriptConnection }): boolean
	local succeeded = true
	for index = #connections, 1, -1 do
		local connection = connections[index]
		connections[index] = nil
		local disconnected = pcall(function()
			connection:Disconnect()
		end)
		if not disconnected then
			succeeded = false
		end
	end
	return succeeded
end

local function addConnection(connections: { RBXScriptConnection }, create: () -> unknown): boolean
	local connected, connection = pcall(create)
	if not connected or typeof(connection) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(connections, connection :: RBXScriptConnection)
	return true
end

local function metrics(data: ViewData): Metrics
	local state = data.cachedState
	local visible = data.boundMarker ~= nil and state ~= nil and (state :: CanonicalRenderState).visible
	local fixedCount = #data.fixedConnections
	local markerCount = #data.markerWatcherConnections
	local viewCount = #data.viewWatcherConnections
	return table.freeze({
		bound = data.boundMarker ~= nil,
		visible = visible,
		renderCount = data.renderCount,
		viewRecreationCount = data.viewRecreationCount,
		markerRebindCount = data.markerRebindCount,
		fixedConnectionCount = fixedCount,
		markerWatcherConnectionCount = markerCount,
		viewWatcherConnectionCount = viewCount,
		connectionCount = fixedCount + markerCount + viewCount,
		activeTweenCount = if data.activeTween == nil then 0 else 1,
		tweenCreationCount = data.tweenCreationCount,
		callbackFailureCount = data.callbackFailureCount,
		renderedFillScale = data.renderedFillScale,
	})
end

local function normalizeDamageLabel(data: ViewData)
	local instances = data.instances
	if instances == nil then
		return
	end
	pcall(function()
		(instances :: ViewInstances).damageLabel.TextTransparency = 0
		(instances :: ViewInstances).damageLabel.TextStrokeTransparency = 0.5
	end)
end

local function clearTween(data: ViewData): boolean
	local tween = data.activeTween
	data.activeTween = nil
	if tween == nil then
		normalizeDamageLabel(data)
		return true
	end
	local cancelled = pcall(tween.cancel)
	local destroyed = pcall(tween.destroy)
	normalizeDamageLabel(data)
	return cancelled and destroyed
end

local function isExactPulseTween(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local tween = value :: { [any]: unknown }
	return hasExactKeys(tween, { play = true, cancel = true, destroy = true })
		and type(rawget(tween, "play")) == "function"
		and type(rawget(tween, "cancel")) == "function"
		and type(rawget(tween, "destroy")) == "function"
end

local function startPulse(data: ViewData): boolean
	if not clearTween(data) then
		return false
	end
	local instances = data.instances
	if instances == nil then
		return false
	end
	local damageLabel = (instances :: ViewInstances).damageLabel
	local created, tweenValue = pcall(data.dependencies.createPulseTween, damageLabel)
	if not created or not isExactPulseTween(tweenValue) then
		return false
	end
	local tween = tweenValue :: PulseTween
	data.activeTween = tween
	data.tweenCreationCount += 1
	local played = pcall(tween.play)
	if not played then
		data.activeTween = nil
		pcall(tween.cancel)
		pcall(tween.destroy)
		normalizeDamageLabel(data)
		return false
	end
	return true
end

local function configureTextLabel(label: TextLabel, name: string)
	label.Name = name
	label.Text = ""
end

local function applyProductionLayout(instances: ViewInstances)
	local gui = instances.gui
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 256
	gui.ResetOnSpawn = false
	gui.Size = UDim2.fromOffset(220, 92)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)

	local panel = instances.panel
	panel.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Size = UDim2.fromScale(1, 1)

	local background = instances.background
	background.BackgroundColor3 = Color3.fromRGB(65, 65, 70)
	background.BorderSizePixel = 0
	background.ClipsDescendants = true
	background.Position = UDim2.fromOffset(10, 30)
	background.Size = UDim2.new(1, -20, 0, 22)

	local fill = instances.fill
	fill.BackgroundColor3 = Color3.fromRGB(55, 205, 95)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)

	for _, label in { instances.healthLabel, instances.statusLabel, instances.lowLabel, instances.damageLabel } do
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.TextWrapped = false
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Font = Enum.Font.GothamBold
	end
	instances.healthLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	instances.healthLabel.TextSize = 18
	instances.healthLabel.Position = UDim2.fromOffset(10, 2)
	instances.healthLabel.Size = UDim2.new(1, -20, 0, 26)
	instances.statusLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
	instances.statusLabel.TextSize = 13
	instances.statusLabel.Position = UDim2.fromOffset(10, 55)
	instances.statusLabel.Size = UDim2.new(1, -20, 0, 20)
	instances.lowLabel.TextColor3 = Color3.fromRGB(255, 235, 80)
	instances.lowLabel.TextStrokeTransparency = 0.35
	instances.lowLabel.TextSize = 17
	instances.lowLabel.Position = UDim2.fromOffset(8, 68)
	instances.lowLabel.Size = UDim2.fromOffset(56, 20)
	instances.damageLabel.TextColor3 = Color3.fromRGB(255, 115, 90)
	instances.damageLabel.TextStrokeTransparency = 0.5
	instances.damageLabel.TextSize = 18
	instances.damageLabel.Position = UDim2.new(1, -74, 0, 68)
	instances.damageLabel.Size = UDim2.fromOffset(66, 20)
end

local function createInstances(data: ViewData): ViewInstances?
	local existing = data.playerGuiParent:FindFirstChild(GUI_NAME)
	if existing ~= nil then
		return nil
	end

	local gui: BillboardGui? = nil
	local created, value = pcall(function(): ViewInstances
		local nextGui = Instance.new("BillboardGui")
		gui = nextGui
		nextGui.Name = GUI_NAME
		nextGui.Enabled = false

		local panel = Instance.new("Frame")
		panel.Name = PANEL_NAME
		panel.Parent = nextGui

		local background = Instance.new("Frame")
		background.Name = BACKGROUND_NAME
		background.Parent = panel

		local fill = Instance.new("Frame")
		fill.Name = FILL_NAME
		fill.Parent = background

		local healthLabel = Instance.new("TextLabel")
		configureTextLabel(healthLabel, HEALTH_LABEL_NAME)
		healthLabel.Parent = panel

		local statusLabel = Instance.new("TextLabel")
		configureTextLabel(statusLabel, STATUS_LABEL_NAME)
		statusLabel.Parent = panel

		local lowLabel = Instance.new("TextLabel")
		configureTextLabel(lowLabel, LOW_LABEL_NAME)
		lowLabel.Visible = false
		lowLabel.Parent = panel

		local damageLabel = Instance.new("TextLabel")
		configureTextLabel(damageLabel, DAMAGE_LABEL_NAME)
		damageLabel.Visible = false
		damageLabel.Parent = panel

		local instances: ViewInstances = {
			gui = nextGui,
			panel = panel,
			background = background,
			fill = fill,
			healthLabel = healthLabel,
			statusLabel = statusLabel,
			lowLabel = lowLabel,
			damageLabel = damageLabel,
		}
		if data.applyProductionLayout then
			applyProductionLayout(instances)
		end
		nextGui.Parent = data.playerGuiParent
		return instances
	end)
	if not created then
		if gui ~= nil then
			pcall(function()
				(gui :: BillboardGui):Destroy()
			end)
		end
		return nil
	end
	return value :: ViewInstances
end

local function isViewValid(data: ViewData, instances: ViewInstances): boolean
	local checked, valid = pcall(function(): boolean
		return instances.gui.Parent == data.playerGuiParent
			and instances.gui.Name == GUI_NAME
			and instances.gui:IsA("BillboardGui")
			and instances.panel.Parent == instances.gui
			and instances.panel.Name == PANEL_NAME
			and instances.panel:IsA("Frame")
			and instances.background.Parent == instances.panel
			and instances.background.Name == BACKGROUND_NAME
			and instances.background:IsA("Frame")
			and instances.fill.Parent == instances.background
			and instances.fill.Name == FILL_NAME
			and instances.fill:IsA("Frame")
			and instances.healthLabel.Parent == instances.panel
			and instances.healthLabel.Name == HEALTH_LABEL_NAME
			and instances.healthLabel:IsA("TextLabel")
			and instances.statusLabel.Parent == instances.panel
			and instances.statusLabel.Name == STATUS_LABEL_NAME
			and instances.statusLabel:IsA("TextLabel")
			and instances.lowLabel.Parent == instances.panel
			and instances.lowLabel.Name == LOW_LABEL_NAME
			and instances.lowLabel:IsA("TextLabel")
			and instances.damageLabel.Parent == instances.panel
			and instances.damageLabel.Name == DAMAGE_LABEL_NAME
			and instances.damageLabel:IsA("TextLabel")
	end)
	return checked and valid
end

local function allViewInstances(instances: ViewInstances): { Instance }
	return {
		instances.gui,
		instances.panel,
		instances.background,
		instances.fill,
		instances.healthLabel,
		instances.statusLabel,
		instances.lowLabel,
		instances.damageLabel,
	}
end

local function onViewInvalidated(data: ViewData)
	if not data.callbacksEnabled or data.cleaned or data.suppressViewCallbacks or data.reconcilingView then
		return
	end
	local succeeded = pcall(function()
		if not reconcileView(data) then
			error("reconcile failed", 0)
		end
	end)
	if not succeeded then
		data.callbackFailureCount += 1
	end
end

local function installViewWatchers(data: ViewData, instances: ViewInstances): boolean
	disconnectAll(data.viewWatcherConnections)
	for _, target in allViewInstances(instances) do
		if
			not addConnection(data.viewWatcherConnections, function()
				return data.dependencies.connectAncestryChanged(target, function()
					onViewInvalidated(data)
				end)
			end)
			or not addConnection(data.viewWatcherConnections, function()
				return data.dependencies.connectPropertyChanged(target, "Name", function()
					onViewInvalidated(data)
				end)
			end)
			or not addConnection(data.viewWatcherConnections, function()
				return data.dependencies.connectPropertyChanged(target, "Parent", function()
					onViewInvalidated(data)
				end)
			end)
		then
			disconnectAll(data.viewWatcherConnections)
			return false
		end
	end
	return #data.viewWatcherConnections == MAX_VIEW_WATCHER_CONNECTIONS
end

local function applyRenderState(data: ViewData, state: CanonicalRenderState, allowPulse: boolean): boolean
	local instances = data.instances
	if instances == nil then
		return false
	end
	local currentInstances = instances :: ViewInstances
	data.suppressViewCallbacks = true
	local applied = pcall(function()
		data.renderedFillScale = state.fillScale
		if data.applyProductionLayout then
			currentInstances.fill.Size = UDim2.fromScale(state.fillScale, 1)
		end
		local currentHealth, maximumHealth = parseHealthText(state.healthText)
		currentInstances.healthLabel.Text = if state.healthText == ""
			then ""
			else Localization.text("base.health", { current = currentHealth, maximum = maximumHealth })
		currentInstances.statusLabel.Text = if state.statusText == ""
			then ""
			else Localization.text("base." .. string.lower(state.statusText))
		currentInstances.lowLabel.Text = if state.lowText == "" then "" else Localization.text("base.low")
		currentInstances.lowLabel.Visible = state.lowVisible
		currentInstances.damageLabel.Text = if state.damageText == ""
			then ""
			else Localization.text("base.damage", { damage = tonumber(string.sub(state.damageText, 2)) })
		currentInstances.damageLabel.Visible = state.damageVisible
		if data.applyProductionLayout then
			if state.lowVisible then
				currentInstances.fill.BackgroundColor3 = Color3.fromRGB(230, 155, 45)
			else
				currentInstances.fill.BackgroundColor3 = Color3.fromRGB(55, 205, 95)
			end
		end
	end)
	data.suppressViewCallbacks = false
	if not applied then
		return false
	end

	if not state.damageVisible then
		return clearTween(data)
	end
	local revision = state.baseRevision :: number
	if allowPulse and data.lastPulseRevision ~= revision then
		data.lastPulseRevision = revision
		return startPulse(data)
	end
	if data.lastPulseRevision == revision and data.activeTween == nil then
		pcall(function()
			currentInstances.damageLabel.TextTransparency = 1
			currentInstances.damageLabel.TextStrokeTransparency = 1
		end)
	end
	return true
end

local function destroyOwnedView(data: ViewData): boolean
	local succeeded = disconnectAll(data.viewWatcherConnections)
	if not clearTween(data) then
		succeeded = false
	end
	local instances = data.instances
	data.instances = nil
	if instances ~= nil then
		local currentInstances = instances :: ViewInstances
		data.suppressViewCallbacks = true
		local destroyed = pcall(function()
			data.dependencies.setGuiBinding(currentInstances.gui, nil, false)
			currentInstances.gui:Destroy()
		end)
		data.suppressViewCallbacks = false
		if not destroyed then
			succeeded = false
		end
	end
	return succeeded
end

reconcileView = function(data: ViewData): boolean
	if data.cleaned or data.reconcilingView then
		return not data.cleaned
	end
	data.reconcilingView = true
	local succeeded = true
	local instances = data.instances
	if instances == nil or not isViewValid(data, instances) then
		if not destroyOwnedView(data) then
			succeeded = false
		end
		local created = createInstances(data)
		if created == nil then
			data.reconcilingView = false
			return false
		end
		data.instances = created
		data.viewRecreationCount += 1
		if not installViewWatchers(data, created) then
			destroyOwnedView(data)
			data.reconcilingView = false
			return false
		end
		local cached = data.cachedState
		if cached ~= nil and not applyRenderState(data, cached, false) then
			succeeded = false
		end
	end
	data.reconcilingView = false
	if not reconcileMarker(data) then
		return false
	end
	return succeeded
end

local function inspectMarkerPath(data: ViewData): MarkerPath
	local previous = data.markerPath
	local path: MarkerPath = {
		runtimeRoot = nil,
		markers = nil,
		marker = nil,
	}
	local inspected = pcall(function()
		local runtimeRoot = data.workspaceRoot:FindFirstChild(RUNTIME_ROOT_NAME)
		if runtimeRoot ~= nil and runtimeRoot:IsA("Model") and runtimeRoot.Parent == data.workspaceRoot then
			path.runtimeRoot = runtimeRoot :: Model
		elseif previous.runtimeRoot ~= nil and (previous.runtimeRoot :: Model):IsA("Model") then
			path.runtimeRoot = previous.runtimeRoot
		end
		local selectedRoot = path.runtimeRoot
		if selectedRoot == nil then
			return
		end

		local markers = selectedRoot:FindFirstChild(MARKERS_NAME)
		if markers ~= nil and markers:IsA("Folder") and markers.Parent == selectedRoot then
			path.markers = markers :: Folder
		elseif previous.markers ~= nil and (previous.markers :: Folder):IsA("Folder") then
			path.markers = previous.markers
		end
		local selectedMarkers = path.markers
		if selectedMarkers == nil then
			return
		end

		local marker = selectedMarkers:FindFirstChild(MARKER_NAME)
		if marker ~= nil and marker:IsA("Part") and marker.Parent == selectedMarkers then
			path.marker = marker :: Part
		elseif previous.marker ~= nil and (previous.marker :: Part):IsA("Part") then
			path.marker = previous.marker
		end
	end)
	if not inspected then
		return {
			runtimeRoot = nil,
			markers = nil,
			marker = nil,
		}
	end
	return path
end

local function sameMarkerPath(left: MarkerPath, right: MarkerPath): boolean
	return left.runtimeRoot == right.runtimeRoot and left.markers == right.markers and left.marker == right.marker
end

local function onMarkerInvalidated(data: ViewData)
	if not data.callbacksEnabled or data.cleaned or data.reconcilingMarker then
		return
	end
	local succeeded = pcall(function()
		if not reconcileMarker(data) then
			error("reconcile failed", 0)
		end
	end)
	if not succeeded then
		data.callbackFailureCount += 1
	end
end

local function installMarkerWatchers(data: ViewData, path: MarkerPath): boolean
	disconnectAll(data.markerWatcherConnections)
	local targets = {} :: { Instance }
	if path.runtimeRoot ~= nil then
		table.insert(targets, path.runtimeRoot :: Model)
	end
	if path.markers ~= nil then
		table.insert(targets, path.markers :: Folder)
	end
	if path.marker ~= nil then
		table.insert(targets, path.marker :: Part)
	end
	for _, target in targets do
		if
			not addConnection(data.markerWatcherConnections, function()
				return data.dependencies.connectAncestryChanged(target, function()
					onMarkerInvalidated(data)
				end)
			end)
			or not addConnection(data.markerWatcherConnections, function()
				return data.dependencies.connectPropertyChanged(target, "Name", function()
					onMarkerInvalidated(data)
				end)
			end)
			or not addConnection(data.markerWatcherConnections, function()
				return data.dependencies.connectPropertyChanged(target, "Parent", function()
					onMarkerInvalidated(data)
				end)
			end)
		then
			disconnectAll(data.markerWatcherConnections)
			return false
		end
	end
	local marker = path.marker
	if marker ~= nil then
		if
			not addConnection(data.markerWatcherConnections, function()
				return data.dependencies.connectPropertyChanged(marker :: Part, "CFrame", function()
					onMarkerInvalidated(data)
				end)
			end)
		then
			disconnectAll(data.markerWatcherConnections)
			return false
		end
	end
	return #data.markerWatcherConnections <= MAX_MARKER_WATCHER_CONNECTIONS
end

local function markerMatchesState(path: MarkerPath, state: CanonicalRenderState?, workspaceRoot: Instance): boolean
	local runtimeRoot = path.runtimeRoot
	local markers = path.markers
	local marker = path.marker
	if
		runtimeRoot == nil
		or markers == nil
		or marker == nil
		or state == nil
		or not state.visible
		or state.basePosition == nil
	then
		return false
	end
	local readSucceeded, result = pcall(function(): { valid: boolean, position: Vector3 }
		return {
			valid = (runtimeRoot :: Model).Parent == workspaceRoot
				and (runtimeRoot :: Model).Name == RUNTIME_ROOT_NAME
				and (markers :: Folder).Parent == runtimeRoot
				and (markers :: Folder).Name == MARKERS_NAME
				and (marker :: Part).Parent == markers
				and (marker :: Part).Name == MARKER_NAME,
			position = (marker :: Part).Position,
		}
	end)
	return readSucceeded
		and result.valid
		and (result.position - (state.basePosition :: Vector3)).Magnitude <= POSITION_TOLERANCE
end

local function setBinding(data: ViewData, marker: Part?): boolean
	if data.boundMarker ~= marker then
		data.boundMarker = marker
		data.markerRebindCount += 1
	end
	local instances = data.instances
	if instances == nil then
		return marker == nil
	end
	local state = data.cachedState
	local currentInstances = instances :: ViewInstances
	local updated = pcall(function()
		data.dependencies.setGuiBinding(
			currentInstances.gui,
			marker,
			marker ~= nil and state ~= nil and (state :: CanonicalRenderState).visible
		)
	end)
	return updated
end

reconcileMarker = function(data: ViewData): boolean
	if data.cleaned or data.reconcilingMarker then
		return not data.cleaned
	end
	data.reconcilingMarker = true
	local path = inspectMarkerPath(data)
	if not sameMarkerPath(data.markerPath, path) then
		data.markerPath = path
	end
	if not installMarkerWatchers(data, path) then
		setBinding(data, nil)
		data.reconcilingMarker = false
		return false
	end
	local marker = if markerMatchesState(path, data.cachedState, data.workspaceRoot) then path.marker else nil
	local succeeded = setBinding(data, marker)
	data.reconcilingMarker = false
	return succeeded
end

local function validateDependencies(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local dependencies = value :: { [any]: unknown }
	if
		not hasExactKeys(dependencies, {
			connectWorkspaceDescendantAdded = true,
			connectWorkspaceDescendantRemoving = true,
			connectPlayerGuiChildAdded = true,
			connectPlayerGuiChildRemoved = true,
			connectAncestryChanged = true,
			connectPropertyChanged = true,
			createPulseTween = true,
			setGuiBinding = true,
		})
	then
		return false
	end
	for _, name in
		{
			"connectWorkspaceDescendantAdded",
			"connectWorkspaceDescendantRemoving",
			"connectPlayerGuiChildAdded",
			"connectPlayerGuiChildRemoved",
			"connectAncestryChanged",
			"connectPropertyChanged",
			"createPulseTween",
			"setGuiBinding",
		}
	do
		if type(rawget(dependencies, name)) ~= "function" then
			return false
		end
	end
	return true
end

local function installFixedConnections(data: ViewData): boolean
	local records = {
		{ connector = data.dependencies.connectWorkspaceDescendantAdded, marker = true },
		{ connector = data.dependencies.connectWorkspaceDescendantRemoving, marker = true },
		{ connector = data.dependencies.connectPlayerGuiChildAdded, marker = false },
		{ connector = data.dependencies.connectPlayerGuiChildRemoved, marker = false },
	}
	for _, record in records do
		if
			not addConnection(data.fixedConnections, function()
				return record.connector(function()
					if record.marker then
						onMarkerInvalidated(data)
					else
						onViewInvalidated(data)
					end
				end)
			end)
		then
			disconnectAll(data.fixedConnections)
			return false
		end
	end
	return #data.fixedConnections == FIXED_CONNECTION_COUNT
end

local function construct(
	playerGuiParent: Instance,
	workspaceRoot: Instance,
	dependencies: TestDependencies,
	applyProduction: boolean
): Result.Result<View, Error>
	if typeof(playerGuiParent) ~= "Instance" or typeof(workspaceRoot) ~= "Instance" then
		return failure("INVALID_PARENT")
	end
	if not validateDependencies(dependencies) then
		return failure("INVALID_DEPENDENCIES")
	end
	if playerGuiParent:FindFirstChild(GUI_NAME) ~= nil then
		return failure("CREATION_FAILED")
	end

	local view = setmetatable({}, ViewMethods) :: any
	table.freeze(view)
	local data: ViewData = {
		playerGuiParent = playerGuiParent,
		workspaceRoot = workspaceRoot,
		dependencies = dependencies,
		instances = nil,
		boundMarker = nil,
		markerPath = {
			runtimeRoot = nil,
			markers = nil,
			marker = nil,
		},
		cachedState = nil,
		activeTween = nil,
		lastPulseRevision = nil,
		fixedConnections = {},
		markerWatcherConnections = {},
		viewWatcherConnections = {},
		callbacksEnabled = false,
		reconcilingMarker = false,
		reconcilingView = false,
		suppressViewCallbacks = false,
		cleaned = false,
		renderCount = 0,
		viewRecreationCount = 0,
		markerRebindCount = 0,
		tweenCreationCount = 0,
		callbackFailureCount = 0,
		renderedFillScale = 0,
		applyProductionLayout = applyProduction,
	}
	VIEW_DATA[view] = data

	if not installFixedConnections(data) then
		VIEW_DATA[view] = nil
		return failure("CONNECTION_FAILED")
	end
	data.callbacksEnabled = true
	if not reconcileView(data) then
		data.callbacksEnabled = false
		disconnectAll(data.fixedConnections)
		destroyOwnedView(data)
		VIEW_DATA[view] = nil
		return failure("CREATION_FAILED")
	end
	return Result.ok(view :: View)
end

function ViewMethods.render(self: View, renderState: unknown): Result.Result<Metrics, Error>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local canonical = canonicalizeRenderState(renderState)
	if canonical == nil then
		return failure("INVALID_RENDER_STATE")
	end
	data.cachedState = canonical
	if not reconcileView(data) then
		return failure("RENDER_FAILED")
	end
	if not applyRenderState(data, canonical, true) then
		return failure("RENDER_FAILED")
	end
	if not reconcileMarker(data) then
		return failure("RENDER_FAILED")
	end
	data.renderCount += 1
	return Result.ok(metrics(data))
end

function ViewMethods.getMetrics(self: View): Result.Result<Metrics, Error>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	return Result.ok(metrics(data))
end

function ViewMethods.cleanup(self: View): Result.Result<boolean, Error>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(true)
	end
	data.cleaned = true
	data.callbacksEnabled = false
	local succeeded = disconnectAll(data.fixedConnections)
	if not disconnectAll(data.markerWatcherConnections) then
		succeeded = false
	end
	if not destroyOwnedView(data) then
		succeeded = false
	end
	data.boundMarker = nil
	data.markerPath = {
		runtimeRoot = nil,
		markers = nil,
		marker = nil,
	}
	data.cachedState = nil
	data.lastPulseRevision = nil
	if not succeeded then
		return failure("CLEANUP_FAILED")
	end
	return Result.ok(true)
end

local function productionDependencies(playerGui: PlayerGui): TestDependencies
	return {
		connectWorkspaceDescendantAdded = function(callback)
			return Workspace.DescendantAdded:Connect(function(_descendant)
				callback()
			end)
		end,
		connectWorkspaceDescendantRemoving = function(callback)
			return Workspace.DescendantRemoving:Connect(function(_descendant)
				callback()
			end)
		end,
		connectPlayerGuiChildAdded = function(callback)
			return playerGui.ChildAdded:Connect(function(_child)
				callback()
			end)
		end,
		connectPlayerGuiChildRemoved = function(callback)
			return playerGui.ChildRemoved:Connect(function(_child)
				callback()
			end)
		end,
		connectAncestryChanged = function(target, callback)
			return target.AncestryChanged:Connect(function(_child, _parent)
				callback()
			end)
		end,
		connectPropertyChanged = function(target, propertyName, callback)
			return target:GetPropertyChangedSignal(propertyName):Connect(callback)
		end,
		createPulseTween = function(label)
			local tween =
				TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				})
			return {
				play = function()
					tween:Play()
				end,
				cancel = function()
					tween:Cancel()
				end,
				destroy = function()
					tween:Destroy()
				end,
			}
		end,
		setGuiBinding = function(gui, marker, enabled)
			gui.Adornee = marker
			gui.Enabled = enabled
		end,
	}
end

function BaseWorldView.new(): Result.Result<View, Error>
	local player = Players.LocalPlayer
	if player == nil then
		return failure("INVALID_PARENT")
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil or not playerGui:IsA("PlayerGui") then
		return failure("INVALID_PARENT")
	end
	return construct(playerGui, Workspace, productionDependencies(playerGui), true)
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "BaseWorldView" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionClientBase" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

if isExactTestModule() then
	BaseWorldView.newForTests = function(
		playerGuiParent: Instance,
		workspaceRoot: Instance,
		dependencies: TestDependencies
	): Result.Result<View, Error>
		return construct(playerGuiParent, workspaceRoot, dependencies, false)
	end
end

table.freeze(ViewMethods)
return table.freeze(BaseWorldView)
