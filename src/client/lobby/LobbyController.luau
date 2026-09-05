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
local ContentSelection = require(ReplicatedStorage.Shared.config.ContentSelection)
local InventoryProtocol = require(ReplicatedStorage.Shared.inventory.InventoryProtocol)
local LobbyProtocol = require(ReplicatedStorage.Shared.lobby.LobbyProtocol)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local PartyProtocol = require(ReplicatedStorage.Shared.party.PartyProtocol)
local ProfileProtocol = require(ReplicatedStorage.Shared.profile.ProfileProtocol)
local TutorialProtocol = require(ReplicatedStorage.Shared.profile.TutorialProtocol)
local QueueProtocol = require(ReplicatedStorage.Shared.queue.QueueProtocol)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local SettingsProtocol = require(ReplicatedStorage.Shared.settings.SettingsProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

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

local Localization = require(ReplicatedStorage.Shared.localization.Localization)
local Accessibility = require(ReplicatedStorage.Shared.settings.Accessibility)

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

export type Accessibility =
	{ textScale: number, textPreference: string?, transparency: number, reducedMotion: boolean? }
export type Dependencies = {
	presentation: any?,
	view: ViewAdapter,
	request: (string, unknown, ResponseCallback) -> boolean,
	cancel: (string) -> (),
	connectEvent: (string, (unknown, ...unknown) -> ()) -> RBXScriptConnection,
	connectStep: ((number) -> ()) -> RBXScriptConnection,
	now: () -> number,
	getViewport: () -> Vector2,
	getAccessibility: () -> Accessibility,
	getInputFamily: () -> LobbyView.InputFamily,
	getLocalUserId: () -> number,
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
type LobbyUiModelSquadState = "Loading" | "Ready" | "Failed"

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
	localUserId: number,
	partyState: LobbyUiModelSquadState,
	partySnapshot: PartyProtocol.ViewerSnapshot?,
	queuesState: LobbyUiModelSquadState,
	queueSnapshots: { QueueProtocol.Snapshot }?,
	activeRouteState: LobbyUiModelSquadState,
	activeRoute: LobbyProtocol.ActiveRouteView?,
	selectedQueueId: string?,
	revision: number,
	inputFamily: LobbyView.InputFamily,
	selectedUnitId: string?,
	modals: { Modal },
	pendingChestQuantity: number?,
	pending: { [string]: Pending },
	mutationPending: boolean,
	navigation: NavigationStore.Store,
	activeScreen: LobbyView.PrimaryScreen,
	notifications: NotificationStore.Store,
	lastProfilePoll: number,
	lastToastTick: number,
	lastUiSignature: string,
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
local RELEASE_BANNER_ID = ContentSelection.RELEASE_BANNER_ID
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
		then Localization.text("lobby_controller.that_action_is_happening_too_quickly_please")
		elseif code == "STALE_REQUEST" then Localization.text(
			"lobby_controller.your_party_queue_or_profile_changed_refreshing"
		)
		else Localization.text("lobby_controller.the_lobby_server_did_not_accept_that")
	notify(
		data,
		if code == "STALE_REQUEST" then "Warning" else "Error",
		Localization.text("lobby_controller.request_not_completed"),
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
	local pushed = data.navigation:pushModal(modal.id, `screen:{string.lower(data.activeScreen)}`)
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
		then Localization.text("lobby_controller.next_support_range", { rangeStuds = nextLevel.rangeStuds })
		else Localization.text(
			"lobby_controller.next_damage_range_s",
			{ damage = attack.damage, rangeStuds = nextLevel.rangeStuds, cooldownSeconds = attack.cooldownSeconds }
		)
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
	local starterUnitIds: { [string]: boolean } = {}
	for _, unitId in ContentSelection.STARTER_UNIT_IDS do
		starterUnitIds[unitId] = true
	end
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
			description = Localization.contentDescription(definition.id, definition.description),
			acquisitionSource = if starterUnitIds[unit.unitId] == true
				then Localization.text("lobby_controller.starter_profile_grant")
				else Localization.text("lobby_controller.earn_only_tower_chest"),
			copies = counts[unit.towerId] or 1,
			favorite = unit.favorite,
			locked = unit.locked,
			equippedSlot = unit.equippedSlot,
			placementCost = definition.placementCost,
			placementCap = definition.placementCap,
			damage = damage,
			rangeStuds = rangeStuds,
			cooldownSeconds = cooldown,
			targetModesText = table.concat(
				(function()
					local labels = {}
					for _, mode in definition.supportedTargetModes do
						table.insert(labels, Localization.enum("target", mode))
					end
					return labels
				end)(),
				", "
			),
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
		policyDisclosure = Localization.contentPolicy(banner.bannerId, banner.policyDisclosure),
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

local function tagged(tags: { string }?, wanted: string): boolean
	for _, tag in tags or {} do
		if tag == wanted then
			return true
		end
	end
	return false
end

local function queueMapOptions(data: ControllerData): { any }
	local options = table.create(#data.configuration.maps.ordered)
	for _, map in data.configuration.maps.ordered do
		local selectableMap = not tagged(map.tags, "hidden") and not tagged(map.tags, "development")
		local difficulties = table.create(#map.supportedDifficultyIds)
		for _, difficultyId in map.supportedDifficultyIds do
			local difficulty = data.configuration.difficulties.byId[difficultyId]
			if difficulty ~= nil then
				table.insert(difficulties, {
					difficultyId = difficulty.id,
					displayName = difficulty.displayName,
					selectable = selectableMap
						and not tagged(difficulty.tags, "hidden")
						and not tagged(difficulty.tags, "development"),
				})
			end
		end
		table.insert(options, {
			mapId = map.id,
			displayName = map.displayName,
			selectable = selectableMap,
			difficulties = difficulties,
		})
	end
	return options
end

local function tutorialGuidance(data: ControllerData): any?
	if data.profile.state ~= "Ready" or data.profile.tutorial == nil then
		return nil
	end
	local tutorial = data.profile.tutorial :: ProfileProtocol.TutorialView
	local step = math.clamp(tutorial.tutorialStep, 0, TutorialProtocol.COMPLETE_STEP)
	if tutorial.version == nil then
		return nil
	end
	local title = Localization.text("lobby_controller.getting_started")
	local message = Localization.text("lobby_controller.preparing_your_permanent_starter_loadout_safely")
	local primaryActionText: string? = nil
	local canAdvance = false
	local canReplay = false
	if step == 1 then
		title = Localization.text("lobby_controller.gold_and_battle_cash")
		message = Localization.text("lobby_controller.gold_is_permanent_and_opens_earn_only")
		primaryActionText = Localization.text("lobby_controller.got_it")
		canAdvance = true
	elseif step == 2 then
		title = Localization.text("lobby_controller.starter_loadout")
		message = Localization.text("lobby_controller.your_server_validated_attacking_loadout_is_ready")
		primaryActionText = Localization.text("lobby_controller.loadout_ready")
		canAdvance = true
	elseif step == 3 then
		title = Localization.text("lobby_controller.enter_your_first_defense")
		message = Localization.text("lobby_controller.open_queue_choose_backyard_garden_on_easy")
	elseif step == 4 then
		title = Localization.text("lobby_controller.start_when_ready")
		message = Localization.text("lobby_controller.your_solo_easy_queue_is_ready_start")
	elseif step == 5 then
		title = Localization.text("lobby_controller.place_a_tower")
		message = Localization.text("lobby_controller.choose_a_starter_tower_and_place_it")
	elseif step == 6 then
		title = Localization.text("lobby_controller.upgrade_a_tower")
		message = Localization.text("lobby_controller.select_one_of_your_placed_towers_and")
	elseif step == 7 then
		title = Localization.text("lobby_controller.finish_the_run")
		message = Localization.text("lobby_controller.keep_defending_a_durable_server_result_not")
	elseif step == 8 then
		title = Localization.text("lobby_controller.return_safely")
		message = Localization.text("lobby_controller.return_to_the_lobby_your_onboarding_completes")
	elseif step == TutorialProtocol.COMPLETE_STEP then
		title = if tutorial.skipped == true
			then Localization.text("lobby_controller.onboarding_skipped")
			else Localization.text("lobby_controller.onboarding_complete")
		message = Localization.text("lobby_controller.need_a_refresher_replay_the_concise_guide")
		primaryActionText = Localization.text("lobby_controller.replay_help")
		canReplay = true
	end
	return {
		step = step,
		title = title,
		message = message,
		primaryActionText = primaryActionText,
		canAdvance = canAdvance,
		canSkip = step >= 1 and step < TutorialProtocol.COMPLETE_STEP,
		canReplay = canReplay,
	}
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
	local viewport = safeViewport(dependencies)
	data.lastUiSignature = tostring(viewport)
		.. ":"
		.. tostring(access.textScale)
		.. ":"
		.. tostring(access.textPreference)
		.. ":"
		.. tostring(access.transparency)
		.. ":"
		.. tostring(access.reducedMotion)
		.. ":"
		.. Localization.getMode()
	local effectiveReady = data.profile.state == "Ready" and data.inventory ~= nil
	local profileState: ProfileProtocol.ProfileState = if effectiveReady then "Ready" else data.profile.state
	if data.profile.state == "Ready" and not effectiveReady then
		profileState = "Loading"
	end
	local statusText = if data.profile.state == "Failed"
		then Localization.text("lobby_controller.your_profile_could_not_be_loaded_safely")
		elseif data.profile.state == "Releasing" then Localization.text(
			"lobby_controller.saving_and_releasing_your_protected_profile_session"
		)
		elseif not effectiveReady then Localization.text(
			"lobby_controller.loading_your_protected_profile_and_inventory"
		)
		elseif data.profile.migrationOutcome == "Created" then Localization.text(
			"lobby_controller.welcome_your_starter_towers_and_earn_only"
		)
		elseif data.profile.migrationOutcome == "Migrated" then Localization.text(
			"lobby_controller.welcome_back_your_profile_was_migrated_safely"
		)
		else Localization.text("lobby_controller.welcome_back_your_saved_loadout_is_ready")
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
		screen = data.activeScreen,
		statusText = statusText,
		canRetry = data.profile.state == "Failed",
		canLeave = true,
		inputFamily = data.inputFamily,
		viewport = viewport,
		preferredTextScale = access.textScale,
		preferredTransparency = access.transparency,
		reducedMotion = if effectiveReady
			then (data.profile.settings :: ProfileProtocol.SettingsView).reducedMotionEnabled or access.reducedMotion == true
			else access.reducedMotion == true,
		isFirstJoin = false,
		didMigrate = false,
		localUserId = data.localUserId,
		partyState = data.partyState,
		partySnapshot = data.partySnapshot,
		queuesState = data.queuesState,
		queueSnapshots = data.queueSnapshots,
		selectedQueueId = data.selectedQueueId,
		activeRouteState = data.activeRouteState,
		activeRoute = data.activeRoute,
		squadMutationPending = data.mutationPending,
		modals = if effectiveReady then data.modals else {},
		toasts = toasts,
		tutorialGuidance = tutorialGuidance(data),
		queueMapOptions = queueMapOptions(data),
	}
	if effectiveReady then
		local settings = data.profile.settings :: ProfileProtocol.SettingsView
		local readyState = base :: any
		readyState.profileRevision = data.revision
		readyState.gold = data.profile.gold
		readyState.progressionText = Localization.text("lobby_controller.progression_systems_are_coming_later")
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
			firstClears = profile.firstClears,
			migrationOutcome = profile.migrationOutcome,
		})
	end
end

local issueProfile: (ControllerData) -> boolean
local issueInventory: (ControllerData) -> boolean
local issueBanner: (ControllerData) -> boolean
local issueParty: (ControllerData) -> boolean
local issueQueues: (ControllerData) -> boolean
local issueActiveRoute: (ControllerData) -> boolean

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
				issueParty(data)
				issueQueues(data)
				issueActiveRoute(data)
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

local function issueTutorialMutation(data: ControllerData, endpoint: string): boolean
	if data.profile.state ~= "Ready" then
		return false
	end
	local transactionId = (data.dependencies :: Dependencies).newTransactionId()
	return issueRequest(
		data,
		endpoint,
		{
			transactionId = transactionId,
			expectedRevision = data.revision,
		},
		true,
		function(value)
			local validated = TutorialProtocol.validateMutationReceipt(value)
			if not validated.ok or validated.value.transactionId ~= transactionId then
				return false
			end
			local profile = data.profile :: any
			data.profile = table.freeze({
				state = "Ready",
				retryable = false,
				revision = validated.value.revision,
				gold = profile.gold,
				settings = profile.settings,
				tutorial = validated.value.tutorial,
				stats = profile.stats,
				firstClears = profile.firstClears,
				migrationOutcome = profile.migrationOutcome,
			})
			updateProfileRevision(data, validated.value.revision)
			if validated.value.changed then
				notify(
					data,
					"Success",
					Localization.text("lobby_controller.guide_updated"),
					Localization.text("lobby_controller.your_onboarding_progress_was_saved"),
					"tutorial:updated"
				)
			end
			return true
		end
	)
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
		if data.partyState ~= "Ready" then
			issueParty(data)
		end
		if data.queuesState ~= "Ready" then
			issueQueues(data)
		end
		if data.activeRouteState ~= "Ready" then
			issueActiveRoute(data)
		end
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
		{ bannerId = RELEASE_BANNER_ID },
		false,
		function(value)
			local validated = AcquisitionProtocol.validateBannerView(value)
			if not validated.ok then
				return false
			end
			if validated.value.bannerId ~= RELEASE_BANNER_ID then
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

local function selectUsefulQueue(data: ControllerData, queues: { QueueProtocol.Snapshot })
	if data.selectedQueueId ~= nil then
		for _, queue in queues do
			if queue.queueId == data.selectedQueueId then
				return
			end
		end
	end
	for _, queue in queues do
		for _, member in queue.members do
			if member.userId == data.localUserId then
				data.selectedQueueId = queue.queueId
				return
			end
		end
	end
	data.selectedQueueId = if queues[1] == nil then nil else queues[1].queueId
end

local function applyQueueList(data: ControllerData, value: unknown): boolean
	local validated = LobbyProtocol.validateQueueList(value)
	if not validated.ok then
		return false
	end
	data.queuesState = "Ready"
	data.queueSnapshots = validated.value.queues
	selectUsefulQueue(data, validated.value.queues)
	return true
end

local function applyQueueSnapshot(data: ControllerData, value: unknown): boolean
	local validated = QueueProtocol.validateSnapshot(value)
	if not validated.ok then
		return false
	end
	local queues = {} :: { QueueProtocol.Snapshot }
	local replaced = false
	for _, queue in data.queueSnapshots or {} do
		if queue.queueId == validated.value.queueId then
			table.insert(queues, validated.value)
			replaced = true
		else
			table.insert(queues, queue)
		end
	end
	if not replaced then
		table.insert(queues, validated.value)
	end
	table.sort(queues, function(left, right)
		return left.queueId < right.queueId
	end)
	return applyQueueList(data, { version = LobbyProtocol.VERSION, queues = queues })
end

issueParty = function(data: ControllerData): boolean
	return issueRequest(data, LobbyProtocol.ENDPOINTS.GET_PARTY, {}, false, function(value)
		local validated = PartyProtocol.validateViewerSnapshot(value)
		if not validated.ok then
			data.partyState = "Failed"
			data.partySnapshot = nil
			return false
		end
		data.partyState = "Ready"
		data.partySnapshot = validated.value
		return true
	end)
end

issueQueues = function(data: ControllerData): boolean
	return issueRequest(data, LobbyProtocol.ENDPOINTS.GET_QUEUES, {}, false, function(value)
		if not applyQueueList(data, value) then
			data.queuesState = "Failed"
			data.queueSnapshots = nil
			data.selectedQueueId = nil
			return false
		end
		return true
	end)
end

issueActiveRoute = function(data: ControllerData): boolean
	return issueRequest(data, LobbyProtocol.ENDPOINTS.GET_ACTIVE_ROUTE, {}, false, function(value)
		local validated = LobbyProtocol.validateActiveRoute(value)
		if not validated.ok then
			data.activeRouteState = "Failed"
			data.activeRoute = nil
			return false
		end
		data.activeRouteState = "Ready"
		data.activeRoute = validated.value
		return true
	end)
end

local function currentParty(data: ControllerData): PartyProtocol.PartyView?
	return if data.partySnapshot == nil then nil else data.partySnapshot.party
end

local function currentQueue(data: ControllerData): QueueProtocol.Snapshot?
	if data.queueSnapshots == nil or data.selectedQueueId == nil then
		return nil
	end
	for _, queue in data.queueSnapshots do
		if queue.queueId == data.selectedQueueId then
			return queue
		end
	end
	return nil
end

local function applyPartyReceipt(
	data: ControllerData,
	value: unknown,
	transactionId: string,
	successMessage: string
): boolean
	local validated = PartyProtocol.validateMutationReceipt(value)
	if not validated.ok or validated.value.transactionId ~= transactionId then
		return false
	end
	data.partyState = "Ready"
	data.partySnapshot = validated.value.snapshot
	if validated.value.changed then
		notify(data, "Success", Localization.text("lobby_controller.party_updated"), successMessage, nil)
	end
	return true
end

local function issuePartyMutation(
	data: ControllerData,
	endpoint: string,
	payload: { [string]: any },
	successMessage: string
): boolean
	local transactionId = (data.dependencies :: Dependencies).newTransactionId()
	payload.transactionId = transactionId
	return issueRequest(data, endpoint, payload, true, function(value)
		return applyPartyReceipt(data, value, transactionId, successMessage)
	end)
end

local function applyQueueReceipt(
	data: ControllerData,
	value: unknown,
	transactionId: string,
	successMessage: string
): boolean
	local validated = QueueProtocol.validateMutationReceipt(value)
	if not validated.ok or validated.value.transactionId ~= transactionId then
		return false
	end
	local current = data.queueSnapshots or {}
	local queues = table.create(math.max(#current, 1)) :: { QueueProtocol.Snapshot }
	local replaced = false
	for _, queue in current do
		if queue.queueId == validated.value.snapshot.queueId then
			table.insert(queues, validated.value.snapshot)
			replaced = true
		else
			table.insert(queues, queue)
		end
	end
	if not replaced then
		table.insert(queues, validated.value.snapshot)
	end
	table.sort(queues, function(left, right)
		return left.queueId < right.queueId
	end)
	local list = LobbyProtocol.validateQueueList({ version = LobbyProtocol.VERSION, queues = queues })
	if not list.ok then
		return false
	end
	data.queuesState = "Ready"
	data.queueSnapshots = list.value.queues
	data.selectedQueueId = validated.value.snapshot.queueId
	if validated.value.changed then
		notify(data, "Success", Localization.text("lobby_controller.queue_updated"), successMessage, nil)
	end
	return true
end

local function issueQueueMutation(
	data: ControllerData,
	endpoint: string,
	payload: { [string]: any },
	successMessage: string
): boolean
	local transactionId = (data.dependencies :: Dependencies).newTransactionId()
	payload.transactionId = transactionId
	return issueRequest(data, endpoint, payload, true, function(value)
		return applyQueueReceipt(data, value, transactionId, successMessage)
	end)
end

local function issueInvitePrompt(data: ControllerData): boolean
	local party = currentParty(data)
	if party == nil then
		return false
	end
	local transactionId = (data.dependencies :: Dependencies).newTransactionId()
	return issueRequest(
		data,
		LobbyProtocol.ENDPOINTS.PROMPT_PARTY_INVITE,
		{
			transactionId = transactionId,
			expectedRevision = party.revision,
		},
		true,
		function(value)
			local validated = LobbyProtocol.InvitePromptReceiptSchema:validate(value)
			if not validated.ok or (validated.value :: any).transactionId ~= transactionId then
				return false
			end
			local status = (validated.value :: any).status
			if status == "Opened" then
				notify(
					data,
					"Info",
					Localization.text("lobby_controller.invite_friends"),
					Localization.text("lobby_controller.the_roblox_invite_prompt_is_open"),
					"party:prompt-open"
				)
			elseif status == "Denied" then
				notify(
					data,
					"Warning",
					Localization.text("lobby_controller.invite_unavailable"),
					Localization.text("lobby_controller.invite_permission_was_denied_you_can_still"),
					"party:prompt-denied"
				)
			else
				notify(
					data,
					"Warning",
					Localization.text("lobby_controller.invite_unavailable"),
					Localization.text("lobby_controller.the_roblox_invite_prompt_is_unavailable_here"),
					"party:prompt-unavailable"
				)
			end
			return true
		end
	)
end

local function issueReconnect(data: ControllerData): boolean
	if data.activeRoute == nil or data.activeRoute.status ~= "Available" then
		return false
	end
	local transactionId = (data.dependencies :: Dependencies).newTransactionId()
	return issueRequest(
		data,
		LobbyProtocol.ENDPOINTS.RECONNECT_ACTIVE_MATCH,
		{
			transactionId = transactionId,
		},
		true,
		function(value)
			local validated = LobbyProtocol.validateReconnectReceipt(value)
			if not validated.ok or validated.value.transactionId ~= transactionId then
				return false
			end
			data.activeRouteState = "Ready"
			data.activeRoute = validated.value.route
			if validated.value.status == "Initializing" then
				notify(
					data,
					"Info",
					"Reconnecting",
					Localization.text("lobby_controller.the_server_is_safely_reconnecting_you_to"),
					"route:initializing"
				)
			elseif validated.value.status == "Stale" then
				notify(
					data,
					"Warning",
					Localization.text("lobby_controller.reconnect_expired"),
					Localization.text("lobby_controller.that_match_route_is_stale_you_remain"),
					"route:stale"
				)
			else
				notify(
					data,
					"Error",
					Localization.text("lobby_controller.reconnect_failed"),
					Localization.text("lobby_controller.the_match_could_not_be_reached_you"),
					"route:failed"
				)
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
	notify(
		data,
		"Success",
		Localization.text("lobby_controller.loadout_saved"),
		Localization.text("lobby_controller.your_inventory_change_was_accepted_by_the"),
		nil
	)
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
		notify(
			data,
			"Warning",
			Localization.text("lobby_controller.not_enough_gold"),
			Localization.text("lobby_controller.this_pull_costs_earn_only_gold", { cost = cost }),
			"chest:insufficient"
		)
		return false
	end
	data.pendingChestQuantity = quantity
	return pushModal(data, {
		id = `modal:chest-confirm:{quantity}`,
		title = if quantity == 10
			then Localization.text("lobby_controller.confirm_10_pulls")
			else Localization.text("lobby_controller.confirm_1_pull"),
		message = Localization.text("lobby_controller.spend_earn_only_gold_outcomes_use_the", { cost = cost }),
		confirmText = Localization.text("lobby.chest.confirm"),
		cancelText = Localization.text("lobby.chest.cancel"),
		dismissable = true,
		busy = false,
	})
end

local function pullResultsMessage(data: ControllerData, receipt: AcquisitionProtocol.PullReceipt): string
	local parts = table.create(#receipt.results)
	for index, outcome in receipt.results do
		local definition = data.configuration.towers.byId[outcome.towerId]
		parts[index] = if definition == nil
			then Localization.text(
				if outcome.isNew then "lobby.chest.unknown_new_result" else "lobby.chest.unknown_duplicate_result",
				{ index = index }
			)
			else Localization.text(
				if outcome.isNew then "lobby.chest.new_result" else "lobby.chest.duplicate_result",
				{
					index = index,
					towerName = definition.displayName,
				}
			)
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
		title = Localization.text("lobby_controller.opening_chest"),
		message = Localization.text("lobby_controller.the_server_is_committing_gold_outcomes_copies"),
		confirmText = nil,
		cancelText = Localization.text("lobby_controller.skip_animation"),
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
		local presentation = (data.dependencies :: Dependencies).presentation
		if presentation ~= nil then
			pcall(function()
				presentation:reward()
			end)
		end
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
				firstClears = profile.firstClears,
				migrationOutcome = profile.migrationOutcome,
			})
		end
		popModal(data, `modal:chest-confirm:{quantity}`)
		pushModal(data, {
			id = CHEST_RESULTS_MODAL_ID,
			title = if quantity == 10
				then Localization.text("lobby_controller.10_pull_results")
				else Localization.text("lobby_controller.chest_result"),
			message = pullResultsMessage(data, receipt),
			confirmText = Localization.text("lobby.chest.done"),
			cancelText = nil,
			dismissable = true,
			busy = false,
		})
		notify(
			data,
			"Success",
			Localization.text("lobby_controller.chest_opened"),
			Localization.text(
				"lobby_controller.spent_gold_pity_is_now",
				{ cost = receipt.cost, pityAfter = receipt.pityAfter }
			),
			nil
		)
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
		firstClears = profile.firstClears,
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
				firstClears = currentProfile.firstClears,
				migrationOutcome = currentProfile.migrationOutcome,
			})
			pcall((data.dependencies :: Dependencies).applySettings, accepted.settings)
			notify(
				data,
				"Success",
				Localization.text("lobby_controller.settings_saved"),
				Localization.text("lobby_controller.your_settings_were_saved_to_your_profile"),
				"settings:saved"
			)
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
	if action.kind ~= "InputFamilyChanged" then
		local presentation = (data.dependencies :: Dependencies).presentation
		if presentation ~= nil then
			pcall(function()
				presentation:selection()
			end)
		end
	end
	if action.kind == "InputFamilyChanged" and action.inputFamily ~= nil then
		data.inputFamily = action.inputFamily
	elseif action.kind == "Navigate" and action.screen ~= nil then
		if action.screen == "Party" or action.screen == "Queue" then
			if #data.modals == 0 then
				data.activeScreen = action.screen
			end
		else
			local changed = data.navigation:setPrimary(action.screen)
			if changed.ok then
				data.activeScreen = action.screen
			end
		end
		if action.screen == "Party" and data.partyState ~= "Ready" then
			issueParty(data)
		elseif action.screen == "Queue" and data.queuesState ~= "Ready" then
			issueQueues(data)
		end
	elseif action.kind == "Back" then
		local backed = if #data.modals == 0 and (data.activeScreen == "Party" or data.activeScreen == "Queue")
			then nil
			else data.navigation:back()
		if backed == nil then
			data.activeScreen = "Home"
			data.navigation:setPrimary("Home")
		elseif backed.ok and backed.value.kind == "ScreenChanged" then
			data.activeScreen = (data.navigation:getSnapshot() :: any).value.activeScreen
		end
		if backed ~= nil and backed.ok and backed.value.kind == "ModalClosed" then
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
		if #data.modals == 0 then
			data.activeScreen = "Queue"
		end
	elseif action.kind == "AdvanceTutorial" then
		issueTutorialMutation(data, LobbyProtocol.ENDPOINTS.ADVANCE_TUTORIAL)
	elseif action.kind == "SkipTutorial" then
		issueTutorialMutation(data, LobbyProtocol.ENDPOINTS.SKIP_TUTORIAL)
	elseif action.kind == "ReplayTutorial" then
		issueTutorialMutation(data, LobbyProtocol.ENDPOINTS.REPLAY_TUTORIAL)
	elseif action.kind == "SelectQueue" and action.queueId ~= nil and data.queueSnapshots ~= nil then
		for _, queue in data.queueSnapshots do
			if queue.queueId == action.queueId then
				data.selectedQueueId = queue.queueId
				break
			end
		end
	elseif action.kind == "ReconnectActiveMatch" then
		if data.profile.state == "Ready" and data.inventory ~= nil then
			issueReconnect(data)
		else
			notify(
				data,
				"Warning",
				Localization.text("lobby_controller.profile_not_ready"),
				Localization.text("lobby_controller.reconnect_begins_only_after_protected_profile_acquisition"),
				"route:profile-not-ready"
			)
		end
	elseif
		action.kind == "CreateParty"
		or action.kind == "InvitePartyMember"
		or action.kind == "AcceptPartyInvite"
		or action.kind == "DeclinePartyInvite"
		or action.kind == "LeaveParty"
		or action.kind == "KickPartyMember"
		or action.kind == "TransferPartyLeadership"
		or action.kind == "TogglePartyPrivacy"
		or action.kind == "DisbandParty"
		or action.kind == "PromptPartyInvite"
		or action.kind == "JoinQueue"
		or action.kind == "LeaveQueue"
		or action.kind == "ConfigureQueue"
		or action.kind == "StartQueue"
	then
		if data.profile.state ~= "Ready" or data.inventory == nil then
			notify(
				data,
				"Warning",
				Localization.text("lobby_controller.profile_not_ready"),
				Localization.text("lobby_controller.party_and_queue_changes_unlock_after_your"),
				"squad:profile-not-ready"
			)
		elseif action.kind == "CreateParty" then
			issuePartyMutation(data, LobbyProtocol.ENDPOINTS.CREATE_PARTY, {
				expectedRevision = 0,
				privacy = "InviteOnly",
			}, Localization.text("lobby_controller.your_same_server_party_was_created"))
		elseif action.kind == "AcceptPartyInvite" or action.kind == "DeclinePartyInvite" then
			local invitation: PartyProtocol.InvitationView? = nil
			if data.partySnapshot ~= nil and action.invitationId ~= nil then
				for _, candidate in data.partySnapshot.incomingInvitations do
					if candidate.invitationId == action.invitationId then
						invitation = candidate
						break
					end
				end
			end
			if invitation ~= nil then
				issuePartyMutation(
					data,
					if action.kind == "AcceptPartyInvite"
						then LobbyProtocol.ENDPOINTS.ACCEPT_PARTY_INVITE
						else LobbyProtocol.ENDPOINTS.DECLINE_PARTY_INVITE,
					{
						expectedRevision = invitation.partyRevision,
						invitationId = invitation.invitationId,
					},
					if action.kind == "AcceptPartyInvite"
						then Localization.text("lobby_controller.you_joined_the_party")
						else Localization.text("lobby_controller.the_invitation_was_declined")
				)
			end
		else
			local party = currentParty(data)
			local queue = currentQueue(data)
			if action.kind == "InvitePartyMember" and party ~= nil and action.targetUserId ~= nil then
				issuePartyMutation(data, LobbyProtocol.ENDPOINTS.INVITE_PARTY, {
					expectedRevision = party.revision,
					targetUserId = action.targetUserId,
				}, Localization.text("lobby_controller.the_bounded_invitation_was_sent"))
			elseif action.kind == "LeaveParty" and party ~= nil then
				issuePartyMutation(data, LobbyProtocol.ENDPOINTS.LEAVE_PARTY, {
					expectedRevision = party.revision,
				}, Localization.text("lobby_controller.you_left_the_party"))
			elseif action.kind == "KickPartyMember" and party ~= nil and action.targetUserId ~= nil then
				issuePartyMutation(data, LobbyProtocol.ENDPOINTS.KICK_PARTY_MEMBER, {
					expectedRevision = party.revision,
					targetUserId = action.targetUserId,
				}, Localization.text("lobby_controller.the_member_was_removed"))
			elseif action.kind == "TransferPartyLeadership" and party ~= nil and action.targetUserId ~= nil then
				issuePartyMutation(data, LobbyProtocol.ENDPOINTS.TRANSFER_PARTY_LEADERSHIP, {
					expectedRevision = party.revision,
					targetUserId = action.targetUserId,
				}, Localization.text("lobby_controller.party_leadership_was_transferred"))
			elseif action.kind == "TogglePartyPrivacy" and party ~= nil then
				issuePartyMutation(data, LobbyProtocol.ENDPOINTS.SET_PARTY_PRIVACY, {
					expectedRevision = party.revision,
					privacy = if party.privacy == "InviteOnly" then "FriendsOnly" else "InviteOnly",
				}, Localization.text("lobby_controller.party_privacy_was_updated"))
			elseif action.kind == "DisbandParty" and party ~= nil then
				issuePartyMutation(data, LobbyProtocol.ENDPOINTS.DISBAND_PARTY, {
					expectedRevision = party.revision,
				}, Localization.text("lobby_controller.the_party_was_disbanded"))
			elseif action.kind == "PromptPartyInvite" then
				issueInvitePrompt(data)
			elseif action.kind == "JoinQueue" and queue ~= nil then
				issueQueueMutation(data, LobbyProtocol.ENDPOINTS.JOIN_QUEUE, {
					expectedRevision = queue.revision,
					queueId = queue.queueId,
					source = "UI",
				}, Localization.text("lobby_controller.you_entered_the_queue_through_the_accessible"))
			elseif action.kind == "LeaveQueue" and queue ~= nil then
				issueQueueMutation(data, LobbyProtocol.ENDPOINTS.LEAVE_QUEUE, {
					expectedRevision = queue.revision,
					queueId = queue.queueId,
				}, Localization.text("lobby_controller.your_enrollment_left_the_queue_cleanly"))
			elseif action.kind == "ConfigureQueue" and queue ~= nil and action.configuration ~= nil then
				issueQueueMutation(data, LobbyProtocol.ENDPOINTS.CONFIGURE_QUEUE, {
					expectedRevision = queue.revision,
					queueId = queue.queueId,
					configuration = action.configuration,
				}, Localization.text("lobby_controller.the_captain_configuration_was_saved"))
			elseif action.kind == "StartQueue" and queue ~= nil then
				issueQueueMutation(data, LobbyProtocol.ENDPOINTS.START_QUEUE, {
					expectedRevision = queue.revision,
					queueId = queue.queueId,
				}, Localization.text("lobby_controller.the_squad_is_locked_and_travel_initialization"))
			end
		end
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
		and type(record.getLocalUserId) == "function"
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
	local userOk, userId = pcall((dependencies :: Dependencies).getLocalUserId)
	if
		not userOk
		or type(userId) ~= "number"
		or not Validation.isSafeInteger(userId :: number)
		or (userId :: number) < 1
	then
		data.state = "Failed"
		error("[ATD_LOBBY_CONTROLLER][code=LOCAL_USER_INVALID]", 0)
	end
	data.localUserId = userId
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
		issueParty(data)
		issueQueues(data)
		issueActiveRoute(data)
	end
	local interval = if data.profile.state == "Ready" then READY_REFRESH_SECONDS else PROFILE_POLL_SECONDS
	if data.pending[LobbyProtocol.ENDPOINTS.GET_PROFILE] == nil and now - data.lastProfilePoll >= interval then
		issueProfile(data)
	end
	if now - data.lastToastTick >= TOAST_TICK_SECONDS then
		data.lastToastTick = now
		local ticked = data.notifications:tick()
		local access = safeAccessibility(data.dependencies)
		local signature = tostring(safeViewport(data.dependencies))
			.. ":"
			.. tostring(access.textScale)
			.. ":"
			.. tostring(access.textPreference)
			.. ":"
			.. tostring(access.transparency)
			.. ":"
			.. tostring(access.reducedMotion)
			.. ":"
			.. Localization.getMode()
		if (ticked.ok and ticked.value > 0) or signature ~= data.lastUiSignature then
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
	local partyConnection = dependencies.connectEvent(LobbyProtocol.ENDPOINTS.PARTY_REPLICATION, function(value, ...)
		if not data.active or data.generation ~= generation then
			return
		end
		local parsed = RequestProtocol.parseEvent(value, ...)
		local validated = if parsed.ok then PartyProtocol.validateViewerSnapshot(parsed.value.payload) else nil
		if validated ~= nil and validated.ok then
			data.partyState = "Ready"
			data.partySnapshot = validated.value
		else
			data.rejectedResponseCount += 1
			issueParty(data)
		end
		render(data)
	end)
	local queueConnection = dependencies.connectEvent(LobbyProtocol.ENDPOINTS.QUEUE_REPLICATION, function(value, ...)
		if not data.active or data.generation ~= generation then
			return
		end
		local parsed = RequestProtocol.parseEvent(value, ...)
		if not parsed.ok or not applyQueueSnapshot(data, parsed.value.payload) then
			data.rejectedResponseCount += 1
			issueQueues(data)
		end
		render(data)
	end)
	local routeConnection = dependencies.connectEvent(
		LobbyProtocol.ENDPOINTS.ACTIVE_ROUTE_REPLICATION,
		function(value, ...)
			if not data.active or data.generation ~= generation then
				return
			end
			local parsed = RequestProtocol.parseEvent(value, ...)
			local validated = if parsed.ok then LobbyProtocol.validateActiveRoute(parsed.value.payload) else nil
			if validated ~= nil and validated.ok then
				data.activeRouteState = "Ready"
				data.activeRoute = validated.value
			else
				data.rejectedResponseCount += 1
				issueActiveRoute(data)
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
		or not addConnection(data, partyConnection)
		or not addConnection(data, queueConnection)
		or not addConnection(data, routeConnection)
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
	data.partySnapshot = nil
	data.queueSnapshots = nil
	data.activeRoute = nil
	data.selectedQueueId = nil
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
		localUserId = 1,
		partyState = "Loading",
		partySnapshot = nil,
		queuesState = "Loading",
		queueSnapshots = nil,
		activeRouteState = "Loading",
		activeRoute = nil,
		selectedQueueId = nil,
		revision = 0,
		inputFamily = "Desktop",
		selectedUnitId = nil,
		modals = {},
		pendingChestQuantity = nil,
		pending = {},
		mutationPending = false,
		navigation = navigationResult.value,
		activeScreen = "Home",
		notifications = notificationResult.value,
		lastProfilePoll = 0,
		lastToastTick = 0,
		lastUiSignature = "",
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
	{
		LobbyProtocol.ENDPOINTS.ADVANCE_TUTORIAL,
		LobbyProtocol.TutorialActionIntentSchema,
		LobbyProtocol.TutorialMutationReceiptSchema,
	},
	{
		LobbyProtocol.ENDPOINTS.SKIP_TUTORIAL,
		LobbyProtocol.TutorialActionIntentSchema,
		LobbyProtocol.TutorialMutationReceiptSchema,
	},
	{
		LobbyProtocol.ENDPOINTS.REPLAY_TUTORIAL,
		LobbyProtocol.TutorialActionIntentSchema,
		LobbyProtocol.TutorialMutationReceiptSchema,
	},
	{ LobbyProtocol.ENDPOINTS.GET_PARTY, LobbyProtocol.EmptyPayloadSchema, PartyProtocol.ViewerSnapshotSchema },
	{ LobbyProtocol.ENDPOINTS.CREATE_PARTY, PartyProtocol.CreateIntentSchema, PartyProtocol.MutationReceiptSchema },
	{ LobbyProtocol.ENDPOINTS.INVITE_PARTY, PartyProtocol.InviteIntentSchema, PartyProtocol.MutationReceiptSchema },
	{
		LobbyProtocol.ENDPOINTS.ACCEPT_PARTY_INVITE,
		PartyProtocol.InvitationIntentSchema,
		PartyProtocol.MutationReceiptSchema,
	},
	{
		LobbyProtocol.ENDPOINTS.DECLINE_PARTY_INVITE,
		PartyProtocol.InvitationIntentSchema,
		PartyProtocol.MutationReceiptSchema,
	},
	{ LobbyProtocol.ENDPOINTS.LEAVE_PARTY, PartyProtocol.RevisionIntentSchema, PartyProtocol.MutationReceiptSchema },
	{
		LobbyProtocol.ENDPOINTS.KICK_PARTY_MEMBER,
		PartyProtocol.MemberIntentSchema,
		PartyProtocol.MutationReceiptSchema,
	},
	{
		LobbyProtocol.ENDPOINTS.TRANSFER_PARTY_LEADERSHIP,
		PartyProtocol.MemberIntentSchema,
		PartyProtocol.MutationReceiptSchema,
	},
	{
		LobbyProtocol.ENDPOINTS.SET_PARTY_PRIVACY,
		PartyProtocol.PrivacyIntentSchema,
		PartyProtocol.MutationReceiptSchema,
	},
	{ LobbyProtocol.ENDPOINTS.DISBAND_PARTY, PartyProtocol.RevisionIntentSchema, PartyProtocol.MutationReceiptSchema },
	{
		LobbyProtocol.ENDPOINTS.PROMPT_PARTY_INVITE,
		LobbyProtocol.InvitePromptIntentSchema,
		LobbyProtocol.InvitePromptReceiptSchema,
	},
	{ LobbyProtocol.ENDPOINTS.GET_QUEUES, LobbyProtocol.EmptyPayloadSchema, LobbyProtocol.QueueListSchema },
	{ LobbyProtocol.ENDPOINTS.JOIN_QUEUE, QueueProtocol.JoinIntentSchema, QueueProtocol.MutationReceiptSchema },
	{ LobbyProtocol.ENDPOINTS.LEAVE_QUEUE, QueueProtocol.LeaveIntentSchema, QueueProtocol.MutationReceiptSchema },
	{
		LobbyProtocol.ENDPOINTS.CONFIGURE_QUEUE,
		QueueProtocol.ConfigureIntentSchema,
		QueueProtocol.MutationReceiptSchema,
	},
	{ LobbyProtocol.ENDPOINTS.START_QUEUE, QueueProtocol.StartIntentSchema, QueueProtocol.MutationReceiptSchema },
	{ LobbyProtocol.ENDPOINTS.GET_ACTIVE_ROUTE, LobbyProtocol.EmptyPayloadSchema, LobbyProtocol.ActiveRouteViewSchema },
	{
		LobbyProtocol.ENDPOINTS.RECONNECT_ACTIVE_MATCH,
		LobbyProtocol.ReconnectIntentSchema,
		LobbyProtocol.ReconnectReceiptSchema,
	},
})

local function inputFamily(): LobbyView.InputFamily
	local inputType = UserInputService.PreferredInput
	if inputType == Enum.PreferredInput.Touch then
		return "Touch"
	elseif inputType == Enum.PreferredInput.Gamepad then
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
		for _, name in
			{
				LobbyProtocol.ENDPOINTS.PROFILE_REPLICATION,
				LobbyProtocol.ENDPOINTS.INVENTORY_REPLICATION,
				LobbyProtocol.ENDPOINTS.PARTY_REPLICATION,
				LobbyProtocol.ENDPOINTS.QUEUE_REPLICATION,
				LobbyProtocol.ENDPOINTS.ACTIVE_ROUTE_REPLICATION,
			}
		do
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
		local FeedbackDirector = require(script.Parent.Parent.common.presentation.FeedbackDirector)
		local presentation = FeedbackDirector.newForSoundService(SoundService)
		local WorldLocalization = require(script.Parent.Parent.common.ui.WorldLocalization)
		local worldLocalization = WorldLocalization.new(Workspace)
		presentation:lobby()
		local function applySettings(settings: ProfileProtocol.SettingsView)
			presentation:applySettings(settings)
			worldLocalization:applySettings(settings)
		end
		return {
			presentation = presentation,
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
				return RunService.RenderStepped:Connect(function(deltaSeconds)
					presentation:step(os.clock())
					worldLocalization:step(os.clock())
					callback(deltaSeconds)
				end)
			end,
			now = os.clock,
			getViewport = function()
				local camera = Workspace.CurrentCamera
				return if camera == nil then DEFAULT_VIEWPORT else camera.ViewportSize
			end,
			getAccessibility = Accessibility.readPreferences,
			getInputFamily = inputFamily,
			getLocalUserId = function()
				local player = Players.LocalPlayer
				return if player == nil then 0 else player.UserId
			end,
			newTransactionId = function()
				return `transaction:{string.lower(HttpService:GenerateGUID(false))}`
			end,
			applySettings = applySettings,
			leave = function()
				local player = Players.LocalPlayer
				if player ~= nil then
					player:Kick(Localization.text("lobby_controller.your_profile_was_not_changed_please_rejoin"))
				end
			end,
			cleanupNetwork = function()
				worldLocalization:cleanup()
				presentation:cleanup()
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
