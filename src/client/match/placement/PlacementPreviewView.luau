--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PlacementProtocol = require(ReplicatedStorage.Shared.match.PlacementProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type UiAction = {
	kind: "SelectSlot" | "Confirm" | "Cancel" | "Rotate",
	slot: number?,
}

export type UiActionCallback = (UiAction) -> ()
export type Dependencies = {
	connectActivated: (GuiButton, () -> ()) -> RBXScriptConnection,
}

export type Metrics = {
	connectionCount: number,
	worldPartCount: number,
	renderCount: number,
	previewVisible: boolean,
	rangeVisible: boolean,
	reticleVisible: boolean,
	selectedSlot: number?,
	statusText: string,
	hintText: string,
	cleaned: boolean,
}

export type ErrorCode =
	"INVALID_ARGUMENT"
	| "INVALID_PARENT"
	| "CREATION_FAILED"
	| "CONNECTION_FAILED"
	| "INVALID_STATE"
	| "RENDER_FAILED"
	| "CLEANUP_FAILED"
	| "CLEANED_UP"

export type Error = {
	code: ErrorCode,
}

type ViewInstances = {
	gui: ScreenGui,
	root: Frame,
	hotbar: Frame,
	buttons: { TextButton },
	status: TextLabel,
	hint: TextLabel,
	confirm: TextButton,
	cancel: TextButton,
	rotate: TextButton,
	reticle: TextLabel,
	worldFolder: Folder,
	ghost: Part,
	range: Part,
}

type ViewData = {
	instances: ViewInstances,
	connections: { RBXScriptConnection },
	actionCallback: UiActionCallback,
	dependencies: Dependencies,
	cleaned: boolean,
	renderCount: number,
	previewVisible: boolean,
	rangeVisible: boolean,
	reticleVisible: boolean,
	selectedSlot: number?,
	statusText: string,
	hintText: string,
	applyProductionLayout: boolean,
}

local ViewMethods = {}
ViewMethods.__index = ViewMethods

export type View = typeof(setmetatable({} :: {}, ViewMethods))
export type ViewResult = Result.Result<View, Error>
export type TestConstructor = (Instance, Instance, UiActionCallback, Dependencies) -> ViewResult
export type ResponsiveLayout = {
	horizontalMargin: number,
	panelWidth: number,
	slotWidth: number,
}
export type ResponsiveLayoutResolver = (unknown) -> ResponsiveLayout?

local VIEW_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ViewData }

local GUI_NAME = "ATDPlacementPreview"
local WORLD_FOLDER_NAME = "_ATDPlacementPreview"
local FIXED_CONNECTION_COUNT = 8
local WORLD_PART_COUNT = 2
local PANEL_REFERENCE_WIDTH = 700
local PANEL_HORIZONTAL_MARGIN = 12

local function horizontalScale(referenceOffset: number): number
	return referenceOffset / PANEL_REFERENCE_WIDTH
end

local function resolveResponsiveLayout(viewportWidthValue: unknown): ResponsiveLayout?
	if
		type(viewportWidthValue) ~= "number"
		or not Validation.isFiniteNumber(viewportWidthValue)
		or viewportWidthValue <= PANEL_HORIZONTAL_MARGIN * 2
	then
		return nil
	end
	local panelWidth = math.min(PANEL_REFERENCE_WIDTH, viewportWidthValue - PANEL_HORIZONTAL_MARGIN * 2)
	return table.freeze({
		horizontalMargin = PANEL_HORIZONTAL_MARGIN,
		panelWidth = panelWidth,
		slotWidth = panelWidth * horizontalScale(90),
	})
end

local function colorFromRGB(red: number, green: number, blue: number): Color3
	local succeeded, value = pcall(function(): Color3
		return Color3.fromRGB(red, green, blue)
	end)
	if succeeded then
		return value
	end
	-- The headless Roblox adapter does not expose the Color3 constructor.
	-- A property-derived fallback keeps the production module executable there;
	-- production always takes the authored RGB path above.
	local proxy = Instance.new("Part")
	local fallback = proxy.Color
	proxy:Destroy()
	return fallback
end

local COLORS = table.freeze({
	Neutral = colorFromRGB(43, 48, 58),
	Selected = colorFromRGB(72, 94, 125),
	Valid = colorFromRGB(66, 210, 112),
	Invalid = colorFromRGB(235, 82, 82),
	Warning = colorFromRGB(250, 178, 65),
	Unavailable = colorFromRGB(145, 151, 165),
	Text = colorFromRGB(245, 247, 250),
})

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_ARGUMENT = table.freeze({ code = "INVALID_ARGUMENT" :: "INVALID_ARGUMENT" }),
	INVALID_PARENT = table.freeze({ code = "INVALID_PARENT" :: "INVALID_PARENT" }),
	CREATION_FAILED = table.freeze({ code = "CREATION_FAILED" :: "CREATION_FAILED" }),
	CONNECTION_FAILED = table.freeze({ code = "CONNECTION_FAILED" :: "CONNECTION_FAILED" }),
	INVALID_STATE = table.freeze({ code = "INVALID_STATE" :: "INVALID_STATE" }),
	RENDER_FAILED = table.freeze({ code = "RENDER_FAILED" :: "RENDER_FAILED" }),
	CLEANUP_FAILED = table.freeze({ code = "CLEANUP_FAILED" :: "CLEANUP_FAILED" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local PlacementPreviewView = {
	GUI_NAME = GUI_NAME,
	WORLD_FOLDER_NAME = WORLD_FOLDER_NAME,
	FIXED_CONNECTION_COUNT = FIXED_CONNECTION_COUNT,
	WORLD_PART_COUNT = WORLD_PART_COUNT,
	newForTests = nil :: TestConstructor?,
	resolveResponsiveLayoutForTests = nil :: ResponsiveLayoutResolver?,
}

local function failure(code: ErrorCode)
	return Result.err(ERRORS[code])
end

local function requireData(value: unknown): ViewData
	if type(value) ~= "table" then
		error("[ATD_PLACEMENT_PREVIEW_VIEW][code=INVALID_CONTEXT]", 0)
	end
	local data = VIEW_DATA[value :: any]
	if data == nil then
		error("[ATD_PLACEMENT_PREVIEW_VIEW][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function makeTextLabel(name: string, parent: Instance, applyProductionLayout: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextColor3 = COLORS.Text
	if applyProductionLayout then
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
	end
	label.Parent = parent
	return label
end

local function makeButton(name: string, parent: Instance, applyProductionLayout: boolean): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = true
	button.BackgroundColor3 = COLORS.Neutral
	button.BorderSizePixel = 2
	button.BorderColor3 = COLORS.Unavailable
	button.TextColor3 = COLORS.Text
	if applyProductionLayout then
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
	end
	button.Parent = parent
	return button
end

local function makePreviewPart(name: string, parent: Instance, applyProductionLayout: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	if applyProductionLayout then
		part.Material = Enum.Material.ForceField
	end
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function createInstances(
	guiParent: Instance,
	worldParent: Instance,
	applyProductionStyle: boolean,
	applyResponsiveLayout: boolean
): ViewInstances?
	if guiParent:FindFirstChild(GUI_NAME) ~= nil or worldParent:FindFirstChild(WORLD_FOLDER_NAME) ~= nil then
		return nil
	end
	local created: ViewInstances? = nil
	local succeeded = pcall(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = GUI_NAME
		gui.DisplayOrder = 20
		gui.IgnoreGuiInset = false
		gui.ResetOnSpawn = false
		if applyProductionStyle then
			gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
			gui.ClipToDeviceSafeArea = true
			gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		end
		gui.Parent = guiParent

		local root = Instance.new("Frame")
		root.Name = "PlacementPanel"
		root.AnchorPoint = Vector2.new(0.5, 1)
		if applyResponsiveLayout then
			root.Position = UDim2.new(0.5, 0, 1, -18)
			root.Size = UDim2.new(1, -PANEL_HORIZONTAL_MARGIN * 2, 0, 154)
			root.ClipsDescendants = true
			local responsiveBounds = Instance.new("UISizeConstraint")
			responsiveBounds.Name = "ResponsiveBounds"
			responsiveBounds.MaxSize = Vector2.new(PANEL_REFERENCE_WIDTH, 154)
			responsiveBounds.Parent = root
		end
		root.BackgroundColor3 = colorFromRGB(24, 27, 34)
		root.BackgroundTransparency = 0.12
		root.BorderSizePixel = 0
		root.Parent = gui

		local hotbar = Instance.new("Frame")
		hotbar.Name = "TemporaryLoadout"
		hotbar.BackgroundTransparency = 1
		if applyResponsiveLayout then
			hotbar.Position = UDim2.new(horizontalScale(12), 0, 0, 48)
			hotbar.Size = UDim2.new(horizontalScale(500), 0, 0, 94)
		end
		hotbar.Parent = root

		local buttons: { TextButton } = {}
		for slot = 1, PlacementProtocol.MAX_LOADOUT_SLOTS do
			local button = makeButton(`Slot{slot}`, hotbar, applyProductionStyle)
			if applyResponsiveLayout then
				button.Position = UDim2.fromScale((slot - 1) * (98 / 500), 0)
				button.Size = UDim2.new(90 / 500, 0, 0, 90)
			end
			button.Text = `{slot}\n—`
			table.insert(buttons, button)
		end

		local status = makeTextLabel("Status", root, applyProductionStyle)
		if applyResponsiveLayout then
			status.Position = UDim2.new(horizontalScale(12), 0, 0, 8)
			status.Size = UDim2.new(horizontalScale(480), 0, 0, 34)
			status.TextXAlignment = Enum.TextXAlignment.Left
		end
		status.Text = "○ SELECT A TOWER"

		local hint = makeTextLabel("InputHint", root, applyProductionStyle)
		if applyResponsiveLayout then
			hint.Position = UDim2.new(horizontalScale(500), 0, 0, 8)
			hint.Size = UDim2.new(horizontalScale(188), 0, 0, 34)
			hint.TextXAlignment = Enum.TextXAlignment.Right
		end
		hint.Text = "1–5 Select • R Rotate • Click Place • Q Cancel"

		local confirm = makeButton("TouchConfirm", root, applyProductionStyle)
		if applyResponsiveLayout then
			confirm.Position = UDim2.new(horizontalScale(518), 0, 0, 48)
			confirm.Size = UDim2.new(horizontalScale(170), 0, 0, 42)
		end
		confirm.Text = "✓ CONFIRM"
		confirm.BackgroundColor3 = COLORS.Valid
		confirm.Visible = false

		local rotate = makeButton("TouchRotate", root, applyProductionStyle)
		if applyResponsiveLayout then
			rotate.Position = UDim2.new(horizontalScale(518), 0, 0, 96)
			rotate.Size = UDim2.new(horizontalScale(82), 0, 0, 46)
		end
		rotate.Text = "↻ 15°"
		rotate.Visible = false

		local cancel = makeButton("TouchCancel", root, applyProductionStyle)
		if applyResponsiveLayout then
			cancel.Position = UDim2.new(horizontalScale(606), 0, 0, 96)
			cancel.Size = UDim2.new(horizontalScale(82), 0, 0, 46)
		end
		cancel.Text = "✕"
		cancel.BackgroundColor3 = COLORS.Invalid
		cancel.Visible = false

		local reticle = makeTextLabel("GamepadReticle", gui, applyProductionStyle)
		reticle.AnchorPoint = Vector2.new(0.5, 0.5)
		if applyResponsiveLayout then
			reticle.Size = UDim2.fromOffset(42, 42)
		end
		reticle.Text = "⊕"
		reticle.TextColor3 = COLORS.Valid
		reticle.TextStrokeTransparency = 0
		reticle.Visible = false

		local worldFolder = Instance.new("Folder")
		worldFolder.Name = WORLD_FOLDER_NAME
		worldFolder.Parent = worldParent

		local ghost = makePreviewPart("Ghost", worldFolder, applyProductionStyle)
		if applyProductionStyle then
			ghost.Shape = Enum.PartType.Block
		end

		local range = makePreviewPart("RangeIndicator", worldFolder, applyProductionStyle)
		if applyProductionStyle then
			range.Shape = Enum.PartType.Cylinder
		end

		created = {
			gui = gui,
			root = root,
			hotbar = hotbar,
			buttons = buttons,
			status = status,
			hint = hint,
			confirm = confirm,
			cancel = cancel,
			rotate = rotate,
			reticle = reticle,
			worldFolder = worldFolder,
			ghost = ghost,
			range = range,
		}
	end)
	if not succeeded then
		local gui = guiParent:FindFirstChild(GUI_NAME)
		if gui ~= nil then
			gui:Destroy()
		end
		local worldFolder = worldParent:FindFirstChild(WORLD_FOLDER_NAME)
		if worldFolder ~= nil then
			worldFolder:Destroy()
		end
		return nil
	end
	return created
end

local function statusPresentation(validity: string, phase: string, lastRejection: unknown): (string, Color3)
	if phase == "Submitting" then
		return "… PLACING — SERVER VALIDATION", COLORS.Warning
	elseif type(lastRejection) == "string" then
		return `! SERVER: {string.upper(lastRejection)}`, COLORS.Warning
	elseif phase == "Idle" then
		return "○ SELECT A TOWER", COLORS.Unavailable
	elseif phase == "Selected" or validity == "None" then
		return "◇ CHOOSE A POSITION", COLORS.Selected
	elseif validity == "Valid" then
		return "✓ VALID — READY TO CONFIRM", COLORS.Valid
	elseif validity == "Unaffordable" then
		return "$ NOT AFFORDABLE", COLORS.Warning
	elseif validity == "Capped" then
		return "! TOWER CAP REACHED", COLORS.Warning
	elseif validity == "InvalidSurface" then
		return "≈ SURFACE NOT SUPPORTED", COLORS.Invalid
	elseif validity == "OutsideZone" then
		return "▱ OUTSIDE PLACEMENT ZONE", COLORS.Invalid
	elseif validity == "Excluded" then
		return "⊘ BLOCKED AREA", COLORS.Invalid
	elseif validity == "Occupied" then
		return "◉ SPACE OCCUPIED", COLORS.Invalid
	end
	return "✕ INVALID POSITION", COLORS.Invalid
end

local function hintFor(inputFamily: string): string
	if inputFamily == "Touch" then
		return "Tap Position • Then Confirm"
	elseif inputFamily == "Gamepad" then
		return "L Move • A Confirm • B Cancel • RB Rotate"
	end
	return "1–5 Select • R Rotate • Click Place • Q Cancel"
end

local function validRenderState(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local state = value :: any
	if
		(
			state.phase ~= "Idle"
			and state.phase ~= "Selected"
			and state.phase ~= "Positioned"
			and state.phase ~= "Submitting"
		)
		or (state.preferredInput ~= "Desktop" and state.preferredInput ~= "Touch" and state.preferredInput ~= "Gamepad")
		or type(state.yawDegrees) ~= "number"
		or not Validation.isFiniteNumber(state.yawDegrees)
		or type(state.validity) ~= "string"
		or type(state.canConfirm) ~= "boolean"
	then
		return false
	end
	if state.snapshot ~= nil and not PlacementProtocol.validateQuerySnapshot(state.snapshot).ok then
		return false
	end
	if
		state.selectedSlot ~= nil
		and (type(state.selectedSlot) ~= "number" or state.selectedSlot < 1 or state.selectedSlot > 5)
	then
		return false
	end
	if state.worldPosition ~= nil then
		local position = state.worldPosition
		if
			typeof(position) ~= "Vector3"
			or not Validation.isFiniteNumber(position.X)
			or not Validation.isFiniteNumber(position.Y)
			or not Validation.isFiniteNumber(position.Z)
		then
			return false
		end
	end
	return true
end

local function disconnectAll(connections: { RBXScriptConnection }): boolean
	local succeeded = true
	for index = #connections, 1, -1 do
		local connection = connections[index]
		connections[index] = nil
		if not pcall(function()
			connection:Disconnect()
		end) then
			succeeded = false
		end
	end
	return succeeded
end

local function connectActions(data: ViewData): boolean
	local instances = data.instances
	local bindings: { { button: GuiButton, action: UiAction } } = {}
	for slot, button in instances.buttons do
		table.insert(bindings, {
			button = button,
			action = table.freeze({ kind = "SelectSlot", slot = slot }),
		})
	end
	table.insert(bindings, { button = instances.confirm, action = table.freeze({ kind = "Confirm" }) })
	table.insert(bindings, { button = instances.cancel, action = table.freeze({ kind = "Cancel" }) })
	table.insert(bindings, { button = instances.rotate, action = table.freeze({ kind = "Rotate" }) })
	for _, binding in bindings do
		local connected, connection = pcall(data.dependencies.connectActivated, binding.button, function()
			if data.cleaned then
				return
			end
			local called = pcall(data.actionCallback, binding.action)
			local _ = called
		end)
		if not connected or typeof(connection) ~= "RBXScriptConnection" then
			disconnectAll(data.connections)
			return false
		end
		table.insert(data.connections, connection :: RBXScriptConnection)
	end
	return #data.connections == FIXED_CONNECTION_COUNT
end

local function construct(
	guiParent: Instance,
	worldParent: Instance,
	actionCallback: UiActionCallback,
	dependencies: Dependencies,
	applyProductionStyle: boolean,
	applyResponsiveLayout: boolean
): ViewResult
	if typeof(guiParent) ~= "Instance" or typeof(worldParent) ~= "Instance" then
		return failure("INVALID_PARENT")
	end
	if
		type(actionCallback) ~= "function"
		or type(dependencies) ~= "table"
		or type(dependencies.connectActivated) ~= "function"
	then
		return failure("INVALID_ARGUMENT")
	end
	local instances = createInstances(guiParent, worldParent, applyProductionStyle, applyResponsiveLayout)
	if instances == nil then
		return failure("CREATION_FAILED")
	end
	local view = setmetatable({}, ViewMethods) :: View
	table.freeze(view)
	local data: ViewData = {
		instances = instances,
		connections = {},
		actionCallback = actionCallback,
		dependencies = dependencies,
		cleaned = false,
		renderCount = 0,
		previewVisible = false,
		rangeVisible = false,
		reticleVisible = false,
		selectedSlot = nil,
		statusText = "○ SELECT A TOWER",
		hintText = hintFor("Desktop"),
		applyProductionLayout = applyResponsiveLayout,
	}
	VIEW_DATA[view] = data
	if not connectActions(data) then
		instances.gui:Destroy()
		instances.worldFolder:Destroy()
		VIEW_DATA[view] = nil
		return failure("CONNECTION_FAILED")
	end
	return Result.ok(view)
end

function ViewMethods.render(self: View, value: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not validRenderState(value) then
		return failure("INVALID_STATE")
	end
	local state = value :: any
	local instances = data.instances
	local succeeded = pcall(function()
		instances.gui.Enabled = state.snapshot ~= nil
		for slot, button in instances.buttons do
			local metadata = if state.snapshot == nil then nil else state.snapshot.slots[slot]
			local occupied = metadata ~= nil and metadata.kind == "Occupied"
			button.Active = occupied
			button.AutoButtonColor = occupied
			button.Text = if occupied
				then `{slot}\n{metadata.displayName}\n${metadata.placementCost}`
				else `{slot}\n—`
			button.BackgroundColor3 = if state.selectedSlot == slot then COLORS.Selected else COLORS.Neutral
			button.BorderColor3 = if state.selectedSlot == slot then COLORS.Valid else COLORS.Unavailable
		end

		local statusText, statusColor = statusPresentation(state.validity, state.phase, state.lastRejection)
		instances.status.Text = statusText
		instances.status.TextColor3 = statusColor
		instances.hint.Text = hintFor(state.preferredInput)
		local touchSelected = state.preferredInput == "Touch" and state.selectedSlot ~= nil
		instances.confirm.Visible = touchSelected and state.phase == "Positioned"
		instances.confirm.Active = state.canConfirm
		instances.confirm.AutoButtonColor = state.canConfirm
		instances.confirm.BackgroundColor3 = if state.canConfirm then COLORS.Valid else COLORS.Unavailable
		instances.cancel.Visible = touchSelected
		instances.rotate.Visible = touchSelected

		local metadata = state.selectedMetadata
		local worldPosition = state.worldPosition
		local visible = metadata ~= nil and worldPosition ~= nil and state.phase ~= "Submitting"
		if visible then
			local radius = metadata.footprintRadiusStuds
			local height = math.max(2, radius * 2)
			local color = if state.validity == "Valid"
				then COLORS.Valid
				elseif state.validity == "Capped" or state.validity == "Unaffordable" then COLORS.Warning
				else COLORS.Invalid
			instances.ghost.Size = Vector3.new(radius * 2, height, radius * 2)
			instances.ghost.CFrame = CFrame.new(worldPosition + Vector3.new(0, height * 0.5, 0))
				* CFrame.Angles(0, math.rad(state.yawDegrees), 0)
			instances.ghost.Color = color
			instances.ghost.Transparency = 0.45

			local rangeDiameter = metadata.rangeStuds * 2
			instances.range.Size = Vector3.new(0.08, rangeDiameter, rangeDiameter)
			instances.range.CFrame = CFrame.new(worldPosition + Vector3.new(0, 0.04, 0))
				* CFrame.Angles(0, 0, math.rad(90))
			instances.range.Color = color
			instances.range.Transparency = 0.72
		else
			instances.ghost.Transparency = 1
			instances.range.Transparency = 1
		end

		data.renderCount += 1
		data.previewVisible = visible
		data.rangeVisible = visible
		data.selectedSlot = state.selectedSlot
		data.statusText = instances.status.Text
		data.hintText = instances.hint.Text
	end)
	if not succeeded then
		return failure("RENDER_FAILED")
	end
	return Result.ok(self:getMetrics())
end

function ViewMethods.setReticle(self: View, positionValue: unknown, visibleValue: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if typeof(positionValue) ~= "Vector2" or type(visibleValue) ~= "boolean" then
		return failure("INVALID_ARGUMENT")
	end
	local position = positionValue :: Vector2
	if not Validation.isFiniteNumber(position.X) or not Validation.isFiniteNumber(position.Y) then
		return failure("INVALID_ARGUMENT")
	end
	local succeeded = pcall(function()
		if data.applyProductionLayout then
			data.instances.reticle.Position = UDim2.fromOffset(position.X, position.Y)
		end
		data.instances.reticle.Visible = visibleValue :: boolean
	end)
	if not succeeded then
		return failure("RENDER_FAILED")
	end
	data.reticleVisible = visibleValue :: boolean
	return Result.ok(true)
end

function ViewMethods.getMetrics(self: View): Metrics
	local data = requireData(self)
	return table.freeze({
		connectionCount = #data.connections,
		worldPartCount = if data.cleaned then 0 else WORLD_PART_COUNT,
		renderCount = data.renderCount,
		previewVisible = data.previewVisible,
		rangeVisible = data.rangeVisible,
		reticleVisible = data.reticleVisible,
		selectedSlot = data.selectedSlot,
		statusText = data.statusText,
		hintText = data.hintText,
		cleaned = data.cleaned,
	})
end

function ViewMethods.cleanup(self: View)
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(true)
	end
	data.cleaned = true
	local succeeded = disconnectAll(data.connections)
	if not pcall(function()
		data.instances.gui:Destroy()
		data.instances.worldFolder:Destroy()
	end) then
		succeeded = false
	end
	data.previewVisible = false
	data.rangeVisible = false
	data.reticleVisible = false
	data.selectedSlot = nil
	if not succeeded then
		return failure("CLEANUP_FAILED")
	end
	return Result.ok(true)
end

local function productionDependencies(): Dependencies
	return {
		connectActivated = function(button, callback)
			return button.Activated:Connect(callback)
		end,
	}
end

function PlacementPreviewView.new(actionCallback: UiActionCallback): ViewResult
	local player = Players.LocalPlayer
	local playerGui = if player == nil then nil else player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return failure("INVALID_PARENT")
	end
	return construct(playerGui, Workspace, actionCallback, productionDependencies(), true, true)
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "PlacementPreviewView" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionClientPlacement" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

if isExactTestModule() then
	PlacementPreviewView.newForTests = function(
		guiParent: Instance,
		worldParent: Instance,
		actionCallback: UiActionCallback,
		dependencies: Dependencies
	): ViewResult
		return construct(guiParent, worldParent, actionCallback, dependencies, false, false)
	end
	PlacementPreviewView.resolveResponsiveLayoutForTests = resolveResponsiveLayout
end

table.freeze(ViewMethods)
return table.freeze(PlacementPreviewView)
