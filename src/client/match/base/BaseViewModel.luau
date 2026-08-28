--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseProtocol = require(ReplicatedStorage.Shared.match.BaseProtocol)
local BaseStateReducer = require(script.Parent.BaseStateReducer)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type RenderState = {
	visible: boolean,
	basePosition: Vector3?,
	baseRevision: number?,
	fillScale: number,
	healthText: string,
	statusText: string,
	lowVisible: boolean,
	lowText: string,
	damageVisible: boolean,
	damageText: string,
}

export type ErrorCode = "INVALID_STATE"

export type Error = {
	code: ErrorCode,
}

local ERROR = table.freeze({ code = "INVALID_STATE" :: "INVALID_STATE" })

local function failure()
	return Result.err(ERROR)
end

local function isExactFeedback(value: unknown, snapshot: BaseProtocol.BaseSnapshot): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local feedback = value :: { [any]: any }
	local count = 0
	for key in next, feedback do
		if key ~= "baseRevision" and key ~= "appliedDamage" and key ~= "leakCount" and key ~= "lowHealthCrossed" then
			return false
		end
		count += 1
	end
	return count == 4
		and type(feedback.baseRevision) == "number"
		and Validation.isSafeInteger(feedback.baseRevision)
		and feedback.baseRevision == snapshot.baseRevision
		and type(feedback.appliedDamage) == "number"
		and Validation.isSafeInteger(feedback.appliedDamage)
		and feedback.appliedDamage >= 1
		and feedback.appliedDamage <= snapshot.maximumHealth
		and type(feedback.leakCount) == "number"
		and Validation.isSafeInteger(feedback.leakCount)
		and feedback.leakCount >= 1
		and feedback.leakCount <= BaseProtocol.MAX_LEAKS_PER_MESSAGE
		and type(feedback.lowHealthCrossed) == "boolean"
end

local function statusText(status: BaseProtocol.BaseStatus): string
	if status == "Active" then
		return "ACTIVE"
	elseif status == "Defeated" then
		return "DEFEATED"
	end
	return "UNAVAILABLE"
end

local BaseViewModel = {}

function BaseViewModel.project(
	value: unknown,
	feedbackValue: BaseStateReducer.DamageFeedback?
): Result.Result<RenderState, Error>
	if value == nil then
		if feedbackValue ~= nil then
			return failure()
		end
		return Result.ok(table.freeze({
			visible = false,
			basePosition = nil,
			baseRevision = nil,
			fillScale = 0,
			healthText = "",
			statusText = "",
			lowVisible = false,
			lowText = "",
			damageVisible = false,
			damageText = "",
		}))
	end

	local validationResult = BaseProtocol.validateBaseSnapshot(value)
	if not validationResult.ok then
		return failure()
	end
	local snapshot = validationResult.value
	if feedbackValue ~= nil and not isExactFeedback(feedbackValue, snapshot) then
		return failure()
	end

	local feedback = feedbackValue :: BaseStateReducer.DamageFeedback?
	local lowVisible = snapshot.lowHealth
	return Result.ok(table.freeze({
		visible = true,
		basePosition = snapshot.basePosition,
		baseRevision = snapshot.baseRevision,
		fillScale = math.clamp(snapshot.currentHealth / snapshot.maximumHealth, 0, 1),
		healthText = string.format("%.0f / %.0f", snapshot.currentHealth, snapshot.maximumHealth),
		statusText = statusText(snapshot.status),
		lowVisible = lowVisible,
		lowText = if lowVisible then "LOW" else "",
		damageVisible = feedback ~= nil,
		damageText = if feedback == nil then "" else string.format("-%.0f", feedback.appliedDamage),
	}))
end

return table.freeze(BaseViewModel)
