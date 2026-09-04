--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local ConfigurationFixtures = require(script.Parent.Parent.Fixtures.ConfigurationFixtures)
local IsolatedProfileStore = require(script.Parent.Parent.Fixtures.IsolatedProfileStore)
local IsolatedResultLedgerStore = require(script.Parent.Parent.Fixtures.IsolatedResultLedgerStore)
local ProfileService = require(script.Parent.Parent.ProductionServerProfile.ProfileService)
local PendingResultService = require(script.Parent.Parent.ProductionServerProfile.PendingResultService)
local ProfileRewardClaimService = require(script.Parent.Parent.ProductionServerMatchRewards.ProfileRewardClaimService)
local ResultLedgerService = require(script.Parent.Parent.ProductionServerMatchRewards.ResultLedgerService)
local ConfigurationValidator = require(game:GetService("ReplicatedStorage").Shared.config.ConfigurationValidator)
local Result = require(game:GetService("ReplicatedStorage").Shared.util.Result)

local USER_ID = 701
local SECOND_USER_ID = 702

local function success(assertions, result)
	if not result.ok then
		error(`expected operation to succeed: {result.error.code or "UNKNOWN"}`, 0)
	end
	assertions.isTrue(result.ok)
	return result.value
end

local function resultRecord(resultId: string, outcome: string?, overrides: { [string]: any }?): any
	local entry = {
		userId = USER_ID,
		authenticatedParticipant = true,
		spectator = false,
		submittedReady = true,
		placements = 1,
		wavesCompleted = 2,
		connectedAtResults = true,
		battleCashEarned = 600,
		battleCashSpent = 400,
	}
	for key, value in overrides or {} do
		entry[key] = value
	end
	return {
		version = 1,
		resultId = resultId,
		matchId = `match:{string.sub(resultId, 8, 15)}`,
		ticketId = `ticket:{string.sub(resultId, 8, 15)}`,
		mapId = "map:garden",
		difficultyId = "difficulty:normal",
		outcome = outcome or "Victory",
		createdAt = 1_000,
		rewardingMatch = true,
		entries = { entry },
	}
end

local function twoMemberResult(resultId: string): any
	local value = resultRecord(resultId)
	local second = table.clone(value.entries[1])
	second.userId = SECOND_USER_ID
	value.entries = { value.entries[1], second }
	return value
end

local function endlessResultRecord(resultId: string, waveNumber: number): any
	local value = resultRecord(resultId, "Defeat", { wavesCompleted = waveNumber })
	value.version = 2
	value.mapId = "map:backyard-garden-v1"
	value.difficultyId = "difficulty:endless-v1"
	value.modeKind = "Endless"
	value.highestCompletedWave = waveNumber
	value.elapsedSeconds = 3_600
	value.seed = 77_031
	value.contentVersion = 1
	value.terminationReason = "PlayerEnded"
	return value
end

local function stack(assertions, initialNow: number?)
	local configuration = success(assertions, ConfigurationValidator.validate(ConfigurationFixtures.validSources()))
	local profileStore = IsolatedProfileStore.new()
	local now = initialNow or 2_000
	local profile = success(
		assertions,
		ProfileService.new(configuration.towers, profileStore, {
			sessionId = "reward-claim-session",
			clock = function()
				return now
			end,
			wait = function(_seconds) end,
		})
	)
	success(assertions, profile:load(USER_ID))
	local resultStore = IsolatedResultLedgerStore.new()
	local ledger = success(
		assertions,
		ResultLedgerService.new(resultStore, function()
			return now
		end)
	)
	local claims = success(
		assertions,
		ProfileRewardClaimService.new(profile, ledger, configuration, function()
			return now
		end)
	)
	local pendingResults = success(assertions, PendingResultService.new(profile))
	return {
		configuration = configuration,
		profileStore = profileStore,
		profile = profile,
		resultStore = resultStore,
		ledger = ledger,
		claims = claims,
		pendingResults = pendingResults,
		advance = function(seconds)
			now += seconds
		end,
	}
end

return TestHarness.suite("durable exactly-once profile reward claims", {
	TestHarness.case(
		"grants 500 first victory Gold once and returns the durable receipt on retry",
		function(assertions)
			local context = stack(assertions)
			local resultId = "result:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
			success(assertions, context.pendingResults:reserve({ USER_ID }, resultId, 1_000))
			success(assertions, context.ledger:create(resultRecord(resultId)))
			local first = success(assertions, context.claims:claim(USER_ID, resultId))
			assertions.equal(first.status, "Granted")
			assertions.equal(first.persistentGoldAwarded, 500)
			assertions.equal(first.firstClearBonus, 250)
			assertions.equal(first.battleCashEarned, 600)
			local afterFirst = success(assertions, context.profile:read(USER_ID))
			assertions.equal(afterFirst.gold, 2_500)
			assertions.equal(#afterFirst.pendingResults, 0)
			assertions.equal(#afterFirst.claimedResults, 1)
			assertions.isNotNil(afterFirst.firstClears["map:garden|difficulty:normal"])

			local retry = success(assertions, context.claims:claim(USER_ID, resultId))
			assertions.equal(retry.status, "Granted")
			assertions.equal(retry.persistentGoldAwarded, 500)
			assertions.equal(success(assertions, context.profile:read(USER_ID)).gold, 2_500)
		end
	),
	TestHarness.case("awards repeat victory 250 and eligible defeat 50 without another clear", function(assertions)
		local context = stack(assertions)
		local firstId = "result:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
		local repeatId = "result:cccccccc-cccc-cccc-cccc-cccccccccccc"
		local defeatId = "result:dddddddd-dddd-dddd-dddd-dddddddddddd"
		context.ledger:create(resultRecord(firstId))
		context.claims:claim(USER_ID, firstId)
		context.ledger:create(resultRecord(repeatId))
		local repeatReward = success(assertions, context.claims:claim(USER_ID, repeatId))
		assertions.equal(repeatReward.persistentGoldAwarded, 250)
		assertions.equal(repeatReward.firstClearBonus, 0)
		context.ledger:create(resultRecord(defeatId, "Defeat"))
		local defeatReward = success(assertions, context.claims:claim(USER_ID, defeatId))
		assertions.equal(defeatReward.persistentGoldAwarded, 50)
		local profile = success(assertions, context.profile:read(USER_ID))
		assertions.equal(profile.gold, 2_800)
		assertions.equal(profile.stats.matchesPlayed, 3)
		assertions.equal(profile.stats.victories, 2)
		assertions.equal(profile.stats.defeats, 1)
	end),
	TestHarness.case("grants the capped Endless award exactly once through the existing receipt", function(assertions)
		local context = stack(assertions)
		local resultId = "result:99999999-endless-capped"
		success(assertions, context.pendingResults:reserve({ USER_ID }, resultId, 1_000))
		success(assertions, context.ledger:create(endlessResultRecord(resultId, 10_000)))
		local first = success(assertions, context.claims:claim(USER_ID, resultId))
		assertions.equal(first.status, "Granted")
		assertions.equal(first.persistentGoldAwarded, 300)
		assertions.equal(first.firstClearBonus, 0)
		assertions.equal(success(assertions, context.profile:read(USER_ID)).gold, 2_300)

		local retry = success(assertions, context.claims:claim(USER_ID, resultId))
		assertions.equal(retry.status, "Granted")
		assertions.equal(retry.persistentGoldAwarded, 300)
		local finalProfile = success(assertions, context.profile:read(USER_ID))
		assertions.equal(finalProfile.gold, 2_300)
		assertions.equal(finalProfile.stats.matchesPlayed, 1)
		assertions.equal(finalProfile.stats.defeats, 1)
	end),
	TestHarness.case("keeps a claim pending across a profile-save failure and never grants twice", function(assertions)
		local context = stack(assertions)
		local resultId = "result:eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
		success(assertions, context.pendingResults:reserve({ USER_ID }, resultId, 1_000))
		context.ledger:create(resultRecord(resultId))
		context.profileStore:failNext(3)
		local pending = success(assertions, context.claims:claim(USER_ID, resultId))
		assertions.equal(pending.status, "Pending")
		assertions.equal(pending.persistentGoldAwarded, 0)
		assertions.equal(context.ledger:getForUser(resultId, USER_ID).value.state, "Pending")
		local granted = success(assertions, context.claims:claim(USER_ID, resultId))
		assertions.equal(granted.status, "Granted")
		assertions.equal(granted.persistentGoldAwarded, 500)
		assertions.equal(success(assertions, context.profile:read(USER_ID)).gold, 2_500)
	end),
	TestHarness.case("recovers a crash after profile commit but before ledger acknowledgement", function(assertions)
		local context = stack(assertions)
		local resultId = "result:ffffffff-ffff-ffff-ffff-ffffffffffff"
		success(assertions, context.pendingResults:reserve({ USER_ID }, resultId, 1_000))
		context.ledger:create(resultRecord(resultId))
		local rejectAck = true
		local interruptedLedger = {
			getForUser = function(_self, ...)
				return context.ledger:getForUser(...)
			end,
			acknowledge = function(_self, ...)
				if rejectAck then
					rejectAck = false
					error("simulated crash before acknowledgement", 0)
				end
				return context.ledger:acknowledge(...)
			end,
			expireIntent = function(_self, ...)
				return context.ledger:expireIntent(...)
			end,
			compact = function(_self, ...)
				return context.ledger:compact(...)
			end,
		}
		local interruptedClaims = success(
			assertions,
			ProfileRewardClaimService.new(context.profile, interruptedLedger, context.configuration, function()
				return 2_000
			end)
		)
		local pending = success(assertions, interruptedClaims:claim(USER_ID, resultId))
		assertions.equal(pending.status, "Pending")
		local committedProfile = success(assertions, context.profile:read(USER_ID))
		assertions.equal(committedProfile.gold, 2_500)
		assertions.equal(#committedProfile.pendingResults, 1)
		assertions.equal(#committedProfile.claimedResults, 1)
		assertions.equal(context.ledger:getForUser(resultId, USER_ID).value.state, "Pending")

		local recovered = success(assertions, context.claims:claim(USER_ID, resultId))
		assertions.equal(recovered.status, "Granted")
		assertions.equal(recovered.persistentGoldAwarded, 500)
		local recoveredProfile = success(assertions, context.profile:read(USER_ID))
		assertions.equal(recoveredProfile.gold, 2_500)
		assertions.equal(#recoveredProfile.pendingResults, 0)
	end),
	TestHarness.case("protects an unacknowledged commit when bounded claim history rolls over", function(assertions)
		local context = stack(assertions)
		local protectedResultId = "result:protected-commit"
		success(assertions, context.pendingResults:reserve({ USER_ID }, protectedResultId, 1_000))
		success(assertions, context.ledger:create(resultRecord(protectedResultId)))
		local interruptedLedger = {
			getForUser = function(_self, ...)
				return context.ledger:getForUser(...)
			end,
			acknowledge = function()
				error("simulated acknowledgement outage", 0)
			end,
			expireIntent = function(_self, ...)
				return context.ledger:expireIntent(...)
			end,
			compact = function(_self, ...)
				return context.ledger:compact(...)
			end,
		}
		local interruptedClaims = success(
			assertions,
			ProfileRewardClaimService.new(context.profile, interruptedLedger, context.configuration, function()
				return 2_000
			end)
		)
		assertions.equal(success(assertions, interruptedClaims:claim(USER_ID, protectedResultId)).status, "Pending")

		local beforeSeed = success(assertions, context.profile:read(USER_ID))
		success(
			assertions,
			context.profile:transact(
				USER_ID,
				"transaction:seed-claim-bound",
				beforeSeed.revision,
				"TestClaimHistoryBound",
				"test-only-claim-history-bound",
				function(draft)
					for index = 1, 127 do
						table.insert(draft.claimedResults, {
							resultId = `result:seed-{index}`,
							persistentGoldAwarded = 50,
							firstClearBonus = 0,
							claimedAt = 2_000,
						})
					end
					return Result.ok({
						resultCode = "TEST_HISTORY_SEEDED",
						goldBalance = draft.gold,
						unitIds = {},
						towerIds = {},
						newFlags = {},
						pityCount = 0,
					})
				end
			)
		)

		local rolloverResultId = "result:rollover-safe"
		success(assertions, context.ledger:create(resultRecord(rolloverResultId)))
		assertions.equal(success(assertions, context.claims:claim(USER_ID, rolloverResultId)).status, "Granted")
		local rolled = success(assertions, context.profile:read(USER_ID))
		assertions.equal(#rolled.claimedResults, 128)
		local protectedFound = false
		for _, receipt in rolled.claimedResults do
			protectedFound = protectedFound or receipt.resultId == protectedResultId
		end
		assertions.isTrue(protectedFound)
		assertions.equal(#rolled.pendingResults, 1)

		local goldBeforeRecovery = rolled.gold
		assertions.equal(success(assertions, context.claims:claim(USER_ID, protectedResultId)).status, "Granted")
		local recovered = success(assertions, context.profile:read(USER_ID))
		assertions.equal(recovered.gold, goldBeforeRecovery)
		assertions.equal(#recovered.pendingResults, 0)
	end),
	TestHarness.case("durably marks spectators and immediate leavers ineligible with zero Gold", function(assertions)
		for index, overrides in
			{
				{ spectator = true, authenticatedParticipant = false },
				{ wavesCompleted = 1, connectedAtResults = false },
			}
		do
			local context = stack(assertions)
			local resultId =
				`result:{index}{index}{index}{index}{index}{index}{index}{index}-1111-1111-1111-111111111111`
			success(assertions, context.pendingResults:reserve({ USER_ID }, resultId, 1_000))
			context.ledger:create(resultRecord(resultId, "Defeat", overrides))
			local claim = success(assertions, context.claims:claim(USER_ID, resultId))
			assertions.equal(claim.status, "Ineligible")
			assertions.equal(claim.persistentGoldAwarded, 0)
			local profile = success(assertions, context.profile:read(USER_ID))
			assertions.equal(profile.gold, 2_000)
			assertions.equal(#profile.pendingResults, 0)
			assertions.equal(context.ledger:getForUser(resultId, USER_ID).value.state, "Ineligible")
		end
	end),
	TestHarness.case("fails an orphaned pre-travel intent durably only after route expiry", function(assertions)
		local context = stack(assertions, 4_000)
		local function must(value, label)
			if not value.ok then
				error(`expected {label}: {value.error.code}`, 0)
			end
			return value.value
		end
		local resultId = "result:orphaned-match-intent"
		local result = resultRecord(resultId)
		must(context.pendingResults:reserve({ USER_ID }, resultId, 1_301), "pending reservation")
		local intent = context.ledger:createIntent({
			version = 1,
			resultId = resultId,
			matchId = result.matchId,
			ticketId = result.ticketId,
			expectedUserIds = { USER_ID },
			createdAt = 1_301,
		})
		if not intent.ok then
			error(`expected durable intent: {intent.error.code}`, 0)
		end
		local activeResult = context.claims:claim(USER_ID, resultId)
		if not activeResult.ok then
			error(`expected active intent claim: {activeResult.error.code}`, 0)
		end
		local active = activeResult.value
		assertions.equal(active.status, "Pending")
		assertions.equal(#must(context.profile:read(USER_ID), "active profile read").pendingResults, 1)
		context.advance(1)
		local failedResult = context.claims:claim(USER_ID, resultId)
		if not failedResult.ok then
			error(`expected expired intent claim: {failedResult.error.code}`, 0)
		end
		local failed = failedResult.value
		assertions.equal(failed.status, "Failed")
		assertions.equal(failed.persistentGoldAwarded, 0)
		assertions.equal(failed.reason, "MATCH_RESULT_TIMEOUT")
		local failedProfileResult = context.profile:read(USER_ID)
		assertions.equal(#must(failedProfileResult, "failed profile read").pendingResults, 0)
		local goldProfileResult = context.profile:read(USER_ID)
		assertions.equal(must(goldProfileResult, "gold profile read").gold, 2_000)
		local tombstone = context.ledger:getForUser(resultId, USER_ID)
		assertions.equal(tombstone.value.phase, "Compacted")
		assertions.equal(tombstone.value.state, "Failed")
		assertions.isFalse(context.ledger:create(result).ok)
	end),
	TestHarness.case(
		"retains and later clears an ineligible inbox across ambiguous ledger acknowledgement",
		function(assertions)
			local context = stack(assertions)
			local resultId = "result:ineligible-ack-crash"
			success(assertions, context.pendingResults:reserve({ USER_ID }, resultId, 1_000))
			success(
				assertions,
				context.ledger:create(resultRecord(resultId, "Defeat", {
					wavesCompleted = 1,
					connectedAtResults = false,
				}))
			)
			local ambiguousLedger = {
				getForUser = function(_self, ...)
					return context.ledger:getForUser(...)
				end,
				acknowledge = function(_self, ...)
					context.ledger:acknowledge(...)
					error("simulated response loss after durable acknowledgement", 0)
				end,
				expireIntent = function(_self, ...)
					return context.ledger:expireIntent(...)
				end,
				compact = function(_self, ...)
					return context.ledger:compact(...)
				end,
			}
			local interruptedClaims = success(
				assertions,
				ProfileRewardClaimService.new(context.profile, ambiguousLedger, context.configuration, function()
					return 2_000
				end)
			)
			local interrupted = success(assertions, interruptedClaims:claim(USER_ID, resultId))
			assertions.equal(interrupted.status, "Pending")
			assertions.equal(#success(assertions, context.profile:read(USER_ID)).pendingResults, 1)
			assertions.equal(context.ledger:getForUser(resultId, USER_ID).value.state, "Ineligible")

			local recovered = success(assertions, context.claims:claim(USER_ID, resultId))
			assertions.equal(recovered.status, "Ineligible")
			assertions.equal(recovered.persistentGoldAwarded, 0)
			assertions.equal(#success(assertions, context.profile:read(USER_ID)).pendingResults, 0)
			assertions.equal(success(assertions, context.profile:read(USER_ID)).gold, 2_000)
		end
	),
	TestHarness.case("keeps the inbox retry trigger when final ledger compaction is unavailable", function(assertions)
		local context = stack(assertions)
		local resultId = "result:compactretry-trigger"
		local reserved = context.pendingResults:reserve({ USER_ID }, resultId, 1_000)
		success(assertions, reserved)
		local created = context.ledger:create(resultRecord(resultId))
		success(assertions, created)
		local failCompact = true
		local interruptedLedger = {
			getForUser = function(_self, ...)
				return context.ledger:getForUser(...)
			end,
			acknowledge = function(_self, ...)
				return context.ledger:acknowledge(...)
			end,
			expireIntent = function(_self, ...)
				return context.ledger:expireIntent(...)
			end,
			compact = function(_self, ...)
				if failCompact then
					failCompact = false
					return Result.err({ code = "STORE_UNAVAILABLE" })
				end
				return context.ledger:compact(...)
			end,
		}
		local interruptedClaims = success(
			assertions,
			ProfileRewardClaimService.new(context.profile, interruptedLedger, context.configuration, function()
				return 2_000
			end)
		)
		local firstClaim = interruptedClaims:claim(USER_ID, resultId)
		assertions.equal(success(assertions, firstClaim).status, "Granted")
		assertions.equal(#success(assertions, context.profile:read(USER_ID)).pendingResults, 1)
		local secondClaim = context.claims:claim(USER_ID, resultId)
		assertions.equal(success(assertions, secondClaim).status, "Granted")
		assertions.equal(#success(assertions, context.profile:read(USER_ID)).pendingResults, 0)
		assertions.equal(context.ledger:getForUser(resultId, USER_ID).value.phase, "Compacted")
	end),
	TestHarness.case("retries the durable marker flush after in-memory cleanup already succeeded", function(assertions)
		local context = stack(assertions)
		local resultId = "result:markerflush-retry"
		success(assertions, context.pendingResults:reserve({ USER_ID }, resultId, 1_000))
		success(assertions, context.ledger:create(resultRecord(resultId)))
		local clearStarted = false
		local failClearFlush = true
		local clearFlushAttempts = 0
		local interruptedProfile = {
			getState = function(_self, ...)
				return context.profile:getState(...)
			end,
			read = function(_self, ...)
				return context.profile:read(...)
			end,
			transact = function(_self, userId, transactionId, expectedRevision, kind, fingerprint, callback)
				if kind == "ClearPendingMatchResult" then
					clearStarted = true
				end
				return context.profile:transact(userId, transactionId, expectedRevision, kind, fingerprint, callback)
			end,
			flush = function(_self, ...)
				if clearStarted then
					clearFlushAttempts += 1
					if failClearFlush then
						failClearFlush = false
						return Result.err({ code = "STORE_FAILED" })
					end
				end
				return context.profile:flush(...)
			end,
		}
		local interruptedClaims = success(
			assertions,
			ProfileRewardClaimService.new(interruptedProfile, context.ledger, context.configuration, function()
				return 2_000
			end)
		)
		assertions.equal(success(assertions, interruptedClaims:claim(USER_ID, resultId)).status, "Granted")
		assertions.equal(context.ledger:getForUser(resultId, USER_ID).value.phase, "Compacted")
		assertions.equal(success(assertions, interruptedClaims:claim(USER_ID, resultId)).status, "Granted")
		assertions.equal(clearFlushAttempts, 2)
		success(assertions, context.profile:release(USER_ID))
		success(assertions, context.profile:load(USER_ID))
		assertions.equal(#success(assertions, context.profile:read(USER_ID)).pendingResults, 0)
	end),
	TestHarness.case("clears a stale roster marker after another member compacts the tombstone", function(assertions)
		local context = stack(assertions)
		success(assertions, context.profile:load(SECOND_USER_ID))
		local resultId = "result:roster-compaction-race"
		success(assertions, context.pendingResults:reserve({ USER_ID, SECOND_USER_ID }, resultId, 1_000))
		success(assertions, context.ledger:create(twoMemberResult(resultId)))
		local blockedProfile = {
			getState = function(_self, ...)
				return context.profile:getState(...)
			end,
			read = function(_self, ...)
				return context.profile:read(...)
			end,
			transact = function(_self, userId, transactionId, expectedRevision, kind, fingerprint, callback)
				if userId == USER_ID and kind == "ClearPendingMatchResult" then
					return Result.err({ code = "STORE_FAILED" })
				end
				return context.profile:transact(userId, transactionId, expectedRevision, kind, fingerprint, callback)
			end,
			flush = function(_self, ...)
				return context.profile:flush(...)
			end,
		}
		local blockedClaims = success(
			assertions,
			ProfileRewardClaimService.new(blockedProfile, context.ledger, context.configuration, function()
				return 2_000
			end)
		)
		assertions.equal(success(assertions, blockedClaims:claim(USER_ID, resultId)).status, "Granted")
		assertions.equal(#success(assertions, context.profile:read(USER_ID)).pendingResults, 1)
		assertions.equal(success(assertions, context.claims:claim(SECOND_USER_ID, resultId)).status, "Granted")
		assertions.equal(context.ledger:getForUser(resultId, USER_ID).value.phase, "Compacted")
		assertions.equal(success(assertions, context.claims:claim(USER_ID, resultId)).status, "Granted")
		assertions.equal(#success(assertions, context.profile:read(USER_ID)).pendingResults, 0)
		assertions.equal(success(assertions, context.profile:read(USER_ID)).gold, 2_500)
	end),
})
