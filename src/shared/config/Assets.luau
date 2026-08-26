--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

local Assets: { ConfigTypes.AssetDefinition } = {}

return table.freeze(Assets)
