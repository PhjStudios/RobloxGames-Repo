--!strict

local ServerRateLimiter = require(script.Parent.ServerRateLimiter)

local function requirePolicy(capacity: number, refillPerSecond: number): ServerRateLimiter.Policy
	local result = ServerRateLimiter.createPolicy(capacity, refillPerSecond)
	if not result.ok then
		error("Production rate-limit policy construction failed closed", 0)
	end
	return result.value
end

local bindings: { ServerRateLimiter.PolicyBinding } = {
	table.freeze({
		endpoint = "GetBaseSnapshot",
		policy = requirePolicy(2, 0.25),
	}),
	table.freeze({
		endpoint = "GetEnemySnapshot",
		policy = requirePolicy(2, 0.25),
	}),
	table.freeze({
		endpoint = "GetMatchSnapshot",
		policy = requirePolicy(2, 1),
	}),
	table.freeze({
		endpoint = "GetTowerPlacementQuery",
		policy = requirePolicy(4, 1),
	}),
	table.freeze({
		endpoint = "GetWaveSnapshot",
		policy = requirePolicy(2, 0.25),
	}),
	table.freeze({
		endpoint = "SubmitReady",
		policy = requirePolicy(2, 0.5),
	}),
	table.freeze({
		endpoint = "SubmitSkipVote",
		policy = requirePolicy(2, 0.5),
	}),
	table.freeze({
		endpoint = "SubmitTowerPlacement",
		policy = requirePolicy(3, 0.5),
	}),
}

return table.freeze(bindings)
