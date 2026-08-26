--!strict

-- This tracked harness is intentionally absent from every Rojo project. Follow
-- docs/NETWORK_SECURITY_STUDIO_REGRESSION.md; never publish or save it in a place.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:FindFirstChild("Shared")
local ServerRoot = ServerScriptService:FindFirstChild("Server")

local terminal = false
local finishing = false
local fixtureCleanup: any = nil
local fixtureRoot: Folder? = nil
local fixtureRegistry: any = nil
local limiter: any = nil
local dispatcher: any = nil

local function cleanupFixture(): (boolean, string)
	if fixtureCleanup == nil then
		return true, "NotCreated"
	end
	local succeeded = pcall(function()
		fixtureCleanup:cleanup()
	end)
	local state = fixtureCleanup:getState()
	return succeeded, state
end

local function failHarness(code: string)
	if terminal or finishing then
		return
	end
	terminal = true
	local cleanupSucceeded, cleanupState = cleanupFixture()
	local safeCleanupState = if cleanupSucceeded then cleanupState else "Failed"
	print(`[ATD_PHASE06_STUDIO][FAIL][context=server][code={code}][cleanupState={safeCleanupState}]`)
end

local function requireSetup(condition: boolean, code: string)
	if condition then
		return
	end
	failHarness(code)
	error("[ATD_PHASE06_STUDIO_ABORT]", 0)
end

if not RunService:IsStudio() or not RunService:IsServer() or not RunService:IsRunning() then
	failHarness("INVALID_RUNTIME")
	return
end

if Shared == nil or not Shared:IsA("Folder") or ServerRoot == nil or not ServerRoot:IsA("Folder") then
	failHarness("SOURCE_TREE_MISSING")
	return
end

local sourceLoaded, sourceModules = pcall(function()
	local PlaceRoles = require((Shared :: Folder).config.PlaceRoles)
	local EnvironmentContext = require((Shared :: Folder).logging.EnvironmentContext)
	local Log = require((Shared :: Folder).logging.Log)
	local PayloadValidation = require((Shared :: Folder).network.PayloadValidation)
	local RemoteRegistry = require((Shared :: Folder).network.RemoteRegistry)
	local RequestProtocol = require((Shared :: Folder).network.RequestProtocol)
	local Cleanup = require((Shared :: Folder).util.Cleanup)
	local networking = (ServerRoot :: Folder).common.networking
	local ServerRateLimiter = require(networking.ServerRateLimiter)
	local ServerRequestDispatcher = require(networking.ServerRequestDispatcher)
	return {
		PlaceRoles = PlaceRoles,
		EnvironmentContext = EnvironmentContext,
		Log = Log,
		PayloadValidation = PayloadValidation,
		RemoteRegistry = RemoteRegistry,
		RequestProtocol = RequestProtocol,
		Cleanup = Cleanup,
		ServerRateLimiter = ServerRateLimiter,
		ServerRequestDispatcher = ServerRequestDispatcher,
	}
end)

if not sourceLoaded then
	failHarness("SOURCE_LOAD_FAILED")
	return
end

local Modules = sourceModules :: any
local PlaceRoles = Modules.PlaceRoles
local EnvironmentContext = Modules.EnvironmentContext
local Log = Modules.Log
local PayloadValidation = Modules.PayloadValidation
local RemoteRegistry = Modules.RemoteRegistry
local RequestProtocol = Modules.RequestProtocol
local Cleanup = Modules.Cleanup
local ServerRateLimiter = Modules.ServerRateLimiter
local ServerRequestDispatcher = Modules.ServerRequestDispatcher

local FIXTURE_ROOT_NAME = "ATDPhase06StudioFixture"
local VERSION_NAME = "v1"
local TOTAL_TIMEOUT_SECONDS = 120
local PLAYER_CLEANUP_TIMEOUT_SECONDS = 5
local CLIENT_COUNT = 2

local IDENTITY_ENDPOINT = "StudioIdentity"
local NUMERIC_ENDPOINT = "StudioNumeric"
local DEFAULT_INSTANCE_ENDPOINT = "StudioInstanceDefault"
local EXPLICIT_INSTANCE_ENDPOINT = "StudioInstanceExplicit"
local BURST_ENDPOINT = "StudioBurst"
local HELLO_ENDPOINT = "StudioClientHello"
local COMPLETE_ENDPOINT = "StudioClientComplete"
local FINAL_ACK_ENDPOINT = "StudioFinalAck"
local ASSIGNMENT_ENDPOINT = "StudioAssignment"
local LEAVE_ENDPOINT = "StudioLeave"
local CONTINUE_ENDPOINT = "StudioContinue"
local FINISHED_ENDPOINT = "StudioFinished"

type EndpointRemotes = {
	request: RemoteEvent?,
	response: RemoteEvent?,
	event: RemoteEvent?,
}

local endpointRemotes: { [string]: EndpointRemotes } = {}
local assignedSlots: { [Player]: number } = {}
local helloPlayers: { [Player]: boolean } = {}
local completedPlayers: { [Player]: boolean } = {}
local rateReports: { any } = {}
local protocolReports: { any } = {}
local reportShapeInvalid = false
local assignmentStarted = false
local leaveStarted = false
local removalObserved = false
local finalAcknowledged = false
local continueSent = false
local coordinatorActive = true
local playerCleanupDeadline: number? = nil
local leavingPlayer: Player? = nil
local remainingPlayer: Player? = nil

local identityMutationCount = 0
local numericMutationCount = 0
local defaultInstanceMutationCount = 0
local explicitInstanceMutationCount = 0
local burstMutationCount = 0

local function countKeys(values: { [any]: any }): number
	local count = 0
	for _ in values do
		count += 1
	end
	return count
end

local function hasExactKeys(value: any, allowed: { [string]: boolean }, expectedCount: number): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for key in next, value do
		count += 1
		if type(key) ~= "string" or rawget(allowed, key) ~= true then
			return false
		end
	end
	return count == expectedCount
end

local RATE_REPORT_KEYS = table.freeze({
	code = true,
	endpoint = true,
	rateLimitRejectionCount = true,
	rateLimitWindowSeconds = true,
})

local PROTOCOL_REPORT_KEYS = table.freeze({
	code = true,
	endpoint = true,
	protocolRejectionCount = true,
	protocolWindowSeconds = true,
})

local PROTOCOL_REPORT_CODES = table.freeze({
	MALFORMED_ENVELOPE = true,
	INVALID_PLAYER = true,
	INVALID_RESPONSE_REMOTE = true,
	DUPLICATE_REQUEST = true,
	STALE_REQUEST = true,
	NOT_AUTHORIZED = true,
	INVALID_PAYLOAD = true,
	HANDLER_FAILED = true,
	INVALID_HANDLER_OUTCOME = true,
	INVALID_RESPONSE_PAYLOAD = true,
	UNAVAILABLE = true,
	RESPONSE_SEND_FAILED = true,
	MULTIPLE_SIGNALS = true,
})

local function isSafeReportCount(value: unknown, maximum: number): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value % 1 == 0
		and value >= 1
		and value <= maximum
end

local function isAllowedReportEndpoint(value: unknown): boolean
	if type(value) ~= "string" or #value > RemoteRegistry.MAX_NAME_BYTES then
		return false
	end
	if value == "<multiple>" then
		return true
	end
	local registry = fixtureRegistry
	return registry ~= nil and registry:get(value) ~= nil
end

local function captureRateReport(report: any)
	if
		not hasExactKeys(report, RATE_REPORT_KEYS, 4)
		or not table.isfrozen(report)
		or report.code ~= "RATE_LIMITED"
		or not isAllowedReportEndpoint(report.endpoint)
		or not isSafeReportCount(report.rateLimitRejectionCount, ServerRateLimiter.MAX_AGGREGATE_REJECTIONS)
		or report.rateLimitWindowSeconds ~= ServerRateLimiter.REPORT_INTERVAL_SECONDS
	then
		reportShapeInvalid = true
		return
	end
	table.insert(rateReports, report)
end

local function captureProtocolReport(report: any)
	if
		not hasExactKeys(report, PROTOCOL_REPORT_KEYS, 4)
		or not table.isfrozen(report)
		or type(report.code) ~= "string"
		or PROTOCOL_REPORT_CODES[report.code] ~= true
		or not isAllowedReportEndpoint(report.endpoint)
		or not isSafeReportCount(report.protocolRejectionCount, ServerRequestDispatcher.MAX_AGGREGATE_SIGNALS)
		or report.protocolWindowSeconds ~= ServerRequestDispatcher.REPORT_INTERVAL_SECONDS
	then
		reportShapeInvalid = true
		return
	end
	table.insert(protocolReports, report)
end

local function fireFixedEvent(remote: RemoteEvent, player: Player, payload: unknown): boolean
	local wireResult = RequestProtocol.buildEvent(payload)
	if not wireResult.ok then
		return false
	end
	local sent = pcall(function()
		remote:FireClient(player, wireResult.value)
	end)
	return sent
end

local function finishSuccessfully()
	if terminal or finishing then
		return
	end
	finishing = true

	local currentRemaining = remainingPlayer
	local currentRoot = fixtureRoot
	if currentRemaining == nil or currentRoot == nil then
		finishing = false
		failHarness("FINAL_STATE_MISSING")
		return
	end

	local limiterStats = limiter:getStats()
	local dispatcherStats = dispatcher:getStats()
	local finalChecks = {
		identityMutationCount == 5,
		numericMutationCount == 2,
		defaultInstanceMutationCount == 0,
		explicitInstanceMutationCount == 2,
		burstMutationCount == 2,
		removalObserved,
		finalAcknowledged,
		limiterStats.trackedPlayerCount == 1,
		dispatcherStats.trackedPlayerCount == 1 and dispatcherStats.pendingRequestCount == 0,
		not reportShapeInvalid and #rateReports >= 1 and #protocolReports >= 1,
	}
	local passedCheckCount = 0
	for _, passed in finalChecks do
		if passed then
			passedCheckCount += 1
		end
	end
	if passedCheckCount ~= #finalChecks then
		finishing = false
		failHarness("FINAL_ASSERTION_FAILED")
		return
	end

	local finishedRemote = endpointRemotes[FINISHED_ENDPOINT].event
	if finishedRemote == nil or not fireFixedEvent(finishedRemote, currentRemaining, { passed = true }) then
		finishing = false
		failHarness("FINAL_EVENT_FAILED")
		return
	end

	task.wait(0.25)
	local cleanupSucceeded, cleanupState = cleanupFixture()
	local rootRemoved = currentRoot.Parent == nil and ReplicatedStorage:FindFirstChild(FIXTURE_ROOT_NAME) == nil
	local childrenStopped = limiter:getState() == "Shutdown" and dispatcher:getState() == "Shutdown"
	if not cleanupSucceeded or cleanupState ~= "Cleaned" or not rootRemoved or not childrenStopped then
		terminal = true
		finishing = false
		print("[ATD_PHASE06_STUDIO][FAIL][context=server][code=FINAL_CLEANUP_FAILED][cleanupState=Failed]")
		return
	end

	terminal = true
	finishing = false
	print(
		`[ATD_PHASE06_STUDIO][PASS][context=server][caseCount={passedCheckCount}][clientCount=2][cleanupState=Cleaned]`
	)
end

local function advanceAssignment(): boolean
	if assignmentStarted or countKeys(helloPlayers) ~= CLIENT_COUNT then
		return true
	end
	assignmentStarted = true

	local activePlayers = {}
	for player in helloPlayers do
		if player.Parent == Players then
			table.insert(activePlayers, player)
		end
	end
	table.sort(activePlayers, function(left: Player, right: Player): boolean
		if left.UserId == right.UserId then
			return left.Name < right.Name
		end
		return left.UserId < right.UserId
	end)
	if #activePlayers ~= CLIENT_COUNT or #Players:GetPlayers() ~= CLIENT_COUNT then
		failHarness("CLIENT_COUNT_MISMATCH")
		return false
	end

	local assignmentRemote = endpointRemotes[ASSIGNMENT_ENDPOINT].event
	if assignmentRemote == nil then
		failHarness("ASSIGNMENT_REMOTE_MISSING")
		return false
	end
	for slot, player in activePlayers do
		assignedSlots[player] = slot
		if not fireFixedEvent(assignmentRemote, player, { slot = slot }) then
			failHarness("ASSIGNMENT_SEND_FAILED")
			return false
		end
	end
	return true
end

local function advanceLeave(): boolean
	if leaveStarted or countKeys(completedPlayers) ~= CLIENT_COUNT then
		return true
	end
	leaveStarted = true

	for player, slot in assignedSlots do
		if slot == 1 then
			leavingPlayer = player
		else
			remainingPlayer = player
		end
	end
	local leaveRemote = endpointRemotes[LEAVE_ENDPOINT].event
	if leavingPlayer == nil or remainingPlayer == nil or leaveRemote == nil then
		failHarness("LEAVE_STATE_MISSING")
		return false
	end
	if not fireFixedEvent(leaveRemote, remainingPlayer :: Player, { leave = false }) then
		failHarness("LEAVE_BARRIER_FAILED")
		return false
	end
	if not fireFixedEvent(leaveRemote, leavingPlayer :: Player, { leave = true }) then
		failHarness("LEAVE_EVENT_FAILED")
		return false
	end
	return true
end

local function advanceRemoval(): boolean
	if not removalObserved or continueSent then
		return true
	end

	local currentRemaining = remainingPlayer
	local cleanupDeadline = playerCleanupDeadline
	if currentRemaining == nil or cleanupDeadline == nil then
		failHarness("PLAYER_CLEANUP_STATE_MISSING")
		return false
	end
	local limiterStats = limiter:getStats()
	local dispatcherStats = dispatcher:getStats()
	local cleanupReady = currentRemaining.Parent == Players
		and limiterStats.trackedPlayerCount == 1
		and dispatcherStats.trackedPlayerCount == 1
		and dispatcherStats.pendingRequestCount == 0
	if cleanupReady then
		continueSent = true
		local continueRemote = endpointRemotes[CONTINUE_ENDPOINT].event
		if continueRemote == nil or not fireFixedEvent(continueRemote, currentRemaining, { continue = true }) then
			failHarness("CONTINUE_EVENT_FAILED")
			return false
		end
	elseif os.clock() >= cleanupDeadline then
		failHarness("PLAYER_CLEANUP_FAILED")
		return false
	end
	return true
end

local function advanceCoordinator()
	if not advanceAssignment() or not advanceLeave() or not advanceRemoval() then
		return
	end
	if finalAcknowledged and removalObserved then
		finishSuccessfully()
	end
end

local setupSucceeded = pcall(function()
	local roleResult = PlaceRoles.resolve(
		ReplicatedStorage:GetAttribute(PlaceRoles.ATTRIBUTE_NAME),
		game.PlaceId,
		RunService:IsStudio()
	)
	requireSetup(roleResult.ok and roleResult.role == "Match", "WRONG_PLACE_OR_ROLE")

	local productionRoot = ReplicatedStorage:WaitForChild(RemoteRegistry.ROOT_NAME, 5)
	requireSetup(productionRoot ~= nil and productionRoot:IsA("Folder"), "PRODUCTION_ROOT_MISSING")
	local productionRootCount = 0
	for _, child in ReplicatedStorage:GetChildren() do
		if child.Name == RemoteRegistry.ROOT_NAME then
			productionRootCount += 1
		end
	end
	requireSetup(productionRootCount == 1, "PRODUCTION_ROOT_NOT_UNIQUE")
	local productionVersion = (productionRoot :: Folder):FindFirstChild(RemoteRegistry.VERSION_NAME)
	requireSetup(
		productionVersion ~= nil and productionVersion:IsA("Folder") and #productionVersion:GetChildren() == 0,
		"PRODUCTION_ROOT_NOT_EMPTY"
	)
	requireSetup(ReplicatedStorage:FindFirstChild(FIXTURE_ROOT_NAME) == nil, "FIXTURE_ROOT_CONFLICT")

	local definitions = {
		{
			name = IDENTITY_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ClientToServer",
			kind = "Request",
			response = "Required",
			placeRoles = { "Match" },
		},
		{
			name = NUMERIC_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ClientToServer",
			kind = "Request",
			response = "Required",
			placeRoles = { "Match" },
		},
		{
			name = DEFAULT_INSTANCE_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ClientToServer",
			kind = "Request",
			response = "Required",
			placeRoles = { "Match" },
		},
		{
			name = EXPLICIT_INSTANCE_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ClientToServer",
			kind = "Request",
			response = "Required",
			placeRoles = { "Match" },
		},
		{
			name = BURST_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ClientToServer",
			kind = "Request",
			response = "Required",
			placeRoles = { "Match" },
		},
		{
			name = HELLO_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ClientToServer",
			kind = "Event",
			response = "None",
			placeRoles = { "Match" },
		},
		{
			name = COMPLETE_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ClientToServer",
			kind = "Event",
			response = "None",
			placeRoles = { "Match" },
		},
		{
			name = FINAL_ACK_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ClientToServer",
			kind = "Event",
			response = "None",
			placeRoles = { "Match" },
		},
		{
			name = ASSIGNMENT_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ServerToClient",
			kind = "Event",
			response = "None",
			placeRoles = { "Match" },
		},
		{
			name = LEAVE_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ServerToClient",
			kind = "Event",
			response = "None",
			placeRoles = { "Match" },
		},
		{
			name = CONTINUE_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ServerToClient",
			kind = "Event",
			response = "None",
			placeRoles = { "Match" },
		},
		{
			name = FINISHED_ENDPOINT,
			transport = "ReliableRemoteEvent",
			direction = "ServerToClient",
			kind = "Event",
			response = "None",
			placeRoles = { "Match" },
		},
	}
	local registryResult = RemoteRegistry.create(definitions)
	requireSetup(registryResult.ok, "REGISTRY_CREATION_FAILED")
	local registry = registryResult.value
	fixtureRegistry = registry

	local context = EnvironmentContext.new("server", "Match", game.PlaceId, true)
	local logger = Log.new(context)
	fixtureCleanup = Cleanup.new(logger, "phase06-studio-network")
	fixtureCleanup:add(function()
		coordinatorActive = false
	end)

	local root = Instance.new("Folder")
	root.Name = FIXTURE_ROOT_NAME
	fixtureRoot = root
	fixtureCleanup:add(root)
	local version = Instance.new("Folder")
	version.Name = VERSION_NAME
	version.Parent = root
	local objectFolder = Instance.new("Folder")
	objectFolder.Name = "FixtureObjects"
	objectFolder.Parent = root
	local allowedPart = Instance.new("Part")
	allowedPart.Name = "AllowedPart"
	allowedPart.Anchored = true
	allowedPart.Parent = objectFolder
	local wrongClass = Instance.new("Folder")
	wrongClass.Name = "WrongClass"
	wrongClass.Parent = objectFolder
	local outsidePart = Instance.new("Part")
	outsidePart.Name = "OutsidePart"
	outsidePart.Anchored = true
	outsidePart.Parent = root

	for _, definition in registry:listForRole("Match") do
		local endpoint = Instance.new("Folder")
		endpoint.Name = definition.name
		endpoint.Parent = version
		local remotes: EndpointRemotes = {
			request = nil,
			response = nil,
			event = nil,
		}
		if definition.kind == "Request" then
			local request = Instance.new("RemoteEvent")
			request.Name = "Request"
			request.Parent = endpoint
			remotes.request = request
			if definition.response == "Required" then
				local response = Instance.new("RemoteEvent")
				response.Name = "Response"
				response.Parent = endpoint
				remotes.response = response
			end
		else
			local event = Instance.new("RemoteEvent")
			event.Name = "Event"
			event.Parent = endpoint
			remotes.event = event
		end
		endpointRemotes[definition.name] = remotes
	end

	local function policy(capacity: number): any
		local result = ServerRateLimiter.createPolicy(capacity, 0.01)
		requireSetup(result.ok, "POLICY_CREATION_FAILED")
		return result.value
	end

	local capacities = {
		[IDENTITY_ENDPOINT] = 5,
		[NUMERIC_ENDPOINT] = 4,
		[DEFAULT_INSTANCE_ENDPOINT] = 1,
		[EXPLICIT_INSTANCE_ENDPOINT] = 3,
		[BURST_ENDPOINT] = 1,
		[HELLO_ENDPOINT] = 1,
		[COMPLETE_ENDPOINT] = 1,
		[FINAL_ACK_ENDPOINT] = 1,
	}
	local policyBindings = {}
	for _, definition in registry:list() do
		if definition.direction == "ClientToServer" then
			table.insert(policyBindings, {
				endpoint = definition.name,
				policy = policy(capacities[definition.name]),
			})
		end
	end
	local policySetResult = ServerRateLimiter.createPolicySet(registry, "Match", policyBindings)
	requireSetup(policySetResult.ok, "POLICY_SET_FAILED")

	limiter = ServerRateLimiter.new(logger, Players, policySetResult.value, os.clock, nil, captureRateReport)
	local limiterCleanup = limiter:initialize()
	fixtureCleanup:add(limiterCleanup)

	dispatcher = ServerRequestDispatcher.new(logger, registry, "Match", Players, limiter, {
		clock = os.clock,
		reporter = captureProtocolReport,
		sender = function(remote: RemoteEvent, originatingPlayer: Player, envelope: any)
			remote:FireClient(originatingPlayer, envelope)
		end,
	})

	local identitySchema = PayloadValidation.schema(PayloadValidation.record({
		value = PayloadValidation.integer(1, 1),
	}))
	local slotResponseSchema = PayloadValidation.schema(PayloadValidation.record({
		slot = PayloadValidation.integer(1, CLIENT_COUNT),
	}))
	local numericSchema = PayloadValidation.schema(PayloadValidation.record({
		vector2 = PayloadValidation.vector2(),
		vector3 = PayloadValidation.vector3(),
		transform = PayloadValidation.cframe(),
	}))
	local acceptedResponseSchema = PayloadValidation.schema(PayloadValidation.record({
		accepted = PayloadValidation.boolean(),
	}))
	local defaultInstanceSchema = PayloadValidation.schema(PayloadValidation.record({
		reference = PayloadValidation.string(16, 1),
	}))
	local explicitInstanceSchema = PayloadValidation.schema(PayloadValidation.record({
		reference = PayloadValidation.instance(PayloadValidation.instancePolicy("Part", objectFolder, false)),
	}))
	local trueSchema = PayloadValidation.schema(PayloadValidation.record({
		complete = PayloadValidation.boolean(),
	}))
	local helloSchema = PayloadValidation.schema(PayloadValidation.record({
		ready = PayloadValidation.boolean(),
	}))

	local function definition(name: string): any
		local value = registry:get(name)
		requireSetup(value ~= nil, "DEFINITION_MISSING")
		return value
	end

	local function assignedAuthorizer(serverContext: any): boolean
		return assignedSlots[serverContext.player] ~= nil
	end

	local contracts: { [string]: any } = {}
	contracts[IDENTITY_ENDPOINT] = ServerRequestDispatcher.createRequestContract(
		registry,
		"Match",
		definition(IDENTITY_ENDPOINT),
		identitySchema,
		slotResponseSchema,
		assignedAuthorizer,
		function(serverContext: any, _payload: any): any
			local slot = assignedSlots[serverContext.player]
			if slot == nil then
				return ServerRequestDispatcher.success({ slot = 0 })
			end
			identityMutationCount += 1
			return ServerRequestDispatcher.success({ slot = slot })
		end
	)
	contracts[NUMERIC_ENDPOINT] = ServerRequestDispatcher.createRequestContract(
		registry,
		"Match",
		definition(NUMERIC_ENDPOINT),
		numericSchema,
		acceptedResponseSchema,
		assignedAuthorizer,
		function(_serverContext: any, _payload: any): any
			numericMutationCount += 1
			return ServerRequestDispatcher.success({ accepted = true })
		end
	)
	contracts[DEFAULT_INSTANCE_ENDPOINT] = ServerRequestDispatcher.createRequestContract(
		registry,
		"Match",
		definition(DEFAULT_INSTANCE_ENDPOINT),
		defaultInstanceSchema,
		acceptedResponseSchema,
		assignedAuthorizer,
		function(_serverContext: any, _payload: any): any
			defaultInstanceMutationCount += 1
			return ServerRequestDispatcher.success({ accepted = true })
		end
	)
	contracts[EXPLICIT_INSTANCE_ENDPOINT] = ServerRequestDispatcher.createRequestContract(
		registry,
		"Match",
		definition(EXPLICIT_INSTANCE_ENDPOINT),
		explicitInstanceSchema,
		acceptedResponseSchema,
		assignedAuthorizer,
		function(_serverContext: any, payload: any): any
			if payload.reference ~= allowedPart then
				return ServerRequestDispatcher.success({ accepted = false })
			end
			explicitInstanceMutationCount += 1
			return ServerRequestDispatcher.success({ accepted = true })
		end
	)
	contracts[BURST_ENDPOINT] = ServerRequestDispatcher.createRequestContract(
		registry,
		"Match",
		definition(BURST_ENDPOINT),
		identitySchema,
		acceptedResponseSchema,
		assignedAuthorizer,
		function(_serverContext: any, _payload: any): any
			burstMutationCount += 1
			return ServerRequestDispatcher.success({ accepted = true })
		end
	)

	contracts[HELLO_ENDPOINT] = ServerRequestDispatcher.createEventContract(
		registry,
		"Match",
		definition(HELLO_ENDPOINT),
		helloSchema,
		function(serverContext: any): boolean
			return serverContext.player.Parent == Players
		end,
		function(serverContext: any, payload: any): any
			if payload.ready == true and helloPlayers[serverContext.player] ~= true then
				helloPlayers[serverContext.player] = true
			end
			return ServerRequestDispatcher.success(nil)
		end
	)

	contracts[COMPLETE_ENDPOINT] = ServerRequestDispatcher.createEventContract(
		registry,
		"Match",
		definition(COMPLETE_ENDPOINT),
		trueSchema,
		assignedAuthorizer,
		function(serverContext: any, payload: any): any
			if payload.complete == true then
				completedPlayers[serverContext.player] = true
			end
			return ServerRequestDispatcher.success(nil)
		end
	)

	contracts[FINAL_ACK_ENDPOINT] = ServerRequestDispatcher.createEventContract(
		registry,
		"Match",
		definition(FINAL_ACK_ENDPOINT),
		trueSchema,
		assignedAuthorizer,
		function(serverContext: any, payload: any): any
			if payload.complete == true and serverContext.player == remainingPlayer and removalObserved then
				finalAcknowledged = true
			end
			return ServerRequestDispatcher.success(nil)
		end
	)

	for _, definitionValue in registry:listForRole("Match") do
		if definitionValue.direction == "ClientToServer" then
			dispatcher:registerContract(contracts[definitionValue.name])
		end
	end
	local dispatcherCleanup = dispatcher:initialize()
	fixtureCleanup:add(dispatcherCleanup)
	limiter:start()
	dispatcher:start()

	for _, definitionValue in registry:listForRole("Match") do
		if definitionValue.direction == "ClientToServer" then
			local remotes = endpointRemotes[definitionValue.name]
			local inbound = if definitionValue.kind == "Request" then remotes.request else remotes.event
			requireSetup(inbound ~= nil, "INBOUND_REMOTE_MISSING")
			local response = remotes.response
			local contract = contracts[definitionValue.name]
			fixtureCleanup:add((inbound :: RemoteEvent).OnServerEvent:Connect(function(player: Player, ...: unknown)
				dispatcher:dispatch(contract, response, player, ...)
			end))
		end
	end

	fixtureCleanup:add(Players.PlayerRemoving:Connect(function(player: Player)
		if terminal or finishing then
			return
		end
		if player ~= leavingPlayer then
			failHarness("UNEXPECTED_PLAYER_REMOVAL")
			return
		end
		removalObserved = true
		playerCleanupDeadline = os.clock() + PLAYER_CLEANUP_TIMEOUT_SECONDS
	end))

	requireSetup(ReplicatedStorage:FindFirstChild(FIXTURE_ROOT_NAME) == nil, "LATE_FIXTURE_ROOT_CONFLICT")
	root.Parent = ReplicatedStorage
	requireSetup(root.Parent == ReplicatedStorage, "FIXTURE_PUBLICATION_FAILED")
end)

if not setupSucceeded and not terminal then
	failHarness("SETUP_FAILED")
	return
end

if terminal then
	return
end

local coordinatorDeadline = os.clock() + TOTAL_TIMEOUT_SECONDS
while coordinatorActive and not terminal do
	local advanced = pcall(advanceCoordinator)
	if not advanced then
		finishing = false
		failHarness("COORDINATOR_FAILED")
	end
	if coordinatorActive and not terminal then
		if os.clock() >= coordinatorDeadline then
			failHarness("TIMEOUT")
		else
			task.wait()
		end
	end
end
