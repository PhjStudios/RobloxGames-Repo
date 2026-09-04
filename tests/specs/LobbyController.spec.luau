--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local LobbyProtocol = require(ReplicatedStorage.Shared.lobby.LobbyProtocol)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local LobbyController = require(script.Parent.Parent.ProductionClientLobby.LobbyController)
local LobbyUiModel = require(script.Parent.Parent.ProductionClientLobbyUi.LobbyUiModel)

type Assertions = TestHarness.Assertions

type RequestRecord = {
	name: string,
	payload: any,
	callback: LobbyController.ResponseCallback,
	active: boolean,
}

type Rig = {
	controller: LobbyController.Controller,
	definition: any,
	configuration: TowerFixtures.AuthenticatedFixture,
	now: number,
	requests: { RequestRecord },
	events: { [string]: (unknown) -> () },
	step: (() -> ())?,
	renders: { LobbyUiModel.RenderState },
	appliedSettings: { any },
	cancelled: { string },
	disconnectCount: number,
	leaveCount: number,
	viewCleanupCount: number,
	networkCleanupCount: number,
	transactionSequence: number,
}

local logger = Log.new(EnvironmentContext.new("client", "Lobby", 0, false))
local newForTests = LobbyController.newForTests
local invokeAction = LobbyController.invokeActionForTests
if newForTests == nil or invokeAction == nil then
	error("[ATD_TEST_FIXTURE][code=LOBBY_CONTROLLER_TEST_SEAM_MISSING]", 0)
end

local LARGE_ROBLOX_USER_ID = 11_604_687_814

local function success<T>(assertions: Assertions, value: any): T
	assertions.isTrue(value.ok)
	if not value.ok then
		error("expected Lobby controller operation to succeed", 0)
	end
	return value.value :: T
end

local function makeConnection(rig: Rig): RBXScriptConnection
	local connected = true
	return RobloxAdapter.createConnection(function()
		if connected then
			connected = false
			rig.disconnectCount += 1
		end
	end) :: RBXScriptConnection
end

local function makeRig(assertions: Assertions, localUserIdValue: number?): Rig
	local fixture = TowerFixtures.createAuthenticatedFixture()
	local localUserId = localUserIdValue or 101
	local rig = {
		controller = nil :: any,
		definition = nil,
		configuration = fixture,
		now = 0,
		requests = {},
		events = {},
		step = nil,
		renders = {},
		appliedSettings = {},
		cancelled = {},
		disconnectCount = 0,
		leaveCount = 0,
		viewCleanupCount = 0,
		networkCleanupCount = 0,
		transactionSequence = 0,
	} :: Rig
	local view = {
		render = function(_self: unknown, value: unknown)
			local canonical = LobbyUiModel.canonicalize(value)
			if canonical == nil then
				return Result.err(table.freeze({ code = "INVALID_RENDER" }))
			end
			table.insert(rig.renders, canonical)
			return Result.ok(true)
		end,
		getMetrics = function(_self: unknown)
			return Result.ok(table.freeze({ renderCount = #rig.renders }))
		end,
		cleanup = function(_self: unknown)
			rig.viewCleanupCount += 1
			return Result.ok(true)
		end,
	}
	local dependencies: LobbyController.Dependencies = {
		view = view :: any,
		request = function(name, payload, callback)
			table.insert(rig.requests, {
				name = name,
				payload = payload,
				callback = callback,
				active = true,
			})
			return true
		end,
		cancel = function(name)
			table.insert(rig.cancelled, name)
			for _, request in rig.requests do
				if request.name == name and request.active then
					request.active = false
					break
				end
			end
		end,
		connectEvent = function(name, callback)
			rig.events[name] = callback
			return makeConnection(rig)
		end,
		connectStep = function(callback)
			rig.step = function()
				callback(0)
			end
			return makeConnection(rig)
		end,
		now = function()
			return rig.now
		end,
		getViewport = function()
			return Vector2.new(1280, 720)
		end,
		getAccessibility = function()
			return { textScale = 1.15, transparency = 0.2 }
		end,
		getInputFamily = function()
			return "Desktop"
		end,
		getLocalUserId = function()
			return localUserId
		end,
		newTransactionId = function()
			rig.transactionSequence += 1
			return string.format("transaction:00000000-0000-4000-8000-%012d", rig.transactionSequence)
		end,
		applySettings = function(settings)
			table.insert(rig.appliedSettings, settings)
		end,
		leave = function()
			rig.leaveCount += 1
		end,
		cleanupNetwork = function()
			rig.networkCleanupCount += 1
		end,
	}
	local constructor =
		newForTests :: (Log.Logger, any, LobbyController.Dependencies) -> LobbyController.ControllerResult
	rig.controller =
		success(assertions, constructor(logger, fixture.configuration, dependencies)) :: LobbyController.Controller
	rig.definition = rig.controller:getServiceDefinition()
	rig.definition.initialize()
	rig.definition.start()
	return rig
end

local function latest(rig: Rig): LobbyUiModel.RenderState
	local state = rig.renders[#rig.renders]
	if state == nil then
		error("Lobby controller did not render", 0)
	end
	return state
end

local function findRequest(rig: Rig, name: string): RequestRecord?
	for _, request in rig.requests do
		if request.name == name and request.active then
			return request
		end
	end
	return nil
end

local function requestCount(rig: Rig, name: string): number
	local count = 0
	for _, request in rig.requests do
		if request.name == name then
			count += 1
		end
	end
	return count
end

local function respond(rig: Rig, name: string, ok: boolean, value: unknown?, code: string?): RequestRecord
	local request = findRequest(rig, name)
	if request == nil then
		error(`missing active Lobby request {name}`, 0)
	end
	request.active = false
	request.callback(ok, value, code)
	return request
end

local function dispatch(rig: Rig, fields: { [string]: any })
	fields.source = fields.source or "Desktop"
	(invokeAction :: any)(rig.controller, fields)
end

local function settings(masterVolume: number?): any
	return {
		version = 2,
		masterVolume = masterVolume or 1,
		musicVolume = 0.75,
		sfxVolume = 0.8,
		uiVolume = 0.9,
		cameraShakeIntensity = 0.5,
		damageNumbersEnabled = true,
		enemyHealthBarsEnabled = true,
		otherPlayerEffectsEnabled = true,
		lowDetailEnabled = false,
		reducedMotionEnabled = false,
		towerRangeEnabled = true,
		uiScale = 1,
	}
end

local function profile(revision: number, gold: number?): any
	return {
		state = "Ready",
		retryable = false,
		revision = revision,
		gold = gold or 2_500,
		settings = settings(),
		tutorial = { firstJoin = false, tutorialCompleted = false, tutorialStep = 1 },
		stats = { matchesPlayed = 2, victories = 1, defeats = 1, towersAcquired = 2, chestsOpened = 1 },
		firstClears = {},
		migrationOutcome = "Current",
	}
end

local function inventory(rig: Rig, revision: number, favorite: boolean?): any
	local single = rig.configuration.single.id
	local splash = rig.configuration.splash.id
	return {
		revision = revision,
		units = {
			{
				unitId = "unit:controller-a",
				towerId = single,
				favorite = favorite == true,
				locked = false,
				equippedSlot = 1,
			},
			{
				unitId = "unit:controller-b",
				towerId = splash,
				favorite = false,
				locked = false,
			},
		},
		copyCounts = {
			{ towerId = single, copies = 1 },
			{ towerId = splash, copies = 1 },
		},
		equipped = {
			{ slot = 1, unitId = "unit:controller-a", towerId = single },
		},
	}
end

local function banner(rig: Rig, revision: number): any
	return {
		bannerId = "banner:starter",
		bannerVersion = 1,
		displayName = "Starter Tower Chest",
		available = true,
		currencyPolicy = "EarnOnlyGold",
		policyDisclosure = "Earn-only Gold. No Robux or paid currency conversion.",
		onePullCost = 100,
		tenPullCost = 900,
		odds = {
			{ towerId = rig.configuration.single.id, probabilityPercent = 60 },
			{ towerId = rig.configuration.splash.id, probabilityPercent = 40 },
		},
		hardPityPullCount = 10,
		guaranteedTowerId = rig.configuration.splash.id,
		currentPityCount = 2,
		gold = 2_500,
		profileRevision = revision,
	}
end

local function readyRig(assertions: Assertions): Rig
	local rig = makeRig(assertions)
	respond(rig, LobbyProtocol.ENDPOINTS.GET_PROFILE, true, profile(7))
	respond(rig, LobbyProtocol.ENDPOINTS.GET_INVENTORY, true, inventory(rig, 7))
	respond(rig, LobbyProtocol.ENDPOINTS.GET_BANNER, true, banner(rig, 7))
	assertions.equal(latest(rig).profileState, "Ready")
	return rig
end

local function emptyPartySnapshot(): any
	return { version = 1, incomingInvitations = {} }
end

local function queueSnapshot(withMember: boolean?): any
	local members = if withMember then { { userId = 101, order = 1, isCaptain = true, readiness = "Ready" } } else {}
	local enrollments = if withMember
		then {
			{
				sequence = 1,
				kind = "Solo",
				leaderUserId = 101,
				userIds = { 101 },
				source = "UI",
			},
		}
		else {}
	return {
		version = 1,
		queueId = "queue:alpha",
		revision = if withMember then 2 else 1,
		state = "Open",
		captainUserId = if withMember then 101 else nil,
		configuration = {
			mapId = "map:meadow",
			difficultyId = "difficulty:normal",
			privacy = "Public",
			maxPlayers = 4,
		},
		members = members,
		enrollments = enrollments,
		canStart = withMember == true,
	}
end

local function readySquadRig(assertions: Assertions): Rig
	local rig = readyRig(assertions)
	respond(rig, LobbyProtocol.ENDPOINTS.GET_PARTY, true, emptyPartySnapshot())
	respond(rig, LobbyProtocol.ENDPOINTS.GET_QUEUES, true, { version = 1, queues = { queueSnapshot() } })
	respond(rig, LobbyProtocol.ENDPOINTS.GET_ACTIVE_ROUTE, true, { version = 1, status = "None" })
	return rig
end

local function shutdown(rig: Rig)
	if rig.controller:getMetrics().lifecycleState ~= "Shutdown" then
		rig.definition.shutdown()
	end
end

local function pullReceipt(rig: Rig, request: RequestRecord, quantity: number, revision: number): any
	local results = table.create(quantity)
	for index = 1, quantity do
		results[index] = {
			index = index,
			unitId = `unit:chest-{quantity}-{index}`,
			towerId = if index == quantity and quantity == 10
				then rig.configuration.support.id
				else rig.configuration.single.id,
			isNew = index == quantity,
		}
	end
	local cost = if quantity == 10 then 900 else 100
	return {
		transactionId = request.payload.transactionId,
		bannerId = "banner:starter",
		bannerVersion = 1,
		quantity = quantity,
		cost = cost,
		goldBefore = 2_500,
		goldAfter = 2_500 - cost,
		pityBefore = 2,
		pityAfter = if quantity == 10 then 2 else 3,
		profileRevision = revision,
		results = results,
	}
end

return TestHarness.suite("LobbyController", {
	TestHarness.case("waits for profile readiness before requesting dependent Lobby authority", function(assertions)
		local rig = makeRig(assertions)
		assertions.isNotNil(findRequest(rig, LobbyProtocol.ENDPOINTS.GET_PROFILE))
		assertions.isNil(findRequest(rig, LobbyProtocol.ENDPOINTS.GET_PARTY))
		assertions.isNil(findRequest(rig, LobbyProtocol.ENDPOINTS.GET_QUEUES))
		assertions.isNil(findRequest(rig, LobbyProtocol.ENDPOINTS.GET_ACTIVE_ROUTE))
		assertions.equal(#latest(rig).toasts, 0)

		respond(rig, LobbyProtocol.ENDPOINTS.GET_PROFILE, true, { state = "Loading", retryable = false })
		assertions.isNil(findRequest(rig, LobbyProtocol.ENDPOINTS.GET_PARTY))
		assertions.isNil(findRequest(rig, LobbyProtocol.ENDPOINTS.GET_QUEUES))
		assertions.isNil(findRequest(rig, LobbyProtocol.ENDPOINTS.GET_ACTIVE_ROUTE))
		assertions.equal(#latest(rig).toasts, 0)

		rig.now = LobbyController.PROFILE_POLL_SECONDS + 0.1
		(rig.step :: () -> ())()
		respond(rig, LobbyProtocol.ENDPOINTS.GET_PROFILE, true, profile(7))
		assertions.isNotNil(findRequest(rig, LobbyProtocol.ENDPOINTS.GET_PARTY))
		assertions.isNotNil(findRequest(rig, LobbyProtocol.ENDPOINTS.GET_QUEUES))
		assertions.isNotNil(findRequest(rig, LobbyProtocol.ENDPOINTS.GET_ACTIVE_ROUTE))
		assertions.equal(#latest(rig).toasts, 0)
		shutdown(rig)
	end),

	TestHarness.case("accepts Roblox UserIds above the signed 32-bit range", function(assertions)
		local rig = makeRig(assertions, LARGE_ROBLOX_USER_ID)
		assertions.equal(latest(rig).localUserId, LARGE_ROBLOX_USER_ID)
		shutdown(rig)
	end),

	TestHarness.case("rejects non-positive non-finite fractional and unsafe local UserIds", function(assertions)
		for _, invalidUserId in { 0, -1, 1.5, math.huge, -math.huge, 0 / 0, Validation.MAX_SAFE_INTEGER + 1 } do
			assertions.isFalse(pcall(function()
				makeRig(assertions, invalidUserId)
			end))
		end
	end),

	TestHarness.case(
		"never renders authoritative defaults before Ready and blocks non-ready mutations",
		function(assertions)
			local rig = makeRig(assertions)
			local initial = latest(rig)
			assertions.equal(initial.profileState, "Loading")
			assertions.isNil(initial.gold)
			assertions.isNil(initial.profileRevision)
			assertions.isNil(initial.settings)
			assertions.equal(#initial.inventory, 0)
			local before = #rig.requests
			dispatch(rig, { kind = "ToggleFavorite", unitId = "unit:controller-a", enabled = true })
			dispatch(rig, { kind = "PullChest", quantity = 1 })
			dispatch(rig, { kind = "UpdateSetting", settingKey = "uiScale", settingValue = 1.25 })
			assertions.equal(#rig.requests, before)

			respond(rig, LobbyProtocol.ENDPOINTS.GET_PROFILE, true, { state = "Failed", retryable = true })
			assertions.equal(latest(rig).profileState, "Failed")
			local failedBefore = #rig.requests
			dispatch(rig, { kind = "ToggleLock", unitId = "unit:controller-a", enabled = true })
			dispatch(rig, { kind = "PullChest", quantity = 10 })
			dispatch(rig, { kind = "UpdateSetting", settingKey = "uiScale", settingValue = 0.9 })
			assertions.equal(#rig.requests, failedBefore)
			dispatch(rig, { kind = "RetryProfile" })
			assertions.isNotNil(findRequest(rig, LobbyProtocol.ENDPOINTS.RETRY_PROFILE))
			respond(rig, LobbyProtocol.ENDPOINTS.RETRY_PROFILE, true, { state = "Loading", retryable = false })
			assertions.equal(latest(rig).profileState, "Loading")

			local event = rig.events[LobbyProtocol.ENDPOINTS.PROFILE_REPLICATION]
			assertions.isNotNil(event)
			local profileEvent = event :: (unknown) -> ()
			profileEvent({
				payload = { state = "Releasing", retryable = false },
			})
			assertions.equal(latest(rig).profileState, "Releasing")
			local releasingBefore = #rig.requests
			dispatch(rig, { kind = "EquipTower", unitId = "unit:controller-a" })
			dispatch(rig, { kind = "PullChest", quantity = 1 })
			assertions.equal(#rig.requests, releasingBefore)
			dispatch(rig, { kind = "SafeLeave" })
			assertions.equal(rig.leaveCount, 1)
			shutdown(rig)
		end
	),

	TestHarness.case(
		"composes validated Ready profile inventory banner and applies settings immediately",
		function(assertions)
			local rig = readyRig(assertions)
			local state = latest(rig)
			assertions.equal(state.profileRevision, 7)
			assertions.equal(state.gold, 2_500)
			assertions.equal(#state.inventory, 2)
			assertions.equal(state.inventory[1].unitId, "unit:controller-a")
			assertions.equal(state.inventory[1].displayName, rig.configuration.single.displayName)
			assertions.equal(state.inventory[1].copies, 1)
			assertions.equal((state.banner :: LobbyUiModel.Banner).onePullCost, 100)
			assertions.equal(
				(state.banner :: LobbyUiModel.Banner).odds[2].displayName,
				rig.configuration.splash.displayName
			)
			assertions.equal(#rig.appliedSettings, 1)
			assertions.equal(rig.appliedSettings[1].musicVolume, 0.75)
			assertions.equal(state.preferredTextScale, 1.15)
			assertions.equal(state.preferredTransparency, 0.2)
			shutdown(rig)
		end
	),

	TestHarness.case(
		"rejects malformed and stale wire events without regressing authoritative inventory",
		function(assertions)
			local rig = readyRig(assertions)
			local rejectedBefore = rig.controller:getMetrics().rejectedResponseCount
			local renderBefore = #rig.renders
			local profileEvent = rig.events[LobbyProtocol.ENDPOINTS.PROFILE_REPLICATION] :: (unknown) -> ()
			profileEvent({ state = "Ready" })
			assertions.equal(rig.controller:getMetrics().rejectedResponseCount, rejectedBefore + 1)
			profileEvent({ payload = { state = "Loading", retryable = false, unexpected = true } })
			assertions.equal(rig.controller:getMetrics().rejectedResponseCount, rejectedBefore + 2)

			local stale = inventory(rig, 6, true)
			local inventoryEvent = rig.events[LobbyProtocol.ENDPOINTS.INVENTORY_REPLICATION] :: (unknown) -> ()
			inventoryEvent({ payload = stale })
			assertions.equal(rig.controller:getMetrics().revision, 7)
			assertions.equal(rig.controller:getMetrics().rejectedResponseCount, rejectedBefore + 3)
			assertions.isFalse(latest(rig).inventory[1].favorite)
			assertions.isTrue(#rig.renders >= renderBefore)

			dispatch(rig, { kind = "ToggleFavorite", unitId = "unit:controller-a", enabled = true })
			respond(rig, LobbyProtocol.ENDPOINTS.FAVORITE_TOWER, true, { malformed = true })
			assertions.isTrue(rig.controller:getMetrics().rejectedResponseCount >= rejectedBefore + 4)
			shutdown(rig)
		end
	),

	TestHarness.case(
		"sends inventory mutations with unique UnitId current revision and transaction identity",
		function(assertions)
			local rig = readyRig(assertions)
			dispatch(rig, {
				kind = "ToggleFavorite",
				unitId = "unit:controller-a",
				towerId = rig.configuration.single.id,
				enabled = true,
				profileRevision = 1,
			})
			local request = findRequest(rig, LobbyProtocol.ENDPOINTS.FAVORITE_TOWER) :: RequestRecord
			assertions.isNotNil(request)
			assertions.equal(request.payload.unitId, "unit:controller-a")
			assertions.equal(request.payload.expectedRevision, 7)
			assertions.equal(request.payload.transactionId, "transaction:00000000-0000-4000-8000-000000000001")
			assertions.isNil(request.payload.towerId)
			local nextInventory = inventory(rig, 8, true)
			respond(rig, LobbyProtocol.ENDPOINTS.FAVORITE_TOWER, true, {
				transactionId = request.payload.transactionId,
				kind = "Favorite",
				changed = true,
				revision = 8,
				snapshot = nextInventory,
			})
			assertions.equal(rig.controller:getMetrics().revision, 8)
			assertions.isTrue(latest(rig).inventory[1].favorite)
			assertions.isTrue(rig.controller:getMetrics().toastCount >= 1)
			shutdown(rig)
		end
	),

	TestHarness.case(
		"confirms one and ten pulls skips presentation only and shows complete results",
		function(assertions)
			for _, quantity in { 1, 10 } do
				local rig = readyRig(assertions)
				dispatch(rig, { kind = "PullChest", quantity = quantity })
				assertions.equal(requestCount(rig, LobbyProtocol.ENDPOINTS.PULL_CHEST), 0)
				local confirm = latest(rig).modals[#latest(rig).modals]
				assertions.isNotNil(confirm)
				dispatch(rig, { kind = "ConfirmModal", modalId = confirm.id })
				local request = findRequest(rig, LobbyProtocol.ENDPOINTS.PULL_CHEST) :: RequestRecord
				assertions.isNotNil(request)
				assertions.equal(request.payload.quantity, quantity)
				assertions.equal(request.payload.expectedRevision, 7)
				assertions.equal(requestCount(rig, LobbyProtocol.ENDPOINTS.PULL_CHEST), 1)
				dispatch(rig, { kind = "SkipChestPresentation" })
				assertions.equal(#latest(rig).modals, 0)
				assertions.equal(requestCount(rig, LobbyProtocol.ENDPOINTS.PULL_CHEST), 1)

				request.active = false
				request.callback(true, pullReceipt(rig, request, quantity, 8), nil)
				local result = latest(rig).modals[#latest(rig).modals]
				assertions.isNotNil(result)
				assertions.equal(result.id, "modal:chest-results:current")
				if quantity == 10 then
					assertions.contains(result.message, rig.configuration.support.displayName)
				end
				dispatch(rig, { kind = "SkipChestPresentation" })
				assertions.equal(#latest(rig).modals, 0)
				assertions.equal(requestCount(rig, LobbyProtocol.ENDPOINTS.PULL_CHEST), 1)
				shutdown(rig)
			end
		end
	),

	TestHarness.case(
		"applies settings optimistically then converges to the authoritative receipt",
		function(assertions)
			local rig = readyRig(assertions)
			dispatch(rig, { kind = "UpdateSetting", settingKey = "masterVolume", settingValue = 0.25 })
			assertions.equal((latest(rig).settings :: LobbyUiModel.Settings).masterVolume, 0.25)
			assertions.equal(rig.appliedSettings[#rig.appliedSettings].masterVolume, 0.25)
			local request = findRequest(rig, LobbyProtocol.ENDPOINTS.UPDATE_SETTINGS) :: RequestRecord
			assertions.equal(request.payload.expectedRevision, 7)
			assertions.equal(request.payload.transactionId, "transaction:00000000-0000-4000-8000-000000000001")
			local accepted = settings(0.5)
			respond(rig, LobbyProtocol.ENDPOINTS.UPDATE_SETTINGS, true, {
				transactionId = request.payload.transactionId,
				revision = 8,
				changed = true,
				settings = accepted,
			})
			assertions.equal((latest(rig).settings :: LobbyUiModel.Settings).masterVolume, 0.5)
			assertions.equal(rig.appliedSettings[#rig.appliedSettings].masterVolume, 0.5)
			assertions.equal(rig.controller:getMetrics().revision, 8)
			shutdown(rig)
		end
	),

	TestHarness.case("deduplicates repeated network failures", function(assertions)
		local rig = makeRig(assertions)
		respond(rig, LobbyProtocol.ENDPOINTS.GET_PROFILE, false, nil, "UNAVAILABLE")
		rig.now = LobbyController.PROFILE_POLL_SECONDS + 0.1
		(rig.step :: () -> ())()
		respond(rig, LobbyProtocol.ENDPOINTS.GET_PROFILE, false, nil, "UNAVAILABLE")
		local toast = latest(rig).toasts[1]
		assertions.isNotNil(toast)
		assertions.equal(toast.repeatCount, 2)
		shutdown(rig)
	end),

	TestHarness.case("cancels timed-out profile polling and starts bounded recovery", function(assertions)
		local rig = makeRig(assertions)
		rig.now = LobbyController.REQUEST_TIMEOUT_SECONDS + 0.1
		(rig.step :: () -> ())()
		assertions.contains(table.concat(rig.cancelled, ","), LobbyProtocol.ENDPOINTS.GET_PROFILE)
		assertions.isTrue(requestCount(rig, LobbyProtocol.ENDPOINTS.GET_PROFILE) >= 2)

		respond(rig, LobbyProtocol.ENDPOINTS.GET_PROFILE, false, nil, "UNAVAILABLE")
		rig.now += LobbyController.PROFILE_POLL_SECONDS + 0.1
		(rig.step :: () -> ())()
		assertions.isNotNil(findRequest(rig, LobbyProtocol.ENDPOINTS.GET_PROFILE))
		shutdown(rig)
	end),

	TestHarness.case(
		"loads squad authority without defaults and sends revision-bound party queue and reconnect intents",
		function(assertions)
			local rig = readySquadRig(assertions)
			assertions.equal(latest(rig).partyState, "Ready")
			assertions.equal(latest(rig).queuesState, "Ready")
			assertions.equal(latest(rig).activeRouteState, "Ready")
			assertions.isNil((latest(rig).partySnapshot :: any).party)
			assertions.equal((latest(rig).queueSnapshots :: any)[1].queueId, "queue:alpha")

			dispatch(rig, { kind = "Navigate", screen = "Party" })
			dispatch(rig, { kind = "CreateParty" })
			local createRequest = findRequest(rig, LobbyProtocol.ENDPOINTS.CREATE_PARTY) :: RequestRecord
			assertions.isNotNil(createRequest)
			assertions.equal(createRequest.payload.expectedRevision, 0)
			assertions.equal(createRequest.payload.privacy, "InviteOnly")
			respond(rig, LobbyProtocol.ENDPOINTS.CREATE_PARTY, true, {
				transactionId = createRequest.payload.transactionId,
				kind = "Create",
				reason = "PartyCreated",
				changed = true,
				partyRevision = 1,
				snapshot = {
					version = 1,
					party = {
						version = 1,
						partyId = "party:alpha",
						revision = 1,
						leaderUserId = 101,
						privacy = "InviteOnly",
						queueState = "Idle",
						members = { { userId = 101, order = 1, isLeader = true, profileReady = true } },
						pendingInvitationCount = 0,
					},
					incomingInvitations = {},
				},
			})
			assertions.equal(((latest(rig).partySnapshot :: any).party :: any).leaderUserId, 101)

			dispatch(rig, { kind = "Navigate", screen = "Queue" })
			dispatch(rig, { kind = "JoinQueue" })
			local joinRequest = findRequest(rig, LobbyProtocol.ENDPOINTS.JOIN_QUEUE) :: RequestRecord
			assertions.isNotNil(joinRequest)
			assertions.equal(joinRequest.payload.queueId, "queue:alpha")
			assertions.equal(joinRequest.payload.expectedRevision, 1)
			assertions.equal(joinRequest.payload.source, "UI")
			respond(rig, LobbyProtocol.ENDPOINTS.JOIN_QUEUE, true, {
				transactionId = joinRequest.payload.transactionId,
				kind = "Join",
				changed = true,
				revision = 2,
				snapshot = queueSnapshot(true),
			})
			dispatch(rig, {
				kind = "ConfigureQueue",
				configuration = {
					mapId = "map:meadow",
					difficultyId = "difficulty:normal",
					privacy = "PartyOnly",
					maxPlayers = 3,
				},
			})
			local configureRequest = findRequest(rig, LobbyProtocol.ENDPOINTS.CONFIGURE_QUEUE) :: RequestRecord
			assertions.isNotNil(configureRequest)
			assertions.equal(configureRequest.payload.expectedRevision, 2)
			assertions.equal(configureRequest.payload.configuration.privacy, "PartyOnly")

			respond(rig, LobbyProtocol.ENDPOINTS.CONFIGURE_QUEUE, false, nil, "STALE_REQUEST")
			local routeEvent = rig.events[LobbyProtocol.ENDPOINTS.ACTIVE_ROUTE_REPLICATION] :: (unknown) -> ()
			routeEvent({ payload = { version = 1, status = "Available", matchId = "match:active", expiresAt = 500 } })
			dispatch(rig, { kind = "ReconnectActiveMatch" })
			local reconnectRequest = findRequest(rig, LobbyProtocol.ENDPOINTS.RECONNECT_ACTIVE_MATCH) :: RequestRecord
			assertions.isNotNil(reconnectRequest)
			assertions.isNil(reconnectRequest.payload.matchId)
			assertions.isNil(reconnectRequest.payload.routeId)
			assertions.isNil(reconnectRequest.payload.ticketId)
			shutdown(rig)
		end
	),

	TestHarness.case(
		"preserves input navigation and disconnects cancels and ignores stale callbacks",
		function(assertions)
			local rig = readyRig(assertions)
			dispatch(rig, { kind = "Navigate", screen = "Inventory" })
			dispatch(rig, { kind = "InputFamilyChanged", inputFamily = "Gamepad" })
			assertions.equal(latest(rig).screen, "Inventory")
			assertions.equal(latest(rig).inputFamily, "Gamepad")
			dispatch(rig, { kind = "Play" })
			assertions.equal(latest(rig).screen, "Queue")
			dispatch(rig, { kind = "Back" })
			assertions.equal(latest(rig).screen, "Home")

			rig.now = 11
			(rig.step :: () -> ())()
			local pending = findRequest(rig, LobbyProtocol.ENDPOINTS.GET_PROFILE)
			assertions.isNotNil(pending)
			local callback = (pending :: RequestRecord).callback
			local event = rig.events[LobbyProtocol.ENDPOINTS.PROFILE_REPLICATION] :: (unknown) -> ()
			rig.definition.shutdown()
			assertions.equal(rig.controller:getMetrics().lifecycleState, "Shutdown")
			assertions.equal(rig.disconnectCount, 6)
			assertions.equal(rig.viewCleanupCount, 1)
			assertions.equal(rig.networkCleanupCount, 1)
			assertions.contains(table.concat(rig.cancelled, ","), LobbyProtocol.ENDPOINTS.GET_PROFILE)
			local renderCount = #rig.renders
			callback(true, profile(99), nil)
			event({ payload = profile(99) })
			dispatch(rig, { kind = "Navigate", screen = "Settings" })
			assertions.equal(#rig.renders, renderCount)
		end
	),
})
