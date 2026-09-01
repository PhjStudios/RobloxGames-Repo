--!strict

-- Persistent Gold is awarded only by the authoritative ticketed-Match result
-- pipeline. Battle Cash remains match-local and is intentionally absent here.
local MatchRewards = table.freeze({
	version = 1,
	participationGold = 50,
	victoryBonusGold = 200,
	firstClearGold = 250,
	minimumCompletedWaves = 2,
	requireReady = true,
	requireTowerPlacement = true,
})

return MatchRewards
