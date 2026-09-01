--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type ClaimStatus = "Granted" | "Pending" | "Ineligible" | "Failed"

export type RewardView = {
	resultId: string,
	status: ClaimStatus,
	persistentGoldAwarded: number,
	firstClearBonus: number,
	battleCashEarned: number,
	battleCashSpent: number,
	reason: string,
}

local MAX_GOLD = 1_000_000_000_000

local RewardViewSchema = PayloadValidation.schema(PayloadValidation.record({
	resultId = PayloadValidation.string(64, 8),
	status = PayloadValidation.enum({ "Granted", "Pending", "Ineligible", "Failed" }),
	persistentGoldAwarded = PayloadValidation.integer(0, MAX_GOLD),
	firstClearBonus = PayloadValidation.integer(0, MAX_GOLD),
	battleCashEarned = PayloadValidation.integer(0, MAX_GOLD),
	battleCashSpent = PayloadValidation.integer(0, MAX_GOLD),
	reason = PayloadValidation.string(48, 1),
}))

local RewardProtocol = {
	RewardViewSchema = RewardViewSchema,
}

function RewardProtocol.validateRewardView(value: unknown): Result.Result<RewardView, Validation.Issue>
	local validated = RewardViewSchema:validate(value)
	if not validated.ok then
		return Result.err(validated.error)
	end
	local view = validated.value :: RewardView
	if string.match(view.resultId, "^result:[a-z0-9][a-z0-9_.%-]*$") == nil then
		return Result.err(Validation.issue("INVALID_ID", { "payload", "resultId" }, "Result ID is malformed"))
	end
	if view.firstClearBonus > view.persistentGoldAwarded then
		return Result.err(
			Validation.issue("INVALID_REFERENCE", { "payload", "firstClearBonus" }, "Bonus exceeds award")
		)
	end
	if view.status ~= "Granted" and (view.persistentGoldAwarded ~= 0 or view.firstClearBonus ~= 0) then
		return Result.err(
			Validation.issue("INVALID_REFERENCE", { "payload" }, "Only a durable claim may display awarded Gold")
		)
	end
	return Result.ok(view)
end

return table.freeze(RewardProtocol)
