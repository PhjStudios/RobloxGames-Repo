--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local MatchLoadoutProtocol = require(ReplicatedStorage.Shared.match.MatchLoadoutProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)

local PlayableMatchService = require(script.Parent.Parent.ProductionServerPlayable.PlayableMatchService)

type Assertions = TestHarness.Assertions

local logger = Log.new(EnvironmentContext.new("server", "Match", 0, false))
local loaded = ConfigurationValidator.validateLoaded()
if not loaded.ok then
	error("expected loaded production configuration", 0)
end
local CONFIGURATION = loaded.value
local newForTests = PlayableMatchService.newForTests
if newForTests == nil then
	error("expected PlayableMatchService test constructor", 0)
end

local function frozenLoadout(userId: number, settingsOverride: any?): MatchLoadoutProtocol.Snapshot
	local slots = {}
	for index, definition in CONFIGURATION.towers.ordered do
		if index > MatchLoadoutProtocol.MAX_SLOTS then
			break
		end
		table.insert(slots, {
			slot = index,
			unitId = `unit:ticket-{userId}-{index}`,
			towerId = definition.id,
		})
	end
	local validated = MatchLoadoutProtocol.validate({
		userId = userId,
		revision = 7,
		slots = slots,
		settings = settingsOverride or CONFIGURATION.defaultSettings,
	}, CONFIGURATION)
	if not validated.ok then
		error("expected valid frozen loadout", 0)
	end
	return validated.value
end

local function runtimeMap(mapId: string?): any
	local first = Vector3.new(-1, 0, 0)
	local last = Vector3.new(1, 0, 0)
	return {
		mapId = mapId or "map:phase07-graybox",
		base = { cframe = CFrame.new(last), position = last },
		bounds = { cframe = CFrame.new(), size = Vector3.new(100, 20, 100) },
		lanes = {
			{
				id = "main",
				totalDistance = 2,
				points = {
					{ kind = "Path", nodeOrder = 1, cframe = CFrame.new(first), position = first, distance = 0 },
					{ kind = "Path", nodeOrder = 2, cframe = CFrame.new(last), position = last, distance = 2 },
				},
			},
		},
		placementZones = {
			{ id = "land", cframe = CFrame.new(0, -1, 0), size = Vector3.new(80, 2, 80) },
		},
		noPlacementZones = {},
		cameraAnchors = {},
		playerSpawns = {},
	}
end

local function contentRoot(): Folder
	local root = Instance.new("Folder")
	local catalog = Instance.new("Folder")
	catalog.Name = "ATDPlayableTemplates"
	catalog:SetAttribute("ATDContentContract", "playable-local-match-v1")
	catalog:SetAttribute("ContentVersion", 1)
	catalog.Parent = root
	local function model(assetKey: string, kind: string, definitionId: string)
		local value = Instance.new("Model")
		value.Name = assetKey
		value:SetAttribute("ATDContentContract", "playable-local-match-v1")
		value:SetAttribute("AssetKey", assetKey)
		value:SetAttribute("ContentKind", kind)
		value:SetAttribute("DefinitionId", definitionId)
		local part = Instance.new("Part")
		part.Name = "Root"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Parent = value
		value.PrimaryPart = part
		value.Parent = catalog
	end
	for _, definition in CONFIGURATION.towers.ordered do
		model(definition.modelAssetKey, "TowerModel", definition.id)
	end
	for _, definition in CONFIGURATION.enemies.ordered do
		model(definition.modelAssetKey, "EnemyModel", definition.id)
	end
	return root
end

local function fakePlayer(name: string): Player
	local player = Instance.new("Player") :: Player
	player.Name = name
	return player
end

local function removeActive(active: { Player }, player: Player)
	for index, candidate in active do
		if candidate == player then
			table.remove(active, index)
			return
		end
	end
end

local function makeRig(
	extraContent: boolean?,
	rosterInputs: PlayableMatchService.RosterInputs?,
	directContentSelection: PlayableMatchService.DirectContentSelection?,
	isStudio: boolean?
): any
	local root = contentRoot()
	if extraContent then
		local catalog = root:FindFirstChild("ATDPlayableTemplates") :: Folder
		local duplicate = (catalog:GetChildren()[1] :: Model):Clone()
		duplicate.Parent = catalog
	end
	local addedCallback: ((Player) -> ())? = nil
	local removingCallback: ((Player) -> ())? = nil
	local heartbeatCallback: (() -> ())? = nil
	local function connection(disconnect: () -> ()): RBXScriptConnection
		return ({ Disconnect = disconnect } :: any) :: RBXScriptConnection
	end
	local first = fakePlayer("ServicePlayerOne")
	local second = fakePlayer("ServicePlayerTwo")
	local active: { Player } = { first }
	local ids: { [Player]: number } = { [first] = 101, [second] = 202 }
	local clock = 100
	local matchSequence = 0
	local publications = {}
	local legacyState = "WaveActive"
	local lifecycle: any = {}
	function lifecycle:getRuntimeMapSnapshot()
		local selectedMapId = if directContentSelection ~= nil
			then directContentSelection.mapId
			elseif rosterInputs == nil then nil
			else rosterInputs.mapId
		return Result.ok(runtimeMap(selectedMapId))
	end
	function lifecycle:getSnapshot()
		return Result.ok(table.freeze({ state = legacyState, matchId = "match:legacy", revision = 1 }))
	end
	function lifecycle:submitReady()
		return Result.ok(true)
	end
	function lifecycle:beginWaveActivation()
		return Result.ok(table.freeze({}))
	end
	function lifecycle:commitWaveActivation()
		legacyState = "WaveActive"
		return Result.ok(true)
	end
	function lifecycle:rollbackWaveActivation()
		return Result.ok(true)
	end
	function lifecycle:beginBaseDefeat()
		return Result.ok(table.freeze({}))
	end
	function lifecycle:commitBaseDefeat()
		legacyState = "Closing"
		return Result.ok(true)
	end
	function lifecycle:rollbackBaseDefeat()
		return Result.ok(true)
	end

	local environment: PlayableMatchService.Environment = {
		now = function()
			return clock
		end,
		generateMatchId = function()
			matchSequence += 1
			return `match:service-{matchSequence}` :: any
		end,
		getActivePlayers = function()
			return table.clone(active)
		end,
		getUserId = function(player)
			return ids[player]
		end,
		isActivePlayer = function(player)
			for _, candidate in active do
				if candidate == player then
					return true
				end
			end
			return false
		end,
		connectPlayerAdded = function(callback)
			addedCallback = callback
			return connection(function()
				addedCallback = nil
			end)
		end,
		connectPlayerRemoving = function(callback)
			removingCallback = callback
			return connection(function()
				removingCallback = nil
			end)
		end,
		connectHeartbeat = function(callback)
			heartbeatCallback = callback
			return connection(function()
				heartbeatCallback = nil
			end)
		end,
		contentRoot = root,
	}
	local service = (newForTests :: PlayableMatchService.TestConstructor)(
		logger,
		lifecycle,
		CONFIGURATION,
		function(_recipient, value)
			table.insert(publications, value)
			return true
		end,
		function()
			return true
		end,
		environment,
		nil,
		rosterInputs,
		directContentSelection,
		isStudio
	)
	return {
		service = service,
		definition = service:getServiceDefinition(),
		root = root,
		fireAdded = function(player: Player)
			(addedCallback :: (Player) -> ())(player)
		end,
		fireRemoving = function(player: Player)
			(removingCallback :: (Player) -> ())(player)
		end,
		fireHeartbeat = function()
			(heartbeatCallback :: () -> ())()
		end,
		active = active,
		first = first,
		second = second,
		bindPlayer = function(player: Player, userId: number)
			ids[player] = userId
		end,
		publications = publications,
		setClock = function(value: number)
			clock = value
		end,
		getClock = function()
			return clock
		end,
	}
end

local function startRig(rig: any)
	rig.definition.initialize()
	rig.definition.start()
end

local function cleanupRig(rig: any)
	if rig.service:getMetrics().state ~= "Shutdown" then
		rig.definition.shutdown()
	end
	rig.root:Destroy()
	rig.first:Destroy()
	rig.second:Destroy()
end

local function currentSnapshot(assertions: Assertions, rig: any, player: Player): any
	local result = rig.service:getSnapshot(player)
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected service snapshot", 0)
	end
	return result.value
end

local function ready(assertions: Assertions, rig: any, player: Player): string
	local initial = currentSnapshot(assertions, rig, player)
	local receipt = rig.service:submitReady(player, { matchId = initial.matchId })
	assertions.isNotNil(receipt)
	assertions.isTrue((receipt :: any).accepted)
	return initial.matchId
end

local function runToResults(assertions: Assertions, rig: any)
	for _ = 1, 1_000 do
		local runtime = rig.service:getMetrics().runtime
		if runtime ~= nil and runtime.state == "Results" then
			return
		end
		rig.setClock(rig.getClock() + 0.25)
		rig.fireHeartbeat()
	end
	assertions.isTrue(false)
end

return TestHarness.suite("playable match service integration", {
	TestHarness.case(
		"observes terminal heartbeat transitions once while failed observers leave gameplay intact",
		function(assertions)
			local rig = makeRig()
			local states = {}
			rig.service:setOutcomeObserver(function(metrics)
				states[metrics.state] = (states[metrics.state] or 0) + 1
				if metrics.state == "Playing" then
					coroutine.yield()
				elseif metrics.state == "Results" then
					error("unavailable observer")
				end
			end)
			startRig(rig)
			ready(assertions, rig, rig.first)
			runToResults(assertions, rig)
			assertions.equal(states.Results, 1)
			assertions.equal(states.Playing, 1)
			local result = rig.service:getMetrics().runtime.result
			rig.fireHeartbeat()
			rig.fireHeartbeat()
			assertions.equal(states.Results, 1)
			assertions.equal(rig.service:getMetrics().runtime.result, result)
			cleanupRig(rig)
		end
	),
	TestHarness.case("accepts the complete authenticated model catalog and rejects extras", function(assertions)
		local exact = makeRig()
		startRig(exact)
		assertions.equal(exact.service:getMetrics().state, "Started")
		assertions.equal(#exact.publications, 1)
		cleanupRig(exact)

		local extra = makeRig(true)
		local initialized = pcall(extra.definition.initialize)
		assertions.isFalse(initialized)
		assertions.equal(extra.service:getMetrics().state, "Failed")
		cleanupRig(extra)
	end),

	TestHarness.case(
		"runs an explicit direct selection through the same non-rewarding authority graph",
		function(assertions)
			local rig = makeRig(false, nil, {
				mapId = "map:backyard-garden-v1",
				difficultyId = "difficulty:easy-v1",
			})
			startRig(rig)
			local snapshot = currentSnapshot(assertions, rig, rig.first)
			assertions.equal(snapshot.mapId, "map:backyard-garden-v1")
			assertions.equal(snapshot.difficultyId, "difficulty:easy-v1")
			assertions.equal(snapshot.modeKind, "Finite")
			assertions.equal(snapshot.totalWaves, 20)
			assertions.isFalse(snapshot.rewarding)
			cleanupRig(rig)
		end
	),

	TestHarness.case("mints deterministic negative-id starters only for a direct Studio runtime", function(assertions)
		local selection = {
			mapId = "map:backyard-garden-v1",
			difficultyId = "difficulty:easy-v1",
		}
		local publishedBoundary = makeRig(false, nil, selection, false)
		publishedBoundary.bindPlayer(publishedBoundary.first, -1)
		startRig(publishedBoundary)
		local spectator = currentSnapshot(assertions, publishedBoundary, publishedBoundary.first)
		assertions.equal(spectator.viewerRole, "Spectator")
		assertions.equal(publishedBoundary.service:getMetrics().frozenLoadoutCount, 0)
		cleanupRig(publishedBoundary)

		local studio = makeRig(false, nil, selection, true)
		studio.bindPlayer(studio.first, -1)
		startRig(studio)
		local initial = currentSnapshot(assertions, studio, studio.first)
		assertions.equal(initial.viewerRole, "Participant")
		assertions.isFalse(initial.rewarding)
		assertions.equal(initial.loadoutRevision, 1)
		assertions.equal(#initial.towerOptions, 2)
		assertions.equal(initial.towerOptions[1].unitId, "unit:starter-1")
		assertions.equal(initial.towerOptions[1].towerId, "tower:dart-ant")
		assertions.equal(initial.towerOptions[2].unitId, "unit:starter-2")
		assertions.equal(initial.towerOptions[2].towerId, "tower:bombardier-ant")

		ready(assertions, studio, studio.first)
		local placed = studio.service:submitPlacement(studio.first, {
			matchId = initial.matchId,
			loadoutRevision = initial.loadoutRevision,
			slot = 1,
			towerId = "tower:dart-ant",
			position = Vector3.new(0, 0, 8),
			rotationDegrees = 0,
		})
		assertions.isNotNil(placed)
		assertions.isTrue((placed :: any).accepted)
		local afterPlacement = currentSnapshot(assertions, studio, studio.first)
		assertions.equal(afterPlacement.towers[1].ownerUserId, -1)

		removeActive(studio.active, studio.first)
		studio.fireRemoving(studio.first)
		assertions.equal((studio.service:getMetrics().runtime :: any).connectedParticipantCount, 0)
		table.insert(studio.active, studio.first)
		studio.fireAdded(studio.first)
		local reconnected = currentSnapshot(assertions, studio, studio.first)
		assertions.equal(reconnected.viewerRole, "Participant")
		assertions.equal(reconnected.towers[1].ownerUserId, -1)
		cleanupRig(studio)
		assertions.equal(studio.service:getMetrics().state, "Shutdown")
		assertions.equal(studio.service:getMetrics().frozenLoadoutCount, 0)
		assertions.isNil(studio.service:getMetrics().runtime)
	end),

	TestHarness.case("returns the old replay receipt while publishing the fresh Ready match", function(assertions)
		local rig = makeRig()
		startRig(rig)
		local oldMatchId = ready(assertions, rig, rig.first)
		runToResults(assertions, rig)
		local publicationCount = #rig.publications
		local receipt = rig.service:submitReplay(rig.first, { matchId = oldMatchId })
		assertions.isNotNil(receipt)
		assertions.isTrue((receipt :: any).accepted)
		assertions.equal((receipt :: any).matchId, oldMatchId)
		local replacement = currentSnapshot(assertions, rig, rig.first)
		assertions.notEqual(replacement.matchId, oldMatchId)
		assertions.equal(replacement.state, "Ready")
		assertions.equal(rig.service:getMetrics().generation, 2)
		assertions.equal(#rig.publications, publicationCount + 1)
		assertions.equal(rig.publications[#rig.publications].matchId, replacement.matchId)
		cleanupRig(rig)
	end),

	TestHarness.case(
		"retains a disconnected participant and makes late arrivals read-only spectators",
		function(assertions)
			local playing = makeRig()
			startRig(playing)
			ready(assertions, playing, playing.first)
			local playingSnapshot = currentSnapshot(assertions, playing, playing.first)
			local placed = playing.service:submitPlacement(playing.first, {
				matchId = playingSnapshot.matchId,
				loadoutRevision = playingSnapshot.loadoutRevision,
				slot = 1,
				towerId = "tower:dart-ant",
				position = Vector3.new(0, 0, 8),
				rotationDegrees = 0,
			})
			assertions.isTrue((placed :: any).accepted)
			removeActive(playing.active, playing.first)
			playing.fireRemoving(playing.first)
			assertions.equal(playing.service:getMetrics().frozenLoadoutCount, 1)
			assertions.equal((playing.service:getMetrics().runtime :: any).participantCount, 1)
			assertions.equal((playing.service:getMetrics().runtime :: any).connectedParticipantCount, 0)
			assertions.equal((playing.service:getMetrics().runtime :: any).activeTowerCount, 1)
			table.insert(playing.active, playing.second)
			playing.fireAdded(playing.second)
			local spectator = currentSnapshot(assertions, playing, playing.second)
			assertions.equal(spectator.viewerRole, "Spectator")
			assertions.equal(spectator.state, "Playing")
			assertions.equal(spectator.battleCash, 0)
			assertions.equal(#spectator.towerOptions, 0)
			assertions.equal(#spectator.towers, 1)
			local spectatorPlacement = playing.service:submitPlacement(playing.second, {
				matchId = spectator.matchId,
				loadoutRevision = 1,
				slot = 1,
				towerId = "tower:dart-ant",
				position = Vector3.new(4, 0, 8),
				rotationDegrees = 0,
			})
			assertions.isNotNil(spectatorPlacement)
			assertions.isFalse((spectatorPlacement :: any).accepted)
			assertions.equal((spectatorPlacement :: any).reason, "NotParticipant")
			assertions.equal(playing.service:getMetrics().generation, 1)
			assertions.isTrue(playing.service:getMetrics().publishPending)

			removeActive(playing.active, playing.second)
			playing.fireRemoving(playing.second)
			local replacementPlayer = fakePlayer("ServicePlayerOneReplacement")
			playing.bindPlayer(replacementPlayer, 101)
			table.insert(playing.active, replacementPlayer)
			playing.fireAdded(replacementPlayer)
			local rebound = currentSnapshot(assertions, playing, replacementPlayer)
			assertions.equal(rebound.viewerRole, "Participant")
			assertions.equal(rebound.matchId, playingSnapshot.matchId)
			assertions.equal(rebound.battleCash, 380)
			assertions.equal(rebound.stats.placements, 1)
			assertions.equal(#rebound.towers, 1)
			assertions.equal((playing.service:getMetrics().runtime :: any).participantCount, 1)
			assertions.equal((playing.service:getMetrics().runtime :: any).connectedParticipantCount, 1)
			removeActive(playing.active, replacementPlayer)
			playing.fireRemoving(replacementPlayer)
			replacementPlayer:Destroy()
			cleanupRig(playing)

			local results = makeRig()
			startRig(results)
			ready(assertions, results, results.first)
			runToResults(assertions, results)
			local directEvidence = results.service:getResultEvidence()
			assertions.isTrue(directEvidence.ok)
			assertions.isFalse((directEvidence :: any).value.rewardingMatch)
			assertions.equal(#(directEvidence :: any).value.entries, 1)
			removeActive(results.active, results.first)
			results.fireRemoving(results.first)
			assertions.equal(results.service:getMetrics().frozenLoadoutCount, 1)
			assertions.equal((results.service:getMetrics().runtime :: any).participantCount, 1)
			table.insert(results.active, results.second)
			results.fireAdded(results.second)
			local resultsSpectator = currentSnapshot(assertions, results, results.second)
			assertions.equal(resultsSpectator.viewerRole, "Spectator")
			assertions.equal(resultsSpectator.state, "Results")
			assertions.equal(results.service:getMetrics().generation, 1)
			removeActive(results.active, results.second)
			results.fireRemoving(results.second)
			table.insert(results.active, results.first)
			results.fireAdded(results.first)
			local resultsRebound = currentSnapshot(assertions, results, results.first)
			assertions.equal(resultsRebound.viewerRole, "Participant")
			assertions.equal(resultsRebound.state, "Results")
			assertions.equal(results.service:getMetrics().generation, 1)
			cleanupRig(results)
		end
	),

	TestHarness.case("rejects every playable mutation from an authorized ticket spectator", function(assertions)
		local rig = makeRig(false, {
			expectedUserIds = { 101, 202 },
			frozenLoadouts = { frozenLoadout(101), frozenLoadout(202) },
			rewarding = true,
			managedAdmissions = true,
			connectedParticipantUserIds = { 101 },
			matchId = "match:ticket-spectator",
			mapId = "map:phase07-graybox",
			difficultyId = "difficulty:local",
		})
		startRig(rig)
		table.insert(rig.active, rig.second)
		assertions.isTrue(rig.service:admitAuthorized(rig.second, false).accepted)
		local spectator = currentSnapshot(assertions, rig, rig.second)
		assertions.equal(spectator.viewerRole, "Spectator")
		assertions.equal(spectator.state, "Ready")
		assertions.equal(spectator.loadoutRevision, 0)
		assertions.equal(spectator.battleCash, 0)
		assertions.equal(#spectator.towerOptions, 0)
		local function rejected(receipt, reason)
			assertions.isNotNil(receipt)
			assertions.isFalse(receipt.accepted)
			assertions.equal(receipt.reason, reason)
		end
		local beforeReady = currentSnapshot(assertions, rig, rig.first)
		rejected(rig.service:submitReady(rig.second, { matchId = spectator.matchId }), "ParticipantDisconnected")
		local afterReady = currentSnapshot(assertions, rig, rig.first)
		assertions.equal(afterReady.revision, beforeReady.revision)
		assertions.equal(afterReady.state, "Ready")
		assertions.equal(afterReady.participants.readyCount, beforeReady.participants.readyCount)
		ready(assertions, rig, rig.first)
		assertions.isTrue(rig.service:submitPlacement(rig.first, {
			matchId = spectator.matchId,
			loadoutRevision = 7,
			slot = 1,
			towerId = "tower:dart-ant",
			position = Vector3.new(0, 0, 8),
			rotationDegrees = 0,
		}).accepted)
		local before = currentSnapshot(assertions, rig, rig.first)
		local tower = before.towers[1]
		local towerPayload = {
			matchId = before.matchId,
			runtimeTowerId = tower.runtimeTowerId,
			towerRevision = tower.revision,
		}
		rejected(
			rig.service:submitPlacement(rig.second, {
				matchId = before.matchId,
				loadoutRevision = 7,
				slot = 1,
				towerId = "tower:dart-ant",
				position = Vector3.new(4, 0, 8),
				rotationDegrees = 0,
			}),
			"ParticipantDisconnected"
		)
		rejected(rig.service:submitUpgrade(rig.second, towerPayload), "ParticipantDisconnected")
		rejected(rig.service:submitSell(rig.second, towerPayload), "ParticipantDisconnected")
		local targetPayload = table.clone(towerPayload)
		targetPayload.targetMode = "Last"
		rejected(rig.service:submitTargetMode(rig.second, targetPayload), "ParticipantDisconnected")
		local after = currentSnapshot(assertions, rig, rig.first)
		assertions.equal(after.revision, before.revision)
		assertions.equal(after.battleCash, before.battleCash)
		assertions.equal(after.stats.placements, before.stats.placements)
		assertions.equal(after.stats.upgrades, before.stats.upgrades)
		assertions.equal(after.stats.sells, before.stats.sells)
		assertions.equal(#after.towers, 1)
		assertions.equal(after.towers[1].ownerUserId, 101)
		assertions.equal(after.towers[1].revision, tower.revision)
		assertions.equal(after.towers[1].level, tower.level)
		assertions.equal(after.towers[1].targetMode, tower.targetMode)
		local afterSpectator = currentSnapshot(assertions, rig, rig.second)
		assertions.equal(afterSpectator.viewerRole, "Spectator")
		assertions.equal(afterSpectator.battleCash, 0)
		assertions.equal(#afterSpectator.towerOptions, 0)
		assertions.equal(afterSpectator.stats.placements, 0)
		assertions.equal(afterSpectator.stats.upgrades, 0)
		assertions.equal(afterSpectator.stats.sells, 0)
		runToResults(assertions, rig)
		local result = currentSnapshot(assertions, rig, rig.first)
		rejected(rig.service:submitReplay(rig.second, { matchId = result.matchId }), "WrongState")
		local afterReplay = currentSnapshot(assertions, rig, rig.first)
		assertions.equal(afterReplay.matchId, result.matchId)
		assertions.equal(afterReplay.revision, result.revision)
		assertions.equal(afterReplay.state, "Results")
		assertions.equal(rig.service:getMetrics().generation, 1)
		cleanupRig(rig)
	end),

	TestHarness.case("rejects spectator replay even when local participant replay is enabled", function(assertions)
		local rig = makeRig()
		startRig(rig)
		ready(assertions, rig, rig.first)
		table.insert(rig.active, rig.second)
		rig.fireAdded(rig.second)
		runToResults(assertions, rig)
		local spectator = currentSnapshot(assertions, rig, rig.second)
		assertions.equal(spectator.viewerRole, "Spectator")
		assertions.isFalse(spectator.rewarding)
		local receipt = rig.service:submitReplay(rig.second, { matchId = spectator.matchId })
		assertions.isNotNil(receipt)
		assertions.isFalse(receipt.accepted)
		assertions.equal(receipt.reason, "NotParticipant")
		local after = currentSnapshot(assertions, rig, rig.second)
		assertions.equal(after.matchId, spectator.matchId)
		assertions.equal(after.revision, spectator.revision)
		assertions.equal(after.state, "Results")
		assertions.equal(rig.service:getMetrics().generation, 1)
		cleanupRig(rig)
	end),

	TestHarness.case(
		"projects cached Match tutorial steps only to their authenticated participant",
		function(assertions)
			local tutorialStep = 5
			local providerCalls = {}
			local matchId = "match:tutorial-service"
			local rig = makeRig(false, {
				expectedUserIds = { 101, 202 },
				frozenLoadouts = { frozenLoadout(101), frozenLoadout(202) },
				rewarding = true,
				managedAdmissions = true,
				connectedParticipantUserIds = { 101 },
				matchId = matchId,
				mapId = "map:backyard-garden-v1",
				difficultyId = "difficulty:easy-v1",
				tutorialStepProvider = function(userId, requestedMatchId)
					table.insert(providerCalls, { userId = userId, matchId = requestedMatchId })
					return tutorialStep
				end,
			})
			startRig(rig)
			local initial = currentSnapshot(assertions, rig, rig.first)
			assertions.equal(initial.tutorialStep, 5)
			assertions.equal(rig.publications[#rig.publications].tutorialStep, 5)

			tutorialStep = 6
			assertions.isTrue(rig.service:refreshTutorial(101))
			rig.setClock(100.25)
			rig.fireHeartbeat()
			local guided = rig.publications[#rig.publications]
			assertions.equal(guided.tutorialStep, 6)
			assertions.isTrue(guided.revision > initial.revision)

			table.insert(rig.active, rig.second)
			assertions.isTrue(rig.service:admitAuthorized(rig.second, false).accepted)
			local callsBeforeSpectator = #providerCalls
			local spectator = currentSnapshot(assertions, rig, rig.second)
			assertions.equal(spectator.viewerRole, "Spectator")
			assertions.isNil(spectator.tutorialStep)
			assertions.equal(#providerCalls, callsBeforeSpectator)

			tutorialStep = 9
			assertions.isTrue(rig.service:refreshTutorial(101))
			assertions.isNil(currentSnapshot(assertions, rig, rig.first).tutorialStep)
			cleanupRig(rig)
		end
	),

	TestHarness.case("bounds frozen loadouts across rejected joins and player churn", function(assertions)
		local rig = makeRig()
		startRig(rig)
		ready(assertions, rig, rig.first)
		assertions.equal(rig.service:getMetrics().frozenLoadoutCount, 1)
		table.insert(rig.active, rig.second)
		rig.fireAdded(rig.second)
		assertions.equal((rig.service:getMetrics().runtime :: any).participantCount, 1)
		assertions.equal(rig.service:getMetrics().frozenLoadoutCount, 1)
		removeActive(rig.active, rig.second)
		rig.fireRemoving(rig.second)
		removeActive(rig.active, rig.first)
		rig.fireRemoving(rig.first)
		assertions.equal(rig.service:getMetrics().frozenLoadoutCount, 1)
		cleanupRig(rig)
	end),

	TestHarness.case(
		"injects an ordered frozen ticket roster before all expected identities arrive",
		function(assertions)
			local rig = makeRig(false, {
				expectedUserIds = { 202, 101 },
				frozenLoadouts = { frozenLoadout(202), frozenLoadout(101) },
				rewarding = true,
				matchId = "match:ticket-roster",
				mapId = "map:backyard-garden-v1",
				difficultyId = "difficulty:easy-v1",
			})
			startRig(rig)
			local first = currentSnapshot(assertions, rig, rig.first)
			assertions.equal(first.viewerRole, "Participant")
			assertions.isTrue(first.rewarding)
			assertions.equal(first.loadoutRevision, 7)
			assertions.equal((rig.service:getMetrics().runtime :: any).participantCount, 2)
			assertions.equal((rig.service:getMetrics().runtime :: any).connectedParticipantCount, 1)

			-- The second expected identity reconnects to the preloaded participant
			-- instead of appending or resolving a fresh profile loadout.
			table.insert(rig.active, rig.second)
			rig.fireAdded(rig.second)
			local second = currentSnapshot(assertions, rig, rig.second)
			assertions.equal(second.viewerRole, "Participant")
			assertions.equal(second.loadoutRevision, 7)
			assertions.equal((rig.service:getMetrics().runtime :: any).participantCount, 2)
			assertions.equal((rig.service:getMetrics().runtime :: any).connectedParticipantCount, 2)
			cleanupRig(rig)

			local spectatorSettings = table.clone(CONFIGURATION.defaultSettings)
			spectatorSettings.uiScale = 1.25
			spectatorSettings.reducedMotionEnabled = true
			local late = makeRig(false, {
				expectedUserIds = { 101, 202 },
				frozenLoadouts = { frozenLoadout(101), frozenLoadout(202, spectatorSettings) },
				rewarding = true,
				matchId = "match:ticket-roster-late",
				mapId = "map:backyard-garden-v1",
				difficultyId = "difficulty:easy-v1",
			})
			startRig(late)
			ready(assertions, late, late.first)
			table.insert(late.active, late.second)
			late.fireAdded(late.second)
			local lateSnapshot = currentSnapshot(assertions, late, late.second)
			assertions.equal(lateSnapshot.viewerRole, "Spectator")
			assertions.equal(lateSnapshot.state, "Playing")
			assertions.equal(lateSnapshot.loadoutRevision, 0)
			assertions.equal(lateSnapshot.settings.uiScale, 1.25)
			assertions.isTrue(lateSnapshot.settings.reducedMotionEnabled)
			assertions.equal(lateSnapshot.battleCash, 0)
			assertions.equal(#lateSnapshot.towerOptions, 0)
			assertions.equal((late.service:getMetrics().runtime :: any).participantCount, 2)
			assertions.equal((late.service:getMetrics().runtime :: any).connectedParticipantCount, 1)
			cleanupRig(late)
		end
	),
})
