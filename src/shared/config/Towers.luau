--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

local Towers: { ConfigTypes.TowerDefinition } = {}

return table.freeze(Towers)
