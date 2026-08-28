--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local WaveProtocol = require(ReplicatedStorage.Shared.match.WaveProtocol)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Operation = "new" | "preflightPublication" | "queueSnapshot" | "flush" | "getMetrics" | "cleanup"

export type ErrorCode =
	"INVALID_ARGUMENT"
	| "INVALID_SNAPSHOT"
	| "WRONG_IDENTITY"
	| "INVALID_REVISION"
	| "INVALID_PASS"
	| "CAPACITY_EXCEEDED"
	| "REENTRANT"
	| "FAULTED"
	| "CLEANED"
	| "INTERNAL_ERROR"

export type PublisherError = {
	code: ErrorCode,
	operation: Operation,
}

export type RecipientRecord = {
	recipient: Player,
	userId: number,
}

export type Sender = (recipient: Player, snapshot: WaveProtocol.WaveSnapshot) -> boolean
export type GetRecipients = () -> unknown

export type Dependencies = {
	sender: Sender,
	getRecipients: GetRecipients,
}

export type FlushOutcome = {
	published: boolean,
	passOrdinal: number,
	waveRevision: number?,
	recipientCount: number,
	senderFailureCount: number,
}

export type Metrics = {
	publicationCount: number,
	flushCount: number,
	queueCount: number,
	coalescedQueueCount: number,
	duplicateQueueCount: number,
	senderCallCount: number,
	senderFailureCount: number,
	hasPending: boolean,
	latestWaveRevision: number?,
	lastPassOrdinal: number?,
	retainsSender: boolean,
	retainsRecipientProvider: boolean,
	retainsTestRecipientValidator: boolean,
	faulted: boolean,
	cleaned: boolean,
}

type TestRecipientValidator = (recipient: unknown, userId: number) -> boolean

type TestOptions = {
	maxPublications: number?,
	recipientValidator: TestRecipientValidator?,
}

type InternalRecipientRecord = {
	recipient: unknown,
	userId: number,
}

type PublisherData = {
	matchId: Ids.MatchId?,
	enemyEpoch: number,
	mapId: Ids.MapId?,
	difficultyId: Ids.DifficultyId?,
	totalWaves: number,
	sender: ((unknown, WaveProtocol.WaveSnapshot) -> boolean)?,
	getRecipients: GetRecipients?,
	testRecipientValidator: TestRecipientValidator?,
	maxPublications: number,
	pending: WaveProtocol.WaveSnapshot?,
	latestSnapshot: WaveProtocol.WaveSnapshot?,
	publicationCount: number,
	flushCount: number,
	queueCount: number,
	coalescedQueueCount: number,
	duplicateQueueCount: number,
	senderCallCount: number,
	senderFailureCount: number,
	lastPassOrdinal: number?,
	busy: boolean,
	cleanupRequested: boolean,
	faulted: boolean,
	cleaned: boolean,
}

local PublisherMethods = {}
PublisherMethods.__index = PublisherMethods

export type Publisher = typeof(setmetatable({} :: {}, PublisherMethods))
export type TestConstructor = (
	matchId: unknown,
	enemyEpoch: unknown,
	mapId: unknown,
	difficultyId: unknown,
	totalWaves: unknown,
	dependencies: unknown,
	options: TestOptions?
) -> Result.Result<Publisher, PublisherError>

local MAX_PUBLICATIONS = 16_384

local DEPENDENCY_FIELDS: { [string]: boolean } = table.freeze({
	sender = true,
	getRecipients = true,
})

local RECIPIENT_FIELDS: { [string]: boolean } = table.freeze({
	recipient = true,
	userId = true,
})

local TEST_OPTION_FIELDS: { [string]: boolean } = table.freeze({
	maxPublications = true,
	recipientValidator = true,
})

local PUBLISHER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: PublisherData }

local WaveReplicationPublisher = {
	MAX_BROADCAST_RECIPIENTS = WaveProtocol.MAX_BROADCAST_RECIPIENTS,
	MAX_PUBLICATIONS = MAX_PUBLICATIONS,
	newForTests = nil :: TestConstructor?,
}

local function makeError(code: ErrorCode, operation: Operation): PublisherError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<PublisherError>
	return Result.err(makeError(code, operation))
end

local function requireData(value: unknown): PublisherData
	if type(value) ~= "table" then
		error("[ATD_WAVE_REPLICATION_PUBLISHER][code=INVALID_CONTEXT]", 0)
	end
	local data = PUBLISHER_DATA[value :: any]
	if data == nil then
		error("[ATD_WAVE_REPLICATION_PUBLISHER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function hasExactFields(value: { [any]: unknown }, fields: { [string]: boolean }): boolean
	local actualCount = 0
	for fieldName in next, value do
		actualCount += 1
		if type(fieldName) ~= "string" or fields[fieldName] ~= true then
			return false
		end
	end
	local expectedCount = 0
	for _ in fields do
		expectedCount += 1
	end
	return actualCount == expectedCount
end

local function isSafePositiveInteger(value: unknown, maximum: number): boolean
	return type(value) == "number"
		and Validation.isSafeInteger(value :: number)
		and (value :: number) >= 1
		and (value :: number) <= maximum
end

local function isUserId(value: unknown): boolean
	return type(value) == "number" and value ~= 0 and Validation.isSafeInteger(value :: number)
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, any)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function validateLive(data: PublisherData, operation: Operation): PublisherError?
	if data.cleaned then
		return makeError("CLEANED", operation)
	end
	if data.busy then
		return makeError("REENTRANT", operation)
	end
	if data.faulted then
		return makeError("FAULTED", operation)
	end
	return nil
end

local function countsEqual(left: WaveProtocol.WaveCounts, right: WaveProtocol.WaveCounts): boolean
	return left.totalScheduled == right.totalScheduled
		and left.pending == right.pending
		and left.spawned == right.spawned
		and left.alive == right.alive
		and left.leaked == right.leaked
		and left.otherwiseResolved == right.otherwiseResolved
end

local function skipStatesEqual(left: WaveProtocol.SkipState, right: WaveProtocol.SkipState): boolean
	return left.available == right.available
		and left.activeParticipantCount == right.activeParticipantCount
		and left.yesVoteCount == right.yesVoteCount
		and left.requiredVoteCount == right.requiredVoteCount
		and left.quorumPending == right.quorumPending
end

local function snapshotsEqual(left: WaveProtocol.WaveSnapshot, right: WaveProtocol.WaveSnapshot): boolean
	return left.matchId == right.matchId
		and left.enemyEpoch == right.enemyEpoch
		and left.mapId == right.mapId
		and left.difficultyId == right.difficultyId
		and left.state == right.state
		and left.waveRevision == right.waveRevision
		and left.currentWaveNumber == right.currentWaveNumber
		and left.totalWaves == right.totalWaves
		and left.currentWaveId == right.currentWaveId
		and left.bossKind == right.bossKind
		and left.timerPhase == right.timerPhase
		and left.waveStartedServerTime == right.waveStartedServerTime
		and left.deadlineServerTime == right.deadlineServerTime
		and left.intermissionEndsServerTime == right.intermissionEndsServerTime
		and left.skipAvailableServerTime == right.skipAvailableServerTime
		and left.finiteCompleteServerTime == right.finiteCompleteServerTime
		and countsEqual(left.currentCounts, right.currentCounts)
		and countsEqual(left.aggregateCounts, right.aggregateCounts)
		and skipStatesEqual(left.skipState, right.skipState)
end

local function failClosed(data: PublisherData)
	data.faulted = true
	data.pending = nil
end

local function fault<T>(data: PublisherData, code: ErrorCode, operation: Operation): Result.Failure<PublisherError>
	failClosed(data)
	return failure(code, operation)
end

local function preflightInternal(data: PublisherData, operation: Operation): PublisherError?
	if data.publicationCount >= data.maxPublications then
		failClosed(data)
		return makeError("CAPACITY_EXCEEDED", operation)
	end
	return nil
end

local function validateSnapshotIdentity(data: PublisherData, snapshot: WaveProtocol.WaveSnapshot): boolean
	return snapshot.matchId == data.matchId
		and snapshot.enemyEpoch == data.enemyEpoch
		and snapshot.mapId == data.mapId
		and snapshot.difficultyId == data.difficultyId
		and snapshot.totalWaves == data.totalWaves
end

local function queueSnapshotInternal(
	data: PublisherData,
	snapshotValue: unknown,
	operation: Operation
): Result.Result<boolean, PublisherError>
	local snapshotResult = WaveProtocol.validateWaveSnapshot(snapshotValue)
	if not snapshotResult.ok then
		return fault(data, "INVALID_SNAPSHOT", operation)
	end
	local snapshot = snapshotResult.value
	if not validateSnapshotIdentity(data, snapshot) then
		return fault(data, "WRONG_IDENTITY", operation)
	end

	local previous = data.latestSnapshot
	if previous == nil then
		if snapshot.waveRevision ~= 1 then
			return fault(data, "INVALID_REVISION", operation)
		end
	elseif snapshot.waveRevision < previous.waveRevision then
		return fault(data, "INVALID_REVISION", operation)
	elseif snapshot.waveRevision == previous.waveRevision then
		if not snapshotsEqual(previous, snapshot) then
			return fault(data, "INVALID_REVISION", operation)
		end
		data.duplicateQueueCount += 1
		return Result.ok(false)
	end

	local capacityError = preflightInternal(data, operation)
	if capacityError ~= nil then
		return Result.err(capacityError)
	end
	if data.pending ~= nil then
		data.coalescedQueueCount += 1
	end
	data.pending = snapshot
	data.latestSnapshot = snapshot
	data.queueCount += 1
	return Result.ok(true)
end

local function productionRecipientIsLive(recipient: unknown, userId: number): boolean
	if typeof(recipient) ~= "Instance" or not (recipient :: Instance):IsA("Player") then
		return false
	end
	local player = recipient :: Player
	return player.Parent == Players and player.UserId == userId
end

local function recipientIsLive(data: PublisherData, recipient: unknown, userId: number): boolean
	local validator = data.testRecipientValidator
	if validator == nil then
		return productionRecipientIsLive(recipient, userId)
	end
	local called, accepted = callNonYielding(validator, recipient, userId)
	return called and accepted == true
end

local function readRecipients(data: PublisherData): { InternalRecipientRecord }?
	local provider = data.getRecipients
	if provider == nil then
		return nil
	end
	local called, value = callNonYielding(provider)
	if not called or type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local length = #value
	if length > WaveProtocol.MAX_BROADCAST_RECIPIENTS then
		return nil
	end
	local keyCount = 0
	for key in next, value :: any do
		keyCount += 1
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 or key > length then
			return nil
		end
	end
	if keyCount ~= length then
		return nil
	end

	local recipients: { InternalRecipientRecord } = table.create(length)
	for index = 1, length do
		local record = rawget(value :: any, index)
		if
			type(record) ~= "table"
			or getmetatable(record) ~= nil
			or not hasExactFields(record, RECIPIENT_FIELDS)
			or not isUserId(record.userId)
			or not recipientIsLive(data, record.recipient, record.userId)
		then
			return nil
		end
		for previousIndex = 1, index - 1 do
			local previous = recipients[previousIndex]
			if previous.recipient == record.recipient or previous.userId == record.userId then
				return nil
			end
		end
		recipients[index] = {
			recipient = record.recipient,
			userId = record.userId,
		}
	end
	table.sort(recipients, function(left: InternalRecipientRecord, right: InternalRecipientRecord): boolean
		return left.userId < right.userId
	end)
	return recipients
end

local function flushInternal(
	data: PublisherData,
	passOrdinal: number,
	operation: Operation
): Result.Result<FlushOutcome, PublisherError>
	if data.lastPassOrdinal ~= nil and passOrdinal ~= (data.lastPassOrdinal :: number) + 1 then
		return fault(data, "INVALID_PASS", operation)
	end
	data.lastPassOrdinal = passOrdinal
	data.flushCount += 1

	local pending = data.pending
	if pending == nil then
		return Result.ok(table.freeze({
			published = false,
			passOrdinal = passOrdinal,
			waveRevision = nil,
			recipientCount = 0,
			senderFailureCount = 0,
		}))
	end
	local capacityError = preflightInternal(data, operation)
	if capacityError ~= nil then
		return Result.err(capacityError)
	end
	local wireResult = WaveProtocol.validateWaveSnapshot(pending)
	if not wireResult.ok or not snapshotsEqual(pending, wireResult.value) then
		return fault(data, "INTERNAL_ERROR", operation)
	end
	local recipients = readRecipients(data)
	if recipients == nil then
		return fault(data, "INTERNAL_ERROR", operation)
	end
	if data.cleanupRequested then
		table.clear(recipients)
		return failure("CLEANED", operation)
	end
	local sender = data.sender
	if sender == nil then
		table.clear(recipients)
		return fault(data, "INTERNAL_ERROR", operation)
	end

	local snapshot = wireResult.value
	data.pending = nil
	data.publicationCount += 1
	local failureStart = data.senderFailureCount
	local recipientCount = #recipients
	for _, record in recipients do
		if data.cleanupRequested then
			break
		end
		data.senderCallCount += 1
		local called, sent = callNonYielding(sender, record.recipient, snapshot)
		if not called or sent ~= true then
			data.senderFailureCount += 1
		end
	end
	table.clear(recipients)
	if data.cleanupRequested then
		return failure("CLEANED", operation)
	end
	return Result.ok(table.freeze({
		published = true,
		passOrdinal = passOrdinal,
		waveRevision = snapshot.waveRevision,
		recipientCount = recipientCount,
		senderFailureCount = data.senderFailureCount - failureStart,
	}))
end

local function clearData(data: PublisherData)
	data.matchId = nil
	data.enemyEpoch = 0
	data.mapId = nil
	data.difficultyId = nil
	data.totalWaves = 0
	data.sender = nil
	data.getRecipients = nil
	data.testRecipientValidator = nil
	data.maxPublications = 0
	data.pending = nil
	data.latestSnapshot = nil
	data.publicationCount = 0
	data.flushCount = 0
	data.queueCount = 0
	data.coalescedQueueCount = 0
	data.duplicateQueueCount = 0
	data.senderCallCount = 0
	data.senderFailureCount = 0
	data.lastPassOrdinal = nil
	data.busy = false
	data.cleanupRequested = false
	data.faulted = false
	data.cleaned = true
end

local function finishMutation(data: PublisherData)
	data.busy = false
	if data.cleanupRequested then
		clearData(data)
	end
end

function PublisherMethods.preflightPublication(self: Publisher): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "preflightPublication")
	if liveError ~= nil then
		return Result.err(liveError)
	end
	local capacityError = preflightInternal(data, "preflightPublication")
	if capacityError ~= nil then
		return Result.err(capacityError)
	end
	return Result.ok(true)
end

function PublisherMethods.queueSnapshot(self: Publisher, snapshotValue: unknown): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "queueSnapshot")
	if liveError ~= nil then
		return Result.err(liveError)
	end
	data.busy = true
	local outcome = queueSnapshotInternal(data, snapshotValue, "queueSnapshot")
	finishMutation(data)
	return outcome
end

function PublisherMethods.flush(self: Publisher, passOrdinalValue: unknown): Result.Result<FlushOutcome, PublisherError>
	local data = requireData(self)
	local liveError = validateLive(data, "flush")
	if liveError ~= nil then
		return Result.err(liveError)
	end
	if not isSafePositiveInteger(passOrdinalValue, Validation.MAX_SAFE_INTEGER) then
		failClosed(data)
		return failure("INVALID_PASS", "flush")
	end
	data.busy = true
	local outcome = flushInternal(data, passOrdinalValue :: number, "flush")
	finishMutation(data)
	return outcome
end

function PublisherMethods.getMetrics(self: Publisher): Metrics
	local data = requireData(self)
	local latest = data.latestSnapshot
	return table.freeze({
		publicationCount = data.publicationCount,
		flushCount = data.flushCount,
		queueCount = data.queueCount,
		coalescedQueueCount = data.coalescedQueueCount,
		duplicateQueueCount = data.duplicateQueueCount,
		senderCallCount = data.senderCallCount,
		senderFailureCount = data.senderFailureCount,
		hasPending = data.pending ~= nil,
		latestWaveRevision = if latest == nil then nil else latest.waveRevision,
		lastPassOrdinal = data.lastPassOrdinal,
		retainsSender = data.sender ~= nil,
		retainsRecipientProvider = data.getRecipients ~= nil,
		retainsTestRecipientValidator = data.testRecipientValidator ~= nil,
		faulted = data.faulted,
		cleaned = data.cleaned,
	})
end

function PublisherMethods.cleanup(self: Publisher): Result.Result<boolean, PublisherError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	if data.busy then
		data.cleanupRequested = true
		return Result.ok(false)
	end
	clearData(data)
	return Result.ok(true)
end

local function validateTestOptions(optionsValue: TestOptions?): (number?, TestRecipientValidator?, boolean)
	if optionsValue == nil then
		return MAX_PUBLICATIONS, nil, true
	end
	if
		type(optionsValue) ~= "table"
		or getmetatable(optionsValue :: any) ~= nil
		or not hasExactFields(optionsValue :: { [any]: unknown }, TEST_OPTION_FIELDS)
	then
		return nil, nil, false
	end
	local maxPublications = optionsValue.maxPublications
	if maxPublications == nil then
		maxPublications = MAX_PUBLICATIONS
	end
	if not isSafePositiveInteger(maxPublications, MAX_PUBLICATIONS) then
		return nil, nil, false
	end
	local recipientValidator = optionsValue.recipientValidator
	if recipientValidator ~= nil and type(recipientValidator) ~= "function" then
		return nil, nil, false
	end
	return maxPublications :: number, recipientValidator, true
end

local function construct(
	matchIdValue: unknown,
	enemyEpochValue: unknown,
	mapIdValue: unknown,
	difficultyIdValue: unknown,
	totalWavesValue: unknown,
	dependenciesValue: unknown,
	testOptions: TestOptions?
): Result.Result<Publisher, PublisherError>
	local matchIdResult = Ids.validateMatchId(matchIdValue)
	local mapIdResult = Ids.validateMapId(mapIdValue)
	local difficultyIdResult = Ids.validateDifficultyId(difficultyIdValue)
	if
		not matchIdResult.ok
		or not mapIdResult.ok
		or not difficultyIdResult.ok
		or not isSafePositiveInteger(enemyEpochValue, WaveProtocol.MAX_ENEMY_EPOCH)
		or not isSafePositiveInteger(totalWavesValue, WaveProtocol.MAX_TOTAL_WAVES)
	then
		return failure("INVALID_ARGUMENT", "new")
	end
	if
		type(dependenciesValue) ~= "table"
		or getmetatable(dependenciesValue :: any) ~= nil
		or not hasExactFields(dependenciesValue :: { [any]: unknown }, DEPENDENCY_FIELDS)
	then
		return failure("INVALID_ARGUMENT", "new")
	end
	local dependencies = dependenciesValue :: any
	if type(dependencies.sender) ~= "function" or type(dependencies.getRecipients) ~= "function" then
		return failure("INVALID_ARGUMENT", "new")
	end
	local maxPublications, recipientValidator, validOptions = validateTestOptions(testOptions)
	if not validOptions or maxPublications == nil then
		return failure("INVALID_ARGUMENT", "new")
	end

	local publisher = setmetatable({}, PublisherMethods) :: Publisher
	table.freeze(publisher)
	PUBLISHER_DATA[publisher] = {
		matchId = matchIdResult.value,
		enemyEpoch = enemyEpochValue :: number,
		mapId = mapIdResult.value,
		difficultyId = difficultyIdResult.value,
		totalWaves = totalWavesValue :: number,
		sender = dependencies.sender,
		getRecipients = dependencies.getRecipients,
		testRecipientValidator = recipientValidator,
		maxPublications = maxPublications,
		pending = nil,
		latestSnapshot = nil,
		publicationCount = 0,
		flushCount = 0,
		queueCount = 0,
		coalescedQueueCount = 0,
		duplicateQueueCount = 0,
		senderCallCount = 0,
		senderFailureCount = 0,
		lastPassOrdinal = nil,
		busy = false,
		cleanupRequested = false,
		faulted = false,
		cleaned = false,
	}
	return Result.ok(publisher)
end

function WaveReplicationPublisher.new(
	matchId: unknown,
	enemyEpoch: unknown,
	mapId: unknown,
	difficultyId: unknown,
	totalWaves: unknown,
	dependencies: unknown
): Result.Result<Publisher, PublisherError>
	return construct(matchId, enemyEpoch, mapId, difficultyId, totalWaves, dependencies, nil)
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "WaveReplicationPublisher" then
		return false
	end
	local productionServerWaves = script.Parent
	if
		productionServerWaves == nil
		or not productionServerWaves:IsA("Folder")
		or productionServerWaves.Name ~= "ProductionServerWaves"
	then
		return false
	end
	local automatedTests = productionServerWaves.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	return automatedTests.Parent == ServerStorage and ServerScriptService:FindFirstChild("Server") == nil
end

if testModuleIdentityIsExact() then
	WaveReplicationPublisher.newForTests = function(
		matchId: unknown,
		enemyEpoch: unknown,
		mapId: unknown,
		difficultyId: unknown,
		totalWaves: unknown,
		dependencies: unknown,
		options: TestOptions?
	): Result.Result<Publisher, PublisherError>
		return construct(matchId, enemyEpoch, mapId, difficultyId, totalWaves, dependencies, options)
	end
end

table.freeze(PublisherMethods)
return table.freeze(WaveReplicationPublisher)
