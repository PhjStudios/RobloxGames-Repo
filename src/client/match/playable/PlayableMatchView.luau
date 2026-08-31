--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

export type InputFamily = "Desktop" | "Touch" | "Gamepad"
export type MatchState = "Loading" | "ReadyCheck" | "PreWave" | "WaveActive" | "Results" | "Closing"
export type ResultKind = "Victory" | "Defeat"
export type TargetMode = "First" | "Last" | "Strongest" | "Weakest" | "Closest"
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
	cost: number,
	available: boolean,
	selected: boolean,
	reason: string?,
}

export type WaveState = {
	current: number,
	total: number,
	enemiesRemaining: number,
	status: string?,
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
}

export type RenderSnapshot = {
	matchId: string,
	revision: number,
	state: MatchState,
	inputFamily: InputFamily,
	wave: WaveState,
	base: BaseState,
	battleCash: number,
	hotbar: { HotbarSlot },
	ready: ReadyState?,
	selection: TowerSelection?,
	feedback: FeedbackState?,
	result: ResultState?,
	placement: PlacementState?,
	inputHint: string?,
	viewport: Vector2?,
	uiScale: number?,
	reducedMotion: boolean?,
	lowEffects: boolean?,
}

export type TowerVisual = {
	id: string,
	definitionId: string,
	position: Vector3,
	rotationDegrees: number?,
	selected: boolean?,
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
	baseText: string,
	cashText: string,
	feedbackText: string,
	readyVisible: boolean,
	towerPanelVisible: boolean,
	inspectionOnly: boolean,
	resultsVisible: boolean,
	resultKind: ResultKind?,
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
	resultHint: TextLabel,
	replayButton: TextButton,
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
	model: Model,
	primaryPart: BasePart,
	definitionId: string,
	selection: Highlight?,
	isPrimitiveFallback: boolean,
}

type EnemyRecord = {
	model: Model,
	primaryPart: BasePart,
	definitionId: string,
	healthFill: Frame?,
	healthText: TextLabel?,
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
	current: CanonicalSnapshot?,
	lastAttackSequence: number,
	lastFocusMode: string?,
	inputFamily: InputFamily,
	reducedMotion: boolean,
	lowEffects: boolean,
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
export type TestConstructor = (Instance, Instance, UiActionCallback, Dependencies) -> ViewResult
export type TemplateTestConstructor = (Instance, Instance, Instance, UiActionCallback, Dependencies) -> ViewResult
export type ResponsiveLayoutResolver = (unknown, unknown) -> ResponsiveLayout?

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ViewData }

local GUI_NAME = "ATDPlayableMatch"
local WORLD_FOLDER_NAME = "_ATDPlayablePresentation"
local TEMPLATE_FOLDER_NAME = "ATDPlayableTemplates"
local CONTENT_CONTRACT = "playable-local-match-v1"
local CONTENT_VERSION = 1
local HOTBAR_SLOTS = 3
local BUTTON_CONNECTION_COUNT = 13
local MAX_TOWERS = 64
local MAX_ENEMIES = 256
local MAX_ATTACK_EFFECTS = 32
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
		or (heightValue :: number) < 320
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
	local maximumHotbar = if mode == "Compact" then 352 else 420
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
	if status ~= nil and not safeText(status, 96, true) then
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
	if
		(kind ~= "Victory" and kind ~= "Defeat")
		or not safeText(summary, 180, true)
		or type(canReplay) ~= "boolean"
		or (status ~= nil and not safeText(status, 96, true))
	then
		return nil
	end
	return table.freeze({
		kind = kind :: ResultKind,
		summary = summary :: string,
		canReplay = canReplay :: boolean,
		status = status :: string?,
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

local function canonicalSnapshot(value: unknown): CanonicalSnapshot?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local snapshot = value :: { [any]: unknown }
	local matchId = rawget(snapshot, "matchId")
	local revision = rawget(snapshot, "revision")
	local state = rawget(snapshot, "state")
	local inputFamily = rawget(snapshot, "inputFamily")
	local waveValue = rawget(snapshot, "wave")
	local baseValue = rawget(snapshot, "base")
	local battleCash = rawget(snapshot, "battleCash")
	local hotbarValue = rawget(snapshot, "hotbar")
	if
		not safeId(matchId)
		or not safeInteger(revision, 0, 2 ^ 31 - 1)
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
	then
		return nil
	end

	local wave = waveValue :: { [any]: unknown }
	local current = rawget(wave, "current")
	local total = rawget(wave, "total")
	local enemiesRemaining = rawget(wave, "enemiesRemaining")
	local waveStatus = rawget(wave, "status")
	if
		not safeInteger(total, 1, 1_000)
		or not safeInteger(current, 0, total :: number)
		or not safeInteger(enemiesRemaining, 0, 100_000)
		or (waveStatus ~= nil and not safeText(waveStatus, 64, true))
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
	if hotbarCount ~= HOTBAR_SLOTS then
		return nil
	end
	local hotbar = table.create(HOTBAR_SLOTS) :: { HotbarSlot }
	local selectedCount = 0
	for index = 1, HOTBAR_SLOTS do
		local slotValue = rawget(hotbarValue :: { [any]: unknown }, index)
		if type(slotValue) ~= "table" or getmetatable(slotValue) ~= nil then
			return nil
		end
		local slot = slotValue :: { [any]: unknown }
		local slotIndex = rawget(slot, "slot")
		local displayName = rawget(slot, "displayName")
		local cost = rawget(slot, "cost")
		local available = rawget(slot, "available")
		local selected = rawget(slot, "selected")
		local reason = rawget(slot, "reason")
		if
			slotIndex ~= index
			or not safeText(displayName, 32)
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

	local selectionValue = rawget(snapshot, "selection")
	local selection = if selectionValue == nil then nil else canonicalSelection(selectionValue)
	if selectionValue ~= nil and selection == nil then
		return nil
	end
	if selection ~= nil and state ~= "PreWave" and state ~= "WaveActive" then
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

	local placementValue = rawget(snapshot, "placement")
	local placement = if placementValue == nil then nil else canonicalPlacement(placementValue)
	if placementValue ~= nil and placement == nil then
		return nil
	end
	if
		placement ~= nil
		and (inputFamily ~= "Touch" or (state ~= "PreWave" and state ~= "WaveActive") or selectedCount ~= 1)
	then
		return nil
	end

	local inputHint = rawget(snapshot, "inputHint")
	local viewport = rawget(snapshot, "viewport")
	local uiScale = rawget(snapshot, "uiScale")
	local reducedMotion = rawget(snapshot, "reducedMotion")
	local lowEffects = rawget(snapshot, "lowEffects")
	if inputHint ~= nil and not safeText(inputHint, 120, true) then
		return nil
	end
	if
		viewport ~= nil
		and (not finiteVector2(viewport) or (viewport :: Vector2).X < 240 or (viewport :: Vector2).Y < 320)
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

	return table.freeze({
		matchId = matchId :: string,
		revision = revision :: number,
		state = state :: MatchState,
		inputFamily = inputFamily :: InputFamily,
		wave = table.freeze({
			current = current :: number,
			total = total :: number,
			enemiesRemaining = enemiesRemaining :: number,
			status = waveStatus :: string?,
		}),
		base = table.freeze({ health = health :: number, maxHealth = maxHealth :: number }),
		battleCash = battleCash :: number,
		hotbar = table.freeze(hotbar),
		ready = ready,
		selection = selection,
		feedback = feedback,
		result = result,
		placement = placement,
		inputHint = inputHint :: string?,
		viewport = viewport :: Vector2?,
		uiScale = uiScale :: number?,
		reducedMotion = reducedMotion :: boolean?,
		lowEffects = lowEffects :: boolean?,
	})
end

local FEEDBACK_TEXT: { [string]: string } = table.freeze({
	INSUFFICIENT_CASH = "$ Not enough Battle Cash — defeat enemies or wait for the next stipend.",
	INVALID_POSITION = "▱ Move the tower onto an open placement zone.",
	TOWER_CAP_REACHED = "! Tower limit reached — sell a tower before placing another.",
	NOT_OWNER = "⌁ Inspection only — only the owner can change this tower.",
	STALE_MATCH = "↻ That match ended — wait for the new match to load.",
	STALE_TOWER = "↻ Tower changed — select it again and retry.",
	TOWER_NOT_FOUND = "? Tower no longer exists — choose another tower.",
	MATCH_NOT_ACTIVE = "! Tower actions unlock when the match is active.",
	RATE_LIMITED = "… Too many requests — wait a moment and try again.",
	REQUEST_PENDING = "… Waiting for server confirmation.",
	REQUEST_ACCEPTED = "✓ Server confirmed the action.",
	REQUEST_REJECTED = "! The server rejected that action — retry or choose another.",
	SERVER_UNAVAILABLE = "! Server unavailable — wait a moment and retry.",
	POSITION_SELECTED = "✓ Position selected — Confirm to spend Battle Cash and place the tower.",
})

local function feedbackText(feedback: FeedbackState?): string
	if feedback == nil then
		return ""
	end
	return FEEDBACK_TEXT[feedback.code] or "! Action unavailable — review the current match state and retry."
end

local function defaultHint(snapshot: CanonicalSnapshot): string
	if snapshot.placement ~= nil then
		return "Tap the map to choose a position • Confirm • Rotate • Cancel"
	elseif snapshot.state == "ReadyCheck" then
		return if snapshot.inputFamily == "Gamepad"
			then "A Ready"
			elseif snapshot.inputFamily == "Touch" then "Tap Ready"
			else "R / Enter Ready"
	elseif snapshot.state == "Results" then
		return if snapshot.inputFamily == "Gamepad"
			then "A Play Again"
			elseif snapshot.inputFamily == "Touch" then "Tap Play Again"
			else "R / Enter Play Again"
	elseif snapshot.selection ~= nil then
		return if snapshot.inputFamily == "Gamepad"
			then "Y Upgrade • RB Target • X Sell • B Close"
			elseif snapshot.inputFamily == "Touch" then "Use tower controls or Close"
			else "U Upgrade • T Target • X Sell • Q Close"
	end
	return if snapshot.inputFamily == "Gamepad"
		then "LB/RB Tower • D-Pad Down Focus Base"
		elseif snapshot.inputFamily == "Touch" then "Tap tower cards • Tap Base to focus"
		else "1–3 Select Tower • F Focus Base"
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

local function makeEnemyHealthDisplay(
	model: Model,
	primaryPart: BasePart,
	applyProductionStyle: boolean
): (Frame, TextLabel)
	local display = Instance.new("BillboardGui")
	display.Name = "HealthDisplay"
	display.Adornee = primaryPart
	if applyProductionStyle then
		display.AlwaysOnTop = true
		display.LightInfluence = 0
		display.MaxDistance = 220
		display.Size = UDim2.fromOffset(96, 30)
		display.StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0)
	end
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
	return fill, label
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

		local hotbar = makeFrame("TowerHotbar", root)
		local hotbarButtons = table.create(HOTBAR_SLOTS) :: { TextButton }
		for slot = 1, HOTBAR_SLOTS do
			local button = makeButton(`TowerSlot{slot}`, hotbar, applyProductionStyle)
			button.SelectionOrder = 20 + slot
			button.Text = `{slot}\n—`
			hotbarButtons[slot] = button
		end
		local hintLabel = makeLabel("InputHint", hotbar, applyProductionStyle)
		local touchPlacementPanel = makeFrame("TouchPlacementPanel", root)
		local touchPlacementStatus = makeLabel("Status", touchPlacementPanel, applyProductionStyle)
		local touchConfirmButton = makeButton("Confirm", touchPlacementPanel, applyProductionStyle)
		touchConfirmButton.Text = "✓ CONFIRM"
		local touchRotateButton = makeButton("Rotate", touchPlacementPanel, applyProductionStyle)
		touchRotateButton.Text = "↻ ROTATE"
		local touchCancelButton = makeButton("Cancel", touchPlacementPanel, applyProductionStyle)
		touchCancelButton.Text = "✕ CANCEL"

		local feedback = makeLabel("ActionFeedback", root, applyProductionStyle)
		feedback.BackgroundTransparency = 0.08
		feedback.BackgroundColor3 = COLORS.Panel
		feedback.Visible = false

		local readyOverlay = makeFrame("ReadyOverlay", root)
		local readyTitle = makeLabel("Title", readyOverlay, applyProductionStyle)
		readyTitle.Text = "◆ DEFEND THE COLONY"
		local readyCountdown = makeLabel("Countdown", readyOverlay, applyProductionStyle)
		local readyStatus = makeLabel("Status", readyOverlay, applyProductionStyle)
		local readyHint = makeLabel("InputHint", readyOverlay, applyProductionStyle)
		local readyButton = makeButton("Ready", readyOverlay, applyProductionStyle)
		readyButton.Text = "✓ READY"
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
		closeButton.Text = "✕ CLOSE"
		closeButton.SelectionOrder = 43

		local resultsOverlay = makeFrame("ResultsOverlay", root)
		local resultTitle = makeLabel("ResultTitle", resultsOverlay, applyProductionStyle)
		local resultSummary = makeLabel("Summary", resultsOverlay, applyProductionStyle)
		local resultHint = makeLabel("InputHint", resultsOverlay, applyProductionStyle)
		local replayButton = makeButton("Replay", resultsOverlay, applyProductionStyle)
		replayButton.Text = "↻ PLAY AGAIN"
		replayButton.SelectionOrder = 2

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
			resultHint = resultHint,
			replayButton = replayButton,
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
	local hudHeight = if layout.mode == "TenFoot" then 92 else 72
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

	local hotbarHeight = if layout.mode == "TenFoot" then 132 else 112
	instances.hotbar.AnchorPoint = Vector2.new(0.5, 1)
	instances.hotbar.Position = UDim2.new(0.5, 0, 1, -12)
	instances.hotbar.Size = UDim2.fromOffset(layout.hotbarWidth, hotbarHeight)
	instances.hotbar.BackgroundTransparency = 0.08
	local slotGap = 8
	local buttonWidth = (layout.hotbarWidth - 24 - slotGap * 2) / 3
	local buttonHeight = math.max(layout.touchTarget, hotbarHeight - 38)
	for slot, button in instances.hotbarButtons do
		button.Position = UDim2.fromOffset(12 + (slot - 1) * (buttonWidth + slotGap), 8)
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
	instances.feedback.Position = UDim2.new(0.5, 0, 0, hudHeight + 18)
	instances.feedback.Size = UDim2.fromOffset(math.min(layout.hudWidth, 720), layout.touchTarget)
	instances.feedback.TextSize = layout.textSize - 1

	instances.readyOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
	instances.readyOverlay.Position = UDim2.fromScale(0.5, 0.5)
	instances.readyOverlay.Size =
		UDim2.fromOffset(math.min(440, layout.hudWidth), if layout.mode == "Compact" then 250 else 280)
	instances.readyOverlay.BackgroundTransparency = 0.04
	local readyTitle = instances.readyOverlay:FindFirstChild("Title") :: TextLabel
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
	instances.resultsOverlay.Size = UDim2.fromOffset(math.min(500, layout.hudWidth), 310)
	instances.resultsOverlay.BackgroundTransparency = 0.03
	instances.resultTitle.Position = UDim2.fromOffset(18, 22)
	instances.resultTitle.Size = UDim2.new(1, -36, 0, 58)
	instances.resultTitle.TextSize = layout.textSize + 10
	instances.resultSummary.Position = UDim2.fromOffset(18, 88)
	instances.resultSummary.Size = UDim2.new(1, -36, 0, 92)
	instances.resultSummary.TextSize = layout.textSize
	instances.replayButton.Position = UDim2.new(0, 18, 1, -(layout.touchTarget + 50))
	instances.replayButton.Size = UDim2.new(1, -36, 0, layout.touchTarget + 8)
	instances.replayButton.TextSize = layout.textSize + 1
	instances.resultHint.Position = UDim2.new(0, 18, 1, -32)
	instances.resultHint.Size = UDim2.new(1, -36, 0, 22)
	instances.resultHint.TextSize = math.max(13, layout.textSize - 4)
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
	end
	return "Match"
end

local function bestFocus(instances: ViewInstances, snapshot: CanonicalSnapshot): GuiObject?
	if snapshot.result ~= nil and snapshot.result.canReplay then
		return instances.replayButton
	elseif snapshot.ready ~= nil and snapshot.ready.enabled then
		return instances.readyButton
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
	if kind == "SelectHotbar" then
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
	local connected, connectionOrError = pcall(data.dependencies.connectActivated, button, function()
		if data.cleaned then
			return
		end
		local action = actionFor(data, kind, slot)
		if action ~= nil and pcall(data.callback, action) then
			data.actionCount += 1
		end
	end)
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

local function stepEffects(data: ViewData, now: number)
	for index = #data.effects, 1, -1 do
		local effect = data.effects[index]
		if effect.expiresAt <= now then
			table.remove(data.effects, index)
			effect.part:Destroy()
		end
	end
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
			stepEffects(data, data.dependencies.now())
		end
	end)
	if not connected or typeof(connectionOrError) ~= "RBXScriptConnection" then
		disconnectAll(data.connections)
		return false
	end
	table.insert(data.connections, connectionOrError :: RBXScriptConnection)
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
		current = nil,
		lastAttackSequence = 0,
		lastFocusMode = nil,
		inputFamily = "Desktop",
		reducedMotion = false,
		lowEffects = false,
		renderCount = 0,
		actionCount = 0,
		cleaned = false,
		applyProductionStyle = applyProductionStyle,
		templateRoot = templateRoot,
		allowPrimitiveFallback = allowPrimitiveFallback,
	}
	DATA[view] = data
	if not connectAll(data) then
		instances.gui:Destroy()
		instances.worldFolder:Destroy()
		DATA[view] = nil
		return failure("CONNECTION_FAILED")
	end
	instances.readyOverlay.Visible = false
	instances.towerPanel.Visible = false
	instances.resultsOverlay.Visible = false
	instances.touchPlacementPanel.Visible = false
	instances.feedback.Visible = false
	return ok(view)
end

local function renderSnapshot(data: ViewData, snapshot: CanonicalSnapshot)
	local instances = data.instances
	local viewport = snapshot.viewport or Vector2.new(1280, 720)
	local layout = resolveResponsiveLayout(viewport.X, viewport.Y)
	if layout == nil then
		error("invalid responsive layout", 0)
	end
	if data.applyProductionStyle then
		applyLayout(instances, layout)
	end
	instances.uiScale.Scale = snapshot.uiScale or 1

	if snapshot.state == "Loading" then
		instances.waveLabel.Text = "◆ MATCH LOADING"
		instances.enemyLabel.Text = "♟ ENEMIES —"
		instances.baseButton.Text = "♥ BASE —"
		instances.cashLabel.Text = "$ BATTLE CASH —"
	else
		instances.waveLabel.Text = `◆ WAVE {snapshot.wave.current} / {snapshot.wave.total}`
		instances.enemyLabel.Text = `♟ ENEMIES {snapshot.wave.enemiesRemaining}`
		instances.baseButton.Text = `♥ BASE {snapshot.base.health} / {snapshot.base.maxHealth}`
		instances.cashLabel.Text = `$ {snapshot.battleCash} BATTLE CASH`
	end
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

	for slot, metadata in snapshot.hotbar do
		local button = instances.hotbarButtons[slot]
		local availabilityText = if metadata.available then "AVAILABLE" else (metadata.reason or "UNAVAILABLE")
		button.Text = `{slot} • {metadata.displayName}\n${metadata.cost} • {availabilityText}`
		button.BorderColor3 = if metadata.selected then COLORS.Good else COLORS.Muted
		button.BackgroundColor3 = if metadata.selected then COLORS.Selected else COLORS.Neutral
		setButtonEnabled(button, metadata.available and (snapshot.state == "PreWave" or snapshot.state == "WaveActive"))
	end
	local hint = snapshot.inputHint or defaultHint(snapshot)
	instances.hintLabel.Text = hint
	local placement = snapshot.placement
	instances.touchPlacementPanel.Visible = placement ~= nil
	if placement ~= nil then
		instances.touchPlacementStatus.Text = if placement.positionSelected
			then `✓ POSITION SELECTED • ROTATION {math.floor(placement.rotationDegrees + 0.5)}°`
			else "1. TAP THE MAP TO CHOOSE A POSITION"
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
			then "READY CHECK"
			else `STARTING IN {ready.countdownSeconds}s`
		instances.readyStatus.Text = ready.status or "Ready up when your defenses are planned."
		instances.readyHint.Text = hint
		setButtonEnabled(instances.readyButton, ready.enabled)
	end

	local selection = snapshot.selection
	instances.towerPanel.Visible = selection ~= nil
	if selection ~= nil then
		instances.towerTitle.Text = `▣ {selection.displayName} • LEVEL {selection.level}/{selection.maxLevel}`
		instances.towerStatus.Text = if selection.isOwner
			then "✓ YOUR TOWER — CONTROLS AVAILABLE"
			else "⌁ INSPECTION ONLY — OWNED BY ANOTHER PLAYER"
		instances.towerStatus.TextColor3 = if selection.isOwner then COLORS.Good else COLORS.Warning
		instances.towerStats.Text = `Damage {selection.damage}  •  Range {selection.range}\nCooldown {string.format(
			"%.2fs",
			selection.cooldownSeconds
		)}`
		instances.towerTarget.Text = `◎ TARGET: {string.upper(selection.targetMode)}`
		instances.upgradeButton.Text = if selection.upgradeCost == nil
			then "▲ MAX LEVEL"
			else `▲ UPGRADE\n${selection.upgradeCost}`
		instances.targetButton.Text = `◎ TARGET\n{nextTargetMode(selection.targetMode)}`
		instances.sellButton.Text = if selection.sellValue == nil then "$ SELL" else `$ SELL\n+${selection.sellValue}`
		setButtonEnabled(instances.upgradeButton, selection.canUpgrade)
		setButtonEnabled(instances.targetButton, selection.canRetarget)
		setButtonEnabled(instances.sellButton, selection.canSell)
		setButtonEnabled(instances.closeButton, true)
	end

	local result = snapshot.result
	instances.resultsOverlay.Visible = result ~= nil
	if result ~= nil then
		instances.resultTitle.Text = if result.kind == "Victory" then "✓ VICTORY" else "✕ DEFEAT"
		instances.resultTitle.TextColor3 = if result.kind == "Victory" then COLORS.Good else COLORS.Bad
		instances.resultSummary.Text = result.summary
		instances.resultHint.Text = result.status or hint
		setButtonEnabled(instances.replayButton, result.canReplay)
	else
		instances.resultTitle.Text = ""
		instances.resultSummary.Text = ""
		instances.resultHint.Text = ""
		setButtonEnabled(instances.replayButton, false)
	end

	local nextFocusMode = focusMode(snapshot)
	if snapshot.inputFamily == "Gamepad" and (data.inputFamily ~= "Gamepad" or data.lastFocusMode ~= nextFocusMode) then
		data.dependencies.selectObject(bestFocus(instances, snapshot))
	end
	data.lastFocusMode = nextFocusMode
	data.inputFamily = snapshot.inputFamily
	data.reducedMotion = snapshot.reducedMotion == true
	data.lowEffects = snapshot.lowEffects == true
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
	local rendered = pcall(renderSnapshot, data, canonical)
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
		if
			not safeId(id)
			or identifiers[id :: string]
			or not safeId(definitionId)
			or not finiteVector3(position)
			or (rotationDegrees ~= nil and (not finiteNumber(rotationDegrees) or math.abs(rotationDegrees :: number) > 360))
			or (selected ~= nil and type(selected) ~= "boolean")
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

function ViewMethods.syncWorld(self: View, value: unknown): Outcome<Metrics>
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
				stagedTowers[tower.id] = {
					model = model,
					primaryPart = primaryPart,
					definitionId = tower.definitionId,
					selection = makeSelectionHighlight(model, data.applyProductionStyle),
					isPrimitiveFallback = isPrimitiveFallback,
				}
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
				local healthFill, healthText = makeEnemyHealthDisplay(model, primaryPart, data.applyProductionStyle)
				stagedEnemies[enemy.id] = {
					model = model,
					primaryPart = primaryPart,
					definitionId = enemy.definitionId,
					healthFill = healthFill,
					healthText = healthText,
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
			local position = if record.isPrimitiveFallback
				then tower.position + Vector3.new(0, record.primaryPart.Size.Y * 0.5, 0)
				else tower.position
			local rotation = math.rad(tower.rotationDegrees or 0)
			pivotVisual(data, record.model, record.primaryPart, CFrame.new(position) * CFrame.Angles(0, rotation, 0))
			if record.selection ~= nil then
				record.selection.Enabled = tower.selected == true
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
				if data.applyProductionStyle then
					record.healthFill.Size = UDim2.fromScale(healthRatio, 1)
				end
				record.healthFill.BackgroundColor3 = if healthRatio <= 0.25
					then COLORS.Bad
					elseif healthRatio <= 0.5 then COLORS.Warning
					else COLORS.Good
				record.healthText.Text = `{math.ceil(enemy.health)} / {math.ceil(enemy.maxHealth)}`
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

local function attackPositions(data: ViewData, event: AttackEvent): (Vector3?, Vector3?)
	local origin = event.origin
	local target = event.target
	if origin == nil then
		local towerRecord = data.towerRecords[event.towerId]
		origin = if towerRecord == nil then nil else towerRecord.primaryPart.CFrame.Position
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
	}
	if
		not safeId(event.matchId)
		or not safeInteger(event.sequence, 1, 2 ^ 31 - 1)
		or not safeId(event.towerId)
		or not safeId(event.targetId)
		or (event.origin ~= nil and not finiteVector3(event.origin))
		or (event.target ~= nil and not finiteVector3(event.target))
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
	local created, partOrError = pcall(function(): Part
		stepEffects(data, data.dependencies.now())
		local maximum = if data.lowEffects then 8 else MAX_ATTACK_EFFECTS
		while #data.effects >= maximum do
			local oldest = table.remove(data.effects, 1)
			oldest.part:Destroy()
		end
		local effect = makeWorldPart("Attack", data.instances.effectFolder, data.applyProductionStyle)
		effect.Size = Vector3.new(0.12, 0.12, delta.Magnitude)
		effect.CFrame = CFrame.lookAt(origin + delta * 0.5, target)
		effect.Color = COLORS.Effect
		effect.Transparency = if data.reducedMotion then 0.35 else 0.12
		if data.applyProductionStyle then
			effect.Material = Enum.Material.Neon
		end
		return effect
	end)
	if not created then
		return failure("RENDER_FAILED")
	end
	local duration = if data.reducedMotion then 0.04 else EFFECT_DURATION_SECONDS
	table.insert(data.effects, {
		part = partOrError :: Part,
		expiresAt = data.dependencies.now() + duration,
	})
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
			baseText = "",
			cashText = "",
			feedbackText = "",
			readyVisible = false,
			towerPanelVisible = false,
			inspectionOnly = false,
			resultsVisible = false,
			resultKind = nil,
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
		baseText = instances.baseButton.Text,
		cashText = instances.cashLabel.Text,
		feedbackText = instances.feedback.Text,
		readyVisible = instances.readyOverlay.Visible,
		towerPanelVisible = instances.towerPanel.Visible,
		inspectionOnly = snapshot ~= nil and snapshot.selection ~= nil and not snapshot.selection.isOwner,
		resultsVisible = instances.resultsOverlay.Visible,
		resultKind = if snapshot == nil or snapshot.result == nil then nil else snapshot.result.kind,
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
	data.current = nil
	if not succeeded then
		return failure("CLEANUP_FAILED")
	end
	return ok(true)
end

local function productionDependencies(): Dependencies
	return {
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
		dependencies: Dependencies
	): ViewResult
		return construct(guiParent, worldParent, callback, dependencies, false, nil, true)
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
