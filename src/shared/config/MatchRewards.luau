--!strict

local ContentSelection = require(script.Parent.ContentSelection)

-- Persistent Gold is awarded only by the authoritative ticketed-Match result
-- pipeline. Battle Cash remains match-local and is intentionally absent here.
local MatchRewards = table.freeze({
	version = 2,
	-- Version-1 result records retain the historical policy below.
	participationGold = 50,
	victoryBonusGold = 200,
	firstClearGold = 250,
	finiteByDifficultyId = table.freeze({
		[ContentSelection.DEVELOPMENT_DIFFICULTY_ID] = table.freeze({
			participationGold = 0,
			victoryBonusGold = 0,
			firstClearGold = 0,
		}),
		[ContentSelection.EASY_DIFFICULTY_ID] = table.freeze({
			participationGold = 50,
			victoryBonusGold = 150,
			firstClearGold = 150,
		}),
		[ContentSelection.NORMAL_DIFFICULTY_ID] = table.freeze({
			participationGold = 65,
			victoryBonusGold = 235,
			firstClearGold = 225,
		}),
		[ContentSelection.HARD_DIFFICULTY_ID] = table.freeze({
			participationGold = 85,
			victoryBonusGold = 365,
			firstClearGold = 325,
		}),
	}),
	endless = table.freeze({
		minimumCompletedWaves = 5,
		baseGold = 25,
		milestoneEveryWaves = 10,
		milestoneGold = 25,
		maximumGold = 300,
	}),
	minimumCompletedWaves = 2,
	requireReady = true,
	requireTowerPlacement = true,
})

return MatchRewards
