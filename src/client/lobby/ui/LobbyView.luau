--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local UserInputService = game:GetService("UserInputService")

local LobbyUiModel = require(script.Parent.LobbyUiModel)

local function findCommonUi(): Instance
	local clientRoot = script.Parent.Parent.Parent
	local common = clientRoot:FindFirstChild("common")
	local production = if common == nil then nil else common:FindFirstChild("ui")
	if production ~= nil then
		return production
	end
	local automatedTests = script.Parent.Parent
	local mirrored = automatedTests:FindFirstChild("ProductionClientCommonUi")
	if mirrored ~= nil then
		return mirrored
	end
	error("[ATD_LOBBY_VIEW][code=COMMON_UI_MISSING]", 0)
end

local commonUi = findCommonUi()
local ResponsiveLayout = require(commonUi.ResponsiveLayout)
local Theme = require(commonUi.Theme)

export type InputFamily = LobbyUiModel.InputFamily
export type PrimaryScreen = LobbyUiModel.PrimaryScreen

export type ActionKind =
	"Navigate"
	| "Back"
	| "RetryProfile"
	| "SafeLeave"
	| "Play"
	| "SelectTower"
	| "CloseTowerDetails"
	| "EquipTower"
	| "UnequipTower"
	| "ToggleFavorite"
	| "ToggleLock"
	| "PullChest"
	| "SkipChestPresentation"
	| "UpdateSetting"
	| "ConfirmModal"
	| "CancelModal"
	| "DismissToast"
	| "InputFamilyChanged"
	| "InventoryQueryChanged"
	| "InventorySortChanged"
	| "InventoryFilterChanged"
	| "CreateParty"
	| "InvitePartyMember"
	| "AcceptPartyInvite"
	| "DeclinePartyInvite"
	| "LeaveParty"
	| "KickPartyMember"
	| "TransferPartyLeadership"
	| "TogglePartyPrivacy"
	| "DisbandParty"
	| "PromptPartyInvite"
	| "SelectQueue"
	| "JoinQueue"
	| "LeaveQueue"
	| "ConfigureQueue"
	| "StartQueue"
	| "ReconnectActiveMatch"

export type Action = {
	kind: ActionKind,
	source: InputFamily,
	profileRevision: number?,
	screen: PrimaryScreen?,
	unitId: string?,
	towerId: string?,
	quantity: number?,
	enabled: boolean?,
	settingKey: string?,
	settingValue: boolean | number?,
	modalId: string?,
	toastId: string?,
	inputFamily: InputFamily?,
	textValue: string?,
	targetUserId: number?,
	invitationId: string?,
	queueId: string?,
	configuration: {
		mapId: string,
		difficultyId: string,
		privacy: "Public" | "PartyOnly",
		maxPlayers: number,
	}?,
}

export type Callback = (Action) -> ()

export type Dependencies = {
	connectActivated: (GuiButton, () -> ()) -> RBXScriptConnection,
	connectInputBegan: ((string, boolean) -> ()) -> RBXScriptConnection,
	connectInputFamilyChanged: ((InputFamily) -> ()) -> RBXScriptConnection,
	connectSearchCommitted: (TextBox, (string) -> ()) -> RBXScriptConnection,
	selectObject: (GuiObject?) -> (),
	getSelectedObject: () -> GuiObject?,
}

export type ErrorCode =
	"INVALID_ARGUMENT"
	| "INVALID_PARENT"
	| "GUI_CONFLICT"
	| "CREATION_FAILED"
	| "CONNECTION_FAILED"
	| "INVALID_RENDER_STATE"
	| "RENDER_FAILED"
	| "CLEANUP_FAILED"
	| "CLEANED_UP"

export type Error = { code: ErrorCode }
export type Outcome<T> = { ok: true, value: T } | { ok: false, error: Error }

export type Metrics = {
	profileState: LobbyUiModel.ProfileState?,
	activeScreen: PrimaryScreen?,
	modalDepth: number,
	toastCount: number,
	inventoryCardCount: number,
	staticConnectionCount: number,
	dynamicConnectionCount: number,
	renderCount: number,
	actionCount: number,
	goldText: string,
	blockingVisible: boolean,
	cleaned: boolean,
}

type Instances = {
	gui: ScreenGui,
	root: Frame,
	uiScale: UIScale,
	header: Frame,
	title: TextLabel,
	readiness: TextLabel,
	gold: TextLabel,
	backButton: TextButton,
	navigation: Frame,
	navigationButtons: { [PrimaryScreen]: TextButton },
	content: Frame,
	screens: { [PrimaryScreen]: Frame },
	homeStatus: TextLabel,
	homeProgression: TextLabel,
	playButton: TextButton,
	partyScroll: ScrollingFrame,
	partyHeading: TextLabel,
	partyStatus: TextLabel,
	partyInviteInput: TextBox,
	partyCreateButton: TextButton,
	partyInviteButton: TextButton,
	partyPlatformInviteButton: TextButton,
	partyPrivacyButton: TextButton,
	partyLeaveButton: TextButton,
	partyDisbandButton: TextButton,
	partyList: ScrollingFrame,
	queueScroll: ScrollingFrame,
	queueHeading: TextLabel,
	queueStatus: TextLabel,
	queueList: ScrollingFrame,
	queueRoster: TextLabel,
	queueConfiguration: TextLabel,
	queueJoinButton: TextButton,
	queueLeaveButton: TextButton,
	queueMapButton: TextButton,
	queueDifficultyButton: TextButton,
	queuePrivacyButton: TextButton,
	queueCapacityButton: TextButton,
	queueStartButton: TextButton,
	reconnectButton: TextButton,
	inventorySearch: TextBox,
	inventorySort: TextButton,
	inventoryFilter: TextButton,
	inventoryGrid: ScrollingFrame,
	inventoryGridLayout: UIGridLayout,
	detailPanel: ScrollingFrame,
	detailBackButton: TextButton,
	detailTitle: TextLabel,
	detailOwnership: TextLabel,
	detailDescription: TextLabel,
	detailStats: TextLabel,
	detailUpgrade: TextLabel,
	equipButton: TextButton,
	favoriteButton: TextButton,
	lockButton: TextButton,
	chestScroll: ScrollingFrame,
	chestTitle: TextLabel,
	chestPolicy: TextLabel,
	chestPity: TextLabel,
	chestOdds: TextLabel,
	onePullButton: TextButton,
	tenPullButton: TextButton,
	skipButton: TextButton,
	settingsList: ScrollingFrame,
	settingsButtons: { [string]: TextButton },
	blocking: Frame,
	blockingTitle: TextLabel,
	blockingMessage: TextLabel,
	retryButton: TextButton,
	leaveButton: TextButton,
	modalScrim: Frame,
	modalPanel: Frame,
	modalDepth: TextLabel,
	modalTitle: TextLabel,
	modalMessage: TextLabel,
	modalConfirm: TextButton,
	modalCancel: TextButton,
	toastContainer: Frame,
	allLabels: { TextLabel },
	allButtons: { TextButton },
}

type FocusEntry = { object: GuiObject? }

type ViewData = {
	instances: Instances,
	callback: Callback,
	dependencies: Dependencies,
	connections: { RBXScriptConnection },
	dynamicConnections: { RBXScriptConnection },
	current: LobbyUiModel.RenderState?,
	focusStack: { FocusEntry },
	localSelectedUnitId: string?,
	partyInviteText: string,
	inventoryQuery: string,
	inventorySort: "Name" | "Copies" | "Equipped",
	inventoryFilter: "All" | "Equipped" | "Favorites" | "Locked",
	renderCount: number,
	actionCount: number,
	inventoryCardCount: number,
	goldText: string,
	blockingVisible: boolean,
	cleaned: boolean,
	productionStyle: boolean,
	compactMode: boolean,
}

local ViewMethods = {}
ViewMethods.__index = ViewMethods

export type View = typeof(setmetatable({} :: {}, ViewMethods))
export type ViewResult = Outcome<View>
export type TestConstructor = (Instance, Callback, Dependencies) -> ViewResult

local GUI_NAME = "ATDLobbyGui"
local MAX_QUERY_BYTES = 48
local NAVIGATION_ORDER: { PrimaryScreen } =
	table.freeze({ "Home", "Party", "Queue", "Inventory", "Chests", "Settings" })
local SETTING_ORDER: { string } = table.freeze({
	"masterVolume",
	"musicVolume",
	"sfxVolume",
	"uiVolume",
	"cameraShakeIntensity",
	"reducedMotionEnabled",
	"damageNumbersEnabled",
	"enemyHealthBarsEnabled",
	"otherPlayerEffectsEnabled",
	"lowDetailEnabled",
	"towerRangeEnabled",
	"uiScale",
})
local SETTING_LABELS: { [string]: string } = table.freeze({
	masterVolume = "Master Volume",
	musicVolume = "Music Volume",
	sfxVolume = "Sound Effects",
	uiVolume = "Interface Sounds",
	cameraShakeIntensity = "Camera Shake",
	reducedMotionEnabled = "Reduced Motion",
	damageNumbersEnabled = "Damage Numbers",
	enemyHealthBarsEnabled = "Enemy Health Bars",
	otherPlayerEffectsEnabled = "Other-player Effects",
	lowDetailEnabled = "Low Detail",
	towerRangeEnabled = "Tower Range",
	uiScale = "UI Scale",
})

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_ARGUMENT = table.freeze({ code = "INVALID_ARGUMENT" :: "INVALID_ARGUMENT" }),
	INVALID_PARENT = table.freeze({ code = "INVALID_PARENT" :: "INVALID_PARENT" }),
	GUI_CONFLICT = table.freeze({ code = "GUI_CONFLICT" :: "GUI_CONFLICT" }),
	CREATION_FAILED = table.freeze({ code = "CREATION_FAILED" :: "CREATION_FAILED" }),
	CONNECTION_FAILED = table.freeze({ code = "CONNECTION_FAILED" :: "CONNECTION_FAILED" }),
	INVALID_RENDER_STATE = table.freeze({ code = "INVALID_RENDER_STATE" :: "INVALID_RENDER_STATE" }),
	RENDER_FAILED = table.freeze({ code = "RENDER_FAILED" :: "RENDER_FAILED" }),
	CLEANUP_FAILED = table.freeze({ code = "CLEANUP_FAILED" :: "CLEANUP_FAILED" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ViewData }

local LobbyView = {
	GUI_NAME = GUI_NAME,
	newForTests = nil :: TestConstructor?,
}

local renderCanonical: (ViewData, LobbyUiModel.RenderState) -> ()

local function ok<T>(value: T): Outcome<T>
	return table.freeze({ ok = true :: true, value = value })
end

local function failure<T>(code: ErrorCode): Outcome<T>
	return table.freeze({ ok = false :: false, error = ERRORS[code] })
end

local function requireData(value: unknown): ViewData
	if type(value) ~= "table" or DATA[value :: any] == nil then
		error("[ATD_LOBBY_VIEW][code=INVALID_CONTEXT]", 0)
	end
	return DATA[value :: any]
end

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = 0.15
	stroke.Parent = parent
end

local function makeFrame(name: string, parent: Instance, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Theme.Colors.Surface
	frame.ZIndex = zIndex
	frame.Parent = parent
	return frame
end

local function makeLabel(name: string, parent: Instance, text: string, zIndex: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = text
	label.TextColor3 = Theme.Colors.Text
	label.TextWrapped = true
	label.RichText = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Font = Enum.Font.Gotham
	label.ZIndex = zIndex
	label.Parent = parent
	return label
end

local function makeButton(name: string, parent: Instance, text: string, zIndex: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = Theme.Colors.SurfaceRaised
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = text
	button.TextColor3 = Theme.Colors.Text
	button.TextWrapped = true
	button.RichText = false
	button.Font = Enum.Font.GothamBold
	button.ZIndex = zIndex
	button.Parent = parent
	addCorner(button, Theme.Radii.Small)
	addStroke(button, Theme.Colors.SurfaceMuted, Theme.Stroke.Normal)
	return button
end

local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then Theme.Colors.SurfaceRaised else Theme.Colors.SurfaceMuted
	button.TextTransparency = if enabled then 0 else 0.25
end

local function createInstances(parent: Instance, productionStyle: boolean): Instances?
	if parent:FindFirstChild(GUI_NAME) ~= nil then
		return nil
	end
	local gui: ScreenGui? = nil
	local result: Instances? = nil
	local succeeded = pcall(function()
		local nextGui = Instance.new("ScreenGui")
		gui = nextGui
		nextGui.Name = GUI_NAME
		nextGui.ResetOnSpawn = false
		nextGui.DisplayOrder = 40
		nextGui.IgnoreGuiInset = false
		if productionStyle then
			nextGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
			nextGui.ClipToDeviceSafeArea = true
			nextGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
			nextGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		end
		nextGui.Parent = parent

		local labels = {} :: { TextLabel }
		local buttons = {} :: { TextButton }
		local function label(name: string, owner: Instance, text: string, zIndex: number): TextLabel
			local created = makeLabel(name, owner, text, zIndex)
			table.insert(labels, created)
			return created
		end
		local function button(name: string, owner: Instance, text: string, zIndex: number): TextButton
			local created = makeButton(name, owner, text, zIndex)
			table.insert(buttons, created)
			return created
		end

		local root = makeFrame("Root", nextGui, Theme.ZIndex.Content)
		root.BackgroundColor3 = Theme.Colors.Backdrop
		root.Size = UDim2.fromScale(1, 1)

		local uiScale = Instance.new("UIScale")
		uiScale.Name = "PlayerUiScale"
		uiScale.Scale = 1
		uiScale.Parent = root

		local header = makeFrame("Header", root, Theme.ZIndex.Navigation)
		addCorner(header, Theme.Radii.Medium)
		local title = label("Title", header, "ANT TOWER DEFENSE", Theme.ZIndex.Navigation + 1)
		title.Font = Enum.Font.GothamBold
		local readiness = label("ProfileReadiness", header, "LOADING PROFILE", Theme.ZIndex.Navigation + 1)
		local gold = label("Gold", header, "GOLD —", Theme.ZIndex.Navigation + 1)
		gold.TextXAlignment = Enum.TextXAlignment.Right
		local backButton = button("Back", header, "‹ BACK", Theme.ZIndex.Navigation + 1)

		local navigation = makeFrame("Navigation", root, Theme.ZIndex.Navigation)
		addCorner(navigation, Theme.Radii.Medium)
		local navigationButtons = {} :: { [PrimaryScreen]: TextButton }
		for index, screen in NAVIGATION_ORDER do
			local navigationButton = button(screen, navigation, string.upper(screen), Theme.ZIndex.Navigation + 1)
			navigationButton.SelectionOrder = 10 + index
			navigationButtons[screen] = navigationButton
		end

		local content = makeFrame("Content", root, Theme.ZIndex.Content)
		content.BackgroundColor3 = Theme.Colors.Surface
		content.ClipsDescendants = true
		addCorner(content, Theme.Radii.Large)
		addStroke(content, Theme.Colors.SurfaceMuted, Theme.Stroke.Normal)
		local screens = {} :: { [PrimaryScreen]: Frame }
		for _, screen in NAVIGATION_ORDER do
			local screenFrame = makeFrame(`{screen}Screen`, content, Theme.ZIndex.Content + 1)
			screenFrame.BackgroundTransparency = 1
			screenFrame.Visible = false
			screens[screen] = screenFrame
		end

		local home = screens.Home
		local homeTitle = label("Heading", home, "WELCOME TO THE COLONY", Theme.ZIndex.Content + 2)
		homeTitle.Font = Enum.Font.GothamBold
		local homeStatus = label("Status", home, "", Theme.ZIndex.Content + 2)
		local homeProgression = label("Progression", home, "", Theme.ZIndex.Content + 2)
		local playButton = button("Play", home, "PLAY\nLocal Match", Theme.ZIndex.Content + 2)
		playButton.SelectionOrder = 1

		local partyScreen = screens.Party
		local party = Instance.new("ScrollingFrame")
		party.Name = "PartyContent"
		party.BackgroundTransparency = 1
		party.BorderSizePixel = 0
		party.AutomaticCanvasSize = Enum.AutomaticSize.None
		party.CanvasSize = UDim2.fromOffset(0, 0)
		party.ScrollingDirection = Enum.ScrollingDirection.Y
		party.ScrollBarThickness = 8
		party.ZIndex = Theme.ZIndex.Content + 1
		party.Parent = partyScreen
		local partyHeading = label("Heading", party, "SAME-SERVER PARTY", Theme.ZIndex.Content + 2)
		partyHeading.Font = Enum.Font.GothamBold
		local partyStatus = label("Status", party, "LOADING AUTHORITATIVE PARTY…", Theme.ZIndex.Content + 2)
		local partyInviteInput = Instance.new("TextBox")
		partyInviteInput.Name = "InviteUserId"
		partyInviteInput.BackgroundColor3 = Theme.Colors.SurfaceRaised
		partyInviteInput.BorderSizePixel = 0
		partyInviteInput.ClearTextOnFocus = false
		partyInviteInput.PlaceholderText = "Present player UserId"
		partyInviteInput.PlaceholderColor3 = Theme.Colors.TextMuted
		partyInviteInput.Text = ""
		partyInviteInput.TextColor3 = Theme.Colors.Text
		partyInviteInput.Font = Enum.Font.Gotham
		partyInviteInput.TextXAlignment = Enum.TextXAlignment.Left
		partyInviteInput.ZIndex = Theme.ZIndex.Content + 2
		partyInviteInput.SelectionOrder = 61
		partyInviteInput.Parent = party
		addCorner(partyInviteInput, Theme.Radii.Small)
		addStroke(partyInviteInput, Theme.Colors.SurfaceMuted, Theme.Stroke.Normal)
		local partyCreateButton = button("CreateParty", party, "CREATE PARTY", Theme.ZIndex.Content + 2)
		local partyInviteButton = button("InviteMember", party, "INVITE USERID", Theme.ZIndex.Content + 2)
		local partyPlatformInviteButton = button("InviteFriends", party, "INVITE FRIENDS", Theme.ZIndex.Content + 2)
		local partyPrivacyButton = button("Privacy", party, "PRIVACY", Theme.ZIndex.Content + 2)
		local partyLeaveButton = button("LeaveParty", party, "LEAVE", Theme.ZIndex.Content + 2)
		local partyDisbandButton = button("DisbandParty", party, "DISBAND", Theme.ZIndex.Content + 2)
		local partyList = Instance.new("ScrollingFrame")
		partyList.Name = "PartyRosterAndInvites"
		partyList.BackgroundColor3 = Theme.Colors.Backdrop
		partyList.BackgroundTransparency = 0.3
		partyList.BorderSizePixel = 0
		partyList.AutomaticCanvasSize = Enum.AutomaticSize.Y
		partyList.CanvasSize = UDim2.fromOffset(0, 0)
		partyList.ScrollBarThickness = 8
		partyList.ScrollingDirection = Enum.ScrollingDirection.Y
		partyList.ZIndex = Theme.ZIndex.Content + 2
		partyList.Parent = party
		addCorner(partyList, Theme.Radii.Small)
		local partyListLayout = Instance.new("UIListLayout")
		partyListLayout.Name = "Layout"
		partyListLayout.Padding = UDim.new(0, Theme.Spacing.Small)
		partyListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		partyListLayout.Parent = partyList

		local queueScreen = screens.Queue
		local queue = Instance.new("ScrollingFrame")
		queue.Name = "QueueContent"
		queue.BackgroundTransparency = 1
		queue.BorderSizePixel = 0
		queue.AutomaticCanvasSize = Enum.AutomaticSize.None
		queue.CanvasSize = UDim2.fromOffset(0, 0)
		queue.ScrollingDirection = Enum.ScrollingDirection.Y
		queue.ScrollBarThickness = 8
		queue.ZIndex = Theme.ZIndex.Content + 1
		queue.Parent = queueScreen
		local queueHeading = label("Heading", queue, "SQUAD QUEUE", Theme.ZIndex.Content + 2)
		queueHeading.Font = Enum.Font.GothamBold
		local queueStatus = label("Status", queue, "LOADING AUTHORITATIVE QUEUES…", Theme.ZIndex.Content + 2)
		local queueList = Instance.new("ScrollingFrame")
		queueList.Name = "QueueSelector"
		queueList.BackgroundColor3 = Theme.Colors.Backdrop
		queueList.BackgroundTransparency = 0.3
		queueList.BorderSizePixel = 0
		queueList.AutomaticCanvasSize = Enum.AutomaticSize.Y
		queueList.CanvasSize = UDim2.fromOffset(0, 0)
		queueList.ScrollBarThickness = 8
		queueList.ScrollingDirection = Enum.ScrollingDirection.Y
		queueList.ZIndex = Theme.ZIndex.Content + 2
		queueList.Parent = queue
		addCorner(queueList, Theme.Radii.Small)
		local queueListLayout = Instance.new("UIListLayout")
		queueListLayout.Name = "Layout"
		queueListLayout.Padding = UDim.new(0, Theme.Spacing.Small)
		queueListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		queueListLayout.Parent = queueList
		local queueRoster = label("Roster", queue, "ROSTER —", Theme.ZIndex.Content + 2)
		queueRoster.TextYAlignment = Enum.TextYAlignment.Top
		local queueConfiguration = label("Configuration", queue, "CONFIGURATION —", Theme.ZIndex.Content + 2)
		queueConfiguration.TextYAlignment = Enum.TextYAlignment.Top
		local queueJoinButton = button("JoinQueue", queue, "JOIN VIA UI", Theme.ZIndex.Content + 2)
		local queueLeaveButton = button("LeaveQueue", queue, "LEAVE QUEUE", Theme.ZIndex.Content + 2)
		local queueMapButton = button("Map", queue, "MAP", Theme.ZIndex.Content + 2)
		local queueDifficultyButton = button("Difficulty", queue, "DIFFICULTY", Theme.ZIndex.Content + 2)
		local queuePrivacyButton = button("QueuePrivacy", queue, "PRIVACY", Theme.ZIndex.Content + 2)
		local queueCapacityButton = button("Capacity", queue, "CAPACITY", Theme.ZIndex.Content + 2)
		local queueStartButton = button("StartQueue", queue, "LOCK & START", Theme.ZIndex.Content + 2)
		local reconnectButton = button("ReconnectMatch", queue, "RECONNECT TO ACTIVE MATCH", Theme.ZIndex.Content + 2)

		local inventory = screens.Inventory
		local inventoryTitle = label("Heading", inventory, "INVENTORY & LOADOUT", Theme.ZIndex.Content + 2)
		inventoryTitle.Font = Enum.Font.GothamBold
		local inventorySearch = Instance.new("TextBox")
		inventorySearch.Name = "Search"
		inventorySearch.BackgroundColor3 = Theme.Colors.SurfaceRaised
		inventorySearch.BorderSizePixel = 0
		inventorySearch.ClearTextOnFocus = false
		inventorySearch.PlaceholderText = "Search owned towers"
		inventorySearch.PlaceholderColor3 = Theme.Colors.TextMuted
		inventorySearch.Text = ""
		inventorySearch.TextColor3 = Theme.Colors.Text
		inventorySearch.Font = Enum.Font.Gotham
		inventorySearch.TextXAlignment = Enum.TextXAlignment.Left
		inventorySearch.ZIndex = Theme.ZIndex.Content + 2
		inventorySearch.SelectionOrder = 21
		inventorySearch.Parent = inventory
		addCorner(inventorySearch, Theme.Radii.Small)
		addStroke(inventorySearch, Theme.Colors.SurfaceMuted, Theme.Stroke.Normal)
		local inventorySort = button("Sort", inventory, "SORT: NAME", Theme.ZIndex.Content + 2)
		inventorySort.SelectionOrder = 22
		local inventoryFilter = button("Filter", inventory, "FILTER: ALL", Theme.ZIndex.Content + 2)
		inventoryFilter.SelectionOrder = 23
		local inventoryGrid = Instance.new("ScrollingFrame")
		inventoryGrid.Name = "OwnedTowerGrid"
		inventoryGrid.BackgroundColor3 = Theme.Colors.Backdrop
		inventoryGrid.BackgroundTransparency = 0.3
		inventoryGrid.BorderSizePixel = 0
		inventoryGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
		inventoryGrid.CanvasSize = UDim2.fromOffset(0, 0)
		inventoryGrid.ScrollBarThickness = 8
		inventoryGrid.ScrollingDirection = Enum.ScrollingDirection.Y
		inventoryGrid.ZIndex = Theme.ZIndex.Content + 2
		inventoryGrid.Parent = inventory
		addCorner(inventoryGrid, Theme.Radii.Small)
		local inventoryGridLayout = Instance.new("UIGridLayout")
		inventoryGridLayout.Name = "GridLayout"
		inventoryGridLayout.FillDirectionMaxCells = 3
		inventoryGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		inventoryGridLayout.Parent = inventoryGrid
		local detailPanel = Instance.new("ScrollingFrame")
		detailPanel.Name = "TowerDetails"
		detailPanel.BackgroundColor3 = Theme.Colors.Surface
		detailPanel.BorderSizePixel = 0
		detailPanel.AutomaticCanvasSize = Enum.AutomaticSize.None
		detailPanel.CanvasSize = UDim2.fromOffset(0, 0)
		detailPanel.ScrollingDirection = Enum.ScrollingDirection.Y
		detailPanel.ScrollBarThickness = 8
		detailPanel.ZIndex = Theme.ZIndex.Content + 2
		detailPanel.Parent = inventory
		addCorner(detailPanel, Theme.Radii.Medium)
		local detailBackButton = button("CloseDetails", detailPanel, "‹ TOWER LIST", Theme.ZIndex.Content + 3)
		detailBackButton.SelectionOrder = 230
		local detailTitle = label("TowerName", detailPanel, "SELECT A TOWER", Theme.ZIndex.Content + 3)
		detailTitle.Font = Enum.Font.GothamBold
		local detailOwnership = label("Ownership", detailPanel, "", Theme.ZIndex.Content + 3)
		local detailDescription = label("Description", detailPanel, "", Theme.ZIndex.Content + 3)
		local detailStats = label("CombatStats", detailPanel, "", Theme.ZIndex.Content + 3)
		local detailUpgrade = label("UpgradePreview", detailPanel, "", Theme.ZIndex.Content + 3)
		local equipButton = button("Equip", detailPanel, "EQUIP", Theme.ZIndex.Content + 3)
		local favoriteButton = button("Favorite", detailPanel, "☆ FAVORITE", Theme.ZIndex.Content + 3)
		local lockButton = button("Lock", detailPanel, "◇ LOCK", Theme.ZIndex.Content + 3)

		local chests = screens.Chests
		local chestScroll = Instance.new("ScrollingFrame")
		chestScroll.Name = "ChestScroll"
		chestScroll.BackgroundTransparency = 1
		chestScroll.BorderSizePixel = 0
		chestScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
		chestScroll.CanvasSize = UDim2.fromOffset(0, 0)
		chestScroll.ScrollingDirection = Enum.ScrollingDirection.Y
		chestScroll.ScrollBarThickness = 8
		chestScroll.ZIndex = Theme.ZIndex.Content + 2
		chestScroll.Parent = chests
		local chestTitle = label("Heading", chestScroll, "CHESTS", Theme.ZIndex.Content + 2)
		chestTitle.Font = Enum.Font.GothamBold
		local chestPolicy = label("Policy", chestScroll, "", Theme.ZIndex.Content + 2)
		local chestPity = label("Pity", chestScroll, "", Theme.ZIndex.Content + 2)
		local chestOdds = label("Odds", chestScroll, "", Theme.ZIndex.Content + 2)
		chestOdds.TextYAlignment = Enum.TextYAlignment.Top
		local onePullButton = button("OnePull", chestScroll, "OPEN 1", Theme.ZIndex.Content + 2)
		local tenPullButton = button("TenPull", chestScroll, "OPEN 10", Theme.ZIndex.Content + 2)
		local skipButton = button("SkipPresentation", chestScroll, "SKIP PRESENTATION", Theme.ZIndex.Content + 2)

		local settings = screens.Settings
		local settingsHeading = label("Heading", settings, "SETTINGS", Theme.ZIndex.Content + 2)
		settingsHeading.Font = Enum.Font.GothamBold
		local settingsList = Instance.new("ScrollingFrame")
		settingsList.Name = "SettingsList"
		settingsList.BackgroundTransparency = 1
		settingsList.BorderSizePixel = 0
		settingsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
		settingsList.CanvasSize = UDim2.fromOffset(0, 0)
		settingsList.ScrollBarThickness = 8
		settingsList.ZIndex = Theme.ZIndex.Content + 2
		settingsList.Parent = settings
		local settingsLayout = Instance.new("UIListLayout")
		settingsLayout.Padding = UDim.new(0, Theme.Spacing.Small)
		settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		settingsLayout.Parent = settingsList
		local settingsButtons = {} :: { [string]: TextButton }
		for index, key in SETTING_ORDER do
			local settingButton = button(key, settingsList, SETTING_LABELS[key], Theme.ZIndex.Content + 3)
			settingButton.LayoutOrder = index
			settingButton.SelectionOrder = 40 + index
			settingsButtons[key] = settingButton
		end

		local toastContainer = makeFrame("Notifications", root, Theme.ZIndex.Toast)
		toastContainer.BackgroundTransparency = 1

		local modalScrim = makeFrame("ModalScrim", root, Theme.ZIndex.ModalScrim)
		modalScrim.BackgroundColor3 = Theme.Colors.Scrim
		modalScrim.BackgroundTransparency = 0.3
		modalScrim.Active = true
		modalScrim.Visible = false
		local modalPanel = makeFrame("ModalPanel", modalScrim, Theme.ZIndex.Modal)
		addCorner(modalPanel, Theme.Radii.Large)
		addStroke(modalPanel, Theme.Colors.Focus, Theme.Stroke.Focus)
		local modalDepth = label("Depth", modalPanel, "", Theme.ZIndex.Modal + 1)
		local modalTitle = label("Title", modalPanel, "", Theme.ZIndex.Modal + 1)
		modalTitle.Font = Enum.Font.GothamBold
		local modalMessage = label("Message", modalPanel, "", Theme.ZIndex.Modal + 1)
		local modalConfirm = button("Confirm", modalPanel, "CONFIRM", Theme.ZIndex.Modal + 1)
		modalConfirm.SelectionOrder = 101
		local modalCancel = button("Cancel", modalPanel, "CANCEL", Theme.ZIndex.Modal + 1)
		modalCancel.SelectionOrder = 102

		local blocking = makeFrame("ProfileBlocking", root, Theme.ZIndex.Blocking)
		blocking.Active = true
		blocking.BackgroundColor3 = Theme.Colors.Backdrop
		local blockingTitle = label("Title", blocking, "LOADING PROFILE", Theme.ZIndex.Blocking + 1)
		blockingTitle.Font = Enum.Font.GothamBold
		blockingTitle.TextXAlignment = Enum.TextXAlignment.Center
		local blockingMessage = label(
			"Message",
			blocking,
			"Loading your saved data safely. Inventory and Gold stay hidden until the server is ready.",
			Theme.ZIndex.Blocking + 1
		)
		blockingMessage.TextXAlignment = Enum.TextXAlignment.Center
		local retryButton = button("Retry", blocking, "RETRY", Theme.ZIndex.Blocking + 1)
		retryButton.SelectionOrder = 201
		local leaveButton = button("Leave", blocking, "LEAVE SAFELY", Theme.ZIndex.Blocking + 1)
		leaveButton.SelectionOrder = 202

		result = {
			gui = nextGui,
			root = root,
			uiScale = uiScale,
			header = header,
			title = title,
			readiness = readiness,
			gold = gold,
			backButton = backButton,
			navigation = navigation,
			navigationButtons = navigationButtons,
			content = content,
			screens = screens,
			homeStatus = homeStatus,
			homeProgression = homeProgression,
			playButton = playButton,
			partyScroll = party,
			partyHeading = partyHeading,
			partyStatus = partyStatus,
			partyInviteInput = partyInviteInput,
			partyCreateButton = partyCreateButton,
			partyInviteButton = partyInviteButton,
			partyPlatformInviteButton = partyPlatformInviteButton,
			partyPrivacyButton = partyPrivacyButton,
			partyLeaveButton = partyLeaveButton,
			partyDisbandButton = partyDisbandButton,
			partyList = partyList,
			queueScroll = queue,
			queueHeading = queueHeading,
			queueStatus = queueStatus,
			queueList = queueList,
			queueRoster = queueRoster,
			queueConfiguration = queueConfiguration,
			queueJoinButton = queueJoinButton,
			queueLeaveButton = queueLeaveButton,
			queueMapButton = queueMapButton,
			queueDifficultyButton = queueDifficultyButton,
			queuePrivacyButton = queuePrivacyButton,
			queueCapacityButton = queueCapacityButton,
			queueStartButton = queueStartButton,
			reconnectButton = reconnectButton,
			inventorySearch = inventorySearch,
			inventorySort = inventorySort,
			inventoryFilter = inventoryFilter,
			inventoryGrid = inventoryGrid,
			inventoryGridLayout = inventoryGridLayout,
			detailPanel = detailPanel,
			detailBackButton = detailBackButton,
			detailTitle = detailTitle,
			detailOwnership = detailOwnership,
			detailDescription = detailDescription,
			detailStats = detailStats,
			detailUpgrade = detailUpgrade,
			equipButton = equipButton,
			favoriteButton = favoriteButton,
			lockButton = lockButton,
			chestScroll = chestScroll,
			chestTitle = chestTitle,
			chestPolicy = chestPolicy,
			chestPity = chestPity,
			chestOdds = chestOdds,
			onePullButton = onePullButton,
			tenPullButton = tenPullButton,
			skipButton = skipButton,
			settingsList = settingsList,
			settingsButtons = settingsButtons,
			blocking = blocking,
			blockingTitle = blockingTitle,
			blockingMessage = blockingMessage,
			retryButton = retryButton,
			leaveButton = leaveButton,
			modalScrim = modalScrim,
			modalPanel = modalPanel,
			modalDepth = modalDepth,
			modalTitle = modalTitle,
			modalMessage = modalMessage,
			modalConfirm = modalConfirm,
			modalCancel = modalCancel,
			toastContainer = toastContainer,
			allLabels = labels,
			allButtons = buttons,
		}
	end)
	if not succeeded then
		if gui ~= nil then
			pcall(function()
				(gui :: ScreenGui):Destroy()
			end)
		end
		return nil
	end
	return result
end

local function applyLayout(instances: Instances, layout: ResponsiveLayout.Layout)
	local margin = layout.safeMargin
	local wideCompact = layout.mode == "Compact" and layout.logicalWidth >= 600
	instances.header.Position = UDim2.fromOffset(margin, margin)
	instances.header.Size = UDim2.new(1, -margin * 2, 0, layout.headerHeight)
	instances.title.Position = UDim2.fromOffset(18, 0)
	instances.title.Size = UDim2.new(0.4, -18, 1, 0)
	instances.readiness.Position = UDim2.fromScale(0.4, 0)
	instances.readiness.Size = UDim2.fromScale(0.3, 1)
	instances.gold.Position = UDim2.fromScale(0.7, 0)
	instances.gold.Size = UDim2.new(0.3, -18, 1, 0)
	instances.backButton.Position = UDim2.fromOffset(12, 10)
	instances.backButton.Size = UDim2.fromOffset(math.max(96, layout.touchTarget * 2), layout.touchTarget)

	local contentTop = margin + layout.headerHeight + layout.panelPadding
	local contentFrameHeight: number
	if layout.mode == "Compact" then
		local navigationColumns = if wideCompact then #NAVIGATION_ORDER else 3
		local navigationRows = math.ceil(#NAVIGATION_ORDER / navigationColumns)
		local compactNavigationHeight =
			math.max(layout.bottomNavigationHeight, navigationRows * layout.touchTarget + (navigationRows + 1) * 8)
		instances.navigation.Position = UDim2.new(0, margin, 1, -(margin + compactNavigationHeight))
		instances.navigation.Size = UDim2.new(1, -margin * 2, 0, compactNavigationHeight)
		for index, screen in NAVIGATION_ORDER do
			local button = instances.navigationButtons[screen]
			local column = (index - 1) % navigationColumns
			local row = math.floor((index - 1) / navigationColumns)
			button.Position = UDim2.new(column / navigationColumns, 4, 0, 8 + row * (layout.touchTarget + 8))
			button.Size = UDim2.new(1 / navigationColumns, -8, 0, layout.touchTarget)
		end
		instances.content.Position = UDim2.fromOffset(margin, contentTop)
		instances.content.Size =
			UDim2.new(1, -margin * 2, 1, -(contentTop + margin + compactNavigationHeight + layout.panelPadding))
		contentFrameHeight = layout.logicalHeight
			- (contentTop + margin + compactNavigationHeight + layout.panelPadding)
	else
		instances.navigation.Position = UDim2.fromOffset(margin, contentTop)
		instances.navigation.Size = UDim2.new(0, layout.navigationWidth, 1, -(contentTop + margin))
		for index, screen in NAVIGATION_ORDER do
			local button = instances.navigationButtons[screen]
			button.Position = UDim2.fromOffset(10, 12 + (index - 1) * (layout.touchTarget + 10))
			button.Size = UDim2.new(1, -20, 0, layout.touchTarget)
		end
		instances.content.Position = UDim2.fromOffset(margin + layout.navigationWidth + layout.panelPadding, contentTop)
		instances.content.Size =
			UDim2.new(1, -(margin * 2 + layout.navigationWidth + layout.panelPadding), 1, -(contentTop + margin))
		contentFrameHeight = layout.logicalHeight - (contentTop + margin)
	end

	for _, screen in NAVIGATION_ORDER do
		instances.screens[screen].Position = UDim2.fromOffset(layout.panelPadding, layout.panelPadding)
		instances.screens[screen].Size = UDim2.new(1, -layout.panelPadding * 2, 1, -layout.panelPadding * 2)
	end
	for _, label in instances.allLabels do
		label.TextSize = layout.baseTextSize
	end
	for _, button in instances.allButtons do
		button.TextSize = math.max(14, layout.baseTextSize - 1)
	end
	instances.title.TextSize = layout.titleTextSize

	instances.homeStatus.Position = UDim2.fromOffset(0, 66)
	instances.homeStatus.Size = UDim2.new(1, 0, 0, 82)
	instances.homeProgression.Position = UDim2.fromOffset(0, 152)
	instances.homeProgression.Size = UDim2.new(1, 0, 0, 58)
	instances.playButton.AnchorPoint = Vector2.new(0.5, 1)
	instances.playButton.Position = UDim2.new(0.5, 0, 1, -12)
	instances.playButton.Size = UDim2.fromOffset(math.min(420, layout.contentWidth - 40), layout.touchTarget + 18)

	local squadViewportHeight = math.max(1, contentFrameHeight - layout.panelPadding * 2)
	instances.partyScroll.Position = UDim2.fromScale(0, 0)
	instances.partyScroll.Size = UDim2.fromScale(1, 1)
	instances.partyHeading.Position = UDim2.fromOffset(0, 0)
	instances.partyHeading.Size = UDim2.new(1, -10, 0, 26)
	instances.partyStatus.Position = UDim2.fromOffset(0, 28)
	instances.partyStatus.Size = UDim2.new(1, -10, 0, 26)
	instances.partyInviteInput.TextSize = layout.baseTextSize
	local partyListTop: number
	if layout.mode == "Compact" then
		instances.partyInviteInput.Position = UDim2.fromOffset(0, 58)
		instances.partyInviteInput.Size = UDim2.new(0.55, -5, 0, layout.touchTarget)
		instances.partyInviteButton.Position = UDim2.new(0.55, 5, 0, 58)
		instances.partyInviteButton.Size = UDim2.new(0.45, -5, 0, layout.touchTarget)
		instances.partyCreateButton.Position = UDim2.fromOffset(0, 58)
		instances.partyCreateButton.Size = UDim2.new(1, -10, 0, layout.touchTarget)
		local actionColumns = if wideCompact then 4 else 2
		for index, button in
			{
				instances.partyPlatformInviteButton,
				instances.partyPrivacyButton,
				instances.partyLeaveButton,
				instances.partyDisbandButton,
			}
		do
			local column = (index - 1) % actionColumns
			local row = math.floor((index - 1) / actionColumns)
			button.Position =
				UDim2.new(column / actionColumns, if column == 0 then 0 else 5, 0, 110 + row * (layout.touchTarget + 6))
			button.Size = UDim2.new(1 / actionColumns, -5, 0, layout.touchTarget)
		end
		local actionRows = math.ceil(4 / actionColumns)
		partyListTop = 110 + actionRows * (layout.touchTarget + 6)
	else
		instances.partyInviteInput.Position = UDim2.fromOffset(0, 58)
		instances.partyInviteInput.Size = UDim2.new(0.35, -5, 0, layout.touchTarget)
		instances.partyInviteButton.Position = UDim2.new(0.35, 5, 0, 58)
		instances.partyInviteButton.Size = UDim2.new(0.2, -5, 0, layout.touchTarget)
		local partyButtons = {
			instances.partyCreateButton,
			instances.partyPlatformInviteButton,
			instances.partyPrivacyButton,
			instances.partyLeaveButton,
			instances.partyDisbandButton,
		}
		for index, button in partyButtons do
			button.Position = UDim2.new(0.55 + (index - 1) * 0.09, 5, 0, 58)
			button.Size = UDim2.new(0.09, -5, 0, layout.touchTarget)
		end
		partyListTop = 58 + layout.touchTarget + 10
	end
	local partyListHeight = math.max(160, squadViewportHeight - partyListTop)
	instances.partyList.Position = UDim2.fromOffset(0, partyListTop)
	instances.partyList.Size = UDim2.new(1, -10, 0, partyListHeight)
	instances.partyScroll.CanvasSize = UDim2.fromOffset(0, partyListTop + partyListHeight)

	instances.queueScroll.Position = UDim2.fromScale(0, 0)
	instances.queueScroll.Size = UDim2.fromScale(1, 1)
	instances.queueHeading.Position = UDim2.fromOffset(0, 0)
	instances.queueHeading.Size = UDim2.new(1, -10, 0, 26)
	instances.queueStatus.Position = UDim2.fromOffset(0, 28)
	instances.queueStatus.Size = UDim2.new(1, -10, 0, 26)
	local queueListWidth = if layout.mode == "Compact" then 0.34 else 0.26
	instances.queueList.Position = UDim2.fromOffset(0, 58)
	instances.queueRoster.Position = UDim2.new(queueListWidth, 6, 0, 58)
	local queueControlTop = 232
	if layout.mode == "Compact" then
		instances.queueRoster.Size = UDim2.new(1 - queueListWidth, -6, 0, 64)
		instances.queueConfiguration.Position = UDim2.new(queueListWidth, 6, 0, 126)
		instances.queueConfiguration.Size = UDim2.new(1 - queueListWidth, -6, 0, 64)
		queueControlTop = 196
	else
		instances.queueRoster.Size = UDim2.new(1 - queueListWidth, -6, 0, 92)
		instances.queueConfiguration.Position = UDim2.new(queueListWidth, 6, 0, 154)
		instances.queueConfiguration.Size = UDim2.new(1 - queueListWidth, -6, 0, 72)
	end
	local queueControls = {
		instances.queueJoinButton,
		instances.queueLeaveButton,
		instances.queueMapButton,
		instances.queueDifficultyButton,
		instances.queuePrivacyButton,
		instances.queueCapacityButton,
		instances.queueStartButton,
		instances.reconnectButton,
	}
	local queueColumns = if layout.mode == "Compact" and not wideCompact then 2 else 4
	for index, button in queueControls do
		local column = (index - 1) % queueColumns
		local row = math.floor((index - 1) / queueColumns)
		button.Position = UDim2.new(
			queueListWidth + column * ((1 - queueListWidth) / queueColumns),
			6,
			0,
			queueControlTop + row * (layout.touchTarget + 8)
		)
		button.Size = UDim2.new((1 - queueListWidth) / queueColumns, -8, 0, layout.touchTarget)
	end
	local queueRows = math.ceil(#queueControls / queueColumns)
	local queueCanvasHeight = math.max(squadViewportHeight, queueControlTop + queueRows * (layout.touchTarget + 8))
	instances.queueList.Size = UDim2.new(queueListWidth, -6, 0, queueCanvasHeight - 58)
	instances.queueScroll.CanvasSize = UDim2.fromOffset(0, queueCanvasHeight)

	instances.inventorySearch.TextSize = layout.baseTextSize
	local inventoryTop: number
	if layout.mode == "Compact" then
		instances.inventorySearch.Position = UDim2.fromOffset(0, 0)
		instances.inventorySearch.Size = UDim2.new(0.45, -6, 0, layout.touchTarget)
		instances.inventorySort.Position = UDim2.fromScale(0.45, 0)
		instances.inventorySort.Size = UDim2.new(0.27, -4, 0, layout.touchTarget)
		instances.inventoryFilter.Position = UDim2.new(0.72, 2, 0, 0)
		instances.inventoryFilter.Size = UDim2.new(0.28, -2, 0, layout.touchTarget)
		inventoryTop = layout.touchTarget + 8
		instances.inventoryGrid.Position = UDim2.fromOffset(0, inventoryTop)
		instances.inventoryGrid.Size = UDim2.new(1, 0, 1, -inventoryTop)
		instances.detailPanel.Position = UDim2.fromScale(0, 0)
		instances.detailPanel.Size = UDim2.fromScale(1, 1)
		instances.detailPanel.CanvasSize = UDim2.fromOffset(0, 416)
		instances.detailBackButton.Position = UDim2.fromOffset(10, 8)
		instances.detailBackButton.Size = UDim2.fromOffset(132, layout.touchTarget)
		instances.detailTitle.Position = UDim2.fromOffset(152, 8)
		instances.detailTitle.Size = UDim2.new(1, -170, 0, layout.touchTarget)
		instances.detailOwnership.Position = UDim2.fromOffset(14, 62)
		instances.detailOwnership.Size = UDim2.new(1, -28, 0, 52)
		instances.detailDescription.Position = UDim2.fromOffset(14, 118)
		instances.detailDescription.Size = UDim2.new(1, -28, 0, 72)
		instances.detailStats.Position = UDim2.fromOffset(14, 194)
		instances.detailStats.Size = UDim2.new(1, -28, 0, 90)
		instances.detailUpgrade.Position = UDim2.fromOffset(14, 288)
		instances.detailUpgrade.Size = UDim2.new(1, -28, 0, 62)
		local detailButtonWidth = 1 / 3
		for index, button in { instances.equipButton, instances.favoriteButton, instances.lockButton } do
			button.Position = UDim2.new((index - 1) * detailButtonWidth, 5, 0, 358)
			button.Size = UDim2.new(detailButtonWidth, -10, 0, layout.touchTarget)
		end
	else
		instances.inventorySearch.Position = UDim2.fromOffset(0, 54)
		instances.inventorySearch.Size = UDim2.new(0.5, -8, 0, layout.touchTarget)
		instances.inventorySort.Position = UDim2.new(0.5, 0, 0, 54)
		instances.inventorySort.Size = UDim2.new(0.25, -5, 0, layout.touchTarget)
		instances.inventoryFilter.Position = UDim2.new(0.75, 5, 0, 54)
		instances.inventoryFilter.Size = UDim2.new(0.25, -5, 0, layout.touchTarget)
		inventoryTop = 54 + layout.touchTarget + 10
		instances.inventoryGrid.Position = UDim2.fromOffset(0, inventoryTop)
		instances.inventoryGrid.Size = UDim2.new(0.58, -8, 1, -inventoryTop)
		instances.detailPanel.Position = UDim2.new(0.58, 8, 0, inventoryTop)
		instances.detailPanel.Size = UDim2.new(0.42, -8, 1, -inventoryTop)
		instances.detailPanel.CanvasSize = UDim2.fromOffset(0, 0)
		instances.detailBackButton.Visible = false
		instances.detailTitle.Position = UDim2.fromOffset(14, 10)
		instances.detailTitle.Size = UDim2.new(1, -28, 0, 38)
		instances.detailOwnership.Position = UDim2.fromOffset(14, 48)
		instances.detailOwnership.Size = UDim2.new(1, -28, 0, 34)
		instances.detailDescription.Position = UDim2.fromOffset(14, 82)
		instances.detailDescription.Size = UDim2.new(1, -28, 0, 74)
		instances.detailStats.Position = UDim2.fromOffset(14, 158)
		instances.detailStats.Size = UDim2.new(1, -28, 0, 90)
		instances.detailUpgrade.Position = UDim2.fromOffset(14, 250)
		instances.detailUpgrade.Size = UDim2.new(1, -28, 0, 66)
		local detailButtonWidth = 1 / 3
		for index, button in { instances.equipButton, instances.favoriteButton, instances.lockButton } do
			button.Position = UDim2.new((index - 1) * detailButtonWidth, 5, 1, -(layout.touchTarget + 10))
			button.Size = UDim2.new(detailButtonWidth, -10, 0, layout.touchTarget)
		end
	end
	instances.inventoryGridLayout.CellPadding = UDim2.fromOffset(10, 10)
	instances.inventoryGridLayout.CellSize = UDim2.fromOffset(
		math.max(132, if layout.mode == "Compact" then (layout.contentWidth - 42) / 2 else layout.cardWidth),
		if layout.mode == "Compact" then layout.touchTarget + 4 else layout.touchTarget + 44
	)
	instances.chestScroll.Position = UDim2.fromScale(0, 0)
	instances.chestScroll.Size = UDim2.fromScale(1, 1)
	if layout.mode == "Compact" then
		instances.chestScroll.CanvasSize = UDim2.fromOffset(0, 360)
		instances.chestTitle.Position = UDim2.fromOffset(0, 0)
		instances.chestTitle.Size = UDim2.new(1, 0, 0, 40)
		instances.onePullButton.Position = UDim2.fromOffset(0, 44)
		instances.onePullButton.Size = UDim2.new(0.5, -5, 0, layout.touchTarget)
		instances.tenPullButton.Position = UDim2.new(0.5, 5, 0, 44)
		instances.tenPullButton.Size = UDim2.new(0.5, -5, 0, layout.touchTarget)
		instances.chestPolicy.Position = UDim2.fromOffset(0, 98)
		instances.chestPolicy.Size = UDim2.new(1, -10, 0, 58)
		instances.chestPity.Position = UDim2.fromOffset(0, 160)
		instances.chestPity.Size = UDim2.new(1, -10, 0, 38)
		instances.chestOdds.Position = UDim2.fromOffset(0, 202)
		instances.chestOdds.Size = UDim2.new(1, -10, 0, 96)
		instances.skipButton.Position = UDim2.fromOffset(0, 304)
		instances.skipButton.Size = UDim2.new(1, -10, 0, layout.touchTarget)
	else
		instances.chestScroll.CanvasSize = UDim2.fromOffset(0, 0)
		instances.chestTitle.Position = UDim2.fromOffset(0, 0)
		instances.chestTitle.Size = UDim2.new(1, 0, 0, 46)
		instances.chestPolicy.Position = UDim2.fromOffset(0, 58)
		instances.chestPolicy.Size = UDim2.new(1, 0, 0, 62)
		instances.chestPity.Position = UDim2.fromOffset(0, 122)
		instances.chestPity.Size = UDim2.new(1, 0, 0, 46)
		instances.chestOdds.Position = UDim2.fromOffset(0, 174)
		instances.chestOdds.Size = UDim2.new(1, 0, 1, -(174 + layout.touchTarget + 22))
		instances.onePullButton.Position = UDim2.new(0, 0, 1, -(layout.touchTarget + 8))
		instances.onePullButton.Size = UDim2.new(0.34, -6, 0, layout.touchTarget)
		instances.tenPullButton.Position = UDim2.new(0.34, 3, 1, -(layout.touchTarget + 8))
		instances.tenPullButton.Size = UDim2.new(0.42, -6, 0, layout.touchTarget)
		instances.skipButton.Position = UDim2.new(0.76, 3, 1, -(layout.touchTarget + 8))
		instances.skipButton.Size = UDim2.new(0.24, -3, 0, layout.touchTarget)
	end

	instances.settingsList.Position = UDim2.fromOffset(0, 58)
	instances.settingsList.Size = UDim2.new(1, 0, 1, -58)
	for _, key in SETTING_ORDER do
		instances.settingsButtons[key].Size = UDim2.new(1, -10, 0, layout.touchTarget + 4)
	end

	instances.toastContainer.AnchorPoint = Vector2.new(1, 0)
	instances.toastContainer.Position = UDim2.new(1, -margin, 0, margin + layout.headerHeight + 8)
	instances.toastContainer.Size = UDim2.fromOffset(layout.toastWidth, math.min(420, layout.logicalHeight * 0.6))
	instances.modalScrim.Size = UDim2.fromScale(1, 1)
	instances.modalPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	instances.modalPanel.Position = UDim2.fromScale(0.5, 0.5)
	instances.modalPanel.Size = UDim2.fromOffset(layout.modalWidth, math.min(340, layout.logicalHeight - margin * 2))
	instances.modalDepth.Position = UDim2.fromOffset(18, 10)
	instances.modalDepth.Size = UDim2.new(1, -36, 0, 24)
	instances.modalTitle.Position = UDim2.fromOffset(18, 38)
	instances.modalTitle.Size = UDim2.new(1, -36, 0, 48)
	instances.modalTitle.TextSize = layout.titleTextSize
	instances.modalMessage.Position = UDim2.fromOffset(18, 90)
	instances.modalMessage.Size = UDim2.new(1, -36, 1, -(90 + layout.touchTarget + 30))
	instances.modalConfirm.Position = UDim2.new(0, 18, 1, -(layout.touchTarget + 16))
	instances.modalConfirm.Size = UDim2.new(0.5, -24, 0, layout.touchTarget)
	instances.modalCancel.Position = UDim2.new(0.5, 6, 1, -(layout.touchTarget + 16))
	instances.modalCancel.Size = UDim2.new(0.5, -24, 0, layout.touchTarget)
	instances.blocking.Size = UDim2.fromScale(1, 1)
	instances.blockingTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	instances.blockingTitle.Position = UDim2.fromScale(0.5, 0.38)
	instances.blockingTitle.Size = UDim2.new(1, -margin * 4, 0, 60)
	instances.blockingTitle.TextSize = layout.titleTextSize
	instances.blockingMessage.AnchorPoint = Vector2.new(0.5, 0.5)
	instances.blockingMessage.Position = UDim2.fromScale(0.5, 0.49)
	instances.blockingMessage.Size = UDim2.new(1, -margin * 4, 0, 90)
	instances.retryButton.Position = UDim2.new(0.5, -210, 0.62, 0)
	instances.retryButton.Size = UDim2.fromOffset(200, layout.touchTarget)
	instances.leaveButton.Position = UDim2.new(0.5, 10, 0.62, 0)
	instances.leaveButton.Size = UDim2.fromOffset(200, layout.touchTarget)
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

local function emit(data: ViewData, fields: { [string]: any })
	if data.cleaned then
		return
	end
	local snapshot = data.current
	local action = table.freeze({
		kind = fields.kind :: ActionKind,
		source = if snapshot == nil then "Desktop" else snapshot.inputFamily,
		profileRevision = if snapshot == nil then nil else snapshot.profileRevision,
		screen = fields.screen,
		unitId = fields.unitId,
		towerId = fields.towerId,
		quantity = fields.quantity,
		enabled = fields.enabled,
		settingKey = fields.settingKey,
		settingValue = fields.settingValue,
		modalId = fields.modalId,
		toastId = fields.toastId,
		inputFamily = fields.inputFamily,
		textValue = fields.textValue,
		targetUserId = fields.targetUserId,
		invitationId = fields.invitationId,
		queueId = fields.queueId,
		configuration = fields.configuration,
	}) :: Action
	if pcall(data.callback, action) then
		data.actionCount += 1
	end
end

local function connectButton(data: ViewData, button: TextButton, callback: () -> ()): boolean
	local connected, connection = pcall(data.dependencies.connectActivated, button, function()
		if not data.cleaned and button.Active then
			callback()
		end
	end)
	if not connected or typeof(connection) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, connection :: RBXScriptConnection)
	return true
end

local function selectedTower(data: ViewData): LobbyUiModel.TowerCard?
	local snapshot = data.current
	if snapshot == nil or snapshot.profileState ~= "Ready" then
		return nil
	end
	local selectedId = snapshot.selectedUnitId or data.localSelectedUnitId
	if selectedId == nil then
		return nil
	end
	for _, tower in snapshot.inventory do
		if tower.unitId == selectedId then
			return tower
		end
	end
	return nil
end

local function closeCompactDetails(data: ViewData): boolean
	if not data.compactMode or selectedTower(data) == nil then
		return false
	end
	data.localSelectedUnitId = nil
	emit(data, { kind = "CloseTowerDetails" })
	return true
end

local function nextSettingValue(settings: LobbyUiModel.Settings, key: string): boolean | number
	local value = (settings :: any)[key]
	if type(value) == "boolean" then
		return not value
	end
	local step = if key == "uiScale" then 0.125 else 0.25
	local minimum = if key == "uiScale" then 0.75 else 0
	local maximum = if key == "uiScale" then 1.25 else 1
	local nextValue = math.floor(((value :: number) + step) * 1_000 + 0.5) / 1_000
	return if nextValue > maximum then minimum else nextValue
end

local function cycleSort(value: "Name" | "Copies" | "Equipped"): "Name" | "Copies" | "Equipped"
	if value == "Name" then
		return "Copies"
	elseif value == "Copies" then
		return "Equipped"
	end
	return "Name"
end

local function cycleFilter(
	value: "All" | "Equipped" | "Favorites" | "Locked"
): "All" | "Equipped" | "Favorites" | "Locked"
	if value == "All" then
		return "Equipped"
	elseif value == "Equipped" then
		return "Favorites"
	elseif value == "Favorites" then
		return "Locked"
	end
	return "All"
end

local function selectedQueue(snapshot: LobbyUiModel.RenderState?): any
	if snapshot == nil or snapshot.queueSnapshots == nil or snapshot.selectedQueueId == nil then
		return nil
	end
	for _, queue in snapshot.queueSnapshots do
		if queue.queueId == snapshot.selectedQueueId then
			return queue
		end
	end
	return nil
end

local function nextConfiguredId(
	snapshot: LobbyUiModel.RenderState,
	current: string,
	field: "mapId" | "difficultyId"
): string
	local values = {} :: { string }
	local seen: { [string]: boolean } = {}
	for _, queue in snapshot.queueSnapshots or {} do
		local value = queue.configuration[field]
		if not seen[value] then
			seen[value] = true
			table.insert(values, value)
		end
	end
	table.sort(values)
	for index, value in values do
		if value == current then
			return values[index % #values + 1]
		end
	end
	return values[1] or current
end

local function emitQueueConfiguration(data: ViewData, field: string)
	local snapshot = data.current
	local queue = selectedQueue(snapshot)
	if snapshot == nil or queue == nil then
		return
	end
	local configuration = {
		mapId = queue.configuration.mapId,
		difficultyId = queue.configuration.difficultyId,
		privacy = queue.configuration.privacy,
		maxPlayers = queue.configuration.maxPlayers,
	}
	if field == "mapId" then
		configuration.mapId = nextConfiguredId(snapshot, configuration.mapId, "mapId")
	elseif field == "difficultyId" then
		configuration.difficultyId = nextConfiguredId(snapshot, configuration.difficultyId, "difficultyId")
	elseif field == "privacy" then
		configuration.privacy = if configuration.privacy == "Public" then "PartyOnly" else "Public"
	else
		configuration.maxPlayers = math.max(#queue.members, configuration.maxPlayers % 4 + 1)
	end
	emit(data, { kind = "ConfigureQueue", queueId = queue.queueId, configuration = configuration })
end

local function connectStatic(data: ViewData): boolean
	for _, screen in NAVIGATION_ORDER do
		local selectedScreen = screen
		if
			not connectButton(data, data.instances.navigationButtons[screen], function()
				emit(data, { kind = "Navigate", screen = selectedScreen })
			end)
		then
			return false
		end
	end
	if
		not connectButton(data, data.instances.backButton, function()
			if not closeCompactDetails(data) then
				emit(data, { kind = "Back" })
			end
		end)
		or not connectButton(data, data.instances.detailBackButton, function()
			data.localSelectedUnitId = nil
			emit(data, { kind = "CloseTowerDetails" })
		end)
		or not connectButton(data, data.instances.playButton, function()
			emit(data, { kind = "Play" })
		end)
		or not connectButton(data, data.instances.partyCreateButton, function()
			emit(data, { kind = "CreateParty" })
		end)
		or not connectButton(data, data.instances.partyInviteButton, function()
			local targetUserId = tonumber(data.partyInviteText)
			if targetUserId ~= nil and targetUserId % 1 == 0 and targetUserId > 0 then
				emit(data, { kind = "InvitePartyMember", targetUserId = targetUserId })
			end
		end)
		or not connectButton(data, data.instances.partyPlatformInviteButton, function()
			emit(data, { kind = "PromptPartyInvite" })
		end)
		or not connectButton(data, data.instances.partyPrivacyButton, function()
			emit(data, { kind = "TogglePartyPrivacy" })
		end)
		or not connectButton(data, data.instances.partyLeaveButton, function()
			emit(data, { kind = "LeaveParty" })
		end)
		or not connectButton(data, data.instances.partyDisbandButton, function()
			emit(data, { kind = "DisbandParty" })
		end)
		or not connectButton(data, data.instances.queueJoinButton, function()
			local queue = selectedQueue(data.current)
			if queue ~= nil then
				emit(data, { kind = "JoinQueue", queueId = queue.queueId })
			end
		end)
		or not connectButton(data, data.instances.queueLeaveButton, function()
			local queue = selectedQueue(data.current)
			if queue ~= nil then
				emit(data, { kind = "LeaveQueue", queueId = queue.queueId })
			end
		end)
		or not connectButton(data, data.instances.queueMapButton, function()
			emitQueueConfiguration(data, "mapId")
		end)
		or not connectButton(data, data.instances.queueDifficultyButton, function()
			emitQueueConfiguration(data, "difficultyId")
		end)
		or not connectButton(data, data.instances.queuePrivacyButton, function()
			emitQueueConfiguration(data, "privacy")
		end)
		or not connectButton(data, data.instances.queueCapacityButton, function()
			emitQueueConfiguration(data, "maxPlayers")
		end)
		or not connectButton(data, data.instances.queueStartButton, function()
			local queue = selectedQueue(data.current)
			if queue ~= nil then
				emit(data, { kind = "StartQueue", queueId = queue.queueId })
			end
		end)
		or not connectButton(data, data.instances.reconnectButton, function()
			emit(data, { kind = "ReconnectActiveMatch" })
		end)
		or not connectButton(data, data.instances.retryButton, function()
			emit(data, { kind = "RetryProfile" })
		end)
		or not connectButton(data, data.instances.leaveButton, function()
			emit(data, { kind = "SafeLeave" })
		end)
		or not connectButton(data, data.instances.inventorySort, function()
			data.inventorySort = cycleSort(data.inventorySort)
			if data.current ~= nil then
				renderCanonical(data, data.current :: LobbyUiModel.RenderState)
			end
			emit(data, { kind = "InventorySortChanged", textValue = data.inventorySort })
		end)
		or not connectButton(data, data.instances.inventoryFilter, function()
			data.inventoryFilter = cycleFilter(data.inventoryFilter)
			if data.current ~= nil then
				renderCanonical(data, data.current :: LobbyUiModel.RenderState)
			end
			emit(data, { kind = "InventoryFilterChanged", textValue = data.inventoryFilter })
		end)
		or not connectButton(data, data.instances.onePullButton, function()
			emit(data, { kind = "PullChest", quantity = 1 })
		end)
		or not connectButton(data, data.instances.tenPullButton, function()
			emit(data, { kind = "PullChest", quantity = 10 })
		end)
		or not connectButton(data, data.instances.skipButton, function()
			emit(data, { kind = "SkipChestPresentation" })
		end)
	then
		return false
	end

	for _, key in SETTING_ORDER do
		local settingKey = key
		if
			not connectButton(data, data.instances.settingsButtons[key], function()
				local snapshot = data.current
				if snapshot == nil or snapshot.settings == nil then
					return
				end
				emit(data, {
					kind = "UpdateSetting",
					settingKey = settingKey,
					settingValue = nextSettingValue(snapshot.settings, settingKey),
				})
			end)
		then
			return false
		end
	end

	for _, binding in
		{
			{ data.instances.equipButton, "equip" },
			{ data.instances.favoriteButton, "favorite" },
			{ data.instances.lockButton, "lock" },
		}
	do
		local button = binding[1] :: TextButton
		local operation = binding[2]
		if
			not connectButton(data, button, function()
				local tower = selectedTower(data)
				if tower == nil then
					return
				end
				if operation == "equip" then
					emit(data, {
						kind = if tower.equippedSlot == nil then "EquipTower" else "UnequipTower",
						unitId = tower.unitId,
						towerId = tower.towerId,
					})
				elseif operation == "favorite" then
					emit(data, {
						kind = "ToggleFavorite",
						unitId = tower.unitId,
						towerId = tower.towerId,
						enabled = not tower.favorite,
					})
				else
					emit(data, {
						kind = "ToggleLock",
						unitId = tower.unitId,
						towerId = tower.towerId,
						enabled = not tower.locked,
					})
				end
			end)
		then
			return false
		end
	end

	if
		not connectButton(data, data.instances.modalConfirm, function()
			local snapshot = data.current
			local modal = if snapshot == nil then nil else snapshot.modals[#snapshot.modals]
			if modal ~= nil then
				emit(data, { kind = "ConfirmModal", modalId = modal.id })
			end
		end)
		or not connectButton(data, data.instances.modalCancel, function()
			local snapshot = data.current
			local modal = if snapshot == nil then nil else snapshot.modals[#snapshot.modals]
			if modal ~= nil then
				emit(data, { kind = "CancelModal", modalId = modal.id })
			end
		end)
	then
		return false
	end

	local inputConnected, inputConnection = pcall(data.dependencies.connectInputBegan, function(keyCode, processed)
		if not data.cleaned and not processed and (keyCode == "Escape" or keyCode == "ButtonB") then
			if not closeCompactDetails(data) then
				emit(data, { kind = "Back" })
			end
		end
	end)
	if not inputConnected or typeof(inputConnection) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, inputConnection :: RBXScriptConnection)

	local familyConnected, familyConnection = pcall(data.dependencies.connectInputFamilyChanged, function(family)
		if not data.cleaned then
			emit(data, { kind = "InputFamilyChanged", inputFamily = family })
		end
	end)
	if not familyConnected or typeof(familyConnection) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, familyConnection :: RBXScriptConnection)

	local searchConnected, searchConnection = pcall(
		data.dependencies.connectSearchCommitted,
		data.instances.inventorySearch,
		function(text)
			if data.cleaned or type(text) ~= "string" then
				return
			end
			local bounded = string.sub(text, 1, MAX_QUERY_BYTES)
			data.inventoryQuery = bounded
			data.instances.inventorySearch.Text = bounded
			if data.current ~= nil then
				renderCanonical(data, data.current :: LobbyUiModel.RenderState)
			end
			emit(data, { kind = "InventoryQueryChanged", textValue = bounded })
		end
	)
	if not searchConnected or typeof(searchConnection) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, searchConnection :: RBXScriptConnection)
	local inviteConnected, inviteConnection = pcall(
		data.dependencies.connectSearchCommitted,
		data.instances.partyInviteInput,
		function(text)
			if data.cleaned or type(text) ~= "string" then
				return
			end
			local bounded = string.sub(text, 1, 20)
			data.partyInviteText = bounded
			data.instances.partyInviteInput.Text = bounded
		end
	)
	if not inviteConnected or typeof(inviteConnection) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, inviteConnection :: RBXScriptConnection)
	return true
end

local function clearDynamic(data: ViewData): boolean
	local succeeded = disconnectAll(data.dynamicConnections)
	for _, container in
		{
			data.instances.inventoryGrid,
			data.instances.partyList,
			data.instances.queueList,
			data.instances.toastContainer,
		}
	do
		for _, child in container:GetChildren() do
			if child.Name ~= "GridLayout" and child.Name ~= "Layout" then
				local destroyed = pcall(function()
					child:Destroy()
				end)
				if not destroyed then
					succeeded = false
				end
			end
		end
	end
	data.inventoryCardCount = 0
	return succeeded
end

local function connectDynamic(data: ViewData, button: TextButton, callback: () -> ()): boolean
	local connected, connection = pcall(data.dependencies.connectActivated, button, function()
		if not data.cleaned and button.Active then
			callback()
		end
	end)
	if not connected or typeof(connection) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.dynamicConnections, connection :: RBXScriptConnection)
	return true
end

local function inventoryCards(data: ViewData, snapshot: LobbyUiModel.RenderState): { LobbyUiModel.TowerCard }
	local cards = {} :: { LobbyUiModel.TowerCard }
	local query = string.lower(data.inventoryQuery)
	for _, tower in snapshot.inventory do
		local matchesQuery = query == "" or string.find(string.lower(tower.displayName), query, 1, true) ~= nil
		local matchesFilter = data.inventoryFilter == "All"
			or (data.inventoryFilter == "Equipped" and tower.equippedSlot ~= nil)
			or (data.inventoryFilter == "Favorites" and tower.favorite)
			or (data.inventoryFilter == "Locked" and tower.locked)
		if matchesQuery and matchesFilter then
			table.insert(cards, tower)
		end
	end
	table.sort(cards, function(left, right)
		if data.inventorySort == "Copies" and left.copies ~= right.copies then
			return left.copies > right.copies
		elseif data.inventorySort == "Equipped" then
			local leftSlot = left.equippedSlot or 99
			local rightSlot = right.equippedSlot or 99
			if leftSlot ~= rightSlot then
				return leftSlot < rightSlot
			end
		end
		if left.displayName ~= right.displayName then
			return left.displayName < right.displayName
		end
		return left.unitId < right.unitId
	end)
	return cards
end

local function renderInventory(data: ViewData, snapshot: LobbyUiModel.RenderState)
	local instances = data.instances
	instances.inventorySort.Text = `SORT: {string.upper(data.inventorySort)}`
	instances.inventoryFilter.Text = `FILTER: {string.upper(data.inventoryFilter)}`
	instances.inventorySearch.Text = data.inventoryQuery
	local selectedId = snapshot.selectedUnitId or data.localSelectedUnitId
	local tower = selectedTower(data)
	local compactDetail = data.compactMode and tower ~= nil
	instances.inventorySearch.Visible = not compactDetail
	instances.inventorySort.Visible = not compactDetail
	instances.inventoryFilter.Visible = not compactDetail
	instances.inventoryGrid.Visible = not compactDetail
	instances.detailPanel.Visible = not data.compactMode or compactDetail
	instances.detailBackButton.Visible = compactDetail
	for index, cardTower in inventoryCards(data, snapshot) do
		local badges = `{if cardTower.favorite then "★ " else ""}{if cardTower.locked then "◆ " else ""}`
		local equipped = if cardTower.equippedSlot == nil then "NOT EQUIPPED" else `SLOT {cardTower.equippedSlot}`
		local card = makeButton(
			`TowerCard{index}`,
			instances.inventoryGrid,
			`{badges}{cardTower.displayName}\nCOPIES {cardTower.copies} • {equipped}`,
			Theme.ZIndex.Content + 3
		)
		card.LayoutOrder = index
		card.SelectionOrder = 200 + index
		card.BackgroundColor3 = if cardTower.unitId == selectedId
			then Theme.Colors.AccentStrong
			else Theme.Colors.SurfaceRaised
		setButtonEnabled(card, #snapshot.modals == 0)
		if
			not connectDynamic(data, card, function()
				data.localSelectedUnitId = cardTower.unitId
				emit(data, { kind = "SelectTower", unitId = cardTower.unitId, towerId = cardTower.towerId })
				if data.current ~= nil then
					renderCanonical(data, data.current :: LobbyUiModel.RenderState)
				end
				local current = data.current
				if current ~= nil and current.inputFamily == "Gamepad" and data.compactMode then
					pcall(data.dependencies.selectObject, data.instances.detailBackButton)
				end
			end)
		then
			error("dynamic inventory connection failed", 0)
		end
		data.inventoryCardCount += 1
	end

	if tower == nil then
		instances.detailTitle.Text = "SELECT A TOWER"
		instances.detailOwnership.Text = "Owned tower details and match upgrades are shown separately here."
		instances.detailDescription.Text = ""
		instances.detailStats.Text = ""
		instances.detailUpgrade.Text = ""
		for _, button in { instances.equipButton, instances.favoriteButton, instances.lockButton } do
			setButtonEnabled(button, false)
		end
		return
	end
	instances.detailTitle.Text = tower.displayName
	instances.detailOwnership.Text = `OWNED COPIES {tower.copies} • {if tower.equippedSlot == nil
		then "NOT EQUIPPED"
		else `EQUIPPED SLOT {tower.equippedSlot}`}\nSOURCE: {tower.acquisitionSource}`
	instances.detailDescription.Text = tower.description
	instances.detailStats.Text =
		`MATCH LEVEL 1 • DAMAGE {tower.damage} • RANGE {tower.rangeStuds}\nCOOLDOWN {string.format(
			"%.2fs",
			tower.cooldownSeconds
		)} • COST ${tower.placementCost} • LIMIT {tower.placementCap}\nTARGETING: {tower.targetModesText}`
	instances.detailUpgrade.Text = `MATCH UPGRADE PREVIEW: {tower.upgradePreview}`
	instances.equipButton.Text = if tower.equippedSlot == nil then "EQUIP" else "UNEQUIP"
	instances.favoriteButton.Text = if tower.favorite then "★ FAVORITE" else "☆ FAVORITE"
	instances.lockButton.Text = if tower.locked then "◆ LOCKED" else "◇ LOCK"
	for _, button in { instances.equipButton, instances.favoriteButton, instances.lockButton } do
		setButtonEnabled(button, #snapshot.modals == 0)
	end
end

local function renderParty(data: ViewData, snapshot: LobbyUiModel.RenderState, layout: ResponsiveLayout.Layout)
	local instances = data.instances
	local interactive = snapshot.profileState == "Ready" and #snapshot.modals == 0 and not snapshot.squadMutationPending
	instances.partyInviteInput.Text = data.partyInviteText
	if snapshot.partyState ~= "Ready" or snapshot.partySnapshot == nil then
		instances.partyStatus.Text = if snapshot.partyState == "Failed"
			then "PARTY UNAVAILABLE • Refreshing server-owned state."
			else "LOADING AUTHORITATIVE PARTY…"
		instances.partyInviteInput.Visible = false
		instances.partyInviteInput.PlaceholderText = "Waiting for party snapshot"
		instances.partyInviteInput.Active = false
		instances.partyInviteInput.Selectable = false
		for _, button in
			{
				instances.partyCreateButton,
				instances.partyInviteButton,
				instances.partyPlatformInviteButton,
				instances.partyPrivacyButton,
				instances.partyLeaveButton,
				instances.partyDisbandButton,
			}
		do
			button.Visible = false
			setButtonEnabled(button, false)
		end
		return
	end

	local party = snapshot.partySnapshot.party
	local isLeader = party ~= nil and party.leaderUserId == snapshot.localUserId
	local partyHasRoom = party ~= nil and #party.members < 4
	instances.partyCreateButton.Visible = party == nil
	setButtonEnabled(instances.partyCreateButton, party == nil and interactive)
	instances.partyInviteInput.Visible = party ~= nil
	instances.partyInviteInput.PlaceholderText = "Present player UserId"
	instances.partyInviteInput.Active = isLeader and interactive and partyHasRoom
	instances.partyInviteInput.Selectable = instances.partyInviteInput.Active
	instances.partyInviteButton.Visible = party ~= nil
	instances.partyPlatformInviteButton.Visible = party ~= nil
	instances.partyPrivacyButton.Visible = party ~= nil
	instances.partyLeaveButton.Visible = party ~= nil
	instances.partyDisbandButton.Visible = party ~= nil
	setButtonEnabled(instances.partyInviteButton, isLeader and interactive and partyHasRoom)
	setButtonEnabled(instances.partyPlatformInviteButton, isLeader and interactive and partyHasRoom)
	setButtonEnabled(instances.partyPrivacyButton, isLeader and interactive)
	setButtonEnabled(instances.partyLeaveButton, party ~= nil and interactive)
	setButtonEnabled(instances.partyDisbandButton, isLeader and interactive)
	if party == nil then
		instances.partyStatus.Text = `NO PARTY • {#snapshot.partySnapshot.incomingInvitations} bounded invitation(s)`
	else
		instances.partyStatus.Text =
			`PARTY {#party.members}/4 • {party.privacy} • {party.queueState} • REV {party.revision}`
		instances.partyPrivacyButton.Text = `PRIVACY\n{string.upper(party.privacy)}`
		for index, member in party.members do
			local memberLabel = makeButton(
				`PartyMember{index}`,
				instances.partyList,
				`{if member.isLeader then "CAPTAIN • " else ""}USER {member.userId}\n{if member.profileReady
					then "PROFILE READY"
					else "PROFILE LOADING"}`,
				Theme.ZIndex.Content + 3
			)
			memberLabel.LayoutOrder = index * 3
			memberLabel.Size = UDim2.new(1, -10, 0, layout.touchTarget + 12)
			memberLabel.TextXAlignment = Enum.TextXAlignment.Left
			setButtonEnabled(memberLabel, false)
			if isLeader and member.userId ~= snapshot.localUserId then
				local kick = makeButton(
					`KickMember{index}`,
					instances.partyList,
					`REMOVE USER {member.userId}`,
					Theme.ZIndex.Content + 3
				)
				kick.LayoutOrder = index * 3 + 1
				kick.Size = UDim2.new(1, -10, 0, layout.touchTarget)
				setButtonEnabled(kick, interactive)
				if
					not connectDynamic(data, kick, function()
						emit(data, { kind = "KickPartyMember", targetUserId = member.userId })
					end)
				then
					error("dynamic party kick connection failed", 0)
				end
				local transfer = makeButton(
					`TransferMember{index}`,
					instances.partyList,
					`TRANSFER LEADERSHIP TO {member.userId}`,
					Theme.ZIndex.Content + 3
				)
				transfer.LayoutOrder = index * 3 + 2
				transfer.Size = UDim2.new(1, -10, 0, layout.touchTarget)
				setButtonEnabled(transfer, interactive)
				if
					not connectDynamic(data, transfer, function()
						emit(data, { kind = "TransferPartyLeadership", targetUserId = member.userId })
					end)
				then
					error("dynamic party transfer connection failed", 0)
				end
			end
		end
	end
	for index, invitation in snapshot.partySnapshot.incomingInvitations do
		local accept = makeButton(
			`AcceptInvitation{index}`,
			instances.partyList,
			`ACCEPT INVITE FROM USER {invitation.inviterUserId}`,
			Theme.ZIndex.Content + 3
		)
		accept.LayoutOrder = 100 + index * 2
		accept.Size = UDim2.new(1, -10, 0, layout.touchTarget)
		setButtonEnabled(accept, party == nil and interactive)
		if
			not connectDynamic(data, accept, function()
				emit(data, { kind = "AcceptPartyInvite", invitationId = invitation.invitationId })
			end)
		then
			error("dynamic party accept connection failed", 0)
		end
		local decline = makeButton(
			`DeclineInvitation{index}`,
			instances.partyList,
			`DECLINE INVITE FROM USER {invitation.inviterUserId}`,
			Theme.ZIndex.Content + 3
		)
		decline.LayoutOrder = 101 + index * 2
		decline.Size = UDim2.new(1, -10, 0, layout.touchTarget)
		setButtonEnabled(decline, interactive)
		if
			not connectDynamic(data, decline, function()
				emit(data, { kind = "DeclinePartyInvite", invitationId = invitation.invitationId })
			end)
		then
			error("dynamic party decline connection failed", 0)
		end
	end
end

local function renderQueue(data: ViewData, snapshot: LobbyUiModel.RenderState, layout: ResponsiveLayout.Layout)
	local instances = data.instances
	local interactive = snapshot.profileState == "Ready" and #snapshot.modals == 0 and not snapshot.squadMutationPending
	local routeAvailable = snapshot.activeRouteState == "Ready"
		and snapshot.activeRoute ~= nil
		and snapshot.activeRoute.status == "Available"
	setButtonEnabled(instances.reconnectButton, routeAvailable and interactive)
	instances.reconnectButton.Text = if snapshot.activeRouteState == "Loading"
		then "CHECKING ACTIVE MATCH…"
		elseif routeAvailable then "RECONNECT TO ACTIVE MATCH"
		elseif
			snapshot.activeRoute ~= nil and snapshot.activeRoute.status == "Stale"
		then "RECONNECT EXPIRED • SAFE IN LOBBY"
		elseif snapshot.activeRouteState == "Failed" then "RECONNECT STATUS UNAVAILABLE"
		else "NO ACTIVE MATCH"
	if snapshot.queuesState ~= "Ready" or snapshot.queueSnapshots == nil then
		instances.queueStatus.Text = if snapshot.queuesState == "Failed"
			then "QUEUES UNAVAILABLE • Refreshing server-owned state."
			else "LOADING AUTHORITATIVE QUEUES…"
		instances.queueRoster.Text = "ROSTER —"
		instances.queueConfiguration.Text = "CONFIGURATION —"
		for _, button in
			{
				instances.queueJoinButton,
				instances.queueLeaveButton,
				instances.queueMapButton,
				instances.queueDifficultyButton,
				instances.queuePrivacyButton,
				instances.queueCapacityButton,
				instances.queueStartButton,
			}
		do
			setButtonEnabled(button, false)
		end
		return
	end
	for index, queue in snapshot.queueSnapshots do
		local selector = makeButton(
			`Queue{index}`,
			instances.queueList,
			`{queue.queueId}\n{#queue.members}/{queue.configuration.maxPlayers} • {queue.state}`,
			Theme.ZIndex.Content + 3
		)
		selector.LayoutOrder = index
		selector.Size = UDim2.new(1, -10, 0, layout.touchTarget + 14)
		selector.TextXAlignment = Enum.TextXAlignment.Left
		selector.BackgroundColor3 = if queue.queueId == snapshot.selectedQueueId
			then Theme.Colors.AccentStrong
			else Theme.Colors.SurfaceRaised
		setButtonEnabled(selector, interactive)
		if
			not connectDynamic(data, selector, function()
				emit(data, { kind = "SelectQueue", queueId = queue.queueId })
			end)
		then
			error("dynamic queue selection connection failed", 0)
		end
	end
	local queue = selectedQueue(snapshot)
	if queue == nil then
		instances.queueStatus.Text = "NO CONFIGURED QUEUE"
		instances.queueRoster.Text = "ROSTER —"
		instances.queueConfiguration.Text = "CONFIGURATION —"
		return
	end
	local isMember = false
	local isCaptain = queue.captainUserId == snapshot.localUserId
	local roster = table.create(#queue.members)
	for index, member in queue.members do
		isMember = isMember or member.userId == snapshot.localUserId
		roster[index] = `{if member.isCaptain then "CAPTAIN " else ""}USER {member.userId} • {member.readiness}`
	end
	local status = queue.publicStatus or queue.state
	instances.queueStatus.Text = `{queue.queueId} • {string.upper(status)} • REV {queue.revision}`
	instances.queueRoster.Text = if #roster == 0 then "ROSTER • EMPTY" else `ROSTER\n{table.concat(roster, "\n")}`
	instances.queueConfiguration.Text =
		`MAP {queue.configuration.mapId} • DIFFICULTY {queue.configuration.difficultyId}\n{queue.configuration.privacy} • CAPACITY {queue.configuration.maxPlayers}`
	instances.queueMapButton.Text = `MAP\n{queue.configuration.mapId}`
	instances.queueDifficultyButton.Text = `DIFFICULTY\n{queue.configuration.difficultyId}`
	instances.queuePrivacyButton.Text = `PRIVACY\n{queue.configuration.privacy}`
	instances.queueCapacityButton.Text = `CAPACITY\n{queue.configuration.maxPlayers}`
	local open = queue.state == "Open"
	setButtonEnabled(instances.queueJoinButton, interactive and open and not isMember)
	setButtonEnabled(instances.queueLeaveButton, interactive and open and isMember)
	for _, button in
		{
			instances.queueMapButton,
			instances.queueDifficultyButton,
			instances.queuePrivacyButton,
			instances.queueCapacityButton,
		}
	do
		setButtonEnabled(button, interactive and open and isCaptain)
	end
	setButtonEnabled(instances.queueStartButton, interactive and open and isCaptain and queue.canStart)
end

local function renderToasts(data: ViewData, snapshot: LobbyUiModel.RenderState, layout: ResponsiveLayout.Layout)
	for index, toast in snapshot.toasts do
		local toastButton = makeButton(
			`Toast{index}`,
			data.instances.toastContainer,
			`{toast.kind == "Success" and "✓" or toast.kind == "Warning" and "!" or toast.kind == "Error" and "✕" or "i"} {toast.title}\n{toast.message}{if toast.repeatCount
					> 1
				then ` • repeated ×{toast.repeatCount}`
				else ""}`,
			Theme.ZIndex.Toast + index
		)
		toastButton.Position = UDim2.fromOffset(0, (index - 1) * (layout.touchTarget + 42))
		toastButton.Size = UDim2.new(1, 0, 0, layout.touchTarget + 34)
		toastButton.TextSize = layout.baseTextSize - 1
		toastButton.TextXAlignment = Enum.TextXAlignment.Left
		toastButton.BackgroundColor3 = if toast.kind == "Success"
			then Theme.Colors.Success
			elseif toast.kind == "Warning" then Theme.Colors.Warning
			elseif toast.kind == "Error" then Theme.Colors.Error
			else Theme.Colors.Info
		setButtonEnabled(toastButton, #snapshot.modals == 0)
		if
			not connectDynamic(data, toastButton, function()
				emit(data, { kind = "DismissToast", toastId = toast.id })
			end)
		then
			error("dynamic toast connection failed", 0)
		end
	end
end

local function renderSettings(instances: Instances, settings: LobbyUiModel.Settings?, enabled: boolean)
	for _, key in SETTING_ORDER do
		local button = instances.settingsButtons[key]
		if settings == nil then
			button.Text = `{SETTING_LABELS[key]}: —`
			setButtonEnabled(button, false)
		else
			local value = (settings :: any)[key]
			local display = if type(value) == "boolean"
				then (if value then "ON" else "OFF")
				elseif key == "uiScale" then `{math.floor((value :: number) * 100 + 0.5)}%`
				else `{math.floor((value :: number) * 100 + 0.5)}%`
			button.Text = `{SETTING_LABELS[key]}: {display}`
			setButtonEnabled(button, enabled)
		end
	end
end

local function bestFocus(instances: Instances, snapshot: LobbyUiModel.RenderState): GuiObject?
	local modal = snapshot.modals[#snapshot.modals]
	if modal ~= nil then
		if modal.confirmText ~= nil and not modal.busy then
			return instances.modalConfirm
		elseif modal.cancelText ~= nil or modal.dismissable then
			return instances.modalCancel
		end
		return nil
	end
	if snapshot.profileState ~= "Ready" then
		if snapshot.profileState == "Failed" then
			if snapshot.canRetry then
				return instances.retryButton
			elseif snapshot.canLeave then
				return instances.leaveButton
			end
		end
		return nil
	end
	if snapshot.screen == "Home" then
		return instances.playButton
	elseif snapshot.screen == "Party" then
		if snapshot.partyState ~= "Ready" or snapshot.partySnapshot == nil then
			return instances.backButton
		end
		return if snapshot.partySnapshot.party == nil then instances.partyCreateButton else instances.partyInviteInput
	elseif snapshot.screen == "Queue" then
		return instances.queueJoinButton
	elseif snapshot.screen == "Inventory" then
		return instances.inventorySearch
	elseif snapshot.screen == "Chests" then
		return if snapshot.banner ~= nil and snapshot.banner.canPullOne
			then instances.onePullButton
			else instances.backButton
	end
	return instances.settingsButtons.masterVolume
end

local function updateFocus(data: ViewData, snapshot: LobbyUiModel.RenderState, previous: LobbyUiModel.RenderState?)
	local previousDepth = if previous == nil then 0 else #previous.modals
	local nextDepth = #snapshot.modals
	if nextDepth < previousDepth then
		local restore: GuiObject? = nil
		for _ = previousDepth, nextDepth + 1, -1 do
			local entry = table.remove(data.focusStack)
			if entry ~= nil then
				restore = entry.object
			end
		end
		if snapshot.inputFamily == "Gamepad" and restore ~= nil and restore:IsDescendantOf(data.instances.gui) then
			pcall(data.dependencies.selectObject, restore)
			return
		end
	end
	if
		snapshot.inputFamily == "Gamepad"
		and (
			previous == nil
			or previous.inputFamily ~= "Gamepad"
			or previous.screen ~= snapshot.screen
			or previousDepth ~= nextDepth
			or previous.profileState ~= snapshot.profileState
		)
	then
		pcall(data.dependencies.selectObject, bestFocus(data.instances, snapshot))
	end
end

local function prepareFocusTransition(
	data: ViewData,
	snapshot: LobbyUiModel.RenderState,
	previous: LobbyUiModel.RenderState?
)
	if previous == nil then
		return
	end
	local previousDepth = #previous.modals
	local nextDepth = #snapshot.modals
	local selected: GuiObject? = nil
	pcall(function()
		selected = data.dependencies.getSelectedObject()
	end)
	if nextDepth > previousDepth then
		for _ = previousDepth + 1, nextDepth do
			table.insert(data.focusStack, { object = selected })
		end
	end
	local hidesSelectedSurface = previous.profileState ~= snapshot.profileState
		or previous.screen ~= snapshot.screen
		or nextDepth ~= previousDepth
		or (previous.inputFamily == "Gamepad" and snapshot.inputFamily ~= "Gamepad")
	if hidesSelectedSurface and selected ~= nil and selected:IsDescendantOf(data.instances.gui) then
		pcall(data.dependencies.selectObject, nil)
	end
end

renderCanonical = function(data: ViewData, snapshot: LobbyUiModel.RenderState)
	local instances = data.instances
	local previous = data.current
	prepareFocusTransition(data, snapshot, previous)
	local uiScale = if snapshot.settings == nil then 1 else snapshot.settings.uiScale
	local effectiveReducedMotion = snapshot.reducedMotion
		or (snapshot.settings ~= nil and snapshot.settings.reducedMotionEnabled)
	local layout = ResponsiveLayout.resolve(snapshot.viewport, uiScale, snapshot.preferredTextScale)
	if layout == nil then
		error("invalid responsive layout", 0)
	end
	data.compactMode = layout.mode == "Compact"
	applyLayout(instances, layout)
	instances.root.Size = UDim2.fromScale(1 / uiScale, 1 / uiScale)
	instances.uiScale.Scale = uiScale
	instances.gui:SetAttribute("ATDReducedMotion", effectiveReducedMotion)
	local baseTransparency = math.clamp(0.04 + snapshot.preferredTransparency * 0.35, 0.04, 0.5)
	instances.header.BackgroundTransparency = baseTransparency
	instances.navigation.BackgroundTransparency = baseTransparency
	instances.content.BackgroundTransparency = baseTransparency

	data.current = snapshot
	if not clearDynamic(data) then
		error("dynamic cleanup failed", 0)
	end
	instances.readiness.Text = string.upper(snapshot.statusText)
	instances.gold.Text = if snapshot.profileState == "Ready" then `GOLD {snapshot.gold}` else "GOLD —"
	instances.header.Visible = snapshot.profileState == "Ready"
	instances.navigation.Visible = snapshot.profileState == "Ready"
	instances.content.Visible = snapshot.profileState == "Ready"
	instances.blocking.Visible = snapshot.profileState ~= "Ready"
	data.goldText = instances.gold.Text
	data.blockingVisible = instances.blocking.Visible
	instances.backButton.Visible = snapshot.profileState == "Ready"
		and (snapshot.screen ~= "Home" or #snapshot.modals > 0)
	instances.title.Visible = not instances.backButton.Visible
	setButtonEnabled(instances.backButton, instances.backButton.Visible)

	if snapshot.profileState ~= "Ready" then
		instances.blockingTitle.Text = if snapshot.profileState == "Loading"
			then "LOADING PROFILE"
			elseif snapshot.profileState == "Failed" then "PROFILE LOAD FAILED"
			else "SAVING & RELEASING"
		instances.blockingMessage.Text = snapshot.statusText
		instances.retryButton.Visible = snapshot.canRetry
		instances.leaveButton.Visible = snapshot.canLeave
		setButtonEnabled(instances.retryButton, snapshot.canRetry)
		setButtonEnabled(instances.leaveButton, snapshot.canLeave)
	else
		instances.homeStatus.Text = if snapshot.isFirstJoin
			then "NEW COLONY READY • Your starter tower is equipped. Inventory, Chests, and Settings are ready."
			elseif snapshot.didMigrate then "WELCOME BACK • Your saved profile was migrated safely."
			else "WELCOME BACK • Your Gold, inventory, loadout, pity, and settings are ready."
		instances.homeProgression.Text = `PROGRESSION • {snapshot.progressionText}`
		for _, screen in NAVIGATION_ORDER do
			local active = screen == snapshot.screen
			instances.screens[screen].Visible = active
			local navButton = instances.navigationButtons[screen]
			navButton.BackgroundColor3 = if active then Theme.Colors.AccentStrong else Theme.Colors.SurfaceRaised
			setButtonEnabled(navButton, #snapshot.modals == 0)
		end
		setButtonEnabled(instances.playButton, #snapshot.modals == 0)
		setButtonEnabled(instances.inventorySort, #snapshot.modals == 0)
		setButtonEnabled(instances.inventoryFilter, #snapshot.modals == 0)
		instances.inventorySearch.Active = #snapshot.modals == 0
		instances.inventorySearch.Selectable = #snapshot.modals == 0
		renderInventory(data, snapshot)
		renderParty(data, snapshot, layout)
		renderQueue(data, snapshot, layout)

		local banner = snapshot.banner
		if banner == nil then
			instances.chestTitle.Text = "CHESTS UNAVAILABLE"
			instances.chestPolicy.Text =
				"Earn-only chest configuration is not currently available. No Gold can be spent."
			instances.chestPity.Text = "PITY —"
			instances.chestOdds.Text = "Exact odds unavailable."
			instances.onePullButton.Text = "OPEN 1 —"
			instances.tenPullButton.Text = "OPEN 10 —"
			for _, button in { instances.onePullButton, instances.tenPullButton, instances.skipButton } do
				setButtonEnabled(button, false)
			end
		else
			instances.chestTitle.Text = banner.displayName
			instances.chestPolicy.Text =
				"EARN-ONLY GOLD • Exact final odds are disclosed below. No Robux, products, passes, or paid conversion."
			instances.chestPity.Text = `PITY {banner.pityCount} / {banner.hardPityPullCount}`
			local oddsLines = table.create(#banner.odds)
			for index, odd in banner.odds do
				oddsLines[index] = `{odd.displayName}: {string.format("%.4g", odd.probabilityPercent)}%`
			end
			instances.chestOdds.Text = `EXACT ODDS\n{table.concat(oddsLines, "\n")}`
			instances.onePullButton.Text = `OPEN 1\n{banner.onePullCost} GOLD`
			instances.tenPullButton.Text = `OPEN 10\n{banner.tenPullCost} GOLD`
			setButtonEnabled(
				instances.onePullButton,
				banner.canPullOne and not banner.transactionPending and #snapshot.modals == 0
			)
			setButtonEnabled(
				instances.tenPullButton,
				banner.canPullTen and not banner.transactionPending and #snapshot.modals == 0
			)
			instances.skipButton.Visible = banner.transactionPending
			setButtonEnabled(instances.skipButton, banner.transactionPending and #snapshot.modals == 0)
		end
		renderSettings(instances, snapshot.settings, #snapshot.modals == 0)
	end

	local modal = snapshot.modals[#snapshot.modals]
	instances.modalScrim.Visible = modal ~= nil
	if modal ~= nil then
		instances.modalDepth.Text = if #snapshot.modals > 1
			then `DIALOG {#snapshot.modals} OF {#snapshot.modals}`
			else "CONFIRMATION"
		instances.modalTitle.Text = modal.title
		instances.modalMessage.Text = modal.message
		instances.modalConfirm.Visible = modal.confirmText ~= nil
		instances.modalConfirm.Text = modal.confirmText or "CONFIRM"
		instances.modalCancel.Visible = modal.cancelText ~= nil or modal.dismissable
		instances.modalCancel.Text = modal.cancelText or "CLOSE"
		setButtonEnabled(instances.modalConfirm, modal.confirmText ~= nil and not modal.busy)
		setButtonEnabled(instances.modalCancel, (modal.cancelText ~= nil or modal.dismissable) and not modal.busy)
	end

	renderToasts(data, snapshot, layout)
	updateFocus(data, snapshot, previous)
end

local function construct(
	parent: Instance,
	callback: Callback,
	dependencies: Dependencies,
	productionStyle: boolean
): ViewResult
	if typeof(parent) ~= "Instance" then
		return failure("INVALID_PARENT")
	end
	if
		type(callback) ~= "function"
		or type(dependencies) ~= "table"
		or type(dependencies.connectActivated) ~= "function"
		or type(dependencies.connectInputBegan) ~= "function"
		or type(dependencies.connectInputFamilyChanged) ~= "function"
		or type(dependencies.connectSearchCommitted) ~= "function"
		or type(dependencies.selectObject) ~= "function"
		or type(dependencies.getSelectedObject) ~= "function"
	then
		return failure("INVALID_ARGUMENT")
	end
	if parent:FindFirstChild(GUI_NAME) ~= nil then
		return failure("GUI_CONFLICT")
	end
	local instances = createInstances(parent, productionStyle)
	if instances == nil then
		return failure("CREATION_FAILED")
	end
	local view = setmetatable({}, ViewMethods) :: View
	table.freeze(view)
	local data: ViewData = {
		instances = instances,
		callback = callback,
		dependencies = dependencies,
		connections = {},
		dynamicConnections = {},
		current = nil,
		focusStack = {},
		localSelectedUnitId = nil,
		partyInviteText = "",
		inventoryQuery = "",
		inventorySort = "Name",
		inventoryFilter = "All",
		renderCount = 0,
		actionCount = 0,
		inventoryCardCount = 0,
		goldText = "GOLD —",
		blockingVisible = true,
		cleaned = false,
		productionStyle = productionStyle,
		compactMode = false,
	}
	DATA[view] = data
	if not connectStatic(data) then
		disconnectAll(data.connections)
		instances.gui:Destroy()
		DATA[view] = nil
		return failure("CONNECTION_FAILED")
	end
	instances.header.Visible = false
	instances.navigation.Visible = false
	instances.content.Visible = false
	instances.modalScrim.Visible = false
	instances.retryButton.Visible = false
	instances.leaveButton.Visible = false
	instances.skipButton.Visible = false
	return ok(view)
end

function ViewMethods.render(self: View, value: unknown): Outcome<Metrics>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local canonical = LobbyUiModel.canonicalize(value)
	if canonical == nil then
		return failure("INVALID_RENDER_STATE")
	end
	local rendered = pcall(renderCanonical, data, canonical)
	if not rendered then
		return failure("RENDER_FAILED")
	end
	data.renderCount += 1
	return ok(self:getMetrics())
end

function ViewMethods.getMetrics(self: View): Metrics
	local data = requireData(self)
	local snapshot = data.current
	return table.freeze({
		profileState = if snapshot == nil then nil else snapshot.profileState,
		activeScreen = if snapshot == nil then nil else snapshot.screen,
		modalDepth = if snapshot == nil then 0 else #snapshot.modals,
		toastCount = if snapshot == nil then 0 else #snapshot.toasts,
		inventoryCardCount = data.inventoryCardCount,
		staticConnectionCount = #data.connections,
		dynamicConnectionCount = #data.dynamicConnections,
		renderCount = data.renderCount,
		actionCount = data.actionCount,
		goldText = data.goldText,
		blockingVisible = data.blockingVisible,
		cleaned = data.cleaned,
	})
end

function ViewMethods.cleanup(self: View): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return ok(true)
	end
	data.cleaned = true
	data.goldText = "GOLD —"
	data.blockingVisible = false
	local succeeded = pcall(function()
		local selected = data.dependencies.getSelectedObject()
		if selected ~= nil and selected:IsDescendantOf(data.instances.gui) then
			data.dependencies.selectObject(nil)
		end
	end)
	if not clearDynamic(data) then
		succeeded = false
	end
	if not disconnectAll(data.connections) then
		succeeded = false
	end
	if not pcall(function()
		data.instances.gui:Destroy()
	end) then
		succeeded = false
	end
	table.clear(data.focusStack)
	data.current = nil
	if not succeeded then
		return failure("CLEANUP_FAILED")
	end
	return ok(true)
end

local function inputFamilyFromType(inputType: Enum.UserInputType): InputFamily
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.sub(inputType.Name, 1, 7) == "Gamepad" then
		return "Gamepad"
	end
	return "Desktop"
end

local function productionDependencies(): Dependencies
	return {
		connectActivated = function(button, callback)
			return button.Activated:Connect(callback)
		end,
		connectInputBegan = function(callback)
			return UserInputService.InputBegan:Connect(function(input, processed)
				callback(input.KeyCode.Name, processed)
			end)
		end,
		connectInputFamilyChanged = function(callback)
			return UserInputService.LastInputTypeChanged:Connect(function(inputType)
				callback(inputFamilyFromType(inputType))
			end)
		end,
		connectSearchCommitted = function(textBox, callback)
			return textBox.FocusLost:Connect(function()
				callback(textBox.Text)
			end)
		end,
		selectObject = function(value)
			GuiService.SelectedObject = value
		end,
		getSelectedObject = function()
			return GuiService.SelectedObject
		end,
	}
end

function LobbyView.new(callback: unknown): ViewResult
	if type(callback) ~= "function" then
		return failure("INVALID_ARGUMENT")
	end
	local player = Players.LocalPlayer
	local playerGui = if player == nil then nil else player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return failure("INVALID_PARENT")
	end
	return construct(playerGui, callback :: Callback, productionDependencies(), true)
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "LobbyView" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionClientLobbyUi" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

if isExactTestModule() then
	LobbyView.newForTests = function(parent: Instance, callback: Callback, dependencies: Dependencies): ViewResult
		if typeof(parent) ~= "Instance" or not parent:IsA("Folder") then
			return failure("INVALID_PARENT")
		end
		return construct(parent, callback, dependencies, false)
	end
end

table.freeze(ViewMethods)
return table.freeze(LobbyView)
