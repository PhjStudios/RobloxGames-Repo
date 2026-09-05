--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local LobbyView = require(script.Parent.Parent.ProductionClientLobbyUi.LobbyView)
local Theme = require(script.Parent.Parent.ProductionClientCommonUi.Theme)
local Localization = require(game:GetService("ReplicatedStorage").Shared.localization.Localization)

local newForTests = LobbyView.newForTests
if newForTests == nil then
	error("[ATD_TEST_FIXTURE][code=LOBBY_VIEW_CONSTRUCTOR_MISSING]", 0)
end

local function child(parent: Instance, name: string, className: string): Instance
	local value = parent:FindFirstChild(name)
	if value == nil or value.ClassName ~= className then
		error("[ATD_TEST_FIXTURE][code=LOBBY_VIEW_CHILD_MISSING]", 0)
	end
	return value
end

local function settings(): any
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

local function tower(
	unitId: string,
	towerId: string,
	displayName: string,
	copies: number,
	equippedSlot: number?,
	favorite: boolean,
	locked: boolean
): any
	return {
		unitId = unitId,
		towerId = towerId,
		displayName = displayName,
		description = `{displayName} defends the colony with a persistent owned record.`,
		acquisitionSource = "Starter profile or earn-only Gold chest",
		copies = copies,
		favorite = favorite,
		locked = locked,
		equippedSlot = equippedSlot,
		placementCost = if towerId == "tower:dart-ant" then 120 else 165,
		placementCap = 8,
		damage = if towerId == "tower:dart-ant" then 12 else 8,
		rangeStuds = 24,
		cooldownSeconds = if towerId == "tower:dart-ant" then 0.8 else 0.45,
		targetModesText = "First, Last, Strongest, Weakest, Closest",
		upgradePreview = "Level 2 improves damage and range while remaining a match-local upgrade.",
	}
end

local function loadingState(): any
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
		localUserId = 101,
		partyState = "Loading",
		queuesState = "Loading",
		activeRouteState = "Loading",
		squadMutationPending = false,
		modals = {},
		toasts = {},
	}
end

local function readyState(screen: string?, inputFamily: string?): any
	return {
		profileState = "Ready",
		screen = screen or "Home",
		profileRevision = 7,
		statusText = "Profile ready",
		canRetry = false,
		canLeave = false,
		inputFamily = inputFamily or "Desktop",
		viewport = Vector2.new(1280, 720),
		preferredTextScale = 1.1,
		preferredTransparency = 0.2,
		reducedMotion = false,
		gold = 2_500,
		progressionText = "Level 1 with more progression coming later",
		isFirstJoin = false,
		didMigrate = false,
		inventory = {
			tower("unit:dart-ant:001", "tower:dart-ant", "Dart Ant", 2, 1, true, false),
			tower("unit:dart-ant:002", "tower:dart-ant", "Dart Ant", 2, nil, false, true),
			tower("unit:rapid-ant:001", "tower:rapid-ant", "Rapid Ant", 1, nil, false, false),
		},
		selectedUnitId = "unit:dart-ant:001",
		settings = settings(),
		banner = {
			bannerId = "banner:starter",
			displayName = "Starter Tower Chest",
			policyDisclosure = "Gold is earned through play. Duplicates remain separate units.",
			onePullCost = 250,
			tenPullCost = 2_250,
			pityCount = 2,
			hardPityPullCount = 10,
			odds = {
				{ towerId = "tower:dart-ant", displayName = "Dart Ant", probabilityPercent = 60 },
				{ towerId = "tower:rapid-ant", displayName = "Rapid Ant", probabilityPercent = 30 },
				{ towerId = "tower:guard-ant", displayName = "Guard Ant", probabilityPercent = 10 },
			},
			earnOnly = true,
			canPullOne = true,
			canPullTen = true,
			transactionPending = false,
		},
		localUserId = 101,
		partyState = "Ready",
		partySnapshot = { version = 1, incomingInvitations = {} },
		queuesState = "Ready",
		queueSnapshots = {},
		activeRouteState = "Ready",
		activeRoute = { version = 1, status = "None" },
		squadMutationPending = false,
		modals = {},
		toasts = {},
	}
end

local function squadState(screen: "Party" | "Queue", queued: boolean?): any
	local state = readyState(screen)
	state.partySnapshot = {
		version = 1,
		party = {
			version = 1,
			partyId = "party:alpha",
			revision = 3,
			leaderUserId = 101,
			privacy = "InviteOnly",
			queueState = if queued then "Queued" else "Idle",
			members = {
				{ userId = 101, order = 1, isLeader = true, profileReady = true },
				{ userId = 202, order = 2, isLeader = false, profileReady = true },
			},
			pendingInvitationCount = 0,
		},
		incomingInvitations = {},
	}
	local members = if queued
		then {
			{ userId = 101, order = 1, isCaptain = true, readiness = "Ready" },
			{ userId = 202, order = 2, isCaptain = false, readiness = "Ready" },
		}
		else {}
	local enrollments = if queued
		then {
			{
				sequence = 1,
				kind = "Party",
				leaderUserId = 101,
				partyId = "party:alpha",
				partyRevision = 3,
				userIds = { 101, 202 },
				source = "UI",
			},
		}
		else {}
	state.queueSnapshots = {
		{
			version = 1,
			queueId = "queue:alpha",
			revision = if queued then 2 else 1,
			state = "Open",
			captainUserId = if queued then 101 else nil,
			configuration = {
				mapId = "map:meadow",
				difficultyId = "difficulty:normal",
				privacy = "Public",
				maxPlayers = 4,
			},
			members = members,
			enrollments = enrollments,
			canStart = queued == true,
		},
	}
	state.selectedQueueId = "queue:alpha"
	state.activeRoute = { version = 1, status = "Available", matchId = "match:active", expiresAt = 500 }
	return state
end

local function makeFixture(): any
	local guiParent = Instance.new("Folder")
	guiParent.Name = "LobbyGuiParent"
	local fixture = {
		guiParent = guiParent,
		actions = {} :: { any },
		activations = {} :: { [GuiButton]: () -> () },
		inputListeners = {} :: { (string, boolean) -> () },
		familyListeners = {} :: { (any) -> () },
		searchListeners = {} :: { [TextBox]: (string) -> () },
		selected = nil :: GuiObject?,
		disconnectCount = 0,
		clearFocusOnDynamicDisconnect = false,
		focusClearCount = 0,
	}
	fixture.callback = function(action: any)
		table.insert(fixture.actions, action)
	end
	fixture.dependencies = {
		connectActivated = function(button: GuiButton, listener: () -> ())
			fixture.activations[button] = listener
			return RobloxAdapter.createConnection(function()
				fixture.disconnectCount += 1
				if fixture.clearFocusOnDynamicDisconnect then
					fixture.selected = nil
					fixture.focusClearCount += 1
				end
			end) :: RBXScriptConnection
		end,
		connectInputBegan = function(listener: (string, boolean) -> ())
			table.insert(fixture.inputListeners, listener)
			return RobloxAdapter.createConnection(function()
				fixture.disconnectCount += 1
			end) :: RBXScriptConnection
		end,
		connectInputFamilyChanged = function(listener: (any) -> ())
			table.insert(fixture.familyListeners, listener)
			return RobloxAdapter.createConnection(function()
				fixture.disconnectCount += 1
			end) :: RBXScriptConnection
		end,
		connectSearchCommitted = function(textBox: TextBox, listener: (string) -> ())
			fixture.searchListeners[textBox] = listener
			return RobloxAdapter.createConnection(function()
				fixture.disconnectCount += 1
			end) :: RBXScriptConnection
		end,
		selectObject = function(value: GuiObject?)
			fixture.selected = value
		end,
		getSelectedObject = function(): GuiObject?
			return fixture.selected
		end,
	}
	return fixture
end

local function construct(fixture: any): any
	local result = (newForTests :: any)(fixture.guiParent, fixture.callback, fixture.dependencies)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=LOBBY_VIEW_CONSTRUCTION_FAILED]", 0)
	end
	return result.value
end

local function withView(callback: (any, any) -> ())
	local fixture = makeFixture()
	local view = construct(fixture)
	callback(view, fixture)
	view:cleanup()
	fixture.guiParent:Destroy()
end

local function guiTree(fixture: any): (ScreenGui, Frame)
	local gui = child(fixture.guiParent, LobbyView.GUI_NAME, "ScreenGui") :: ScreenGui
	return gui, child(gui, "Root", "Frame") :: Frame
end

local function contentScreens(root: Frame): (Frame, { Frame })
	local content = child(root, "Content", "Frame") :: Frame
	return content,
		{
			child(content, "HomeScreen", "Frame") :: Frame,
			child(content, "PartyScreen", "Frame") :: Frame,
			child(content, "QueueScreen", "Frame") :: Frame,
			child(content, "InventoryScreen", "Frame") :: Frame,
			child(content, "ChestsScreen", "Frame") :: Frame,
			child(content, "SettingsScreen", "Frame") :: Frame,
		}
end

local function assertOneActiveScreen(assertions: TestHarness.Assertions, root: Frame, expected: string)
	local _, screens = contentScreens(root)
	local visible = 0
	for _, screen in screens do
		if screen.Visible then
			visible += 1
			assertions.equal(screen.Name, `{expected}Screen`)
		end
	end
	assertions.equal(visible, 1)
end

local function activate(fixture: any, button: GuiButton)
	local listener = fixture.activations[button]
	if listener == nil then
		error("[ATD_TEST_FIXTURE][code=LOBBY_VIEW_ACTIVATION_MISSING]", 0)
	end
	listener()
end

return TestHarness.suite("persistent Lobby presentation", {
	TestHarness.case(
		"expanded noncompact profile status grows the header and reserves the content space",
		function(assertions)
			local fixture = makeFixture()
			local made = (newForTests :: any)(fixture.guiParent, fixture.callback, fixture.dependencies, true)
			assertions.isTrue(made.ok)
			local view = made.value
			local _, root = guiTree(fixture)
			pcall(function()
				(root :: any).AbsoluteSize = Vector2.zero
			end)
			local state = readyState("Settings", "Touch")
			state.viewport = Vector2.new(1178, 819)
			state.settings.uiScale = 0.75
			state.preferredTextScale = 1.5
			state.statusText =
				Localization.format("lobby_controller.welcome_your_starter_towers_and_earn_only", {}, "pseudo50").value
			assertions.isTrue(view:render(state).ok)
			local header = child(root, "Header", "Frame") :: Frame
			local content = child(root, "Content", "Frame") :: Frame
			local navigation = child(root, "Navigation", "Frame") :: Frame
			local readiness = child(header, "ProfileReadiness", "TextLabel") :: TextLabel
			assertions.isTrue(readiness.Visible)
			assertions.isTrue(header.Size.Y.Offset > 92)
			assertions.isTrue(content.Position.Y.Offset >= header.Position.Y.Offset + header.Size.Y.Offset)
			assertions.equal(navigation.Position.Y.Offset, content.Position.Y.Offset)
			assertions.isTrue(content.Size.Y.Offset > 240)
			view:cleanup()
			fixture.guiParent:Destroy()
		end
	),
	TestHarness.case(
		"expanded inventory toolbar grows without overlapping or moving the grid bottom",
		function(assertions)
			local fixture = makeFixture()
			local made = (newForTests :: any)(fixture.guiParent, fixture.callback, fixture.dependencies, true)
			assertions.isTrue(made.ok)
			local view = made.value
			local _, root = guiTree(fixture)
			pcall(function()
				(root :: any).AbsoluteSize = Vector2.zero
			end)
			local state = readyState("Inventory", "Touch")
			state.selectedUnitId = nil
			state.viewport = Vector2.new(666, 316)
			state.settings.uiScale = 0.75
			assertions.isTrue(view:render(state).ok)
			local page = child(root, "ATDCompactPage", "ScrollingFrame")
			local content = child(page, "Content", "Frame")
			local inventory = child(content, "InventoryScreen", "Frame")
			local filter = child(inventory, "Filter", "TextButton") :: TextButton
			local sort = child(inventory, "Sort", "TextButton") :: TextButton
			local grid = child(inventory, "OwnedTowerGrid", "ScrollingFrame") :: ScrollingFrame
			local beforeHeight = filter.Size.Y.Offset
			local bottomOffset = grid.Position.Y.Offset + grid.Size.Y.Offset
			activate(fixture, filter)
			activate(fixture, filter)
			state.preferredTextScale = 1.5
			Localization.setMode("pseudo50")
			local rendered = view:render(state)
			Localization.setMode("en")
			assertions.isTrue(rendered.ok)
			assertions.isTrue(filter.Size.Y.Offset > beforeHeight)
			assertions.equal(sort.Size.Y.Offset, filter.Size.Y.Offset)
			assertions.isTrue(grid.Position.Y.Offset >= filter.Position.Y.Offset + filter.Size.Y.Offset)
			assertions.equal(grid.Position.Y.Offset + grid.Size.Y.Offset, bottomOffset)
			assertions.equal((child(inventory, "Search", "TextBox") :: TextBox).PlaceholderText, "Search towers")
			view:cleanup()
			fixture.guiParent:Destroy()
		end
	),
	TestHarness.case(
		"small UI scale preserves physical touch rows and inline contrasting notifications",
		function(assertions)
			local fixture = makeFixture()
			local made = (newForTests :: any)(fixture.guiParent, fixture.callback, fixture.dependencies, true)
			assertions.isTrue(made.ok)
			local view = made.value
			local _, root = guiTree(fixture)
			pcall(function()
				(root :: any).AbsoluteSize = Vector2.zero
			end)
			local state = readyState("Settings", "Touch")
			state.viewport = Vector2.new(666, 316)
			state.settings.uiScale = 0.75
			state.toasts = {
				{
					id = "toast:scale",
					kind = "Success",
					title = "Settings saved",
					message = "Your settings were saved to your profile.",
					repeatCount = 2,
				},
			}
			assertions.isTrue(view:render(state).ok)
			local page = child(root, "ATDCompactPage", "ScrollingFrame")
			local content = child(page, "Content", "Frame") :: Frame
			local notifications = child(page, "Notifications", "Frame") :: Frame
			local settingsScreen = child(content, "SettingsScreen", "Frame")
			local settingsList = child(settingsScreen, "SettingsList", "ScrollingFrame")
			for _, control in settingsList:GetChildren() do
				if control:IsA("TextButton") then
					assertions.isTrue(control.Size.Y.Offset * 0.75 >= 44)
				end
			end
			assertions.isTrue(
				notifications.Position.Y.Offset + notifications.Size.Y.Offset <= content.Position.Y.Offset
			)
			assertions.equal(notifications.Size.X.Offset, 868)
			local toastBody = child(notifications, "ATDReadableContent", "ScrollingFrame")
			local toast = child(toastBody, "Toast1", "TextButton") :: TextButton
			assertions.equal(toast.BackgroundColor3, Theme.Colors.Success)
			assertions.equal(toast.TextColor3, Theme.Colors.Backdrop)
			assertions.isTrue(toast.Size.Y.Offset * 0.75 >= 44)
			activate(fixture, toast)
			assertions.equal(fixture.actions[#fixture.actions].kind, "DismissToast")
			view:cleanup()
			fixture.guiParent:Destroy()
		end
	),
	TestHarness.case(
		"same-screen scale updates restore surviving focus after engine-style clearing",
		function(assertions)
			local fixture = makeFixture()
			local made = (newForTests :: any)(fixture.guiParent, fixture.callback, fixture.dependencies, true)
			assertions.isTrue(made.ok)
			local view = made.value
			local _, root = guiTree(fixture)
			pcall(function()
				(root :: any).AbsoluteSize = Vector2.zero
			end)
			local state = readyState("Settings", "Gamepad")
			state.viewport = Vector2.new(666, 316)
			state.settings.uiScale = 1
			assertions.isTrue(view:render(state).ok)
			fixture.inputListeners[1]("Tab", false)
			local scaleButton = root:FindFirstChild("uiScale", true) :: TextButton
			assertions.isNotNil(scaleButton)
			assertions.isNil(scaleButton:GetAttribute("ATDControlKey"))
			fixture.selected = scaleButton
			-- The live engine clears selection during ancestor reparenting. The
			-- isolated adapter clears it at owned dynamic cleanup in the same render.
			fixture.clearFocusOnDynamicDisconnect = true
			state.profileRevision += 1
			state.settings.uiScale = 1.125
			assertions.isTrue(view:render(state).ok)
			assertions.isTrue(fixture.focusClearCount > 0)
			assertions.equal(fixture.selected, scaleButton)
			fixture.inputListeners[1]("Return", false)
			assertions.equal(fixture.actions[#fixture.actions].kind, "UpdateSetting")
			assertions.equal(fixture.actions[#fixture.actions].settingKey, "uiScale")

			local nextScreen = readyState("Home", "Gamepad")
			nextScreen.viewport = state.viewport
			assertions.isTrue(view:render(nextScreen).ok)
			assertions.isTrue(fixture.selected ~= scaleButton)
			assertions.equal(fixture.selected, root:FindFirstChild("Play", true))
			view:cleanup()
			fixture.guiParent:Destroy()
		end
	),

	TestHarness.case("recreated inventory controls restore focus by stable owned-unit identity", function(assertions)
		withView(function(view, fixture)
			local state = readyState("Inventory", "Gamepad")
			assertions.isTrue(view:render(state).ok)
			local _, root = guiTree(fixture)
			local content = child(root, "Content", "Frame")
			local inventory = child(content, "InventoryScreen", "Frame")
			local grid = child(inventory, "OwnedTowerGrid", "ScrollingFrame")
			local card = child(grid, "TowerCard2", "TextButton") :: TextButton
			local key = card:GetAttribute("ATDControlKey")
			fixture.selected = card
			state.preferredTextScale = 1.5
			assertions.isTrue(view:render(state).ok)
			assertions.isTrue(fixture.selected ~= card)
			assertions.equal(fixture.selected:GetAttribute("ATDControlKey"), key)
			assertions.isTrue(fixture.selected.TextSize >= 16)
		end)
	end),
	TestHarness.case("ordinary updates and input changes preserve the selected tutorial action", function(assertions)
		withView(function(view, fixture)
			local state = readyState("Home", "Desktop")
			state.tutorialGuidance = {
				step = 1,
				title = "Gold and Battle Cash",
				message = "Gold is permanent; Battle Cash is match-only.",
				primaryActionText = "GOT IT",
				canAdvance = true,
				canSkip = true,
				canReplay = false,
			}
			assertions.isTrue(view:render(state).ok)
			fixture.inputListeners[1]("Tab", false)
			local _, root = guiTree(fixture)
			local skip = child(child(root, "ATDTutorialGuidance", "Frame"), "Skip", "TextButton")
			fixture.selected = skip
			for _, family in { "Desktop", "Touch", "Gamepad", "Desktop" } do
				state.inputFamily = family
				state.preferredTextScale = 1.5
				state.preferredTransparency = 0
				assertions.isTrue(view:render(state).ok)
				assertions.equal(fixture.selected, skip)
			end
			fixture.inputListeners[1]("Return", false)
			assertions.equal(fixture.actions[#fixture.actions].kind, "SkipTutorial")
		end)
	end),
	TestHarness.case(
		"small safe landscape with largest expanded text keeps chrome separate and guidance actions reachable",
		function(assertions)
			local fixture = makeFixture()
			local result = (newForTests :: any)(fixture.guiParent, fixture.callback, fixture.dependencies, true)
			assertions.isTrue(result.ok)
			local view = result.value
			local _, testRoot = guiTree(fixture)
			pcall(function()
				(testRoot :: any).AbsoluteSize = Vector2.zero
			end)
			local state = readyState("Home", "Touch")
			state.viewport = Vector2.new(666, 316)
			state.settings.uiScale = 1
			state.preferredTextScale = 1.5
			Localization.setMode("pseudo50")
			state.tutorialGuidance = {
				step = 1,
				title = "Gold and Battle Cash",
				message = Localization.text("lobby_controller.gold_is_permanent_and_opens_earn_only"),
				primaryActionText = Localization.enum("action", "CONTINUE"),
				canAdvance = true,
				canSkip = true,
				canReplay = false,
			}
			local rendered = view:render(state)
			Localization.setMode("en")
			assertions.isTrue(rendered.ok)
			local _, root = guiTree(fixture)
			local page = child(root, "ATDCompactPage", "ScrollingFrame") :: ScrollingFrame
			local header = child(root, "Header", "Frame") :: Frame
			local navigation = child(root, "Navigation", "Frame") :: Frame
			local guide = child(page, "ATDTutorialGuidance", "Frame") :: Frame
			local body = child(guide, "GuideBody", "ScrollingFrame") :: ScrollingFrame
			local primary = child(guide, "Primary", "TextButton") :: TextButton
			local content = child(page, "Content", "Frame") :: Frame
			assertions.isTrue(header.Position.Y.Offset + header.Size.Y.Offset <= page.Position.Y.Offset)
			assertions.isTrue(page.Position.Y.Offset + page.Size.Y.Offset <= 316 + navigation.Position.Y.Offset)
			assertions.isTrue(primary.Size.Y.Offset >= 44)
			assertions.isTrue(primary.Position.Y.Offset + primary.Size.Y.Offset <= guide.Size.Y.Offset)
			assertions.isTrue(body.CanvasSize.Y.Offset > body.Size.Y.Offset)
			assertions.isTrue(content.Position.Y.Offset >= guide.Size.Y.Offset)
			assertions.isTrue(content.Size.Y.Offset >= 240)
			assertions.isTrue(page.CanvasSize.Y.Offset >= content.Position.Y.Offset + content.Size.Y.Offset)
			local home = child(content, "HomeScreen", "Frame")
			local homeBody = child(home, "ATDReadableContent", "ScrollingFrame") :: ScrollingFrame
			local heading = child(homeBody, "Heading", "TextLabel") :: TextLabel
			local progression = child(homeBody, "Progression", "TextLabel") :: TextLabel
			local play = child(homeBody, "Play", "TextButton") :: TextButton
			assertions.equal(heading.Size.X.Scale, 1)
			assertions.isTrue(heading.Size.Y.Offset < 200)
			assertions.isTrue(play.Position.Y.Offset >= progression.Position.Y.Offset + progression.Size.Y.Offset)
			assertions.isTrue(homeBody.CanvasSize.Y.Offset < 800)
			assertions.isTrue(view:render(state).ok)
			assertions.equal(heading.Size.X.Scale, 1)
			assertions.isTrue(heading.Size.Y.Offset < 200)
			local navScroll = child(navigation, "ATDNavigationScroll", "ScrollingFrame") :: ScrollingFrame
			assertions.isTrue(navScroll.CanvasSize.X.Offset > 646)
			for _, control in navScroll:GetChildren() do
				if control:IsA("TextButton") then
					assertions.isTrue(control.TextSize >= 23)
					assertions.isTrue(control.Size.Y.Offset >= 44)
				end
			end
			view:cleanup()
			fixture.guiParent:Destroy()
		end
	),
	TestHarness.case("keyboard traversal contains modal focus and restores the surviving control", function(assertions)
		withView(function(view, fixture)
			local state = readyState("Settings", "Desktop")
			assertions.isTrue(view:render(state).ok)
			fixture.inputListeners[1]("Tab", false)
			assertions.isNotNil(fixture.selected)
			local before = fixture.selected
			local modalState = readyState("Settings", "Desktop")
			modalState.modals = {
				{
					id = "modal:keyboard",
					title = "Confirm",
					message = "Confirm the action.",
					confirmText = "Confirm",
					cancelText = "Cancel",
					dismissable = true,
					busy = false,
				},
			}
			assertions.isTrue(view:render(modalState).ok)
			local _, root = guiTree(fixture)
			local scrim = child(root, "ModalScrim", "Frame") :: Frame
			local panel = child(scrim, "ModalPanel", "Frame") :: Frame
			for _ = 1, 5 do
				fixture.inputListeners[1]("Tab", false)
				assertions.isTrue(fixture.selected:IsDescendantOf(panel))
			end
			fixture.inputListeners[1]("Return", false)
			assertions.isTrue(#fixture.actions > 0)
			assertions.isTrue(view:render(state).ok)
			assertions.equal(fixture.selected, before)
		end)
	end),
	TestHarness.case("party invitation cycles present candidates without any keyboard text entry", function(assertions)
		withView(function(view, fixture)
			fixture.dependencies.getPresentPlayers = function()
				return { { userId = 999, displayName = "Second" }, { userId = 998, displayName = "First" } }
			end
			local state = squadState("Party")
			state.inputFamily = "Gamepad"
			assertions.isTrue(view:render(state).ok)
			local _, root = guiTree(fixture)
			local content = child(root, "Content", "Frame") :: Frame
			local screen = child(content, "PartyScreen", "Frame") :: Frame
			local party = child(screen, "PartyContent", "ScrollingFrame") :: ScrollingFrame
			local picker = child(party, "ChoosePlayer", "TextButton") :: TextButton
			assertions.contains(picker.Text, "First")
			assertions.isFalse((child(party, "InviteUserId", "TextBox") :: TextBox).Visible)
			activate(fixture, picker)
			assertions.contains(picker.Text, "Second")
			activate(fixture, child(party, "InviteMember", "TextButton") :: TextButton)
			assertions.equal(fixture.actions[#fixture.actions].kind, "InvitePartyMember")
			assertions.equal(fixture.actions[#fixture.actions].targetUserId, 999)
		end)
	end),
	TestHarness.case("owns one GUI and never flashes default profile values", function(assertions)
		withView(function(view, fixture)
			assertions.isTrue(table.isfrozen(LobbyView))
			assertions.isTrue(table.isfrozen(view))
			local gui, root = guiTree(fixture)
			assertions.isFalse(gui.ResetOnSpawn)
			assertions.isFalse(gui.IgnoreGuiInset)
			assertions.equal(gui.DisplayOrder, 40)
			local header = child(root, "Header", "Frame") :: Frame
			local content = child(root, "Content", "Frame") :: Frame
			local blocking = child(root, "ProfileBlocking", "Frame") :: Frame
			assertions.isFalse(header.Visible)
			assertions.isFalse(content.Visible)
			assertions.isTrue(blocking.Visible)
			assertions.equal((child(header, "Gold", "TextLabel") :: TextLabel).Text, "GOLD —")
			assertions.isFalse((newForTests :: any)(fixture.guiParent, fixture.callback, fixture.dependencies).ok)
			assertions.equal(#fixture.guiParent:GetChildren(), 1)

			assertions.isTrue(view:render(loadingState()).ok)
			assertions.isTrue(view:getMetrics().blockingVisible)
			assertions.equal(view:getMetrics().goldText, "GOLD —")
			assertions.contains((child(blocking, "Message", "TextLabel") :: TextLabel).Text, "saved profile")

			local failed = loadingState()
			failed.profileState = "Failed"
			failed.statusText = "Profile load failed safely. No writable blank profile was created."
			failed.canRetry = true
			assertions.isTrue(view:render(failed).ok)
			assertions.contains((child(blocking, "Title", "TextLabel") :: TextLabel).Text, "FAILED")
			assertions.isTrue((child(blocking, "Retry", "TextButton") :: TextButton).Active)
			assertions.equal(view:getMetrics().goldText, "GOLD —")

			local releasing = loadingState()
			releasing.profileState = "Releasing"
			releasing.statusText = "Saving and releasing your profile safely."
			releasing.canLeave = false
			assertions.isTrue(view:render(releasing).ok)
			assertions.contains((child(blocking, "Title", "TextLabel") :: TextLabel).Text, "RELEASING")
		end)
	end),

	TestHarness.case(
		"focuses stable failure actions and clears them before the surface is hidden",
		function(assertions)
			withView(function(view, fixture)
				local failed = loadingState()
				failed.profileState = "Failed"
				failed.canRetry = true
				failed.inputFamily = "Gamepad"
				assertions.isTrue(view:render(failed).ok)
				local _, root = guiTree(fixture)
				local blocking = child(root, "ProfileBlocking", "Frame") :: Frame
				local retry = child(blocking, "Retry", "TextButton") :: TextButton
				assertions.equal(fixture.selected, retry)

				assertions.isTrue(view:render(readyState("Home", "Desktop")).ok)
				assertions.isFalse(blocking.Visible)
				assertions.isNil(fixture.selected)
			end)
		end
	),

	TestHarness.case("renders one Ready screen with duplicate unit records and full details", function(assertions)
		withView(function(view, fixture)
			assertions.isTrue(view:render(readyState("Home")).ok)
			local _, root = guiTree(fixture)
			local header = child(root, "Header", "Frame") :: Frame
			assertions.equal((child(header, "Gold", "TextLabel") :: TextLabel).Text, "GOLD 2,500")
			assertions.isTrue((child(header, "Title", "TextLabel") :: TextLabel).Visible)
			assertions.isFalse(view:getMetrics().blockingVisible)
			assertOneActiveScreen(assertions, root, "Home")

			local inventoryState = readyState("Inventory")
			assertions.isTrue(view:render(inventoryState).ok)
			assertOneActiveScreen(assertions, root, "Inventory")
			assertions.isTrue((child(header, "Back", "TextButton") :: TextButton).Visible)
			assertions.isFalse((child(header, "Title", "TextLabel") :: TextLabel).Visible)
			assertions.equal(view:getMetrics().inventoryCardCount, 3)
			local content = child(root, "Content", "Frame") :: Frame
			local inventory = child(content, "InventoryScreen", "Frame") :: Frame
			local grid = child(inventory, "OwnedTowerGrid", "ScrollingFrame") :: ScrollingFrame
			local first = child(grid, "TowerCard1", "TextButton") :: TextButton
			local second = child(grid, "TowerCard2", "TextButton") :: TextButton
			local third = child(grid, "TowerCard3", "TextButton") :: TextButton
			assertions.contains(first.Text, "Dart Ant")
			assertions.contains(first.Text, "COPIES 2")
			assertions.contains(second.Text, "Dart Ant")
			assertions.contains(second.Text, "COPIES 2")
			assertions.contains(third.Text, "Rapid Ant")

			local details = child(inventory, "TowerDetails", "ScrollingFrame") :: ScrollingFrame
			assertions.equal((child(details, "TowerName", "TextLabel") :: TextLabel).Text, "Dart Ant")
			assertions.contains((child(details, "Ownership", "TextLabel") :: TextLabel).Text, "OWNED COPIES 2")
			assertions.contains((child(details, "Ownership", "TextLabel") :: TextLabel).Text, "earn-only")
			assertions.contains((child(details, "CombatStats", "TextLabel") :: TextLabel).Text, "DAMAGE 12")
			assertions.contains((child(details, "CombatStats", "TextLabel") :: TextLabel).Text, "TARGETING")
			assertions.contains((child(details, "UpgradePreview", "TextLabel") :: TextLabel).Text, "MATCH UPGRADE")

			activate(fixture, second)
			local action = fixture.actions[#fixture.actions]
			assertions.equal(action.kind, "SelectTower")
			assertions.equal(action.unitId, "unit:dart-ant:002")
			assertions.equal(action.towerId, "tower:dart-ant")
			assertions.equal(action.profileRevision, 7)

			local selectedDuplicate = readyState("Inventory")
			selectedDuplicate.selectedUnitId = "unit:dart-ant:002"
			assertions.isTrue(view:render(selectedDuplicate).ok)
			assertions.equal((child(details, "Lock", "TextButton") :: TextButton).Text, "◆ LOCKED")
		end)
	end),

	TestHarness.case("shows earn only odds settings accessibility and typed toasts", function(assertions)
		withView(function(view, fixture)
			local chestsState = readyState("Chests")
			chestsState.toasts = {
				{ id = "toast:info", kind = "Info", title = "Info", message = "Profile ready.", repeatCount = 1 },
				{
					id = "toast:success",
					kind = "Success",
					title = "Saved",
					message = "Loadout saved.",
					repeatCount = 1,
				},
				{
					id = "toast:warning",
					kind = "Warning",
					title = "Notice",
					message = "Pity is close.",
					repeatCount = 1,
				},
				{ id = "toast:error", kind = "Error", title = "Network", message = "Request failed.", repeatCount = 3 },
			}
			assertions.isTrue(view:render(chestsState).ok)
			local gui, root = guiTree(fixture)
			assertOneActiveScreen(assertions, root, "Chests")
			local content = child(root, "Content", "Frame") :: Frame
			local chests = child(content, "ChestsScreen", "Frame") :: Frame
			local chestScroll = child(chests, "ChestScroll", "ScrollingFrame") :: ScrollingFrame
			assertions.equal((child(chestScroll, "Heading", "TextLabel") :: TextLabel).Text, "Starter Tower Chest")
			assertions.contains((child(chestScroll, "Policy", "TextLabel") :: TextLabel).Text, "EARN-ONLY GOLD")
			assertions.contains(
				(child(chestScroll, "Policy", "TextLabel") :: TextLabel).Text,
				"Duplicates remain separate units"
			)
			local odds = (child(chestScroll, "Odds", "TextLabel") :: TextLabel).Text
			assertions.contains(odds, "Dart Ant: 60%")
			assertions.contains(odds, "Rapid Ant: 30%")
			assertions.contains(odds, "Guard Ant: 10%")
			assertions.contains((child(chestScroll, "Pity", "TextLabel") :: TextLabel).Text, "2 / 10")
			assertions.contains((child(chestScroll, "OnePull", "TextButton") :: TextButton).Text, "250 GOLD")
			assertions.contains((child(chestScroll, "TenPull", "TextButton") :: TextButton).Text, "2,250 GOLD")

			local notifications = child(root, "Notifications", "Frame") :: Frame
			assertions.equal(view:getMetrics().toastCount, 4)
			for index, color in { Theme.Colors.Info, Theme.Colors.Success, Theme.Colors.Warning, Theme.Colors.Error } do
				local toast = child(notifications, `Toast{index}`, "TextButton") :: TextButton
				assertions.equal(toast.BackgroundColor3, color)
				assertions.equal(toast.TextColor3, Theme.Colors.Backdrop)
			end
			assertions.contains((child(notifications, "Toast1", "TextButton") :: TextButton).Text, "i Info")
			assertions.contains((child(notifications, "Toast2", "TextButton") :: TextButton).Text, "✓ Saved")
			assertions.contains((child(notifications, "Toast3", "TextButton") :: TextButton).Text, "! Notice")
			local repeated = child(notifications, "Toast4", "TextButton") :: TextButton
			assertions.contains(repeated.Text, "✕ Network")
			assertions.contains(repeated.Text, "Repeated ×3")
			activate(fixture, repeated)
			assertions.equal(fixture.actions[#fixture.actions].kind, "DismissToast")
			assertions.equal(fixture.actions[#fixture.actions].toastId, "toast:error")

			local settingsState = readyState("Settings")
			assertions.isTrue(view:render(settingsState).ok)
			assertOneActiveScreen(assertions, root, "Settings")
			local settingsScreen = child(content, "SettingsScreen", "Frame") :: Frame
			local list = child(settingsScreen, "SettingsList", "ScrollingFrame") :: ScrollingFrame
			local reduced = child(list, "reducedMotionEnabled", "TextButton") :: TextButton
			local uiScale = child(list, "uiScale", "TextButton") :: TextButton
			assertions.contains(reduced.Text, "Reduced Motion: ON")
			assertions.contains(uiScale.Text, "UI Scale: 113%")
			assertions.equal((child(root, "PlayerUiScale", "UIScale") :: UIScale).Scale, 1.125)
			assertions.isTrue(math.abs(root.Size.X.Scale - (1 / 1.125)) < 1e-5)
			assertions.isTrue(math.abs(root.Size.Y.Scale - (1 / 1.125)) < 1e-5)
			assertions.equal(gui:GetAttribute("ATDReducedMotion"), true)
			activate(fixture, reduced)
			assertions.equal(fixture.actions[#fixture.actions].kind, "UpdateSetting")
			assertions.equal(fixture.actions[#fixture.actions].settingKey, "reducedMotionEnabled")
			assertions.equal(fixture.actions[#fixture.actions].settingValue, false)
			activate(fixture, uiScale)
			assertions.equal(fixture.actions[#fixture.actions].settingValue, 1.25)

			local robloxReduced = readyState("Settings")
			robloxReduced.settings.reducedMotionEnabled = false
			robloxReduced.reducedMotion = true
			assertions.isTrue(view:render(robloxReduced).ok)
			assertions.equal(gui:GetAttribute("ATDReducedMotion"), true)
		end)
	end),

	TestHarness.case("processed Escape stays with Roblox while unprocessed Backspace goes back", function(assertions)
		withView(function(view, fixture)
			assertions.isTrue(view:render(readyState("Party")).ok)
			fixture.inputListeners[1]("Escape", true)
			assertions.equal(#fixture.actions, 0)
			fixture.inputListeners[1]("Backspace", true)
			assertions.equal(#fixture.actions, 0)
			fixture.inputListeners[1]("Backspace", false)
			assertions.equal(#fixture.actions, 1)
			assertions.equal(fixture.actions[1].kind, "Back")
		end)
	end),

	TestHarness.case("blocks modal click through and restores gamepad focus", function(assertions)
		withView(function(view, fixture)
			local base = readyState("Inventory", "Gamepad")
			base.banner.transactionPending = true
			base.toasts = {
				{ id = "toast:under-modal", kind = "Error", title = "Network", message = "Retrying.", repeatCount = 2 },
			}
			assertions.isTrue(view:render(base).ok)
			local _, root = guiTree(fixture)
			local content = child(root, "Content", "Frame") :: Frame
			local inventory = child(content, "InventoryScreen", "Frame") :: Frame
			local search = child(inventory, "Search", "TextBox") :: TextBox
			fixture.selected = search

			local modal = readyState("Inventory", "Gamepad")
			modal.banner.transactionPending = true
			modal.toasts = base.toasts
			modal.modals = {
				{
					id = "confirm:pull",
					title = "Open chest",
					message = "Spend earned Gold for a server-owned result?",
					confirmText = "OPEN",
					cancelText = "CANCEL",
					dismissable = true,
					busy = false,
				},
			}
			assertions.isTrue(view:render(modal).ok)
			local scrim = child(root, "ModalScrim", "Frame") :: Frame
			local panel = child(scrim, "ModalPanel", "Frame") :: Frame
			local confirm = child(panel, "Confirm", "TextButton") :: TextButton
			assertions.isTrue(scrim.Visible)
			assertions.isTrue(scrim.Active)
			assertions.isTrue(scrim.ZIndex > content.ZIndex)
			assertions.equal(fixture.selected, confirm)

			local grid = child(inventory, "OwnedTowerGrid", "ScrollingFrame") :: ScrollingFrame
			local coveredCard = child(grid, "TowerCard1", "TextButton") :: TextButton
			local notifications = child(root, "Notifications", "Frame") :: Frame
			local coveredToast = child(notifications, "Toast1", "TextButton") :: TextButton
			local chests = child(content, "ChestsScreen", "Frame") :: Frame
			local chestScroll = child(chests, "ChestScroll", "ScrollingFrame") :: ScrollingFrame
			local coveredSkip = child(chestScroll, "SkipPresentation", "TextButton") :: TextButton
			assertions.isFalse(coveredCard.Active)
			assertions.isFalse(coveredCard.Selectable)
			assertions.isFalse(coveredToast.Active)
			assertions.isFalse(coveredSkip.Active)
			local beforeCovered = #fixture.actions
			activate(fixture, coveredCard)
			activate(fixture, coveredToast)
			activate(fixture, coveredSkip)
			assertions.equal(#fixture.actions, beforeCovered)

			activate(fixture, confirm)
			assertions.equal(fixture.actions[#fixture.actions].kind, "ConfirmModal")
			assertions.equal(fixture.actions[#fixture.actions].modalId, "confirm:pull")
			fixture.inputListeners[1]("Escape", false)
			fixture.inputListeners[1]("ButtonB", false)
			activate(fixture, child(child(root, "Header", "Frame"), "Back", "TextButton") :: TextButton)
			assertions.equal(fixture.actions[#fixture.actions - 2].kind, "Back")
			assertions.equal(fixture.actions[#fixture.actions - 1].kind, "Back")
			assertions.equal(fixture.actions[#fixture.actions].kind, "Back")

			assertions.isTrue(view:render(base).ok)
			assertions.isFalse(scrim.Visible)
			assertions.equal(fixture.selected, search)
		end)
	end),

	TestHarness.case("routes desktop touch gamepad and responsive safe layouts", function(assertions)
		withView(function(view, fixture)
			local desktop = readyState("Home", "Desktop")
			assertions.isTrue(view:render(desktop).ok)
			local _, root = guiTree(fixture)
			local content = child(root, "Content", "Frame") :: Frame
			local home = child(content, "HomeScreen", "Frame") :: Frame
			activate(fixture, child(home, "Play", "TextButton") :: TextButton)
			assertions.equal(fixture.actions[#fixture.actions].kind, "Play")
			assertions.equal(fixture.actions[#fixture.actions].source, "Desktop")

			local touch = readyState("Home", "Touch")
			touch.viewport = Vector2.new(375, 667)
			assertions.isTrue(view:render(touch).ok)
			local navigation = child(root, "Navigation", "Frame") :: Frame
			local header = child(root, "Header", "Frame") :: Frame
			assertions.equal(navigation.Position.Y.Scale, 1)
			assertions.equal(navigation.Size.X.Scale, 1)
			assertions.equal(header.Position.X.Offset, 10)
			local inventoryButton = child(navigation, "Inventory", "TextButton") :: TextButton
			activate(fixture, inventoryButton)
			assertions.equal(fixture.actions[#fixture.actions].kind, "Navigate")
			assertions.equal(fixture.actions[#fixture.actions].screen, "Inventory")
			assertions.equal(fixture.actions[#fixture.actions].source, "Touch")

			local compactInventory = readyState("Inventory", "Touch")
			compactInventory.viewport = Vector2.new(749, 361)
			compactInventory.selectedUnitId = nil
			assertions.isTrue(view:render(compactInventory).ok)
			local inventory = child(content, "InventoryScreen", "Frame") :: Frame
			local grid = child(inventory, "OwnedTowerGrid", "ScrollingFrame") :: ScrollingFrame
			local details = child(inventory, "TowerDetails", "ScrollingFrame") :: ScrollingFrame
			assertions.isTrue(grid.Visible)
			assertions.isFalse(details.Visible)
			activate(fixture, child(grid, "TowerCard1", "TextButton") :: TextButton)
			assertions.equal(fixture.actions[#fixture.actions].kind, "SelectTower")
			assertions.isFalse(grid.Visible)
			assertions.isTrue(details.Visible)
			local closeDetails = child(details, "CloseDetails", "TextButton") :: TextButton
			assertions.isTrue(closeDetails.Visible)
			activate(fixture, closeDetails)
			assertions.equal(fixture.actions[#fixture.actions].kind, "CloseTowerDetails")
			assertions.isTrue(view:render(compactInventory).ok)
			assertions.isTrue(grid.Visible)
			assertions.isFalse(details.Visible)

			local gamepad = readyState("Settings", "Gamepad")
			gamepad.viewport = Vector2.new(1920, 1080)
			assertions.isTrue(view:render(gamepad).ok)
			assertions.equal(navigation.Size.X.Offset, 252)
			assertions.equal(header.Position.X.Offset, 36)
			local settingsScreen = child(content, "SettingsScreen", "Frame") :: Frame
			local list = child(settingsScreen, "SettingsList", "ScrollingFrame") :: ScrollingFrame
			local range = child(list, "towerRangeEnabled", "TextButton") :: TextButton
			assertions.equal(fixture.selected, child(list, "masterVolume", "TextButton"))
			activate(fixture, range)
			assertions.equal(fixture.actions[#fixture.actions].kind, "UpdateSetting")
			assertions.equal(fixture.actions[#fixture.actions].source, "Gamepad")
			fixture.familyListeners[1]("Touch")
			assertions.equal(fixture.actions[#fixture.actions].kind, "InputFamilyChanged")
			assertions.equal(fixture.actions[#fixture.actions].inputFamily, "Touch")
		end)
	end),

	TestHarness.case(
		"keeps compact landscape party and queue actions reachable above bottom navigation",
		function(assertions)
			withView(function(view, fixture)
				local partyState = readyState("Party", "Touch")
				partyState.viewport = Vector2.new(749, 361)
				assertions.isTrue(view:render(partyState).ok)

				local _, root = guiTree(fixture)
				local navigation = child(root, "Navigation", "Frame") :: Frame
				local content = child(root, "Content", "Frame") :: Frame
				local partyScreen = child(content, "PartyScreen", "Frame") :: Frame
				local party = child(partyScreen, "PartyContent", "ScrollingFrame") :: ScrollingFrame
				local create = child(party, "CreateParty", "TextButton") :: TextButton
				local inviteInput = child(party, "InviteUserId", "TextBox") :: TextBox
				local logicalHeight = partyState.viewport.Y / partyState.settings.uiScale
				local contentBottom = content.Position.Y.Offset + logicalHeight + content.Size.Y.Offset
				local navigationTop = logicalHeight + navigation.Position.Y.Offset

				assertions.equal(navigation.Size.Y.Offset, 68)
				assertions.equal((child(navigation, "Home", "TextButton") :: TextButton).Position.Y.Offset, 8)
				assertions.equal((child(navigation, "Settings", "TextButton") :: TextButton).Position.Y.Offset, 8)
				assertions.isTrue(content.ClipsDescendants)
				assertions.isTrue(contentBottom <= navigationTop)
				assertions.isTrue(create.Visible)
				assertions.isFalse(inviteInput.Visible)
				assertions.isTrue(create.Position.Y.Offset + create.Size.Y.Offset <= party.CanvasSize.Y.Offset)
				assertions.isTrue(create.Position.Y.Offset + create.Size.Y.Offset <= 110)

				local loadingParty = readyState("Party", "Gamepad")
				loadingParty.viewport = Vector2.new(749, 361)
				loadingParty.partyState = "Loading"
				loadingParty.partySnapshot = nil
				assertions.isTrue(view:render(loadingParty).ok)
				assertions.equal(fixture.selected, child(child(root, "Header", "Frame"), "Back", "TextButton"))
				assertions.isFalse(inviteInput.Visible)

				local formedParty = squadState("Party")
				formedParty.inputFamily = "Touch"
				formedParty.viewport = Vector2.new(749, 361)
				assertions.isTrue(view:render(formedParty).ok)
				assertions.isFalse(create.Visible)
				assertions.isFalse(inviteInput.Visible)
				assertions.isTrue((child(party, "ChoosePlayer", "TextButton") :: TextButton).Visible)
				for _, name in { "InviteFriends", "Privacy", "LeaveParty", "DisbandParty" } do
					local action = child(party, name, "TextButton") :: TextButton
					assertions.isTrue(action.Position.Y.Offset + action.Size.Y.Offset <= party.CanvasSize.Y.Offset)
				end

				local queueState = squadState("Queue", true)
				queueState.inputFamily = "Touch"
				queueState.viewport = Vector2.new(749, 361)
				assertions.isTrue(view:render(queueState).ok)
				local queueScreen = child(content, "QueueScreen", "Frame") :: Frame
				local queue = child(queueScreen, "QueueContent", "ScrollingFrame") :: ScrollingFrame
				assertions.isTrue(queue.CanvasSize.Y.Offset > 0)
				for _, name in
					{
						"JoinQueue",
						"LeaveQueue",
						"Map",
						"Difficulty",
						"QueuePrivacy",
						"Capacity",
						"StartQueue",
						"ReconnectMatch",
					}
				do
					local action = child(queue, name, "TextButton") :: TextButton
					assertions.isTrue(action.Position.Y.Offset + action.Size.Y.Offset <= queue.CanvasSize.Y.Offset)
				end
			end)
		end
	),

	TestHarness.case("closes compact details before Back and restores valid gamepad focus", function(assertions)
		withView(function(view, fixture)
			local compact = readyState("Inventory", "Gamepad")
			compact.viewport = Vector2.new(749, 361)
			compact.selectedUnitId = nil
			assertions.isTrue(view:render(compact).ok)

			local _, root = guiTree(fixture)
			local content = child(root, "Content", "Frame") :: Frame
			local inventory = child(content, "InventoryScreen", "Frame") :: Frame
			local grid = child(inventory, "OwnedTowerGrid", "ScrollingFrame") :: ScrollingFrame
			local details = child(inventory, "TowerDetails", "ScrollingFrame") :: ScrollingFrame
			local detailBack = child(details, "CloseDetails", "TextButton") :: TextButton
			local headerBack = child(child(root, "Header", "Frame"), "Back", "TextButton") :: TextButton

			local function openDetails()
				local card = child(grid, "TowerCard1", "TextButton") :: TextButton
				fixture.selected = card
				activate(fixture, card)
				assertions.equal(fixture.actions[#fixture.actions].kind, "SelectTower")
				assertions.isTrue(details.Visible)
				assertions.equal(fixture.selected, detailBack)
			end

			openDetails()
			activate(fixture, headerBack)
			assertions.equal(fixture.actions[#fixture.actions].kind, "CloseTowerDetails")

			assertions.isTrue(view:render(compact).ok)
			openDetails()
			fixture.inputListeners[1]("Escape", false)
			assertions.equal(fixture.actions[#fixture.actions].kind, "CloseTowerDetails")

			assertions.isTrue(view:render(compact).ok)
			openDetails()
			fixture.inputListeners[1]("ButtonB", false)
			assertions.equal(fixture.actions[#fixture.actions].kind, "CloseTowerDetails")

			assertions.isTrue(view:render(compact).ok)
			activate(fixture, headerBack)
			assertions.equal(fixture.actions[#fixture.actions].kind, "Back")
		end)
	end),

	TestHarness.case(
		"preserves an uncommitted party invite draft through authoritative rerenders",
		function(assertions)
			for _, family in { "Desktop", "Touch", "Gamepad" } do
				withView(function(view, fixture)
					local state = squadState("Party")
					state.inputFamily = family
					assertions.isTrue(view:render(state).ok)
					local _, root = guiTree(fixture)
					local content = child(root, "Content", "Frame")
					local partyScreen = child(content, "PartyScreen", "Frame")
					local party = child(partyScreen, "PartyContent", "ScrollingFrame")
					local inviteInput = child(party, "InviteUserId", "TextBox") :: TextBox
					local userIdText = "11604687814"
					for index = 1, #userIdText do
						local draft = string.sub(userIdText, 1, index)
						inviteInput.Text = draft
						state.profileRevision += 1
						assertions.isTrue(view:render(state).ok)
						assertions.equal(inviteInput.Text, draft)
					end
					assertions.equal(#fixture.actions, 0)
					activate(fixture, child(party, "InviteMember", "TextButton") :: TextButton)
					assertions.equal(#fixture.actions, 1)
					assertions.equal(fixture.actions[1].kind, "InvitePartyMember")
					assertions.equal(fixture.actions[1].targetUserId, 11_604_687_814)
					assertions.equal(fixture.actions[1].source, family)
				end)
			end
		end
	),

	TestHarness.case("submits only the current bounded party invite independently of focus loss", function(assertions)
		withView(function(view, fixture)
			assertions.isTrue(view:render(squadState("Party")).ok)
			local _, root = guiTree(fixture)
			local content = child(root, "Content", "Frame")
			local partyScreen = child(content, "PartyScreen", "Frame")
			local party = child(partyScreen, "PartyContent", "ScrollingFrame")
			local inviteInput = child(party, "InviteUserId", "TextBox") :: TextBox
			local inviteButton = child(party, "InviteMember", "TextButton") :: TextButton
			local loseFocus = fixture.searchListeners[inviteInput] :: (string) -> ()
			loseFocus("202")
			inviteInput.Text = "11604687814"
			activate(fixture, inviteButton)
			assertions.equal(#fixture.actions, 1)
			assertions.equal(fixture.actions[1].targetUserId, 11_604_687_814)
			loseFocus(inviteInput.Text)
			assertions.isTrue(view:render(squadState("Party")).ok)
			assertions.equal(#fixture.actions, 1)
			assertions.equal(inviteInput.Text, "11604687814")
			activate(fixture, inviteButton)
			assertions.equal(#fixture.actions, 2)
			assertions.equal(fixture.actions[2].targetUserId, 11_604_687_814)

			for _, invalid in { "", "not-a-user", "0", "-1", "1.5", "9007199254740992", string.rep("9", 30) } do
				inviteInput.Text = invalid
				activate(fixture, inviteButton)
				assertions.equal(#fixture.actions, 2)
				assertions.isTrue(#inviteInput.Text <= 20)
			end
			loseFocus(string.rep("9", 30))
			assertions.equal(#inviteInput.Text, 20)
			assertions.equal(#fixture.actions, 2)
		end)
	end),

	TestHarness.case(
		"keeps party queue captain and reconnect controls in the permanent accessible shell",
		function(assertions)
			withView(function(view, fixture)
				local _, root = guiTree(fixture)
				local content = child(root, "Content", "Frame") :: Frame
				local partyScreen = child(content, "PartyScreen", "Frame") :: Frame
				local party = child(partyScreen, "PartyContent", "ScrollingFrame") :: ScrollingFrame
				assertions.isTrue(view:render(squadState("Party")).ok)
				assertOneActiveScreen(assertions, root, "Party")
				local inviteInput = child(party, "InviteUserId", "TextBox") :: TextBox
				(fixture.searchListeners[inviteInput] :: (string) -> ())("202")
				activate(fixture, child(party, "InviteMember", "TextButton") :: TextButton)
				local inviteAction = fixture.actions[#fixture.actions]
				assertions.equal(inviteAction.kind, "InvitePartyMember")
				assertions.equal(inviteAction.targetUserId, 202)
				local partyList = child(party, "PartyRosterAndInvites", "ScrollingFrame") :: ScrollingFrame
				activate(fixture, child(partyList, "KickMember2", "TextButton") :: TextButton)
				assertions.equal(fixture.actions[#fixture.actions].kind, "KickPartyMember")
				activate(fixture, child(partyList, "TransferMember2", "TextButton") :: TextButton)
				assertions.equal(fixture.actions[#fixture.actions].kind, "TransferPartyLeadership")

				assertions.isTrue(view:render(squadState("Queue")).ok)
				assertOneActiveScreen(assertions, root, "Queue")
				local queueScreen = child(content, "QueueScreen", "Frame") :: Frame
				local queue = child(queueScreen, "QueueContent", "ScrollingFrame") :: ScrollingFrame
				activate(fixture, child(queue, "JoinQueue", "TextButton") :: TextButton)
				assertions.equal(fixture.actions[#fixture.actions].kind, "JoinQueue")
				assertions.equal(fixture.actions[#fixture.actions].queueId, "queue:alpha")

				assertions.isTrue(view:render(squadState("Queue", true)).ok)
				activate(fixture, child(queue, "QueuePrivacy", "TextButton") :: TextButton)
				local configurationAction = fixture.actions[#fixture.actions]
				assertions.equal(configurationAction.kind, "ConfigureQueue")
				assertions.equal(configurationAction.configuration.privacy, "PartyOnly")
				activate(fixture, child(queue, "StartQueue", "TextButton") :: TextButton)
				assertions.equal(fixture.actions[#fixture.actions].kind, "StartQueue")
				activate(fixture, child(queue, "ReconnectMatch", "TextButton") :: TextButton)
				assertions.equal(fixture.actions[#fixture.actions].kind, "ReconnectActiveMatch")
				assertions.equal(#fixture.guiParent:GetChildren(), 1)
			end)
		end
	),

	TestHarness.case("renders contextual tutorial actions and catalog names without internal IDs", function(assertions)
		withView(function(view, fixture)
			local state = squadState("Queue", true)
			state.tutorialGuidance = {
				step = 1,
				title = "Gold and Battle Cash",
				message = "Gold is permanent; Battle Cash is match-only.",
				primaryActionText = "GOT IT",
				canAdvance = true,
				canSkip = true,
				canReplay = false,
			}
			state.queueMapOptions = {
				{
					mapId = "map:backyard-garden-v1",
					displayName = "Backyard Garden",
					selectable = true,
					difficulties = {
						{ difficultyId = "difficulty:easy-v1", displayName = "Easy", selectable = true },
					},
				},
			}
			state.queueSnapshots[1].configuration.mapId = "map:backyard-garden-v1"
			state.queueSnapshots[1].configuration.difficultyId = "difficulty:easy-v1"
			state.queueSnapshots[1].configuration.privacy = "PartyOnly"
			assertions.isTrue(view:render(state).ok)
			local _, root = guiTree(fixture)
			local tutorial = child(root, "ATDTutorialGuidance", "Frame") :: Frame
			assertions.isTrue(tutorial.Visible)
			assertions.contains((child(tutorial, "Message", "TextLabel") :: TextLabel).Text, "Battle Cash")
			activate(fixture, child(tutorial, "Primary", "TextButton") :: TextButton)
			assertions.equal(fixture.actions[#fixture.actions].kind, "AdvanceTutorial")
			activate(fixture, child(tutorial, "Skip", "TextButton") :: TextButton)
			assertions.equal(fixture.actions[#fixture.actions].kind, "SkipTutorial")

			local content = child(root, "Content", "Frame")
			local queue = child(child(content, "QueueScreen", "Frame"), "QueueContent", "ScrollingFrame")
			local configuration = (child(queue, "Configuration", "TextLabel") :: TextLabel).Text
			local status = (child(queue, "Status", "TextLabel") :: TextLabel).Text
			assertions.contains(configuration, "Backyard Garden")
			assertions.contains(configuration, "Easy")
			assertions.contains(configuration, "Party Only")
			assertions.isNil(string.find(configuration, "PartyOnly", 1, true))
			assertions.isNil(string.find(configuration, "map:", 1, true))
			assertions.isNil(string.find(configuration, "difficulty:", 1, true))
			assertions.isNil(string.find(status, "queue:", 1, true))
		end)
	end),

	TestHarness.case("cleans GUI focus and every stale callback across respawn style recreation", function(assertions)
		local fixture = makeFixture()
		local view = construct(fixture)
		assertions.isTrue(view:render(readyState("Inventory", "Gamepad")).ok)
		local _, root = guiTree(fixture)
		local content = child(root, "Content", "Frame") :: Frame
		local inventory = child(content, "InventoryScreen", "Frame") :: Frame
		local grid = child(inventory, "OwnedTowerGrid", "ScrollingFrame") :: ScrollingFrame
		local staleCard = child(grid, "TowerCard1", "TextButton") :: TextButton
		local staleActivation = fixture.activations[staleCard]
		local staleInput = fixture.inputListeners[1]
		local staleFamily = fixture.familyListeners[1]
		local party = child(child(content, "PartyScreen", "Frame"), "PartyContent", "ScrollingFrame")
		local inviteInput = child(party, "InviteUserId", "TextBox") :: TextBox
		local staleInviteCommit = fixture.searchListeners[inviteInput] :: (string) -> ()
		local staleInviteActivation = fixture.activations[child(party, "InviteMember", "TextButton")] :: () -> ()
		fixture.selected = staleCard
		local firstCleanup = view:cleanup()
		assertions.isTrue(firstCleanup.ok)
		assertions.isTrue(view:getMetrics().cleaned)
		assertions.equal(view:getMetrics().staticConnectionCount, 0)
		assertions.equal(view:getMetrics().dynamicConnectionCount, 0)
		assertions.isNil(fixture.selected)
		assertions.isNil(fixture.guiParent:FindFirstChild(LobbyView.GUI_NAME))
		local beforeStale = #fixture.actions
		local activateStale = staleActivation :: () -> ()
		local inputStale = staleInput :: (string, boolean) -> ()
		local familyStale = staleFamily :: (any) -> ()
		activateStale()
		inputStale("Escape", false)
		familyStale("Touch")
		staleInviteCommit("11604687814")
		staleInviteActivation()
		assertions.equal(#fixture.actions, beforeStale)
		assertions.isFalse(view:render(readyState()).ok)
		local repeatedCleanup = view:cleanup()
		assertions.isTrue(repeatedCleanup.ok)

		local replacement = construct(fixture)
		assertions.equal(#fixture.guiParent:GetChildren(), 1)
		local replacementRender = replacement:render(loadingState())
		assertions.isTrue(replacementRender.ok)
		local replacementCleanup = replacement:cleanup()
		assertions.isTrue(replacementCleanup.ok)
		assertions.isNil(fixture.guiParent:FindFirstChild(LobbyView.GUI_NAME))
		fixture.guiParent:Destroy()
	end),
})
