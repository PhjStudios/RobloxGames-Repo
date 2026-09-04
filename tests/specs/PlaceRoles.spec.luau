--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local PlaceRoles = require(game:GetService("ReplicatedStorage").Shared.config.PlaceRoles)

type Assertions = TestHarness.Assertions

local PRODUCTION_GAME_ID = 10757629094
local PRODUCTION_LOBBY_PLACE_ID = 100561454756026
local PRODUCTION_MATCH_PLACE_ID = 136401514513678

local STAGING_GAME_ID = 10764687717
local STAGING_LOBBY_PLACE_ID = 140661668701496
local STAGING_MATCH_PLACE_ID = 104415140644510

local function expectFailure(assertions: Assertions, result: PlaceRoles.Resolution, code: string)
	assertions.isFalse(result.ok)
	if result.ok then
		return
	end
	assertions.equal(result.code, code)
end

local function expectSuccess(
	assertions: Assertions,
	result: PlaceRoles.Resolution,
	expectedRole: PlaceRoles.PlaceRole,
	expectedDeployment: PlaceRoles.Deployment,
	expectedGameId: number,
	expectedPlaceId: number
)
	assertions.isTrue(result.ok)
	if not result.ok then
		return
	end
	assertions.equal(result.role, expectedRole)
	assertions.equal(result.deployment, expectedDeployment)
	assertions.equal(result.actualGameId, expectedGameId)
	assertions.equal(result.expectedGameId, expectedGameId)
	assertions.equal(result.actualPlaceId, expectedPlaceId)
	assertions.equal(result.expectedPlaceId, expectedPlaceId)
end

return TestHarness.suite("place roles and deployments", {
	TestHarness.case("pins the validated production and staging identities", function(assertions)
		local validation = PlaceRoles.validateConfiguration()
		assertions.isTrue(validation.ok)

		assertions.equal(PlaceRoles.getConfiguredGameId(PlaceRoles.PRODUCTION_DEPLOYMENT), PRODUCTION_GAME_ID)
		assertions.equal(
			PlaceRoles.getConfiguredPlaceId(PlaceRoles.PRODUCTION_DEPLOYMENT, PlaceRoles.LOBBY_ROLE),
			PRODUCTION_LOBBY_PLACE_ID
		)
		assertions.equal(
			PlaceRoles.getConfiguredPlaceId(PlaceRoles.PRODUCTION_DEPLOYMENT, PlaceRoles.MATCH_ROLE),
			PRODUCTION_MATCH_PLACE_ID
		)
		assertions.equal(PlaceRoles.getConfiguredGameId(PlaceRoles.STAGING_DEPLOYMENT), STAGING_GAME_ID)
		assertions.equal(
			PlaceRoles.getConfiguredPlaceId(PlaceRoles.STAGING_DEPLOYMENT, PlaceRoles.LOBBY_ROLE),
			STAGING_LOBBY_PLACE_ID
		)
		assertions.equal(
			PlaceRoles.getConfiguredPlaceId(PlaceRoles.STAGING_DEPLOYMENT, PlaceRoles.MATCH_ROLE),
			STAGING_MATCH_PLACE_ID
		)
		assertions.isNil(PlaceRoles.getConfiguredPlaceId(PlaceRoles.PRODUCTION_DEPLOYMENT, PlaceRoles.DEVELOPMENT_ROLE))
		assertions.isNil(PlaceRoles.getConfiguredGameId("Unknown" :: any))
		assertions.isTrue(PlaceRoles.isDeployment("Production"))
		assertions.isTrue(PlaceRoles.isDeployment("Staging"))
		assertions.isFalse(PlaceRoles.isDeployment("Unknown"))
		assertions.isTrue(table.isfrozen(PlaceRoles))
	end),
	TestHarness.case("resolves exact production lobby and match pairs", function(assertions)
		expectSuccess(
			assertions,
			PlaceRoles.resolve(PlaceRoles.LOBBY_ROLE, PRODUCTION_GAME_ID, PRODUCTION_LOBBY_PLACE_ID, false),
			PlaceRoles.LOBBY_ROLE,
			PlaceRoles.PRODUCTION_DEPLOYMENT,
			PRODUCTION_GAME_ID,
			PRODUCTION_LOBBY_PLACE_ID
		)
		expectSuccess(
			assertions,
			PlaceRoles.resolve(PlaceRoles.MATCH_ROLE, PRODUCTION_GAME_ID, PRODUCTION_MATCH_PLACE_ID, false),
			PlaceRoles.MATCH_ROLE,
			PlaceRoles.PRODUCTION_DEPLOYMENT,
			PRODUCTION_GAME_ID,
			PRODUCTION_MATCH_PLACE_ID
		)
	end),
	TestHarness.case("resolves exact staging lobby and match pairs", function(assertions)
		expectSuccess(
			assertions,
			PlaceRoles.resolve(PlaceRoles.LOBBY_ROLE, STAGING_GAME_ID, STAGING_LOBBY_PLACE_ID, false),
			PlaceRoles.LOBBY_ROLE,
			PlaceRoles.STAGING_DEPLOYMENT,
			STAGING_GAME_ID,
			STAGING_LOBBY_PLACE_ID
		)
		expectSuccess(
			assertions,
			PlaceRoles.resolve(PlaceRoles.MATCH_ROLE, STAGING_GAME_ID, STAGING_MATCH_PLACE_ID, false),
			PlaceRoles.MATCH_ROLE,
			PlaceRoles.STAGING_DEPLOYMENT,
			STAGING_GAME_ID,
			STAGING_MATCH_PLACE_ID
		)
	end),
	TestHarness.case("rejects every production and staging cross-pair", function(assertions)
		expectFailure(
			assertions,
			PlaceRoles.resolve(PlaceRoles.LOBBY_ROLE, PRODUCTION_GAME_ID, STAGING_LOBBY_PLACE_ID, false),
			"PLACE_ID_MISMATCH"
		)
		expectFailure(
			assertions,
			PlaceRoles.resolve(PlaceRoles.MATCH_ROLE, PRODUCTION_GAME_ID, STAGING_MATCH_PLACE_ID, false),
			"PLACE_ID_MISMATCH"
		)
		expectFailure(
			assertions,
			PlaceRoles.resolve(PlaceRoles.LOBBY_ROLE, STAGING_GAME_ID, PRODUCTION_LOBBY_PLACE_ID, false),
			"PLACE_ID_MISMATCH"
		)
		expectFailure(
			assertions,
			PlaceRoles.resolve(PlaceRoles.MATCH_ROLE, STAGING_GAME_ID, PRODUCTION_MATCH_PLACE_ID, false),
			"PLACE_ID_MISMATCH"
		)
	end),
	TestHarness.case("fails closed on invalid or unknown observed GameIds", function(assertions)
		for _, gameId in { 0, -1, 1.5, math.huge, 0 / 0, "10764687717" :: any } do
			expectFailure(
				assertions,
				PlaceRoles.resolve(PlaceRoles.LOBBY_ROLE, gameId, STAGING_LOBBY_PLACE_ID, false),
				"INVALID_ACTUAL_GAME_ID"
			)
		end
		expectFailure(
			assertions,
			PlaceRoles.resolve(PlaceRoles.LOBBY_ROLE, 999999999, STAGING_LOBBY_PLACE_ID, false),
			"GAME_ID_UNCONFIGURED"
		)
	end),
	TestHarness.case("does not stringify rejected identity values", function(assertions)
		local stringifyCount = 0
		local sentinel = setmetatable({}, {
			__tostring = function()
				stringifyCount += 1
				return "sensitive"
			end,
		})

		expectFailure(
			assertions,
			PlaceRoles.resolve(PlaceRoles.LOBBY_ROLE, sentinel, STAGING_LOBBY_PLACE_ID, false),
			"INVALID_ACTUAL_GAME_ID"
		)
		expectFailure(
			assertions,
			PlaceRoles.resolve(PlaceRoles.LOBBY_ROLE, STAGING_GAME_ID, sentinel, false),
			"INVALID_ACTUAL_PLACE_ID"
		)
		assertions.equal(stringifyCount, 0)
	end),
	TestHarness.case("preserves the Studio-only production Development pairing", function(assertions)
		expectSuccess(
			assertions,
			PlaceRoles.resolve(PlaceRoles.DEVELOPMENT_ROLE, PRODUCTION_GAME_ID, PRODUCTION_LOBBY_PLACE_ID, true),
			PlaceRoles.DEVELOPMENT_ROLE,
			PlaceRoles.PRODUCTION_DEPLOYMENT,
			PRODUCTION_GAME_ID,
			PRODUCTION_LOBBY_PLACE_ID
		)
		expectFailure(
			assertions,
			PlaceRoles.resolve(PlaceRoles.DEVELOPMENT_ROLE, PRODUCTION_GAME_ID, PRODUCTION_LOBBY_PLACE_ID, false),
			"DEVELOPMENT_ROLE_OUTSIDE_STUDIO"
		)
		expectFailure(
			assertions,
			PlaceRoles.resolve(PlaceRoles.DEVELOPMENT_ROLE, STAGING_GAME_ID, STAGING_LOBBY_PLACE_ID, true),
			"GAME_ID_MISMATCH"
		)
	end),
	TestHarness.case("retains declared-role and actual-place rejection", function(assertions)
		expectFailure(
			assertions,
			PlaceRoles.resolve("Other", PRODUCTION_GAME_ID, PRODUCTION_LOBBY_PLACE_ID, false),
			"INVALID_DECLARED_ROLE"
		)
		expectFailure(
			assertions,
			PlaceRoles.resolve(PlaceRoles.LOBBY_ROLE, PRODUCTION_GAME_ID, "100561454756026", false),
			"INVALID_ACTUAL_PLACE_ID"
		)
		expectFailure(
			assertions,
			PlaceRoles.resolve(PlaceRoles.LOBBY_ROLE, PRODUCTION_GAME_ID, PRODUCTION_MATCH_PLACE_ID, false),
			"PLACE_ID_MISMATCH"
		)
	end),
})
