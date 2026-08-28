--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type WaveState = "Running" | "Intermission" | "FiniteComplete" | "DefeatClosed" | "Faulted"
export type TimerPhase = "WaveDeadline" | "EarlyClearIntermission" | "PostDeadline" | "None"
export type BossKind = "None" | "MiniBoss" | "Boss"

export type GetWaveSnapshotPayload = {}

export type SubmitSkipVotePayload = {
	matchId: Ids.MatchId,
	waveNumber: number,
}

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
	state: WaveState,
	waveRevision: number,
	currentWaveNumber: number,
	totalWaves: number,
	currentWaveId: Ids.WaveId,
	bossKind: BossKind,
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

local GET_WAVE_SNAPSHOT_ENDPOINT = "GetWaveSnapshot"
local SUBMIT_SKIP_VOTE_ENDPOINT = "SubmitSkipVote"
local WAVE_REPLICATION_ENDPOINT = "WaveReplication"

local MAX_ENEMY_EPOCH = 4_096
local MAX_TOTAL_WAVES = 1_000
local MAX_TOTAL_SCHEDULED = 4_096
local MAX_ACTIVE_PARTICIPANTS = 4
local MAX_BROADCAST_RECIPIENTS = 4
local MAX_WAVE_REVISION = Validation.MAX_SAFE_INTEGER
local MAX_FINITE_NUMBER = 1.7976931348623157e308

local NONNEGATIVE_TIMESTAMP_VALIDATOR = PayloadValidation.number(0, MAX_FINITE_NUMBER)
local BOUNDED_COUNT_VALIDATOR = PayloadValidation.integer(0, MAX_TOTAL_SCHEDULED)
local WAVE_NUMBER_VALIDATOR = PayloadValidation.integer(1, MAX_TOTAL_WAVES)

local WAVE_COUNTS_VALIDATOR = PayloadValidation.record({
	totalScheduled = BOUNDED_COUNT_VALIDATOR,
	pending = BOUNDED_COUNT_VALIDATOR,
	spawned = BOUNDED_COUNT_VALIDATOR,
	alive = BOUNDED_COUNT_VALIDATOR,
	leaked = BOUNDED_COUNT_VALIDATOR,
	otherwiseResolved = BOUNDED_COUNT_VALIDATOR,
})

local SKIP_STATE_VALIDATOR = PayloadValidation.record({
	available = PayloadValidation.boolean(),
	activeParticipantCount = PayloadValidation.integer(0, MAX_ACTIVE_PARTICIPANTS),
	yesVoteCount = PayloadValidation.integer(0, MAX_ACTIVE_PARTICIPANTS),
	requiredVoteCount = PayloadValidation.integer(0, MAX_ACTIVE_PARTICIPANTS),
	quorumPending = PayloadValidation.boolean(),
})

local WAVE_SNAPSHOT_VALIDATOR = PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	enemyEpoch = PayloadValidation.integer(1, MAX_ENEMY_EPOCH),
	mapId = PayloadValidation.id("map"),
	difficultyId = PayloadValidation.id("difficulty"),
	state = PayloadValidation.enum({ "Running", "Intermission", "FiniteComplete", "DefeatClosed", "Faulted" }),
	waveRevision = PayloadValidation.integer(1, MAX_WAVE_REVISION),
	currentWaveNumber = WAVE_NUMBER_VALIDATOR,
	totalWaves = WAVE_NUMBER_VALIDATOR,
	currentWaveId = PayloadValidation.id("wave"),
	bossKind = PayloadValidation.enum({ "None", "MiniBoss", "Boss" }),
	timerPhase = PayloadValidation.enum({ "WaveDeadline", "EarlyClearIntermission", "PostDeadline", "None" }),
	waveStartedServerTime = NONNEGATIVE_TIMESTAMP_VALIDATOR,
	deadlineServerTime = NONNEGATIVE_TIMESTAMP_VALIDATOR,
	intermissionEndsServerTime = NONNEGATIVE_TIMESTAMP_VALIDATOR,
	skipAvailableServerTime = NONNEGATIVE_TIMESTAMP_VALIDATOR,
	finiteCompleteServerTime = NONNEGATIVE_TIMESTAMP_VALIDATOR,
	currentCounts = WAVE_COUNTS_VALIDATOR,
	aggregateCounts = WAVE_COUNTS_VALIDATOR,
	skipState = SKIP_STATE_VALIDATOR,
})

local GetWaveSnapshotPayloadSchema = PayloadValidation.schema(PayloadValidation.record({}))
local SubmitSkipVotePayloadSchema = PayloadValidation.schema(PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	waveNumber = WAVE_NUMBER_VALIDATOR,
}))
local WaveSnapshotSchema = PayloadValidation.schema(WAVE_SNAPSHOT_VALIDATOR)

local function issue(
	code: Validation.Code,
	path: { Validation.PathSegment },
	message: string
): Result.Failure<Validation.Issue>
	return Result.err(Validation.issue(code, path, message))
end

local function fieldPath(prefix: { Validation.PathSegment }, fieldName: string): { Validation.PathSegment }
	return Validation.appendPath(prefix, fieldName)
end

local function validateCounts(counts: WaveCounts, prefix: { Validation.PathSegment }): Result.Failure<Validation.Issue>?
	if counts.pending ~= counts.totalScheduled - counts.spawned then
		return issue(
			"INVALID_TOTAL",
			fieldPath(prefix, "pending"),
			"Pending count must equal total scheduled minus spawned"
		)
	end
	if counts.leaked > counts.spawned or counts.otherwiseResolved > counts.spawned then
		return issue("INVALID_TOTAL", fieldPath(prefix, "alive"), "Resolved counts must fit within the spawned count")
	end
	if counts.alive ~= counts.spawned - counts.leaked - counts.otherwiseResolved then
		return issue(
			"INVALID_TOTAL",
			fieldPath(prefix, "alive"),
			"Alive count must equal spawned minus every terminal count"
		)
	end
	return nil
end

local function validateAggregateContainsCurrent(
	currentCounts: WaveCounts,
	aggregateCounts: WaveCounts
): Result.Failure<Validation.Issue>?
	for _, fieldName in
		{
			"totalScheduled",
			"pending",
			"spawned",
			"alive",
			"leaked",
			"otherwiseResolved",
		}
	do
		if (currentCounts :: any)[fieldName] > (aggregateCounts :: any)[fieldName] then
			return issue(
				"INVALID_TOTAL",
				{ "payload", "aggregateCounts", fieldName },
				"Aggregate count must include the current originating wave"
			)
		end
	end
	return nil
end

local function validateTimerSemantics(snapshot: WaveSnapshot): Result.Failure<Validation.Issue>?
	if snapshot.deadlineServerTime <= snapshot.waveStartedServerTime then
		return issue(
			"INVALID_ORDER",
			{ "payload", "deadlineServerTime" },
			"Wave deadline must be strictly later than the authoritative wave start"
		)
	end

	if snapshot.state == "Running" then
		if snapshot.timerPhase ~= "WaveDeadline" and snapshot.timerPhase ~= "PostDeadline" then
			return issue(
				"INVALID_REFERENCE",
				{ "payload", "timerPhase" },
				"Running state requires a running timer phase"
			)
		end
	elseif snapshot.state == "Intermission" then
		if snapshot.timerPhase ~= "EarlyClearIntermission" then
			return issue(
				"INVALID_REFERENCE",
				{ "payload", "timerPhase" },
				"Intermission state requires the early-clear intermission timer phase"
			)
		end
	elseif snapshot.timerPhase ~= "None" then
		return issue(
			"INVALID_REFERENCE",
			{ "payload", "timerPhase" },
			"Terminal Wave states require the None timer phase"
		)
	end

	if snapshot.timerPhase == "PostDeadline" and snapshot.currentWaveNumber ~= snapshot.totalWaves then
		return issue(
			"INVALID_REFERENCE",
			{ "payload", "timerPhase" },
			"PostDeadline is valid only for the final authored wave"
		)
	end
	if snapshot.state == "Intermission" and snapshot.currentWaveNumber >= snapshot.totalWaves then
		return issue("INVALID_REFERENCE", { "payload", "state" }, "The final authored wave cannot enter intermission")
	end

	if snapshot.state == "Intermission" then
		if snapshot.intermissionEndsServerTime < snapshot.waveStartedServerTime then
			return issue(
				"INVALID_ORDER",
				{ "payload", "intermissionEndsServerTime" },
				"Intermission end must not precede the current wave start"
			)
		end
	elseif snapshot.intermissionEndsServerTime ~= 0 then
		return issue(
			"INVALID_REFERENCE",
			{ "payload", "intermissionEndsServerTime" },
			"Intermission end must be zero outside intermission"
		)
	end

	local skipTimestampApplies = snapshot.state == "Running"
		and snapshot.timerPhase == "WaveDeadline"
		and snapshot.currentWaveNumber < snapshot.totalWaves
	if skipTimestampApplies then
		if snapshot.skipAvailableServerTime < snapshot.waveStartedServerTime then
			return issue(
				"INVALID_ORDER",
				{ "payload", "skipAvailableServerTime" },
				"Skip availability must not precede the current wave start"
			)
		end
	elseif snapshot.skipAvailableServerTime ~= 0 then
		return issue(
			"INVALID_REFERENCE",
			{ "payload", "skipAvailableServerTime" },
			"Skip availability must be zero outside a non-final running wave"
		)
	end

	if snapshot.state == "FiniteComplete" then
		if snapshot.currentWaveNumber ~= snapshot.totalWaves then
			return issue(
				"INVALID_REFERENCE",
				{ "payload", "state" },
				"Finite completion requires the final authored wave"
			)
		end
		if snapshot.finiteCompleteServerTime < snapshot.waveStartedServerTime then
			return issue(
				"INVALID_ORDER",
				{ "payload", "finiteCompleteServerTime" },
				"Finite completion must not precede the final wave start"
			)
		end
	elseif snapshot.finiteCompleteServerTime ~= 0 then
		return issue(
			"INVALID_REFERENCE",
			{ "payload", "finiteCompleteServerTime" },
			"Finite-completion time must be zero before finite completion"
		)
	end
	return nil
end

local function validateSkipSemantics(snapshot: WaveSnapshot): Result.Failure<Validation.Issue>?
	local skipState = snapshot.skipState
	if skipState.yesVoteCount > skipState.activeParticipantCount then
		return issue(
			"INVALID_TOTAL",
			{ "payload", "skipState", "yesVoteCount" },
			"Yes votes cannot exceed current Active participants"
		)
	end

	local expectedRequired = if skipState.activeParticipantCount == 0
		then 0
		else math.floor(skipState.activeParticipantCount / 2) + 1
	if skipState.requiredVoteCount ~= expectedRequired then
		return issue(
			"INVALID_TOTAL",
			{ "payload", "skipState", "requiredVoteCount" },
			"Required votes must equal the strict majority of Active participants"
		)
	end

	local eligiblePhase = snapshot.state == "Running"
		and snapshot.timerPhase == "WaveDeadline"
		and snapshot.currentWaveNumber < snapshot.totalWaves
	if skipState.available and not eligiblePhase then
		return issue(
			"INVALID_REFERENCE",
			{ "payload", "skipState", "available" },
			"Skip voting is available only during a non-final running wave"
		)
	end
	if skipState.available and snapshot.skipAvailableServerTime >= snapshot.deadlineServerTime then
		return issue(
			"INVALID_ORDER",
			{ "payload", "skipAvailableServerTime" },
			"An available skip window must begin strictly before the wave deadline"
		)
	end
	if skipState.quorumPending then
		if not skipState.available or expectedRequired == 0 or skipState.yesVoteCount < expectedRequired then
			return issue(
				"INVALID_REFERENCE",
				{ "payload", "skipState", "quorumPending" },
				"A pending quorum requires an available window and a strict majority"
			)
		end
	end
	return nil
end

local function validateSnapshotSemantics(snapshot: WaveSnapshot): Result.Failure<Validation.Issue>?
	if snapshot.currentWaveNumber > snapshot.totalWaves then
		return issue(
			"INVALID_TOTAL",
			{ "payload", "currentWaveNumber" },
			"Current wave number must fit within the finite authored schedule"
		)
	end

	local currentFailure = validateCounts(snapshot.currentCounts, { "payload", "currentCounts" })
	if currentFailure ~= nil then
		return currentFailure
	end
	local aggregateFailure = validateCounts(snapshot.aggregateCounts, { "payload", "aggregateCounts" })
	if aggregateFailure ~= nil then
		return aggregateFailure
	end
	local containmentFailure = validateAggregateContainsCurrent(snapshot.currentCounts, snapshot.aggregateCounts)
	if containmentFailure ~= nil then
		return containmentFailure
	end

	if
		(snapshot.state == "Intermission" or snapshot.state == "FiniteComplete")
		and (snapshot.aggregateCounts.pending ~= 0 or snapshot.aggregateCounts.alive ~= 0)
	then
		return issue(
			"INVALID_REFERENCE",
			{ "payload", "aggregateCounts" },
			"Intermission and finite completion require global pending and alive counts to be zero"
		)
	end

	local timerFailure = validateTimerSemantics(snapshot)
	if timerFailure ~= nil then
		return timerFailure
	end
	return validateSkipSemantics(snapshot)
end

local function canonicalCounts(counts: WaveCounts): WaveCounts
	return table.freeze({
		totalScheduled = counts.totalScheduled,
		pending = counts.pending,
		spawned = counts.spawned,
		alive = counts.alive,
		leaked = counts.leaked,
		otherwiseResolved = counts.otherwiseResolved,
	})
end

local function canonicalSkipState(skipState: SkipState): SkipState
	return table.freeze({
		available = skipState.available,
		activeParticipantCount = skipState.activeParticipantCount,
		yesVoteCount = skipState.yesVoteCount,
		requiredVoteCount = skipState.requiredVoteCount,
		quorumPending = skipState.quorumPending,
	})
end

local function canonicalSnapshot(snapshot: WaveSnapshot): WaveSnapshot
	return table.freeze({
		matchId = snapshot.matchId,
		enemyEpoch = snapshot.enemyEpoch,
		mapId = snapshot.mapId,
		difficultyId = snapshot.difficultyId,
		state = snapshot.state,
		waveRevision = snapshot.waveRevision,
		currentWaveNumber = snapshot.currentWaveNumber,
		totalWaves = snapshot.totalWaves,
		currentWaveId = snapshot.currentWaveId,
		bossKind = snapshot.bossKind,
		timerPhase = snapshot.timerPhase,
		waveStartedServerTime = snapshot.waveStartedServerTime,
		deadlineServerTime = snapshot.deadlineServerTime,
		intermissionEndsServerTime = snapshot.intermissionEndsServerTime,
		skipAvailableServerTime = snapshot.skipAvailableServerTime,
		finiteCompleteServerTime = snapshot.finiteCompleteServerTime,
		currentCounts = canonicalCounts(snapshot.currentCounts),
		aggregateCounts = canonicalCounts(snapshot.aggregateCounts),
		skipState = canonicalSkipState(snapshot.skipState),
	})
end

local WaveProtocol = {
	GET_WAVE_SNAPSHOT_ENDPOINT = GET_WAVE_SNAPSHOT_ENDPOINT,
	SUBMIT_SKIP_VOTE_ENDPOINT = SUBMIT_SKIP_VOTE_ENDPOINT,
	WAVE_REPLICATION_ENDPOINT = WAVE_REPLICATION_ENDPOINT,
	MAX_ENEMY_EPOCH = MAX_ENEMY_EPOCH,
	MAX_TOTAL_WAVES = MAX_TOTAL_WAVES,
	MAX_TOTAL_SCHEDULED = MAX_TOTAL_SCHEDULED,
	MAX_ACTIVE_PARTICIPANTS = MAX_ACTIVE_PARTICIPANTS,
	MAX_BROADCAST_RECIPIENTS = MAX_BROADCAST_RECIPIENTS,
	MAX_WAVE_REVISION = MAX_WAVE_REVISION,
	GetWaveSnapshotPayloadSchema = GetWaveSnapshotPayloadSchema,
	SubmitSkipVotePayloadSchema = SubmitSkipVotePayloadSchema,
	WaveSnapshotSchema = WaveSnapshotSchema,
}

function WaveProtocol.validateWaveSnapshot(value: unknown): Result.Result<WaveSnapshot, Validation.Issue>
	local schemaResult = WaveSnapshotSchema:validate(value)
	if not schemaResult.ok then
		return Result.err(schemaResult.error)
	end

	local snapshot = schemaResult.value :: WaveSnapshot
	local semanticFailure = validateSnapshotSemantics(snapshot)
	if semanticFailure ~= nil then
		return semanticFailure
	end
	return Result.ok(canonicalSnapshot(snapshot))
end

return table.freeze(WaveProtocol)
