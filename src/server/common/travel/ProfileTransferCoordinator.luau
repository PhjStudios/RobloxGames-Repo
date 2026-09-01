--!strict

local Result = require(game:GetService("ReplicatedStorage").Shared.util.Result)
local Validation = require(game:GetService("ReplicatedStorage").Shared.util.Validation)

export type ProfileOwner = {
	beginTransfer: (self: ProfileOwner, userId: number) -> any,
	cancelTransfer: (self: ProfileOwner, userId: number) -> any,
	release: (self: ProfileOwner, userId: number) -> any,
	load: (self: ProfileOwner, userId: number) -> any,
}
export type Handle = {}
export type Prepared = { handle: Handle, orderedUserIds: { number }, loadouts: { unknown } }
export type Dependencies = {
	isPresent: (number) -> boolean,
	snapshotLoadout: (number, unknown) -> unknown,
}
export type ErrorCode =
	"INVALID_ARGUMENT"
	| "BUSY"
	| "PROFILE_NOT_READY"
	| "INVALID_LOADOUT"
	| "FLUSH_FAILED"
	| "RELEASE_FAILED"
	| "ROLLBACK_FAILED"
	| "INVALID_HANDLE"
	| "CLEANED"
export type Operation = "prepare" | "rollback" | "recoverCommitted" | "commit" | "cleanup"
export type TransferError = { code: ErrorCode, operation: Operation }

type HandleData = {
	owner: ServiceData,
	orderedUserIds: { number },
	loadouts: { unknown },
	releasedUserIds: { number },
	state: "Released" | "RecoveryPending" | "RolledBack" | "Committed",
}
type ServiceData = {
	profileOwner: ProfileOwner,
	isPresent: (number) -> boolean,
	snapshotLoadout: (number, unknown) -> unknown,
	handles: { [Handle]: boolean },
	busy: boolean,
	cleaned: boolean,
}

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local HANDLE_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: HandleData }
local MAX_RECOVERY_ATTEMPTS = 3

local ProfileTransferCoordinator = {}

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<TransferError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_PROFILE_TRANSFER][code=INVALID_CONTEXT]", 0)
	end
	return data :: ServiceData
end

local function clone(value: any, seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end
	local memo = seen or {}
	if memo[value] ~= nil then
		return memo[value]
	end
	local output = {}
	memo[value] = output
	for key, child in value do
		output[clone(key, memo)] = clone(child, memo)
	end
	return output
end

local function freezeDeep(value: any): any
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			freezeDeep(child)
		end
		table.freeze(value)
	end
	return value
end

local function success(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function roster(value: unknown): { number }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or #value < 1 or #value > 4 then
		return nil
	end
	local output: { number } = table.create(#value)
	local seen: { [number]: boolean } = {}
	for index, candidate in value :: { unknown } do
		if
			type(candidate) ~= "number"
			or not Validation.isSafeInteger(candidate :: number)
			or candidate <= 0
			or seen[candidate :: number]
		then
			return nil
		end
		seen[candidate :: number] = true
		output[index] = candidate :: number
	end
	return output
end

local function readPresence(data: ServiceData, userId: number): boolean?
	local called, value = pcall(data.isPresent, userId)
	return if called and type(value) == "boolean" then value :: boolean else nil
end

local function recoverUser(data: ServiceData, userId: number): boolean
	for _attempt = 1, MAX_RECOVERY_ATTEMPTS do
		local present = readPresence(data, userId)
		if present ~= nil then
			-- A live player needs this server to reacquire its lease. A player who
			-- departed during a partial transfer must instead be settled with a
			-- release; loading them here would create an owner with no later
			-- PlayerRemoving signal to release it.
			local recover = if present then data.profileOwner.load else data.profileOwner.release
			local called, resultValue = pcall(recover, data.profileOwner, userId)
			if called and success(resultValue) then
				local stillPresent = readPresence(data, userId)
				if stillPresent == present then
					return true
				end
				if present then
					-- Presence can change while a protected load yields. Never retain a
					-- newly acquired lease under an uncertain or absent disposition.
					pcall(data.profileOwner.release, data.profileOwner, userId)
				end
			end
		end
	end
	return false
end

local function recoverOwnership(data: ServiceData, releasedUserIds: { number }): ({ number }, boolean)
	local failedUserIds: { number } = {}
	for index = #releasedUserIds, 1, -1 do
		local userId = releasedUserIds[index]
		if not recoverUser(data, userId) then
			table.insert(failedUserIds, userId)
		end
	end
	return failedUserIds, #failedUserIds == 0
end

local function cancelGates(data: ServiceData, gatedUserIds: { number }): ({ number }, boolean)
	local recoveryUserIds: { number } = {}
	local allCancelled = true
	for index = #gatedUserIds, 1, -1 do
		local userId = gatedUserIds[index]
		local called, resultValue = pcall(data.profileOwner.cancelTransfer, data.profileOwner, userId)
		if not called or not success(resultValue) then
			allCancelled = false
			table.insert(recoveryUserIds, userId)
		end
	end
	return recoveryUserIds, allCancelled
end

local function retainRecovery(data: ServiceData, orderedUserIds: { number }, recoveryUserIds: { number })
	if #recoveryUserIds < 1 then
		return
	end
	local handle = table.freeze({}) :: Handle
	HANDLE_DATA[handle] = {
		owner = data,
		orderedUserIds = table.clone(orderedUserIds),
		loadouts = {},
		releasedUserIds = table.clone(recoveryUserIds),
		state = "RecoveryPending",
	}
	data.handles[handle] = true
end

function Methods.prepare(self: Service, userIdsValue: unknown): Result.Result<Prepared, TransferError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "prepare")
	end
	if data.busy then
		return failure("BUSY", "prepare")
	end
	local userIds = roster(userIdsValue)
	if userIds == nil then
		return failure("INVALID_ARGUMENT", "prepare")
	end
	data.busy = true
	local loadouts: { unknown } = table.create(#userIds)
	local gated: { number } = {}
	for index, userId in userIds do
		local beginCalled, beginResult = pcall(data.profileOwner.beginTransfer, data.profileOwner, userId)
		if not beginCalled or not success(beginResult) then
			local recoveryUserIds, cancelled = cancelGates(data, gated)
			retainRecovery(data, userIds, recoveryUserIds)
			data.busy = false
			return failure(if cancelled then "PROFILE_NOT_READY" else "ROLLBACK_FAILED", "prepare")
		end
		table.insert(gated, userId)
		local snapshotCalled, snapshot = pcall(data.snapshotLoadout, userId, (beginResult :: any).value)
		if not snapshotCalled or type(snapshot) ~= "table" or (snapshot :: any).userId ~= userId then
			local recoveryUserIds, cancelled = cancelGates(data, gated)
			retainRecovery(data, userIds, recoveryUserIds)
			data.busy = false
			return failure(if cancelled then "INVALID_LOADOUT" else "ROLLBACK_FAILED", "prepare")
		end
		loadouts[index] = freezeDeep(clone(snapshot))
	end
	local released: { number } = {}
	for index, userId in userIds do
		local called, resultValue = pcall(data.profileOwner.release, data.profileOwner, userId)
		if not called or not success(resultValue) or (resultValue :: any).value ~= true then
			-- Include the release that returned an error. Its protected store call
			-- may have committed before transport failure, so recovery must either
			-- reacquire a present member or finish releasing an absent member.
			local ambiguous = table.clone(released)
			table.insert(ambiguous, userId)
			local remaining: { number } = {}
			for remainingIndex = index + 1, #userIds do
				table.insert(remaining, userIds[remainingIndex])
			end
			local gateRecovery, gatesCancelled = cancelGates(data, remaining)
			for _, recoveryUserId in gateRecovery do
				table.insert(ambiguous, recoveryUserId)
			end
			local unrecovered, rolledBack = recoverOwnership(data, ambiguous)
			if not rolledBack or not gatesCancelled then
				for _, recoveryUserId in gateRecovery do
					if table.find(unrecovered, recoveryUserId) == nil then
						table.insert(unrecovered, recoveryUserId)
					end
				end
				retainRecovery(data, userIds, unrecovered)
			end
			data.busy = false
			return failure(if rolledBack and gatesCancelled then "RELEASE_FAILED" else "ROLLBACK_FAILED", "prepare")
		end
		table.insert(released, userId)
	end
	local handle = table.freeze({}) :: Handle
	HANDLE_DATA[handle] = {
		owner = data,
		orderedUserIds = userIds,
		loadouts = loadouts,
		releasedUserIds = released,
		state = "Released",
	}
	data.handles[handle] = true
	data.busy = false
	return Result.ok(table.freeze({
		handle = handle,
		orderedUserIds = freezeDeep(clone(userIds)),
		loadouts = freezeDeep(clone(loadouts)),
	}))
end

local function handleFor(data: ServiceData, value: unknown): HandleData?
	if type(value) ~= "table" then
		return nil
	end
	local handleData = HANDLE_DATA[value :: any]
	return if handleData ~= nil and handleData.owner == data then handleData else nil
end

function Methods.rollback(self: Service, handleValue: unknown): Result.Result<boolean, TransferError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "rollback")
	end
	if data.busy then
		return failure("BUSY", "rollback")
	end
	local handleData = handleFor(data, handleValue)
	if handleData == nil then
		return failure("INVALID_HANDLE", "rollback")
	end
	if handleData.state == "RolledBack" then
		return Result.ok(false)
	elseif handleData.state ~= "Released" and handleData.state ~= "RecoveryPending" then
		return failure("INVALID_HANDLE", "rollback")
	end
	data.busy = true
	local unrecovered, recovered = recoverOwnership(data, handleData.releasedUserIds)
	handleData.releasedUserIds = unrecovered
	data.busy = false
	if not recovered then
		handleData.state = "RecoveryPending"
		return failure("ROLLBACK_FAILED", "rollback")
	end
	handleData.state = "RolledBack"
	data.handles[handleValue :: Handle] = nil
	return Result.ok(true)
end

-- A transfer handle intentionally disappears after commit, but a later
-- TeleportInitFailed rollback can still require this server to settle profile
-- ownership. Reuse the same presence-aware disposition as ordinary rollback:
-- live players are loaded, while departed players are idempotently released.
-- The post-operation presence check inside recoverUser prevents a load that
-- yielded across PlayerRemoving from leaving an orphan lease behind.
function Methods.recoverCommitted(self: Service, userIdValue: unknown): Result.Result<boolean, TransferError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "recoverCommitted")
	end
	if data.busy then
		return failure("BUSY", "recoverCommitted")
	end
	if type(userIdValue) ~= "number" or not Validation.isSafeInteger(userIdValue :: number) or userIdValue <= 0 then
		return failure("INVALID_ARGUMENT", "recoverCommitted")
	end
	data.busy = true
	local recovered = recoverUser(data, userIdValue :: number)
	data.busy = false
	return if recovered then Result.ok(true) else failure("ROLLBACK_FAILED", "recoverCommitted")
end

function Methods.step(self: Service): number
	local data = requireData(self)
	if data.cleaned or data.busy then
		return 0
	end
	data.busy = true
	local recovered = 0
	for handle in data.handles do
		local handleData = HANDLE_DATA[handle]
		if handleData ~= nil and handleData.state == "RecoveryPending" then
			local unrecovered, allRecovered = recoverOwnership(data, handleData.releasedUserIds)
			handleData.releasedUserIds = unrecovered
			if allRecovered then
				handleData.state = "RolledBack"
				data.handles[handle] = nil
				recovered += 1
			end
		end
	end
	data.busy = false
	return recovered
end

function Methods.commit(self: Service, handleValue: unknown): Result.Result<boolean, TransferError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "commit")
	end
	local handleData = handleFor(data, handleValue)
	if handleData ~= nil and handleData.state == "Committed" then
		return Result.ok(false)
	elseif handleData == nil or handleData.state ~= "Released" then
		return failure("INVALID_HANDLE", "commit")
	end
	handleData.state = "Committed"
	data.handles[handleValue :: Handle] = nil
	table.clear(handleData.loadouts)
	return Result.ok(true)
end

function Methods.cleanup(self: Service): Result.Result<boolean, TransferError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	if data.busy then
		return failure("BUSY", "cleanup")
	end
	data.busy = true
	local successfulRollback = true
	for handle in data.handles do
		local handleData = HANDLE_DATA[handle]
		if handleData ~= nil and (handleData.state == "Released" or handleData.state == "RecoveryPending") then
			local unrecovered, allRecovered = recoverOwnership(data, handleData.releasedUserIds)
			handleData.releasedUserIds = unrecovered
			successfulRollback = allRecovered and successfulRollback
			if allRecovered then
				handleData.state = "RolledBack"
			else
				handleData.state = "RecoveryPending"
			end
		end
		if handleData == nil or handleData.state ~= "RecoveryPending" then
			data.handles[handle] = nil
		end
	end
	data.busy = false
	if not successfulRollback then
		return failure("ROLLBACK_FAILED", "cleanup")
	end
	data.cleaned = true
	return Result.ok(true)
end

function ProfileTransferCoordinator.new(
	ownerValue: unknown,
	dependenciesValue: unknown
): Result.Result<Service, TransferError>
	if
		type(ownerValue) ~= "table"
		or type((ownerValue :: any).beginTransfer) ~= "function"
		or type((ownerValue :: any).cancelTransfer) ~= "function"
		or type((ownerValue :: any).release) ~= "function"
		or type((ownerValue :: any).load) ~= "function"
		or type(dependenciesValue) ~= "table"
		or getmetatable(dependenciesValue :: any) ~= nil
		or type((dependenciesValue :: any).isPresent) ~= "function"
		or type((dependenciesValue :: any).snapshotLoadout) ~= "function"
	then
		return failure("INVALID_ARGUMENT", "prepare")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		profileOwner = ownerValue :: ProfileOwner,
		isPresent = (dependenciesValue :: Dependencies).isPresent,
		snapshotLoadout = (dependenciesValue :: Dependencies).snapshotLoadout,
		handles = {},
		busy = false,
		cleaned = false,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(ProfileTransferCoordinator)
