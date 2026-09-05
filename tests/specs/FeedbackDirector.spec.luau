--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local FeedbackDirector = require(script.Parent.Parent.ProductionClientPresentation.FeedbackDirector)

return TestHarness.suite("FeedbackDirector", {
	TestHarness.case("accepted snapshots and events drive the audio owner once", function(assert)
		local observed = { scenes = {}, cues = {}, cleaned = 0 }
		local director = FeedbackDirector.new({
			setScene = function(_self, scene)
				table.insert(observed.scenes, scene)
			end,
			cue = function(_self, cue)
				table.insert(observed.cues, cue)
			end,
			cleanup = function()
				observed.cleaned += 1
			end,
		})
		director:lobby()
		director:snapshot({ matchId = "match:test", revision = 1, state = "Playing" })
		director:attack({ matchId = "match:test", sequence = 1, killed = true })
		director:attack({ matchId = "match:test", sequence = 1, killed = true })
		director:action("Placement")
		assert.equal(#observed.scenes, 2)
		assert.equal(observed.scenes[1], "Lobby")
		assert.equal(observed.scenes[2], "Match")
		assert.equal(#observed.cues, 4)
		assert.equal(observed.cues[4], "Placement")
		director:cleanup()
		director:cleanup()
		director:action("Sell")
		assert.equal(observed.cleaned, 1)
		assert.equal(#observed.cues, 4)
	end),
	TestHarness.case("audio failures cannot escape or alter a snapshot", function(assert)
		local function fail()
			error("synthetic audio failure", 0)
		end
		local director =
			FeedbackDirector.new({ setScene = fail, cue = fail, cleanup = fail, applySettings = fail, step = fail })
		local snapshot =
			table.freeze({ matchId = "match:test", revision = 1, state = "Results", result = "Defeat", baseHealth = 0 })
		director:snapshot(snapshot)
		director:action("Upgrade")
		director:applySettings({})
		director:step(10)
		director:cleanup()
		assert.equal(snapshot.revision, 1)
		assert.equal(snapshot.result, "Defeat")
	end),
})
