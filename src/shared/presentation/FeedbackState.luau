--!strict

-- Feed only already-validated authoritative snapshots/receipts/events into this
-- reducer. Its output is disposable presentation; none is sent to the server.
export type State = {
	matchId: string?,
	revision: number,
	attackSequence: number,
	baseHealth: number?,
	bossId: number?,
	result: string?,
	rewardStatus: string?,
	retired: { string },
}
local FeedbackState = { MAX_RETIRED_MATCHES = 8 }
local ACTION_CUES = table.freeze({
	Placement = "Placement",
	Upgrade = "Upgrade",
	Sell = "Sell",
	Retarget = "Selection",
	Ready = "Selection",
})

function FeedbackState.new(): State
	return {
		matchId = nil,
		revision = 0,
		attackSequence = 0,
		baseHealth = nil,
		bossId = nil,
		result = nil,
		rewardStatus = nil,
		retired = {},
	}
end

function FeedbackState.snapshot(state: State, snapshot: any): (string?, { string })
	local cues = {}
	if
		type(snapshot) ~= "table"
		or type(snapshot.matchId) ~= "string"
		or #snapshot.matchId > 96
		or type(snapshot.revision) ~= "number"
		or snapshot.revision < 1
		or snapshot.revision % 1 ~= 0
	then
		return nil, cues
	end
	if snapshot.matchId ~= state.matchId then
		if table.find(state.retired, snapshot.matchId) then
			return nil, cues
		end
		if state.matchId ~= nil then
			table.insert(state.retired, state.matchId)
			if #state.retired > FeedbackState.MAX_RETIRED_MATCHES then
				table.remove(state.retired, 1)
			end
		end
		state.matchId = snapshot.matchId
		state.revision = 0
		state.attackSequence = 0
		state.baseHealth = nil
		state.bossId = nil
		state.result = nil
		state.rewardStatus = nil
	end
	if snapshot.revision <= state.revision then
		return nil, cues
	end
	state.revision = snapshot.revision
	if type(snapshot.baseHealth) == "number" and snapshot.baseHealth >= 0 and snapshot.baseHealth <= 1e12 then
		if state.baseHealth ~= nil and snapshot.baseHealth < state.baseHealth then
			table.insert(cues, "BaseDamage")
			table.insert(cues, "Leak")
		end
		state.baseHealth = snapshot.baseHealth
	end
	local bossId = if type(snapshot.boss) == "table" then snapshot.boss.runtimeEnemyId else nil
	if bossId ~= nil and bossId ~= state.bossId then
		table.insert(cues, "Boss")
	end
	state.bossId = bossId
	local scene = if bossId ~= nil then "Boss" else "Match"
	if snapshot.state == "Results" and (snapshot.result == "Victory" or snapshot.result == "Defeat") then
		scene = snapshot.result
		if snapshot.result ~= state.result then
			table.insert(cues, snapshot.result)
		end
		state.result = snapshot.result
	end
	local rewardStatus = if type(snapshot.reward) == "table" then snapshot.reward.status else nil
	if rewardStatus == "Granted" and rewardStatus ~= state.rewardStatus then
		table.insert(cues, "Reward")
	end
	state.rewardStatus = rewardStatus
	return scene, cues
end

function FeedbackState.attack(state: State, event: any): { string }
	if
		type(event) ~= "table"
		or event.matchId ~= state.matchId
		or type(event.sequence) ~= "number"
		or event.sequence % 1 ~= 0
		or event.sequence <= state.attackSequence
		or event.sequence > 2 ^ 31 - 1
	then
		return {}
	end
	state.attackSequence = event.sequence
	return if event.killed == true then { "Attack", "Impact", "Kill" } else { "Attack", "Impact" }
end

function FeedbackState.action(kind: string): string?
	return ACTION_CUES[kind]
end

return table.freeze(FeedbackState)
