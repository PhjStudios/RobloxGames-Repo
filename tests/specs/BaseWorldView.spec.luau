--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local BaseViewModel = require(script.Parent.Parent.ProductionClientBase.BaseViewModel)
local BaseWorldView = require(script.Parent.Parent.ProductionClientBase.BaseWorldView)

local Shared = game:GetService("ReplicatedStorage").Shared
local BaseProtocol = require(Shared.match.BaseProtocol)

type Assertions = TestHarness.Assertions
type View = BaseWorldView.View
type RenderState = BaseViewModel.RenderState

type WatchKind =
	"WorkspaceAdded"
	| "WorkspaceRemoving"
	| "PlayerGuiAdded"
	| "PlayerGuiRemoved"
	| "Ancestry"
	| "Property"

type WatchRecord = {
	kind: WatchKind,
	target: Instance?,
	propertyName: string?,
	callback: () -> (),
	active: boolean,
}

type PulseRecord = {
	target: TextLabel,
	played: boolean,
	cancelled: boolean,
	destroyed: boolean,
}

type Hub = {
	watches: { WatchRecord },
	pulses: { PulseRecord },
	activePulseCount: number,
	maximumActivePulseCount: number,
	disconnectCount: number,
	boundGui: BillboardGui?,
	boundMarker: Part?,
	guiVisible: boolean,
	dependencies: BaseWorldView.TestDependencies,
}

type MarkerTree = {
	runtimeRoot: Model,
	markers: Folder,
	marker: Part,
}

type Rig = {
	playerGuiParent: Folder,
	workspaceRoot: Folder,
	hub: Hub,
	view: View,
	markerTree: MarkerTree?,
}

local newForTests = BaseWorldView.newForTests
if newForTests == nil then
	error("[ATD_TEST_FIXTURE][code=BASE_WORLD_VIEW_TEST_CONSTRUCTOR_MISSING]", 0)
end

local BASE_POSITION = Vector3.new(30, 5, -12)

local function activeWatchCount(hub: Hub): number
	local count = 0
	for _, watch in hub.watches do
		if watch.active then
			count += 1
		end
	end
	return count
end

local function makeHub(): Hub
	local hub = {
		watches = {},
		pulses = {},
		activePulseCount = 0,
		maximumActivePulseCount = 0,
		disconnectCount = 0,
		boundGui = nil,
		boundMarker = nil,
		guiVisible = false,
		dependencies = nil :: any,
	} :: Hub

	local function addWatch(
		kind: WatchKind,
		target: Instance?,
		propertyName: string?,
		callback: () -> ()
	): RBXScriptConnection
		local record: WatchRecord = {
			kind = kind,
			target = target,
			propertyName = propertyName,
			callback = callback,
			active = true,
		}
		table.insert(hub.watches, record)
		return RobloxAdapter.createConnection(function()
			if record.active then
				record.active = false
				hub.disconnectCount += 1
			end
		end) :: RBXScriptConnection
	end

	hub.dependencies = {
		connectWorkspaceDescendantAdded = function(callback)
			return addWatch("WorkspaceAdded", nil, nil, callback)
		end,
		connectWorkspaceDescendantRemoving = function(callback)
			return addWatch("WorkspaceRemoving", nil, nil, callback)
		end,
		connectPlayerGuiChildAdded = function(callback)
			return addWatch("PlayerGuiAdded", nil, nil, callback)
		end,
		connectPlayerGuiChildRemoved = function(callback)
			return addWatch("PlayerGuiRemoved", nil, nil, callback)
		end,
		connectAncestryChanged = function(target, callback)
			return addWatch("Ancestry", target, nil, callback)
		end,
		connectPropertyChanged = function(target, propertyName, callback)
			return addWatch("Property", target, propertyName, callback)
		end,
		createPulseTween = function(target)
			local record: PulseRecord = {
				target = target,
				played = false,
				cancelled = false,
				destroyed = false,
			}
			table.insert(hub.pulses, record)
			hub.activePulseCount += 1
			hub.maximumActivePulseCount = math.max(hub.maximumActivePulseCount, hub.activePulseCount)
			return {
				play = function()
					record.played = true
				end,
				cancel = function()
					record.cancelled = true
				end,
				destroy = function()
					if not record.destroyed then
						record.destroyed = true
						hub.activePulseCount -= 1
					end
				end,
			}
		end,
		setGuiBinding = function(gui, marker, enabled)
			hub.boundGui = gui
			hub.boundMarker = marker
			hub.guiVisible = enabled
		end,
	}
	return hub
end

local function fireWatch(hub: Hub, kind: WatchKind, target: Instance?, propertyName: string?)
	local selected = {} :: { WatchRecord }
	for _, watch in hub.watches do
		if
			watch.active
			and watch.kind == kind
			and (target == nil or watch.target == target)
			and (propertyName == nil or watch.propertyName == propertyName)
		then
			table.insert(selected, watch)
		end
	end
	for _, watch in selected do
		if watch.active then
			watch.callback()
		end
	end
end

local function createMarkerTree(workspaceRoot: Folder, position: Vector3?): MarkerTree
	local runtimeRoot = Instance.new("Model")
	runtimeRoot.Name = BaseWorldView.RUNTIME_ROOT_NAME
	runtimeRoot.Parent = workspaceRoot
	local markers = Instance.new("Folder")
	markers.Name = BaseWorldView.MARKERS_NAME
	markers.Parent = runtimeRoot
	local marker = Instance.new("Part")
	marker.Name = BaseWorldView.MARKER_NAME
	marker.Anchored = true
	marker.Position = position or BASE_POSITION
	marker.Parent = markers
	return {
		runtimeRoot = runtimeRoot,
		markers = markers,
		marker = marker,
	}
end

local function expectView(parent: Folder, workspaceRoot: Folder, hub: Hub): View
	local result = (newForTests :: BaseWorldView.TestConstructor)(parent, workspaceRoot, hub.dependencies)
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=BASE_WORLD_VIEW_CREATION_FAILED][detail={result.error.code}]`, 0)
	end
	return result.value
end

local function makeRig(withMarker: boolean?): Rig
	local playerGuiParent = Instance.new("Folder")
	playerGuiParent.Name = "BaseWorldViewPlayerGui"
	local workspaceRoot = Instance.new("Folder")
	workspaceRoot.Name = "BaseWorldViewWorkspace"
	local markerTree = if withMarker == false then nil else createMarkerTree(workspaceRoot, BASE_POSITION)
	local hub = makeHub()
	return {
		playerGuiParent = playerGuiParent,
		workspaceRoot = workspaceRoot,
		hub = hub,
		view = expectView(playerGuiParent, workspaceRoot, hub),
		markerTree = markerTree,
	}
end

local function canonicalSnapshot(
	revision: number,
	currentHealth: number,
	status: "Active" | "Defeated" | "Faulted"?,
	position: Vector3?
): BaseProtocol.BaseSnapshot
	local result = BaseProtocol.validateBaseSnapshot({
		matchId = "match:phase10-world-view",
		enemyEpoch = 1,
		mapId = "map:phase10-world-view",
		difficultyId = "difficulty:phase10-world-view",
		basePosition = position or BASE_POSITION,
		baseRevision = revision,
		status = status or "Active",
		currentHealth = currentHealth,
		maximumHealth = 100,
		lowHealth = currentHealth <= 25,
		initializedServerTime = 10,
		updatedServerTime = 10 + revision,
	})
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=BASE_WORLD_VIEW_SNAPSHOT_INVALID][path={result.error.path}]`, 0)
	end
	return result.value
end

local function renderState(
	revision: number,
	currentHealth: number,
	status: "Active" | "Defeated" | "Faulted"?,
	damage: number?,
	position: Vector3?
): RenderState
	local feedback = if damage == nil
		then nil
		else {
			baseRevision = revision,
			appliedDamage = damage,
			leakCount = 1,
			lowHealthCrossed = currentHealth <= 25,
		}
	local result = BaseViewModel.project(canonicalSnapshot(revision, currentHealth, status, position), feedback)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=BASE_WORLD_VIEW_MODEL_FAILED]", 0)
	end
	return result.value
end

local function render(view: View, state: RenderState): BaseWorldView.Metrics
	local result = view:render(state)
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=BASE_WORLD_VIEW_RENDER_FAILED][detail={result.error.code}]`, 0)
	end
	return result.value
end

local function gui(rig: Rig): BillboardGui
	local candidate = rig.playerGuiParent:FindFirstChild(BaseWorldView.GUI_NAME)
	if candidate == nil or not candidate:IsA("BillboardGui") then
		error("[ATD_TEST_FIXTURE][code=BASE_WORLD_VIEW_GUI_MISSING]", 0)
	end
	return candidate
end

local function child(parent: Instance, name: string, className: string): Instance
	local candidate = parent:FindFirstChild(name)
	if candidate == nil or candidate.ClassName ~= className then
		error(`[ATD_TEST_FIXTURE][code=BASE_WORLD_VIEW_CHILD_MISSING][name={name}]`, 0)
	end
	return candidate
end

local function panel(rig: Rig): Frame
	return child(gui(rig), BaseWorldView.PANEL_NAME, "Frame") :: Frame
end

local function healthLabel(rig: Rig): TextLabel
	return child(panel(rig), BaseWorldView.HEALTH_LABEL_NAME, "TextLabel") :: TextLabel
end

local function statusLabel(rig: Rig): TextLabel
	return child(panel(rig), BaseWorldView.STATUS_LABEL_NAME, "TextLabel") :: TextLabel
end

local function lowLabel(rig: Rig): TextLabel
	return child(panel(rig), BaseWorldView.LOW_LABEL_NAME, "TextLabel") :: TextLabel
end

local function damageLabel(rig: Rig): TextLabel
	return child(panel(rig), BaseWorldView.DAMAGE_LABEL_NAME, "TextLabel") :: TextLabel
end

local function destroyRig(rig: Rig)
	rig.view:cleanup()
	rig.playerGuiParent:Destroy()
	rig.workspaceRoot:Destroy()
end

local function expectFailure(assertions: Assertions, result: any, code: string)
	assertions.isFalse(result.ok)
	if not result.ok then
		assertions.equal(result.error.code, code)
	end
end

return TestHarness.suite("base world-space view", {
	TestHarness.case(
		"accepts the canonical hidden bootstrap state without authoritative identity",
		function(assertions)
			local rig = makeRig()
			local projected = BaseViewModel.project(nil, nil)
			assertions.isTrue(projected.ok)
			if not projected.ok then
				destroyRig(rig)
				return
			end

			local metrics = render(rig.view, projected.value)
			assertions.isFalse(metrics.bound)
			assertions.isFalse(metrics.visible)
			assertions.isFalse(rig.hub.guiVisible)
			assertions.equal(healthLabel(rig).Text, "")
			assertions.equal(statusLabel(rig).Text, "")
			assertions.isFalse(lowLabel(rig).Visible)
			assertions.isFalse(damageLabel(rig).Visible)
			assertions.equal(metrics.renderCount, 1)
			destroyRig(rig)
		end
	),

	TestHarness.case("owns one PlayerGui BillboardGui and binds only the exact authored marker", function(assertions)
		local rig = makeRig()
		local markerTree = rig.markerTree :: MarkerTree
		local metrics = render(rig.view, renderState(1, 75, "Active", nil, nil))

		assertions.isTrue(metrics.bound)
		assertions.isTrue(metrics.visible)
		assertions.equal(gui(rig).Parent, rig.playerGuiParent)
		assertions.equal(rig.hub.boundGui, gui(rig))
		assertions.equal(rig.hub.boundMarker, markerTree.marker)
		assertions.isTrue(rig.hub.guiVisible)
		assertions.equal(#markerTree.marker:GetChildren(), 0)
		assertions.equal(#markerTree.marker:GetAttributes(), 0)
		assertions.equal(healthLabel(rig).Text, "75 / 100")
		assertions.equal(statusLabel(rig).Text, "ACTIVE")
		assertions.equal(metrics.renderedFillScale, 0.75)
		assertions.isFalse(lowLabel(rig).Visible)
		assertions.isFalse(damageLabel(rig).Visible)
		assertions.equal(metrics.fixedConnectionCount, BaseWorldView.FIXED_CONNECTION_COUNT)
		assertions.equal(metrics.markerWatcherConnectionCount, BaseWorldView.MAX_MARKER_WATCHER_CONNECTIONS)
		assertions.equal(metrics.viewWatcherConnectionCount, BaseWorldView.MAX_VIEW_WATCHER_CONNECTIONS)
		assertions.equal(metrics.connectionCount, BaseWorldView.MAX_CONNECTION_COUNT)
		assertions.equal(activeWatchCount(rig.hub), BaseWorldView.MAX_CONNECTION_COUNT)
		destroyRig(rig)
	end),

	TestHarness.case("renders exact LOW and damage text with one cancellable bounded pulse", function(assertions)
		local rig = makeRig()
		local initialConnections = render(rig.view, renderState(1, 100, "Active", nil, nil)).connectionCount
		local low = render(rig.view, renderState(2, 25, "Active", 75, nil))
		assertions.equal(low.renderedFillScale, 0.25)
		assertions.isTrue(lowLabel(rig).Visible)
		assertions.equal(lowLabel(rig).Text, "LOW")
		assertions.isTrue(damageLabel(rig).Visible)
		assertions.equal(damageLabel(rig).Text, "-75")
		assertions.equal(low.activeTweenCount, 1)
		assertions.equal(low.tweenCreationCount, 1)
		assertions.isTrue(rig.hub.pulses[1].played)

		local duplicate = render(rig.view, renderState(2, 25, "Active", 75, nil))
		assertions.equal(duplicate.tweenCreationCount, 1)
		assertions.isFalse(rig.hub.pulses[1].cancelled)
		local nextDamage = render(rig.view, renderState(3, 15, "Active", 10, nil))
		assertions.equal(nextDamage.tweenCreationCount, 2)
		assertions.isTrue(rig.hub.pulses[1].cancelled)
		assertions.isTrue(rig.hub.pulses[1].destroyed)
		assertions.isTrue(rig.hub.pulses[2].played)
		assertions.equal(rig.hub.maximumActivePulseCount, 1)
		assertions.equal(nextDamage.connectionCount, initialConnections)

		local corrected = render(rig.view, renderState(3, 15, "Active", nil, nil))
		assertions.equal(corrected.activeTweenCount, 0)
		assertions.isTrue(rig.hub.pulses[2].cancelled)
		assertions.isTrue(rig.hub.pulses[2].destroyed)
		assertions.isFalse(damageLabel(rig).Visible)
		assertions.equal(rig.hub.activePulseCount, 0)
		destroyRig(rig)
	end),

	TestHarness.case(
		"hides on position mismatch and rebinds across move rename removal and replacement",
		function(assertions)
			local rig = makeRig()
			local markerTree = rig.markerTree :: MarkerTree
			local state = renderState(1, 80, "Active", nil, nil)
			render(rig.view, state)

			markerTree.marker.Position = BASE_POSITION + Vector3.new(BaseWorldView.POSITION_TOLERANCE * 2, 0, 0)
			fireWatch(rig.hub, "Property", markerTree.marker, "CFrame")
			assertions.isNil(rig.hub.boundMarker)
			assertions.isFalse(rig.hub.guiVisible)
			assertions.equal(
				(rig.view:getMetrics() :: any).value.markerWatcherConnectionCount,
				BaseWorldView.MAX_MARKER_WATCHER_CONNECTIONS
			)

			markerTree.marker.Position = BASE_POSITION + Vector3.new(BaseWorldView.POSITION_TOLERANCE / 2, 0, 0)
			fireWatch(rig.hub, "Property", markerTree.marker, "CFrame")
			assertions.equal(rig.hub.boundMarker, markerTree.marker)
			assertions.isTrue(rig.hub.guiVisible)

			markerTree.marker.Name = "RenamedBase"
			fireWatch(rig.hub, "Property", markerTree.marker, "Name")
			assertions.isNil(rig.hub.boundMarker)
			markerTree.marker.Name = BaseWorldView.MARKER_NAME
			fireWatch(rig.hub, "Property", markerTree.marker, "Name")
			assertions.equal(rig.hub.boundMarker, markerTree.marker)

			markerTree.marker.Parent = nil
			fireWatch(rig.hub, "Ancestry", markerTree.marker, nil)
			assertions.isNil(rig.hub.boundMarker)
			markerTree.marker.Parent = markerTree.markers
			fireWatch(rig.hub, "Ancestry", markerTree.marker, nil)
			assertions.equal(rig.hub.boundMarker, markerTree.marker)

			local oldMarker = markerTree.marker
			oldMarker:Destroy()
			fireWatch(rig.hub, "WorkspaceRemoving", nil, nil)
			assertions.isNil(rig.hub.boundMarker)
			local replacement = Instance.new("Part")
			replacement.Name = BaseWorldView.MARKER_NAME
			replacement.Position = BASE_POSITION
			replacement.Parent = markerTree.markers
			fireWatch(rig.hub, "WorkspaceAdded", nil, nil)
			assertions.equal(rig.hub.boundMarker, replacement)
			assertions.equal(activeWatchCount(rig.hub), BaseWorldView.MAX_CONNECTION_COUNT)
			destroyRig(rig)
		end
	),

	TestHarness.case("binds a late streamed marker without changing cached health", function(assertions)
		local rig = makeRig(false)
		local state = renderState(4, 60, "Active", nil, nil)
		local missing = render(rig.view, state)
		assertions.isFalse(missing.bound)
		assertions.isFalse(missing.visible)
		assertions.equal(healthLabel(rig).Text, "60 / 100")

		local markerTree = createMarkerTree(rig.workspaceRoot, BASE_POSITION)
		rig.markerTree = markerTree
		fireWatch(rig.hub, "WorkspaceAdded", nil, nil)
		assertions.equal(rig.hub.boundMarker, markerTree.marker)
		assertions.isTrue(rig.hub.guiVisible)
		assertions.equal(healthLabel(rig).Text, "60 / 100")
		assertions.equal((rig.view:getMetrics() :: any).value.renderCount, 1)
		destroyRig(rig)
	end),

	TestHarness.case("rebinds after the complete streamed runtime path is replaced", function(assertions)
		local rig = makeRig()
		local original = rig.markerTree :: MarkerTree
		render(rig.view, renderState(4, 60, "Active", nil, nil))
		local originalRebinds = (rig.view:getMetrics() :: any).value.markerRebindCount

		original.runtimeRoot.Parent = nil
		fireWatch(rig.hub, "WorkspaceRemoving", nil, nil)
		assertions.isNil(rig.hub.boundMarker)
		assertions.isFalse(rig.hub.guiVisible)
		assertions.equal(healthLabel(rig).Text, "60 / 100")

		original.runtimeRoot:Destroy()
		local replacement = createMarkerTree(rig.workspaceRoot, BASE_POSITION)
		rig.markerTree = replacement
		fireWatch(rig.hub, "WorkspaceAdded", nil, nil)
		local recovered = (rig.view:getMetrics() :: any).value :: BaseWorldView.Metrics
		assertions.equal(rig.hub.boundMarker, replacement.marker)
		assertions.isTrue(rig.hub.guiVisible)
		assertions.equal(healthLabel(rig).Text, "60 / 100")
		assertions.equal(recovered.renderCount, 1)
		assertions.isTrue(recovered.markerRebindCount >= originalRebinds + 2)
		assertions.equal(recovered.connectionCount, BaseWorldView.MAX_CONNECTION_COUNT)
		assertions.equal(activeWatchCount(rig.hub), BaseWorldView.MAX_CONNECTION_COUNT)
		destroyRig(rig)
	end),

	TestHarness.case("recreates deleted renamed or reparented UI from cached authoritative state", function(assertions)
		local rig = makeRig()
		local marker = (rig.markerTree :: MarkerTree).marker
		local state = renderState(2, 25, "Active", 75, nil)
		local firstMetrics = render(rig.view, state)
		local firstGui = gui(rig)
		assertions.equal(firstMetrics.tweenCreationCount, 1)

		firstGui:Destroy()
		fireWatch(rig.hub, "Ancestry", firstGui, nil)
		local secondGui = gui(rig)
		assertions.notEqual(secondGui, firstGui)
		assertions.equal(rig.hub.boundGui, secondGui)
		assertions.equal(rig.hub.boundMarker, marker)
		assertions.isTrue(rig.hub.guiVisible)
		assertions.equal(healthLabel(rig).Text, "25 / 100")
		assertions.equal(lowLabel(rig).Text, "LOW")
		assertions.equal(damageLabel(rig).Text, "-75")
		local afterDelete = (rig.view:getMetrics() :: any).value :: BaseWorldView.Metrics
		assertions.equal(afterDelete.viewRecreationCount, firstMetrics.viewRecreationCount + 1)
		assertions.equal(afterDelete.tweenCreationCount, 1)
		assertions.equal(afterDelete.activeTweenCount, 0)

		local oldGui = secondGui
		local oldHealth = healthLabel(rig)
		oldHealth.Name = "TamperedHealth"
		fireWatch(rig.hub, "Property", oldHealth, "Name")
		assertions.isTrue(gui(rig) ~= oldGui)
		assertions.equal(healthLabel(rig).Text, "25 / 100")
		assertions.equal(rig.hub.boundMarker, marker)
		assertions.equal(activeWatchCount(rig.hub), BaseWorldView.MAX_CONNECTION_COUNT)
		destroyRig(rig)
	end),

	TestHarness.case("rejects noncanonical render state without mutating the last display", function(assertions)
		local rig = makeRig()
		render(rig.view, renderState(1, 90, "Active", nil, nil))
		local mutable = {
			visible = true,
			basePosition = BASE_POSITION,
			baseRevision = 2,
			fillScale = 0.5,
			healthText = "50 / 100",
			statusText = "ACTIVE",
			lowVisible = false,
			lowText = "",
			damageVisible = false,
			damageText = "",
		}
		expectFailure(assertions, rig.view:render(mutable), "INVALID_RENDER_STATE")
		assertions.equal(healthLabel(rig).Text, "90 / 100")
		assertions.equal((rig.view:getMetrics() :: any).value.renderCount, 1)

		local malformed = table.clone(renderState(2, 50, "Active", nil, nil))
		malformed.fillScale = 0.75
		table.freeze(malformed)
		expectFailure(assertions, rig.view:render(malformed), "INVALID_RENDER_STATE")
		assertions.equal(healthLabel(rig).Text, "90 / 100")
		destroyRig(rig)
	end),

	TestHarness.case("keeps watcher and tween ownership constant through repeated recreation", function(assertions)
		local rig = makeRig()
		render(rig.view, renderState(1, 100, "Active", nil, nil))
		for revision = 2, 12 do
			local marker = (rig.markerTree :: MarkerTree).marker
			marker.Position = BASE_POSITION + Vector3.new(0, 0, BaseWorldView.POSITION_TOLERANCE * 2)
			fireWatch(rig.hub, "Property", marker, "CFrame")
			marker.Position = BASE_POSITION
			fireWatch(rig.hub, "Property", marker, "CFrame")
			local damage = if revision % 2 == 0 then 1 else nil
			render(rig.view, renderState(revision, 100 - revision, "Active", damage, nil))
			local current = (rig.view:getMetrics() :: any).value :: BaseWorldView.Metrics
			assertions.equal(current.connectionCount, BaseWorldView.MAX_CONNECTION_COUNT)
			assertions.isTrue(current.activeTweenCount <= 1)
			assertions.equal(activeWatchCount(rig.hub), BaseWorldView.MAX_CONNECTION_COUNT)
		end
		assertions.equal(rig.hub.maximumActivePulseCount, 1)
		destroyRig(rig)
	end),

	TestHarness.case("cleans every callback tween binding and GUI idempotently", function(assertions)
		local rig = makeRig()
		render(rig.view, renderState(2, 80, "Active", 20, nil))
		local ownedGui = gui(rig)
		assertions.equal(rig.hub.activePulseCount, 1)
		local cleanupResult = rig.view:cleanup()
		assertions.isTrue(cleanupResult.ok)
		assertions.isTrue(rig.view:cleanup().ok)
		assertions.isNil(ownedGui.Parent)
		assertions.isNil(rig.playerGuiParent:FindFirstChild(BaseWorldView.GUI_NAME))
		assertions.equal(activeWatchCount(rig.hub), 0)
		assertions.equal(rig.hub.activePulseCount, 0)
		assertions.isTrue(rig.hub.pulses[1].cancelled)
		assertions.isTrue(rig.hub.pulses[1].destroyed)
		expectFailure(assertions, rig.view:getMetrics(), "CLEANED_UP")
		expectFailure(assertions, rig.view:render(renderState(3, 70, "Active", nil, nil)), "CLEANED_UP")

		fireWatch(rig.hub, "WorkspaceAdded", nil, nil)
		fireWatch(rig.hub, "PlayerGuiAdded", nil, nil)
		assertions.isNil(rig.playerGuiParent:FindFirstChild(BaseWorldView.GUI_NAME))
		rig.playerGuiParent:Destroy()
		rig.workspaceRoot:Destroy()
	end),

	TestHarness.case(
		"keeps the production-only constructor seam hidden outside the exact test mapping",
		function(assertions)
			local parent = Instance.new("Folder")
			local workspaceRoot = Instance.new("Folder")
			expectFailure(
				assertions,
				(newForTests :: BaseWorldView.TestConstructor)(parent, workspaceRoot, {} :: any),
				"INVALID_DEPENDENCIES"
			)

			local conflict = Instance.new("Folder")
			conflict.Name = BaseWorldView.GUI_NAME
			conflict.Parent = parent
			expectFailure(
				assertions,
				(newForTests :: BaseWorldView.TestConstructor)(parent, workspaceRoot, makeHub().dependencies),
				"CREATION_FAILED"
			)
			parent:Destroy()
			workspaceRoot:Destroy()

			local productionFolder = script.Parent.Parent.ProductionClientBase:Clone()
			productionFolder.Name = "BaseWorldViewProductionLocationProbe"
			productionFolder.Parent = game:GetService("ReplicatedStorage")
			local productionLocated = require(productionFolder.BaseWorldView)
			assertions.isNil(productionLocated.newForTests)
			productionFolder:Destroy()
		end
	),
})
