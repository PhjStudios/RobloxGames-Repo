--!strict

local Ids = require(script.Parent.Parent.util.Ids)

local ConfigTypes = {}

export type AssetKey = string
export type FeatureKey = string

export type AssetKind = "TowerModel" | "EnemyModel" | "MapModel" | "Icon"

export type AssetDefinition = {
	key: AssetKey,
	kind: AssetKind,
}

export type AssetManifest = {
	ordered: { AssetDefinition },
	byKey: { [AssetKey]: AssetDefinition },
}

export type TargetMode = "First" | "Last" | "Strongest" | "Weakest" | "Closest"
export type DamageIncomeClass = "EligibleHealthRemoved" | "None"

export type FeatureKind =
	"AttackBehavior"
	| "EndlessWaveGenerator"
	| "StatusEffect"
	| "MergeProgression"
	| "ResistanceProfile"
	| "EnemyBehavior"

export type AttackBehaviorReference = {
	kind: "AttackBehavior",
	key: FeatureKey,
}

export type StatusEffectReference = {
	kind: "StatusEffect",
	key: FeatureKey,
}

export type MergeProgressionReference = {
	kind: "MergeProgression",
	key: FeatureKey,
}

export type ResistanceProfileReference = {
	kind: "ResistanceProfile",
	key: FeatureKey,
}

export type EnemyBehaviorReference = {
	kind: "EnemyBehavior",
	key: FeatureKey,
}

export type EndlessWaveGeneratorReference = {
	kind: "EndlessWaveGenerator",
	key: FeatureKey,
}

export type FeatureReference =
	AttackBehaviorReference
	| StatusEffectReference
	| MergeProgressionReference
	| ResistanceProfileReference
	| EnemyBehaviorReference
	| EndlessWaveGeneratorReference

export type TowerAttackDefinition = {
	behavior: AttackBehaviorReference,
	damage: number,
	cooldownSeconds: number,
	statusEffects: { StatusEffectReference }?,
}

export type TowerLevelDefinition = {
	upgradeCost: number,
	rangeStuds: number,
	attack: TowerAttackDefinition?,
}

export type TowerDefinition = {
	id: Ids.TowerId,
	displayName: string,
	description: string?,
	modelAssetKey: AssetKey,
	iconAssetKey: AssetKey?,
	placementCost: number,
	footprintRadiusStuds: number,
	placementCap: number,
	supportedTargetModes: { TargetMode },
	defaultTargetMode: TargetMode?,
	levels: { TowerLevelDefinition },
	tags: { FeatureKey }?,
	mergeProgression: MergeProgressionReference?,
}

export type EnemyDefinition = {
	id: Ids.EnemyId,
	displayName: string,
	description: string?,
	modelAssetKey: AssetKey,
	iconAssetKey: AssetKey?,
	maxHealth: number,
	moveSpeedStudsPerSecond: number,
	leakDamage: number,
	damageIncomeClass: DamageIncomeClass,
	tags: { FeatureKey }?,
	resistanceProfile: ResistanceProfileReference?,
	behaviors: { EnemyBehaviorReference }?,
}

export type TowerCatalog = {
	ordered: { TowerDefinition },
	byId: { [Ids.TowerId]: TowerDefinition },
}

export type EnemyCatalog = {
	ordered: { EnemyDefinition },
	byId: { [Ids.EnemyId]: EnemyDefinition },
}

export type MapLaneDefinition = {
	id: FeatureKey,
}

export type MapDefinition = {
	id: Ids.MapId,
	displayName: string,
	description: string?,
	modelAssetKey: AssetKey,
	iconAssetKey: AssetKey?,
	lanes: { MapLaneDefinition },
	supportedDifficultyIds: { Ids.DifficultyId },
	tags: { FeatureKey }?,
}

export type MapCatalog = {
	ordered: { MapDefinition },
	byId: { [Ids.MapId]: MapDefinition },
}

export type BaseConfiguration = {
	maxHealth: number,
}

export type DifficultyModifiers = {
	enemyHealthMultiplier: number,
	enemyMoveSpeedMultiplier: number,
}

export type WaveTimingConfiguration = {
	earlyClearIntermissionSeconds: number,
	bossCadenceWaves: number,
	skipVoteMinimumDelaySeconds: number,
}

export type DifficultyCommon = {
	id: Ids.DifficultyId,
	displayName: string,
	description: string?,
	iconAssetKey: AssetKey?,
	base: BaseConfiguration,
	modifiers: DifficultyModifiers,
	timing: WaveTimingConfiguration,
	tags: { FeatureKey }?,
}

export type FiniteDifficultyDefinition = DifficultyCommon & {
	kind: "Finite",
	waveCount: number,
}

export type EndlessDifficultyDefinition = DifficultyCommon & {
	kind: "Endless",
}

export type DifficultyDefinition = FiniteDifficultyDefinition | EndlessDifficultyDefinition

export type DifficultyCatalog = {
	ordered: { DifficultyDefinition },
	byId: { [Ids.DifficultyId]: DifficultyDefinition },
}

export type WaveSpawnGroupDefinition = {
	enemyId: Ids.EnemyId,
	laneId: FeatureKey,
	count: number,
	startDelaySeconds: number,
	spawnIntervalSeconds: number,
}

export type WaveDeadlinePolicy = "AllSpawnsByDeadline" | "AllowScheduledOverlap"
export type BossKind = "None" | "MiniBoss" | "Boss"
export type WaveRewardClass = "Standard" | "Milestone" | "Final"

export type AuthoredWaveDefinition = {
	id: Ids.WaveId,
	deadlineSeconds: number,
	deadlinePolicy: WaveDeadlinePolicy,
	bossKind: BossKind,
	rewardClass: WaveRewardClass,
	groups: { WaveSpawnGroupDefinition },
}

export type FiniteWaveScheduleDefinition = {
	kind: "AuthoredFinite",
	mapId: Ids.MapId,
	difficultyId: Ids.DifficultyId,
	waves: { AuthoredWaveDefinition },
}

export type EndlessWaveScheduleDefinition = {
	kind: "GeneratedEndless",
	mapId: Ids.MapId,
	difficultyId: Ids.DifficultyId,
	authoredOpeningWaves: { AuthoredWaveDefinition },
	generator: EndlessWaveGeneratorReference,
}

export type WaveScheduleDefinition = FiniteWaveScheduleDefinition | EndlessWaveScheduleDefinition

export type WaveCatalog = {
	ordered: { WaveScheduleDefinition },
	byId: { [Ids.WaveId]: AuthoredWaveDefinition },
	byMapId: { [Ids.MapId]: { [Ids.DifficultyId]: WaveScheduleDefinition } },
}

export type ConfigurationVersion = number
export type CurrencyAmount = number

export type CurrencyRoundingMode = "Floor"
export type DamageAccrualScope = "PerPlayerMatch"

export type SellRefundConfiguration = {
	basisPoints: number,
	rounding: CurrencyRoundingMode,
}

export type DamageIncomeConfiguration = {
	battleCashNumerator: number,
	healthRemovedDenominator: number,
	rounding: CurrencyRoundingMode,
	accrualScope: DamageAccrualScope,
}

export type PersistentGoldRewardMetadata = {
	baseAmountPerEligiblePlayer: CurrencyAmount,
}

export type WaveRewardEconomyDefinition = {
	battleCashStipendPerActivePlayer: CurrencyAmount,
	persistentGold: PersistentGoldRewardMetadata,
}

export type WaveRewardEconomySet = {
	standard: WaveRewardEconomyDefinition,
	milestone: WaveRewardEconomyDefinition,
	final: WaveRewardEconomyDefinition,
}

export type DifficultyEconomyDefinition = {
	difficultyId: Ids.DifficultyId,
	startingBattleCash: CurrencyAmount,
	damageIncome: DamageIncomeConfiguration,
	waveRewards: WaveRewardEconomySet,
}

export type AuthoredEconomyConfiguration = {
	version: ConfigurationVersion,
	sellRefund: SellRefundConfiguration,
	difficultyRules: { DifficultyEconomyDefinition },
}

export type EconomyConfiguration = {
	version: ConfigurationVersion,
	sellRefund: SellRefundConfiguration,
	ordered: { DifficultyEconomyDefinition },
	byDifficultyId: { [Ids.DifficultyId]: DifficultyEconomyDefinition },
}

export type BannerOutcomeDefinition = {
	towerId: Ids.TowerId,
	probabilityPercent: number,
}

export type BannerPullOptionDefinition = {
	goldCost: CurrencyAmount,
}

export type BannerPullOptionsDefinition = {
	onePull: BannerPullOptionDefinition,
	tenPull: BannerPullOptionDefinition,
}

export type BannerPityRuleDefinition = {
	kind: "GuaranteedTower",
	hardPityPullCount: number,
	guaranteedTowerId: Ids.TowerId,
}

export type BannerDefinition = {
	id: Ids.BannerId,
	version: ConfigurationVersion,
	displayName: string,
	pullOptions: BannerPullOptionsDefinition,
	outcomes: { BannerOutcomeDefinition },
	pityRule: BannerPityRuleDefinition?,
}

export type BannerCatalog = {
	ordered: { BannerDefinition },
	byId: { [Ids.BannerId]: BannerDefinition },
}

export type PlayerSettingsDefaults = {
	version: ConfigurationVersion,
	masterVolume: number,
	musicVolume: number,
	sfxVolume: number,
	uiVolume: number,
	cameraShakeIntensity: number,
	damageNumbersEnabled: boolean,
	enemyHealthBarsEnabled: boolean,
	otherPlayerEffectsEnabled: boolean,
	lowDetailEnabled: boolean,
	reducedMotionEnabled: boolean,
	towerRangeEnabled: boolean,
	uiScale: number,
}

-- Every value is deliberately unknown at the validator boundary. Authored
-- modules receive their canonical types only after runtime schema validation.
export type AuthoredConfigurationSources = {
	assets: unknown,
	towers: unknown,
	enemies: unknown,
	difficulties: unknown,
	maps: unknown,
	waves: unknown,
	economy: unknown,
	banners: unknown,
	defaultSettings: unknown,
}

export type CoreConfiguration = {
	assets: AssetManifest,
	towers: TowerCatalog,
	enemies: EnemyCatalog,
	difficulties: DifficultyCatalog,
	maps: MapCatalog,
	waves: WaveCatalog,
	economy: EconomyConfiguration,
	banners: BannerCatalog,
	defaultSettings: PlayerSettingsDefaults,
}

return table.freeze(ConfigTypes)
