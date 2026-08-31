--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local ProfileMigrations = require(script.Parent.Parent.ProductionServerProfile.ProfileMigrations)
local ProfileSchema = require(script.Parent.Parent.ProductionServerProfile.ProfileSchema)

type Assertions = TestHarness.Assertions

local NOW = 1_700_000_100

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected profile migration to succeed", 0)
	end
	return result.value
end

local function expectError(assertions: Assertions, result: any, code: string)
	assertions.isFalse(result.ok)
	if not result.ok then
		assertions.equal(result.error.code, code)
	end
end

local function current(assertions: Assertions, fixture: TowerFixtures.AuthenticatedFixture): any
	return success(assertions, ProfileSchema.createStarter(fixture.configuration.towers, NOW - 100))
end

local function legacySettings(profile: any)
	profile.settings.version = 1
	profile.settings.reducedMotionEnabled = nil
end

local function versionTwo(assertions: Assertions, fixture: TowerFixtures.AuthenticatedFixture): any
	local profile = ProfileSchema.clone(current(assertions, fixture))
	profile.schemaVersion = 2
	profile.migration = nil
	legacySettings(profile)
	return profile
end

local function versionOne(assertions: Assertions, fixture: TowerFixtures.AuthenticatedFixture): any
	local profile = versionTwo(assertions, fixture)
	profile.schemaVersion = 1
	profile.stats = nil
	profile.receipts = nil
	return profile
end

return TestHarness.suite("ProfileMigrations", {
	TestHarness.case("creates only a missing profile and preserves explicit creation metadata", function(assertions)
		local fixture = TowerFixtures.createAuthenticatedFixture()
		local migrated = success(assertions, ProfileMigrations.migrate(nil, fixture.configuration.towers, NOW))
		assertions.equal(migrated.outcome, "Created")
		assertions.equal(migrated.fromVersion, 0)
		assertions.equal(#migrated.appliedVersions, 0)
		assertions.equal(migrated.profile.migration.createdAt, NOW)
		assertions.equal(migrated.profile.migration.migrationCount, 0)
	end),

	TestHarness.case("accepts valid current profiles without rewriting migration metadata", function(assertions)
		local fixture = TowerFixtures.createAuthenticatedFixture()
		local profile = current(assertions, fixture)
		local migrated = success(assertions, ProfileMigrations.migrate(profile, fixture.configuration.towers, NOW))
		assertions.equal(migrated.outcome, "Current")
		assertions.equal(migrated.fromVersion, ProfileSchema.CURRENT_VERSION)
		assertions.equal(#migrated.appliedVersions, 0)
		assertions.equal(migrated.profile.migration.createdAt, NOW - 100)
	end),

	TestHarness.case("runs v1 migrations sequentially through v2 and v3", function(assertions)
		local fixture = TowerFixtures.createAuthenticatedFixture()
		local migrated = success(
			assertions,
			ProfileMigrations.migrate(versionOne(assertions, fixture), fixture.configuration.towers, NOW)
		)
		assertions.equal(migrated.outcome, "Migrated")
		assertions.equal(migrated.fromVersion, 1)
		assertions.equal(#migrated.appliedVersions, 2)
		assertions.equal(migrated.appliedVersions[1], 2)
		assertions.equal(migrated.appliedVersions[2], 3)
		assertions.equal(migrated.profile.schemaVersion, 3)
		assertions.equal(migrated.profile.settings.version, 2)
		assertions.isFalse(migrated.profile.settings.reducedMotionEnabled)
		assertions.equal(migrated.profile.stats.towersAcquired, 1)
		assertions.equal(migrated.profile.migration.migratedFromVersion, 1)
		assertions.equal(migrated.profile.migration.migrationCount, 2)
		assertions.equal(migrated.profile.migration.lastMigratedAt, NOW)
	end),

	TestHarness.case("runs v2 to v3 without fabricating transaction history", function(assertions)
		local fixture = TowerFixtures.createAuthenticatedFixture()
		local migrated = success(
			assertions,
			ProfileMigrations.migrate(versionTwo(assertions, fixture), fixture.configuration.towers, NOW)
		)
		assertions.equal(migrated.outcome, "Migrated")
		assertions.equal(migrated.fromVersion, 2)
		assertions.equal(#migrated.appliedVersions, 1)
		assertions.equal(migrated.appliedVersions[1], 3)
		assertions.equal(#migrated.profile.receipts, 0)
		assertions.equal(migrated.profile.migration.migrationCount, 1)
	end),

	TestHarness.case(
		"fails closed for missing malformed unsupported future and broken legacy profiles",
		function(assertions)
			local fixture = TowerFixtures.createAuthenticatedFixture()
			expectError(assertions, ProfileMigrations.migrate({}, fixture.configuration.towers, NOW), "MISSING_VERSION")
			expectError(
				assertions,
				ProfileMigrations.migrate({ schemaVersion = "3" }, fixture.configuration.towers, NOW),
				"MALFORMED_PROFILE"
			)
			expectError(
				assertions,
				ProfileMigrations.migrate({ schemaVersion = 0 }, fixture.configuration.towers, NOW),
				"UNSUPPORTED_VERSION"
			)
			expectError(
				assertions,
				ProfileMigrations.migrate(
					{ schemaVersion = ProfileSchema.CURRENT_VERSION + 1 },
					fixture.configuration.towers,
					NOW
				),
				"FUTURE_VERSION"
			)
			local broken = versionOne(assertions, fixture)
			broken.stats = {}
			expectError(
				assertions,
				ProfileMigrations.migrate(broken, fixture.configuration.towers, NOW),
				"MIGRATION_FAILED"
			)
		end
	),

	TestHarness.case("rejects cyclic and invalid current data instead of resetting it", function(assertions)
		local fixture = TowerFixtures.createAuthenticatedFixture()
		local cyclic = versionOne(assertions, fixture)
		cyclic.loop = cyclic
		expectError(
			assertions,
			ProfileMigrations.migrate(cyclic, fixture.configuration.towers, NOW),
			"MALFORMED_PROFILE"
		)
		local malformed = ProfileSchema.clone(current(assertions, fixture))
		malformed.gold = -1
		expectError(
			assertions,
			ProfileMigrations.migrate(malformed, fixture.configuration.towers, NOW),
			"INVALID_FIELD"
		)
	end),

	TestHarness.case("rejects flat oversized legacy profiles within the migration copy budget", function(assertions)
		local fixture = TowerFixtures.createAuthenticatedFixture()
		local oversized = versionOne(assertions, fixture)
		local flatValues = {}
		for index = 1, ProfileMigrations.MAX_CLONE_NODES + 1 do
			flatValues[`field-{index}`] = index
		end
		oversized.oversized = flatValues

		expectError(
			assertions,
			ProfileMigrations.migrate(oversized, fixture.configuration.towers, NOW),
			"MALFORMED_PROFILE"
		)
	end),
})
