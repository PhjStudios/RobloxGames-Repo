--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local NetworkFixtures = require(script.Parent.Parent.Fixtures.NetworkFixtures)
local Shared = game:GetService("ReplicatedStorage").Shared
local LobbyProtocol = require(Shared.lobby.LobbyProtocol)
local ProductionRemotes = require(Shared.network.ProductionRemotes)
local RemoteRegistry = require(Shared.network.RemoteRegistry)

type Assertions = TestHarness.Assertions

local ERROR_FIELDS: { [string]: boolean } = table.freeze({
	code = true,
	path = true,
	message = true,
})

local function assertExactError(assertions: Assertions, errorValue: RemoteRegistry.Error)
	local fieldCount = 0
	for fieldName in next, errorValue :: any do
		fieldCount += 1
		assertions.isTrue(ERROR_FIELDS[fieldName] == true)
	end
	assertions.equal(fieldCount, 3)
	assertions.isTrue(table.isfrozen(errorValue))
end

local function expectFailure(
	assertions: Assertions,
	value: unknown,
	code: RemoteRegistry.ErrorCode,
	path: string
): RemoteRegistry.Error
	local result = RemoteRegistry.create(value)
	assertions.isFalse(result.ok)
	local errorValue = (result :: any).error :: RemoteRegistry.Error
	assertions.equal(errorValue.code, code)
	assertions.equal(errorValue.path, path)
	assertions.isTrue(type(errorValue.message) == "string" and #errorValue.message > 0)
	assertions.isTrue(table.isfrozen(result))
	assertExactError(assertions, errorValue)
	return errorValue
end

local function expectRegistry(assertions: Assertions, value: unknown): RemoteRegistry.Registry
	local result = RemoteRegistry.create(value)
	assertions.isTrue(result.ok)
	local registry = (result :: any).value :: RemoteRegistry.Registry
	assertions.isTrue(RemoteRegistry.isRegistry(registry))
	return registry
end

local function namedDefinition(name: string): NetworkFixtures.RawDefinition
	local definition = NetworkFixtures.responseRequestDefinition()
	definition.name = name
	return definition
end

local function assertNames(assertions: Assertions, definitions: { RemoteRegistry.Definition }, names: { string })
	assertions.equal(rawlen(definitions), rawlen(names))
	for index = 1, rawlen(names) do
		assertions.equal(definitions[index].name, names[index])
	end
end

return TestHarness.suite("remote registry contract", {
	TestHarness.case(
		"exports fixed protocol constants and the complete Match and Lobby production remote boundary",
		function(assertions)
			assertions.equal(RemoteRegistry.ROOT_NAME, "ATDNetwork")
			assertions.equal(RemoteRegistry.VERSION_NAME, "v1")
			assertions.equal(RemoteRegistry.MAX_DEFINITIONS, 128)
			assertions.equal(RemoteRegistry.MAX_NAME_BYTES, 48)
			assertions.isTrue(table.isfrozen(RemoteRegistry))

			assertions.isTrue(RemoteRegistry.isRegistry(ProductionRemotes))
			local matchNames = {
				"BaseReplication",
				"CombatAttackEvent",
				"EnemyReplication",
				"GetBaseSnapshot",
				"GetEnemySnapshot",
				"GetMatchSnapshot",
				"GetMatchTravelSnapshot",
				"GetPlayableMatchSnapshot",
				"GetTowerPlacementQuery",
				"GetWaveSnapshot",
				"MatchSnapshot",
				"MatchTravelReplication",
				"PlayableMatchReplication",
				"RequestReturnToLobby",
				"SubmitPlayablePlacement",
				"SubmitPlayableReady",
				"SubmitPlayableReplay",
				"SubmitReady",
				"SubmitRematchVote",
				"SubmitSkipVote",
				"SubmitTowerPlacement",
				"SubmitTowerSell",
				"SubmitTowerTargetMode",
				"SubmitTowerUpgrade",
				"TowerPlacementRevision",
				"WaveReplication",
			}
			local lobbyNames = {} :: { string }
			for _, endpoint in LobbyProtocol.ENDPOINTS do
				table.insert(lobbyNames, endpoint)
			end
			table.sort(lobbyNames)
			local allNames = table.clone(matchNames)
			for _, endpoint in lobbyNames do
				table.insert(allNames, endpoint)
			end
			table.sort(allNames)
			assertions.equal(ProductionRemotes:count(), #allNames)
			assertNames(assertions, ProductionRemotes:list(), allNames)
			assertNames(assertions, ProductionRemotes:listForRole("Development"), allNames)
			assertNames(assertions, ProductionRemotes:listForRole("Lobby"), lobbyNames)
			assertNames(assertions, ProductionRemotes:listForRole("Match"), matchNames)

			local getSnapshot = ProductionRemotes:get("GetMatchSnapshot") :: RemoteRegistry.Definition
			assertions.equal(getSnapshot.transport, "ReliableRemoteEvent")
			assertions.equal(getSnapshot.direction, "ClientToServer")
			assertions.equal(getSnapshot.kind, "Request")
			assertions.equal(getSnapshot.response, "Required")
			assertions.equal(rawlen(getSnapshot.placeRoles), 1)
			assertions.equal(getSnapshot.placeRoles[1], "Match")

			local getBaseSnapshot = ProductionRemotes:get("GetBaseSnapshot") :: RemoteRegistry.Definition
			assertions.equal(getBaseSnapshot.transport, "ReliableRemoteEvent")
			assertions.equal(getBaseSnapshot.direction, "ClientToServer")
			assertions.equal(getBaseSnapshot.kind, "Request")
			assertions.equal(getBaseSnapshot.response, "Required")
			assertions.equal(rawlen(getBaseSnapshot.placeRoles), 1)
			assertions.equal(getBaseSnapshot.placeRoles[1], "Match")

			local getEnemySnapshot = ProductionRemotes:get("GetEnemySnapshot") :: RemoteRegistry.Definition
			assertions.equal(getEnemySnapshot.transport, "ReliableRemoteEvent")
			assertions.equal(getEnemySnapshot.direction, "ClientToServer")
			assertions.equal(getEnemySnapshot.kind, "Request")
			assertions.equal(getEnemySnapshot.response, "Required")
			assertions.equal(rawlen(getEnemySnapshot.placeRoles), 1)
			assertions.equal(getEnemySnapshot.placeRoles[1], "Match")

			local getWaveSnapshot = ProductionRemotes:get("GetWaveSnapshot") :: RemoteRegistry.Definition
			assertions.equal(getWaveSnapshot.transport, "ReliableRemoteEvent")
			assertions.equal(getWaveSnapshot.direction, "ClientToServer")
			assertions.equal(getWaveSnapshot.kind, "Request")
			assertions.equal(getWaveSnapshot.response, "Required")
			assertions.equal(rawlen(getWaveSnapshot.placeRoles), 1)
			assertions.equal(getWaveSnapshot.placeRoles[1], "Match")

			local getTowerPlacementQuery = ProductionRemotes:get("GetTowerPlacementQuery") :: RemoteRegistry.Definition
			assertions.equal(getTowerPlacementQuery.transport, "ReliableRemoteEvent")
			assertions.equal(getTowerPlacementQuery.direction, "ClientToServer")
			assertions.equal(getTowerPlacementQuery.kind, "Request")
			assertions.equal(getTowerPlacementQuery.response, "Required")
			assertions.equal(rawlen(getTowerPlacementQuery.placeRoles), 1)
			assertions.equal(getTowerPlacementQuery.placeRoles[1], "Match")

			local submitReady = ProductionRemotes:get("SubmitReady") :: RemoteRegistry.Definition
			assertions.equal(submitReady.direction, "ClientToServer")
			assertions.equal(submitReady.kind, "Request")
			assertions.equal(submitReady.response, "Required")
			assertions.equal(rawlen(submitReady.placeRoles), 1)
			assertions.equal(submitReady.placeRoles[1], "Match")

			local submitSkipVote = ProductionRemotes:get("SubmitSkipVote") :: RemoteRegistry.Definition
			assertions.equal(submitSkipVote.transport, "ReliableRemoteEvent")
			assertions.equal(submitSkipVote.direction, "ClientToServer")
			assertions.equal(submitSkipVote.kind, "Request")
			assertions.equal(submitSkipVote.response, "Required")
			assertions.equal(rawlen(submitSkipVote.placeRoles), 1)
			assertions.equal(submitSkipVote.placeRoles[1], "Match")

			local submitTowerPlacement = ProductionRemotes:get("SubmitTowerPlacement") :: RemoteRegistry.Definition
			assertions.equal(submitTowerPlacement.transport, "ReliableRemoteEvent")
			assertions.equal(submitTowerPlacement.direction, "ClientToServer")
			assertions.equal(submitTowerPlacement.kind, "Request")
			assertions.equal(submitTowerPlacement.response, "Required")
			assertions.equal(rawlen(submitTowerPlacement.placeRoles), 1)
			assertions.equal(submitTowerPlacement.placeRoles[1], "Match")

			local snapshotEvent = ProductionRemotes:get("MatchSnapshot") :: RemoteRegistry.Definition
			assertions.equal(snapshotEvent.direction, "ServerToClient")
			assertions.equal(snapshotEvent.kind, "Event")
			assertions.equal(snapshotEvent.response, "None")
			assertions.equal(rawlen(snapshotEvent.placeRoles), 1)
			assertions.equal(snapshotEvent.placeRoles[1], "Match")

			local enemyEvent = ProductionRemotes:get("EnemyReplication") :: RemoteRegistry.Definition
			assertions.equal(enemyEvent.transport, "ReliableRemoteEvent")
			assertions.equal(enemyEvent.direction, "ServerToClient")
			assertions.equal(enemyEvent.kind, "Event")
			assertions.equal(enemyEvent.response, "None")
			assertions.equal(rawlen(enemyEvent.placeRoles), 1)
			assertions.equal(enemyEvent.placeRoles[1], "Match")

			local baseEvent = ProductionRemotes:get("BaseReplication") :: RemoteRegistry.Definition
			assertions.equal(baseEvent.transport, "ReliableRemoteEvent")
			assertions.equal(baseEvent.direction, "ServerToClient")
			assertions.equal(baseEvent.kind, "Event")
			assertions.equal(baseEvent.response, "None")
			assertions.equal(rawlen(baseEvent.placeRoles), 1)
			assertions.equal(baseEvent.placeRoles[1], "Match")

			local waveEvent = ProductionRemotes:get("WaveReplication") :: RemoteRegistry.Definition
			assertions.equal(waveEvent.transport, "ReliableRemoteEvent")
			assertions.equal(waveEvent.direction, "ServerToClient")
			assertions.equal(waveEvent.kind, "Event")
			assertions.equal(waveEvent.response, "None")
			assertions.equal(rawlen(waveEvent.placeRoles), 1)
			assertions.equal(waveEvent.placeRoles[1], "Match")

			local placementRevision = ProductionRemotes:get("TowerPlacementRevision") :: RemoteRegistry.Definition
			assertions.equal(placementRevision.transport, "ReliableRemoteEvent")
			assertions.equal(placementRevision.direction, "ServerToClient")
			assertions.equal(placementRevision.kind, "Event")
			assertions.equal(placementRevision.response, "None")
			assertions.equal(rawlen(placementRevision.placeRoles), 1)
			assertions.equal(placementRevision.placeRoles[1], "Match")

			for _, endpoint in
				{
					LobbyProtocol.ENDPOINTS.GET_PROFILE,
					LobbyProtocol.ENDPOINTS.RETRY_PROFILE,
					LobbyProtocol.ENDPOINTS.GET_INVENTORY,
					LobbyProtocol.ENDPOINTS.EQUIP_TOWER,
					LobbyProtocol.ENDPOINTS.UNEQUIP_TOWER,
					LobbyProtocol.ENDPOINTS.FAVORITE_TOWER,
					LobbyProtocol.ENDPOINTS.LOCK_TOWER,
					LobbyProtocol.ENDPOINTS.GET_BANNER,
					LobbyProtocol.ENDPOINTS.PULL_CHEST,
					LobbyProtocol.ENDPOINTS.UPDATE_SETTINGS,
					LobbyProtocol.ENDPOINTS.ADVANCE_TUTORIAL,
					LobbyProtocol.ENDPOINTS.SKIP_TUTORIAL,
					LobbyProtocol.ENDPOINTS.REPLAY_TUTORIAL,
					LobbyProtocol.ENDPOINTS.GET_PARTY,
					LobbyProtocol.ENDPOINTS.CREATE_PARTY,
					LobbyProtocol.ENDPOINTS.INVITE_PARTY,
					LobbyProtocol.ENDPOINTS.ACCEPT_PARTY_INVITE,
					LobbyProtocol.ENDPOINTS.DECLINE_PARTY_INVITE,
					LobbyProtocol.ENDPOINTS.LEAVE_PARTY,
					LobbyProtocol.ENDPOINTS.KICK_PARTY_MEMBER,
					LobbyProtocol.ENDPOINTS.TRANSFER_PARTY_LEADERSHIP,
					LobbyProtocol.ENDPOINTS.SET_PARTY_PRIVACY,
					LobbyProtocol.ENDPOINTS.DISBAND_PARTY,
					LobbyProtocol.ENDPOINTS.PROMPT_PARTY_INVITE,
					LobbyProtocol.ENDPOINTS.GET_QUEUES,
					LobbyProtocol.ENDPOINTS.JOIN_QUEUE,
					LobbyProtocol.ENDPOINTS.LEAVE_QUEUE,
					LobbyProtocol.ENDPOINTS.CONFIGURE_QUEUE,
					LobbyProtocol.ENDPOINTS.START_QUEUE,
					LobbyProtocol.ENDPOINTS.GET_ACTIVE_ROUTE,
					LobbyProtocol.ENDPOINTS.RECONNECT_ACTIVE_MATCH,
				}
			do
				local definition = ProductionRemotes:get(endpoint) :: RemoteRegistry.Definition
				assertions.isNotNil(definition)
				assertions.equal(definition.transport, "ReliableRemoteEvent")
				assertions.equal(definition.direction, "ClientToServer")
				assertions.equal(definition.kind, "Request")
				assertions.equal(definition.response, "Required")
				assertions.equal(rawlen(definition.placeRoles), 1)
				assertions.equal(definition.placeRoles[1], "Lobby")
			end

			for _, endpoint in
				{
					LobbyProtocol.ENDPOINTS.PROFILE_REPLICATION,
					LobbyProtocol.ENDPOINTS.INVENTORY_REPLICATION,
					LobbyProtocol.ENDPOINTS.PARTY_REPLICATION,
					LobbyProtocol.ENDPOINTS.QUEUE_REPLICATION,
					LobbyProtocol.ENDPOINTS.ACTIVE_ROUTE_REPLICATION,
				}
			do
				local definition = ProductionRemotes:get(endpoint) :: RemoteRegistry.Definition
				assertions.isNotNil(definition)
				assertions.equal(definition.transport, "ReliableRemoteEvent")
				assertions.equal(definition.direction, "ServerToClient")
				assertions.equal(definition.kind, "Event")
				assertions.equal(definition.response, "None")
				assertions.equal(rawlen(definition.placeRoles), 1)
				assertions.equal(definition.placeRoles[1], "Lobby")
			end
		end
	),

	TestHarness.case("accepts every supported semantic variant and canonicalizes lookup order", function(assertions)
		local registry = expectRegistry(assertions, NetworkFixtures.validDefinitions())
		assertions.equal(registry:count(), 4)
		assertNames(assertions, registry:list(), {
			"TestClientEvent",
			"TestNoResponseRequest",
			"TestResponseRequest",
			"TestServerEvent",
		})

		local responseRequest = registry:get("TestResponseRequest")
		assertions.isNotNil(responseRequest)
		assertions.equal(responseRequest, registry:list()[3])
		assertions.equal((responseRequest :: RemoteRegistry.Definition).transport, "ReliableRemoteEvent")
		assertions.equal((responseRequest :: RemoteRegistry.Definition).direction, "ClientToServer")
		assertions.equal((responseRequest :: RemoteRegistry.Definition).kind, "Request")
		assertions.equal((responseRequest :: RemoteRegistry.Definition).response, "Required")
		assertions.equal((responseRequest :: RemoteRegistry.Definition).placeRoles[1], "Lobby")
		assertions.equal((responseRequest :: RemoteRegistry.Definition).placeRoles[2], "Match")
		assertions.isNil(registry:get("TestUnknownEndpoint"))
	end),

	TestHarness.case("filters canonical definitions by fixed place role without changing order", function(assertions)
		local registry = expectRegistry(assertions, NetworkFixtures.validDefinitions())
		assertNames(assertions, registry:listForRole("Development"), {
			"TestClientEvent",
			"TestNoResponseRequest",
			"TestResponseRequest",
			"TestServerEvent",
		})
		assertNames(assertions, registry:listForRole("Lobby"), {
			"TestResponseRequest",
			"TestServerEvent",
		})
		assertNames(assertions, registry:listForRole("Match"), {
			"TestClientEvent",
			"TestNoResponseRequest",
			"TestResponseRequest",
		})

		local invalidRoleList = (registry.listForRole :: any)(registry, "Development/Match")
		assertions.equal(rawlen(invalidRoleList), 0)
		assertions.isTrue(table.isfrozen(invalidRoleList))
	end),

	TestHarness.case("sorts independently of authored order", function(assertions)
		local forward = NetworkFixtures.validDefinitions()
		local reverse = {}
		for index = rawlen(forward), 1, -1 do
			table.insert(reverse, forward[index])
		end
		local first = expectRegistry(assertions, forward)
		local second = expectRegistry(assertions, reverse)
		assertions.notEqual(first, second)
		for index, definition in first:list() do
			assertions.equal(definition.name, second:list()[index].name)
		end
	end),

	TestHarness.case("deep-freezes canonical state and detaches it from authored input", function(assertions)
		local rawDefinitions = NetworkFixtures.validDefinitions()
		local rawResponseRequest = rawDefinitions[2]
		local rawRoles = rawResponseRequest.placeRoles
		local registry = expectRegistry(assertions, rawDefinitions)
		local ordered = registry:list()
		local definition = registry:get("TestResponseRequest") :: RemoteRegistry.Definition

		rawResponseRequest.name = "ChangedAfterValidation"
		rawResponseRequest.direction = "ServerToClient"
		rawRoles[1] = "Lobby"
		rawRoles[2] = nil
		rawDefinitions[1] = namedDefinition("ReplacementAfterValidation")
		assertions.isNotNil(registry:get("TestResponseRequest"))
		assertions.isNil(registry:get("ChangedAfterValidation"))
		assertions.equal(definition.direction, "ClientToServer")
		assertions.equal(definition.placeRoles[1], "Lobby")
		assertions.equal(definition.placeRoles[2], "Match")

		assertions.isTrue(table.isfrozen(registry))
		assertions.isTrue(table.isfrozen(ordered))
		assertions.isTrue(table.isfrozen(definition))
		assertions.isTrue(table.isfrozen(definition.placeRoles))
		assertions.isTrue(table.isfrozen(registry:listForRole("Lobby")))
		assertions.isTrue(table.isfrozen(registry:listForRole("Match")))

		assertions.isFalse(pcall(function()
			(registry :: any)._count = 99
		end))
		assertions.isFalse(pcall(function()
			(ordered :: any)[1] = nil
		end))
		assertions.isFalse(pcall(function()
			(definition :: any).name = "Changed"
		end))
		assertions.isFalse(pcall(function()
			(definition.placeRoles :: any)[1] = "Match"
		end))
		assertions.isFalse(pcall(function()
			(RemoteRegistry :: any).MAX_NAME_BYTES = 999
		end))
	end),

	TestHarness.case("authenticates registries and fails closed for counterfeit receivers", function(assertions)
		local registry = expectRegistry(assertions, NetworkFixtures.validDefinitions())
		local spoof = table.freeze({
			_ordered = registry:list(),
			_byName = { TestResponseRequest = registry:get("TestResponseRequest") },
			_byRole = {},
			_count = registry:count(),
		})
		assertions.isFalse(RemoteRegistry.isRegistry(spoof))
		assertions.isFalse(RemoteRegistry.isRegistry({}))
		assertions.isFalse(RemoteRegistry.isRegistry(nil))
		assertions.isFalse(RemoteRegistry.isRegistry("registry"))

		local getMethod = registry.get :: any
		local listMethod = registry.list :: any
		local listForRoleMethod = registry.listForRole :: any
		local countMethod = registry.count :: any
		assertions.isNil(getMethod(spoof, "TestResponseRequest"))
		local counterfeitList = listMethod(spoof)
		assertions.equal(rawlen(counterfeitList), 0)
		assertions.isTrue(table.isfrozen(counterfeitList))
		assertions.equal(rawlen(listForRoleMethod(spoof, "Development")), 0)
		assertions.equal(countMethod(spoof), 0)
	end),

	TestHarness.case("returns fresh fixture graphs and distinct authenticated registries", function(assertions)
		local firstFixture = NetworkFixtures.validDefinitions()
		local secondFixture = NetworkFixtures.validDefinitions()
		assertions.notEqual(firstFixture, secondFixture)
		assertions.notEqual(firstFixture[1], secondFixture[1])
		assertions.notEqual(firstFixture[1].placeRoles, secondFixture[1].placeRoles)
		firstFixture[1].name = "ChangedFixture"
		assertions.equal(secondFixture[1].name, "TestServerEvent")
		assertions.isTrue(table.isfrozen(NetworkFixtures))

		local firstRegistry = expectRegistry(assertions, secondFixture)
		local secondRegistry = expectRegistry(assertions, NetworkFixtures.clone(secondFixture))
		assertions.notEqual(firstRegistry, secondRegistry)
		assertions.notEqual(firstRegistry:list()[1], secondRegistry:list()[1])
		assertions.isTrue(RemoteRegistry.isRegistry(firstRegistry))
		assertions.isTrue(RemoteRegistry.isRegistry(secondRegistry))
	end),

	TestHarness.case("rejects non-array roots sparse arrays and unsupported keys", function(assertions)
		local wrongTypes: { unknown } = { false, 1, "definitions", function() end, coroutine.create(function() end) }
		for _, value in wrongTypes do
			expectFailure(assertions, value, "INVALID_TYPE", "definitions")
		end
		expectFailure(assertions, nil, "INVALID_TYPE", "definitions")

		expectFailure(assertions, {
			[1] = namedDefinition("TestSparseOne"),
			[3] = namedDefinition("TestSparseThree"),
		}, "INVALID_ARRAY", "definitions")
		expectFailure(assertions, {
			[0] = namedDefinition("TestZeroIndex"),
		}, "INVALID_ARRAY", "definitions")
		expectFailure(assertions, {
			[1.5] = namedDefinition("TestFractionalIndex"),
		}, "INVALID_ARRAY", "definitions")
		expectFailure(assertions, {
			endpoint = namedDefinition("TestNamedIndex"),
		}, "INVALID_ARRAY", "definitions")
	end),

	TestHarness.case("enforces the exact maximum definition count", function(assertions)
		local exactMaximum = {}
		for index = 1, RemoteRegistry.MAX_DEFINITIONS do
			table.insert(exactMaximum, namedDefinition(string.format("TestEndpoint%03d", index)))
		end
		local registry = expectRegistry(assertions, exactMaximum)
		assertions.equal(registry:count(), RemoteRegistry.MAX_DEFINITIONS)
		assertions.equal(registry:list()[1].name, "TestEndpoint001")
		assertions.equal(registry:list()[RemoteRegistry.MAX_DEFINITIONS].name, "TestEndpoint128")

		table.insert(exactMaximum, namedDefinition("TestEndpoint129"))
		expectFailure(assertions, exactMaximum, "TOO_MANY_DEFINITIONS", "definitions")
		expectFailure(assertions, {
			[RemoteRegistry.MAX_DEFINITIONS + 1] = namedDefinition("TestFarIndex"),
		}, "TOO_MANY_DEFINITIONS", "definitions")
	end),

	TestHarness.case("requires exact plain definition records in stable field order", function(assertions)
		local requiredFields = { "name", "transport", "direction", "kind", "response", "placeRoles" }
		for _, fieldName in requiredFields do
			local definition = NetworkFixtures.responseRequestDefinition()
			definition[fieldName] = nil
			expectFailure(assertions, { definition }, "MISSING_FIELD", `definitions[1].{fieldName}`)
		end

		expectFailure(assertions, { "definition" }, "INVALID_TYPE", "definitions[1]")
		expectFailure(
			assertions,
			{ NetworkFixtures.responseRequestDefinition(), false },
			"INVALID_TYPE",
			"definitions[2]"
		)
		local unknown = NetworkFixtures.responseRequestDefinition()
		unknown.extra = true
		expectFailure(assertions, { unknown }, "UNKNOWN_FIELD", "definitions[1]")
		local nonStringKey = NetworkFixtures.responseRequestDefinition()
		nonStringKey[{}] = true
		expectFailure(assertions, { nonStringKey }, "UNKNOWN_FIELD", "definitions[1]")
	end),

	TestHarness.case("accepts the name byte boundary and rejects malformed path-like names", function(assertions)
		local exactBoundary = "A" .. string.rep("b", RemoteRegistry.MAX_NAME_BYTES - 1)
		assertions.equal(#exactBoundary, RemoteRegistry.MAX_NAME_BYTES)
		local registry = expectRegistry(assertions, {
			namedDefinition(exactBoundary),
			namedDefinition("LowerCamel9"),
		})
		assertions.isNotNil(registry:get(exactBoundary))
		assertions.isNotNil(registry:get("LowerCamel9"))

		expectFailure(assertions, { namedDefinition(exactBoundary .. "c") }, "NAME_TOO_LONG", "definitions[1].name")
		local malformedNames = {
			"",
			"lowerCamel9",
			"9StartsWithDigit",
			"Test_Underscore",
			"Test.Dot",
			"Test/Slash",
			"Test\\Backslash",
			"Test-Hyphen",
			"Test Space",
			"T\0est",
			"T\u{00E9}st",
		}
		for _, name in malformedNames do
			expectFailure(assertions, { namedDefinition(name) }, "INVALID_NAME", "definitions[1].name")
		end
	end),

	TestHarness.case(
		"rejects structural names case-insensitively and non-string names without coercion",
		function(assertions)
			local reservedNames =
				{ "ATDNetwork", "atdnetwork", "AtDnEtWoRk", "v1", "V1", "Request", "response", "EVENT" }
			for _, name in reservedNames do
				expectFailure(assertions, { namedDefinition(name) }, "RESERVED_NAME", "definitions[1].name")
			end

			local coercionCount = 0
			local hostileName = setmetatable({}, {
				__tostring = function()
					coercionCount += 1
					return "PRIVATE_NAME"
				end,
			})
			local definition = NetworkFixtures.responseRequestDefinition()
			definition.name = hostileName
			expectFailure(assertions, { definition }, "INVALID_TYPE", "definitions[1].name")
			assertions.equal(coercionCount, 0)
		end
	),

	TestHarness.case("rejects unsupported enum values and types without coercion", function(assertions)
		local cases = {
			{ field = "transport", invalid = "RemoteFunction" },
			{ field = "transport", invalid = "UnreliableRemoteEvent" },
			{ field = "direction", invalid = "Bidirectional" },
			{ field = "kind", invalid = "Response" },
			{ field = "response", invalid = "Optional" },
		}
		for _, fixture in cases do
			local definition = NetworkFixtures.responseRequestDefinition()
			definition[fixture.field] = fixture.invalid
			local errorValue =
				expectFailure(assertions, { definition }, "INVALID_ENUM", `definitions[1].{fixture.field}`)
			assertions.isNil(string.find(errorValue.message, fixture.invalid, 1, true))
		end

		local coercionCount = 0
		for _, fieldName in { "transport", "direction", "kind", "response" } do
			local hostileValue = setmetatable({}, {
				__tostring = function()
					coercionCount += 1
					return "PRIVATE_ENUM"
				end,
			})
			local definition = NetworkFixtures.responseRequestDefinition()
			definition[fieldName] = hostileValue
			expectFailure(assertions, { definition }, "INVALID_TYPE", `definitions[1].{fieldName}`)
		end
		assertions.equal(coercionCount, 0)
	end),

	TestHarness.case("enforces request direction and event response combinations", function(assertions)
		local wrongRequestDirection = NetworkFixtures.responseRequestDefinition()
		wrongRequestDirection.direction = "ServerToClient"
		expectFailure(assertions, { wrongRequestDirection }, "INVALID_COMBINATION", "definitions[1].direction")

		local eventWithResponse = NetworkFixtures.serverEventDefinition()
		eventWithResponse.response = "Required"
		expectFailure(assertions, { eventWithResponse }, "INVALID_COMBINATION", "definitions[1].response")

		assertions.isTrue(RemoteRegistry.create({ NetworkFixtures.noResponseRequestDefinition() }).ok)
		assertions.isTrue(RemoteRegistry.create({ NetworkFixtures.clientEventDefinition() }).ok)
		assertions.isTrue(RemoteRegistry.create({ NetworkFixtures.serverEventDefinition() }).ok)
	end),

	TestHarness.case("requires nonempty dense unique Lobby and Match role arrays", function(assertions)
		local function withRoles(roles: any): NetworkFixtures.RawDefinition
			local definition = NetworkFixtures.responseRequestDefinition()
			definition.placeRoles = roles
			return definition
		end

		expectFailure(assertions, { withRoles("Lobby") }, "INVALID_TYPE", "definitions[1].placeRoles")
		expectFailure(assertions, { withRoles({}) }, "EMPTY_PLACE_ROLES", "definitions[1].placeRoles")
		expectFailure(assertions, { withRoles({ [2] = "Lobby" }) }, "INVALID_ARRAY", "definitions[1].placeRoles")
		expectFailure(assertions, { withRoles({ role = "Lobby" }) }, "INVALID_ARRAY", "definitions[1].placeRoles")
		expectFailure(
			assertions,
			{ withRoles({ "Lobby", "Match", "Lobby" }) },
			"INVALID_ARRAY",
			"definitions[1].placeRoles"
		)
		expectFailure(assertions, { withRoles({ "Development" }) }, "INVALID_ENUM", "definitions[1].placeRoles[1]")
		expectFailure(assertions, { withRoles({ true }) }, "INVALID_TYPE", "definitions[1].placeRoles[1]")
		expectFailure(
			assertions,
			{ withRoles({ "Lobby", "Lobby" }) },
			"DUPLICATE_PLACE_ROLE",
			"definitions[1].placeRoles[2]"
		)

		local canonical = expectRegistry(assertions, { withRoles({ "Match", "Lobby" }) }):list()[1].placeRoles
		assertions.equal(canonical[1], "Lobby")
		assertions.equal(canonical[2], "Match")
	end),

	TestHarness.case("distinguishes duplicate definitions from same-name conflicts", function(assertions)
		local first = NetworkFixtures.responseRequestDefinition()
		local duplicate = NetworkFixtures.clone(first)
		duplicate.placeRoles = { "Lobby", "Match" }
		expectFailure(assertions, { first, duplicate }, "DUPLICATE_DEFINITION", "definitions[2].name")

		local conflict = NetworkFixtures.clone(first)
		conflict.response = "None"
		expectFailure(assertions, { first, conflict }, "CONFLICTING_DEFINITION", "definitions[2].name")
	end),

	TestHarness.case("rejects hostile metatables without invoking attacker metamethods", function(assertions)
		local invocationCount = 0
		local hostileMetatable = {
			__index = function()
				invocationCount += 1
				return "PRIVATE_INDEX"
			end,
			__len = function()
				invocationCount += 1
				return 1
			end,
			__pairs = function()
				invocationCount += 1
				return next, {}, nil
			end,
			__tostring = function()
				invocationCount += 1
				return "PRIVATE_TOSTRING"
			end,
			__metatable = "locked",
		}

		local hostileRoot = setmetatable({ NetworkFixtures.responseRequestDefinition() }, hostileMetatable)
		expectFailure(assertions, hostileRoot, "INVALID_TABLE", "definitions")

		local hostileDefinition = setmetatable(NetworkFixtures.responseRequestDefinition(), hostileMetatable)
		expectFailure(assertions, { hostileDefinition }, "INVALID_TABLE", "definitions[1]")

		local hostileRoles = setmetatable({ "Lobby" }, hostileMetatable)
		local definition = NetworkFixtures.responseRequestDefinition()
		definition.placeRoles = hostileRoles
		expectFailure(assertions, { definition }, "INVALID_TABLE", "definitions[1].placeRoles")
		assertions.equal(invocationCount, 0)
	end),

	TestHarness.case("keeps unknown keys rejected values and diagnostics privacy safe", function(assertions)
		local privateSentinel = "PRIVATE_REMOTE_SENTINEL_62ef"
		local definition = NetworkFixtures.responseRequestDefinition()
		definition[privateSentinel] = privateSentinel
		local errorValue = expectFailure(assertions, { definition }, "UNKNOWN_FIELD", "definitions[1]")
		assertions.isNil(string.find(errorValue.code, privateSentinel, 1, true))
		assertions.isNil(string.find(errorValue.path, privateSentinel, 1, true))
		assertions.isNil(string.find(errorValue.message, privateSentinel, 1, true))

		local coercionCount = 0
		local hostileKey = setmetatable({}, {
			__tostring = function()
				coercionCount += 1
				return privateSentinel
			end,
		})
		local nonStringKey = NetworkFixtures.responseRequestDefinition()
		nonStringKey[hostileKey] = privateSentinel
		local hostileError = expectFailure(assertions, { nonStringKey }, "UNKNOWN_FIELD", "definitions[1]")
		assertions.equal(coercionCount, 0)
		assertions.isNil(string.find(hostileError.path, privateSentinel, 1, true))
		assertions.isNil(string.find(hostileError.message, privateSentinel, 1, true))
	end),
})
