--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

-- Authored banners are intentionally empty until a content and balance packet.
local Banners: { ConfigTypes.BannerDefinition } = {}

return table.freeze(Banners)
