--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)

local PlayableMatchView = require(script.Parent.Parent.ProductionClientPlayable.PlayableMatchView)

local newForTests = PlayableMatchView.newForTests
local newTemplateBackedForTests = PlayableMatchView.newTemplateBackedForTests
local resolveResponsiveLayoutForTests = PlayableMatchView.resolveResponsiveLayoutForTests
if newForTests == nil or newTemplateBackedForTests == nil or resolveResponsiveLayoutForTests == nil then
	error("[ATD_TEST_FIXTURE][code=PLAYABLE_VIEW_CONSTRUCTOR_MISSING]", 0)
end

local function hotbar(available: boolean?): { any }
	local enabled = available ~= false
	return {
		{ slot = 1, displayName = "Scout", cost = 100, available = enabled, selected = false },
		{ slot = 2, displayName = "Ranger", cost = 175, available = enabled, selected = true },
		{ slot = 3, displayName = "Cannon", cost = 300, available = false, selected = false, reason = "NEED CASH" },
	}
end

local function snapshot(): any
	return {
		matchId = "match:playable-view",
		revision = 7,
		state = "WaveActive",
		inputFamily = "Desktop",
		wave = { current = 2, total = 5, enemiesRemaining = 7, status = "Active" },
		base = { health = 80, maxHealth = 100 },
		battleCash = 425,
		hotbar = hotbar(),
		viewport = Vector2.new(1280, 720),
	}
end

local function selection(isOwner: boolean): any
	return {
		towerId = "tower:owned-7",
		revision = 11,
		displayName = "Ranger",
		isOwner = isOwner,
		level = 1,
		maxLevel = 3,
		targetMode = "First",
		damage = 12,
		range = 24,
		cooldownSeconds = 0.8,
		upgradeCost = 225,
		sellValue = 122,
		canUpgrade = isOwner,
		canRetarget = isOwner,
		canSell = isOwner,
	}
end

local function child(parent: Instance, name: string, className: string): Instance
	local value = parent:FindFirstChild(name)
	if value == nil or value.ClassName ~= className then
		error("[ATD_TEST_FIXTURE][code=PLAYABLE_VIEW_CHILD_MISSING]", 0)
	end
	return value
end

local function withView(callback: (any, any) -> (), templateRoot: Instance?)
	local guiParent = Instance.new("Folder")
	guiParent.Name = "PlayableGuiParent"
	local worldParent = Instance.new("Folder")
	worldParent.Name = "PlayableWorldParent"
	local fixture = {
		actions = {} :: { any },
		activations = {} :: { () -> () },
		stepListeners = {} :: { (number) -> () },
		disconnectCount = 0,
		clock = 10,
		selected = nil :: GuiObject?,
		guiParent = guiParent,
		worldParent = worldParent,
	}
	local actionCallback = function(action: any)
		table.insert(fixture.actions, action)
	end
	local dependencies = {
		connectActivated = function(_button, listener)
			table.insert(fixture.activations, listener)
			return RobloxAdapter.createConnection(function()
				fixture.disconnectCount += 1
			end) :: RBXScriptConnection
		end,
		connectStepped = function(listener)
			table.insert(fixture.stepListeners, listener)
			return RobloxAdapter.createConnection(function()
				fixture.disconnectCount += 1
			end) :: RBXScriptConnection
		end,
		now = function()
			return fixture.clock
		end,
		selectObject = function(value)
			fixture.selected = value
		end,
	}
	local result = if templateRoot == nil
		then (newForTests :: any)(guiParent, worldParent, actionCallback, dependencies)
		else (newTemplateBackedForTests :: any)(guiParent, worldParent, templateRoot, actionCallback, dependencies)
	if not result.ok then
		guiParent:Destroy()
		worldParent:Destroy()
		error("playable view fixture failed", 0)
	end
	fixture.view = result.value
	local succeeded, problem = pcall(callback, result.value, fixture)
	pcall(function()
		result.value:cleanup()
	end)
	guiParent:Destroy()
	worldParent:Destroy()
	if not succeeded then
		error(problem, 0)
	end
end

local function addTemplate(folder: Folder, assetKey: string, contentKind: string, definitionId: string): Model
	local model = Instance.new("Model")
	model.Name = assetKey
	model:SetAttribute("ATDContentContract", "playable-local-match-v1")
	model:SetAttribute("AssetKey", assetKey)
	model:SetAttribute("ContentKind", contentKind)
	model:SetAttribute("DefinitionId", definitionId)
	local root = Instance.new("Part")
	root.Name = "AuthenticatedRoot"
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root
	model.Parent = folder
	return model
end

local function templateRoot(): (Folder, Model, Model)
	local root = Instance.new("Folder")
	local folder = Instance.new("Folder")
	folder.Name = "ATDPlayableTemplates"
	folder:SetAttribute("ATDContentContract", "playable-local-match-v1")
	folder:SetAttribute("ContentVersion", 1)
	folder.Parent = root
	local tower = addTemplate(folder, "tower.dart-ant-model", "TowerModel", "tower:dart-ant")
	local enemy = addTemplate(folder, "enemy.scout-ant-model", "EnemyModel", "enemy:scout-ant")
	return root, tower, enemy
end

local function guiTree(fixture: any): (ScreenGui, Frame)
	local gui = child(fixture.guiParent, PlayableMatchView.GUI_NAME, "ScreenGui") :: ScreenGui
	local root = child(gui, "Root", "Frame") :: Frame
	return gui, root
end

return TestHarness.suite("playable local Match presentation", {
	TestHarness.case("owns one bounded safe-area GUI world root and callback surface", function(assertions)
		withView(function(view, fixture)
			assertions.isTrue(table.isfrozen(PlayableMatchView))
			assertions.isTrue(table.isfrozen(view))
			local gui, root = guiTree(fixture)
			assertions.isFalse(gui.ResetOnSpawn)
			assertions.isFalse(gui.IgnoreGuiInset)
			assertions.isNotNil(root:FindFirstChild("TopHUD"))
			assertions.isNotNil(root:FindFirstChild("TowerHotbar"))
			assertions.isNotNil(root:FindFirstChild("ReadyOverlay"))
			assertions.isNotNil(root:FindFirstChild("TowerPanel"))
			assertions.isNotNil(root:FindFirstChild("ResultsOverlay"))
			assertions.equal(#fixture.activations, PlayableMatchView.BUTTON_CONNECTION_COUNT)
			assertions.equal(#fixture.stepListeners, 1)
			assertions.equal(view:getMetrics().connectionCount, PlayableMatchView.BUTTON_CONNECTION_COUNT + 1)
			local world = fixture.worldParent:FindFirstChild(PlayableMatchView.WORLD_FOLDER_NAME) :: Folder
			assertions.isNotNil(world)
			assertions.equal(#world:GetChildren(), 3)
		end)
	end),

	TestHarness.case(
		"renders wave enemies numeric base health cash and three actionable tower cards",
		function(assertions)
			withView(function(view, fixture)
				local scaled = snapshot()
				scaled.uiScale = 1.25
				assertions.isTrue(view:render(scaled).ok)
				local metrics = view:getMetrics()
				assertions.contains(metrics.waveText, "2 / 5")
				assertions.contains(metrics.enemyText, "7")
				assertions.contains(metrics.baseText, "80 / 100")
				assertions.contains(metrics.baseText, "♥")
				assertions.contains(metrics.cashText, "425")
				assertions.contains(metrics.cashText, "BATTLE CASH")

				local _, root = guiTree(fixture)
				assertions.isTrue(math.abs(root.Size.X.Scale - 0.8) < 1e-5)
				assertions.isTrue(math.abs(root.Size.Y.Scale - 0.8) < 1e-5)
				local hotbarPanel = child(root, "TowerHotbar", "Frame") :: Frame
				assertions.contains((child(hotbarPanel, "TowerSlot1", "TextButton") :: TextButton).Text, "Scout")
				assertions.contains((child(hotbarPanel, "TowerSlot2", "TextButton") :: TextButton).Text, "$175")
				assertions.contains((child(hotbarPanel, "TowerSlot3", "TextButton") :: TextButton).Text, "NEED CASH")

				fixture.activations[1]()
				fixture.activations[6]()
				assertions.equal(#fixture.actions, 2)
				assertions.equal(fixture.actions[1].kind, "SelectHotbar")
				assertions.equal(fixture.actions[1].slot, 1)
				assertions.equal(fixture.actions[1].matchId, "match:playable-view")
				assertions.equal(fixture.actions[1].matchRevision, 7)
				assertions.equal(fixture.actions[2].kind, "FocusBase")
			end)
		end
	),

	TestHarness.case("hides absent slots for one-slot desktop and shrinking touch loadouts", function(assertions)
		withView(function(view, fixture)
			local oneSlot = snapshot()
			oneSlot.hotbar = {
				{ slot = 1, displayName = "Scout", cost = 100, available = true, selected = false },
			}
			assertions.isTrue(view:render(oneSlot).ok)

			local _, root = guiTree(fixture)
			local hotbarPanel = child(root, "TowerHotbar", "Frame") :: Frame
			assertions.isTrue((child(hotbarPanel, "TowerSlot1", "TextButton") :: TextButton).Visible)
			for slot = 2, PlayableMatchView.HOTBAR_SLOTS do
				local button = child(hotbarPanel, `TowerSlot{slot}`, "TextButton") :: TextButton
				assertions.isFalse(button.Visible)
				assertions.isFalse(button.Active)
			end

			local fiveSlots = snapshot()
			fiveSlots.hotbar = {
				{ slot = 1, displayName = "Scout", cost = 100, available = true, selected = false },
				{ slot = 2, displayName = "Ranger", cost = 175, available = true, selected = false },
				{ slot = 3, displayName = "Cannon", cost = 300, available = true, selected = false },
				{ slot = 4, displayName = "Guard", cost = 400, available = true, selected = false },
				{ slot = 5, displayName = "Rapid", cost = 500, available = true, selected = false },
			}
			assertions.isTrue(view:render(fiveSlots).ok)
			for slot = 1, PlayableMatchView.HOTBAR_SLOTS do
				assertions.isTrue((child(hotbarPanel, `TowerSlot{slot}`, "TextButton") :: TextButton).Visible)
			end

			local twoSlotTouch = snapshot()
			twoSlotTouch.inputFamily = "Touch"
			twoSlotTouch.hotbar = {
				{ slot = 1, displayName = "Scout", cost = 100, available = true, selected = false },
				{ slot = 2, displayName = "Ranger", cost = 175, available = true, selected = false },
			}
			assertions.isTrue(view:render(twoSlotTouch).ok)
			for slot = 1, 2 do
				assertions.isTrue((child(hotbarPanel, `TowerSlot{slot}`, "TextButton") :: TextButton).Visible)
			end
			for slot = 3, PlayableMatchView.HOTBAR_SLOTS do
				local button = child(hotbarPanel, `TowerSlot{slot}`, "TextButton") :: TextButton
				assertions.isFalse(button.Visible)
				assertions.isFalse(button.Active)
			end
		end)
	end),

	TestHarness.case("shows a Ready overlay and gives gamepad focus to its enabled action", function(assertions)
		withView(function(view, fixture)
			local ready = snapshot()
			ready.state = "ReadyCheck"
			ready.inputFamily = "Gamepad"
			ready.hotbar = hotbar(false)
			ready.ready = { enabled = true, countdownSeconds = 18, status = "Waiting for you" }
			assertions.isTrue(view:render(ready).ok)
			assertions.isTrue(view:getMetrics().readyVisible)
			local _, root = guiTree(fixture)
			local overlay = child(root, "ReadyOverlay", "Frame") :: Frame
			assertions.contains((child(overlay, "Countdown", "TextLabel") :: TextLabel).Text, "18s")
			assertions.contains((child(overlay, "Status", "TextLabel") :: TextLabel).Text, "Waiting")
			assertions.equal(fixture.selected, child(overlay, "Ready", "TextButton"))

			fixture.activations[7]()
			assertions.equal(#fixture.actions, 1)
			assertions.equal(fixture.actions[1].kind, "Ready")
			assertions.equal(fixture.actions[1].source, "Gamepad")
		end)
	end),

	TestHarness.case(
		"routes owner upgrade retarget sell and close intents with stale-race identity",
		function(assertions)
			withView(function(view, fixture)
				local active = snapshot()
				active.selection = selection(true)
				assertions.isTrue(view:render(active).ok)
				assertions.isTrue(view:getMetrics().towerPanelVisible)
				assertions.isFalse(view:getMetrics().inspectionOnly)
				local _, root = guiTree(fixture)
				local panel = child(root, "TowerPanel", "Frame") :: Frame
				assertions.contains((child(panel, "OwnerState", "TextLabel") :: TextLabel).Text, "YOUR TOWER")
				assertions.contains((child(panel, "Stats", "TextLabel") :: TextLabel).Text, "Cooldown 0.80s")
				assertions.contains((child(panel, "TargetMode", "TextLabel") :: TextLabel).Text, "FIRST")

				for index = 8, 11 do
					fixture.activations[index]()
				end
				assertions.equal(#fixture.actions, 4)
				assertions.equal(fixture.actions[1].kind, "Upgrade")
				assertions.equal(fixture.actions[2].kind, "Retarget")
				assertions.equal(fixture.actions[2].targetMode, "Last")
				assertions.equal(fixture.actions[3].kind, "Sell")
				assertions.equal(fixture.actions[4].kind, "Cancel")
				for _, action in fixture.actions do
					assertions.equal(action.towerId, "tower:owned-7")
					assertions.equal(action.towerRevision, 11)
				end
			end)
		end
	),

	TestHarness.case(
		"keeps non-owner tower inspection readable while owner mutations stay disabled",
		function(assertions)
			withView(function(view, fixture)
				local active = snapshot()
				active.selection = selection(false)
				assertions.isTrue(view:render(active).ok)
				assertions.isTrue(view:getMetrics().inspectionOnly)
				local _, root = guiTree(fixture)
				local panel = child(root, "TowerPanel", "Frame") :: Frame
				assertions.contains((child(panel, "OwnerState", "TextLabel") :: TextLabel).Text, "INSPECTION ONLY")
				for _, name in { "Upgrade", "Target", "Sell" } do
					local button = child(panel, name, "TextButton") :: TextButton
					assertions.isFalse(button.Active)
					assertions.isFalse(button.Selectable)
				end
				fixture.activations[8]()
				fixture.activations[9]()
				fixture.activations[10]()
				fixture.activations[11]()
				assertions.equal(#fixture.actions, 1)
				assertions.equal(fixture.actions[1].kind, "Cancel")
			end)
		end
	),

	TestHarness.case("presents actionable non-color feedback and Victory or Defeat replay", function(assertions)
		withView(function(view, fixture)
			local victory = snapshot()
			victory.state = "Results"
			victory.feedback = { code = "INSUFFICIENT_CASH" }
			victory.result = {
				kind = "Victory",
				summary = "All 5 waves cleared • Base 42 HP • Cash 310",
				canReplay = true,
			}
			assertions.isTrue(view:render(victory).ok)
			assertions.isTrue(view:getMetrics().resultsVisible)
			assertions.equal(view:getMetrics().resultKind, "Victory")
			assertions.contains(view:getMetrics().feedbackText, "defeat enemies")
			local _, root = guiTree(fixture)
			local results = child(root, "ResultsOverlay", "Frame") :: Frame
			assertions.contains((child(results, "ResultTitle", "TextLabel") :: TextLabel).Text, "✓")
			assertions.contains((child(results, "ResultTitle", "TextLabel") :: TextLabel).Text, "VICTORY")
			fixture.activations[12]()
			assertions.equal(fixture.actions[1].kind, "Replay")

			local defeat = snapshot()
			defeat.revision = 8
			defeat.state = "Results"
			defeat.result = { kind = "Defeat", summary = "The base was overrun.", canReplay = false }
			assertions.isTrue(view:render(defeat).ok)
			assertions.equal(view:getMetrics().resultKind, "Defeat")
			assertions.contains((child(results, "ResultTitle", "TextLabel") :: TextLabel).Text, "✕")
			fixture.activations[12]()
			assertions.equal(#fixture.actions, 1)

			local replayReady = snapshot()
			replayReady.matchId = "match:playable-view-replay"
			replayReady.revision = 1
			replayReady.state = "ReadyCheck"
			replayReady.ready = { enabled = true, status = "0/1 players ready" }
			assertions.isTrue(view:render(replayReady).ok)
			assertions.isFalse(view:getMetrics().resultsVisible)
			assertions.isNil(view:getMetrics().resultKind)
			assertions.equal((child(results, "ResultTitle", "TextLabel") :: TextLabel).Text, "")
			assertions.equal((child(results, "Summary", "TextLabel") :: TextLabel).Text, "")
			assertions.isFalse((child(results, "Replay", "TextButton") :: TextButton).Active)
		end)
	end),

	TestHarness.case("resolves compact phone standard and ten-foot layouts with touch targets", function(assertions)
		withView(function(_view)
			local phone = (resolveResponsiveLayoutForTests :: any)(375, 667)
			local desktop = (resolveResponsiveLayoutForTests :: any)(1280, 720)
			local tenFoot = (resolveResponsiveLayoutForTests :: any)(1920, 1080)
			assertions.equal(phone.mode, "Compact")
			assertions.isTrue(phone.hudWidth < 375)
			assertions.isTrue(phone.touchTarget >= 48)
			assertions.equal(desktop.mode, "Standard")
			assertions.equal(tenFoot.mode, "TenFoot")
			assertions.isTrue(tenFoot.touchTarget >= 64)
			assertions.isTrue(tenFoot.textSize > desktop.textSize)
			assertions.isNil((resolveResponsiveLayoutForTests :: any)(120, 200))
		end)
	end),

	TestHarness.case(
		"renders bounded loading feedback and explicit two-step touch placement controls",
		function(assertions)
			withView(function(view, fixture)
				local loading = snapshot()
				loading.state = "Loading"
				loading.feedback = { code = "SERVER_UNAVAILABLE" }
				loading.hotbar = hotbar(false)
				loading.hotbar[2].selected = false
				assertions.isTrue(view:render(loading).ok)
				assertions.contains(view:getMetrics().waveText, "MATCH LOADING")
				assertions.contains(view:getMetrics().baseText, "BASE —")
				assertions.contains(view:getMetrics().feedbackText, "Server unavailable")
				assertions.isFalse(view:getMetrics().touchPlacementVisible)

				local touch = snapshot()
				touch.inputFamily = "Touch"
				touch.placement = { positionSelected = false, rotationDegrees = 0, controlsEnabled = true }
				assertions.isTrue(view:render(touch).ok)
				assertions.isTrue(view:getMetrics().touchPlacementVisible)
				assertions.contains(view:getMetrics().touchPlacementText, "TAP THE MAP")
				local _, root = guiTree(fixture)
				local panel = child(root, "TouchPlacementPanel", "Frame") :: Frame
				local confirm = child(panel, "Confirm", "TextButton") :: TextButton
				local rotate = child(panel, "Rotate", "TextButton") :: TextButton
				local cancel = child(panel, "Cancel", "TextButton") :: TextButton
				assertions.isFalse(confirm.Active)
				assertions.isTrue(rotate.Active)
				assertions.isTrue(cancel.Active)
				fixture.activations[13]()
				fixture.activations[14]()
				fixture.activations[15]()
				assertions.equal(#fixture.actions, 2)
				assertions.equal(fixture.actions[1].kind, "Rotate")
				assertions.equal(fixture.actions[2].kind, "Cancel")

				touch.placement.positionSelected = true
				touch.placement.rotationDegrees = 15
				assertions.isTrue(view:render(touch).ok)
				assertions.isTrue(confirm.Active)
				assertions.contains(view:getMetrics().touchPlacementText, "POSITION SELECTED")
				assertions.contains(view:getMetrics().touchPlacementText, "15")
				fixture.activations[13]()
				assertions.equal(fixture.actions[3].kind, "Confirm")

				local invalidDesktop = snapshot()
				invalidDesktop.placement = { positionSelected = true, rotationDegrees = 0, controlsEnabled = true }
				assertions.isFalse(view:render(invalidDesktop).ok)
			end)
		end
	),

	TestHarness.case("rejects malformed snapshots atomically without displaying hostile values", function(assertions)
		withView(function(view)
			assertions.isTrue(view:render(snapshot()).ok)
			local before = view:getMetrics()
			local invalid = snapshot()
			invalid.battleCash = -1
			invalid.feedback = { code = "PRIVATE\nVALUE" }
			assertions.isFalse(view:render(invalid).ok)
			local after = view:getMetrics()
			assertions.equal(after.renderCount, before.renderCount)
			assertions.equal(after.cashText, before.cashText)
			assertions.equal(after.feedbackText, before.feedbackText)
			local twoSelected = snapshot()
			twoSelected.hotbar[1].selected = true
			assertions.isFalse(view:render(twoSelected).ok)
		end)
	end),

	TestHarness.case("syncs bounded client visuals and expires compact attack effects", function(assertions)
		withView(function(view, fixture)
			assertions.isTrue(view:render(snapshot()).ok)
			assertions.isTrue(view:syncWorld({
				towers = {
					{
						id = "tower:one",
						definitionId = "tower:dart-ant",
						position = Vector3.new(0, 0, 0),
						selected = true,
						range = 24,
					},
				},
				enemies = {
					{
						id = "enemy:one",
						definitionId = "enemy:scout-ant",
						position = Vector3.new(0, 2, 12),
						health = 6,
						maxHealth = 10,
						archetype = "Fast",
					},
					{
						id = "enemy:two",
						definitionId = "enemy:soldier-ant",
						position = Vector3.new(2, 2, 14),
						health = 20,
						maxHealth = 20,
						archetype = "Tank",
					},
				},
			}).ok)
			assertions.equal(view:getMetrics().worldTowerCount, 1)
			assertions.equal(view:getMetrics().worldEnemyCount, 2)
			local world = fixture.worldParent:FindFirstChild(PlayableMatchView.WORLD_FOLDER_NAME) :: Folder
			local towerModel = (world:FindFirstChild("Towers") :: Folder):FindFirstChild("tower:one") :: Model
			assertions.isTrue(
				math.abs((towerModel:FindFirstChild("RangeIndicator") :: Part).Transparency - 0.82) < 1e-5
			)
			local enemyModel = (world:FindFirstChild("Enemies") :: Folder):FindFirstChild("enemy:one") :: Model
			assertions.isTrue((enemyModel:FindFirstChild("HealthDisplay") :: BillboardGui).Enabled)

			local attack = {
				matchId = "match:playable-view",
				sequence = 1,
				towerId = "tower:one",
				targetId = "enemy:one",
				damage = 12,
			}
			assertions.isTrue(view:playAttackEffect(attack).ok)
			assertions.equal(view:getMetrics().attackEffectCount, 1)
			local effects = world:FindFirstChild("AttackEffects") :: Folder
			assertions.isNotNil((effects:GetChildren()[1] :: Part):FindFirstChild("DamageNumber"))
			assertions.isFalse(view:playAttackEffect(attack).ok)
			fixture.clock = 11
			assertions.equal(view:stepEffects(11).value, 0)

			local preferences = snapshot()
			preferences.enemyHealthBars = false
			preferences.towerRange = false
			assertions.isTrue(view:render(preferences).ok)
			assertions.isTrue(view:syncWorld({
				towers = {
					{
						id = "tower:one",
						definitionId = "tower:dart-ant",
						position = Vector3.new(0, 0, 0),
						selected = true,
						range = 24,
					},
				},
				enemies = {
					{
						id = "enemy:one",
						definitionId = "enemy:scout-ant",
						position = Vector3.new(0, 2, 12),
						health = 6,
						maxHealth = 10,
					},
				},
			}).ok)
			assertions.equal((towerModel:FindFirstChild("RangeIndicator") :: Part).Transparency, 1)
			assertions.isFalse((enemyModel:FindFirstChild("HealthDisplay") :: BillboardGui).Enabled)

			local replay = snapshot()
			replay.matchId = "match:playable-replay"
			replay.revision = 0
			assertions.isTrue(view:render(replay).ok)
			assertions.equal(view:getMetrics().worldTowerCount, 0)
			assertions.equal(view:getMetrics().worldEnemyCount, 0)
			assertions.isFalse(view:playAttackEffect(attack).ok)

			assertions.isTrue(view:syncWorld({ towers = {}, enemies = {} }).ok)
			assertions.equal(view:getMetrics().worldTowerCount, 0)
			assertions.equal(view:getMetrics().worldEnemyCount, 0)
			assertions.isFalse(view:syncWorld({ towers = { [2] = {} }, enemies = {} }).ok)
		end)
	end),

	TestHarness.case(
		"clones authenticated content models with selection and numeric enemy health",
		function(assertions)
			local templates, towerTemplate, enemyTemplate = templateRoot()
			withView(function(view, fixture)
				assertions.isTrue(view:render(snapshot()).ok)
				assertions.isTrue(view:syncWorld({
					towers = {
						{
							id = "tower:one",
							definitionId = "tower:dart-ant",
							position = Vector3.new(2, 0, 3),
							rotationDegrees = 45,
							selected = true,
						},
					},
					enemies = {
						{
							id = "enemy:one",
							definitionId = "enemy:scout-ant",
							position = Vector3.new(4, 0, 8),
							health = 6,
							maxHealth = 10,
						},
					},
				}).ok)
				local world = fixture.worldParent:FindFirstChild(PlayableMatchView.WORLD_FOLDER_NAME) :: Folder
				local towerClone = (world:FindFirstChild("Towers") :: Folder):FindFirstChild("tower:one") :: Model
				local enemyClone = (world:FindFirstChild("Enemies") :: Folder):FindFirstChild("enemy:one") :: Model
				assertions.isNotNil(towerClone)
				assertions.isNotNil(enemyClone)
				assertions.isFalse(towerClone == towerTemplate)
				assertions.isFalse(enemyClone == enemyTemplate)
				assertions.isTrue((towerClone:FindFirstChild("SelectionHighlight") :: Highlight).Enabled)
				local health = enemyClone:FindFirstChild("HealthDisplay") :: BillboardGui
				assertions.equal((health:FindFirstChild("Value") :: TextLabel).Text, "6 / 10")
				assertions.equal(view:getMetrics().worldTowerCount, 1)
				assertions.equal(view:getMetrics().worldEnemyCount, 1)

				assertions.isFalse(view:syncWorld({
					towers = {
						{ id = "tower:missing", definitionId = "tower:unknown", position = Vector3.new() },
					},
					enemies = {},
				}).ok)
				assertions.equal(view:getMetrics().worldTowerCount, 1)
			end, templates)
			templates:Destroy()
		end
	),

	TestHarness.case("cleans all callbacks GUI visuals focus and effects exactly once", function(assertions)
		withView(function(view, fixture)
			view:render(snapshot())
			view:syncWorld({
				towers = {
					{ id = "tower:one", definitionId = "tower:dart-ant", position = Vector3.new() },
				},
				enemies = {
					{
						id = "enemy:one",
						definitionId = "enemy:worker-ant",
						position = Vector3.new(0, 0, 4),
						health = 1,
						maxHealth = 1,
					},
				},
			})
			view:playAttackEffect({
				matchId = "match:playable-view",
				sequence = 1,
				towerId = "tower:one",
				targetId = "enemy:one",
			})
			assertions.isTrue(view:cleanup().ok)
			assertions.isTrue(view:getMetrics().cleaned)
			assertions.equal(view:getMetrics().connectionCount, 0)
			assertions.equal(view:getMetrics().worldTowerCount, 0)
			assertions.equal(view:getMetrics().worldEnemyCount, 0)
			assertions.equal(view:getMetrics().attackEffectCount, 0)
			assertions.equal(fixture.disconnectCount, PlayableMatchView.BUTTON_CONNECTION_COUNT + 1)
			assertions.isNil(fixture.guiParent:FindFirstChild(PlayableMatchView.GUI_NAME))
			assertions.isNil(fixture.worldParent:FindFirstChild(PlayableMatchView.WORLD_FOLDER_NAME))
			fixture.activations[1]()
			assertions.equal(#fixture.actions, 0)
			assertions.isFalse(view:render(snapshot()).ok)
			assertions.isTrue(view:cleanup().ok)
		end)
	end),

	TestHarness.case("fails closed on ownership conflicts and partial connection setup", function(assertions)
		local guiParent = Instance.new("Folder")
		local worldParent = Instance.new("Folder")
		local blocker = Instance.new("Folder")
		blocker.Name = PlayableMatchView.GUI_NAME
		blocker.Parent = guiParent
		local dependencies = {
			connectActivated = function(_button, _listener)
				return RobloxAdapter.createConnection(function() end) :: RBXScriptConnection
			end,
			connectStepped = function(_listener)
				return RobloxAdapter.createConnection(function() end) :: RBXScriptConnection
			end,
			now = function()
				return 0
			end,
			selectObject = function(_value) end,
		}
		assertions.isFalse((newForTests :: any)(guiParent, worldParent, function() end, dependencies).ok)
		blocker:Destroy()

		local attempts = 0
		dependencies.connectActivated = function(_button, _listener): any
			attempts += 1
			return if attempts == 4 then {} else RobloxAdapter.createConnection(function() end)
		end
		assertions.isFalse((newForTests :: any)(guiParent, worldParent, function() end, dependencies).ok)
		assertions.isNil(guiParent:FindFirstChild(PlayableMatchView.GUI_NAME))
		assertions.isNil(worldParent:FindFirstChild(PlayableMatchView.WORLD_FOLDER_NAME))
		guiParent:Destroy()
		worldParent:Destroy()
	end),
})
