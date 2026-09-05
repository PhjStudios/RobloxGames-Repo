--!strict

-- No audio has been supplied with verified ownership, license and experience
-- permissions. Empty identifiers are intentional silent fallbacks; never replace
-- them with arbitrary catalog IDs. All additions require provenance review.
local entries = {}
for _, scene in { "Lobby", "Match", "Boss", "Victory", "Defeat" } do
	entries[`Music.{scene}`] = table.freeze({
		key = `Music.{scene}`,
		group = "Music",
		approved = false,
		assetId = "",
		owner = "",
		license = "",
		source = "",
		permissionVerified = false,
	})
end
for _, cue in
	{
		"Placement",
		"Attack",
		"Impact",
		"Kill",
		"Upgrade",
		"Sell",
		"Leak",
		"BaseDamage",
		"Boss",
		"Victory",
		"Defeat",
		"Reward",
		"Selection",
	}
do
	entries[cue] = table.freeze({
		key = cue,
		group = if cue == "Reward" or cue == "Selection" then "UI" else "SFX",
		approved = false,
		assetId = "",
		owner = "",
		license = "",
		source = "",
		permissionVerified = false,
	})
end

return table.freeze({ version = 1, entries = table.freeze(entries) })
