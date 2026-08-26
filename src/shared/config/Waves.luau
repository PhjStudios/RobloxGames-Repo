--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

-- Authored wave schedules are intentionally empty until a content packet.
local Waves: { ConfigTypes.WaveScheduleDefinition } = {}

return table.freeze(Waves)
