--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local LobbyUiModel = require(script.Parent.Parent.ProductionClientLobbyUi.LobbyUiModel)

local function settings()
	return {
		masterVolume = 1,
		musicVolume = 0.75,
		sfxVolume = 0.5,
		uiVolume = 1,
		cameraShakeIntensity = 0.25,
		reducedMotionEnabled = true,
		damageNumbersEnabled = true,
		enemyHealthBarsEnabled = true,
		otherPlayerEffectsEnabled = false,
		lowDetailEnabled = false,
		towerRangeEnabled = true,
		uiScale = 1.125,
	}
end

local function tower(id: string, slot: number?)
	return {
		unitId = if id == "tower:dart-ant" then "unit:dart-ant:001" else "unit:rapid-ant:001",
		towerId = id,
		displayName = if id == "tower:dart-ant" then "Dart Ant" else "Rapid Ant",
		description = "Persistent ownership is separate from match upgrades.",
		acquisitionSource = "Starter profile or earn-only chest",
		copies = 1,
		favorite = id == "tower:dart-ant",
		locked = false,
		equippedSlot = slot,
		placementCost = 120,
		placementCap = 8,
		damage = 12,
		rangeStuds = 24,
		cooldownSeconds = 0.8,
		targetModesText = "First, Last, Strongest, Weakest, Closest",
		upgradePreview = "Level 2: 22 damage, 27 range, 0.70s cooldown",
	}
end

local function readyState()
	return {
		profileState = "Ready",
		screen = "Inventory",
		profileRevision = 7,
		statusText = "Profile ready",
		canRetry = false,
		canLeave = false,
		inputFamily = "Gamepad",
		viewport = Vector2.new(1280, 720),
		preferredTextScale = 1.25,
		preferredTransparency = 0.2,
		reducedMotion = false,
		gold = 2500,
		progressionText = "Level 1 • More progression coming later",
		isFirstJoin = false,
		didMigrate = true,
		inventory = { tower("tower:dart-ant", 1), tower("tower:rapid-ant", nil) },
		selectedUnitId = "unit:dart-ant:001",
		settings = settings(),
		banner = {
			bannerId = "banner:starter",
			displayName = "Colony Chest",
			onePullCost = 100,
			tenPullCost = 900,
			pityCount = 2,
			hardPityPullCount = 10,
			odds = {
				{ towerId = "tower:dart-ant", displayName = "Dart Ant", probabilityPercent = 50 },
				{ towerId = "tower:rapid-ant", displayName = "Rapid Ant", probabilityPercent = 50 },
			},
			earnOnly = true,
			canPullOne = true,
			canPullTen = true,
			transactionPending = false,
		},
		modals = {
			{
				id = "confirm:pull",
				title = "Open chest?",
				message = "Spend earned Gold for the server-owned result.",
				confirmText = "OPEN",
				cancelText = "CANCEL",
				dismissable = true,
				busy = false,
			},
		},
		toasts = {
			{
				id = "toast:1",
				kind = "Success",
				title = "Saved",
				message = "Your loadout was saved.",
				repeatCount = 1,
			},
		},
	}
end

local function loadingState()
	return {
		profileState = "Loading",
		screen = "Home",
		statusText = "Loading your saved profile safely.",
		canRetry = false,
		canLeave = true,
		inputFamily = "Desktop",
		viewport = Vector2.new(1280, 720),
		preferredTextScale = 1,
		preferredTransparency = 0,
		reducedMotion = false,
		isFirstJoin = false,
		didMigrate = false,
		modals = {},
		toasts = {},
	}
end

return TestHarness.suite("Lobby UI canonical render model", {
	TestHarness.case("accepts and deeply detaches a bounded Ready profile view", function(assertions)
		local raw = readyState()
		local canonical = LobbyUiModel.canonicalize(raw)
		assertions.isNotNil(canonical)
		local state = canonical :: LobbyUiModel.RenderState
		assertions.equal(state.profileState, "Ready")
		assertions.equal(state.gold, 2500)
		assertions.equal(#state.inventory, 2)
		assertions.equal(state.inventory[1].unitId, "unit:dart-ant:001")
		assertions.equal(state.inventory[1].equippedSlot, 1)
		assertions.isTrue((state.settings :: LobbyUiModel.Settings).reducedMotionEnabled)
		assertions.isTrue((state.banner :: LobbyUiModel.Banner).earnOnly)
		assertions.isTrue(table.isfrozen(state))
		assertions.isTrue(table.isfrozen(state.inventory))
		assertions.isTrue(table.isfrozen(state.inventory[1]))
		assertions.isTrue(table.isfrozen((state.banner :: LobbyUiModel.Banner).odds))

		raw.inventory[1].displayName = "Hostile mutation"
		raw.settings.masterVolume = 0
		assertions.equal(state.inventory[1].displayName, "Dart Ant")
		assertions.equal((state.settings :: LobbyUiModel.Settings).masterVolume, 1)
	end),

	TestHarness.case("keeps all profile values absent until authoritative Ready", function(assertions)
		local canonical = LobbyUiModel.canonicalize(loadingState())
		assertions.isNotNil(canonical)
		local state = canonical :: LobbyUiModel.RenderState
		assertions.equal(state.profileState, "Loading")
		assertions.isNil(state.gold)
		assertions.isNil(state.profileRevision)
		assertions.equal(#state.inventory, 0)
		assertions.isNil(state.settings)
		assertions.isNil(state.banner)

		local leaked = loadingState()
		leaked.gold = 0
		leaked.inventory = {}
		assertions.isNil(LobbyUiModel.canonicalize(leaked))
	end),

	TestHarness.case("rejects unusable or ambiguous persistent loadouts", function(assertions)
		local zero = readyState()
		zero.inventory[1].equippedSlot = nil
		assertions.isNil(LobbyUiModel.canonicalize(zero))

		local duplicateSlot = readyState()
		duplicateSlot.inventory[2].equippedSlot = 1
		assertions.isNil(LobbyUiModel.canonicalize(duplicateSlot))

		local duplicateUnit = readyState()
		duplicateUnit.inventory[2].unitId = "unit:dart-ant:001"
		assertions.isNil(LobbyUiModel.canonicalize(duplicateUnit))

		local duplicateCopy = readyState()
		duplicateCopy.inventory[2].towerId = "tower:dart-ant"
		duplicateCopy.inventory[2].displayName = "Dart Ant"
		duplicateCopy.inventory[1].copies = 2
		duplicateCopy.inventory[2].copies = 2
		assertions.isNotNil(LobbyUiModel.canonicalize(duplicateCopy))

		local duplicateEquippedTower = readyState()
		duplicateEquippedTower.inventory[2].towerId = "tower:dart-ant"
		duplicateEquippedTower.inventory[2].displayName = "Dart Ant"
		duplicateEquippedTower.inventory[1].copies = 2
		duplicateEquippedTower.inventory[2].copies = 2
		duplicateEquippedTower.inventory[2].equippedSlot = 2
		assertions.isNil(LobbyUiModel.canonicalize(duplicateEquippedTower))

		local staleSelection = readyState()
		staleSelection.selectedUnitId = "unit:guard-ant:001"
		assertions.isNil(LobbyUiModel.canonicalize(staleSelection))
	end),

	TestHarness.case("rejects malformed odds paid policy accessibility and private fields", function(assertions)
		local odds = readyState()
		odds.banner.odds[1].probabilityPercent = 49
		assertions.isNil(LobbyUiModel.canonicalize(odds))

		local paid = readyState()
		paid.banner.earnOnly = false
		assertions.isNil(LobbyUiModel.canonicalize(paid))

		local accessibility = readyState()
		accessibility.settings.reducedMotionEnabled = "yes"
		assertions.isNil(LobbyUiModel.canonicalize(accessibility))

		local private = readyState()
		private.privateTransactionHistory = { "secret" }
		assertions.isNil(LobbyUiModel.canonicalize(private))
	end),

	TestHarness.case("bounds modal and toast presentation with failure retry state", function(assertions)
		local tooMany = readyState()
		for index = 2, LobbyUiModel.MAX_MODAL_DEPTH + 1 do
			table.insert(tooMany.modals, {
				id = `modal:{index}`,
				title = "Bounded",
				message = "Bounded modal",
				cancelText = "CLOSE",
				dismissable = true,
				busy = false,
			})
		end
		assertions.isNil(LobbyUiModel.canonicalize(tooMany))

		local failed = loadingState()
		failed.profileState = "Failed"
		failed.statusText = "We could not load your profile. No blank profile was created."
		failed.canRetry = true
		assertions.isNotNil(LobbyUiModel.canonicalize(failed))

		local invalidRetry = loadingState()
		invalidRetry.canRetry = true
		assertions.isNil(LobbyUiModel.canonicalize(invalidRetry))
	end),
})
