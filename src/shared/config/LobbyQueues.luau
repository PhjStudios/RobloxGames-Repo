--!strict

-- These are queue identities and defaults, not roster state. Membership,
-- captaincy, configuration revisions, locks, and travel status remain owned by
-- the Lobby server.
local ContentSelection = require(script.Parent.ContentSelection)

local LobbyQueues = table.freeze({
	version = 1,
	ordered = table.freeze({
		table.freeze({
			queueId = "queue:backyard-squad",
			worldPartName = "ATDSquadQueueZone",
			worldDisplayName = "ATDSquadQueueDisplay",
			configuration = table.freeze({
				mapId = ContentSelection.RELEASE_MAP_ID,
				difficultyId = ContentSelection.EASY_DIFFICULTY_ID,
				privacy = "Public",
				maxPlayers = 4,
			}),
		}),
	}),
})

return LobbyQueues
