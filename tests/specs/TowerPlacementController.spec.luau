--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)

local ClientRequestTracker = require(script.Parent.Parent.ProductionClientNetworking.ClientRequestTracker)
local PlacementInputAdapter = require(script.Parent.Parent.ProductionClientPlacement.PlacementInputAdapter)
local PlacementPreviewReducer = require(script.Parent.Parent.ProductionClientPlacement.PlacementPreviewReducer)
local TowerPlacementController = require(script.Parent.Parent.ProductionClientPlacement.TowerPlacementController)
local TowerPlacementService = require(script.Parent.Parent.ProductionServerPlacement.TowerPlacementService)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local PlacementProtocol = require(ReplicatedStorage.Shared.match.PlacementProtocol)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local Result = require(ReplicatedStorage.Shared.util.Result)

type Signal = {
	connect: (self: Signal, (unknown, ...unknown) -> ()) -> RBXScriptConnection,
	fire: (self: Signal, unknown, ...unknown) -> (),
	force: (self: Signal, unknown, ...unknown) -> (),
}

type Rig = {
	controller: TowerPlacementController.Controller,
	service: any,
	tracker: any,
	reducer: any,
	input: any,
	order: { string },
	getFires: { any },
	submitFires: { any },
	revisionSignal: Signal,
	getResponseSignal: Signal,
	submitResponseSignal: Signal,
	inputBeganSignal: Signal,
	inputChangedSignal: Signal,
	inputEndedSignal: Signal,
	preferredSignal: Signal,
	renderSignal: Signal,
	disconnectCount: number,
	renders: { any },
	reticles: { any },
	viewCleaned: boolean,
	pointer: Vector2,
	viewport: Vector2,
	raycastMode: string,
	raycastInputs: { Vector2 },
	studioMode: boolean,
	studioTriggerName: string?,
	studioTriggerHandler: ((...unknown) -> unknown)?,
	studioTriggerDestroyed: boolean,
}

local logger = Log.new(EnvironmentContext.new("client", "Match", 0, false))
local newTrackerForTests = ClientRequestTracker.newForTests
local newControllerForTests = TowerPlacementController.newForTests
local invokeUiActionForTests = TowerPlacementController.invokeUiActionForTests

if newTrackerForTests == nil or newControllerForTests == nil or invokeUiActionForTests == nil then
	error("[ATD_TEST_FIXTURE][code=PLACEMENT_CONTROLLER_TEST_SEAM_MISSING]", 0)
end
local invokeUiAction = invokeUiActionForTests :: any

local registryResult = RemoteRegistry.create({
	{
		name = PlacementProtocol.GET_QUERY_ENDPOINT,
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	},
	{
		name = PlacementProtocol.SUBMIT_PLACEMENT_ENDPOINT,
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	},
	{
		name = PlacementProtocol.REVISION_ENDPOINT,
		transport = "ReliableRemoteEvent",
		direction = "ServerToClient",
		kind = "Event",
		response = "None",
		placeRoles = { "Match" },
	},
})
if not registryResult.ok then
	error("[ATD_TEST_FIXTURE][code=PLACEMENT_CONTROLLER_REGISTRY_FAILED]", 0)
end
local REGISTRY = registryResult.value

local function occupied(slot: number): any
	return {
		kind = "Occupied",
		slot = slot,
		towerId = `tower:controller-{slot}`,
		displayName = `Controller {slot}`,
		iconAssetKey = `test.controller.{slot}`,
		rangeStuds = 10,
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

local function query(revision: number?): any
	return {
		contractVersion = 1,
		matchId = "match:phase13-controller",
		mapId = "map:phase07-graybox",
		queryRevision = revision or 1,
		loadoutRevision = 2,
		bounds = { cframe = CFrame.new(), size = Vector3.new(120, 20, 120) },
		placementZones = {
			{ cframe = CFrame.new(0, -4, 0), size = Vector3.new(100, 2, 100), surfaceCategory = "Land" },
		},
		exclusions = {
			{ cframe = CFrame.new(20, -4, 0), size = Vector3.new(6, 2, 6) },
		},
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

local function successWire(request: any, payload: unknown): any
	return {
		requestId = request.requestId,
		state = "Success",
		payload = payload,
	}
end

local function rejectedWire(request: any, code: string): any
	return {
		requestId = request.requestId,
		state = "Rejected",
		error = { code = code },
	}
end

local function makeSignal(rig: Rig, name: string): Signal
	local listener: ((unknown, ...unknown) -> ())? = nil
	local active = false
	local signal = {} :: Signal
	function signal:connect(nextListener)
		table.insert(rig.order, name)
		listener = nextListener
		active = true
		return RobloxAdapter.createConnection(function()
			if active then
				active = false
				rig.disconnectCount += 1
			end
		end) :: any
	end
	function signal:fire(value, ...)
		if active and listener ~= nil then
			(listener :: any)(value, ...)
		end
	end
	function signal:force(value, ...)
		if listener ~= nil then
			(listener :: any)(value, ...)
		end
	end
	return signal
end

local function makeRig(studioMode: boolean?): Rig
	local requestSequence = 0
	local trackerResult = (newTrackerForTests :: any)(REGISTRY, "Match", function(): string
		requestSequence += 1
		return `placectrl{string.format("%04d", requestSequence)}`
	end)
	local reducerResult = PlacementPreviewReducer.new()
	local inputResult = PlacementInputAdapter.new()
	if not trackerResult.ok or not reducerResult.ok or not inputResult.ok then
		error("[ATD_TEST_FIXTURE][code=PLACEMENT_CONTROLLER_DEPENDENCY_FAILED]", 0)
	end
	local rig = {
		controller = nil :: any,
		service = nil,
		tracker = trackerResult.value,
		reducer = reducerResult.value,
		input = inputResult.value,
		order = {},
		getFires = {},
		submitFires = {},
		revisionSignal = nil :: any,
		getResponseSignal = nil :: any,
		submitResponseSignal = nil :: any,
		inputBeganSignal = nil :: any,
		inputChangedSignal = nil :: any,
		inputEndedSignal = nil :: any,
		preferredSignal = nil :: any,
		renderSignal = nil :: any,
		disconnectCount = 0,
		renders = {},
		reticles = {},
		viewCleaned = false,
		pointer = Vector2.new(0, 0),
		viewport = Vector2.new(1280, 720),
		raycastMode = "Hit",
		raycastInputs = {},
		studioMode = studioMode == true,
		studioTriggerName = nil,
		studioTriggerHandler = nil,
		studioTriggerDestroyed = false,
	} :: Rig
	rig.revisionSignal = makeSignal(rig, "revision")
	rig.getResponseSignal = makeSignal(rig, "get-response")
	rig.submitResponseSignal = makeSignal(rig, "submit-response")
	rig.inputBeganSignal = makeSignal(rig, "input-began")
	rig.inputChangedSignal = makeSignal(rig, "input-changed")
	rig.inputEndedSignal = makeSignal(rig, "input-ended")
	rig.preferredSignal = makeSignal(rig, "preferred")
	rig.renderSignal = makeSignal(rig, "render")

	local getDefinition = REGISTRY:get(PlacementProtocol.GET_QUERY_ENDPOINT)
	local submitDefinition = REGISTRY:get(PlacementProtocol.SUBMIT_PLACEMENT_ENDPOINT)
	local revisionDefinition = REGISTRY:get(PlacementProtocol.REVISION_ENDPOINT)
	local view = {
		render = function(_self, state)
			table.insert(rig.renders, state)
			return Result.ok(true)
		end,
		setReticle = function(_self, position, visible)
			table.insert(rig.reticles, { position = position, visible = visible })
			return Result.ok(true)
		end,
		getMetrics = function(_self)
			return table.freeze({ renderCount = #rig.renders, cleaned = rig.viewCleaned })
		end,
		cleanup = function(_self)
			rig.viewCleaned = true
			return Result.ok(true)
		end,
	}
	local dependencies: TowerPlacementController.Dependencies = {
		tracker = rig.tracker,
		getQuery = {
			definition = getDefinition :: any,
			connectResponse = function(listener)
				return rig.getResponseSignal:connect(listener)
			end,
			fire = function(envelope)
				table.insert(rig.order, "fire-get")
				table.insert(rig.getFires, envelope)
			end,
		},
		submitPlacement = {
			definition = submitDefinition :: any,
			connectResponse = function(listener)
				return rig.submitResponseSignal:connect(listener)
			end,
			fire = function(envelope)
				table.insert(rig.order, "fire-submit")
				table.insert(rig.submitFires, envelope)
			end,
		},
		revisionEvent = {
			definition = revisionDefinition :: any,
			connectEvent = function(listener)
				return rig.revisionSignal:connect(listener)
			end,
		},
		reducer = rig.reducer,
		input = rig.input,
		view = view,
		connectInputBegan = function(listener)
			return rig.inputBeganSignal:connect(listener :: any)
		end,
		connectInputChanged = function(listener)
			return rig.inputChangedSignal:connect(listener :: any)
		end,
		connectInputEnded = function(listener)
			return rig.inputEndedSignal:connect(listener :: any)
		end,
		connectPreferredInputChanged = function(listener)
			return rig.preferredSignal:connect(listener :: any)
		end,
		connectRenderStep = function(listener)
			return rig.renderSignal:connect(listener :: any)
		end,
		getPointerPosition = function()
			return rig.pointer
		end,
		getViewportSize = function()
			return rig.viewport
		end,
		getInitialInput = function()
			return "Desktop"
		end,
		raycast = function(screenPosition)
			table.insert(rig.raycastInputs, screenPosition)
			if rig.raycastMode == "Miss" then
				return nil
			elseif rig.raycastMode == "Throw" then
				error("PRIVATE_RAYCAST_FAILURE", 0)
			elseif rig.raycastMode == "Viewport" then
				return Vector3.new((screenPosition.X - 640) / 10, -3, (screenPosition.Y - 360) / 10)
			end
			return Vector3.new(screenPosition.X, -3, screenPosition.Y)
		end,
		isStudio = function()
			return rig.studioMode
		end,
		createStudioEvidenceTrigger = function(handler)
			rig.studioTriggerName = TowerPlacementController.STUDIO_EVIDENCE_TRIGGER_NAME
			rig.studioTriggerHandler = handler
			return {
				Destroy = function()
					rig.studioTriggerDestroyed = true
					rig.studioTriggerHandler = nil
				end,
			}
		end,
	}
	local controllerResult = (newControllerForTests :: any)(logger, dependencies)
	if not controllerResult.ok then
		error("[ATD_TEST_FIXTURE][code=PLACEMENT_CONTROLLER_CREATION_FAILED]", 0)
	end
	rig.controller = controllerResult.value
	rig.service = rig.controller:getServiceDefinition()
	rig.service.initialize()
	rig.service.start()
	return rig
end

local function respondQuery(rig: Rig, requestIndex: number, snapshot: any)
	rig.getResponseSignal:fire(successWire(rig.getFires[requestIndex], snapshot))
end

local function selectDesktop(rig: Rig, slot: number)
	rig.inputBeganSignal:fire({ kind = "SelectSlot", source = "Desktop", slot = slot })
end

local function renderFrame(rig: Rig, delta: number?)
	rig.renderSignal:fire(delta or 1 / 60)
end

local function currentState(rig: Rig): any
	local result = rig.reducer:getState()
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=PLACEMENT_CONTROLLER_STATE_FAILED]", 0)
	end
	return result.value
end

return TestHarness.suite("Phase 13 tower placement client controller", {
	TestHarness.case("connects eight fixed callbacks before one tracked initial query", function(assertions)
		local rig = makeRig()
		assertions.equal(rig.controller:getState(), "Started")
		assertions.equal(rig.service.name, "TowerPlacementController")
		assertions.equal(rig.service.dependencies[1], "WaveController")
		assertions.equal(rig.controller:getMetrics().connectionCount, TowerPlacementController.CONNECTION_COUNT)
		assertions.equal(#rig.getFires, 1)
		assertions.equal(next(rig.getFires[1].payload), nil)
		assertions.equal(rig.controller:getMetrics().queryRequestCount, 1)
		assertions.isTrue(rig.controller:getMetrics().queryPending)
		assertions.equal(rig.tracker:getStats().pendingCount, 1)
		rig.service.shutdown()
	end),

	TestHarness.case(
		"applies a query and performs no more than one explicit-filter raycast per frame",
		function(assertions)
			local rig = makeRig()
			respondQuery(rig, 1, query())
			selectDesktop(rig, 1)
			rig.pointer = Vector2.new(5, 6)
			rig.inputBeganSignal:fire({ kind = "SelectSlot", source = "Desktop", slot = 2 })
			rig.pointer = Vector2.new(7, 8)
			renderFrame(rig)
			assertions.equal(#rig.raycastInputs, 1)
			assertions.equal(rig.raycastInputs[1], Vector2.new(7, 8))
			assertions.equal(currentState(rig).positionXZ, Vector2.new(7, 8))
			assertions.equal(currentState(rig).validity, "Valid")
			assertions.equal(rig.controller:getMetrics().maximumRaycastsPerFrame, 1)
			rig.service.shutdown()
		end
	),

	TestHarness.case(
		"submits only reducer-built desktop intent and recovers from accepted receipt",
		function(assertions)
			local rig = makeRig()
			respondQuery(rig, 1, query())
			selectDesktop(rig, 1)
			renderFrame(rig)
			rig.inputBeganSignal:fire({ kind = "Rotate", source = "Desktop", direction = 1 })
			rig.inputBeganSignal:fire({ kind = "Confirm", source = "Desktop" })
			assertions.equal(#rig.submitFires, 1)
			local intent = rig.submitFires[1].payload
			assertions.equal(intent.matchId, "match:phase13-controller")
			assertions.equal(intent.observedQueryRevision, 1)
			assertions.equal(intent.loadoutRevision, 2)
			assertions.equal(intent.slot, 1)
			assertions.equal(intent.positionXZ, Vector2.new(0, 0))
			assertions.equal(intent.yawDegrees, 15)
			assertions.isNil(intent.towerId)
			assertions.isNil(intent.placementCFrame)
			rig.submitResponseSignal:fire(successWire(rig.submitFires[1], {
				state = "Accepted",
				runtimeTowerId = 11,
				placementCFrame = CFrame.new(0, -3, 0),
				queryRevision = 2,
			}))
			assertions.equal(rig.controller:getMetrics().acceptedPlacementCount, 1)
			assertions.equal(#rig.getFires, 2)
			assertions.equal(currentState(rig).phase, "Selected")
			rig.service.shutdown()
		end
	),

	TestHarness.case("touch drag and pinch never place while tap then separate confirm does", function(assertions)
		local rig = makeRig()
		respondQuery(rig, 1, query())
		rig.preferredSignal:fire("Touch")
		invokeUiAction(rig.controller, { kind = "SelectSlot", slot = 1 })
		rig.inputBeganSignal:fire({
			kind = "TouchBegin",
			source = "Touch",
			touchId = 1,
			position = Vector2.new(10, 10),
			processed = false,
		})
		rig.inputChangedSignal:fire({
			kind = "TouchMove",
			source = "Touch",
			touchId = 1,
			position = Vector2.new(40, 10),
		})
		rig.inputEndedSignal:fire({
			kind = "TouchEnd",
			source = "Touch",
			touchId = 1,
			position = Vector2.new(40, 10),
		})
		renderFrame(rig)
		assertions.equal(#rig.submitFires, 0)
		assertions.equal(#rig.raycastInputs, 0)

		for touchId = 1, 2 do
			rig.inputBeganSignal:fire({
				kind = "TouchBegin",
				source = "Touch",
				touchId = touchId,
				position = Vector2.new(touchId * 10, 20),
				processed = false,
			})
		end
		for touchId = 1, 2 do
			rig.inputEndedSignal:fire({
				kind = "TouchEnd",
				source = "Touch",
				touchId = touchId,
				position = Vector2.new(touchId * 10, 20),
			})
		end
		renderFrame(rig)
		assertions.equal(#rig.raycastInputs, 0)

		rig.inputBeganSignal:fire({
			kind = "TouchBegin",
			source = "Touch",
			touchId = 3,
			position = Vector2.new(3, 4),
			processed = false,
		})
		rig.inputEndedSignal:fire({
			kind = "TouchEnd",
			source = "Touch",
			touchId = 3,
			position = Vector2.new(3, 4),
		})
		renderFrame(rig)
		assertions.equal(currentState(rig).positionXZ, Vector2.new(3, 4))
		assertions.equal(#rig.submitFires, 0)
		invokeUiAction(rig.controller, { kind = "Confirm" })
		assertions.equal(#rig.submitFires, 1)
		rig.service.shutdown()
	end),

	TestHarness.case(
		"gamepad moves its reticle and uses explicit rotate confirm cancel and slot cycling",
		function(assertions)
			local rig = makeRig()
			respondQuery(rig, 1, query())
			rig.raycastMode = "Viewport"
			rig.preferredSignal:fire("Gamepad")
			rig.inputBeganSignal:fire({ kind = "CycleSlot", source = "Gamepad", direction = 1 })
			assertions.equal(currentState(rig).selectedSlot, 1)
			rig.inputChangedSignal:fire({ kind = "GamepadAxis", source = "Gamepad", axis = Vector2.new(1, 0) })
			renderFrame(rig, 0.1)
			assertions.equal(#rig.raycastInputs, 1)
			assertions.isTrue(rig.raycastInputs[1].X > 640)
			assertions.isTrue(rig.reticles[#rig.reticles].visible)
			rig.inputBeganSignal:fire({ kind = "Rotate", source = "Gamepad", direction = 1 })
			assertions.equal(currentState(rig).yawDegrees, 15)
			rig.inputBeganSignal:fire({ kind = "Confirm", source = "Gamepad" })
			assertions.equal(#rig.submitFires, 1)
			rig.submitResponseSignal:fire(successWire(rig.submitFires[1], {
				state = "Rejected",
				reason = "Occupied",
				queryRevision = 1,
			}))
			assertions.equal(rig.controller:getMetrics().rejectedPlacementCount, 1)
			rig.inputBeganSignal:fire({ kind = "Cancel", source = "Gamepad" })
			assertions.equal(currentState(rig).phase, "Idle")
			rig.service.shutdown()
		end
	),

	TestHarness.case("Studio evidence trigger drives only bounded gamepad controller actions", function(assertions)
		local rig = makeRig(true)
		respondQuery(rig, 1, query())
		rig.raycastMode = "Viewport"
		assertions.equal(rig.studioTriggerName, TowerPlacementController.STUDIO_EVIDENCE_TRIGGER_NAME)
		assertions.isNotNil(rig.studioTriggerHandler)
		local invoke = rig.studioTriggerHandler :: (...unknown) -> unknown

		assertions.isTrue((invoke({ operation = "CycleNext" }) :: any).ok)
		assertions.equal(currentState(rig).preferredInput, "Gamepad")
		assertions.equal(currentState(rig).selectedSlot, 1)
		assertions.isTrue((invoke({ operation = "Axis", axis = Vector2.new(1, 0) }) :: any).ok)
		renderFrame(rig, 0.1)
		assertions.isTrue(rig.raycastInputs[1].X > 640)
		assertions.isTrue(rig.reticles[#rig.reticles].visible)
		assertions.isTrue((invoke({ operation = "Axis", axis = Vector2.zero }) :: any).ok)
		assertions.isTrue((invoke({ operation = "Rotate" }) :: any).ok)
		assertions.equal(currentState(rig).yawDegrees, 15)
		assertions.isTrue((invoke({ operation = "Confirm" }) :: any).ok)
		assertions.equal(#rig.submitFires, 1)
		rig.submitResponseSignal:fire(successWire(rig.submitFires[1], {
			state = "Rejected",
			reason = "Occupied",
			queryRevision = 1,
		}))
		assertions.isTrue((invoke({ operation = "Cancel" }) :: any).ok)
		assertions.equal(currentState(rig).phase, "Idle")
		assertions.isFalse((invoke({ operation = "Cancel", extra = true }) :: any).ok)
		assertions.isFalse((invoke({ operation = "Axis", axis = Vector2.new(2, 0) }) :: any).ok)

		local diagnostics = invoke({ operation = "Diagnostics" }) :: any
		assertions.isTrue(diagnostics.ok)
		assertions.equal(diagnostics.value.studioTriggerCount, 1)
		assertions.equal(diagnostics.value.studioOperationCount, 7)
		assertions.equal(diagnostics.value.connectionCount, TowerPlacementController.CONNECTION_COUNT)
		rig.service.shutdown()
		assertions.isTrue(rig.studioTriggerDestroyed)
		assertions.equal(rig.controller:getMetrics().studioTriggerCount, 0)
		assertions.equal(rig.controller:getMetrics().studioOperationCount, 0)
	end),

	TestHarness.case(
		"preferred input changes update hints without discarding selection or position",
		function(assertions)
			local rig = makeRig()
			respondQuery(rig, 1, query())
			selectDesktop(rig, 1)
			renderFrame(rig)
			local position = currentState(rig).positionXZ
			rig.preferredSignal:fire("Touch")
			assertions.equal(currentState(rig).preferredInput, "Touch")
			assertions.equal(currentState(rig).positionXZ, position)
			rig.preferredSignal:fire("Gamepad")
			assertions.equal(currentState(rig).selectedSlot, 1)
			assertions.equal(rig.controller:getMetrics().connectionCount, 8)
			rig.service.shutdown()
		end
	),

	TestHarness.case(
		"recovers a rejected initial query from the authoritative PreWave lifecycle publication",
		function(assertions)
			local rig = makeRig()
			rig.getResponseSignal:fire(rejectedWire(rig.getFires[1], "UNAVAILABLE"))
			assertions.isFalse(rig.controller:getMetrics().queryPending)
			assertions.equal(#rig.getFires, 1)
			assertions.isNil(rig.studioTriggerHandler)

			local snapshotCount = 0
			local revisionCount = 0
			local lifecycleSender = TowerPlacementService.createRevisionAwareSnapshotSender(
				function(_recipient, snapshot)
					snapshotCount += 1
					assertions.equal(snapshot.state, "PreWave")
					return true
				end,
				function(_recipient, payload)
					revisionCount += 1
					rig.revisionSignal:fire({ payload = payload })
					return true
				end,
				function()
					return 1
				end
			)
			assertions.isTrue(lifecycleSender("authenticated-player", {
				matchId = "match:phase13-controller",
				revision = 3,
				state = "PreWave",
				participants = {
					{ userId = 123, state = "Active", ready = true },
				},
			}))
			assertions.equal(snapshotCount, 1)
			assertions.equal(revisionCount, 1)
			assertions.equal(#rig.getFires, 2)
			assertions.isTrue(rig.controller:getMetrics().queryPending)
			assertions.equal(rig.controller:getMetrics().revisionEventCount, 1)
			respondQuery(rig, 2, query())
			assertions.equal(rig.controller:getMetrics().queryRevision, 1)
			assertions.isFalse(rig.controller:getMetrics().refreshRequired)
			rig.service.shutdown()
		end
	),

	TestHarness.case("coalesces revision refresh while one query is pending", function(assertions)
		local rig = makeRig()
		respondQuery(rig, 1, query())
		rig.revisionSignal:fire({
			payload = { matchId = "match:phase13-controller", queryRevision = 2 },
		})
		assertions.equal(#rig.getFires, 2)
		rig.revisionSignal:fire({
			payload = { matchId = "match:phase13-controller", queryRevision = 3 },
		})
		assertions.equal(#rig.getFires, 2)
		assertions.isTrue(rig.controller:getMetrics().refreshQueued)
		respondQuery(rig, 2, query(2))
		assertions.equal(#rig.getFires, 3)
		respondQuery(rig, 3, query(3))
		assertions.equal(rig.controller:getMetrics().queryRevision, 3)
		assertions.isFalse(rig.controller:getMetrics().refreshQueued)
		rig.service.shutdown()
	end),

	TestHarness.case("clears a preview on ray misses and contains raycast failures", function(assertions)
		local rig = makeRig()
		respondQuery(rig, 1, query())
		selectDesktop(rig, 1)
		renderFrame(rig)
		assertions.equal(currentState(rig).phase, "Positioned")
		rig.raycastMode = "Miss"
		renderFrame(rig)
		assertions.equal(currentState(rig).phase, "Selected")
		rig.raycastMode = "Throw"
		renderFrame(rig)
		assertions.equal(currentState(rig).phase, "Selected")
		assertions.equal(rig.controller:getMetrics().raycastCount, 3)
		rig.service.shutdown()
	end),

	TestHarness.case("handles dispatcher rejection without retaining a submitting state", function(assertions)
		local rig = makeRig()
		respondQuery(rig, 1, query())
		selectDesktop(rig, 1)
		renderFrame(rig)
		rig.inputBeganSignal:fire({ kind = "Confirm", source = "Desktop" })
		assertions.equal(currentState(rig).phase, "Submitting")
		rig.submitResponseSignal:fire(rejectedWire(rig.submitFires[1], "UNAVAILABLE"))
		assertions.equal(currentState(rig).phase, "Positioned")
		assertions.isFalse(rig.controller:getMetrics().submitPending)
		assertions.equal(rig.controller:getMetrics().rejectedPlacementCount, 1)
		rig.service.shutdown()
	end),

	TestHarness.case("cleans requests callbacks reducer input and view with late callbacks inert", function(assertions)
		local rig = makeRig()
		respondQuery(rig, 1, query())
		selectDesktop(rig, 1)
		renderFrame(rig)
		rig.inputBeganSignal:fire({ kind = "Confirm", source = "Desktop" })
		local before = rig.controller:getMetrics()
		rig.service.shutdown()
		assertions.equal(rig.controller:getState(), "Shutdown")
		assertions.equal(rig.disconnectCount, TowerPlacementController.CONNECTION_COUNT)
		assertions.equal(rig.tracker:getStats().pendingCount, 0)
		assertions.isTrue(rig.viewCleaned)
		assertions.equal(rig.controller:getMetrics().connectionCount, 0)
		rig.inputBeganSignal:force({ kind = "Confirm", source = "Desktop" })
		rig.renderSignal:force(1 / 60)
		rig.revisionSignal:force({ payload = { matchId = "match:phase13-controller", queryRevision = 2 } })
		assertions.equal(rig.controller:getMetrics().submitRequestCount, before.submitRequestCount)
		assertions.equal(rig.controller:getMetrics().raycastCount, before.raycastCount)
		assertions.isTrue(pcall(rig.service.shutdown))
	end),
})
