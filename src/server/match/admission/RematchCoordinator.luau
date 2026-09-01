--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type VoteState = "Pending" | "Approved" | "Declined" | "Failed"
export type VoteChoice = "Pending" | "Approve" | "Decline"
export type VoteEntry = { userId: number, choice: VoteChoice }
export type FreshRematch = {
	matchId: string,
	resultId: string,
	ticketId: string,
	loadouts: { { userId: number, revision: number } },
}
export type Snapshot = {
	revision: number,
	state: VoteState,
	deadline: number,
	votes: { VoteEntry },
	rematch: FreshRematch?,
}
export type PreviousIds = { matchId: string, resultId: string?, ticketId: string? }
export type Dependencies = { clock: (() -> unknown)?, timeoutSeconds: number? }
export type ErrorCode =
	"INVALID_ARGUMENT"
	| "INVALID_STATE"
	| "STALE_REVISION"
	| "VOTE_CONFLICT"
	| "ROSTER_CHANGED"
	| "FACTORY_FAILED"
	| "CLEANED"
export type Operation = "begin" | "vote" | "disconnect" | "step" | "cleanup"
export type RematchError = { code: ErrorCode, operation: Operation }

type RosterProvider = () -> unknown
type Factory = ({ number }) -> unknown
type ServiceData = {
	previous: PreviousIds,
	rosterProvider: RosterProvider,
	factory: Factory,
	clock: () -> unknown,
	timeoutSeconds: number,
	snapshot: Snapshot?,
	cleaned: boolean,
}

local DEFAULT_TIMEOUT_SECONDS = 20
local MAX_TIMEOUT_SECONDS = 60

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local RematchCoordinator = {
	DEFAULT_TIMEOUT_SECONDS = DEFAULT_TIMEOUT_SECONDS,
}

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<RematchError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_REMATCH_COORDINATOR][code=INVALID_CONTEXT]", 0)
	end
	return data :: ServiceData
end

local function now(data: ServiceData): number?
	local called, value = pcall(data.clock)
	return if called
			and type(value) == "number"
			and Validation.isFiniteNumber(value :: number)
			and value >= 0
		then value :: number
		else nil
end

local function token(value: unknown, prefix: string, maximum: number): string?
	return if type(value) == "string"
			and #value >= #prefix + 2
			and #value <= maximum
			and string.sub(value :: string, 1, #prefix + 1) == `{prefix}:`
		then value :: string
		else nil
end

local function activeRoster(data: ServiceData): { number }?
	local called, value = pcall(data.rosterProvider)
	if not called or type(value) ~= "table" or getmetatable(value :: any) ~= nil or #value < 1 or #value > 4 then
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

local function sameRoster(snapshot: Snapshot, active: { number }): boolean
	if #snapshot.votes ~= #active then
		return false
	end
	for index, entry in snapshot.votes do
		if entry.userId ~= active[index] then
			return false
		end
	end
	return true
end

local function freezeSnapshot(snapshot: Snapshot): Snapshot
	for _, vote in snapshot.votes do
		table.freeze(vote)
	end
	table.freeze(snapshot.votes)
	if snapshot.rematch ~= nil then
		for _, loadout in snapshot.rematch.loadouts do
			table.freeze(loadout)
		end
		table.freeze(snapshot.rematch.loadouts)
		table.freeze(snapshot.rematch)
	end
	return table.freeze(snapshot)
end

local function copySnapshot(snapshot: Snapshot): Snapshot
	local votes: { VoteEntry } = table.create(#snapshot.votes)
	for index, vote in snapshot.votes do
		votes[index] = { userId = vote.userId, choice = vote.choice }
	end
	return {
		revision = snapshot.revision,
		state = snapshot.state,
		deadline = snapshot.deadline,
		votes = votes,
		rematch = snapshot.rematch,
	}
end

local function validateFresh(data: ServiceData, value: unknown, roster: { number }): FreshRematch?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local record = value :: any
	local matchId = token(record.matchId, "match", 100)
	local resultId = token(record.resultId, "result", 43)
	local ticketId = token(record.ticketId, "ticket", 80)
	if
		matchId == nil
		or resultId == nil
		or ticketId == nil
		or matchId == data.previous.matchId
		or resultId == data.previous.resultId
		or ticketId == data.previous.ticketId
		or type(record.loadouts) ~= "table"
		or #record.loadouts ~= #roster
	then
		return nil
	end
	local loadouts: { { userId: number, revision: number } } = table.create(#roster)
	for index, userId in roster do
		local loadout = record.loadouts[index]
		if
			type(loadout) ~= "table"
			or loadout.userId ~= userId
			or type(loadout.revision) ~= "number"
			or not Validation.isSafeInteger(loadout.revision)
			or loadout.revision < 1
		then
			return nil
		end
		loadouts[index] = { userId = userId, revision = loadout.revision }
	end
	return {
		matchId = matchId,
		resultId = resultId,
		ticketId = ticketId,
		loadouts = loadouts,
	}
end

local function decline(data: ServiceData): Snapshot
	local snapshot = data.snapshot :: Snapshot
	if snapshot.state == "Pending" then
		local replacement = copySnapshot(snapshot)
		replacement.revision += 1
		replacement.state = "Declined"
		data.snapshot = freezeSnapshot(replacement)
	end
	return data.snapshot :: Snapshot
end

function Methods.begin(self: Service): Result.Result<Snapshot, RematchError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "begin")
	end
	if data.snapshot ~= nil then
		return Result.ok(data.snapshot :: Snapshot)
	end
	local roster = activeRoster(data)
	local currentTime = now(data)
	if roster == nil or currentTime == nil then
		return failure("INVALID_ARGUMENT", "begin")
	end
	local votes: { VoteEntry } = table.create(#roster)
	for index, userId in roster do
		votes[index] = { userId = userId, choice = "Pending" }
	end
	data.snapshot = freezeSnapshot({
		revision = 1,
		state = "Pending",
		deadline = currentTime + data.timeoutSeconds,
		votes = votes,
		rematch = nil,
	})
	return Result.ok(data.snapshot :: Snapshot)
end

function Methods.vote(
	self: Service,
	userIdValue: unknown,
	approveValue: unknown,
	observedRevisionValue: unknown
): Result.Result<Snapshot, RematchError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "vote")
	end
	local snapshot = data.snapshot
	if
		type(userIdValue) ~= "number"
		or not Validation.isSafeInteger(userIdValue :: number)
		or userIdValue <= 0
		or type(approveValue) ~= "boolean"
	then
		return failure("INVALID_ARGUMENT", "vote")
	end
	if snapshot == nil then
		return failure("INVALID_STATE", "vote")
	end
	local index: number? = nil
	for candidate, vote in snapshot.votes do
		if vote.userId == userIdValue then
			index = candidate
			break
		end
	end
	if index == nil then
		return failure("INVALID_ARGUMENT", "vote")
	end
	local choice: VoteChoice = if approveValue then "Approve" else "Decline"
	if snapshot.votes[index].choice == choice then
		return Result.ok(snapshot)
	end
	if snapshot.state ~= "Pending" then
		return failure("INVALID_STATE", "vote")
	end
	if observedRevisionValue ~= snapshot.revision then
		return failure("STALE_REVISION", "vote")
	end
	local active = activeRoster(data)
	if active == nil or not sameRoster(snapshot, active) then
		decline(data)
		return failure("ROSTER_CHANGED", "vote")
	end
	if snapshot.votes[index].choice ~= "Pending" then
		return failure("VOTE_CONFLICT", "vote")
	end
	local replacement = copySnapshot(snapshot)
	replacement.revision += 1
	replacement.votes[index].choice = choice
	if not approveValue then
		replacement.state = "Declined"
		data.snapshot = freezeSnapshot(replacement)
		return Result.ok(data.snapshot :: Snapshot)
	end
	local unanimous = true
	for _, vote in replacement.votes do
		unanimous = unanimous and vote.choice == "Approve"
	end
	if unanimous then
		local called, factoryValue = pcall(data.factory, table.freeze(active))
		local fresh = if called then validateFresh(data, factoryValue, active) else nil
		if fresh == nil then
			replacement.state = "Failed"
			data.snapshot = freezeSnapshot(replacement)
			return failure("FACTORY_FAILED", "vote")
		end
		replacement.state = "Approved"
		replacement.rematch = fresh
	end
	data.snapshot = freezeSnapshot(replacement)
	return Result.ok(data.snapshot :: Snapshot)
end

function Methods.disconnect(self: Service, userIdValue: unknown): Result.Result<Snapshot, RematchError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "disconnect")
	end
	local snapshot = data.snapshot
	if snapshot == nil or snapshot.state ~= "Pending" then
		return failure("INVALID_STATE", "disconnect")
	end
	for _, vote in snapshot.votes do
		if vote.userId == userIdValue then
			return Result.ok(decline(data))
		end
	end
	return Result.ok(snapshot)
end

function Methods.step(self: Service, nowValue: unknown): Result.Result<Snapshot, RematchError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "step")
	end
	local snapshot = data.snapshot
	if snapshot == nil then
		return failure("INVALID_STATE", "step")
	end
	if type(nowValue) ~= "number" or not Validation.isFiniteNumber(nowValue :: number) or nowValue < 0 then
		return failure("INVALID_ARGUMENT", "step")
	end
	if snapshot.state == "Pending" then
		local active = activeRoster(data)
		if active == nil or not sameRoster(snapshot, active) or nowValue >= snapshot.deadline then
			return Result.ok(decline(data))
		end
	end
	return Result.ok(data.snapshot :: Snapshot)
end

function Methods.cleanup(self: Service): Result.Result<boolean, RematchError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	data.cleaned = true
	data.snapshot = nil
	return Result.ok(true)
end

function RematchCoordinator.new(
	previousValue: unknown,
	rosterProviderValue: unknown,
	factoryValue: unknown,
	dependenciesValue: Dependencies?
): Result.Result<Service, RematchError>
	if
		type(previousValue) ~= "table"
		or getmetatable(previousValue :: any) ~= nil
		or token((previousValue :: any).matchId, "match", 100) == nil
		or ((previousValue :: any).resultId ~= nil and token((previousValue :: any).resultId, "result", 43) == nil)
		or ((previousValue :: any).ticketId ~= nil and token((previousValue :: any).ticketId, "ticket", 80) == nil)
		or type(rosterProviderValue) ~= "function"
		or type(factoryValue) ~= "function"
		or (
			dependenciesValue ~= nil
			and (type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil)
		)
	then
		return failure("INVALID_ARGUMENT", "begin")
	end
	local dependencies = dependenciesValue or {}
	local timeout = dependencies.timeoutSeconds or DEFAULT_TIMEOUT_SECONDS
	if
		(dependencies.clock ~= nil and type(dependencies.clock) ~= "function")
		or type(timeout) ~= "number"
		or not Validation.isSafeInteger(timeout)
		or timeout < 1
		or timeout > MAX_TIMEOUT_SECONDS
	then
		return failure("INVALID_ARGUMENT", "begin")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		previous = {
			matchId = (previousValue :: any).matchId,
			resultId = (previousValue :: any).resultId,
			ticketId = (previousValue :: any).ticketId,
		},
		rosterProvider = rosterProviderValue :: RosterProvider,
		factory = factoryValue :: Factory,
		clock = dependencies.clock or os.clock,
		timeoutSeconds = timeout,
		snapshot = nil,
		cleaned = false,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(RematchCoordinator)
