--!strict

local Shared = game:GetService("ReplicatedStorage").Shared
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local ContentSelection = require(Shared.config.ContentSelection)
local Simulation = require(script.Parent.ContentBalanceSimulation)
local Runtime = require(script.Parent.Parent.ProductionServerPlayable.PlayableMatchRuntime)
local Generator = require(script.Parent.Parent.ProductionServerPlayable.EndlessWaveGenerator)

local Report = { VERSION = 1, SEED = 1 }

local function ordered(catalog: any): { any }
	local values = table.clone(catalog.ordered)
	table.sort(values, function(left, right)
		return (left.id or left.difficultyId) < (right.id or right.difficultyId)
	end)
	return values
end

local function waveBudget(
	configuration: any,
	difficulty: any,
	wave: any,
	healthMultiplier: number,
	speedMultiplier: number
): any
	local count, health, speed, spawnSeconds = 0, 0, 0, 0
	for _, group in wave.groups do
		local enemy = configuration.enemies.byId[group.enemyId]
		count += group.count
		health += group.count * math.clamp(
			math.floor(enemy.maxHealth * difficulty.modifiers.enemyHealthMultiplier * healthMultiplier + 0.5),
			1,
			Runtime.MAX_ENEMY_HEALTH
		)
		speed = math.max(
			speed,
			math.clamp(
				enemy.moveSpeedStudsPerSecond * difficulty.modifiers.enemyMoveSpeedMultiplier * speedMultiplier,
				0.1,
				Runtime.MAX_ENEMY_MOVE_SPEED
			)
		)
		spawnSeconds =
			math.max(spawnSeconds, group.startDelaySeconds + math.max(0, group.count - 1) * group.spawnIntervalSeconds)
	end
	return { count = count, health = health, speed = speed, spawnSeconds = spawnSeconds }
end

function Report.render(configuration: any, includeCampaigns: boolean?): string
	assert(
		ConfigurationValidator.isValidatedConfiguration(configuration),
		"report requires validated production content"
	)
	local lines = {
		"# Deterministic content balance report",
		"",
		`Report version {Report.VERSION}; content version {ContentSelection.CONTENT_VERSION}; seed {Report.SEED}.`,
		`Map: {ContentSelection.RELEASE_MAP_ID}. Build policy: ContentBalanceSimulation garden slots, starter pair, virtual clock.`,
		"Evidence: deterministic production configuration and runtime. This is not player acceptance, frame-time, memory, or network evidence.",
		"",
		"## Tower investment and role coverage",
		"",
		"DPS is sustained primary-target damage/cooldown; splash multiplicity, target downtime, buffs, and overkill are excluded.",
		"",
		"| Tower | Level | Investment | Primary DPS | DPS / 100 cash | Range | Role tags |",
		"| --- | ---: | ---: | ---: | ---: | ---: | --- |",
	}
	for _, tower in ordered(configuration.towers) do
		local investment = tower.placementCost
		local roles = {}
		for _, tag in tower.tags or {} do
			if string.sub(tag, 1, 5) == "role." then
				table.insert(roles, tag)
			end
		end
		table.sort(roles)
		for index, level in tower.levels do
			investment += level.upgradeCost
			local dps = if level.attack == nil then 0 else level.attack.damage / level.attack.cooldownSeconds
			table.insert(
				lines,
				string.format(
					"| %s | %d | %d | %.2f | %.2f | %.1f | %s |",
					tower.id,
					index,
					investment,
					dps,
					dps * 100 / investment,
					level.rangeStuds,
					table.concat(roles, ", ")
				)
			)
		end
	end
	table.insert(lines, "\n## Economy pressure\n")
	table.insert(lines, "| Difficulty | Starting cash | Damage income ratio | Standard / milestone / final cash |")
	table.insert(lines, "| --- | ---: | --- | --- |")
	for _, economy in ordered(configuration.economy) do
		table.insert(
			lines,
			string.format(
				"| %s | %d | %d / %d health | %d / %d / %d |",
				economy.difficultyId,
				economy.startingBattleCash,
				economy.damageIncome.battleCashNumerator,
				economy.damageIncome.healthRemovedDenominator,
				economy.waveRewards.standard.battleCashStipendPerActivePlayer,
				economy.waveRewards.milestone.battleCashStipendPerActivePlayer,
				economy.waveRewards.final.battleCashStipendPerActivePlayer
			)
		)
	end
	table.insert(lines, "\n## Finite wave budgets\n")
	table.insert(
		lines,
		"Spawn duration is scheduled first-to-last offset. Health/speed use production rounding and exported runtime caps."
	)
	table.insert(
		lines,
		"\n| Difficulty | Wave | Spawns | Total health | Maximum speed | Spawn seconds | Deadline seconds |"
	)
	table.insert(lines, "| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
	for _, difficulty in ordered(configuration.difficulties) do
		local schedules = configuration.waves.byMapId[ContentSelection.RELEASE_MAP_ID]
		local schedule = schedules[difficulty.id]
		if schedule ~= nil and schedule.kind == "AuthoredFinite" then
			for index, wave in schedule.waves do
				local budget = waveBudget(configuration, difficulty, wave, 1, 1)
				table.insert(
					lines,
					string.format(
						"| %s | %d | %d | %d | %.2f | %.2f | %.2f |",
						difficulty.id,
						index,
						budget.count,
						budget.health,
						budget.speed,
						budget.spawnSeconds,
						wave.deadlineSeconds
					)
				)
			end
		end
	end
	table.insert(lines, "\n## Endless bounds\n")
	table.insert(
		lines,
		`Generator {Generator.GENERATOR_KEY}: at most {Generator.MAX_GROUPS} groups / {Generator.MAX_SPAWNS_PER_WAVE} spawns; health multiplier <= {Generator.MAX_HEALTH_MULTIPLIER}; speed multiplier <= {Generator.MAX_MOVE_SPEED_MULTIPLIER}.`
	)
	table.insert(
		lines,
		`Runtime: {Runtime.MAX_TOWERS} towers / {Runtime.MAX_ENEMIES} enemies / {Runtime.MAX_ACTIVE_WAVE_ORIGINS} overlapping origins; {Runtime.MAX_ATTACKS_PER_STEP} attacks / {Runtime.MAX_SPAWNS_PER_STEP} spawns per fixed step.`
	)
	table.insert(lines, "\n| Generated wave | Spawns | Total health | Maximum speed | Spawn seconds |")
	table.insert(lines, "| ---: | ---: | ---: | ---: | ---: |")
	local endless = configuration.difficulties.byId[ContentSelection.ENDLESS_DIFFICULTY_ID]
	for _, waveNumber in { 1, 10, 100, 1000, 10000 } do
		local generated = Generator.generate(configuration, Generator.GENERATOR_KEY, Report.SEED, waveNumber, "main")
		assert(generated.ok, "production generator rejected report inputs")
		local wave = generated.value
		local budget = waveBudget(configuration, endless, wave.wave, wave.healthMultiplier, wave.moveSpeedMultiplier)
		table.insert(
			lines,
			string.format(
				"| %d | %d | %d | %.2f | %.2f |",
				waveNumber,
				budget.count,
				budget.health,
				budget.speed,
				budget.spawnSeconds
			)
		)
	end
	if includeCampaigns ~= false then
		table.insert(lines, "\n## Production-runtime campaign outcomes\n")
		table.insert(
			lines,
			"Inputs: the fixed starter pair, eight authenticated Garden build slots, one simulated participant, no live profile or reward writes."
		)
		table.insert(
			lines,
			"\n| Difficulty | Outcome | Waves completed | Base health | Cash remaining | Damage | Peak enemies | Seconds |"
		)
		table.insert(lines, "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |")
		for _, difficultyId in
			{
				ContentSelection.EASY_DIFFICULTY_ID,
				ContentSelection.NORMAL_DIFFICULTY_ID,
				ContentSelection.HARD_DIFFICULTY_ID,
			}
		do
			local result = Simulation.run(configuration, difficultyId, ContentSelection.STARTER_TOWER_IDS)
			table.insert(
				lines,
				string.format(
					"| %s | %s | %d | %d | %d | %d | %d | %.2f |",
					difficultyId,
					if result.victory then "Victory" else "Defeat",
					result.wavesCompleted,
					result.baseHealthRemaining,
					result.battleCashRemaining,
					result.damageDealt,
					result.maximumActiveEnemies,
					result.durationSeconds
				)
			)
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

Report.waveBudget = waveBudget
return table.freeze(Report)
