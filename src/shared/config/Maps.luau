--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local ContentSelection = require(script.Parent.ContentSelection)

local Maps: { ConfigTypes.MapDefinition } = {
	{
		id = ContentSelection.DEVELOPMENT_MAP_ID,
		displayName = "Backyard Graybox",
		description = "A compact garden lane built for a short local defense.",
		modelAssetKey = "map.phase07-graybox-model",
		iconAssetKey = "icon.phase07-graybox",
		lanes = {
			{ id = "main" },
		},
		supportedDifficultyIds = { ContentSelection.DEVELOPMENT_DIFFICULTY_ID },
		tags = { "development", "hidden", "local-match", "non-rewarding", "single-lane" },
	},
	{
		id = ContentSelection.RELEASE_MAP_ID,
		displayName = "Backyard Garden",
		description = "A bright ant-scale garden with two readable bends and broad placement pockets.",
		modelAssetKey = "map.backyard-garden-v1-model",
		iconAssetKey = "icon.backyard-garden-v1",
		lanes = {
			{ id = "main" },
		},
		supportedDifficultyIds = {
			ContentSelection.EASY_DIFFICULTY_ID,
			ContentSelection.NORMAL_DIFFICULTY_ID,
			ContentSelection.HARD_DIFFICULTY_ID,
			ContentSelection.ENDLESS_DIFFICULTY_ID,
		},
		tags = { "production", "release", "single-lane", "theme.backyard-garden" },
	},
}

return table.freeze(Maps)
