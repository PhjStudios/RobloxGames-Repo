--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

-- Authored map content is intentionally empty until a content packet.
local Maps: { ConfigTypes.MapDefinition } = {}

return table.freeze(Maps)
