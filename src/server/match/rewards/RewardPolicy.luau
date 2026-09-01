--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchRewards = require(ReplicatedStorage.Shared.config.MatchRewards)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Outcome = "Victory" | "Defeat"

export type Evidence = {
	rewardingMatch: boolean,
	authenticatedParticipant: boolean,
	spectator: boolean,
	submittedReady: boolean,
	placements: number,
	wavesCompleted: number,
	connectedAtResults: boolean,
	outcome: Outcome,
}

export type Breakdown = {
	eligible: boolean,
	reason: string,
	participationGold: number,
	victoryGold: number,
	firstClearGold: number,
	totalGold: number,
}

local RewardPolicy = {}

local function ineligible(reason: string): Result.Result<Breakdown, string>
	return Result.ok(table.freeze({
		eligible = false,
		reason = reason,
		participationGold = 0,
		victoryGold = 0,
		firstClearGold = 0,
		totalGold = 0,
	}))
end

function RewardPolicy.evaluate(
	evidenceValue: unknown,
	firstClearAvailableValue: unknown
): Result.Result<Breakdown, string>
	if type(evidenceValue) ~= "table" or getmetatable(evidenceValue :: any) ~= nil then
		return Result.err("INVALID_EVIDENCE")
	end
	local evidence = evidenceValue :: any
	if
		type(evidence.rewardingMatch) ~= "boolean"
		or type(evidence.authenticatedParticipant) ~= "boolean"
		or type(evidence.spectator) ~= "boolean"
		or type(evidence.submittedReady) ~= "boolean"
		or type(evidence.connectedAtResults) ~= "boolean"
		or type(evidence.placements) ~= "number"
		or not Validation.isSafeInteger(evidence.placements)
		or evidence.placements < 0
		or type(evidence.wavesCompleted) ~= "number"
		or not Validation.isSafeInteger(evidence.wavesCompleted)
		or evidence.wavesCompleted < 0
		or (evidence.outcome ~= "Victory" and evidence.outcome ~= "Defeat")
		or type(firstClearAvailableValue) ~= "boolean"
	then
		return Result.err("INVALID_EVIDENCE")
	end
	if not evidence.rewardingMatch then
		return ineligible("NON_REWARDING_MATCH")
	elseif not evidence.authenticatedParticipant or evidence.spectator then
		return ineligible("NOT_PARTICIPANT")
	elseif MatchRewards.requireReady and not evidence.submittedReady then
		return ineligible("READY_REQUIRED")
	elseif MatchRewards.requireTowerPlacement and evidence.placements < 1 then
		return ineligible("PLACEMENT_REQUIRED")
	elseif not evidence.connectedAtResults and evidence.wavesCompleted < MatchRewards.minimumCompletedWaves then
		return ineligible("PARTICIPATION_TOO_SHORT")
	end

	local victoryGold = if evidence.outcome == "Victory" then MatchRewards.victoryBonusGold else 0
	local firstClearGold = if evidence.outcome == "Victory" and firstClearAvailableValue
		then MatchRewards.firstClearGold
		else 0
	local total = MatchRewards.participationGold + victoryGold + firstClearGold
	return Result.ok(table.freeze({
		eligible = true,
		reason = "ELIGIBLE",
		participationGold = MatchRewards.participationGold,
		victoryGold = victoryGold,
		firstClearGold = firstClearGold,
		totalGold = total,
	}))
end

return table.freeze(RewardPolicy)
