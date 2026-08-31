--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

local Maps: { ConfigTypes.MapDefinition } = {
	{
		id = "map:phase07-graybox",
		displayName = "Backyard Graybox",
		description = "A compact garden lane built for a short local defense.",
		modelAssetKey = "map.phase07-graybox-model",
		iconAssetKey = "icon.phase07-graybox",
		lanes = {
			{ id = "main" },
		},
		supportedDifficultyIds = { "difficulty:local" },
		tags = { "production", "local-match", "single-lane" },
	},
}

return table.freeze(Maps)
