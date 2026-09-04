--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Dependencies = {
	clock: () -> unknown,
	activeRoutes: any,
	tutorial: any,
	isCurrent: (number) -> unknown,
}

export type ErrorCode = "INVALID_DEPENDENCIES" | "INVALID_ARGUMENT" | "UNAVAILABLE"
export type RecoveryError = { code: ErrorCode, operation: "recover" }

local TutorialTravelRecovery = {}

local function failure<T>(code: ErrorCode): Result.Failure<RecoveryError>
	return Result.err(table.freeze({ code = code, operation = "recover" }))
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and value > 0 and Validation.isSafeInteger(value :: number)
end

local function resultOk(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function dependencies(value: unknown): Dependencies?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local candidate = value :: any
	if
		type(candidate.clock) ~= "function"
		or type(candidate.activeRoutes) ~= "table"
		or type(candidate.activeRoutes.findConfirmed) ~= "function"
		or type(candidate.tutorial) ~= "table"
		or type(candidate.tutorial.getView) ~= "function"
		or type(candidate.tutorial.repairTravel) ~= "function"
		or type(candidate.tutorial.observeLobbyReturn) ~= "function"
		or type(candidate.isCurrent) ~= "function"
	then
		return nil
	end
	return candidate :: Dependencies
end

local function current(deps: Dependencies, userId: number): boolean
	local called, value = pcall(deps.isCurrent, userId)
	return called and value == true
end

function TutorialTravelRecovery.recover(
	dependenciesValue: unknown,
	userIdValue: unknown,
	eventIdValue: unknown,
	hasValidReturnValue: unknown
): Result.Result<boolean, RecoveryError>
	local deps = dependencies(dependenciesValue)
	if deps == nil then
		return failure("INVALID_DEPENDENCIES")
	end
	if
		not validUserId(userIdValue)
		or type(eventIdValue) ~= "string"
		or #eventIdValue < 1
		or #eventIdValue > 160
		or type(hasValidReturnValue) ~= "boolean"
	then
		return failure("INVALID_ARGUMENT")
	end
	if hasValidReturnValue then
		return Result.ok(false)
	end

	local userId = userIdValue :: number
	local eventId = eventIdValue :: string
	local viewCalled, viewResult = pcall(deps.tutorial.getView, deps.tutorial, userId)
	if not viewCalled or not resultOk(viewResult) then
		return failure("UNAVAILABLE")
	end
	local observation = (viewResult :: any).value
	local tutorial = if type(observation) == "table" then observation.tutorial else nil
	local step = if type(tutorial) == "table" then tutorial.tutorialStep else nil
	if type(step) ~= "number" or step < 4 or step > 8 then
		return Result.ok(false)
	end
	if not current(deps, userId) then
		return Result.ok(false)
	end

	local clockCalled, nowValue = pcall(deps.clock)
	if
		not clockCalled
		or type(nowValue) ~= "number"
		or not Validation.isSafeInteger(nowValue :: number)
		or nowValue < 0
	then
		return failure("UNAVAILABLE")
	end
	local routeCalled, routeResult =
		pcall(deps.activeRoutes.findConfirmed, deps.activeRoutes, userId, nowValue :: number)
	if not routeCalled or not resultOk(routeResult) then
		-- A routing-store error is deliberately not treated as a missing route.
		return failure("UNAVAILABLE")
	end
	if (routeResult :: any).value ~= nil or not current(deps, userId) then
		return Result.ok(false)
	end

	-- Both mutations re-read the profile before committing, closing the profile
	-- race after the strict route check. Step 8 already has a durable result and
	-- its server-tracked Match ID is sufficient to complete a lost Lobby return.
	local repairedCalled, repaired
	if step == 8 then
		local trackedMatchId = tutorial.trackedMatchId
		if type(trackedMatchId) ~= "string" then
			return failure("UNAVAILABLE")
		end
		repairedCalled, repaired = pcall(deps.tutorial.observeLobbyReturn, deps.tutorial, userId, trackedMatchId)
	else
		repairedCalled, repaired = pcall(deps.tutorial.repairTravel, deps.tutorial, userId, eventId)
	end
	if not repairedCalled or not resultOk(repaired) then
		return failure("UNAVAILABLE")
	end
	local repairedObservation = (repaired :: any).value
	return Result.ok(type(repairedObservation) == "table" and repairedObservation.advanced == true)
end

return table.freeze(TutorialTravelRecovery)
