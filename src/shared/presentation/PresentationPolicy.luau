--!strict

-- These are admission safety limits, not evidence of a hardware frame budget.
-- Lasting health, range, ownership and navigation never pass through this filter.
local PresentationPolicy = {
	VERSION = 1,
	MAX_EFFECTS = 32,
	LOW_DETAIL_EFFECTS = 8,
	MAX_EFFECTS_PER_FRAME = 4,
	LOW_DETAIL_PER_FRAME = 1,
	MAX_EFFECT_DISTANCE = 180,
	MAX_SOUNDS = 12,
	MAX_MUSIC = 1,
	MAX_UI_SOUNDS = 2,
	MAX_PARTICLES = 0,
}

export type Cue = {
	group: string,
	priority: number,
	minimumInterval: number,
	duration: number,
	persistentEquivalent: string?,
}

local cues: { [string]: Cue } = {
	Placement = { group = "SFX", priority = 2, minimumInterval = 0.1, duration = 1 },
	Attack = { group = "SFX", priority = 1, minimumInterval = 0.12, duration = 0.4 },
	Impact = { group = "SFX", priority = 1, minimumInterval = 0.12, duration = 0.4 },
	Kill = { group = "SFX", priority = 1, minimumInterval = 0.2, duration = 0.5 },
	Upgrade = { group = "SFX", priority = 2, minimumInterval = 0.15, duration = 1 },
	Sell = { group = "SFX", priority = 2, minimumInterval = 0.15, duration = 1 },
	Leak = { group = "SFX", priority = 3, minimumInterval = 0.75, duration = 1, persistentEquivalent = "BaseHealth" },
	BaseDamage = {
		group = "SFX",
		priority = 3,
		minimumInterval = 0.75,
		duration = 1,
		persistentEquivalent = "BaseHealth",
	},
	Boss = { group = "SFX", priority = 3, minimumInterval = 2, duration = 2, persistentEquivalent = "BossPanel" },
	Victory = { group = "SFX", priority = 3, minimumInterval = 2, duration = 3, persistentEquivalent = "ResultsPanel" },
	Defeat = { group = "SFX", priority = 3, minimumInterval = 2, duration = 3, persistentEquivalent = "ResultsPanel" },
	Reward = { group = "UI", priority = 3, minimumInterval = 0.5, duration = 2, persistentEquivalent = "RewardSummary" },
	Selection = { group = "UI", priority = 2, minimumInterval = 0.08, duration = 0.25 },
}
for _, cue in cues do
	table.freeze(cue)
end
PresentationPolicy.CUES = table.freeze(cues)

function PresentationPolicy.effects(settings: { [string]: any }): { [string]: any }
	local reduced = settings.reducedMotionEnabled == true or settings.reducedMotion == true
	local low = settings.lowDetailEnabled == true or settings.lowEffects == true
	return table.freeze({
		maximum = if reduced
			then 0
			elseif low then PresentationPolicy.LOW_DETAIL_EFFECTS
			else PresentationPolicy.MAX_EFFECTS,
		perFrame = if reduced
			then 0
			elseif low then PresentationPolicy.LOW_DETAIL_PER_FRAME
			else PresentationPolicy.MAX_EFFECTS_PER_FRAME,
		flashes = not reduced and not low,
		aiming = not reduced,
		particles = PresentationPolicy.MAX_PARTICLES,
		-- Retained explicitly: reduced presentation never controls these signals.
		criticalSignals = true,
	})
end

return table.freeze(PresentationPolicy)
