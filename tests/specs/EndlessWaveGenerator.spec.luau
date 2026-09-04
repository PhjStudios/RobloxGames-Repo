--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local ContentSelection = require(ReplicatedStorage.Shared.config.ContentSelection)
local EndlessWaveGenerator = require(script.Parent.Parent.ProductionServerPlayable.EndlessWaveGenerator)

local loadedConfiguration = ConfigurationValidator.validateLoaded()
if not loadedConfiguration.ok then
	error("expected the loaded production configuration to validate", 0)
end
local CONFIGURATION = loadedConfiguration.value

local function generated(assertions: TestHarness.Assertions, seed: number, waveNumber: number): any
	local result =
		EndlessWaveGenerator.generate(CONFIGURATION, ContentSelection.ENDLESS_GENERATOR_KEY, seed, waveNumber, "main")
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected Endless wave generation to succeed", 0)
	end
	return result.value
end

local function signature(value: any): string
	local groups = {}
	for _, group in value.wave.groups do
		table.insert(groups, `{group.enemyId}:{group.count}:{group.startDelaySeconds}:{group.spawnIntervalSeconds}`)
	end
	return table.concat({
		value.wave.id,
		value.wave.deadlinePolicy,
		value.wave.bossKind,
		value.wave.rewardClass,
		tostring(value.healthMultiplier),
		tostring(value.moveSpeedMultiplier),
		table.concat(groups, "|"),
	}, ";")
end

return TestHarness.suite("deterministic bounded Endless wave generation", {
	TestHarness.case("derives stable nonzero seeds without using global RNG state", function(assertions)
		local first = EndlessWaveGenerator.deriveSeed("match:endless-seed", ContentSelection.CONTENT_VERSION)
		local repeatSeed = EndlessWaveGenerator.deriveSeed("match:endless-seed", ContentSelection.CONTENT_VERSION)
		local other = EndlessWaveGenerator.deriveSeed("match:endless-other", ContentSelection.CONTENT_VERSION)
		assertions.isNotNil(first)
		assertions.equal(first, repeatSeed)
		assertions.notEqual(first, other)
		assertions.isNil(EndlessWaveGenerator.deriveSeed("", ContentSelection.CONTENT_VERSION))
		assertions.isNil(EndlessWaveGenerator.deriveSeed("match:endless-seed", 0))
	end),

	TestHarness.case("soaks ten thousand lazily generated waves within every hard bound", function(assertions)
		local seed = 1_337_337
		local otherSeedDiffers = false
		for waveNumber = 1, 10_000 do
			local value = generated(assertions, seed, waveNumber)
			local repeatValue = generated(assertions, seed, waveNumber)
			assertions.equal(signature(value), signature(repeatValue))
			assertions.isTrue(table.isfrozen(value))
			assertions.isTrue(table.isfrozen(value.wave))
			assertions.isTrue(table.isfrozen(value.wave.groups))
			assertions.isTrue(#value.wave.groups >= 1)
			assertions.isTrue(#value.wave.groups <= EndlessWaveGenerator.MAX_GROUPS)
			assertions.isTrue(value.healthMultiplier >= 1)
			assertions.isTrue(value.healthMultiplier <= EndlessWaveGenerator.MAX_HEALTH_MULTIPLIER)
			assertions.isTrue(value.moveSpeedMultiplier >= 1)
			assertions.isTrue(value.moveSpeedMultiplier <= EndlessWaveGenerator.MAX_MOVE_SPEED_MULTIPLIER)
			assertions.equal(value.wave.id, `wave:endless-v1-{waveNumber}`)
			assertions.notEqual(value.wave.rewardClass, "Final")

			local spawnCount = 0
			local bossCount = 0
			local miniBossCount = 0
			for _, group in value.wave.groups do
				spawnCount += group.count
				local enemy = CONFIGURATION.enemies.byId[group.enemyId]
				assertions.isNotNil(enemy)
				if enemy ~= nil and enemy.threatClass == "Boss" then
					bossCount += group.count
				elseif enemy ~= nil and enemy.threatClass == "MiniBoss" then
					miniBossCount += group.count
				end
			end
			assertions.isTrue(spawnCount <= EndlessWaveGenerator.MAX_SPAWNS_PER_WAVE)
			if waveNumber % 10 == 0 then
				assertions.equal(value.wave.bossKind, "Boss")
				assertions.equal(value.wave.rewardClass, "Milestone")
				assertions.equal(bossCount, 1)
				assertions.equal(miniBossCount, 0)
			elseif waveNumber >= 15 and waveNumber % 5 == 0 then
				assertions.equal(value.wave.bossKind, "MiniBoss")
				assertions.equal(value.wave.rewardClass, "Milestone")
				assertions.equal(bossCount, 0)
				assertions.equal(miniBossCount, 1)
			else
				assertions.equal(value.wave.bossKind, "None")
				assertions.equal(value.wave.rewardClass, "Standard")
				assertions.equal(bossCount, 0)
				assertions.equal(miniBossCount, 0)
			end

			if waveNumber <= 100 and signature(value) ~= signature(generated(assertions, seed + 1, waveNumber)) then
				otherSeedDiffers = true
			end
		end
		assertions.isTrue(otherSeedDiffers)

		local distant = generated(assertions, seed, 1_000_000_000_000)
		assertions.equal(distant.healthMultiplier, EndlessWaveGenerator.MAX_HEALTH_MULTIPLIER)
		assertions.equal(distant.moveSpeedMultiplier, EndlessWaveGenerator.MAX_MOVE_SPEED_MULTIPLIER)
		assertions.equal(distant.wave.bossKind, "Boss")
	end),

	TestHarness.case("rejects unowned generator keys and malformed stable inputs", function(assertions)
		assertions.isFalse(EndlessWaveGenerator.generate(CONFIGURATION, "wave-generator:wrong", 1, 1, "main").ok)
		assertions.isFalse(
			EndlessWaveGenerator.generate(CONFIGURATION, ContentSelection.ENDLESS_GENERATOR_KEY, 0, 1, "main").ok
		)
		assertions.isFalse(
			EndlessWaveGenerator.generate(CONFIGURATION, ContentSelection.ENDLESS_GENERATOR_KEY, 1, 0, "main").ok
		)
		assertions.isFalse(
			EndlessWaveGenerator.generate(CONFIGURATION, ContentSelection.ENDLESS_GENERATOR_KEY, 1, 1, "bad lane").ok
		)
	end),
})
