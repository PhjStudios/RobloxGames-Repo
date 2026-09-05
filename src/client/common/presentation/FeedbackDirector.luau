--!strict

local FeedbackState = require(game:GetService("ReplicatedStorage").Shared.presentation.FeedbackState)
local AudioDirector = require(script.Parent.AudioDirector)

local FeedbackDirector = {}

-- The caller supplies accepted authority data. Audio exceptions are contained
-- at this projection boundary and can never invalidate accepted gameplay state.
function FeedbackDirector.new(audio: any)
	local state = FeedbackState.new()
	local cleaned = false
	local function cues(keys: { string })
		for _, key in keys do
			pcall(function()
				audio:cue(key)
			end)
		end
	end
	return table.freeze({
		applySettings = function(_self: any, settings: any)
			if not cleaned then
				pcall(function()
					audio:applySettings(settings)
				end)
			end
		end,
		snapshot = function(_self: any, snapshot: any)
			if cleaned then
				return
			end
			local scene, keys = FeedbackState.snapshot(state, snapshot)
			if scene ~= nil then
				pcall(function()
					audio:setScene(scene)
				end)
			end
			cues(keys)
		end,
		attack = function(_self: any, event: any)
			if not cleaned then
				cues(FeedbackState.attack(state, event))
			end
		end,
		action = function(_self: any, kind: string)
			if cleaned then
				return
			end
			local key = FeedbackState.action(kind)
			if key ~= nil then
				cues({ key })
			end
		end,
		lobby = function(_self: any)
			if not cleaned then
				pcall(function()
					audio:setScene("Lobby")
				end)
			end
		end,
		selection = function(_self: any)
			if not cleaned then
				cues({ "Selection" })
			end
		end,
		reward = function(_self: any)
			if not cleaned then
				cues({ "Reward" })
			end
		end,
		step = function(_self: any, now: number)
			if not cleaned then
				pcall(function()
					audio:step(now)
				end)
			end
		end,
		getMetrics = function(_self: any)
			return audio:getMetrics()
		end,
		cleanup = function(_self: any)
			if cleaned then
				return
			end
			cleaned = true
			state = FeedbackState.new()
			pcall(function()
				audio:cleanup()
			end)
		end,
	})
end

function FeedbackDirector.newForSoundService(soundService: Instance)
	return FeedbackDirector.new(AudioDirector.newForSoundService(soundService))
end

return table.freeze(FeedbackDirector)
