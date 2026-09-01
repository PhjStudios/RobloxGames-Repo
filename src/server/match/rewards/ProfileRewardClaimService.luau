--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local RewardProtocol = require(ReplicatedStorage.Shared.match.RewardProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local RewardPolicy = require(script.Parent.RewardPolicy)

local MAX_PROFILE_GOLD = 1_000_000_000_000
local MAX_CLAIMED_RESULTS = 128
local INTENT_TIMEOUT_SECONDS = 2_700

export type ProfileOwner = {
	getState: (self: ProfileOwner, userId: number) -> unknown,
	read: (self: ProfileOwner, userId: number) -> unknown,
	transact: (
		self: ProfileOwner,
		userId: number,
		transactionId: string,
		expectedRevision: number,
		kind: string,
		fingerprint: string,
		callback: (profile: any) -> unknown
	) -> unknown,
	flush: (self: ProfileOwner, userId: number) -> unknown,
}

export type Ledger = {
	getForUser: (self: Ledger, resultId: unknown, userId: unknown) -> unknown,
	acknowledge: (self: Ledger, resultId: unknown, userId: unknown, state: unknown, award: unknown?) -> unknown,
	expireIntent: (self: Ledger, resultId: unknown, userId: unknown, nowValue: unknown) -> unknown,
	compact: (self: Ledger, resultId: unknown) -> unknown,
}

export type ClaimError = {
	code: string,
	operation: string,
}

type ServiceData = {
	profile: ProfileOwner,
	ledger: Ledger,
	now: () -> number,
	busy: { [number]: boolean },
}

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local ProfileRewardClaimService = {}

local function failure<T>(code: string, operation: string): Result.Failure<ClaimError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_REWARD_CLAIM][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validDependencies(profile: unknown, ledger: unknown): boolean
	return type(profile) == "table"
		and type((profile :: any).getState) == "function"
		and type((profile :: any).read) == "function"
		and type((profile :: any).transact) == "function"
		and type((profile :: any).flush) == "function"
		and type(ledger) == "table"
		and type((ledger :: any).getForUser) == "function"
		and type((ledger :: any).acknowledge) == "function"
		and type((ledger :: any).expireIntent) == "function"
		and type((ledger :: any).compact) == "function"
end

local function pairKey(mapId: string, difficultyId: string): string
	return `{mapId}|{difficultyId}`
end

local function transactionId(resultId: string): string?
	local body = string.sub(resultId, 8)
	local value = `transaction:r-{body}`
	return if #value <= 50 then value else nil
end

local function findClaim(profile: any, resultId: string): any?
	if type(profile) ~= "table" or type(profile.claimedResults) ~= "table" then
		return nil
	end
	for _, claim in profile.claimedResults do
		if claim.resultId == resultId then
			return claim
		end
	end
	return nil
end

local function pendingIndex(profile: any, resultId: string): number?
	if type(profile) ~= "table" or type(profile.pendingResults) ~= "table" then
		return nil
	end
	for index, pending in profile.pendingResults do
		if pending.resultId == resultId then
			return index
		end
	end
	return nil
end

local function view(
	status: RewardProtocol.ClaimStatus,
	resultId: string,
	reason: string,
	entry: any,
	persistentGoldAwarded: number?,
	firstClearBonus: number?
): RewardProtocol.RewardView
	local candidate = {
		resultId = resultId,
		status = status,
		persistentGoldAwarded = persistentGoldAwarded or 0,
		firstClearBonus = firstClearBonus or 0,
		battleCashEarned = entry.battleCashEarned,
		battleCashSpent = entry.battleCashSpent,
		reason = reason,
	}
	local validated = RewardProtocol.validateRewardView(candidate)
	if not validated.ok then
		error("[ATD_REWARD_CLAIM][code=INVALID_VIEW]", 0)
	end
	return validated.value
end

local function resultOk(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function fallbackEntry(): any
	return { battleCashEarned = 0, battleCashSpent = 0 }
end

local function clearPending(data: ServiceData, userId: number, resultId: string, profile: any, prefix: string): boolean
	if pendingIndex(profile, resultId) == nil then
		-- A prior transaction may have removed the in-memory marker while its
		-- durable flush failed. Always retry the save before considering cleanup
		-- complete, even when the current session no longer lists the marker.
		local flushedCalled, flushed = pcall(data.profile.flush, data.profile, userId)
		return flushedCalled and resultOk(flushed)
	end
	local body = string.sub(resultId, 8)
	local transactionIdValue = `transaction:{prefix}-{body}`
	if #transactionIdValue > 50 then
		return false
	end
	local called, transacted = pcall(
		data.profile.transact,
		data.profile,
		userId,
		transactionIdValue,
		profile.revision,
		"ClearPendingMatchResult",
		`clear-pending|{resultId}|{userId}`,
		function(draft: any)
			local index = pendingIndex(draft, resultId)
			if index ~= nil then
				table.remove(draft.pendingResults, index)
			end
			return Result.ok({
				resultCode = "PENDING_RESULT_CLEARED",
				goldBalance = draft.gold,
				unitIds = {},
				towerIds = {},
				newFlags = {},
				pityCount = 0,
			})
		end
	)
	if not called or not resultOk(transacted) then
		return false
	end
	local flushedCalled, flushed = pcall(data.profile.flush, data.profile, userId)
	return flushedCalled and resultOk(flushed)
end

local function clearPendingFresh(data: ServiceData, userId: number, resultId: string, prefix: string): boolean
	local readCalled, readValue = pcall(data.profile.read, data.profile, userId)
	if not readCalled or not resultOk(readValue) then
		return false
	end
	return clearPending(data, userId, resultId, (readValue :: any).value, prefix)
end

local function clearAndCompact(data: ServiceData, userId: number, resultId: string, prefix: string): boolean
	-- Compact before removing the final durable retry trigger. If other roster
	-- claims are still Pending, this member may clear its marker and the eventual
	-- last claimant will compact. Any store outage keeps this marker for retry.
	local compactCalled, compacted = pcall(data.ledger.compact, data.ledger, resultId)
	if not compactCalled or type(compacted) ~= "table" then
		return false
	end
	local compactResult = compacted :: any
	if compactResult.ok ~= true then
		if type(compactResult.error) ~= "table" or compactResult.error.code ~= "PENDING_CLAIMS" then
			return false
		end
	end
	return clearPendingFresh(data, userId, resultId, prefix)
end

local function evictableClaimIndex(profile: any): number?
	for index, claim in profile.claimedResults do
		-- A pending-result reference protects a profile commit whose ledger
		-- acknowledgement may not have completed yet. Never evict that replay
		-- barrier while compacting the bounded receipt history.
		if pendingIndex(profile, claim.resultId) == nil then
			return index
		end
	end
	return nil
end

function Methods.claim(
	self: Service,
	userIdValue: unknown,
	resultIdValue: unknown
): Result.Result<RewardProtocol.RewardView, ClaimError>
	local data = requireData(self)
	if
		type(userIdValue) ~= "number"
		or not Validation.isSafeInteger(userIdValue)
		or userIdValue < 1
		or type(resultIdValue) ~= "string"
	then
		return failure("INVALID_ARGUMENT", "claim")
	end
	local userId = userIdValue :: number
	local resultId = resultIdValue :: string
	if data.busy[userId] then
		return failure("BUSY", "claim")
	end
	data.busy[userId] = true
	local function finish(value: Result.Result<RewardProtocol.RewardView, ClaimError>)
		data.busy[userId] = nil
		return value
	end

	local function readLedger(): any?
		local called, value = pcall(data.ledger.getForUser, data.ledger, resultId, userId)
		return if called and resultOk(value) then (value :: any).value else nil
	end
	local claimRecord = readLedger()
	if claimRecord == nil then
		return finish(Result.ok(view("Pending", resultId, "LEDGER_UNAVAILABLE", fallbackEntry(), nil, nil)))
	end
	if claimRecord.phase == "Intent" then
		local nowCalled, nowValue = pcall(data.now)
		if not nowCalled or type(nowValue) ~= "number" or not Validation.isSafeInteger(nowValue) or nowValue < 0 then
			return finish(Result.ok(view("Pending", resultId, "CLOCK_UNAVAILABLE", fallbackEntry(), nil, nil)))
		end
		if
			type(claimRecord.intentHeartbeatAt) ~= "number"
			or nowValue < claimRecord.intentHeartbeatAt + INTENT_TIMEOUT_SECONDS
		then
			return finish(Result.ok(view("Pending", resultId, "RESULT_NOT_FINAL", fallbackEntry(), nil, nil)))
		end
		-- A durable pre-travel intent is never deleted merely because the final
		-- result is not visible yet. Only an expired authoritative Match lease can
		-- turn it into a durable zero-award failure tombstone.
		pcall(data.ledger.expireIntent, data.ledger, resultId, userId, nowValue)
		claimRecord = readLedger()
		if claimRecord == nil or claimRecord.phase == "Intent" then
			return finish(Result.ok(view("Pending", resultId, "RESULT_NOT_FINAL", fallbackEntry(), nil, nil)))
		end
	end
	local entry = claimRecord.entry or fallbackEntry()
	if claimRecord.phase == "Compacted" then
		-- Another roster member may have completed the final ledger compaction
		-- after this profile's terminal acknowledgement but before this profile's
		-- pending inbox marker was durably removed. The compacted tombstone is the
		-- replay barrier, so the stale marker can be retried safely on every load.
		if data.profile:getState(userId) == "Ready" then
			clearPendingFresh(data, userId, resultId, "c")
		end
		if claimRecord.state == "Claimed" and type(claimRecord.award) == "table" then
			return finish(
				Result.ok(
					view(
						"Granted",
						resultId,
						"DURABLY_CLAIMED",
						entry,
						claimRecord.award.persistentGoldAwarded,
						claimRecord.award.firstClearBonus
					)
				)
			)
		elseif claimRecord.state == "Ineligible" then
			return finish(Result.ok(view("Ineligible", resultId, "INELIGIBLE", entry, nil, nil)))
		elseif claimRecord.state == "Failed" then
			return finish(
				Result.ok(
					view("Failed", resultId, claimRecord.failureReason or "RESULT_PIPELINE_FAILED", entry, nil, nil)
				)
			)
		end
		return finish(Result.ok(view("Failed", resultId, "CLAIM_RECEIPT_MISSING", entry, nil, nil)))
	elseif claimRecord.phase == "Failed" then
		if claimRecord.state == "Pending" then
			local ackCalled, ack = pcall(data.ledger.acknowledge, data.ledger, resultId, userId, "Failed", nil)
			if not ackCalled or not resultOk(ack) then
				return finish(Result.ok(view("Pending", resultId, "LEDGER_ACK_PENDING", entry, nil, nil)))
			end
		end
		if data.profile:getState(userId) == "Ready" then
			clearAndCompact(data, userId, resultId, "e")
		end
		return finish(
			Result.ok(view("Failed", resultId, claimRecord.failureReason or "RESULT_PIPELINE_FAILED", entry, nil, nil))
		)
	end
	local matchResult = claimRecord.result
	if claimRecord.phase ~= "Final" or type(matchResult) ~= "table" or claimRecord.entry == nil then
		return finish(Result.ok(view("Pending", resultId, "RESULT_NOT_FINAL", entry, nil, nil)))
	end
	-- The durable server-owned ticket/result is the immutable configuration
	-- authority for a historical claim. Do not strand an earned reward merely
	-- because a later Lobby deployment removes that content pair.
	if claimRecord.state == "Claimed" then
		local award = claimRecord.award
		if type(award) ~= "table" then
			return finish(Result.ok(view("Failed", resultId, "CLAIM_RECEIPT_MISSING", entry, nil, nil)))
		end
		if data.profile:getState(userId) == "Ready" then
			-- Best-effort finalization cleanup. The ledger tombstone and durable
			-- profile receipt already make the award exactly once even if this
			-- cleanup has to be retried on a later Lobby load.
			clearAndCompact(data, userId, resultId, "f")
		end
		return finish(
			Result.ok(
				view("Granted", resultId, "DURABLY_CLAIMED", entry, award.persistentGoldAwarded, award.firstClearBonus)
			)
		)
	elseif claimRecord.state == "Ineligible" then
		if data.profile:getState(userId) == "Ready" then
			-- The durable ledger state is the zero-award replay barrier. Pending
			-- profile cleanup may safely retry after an ambiguous prior response.
			clearAndCompact(data, userId, resultId, "i")
		end
		return finish(Result.ok(view("Ineligible", resultId, "INELIGIBLE", entry, nil, nil)))
	end

	if data.profile:getState(userId) ~= "Ready" then
		return finish(Result.ok(view("Pending", resultId, "PROFILE_NOT_READY", entry, nil, nil)))
	end
	local readCalled, readValue = pcall(data.profile.read, data.profile, userId)
	if not readCalled or not resultOk(readValue) then
		return finish(Result.ok(view("Pending", resultId, "PROFILE_UNAVAILABLE", entry, nil, nil)))
	end
	local profile = (readValue :: any).value
	local existingClaim = findClaim(profile, resultId)
	if existingClaim ~= nil then
		local flushedCalled, flushed = pcall(data.profile.flush, data.profile, userId)
		if not flushedCalled or not resultOk(flushed) then
			return finish(Result.ok(view("Pending", resultId, "PROFILE_SAVE_PENDING", entry, nil, nil)))
		end
		local acknowledgedCalled, acknowledged =
			pcall(data.ledger.acknowledge, data.ledger, resultId, userId, "Claimed", {
				persistentGoldAwarded = existingClaim.persistentGoldAwarded,
				firstClearBonus = existingClaim.firstClearBonus,
			})
		if not acknowledgedCalled or not resultOk(acknowledged) then
			return finish(Result.ok(view("Pending", resultId, "LEDGER_ACK_PENDING", entry, nil, nil)))
		end
		clearAndCompact(data, userId, resultId, "f")
		return finish(
			Result.ok(
				view(
					"Granted",
					resultId,
					"DURABLY_CLAIMED",
					entry,
					existingClaim.persistentGoldAwarded,
					existingClaim.firstClearBonus
				)
			)
		)
	end

	local clearKey = pairKey(matchResult.mapId, matchResult.difficultyId)
	local initialPolicy = RewardPolicy.evaluate({
		rewardingMatch = matchResult.rewardingMatch,
		authenticatedParticipant = entry.authenticatedParticipant,
		spectator = entry.spectator,
		submittedReady = entry.submittedReady,
		placements = entry.placements,
		wavesCompleted = entry.wavesCompleted,
		connectedAtResults = entry.connectedAtResults,
		outcome = matchResult.outcome,
	}, profile.firstClears[clearKey] == nil)
	if not initialPolicy.ok then
		return finish(Result.ok(view("Failed", resultId, "INVALID_EVIDENCE", entry, nil, nil)))
	elseif not initialPolicy.value.eligible then
		local ackCalled, ack = pcall(data.ledger.acknowledge, data.ledger, resultId, userId, "Ineligible", nil)
		if not ackCalled or not resultOk(ack) then
			return finish(Result.ok(view("Pending", resultId, "LEDGER_ACK_PENDING", entry, nil, nil)))
		end
		-- A crash may leave this marker behind, but can no longer erase the only
		-- retry path before the ledger reaches its terminal Ineligible state.
		clearAndCompact(data, userId, resultId, "i")
		return finish(Result.ok(view("Ineligible", resultId, initialPolicy.value.reason, entry, nil, nil)))
	end

	local txId = transactionId(resultId)
	if txId == nil then
		return finish(Result.ok(view("Failed", resultId, "INVALID_RESULT_ID", entry, nil, nil)))
	end
	local nowCalled, nowValue = pcall(data.now)
	if not nowCalled or type(nowValue) ~= "number" or not Validation.isSafeInteger(nowValue) or nowValue < 0 then
		return finish(Result.ok(view("Pending", resultId, "CLOCK_UNAVAILABLE", entry, nil, nil)))
	end
	local awarded: RewardPolicy.Breakdown? = nil
	local transactedCalled, transacted = pcall(
		data.profile.transact,
		data.profile,
		userId,
		txId,
		profile.revision,
		"MatchReward",
		`reward|{resultId}|{userId}`,
		function(draft: any)
			local duplicate = findClaim(draft, resultId)
			if duplicate ~= nil then
				return Result.ok({
					resultCode = "REWARD_ALREADY_CLAIMED",
					goldBalance = draft.gold,
					unitIds = {},
					towerIds = {},
					newFlags = {},
					pityCount = 0,
				})
			end
			local policy = RewardPolicy.evaluate({
				rewardingMatch = matchResult.rewardingMatch,
				authenticatedParticipant = entry.authenticatedParticipant,
				spectator = entry.spectator,
				submittedReady = entry.submittedReady,
				placements = entry.placements,
				wavesCompleted = entry.wavesCompleted,
				connectedAtResults = entry.connectedAtResults,
				outcome = matchResult.outcome,
			}, draft.firstClears[clearKey] == nil)
			if not policy.ok or not policy.value.eligible or draft.gold > MAX_PROFILE_GOLD - policy.value.totalGold then
				return Result.err("REWARD_REJECTED")
			end
			awarded = policy.value
			draft.gold += policy.value.totalGold
			if policy.value.firstClearGold > 0 then
				draft.firstClears[clearKey] = {
					mapId = matchResult.mapId,
					difficultyId = matchResult.difficultyId,
					clearedAt = nowValue,
				}
			end
			if #draft.claimedResults >= MAX_CLAIMED_RESULTS then
				local removeIndex = evictableClaimIndex(draft)
				if removeIndex == nil then
					return Result.err("CLAIM_HISTORY_PROTECTED")
				end
				table.remove(draft.claimedResults, removeIndex)
			end
			table.insert(draft.claimedResults, {
				resultId = resultId,
				persistentGoldAwarded = policy.value.totalGold,
				firstClearBonus = policy.value.firstClearGold,
				claimedAt = nowValue,
			})
			draft.stats.matchesPlayed += 1
			if matchResult.outcome == "Victory" then
				draft.stats.victories += 1
			else
				draft.stats.defeats += 1
			end
			return Result.ok({
				resultCode = "REWARD_GRANTED",
				goldBalance = draft.gold,
				unitIds = {},
				towerIds = {},
				newFlags = {},
				pityCount = 0,
			})
		end
	)
	if not transactedCalled or not resultOk(transacted) then
		return finish(Result.ok(view("Pending", resultId, "PROFILE_CLAIM_PENDING", entry, nil, nil)))
	end
	if awarded == nil then
		local reread = data.profile:read(userId)
		local rereadProfile = if resultOk(reread) then (reread :: any).value else nil
		local replayed = findClaim(rereadProfile, resultId)
		if replayed ~= nil then
			awarded = table.freeze({
				eligible = true,
				reason = "ELIGIBLE",
				participationGold = 0,
				victoryGold = replayed.persistentGoldAwarded - replayed.firstClearBonus,
				firstClearGold = replayed.firstClearBonus,
				totalGold = replayed.persistentGoldAwarded,
			})
		end
	end
	if awarded == nil then
		return finish(Result.ok(view("Failed", resultId, "CLAIM_RECEIPT_MISSING", entry, nil, nil)))
	end
	local flushedCalled, flushed = pcall(data.profile.flush, data.profile, userId)
	if not flushedCalled or not resultOk(flushed) then
		return finish(Result.ok(view("Pending", resultId, "PROFILE_SAVE_PENDING", entry, nil, nil)))
	end
	local acknowledgedCalled, acknowledged = pcall(data.ledger.acknowledge, data.ledger, resultId, userId, "Claimed", {
		persistentGoldAwarded = awarded.totalGold,
		firstClearBonus = awarded.firstClearGold,
	})
	if not acknowledgedCalled or not resultOk(acknowledged) then
		return finish(Result.ok(view("Pending", resultId, "LEDGER_ACK_PENDING", entry, nil, nil)))
	end
	clearAndCompact(data, userId, resultId, "f")
	return finish(
		Result.ok(view("Granted", resultId, "DURABLY_CLAIMED", entry, awarded.totalGold, awarded.firstClearGold))
	)
end

function ProfileRewardClaimService.new(
	profileValue: unknown,
	ledgerValue: unknown,
	configurationValue: unknown,
	nowValue: unknown
): Result.Result<Service, ClaimError>
	if
		not validDependencies(profileValue, ledgerValue)
		or not ConfigurationValidator.isValidatedConfiguration(configurationValue)
		or type(nowValue) ~= "function"
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		profile = profileValue :: ProfileOwner,
		ledger = ledgerValue :: Ledger,
		now = nowValue :: () -> number,
		busy = {},
	}
	return Result.ok(service)
end

return table.freeze(ProfileRewardClaimService)
