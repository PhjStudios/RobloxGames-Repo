--!strict

-- These are queue identities and defaults, not roster state. Membership,
-- captaincy, configuration revisions, locks, and travel status remain owned by
-- the Lobby server.
local LobbyQueues = table.freeze({
	version = 1,
	ordered = table.freeze({
		table.freeze({
			queueId = "queue:backyard-squad",
			worldPartName = "ATDSquadQueueZone",
			worldDisplayName = "ATDSquadQueueDisplay",
			configuration = table.freeze({
				mapId = "map:phase07-graybox",
				difficultyId = "difficulty:local",
				privacy = "Public",
				maxPlayers = 4,
			}),
		}),
	}),
})

return LobbyQueues
