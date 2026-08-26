--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

-- Only approved structural policy is authored here. Difficulty-specific values
-- remain empty until a later content and balance packet defines real content.
local difficultyRules: { ConfigTypes.DifficultyEconomyDefinition } = {}
local sellRefund: ConfigTypes.SellRefundConfiguration = {
	basisPoints = 7_000,
	rounding = "Floor",
}

local Economy: ConfigTypes.AuthoredEconomyConfiguration = {
	version = 1,
	sellRefund = table.freeze(sellRefund),
	difficultyRules = table.freeze(difficultyRules),
}

return table.freeze(Economy)
