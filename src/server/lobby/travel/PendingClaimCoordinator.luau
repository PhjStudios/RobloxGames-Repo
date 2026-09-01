--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Dependencies = {
	pendingResults: any,
	rewardClaims: any,
	onClaim: ((number, unknown) -> ())?,
}

export type Summary = {
	attempted: number,
	granted: number,
	pending: number,
	ineligible: number,
	failed: number,
	views: { unknown },
}

export type ErrorCode = "INVALID_DEPENDENCIES" | "INVALID_USER_ID" | "PROFILE_NOT_READY" | "CLEANED"
export type ClaimCoordinatorError = { code: ErrorCode, operation: string }

type ServiceData = {
	dependencies: Dependencies,
	busyUserIds: { [number]: boolean },
	cleaned: boolean,
	attemptCount: number,
}

local Methods = {}
Methods.__index = Methods
export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local MAX_PENDING_CLAIMS = 16

local PendingClaimCoordinator = {}

local function failure<T>(code: ErrorCode, operation: string): Result.Failure<ClaimCoordinatorError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_PENDING_CLAIM_COORDINATOR][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and value > 0
end

local function resultOk(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

function Methods.processReady(self: Service, userIdValue: unknown): Result.Result<Summary, ClaimCoordinatorError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "processReady")
	end
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "processReady")
	end
	local userId = userIdValue :: number
	if data.busyUserIds[userId] then
		return failure("PROFILE_NOT_READY", "processReady")
	end
	data.busyUserIds[userId] = true
	local listedCalled, listed = pcall(data.dependencies.pendingResults.list, data.dependencies.pendingResults, userId)
	if not listedCalled or not resultOk(listed) or type((listed :: any).value) ~= "table" then
		data.busyUserIds[userId] = nil
		return failure("PROFILE_NOT_READY", "processReady")
	end
	local records = (listed :: any).value :: { any }
	if #records > MAX_PENDING_CLAIMS then
		data.busyUserIds[userId] = nil
		return failure("PROFILE_NOT_READY", "processReady")
	end
	local views: { unknown } = {}
	local granted = 0
	local pending = 0
	local ineligible = 0
	local failed = 0
	for _, record in records do
		local resultId = if type(record) == "table" then record.resultId else nil
		local called, claimed =
			pcall(data.dependencies.rewardClaims.claim, data.dependencies.rewardClaims, userId, resultId)
		if called and resultOk(claimed) then
			local view = (claimed :: any).value
			table.insert(views, view)
			if type(view) == "table" and view.status == "Granted" then
				granted += 1
			elseif type(view) == "table" and view.status == "Ineligible" then
				ineligible += 1
			elseif type(view) == "table" and view.status == "Pending" then
				pending += 1
			else
				failed += 1
			end
			local callback = data.dependencies.onClaim
			if callback ~= nil then
				pcall(callback, userId, view)
			end
		else
			failed += 1
		end
	end
	data.busyUserIds[userId] = nil
	data.attemptCount += #records
	return Result.ok(table.freeze({
		attempted = #records,
		granted = granted,
		pending = pending,
		ineligible = ineligible,
		failed = failed,
		views = table.freeze(views),
	}))
end

function Methods.cleanup(self: Service): Result.Result<boolean, ClaimCoordinatorError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	data.cleaned = true
	table.clear(data.busyUserIds)
	return Result.ok(true)
end

function Methods.getMetrics(self: Service): { attemptCount: number, cleaned: boolean }
	local data = requireData(self)
	return table.freeze({ attemptCount = data.attemptCount, cleaned = data.cleaned })
end

function Methods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	return table.freeze({
		name = "PendingClaimCoordinator",
		dependencies = table.freeze({}),
		initialize = function() end,
		start = function() end,
		shutdown = function()
			self:cleanup()
		end,
	})
end

function PendingClaimCoordinator.new(dependenciesValue: unknown): Result.Result<Service, ClaimCoordinatorError>
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local dependencies = dependenciesValue :: any
	if
		type(dependencies.pendingResults) ~= "table"
		or type(dependencies.pendingResults.list) ~= "function"
		or type(dependencies.rewardClaims) ~= "table"
		or type(dependencies.rewardClaims.claim) ~= "function"
		or (dependencies.onClaim ~= nil and type(dependencies.onClaim) ~= "function")
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		dependencies = dependenciesValue :: Dependencies,
		busyUserIds = {},
		cleaned = false,
		attemptCount = 0,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(PendingClaimCoordinator)
