--!strict

-- Deterministic balance evidence must exercise the production authority graph.
-- This harness advances PlayableMatchRuntime with a virtual server clock and
-- supplies only player decisions; the runtime owns every gameplay rule.
local ContentSelection = require(game:GetService("ReplicatedStorage").Shared.config.ContentSelection)
local PlacementGeometry = require(game:GetService("ReplicatedStorage").Shared.match.PlacementGeometry)
local PlayableMatchRuntime = require(script.Parent.Parent.ProductionServerPlayable.PlayableMatchRuntime)

local ContentBalanceSimulation = {}

export type PlacementSnapshot = {
	towerId: string,
	slotId: string,
	zoneId: string,
	positionXZ: Vector2,
	footprintRadiusStuds: number,
	minimumPathDistanceStuds: number,
}

export type Result = {
	victory: boolean,
	wavesCompleted: number,
	baseHealthRemaining: number,
	battleCashRemaining: number,
	damageDealt: number,
	maximumActiveEnemies: number,
	towerCount: number,
	attackCount: number,
	durationSeconds: number,
	placements: { PlacementSnapshot },
}

type PathSegment = {
	start: Vector2,
	finish: Vector2,
	length: number,
	startProgress: number,
}

type BuildSlot = {
	id: string,
	zoneId: string,
	positionXZ: Vector2,
}

local MATCH_ID = "match:content-balance"
local USER_ID = 840_001
local LOADOUT_REVISION = 1
local START_SERVER_TIME = 100
local MAX_VIRTUAL_STEPS = 20_000

local GARDEN_PATH = table.freeze({
	Vector2.new(-70, -40),
	Vector2.new(-42, -40),
	Vector2.new(-28, -18),
	Vector2.new(8, -18),
	Vector2.new(24, 10),
	Vector2.new(48, 10),
	Vector2.new(70, 10),
})

local GARDEN_BOUNDS = table.freeze({
	cframe = CFrame.new(0, 25, 0),
	size = Vector3.new(170, 90, 150),
})

local GARDEN_PLACEMENT_ZONES = table.freeze({
	table.freeze({
		id = "west-overlook",
		cframe = CFrame.new(-45, 0, -54),
		size = Vector3.new(34, 2, 12),
		surfaceCategory = "Land",
	}),
	table.freeze({
		id = "middle-bend",
		cframe = CFrame.new(-12, 0, -5),
		size = Vector3.new(36, 2, 12),
		surfaceCategory = "Land",
	}),
	table.freeze({
		id = "upper-choke",
		cframe = CFrame.new(30, 0, 23),
		size = Vector3.new(38, 2, 12),
		surfaceCategory = "Land",
	}),
	table.freeze({
		id = "east-choke",
		cframe = CFrame.new(51, 0, -5),
		size = Vector3.new(26, 2, 10),
		surfaceCategory = "Land",
	}),
})

local GARDEN_EXCLUSIONS = table.freeze({
	table.freeze({
		id = "west-rock",
		cframe = CFrame.new(-45, 0, -54),
		size = Vector3.new(7, 2, 7),
	}),
})

-- A player's deterministic build policy rotates through every readable pocket.
-- Each position is legal for the largest tower and reaches the lane at level one.
local GARDEN_PLACEMENT_SLOTS: { BuildSlot } = table.freeze({
	table.freeze({ id = "west-a", zoneId = "west-overlook", positionXZ = Vector2.new(-54, -54) }),
	table.freeze({ id = "middle-a", zoneId = "middle-bend", positionXZ = Vector2.new(-25, -5) }),
	table.freeze({ id = "upper-a", zoneId = "upper-choke", positionXZ = Vector2.new(16, 19) }),
	table.freeze({ id = "east-a", zoneId = "east-choke", positionXZ = Vector2.new(43, -5) }),
	table.freeze({ id = "west-b", zoneId = "west-overlook", positionXZ = Vector2.new(-33, -54) }),
	table.freeze({ id = "middle-b", zoneId = "middle-bend", positionXZ = Vector2.new(1, -5) }),
	table.freeze({ id = "upper-b", zoneId = "upper-choke", positionXZ = Vector2.new(44, 23) }),
	table.freeze({ id = "east-b", zoneId = "east-choke", positionXZ = Vector2.new(61, -5) }),
})

local pathSegments: { PathSegment } = {}
local PATH_LENGTH_STUDS = 0
for index = 1, #GARDEN_PATH - 1 do
	local start = GARDEN_PATH[index]
	local finish = GARDEN_PATH[index + 1]
	local length = (finish - start).Magnitude
	table.insert(pathSegments, {
		start = start,
		finish = finish,
		length = length,
		startProgress = PATH_LENGTH_STUDS,
	})
	PATH_LENGTH_STUDS += length
end
table.freeze(pathSegments)

local function distanceToSegment(position: Vector2, segment: PathSegment): number
	local delta = segment.finish - segment.start
	local alpha = math.clamp((position - segment.start):Dot(delta) / delta:Dot(delta), 0, 1)
	return (position - segment.start:Lerp(segment.finish, alpha)).Magnitude
end

local function minimumDistanceToPath(position: Vector2): number
	local minimum = math.huge
	for _, segment in pathSegments do
		minimum = math.min(minimum, distanceToSegment(position, segment))
	end
	return minimum
end

local function runtimeMap(): any
	local points = table.create(#GARDEN_PATH)
	local totalDistance = 0
	local previous: Vector2? = nil
	for index, positionXZ in GARDEN_PATH do
		if previous ~= nil then
			totalDistance += (positionXZ - (previous :: Vector2)).Magnitude
		end
		local position = Vector3.new(positionXZ.X, 3, positionXZ.Y)
		table.insert(points, {
			kind = "Path",
			nodeOrder = index,
			cframe = CFrame.new(position),
			position = position,
			distance = totalDistance,
		})
		previous = positionXZ
	end
	local basePosition = points[#points].position
	return {
		mapId = ContentSelection.RELEASE_MAP_ID,
		base = { cframe = CFrame.new(basePosition), position = basePosition },
		bounds = GARDEN_BOUNDS,
		lanes = {
			{
				id = "main",
				totalDistance = totalDistance,
				points = points,
			},
		},
		placementZones = GARDEN_PLACEMENT_ZONES,
		noPlacementZones = GARDEN_EXCLUSIONS,
		cameraAnchors = {},
		playerSpawns = {},
	}
end

local function unwrap(operation: string, result: any): any
	if not result.ok then
		error(`content balance runtime {operation} failed: {result.error.code}`, 2)
	end
	return result.value
end

local function expectAccepted(operation: string, outcome: any)
	if not outcome.accepted then
		error(`content balance runtime {operation} was rejected: {outcome.reason}`, 2)
	end
end

local function loadout(configuration: any, towerIds: { string }): any
	local slots = table.create(#towerIds)
	for index, towerId in towerIds do
		if configuration.towers.byId[towerId] == nil then
			error(`content balance tower is unavailable: {towerId}`, 2)
		end
		table.insert(slots, {
			slot = index,
			unitId = `unit:content-balance-{index}`,
			towerId = towerId,
		})
	end
	return {
		userId = USER_ID,
		revision = LOADOUT_REVISION,
		slots = slots,
		settings = configuration.defaultSettings,
	}
end

local function loadoutSlotByTowerId(towerIds: { string }): { [string]: number }
	local slots: { [string]: number } = {}
	for index, towerId in towerIds do
		slots[towerId] = index
	end
	return slots
end

local function validatePlacementPlan(configuration: any, towerIds: { string })
	local footprints: { Vector3 } = {}
	for index, buildSlot in GARDEN_PLACEMENT_SLOTS do
		local towerId = towerIds[((index - 1) % #towerIds) + 1]
		local definition = configuration.towers.byId[towerId]
		local evaluation = PlacementGeometry.evaluate(
			buildSlot.positionXZ,
			definition.footprintRadiusStuds,
			GARDEN_BOUNDS,
			GARDEN_PLACEMENT_ZONES,
			GARDEN_EXCLUSIONS,
			footprints
		)
		if not evaluation.valid or evaluation.zoneIndex == nil then
			error(`content balance slot {buildSlot.id} is not legal: {evaluation.reason}`, 2)
		end
		if GARDEN_PLACEMENT_ZONES[evaluation.zoneIndex].id ~= buildSlot.zoneId then
			error(`content balance slot {buildSlot.id} resolved to the wrong build pocket`, 2)
		end
		local footprint = PlacementGeometry.encodeFootprint(buildSlot.positionXZ, definition.footprintRadiusStuds)
		if footprint == nil then
			error(`content balance slot {buildSlot.id} has an invalid footprint`, 2)
		end
		table.insert(footprints, footprint)
	end
end

-- This is only a player decision policy: fill eight authored slots by rotating
-- through the selected roles, then buy upgrades in stable tower order. Costs,
-- validation, mutations, and combat remain exclusively inside the runtime.
local function applyBuildPolicy(runtime: any, configuration: any, towerIds: { string }, serverTime: number)
	local slotsByTowerId = loadoutSlotByTowerId(towerIds)
	for _ = 1, 64 do
		local snapshot = unwrap("snapshot", runtime:getSnapshot(USER_ID, serverTime))
		if snapshot.state ~= "Playing" then
			return
		end
		if #snapshot.towers < #GARDEN_PLACEMENT_SLOTS then
			local buildSlot = GARDEN_PLACEMENT_SLOTS[#snapshot.towers + 1]
			local towerId = towerIds[(#snapshot.towers % #towerIds) + 1]
			local definition = configuration.towers.byId[towerId]
			if snapshot.battleCash < definition.placementCost then
				return
			end
			expectAccepted(
				"placeTower",
				runtime:placeTower(
					USER_ID,
					MATCH_ID,
					towerId,
					slotsByTowerId[towerId],
					LOADOUT_REVISION,
					Vector3.new(buildSlot.positionXZ.X, 0, buildSlot.positionXZ.Y),
					0,
					serverTime
				)
			)
		else
			local upgraded = false
			for _, tower in snapshot.towers do
				if tower.upgradeCost > 0 and tower.upgradeCost <= snapshot.battleCash then
					expectAccepted(
						"upgradeTower",
						runtime:upgradeTower(USER_ID, MATCH_ID, tower.runtimeTowerId, tower.revision)
					)
					upgraded = true
					break
				end
			end
			if not upgraded then
				return
			end
		end
	end
	error("content balance build policy exceeded its bounded action budget", 2)
end

function ContentBalanceSimulation.run(configuration: any, difficultyId: string, towerIds: { string }): Result
	local difficulty = configuration.difficulties.byId[difficultyId]
	local schedules = configuration.waves.byMapId[ContentSelection.RELEASE_MAP_ID]
	local schedule = if schedules == nil then nil else schedules[difficultyId]
	if difficulty == nil or difficulty.kind ~= "Finite" or schedule == nil or schedule.kind ~= "AuthoredFinite" then
		error("content balance harness requires an authenticated finite garden schedule", 2)
	end
	if #towerIds ~= 2 or towerIds[1] == towerIds[2] then
		error("content balance harness requires two distinct player-selected roles", 2)
	end
	validatePlacementPlan(configuration, towerIds)

	local runtime = unwrap(
		"new",
		PlayableMatchRuntime.new({
			matchId = MATCH_ID,
			mapId = ContentSelection.RELEASE_MAP_ID,
			difficultyId = difficultyId,
			configuration = configuration,
			runtimeMap = runtimeMap(),
			participantLoadouts = { loadout(configuration, towerIds) },
			connectedParticipantUserIds = { USER_ID },
			rewarding = false,
			seed = 1,
		})
	)
	local serverTime = START_SERVER_TIME
	expectAccepted("submitReady", runtime:submitReady(USER_ID, MATCH_ID, serverTime))
	applyBuildPolicy(runtime, configuration, towerIds, serverTime)

	local maximumActiveEnemies = 0
	for _ = 1, MAX_VIRTUAL_STEPS do
		local metrics = runtime:getMetrics()
		if metrics.state == "Results" then
			break
		end
		local stepped = unwrap("step", runtime:step(serverTime + PlayableMatchRuntime.MAX_STEP_SECONDS))
		if stepped.serverTime <= serverTime then
			error("content balance runtime virtual clock made no progress", 2)
		end
		serverTime = stepped.serverTime
		local snapshot = unwrap("snapshot", runtime:getSnapshot(USER_ID, serverTime))
		maximumActiveEnemies = math.max(maximumActiveEnemies, #snapshot.enemies)
		applyBuildPolicy(runtime, configuration, towerIds, serverTime)
	end
	if runtime:getMetrics().state ~= "Results" then
		runtime:cleanup()
		error("content balance runtime did not reach Results within the virtual-time bound", 2)
	end

	local finalSnapshot = unwrap("snapshot", runtime:getSnapshot(USER_ID, serverTime))
	local metrics = runtime:getMetrics()
	local placements: { PlacementSnapshot } = table.create(#finalSnapshot.towers)
	for index, tower in finalSnapshot.towers do
		local slot = GARDEN_PLACEMENT_SLOTS[index]
		local positionXZ = Vector2.new(tower.position.X, tower.position.Z)
		table.insert(
			placements,
			table.freeze({
				towerId = tower.towerId,
				slotId = slot.id,
				zoneId = slot.zoneId,
				positionXZ = positionXZ,
				footprintRadiusStuds = configuration.towers.byId[tower.towerId].footprintRadiusStuds,
				minimumPathDistanceStuds = minimumDistanceToPath(positionXZ),
			})
		)
	end
	local cleaned = runtime:cleanup()
	if not cleaned.ok then
		error(`content balance runtime cleanup failed: {cleaned.error.code}`, 2)
	end
	return table.freeze({
		victory = finalSnapshot.result == "Victory",
		wavesCompleted = finalSnapshot.stats.wavesCompleted,
		baseHealthRemaining = finalSnapshot.baseHealth,
		battleCashRemaining = finalSnapshot.battleCash,
		damageDealt = finalSnapshot.stats.damageDealt,
		maximumActiveEnemies = maximumActiveEnemies,
		towerCount = #finalSnapshot.towers,
		attackCount = metrics.attackCount,
		durationSeconds = finalSnapshot.stats.durationSeconds,
		placements = table.freeze(placements),
	})
end

ContentBalanceSimulation.GARDEN_BOUNDS = GARDEN_BOUNDS
ContentBalanceSimulation.GARDEN_PATH = GARDEN_PATH
ContentBalanceSimulation.GARDEN_PATH_LENGTH_STUDS = PATH_LENGTH_STUDS
ContentBalanceSimulation.GARDEN_PLACEMENT_ZONES = GARDEN_PLACEMENT_ZONES
ContentBalanceSimulation.GARDEN_EXCLUSIONS = GARDEN_EXCLUSIONS
ContentBalanceSimulation.GARDEN_PLACEMENT_SLOTS = GARDEN_PLACEMENT_SLOTS
ContentBalanceSimulation.minimumDistanceToPath = minimumDistanceToPath

return table.freeze(ContentBalanceSimulation)
