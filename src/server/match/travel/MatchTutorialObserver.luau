--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialProtocol = require(ReplicatedStorage.Shared.profile.TutorialProtocol)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type TutorialAdapter = {
	observeResult: (self: TutorialAdapter, userId: number, evidence: unknown) -> unknown,
	repairTravel: (self: TutorialAdapter, userId: number, eventId: string) -> unknown,
}

export type Observation = {
	advanced: boolean,
	revision: number,
	tutorial: TutorialProtocol.View,
}

export type ErrorCode =
	"INVALID_ARGUMENT"
	| "TUTORIAL_RESULT_UNAVAILABLE"
	| "TUTORIAL_REPAIR_UNAVAILABLE"
	| "UNRESOLVED_STATE"

export type ObserverError = {
	code: ErrorCode,
	operation: "observeDurableResult",
}

local MatchTutorialObserver = {}

local function failure(code: ErrorCode): Result.Failure<ObserverError>
	return Result.err(table.freeze({ code = code, operation = "observeDurableResult" }))
end

local function resultOk(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function parseObservation(value: unknown): Observation?
	local raw = if resultOk(value) then (value :: any).value else nil
	if
		type(raw) ~= "table"
		or type(raw.advanced) ~= "boolean"
		or type(raw.revision) ~= "number"
		or not Validation.isSafeInteger(raw.revision)
		or raw.revision < 1
	then
		return nil
	end
	local tutorial = TutorialProtocol.validateView(raw.tutorial)
	if not tutorial.ok then
		return nil
	end
	return table.freeze({
		advanced = raw.advanced,
		revision = raw.revision,
		tutorial = tutorial.value,
	})
end

local function repairedState(observation: Observation): boolean
	local view = observation.tutorial
	return view.tutorialStep == 3 and view.trackedMatchId == nil
end

local function completedResultState(observation: Observation, matchId: string): boolean
	local view = observation.tutorial
	return view.tutorialStep == 8 and view.trackedMatchId == matchId
end

function MatchTutorialObserver.observeDurableResult(
	tutorialValue: unknown,
	userIdValue: unknown,
	evidenceValue: unknown
): Result.Result<Observation, ObserverError>
	if
		type(tutorialValue) ~= "table"
		or type((tutorialValue :: any).observeResult) ~= "function"
		or type((tutorialValue :: any).repairTravel) ~= "function"
		or type(userIdValue) ~= "number"
		or not Validation.isSafeInteger(userIdValue :: number)
		or (userIdValue :: number) <= 0
		or type(evidenceValue) ~= "table"
	then
		return failure("INVALID_ARGUMENT")
	end
	local matchId = Ids.validateMatchId((evidenceValue :: any).matchId)
	if not matchId.ok then
		return failure("INVALID_ARGUMENT")
	end
	local tutorial = tutorialValue :: TutorialAdapter
	local userId = userIdValue :: number
	local called, observedValue = pcall(tutorial.observeResult, tutorial, userId, evidenceValue)
	local observed = if called then parseObservation(observedValue) else nil
	if observed == nil then
		return failure("TUTORIAL_RESULT_UNAVAILABLE")
	end

	if completedResultState(observed, matchId.value) or repairedState(observed) then
		return Result.ok(observed)
	end
	local view = observed.tutorial
	local failedBeforeResultStep = view.tutorialStep == 4
		or ((view.tutorialStep == 5 or view.tutorialStep == 6) and view.trackedMatchId == matchId.value)
	if failedBeforeResultStep then
		local eventId = `durable-result-failure|{matchId.value}`
		local repairedCalled, repairedValue = pcall(tutorial.repairTravel, tutorial, userId, eventId)
		local repaired = if repairedCalled then parseObservation(repairedValue) else nil
		if repaired == nil then
			return failure("TUTORIAL_REPAIR_UNAVAILABLE")
		end
		if repairedState(repaired) then
			return Result.ok(repaired)
		end
		return failure("UNRESOLVED_STATE")
	end

	-- A completed or skipped tutorial no longer has tracked Match work. Every
	-- other mismatch remains retryable so a durable result can never strand a
	-- player in a Match-only tutorial state during return travel.
	if
		view.tutorialCompleted
		and view.tutorialStep == TutorialProtocol.COMPLETE_STEP
		and view.trackedMatchId == nil
	then
		return Result.ok(observed)
	end
	return failure("UNRESOLVED_STATE")
end

return table.freeze(MatchTutorialObserver)
