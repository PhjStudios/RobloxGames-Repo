--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local AcquisitionConfig = require(ReplicatedStorage.Shared.acquisition.AcquisitionConfig)
local AcquisitionProtocol = require(ReplicatedStorage.Shared.acquisition.AcquisitionProtocol)
local BannerRollPlanner = require(ReplicatedStorage.Shared.acquisition.BannerRollPlanner)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)

local loaded = ConfigurationValidator.validateLoaded()
if not loaded.ok then
	error("expected production configuration", 0)
end

local function authenticated(available: boolean): AcquisitionProtocol.AuthenticatedConfiguration
	local policies = {}
	for index, policy in AcquisitionConfig.banners do
		policies[index] = {
			bannerId = policy.bannerId,
			bannerVersion = policy.bannerVersion,
			available = if index == 1 then available else policy.available,
			currencyPolicy = policy.currencyPolicy,
			policyDisclosure = policy.policyDisclosure,
		}
	end
	local raw = {
		version = AcquisitionConfig.version,
		banners = policies,
	}
	local result = AcquisitionProtocol.validateConfiguration(raw, loaded.value.banners)
	if not result.ok then
		error("expected authenticated acquisition configuration", 0)
	end
	return result.value
end

local function randomSequence(values: { number }): (BannerRollPlanner.RandomSource, () -> number)
	local index = 0
	return {
		nextNumber = function(): number
			index += 1
			return values[index]
		end,
	}, function(): number
		return index
	end
end

return TestHarness.suite("deterministic banner roll planner", {
	TestHarness.case("uses exact weighted boundaries in authenticated order", function(assertions)
		local random = randomSequence({ 0, 0.599999, 0.6, 0.899999, 0.9, 0.999999 })
		local planner = BannerRollPlanner.new(authenticated(true), random)
		assertions.isTrue(planner.ok)
		if not planner.ok then
			return
		end
		local expected = {
			"tower:dart-ant",
			"tower:dart-ant",
			"tower:rapid-ant",
			"tower:rapid-ant",
			"tower:guard-ant",
			"tower:guard-ant",
		}
		for _, towerId in expected do
			local result = planner.value:plan("banner:starter", 0, 1)
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.equal(result.value.outcomes[1].towerId, towerId)
			end
		end
	end),
	TestHarness.case("forces hard pity without consulting RNG and resets it", function(assertions)
		local random, calls = randomSequence({ 0 })
		local planner = BannerRollPlanner.new(authenticated(true), random)
		assertions.isTrue(planner.ok)
		if not planner.ok then
			return
		end
		local result = planner.value:plan("banner:starter", 9, 1)
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.equal(result.value.outcomes[1].towerId, "tower:guard-ant")
			assertions.isTrue(result.value.outcomes[1].pityTriggered)
			assertions.equal(result.value.pityBefore, 9)
			assertions.equal(result.value.pityAfter, 0)
		end
		assertions.equal(calls(), 0)
	end),
	TestHarness.case("plans a ten pull sequentially across its pity boundary", function(assertions)
		local random, calls = randomSequence({ 0, 0, 0, 0, 0, 0, 0, 0, 0 })
		local planner = BannerRollPlanner.new(authenticated(true), random)
		assertions.isTrue(planner.ok)
		if not planner.ok then
			return
		end
		local result = planner.value:plan("banner:starter", 0, 10)
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.equal(#result.value.outcomes, 10)
			assertions.equal(result.value.outcomes[9].towerId, "tower:dart-ant")
			assertions.equal(result.value.outcomes[10].towerId, "tower:guard-ant")
			assertions.isTrue(result.value.outcomes[10].pityTriggered)
			assertions.equal(result.value.pityAfter, 0)
		end
		assertions.equal(calls(), 9)
	end),
	TestHarness.case("rejects unavailable malformed and impossible planner inputs", function(assertions)
		local unavailable = BannerRollPlanner.new(authenticated(false), randomSequence({ 0 }))
		assertions.isTrue(unavailable.ok)
		if unavailable.ok then
			local result = unavailable.value:plan("banner:starter", 0, 1)
			assertions.isFalse(result.ok)
			if not result.ok then
				assertions.equal(result.error.code, "UNAVAILABLE")
			end
		end
		local invalidRandom = BannerRollPlanner.new(authenticated(true), {
			nextNumber = function(): number
				return 1
			end,
		})
		assertions.isTrue(invalidRandom.ok)
		if invalidRandom.ok then
			local result = invalidRandom.value:plan("banner:starter", 0, 1)
			assertions.isFalse(result.ok)
			if not result.ok then
				assertions.equal(result.error.code, "RANDOM_OUT_OF_RANGE")
			end
			assertions.isFalse(invalidRandom.value:plan("banner:starter", 10, 1).ok)
			assertions.isFalse(invalidRandom.value:plan("banner:starter", 0, 2).ok)
			assertions.isFalse(invalidRandom.value:plan("banner:missing", 0, 1).ok)
		end
	end),
})
