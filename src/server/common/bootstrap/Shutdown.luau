local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage.Shared.logging.Log)

export type Status = "Completed" | "Failed" | "TimedOut"

export type Result = {
	status: Status,
	elapsedSeconds: number,
}

export type ErrorCode = "INVALID_CONTEXT" | "INVALID_CALLBACK" | "INVALID_BUDGET"

export type ShutdownCallback = () -> ()

local DEFAULT_BUDGET_SECONDS = 10
local MAX_BUDGET_SECONDS = 25
local POLL_INTERVAL_SECONDS = 0.01

local Shutdown = {
	DEFAULT_BUDGET_SECONDS = DEFAULT_BUDGET_SECONDS,
	MAX_BUDGET_SECONDS = MAX_BUDGET_SECONDS,
}

local function isFiniteNumber(value: number): boolean
	return value == value and value > 0 and value < math.huge
end

local function result(status: Status, elapsedSeconds: number): Result
	return table.freeze({
		status = status,
		elapsedSeconds = elapsedSeconds,
	})
end

function Shutdown.run(logger: Log.Logger, callback: ShutdownCallback, budgetSeconds: number): Result
	if not Log.isLogger(logger) then
		error(
			"[ATD][ERROR][context=unknown][role=Unresolved][placeId=unknown][environment=unknown][subsystem=shutdown][event=run_rejected][code=INVALID_CONTEXT] Shutdown requires a genuine context-bound Log",
			0
		)
	end

	if type(callback) ~= "function" then
		logger:error("shutdown", "run_rejected", "Shutdown callback must be a function", {
			code = "INVALID_CALLBACK",
		})
	end

	if type(budgetSeconds) ~= "number" or not isFiniteNumber(budgetSeconds) or budgetSeconds > MAX_BUDGET_SECONDS then
		logger:error("shutdown", "run_rejected", "Shutdown budget must be greater than zero and at most 25 seconds", {
			code = "INVALID_BUDGET",
		})
	end

	local startedAt = os.clock()
	local deadline = startedAt + budgetSeconds
	local callbackSucceeded = false
	local callbackCompletedAt: number? = nil

	task.spawn(function()
		callbackSucceeded = pcall(callback)
		callbackCompletedAt = os.clock()
	end)

	while callbackCompletedAt == nil do
		local remainingSeconds = deadline - os.clock()
		if remainingSeconds <= 0 then
			break
		end

		task.wait(math.min(POLL_INTERVAL_SECONDS, remainingSeconds))
	end

	if callbackCompletedAt ~= nil and callbackCompletedAt <= deadline then
		return result(if callbackSucceeded then "Completed" else "Failed", callbackCompletedAt - startedAt)
	end

	-- Do not cancel the worker. Cancellation can strand Cleanup in Cleaning or
	-- ServiceLifecycle in ShuttingDown; the closing process remains the hard stop.
	local finishedAt = callbackCompletedAt or os.clock()
	return result("TimedOut", finishedAt - startedAt)
end

return table.freeze(Shutdown)
