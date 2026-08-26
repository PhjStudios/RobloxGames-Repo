--!strict

local RemoteRegistry = require(script.Parent.RemoteRegistry)

-- Phase 06 establishes the boundary without inventing production features.
-- Construction failure is a static boot-time fault; returning a counterfeit or
-- partially valid registry would weaken the server-owned endpoint allowlist.
local result = RemoteRegistry.create({})
if not result.ok then
	error("Production remote registry construction failed closed", 0)
end

return result.value
