--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ContentSelection = require(ReplicatedStorage.Shared.config.ContentSelection)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type GeneratedWave = {
	wave: ConfigTypes.AuthoredWaveDefinition,
	healthMultiplier: number,
	moveSpeedMultiplier: number,
}

export type GeneratorError = "INVALID_ARGUMENT" | "UNSUPPORTED_GENERATOR" | "CONTENT_UNAVAILABLE"

local CONTENT_VERSION = ContentSelection.CONTENT_VERSION
local GENERATOR_KEY = ContentSelection.ENDLESS_GENERATOR_KEY
local MAX_GROUPS = 6
local MAX_SPAWNS_PER_WAVE = 72
local MAX_HEALTH_MULTIPLIER = 30
local MAX_MOVE_SPEED_MULTIPLIER = 1.6
local MAX_SEED = 2_147_483_647

local ROLE_TAGS = table.freeze({
	"role.basic",
	"role.fast",
	"role.swarm",
	"role.durable",
})

local EndlessWaveGenerator = {
	CONTENT_VERSION = CONTENT_VERSION,
	GENERATOR_KEY = GENERATOR_KEY,
	MAX_GROUPS = MAX_GROUPS,
	MAX_SPAWNS_PER_WAVE = MAX_SPAWNS_PER_WAVE,
	MAX_HEALTH_MULTIPLIER = MAX_HEALTH_MULTIPLIER,
	MAX_MOVE_SPEED_MULTIPLIER = MAX_MOVE_SPEED_MULTIPLIER,
	MAX_SEED = MAX_SEED,
}

local function validPositiveInteger(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and (value :: number) >= 1
end

-- Only exact integer addition and bit32 operations are used so a generated wave
-- is independent of engine RNG state and of the order in which waves are asked
-- for. Wave number is mixed as text to retain stable behavior for large safe
-- integers without relying on imprecise integer multiplication.
local function hashText(value: string, initial: number): number
	local state = bit32.band(initial, 0x7FFFFFFF)
	for index = 1, #value do
		state = bit32.bxor(state, string.byte(value, index) :: number)
		state = bit32.band(bit32.lrotate(state, 5) + 0x1F123BB5 + index, 0x7FFFFFFF)
	end
	return state
end

local function draw(seed: number, waveNumber: number, drawIndex: number): number
	local state = hashText(tostring(seed), 0x13579BDF)
	state = hashText(tostring(waveNumber), bit32.bxor(state, 0x2468ACE0))
	return hashText(tostring(drawIndex), bit32.bxor(state, 0x51ED270B))
end

function EndlessWaveGenerator.deriveSeed(matchIdValue: unknown, contentVersionValue: unknown?): number?
	if type(matchIdValue) ~= "string" or #matchIdValue < 1 then
		return nil
	end
	local contentVersion = contentVersionValue or CONTENT_VERSION
	if not validPositiveInteger(contentVersion) then
		return nil
	end
	return 1 + hashText(`{contentVersion}:{matchIdValue}`, 0x31415926) % MAX_SEED
end

local function hasTag(definition: any, expected: string): boolean
	if type(definition.tags) ~= "table" then
		return false
	end
	for _, tag in definition.tags do
		if tag == expected then
			return true
		end
	end
	return false
end

local function threatClass(definition: any): string
	local value = definition.threatClass
	if value == "Elite" or value == "MiniBoss" or value == "Boss" then
		return value
	end
	return "Standard"
end

type Pools = {
	all: { ConfigTypes.EnemyDefinition },
	ordinary: { ConfigTypes.EnemyDefinition },
	standard: { ConfigTypes.EnemyDefinition },
	elite: { ConfigTypes.EnemyDefinition },
	miniBoss: { ConfigTypes.EnemyDefinition },
	boss: { ConfigTypes.EnemyDefinition },
	roles: { [string]: { ConfigTypes.EnemyDefinition } },
}

local function buildPools(configuration: ConfigTypes.CoreConfiguration): Pools?
	local pools: Pools = {
		all = {},
		ordinary = {},
		standard = {},
		elite = {},
		miniBoss = {},
		boss = {},
		roles = {},
	}
	for _, roleTag in ROLE_TAGS do
		pools.roles[roleTag] = {}
	end
	for _, definition in configuration.enemies.ordered do
		table.insert(pools.all, definition)
		local class = threatClass(definition)
		if class == "Boss" or hasTag(definition, "role.boss") then
			table.insert(pools.boss, definition)
		elseif class == "MiniBoss" then
			table.insert(pools.miniBoss, definition)
		elseif class == "Elite" then
			table.insert(pools.elite, definition)
			table.insert(pools.ordinary, definition)
		else
			table.insert(pools.standard, definition)
			table.insert(pools.ordinary, definition)
		end
		if class ~= "Boss" and class ~= "MiniBoss" then
			for _, roleTag in ROLE_TAGS do
				if hasTag(definition, roleTag) or (roleTag == "role.durable" and hasTag(definition, "role.tank")) then
					table.insert(pools.roles[roleTag], definition)
				end
			end
		end
	end
	return if #pools.ordinary > 0 then pools else nil
end

local function strongest(values: { ConfigTypes.EnemyDefinition }): ConfigTypes.EnemyDefinition?
	local selected: ConfigTypes.EnemyDefinition? = nil
	for _, definition in values do
		if
			selected == nil
			or definition.maxHealth > selected.maxHealth
			or (definition.maxHealth == selected.maxHealth and definition.id < selected.id)
		then
			selected = definition
		end
	end
	return selected
end

local function selectFrom(
	values: { ConfigTypes.EnemyDefinition },
	fallback: { ConfigTypes.EnemyDefinition },
	value: number
): ConfigTypes.EnemyDefinition
	local source = if #values > 0 then values else fallback
	return source[1 + value % #source]
end

local function freezeGroup(
	definition: ConfigTypes.EnemyDefinition,
	laneId: string,
	count: number,
	startDelaySeconds: number,
	spawnIntervalSeconds: number
): ConfigTypes.WaveSpawnGroupDefinition
	return table.freeze({
		enemyId = definition.id,
		laneId = laneId,
		count = count,
		startDelaySeconds = startDelaySeconds,
		spawnIntervalSeconds = spawnIntervalSeconds,
	})
end

function EndlessWaveGenerator.generate(
	configurationValue: unknown,
	generatorKeyValue: unknown,
	seedValue: unknown,
	waveNumberValue: unknown,
	laneIdValue: unknown
): Result.Result<GeneratedWave, GeneratorError>
	if
		type(configurationValue) ~= "table"
		or type(generatorKeyValue) ~= "string"
		or not validPositiveInteger(seedValue)
		or (seedValue :: number) > MAX_SEED
		or not validPositiveInteger(waveNumberValue)
		or type(laneIdValue) ~= "string"
		or not Validation.isSymbolicKey(laneIdValue :: string)
	then
		return Result.err("INVALID_ARGUMENT")
	end
	if generatorKeyValue ~= GENERATOR_KEY then
		return Result.err("UNSUPPORTED_GENERATOR")
	end
	local configuration = configurationValue :: ConfigTypes.CoreConfiguration
	if type(configuration.enemies) ~= "table" or type(configuration.enemies.ordered) ~= "table" then
		return Result.err("CONTENT_UNAVAILABLE")
	end
	local pools = buildPools(configuration)
	if pools == nil then
		return Result.err("CONTENT_UNAVAILABLE")
	end

	local seed = seedValue :: number
	local waveNumber = waveNumberValue :: number
	local laneId = laneIdValue :: string
	local boundedProgress = math.min(waveNumber, 10_000)
	local bossWave = waveNumber % 10 == 0
	local miniBossWave = not bossWave and waveNumber >= 15 and waveNumber % 5 == 0
	local normalGroupCount = math.min(5, 2 + math.floor((boundedProgress - 1) / 20))
	local totalNormalCount = math.min(
		MAX_SPAWNS_PER_WAVE - if bossWave or miniBossWave then 1 else 0,
		12 + math.floor(boundedProgress * 1.2)
	)
	local groups: { ConfigTypes.WaveSpawnGroupDefinition } = {}
	local remaining = totalNormalCount
	for groupIndex = 1, normalGroupCount do
		local groupsLeft = normalGroupCount - groupIndex + 1
		local count = math.max(1, math.floor(remaining / groupsLeft))
		remaining -= count
		local availableRoles = { "role.basic" }
		if waveNumber >= 12 then
			table.insert(availableRoles, "role.fast")
		end
		if waveNumber >= 13 then
			table.insert(availableRoles, "role.swarm")
		end
		if waveNumber >= 15 then
			table.insert(availableRoles, "role.durable")
		end
		local role = availableRoles[1 + draw(seed, waveNumber, groupIndex * 3) % #availableRoles]
		local rolePool = pools.roles[role]
		local fallback = if #pools.standard > 0 then pools.standard else pools.ordinary
		local definition = selectFrom(rolePool, fallback, draw(seed, waveNumber, groupIndex * 3 + 1))
		local intervalHundredths = 38 + draw(seed, waveNumber, groupIndex * 3 + 2) % 63
		local startDelay = (groupIndex - 1) * 1.5
		table.insert(groups, freezeGroup(definition, laneId, count, startDelay, intervalHundredths / 100))
	end

	local bossKind: ConfigTypes.BossKind = "None"
	if bossWave then
		bossKind = "Boss"
		local boss = strongest(pools.boss)
			or strongest(pools.miniBoss)
			or strongest(pools.elite)
			or strongest(pools.all)
		table.insert(groups, freezeGroup(boss :: ConfigTypes.EnemyDefinition, laneId, 1, 7, 0))
	elseif miniBossWave and (#pools.miniBoss > 0 or #pools.elite > 0) then
		bossKind = "MiniBoss"
		local pool = if #pools.miniBoss > 0 then pools.miniBoss else pools.elite
		local miniBoss = selectFrom(pool, pools.all, draw(seed, waveNumber, 97))
		table.insert(groups, freezeGroup(miniBoss, laneId, 1, 6, 0))
	end

	local healthMultiplier = math.min(MAX_HEALTH_MULTIPLIER, 1 + math.floor(boundedProgress / 5) * 0.08)
	local moveSpeedMultiplier = math.min(MAX_MOVE_SPEED_MULTIPLIER, 1 + math.floor(boundedProgress / 20) * 0.015)
	local rewardClass: ConfigTypes.WaveRewardClass = if bossKind ~= "None" then "Milestone" else "Standard"
	local wave: ConfigTypes.AuthoredWaveDefinition = table.freeze({
		id = `wave:endless-v1-{waveNumber}`,
		deadlineSeconds = math.min(55, 34 + normalGroupCount * 3),
		deadlinePolicy = if waveNumber >= 21 then "AllowScheduledOverlap" else "AllSpawnsByDeadline",
		bossKind = bossKind,
		rewardClass = rewardClass,
		groups = table.freeze(groups),
	})
	return Result.ok(table.freeze({
		wave = wave,
		healthMultiplier = healthMultiplier,
		moveSpeedMultiplier = moveSpeedMultiplier,
	}))
end

return table.freeze(EndlessWaveGenerator)
