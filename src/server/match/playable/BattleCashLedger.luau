--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type State = "Active" | "Cleaned"
export type MutationKind = "Credit" | "DamageIncome" | "Refund"
export type ReceiptKind = MutationKind | "Spend" | "WaveStipend"

export type ParticipantSnapshot = {
	matchId: Ids.MatchId,
	userId: number,
	active: boolean,
	revision: number,
	balance: number,
	availableBalance: number,
	reservedBalance: number,
	startingBattleCash: number,
	spentBattleCash: number,
	damageHealthRemoved: number,
	damageIncomeBattleCash: number,
	damageIncomeRemainder: number,
	waveStipendBattleCash: number,
	creditedBattleCash: number,
	refundedBattleCash: number,
}

export type BalanceMutation = {
	applied: boolean,
	kind: MutationKind,
	receiptKey: string,
	requestedAmount: number,
	balanceDelta: number,
	snapshot: ParticipantSnapshot,
}

export type WaveStipendResult = {
	applied: boolean,
	receiptKey: string,
	amountPerParticipant: number,
	participantCount: number,
	totalCredited: number,
	snapshots: { ParticipantSnapshot },
}

export type Stats = {
	state: State,
	matchId: Ids.MatchId?,
	participantCount: number,
	receiptCount: number,
	outstandingSpendCount: number,
	prepareCount: number,
	commitCount: number,
	abortCount: number,
	totalBalance: number,
	totalReserved: number,
	totalStartingBattleCash: number,
	totalSpentBattleCash: number,
	totalDamageHealthRemoved: number,
	totalDamageIncomeBattleCash: number,
	totalWaveStipendBattleCash: number,
	totalCreditedBattleCash: number,
	totalRefundedBattleCash: number,
}

export type SpendToken = {}

export type Operation =
	"new"
	| "initializeParticipant"
	| "setParticipantActive"
	| "canAfford"
	| "prepare"
	| "commit"
	| "abort"
	| "getSnapshot"
	| "listSnapshots"
	| "recordDamageIncome"
	| "grantWaveStipend"
	| "credit"
	| "refund"
	| "cleanup"

export type ErrorCode =
	"INVALID_MATCH_ID"
	| "INVALID_STARTING_BALANCE"
	| "INVALID_DAMAGE_RATE"
	| "INVALID_USER_ID"
	| "DUPLICATE_PARTICIPANT"
	| "PARTICIPANT_NOT_FOUND"
	| "INVALID_AMOUNT"
	| "INVALID_ELIGIBILITY"
	| "INVALID_RECEIPT"
	| "RECEIPT_CONFLICT"
	| "RECEIPT_FINALIZED"
	| "UNAFFORDABLE"
	| "INVALID_TOKEN"
	| "CAPACITY_EXCEEDED"
	| "ARITHMETIC_OVERFLOW"
	| "REVISION_EXHAUSTED"
	| "CLEANED"

export type LedgerError = {
	code: ErrorCode,
	operation: Operation,
}

type ParticipantData = {
	userId: number,
	active: boolean,
	revision: number,
	balance: number,
	reserved: number,
	spent: number,
	damageHealthRemoved: number,
	damageIncome: number,
	damageRemainder: number,
	waveStipends: number,
	credits: number,
	refunds: number,
}

type SpendReceiptState = "Prepared" | "Committed" | "Aborted"

type ReceiptData = {
	kind: ReceiptKind,
	userId: number?,
	amount: number,
	eligible: boolean?,
	state: SpendReceiptState?,
	token: SpendToken?,
}

type SpendTokenData = {
	owner: LedgerData,
	userId: number,
	amount: number,
	receiptKey: string?,
	active: boolean,
}

type LedgerData = {
	state: State,
	matchId: Ids.MatchId?,
	startingBattleCash: number,
	damageNumerator: number,
	damageDenominator: number,
	participantsByUserId: { [number]: ParticipantData },
	orderedUserIds: { number },
	issuedUserIds: { [number]: boolean },
	receipts: { [string]: ReceiptData },
	receiptCount: number,
	tokens: { [SpendToken]: boolean },
	outstandingSpendCount: number,
	prepareCount: number,
	commitCount: number,
	abortCount: number,
	totalBalance: number,
	totalReserved: number,
	totalStartingBattleCash: number,
	totalSpentBattleCash: number,
	totalDamageHealthRemoved: number,
	totalDamageIncomeBattleCash: number,
	totalWaveStipendBattleCash: number,
	totalCreditedBattleCash: number,
	totalRefundedBattleCash: number,
}

local MAX_PARTICIPANTS = 4
local MAX_OUTSTANDING_SPENDS = 256
local MAX_RECEIPTS = 16_384
local MAX_DAMAGE_RATE_COMPONENT = 1_000_000

local Methods = {}
Methods.__index = Methods

export type Ledger = typeof(setmetatable({} :: {}, Methods))

local LEDGER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: LedgerData }
local TOKEN_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: SpendTokenData }

local BattleCashLedger = {
	MAX_DAMAGE_RATE_COMPONENT = MAX_DAMAGE_RATE_COMPONENT,
	MAX_OUTSTANDING_SPENDS = MAX_OUTSTANDING_SPENDS,
	MAX_PARTICIPANTS = MAX_PARTICIPANTS,
	MAX_RECEIPTS = MAX_RECEIPTS,
}

local function makeError(code: ErrorCode, operation: Operation): LedgerError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<LedgerError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): LedgerData
	local data = if type(value) == "table" then LEDGER_DATA[value :: any] else nil
	if data == nil then
		error("[ATD_BATTLE_CASH_LEDGER][code=INVALID_CONTEXT]", 0)
	end
	return data :: LedgerData
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and value ~= 0
end

local function validNonnegativeAmount(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and value >= 0
end

local function validReceiptKey(value: unknown): boolean
	return type(value) == "string" and Validation.isSymbolicKey(value :: string)
end

local function checkedAdd(left: number, right: number): number?
	if right < 0 or right > Validation.MAX_SAFE_INTEGER - left then
		return nil
	end
	return left + right
end

local function checkedIncrement(value: number): number?
	return if value < Validation.MAX_SAFE_INTEGER then value + 1 else nil
end

local function snapshot(data: LedgerData, participant: ParticipantData): ParticipantSnapshot
	return table.freeze({
		matchId = data.matchId :: Ids.MatchId,
		userId = participant.userId,
		active = participant.active,
		revision = participant.revision,
		balance = participant.balance,
		availableBalance = participant.balance - participant.reserved,
		reservedBalance = participant.reserved,
		startingBattleCash = data.startingBattleCash,
		spentBattleCash = participant.spent,
		damageHealthRemoved = participant.damageHealthRemoved,
		damageIncomeBattleCash = participant.damageIncome,
		damageIncomeRemainder = participant.damageRemainder,
		waveStipendBattleCash = participant.waveStipends,
		creditedBattleCash = participant.credits,
		refundedBattleCash = participant.refunds,
	})
end

local function listSnapshotsTrusted(data: LedgerData): { ParticipantSnapshot }
	local snapshots: { ParticipantSnapshot } = table.create(#data.orderedUserIds)
	for index, userId in data.orderedUserIds do
		snapshots[index] = snapshot(data, data.participantsByUserId[userId])
	end
	return table.freeze(snapshots)
end

local function requireActive(data: LedgerData, operation: Operation): LedgerError?
	if data.state ~= "Active" then
		return makeError("CLEANED", operation)
	end
	return nil
end

local function participantFor(
	data: LedgerData,
	userIdValue: unknown,
	operation: Operation
): (ParticipantData?, LedgerError?)
	if not validUserId(userIdValue) then
		return nil, makeError("INVALID_USER_ID", operation)
	end
	local participant = data.participantsByUserId[userIdValue :: number]
	if participant == nil then
		return nil, makeError("PARTICIPANT_NOT_FOUND", operation)
	end
	return participant, nil
end

local function receiptForMutation(
	data: LedgerData,
	receiptKeyValue: unknown,
	kind: ReceiptKind,
	userId: number?,
	amount: number,
	eligible: boolean?,
	operation: Operation
): (ReceiptData?, LedgerError?)
	if not validReceiptKey(receiptKeyValue) then
		return nil, makeError("INVALID_RECEIPT", operation)
	end
	local existing = data.receipts[receiptKeyValue :: string]
	if existing == nil then
		if data.receiptCount >= MAX_RECEIPTS then
			return nil, makeError("CAPACITY_EXCEEDED", operation)
		end
		return nil, nil
	end
	if
		existing.kind ~= kind
		or existing.userId ~= userId
		or existing.amount ~= amount
		or existing.eligible ~= eligible
	then
		return nil, makeError("RECEIPT_CONFLICT", operation)
	end
	return existing, nil
end

local function recordReceipt(
	data: LedgerData,
	receiptKey: string,
	kind: ReceiptKind,
	userId: number?,
	amount: number,
	eligible: boolean?,
	state: SpendReceiptState?,
	token: SpendToken?
)
	data.receipts[receiptKey] = {
		kind = kind,
		userId = userId,
		amount = amount,
		eligible = eligible,
		state = state,
		token = token,
	}
	data.receiptCount += 1
end

local function mutationResult(
	data: LedgerData,
	participant: ParticipantData,
	applied: boolean,
	kind: MutationKind,
	receiptKey: string,
	requestedAmount: number,
	balanceDelta: number
): BalanceMutation
	return table.freeze({
		applied = applied,
		kind = kind,
		receiptKey = receiptKey,
		requestedAmount = requestedAmount,
		balanceDelta = balanceDelta,
		snapshot = snapshot(data, participant),
	})
end

local function creditFixed(
	data: LedgerData,
	participant: ParticipantData,
	amount: number,
	receiptKey: string,
	kind: "Credit" | "Refund",
	operation: "credit" | "refund"
): Result.Result<BalanceMutation, LedgerError>
	local existing, receiptError =
		receiptForMutation(data, receiptKey, kind, participant.userId, amount, nil, operation)
	if receiptError ~= nil then
		return Result.err(receiptError)
	end
	if existing ~= nil then
		return Result.ok(mutationResult(data, participant, false, kind, receiptKey, amount, 0))
	end
	if participant.revision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", operation)
	end
	local nextBalance = checkedAdd(participant.balance, amount)
	local nextTotalBalance = checkedAdd(data.totalBalance, amount)
	local participantTotal = if kind == "Credit"
		then checkedAdd(participant.credits, amount)
		else checkedAdd(participant.refunds, amount)
	local ledgerTotal = if kind == "Credit"
		then checkedAdd(data.totalCreditedBattleCash, amount)
		else checkedAdd(data.totalRefundedBattleCash, amount)
	if nextBalance == nil or nextTotalBalance == nil or participantTotal == nil or ledgerTotal == nil then
		return failure("ARITHMETIC_OVERFLOW", operation)
	end

	participant.balance = nextBalance
	participant.revision += 1
	data.totalBalance = nextTotalBalance
	if kind == "Credit" then
		participant.credits = participantTotal
		data.totalCreditedBattleCash = ledgerTotal
	else
		participant.refunds = participantTotal
		data.totalRefundedBattleCash = ledgerTotal
	end
	recordReceipt(data, receiptKey, kind, participant.userId, amount, nil, nil, nil)
	return Result.ok(mutationResult(data, participant, true, kind, receiptKey, amount, amount))
end

local function calculateDamageGrant(
	currentRemainder: number,
	healthRemoved: number,
	numerator: number,
	denominator: number
): (number?, number?)
	local wholeHealth = math.floor(healthRemoved / denominator)
	local healthRemainder = healthRemoved - wholeHealth * denominator
	local partial = currentRemainder + healthRemainder * numerator
	local extra = math.floor(partial / denominator)
	local nextRemainder = partial - extra * denominator
	if wholeHealth > math.floor((Validation.MAX_SAFE_INTEGER - extra) / numerator) then
		return nil, nil
	end
	return wholeHealth * numerator + extra, nextRemainder
end

function Methods.initializeParticipant(
	self: Ledger,
	userIdValue: unknown
): Result.Result<ParticipantSnapshot, LedgerError>
	local data = requireData(self)
	local stateError = requireActive(data, "initializeParticipant")
	if stateError ~= nil then
		return Result.err(stateError)
	end
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "initializeParticipant")
	end
	local userId = userIdValue :: number
	if data.issuedUserIds[userId] == true then
		return failure("DUPLICATE_PARTICIPANT", "initializeParticipant")
	end
	if #data.orderedUserIds >= MAX_PARTICIPANTS then
		return failure("CAPACITY_EXCEEDED", "initializeParticipant")
	end
	local totalStarting = checkedAdd(data.totalStartingBattleCash, data.startingBattleCash)
	local totalBalance = checkedAdd(data.totalBalance, data.startingBattleCash)
	if totalStarting == nil or totalBalance == nil then
		return failure("ARITHMETIC_OVERFLOW", "initializeParticipant")
	end
	local participant: ParticipantData = {
		userId = userId,
		active = true,
		revision = 1,
		balance = data.startingBattleCash,
		reserved = 0,
		spent = 0,
		damageHealthRemoved = 0,
		damageIncome = 0,
		damageRemainder = 0,
		waveStipends = 0,
		credits = 0,
		refunds = 0,
	}
	data.participantsByUserId[userId] = participant
	data.issuedUserIds[userId] = true
	table.insert(data.orderedUserIds, userId)
	table.sort(data.orderedUserIds)
	data.totalStartingBattleCash = totalStarting
	data.totalBalance = totalBalance
	return Result.ok(snapshot(data, participant))
end

function Methods.setParticipantActive(
	self: Ledger,
	userIdValue: unknown,
	activeValue: unknown
): Result.Result<ParticipantSnapshot, LedgerError>
	local data = requireData(self)
	local stateError = requireActive(data, "setParticipantActive")
	if stateError ~= nil then
		return Result.err(stateError)
	end
	if type(activeValue) ~= "boolean" then
		return failure("INVALID_ELIGIBILITY", "setParticipantActive")
	end
	local participant, participantError = participantFor(data, userIdValue, "setParticipantActive")
	if participant == nil then
		return Result.err(participantError :: LedgerError)
	end
	if participant.active == activeValue then
		return Result.ok(snapshot(data, participant))
	end
	if participant.revision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", "setParticipantActive")
	end
	participant.active = activeValue :: boolean
	participant.revision += 1
	return Result.ok(snapshot(data, participant))
end

function Methods.canAfford(
	self: Ledger,
	userIdValue: unknown,
	amountValue: unknown
): Result.Result<boolean, LedgerError>
	local data = requireData(self)
	local stateError = requireActive(data, "canAfford")
	if stateError ~= nil then
		return Result.err(stateError)
	end
	if not validNonnegativeAmount(amountValue) then
		return failure("INVALID_AMOUNT", "canAfford")
	end
	local participant, participantError = participantFor(data, userIdValue, "canAfford")
	if participant == nil then
		return Result.err(participantError :: LedgerError)
	end
	return Result.ok((amountValue :: number) <= participant.balance - participant.reserved)
end

function Methods.prepare(
	self: Ledger,
	userIdValue: unknown,
	amountValue: unknown,
	receiptKeyValue: unknown?
): Result.Result<SpendToken, LedgerError>
	local data = requireData(self)
	local stateError = requireActive(data, "prepare")
	if stateError ~= nil then
		return Result.err(stateError)
	end
	if not validNonnegativeAmount(amountValue) then
		return failure("INVALID_AMOUNT", "prepare")
	end
	local participant, participantError = participantFor(data, userIdValue, "prepare")
	if participant == nil then
		return Result.err(participantError :: LedgerError)
	end
	local amount = amountValue :: number
	local receiptKey: string? = nil
	if receiptKeyValue ~= nil then
		if not validReceiptKey(receiptKeyValue) then
			return failure("INVALID_RECEIPT", "prepare")
		end
		receiptKey = receiptKeyValue :: string
		local existing, receiptError =
			receiptForMutation(data, receiptKey, "Spend", participant.userId, amount, nil, "prepare")
		if receiptError ~= nil then
			return Result.err(receiptError)
		end
		if existing ~= nil then
			if existing.state == "Prepared" and existing.token ~= nil then
				return Result.ok(existing.token)
			end
			return failure("RECEIPT_FINALIZED", "prepare")
		end
	end
	if amount > participant.balance - participant.reserved then
		return failure("UNAFFORDABLE", "prepare")
	end
	if data.outstandingSpendCount >= MAX_OUTSTANDING_SPENDS then
		return failure("CAPACITY_EXCEEDED", "prepare")
	end
	if participant.revision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", "prepare")
	end
	local nextPrepareCount = checkedIncrement(data.prepareCount)
	local nextReserved = checkedAdd(participant.reserved, amount)
	local nextTotalReserved = checkedAdd(data.totalReserved, amount)
	if nextPrepareCount == nil or nextReserved == nil or nextTotalReserved == nil then
		return failure("ARITHMETIC_OVERFLOW", "prepare")
	end

	local token = table.freeze({}) :: SpendToken
	TOKEN_DATA[token] = {
		owner = data,
		userId = participant.userId,
		amount = amount,
		receiptKey = receiptKey,
		active = true,
	}
	data.tokens[token] = true
	data.outstandingSpendCount += 1
	data.prepareCount = nextPrepareCount
	data.totalReserved = nextTotalReserved
	participant.reserved = nextReserved
	participant.revision += 1
	if receiptKey ~= nil then
		recordReceipt(data, receiptKey, "Spend", participant.userId, amount, nil, "Prepared", token)
	end
	return Result.ok(token)
end

local function finishSpend(
	data: LedgerData,
	tokenValue: unknown,
	operation: "commit" | "abort"
): Result.Result<boolean, LedgerError>
	local stateError = requireActive(data, operation)
	if stateError ~= nil then
		return Result.err(stateError)
	end
	local tokenData = if type(tokenValue) == "table" then TOKEN_DATA[tokenValue :: any] else nil
	if
		tokenData == nil
		or tokenData.owner ~= data
		or not tokenData.active
		or data.tokens[tokenValue :: any] ~= true
	then
		return failure("INVALID_TOKEN", operation)
	end
	local participant = data.participantsByUserId[tokenData.userId]
	if participant == nil or participant.reserved < tokenData.amount then
		return failure("INVALID_TOKEN", operation)
	end
	if participant.revision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", operation)
	end
	local nextCount = if operation == "commit"
		then checkedIncrement(data.commitCount)
		else checkedIncrement(data.abortCount)
	if nextCount == nil then
		return failure("ARITHMETIC_OVERFLOW", operation)
	end
	local nextBalance = participant.balance
	local nextSpent = participant.spent
	local nextTotalBalance = data.totalBalance
	local nextTotalSpent = data.totalSpentBattleCash
	if operation == "commit" then
		nextBalance -= tokenData.amount
		nextTotalBalance -= tokenData.amount
		local participantSpent = checkedAdd(participant.spent, tokenData.amount)
		local totalSpent = checkedAdd(data.totalSpentBattleCash, tokenData.amount)
		if participantSpent == nil or totalSpent == nil then
			return failure("ARITHMETIC_OVERFLOW", operation)
		end
		nextSpent = participantSpent
		nextTotalSpent = totalSpent
	end

	participant.balance = nextBalance
	participant.reserved -= tokenData.amount
	participant.spent = nextSpent
	participant.revision += 1
	data.totalBalance = nextTotalBalance
	data.totalReserved -= tokenData.amount
	data.totalSpentBattleCash = nextTotalSpent
	data.outstandingSpendCount -= 1
	if operation == "commit" then
		data.commitCount = nextCount
	else
		data.abortCount = nextCount
	end
	tokenData.active = false
	TOKEN_DATA[tokenValue :: any] = nil
	data.tokens[tokenValue :: any] = nil
	if tokenData.receiptKey ~= nil then
		local receipt = data.receipts[tokenData.receiptKey]
		if receipt ~= nil then
			receipt.state = if operation == "commit" then "Committed" else "Aborted"
			receipt.token = nil
		end
	end
	return Result.ok(true)
end

function Methods.commit(self: Ledger, token: unknown): Result.Result<boolean, LedgerError>
	return finishSpend(requireData(self), token, "commit")
end

function Methods.abort(self: Ledger, token: unknown): Result.Result<boolean, LedgerError>
	return finishSpend(requireData(self), token, "abort")
end

function Methods.getSnapshot(self: Ledger, userIdValue: unknown): Result.Result<ParticipantSnapshot, LedgerError>
	local data = requireData(self)
	local stateError = requireActive(data, "getSnapshot")
	if stateError ~= nil then
		return Result.err(stateError)
	end
	local participant, participantError = participantFor(data, userIdValue, "getSnapshot")
	if participant == nil then
		return Result.err(participantError :: LedgerError)
	end
	return Result.ok(snapshot(data, participant))
end

function Methods.listSnapshots(self: Ledger): Result.Result<{ ParticipantSnapshot }, LedgerError>
	local data = requireData(self)
	local stateError = requireActive(data, "listSnapshots")
	if stateError ~= nil then
		return Result.err(stateError)
	end
	return Result.ok(listSnapshotsTrusted(data))
end

function Methods.recordDamageIncome(
	self: Ledger,
	userIdValue: unknown,
	actualHealthRemovedValue: unknown,
	receiptKeyValue: unknown,
	eligibleValue: unknown?
): Result.Result<BalanceMutation, LedgerError>
	local data = requireData(self)
	local stateError = requireActive(data, "recordDamageIncome")
	if stateError ~= nil then
		return Result.err(stateError)
	end
	if not validNonnegativeAmount(actualHealthRemovedValue) then
		return failure("INVALID_AMOUNT", "recordDamageIncome")
	end
	local eligible = if eligibleValue == nil then true else eligibleValue
	if type(eligible) ~= "boolean" then
		return failure("INVALID_ELIGIBILITY", "recordDamageIncome")
	end
	local participant, participantError = participantFor(data, userIdValue, "recordDamageIncome")
	if participant == nil then
		return Result.err(participantError :: LedgerError)
	end
	local healthRemoved = actualHealthRemovedValue :: number
	local receiptKey = if validReceiptKey(receiptKeyValue) then receiptKeyValue :: string else nil
	if receiptKey == nil then
		return failure("INVALID_RECEIPT", "recordDamageIncome")
	end
	local existing, receiptError = receiptForMutation(
		data,
		receiptKey,
		"DamageIncome",
		participant.userId,
		healthRemoved,
		eligible :: boolean,
		"recordDamageIncome"
	)
	if receiptError ~= nil then
		return Result.err(receiptError)
	end
	if existing ~= nil then
		return Result.ok(mutationResult(data, participant, false, "DamageIncome", receiptKey, healthRemoved, 0))
	end
	if participant.revision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", "recordDamageIncome")
	end

	local grant = 0
	local nextRemainder = participant.damageRemainder
	local nextHealthRemoved = participant.damageHealthRemoved
	local nextLedgerHealthRemoved = data.totalDamageHealthRemoved
	if eligible then
		local calculatedGrant, calculatedRemainder = calculateDamageGrant(
			participant.damageRemainder,
			healthRemoved,
			data.damageNumerator,
			data.damageDenominator
		)
		if calculatedGrant == nil or calculatedRemainder == nil then
			return failure("ARITHMETIC_OVERFLOW", "recordDamageIncome")
		end
		grant = calculatedGrant
		nextRemainder = calculatedRemainder
		local participantHealth = checkedAdd(participant.damageHealthRemoved, healthRemoved)
		local ledgerHealth = checkedAdd(data.totalDamageHealthRemoved, healthRemoved)
		if participantHealth == nil or ledgerHealth == nil then
			return failure("ARITHMETIC_OVERFLOW", "recordDamageIncome")
		end
		nextHealthRemoved = participantHealth
		nextLedgerHealthRemoved = ledgerHealth
	end
	local nextBalance = checkedAdd(participant.balance, grant)
	local nextTotalBalance = checkedAdd(data.totalBalance, grant)
	local nextIncome = checkedAdd(participant.damageIncome, grant)
	local nextTotalIncome = checkedAdd(data.totalDamageIncomeBattleCash, grant)
	if nextBalance == nil or nextTotalBalance == nil or nextIncome == nil or nextTotalIncome == nil then
		return failure("ARITHMETIC_OVERFLOW", "recordDamageIncome")
	end

	participant.balance = nextBalance
	participant.damageHealthRemoved = nextHealthRemoved
	participant.damageIncome = nextIncome
	participant.damageRemainder = nextRemainder
	participant.revision += 1
	data.totalBalance = nextTotalBalance
	data.totalDamageHealthRemoved = nextLedgerHealthRemoved
	data.totalDamageIncomeBattleCash = nextTotalIncome
	recordReceipt(data, receiptKey, "DamageIncome", participant.userId, healthRemoved, eligible, nil, nil)
	return Result.ok(mutationResult(data, participant, true, "DamageIncome", receiptKey, healthRemoved, grant))
end

function Methods.grantWaveStipend(
	self: Ledger,
	receiptKeyValue: unknown,
	amountPerParticipantValue: unknown
): Result.Result<WaveStipendResult, LedgerError>
	local data = requireData(self)
	local stateError = requireActive(data, "grantWaveStipend")
	if stateError ~= nil then
		return Result.err(stateError)
	end
	if not validNonnegativeAmount(amountPerParticipantValue) then
		return failure("INVALID_AMOUNT", "grantWaveStipend")
	end
	local amount = amountPerParticipantValue :: number
	local receiptKey = if validReceiptKey(receiptKeyValue) then receiptKeyValue :: string else nil
	if receiptKey == nil then
		return failure("INVALID_RECEIPT", "grantWaveStipend")
	end
	local existing, receiptError =
		receiptForMutation(data, receiptKey, "WaveStipend", nil, amount, nil, "grantWaveStipend")
	if receiptError ~= nil then
		return Result.err(receiptError)
	end
	if existing ~= nil then
		local participantCount = 0
		for _, userId in data.orderedUserIds do
			if data.participantsByUserId[userId].active then
				participantCount += 1
			end
		end
		return Result.ok(table.freeze({
			applied = false,
			receiptKey = receiptKey,
			amountPerParticipant = amount,
			participantCount = participantCount,
			totalCredited = 0,
			snapshots = listSnapshotsTrusted(data),
		}))
	end

	local totalGrant = 0
	local participantCount = 0
	for _, userId in data.orderedUserIds do
		local participant = data.participantsByUserId[userId]
		if participant.active and participant.revision >= Validation.MAX_SAFE_INTEGER then
			return failure("REVISION_EXHAUSTED", "grantWaveStipend")
		end
		if
			participant.active
			and (checkedAdd(participant.balance, amount) == nil or checkedAdd(participant.waveStipends, amount) == nil)
		then
			return failure("ARITHMETIC_OVERFLOW", "grantWaveStipend")
		end
		if participant.active then
			participantCount += 1
			local nextTotalGrant = checkedAdd(totalGrant, amount)
			if nextTotalGrant == nil then
				return failure("ARITHMETIC_OVERFLOW", "grantWaveStipend")
			end
			totalGrant = nextTotalGrant
		end
	end
	local nextTotalBalance = checkedAdd(data.totalBalance, totalGrant)
	local nextTotalStipends = checkedAdd(data.totalWaveStipendBattleCash, totalGrant)
	if nextTotalBalance == nil or nextTotalStipends == nil then
		return failure("ARITHMETIC_OVERFLOW", "grantWaveStipend")
	end

	for _, userId in data.orderedUserIds do
		local participant = data.participantsByUserId[userId]
		if participant.active then
			participant.balance += amount
			participant.waveStipends += amount
			participant.revision += 1
		end
	end
	data.totalBalance = nextTotalBalance
	data.totalWaveStipendBattleCash = nextTotalStipends
	recordReceipt(data, receiptKey, "WaveStipend", nil, amount, nil, nil, nil)
	return Result.ok(table.freeze({
		applied = true,
		receiptKey = receiptKey,
		amountPerParticipant = amount,
		participantCount = participantCount,
		totalCredited = totalGrant,
		snapshots = listSnapshotsTrusted(data),
	}))
end

function Methods.credit(
	self: Ledger,
	userIdValue: unknown,
	amountValue: unknown,
	receiptKeyValue: unknown
): Result.Result<BalanceMutation, LedgerError>
	local data = requireData(self)
	local stateError = requireActive(data, "credit")
	if stateError ~= nil then
		return Result.err(stateError)
	end
	if not validNonnegativeAmount(amountValue) then
		return failure("INVALID_AMOUNT", "credit")
	end
	if not validReceiptKey(receiptKeyValue) then
		return failure("INVALID_RECEIPT", "credit")
	end
	local participant, participantError = participantFor(data, userIdValue, "credit")
	if participant == nil then
		return Result.err(participantError :: LedgerError)
	end
	return creditFixed(data, participant, amountValue :: number, receiptKeyValue :: string, "Credit", "credit")
end

function Methods.refund(
	self: Ledger,
	userIdValue: unknown,
	amountValue: unknown,
	receiptKeyValue: unknown
): Result.Result<BalanceMutation, LedgerError>
	local data = requireData(self)
	local stateError = requireActive(data, "refund")
	if stateError ~= nil then
		return Result.err(stateError)
	end
	if not validNonnegativeAmount(amountValue) then
		return failure("INVALID_AMOUNT", "refund")
	end
	if not validReceiptKey(receiptKeyValue) then
		return failure("INVALID_RECEIPT", "refund")
	end
	local participant, participantError = participantFor(data, userIdValue, "refund")
	if participant == nil then
		return Result.err(participantError :: LedgerError)
	end
	return creditFixed(data, participant, amountValue :: number, receiptKeyValue :: string, "Refund", "refund")
end

function Methods.getStats(self: Ledger): Stats
	local data = requireData(self)
	return table.freeze({
		state = data.state,
		matchId = data.matchId,
		participantCount = #data.orderedUserIds,
		receiptCount = data.receiptCount,
		outstandingSpendCount = data.outstandingSpendCount,
		prepareCount = data.prepareCount,
		commitCount = data.commitCount,
		abortCount = data.abortCount,
		totalBalance = data.totalBalance,
		totalReserved = data.totalReserved,
		totalStartingBattleCash = data.totalStartingBattleCash,
		totalSpentBattleCash = data.totalSpentBattleCash,
		totalDamageHealthRemoved = data.totalDamageHealthRemoved,
		totalDamageIncomeBattleCash = data.totalDamageIncomeBattleCash,
		totalWaveStipendBattleCash = data.totalWaveStipendBattleCash,
		totalCreditedBattleCash = data.totalCreditedBattleCash,
		totalRefundedBattleCash = data.totalRefundedBattleCash,
	})
end

local function clearData(data: LedgerData)
	for token in data.tokens do
		local tokenData = TOKEN_DATA[token]
		if tokenData ~= nil then
			tokenData.active = false
		end
		TOKEN_DATA[token] = nil
	end
	table.clear(data.tokens)
	table.clear(data.receipts)
	table.clear(data.participantsByUserId)
	table.clear(data.orderedUserIds)
	table.clear(data.issuedUserIds)
	data.state = "Cleaned"
	data.matchId = nil
	data.startingBattleCash = 0
	data.damageNumerator = 0
	data.damageDenominator = 0
	data.receiptCount = 0
	data.outstandingSpendCount = 0
	data.prepareCount = 0
	data.commitCount = 0
	data.abortCount = 0
	data.totalBalance = 0
	data.totalReserved = 0
	data.totalStartingBattleCash = 0
	data.totalSpentBattleCash = 0
	data.totalDamageHealthRemoved = 0
	data.totalDamageIncomeBattleCash = 0
	data.totalWaveStipendBattleCash = 0
	data.totalCreditedBattleCash = 0
	data.totalRefundedBattleCash = 0
end

function Methods.cleanup(self: Ledger): Result.Result<boolean, LedgerError>
	local data = requireData(self)
	if data.state == "Cleaned" then
		return Result.ok(false)
	end
	clearData(data)
	return Result.ok(true)
end

function BattleCashLedger.new(
	matchIdValue: unknown,
	startingBattleCashValue: unknown,
	damageNumeratorValue: unknown,
	damageDenominatorValue: unknown
): Result.Result<Ledger, LedgerError>
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if not matchIdResult.ok then
		return failure("INVALID_MATCH_ID", "new")
	end
	if not validNonnegativeAmount(startingBattleCashValue) then
		return failure("INVALID_STARTING_BALANCE", "new")
	end
	if
		type(damageNumeratorValue) ~= "number"
		or not Validation.isSafeInteger(damageNumeratorValue :: number)
		or (damageNumeratorValue :: number) < 1
		or (damageNumeratorValue :: number) > MAX_DAMAGE_RATE_COMPONENT
		or type(damageDenominatorValue) ~= "number"
		or not Validation.isSafeInteger(damageDenominatorValue :: number)
		or (damageDenominatorValue :: number) < 1
		or (damageDenominatorValue :: number) > MAX_DAMAGE_RATE_COMPONENT
	then
		return failure("INVALID_DAMAGE_RATE", "new")
	end
	local ledger = setmetatable({}, Methods) :: Ledger
	table.freeze(ledger)
	LEDGER_DATA[ledger] = {
		state = "Active",
		matchId = matchIdResult.value,
		startingBattleCash = startingBattleCashValue :: number,
		damageNumerator = damageNumeratorValue :: number,
		damageDenominator = damageDenominatorValue :: number,
		participantsByUserId = {},
		orderedUserIds = {},
		issuedUserIds = {},
		receipts = {},
		receiptCount = 0,
		tokens = {},
		outstandingSpendCount = 0,
		prepareCount = 0,
		commitCount = 0,
		abortCount = 0,
		totalBalance = 0,
		totalReserved = 0,
		totalStartingBattleCash = 0,
		totalSpentBattleCash = 0,
		totalDamageHealthRemoved = 0,
		totalDamageIncomeBattleCash = 0,
		totalWaveStipendBattleCash = 0,
		totalCreditedBattleCash = 0,
		totalRefundedBattleCash = 0,
	}
	return Result.ok(ledger)
end

table.freeze(Methods)
return table.freeze(BattleCashLedger)
