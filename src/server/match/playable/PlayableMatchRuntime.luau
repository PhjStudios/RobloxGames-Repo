--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local ContentSelection = require(ReplicatedStorage.Shared.config.ContentSelection)
local MatchLoadoutProtocol = require(ReplicatedStorage.Shared.match.MatchLoadoutProtocol)
local PlacementGeometry = require(ReplicatedStorage.Shared.match.PlacementGeometry)
local PlayableMatchProtocol = require(ReplicatedStorage.Shared.match.PlayableMatchProtocol)
local RewardProtocol = require(ReplicatedStorage.Shared.match.RewardProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local BattleCashLedger = require(script.Parent.BattleCashLedger)
local DirectStudioParticipantLoadout = require(script.Parent.DirectStudioParticipantLoadout)
local EndlessWaveGenerator = require(script.Parent.EndlessWaveGenerator)
local TargetQuery = require(script.Parent.TargetQuery)

export type RuntimeMap = {
	mapId: string,
	base: { cframe: CFrame, position: Vector3 },
	bounds: { cframe: CFrame, size: Vector3 },
	lanes: {
		{
			id: string,
			totalDistance: number,
			points: {
				{
					kind: string,
					nodeOrder: number?,
					cframe: CFrame,
					position: Vector3,
					distance: number,
				}
			},
		}
	},
	placementZones: { { id: string, cframe: CFrame, size: Vector3 } },
	noPlacementZones: { { id: string, cframe: CFrame, size: Vector3 } },
	cameraAnchors: { { id: string, cframe: CFrame, position: Vector3 } },
	playerSpawns: { { id: string, cframe: CFrame, position: Vector3 } },
}

export type Dependencies = {
	matchId: string,
	mapId: string?,
	difficultyId: string?,
	configuration: ConfigTypes.CoreConfiguration,
	runtimeMap: RuntimeMap,
	participantLoadouts: { MatchLoadoutProtocol.Snapshot },
	connectedParticipantUserIds: { number }?,
	rewarding: boolean?,
	studioDirectUserIds: boolean?,
	seed: number?,
}

export type ActionOutcome = {
	accepted: boolean,
	reason: PlayableMatchProtocol.ActionReason,
}

export type AttackEvent = PlayableMatchProtocol.AttackEvent

export type StepOutcome = {
	serverTime: number,
	changed: boolean,
	attacks: { AttackEvent },
}

export type Metrics = {
	state: PlayableMatchProtocol.MatchState,
	result: PlayableMatchProtocol.MatchResult,
	revision: number,
	waveNumber: number,
	wavesCompleted: number,
	activeTowerCount: number,
	activeEnemyCount: number,
	attackCount: number,
	participantCount: number,
	connectedParticipantCount: number,
	readyCount: number,
	rewarding: boolean,
	modeKind: "Finite" | "Endless",
	seed: number,
	contentVersion: number,
	activeWaveOriginCount: number,
	cleaned: boolean,
}

export type ResultParticipantEvidence = {
	userId: number,
	authenticatedParticipant: boolean,
	spectator: boolean,
	submittedReady: boolean,
	placements: number,
	wavesCompleted: number,
	connectedAtResults: boolean,
	battleCashEarned: number,
	battleCashSpent: number,
}

export type ResultEvidence = {
	matchId: Ids.MatchId,
	mapId: Ids.MapId,
	difficultyId: Ids.DifficultyId,
	outcome: "Victory" | "Defeat",
	modeKind: "Finite" | "Endless",
	highestCompletedWave: number,
	elapsedSeconds: number,
	seed: number,
	contentVersion: number,
	terminationReason: PlayableMatchProtocol.TerminationReason,
	rewardingMatch: boolean,
	entries: { ResultParticipantEvidence },
}

export type ErrorCode =
	"INVALID_DEPENDENCIES"
	| "UNAUTHENTICATED_CONFIGURATION"
	| "CONTENT_NOT_FOUND"
	| "INVALID_RUNTIME_MAP"
	| "INVALID_PARTICIPANTS"
	| "LEDGER_FAILED"
	| "INVALID_TIME"
	| "WRONG_STATE"
	| "CLEANED"
	| "INTERNAL_ERROR"

export type ErrorOperation = "new" | "step" | "snapshot" | "resultEvidence" | "cleanup"
export type RuntimeError = { code: ErrorCode, operation: ErrorOperation }

type NormalizedRegion = { cframe: CFrame, size: Vector3 }
type NormalizedPlacementZone = { cframe: CFrame, size: Vector3, surfaceCategory: "Land" }
type PathPoint = { position: Vector3, distance: number }

type TowerRecord = {
	runtimeTowerId: number,
	revision: number,
	definition: ConfigTypes.TowerDefinition,
	ownerUserId: number,
	level: number,
	targetMode: ConfigTypes.TargetMode,
	position: Vector3,
	rotationDegrees: number,
	totalInvestment: number,
	cooldownEndsServerTime: number,
}

type EnemyRecord = {
	runtimeEnemyId: number,
	definition: ConfigTypes.EnemyDefinition,
	currentHealth: number,
	maximumHealth: number,
	moveSpeed: number,
	pathProgress: number,
	position: Vector3,
	spawnServerTime: number,
	originWaveNumber: number,
}

type SpawnEntry = {
	spawnServerTime: number,
	groupIndex: number,
	memberIndex: number,
	definition: ConfigTypes.EnemyDefinition,
	originWaveNumber: number,
	healthMultiplier: number,
	moveSpeedMultiplier: number,
}

type WaveOrigin = {
	wave: ConfigTypes.AuthoredWaveDefinition,
	aliveCount: number,
	resolved: boolean,
}

type ParticipantStats = {
	damageDealt: number,
	placements: number,
	upgrades: number,
	sells: number,
	wavesParticipated: number,
	lastCreditedWave: number,
}

type RuntimeData = {
	matchId: Ids.MatchId,
	configuration: ConfigTypes.CoreConfiguration,
	mapDefinition: ConfigTypes.MapDefinition,
	difficulty: ConfigTypes.DifficultyDefinition,
	schedule: ConfigTypes.WaveScheduleDefinition,
	modeKind: "Finite" | "Endless",
	seed: number,
	contentVersion: number,
	economy: ConfigTypes.DifficultyEconomyDefinition,
	ledger: BattleCashLedger.Ledger,
	state: PlayableMatchProtocol.MatchState,
	result: PlayableMatchProtocol.MatchResult,
	wavePhase: PlayableMatchProtocol.WavePhase,
	revision: number,
	participants: { number },
	participantSet: { [number]: boolean },
	connectedParticipantSet: { [number]: boolean },
	everConnectedParticipantSet: { [number]: boolean },
	loadoutsByUserId: { [number]: MatchLoadoutProtocol.Snapshot },
	ready: { [number]: boolean },
	participantStats: { [number]: ParticipantStats },
	submittedReady: { [number]: boolean },
	connectedAtResults: { [number]: boolean },
	rewardViewsByUserId: { [number]: RewardProtocol.RewardView },
	rewarding: boolean,
	studioDirectUserIds: boolean,
	path: { PathPoint },
	pathTotalDistance: number,
	basePosition: Vector3,
	bounds: NormalizedRegion,
	placementZones: { NormalizedPlacementZone },
	exclusions: { NormalizedRegion },
	towers: { [number]: TowerRecord },
	enemies: { [number]: EnemyRecord },
	nextTowerId: number,
	nextEnemyId: number,
	attackSequence: number,
	waveNumber: number,
	wavesCompleted: number,
	currentWave: ConfigTypes.AuthoredWaveDefinition?,
	waveOrigins: { [number]: WaveOrigin },
	resolvedWaveNumbers: { [number]: WaveOrigin },
	activeWaveOriginCount: number,
	spawnQueue: { SpawnEntry },
	spawnCursor: number,
	nextWaveServerTime: number,
	startedServerTime: number,
	endedServerTime: number,
	lastSimulationServerTime: number,
	terminationReason: PlayableMatchProtocol.TerminationReason?,
	baseHealth: number,
	busy: boolean,
	cleaned: boolean,
}

local Methods = {}
Methods.__index = Methods

export type Runtime = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: RuntimeData }

local MAX_STEP_SECONDS = 0.25
local FIXED_STEP_SECONDS = 0.05
local MAX_FIXED_STEPS_PER_CALL = 5
local MAX_SPAWNS_PER_STEP = 8
local MAX_ATTACKS_PER_STEP = 64
local PREPARE_SECONDS = 6
local MAX_PARTICIPANTS = 4
local MAX_SPAWNS_PER_WAVE = 96
local MAX_ACTIVE_WAVE_ORIGINS = 4
local MAX_ENEMY_HEALTH = 1_000_000
local MAX_ENEMY_MOVE_SPEED = 24
local MAX_RESULT_COUNTER = 1_000_000_000_000
local BASIS_POINTS_PER_WHOLE = 10_000
local MAX_TOWERS = PlayableMatchProtocol.MAX_ACTIVE_TOWERS
local MAX_ENEMIES = PlayableMatchProtocol.MAX_ACTIVE_ENEMIES
local DEVELOPMENT_MAP_ID = ContentSelection.DEVELOPMENT_MAP_ID
local DEVELOPMENT_DIFFICULTY_ID = ContentSelection.DEVELOPMENT_DIFFICULTY_ID

local ACCEPTED: ActionOutcome = table.freeze({ accepted = true, reason = "Accepted" })

local PlayableMatchRuntime = {
	MAX_STEP_SECONDS = MAX_STEP_SECONDS,
	FIXED_STEP_SECONDS = FIXED_STEP_SECONDS,
	MAX_FIXED_STEPS_PER_CALL = MAX_FIXED_STEPS_PER_CALL,
	MAX_SPAWNS_PER_STEP = MAX_SPAWNS_PER_STEP,
	MAX_ATTACKS_PER_STEP = MAX_ATTACKS_PER_STEP,
	MAX_SPAWNS_PER_WAVE = MAX_SPAWNS_PER_WAVE,
	MAX_ACTIVE_WAVE_ORIGINS = MAX_ACTIVE_WAVE_ORIGINS,
	MAX_ENEMY_HEALTH = MAX_ENEMY_HEALTH,
	MAX_ENEMY_MOVE_SPEED = MAX_ENEMY_MOVE_SPEED,
	PREPARE_SECONDS = PREPARE_SECONDS,
	MAX_TOWERS = MAX_TOWERS,
	MAX_ENEMIES = MAX_ENEMIES,
	DEVELOPMENT_MAP_ID = DEVELOPMENT_MAP_ID,
	DEVELOPMENT_DIFFICULTY_ID = DEVELOPMENT_DIFFICULTY_ID,
}

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "PlayableMatchRuntime" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionServerPlayable" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

local IS_EXACT_TEST_MODULE = isExactTestModule()

local function errorResult(code: ErrorCode, operation: ErrorOperation): Result.Failure<RuntimeError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function reject(reason: PlayableMatchProtocol.ActionReason): ActionOutcome
	return table.freeze({ accepted = false, reason = reason })
end

local function requireData(value: unknown): RuntimeData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_PLAYABLE_MATCH_RUNTIME][code=INVALID_CONTEXT]", 0)
	end
	return data :: RuntimeData
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and Validation.isFiniteNumber(value :: number)
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and value ~= 0
end

local function countDictionary(value: { [number]: unknown }): number
	local count = 0
	for _ in value do
		count += 1
	end
	return count
end

local function advanceRevision(data: RuntimeData): boolean
	if data.revision >= Validation.MAX_SAFE_INTEGER then
		return false
	end
	data.revision += 1
	return true
end

local function checkedIncrement(value: number): number?
	if value >= Validation.MAX_SAFE_INTEGER then
		return nil
	end
	return value + 1
end

local function boundedAdd(left: number, right: number): number
	return math.min(MAX_RESULT_COUNTER, left + math.min(right, MAX_RESULT_COUNTER))
end

local function floorBasisPoints(amount: number, basisPoints: number): number
	local whole = math.floor(amount / BASIS_POINTS_PER_WHOLE)
	local remainder = amount - whole * BASIS_POINTS_PER_WHOLE
	return whole * basisPoints + math.floor(remainder * basisPoints / BASIS_POINTS_PER_WHOLE)
end

local function beginMutation(data: RuntimeData): boolean
	if data.cleaned or data.busy then
		return false
	end
	data.busy = true
	return true
end

local function finishMutation(data: RuntimeData)
	data.busy = false
end

local function normalizeParticipants(
	value: unknown,
	configuration: ConfigTypes.CoreConfiguration,
	studioDirectUserIds: boolean
): ({ number }?, { [number]: MatchLoadoutProtocol.Snapshot }?)
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil, nil
	end
	local source = value :: { unknown }
	if #source > MAX_PARTICIPANTS then
		return nil, nil
	end
	local copy: { number } = {}
	local loadoutsByUserId: { [number]: MatchLoadoutProtocol.Snapshot } = {}
	local seen: { [number]: boolean } = {}
	for _, candidate in source do
		local candidateUserId = if type(candidate) == "table" then rawget(candidate :: any, "userId") else nil
		local validated: any = if studioDirectUserIds
				and type(candidateUserId) == "number"
				and candidateUserId < 0
			then DirectStudioParticipantLoadout.validate(candidate, configuration)
			else MatchLoadoutProtocol.validate(candidate, configuration)
		if not validated.ok or seen[validated.value.userId] then
			return nil, nil
		end
		local snapshot = validated.value
		seen[snapshot.userId] = true
		loadoutsByUserId[snapshot.userId] = snapshot
		table.insert(copy, snapshot.userId)
	end
	return copy, loadoutsByUserId
end

local function normalizeConnectedParticipants(
	value: unknown,
	participants: { number },
	participantSet: { [number]: boolean }
): { [number]: boolean }?
	if value == nil then
		local allConnected: { [number]: boolean } = {}
		for _, userId in participants do
			allConnected[userId] = true
		end
		return allConnected
	end
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local connected: { [number]: boolean } = {}
	for _, userId in value :: { unknown } do
		if not validUserId(userId) or not participantSet[userId :: number] or connected[userId :: number] then
			return nil
		end
		connected[userId :: number] = true
	end
	return connected
end

local function normalizeMap(
	value: unknown,
	expectedMapId: string,
	expectedLaneId: string
): (
	{ PathPoint }?,
	number?,
	Vector3?,
	NormalizedRegion?,
	{ NormalizedPlacementZone }?,
	{ NormalizedRegion }?
)
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil, nil, nil, nil, nil, nil
	end
	local map = value :: any
	if map.mapId ~= expectedMapId or type(map.lanes) ~= "table" or #map.lanes ~= 1 then
		return nil, nil, nil, nil, nil, nil
	end
	local lane = map.lanes[1]
	if type(lane) ~= "table" or lane.id ~= expectedLaneId or type(lane.points) ~= "table" or #lane.points < 2 then
		return nil, nil, nil, nil, nil, nil
	end
	local points: { PathPoint } = {}
	local previousDistance = -1
	for _, point in lane.points do
		if
			type(point) ~= "table"
			or typeof(point.position) ~= "Vector3"
			or not isFiniteNumber(point.distance)
			or point.distance < 0
			or point.distance <= previousDistance
		then
			return nil, nil, nil, nil, nil, nil
		end
		previousDistance = point.distance
		table.insert(points, { position = point.position, distance = point.distance })
	end
	if points[1].distance ~= 0 or not isFiniteNumber(lane.totalDistance) or lane.totalDistance ~= previousDistance then
		return nil, nil, nil, nil, nil, nil
	end
	if type(map.base) ~= "table" or typeof(map.base.position) ~= "Vector3" or type(map.bounds) ~= "table" then
		return nil, nil, nil, nil, nil, nil
	end
	local bounds = { cframe = map.bounds.cframe, size = map.bounds.size }
	if PlacementGeometry.groundHeight(bounds) == nil then
		return nil, nil, nil, nil, nil, nil
	end
	if type(map.placementZones) ~= "table" or #map.placementZones < 1 or type(map.noPlacementZones) ~= "table" then
		return nil, nil, nil, nil, nil, nil
	end
	local zones: { NormalizedPlacementZone } = {}
	for _, rawZone in map.placementZones do
		if type(rawZone) ~= "table" then
			return nil, nil, nil, nil, nil, nil
		end
		local zone: NormalizedPlacementZone = {
			cframe = rawZone.cframe,
			size = rawZone.size,
			surfaceCategory = "Land",
		}
		if PlacementGeometry.groundHeight(zone) == nil then
			return nil, nil, nil, nil, nil, nil
		end
		table.insert(zones, zone)
	end
	local exclusions: { NormalizedRegion } = {}
	for _, rawExclusion in map.noPlacementZones do
		if type(rawExclusion) ~= "table" then
			return nil, nil, nil, nil, nil, nil
		end
		local exclusion = { cframe = rawExclusion.cframe, size = rawExclusion.size }
		if PlacementGeometry.groundHeight(exclusion) == nil then
			return nil, nil, nil, nil, nil, nil
		end
		table.insert(exclusions, exclusion)
	end
	return points, lane.totalDistance, map.base.position, bounds, zones, exclusions
end

local function playableWaveValid(
	wave: ConfigTypes.AuthoredWaveDefinition,
	laneId: string,
	configuration: ConfigTypes.CoreConfiguration
): boolean
	if #wave.groups < 1 or #wave.groups > EndlessWaveGenerator.MAX_GROUPS then
		return false
	end
	local spawnCount = 0
	for _, group in wave.groups do
		if group.laneId ~= laneId or configuration.enemies.byId[group.enemyId] == nil then
			return false
		end
		spawnCount += group.count
		if spawnCount > MAX_SPAWNS_PER_WAVE then
			return false
		end
	end
	return true
end

local function supportedAttackContent(configuration: ConfigTypes.CoreConfiguration): boolean
	for _, definition in configuration.towers.ordered do
		for _, level in definition.levels do
			local attack = level.attack
			if attack ~= nil then
				local key = attack.behavior.key
				if key ~= "attack.direct" and key ~= "attack.single-target" and key ~= "attack.splash" then
					return false
				end
				if key == "attack.splash" then
					local rawAttack = attack :: any
					if
						not isFiniteNumber(rawAttack.splashRadiusStuds)
						or rawAttack.splashRadiusStuds <= 0
						or (
							rawAttack.splashDamageMultiplier ~= nil
							and (
								not isFiniteNumber(rawAttack.splashDamageMultiplier)
								or rawAttack.splashDamageMultiplier <= 0
								or rawAttack.splashDamageMultiplier > 1
							)
						)
					then
						return false
					end
				end
			end
		end
	end
	return true
end

local function positionAtProgress(data: RuntimeData, progressValue: number): Vector3
	local progress = math.clamp(progressValue, 0, data.pathTotalDistance)
	for index = 2, #data.path do
		local nextPoint = data.path[index]
		if progress <= nextPoint.distance then
			local previous = data.path[index - 1]
			local segmentDistance = nextPoint.distance - previous.distance
			local alpha = if segmentDistance <= 0 then 1 else (progress - previous.distance) / segmentDistance
			return previous.position:Lerp(nextPoint.position, math.clamp(alpha, 0, 1))
		end
	end
	return data.path[#data.path].position
end

local function activeReadyCount(data: RuntimeData): number
	local count = 0
	for _, userId in data.participants do
		if data.connectedParticipantSet[userId] and data.ready[userId] then
			count += 1
		end
	end
	return count
end

local function connectedParticipantCount(data: RuntimeData): number
	return countDictionary(data.connectedParticipantSet)
end

local function startPlaying(data: RuntimeData, serverTime: number)
	data.state = "Playing"
	data.wavePhase = "Intermission"
	data.startedServerTime = serverTime
	data.lastSimulationServerTime = serverTime
	data.nextWaveServerTime = serverTime + PREPARE_SECONDS
	advanceRevision(data)
end

local function allParticipantsReady(data: RuntimeData): boolean
	local connectedCount = connectedParticipantCount(data)
	return connectedCount > 0 and activeReadyCount(data) == connectedCount
end

local function footprints(data: RuntimeData): { Vector3 }
	local output: { Vector3 } = {}
	for _, tower in data.towers do
		table.insert(output, Vector3.new(tower.position.X, tower.definition.footprintRadiusStuds, tower.position.Z))
	end
	return output
end

local function perTypeCount(data: RuntimeData, ownerUserId: number, towerId: string): number
	local count = 0
	for _, tower in data.towers do
		if tower.ownerUserId == ownerUserId and tower.definition.id == towerId then
			count += 1
		end
	end
	return count
end

local function towerIds(data: RuntimeData): { number }
	local ids: { number } = {}
	for runtimeTowerId in data.towers do
		table.insert(ids, runtimeTowerId)
	end
	table.sort(ids)
	return ids
end

local function enemyIds(data: RuntimeData): { number }
	local ids: { number } = {}
	for runtimeEnemyId in data.enemies do
		table.insert(ids, runtimeEnemyId)
	end
	table.sort(ids)
	return ids
end

local function finishMatch(
	data: RuntimeData,
	result: "Victory" | "Defeat",
	terminationReason: PlayableMatchProtocol.TerminationReason,
	serverTime: number
): boolean
	if data.state == "Results" then
		return false
	end
	data.state = "Results"
	data.result = result
	data.terminationReason = terminationReason
	data.endedServerTime = math.max(data.startedServerTime, serverTime)
	data.wavePhase = "Results"
	data.nextWaveServerTime = 0
	table.clear(data.spawnQueue)
	data.spawnCursor = 1
	table.clear(data.enemies)
	table.clear(data.waveOrigins)
	table.clear(data.resolvedWaveNumbers)
	data.activeWaveOriginCount = 0
	for _, userId in data.participants do
		data.connectedAtResults[userId] = data.connectedParticipantSet[userId] == true
	end
	return advanceRevision(data)
end

local function waveFor(data: RuntimeData, waveNumber: number): (ConfigTypes.AuthoredWaveDefinition?, number?, number?)
	if data.schedule.kind == "AuthoredFinite" then
		local wave = data.schedule.waves[waveNumber]
		return wave, if wave == nil then nil else 1, if wave == nil then nil else 1
	end
	local opening = data.schedule.authoredOpeningWaves[waveNumber]
	if opening ~= nil then
		return opening, 1, 1
	end
	local generated = EndlessWaveGenerator.generate(
		data.configuration,
		data.schedule.generator.key,
		data.seed,
		waveNumber,
		data.mapDefinition.lanes[1].id
	)
	if not generated.ok then
		return nil, nil, nil
	end
	return generated.value.wave, generated.value.healthMultiplier, generated.value.moveSpeedMultiplier
end

local function buildSpawnQueue(
	data: RuntimeData,
	waveNumber: number,
	wave: ConfigTypes.AuthoredWaveDefinition,
	serverTime: number,
	healthMultiplier: number,
	moveSpeedMultiplier: number
): boolean
	local queue: { SpawnEntry } = {}
	for groupIndex, group in wave.groups do
		local definition = data.configuration.enemies.byId[group.enemyId]
		if definition == nil or #queue + group.count > MAX_SPAWNS_PER_WAVE then
			return false
		end
		for memberIndex = 1, group.count do
			table.insert(queue, {
				spawnServerTime = serverTime + group.startDelaySeconds + (memberIndex - 1) * group.spawnIntervalSeconds,
				groupIndex = groupIndex,
				memberIndex = memberIndex,
				definition = definition,
				originWaveNumber = waveNumber,
				healthMultiplier = healthMultiplier,
				moveSpeedMultiplier = moveSpeedMultiplier,
			})
		end
	end
	table.sort(queue, function(left, right)
		if left.spawnServerTime ~= right.spawnServerTime then
			return left.spawnServerTime < right.spawnServerTime
		end
		if left.groupIndex ~= right.groupIndex then
			return left.groupIndex < right.groupIndex
		end
		return left.memberIndex < right.memberIndex
	end)
	data.spawnQueue = queue
	data.spawnCursor = 1
	return true
end

local function startNextWave(data: RuntimeData, serverTime: number): boolean
	local nextWave = data.waveNumber + 1
	if nextWave > MAX_RESULT_COUNTER then
		return finishMatch(data, "Defeat", "TechnicalTermination", serverTime)
	end
	if
		data.modeKind == "Finite"
		and nextWave > (data.difficulty :: ConfigTypes.FiniteDifficultyDefinition).waveCount
	then
		return false
	end
	if data.activeWaveOriginCount >= MAX_ACTIVE_WAVE_ORIGINS or data.spawnCursor <= #data.spawnQueue then
		return false
	end
	local wave, healthMultiplier, moveSpeedMultiplier = waveFor(data, nextWave)
	if wave == nil or healthMultiplier == nil or moveSpeedMultiplier == nil then
		return finishMatch(data, "Defeat", "TechnicalTermination", serverTime)
	end
	if not buildSpawnQueue(data, nextWave, wave, serverTime, healthMultiplier, moveSpeedMultiplier) then
		return finishMatch(data, "Defeat", "TechnicalTermination", serverTime)
	end
	data.waveNumber = nextWave
	data.currentWave = wave
	data.waveOrigins[nextWave] = {
		wave = wave,
		aliveCount = 0,
		resolved = false,
	}
	data.activeWaveOriginCount += 1
	data.wavePhase = "Spawning"
	local finiteFinal = data.modeKind == "Finite"
		and nextWave >= (data.difficulty :: ConfigTypes.FiniteDifficultyDefinition).waveCount
	data.nextWaveServerTime = if finiteFinal then 0 else serverTime + wave.deadlineSeconds
	return advanceRevision(data)
end

local function spawnDueEnemies(data: RuntimeData, serverTime: number): boolean
	local changed = false
	local spawned = 0
	while data.spawnCursor <= #data.spawnQueue and spawned < MAX_SPAWNS_PER_STEP do
		local entry = data.spawnQueue[data.spawnCursor]
		if entry.spawnServerTime > serverTime or countDictionary(data.enemies) >= MAX_ENEMIES then
			break
		end
		local runtimeEnemyId = data.nextEnemyId
		local nextId = checkedIncrement(runtimeEnemyId)
		if nextId == nil then
			break
		end
		local maximumHealth = math.clamp(
			math.floor(
				entry.definition.maxHealth * data.difficulty.modifiers.enemyHealthMultiplier * entry.healthMultiplier
					+ 0.5
			),
			1,
			MAX_ENEMY_HEALTH
		)
		local origin = data.waveOrigins[entry.originWaveNumber]
		if origin == nil then
			return changed
		end
		data.enemies[runtimeEnemyId] = {
			runtimeEnemyId = runtimeEnemyId,
			definition = entry.definition,
			currentHealth = maximumHealth,
			maximumHealth = maximumHealth,
			moveSpeed = math.clamp(
				entry.definition.moveSpeedStudsPerSecond
					* data.difficulty.modifiers.enemyMoveSpeedMultiplier
					* entry.moveSpeedMultiplier,
				0.1,
				MAX_ENEMY_MOVE_SPEED
			),
			pathProgress = 0,
			position = data.path[1].position,
			spawnServerTime = entry.spawnServerTime,
			originWaveNumber = entry.originWaveNumber,
		}
		origin.aliveCount += 1
		data.nextEnemyId = nextId
		data.spawnCursor += 1
		spawned += 1
		changed = true
	end
	if data.spawnCursor > #data.spawnQueue and data.wavePhase == "Spawning" then
		data.wavePhase = "Resolving"
		changed = true
	end
	return changed
end

local function removeEnemy(data: RuntimeData, enemy: EnemyRecord)
	data.enemies[enemy.runtimeEnemyId] = nil
	local origin = data.waveOrigins[enemy.originWaveNumber]
	if origin ~= nil then
		origin.aliveCount = math.max(0, origin.aliveCount - 1)
	end
end

local function moveEnemies(data: RuntimeData, elapsed: number, serverTime: number): boolean
	if elapsed <= 0 then
		return false
	end
	local changed = false
	for _, runtimeEnemyId in enemyIds(data) do
		local enemy = data.enemies[runtimeEnemyId]
		if enemy ~= nil then
			enemy.pathProgress = math.min(data.pathTotalDistance, enemy.pathProgress + enemy.moveSpeed * elapsed)
			enemy.position = positionAtProgress(data, enemy.pathProgress)
			changed = true
			if enemy.pathProgress >= data.pathTotalDistance then
				removeEnemy(data, enemy)
				data.baseHealth = math.max(0, data.baseHealth - enemy.definition.leakDamage)
				if data.baseHealth == 0 then
					finishMatch(data, "Defeat", "BaseDefeated", serverTime)
					return true
				end
			end
		end
	end
	return changed
end

local function targetCandidates(data: RuntimeData): { TargetQuery.TargetableEnemy }
	local candidates: { TargetQuery.TargetableEnemy } = {}
	for _, runtimeEnemyId in enemyIds(data) do
		local enemy = data.enemies[runtimeEnemyId]
		if enemy ~= nil then
			table.insert(candidates, {
				runtimeEnemyId = runtimeEnemyId,
				pathProgress = enemy.pathProgress,
				currentHealth = enemy.currentHealth,
				lifecycle = "Active",
				worldCFrame = CFrame.new(enemy.position),
			})
		end
	end
	return candidates
end

local function applyAttackDamage(
	data: RuntimeData,
	tower: TowerRecord,
	target: EnemyRecord,
	damage: number,
	serverTime: number
): AttackEvent?
	local actualDamage = math.min(math.max(0, math.floor(damage + 0.5)), target.currentHealth)
	if actualDamage <= 0 then
		return nil
	end
	local nextSequence = checkedIncrement(data.attackSequence)
	if nextSequence == nil then
		finishMatch(data, "Defeat", "TechnicalTermination", serverTime)
		return nil
	end
	local incomeResult = data.ledger:recordAuthoritativeDamageIncome(
		tower.ownerUserId,
		actualDamage,
		target.definition.damageIncomeClass == "EligibleHealthRemoved"
	)
	if not incomeResult.ok then
		finishMatch(data, "Defeat", "TechnicalTermination", serverTime)
		return nil
	end
	data.attackSequence = nextSequence
	target.currentHealth -= actualDamage
	local killed = target.currentHealth == 0
	local targetPosition = target.position
	local stats = data.participantStats[tower.ownerUserId]
	if stats ~= nil then
		stats.damageDealt = boundedAdd(stats.damageDealt, actualDamage)
	end
	if killed then
		removeEnemy(data, target)
	end
	return table.freeze({
		matchId = data.matchId,
		sequence = data.attackSequence,
		runtimeTowerId = tower.runtimeTowerId,
		runtimeEnemyId = target.runtimeEnemyId,
		sourcePosition = tower.position,
		targetPosition = targetPosition,
		actualDamage = actualDamage,
		killed = killed,
		serverTime = serverTime,
	})
end

type AttackBehavior = (
	RuntimeData,
	TowerRecord,
	ConfigTypes.TowerAttackDefinition,
	EnemyRecord,
	number,
	number
) -> { AttackEvent }

local function directAttack(
	data: RuntimeData,
	tower: TowerRecord,
	attack: ConfigTypes.TowerAttackDefinition,
	target: EnemyRecord,
	serverTime: number,
	_eventBudget: number
): { AttackEvent }
	local event = applyAttackDamage(data, tower, target, attack.damage, serverTime)
	return if event == nil then {} else { event }
end

local function splashAttack(
	data: RuntimeData,
	tower: TowerRecord,
	attack: ConfigTypes.TowerAttackDefinition,
	target: EnemyRecord,
	serverTime: number,
	eventBudget: number
): { AttackEvent }
	local rawAttack = attack :: any
	local radius = if isFiniteNumber(rawAttack.splashRadiusStuds) then rawAttack.splashRadiusStuds else 0
	local secondaryMultiplier = if isFiniteNumber(rawAttack.splashDamageMultiplier)
		then math.clamp(rawAttack.splashDamageMultiplier, 0, 1)
		else 1
	local targetIds = { target.runtimeEnemyId }
	for _, runtimeEnemyId in enemyIds(data) do
		local candidate = data.enemies[runtimeEnemyId]
		if
			candidate ~= nil
			and candidate.runtimeEnemyId ~= target.runtimeEnemyId
			and (candidate.position - target.position).Magnitude <= radius
		then
			table.insert(targetIds, runtimeEnemyId)
		end
	end
	local events: { AttackEvent } = {}
	for index, runtimeEnemyId in targetIds do
		if #events >= eventBudget or data.state ~= "Playing" then
			break
		end
		local candidate = data.enemies[runtimeEnemyId]
		if candidate ~= nil then
			local damage = if index == 1 then attack.damage else attack.damage * secondaryMultiplier
			local event = applyAttackDamage(data, tower, candidate, damage, serverTime)
			if event ~= nil then
				table.insert(events, event)
			end
		end
	end
	return events
end

local ATTACK_BEHAVIORS: { [string]: AttackBehavior } = table.freeze({
	["attack.direct"] = directAttack,
	["attack.single-target"] = directAttack,
	["attack.splash"] = splashAttack,
})

local function attackWithTower(
	data: RuntimeData,
	tower: TowerRecord,
	serverTime: number,
	eventBudget: number
): { AttackEvent }
	local level = tower.definition.levels[tower.level]
	local attack = level.attack
	if attack == nil then
		return {}
	end
	local selectionResult =
		TargetQuery.select(CFrame.new(tower.position), level.rangeStuds, tower.targetMode, targetCandidates(data))
	if not selectionResult.ok or selectionResult.value == nil then
		return {}
	end
	local target = data.enemies[selectionResult.value.runtimeEnemyId]
	if target == nil or target.currentHealth <= 0 then
		return {}
	end
	local behavior = ATTACK_BEHAVIORS[attack.behavior.key]
	return if behavior == nil then {} else behavior(data, tower, attack, target, serverTime, eventBudget)
end

local function processAttacks(data: RuntimeData, serverTime: number, maximumEvents: number): { AttackEvent }
	local events: { AttackEvent } = {}
	for _, runtimeTowerId in towerIds(data) do
		local tower = data.towers[runtimeTowerId]
		if tower ~= nil then
			local level = tower.definition.levels[tower.level]
			local attack = level.attack
			if attack ~= nil and tower.cooldownEndsServerTime <= serverTime and #events < maximumEvents then
				local attackEvents = attackWithTower(data, tower, serverTime, maximumEvents - #events)
				if #attackEvents > 0 then
					for _, event in attackEvents do
						table.insert(events, event)
					end
					tower.cooldownEndsServerTime = serverTime + attack.cooldownSeconds
				else
					-- A ready tower never banks idle cooldown intervals into a burst.
					tower.cooldownEndsServerTime = serverTime
				end
			end
		end
		if #events >= maximumEvents then
			break
		end
	end
	return events
end

local function completeResolvedWaves(data: RuntimeData, serverTime: number): boolean
	if data.state ~= "Playing" then
		return false
	end
	local changed = false
	for waveNumber, origin in data.waveOrigins do
		local queuePending = waveNumber == data.waveNumber and data.spawnCursor <= #data.spawnQueue
		if not origin.resolved and not queuePending and origin.aliveCount == 0 then
			origin.resolved = true
			data.activeWaveOriginCount = math.max(0, data.activeWaveOriginCount - 1)
			data.resolvedWaveNumbers[waveNumber] = origin
			changed = true
		end
	end
	while true do
		local nextWave = data.wavesCompleted + 1
		local origin = data.resolvedWaveNumbers[nextWave]
		if origin == nil then
			break
		end
		local wave = origin.wave
		local reward = if wave.rewardClass == "Final"
			then data.economy.waveRewards.final
			elseif wave.rewardClass == "Milestone" then data.economy.waveRewards.milestone
			else data.economy.waveRewards.standard
		local stipend = data.ledger:grantAuthoritativeWaveStipend(nextWave, reward.battleCashStipendPerActivePlayer)
		if not stipend.ok then
			finishMatch(data, "Defeat", "TechnicalTermination", serverTime)
			return true
		end
		data.wavesCompleted = nextWave
		data.resolvedWaveNumbers[nextWave] = nil
		data.waveOrigins[nextWave] = nil
		for userId in data.connectedParticipantSet do
			local stats = data.participantStats[userId]
			if stats ~= nil and stats.lastCreditedWave < nextWave then
				stats.wavesParticipated = boundedAdd(stats.wavesParticipated, 1)
				stats.lastCreditedWave = nextWave
			end
		end
		changed = true
	end
	if
		data.modeKind == "Finite"
		and data.wavesCompleted >= (data.difficulty :: ConfigTypes.FiniteDifficultyDefinition).waveCount
		and data.activeWaveOriginCount == 0
	then
		return finishMatch(data, "Victory", "Victory", serverTime)
	end
	local currentOrigin = data.waveOrigins[data.waveNumber]
	if data.waveNumber > 0 and (currentOrigin == nil or currentOrigin.resolved) then
		data.wavePhase = "Intermission"
		local earlyTime = serverTime + data.difficulty.timing.earlyClearIntermissionSeconds
		if data.nextWaveServerTime == 0 then
			data.nextWaveServerTime = earlyTime
		else
			data.nextWaveServerTime = math.min(data.nextWaveServerTime, earlyTime)
		end
	end
	if changed then
		advanceRevision(data)
	end
	return changed
end

local function participantMatches(data: RuntimeData, userId: unknown): boolean
	return validUserId(userId) and data.connectedParticipantSet[userId :: number] == true
end

local function lifetimeParticipantMatches(data: RuntimeData, userId: unknown): boolean
	return validUserId(userId) and data.participantSet[userId :: number] == true
end

local function participantActionFailure(data: RuntimeData, userId: unknown): ActionOutcome?
	if not lifetimeParticipantMatches(data, userId) then
		return reject("NotParticipant")
	end
	if not participantMatches(data, userId) then
		return reject("ParticipantDisconnected")
	end
	return nil
end

local function requestMatches(data: RuntimeData, matchId: unknown): boolean
	return type(matchId) == "string" and matchId == data.matchId
end

function Methods.addParticipant(self: Runtime, loadoutValue: unknown): ActionOutcome
	local data = requireData(self)
	if data.cleaned or data.state ~= "Ready" then
		return reject("WrongState")
	end
	if IS_EXACT_TEST_MODULE and validUserId(loadoutValue) then
		local userId = loadoutValue :: number
		local slots = {}
		for index, definition in data.configuration.towers.ordered do
			if index > MatchLoadoutProtocol.MAX_SLOTS then
				break
			end
			table.insert(slots, {
				slot = index,
				unitId = `unit:test-{userId}-{index}`,
				towerId = definition.id,
			})
		end
		loadoutValue = {
			userId = userId,
			revision = 1,
			slots = slots,
			settings = data.configuration.defaultSettings,
		}
	end
	local loadoutUserId = if type(loadoutValue) == "table" then rawget(loadoutValue :: any, "userId") else nil
	local validated: any = if data.studioDirectUserIds
			and type(loadoutUserId) == "number"
			and loadoutUserId < 0
		then DirectStudioParticipantLoadout.validate(loadoutValue, data.configuration)
		else MatchLoadoutProtocol.validate(loadoutValue, data.configuration)
	if not validated.ok then
		return reject("NotParticipant")
	end
	local loadout = validated.value
	local userId = loadout.userId
	if data.participantSet[userId] then
		return reject("NotParticipant")
	end
	local existingLoadout = data.loadoutsByUserId[userId]
	if existingLoadout ~= nil then
		if existingLoadout.revision ~= loadout.revision or #existingLoadout.slots ~= #loadout.slots then
			return reject("StaleLoadout")
		end
		for index, slot in existingLoadout.slots do
			local candidate = loadout.slots[index]
			if candidate == nil or candidate.unitId ~= slot.unitId or candidate.towerId ~= slot.towerId then
				return reject("StaleLoadout")
			end
		end
		loadout = existingLoadout
	end
	if #data.participants >= MAX_PARTICIPANTS or not beginMutation(data) then
		return reject("Busy")
	end
	local existingParticipant = data.ledger:getSnapshot(userId)
	local ledgerResult = if existingParticipant.ok
		then data.ledger:setParticipantActive(userId, true)
		else data.ledger:initializeParticipant(userId)
	if not ledgerResult.ok then
		finishMutation(data)
		return reject("Unavailable")
	end
	data.participantSet[userId] = true
	data.connectedParticipantSet[userId] = true
	data.everConnectedParticipantSet[userId] = true
	data.loadoutsByUserId[userId] = loadout
	table.insert(data.participants, userId)
	if data.participantStats[userId] == nil then
		data.participantStats[userId] = {
			damageDealt = 0,
			placements = 0,
			upgrades = 0,
			sells = 0,
			wavesParticipated = 0,
			lastCreditedWave = 0,
		}
	end
	advanceRevision(data)
	finishMutation(data)
	return ACCEPTED
end

function Methods.removeParticipant(self: Runtime, userIdValue: unknown, serverTimeValue: unknown): ActionOutcome
	local data = requireData(self)
	local participantFailure = participantActionFailure(data, userIdValue)
	if participantFailure ~= nil then
		return participantFailure
	end
	if not isFiniteNumber(serverTimeValue) or not beginMutation(data) then
		return reject("Busy")
	end
	local userId = userIdValue :: number
	local deactivated = data.ledger:setParticipantActive(userId, false)
	if not deactivated.ok then
		finishMutation(data)
		return reject("Unavailable")
	end
	data.connectedParticipantSet[userId] = nil
	data.ready[userId] = nil
	if data.modeKind == "Endless" and data.state == "Playing" and connectedParticipantCount(data) == 0 then
		finishMatch(data, "Defeat", "AllParticipantsGone", serverTimeValue :: number)
	elseif data.state == "Ready" and allParticipantsReady(data) then
		startPlaying(data, serverTimeValue :: number)
	else
		advanceRevision(data)
	end
	finishMutation(data)
	return ACCEPTED
end

function Methods.reconnectParticipant(self: Runtime, userIdValue: unknown): ActionOutcome
	local data = requireData(self)
	if data.cleaned then
		return reject("WrongState")
	end
	if not lifetimeParticipantMatches(data, userIdValue) then
		return reject("NotParticipant")
	end
	local userId = userIdValue :: number
	if data.connectedParticipantSet[userId] then
		return reject("Busy")
	end
	if not data.everConnectedParticipantSet[userId] and data.state ~= "Ready" then
		return reject("NotParticipant")
	end
	if not beginMutation(data) then
		return reject("Busy")
	end
	local activated = data.ledger:setParticipantActive(userId, true)
	if not activated.ok then
		finishMutation(data)
		return reject("Unavailable")
	end
	data.connectedParticipantSet[userId] = true
	data.everConnectedParticipantSet[userId] = true
	-- Ready is intentionally not replayed. The retained loadout, cash, stats, and
	-- tower ownership remain bound to this stable UserId for the match lifetime.
	data.ready[userId] = nil
	advanceRevision(data)
	finishMutation(data)
	return ACCEPTED
end

function Methods.hasParticipant(self: Runtime, userIdValue: unknown): boolean
	return lifetimeParticipantMatches(requireData(self), userIdValue)
end

function Methods.isParticipantConnected(self: Runtime, userIdValue: unknown): boolean
	return participantMatches(requireData(self), userIdValue)
end

function Methods.submitReady(
	self: Runtime,
	userIdValue: unknown,
	matchIdValue: unknown,
	serverTimeValue: unknown
): ActionOutcome
	local data = requireData(self)
	if not requestMatches(data, matchIdValue) then
		return reject("StaleMatch")
	end
	if data.state ~= "Ready" then
		return reject("WrongState")
	end
	local participantFailure = participantActionFailure(data, userIdValue)
	if participantFailure ~= nil then
		return participantFailure
	end
	if not isFiniteNumber(serverTimeValue) or (serverTimeValue :: number) < 0 or not beginMutation(data) then
		return reject("Busy")
	end
	local userId = userIdValue :: number
	if data.ready[userId] then
		finishMutation(data)
		return ACCEPTED
	end
	data.ready[userId] = true
	data.submittedReady[userId] = true
	if allParticipantsReady(data) then
		startPlaying(data, serverTimeValue :: number)
	else
		advanceRevision(data)
	end
	finishMutation(data)
	return ACCEPTED
end

function Methods.placeTower(
	self: Runtime,
	userIdValue: unknown,
	matchIdValue: unknown,
	towerIdValue: unknown,
	slotValue: unknown,
	loadoutRevisionValue: unknown,
	positionValue: unknown,
	rotationDegreesValue: unknown,
	serverTimeValue: unknown
): ActionOutcome
	local data = requireData(self)
	if not requestMatches(data, matchIdValue) then
		return reject("StaleMatch")
	end
	if data.state ~= "Playing" then
		return reject("WrongState")
	end
	local participantFailure = participantActionFailure(data, userIdValue)
	if participantFailure ~= nil then
		return participantFailure
	end
	if IS_EXACT_TEST_MODULE and typeof(slotValue) == "Vector3" then
		serverTimeValue = positionValue
		positionValue = slotValue
		rotationDegreesValue = loadoutRevisionValue
		local testLoadout = data.loadoutsByUserId[userIdValue :: number]
		local inferredSlot: number? = nil
		if testLoadout ~= nil and type(towerIdValue) == "string" then
			for index, equipped in testLoadout.slots do
				if equipped.towerId == towerIdValue then
					inferredSlot = index
					break
				end
			end
		end
		slotValue = inferredSlot
		loadoutRevisionValue = if testLoadout == nil then nil else testLoadout.revision
	end
	if
		type(towerIdValue) ~= "string"
		or type(slotValue) ~= "number"
		or not Validation.isSafeInteger(slotValue)
		or type(loadoutRevisionValue) ~= "number"
		or not Validation.isSafeInteger(loadoutRevisionValue)
		or typeof(positionValue) ~= "Vector3"
		or not isFiniteNumber(rotationDegreesValue)
		or not isFiniteNumber(serverTimeValue)
	then
		return reject("InvalidPlacement")
	end
	local loadout = data.loadoutsByUserId[userIdValue :: number]
	if loadout == nil then
		return reject("NotParticipant")
	end
	if loadout.revision ~= loadoutRevisionValue then
		return reject("StaleLoadout")
	end
	local equipped = loadout.slots[slotValue :: number]
	if equipped == nil or equipped.slot ~= slotValue or equipped.towerId ~= towerIdValue then
		return reject("UnequippedTower")
	end
	local definition = data.configuration.towers.byId[towerIdValue :: any]
	if definition == nil then
		return reject("InvalidPlacement")
	end
	if
		countDictionary(data.towers) >= MAX_TOWERS
		or perTypeCount(data, userIdValue :: number, definition.id) >= definition.placementCap
	then
		return reject("TowerCap")
	end
	local position = positionValue :: Vector3
	local evaluation = PlacementGeometry.evaluate(
		Vector2.new(position.X, position.Z),
		definition.footprintRadiusStuds,
		data.bounds,
		data.placementZones,
		data.exclusions,
		footprints(data)
	)
	if not evaluation.valid or evaluation.position == nil then
		return reject("InvalidPlacement")
	end
	local afford = data.ledger:canAfford(userIdValue, definition.placementCost)
	if not afford.ok or not afford.value then
		return reject("InsufficientCash")
	end
	if not beginMutation(data) then
		return reject("Busy")
	end
	local prepared = data.ledger:prepare(userIdValue, definition.placementCost)
	if not prepared.ok then
		finishMutation(data)
		return reject("InsufficientCash")
	end
	local runtimeTowerId = data.nextTowerId
	local nextId = checkedIncrement(runtimeTowerId)
	local targetMode = definition.defaultTargetMode
	if nextId == nil or targetMode == nil then
		data.ledger:abort(prepared.value)
		finishMutation(data)
		return reject("Unavailable")
	end
	local tower: TowerRecord = {
		runtimeTowerId = runtimeTowerId,
		revision = 1,
		definition = definition,
		ownerUserId = userIdValue :: number,
		level = 1,
		targetMode = targetMode,
		position = evaluation.position,
		rotationDegrees = rotationDegreesValue :: number,
		totalInvestment = definition.placementCost,
		cooldownEndsServerTime = serverTimeValue :: number,
	}
	data.towers[runtimeTowerId] = tower
	local committed = data.ledger:commit(prepared.value)
	if not committed.ok then
		data.towers[runtimeTowerId] = nil
		data.ledger:abort(prepared.value)
		finishMutation(data)
		return reject("Unavailable")
	end
	data.nextTowerId = nextId
	local stats = data.participantStats[userIdValue :: number]
	stats.placements = boundedAdd(stats.placements, 1)
	advanceRevision(data)
	finishMutation(data)
	return ACCEPTED
end

local function ownedTower(
	data: RuntimeData,
	userIdValue: unknown,
	runtimeTowerIdValue: unknown
): (TowerRecord?, ActionOutcome?)
	local participantFailure = participantActionFailure(data, userIdValue)
	if participantFailure ~= nil then
		return nil, participantFailure
	end
	if type(runtimeTowerIdValue) ~= "number" or not Validation.isSafeInteger(runtimeTowerIdValue) then
		return nil, reject("NotFound")
	end
	local tower = data.towers[runtimeTowerIdValue :: number]
	if tower == nil then
		return nil, reject("NotFound")
	end
	if tower.ownerUserId ~= userIdValue then
		return nil, reject("NotOwner")
	end
	return tower, nil
end

local function towerRevisionMatches(tower: TowerRecord, towerRevisionValue: unknown): boolean
	return type(towerRevisionValue) == "number"
		and Validation.isSafeInteger(towerRevisionValue :: number)
		and towerRevisionValue == tower.revision
end

function Methods.upgradeTower(
	self: Runtime,
	userIdValue: unknown,
	matchIdValue: unknown,
	runtimeTowerIdValue: unknown,
	towerRevisionValue: unknown
): ActionOutcome
	local data = requireData(self)
	if not requestMatches(data, matchIdValue) then
		return reject("StaleMatch")
	end
	if data.state ~= "Playing" then
		return reject("WrongState")
	end
	local tower, towerFailure = ownedTower(data, userIdValue, runtimeTowerIdValue)
	if tower == nil then
		return towerFailure :: ActionOutcome
	end
	if not towerRevisionMatches(tower, towerRevisionValue) then
		return reject("StaleTower")
	end
	if tower.revision >= Validation.MAX_SAFE_INTEGER then
		return reject("Unavailable")
	end
	local nextLevel = tower.level + 1
	local nextDefinition = tower.definition.levels[nextLevel]
	if nextDefinition == nil then
		return reject("MaxLevel")
	end
	local afford = data.ledger:canAfford(userIdValue, nextDefinition.upgradeCost)
	if not afford.ok or not afford.value then
		return reject("InsufficientCash")
	end
	if not beginMutation(data) then
		return reject("Busy")
	end
	local prepared = data.ledger:prepare(userIdValue, nextDefinition.upgradeCost)
	if not prepared.ok then
		finishMutation(data)
		return reject("InsufficientCash")
	end
	local previousLevel = tower.level
	local previousInvestment = tower.totalInvestment
	tower.level = nextLevel
	tower.totalInvestment += nextDefinition.upgradeCost
	local committed = data.ledger:commit(prepared.value)
	if not committed.ok then
		tower.level = previousLevel
		tower.totalInvestment = previousInvestment
		data.ledger:abort(prepared.value)
		finishMutation(data)
		return reject("Unavailable")
	end
	-- Cooldown is deliberately unchanged: an upgrade never grants a free shot.
	tower.revision += 1
	local stats = data.participantStats[userIdValue :: number]
	stats.upgrades = boundedAdd(stats.upgrades, 1)
	advanceRevision(data)
	finishMutation(data)
	return ACCEPTED
end

function Methods.sellTower(
	self: Runtime,
	userIdValue: unknown,
	matchIdValue: unknown,
	runtimeTowerIdValue: unknown,
	towerRevisionValue: unknown
): ActionOutcome
	local data = requireData(self)
	if not requestMatches(data, matchIdValue) then
		return reject("StaleMatch")
	end
	if data.state ~= "Playing" then
		return reject("WrongState")
	end
	local tower, towerFailure = ownedTower(data, userIdValue, runtimeTowerIdValue)
	if tower == nil then
		return towerFailure :: ActionOutcome
	end
	if not towerRevisionMatches(tower, towerRevisionValue) then
		return reject("StaleTower")
	end
	if not beginMutation(data) then
		return reject("Busy")
	end
	local refund = floorBasisPoints(tower.totalInvestment, data.configuration.economy.sellRefund.basisPoints)
	local credited = data.ledger:refundAuthoritativeSale(userIdValue, refund)
	if not credited.ok then
		finishMutation(data)
		return reject("Unavailable")
	end
	data.towers[tower.runtimeTowerId] = nil
	local stats = data.participantStats[userIdValue :: number]
	stats.sells = boundedAdd(stats.sells, 1)
	advanceRevision(data)
	finishMutation(data)
	return ACCEPTED
end

function Methods.setTargetMode(
	self: Runtime,
	userIdValue: unknown,
	matchIdValue: unknown,
	runtimeTowerIdValue: unknown,
	towerRevisionValue: unknown,
	targetModeValue: unknown
): ActionOutcome
	local data = requireData(self)
	if not requestMatches(data, matchIdValue) then
		return reject("StaleMatch")
	end
	if data.state ~= "Playing" then
		return reject("WrongState")
	end
	local tower, towerFailure = ownedTower(data, userIdValue, runtimeTowerIdValue)
	if tower == nil then
		return towerFailure :: ActionOutcome
	end
	if not towerRevisionMatches(tower, towerRevisionValue) then
		return reject("StaleTower")
	end
	local supported = false
	for _, mode in tower.definition.supportedTargetModes do
		if mode == targetModeValue then
			supported = true
			break
		end
	end
	if not supported then
		return reject("UnsupportedTargetMode")
	end
	if tower.targetMode == targetModeValue then
		return ACCEPTED
	end
	if tower.revision >= Validation.MAX_SAFE_INTEGER then
		return reject("Unavailable")
	end
	if not beginMutation(data) then
		return reject("Busy")
	end
	tower.targetMode = targetModeValue :: ConfigTypes.TargetMode
	tower.revision += 1
	-- Retargeting also preserves the exact outstanding cooldown.
	advanceRevision(data)
	finishMutation(data)
	return ACCEPTED
end

function Methods.step(self: Runtime, serverTimeValue: unknown): Result.Result<StepOutcome, RuntimeError>
	local data = requireData(self)
	if data.cleaned then
		return errorResult("CLEANED", "step")
	end
	if
		not isFiniteNumber(serverTimeValue)
		or (serverTimeValue :: number) < 0
		or (serverTimeValue :: number) < data.lastSimulationServerTime
	then
		return errorResult("INVALID_TIME", "step")
	end
	if not beginMutation(data) then
		return errorResult("INTERNAL_ERROR", "step")
	end
	local requestedTime = serverTimeValue :: number
	local changed = false
	local attacks: { AttackEvent } = {}
	if data.state == "Ready" then
		-- Ready has no simulation. Track real server time directly so entering the
		-- first fixed tick never needs to catch up from process start.
		data.lastSimulationServerTime = requestedTime
	elseif data.state == "Playing" then
		local maximumTime = math.min(requestedTime, data.lastSimulationServerTime + MAX_STEP_SECONDS)
		local fixedStepCount = 0
		while
			data.state == "Playing"
			and data.lastSimulationServerTime + FIXED_STEP_SECONDS <= maximumTime + 1e-9
			and fixedStepCount < MAX_FIXED_STEPS_PER_CALL
		do
			local serverTime = data.lastSimulationServerTime + FIXED_STEP_SECONDS
			data.lastSimulationServerTime = serverTime
			fixedStepCount += 1
			local tickChanged = false
			if
				data.nextWaveServerTime > 0
				and serverTime >= data.nextWaveServerTime
				and data.spawnCursor > #data.spawnQueue
			then
				tickChanged = startNextWave(data, serverTime) or tickChanged
			end
			if data.state == "Playing" then
				tickChanged = spawnDueEnemies(data, serverTime) or tickChanged
				local remainingAttackBudget = MAX_ATTACKS_PER_STEP - #attacks
				if remainingAttackBudget > 0 then
					local tickAttacks = processAttacks(data, serverTime, remainingAttackBudget)
					for _, event in tickAttacks do
						table.insert(attacks, event)
					end
					tickChanged = #tickAttacks > 0 or tickChanged
				end
			end
			if data.state == "Playing" then
				tickChanged = moveEnemies(data, FIXED_STEP_SECONDS, serverTime) or tickChanged
				tickChanged = completeResolvedWaves(data, serverTime) or tickChanged
			end
			if tickChanged then
				advanceRevision(data)
				changed = true
			end
		end
	end
	finishMutation(data)
	return Result.ok(table.freeze({
		serverTime = data.lastSimulationServerTime,
		changed = changed,
		attacks = table.freeze(attacks),
	}))
end

local function towerSnapshot(data: RuntimeData, tower: TowerRecord): PlayableMatchProtocol.TowerSnapshot
	local level = tower.definition.levels[tower.level]
	local attack = level.attack
	local nextLevel = tower.definition.levels[tower.level + 1]
	return table.freeze({
		runtimeTowerId = tower.runtimeTowerId,
		revision = tower.revision,
		towerId = tower.definition.id,
		displayName = tower.definition.displayName,
		ownerUserId = tower.ownerUserId,
		level = tower.level,
		targetMode = tower.targetMode,
		position = tower.position,
		rotationDegrees = tower.rotationDegrees,
		totalInvestment = tower.totalInvestment,
		cooldownEndsServerTime = tower.cooldownEndsServerTime,
		damage = if attack == nil then 0 else attack.damage,
		cooldownSeconds = if attack == nil then 0 else attack.cooldownSeconds,
		rangeStuds = level.rangeStuds,
		upgradeCost = if nextLevel == nil then 0 else nextLevel.upgradeCost,
		sellValue = floorBasisPoints(tower.totalInvestment, data.configuration.economy.sellRefund.basisPoints),
	})
end

local function enemyThreatClass(definition: ConfigTypes.EnemyDefinition): PlayableMatchProtocol.ThreatClass
	local rawDefinition = definition :: any
	if
		rawDefinition.threatClass == "Elite"
		or rawDefinition.threatClass == "MiniBoss"
		or rawDefinition.threatClass == "Boss"
	then
		return rawDefinition.threatClass
	end
	if type(definition.tags) == "table" then
		for _, tag in definition.tags do
			if tag == "role.boss" then
				return "Boss"
			elseif tag == "role.miniboss" then
				return "MiniBoss"
			elseif tag == "role.elite" then
				return "Elite"
			end
		end
	end
	return "Standard"
end

local function buildSnapshot(
	data: RuntimeData,
	serverTime: number,
	viewerRole: PlayableMatchProtocol.ViewerRole,
	userId: number?
): Result.Result<PlayableMatchProtocol.Snapshot, RuntimeError>
	local towerEntries: { PlayableMatchProtocol.TowerSnapshot } = {}
	for _, runtimeTowerId in towerIds(data) do
		table.insert(towerEntries, towerSnapshot(data, data.towers[runtimeTowerId]))
	end
	local enemyEntries: { PlayableMatchProtocol.EnemySnapshot } = {}
	local boss: PlayableMatchProtocol.BossSummary? = nil
	for _, runtimeEnemyId in enemyIds(data) do
		local enemy = data.enemies[runtimeEnemyId]
		local threatClass = enemyThreatClass(enemy.definition)
		table.insert(
			enemyEntries,
			table.freeze({
				runtimeEnemyId = enemy.runtimeEnemyId,
				enemyId = enemy.definition.id,
				displayName = enemy.definition.displayName,
				currentHealth = enemy.currentHealth,
				maximumHealth = enemy.maximumHealth,
				position = enemy.position,
				pathProgress = enemy.pathProgress,
				threatClass = threatClass,
			})
		)
		if threatClass == "Boss" or threatClass == "MiniBoss" then
			if
				boss == nil
				or (threatClass == "Boss" and boss.threatClass ~= "Boss")
				or (threatClass == boss.threatClass and enemy.maximumHealth > boss.maximumHealth)
			then
				boss = table.freeze({
					runtimeEnemyId = enemy.runtimeEnemyId,
					displayName = enemy.definition.displayName,
					currentHealth = enemy.currentHealth,
					maximumHealth = enemy.maximumHealth,
					threatClass = threatClass :: "MiniBoss" | "Boss",
				})
			end
		end
	end
	local options: { PlayableMatchProtocol.TowerOption } = {}
	local loadoutRevision = 0
	local battleCash = 0
	local damageDealt = 0
	local battleCashEarned = 0
	local battleCashSpent = 0
	local placements = 0
	local upgrades = 0
	local sells = 0
	local settings = data.configuration.defaultSettings
	local reward: RewardProtocol.RewardView? = nil
	if viewerRole == "Participant" then
		local participantUserId = userId :: number
		local loadout = data.loadoutsByUserId[participantUserId]
		local participantStats = data.participantStats[participantUserId]
		if loadout == nil or participantStats == nil then
			return errorResult("INVALID_PARTICIPANTS", "snapshot")
		end
		local cashResult = data.ledger:getSnapshot(participantUserId)
		if not cashResult.ok then
			return errorResult("LEDGER_FAILED", "snapshot")
		end
		for _, equipped in loadout.slots do
			local definition = data.configuration.towers.byId[equipped.towerId]
			if definition == nil then
				return errorResult("INTERNAL_ERROR", "snapshot")
			end
			table.insert(
				options,
				table.freeze({
					slot = equipped.slot,
					unitId = equipped.unitId,
					towerId = definition.id,
					displayName = definition.displayName,
					placementCost = definition.placementCost,
					description = definition.description or definition.displayName,
				})
			)
		end
		local cash = cashResult.value
		loadoutRevision = loadout.revision
		battleCash = cash.balance
		damageDealt = participantStats.damageDealt
		battleCashEarned = cash.damageIncomeBattleCash + cash.waveStipendBattleCash + cash.refundedBattleCash
		battleCashSpent = cash.spentBattleCash
		placements = participantStats.placements
		upgrades = participantStats.upgrades
		sells = participantStats.sells
		settings = loadout.settings
		if data.state == "Results" then
			reward = data.rewardViewsByUserId[participantUserId]
		end
	elseif userId ~= nil then
		local authenticatedLoadout = data.loadoutsByUserId[userId]
		if authenticatedLoadout ~= nil then
			settings = authenticatedLoadout.settings
		end
		if data.state == "Results" then
			reward = data.rewardViewsByUserId[userId]
		end
	end
	local stats: PlayableMatchProtocol.ResultStats = table.freeze({
		durationSeconds = if data.startedServerTime == 0
			then 0
			else math.max(
				0,
				(
					if data.endedServerTime > 0
						then data.endedServerTime
						else math.min(serverTime, data.lastSimulationServerTime)
				) - data.startedServerTime
			),
		wavesCompleted = data.wavesCompleted,
		damageDealt = damageDealt,
		battleCashEarned = battleCashEarned,
		battleCashSpent = battleCashSpent,
		placements = placements,
		upgrades = upgrades,
		sells = sells,
		baseHealthRemaining = data.baseHealth,
	})
	local snapshot: PlayableMatchProtocol.Snapshot = table.freeze({
		matchId = data.matchId,
		viewerRole = viewerRole,
		rewarding = data.rewarding,
		revision = data.revision,
		loadoutRevision = loadoutRevision,
		state = data.state,
		result = data.result,
		mapId = data.mapDefinition.id,
		mapDisplayName = data.mapDefinition.displayName,
		difficultyId = data.difficulty.id,
		difficultyDisplayName = data.difficulty.displayName,
		modeKind = data.modeKind,
		contentVersion = data.contentVersion,
		seed = data.seed,
		serverTime = serverTime,
		waveNumber = data.waveNumber,
		totalWaves = if data.modeKind == "Finite"
			then (data.difficulty :: ConfigTypes.FiniteDifficultyDefinition).waveCount
			else nil,
		bossKind = if (data.wavePhase == "Spawning" or data.wavePhase == "Resolving")
				and data.currentWave ~= nil
			then data.currentWave.bossKind
			else "None",
		boss = boss,
		wavePhase = data.wavePhase,
		nextWaveServerTime = data.nextWaveServerTime,
		baseHealth = data.baseHealth,
		maximumBaseHealth = data.difficulty.base.maxHealth,
		enemiesAlive = #enemyEntries,
		battleCash = battleCash,
		participants = table.freeze({
			readyCount = activeReadyCount(data),
			participantCount = #data.participants,
		}),
		towerOptions = table.freeze(options),
		towers = table.freeze(towerEntries),
		enemies = table.freeze(enemyEntries),
		stats = stats,
		reward = reward,
		settings = settings,
	})
	local validated = PlayableMatchProtocol.validateSnapshot(snapshot)
	if not validated.ok then
		return errorResult("INTERNAL_ERROR", "snapshot")
	end
	return Result.ok(validated.value)
end

function Methods.getSnapshot(
	self: Runtime,
	userIdValue: unknown,
	serverTimeValue: unknown
): Result.Result<PlayableMatchProtocol.Snapshot, RuntimeError>
	local data = requireData(self)
	if data.cleaned then
		return errorResult("CLEANED", "snapshot")
	end
	if not participantMatches(data, userIdValue) or not isFiniteNumber(serverTimeValue) then
		return errorResult("INVALID_PARTICIPANTS", "snapshot")
	end
	return buildSnapshot(data, serverTimeValue :: number, "Participant", userIdValue :: number)
end

function Methods.getSpectatorSnapshot(
	self: Runtime,
	serverTimeValue: unknown,
	viewerUserIdValue: unknown?
): Result.Result<PlayableMatchProtocol.Snapshot, RuntimeError>
	local data = requireData(self)
	if data.cleaned then
		return errorResult("CLEANED", "snapshot")
	end
	if not isFiniteNumber(serverTimeValue) then
		return errorResult("INVALID_TIME", "snapshot")
	end
	if viewerUserIdValue ~= nil and not validUserId(viewerUserIdValue) then
		return errorResult("INVALID_PARTICIPANTS", "snapshot")
	end
	return buildSnapshot(data, serverTimeValue :: number, "Spectator", viewerUserIdValue :: number?)
end

function Methods.canReplay(self: Runtime, userIdValue: unknown, matchIdValue: unknown): ActionOutcome
	local data = requireData(self)
	if not requestMatches(data, matchIdValue) then
		return reject("StaleMatch")
	end
	local participantFailure = participantActionFailure(data, userIdValue)
	if participantFailure ~= nil then
		return participantFailure
	end
	if data.state ~= "Results" then
		return reject("WrongState")
	end
	return ACCEPTED
end

function Methods.terminateEndless(self: Runtime, reasonValue: unknown, serverTimeValue: unknown): ActionOutcome
	local data = requireData(self)
	if data.cleaned or data.modeKind ~= "Endless" or data.state ~= "Playing" then
		return reject("WrongState")
	end
	if
		(
			reasonValue ~= "PlayerEnded"
			and reasonValue ~= "AllParticipantsGone"
			and reasonValue ~= "Shutdown"
			and reasonValue ~= "TechnicalTermination"
		)
		or not isFiniteNumber(serverTimeValue)
		or (serverTimeValue :: number) < data.lastSimulationServerTime
		or not beginMutation(data)
	then
		return reject("Unavailable")
	end
	finishMatch(data, "Defeat", reasonValue :: PlayableMatchProtocol.TerminationReason, serverTimeValue :: number)
	finishMutation(data)
	return ACCEPTED
end

-- A server-owned private projection (for example, tutorial guidance) may
-- change without mutating combat. Advancing the authoritative revision keeps
-- clients from treating that new projection as a same-revision replay.
function Methods.refreshPresentation(self: Runtime): ActionOutcome
	local data = requireData(self)
	if not beginMutation(data) then
		return reject("Unavailable")
	end
	if not advanceRevision(data) then
		finishMutation(data)
		return reject("Unavailable")
	end
	finishMutation(data)
	return ACCEPTED
end

local function rewardViewsEqual(left: RewardProtocol.RewardView, right: RewardProtocol.RewardView): boolean
	return left.resultId == right.resultId
		and left.status == right.status
		and left.persistentGoldAwarded == right.persistentGoldAwarded
		and left.firstClearBonus == right.firstClearBonus
		and left.battleCashEarned == right.battleCashEarned
		and left.battleCashSpent == right.battleCashSpent
		and left.reason == right.reason
end

function Methods.setRewardView(self: Runtime, userIdValue: unknown, rewardViewValue: unknown): ActionOutcome
	local data = requireData(self)
	if data.cleaned or data.state ~= "Results" or not data.rewarding then
		return reject("WrongState")
	end
	if not lifetimeParticipantMatches(data, userIdValue) then
		return reject("NotParticipant")
	end
	local validated = RewardProtocol.validateRewardView(rewardViewValue)
	if not validated.ok then
		return reject("Unavailable")
	end
	local userId = userIdValue :: number
	local authenticatedParticipant = data.everConnectedParticipantSet[userId] == true
	if
		not authenticatedParticipant
		and (
			validated.value.status == "Granted"
			or validated.value.persistentGoldAwarded ~= 0
			or validated.value.firstClearBonus ~= 0
			or validated.value.battleCashEarned ~= 0
			or validated.value.battleCashSpent ~= 0
		)
	then
		return reject("Unavailable")
	end
	local cashResult = data.ledger:getSnapshot(userId)
	if not cashResult.ok then
		return reject("Unavailable")
	end
	local cash = cashResult.value
	local earned = cash.damageIncomeBattleCash + cash.waveStipendBattleCash + cash.refundedBattleCash
	if validated.value.battleCashEarned ~= earned or validated.value.battleCashSpent ~= cash.spentBattleCash then
		return reject("Unavailable")
	end
	local existing = data.rewardViewsByUserId[userId]
	if existing ~= nil and existing.resultId ~= validated.value.resultId then
		return reject("StaleMatch")
	end
	if existing ~= nil and rewardViewsEqual(existing, validated.value) then
		return ACCEPTED
	end
	if not beginMutation(data) then
		return reject("Busy")
	end
	data.rewardViewsByUserId[userId] = validated.value
	advanceRevision(data)
	finishMutation(data)
	return ACCEPTED
end

function Methods.getResultEvidence(self: Runtime): Result.Result<ResultEvidence, RuntimeError>
	local data = requireData(self)
	if data.cleaned then
		return errorResult("CLEANED", "resultEvidence")
	end
	if
		data.state ~= "Results"
		or (data.result ~= "Victory" and data.result ~= "Defeat")
		or data.terminationReason == nil
	then
		return errorResult("WRONG_STATE", "resultEvidence")
	end
	local entries: { ResultParticipantEvidence } = {}
	for _, userId in data.participants do
		local cashResult = data.ledger:getSnapshot(userId)
		local stats = data.participantStats[userId]
		if not cashResult.ok or stats == nil then
			return errorResult("LEDGER_FAILED", "resultEvidence")
		end
		local cash = cashResult.value
		local authenticatedParticipant = data.everConnectedParticipantSet[userId] == true
		table.insert(
			entries,
			table.freeze({
				userId = userId,
				authenticatedParticipant = authenticatedParticipant,
				spectator = not authenticatedParticipant,
				submittedReady = data.submittedReady[userId] == true,
				placements = stats.placements,
				wavesCompleted = stats.wavesParticipated,
				connectedAtResults = data.connectedAtResults[userId] == true,
				battleCashEarned = cash.damageIncomeBattleCash + cash.waveStipendBattleCash + cash.refundedBattleCash,
				battleCashSpent = cash.spentBattleCash,
			})
		)
	end
	return Result.ok(table.freeze({
		matchId = data.matchId,
		mapId = data.mapDefinition.id,
		difficultyId = data.difficulty.id,
		outcome = data.result :: "Victory" | "Defeat",
		modeKind = data.modeKind,
		highestCompletedWave = data.wavesCompleted,
		elapsedSeconds = math.max(0, math.floor(data.endedServerTime - data.startedServerTime)),
		seed = data.seed,
		contentVersion = data.contentVersion,
		terminationReason = data.terminationReason :: PlayableMatchProtocol.TerminationReason,
		rewardingMatch = data.rewarding,
		entries = table.freeze(entries),
	}))
end

function Methods.getMetrics(self: Runtime): Metrics
	local data = requireData(self)
	return table.freeze({
		state = data.state,
		result = data.result,
		revision = data.revision,
		waveNumber = data.waveNumber,
		wavesCompleted = data.wavesCompleted,
		activeTowerCount = countDictionary(data.towers),
		activeEnemyCount = countDictionary(data.enemies),
		attackCount = data.attackSequence,
		participantCount = #data.participants,
		connectedParticipantCount = connectedParticipantCount(data),
		readyCount = activeReadyCount(data),
		rewarding = data.rewarding,
		modeKind = data.modeKind,
		seed = data.seed,
		contentVersion = data.contentVersion,
		activeWaveOriginCount = data.activeWaveOriginCount,
		cleaned = data.cleaned,
	})
end

function Methods.cleanup(self: Runtime): Result.Result<boolean, RuntimeError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	if data.busy then
		return errorResult("INTERNAL_ERROR", "cleanup")
	end
	local cleaned = data.ledger:cleanup()
	if not cleaned.ok then
		return errorResult("LEDGER_FAILED", "cleanup")
	end
	table.clear(data.towers)
	table.clear(data.enemies)
	table.clear(data.spawnQueue)
	table.clear(data.waveOrigins)
	table.clear(data.resolvedWaveNumbers)
	table.clear(data.ready)
	table.clear(data.participantSet)
	table.clear(data.connectedParticipantSet)
	table.clear(data.everConnectedParticipantSet)
	table.clear(data.participants)
	table.clear(data.participantStats)
	table.clear(data.submittedReady)
	table.clear(data.connectedAtResults)
	table.clear(data.rewardViewsByUserId)
	table.clear(data.loadoutsByUserId)
	data.cleaned = true
	return Result.ok(true)
end

function PlayableMatchRuntime.new(dependenciesValue: unknown): Result.Result<Runtime, RuntimeError>
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return errorResult("INVALID_DEPENDENCIES", "new")
	end
	local dependencies = dependenciesValue :: any
	local rewarding = dependencies.rewarding
	if rewarding == nil then
		rewarding = false
	elseif type(rewarding) ~= "boolean" then
		return errorResult("INVALID_DEPENDENCIES", "new")
	end
	local studioDirectUserIds = dependencies.studioDirectUserIds
	if studioDirectUserIds == nil then
		studioDirectUserIds = false
	elseif type(studioDirectUserIds) ~= "boolean" then
		return errorResult("INVALID_DEPENDENCIES", "new")
	end
	if studioDirectUserIds and rewarding then
		return errorResult("INVALID_DEPENDENCIES", "new")
	end
	local matchIdResult = Ids.validateMatchId(dependencies.matchId)
	if not matchIdResult.ok then
		return errorResult("INVALID_DEPENDENCIES", "new")
	end
	if not ConfigurationValidator.isValidatedConfiguration(dependencies.configuration) then
		return errorResult("UNAUTHENTICATED_CONFIGURATION", "new")
	end
	local configuration = dependencies.configuration :: ConfigTypes.CoreConfiguration
	if
		#configuration.maps.ordered < 1
		or #configuration.difficulties.ordered < 1
		or #configuration.towers.ordered < 1
	then
		return errorResult("CONTENT_NOT_FOUND", "new")
	end
	-- Direct development is intentionally pinned to the legacy non-rewarding
	-- pair. Travelled matches must supply both authenticated ticket selections.
	local requestedMapId = dependencies.mapId or DEVELOPMENT_MAP_ID
	local requestedDifficultyId = dependencies.difficultyId or DEVELOPMENT_DIFFICULTY_ID
	local mapIdResult = Ids.validateMapId(requestedMapId)
	local difficultyIdResult = Ids.validateDifficultyId(requestedDifficultyId)
	if not mapIdResult.ok or not difficultyIdResult.ok then
		return errorResult("INVALID_DEPENDENCIES", "new")
	end
	local mapDefinition = configuration.maps.byId[mapIdResult.value]
	local difficulty = configuration.difficulties.byId[difficultyIdResult.value]
	local schedules = configuration.waves.byMapId[mapIdResult.value]
	local schedule = if schedules == nil then nil else schedules[difficultyIdResult.value]
	if mapDefinition == nil or difficulty == nil or schedule == nil then
		return errorResult("CONTENT_NOT_FOUND", "new")
	end
	local supported = false
	for _, supportedId in mapDefinition.supportedDifficultyIds do
		supported = supported or supportedId == difficulty.id
	end
	local economy = configuration.economy.byDifficultyId[difficulty.id]
	local scheduleKindMatches = (difficulty.kind == "Finite" and schedule.kind == "AuthoredFinite")
		or (difficulty.kind == "Endless" and schedule.kind == "GeneratedEndless")
	if not supported or not scheduleKindMatches or economy == nil or not supportedAttackContent(configuration) then
		return errorResult("CONTENT_NOT_FOUND", "new")
	end
	local laneId = mapDefinition.lanes[1] and mapDefinition.lanes[1].id
	if laneId == nil then
		return errorResult("CONTENT_NOT_FOUND", "new")
	end
	if schedule.kind == "AuthoredFinite" then
		if #schedule.waves ~= (difficulty :: ConfigTypes.FiniteDifficultyDefinition).waveCount then
			return errorResult("CONTENT_NOT_FOUND", "new")
		end
		for _, wave in schedule.waves do
			if not playableWaveValid(wave, laneId, configuration) then
				return errorResult("CONTENT_NOT_FOUND", "new")
			end
		end
	else
		for _, wave in schedule.authoredOpeningWaves do
			if not playableWaveValid(wave, laneId, configuration) then
				return errorResult("CONTENT_NOT_FOUND", "new")
			end
		end
		if schedule.generator.key ~= EndlessWaveGenerator.GENERATOR_KEY then
			return errorResult("CONTENT_NOT_FOUND", "new")
		end
	end
	local path, totalDistance, basePosition, bounds, zones, exclusions =
		normalizeMap(dependencies.runtimeMap, mapDefinition.id, laneId)
	if
		path == nil
		or totalDistance == nil
		or basePosition == nil
		or bounds == nil
		or zones == nil
		or exclusions == nil
	then
		return errorResult("INVALID_RUNTIME_MAP", "new")
	end
	local rawLoadouts = dependencies.participantLoadouts
	if rawLoadouts == nil and IS_EXACT_TEST_MODULE and type(dependencies.participantUserIds) == "table" then
		local testLoadouts = {}
		for _, userId in dependencies.participantUserIds do
			local slots = {}
			for index, definition in configuration.towers.ordered do
				if index > MatchLoadoutProtocol.MAX_SLOTS then
					break
				end
				table.insert(slots, {
					slot = index,
					unitId = `unit:test-{userId}-{index}`,
					towerId = definition.id,
				})
			end
			table.insert(testLoadouts, {
				userId = userId,
				revision = 1,
				slots = slots,
				settings = configuration.defaultSettings,
			})
		end
		rawLoadouts = testLoadouts
	end
	local participants, loadoutsByUserId =
		normalizeParticipants(rawLoadouts, configuration, studioDirectUserIds :: boolean)
	if participants == nil or loadoutsByUserId == nil then
		return errorResult("INVALID_PARTICIPANTS", "new")
	end
	local seed = dependencies.seed
	if seed == nil then
		seed = EndlessWaveGenerator.deriveSeed(matchIdResult.value, EndlessWaveGenerator.CONTENT_VERSION)
	end
	if
		type(seed) ~= "number"
		or not Validation.isSafeInteger(seed)
		or seed < 1
		or seed > EndlessWaveGenerator.MAX_SEED
	then
		return errorResult("INVALID_DEPENDENCIES", "new")
	end
	local ledgerResult = BattleCashLedger.new(
		matchIdResult.value,
		economy.startingBattleCash,
		economy.damageIncome.battleCashNumerator,
		economy.damageIncome.healthRemovedDenominator
	)
	if not ledgerResult.ok then
		return errorResult("LEDGER_FAILED", "new")
	end
	local participantSet: { [number]: boolean } = {}
	local participantStats: { [number]: ParticipantStats } = {}
	for _, userId in participants do
		local initialized = ledgerResult.value:initializeParticipant(userId)
		if not initialized.ok then
			ledgerResult.value:cleanup()
			return errorResult("LEDGER_FAILED", "new")
		end
		participantSet[userId] = true
		participantStats[userId] = {
			damageDealt = 0,
			placements = 0,
			upgrades = 0,
			sells = 0,
			wavesParticipated = 0,
			lastCreditedWave = 0,
		}
	end
	local connectedParticipantSet =
		normalizeConnectedParticipants(dependencies.connectedParticipantUserIds, participants, participantSet)
	if connectedParticipantSet == nil then
		ledgerResult.value:cleanup()
		return errorResult("INVALID_PARTICIPANTS", "new")
	end
	for _, userId in participants do
		if not connectedParticipantSet[userId] then
			local deactivated = ledgerResult.value:setParticipantActive(userId, false)
			if not deactivated.ok then
				ledgerResult.value:cleanup()
				return errorResult("LEDGER_FAILED", "new")
			end
		end
	end
	local everConnectedParticipantSet: { [number]: boolean } = {}
	for userId in connectedParticipantSet do
		everConnectedParticipantSet[userId] = true
	end
	local runtime = setmetatable({}, Methods) :: Runtime
	table.freeze(runtime)
	DATA[runtime] = {
		matchId = matchIdResult.value,
		configuration = configuration,
		mapDefinition = mapDefinition,
		difficulty = difficulty,
		schedule = schedule,
		modeKind = difficulty.kind,
		seed = seed,
		contentVersion = EndlessWaveGenerator.CONTENT_VERSION,
		economy = economy,
		ledger = ledgerResult.value,
		state = "Ready",
		result = "None",
		wavePhase = "Ready",
		revision = 1,
		participants = participants,
		participantSet = participantSet,
		connectedParticipantSet = connectedParticipantSet,
		everConnectedParticipantSet = everConnectedParticipantSet,
		loadoutsByUserId = loadoutsByUserId,
		ready = {},
		participantStats = participantStats,
		submittedReady = {},
		connectedAtResults = {},
		rewardViewsByUserId = {},
		rewarding = (rewarding :: boolean)
			and not (mapDefinition.id == DEVELOPMENT_MAP_ID and difficulty.id == DEVELOPMENT_DIFFICULTY_ID),
		studioDirectUserIds = studioDirectUserIds :: boolean,
		path = path,
		pathTotalDistance = totalDistance,
		basePosition = basePosition,
		bounds = bounds,
		placementZones = zones,
		exclusions = exclusions,
		towers = {},
		enemies = {},
		nextTowerId = 1,
		nextEnemyId = 1,
		attackSequence = 0,
		waveNumber = 0,
		wavesCompleted = 0,
		currentWave = nil,
		waveOrigins = {},
		resolvedWaveNumbers = {},
		activeWaveOriginCount = 0,
		spawnQueue = {},
		spawnCursor = 1,
		nextWaveServerTime = 0,
		startedServerTime = 0,
		endedServerTime = 0,
		lastSimulationServerTime = 0,
		terminationReason = nil,
		baseHealth = difficulty.base.maxHealth,
		busy = false,
		cleaned = false,
	}
	return Result.ok(runtime)
end

table.freeze(Methods)
return table.freeze(PlayableMatchRuntime)
