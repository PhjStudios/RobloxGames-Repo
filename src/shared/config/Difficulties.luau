--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local ContentSelection = require(script.Parent.ContentSelection)

local Difficulties: { ConfigTypes.DifficultyDefinition } = {
	{
		id = ContentSelection.DEVELOPMENT_DIFFICULTY_ID,
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
		tags = { "development", "hidden", "local-match", "non-rewarding" },
	},
	{
		id = ContentSelection.EASY_DIFFICULTY_ID,
		displayName = "Easy",
		description = "A welcoming twenty-wave campaign with room to learn each role.",
		iconAssetKey = "icon.difficulty-easy-v1",
		kind = "Finite",
		waveCount = 20,
		base = { maxHealth = 100 },
		modifiers = {
			enemyHealthMultiplier = 0.9,
			enemyMoveSpeedMultiplier = 0.95,
		},
		timing = {
			earlyClearIntermissionSeconds = 6,
			bossCadenceWaves = 10,
			skipVoteMinimumDelaySeconds = 2,
		},
		tags = { "production", "campaign", "difficulty.easy" },
	},
	{
		id = ContentSelection.NORMAL_DIFFICULTY_ID,
		displayName = "Normal",
		description = "A thirty-wave campaign with earlier role combinations and tighter recovery.",
		iconAssetKey = "icon.difficulty-normal-v1",
		kind = "Finite",
		waveCount = 30,
		base = { maxHealth = 75 },
		modifiers = {
			enemyHealthMultiplier = 1,
			enemyMoveSpeedMultiplier = 1,
		},
		timing = {
			earlyClearIntermissionSeconds = 5,
			bossCadenceWaves = 10,
			skipVoteMinimumDelaySeconds = 2,
		},
		tags = { "production", "campaign", "difficulty.normal" },
	},
	{
		id = ContentSelection.HARD_DIFFICULTY_ID,
		displayName = "Hard",
		description = "A forty-wave campaign with lean resources and layered pressure.",
		iconAssetKey = "icon.difficulty-hard-v1",
		kind = "Finite",
		waveCount = 40,
		base = { maxHealth = 60 },
		modifiers = {
			enemyHealthMultiplier = 1.12,
			enemyMoveSpeedMultiplier = 1.05,
		},
		timing = {
			earlyClearIntermissionSeconds = 4,
			bossCadenceWaves = 10,
			skipVoteMinimumDelaySeconds = 2,
		},
		tags = { "production", "campaign", "difficulty.hard" },
	},
	{
		id = ContentSelection.ENDLESS_DIFFICULTY_ID,
		displayName = "Endless",
		description = "An unbounded seeded defense that grows within stable gameplay limits.",
		iconAssetKey = "icon.difficulty-endless-v1",
		kind = "Endless",
		base = { maxHealth = 75 },
		modifiers = {
			enemyHealthMultiplier = 1.04,
			enemyMoveSpeedMultiplier = 1.02,
		},
		timing = {
			earlyClearIntermissionSeconds = 5,
			bossCadenceWaves = 10,
			skipVoteMinimumDelaySeconds = 2,
		},
		tags = { "production", "endless", "difficulty.endless" },
	},
}

return table.freeze(Difficulties)
