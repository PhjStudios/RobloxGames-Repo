--!strict

-- Deterministic workload/accounting around the existing authority. This file
-- never implements combat, reward, target selection or a second simulation.
local Shared = game:GetService("ReplicatedStorage").Shared
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local ContentSelection = require(Shared.config.ContentSelection)
local PlayableMatchProtocol = require(Shared.match.PlayableMatchProtocol)
local RequestProtocol = require(Shared.network.RequestProtocol)
local ProductionRemotes = require(Shared.network.ProductionRemotes)
local ConfigurationFixtures = require(script.Parent.Parent.Fixtures.ConfigurationFixtures)
local PlayableMatchRuntime = require(script.Parent.Parent.ProductionServerPlayable.PlayableMatchRuntime)
local EndlessWaveGenerator = require(script.Parent.Parent.ProductionServerPlayable.EndlessWaveGenerator)
local ContentBalanceSimulation = require(script.Parent.ContentBalanceSimulation)
local PerformanceWindow = require(script.Parent.PerformanceWindow)

local PerformanceScenarios = {
	VERSION = 1,
	DENSE_STEPS = 200,
	STEP_SECONDS = 0.05,
	PROJECTION_INTERVAL_STEPS = 2,
}
local PARTICIPANTS = table.freeze({ 710_001, 710_002, 710_003, 710_004 })
local TOWER_IDS = table.freeze({ "tower:rapid-ant", "tower:bombardier-ant", "tower:dart-ant", "tower:guard-ant" })
local START_TIME = 100

local function unwrap(result: any): any
	assert(result.ok, "performance scenario production operation failed")
	return result.value
end

local function accepted(result: any)
	assert(result.accepted, "performance scenario action rejected")
end

local function map(short: boolean, mapId: string): any
	local positions = {}
	if short then
		positions = { Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0) }
	else
		for index = 0, 64 do
			local angle = index * math.pi * 2 / 16
			table.insert(positions, Vector3.new(math.cos(angle) * 8, 0, math.sin(angle) * 8))
		end
	end
	local points, distance = {}, 0
	for index, position in positions do
		if index > 1 then
			distance += (position - positions[index - 1]).Magnitude
		end
		table.insert(points, {
			kind = "Path",
			nodeOrder = index,
			cframe = CFrame.new(position),
			position = position,
			distance = distance,
		})
	end
	local endpoint = positions[#positions]
	return {
		mapId = mapId,
		base = { cframe = CFrame.new(endpoint), position = endpoint },
		bounds = { cframe = CFrame.new(), size = Vector3.new(100, 20, 100) },
		lanes = { { id = "main", totalDistance = distance, points = points } },
		placementZones = { { id = "stress-land", cframe = CFrame.new(0, -1, 0), size = Vector3.new(80, 2, 80) } },
		noPlacementZones = {},
		cameraAnchors = {},
		playerSpawns = {},
	}
end

local function loadouts(configuration: any): { any }
	local result = {}
	for _, userId in PARTICIPANTS do
		local slots = {}
		for index, towerId in TOWER_IDS do
			table.insert(slots, { slot = index, unitId = `unit:performance-{userId}-{index}`, towerId = towerId })
		end
		table.insert(result, { userId = userId, revision = 1, slots = slots, settings = configuration.defaultSettings })
	end
	return result
end

local function construct(configuration: any, matchId: string, mapId: string, difficultyId: string, short: boolean): any
	return unwrap(PlayableMatchRuntime.new({
		matchId = matchId,
		configuration = configuration,
		runtimeMap = map(short, mapId),
		mapId = mapId,
		difficultyId = difficultyId,
		participantLoadouts = loadouts(configuration),
		connectedParticipantUserIds = PARTICIPANTS,
		rewarding = false,
		seed = 1,
	}))
end

local function ready(runtime: any, matchId: string)
	for _, userId in PARTICIPANTS do
		accepted(runtime:submitReady(userId, matchId, START_TIME))
	end
end

local function clean(runtime: any): any
	assert(unwrap(runtime:cleanup()) == true, "first cleanup should retire runtime")
	assert(unwrap(runtime:cleanup()) == false, "second cleanup must be idempotent")
	local metrics = runtime:getMetrics()
	assert(
		metrics.cleaned
			and metrics.activeTowerCount == 0
			and metrics.activeEnemyCount == 0
			and metrics.participantCount == 0
			and metrics.connectedParticipantCount == 0
			and metrics.readyCount == 0
			and metrics.activeWaveOriginCount == 0,
		"runtime collections retained after cleanup"
	)
	assert(not runtime:getSnapshot(PARTICIPANTS[1], START_TIME).ok, "cleaned runtime remained readable")
	return metrics
end

local function estimate(payload: any): number
	local envelope = unwrap(RequestProtocol.buildEvent(payload))
	local bytes = PerformanceWindow.payloadEstimate(envelope)
	assert(bytes ~= nil, "validated production envelope not measurable")
	return bytes :: number
end

function PerformanceScenarios.denseConfiguration(): any
	local sources = {}
	for key, name in
		{
			assets = "Assets",
			towers = "Towers",
			enemies = "Enemies",
			difficulties = "Difficulties",
			maps = "Maps",
			waves = "Waves",
			economy = "Economy",
			banners = "Banners",
			defaultSettings = "DefaultSettings",
		}
	do
		sources[key] = ConfigurationFixtures.clone(require(Shared.config[name]))
	end
	-- Declared stress-only overrides: saturate the current entity cap while
	-- preserving production towers, attack behavior, costs, IDs and protocols.
	for _, enemy in sources.enemies do
		if enemy.id == "enemy:worker-ant" then
			enemy.maxHealth = 1_000_000
			enemy.moveSpeedStudsPerSecond = 0.1
		end
	end
	for _, schedule in sources.waves do
		if
			schedule.mapId == ContentSelection.RELEASE_MAP_ID
			and schedule.difficultyId == ContentSelection.NORMAL_DIFFICULTY_ID
		then
			local wave = schedule.waves[1]
			wave.deadlineSeconds = 300
			wave.groups = {
				{
					enemyId = "enemy:worker-ant",
					laneId = "main",
					count = 20,
					startDelaySeconds = 0,
					spawnIntervalSeconds = 0,
				},
			}
		end
	end
	return unwrap(ConfigurationValidator.validate(sources))
end

function PerformanceScenarios.runDense(): any
	assert(
		ProductionRemotes:get(PlayableMatchProtocol.ENDPOINTS.REPLICATION).transport == "ReliableRemoteEvent",
		"snapshot transport changed"
	)
	assert(
		ProductionRemotes:get(PlayableMatchProtocol.ENDPOINTS.ATTACK_EVENT).transport == "ReliableRemoteEvent",
		"attack transport changed"
	)
	local configuration = PerformanceScenarios.denseConfiguration()
	local matchId = "match:performance-dense"
	local runtime =
		construct(configuration, matchId, ContentSelection.RELEASE_MAP_ID, ContentSelection.NORMAL_DIFFICULTY_ID, false)
	local stepWindow, snapshotWindow, attackWindow =
		PerformanceWindow.new(), PerformanceWindow.new(), PerformanceWindow.new()
	local snapshotBytes, attackBytes, snapshots, attacks = 0, 0, 0, 0
	local maximumTowers, maximumEnemies, maximumAttacksPerStep = 0, 0, 0
	local startClock = os.clock()
	local finished, result = pcall(function()
		ready(runtime, matchId)
		for participantIndex, userId in PARTICIPANTS do
			for slot = 1, 3 do
				local position = Vector3.new(-9 + (participantIndex - 1) * 6, 0, -6 + (slot - 1) * 6)
				accepted(runtime:placeTower(userId, matchId, TOWER_IDS[slot], slot, 1, position, 0, START_TIME))
			end
		end
		for step = 1, PerformanceScenarios.DENSE_STEPS do
			local before = os.clock()
			local output = unwrap(runtime:step(START_TIME + step * PerformanceScenarios.STEP_SECONDS))
			stepWindow:add((os.clock() - before) * 1_000)
			maximumAttacksPerStep = math.max(maximumAttacksPerStep, #output.attacks)
			for _, event in output.attacks do
				unwrap(PlayableMatchProtocol.validateAttackEvent(event))
				local bytes = estimate(event)
				attackWindow:add(bytes)
				attacks += 1
				attackBytes += bytes * #PARTICIPANTS
			end
			if step % PerformanceScenarios.PROJECTION_INTERVAL_STEPS == 0 then
				for _, userId in PARTICIPANTS do
					local snapshot = unwrap(runtime:getSnapshot(userId, output.serverTime))
					unwrap(PlayableMatchProtocol.validateSnapshot(snapshot))
					maximumTowers = math.max(maximumTowers, #snapshot.towers)
					maximumEnemies = math.max(maximumEnemies, #snapshot.enemies)
					local bytes = estimate(snapshot)
					snapshotWindow:add(bytes)
					snapshotBytes += bytes
					snapshots += 1
				end
			end
		end
		return {
			version = PerformanceScenarios.VERSION,
			contentVersion = ContentSelection.CONTENT_VERSION,
			evidence = "deterministic",
			byteKind = "JSON-like event envelope estimate; not Roblox wire bytes",
			transport = "ReliableRemoteEvent",
			projectionSchedule = "virtual 10 Hz accounting; actual sender cadence requires Studio measurement",
			scenario = "production towers and runtime; stress-only enemy/wave override; synthetic loop lane",
			durationSeconds = PerformanceScenarios.DENSE_STEPS * PerformanceScenarios.STEP_SECONDS,
			recipients = #PARTICIPANTS,
			maximumTowers = maximumTowers,
			maximumEnemies = maximumEnemies,
			maximumAttacksPerStep = maximumAttacksPerStep,
			waveOriginsBeforeCleanup = runtime:getMetrics().activeWaveOriginCount,
			logicalAttacks = attacks,
			deliveredAttackEnvelopes = attacks * #PARTICIPANTS,
			snapshotEnvelopes = snapshots,
			snapshotEstimatedBytes = snapshotBytes,
			attackEstimatedBytes = attackBytes,
			snapshotSizes = snapshotWindow:summary(),
			attackSizes = attackWindow:summary(),
			stepMilliseconds = stepWindow:summary(),
			hostElapsedSeconds = os.clock() - startClock,
		}
	end)
	local cleanupMetrics = clean(runtime)
	assert(finished, tostring(result))
	result.cleanedTowers = cleanupMetrics.activeTowerCount
	result.cleanedEnemies = cleanupMetrics.activeEnemyCount
	result.cleanedParticipants = cleanupMetrics.participantCount
	result.cleanedWaveOrigins = cleanupMetrics.activeWaveOriginCount
	return table.freeze(result)
end

function PerformanceScenarios.runRepeatedFinite(configuration: any, cycles: number): any
	assert(cycles >= 1 and cycles <= 100 and cycles % 1 == 0, "invalid finite cycle bound")
	local completed, maximumEnemies, totalSteps = 0, 0, 0
	local outcomes = {}
	for cycle = 1, cycles do
		local matchId = `match:performance-cycle-{cycle}`
		local runtime = construct(
			configuration,
			matchId,
			ContentSelection.DEVELOPMENT_MAP_ID,
			ContentSelection.DEVELOPMENT_DIFFICULTY_ID,
			true
		)
		local finished, result = pcall(function()
			ready(runtime, matchId)
			local now = START_TIME
			for _ = 1, 2_000 do
				local metrics = runtime:getMetrics()
				if metrics.state == "Results" then
					completed += 1
					table.insert(outcomes, `{metrics.result}:{metrics.wavesCompleted}`)
					return
				end
				now = unwrap(runtime:step(now + PlayableMatchRuntime.MAX_STEP_SECONDS)).serverTime
				totalSteps += 1
				maximumEnemies = math.max(maximumEnemies, runtime:getMetrics().activeEnemyCount)
			end
			error("finite runtime exceeded virtual-time bound", 0)
		end)
		clean(runtime)
		assert(finished, tostring(result))
	end
	return table.freeze({
		cycles = cycles,
		terminalResults = completed,
		totalSteps = totalSteps,
		maximumEnemies = maximumEnemies,
		remainingTowers = 0,
		remainingEnemies = 0,
		remainingParticipants = 0,
		outcomes = table.concat(outcomes, "|"),
	})
end

function PerformanceScenarios.runCampaigns(configuration: any, cycles: number): string
	assert(cycles >= 1 and cycles <= 5 and cycles % 1 == 0, "invalid campaign cycle bound")
	local summaries = {}
	for _ = 1, cycles do
		for _, difficultyId in
			{
				ContentSelection.EASY_DIFFICULTY_ID,
				ContentSelection.NORMAL_DIFFICULTY_ID,
				ContentSelection.HARD_DIFFICULTY_ID,
			}
		do
			local result =
				ContentBalanceSimulation.run(configuration, difficultyId, { "tower:dart-ant", "tower:bombardier-ant" })
			table.insert(
				summaries,
				`{difficultyId}:{result.victory}:{result.wavesCompleted}:{result.attackCount}:{result.battleCashRemaining}`
			)
		end
	end
	return table.concat(summaries, "|")
end

function PerformanceScenarios.runEndlessDescriptions(configuration: any, waves: number): any
	assert(waves >= 1 and waves <= 10_000 and waves % 1 == 0, "invalid generator wave bound")
	local maximumGroups, maximumSpawns, checksum = 0, 0, 0
	for wave = 1, waves do
		local value = unwrap(
			EndlessWaveGenerator.generate(
				configuration,
				ContentSelection.ENDLESS_GENERATOR_KEY,
				1_337_337,
				wave,
				"main"
			)
		)
		local spawns = 0
		for _, group in value.wave.groups do
			spawns += group.count
		end
		maximumGroups = math.max(maximumGroups, #value.wave.groups)
		maximumSpawns = math.max(maximumSpawns, spawns)
		checksum = (checksum * 31 + spawns + #value.wave.groups + wave) % 2_147_483_647
	end
	return table.freeze({
		waves = waves,
		maximumGroups = maximumGroups,
		maximumSpawns = maximumSpawns,
		checksum = checksum,
		evidence = "deterministic generated descriptions; not a memory/frame/network soak",
	})
end

return table.freeze(PerformanceScenarios)
