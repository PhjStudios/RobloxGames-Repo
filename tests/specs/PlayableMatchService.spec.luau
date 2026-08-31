--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
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

local function runtimeMap(): any
	local first = Vector3.new(-1, 0, 0)
	local last = Vector3.new(1, 0, 0)
	return {
		mapId = "map:phase07-graybox",
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

local function makeRig(extraContent: boolean?): any
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
		return Result.ok(runtimeMap())
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
		environment
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
		"accepts exactly seven unique authenticated direct models and rejects extras",
		function(assertions)
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
		end
	),

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

	TestHarness.case("replaces empty Playing and Results runtimes on the next active join", function(assertions)
		local playing = makeRig()
		startRig(playing)
		ready(assertions, playing, playing.first)
		local placed = playing.service:submitPlacement(playing.first, {
			matchId = currentSnapshot(assertions, playing, playing.first).matchId,
			towerId = "tower:dart-ant",
			position = Vector3.new(0, 0, 8),
			rotationDegrees = 0,
		})
		assertions.isTrue((placed :: any).accepted)
		removeActive(playing.active, playing.first)
		playing.fireRemoving(playing.first)
		assertions.equal((playing.service:getMetrics().runtime :: any).participantCount, 0)
		assertions.equal((playing.service:getMetrics().runtime :: any).activeTowerCount, 0)
		table.insert(playing.active, playing.second)
		playing.fireAdded(playing.second)
		local playingReplacement = currentSnapshot(assertions, playing, playing.second)
		assertions.equal(playingReplacement.state, "Ready")
		assertions.equal(playingReplacement.battleCash, 500)
		assertions.equal(playing.service:getMetrics().generation, 2)
		assertions.isTrue(playing.service:getMetrics().publishPending)
		cleanupRig(playing)

		local results = makeRig()
		startRig(results)
		ready(assertions, results, results.first)
		runToResults(assertions, results)
		removeActive(results.active, results.first)
		results.fireRemoving(results.first)
		assertions.equal((results.service:getMetrics().runtime :: any).participantCount, 0)
		table.insert(results.active, results.second)
		results.fireAdded(results.second)
		assertions.equal(currentSnapshot(assertions, results, results.second).state, "Ready")
		assertions.equal(results.service:getMetrics().generation, 2)
		cleanupRig(results)
	end),
})
