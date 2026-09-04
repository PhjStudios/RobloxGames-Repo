--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Outcome = "Victory" | "Defeat"
export type ModeKind = "Finite" | "Endless"
export type TerminationReason =
	"Victory"
	| "BaseDefeated"
	| "PlayerEnded"
	| "AllParticipantsGone"
	| "Shutdown"
	| "TechnicalTermination"

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

-- Current-only fields are optional in the shared type so historical version-1
-- records and current records can use one durable ledger API. Validation still
-- requires the exact field set for the declared version.
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
	modeKind: ModeKind?,
	highestCompletedWave: number?,
	elapsedSeconds: number?,
	seed: number?,
	contentVersion: number?,
	terminationReason: TerminationReason?,
}

export type ContractError = {
	code: string,
	path: string,
}

local LEGACY_VERSION = 1
local CURRENT_VERSION = 2
local MAX_ENTRIES = 4
local MAX_COUNTER = 1_000_000_000_000
local MAX_SEED = 2_147_483_647

local COMMON_ROOT_FIELDS = {
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
}

local LEGACY_ROOT_FIELDS = table.freeze(table.clone(COMMON_ROOT_FIELDS))
local currentFields = table.clone(COMMON_ROOT_FIELDS)
currentFields.modeKind = true
currentFields.highestCompletedWave = true
currentFields.elapsedSeconds = true
currentFields.seed = true
currentFields.contentVersion = true
currentFields.terminationReason = true
local CURRENT_ROOT_FIELDS = table.freeze(currentFields)

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
	VERSION = CURRENT_VERSION,
	LEGACY_VERSION = LEGACY_VERSION,
	CURRENT_VERSION = CURRENT_VERSION,
	MAX_ENTRIES = MAX_ENTRIES,
	MAX_COUNTER = MAX_COUNTER,
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

local function validateEntries(value: unknown): { Entry }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local rawEntries = value :: { [any]: unknown }
	local count = 0
	for key in next, rawEntries do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > MAX_ENTRIES then
			return nil
		end
		count += 1
	end
	if count < 1 or count ~= #rawEntries then
		return nil
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
			return nil
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
	return table.freeze(entries)
end

function MatchResultContract.validate(value: unknown): Result.Result<MatchResult, ContractError>
	local rawVersion = if type(value) == "table" then (value :: any).version else nil
	local fields = if rawVersion == LEGACY_VERSION
		then LEGACY_ROOT_FIELDS
		elseif rawVersion == CURRENT_VERSION then CURRENT_ROOT_FIELDS
		else nil
	local record = if fields == nil then nil else exact(value, fields)
	if record == nil then
		return failure("INVALID_RESULT", "result")
	end
	local matchId = Ids.validateMatchId(record.matchId)
	local mapId = Ids.validateMapId(record.mapId)
	local difficultyId = Ids.validateDifficultyId(record.difficultyId)
	local resultId = opaque(record.resultId, "result")
	local ticketId = opaque(record.ticketId, "ticket")
	local createdAt = integer(record.createdAt, 0, Validation.MAX_SAFE_INTEGER)
	local entries = validateEntries(record.entries)
	if
		resultId == nil
		or #resultId > 43
		or ticketId == nil
		or not matchId.ok
		or not mapId.ok
		or not difficultyId.ok
		or (record.outcome ~= "Victory" and record.outcome ~= "Defeat")
		or createdAt == nil
		or type(record.rewardingMatch) ~= "boolean"
		or entries == nil
	then
		return failure("INVALID_FIELD", "result")
	end

	local common = {
		version = rawVersion :: number,
		resultId = resultId,
		matchId = matchId.value,
		ticketId = ticketId,
		mapId = mapId.value,
		difficultyId = difficultyId.value,
		outcome = record.outcome :: Outcome,
		createdAt = createdAt,
		rewardingMatch = record.rewardingMatch :: boolean,
		entries = entries,
	}
	if rawVersion == LEGACY_VERSION then
		return Result.ok(table.freeze(common) :: MatchResult)
	end

	local highestCompletedWave = integer(record.highestCompletedWave, 0, MAX_COUNTER)
	local elapsedSeconds = integer(record.elapsedSeconds, 0, MAX_COUNTER)
	local seed = integer(record.seed, 1, MAX_SEED)
	local contentVersion = integer(record.contentVersion, 1, Validation.MAX_SAFE_INTEGER)
	local modeKind = record.modeKind
	local terminationReason = record.terminationReason
	local validTermination = terminationReason == "Victory"
		or terminationReason == "BaseDefeated"
		or terminationReason == "PlayerEnded"
		or terminationReason == "AllParticipantsGone"
		or terminationReason == "Shutdown"
		or terminationReason == "TechnicalTermination"
	if
		(modeKind ~= "Finite" and modeKind ~= "Endless")
		or highestCompletedWave == nil
		or elapsedSeconds == nil
		or seed == nil
		or contentVersion == nil
		or not validTermination
		or ((terminationReason == "Victory") ~= (record.outcome == "Victory"))
		or (record.outcome == "Victory" and modeKind ~= "Finite")
		or (modeKind == "Endless" and (record.outcome ~= "Defeat" or terminationReason == "Victory"))
	then
		return failure("INVALID_FIELD", "result")
	end
	for _, entry in entries do
		if entry.wavesCompleted > highestCompletedWave then
			return failure("INVALID_FIELD", "result.entries")
		end
	end
	common.modeKind = modeKind
	common.highestCompletedWave = highestCompletedWave
	common.elapsedSeconds = elapsedSeconds
	common.seed = seed
	common.contentVersion = contentVersion
	common.terminationReason = terminationReason
	return Result.ok(table.freeze(common) :: MatchResult)
end

return table.freeze(MatchResultContract)
