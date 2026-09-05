--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local AudioDirector = require(script.Parent.Parent.ProductionClientPresentation.AudioDirector)
local AudioManifest = require(game:GetService("ReplicatedStorage").Shared.presentation.AudioManifest)

local function fixture(unavailable: boolean?)
	local state: any = {
		now = 10,
		voices = {},
		volumes = {},
		created = 0,
		destroyed = 0,
		played = 0,
		cleaned = 0,
		loaded = true,
		failCreate = false,
		failPlay = false,
	}
	local entries = {}
	for key, entry in AudioManifest.entries do
		entries[key] = {
			key = key,
			group = entry.group,
			approved = unavailable ~= true,
			-- Synthetic identifier used only by the in-memory fake, never fetched.
			assetId = "rbxassetid://12345",
			owner = "test-fixture",
			source = "test-fixture",
			license = "test-fixture",
			permissionVerified = true,
		}
	end
	local director = AudioDirector.new({
		now = function()
			return state.now
		end,
		setVolume = function(group, value)
			state.volumes[group] = value
		end,
		create = function(assetId, group, looped)
			if state.failCreate then
				error("synthetic create failure", 0)
			end
			state.created += 1
			local voice = { assetId = assetId, group = group, looped = looped, destroyed = false }
			table.insert(state.voices, voice)
			return voice
		end,
		loaded = function()
			return state.loaded
		end,
		play = function()
			if state.failPlay then
				error("synthetic play failure", 0)
			end
			state.played += 1
		end,
		destroy = function(voice)
			if voice.destroyed then
				error("duplicate destruction", 0)
			end
			voice.destroyed = true
			state.destroyed += 1
		end,
		cleanup = function()
			state.cleaned += 1
		end,
	}, { version = 1, entries = entries })
	return director, state, entries
end

return TestHarness.suite("AudioDirector", {
	TestHarness.case("production adapter owns nested groups starts muted and cleans only its root", function(assert)
		local service = Instance.new("Folder")
		local unrelated = Instance.new("SoundGroup")
		unrelated.Name = "UserAudio"
		unrelated.Parent = service
		local director = AudioDirector.newForSoundService(service)
		local root = service:FindFirstChild(AudioDirector.ROOT_NAME) :: Folder
		local master = root:FindFirstChild("Master") :: SoundGroup
		assert.equal(master.Volume, 0)
		for _, name in { "Music", "SFX", "UI" } do
			assert.isTrue((master:FindFirstChild(name) :: SoundGroup):IsA("SoundGroup"))
		end
		director:applySettings({ masterVolume = 0.5, musicVolume = 0.25, sfxVolume = 0.75, uiVolume = 1 })
		assert.equal(master.Volume, 0.5)
		assert.equal((master:FindFirstChild("Music") :: SoundGroup).Volume, 0.25)
		director:cleanup()
		assert.isNil(service:FindFirstChild(AudioDirector.ROOT_NAME))
		assert.equal(unrelated.Parent, service)
		service:Destroy()
	end),
	TestHarness.case("existing presentation root is preserved on constructor conflict", function(assert)
		local service = Instance.new("Folder")
		local root = Instance.new("Folder")
		root.Name = AudioDirector.ROOT_NAME
		root.Parent = service
		local director = AudioDirector.newForSoundService(service)
		director:cleanup()
		assert.equal(root.Parent, service)
		assert.equal(#service:GetChildren(), 1)
		service:Destroy()
	end),
	TestHarness.case("volume settings apply immediately to separate master and category groups", function(assert)
		local director, state = fixture()
		assert.isTrue(
			director:applySettings({ masterVolume = 0.2, musicVolume = 0.3, sfxVolume = 0.4, uiVolume = 0.5 })
		)
		assert.equal(state.volumes.Master, 0.2)
		assert.equal(state.volumes.Music, 0.3)
		assert.equal(state.volumes.SFX, 0.4)
		assert.equal(state.volumes.UI, 0.5)
		director:cleanup()
	end),
	TestHarness.case("invalid settings are rejected atomically", function(assert)
		local director, state = fixture()
		assert.isFalse(
			director:applySettings({ masterVolume = 0.5, musicVolume = 0.5, sfxVolume = 0 / 0, uiVolume = 0.5 })
		)
		assert.equal(next(state.volumes), nil)
		assert.isFalse(director:applySettings({ masterVolume = 0.5, musicVolume = 0.5, uiVolume = 0.5 }))
		assert.equal(next(state.volumes), nil)
		director:cleanup()
	end),
	TestHarness.case("music transitions own at most one voice and do not restart repeated scenes", function(assert)
		local director, state = fixture()
		for _, scene in { "Lobby", "Match", "Boss", "Victory", "Defeat" } do
			assert.isTrue(director:setScene(scene))
			director:step(state.now)
			assert.equal(director:getMetrics().activeSounds, 1)
		end
		assert.equal(state.created, 5)
		director:setScene("Defeat")
		assert.equal(state.created, 5)
		director:cleanup()
		assert.equal(state.destroyed, 5)
	end),
	TestHarness.case("unapproved asset fallback is silent bounded and cannot allocate", function(assert)
		local director, state = fixture(true)
		for _ = 1, 50 do
			director:cue("Attack")
			state.now += 1
		end
		assert.equal(state.created, 0)
		assert.equal(director:getMetrics().unavailable, 1)
		director:cleanup()
	end),
	TestHarness.case("provenance and experience permission are mandatory", function(assert)
		local director, state, entries = fixture()
		entries.Upgrade.permissionVerified = false
		entries.Sell.license = ""
		assert.isFalse(director:cue("Upgrade"))
		assert.isFalse(director:cue("Sell"))
		assert.equal(state.created, 0)
		director:cleanup()
	end),
	TestHarness.case("slow asset load times out and remains disabled for this session", function(assert)
		local director, state = fixture()
		state.loaded = false
		assert.isTrue(director:cue("Attack"))
		director:step(13)
		assert.equal(state.played, 0)
		director:step(14)
		assert.equal(state.destroyed, 1)
		state.now = 15
		assert.isFalse(director:cue("Attack"))
		assert.equal(state.created, 1)
		director:cleanup()
	end),
	TestHarness.case("cold loads do not queue repeats or play expired transient cues", function(assert)
		local director, state = fixture()
		state.loaded = false
		assert.isTrue(director:cue("Attack"))
		state.now = 10.2
		assert.isFalse(director:cue("Attack"))
		assert.equal(state.created, 1)
		state.loaded = true
		director:step(10.8)
		assert.equal(state.played, 0)
		assert.equal(state.destroyed, 1)
		assert.equal(director:getMetrics().unavailable, 0)
		state.now = 11
		assert.isTrue(director:cue("Attack"))
		director:step(11)
		assert.equal(state.played, 1)
		director:cleanup()
	end),
	TestHarness.case("play failures destroy owned voices and suppress retry spam", function(assert)
		local director, state = fixture()
		state.failPlay = true
		director:cue("Attack")
		director:step(10)
		assert.equal(director:getMetrics().activeSounds, 0)
		assert.equal(state.destroyed, 1)
		state.now = 11
		assert.isFalse(director:cue("Attack"))
		director:cleanup()
	end),
	TestHarness.case("creation failure never escapes into gameplay", function(assert)
		local director, state = fixture()
		state.failCreate = true
		assert.isFalse(director:cue("Attack"))
		assert.equal(director:getMetrics().unavailable, 1)
		director:cleanup()
	end),
	TestHarness.case("UI cue cadence and concurrency avoid repeated feedback fatigue", function(assert)
		local director, state = fixture()
		assert.isTrue(director:cue("Selection"))
		director:step(state.now)
		assert.isFalse(director:cue("Selection"))
		state.now += 0.1
		assert.isTrue(director:cue("Selection"))
		director:step(state.now)
		state.now += 0.1
		assert.isFalse(director:cue("Selection"))
		assert.equal(director:getMetrics().activeSounds, 2)
		director:cleanup()
	end),
	TestHarness.case("a reward cue displaces selection audio without exceeding the UI cap", function(assert)
		local director, state = fixture()
		assert.isTrue(director:cue("Selection"))
		director:step(state.now)
		state.now += 0.1
		assert.isTrue(director:cue("Selection"))
		director:step(state.now)
		assert.isTrue(director:cue("Reward"))
		assert.equal(state.destroyed, 1)
		assert.equal(director:getMetrics().activeSounds, 2)
		director:cleanup()
	end),
	TestHarness.case("dense audio remains bounded and critical feedback displaces decoration", function(assert)
		local director, state = fixture()
		for _, key in
			{
				"Placement",
				"Attack",
				"Impact",
				"Kill",
				"Upgrade",
				"Sell",
				"Leak",
				"BaseDamage",
				"Victory",
				"Defeat",
				"Selection",
				"Reward",
			}
		do
			assert.isTrue(director:cue(key))
			director:step(state.now)
		end
		state.now += 0.2
		assert.isFalse(director:cue("Attack"))
		assert.isTrue(director:cue("Boss"))
		assert.equal(director:getMetrics().activeSounds, 12)
		assert.equal(state.destroyed, 1)
		director:cleanup()
	end),
	TestHarness.case("completed effects and repeated cleanup release every voice exactly once", function(assert)
		local director, state = fixture()
		director:cue("Placement")
		director:step(10)
		director:step(12)
		assert.equal(state.destroyed, 1)
		director:setScene("Match")
		director:cleanup()
		director:cleanup()
		assert.equal(state.destroyed, 2)
		assert.equal(state.cleaned, 1)
		assert.equal(director:getMetrics().activeSounds, 0)
		assert.isFalse(director:cue("Placement"))
	end),
})
