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
	{ key = "tower.bombardier-ant-model", kind = "TowerModel" },
	{ key = "enemy.broodling-ant-model", kind = "EnemyModel" },
	{ key = "enemy.royal-guard-ant-model", kind = "EnemyModel" },
	{ key = "map.backyard-garden-v1-model", kind = "MapModel" },
	{ key = "icon.bombardier-ant", kind = "Icon" },
	{ key = "icon.broodling-ant", kind = "Icon" },
	{ key = "icon.royal-guard-ant", kind = "Icon" },
	{ key = "icon.backyard-garden-v1", kind = "Icon" },
	{ key = "icon.difficulty-easy-v1", kind = "Icon" },
	{ key = "icon.difficulty-normal-v1", kind = "Icon" },
	{ key = "icon.difficulty-hard-v1", kind = "Icon" },
	{ key = "icon.difficulty-endless-v1", kind = "Icon" },
}

return table.freeze(Assets)
