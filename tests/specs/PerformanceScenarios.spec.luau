--!strict

local Harness = require(script.Parent.Parent.Support.TestHarness)
local Scenarios = require(script.Parent.Parent.Support.PerformanceScenarios)
local Shared = game:GetService("ReplicatedStorage").Shared
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local PlayableMatchProtocol = require(Shared.match.PlayableMatchProtocol)
local config = ConfigurationValidator.validateLoaded().value

return Harness.suite("deterministic performance accounting and runtime cleanup", {
	Harness.case("measures validated saturated projections and attack envelopes for four recipients", function(a)
		local report = Scenarios.runDense()
		a.equal(report.maximumTowers, PlayableMatchProtocol.MAX_ACTIVE_TOWERS)
		a.equal(report.maximumEnemies, PlayableMatchProtocol.MAX_ACTIVE_ENEMIES)
		a.equal(report.recipients, 4)
		a.equal(report.snapshotEnvelopes, 400)
		a.isTrue(report.logicalAttacks > 0)
		a.isTrue(report.snapshotSizes.maximum < 32_768)
		a.isTrue(report.attackSizes.maximum < 1_024)
		a.equal(report.cleanedTowers, 0)
		a.equal(report.cleanedEnemies, 0)
		a.equal(report.cleanedParticipants, 0)
		a.isTrue(report.waveOriginsBeforeCleanup > 0)
		a.equal(report.cleanedWaveOrigins, 0)
		print(
			`ATD_PERFORMANCE_DENSE duration={report.durationSeconds} recipients={report.recipients} towers={report.maximumTowers} enemies={report.maximumEnemies} snapshots={report.snapshotEnvelopes} snapshotMax={report.snapshotSizes.maximum} snapshotMean={report.snapshotSizes.mean} snapshotTotal={report.snapshotEstimatedBytes} logicalAttacks={report.logicalAttacks} deliveredAttacks={report.deliveredAttackEnvelopes} attackMax={report.attackSizes.maximum} attackMean={report.attackSizes.mean} attackTotal={report.attackEstimatedBytes} stepP50Ms={report.stepMilliseconds.p50} stepP95Ms={report.stepMilliseconds.p95} stepMaxMs={report.stepMilliseconds.maximum} hostElapsedSeconds={report.hostElapsedSeconds} kind=JSON-like-estimate-not-wire`
		)
	end),
	Harness.case("repeated finite authority sessions retire entities participants and snapshot access", function(a)
		local first = Scenarios.runRepeatedFinite(config, 24)
		local repeatResult = Scenarios.runRepeatedFinite(config, 24)
		a.equal(first.terminalResults, 24)
		a.equal(first.outcomes, repeatResult.outcomes)
		a.equal(first.totalSteps, repeatResult.totalSteps)
		a.equal(first.remainingTowers, 0)
		a.equal(first.remainingEnemies, 0)
		a.equal(first.remainingParticipants, 0)
		print(
			`ATD_PERFORMANCE_FINITE cycles={first.cycles + repeatResult.cycles} stepsPer24Cycles={first.totalSteps} maximumEnemies={first.maximumEnemies} cleanedEntities=0 cleanedParticipants=0 evidence=deterministic-not-engine-memory`
		)
	end),
	Harness.case("repeated Garden campaign reports reuse production runtime and remain reproducible", function(a)
		local first = Scenarios.runCampaigns(config, 1)
		a.equal(first, Scenarios.runCampaigns(config, 1))
		a.contains(first, "difficulty:easy-v1:true:20")
		print(`ATD_PERFORMANCE_CAMPAIGNS repeats=2 difficulties=3 outcomes={first}`)
	end),
	Harness.case("two thousand generated Endless descriptions preserve hard bounds and signature", function(a)
		local first = Scenarios.runEndlessDescriptions(config, 2_000)
		local repeated = Scenarios.runEndlessDescriptions(config, 2_000)
		a.equal(first.checksum, repeated.checksum)
		a.isTrue(first.maximumSpawns <= 96)
		a.isTrue(first.maximumGroups <= 8)
		print(
			`ATD_PERFORMANCE_ENDLESS generatedWaves={first.waves} repeats=2 groups={first.maximumGroups} spawns={first.maximumSpawns} checksum={first.checksum} evidence=generator-only`
		)
	end),
})
