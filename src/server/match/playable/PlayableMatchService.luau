--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Log = require(ReplicatedStorage.Shared.logging.Log)
local MatchLoadoutProtocol = require(ReplicatedStorage.Shared.match.MatchLoadoutProtocol)
local PlayableMatchProtocol = require(ReplicatedStorage.Shared.match.PlayableMatchProtocol)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)

local PlayableMatchRuntime = require(script.Parent.PlayableMatchRuntime)

export type LifecycleAdapter = {
	getSnapshot: (self: LifecycleAdapter) -> any,
	getRuntimeMapSnapshot: (self: LifecycleAdapter) -> any,
	submitReady: (self: LifecycleAdapter, player: Player, matchId: unknown, revision: unknown) -> any,
	beginWaveActivation: (self: LifecycleAdapter, matchId: unknown) -> any,
	commitWaveActivation: (self: LifecycleAdapter, token: unknown) -> any,
	rollbackWaveActivation: (self: LifecycleAdapter, token: unknown) -> any,
	beginBaseDefeat: (self: LifecycleAdapter, matchId: unknown) -> any,
	commitBaseDefeat: (self: LifecycleAdapter, token: unknown) -> any,
	rollbackBaseDefeat: (self: LifecycleAdapter, token: unknown) -> any,
}

export type SnapshotSender = (recipient: unknown, snapshot: PlayableMatchProtocol.Snapshot) -> boolean
export type AttackSender = (recipient: unknown, event: PlayableMatchProtocol.AttackEvent) -> boolean
export type LoadoutProvider = (userId: number) -> MatchLoadoutProtocol.Snapshot?
export type LifecycleState = "Constructed" | "Initialized" | "Started" | "Shutdown" | "Failed"

export type RosterInputs = {
	expectedUserIds: { number },
	frozenLoadouts: { MatchLoadoutProtocol.Snapshot },
	rewarding: boolean?,
	matchId: string?,
	mapId: string?,
	difficultyId: string?,
	managedAdmissions: boolean?,
	connectedParticipantUserIds: { number }?,
}

export type Environment = {
	now: () -> number,
	generateMatchId: () -> Ids.MatchId?,
	getActivePlayers: () -> { Player },
	getUserId: (Player) -> number,
	isActivePlayer: (Player) -> boolean,
	connectPlayerAdded: ((Player) -> ()) -> RBXScriptConnection,
	connectPlayerRemoving: ((Player) -> ()) -> RBXScriptConnection,
	connectHeartbeat: (() -> ()) -> RBXScriptConnection,
	contentRoot: Instance,
}

export type Metrics = {
	state: LifecycleState,
	generation: number,
	replayBusy: boolean,
	publishPending: boolean,
	publishCount: number,
	attackPublishCount: number,
	frozenLoadoutCount: number,
	spectatorCount: number,
	runtime: PlayableMatchRuntime.Metrics?,
}

type ServiceData = {
	logger: Log.Logger,
	lifecycle: LifecycleAdapter,
	configuration: ConfigTypes.CoreConfiguration,
	snapshotSender: SnapshotSender,
	attackSender: AttackSender,
	environment: Environment,
	state: LifecycleState,
	serviceDefinition: ServiceLifecycle.ServiceDefinition?,
	runtimeMap: PlayableMatchRuntime.RuntimeMap?,
	runtime: PlayableMatchRuntime.Runtime?,
	connections: { RBXScriptConnection },
	generation: number,
	replayBusy: boolean,
	publishPending: boolean,
	lastPublishServerTime: number,
	publishCount: number,
	attackPublishCount: number,
	legacyDefeatAttempted: boolean,
	loadoutProvider: LoadoutProvider,
	frozenLoadouts: { [number]: MatchLoadoutProtocol.Snapshot },
	admittedUserIds: { [number]: boolean },
	expectedUserIds: { [number]: boolean }?,
	expectedUserIdOrder: { number }?,
	spectatorUserIds: { [number]: boolean },
	rewarding: boolean,
	fixedMatchId: Ids.MatchId?,
	fixedMapId: Ids.MapId?,
	fixedDifficultyId: Ids.DifficultyId?,
	managedAdmissions: boolean,
	initialConnectedParticipantUserIds: { number },
}

local SERVICE_NAME = "PlayableMatch"
local SNAPSHOT_INTERVAL_SECONDS = 0.1
local CONTENT_FOLDER_NAME = "ATDPlayableTemplates"
local CONTENT_CONTRACT = "playable-local-match-v1"

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

export type TestConstructor = (
	Log.Logger,
	LifecycleAdapter,
	ConfigTypes.CoreConfiguration,
	SnapshotSender,
	AttackSender,
	Environment,
	LoadoutProvider?,
	RosterInputs?
) -> Service

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local PlayableMatchService = {
	newForTests = nil :: TestConstructor?,
}

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_PLAYABLE_MATCH_SERVICE][code=INVALID_CONTEXT]", 0)
	end
	return data :: ServiceData
end

local function generateProductionMatchId(): Ids.MatchId?
	local generated, guidValue = pcall(HttpService.GenerateGUID, HttpService, false)
	if not generated or type(guidValue) ~= "string" then
		return nil
	end
	local result = Ids.makeMatchId(string.lower(guidValue :: string))
	return if result.ok then result.value else nil
end

local function productionActivePlayers(): { Player }
	local output: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player.Parent == Players and player.UserId ~= 0 then
			table.insert(output, player)
		end
	end
	table.sort(output, function(left, right)
		return left.UserId < right.UserId
	end)
	return output
end

local PRODUCTION_ENVIRONMENT: Environment = table.freeze({
	now = function(): number
		return Workspace:GetServerTimeNow()
	end,
	generateMatchId = generateProductionMatchId,
	getActivePlayers = productionActivePlayers,
	getUserId = function(player: Player): number
		return player.UserId
	end,
	isActivePlayer = function(player: Player): boolean
		return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player and player.UserId ~= 0
	end,
	connectPlayerAdded = function(callback: (Player) -> ()): RBXScriptConnection
		return Players.PlayerAdded:Connect(callback)
	end,
	connectPlayerRemoving = function(callback: (Player) -> ()): RBXScriptConnection
		return Players.PlayerRemoving:Connect(callback)
	end,
	connectHeartbeat = function(callback: () -> ()): RBXScriptConnection
		return RunService.Heartbeat:Connect(callback)
	end,
	contentRoot = ReplicatedStorage,
})

local function normalizeRosterInputs(
	value: RosterInputs?,
	configuration: ConfigTypes.CoreConfiguration
): (
	{ number }?,
	{ [number]: boolean }?,
	{ [number]: MatchLoadoutProtocol.Snapshot }?
)
	if value == nil then
		return nil, nil, {}
	end
	if
		type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or type(value.expectedUserIds) ~= "table"
		or type(value.frozenLoadouts) ~= "table"
		or #value.expectedUserIds < 1
		or #value.expectedUserIds > 4
		or #value.expectedUserIds ~= #value.frozenLoadouts
		or (value.rewarding ~= nil and type(value.rewarding) ~= "boolean")
		or (value.matchId ~= nil and type(value.matchId) ~= "string")
		or (value.mapId ~= nil and type(value.mapId) ~= "string")
		or (value.difficultyId ~= nil and type(value.difficultyId) ~= "string")
		or (value.managedAdmissions ~= nil and type(value.managedAdmissions) ~= "boolean")
		or (value.connectedParticipantUserIds ~= nil and type(value.connectedParticipantUserIds) ~= "table")
	then
		return nil, nil, nil
	end
	local order: { number } = {}
	local expected: { [number]: boolean } = {}
	local frozen: { [number]: MatchLoadoutProtocol.Snapshot } = {}
	for index, userId in value.expectedUserIds do
		local validated = MatchLoadoutProtocol.validate(value.frozenLoadouts[index], configuration)
		if not validated.ok or validated.value.userId ~= userId or userId == 0 or expected[userId] == true then
			return nil, nil, nil
		end
		expected[userId] = true
		frozen[userId] = validated.value
		table.insert(order, userId)
	end
	return table.freeze(order), expected, frozen
end

local function resolveLoadout(data: ServiceData, userId: number): MatchLoadoutProtocol.Snapshot?
	local retained = data.frozenLoadouts[userId]
	if retained ~= nil then
		return retained
	end
	local called, value = pcall(data.loadoutProvider, userId)
	if not called then
		return nil
	end
	local validated = MatchLoadoutProtocol.validate(value, data.configuration)
	if not validated.ok or validated.value.userId ~= userId then
		return nil
	end
	data.frozenLoadouts[userId] = validated.value
	return validated.value
end

local function participantLoadouts(data: ServiceData, retainedOnly: boolean): { MatchLoadoutProtocol.Snapshot }
	local output: { MatchLoadoutProtocol.Snapshot } = {}
	if data.expectedUserIdOrder ~= nil then
		for _, userId in data.expectedUserIdOrder do
			local loadout = data.frozenLoadouts[userId]
			if loadout ~= nil then
				table.insert(output, loadout)
				data.admittedUserIds[userId] = true
			end
		end
		return output
	end
	for _, player in data.environment.getActivePlayers() do
		if #output >= 4 then
			break
		end
		local userId = data.environment.getUserId(player)
		local retainedParticipant = data.admittedUserIds[userId] == true
			and (data.runtime == nil or data.runtime:isParticipantConnected(userId))
		local loadout = if userId == 0 or (retainedOnly and not retainedParticipant)
			then nil
			else resolveLoadout(data, userId)
		if loadout ~= nil then
			table.insert(output, loadout)
			data.admittedUserIds[userId] = true
		end
	end
	table.sort(output, function(left, right)
		return left.userId < right.userId
	end)
	return output
end

local function validContentTemplate(
	instance: Instance,
	assetKey: string,
	contentKind: string,
	definitionId: string
): boolean
	if not instance:IsA("Model") or instance.Name ~= assetKey or not instance.Archivable then
		return false
	end
	if
		instance:GetAttribute("ATDContentContract") ~= CONTENT_CONTRACT
		or instance:GetAttribute("AssetKey") ~= assetKey
		or instance:GetAttribute("ContentKind") ~= contentKind
		or instance:GetAttribute("DefinitionId") ~= definitionId
	then
		return false
	end
	local primaryPart = instance.PrimaryPart
	if primaryPart == nil or not primaryPart:IsDescendantOf(instance) then
		return false
	end
	local partCount = 0
	for _, descendant in instance:GetDescendants() do
		if not descendant.Archivable or descendant:IsA("LuaSourceContainer") then
			return false
		end
		if descendant:IsA("BasePart") then
			partCount += 1
			if not descendant.Anchored or descendant.CanCollide or descendant.CanTouch or descendant.CanQuery then
				return false
			end
		end
	end
	return partCount > 0
end

type ContentExpectation = {
	assetKey: string,
	contentKind: "TowerModel" | "EnemyModel",
	definitionId: string,
}

local function hasAuthenticatedContent(configuration: ConfigTypes.CoreConfiguration, contentRoot: Instance): boolean
	local matchingFolders: { Folder } = {}
	for _, child in contentRoot:GetChildren() do
		if child.Name == CONTENT_FOLDER_NAME then
			if not child:IsA("Folder") then
				return false
			end
			table.insert(matchingFolders, child)
		end
	end
	if #matchingFolders ~= 1 then
		return false
	end
	local instance = matchingFolders[1]
	if
		instance:GetAttribute("ATDContentContract") ~= CONTENT_CONTRACT
		or instance:GetAttribute("ContentVersion") ~= 1
	then
		return false
	end
	local expectations: { [string]: ContentExpectation } = {}
	local expectedCount = 0
	for _, definition in configuration.towers.ordered do
		if expectations[definition.modelAssetKey] ~= nil then
			return false
		end
		expectations[definition.modelAssetKey] = {
			assetKey = definition.modelAssetKey,
			contentKind = "TowerModel",
			definitionId = definition.id,
		}
		expectedCount += 1
	end
	for _, definition in configuration.enemies.ordered do
		if expectations[definition.modelAssetKey] ~= nil then
			return false
		end
		expectations[definition.modelAssetKey] = {
			assetKey = definition.modelAssetKey,
			contentKind = "EnemyModel",
			definitionId = definition.id,
		}
		expectedCount += 1
	end
	local children = instance:GetChildren()
	if expectedCount ~= 7 or #children ~= expectedCount then
		return false
	end
	local seen: { [string]: boolean } = {}
	for _, child in children do
		local expectation = expectations[child.Name]
		if expectation == nil or seen[child.Name] then
			return false
		end
		seen[child.Name] = true
		if not validContentTemplate(child, expectation.assetKey, expectation.contentKind, expectation.definitionId) then
			return false
		end
	end
	return true
end

local function constructRuntime(data: ServiceData, retainedOnly: boolean?): PlayableMatchRuntime.Runtime?
	local matchId = data.fixedMatchId or data.environment.generateMatchId()
	local runtimeMap = data.runtimeMap
	if matchId == nil or runtimeMap == nil then
		return nil
	end
	local loadouts = participantLoadouts(data, retainedOnly == true)
	local connectedParticipantUserIds: { number }? = nil
	if data.managedAdmissions then
		connectedParticipantUserIds = table.clone(data.initialConnectedParticipantUserIds)
	elseif data.expectedUserIds ~= nil then
		connectedParticipantUserIds = {}
		for _, player in data.environment.getActivePlayers() do
			local userId = data.environment.getUserId(player)
			if data.expectedUserIds[userId] then
				table.insert(connectedParticipantUserIds, userId)
			end
		end
	end
	local result = PlayableMatchRuntime.new({
		matchId = matchId,
		mapId = data.fixedMapId,
		difficultyId = data.fixedDifficultyId,
		configuration = data.configuration,
		runtimeMap = runtimeMap,
		participantLoadouts = loadouts,
		connectedParticipantUserIds = connectedParticipantUserIds,
		rewarding = data.rewarding,
	})
	return if result.ok then result.value else nil
end

local function runtimeSnapshot(
	data: ServiceData,
	player: Player,
	serverTimeValue: number?
): PlayableMatchProtocol.Snapshot?
	local runtime = data.runtime
	if runtime == nil or not data.environment.isActivePlayer(player) then
		return nil
	end
	local userId = data.environment.getUserId(player)
	local serverTime = serverTimeValue or data.environment.now()
	local result = if runtime:isParticipantConnected(userId)
		then runtime:getSnapshot(userId, serverTime)
		else runtime:getSpectatorSnapshot(serverTime, userId)
	return if result.ok then result.value else nil
end

local function publishAll(data: ServiceData, serverTime: number)
	local runtime = data.runtime
	if runtime == nil or data.state ~= "Started" then
		return
	end
	for _, player in data.environment.getActivePlayers() do
		local snapshot = runtimeSnapshot(data, player, serverTime)
		if snapshot ~= nil and data.snapshotSender(player, snapshot) then
			data.publishCount += 1
		end
	end
	data.lastPublishServerTime = serverTime
	data.publishPending = false
end

local function installReplacement(
	data: ServiceData,
	previous: PlayableMatchRuntime.Runtime,
	replacement: PlayableMatchRuntime.Runtime
)
	data.runtime = replacement
	data.generation += 1
	data.legacyDefeatAttempted = false
	data.publishPending = true
	data.lastPublishServerTime = 0
	previous:cleanup()
end

local function handlePlayerAdded(data: ServiceData, player: Player)
	if data.managedAdmissions then
		return
	end
	local runtime = data.runtime
	if data.state ~= "Started" or runtime == nil or not data.environment.isActivePlayer(player) then
		return
	end
	local userId = data.environment.getUserId(player)
	if runtime:hasParticipant(userId) then
		if not runtime:isParticipantConnected(userId) then
			local outcome = runtime:reconnectParticipant(userId)
			if outcome.accepted then
				data.spectatorUserIds[userId] = nil
				data.publishPending = true
			else
				data.spectatorUserIds[userId] = true
				data.publishPending = true
			end
		end
		return
	end
	local metrics = runtime:getMetrics()
	if data.expectedUserIds ~= nil or metrics.state ~= "Ready" then
		data.spectatorUserIds[userId] = true
		data.publishPending = true
		return
	end
	local loadout = resolveLoadout(data, userId)
	if loadout == nil then
		data.spectatorUserIds[userId] = true
		return
	end
	local outcome = runtime:addParticipant(loadout)
	if outcome.accepted then
		data.admittedUserIds[userId] = true
		data.spectatorUserIds[userId] = nil
		data.publishPending = true
	else
		data.frozenLoadouts[userId] = nil
		data.spectatorUserIds[userId] = true
	end
end

local function handlePlayerRemoving(data: ServiceData, player: Player)
	if data.managedAdmissions then
		return
	end
	local userId = data.environment.getUserId(player)
	data.spectatorUserIds[userId] = nil
	local runtime = data.runtime
	if data.state ~= "Started" or runtime == nil then
		return
	end
	if runtime:isParticipantConnected(userId) then
		local outcome = runtime:removeParticipant(userId, data.environment.now())
		if outcome.accepted then
			data.publishPending = true
		end
	end
end

local function receipt(
	data: ServiceData,
	player: Player,
	outcome: PlayableMatchRuntime.ActionOutcome
): PlayableMatchProtocol.ActionReceipt?
	local snapshot = runtimeSnapshot(data, player, nil)
	if snapshot == nil then
		return nil
	end
	return table.freeze({
		accepted = outcome.accepted,
		reason = outcome.reason,
		matchId = snapshot.matchId,
		revision = snapshot.revision,
		battleCash = snapshot.battleCash,
	})
end

local function activateLegacyWave(data: ServiceData)
	local snapshotResult = data.lifecycle:getSnapshot()
	if not snapshotResult.ok or snapshotResult.value.state ~= "PreWave" then
		return
	end
	local begun = data.lifecycle:beginWaveActivation(snapshotResult.value.matchId)
	if not begun.ok then
		return
	end
	local committed = data.lifecycle:commitWaveActivation(begun.value)
	if not committed.ok then
		data.lifecycle:rollbackWaveActivation(begun.value)
	end
end

local function mirrorLegacyReady(data: ServiceData, player: Player)
	local snapshotResult = data.lifecycle:getSnapshot()
	if not snapshotResult.ok then
		return
	end
	local snapshot = snapshotResult.value
	if snapshot.state == "ReadyCheck" then
		data.lifecycle:submitReady(player, snapshot.matchId, snapshot.revision)
	end
	activateLegacyWave(data)
end

local function mirrorLegacyDefeat(data: ServiceData)
	if data.legacyDefeatAttempted then
		return
	end
	data.legacyDefeatAttempted = true
	local snapshotResult = data.lifecycle:getSnapshot()
	if not snapshotResult.ok or snapshotResult.value.state ~= "WaveActive" then
		return
	end
	local begun = data.lifecycle:beginBaseDefeat(snapshotResult.value.matchId)
	if not begun.ok then
		return
	end
	local committed = data.lifecycle:commitBaseDefeat(begun.value)
	if not committed.ok then
		data.lifecycle:rollbackBaseDefeat(begun.value)
	end
end

local function heartbeat(data: ServiceData)
	if data.state ~= "Started" then
		return
	end
	local runtime = data.runtime
	if runtime == nil then
		data.state = "Failed"
		return
	end
	if not data.managedAdmissions and runtime:getMetrics().state == "Ready" then
		for _, player in data.environment.getActivePlayers() do
			local userId = data.environment.getUserId(player)
			if
				userId ~= 0
				and (
					data.admittedUserIds[userId] ~= true
					or (runtime:hasParticipant(userId) and not runtime:isParticipantConnected(userId))
				)
			then
				handlePlayerAdded(data, player)
			end
		end
	end
	local serverTime = data.environment.now()
	local stepped = runtime:step(serverTime)
	if not stepped.ok then
		data.state = "Failed"
		return
	end
	if stepped.value.changed then
		data.publishPending = true
	end
	if #stepped.value.attacks > 0 then
		for _, event in stepped.value.attacks do
			for _, player in data.environment.getActivePlayers() do
				if data.attackSender(player, event) then
					data.attackPublishCount += 1
				end
			end
		end
	end
	local metrics = runtime:getMetrics()
	if metrics.state == "Results" and metrics.result == "Defeat" then
		mirrorLegacyDefeat(data)
	end
	if data.publishPending and serverTime - data.lastPublishServerTime >= SNAPSHOT_INTERVAL_SECONDS then
		publishAll(data, serverTime)
	end
end

local function initialize(data: ServiceData)
	if data.state ~= "Constructed" then
		error("[ATD_PLAYABLE_MATCH_SERVICE][code=INVALID_INITIALIZE_STATE]", 0)
	end
	if not hasAuthenticatedContent(data.configuration, data.environment.contentRoot) then
		data.state = "Failed"
		error("[ATD_PLAYABLE_MATCH_SERVICE][code=CONTENT_TEMPLATES_INVALID]", 0)
	end
	local mapResult = data.lifecycle:getRuntimeMapSnapshot()
	if not mapResult.ok then
		data.state = "Failed"
		error("[ATD_PLAYABLE_MATCH_SERVICE][code=MAP_UNAVAILABLE]", 0)
	end
	data.runtimeMap = mapResult.value :: PlayableMatchRuntime.RuntimeMap
	data.runtime = constructRuntime(data, false)
	if data.runtime == nil then
		data.state = "Failed"
		error("[ATD_PLAYABLE_MATCH_SERVICE][code=RUNTIME_CREATION_FAILED]", 0)
	end
	data.state = "Initialized"
end

local function start(data: ServiceData)
	if data.state ~= "Initialized" then
		error("[ATD_PLAYABLE_MATCH_SERVICE][code=INVALID_START_STATE]", 0)
	end
	data.state = "Started"
	if not data.managedAdmissions then
		table.insert(
			data.connections,
			data.environment.connectPlayerAdded(function(player)
				handlePlayerAdded(data, player)
			end)
		)
		table.insert(
			data.connections,
			data.environment.connectPlayerRemoving(function(player)
				handlePlayerRemoving(data, player)
			end)
		)
	end
	table.insert(
		data.connections,
		data.environment.connectHeartbeat(function()
			heartbeat(data)
		end)
	)
	publishAll(data, data.environment.now())
end

local function shutdown(data: ServiceData)
	if data.state == "Shutdown" then
		return
	end
	data.state = "Shutdown"
	for index = #data.connections, 1, -1 do
		data.connections[index]:Disconnect()
	end
	table.clear(data.connections)
	local runtime = data.runtime
	data.runtime = nil
	if runtime ~= nil then
		runtime:cleanup()
	end
	data.runtimeMap = nil
	table.clear(data.frozenLoadouts)
	table.clear(data.admittedUserIds)
	table.clear(data.spectatorUserIds)
	data.publishPending = false
	data.replayBusy = false
end

function Methods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	return requireData(self).serviceDefinition :: ServiceLifecycle.ServiceDefinition
end

function Methods.admitAuthorized(
	self: Service,
	player: Player,
	participant: boolean
): PlayableMatchRuntime.ActionOutcome
	local data = requireData(self)
	local runtime = data.runtime
	if
		not data.managedAdmissions
		or data.state ~= "Started"
		or runtime == nil
		or not data.environment.isActivePlayer(player)
		or type(participant) ~= "boolean"
	then
		return table.freeze({ accepted = false, reason = "Unavailable" })
	end
	local userId = data.environment.getUserId(player)
	if data.expectedUserIds == nil or data.expectedUserIds[userId] ~= true or not runtime:hasParticipant(userId) then
		return table.freeze({ accepted = false, reason = "NotParticipant" })
	end
	if not participant then
		if runtime:isParticipantConnected(userId) then
			local removed = runtime:removeParticipant(userId, data.environment.now())
			if not removed.accepted then
				return removed
			end
		end
		data.spectatorUserIds[userId] = true
		data.publishPending = true
		return table.freeze({ accepted = true, reason = "Accepted" })
	end
	if runtime:isParticipantConnected(userId) then
		data.spectatorUserIds[userId] = nil
		return table.freeze({ accepted = true, reason = "Accepted" })
	end
	local outcome = runtime:reconnectParticipant(userId)
	if outcome.accepted then
		data.admittedUserIds[userId] = true
		data.spectatorUserIds[userId] = nil
		data.publishPending = true
	end
	return outcome
end

function Methods.disconnectAuthorized(self: Service, player: Player): PlayableMatchRuntime.ActionOutcome
	local data = requireData(self)
	local runtime = data.runtime
	if not data.managedAdmissions or data.state ~= "Started" or runtime == nil then
		return table.freeze({ accepted = false, reason = "Unavailable" })
	end
	local userId = data.environment.getUserId(player)
	data.spectatorUserIds[userId] = nil
	if not runtime:isParticipantConnected(userId) then
		return table.freeze({ accepted = true, reason = "Accepted" })
	end
	local outcome = runtime:removeParticipant(userId, data.environment.now())
	data.publishPending = data.publishPending or outcome.accepted
	return outcome
end

function Methods.getSnapshot(self: Service, player: Player): Result.Result<PlayableMatchProtocol.Snapshot, string>
	local snapshot = runtimeSnapshot(requireData(self), player, nil)
	return if snapshot == nil then Result.err("UNAVAILABLE") else Result.ok(snapshot)
end

function Methods.getResultEvidence(self: Service): Result.Result<PlayableMatchRuntime.ResultEvidence, string>
	local data = requireData(self)
	local runtime = data.runtime
	if data.state ~= "Started" or runtime == nil then
		return Result.err("UNAVAILABLE")
	end
	local evidence = runtime:getResultEvidence()
	return if evidence.ok then Result.ok(evidence.value) else Result.err(evidence.error.code)
end

function Methods.setRewardView(self: Service, userId: number, rewardView: unknown): PlayableMatchRuntime.ActionOutcome
	local data = requireData(self)
	local runtime = data.runtime
	if data.state ~= "Started" or runtime == nil then
		return table.freeze({ accepted = false, reason = "Unavailable" })
	end
	local outcome = runtime:setRewardView(userId, rewardView)
	data.publishPending = data.publishPending or outcome.accepted
	return outcome
end

function Methods.submitReady(
	self: Service,
	player: Player,
	payload: PlayableMatchProtocol.ReadyPayload
): PlayableMatchProtocol.ActionReceipt?
	local data = requireData(self)
	local runtime = data.runtime
	if data.state ~= "Started" or runtime == nil then
		return nil
	end
	local outcome = runtime:submitReady(data.environment.getUserId(player), payload.matchId, data.environment.now())
	if outcome.accepted then
		mirrorLegacyReady(data, player)
		data.publishPending = true
	end
	return receipt(data, player, outcome)
end

function Methods.submitPlacement(
	self: Service,
	player: Player,
	payload: PlayableMatchProtocol.PlacementPayload
): PlayableMatchProtocol.ActionReceipt?
	local data = requireData(self)
	local runtime = data.runtime
	if data.state ~= "Started" or runtime == nil then
		return nil
	end
	local outcome = runtime:placeTower(
		data.environment.getUserId(player),
		payload.matchId,
		payload.towerId,
		payload.slot,
		payload.loadoutRevision,
		payload.position,
		payload.rotationDegrees,
		data.environment.now()
	)
	data.publishPending = data.publishPending or outcome.accepted
	return receipt(data, player, outcome)
end

function Methods.submitUpgrade(
	self: Service,
	player: Player,
	payload: PlayableMatchProtocol.TowerPayload
): PlayableMatchProtocol.ActionReceipt?
	local data = requireData(self)
	local runtime = data.runtime
	if data.state ~= "Started" or runtime == nil then
		return nil
	end
	local outcome = runtime:upgradeTower(
		data.environment.getUserId(player),
		payload.matchId,
		payload.runtimeTowerId,
		payload.towerRevision
	)
	data.publishPending = data.publishPending or outcome.accepted
	return receipt(data, player, outcome)
end

function Methods.submitSell(
	self: Service,
	player: Player,
	payload: PlayableMatchProtocol.TowerPayload
): PlayableMatchProtocol.ActionReceipt?
	local data = requireData(self)
	local runtime = data.runtime
	if data.state ~= "Started" or runtime == nil then
		return nil
	end
	local outcome = runtime:sellTower(
		data.environment.getUserId(player),
		payload.matchId,
		payload.runtimeTowerId,
		payload.towerRevision
	)
	data.publishPending = data.publishPending or outcome.accepted
	return receipt(data, player, outcome)
end

function Methods.submitTargetMode(
	self: Service,
	player: Player,
	payload: PlayableMatchProtocol.TargetModePayload
): PlayableMatchProtocol.ActionReceipt?
	local data = requireData(self)
	local runtime = data.runtime
	if data.state ~= "Started" or runtime == nil then
		return nil
	end
	local outcome = runtime:setTargetMode(
		data.environment.getUserId(player),
		payload.matchId,
		payload.runtimeTowerId,
		payload.towerRevision,
		payload.targetMode
	)
	data.publishPending = data.publishPending or outcome.accepted
	return receipt(data, player, outcome)
end

function Methods.submitReplay(
	self: Service,
	player: Player,
	payload: PlayableMatchProtocol.ReplayPayload
): PlayableMatchProtocol.ActionReceipt?
	local data = requireData(self)
	local runtime = data.runtime
	if data.state ~= "Started" or runtime == nil then
		return nil
	end
	if data.replayBusy then
		return receipt(data, player, table.freeze({ accepted = false, reason = "Busy" }))
	end
	if data.rewarding then
		return receipt(data, player, table.freeze({ accepted = false, reason = "WrongState" }))
	end
	local eligibility = runtime:canReplay(data.environment.getUserId(player), payload.matchId)
	if not eligibility.accepted then
		return receipt(data, player, eligibility)
	end
	local acceptedReceipt = receipt(data, player, eligibility)
	if acceptedReceipt == nil then
		return nil
	end
	data.replayBusy = true
	local replacement = constructRuntime(data, true)
	if replacement == nil then
		data.replayBusy = false
		return receipt(data, player, table.freeze({ accepted = false, reason = "Unavailable" }))
	end
	installReplacement(data, runtime, replacement)
	data.replayBusy = false
	publishAll(data, data.environment.now())
	return acceptedReceipt
end

function Methods.getMetrics(self: Service): Metrics
	local data = requireData(self)
	local runtime = data.runtime
	local frozenLoadoutCount = 0
	for _ in data.frozenLoadouts do
		frozenLoadoutCount += 1
	end
	local spectatorCount = 0
	if runtime ~= nil then
		for _, player in data.environment.getActivePlayers() do
			if not runtime:isParticipantConnected(data.environment.getUserId(player)) then
				spectatorCount += 1
			end
		end
	end
	return table.freeze({
		state = data.state,
		generation = data.generation,
		replayBusy = data.replayBusy,
		publishPending = data.publishPending,
		publishCount = data.publishCount,
		attackPublishCount = data.attackPublishCount,
		frozenLoadoutCount = frozenLoadoutCount,
		spectatorCount = spectatorCount,
		runtime = if runtime == nil then nil else runtime:getMetrics(),
	})
end

local function construct(
	logger: Log.Logger,
	lifecycle: LifecycleAdapter,
	configuration: ConfigTypes.CoreConfiguration,
	snapshotSender: SnapshotSender,
	attackSender: AttackSender,
	environment: Environment,
	loadoutProvider: LoadoutProvider,
	rosterInputs: RosterInputs?
): Service
	local expectedUserIdOrder, expectedUserIds, frozenLoadouts = normalizeRosterInputs(rosterInputs, configuration)
	if rosterInputs ~= nil and frozenLoadouts == nil then
		error("[ATD_PLAYABLE_MATCH_SERVICE][code=INVALID_ROSTER_INPUTS]", 0)
	end
	local rewarding = rosterInputs ~= nil and rosterInputs.rewarding == true
	local managedAdmissions = rosterInputs ~= nil and rosterInputs.managedAdmissions == true
	local initialConnectedParticipantUserIds: { number } = {}
	if rosterInputs ~= nil and rosterInputs.connectedParticipantUserIds ~= nil then
		local connectedSeen: { [number]: boolean } = {}
		for _, userId in rosterInputs.connectedParticipantUserIds do
			if
				type(userId) ~= "number"
				or userId % 1 ~= 0
				or userId <= 0
				or expectedUserIds == nil
				or expectedUserIds[userId] ~= true
				or connectedSeen[userId]
			then
				error("[ATD_PLAYABLE_MATCH_SERVICE][code=INVALID_CONNECTED_PARTICIPANTS]", 0)
			end
			connectedSeen[userId] = true
			table.insert(initialConnectedParticipantUserIds, userId)
		end
	end
	local fixedMatchId: Ids.MatchId? = nil
	local fixedMapId: Ids.MapId? = nil
	local fixedDifficultyId: Ids.DifficultyId? = nil
	if
		rosterInputs ~= nil
		and (rosterInputs.matchId ~= nil or rosterInputs.mapId ~= nil or rosterInputs.difficultyId ~= nil)
	then
		local matchId = Ids.validateMatchId(rosterInputs.matchId)
		local mapId = Ids.validateMapId(rosterInputs.mapId)
		local difficultyId = Ids.validateDifficultyId(rosterInputs.difficultyId)
		local schedules = if mapId.ok then configuration.waves.byMapId[mapId.value] else nil
		if
			not matchId.ok
			or not mapId.ok
			or not difficultyId.ok
			or configuration.maps.byId[mapId.value] == nil
			or configuration.difficulties.byId[difficultyId.value] == nil
			or schedules == nil
			or schedules[difficultyId.value] == nil
		then
			error("[ATD_PLAYABLE_MATCH_SERVICE][code=INVALID_MATCH_CONTEXT]", 0)
		end
		fixedMatchId = matchId.value
		fixedMapId = mapId.value
		fixedDifficultyId = difficultyId.value
	end
	if
		managedAdmissions
		and (
			not rewarding
			or fixedMatchId == nil
			or rosterInputs == nil
			or rosterInputs.connectedParticipantUserIds == nil
		)
	then
		error("[ATD_PLAYABLE_MATCH_SERVICE][code=INVALID_MANAGED_ADMISSIONS]", 0)
	end
	local data: ServiceData = {
		logger = logger,
		lifecycle = lifecycle,
		configuration = configuration,
		snapshotSender = snapshotSender,
		attackSender = attackSender,
		environment = environment,
		state = "Constructed",
		serviceDefinition = nil,
		runtimeMap = nil,
		runtime = nil,
		connections = {},
		generation = 1,
		replayBusy = false,
		publishPending = false,
		lastPublishServerTime = 0,
		publishCount = 0,
		attackPublishCount = 0,
		legacyDefeatAttempted = false,
		loadoutProvider = loadoutProvider,
		frozenLoadouts = frozenLoadouts :: { [number]: MatchLoadoutProtocol.Snapshot },
		admittedUserIds = {},
		expectedUserIds = expectedUserIds,
		expectedUserIdOrder = expectedUserIdOrder,
		spectatorUserIds = {},
		rewarding = rewarding,
		fixedMatchId = fixedMatchId,
		fixedMapId = fixedMapId,
		fixedDifficultyId = fixedDifficultyId,
		managedAdmissions = managedAdmissions,
		initialConnectedParticipantUserIds = table.freeze(initialConnectedParticipantUserIds),
	}
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	data.serviceDefinition = table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({ "NetworkRegistry", "ProfileService", "MatchLifecycle" }),
		initialize = function()
			initialize(data)
		end,
		start = function()
			start(data)
		end,
		shutdown = function()
			shutdown(data)
		end,
	})
	DATA[service] = data
	return service
end

function PlayableMatchService.new(
	logger: Log.Logger,
	lifecycle: LifecycleAdapter,
	configuration: ConfigTypes.CoreConfiguration,
	snapshotSender: SnapshotSender,
	attackSender: AttackSender,
	loadoutProvider: LoadoutProvider,
	rosterInputs: RosterInputs?
): Service
	if type(loadoutProvider) ~= "function" then
		error("[ATD_PLAYABLE_MATCH_SERVICE][code=LOADOUT_PROVIDER_MISSING]", 0)
	end
	return construct(
		logger,
		lifecycle,
		configuration,
		snapshotSender,
		attackSender,
		PRODUCTION_ENVIRONMENT,
		loadoutProvider,
		rosterInputs
	)
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "PlayableMatchService" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionServerPlayable" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

if isExactTestModule() then
	PlayableMatchService.newForTests = function(
		logger: Log.Logger,
		lifecycle: LifecycleAdapter,
		configuration: ConfigTypes.CoreConfiguration,
		snapshotSender: SnapshotSender,
		attackSender: AttackSender,
		environment: Environment,
		loadoutProvider: LoadoutProvider?,
		rosterInputs: RosterInputs?
	): Service
		local provider = loadoutProvider
			or function(userId: number): MatchLoadoutProtocol.Snapshot?
				local slots = {}
				for index, definition in configuration.towers.ordered do
					if index > MatchLoadoutProtocol.MAX_SLOTS then
						break
					end
					table.insert(slots, {
						slot = index,
						unitId = `unit:test-{userId}-{index}`,
						towerId = definition.id,
					})
				end
				local result = MatchLoadoutProtocol.validate({
					userId = userId,
					revision = 1,
					slots = slots,
					settings = configuration.defaultSettings,
				}, configuration)
				return if result.ok then result.value else nil
			end
		return construct(
			logger,
			lifecycle,
			configuration,
			snapshotSender,
			attackSender,
			environment,
			provider,
			rosterInputs
		)
	end
end

table.freeze(Methods)
return table.freeze(PlayableMatchService)
