--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Shared = game:GetService("ReplicatedStorage").Shared
local LobbyProtocol = require(Shared.lobby.LobbyProtocol)
local PayloadValidation = require(Shared.network.PayloadValidation)

type Assertions = TestHarness.Assertions

local function expectSuccess(assertions: Assertions, schema: PayloadValidation.Schema, value: unknown): unknown
	local result = schema:validate(value)
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return (result :: any).value
end

local function expectFailure(
	assertions: Assertions,
	schema: PayloadValidation.Schema,
	value: unknown,
	code: string,
	path: string
)
	local result = schema:validate(value)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local issue = (result :: any).error
	assertions.equal(issue.code, code)
	assertions.equal(issue.path, path)
	assertions.isTrue(table.isfrozen(issue))
	assertions.isTrue(table.isfrozen(issue.pathSegments))
end

return TestHarness.suite("Lobby network protocol", {
	TestHarness.case("exports one frozen exact Lobby endpoint family", function(assertions)
		assertions.isTrue(table.isfrozen(LobbyProtocol))
		assertions.isTrue(table.isfrozen(LobbyProtocol.ENDPOINTS))
		assertions.isTrue(PayloadValidation.isSchema(LobbyProtocol.EmptyPayloadSchema))
		assertions.isTrue(PayloadValidation.isSchema(LobbyProtocol.BannerRequestSchema))
		assertions.isTrue(PayloadValidation.isSchema(LobbyProtocol.QueueListSchema))
		assertions.isTrue(PayloadValidation.isSchema(LobbyProtocol.ActiveRouteViewSchema))

		local expected = {
			GET_PROFILE = "GetLobbyProfile",
			RETRY_PROFILE = "RetryLobbyProfile",
			GET_INVENTORY = "GetLobbyInventory",
			EQUIP_TOWER = "EquipLobbyTower",
			UNEQUIP_TOWER = "UnequipLobbyTower",
			FAVORITE_TOWER = "FavoriteLobbyTower",
			LOCK_TOWER = "LockLobbyTower",
			GET_BANNER = "GetLobbyBanner",
			PULL_CHEST = "PullLobbyChest",
			UPDATE_SETTINGS = "UpdateLobbySettings",
			GET_PARTY = "GetLobbyParty",
			CREATE_PARTY = "CreateLobbyParty",
			INVITE_PARTY = "InviteLobbyParty",
			ACCEPT_PARTY_INVITE = "AcceptLobbyPartyInvite",
			DECLINE_PARTY_INVITE = "DeclineLobbyPartyInvite",
			LEAVE_PARTY = "LeaveLobbyParty",
			KICK_PARTY_MEMBER = "KickLobbyPartyMember",
			TRANSFER_PARTY_LEADERSHIP = "TransferLobbyPartyLeadership",
			SET_PARTY_PRIVACY = "SetLobbyPartyPrivacy",
			DISBAND_PARTY = "DisbandLobbyParty",
			PROMPT_PARTY_INVITE = "PromptLobbyPartyInvite",
			GET_QUEUES = "GetLobbyQueues",
			JOIN_QUEUE = "JoinLobbyQueue",
			LEAVE_QUEUE = "LeaveLobbyQueue",
			CONFIGURE_QUEUE = "ConfigureLobbyQueue",
			START_QUEUE = "StartLobbyQueue",
			GET_ACTIVE_ROUTE = "GetLobbyActiveRoute",
			RECONNECT_ACTIVE_MATCH = "ReconnectLobbyActiveMatch",
			PROFILE_REPLICATION = "LobbyProfileReplication",
			INVENTORY_REPLICATION = "LobbyInventoryReplication",
			PARTY_REPLICATION = "LobbyPartyReplication",
			QUEUE_REPLICATION = "LobbyQueueReplication",
			ACTIVE_ROUTE_REPLICATION = "LobbyActiveRouteReplication",
		}
		local count = 0
		local seenValues: { [string]: boolean } = {}
		for key, value in LobbyProtocol.ENDPOINTS do
			count += 1
			assertions.equal(value, expected[key])
			assertions.isFalse(seenValues[value] == true)
			seenValues[value] = true
		end
		assertions.equal(count, 33)

		assertions.equal(LobbyProtocol.VERSION, 1)
	end),

	TestHarness.case("accepts only detached empty payloads for snapshot and retry requests", function(assertions)
		local raw = {}
		local canonical = expectSuccess(assertions, LobbyProtocol.EmptyPayloadSchema, raw)
		assertions.notEqual(canonical, raw)
		assertions.isTrue(table.isfrozen(canonical :: any))

		for _, invalid in
			{
				nil,
				false,
				0,
				"",
				{ profileRevision = 7 },
				{ gold = 9_999 },
				{ [1] = "not a record" },
			}
		do
			assertions.isFalse(LobbyProtocol.EmptyPayloadSchema:validate(invalid).ok)
		end
		expectFailure(
			assertions,
			LobbyProtocol.EmptyPayloadSchema,
			{ privateSessionLock = "PRIVATE" },
			"UNKNOWN_FIELD",
			"payload"
		)
	end),

	TestHarness.case("validates only one bounded banner identity without client proposed results", function(assertions)
		local raw = { bannerId = "banner:starter" }
		local canonical = expectSuccess(assertions, LobbyProtocol.BannerRequestSchema, raw) :: any
		assertions.notEqual(canonical, raw)
		assertions.equal(canonical.bannerId, "banner:starter")
		assertions.isTrue(table.isfrozen(canonical))
		raw.bannerId = "banner:changed"
		assertions.equal(canonical.bannerId, "banner:starter")

		for _, bannerId in
			{
				"",
				"starter",
				"tower:starter",
				"banner:",
				"banner:bad value",
				string.rep("x", 200),
				42,
				{},
			}
		do
			assertions.isFalse(LobbyProtocol.BannerRequestSchema:validate({ bannerId = bannerId }).ok)
		end
		expectFailure(
			assertions,
			LobbyProtocol.BannerRequestSchema,
			{ bannerId = "banner:starter", gold = 9_999 },
			"UNKNOWN_FIELD",
			"payload"
		)
		expectFailure(
			assertions,
			LobbyProtocol.BannerRequestSchema,
			{ bannerId = "banner:starter", result = "tower:guard-ant" },
			"UNKNOWN_FIELD",
			"payload"
		)
		expectFailure(
			assertions,
			LobbyProtocol.BannerRequestSchema,
			{ bannerId = "banner:starter", pity = 10 },
			"UNKNOWN_FIELD",
			"payload"
		)
	end),

	TestHarness.case("bounds ordered queue discovery and rejects client-visible travel secrets", function(assertions)
		local queue = {
			version = 1,
			queueId = "queue:alpha",
			revision = 1,
			state = "Open",
			configuration = {
				mapId = "map:meadow",
				difficultyId = "difficulty:normal",
				privacy = "Public",
				maxPlayers = 4,
			},
			members = {},
			enrollments = {},
			canStart = false,
		}
		local list = LobbyProtocol.validateQueueList({ version = 1, queues = { queue } })
		assertions.isTrue(list.ok)
		assertions.equal((list :: any).value.queues[1].queueId, "queue:alpha")
		assertions.isFalse(LobbyProtocol.validateQueueList({ version = 1, queues = { queue, queue } }).ok)

		local route = LobbyProtocol.validateActiveRoute({
			version = 1,
			status = "Available",
			matchId = "match:active",
			expiresAt = 100,
		})
		assertions.isTrue(route.ok)
		assertions.isFalse(LobbyProtocol.ActiveRouteViewSchema:validate({
			version = 1,
			status = "Available",
			matchId = "match:active",
			expiresAt = 100,
			reservedAccessCode = "PRIVATE",
		}).ok)
		assertions.isFalse(LobbyProtocol.ActiveRouteViewSchema:validate({
			version = 1,
			status = "Available",
			matchId = "match:active",
			expiresAt = 100,
			ticketId = "ticket:private",
		}).ok)
		assertions.isFalse(LobbyProtocol.validateActiveRoute({ version = 1, status = "Available" }).ok)
		assertions.isTrue(LobbyProtocol.validateActiveRoute({ version = 1, status = "None" }).ok)
	end),
})
