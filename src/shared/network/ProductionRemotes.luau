--!strict

local RemoteRegistry = require(script.Parent.RemoteRegistry)

local result = RemoteRegistry.create({
	{
		name = "GetMatchSnapshot",
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
		name = "MatchSnapshot",
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
