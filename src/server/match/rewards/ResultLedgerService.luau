--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local MatchResultContract = require(script.Parent.MatchResultContract)

export type ClaimState = "Pending" | "Claimed" | "Ineligible" | "Failed"
export type LedgerPhase = "Intent" | "Final" | "Failed" | "Compacted"

export type Adapter = {
	read: (self: Adapter, key: string) -> unknown,
	update: (self: Adapter, key: string, transform: (unknown) -> unknown) -> unknown,
}

export type AwardRecord = {
	persistentGoldAwarded: number,
	firstClearBonus: number,
}

export type ResultIntent = {
	version: number,
	resultId: string,
	matchId: string,
	ticketId: string,
	expectedUserIds: { number },
	createdAt: number,
}

export type ClaimRecord = {
	phase: LedgerPhase,
	result: MatchResultContract.MatchResult?,
	entry: MatchResultContract.Entry?,
	state: ClaimState,
	award: AwardRecord?,
	intentCreatedAt: number,
	intentHeartbeatAt: number,
	failureReason: string?,
}

export type LedgerError = { code: string, operation: string }

type StoredRecord = {
	version: number,
	phase: LedgerPhase,
	result: MatchResultContract.MatchResult?,
	resultId: string,
	matchId: string,
	ticketId: string,
	expectedUserIds: { number },
	intentCreatedAt: number,
	intentHeartbeatAt: number,
	states: { [string]: ClaimState },
	acknowledgedAt: { [string]: number },
	awards: { [string]: AwardRecord },
	failureReason: string?,
	compacted: boolean,
}

type ServiceData = { adapter: Adapter, now: () -> number, busy: { [string]: boolean } }

local Methods = {}
Methods.__index = Methods
export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local INTENT_TIMEOUT_SECONDS = 2_700
local MAX_ROSTER = 4
local MAX_RESULT_ID_LENGTH = 43
local DATASTORE_KEY_PREFIX = "mr1/"
local ResultLedgerService = { INTENT_TIMEOUT_SECONDS = INTENT_TIMEOUT_SECONDS }

local function failure<T>(code: string, operation: string): Result.Failure<LedgerError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_RESULT_LEDGER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validAdapter(value: unknown): boolean
	return type(value) == "table"
		and type((value :: any).read) == "function"
		and type((value :: any).update) == "function"
end

local function key(resultId: string): string
	return `{DATASTORE_KEY_PREFIX}{resultId}`
end

local function validTime(value: unknown): number?
	return if type(value) == "number" and Validation.isSafeInteger(value) and value >= 0 then value else nil
end

local function validToken(value: unknown, prefix: string, maximum: number): string?
	if type(value) ~= "string" or #value < #prefix + 2 or #value > maximum then
		return nil
	end
	if string.sub(value :: string, 1, #prefix + 1) ~= `{prefix}:` then
		return nil
	end
	for index = #prefix + 2, #value do
		local byte = string.byte(value :: string, index)
		if
			byte == nil
			or not (
				(byte >= string.byte("a") and byte <= string.byte("z"))
				or (byte >= string.byte("0") and byte <= string.byte("9"))
				or byte == string.byte("-")
			)
		then
			return nil
		end
	end
	return value :: string
end

local function validRoster(value: unknown): { number }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or #value < 1 or #value > MAX_ROSTER then
		return nil
	end
	local output: { number } = table.create(#value)
	local seen: { [number]: boolean } = {}
	for index, rawUserId in value :: { unknown } do
		if
			type(rawUserId) ~= "number"
			or not Validation.isSafeInteger(rawUserId :: number)
			or rawUserId <= 0
			or seen[rawUserId :: number]
		then
			return nil
		end
		seen[rawUserId :: number] = true
		output[index] = rawUserId :: number
	end
	return output
end

local function sameRoster(left: { number }, right: { number }): boolean
	if #left ~= #right then
		return false
	end
	for index, userId in left do
		if right[index] ~= userId then
			return false
		end
	end
	return true
end

local function resultRoster(matchResult: MatchResultContract.MatchResult): { number }
	local output: { number } = table.create(#matchResult.entries)
	for index, entry in matchResult.entries do
		output[index] = entry.userId
	end
	return output
end

local function sameResult(left: MatchResultContract.MatchResult, right: MatchResultContract.MatchResult): boolean
	if
		left.version ~= right.version
		or left.resultId ~= right.resultId
		or left.matchId ~= right.matchId
		or left.ticketId ~= right.ticketId
		or left.mapId ~= right.mapId
		or left.difficultyId ~= right.difficultyId
		or left.outcome ~= right.outcome
		or left.createdAt ~= right.createdAt
		or left.rewardingMatch ~= right.rewardingMatch
		or #left.entries ~= #right.entries
	then
		return false
	end
	for index, entry in left.entries do
		local candidate = right.entries[index]
		for field, value in entry do
			if candidate[field] ~= value then
				return false
			end
		end
	end
	return true
end

local function callRead(data: ServiceData, resultId: string): (boolean, unknown)
	return pcall(data.adapter.read, data.adapter, key(resultId))
end

local function callUpdate(data: ServiceData, resultId: string, transform: (unknown) -> unknown): (boolean, unknown)
	if data.busy[resultId] then
		return false, nil
	end
	data.busy[resultId] = true
	local called, value = pcall(data.adapter.update, data.adapter, key(resultId), transform)
	data.busy[resultId] = nil
	return called, value
end

local function validateStored(value: unknown): (StoredRecord?, MatchResultContract.MatchResult?)
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil, nil
	end
	local stored = value :: any
	local expected = validRoster(stored.expectedUserIds)
	local intentCreatedAt = validTime(stored.intentCreatedAt)
	local intentHeartbeatAt = validTime(stored.intentHeartbeatAt)
	if
		stored.version ~= 1
		or (stored.phase ~= "Intent" and stored.phase ~= "Final" and stored.phase ~= "Failed" and stored.phase ~= "Compacted")
		or validToken(stored.resultId, "result", MAX_RESULT_ID_LENGTH) == nil
		or validToken(stored.matchId, "match", 100) == nil
		or validToken(stored.ticketId, "ticket", 100) == nil
		or expected == nil
		or intentCreatedAt == nil
		or intentHeartbeatAt == nil
		or intentHeartbeatAt < intentCreatedAt
		or type(stored.states) ~= "table"
		or type(stored.acknowledgedAt) ~= "table"
		or type(stored.awards) ~= "table"
		or getmetatable(stored.states) ~= nil
		or getmetatable(stored.acknowledgedAt) ~= nil
		or getmetatable(stored.awards) ~= nil
		or type(stored.compacted) ~= "boolean"
		or stored.compacted ~= (stored.phase == "Compacted")
	then
		return nil, nil
	end
	local allowed: { [string]: boolean } = {}
	for _, userId in expected do
		local userKey = tostring(userId)
		allowed[userKey] = true
		local state = stored.states[userKey]
		if state ~= "Pending" and state ~= "Claimed" and state ~= "Ineligible" and state ~= "Failed" then
			return nil, nil
		end
		if stored.phase == "Intent" and state ~= "Pending" then
			return nil, nil
		elseif stored.phase == "Final" and state == "Failed" then
			return nil, nil
		elseif stored.phase == "Failed" and state ~= "Pending" and state ~= "Failed" then
			return nil, nil
		elseif stored.phase == "Compacted" and state == "Pending" then
			return nil, nil
		end
		local acknowledgedAt = stored.acknowledgedAt[userKey]
		if state == "Pending" then
			if acknowledgedAt ~= nil or stored.awards[userKey] ~= nil then
				return nil, nil
			end
		elseif validTime(acknowledgedAt) == nil or acknowledgedAt < intentCreatedAt then
			return nil, nil
		end
		local award = stored.awards[userKey]
		if state == "Claimed" then
			if type(award) ~= "table" or getmetatable(award) ~= nil then
				return nil, nil
			end
			local fieldCount = 0
			for field in award do
				if field ~= "persistentGoldAwarded" and field ~= "firstClearBonus" then
					return nil, nil
				end
				fieldCount += 1
			end
			if
				fieldCount ~= 2
				or type(award.persistentGoldAwarded) ~= "number"
				or not Validation.isSafeInteger(award.persistentGoldAwarded)
				or award.persistentGoldAwarded < 0
				or type(award.firstClearBonus) ~= "number"
				or not Validation.isSafeInteger(award.firstClearBonus)
				or award.firstClearBonus < 0
				or award.firstClearBonus > award.persistentGoldAwarded
			then
				return nil, nil
			end
		elseif award ~= nil then
			return nil, nil
		end
	end
	for userKey in stored.states do
		if allowed[userKey] ~= true then
			return nil, nil
		end
	end
	for userKey in stored.acknowledgedAt do
		if allowed[userKey] ~= true then
			return nil, nil
		end
	end
	for userKey in stored.awards do
		if allowed[userKey] ~= true then
			return nil, nil
		end
	end
	local reason = stored.failureReason
	if
		(stored.phase == "Failed" or (stored.phase == "Compacted" and reason ~= nil))
		and (type(reason) ~= "string" or #reason < 1 or #reason > 100)
	then
		return nil, nil
	elseif stored.phase ~= "Failed" and stored.phase ~= "Compacted" and reason ~= nil then
		return nil, nil
	end
	if stored.phase == "Intent" or stored.phase == "Failed" or stored.phase == "Compacted" then
		if stored.result ~= nil then
			return nil, nil
		end
		return stored :: StoredRecord, nil
	end
	local validated = MatchResultContract.validate(stored.result)
	if
		not validated.ok
		or validated.value.resultId ~= stored.resultId
		or validated.value.matchId ~= stored.matchId
		or validated.value.ticketId ~= stored.ticketId
		or not sameRoster(expected, resultRoster(validated.value))
	then
		return nil, nil
	end
	return stored :: StoredRecord, validated.value
end

local function validateIntent(value: unknown): ResultIntent?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local raw = value :: any
	local resultId = validToken(raw.resultId, "result", MAX_RESULT_ID_LENGTH)
	local matchId = validToken(raw.matchId, "match", 100)
	local ticketId = validToken(raw.ticketId, "ticket", 100)
	local expected = validRoster(raw.expectedUserIds)
	local createdAt = validTime(raw.createdAt)
	if
		raw.version ~= 1
		or resultId == nil
		or matchId == nil
		or ticketId == nil
		or expected == nil
		or createdAt == nil
	then
		return nil
	end
	return table.freeze({
		version = 1,
		resultId = resultId,
		matchId = matchId,
		ticketId = ticketId,
		expectedUserIds = table.freeze(expected),
		createdAt = createdAt,
	})
end

local function isZeroAwardFailureTerminal(stored: StoredRecord): boolean
	if stored.failureReason == nil or next(stored.awards) ~= nil then
		return false
	end
	if stored.phase == "Failed" then
		return true
	elseif stored.phase ~= "Compacted" then
		return false
	end
	for _, userId in stored.expectedUserIds do
		if stored.states[tostring(userId)] ~= "Failed" then
			return false
		end
	end
	return true
end

local function baseRecord(intent: ResultIntent): StoredRecord
	local states: { [string]: ClaimState } = {}
	for _, userId in intent.expectedUserIds do
		states[tostring(userId)] = "Pending"
	end
	return {
		version = 1,
		phase = "Intent",
		result = nil,
		resultId = intent.resultId,
		matchId = intent.matchId,
		ticketId = intent.ticketId,
		expectedUserIds = table.clone(intent.expectedUserIds),
		intentCreatedAt = intent.createdAt,
		intentHeartbeatAt = intent.createdAt,
		states = states,
		acknowledgedAt = {},
		awards = {},
		failureReason = nil,
		compacted = false,
	}
end

local function exactIntent(stored: StoredRecord?, intent: ResultIntent): boolean
	return stored ~= nil
		and stored.phase == "Intent"
		and stored.resultId == intent.resultId
		and stored.matchId == intent.matchId
		and stored.ticketId == intent.ticketId
		and stored.intentCreatedAt == intent.createdAt
		and sameRoster(stored.expectedUserIds, intent.expectedUserIds)
end

local function readStored(data: ServiceData, resultId: string): (StoredRecord?, MatchResultContract.MatchResult?)
	local called, value = callRead(data, resultId)
	return if called then validateStored(value) else nil, nil
end

function Methods.createIntent(self: Service, intentValue: unknown): Result.Result<boolean, LedgerError>
	local data = requireData(self)
	local intent = validateIntent(intentValue)
	if intent == nil then
		return failure("INVALID_INTENT", "createIntent")
	end
	local created = false
	local conflict = false
	local called, updated = callUpdate(data, intent.resultId, function(existing)
		if existing == nil then
			created = true
			return baseRecord(intent)
		end
		local stored = validateStored(existing)
		if not exactIntent(stored, intent) then
			conflict = true
		end
		return existing
	end)
	if not called or updated == nil then
		local stored = readStored(data, intent.resultId)
		if exactIntent(stored, intent) then
			return Result.ok(created)
		end
		return failure("STORE_UNAVAILABLE", "createIntent")
	elseif conflict then
		return failure("RESULT_CONFLICT", "createIntent")
	end
	return Result.ok(created)
end

function Methods.create(self: Service, resultValue: unknown): Result.Result<boolean, LedgerError>
	local data = requireData(self)
	local validated = MatchResultContract.validate(resultValue)
	if not validated.ok then
		return failure("INVALID_RESULT", "create")
	end
	local matchResult = validated.value
	local roster = resultRoster(matchResult)
	local created = false
	local conflict = false
	local called, updated = callUpdate(data, matchResult.resultId, function(existing)
		if existing == nil then
			local record = baseRecord({
				version = 1,
				resultId = matchResult.resultId,
				matchId = matchResult.matchId,
				ticketId = matchResult.ticketId,
				expectedUserIds = roster,
				createdAt = matchResult.createdAt,
			})
			record.phase = "Final"
			record.result = matchResult
			created = true
			return record
		end
		local stored, existingResult = validateStored(existing)
		if
			stored ~= nil
			and stored.phase == "Intent"
			and stored.matchId == matchResult.matchId
			and stored.ticketId == matchResult.ticketId
			and sameRoster(stored.expectedUserIds, roster)
		then
			local copy = table.clone(stored) :: any
			copy.phase = "Final"
			copy.result = matchResult
			created = true
			return copy
		elseif
			stored ~= nil
			and stored.phase == "Final"
			and existingResult ~= nil
			and sameResult(existingResult, matchResult)
		then
			return existing
		end
		conflict = true
		return existing
	end)
	if not called or updated == nil then
		local stored, existingResult = readStored(data, matchResult.resultId)
		if
			stored ~= nil
			and stored.phase == "Final"
			and existingResult ~= nil
			and sameResult(existingResult, matchResult)
		then
			return Result.ok(created)
		end
		return failure("STORE_UNAVAILABLE", "create")
	elseif conflict then
		return failure("RESULT_CONFLICT", "create")
	end
	return Result.ok(created)
end

function Methods.renewIntent(
	self: Service,
	resultIdValue: unknown,
	matchIdValue: unknown,
	ticketIdValue: unknown,
	nowValue: unknown
): Result.Result<boolean, LedgerError>
	local data = requireData(self)
	local resultId = validToken(resultIdValue, "result", MAX_RESULT_ID_LENGTH)
	local matchId = validToken(matchIdValue, "match", 100)
	local ticketId = validToken(ticketIdValue, "ticket", 100)
	local currentTime = validTime(nowValue)
	if resultId == nil or matchId == nil or ticketId == nil or currentTime == nil then
		return failure("INVALID_ARGUMENT", "renewIntent")
	end
	local changed = false
	local missing = false
	local conflict = false
	local called, updated = callUpdate(data, resultId, function(existing)
		local stored = validateStored(existing)
		if stored == nil then
			missing = true
			return existing
		end
		if stored.matchId ~= matchId or stored.ticketId ~= ticketId then
			conflict = true
			return existing
		end
		if stored.phase == "Final" then
			return existing
		elseif stored.phase ~= "Intent" or currentTime < stored.intentHeartbeatAt then
			conflict = true
			return existing
		elseif currentTime == stored.intentHeartbeatAt then
			return existing
		end
		local copy = table.clone(stored) :: any
		copy.intentHeartbeatAt = currentTime
		changed = true
		return copy
	end)
	if not called or updated == nil then
		local stored = readStored(data, resultId)
		if
			stored ~= nil
			and stored.matchId == matchId
			and stored.ticketId == ticketId
			and (stored.phase == "Final" or (stored.phase == "Intent" and stored.intentHeartbeatAt >= currentTime))
		then
			return Result.ok(changed)
		end
		return failure("STORE_UNAVAILABLE", "renewIntent")
	elseif missing then
		return failure("NOT_FOUND", "renewIntent")
	elseif conflict then
		return failure("RESULT_CONFLICT", "renewIntent")
	end
	return Result.ok(changed)
end

function Methods.cancelIntent(
	self: Service,
	resultIdValue: unknown,
	matchIdValue: unknown,
	ticketIdValue: unknown,
	reasonValue: unknown,
	nowValue: unknown
): Result.Result<boolean, LedgerError>
	local data = requireData(self)
	local resultId = validToken(resultIdValue, "result", MAX_RESULT_ID_LENGTH)
	local matchId = validToken(matchIdValue, "match", 100)
	local ticketId = validToken(ticketIdValue, "ticket", 100)
	local currentTime = validTime(nowValue)
	if
		resultId == nil
		or matchId == nil
		or ticketId == nil
		or type(reasonValue) ~= "string"
		or #reasonValue < 1
		or #reasonValue > 100
		or currentTime == nil
	then
		return failure("INVALID_ARGUMENT", "cancelIntent")
	end
	local reason = reasonValue :: string
	local changed = false
	local missing = false
	local conflict = false
	local called, updated = callUpdate(data, resultId, function(existing)
		local stored = validateStored(existing)
		if stored == nil then
			missing = true
			return existing
		end
		if stored.matchId ~= matchId or stored.ticketId ~= ticketId or currentTime < stored.intentCreatedAt then
			conflict = true
			return existing
		end
		if isZeroAwardFailureTerminal(stored) then
			return existing
		elseif stored.phase ~= "Intent" then
			conflict = true
			return existing
		end
		local states: { [string]: ClaimState } = {}
		local acknowledgedAt: { [string]: number } = {}
		for _, userId in stored.expectedUserIds do
			local userKey = tostring(userId)
			states[userKey] = "Failed"
			acknowledgedAt[userKey] = currentTime
		end
		local copy = table.clone(stored) :: any
		copy.phase = "Compacted"
		copy.states = states
		copy.acknowledgedAt = acknowledgedAt
		copy.awards = {}
		copy.failureReason = reason
		copy.compacted = true
		changed = true
		return copy
	end)
	if not called or updated == nil then
		local stored = readStored(data, resultId)
		if
			stored ~= nil
			and isZeroAwardFailureTerminal(stored)
			and stored.matchId == matchId
			and stored.ticketId == ticketId
		then
			return Result.ok(changed)
		end
		return failure("STORE_UNAVAILABLE", "cancelIntent")
	elseif missing then
		return failure("NOT_FOUND", "cancelIntent")
	elseif conflict then
		return failure("RESULT_CONFLICT", "cancelIntent")
	end
	return Result.ok(changed)
end

local function markFailed(
	data: ServiceData,
	resultId: string,
	matchId: string?,
	ticketId: string?,
	reason: string,
	nowValue: number,
	requireExpired: boolean,
	userId: number?
): Result.Result<boolean, LedgerError>
	local changed = false
	local missing = false
	local conflict = false
	local tooEarly = false
	local called, updated = callUpdate(data, resultId, function(existing)
		local stored = validateStored(existing)
		if stored == nil then
			missing = true
			return existing
		end
		if matchId ~= nil and (stored.matchId ~= matchId or stored.ticketId ~= ticketId) then
			conflict = true
			return existing
		end
		if userId ~= nil and table.find(stored.expectedUserIds, userId) == nil then
			conflict = true
			return existing
		end
		if isZeroAwardFailureTerminal(stored) then
			return existing
		elseif stored.phase ~= "Intent" then
			conflict = true
			return existing
		end
		if requireExpired and nowValue < stored.intentHeartbeatAt + INTENT_TIMEOUT_SECONDS then
			tooEarly = true
			return existing
		end
		local copy = table.clone(stored) :: any
		copy.phase = "Failed"
		copy.failureReason = reason
		changed = true
		return copy
	end)
	local operation = if requireExpired then "expireIntent" else "markFailed"
	if not called or updated == nil then
		local stored = readStored(data, resultId)
		if
			stored ~= nil
			and isZeroAwardFailureTerminal(stored)
			and (matchId == nil or (stored.matchId == matchId and stored.ticketId == ticketId))
			and (userId == nil or table.find(stored.expectedUserIds, userId) ~= nil)
		then
			return Result.ok(changed)
		end
		return failure("STORE_UNAVAILABLE", operation)
	elseif missing then
		return failure("NOT_FOUND", operation)
	elseif tooEarly then
		return failure("INTENT_ACTIVE", operation)
	elseif conflict then
		return failure("RESULT_CONFLICT", operation)
	end
	return Result.ok(changed)
end

function Methods.markFailed(
	self: Service,
	resultIdValue: unknown,
	matchIdValue: unknown,
	ticketIdValue: unknown,
	reasonValue: unknown,
	nowValue: unknown
): Result.Result<boolean, LedgerError>
	local resultId = validToken(resultIdValue, "result", MAX_RESULT_ID_LENGTH)
	local matchId = validToken(matchIdValue, "match", 100)
	local ticketId = validToken(ticketIdValue, "ticket", 100)
	local now = validTime(nowValue)
	if
		resultId == nil
		or matchId == nil
		or ticketId == nil
		or type(reasonValue) ~= "string"
		or #reasonValue < 1
		or #reasonValue > 100
		or now == nil
	then
		return failure("INVALID_ARGUMENT", "markFailed")
	end
	return markFailed(requireData(self), resultId, matchId, ticketId, reasonValue :: string, now, false, nil)
end

function Methods.expireIntent(
	self: Service,
	resultIdValue: unknown,
	userIdValue: unknown,
	nowValue: unknown
): Result.Result<boolean, LedgerError>
	local resultId = validToken(resultIdValue, "result", MAX_RESULT_ID_LENGTH)
	local now = validTime(nowValue)
	if
		resultId == nil
		or type(userIdValue) ~= "number"
		or not Validation.isSafeInteger(userIdValue :: number)
		or userIdValue <= 0
		or now == nil
	then
		return failure("INVALID_ARGUMENT", "expireIntent")
	end
	return markFailed(requireData(self), resultId, nil, nil, "MATCH_RESULT_TIMEOUT", now, true, userIdValue :: number)
end

function Methods.getForUser(
	self: Service,
	resultIdValue: unknown,
	userIdValue: unknown
): Result.Result<ClaimRecord, LedgerError>
	local data = requireData(self)
	local resultId = validToken(resultIdValue, "result", MAX_RESULT_ID_LENGTH)
	if
		resultId == nil
		or type(userIdValue) ~= "number"
		or not Validation.isSafeInteger(userIdValue)
		or userIdValue < 1
	then
		return failure("INVALID_ARGUMENT", "getForUser")
	end
	local called, value = callRead(data, resultId)
	if not called then
		return failure("STORE_UNAVAILABLE", "getForUser")
	end
	local stored, matchResult = validateStored(value)
	if stored == nil then
		return failure("NOT_FOUND", "getForUser")
	end
	local userKey = tostring(userIdValue)
	local state = stored.states[userKey]
	if state == nil or table.find(stored.expectedUserIds, userIdValue) == nil then
		return failure("USER_NOT_EXPECTED", "getForUser")
	end
	local entry: MatchResultContract.Entry? = nil
	if matchResult ~= nil then
		for _, candidate in matchResult.entries do
			if candidate.userId == userIdValue then
				entry = candidate
				break
			end
		end
		if entry == nil then
			return failure("USER_NOT_EXPECTED", "getForUser")
		end
	end
	return Result.ok(table.freeze({
		phase = stored.phase,
		result = matchResult,
		entry = entry,
		state = state,
		award = stored.awards[userKey],
		intentCreatedAt = stored.intentCreatedAt,
		intentHeartbeatAt = stored.intentHeartbeatAt,
		failureReason = stored.failureReason,
	}))
end

function Methods.acknowledge(
	self: Service,
	resultIdValue: unknown,
	userIdValue: unknown,
	stateValue: unknown,
	awardValue: unknown?
): Result.Result<boolean, LedgerError>
	local data = requireData(self)
	local resultId = validToken(resultIdValue, "result", MAX_RESULT_ID_LENGTH)
	if
		resultId == nil
		or type(userIdValue) ~= "number"
		or not Validation.isSafeInteger(userIdValue)
		or userIdValue < 1
		or (stateValue ~= "Claimed" and stateValue ~= "Ineligible" and stateValue ~= "Failed")
	then
		return failure("INVALID_ARGUMENT", "acknowledge")
	end
	local award: AwardRecord? = nil
	if stateValue == "Claimed" then
		if type(awardValue) ~= "table" or getmetatable(awardValue :: any) ~= nil then
			return failure("INVALID_ARGUMENT", "acknowledge")
		end
		local rawAward = awardValue :: any
		if
			type(rawAward.persistentGoldAwarded) ~= "number"
			or not Validation.isSafeInteger(rawAward.persistentGoldAwarded)
			or rawAward.persistentGoldAwarded < 0
			or type(rawAward.firstClearBonus) ~= "number"
			or not Validation.isSafeInteger(rawAward.firstClearBonus)
			or rawAward.firstClearBonus < 0
			or rawAward.firstClearBonus > rawAward.persistentGoldAwarded
		then
			return failure("INVALID_ARGUMENT", "acknowledge")
		end
		award = table.freeze({
			persistentGoldAwarded = rawAward.persistentGoldAwarded,
			firstClearBonus = rawAward.firstClearBonus,
		})
	elseif awardValue ~= nil then
		return failure("INVALID_ARGUMENT", "acknowledge")
	end
	local nowCalled, nowValue = pcall(data.now)
	local now = if nowCalled then validTime(nowValue) else nil
	if now == nil then
		return failure("CLOCK_UNAVAILABLE", "acknowledge")
	end
	local changed = false
	local missing = false
	local conflict = false
	local userKey = tostring(userIdValue)
	local called, updated = callUpdate(data, resultId, function(existing)
		local stored = validateStored(existing)
		if stored == nil or stored.phase == "Compacted" or stored.phase == "Intent" then
			missing = true
			return existing
		end
		if (stateValue == "Failed") ~= (stored.phase == "Failed") then
			conflict = true
			return existing
		end
		local current = stored.states[userKey]
		if current == stateValue then
			return existing
		elseif current ~= "Pending" then
			conflict = true
			return existing
		end
		local copy = table.clone(stored) :: any
		copy.states = table.clone(stored.states)
		copy.acknowledgedAt = table.clone(stored.acknowledgedAt)
		copy.awards = table.clone(stored.awards)
		copy.states[userKey] = stateValue
		copy.acknowledgedAt[userKey] = now
		if award ~= nil then
			copy.awards[userKey] = award
		end
		changed = true
		return copy
	end)
	if not called or updated == nil then
		return failure("STORE_UNAVAILABLE", "acknowledge")
	elseif missing then
		return failure("NOT_FOUND", "acknowledge")
	elseif conflict then
		return failure("STATE_CONFLICT", "acknowledge")
	end
	return Result.ok(changed)
end

function Methods.compact(self: Service, resultIdValue: unknown): Result.Result<boolean, LedgerError>
	local data = requireData(self)
	local resultId = validToken(resultIdValue, "result", MAX_RESULT_ID_LENGTH)
	if resultId == nil then
		return failure("INVALID_ARGUMENT", "compact")
	end
	local changed = false
	local incomplete = false
	local called, updated = callUpdate(data, resultId, function(existing)
		local stored = validateStored(existing)
		if stored == nil then
			return existing
		elseif stored.phase == "Compacted" then
			return existing
		elseif stored.phase == "Intent" then
			incomplete = true
			return existing
		end
		for _, state in stored.states do
			if state == "Pending" then
				incomplete = true
				return existing
			end
		end
		changed = true
		return {
			version = 1,
			phase = "Compacted",
			result = nil,
			resultId = stored.resultId,
			matchId = stored.matchId,
			ticketId = stored.ticketId,
			expectedUserIds = table.clone(stored.expectedUserIds),
			intentCreatedAt = stored.intentCreatedAt,
			intentHeartbeatAt = stored.intentHeartbeatAt,
			states = table.clone(stored.states),
			acknowledgedAt = table.clone(stored.acknowledgedAt),
			awards = table.clone(stored.awards),
			failureReason = stored.failureReason,
			compacted = true,
		}
	end)
	if not called or updated == nil then
		return failure("STORE_UNAVAILABLE", "compact")
	elseif incomplete then
		return failure("PENDING_CLAIMS", "compact")
	end
	return Result.ok(changed)
end

function ResultLedgerService.new(adapterValue: unknown, nowValue: unknown): Result.Result<Service, LedgerError>
	if not validAdapter(adapterValue) or type(nowValue) ~= "function" then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = { adapter = adapterValue :: Adapter, now = nowValue :: () -> number, busy = {} }
	return Result.ok(service)
end

return table.freeze(ResultLedgerService)
