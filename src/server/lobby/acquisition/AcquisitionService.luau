--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AcquisitionConfig = require(ReplicatedStorage.Shared.acquisition.AcquisitionConfig)
local AcquisitionProtocol = require(ReplicatedStorage.Shared.acquisition.AcquisitionProtocol)
local BannerRollPlanner = require(ReplicatedStorage.Shared.acquisition.BannerRollPlanner)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local InventoryProtocol = require(ReplicatedStorage.Shared.inventory.InventoryProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

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
}

export type UnitIdGenerator = {
	generate: (self: UnitIdGenerator, userId: number, transactionId: string, index: number) -> unknown,
}

export type Clock = {
	now: (self: Clock) -> unknown,
}

export type Operation = "new" | "getBannerView" | "pull"
export type ErrorCode =
	"INVALID_DEPENDENCIES"
	| "INVALID_USER_ID"
	| "INVALID_BANNER"
	| "INVALID_INTENT"
	| "BANNER_VERSION_MISMATCH"
	| "UNAVAILABLE"
	| "NOT_READY"
	| "PROFILE_INVALID"
	| "INSUFFICIENT_GOLD"
	| "INVENTORY_FULL"
	| "STALE_REVISION"
	| "TRANSACTION_CONFLICT"
	| "REVISION_EXHAUSTED"
	| "STATISTICS_EXHAUSTED"
	| "RNG_FAILED"
	| "UNIT_ID_FAILED"
	| "CLOCK_FAILED"
	| "CALLBACK_FAILED"

export type ServiceError = {
	code: ErrorCode,
	operation: Operation,
}

type ProfileSummary = {
	revision: number,
	gold: number,
	unitCount: number,
	copyCounts: { [string]: number },
	maximumSequence: number,
	pityCount: number,
}

type ServiceData = {
	profileOwner: ProfileOwner,
	configuration: ConfigTypes.CoreConfiguration,
	acquisition: AcquisitionProtocol.AuthenticatedConfiguration,
	planner: BannerRollPlanner.Planner,
	unitIds: UnitIdGenerator,
	clock: Clock,
}

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local MAX_GOLD = 1_000_000_000_000
local MAX_STATISTIC = 1_000_000_000_000

local AcquisitionService = {}

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<ServiceError>
	return Result.err(table.freeze({
		code = code,
		operation = operation,
	}))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_ACQUISITION_SERVICE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and value > 0 and Validation.isSafeInteger(value :: number)
end

local function ownerReady(data: ServiceData, userId: number): boolean
	local called, state = callNonYielding(data.profileOwner.getState, data.profileOwner, userId)
	return called and state == "Ready"
end

local function ownerErrorCode(value: unknown): ErrorCode
	local code = if type(value) == "table"
		then (rawget(value :: any, "reason") or rawget(value :: any, "code"))
		else value
	if code == "NOT_READY" or code == "PROFILE_NOT_READY" then
		return "NOT_READY"
	elseif code == "STALE_REVISION" or code == "STALE" then
		return "STALE_REVISION"
	elseif code == "RECEIPT_CONFLICT" or code == "TRANSACTION_CONFLICT" then
		return "TRANSACTION_CONFLICT"
	elseif code == "REVISION_EXHAUSTED" then
		return "REVISION_EXHAUSTED"
	elseif code == "PROFILE_INVALID" then
		return "PROFILE_INVALID"
	elseif code == "INSUFFICIENT_GOLD" then
		return "INSUFFICIENT_GOLD"
	elseif code == "INVENTORY_FULL" then
		return "INVENTORY_FULL"
	elseif code == "STATISTICS_EXHAUSTED" then
		return "STATISTICS_EXHAUSTED"
	elseif code == "RNG_FAILED" then
		return "RNG_FAILED"
	elseif code == "UNIT_ID_FAILED" then
		return "UNIT_ID_FAILED"
	elseif code == "CLOCK_FAILED" then
		return "CLOCK_FAILED"
	end
	return "UNAVAILABLE"
end

local function profileSummary(
	data: ServiceData,
	profile: any,
	policy: AcquisitionProtocol.AuthenticatedBannerPolicy
): ProfileSummary?
	if type(profile) ~= "table" or getmetatable(profile) ~= nil then
		return nil
	end
	local revision = rawget(profile, "revision")
	local gold = rawget(profile, "gold")
	local unitsValue = rawget(profile, "units")
	if
		type(revision) ~= "number"
		or not Validation.isSafeInteger(revision)
		or revision < 1
		or type(gold) ~= "number"
		or not Validation.isSafeInteger(gold)
		or gold < 0
		or gold > MAX_GOLD
		or type(unitsValue) ~= "table"
		or getmetatable(unitsValue :: any) ~= nil
	then
		return nil
	end

	local count = 0
	local maximumSequence = 0
	local copyCounts: { [string]: number } = {}
	for key, rawUnit in next, unitsValue :: { [any]: unknown } do
		count += 1
		if
			count > InventoryProtocol.MAX_UNITS
			or type(key) ~= "string"
			or type(rawUnit) ~= "table"
			or getmetatable(rawUnit :: any) ~= nil
		then
			return nil
		end
		local unit = rawUnit :: { [any]: unknown }
		local unitId = Ids.validateUnitId(rawget(unit, "unitId"))
		local towerId = Ids.validateTowerId(rawget(unit, "towerId"))
		local sequence = rawget(unit, "acquisitionSequence")
		if
			not unitId.ok
			or unitId.value ~= key
			or not towerId.ok
			or data.configuration.towers.byId[towerId.value] == nil
			or type(sequence) ~= "number"
			or not Validation.isSafeInteger(sequence)
			or sequence < 1
		then
			return nil
		end
		maximumSequence = math.max(maximumSequence, sequence :: number)
		copyCounts[towerId.value] = (copyCounts[towerId.value] or 0) + 1
	end
	if count < 1 then
		return nil
	end

	local pityCount = 0
	local pityMap = rawget(profile, "bannerPity")
	if type(pityMap) ~= "table" or getmetatable(pityMap :: any) ~= nil then
		return nil
	end
	local pityValue = rawget(pityMap, policy.bannerId)
	if pityValue ~= nil then
		if type(pityValue) ~= "table" or getmetatable(pityValue :: any) ~= nil then
			return nil
		end
		local pity = pityValue :: { [any]: unknown }
		local countValue = rawget(pity, "count")
		if
			rawget(pity, "bannerId") ~= policy.bannerId
			or rawget(pity, "bannerVersion") ~= policy.bannerVersion
			or type(countValue) ~= "number"
			or not Validation.isSafeInteger(countValue)
			or countValue < 0
			or countValue >= policy.definition.pityRule.hardPityPullCount
		then
			return nil
		end
		pityCount = countValue :: number
	end

	return {
		revision = revision :: number,
		gold = gold :: number,
		unitCount = count,
		copyCounts = copyCounts,
		maximumSequence = maximumSequence,
		pityCount = pityCount,
	}
end

local function readProfile(data: ServiceData, userId: number, operation: Operation): Result.Result<any, ServiceError>
	local called, readResult = callNonYielding(data.profileOwner.read, data.profileOwner, userId)
	if not called or type(readResult) ~= "table" then
		return failure("UNAVAILABLE", operation)
	end
	if (readResult :: any).ok ~= true then
		return failure(ownerErrorCode((readResult :: any).error), operation)
	end
	return Result.ok((readResult :: any).value)
end

local function pullCost(policy: AcquisitionProtocol.AuthenticatedBannerPolicy, quantity: number): number
	return if quantity == 1
		then policy.definition.pullOptions.onePull.goldCost
		else policy.definition.pullOptions.tenPull.goldCost
end

local function bannerView(
	policy: AcquisitionProtocol.AuthenticatedBannerPolicy,
	summary: ProfileSummary
): Result.Result<AcquisitionProtocol.BannerView, ServiceError>
	local odds: { AcquisitionProtocol.OddsView } = table.create(#policy.definition.outcomes)
	for index, outcome in policy.definition.outcomes do
		odds[index] = table.freeze({
			towerId = outcome.towerId,
			probabilityPercent = outcome.probabilityPercent,
		})
	end
	local pity = policy.definition.pityRule
	local view: AcquisitionProtocol.BannerView = table.freeze({
		bannerId = policy.bannerId,
		bannerVersion = policy.bannerVersion,
		displayName = policy.definition.displayName,
		available = policy.available,
		currencyPolicy = policy.currencyPolicy,
		policyDisclosure = policy.policyDisclosure,
		onePullCost = policy.definition.pullOptions.onePull.goldCost,
		tenPullCost = policy.definition.pullOptions.tenPull.goldCost,
		odds = table.freeze(odds),
		hardPityPullCount = pity.hardPityPullCount,
		guaranteedTowerId = pity.guaranteedTowerId,
		currentPityCount = summary.pityCount,
		gold = summary.gold,
		profileRevision = summary.revision,
	})
	local validated = AcquisitionProtocol.validateBannerView(view)
	if not validated.ok then
		return failure("PROFILE_INVALID", "getBannerView")
	end
	return Result.ok(validated.value)
end

function Methods.getBannerView(
	self: Service,
	userIdValue: unknown,
	bannerIdValue: unknown
): Result.Result<AcquisitionProtocol.BannerView, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "getBannerView")
	end
	if type(bannerIdValue) ~= "string" then
		return failure("INVALID_BANNER", "getBannerView")
	end
	local policy = data.acquisition.byBannerId[bannerIdValue]
	if policy == nil then
		return failure("INVALID_BANNER", "getBannerView")
	end
	local userId = userIdValue :: number
	if not ownerReady(data, userId) then
		return failure("NOT_READY", "getBannerView")
	end
	local profileResult = readProfile(data, userId, "getBannerView")
	if not profileResult.ok then
		return Result.err(profileResult.error)
	end
	local summary = profileSummary(data, profileResult.value, policy)
	if summary == nil then
		return failure("PROFILE_INVALID", "getBannerView")
	end
	return bannerView(policy, summary)
end

local function parsePityBefore(value: unknown, hardPity: number): number?
	if type(value) ~= "string" then
		return nil
	end
	local digits = string.match(value :: string, "^PULL_PITY_(%d+)$")
	local count = if digits == nil then nil else tonumber(digits)
	if count == nil or not Validation.isSafeInteger(count) or count < 0 or count >= hardPity then
		return nil
	end
	return count
end

local function receiptFromOwner(
	transactionId: string,
	policy: AcquisitionProtocol.AuthenticatedBannerPolicy,
	quantity: number,
	cost: number,
	ownerValue: unknown
): Result.Result<AcquisitionProtocol.PullReceipt, ServiceError>
	if type(ownerValue) ~= "table" then
		return failure("UNAVAILABLE", "pull")
	end
	local committedRevision = rawget(ownerValue :: any, "committedRevision")
	local stored = rawget(ownerValue :: any, "result")
	if
		type(committedRevision) ~= "number"
		or not Validation.isSafeInteger(committedRevision)
		or committedRevision < 1
		or type(stored) ~= "table"
	then
		return failure("UNAVAILABLE", "pull")
	end
	local storedRecord = stored :: { [any]: unknown }
	local pityBefore = parsePityBefore(rawget(storedRecord, "resultCode"), policy.definition.pityRule.hardPityPullCount)
	local goldAfter = rawget(storedRecord, "goldBalance")
	local pityAfter = rawget(storedRecord, "pityCount")
	local unitIds = rawget(storedRecord, "unitIds")
	local towerIds = rawget(storedRecord, "towerIds")
	local newFlags = rawget(storedRecord, "newFlags")
	if
		pityBefore == nil
		or type(goldAfter) ~= "number"
		or not Validation.isSafeInteger(goldAfter)
		or goldAfter < 0
		or goldAfter > MAX_GOLD - cost
		or type(pityAfter) ~= "number"
		or not Validation.isSafeInteger(pityAfter)
		or pityAfter < 0
		or pityAfter >= policy.definition.pityRule.hardPityPullCount
		or type(unitIds) ~= "table"
		or type(towerIds) ~= "table"
		or type(newFlags) ~= "table"
		or #unitIds ~= quantity
		or #towerIds ~= quantity
		or #newFlags ~= quantity
	then
		return failure("UNAVAILABLE", "pull")
	end

	local results: { AcquisitionProtocol.PullResult } = table.create(quantity)
	for index = 1, quantity do
		results[index] = table.freeze({
			index = index,
			unitId = (unitIds :: { any })[index],
			towerId = (towerIds :: { any })[index],
			isNew = (newFlags :: { any })[index],
		})
	end
	local receipt: AcquisitionProtocol.PullReceipt = table.freeze({
		transactionId = transactionId,
		bannerId = policy.bannerId,
		bannerVersion = policy.bannerVersion,
		quantity = quantity,
		cost = cost,
		goldBefore = (goldAfter :: number) + cost,
		goldAfter = goldAfter :: number,
		pityBefore = pityBefore,
		pityAfter = pityAfter :: number,
		profileRevision = committedRevision :: number,
		results = table.freeze(results),
	})
	local validated = AcquisitionProtocol.validatePullReceipt(receipt)
	if not validated.ok then
		return failure("UNAVAILABLE", "pull")
	end
	return Result.ok(validated.value)
end

function Methods.pull(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<AcquisitionProtocol.PullReceipt, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "pull")
	end
	local intentResult = AcquisitionProtocol.validatePullIntent(intentValue)
	if not intentResult.ok then
		return failure("INVALID_INTENT", "pull")
	end
	local intent = intentResult.value
	local policy = data.acquisition.byBannerId[intent.bannerId]
	if policy == nil then
		return failure("INVALID_BANNER", "pull")
	end
	if intent.bannerVersion ~= policy.bannerVersion then
		return failure("BANNER_VERSION_MISMATCH", "pull")
	end
	if not policy.available then
		return failure("UNAVAILABLE", "pull")
	end
	local userId = userIdValue :: number
	if not ownerReady(data, userId) then
		return failure("NOT_READY", "pull")
	end
	if intent.expectedRevision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED", "pull")
	end
	local cost = pullCost(policy, intent.quantity)
	local called, transaction = callNonYielding(
		data.profileOwner.transact,
		data.profileOwner,
		userId,
		intent.transactionId,
		intent.expectedRevision,
		"AcquisitionPull",
		`pull|{intent.bannerId}|{intent.bannerVersion}|{intent.quantity}`,
		function(profile: any): unknown
			local summary = profileSummary(data, profile, policy)
			if summary == nil then
				return Result.err("PROFILE_INVALID")
			end
			if summary.gold < cost then
				return Result.err("INSUFFICIENT_GOLD")
			end
			if summary.unitCount + intent.quantity > InventoryProtocol.MAX_UNITS then
				return Result.err("INVENTORY_FULL")
			end
			if summary.maximumSequence > Validation.MAX_SAFE_INTEGER - intent.quantity then
				return Result.err("PROFILE_INVALID")
			end
			local stats = rawget(profile, "stats")
			if type(stats) ~= "table" or getmetatable(stats :: any) ~= nil then
				return Result.err("PROFILE_INVALID")
			end
			local towersAcquired = rawget(stats, "towersAcquired")
			local chestsOpened = rawget(stats, "chestsOpened")
			if
				type(towersAcquired) ~= "number"
				or not Validation.isSafeInteger(towersAcquired)
				or towersAcquired < 0
				or towersAcquired > MAX_STATISTIC - intent.quantity
				or type(chestsOpened) ~= "number"
				or not Validation.isSafeInteger(chestsOpened)
				or chestsOpened < 0
				or chestsOpened >= MAX_STATISTIC
			then
				return Result.err("STATISTICS_EXHAUSTED")
			end

			local planResult = data.planner:plan(policy.bannerId, summary.pityCount, intent.quantity)
			if not planResult.ok then
				return Result.err("RNG_FAILED")
			end
			local plan = planResult.value
			local calledClock, acquiredAt = callNonYielding(data.clock.now, data.clock)
			if
				not calledClock
				or type(acquiredAt) ~= "number"
				or not Validation.isSafeInteger(acquiredAt)
				or acquiredAt < 0
			then
				return Result.err("CLOCK_FAILED")
			end

			local generated: { string } = table.create(intent.quantity)
			local generatedSet: { [string]: boolean } = {}
			local units = rawget(profile, "units") :: { [string]: any }
			for index = 1, intent.quantity do
				local generatedOk, unitIdValue =
					callNonYielding(data.unitIds.generate, data.unitIds, userId, intent.transactionId, index)
				local unitIdResult = Ids.validateUnitId(unitIdValue)
				if
					not generatedOk
					or not unitIdResult.ok
					or units[unitIdResult.value] ~= nil
					or generatedSet[unitIdResult.value]
				then
					return Result.err("UNIT_ID_FAILED")
				end
				generated[index] = unitIdResult.value
				generatedSet[unitIdResult.value] = true
			end

			local towerIds: { string } = table.create(intent.quantity)
			local newFlags: { boolean } = table.create(intent.quantity)
			local counts = table.clone(summary.copyCounts)
			for index, outcome in plan.outcomes do
				local previousCopies = counts[outcome.towerId] or 0
				counts[outcome.towerId] = previousCopies + 1
				towerIds[index] = outcome.towerId
				newFlags[index] = previousCopies == 0
				local unitId = generated[index]
				units[unitId] = {
					unitId = unitId,
					towerId = outcome.towerId,
					favorite = false,
					locked = false,
					acquiredAt = acquiredAt,
					acquisitionSequence = summary.maximumSequence + index,
				}
			end
			rawset(profile, "gold", summary.gold - cost)
			local pityMap = rawget(profile, "bannerPity") :: { [string]: any }
			pityMap[policy.bannerId] = {
				bannerId = policy.bannerId,
				bannerVersion = policy.bannerVersion,
				count = plan.pityAfter,
			}
			rawset(stats, "towersAcquired", (towersAcquired :: number) + intent.quantity)
			rawset(stats, "chestsOpened", (chestsOpened :: number) + 1)
			return Result.ok(table.freeze({
				resultCode = `PULL_PITY_{plan.pityBefore}`,
				goldBalance = summary.gold - cost,
				unitIds = table.freeze(generated),
				towerIds = table.freeze(towerIds),
				newFlags = table.freeze(newFlags),
				pityCount = plan.pityAfter,
			}))
		end
	)
	if not called or type(transaction) ~= "table" then
		return failure("CALLBACK_FAILED", "pull")
	end
	local transactionResult = transaction :: any
	if transactionResult.ok ~= true then
		return failure(ownerErrorCode(transactionResult.error), "pull")
	end
	return receiptFromOwner(intent.transactionId, policy, intent.quantity, cost, transactionResult.value)
end

local function productionRandom(): BannerRollPlanner.RandomSource
	local source = Random.new()
	return table.freeze({
		nextNumber = function(): number
			return source:NextNumber()
		end,
	}) :: any
end

local function productionUnitIds(): UnitIdGenerator
	return table.freeze({
		generate = function(): string
			return `unit:{string.lower(HttpService:GenerateGUID(false))}`
		end,
	}) :: any
end

local function productionClock(): Clock
	return table.freeze({
		now = function(): number
			return os.time()
		end,
	}) :: any
end

function AcquisitionService.new(
	profileOwnerValue: unknown,
	configurationValue: unknown,
	randomValue: unknown?,
	unitIdGeneratorValue: unknown?,
	clockValue: unknown?
): Result.Result<Service, ServiceError>
	if
		type(profileOwnerValue) ~= "table"
		or type((profileOwnerValue :: any).getState) ~= "function"
		or type((profileOwnerValue :: any).read) ~= "function"
		or type((profileOwnerValue :: any).transact) ~= "function"
		or not ConfigurationValidator.isValidatedConfiguration(configurationValue)
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local configuration = configurationValue :: ConfigTypes.CoreConfiguration
	local acquisitionResult = AcquisitionProtocol.validateConfiguration(AcquisitionConfig, configuration.banners)
	if not acquisitionResult.ok then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local random = randomValue or productionRandom()
	local unitIds = unitIdGeneratorValue or productionUnitIds()
	local clock = clockValue or productionClock()
	if
		type(random) ~= "table"
		or type((random :: any).nextNumber) ~= "function"
		or type(unitIds) ~= "table"
		or type((unitIds :: any).generate) ~= "function"
		or type(clock) ~= "table"
		or type((clock :: any).now) ~= "function"
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local plannerResult = BannerRollPlanner.new(acquisitionResult.value, random)
	if not plannerResult.ok then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		profileOwner = profileOwnerValue :: ProfileOwner,
		configuration = configuration,
		acquisition = acquisitionResult.value,
		planner = plannerResult.value,
		unitIds = unitIds :: UnitIdGenerator,
		clock = clock :: Clock,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(AcquisitionService)
