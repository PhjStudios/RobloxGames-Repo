--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchRewards = require(ReplicatedStorage.Shared.config.MatchRewards)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Outcome = "Victory" | "Defeat"

export type Evidence = {
	resultVersion: number?,
	difficultyId: string?,
	modeKind: "Finite" | "Endless"?,
	highestCompletedWave: number?,
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
		or (evidence.resultVersion ~= nil and evidence.resultVersion ~= 1 and evidence.resultVersion ~= 2)
		or (evidence.modeKind ~= nil and evidence.modeKind ~= "Finite" and evidence.modeKind ~= "Endless")
		or (evidence.resultVersion == 2 and (evidence.modeKind == nil or type(evidence.difficultyId) ~= "string" or type(
			evidence.highestCompletedWave
		) ~= "number" or not Validation.isSafeInteger(evidence.highestCompletedWave) or evidence.highestCompletedWave < 0))
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
		or (evidence.resultVersion == 2 and evidence.wavesCompleted > evidence.highestCompletedWave)
		or (evidence.outcome ~= "Victory" and evidence.outcome ~= "Defeat")
		or (evidence.modeKind == "Endless" and evidence.outcome ~= "Defeat")
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
	if evidence.modeKind == "Endless" then
		if evidence.resultVersion ~= 2 then
			return Result.err("INVALID_EVIDENCE")
		end
		local endless = MatchRewards.endless
		-- Rewards follow the participant's durable participation, not the squad's
		-- eventual high-water mark after that participant may have departed.
		local rewardedWave = math.min(evidence.wavesCompleted, evidence.highestCompletedWave)
		if rewardedWave < endless.minimumCompletedWaves then
			return ineligible("ENDLESS_MINIMUM_WAVES")
		end
		local milestoneCount = math.floor(rewardedWave / endless.milestoneEveryWaves)
		local total = math.min(endless.maximumGold, endless.baseGold + milestoneCount * endless.milestoneGold)
		return Result.ok(table.freeze({
			eligible = true,
			reason = "ELIGIBLE",
			participationGold = total,
			victoryGold = 0,
			firstClearGold = 0,
			totalGold = total,
		}))
	end

	local finiteReward = if evidence.resultVersion == 2 and type(evidence.difficultyId) == "string"
		then MatchRewards.finiteByDifficultyId[evidence.difficultyId]
		else nil
	if evidence.resultVersion == 2 and finiteReward == nil then
		return Result.err("INVALID_EVIDENCE")
	end
	local participationGold = if finiteReward == nil
		then MatchRewards.participationGold
		else finiteReward.participationGold
	local victoryBonusGold = if finiteReward == nil
		then MatchRewards.victoryBonusGold
		else finiteReward.victoryBonusGold
	local configuredFirstClearGold = if finiteReward == nil
		then MatchRewards.firstClearGold
		else finiteReward.firstClearGold
	local victoryGold = if evidence.outcome == "Victory" then victoryBonusGold else 0
	local firstClearGold = if evidence.outcome == "Victory" and firstClearAvailableValue
		then configuredFirstClearGold
		else 0
	local total = participationGold + victoryGold + firstClearGold
	return Result.ok(table.freeze({
		eligible = true,
		reason = "ELIGIBLE",
		participationGold = participationGold,
		victoryGold = victoryGold,
		firstClearGold = firstClearGold,
		totalGold = total,
	}))
end

return table.freeze(RewardPolicy)
