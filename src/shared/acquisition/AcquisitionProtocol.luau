--!strict

local BannerSchema = require(script.Parent.Parent.config.BannerSchema)
local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type CurrencyPolicy = "EarnOnlyGold"

export type AuthoredBannerPolicy = {
	bannerId: string,
	bannerVersion: number,
	available: boolean,
	currencyPolicy: CurrencyPolicy,
	policyDisclosure: string,
}

export type AuthoredConfiguration = {
	version: number,
	banners: { AuthoredBannerPolicy },
}

export type PityBannerDefinition = ConfigTypes.BannerDefinition & {
	pityRule: ConfigTypes.BannerPityRuleDefinition,
}

export type AuthenticatedBannerPolicy = AuthoredBannerPolicy & {
	definition: PityBannerDefinition,
}

export type AuthenticatedConfiguration = {
	version: number,
	ordered: { AuthenticatedBannerPolicy },
	byBannerId: { [string]: AuthenticatedBannerPolicy },
}

export type OddsView = {
	towerId: string,
	probabilityPercent: number,
}

export type BannerView = {
	bannerId: string,
	bannerVersion: number,
	displayName: string,
	available: boolean,
	currencyPolicy: CurrencyPolicy,
	policyDisclosure: string,
	onePullCost: number,
	tenPullCost: number,
	odds: { OddsView },
	hardPityPullCount: number,
	guaranteedTowerId: string,
	currentPityCount: number,
	gold: number,
	profileRevision: number,
}

export type PullIntent = {
	transactionId: string,
	expectedRevision: number,
	bannerId: string,
	bannerVersion: number,
	quantity: number,
}

export type PullResult = {
	index: number,
	unitId: string,
	towerId: string,
	isNew: boolean,
}

export type PullReceipt = {
	transactionId: string,
	bannerId: string,
	bannerVersion: number,
	quantity: number,
	cost: number,
	goldBefore: number,
	goldAfter: number,
	pityBefore: number,
	pityAfter: number,
	profileRevision: number,
	results: { PullResult },
}

local MAX_PULL_QUANTITY = 10
local MAX_POLICY_TEXT_BYTES = 240
local MAX_DISPLAY_NAME_BYTES = 80
local MAX_OUTCOMES = PayloadValidation.MAX_ARRAY_ITEMS

local POSITIVE_SAFE_INTEGER = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)
local NONNEGATIVE_SAFE_INTEGER = PayloadValidation.integer(0, Validation.MAX_SAFE_INTEGER)
local PROBABILITY = PayloadValidation.number(0.000000001, 100)

local ODDS_VIEW = PayloadValidation.record({
	towerId = PayloadValidation.id("tower"),
	probabilityPercent = PROBABILITY,
})

local BANNER_VIEW = PayloadValidation.record({
	bannerId = PayloadValidation.id("banner"),
	bannerVersion = POSITIVE_SAFE_INTEGER,
	displayName = PayloadValidation.string(MAX_DISPLAY_NAME_BYTES, 1),
	available = PayloadValidation.boolean(),
	currencyPolicy = PayloadValidation.enum({ "EarnOnlyGold" }),
	policyDisclosure = PayloadValidation.string(MAX_POLICY_TEXT_BYTES, 1),
	onePullCost = POSITIVE_SAFE_INTEGER,
	tenPullCost = POSITIVE_SAFE_INTEGER,
	odds = PayloadValidation.array(ODDS_VIEW, MAX_OUTCOMES, 1),
	hardPityPullCount = POSITIVE_SAFE_INTEGER,
	guaranteedTowerId = PayloadValidation.id("tower"),
	currentPityCount = NONNEGATIVE_SAFE_INTEGER,
	gold = NONNEGATIVE_SAFE_INTEGER,
	profileRevision = POSITIVE_SAFE_INTEGER,
})

local PULL_INTENT = PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	expectedRevision = POSITIVE_SAFE_INTEGER,
	bannerId = PayloadValidation.id("banner"),
	bannerVersion = POSITIVE_SAFE_INTEGER,
	quantity = PayloadValidation.integer(1, MAX_PULL_QUANTITY),
})

local PULL_RESULT = PayloadValidation.record({
	index = PayloadValidation.integer(1, MAX_PULL_QUANTITY),
	unitId = PayloadValidation.id("unit"),
	towerId = PayloadValidation.id("tower"),
	isNew = PayloadValidation.boolean(),
})

local PULL_RECEIPT = PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	bannerId = PayloadValidation.id("banner"),
	bannerVersion = POSITIVE_SAFE_INTEGER,
	quantity = PayloadValidation.integer(1, MAX_PULL_QUANTITY),
	cost = POSITIVE_SAFE_INTEGER,
	goldBefore = NONNEGATIVE_SAFE_INTEGER,
	goldAfter = NONNEGATIVE_SAFE_INTEGER,
	pityBefore = NONNEGATIVE_SAFE_INTEGER,
	pityAfter = NONNEGATIVE_SAFE_INTEGER,
	profileRevision = POSITIVE_SAFE_INTEGER,
	results = PayloadValidation.array(PULL_RESULT, MAX_PULL_QUANTITY, 1),
})

local BannerViewSchema = PayloadValidation.schema(BANNER_VIEW)
local PullIntentSchema = PayloadValidation.schema(PULL_INTENT)
local PullReceiptSchema = PayloadValidation.schema(PULL_RECEIPT)

local AUTHENTIC_CONFIGURATIONS = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }

local AcquisitionProtocol = {
	MAX_PULL_QUANTITY = MAX_PULL_QUANTITY,
	MAX_POLICY_TEXT_BYTES = MAX_POLICY_TEXT_BYTES,
	BannerViewSchema = BannerViewSchema,
	PullIntentSchema = PullIntentSchema,
	PullReceiptSchema = PullReceiptSchema,
}

local function issue(
	code: Validation.Code,
	path: { Validation.PathSegment },
	message: string
): Result.Failure<Validation.Issue>
	return Result.err(Validation.issue(code, path, message))
end

local function isDenseArray(value: unknown, maximum: number): ({ unknown }?, Validation.Issue?)
	return Validation.readArray(value, { "Acquisition", "banners" }, maximum)
end

function AcquisitionProtocol.validateConfiguration(
	value: unknown,
	banners: ConfigTypes.BannerCatalog
): Result.Result<AuthenticatedConfiguration, Validation.Issue>
	if not BannerSchema.isValidatedCatalog(banners) then
		return issue("INVALID_REFERENCE", { "BannerCatalog" }, "Expected an authenticated banner catalog")
	end
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return issue("INVALID_TYPE", { "Acquisition" }, "Acquisition configuration must be a plain table")
	end
	local source = value :: { [any]: unknown }
	local fieldCount = 0
	for key in next, source do
		fieldCount += 1
		if (key ~= "version" and key ~= "banners") or fieldCount > 2 then
			return issue("UNKNOWN_FIELD", { "Acquisition" }, "Acquisition configuration contains an unknown field")
		end
	end
	local version = rawget(source, "version")
	if type(version) ~= "number" or not Validation.isSafeInteger(version) or version ~= 1 then
		return issue("UNSUPPORTED_VERSION", { "Acquisition", "version" }, "Acquisition version is unsupported")
	end
	local rawPolicies, arrayIssue = isDenseArray(rawget(source, "banners"), Validation.MAX_CATALOG_ENTRIES)
	if arrayIssue ~= nil then
		return Result.err(arrayIssue)
	end
	if #(rawPolicies :: { unknown }) ~= #banners.ordered then
		return issue(
			"INVALID_TOTAL",
			{ "Acquisition", "banners" },
			"Every authored banner must have exactly one acquisition policy"
		)
	end

	local ordered: { AuthenticatedBannerPolicy } = {}
	local byBannerId: { [string]: AuthenticatedBannerPolicy } = {}
	for index, rawPolicy in rawPolicies :: { unknown } do
		if type(rawPolicy) ~= "table" or getmetatable(rawPolicy :: any) ~= nil then
			return issue("INVALID_TYPE", { "Acquisition", "banners", index }, "Banner policy must be a plain table")
		end
		local policy = rawPolicy :: { [any]: unknown }
		local allowed = {
			bannerId = true,
			bannerVersion = true,
			available = true,
			currencyPolicy = true,
			policyDisclosure = true,
		}
		local policyFieldCount = 0
		for key in next, policy do
			policyFieldCount += 1
			if type(key) ~= "string" or not allowed[key] or policyFieldCount > 5 then
				return issue(
					"UNKNOWN_FIELD",
					{ "Acquisition", "banners", index },
					"Banner policy contains an unknown field"
				)
			end
		end
		if policyFieldCount ~= 5 then
			return issue("MISSING_FIELD", { "Acquisition", "banners", index }, "Banner policy is incomplete")
		end
		local bannerId = rawget(policy, "bannerId")
		local bannerVersion = rawget(policy, "bannerVersion")
		local available = rawget(policy, "available")
		local currencyPolicy = rawget(policy, "currencyPolicy")
		local disclosure = rawget(policy, "policyDisclosure")
		local definition = if type(bannerId) == "string" then banners.byId[bannerId :: any] else nil
		if definition == nil or definition ~= banners.ordered[index] then
			return issue(
				"INVALID_REFERENCE",
				{ "Acquisition", "banners", index, "bannerId" },
				"Banner policy must follow the authenticated banner order"
			)
		end
		if definition.pityRule == nil then
			return issue(
				"MISSING_FIELD",
				{ "Acquisition", "banners", index, "bannerId" },
				"An acquisition banner must define a validated hard-pity rule"
			)
		end
		if bannerVersion ~= definition.version then
			return issue(
				"INVALID_REFERENCE",
				{ "Acquisition", "banners", index, "bannerVersion" },
				"Banner policy version does not match its immutable definition"
			)
		end
		if type(available) ~= "boolean" then
			return issue(
				"INVALID_TYPE",
				{ "Acquisition", "banners", index, "available" },
				"Banner availability must be a boolean"
			)
		end
		if currencyPolicy ~= "EarnOnlyGold" then
			return issue(
				"INVALID_ENUM",
				{ "Acquisition", "banners", index, "currencyPolicy" },
				"Only the earn-only Gold policy is supported"
			)
		end
		if
			type(disclosure) ~= "string"
			or #disclosure < 1
			or #disclosure > MAX_POLICY_TEXT_BYTES
			or not Validation.isDisplayText(disclosure :: string, MAX_POLICY_TEXT_BYTES)
		then
			return issue(
				"INVALID_STRING",
				{ "Acquisition", "banners", index, "policyDisclosure" },
				"Policy disclosure must be bounded visible text"
			)
		end
		if byBannerId[definition.id] ~= nil then
			return issue(
				"DUPLICATE_VALUE",
				{ "Acquisition", "banners", index, "bannerId" },
				"Banner policy is duplicated"
			)
		end
		local authenticated: AuthenticatedBannerPolicy = table.freeze({
			bannerId = definition.id,
			bannerVersion = definition.version,
			available = available :: boolean,
			currencyPolicy = "EarnOnlyGold",
			policyDisclosure = disclosure :: string,
			definition = definition :: PityBannerDefinition,
		})
		table.insert(ordered, authenticated)
		byBannerId[definition.id] = authenticated
	end
	local configuration: AuthenticatedConfiguration = table.freeze({
		version = version :: number,
		ordered = table.freeze(ordered),
		byBannerId = table.freeze(byBannerId),
	})
	AUTHENTIC_CONFIGURATIONS[configuration] = true
	return Result.ok(configuration)
end

function AcquisitionProtocol.isAuthenticatedConfiguration(value: unknown): boolean
	return type(value) == "table" and AUTHENTIC_CONFIGURATIONS[value :: any] == true
end

function AcquisitionProtocol.validateBannerView(value: unknown): Result.Result<BannerView, Validation.Issue>
	local result = BannerViewSchema:validate(value)
	if not result.ok then
		return Result.err(result.error)
	end
	local view = result.value :: BannerView
	if view.currentPityCount >= view.hardPityPullCount then
		return issue("OUT_OF_RANGE", { "payload", "currentPityCount" }, "Pity count must remain below hard pity")
	end
	local total = 0
	local compensation = 0
	local seen: { [string]: boolean } = {}
	local guaranteedFound = false
	for index, outcome in view.odds do
		if seen[outcome.towerId] then
			return issue("DUPLICATE_VALUE", { "payload", "odds", index, "towerId" }, "Odds duplicate a tower")
		end
		seen[outcome.towerId] = true
		guaranteedFound = guaranteedFound or outcome.towerId == view.guaranteedTowerId
		local adjusted = outcome.probabilityPercent - compensation
		local nextTotal = total + adjusted
		compensation = (nextTotal - total) - adjusted
		total = nextTotal
	end
	if math.abs(total - 100) > 1e-9 or not guaranteedFound then
		return issue("INVALID_TOTAL", { "payload", "odds" }, "Displayed odds or pity target are inconsistent")
	end
	return Result.ok(view)
end

function AcquisitionProtocol.validatePullIntent(value: unknown): Result.Result<PullIntent, Validation.Issue>
	local result = PullIntentSchema:validate(value)
	if not result.ok then
		return Result.err(result.error)
	end
	local intent = result.value :: PullIntent
	if intent.quantity ~= 1 and intent.quantity ~= 10 then
		return issue("INVALID_ENUM", { "payload", "quantity" }, "Pull quantity must be one or ten")
	end
	return Result.ok(intent)
end

function AcquisitionProtocol.validatePullReceipt(value: unknown): Result.Result<PullReceipt, Validation.Issue>
	local result = PullReceiptSchema:validate(value)
	if not result.ok then
		return Result.err(result.error)
	end
	local receipt = result.value :: PullReceipt
	if receipt.quantity ~= 1 and receipt.quantity ~= 10 then
		return issue("INVALID_ENUM", { "payload", "quantity" }, "Pull quantity must be one or ten")
	end
	if #receipt.results ~= receipt.quantity then
		return issue("INVALID_TOTAL", { "payload", "results" }, "Pull results must match requested quantity")
	end
	if receipt.goldAfter > receipt.goldBefore or receipt.goldBefore - receipt.goldAfter ~= receipt.cost then
		return issue("INVALID_TOTAL", { "payload", "goldAfter" }, "Gold totals do not match the recorded cost")
	end
	local unitIds: { [string]: boolean } = {}
	for index, outcome in receipt.results do
		if outcome.index ~= index then
			return issue("INVALID_ORDER", { "payload", "results", index, "index" }, "Results must be ordered")
		end
		if unitIds[outcome.unitId] then
			return issue(
				"DUPLICATE_VALUE",
				{ "payload", "results", index, "unitId" },
				"One transaction cannot grant the same unit twice"
			)
		end
		unitIds[outcome.unitId] = true
	end
	return Result.ok(receipt)
end

return table.freeze(AcquisitionProtocol)
