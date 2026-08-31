--!strict

local RemoteRegistry = require(script.Parent.RemoteRegistry)

local result = RemoteRegistry.create({
	{
		name = "GetBaseSnapshot",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	},
	{
		name = "GetEnemySnapshot",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	},
	{
		name = "GetMatchSnapshot",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	},
	{
		name = "GetTowerPlacementQuery",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	},
	{
		name = "GetWaveSnapshot",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	},
	{
		name = "SubmitReady",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	},
	{
		name = "SubmitTowerPlacement",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	},
	{
		name = "SubmitSkipVote",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	},
	{
		name = "BaseReplication",
		transport = "ReliableRemoteEvent",
		direction = "ServerToClient",
		kind = "Event",
		response = "None",
		placeRoles = { "Match" },
	},
	{
		name = "MatchSnapshot",
		transport = "ReliableRemoteEvent",
		direction = "ServerToClient",
		kind = "Event",
		response = "None",
		placeRoles = { "Match" },
	},
	{
		name = "EnemyReplication",
		transport = "ReliableRemoteEvent",
		direction = "ServerToClient",
		kind = "Event",
		response = "None",
		placeRoles = { "Match" },
	},
	{
		name = "WaveReplication",
		transport = "ReliableRemoteEvent",
		direction = "ServerToClient",
		kind = "Event",
		response = "None",
		placeRoles = { "Match" },
	},
	{
		name = "TowerPlacementRevision",
		transport = "ReliableRemoteEvent",
		direction = "ServerToClient",
		kind = "Event",
		response = "None",
		placeRoles = { "Match" },
	},
})
if not result.ok then
	error("Production remote registry construction failed closed", 0)
end

return result.value
