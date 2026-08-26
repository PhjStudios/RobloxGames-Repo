--!strict

local DifficultySchema = require(script.Parent.DifficultySchema)
local SchemaPrimitives = require(script.Parent.SchemaPrimitives)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

local ROOT_PATH: { Validation.PathSegment } = { "Economy" }

local ECONOMY_FIELDS: { [string]: boolean } = table.freeze({
	difficultyRules = true,
	sellRefund = true,
	version = true,
})

local ECONOMY_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	balance = true,
	balances = true,
	battleCashBalances = true,
	goldBalances = true,
	players = true,
	receipts = true,
	transactions = true,
})

local SELL_REFUND_FIELDS: { [string]: boolean } = table.freeze({
	basisPoints = true,
	rounding = true,
})

local SELL_REFUND_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	currentRefund = true,
	placedTower = true,
	totalInvestment = true,
})

local DIFFICULTY_RULE_FIELDS: { [string]: boolean } = table.freeze({
	damageIncome = true,
	difficultyId = true,
	startingBattleCash = true,
	waveRewards = true,
})

local DIFFICULTY_RULE_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	currentBalance = true,
	earnedBattleCash = true,
	ownerUserId = true,
	spentBattleCash = true,
})

local DAMAGE_INCOME_FIELDS: { [string]: boolean } = table.freeze({
	accrualScope = true,
	battleCashNumerator = true,
	healthRemovedDenominator = true,
	rounding = true,
})

local DAMAGE_INCOME_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	creditedDamage = true,
	fractionalRemainder = true,
	ownerUserId = true,
})

local WAVE_REWARD_SET_FIELDS: { [string]: boolean } = table.freeze({
	final = true,
	milestone = true,
	standard = true,
})

local WAVE_REWARD_FIELDS: { [string]: boolean } = table.freeze({
	battleCashStipendPerActivePlayer = true,
	persistentGold = true,
})

local WAVE_REWARD_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	awarded = true,
	claimed = true,
	recipients = true,
})

local PERSISTENT_GOLD_FIELDS: { [string]: boolean } = table.freeze({
	baseAmountPerEligiblePlayer = true,
})

local PERSISTENT_GOLD_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	claimState = true,
	receiptId = true,
})

local NO_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({})

local ROUNDING_MODES: { [string]: boolean } = table.freeze({
	Floor = true,
})

local ACCRUAL_SCOPES: { [string]: boolean } = table.freeze({
	PerPlayerMatch = true,
})

local PROVISIONAL_SELL_REFUND_BASIS_POINTS = 7_000
local BASIS_POINTS_PER_WHOLE = 10_000
local MAX_DAMAGE_RATE_COMPONENT = 1_000_000

local validatedConfigurations: { [ConfigTypes.EconomyConfiguration]: boolean } = setmetatable({}, {
	__mode = "k",
}) :: any

local EconomySchema = {
	PROVISIONAL_SELL_REFUND_BASIS_POINTS = PROVISIONAL_SELL_REFUND_BASIS_POINTS,
	BASIS_POINTS_PER_WHOLE = BASIS_POINTS_PER_WHOLE,
	MAX_DAMAGE_RATE_COMPONENT = MAX_DAMAGE_RATE_COMPONENT,
}

local function requiredEnum(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment },
	allowedValues: { [string]: boolean },
	label: string
): (string?, Validation.Issue?)
	local value, missingIssue = Validation.getRequiredField(record, fieldName, path)
	if missingIssue ~= nil then
		return nil, missingIssue
	end

	local fieldPath = Validation.appendPath(path, fieldName)
	if type(value) ~= "string" then
		return nil, Validation.issueWithType("INVALID_TYPE", fieldPath, `{label} must be a string`, value)
	end
	if allowedValues[value] ~= true then
		return nil, Validation.issue("INVALID_ENUM", fieldPath, `{label} is not recognized`)
	end

	return value, nil
end

local function greatestCommonDivisor(first: number, second: number): number
	local left = first
	local right = second
	while right ~= 0 do
		left, right = right, left % right
	end
	return left
end

local function validateSellRefund(
	value: unknown,
	path: { Validation.PathSegment }
): (ConfigTypes.SellRefundConfiguration?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, SELL_REFUND_FIELDS, SELL_REFUND_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local basisPoints, basisPointsIssue =
		SchemaPrimitives.boundedInteger(record :: Validation.RawObject, "basisPoints", path, 0, BASIS_POINTS_PER_WHOLE)
	if basisPointsIssue ~= nil then
		return nil, basisPointsIssue
	end

	local rounding, roundingIssue =
		requiredEnum(record :: Validation.RawObject, "rounding", path, ROUNDING_MODES, "Rounding mode")
	if roundingIssue ~= nil then
		return nil, roundingIssue
	end

	return table.freeze({
		basisPoints = basisPoints :: number,
		rounding = rounding :: ConfigTypes.CurrencyRoundingMode,
	}),
		nil
end

local function validateDamageIncome(
	value: unknown,
	path: { Validation.PathSegment }
): (ConfigTypes.DamageIncomeConfiguration?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, DAMAGE_INCOME_FIELDS, DAMAGE_INCOME_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local numerator, numeratorIssue = SchemaPrimitives.boundedInteger(
		record :: Validation.RawObject,
		"battleCashNumerator",
		path,
		1,
		MAX_DAMAGE_RATE_COMPONENT
	)
	if numeratorIssue ~= nil then
		return nil, numeratorIssue
	end

	local denominator, denominatorIssue = SchemaPrimitives.boundedInteger(
		record :: Validation.RawObject,
		"healthRemovedDenominator",
		path,
		1,
		MAX_DAMAGE_RATE_COMPONENT
	)
	if denominatorIssue ~= nil then
		return nil, denominatorIssue
	end

	if greatestCommonDivisor(numerator :: number, denominator :: number) ~= 1 then
		return nil,
			Validation.issue(
				"INVALID_ORDER",
				Validation.appendPath(path, "healthRemovedDenominator"),
				"Damage-income rate must use a reduced rational representation"
			)
	end

	local rounding, roundingIssue =
		requiredEnum(record :: Validation.RawObject, "rounding", path, ROUNDING_MODES, "Rounding mode")
	if roundingIssue ~= nil then
		return nil, roundingIssue
	end

	local accrualScope, accrualScopeIssue =
		requiredEnum(record :: Validation.RawObject, "accrualScope", path, ACCRUAL_SCOPES, "Accrual scope")
	if accrualScopeIssue ~= nil then
		return nil, accrualScopeIssue
	end

	return table.freeze({
		battleCashNumerator = numerator :: number,
		healthRemovedDenominator = denominator :: number,
		rounding = rounding :: ConfigTypes.CurrencyRoundingMode,
		accrualScope = accrualScope :: ConfigTypes.DamageAccrualScope,
	}),
		nil
end

local function validatePersistentGold(
	value: unknown,
	path: { Validation.PathSegment }
): (ConfigTypes.PersistentGoldRewardMetadata?, Validation.Issue?)
	local record, recordIssue =
		Validation.readObject(value, path, PERSISTENT_GOLD_FIELDS, PERSISTENT_GOLD_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local amount, amountIssue =
		SchemaPrimitives.nonNegativeInteger(record :: Validation.RawObject, "baseAmountPerEligiblePlayer", path)
	if amountIssue ~= nil then
		return nil, amountIssue
	end

	return table.freeze({
		baseAmountPerEligiblePlayer = amount :: number,
	}), nil
end

local function validateWaveReward(
	value: unknown,
	path: { Validation.PathSegment }
): (ConfigTypes.WaveRewardEconomyDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, WAVE_REWARD_FIELDS, WAVE_REWARD_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local stipend, stipendIssue =
		SchemaPrimitives.nonNegativeInteger(record :: Validation.RawObject, "battleCashStipendPerActivePlayer", path)
	if stipendIssue ~= nil then
		return nil, stipendIssue
	end

	local rawPersistentGold, persistentGoldMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "persistentGold", path)
	if persistentGoldMissing ~= nil then
		return nil, persistentGoldMissing
	end
	local persistentGold, persistentGoldIssue =
		validatePersistentGold(rawPersistentGold, Validation.appendPath(path, "persistentGold"))
	if persistentGoldIssue ~= nil then
		return nil, persistentGoldIssue
	end

	return table.freeze({
		battleCashStipendPerActivePlayer = stipend :: number,
		persistentGold = persistentGold :: ConfigTypes.PersistentGoldRewardMetadata,
	}),
		nil
end

local function validateWaveRewards(
	value: unknown,
	path: { Validation.PathSegment }
): (ConfigTypes.WaveRewardEconomySet?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, WAVE_REWARD_SET_FIELDS, NO_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawStandard, standardMissing = Validation.getRequiredField(record :: Validation.RawObject, "standard", path)
	if standardMissing ~= nil then
		return nil, standardMissing
	end
	local standard, standardIssue = validateWaveReward(rawStandard, Validation.appendPath(path, "standard"))
	if standardIssue ~= nil then
		return nil, standardIssue
	end

	local rawMilestone, milestoneMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "milestone", path)
	if milestoneMissing ~= nil then
		return nil, milestoneMissing
	end
	local milestone, milestoneIssue = validateWaveReward(rawMilestone, Validation.appendPath(path, "milestone"))
	if milestoneIssue ~= nil then
		return nil, milestoneIssue
	end

	local rawFinal, finalMissing = Validation.getRequiredField(record :: Validation.RawObject, "final", path)
	if finalMissing ~= nil then
		return nil, finalMissing
	end
	local final, finalIssue = validateWaveReward(rawFinal, Validation.appendPath(path, "final"))
	if finalIssue ~= nil then
		return nil, finalIssue
	end

	return table.freeze({
		standard = standard :: ConfigTypes.WaveRewardEconomyDefinition,
		milestone = milestone :: ConfigTypes.WaveRewardEconomyDefinition,
		final = final :: ConfigTypes.WaveRewardEconomyDefinition,
	}),
		nil
end

local function validateDifficultyRule(
	value: unknown,
	path: { Validation.PathSegment },
	difficulties: ConfigTypes.DifficultyCatalog,
	firstIdPaths: { [string]: string }
): (ConfigTypes.DifficultyEconomyDefinition?, Validation.Issue?)
	local record, recordIssue =
		Validation.readObject(value, path, DIFFICULTY_RULE_FIELDS, DIFFICULTY_RULE_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawDifficultyId, difficultyIdMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "difficultyId", path)
	if difficultyIdMissing ~= nil then
		return nil, difficultyIdMissing
	end
	local difficultyIdPath = Validation.appendPath(path, "difficultyId")
	local difficultyIdResult = Ids.validateDifficultyId(rawDifficultyId)
	if not difficultyIdResult.ok then
		return nil,
			Validation.issueWithCause(
				"INVALID_ID",
				difficultyIdPath,
				"Economy difficulty reference is invalid",
				difficultyIdResult.error.code
			)
	end
	local difficultyId = difficultyIdResult.value

	local firstPath = firstIdPaths[difficultyId]
	if firstPath ~= nil then
		return nil,
			Validation.issueWithRelated(
				"DUPLICATE_VALUE",
				difficultyIdPath,
				"Difficulty economy rule duplicates an earlier reference",
				firstPath
			)
	end
	firstIdPaths[difficultyId] = Validation.renderPath(difficultyIdPath)

	local difficultyById = rawget(difficulties :: any, "byId")
	if rawget(difficultyById, difficultyId) == nil then
		return nil,
			Validation.issue(
				"INVALID_REFERENCE",
				difficultyIdPath,
				"Difficulty economy rule references an unknown difficulty"
			)
	end

	local startingBattleCash, startingCashIssue =
		SchemaPrimitives.nonNegativeInteger(record :: Validation.RawObject, "startingBattleCash", path)
	if startingCashIssue ~= nil then
		return nil, startingCashIssue
	end

	local rawDamageIncome, damageIncomeMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "damageIncome", path)
	if damageIncomeMissing ~= nil then
		return nil, damageIncomeMissing
	end
	local damageIncome, damageIncomeIssue =
		validateDamageIncome(rawDamageIncome, Validation.appendPath(path, "damageIncome"))
	if damageIncomeIssue ~= nil then
		return nil, damageIncomeIssue
	end

	local rawWaveRewards, waveRewardsMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "waveRewards", path)
	if waveRewardsMissing ~= nil then
		return nil, waveRewardsMissing
	end
	local waveRewards, waveRewardsIssue =
		validateWaveRewards(rawWaveRewards, Validation.appendPath(path, "waveRewards"))
	if waveRewardsIssue ~= nil then
		return nil, waveRewardsIssue
	end

	return table.freeze({
		difficultyId = difficultyId,
		startingBattleCash = startingBattleCash :: number,
		damageIncome = damageIncome :: ConfigTypes.DamageIncomeConfiguration,
		waveRewards = waveRewards :: ConfigTypes.WaveRewardEconomySet,
	}),
		nil
end

function EconomySchema.validateConfiguration(
	value: unknown,
	difficulties: ConfigTypes.DifficultyCatalog
): Result.Result<ConfigTypes.EconomyConfiguration, Validation.Issue>
	if not DifficultySchema.isValidatedCatalog(difficulties) then
		return Result.err(
			Validation.issue(
				"INVALID_REFERENCE",
				{ "DifficultyCatalog" },
				"Expected a difficulty catalog validated by DifficultySchema"
			)
		)
	end

	local record, recordIssue = Validation.readObject(value, ROOT_PATH, ECONOMY_FIELDS, ECONOMY_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return Result.err(recordIssue)
	end

	local version, versionIssue = SchemaPrimitives.positiveInteger(record :: Validation.RawObject, "version", ROOT_PATH)
	if versionIssue ~= nil then
		return Result.err(versionIssue)
	end

	local rawSellRefund, sellRefundMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "sellRefund", ROOT_PATH)
	if sellRefundMissing ~= nil then
		return Result.err(sellRefundMissing)
	end
	local sellRefund, sellRefundIssue =
		validateSellRefund(rawSellRefund, Validation.appendPath(ROOT_PATH, "sellRefund"))
	if sellRefundIssue ~= nil then
		return Result.err(sellRefundIssue)
	end

	local rawDifficultyRules, difficultyRulesMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "difficultyRules", ROOT_PATH)
	if difficultyRulesMissing ~= nil then
		return Result.err(difficultyRulesMissing)
	end
	local difficultyRulesPath = Validation.appendPath(ROOT_PATH, "difficultyRules")
	local rawRules, rulesIssue =
		Validation.readArray(rawDifficultyRules, difficultyRulesPath, Validation.MAX_CATALOG_ENTRIES)
	if rulesIssue ~= nil then
		return Result.err(rulesIssue)
	end

	local ordered: { ConfigTypes.DifficultyEconomyDefinition } = {}
	local byDifficultyId: { [Ids.DifficultyId]: ConfigTypes.DifficultyEconomyDefinition } = {}
	local firstIdPaths: { [string]: string } = {}
	for index = 1, #(rawRules :: { unknown }) do
		local rule, ruleIssue = validateDifficultyRule(
			(rawRules :: { unknown })[index],
			Validation.appendPath(difficultyRulesPath, index),
			difficulties,
			firstIdPaths
		)
		if ruleIssue ~= nil then
			return Result.err(ruleIssue)
		end

		local canonicalRule = rule :: ConfigTypes.DifficultyEconomyDefinition
		table.insert(ordered, canonicalRule)
		byDifficultyId[canonicalRule.difficultyId] = canonicalRule
	end

	local difficultyOrdered = rawget(difficulties :: any, "ordered") :: { ConfigTypes.DifficultyDefinition }
	for index = 1, #difficultyOrdered do
		local difficulty = difficultyOrdered[index]
		if byDifficultyId[difficulty.id] == nil then
			return Result.err(
				Validation.issue(
					"INVALID_REFERENCE",
					{ "Difficulties", index, "id" },
					"Validated difficulty has no economy rule"
				)
			)
		end
	end

	local configuration: ConfigTypes.EconomyConfiguration = table.freeze({
		version = version :: ConfigTypes.ConfigurationVersion,
		sellRefund = sellRefund :: ConfigTypes.SellRefundConfiguration,
		ordered = table.freeze(ordered),
		byDifficultyId = table.freeze(byDifficultyId),
	})
	validatedConfigurations[configuration] = true
	return Result.ok(configuration)
end

function EconomySchema.isValidatedConfiguration(value: unknown): boolean
	return type(value) == "table" and validatedConfigurations[value :: any] == true
end

return table.freeze(EconomySchema)
