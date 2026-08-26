--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

-- Authored difficulty content is intentionally empty until a content packet.
local Difficulties: { ConfigTypes.DifficultyDefinition } = {}

return table.freeze(Difficulties)
