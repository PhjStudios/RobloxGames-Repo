--!strict

-- Fresh, test-only authored-wave fixtures. Every raw root is complete and
-- mutable until the production ConfigurationValidator canonicalizes it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local ConfigTypes = require(Shared.types.ConfigTypes)
local Ids = require(Shared.util.Ids)

local WaveFixtures = {}

export type RawSources = { [string]: any }

export type RoutePointKind = "EnemySpawn" | "PathNode" | "DefenderBase"

export type RoutePointSnapshot = {
	kind: RoutePointKind,
	nodeOrder: number?,
	cframe: CFrame,
	position: Vector3,
	distance: number,
}

export type RuntimeLaneSnapshot = {
	id: string,
	totalDistance: number,
	points: { RoutePointSnapshot },
}

export type PointSnapshot = {
	cframe: CFrame,
	position: Vector3,
}

export type RegionSnapshot = {
	id: string,
	cframe: CFrame,
	size: Vector3,
}

export type NamedPointSnapshot = {
	id: string,
	cframe: CFrame,
	position: Vector3,
}

export type RuntimeMapSnapshot = {
	mapId: Ids.MapId,
	base: PointSnapshot,
	bounds: {
		cframe: CFrame,
		size: Vector3,
	},
	lanes: { RuntimeLaneSnapshot },
	placementZones: { RegionSnapshot },
	noPlacementZones: { RegionSnapshot },
	cameraAnchors: { NamedPointSnapshot },
	playerSpawns: { NamedPointSnapshot },
}

export type RuntimeMetadata = {
	difficultyId: Ids.DifficultyId,
	enemyHealthMultiplier: number,
	enemyMoveSpeedMultiplier: number,
	startingBattleCash: number,
}

export type FiniteSelection = {
	mapDefinition: ConfigTypes.MapDefinition,
	difficultyDefinition: ConfigTypes.FiniteDifficultyDefinition,
	schedule: ConfigTypes.FiniteWaveScheduleDefinition,
	economyRule: ConfigTypes.DifficultyEconomyDefinition,
	runtimeMetadata: RuntimeMetadata,
}

export type AuthenticatedFixture = {
	rawSources: RawSources,
	configuration: ConfigTypes.CoreConfiguration,
	runtimeMap: RuntimeMapSnapshot,
	primary: FiniteSelection,
	overlap: FiniteSelection,
}

WaveFixtures.MAP_ID = "map:phase07-graybox"
WaveFixtures.PRIMARY_DIFFICULTY_ID = "difficulty:phase11-authored"
WaveFixtures.OVERLAP_DIFFICULTY_ID = "difficulty:phase11-overlap"
WaveFixtures.ENDLESS_DIFFICULTY_ID = "difficulty:phase11-endless"
WaveFixtures.MAIN_LANE_ID = "main"
WaveFixtures.ALTERNATE_LANE_ID = "alternate"
WaveFixtures.WORKER_ENEMY_ID = "enemy:phase11-worker"
WaveFixtures.SCOUT_ENEMY_ID = "enemy:phase11-scout"
WaveFixtures.PRIMARY_SCHEDULED_SPAWNS = 13
WaveFixtures.OVERLAP_SCHEDULED_SPAWNS = 5
WaveFixtures.MAX_PRIMARY_SIMULTANEOUS_SPAWNS = 3

WaveFixtures.INVALID_CONFIGURATION = "INVALID_CONFIGURATION"
WaveFixtures.INVALID_RUNTIME_MAP = "INVALID_RUNTIME_MAP"
WaveFixtures.DIFFICULTY_NOT_FOUND = "DIFFICULTY_NOT_FOUND"
WaveFixtures.SCHEDULE_NOT_FOUND = "SCHEDULE_NOT_FOUND"
WaveFixtures.GENERATED_ENDLESS_UNSUPPORTED = "GENERATED_ENDLESS_UNSUPPORTED"
WaveFixtures.ECONOMY_RULE_NOT_FOUND = "ECONOMY_RULE_NOT_FOUND"

local ENEMY_MODEL_KEY = "test.phase11.enemy-model"
local MAP_MODEL_KEY = "test.phase11.map-model"
local BASE_POSITION = Vector3.new(30, 5, 0)

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in next, value do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy
end

local function waveReward(battleCash: number, gold: number): { [string]: any }
	return {
		battleCashStipendPerActivePlayer = battleCash,
		persistentGold = {
			baseAmountPerEligiblePlayer = gold,
		},
	}
end

local function economyRule(difficultyId: string, startingBattleCash: number, denominator: number): { [string]: any }
	return {
		difficultyId = difficultyId,
		startingBattleCash = startingBattleCash,
		damageIncome = {
			battleCashNumerator = 1,
			healthRemovedDenominator = denominator,
			rounding = "Floor",
			accrualScope = "PerPlayerMatch",
		},
		waveRewards = {
			standard = waveReward(25, 0),
			milestone = waveReward(75, 2),
			final = waveReward(150, 10),
		},
	}
end

local function primarySchedule(): { [string]: any }
	return {
		kind = "AuthoredFinite",
		mapId = WaveFixtures.MAP_ID,
		difficultyId = WaveFixtures.PRIMARY_DIFFICULTY_ID,
		waves = {
			{
				id = "wave:phase11-authored-1",
				deadlineSeconds = 12,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "None",
				rewardClass = "Standard",
				groups = {
					{
						enemyId = WaveFixtures.WORKER_ENEMY_ID,
						laneId = WaveFixtures.MAIN_LANE_ID,
						count = 3,
						startDelaySeconds = 0,
						spawnIntervalSeconds = 0,
					},
					{
						enemyId = WaveFixtures.SCOUT_ENEMY_ID,
						laneId = WaveFixtures.ALTERNATE_LANE_ID,
						count = 3,
						startDelaySeconds = 2,
						spawnIntervalSeconds = 2,
					},
					{
						enemyId = WaveFixtures.WORKER_ENEMY_ID,
						laneId = WaveFixtures.MAIN_LANE_ID,
						count = 2,
						startDelaySeconds = 6,
						spawnIntervalSeconds = 3,
					},
				},
			},
			{
				id = "wave:phase11-authored-2",
				deadlineSeconds = 8,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "MiniBoss",
				rewardClass = "Milestone",
				groups = {
					{
						enemyId = WaveFixtures.WORKER_ENEMY_ID,
						laneId = WaveFixtures.ALTERNATE_LANE_ID,
						count = 2,
						startDelaySeconds = 1,
						spawnIntervalSeconds = 2,
					},
				},
			},
			{
				id = "wave:phase11-authored-3",
				deadlineSeconds = 6,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "None",
				rewardClass = "Standard",
				groups = {},
			},
			{
				id = "wave:phase11-authored-4",
				deadlineSeconds = 10,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "Boss",
				rewardClass = "Final",
				groups = {
					{
						enemyId = WaveFixtures.SCOUT_ENEMY_ID,
						laneId = WaveFixtures.MAIN_LANE_ID,
						count = 3,
						startDelaySeconds = 6,
						spawnIntervalSeconds = 2,
					},
				},
			},
		},
	}
end

local function overlapSchedule(): { [string]: any }
	return {
		kind = "AuthoredFinite",
		mapId = WaveFixtures.MAP_ID,
		difficultyId = WaveFixtures.OVERLAP_DIFFICULTY_ID,
		waves = {
			{
				id = "wave:phase11-overlap-1",
				deadlineSeconds = 5,
				deadlinePolicy = "AllowScheduledOverlap",
				bossKind = "None",
				rewardClass = "Standard",
				groups = {
					{
						enemyId = WaveFixtures.WORKER_ENEMY_ID,
						laneId = WaveFixtures.MAIN_LANE_ID,
						count = 3,
						startDelaySeconds = 2,
						spawnIntervalSeconds = 3,
					},
				},
			},
			{
				id = "wave:phase11-overlap-2",
				deadlineSeconds = 8,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "Boss",
				rewardClass = "Final",
				groups = {
					{
						enemyId = WaveFixtures.SCOUT_ENEMY_ID,
						laneId = WaveFixtures.ALTERNATE_LANE_ID,
						count = 2,
						startDelaySeconds = 0,
						spawnIntervalSeconds = 0,
					},
				},
			},
		},
	}
end

function WaveFixtures.rawSources(includeGeneratedEndless: boolean?): RawSources
	local supportedDifficultyIds = {
		WaveFixtures.PRIMARY_DIFFICULTY_ID,
		WaveFixtures.OVERLAP_DIFFICULTY_ID,
	}
	local difficulties = {
		{
			id = WaveFixtures.PRIMARY_DIFFICULTY_ID,
			displayName = "Phase 11 Authored",
			description = "Primary authenticated authored-wave fixture.",
			kind = "Finite",
			waveCount = 4,
			base = { maxHealth = 250 },
			modifiers = {
				enemyHealthMultiplier = 1.25,
				enemyMoveSpeedMultiplier = 0.8,
			},
			timing = {
				earlyClearIntermissionSeconds = 5,
				bossCadenceWaves = 4,
				skipVoteMinimumDelaySeconds = 2,
			},
			tags = { "fixture", "authored" },
		},
		{
			id = WaveFixtures.OVERLAP_DIFFICULTY_ID,
			displayName = "Phase 11 Overlap",
			kind = "Finite",
			waveCount = 2,
			base = { maxHealth = 300 },
			modifiers = {
				enemyHealthMultiplier = 1.5,
				enemyMoveSpeedMultiplier = 1.1,
			},
			timing = {
				earlyClearIntermissionSeconds = 5,
				bossCadenceWaves = 2,
				skipVoteMinimumDelaySeconds = 1,
			},
		},
	}
	local waves = { primarySchedule(), overlapSchedule() }
	local economyRules = {
		economyRule(WaveFixtures.PRIMARY_DIFFICULTY_ID, 375, 5),
		economyRule(WaveFixtures.OVERLAP_DIFFICULTY_ID, 250, 10),
	}

	if includeGeneratedEndless == true then
		table.insert(supportedDifficultyIds, WaveFixtures.ENDLESS_DIFFICULTY_ID)
		table.insert(difficulties, {
			id = WaveFixtures.ENDLESS_DIFFICULTY_ID,
			displayName = "Phase 11 Endless Boundary",
			kind = "Endless",
			base = { maxHealth = 500 },
			modifiers = {
				enemyHealthMultiplier = 2,
				enemyMoveSpeedMultiplier = 1.25,
			},
			timing = {
				earlyClearIntermissionSeconds = 5,
				bossCadenceWaves = 10,
				skipVoteMinimumDelaySeconds = 2,
			},
		})
		table.insert(waves, {
			kind = "GeneratedEndless",
			mapId = WaveFixtures.MAP_ID,
			difficultyId = WaveFixtures.ENDLESS_DIFFICULTY_ID,
			authoredOpeningWaves = {},
			generator = { kind = "EndlessWaveGenerator", key = "endless.phase11-boundary" },
		})
		table.insert(economyRules, economyRule(WaveFixtures.ENDLESS_DIFFICULTY_ID, 200, 20))
	end

	return {
		assets = {
			{ key = ENEMY_MODEL_KEY, kind = "EnemyModel" },
			{ key = MAP_MODEL_KEY, kind = "MapModel" },
		},
		towers = {},
		enemies = {
			{
				id = WaveFixtures.WORKER_ENEMY_ID,
				displayName = "Phase 11 Worker",
				modelAssetKey = ENEMY_MODEL_KEY,
				maxHealth = 80,
				moveSpeedStudsPerSecond = 5,
				leakDamage = 3,
				damageIncomeClass = "EligibleHealthRemoved",
			},
			{
				id = WaveFixtures.SCOUT_ENEMY_ID,
				displayName = "Phase 11 Scout",
				modelAssetKey = ENEMY_MODEL_KEY,
				maxHealth = 40,
				moveSpeedStudsPerSecond = 7.5,
				leakDamage = 1,
				damageIncomeClass = "None",
			},
		},
		difficulties = difficulties,
		maps = {
			{
				id = WaveFixtures.MAP_ID,
				displayName = "Phase 07 Graybox",
				description = "Detached two-lane snapshot fixture.",
				modelAssetKey = MAP_MODEL_KEY,
				lanes = {
					{ id = WaveFixtures.MAIN_LANE_ID },
					{ id = WaveFixtures.ALTERNATE_LANE_ID },
				},
				supportedDifficultyIds = supportedDifficultyIds,
				tags = { "fixture", "graybox" },
			},
		},
		waves = waves,
		economy = {
			version = 1,
			sellRefund = { basisPoints = 7_000, rounding = "Floor" },
			difficultyRules = economyRules,
		},
		banners = {},
		defaultSettings = {
			version = 2,
			masterVolume = 1,
			musicVolume = 0.75,
			sfxVolume = 0.8,
			uiVolume = 0.9,
			cameraShakeIntensity = 0.5,
			damageNumbersEnabled = true,
			enemyHealthBarsEnabled = true,
			otherPlayerEffectsEnabled = true,
			lowDetailEnabled = false,
			reducedMotionEnabled = false,
			towerRangeEnabled = true,
			uiScale = 1,
		},
	}
end

function WaveFixtures.clone<T>(value: T): T
	return deepCopy(value)
end

local function routePoint(
	kind: RoutePointKind,
	nodeOrder: number?,
	position: Vector3,
	distance: number
): RoutePointSnapshot
	return table.freeze({
		kind = kind,
		nodeOrder = nodeOrder,
		cframe = CFrame.new(position),
		position = position,
		distance = distance,
	})
end

local function runtimeLane(id: string, positions: { Vector3 }): RuntimeLaneSnapshot
	local points: { RoutePointSnapshot } = {}
	local distance = 0
	for index, position in positions do
		if index > 1 then
			distance += (position - positions[index - 1]).Magnitude
		end

		local kind: RoutePointKind
		local nodeOrder: number? = nil
		if index == 1 then
			kind = "EnemySpawn"
		elseif index == #positions then
			kind = "DefenderBase"
		else
			kind = "PathNode"
			nodeOrder = index - 1
		end
		table.insert(points, routePoint(kind, nodeOrder, position, distance))
	end

	return table.freeze({
		id = id,
		totalDistance = distance,
		points = table.freeze(points),
	})
end

local function pointSnapshot(position: Vector3): PointSnapshot
	return table.freeze({
		cframe = CFrame.new(position),
		position = position,
	})
end

local function regionSnapshot(id: string, cframe: CFrame, size: Vector3): RegionSnapshot
	return table.freeze({
		id = id,
		cframe = cframe,
		size = size,
	})
end

local function namedPointSnapshot(id: string, position: Vector3): NamedPointSnapshot
	return table.freeze({
		id = id,
		cframe = CFrame.new(position),
		position = position,
	})
end

function WaveFixtures.createRuntimeMapSnapshot(): RuntimeMapSnapshot
	local mapIdResult = Ids.validateMapId(WaveFixtures.MAP_ID)
	if not mapIdResult.ok then
		error("Phase 11 fixture MapId failed production validation", 0)
	end

	return table.freeze({
		mapId = mapIdResult.value,
		base = pointSnapshot(BASE_POSITION),
		bounds = table.freeze({
			cframe = CFrame.new(0, 5, 0),
			size = Vector3.new(100, 20, 80),
		}),
		lanes = table.freeze({
			runtimeLane(WaveFixtures.MAIN_LANE_ID, {
				Vector3.new(-40, 5, -20),
				Vector3.new(-15, 5, -20),
				Vector3.new(0, 5, 0),
				BASE_POSITION,
			}),
			runtimeLane(WaveFixtures.ALTERNATE_LANE_ID, {
				Vector3.new(-40, 5, 20),
				Vector3.new(-10, 5, 20),
				Vector3.new(0, 5, 0),
				BASE_POSITION,
			}),
		}),
		placementZones = table.freeze({
			regionSnapshot("fixture-land", CFrame.new(0, 0, 0), Vector3.new(90, 2, 70)),
		}),
		noPlacementZones = table.freeze({
			regionSnapshot("fixture-route", CFrame.new(-5, 0, 0), Vector3.new(70, 1, 8)),
		}),
		cameraAnchors = table.freeze({
			namedPointSnapshot("fixture-overview", Vector3.new(0, 45, 55)),
		}),
		playerSpawns = table.freeze({
			namedPointSnapshot("fixture-player", Vector3.new(35, 5, 15)),
		}),
	})
end

local function runtimeMapMatches(runtimeMap: unknown, mapDefinition: ConfigTypes.MapDefinition): boolean
	if type(runtimeMap) ~= "table" or not table.isfrozen(runtimeMap) then
		return false
	end

	local snapshot = runtimeMap :: any
	if snapshot.mapId ~= mapDefinition.id or type(snapshot.lanes) ~= "table" then
		return false
	end
	if #snapshot.lanes ~= #mapDefinition.lanes then
		return false
	end

	for index, lane in mapDefinition.lanes do
		local runtimeLaneAtIndex = snapshot.lanes[index]
		if type(runtimeLaneAtIndex) ~= "table" or runtimeLaneAtIndex.id ~= lane.id then
			return false
		end
	end
	return true
end

function WaveFixtures.selectAuthoredFinite(
	configuration: unknown,
	runtimeMap: unknown,
	difficultyId: unknown
): (FiniteSelection?, string?)
	if not ConfigurationValidator.isValidatedConfiguration(configuration) then
		return nil, WaveFixtures.INVALID_CONFIGURATION
	end

	local canonical = configuration :: ConfigTypes.CoreConfiguration
	local mapDefinition = canonical.maps.byId[WaveFixtures.MAP_ID]
	if mapDefinition == nil or not runtimeMapMatches(runtimeMap, mapDefinition) then
		return nil, WaveFixtures.INVALID_RUNTIME_MAP
	end
	if type(difficultyId) ~= "string" then
		return nil, WaveFixtures.DIFFICULTY_NOT_FOUND
	end

	local difficulty = canonical.difficulties.byId[difficultyId :: any]
	if difficulty == nil then
		return nil, WaveFixtures.DIFFICULTY_NOT_FOUND
	end
	local schedule = canonical.waves.byMapId[mapDefinition.id][difficulty.id]
	if schedule == nil then
		return nil, WaveFixtures.SCHEDULE_NOT_FOUND
	end
	if difficulty.kind ~= "Finite" or schedule.kind ~= "AuthoredFinite" then
		return nil, WaveFixtures.GENERATED_ENDLESS_UNSUPPORTED
	end

	local economy = canonical.economy.byDifficultyId[difficulty.id]
	if economy == nil then
		return nil, WaveFixtures.ECONOMY_RULE_NOT_FOUND
	end

	return table.freeze({
		mapDefinition = mapDefinition,
		difficultyDefinition = difficulty,
		schedule = schedule,
		economyRule = economy,
		runtimeMetadata = table.freeze({
			difficultyId = difficulty.id,
			enemyHealthMultiplier = difficulty.modifiers.enemyHealthMultiplier,
			enemyMoveSpeedMultiplier = difficulty.modifiers.enemyMoveSpeedMultiplier,
			startingBattleCash = economy.startingBattleCash,
		}),
	}),
		nil
end

function WaveFixtures.authenticateSources(rawSources: RawSources): AuthenticatedFixture
	local result = ConfigurationValidator.validate(rawSources)
	if not result.ok then
		error("Phase 11 fixture configuration failed production validation", 0)
	end
	local configuration = result.value
	if not ConfigurationValidator.isValidatedConfiguration(configuration) then
		error("Phase 11 fixture configuration was not authenticated", 0)
	end

	local runtimeMap = WaveFixtures.createRuntimeMapSnapshot()
	local primary, primaryError =
		WaveFixtures.selectAuthoredFinite(configuration, runtimeMap, WaveFixtures.PRIMARY_DIFFICULTY_ID)
	if primary == nil then
		error("Phase 11 primary selection failed: " .. (primaryError or "UNKNOWN"), 0)
	end
	local overlap, overlapError =
		WaveFixtures.selectAuthoredFinite(configuration, runtimeMap, WaveFixtures.OVERLAP_DIFFICULTY_ID)
	if overlap == nil then
		error("Phase 11 overlap selection failed: " .. (overlapError or "UNKNOWN"), 0)
	end

	return table.freeze({
		rawSources = rawSources,
		configuration = configuration,
		runtimeMap = runtimeMap,
		primary = primary,
		overlap = overlap,
	})
end

function WaveFixtures.createAuthenticatedFixture(): AuthenticatedFixture
	return WaveFixtures.authenticateSources(WaveFixtures.rawSources())
end

return table.freeze(WaveFixtures)
