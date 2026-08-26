--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

local Enemies: { ConfigTypes.EnemyDefinition } = {}

return table.freeze(Enemies)
