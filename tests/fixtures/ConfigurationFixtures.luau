--!strict

-- Every call returns fresh, mutable raw authored data. These definitions are
-- intentionally test-only and must never be mapped into a production project.
local ConfigurationFixtures = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in next, value do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy
end

local function waveReward(battleCash: number, gold: number): { [string]: any }
	return {
		battleCashStipendPerActivePlayer = battleCash,
		persistentGold = {
			baseAmountPerEligiblePlayer = gold,
		},
	}
end

function ConfigurationFixtures.validSources(): { [string]: any }
	return {
		assets = {
			{ key = "tower.worker-model", kind = "TowerModel" },
			{ key = "tower.guard-model", kind = "TowerModel" },
			{ key = "enemy.worker-ant-model", kind = "EnemyModel" },
			{ key = "map.garden-model", kind = "MapModel" },
			{ key = "icon.worker", kind = "Icon" },
		},
		towers = {
			{
				id = "tower:worker",
				displayName = "Worker Ant",
				description = "A deterministic fixture tower.",
				modelAssetKey = "tower.worker-model",
				iconAssetKey = "icon.worker",
				placementCost = 100,
				footprintRadiusStuds = 1.5,
				placementCap = 8,
				supportedTargetModes = { "First", "Closest" },
				defaultTargetMode = "First",
				levels = {
					{
						upgradeCost = 0,
						rangeStuds = 12,
						attack = {
							behavior = { kind = "AttackBehavior", key = "attack.single-target" },
							damage = 5,
							cooldownSeconds = 1,
							statusEffects = {
								{ kind = "StatusEffect", key = "status.marked" },
							},
						},
					},
					{
						upgradeCost = 75,
						rangeStuds = 14,
						attack = {
							behavior = { kind = "AttackBehavior", key = "attack.single-target" },
							damage = 9,
							cooldownSeconds = 0.8,
						},
					},
				},
				tags = { "fixture", "attacker" },
				mergeProgression = { kind = "MergeProgression", key = "merge.standard" },
			},
			{
				id = "tower:guard",
				displayName = "Guard Ant",
				modelAssetKey = "tower.guard-model",
				placementCost = 50,
				footprintRadiusStuds = 2,
				placementCap = 4,
				supportedTargetModes = {},
				levels = {
					{ upgradeCost = 0, rangeStuds = 0 },
				},
			},
		},
		enemies = {
			{
				id = "enemy:worker-ant",
				displayName = "Worker Ant Enemy",
				description = "A deterministic fixture enemy.",
				modelAssetKey = "enemy.worker-ant-model",
				iconAssetKey = "icon.worker",
				maxHealth = 25,
				moveSpeedStudsPerSecond = 6,
				leakDamage = 2,
				damageIncomeClass = "EligibleHealthRemoved",
				tags = { "fixture" },
				resistanceProfile = { kind = "ResistanceProfile", key = "resistance.none" },
				behaviors = {
					{ kind = "EnemyBehavior", key = "enemy.walk" },
				},
			},
		},
		difficulties = {
			{
				id = "difficulty:normal",
				displayName = "Normal",
				iconAssetKey = "icon.worker",
				kind = "Finite",
				waveCount = 2,
				base = { maxHealth = 100 },
				modifiers = {
					enemyHealthMultiplier = 1,
					enemyMoveSpeedMultiplier = 1,
				},
				timing = {
					earlyClearIntermissionSeconds = 5,
					bossCadenceWaves = 2,
					skipVoteMinimumDelaySeconds = 2,
				},
				tags = { "fixture" },
			},
			{
				id = "difficulty:endless",
				displayName = "Endless",
				kind = "Endless",
				base = { maxHealth = 100 },
				modifiers = {
					enemyHealthMultiplier = 1.25,
					enemyMoveSpeedMultiplier = 1.1,
				},
				timing = {
					earlyClearIntermissionSeconds = 3,
					bossCadenceWaves = 10,
					skipVoteMinimumDelaySeconds = 2,
				},
			},
		},
		maps = {
			{
				id = "map:garden",
				displayName = "Garden",
				description = "A deterministic fixture map.",
				modelAssetKey = "map.garden-model",
				iconAssetKey = "icon.worker",
				lanes = {
					{ id = "lane.main" },
				},
				supportedDifficultyIds = { "difficulty:normal", "difficulty:endless" },
				tags = { "fixture" },
			},
		},
		waves = {
			{
				kind = "AuthoredFinite",
				mapId = "map:garden",
				difficultyId = "difficulty:normal",
				waves = {
					{
						id = "wave:normal-1",
						deadlineSeconds = 20,
						deadlinePolicy = "AllSpawnsByDeadline",
						bossKind = "None",
						rewardClass = "Standard",
						groups = {
							{
								enemyId = "enemy:worker-ant",
								laneId = "lane.main",
								count = 3,
								startDelaySeconds = 0,
								spawnIntervalSeconds = 1,
							},
						},
					},
					{
						id = "wave:normal-2",
						deadlineSeconds = 30,
						deadlinePolicy = "AllowScheduledOverlap",
						bossKind = "Boss",
						rewardClass = "Final",
						groups = {
							{
								enemyId = "enemy:worker-ant",
								laneId = "lane.main",
								count = 1,
								startDelaySeconds = 0,
								spawnIntervalSeconds = 0,
							},
						},
					},
				},
			},
			{
				kind = "GeneratedEndless",
				mapId = "map:garden",
				difficultyId = "difficulty:endless",
				authoredOpeningWaves = {
					{
						id = "wave:endless-1",
						deadlineSeconds = 20,
						deadlinePolicy = "AllSpawnsByDeadline",
						bossKind = "None",
						rewardClass = "Standard",
						groups = {
							{
								enemyId = "enemy:worker-ant",
								laneId = "lane.main",
								count = 2,
								startDelaySeconds = 0,
								spawnIntervalSeconds = 1,
							},
						},
					},
				},
				generator = { kind = "EndlessWaveGenerator", key = "endless.standard" },
			},
		},
		economy = {
			version = 1,
			sellRefund = { basisPoints = 7_000, rounding = "Floor" },
			difficultyRules = {
				{
					difficultyId = "difficulty:normal",
					startingBattleCash = 500,
					damageIncome = {
						battleCashNumerator = 1,
						healthRemovedDenominator = 5,
						rounding = "Floor",
						accrualScope = "PerPlayerMatch",
					},
					waveRewards = {
						standard = waveReward(25, 0),
						milestone = waveReward(50, 1),
						final = waveReward(100, 10),
					},
				},
				{
					difficultyId = "difficulty:endless",
					startingBattleCash = 400,
					damageIncome = {
						battleCashNumerator = 1,
						healthRemovedDenominator = 10,
						rounding = "Floor",
						accrualScope = "PerPlayerMatch",
					},
					waveRewards = {
						standard = waveReward(20, 0),
						milestone = waveReward(60, 2),
						final = waveReward(0, 0),
					},
				},
			},
		},
		banners = {
			{
				id = "banner:starter",
				version = 1,
				displayName = "Starter Banner",
				pullOptions = {
					onePull = { goldCost = 100 },
					tenPull = { goldCost = 900 },
				},
				outcomes = {
					{ towerId = "tower:worker", probabilityPercent = 60 },
					{ towerId = "tower:guard", probabilityPercent = 40 },
				},
				pityRule = {
					kind = "GuaranteedTower",
					hardPityPullCount = 50,
					guaranteedTowerId = "tower:guard",
				},
			},
		},
		defaultSettings = {
			version = 2,
			masterVolume = 1,
			musicVolume = 0.75,
			sfxVolume = 0.8,
			uiVolume = 0.9,
			cameraShakeIntensity = 0.5,
			damageNumbersEnabled = true,
			enemyHealthBarsEnabled = true,
			otherPlayerEffectsEnabled = true,
			lowDetailEnabled = false,
			reducedMotionEnabled = false,
			towerRangeEnabled = true,
			uiScale = 1,
		},
	}
end

function ConfigurationFixtures.clone<T>(value: T): T
	return deepCopy(value)
end

return table.freeze(ConfigurationFixtures)
