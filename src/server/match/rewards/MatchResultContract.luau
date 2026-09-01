--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Outcome = "Victory" | "Defeat"

export type Entry = {
	userId: number,
	authenticatedParticipant: boolean,
	spectator: boolean,
	submittedReady: boolean,
	placements: number,
	wavesCompleted: number,
	connectedAtResults: boolean,
	battleCashEarned: number,
	battleCashSpent: number,
}

export type MatchResult = {
	version: number,
	resultId: string,
	matchId: Ids.MatchId,
	ticketId: string,
	mapId: Ids.MapId,
	difficultyId: Ids.DifficultyId,
	outcome: Outcome,
	createdAt: number,
	rewardingMatch: boolean,
	entries: { Entry },
}

export type ContractError = {
	code: string,
	path: string,
}

local VERSION = 1
local MAX_ENTRIES = 4
local MAX_COUNTER = 1_000_000_000_000

local ROOT_FIELDS = table.freeze({
	version = true,
	resultId = true,
	matchId = true,
	ticketId = true,
	mapId = true,
	difficultyId = true,
	outcome = true,
	createdAt = true,
	rewardingMatch = true,
	entries = true,
})

local ENTRY_FIELDS = table.freeze({
	userId = true,
	authenticatedParticipant = true,
	spectator = true,
	submittedReady = true,
	placements = true,
	wavesCompleted = true,
	connectedAtResults = true,
	battleCashEarned = true,
	battleCashSpent = true,
})

local MatchResultContract = {
	VERSION = VERSION,
	MAX_ENTRIES = MAX_ENTRIES,
}

local function failure(code: string, path: string): Result.Failure<ContractError>
	return Result.err(table.freeze({ code = code, path = path }))
end

local function exact(value: unknown, fields: { [string]: boolean }): { [string]: unknown }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "string" or fields[key] ~= true then
			return nil
		end
	end
	for key in fields do
		if rawget(value :: any, key) == nil then
			return nil
		end
	end
	return value :: { [string]: unknown }
end

local function integer(value: unknown, minimum: number, maximum: number): number?
	return if type(value) == "number"
			and Validation.isSafeInteger(value)
			and value >= minimum
			and value <= maximum
		then value
		else nil
end

local function opaque(value: unknown, prefix: string): string?
	if
		type(value) ~= "string"
		or #value < #prefix + 2
		or #value > 64
		or string.sub(value, 1, #prefix + 1) ~= `{prefix}:`
		or string.match(value, `^{prefix}:[a-z0-9][a-z0-9_.%-]*$`) == nil
	then
		return nil
	end
	return value :: string
end

function MatchResultContract.validate(value: unknown): Result.Result<MatchResult, ContractError>
	local record = exact(value, ROOT_FIELDS)
	if record == nil then
		return failure("INVALID_RESULT", "result")
	end
	local matchId = Ids.validateMatchId(record.matchId)
	local mapId = Ids.validateMapId(record.mapId)
	local difficultyId = Ids.validateDifficultyId(record.difficultyId)
	local resultId = opaque(record.resultId, "result")
	local ticketId = opaque(record.ticketId, "ticket")
	local createdAt = integer(record.createdAt, 0, Validation.MAX_SAFE_INTEGER)
	if
		record.version ~= VERSION
		or resultId == nil
		or #resultId > 43
		or ticketId == nil
		or not matchId.ok
		or not mapId.ok
		or not difficultyId.ok
		or (record.outcome ~= "Victory" and record.outcome ~= "Defeat")
		or createdAt == nil
		or type(record.rewardingMatch) ~= "boolean"
		or type(record.entries) ~= "table"
		or getmetatable(record.entries :: any) ~= nil
	then
		return failure("INVALID_FIELD", "result")
	end
	local rawEntries = record.entries :: { [any]: unknown }
	local count = 0
	for key in next, rawEntries do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > MAX_ENTRIES then
			return failure("INVALID_ENTRIES", "result.entries")
		end
		count += 1
	end
	if count < 1 or count ~= #rawEntries then
		return failure("INVALID_ENTRIES", "result.entries")
	end
	local entries: { Entry } = table.create(count)
	local seen: { [number]: boolean } = {}
	for index = 1, count do
		local entry = exact(rawEntries[index], ENTRY_FIELDS)
		local userId = if entry == nil then nil else integer(entry.userId, 1, Validation.MAX_SAFE_INTEGER)
		if
			entry == nil
			or userId == nil
			or seen[userId]
			or type(entry.authenticatedParticipant) ~= "boolean"
			or type(entry.spectator) ~= "boolean"
			or type(entry.submittedReady) ~= "boolean"
			or type(entry.connectedAtResults) ~= "boolean"
			or integer(entry.placements, 0, MAX_COUNTER) == nil
			or integer(entry.wavesCompleted, 0, MAX_COUNTER) == nil
			or integer(entry.battleCashEarned, 0, MAX_COUNTER) == nil
			or integer(entry.battleCashSpent, 0, MAX_COUNTER) == nil
			or (entry.spectator == true and entry.authenticatedParticipant == true)
		then
			return failure("INVALID_ENTRY", `result.entries[{index}]`)
		end
		seen[userId] = true
		entries[index] = table.freeze({
			userId = userId,
			authenticatedParticipant = entry.authenticatedParticipant :: boolean,
			spectator = entry.spectator :: boolean,
			submittedReady = entry.submittedReady :: boolean,
			placements = entry.placements :: number,
			wavesCompleted = entry.wavesCompleted :: number,
			connectedAtResults = entry.connectedAtResults :: boolean,
			battleCashEarned = entry.battleCashEarned :: number,
			battleCashSpent = entry.battleCashSpent :: number,
		})
	end
	return Result.ok(table.freeze({
		version = VERSION,
		resultId = resultId,
		matchId = matchId.value,
		ticketId = ticketId,
		mapId = mapId.value,
		difficultyId = difficultyId.value,
		outcome = record.outcome :: Outcome,
		createdAt = createdAt,
		rewardingMatch = record.rewardingMatch :: boolean,
		entries = table.freeze(entries),
	}))
end

return table.freeze(MatchResultContract)
