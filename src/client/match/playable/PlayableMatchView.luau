--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Localization = require(ReplicatedStorage.Shared.localization.Localization)
local Accessibility = require(ReplicatedStorage.Shared.settings.Accessibility)
local function commonUiRoot(): Instance
	local common = script.Parent.Parent.Parent:FindFirstChild("common")
	local production = if common == nil then nil else common:FindFirstChild("ui")
	local mirrored = script.Parent.Parent:FindFirstChild("ProductionClientCommonUi")
	return production or mirrored or error("[ATD_PLAYABLE_VIEW][code=COMMON_UI_MISSING]", 0)
end
local FocusNavigation = require(commonUiRoot().FocusNavigation)
local TextLayout = require(commonUiRoot().TextLayout)
local PresentationPolicy = require(ReplicatedStorage.Shared.presentation.PresentationPolicy)
local TowerAim = require(ReplicatedStorage.Shared.presentation.TowerAim)
local ProfileScope = require(ReplicatedStorage.Shared.util.ProfileScope)

export type InputFamily = "Desktop" | "Touch" | "Gamepad"
export type MatchState = "Loading" | "ReadyCheck" | "PreWave" | "WaveActive" | "Results" | "Closing"
export type ResultKind = "Victory" | "Defeat"
export type ViewerRole = "Participant" | "Spectator"
export type RewardStatus = "Granted" | "Pending" | "Ineligible" | "Failed"
export type TargetMode = "First" | "Last" | "Strongest" | "Weakest" | "Closest"
export type ModeKind = "Finite" | "Endless"
export type BossKind = "None" | "MiniBoss" | "Boss"
export type UiActionKind =
	"SelectHotbar"
	| "FocusBase"
	| "Ready"
	| "Upgrade"
	| "Retarget"
	| "Sell"
	| "Confirm"
	| "Rotate"
	| "Cancel"
	| "Replay"
	| "Return"
	| "RematchApprove"
	| "RematchDecline"
	| "SpectatePrevious"
	| "SpectateNext"

export type UiAction = {
	kind: UiActionKind,
	source: InputFamily,
	matchId: string,
	matchRevision: number,
	slot: number?,
	towerId: string?,
	towerRevision: number?,
	targetMode: TargetMode?,
}

export type UiActionCallback = (UiAction) -> ()

export type HotbarSlot = {
	slot: number,
	displayName: string,
	description: string?,
	cost: number,
	available: boolean,
	selected: boolean,
	reason: string?,
}

export type BossState = {
	runtimeEnemyId: number,
	displayName: string,
	currentHealth: number,
	maximumHealth: number,
	threatClass: "MiniBoss" | "Boss",
}

export type WaveState = {
	current: number,
	total: number?,
	enemiesRemaining: number,
	status: string?,
	modeKind: ModeKind?,
	bossKind: BossKind?,
	boss: BossState?,
}

export type BaseState = {
	health: number,
	maxHealth: number,
}

export type ReadyState = {
	enabled: boolean,
	countdownSeconds: number?,
	status: string?,
}

export type TowerSelection = {
	towerId: string,
	revision: number,
	displayName: string,
	description: string?,
	isOwner: boolean,
	level: number,
	maxLevel: number,
	targetMode: TargetMode,
	damage: number,
	range: number,
	cooldownSeconds: number,
	upgradeCost: number?,
	sellValue: number?,
	canUpgrade: boolean,
	canRetarget: boolean,
	canSell: boolean,
}

export type FeedbackState = {
	code: string,
}

export type PlacementState = {
	positionSelected: boolean,
	rotationDegrees: number,
	controlsEnabled: boolean,
}

export type ResultState = {
	kind: ResultKind,
	summary: string,
	canReplay: boolean,
	status: string?,
	rewardStatus: RewardStatus,
	persistentGoldAwarded: number,
	firstClearBonus: number,
	battleCashEarned: number,
	battleCashSpent: number,
	rewardReason: string?,
}

export type TravelState = {
	returnStatus: "Idle" | "Pending" | "Teleporting" | "Failed",
	failure: string?,
	canReturn: boolean,
	rematchState: "Pending" | "Starting" | "Approved" | "Declined" | "Failed"?,
	rematchStatus: string?,
	canApprove: boolean,
	canDecline: boolean,
}

export type RenderSnapshot = {
	matchId: string,
	revision: number,
	viewerRole: ViewerRole,
	state: MatchState,
	inputFamily: InputFamily,
	wave: WaveState,
	base: BaseState,
	battleCash: number,
	hotbar: { HotbarSlot },
	tutorialStep: number?,
	ready: ReadyState?,
	selection: TowerSelection?,
	feedback: FeedbackState?,
	result: ResultState?,
	travel: TravelState?,
	placement: PlacementState?,
	inputHint: string?,
	viewport: Vector2?,
	uiScale: number?,
	reducedMotion: boolean?,
	lowEffects: boolean?,
	enemyHealthBars: boolean?,
	towerRange: boolean?,
}

export type TowerVisual = {
	id: string,
	definitionId: string,
	position: Vector3,
	rotationDegrees: number?,
	selected: boolean?,
	range: number?,
	level: number,
}

export type EnemyVisual = {
	id: string,
	definitionId: string,
	position: Vector3,
	health: number,
	maxHealth: number,
	archetype: string?,
}

export type WorldSnapshot = {
	towers: { TowerVisual },
	enemies: { EnemyVisual },
}

export type AttackEvent = {
	matchId: string,
	sequence: number,
	towerId: string,
	targetId: string,
	origin: Vector3?,
	target: Vector3?,
	damage: number?,
}

export type ResponsiveLayout = {
	mode: "Compact" | "Standard" | "TenFoot",
	hudWidth: number,
	hotbarWidth: number,
	towerPanelWidth: number,
	touchTarget: number,
	textSize: number,
}

export type Metrics = {
	connectionCount: number,
	renderCount: number,
	actionCount: number,
	matchState: MatchState?,
	inputFamily: InputFamily,
	waveText: string,
	enemyText: string,
	bossVisible: boolean,
	bossText: string,
	tutorialVisible: boolean,
	tutorialText: string,
	baseText: string,
	cashText: string,
	feedbackText: string,
	readyVisible: boolean,
	towerPanelVisible: boolean,
	inspectionOnly: boolean,
	resultsVisible: boolean,
	resultKind: ResultKind?,
	viewerRole: ViewerRole?,
	spectatorVisible: boolean,
	rewardText: string,
	travelText: string,
	touchPlacementVisible: boolean,
	touchPlacementText: string,
	worldTowerCount: number,
	worldEnemyCount: number,
	attackEffectCount: number,
	cleaned: boolean,
}

export type ErrorCode =
	"INVALID_ARGUMENT"
	| "INVALID_PARENT"
	| "GUI_CONFLICT"
	| "CREATION_FAILED"
	| "CONNECTION_FAILED"
	| "INVALID_SNAPSHOT"
	| "INVALID_WORLD"
	| "STALE_EVENT"
	| "ENTITY_NOT_FOUND"
	| "RENDER_FAILED"
	| "CLEANUP_FAILED"
	| "CLEANED_UP"

export type ViewError = {
	code: ErrorCode,
}

export type Outcome<T> = { ok: true, value: T } | { ok: false, error: ViewError }

export type Dependencies = {
	connectActivated: (GuiButton, () -> ()) -> RBXScriptConnection,
	connectStepped: ((number) -> ()) -> RBXScriptConnection,
	now: () -> number,
	selectObject: (GuiObject?) -> (),
	getSelectedObject: (() -> GuiObject?)?,
	connectInputBegan: (((string, boolean) -> ()) -> RBXScriptConnection)?,
	cleanupInput: (() -> ())?,
}

type CanonicalReady = ReadyState
type CanonicalSelection = TowerSelection
type CanonicalResult = ResultState
type CanonicalPlacement = PlacementState
type CanonicalSnapshot = RenderSnapshot

type ViewInstances = {
	gui: ScreenGui,
	root: Frame,
	uiScale: UIScale,
	topHud: Frame,
	waveLabel: TextLabel,
	enemyLabel: TextLabel,
	baseButton: TextButton,
	baseFill: Frame,
	cashLabel: TextLabel,
	bossPanel: Frame,
	bossLabel: TextLabel,
	bossHealth: Frame,
	bossHealthFill: Frame,
	tutorialPanel: Frame,
	tutorialLabel: TextLabel,
	hotbar: Frame,
	hotbarButtons: { TextButton },
	hintLabel: TextLabel,
	feedback: TextLabel,
	readyOverlay: Frame,
	readyCountdown: TextLabel,
	readyStatus: TextLabel,
	readyHint: TextLabel,
	readyButton: TextButton,
	towerPanel: Frame,
	towerTitle: TextLabel,
	towerStatus: TextLabel,
	towerStats: TextLabel,
	towerTarget: TextLabel,
	upgradeButton: TextButton,
	targetButton: TextButton,
	sellButton: TextButton,
	closeButton: TextButton,
	resultsOverlay: Frame,
	resultTitle: TextLabel,
	resultSummary: TextLabel,
	resultReward: TextLabel,
	resultHint: TextLabel,
	replayButton: TextButton,
	rematchApproveButton: TextButton,
	rematchDeclineButton: TextButton,
	spectatorPanel: Frame,
	spectatorBanner: TextLabel,
	spectatorTarget: TextLabel,
	spectatorPreviousButton: TextButton,
	spectatorNextButton: TextButton,
	returnButton: TextButton,
	touchPlacementPanel: Frame,
	touchPlacementStatus: TextLabel,
	touchConfirmButton: TextButton,
	touchRotateButton: TextButton,
	touchCancelButton: TextButton,
	worldFolder: Folder,
	towerFolder: Folder,
	enemyFolder: Folder,
	effectFolder: Folder,
}

type EffectRecord = {
	part: Part,
	expiresAt: number,
}

type TowerRecord = {
	aim: TowerAim.State,
	position: Vector3,
	model: Model,
	primaryPart: BasePart,
	definitionId: string,
	muzzles: { BasePart },
	selection: Highlight?,
	rangeIndicator: Part?,
	levelDisplay: BillboardGui,
	levelText: TextLabel,
	level: number,
	isPrimitiveFallback: boolean,
}

type EnemyRecord = {
	model: Model,
	primaryPart: BasePart,
	definitionId: string,
	healthFill: Frame?,
	healthText: TextLabel?,
	healthDisplay: BillboardGui?,
	isPrimitiveFallback: boolean,
}

type ViewData = {
	instances: ViewInstances,
	callback: UiActionCallback,
	dependencies: Dependencies,
	connections: { RBXScriptConnection },
	towerRecords: { [string]: TowerRecord },
	enemyRecords: { [string]: EnemyRecord },
	effects: { EffectRecord },
	effectsAdmittedThisFrame: number,
	lastPresentationStep: number,
	current: CanonicalSnapshot?,
	lastAttackSequence: number,
	lastFocusMode: string?,
	keyboardNavigation: boolean,
	activationCallbacks: { [GuiObject]: () -> () },
	focusRestore: GuiObject?,
	inputFamily: InputFamily,
	reducedMotion: boolean,
	lowEffects: boolean,
	enemyHealthBars: boolean,
	towerRange: boolean,
	renderCount: number,
	actionCount: number,
	cleaned: boolean,
	applyProductionStyle: boolean,
	templateRoot: Instance?,
	allowPrimitiveFallback: boolean,
}

local ViewMethods = {}
ViewMethods.__index = ViewMethods

export type View = typeof(setmetatable({} :: {}, ViewMethods))
export type ViewResult = Outcome<View>
export type TestConstructor = (Instance, Instance, UiActionCallback, Dependencies, boolean?) -> ViewResult
export type TemplateTestConstructor = (Instance, Instance, Instance, UiActionCallback, Dependencies) -> ViewResult
export type ResponsiveLayoutResolver = (unknown, unknown) -> ResponsiveLayout?

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ViewData }

local GUI_NAME = "ATDPlayableMatch"
local WORLD_FOLDER_NAME = "_ATDPlayablePresentation"
local TEMPLATE_FOLDER_NAME = "ATDPlayableTemplates"
local CONTENT_CONTRACT = "playable-local-match-v1"
local CONTENT_VERSION = 1
local HOTBAR_SLOTS = 5
local BUTTON_CONNECTION_COUNT = 20
local MAX_TOWERS = 64
local MAX_ENEMIES = 256
local MAX_ATTACK_EFFECTS = PresentationPolicy.MAX_EFFECTS
local MAX_MUZZLES_PER_TOWER = 8
local MAX_MUZZLE_OFFSET_STUDS = 16
local MAX_MODEL_LABEL_OFFSET_STUDS = 64
local EFFECT_DURATION_SECONDS = 0.12

local MATCH_STATES: { [MatchState]: boolean } = table.freeze({
	Loading = true,
	ReadyCheck = true,
	PreWave = true,
	WaveActive = true,
	Results = true,
	Closing = true,
})

local INPUT_FAMILIES: { [InputFamily]: boolean } = table.freeze({
	Desktop = true,
	Touch = true,
	Gamepad = true,
})

local TARGET_MODES: { TargetMode } = table.freeze({ "First", "Last", "Strongest", "Weakest", "Closest" })
local TARGET_MODE_SET: { [TargetMode]: boolean } = table.freeze({
	First = true,
	Last = true,
	Strongest = true,
	Weakest = true,
	Closest = true,
})

local function colorFromRGB(red: number, green: number, blue: number): Color3
	local succeeded, value = pcall(function(): Color3
		return Color3.fromRGB(red, green, blue)
	end)
	if succeeded then
		return value
	end
	local proxy = Instance.new("Part")
	local fallback = proxy.Color
	proxy:Destroy()
	return fallback
end

local COLORS = table.freeze({
	Background = colorFromRGB(19, 23, 31),
	Panel = colorFromRGB(32, 38, 49),
	Neutral = colorFromRGB(52, 61, 76),
	Selected = colorFromRGB(60, 113, 180),
	Good = colorFromRGB(57, 191, 105),
	Warning = colorFromRGB(241, 171, 56),
	Bad = colorFromRGB(225, 75, 75),
	Muted = colorFromRGB(145, 154, 171),
	Text = colorFromRGB(247, 249, 252),
	Effect = colorFromRGB(255, 224, 91),
})

local ERRORS: { [ErrorCode]: ViewError } = table.freeze({
	INVALID_ARGUMENT = table.freeze({ code = "INVALID_ARGUMENT" :: "INVALID_ARGUMENT" }),
	INVALID_PARENT = table.freeze({ code = "INVALID_PARENT" :: "INVALID_PARENT" }),
	GUI_CONFLICT = table.freeze({ code = "GUI_CONFLICT" :: "GUI_CONFLICT" }),
	CREATION_FAILED = table.freeze({ code = "CREATION_FAILED" :: "CREATION_FAILED" }),
	CONNECTION_FAILED = table.freeze({ code = "CONNECTION_FAILED" :: "CONNECTION_FAILED" }),
	INVALID_SNAPSHOT = table.freeze({ code = "INVALID_SNAPSHOT" :: "INVALID_SNAPSHOT" }),
	INVALID_WORLD = table.freeze({ code = "INVALID_WORLD" :: "INVALID_WORLD" }),
	STALE_EVENT = table.freeze({ code = "STALE_EVENT" :: "STALE_EVENT" }),
	ENTITY_NOT_FOUND = table.freeze({ code = "ENTITY_NOT_FOUND" :: "ENTITY_NOT_FOUND" }),
	RENDER_FAILED = table.freeze({ code = "RENDER_FAILED" :: "RENDER_FAILED" }),
	CLEANUP_FAILED = table.freeze({ code = "CLEANUP_FAILED" :: "CLEANUP_FAILED" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local PlayableMatchView = {
	GUI_NAME = GUI_NAME,
	WORLD_FOLDER_NAME = WORLD_FOLDER_NAME,
	HOTBAR_SLOTS = HOTBAR_SLOTS,
	BUTTON_CONNECTION_COUNT = BUTTON_CONNECTION_COUNT,
	MAX_TOWERS = MAX_TOWERS,
	MAX_ENEMIES = MAX_ENEMIES,
	MAX_ATTACK_EFFECTS = MAX_ATTACK_EFFECTS,
	newForTests = nil :: TestConstructor?,
	newTemplateBackedForTests = nil :: TemplateTestConstructor?,
	resolveResponsiveLayoutForTests = nil :: ResponsiveLayoutResolver?,
}

local function ok<T>(value: T): Outcome<T>
	return table.freeze({
		ok = true :: true,
		value = value,
	})
end

local function failure<T>(code: ErrorCode): Outcome<T>
	return table.freeze({
		ok = false :: false,
		error = ERRORS[code],
	})
end

local function requireData(value: unknown): ViewData
	if type(value) ~= "table" then
		error("[ATD_PLAYABLE_VIEW][code=INVALID_CONTEXT]", 0)
	end
	local data = DATA[value :: any]
	if data == nil then
		error("[ATD_PLAYABLE_VIEW][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function finiteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function safeInteger(value: unknown, minimum: number, maximum: number): boolean
	return finiteNumber(value)
		and (value :: number) % 1 == 0
		and (value :: number) >= minimum
		and (value :: number) <= maximum
end

local function safeText(value: unknown, maximumLength: number, allowEmpty: boolean?): boolean
	return type(value) == "string"
		and (allowEmpty == true or #value > 0)
		and #value <= maximumLength
		and string.find(value, "[%z\1-\8\11\12\14-\31]") == nil
end

local function safeId(value: unknown): boolean
	return safeText(value, 96) and string.match(value :: string, "^[%w%._:%-]+$") ~= nil
end

local function finiteVector2(value: unknown): boolean
	return typeof(value) == "Vector2"
		and finiteNumber((value :: Vector2).X)
		and finiteNumber((value :: Vector2).Y)
		and math.abs((value :: Vector2).X) <= 16_384
		and math.abs((value :: Vector2).Y) <= 16_384
end

local function finiteVector3(value: unknown): boolean
	return typeof(value) == "Vector3"
		and finiteNumber((value :: Vector3).X)
		and finiteNumber((value :: Vector3).Y)
		and finiteNumber((value :: Vector3).Z)
		and math.abs((value :: Vector3).X) <= 100_000
		and math.abs((value :: Vector3).Y) <= 100_000
		and math.abs((value :: Vector3).Z) <= 100_000
end

local function denseCount(value: { [any]: unknown }, maximum: number): number?
	if getmetatable(value) ~= nil then
		return nil
	end
	local count = 0
	for key in next, value do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > maximum then
			return nil
		end
		count += 1
	end
	for index = 1, count do
		if rawget(value, index) == nil then
			return nil
		end
	end
	return count
end

local function resolveResponsiveLayout(widthValue: unknown, heightValue: unknown): ResponsiveLayout?
	if
		not finiteNumber(widthValue)
		or not finiteNumber(heightValue)
		or (widthValue :: number) < 240
		or (heightValue :: number) < 240
		or widthValue > 16_384
		or heightValue > 16_384
	then
		return nil
	end
	local width = widthValue :: number
	local height = heightValue :: number
	local mode: "Compact" | "Standard" | "TenFoot" = "Standard"
	if width < 680 or height < 520 then
		mode = "Compact"
	elseif width >= 1_800 and height >= 900 then
		mode = "TenFoot"
	end
	local margin = if mode == "TenFoot" then 32 else 12
	local maximumHud = if mode == "TenFoot" then 1_160 else 900
	local maximumHotbar = if mode == "Compact" then width elseif mode == "TenFoot" then 1_240 else 1_040
	return table.freeze({
		mode = mode,
		hudWidth = math.min(maximumHud, width - margin * 2),
		hotbarWidth = math.min(maximumHotbar, width - margin * 2),
		towerPanelWidth = math.min(if mode == "Compact" then 300 else 340, width - margin * 2),
		touchTarget = if mode == "TenFoot" then 64 else 48,
		textSize = if mode == "TenFoot" then 24 elseif mode == "Compact" then 16 else 18,
	})
end

local function canonicalReady(value: unknown): CanonicalReady?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local ready = value :: { [any]: unknown }
	local enabled = rawget(ready, "enabled")
	local countdown = rawget(ready, "countdownSeconds")
	local status = rawget(ready, "status")
	if type(enabled) ~= "boolean" then
		return nil
	end
	if countdown ~= nil and not safeInteger(countdown, 0, 300) then
		return nil
	end
	if status ~= nil and not safeText(status, 512, true) then
		return nil
	end
	return table.freeze({
		enabled = enabled,
		countdownSeconds = countdown :: number?,
		status = status :: string?,
	})
end

local function canonicalSelection(value: unknown): CanonicalSelection?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local selection = value :: { [any]: unknown }
	local towerId = rawget(selection, "towerId")
	local revision = rawget(selection, "revision")
	local displayName = rawget(selection, "displayName")
	local description = rawget(selection, "description")
	local isOwner = rawget(selection, "isOwner")
	local level = rawget(selection, "level")
	local maxLevel = rawget(selection, "maxLevel")
	local targetMode = rawget(selection, "targetMode")
	local damage = rawget(selection, "damage")
	local range = rawget(selection, "range")
	local cooldownSeconds = rawget(selection, "cooldownSeconds")
	local upgradeCost = rawget(selection, "upgradeCost")
	local sellValue = rawget(selection, "sellValue")
	local canUpgrade = rawget(selection, "canUpgrade")
	local canRetarget = rawget(selection, "canRetarget")
	local canSell = rawget(selection, "canSell")
	if
		not safeId(towerId)
		or not safeInteger(revision, 0, 2 ^ 31 - 1)
		or not safeText(displayName, 40)
		or (description ~= nil and not safeText(description, 512))
		or type(isOwner) ~= "boolean"
		or not safeInteger(level, 1, 100)
		or not safeInteger(maxLevel, level :: number, 100)
		or type(targetMode) ~= "string"
		or rawget(TARGET_MODE_SET, targetMode) ~= true
		or not finiteNumber(damage)
		or (damage :: number) < 0
		or (damage :: number) > 1_000_000
		or not finiteNumber(range)
		or (range :: number) < 0
		or (range :: number) > 10_000
		or not finiteNumber(cooldownSeconds)
		or (cooldownSeconds :: number) < 0.01
		or (cooldownSeconds :: number) > 1_000
		or type(canUpgrade) ~= "boolean"
		or type(canRetarget) ~= "boolean"
		or type(canSell) ~= "boolean"
	then
		return nil
	end
	if upgradeCost ~= nil and not safeInteger(upgradeCost, 0, 2 ^ 31 - 1) then
		return nil
	end
	if sellValue ~= nil and not safeInteger(sellValue, 0, 2 ^ 31 - 1) then
		return nil
	end
	if not isOwner and (canUpgrade or canRetarget or canSell) then
		return nil
	end
	return table.freeze({
		towerId = towerId :: string,
		revision = revision :: number,
		displayName = displayName :: string,
		description = description :: string?,
		isOwner = isOwner :: boolean,
		level = level :: number,
		maxLevel = maxLevel :: number,
		targetMode = targetMode :: TargetMode,
		damage = damage :: number,
		range = range :: number,
		cooldownSeconds = cooldownSeconds :: number,
		upgradeCost = upgradeCost :: number?,
		sellValue = sellValue :: number?,
		canUpgrade = canUpgrade :: boolean,
		canRetarget = canRetarget :: boolean,
		canSell = canSell :: boolean,
	})
end

local function canonicalResult(value: unknown): CanonicalResult?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local result = value :: { [any]: unknown }
	local kind = rawget(result, "kind")
	local summary = rawget(result, "summary")
	local canReplay = rawget(result, "canReplay")
	local status = rawget(result, "status")
	local rewardStatus = rawget(result, "rewardStatus")
	local persistentGoldAwarded = rawget(result, "persistentGoldAwarded")
	local firstClearBonus = rawget(result, "firstClearBonus")
	local battleCashEarned = rawget(result, "battleCashEarned")
	local battleCashSpent = rawget(result, "battleCashSpent")
	local rewardReason = rawget(result, "rewardReason")
	if
		(kind ~= "Victory" and kind ~= "Defeat")
		or not safeText(summary, 1_024, true)
		or type(canReplay) ~= "boolean"
		or (status ~= nil and not safeText(status, 96, true))
		or (rewardStatus ~= "Granted" and rewardStatus ~= "Pending" and rewardStatus ~= "Ineligible" and rewardStatus ~= "Failed")
		or not safeInteger(persistentGoldAwarded, 0, 1_000_000)
		or not safeInteger(firstClearBonus, 0, 1_000_000)
		or not safeInteger(battleCashEarned, 0, 2 ^ 31 - 1)
		or not safeInteger(battleCashSpent, 0, 2 ^ 31 - 1)
		or (rewardReason ~= nil and not safeText(rewardReason, 160, true))
	then
		return nil
	end
	return table.freeze({
		kind = kind :: ResultKind,
		summary = summary :: string,
		canReplay = canReplay :: boolean,
		status = status :: string?,
		rewardStatus = rewardStatus :: RewardStatus,
		persistentGoldAwarded = persistentGoldAwarded :: number,
		firstClearBonus = firstClearBonus :: number,
		battleCashEarned = battleCashEarned :: number,
		battleCashSpent = battleCashSpent :: number,
		rewardReason = rewardReason :: string?,
	})
end

local function canonicalTravel(value: unknown): TravelState?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local travel = value :: { [any]: unknown }
	local returnStatus = rawget(travel, "returnStatus")
	local failureValue = rawget(travel, "failure")
	local canReturn = rawget(travel, "canReturn")
	local rematchState = rawget(travel, "rematchState")
	local rematchStatus = rawget(travel, "rematchStatus")
	local canApprove = rawget(travel, "canApprove")
	local canDecline = rawget(travel, "canDecline")
	if
		(
			returnStatus ~= "Idle"
			and returnStatus ~= "Pending"
			and returnStatus ~= "Teleporting"
			and returnStatus ~= "Failed"
		)
		or (failureValue ~= nil and not safeText(failureValue, 64))
		or type(canReturn) ~= "boolean"
		or (rematchState ~= nil and rematchState ~= "Pending" and rematchState ~= "Starting" and rematchState ~= "Approved" and rematchState ~= "Declined" and rematchState ~= "Failed")
		or (rematchStatus ~= nil and not safeText(rematchStatus, 120, true))
		or type(canApprove) ~= "boolean"
		or type(canDecline) ~= "boolean"
	then
		return nil
	end
	if rematchState == nil and (canApprove or canDecline or rematchStatus ~= nil) then
		return nil
	end
	return table.freeze({
		returnStatus = returnStatus :: any,
		failure = failureValue :: string?,
		canReturn = canReturn :: boolean,
		rematchState = rematchState :: any,
		rematchStatus = rematchStatus :: string?,
		canApprove = canApprove :: boolean,
		canDecline = canDecline :: boolean,
	})
end

local function canonicalPlacement(value: unknown): CanonicalPlacement?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local placement = value :: { [any]: unknown }
	local positionSelected = rawget(placement, "positionSelected")
	local rotationDegrees = rawget(placement, "rotationDegrees")
	local controlsEnabled = rawget(placement, "controlsEnabled")
	if
		type(positionSelected) ~= "boolean"
		or not finiteNumber(rotationDegrees)
		or math.abs(rotationDegrees :: number) > 360
		or type(controlsEnabled) ~= "boolean"
	then
		return nil
	end
	return table.freeze({
		positionSelected = positionSelected :: boolean,
		rotationDegrees = rotationDegrees :: number,
		controlsEnabled = controlsEnabled :: boolean,
	})
end

local function canonicalBoss(value: unknown): BossState?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local boss = value :: { [any]: unknown }
	local runtimeEnemyId = rawget(boss, "runtimeEnemyId")
	local displayName = rawget(boss, "displayName")
	local currentHealth = rawget(boss, "currentHealth")
	local maximumHealth = rawget(boss, "maximumHealth")
	local threatClass = rawget(boss, "threatClass")
	if
		not safeInteger(runtimeEnemyId, 1, 2 ^ 31 - 1)
		or not safeText(displayName, 64)
		or not safeInteger(maximumHealth, 1, 2 ^ 31 - 1)
		or not safeInteger(currentHealth, 0, maximumHealth :: number)
		or (threatClass ~= "MiniBoss" and threatClass ~= "Boss")
	then
		return nil
	end
	return table.freeze({
		runtimeEnemyId = runtimeEnemyId :: number,
		displayName = displayName :: string,
		currentHealth = currentHealth :: number,
		maximumHealth = maximumHealth :: number,
		threatClass = threatClass :: "MiniBoss" | "Boss",
	})
end

local function canonicalSnapshot(value: unknown): CanonicalSnapshot?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local snapshot = value :: { [any]: unknown }
	local matchId = rawget(snapshot, "matchId")
	local revision = rawget(snapshot, "revision")
	local viewerRole = rawget(snapshot, "viewerRole")
	local state = rawget(snapshot, "state")
	local inputFamily = rawget(snapshot, "inputFamily")
	local waveValue = rawget(snapshot, "wave")
	local baseValue = rawget(snapshot, "base")
	local battleCash = rawget(snapshot, "battleCash")
	local hotbarValue = rawget(snapshot, "hotbar")
	local tutorialStep = rawget(snapshot, "tutorialStep")
	if
		not safeId(matchId)
		or not safeInteger(revision, 0, 2 ^ 31 - 1)
		or (viewerRole ~= "Participant" and viewerRole ~= "Spectator")
		or type(state) ~= "string"
		or rawget(MATCH_STATES, state) ~= true
		or type(inputFamily) ~= "string"
		or rawget(INPUT_FAMILIES, inputFamily) ~= true
		or type(waveValue) ~= "table"
		or getmetatable(waveValue) ~= nil
		or type(baseValue) ~= "table"
		or getmetatable(baseValue) ~= nil
		or not safeInteger(battleCash, 0, 2 ^ 31 - 1)
		or type(hotbarValue) ~= "table"
		or (tutorialStep ~= nil and not safeInteger(tutorialStep, 5, 8))
	then
		return nil
	end

	local wave = waveValue :: { [any]: unknown }
	local current = rawget(wave, "current")
	local total = rawget(wave, "total")
	local enemiesRemaining = rawget(wave, "enemiesRemaining")
	local waveStatus = rawget(wave, "status")
	local modeKind = rawget(wave, "modeKind")
	local bossKind = rawget(wave, "bossKind")
	local bossValue = rawget(wave, "boss")
	if modeKind == nil then
		modeKind = "Finite"
	end
	if bossKind == nil then
		bossKind = "None"
	end
	local boss = if bossValue == nil then nil else canonicalBoss(bossValue)
	if
		(modeKind ~= "Finite" and modeKind ~= "Endless")
		or (modeKind == "Finite" and not safeInteger(total, 1, 1_000))
		or (modeKind == "Finite" and not safeInteger(current, 0, total :: number))
		or (modeKind == "Endless" and total ~= nil)
		or (modeKind == "Endless" and not safeInteger(current, 0, 2 ^ 31 - 1))
		or not safeInteger(enemiesRemaining, 0, 100_000)
		or (waveStatus ~= nil and not safeText(waveStatus, 64, true))
		or (bossKind ~= "None" and bossKind ~= "MiniBoss" and bossKind ~= "Boss")
		or (bossValue ~= nil and boss == nil)
	then
		return nil
	end

	local base = baseValue :: { [any]: unknown }
	local health = rawget(base, "health")
	local maxHealth = rawget(base, "maxHealth")
	if not safeInteger(maxHealth, 1, 1_000_000) or not safeInteger(health, 0, maxHealth :: number) then
		return nil
	end

	local hotbarCount = denseCount(hotbarValue :: { [any]: unknown }, HOTBAR_SLOTS)
	if
		hotbarCount == nil
		or (viewerRole == "Participant" and hotbarCount < 1)
		or (viewerRole == "Spectator" and hotbarCount ~= 0)
	then
		return nil
	end
	local hotbar = table.create(hotbarCount) :: { HotbarSlot }
	local selectedCount = 0
	for index = 1, hotbarCount do
		local slotValue = rawget(hotbarValue :: { [any]: unknown }, index)
		if type(slotValue) ~= "table" or getmetatable(slotValue) ~= nil then
			return nil
		end
		local slot = slotValue :: { [any]: unknown }
		local slotIndex = rawget(slot, "slot")
		local displayName = rawget(slot, "displayName")
		local description = rawget(slot, "description")
		local cost = rawget(slot, "cost")
		local available = rawget(slot, "available")
		local selected = rawget(slot, "selected")
		local reason = rawget(slot, "reason")
		if
			slotIndex ~= index
			or not safeText(displayName, 32)
			or (description ~= nil and not safeText(description, 512))
			or not safeInteger(cost, 0, 2 ^ 31 - 1)
			or type(available) ~= "boolean"
			or type(selected) ~= "boolean"
			or (reason ~= nil and not safeText(reason, 64, true))
		then
			return nil
		end
		if selected then
			selectedCount += 1
		end
		hotbar[index] = table.freeze({
			slot = index,
			displayName = displayName :: string,
			description = description :: string?,
			cost = cost :: number,
			available = available :: boolean,
			selected = selected :: boolean,
			reason = reason :: string?,
		})
	end
	if selectedCount > 1 then
		return nil
	end

	local readyValue = rawget(snapshot, "ready")
	local ready = if readyValue == nil then nil else canonicalReady(readyValue)
	if readyValue ~= nil and ready == nil then
		return nil
	end
	if state == "ReadyCheck" and ready == nil then
		ready = table.freeze({ enabled = true, countdownSeconds = nil, status = nil })
	elseif state ~= "ReadyCheck" and ready ~= nil then
		return nil
	end
	if viewerRole == "Spectator" and ready ~= nil then
		return nil
	end

	local selectionValue = rawget(snapshot, "selection")
	local selection = if selectionValue == nil then nil else canonicalSelection(selectionValue)
	if selectionValue ~= nil and selection == nil then
		return nil
	end
	if selection ~= nil and state ~= "PreWave" and state ~= "WaveActive" then
		return nil
	end
	if viewerRole == "Spectator" and selection ~= nil then
		return nil
	end

	local feedbackValue = rawget(snapshot, "feedback")
	local feedback: FeedbackState? = nil
	if feedbackValue ~= nil then
		if type(feedbackValue) ~= "table" or getmetatable(feedbackValue) ~= nil then
			return nil
		end
		local code = rawget(feedbackValue :: { [any]: unknown }, "code")
		if not safeText(code, 48) or string.match(code :: string, "^[A-Z0-9_]+$") == nil then
			return nil
		end
		feedback = table.freeze({ code = code :: string })
	end

	local resultValue = rawget(snapshot, "result")
	local result = if resultValue == nil then nil else canonicalResult(resultValue)
	if resultValue ~= nil and result == nil then
		return nil
	end
	if (state == "Results") ~= (result ~= nil) then
		return nil
	end
	if viewerRole == "Spectator" and result ~= nil and (result.canReplay or result.rewardStatus == "Granted") then
		return nil
	end

	local travelValue = rawget(snapshot, "travel")
	local travel = if travelValue == nil then nil else canonicalTravel(travelValue)
	if travelValue ~= nil and travel == nil then
		return nil
	end
	if viewerRole == "Spectator" and travel ~= nil and (travel.canApprove or travel.canDecline) then
		return nil
	end

	local placementValue = rawget(snapshot, "placement")
	local placement = if placementValue == nil then nil else canonicalPlacement(placementValue)
	if placementValue ~= nil and placement == nil then
		return nil
	end
	if placement ~= nil and ((state ~= "PreWave" and state ~= "WaveActive") or selectedCount ~= 1) then
		return nil
	end
	if viewerRole == "Spectator" and placement ~= nil then
		return nil
	end

	local inputHint = rawget(snapshot, "inputHint")
	local viewport = rawget(snapshot, "viewport")
	local uiScale = rawget(snapshot, "uiScale")
	local reducedMotion = rawget(snapshot, "reducedMotion")
	local lowEffects = rawget(snapshot, "lowEffects")
	local enemyHealthBars = rawget(snapshot, "enemyHealthBars")
	local towerRange = rawget(snapshot, "towerRange")
	if inputHint ~= nil and not safeText(inputHint, 512, true) then
		return nil
	end
	if
		viewport ~= nil
		and (not finiteVector2(viewport) or (viewport :: Vector2).X < 240 or (viewport :: Vector2).Y < 240)
	then
		return nil
	end
	if uiScale ~= nil and (not finiteNumber(uiScale) or (uiScale :: number) < 0.75 or (uiScale :: number) > 1.5) then
		return nil
	end
	if reducedMotion ~= nil and type(reducedMotion) ~= "boolean" then
		return nil
	end
	if lowEffects ~= nil and type(lowEffects) ~= "boolean" then
		return nil
	end
	if enemyHealthBars ~= nil and type(enemyHealthBars) ~= "boolean" then
		return nil
	end
	if towerRange ~= nil and type(towerRange) ~= "boolean" then
		return nil
	end

	return table.freeze({
		matchId = matchId :: string,
		revision = revision :: number,
		viewerRole = viewerRole :: ViewerRole,
		state = state :: MatchState,
		inputFamily = inputFamily :: InputFamily,
		wave = table.freeze({
			current = current :: number,
			total = total :: number?,
			enemiesRemaining = enemiesRemaining :: number,
			status = waveStatus :: string?,
			modeKind = modeKind :: ModeKind,
			bossKind = bossKind :: BossKind,
			boss = boss,
		}),
		base = table.freeze({ health = health :: number, maxHealth = maxHealth :: number }),
		battleCash = battleCash :: number,
		hotbar = table.freeze(hotbar),
		tutorialStep = tutorialStep :: number?,
		ready = ready,
		selection = selection,
		feedback = feedback,
		result = result,
		travel = travel,
		placement = placement,
		inputHint = inputHint :: string?,
		viewport = viewport :: Vector2?,
		uiScale = uiScale :: number?,
		reducedMotion = reducedMotion :: boolean?,
		lowEffects = lowEffects :: boolean?,
		enemyHealthBars = enemyHealthBars :: boolean?,
		towerRange = towerRange :: boolean?,
	})
end

local FEEDBACK_TEXT: { [string]: string } = table.freeze({
	INSUFFICIENT_CASH = "playable_match_view.not_enough_battle_cash_defeat_enemies_or",
	INVALID_POSITION = "playable_match_view.move_the_tower_onto_an_open_placement",
	TOWER_CAP_REACHED = "playable_match_view.tower_limit_reached_sell_a_tower_before",
	NOT_OWNER = "playable_match_view.inspection_only_only_the_owner_can_change",
	STALE_MATCH = "playable_match_view.that_match_ended_wait_for_the_new",
	STALE_TOWER = "playable_match_view.tower_changed_select_it_again_and_retry",
	TOWER_NOT_FOUND = "playable_match_view.tower_no_longer_exists_choose_another_tower",
	MATCH_NOT_ACTIVE = "playable_match_view.tower_actions_unlock_when_the_match_is",
	RATE_LIMITED = "playable_match_view.too_many_requests_wait_a_moment_and",
	REQUEST_PENDING = "playable_match_view.waiting_for_server_confirmation",
	REQUEST_ACCEPTED = "playable_match_view.server_confirmed_the_action",
	REQUEST_REJECTED = "playable_match_view.the_server_rejected_that_action_retry_or",
	SERVER_UNAVAILABLE = "playable_match_view.server_unavailable_wait_a_moment_and_retry",
	POSITION_SELECTED = "playable_match_view.position_selected_confirm_to_spend_battle_cash",
	SPECTATOR_READ_ONLY = "playable_match_view.spectators_are_read_only_and_cannot_affect",
	SPECTATOR_TARGET_UNAVAILABLE = Localization.text(
		"playable_match_view.no_live_spectator_camera_target_is_available"
	),
	TRAVEL_UNAVAILABLE = "playable_match_view.return_or_rematch_is_not_available_yet",
	RETURN_PENDING = "playable_match_view.requesting_a_safe_return_to_the_lobby",
	RETURN_CONFIRMED = "playable_match_view.return_request_confirmed_by_the_server",
	REMATCH_PENDING = "playable_match_view.sending_your_rematch_vote",
	REMATCH_CONFIRMED = "playable_match_view.rematch_vote_confirmed_by_the_server",
	REMATCH_UNAVAILABLE = "playable_match_view.rematch_voting_is_unavailable_or_already_resolved",
})

local function feedbackText(feedback: FeedbackState?): string
	if feedback == nil then
		return ""
	end
	return Localization.text(
		FEEDBACK_TEXT[feedback.code] or "playable_match_view.action_unavailable_review_the_current_match_state"
	)
end

local function defaultHint(snapshot: CanonicalSnapshot): string
	if snapshot.viewerRole == "Spectator" then
		return if snapshot.inputFamily == "Gamepad"
			then Localization.text("playable_match_view.lb_rb_camera_target_return_is_always")
			elseif snapshot.inputFamily == "Touch" then Localization.text(
				"playable_match_view.cycle_camera_targets_or_return"
			)
			else Localization.text("playable_match_view.camera_target_return")
	elseif snapshot.placement ~= nil then
		return Localization.text("playable_match_view.tap_the_map_to_choose_a_position")
	elseif snapshot.state == "ReadyCheck" then
		return if snapshot.inputFamily == "Gamepad"
			then Localization.text("playable_input_map.a_ready")
			elseif snapshot.inputFamily == "Touch" then Localization.text("playable_input_map.tap_ready")
			else Localization.text("playable_input_map.r_enter_ready")
	elseif snapshot.state == "Results" then
		return if snapshot.inputFamily == "Gamepad"
			then Localization.text("playable_input_map.a_play_again")
			elseif snapshot.inputFamily == "Touch" then Localization.text("playable_input_map.tap_play_again")
			else Localization.text("playable_input_map.r_enter_play_again")
	elseif snapshot.selection ~= nil then
		return if snapshot.inputFamily == "Gamepad"
			then Localization.text("playable_match_view.y_upgrade_rb_target_x_sell_b")
			elseif snapshot.inputFamily == "Touch" then Localization.text(
				"playable_match_view.use_tower_controls_or_close"
			)
			else Localization.text("playable_input_map.u_upgrade_t_target_x_sell_q")
	end
	return if snapshot.inputFamily == "Gamepad"
		then Localization.text("playable_match_view.lb_rb_tower_d_pad_down_focus")
		elseif snapshot.inputFamily == "Touch" then Localization.text(
			"playable_match_view.tap_tower_cards_tap_base_to_focus"
		)
		else Localization.text("playable_match_view.1_3_select_tower_f_focus_base")
end

local function makeFrame(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = COLORS.Panel
	frame.Parent = parent
	return frame
end

local function makeLabel(name: string, parent: Instance, applyProductionStyle: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextColor3 = COLORS.Text
	label.RichText = false
	label.AutoLocalize = false
	label.TextWrapped = true
	if applyProductionStyle then
		label.Font = Enum.Font.GothamBold
	end
	label.Parent = parent
	return label
end

local function makeButton(name: string, parent: Instance, applyProductionStyle: boolean): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundColor3 = COLORS.Neutral
	button.BorderSizePixel = 2
	button.BorderColor3 = COLORS.Muted
	button.TextColor3 = COLORS.Text
	button.RichText = false
	button.AutoLocalize = false
	button.TextWrapped = true
	if applyProductionStyle then
		button.Font = Enum.Font.GothamBold
	end
	button.Parent = parent
	return button
end

local function makeWorldPart(name: string, parent: Instance, applyProductionStyle: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	if applyProductionStyle then
		part.Material = Enum.Material.SmoothPlastic
	end
	part.Parent = parent
	return part
end

local function authenticatedTemplateFolder(root: Instance): Folder?
	local matching: Folder? = nil
	for _, child in root:GetChildren() do
		if child.Name == TEMPLATE_FOLDER_NAME then
			if matching ~= nil or not child:IsA("Folder") then
				return nil
			end
			matching = child
		end
	end
	if
		matching == nil
		or matching:GetAttribute("ATDContentContract") ~= CONTENT_CONTRACT
		or matching:GetAttribute("ContentVersion") ~= CONTENT_VERSION
	then
		return nil
	end
	return matching
end

local function safeTemplateModel(
	instance: Instance,
	contentKind: "TowerModel" | "EnemyModel",
	definitionId: string
): boolean
	if
		not instance:IsA("Model")
		or not instance.Archivable
		or instance:GetAttribute("ATDContentContract") ~= CONTENT_CONTRACT
		or instance:GetAttribute("ContentKind") ~= contentKind
		or instance:GetAttribute("DefinitionId") ~= definitionId
	then
		return false
	end
	local primaryPart = instance.PrimaryPart
	if primaryPart == nil or not primaryPart:IsDescendantOf(instance) then
		return false
	end
	local partCount = 0
	for _, descendant in instance:GetDescendants() do
		if not descendant.Archivable or descendant:IsA("LuaSourceContainer") then
			return false
		end
		if descendant:IsA("BasePart") then
			partCount += 1
			if not descendant.Anchored or descendant.CanCollide or descendant.CanTouch or descendant.CanQuery then
				return false
			end
		end
	end
	return partCount > 0
end

local function resolveTemplate(root: Instance, contentKind: "TowerModel" | "EnemyModel", definitionId: string): Model?
	local folder = authenticatedTemplateFolder(root)
	if folder == nil then
		return nil
	end
	local matching: Model? = nil
	for _, child in folder:GetChildren() do
		if child:GetAttribute("DefinitionId") == definitionId and child:GetAttribute("ContentKind") == contentKind then
			if matching ~= nil or not safeTemplateModel(child, contentKind, definitionId) then
				return nil
			end
			matching = child :: Model
		end
	end
	return matching
end

local function primitiveFallback(
	parent: Instance,
	contentKind: "TowerModel" | "EnemyModel",
	applyProductionStyle: boolean
): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = `{contentKind}TestFallback`
	local part = makeWorldPart("Root", model, applyProductionStyle)
	part.Size = if contentKind == "TowerModel" then Vector3.new(2.5, 3.5, 2.5) else Vector3.new(1.8, 1.4, 2.4)
	part.Color = if contentKind == "TowerModel" then COLORS.Selected else COLORS.Good
	model.PrimaryPart = part
	model.Parent = parent
	return model, part
end

local function cloneVisualModel(
	data: ViewData,
	parent: Instance,
	contentKind: "TowerModel" | "EnemyModel",
	definitionId: string
): (Model?, BasePart?, boolean?)
	local template = if data.templateRoot == nil
		then nil
		else resolveTemplate(data.templateRoot, contentKind, definitionId)
	if template ~= nil then
		local clone = template:Clone()
		if not clone:IsA("Model") or clone.PrimaryPart == nil then
			clone:Destroy()
			return nil, nil, nil
		end
		clone.Parent = parent
		return clone, clone.PrimaryPart, false
	end
	if not data.allowPrimitiveFallback then
		return nil, nil, nil
	end
	local model, primaryPart = primitiveFallback(parent, contentKind, data.applyProductionStyle)
	return model, primaryPart, true
end

local function orderedMuzzles(model: Model): { BasePart }
	local indexed = {} :: { [number]: BasePart }
	for _, descendant in model:GetDescendants() do
		local index = descendant:GetAttribute("MuzzleIndex")
		if descendant:IsA("BasePart") and safeInteger(index, 1, MAX_MUZZLES_PER_TOWER) then
			local canonicalIndex = index :: number
			local current = indexed[canonicalIndex]
			if current == nil or descendant.Name < current.Name then
				indexed[canonicalIndex] = descendant
			end
		end
	end
	local muzzles = table.create(MAX_MUZZLES_PER_TOWER) :: { BasePart }
	for index = 1, MAX_MUZZLES_PER_TOWER do
		local muzzle = indexed[index]
		if muzzle ~= nil then
			table.insert(muzzles, muzzle)
		end
	end
	return muzzles
end

local function makeSelectionHighlight(model: Model, applyProductionStyle: boolean): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "SelectionHighlight"
	highlight.Adornee = model
	highlight.Enabled = false
	highlight.FillTransparency = 1
	highlight.OutlineColor = COLORS.Good
	highlight.OutlineTransparency = 0
	if applyProductionStyle then
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	end
	highlight.Parent = model
	return highlight
end

local function makeRangeIndicator(model: Model, applyProductionStyle: boolean): Part
	local indicator = makeWorldPart("RangeIndicator", model, applyProductionStyle)
	indicator.Shape = Enum.PartType.Cylinder
	indicator.Color = COLORS.Effect
	indicator.Transparency = 1
	return indicator
end

local function modelTopOffset(model: Model, primaryPart: BasePart, margin: number): number
	local primaryY = primaryPart.CFrame.Position.Y
	local topY = primaryY + primaryPart.Size.Y * 0.5
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			local cframe = descendant.CFrame
			local size = descendant.Size
			local halfHeight = (
				math.abs(cframe.RightVector.Y) * size.X
				+ math.abs(cframe.UpVector.Y) * size.Y
				+ math.abs(cframe.LookVector.Y) * size.Z
			) * 0.5
			topY = math.max(topY, cframe.Position.Y + halfHeight)
		end
	end
	return math.clamp(topY - primaryY + margin, 0.5, MAX_MODEL_LABEL_OFFSET_STUDS)
end

local function towerLevelColor(level: number): Color3
	if level >= 3 then
		return COLORS.Warning
	elseif level == 2 then
		return COLORS.Good
	end
	return COLORS.Text
end

local function setTowerLevel(record: TowerRecord, level: number)
	record.level = level
	record.levelText.Text = Localization.text("playable_match_view.level", { level = level })
	record.levelText.TextColor3 = towerLevelColor(level)
end

local function makeTowerLevelDisplay(
	model: Model,
	primaryPart: BasePart,
	applyProductionStyle: boolean
): (BillboardGui, TextLabel)
	local display = Instance.new("BillboardGui")
	display.Name = "ATDLevelDisplay"
	display.Adornee = primaryPart
	display.Size = UDim2.fromOffset(78, 22)
	display.StudsOffsetWorldSpace = Vector3.new(0, modelTopOffset(model, primaryPart, 0.55), 0)
	if applyProductionStyle then
		display.AlwaysOnTop = true
		display.LightInfluence = 0
		display.MaxDistance = 180
	end
	display.Parent = model

	local label = makeLabel("Value", display, applyProductionStyle)
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = COLORS.Background
	label.BackgroundTransparency = 0.2
	label.TextScaled = true
	label.TextStrokeColor3 = COLORS.Background
	label.TextStrokeTransparency = 0.15
	Localization.bind(label, "playable_match_view.level_1", "Text")
	label.TextColor3 = towerLevelColor(1)
	return display, label
end

local function makeEnemyHealthDisplay(
	model: Model,
	primaryPart: BasePart,
	applyProductionStyle: boolean
): (BillboardGui, Frame, TextLabel)
	local display = Instance.new("BillboardGui")
	display.Name = "HealthDisplay"
	display.Adornee = primaryPart
	if applyProductionStyle then
		display.AlwaysOnTop = true
		display.LightInfluence = 0
		display.MaxDistance = 220
		display.Size = UDim2.fromOffset(96, 30)
	end
	display.StudsOffsetWorldSpace = Vector3.new(0, modelTopOffset(model, primaryPart, 0.45), 0)
	display.Parent = model

	local bar = makeFrame("Bar", display)
	bar.BackgroundColor3 = COLORS.Background
	bar.BackgroundTransparency = 0.12
	local fill = makeFrame("Fill", bar)
	fill.BackgroundColor3 = COLORS.Good

	local label = makeLabel("Value", display, applyProductionStyle)
	if applyProductionStyle then
		bar.Size = UDim2.new(1, 0, 0, 8)
		bar.Position = UDim2.new(0, 0, 1, -8)
		fill.Size = UDim2.fromScale(1, 1)
		label.Size = UDim2.new(1, 0, 1, -8)
		label.TextScaled = true
		label.TextStrokeColor3 = COLORS.Background
		label.TextStrokeTransparency = 0.2
	end
	return display, fill, label
end

local function manualPivot(model: Model, primaryPart: BasePart, target: CFrame)
	local offsets: { [BasePart]: CFrame } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			offsets[descendant] = primaryPart.CFrame:ToObjectSpace(descendant.CFrame)
		end
	end
	for part, offset in offsets do
		part.CFrame = target * offset
	end
end

local function pivotVisual(data: ViewData, model: Model, primaryPart: BasePart, target: CFrame)
	if data.applyProductionStyle then
		model:PivotTo(target)
	else
		manualPivot(model, primaryPart, target)
	end
end

local function createInstances(
	guiParent: Instance,
	worldParent: Instance,
	applyProductionStyle: boolean
): ViewInstances?
	if guiParent:FindFirstChild(GUI_NAME) ~= nil or worldParent:FindFirstChild(WORLD_FOLDER_NAME) ~= nil then
		return nil
	end
	local instances: ViewInstances? = nil
	local succeeded, creationProblem = pcall(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = GUI_NAME
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 30
		gui.IgnoreGuiInset = false
		if applyProductionStyle then
			gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
			gui.ClipToDeviceSafeArea = true
			gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		end
		gui.Parent = guiParent

		local root = makeFrame("Root", gui)
		root.BackgroundTransparency = 1
		if applyProductionStyle then
			root.Size = UDim2.fromScale(1, 1)
		end

		local uiScale = Instance.new("UIScale")
		uiScale.Name = "AccessibilityScale"
		uiScale.Scale = 1
		uiScale.Parent = root

		local topHud = makeFrame("TopHUD", root)
		local waveLabel = makeLabel("Wave", topHud, applyProductionStyle)
		local enemyLabel = makeLabel("Enemies", topHud, applyProductionStyle)
		local baseButton = makeButton("BaseHealth", topHud, applyProductionStyle)
		local baseFill = makeFrame("HealthFill", baseButton)
		baseFill.BackgroundColor3 = COLORS.Good
		baseFill.ZIndex = baseButton.ZIndex - 1
		local cashLabel = makeLabel("BattleCash", topHud, applyProductionStyle)
		local bossPanel = makeFrame("BossStatus", root)
		bossPanel.BackgroundColor3 = COLORS.Panel
		bossPanel.BackgroundTransparency = 0.04
		bossPanel.Visible = false
		local bossHealth = makeFrame("Health", bossPanel)
		bossHealth.BackgroundColor3 = COLORS.Background
		local bossHealthFill = makeFrame("Fill", bossHealth)
		bossHealthFill.BackgroundColor3 = COLORS.Bad
		local bossLabel = makeLabel("Label", bossPanel, applyProductionStyle)
		local tutorialPanel = makeFrame("TutorialGuidance", root)
		tutorialPanel.BackgroundColor3 = COLORS.Selected
		tutorialPanel.BackgroundTransparency = 0.04
		tutorialPanel.Visible = false
		local tutorialLabel = makeLabel("Label", tutorialPanel, applyProductionStyle)

		local hotbar = makeFrame("TowerHotbar", root)
		local hotbarButtons = table.create(HOTBAR_SLOTS) :: { TextButton }
		for slot = 1, HOTBAR_SLOTS do
			local button = makeButton(`TowerSlot{slot}`, hotbar, applyProductionStyle)
			button.SelectionOrder = 20 + slot
			button.Text = Localization.text("placement_preview_view.value", { slot = slot })
			hotbarButtons[slot] = button
		end
		local hintLabel = makeLabel("InputHint", hotbar, applyProductionStyle)
		local touchPlacementPanel = makeFrame("TouchPlacementPanel", root)
		local touchPlacementStatus = makeLabel("Status", touchPlacementPanel, applyProductionStyle)
		local touchConfirmButton = makeButton("Confirm", touchPlacementPanel, applyProductionStyle)
		Localization.bind(touchConfirmButton, "placement_preview_view.confirm", "Text")
		local touchRotateButton = makeButton("Rotate", touchPlacementPanel, applyProductionStyle)
		Localization.bind(touchRotateButton, "playable_match_view.rotate", "Text")
		local touchCancelButton = makeButton("Cancel", touchPlacementPanel, applyProductionStyle)
		Localization.bind(touchCancelButton, "playable_match_view.cancel", "Text")

		local feedback = makeLabel("ActionFeedback", root, applyProductionStyle)
		feedback.BackgroundTransparency = 0.08
		feedback.BackgroundColor3 = COLORS.Panel
		feedback.Visible = false

		local readyOverlay = makeFrame("ReadyOverlay", root)
		local readyTitle = makeLabel("Title", readyOverlay, applyProductionStyle)
		Localization.bind(readyTitle, "playable_match_view.defend_the_colony", "Text")
		local readyCountdown = makeLabel("Countdown", readyOverlay, applyProductionStyle)
		local readyStatus = makeLabel("Status", readyOverlay, applyProductionStyle)
		local readyHint = makeLabel("InputHint", readyOverlay, applyProductionStyle)
		local readyButton = makeButton("Ready", readyOverlay, applyProductionStyle)
		Localization.bind(readyButton, "playable_match_view.ready", "Text")
		readyButton.SelectionOrder = 1

		local towerPanel = makeFrame("TowerPanel", root)
		local towerTitle = makeLabel("TowerTitle", towerPanel, applyProductionStyle)
		local towerStatus = makeLabel("OwnerState", towerPanel, applyProductionStyle)
		local towerStats = makeLabel("Stats", towerPanel, applyProductionStyle)
		local towerTarget = makeLabel("TargetMode", towerPanel, applyProductionStyle)
		local upgradeButton = makeButton("Upgrade", towerPanel, applyProductionStyle)
		upgradeButton.SelectionOrder = 40
		local targetButton = makeButton("Target", towerPanel, applyProductionStyle)
		targetButton.SelectionOrder = 41
		local sellButton = makeButton("Sell", towerPanel, applyProductionStyle)
		sellButton.SelectionOrder = 42
		local closeButton = makeButton("Close", towerPanel, applyProductionStyle)
		Localization.bind(closeButton, "playable_match_view.close", "Text")
		closeButton.SelectionOrder = 43

		local resultsOverlay = makeFrame("ResultsOverlay", root)
		local resultTitle = makeLabel("ResultTitle", resultsOverlay, applyProductionStyle)
		local resultSummary = makeLabel("Summary", resultsOverlay, applyProductionStyle)
		local resultReward = makeLabel("Reward", resultsOverlay, applyProductionStyle)
		local resultHint = makeLabel("InputHint", resultsOverlay, applyProductionStyle)
		local replayButton = makeButton("Replay", resultsOverlay, applyProductionStyle)
		Localization.bind(replayButton, "playable_match_view.play_again", "Text")
		replayButton.SelectionOrder = 2
		local rematchApproveButton = makeButton("ApproveRematch", resultsOverlay, applyProductionStyle)
		Localization.bind(rematchApproveButton, "playable_match_view.rematch", "Text")
		rematchApproveButton.SelectionOrder = 3
		local rematchDeclineButton = makeButton("DeclineRematch", resultsOverlay, applyProductionStyle)
		Localization.bind(rematchDeclineButton, "playable_match_view.decline", "Text")
		rematchDeclineButton.SelectionOrder = 4

		local spectatorPanel = makeFrame("SpectatorTravelPanel", root)
		local spectatorBanner = makeLabel("Banner", spectatorPanel, applyProductionStyle)
		local spectatorTarget = makeLabel("Target", spectatorPanel, applyProductionStyle)
		local spectatorPreviousButton = makeButton("PreviousTarget", spectatorPanel, applyProductionStyle)
		Localization.bind(spectatorPreviousButton, "playable_match_view.target", "Text")
		spectatorPreviousButton.SelectionOrder = 60
		local spectatorNextButton = makeButton("NextTarget", spectatorPanel, applyProductionStyle)
		Localization.bind(spectatorNextButton, "playable_match_view.target_2", "Text")
		spectatorNextButton.SelectionOrder = 61
		local returnButton = makeButton("ReturnToLobby", spectatorPanel, applyProductionStyle)
		Localization.bind(returnButton, "playable_match_view.return_to_lobby", "Text")
		returnButton.SelectionOrder = 62

		local worldFolder = Instance.new("Folder")
		worldFolder.Name = WORLD_FOLDER_NAME
		worldFolder.Parent = worldParent
		local towerFolder = Instance.new("Folder")
		towerFolder.Name = "Towers"
		towerFolder.Parent = worldFolder
		local enemyFolder = Instance.new("Folder")
		enemyFolder.Name = "Enemies"
		enemyFolder.Parent = worldFolder
		local effectFolder = Instance.new("Folder")
		effectFolder.Name = "AttackEffects"
		effectFolder.Parent = worldFolder

		instances = {
			gui = gui,
			root = root,
			uiScale = uiScale,
			topHud = topHud,
			waveLabel = waveLabel,
			enemyLabel = enemyLabel,
			baseButton = baseButton,
			baseFill = baseFill,
			cashLabel = cashLabel,
			bossPanel = bossPanel,
			bossLabel = bossLabel,
			bossHealth = bossHealth,
			bossHealthFill = bossHealthFill,
			tutorialPanel = tutorialPanel,
			tutorialLabel = tutorialLabel,
			hotbar = hotbar,
			hotbarButtons = hotbarButtons,
			hintLabel = hintLabel,
			feedback = feedback,
			readyOverlay = readyOverlay,
			readyCountdown = readyCountdown,
			readyStatus = readyStatus,
			readyHint = readyHint,
			readyButton = readyButton,
			towerPanel = towerPanel,
			towerTitle = towerTitle,
			towerStatus = towerStatus,
			towerStats = towerStats,
			towerTarget = towerTarget,
			upgradeButton = upgradeButton,
			targetButton = targetButton,
			sellButton = sellButton,
			closeButton = closeButton,
			resultsOverlay = resultsOverlay,
			resultTitle = resultTitle,
			resultSummary = resultSummary,
			resultReward = resultReward,
			resultHint = resultHint,
			replayButton = replayButton,
			rematchApproveButton = rematchApproveButton,
			rematchDeclineButton = rematchDeclineButton,
			spectatorPanel = spectatorPanel,
			spectatorBanner = spectatorBanner,
			spectatorTarget = spectatorTarget,
			spectatorPreviousButton = spectatorPreviousButton,
			spectatorNextButton = spectatorNextButton,
			returnButton = returnButton,
			touchPlacementPanel = touchPlacementPanel,
			touchPlacementStatus = touchPlacementStatus,
			touchConfirmButton = touchConfirmButton,
			touchRotateButton = touchRotateButton,
			touchCancelButton = touchCancelButton,
			worldFolder = worldFolder,
			towerFolder = towerFolder,
			enemyFolder = enemyFolder,
			effectFolder = effectFolder,
		}
	end)
	if not succeeded then
		local _ = creationProblem
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
	return instances
end

local function applyLayout(instances: ViewInstances, layout: ResponsiveLayout)
	local hudHeight = math.max(if layout.mode == "TenFoot" then 92 else 72, layout.touchTarget + 16)
	instances.topHud.AnchorPoint = Vector2.new(0.5, 0)
	instances.topHud.Position = UDim2.new(0.5, 0, 0, 10)
	instances.topHud.Size = UDim2.fromOffset(layout.hudWidth, hudHeight)
	instances.topHud.BackgroundTransparency = 0.08
	for index, item in { instances.waveLabel, instances.enemyLabel, instances.baseButton, instances.cashLabel } do
		item.Position = UDim2.new((index - 1) * 0.25, 6, 0, 8)
		item.Size = UDim2.new(0.25, -12, 1, -16)
		item.TextSize = layout.textSize
	end
	instances.baseFill.AnchorPoint = Vector2.new(0, 1)
	instances.baseFill.Position = UDim2.fromScale(0, 1)
	instances.baseFill.Size = UDim2.fromScale(1, 0.12)
	instances.bossPanel.AnchorPoint = Vector2.new(0.5, 0)
	instances.bossPanel.Position = UDim2.new(0.5, 0, 0, hudHeight + 18)
	instances.bossPanel.Size = UDim2.fromOffset(math.min(layout.hudWidth, 620), 52)
	instances.bossLabel.Position = UDim2.fromOffset(10, 3)
	instances.bossLabel.Size = UDim2.new(1, -20, 0, 27)
	instances.bossLabel.TextSize = layout.textSize - 1
	instances.bossHealth.Position = UDim2.fromOffset(10, 34)
	instances.bossHealth.Size = UDim2.new(1, -20, 0, 10)
	instances.bossHealthFill.Position = UDim2.fromScale(0, 0)
	instances.bossHealthFill.Size = UDim2.fromScale(0, 1)
	instances.tutorialPanel.AnchorPoint = Vector2.new(0.5, 0)
	instances.tutorialPanel.Position = UDim2.new(0.5, 0, 0, hudHeight + 18)
	instances.tutorialPanel.Size = UDim2.fromOffset(math.min(layout.hudWidth, 620), 58)
	instances.tutorialLabel.Position = UDim2.fromOffset(10, 4)
	instances.tutorialLabel.Size = UDim2.new(1, -20, 1, -8)
	instances.tutorialLabel.TextSize = math.max(13, layout.textSize - 2)

	local hotbarHeight = if layout.mode == "Compact" then 170 elseif layout.mode == "TenFoot" then 132 else 112
	instances.hotbar.AnchorPoint = Vector2.new(0.5, 1)
	instances.hotbar.Position = UDim2.new(0.5, 0, 1, -12)
	instances.hotbar.Size = UDim2.fromOffset(layout.hotbarWidth, hotbarHeight)
	instances.hotbar.BackgroundTransparency = 0.08
	local slotGap = 8
	local columns = if layout.mode == "Compact" then 3 else HOTBAR_SLOTS
	local rows = math.ceil(HOTBAR_SLOTS / columns)
	local buttonWidth = (layout.hotbarWidth - 24 - slotGap * (columns - 1)) / columns
	local buttonHeight = math.max(layout.touchTarget, (hotbarHeight - 38 - slotGap * (rows - 1)) / rows)
	for slot, button in instances.hotbarButtons do
		local column = (slot - 1) % columns
		local row = math.floor((slot - 1) / columns)
		button.Position = UDim2.fromOffset(12 + column * (buttonWidth + slotGap), 8 + row * (buttonHeight + slotGap))
		button.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
		button.TextSize = layout.textSize - 1
	end
	instances.hintLabel.Position = UDim2.fromOffset(12, hotbarHeight - 26)
	instances.hintLabel.Size = UDim2.new(1, -24, 0, 22)
	instances.hintLabel.TextSize = math.max(13, layout.textSize - 4)
	instances.touchPlacementPanel.AnchorPoint = Vector2.new(0.5, 1)
	instances.touchPlacementPanel.Position = UDim2.new(0.5, 0, 1, -(hotbarHeight + 22))
	instances.touchPlacementPanel.Size = UDim2.fromOffset(math.min(layout.hotbarWidth, 420), layout.touchTarget + 44)
	instances.touchPlacementPanel.BackgroundTransparency = 0.04
	instances.touchPlacementStatus.Position = UDim2.fromOffset(10, 4)
	instances.touchPlacementStatus.Size = UDim2.new(1, -20, 0, 28)
	instances.touchPlacementStatus.TextSize = math.max(13, layout.textSize - 3)
	local placementButtonWidth = (math.min(layout.hotbarWidth, 420) - 32) / 3
	for index, button in { instances.touchConfirmButton, instances.touchRotateButton, instances.touchCancelButton } do
		button.Position = UDim2.fromOffset(8 + (index - 1) * (placementButtonWidth + 8), 34)
		button.Size = UDim2.fromOffset(placementButtonWidth, layout.touchTarget)
		button.TextSize = math.max(13, layout.textSize - 3)
	end

	instances.feedback.AnchorPoint = Vector2.new(0.5, 0)
	instances.feedback.Position = UDim2.new(0.5, 0, 0, hudHeight + 78)
	instances.feedback.Size = UDim2.fromOffset(math.min(layout.hudWidth, 720), layout.touchTarget)
	instances.feedback.TextSize = layout.textSize - 1

	instances.readyOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
	instances.readyOverlay.Position = UDim2.fromScale(0.5, 0.5)
	instances.readyOverlay.Size =
		UDim2.fromOffset(math.min(440, layout.hudWidth), if layout.mode == "Compact" then 250 else 280)
	instances.readyOverlay.BackgroundTransparency = 0.04
	local readyTitle = instances.readyOverlay:FindFirstChild("Title", true) :: TextLabel
	readyTitle.Position = UDim2.fromOffset(16, 14)
	readyTitle.Size = UDim2.new(1, -32, 0, 42)
	readyTitle.TextSize = layout.textSize + 5
	instances.readyCountdown.Position = UDim2.fromOffset(16, 62)
	instances.readyCountdown.Size = UDim2.new(1, -32, 0, 36)
	instances.readyCountdown.TextSize = layout.textSize + 2
	instances.readyStatus.Position = UDim2.fromOffset(16, 102)
	instances.readyStatus.Size = UDim2.new(1, -32, 0, 42)
	instances.readyStatus.TextSize = layout.textSize - 1
	instances.readyButton.Position = UDim2.new(0, 16, 1, -(layout.touchTarget + 42))
	instances.readyButton.Size = UDim2.new(1, -32, 0, layout.touchTarget + 6)
	instances.readyButton.TextSize = layout.textSize + 1
	instances.readyHint.Position = UDim2.new(0, 16, 1, -30)
	instances.readyHint.Size = UDim2.new(1, -32, 0, 22)
	instances.readyHint.TextSize = math.max(13, layout.textSize - 4)

	instances.towerPanel.AnchorPoint = Vector2.new(1, 0.5)
	instances.towerPanel.Position = UDim2.new(1, -12, 0.5, 0)
	instances.towerPanel.Size = UDim2.fromOffset(layout.towerPanelWidth, if layout.mode == "Compact" then 340 else 370)
	instances.towerPanel.BackgroundTransparency = 0.04
	instances.towerTitle.Position = UDim2.fromOffset(14, 12)
	instances.towerTitle.Size = UDim2.new(1, -28, 0, 34)
	instances.towerTitle.TextSize = layout.textSize + 2
	instances.towerStatus.Position = UDim2.fromOffset(14, 48)
	instances.towerStatus.Size = UDim2.new(1, -28, 0, 32)
	instances.towerStatus.TextSize = layout.textSize - 2
	instances.towerStats.Position = UDim2.fromOffset(14, 82)
	instances.towerStats.Size = UDim2.new(1, -28, 0, 66)
	instances.towerStats.TextSize = layout.textSize - 2
	instances.towerTarget.Position = UDim2.fromOffset(14, 150)
	instances.towerTarget.Size = UDim2.new(1, -28, 0, 32)
	instances.towerTarget.TextSize = layout.textSize - 2
	local controlWidth = (layout.towerPanelWidth - 36) / 2
	local controlHeight = layout.touchTarget
	for index, button in
		{ instances.upgradeButton, instances.targetButton, instances.sellButton, instances.closeButton }
	do
		local column = (index - 1) % 2
		local row = math.floor((index - 1) / 2)
		button.Position = UDim2.fromOffset(12 + column * (controlWidth + 12), 190 + row * (controlHeight + 10))
		button.Size = UDim2.fromOffset(controlWidth, controlHeight)
		button.TextSize = layout.textSize - 2
	end

	instances.resultsOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
	instances.resultsOverlay.Position = UDim2.fromScale(0.5, 0.5)
	instances.resultsOverlay.Size = UDim2.fromOffset(math.min(540, layout.hudWidth), 430)
	instances.resultsOverlay.BackgroundTransparency = 0.03
	instances.resultTitle.Position = UDim2.fromOffset(18, 22)
	instances.resultTitle.Size = UDim2.new(1, -36, 0, 58)
	instances.resultTitle.TextSize = layout.textSize + 10
	instances.resultSummary.Position = UDim2.fromOffset(18, 78)
	instances.resultSummary.Size = UDim2.new(1, -36, 0, 64)
	instances.resultSummary.TextSize = layout.textSize
	instances.resultReward.Position = UDim2.fromOffset(18, 146)
	instances.resultReward.Size = UDim2.new(1, -36, 0, 104)
	instances.resultReward.TextSize = math.max(13, layout.textSize - 2)
	instances.rematchApproveButton.Position = UDim2.fromOffset(18, 260)
	instances.rematchApproveButton.Size = UDim2.new(0.5, -23, 0, layout.touchTarget)
	instances.rematchDeclineButton.Position = UDim2.new(0.5, 5, 0, 260)
	instances.rematchDeclineButton.Size = UDim2.new(0.5, -23, 0, layout.touchTarget)
	instances.replayButton.Position = UDim2.fromOffset(18, 320)
	instances.replayButton.Size = UDim2.new(1, -36, 0, layout.touchTarget)
	instances.replayButton.TextSize = layout.textSize + 1
	instances.resultHint.Position = UDim2.new(0, 18, 1, -42)
	instances.resultHint.Size = UDim2.new(1, -36, 0, 22)
	instances.resultHint.TextSize = math.max(13, layout.textSize - 4)

	instances.spectatorPanel.AnchorPoint = Vector2.new(0.5, 0)
	instances.spectatorPanel.Position = UDim2.new(0.5, 0, 0, hudHeight + 138)
	instances.spectatorPanel.Size = UDim2.fromOffset(math.min(520, layout.hudWidth), 160)
	instances.spectatorBanner.Position = UDim2.fromOffset(12, 8)
	instances.spectatorBanner.Size = UDim2.new(1, -24, 0, 34)
	instances.spectatorBanner.TextSize = layout.textSize
	instances.spectatorTarget.Position = UDim2.fromOffset(12, 42)
	instances.spectatorTarget.Size = UDim2.new(1, -24, 0, 24)
	instances.spectatorTarget.TextSize = math.max(13, layout.textSize - 3)
	instances.spectatorPreviousButton.Position = UDim2.fromOffset(12, 72)
	instances.spectatorPreviousButton.Size = UDim2.new(0.25, -9, 0, layout.touchTarget)
	instances.spectatorNextButton.Position = UDim2.new(0.25, 6, 0, 72)
	instances.spectatorNextButton.Size = UDim2.new(0.25, -9, 0, layout.touchTarget)
	instances.returnButton.Position = UDim2.new(0.5, 6, 0, 72)
	instances.returnButton.Size = UDim2.new(0.5, -18, 0, layout.touchTarget)
end

local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then COLORS.Neutral else COLORS.Muted
end

local function nextTargetMode(current: TargetMode): TargetMode
	for index, mode in TARGET_MODES do
		if mode == current then
			return TARGET_MODES[(index % #TARGET_MODES) + 1]
		end
	end
	return "First"
end

local function focusMode(snapshot: CanonicalSnapshot): string
	if snapshot.result ~= nil then
		return "Results"
	elseif snapshot.ready ~= nil then
		return "Ready"
	elseif snapshot.selection ~= nil then
		return "Tower"
	elseif snapshot.placement ~= nil then
		return "Placement"
	end
	return "Match"
end

local function bestFocus(instances: ViewInstances, snapshot: CanonicalSnapshot): GuiObject?
	if snapshot.result ~= nil and snapshot.travel ~= nil and snapshot.travel.canApprove then
		return instances.rematchApproveButton
	elseif snapshot.result ~= nil and snapshot.result.canReplay then
		return instances.replayButton
	elseif snapshot.result ~= nil and snapshot.travel ~= nil and snapshot.travel.canReturn then
		return instances.returnButton
	elseif snapshot.viewerRole == "Spectator" then
		return instances.spectatorNextButton
	elseif snapshot.ready ~= nil and snapshot.ready.enabled then
		return instances.readyButton
	elseif snapshot.placement ~= nil then
		return if snapshot.placement.positionSelected then instances.touchConfirmButton else instances.touchCancelButton
	elseif snapshot.selection ~= nil then
		if snapshot.selection.canUpgrade then
			return instances.upgradeButton
		elseif snapshot.selection.canRetarget then
			return instances.targetButton
		elseif snapshot.selection.canSell then
			return instances.sellButton
		end
		return instances.closeButton
	end
	for slot, metadata in snapshot.hotbar do
		if metadata.available then
			return instances.hotbarButtons[slot]
		end
	end
	return instances.baseButton
end

local function actionFor(data: ViewData, kind: UiActionKind, slot: number?): UiAction?
	local snapshot = data.current
	if snapshot == nil then
		return nil
	end
	local selection = snapshot.selection
	local placement = snapshot.placement
	if kind == "Return" then
		if snapshot.travel == nil or not snapshot.travel.canReturn then
			return nil
		end
	elseif kind == "RematchApprove" then
		if snapshot.travel == nil or not snapshot.travel.canApprove then
			return nil
		end
	elseif kind == "RematchDecline" then
		if snapshot.travel == nil or not snapshot.travel.canDecline then
			return nil
		end
	elseif kind == "SpectatePrevious" or kind == "SpectateNext" then
		if snapshot.viewerRole ~= "Spectator" then
			return nil
		end
	elseif snapshot.viewerRole == "Spectator" and kind ~= "FocusBase" then
		return nil
	elseif kind == "SelectHotbar" then
		if
			(snapshot.state ~= "PreWave" and snapshot.state ~= "WaveActive")
			or slot == nil
			or snapshot.hotbar[slot] == nil
			or not snapshot.hotbar[slot].available
		then
			return nil
		end
	elseif kind == "FocusBase" then
		if snapshot.state == "Loading" or snapshot.state == "Results" or snapshot.state == "Closing" then
			return nil
		end
	elseif kind == "Ready" then
		if snapshot.ready == nil or not snapshot.ready.enabled then
			return nil
		end
	elseif kind == "Replay" then
		if snapshot.result == nil or not snapshot.result.canReplay then
			return nil
		end
	elseif kind == "Upgrade" then
		if selection == nil or not selection.canUpgrade then
			return nil
		end
	elseif kind == "Retarget" then
		if selection == nil or not selection.canRetarget then
			return nil
		end
	elseif kind == "Sell" then
		if selection == nil or not selection.canSell then
			return nil
		end
	elseif kind == "Confirm" then
		if placement == nil or not placement.controlsEnabled or not placement.positionSelected then
			return nil
		end
	elseif kind == "Rotate" then
		if placement == nil or not placement.controlsEnabled then
			return nil
		end
	elseif kind == "Cancel" and selection == nil and placement == nil then
		return nil
	end
	return table.freeze({
		kind = kind,
		source = snapshot.inputFamily,
		matchId = snapshot.matchId,
		matchRevision = snapshot.revision,
		slot = slot,
		towerId = if selection == nil then nil else selection.towerId,
		towerRevision = if selection == nil then nil else selection.revision,
		targetMode = if kind == "Retarget" and selection ~= nil then nextTargetMode(selection.targetMode) else nil,
	})
end

local function connectButton(data: ViewData, button: TextButton, kind: UiActionKind, slot: number?): boolean
	local function activate()
		if data.cleaned then
			return
		end
		local action = actionFor(data, kind, slot)
		if action ~= nil and pcall(data.callback, action) then
			data.actionCount += 1
		end
	end
	data.activationCallbacks[button] = activate
	local connected, connectionOrError = pcall(data.dependencies.connectActivated, button, activate)
	if not connected or typeof(connectionOrError) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, connectionOrError :: RBXScriptConnection)
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

local function trimEffects(data: ViewData, now: number)
	for index = #data.effects, 1, -1 do
		local effect = data.effects[index]
		if data.reducedMotion or effect.expiresAt <= now then
			table.remove(data.effects, index)
			effect.part:Destroy()
		end
	end
	local maximum = if data.lowEffects then PresentationPolicy.LOW_DETAIL_EFFECTS else MAX_ATTACK_EFFECTS
	while #data.effects > maximum do
		local oldest = table.remove(data.effects, 1)
		oldest.part:Destroy()
	end
end

local function stepEffects(data: ViewData, now: number)
	ProfileScope.call("ATD.Client.Effects", trimEffects, data, now)
end

local function stepAiming(data: ViewData, now: number, deltaSeconds: number)
	for _, record in data.towerRecords do
		local previousYaw = record.aim.yaw
		local yaw = TowerAim.step(record.aim, now, deltaSeconds, data.reducedMotion)
		if math.abs(previousYaw - yaw) > 0.0001 then
			pcall(
				pivotVisual,
				data,
				record.model,
				record.primaryPart,
				CFrame.new(record.position) * CFrame.Angles(0, yaw, 0)
			)
		end
	end
end

local function updatePresentation(data: ViewData, now: number)
	local deltaSeconds = math.max(0, now - data.lastPresentationStep)
	data.lastPresentationStep = now
	data.effectsAdmittedThisFrame = 0
	stepEffects(data, now)
	ProfileScope.call("ATD.Client.Aim", stepAiming, data, now, deltaSeconds)
end

local function stepPresentation(data: ViewData, now: number)
	ProfileScope.call("ATD.Client.Presentation", updatePresentation, data, now)
end

local function currentFocusControls(data: ViewData, snapshot: CanonicalSnapshot?): { GuiObject }
	local scope: Instance? = nil
	if snapshot ~= nil and snapshot.ready ~= nil then
		scope = data.instances.readyOverlay
	elseif snapshot ~= nil and snapshot.selection ~= nil then
		scope = data.instances.towerPanel
	elseif snapshot ~= nil and snapshot.placement ~= nil then
		scope = data.instances.touchPlacementPanel
	elseif snapshot ~= nil and snapshot.result ~= nil then
		scope = data.instances.resultsOverlay
	end
	local controls = FocusNavigation.controls(data.instances.gui, scope)
	if snapshot ~= nil and snapshot.result ~= nil then
		for _, control in FocusNavigation.controls(data.instances.gui, data.instances.spectatorPanel) do
			table.insert(controls, control)
		end
	end
	return controls
end

local function connectAll(data: ViewData): boolean
	for slot, button in data.instances.hotbarButtons do
		if not connectButton(data, button, "SelectHotbar", slot) then
			disconnectAll(data.connections)
			return false
		end
	end
	for _, binding in
		{
			{ data.instances.baseButton, "FocusBase" :: UiActionKind },
			{ data.instances.readyButton, "Ready" :: UiActionKind },
			{ data.instances.upgradeButton, "Upgrade" :: UiActionKind },
			{ data.instances.targetButton, "Retarget" :: UiActionKind },
			{ data.instances.sellButton, "Sell" :: UiActionKind },
			{ data.instances.closeButton, "Cancel" :: UiActionKind },
			{ data.instances.replayButton, "Replay" :: UiActionKind },
			{ data.instances.touchConfirmButton, "Confirm" :: UiActionKind },
			{ data.instances.touchRotateButton, "Rotate" :: UiActionKind },
			{ data.instances.touchCancelButton, "Cancel" :: UiActionKind },
			{ data.instances.returnButton, "Return" :: UiActionKind },
			{ data.instances.rematchApproveButton, "RematchApprove" :: UiActionKind },
			{ data.instances.rematchDeclineButton, "RematchDecline" :: UiActionKind },
			{ data.instances.spectatorPreviousButton, "SpectatePrevious" :: UiActionKind },
			{ data.instances.spectatorNextButton, "SpectateNext" :: UiActionKind },
		}
	do
		if not connectButton(data, binding[1] :: TextButton, binding[2] :: UiActionKind, nil) then
			disconnectAll(data.connections)
			return false
		end
	end
	if #data.connections ~= BUTTON_CONNECTION_COUNT then
		disconnectAll(data.connections)
		return false
	end
	local connected, connectionOrError = pcall(data.dependencies.connectStepped, function()
		if not data.cleaned then
			stepPresentation(data, data.dependencies.now())
		end
	end)
	if not connected or typeof(connectionOrError) ~= "RBXScriptConnection" then
		disconnectAll(data.connections)
		return false
	end
	table.insert(data.connections, connectionOrError :: RBXScriptConnection)
	if data.dependencies.connectInputBegan ~= nil then
		local inputConnected, inputConnection = pcall(data.dependencies.connectInputBegan, function(keyCode, processed)
			if data.cleaned or processed then
				return
			end
			if keyCode == "Tab" then
				data.keyboardNavigation = true
				local selected = if data.dependencies.getSelectedObject == nil
					then nil
					else data.dependencies.getSelectedObject()
				local direction = 1
				pcall(function()
					if
						UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
						or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
					then
						direction = -1
					end
				end)
				local nextControl = FocusNavigation.next(currentFocusControls(data, data.current), selected, direction)
				data.dependencies.selectObject(nextControl)
				pcall(FocusNavigation.reveal, nextControl)
			elseif
				data.keyboardNavigation and (keyCode == "Return" or keyCode == "KeypadEnter" or keyCode == "Space")
			then
				local selected = if data.dependencies.getSelectedObject == nil
					then nil
					else data.dependencies.getSelectedObject()
				if selected ~= nil and table.find(currentFocusControls(data, data.current), selected) ~= nil then
					local callback = data.activationCallbacks[selected]
					if callback ~= nil then
						callback()
					end
				end
			elseif keyCode == "Escape" or keyCode == "ButtonB" then
				local snapshot = data.current
				if
					snapshot ~= nil
					and (snapshot.result ~= nil or snapshot.ready ~= nil or snapshot.viewerRole == "Spectator")
					and data.instances.returnButton.Active
				then
					local callback = data.activationCallbacks[data.instances.returnButton]
					if callback ~= nil then
						callback()
					end
				end
			end
		end)
		if not inputConnected or typeof(inputConnection) ~= "RBXScriptConnection" then
			disconnectAll(data.connections)
			return false
		end
		table.insert(data.connections, inputConnection :: RBXScriptConnection)
	end
	return true
end

local function construct(
	guiParent: Instance,
	worldParent: Instance,
	callback: UiActionCallback,
	dependencies: Dependencies,
	applyProductionStyle: boolean,
	templateRoot: Instance?,
	allowPrimitiveFallback: boolean
): ViewResult
	if typeof(guiParent) ~= "Instance" or typeof(worldParent) ~= "Instance" then
		return failure("INVALID_PARENT")
	end
	if
		type(callback) ~= "function"
		or type(dependencies) ~= "table"
		or type(dependencies.connectActivated) ~= "function"
		or type(dependencies.connectStepped) ~= "function"
		or type(dependencies.now) ~= "function"
		or type(dependencies.selectObject) ~= "function"
	then
		return failure("INVALID_ARGUMENT")
	end
	if guiParent:FindFirstChild(GUI_NAME) ~= nil or worldParent:FindFirstChild(WORLD_FOLDER_NAME) ~= nil then
		return failure("GUI_CONFLICT")
	end
	local instances = createInstances(guiParent, worldParent, applyProductionStyle)
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
		towerRecords = {},
		enemyRecords = {},
		effects = {},
		effectsAdmittedThisFrame = 0,
		lastPresentationStep = dependencies.now(),
		current = nil,
		lastAttackSequence = 0,
		lastFocusMode = nil,
		keyboardNavigation = false,
		activationCallbacks = {},
		focusRestore = nil,
		inputFamily = "Desktop",
		reducedMotion = false,
		lowEffects = false,
		enemyHealthBars = true,
		towerRange = true,
		renderCount = 0,
		actionCount = 0,
		cleaned = false,
		applyProductionStyle = applyProductionStyle,
		templateRoot = templateRoot,
		allowPrimitiveFallback = allowPrimitiveFallback,
	}
	DATA[view] = data
	if not connectAll(data) then
		if dependencies.cleanupInput ~= nil then
			dependencies.cleanupInput()
		end
		instances.gui:Destroy()
		instances.worldFolder:Destroy()
		DATA[view] = nil
		return failure("CONNECTION_FAILED")
	end
	instances.readyOverlay.Visible = false
	instances.towerPanel.Visible = false
	instances.resultsOverlay.Visible = false
	instances.spectatorPanel.Visible = false
	instances.touchPlacementPanel.Visible = false
	instances.feedback.Visible = false
	return ok(view)
end

local TUTORIAL_COPY: { [number]: string } = table.freeze({
	[5] = "playable_match_view.1_of_3_place_a_tower_choose",
	[6] = "playable_match_view.2_of_3_upgrade_a_tower_select",
	[7] = "playable_match_view.3_of_3_finish_the_match_keep",
	[8] = "playable_match_view.match_recorded_use_return_to_lobby_your",
})

local function fitModal(
	panel: Frame,
	labels: { TextLabel },
	buttons: { TextButton },
	maximumHeight: number,
	touchTarget: number
)
	local width = panel.Size.X.Offset
	local body = panel:FindFirstChild("ATDModalBody") :: ScrollingFrame?
	if body == nil then
		body = Instance.new("ScrollingFrame")
		body.Name = "ATDModalBody"
		body.BackgroundTransparency = 1
		body.BorderSizePixel = 0
		body.ScrollBarThickness = 5
		body.ScrollingDirection = Enum.ScrollingDirection.Y
		body.Parent = panel
	end
	for index, label in labels do
		label:SetAttribute("ATDFlowOrder", index)
		label.Parent = body
	end
	local visibleButtons = {}
	for _, button in buttons do
		button.Parent = panel
		if button.Visible then
			table.insert(visibleButtons, button)
		end
	end
	local buttonWidth = (width - 24 - math.max(0, #visibleButtons - 1) * 8) / math.max(1, #visibleButtons)
	local footerHeight = touchTarget
	for _, button in visibleButtons do
		footerHeight = math.max(
			footerHeight,
			TextLayout.measure(button.Text, button.TextSize, buttonWidth, button.Font, TextLayout.scale(button))
		)
	end
	body.Position = UDim2.fromOffset(8, 8)
	body.Size = UDim2.fromOffset(width - 16, math.max(44, maximumHeight - footerHeight - 24))
	TextLayout.reflow(body, width - 16, math.max(44, maximumHeight - footerHeight - 24), touchTarget)
	local bodyHeight = body.Size.Y.Offset
	panel.Size = UDim2.fromOffset(width, bodyHeight + footerHeight + 24)
	for index, button in visibleButtons do
		button.AnchorPoint = Vector2.zero
		button.Position = UDim2.fromOffset(12 + (index - 1) * (buttonWidth + 8), bodyHeight + 16)
		button.Size = UDim2.fromOffset(buttonWidth, footerHeight)
	end
end

local function renderSnapshot(data: ViewData, snapshot: CanonicalSnapshot)
	local instances = data.instances
	Localization.refresh(instances.gui)
	local viewport = snapshot.viewport or Vector2.new(1280, 720)
	if data.applyProductionStyle and instances.root.AbsoluteSize.X >= 240 and instances.root.AbsoluteSize.Y >= 240 then
		viewport = instances.root.AbsoluteSize
	end
	if snapshot.result == nil and instances.returnButton.Parent ~= instances.spectatorPanel then
		instances.returnButton.Parent = instances.spectatorPanel
		instances.spectatorTarget.Parent = instances.spectatorPanel
	end
	local effective = Accessibility.resolve({
		uiScale = snapshot.uiScale,
		reducedMotionEnabled = snapshot.reducedMotion,
		lowDetailEnabled = snapshot.lowEffects,
	}, Accessibility.readPreferences())
	local uiScale = effective.uiScale
	local baseLayout = resolveResponsiveLayout(viewport.X / uiScale, viewport.Y / uiScale)
	local layout = if baseLayout == nil then nil else table.clone(baseLayout)
	if layout == nil then
		error("invalid responsive layout", 0)
	end
	layout.textSize = math.max(16, math.floor(layout.textSize * effective.textScale + 0.5))
	layout.touchTarget = math.max(layout.touchTarget, math.ceil(44 / uiScale))
	instances.gui:SetAttribute("ATDReducedMotion", effective.reducedMotion)
	instances.root.Size = UDim2.fromScale(1 / uiScale, 1 / uiScale)
	if data.applyProductionStyle then
		applyLayout(instances, layout)
	end
	instances.uiScale.Scale = uiScale
	for _, panel in
		{
			instances.topHud,
			instances.hotbar,
			instances.readyOverlay,
			instances.towerPanel,
			instances.resultsOverlay,
			instances.spectatorPanel,
			instances.bossPanel,
			instances.touchPlacementPanel,
			instances.tutorialPanel,
			instances.feedback,
		}
	do
		panel.BackgroundTransparency = effective.transparency
	end

	if snapshot.state == "Loading" then
		Localization.bind(instances.waveLabel, "playable_match_view.match_loading", "Text")
		Localization.bind(instances.enemyLabel, "playable_match_view.enemies", "Text")
		Localization.bind(instances.baseButton, "playable_match_view.base", "Text")
		Localization.bind(instances.cashLabel, "playable_match_view.battle_cash", "Text")
	elseif layout.mode == "Compact" then
		instances.waveLabel.Text = if snapshot.wave.modeKind == "Endless"
			then Localization.text("match.hud.compact_endless", { current = snapshot.wave.current })
			else Localization.text(
				"match.hud.compact_wave",
				{ current = snapshot.wave.current, total = snapshot.wave.total }
			)
		instances.enemyLabel.Text =
			Localization.text("match.hud.compact_enemies", { count = snapshot.wave.enemiesRemaining })
		instances.baseButton.Text = Localization.text(
			"match.hud.compact_base",
			{ health = snapshot.base.health, maximum = snapshot.base.maxHealth }
		)
		instances.cashLabel.Text = Localization.text("match.hud.compact_cash", { amount = snapshot.battleCash })
	elseif snapshot.wave.modeKind == "Endless" then
		instances.waveLabel.Text =
			Localization.text("playable_match_view.wave_endless", { current = snapshot.wave.current })
		instances.enemyLabel.Text =
			Localization.text("playable_match_view.enemies_2", { enemiesRemaining = snapshot.wave.enemiesRemaining })
		instances.baseButton.Text = Localization.text(
			"playable_match_view.base_2",
			{ health = snapshot.base.health, maxHealth = snapshot.base.maxHealth }
		)
		instances.cashLabel.Text =
			Localization.text("playable_match_view.battle_cash_2", { battleCash = snapshot.battleCash })
	else
		instances.waveLabel.Text = Localization.text(
			"playable_match_view.wave",
			{ current = snapshot.wave.current, total = snapshot.wave.total }
		)
		instances.enemyLabel.Text =
			Localization.text("playable_match_view.enemies_2", { enemiesRemaining = snapshot.wave.enemiesRemaining })
		instances.baseButton.Text = Localization.text(
			"playable_match_view.base_2",
			{ health = snapshot.base.health, maxHealth = snapshot.base.maxHealth }
		)
		instances.cashLabel.Text =
			Localization.text("playable_match_view.battle_cash_2", { battleCash = snapshot.battleCash })
	end
	local bossKind = snapshot.wave.bossKind or "None"
	local boss = snapshot.wave.boss
	local presentedBossKind = if boss == nil then bossKind else boss.threatClass
	instances.bossPanel.Visible = presentedBossKind ~= "None"
		and snapshot.state ~= "Loading"
		and snapshot.state ~= "Results"
	instances.bossPanel.BackgroundColor3 = if effective.reducedMotion or snapshot.lowEffects == true
		then COLORS.Panel
		else COLORS.Neutral
	instances.bossLabel.TextColor3 = if presentedBossKind == "Boss" then COLORS.Bad else COLORS.Warning
	if boss == nil then
		instances.bossLabel.Text = if bossKind == "Boss"
			then Localization.text("playable_match_view.boss_wave_major_threat_incoming")
			elseif bossKind == "MiniBoss" then Localization.text(
				"playable_match_view.miniboss_wave_durable_threat_incoming"
			)
			else ""
		instances.bossHealth.Visible = false
		instances.bossHealthFill.Size = UDim2.fromScale(0, 1)
	else
		instances.bossLabel.Text = Localization.text("playable_match_view.hp", {
			threatClass = string.upper(Localization.enum("state", boss.threatClass)),
			displayName = string.upper(boss.displayName),
			currentHealth = boss.currentHealth,
			maximumHealth = boss.maximumHealth,
		})
		instances.bossHealth.Visible = true
		instances.bossHealthFill.Size = UDim2.fromScale(boss.currentHealth / boss.maximumHealth, 1)
	end
	local tutorialText = if snapshot.tutorialStep == nil then nil else TUTORIAL_COPY[snapshot.tutorialStep]
	instances.tutorialPanel.Visible = tutorialText ~= nil
	instances.tutorialLabel.Text = if tutorialText == nil then "" else Localization.text(tutorialText)
	local noticeY = instances.topHud.Position.Y.Offset + instances.topHud.Size.Y.Offset + 8
	instances.bossPanel.Position = UDim2.new(0.5, 0, 0, noticeY)
	if instances.bossPanel.Visible then
		noticeY += instances.bossPanel.Size.Y.Offset + 8
	end
	instances.tutorialPanel.Position = UDim2.new(0.5, 0, 0, noticeY)
	if instances.tutorialPanel.Visible then
		noticeY += instances.tutorialPanel.Size.Y.Offset + 8
	end
	instances.feedback.Position = UDim2.new(0.5, 0, 0, noticeY)
	local healthRatio = snapshot.base.health / snapshot.base.maxHealth
	if data.applyProductionStyle then
		instances.baseFill.Size =
			UDim2.new(healthRatio, 0, instances.baseFill.Size.Y.Scale, instances.baseFill.Size.Y.Offset)
	end
	instances.baseFill.BackgroundColor3 = if healthRatio <= 0.25
		then COLORS.Bad
		elseif healthRatio <= 0.5 then COLORS.Warning
		else COLORS.Good
	setButtonEnabled(instances.baseButton, snapshot.state ~= "Loading" and snapshot.state ~= "Closing")

	for slot, button in instances.hotbarButtons do
		local visible = snapshot.hotbar[slot] ~= nil
		button.Visible = visible
		if not visible then
			setButtonEnabled(button, false)
		end
	end
	instances.hotbar.Visible = snapshot.viewerRole == "Participant" and snapshot.ready == nil and snapshot.result == nil
	instances.topHud.Visible = snapshot.ready == nil and snapshot.result == nil
	for slot, metadata in snapshot.hotbar do
		local button = instances.hotbarButtons[slot]
		local availabilityText = Localization.enum(
			"availability",
			if metadata.available then "AVAILABLE" else (metadata.reason or "UNAVAILABLE")
		)
		button.Text = if metadata.available
				or metadata.reason == nil
				or metadata.reason == "WAITING"
			then Localization.text(
				if layout.mode == "Compact" then "match.hotbar.compact_card" else "match.hotbar.card",
				{ slot = slot, displayName = metadata.displayName, cost = metadata.cost }
			)
			else Localization.text(
				if layout.mode == "Compact" then "match.hotbar.compact_unavailable" else "playable_match_view.value",
				{
					slot = slot,
					displayName = metadata.displayName,
					cost = metadata.cost,
					availabilityText = availabilityText,
				}
			)
		button.BorderColor3 = if metadata.selected then COLORS.Good else COLORS.Muted
		button.BackgroundColor3 = if metadata.selected then COLORS.Selected else COLORS.Neutral
		setButtonEnabled(button, metadata.available and (snapshot.state == "PreWave" or snapshot.state == "WaveActive"))
	end
	local hint = snapshot.inputHint or defaultHint(snapshot)
	local selectedDescription: string? = nil
	local selectedName = ""
	for _, metadata in snapshot.hotbar do
		if metadata.selected and metadata.description ~= nil then
			selectedDescription = metadata.description
			selectedName = metadata.displayName
			break
		end
	end
	instances.hintLabel.Text = selectedDescription or hint
	local placement = snapshot.placement
	instances.touchPlacementPanel.Visible = placement ~= nil
	if placement ~= nil then
		instances.touchPlacementStatus.Text = if snapshot.inputFamily == "Touch" and not placement.positionSelected
			then Localization.text("match.placement.choose", { tower = selectedName })
			else Localization.text(
				if snapshot.inputFamily == "Touch"
					then "match.placement.ready"
					elseif snapshot.inputFamily == "Gamepad" then "match.placement.gamepad"
					else "match.placement.keyboard",
				{ tower = selectedName, rotation = math.floor(placement.rotationDegrees + 0.5) }
			)
		setButtonEnabled(instances.touchConfirmButton, placement.controlsEnabled and placement.positionSelected)
		setButtonEnabled(instances.touchRotateButton, placement.controlsEnabled)
		setButtonEnabled(instances.touchCancelButton, placement.controlsEnabled)
	else
		instances.touchPlacementStatus.Text = ""
		setButtonEnabled(instances.touchConfirmButton, false)
		setButtonEnabled(instances.touchRotateButton, false)
		setButtonEnabled(instances.touchCancelButton, false)
	end

	local currentFeedback = feedbackText(snapshot.feedback)
	instances.feedback.Text = currentFeedback
	instances.feedback.Visible = currentFeedback ~= ""
	instances.feedback.TextColor3 = if snapshot.feedback ~= nil
			and snapshot.feedback.code == "REQUEST_ACCEPTED"
		then COLORS.Good
		elseif
			snapshot.feedback ~= nil
			and (snapshot.feedback.code == "REQUEST_PENDING" or snapshot.feedback.code == "RATE_LIMITED")
		then COLORS.Warning
		else COLORS.Text

	local ready = snapshot.ready
	instances.readyOverlay.Visible = ready ~= nil
	if ready ~= nil then
		instances.readyCountdown.Text = if ready.countdownSeconds == nil
			then Localization.text("playable_match_view.ready_check")
			else Localization.text(
				"playable_match_view.starting_in_s",
				{ countdownSeconds = ready.countdownSeconds }
			)
		instances.readyStatus.Text = ready.status
			or Localization.text("playable_match_view.ready_up_when_your_defenses_are_planned")
		instances.readyHint.Text = hint
		setButtonEnabled(instances.readyButton, ready.enabled)
	end

	local selection = snapshot.selection
	instances.towerPanel.Visible = selection ~= nil
	if selection ~= nil then
		instances.towerTitle.Text = Localization.text(
			"playable_match_view.level_2",
			{ displayName = selection.displayName, level = selection.level, maxLevel = selection.maxLevel }
		)
		instances.towerStatus.Text = if selection.isOwner
			then Localization.text("playable_match_view.your_tower_controls_available")
			else Localization.text("playable_match_view.inspection_only_owned_by_another_player")
		instances.towerStatus.TextColor3 = if selection.isOwner then COLORS.Good else COLORS.Warning
		local roleDescription = selection.description or ""
		instances.towerStats.Text = Localization.text("match.tower.stats", {
			description = roleDescription,
			damage = selection.damage,
			range = selection.range,
			cooldown = selection.cooldownSeconds,
		})
		instances.towerTarget.Text = Localization.text(
			"playable_match_view.target_3",
			{ targetMode = string.upper(Localization.enum("target", selection.targetMode)) }
		)
		instances.upgradeButton.Text = if selection.upgradeCost == nil
			then Localization.text("playable_match_view.max_level")
			else Localization.text("playable_match_view.upgrade", { upgradeCost = selection.upgradeCost })
		instances.targetButton.Text = Localization.text(
			"playable_match_view.target_4",
			{ targetMode = Localization.enum("target", nextTargetMode(selection.targetMode)) }
		)
		instances.sellButton.Text = if selection.sellValue == nil
			then Localization.text("playable_match_view.sell")
			else Localization.text("playable_match_view.sell_2", { sellValue = selection.sellValue })
		setButtonEnabled(instances.upgradeButton, selection.canUpgrade)
		setButtonEnabled(instances.targetButton, selection.canRetarget)
		setButtonEnabled(instances.sellButton, selection.canSell)
		setButtonEnabled(instances.closeButton, true)
	end

	local result = snapshot.result
	instances.resultsOverlay.Visible = result ~= nil
	if result ~= nil then
		instances.resultTitle.Text = if result.kind == "Victory"
			then Localization.text("playable_match_view.victory")
			else Localization.text("playable_match_view.defeat")
		instances.resultTitle.TextColor3 = if result.kind == "Victory" then COLORS.Good else COLORS.Bad
		instances.resultSummary.Text = result.summary
		local rewardPrefix = if result.rewardStatus == "Granted"
			then Localization.text("playable_match_view.reward_granted")
			elseif result.rewardStatus == "Pending" then Localization.text("playable_match_view.reward_pending")
			elseif result.rewardStatus == "Failed" then Localization.text("playable_match_view.reward_failed")
			else Localization.text("playable_match_view.reward_ineligible")
		instances.resultReward.Text =
			Localization.text("playable_match_view.persistent_gold_first_clear_match_local_battle", {
				rewardPrefix = rewardPrefix,
				persistentGoldAwarded = result.persistentGoldAwarded,
				firstClearBonus = result.firstClearBonus,
				battleCashEarned = result.battleCashEarned,
				battleCashSpent = result.battleCashSpent,
				rewardReason = if result.rewardReason == nil then "" else `\n{result.rewardReason}`,
			})
		instances.resultReward.TextColor3 = if result.rewardStatus == "Granted"
			then COLORS.Good
			elseif result.rewardStatus == "Pending" then COLORS.Warning
			elseif result.rewardStatus == "Failed" then COLORS.Bad
			else COLORS.Muted
		instances.resultHint.Text = result.status or hint
		setButtonEnabled(instances.replayButton, result.canReplay)
	else
		instances.resultTitle.Text = ""
		instances.resultSummary.Text = ""
		instances.resultReward.Text = ""
		instances.resultHint.Text = ""
		setButtonEnabled(instances.replayButton, false)
	end

	local travel = snapshot.travel
	instances.spectatorPanel.Visible = snapshot.viewerRole == "Spectator" or (result ~= nil and travel ~= nil)
	instances.spectatorBanner.Text = if snapshot.viewerRole == "Spectator"
		then Localization.text("playable_match_view.spectator_read_only_zero_participation_credit")
		else Localization.text("playable_match_view.return_rematch")
	instances.spectatorBanner.TextColor3 = if snapshot.viewerRole == "Spectator" then COLORS.Warning else COLORS.Text
	instances.spectatorTarget.Text = if travel == nil
		then Localization.text("playable_match_view.waiting_for_the_server_owned_travel_state")
		elseif travel.failure ~= nil then Localization.text("match.travel.failure")
		elseif snapshot.viewerRole == "Spectator" then Localization.text(
			"playable_match_view.camera_targets_return",
			{ returnStatus = string.upper(Localization.enum("state", travel.returnStatus)) }
		)
		else Localization.text("playable_match_view.return", {
			returnStatus = Localization.enum("state", travel.returnStatus),
			uNAVAILABLE = travel.rematchStatus or Localization.text("common.unavailable"),
		})
	instances.spectatorPreviousButton.Visible = snapshot.viewerRole == "Spectator"
	instances.spectatorNextButton.Visible = snapshot.viewerRole == "Spectator"
	instances.returnButton.Visible = travel ~= nil
	setButtonEnabled(instances.spectatorPreviousButton, snapshot.viewerRole == "Spectator")
	setButtonEnabled(instances.spectatorNextButton, snapshot.viewerRole == "Spectator")
	setButtonEnabled(instances.returnButton, travel ~= nil and travel.canReturn)
	instances.rematchApproveButton.Visible = result ~= nil and travel ~= nil and travel.rematchState ~= nil
	instances.rematchDeclineButton.Visible = result ~= nil and travel ~= nil and travel.rematchState ~= nil
	setButtonEnabled(instances.rematchApproveButton, travel ~= nil and travel.canApprove)
	setButtonEnabled(instances.rematchDeclineButton, travel ~= nil and travel.canDecline)
	if selection ~= nil then
		local towerRecord = data.towerRecords[selection.towerId]
		if towerRecord ~= nil and towerRecord.level ~= selection.level then
			setTowerLevel(towerRecord, selection.level)
		end
	end

	if data.applyProductionStyle then
		local maximumHeight = viewport.Y / uiScale - 32
		for _, object in instances.gui:GetDescendants() do
			if object:IsA("TextLabel") or object:IsA("TextButton") then
				object.TextSize = math.max(16, object.TextSize)
			end
		end
		local hudRowHeight = layout.touchTarget
		local hudColumnWidth = layout.hudWidth * 0.25 - 12
		for _, label in { instances.waveLabel, instances.enemyLabel, instances.baseButton, instances.cashLabel } do
			-- The column's six-pixel margins are already outside the label.
			-- Cancel TextLayout's default inner inset: this label has no UIPadding.
			hudRowHeight = math.max(
				hudRowHeight,
				TextLayout.measure(label.Text, label.TextSize, hudColumnWidth + 16, label.Font, TextLayout.scale(label))
			)
		end
		instances.topHud.Size = UDim2.fromOffset(layout.hudWidth, hudRowHeight + 16)
		for _, panel in
			{
				instances.towerPanel,
				instances.spectatorPanel,
			}
		do
			if panel.Visible then
				TextLayout.reflow(panel, panel.Size.X.Offset, maximumHeight, layout.touchTarget)
			end
		end
		if instances.readyOverlay.Visible then
			local title = instances.readyOverlay:FindFirstChild("Title", true) :: TextLabel
			fitModal(
				instances.readyOverlay,
				{ title, instances.readyCountdown, instances.readyStatus, instances.readyHint },
				{ instances.readyButton },
				maximumHeight,
				layout.touchTarget
			)
		end
		if instances.resultsOverlay.Visible then
			fitModal(instances.resultsOverlay, {
				instances.resultTitle,
				instances.resultSummary,
				instances.resultReward,
				instances.resultHint,
				instances.spectatorTarget,
			}, {
				instances.replayButton,
				instances.rematchApproveButton,
				instances.rematchDeclineButton,
				instances.returnButton,
			}, maximumHeight, layout.touchTarget)
			instances.spectatorPanel.Visible = false
		end
		local cardScroll = instances.hotbar:FindFirstChild("ATDHotbarCards") :: ScrollingFrame?
		if cardScroll == nil then
			cardScroll = Instance.new("ScrollingFrame")
			cardScroll.Name = "ATDHotbarCards"
			cardScroll.BackgroundTransparency = 1
			cardScroll.BorderSizePixel = 0
			cardScroll.ScrollBarThickness = 4
			cardScroll.ScrollingDirection = Enum.ScrollingDirection.X
			cardScroll.Parent = instances.hotbar
			for _, button in instances.hotbarButtons do
				button.Parent = cardScroll
			end
		end
		local optionCount = math.max(1, #snapshot.hotbar)
		local fittedCardWidth = (layout.hotbarWidth - 16 - (optionCount - 1) * 8) / optionCount
		local cardWidth = math.max(
			180,
			layout.textSize * 10,
			if layout.mode == "Compact" then math.max(fittedCardWidth, 280 / uiScale) else 0
		)
		local cardHeight = layout.touchTarget
		for _, button in instances.hotbarButtons do
			if button.Visible then
				cardHeight = math.max(
					cardHeight,
					TextLayout.measure(button.Text, button.TextSize, cardWidth, button.Font, TextLayout.scale(button))
				)
			end
		end
		for index, button in instances.hotbarButtons do
			button.Position = UDim2.fromOffset((index - 1) * (cardWidth + 8), 0)
			button.Size = UDim2.fromOffset(cardWidth, cardHeight)
		end
		local showHint = layout.mode ~= "Compact"
		local hintHeight = if showHint
			then TextLayout.measure(
				instances.hintLabel.Text,
				instances.hintLabel.TextSize,
				layout.hotbarWidth - 24,
				instances.hintLabel.Font,
				TextLayout.scale(instances.hintLabel)
			)
			else 0
		cardScroll.Position = UDim2.fromOffset(8, 8)
		cardScroll.Size = UDim2.new(1, -16, 0, cardHeight + 6)
		cardScroll.CanvasSize =
			UDim2.fromOffset(#snapshot.hotbar * cardWidth + math.max(0, #snapshot.hotbar - 1) * 8, cardHeight)
		instances.hintLabel.Visible = showHint
		instances.hintLabel.Position = UDim2.fromOffset(12, cardHeight + 16)
		instances.hintLabel.Size = UDim2.new(1, -24, 0, hintHeight)
		instances.hotbar.Size = UDim2.fromOffset(layout.hotbarWidth, cardHeight + hintHeight + 20)
		if instances.touchPlacementPanel.Visible then
			local panel = instances.touchPlacementPanel
			local width = panel.Size.X.Offset
			local buttonWidth = (width - 32) / 3
			local buttonHeight = layout.touchTarget
			for _, button in { instances.touchConfirmButton, instances.touchRotateButton, instances.touchCancelButton } do
				buttonHeight = math.max(
					buttonHeight,
					TextLayout.measure(button.Text, button.TextSize, buttonWidth, button.Font, TextLayout.scale(button))
				)
			end
			local contentHeight = TextLayout.measure(
				instances.touchPlacementStatus.Text,
				instances.touchPlacementStatus.TextSize,
				width - 20,
				instances.touchPlacementStatus.Font,
				TextLayout.scale(instances.touchPlacementStatus)
			)
			local statusHeight =
				math.max(32, math.min(contentHeight, math.max(120, maximumHeight * 0.46) - buttonHeight - 24))
			local statusScroll = panel:FindFirstChild("InstructionScroll") :: ScrollingFrame?
			if statusScroll == nil then
				statusScroll = Instance.new("ScrollingFrame")
				statusScroll.Name = "InstructionScroll"
				statusScroll.BackgroundTransparency = 1
				statusScroll.BorderSizePixel = 0
				statusScroll.ScrollBarThickness = 4
				statusScroll.ScrollingDirection = Enum.ScrollingDirection.Y
				statusScroll.Parent = panel
				instances.touchPlacementStatus.Parent = statusScroll
			end
			statusScroll.Position = UDim2.fromOffset(10, 8)
			statusScroll.Size = UDim2.new(1, -20, 0, statusHeight)
			statusScroll.CanvasSize = UDim2.fromOffset(0, contentHeight)
			instances.touchPlacementStatus.Position = UDim2.fromOffset(0, 0)
			instances.touchPlacementStatus.Size = UDim2.new(1, 0, 0, contentHeight)
			instances.touchPlacementStatus.TextYAlignment = Enum.TextYAlignment.Top
			panel.Size = UDim2.fromOffset(width, statusHeight + buttonHeight + 24)
			for index, button in
				{ instances.touchConfirmButton, instances.touchRotateButton, instances.touchCancelButton }
			do
				button.Position = UDim2.fromOffset(8 + (index - 1) * (buttonWidth + 8), statusHeight + 16)
				button.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
			end
		end
		if layout.mode == "Compact" and snapshot.placement ~= nil then
			instances.hotbar.Visible = false
			instances.tutorialPanel.Visible = false
			instances.touchPlacementPanel.Position = UDim2.new(0.5, 0, 1, -12)
		else
			instances.touchPlacementPanel.Position = UDim2.new(0.5, 0, 1, -(instances.hotbar.Size.Y.Offset + 22))
		end
		-- Place notices after final HUD/card measurements. Their text may scroll,
		-- while the HUD, action cards, and boss health retain their fixed regions.
		local noticeTop = if instances.topHud.Visible
			then instances.topHud.Position.Y.Offset + instances.topHud.Size.Y.Offset + 8
			else 16
		local noticeBottom = viewport.Y / uiScale - 16
		if instances.hotbar.Visible then
			noticeBottom = math.min(noticeBottom, viewport.Y / uiScale - instances.hotbar.Size.Y.Offset - 20)
		end
		if instances.touchPlacementPanel.Visible then
			noticeBottom = math.min(
				noticeBottom,
				viewport.Y / uiScale
					+ instances.touchPlacementPanel.Position.Y.Offset
					- instances.touchPlacementPanel.Size.Y.Offset
					- 8
			)
		end
		local remainingHeight = math.max(44, noticeBottom - noticeTop)
		local leftWidth = layout.hudWidth
		if instances.bossPanel.Visible then
			local bossWidth = if layout.mode == "Compact"
				then math.min(280, layout.hudWidth * 0.44)
				else math.min(620, layout.hudWidth)
			local bossBody = instances.bossPanel:FindFirstChild("ATDBossText") :: ScrollingFrame?
			if bossBody == nil then
				bossBody = Instance.new("ScrollingFrame")
				bossBody.Name = "ATDBossText"
				bossBody.BackgroundTransparency = 1
				bossBody.BorderSizePixel = 0
				bossBody.ScrollBarThickness = 3
				bossBody.ScrollingDirection = Enum.ScrollingDirection.Y
				bossBody.Parent = instances.bossPanel
				instances.bossLabel.Parent = bossBody
			end
			local textHeight = TextLayout.measure(
				instances.bossLabel.Text,
				instances.bossLabel.TextSize,
				bossWidth - 20,
				instances.bossLabel.Font,
				TextLayout.scale(instances.bossLabel)
			)
			local bodyHeight = math.min(textHeight, math.max(26, remainingHeight - 18))
			bossBody.Position = UDim2.fromOffset(10, 3)
			bossBody.Size = UDim2.fromOffset(bossWidth - 20, bodyHeight)
			bossBody.CanvasSize = UDim2.fromOffset(0, textHeight)
			instances.bossLabel.AnchorPoint = Vector2.zero
			instances.bossLabel.Position = UDim2.fromOffset(0, 0)
			instances.bossLabel.Size = UDim2.new(1, 0, 0, textHeight)
			instances.bossLabel.TextYAlignment = Enum.TextYAlignment.Top
			instances.bossHealth.Position = UDim2.fromOffset(10, bodyHeight + 6)
			instances.bossPanel.Size = UDim2.fromOffset(bossWidth, bodyHeight + 18)
			if layout.mode == "Compact" then
				instances.bossPanel.AnchorPoint = Vector2.new(1, 0)
				instances.bossPanel.Position = UDim2.new(1, -12, 0, noticeTop)
				leftWidth = layout.hudWidth - bossWidth - 8
			else
				instances.bossPanel.Position = UDim2.new(0.5, 0, 0, noticeTop)
				noticeTop += instances.bossPanel.Size.Y.Offset + 8
				remainingHeight = math.max(44, noticeBottom - noticeTop)
			end
		end
		local notices = instances.root:FindFirstChild("ATDMatchNotices") :: ScrollingFrame?
		if notices == nil then
			notices = Instance.new("ScrollingFrame")
			notices.Name = "ATDMatchNotices"
			notices.BackgroundTransparency = 1
			notices.BorderSizePixel = 0
			notices.ScrollBarThickness = 4
			notices.ScrollingDirection = Enum.ScrollingDirection.Y
			notices.Parent = instances.root
			instances.feedback.Parent = notices
			instances.tutorialPanel.Parent = notices
		end
		notices.Position = UDim2.new(0.5, -layout.hudWidth * 0.5, 0, noticeTop)
		notices.Size = UDim2.fromOffset(leftWidth, remainingHeight)
		local feedbackCode = if snapshot.feedback == nil then "" else snapshot.feedback.code
		if notices:GetAttribute("ATDFeedbackCode") ~= feedbackCode then
			notices.CanvasPosition = Vector2.zero
			notices:SetAttribute("ATDFeedbackCode", feedbackCode)
		end
		notices.Visible = snapshot.ready == nil
			and snapshot.result == nil
			and (instances.feedback.Visible or instances.tutorialPanel.Visible)
		local cursor = 0
		if instances.feedback.Visible then
			local feedbackHeight = TextLayout.measure(
				instances.feedback.Text,
				instances.feedback.TextSize,
				leftWidth,
				instances.feedback.Font,
				TextLayout.scale(instances.feedback)
			)
			instances.feedback.AnchorPoint = Vector2.zero
			instances.feedback.Position = UDim2.fromOffset(0, 0)
			instances.feedback.Size = UDim2.fromOffset(leftWidth, feedbackHeight)
			cursor = feedbackHeight + 8
		end
		if instances.tutorialPanel.Visible then
			instances.tutorialPanel.AnchorPoint = Vector2.zero
			instances.tutorialPanel.Position = UDim2.fromOffset(0, cursor)
			instances.tutorialPanel.Size = UDim2.fromOffset(leftWidth, remainingHeight)
			TextLayout.reflow(instances.tutorialPanel, leftWidth, remainingHeight, layout.touchTarget)
			cursor += instances.tutorialPanel.Size.Y.Offset + 8
		end
		notices.CanvasSize = UDim2.fromOffset(0, cursor)
	end
	local controls = currentFocusControls(data, snapshot)
	pcall(FocusNavigation.link, controls)
	local preferredFocus = bestFocus(instances, snapshot)
	if table.find(controls, preferredFocus) == nil then
		preferredFocus = controls[1]
	end
	local nextFocusMode = focusMode(snapshot)
	if (snapshot.inputFamily == "Gamepad" or data.keyboardNavigation) and data.lastFocusMode ~= nextFocusMode then
		if data.lastFocusMode == "Match" and data.dependencies.getSelectedObject ~= nil then
			data.focusRestore = data.dependencies.getSelectedObject()
		end
		local restore = if nextFocusMode == "Match" and table.find(controls, data.focusRestore) ~= nil
			then data.focusRestore
			else preferredFocus
		data.dependencies.selectObject(restore)
		pcall(FocusNavigation.reveal, restore)
	end
	if snapshot.inputFamily == "Gamepad" or data.keyboardNavigation then
		local selected = if data.dependencies.getSelectedObject == nil
			then nil
			else data.dependencies.getSelectedObject()
		if selected == nil or table.find(controls, selected) == nil then
			data.dependencies.selectObject(preferredFocus)
			pcall(FocusNavigation.reveal, preferredFocus)
		end
	end
	data.lastFocusMode = nextFocusMode
	data.inputFamily = snapshot.inputFamily
	data.reducedMotion = effective.reducedMotion
	data.lowEffects = snapshot.lowEffects == true
	data.enemyHealthBars = snapshot.enemyHealthBars ~= false
	data.towerRange = snapshot.towerRange ~= false
end

function ViewMethods.setPlacementCursor(self: View, position: Vector2?)
	local data = requireData(self)
	if data.cleaned then
		return
	end
	local root = data.instances.root
	local existing = root:FindFirstChild("PlacementCursor")
	if position == nil then
		if existing ~= nil and existing:IsA("GuiObject") then
			existing.Visible = false
		end
		return
	end
	if not finiteVector2(position) then
		return
	end
	local cursor: TextLabel
	if existing == nil then
		cursor = makeLabel("PlacementCursor", root, data.applyProductionStyle)
		cursor.Text = "+"
		cursor.AnchorPoint = Vector2.new(0.5, 0.5)
		cursor.Size = UDim2.fromOffset(36, 36)
		cursor.TextSize = 32
		cursor.TextColor3 = Color3.new(1, 1, 1)
		cursor.TextStrokeColor3 = Color3.new(0, 0, 0)
		cursor.TextStrokeTransparency = 0
		cursor.BackgroundTransparency = 1
		cursor.ZIndex = 20
	elseif existing:IsA("TextLabel") then
		cursor = existing
	else
		return
	end
	cursor.Visible = data.current ~= nil and data.current.placement ~= nil
	local scale = data.instances.uiScale.Scale
	local relative = position / scale
	if data.applyProductionStyle then
		relative -= root.AbsolutePosition / scale
	end
	cursor.Position = UDim2.fromOffset(relative.X, relative.Y)
end

function ViewMethods.render(self: View, value: unknown): Outcome<Metrics>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local canonical = canonicalSnapshot(value)
	if canonical == nil then
		return failure("INVALID_SNAPSHOT")
	end
	local previousMatchId = if data.current == nil then nil else data.current.matchId
	local rendered = pcall(ProfileScope.call, "ATD.Client.UI", renderSnapshot, data, canonical)
	if not rendered then
		return failure("RENDER_FAILED")
	end
	if previousMatchId ~= nil and previousMatchId ~= canonical.matchId then
		data.lastAttackSequence = 0
		for id, record in data.towerRecords do
			data.towerRecords[id] = nil
			record.model:Destroy()
		end
		for id, record in data.enemyRecords do
			data.enemyRecords[id] = nil
			record.model:Destroy()
		end
		for index = #data.effects, 1, -1 do
			data.effects[index].part:Destroy()
			data.effects[index] = nil
		end
	end
	data.current = canonical
	data.renderCount += 1
	return ok(self:getMetrics())
end

function ViewMethods.focusGamepad(self: View): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if data.current == nil then
		return failure("INVALID_SNAPSHOT")
	end
	local selected = bestFocus(data.instances, data.current)
	if not pcall(data.dependencies.selectObject, selected) then
		return failure("RENDER_FAILED")
	end
	return ok(selected ~= nil)
end

local function canonicalWorld(value: unknown): ({ TowerVisual }?, { EnemyVisual }?)
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil, nil
	end
	local world = value :: { [any]: unknown }
	local towersValue = rawget(world, "towers")
	local enemiesValue = rawget(world, "enemies")
	if type(towersValue) ~= "table" or type(enemiesValue) ~= "table" then
		return nil, nil
	end
	local towerCount = denseCount(towersValue :: { [any]: unknown }, MAX_TOWERS)
	local enemyCount = denseCount(enemiesValue :: { [any]: unknown }, MAX_ENEMIES)
	if towerCount == nil or enemyCount == nil then
		return nil, nil
	end
	local towers = table.create(towerCount) :: { TowerVisual }
	local enemies = table.create(enemyCount) :: { EnemyVisual }
	local identifiers: { [string]: boolean } = {}
	for index = 1, towerCount do
		local towerValue = rawget(towersValue :: { [any]: unknown }, index)
		if type(towerValue) ~= "table" or getmetatable(towerValue) ~= nil then
			return nil, nil
		end
		local tower = towerValue :: { [any]: unknown }
		local id = rawget(tower, "id")
		local definitionId = rawget(tower, "definitionId")
		local position = rawget(tower, "position")
		local rotationDegrees = rawget(tower, "rotationDegrees")
		local selected = rawget(tower, "selected")
		local range = rawget(tower, "range")
		local level = rawget(tower, "level")
		if
			not safeId(id)
			or identifiers[id :: string]
			or not safeId(definitionId)
			or not finiteVector3(position)
			or (rotationDegrees ~= nil and (not finiteNumber(rotationDegrees) or math.abs(rotationDegrees :: number) > 360))
			or (selected ~= nil and type(selected) ~= "boolean")
			or (range ~= nil and (not finiteNumber(range) or (range :: number) < 0 or (range :: number) > 10_000))
			or not safeInteger(level, 1, 100)
		then
			return nil, nil
		end
		identifiers[id :: string] = true
		towers[index] = table.freeze({
			id = id :: string,
			definitionId = definitionId :: string,
			position = position :: Vector3,
			rotationDegrees = rotationDegrees :: number?,
			selected = selected :: boolean?,
			range = range :: number?,
			level = level :: number,
		})
	end
	for index = 1, enemyCount do
		local enemyValue = rawget(enemiesValue :: { [any]: unknown }, index)
		if type(enemyValue) ~= "table" or getmetatable(enemyValue) ~= nil then
			return nil, nil
		end
		local enemy = enemyValue :: { [any]: unknown }
		local id = rawget(enemy, "id")
		local definitionId = rawget(enemy, "definitionId")
		local position = rawget(enemy, "position")
		local health = rawget(enemy, "health")
		local maxHealth = rawget(enemy, "maxHealth")
		local archetype = rawget(enemy, "archetype")
		if
			not safeId(id)
			or identifiers[id :: string]
			or not safeId(definitionId)
			or not finiteVector3(position)
			or not finiteNumber(maxHealth)
			or (maxHealth :: number) <= 0
			or (maxHealth :: number) > 1_000_000
			or not finiteNumber(health)
			or (health :: number) < 0
			or (health :: number) > (maxHealth :: number)
			or (archetype ~= nil and not safeText(archetype, 32))
		then
			return nil, nil
		end
		identifiers[id :: string] = true
		enemies[index] = table.freeze({
			id = id :: string,
			definitionId = definitionId :: string,
			position = position :: Vector3,
			health = health :: number,
			maxHealth = maxHealth :: number,
			archetype = archetype :: string?,
		})
	end
	return towers, enemies
end

local function syncWorld(self: View, value: unknown): Outcome<Metrics>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local towers, enemies = canonicalWorld(value)
	if towers == nil or enemies == nil then
		return failure("INVALID_WORLD")
	end
	local createdModels: { Model } = {}
	local stagedTowers: { [string]: TowerRecord } = {}
	local stagedEnemies: { [string]: EnemyRecord } = {}
	local staged, _ = pcall(function()
		for _, tower in towers :: { TowerVisual } do
			local current = data.towerRecords[tower.id]
			if current == nil or current.definitionId ~= tower.definitionId then
				local model, primaryPart, isPrimitiveFallback =
					cloneVisualModel(data, data.instances.towerFolder, "TowerModel", tower.definitionId)
				if model == nil or primaryPart == nil or isPrimitiveFallback == nil then
					error("tower template unavailable", 0)
				end
				table.insert(createdModels, model)
				model.Name = tower.id
				local levelDisplay, levelText = makeTowerLevelDisplay(model, primaryPart, data.applyProductionStyle)
				local initialLevel = tower.level
				local towerRecord: TowerRecord = {
					aim = TowerAim.new(math.rad(tower.rotationDegrees or 0)),
					position = tower.position,
					model = model,
					primaryPart = primaryPart,
					definitionId = tower.definitionId,
					muzzles = orderedMuzzles(model),
					selection = makeSelectionHighlight(model, data.applyProductionStyle),
					rangeIndicator = makeRangeIndicator(model, data.applyProductionStyle),
					levelDisplay = levelDisplay,
					levelText = levelText,
					level = initialLevel,
					isPrimitiveFallback = isPrimitiveFallback,
				}
				setTowerLevel(towerRecord, initialLevel)
				stagedTowers[tower.id] = towerRecord
			end
		end
		for _, enemy in enemies :: { EnemyVisual } do
			local current = data.enemyRecords[enemy.id]
			if current == nil or current.definitionId ~= enemy.definitionId then
				local model, primaryPart, isPrimitiveFallback =
					cloneVisualModel(data, data.instances.enemyFolder, "EnemyModel", enemy.definitionId)
				if model == nil or primaryPart == nil or isPrimitiveFallback == nil then
					error("enemy template unavailable", 0)
				end
				table.insert(createdModels, model)
				model.Name = enemy.id
				local healthDisplay, healthFill, healthText =
					makeEnemyHealthDisplay(model, primaryPart, data.applyProductionStyle)
				stagedEnemies[enemy.id] = {
					model = model,
					primaryPart = primaryPart,
					definitionId = enemy.definitionId,
					healthFill = healthFill,
					healthText = healthText,
					healthDisplay = healthDisplay,
					isPrimitiveFallback = isPrimitiveFallback,
				}
			end
		end
	end)
	if not staged then
		for _, model in createdModels do
			model:Destroy()
		end
		return failure("RENDER_FAILED")
	end

	local succeeded = pcall(function()
		local seenTowers: { [string]: boolean } = {}
		for _, tower in towers :: { TowerVisual } do
			seenTowers[tower.id] = true
			local replacement = stagedTowers[tower.id]
			if replacement ~= nil then
				local previous = data.towerRecords[tower.id]
				if previous ~= nil then
					previous.model:Destroy()
				end
				data.towerRecords[tower.id] = replacement
			end
			local record = data.towerRecords[tower.id]
			if record == nil then
				error("tower record missing", 0)
			end
			if record.level ~= tower.level then
				setTowerLevel(record, tower.level)
			end
			local position = if record.isPrimitiveFallback
				then tower.position + Vector3.new(0, record.primaryPart.Size.Y * 0.5, 0)
				else tower.position
			local rotation = math.rad(tower.rotationDegrees or 0)
			record.position = position
			TowerAim.setIdle(record.aim, rotation)
			local yaw = TowerAim.step(record.aim, data.dependencies.now(), 0, data.reducedMotion)
			pivotVisual(data, record.model, record.primaryPart, CFrame.new(position) * CFrame.Angles(0, yaw, 0))
			if record.selection ~= nil then
				record.selection.Enabled = tower.selected == true
			end
			if record.rangeIndicator ~= nil then
				local radius = tower.range or 0
				record.rangeIndicator.Size = Vector3.new(0.08, radius * 2, radius * 2)
				record.rangeIndicator.CFrame = CFrame.new(tower.position + Vector3.new(0, 0.04, 0))
					* CFrame.Angles(0, 0, math.pi / 2)
				record.rangeIndicator.Transparency = if data.towerRange
						and tower.selected == true
						and radius > 0
					then 0.82
					else 1
			end
		end
		for id, record in data.towerRecords do
			if not seenTowers[id] then
				data.towerRecords[id] = nil
				record.model:Destroy()
			end
		end

		local seenEnemies: { [string]: boolean } = {}
		for _, enemy in enemies :: { EnemyVisual } do
			seenEnemies[enemy.id] = true
			local replacement = stagedEnemies[enemy.id]
			if replacement ~= nil then
				local previous = data.enemyRecords[enemy.id]
				if previous ~= nil then
					previous.model:Destroy()
				end
				data.enemyRecords[enemy.id] = replacement
			end
			local record = data.enemyRecords[enemy.id]
			if record == nil then
				error("enemy record missing", 0)
			end
			pivotVisual(data, record.model, record.primaryPart, CFrame.new(enemy.position))
			local healthRatio = enemy.health / enemy.maxHealth
			if record.healthFill ~= nil and record.healthText ~= nil then
				if record.healthDisplay ~= nil then
					record.healthDisplay.Enabled = data.enemyHealthBars
				end
				if data.applyProductionStyle then
					record.healthFill.Size = UDim2.fromScale(healthRatio, 1)
				end
				record.healthFill.BackgroundColor3 = if healthRatio <= 0.25
					then COLORS.Bad
					elseif healthRatio <= 0.5 then COLORS.Warning
					else COLORS.Good
				record.healthText.Text = Localization.text(
					"playable_match_view.value_2",
					{ health = math.ceil(enemy.health), maxHealth = math.ceil(enemy.maxHealth) }
				)
			end
		end
		for id, record in data.enemyRecords do
			if not seenEnemies[id] then
				data.enemyRecords[id] = nil
				record.model:Destroy()
			end
		end
	end)
	if not succeeded then
		for id, record in stagedTowers do
			if data.towerRecords[id] ~= record then
				record.model:Destroy()
			end
		end
		for id, record in stagedEnemies do
			if data.enemyRecords[id] ~= record then
				record.model:Destroy()
			end
		end
		return failure("RENDER_FAILED")
	end
	return ok(self:getMetrics())
end

function ViewMethods.syncWorld(self: View, value: unknown): Outcome<Metrics>
	return ProfileScope.call("ATD.Client.World", syncWorld, self, value)
end

local function attackPositions(data: ViewData, event: AttackEvent): (Vector3?, Vector3?)
	local origin = event.origin
	local target = event.target
	local towerRecord = data.towerRecords[event.towerId]
	if origin == nil and towerRecord ~= nil then
		origin = towerRecord.primaryPart.CFrame.Position
	end
	if origin ~= nil and towerRecord ~= nil and #towerRecord.muzzles > 0 then
		-- Attack events do not identify a per-shot muzzle. Always choose the first
		-- bounded authored marker rather than implying unsupported alternation.
		local muzzle = towerRecord.muzzles[1]
		local muzzlePosition = muzzle.CFrame.Position
		if (muzzlePosition - origin).Magnitude <= MAX_MUZZLE_OFFSET_STUDS then
			origin = muzzlePosition
		end
	end
	if target == nil then
		local enemyRecord = data.enemyRecords[event.targetId]
		target = if enemyRecord == nil then nil else enemyRecord.primaryPart.CFrame.Position
	end
	return origin, target
end

function ViewMethods.playAttackEffect(self: View, value: unknown): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if type(value) ~= "table" or getmetatable(value) ~= nil or data.current == nil then
		return failure("INVALID_ARGUMENT")
	end
	local record = value :: { [any]: unknown }
	local event: AttackEvent = {
		matchId = rawget(record, "matchId") :: any,
		sequence = rawget(record, "sequence") :: any,
		towerId = rawget(record, "towerId") :: any,
		targetId = rawget(record, "targetId") :: any,
		origin = rawget(record, "origin") :: any,
		target = rawget(record, "target") :: any,
		damage = rawget(record, "damage") :: any,
	}
	if
		not safeId(event.matchId)
		or not safeInteger(event.sequence, 1, 2 ^ 31 - 1)
		or not safeId(event.towerId)
		or not safeId(event.targetId)
		or (event.origin ~= nil and not finiteVector3(event.origin))
		or (event.target ~= nil and not finiteVector3(event.target))
		or (event.damage ~= nil and not safeInteger(event.damage, 1, 1_000_000))
	then
		return failure("INVALID_ARGUMENT")
	end
	if event.matchId ~= data.current.matchId or event.sequence <= data.lastAttackSequence then
		return failure("STALE_EVENT")
	end
	local origin, target = attackPositions(data, event)
	if origin == nil or target == nil then
		return failure("ENTITY_NOT_FOUND")
	end
	local delta = target - origin
	if delta.Magnitude < 0.01 or delta.Magnitude > 10_000 then
		return failure("INVALID_ARGUMENT")
	end
	data.lastAttackSequence = event.sequence
	local towerRecord = data.towerRecords[event.towerId]
	if towerRecord ~= nil and not data.reducedMotion then
		TowerAim.observe(towerRecord.aim, origin, target, data.dependencies.now())
	end
	local policy = PresentationPolicy.effects({ reducedMotion = data.reducedMotion, lowEffects = data.lowEffects })
	stepEffects(data, data.dependencies.now())
	if data.effectsAdmittedThisFrame >= policy.perFrame then
		return ok(false)
	end
	if data.applyProductionStyle then
		local camera = Workspace.CurrentCamera
		if
			camera ~= nil
			and (camera.CFrame.Position - target).Magnitude > PresentationPolicy.MAX_EFFECT_DISTANCE
			and (camera.CFrame.Position - origin).Magnitude > PresentationPolicy.MAX_EFFECT_DISTANCE
		then
			return ok(false)
		end
	end
	data.effectsAdmittedThisFrame += 1
	local stagedEffect: Part? = nil
	local created = pcall(ProfileScope.call, "ATD.Client.EffectCreate", function()
		local maximum = policy.maximum
		while #data.effects >= maximum do
			local oldest = table.remove(data.effects, 1)
			oldest.part:Destroy()
		end
		local effect = makeWorldPart("Attack", data.instances.effectFolder, data.applyProductionStyle)
		stagedEffect = effect
		effect.Size = Vector3.new(0.12, 0.12, delta.Magnitude)
		effect.CFrame = CFrame.lookAt(origin + delta * 0.5, target)
		effect.Color = COLORS.Effect
		effect.Transparency = if data.reducedMotion then 0.35 else 0.12
		if data.applyProductionStyle then
			effect.Material = Enum.Material.Neon
		end
		if policy.flashes then
			local muzzleFlash = makeWorldPart("MuzzleFlash", effect, data.applyProductionStyle)
			muzzleFlash.Shape = Enum.PartType.Ball
			muzzleFlash.Size = Vector3.new(0.48, 0.48, 0.48)
			muzzleFlash.CFrame = CFrame.new(origin)
			muzzleFlash.Color = COLORS.Warning
			muzzleFlash.Transparency = if data.reducedMotion then 0.28 else 0.08
			if data.applyProductionStyle then
				muzzleFlash.Material = Enum.Material.Neon
			end

			local impactFlash = makeWorldPart("ImpactFlash", effect, data.applyProductionStyle)
			impactFlash.Shape = Enum.PartType.Ball
			impactFlash.Size = Vector3.new(0.72, 0.72, 0.72)
			impactFlash.CFrame = CFrame.new(target)
			impactFlash.Color = COLORS.Effect
			impactFlash.Transparency = if data.reducedMotion then 0.32 else 0.12
			if data.applyProductionStyle then
				impactFlash.Material = Enum.Material.Neon
			end
		end
		if event.damage ~= nil then
			local display = Instance.new("BillboardGui")
			display.Name = "DamageNumber"
			display.Adornee = effect
			display.AlwaysOnTop = true
			display.LightInfluence = 0
			display.Size = UDim2.fromOffset(80, 28)
			display.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
			display.Parent = effect
			local label = makeLabel("Value", display, data.applyProductionStyle)
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = Localization.text("playable_match_view.value_3", { damage = event.damage })
			label.TextColor3 = COLORS.Warning
			label.TextScaled = true
		end
		local duration = if data.reducedMotion then 0.04 else EFFECT_DURATION_SECONDS
		table.insert(data.effects, {
			part = effect,
			expiresAt = data.dependencies.now() + duration,
		})
	end)
	if not created then
		if stagedEffect ~= nil then
			stagedEffect:Destroy()
		end
		return failure("RENDER_FAILED")
	end
	data.lastAttackSequence = event.sequence
	return ok(true)
end

function ViewMethods.stepEffects(self: View, nowValue: unknown): Outcome<number>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not finiteNumber(nowValue) or (nowValue :: number) < 0 then
		return failure("INVALID_ARGUMENT")
	end
	local succeeded = pcall(stepEffects, data, nowValue :: number)
	if not succeeded then
		return failure("RENDER_FAILED")
	end
	return ok(#data.effects)
end

local function countMap(parts: { [string]: any }): number
	local count = 0
	for _ in parts do
		count += 1
	end
	return count
end

function ViewMethods.getMetrics(self: View): Metrics
	local data = requireData(self)
	if data.cleaned then
		return table.freeze({
			connectionCount = 0,
			renderCount = data.renderCount,
			actionCount = data.actionCount,
			matchState = nil,
			inputFamily = data.inputFamily,
			waveText = "",
			enemyText = "",
			bossVisible = false,
			bossText = "",
			tutorialVisible = false,
			tutorialText = "",
			baseText = "",
			cashText = "",
			feedbackText = "",
			readyVisible = false,
			towerPanelVisible = false,
			inspectionOnly = false,
			resultsVisible = false,
			resultKind = nil,
			viewerRole = nil,
			spectatorVisible = false,
			rewardText = "",
			travelText = "",
			touchPlacementVisible = false,
			touchPlacementText = "",
			worldTowerCount = 0,
			worldEnemyCount = 0,
			attackEffectCount = 0,
			cleaned = true,
		})
	end
	local instances = data.instances
	local snapshot = data.current
	return table.freeze({
		connectionCount = #data.connections,
		renderCount = data.renderCount,
		actionCount = data.actionCount,
		matchState = if snapshot == nil then nil else snapshot.state,
		inputFamily = data.inputFamily,
		waveText = instances.waveLabel.Text,
		enemyText = instances.enemyLabel.Text,
		bossVisible = instances.bossPanel.Visible,
		bossText = instances.bossLabel.Text,
		tutorialVisible = instances.tutorialPanel.Visible,
		tutorialText = instances.tutorialLabel.Text,
		baseText = instances.baseButton.Text,
		cashText = instances.cashLabel.Text,
		feedbackText = instances.feedback.Text,
		readyVisible = instances.readyOverlay.Visible,
		towerPanelVisible = instances.towerPanel.Visible,
		inspectionOnly = snapshot ~= nil and snapshot.selection ~= nil and not snapshot.selection.isOwner,
		resultsVisible = instances.resultsOverlay.Visible,
		resultKind = if snapshot == nil or snapshot.result == nil then nil else snapshot.result.kind,
		viewerRole = if snapshot == nil then nil else snapshot.viewerRole,
		spectatorVisible = instances.spectatorPanel.Visible,
		rewardText = instances.resultReward.Text,
		travelText = instances.spectatorTarget.Text,
		touchPlacementVisible = instances.touchPlacementPanel.Visible,
		touchPlacementText = instances.touchPlacementStatus.Text,
		worldTowerCount = countMap(data.towerRecords),
		worldEnemyCount = countMap(data.enemyRecords),
		attackEffectCount = #data.effects,
		cleaned = data.cleaned,
	})
end

function ViewMethods.cleanup(self: View): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return ok(true)
	end
	data.cleaned = true
	local succeeded = disconnectAll(data.connections)
	if data.dependencies.cleanupInput ~= nil and not pcall(data.dependencies.cleanupInput) then
		succeeded = false
	end
	if
		not pcall(function()
			data.dependencies.selectObject(nil)
			data.instances.gui:Destroy()
			data.instances.worldFolder:Destroy()
		end)
	then
		succeeded = false
	end
	table.clear(data.towerRecords)
	table.clear(data.enemyRecords)
	table.clear(data.effects)
	table.clear(data.activationCallbacks)
	data.focusRestore = nil
	data.current = nil
	if not succeeded then
		return failure("CLEANUP_FAILED")
	end
	return ok(true)
end

local function productionDependencies(): Dependencies
	local KeyboardNavigation = require(commonUiRoot().KeyboardNavigation)
	local releaseKeyboard: (() -> ())? = nil
	return {
		cleanupInput = function()
			if releaseKeyboard ~= nil then
				releaseKeyboard()
				releaseKeyboard = nil
			end
		end,
		connectActivated = function(button, callback)
			return button.Activated:Connect(callback)
		end,
		connectStepped = function(callback)
			return RunService.RenderStepped:Connect(callback)
		end,
		now = os.clock,
		selectObject = function(value)
			GuiService.SelectedObject = value
		end,
		getSelectedObject = function()
			return GuiService.SelectedObject
		end,
		connectInputBegan = function(callback)
			releaseKeyboard = KeyboardNavigation.bind(GUI_NAME, callback)
			return UserInputService.InputBegan:Connect(function(input, processed)
				if KeyboardNavigation.ownsKey(input.KeyCode) then
					return
				end
				callback(input.KeyCode.Name, processed)
			end)
		end,
	}
end

function PlayableMatchView.new(callback: unknown): ViewResult
	if type(callback) ~= "function" then
		return failure("INVALID_ARGUMENT")
	end
	local player = Players.LocalPlayer
	local playerGui = if player == nil then nil else player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return failure("INVALID_PARENT")
	end
	return construct(
		playerGui,
		Workspace,
		callback :: UiActionCallback,
		productionDependencies(),
		true,
		ReplicatedStorage,
		false
	)
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "PlayableMatchView" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionClientPlayable" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

if isExactTestModule() then
	PlayableMatchView.newForTests = function(
		guiParent: Instance,
		worldParent: Instance,
		callback: UiActionCallback,
		dependencies: Dependencies,
		productionLayout: boolean?
	): ViewResult
		return construct(guiParent, worldParent, callback, dependencies, productionLayout == true, nil, true)
	end
	PlayableMatchView.newTemplateBackedForTests = function(
		guiParent: Instance,
		worldParent: Instance,
		templateRoot: Instance,
		callback: UiActionCallback,
		dependencies: Dependencies
	): ViewResult
		return construct(guiParent, worldParent, callback, dependencies, false, templateRoot, false)
	end
	PlayableMatchView.resolveResponsiveLayoutForTests = resolveResponsiveLayout
end

table.freeze(ViewMethods)
return table.freeze(PlayableMatchView)
