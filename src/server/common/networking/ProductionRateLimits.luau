--!strict

local ServerRateLimiter = require(script.Parent.ServerRateLimiter)

local bindings: { ServerRateLimiter.PolicyBinding } = {}

return table.freeze(bindings)
