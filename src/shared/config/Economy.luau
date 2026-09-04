--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local ContentSelection = require(script.Parent.ContentSelection)

local function reward(stipend: number): ConfigTypes.WaveRewardEconomyDefinition
	return {
		battleCashStipendPerActivePlayer = stipend,
		persistentGold = { baseAmountPerEligiblePlayer = 0 },
	}
end

local difficultyRules: { ConfigTypes.DifficultyEconomyDefinition } = {
	{
		difficultyId = ContentSelection.DEVELOPMENT_DIFFICULTY_ID,
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
	{
		difficultyId = ContentSelection.EASY_DIFFICULTY_ID,
		startingBattleCash = 650,
		damageIncome = {
			battleCashNumerator = 1,
			healthRemovedDenominator = 4,
			rounding = "Floor",
			accrualScope = "PerPlayerMatch",
		},
		waveRewards = {
			standard = reward(90),
			milestone = reward(140),
			final = reward(220),
		},
	},
	{
		difficultyId = ContentSelection.NORMAL_DIFFICULTY_ID,
		startingBattleCash = 575,
		damageIncome = {
			battleCashNumerator = 1,
			healthRemovedDenominator = 5,
			rounding = "Floor",
			accrualScope = "PerPlayerMatch",
		},
		waveRewards = {
			standard = reward(75),
			milestone = reward(125),
			final = reward(200),
		},
	},
	{
		difficultyId = ContentSelection.HARD_DIFFICULTY_ID,
		startingBattleCash = 500,
		damageIncome = {
			battleCashNumerator = 1,
			healthRemovedDenominator = 6,
			rounding = "Floor",
			accrualScope = "PerPlayerMatch",
		},
		waveRewards = {
			standard = reward(60),
			milestone = reward(105),
			final = reward(175),
		},
	},
	{
		difficultyId = ContentSelection.ENDLESS_DIFFICULTY_ID,
		startingBattleCash = 550,
		damageIncome = {
			battleCashNumerator = 1,
			healthRemovedDenominator = 6,
			rounding = "Floor",
			accrualScope = "PerPlayerMatch",
		},
		waveRewards = {
			standard = reward(65),
			milestone = reward(110),
			final = reward(0),
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
