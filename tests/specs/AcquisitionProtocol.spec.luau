--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local AcquisitionConfig = require(ReplicatedStorage.Shared.acquisition.AcquisitionConfig)
local AcquisitionProtocol = require(ReplicatedStorage.Shared.acquisition.AcquisitionProtocol)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)

local loaded = ConfigurationValidator.validateLoaded()
if not loaded.ok then
	error("expected production configuration", 0)
end

local function bannerView(): any
	return {
		bannerId = "banner:starter",
		bannerVersion = 1,
		displayName = "Starter Tower Chest",
		available = true,
		currencyPolicy = "EarnOnlyGold",
		policyDisclosure = "Gold is earned through play. No purchase is offered.",
		onePullCost = 250,
		tenPullCost = 2_250,
		odds = {
			{ towerId = "tower:dart-ant", probabilityPercent = 60 },
			{ towerId = "tower:rapid-ant", probabilityPercent = 30 },
			{ towerId = "tower:guard-ant", probabilityPercent = 10 },
		},
		hardPityPullCount = 10,
		guaranteedTowerId = "tower:guard-ant",
		currentPityCount = 4,
		gold = 2_000,
		profileRevision = 7,
	}
end

local function receipt(quantity: number): any
	local results = {}
	for index = 1, quantity do
		table.insert(results, {
			index = index,
			unitId = `unit:pull-{index}`,
			towerId = "tower:dart-ant",
			isNew = index == 1,
		})
	end
	local cost = if quantity == 1 then 250 else 2_250
	return {
		transactionId = "transaction:pull-a",
		bannerId = "banner:starter",
		bannerVersion = 1,
		quantity = quantity,
		cost = cost,
		goldBefore = 5_000,
		goldAfter = 5_000 - cost,
		pityBefore = 0,
		pityAfter = quantity % 10,
		profileRevision = 8,
		results = results,
	}
end

return TestHarness.suite("authenticated acquisition protocol", {
	TestHarness.case("authenticates exact earn-only production policy and odds", function(assertions)
		local result = AcquisitionProtocol.validateConfiguration(AcquisitionConfig, loaded.value.banners)
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.isTrue(AcquisitionProtocol.isAuthenticatedConfiguration(result.value))
			assertions.equal(result.value.ordered[1].currencyPolicy, "EarnOnlyGold")
			assertions.equal(result.value.ordered[1].definition.outcomes[1].probabilityPercent, 60)
			assertions.equal(result.value.ordered[1].definition.outcomes[2].probabilityPercent, 30)
			assertions.equal(result.value.ordered[1].definition.outcomes[3].probabilityPercent, 10)
		end
		assertions.isFalse(AcquisitionProtocol.isAuthenticatedConfiguration(table.clone(AcquisitionConfig)))
	end),
	TestHarness.case("validates bounded client-safe banner views", function(assertions)
		assertions.isTrue(AcquisitionProtocol.validateBannerView(bannerView()).ok)
		local wrongTotal = bannerView()
		wrongTotal.odds[1].probabilityPercent = 59
		assertions.isFalse(AcquisitionProtocol.validateBannerView(wrongTotal).ok)
		local missingPity = bannerView()
		missingPity.guaranteedTowerId = "tower:unknown"
		assertions.isFalse(AcquisitionProtocol.validateBannerView(missingPity).ok)
		local private = bannerView()
		private.sessionLock = "private"
		assertions.isFalse(AcquisitionProtocol.validateBannerView(private).ok)
	end),
	TestHarness.case("accepts only one or ten pull intents", function(assertions)
		local intent = {
			transactionId = "transaction:pull-a",
			expectedRevision = 3,
			bannerId = "banner:starter",
			bannerVersion = 1,
			quantity = 1,
		}
		assertions.isTrue(AcquisitionProtocol.validatePullIntent(intent).ok)
		intent.quantity = 10
		assertions.isTrue(AcquisitionProtocol.validatePullIntent(intent).ok)
		intent.quantity = 2
		assertions.isFalse(AcquisitionProtocol.validatePullIntent(intent).ok)
		intent.quantity = 1
		intent.clientRoll = 0.5
		assertions.isFalse(AcquisitionProtocol.validatePullIntent(intent).ok)
	end),
	TestHarness.case("validates complete ordered idempotent pull receipts", function(assertions)
		assertions.isTrue(AcquisitionProtocol.validatePullReceipt(receipt(1)).ok)
		assertions.isTrue(AcquisitionProtocol.validatePullReceipt(receipt(10)).ok)
		local duplicate = receipt(10)
		duplicate.results[10].unitId = duplicate.results[1].unitId
		assertions.isFalse(AcquisitionProtocol.validatePullReceipt(duplicate).ok)
		local wrongGold = receipt(1)
		wrongGold.goldAfter += 1
		assertions.isFalse(AcquisitionProtocol.validatePullReceipt(wrongGold).ok)
		local skipped = receipt(10)
		table.remove(skipped.results, 5)
		assertions.isFalse(AcquisitionProtocol.validatePullReceipt(skipped).ok)
	end),
	TestHarness.case("rejects malformed unavailable policy records", function(assertions)
		local malformed = {
			version = 1,
			banners = {
				{
					bannerId = "banner:starter",
					bannerVersion = 1,
					available = true,
					currencyPolicy = "PaidGold",
					policyDisclosure = "invalid",
				},
			},
		}
		assertions.isFalse(AcquisitionProtocol.validateConfiguration(malformed, loaded.value.banners).ok)
		malformed.banners[1].currencyPolicy = "EarnOnlyGold"
		malformed.banners[1].bannerVersion = 2
		assertions.isFalse(AcquisitionProtocol.validateConfiguration(malformed, loaded.value.banners).ok)
	end),
})
