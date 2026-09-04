--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local ClientRequestTracker = require(script.Parent.Parent.ProductionClientNetworking.ClientRequestTracker)
local PlayableMatchController = require(script.Parent.Parent.ProductionClientPlayable.PlayableMatchController)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DefaultSettings = require(ReplicatedStorage.Shared.config.DefaultSettings)
local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local MatchTravelProtocol = require(ReplicatedStorage.Shared.match.MatchTravelProtocol)
local PlayableMatchProtocol = require(ReplicatedStorage.Shared.match.PlayableMatchProtocol)
local ProductionRemotes = require(ReplicatedStorage.Shared.network.ProductionRemotes)

type Signal = {
	connect: (self: Signal, (unknown, ...unknown) -> ()) -> RBXScriptConnection,
	fire: (self: Signal, unknown, ...unknown) -> (),
}

local newTrackerForTests = ClientRequestTracker.newForTests
local newControllerForTests = PlayableMatchController.newForTests
local invokeActionForTests = PlayableMatchController.invokeSemanticActionForTests
local invokePointerForTests = PlayableMatchController.invokeWorldPointerForTests
if
	newTrackerForTests == nil
	or newControllerForTests == nil
	or invokeActionForTests == nil
	or invokePointerForTests == nil
then
	error("[ATD_TEST_FIXTURE][code=PLAYABLE_CONTROLLER_TEST_SEAM_MISSING]", 0)
end

local logger = Log.new(EnvironmentContext.new("client", "Match", 0, false))

local function towerOption(slot: number, towerId: string, displayName: string, cost: number): any
	return {
		slot = slot,
		unitId = `unit:controller-{slot}`,
		towerId = towerId,
		displayName = displayName,
		placementCost = cost,
		description = `Place {displayName}.`,
	}
end

local function snapshot(revision: number, state: string?): any
	local selectedState = state or "Playing"
	local isResults = selectedState == "Results"
	local isReady = selectedState == "Ready"
	return {
		matchId = "match:playable-controller",
		viewerRole = "Participant",
		rewarding = false,
		revision = revision,
		loadoutRevision = 6,
		state = selectedState,
		result = if isResults then "Victory" else "None",
		mapId = "map:phase07-graybox",
		mapDisplayName = "Backyard Graybox",
		difficultyId = "difficulty:local",
		difficultyDisplayName = "Local",
		serverTime = 110,
		waveNumber = if isReady then 0 elseif isResults then 5 else 2,
		totalWaves = 5,
		wavePhase = if isResults then "Results" elseif isReady then "Ready" else "Resolving",
		nextWaveServerTime = 0,
		baseHealth = 27,
		maximumBaseHealth = 30,
		enemiesAlive = if isResults or isReady then 0 else 1,
		battleCash = 245,
		participants = { readyCount = if isReady then 0 else 1, participantCount = 1 },
		towerOptions = {
			towerOption(1, "tower:dart-ant", "Dart Ant", 120),
			towerOption(2, "tower:rapid-ant", "Rapid Ant", 165),
			towerOption(3, "tower:guard-ant", "Guard Ant", 225),
		},
		towers = if isReady or isResults
			then {}
			else {
				{
					runtimeTowerId = 1,
					revision = 4,
					towerId = "tower:dart-ant",
					displayName = "Dart Ant",
					ownerUserId = 42,
					level = 2,
					targetMode = "First",
					position = Vector3.new(4, 1, 7),
					rotationDegrees = 90,
					totalInvestment = 230,
					cooldownEndsServerTime = 110.4,
					damage = 22,
					cooldownSeconds = 0.7,
					rangeStuds = 27,
					upgradeCost = 190,
					sellValue = 161,
				},
			},
		enemies = if isReady or isResults
			then {}
			else {
				{
					runtimeEnemyId = 3,
					enemyId = "enemy:worker-ant",
					displayName = "Worker Ant",
					currentHealth = 21,
					maximumHealth = 45,
					position = Vector3.new(-8, 2, 3),
					pathProgress = 18,
				},
			},
		stats = {
			durationSeconds = 10,
			wavesCompleted = if isResults then 5 elseif isReady then 0 else 1,
			damageDealt = 24,
			battleCashEarned = 76,
			battleCashSpent = 230,
			placements = 1,
			upgrades = 1,
			sells = 0,
			baseHealthRemaining = 27,
		},
		settings = table.clone(DefaultSettings),
	}
end

local function travelSnapshot(revision: number, role: string?): any
	return {
		version = 1,
		matchId = "match:playable-controller",
		revision = revision,
		viewerRole = role or "Participant",
		returnStatus = "Idle",
		rematch = {
			revision = revision,
			state = "Pending",
			deadline = 300,
			votes = { { userId = 42, choice = "Pending" } },
		},
	}
end

local function successWire(request: any, payload: unknown): any
	return { requestId = request.requestId, state = "Success", payload = payload }
end

local function rejectedWire(request: any, code: string): any
	return { requestId = request.requestId, state = "Rejected", error = { code = code } }
end

local function replayReplacement(): any
	local value = snapshot(1, "Ready")
	value.matchId = "match:playable-replacement"
	return value
end

local function makeSignal(rig: any): Signal
	local listener: ((unknown, ...unknown) -> ())? = nil
	local active = false
	local signal = {} :: Signal
	function signal:connect(nextListener)
		listener = nextListener
		active = true
		return RobloxAdapter.createConnection(function()
			if active then
				active = false
				rig.disconnectCount += 1
			end
		end) :: RBXScriptConnection
	end
	function signal:fire(value, ...)
		if active and listener ~= nil then
			(listener :: (unknown, ...unknown) -> ())(value, ...)
		end
	end
	return signal
end

local function makeRig(localUserId: number?): any
	local rig: any = {
		fires = {},
		responses = {},
		events = {},
		renders = {},
		worlds = {},
		effects = {},
		appliedSettings = {},
		contexts = {},
		disconnectCount = 0,
		clock = 20,
		pointer = Vector2.new(100, 200),
		viewport = Vector2.new(1280, 720),
		raycastPosition = Vector3.new(8, 0, 9),
		raycastScreenPosition = nil,
		pickedTowerId = 1,
		overviewFocused = 0,
		focused = 0,
		spectatorFocuses = {},
		restored = 0,
		renderListener = nil,
		worldPointerListener = nil,
		viewInputFamily = "Desktop",
		inputFamily = "Desktop",
		renderFailuresRemaining = 0,
		viewCleaned = 0,
		inputCleaned = 0,
		transactionSequence = 0,
	}
	local requestCounter = 0
	local trackerResult = (newTrackerForTests :: ClientRequestTracker.TestConstructor)(
		ProductionRemotes,
		"Match",
		function(): string
			requestCounter += 1
			return `play{string.format("%04d", requestCounter)}`
		end
	)
	if not trackerResult.ok then
		error("playable tracker fixture failed", 0)
	end

	local function requestEndpoint(name: string): any
		local definition = ProductionRemotes:get(name)
		local response = makeSignal(rig)
		rig.responses[name] = response
		rig.fires[name] = {}
		return {
			definition = definition,
			connectResponse = function(listener)
				return response:connect(listener)
			end,
			fire = function(envelope)
				table.insert(rig.fires[name], envelope)
			end,
		}
	end

	local function eventEndpoint(name: string): any
		local definition = ProductionRemotes:get(name)
		local event = makeSignal(rig)
		rig.events[name] = event
		return {
			definition = definition,
			connectEvent = function(listener)
				return event:connect(listener)
			end,
		}
	end

	local dependencies: any = {
		localUserId = localUserId or 42,
		tracker = trackerResult.value,
		getSnapshot = requestEndpoint(PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT),
		submitReady = requestEndpoint(PlayableMatchProtocol.ENDPOINTS.SUBMIT_READY),
		submitPlacement = requestEndpoint(PlayableMatchProtocol.ENDPOINTS.SUBMIT_PLACEMENT),
		submitUpgrade = requestEndpoint(PlayableMatchProtocol.ENDPOINTS.SUBMIT_UPGRADE),
		submitSell = requestEndpoint(PlayableMatchProtocol.ENDPOINTS.SUBMIT_SELL),
		submitTargetMode = requestEndpoint(PlayableMatchProtocol.ENDPOINTS.SUBMIT_TARGET_MODE),
		submitReplay = requestEndpoint(PlayableMatchProtocol.ENDPOINTS.SUBMIT_REPLAY),
		getTravelSnapshot = requestEndpoint(MatchTravelProtocol.ENDPOINTS.GET_SNAPSHOT),
		requestReturn = requestEndpoint(MatchTravelProtocol.ENDPOINTS.REQUEST_RETURN),
		voteRematch = requestEndpoint(MatchTravelProtocol.ENDPOINTS.VOTE_REMATCH),
		replicationEvent = eventEndpoint(PlayableMatchProtocol.ENDPOINTS.REPLICATION),
		attackEvent = eventEndpoint(PlayableMatchProtocol.ENDPOINTS.ATTACK_EVENT),
		travelReplicationEvent = eventEndpoint(MatchTravelProtocol.ENDPOINTS.REPLICATION),
		view = {
			render = function(_self, value)
				table.insert(rig.renders, value)
				rig.viewInputFamily = value.inputFamily
				if rig.renderFailuresRemaining > 0 then
					rig.renderFailuresRemaining -= 1
					return { ok = false, error = { code = "RENDER_FAILED" } }
				end
				return { ok = true, value = true }
			end,
			syncWorld = function(_self, value)
				table.insert(rig.worlds, value)
				return { ok = true, value = true }
			end,
			playAttackEffect = function(_self, value)
				table.insert(rig.effects, value)
				return { ok = true, value = true }
			end,
			getMetrics = function()
				return { inputFamily = rig.viewInputFamily }
			end,
			cleanup = function()
				rig.viewCleaned += 1
				return { ok = true, value = true }
			end,
		},
		input = {
			setContext = function(_self, value)
				table.insert(rig.contexts, value)
				return { ok = true, value = true }
			end,
			getHints = function()
				return { ok = true, value = "test hint" }
			end,
			getMetrics = function()
				return { preferredInput = rig.inputFamily }
			end,
			cleanup = function()
				rig.inputCleaned += 1
				return { ok = true, value = true }
			end,
		},
		connectWorldPointer = function(listener)
			rig.worldPointerListener = listener
			return RobloxAdapter.createConnection(function()
				rig.disconnectCount += 1
			end) :: RBXScriptConnection
		end,
		connectRenderStep = function(listener)
			rig.renderListener = listener
			return RobloxAdapter.createConnection(function()
				rig.disconnectCount += 1
			end) :: RBXScriptConnection
		end,
		now = function()
			return rig.clock
		end,
		getPointerPosition = function()
			return rig.pointer
		end,
		getViewportSize = function()
			return rig.viewport
		end,
		raycastPlacement = function(position)
			rig.raycastScreenPosition = position
			return rig.raycastPosition
		end,
		pickTower = function(_position, _towers, _family)
			return rig.pickedTowerId
		end,
		focusOverview = function()
			rig.overviewFocused += 1
			return true
		end,
		focusBase = function()
			rig.focused += 1
			return true
		end,
		focusSpectatorTarget = function(position)
			table.insert(rig.spectatorFocuses, position)
			return true
		end,
		restoreCamera = function()
			rig.restored += 1
		end,
		applySettings = function(settings)
			table.insert(rig.appliedSettings, settings)
		end,
		newTransactionId = function()
			rig.transactionSequence += 1
			return string.format("transaction:00000000-0000-4000-8000-%012d", rig.transactionSequence)
		end,
	}

	local controllerResult = (newControllerForTests :: PlayableMatchController.TestConstructor)(logger, dependencies)
	if not controllerResult.ok then
		error("playable controller fixture failed", 0)
	end
	rig.controller = controllerResult.value
	local service = controllerResult.value:getServiceDefinition()
	service.initialize()
	service.start()
	rig.service = service
	return rig
end

local function deliverInitial(rig: any, value: any)
	local endpoint = PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT
	local request = rig.fires[endpoint][1]
	if request == nil then
		error("initial playable Get missing", 0)
	end
	rig.responses[endpoint]:fire(successWire(request, value))
end

local function deliverTravel(rig: any, value: any)
	local endpoint = MatchTravelProtocol.ENDPOINTS.GET_SNAPSHOT
	local request = rig.fires[endpoint][1]
	if request == nil then
		error("initial Match travel Get missing", 0)
	end
	rig.responses[endpoint]:fire(successWire(request, value))
end

local function cleanupRig(rig: any)
	if rig.controller:getState() ~= "Shutdown" then
		rig.service.shutdown()
	end
end

return TestHarness.suite("playable Match production client controller", {
	TestHarness.case("registers listeners before one initial owner-private snapshot request", function(assertions)
		local rig = makeRig()
		assertions.equal(#rig.fires[PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT], 1)
		assertions.equal(rig.controller:getMetrics().connectionCount, 15)
		assertions.equal(#rig.renders, 1)
		assertions.equal(rig.renders[1].state, "Loading")
		assertions.equal(rig.renders[1].inputHint, "Connecting to the authoritative match.")
		assertions.equal(#rig.worlds[1].towers, 0)
		assertions.equal(#rig.worlds[1].enemies, 0)
		local saved = snapshot(7)
		saved.settings.uiScale = 1.25
		saved.settings.reducedMotionEnabled = true
		saved.settings.enemyHealthBarsEnabled = false
		saved.settings.lowDetailEnabled = true
		saved.settings.towerRangeEnabled = false
		deliverInitial(rig, saved)
		local metrics = rig.controller:getMetrics()
		assertions.equal(metrics.matchId, "match:playable-controller")
		assertions.equal(metrics.revision, 7)
		assertions.equal(metrics.acceptedSnapshotCount, 1)
		assertions.equal(rig.overviewFocused, 1)
		assertions.equal(#rig.renders, 2)
		assertions.equal(rig.renders[2].battleCash, 245)
		assertions.equal(rig.renders[2].base.health, 27)
		assertions.equal(rig.renders[2].wave.enemiesRemaining, 1)
		assertions.equal(#rig.worlds[2].towers, 1)
		assertions.equal(#rig.worlds[2].enemies, 1)
		assertions.equal(rig.worlds[2].towers[1].level, 2)
		assertions.equal(rig.worlds[2].towers[1].range, 27)
		assertions.equal(rig.renders[2].uiScale, 1.25)
		assertions.isTrue(rig.renders[2].reducedMotion)
		assertions.isTrue(rig.renders[2].lowEffects)
		assertions.isFalse(rig.renders[2].enemyHealthBars)
		assertions.isFalse(rig.renders[2].towerRange)
		assertions.equal(#rig.appliedSettings, 1)
		assertions.equal(rig.appliedSettings[1].uiScale, 1.25)
		cleanupRig(rig)
	end),

	TestHarness.case(
		"reflows the current snapshot exactly once after the device viewport settles",
		function(assertions)
			local rig = makeRig()
			local renderListener = rig.renderListener :: any
			deliverInitial(rig, snapshot(7))
			assertions.equal(#rig.renders, 2)
			assertions.equal(rig.renders[2].viewport, Vector2.new(1280, 720))

			rig.viewport = Vector2.new(750, 361)
			renderListener(0.1)
			assertions.equal(#rig.renders, 3)
			assertions.equal(rig.renders[3].viewport, Vector2.new(750, 361))
			renderListener(0.1)
			assertions.equal(#rig.renders, 3)
			cleanupRig(rig)
		end
	),

	TestHarness.case("omits a zero Studio viewport so the view can use its safe fallback", function(assertions)
		local rig = makeRig()
		rig.viewport = Vector2.zero
		deliverInitial(rig, snapshot(7))
		assertions.isNil(rig.renders[#rig.renders].viewport)
		assertions.equal(rig.controller:getMetrics().acceptedSnapshotCount, 1)
		assertions.equal(rig.controller:getMetrics().renderCount, 2)
		assertions.equal(rig.controller:getMetrics().rejectedInputCount, 0)
		cleanupRig(rig)
	end),

	TestHarness.case("keeps an actionable Loading HUD through initial rejection and timeout", function(assertions)
		local endpoint = PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT

		local rejected = makeRig()
		local rejectedRequest = rejected.fires[endpoint][1]
		rejected.responses[endpoint]:fire(rejectedWire(rejectedRequest, "UNAVAILABLE"))
		assertions.equal(rejected.controller:getMetrics().feedbackCode, "SERVER_UNAVAILABLE")
		assertions.equal(rejected.renders[#rejected.renders].state, "Loading")
		assertions.equal(rejected.renders[#rejected.renders].feedback.code, "SERVER_UNAVAILABLE")
		assertions.equal(#rejected.fires[endpoint], 2)
		cleanupRig(rejected)

		local timedOut = makeRig()
		local renderListener = timedOut.renderListener :: any
		timedOut.clock += PlayableMatchController.REQUEST_TIMEOUT_SECONDS + 0.1
		renderListener(0.1)
		assertions.equal(timedOut.controller:getMetrics().feedbackCode, "SERVER_UNAVAILABLE")
		assertions.equal(timedOut.renders[#timedOut.renders].state, "Loading")
		assertions.equal(timedOut.renders[#timedOut.renders].feedback.code, "SERVER_UNAVAILABLE")
		assertions.equal(#timedOut.fires[endpoint], 2)
		cleanupRig(timedOut)
	end),

	TestHarness.case(
		"retries a failed render from an exact duplicate without recounting or chaining recovery",
		function(assertions)
			local rig = makeRig()
			local renderListener = rig.renderListener :: any
			rig.renderFailuresRemaining = 1
			local authoritative = snapshot(7)
			deliverInitial(rig, authoritative)
			assertions.equal(rig.controller:getMetrics().acceptedSnapshotCount, 1)
			assertions.equal(rig.controller:getMetrics().renderCount, 1)

			rig.clock += PlayableMatchController.RECOVERY_SILENCE_SECONDS + 0.1
			renderListener(0.1)
			local endpoint = PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT
			assertions.equal(#rig.fires[endpoint], 2)
			rig.events[PlayableMatchProtocol.ENDPOINTS.REPLICATION]:fire({ payload = {} })
			local rejectedBeforeDuplicate = rig.controller:getMetrics().rejectedInputCount
			rig.clock += PlayableMatchController.RECOVERY_SILENCE_SECONDS + 0.1
			local recovered = snapshot(7)
			recovered.serverTime = authoritative.serverTime + 10
			rig.responses[endpoint]:fire(successWire(rig.fires[endpoint][2], recovered))

			local metrics = rig.controller:getMetrics()
			assertions.equal(metrics.acceptedSnapshotCount, 1)
			assertions.equal(metrics.rejectedInputCount, rejectedBeforeDuplicate)
			assertions.equal(metrics.renderCount, 2)
			assertions.equal(metrics.recoveryRequestCount, 1)
			assertions.equal(#rig.renders, 3)
			assertions.equal(#rig.fires[endpoint], 2)
			renderListener(0.1)
			renderListener(0.1)
			assertions.equal(#rig.fires[endpoint], 2)
			cleanupRig(rig)
		end
	),

	TestHarness.case(
		"turns hotbar and pointer confirm into an exact placement intent then recovers",
		function(assertions)
			local rig = makeRig()
			deliverInitial(rig, snapshot(7))
			assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
				kind = "SelectHotbar",
				source = "Desktop",
				slot = 1,
			}))
			assertions.equal(rig.controller:getMetrics().selectedSlot, 1)
			assertions.equal(rig.contexts[#rig.contexts], "Placement")
			assertions.equal(rig.renders[#rig.renders].hotbar[1].description, "Place Dart Ant.")
			assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
				kind = "Rotate",
				source = "Desktop",
			}))
			assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
				kind = "Confirm",
				source = "Desktop",
				screenPosition = Vector2.new(80, 90),
			}))

			local endpoint = PlayableMatchProtocol.ENDPOINTS.SUBMIT_PLACEMENT
			assertions.equal(#rig.fires[endpoint], 1)
			local request = rig.fires[endpoint][1]
			assertions.equal(request.payload.matchId, "match:playable-controller")
			assertions.equal(request.payload.loadoutRevision, 6)
			assertions.equal(request.payload.slot, 1)
			assertions.equal(request.payload.towerId, "tower:dart-ant")
			assertions.equal(request.payload.position, Vector3.new(8, 0, 9))
			assertions.equal(request.payload.rotationDegrees, 15)
			assertions.isNil(request.payload.damage)
			rig.responses[endpoint]:fire(successWire(request, {
				accepted = true,
				reason = "Accepted",
				matchId = "match:playable-controller",
				revision = 8,
				battleCash = 125,
			}))
			assertions.equal(rig.controller:getMetrics().feedbackCode, "REQUEST_ACCEPTED")
			assertions.isNil(rig.controller:getMetrics().selectedSlot)
			assertions.equal(#rig.fires[PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT], 2)
			cleanupRig(rig)
		end
	),

	TestHarness.case("centers keyboard placement when the pointer is outside the viewport", function(assertions)
		local rig = makeRig()
		deliverInitial(rig, snapshot(7))
		rig.pointer = Vector2.new(-63, -21)
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "SelectHotbar",
			source = "Desktop",
			slot = 1,
		}))
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "Confirm",
			source = "Desktop",
		}))
		assertions.equal(rig.raycastScreenPosition, rig.viewport * 0.5)
		assertions.equal(#rig.fires[PlayableMatchProtocol.ENDPOINTS.SUBMIT_PLACEMENT], 1)
		cleanupRig(rig)
	end),

	TestHarness.case("uses the current desktop pointer for a positionless keyboard confirm", function(assertions)
		local rig = makeRig()
		deliverInitial(rig, snapshot(7))
		rig.pointer = Vector2.new(420, 360)
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "SelectHotbar",
			source = "Desktop",
			slot = 1,
		}))
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "Confirm",
			source = "Desktop",
		}))
		assertions.equal(rig.raycastScreenPosition, rig.pointer)
		assertions.equal(#rig.fires[PlayableMatchProtocol.ENDPOINTS.SUBMIT_PLACEMENT], 1)
		cleanupRig(rig)
	end),

	TestHarness.case("stages touch placement locally until one explicit confirm", function(assertions)
		local rig = makeRig()
		deliverInitial(rig, snapshot(7))
		rig.inputFamily = "Touch"
		(rig.renderListener :: any)(0.1)
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "SelectHotbar",
			source = "Touch",
			slot = 1,
		}))

		local endpoint = PlayableMatchProtocol.ENDPOINTS.SUBMIT_PLACEMENT
		local invokePointer = invokePointerForTests :: any
		invokePointer(rig.controller, Vector2.new(80, 90), "Touch")
		assertions.equal(#rig.fires[endpoint], 0)
		assertions.isTrue(rig.controller:getMetrics().touchPlacementSelected)
		assertions.equal(rig.controller:getMetrics().feedbackCode, "POSITION_SELECTED")
		assertions.isTrue(rig.renders[#rig.renders].placement.positionSelected)

		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "Rotate",
			source = "Touch",
		}))
		assertions.equal(#rig.fires[endpoint], 0)
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "Confirm",
			source = "Touch",
		}))
		assertions.equal(#rig.fires[endpoint], 1)
		assertions.equal(rig.fires[endpoint][1].payload.position, rig.raycastPosition)
		assertions.equal(rig.fires[endpoint][1].payload.rotationDegrees, 15)
		assertions.isFalse((invokeActionForTests :: any)(rig.controller, {
			kind = "Confirm",
			source = "Touch",
		}))
		assertions.equal(#rig.fires[endpoint], 1)
		cleanupRig(rig)
	end),

	TestHarness.case(
		"selects a world tower and sends owner mutation with its observed tower revision",
		function(assertions)
			local rig = makeRig()
			local invokePointer = invokePointerForTests :: any
			deliverInitial(rig, snapshot(7))
			invokePointer(rig.controller, Vector2.new(300, 200), "Touch")
			assertions.equal(rig.controller:getMetrics().selectedTowerId, 1)
			assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
				kind = "Cancel",
				source = "Touch",
			}))
			assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
				kind = "CycleTower",
				source = "Gamepad",
				direction = 1,
			}))
			assertions.equal(rig.controller:getMetrics().selectedTowerId, 1)
			assertions.equal(rig.contexts[#rig.contexts], "Tower")
			assertions.equal(rig.renders[#rig.renders].selection.revision, 4)
			assertions.equal(rig.renders[#rig.renders].selection.description, "Place Dart Ant.")
			assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
				kind = "Upgrade",
				source = "Gamepad",
			}))
			local endpoint = PlayableMatchProtocol.ENDPOINTS.SUBMIT_UPGRADE
			local request = rig.fires[endpoint][1]
			assertions.equal(request.payload.runtimeTowerId, 1)
			assertions.equal(request.payload.towerRevision, 4)
			assertions.isNil(request.payload.damage)
			cleanupRig(rig)
		end
	),

	TestHarness.case("keeps a negative Studio UserId aligned with authoritative tower ownership", function(assertions)
		local rig = makeRig(-3)
		local direct = snapshot(7)
		direct.towers[1].ownerUserId = -3
		deliverInitial(rig, direct)
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "CycleTower",
			source = "Gamepad",
			direction = 1,
		}))
		assertions.equal(rig.controller:getMetrics().selectedTowerId, 1)
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "Upgrade",
			source = "Gamepad",
		}))
		local requests = rig.fires[PlayableMatchProtocol.ENDPOINTS.SUBMIT_UPGRADE]
		assertions.equal(#requests, 1)
		assertions.equal(requests[1].payload.runtimeTowerId, 1)
		assertions.equal(requests[1].payload.towerRevision, 4)
		cleanupRig(rig)
		assertions.equal(rig.viewCleaned, 1)
		assertions.equal(rig.inputCleaned, 1)
	end),

	TestHarness.case(
		"accepts full replication and presents compact attacks only for the current match",
		function(assertions)
			local rig = makeRig()
			deliverInitial(rig, snapshot(7))
			local nextSnapshot = snapshot(8)
			nextSnapshot.battleCash = 300
			rig.events[PlayableMatchProtocol.ENDPOINTS.REPLICATION]:fire({ payload = nextSnapshot })
			assertions.equal(rig.controller:getMetrics().revision, 8)
			assertions.equal(rig.renders[#rig.renders].battleCash, 300)

			rig.events[PlayableMatchProtocol.ENDPOINTS.ATTACK_EVENT]:fire({
				payload = {
					matchId = "match:playable-controller",
					sequence = 1,
					runtimeTowerId = 1,
					runtimeEnemyId = 3,
					sourcePosition = Vector3.new(4, 1, 7),
					targetPosition = Vector3.new(-8, 2, 3),
					actualDamage = 12,
					killed = false,
					serverTime = 111,
				},
			})
			assertions.equal(#rig.effects, 1)
			assertions.equal(rig.effects[1].towerId, "tower-runtime:1")
			assertions.equal(rig.effects[1].targetId, "enemy-runtime:3")
			assertions.equal(rig.effects[1].damage, 12)
			assertions.equal(rig.controller:getMetrics().attackEventCount, 1)

			local muted = snapshot(9)
			muted.settings.otherPlayerEffectsEnabled = false
			muted.towers[1].ownerUserId = 99
			rig.events[PlayableMatchProtocol.ENDPOINTS.REPLICATION]:fire({ payload = muted })
			rig.events[PlayableMatchProtocol.ENDPOINTS.ATTACK_EVENT]:fire({
				payload = {
					matchId = "match:playable-controller",
					sequence = 2,
					runtimeTowerId = 1,
					runtimeEnemyId = 3,
					sourcePosition = Vector3.new(4, 1, 7),
					targetPosition = Vector3.new(-8, 2, 3),
					actualDamage = 8,
					killed = false,
					serverTime = 112,
				},
			})
			assertions.equal(#rig.effects, 1)
			assertions.equal(rig.controller:getMetrics().attackEventCount, 1)
			cleanupRig(rig)
		end
	),

	TestHarness.case("retires tower selection before presenting authoritative Results", function(assertions)
		local rig = makeRig()
		deliverInitial(rig, snapshot(7))
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "CycleTower",
			source = "Gamepad",
			direction = 1,
		}))
		assertions.equal(rig.controller:getMetrics().selectedTowerId, 1)

		local results = snapshot(8, "Results")
		results.towers = snapshot(7).towers
		rig.events[PlayableMatchProtocol.ENDPOINTS.REPLICATION]:fire({ payload = results })

		assertions.equal(rig.controller:getMetrics().revision, 8)
		assertions.isNil(rig.controller:getMetrics().selectedTowerId)
		assertions.equal(rig.renders[#rig.renders].state, "Results")
		assertions.equal(rig.renders[#rig.renders].result.kind, "Victory")
		assertions.equal(rig.renders[#rig.renders].result.rewardStatus, "Ineligible")
		assertions.isTrue(rig.renders[#rig.renders].result.canReplay)
		assertions.isNil(rig.renders[#rig.renders].selection)
		cleanupRig(rig)
	end),

	TestHarness.case("projects authoritative Endless and boss state without a fake wave total", function(assertions)
		local rig = makeRig()
		local active = snapshot(7)
		active.modeKind = "Endless"
		active.totalWaves = nil
		active.contentVersion = 1
		active.seed = 4_242
		active.waveNumber = 317
		active.bossKind = "Boss"
		active.tutorialStep = 5
		active.enemies[1].enemyId = "enemy:queen-ant"
		active.enemies[1].displayName = "Queen Ant"
		active.enemies[1].currentHealth = 2_500
		active.enemies[1].maximumHealth = 10_000
		active.enemies[1].threatClass = "Boss"
		active.boss = {
			runtimeEnemyId = 3,
			displayName = "Queen Ant",
			currentHealth = 2_500,
			maximumHealth = 10_000,
			threatClass = "Boss",
		}
		deliverInitial(rig, active)
		local rendered = rig.renders[#rig.renders]
		assertions.equal(rendered.wave.modeKind, "Endless")
		assertions.isNil(rendered.wave.total)
		assertions.equal(rendered.wave.bossKind, "Boss")
		assertions.equal(rendered.wave.boss.displayName, "Queen Ant")
		assertions.equal(rendered.tutorialStep, 5)

		local results = snapshot(8, "Results")
		results.modeKind = "Endless"
		results.totalWaves = nil
		results.contentVersion = 1
		results.seed = 4_242
		results.bossKind = "None"
		results.tutorialStep = 8
		results.result = "Defeat"
		results.waveNumber = 317
		results.stats.wavesCompleted = 317
		rig.events[PlayableMatchProtocol.ENDPOINTS.REPLICATION]:fire({ payload = results })
		rendered = rig.renders[#rig.renders]
		assertions.isNil(rendered.wave.total)
		assertions.contains(rendered.result.summary, "Endless")
		assertions.contains(rendered.result.summary, "317 waves cleared")
		assertions.equal(rendered.tutorialStep, 8)
		cleanupRig(rig)
	end),

	TestHarness.case(
		"replaces replay state cleanly for response-first and replication-first orderings",
		function(assertions)
			local replayEndpoint = PlayableMatchProtocol.ENDPOINTS.SUBMIT_REPLAY
			local getEndpoint = PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT

			local responseFirst = makeRig()
			deliverInitial(responseFirst, snapshot(7, "Results"))
			assertions.isTrue((invokeActionForTests :: any)(responseFirst.controller, {
				kind = "Replay",
				source = "Gamepad",
			}))
			local replayRequest = responseFirst.fires[replayEndpoint][1]
			responseFirst.responses[replayEndpoint]:fire(successWire(replayRequest, {
				accepted = true,
				reason = "Accepted",
				matchId = "match:playable-controller",
				revision = 8,
				battleCash = 245,
			}))
			assertions.isFalse(responseFirst.controller:getMetrics().actionPending)
			assertions.equal(#responseFirst.fires[getEndpoint], 2)
			local recoveryRequest = responseFirst.fires[getEndpoint][2]
			responseFirst.responses[getEndpoint]:fire(successWire(recoveryRequest, replayReplacement()))
			assertions.equal(responseFirst.controller:getMetrics().matchId, "match:playable-replacement")
			assertions.equal(responseFirst.controller:getMetrics().matchGeneration, 1)
			assertions.equal(responseFirst.overviewFocused, 2)
			responseFirst.events[PlayableMatchProtocol.ENDPOINTS.REPLICATION]:fire({ payload = snapshot(9, "Results") })
			assertions.equal(responseFirst.controller:getMetrics().matchId, "match:playable-replacement")
			assertions.equal(responseFirst.overviewFocused, 2)
			cleanupRig(responseFirst)

			local replicationFirst = makeRig()
			deliverInitial(replicationFirst, snapshot(7, "Results"))
			assertions.isTrue((invokeActionForTests :: any)(replicationFirst.controller, {
				kind = "Replay",
				source = "Desktop",
			}))
			local lateRequest = replicationFirst.fires[replayEndpoint][1]
			replicationFirst.events[PlayableMatchProtocol.ENDPOINTS.REPLICATION]:fire({ payload = replayReplacement() })
			assertions.isFalse(replicationFirst.controller:getMetrics().actionPending)
			assertions.equal(replicationFirst.controller:getMetrics().matchGeneration, 1)
			assertions.equal(replicationFirst.overviewFocused, 2)
			replicationFirst.responses[replayEndpoint]:fire(successWire(lateRequest, {
				accepted = true,
				reason = "Accepted",
				matchId = "match:playable-controller",
				revision = 8,
				battleCash = 245,
			}))
			assertions.equal(replicationFirst.controller:getMetrics().matchId, "match:playable-replacement")
			assertions.isFalse(replicationFirst.controller:getMetrics().actionPending)
			cleanupRig(replicationFirst)
		end
	),

	TestHarness.case(
		"renders durable rewards and sends revision-bound return and rematch intents",
		function(assertions)
			local rig = makeRig()
			local results = snapshot(7, "Results")
			results.rewarding = true
			results.reward = {
				resultId = "result:controller-ticketed",
				status = "Granted",
				persistentGoldAwarded = 500,
				firstClearBonus = 250,
				battleCashEarned = 76,
				battleCashSpent = 230,
				reason = "Claimed",
			}
			deliverInitial(rig, results)
			deliverTravel(rig, travelSnapshot(1))
			local rendered = rig.renders[#rig.renders]
			assertions.equal(rendered.result.rewardStatus, "Granted")
			assertions.equal(rendered.result.persistentGoldAwarded, 500)
			assertions.equal(rendered.result.firstClearBonus, 250)
			assertions.equal(rendered.result.battleCashEarned, 76)
			assertions.isFalse(rendered.result.canReplay)
			assertions.isTrue(rendered.travel.canReturn)
			assertions.isTrue(rendered.travel.canApprove)

			assertions.isTrue((invokeActionForTests :: any)(rig.controller, { kind = "Return", source = "Touch" }))
			local returnEndpoint = MatchTravelProtocol.ENDPOINTS.REQUEST_RETURN
			local returnRequest = rig.fires[returnEndpoint][1]
			assertions.equal(returnRequest.payload.matchId, results.matchId)
			assertions.equal(returnRequest.payload.observedRevision, 1)
			assertions.equal(returnRequest.payload.transactionId, "transaction:00000000-0000-4000-8000-000000000001")
			assertions.isNil(returnRequest.payload.ticketId)
			local returned = travelSnapshot(2)
			returned.returnStatus = "Pending"
			rig.responses[returnEndpoint]:fire(successWire(returnRequest, {
				transactionId = returnRequest.payload.transactionId,
				changed = true,
				snapshot = returned,
			}))
			assertions.isFalse(rig.controller:getMetrics().travelMutationPending)

			assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
				kind = "RematchApprove",
				source = "Gamepad",
			}))
			local rematchRequest = rig.fires[MatchTravelProtocol.ENDPOINTS.VOTE_REMATCH][1]
			assertions.isTrue(rematchRequest.payload.approve)
			assertions.equal(rematchRequest.payload.observedRevision, 2)
			assertions.equal(rematchRequest.payload.observedRematchRevision, 2)
			assertions.isNil(rematchRequest.payload.roster)
			cleanupRig(rig)
		end
	),

	TestHarness.case("keeps a starting rematch non-actionable while the server creates it", function(assertions)
		local rig = makeRig()
		local results = snapshot(7, "Results")
		results.rewarding = true
		results.reward = {
			resultId = "result:controller-rematch-starting",
			status = "Granted",
			persistentGoldAwarded = 250,
			firstClearBonus = 0,
			battleCashEarned = 76,
			battleCashSpent = 230,
			reason = "Claimed",
		}
		deliverInitial(rig, results)
		local starting = travelSnapshot(2)
		starting.rematch.state = "Starting"
		starting.rematch.votes[1].choice = "Approve"
		deliverTravel(rig, starting)

		local rendered = rig.renders[#rig.renders]
		assertions.equal(rendered.travel.rematchState, "Starting")
		assertions.isFalse(rendered.travel.canReturn)
		assertions.isFalse(rendered.travel.canApprove)
		assertions.isFalse(rendered.travel.canDecline)
		assertions.isFalse((invokeActionForTests :: any)(rig.controller, { kind = "Return", source = "Touch" }))
		assertions.isFalse((invokeActionForTests :: any)(rig.controller, {
			kind = "RematchApprove",
			source = "Gamepad",
		}))

		local approved = travelSnapshot(3)
		approved.rematch.state = "Approved"
		approved.rematch.votes[1].choice = "Approve"
		deliverTravel(rig, approved)
		rendered = rig.renders[#rig.renders]
		assertions.isFalse(rendered.travel.canReturn)
		assertions.isFalse((invokeActionForTests :: any)(rig.controller, { kind = "Return", source = "Keyboard" }))
		assertions.equal(#rig.fires[MatchTravelProtocol.ENDPOINTS.REQUEST_RETURN], 0)
		assertions.equal(#rig.fires[MatchTravelProtocol.ENDPOINTS.VOTE_REMATCH], 0)
		cleanupRig(rig)
	end),

	TestHarness.case("keeps spectators read-only while cycling bounded live camera targets", function(assertions)
		local rig = makeRig()
		local spectator = snapshot(7, "Results")
		spectator.viewerRole = "Spectator"
		spectator.rewarding = true
		spectator.loadoutRevision = 0
		spectator.battleCash = 0
		table.clear(spectator.towerOptions)
		spectator.towers = snapshot(7).towers
		spectator.stats.damageDealt = 0
		spectator.stats.battleCashEarned = 0
		spectator.stats.battleCashSpent = 0
		spectator.stats.placements = 0
		spectator.stats.upgrades = 0
		spectator.stats.sells = 0
		spectator.reward = {
			resultId = "result:controller-spectator",
			status = "Pending",
			persistentGoldAwarded = 0,
			firstClearBonus = 0,
			battleCashEarned = 0,
			battleCashSpent = 0,
			reason = "ClaimPending",
		}
		deliverInitial(rig, spectator)
		deliverTravel(rig, travelSnapshot(1, "Spectator"))
		assertions.equal(rig.renders[#rig.renders].viewerRole, "Spectator")
		assertions.equal(rig.renders[#rig.renders].result.rewardStatus, "Pending")
		assertions.isFalse(rig.renders[#rig.renders].travel.canApprove)
		assertions.isFalse((invokeActionForTests :: any)(rig.controller, { kind = "Ready", source = "Desktop" }))
		assertions.equal(#rig.fires[PlayableMatchProtocol.ENDPOINTS.SUBMIT_READY], 0)
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "SpectateNext",
			source = "Gamepad",
		}))
		assertions.equal(#rig.spectatorFocuses, 1)
		assertions.equal(rig.controller:getMetrics().spectatorTargetId, "tower:1")

		local noTargets = table.clone(spectator)
		noTargets.revision = 8
		noTargets.towers = {}
		rig.events[PlayableMatchProtocol.ENDPOINTS.REPLICATION]:fire({ payload = noTargets })
		assertions.isNil(rig.controller:getMetrics().spectatorTargetId)
		assertions.isFalse((invokeActionForTests :: any)(rig.controller, {
			kind = "SpectateNext",
			source = "Touch",
		}))
		cleanupRig(rig)
	end),

	TestHarness.case("times out a missing action receipt and recovers authoritative state", function(assertions)
		local rig = makeRig()
		local renderListener = rig.renderListener :: any
		deliverInitial(rig, snapshot(7))
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "SelectHotbar",
			source = "Desktop",
			slot = 1,
		}))
		assertions.isTrue((invokeActionForTests :: any)(rig.controller, {
			kind = "Confirm",
			source = "Desktop",
			screenPosition = Vector2.new(80, 90),
		}))
		rig.clock += PlayableMatchController.REQUEST_TIMEOUT_SECONDS + 0.1
		renderListener(0.1)
		local metrics = rig.controller:getMetrics()
		assertions.isFalse(metrics.actionPending)
		assertions.equal(metrics.feedbackCode, "SERVER_UNAVAILABLE")
		assertions.equal(#rig.fires[PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT], 2)
		cleanupRig(rig)
	end),

	TestHarness.case("periodically recovers silence and shuts down all owned client state", function(assertions)
		local rig = makeRig()
		local renderListener = rig.renderListener :: any
		deliverInitial(rig, snapshot(7))
		rig.clock += PlayableMatchController.RECOVERY_SILENCE_SECONDS + 0.1
		renderListener(0.1)
		assertions.equal(#rig.fires[PlayableMatchProtocol.ENDPOINTS.GET_SNAPSHOT], 2)
		assertions.equal(rig.controller:getMetrics().recoveryRequestCount, 1)
		rig.service.shutdown()
		assertions.equal(rig.controller:getState(), "Shutdown")
		assertions.equal(rig.controller:getMetrics().connectionCount, 0)
		assertions.equal(rig.viewCleaned, 1)
		assertions.equal(rig.inputCleaned, 1)
		assertions.equal(rig.restored, 1)
		assertions.equal(rig.disconnectCount, 15)
		assertions.isTrue(rig.service.shutdown == rig.service.shutdown)
	end),
})
