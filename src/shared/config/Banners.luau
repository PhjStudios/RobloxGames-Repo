--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

-- The starter chest is intentionally earn-only. Runtime availability and the
-- policy disclosure live in acquisition configuration, while this authored
-- definition contains only the immutable costs, exact odds, and pity rule.
local Banners: { ConfigTypes.BannerDefinition } = {
	{
		id = "banner:starter",
		version = 1,
		displayName = "Starter Tower Chest",
		pullOptions = {
			onePull = { goldCost = 250 },
			tenPull = { goldCost = 2_250 },
		},
		outcomes = {
			{ towerId = "tower:dart-ant", probabilityPercent = 60 },
			{ towerId = "tower:rapid-ant", probabilityPercent = 30 },
			{ towerId = "tower:guard-ant", probabilityPercent = 10 },
		},
		pityRule = {
			kind = "GuaranteedTower",
			hardPityPullCount = 10,
			guaranteedTowerId = "tower:guard-ant",
		},
	},
}

return table.freeze(Banners)
