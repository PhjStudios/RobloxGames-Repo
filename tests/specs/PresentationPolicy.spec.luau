--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local shared = game:GetService("ReplicatedStorage").Shared.presentation
local Policy = require(shared.PresentationPolicy)
local TowerAim = require(shared.TowerAim)
local FeedbackState = require(shared.FeedbackState)
local AudioManifest = require(shared.AudioManifest)

return TestHarness.suite("PresentationPolicy", {
	TestHarness.case("reduced motion eliminates optional effects and preserves critical signals", function(assert)
		local policy = Policy.effects({ reducedMotionEnabled = true })
		assert.equal(policy.maximum, 0)
		assert.equal(policy.perFrame, 0)
		assert.isFalse(policy.flashes)
		assert.isFalse(policy.aiming)
		assert.isTrue(policy.criticalSignals)
	end),
	TestHarness.case("low detail reduces admission without suppressing critical signals", function(assert)
		local policy = Policy.effects({ lowDetailEnabled = true })
		assert.equal(policy.maximum, 8)
		assert.equal(policy.perFrame, 1)
		assert.isFalse(policy.flashes)
		assert.isTrue(policy.criticalSignals)
	end),
	TestHarness.case("normal effects remain bounded without particle allocation", function(assert)
		local policy = Policy.effects({})
		assert.equal(policy.maximum, 32)
		assert.equal(policy.perFrame, 4)
		assert.equal(policy.particles, 0)
	end),
	TestHarness.case("audio critical cues declare persistent visual equivalents", function(assert)
		for _, key in { "Leak", "BaseDamage", "Boss", "Victory", "Defeat", "Reward" } do
			assert.isNotNil(Policy.CUES[key].persistentEquivalent)
			assert.equal(Policy.CUES[key].priority, 3)
		end
	end),
	TestHarness.case("every music scene and cue has a deliberately unavailable provenance entry", function(assert)
		for _, scene in { "Lobby", "Match", "Boss", "Victory", "Defeat" } do
			assert.isNotNil(AudioManifest.entries[`Music.{scene}`])
		end
		for key in Policy.CUES do
			assert.isNotNil(AudioManifest.entries[key])
		end
		for _, entry in AudioManifest.entries do
			assert.isFalse(entry.approved)
			assert.equal(entry.assetId, "")
		end
	end),
	TestHarness.case("aim smooths toward authority event without snapping or overshoot", function(assert)
		local state = TowerAim.new(0)
		assert.isTrue(TowerAim.observe(state, Vector3.zero, Vector3.new(10, 0, 0), 10))
		local yaw = TowerAim.step(state, 10.016, 0.016, false)
		assert.isTrue(yaw < 0 and yaw > -math.pi / 2)
		for index = 1, 20 do
			yaw = TowerAim.step(state, 10.016 + index * 0.016, 0.016, false)
		end
		assert.isTrue(math.abs(yaw + math.pi / 2) < 0.02)
	end),
	TestHarness.case("lost targets return to saved orientation", function(assert)
		local state = TowerAim.new(0)
		TowerAim.observe(state, Vector3.zero, Vector3.new(10, 0, 0), 10)
		TowerAim.step(state, 10.1, 0.1, false)
		local aimed = math.abs(state.yaw)
		TowerAim.step(state, 11, 0.1, false)
		assert.isNil(state.targetYaw)
		assert.isTrue(math.abs(state.yaw) < aimed)
	end),
	TestHarness.case("live reduced motion clears aim and returns immediately to saved yaw", function(assert)
		local state = TowerAim.new(0.3)
		TowerAim.observe(state, Vector3.zero, Vector3.new(10, 0, 0), 10)
		TowerAim.step(state, 10.1, 0.1, false)
		assert.isTrue(math.abs(TowerAim.step(state, 10.2, 0.1, true) - 0.3) < 1e-9)
		assert.isNil(state.targetYaw)
	end),
	TestHarness.case("degenerate positions and invalid clock cannot poison aiming", function(assert)
		local state = TowerAim.new(0)
		assert.isFalse(TowerAim.observe(state, Vector3.zero, Vector3.zero, 10))
		assert.isFalse(TowerAim.observe(state, Vector3.zero, Vector3.new(0 / 0, 0, 0), 10))
		assert.equal(TowerAim.step(state, 0 / 0, 0.1, false), 0)
	end),
	TestHarness.case("snapshot feedback suppresses duplicates and recovers lasting scenes", function(assert)
		local state = FeedbackState.new()
		local scene, cues =
			FeedbackState.snapshot(state, { matchId = "match:test", revision = 1, baseHealth = 100, state = "Playing" })
		assert.equal(scene, "Match")
		assert.equal(#cues, 0)
		scene, cues = FeedbackState.snapshot(
			state,
			{ matchId = "match:test", revision = 2, baseHealth = 80, state = "Playing", boss = { runtimeEnemyId = 7 } }
		)
		assert.equal(scene, "Boss")
		assert.equal(#cues, 3)
		scene, cues = FeedbackState.snapshot(state, { matchId = "match:test", revision = 2, baseHealth = 60 })
		assert.isNil(scene)
		assert.equal(#cues, 0)
		assert.equal(state.baseHealth, 80)
	end),
	TestHarness.case("result and granted reward cues occur once per transition", function(assert)
		local state = FeedbackState.new()
		local scene, cues = FeedbackState.snapshot(state, {
			matchId = "match:test",
			revision = 1,
			state = "Results",
			result = "Victory",
			reward = { status = "Granted" },
		})
		assert.equal(scene, "Victory")
		assert.equal(#cues, 2)
		local _, repeated = FeedbackState.snapshot(state, {
			matchId = "match:test",
			revision = 2,
			state = "Results",
			result = "Victory",
			reward = { status = "Granted" },
		})
		assert.equal(#repeated, 0)
	end),
	TestHarness.case("late attacks and retired sessions never replay cues", function(assert)
		local state = FeedbackState.new()
		FeedbackState.snapshot(state, { matchId = "match:old", revision = 1 })
		assert.equal(#FeedbackState.attack(state, { matchId = "match:old", sequence = 2, killed = true }), 3)
		assert.equal(#FeedbackState.attack(state, { matchId = "match:old", sequence = 1 }), 0)
		FeedbackState.snapshot(state, { matchId = "match:new", revision = 1 })
		local scene = FeedbackState.snapshot(state, { matchId = "match:old", revision = 4 })
		assert.isNil(scene)
		assert.equal(#FeedbackState.attack(state, { matchId = "match:old", sequence = 3 }), 0)
	end),
	TestHarness.case("retired session history remains bounded", function(assert)
		local state = FeedbackState.new()
		for index = 1, 100 do
			FeedbackState.snapshot(state, { matchId = `match:{index}`, revision = 1 })
		end
		assert.equal(#state.retired, FeedbackState.MAX_RETIRED_MATCHES)
		assert.equal(FeedbackState.action("Upgrade"), "Upgrade")
		assert.isNil(FeedbackState.action("arbitrary"))
	end),
})
