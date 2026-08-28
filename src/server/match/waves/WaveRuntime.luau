--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local MatchProtocol = require(ReplicatedStorage.Shared.match.MatchProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type RuntimeState =
	"Uninitialized"
	| "Running"
	| "Intermission"
	| "FiniteComplete"
	| "DefeatClosed"
	| "Faulted"
	| "Cleaned"
export type TimerPhase = "WaveDeadline" | "EarlyClearIntermission" | "PostDeadline" | "None"

export type WaveCounts = {
	totalScheduled: number,
	pending: number,
	spawned: number,
	alive: number,
	leaked: number,
	otherwiseResolved: number,
}

export type SkipState = {
	available: boolean,
	activeParticipantCount: number,
	yesVoteCount: number,
	requiredVoteCount: number,
	quorumPending: boolean,
}

export type WaveSnapshot = {
	matchId: Ids.MatchId,
	enemyEpoch: number,
	mapId: Ids.MapId,
	difficultyId: Ids.DifficultyId,
	state: Exclude<RuntimeState, "Uninitialized" | "Cleaned">,
	waveRevision: number,
	currentWaveNumber: number,
	totalWaves: number,
	currentWaveId: Ids.WaveId,
	bossKind: ConfigTypes.BossKind,
	timerPhase: TimerPhase,
	waveStartedServerTime: number,
	deadlineServerTime: number,
	intermissionEndsServerTime: number,
	skipAvailableServerTime: number,
	finiteCompleteServerTime: number,
	currentCounts: WaveCounts,
	aggregateCounts: WaveCounts,
	skipState: SkipState,
}

export type StartingCashPlaceholder = {
	configurationVersion: number,
	difficultyId: Ids.DifficultyId,
	startingBattleCash: number,
}

export type TerminalOutcome = {
	matchId: Ids.MatchId,
	enemyEpoch: number,
	runtimeEnemyId: number,
	enemyId: Ids.EnemyId,
	reason: "Endpoint" | "Manual" | "Defeat",
	serverTime: number,
}

export type SpawnEvent = {
	originatingWaveIndex: number,
	waveId: Ids.WaveId,
	groupIndex: number,
	spawnOrdinal: number,
	scheduledServerTime: number,
	enemyId: Ids.EnemyId,
	laneId: string,
}

export type SpawnCommitOutcome =
	{
		committed: false,
	}
	| {
		committed: true,
		replicationCommitted: boolean,
		snapshot: {
			runtimeEnemyId: number,
			enemyId: Ids.EnemyId,
			laneId: string,
			currentHealth: number,
			maximumHealth: number,
			effectiveSpeed: number,
			spawnServerTime: number,
		},
	}

export type PassDisposition = "Healthy" | "DefeatCommitted" | "DependencyFault" | "Shutdown"

export type PassFrame = {
	disposition: PassDisposition,
	matchId: Ids.MatchId,
	enemyEpoch: number,
	passOrdinal: number,
	sampleServerTime: number,
	terminalOutcomes: { unknown },
	spawn: ((event: SpawnEvent) -> unknown)?,
}

export type CommittedSpawnReconciliation = {
	event: SpawnEvent,
	outcome: SpawnCommitOutcome,
}

export type DependencyFaultContext = {
	disposition: "DependencyFault",
	matchId: Ids.MatchId,
	enemyEpoch: number,
	passOrdinal: number,
	sampleServerTime: number,
	committedSpawn: CommittedSpawnReconciliation?,
	terminalOutcome: TerminalOutcome?,
}

export type Dependencies = {
	clock: () -> unknown,
	isRuntimeMapSnapshot: (value: unknown) -> unknown,
	initializeBase: (difficulty: ConfigTypes.FiniteDifficultyDefinition) -> unknown,
	bindDifficulty: (
		configuration: ConfigTypes.CoreConfiguration,
		difficulty: ConfigTypes.FiniteDifficultyDefinition
	) -> unknown,
	beginWaveActivation: (matchId: Ids.MatchId) -> unknown,
	commitWaveActivation: (token: unknown) -> unknown,
	rollbackWaveActivation: (token: unknown) -> unknown,
	getLifecycleSnapshot: () -> unknown,
	getBaseDefeatState: () -> unknown,
	isAuthenticatedTerminalOutcome: (outcome: unknown) -> unknown,
}

export type ErrorCode =
	"INVALID_CONFIGURATION"
	| "INVALID_RUNTIME_MAP"
	| "INVALID_MATCH_ID"
	| "INVALID_EPOCH"
	| "INVALID_DIFFICULTY"
	| "UNSUPPORTED_SCHEDULE"
	| "CAPACITY_EXCEEDED"
	| "INVALID_DEPENDENCIES"
	| "WRONG_STATE"
	| "INVALID_PASS"
	| "UNAUTHENTICATED_OUTCOME"
	| "INVALID_OUTCOME"
	| "CLOCK_FAILED"
	| "CALLBACK_FAILED"
	| "LIFECYCLE_FAILED"
	| "BASE_FAILED"
	| "ENEMY_FAILED"
	| "REVISION_EXHAUSTED"
	| "REENTRANT"
	| "FAULTED"
	| "CLEANED"
	| "STALE_REQUEST"
	| "DUPLICATE_REQUEST"
	| "NOT_AUTHORIZED"
	| "UNAVAILABLE"

export type Operation =
	"new"
	| "initialize"
	| "step"
	| "closeDependencyFault"
	| "submitSkipVote"
	| "getSnapshot"
	| "query"
	| "cleanup"

export type RuntimeError = {
	code: ErrorCode,
	operation: Operation,
}

type RelativeEvent = {
	relativeScheduledTime: number,
	waveIndex: number,
	groupIndex: number,
	spawnOrdinal: number,
	enemyId: Ids.EnemyId,
	laneId: string,
}

type HeapEntry = {
	scheduledServerTime: number,
	waveIndex: number,
	eventIndex: number,
	event: RelativeEvent,
}

type OriginRecord = {
	waveIndex: number,
	waveId: Ids.WaveId,
	waveStartedServerTime: number,
	deadlineServerTime: number,
	nextEventIndex: number,
	counts: WaveCounts,
}

type OwnershipRecord = {
	waveIndex: number,
	enemyId: Ids.EnemyId,
	spawnServerTime: number,
	resolved: boolean,
	terminalReason: ("Endpoint" | "Manual" | "Defeat")?,
	terminalServerTime: number?,
}

type RuntimeData = {
	state: RuntimeState,
	timerPhase: TimerPhase,
	matchId: Ids.MatchId,
	enemyEpoch: number,
	mapId: Ids.MapId,
	difficultyId: Ids.DifficultyId,
	configuration: ConfigTypes.CoreConfiguration?,
	runtimeMap: unknown,
	difficulty: ConfigTypes.FiniteDifficultyDefinition?,
	schedule: ConfigTypes.FiniteWaveScheduleDefinition?,
	economyRule: ConfigTypes.DifficultyEconomyDefinition?,
	startingCash: StartingCashPlaceholder?,
	dependencies: Dependencies?,
	relativeEventsByWave: { { RelativeEvent } },
	origins: { [number]: OriginRecord },
	heap: { HeapEntry },
	pendingSpawnEntry: HeapEntry?,
	ownership: { [number]: OwnershipRecord },
	processedTerminalCount: number,
	currentWaveNumber: number,
	totalWaves: number,
	waveRevision: number,
	lastPassOrdinal: number,
	lastServerTime: number,
	intermissionEndsServerTime: number,
	skipAvailableServerTime: number,
	finiteCompleteServerTime: number,
	skipAvailable: boolean,
	activeUserIds: { [number]: boolean },
	voterUserIds: { [number]: boolean },
	castUserIds: { [number]: boolean },
	lastLifecycleRevision: number,
	lastLifecycleState: MatchProtocol.MatchState?,
	lastLifecycleParticipantStates: { [number]: MatchProtocol.ParticipantState },
	lastLifecycleParticipantReady: { [number]: boolean },
	activeParticipantCount: number,
	yesVoteCount: number,
	requiredVoteCount: number,
	quorumPending: boolean,
	deadlineConsumed: boolean,
	aggregateCounts: WaveCounts,
	busy: boolean,
	reentryViolation: boolean,
	cleanupRequested: boolean,
	faultCode: ErrorCode?,
	faultCloseCount: number,
	faultCloseCommittedSpawn: CommittedSpawnReconciliation?,
	faultCloseTerminalOutcome: TerminalOutcome?,
	completionCount: number,
}

type RosterProjection = {
	activeUserIds: { [number]: boolean },
	voterUserIds: { [number]: boolean },
	activeParticipantCount: number,
	yesVoteCount: number,
	requiredVoteCount: number,
}

local MAX_TOTAL_EVENTS = 4_096
local MAX_ACTIVE = 128
local MAX_WAVES = 1_000
local MAX_WORK_PER_PASS = 256
local MAX_SPAWNS_PER_PASS = 128
local MAX_TERMINALS_PER_PASS = 128

local DEPENDENCY_FIELDS = table.freeze({
	clock = true,
	isRuntimeMapSnapshot = true,
	initializeBase = true,
	bindDifficulty = true,
	beginWaveActivation = true,
	commitWaveActivation = true,
	rollbackWaveActivation = true,
	getLifecycleSnapshot = true,
	getBaseDefeatState = true,
	isAuthenticatedTerminalOutcome = true,
})

local CLOSED_PASS_FRAME_FIELDS = table.freeze({
	disposition = true,
	matchId = true,
	enemyEpoch = true,
	passOrdinal = true,
	sampleServerTime = true,
	terminalOutcomes = true,
})

local HEALTHY_PASS_FRAME_FIELDS = table.freeze({
	disposition = true,
	matchId = true,
	enemyEpoch = true,
	passOrdinal = true,
	sampleServerTime = true,
	terminalOutcomes = true,
	spawn = true,
})

local DEPENDENCY_FAULT_CONTEXT_FIELDS = table.freeze({
	disposition = true,
	matchId = true,
	enemyEpoch = true,
	passOrdinal = true,
	sampleServerTime = true,
})

local DEPENDENCY_FAULT_CONTEXT_WITH_SPAWN_FIELDS = table.freeze({
	disposition = true,
	matchId = true,
	enemyEpoch = true,
	passOrdinal = true,
	sampleServerTime = true,
	committedSpawn = true,
	terminalOutcome = true,
})

local COMMITTED_SPAWN_RECONCILIATION_FIELDS = table.freeze({
	event = true,
	outcome = true,
})

local SPAWN_EVENT_FIELDS = table.freeze({
	originatingWaveIndex = true,
	waveId = true,
	groupIndex = true,
	spawnOrdinal = true,
	scheduledServerTime = true,
	enemyId = true,
	laneId = true,
})

local RuntimeMethods = {}
RuntimeMethods.__index = RuntimeMethods

export type Runtime = typeof(setmetatable({} :: {}, RuntimeMethods))

local RUNTIME_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: RuntimeData }

local WaveRuntime = {
	MAX_TOTAL_EVENTS = MAX_TOTAL_EVENTS,
	MAX_ACTIVE = MAX_ACTIVE,
	MAX_WORK_PER_PASS = MAX_WORK_PER_PASS,
	MAX_SPAWNS_PER_PASS = MAX_SPAWNS_PER_PASS,
	MAX_TERMINALS_PER_PASS = MAX_TERMINALS_PER_PASS,
}

local function makeError(code: ErrorCode, operation: Operation): RuntimeError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<RuntimeError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): RuntimeData
	if type(value) ~= "table" then
		error("[ATD_WAVE_RUNTIME][code=INVALID_CONTEXT]", 0)
	end
	local data = RUNTIME_DATA[value :: any]
	if data == nil then
		error("[ATD_WAVE_RUNTIME][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and Validation.isFiniteNumber(value :: number)
end

local function isSuccess(value: unknown): boolean
	return type(value) == "table" and table.isfrozen(value :: any) and (value :: any).ok == true
end

local function hasExactFields(value: { [any]: unknown }, fields: { [string]: boolean }): boolean
	local count = 0
	for key in next, value do
		if type(key) ~= "string" or fields[key] ~= true then
			return false
		end
		count += 1
	end
	local expected = 0
	for _ in fields do
		expected += 1
	end
	return count == expected
end

local function callNonYielding(callback: (...any) -> ...any, ...: any): (boolean, any)
	local arguments = table.pack(...)
	local thread = coroutine.create(function()
		return callback(table.unpack(arguments, 1, arguments.n))
	end)
	local resumed, value = coroutine.resume(thread)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function callResult(callback: (...any) -> ...any, ...: any): (boolean, any)
	local called, value = callNonYielding(callback, ...)
	return called and type(value) == "table" and table.isfrozen(value :: any), value
end

local function zeroCounts(): WaveCounts
	return {
		totalScheduled = 0,
		pending = 0,
		spawned = 0,
		alive = 0,
		leaked = 0,
		otherwiseResolved = 0,
	}
end

local function snapshotCounts(counts: WaveCounts): WaveCounts
	return table.freeze({
		totalScheduled = counts.totalScheduled,
		pending = counts.pending,
		spawned = counts.spawned,
		alive = counts.alive,
		leaked = counts.leaked,
		otherwiseResolved = counts.otherwiseResolved,
	})
end

local function compareEntries(left: HeapEntry, right: HeapEntry): boolean
	if left.scheduledServerTime ~= right.scheduledServerTime then
		return left.scheduledServerTime < right.scheduledServerTime
	elseif left.waveIndex ~= right.waveIndex then
		return left.waveIndex < right.waveIndex
	elseif left.event.groupIndex ~= right.event.groupIndex then
		return left.event.groupIndex < right.event.groupIndex
	end
	return left.event.spawnOrdinal < right.event.spawnOrdinal
end

local function heapPush(heap: { HeapEntry }, entry: HeapEntry)
	table.insert(heap, entry)
	local index = #heap
	while index > 1 do
		local parent = math.floor(index / 2)
		if compareEntries(heap[parent], entry) then
			break
		end
		heap[index] = heap[parent]
		index = parent
	end
	heap[index] = entry
end

local function heapPop(heap: { HeapEntry }): HeapEntry?
	local first = heap[1]
	if first == nil then
		return nil
	end
	local last = table.remove(heap)
	if #heap == 0 then
		return first
	end
	local replacement = last :: HeapEntry
	local index = 1
	while true do
		local leftIndex = index * 2
		if leftIndex > #heap then
			break
		end
		local rightIndex = leftIndex + 1
		local childIndex = leftIndex
		if rightIndex <= #heap and compareEntries(heap[rightIndex], heap[leftIndex]) then
			childIndex = rightIndex
		end
		if compareEntries(replacement, heap[childIndex]) then
			break
		end
		heap[index] = heap[childIndex]
		index = childIndex
	end
	heap[index] = replacement
	return first
end

local function validateDependencies(value: unknown): Dependencies?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local record = value :: { [any]: unknown }
	if not hasExactFields(record, DEPENDENCY_FIELDS) then
		return nil
	end
	for fieldName in DEPENDENCY_FIELDS do
		if type(record[fieldName]) ~= "function" then
			return nil
		end
	end
	return value :: Dependencies
end

local function validateRuntimeMap(
	runtimeMap: unknown,
	mapDefinition: ConfigTypes.MapDefinition,
	predicate: (unknown) -> unknown
): boolean
	local called, authentic = callNonYielding(predicate, runtimeMap)
	if not called or authentic ~= true or type(runtimeMap) ~= "table" or not table.isfrozen(runtimeMap :: any) then
		return false
	end
	local map = runtimeMap :: any
	if map.mapId ~= mapDefinition.id or type(map.lanes) ~= "table" or #map.lanes ~= #mapDefinition.lanes then
		return false
	end
	for index, laneDefinition in mapDefinition.lanes do
		local lane = map.lanes[index]
		if type(lane) ~= "table" or not table.isfrozen(lane) or lane.id ~= laneDefinition.id then
			return false
		end
	end
	return true
end

local function preflatten(schedule: ConfigTypes.FiniteWaveScheduleDefinition): ({ { RelativeEvent } }?, number?)
	local byWave: { { RelativeEvent } } = table.create(#schedule.waves)
	local total = 0
	for waveIndex, wave in schedule.waves do
		local events: { RelativeEvent } = {}
		local simultaneous: { [number]: number } = {}
		for groupIndex, group in wave.groups do
			for authoredOrdinal = 0, group.count - 1 do
				local relativeTime = group.startDelaySeconds + authoredOrdinal * group.spawnIntervalSeconds
				if not Validation.isFiniteNumber(relativeTime) or relativeTime < 0 then
					return nil, nil
				end
				if wave.deadlinePolicy == "AllSpawnsByDeadline" and relativeTime > wave.deadlineSeconds then
					return nil, nil
				end
				total += 1
				if total > MAX_TOTAL_EVENTS then
					return nil, total
				end
				local burst = (simultaneous[relativeTime] or 0) + 1
				simultaneous[relativeTime] = burst
				if burst > MAX_ACTIVE then
					return nil, total
				end
				table.insert(
					events,
					table.freeze({
						relativeScheduledTime = relativeTime,
						waveIndex = waveIndex,
						groupIndex = groupIndex,
						spawnOrdinal = authoredOrdinal,
						enemyId = group.enemyId,
						laneId = group.laneId,
					})
				)
			end
		end
		table.sort(events, function(left, right)
			if left.relativeScheduledTime ~= right.relativeScheduledTime then
				return left.relativeScheduledTime < right.relativeScheduledTime
			elseif left.groupIndex ~= right.groupIndex then
				return left.groupIndex < right.groupIndex
			end
			return left.spawnOrdinal < right.spawnOrdinal
		end)
		byWave[waveIndex] = table.freeze(events)
	end
	return table.freeze(byWave), total
end

local function lifecycleParticipantsMatch(data: RuntimeData, snapshotValue: MatchProtocol.MatchSnapshot): boolean
	local participantCount = 0
	for _ in data.lastLifecycleParticipantStates do
		participantCount += 1
	end
	if participantCount ~= #snapshotValue.participants then
		return false
	end
	for _, participant in snapshotValue.participants do
		if
			data.lastLifecycleParticipantStates[participant.userId] ~= participant.state
			or data.lastLifecycleParticipantReady[participant.userId] ~= participant.ready
		then
			return false
		end
	end
	return true
end

local function commitLifecyclePin(data: RuntimeData, snapshotValue: MatchProtocol.MatchSnapshot)
	local states: { [number]: MatchProtocol.ParticipantState } = {}
	local readiness: { [number]: boolean } = {}
	for _, participant in snapshotValue.participants do
		states[participant.userId] = participant.state
		readiness[participant.userId] = participant.ready
	end
	data.lastLifecycleRevision = snapshotValue.revision
	data.lastLifecycleState = snapshotValue.state
	data.lastLifecycleParticipantStates = states
	data.lastLifecycleParticipantReady = readiness
end

local function lifecycleParticipantTransitionFollowsPin(
	data: RuntimeData,
	participant: MatchProtocol.ParticipantSnapshot
): boolean
	local previousState = data.lastLifecycleParticipantStates[participant.userId]
	local previousReady = data.lastLifecycleParticipantReady[participant.userId]
	if previousState == nil or previousReady == nil then
		return false
	elseif participant.state == previousState then
		return participant.ready == previousReady
	elseif previousState == "Active" then
		return (participant.state == "Disconnected" or participant.state == "Spectator") and participant.ready == false
	elseif previousState == "Disconnected" then
		return participant.state == "Spectator" and participant.ready == false
	end
	return false
end

local function lifecycleSnapshotFollowsPin(data: RuntimeData, snapshotValue: MatchProtocol.MatchSnapshot): boolean
	if data.lastLifecycleRevision == 0 then
		return true
	end
	if snapshotValue.revision < data.lastLifecycleRevision then
		return false
	elseif snapshotValue.revision == data.lastLifecycleRevision then
		return snapshotValue.state == data.lastLifecycleState and lifecycleParticipantsMatch(data, snapshotValue)
	elseif
		data.lastLifecycleState ~= "WaveActive"
		or (snapshotValue.state ~= "WaveActive" and snapshotValue.state ~= "Results")
	then
		return false
	end

	local previousParticipantCount = 0
	for _ in data.lastLifecycleParticipantStates do
		previousParticipantCount += 1
	end
	if #snapshotValue.participants ~= previousParticipantCount then
		return false
	end
	for _, participant in snapshotValue.participants do
		if not lifecycleParticipantTransitionFollowsPin(data, participant) then
			return false
		end
	end
	return true
end

local function readLifecycleSnapshot(data: RuntimeData): MatchProtocol.MatchSnapshot?
	local dependencies = data.dependencies
	if dependencies == nil then
		return nil
	end
	local called, resultValue = callResult(dependencies.getLifecycleSnapshot)
	if not called or not isSuccess(resultValue) then
		return nil
	end
	local validated = MatchProtocol.validateMatchSnapshot((resultValue :: any).value)
	if not validated.ok or validated.value.matchId ~= data.matchId then
		return nil
	end
	local snapshotValue = validated.value
	if not lifecycleSnapshotFollowsPin(data, snapshotValue) then
		return nil
	end
	return snapshotValue
end

local function baseIsDefeated(data: RuntimeData): boolean?
	local dependencies = data.dependencies
	if dependencies == nil then
		return nil
	end
	local called, value = callNonYielding(dependencies.getBaseDefeatState)
	if not called or type(value) ~= "table" or not table.isfrozen(value :: any) then
		return nil
	end
	local record = value :: any
	if type(record.defeatPending) ~= "boolean" or type(record.defeated) ~= "boolean" then
		return nil
	end
	return record.defeatPending or record.defeated
end

local function clearHeap(data: RuntimeData)
	table.clear(data.heap)
end

local function setFault(data: RuntimeData, code: ErrorCode)
	if data.state == "FiniteComplete" or data.state == "DefeatClosed" or data.state == "Cleaned" then
		return
	end
	data.state = "Faulted"
	data.timerPhase = "None"
	data.faultCode = code
	data.intermissionEndsServerTime = 0
	data.skipAvailableServerTime = 0
	data.skipAvailable = false
	data.quorumPending = false
	clearHeap(data)
end

local function enforceBaseAuthority(data: RuntimeData): boolean
	local defeated = baseIsDefeated(data)
	if defeated == nil then
		setFault(data, "BASE_FAILED")
		return false
	elseif defeated then
		data.state = "DefeatClosed"
		data.timerPhase = "None"
		data.skipAvailableServerTime = 0
		data.skipAvailable = false
		data.quorumPending = false
		clearHeap(data)
		return false
	end
	return true
end

local function enforceAuthority(data: RuntimeData): (boolean, MatchProtocol.MatchSnapshot?)
	if not enforceBaseAuthority(data) then
		return false, nil
	end

	local lifecycle = readLifecycleSnapshot(data)
	if lifecycle ~= nil then
		commitLifecyclePin(data, lifecycle)
	end
	if lifecycle ~= nil and lifecycle.state == "Results" then
		data.state = "DefeatClosed"
		data.timerPhase = "None"
		data.skipAvailableServerTime = 0
		data.skipAvailable = false
		data.quorumPending = false
		clearHeap(data)
		return false, nil
	elseif lifecycle == nil or lifecycle.state ~= "WaveActive" then
		setFault(data, "LIFECYCLE_FAILED")
		return false, nil
	end
	return true, lifecycle
end

local function userIdSetEquals(left: { [number]: boolean }, right: { [number]: boolean }): boolean
	for userId in left do
		if right[userId] ~= true then
			return false
		end
	end
	for userId in right do
		if left[userId] ~= true then
			return false
		end
	end
	return true
end

local function projectRoster(data: RuntimeData, lifecycle: MatchProtocol.MatchSnapshot): RosterProjection
	local activeUserIds: { [number]: boolean } = {}
	local activeParticipantCount = 0
	for _, participant in lifecycle.participants do
		if participant.state == "Active" then
			activeUserIds[participant.userId] = true
			activeParticipantCount += 1
		end
	end

	local voterUserIds: { [number]: boolean } = {}
	local yesVoteCount = 0
	for userId in data.voterUserIds do
		if activeUserIds[userId] == true then
			voterUserIds[userId] = true
			yesVoteCount += 1
		end
	end

	return {
		activeUserIds = activeUserIds,
		voterUserIds = voterUserIds,
		activeParticipantCount = activeParticipantCount,
		yesVoteCount = yesVoteCount,
		requiredVoteCount = if activeParticipantCount == 0 then 0 else math.floor(activeParticipantCount / 2) + 1,
	}
end

local function applyRosterProjection(data: RuntimeData, projection: RosterProjection): boolean
	local changed = data.activeParticipantCount ~= projection.activeParticipantCount
		or data.yesVoteCount ~= projection.yesVoteCount
		or data.requiredVoteCount ~= projection.requiredVoteCount
		or not userIdSetEquals(data.activeUserIds, projection.activeUserIds)
		or not userIdSetEquals(data.voterUserIds, projection.voterUserIds)
	data.activeUserIds = projection.activeUserIds
	data.voterUserIds = projection.voterUserIds
	data.activeParticipantCount = projection.activeParticipantCount
	data.yesVoteCount = projection.yesVoteCount
	data.requiredVoteCount = projection.requiredVoteCount
	return changed
end

local function updateSkipWindow(data: RuntimeData, serverTime: number): boolean
	local origin = data.origins[data.currentWaveNumber]
	local available = origin ~= nil
		and data.state == "Running"
		and data.timerPhase == "WaveDeadline"
		and data.currentWaveNumber < data.totalWaves
		and serverTime >= data.skipAvailableServerTime
		and serverTime < origin.deadlineServerTime
	local changed = data.skipAvailable ~= available
	data.skipAvailable = available
	local quorumPending = available and data.requiredVoteCount > 0 and data.yesVoteCount >= data.requiredVoteCount
	changed = changed or data.quorumPending ~= quorumPending
	data.quorumPending = quorumPending
	return changed
end

local function cleanupData(data: RuntimeData)
	data.state = "Cleaned"
	data.timerPhase = "None"
	data.configuration = nil
	data.runtimeMap = nil
	data.difficulty = nil
	data.schedule = nil
	data.economyRule = nil
	data.startingCash = nil
	data.dependencies = nil
	-- Preflattened authored event arrays are intentionally frozen. Drop the
	-- private root reference instead of attempting to mutate canonical runtime
	-- preparation data during teardown.
	data.relativeEventsByWave = {}
	table.clear(data.origins)
	table.clear(data.heap)
	data.pendingSpawnEntry = nil
	table.clear(data.ownership)
	data.processedTerminalCount = 0
	data.currentWaveNumber = 0
	data.totalWaves = 0
	data.waveRevision = 0
	data.lastPassOrdinal = 0
	data.lastServerTime = 0
	data.intermissionEndsServerTime = 0
	data.skipAvailableServerTime = 0
	data.finiteCompleteServerTime = 0
	data.skipAvailable = false
	table.clear(data.activeUserIds)
	table.clear(data.voterUserIds)
	table.clear(data.castUserIds)
	data.lastLifecycleRevision = 0
	data.lastLifecycleState = nil
	table.clear(data.lastLifecycleParticipantStates)
	table.clear(data.lastLifecycleParticipantReady)
	data.activeParticipantCount = 0
	data.yesVoteCount = 0
	data.requiredVoteCount = 0
	data.quorumPending = false
	data.deadlineConsumed = false
	data.aggregateCounts = zeroCounts()
	data.busy = false
	data.reentryViolation = false
	data.cleanupRequested = false
	data.faultCode = nil
	data.faultCloseCount = 0
	data.faultCloseCommittedSpawn = nil
	data.faultCloseTerminalOutcome = nil
	data.completionCount = 0
end

local function beginOperation(data: RuntimeData, operation: Operation, mutation: boolean): RuntimeError?
	if data.state == "Cleaned" then
		return makeError("CLEANED", operation)
	end
	if mutation and data.busy then
		data.reentryViolation = true
		return makeError("REENTRANT", operation)
	end
	if mutation and data.state == "Faulted" then
		return makeError("FAULTED", operation)
	end
	if mutation then
		data.busy = true
		data.reentryViolation = false
	end
	return nil
end

local function finishOperation(data: RuntimeData)
	data.busy = false
	if data.reentryViolation and data.state ~= "Cleaned" then
		setFault(data, "REENTRANT")
	end
	if data.cleanupRequested and data.state ~= "Cleaned" then
		cleanupData(data)
	end
end

local function currentOrigin(data: RuntimeData): OriginRecord?
	return data.origins[data.currentWaveNumber]
end

local function insertOriginHead(data: RuntimeData, origin: OriginRecord): boolean
	local events = data.relativeEventsByWave[origin.waveIndex]
	local event = events and events[origin.nextEventIndex]
	if event == nil then
		return true
	end
	local scheduledTime = origin.waveStartedServerTime + event.relativeScheduledTime
	if not Validation.isFiniteNumber(scheduledTime) or scheduledTime < origin.waveStartedServerTime then
		return false
	end
	heapPush(data.heap, {
		scheduledServerTime = scheduledTime,
		waveIndex = origin.waveIndex,
		eventIndex = origin.nextEventIndex,
		event = event,
	})
	return true
end

local function startWave(data: RuntimeData, waveIndex: number, startedAt: number): boolean
	local schedule = data.schedule
	if
		schedule == nil
		or waveIndex ~= data.currentWaveNumber + 1
		or waveIndex < 1
		or waveIndex > data.totalWaves
		or data.origins[waveIndex] ~= nil
		or not Validation.isFiniteNumber(startedAt)
		or startedAt < 0
	then
		return false
	end
	local wave = schedule.waves[waveIndex]
	local deadline = startedAt + wave.deadlineSeconds
	local difficulty = data.difficulty
	local skipAvailable = if difficulty == nil or waveIndex == data.totalWaves
		then nil
		else startedAt + difficulty.timing.skipVoteMinimumDelaySeconds
	if
		not Validation.isFiniteNumber(deadline)
		or deadline < startedAt
		or (
			waveIndex < data.totalWaves
			and (not Validation.isFiniteNumber(skipAvailable) or (skipAvailable :: number) < startedAt)
		)
	then
		return false
	end
	local totalScheduled = #data.relativeEventsByWave[waveIndex]
	local counts = zeroCounts()
	counts.totalScheduled = totalScheduled
	counts.pending = totalScheduled
	local origin: OriginRecord = {
		waveIndex = waveIndex,
		waveId = wave.id,
		waveStartedServerTime = startedAt,
		deadlineServerTime = deadline,
		nextEventIndex = 1,
		counts = counts,
	}
	data.origins[waveIndex] = origin
	data.currentWaveNumber = waveIndex
	data.timerPhase = "WaveDeadline"
	data.deadlineConsumed = false
	data.intermissionEndsServerTime = 0
	data.skipAvailableServerTime = if skipAvailable == nil then 0 else skipAvailable :: number
	data.skipAvailable = false
	table.clear(data.voterUserIds)
	table.clear(data.castUserIds)
	data.yesVoteCount = 0
	data.requiredVoteCount = if data.activeParticipantCount == 0
		then 0
		else math.floor(data.activeParticipantCount / 2) + 1
	data.quorumPending = false
	data.aggregateCounts.totalScheduled += totalScheduled
	data.aggregateCounts.pending += totalScheduled
	return insertOriginHead(data, origin)
end

local function advanceRevision(data: RuntimeData): boolean
	if data.waveRevision >= Validation.MAX_SAFE_INTEGER then
		return false
	end
	if
		data.waveRevision == Validation.MAX_SAFE_INTEGER - 1
		and data.state ~= "FiniteComplete"
		and data.state ~= "DefeatClosed"
		and data.state ~= "Faulted"
		and data.state ~= "Cleaned"
	then
		setFault(data, "REVISION_EXHAUSTED")
		data.waveRevision = Validation.MAX_SAFE_INTEGER
		return false
	end
	data.waveRevision += 1
	return true
end

local function snapshot(data: RuntimeData): WaveSnapshot?
	local origin = currentOrigin(data)
	local schedule = data.schedule
	if
		origin == nil
		or schedule == nil
		or data.currentWaveNumber < 1
		or data.state == "Uninitialized"
		or data.state == "Cleaned"
	then
		return nil
	end
	local wave = schedule.waves[data.currentWaveNumber]
	return table.freeze({
		matchId = data.matchId,
		enemyEpoch = data.enemyEpoch,
		mapId = data.mapId,
		difficultyId = data.difficultyId,
		state = data.state :: Exclude<RuntimeState, "Uninitialized" | "Cleaned">,
		waveRevision = data.waveRevision,
		currentWaveNumber = data.currentWaveNumber,
		totalWaves = data.totalWaves,
		currentWaveId = origin.waveId,
		bossKind = wave.bossKind,
		timerPhase = data.timerPhase,
		waveStartedServerTime = origin.waveStartedServerTime,
		deadlineServerTime = origin.deadlineServerTime,
		intermissionEndsServerTime = data.intermissionEndsServerTime,
		skipAvailableServerTime = data.skipAvailableServerTime,
		finiteCompleteServerTime = data.finiteCompleteServerTime,
		currentCounts = snapshotCounts(origin.counts),
		aggregateCounts = snapshotCounts(data.aggregateCounts),
		skipState = table.freeze({
			available = data.skipAvailable,
			activeParticipantCount = data.activeParticipantCount,
			yesVoteCount = data.yesVoteCount,
			requiredVoteCount = data.requiredVoteCount,
			quorumPending = data.quorumPending,
		}),
	})
end

local function completeFinite(data: RuntimeData, serverTime: number): boolean
	if
		data.currentWaveNumber ~= data.totalWaves
		or data.aggregateCounts.pending ~= 0
		or data.aggregateCounts.alive ~= 0
		or data.completionCount ~= 0
	then
		return false
	end
	data.state = "FiniteComplete"
	data.timerPhase = "None"
	data.skipAvailableServerTime = 0
	data.skipAvailable = false
	data.quorumPending = false
	data.finiteCompleteServerTime = serverTime
	data.completionCount = 1
	clearHeap(data)
	return true
end

local TERMINAL_FIELDS = table.freeze({
	matchId = true,
	enemyEpoch = true,
	runtimeEnemyId = true,
	enemyId = true,
	reason = true,
	serverTime = true,
})

local function applyTerminal(data: RuntimeData, value: unknown, sampleServerTime: number): (boolean, boolean)
	local dependencies = data.dependencies
	if dependencies == nil then
		return false, false
	end
	local authenticatedCall, authenticated = callNonYielding(dependencies.isAuthenticatedTerminalOutcome, value)
	if not authenticatedCall or authenticated ~= true then
		return false, false
	end
	if
		type(value) ~= "table"
		or not table.isfrozen(value :: any)
		or not hasExactFields(value :: { [any]: unknown }, TERMINAL_FIELDS)
	then
		return false, false
	end
	local outcome = value :: any
	if
		outcome.matchId ~= data.matchId
		or outcome.enemyEpoch ~= data.enemyEpoch
		or type(outcome.runtimeEnemyId) ~= "number"
		or not Validation.isSafeInteger(outcome.runtimeEnemyId)
		or outcome.runtimeEnemyId < 1
		or outcome.runtimeEnemyId > MAX_TOTAL_EVENTS
		or (outcome.reason ~= "Endpoint" and outcome.reason ~= "Manual" and outcome.reason ~= "Defeat")
		or not isFiniteNumber(outcome.serverTime)
		or outcome.serverTime < 0
		or outcome.serverTime > sampleServerTime
	then
		return false, false
	end
	local ownership = data.ownership[outcome.runtimeEnemyId]
	if ownership == nil or ownership.enemyId ~= outcome.enemyId or outcome.serverTime < ownership.spawnServerTime then
		return false, false
	end
	if ownership.resolved then
		return ownership.terminalReason == outcome.reason and ownership.terminalServerTime == outcome.serverTime, false
	end
	local origin = data.origins[ownership.waveIndex]
	if origin == nil or origin.counts.alive < 1 or data.aggregateCounts.alive < 1 then
		return false, false
	end
	ownership.resolved = true
	ownership.terminalReason = outcome.reason
	ownership.terminalServerTime = outcome.serverTime
	origin.counts.alive -= 1
	data.aggregateCounts.alive -= 1
	if outcome.reason == "Endpoint" then
		origin.counts.leaked += 1
		data.aggregateCounts.leaked += 1
	else
		origin.counts.otherwiseResolved += 1
		data.aggregateCounts.otherwiseResolved += 1
	end
	data.processedTerminalCount += 1
	return true, true
end

local SPAWN_OUTCOME_FALSE_FIELDS = table.freeze({ committed = true })
local SPAWN_OUTCOME_TRUE_FIELDS = table.freeze({ committed = true, replicationCommitted = true, snapshot = true })

local function validateSpawnOutcome(
	data: RuntimeData,
	entry: HeapEntry,
	value: unknown,
	sampleServerTime: number
): (boolean, boolean, any?)
	if type(value) ~= "table" or not table.isfrozen(value :: any) then
		return false, false, nil
	end
	local outcome = value :: any
	if outcome.committed == false then
		return hasExactFields(value :: { [any]: unknown }, SPAWN_OUTCOME_FALSE_FIELDS), false, nil
	end
	if outcome.committed ~= true or not hasExactFields(value :: { [any]: unknown }, SPAWN_OUTCOME_TRUE_FIELDS) then
		return false, false, nil
	end
	local record = outcome.snapshot
	local definition = data.configuration and data.configuration.enemies.byId[entry.event.enemyId]
	local difficulty = data.difficulty
	if
		type(outcome.replicationCommitted) ~= "boolean"
		or type(record) ~= "table"
		or not table.isfrozen(record)
		or definition == nil
		or difficulty == nil
		or type(record.runtimeEnemyId) ~= "number"
		or not Validation.isSafeInteger(record.runtimeEnemyId)
		or record.runtimeEnemyId < 1
		or record.runtimeEnemyId > MAX_TOTAL_EVENTS
		or data.ownership[record.runtimeEnemyId] ~= nil
		or record.enemyId ~= entry.event.enemyId
		or record.laneId ~= entry.event.laneId
		or record.spawnServerTime ~= sampleServerTime
		or record.maximumHealth ~= definition.maxHealth * difficulty.modifiers.enemyHealthMultiplier
		or record.currentHealth ~= record.maximumHealth
		or record.effectiveSpeed
			~= definition.moveSpeedStudsPerSecond * difficulty.modifiers.enemyMoveSpeedMultiplier
	then
		return false, false, nil
	end
	return true, true, record
end

local function spawnHead(data: RuntimeData, frame: PassFrame, entry: HeapEntry): (boolean, boolean, ErrorCode?)
	local origin = data.origins[entry.waveIndex]
	if
		origin == nil
		or origin.nextEventIndex ~= entry.eventIndex
		or origin.counts.pending < 1
		or data.aggregateCounts.pending < 1
	then
		return false, false, "INVALID_PASS"
	elseif data.aggregateCounts.alive >= MAX_ACTIVE then
		return false, false, "CAPACITY_EXCEEDED"
	elseif frame.spawn == nil then
		return false, false, "ENEMY_FAILED"
	end
	local defeated = baseIsDefeated(data)
	if defeated == nil then
		return false, false, "BASE_FAILED"
	elseif defeated then
		data.state = "DefeatClosed"
		data.timerPhase = "None"
		clearHeap(data)
		return true, false, nil
	end
	local event = table.freeze({
		originatingWaveIndex = entry.waveIndex,
		waveId = origin.waveId,
		groupIndex = entry.event.groupIndex,
		spawnOrdinal = entry.event.spawnOrdinal,
		scheduledServerTime = entry.scheduledServerTime,
		enemyId = entry.event.enemyId,
		laneId = entry.event.laneId,
	})
	-- Retain the exact attempted head until Enemy's commit-aware outcome has
	-- either been adopted or has proven that Store did not mutate. The separate
	-- authenticated close path uses this record if the callback commits a Store
	-- spawn and then throws before returning its outcome.
	data.pendingSpawnEntry = entry
	local called, outcomeValue = callNonYielding(frame.spawn :: (SpawnEvent) -> unknown, event)
	if not called then
		return false, false, "CALLBACK_FAILED"
	end
	local valid, committed, record = validateSpawnOutcome(data, entry, outcomeValue, frame.sampleServerTime)
	if not valid then
		return false, false, "ENEMY_FAILED"
	elseif not committed then
		data.pendingSpawnEntry = nil
		return false, false, "CAPACITY_EXCEEDED"
	end
	heapPop(data.heap)
	origin.nextEventIndex += 1
	origin.counts.pending -= 1
	origin.counts.spawned += 1
	origin.counts.alive += 1
	data.aggregateCounts.pending -= 1
	data.aggregateCounts.spawned += 1
	data.aggregateCounts.alive += 1
	data.ownership[record.runtimeEnemyId] = {
		waveIndex = entry.waveIndex,
		enemyId = record.enemyId,
		spawnServerTime = record.spawnServerTime,
		resolved = false,
		terminalReason = nil,
		terminalServerTime = nil,
	}
	data.pendingSpawnEntry = nil
	if not insertOriginHead(data, origin) then
		return false, true, "ENEMY_FAILED"
	end
	if not enforceBaseAuthority(data) then
		if data.state == "DefeatClosed" then
			return true, true, nil
		end
		return false, true, "BASE_FAILED"
	end
	if data.reentryViolation then
		return false, true, "REENTRANT"
	elseif (outcomeValue :: any).replicationCommitted ~= true then
		return false, true, "ENEMY_FAILED"
	end
	return true, true, nil
end

local function processHealthy(data: RuntimeData, frame: PassFrame): boolean
	local dirty = false
	local work = 0
	local rosterAuthorized, lifecycle = enforceAuthority(data)
	if not rosterAuthorized or lifecycle == nil then
		return true
	end
	if #frame.terminalOutcomes > MAX_TERMINALS_PER_PASS then
		setFault(data, "CAPACITY_EXCEEDED")
		return true
	end
	for _, outcome in frame.terminalOutcomes do
		if work >= MAX_WORK_PER_PASS then
			setFault(data, "CAPACITY_EXCEEDED")
			return true
		end
		local accepted, changed = applyTerminal(data, outcome, frame.sampleServerTime)
		if not accepted then
			setFault(data, "INVALID_OUTCOME")
			return true
		end
		dirty = dirty or changed
		work += 1
	end

	local rosterChanged = applyRosterProjection(data, projectRoster(data, lifecycle))
	local quorumChanged = updateSkipWindow(data, frame.sampleServerTime)
	dirty = dirty or rosterChanged or quorumChanged

	local spawnCount = 0
	while work < MAX_WORK_PER_PASS and data.state ~= "Faulted" and data.state ~= "DefeatClosed" do
		if not enforceBaseAuthority(data) then
			dirty = true
			break
		end

		if data.state == "Intermission" then
			if frame.sampleServerTime < data.intermissionEndsServerTime then
				break
			end
			if not startWave(data, data.currentWaveNumber + 1, data.intermissionEndsServerTime) then
				setFault(data, "INVALID_PASS")
			end
			data.state = if data.state == "Faulted" then "Faulted" else "Running"
			if data.state == "Running" then
				updateSkipWindow(data, frame.sampleServerTime)
			end
			dirty = true
			work += 1
			continue
		end

		if data.state ~= "Running" then
			break
		end
		local origin = currentOrigin(data)
		if origin == nil then
			setFault(data, "INVALID_PASS")
			dirty = true
			break
		end
		local limit = if data.timerPhase == "PostDeadline"
			then frame.sampleServerTime
			else math.min(frame.sampleServerTime, origin.deadlineServerTime)
		local head = data.heap[1]
		if head ~= nil and head.scheduledServerTime <= limit and spawnCount < MAX_SPAWNS_PER_PASS then
			local succeeded, _, errorCode = spawnHead(data, frame, head)
			if not succeeded then
				setFault(data, errorCode or "ENEMY_FAILED")
				dirty = true
				break
			end
			dirty = true
			work += 1
			spawnCount += 1
			continue
		end
		if head ~= nil and head.scheduledServerTime <= limit and spawnCount >= MAX_SPAWNS_PER_PASS then
			break
		end

		if data.timerPhase ~= "PostDeadline" and frame.sampleServerTime >= origin.deadlineServerTime then
			if data.deadlineConsumed then
				setFault(data, "INVALID_PASS")
			elseif data.currentWaveNumber < data.totalWaves then
				data.deadlineConsumed = true
				if not startWave(data, data.currentWaveNumber + 1, origin.deadlineServerTime) then
					setFault(data, "INVALID_PASS")
				end
				data.state = if data.state == "Faulted" then "Faulted" else "Running"
				if data.state == "Running" then
					updateSkipWindow(data, frame.sampleServerTime)
				end
			else
				data.deadlineConsumed = true
				data.timerPhase = "PostDeadline"
			end
			dirty = true
			work += 1
			continue
		end

		if
			data.quorumPending
			and data.timerPhase == "WaveDeadline"
			and data.currentWaveNumber < data.totalWaves
			and frame.sampleServerTime < origin.deadlineServerTime
		then
			data.deadlineConsumed = true
			if not startWave(data, data.currentWaveNumber + 1, frame.sampleServerTime) then
				setFault(data, "INVALID_PASS")
			end
			data.state = if data.state == "Faulted" then "Faulted" else "Running"
			if data.state == "Running" then
				updateSkipWindow(data, frame.sampleServerTime)
			end
			dirty = true
			work += 1
			continue
		end

		if
			data.currentWaveNumber == data.totalWaves
			and data.aggregateCounts.pending == 0
			and data.aggregateCounts.alive == 0
		then
			if not completeFinite(data, frame.sampleServerTime) then
				setFault(data, "INVALID_PASS")
			end
			dirty = true
			work += 1
			break
		end

		if
			data.currentWaveNumber < data.totalWaves
			and data.timerPhase == "WaveDeadline"
			and frame.sampleServerTime < origin.deadlineServerTime
			and data.aggregateCounts.pending == 0
			and data.aggregateCounts.alive == 0
		then
			local difficulty = data.difficulty :: ConfigTypes.FiniteDifficultyDefinition
			local intermissionEnd = frame.sampleServerTime + difficulty.timing.earlyClearIntermissionSeconds
			if not Validation.isFiniteNumber(intermissionEnd) or intermissionEnd < frame.sampleServerTime then
				setFault(data, "CLOCK_FAILED")
			else
				data.state = "Intermission"
				data.timerPhase = "EarlyClearIntermission"
				data.intermissionEndsServerTime = intermissionEnd
				data.skipAvailableServerTime = 0
				data.skipAvailable = false
				data.quorumPending = false
			end
			dirty = true
			work += 1
			break
		end
		break
	end
	return dirty
end

local function validateFrame(data: RuntimeData, value: unknown): (PassFrame?, ErrorCode?)
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil, "INVALID_PASS"
	end
	local frame = value :: any
	local healthy = frame.disposition == "Healthy"
	if
		not hasExactFields(frame, if healthy then HEALTHY_PASS_FRAME_FIELDS else CLOSED_PASS_FRAME_FIELDS)
		or (frame.disposition ~= "Healthy" and frame.disposition ~= "DefeatCommitted" and frame.disposition ~= "DependencyFault" and frame.disposition ~= "Shutdown")
		or frame.matchId ~= data.matchId
		or frame.enemyEpoch ~= data.enemyEpoch
		or type(frame.passOrdinal) ~= "number"
		or not Validation.isSafeInteger(frame.passOrdinal)
		or ((data.lastPassOrdinal == 0 and frame.passOrdinal < 1) or (data.lastPassOrdinal > 0 and frame.passOrdinal ~= data.lastPassOrdinal + 1))
		or type(frame.terminalOutcomes) ~= "table"
		or getmetatable(frame.terminalOutcomes) ~= nil
		or (healthy and type(frame.spawn) ~= "function")
	then
		return nil, "INVALID_PASS"
	end
	if not isFiniteNumber(frame.sampleServerTime) or frame.sampleServerTime < data.lastServerTime then
		return nil, "CLOCK_FAILED"
	end
	local length = #frame.terminalOutcomes
	local count = 0
	for key in next, frame.terminalOutcomes do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return nil, "INVALID_PASS"
		end
		count += 1
	end
	if count ~= length then
		return nil, "INVALID_PASS"
	end
	return value :: PassFrame, nil
end

function RuntimeMethods.initialize(self: Runtime): Result.Result<WaveSnapshot, RuntimeError>
	local data = requireData(self)
	local operation: Operation = "initialize"
	local operationError = beginOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if data.state ~= "Uninitialized" then
		finishOperation(data)
		return failure("WRONG_STATE", operation)
	end
	local dependencies = data.dependencies :: Dependencies
	local lifecycleBefore = readLifecycleSnapshot(data)
	if lifecycleBefore == nil or lifecycleBefore.state ~= "PreWave" then
		setFault(data, "LIFECYCLE_FAILED")
		finishOperation(data)
		return failure("LIFECYCLE_FAILED", operation)
	end
	commitLifecyclePin(data, lifecycleBefore)
	local began, beginResult = callResult(dependencies.beginWaveActivation, data.matchId)
	if not began or not isSuccess(beginResult) then
		setFault(data, "LIFECYCLE_FAILED")
		finishOperation(data)
		return failure("LIFECYCLE_FAILED", operation)
	end
	local token = (beginResult :: any).value
	local baseCalled, baseResult = callResult(dependencies.initializeBase, data.difficulty :: any)
	if not baseCalled or not isSuccess(baseResult) then
		callResult(dependencies.rollbackWaveActivation, token)
		setFault(data, "BASE_FAILED")
		finishOperation(data)
		return failure("BASE_FAILED", operation)
	end
	local bindCalled, bindResult = callResult(
		dependencies.bindDifficulty,
		data.configuration :: ConfigTypes.CoreConfiguration,
		data.difficulty :: ConfigTypes.FiniteDifficultyDefinition
	)
	if not bindCalled or not isSuccess(bindResult) or (bindResult :: any).value ~= true then
		callResult(dependencies.rollbackWaveActivation, token)
		setFault(data, "ENEMY_FAILED")
		finishOperation(data)
		return failure("ENEMY_FAILED", operation)
	end
	local clockCalled, clockValue = callNonYielding(dependencies.clock)
	if not clockCalled or not isFiniteNumber(clockValue) or (clockValue :: number) < data.lastServerTime then
		callResult(dependencies.rollbackWaveActivation, token)
		setFault(data, "CLOCK_FAILED")
		finishOperation(data)
		return failure("CLOCK_FAILED", operation)
	end
	local committed, commitResult = callResult(dependencies.commitWaveActivation, token)
	local commitValue = if committed and isSuccess(commitResult) then (commitResult :: any).value else nil
	local committedSnapshot = if type(commitValue) == "table"
		then MatchProtocol.validateMatchSnapshot((commitValue :: any).snapshot)
		else nil
	if
		type(commitValue) ~= "table"
		or not table.isfrozen(commitValue)
		or commitValue.committed ~= true
		or type(commitValue.published) ~= "boolean"
		or committedSnapshot == nil
		or not committedSnapshot.ok
		or committedSnapshot.value.matchId ~= data.matchId
		or committedSnapshot.value.state ~= "WaveActive"
		or committedSnapshot.value.revision ~= lifecycleBefore.revision + 1
		or not lifecycleParticipantsMatch(data, committedSnapshot.value)
	then
		callResult(dependencies.rollbackWaveActivation, token)
		setFault(data, "LIFECYCLE_FAILED")
		finishOperation(data)
		return failure("LIFECYCLE_FAILED", operation)
	end
	local activationSnapshot = (committedSnapshot :: any).value :: MatchProtocol.MatchSnapshot
	commitLifecyclePin(data, activationSnapshot)
	data.lastServerTime = clockValue :: number
	if not startWave(data, 1, data.lastServerTime) then
		setFault(data, "CAPACITY_EXCEEDED")
		finishOperation(data)
		return failure("CAPACITY_EXCEEDED", operation)
	end
	data.state = "Running"
	applyRosterProjection(data, projectRoster(data, activationSnapshot))
	updateSkipWindow(data, data.lastServerTime)
	if not advanceRevision(data) then
		finishOperation(data)
		return failure("REVISION_EXHAUSTED", operation)
	end
	local result = snapshot(data)
	finishOperation(data)
	if result == nil or data.state == "Cleaned" then
		return failure("CLEANED", operation)
	end
	return Result.ok(result)
end

function RuntimeMethods.step(self: Runtime, frameValue: unknown): Result.Result<WaveSnapshot, RuntimeError>
	local data = requireData(self)
	local operation: Operation = "step"
	local operationError = beginOperation(data, operation, true)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	if data.state ~= "Running" and data.state ~= "Intermission" then
		finishOperation(data)
		return failure("WRONG_STATE", operation)
	end
	local frame, frameError = validateFrame(data, frameValue)
	if frame == nil then
		setFault(data, frameError or "INVALID_PASS")
		advanceRevision(data)
		local failedSnapshot = snapshot(data)
		finishOperation(data)
		return if failedSnapshot == nil
			then failure(frameError or "INVALID_PASS", operation)
			else Result.ok(failedSnapshot)
	end
	data.lastPassOrdinal = frame.passOrdinal
	data.lastServerTime = frame.sampleServerTime
	local dirty = false
	if frame.disposition == "DefeatCommitted" then
		data.state = "DefeatClosed"
		data.timerPhase = "None"
		data.skipAvailableServerTime = 0
		data.skipAvailable = false
		data.quorumPending = false
		clearHeap(data)
		dirty = true
	elseif frame.disposition == "DependencyFault" or frame.disposition == "Shutdown" then
		setFault(data, if frame.disposition == "Shutdown" then "CLEANED" else "ENEMY_FAILED")
		dirty = true
	else
		dirty = processHealthy(data, frame)
	end
	if dirty and data.state ~= "Cleaned" then
		advanceRevision(data)
	end
	local result = snapshot(data)
	finishOperation(data)
	if result == nil or data.state == "Cleaned" then
		return failure("CLEANED", operation)
	end
	return Result.ok(result)
end

local function validateDependencyFaultContext(data: RuntimeData, value: unknown): DependencyFaultContext?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or not table.isfrozen(value :: any) then
		return nil
	end
	local context = value :: any
	local hasCommittedSpawn = context.committedSpawn ~= nil
	local hasTerminalOutcome = context.terminalOutcome ~= nil
	if hasCommittedSpawn ~= hasTerminalOutcome then
		return nil
	end
	local fields = if hasCommittedSpawn
		then DEPENDENCY_FAULT_CONTEXT_WITH_SPAWN_FIELDS
		else DEPENDENCY_FAULT_CONTEXT_FIELDS
	local nextPassOrdinal = if data.lastPassOrdinal < Validation.MAX_SAFE_INTEGER
		then data.lastPassOrdinal + 1
		else data.lastPassOrdinal
	if
		not hasExactFields(context, fields)
		or context.disposition ~= "DependencyFault"
		or context.matchId ~= data.matchId
		or context.enemyEpoch ~= data.enemyEpoch
		or type(context.passOrdinal) ~= "number"
		or not Validation.isSafeInteger(context.passOrdinal)
		or context.passOrdinal < 1
		or (context.passOrdinal ~= data.lastPassOrdinal and context.passOrdinal ~= nextPassOrdinal)
		or not isFiniteNumber(context.sampleServerTime)
		or context.sampleServerTime < data.lastServerTime
	then
		return nil
	end
	return value :: DependencyFaultContext
end

local function eventMatchesEntry(data: RuntimeData, value: unknown, entry: HeapEntry): boolean
	if
		type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
		or not hasExactFields(value :: { [any]: unknown }, SPAWN_EVENT_FIELDS)
	then
		return false
	end
	local event = value :: any
	local origin = data.origins[entry.waveIndex]
	return origin ~= nil
		and event.originatingWaveIndex == entry.waveIndex
		and event.waveId == origin.waveId
		and event.groupIndex == entry.event.groupIndex
		and event.spawnOrdinal == entry.event.spawnOrdinal
		and event.scheduledServerTime == entry.scheduledServerTime
		and event.enemyId == entry.event.enemyId
		and event.laneId == entry.event.laneId
end

local function validFaultTerminalOutcome(
	data: RuntimeData,
	value: unknown,
	spawnOutcome: unknown,
	sampleServerTime: number
): boolean
	local dependencies = data.dependencies
	if
		dependencies == nil
		or type(value) ~= "table"
		or getmetatable(value :: any) ~= nil
		or not table.isfrozen(value :: any)
		or not hasExactFields(value :: { [any]: unknown }, TERMINAL_FIELDS)
		or type(spawnOutcome) ~= "table"
		or type((spawnOutcome :: any).snapshot) ~= "table"
	then
		return false
	end
	local terminal = value :: any
	local spawn = (spawnOutcome :: any).snapshot
	local called, authenticated = callNonYielding(dependencies.isAuthenticatedTerminalOutcome, value)
	return called
		and authenticated == true
		and terminal.matchId == data.matchId
		and terminal.enemyEpoch == data.enemyEpoch
		and terminal.runtimeEnemyId == spawn.runtimeEnemyId
		and terminal.enemyId == spawn.enemyId
		and terminal.reason == "Manual"
		and terminal.serverTime == sampleServerTime
end

local function sameDeepFrozenValue(left: unknown, right: unknown, seen: { [any]: any }?): boolean
	if left == right then
		return true
	elseif type(left) ~= "table" or type(right) ~= "table" then
		return false
	elseif
		getmetatable(left :: any) ~= nil
		or getmetatable(right :: any) ~= nil
		or not table.isfrozen(left :: any)
		or not table.isfrozen(right :: any)
	then
		return false
	end

	local visited = seen or {}
	if visited[left :: any] ~= nil then
		return visited[left :: any] == right
	end
	visited[left :: any] = right
	local leftCount = 0
	for key, leftValue in next, left :: any do
		leftCount += 1
		if not sameDeepFrozenValue(leftValue, (right :: any)[key], visited) then
			return false
		end
	end
	local rightCount = 0
	for _ in next, right :: any do
		rightCount += 1
	end
	return leftCount == rightCount
end

local function sameCommittedSpawn(left: CommittedSpawnReconciliation?, right: unknown): boolean
	if left == nil then
		return left == nil and right == nil
	end
	return sameDeepFrozenValue(left, right)
end

local function sameTerminalOutcome(left: TerminalOutcome?, right: unknown): boolean
	if left == nil then
		return left == nil and right == nil
	end
	return sameDeepFrozenValue(left, right)
end

local function matchesOwnedCommittedSpawn(data: RuntimeData, outcome: any, sampleServerTime: number): boolean
	if
		type(outcome) ~= "table"
		or getmetatable(outcome) ~= nil
		or not table.isfrozen(outcome)
		or not hasExactFields(outcome, SPAWN_OUTCOME_TRUE_FIELDS)
		or outcome.committed ~= true
		or type(outcome.replicationCommitted) ~= "boolean"
		or type(outcome.snapshot) ~= "table"
		or getmetatable(outcome.snapshot) ~= nil
		or not table.isfrozen(outcome.snapshot)
	then
		return false
	end
	local record = outcome.snapshot
	local ownership = data.ownership[record.runtimeEnemyId]
	local definition = data.configuration and data.configuration.enemies.byId[record.enemyId]
	local difficulty = data.difficulty
	return ownership ~= nil
		and ownership.resolved == false
		and ownership.enemyId == record.enemyId
		and ownership.spawnServerTime == record.spawnServerTime
		and record.spawnServerTime == sampleServerTime
		and definition ~= nil
		and difficulty ~= nil
		and record.maximumHealth == definition.maxHealth * difficulty.modifiers.enemyHealthMultiplier
		and record.currentHealth == record.maximumHealth
		and record.effectiveSpeed
			== definition.moveSpeedStudsPerSecond * difficulty.modifiers.enemyMoveSpeedMultiplier
end

local function reconcileCommittedSpawn(
	data: RuntimeData,
	committedSpawnValue: unknown,
	sampleServerTime: number
): (boolean, boolean)
	if committedSpawnValue == nil then
		data.pendingSpawnEntry = nil
		return true, false
	end
	if
		type(committedSpawnValue) ~= "table"
		or getmetatable(committedSpawnValue :: any) ~= nil
		or not table.isfrozen(committedSpawnValue :: any)
		or not hasExactFields(committedSpawnValue :: { [any]: unknown }, COMMITTED_SPAWN_RECONCILIATION_FIELDS)
	then
		return false, false
	end
	local committedSpawn = committedSpawnValue :: any
	if matchesOwnedCommittedSpawn(data, committedSpawn.outcome, sampleServerTime) then
		data.pendingSpawnEntry = nil
		return true, false
	end

	local entry = data.pendingSpawnEntry or data.heap[1]
	if entry == nil or not eventMatchesEntry(data, committedSpawn.event, entry) then
		return false, false
	end
	local origin = data.origins[entry.waveIndex]
	local valid, committed, record = validateSpawnOutcome(data, entry, committedSpawn.outcome, sampleServerTime)
	if
		not valid
		or not committed
		or record == nil
		or origin == nil
		or origin.nextEventIndex ~= entry.eventIndex
		or origin.counts.pending < 1
		or data.aggregateCounts.pending < 1
		or origin.counts.spawned >= Validation.MAX_SAFE_INTEGER
		or origin.counts.alive >= Validation.MAX_SAFE_INTEGER
		or data.aggregateCounts.spawned >= Validation.MAX_SAFE_INTEGER
		or data.aggregateCounts.alive >= Validation.MAX_SAFE_INTEGER
	then
		return false, false
	end
	if data.heap[1] == entry then
		heapPop(data.heap)
	elseif data.pendingSpawnEntry ~= entry then
		return false, false
	end
	origin.nextEventIndex += 1
	origin.counts.pending -= 1
	origin.counts.spawned += 1
	origin.counts.alive += 1
	data.aggregateCounts.pending -= 1
	data.aggregateCounts.spawned += 1
	data.aggregateCounts.alive += 1
	data.ownership[(record :: any).runtimeEnemyId] = {
		waveIndex = entry.waveIndex,
		enemyId = (record :: any).enemyId,
		spawnServerTime = (record :: any).spawnServerTime,
		resolved = false,
		terminalReason = nil,
		terminalServerTime = nil,
	}
	data.pendingSpawnEntry = nil
	return true, true
end

function RuntimeMethods.closeDependencyFault(
	self: Runtime,
	contextValue: unknown
): Result.Result<WaveSnapshot, RuntimeError>
	local data = requireData(self)
	local operation: Operation = "closeDependencyFault"
	if data.state == "Cleaned" then
		return failure("CLEANED", operation)
	elseif data.state == "Uninitialized" then
		return failure("WRONG_STATE", operation)
	end
	local context = validateDependencyFaultContext(data, contextValue)
	if context == nil then
		return failure("INVALID_PASS", operation)
	end
	if data.state == "FiniteComplete" or data.state == "DefeatClosed" then
		local terminalSnapshot = snapshot(data)
		return if terminalSnapshot == nil then failure("WRONG_STATE", operation) else Result.ok(terminalSnapshot)
	end
	if data.faultCloseCount ~= 0 then
		if
			data.faultCloseCount == 1
			and sameCommittedSpawn(data.faultCloseCommittedSpawn, context.committedSpawn)
			and sameTerminalOutcome(data.faultCloseTerminalOutcome, context.terminalOutcome)
		then
			local retainedSnapshot = snapshot(data)
			return if retainedSnapshot == nil then failure("WRONG_STATE", operation) else Result.ok(retainedSnapshot)
		end
		return failure("INVALID_OUTCOME", operation)
	end

	-- The primary step coroutine is already returned or forcibly closed before
	-- this private one-shot path is invoked. Recover its stale mutation latch so
	-- the sole driver cannot leave Wave apparently Running after a callback yield.
	data.busy = true
	data.reentryViolation = false
	local committedOutcome = if context.committedSpawn == nil
		then nil
		else (context.committedSpawn :: CommittedSpawnReconciliation).outcome
	if
		context.terminalOutcome ~= nil
		and not validFaultTerminalOutcome(data, context.terminalOutcome, committedOutcome, context.sampleServerTime)
	then
		finishOperation(data)
		return failure("INVALID_OUTCOME", operation)
	end
	local reconciled, changed = reconcileCommittedSpawn(data, context.committedSpawn, context.sampleServerTime)
	if not reconciled then
		finishOperation(data)
		return failure("INVALID_OUTCOME", operation)
	end
	if context.terminalOutcome ~= nil then
		local acceptedTerminal, terminalChanged = applyTerminal(data, context.terminalOutcome, context.sampleServerTime)
		if not acceptedTerminal then
			setFault(data, "INVALID_OUTCOME")
			if data.waveRevision < Validation.MAX_SAFE_INTEGER then
				advanceRevision(data)
			end
			finishOperation(data)
			return failure("INVALID_OUTCOME", operation)
		end
		changed = changed or terminalChanged
	end
	data.faultCloseCount = 1
	data.faultCloseCommittedSpawn = context.committedSpawn
	data.faultCloseTerminalOutcome = context.terminalOutcome
	data.lastPassOrdinal = math.max(data.lastPassOrdinal, context.passOrdinal)
	data.lastServerTime = context.sampleServerTime
	local transitioned = data.state ~= "Faulted"
	if transitioned then
		setFault(data, "ENEMY_FAILED")
	end
	if (transitioned or changed) and not advanceRevision(data) then
		finishOperation(data)
		return failure("REVISION_EXHAUSTED", operation)
	end
	local result = snapshot(data)
	finishOperation(data)
	if result == nil or data.state == "Cleaned" then
		return failure("CLEANED", operation)
	end
	return Result.ok(result)
end

function RuntimeMethods.submitSkipVote(
	self: Runtime,
	userIdValue: unknown,
	matchIdValue: unknown,
	waveNumberValue: unknown
): Result.Result<WaveSnapshot, RuntimeError>
	local data = requireData(self)
	local operation: Operation = "submitSkipVote"
	if
		data.state == "Uninitialized"
		or data.state == "FiniteComplete"
		or data.state == "DefeatClosed"
		or data.state == "Faulted"
		or data.state == "Cleaned"
	then
		return failure("UNAVAILABLE", operation)
	end
	if matchIdValue ~= data.matchId or waveNumberValue ~= data.currentWaveNumber then
		return failure("STALE_REQUEST", operation)
	end
	if type(userIdValue) ~= "number" or not Validation.isSafeInteger(userIdValue) or userIdValue == 0 then
		return failure("NOT_AUTHORIZED", operation)
	end
	if data.state ~= "Running" or data.timerPhase ~= "WaveDeadline" or data.currentWaveNumber >= data.totalWaves then
		return failure("UNAVAILABLE", operation)
	end

	local operationError = beginOperation(data, operation, true)
	if operationError ~= nil then
		return failure("UNAVAILABLE", operation)
	end
	local previousState = data.state
	local authorized, lifecycle = enforceAuthority(data)
	if not authorized or lifecycle == nil then
		if data.state ~= previousState then
			advanceRevision(data)
		end
		finishOperation(data)
		return failure("UNAVAILABLE", operation)
	end
	local projection = projectRoster(data, lifecycle)
	commitLifecyclePin(data, lifecycle)

	local dependencies = data.dependencies :: Dependencies
	local clockCalled, clockValue = callNonYielding(dependencies.clock)
	if not clockCalled or not isFiniteNumber(clockValue) or (clockValue :: number) < data.lastServerTime then
		setFault(data, "CLOCK_FAILED")
		advanceRevision(data)
		finishOperation(data)
		return failure("UNAVAILABLE", operation)
	end
	if data.reentryViolation then
		setFault(data, "REENTRANT")
		advanceRevision(data)
		finishOperation(data)
		return failure("UNAVAILABLE", operation)
	elseif data.cleanupRequested then
		finishOperation(data)
		return failure("UNAVAILABLE", operation)
	end

	local serverTime = clockValue :: number
	local origin = currentOrigin(data)
	if origin == nil or serverTime < data.skipAvailableServerTime or serverTime >= origin.deadlineServerTime then
		finishOperation(data)
		return failure("UNAVAILABLE", operation)
	end
	local userId = userIdValue :: number
	if projection.activeUserIds[userId] ~= true then
		finishOperation(data)
		return failure("NOT_AUTHORIZED", operation)
	end
	if data.castUserIds[userId] == true then
		finishOperation(data)
		return failure("DUPLICATE_REQUEST", operation)
	end
	if data.waveRevision >= Validation.MAX_SAFE_INTEGER - 1 then
		if data.waveRevision == Validation.MAX_SAFE_INTEGER - 1 then
			setFault(data, "REVISION_EXHAUSTED")
			advanceRevision(data)
		end
		finishOperation(data)
		return failure("UNAVAILABLE", operation)
	end

	applyRosterProjection(data, projection)
	data.lastServerTime = serverTime
	data.skipAvailable = true
	data.castUserIds[userId] = true
	data.voterUserIds[userId] = true
	data.yesVoteCount += 1
	data.quorumPending = data.requiredVoteCount > 0 and data.yesVoteCount >= data.requiredVoteCount
	if not advanceRevision(data) then
		finishOperation(data)
		return failure("UNAVAILABLE", operation)
	end
	local result = snapshot(data)
	finishOperation(data)
	if result == nil or data.state == "Cleaned" then
		return failure("UNAVAILABLE", operation)
	end
	return Result.ok(result)
end

function RuntimeMethods.getSnapshot(self: Runtime): Result.Result<WaveSnapshot, RuntimeError>
	local data = requireData(self)
	local operation: Operation = "getSnapshot"
	local operationError = beginOperation(data, operation, false)
	if operationError ~= nil then
		return Result.err(operationError)
	end
	local value = snapshot(data)
	return if value == nil then failure("WRONG_STATE", operation) else Result.ok(value)
end

function RuntimeMethods.getStartingCashPlaceholder(self: Runtime): Result.Result<StartingCashPlaceholder, RuntimeError>
	local data = requireData(self)
	if data.state == "Cleaned" then
		return failure("CLEANED", "query")
	end
	local placeholder = data.startingCash
	return if placeholder == nil then failure("WRONG_STATE", "query") else Result.ok(placeholder)
end

function RuntimeMethods.getCompletionState(self: Runtime): { state: RuntimeState, completionCount: number }
	local data = requireData(self)
	return table.freeze({
		state = data.state,
		completionCount = data.completionCount,
	})
end

function RuntimeMethods.query(self: Runtime): unknown
	local data = requireData(self)
	if data.state == "Cleaned" then
		return table.freeze({
			state = "Cleaned",
			retainedOriginCount = 0,
			retainedOwnershipCount = 0,
			retainedHeapCount = 0,
			processedTerminalCount = 0,
			retainedActiveUserIdCount = 0,
			retainedVoteCount = 0,
			retainedCastHistoryCount = 0,
			lastLifecycleRevision = 0,
			faultCloseCount = 0,
			completionCount = 0,
			busy = false,
		})
	end
	local originCount = 0
	for _ in data.origins do
		originCount += 1
	end
	local ownershipCount = 0
	for _ in data.ownership do
		ownershipCount += 1
	end
	local activeUserIdCount = 0
	for _ in data.activeUserIds do
		activeUserIdCount += 1
	end
	local voterCount = 0
	for _ in data.voterUserIds do
		voterCount += 1
	end
	local castHistoryCount = 0
	for _ in data.castUserIds do
		castHistoryCount += 1
	end
	return table.freeze({
		state = data.state,
		timerPhase = data.timerPhase,
		waveRevision = data.waveRevision,
		currentWaveNumber = data.currentWaveNumber,
		totalWaves = data.totalWaves,
		lastPassOrdinal = data.lastPassOrdinal,
		lastServerTime = data.lastServerTime,
		retainedOriginCount = originCount,
		retainedOwnershipCount = ownershipCount,
		retainedHeapCount = #data.heap,
		processedTerminalCount = data.processedTerminalCount,
		retainedActiveUserIdCount = activeUserIdCount,
		retainedVoteCount = voterCount,
		retainedCastHistoryCount = castHistoryCount,
		lastLifecycleRevision = data.lastLifecycleRevision,
		faultCloseCount = data.faultCloseCount,
		completionCount = data.completionCount,
		faultCode = data.faultCode,
		busy = data.busy,
	})
end

function RuntimeMethods.cleanup(self: Runtime): Result.Result<boolean, RuntimeError>
	local data = requireData(self)
	if data.state == "Cleaned" then
		return Result.ok(false)
	end
	if data.busy then
		data.cleanupRequested = true
		return Result.ok(false)
	end
	cleanupData(data)
	return Result.ok(true)
end

function WaveRuntime.new(
	configurationValue: unknown,
	runtimeMapValue: unknown,
	matchIdValue: unknown,
	enemyEpochValue: unknown,
	difficultyIdValue: unknown,
	dependenciesValue: unknown
): Result.Result<Runtime, RuntimeError>
	local operation: Operation = "new"
	if not ConfigurationValidator.isValidatedConfiguration(configurationValue) then
		return failure("INVALID_CONFIGURATION", operation)
	end
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	if not matchIdResult.ok then
		return failure("INVALID_MATCH_ID", operation)
	end
	if
		type(enemyEpochValue) ~= "number"
		or not Validation.isSafeInteger(enemyEpochValue)
		or enemyEpochValue < 1
		or enemyEpochValue > MAX_TOTAL_EVENTS
	then
		return failure("INVALID_EPOCH", operation)
	end
	local difficultyIdResult = Ids.validateDifficultyId(difficultyIdValue)
	if not difficultyIdResult.ok then
		return failure("INVALID_DIFFICULTY", operation)
	end
	local dependencies = validateDependencies(dependenciesValue)
	if dependencies == nil then
		return failure("INVALID_DEPENDENCIES", operation)
	end
	local configuration = configurationValue :: ConfigTypes.CoreConfiguration
	local difficultyValue = configuration.difficulties.byId[difficultyIdResult.value]
	if difficultyValue == nil or difficultyValue.kind ~= "Finite" then
		return failure("INVALID_DIFFICULTY", operation)
	end
	local difficulty = difficultyValue :: ConfigTypes.FiniteDifficultyDefinition
	local runtimeMapId = if type(runtimeMapValue) == "table" then (runtimeMapValue :: any).mapId else nil
	local runtimeMapIdResult = Ids.validateMapId(runtimeMapId)
	if not runtimeMapIdResult.ok then
		return failure("INVALID_RUNTIME_MAP", operation)
	end
	local mapDefinition = configuration.maps.byId[runtimeMapIdResult.value]
	if
		mapDefinition == nil
		or not validateRuntimeMap(runtimeMapValue, mapDefinition, dependencies.isRuntimeMapSnapshot)
	then
		return failure("INVALID_RUNTIME_MAP", operation)
	end
	local schedulesForMap = configuration.waves.byMapId[mapDefinition.id]
	local scheduleValue = schedulesForMap and schedulesForMap[difficulty.id]
	if
		scheduleValue == nil
		or scheduleValue.kind ~= "AuthoredFinite"
		or scheduleValue.mapId ~= mapDefinition.id
		or scheduleValue.difficultyId ~= difficulty.id
		or #scheduleValue.waves ~= difficulty.waveCount
		or difficulty.waveCount < 1
		or difficulty.waveCount > MAX_WAVES
	then
		return failure("UNSUPPORTED_SCHEDULE", operation)
	end
	local economyRule = configuration.economy.byDifficultyId[difficulty.id]
	if economyRule == nil or economyRule.difficultyId ~= difficulty.id then
		return failure("INVALID_CONFIGURATION", operation)
	end
	local relativeEventsByWave, totalEvents = preflatten(scheduleValue)
	if relativeEventsByWave == nil or totalEvents == nil or totalEvents > MAX_TOTAL_EVENTS then
		return failure("CAPACITY_EXCEEDED", operation)
	end
	local runtime = setmetatable({}, RuntimeMethods) :: Runtime
	table.freeze(runtime)
	RUNTIME_DATA[runtime] = {
		state = "Uninitialized",
		timerPhase = "None",
		matchId = matchIdResult.value,
		enemyEpoch = enemyEpochValue,
		mapId = mapDefinition.id,
		difficultyId = difficulty.id,
		configuration = configuration,
		runtimeMap = runtimeMapValue,
		difficulty = difficulty,
		schedule = scheduleValue,
		economyRule = economyRule,
		startingCash = table.freeze({
			configurationVersion = configuration.economy.version,
			difficultyId = difficulty.id,
			startingBattleCash = economyRule.startingBattleCash,
		}),
		dependencies = dependencies,
		relativeEventsByWave = relativeEventsByWave,
		origins = {},
		heap = {},
		pendingSpawnEntry = nil,
		ownership = {},
		processedTerminalCount = 0,
		currentWaveNumber = 0,
		totalWaves = difficulty.waveCount,
		waveRevision = 0,
		lastPassOrdinal = 0,
		lastServerTime = 0,
		intermissionEndsServerTime = 0,
		skipAvailableServerTime = 0,
		finiteCompleteServerTime = 0,
		skipAvailable = false,
		activeUserIds = {},
		voterUserIds = {},
		castUserIds = {},
		lastLifecycleRevision = 0,
		lastLifecycleState = nil,
		lastLifecycleParticipantStates = {},
		lastLifecycleParticipantReady = {},
		activeParticipantCount = 0,
		yesVoteCount = 0,
		requiredVoteCount = 0,
		quorumPending = false,
		deadlineConsumed = false,
		aggregateCounts = zeroCounts(),
		busy = false,
		reentryViolation = false,
		cleanupRequested = false,
		faultCode = nil,
		faultCloseCount = 0,
		faultCloseCommittedSpawn = nil,
		faultCloseTerminalOutcome = nil,
		completionCount = 0,
	}
	return Result.ok(runtime)
end

return table.freeze(WaveRuntime)
