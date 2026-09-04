--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)

local ALL_TARGET_MODES: { ConfigTypes.TargetMode } = {
	"First",
	"Last",
	"Strongest",
	"Weakest",
	"Closest",
}
local Towers: { ConfigTypes.TowerDefinition } = {
	{
		id = "tower:dart-ant",
		displayName = "Dart Ant",
		description = "Reliable single-target damage with balanced range.",
		modelAssetKey = "tower.dart-ant-model",
		iconAssetKey = "icon.dart-ant",
		placementCost = 120,
		footprintRadiusStuds = 1.5,
		placementCap = 8,
		supportedTargetModes = ALL_TARGET_MODES,
		defaultTargetMode = "First",
		levels = {
			{
				upgradeCost = 0,
				rangeStuds = 24,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.direct" },
					damage = 12,
					cooldownSeconds = 0.8,
				},
			},
			{
				upgradeCost = 110,
				rangeStuds = 27,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.direct" },
					damage = 22,
					cooldownSeconds = 0.7,
				},
			},
			{
				upgradeCost = 190,
				rangeStuds = 30,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.direct" },
					damage = 38,
					cooldownSeconds = 0.62,
				},
			},
		},
		tags = { "production", "role.balanced", "attack.direct" },
	},
	{
		id = "tower:rapid-ant",
		displayName = "Rapid Ant",
		description = "Fast attacks excel against scouts and swarms.",
		modelAssetKey = "tower.rapid-ant-model",
		iconAssetKey = "icon.rapid-ant",
		placementCost = 165,
		footprintRadiusStuds = 1.4,
		placementCap = 6,
		supportedTargetModes = ALL_TARGET_MODES,
		defaultTargetMode = "Closest",
		levels = {
			{
				upgradeCost = 0,
				rangeStuds = 20,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.direct" },
					damage = 5,
					cooldownSeconds = 0.24,
				},
			},
			{
				upgradeCost = 135,
				rangeStuds = 22,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.direct" },
					damage = 8,
					cooldownSeconds = 0.2,
				},
			},
			{
				upgradeCost = 220,
				rangeStuds = 24,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.direct" },
					damage = 13,
					cooldownSeconds = 0.18,
				},
			},
		},
		tags = { "production", "role.rapid", "attack.direct" },
	},
	{
		id = "tower:guard-ant",
		displayName = "Guard Ant",
		description = "Slow, heavy hits punish durable enemies at long range.",
		modelAssetKey = "tower.guard-ant-model",
		iconAssetKey = "icon.guard-ant",
		placementCost = 225,
		footprintRadiusStuds = 1.9,
		placementCap = 4,
		supportedTargetModes = ALL_TARGET_MODES,
		defaultTargetMode = "Strongest",
		levels = {
			{
				upgradeCost = 0,
				rangeStuds = 30,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.direct" },
					damage = 42,
					cooldownSeconds = 1.55,
				},
			},
			{
				upgradeCost = 180,
				rangeStuds = 34,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.direct" },
					damage = 72,
					cooldownSeconds = 1.4,
				},
			},
			{
				upgradeCost = 300,
				rangeStuds = 38,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.direct" },
					damage = 125,
					cooldownSeconds = 1.25,
				},
			},
		},
		tags = { "production", "role.heavy", "attack.direct" },
	},
	{
		id = "tower:bombardier-ant",
		displayName = "Bombardier Ant",
		description = "Arcing seed pods burst across tightly packed swarms.",
		modelAssetKey = "tower.bombardier-ant-model",
		iconAssetKey = "icon.bombardier-ant",
		placementCost = 195,
		footprintRadiusStuds = 1.8,
		placementCap = 5,
		supportedTargetModes = ALL_TARGET_MODES,
		defaultTargetMode = "First",
		levels = {
			{
				upgradeCost = 0,
				rangeStuds = 21,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.splash" },
					damage = 20,
					cooldownSeconds = 1.4,
					splashRadiusStuds = 5.5,
				},
			},
			{
				upgradeCost = 145,
				rangeStuds = 23,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.splash" },
					damage = 34,
					cooldownSeconds = 1.25,
					splashRadiusStuds = 6,
				},
			},
			{
				upgradeCost = 250,
				rangeStuds = 26,
				attack = {
					behavior = { kind = "AttackBehavior", key = "attack.splash" },
					damage = 58,
					cooldownSeconds = 1.1,
					splashRadiusStuds = 6.5,
				},
			},
		},
		tags = { "production", "starter", "role.area", "attack.splash" },
	},
}

return table.freeze(Towers)
