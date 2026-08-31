--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

local Difficulties: { ConfigTypes.DifficultyDefinition } = {
	{
		id = "difficulty:local",
		displayName = "Local",
		description = "A five-wave playable development match.",
		kind = "Finite",
		waveCount = 5,
		base = { maxHealth = 30 },
		modifiers = {
			enemyHealthMultiplier = 1,
			enemyMoveSpeedMultiplier = 1,
		},
		timing = {
			earlyClearIntermissionSeconds = 4,
			bossCadenceWaves = 5,
			skipVoteMinimumDelaySeconds = 2,
		},
		tags = { "production", "local-match" },
	},
}

return table.freeze(Difficulties)
