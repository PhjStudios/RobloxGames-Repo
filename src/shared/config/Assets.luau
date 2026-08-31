--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

-- Symbolic production assets. The corresponding map and lightweight model
-- templates are Studio-owned under the Match place; gameplay code only relies
-- on these authenticated identities.
local Assets: { ConfigTypes.AssetDefinition } = {
	{ key = "tower.dart-ant-model", kind = "TowerModel" },
	{ key = "tower.rapid-ant-model", kind = "TowerModel" },
	{ key = "tower.guard-ant-model", kind = "TowerModel" },
	{ key = "enemy.worker-ant-model", kind = "EnemyModel" },
	{ key = "enemy.scout-ant-model", kind = "EnemyModel" },
	{ key = "enemy.soldier-ant-model", kind = "EnemyModel" },
	{ key = "enemy.queen-ant-model", kind = "EnemyModel" },
	{ key = "map.phase07-graybox-model", kind = "MapModel" },
	{ key = "icon.dart-ant", kind = "Icon" },
	{ key = "icon.rapid-ant", kind = "Icon" },
	{ key = "icon.guard-ant", kind = "Icon" },
	{ key = "icon.worker-ant", kind = "Icon" },
	{ key = "icon.scout-ant", kind = "Icon" },
	{ key = "icon.soldier-ant", kind = "Icon" },
	{ key = "icon.queen-ant", kind = "Icon" },
	{ key = "icon.phase07-graybox", kind = "Icon" },
}

return table.freeze(Assets)
