--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileProtocol = require(ReplicatedStorage.Shared.profile.ProfileProtocol)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local ProfileSchema = require(script.Parent.Parent.ProductionServerProfile.ProfileSchema)

type Assertions = TestHarness.Assertions

local NOW = 1_700_000_000

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected profile operation to succeed", 0)
	end
	return result.value
end

local function starter(assertions: Assertions): (any, TowerFixtures.AuthenticatedFixture)
	local fixture = TowerFixtures.createAuthenticatedFixture()
	return success(assertions, ProfileSchema.createStarter(fixture.configuration.towers, NOW)), fixture
end

local function expectProfileError(assertions: Assertions, result: any, code: string)
	assertions.isFalse(result.ok)
	if not result.ok then
		assertions.equal(result.error.code, code)
	end
end

return TestHarness.suite("ProfileSchema", {
	TestHarness.case(
		"creates one usable bounded starter with earn-only Gold and five-slot capacity",
		function(assertions)
			local profile, fixture = starter(assertions)
			assertions.isTrue(table.isfrozen(profile))
			assertions.equal(profile.schemaVersion, ProfileSchema.CURRENT_VERSION)
			assertions.equal(profile.revision, 1)
			assertions.equal(profile.gold, ProfileSchema.STARTER_GOLD)
			assertions.isNil(profile.battleCash)
			assertions.equal(#profile.equippedUnitIds, 1)
			assertions.equal(ProfileSchema.MAX_EQUIPPED_UNITS, 5)
			local starterUnit = profile.units[profile.equippedUnitIds[1]]
			assertions.isNotNil(starterUnit)
			assertions.equal(starterUnit.towerId, fixture.single.id)
			assertions.equal(profile.stats.towersAcquired, 1)
			assertions.isTrue(profile.tutorial.firstJoin)
			assertions.equal(profile.tutorial.version, 1)
			assertions.equal(profile.tutorial.tutorialStep, 0)
			assertions.equal(profile.tutorial.attempt, 1)
			assertions.isFalse(profile.tutorial.skipped)
			assertions.equal(profile.tutorial.trackedMatchId, "")
			assertions.isFalse(profile.settings.reducedMotionEnabled)
			assertions.equal(next(profile.firstClears), nil)
			assertions.equal(#profile.pendingResults, 0)
			assertions.equal(#profile.claimedResults, 0)
			assertions.isTrue(
				success(assertions, ProfileSchema.validate(profile, fixture.configuration.towers)) ~= profile
			)
		end
	),

	TestHarness.case(
		"accepts unique UnitIds and rejects duplicate definitions or unusable support loadouts",
		function(assertions)
			local profile, fixture = starter(assertions)
			local withSecond = ProfileSchema.clone(profile)
			withSecond.units["unit:second"] = {
				unitId = "unit:second",
				towerId = fixture.splash.id,
				favorite = true,
				locked = true,
				acquiredAt = NOW + 1,
				acquisitionSequence = 2,
			}
			withSecond.equippedUnitIds = { profile.equippedUnitIds[1], "unit:second" }
			assertions.equal(
				#success(assertions, ProfileSchema.validate(withSecond, fixture.configuration.towers)).equippedUnitIds,
				2
			)

			local duplicateTower = ProfileSchema.clone(profile)
			duplicateTower.units["unit:duplicate"] = {
				unitId = "unit:duplicate",
				towerId = fixture.single.id,
				favorite = false,
				locked = false,
				acquiredAt = NOW + 1,
				acquisitionSequence = 2,
			}
			duplicateTower.equippedUnitIds = { profile.equippedUnitIds[1], "unit:duplicate" }
			expectProfileError(
				assertions,
				ProfileSchema.validate(duplicateTower, fixture.configuration.towers),
				"INVALID_LOADOUT"
			)

			local supportOnly = ProfileSchema.clone(profile)
			supportOnly.units["unit:support"] = {
				unitId = "unit:support",
				towerId = fixture.support.id,
				favorite = false,
				locked = false,
				acquiredAt = NOW + 1,
				acquisitionSequence = 2,
			}
			supportOnly.equippedUnitIds = { "unit:support" }
			expectProfileError(
				assertions,
				ProfileSchema.validate(supportOnly, fixture.configuration.towers),
				"NO_ATTACKING_TOWER"
			)
		end
	),

	TestHarness.case("fails closed on malformed settings references bounds and extra fields", function(assertions)
		local profile, fixture = starter(assertions)
		local malformed = ProfileSchema.clone(profile)
		malformed.settings.uiScale = 2
		expectProfileError(assertions, ProfileSchema.validate(malformed, fixture.configuration.towers), "INVALID_FIELD")

		malformed = ProfileSchema.clone(profile)
		malformed.units[profile.equippedUnitIds[1]].towerId = "tower:missing"
		expectProfileError(
			assertions,
			ProfileSchema.validate(malformed, fixture.configuration.towers),
			"INVALID_REFERENCE"
		)

		malformed = ProfileSchema.clone(profile)
		malformed.gold = ProfileSchema.MAX_GOLD + 1
		expectProfileError(assertions, ProfileSchema.validate(malformed, fixture.configuration.towers), "INVALID_FIELD")

		malformed = ProfileSchema.clone(profile)
		malformed.privateSession = "must-not-exist"
		expectProfileError(
			assertions,
			ProfileSchema.validate(malformed, fixture.configuration.towers),
			"INVALID_PROFILE"
		)

		malformed = ProfileSchema.clone(profile)
		malformed.tutorial.tutorialStep = 5
		malformed.tutorial.firstJoin = false
		expectProfileError(assertions, ProfileSchema.validate(malformed, fixture.configuration.towers), "INVALID_FIELD")

		malformed = ProfileSchema.clone(profile)
		malformed.tutorial.tutorialStep = 9
		malformed.tutorial.firstJoin = false
		malformed.tutorial.tutorialCompleted = true
		malformed.tutorial.skipped = true
		assertions.isTrue(ProfileSchema.validate(malformed, fixture.configuration.towers).ok)
	end),

	TestHarness.case("validates bounded first clears and durable claimed-result receipts", function(assertions)
		local profile, fixture = starter(assertions)
		local claimed = ProfileSchema.clone(profile)
		claimed.firstClears["map:phase07-graybox|difficulty:local"] = {
			mapId = "map:phase07-graybox",
			difficultyId = "difficulty:local",
			clearedAt = NOW,
		}
		table.insert(claimed.claimedResults, {
			resultId = "result:11111111-1111-1111-1111-111111111111",
			persistentGoldAwarded = 500,
			firstClearBonus = 250,
			claimedAt = NOW,
		})
		local validated = success(assertions, ProfileSchema.validate(claimed, fixture.configuration.towers))
		assertions.equal(validated.claimedResults[1].persistentGoldAwarded, 500)
		assertions.equal(#ProfileProtocol.ready(validated, "Current").firstClears, 1)

		local malformed = ProfileSchema.clone(claimed)
		malformed.claimedResults[1].firstClearBonus = 501
		expectProfileError(assertions, ProfileSchema.validate(malformed, fixture.configuration.towers), "INVALID_FIELD")
		malformed = ProfileSchema.clone(claimed)
		malformed.firstClears["map:wrong|difficulty:local"] =
			malformed.firstClears["map:phase07-graybox|difficulty:local"]
		malformed.firstClears["map:phase07-graybox|difficulty:local"] = nil
		expectProfileError(
			assertions,
			ProfileSchema.validate(malformed, fixture.configuration.towers),
			"INVALID_REFERENCE"
		)
	end),

	TestHarness.case("keeps a bounded server-only pending and claim-finalization inbox", function(assertions)
		local profile, fixture = starter(assertions)
		local pending = ProfileSchema.clone(profile)
		table.insert(pending.pendingResults, {
			resultId = "result:11111111-1111-1111-1111-111111111111",
			createdAt = NOW,
		})
		local validated = success(assertions, ProfileSchema.validate(pending, fixture.configuration.towers))
		assertions.equal(validated.pendingResults[1].createdAt, NOW)
		local client = ProfileProtocol.ready(validated, "Current") :: any
		assertions.isNil(client.pendingResults)
		assertions.isNil(client.claimedResults)

		local finalizing = ProfileSchema.clone(pending)
		table.insert(finalizing.claimedResults, {
			resultId = pending.pendingResults[1].resultId,
			persistentGoldAwarded = 50,
			firstClearBonus = 0,
			claimedAt = NOW,
		})
		assertions.isTrue(ProfileSchema.validate(finalizing, fixture.configuration.towers).ok)

		local oversized = ProfileSchema.clone(profile)
		for index = 1, ProfileSchema.MAX_PENDING_RESULT_IDS + 1 do
			table.insert(oversized.pendingResults, {
				resultId = `result:pending-{index}`,
				createdAt = NOW + index,
			})
		end
		expectProfileError(assertions, ProfileSchema.validate(oversized, fixture.configuration.towers), "INVALID_FIELD")
	end),

	TestHarness.case("bounds exact idempotency receipt results", function(assertions)
		local valid = success(
			assertions,
			ProfileSchema.validateReceiptResult({
				resultCode = "ACQUISITION_OK",
				goldBalance = 1_500,
				unitIds = { "unit:result-one" },
				towerIds = { TowerFixtures.SINGLE_TOWER_ID },
				newFlags = { true },
				pityCount = 1,
			})
		)
		assertions.isTrue(table.isfrozen(valid))
		assertions.equal(valid.goldBalance, 1_500)

		expectProfileError(
			assertions,
			ProfileSchema.validateReceiptResult({
				resultCode = "ACQUISITION_OK",
				goldBalance = 1_500,
				unitIds = { "unit:result-one" },
				towerIds = {},
				newFlags = { true },
				pityCount = 1,
			}),
			"INVALID_RECEIPT_RESULT"
		)
	end),

	TestHarness.case(
		"replicates a bounded safe view without inventory receipts or session internals",
		function(assertions)
			local profile = starter(assertions)
			local snapshot = ProfileProtocol.ready(profile, "Created")
			assertions.isTrue(ProfileProtocol.validateSnapshot(snapshot).ok)
			assertions.equal(snapshot.state, "Ready")
			assertions.equal(snapshot.gold, ProfileSchema.STARTER_GOLD)
			assertions.isNil((snapshot :: any).units)
			assertions.isNil((snapshot :: any).receipts)
			assertions.isNil((snapshot :: any).session)
			assertions.isFalse(ProfileProtocol.validateSnapshot({
				state = "Loading",
				retryable = false,
				gold = 0,
			}).ok)
		end
	),
})
