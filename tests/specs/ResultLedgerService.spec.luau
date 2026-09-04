--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local IsolatedResultLedgerStore = require(script.Parent.Parent.Fixtures.IsolatedResultLedgerStore)
local ResultLedgerService = require(script.Parent.Parent.ProductionServerMatchRewards.ResultLedgerService)

local MAXIMUM_RESULT_ID = "result:22222222-2222-2222-2222-222222222222"

local function matchResult(resultId: string?): any
	return {
		version = 1,
		resultId = resultId or MAXIMUM_RESULT_ID,
		matchId = "match:ledger-one",
		ticketId = "ticket:ledger-one",
		mapId = "map:phase07-graybox",
		difficultyId = "difficulty:local",
		outcome = "Defeat",
		createdAt = 100,
		rewardingMatch = true,
		entries = {
			{
				userId = 10,
				authenticatedParticipant = true,
				spectator = false,
				submittedReady = true,
				placements = 1,
				wavesCompleted = 2,
				connectedAtResults = false,
				battleCashEarned = 300,
				battleCashSpent = 200,
			},
		},
	}
end

local function currentEndlessResult(): any
	local result = matchResult("result:endless-ledger")
	result.version = 2
	result.mapId = "map:backyard-garden-v1"
	result.difficultyId = "difficulty:endless-v1"
	result.modeKind = "Endless"
	result.highestCompletedWave = 10
	result.elapsedSeconds = 312
	result.seed = 44_321
	result.contentVersion = 1
	result.terminationReason = "BaseDefeated"
	return result
end

local function service(assertions): (any, any)
	local store = IsolatedResultLedgerStore.new()
	local created = ResultLedgerService.new(store, function()
		return 500
	end)
	assertions.isTrue(created.ok)
	return created.value, store
end

return TestHarness.suite("durable idempotent result ledger", {
	TestHarness.case("uses Roblox-valid keys for a maximum-length generated result ID", function(assertions)
		assertions.equal(#MAXIMUM_RESULT_ID, 43)
		local ledger, store = service(assertions)
		local result = matchResult(MAXIMUM_RESULT_ID)
		assertions.isTrue(ledger:createIntent({
			version = 1,
			resultId = result.resultId,
			matchId = result.matchId,
			ticketId = result.ticketId,
			expectedUserIds = { 10 },
			createdAt = result.createdAt,
		}).value)
		assertions.isTrue(ledger:create(result).value)
		assertions.isTrue(
			ledger:acknowledge(result.resultId, 10, "Claimed", { persistentGoldAwarded = 50, firstClearBonus = 0 }).value
		)
		assertions.equal(ledger:getForUser(result.resultId, 10).value.state, "Claimed")
		assertions.isTrue(ledger:compact(result.resultId).value)
		assertions.equal(store:getMetrics().keys, 1)
	end),
	TestHarness.case("enforces the Roblox 50-character DataStore key boundary", function(assertions)
		local store = IsolatedResultLedgerStore.new()
		local accepted = pcall(function()
			store:update(string.rep("a", 50), function()
				return { valid = true }
			end)
		end)
		local rejected = pcall(function()
			store:read(string.rep("a", 51))
		end)
		assertions.isTrue(accepted)
		assertions.isFalse(rejected)
	end),
	TestHarness.case("rejects overlong result IDs before accessing the store", function(assertions)
		local ledger, store = service(assertions)
		local overlongResultId = `result:{string.rep("a", 37)}`
		assertions.equal(#overlongResultId, 44)
		assertions.equal(ledger:getForUser(overlongResultId, 10).error.code, "INVALID_ARGUMENT")
		assertions.equal(ledger:acknowledge(overlongResultId, 10, "Ineligible", nil).error.code, "INVALID_ARGUMENT")
		assertions.equal(ledger:compact(overlongResultId).error.code, "INVALID_ARGUMENT")
		local metrics = store:getMetrics()
		assertions.equal(metrics.reads, 0)
		assertions.equal(metrics.updates, 0)
	end),
	TestHarness.case("creates once and exposes only the roster-specific pending entry", function(assertions)
		local ledger = service(assertions)
		assertions.isTrue(ledger:create(matchResult()).value)
		assertions.isFalse(ledger:create(matchResult()).value)
		local claim = ledger:getForUser(matchResult().resultId, 10)
		assertions.isTrue(claim.ok)
		assertions.equal(claim.value.state, "Pending")
		assertions.isFalse(ledger:getForUser(matchResult().resultId, 11).ok)
	end),
	TestHarness.case("persists v2 Endless metadata idempotently and rejects conflicts", function(assertions)
		local ledger = service(assertions)
		local result = currentEndlessResult()
		assertions.isTrue(ledger:create(result).value)
		assertions.isFalse(ledger:create(result).value)
		local pending = ledger:getForUser(result.resultId, 10)
		assertions.isTrue(pending.ok)
		assertions.equal(pending.value.result.version, 2)
		assertions.equal(pending.value.result.modeKind, "Endless")
		assertions.equal(pending.value.result.highestCompletedWave, 10)
		assertions.equal(pending.value.result.seed, 44_321)

		local conflicting = currentEndlessResult()
		conflicting.seed = 44_322
		assertions.isFalse(ledger:create(conflicting).ok)
		assertions.equal(ledger:getForUser(result.resultId, 10).value.result.seed, 44_321)
	end),
	TestHarness.case("acknowledges an award idempotently and rejects conflicting terminals", function(assertions)
		local ledger = service(assertions)
		ledger:create(matchResult())
		local award = { persistentGoldAwarded = 50, firstClearBonus = 0 }
		assertions.isTrue(ledger:acknowledge(matchResult().resultId, 10, "Claimed", award).value)
		assertions.isFalse(ledger:acknowledge(matchResult().resultId, 10, "Claimed", award).value)
		local claim = ledger:getForUser(matchResult().resultId, 10).value
		assertions.equal(claim.state, "Claimed")
		assertions.equal(claim.award.persistentGoldAwarded, 50)
		assertions.isFalse(ledger:acknowledge(matchResult().resultId, 10, "Ineligible", nil).ok)
	end),
	TestHarness.case("retains a compact immutable replay tombstone", function(assertions)
		local ledger = service(assertions)
		ledger:create(matchResult())
		assertions.isFalse(ledger:compact(matchResult().resultId).ok)
		ledger:acknowledge(matchResult().resultId, 10, "Ineligible", nil)
		assertions.isTrue(ledger:compact(matchResult().resultId).value)
		local tombstone = ledger:getForUser(matchResult().resultId, 10)
		assertions.isTrue(tombstone.ok)
		assertions.equal(tombstone.value.phase, "Compacted")
		assertions.equal(tombstone.value.state, "Ineligible")
		assertions.isFalse(ledger:create(matchResult()).ok)
	end),
	TestHarness.case("finalizes a durable pre-travel result intent exactly once", function(assertions)
		local ledger = service(assertions)
		local result = matchResult()
		local intent = {
			version = 1,
			resultId = result.resultId,
			matchId = result.matchId,
			ticketId = result.ticketId,
			expectedUserIds = { 10 },
			createdAt = 100,
		}
		assertions.isTrue(ledger:createIntent(intent).value)
		assertions.isFalse(ledger:createIntent(intent).value)
		local pending = ledger:getForUser(result.resultId, 10)
		assertions.isTrue(pending.ok)
		assertions.equal(pending.value.phase, "Intent")
		assertions.equal(pending.value.state, "Pending")
		assertions.isNil(pending.value.result)
		assertions.isTrue(ledger:create(result).value)
		assertions.isFalse(ledger:create(result).value)
		local finalized = ledger:getForUser(result.resultId, 10)
		assertions.equal(finalized.value.phase, "Final")
		assertions.equal(finalized.value.result.resultId, result.resultId)
	end),
	TestHarness.case("expires an orphan intent only after the active-route lifetime", function(assertions)
		local ledger = service(assertions)
		local result = matchResult("result:orphan-timeout")
		assertions.isTrue(ledger:createIntent({
			version = 1,
			resultId = result.resultId,
			matchId = result.matchId,
			ticketId = result.ticketId,
			expectedUserIds = { 10 },
			createdAt = 100,
		}).ok)
		assertions.isFalse(ledger:expireIntent(result.resultId, 10, 2_799).ok)
		assertions.isTrue(ledger:expireIntent(result.resultId, 10, 2_800).value)
		local failed = ledger:getForUser(result.resultId, 10)
		assertions.equal(failed.value.phase, "Failed")
		assertions.equal(failed.value.state, "Pending")
		assertions.equal(failed.value.failureReason, "MATCH_RESULT_TIMEOUT")
		assertions.isTrue(ledger:acknowledge(result.resultId, 10, "Failed", nil).value)
		assertions.isTrue(ledger:compact(result.resultId).value)
		local tombstone = ledger:getForUser(result.resultId, 10)
		assertions.equal(tombstone.value.phase, "Compacted")
		assertions.equal(tombstone.value.state, "Failed")
		assertions.isFalse(ledger:create(result).ok)
	end),
	TestHarness.case("an authoritative Match heartbeat keeps a long-running intent active", function(assertions)
		local ledger = service(assertions)
		local result = matchResult("result:long-running-match")
		assertions.isTrue(ledger:createIntent({
			version = 1,
			resultId = result.resultId,
			matchId = result.matchId,
			ticketId = result.ticketId,
			expectedUserIds = { 10 },
			createdAt = 100,
		}).ok)
		assertions.isTrue(ledger:renewIntent(result.resultId, result.matchId, result.ticketId, 2_700).value)
		assertions.isFalse(ledger:expireIntent(result.resultId, 10, 5_399).ok)
		assertions.equal(ledger:getForUser(result.resultId, 10).value.phase, "Intent")
		assertions.isTrue(ledger:expireIntent(result.resultId, 10, 5_400).value)
	end),
	TestHarness.case("cancels an aborted launch into an immutable zero-award tombstone", function(assertions)
		local ledger = service(assertions)
		local result = matchResult("result:cancelled-launch")
		assertions.isTrue(ledger:createIntent({
			version = 1,
			resultId = result.resultId,
			matchId = result.matchId,
			ticketId = result.ticketId,
			expectedUserIds = { 10 },
			createdAt = 100,
		}).ok)
		assertions.isTrue(
			ledger:cancelIntent(result.resultId, result.matchId, result.ticketId, "LOBBY_ABORTED", 101).value
		)
		assertions.isFalse(
			ledger:cancelIntent(result.resultId, result.matchId, result.ticketId, "LOBBY_ABORTED", 101).value
		)
		local tombstone = ledger:getForUser(result.resultId, 10).value
		assertions.equal(tombstone.phase, "Compacted")
		assertions.equal(tombstone.state, "Failed")
		assertions.isFalse(ledger:create(result).ok)
	end),
	TestHarness.case(
		"preserves the first durable failure while later terminal paths settle idempotently",
		function(assertions)
			local ledger = service(assertions)
			local result = matchResult("result:terminal-reason-race")
			assertions.isTrue(ledger:createIntent({
				version = 1,
				resultId = result.resultId,
				matchId = result.matchId,
				ticketId = result.ticketId,
				expectedUserIds = { 10 },
				createdAt = 100,
			}).ok)
			assertions.isTrue(ledger:expireIntent(result.resultId, 10, 2_800).value)
			assertions.isFalse(ledger:create(result).ok)
			assertions.isFalse(
				ledger:markFailed(result.resultId, result.matchId, result.ticketId, "RESULT_LEDGER_FAILED", 2_801).value
			)
			assertions.isFalse(
				ledger:cancelIntent(result.resultId, result.matchId, result.ticketId, "LOBBY_ABORTED", 2_801).value
			)
			local failed = ledger:getForUser(result.resultId, 10).value
			assertions.equal(failed.phase, "Failed")
			assertions.equal(failed.failureReason, "MATCH_RESULT_TIMEOUT")

			assertions.isTrue(ledger:acknowledge(result.resultId, 10, "Failed", nil).value)
			assertions.isTrue(ledger:compact(result.resultId).value)
			assertions.isFalse(
				ledger:markFailed(result.resultId, result.matchId, result.ticketId, "MATCH_TERMINAL_CLEANUP", 2_802).value
			)
			assertions.isFalse(
				ledger:cancelIntent(result.resultId, result.matchId, result.ticketId, "REMATCH_ABORTED", 2_802).value
			)
			local compacted = ledger:getForUser(result.resultId, 10).value
			assertions.equal(compacted.phase, "Compacted")
			assertions.equal(compacted.failureReason, "MATCH_RESULT_TIMEOUT")
		end
	),
	TestHarness.case("preserves pending claims across injected transient failures", function(assertions)
		local ledger, store = service(assertions)
		ledger:create(matchResult())
		store:failNext(1)
		assertions.isFalse(
			ledger:acknowledge(
				matchResult().resultId,
				10,
				"Claimed",
				{ persistentGoldAwarded = 50, firstClearBonus = 0 }
			).ok
		)
		assertions.equal(ledger:getForUser(matchResult().resultId, 10).value.state, "Pending")
	end),
})
