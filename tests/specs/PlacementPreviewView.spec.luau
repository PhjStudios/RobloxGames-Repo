--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)

local PlacementPreviewReducer = require(script.Parent.Parent.ProductionClientPlacement.PlacementPreviewReducer)
local PlacementPreviewView = require(script.Parent.Parent.ProductionClientPlacement.PlacementPreviewView)

local newForTests = PlacementPreviewView.newForTests
local resolveResponsiveLayoutForTests = PlacementPreviewView.resolveResponsiveLayoutForTests
if newForTests == nil or resolveResponsiveLayoutForTests == nil then
	error("[ATD_TEST_FIXTURE][code=PLACEMENT_VIEW_TEST_CONSTRUCTOR_MISSING]", 0)
end

local function occupied(slot: number): any
	return {
		kind = "Occupied",
		slot = slot,
		towerId = `tower:view-{slot}`,
		displayName = `Tower {slot}`,
		iconAssetKey = `test.view.{slot}`,
		rangeStuds = 12,
		footprintRadiusStuds = 2,
		placementCost = 100,
		placementCount = 0,
		placementCap = 4,
		totalCount = 0,
		totalCap = 32,
		globalCount = 0,
		globalCap = 128,
		affordability = "Affordable",
		capState = "Available",
	}
end

local function query(): any
	return {
		contractVersion = 1,
		matchId = "match:phase13-view",
		mapId = "map:phase07-graybox",
		queryRevision = 1,
		loadoutRevision = 1,
		bounds = { cframe = CFrame.new(), size = Vector3.new(120, 20, 120) },
		placementZones = {
			{ cframe = CFrame.new(0, -4, 0), size = Vector3.new(100, 2, 100), surfaceCategory = "Land" },
		},
		exclusions = {},
		footprints = {},
		slots = {
			occupied(1),
			occupied(2),
			{ kind = "Empty", slot = 3 },
			{ kind = "Empty", slot = 4 },
			{ kind = "Empty", slot = 5 },
		},
	}
end

local function renderState(position: Vector2?, inputFamily: string?): any
	local result = PlacementPreviewReducer.new()
	if not result.ok then
		error("view reducer fixture failed", 0)
	end
	local reducer = result.value
	reducer:observeQuery(query())
	reducer:selectSlot(1)
	if position ~= nil then
		reducer:setPosition(position)
	end
	if inputFamily ~= nil then
		reducer:setPreferredInput(inputFamily)
	end
	local state = reducer:getState()
	if not state.ok then
		error("view state fixture failed", 0)
	end
	return state.value
end

local function withView(callback: (any, Folder, Folder, { any }, { () -> () }) -> ())
	local guiParent = Instance.new("Folder")
	guiParent.Name = "GuiParent"
	local worldParent = Instance.new("Folder")
	worldParent.Name = "WorldParent"
	local actions = {}
	local activations: { () -> () } = {}
	local dependencies = {
		connectActivated = function(_button: GuiButton, listener: () -> ()): RBXScriptConnection
			table.insert(activations, listener)
			return RobloxAdapter.createConnection(function() end) :: any
		end,
	}
	local result = (newForTests :: any)(guiParent, worldParent, function(action: any)
		table.insert(actions, action)
	end, dependencies)
	if not result.ok then
		guiParent:Destroy()
		worldParent:Destroy()
		error("view construction fixture failed", 0)
	end
	local succeeded, failure = pcall(callback, result.value, guiParent, worldParent, actions, activations)
	pcall(function()
		result.value:cleanup()
	end)
	guiParent:Destroy()
	worldParent:Destroy()
	if not succeeded then
		error(failure, 0)
	end
end

return TestHarness.suite("Phase 13 bounded placement preview view", {
	TestHarness.case("creates one bounded UI and exactly two local non-authoritative world parts", function(assertions)
		withView(function(view, guiParent, worldParent)
			local metrics = view:getMetrics()
			assertions.equal(metrics.connectionCount, PlacementPreviewView.FIXED_CONNECTION_COUNT)
			assertions.equal(metrics.worldPartCount, 2)
			local gui = guiParent:FindFirstChild(PlacementPreviewView.GUI_NAME)
			local folder = worldParent:FindFirstChild(PlacementPreviewView.WORLD_FOLDER_NAME)
			assertions.isNotNil(gui)
			assertions.isNotNil(folder)
			assertions.equal(#(folder :: Folder):GetChildren(), 2)
			for _, child in (folder :: Folder):GetChildren() do
				assertions.isTrue(child:IsA("Part"))
				local part = child :: Part
				assertions.isTrue(part.Anchored)
				assertions.isFalse(part.CanCollide)
				assertions.isFalse(part.CanTouch)
				assertions.isFalse(part.CanQuery)
				assertions.equal(part.Transparency, 1)
			end
		end)
	end),

	TestHarness.case("renders five temporary slots and desktop input hints", function(assertions)
		withView(function(view, guiParent)
			local result = view:render(renderState(nil, "Desktop"))
			assertions.isTrue(result.ok)
			local gui = guiParent:FindFirstChild(PlacementPreviewView.GUI_NAME) :: ScreenGui
			local panel = gui:FindFirstChild("PlacementPanel") :: Frame
			local hotbar = panel:FindFirstChild("TemporaryLoadout") :: Frame
			assertions.equal(#hotbar:GetChildren(), 5)
			assertions.contains((hotbar:FindFirstChild("Slot1") :: TextButton).Text, "Tower 1")
			assertions.contains((hotbar:FindFirstChild("Slot3") :: TextButton).Text, "—")
			assertions.contains(view:getMetrics().hintText, "Click Place")
			assertions.equal(view:getMetrics().selectedSlot, 1)
		end)
	end),

	TestHarness.case("renders a translucent ghost and flat range indicator for a valid candidate", function(assertions)
		withView(function(view, _guiParent, worldParent)
			assertions.isTrue(view:render(renderState(Vector2.new(0, 0))).ok)
			local folder = worldParent:FindFirstChild(PlacementPreviewView.WORLD_FOLDER_NAME) :: Folder
			local ghost = folder:FindFirstChild("Ghost") :: Part
			local range = folder:FindFirstChild("RangeIndicator") :: Part
			assertions.isTrue(view:getMetrics().previewVisible)
			assertions.isTrue(view:getMetrics().rangeVisible)
			assertions.isTrue(math.abs(ghost.Transparency - 0.45) < 1e-5)
			assertions.equal(ghost.Size, Vector3.new(4, 4, 4))
			assertions.isTrue(math.abs(range.Size.X - 0.08) < 1e-5)
			assertions.equal(Vector2.new(range.Size.Y, range.Size.Z), Vector2.new(24, 24))
			assertions.contains(view:getMetrics().statusText, "VALID")
			assertions.contains(view:getMetrics().statusText, "✓")
		end)
	end),

	TestHarness.case("uses text and symbols as well as color for invalid feedback", function(assertions)
		withView(function(view)
			assertions.isTrue(view:render(renderState(Vector2.new(55, 0))).ok)
			assertions.contains(view:getMetrics().statusText, "OUTSIDE")
			assertions.contains(view:getMetrics().statusText, "▱")
			assertions.isFalse(view:getMetrics().previewVisible)
		end)
	end),

	TestHarness.case("shows separate touch confirm rotate and cancel controls", function(assertions)
		withView(function(view, guiParent)
			assertions.isTrue(view:render(renderState(Vector2.new(0, 0), "Touch")).ok)
			local gui = guiParent:FindFirstChild(PlacementPreviewView.GUI_NAME) :: ScreenGui
			local panel = gui:FindFirstChild("PlacementPanel") :: Frame
			assertions.isTrue((panel:FindFirstChild("TouchConfirm") :: TextButton).Visible)
			assertions.isTrue((panel:FindFirstChild("TouchRotate") :: TextButton).Visible)
			assertions.isTrue((panel:FindFirstChild("TouchCancel") :: TextButton).Visible)
			assertions.contains(view:getMetrics().hintText, "Then Confirm")
		end)
	end),

	TestHarness.case("keeps the production panel inside a safe-area phone viewport", function(assertions)
		withView(function(_view, guiParent)
			local gui = guiParent:FindFirstChild(PlacementPreviewView.GUI_NAME) :: ScreenGui
			assertions.isFalse(gui.IgnoreGuiInset)
			local phoneLayout = (resolveResponsiveLayoutForTests :: any)(375)
			local desktopLayout = (resolveResponsiveLayoutForTests :: any)(1_920)
			assertions.isNotNil(phoneLayout)
			assertions.isNotNil(desktopLayout)
			assertions.equal(phoneLayout.horizontalMargin, 12)
			assertions.equal(phoneLayout.panelWidth, 351)
			assertions.isTrue(phoneLayout.panelWidth < 375)
			assertions.isTrue(phoneLayout.slotWidth >= 44)
			assertions.equal(desktopLayout.panelWidth, 700)
			assertions.isTrue(math.abs(desktopLayout.slotWidth - 90) < 1e-6)
			assertions.isNil((resolveResponsiveLayoutForTests :: any)(24))
		end)
	end),

	TestHarness.case("routes all eight UI controls through one bounded callback surface", function(assertions)
		withView(function(_view, _guiParent, _worldParent, actions, activations)
			assertions.equal(#activations, 8)
			for _, activate in activations do
				activate()
			end
			assertions.equal(#actions, 8)
			assertions.equal(actions[1].kind, "SelectSlot")
			assertions.equal(actions[1].slot, 1)
			assertions.equal(actions[5].slot, 5)
			assertions.equal(actions[6].kind, "Confirm")
			assertions.equal(actions[7].kind, "Cancel")
			assertions.equal(actions[8].kind, "Rotate")
		end)
	end),

	TestHarness.case("shows and moves the deterministic gamepad reticle", function(assertions)
		withView(function(view, guiParent)
			assertions.isTrue(view:render(renderState(nil, "Gamepad")).ok)
			assertions.isTrue(view:setReticle(Vector2.new(250, 300), true).ok)
			local gui = guiParent:FindFirstChild(PlacementPreviewView.GUI_NAME) :: ScreenGui
			local reticle = gui:FindFirstChild("GamepadReticle") :: TextLabel
			assertions.isTrue(reticle.Visible)
			assertions.contains(view:getMetrics().hintText, "A Confirm")
			assertions.isTrue(view:getMetrics().reticleVisible)
		end)
	end),

	TestHarness.case("rejects malformed render state without mutating owned visuals", function(assertions)
		withView(function(view)
			assertions.isFalse(view:render({}).ok)
			assertions.isFalse(view:setReticle(Vector2.new(0 / 0, 0), true).ok)
			assertions.equal(view:getMetrics().renderCount, 0)
			assertions.isFalse(view:getMetrics().previewVisible)
		end)
	end),

	TestHarness.case("rejects duplicate ownership names and failed connections", function(assertions)
		local guiParent = Instance.new("Folder")
		local worldParent = Instance.new("Folder")
		local blocker = Instance.new("Folder")
		blocker.Name = PlacementPreviewView.GUI_NAME
		blocker.Parent = guiParent
		local dependencies = {
			connectActivated = function(_button: GuiButton, _listener: () -> ()): RBXScriptConnection
				return RobloxAdapter.createConnection(function() end) :: any
			end,
		}
		assertions.isFalse((newForTests :: any)(guiParent, worldParent, function() end, dependencies).ok)
		blocker:Destroy()

		local attempts = 0
		local failed = (newForTests :: any)(guiParent, worldParent, function() end, {
			connectActivated = function(_button: GuiButton, _listener: () -> ()): any
				attempts += 1
				return if attempts == 3 then {} else RobloxAdapter.createConnection(function() end)
			end,
		})
		assertions.isFalse(failed.ok)
		assertions.isNil(guiParent:FindFirstChild(PlacementPreviewView.GUI_NAME))
		assertions.isNil(worldParent:FindFirstChild(PlacementPreviewView.WORLD_FOLDER_NAME))
		guiParent:Destroy()
		worldParent:Destroy()
	end),

	TestHarness.case("disconnects callbacks and destroys all client preview instances on cleanup", function(assertions)
		withView(function(view, guiParent, worldParent, actions, activations)
			view:render(renderState(Vector2.new(0, 0), "Touch"))
			assertions.isTrue(view:cleanup().ok)
			assertions.isTrue(view:getMetrics().cleaned)
			assertions.equal(view:getMetrics().connectionCount, 0)
			assertions.equal(view:getMetrics().worldPartCount, 0)
			assertions.isNil(guiParent:FindFirstChild(PlacementPreviewView.GUI_NAME))
			assertions.isNil(worldParent:FindFirstChild(PlacementPreviewView.WORLD_FOLDER_NAME))
			activations[1]()
			assertions.equal(#actions, 0)
			assertions.isFalse(view:render(renderState(nil)).ok)
			assertions.isTrue(view:cleanup().ok)
		end)
	end),
})
