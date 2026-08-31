--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AcquisitionProtocol = require(ReplicatedStorage.Shared.acquisition.AcquisitionProtocol)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local InventoryProtocol = require(ReplicatedStorage.Shared.inventory.InventoryProtocol)
local LobbyProtocol = require(ReplicatedStorage.Shared.lobby.LobbyProtocol)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local ProfileProtocol = require(ReplicatedStorage.Shared.profile.ProfileProtocol)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local SettingsProtocol = require(ReplicatedStorage.Shared.settings.SettingsProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Result = require(ReplicatedStorage.Shared.util.Result)

local function findClientModules(): (Instance, Instance)
	local clientRoot = script.Parent.Parent
	local commonUi = clientRoot:FindFirstChild("common")
	local lobbyUi = script.Parent:FindFirstChild("ui")
	if commonUi ~= nil then
		commonUi = commonUi:FindFirstChild("ui")
	end
	if commonUi ~= nil and lobbyUi ~= nil then
		return commonUi, lobbyUi
	end
	local automatedTests = script.Parent.Parent
	local mirroredCommon = automatedTests:FindFirstChild("ProductionClientCommonUi")
	local mirroredLobby = automatedTests:FindFirstChild("ProductionClientLobbyUi")
	if mirroredCommon == nil or mirroredLobby == nil then
		error("[ATD_LOBBY_CONTROLLER][code=UI_MODULES_MISSING]", 0)
	end
	return mirroredCommon, mirroredLobby
end

local commonUi, lobbyUi = findClientModules()
local NavigationStore = require(commonUi.NavigationStore)
local NotificationStore = require(commonUi.NotificationStore)
local LobbyView = require(lobbyUi.LobbyView)

export type LifecycleState =
	"Constructed"
	| "Initializing"
	| "Initialized"
	| "Starting"
	| "Started"
	| "ShuttingDown"
	| "Shutdown"
	| "Failed"

export type ResponseCallback = (boolean, unknown, string?) -> ()
export type ViewAdapter = {
	render: (self: ViewAdapter, unknown) -> any,
	getMetrics: (self: ViewAdapter) -> any,
	cleanup: (self: ViewAdapter) -> any,
}

export type Accessibility = { textScale: number, transparency: number }
export type Dependencies = {
	view: ViewAdapter,
	request: (string, unknown, ResponseCallback) -> boolean,
	cancel: (string) -> (),
	connectEvent: (string, (unknown, ...unknown) -> ()) -> RBXScriptConnection,
	connectStep: ((number) -> ()) -> RBXScriptConnection,
	now: () -> number,
	getViewport: () -> Vector2,
	getAccessibility: () -> Accessibility,
	getInputFamily: () -> LobbyView.InputFamily,
	newTransactionId: () -> string,
	applySettings: (ProfileProtocol.SettingsView) -> (),
	leave: () -> (),
	cleanupNetwork: () -> (),
}

export type ErrorCode = "INVALID_CONTEXT" | "INVALID_CONFIGURATION" | "INVALID_DEPENDENCIES"
export type ControllerError = { code: ErrorCode }
export type Metrics = {
	lifecycleState: LifecycleState,
	profileState: ProfileProtocol.ProfileState,
	revision: number,
	requestCount: number,
	rejectedResponseCount: number,
	renderCount: number,
	pendingCount: number,
	modalDepth: number,
	toastCount: number,
	selectedUnitId: string?,
	viewMetrics: unknown,
}

type Modal = {
	id: string,
	title: string,
	message: string,
	confirmText: string?,
	cancelText: string?,
	dismissable: boolean,
	busy: boolean,
}

type Pending = { startedAt: number, mutation: boolean }
type Factory = ((LobbyView.Action) -> ()) -> Dependencies

type ControllerData = {
	logger: Log.Logger,
	configuration: ConfigTypes.CoreConfiguration,
	factory: Factory,
	dependencies: Dependencies?,
	state: LifecycleState,
	connections: { RBXScriptConnection },
	generation: number,
	active: boolean,
	profile: ProfileProtocol.Snapshot,
	inventory: InventoryProtocol.Snapshot?,
	banner: AcquisitionProtocol.BannerView?,
	revision: number,
	inputFamily: LobbyView.InputFamily,
	selectedUnitId: string?,
	modals: { Modal },
	pendingChestQuantity: number?,
	pending: { [string]: Pending },
	mutationPending: boolean,
	navigation: NavigationStore.Store,
	notifications: NotificationStore.Store,
	lastProfilePoll: number,
	lastToastTick: number,
	requestCount: number,
	rejectedResponseCount: number,
	renderCount: number,
}

local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

export type Controller = typeof(setmetatable({} :: {}, ControllerMethods))
export type ControllerResult = Result.Result<Controller, ControllerError>

local SERVICE_NAME = "LobbyController"
local PROFILE_POLL_SECONDS = 2
local READY_REFRESH_SECONDS = 10
local REQUEST_TIMEOUT_SECONDS = 8
local TOAST_TICK_SECONDS = 0.25
local DEFAULT_VIEWPORT = Vector2.new(1280, 720)
local STARTER_BANNER_ID = "banner:starter"
local CHEST_RESULTS_MODAL_ID = "modal:chest-results:current"

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ControllerData }

local LobbyController = {
	SERVICE_NAME = SERVICE_NAME,
	PROFILE_POLL_SECONDS = PROFILE_POLL_SECONDS,
	REQUEST_TIMEOUT_SECONDS = REQUEST_TIMEOUT_SECONDS,
	newForTests = nil :: ((Log.Logger, ConfigTypes.CoreConfiguration, Dependencies) -> ControllerResult)?,
	invokeActionForTests = nil :: ((Controller, LobbyView.Action) -> ())?,
}

local function failure<T>(code: ErrorCode): Result.Failure<ControllerError>
	return Result.err(table.freeze({ code = code }))
end

local function requireData(value: unknown): ControllerData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_LOBBY_CONTROLLER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function success(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function pendingCount(data: ControllerData): number
	local count = 0
	for _ in data.pending do
		count += 1
	end
	return count
end

local function notify(data: ControllerData, kind: NotificationStore.Kind, title: string, message: string, key: string?)
	data.notifications:push({
		kind = kind,
		title = title,
		message = message,
		dedupeKey = key,
		durationSeconds = if kind == "Error" then 8 else 5,
	})
end

local function networkFailure(data: ControllerData, endpoint: string, code: string?)
	local message = if code == "RATE_LIMITED"
		then "That action is happening too quickly. Please wait a moment."
		elseif code == "STALE_REQUEST" then "Your profile changed. Refreshing the authoritative state."
		else "The Lobby server did not accept that request. Retrying safely."
	notify(
		data,
		if code == "STALE_REQUEST" then "Warning" else "Error",
		"Request not completed",
		message,
		`network:{endpoint}`
	)
end

local function popModal(data: ControllerData, expectedId: string?): boolean
	local top = data.modals[#data.modals]
	if top == nil or (expectedId ~= nil and top.id ~= expectedId) then
		return false
	end
	table.remove(data.modals)
	data.navigation:popModal()
	return true
end

local function pushModal(data: ControllerData, modal: Modal): boolean
	local pushed = data.navigation:pushModal(
		modal.id,
		`screen:{string.lower((data.navigation:getSnapshot() :: any).value.activeScreen)}`
	)
	if not pushed.ok then
		return false
	end
	table.insert(data.modals, table.freeze(modal))
	return true
end

local function replaceTopModal(data: ControllerData, modal: Modal)
	if #data.modals > 0 then
		data.modals[#data.modals] = table.freeze(modal)
	end
end

local function currentSettings(data: ControllerData): ProfileProtocol.SettingsView?
	return if data.profile.state == "Ready" then data.profile.settings else nil
end

local function settingsForView(settings: ProfileProtocol.SettingsView)
	return {
		masterVolume = settings.masterVolume,
		musicVolume = settings.musicVolume,
		sfxVolume = settings.sfxVolume,
		uiVolume = settings.uiVolume,
		cameraShakeIntensity = settings.cameraShakeIntensity,
		reducedMotionEnabled = settings.reducedMotionEnabled,
		damageNumbersEnabled = settings.damageNumbersEnabled,
		enemyHealthBarsEnabled = settings.enemyHealthBarsEnabled,
		otherPlayerEffectsEnabled = settings.otherPlayerEffectsEnabled,
		lowDetailEnabled = settings.lowDetailEnabled,
		towerRangeEnabled = settings.towerRangeEnabled,
		uiScale = settings.uiScale,
	}
end

local function attackStats(definition: ConfigTypes.TowerDefinition): (number, number, number)
	local level = definition.levels[1]
	local attack = level.attack
	if attack == nil then
		return 0, level.rangeStuds, 1
	end
	return attack.damage, level.rangeStuds, attack.cooldownSeconds
end

local function upgradePreview(definition: ConfigTypes.TowerDefinition): string
	local nextLevel = definition.levels[2]
	if nextLevel == nil then
		return ""
	end
	local attack = nextLevel.attack
	return if attack == nil
		then `Next: support range {nextLevel.rangeStuds}`
		else `Next: {attack.damage} damage • {nextLevel.rangeStuds} range • {attack.cooldownSeconds}s`
end

local function towerCards(data: ControllerData): { any }
	local inventory = data.inventory
	if inventory == nil then
		return {}
	end
	local counts: { [string]: number } = {}
	for _, entry in inventory.copyCounts do
		counts[entry.towerId] = entry.copies
	end
	local cards = table.create(#inventory.units)
	for index, unit in inventory.units do
		local definition = data.configuration.towers.byId[unit.towerId]
		if definition == nil then
			return {}
		end
		local damage, rangeStuds, cooldown = attackStats(definition)
		cards[index] = {
			unitId = unit.unitId,
			towerId = unit.towerId,
			displayName = definition.displayName,
			description = definition.description or "",
			acquisitionSource = if unit.unitId == "unit:starter-1"
				then "Starter Profile Grant"
				else "Starter Tower Chest • Earn-only Gold",
			copies = counts[unit.towerId] or 1,
			favorite = unit.favorite,
			locked = unit.locked,
			equippedSlot = unit.equippedSlot,
			placementCost = definition.placementCost,
			placementCap = definition.placementCap,
			damage = damage,
			rangeStuds = rangeStuds,
			cooldownSeconds = cooldown,
			targetModesText = table.concat(definition.supportedTargetModes, ", "),
			upgradePreview = upgradePreview(definition),
		}
	end
	return cards
end

local function bannerForView(data: ControllerData)
	local banner = data.banner
	if banner == nil then
		return nil
	end
	local odds = table.create(#banner.odds)
	for index, entry in banner.odds do
		local definition = data.configuration.towers.byId[entry.towerId]
		if definition == nil then
			return nil
		end
		odds[index] = {
			towerId = entry.towerId,
			displayName = definition.displayName,
			probabilityPercent = entry.probabilityPercent,
		}
	end
	local gold = if data.profile.state == "Ready" then data.profile.gold :: number else banner.gold
	return {
		bannerId = banner.bannerId,
		displayName = banner.displayName,
		onePullCost = banner.onePullCost,
		tenPullCost = banner.tenPullCost,
		pityCount = banner.currentPityCount,
		hardPityPullCount = banner.hardPityPullCount,
		odds = odds,
		earnOnly = banner.currencyPolicy == "EarnOnlyGold",
		canPullOne = banner.available and gold >= banner.onePullCost and not data.mutationPending,
		canPullTen = banner.available and gold >= banner.tenPullCost and not data.mutationPending,
		transactionPending = data.pending[LobbyProtocol.ENDPOINTS.PULL_CHEST] ~= nil,
	}
end

local function safeViewport(dependencies: Dependencies): Vector2
	local called, value = pcall(dependencies.getViewport)
	if called and typeof(value) == "Vector2" and value.X >= 240 and value.Y >= 320 then
		return value
	end
	return DEFAULT_VIEWPORT
end

local function safeAccessibility(dependencies: Dependencies): Accessibility
	local called, value = pcall(dependencies.getAccessibility)
	if
		called
		and type(value) == "table"
		and type(value.textScale) == "number"
		and value.textScale >= 0.85
		and value.textScale <= 1.5
		and type(value.transparency) == "number"
		and value.transparency >= 0
		and value.transparency <= 1
	then
		return value
	end
	return { textScale = 1, transparency = 0 }
end

local function render(data: ControllerData): boolean
	if not data.active or data.state ~= "Started" or data.dependencies == nil then
		return false
	end
	local dependencies = data.dependencies
	local navigation = data.navigation:getSnapshot()
	local toastSnapshot = data.notifications:getSnapshot()
	if not navigation.ok or not toastSnapshot.ok then
		return false
	end
	local access = safeAccessibility(dependencies)
	local effectiveReady = data.profile.state == "Ready" and data.inventory ~= nil
	local profileState: ProfileProtocol.ProfileState = if effectiveReady then "Ready" else data.profile.state
	if data.profile.state == "Ready" and not effectiveReady then
		profileState = "Loading"
	end
	local statusText = if data.profile.state == "Failed"
		then "Your profile could not be loaded safely. No writable fallback was created."
		elseif data.profile.state == "Releasing" then "Saving and releasing your protected profile session."
		elseif not effectiveReady then "Loading your protected profile and inventory…"
		elseif
			data.profile.migrationOutcome == "Created"
		then "Welcome! Your starter tower and earn-only Gold are ready."
		elseif data.profile.migrationOutcome == "Migrated" then "Welcome back. Your profile was migrated safely."
		else "Welcome back. Your saved loadout is ready."
	local toasts = table.create(#toastSnapshot.value)
	for index, entry in toastSnapshot.value do
		toasts[index] = {
			id = entry.id,
			kind = entry.kind,
			title = entry.title,
			message = entry.message,
			repeatCount = entry.repeatCount,
		}
	end
	local base = {
		profileState = profileState,
		screen = navigation.value.activeScreen,
		statusText = statusText,
		canRetry = data.profile.state == "Failed",
		canLeave = true,
		inputFamily = data.inputFamily,
		viewport = safeViewport(dependencies),
		preferredTextScale = access.textScale,
		preferredTransparency = access.transparency,
		reducedMotion = if effectiveReady
			then (data.profile.settings :: ProfileProtocol.SettingsView).reducedMotionEnabled
			else false,
		isFirstJoin = false,
		didMigrate = false,
		modals = if effectiveReady then data.modals else {},
		toasts = toasts,
	}
	if effectiveReady then
		local settings = data.profile.settings :: ProfileProtocol.SettingsView
		local readyState = base :: any
		readyState.profileRevision = data.revision
		readyState.gold = data.profile.gold
		readyState.progressionText = "Progression systems are coming later."
		readyState.isFirstJoin = data.profile.migrationOutcome == "Created"
			and (data.profile.tutorial :: ProfileProtocol.TutorialView).firstJoin
		readyState.didMigrate = data.profile.migrationOutcome == "Migrated"
		readyState.inventory = towerCards(data)
		readyState.selectedUnitId = data.selectedUnitId
		readyState.settings = settingsForView(settings)
		readyState.banner = bannerForView(data)
	end
	local rendered = dependencies.view:render(base)
	if not success(rendered) then
		return false
	end
	data.renderCount += 1
	return true
end

local function updateProfileRevision(data: ControllerData, revision: number)
	data.revision = math.max(data.revision, revision)
	if data.profile.state == "Ready" and (data.profile.revision :: number) < data.revision then
		local profile = data.profile :: any
		data.profile = table.freeze({
			state = "Ready",
			retryable = false,
			revision = data.revision,
			gold = profile.gold,
			settings = profile.settings,
			tutorial = profile.tutorial,
			stats = profile.stats,
			migrationOutcome = profile.migrationOutcome,
		})
	end
end

local issueProfile: (ControllerData) -> boolean
local issueInventory: (ControllerData) -> boolean
local issueBanner: (ControllerData) -> boolean

local function issueRequest(
	data: ControllerData,
	endpoint: string,
	payload: unknown,
	mutation: boolean,
	onSuccess: (unknown) -> boolean
): boolean
	if not data.active or data.dependencies == nil or data.pending[endpoint] ~= nil then
		return false
	end
	if mutation and data.mutationPending then
		return false
	end
	local generation = data.generation
	data.pending[endpoint] = { startedAt = data.dependencies.now(), mutation = mutation }
	if mutation then
		data.mutationPending = true
	end
	data.requestCount += 1
	local requested = data.dependencies.request(endpoint, payload, function(ok, value, code)
		if not data.active or generation ~= data.generation then
			return
		end
		local pending = data.pending[endpoint]
		if pending == nil then
			return
		end
		data.pending[endpoint] = nil
		if pending.mutation then
			data.mutationPending = false
		end
		if not ok or not onSuccess(value) then
			data.rejectedResponseCount += 1
			networkFailure(data, endpoint, code)
			if mutation then
				issueProfile(data)
				issueInventory(data)
				issueBanner(data)
			end
		end
		render(data)
	end)
	if not requested then
		data.pending[endpoint] = nil
		if mutation then
			data.mutationPending = false
		end
		networkFailure(data, endpoint, nil)
		return false
	end
	return true
end

local function applyProfile(data: ControllerData, value: unknown): boolean
	local validated = ProfileProtocol.validateSnapshot(value)
	if not validated.ok then
		return false
	end
	local snapshot = validated.value
	if snapshot.state == "Ready" then
		if snapshot.revision == nil or snapshot.revision < data.revision then
			return snapshot.revision ~= nil
		end
		data.profile = snapshot
		data.revision = snapshot.revision
		pcall((data.dependencies :: Dependencies).applySettings, snapshot.settings :: ProfileProtocol.SettingsView)
		issueInventory(data)
		issueBanner(data)
	else
		data.profile = snapshot
		data.inventory = nil
		data.banner = nil
		data.revision = 0
		data.selectedUnitId = nil
		table.clear(data.modals)
		while (data.navigation:getSnapshot() :: any).value.modals[1] ~= nil do
			data.navigation:popModal()
		end
	end
	return true
end

issueProfile = function(data: ControllerData): boolean
	data.lastProfilePoll = (data.dependencies :: Dependencies).now()
	return issueRequest(data, LobbyProtocol.ENDPOINTS.GET_PROFILE, {}, false, function(value)
		return applyProfile(data, value)
	end)
end

issueInventory = function(data: ControllerData): boolean
	if data.profile.state ~= "Ready" then
		return false
	end
	return issueRequest(data, LobbyProtocol.ENDPOINTS.GET_INVENTORY, {}, false, function(value)
		local validated = InventoryProtocol.validateSnapshot(value)
		if not validated.ok then
			return false
		end
		if validated.value.revision < data.revision then
			return true
		end
		if data.inventory == nil or validated.value.revision >= data.inventory.revision then
			data.inventory = validated.value
			updateProfileRevision(data, validated.value.revision)
		end
		return true
	end)
end

issueBanner = function(data: ControllerData): boolean
	if data.profile.state ~= "Ready" then
		return false
	end
	return issueRequest(
		data,
		LobbyProtocol.ENDPOINTS.GET_BANNER,
		{ bannerId = STARTER_BANNER_ID },
		false,
		function(value)
			local validated = AcquisitionProtocol.validateBannerView(value)
			if not validated.ok then
				return false
			end
			if validated.value.profileRevision < data.revision then
				return true
			end
			if data.banner == nil or validated.value.profileRevision >= data.banner.profileRevision then
				data.banner = validated.value
				updateProfileRevision(data, validated.value.profileRevision)
			end
			return true
		end
	)
end

local function applyInventoryReceipt(data: ControllerData, value: unknown): boolean
	local validated = InventoryProtocol.validateMutationReceipt(value)
	if not validated.ok then
		return false
	end
	data.inventory = validated.value.snapshot
	updateProfileRevision(data, validated.value.revision)
	notify(data, "Success", "Loadout saved", "Your inventory change was accepted by the server.", nil)
	issueProfile(data)
	return true
end

local function issueInventoryMutation(data: ControllerData, action: LobbyView.Action): boolean
	if data.profile.state ~= "Ready" or data.inventory == nil or action.unitId == nil then
		return false
	end
	local unit: InventoryProtocol.UnitView? = nil
	for _, candidate in data.inventory.units do
		if candidate.unitId == action.unitId then
			unit = candidate
			break
		end
	end
	if unit == nil then
		return false
	end
	local transactionId = (data.dependencies :: Dependencies).newTransactionId()
	local payload: any = {
		transactionId = transactionId,
		expectedRevision = data.revision,
		unitId = unit.unitId,
	}
	local endpoint: string
	if action.kind == "EquipTower" then
		endpoint = LobbyProtocol.ENDPOINTS.EQUIP_TOWER
		payload.slot = math.min(#data.inventory.equipped + 1, InventoryProtocol.MAX_LOADOUT_SLOTS)
	elseif action.kind == "UnequipTower" then
		endpoint = LobbyProtocol.ENDPOINTS.UNEQUIP_TOWER
	elseif action.kind == "ToggleFavorite" then
		endpoint = LobbyProtocol.ENDPOINTS.FAVORITE_TOWER
		payload.enabled = action.enabled == true
	else
		endpoint = LobbyProtocol.ENDPOINTS.LOCK_TOWER
		payload.enabled = action.enabled == true
	end
	return issueRequest(data, endpoint, payload, true, function(value)
		return applyInventoryReceipt(data, value)
	end)
end

local function pullCost(banner: AcquisitionProtocol.BannerView, quantity: number): number
	return if quantity == 10 then banner.tenPullCost else banner.onePullCost
end

local function openPullConfirmation(data: ControllerData, quantity: number): boolean
	local banner = data.banner
	if banner == nil or (quantity ~= 1 and quantity ~= 10) then
		return false
	end
	local cost = pullCost(banner, quantity)
	if not banner.available or (data.profile.gold :: number) < cost then
		notify(data, "Warning", "Not enough Gold", `This pull costs {cost} earn-only Gold.`, "chest:insufficient")
		return false
	end
	data.pendingChestQuantity = quantity
	return pushModal(data, {
		id = `modal:chest-confirm:{quantity}`,
		title = if quantity == 10 then "Confirm 10 pulls" else "Confirm 1 pull",
		message = `Spend {cost} earn-only Gold? Outcomes use the exact displayed server-owned odds and pity.`,
		confirmText = "Confirm",
		cancelText = "Cancel",
		dismissable = true,
		busy = false,
	})
end

local function pullResultsMessage(data: ControllerData, receipt: AcquisitionProtocol.PullReceipt): string
	local parts = table.create(#receipt.results)
	for index, outcome in receipt.results do
		local definition = data.configuration.towers.byId[outcome.towerId]
		parts[index] = `{index}. {if outcome.isNew then "NEW" else "DUPLICATE"}: {if definition == nil
			then outcome.towerId
			else definition.displayName}`
	end
	return table.concat(parts, "\n")
end

local function issuePull(data: ControllerData, quantity: number): boolean
	local banner = data.banner
	if banner == nil then
		return false
	end
	replaceTopModal(data, {
		id = `modal:chest-confirm:{quantity}`,
		title = "Opening chest…",
		message = "The server is committing Gold, outcomes, copies, and pity atomically.",
		confirmText = nil,
		cancelText = "Skip Animation",
		dismissable = true,
		busy = false,
	})
	local payload = {
		transactionId = (data.dependencies :: Dependencies).newTransactionId(),
		expectedRevision = data.revision,
		bannerId = banner.bannerId,
		bannerVersion = banner.bannerVersion,
		quantity = quantity,
	}
	return issueRequest(data, LobbyProtocol.ENDPOINTS.PULL_CHEST, payload, true, function(value)
		local validated = AcquisitionProtocol.validatePullReceipt(value)
		if not validated.ok then
			return false
		end
		local receipt = validated.value
		updateProfileRevision(data, receipt.profileRevision)
		if data.profile.state == "Ready" then
			local profile = data.profile :: any
			data.profile = table.freeze({
				state = "Ready",
				retryable = false,
				revision = receipt.profileRevision,
				gold = receipt.goldAfter,
				settings = profile.settings,
				tutorial = profile.tutorial,
				stats = profile.stats,
				migrationOutcome = profile.migrationOutcome,
			})
		end
		popModal(data, `modal:chest-confirm:{quantity}`)
		pushModal(data, {
			id = CHEST_RESULTS_MODAL_ID,
			title = if quantity == 10 then "10-pull results" else "Chest result",
			message = pullResultsMessage(data, receipt),
			confirmText = "Done",
			cancelText = nil,
			dismissable = true,
			busy = false,
		})
		notify(data, "Success", "Chest opened", `Spent {receipt.cost} Gold. Pity is now {receipt.pityAfter}.`, nil)
		data.pendingChestQuantity = nil
		issueProfile(data)
		issueInventory(data)
		issueBanner(data)
		return true
	end)
end

local SETTING_KEYS = table.freeze({
	masterVolume = true,
	musicVolume = true,
	sfxVolume = true,
	uiVolume = true,
	cameraShakeIntensity = true,
	damageNumbersEnabled = true,
	enemyHealthBarsEnabled = true,
	otherPlayerEffectsEnabled = true,
	lowDetailEnabled = true,
	towerRangeEnabled = true,
	uiScale = true,
	reducedMotionEnabled = true,
})

local function issueSetting(data: ControllerData, action: LobbyView.Action): boolean
	local current = currentSettings(data)
	local key = action.settingKey
	if current == nil or key == nil or not SETTING_KEYS[key] or action.settingValue == nil then
		return false
	end
	local nextSettings = table.clone(current) :: any
	nextSettings[key] = action.settingValue
	local payload = table.clone(nextSettings)
	payload.transactionId = (data.dependencies :: Dependencies).newTransactionId()
	payload.expectedRevision = data.revision
	local validatedIntent = SettingsProtocol.UpdateIntentSchema:validate(payload)
	if not validatedIntent.ok then
		return false
	end
	local previous = data.profile
	local profile = data.profile :: any
	data.profile = table.freeze({
		state = "Ready",
		retryable = false,
		revision = profile.revision,
		gold = profile.gold,
		settings = table.freeze(nextSettings),
		tutorial = profile.tutorial,
		stats = profile.stats,
		migrationOutcome = profile.migrationOutcome,
	})
	pcall((data.dependencies :: Dependencies).applySettings, nextSettings)
	render(data)
	local issued = issueRequest(
		data,
		LobbyProtocol.ENDPOINTS.UPDATE_SETTINGS,
		validatedIntent.value,
		true,
		function(value)
			local receipt = SettingsProtocol.validateUpdateReceipt(value)
			if not receipt.ok then
				return false
			end
			local accepted = receipt.value
			updateProfileRevision(data, accepted.revision)
			local currentProfile = data.profile :: any
			data.profile = table.freeze({
				state = "Ready",
				retryable = false,
				revision = accepted.revision,
				gold = currentProfile.gold,
				settings = accepted.settings,
				tutorial = currentProfile.tutorial,
				stats = currentProfile.stats,
				migrationOutcome = currentProfile.migrationOutcome,
			})
			pcall((data.dependencies :: Dependencies).applySettings, accepted.settings)
			notify(data, "Success", "Settings saved", "Your settings were saved to your profile.", "settings:saved")
			return true
		end
	)
	if not issued then
		data.profile = previous
		pcall((data.dependencies :: Dependencies).applySettings, previous.settings :: ProfileProtocol.SettingsView)
	end
	return issued
end

local function onAction(data: ControllerData, action: LobbyView.Action)
	if not data.active or data.state ~= "Started" or type(action) ~= "table" then
		return
	end
	if action.kind == "InputFamilyChanged" and action.inputFamily ~= nil then
		data.inputFamily = action.inputFamily
	elseif action.kind == "Navigate" and action.screen ~= nil then
		data.navigation:setPrimary(action.screen)
	elseif action.kind == "Back" then
		local backed = data.navigation:back()
		if backed.ok and backed.value.kind == "ModalClosed" then
			local top = data.modals[#data.modals]
			if top ~= nil and top.id == backed.value.modalId and not top.busy then
				table.remove(data.modals)
				data.pendingChestQuantity = nil
			end
		end
	elseif action.kind == "RetryProfile" and data.profile.state == "Failed" then
		issueRequest(data, LobbyProtocol.ENDPOINTS.RETRY_PROFILE, {}, false, function(value)
			return applyProfile(data, value)
		end)
	elseif action.kind == "SafeLeave" then
		pcall((data.dependencies :: Dependencies).leave)
	elseif action.kind == "Play" and data.profile.state == "Ready" then
		pushModal(data, {
			id = "modal:play-ready",
			title = "Loadout ready",
			message = "Your saved loadout is ready for the local Match. Parties, queues, and travel are intentionally not enabled yet.",
			confirmText = "OK",
			cancelText = nil,
			dismissable = true,
			busy = false,
		})
	elseif action.kind == "SelectTower" then
		data.selectedUnitId = action.unitId
	elseif action.kind == "CloseTowerDetails" then
		data.selectedUnitId = nil
	elseif
		action.kind == "EquipTower"
		or action.kind == "UnequipTower"
		or action.kind == "ToggleFavorite"
		or action.kind == "ToggleLock"
	then
		issueInventoryMutation(data, action)
	elseif action.kind == "PullChest" and action.quantity ~= nil then
		openPullConfirmation(data, action.quantity)
	elseif action.kind == "ConfirmModal" then
		local top = data.modals[#data.modals]
		if top ~= nil and top.id == action.modalId and not top.busy then
			if string.sub(top.id, 1, 20) == "modal:chest-confirm:" and data.pendingChestQuantity ~= nil then
				issuePull(data, data.pendingChestQuantity)
			else
				popModal(data, top.id)
			end
		end
	elseif action.kind == "CancelModal" then
		local top = data.modals[#data.modals]
		if top ~= nil and top.id == action.modalId and top.dismissable and not top.busy then
			popModal(data, top.id)
			data.pendingChestQuantity = nil
		end
	elseif action.kind == "SkipChestPresentation" then
		local top = data.modals[#data.modals]
		if
			top ~= nil
			and not top.busy
			and (string.sub(top.id, 1, 20) == "modal:chest-confirm:" or top.id == CHEST_RESULTS_MODAL_ID)
		then
			popModal(data, top.id)
		end
	elseif action.kind == "DismissToast" and action.toastId ~= nil then
		data.notifications:dismiss(action.toastId)
	elseif action.kind == "UpdateSetting" then
		issueSetting(data, action)
	end
	render(data)
end

local function validateDependencies(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local record = value :: any
	return type(record.view) == "table"
		and type(record.view.render) == "function"
		and type(record.view.getMetrics) == "function"
		and type(record.view.cleanup) == "function"
		and type(record.request) == "function"
		and type(record.cancel) == "function"
		and type(record.connectEvent) == "function"
		and type(record.connectStep) == "function"
		and type(record.now) == "function"
		and type(record.getViewport) == "function"
		and type(record.getAccessibility) == "function"
		and type(record.getInputFamily) == "function"
		and type(record.newTransactionId) == "function"
		and type(record.applySettings) == "function"
		and type(record.leave) == "function"
		and type(record.cleanupNetwork) == "function"
end

local function addConnection(data: ControllerData, value: unknown): boolean
	if typeof(value) ~= "RBXScriptConnection" then
		return false
	end
	table.insert(data.connections, value :: RBXScriptConnection)
	return true
end

local function initialize(data: ControllerData)
	if data.state ~= "Constructed" then
		error("[ATD_LOBBY_CONTROLLER][code=INVALID_INITIALIZE_STATE]", 0)
	end
	data.state = "Initializing"
	local created, dependencies = pcall(data.factory, function(action)
		onAction(data, action)
	end)
	if not created or not validateDependencies(dependencies) then
		data.state = "Failed"
		error("[ATD_LOBBY_CONTROLLER][code=INITIALIZE_FAILED]", 0)
	end
	data.dependencies = dependencies :: Dependencies
	local familyOk, family = pcall((dependencies :: Dependencies).getInputFamily)
	if familyOk and (family == "Desktop" or family == "Touch" or family == "Gamepad") then
		data.inputFamily = family
	end
	data.state = "Initialized"
end

local function onStep(data: ControllerData)
	if not data.active or data.dependencies == nil then
		return
	end
	local now = data.dependencies.now()
	local mutationTimedOut = false
	for endpoint, pending in data.pending do
		if now - pending.startedAt >= REQUEST_TIMEOUT_SECONDS then
			data.dependencies.cancel(endpoint)
			data.pending[endpoint] = nil
			data.mutationPending = if pending.mutation then false else data.mutationPending
			data.rejectedResponseCount += 1
			networkFailure(data, endpoint, nil)
			mutationTimedOut = mutationTimedOut or pending.mutation
		end
	end
	if mutationTimedOut then
		issueProfile(data)
		issueInventory(data)
		issueBanner(data)
	end
	local interval = if data.profile.state == "Ready" then READY_REFRESH_SECONDS else PROFILE_POLL_SECONDS
	if data.pending[LobbyProtocol.ENDPOINTS.GET_PROFILE] == nil and now - data.lastProfilePoll >= interval then
		issueProfile(data)
	end
	if now - data.lastToastTick >= TOAST_TICK_SECONDS then
		data.lastToastTick = now
		local ticked = data.notifications:tick()
		if ticked.ok and ticked.value > 0 then
			render(data)
		end
	end
end

local function start(data: ControllerData)
	if data.state ~= "Initialized" or data.dependencies == nil then
		error("[ATD_LOBBY_CONTROLLER][code=INVALID_START_STATE]", 0)
	end
	data.state = "Starting"
	data.generation += 1
	local generation = data.generation
	data.active = true
	local dependencies = data.dependencies
	local profileConnection = dependencies.connectEvent(
		LobbyProtocol.ENDPOINTS.PROFILE_REPLICATION,
		function(value, ...)
			if data.active and data.generation == generation then
				local parsed = RequestProtocol.parseEvent(value, ...)
				if not parsed.ok or not applyProfile(data, parsed.value.payload) then
					data.rejectedResponseCount += 1
					issueProfile(data)
				end
				render(data)
			end
		end
	)
	local inventoryConnection = dependencies.connectEvent(
		LobbyProtocol.ENDPOINTS.INVENTORY_REPLICATION,
		function(value, ...)
			if not data.active or data.generation ~= generation then
				return
			end
			local parsed = RequestProtocol.parseEvent(value, ...)
			local validated = if parsed.ok then InventoryProtocol.validateSnapshot(parsed.value.payload) else nil
			if validated ~= nil and validated.ok and validated.value.revision >= data.revision then
				data.inventory = validated.value
				updateProfileRevision(data, validated.value.revision)
			else
				data.rejectedResponseCount += 1
				issueInventory(data)
			end
			render(data)
		end
	)
	local stepConnection = dependencies.connectStep(function()
		onStep(data)
	end)
	if
		not addConnection(data, profileConnection)
		or not addConnection(data, inventoryConnection)
		or not addConnection(data, stepConnection)
	then
		error("[ATD_LOBBY_CONTROLLER][code=START_FAILED]", 0)
	end
	data.state = "Started"
	data.lastProfilePoll = dependencies.now()
	render(data)
	issueProfile(data)
end

local function cleanup(data: ControllerData): boolean
	if data.state == "Shutdown" then
		return true
	end
	data.state = "ShuttingDown"
	data.active = false
	data.generation += 1
	local failed = false
	if data.dependencies ~= nil then
		for endpoint in data.pending do
			pcall((data.dependencies :: Dependencies).cancel, endpoint)
		end
		table.clear(data.pending)
		for index = #data.connections, 1, -1 do
			if not pcall(function()
				data.connections[index]:Disconnect()
			end) then
				failed = true
			end
		end
		table.clear(data.connections)
		if not pcall((data.dependencies :: Dependencies).cleanupNetwork) then
			failed = true
		end
		local viewCleaned, viewResult = pcall(function()
			return (data.dependencies :: Dependencies).view:cleanup()
		end)
		if not viewCleaned or not success(viewResult) then
			failed = true
		end
	end
	data.navigation:cleanup()
	data.notifications:cleanup()
	table.clear(data.modals)
	data.inventory = nil
	data.banner = nil
	data.dependencies = nil
	data.state = "Shutdown"
	return not failed
end

local function construct(
	logger: Log.Logger,
	configuration: ConfigTypes.CoreConfiguration,
	factory: Factory
): ControllerResult
	if not Log.isLogger(logger) then
		return failure("INVALID_CONTEXT")
	end
	if not ConfigurationValidator.isValidatedConfiguration(configuration) then
		return failure("INVALID_CONFIGURATION")
	end
	if type(factory) ~= "function" then
		return failure("INVALID_DEPENDENCIES")
	end
	local navigationResult = NavigationStore.new("Home")
	local notificationResult = NotificationStore.new(os.clock)
	if not navigationResult.ok or not notificationResult.ok then
		return failure("INVALID_DEPENDENCIES")
	end
	local controller = setmetatable({}, ControllerMethods) :: Controller
	table.freeze(controller)
	DATA[controller] = {
		logger = logger,
		configuration = configuration,
		factory = factory,
		dependencies = nil,
		state = "Constructed",
		connections = {},
		generation = 0,
		active = false,
		profile = ProfileProtocol.status("Loading"),
		inventory = nil,
		banner = nil,
		revision = 0,
		inputFamily = "Desktop",
		selectedUnitId = nil,
		modals = {},
		pendingChestQuantity = nil,
		pending = {},
		mutationPending = false,
		navigation = navigationResult.value,
		notifications = notificationResult.value,
		lastProfilePoll = 0,
		lastToastTick = 0,
		requestCount = 0,
		rejectedResponseCount = 0,
		renderCount = 0,
	}
	return Result.ok(controller)
end

function ControllerMethods.getServiceDefinition(self: Controller): ServiceLifecycle.ServiceDefinition
	local data = requireData(self)
	return table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({}),
		initialize = function()
			initialize(data)
		end,
		start = function()
			start(data)
		end,
		shutdown = function()
			if not cleanup(data) then
				error("[ATD_LOBBY_CONTROLLER][code=CLEANUP_FAILED]", 0)
			end
		end,
	})
end

function ControllerMethods.getMetrics(self: Controller): Metrics
	local data = requireData(self)
	local viewMetrics: unknown = nil
	if data.dependencies ~= nil then
		pcall(function()
			viewMetrics = (data.dependencies :: Dependencies).view:getMetrics()
		end)
	end
	local toasts = data.notifications:getSnapshot()
	return table.freeze({
		lifecycleState = data.state,
		profileState = data.profile.state,
		revision = data.revision,
		requestCount = data.requestCount,
		rejectedResponseCount = data.rejectedResponseCount,
		renderCount = data.renderCount,
		pendingCount = pendingCount(data),
		modalDepth = #data.modals,
		toastCount = if toasts.ok then #toasts.value else 0,
		selectedUnitId = data.selectedUnitId,
		viewMetrics = viewMetrics,
	})
end

type RequestEndpoint = {
	definition: RemoteRegistry.Definition,
	request: RemoteEvent,
	response: RemoteEvent,
}

local REQUEST_SPECS = table.freeze({
	{ LobbyProtocol.ENDPOINTS.GET_PROFILE, LobbyProtocol.EmptyPayloadSchema, ProfileProtocol.SnapshotSchema },
	{ LobbyProtocol.ENDPOINTS.RETRY_PROFILE, LobbyProtocol.EmptyPayloadSchema, ProfileProtocol.SnapshotSchema },
	{ LobbyProtocol.ENDPOINTS.GET_INVENTORY, LobbyProtocol.EmptyPayloadSchema, InventoryProtocol.SnapshotSchema },
	{
		LobbyProtocol.ENDPOINTS.EQUIP_TOWER,
		InventoryProtocol.EquipIntentSchema,
		InventoryProtocol.MutationReceiptSchema,
	},
	{
		LobbyProtocol.ENDPOINTS.UNEQUIP_TOWER,
		InventoryProtocol.UnitMutationIntentSchema,
		InventoryProtocol.MutationReceiptSchema,
	},
	{
		LobbyProtocol.ENDPOINTS.FAVORITE_TOWER,
		InventoryProtocol.ToggleIntentSchema,
		InventoryProtocol.MutationReceiptSchema,
	},
	{
		LobbyProtocol.ENDPOINTS.LOCK_TOWER,
		InventoryProtocol.ToggleIntentSchema,
		InventoryProtocol.MutationReceiptSchema,
	},
	{ LobbyProtocol.ENDPOINTS.GET_BANNER, LobbyProtocol.BannerRequestSchema, AcquisitionProtocol.BannerViewSchema },
	{ LobbyProtocol.ENDPOINTS.PULL_CHEST, AcquisitionProtocol.PullIntentSchema, AcquisitionProtocol.PullReceiptSchema },
	{
		LobbyProtocol.ENDPOINTS.UPDATE_SETTINGS,
		SettingsProtocol.UpdateIntentSchema,
		SettingsProtocol.UpdateReceiptSchema,
	},
})

local function inputFamily(): LobbyView.InputFamily
	local inputType = UserInputService:GetLastInputType()
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.sub(inputType.Name, 1, 7) == "Gamepad" then
		return "Gamepad"
	end
	return "Desktop"
end

local function makeProductionFactory(): Factory
	return function(actionCallback)
		local clientRoot = script.Parent.Parent
		local common = clientRoot:FindFirstChild("common")
		local networking = if common == nil then nil else common:FindFirstChild("networking")
		if networking == nil then
			error("[ATD_LOBBY_CONTROLLER][code=NETWORKING_MISSING]", 0)
		end
		local ClientRemoteLookup =
			require((networking :: Instance):FindFirstChild("ClientRemoteLookup") :: ModuleScript)
		local ClientRequestTracker =
			require((networking :: Instance):FindFirstChild("ClientRequestTracker") :: ModuleScript)
		local trackerResult = ClientRequestTracker.new()
		if not success(trackerResult) then
			error("[ATD_LOBBY_CONTROLLER][code=TRACKER_CREATION_FAILED]", 0)
		end
		local tracker = trackerResult.value
		local endpoints: { [string]: RequestEndpoint } = {}
		local callbacks: { [string]: ResponseCallback } = {}
		local pendings: { [string]: any } = {}
		local responseConnections: { RBXScriptConnection } = {}
		for _, spec in REQUEST_SPECS do
			local name = spec[1] :: string
			local registered = tracker:register(name, spec[2], spec[3])
			local lookup = ClientRemoteLookup.resolve(name, 5)
			if not success(registered) or not success(lookup) then
				error("[ATD_LOBBY_CONTROLLER][code=REMOTE_LOOKUP_FAILED]", 0)
			end
			local resolved = lookup.value
			if resolved.request == nil or resolved.response == nil or resolved.event ~= nil then
				error("[ATD_LOBBY_CONTROLLER][code=REMOTE_SHAPE_INVALID]", 0)
			end
			local endpoint: RequestEndpoint = {
				definition = resolved.definition,
				request = resolved.request,
				response = resolved.response,
			}
			endpoints[name] = endpoint
			table.insert(
				responseConnections,
				endpoint.response.OnClientEvent:Connect(function(value, ...)
					local handled = tracker:handleResponse(endpoint.definition, value, ...)
					if not success(handled) then
						return
					end
					local callback = callbacks[name]
					if callback == nil then
						return
					end
					callbacks[name] = nil
					pendings[name] = nil
					local response = handled.value
					if RequestProtocol.isSuccess(response) then
						callback(true, (response :: RequestProtocol.Success).payload, nil)
					else
						callback(false, nil, (response :: RequestProtocol.Rejected).error.code)
					end
				end)
			)
		end
		local eventEndpoints: { [string]: RemoteEvent } = {}
		for _, name in { LobbyProtocol.ENDPOINTS.PROFILE_REPLICATION, LobbyProtocol.ENDPOINTS.INVENTORY_REPLICATION } do
			local lookup = ClientRemoteLookup.resolve(name, 5)
			if not success(lookup) or lookup.value.event == nil or lookup.value.request ~= nil then
				error("[ATD_LOBBY_CONTROLLER][code=EVENT_LOOKUP_FAILED]", 0)
			end
			eventEndpoints[name] = lookup.value.event
		end
		local viewResult = LobbyView.new(actionCallback)
		if not success(viewResult) then
			for _, connection in responseConnections do
				connection:Disconnect()
			end
			tracker:clear()
			error("[ATD_LOBBY_CONTROLLER][code=VIEW_CREATION_FAILED]", 0)
		end
		local function applySettings(settings: ProfileProtocol.SettingsView)
			for name, volume in
				{
					Music = settings.masterVolume * settings.musicVolume,
					SFX = settings.masterVolume * settings.sfxVolume,
					UI = settings.masterVolume * settings.uiVolume,
				}
			do
				local group = SoundService:FindFirstChild(name)
				if group ~= nil and group:IsA("SoundGroup") then
					group.Volume = volume
				end
			end
		end
		return {
			view = viewResult.value,
			request = function(name, payload, callback)
				local endpoint = endpoints[name]
				if endpoint == nil or callbacks[name] ~= nil then
					return false
				end
				local built = tracker:buildRequest(name, payload)
				if not success(built) or not RequestProtocol.isPending(built.value.pending) then
					return false
				end
				callbacks[name] = callback
				pendings[name] = built.value.pending
				local fired = pcall(endpoint.request.FireServer, endpoint.request, built.value.envelope)
				if not fired then
					tracker:cancel(built.value.pending)
					callbacks[name] = nil
					pendings[name] = nil
				end
				return fired
			end,
			cancel = function(name)
				local pending = pendings[name]
				if pending ~= nil then
					tracker:cancel(pending)
				end
				callbacks[name] = nil
				pendings[name] = nil
			end,
			connectEvent = function(name, callback)
				return (eventEndpoints[name] :: RemoteEvent).OnClientEvent:Connect(callback)
			end,
			connectStep = function(callback)
				return RunService.RenderStepped:Connect(callback)
			end,
			now = os.clock,
			getViewport = function()
				local camera = Workspace.CurrentCamera
				return if camera == nil then DEFAULT_VIEWPORT else camera.ViewportSize
			end,
			getAccessibility = function()
				local textScale = 1
				local transparency = 0
				pcall(function()
					local userGameSettings = UserSettings():GetService("UserGameSettings") :: any
					local preferred = userGameSettings.PreferredTextSize
					local name = if typeof(preferred) == "EnumItem" then preferred.Name else "Medium"
					textScale = if name == "Small"
						then 0.9
						elseif name == "Large" then 1.15
						elseif name == "Larger" then 1.3
						else 1
					local preferredTransparency = userGameSettings.PreferredTransparency
					if type(preferredTransparency) == "number" then
						transparency = math.clamp(preferredTransparency, 0, 1)
					end
				end)
				return { textScale = textScale, transparency = transparency }
			end,
			getInputFamily = inputFamily,
			newTransactionId = function()
				return `transaction:{string.lower(HttpService:GenerateGUID(false))}`
			end,
			applySettings = applySettings,
			leave = function()
				local player = Players.LocalPlayer
				if player ~= nil then
					player:Kick("Your profile was not changed. Please rejoin when you are ready.")
				end
			end,
			cleanupNetwork = function()
				for _, connection in responseConnections do
					connection:Disconnect()
				end
				table.clear(responseConnections)
				table.clear(callbacks)
				table.clear(pendings)
				tracker:clear()
			end,
		}
	end
end

function LobbyController.new(logger: Log.Logger, configuration: ConfigTypes.CoreConfiguration): ControllerResult
	return construct(logger, configuration, makeProductionFactory())
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "LobbyController" then
		return false
	end
	local container = script.Parent
	return container ~= nil
		and container:IsA("Folder")
		and container.Name == "ProductionClientLobby"
		and container.Parent ~= nil
		and container.Parent:IsA("Folder")
		and container.Parent.Name == "AutomatedTests"
		and container.Parent.Parent == ServerStorage
end

if isExactTestModule() then
	LobbyController.newForTests = function(
		logger: Log.Logger,
		configuration: ConfigTypes.CoreConfiguration,
		dependencies: Dependencies
	): ControllerResult
		if not validateDependencies(dependencies) then
			return failure("INVALID_DEPENDENCIES")
		end
		return construct(logger, configuration, function(_callback)
			return dependencies
		end)
	end
	LobbyController.invokeActionForTests = function(controller: Controller, action: LobbyView.Action)
		onAction(requireData(controller), action)
	end
end

table.freeze(ControllerMethods)
return table.freeze(LobbyController)
