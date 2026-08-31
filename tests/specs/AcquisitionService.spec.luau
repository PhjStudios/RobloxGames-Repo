--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local Result = require(ReplicatedStorage.Shared.util.Result)
local AcquisitionService = require(ServerStorage.AutomatedTests.ProductionServerLobbyAcquisition.AcquisitionService)

local loaded = ConfigurationValidator.validateLoaded()
if not loaded.ok then
	error("expected production configuration", 0)
end

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local output = {}
	for key, child in next, value do
		output[copy(key)] = copy(child)
	end
	return output
end

local function profile(gold: number, pity: number?): any
	local bannerPity = {}
	if pity ~= nil then
		bannerPity["banner:starter"] = {
			bannerId = "banner:starter",
			bannerVersion = 1,
			count = pity,
		}
	end
	return {
		schemaVersion = 3,
		revision = 1,
		gold = gold,
		units = {
			["unit:a"] = {
				unitId = "unit:a",
				towerId = "tower:dart-ant",
				favorite = false,
				locked = false,
				acquiredAt = 1,
				acquisitionSequence = 1,
			},
		},
		equippedUnitIds = { "unit:a" },
		bannerPity = bannerPity,
		stats = {
			towersAcquired = 1,
			chestsOpened = 0,
		},
	}
end

local function owner(initial: any): (any, () -> any, () -> number)
	local current = copy(initial)
	local state = "Ready"
	local callbacks = 0
	local receipts: { [string]: any } = {}
	local value = {}
	function value:getState(_userId: number): string
		return state
	end
	function value:read(_userId: number): any
		return Result.ok(copy(current))
	end
	function value:transact(
		_userId: number,
		transactionId: string,
		expectedRevision: number,
		kind: string,
		fingerprint: string,
		callback: (any) -> any
	): any
		local stored = receipts[transactionId]
		if stored ~= nil then
			if stored.kind ~= kind or stored.fingerprint ~= fingerprint then
				return Result.err({ code = "TRANSACTION_CONFLICT" })
			end
			return Result.ok({
				applied = false,
				profileRevision = current.revision,
				committedRevision = stored.committedRevision,
				result = copy(stored.result),
				profile = copy(current),
			})
		end
		if expectedRevision ~= current.revision then
			return Result.err({ code = "STALE_REVISION" })
		end
		local staged = copy(current)
		callbacks += 1
		local outcome = callback(staged)
		if outcome.ok ~= true then
			return Result.err({ code = "MUTATION_REJECTED", reason = outcome.error })
		end
		staged.revision += 1
		current = staged
		local storedReceipt = {
			kind = kind,
			fingerprint = fingerprint,
			committedRevision = current.revision,
			result = copy(outcome.value),
		}
		receipts[transactionId] = storedReceipt
		return Result.ok({
			applied = true,
			profileRevision = current.revision,
			committedRevision = current.revision,
			result = copy(storedReceipt.result),
			profile = copy(current),
		})
	end
	function value:setState(nextState: string)
		state = nextState
	end
	return value, function(): any
		return current
	end, function(): number
		return callbacks
	end
end

local function randomSource(values: { number }): (any, () -> number)
	local calls = 0
	return {
		nextNumber = function(): number
			calls += 1
			return values[calls]
		end,
	}, function(): number
		return calls
	end
end

local function unitIds(prefix: string): (any, () -> number)
	local calls = 0
	return {
		generate = function(): string
			calls += 1
			return `unit:{prefix}-{calls}`
		end,
	}, function(): number
		return calls
	end
end

local function clock(): any
	return {
		now = function(): number
			return 123_456
		end,
	}
end

local function intent(transactionId: string, revision: number, quantity: number): any
	return {
		transactionId = transactionId,
		expectedRevision = revision,
		bannerId = "banner:starter",
		bannerVersion = 1,
		quantity = quantity,
	}
end

return TestHarness.suite("atomic earn-only acquisition service", {
	TestHarness.case("replicates exact odds policy balance and pity only when ready", function(assertions)
		local fake = owner(profile(2_000, 4))
		local random = randomSource({ 0 })
		local generated = unitIds("view")
		local service = AcquisitionService.new(fake, loaded.value, random, generated, clock())
		assertions.isTrue(service.ok)
		if not service.ok then
			return
		end
		local view = service.value:getBannerView(42, "banner:starter")
		assertions.isTrue(view.ok)
		if view.ok then
			assertions.equal(view.value.gold, 2_000)
			assertions.equal(view.value.currentPityCount, 4)
			assertions.equal(view.value.odds[1].probabilityPercent, 60)
			assertions.equal(view.value.odds[2].probabilityPercent, 30)
			assertions.equal(view.value.odds[3].probabilityPercent, 10)
			assertions.equal(view.value.currencyPolicy, "EarnOnlyGold")
		end
		fake:setState("Loading")
		assertions.isFalse(service.value:getBannerView(42, "banner:starter").ok)
		assertions.isFalse(service.value:pull(42, intent("transaction:not-ready", 1, 1)).ok)
	end),
	TestHarness.case("spends and grants once across an identical retry", function(assertions)
		local fake, current, callbacks = owner(profile(2_000, 0))
		local random, randomCalls = randomSource({ 0.7 })
		local generated, generatorCalls = unitIds("single")
		local service = AcquisitionService.new(fake, loaded.value, random, generated, clock())
		assertions.isTrue(service.ok)
		if not service.ok then
			return
		end
		local request = intent("transaction:single", 1, 1)
		local first = service.value:pull(42, request)
		local replay = service.value:pull(42, request)
		assertions.isTrue(first.ok)
		assertions.isTrue(replay.ok)
		if first.ok and replay.ok then
			assertions.equal(first.value.goldBefore, 2_000)
			assertions.equal(first.value.goldAfter, 1_750)
			assertions.equal(first.value.results[1].towerId, "tower:rapid-ant")
			assertions.isTrue(first.value.results[1].isNew)
			assertions.equal(replay.value.results[1].unitId, first.value.results[1].unitId)
			assertions.equal(replay.value.profileRevision, first.value.profileRevision)
		end
		assertions.equal(current().gold, 1_750)
		assertions.equal(current().stats.towersAcquired, 2)
		assertions.equal(current().stats.chestsOpened, 1)
		assertions.equal(callbacks(), 1)
		assertions.equal(randomCalls(), 1)
		assertions.equal(generatorCalls(), 1)
	end),
	TestHarness.case("completes ten outcomes and hard pity inside one transaction", function(assertions)
		local fake, current = owner(profile(5_000, 0))
		local randomValues = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
		local random, randomCalls = randomSource(randomValues)
		local generated = unitIds("ten")
		local service = AcquisitionService.new(fake, loaded.value, random, generated, clock())
		assertions.isTrue(service.ok)
		if not service.ok then
			return
		end
		local result = service.value:pull(42, intent("transaction:ten", 1, 10))
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.equal(#result.value.results, 10)
			assertions.equal(result.value.results[1].towerId, "tower:dart-ant")
			assertions.isFalse(result.value.results[1].isNew)
			assertions.equal(result.value.results[10].towerId, "tower:guard-ant")
			assertions.isTrue(result.value.results[10].isNew)
			assertions.equal(result.value.pityAfter, 0)
		end
		assertions.equal(randomCalls(), 9)
		assertions.equal(current().gold, 2_750)
		assertions.equal(current().stats.towersAcquired, 11)
		assertions.equal(current().stats.chestsOpened, 1)
	end),
	TestHarness.case("hard pity does not consume a predictable client roll", function(assertions)
		local fake = owner(profile(2_000, 9))
		local random, randomCalls = randomSource({ 0 })
		local generated = unitIds("pity")
		local service = AcquisitionService.new(fake, loaded.value, random, generated, clock())
		assertions.isTrue(service.ok)
		if service.ok then
			local result = service.value:pull(42, intent("transaction:pity", 1, 1))
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.equal(result.value.results[1].towerId, "tower:guard-ant")
				assertions.equal(result.value.pityBefore, 9)
				assertions.equal(result.value.pityAfter, 0)
			end
		end
		assertions.equal(randomCalls(), 0)
	end),
	TestHarness.case("rejects insufficient stale conflicting and malformed requests", function(assertions)
		local poor = owner(profile(249, 0))
		local random = randomSource({ 0 })
		local generated = unitIds("poor")
		local service = AcquisitionService.new(poor, loaded.value, random, generated, clock())
		assertions.isTrue(service.ok)
		if service.ok then
			local insufficient = service.value:pull(42, intent("transaction:poor", 1, 1))
			assertions.isFalse(insufficient.ok)
			if not insufficient.ok then
				assertions.equal(insufficient.error.code, "INSUFFICIENT_GOLD")
			end
			assertions.isFalse(service.value:pull(42, intent("transaction:stale", 2, 1)).ok)
			local badVersion = intent("transaction:version", 1, 1)
			badVersion.bannerVersion = 2
			assertions.isFalse(service.value:pull(42, badVersion).ok)
			local malformed = intent("transaction:malformed", 1, 2)
			assertions.isFalse(service.value:pull(42, malformed).ok)
		end

		local rich = owner(profile(5_000, 0))
		local richService =
			AcquisitionService.new(rich, loaded.value, randomSource({ 0 }), unitIds("conflict"), clock())
		assertions.isTrue(richService.ok)
		if richService.ok then
			assertions.isTrue(richService.value:pull(42, intent("transaction:conflict", 1, 1)).ok)
			local conflicting = richService.value:pull(42, intent("transaction:conflict", 1, 10))
			assertions.isFalse(conflicting.ok)
			if not conflicting.ok then
				assertions.equal(conflicting.error.code, "TRANSACTION_CONFLICT")
			end
		end
	end),
	TestHarness.case("aborts without spend when RNG or unit identity fails", function(assertions)
		local badRandomOwner, randomProfile = owner(profile(2_000, 0))
		local badRandomService =
			AcquisitionService.new(badRandomOwner, loaded.value, randomSource({ 1 }), unitIds("bad-rng"), clock())
		assertions.isTrue(badRandomService.ok)
		if badRandomService.ok then
			local result = badRandomService.value:pull(42, intent("transaction:bad-rng", 1, 1))
			assertions.isFalse(result.ok)
			if not result.ok then
				assertions.equal(result.error.code, "RNG_FAILED")
			end
		end
		assertions.equal(randomProfile().gold, 2_000)
		assertions.equal(#randomProfile().units, 0)

		local collisionOwner, collisionProfile = owner(profile(2_000, 0))
		local collisionService = AcquisitionService.new(collisionOwner, loaded.value, randomSource({ 0 }), {
			generate = function(): string
				return "unit:a"
			end,
		}, clock())
		assertions.isTrue(collisionService.ok)
		if collisionService.ok then
			local result = collisionService.value:pull(42, intent("transaction:collision", 1, 1))
			assertions.isFalse(result.ok)
			if not result.ok then
				assertions.equal(result.error.code, "UNIT_ID_FAILED")
			end
		end
		assertions.equal(collisionProfile().gold, 2_000)
	end),
	TestHarness.case("enforces the persistent inventory bound before rolling", function(assertions)
		local full = profile(5_000, 0)
		full.units = {}
		for index = 1, 64 do
			local unitId = `unit:owned-{index}`
			full.units[unitId] = {
				unitId = unitId,
				towerId = "tower:dart-ant",
				favorite = false,
				locked = false,
				acquiredAt = index,
				acquisitionSequence = index,
			}
		end
		full.equippedUnitIds = { "unit:owned-1" }
		local fake, current = owner(full)
		local random, randomCalls = randomSource({ 0 })
		local generated, generatorCalls = unitIds("full")
		local service = AcquisitionService.new(fake, loaded.value, random, generated, clock())
		assertions.isTrue(service.ok)
		if service.ok then
			local result = service.value:pull(42, intent("transaction:full", 1, 1))
			assertions.isFalse(result.ok)
			if not result.ok then
				assertions.equal(result.error.code, "INVENTORY_FULL")
			end
		end
		assertions.equal(current().gold, 5_000)
		assertions.equal(randomCalls(), 0)
		assertions.equal(generatorCalls(), 0)
	end),
})
