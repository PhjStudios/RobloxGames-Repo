--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local ContentSelection = require(ReplicatedStorage.Shared.config.ContentSelection)
local MatchLoadoutProtocol = require(ReplicatedStorage.Shared.match.MatchLoadoutProtocol)
local MatchTravelProtocol = require(ReplicatedStorage.Shared.match.MatchTravelProtocol)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local matchRoot = script.Parent.Parent
local rewardsRoot = matchRoot:FindFirstChild("rewards") or matchRoot:FindFirstChild("ProductionServerMatchRewards")
local admissionRoot = matchRoot:FindFirstChild("admission")
	or matchRoot:FindFirstChild("ProductionServerMatchAdmission")
if rewardsRoot == nil or admissionRoot == nil then
	error("[ATD_MATCH_TRAVEL_HOST][code=DEPENDENCY_FOLDER_MISSING]", 0)
end
local MatchResultContract = require((rewardsRoot :: Instance):FindFirstChild("MatchResultContract") :: ModuleScript)
local RematchCoordinator = require((admissionRoot :: Instance):FindFirstChild("RematchCoordinator") :: ModuleScript)

export type ErrorCode =
	"INVALID_DEPENDENCIES"
	| "INVALID_ARGUMENT"
	| "UNAVAILABLE"
	| "NOT_AUTHORIZED"
	| "STALE_REVISION"
	| "PROFILE_RELEASE_FAILED"
	| "RETURN_UNAVAILABLE"
	| "TELEPORT_FAILED"
	| "REMATCH_UNAVAILABLE"
	| "CLEANED"
export type Operation = "new" | "step" | "snapshot" | "return" | "rematch" | "cleanup"
export type HostError = { code: ErrorCode, operation: Operation }

export type Environment = {
	now: () -> unknown,
	getUserId: (unknown) -> unknown,
	isLive: (unknown) -> unknown,
	getPlayers: () -> unknown,
	getRoutingData: (unknown) -> unknown,
	connectPlayerAdded: ((unknown) -> ()) -> unknown,
	connectPlayerRemoving: ((unknown) -> ()) -> unknown,
	connectHeartbeat: (() -> ()) -> unknown,
	scheduleReturn: (() -> ()) -> unknown,
	scheduleRematch: (() -> ()) -> unknown,
	destinationJobId: string,
	lobbyPlaceId: number,
	generateReturnId: () -> unknown,
	safeReturnUnexpected: (unknown, string) -> unknown,
}

export type Dependencies = {
	configuration: unknown,
	profile: unknown,
	ticketStore: unknown,
	admission: unknown,
	routes: unknown,
	returnRecords: unknown,
	profileTransfer: unknown,
	teleport: unknown,
	resultLedger: unknown,
	rewardClaims: unknown,
	observeDurableResult: ((number, unknown) -> unknown)?,
	snapshotSender: (unknown, MatchTravelProtocol.Snapshot) -> unknown,
	playableFactory: (unknown, { number }) -> unknown,
	stopPlayable: (unknown) -> unknown,
	createRematch: ({ number }, unknown) -> unknown,
	stepDependencies: () -> unknown,
	prepareCleanupDependencies: () -> unknown,
	cleanupDependencies: () -> unknown,
	environment: Environment,
}

type Binding = { player: unknown, role: MatchTravelProtocol.ViewerRole }
type ReturnSession = {
	returnId: string,
	matchId: string,
	pendingCount: number,
	departedCount: number,
	failedCount: number,
}
type PendingReturn = {
	userId: number,
	player: unknown,
	handle: unknown,
	session: ReturnSession,
	deadline: number,
	rollbackPending: boolean?,
	publicFailure: string?,
}
type PendingArrival = { player: unknown, routing: TravelProtocol.RoutingData, queuedAt: number }
type ClaimedArrival = { player: unknown, ticket: any, outcome: any, queuedAt: number }
type DepartedCleanup = { userId: number, matchId: string }
type StoredReceipt = { userId: number, operation: "return" | "rematch", receipt: MatchTravelProtocol.MutationReceipt }
type ReturnWork = {
	ticket: any,
	userIds: { number },
	players: { unknown },
	handles: { unknown },
	running: boolean,
	rollbackPending: boolean,
}
type HostData = {
	dependencies: Dependencies,
	state: "Constructed" | "Initialized" | "Started" | "Shutdown" | "Failed",
	ticket: any?,
	playable: any?,
	pendingByPlayer: { [any]: PendingArrival },
	claimedByPlayer: { [any]: ClaimedArrival },
	bindingsByUserId: { [number]: Binding },
	bindingsByPlayer: { [any]: number },
	admittedParticipantsByUserId: { [number]: boolean },
	initialArrivalsByUserId: { [number]: boolean },
	returnStatuses: { [number]: MatchTravelProtocol.ReturnStatus },
	publicFailures: { [number]: string },
	pendingReturnsByUserId: { [number]: PendingReturn },
	pendingReturnsByPlayer: { [any]: PendingReturn },
	returnSessionsById: { [string]: ReturnSession },
	departedCleanupByUserId: { [number]: DepartedCleanup },
	connections: { any },
	revision: number,
	routesBound: boolean,
	stepRunning: boolean,
	ingressOperationsRunning: number,
	publicationsRunning: number,
	returnBusy: boolean,
	activeReturnWork: ReturnWork?,
	shutdownRequested: boolean,
	dependencyCleanupJoining: boolean,
	resultCreated: boolean,
	resultFailed: boolean,
	resultFailureReason: string?,
	resultRecord: any?,
	resultReady: boolean,
	durableResultObservedByUserId: { [number]: boolean },
	rematchSuppressedForTutorial: boolean,
	lastIntentRenewalAt: number,
	lastRewardAttemptAt: number,
	rewardTerminalByUserId: { [number]: boolean },
	rematch: any?,
	rematchRevisionObserved: number,
	publishedFingerprintByUserId: { [number]: string },
	receipts: { [string]: StoredReceipt },
	receiptOrder: { string },
	cleaned: boolean,
}

local SERVICE_NAME = "MatchTravelHost"
local PROFILE_WAIT_SECONDS = 30
local REWARD_RETRY_SECONDS = 1
local INTENT_RENEWAL_SECONDS = 60
local RETURN_INIT_TIMEOUT_SECONDS = 30
local MAX_RECEIPTS = 32
local SHUTDOWN_DURABILITY_ATTEMPTS = 3
local SHUTDOWN_JOIN_SECONDS = 8
local SHUTDOWN_POLL_SECONDS = 0.05

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: HostData }
local MatchTravelHost = {
	PROFILE_WAIT_SECONDS = PROFILE_WAIT_SECONDS,
	MAX_RECEIPTS = MAX_RECEIPTS,
	SHUTDOWN_DURABILITY_ATTEMPTS = SHUTDOWN_DURABILITY_ATTEMPTS,
}

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<HostError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): HostData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_MATCH_TRAVEL_HOST][code=INVALID_CONTEXT]", 0)
	end
	return data :: HostData
end

local function resultOk(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function now(data: HostData): number?
	local called, value = pcall(data.dependencies.environment.now)
	return if called and type(value) == "number" and Validation.isSafeInteger(value) and value >= 0 then value else nil
end

local function readUserId(data: HostData, player: unknown): number?
	local called, value = pcall(data.dependencies.environment.getUserId, player)
	return if called and type(value) == "number" and Validation.isSafeInteger(value) and value > 0 then value else nil
end

local function isLive(data: HostData, player: unknown): boolean
	local called, value = pcall(data.dependencies.environment.isLive, player)
	return called and value == true
end

local function bump(data: HostData)
	if data.revision < Validation.MAX_SAFE_INTEGER then
		data.revision += 1
	end
end

local function safeReject(data: HostData, player: unknown, reason: string)
	data.pendingByPlayer[player :: any] = nil
	data.claimedByPlayer[player :: any] = nil
	pcall(data.dependencies.environment.safeReturnUnexpected, player, reason)
end

local function retainClaimed(data: HostData, pending: PendingArrival, ticket: any, outcome: any)
	pcall(data.dependencies.admission.disconnect, data.dependencies.admission, pending.player)
	data.pendingByPlayer[pending.player :: any] = nil
	data.claimedByPlayer[pending.player :: any] = {
		player = pending.player,
		ticket = ticket,
		outcome = outcome,
		queuedAt = pending.queuedAt,
	}
	data.ticket = ticket
end

local function exactPlayerList(data: HostData): { unknown }
	local called, value = pcall(data.dependencies.environment.getPlayers)
	if not called or type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return {}
	end
	local output: { unknown } = {}
	for _, player in value :: { unknown } do
		if isLive(data, player) and readUserId(data, player) ~= nil then
			table.insert(output, player)
		end
	end
	return output
end

local function ticketMember(ticket: any, userId: number): any?
	if type(ticket) ~= "table" or type(ticket.members) ~= "table" then
		return nil
	end
	for _, member in ticket.members do
		if type(member) == "table" and member.userId == userId then
			return member
		end
	end
	return nil
end

local function preflightTicket(data: HostData, ticket: unknown): any?
	if type(ticket) ~= "table" then
		return nil
	end
	local value = ticket :: any
	local configuration = data.dependencies.configuration :: any
	local map = configuration.maps.byId[value.mapId]
	local difficulty = configuration.difficulties.byId[value.difficultyId]
	local schedules = configuration.waves.byMapId[value.mapId]
	if
		map == nil
		or difficulty == nil
		or schedules == nil
		or schedules[value.difficultyId] == nil
		or type(value.expectedUserIds) ~= "table"
		or type(value.members) ~= "table"
		or #value.expectedUserIds < 1
		or #value.expectedUserIds > 4
		or #value.expectedUserIds ~= #value.members
		or (
			value.claimedDestinationJobId ~= nil
			and value.claimedDestinationJobId ~= data.dependencies.environment.destinationJobId
		)
	then
		return nil
	end
	local seen: { [number]: boolean } = {}
	for index, userId in value.expectedUserIds do
		local member = value.members[index]
		local loadout = if type(member) == "table"
			then MatchLoadoutProtocol.validate(member.loadout, configuration)
			else nil
		if
			type(userId) ~= "number"
			or not Validation.isSafeInteger(userId)
			or userId <= 0
			or seen[userId]
			or member == nil
			or member.userId ~= userId
			or loadout == nil
			or not loadout.ok
			or loadout.value.userId ~= userId
		then
			return nil
		end
		seen[userId] = true
	end
	return value
end

local function ticketFromResult(value: unknown): any?
	if not resultOk(value) then
		return nil
	end
	local stored = (value :: any).value
	return if type(stored) == "table" and type(stored.ticket) == "table" then stored.ticket else stored
end

local function getTicket(data: HostData, ticketId: string, currentTime: number): any?
	local called, resultValue =
		pcall(data.dependencies.ticketStore.get, data.dependencies.ticketStore, ticketId, currentTime)
	return if called then preflightTicket(data, ticketFromResult(resultValue)) else nil
end

local function bindRoutes(data: HostData, ticket: any, currentTime: number): boolean
	if data.routesBound then
		return true
	end
	for _, userId in ticket.expectedUserIds do
		local called, resultValue = pcall(
			data.dependencies.routes.bindDestination,
			data.dependencies.routes,
			userId,
			ticket.matchId,
			data.dependencies.environment.destinationJobId,
			currentTime
		)
		if not called or not resultOk(resultValue) then
			return false
		end
	end
	data.routesBound = true
	return true
end

local function createPlayable(data: HostData, ticket: any, connectedUserId: number): boolean
	local called, resultValue = pcall(data.dependencies.playableFactory, ticket, { connectedUserId })
	if not called or not resultOk(resultValue) or type((resultValue :: any).value) ~= "table" then
		return false
	end
	data.ticket = ticket
	data.playable = (resultValue :: any).value
	return true
end

local function recordBinding(data: HostData, player: unknown, outcome: any): boolean
	local playable = data.playable
	if playable == nil then
		return false
	end
	local participant = outcome.kind == "Participant" or outcome.kind == "Rejoined"
	local called, connected = pcall(playable.admitAuthorized, playable, player, participant)
	if not called or type(connected) ~= "table" or connected.accepted ~= true then
		return false
	end
	local role: MatchTravelProtocol.ViewerRole = if participant then "Participant" else "Spectator"
	local userId = outcome.userId
	data.bindingsByUserId[userId] = { player = player, role = role }
	data.bindingsByPlayer[player :: any] = userId
	if participant then
		data.admittedParticipantsByUserId[userId] = true
	end
	if outcome.kind == "Participant" or outcome.kind == "LateSpectator" then
		data.initialArrivalsByUserId[userId] = true
	end
	data.pendingByPlayer[player :: any] = nil
	bump(data)
	return true
end

local function processArrival(data: HostData, pending: PendingArrival, currentTime: number)
	local player = pending.player
	if not isLive(data, player) then
		data.pendingByPlayer[player :: any] = nil
		return
	end
	local userId = readUserId(data, player)
	if userId == nil then
		safeReject(data, player, "INVALID_PLAYER")
		return
	end
	local profileStateCalled, profileState =
		pcall(data.dependencies.profile.getState, data.dependencies.profile, userId)
	if not profileStateCalled or profileState ~= "Ready" then
		if profileState == "Failed" or currentTime >= pending.queuedAt + PROFILE_WAIT_SECONDS then
			safeReject(data, player, "PROFILE_UNAVAILABLE")
		end
		return
	end

	local initialTicket: any? = nil
	if pending.routing.kind == "Match" then
		initialTicket = getTicket(data, pending.routing.ticketId, currentTime)
		if
			initialTicket == nil
			or (data.ticket ~= nil and data.ticket.ticketId ~= initialTicket.ticketId)
			or ticketMember(initialTicket, userId) == nil
		then
			safeReject(data, player, "TICKET_REJECTED")
			return
		end
	elseif data.ticket == nil then
		safeReject(data, player, "STALE_ROUTE")
		return
	end

	local admittedCalled, admitted = pcall(
		data.dependencies.admission.admit,
		data.dependencies.admission,
		player,
		pending.routing,
		data.dependencies.environment.destinationJobId,
		currentTime
	)
	if not admittedCalled or not resultOk(admitted) then
		safeReject(data, player, "ADMISSION_REJECTED")
		return
	end
	local outcome = (admitted :: any).value
	local ticket = initialTicket
	if pending.routing.kind == "Rejoin" then
		ticket = data.ticket
	elseif ticket == nil then
		ticket = getTicket(data, outcome.ticketId, currentTime)
	else
		ticket = getTicket(data, ticket.ticketId, currentTime)
	end
	if
		ticket == nil
		or ticket.ticketId ~= outcome.ticketId
		or ticket.matchId ~= outcome.matchId
		or ticketMember(ticket, userId) == nil
	then
		pcall(data.dependencies.admission.disconnect, data.dependencies.admission, player)
		safeReject(data, player, "TICKET_REJECTED")
		return
	end
	if data.playable == nil then
		if outcome.kind ~= "Participant" then
			pcall(data.dependencies.admission.disconnect, data.dependencies.admission, player)
			safeReject(data, player, "HOST_UNAVAILABLE")
			return
		end
		if not bindRoutes(data, ticket, currentTime) or not createPlayable(data, ticket, userId) then
			retainClaimed(data, pending, ticket, outcome)
			return
		end
	end
	if not recordBinding(data, player, outcome) then
		retainClaimed(data, pending, ticket, outcome)
	end
end

local function processClaimed(data: HostData, claimed: ClaimedArrival, currentTime: number)
	local player = claimed.player
	local userId = readUserId(data, player)
	if not isLive(data, player) or userId == nil then
		data.claimedByPlayer[player :: any] = nil
		return
	end
	if currentTime >= claimed.queuedAt + PROFILE_WAIT_SECONDS then
		safeReject(data, player, "HOST_UNAVAILABLE")
		return
	end
	if not bindRoutes(data, claimed.ticket, currentTime) then
		return
	end
	local foundCalled, found = pcall(data.dependencies.routes.find, data.dependencies.routes, userId, currentTime)
	local route = if foundCalled and resultOk(found) then (found :: any).value else nil
	local routing = if type(route) == "table" then TravelProtocol.rejoin(route.routeId, "attempt:host-rebind") else nil
	if routing == nil or not routing.ok then
		return
	end
	local admittedCalled, admitted = pcall(
		data.dependencies.admission.admit,
		data.dependencies.admission,
		player,
		routing.value,
		data.dependencies.environment.destinationJobId,
		currentTime
	)
	if not admittedCalled or not resultOk(admitted) then
		return
	end
	local outcome = (admitted :: any).value
	if outcome.kind ~= "Rejoined" or outcome.userId ~= userId or outcome.ticketId ~= claimed.ticket.ticketId then
		pcall(data.dependencies.admission.disconnect, data.dependencies.admission, player)
		safeReject(data, player, "ADMISSION_REJECTED")
		return
	end
	if data.playable == nil and not createPlayable(data, claimed.ticket, userId) then
		pcall(data.dependencies.admission.disconnect, data.dependencies.admission, player)
		return
	end
	if not recordBinding(data, player, outcome) then
		pcall(data.dependencies.admission.disconnect, data.dependencies.admission, player)
		return
	end
	data.claimedByPlayer[player :: any] = nil
end

local function enqueue(data: HostData, player: unknown)
	if data.cleaned or data.shutdownRequested or not isLive(data, player) then
		return
	end
	local readCalled, rawRouting = pcall(data.dependencies.environment.getRoutingData, player)
	local routing = if readCalled then TravelProtocol.validateRoutingData(rawRouting) else nil
	if routing == nil or not routing.ok or routing.value.kind == "Return" then
		safeReject(data, player, "MALFORMED_JOIN_DATA")
		return
	end
	local currentTime = now(data)
	if currentTime == nil then
		safeReject(data, player, "CLOCK_UNAVAILABLE")
		return
	end
	data.pendingByPlayer[player :: any] = { player = player, routing = routing.value, queuedAt = currentTime }
end

local function eligibleRematchRoster(data: HostData): { number }?
	local output: { number } = {}
	local ticket = data.ticket
	if ticket == nil then
		return nil
	end
	for _, userId in ticket.expectedUserIds do
		if data.admittedParticipantsByUserId[userId] then
			local binding = data.bindingsByUserId[userId]
			if binding == nil or binding.role ~= "Participant" or not isLive(data, binding.player) then
				return nil
			end
			table.insert(output, userId)
		end
	end
	return if #output > 0 then output else nil
end

local function readyGateOpen(data: HostData, currentTime: number): boolean
	local ticket = data.ticket
	if ticket == nil or type(ticket.claimedDestinationAt) ~= "number" then
		return false
	end
	for _, userId in ticket.expectedUserIds do
		if data.initialArrivalsByUserId[userId] ~= true then
			return currentTime >= ticket.claimedDestinationAt + 30
		end
	end
	return true
end

local function createRematch(data: HostData)
	local roster = eligibleRematchRoster(data)
	if
		data.rematch ~= nil
		or data.ticket == nil
		or roster == nil
		or data.rematchSuppressedForTutorial
		or data.shutdownRequested
		or data.returnBusy
		or data.activeReturnWork ~= nil
		or next(data.pendingReturnsByUserId) ~= nil
	then
		return
	end
	local created = RematchCoordinator.new(
		{ matchId = data.ticket.matchId, resultId = data.ticket.resultId, ticketId = data.ticket.ticketId },
		function()
			return eligibleRematchRoster(data)
		end,
		function(active)
			local called, value = pcall(data.dependencies.createRematch, active, data.ticket)
			return if called then value else nil
		end,
		{
			clock = data.dependencies.environment.now,
			schedule = data.dependencies.environment.scheduleRematch,
		}
	)
	if created.ok and created.value:begin().ok then
		data.rematch = created.value
		bump(data)
	end
end

local function resultErrorCode(value: unknown): string?
	return if type(value) == "table"
			and type((value :: any).error) == "table"
			and type((value :: any).error.code) == "string"
		then (value :: any).error.code
		else nil
end

local function persistCachedResult(data: HostData): (boolean, string?)
	if data.resultCreated then
		return true, nil
	end
	local resultRecord = data.resultRecord
	if resultRecord == nil then
		return false, "RESULT_RECORD_MISSING"
	end
	local createdCalled, created =
		pcall(data.dependencies.resultLedger.create, data.dependencies.resultLedger, resultRecord)
	if not createdCalled or not resultOk(created) then
		return false, if createdCalled then resultErrorCode(created) else nil
	end
	data.resultCreated = true
	return true, nil
end

local function observeDurableResults(data: HostData, resultRecord: any): boolean
	local observer = data.dependencies.observeDurableResult
	if observer == nil then
		return true
	end
	local complete = true
	for _, entry in resultRecord.entries do
		if
			entry.authenticatedParticipant
			and not entry.spectator
			and not data.durableResultObservedByUserId[entry.userId]
		then
			local evidence = table.freeze({
				matchId = resultRecord.matchId,
				mapId = resultRecord.mapId,
				difficultyId = resultRecord.difficultyId,
				authenticatedParticipant = true,
				spectator = false,
				durable = true,
			})
			local called, observed = pcall(observer, entry.userId, evidence)
			if called and resultOk(observed) then
				data.durableResultObservedByUserId[entry.userId] = true
				local observation = (observed :: any).value
				if type(observation) == "table" and type(observation.tutorial) == "table" then
					local tutorial = observation.tutorial
					local ticket = data.ticket
					-- Step 8 requires a Lobby return tied to this exact Match. A fresh
					-- rematch would strand the solo journey on an unreachable match ID,
					-- so the authoritative host omits the offer entirely.
					if
						ticket ~= nil
						and #ticket.expectedUserIds == 1
						and tutorial.tutorialStep == 8
						and tutorial.trackedMatchId == resultRecord.matchId
					then
						data.rematchSuppressedForTutorial = true
					end
					local playable = data.playable
					if playable ~= nil and type(playable.refreshTutorial) == "function" then
						pcall(playable.refreshTutorial, playable, entry.userId)
					end
				end
			else
				complete = false
			end
		end
	end
	return complete
end

local function applyPipelineView(data: HostData, userId: number, status: string, reason: string): boolean
	local playable = data.playable
	local ticket = data.ticket
	local binding = data.bindingsByUserId[userId]
	if playable == nil or ticket == nil or binding == nil then
		return false
	end
	local earned, spent = 0, 0
	local snapshotCalled, snapshotResult = pcall(playable.getSnapshot, playable, binding.player)
	if snapshotCalled and resultOk(snapshotResult) then
		local snapshot = (snapshotResult :: any).value
		if type(snapshot) == "table" and type(snapshot.stats) == "table" then
			earned = if type(snapshot.stats.battleCashEarned) == "number" then snapshot.stats.battleCashEarned else 0
			spent = if type(snapshot.stats.battleCashSpent) == "number" then snapshot.stats.battleCashSpent else 0
		end
	end
	if binding.role == "Spectator" then
		earned, spent = 0, 0
	end
	local view = {
		resultId = ticket.resultId,
		status = status,
		persistentGoldAwarded = 0,
		firstClearBonus = 0,
		battleCashEarned = earned,
		battleCashSpent = spent,
		reason = reason,
	}
	local appliedCalled, applied = pcall(playable.setRewardView, playable, userId, view)
	return appliedCalled and type(applied) == "table" and applied.accepted == true
end

local function applyResultFailureViews(data: HostData)
	local reason = data.resultFailureReason or "RESULT_PIPELINE_FAILED"
	for userId in data.bindingsByUserId do
		if applyPipelineView(data, userId, "Failed", reason) then
			data.rewardTerminalByUserId[userId] = true
		end
	end
end

local function markResultFailed(data: HostData, reason: string, currentTime: number): boolean
	local ticket = data.ticket
	if ticket == nil then
		return false
	end
	data.resultFailureReason = reason
	local called, marked = pcall(
		data.dependencies.resultLedger.markFailed,
		data.dependencies.resultLedger,
		ticket.resultId,
		ticket.matchId,
		ticket.ticketId,
		reason,
		currentTime
	)
	if not called or not resultOk(marked) then
		for userId in data.bindingsByUserId do
			applyPipelineView(data, userId, "Pending", "RESULT_LEDGER_PENDING")
		end
		return false
	end
	data.resultFailed = true
	applyResultFailureViews(data)
	return true
end

local function processResults(data: HostData, currentTime: number): boolean
	local playable = data.playable
	local ticket = data.ticket
	if playable == nil or ticket == nil then
		return false
	end
	if data.resultFailureReason ~= nil and not data.resultFailed then
		markResultFailed(data, data.resultFailureReason, currentTime)
		return false
	elseif data.resultFailed then
		applyResultFailureViews(data)
		return false
	end
	local evidenceCalled, evidenceResult = pcall(playable.getResultEvidence, playable)
	if not evidenceCalled or not resultOk(evidenceResult) then
		return false
	end
	local evidence = (evidenceResult :: any).value
	local rewardingMatch =
		ContentSelection.rewardingForSelection(data.dependencies.configuration, ticket.mapId, ticket.difficultyId)
	if
		evidence.matchId ~= ticket.matchId
		or evidence.mapId ~= ticket.mapId
		or evidence.difficultyId ~= ticket.difficultyId
		or rewardingMatch == nil
		or evidence.rewardingMatch ~= rewardingMatch
	then
		markResultFailed(data, "RESULT_EVIDENCE_FAILED", currentTime)
		return false
	end
	if data.resultRecord == nil then
		local resultVersion = if evidence.modeKind == "Finite" or evidence.modeKind == "Endless"
			then MatchResultContract.CURRENT_VERSION
			else MatchResultContract.LEGACY_VERSION
		local validated = MatchResultContract.validate({
			version = resultVersion,
			resultId = ticket.resultId,
			matchId = ticket.matchId,
			ticketId = ticket.ticketId,
			mapId = ticket.mapId,
			difficultyId = ticket.difficultyId,
			outcome = evidence.outcome,
			modeKind = evidence.modeKind,
			highestCompletedWave = evidence.highestCompletedWave,
			elapsedSeconds = evidence.elapsedSeconds,
			seed = evidence.seed,
			contentVersion = evidence.contentVersion,
			terminationReason = evidence.terminationReason,
			createdAt = currentTime,
			rewardingMatch = rewardingMatch,
			entries = evidence.entries,
		})
		if not validated.ok then
			markResultFailed(data, "RESULT_VALIDATION_FAILED", currentTime)
			return false
		end
		-- Retries must reuse this exact immutable record. In particular, changing
		-- createdAt after an ambiguous durable write would turn an idempotent
		-- retry into a conflicting result.
		data.resultRecord = validated.value
	end
	local resultRecord = data.resultRecord
	if not data.resultCreated then
		local created, code = persistCachedResult(data)
		if not created then
			if code ~= nil and code ~= "STORE_UNAVAILABLE" and code ~= "BUSY" then
				markResultFailed(data, "RESULT_LEDGER_FAILED", currentTime)
			else
				for userId in data.bindingsByUserId do
					applyPipelineView(data, userId, "Pending", "RESULT_LEDGER_PENDING")
				end
			end
			return false
		end
	end
	local observationComplete = observeDurableResults(data, resultRecord)
	local newlyReady = false
	if observationComplete and not data.resultReady then
		data.resultReady = true
		newlyReady = true
	end
	if currentTime < data.lastRewardAttemptAt + REWARD_RETRY_SECONDS then
		return newlyReady
	end
	data.lastRewardAttemptAt = currentTime
	for _, entry in resultRecord.entries do
		if data.rewardTerminalByUserId[entry.userId] ~= true then
			local binding = data.bindingsByUserId[entry.userId]
			if binding ~= nil and isLive(data, binding.player) then
				local called, claimResult = pcall(
					data.dependencies.rewardClaims.claim,
					data.dependencies.rewardClaims,
					entry.userId,
					ticket.resultId
				)
				if called and resultOk(claimResult) then
					local view = (claimResult :: any).value
					local appliedCalled, applied = pcall(playable.setRewardView, playable, entry.userId, view)
					if appliedCalled and type(applied) == "table" and applied.accepted == true then
						data.rewardTerminalByUserId[entry.userId] = view.status == "Granted"
							or view.status == "Ineligible"
					end
				else
					applyPipelineView(data, entry.userId, "Pending", "REWARD_CLAIM_PENDING")
				end
			end
		end
	end
	return newlyReady
end

local function rematchView(data: HostData): MatchTravelProtocol.RematchView?
	if data.rematch == nil then
		return nil
	end
	local resolved = data.rematch:getSnapshot()
	if not resolved.ok then
		return nil
	end
	local snapshot = resolved.value
	return table.freeze({
		revision = snapshot.revision,
		state = snapshot.state,
		deadline = snapshot.deadline,
		votes = snapshot.votes,
	})
end

local function snapshotFor(data: HostData, userId: number): MatchTravelProtocol.Snapshot?
	local ticket = data.ticket
	local binding = data.bindingsByUserId[userId]
	if ticket == nil or binding == nil then
		return nil
	end
	local status = data.returnStatuses[userId] or "Idle"
	local candidate = {
		version = MatchTravelProtocol.VERSION,
		matchId = ticket.matchId,
		revision = data.revision,
		viewerRole = binding.role,
		returnStatus = status,
		publicFailure = if status == "Failed" then data.publicFailures[userId] or "RETURN_UNAVAILABLE" else nil,
		rematch = rematchView(data),
	}
	local validated = MatchTravelProtocol.validateSnapshot(candidate)
	return if validated.ok then validated.value else nil
end

local function publishSnapshots(data: HostData)
	if data.shutdownRequested then
		return
	end
	data.publicationsRunning += 1
	local called, publicationError = pcall(function()
		for userId, binding in data.bindingsByUserId do
			if isLive(data, binding.player) then
				local snapshot = snapshotFor(data, userId)
				if snapshot ~= nil then
					local rematchRevision = if snapshot.rematch == nil then 0 else snapshot.rematch.revision
					local fingerprint = `{snapshot.revision}:{rematchRevision}`
					if data.publishedFingerprintByUserId[userId] ~= fingerprint then
						local sentCalled, sent = pcall(data.dependencies.snapshotSender, binding.player, snapshot)
						if sentCalled and sent ~= false then
							data.publishedFingerprintByUserId[userId] = fingerprint
						end
					end
				end
			end
		end
	end)
	data.publicationsRunning -= 1
	if not called then
		error(publicationError, 0)
	end
end

local function runIngressOperation(data: HostData, callback: () -> unknown): unknown
	data.ingressOperationsRunning += 1
	local called, resultValue = pcall(callback)
	data.ingressOperationsRunning -= 1
	if not called then
		error(resultValue, 0)
	end
	return resultValue
end

local function rememberReceipt(data: HostData, transactionId: string, stored: StoredReceipt)
	if data.receipts[transactionId] ~= nil then
		return
	end
	if #data.receiptOrder >= MAX_RECEIPTS then
		local oldest = table.remove(data.receiptOrder, 1)
		data.receipts[oldest] = nil
	end
	data.receipts[transactionId] = stored
	table.insert(data.receiptOrder, transactionId)
end

local function receiptFor(
	data: HostData,
	userId: number,
	operation: "return" | "rematch",
	transactionId: string,
	changed: boolean
): Result.Result<MatchTravelProtocol.MutationReceipt, HostError>
	local snapshot = snapshotFor(data, userId)
	if snapshot == nil then
		return failure("UNAVAILABLE", operation)
	end
	local receipt = table.freeze({ transactionId = transactionId, changed = changed, snapshot = snapshot })
	rememberReceipt(data, transactionId, { userId = userId, operation = operation, receipt = receipt })
	return Result.ok(receipt)
end

local function existingReceipt(
	data: HostData,
	userId: number,
	operation: "return" | "rematch",
	transactionId: string
): Result.Result<MatchTravelProtocol.MutationReceipt, HostError>?
	local stored = data.receipts[transactionId]
	if stored == nil then
		return nil
	end
	return if stored.userId == userId and stored.operation == operation
		then Result.ok(stored.receipt)
		else failure("NOT_AUTHORIZED", operation)
end

local function failReturn(data: HostData, userIds: { number }, publicFailure: string)
	for _, userId in userIds do
		data.returnStatuses[userId] = "Failed"
		data.publicFailures[userId] = publicFailure
	end
	bump(data)
end

local function settleReturnSession(data: HostData, session: ReturnSession)
	if session.pendingCount > 0 then
		return
	end
	if session.departedCount == 0 then
		local currentTime = now(data)
		if currentTime ~= nil then
			pcall(
				data.dependencies.returnRecords.markTerminal,
				data.dependencies.returnRecords,
				session.returnId,
				"TELEPORT_INIT_FAILED",
				currentTime
			)
		end
	end
	data.returnSessionsById[session.returnId] = nil
end

local function failPendingReturn(data: HostData, player: unknown, publicFailure: string): boolean
	local pending = data.pendingReturnsByPlayer[player :: any]
	if pending == nil then
		return false
	end
	local called, rolledBack =
		pcall(data.dependencies.profileTransfer.rollback, data.dependencies.profileTransfer, pending.handle)
	if
		(not called or not resultOk(rolledBack))
		and pending.rollbackPending
		and called
		and resultErrorCode(rolledBack) == "INVALID_HANDLE"
	then
		local stateCalled, state = pcall(data.dependencies.profile.getState, data.dependencies.profile, pending.userId)
		if stateCalled and state == "Ready" then
			rolledBack = Result.ok(false)
		end
	end
	if not called or not resultOk(rolledBack) then
		pending.rollbackPending = true
		pending.publicFailure = publicFailure
		data.returnStatuses[pending.userId] = "Failed"
		data.publicFailures[pending.userId] = publicFailure
		bump(data)
		return true
	end
	data.pendingReturnsByPlayer[player :: any] = nil
	data.pendingReturnsByUserId[pending.userId] = nil
	pending.session.pendingCount -= 1
	pending.session.failedCount += 1
	data.returnStatuses[pending.userId] = "Failed"
	data.publicFailures[pending.userId] = publicFailure
	settleReturnSession(data, pending.session)
	bump(data)
	return true
end

local function matchesReturnInitFailure(data: HostData, pending: PendingReturn, contextValue: unknown): boolean
	if type(contextValue) ~= "table" or getmetatable(contextValue :: any) ~= nil then
		return false
	end
	local context = contextValue :: any
	local routing = TravelProtocol.validateRoutingData(context.routingData)
	return context.placeId == data.dependencies.environment.lobbyPlaceId
		and routing.ok
		and routing.value.kind == "Return"
		and routing.value.returnId == pending.session.returnId
end

local function retryPendingReturnRollbacks(data: HostData)
	local pendingPlayers: { unknown } = {}
	for player, pending in data.pendingReturnsByPlayer do
		if pending.rollbackPending then
			table.insert(pendingPlayers, player)
		end
	end
	for _, player in pendingPlayers do
		local pending = data.pendingReturnsByPlayer[player :: any]
		if pending ~= nil then
			failPendingReturn(data, player, pending.publicFailure or "PROFILE_RELEASE_FAILED")
		end
	end
end

local function completePendingReturn(data: HostData, player: unknown): boolean
	local pending = data.pendingReturnsByPlayer[player :: any]
	if pending == nil then
		return false
	end
	pcall(data.dependencies.admission.markReturned, data.dependencies.admission, player, now(data) or 0)
	local committedCalled, committed =
		pcall(data.dependencies.profileTransfer.commit, data.dependencies.profileTransfer, pending.handle)
	if not committedCalled or not resultOk(committed) then
		-- Departure is already authoritative, so rollback is no longer valid. Keep
		-- the exact handle until a later heartbeat can finish the local transfer
		-- settlement before clearing its route and return-session state.
		return false
	end
	local clearedCalled, cleared =
		pcall(data.dependencies.routes.clear, data.dependencies.routes, pending.userId, pending.session.matchId)
	if not clearedCalled or not resultOk(cleared) then
		data.departedCleanupByUserId[pending.userId] = {
			userId = pending.userId,
			matchId = pending.session.matchId,
		}
	end
	data.pendingReturnsByPlayer[player :: any] = nil
	data.pendingReturnsByUserId[pending.userId] = nil
	pending.session.pendingCount -= 1
	pending.session.departedCount += 1
	settleReturnSession(data, pending.session)
	return true
end

local function reconcilePendingReturnTimeouts(data: HostData, currentTime: number)
	local pendingPlayers: { unknown } = {}
	for player, pending in data.pendingReturnsByPlayer do
		if not pending.rollbackPending and (not isLive(data, player) or currentTime >= pending.deadline) then
			table.insert(pendingPlayers, player)
		end
	end
	for _, player in pendingPlayers do
		if isLive(data, player) then
			failPendingReturn(data, player, "TELEPORT_FAILED")
		else
			completePendingReturn(data, player)
		end
	end
end

local function retryDepartedCleanup(data: HostData)
	for userId, cleanup in data.departedCleanupByUserId do
		local called, cleared = pcall(data.dependencies.routes.clear, data.dependencies.routes, userId, cleanup.matchId)
		if called and resultOk(cleared) then
			data.departedCleanupByUserId[userId] = nil
		end
	end
end

local function rollbackWorkHandles(data: HostData, work: ReturnWork): boolean
	for index = #work.handles, 1, -1 do
		local called, rolledBack =
			pcall(data.dependencies.profileTransfer.rollback, data.dependencies.profileTransfer, work.handles[index])
		if called and (resultOk(rolledBack) or resultErrorCode(rolledBack) == "INVALID_HANDLE") then
			table.remove(work.handles, index)
		end
	end
	work.rollbackPending = #work.handles > 0
	return not work.rollbackPending
end

local function beginReturn(data: HostData, requesterUserId: number): (ReturnWork?, ErrorCode?)
	if data.shutdownRequested or data.returnBusy or data.ticket == nil then
		return nil, "RETURN_UNAVAILABLE"
	end
	if data.rematch ~= nil then
		local rematchSnapshot = data.rematch:getSnapshot()
		if
			not rematchSnapshot.ok
			or rematchSnapshot.value.state == "Starting"
			or rematchSnapshot.value.state == "Approved"
		then
			return nil, "RETURN_UNAVAILABLE"
		end
	end
	local requester = data.bindingsByUserId[requesterUserId]
	if requester == nil then
		return nil, "RETURN_UNAVAILABLE"
	end
	local ticket = data.ticket
	if requester.role == "Participant" and data.resultCreated and not data.resultReady and not data.resultFailed then
		return nil, "RETURN_UNAVAILABLE"
	end
	if requester.role == "Participant" and not data.resultCreated and not data.resultFailed then
		-- A deliberate in-match return is an Endless terminal action only for a
		-- singleton run. One squad member must never be able to terminate the
		-- authoritative match for everyone else.
		local currentTime = now(data)
		local playable = data.playable
		local terminated = false
		if currentTime ~= nil and playable ~= nil and #ticket.expectedUserIds == 1 then
			local called, outcome = pcall(playable.terminateEndless, playable, "PlayerEnded")
			terminated = called and type(outcome) == "table" and outcome.accepted == true
		end
		if terminated then
			processResults(data, currentTime :: number)
		end
		if not data.resultCreated and not data.resultFailed then
			return nil, "RETURN_UNAVAILABLE"
		end
	end
	local spectatorOnly = requester.role == "Spectator"
	local userIds: { number } = {}
	local players: { unknown } = {}
	for _, userId in ticket.expectedUserIds do
		local binding = data.bindingsByUserId[userId]
		if (not spectatorOnly or userId == requesterUserId) and binding ~= nil and isLive(data, binding.player) then
			if data.pendingReturnsByUserId[userId] ~= nil then
				return nil, "RETURN_UNAVAILABLE"
			end
			table.insert(userIds, userId)
			table.insert(players, binding.player)
		end
	end
	if #userIds < 1 then
		return nil, "RETURN_UNAVAILABLE"
	end
	data.returnBusy = true
	for _, userId in userIds do
		data.returnStatuses[userId] = "Pending"
		data.publicFailures[userId] = nil
	end
	bump(data)
	return {
		ticket = ticket,
		userIds = userIds,
		players = players,
		handles = {},
		running = false,
		rollbackPending = false,
	},
		nil
end

local function returnWorkIsCurrent(data: HostData, work: ReturnWork): boolean
	if data.cleaned or data.shutdownRequested or data.activeReturnWork ~= work or data.ticket ~= work.ticket then
		return false
	end
	for index, userId in work.userIds do
		local binding = data.bindingsByUserId[userId]
		if
			binding == nil
			or binding.player ~= work.players[index]
			or not isLive(data, binding.player)
			or data.pendingReturnsByUserId[userId] ~= nil
		then
			return false
		end
	end
	return true
end

local function performReturn(data: HostData, work: ReturnWork): (boolean, ErrorCode?)
	local ticket = work.ticket
	local userIds = work.userIds
	local players = work.players
	local handles = work.handles
	if not returnWorkIsCurrent(data, work) then
		if not data.shutdownRequested and not data.cleaned and data.activeReturnWork == work then
			failReturn(data, userIds, "RETURN_UNAVAILABLE")
		end
		return false, "RETURN_UNAVAILABLE"
	end
	for _, userId in userIds do
		local preparedCalled, prepared =
			pcall(data.dependencies.profileTransfer.prepare, data.dependencies.profileTransfer, { userId })
		if preparedCalled and resultOk(prepared) then
			table.insert(handles, (prepared :: any).value.handle)
		end
		if not returnWorkIsCurrent(data, work) then
			rollbackWorkHandles(data, work)
			if not data.shutdownRequested and not data.cleaned and data.activeReturnWork == work then
				failReturn(data, userIds, "RETURN_UNAVAILABLE")
			end
			return false, "RETURN_UNAVAILABLE"
		end
		if not preparedCalled or not resultOk(prepared) then
			rollbackWorkHandles(data, work)
			failReturn(data, userIds, "PROFILE_RELEASE_FAILED")
			return false, "PROFILE_RELEASE_FAILED"
		end
	end
	local generatedCalled, returnIdValue = pcall(data.dependencies.environment.generateReturnId)
	local returnId = if generatedCalled then TravelProtocol.validateOpaqueId(returnIdValue, "return") else nil
	local currentTime = now(data)
	if returnId == nil or not returnId.ok or currentTime == nil then
		rollbackWorkHandles(data, work)
		failReturn(data, userIds, "RETURN_UNAVAILABLE")
		return false, "RETURN_UNAVAILABLE"
	end
	local record = {
		version = 1,
		revision = 1,
		returnId = returnId.value,
		matchId = ticket.matchId,
		priorLeaderUserId = if table.find(userIds, ticket.captainUserId) then ticket.captainUserId else userIds[1],
		expectedUserIds = userIds,
		members = {},
		createdAt = currentTime,
		expiresAt = currentTime + 600,
		state = "Active",
	}
	for _, userId in userIds do
		table.insert(record.members, { userId = userId, state = "Expected" })
	end
	local recordCalled, recordResult =
		pcall(data.dependencies.returnRecords.create, data.dependencies.returnRecords, record, currentTime)
	if not returnWorkIsCurrent(data, work) then
		if recordCalled and resultOk(recordResult) then
			pcall(
				data.dependencies.returnRecords.markTerminal,
				data.dependencies.returnRecords,
				returnId.value,
				"TELEPORT_INIT_FAILED",
				currentTime
			)
		end
		rollbackWorkHandles(data, work)
		if not data.shutdownRequested and not data.cleaned and data.activeReturnWork == work then
			failReturn(data, userIds, "RETURN_UNAVAILABLE")
		end
		return false, "RETURN_UNAVAILABLE"
	end
	if not recordCalled or not resultOk(recordResult) then
		rollbackWorkHandles(data, work)
		failReturn(data, userIds, "RETURN_UNAVAILABLE")
		return false, "RETURN_UNAVAILABLE"
	end
	local session: ReturnSession = {
		returnId = returnId.value,
		matchId = ticket.matchId,
		pendingCount = #userIds,
		departedCount = 0,
		failedCount = 0,
	}
	data.returnSessionsById[session.returnId] = session
	for index, userId in userIds do
		local pending: PendingReturn = {
			userId = userId,
			player = players[index],
			handle = handles[index],
			session = session,
			deadline = currentTime + RETURN_INIT_TIMEOUT_SECONDS,
		}
		data.pendingReturnsByUserId[userId] = pending
		data.pendingReturnsByPlayer[players[index] :: any] = pending
	end
	table.clear(handles)
	work.rollbackPending = false
	local routing = TravelProtocol.returnToLobby(returnId.value)
	local teleportedCalled = false
	local teleported: unknown = nil
	if routing.ok then
		teleportedCalled, teleported = pcall(
			data.dependencies.teleport.teleportPublic,
			data.dependencies.teleport,
			data.dependencies.environment.lobbyPlaceId,
			players,
			routing.value
		)
	end
	if data.cleaned or data.shutdownRequested or data.activeReturnWork ~= work then
		return false, "RETURN_UNAVAILABLE"
	end
	if not teleportedCalled or not resultOk(teleported) then
		for _, player in players do
			failPendingReturn(data, player, "TELEPORT_FAILED")
		end
		return false, "TELEPORT_FAILED"
	end
	local initialized = false
	for _, userId in userIds do
		if data.pendingReturnsByUserId[userId] ~= nil then
			initialized = true
			data.returnStatuses[userId] = "Teleporting"
		end
	end
	bump(data)
	return initialized, if initialized then nil else "TELEPORT_FAILED"
end

local function abortReturnWork(data: HostData, work: ReturnWork, publicFailure: string)
	local pendingFound = false
	for _, player in work.players do
		if data.pendingReturnsByPlayer[player :: any] ~= nil then
			pendingFound = true
			failPendingReturn(data, player, publicFailure)
		end
	end
	if not pendingFound then
		rollbackWorkHandles(data, work)
		failReturn(data, work.userIds, publicFailure)
	end
end

local function finishReturnWork(data: HostData, work: ReturnWork)
	if data.cleaned or data.activeReturnWork ~= work then
		return
	end
	work.running = true
	local called, callbackError = pcall(function()
		local performed = pcall(performReturn, data, work)
		if not performed and not data.cleaned and data.activeReturnWork == work then
			abortReturnWork(data, work, "RETURN_UNAVAILABLE")
		end
		if data.activeReturnWork == work and not data.shutdownRequested and not data.cleaned then
			publishSnapshots(data)
		end
	end)
	work.running = false
	if data.activeReturnWork == work then
		if not work.rollbackPending then
			data.activeReturnWork = nil
			data.returnBusy = false
		end
	end
	if not called then
		error(callbackError, 0)
	end
end

local function retryReturnWorkRollback(data: HostData)
	local work = data.activeReturnWork
	if work == nil or work.running or not work.rollbackPending then
		return
	end
	if rollbackWorkHandles(data, work) and data.activeReturnWork == work then
		data.activeReturnWork = nil
		data.returnBusy = false
	end
end

local function scheduleReturn(data: HostData, requesterUserId: number): (boolean, ErrorCode?)
	local work, errorCode = beginReturn(data, requesterUserId)
	if work == nil then
		return false, errorCode
	end
	data.activeReturnWork = work
	local scheduling = true
	local ranInline = false
	local scheduledCalled, scheduled = pcall(data.dependencies.environment.scheduleReturn, function()
		if scheduling then
			ranInline = true
			return
		end
		finishReturnWork(data, work)
	end)
	scheduling = false
	if not scheduledCalled or scheduled == false or ranInline then
		if data.activeReturnWork == work then
			data.activeReturnWork = nil
			data.returnBusy = false
			failReturn(data, work.userIds, "RETURN_UNAVAILABLE")
		end
		return false, "RETURN_UNAVAILABLE"
	end
	return true, nil
end

local function disconnectPlayer(data: HostData, player: unknown)
	completePendingReturn(data, player)
	data.pendingByPlayer[player :: any] = nil
	data.claimedByPlayer[player :: any] = nil
	local userId = data.bindingsByPlayer[player :: any]
	if userId == nil then
		return
	end
	local playable = data.playable
	if playable ~= nil then
		pcall(playable.disconnectAuthorized, playable, player)
	end
	pcall(data.dependencies.admission.disconnect, data.dependencies.admission, player)
	data.bindingsByPlayer[player :: any] = nil
	data.bindingsByUserId[userId] = nil
	data.publishedFingerprintByUserId[userId] = nil
	if data.rematch ~= nil then
		data.rematch:disconnect(userId)
	end
	bump(data)
end

local function step(data: HostData): Result.Result<boolean, HostError>
	if data.cleaned or data.shutdownRequested then
		return failure("CLEANED", "step")
	end
	local currentTime = now(data)
	if currentTime == nil then
		return failure("UNAVAILABLE", "step")
	end
	-- Retained transfer recovery must progress even when no player, result, or
	-- routing event fires during this heartbeat.
	pcall(data.dependencies.stepDependencies)
	if data.shutdownRequested then
		return failure("CLEANED", "step")
	end
	retryReturnWorkRollback(data)
	local pending: { PendingArrival } = {}
	for _, value in data.pendingByPlayer do
		table.insert(pending, value)
	end
	for _, value in pending do
		processArrival(data, value, currentTime)
	end
	local claimed: { ClaimedArrival } = {}
	for _, value in data.claimedByPlayer do
		table.insert(claimed, value)
	end
	for _, value in claimed do
		processClaimed(data, value, currentTime)
	end
	pcall(data.dependencies.admission.retryReturns, data.dependencies.admission, currentTime)
	reconcilePendingReturnTimeouts(data, currentTime)
	retryPendingReturnRollbacks(data)
	retryDepartedCleanup(data)
	if
		data.ticket ~= nil
		and data.playable ~= nil
		and not data.resultCreated
		and not data.resultFailed
		and currentTime >= data.lastIntentRenewalAt + INTENT_RENEWAL_SECONDS
	then
		-- This lease is authoritative liveness evidence for long Matches. A
		-- transient persistence outage must not terminate otherwise valid play,
		-- but attempts stay throttled so the store cannot be hammered.
		data.lastIntentRenewalAt = currentTime
		pcall(
			data.dependencies.resultLedger.renewIntent,
			data.dependencies.resultLedger,
			data.ticket.resultId,
			data.ticket.matchId,
			data.ticket.ticketId,
			currentTime
		)
	end
	local newlyCreatedResult = processResults(data, currentTime)
	if data.shutdownRequested then
		return failure("CLEANED", "step")
	end
	-- Persistence can yield longer than the voting window. Begin the one-time
	-- offer only after that work, immediately before its first publication.
	local rematchTime = now(data)
	if rematchTime == nil then
		return failure("UNAVAILABLE", "step")
	end
	if newlyCreatedResult then
		createRematch(data)
	end
	if data.rematch ~= nil then
		local rematchResult = data.rematch:step(rematchTime)
		if rematchResult.ok and rematchResult.value.revision ~= data.rematchRevisionObserved then
			data.rematchRevisionObserved = rematchResult.value.revision
			bump(data)
		end
	end
	publishSnapshots(data)
	return Result.ok(true)
end

local function runSerializedStep(data: HostData): Result.Result<boolean, HostError>
	if data.stepRunning then
		return Result.ok(false)
	end
	data.stepRunning = true
	local called, stepped = pcall(step, data)
	data.stepRunning = false
	if not called then
		error(stepped, 0)
	end
	return stepped
end

local function handleReturnInitFailure(data: HostData, player: unknown, context: unknown)
	if data.cleaned or data.shutdownRequested then
		return
	end
	runIngressOperation(data, function()
		local pending = data.pendingReturnsByPlayer[player :: any]
		local changed = pending ~= nil
			and matchesReturnInitFailure(data, pending, context)
			and failPendingReturn(data, player, "TELEPORT_FAILED")
		if changed then
			publishSnapshots(data)
		end
	end)
end

local function initialize(data: HostData)
	if data.state ~= "Constructed" then
		error("[ATD_MATCH_TRAVEL_HOST][code=INVALID_INITIALIZE_STATE]", 0)
	end
	data.state = "Initialized"
end

local function start(data: HostData)
	if data.state ~= "Initialized" then
		error("[ATD_MATCH_TRAVEL_HOST][code=INVALID_START_STATE]", 0)
	end
	data.state = "Started"
	table.insert(
		data.connections,
		data.dependencies.environment.connectPlayerAdded(function(player)
			if not data.cleaned and not data.shutdownRequested then
				runIngressOperation(data, function()
					enqueue(data, player)
				end)
			end
		end)
	)
	table.insert(
		data.connections,
		data.dependencies.environment.connectPlayerRemoving(function(player)
			if not data.cleaned and not data.shutdownRequested then
				runIngressOperation(data, function()
					disconnectPlayer(data, player)
				end)
			end
		end)
	)
	table.insert(
		data.connections,
		data.dependencies.teleport:connectInitFailed(function(player, _failureClass, context)
			handleReturnInitFailure(data, player, context)
		end)
	)
	table.insert(
		data.connections,
		data.dependencies.environment.connectHeartbeat(function()
			runSerializedStep(data)
		end)
	)
	for _, player in exactPlayerList(data) do
		runIngressOperation(data, function()
			enqueue(data, player)
		end)
	end
end

function Methods.getServiceDefinition(self: Service): any
	local data = requireData(self)
	return table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({ "ProfileService", "MatchLifecycle" }),
		initialize = function()
			initialize(data)
		end,
		start = function()
			start(data)
		end,
		shutdown = function()
			local durabilityAttempts = 0
			local joinDeadline = os.clock() + SHUTDOWN_JOIN_SECONDS
			while durabilityAttempts < SHUTDOWN_DURABILITY_ATTEMPTS do
				local cleaned = self:cleanup()
				if cleaned.ok then
					return
				end
				local asyncBusy = data.stepRunning
					or data.ingressOperationsRunning > 0
					or data.publicationsRunning > 0
					or data.activeReturnWork ~= nil
					or data.dependencyCleanupJoining
					or (data.rematch ~= nil and data.rematch:isFactoryBusy())
				if asyncBusy and os.clock() < joinDeadline then
					task.wait(SHUTDOWN_POLL_SECONDS)
				else
					durabilityAttempts += 1
				end
			end
			-- ServiceLifecycle observes thrown failures. A fixed attempt count keeps
			-- this retry path bounded under the outer BindToClose shutdown budget.
			error("[ATD_MATCH_TRAVEL_HOST][code=SHUTDOWN_DURABILITY_FAILED]", 0)
		end,
	})
end

function Methods.step(self: Service): Result.Result<boolean, HostError>
	return runSerializedStep(requireData(self))
end

function Methods.getPlayable(self: Service, player: unknown): any?
	local data = requireData(self)
	if data.cleaned or data.shutdownRequested or data.bindingsByPlayer[player :: any] == nil then
		return nil
	end
	local resolvedCalled, resolved = pcall(data.dependencies.admission.resolve, data.dependencies.admission, player)
	return if resolvedCalled and resultOk(resolved) then data.playable else nil
end

function Methods.canSubmitReady(self: Service, player: unknown): boolean
	local data = requireData(self)
	local userId = readUserId(data, player)
	local binding = if userId == nil then nil else data.bindingsByUserId[userId]
	local currentTime = now(data)
	return not data.cleaned
		and not data.shutdownRequested
		and binding ~= nil
		and binding.player == player
		and binding.role == "Participant"
		and currentTime ~= nil
		and readyGateOpen(data, currentTime)
end

function Methods.getSnapshot(self: Service, player: unknown): Result.Result<MatchTravelProtocol.Snapshot, HostError>
	local data = requireData(self)
	if data.cleaned or data.shutdownRequested then
		return failure("CLEANED", "snapshot")
	end
	local userId = readUserId(data, player)
	local snapshot = if userId == nil then nil else snapshotFor(data, userId)
	return if snapshot == nil then failure("NOT_AUTHORIZED", "snapshot") else Result.ok(snapshot)
end

function Methods.requestReturn(
	self: Service,
	player: unknown,
	intentValue: unknown
): Result.Result<MatchTravelProtocol.MutationReceipt, HostError>
	local data = requireData(self)
	if data.cleaned or data.shutdownRequested then
		return failure("CLEANED", "return")
	end
	return runIngressOperation(data, function()
		local parsed = MatchTravelProtocol.ReturnIntentSchema:validate(intentValue)
		local userId = readUserId(data, player)
		if not parsed.ok or userId == nil or data.bindingsByPlayer[player :: any] ~= userId then
			return failure("INVALID_ARGUMENT", "return")
		end
		local intent = parsed.value
		local replay = existingReceipt(data, userId, "return", intent.transactionId)
		if replay ~= nil then
			return replay
		end
		if data.ticket == nil or intent.matchId ~= data.ticket.matchId then
			return failure("NOT_AUTHORIZED", "return")
		end
		if intent.observedRevision ~= data.revision then
			return failure("STALE_REVISION", "return")
		end
		local changed, errorCode = scheduleReturn(data, userId)
		local receipt = receiptFor(data, userId, "return", intent.transactionId, changed)
		publishSnapshots(data)
		return if errorCode == nil or receipt.ok then receipt else failure(errorCode, "return")
	end) :: any
end

function Methods.voteRematch(
	self: Service,
	player: unknown,
	intentValue: unknown
): Result.Result<MatchTravelProtocol.MutationReceipt, HostError>
	local data = requireData(self)
	if data.cleaned or data.shutdownRequested then
		return failure("CLEANED", "rematch")
	end
	return runIngressOperation(data, function()
		local parsed = MatchTravelProtocol.RematchVoteIntentSchema:validate(intentValue)
		local userId = readUserId(data, player)
		local binding = if userId == nil then nil else data.bindingsByUserId[userId]
		if
			not parsed.ok
			or userId == nil
			or binding == nil
			or binding.player ~= player
			or binding.role ~= "Participant"
		then
			return failure("NOT_AUTHORIZED", "rematch")
		end
		local intent = parsed.value
		local replay = existingReceipt(data, userId, "rematch", intent.transactionId)
		if replay ~= nil then
			return replay
		end
		if data.ticket == nil or intent.matchId ~= data.ticket.matchId or data.rematch == nil then
			return failure("REMATCH_UNAVAILABLE", "rematch")
		end
		if data.returnBusy or data.activeReturnWork ~= nil or next(data.pendingReturnsByUserId) ~= nil then
			return failure("REMATCH_UNAVAILABLE", "rematch")
		end
		local voteTime = now(data)
		if voteTime == nil then
			return failure("UNAVAILABLE", "rematch")
		end
		local currentRematch = data.rematch:step(voteTime)
		if not currentRematch.ok then
			return failure("REMATCH_UNAVAILABLE", "rematch")
		end
		if currentRematch.value.state ~= "Pending" then
			if currentRematch.value.revision ~= data.rematchRevisionObserved then
				data.rematchRevisionObserved = currentRematch.value.revision
				bump(data)
			end
			publishSnapshots(data)
			return failure("REMATCH_UNAVAILABLE", "rematch")
		end
		if intent.observedRevision ~= data.revision then
			return failure("STALE_REVISION", "rematch")
		end
		local voted = data.rematch:vote(userId, intent.approve, intent.observedRematchRevision)
		if not voted.ok then
			return failure(
				if voted.error.code == "STALE_REVISION" then "STALE_REVISION" else "REMATCH_UNAVAILABLE",
				"rematch"
			)
		end
		bump(data)
		local receipt = receiptFor(data, userId, "rematch", intent.transactionId, true)
		publishSnapshots(data)
		return receipt
	end) :: any
end

function Methods.getMetrics(self: Service): any
	local data = requireData(self)
	local participants, spectators, pending = 0, 0, 0
	for _, binding in data.bindingsByUserId do
		if binding.role == "Participant" then
			participants += 1
		else
			spectators += 1
		end
	end
	for _ in data.pendingByPlayer do
		pending += 1
	end
	for _ in data.claimedByPlayer do
		pending += 1
	end
	return table.freeze({
		state = data.state,
		participantCount = participants,
		spectatorCount = spectators,
		pendingArrivalCount = pending,
		resultCreated = data.resultCreated,
		resultReady = data.resultReady,
		resultFailed = data.resultFailed,
		routesBound = data.routesBound,
		cleaned = data.cleaned,
	})
end

function Methods.cleanup(self: Service): Result.Result<boolean, HostError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	data.shutdownRequested = true
	if data.stepRunning or data.ingressOperationsRunning > 0 or data.publicationsRunning > 0 then
		return failure("UNAVAILABLE", "cleanup")
	end
	local activeReturnWork = data.activeReturnWork
	if activeReturnWork ~= nil then
		if activeReturnWork.running then
			return failure("UNAVAILABLE", "cleanup")
		end
		if #activeReturnWork.handles > 0 and not rollbackWorkHandles(data, activeReturnWork) then
			return failure("UNAVAILABLE", "cleanup")
		end
		data.activeReturnWork = nil
		data.returnBusy = false
	end
	if data.rematch ~= nil and data.rematch:isFactoryBusy() then
		local cancelled = data.rematch:cancelFactory()
		if not cancelled.ok or data.rematch:isFactoryBusy() then
			return failure("UNAVAILABLE", "cleanup")
		end
	end
	local prepareCalled, cleanupPrepared = pcall(data.dependencies.prepareCleanupDependencies)
	data.dependencyCleanupJoining = not prepareCalled or cleanupPrepared ~= true
	if data.dependencyCleanupJoining then
		return failure("UNAVAILABLE", "cleanup")
	end
	local terminalTicket = data.ticket
	local terminalTime = now(data)
	if terminalTicket ~= nil and terminalTime == nil then
		return failure("UNAVAILABLE", "cleanup")
	end
	if terminalTicket ~= nil and terminalTime ~= nil and not data.resultCreated and not data.resultFailed then
		if data.resultRecord == nil and data.playable ~= nil then
			-- Consume an already-terminal runtime before asking an active Endless run
			-- to stop. Playable and host heartbeats are separate callbacks, so cleanup
			-- may observe valid Results evidence before the host's next normal step.
			processResults(data, terminalTime)
			if not data.resultCreated and not data.resultFailed and data.resultRecord == nil then
				local called, outcome = pcall(data.playable.terminateEndless, data.playable, "Shutdown")
				if called and type(outcome) == "table" and outcome.accepted == true then
					processResults(data, terminalTime)
				end
			end
		end
		if data.resultRecord ~= nil and not data.resultCreated and not data.resultFailed then
			-- A validated result record is stronger evidence than a zero-award
			-- shutdown tombstone. Preserve and retry this exact immutable value; an
			-- ambiguous prior create is idempotently resolved by ResultLedgerService.
			if not persistCachedResult(data) then
				return failure("UNAVAILABLE", "cleanup")
			end
		elseif
			not data.resultCreated
			and not data.resultFailed
			and not markResultFailed(data, "MATCH_TERMINAL_CLEANUP", terminalTime)
		then
			-- Do not erase the only active host/ticket context while its pending
			-- profile receipts still lack a durable terminal result record. The
			-- lifecycle shutdown wrapper owns a bounded set of later attempts.
			return failure("UNAVAILABLE", "cleanup")
		end
	end
	if data.resultCreated and not data.resultFailed and not data.resultReady then
		if data.resultRecord == nil or not observeDurableResults(data, data.resultRecord) then
			return failure("UNAVAILABLE", "cleanup")
		end
		data.resultReady = true
	end
	if terminalTicket ~= nil and terminalTime ~= nil then
		pcall(
			data.dependencies.ticketStore.markTerminal,
			data.dependencies.ticketStore,
			terminalTicket.ticketId,
			"MATCH_TERMINAL_CLEANUP",
			terminalTime
		)
		for _, userId in terminalTicket.expectedUserIds do
			pcall(data.dependencies.routes.clear, data.dependencies.routes, userId, terminalTicket.matchId)
		end
	end
	for index = #data.connections, 1, -1 do
		local connection = data.connections[index]
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(data.connections)
	if data.playable ~= nil then
		pcall(data.dependencies.stopPlayable, data.playable)
	end
	if data.rematch ~= nil then
		local rematchCleaned = data.rematch:cleanup()
		if not rematchCleaned.ok then
			return failure("UNAVAILABLE", "cleanup")
		end
	end
	for player, pending in data.pendingReturnsByPlayer do
		local settledCalled: boolean
		local settled: unknown
		if isLive(data, player) then
			settledCalled, settled =
				pcall(data.dependencies.profileTransfer.rollback, data.dependencies.profileTransfer, pending.handle)
		else
			settledCalled, settled =
				pcall(data.dependencies.profileTransfer.commit, data.dependencies.profileTransfer, pending.handle)
		end
		if not settledCalled or not resultOk(settled) then
			return failure("UNAVAILABLE", "cleanup")
		end
		data.pendingReturnsByPlayer[player :: any] = nil
		data.pendingReturnsByUserId[pending.userId] = nil
	end
	retryDepartedCleanup(data)
	pcall(data.dependencies.admission.cleanup, data.dependencies.admission)
	local dependenciesCalled, dependenciesCleaned = pcall(data.dependencies.cleanupDependencies)
	if not dependenciesCalled or dependenciesCleaned ~= true then
		return failure("UNAVAILABLE", "cleanup")
	end
	data.cleaned = true
	data.returnBusy = false
	data.state = "Shutdown"
	table.clear(data.pendingByPlayer)
	table.clear(data.claimedByPlayer)
	table.clear(data.bindingsByPlayer)
	table.clear(data.bindingsByUserId)
	table.clear(data.admittedParticipantsByUserId)
	table.clear(data.initialArrivalsByUserId)
	table.clear(data.returnStatuses)
	table.clear(data.publicFailures)
	table.clear(data.pendingReturnsByPlayer)
	table.clear(data.pendingReturnsByUserId)
	table.clear(data.returnSessionsById)
	table.clear(data.departedCleanupByUserId)
	table.clear(data.publishedFingerprintByUserId)
	table.clear(data.receipts)
	table.clear(data.receiptOrder)
	table.clear(data.durableResultObservedByUserId)
	data.playable = nil
	data.ticket = nil
	return Result.ok(true)
end

local function hasMethods(value: unknown, names: { string }): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, name in names do
		if type((value :: any)[name]) ~= "function" then
			return false
		end
	end
	return true
end

function MatchTravelHost.new(dependenciesValue: unknown): Result.Result<Service, HostError>
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local dependencies = dependenciesValue :: any
	local environment = dependencies.environment
	if
		not ConfigurationValidator.isValidatedConfiguration(dependencies.configuration)
		or not hasMethods(dependencies.profile, { "getState", "read", "release", "load" })
		or not hasMethods(dependencies.ticketStore, { "get", "markTerminal" })
		or not hasMethods(
			dependencies.admission,
			{ "admit", "disconnect", "markReturned", "retryReturns", "resolve", "cleanup" }
		)
		or not hasMethods(dependencies.routes, { "bindDestination", "find", "clear" })
		or not hasMethods(dependencies.returnRecords, { "create", "markTerminal" })
		or not hasMethods(dependencies.profileTransfer, { "prepare", "rollback", "commit" })
		or not hasMethods(dependencies.teleport, { "teleportPublic", "connectInitFailed" })
		or not hasMethods(dependencies.resultLedger, { "create", "markFailed", "renewIntent" })
		or not hasMethods(dependencies.rewardClaims, { "claim" })
		or (dependencies.observeDurableResult ~= nil and type(dependencies.observeDurableResult) ~= "function")
		or type(dependencies.snapshotSender) ~= "function"
		or type(dependencies.playableFactory) ~= "function"
		or type(dependencies.stopPlayable) ~= "function"
		or type(dependencies.createRematch) ~= "function"
		or type(dependencies.stepDependencies) ~= "function"
		or type(dependencies.prepareCleanupDependencies) ~= "function"
		or type(dependencies.cleanupDependencies) ~= "function"
		or type(environment) ~= "table"
		or type(environment.now) ~= "function"
		or type(environment.getUserId) ~= "function"
		or type(environment.isLive) ~= "function"
		or type(environment.getPlayers) ~= "function"
		or type(environment.getRoutingData) ~= "function"
		or type(environment.connectPlayerAdded) ~= "function"
		or type(environment.connectPlayerRemoving) ~= "function"
		or type(environment.connectHeartbeat) ~= "function"
		or type(environment.scheduleReturn) ~= "function"
		or type(environment.scheduleRematch) ~= "function"
		or type(environment.destinationJobId) ~= "string"
		or #environment.destinationJobId < 1
		or type(environment.lobbyPlaceId) ~= "number"
		or not Validation.isSafeInteger(environment.lobbyPlaceId)
		or environment.lobbyPlaceId <= 0
		or type(environment.generateReturnId) ~= "function"
		or type(environment.safeReturnUnexpected) ~= "function"
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		dependencies = dependenciesValue :: Dependencies,
		state = "Constructed",
		ticket = nil,
		playable = nil,
		pendingByPlayer = setmetatable({}, { __mode = "k" }),
		claimedByPlayer = setmetatable({}, { __mode = "k" }),
		bindingsByUserId = {},
		bindingsByPlayer = setmetatable({}, { __mode = "k" }),
		admittedParticipantsByUserId = {},
		initialArrivalsByUserId = {},
		returnStatuses = {},
		publicFailures = {},
		pendingReturnsByUserId = {},
		pendingReturnsByPlayer = setmetatable({}, { __mode = "k" }),
		returnSessionsById = {},
		departedCleanupByUserId = {},
		connections = {},
		revision = 1,
		routesBound = false,
		stepRunning = false,
		ingressOperationsRunning = 0,
		publicationsRunning = 0,
		returnBusy = false,
		activeReturnWork = nil,
		shutdownRequested = false,
		dependencyCleanupJoining = false,
		resultCreated = false,
		resultFailed = false,
		resultFailureReason = nil,
		resultRecord = nil,
		resultReady = false,
		durableResultObservedByUserId = {},
		rematchSuppressedForTutorial = false,
		lastIntentRenewalAt = 0,
		lastRewardAttemptAt = 0,
		rewardTerminalByUserId = {},
		rematch = nil,
		rematchRevisionObserved = 0,
		publishedFingerprintByUserId = {},
		receipts = {},
		receiptOrder = {},
		cleaned = false,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(MatchTravelHost)
