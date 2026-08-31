--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local Validation = require(ReplicatedStorage.Shared.util.Validation)

local BattleCashLedger = require(script.Parent.Parent.ProductionServerPlayable.BattleCashLedger)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:playable-ledger"

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		error("expected BattleCashLedger operation to succeed", 0)
	end
	return result.value
end

local function expectError(assertions: Assertions, result: any, code: string, operation: string)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		assertions.isTrue(table.isfrozen(result.error))
		assertions.equal(result.error.code, code)
		assertions.equal(result.error.operation, operation)
	end
end

local function newLedger(
	assertions: Assertions,
	startingBattleCash: number?,
	numerator: number?,
	denominator: number?
): BattleCashLedger.Ledger
	return success(
		assertions,
		BattleCashLedger.new(MATCH_ID, startingBattleCash or 100, numerator or 1, denominator or 4)
	)
end

local function initialize(assertions: Assertions, ledger: BattleCashLedger.Ledger, userId: number): any
	return success(assertions, ledger:initializeParticipant(userId))
end

return TestHarness.suite("BattleCashLedger", {
	TestHarness.case("validates construction and initializes each match participant once", function(assertions)
		expectError(assertions, BattleCashLedger.new("tower:wrong", 100, 1, 4), "INVALID_MATCH_ID", "new")
		for _, startingBalance in { -1, 0.5, 0 / 0, math.huge } do
			expectError(
				assertions,
				BattleCashLedger.new(MATCH_ID, startingBalance, 1, 4),
				"INVALID_STARTING_BALANCE",
				"new"
			)
		end
		for _, rate in
			{
				{ 0, 1 },
				{ 1, 0 },
				{ 0.5, 1 },
				{ 1, BattleCashLedger.MAX_DAMAGE_RATE_COMPONENT + 1 },
			}
		do
			expectError(assertions, BattleCashLedger.new(MATCH_ID, 100, rate[1], rate[2]), "INVALID_DAMAGE_RATE", "new")
		end

		local ledger = newLedger(assertions)
		local first = initialize(assertions, ledger, 20)
		assertions.equal(first.matchId, MATCH_ID)
		assertions.equal(first.balance, 100)
		assertions.equal(first.availableBalance, 100)
		assertions.equal(first.reservedBalance, 0)
		assertions.equal(first.revision, 1)
		assertions.isTrue(table.isfrozen(first))
		expectError(assertions, ledger:initializeParticipant(20), "DUPLICATE_PARTICIPANT", "initializeParticipant")
		expectError(assertions, ledger:initializeParticipant(0), "INVALID_USER_ID", "initializeParticipant")
		initialize(assertions, ledger, -3)
		initialize(assertions, ledger, 30)
		initialize(assertions, ledger, 40)
		expectError(assertions, ledger:initializeParticipant(50), "CAPACITY_EXCEEDED", "initializeParticipant")
		local listed = success(assertions, ledger:listSnapshots())
		assertions.equal(#listed, 4)
		assertions.equal(listed[1].userId, -3)
		assertions.equal(listed[2].userId, 20)
		assertions.equal(listed[3].userId, 30)
		assertions.equal(listed[4].userId, 40)
		assertions.isTrue(table.isfrozen(listed))
		assertions.isTrue(success(assertions, ledger:cleanup()))
	end),

	TestHarness.case("reserves exact funds and commits or aborts each opaque token once", function(assertions)
		local ledger = newLedger(assertions)
		initialize(assertions, ledger, 10)
		assertions.isTrue(success(assertions, ledger:canAfford(10, 100)))

		local first = success(assertions, ledger:prepare(10, 60, "spend-first"))
		assertions.isTrue(table.isfrozen(first))
		assertions.isTrue(success(assertions, ledger:canAfford(10, 40)))
		assertions.isFalse(success(assertions, ledger:canAfford(10, 41)))
		local replayedPrepare = success(assertions, ledger:prepare(10, 60, "spend-first"))
		assertions.equal(replayedPrepare, first)
		assertions.equal(ledger:getStats().outstandingSpendCount, 1)

		local second = success(assertions, ledger:prepare(10, 40, "spend-second"))
		assertions.isTrue(success(assertions, ledger:canAfford(10, 0)))
		expectError(assertions, ledger:prepare(10, 1, "spend-third"), "UNAFFORDABLE", "prepare")
		local reserved = success(assertions, ledger:getSnapshot(10))
		assertions.equal(reserved.balance, 100)
		assertions.equal(reserved.reservedBalance, 100)
		assertions.equal(reserved.availableBalance, 0)

		assertions.isTrue(success(assertions, ledger:commit(first)))
		expectError(assertions, ledger:commit(first), "INVALID_TOKEN", "commit")
		expectError(assertions, ledger:prepare(10, 60, "spend-first"), "RECEIPT_FINALIZED", "prepare")
		assertions.isTrue(success(assertions, ledger:abort(second)))
		expectError(assertions, ledger:abort(second), "INVALID_TOKEN", "abort")
		local final = success(assertions, ledger:getSnapshot(10))
		assertions.equal(final.balance, 40)
		assertions.equal(final.availableBalance, 40)
		assertions.equal(final.reservedBalance, 0)
		assertions.equal(final.spentBattleCash, 60)
		local stats = ledger:getStats()
		assertions.equal(stats.prepareCount, 2)
		assertions.equal(stats.commitCount, 1)
		assertions.equal(stats.abortCount, 1)
		assertions.equal(stats.totalSpentBattleCash, 60)
		assertions.isTrue(success(assertions, ledger:cleanup()))
	end),

	TestHarness.case("rejects forged cross-ledger and conflicting spend tokens", function(assertions)
		local firstLedger = newLedger(assertions)
		local secondLedger = success(assertions, BattleCashLedger.new("match:other-ledger", 100, 1, 4))
		initialize(assertions, firstLedger, 10)
		initialize(assertions, secondLedger, 10)
		local token = success(assertions, firstLedger:prepare(10, 25, "shared-spend"))
		expectError(assertions, secondLedger:commit(token), "INVALID_TOKEN", "commit")
		expectError(assertions, firstLedger:commit(table.freeze({})), "INVALID_TOKEN", "commit")
		expectError(assertions, firstLedger:prepare(10, 20, "shared-spend"), "RECEIPT_CONFLICT", "prepare")
		assertions.isTrue(success(assertions, firstLedger:abort(token)))
		assertions.isTrue(success(assertions, firstLedger:cleanup()))
		assertions.isTrue(success(assertions, secondLedger:cleanup()))
	end),

	TestHarness.case("accrues rational damage income cumulatively without per-hit rounding bias", function(assertions)
		local ledger = newLedger(assertions, 0, 1, 4)
		initialize(assertions, ledger, 10)
		local first = success(assertions, ledger:recordDamageIncome(10, 1, "damage-one"))
		assertions.equal(first.balanceDelta, 0)
		assertions.equal(first.snapshot.damageIncomeRemainder, 1)
		local second = success(assertions, ledger:recordDamageIncome(10, 2, "damage-two"))
		assertions.equal(second.balanceDelta, 0)
		assertions.equal(second.snapshot.damageIncomeRemainder, 3)
		local third = success(assertions, ledger:recordDamageIncome(10, 1, "damage-three"))
		assertions.equal(third.balanceDelta, 1)
		assertions.equal(third.snapshot.balance, 1)
		assertions.equal(third.snapshot.damageIncomeRemainder, 0)
		local replay = success(assertions, ledger:recordDamageIncome(10, 1, "damage-three"))
		assertions.isFalse(replay.applied)
		assertions.equal(replay.balanceDelta, 0)
		expectError(
			assertions,
			ledger:recordDamageIncome(10, 2, "damage-three"),
			"RECEIPT_CONFLICT",
			"recordDamageIncome"
		)

		local noCash = success(assertions, ledger:recordDamageIncome(10, 100, "damage-no-cash", false))
		assertions.equal(noCash.balanceDelta, 0)
		assertions.equal(noCash.snapshot.damageHealthRemoved, 4)
		assertions.equal(noCash.snapshot.damageIncomeRemainder, 0)
		assertions.isFalse(success(assertions, ledger:recordDamageIncome(10, 100, "damage-no-cash", false)).applied)
		assertions.isTrue(success(assertions, ledger:cleanup()))

		local split = success(assertions, BattleCashLedger.new("match:split-ledger", 0, 3, 4))
		local lump = success(assertions, BattleCashLedger.new("match:lump-ledger", 0, 3, 4))
		initialize(assertions, split, 10)
		initialize(assertions, lump, 10)
		success(assertions, split:recordDamageIncome(10, 1, "split-one"))
		success(assertions, split:recordDamageIncome(10, 2, "split-two"))
		success(assertions, split:recordDamageIncome(10, 4, "split-three"))
		success(assertions, lump:recordDamageIncome(10, 7, "lump-one"))
		local splitSnapshot = success(assertions, split:getSnapshot(10))
		local lumpSnapshot = success(assertions, lump:getSnapshot(10))
		assertions.equal(splitSnapshot.balance, 5)
		assertions.equal(splitSnapshot.balance, lumpSnapshot.balance)
		assertions.equal(splitSnapshot.damageIncomeRemainder, lumpSnapshot.damageIncomeRemainder)
		assertions.isTrue(success(assertions, split:cleanup()))
		assertions.isTrue(success(assertions, lump:cleanup()))
	end),

	TestHarness.case("applies wave stipends credits and refunds exactly once", function(assertions)
		local ledger = newLedger(assertions, 10)
		initialize(assertions, ledger, 20)
		initialize(assertions, ledger, 10)
		local stipend = success(assertions, ledger:grantWaveStipend("wave-one", 5))
		assertions.isTrue(stipend.applied)
		assertions.equal(stipend.participantCount, 2)
		assertions.equal(stipend.totalCredited, 10)
		assertions.equal(stipend.snapshots[1].userId, 10)
		assertions.equal(stipend.snapshots[2].userId, 20)
		assertions.isTrue(table.isfrozen(stipend))
		assertions.isTrue(table.isfrozen(stipend.snapshots))
		local stipendReplay = success(assertions, ledger:grantWaveStipend("wave-one", 5))
		assertions.isFalse(stipendReplay.applied)
		assertions.equal(stipendReplay.totalCredited, 0)
		expectError(assertions, ledger:grantWaveStipend("wave-one", 6), "RECEIPT_CONFLICT", "grantWaveStipend")

		local credit = success(assertions, ledger:credit(10, 4, "credit-one"))
		assertions.isTrue(credit.applied)
		assertions.equal(credit.balanceDelta, 4)
		assertions.isFalse(success(assertions, ledger:credit(10, 4, "credit-one")).applied)
		local refund = success(assertions, ledger:refund(10, 3, "refund-one"))
		assertions.equal(refund.balanceDelta, 3)
		expectError(assertions, ledger:refund(10, 4, "credit-one"), "RECEIPT_CONFLICT", "refund")

		local stats = ledger:getStats()
		assertions.isTrue(table.isfrozen(stats))
		assertions.equal(stats.totalBalance, 37)
		assertions.equal(stats.totalWaveStipendBattleCash, 10)
		assertions.equal(stats.totalCreditedBattleCash, 4)
		assertions.equal(stats.totalRefundedBattleCash, 3)
		assertions.equal(stats.receiptCount, 3)
		assertions.isTrue(success(assertions, ledger:cleanup()))
	end),

	TestHarness.case("pays stipends only to active participants and preserves reconnect balances", function(assertions)
		local ledger = newLedger(assertions, 10)
		initialize(assertions, ledger, 10)
		initialize(assertions, ledger, 20)
		local inactive = success(assertions, ledger:setParticipantActive(20, false))
		assertions.isFalse(inactive.active)
		local stipend = success(assertions, ledger:grantWaveStipend("active-wave", 5))
		assertions.equal(stipend.participantCount, 1)
		assertions.equal(stipend.totalCredited, 5)
		assertions.equal(success(assertions, ledger:getSnapshot(10)).balance, 15)
		assertions.equal(success(assertions, ledger:getSnapshot(20)).balance, 10)
		local reconnected = success(assertions, ledger:setParticipantActive(20, true))
		assertions.isTrue(reconnected.active)
		assertions.equal(reconnected.balance, 10)
		assertions.isTrue(success(assertions, ledger:cleanup()))
	end),

	TestHarness.case("fails atomically at safe-integer arithmetic boundaries", function(assertions)
		local maximum = Validation.MAX_SAFE_INTEGER
		local ledger = newLedger(assertions, maximum, 1, 1)
		initialize(assertions, ledger, 10)
		expectError(assertions, ledger:initializeParticipant(20), "ARITHMETIC_OVERFLOW", "initializeParticipant")
		expectError(assertions, ledger:credit(10, 1, "overflow-credit"), "ARITHMETIC_OVERFLOW", "credit")
		expectError(assertions, ledger:refund(10, 1, "overflow-refund"), "ARITHMETIC_OVERFLOW", "refund")
		expectError(
			assertions,
			ledger:recordDamageIncome(10, 1, "overflow-damage"),
			"ARITHMETIC_OVERFLOW",
			"recordDamageIncome"
		)
		expectError(assertions, ledger:grantWaveStipend("overflow-wave", 1), "ARITHMETIC_OVERFLOW", "grantWaveStipend")
		local unchanged = success(assertions, ledger:getSnapshot(10))
		assertions.equal(unchanged.balance, maximum)
		assertions.equal(unchanged.revision, 1)
		assertions.equal(ledger:getStats().receiptCount, 0)
		local token = success(assertions, ledger:prepare(10, maximum, "maximum-spend"))
		assertions.isTrue(success(assertions, ledger:commit(token)))
		assertions.equal(success(assertions, ledger:getSnapshot(10)).balance, 0)
		assertions.isTrue(success(assertions, ledger:cleanup()))

		local rateOverflow = success(
			assertions,
			BattleCashLedger.new("match:rate-overflow", 0, BattleCashLedger.MAX_DAMAGE_RATE_COMPONENT, 1)
		)
		initialize(assertions, rateOverflow, 10)
		expectError(
			assertions,
			rateOverflow:recordDamageIncome(10, maximum, "rate-overflow"),
			"ARITHMETIC_OVERFLOW",
			"recordDamageIncome"
		)
		assertions.equal(success(assertions, rateOverflow:getSnapshot(10)).balance, 0)
		assertions.isTrue(success(assertions, rateOverflow:cleanup()))
	end),

	TestHarness.case("returns detached frozen snapshots and removes all match state on cleanup", function(assertions)
		local ledger = newLedger(assertions)
		initialize(assertions, ledger, 10)
		local first = success(assertions, ledger:getSnapshot(10))
		local second = success(assertions, ledger:getSnapshot(10))
		assertions.notEqual(first, second)
		assertions.isTrue(table.isfrozen(first))
		assertions.isTrue(table.isfrozen(second))
		local token = success(assertions, ledger:prepare(10, 30, "cleanup-spend"))
		success(assertions, ledger:credit(10, 5, "cleanup-credit"))
		assertions.isTrue(success(assertions, ledger:cleanup()))
		assertions.isFalse(success(assertions, ledger:cleanup()))
		local stats = ledger:getStats()
		assertions.equal(stats.state, "Cleaned")
		assertions.isNil(stats.matchId)
		assertions.equal(stats.participantCount, 0)
		assertions.equal(stats.receiptCount, 0)
		assertions.equal(stats.outstandingSpendCount, 0)
		assertions.equal(stats.totalBalance, 0)
		assertions.equal(stats.totalReserved, 0)
		expectError(assertions, ledger:commit(token), "CLEANED", "commit")
		expectError(assertions, ledger:getSnapshot(10), "CLEANED", "getSnapshot")
		expectError(assertions, ledger:listSnapshots(), "CLEANED", "listSnapshots")
		expectError(assertions, ledger:credit(10, 1, "after-cleanup"), "CLEANED", "credit")
	end),
})
