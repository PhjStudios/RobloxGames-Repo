--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local ConfigurationFixtures = require(script.Parent.Parent.Fixtures.ConfigurationFixtures)
local IsolatedProfileStore = require(script.Parent.Parent.Fixtures.IsolatedProfileStore)
local PendingResultService = require(script.Parent.Parent.ProductionServerProfile.PendingResultService)
local ProfileSchema = require(script.Parent.Parent.ProductionServerProfile.ProfileSchema)
local ProfileService = require(script.Parent.Parent.ProductionServerProfile.ProfileService)
local ConfigurationValidator = require(game:GetService("ReplicatedStorage").Shared.config.ConfigurationValidator)
local Result = require(game:GetService("ReplicatedStorage").Shared.util.Result)

local function success(assertions, result)
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected pending-result operation to succeed", 0)
	end
	return result.value
end

local function stack(assertions)
	local configuration = success(assertions, ConfigurationValidator.validate(ConfigurationFixtures.validSources()))
	local store = IsolatedProfileStore.new()
	local profile = success(
		assertions,
		ProfileService.new(configuration.towers, store, {
			sessionId = "pending-result-session",
			clock = function()
				return 2_000
			end,
			wait = function(_seconds) end,
		})
	)
	for _, userId in { 101, 202, 303, 404 } do
		success(assertions, profile:load(userId))
	end
	return profile, success(assertions, PendingResultService.new(profile)), store
end

return TestHarness.suite("bounded pending result profile inbox", {
	TestHarness.case(
		"atomically reserves and idempotently releases one result for an ordered squad",
		function(assertions)
			local profile, pending = stack(assertions)
			local resultId = "result:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
			local reservation = success(assertions, pending:reserve({ 101, 202, 303 }, resultId, 2_000))
			assertions.equal(reservation.resultId, resultId)
			assertions.equal(#reservation.orderedUserIds, 3)
			for _, userId in reservation.orderedUserIds do
				local listed = success(assertions, pending:list(userId))
				assertions.equal(#listed, 1)
				assertions.equal(listed[1].resultId, resultId)
			end
			success(assertions, pending:reserve({ 101, 202, 303 }, resultId, 2_000))
			assertions.equal(#success(assertions, pending:list(101)), 1)
			assertions.isTrue(success(assertions, pending:release({ 101, 202, 303 }, resultId, 2_000)))
			assertions.isTrue(success(assertions, pending:release({ 101, 202, 303 }, resultId, 2_000)))
			assertions.equal(#success(assertions, pending:list(101)), 0)
			assertions.equal(#success(assertions, profile:read(202)).pendingResults, 0)
		end
	),

	TestHarness.case("rolls back earlier members when a later profile is unavailable", function(assertions)
		local profile, pending = stack(assertions)
		success(assertions, profile:release(202))
		local result = pending:reserve({ 101, 202, 303 }, "result:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", 2_000)
		assertions.isFalse(result.ok)
		assertions.equal(#success(assertions, pending:list(101)), 0)
		assertions.equal(#success(assertions, pending:list(303)), 0)
	end),

	TestHarness.case(
		"accepts a reservation whose committed profile returned an ambiguous failure",
		function(assertions)
			local profile, _pending = stack(assertions)
			local failedAfterCommit = false
			local ambiguousOwner = {
				read = function(_self, userId)
					return profile:read(userId)
				end,
				flush = function(_self, userId)
					return profile:flush(userId)
				end,
				transact = function(_self, userId, transactionId, expectedRevision, kind, fingerprint, callback)
					local outcome =
						profile:transact(userId, transactionId, expectedRevision, kind, fingerprint, callback)
					if userId == 202 and kind == "ReserveMatchResult" and not failedAfterCommit then
						failedAfterCommit = true
						return Result.err("AMBIGUOUS_TRANSPORT_FAILURE")
					end
					return outcome
				end,
			}
			local pending = success(assertions, PendingResultService.new(ambiguousOwner))
			local resultId = "result:cccccccc-cccc-cccc-cccc-cccccccccccc"
			success(assertions, pending:reserve({ 101, 202, 303 }, resultId, 2_000))
			for _, userId in { 101, 202, 303 } do
				local records = success(assertions, pending:list(userId))
				assertions.equal(#records, 1)
				assertions.equal(records[1].resultId, resultId)
			end
		end
	),

	TestHarness.case("durably flushes a released result and safely retries a failed flush", function(assertions)
		local profile, pending, store = stack(assertions)
		local resultId = "result:durable-release"
		success(assertions, pending:reserve({ 101 }, resultId, 2_000))
		success(assertions, profile:flush(101))
		assertions.equal(#(store:read("profile:101") :: any).profile.pendingResults, 1)

		store:failNext(3)
		local failed = pending:release({ 101 }, resultId, 2_000)
		assertions.isFalse(failed.ok)
		assertions.equal(#(store:read("profile:101") :: any).profile.pendingResults, 1)

		assertions.isTrue(success(assertions, pending:release({ 101 }, resultId, 2_000)))
		assertions.equal(#(store:read("profile:101") :: any).profile.pendingResults, 0)
	end),

	TestHarness.case("fails closed when the durable inbox reaches its bound", function(assertions)
		local _profile, pending = stack(assertions)
		for index = 1, ProfileSchema.MAX_PENDING_RESULT_IDS do
			local body = string.format("%036d", index)
			success(assertions, pending:reserve({ 404 }, `result:{body}`, 2_000 + index))
		end
		local overflow = pending:reserve({ 404 }, "result:zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz", 3_000)
		assertions.isFalse(overflow.ok)
		if not overflow.ok then
			assertions.equal(overflow.error.code, "CAPACITY_EXCEEDED")
		end
		assertions.equal(#success(assertions, pending:list(404)), ProfileSchema.MAX_PENDING_RESULT_IDS)
	end),
})
