--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

local function group(enemyId: string, count: number, startDelay: number, interval: number)
	return {
		enemyId = enemyId,
		laneId = "main",
		count = count,
		startDelaySeconds = startDelay,
		spawnIntervalSeconds = interval,
	}
end

local Waves: { ConfigTypes.WaveScheduleDefinition } = {
	{
		kind = "AuthoredFinite",
		mapId = "map:phase07-graybox",
		difficultyId = "difficulty:local",
		waves = {
			{
				id = "wave:local-1",
				deadlineSeconds = 28,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "None",
				rewardClass = "Standard",
				groups = { group("enemy:worker-ant", 6, 0, 1.4) },
			},
			{
				id = "wave:local-2",
				deadlineSeconds = 30,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "None",
				rewardClass = "Standard",
				groups = { group("enemy:scout-ant", 9, 0, 0.85) },
			},
			{
				id = "wave:local-3",
				deadlineSeconds = 34,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "None",
				rewardClass = "Standard",
				groups = {
					group("enemy:worker-ant", 7, 0, 1.1),
					group("enemy:soldier-ant", 2, 3, 3.5),
				},
			},
			{
				id = "wave:local-4",
				deadlineSeconds = 38,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "None",
				rewardClass = "Standard",
				groups = {
					group("enemy:scout-ant", 12, 0, 0.7),
					group("enemy:soldier-ant", 3, 2, 2.8),
				},
			},
			{
				id = "wave:local-5",
				deadlineSeconds = 46,
				deadlinePolicy = "AllSpawnsByDeadline",
				bossKind = "Boss",
				rewardClass = "Final",
				groups = {
					group("enemy:soldier-ant", 4, 0, 3),
					group("enemy:garden-queen", 1, 7, 0),
				},
			},
		},
	},
}

return table.freeze(Waves)
