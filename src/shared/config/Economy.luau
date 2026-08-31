--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

local function reward(stipend: number): ConfigTypes.WaveRewardEconomyDefinition
	return {
		battleCashStipendPerActivePlayer = stipend,
		persistentGold = { baseAmountPerEligiblePlayer = 0 },
	}
end

local difficultyRules: { ConfigTypes.DifficultyEconomyDefinition } = {
	{
		difficultyId = "difficulty:local",
		startingBattleCash = 500,
		damageIncome = {
			battleCashNumerator = 1,
			healthRemovedDenominator = 4,
			rounding = "Floor",
			accrualScope = "PerPlayerMatch",
		},
		waveRewards = {
			standard = reward(70),
			milestone = reward(110),
			final = reward(150),
		},
	},
}
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
