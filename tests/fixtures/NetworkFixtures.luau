--!strict

-- Every function returns fresh, mutable test-only definitions. None of these
-- foundation probes are mapped into a production registry.
local NetworkFixtures = {}

export type RawDefinition = { [string]: any }

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in next, value do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy
end

function NetworkFixtures.clientEventDefinition(): RawDefinition
	return {
		name = "TestClientEvent",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Event",
		response = "None",
		placeRoles = { "Match" },
	}
end

function NetworkFixtures.noResponseRequestDefinition(): RawDefinition
	return {
		name = "TestNoResponseRequest",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "None",
		placeRoles = { "Match" },
	}
end

function NetworkFixtures.responseRequestDefinition(): RawDefinition
	return {
		name = "TestResponseRequest",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match", "Lobby" },
	}
end

function NetworkFixtures.serverEventDefinition(): RawDefinition
	return {
		name = "TestServerEvent",
		transport = "ReliableRemoteEvent",
		direction = "ServerToClient",
		kind = "Event",
		response = "None",
		placeRoles = { "Lobby" },
	}
end

function NetworkFixtures.validDefinitions(): { RawDefinition }
	-- Deliberately non-canonical input order exercises registry sorting.
	return {
		NetworkFixtures.serverEventDefinition(),
		NetworkFixtures.responseRequestDefinition(),
		NetworkFixtures.clientEventDefinition(),
		NetworkFixtures.noResponseRequestDefinition(),
	}
end

function NetworkFixtures.clone<T>(value: T): T
	return deepCopy(value)
end

return table.freeze(NetworkFixtures)
