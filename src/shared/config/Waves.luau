--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local ContentSelection = require(script.Parent.ContentSelection)

type GroupSpec = {
	enemyId: string,
	count: number,
	startDelaySeconds: number,
	spawnIntervalSeconds: number,
}

type WaveSpec = {
	groups: { GroupSpec },
	bossKind: ConfigTypes.BossKind?,
}

local function group(enemyId: string, count: number, startDelay: number, interval: number): GroupSpec
	return {
		enemyId = enemyId,
		count = count,
		startDelaySeconds = startDelay,
		spawnIntervalSeconds = interval,
	}
end

local function authoredGroups(specs: { GroupSpec }): { ConfigTypes.WaveSpawnGroupDefinition }
	local groups: { ConfigTypes.WaveSpawnGroupDefinition } = table.create(#specs)
	for index, spec in specs do
		groups[index] = {
			enemyId = spec.enemyId,
			laneId = "main",
			count = spec.count,
			startDelaySeconds = spec.startDelaySeconds,
			spawnIntervalSeconds = spec.spawnIntervalSeconds,
		}
	end
	return groups
end

local function authoredWaves(
	prefix: string,
	specs: { WaveSpec },
	finite: boolean
): { ConfigTypes.AuthoredWaveDefinition }
	local waves: { ConfigTypes.AuthoredWaveDefinition } = table.create(#specs)
	for index, spec in specs do
		local lastSpawnSeconds = 0
		for _, spawn in spec.groups do
			lastSpawnSeconds =
				math.max(lastSpawnSeconds, spawn.startDelaySeconds + spawn.spawnIntervalSeconds * (spawn.count - 1))
		end
		local bossKind = spec.bossKind or if index % 10 == 0 then "Boss" else "None"
		local rewardClass = if finite and index == #specs
			then "Final"
			elseif bossKind ~= "None" then "Milestone"
			else "Standard"
		waves[index] = {
			id = `wave:{prefix}-{string.format("%02d", index)}`,
			deadlineSeconds = math.max(12, lastSpawnSeconds + 4),
			deadlinePolicy = "AllSpawnsByDeadline",
			bossKind = bossKind,
			rewardClass = rewardClass,
			groups = authoredGroups(spec.groups),
		}
	end
	return waves
end

-- Easy introduces each pressure role in isolation before mixing it. The
-- deterministic Dart + Bombardier starter loadout is sufficient for this
-- schedule under the locked Easy economy.
local EASY_SPECS: { WaveSpec } = {
	{ groups = { group("enemy:worker-ant", 6, 0, 1.35) } },
	{ groups = { group("enemy:worker-ant", 8, 0, 1.2) } },
	{ groups = { group("enemy:broodling-ant", 10, 0, 0.75) } },
	{
		groups = {
			group("enemy:scout-ant", 5, 0, 1),
			group("enemy:worker-ant", 5, 1.5, 1.2),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:worker-ant", 4, 2, 1.25),
		},
	},
	{
		groups = {
			group("enemy:scout-ant", 8, 0, 0.9),
			group("enemy:broodling-ant", 6, 2, 0.7),
		},
	},
	{
		groups = {
			group("enemy:worker-ant", 8, 0, 1),
			group("enemy:soldier-ant", 2, 3, 2.5),
		},
	},
	{
		groups = {
			group("enemy:broodling-ant", 14, 0, 0.62),
			group("enemy:scout-ant", 4, 2, 0.85),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 4, 0, 2.2),
			group("enemy:worker-ant", 6, 2, 1),
		},
	},
	{
		groups = {
			group("enemy:garden-queen", 1, 0, 0),
			group("enemy:worker-ant", 6, 2.5, 1),
			group("enemy:broodling-ant", 6, 4, 0.65),
		},
	},
	{
		groups = {
			group("enemy:scout-ant", 8, 0, 0.82),
			group("enemy:worker-ant", 7, 2, 0.95),
		},
	},
	{
		groups = {
			group("enemy:broodling-ant", 15, 0, 0.58),
			group("enemy:soldier-ant", 2, 3, 2.1),
		},
	},
	{
		groups = {
			group("enemy:worker-ant", 9, 0, 0.9),
			group("enemy:soldier-ant", 4, 2.5, 1.8),
		},
	},
	{
		groups = {
			group("enemy:scout-ant", 8, 0, 0.75),
			group("enemy:broodling-ant", 10, 2, 0.55),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:soldier-ant", 3, 3, 1.9),
			group("enemy:worker-ant", 5, 5, 0.9),
		},
	},
	{
		groups = {
			group("enemy:broodling-ant", 16, 0, 0.52),
			group("enemy:scout-ant", 4, 2.5, 0.72),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 5, 0, 1.75),
			group("enemy:scout-ant", 7, 2, 0.72),
		},
	},
	{
		groups = {
			group("enemy:worker-ant", 8, 0, 0.85),
			group("enemy:broodling-ant", 8, 2, 0.5),
			group("enemy:soldier-ant", 3, 4, 1.65),
		},
	},
	{
		groups = {
			group("enemy:scout-ant", 8, 0, 0.68),
			group("enemy:broodling-ant", 8, 2, 0.48),
			group("enemy:soldier-ant", 4, 4, 1.55),
		},
	},
	{
		groups = {
			group("enemy:garden-queen", 1, 0, 0),
			group("enemy:royal-guard-ant", 1, 3, 0),
			group("enemy:worker-ant", 6, 5, 0.8),
		},
	},
}

-- Normal overlaps roles sooner and uses denser spacing while preserving a
-- readable progression from basic pressure into durable screens.
local NORMAL_SPECS: { WaveSpec } = {
	{ groups = { group("enemy:worker-ant", 8, 0, 1.05) } },
	{ groups = { group("enemy:broodling-ant", 12, 0, 0.65) } },
	{ groups = { group("enemy:scout-ant", 6, 0, 0.82), group("enemy:worker-ant", 5, 1.5, 0.95) } },
	{ groups = { group("enemy:soldier-ant", 3, 0, 2), group("enemy:worker-ant", 7, 2, 0.9) } },
	{
		bossKind = "MiniBoss",
		groups = { group("enemy:royal-guard-ant", 1, 0, 0), group("enemy:broodling-ant", 8, 2, 0.58) },
	},
	{ groups = { group("enemy:scout-ant", 8, 0, 0.7), group("enemy:broodling-ant", 8, 1.8, 0.52) } },
	{ groups = { group("enemy:worker-ant", 9, 0, 0.82), group("enemy:soldier-ant", 4, 2, 1.65) } },
	{ groups = { group("enemy:broodling-ant", 14, 0, 0.48), group("enemy:scout-ant", 5, 1.8, 0.65) } },
	{ groups = { group("enemy:soldier-ant", 5, 0, 1.55), group("enemy:scout-ant", 6, 1.6, 0.62) } },
	{
		groups = {
			group("enemy:garden-queen", 1, 0, 0),
			group("enemy:worker-ant", 8, 2, 0.75),
			group("enemy:broodling-ant", 8, 3.5, 0.45),
		},
	},
	{ groups = { group("enemy:scout-ant", 10, 0, 0.58), group("enemy:worker-ant", 6, 1.5, 0.78) } },
	{ groups = { group("enemy:broodling-ant", 12, 0, 0.44), group("enemy:soldier-ant", 4, 2, 1.45) } },
	{
		groups = {
			group("enemy:worker-ant", 8, 0, 0.72),
			group("enemy:soldier-ant", 5, 1.8, 1.38),
			group("enemy:scout-ant", 4, 3, 0.56),
		},
	},
	{ groups = { group("enemy:broodling-ant", 12, 0, 0.42), group("enemy:scout-ant", 7, 1.5, 0.54) } },
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:soldier-ant", 4, 2.5, 1.35),
			group("enemy:worker-ant", 6, 4, 0.7),
		},
	},
	{ groups = { group("enemy:scout-ant", 9, 0, 0.52), group("enemy:broodling-ant", 10, 1.4, 0.4) } },
	{ groups = { group("enemy:soldier-ant", 6, 0, 1.25), group("enemy:worker-ant", 7, 1.8, 0.65) } },
	{
		groups = {
			group("enemy:broodling-ant", 10, 0, 0.38),
			group("enemy:scout-ant", 6, 1.2, 0.5),
			group("enemy:soldier-ant", 3, 3, 1.2),
		},
	},
	{
		groups = {
			group("enemy:worker-ant", 8, 0, 0.62),
			group("enemy:scout-ant", 7, 1.3, 0.48),
			group("enemy:soldier-ant", 4, 3, 1.15),
		},
	},
	{
		groups = {
			group("enemy:garden-queen", 1, 0, 0),
			group("enemy:royal-guard-ant", 1, 2.5, 0),
			group("enemy:broodling-ant", 10, 4, 0.36),
		},
	},
	{ groups = { group("enemy:scout-ant", 10, 0, 0.46), group("enemy:soldier-ant", 5, 1.8, 1.08) } },
	{
		groups = {
			group("enemy:broodling-ant", 12, 0, 0.34),
			group("enemy:worker-ant", 5, 1.2, 0.58),
			group("enemy:soldier-ant", 3, 3, 1.05),
		},
	},
	{ groups = { group("enemy:soldier-ant", 7, 0, 1.02), group("enemy:scout-ant", 8, 1.5, 0.44) } },
	{
		groups = {
			group("enemy:broodling-ant", 10, 0, 0.32),
			group("enemy:scout-ant", 6, 1, 0.42),
			group("enemy:worker-ant", 4, 2.5, 0.55),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 2, 0, 2.5),
			group("enemy:soldier-ant", 4, 2.5, 1),
			group("enemy:broodling-ant", 8, 4, 0.3),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 6, 0, 0.98),
			group("enemy:scout-ant", 8, 1.2, 0.4),
			group("enemy:broodling-ant", 6, 3, 0.3),
		},
	},
	{
		groups = {
			group("enemy:worker-ant", 6, 0, 0.52),
			group("enemy:soldier-ant", 7, 1.2, 0.95),
			group("enemy:scout-ant", 5, 3, 0.38),
		},
	},
	{
		groups = {
			group("enemy:broodling-ant", 9, 0, 0.28),
			group("enemy:scout-ant", 7, 1, 0.36),
			group("enemy:soldier-ant", 4, 2.5, 0.92),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:soldier-ant", 6, 2, 0.9),
			group("enemy:scout-ant", 8, 3.5, 0.34),
		},
	},
	{
		groups = {
			group("enemy:garden-queen", 2, 0, 3),
			group("enemy:royal-guard-ant", 1, 3, 0),
			group("enemy:broodling-ant", 8, 4.5, 0.28),
		},
	},
}

-- Hard begins with mixed waves, compresses spacing, and layers fast/swarm
-- pressure behind durable enemies. Counts stay within the 20-enemy active
-- projection bound so authored pressure never relies on hidden queue backlog.
local HARD_SPECS: { WaveSpec } = {
	{ groups = { group("enemy:worker-ant", 8, 0, 0.78), group("enemy:broodling-ant", 5, 1.5, 0.45) } },
	{ groups = { group("enemy:scout-ant", 7, 0, 0.6), group("enemy:broodling-ant", 7, 1.2, 0.4) } },
	{ groups = { group("enemy:soldier-ant", 3, 0, 1.5), group("enemy:worker-ant", 8, 1.5, 0.7) } },
	{ groups = { group("enemy:broodling-ant", 10, 0, 0.36), group("enemy:scout-ant", 6, 1, 0.52) } },
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:soldier-ant", 3, 2, 1.3),
			group("enemy:broodling-ant", 8, 3.5, 0.34),
		},
	},
	{
		groups = {
			group("enemy:scout-ant", 9, 0, 0.48),
			group("enemy:worker-ant", 6, 1, 0.65),
			group("enemy:broodling-ant", 5, 2.5, 0.32),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 5, 0, 1.18),
			group("enemy:scout-ant", 6, 1.2, 0.46),
			group("enemy:broodling-ant", 6, 2.5, 0.3),
		},
	},
	{
		groups = {
			group("enemy:broodling-ant", 10, 0, 0.3),
			group("enemy:worker-ant", 5, 1, 0.6),
			group("enemy:soldier-ant", 4, 2.5, 1.12),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:scout-ant", 7, 1.5, 0.44),
			group("enemy:soldier-ant", 4, 3, 1.08),
		},
	},
	{
		groups = {
			group("enemy:garden-queen", 1, 0, 0),
			group("enemy:royal-guard-ant", 1, 2, 0),
			group("enemy:broodling-ant", 10, 3.5, 0.28),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 6, 0, 1.02),
			group("enemy:scout-ant", 8, 1.2, 0.4),
			group("enemy:broodling-ant", 6, 2.8, 0.28),
		},
	},
	{
		groups = {
			group("enemy:broodling-ant", 9, 0, 0.26),
			group("enemy:scout-ant", 7, 0.9, 0.38),
			group("enemy:worker-ant", 4, 2.2, 0.55),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 7, 0, 0.98),
			group("enemy:worker-ant", 6, 1.2, 0.52),
			group("enemy:scout-ant", 5, 2.5, 0.36),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:broodling-ant", 10, 1.5, 0.25),
			group("enemy:scout-ant", 6, 2.8, 0.35),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 2, 0, 2.2),
			group("enemy:soldier-ant", 4, 2.5, 0.92),
			group("enemy:worker-ant", 6, 4, 0.5),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 6, 0, 0.9),
			group("enemy:scout-ant", 8, 1, 0.34),
			group("enemy:broodling-ant", 6, 2.4, 0.24),
		},
	},
	{
		groups = {
			group("enemy:broodling-ant", 8, 0, 0.23),
			group("enemy:scout-ant", 7, 0.8, 0.33),
			group("enemy:soldier-ant", 5, 2.2, 0.88),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:soldier-ant", 6, 1.7, 0.85),
			group("enemy:scout-ant", 6, 3, 0.32),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 7, 0, 0.82),
			group("enemy:scout-ant", 7, 1, 0.31),
			group("enemy:broodling-ant", 6, 2.3, 0.22),
		},
	},
	{
		groups = {
			group("enemy:garden-queen", 2, 0, 2.5),
			group("enemy:royal-guard-ant", 1, 2.5, 0),
			group("enemy:broodling-ant", 8, 4, 0.22),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 7, 0, 0.8),
			group("enemy:scout-ant", 7, 0.9, 0.3),
			group("enemy:broodling-ant", 6, 2.2, 0.21),
		},
	},
	{
		groups = {
			group("enemy:broodling-ant", 9, 0, 0.2),
			group("enemy:scout-ant", 7, 0.8, 0.29),
			group("enemy:soldier-ant", 4, 2.1, 0.78),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:soldier-ant", 6, 1.5, 0.76),
			group("enemy:worker-ant", 6, 3, 0.46),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 7, 0, 0.74),
			group("enemy:scout-ant", 7, 0.8, 0.28),
			group("enemy:broodling-ant", 6, 2, 0.2),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 2, 0, 2),
			group("enemy:soldier-ant", 5, 2.2, 0.72),
			group("enemy:broodling-ant", 8, 3.5, 0.19),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 8, 0, 0.7),
			group("enemy:scout-ant", 7, 0.8, 0.27),
			group("enemy:broodling-ant", 5, 1.9, 0.19),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:soldier-ant", 7, 1.4, 0.68),
			group("enemy:scout-ant", 6, 2.8, 0.26),
		},
	},
	{
		groups = {
			group("enemy:broodling-ant", 8, 0, 0.18),
			group("enemy:scout-ant", 7, 0.7, 0.25),
			group("enemy:soldier-ant", 5, 1.8, 0.66),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:soldier-ant", 7, 1.3, 0.64),
			group("enemy:broodling-ant", 8, 2.6, 0.18),
		},
	},
	{
		groups = {
			group("enemy:garden-queen", 2, 0, 2.2),
			group("enemy:royal-guard-ant", 2, 2.2, 1.8),
			group("enemy:scout-ant", 8, 3.8, 0.24),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 8, 0, 0.62),
			group("enemy:scout-ant", 7, 0.7, 0.23),
			group("enemy:broodling-ant", 5, 1.7, 0.17),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:soldier-ant", 7, 1.2, 0.6),
			group("enemy:scout-ant", 6, 2.5, 0.22),
		},
	},
	{
		groups = {
			group("enemy:broodling-ant", 8, 0, 0.16),
			group("enemy:soldier-ant", 7, 0.8, 0.58),
			group("enemy:scout-ant", 5, 2.2, 0.21),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:soldier-ant", 8, 1.1, 0.56),
			group("enemy:broodling-ant", 7, 2.4, 0.16),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 2, 0, 1.7),
			group("enemy:soldier-ant", 7, 1.8, 0.54),
			group("enemy:scout-ant", 6, 3.2, 0.2),
		},
	},
	{
		groups = {
			group("enemy:soldier-ant", 9, 0, 0.52),
			group("enemy:broodling-ant", 6, 0.8, 0.15),
			group("enemy:scout-ant", 5, 2, 0.19),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 1, 0, 0),
			group("enemy:soldier-ant", 8, 1, 0.5),
			group("enemy:scout-ant", 7, 2.3, 0.18),
		},
	},
	{
		groups = {
			group("enemy:broodling-ant", 7, 0, 0.14),
			group("enemy:soldier-ant", 8, 0.7, 0.48),
			group("enemy:scout-ant", 5, 2, 0.17),
		},
	},
	{
		bossKind = "MiniBoss",
		groups = {
			group("enemy:royal-guard-ant", 2, 0, 1.5),
			group("enemy:soldier-ant", 8, 1.6, 0.46),
			group("enemy:broodling-ant", 7, 3, 0.14),
		},
	},
	{
		groups = {
			group("enemy:garden-queen", 3, 0, 2),
			group("enemy:royal-guard-ant", 2, 2, 1.4),
			group("enemy:soldier-ant", 8, 3.5, 0.44),
		},
	},
}

local Waves: { ConfigTypes.WaveScheduleDefinition } = {
	{
		kind = "AuthoredFinite",
		mapId = ContentSelection.DEVELOPMENT_MAP_ID,
		difficultyId = ContentSelection.DEVELOPMENT_DIFFICULTY_ID,
		waves = {
			{
				id = "wave:local-1",
				deadlineSeconds = 28,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "None",
				rewardClass = "Standard",
				groups = authoredGroups({ group("enemy:worker-ant", 6, 0, 1.4) }),
			},
			{
				id = "wave:local-2",
				deadlineSeconds = 30,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "None",
				rewardClass = "Standard",
				groups = authoredGroups({ group("enemy:scout-ant", 9, 0, 0.85) }),
			},
			{
				id = "wave:local-3",
				deadlineSeconds = 34,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "None",
				rewardClass = "Standard",
				groups = authoredGroups({
					group("enemy:worker-ant", 7, 0, 1.1),
					group("enemy:soldier-ant", 2, 3, 3.5),
				}),
			},
			{
				id = "wave:local-4",
				deadlineSeconds = 38,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "None",
				rewardClass = "Standard",
				groups = authoredGroups({
					group("enemy:scout-ant", 12, 0, 0.7),
					group("enemy:soldier-ant", 3, 2, 2.8),
				}),
			},
			{
				id = "wave:local-5",
				deadlineSeconds = 46,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "Boss",
				rewardClass = "Final",
				groups = authoredGroups({
					group("enemy:soldier-ant", 4, 0, 3),
					group("enemy:garden-queen", 1, 7, 0),
				}),
			},
		},
	},
	{
		kind = "AuthoredFinite",
		mapId = ContentSelection.RELEASE_MAP_ID,
		difficultyId = ContentSelection.EASY_DIFFICULTY_ID,
		waves = authoredWaves("garden-easy", EASY_SPECS, true),
	},
	{
		kind = "AuthoredFinite",
		mapId = ContentSelection.RELEASE_MAP_ID,
		difficultyId = ContentSelection.NORMAL_DIFFICULTY_ID,
		waves = authoredWaves("garden-normal", NORMAL_SPECS, true),
	},
	{
		kind = "AuthoredFinite",
		mapId = ContentSelection.RELEASE_MAP_ID,
		difficultyId = ContentSelection.HARD_DIFFICULTY_ID,
		waves = authoredWaves("garden-hard", HARD_SPECS, true),
	},
	{
		kind = "GeneratedEndless",
		mapId = ContentSelection.RELEASE_MAP_ID,
		difficultyId = ContentSelection.ENDLESS_DIFFICULTY_ID,
		authoredOpeningWaves = authoredWaves("garden-endless-opening", {
			NORMAL_SPECS[1],
			NORMAL_SPECS[2],
			NORMAL_SPECS[3],
			NORMAL_SPECS[4],
			NORMAL_SPECS[5],
			NORMAL_SPECS[6],
			NORMAL_SPECS[7],
			NORMAL_SPECS[8],
			NORMAL_SPECS[9],
			NORMAL_SPECS[10],
		}, false),
		generator = {
			kind = "EndlessWaveGenerator",
			key = ContentSelection.ENDLESS_GENERATOR_KEY,
		},
	},
}

return table.freeze(Waves)
