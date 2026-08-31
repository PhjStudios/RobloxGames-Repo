--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

local Enemies: { ConfigTypes.EnemyDefinition } = {
	{
		id = "enemy:worker-ant",
		displayName = "Worker Ant",
		description = "A steady garden worker.",
		modelAssetKey = "enemy.worker-ant-model",
		iconAssetKey = "icon.worker-ant",
		maxHealth = 45,
		moveSpeedStudsPerSecond = 5.5,
		leakDamage = 1,
		damageIncomeClass = "EligibleHealthRemoved",
		tags = { "production", "role.basic" },
	},
	{
		id = "enemy:scout-ant",
		displayName = "Scout Ant",
		description = "Fragile, but quick enough to exploit poor coverage.",
		modelAssetKey = "enemy.scout-ant-model",
		iconAssetKey = "icon.scout-ant",
		maxHealth = 28,
		moveSpeedStudsPerSecond = 9,
		leakDamage = 1,
		damageIncomeClass = "EligibleHealthRemoved",
		tags = { "production", "role.fast" },
	},
	{
		id = "enemy:soldier-ant",
		displayName = "Soldier Ant",
		description = "A durable ant that demands concentrated fire.",
		modelAssetKey = "enemy.soldier-ant-model",
		iconAssetKey = "icon.soldier-ant",
		maxHealth = 145,
		moveSpeedStudsPerSecond = 3.8,
		leakDamage = 4,
		damageIncomeClass = "EligibleHealthRemoved",
		tags = { "production", "role.tank" },
	},
	{
		id = "enemy:garden-queen",
		displayName = "Garden Queen",
		description = "The final local-match boss.",
		modelAssetKey = "enemy.queen-ant-model",
		iconAssetKey = "icon.queen-ant",
		maxHealth = 650,
		moveSpeedStudsPerSecond = 2.7,
		leakDamage = 30,
		damageIncomeClass = "EligibleHealthRemoved",
		tags = { "production", "role.boss" },
	},
}

return table.freeze(Enemies)
