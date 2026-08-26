--!strict

local DifficultySchema = require(script.Parent.DifficultySchema)
local EnemySchema = require(script.Parent.EnemySchema)
local MapSchema = require(script.Parent.MapSchema)
local SchemaPrimitives = require(script.Parent.SchemaPrimitives)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

local ROOT_PATH: { Validation.PathSegment } = { "WaveSchedules" }

local SCHEDULE_FIELDS: { [string]: boolean } = table.freeze({
	authoredOpeningWaves = true,
	difficultyId = true,
	generator = true,
	kind = true,
	mapId = true,
	waves = true,
})

local SCHEDULE_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	activeEnemies = true,
	currentWave = true,
	deadlineAt = true,
	nextWaveAt = true,
	random = true,
	runtimeScheduleId = true,
	seed = true,
	startedAt = true,
	state = true,
})

local WAVE_FIELDS: { [string]: boolean } = table.freeze({
	bossKind = true,
	deadlinePolicy = true,
	deadlineSeconds = true,
	groups = true,
	id = true,
	rewardClass = true,
})

local WAVE_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	aliveEnemyCount = true,
	deadlineAt = true,
	resolvedEnemyCount = true,
	spawnedEnemyCount = true,
	startedAt = true,
	state = true,
	votes = true,
})

local GROUP_FIELDS: { [string]: boolean } = table.freeze({
	count = true,
	enemyId = true,
	laneId = true,
	spawnIntervalSeconds = true,
	startDelaySeconds = true,
})

local GROUP_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	aliveCount = true,
	nextSpawnAt = true,
	remainingCount = true,
	spawnedCount = true,
})

local DEADLINE_POLICIES: { [string]: boolean } = table.freeze({
	AllSpawnsByDeadline = true,
	AllowScheduledOverlap = true,
})

local BOSS_KINDS: { [string]: boolean } = table.freeze({
	Boss = true,
	MiniBoss = true,
	None = true,
})

local REWARD_CLASSES: { [string]: boolean } = table.freeze({
	Final = true,
	Milestone = true,
	Standard = true,
})

type ValidationState = {
	firstWaveIdPaths: { [string]: string },
	firstPairPaths: { [string]: { [string]: string } },
	totalAuthoredWaves: number,
	totalAuthoredGroups: number,
	totalAuthoredSpawns: number,
	byId: { [Ids.WaveId]: ConfigTypes.AuthoredWaveDefinition },
	byMapId: { [Ids.MapId]: { [Ids.DifficultyId]: ConfigTypes.WaveScheduleDefinition } },
}

local validatedCatalogs: { [ConfigTypes.WaveCatalog]: boolean } = setmetatable({}, {
	__mode = "k",
}) :: any

local WaveSchema = {}

local function dependencyIssue(pathName: string, message: string): Validation.Issue
	return Validation.issue("INVALID_REFERENCE", { pathName }, message)
end

local function requiredEnum(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment },
	values: { [string]: boolean },
	label: string
): (string?, Validation.Issue?)
	local value, missingIssue = Validation.getRequiredField(record, fieldName, path)
	if missingIssue ~= nil then
		return nil, missingIssue
	end
	local fieldPath = Validation.appendPath(path, fieldName)
	if type(value) ~= "string" then
		return nil, Validation.issueWithType("INVALID_TYPE", fieldPath, label .. " must be a string", value)
	end
	if values[value] ~= true then
		return nil, Validation.issue("INVALID_ENUM", fieldPath, label .. " is not recognized")
	end
	return value, nil
end

local function buildLaneSet(map: ConfigTypes.MapDefinition): { [string]: boolean }
	local laneSet: { [string]: boolean } = {}
	local lanes = rawget(map :: any, "lanes") :: { ConfigTypes.MapLaneDefinition }
	for index = 1, #lanes do
		laneSet[rawget(lanes[index] :: any, "id")] = true
	end
	return laneSet
end

local function mapSupportsDifficulty(map: ConfigTypes.MapDefinition, difficultyId: Ids.DifficultyId): boolean
	local ids = rawget(map :: any, "supportedDifficultyIds") :: { Ids.DifficultyId }
	for index = 1, #ids do
		if ids[index] == difficultyId then
			return true
		end
	end
	return false
end

local function validateGroup(
	value: unknown,
	path: { Validation.PathSegment },
	enemies: ConfigTypes.EnemyCatalog,
	difficulty: ConfigTypes.DifficultyDefinition,
	laneSet: { [string]: boolean },
	deadlinePolicy: ConfigTypes.WaveDeadlinePolicy,
	deadlineSeconds: number,
	state: ValidationState
): (ConfigTypes.WaveSpawnGroupDefinition?, number?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, GROUP_FIELDS, GROUP_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, nil, recordIssue
	end

	state.totalAuthoredGroups += 1
	if state.totalAuthoredGroups > Validation.MAX_AUTHORED_WAVE_GROUPS then
		return nil, nil, Validation.issue("OUT_OF_RANGE", path, "Wave catalog exceeds its authored-group limit")
	end

	local rawEnemyId, enemyIdMissing = Validation.getRequiredField(record :: Validation.RawObject, "enemyId", path)
	if enemyIdMissing ~= nil then
		return nil, nil, enemyIdMissing
	end
	local enemyIdPath = Validation.appendPath(path, "enemyId")
	local enemyIdResult = Ids.validateEnemyId(rawEnemyId)
	if not enemyIdResult.ok then
		return nil,
			nil,
			Validation.issueWithCause(
				"INVALID_ID",
				enemyIdPath,
				"Wave-group enemy ID is invalid",
				enemyIdResult.error.code
			)
	end
	local enemyId = enemyIdResult.value
	local enemyById = rawget(enemies :: any, "byId")
	local enemy = rawget(enemyById, enemyId) :: ConfigTypes.EnemyDefinition?
	if enemy == nil then
		return nil,
			nil,
			Validation.issue("INVALID_REFERENCE", enemyIdPath, "Wave-group enemy is not present in the catalog")
	end
	local modifiers = rawget(difficulty :: any, "modifiers")
	local derivedHealth = (rawget(enemy :: any, "maxHealth") :: number)
		* rawget(modifiers, "enemyHealthMultiplier") :: number
	local derivedSpeed = (rawget(enemy :: any, "moveSpeedStudsPerSecond") :: number)
		* rawget(modifiers, "enemyMoveSpeedMultiplier") :: number
	if
		not Validation.isFiniteNumber(derivedHealth)
		or derivedHealth <= 0
		or not Validation.isFiniteNumber(derivedSpeed)
		or derivedSpeed <= 0
	then
		return nil,
			nil,
			Validation.issue(
				"OUT_OF_RANGE",
				enemyIdPath,
				"Referenced enemy stats do not compose safely with the difficulty modifiers"
			)
	end

	local laneId, laneIdIssue = SchemaPrimitives.requiredSymbolicKey(record :: Validation.RawObject, "laneId", path)
	if laneIdIssue ~= nil then
		return nil, nil, laneIdIssue
	end
	if laneSet[laneId :: string] ~= true then
		return nil,
			nil,
			Validation.issue(
				"INVALID_REFERENCE",
				Validation.appendPath(path, "laneId"),
				"Wave-group lane is not declared by the schedule map"
			)
	end

	local count, countIssue = SchemaPrimitives.boundedInteger(
		record :: Validation.RawObject,
		"count",
		path,
		1,
		Validation.MAX_GROUP_SPAWN_COUNT
	)
	if countIssue ~= nil then
		return nil, nil, countIssue
	end
	state.totalAuthoredSpawns += count :: number
	if state.totalAuthoredSpawns > Validation.MAX_AUTHORED_SPAWN_COUNT then
		return nil,
			nil,
			Validation.issue(
				"OUT_OF_RANGE",
				Validation.appendPath(path, "count"),
				"Wave catalog exceeds its authored-spawn limit"
			)
	end
	local startDelay, delayIssue = SchemaPrimitives.boundedNumber(
		record :: Validation.RawObject,
		"startDelaySeconds",
		path,
		0,
		Validation.MAX_WAVE_TIME_SECONDS
	)
	if delayIssue ~= nil then
		return nil, nil, delayIssue
	end
	local spawnInterval, intervalIssue = SchemaPrimitives.boundedNumber(
		record :: Validation.RawObject,
		"spawnIntervalSeconds",
		path,
		0,
		Validation.MAX_WAVE_TIME_SECONDS
	)
	if intervalIssue ~= nil then
		return nil, nil, intervalIssue
	end
	if (spawnInterval :: number) == 0 and (count :: number) > Validation.MAX_SIMULTANEOUS_GROUP_SPAWNS then
		return nil,
			nil,
			Validation.issue(
				"OUT_OF_RANGE",
				Validation.appendPath(path, "count"),
				"Zero-interval group exceeds the simultaneous-spawn limit"
			)
	end

	local lastSpawnSeconds = (startDelay :: number) + (spawnInterval :: number) * ((count :: number) - 1)
	local horizonTolerance = math.max(1, Validation.MAX_WAVE_TIME_SECONDS) * 1e-9
	if
		not Validation.isFiniteNumber(lastSpawnSeconds)
		or lastSpawnSeconds - Validation.MAX_WAVE_TIME_SECONDS > horizonTolerance
	then
		return nil,
			nil,
			Validation.issue(
				"OUT_OF_RANGE",
				Validation.appendPath(path, "spawnIntervalSeconds"),
				"Group's final scheduled spawn exceeds the technical wave-time limit"
			)
	end
	local deadlineTolerance = math.max(1, math.abs(deadlineSeconds), math.abs(lastSpawnSeconds)) * 1e-9
	if deadlinePolicy == "AllSpawnsByDeadline" and lastSpawnSeconds - deadlineSeconds > deadlineTolerance then
		local offendingField = if (startDelay :: number) - deadlineSeconds > deadlineTolerance
			then "startDelaySeconds"
			else "spawnIntervalSeconds"
		return nil,
			nil,
			Validation.issue(
				"INVALID_ORDER",
				Validation.appendPath(path, offendingField),
				"Group schedules a spawn after a deadline that forbids overlap"
			)
	end

	local group: ConfigTypes.WaveSpawnGroupDefinition = table.freeze({
		enemyId = enemyId,
		laneId = laneId :: ConfigTypes.FeatureKey,
		count = count :: number,
		startDelaySeconds = startDelay :: number,
		spawnIntervalSeconds = spawnInterval :: number,
	})
	return group, count, nil
end

local function validateWave(
	value: unknown,
	path: { Validation.PathSegment },
	sequenceIndex: number,
	isFinalFiniteWave: boolean,
	map: ConfigTypes.MapDefinition,
	difficulty: ConfigTypes.DifficultyDefinition,
	enemies: ConfigTypes.EnemyCatalog,
	state: ValidationState
): (ConfigTypes.AuthoredWaveDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, WAVE_FIELDS, WAVE_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	state.totalAuthoredWaves += 1
	if state.totalAuthoredWaves > Validation.MAX_AUTHORED_WAVES then
		return nil, Validation.issue("OUT_OF_RANGE", path, "Wave catalog exceeds its authored-wave limit")
	end

	local rawId, idMissing = Validation.getRequiredField(record :: Validation.RawObject, "id", path)
	if idMissing ~= nil then
		return nil, idMissing
	end
	local idPath = Validation.appendPath(path, "id")
	local idResult = Ids.validateWaveId(rawId)
	if not idResult.ok then
		return nil, Validation.issueWithCause("INVALID_ID", idPath, "Wave ID is invalid", idResult.error.code)
	end
	local id = idResult.value
	local firstIdPath = state.firstWaveIdPaths[id]
	if firstIdPath ~= nil then
		return nil,
			Validation.issueWithRelated(
				"DUPLICATE_ID",
				idPath,
				"Wave ID duplicates an earlier authored wave",
				firstIdPath
			)
	end
	state.firstWaveIdPaths[id] = Validation.renderPath(idPath)

	local deadlineSeconds, deadlineIssue = SchemaPrimitives.boundedNumber(
		record :: Validation.RawObject,
		"deadlineSeconds",
		path,
		0.01,
		Validation.MAX_WAVE_TIME_SECONDS
	)
	if deadlineIssue ~= nil then
		return nil, deadlineIssue
	end

	local rawPolicy, policyIssue =
		requiredEnum(record :: Validation.RawObject, "deadlinePolicy", path, DEADLINE_POLICIES, "Deadline policy")
	if policyIssue ~= nil then
		return nil, policyIssue
	end
	local deadlinePolicy = rawPolicy :: ConfigTypes.WaveDeadlinePolicy

	local rawBossKind, bossKindIssue =
		requiredEnum(record :: Validation.RawObject, "bossKind", path, BOSS_KINDS, "Boss kind")
	if bossKindIssue ~= nil then
		return nil, bossKindIssue
	end
	local bossKind = rawBossKind :: ConfigTypes.BossKind

	local rawRewardClass, rewardClassIssue =
		requiredEnum(record :: Validation.RawObject, "rewardClass", path, REWARD_CLASSES, "Reward class")
	if rewardClassIssue ~= nil then
		return nil, rewardClassIssue
	end
	local rewardClass = rawRewardClass :: ConfigTypes.WaveRewardClass

	local rawGroups, groupsMissing = Validation.getRequiredField(record :: Validation.RawObject, "groups", path)
	if groupsMissing ~= nil then
		return nil, groupsMissing
	end
	local rawGroupArray, groupArrayIssue =
		Validation.readArray(rawGroups, Validation.appendPath(path, "groups"), Validation.MAX_WAVE_GROUPS)
	if groupArrayIssue ~= nil then
		return nil, groupArrayIssue
	end

	local laneSet = buildLaneSet(map)
	local groups: { ConfigTypes.WaveSpawnGroupDefinition } = {}
	local totalSpawnCount = 0
	local simultaneousSpawnsByTime: { [number]: number } = {}
	local previousStartDelay: number? = nil
	local previousStartDelayPath: string? = nil
	for groupIndex = 1, #(rawGroupArray :: { unknown }) do
		local group, count, groupIssue = validateGroup(
			(rawGroupArray :: { unknown })[groupIndex],
			Validation.appendPath(Validation.appendPath(path, "groups"), groupIndex),
			enemies,
			difficulty,
			laneSet,
			deadlinePolicy,
			deadlineSeconds :: number,
			state
		)
		if groupIssue ~= nil then
			return nil, groupIssue
		end
		totalSpawnCount += count :: number
		if totalSpawnCount > Validation.MAX_WAVE_SPAWN_COUNT then
			return nil,
				Validation.issue(
					"OUT_OF_RANGE",
					Validation.appendPath(
						Validation.appendPath(Validation.appendPath(path, "groups"), groupIndex),
						"count"
					),
					"Wave exceeds its technical scheduled-enemy limit"
				)
		end
		local canonicalGroup = group :: ConfigTypes.WaveSpawnGroupDefinition
		local startDelayPath = Validation.appendPath(
			Validation.appendPath(Validation.appendPath(path, "groups"), groupIndex),
			"startDelaySeconds"
		)
		if previousStartDelay ~= nil and canonicalGroup.startDelaySeconds < previousStartDelay then
			return nil,
				Validation.issueWithRelated(
					"INVALID_ORDER",
					startDelayPath,
					"Wave groups must be ordered by nondecreasing start delay",
					previousStartDelayPath :: string
				)
		end
		previousStartDelay = canonicalGroup.startDelaySeconds
		previousStartDelayPath = Validation.renderPath(startDelayPath)

		for spawnIndex = 0, canonicalGroup.count - 1 do
			local spawnTime = canonicalGroup.startDelaySeconds + canonicalGroup.spawnIntervalSeconds * spawnIndex
			local burstCount = (simultaneousSpawnsByTime[spawnTime] or 0) + 1
			if burstCount > Validation.MAX_SIMULTANEOUS_WAVE_SPAWNS then
				return nil,
					Validation.issue(
						"OUT_OF_RANGE",
						Validation.appendPath(
							Validation.appendPath(Validation.appendPath(path, "groups"), groupIndex),
							"count"
						),
						"Wave exceeds the simultaneous-spawn limit at one authored time"
					)
			end
			simultaneousSpawnsByTime[spawnTime] = burstCount
		end
		table.insert(groups, canonicalGroup)
	end
	if bossKind ~= "None" and #groups == 0 then
		return nil,
			Validation.issue(
				"EMPTY_COLLECTION",
				Validation.appendPath(path, "groups"),
				"Boss-marked wave must declare at least one spawn group"
			)
	end

	local cadence = rawget(rawget(difficulty :: any, "timing"), "bossCadenceWaves") :: number
	local isCadenceWave = sequenceIndex % cadence == 0
	if isCadenceWave and bossKind ~= "Boss" then
		return nil,
			Validation.issue(
				"INVALID_ORDER",
				Validation.appendPath(path, "bossKind"),
				"Boss-cadence wave must use the Boss marker"
			)
	end
	if not isCadenceWave and bossKind == "Boss" then
		return nil,
			Validation.issue(
				"INVALID_ORDER",
				Validation.appendPath(path, "bossKind"),
				"Boss marker is reserved for the configured cadence"
			)
	end

	if isFinalFiniteWave then
		if rewardClass ~= "Final" then
			return nil,
				Validation.issue(
					"INVALID_ORDER",
					Validation.appendPath(path, "rewardClass"),
					"Final finite wave must use Final reward metadata"
				)
		end
	elseif rewardClass == "Final" then
		return nil,
			Validation.issue(
				"INVALID_ORDER",
				Validation.appendPath(path, "rewardClass"),
				"Only the final finite wave may use Final reward metadata"
			)
	elseif bossKind == "None" and rewardClass ~= "Standard" then
		return nil,
			Validation.issue(
				"INVALID_ORDER",
				Validation.appendPath(path, "rewardClass"),
				"Ordinary wave must use Standard reward metadata"
			)
	elseif bossKind ~= "None" and rewardClass ~= "Milestone" then
		return nil,
			Validation.issue(
				"INVALID_ORDER",
				Validation.appendPath(path, "rewardClass"),
				"Boss or miniboss wave must use Milestone reward metadata"
			)
	end

	local wave: ConfigTypes.AuthoredWaveDefinition = table.freeze({
		id = id,
		deadlineSeconds = deadlineSeconds :: number,
		deadlinePolicy = deadlinePolicy,
		bossKind = bossKind,
		rewardClass = rewardClass,
		groups = table.freeze(groups),
	})
	state.byId[id] = wave
	return wave, nil
end

local function validateWaveList(
	value: unknown,
	path: { Validation.PathSegment },
	map: ConfigTypes.MapDefinition,
	difficulty: ConfigTypes.DifficultyDefinition,
	enemies: ConfigTypes.EnemyCatalog,
	isFinite: boolean,
	state: ValidationState
): ({ ConfigTypes.AuthoredWaveDefinition }?, Validation.Issue?)
	local rawWaves, arrayIssue = Validation.readArray(value, path, Validation.MAX_WAVES_PER_SCHEDULE)
	if arrayIssue ~= nil then
		return nil, arrayIssue
	end

	if isFinite then
		local expectedCount = rawget(difficulty :: any, "waveCount") :: number
		if #(rawWaves :: { unknown }) ~= expectedCount then
			return nil,
				Validation.issue("INVALID_ORDER", path, "Finite schedule length must equal the difficulty wave count")
		end
	end

	local waves: { ConfigTypes.AuthoredWaveDefinition } = {}
	for index = 1, #(rawWaves :: { unknown }) do
		local wave, issue = validateWave(
			(rawWaves :: { unknown })[index],
			Validation.appendPath(path, index),
			index,
			isFinite and index == #(rawWaves :: { unknown }),
			map,
			difficulty,
			enemies,
			state
		)
		if issue ~= nil then
			return nil, issue
		end
		table.insert(waves, wave :: ConfigTypes.AuthoredWaveDefinition)
	end

	return table.freeze(waves), nil
end

local function registerPair(
	mapId: Ids.MapId,
	difficultyId: Ids.DifficultyId,
	difficultyPath: { Validation.PathSegment },
	state: ValidationState
): Validation.Issue?
	local mapPairs = state.firstPairPaths[mapId]
	if mapPairs == nil then
		mapPairs = {}
		state.firstPairPaths[mapId] = mapPairs
	end
	local firstPath = mapPairs[difficultyId]
	if firstPath ~= nil then
		return Validation.issueWithRelated(
			"DUPLICATE_VALUE",
			difficultyPath,
			"Map and difficulty pair duplicates an earlier wave schedule",
			firstPath
		)
	end
	mapPairs[difficultyId] = Validation.renderPath(difficultyPath)
	return nil
end

local function validateScheduleAt(
	value: unknown,
	path: { Validation.PathSegment },
	maps: ConfigTypes.MapCatalog,
	difficulties: ConfigTypes.DifficultyCatalog,
	enemies: ConfigTypes.EnemyCatalog,
	state: ValidationState
): (ConfigTypes.WaveScheduleDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, SCHEDULE_FIELDS, SCHEDULE_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawKind, kindMissing = Validation.getRequiredField(record :: Validation.RawObject, "kind", path)
	if kindMissing ~= nil then
		return nil, kindMissing
	end
	local kindPath = Validation.appendPath(path, "kind")
	if type(rawKind) ~= "string" then
		return nil, Validation.issueWithType("INVALID_TYPE", kindPath, "Schedule kind must be a string", rawKind)
	end
	if rawKind ~= "AuthoredFinite" and rawKind ~= "GeneratedEndless" then
		return nil, Validation.issue("INVALID_ENUM", kindPath, "Schedule kind is not recognized")
	end

	local rawMapId, mapIdMissing = Validation.getRequiredField(record :: Validation.RawObject, "mapId", path)
	if mapIdMissing ~= nil then
		return nil, mapIdMissing
	end
	local mapIdPath = Validation.appendPath(path, "mapId")
	local mapIdResult = Ids.validateMapId(rawMapId)
	if not mapIdResult.ok then
		return nil,
			Validation.issueWithCause("INVALID_ID", mapIdPath, "Schedule map ID is invalid", mapIdResult.error.code)
	end
	local mapId = mapIdResult.value
	local map = rawget(rawget(maps :: any, "byId"), mapId) :: ConfigTypes.MapDefinition?
	if map == nil then
		return nil, Validation.issue("INVALID_REFERENCE", mapIdPath, "Schedule map is not present in the catalog")
	end

	local rawDifficultyId, difficultyIdMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "difficultyId", path)
	if difficultyIdMissing ~= nil then
		return nil, difficultyIdMissing
	end
	local difficultyIdPath = Validation.appendPath(path, "difficultyId")
	local difficultyIdResult = Ids.validateDifficultyId(rawDifficultyId)
	if not difficultyIdResult.ok then
		return nil,
			Validation.issueWithCause(
				"INVALID_ID",
				difficultyIdPath,
				"Schedule difficulty ID is invalid",
				difficultyIdResult.error.code
			)
	end
	local difficultyId = difficultyIdResult.value
	local difficulty = rawget(rawget(difficulties :: any, "byId"), difficultyId) :: ConfigTypes.DifficultyDefinition?
	if difficulty == nil then
		return nil,
			Validation.issue("INVALID_REFERENCE", difficultyIdPath, "Schedule difficulty is not present in the catalog")
	end
	if not mapSupportsDifficulty(map, difficultyId) then
		return nil,
			Validation.issue("INVALID_REFERENCE", difficultyIdPath, "Schedule difficulty is not supported by the map")
	end
	local pairIssue = registerPair(mapId, difficultyId, difficultyIdPath, state)
	if pairIssue ~= nil then
		return nil, pairIssue
	end

	local difficultyKind = rawget(difficulty :: any, "kind")
	if rawKind == "AuthoredFinite" and difficultyKind ~= "Finite" then
		return nil, Validation.issue("INVALID_REFERENCE", kindPath, "Finite schedule requires a finite difficulty")
	end
	if rawKind == "GeneratedEndless" and difficultyKind ~= "Endless" then
		return nil, Validation.issue("INVALID_REFERENCE", kindPath, "Endless schedule requires an Endless difficulty")
	end

	if rawKind == "AuthoredFinite" then
		if Validation.getField(record :: Validation.RawObject, "authoredOpeningWaves") ~= nil then
			return nil,
				Validation.issue(
					"INVALID_REFERENCE",
					Validation.appendPath(path, "authoredOpeningWaves"),
					"Finite schedule must not declare Endless opening waves"
				)
		end
		if Validation.getField(record :: Validation.RawObject, "generator") ~= nil then
			return nil,
				Validation.issue(
					"INVALID_REFERENCE",
					Validation.appendPath(path, "generator"),
					"Finite schedule must not declare an Endless generator"
				)
		end

		local rawWaves, wavesMissing = Validation.getRequiredField(record :: Validation.RawObject, "waves", path)
		if wavesMissing ~= nil then
			return nil, wavesMissing
		end
		local waves, wavesIssue =
			validateWaveList(rawWaves, Validation.appendPath(path, "waves"), map, difficulty, enemies, true, state)
		if wavesIssue ~= nil then
			return nil, wavesIssue
		end

		local schedule: ConfigTypes.FiniteWaveScheduleDefinition = table.freeze({
			kind = "AuthoredFinite",
			mapId = mapId,
			difficultyId = difficultyId,
			waves = waves :: { ConfigTypes.AuthoredWaveDefinition },
		})
		return schedule, nil
	end

	if Validation.getField(record :: Validation.RawObject, "waves") ~= nil then
		return nil,
			Validation.issue(
				"INVALID_REFERENCE",
				Validation.appendPath(path, "waves"),
				"Endless schedule must use authoredOpeningWaves"
			)
	end
	local rawOpeningWaves, openingMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "authoredOpeningWaves", path)
	if openingMissing ~= nil then
		return nil, openingMissing
	end
	local openingWaves, openingIssue = validateWaveList(
		rawOpeningWaves,
		Validation.appendPath(path, "authoredOpeningWaves"),
		map,
		difficulty,
		enemies,
		false,
		state
	)
	if openingIssue ~= nil then
		return nil, openingIssue
	end

	local rawGenerator, generatorMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "generator", path)
	if generatorMissing ~= nil then
		return nil, generatorMissing
	end
	local generator, generatorIssue = SchemaPrimitives.featureReference(
		rawGenerator,
		Validation.appendPath(path, "generator"),
		"EndlessWaveGenerator"
	)
	if generatorIssue ~= nil then
		return nil, generatorIssue
	end

	local schedule: ConfigTypes.EndlessWaveScheduleDefinition = table.freeze({
		kind = "GeneratedEndless",
		mapId = mapId,
		difficultyId = difficultyId,
		authoredOpeningWaves = openingWaves :: { ConfigTypes.AuthoredWaveDefinition },
		generator = generator :: ConfigTypes.EndlessWaveGeneratorReference,
	})
	return schedule, nil
end

local function validateCoverage(
	maps: ConfigTypes.MapCatalog,
	byMapId: { [Ids.MapId]: { [Ids.DifficultyId]: ConfigTypes.WaveScheduleDefinition } }
): Validation.Issue?
	local orderedMaps = rawget(maps :: any, "ordered") :: { ConfigTypes.MapDefinition }
	for mapIndex = 1, #orderedMaps do
		local map = orderedMaps[mapIndex]
		local mapId = rawget(map :: any, "id") :: Ids.MapId
		local difficultyIds = rawget(map :: any, "supportedDifficultyIds") :: { Ids.DifficultyId }
		local schedules = byMapId[mapId]
		for difficultyIndex = 1, #difficultyIds do
			local difficultyId = difficultyIds[difficultyIndex]
			if schedules == nil or schedules[difficultyId] == nil then
				return Validation.issue("INVALID_REFERENCE", {
					"Maps",
					mapIndex,
					"supportedDifficultyIds",
					difficultyIndex,
				}, "Supported map and difficulty pair has no wave schedule")
			end
		end
	end
	return nil
end

function WaveSchema.validateCatalog(
	value: unknown,
	maps: ConfigTypes.MapCatalog,
	difficulties: ConfigTypes.DifficultyCatalog,
	enemies: ConfigTypes.EnemyCatalog
): Result.Result<ConfigTypes.WaveCatalog, Validation.Issue>
	if not MapSchema.isValidatedCatalog(maps) then
		return Result.err(dependencyIssue("MapCatalog", "Expected a map catalog validated by MapSchema"))
	end
	if not DifficultySchema.isValidatedCatalog(difficulties) then
		return Result.err(
			dependencyIssue("DifficultyCatalog", "Expected a difficulty catalog validated by DifficultySchema")
		)
	end
	if not EnemySchema.isValidatedCatalog(enemies) then
		return Result.err(dependencyIssue("EnemyCatalog", "Expected an enemy catalog validated by EnemySchema"))
	end

	local rawSchedules, arrayIssue = Validation.readArray(value, ROOT_PATH, Validation.MAX_CATALOG_ENTRIES)
	if arrayIssue ~= nil then
		return Result.err(arrayIssue)
	end

	local state: ValidationState = {
		firstWaveIdPaths = {},
		firstPairPaths = {},
		totalAuthoredWaves = 0,
		totalAuthoredGroups = 0,
		totalAuthoredSpawns = 0,
		byId = {},
		byMapId = {},
	}
	local ordered: { ConfigTypes.WaveScheduleDefinition } = {}
	for index = 1, #(rawSchedules :: { unknown }) do
		local schedule, issue = validateScheduleAt(
			(rawSchedules :: { unknown })[index],
			Validation.appendPath(ROOT_PATH, index),
			maps,
			difficulties,
			enemies,
			state
		)
		if issue ~= nil then
			return Result.err(issue)
		end

		local canonical = schedule :: ConfigTypes.WaveScheduleDefinition
		table.insert(ordered, canonical)
		local mapSchedules = state.byMapId[canonical.mapId]
		if mapSchedules == nil then
			mapSchedules = {}
			state.byMapId[canonical.mapId] = mapSchedules
		end
		mapSchedules[canonical.difficultyId] = canonical
	end

	local coverageIssue = validateCoverage(maps, state.byMapId)
	if coverageIssue ~= nil then
		return Result.err(coverageIssue)
	end

	for _, difficultySchedules in state.byMapId do
		table.freeze(difficultySchedules)
	end
	local catalog: ConfigTypes.WaveCatalog = table.freeze({
		ordered = table.freeze(ordered),
		byId = table.freeze(state.byId),
		byMapId = table.freeze(state.byMapId),
	})
	validatedCatalogs[catalog] = true
	return Result.ok(catalog)
end

function WaveSchema.isValidatedCatalog(value: unknown): boolean
	return type(value) == "table" and validatedCatalogs[value :: any] == true
end

return table.freeze(WaveSchema)
