--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local ProfileStoreAdapter = require(script.Parent.Parent.ProductionServerProfile.ProfileStoreAdapter)
local MemoryStoreTravelAdapter = require(script.Parent.Parent.ProductionServerTravel.MemoryStoreTravelAdapter)
local ResultLedgerStoreAdapter = require(script.Parent.Parent.ProductionServerMatchRewards.ResultLedgerStoreAdapter)
local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)

local function expectInvalidDeployment(assertions: TestHarness.Assertions, deploymentValue: unknown)
	local profileNamespace = ProfileStoreAdapter.resolvePublishedNamespace(deploymentValue)
	assertions.isFalse(profileNamespace.ok)
	assertions.equal(profileNamespace.error.code, "INVALID_DEPLOYMENT")

	local travelNamespace = MemoryStoreTravelAdapter.resolvePublishedNamespace(deploymentValue)
	assertions.isFalse(travelNamespace.ok)
	assertions.equal(travelNamespace.error.code, "INVALID_DEPLOYMENT")

	local ledgerNamespace = ResultLedgerStoreAdapter.resolvePublishedNamespace(deploymentValue)
	assertions.isFalse(ledgerNamespace.ok)
	assertions.equal(ledgerNamespace.error, "INVALID_DEPLOYMENT")
end

return TestHarness.suite("published persistence namespace routing", {
	TestHarness.case("preserves the exact production namespaces", function(assertions)
		local profile = ProfileStoreAdapter.resolvePublishedNamespace(PlaceRoles.PRODUCTION_DEPLOYMENT)
		assertions.isTrue(profile.ok)
		assertions.equal(profile.value.deployment, "Production")
		assertions.equal(profile.value.storeName, "ATD_Profile_Prod_v1")
		assertions.equal(profile.value.scope, "profiles")
		assertions.isTrue(table.isfrozen(profile.value))

		local travel = MemoryStoreTravelAdapter.resolvePublishedNamespace(PlaceRoles.PRODUCTION_DEPLOYMENT)
		assertions.isTrue(travel.ok)
		assertions.equal(travel.value.deployment, "Production")
		assertions.equal(travel.value.mapName, "ATD_Travel_Prod_v1")
		assertions.isTrue(table.isfrozen(travel.value))

		local ledger = ResultLedgerStoreAdapter.resolvePublishedNamespace(PlaceRoles.PRODUCTION_DEPLOYMENT)
		assertions.isTrue(ledger.ok)
		assertions.equal(ledger.value.deployment, "Production")
		assertions.equal(ledger.value.storeName, "ATDMatchResultLedgerV1")
		assertions.isTrue(table.isfrozen(ledger.value))
	end),

	TestHarness.case("routes staging to isolated namespaces", function(assertions)
		local profile = ProfileStoreAdapter.resolvePublishedNamespace(PlaceRoles.STAGING_DEPLOYMENT)
		assertions.isTrue(profile.ok)
		assertions.equal(profile.value.deployment, "Staging")
		assertions.equal(profile.value.storeName, "ATD_Profile_Staging_v1")
		assertions.equal(profile.value.scope, "profiles_staging")
		assertions.isTrue(table.isfrozen(profile.value))

		local travel = MemoryStoreTravelAdapter.resolvePublishedNamespace(PlaceRoles.STAGING_DEPLOYMENT)
		assertions.isTrue(travel.ok)
		assertions.equal(travel.value.deployment, "Staging")
		assertions.equal(travel.value.mapName, "ATD_Travel_Staging_v1")
		assertions.isTrue(table.isfrozen(travel.value))

		local ledger = ResultLedgerStoreAdapter.resolvePublishedNamespace(PlaceRoles.STAGING_DEPLOYMENT)
		assertions.isTrue(ledger.ok)
		assertions.equal(ledger.value.deployment, "Staging")
		assertions.equal(ledger.value.storeName, "ATD_MatchResultLedger_Staging_v1")
		assertions.isTrue(table.isfrozen(ledger.value))
	end),

	TestHarness.case("requires an explicit supported deployment without a production fallback", function(assertions)
		expectInvalidDeployment(assertions, nil)
		for _, deploymentValue in { "", "Development", "production", "staging", true, 1, {} } do
			expectInvalidDeployment(assertions, deploymentValue)
		end

		local profile = ProfileStoreAdapter.newPublished(nil)
		assertions.isFalse(profile.ok)
		assertions.equal(profile.error.code, "INVALID_DEPLOYMENT")

		local travel = MemoryStoreTravelAdapter.newPublished(nil)
		assertions.isFalse(travel.ok)
		assertions.equal(travel.error.code, "INVALID_DEPLOYMENT")

		local ledger = ResultLedgerStoreAdapter.newPublished(nil)
		assertions.isFalse(ledger.ok)
		assertions.equal(ledger.error, "INVALID_DEPLOYMENT")

		assertions.isNil(ProfileStoreAdapter.newProduction)
		assertions.isNil(MemoryStoreTravelAdapter.newProduction)
		assertions.isNil(ResultLedgerStoreAdapter.newProduction)
	end),
})
