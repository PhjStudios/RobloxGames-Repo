--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local ContentSelection = require(ReplicatedStorage.Shared.config.ContentSelection)
local TutorialProtocol = require(ReplicatedStorage.Shared.profile.TutorialProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local ProfileSchema = require(script.Parent.ProfileSchema)

export type ProfileOwner = {
	getState: (self: ProfileOwner, userId: number) -> unknown,
	read: (self: ProfileOwner, userId: number) -> unknown,
	transact: (
		self: ProfileOwner,
		userId: number,
		transactionId: string,
		expectedRevision: number,
		kind: string,
		fingerprint: string,
		callback: (profile: any) -> unknown
	) -> unknown,
	queueImportantSave: (self: ProfileOwner, userId: number) -> unknown,
}

export type Dependencies = {
	clock: (() -> number)?,
}

export type ErrorCode =
	"INVALID_DEPENDENCIES"
	| "INVALID_USER_ID"
	| "INVALID_INTENT"
	| "INVALID_EVENT"
	| "NOT_READY"
	| "STARTER_UNAVAILABLE"
	| "PROFILE_INVALID"
	| "STALE_REVISION"
	| "TRANSACTION_CONFLICT"
	| "UNAVAILABLE"

export type ServiceError = {
	code: ErrorCode,
	operation: string,
}

export type Observation = {
	advanced: boolean,
	revision: number,
	tutorial: TutorialProtocol.View,
}

export type MatchArrival = {
	matchId: string,
	mapId: string,
	difficultyId: string,
	privacy: "Public" | "PartyOnly",
	expectedUserIds: { number },
	authenticatedParticipant: boolean,
	spectator: boolean,
}

export type ResultEvidence = {
	matchId: string,
	mapId: string,
	difficultyId: string,
	authenticatedParticipant: boolean,
	spectator: boolean,
	durable: boolean,
}

type ServiceData = {
	profileOwner: ProfileOwner,
	configuration: ConfigTypes.CoreConfiguration,
	clock: () -> number,
}

local RELEASE_MAP_ID = ContentSelection.RELEASE_MAP_ID
local EASY_DIFFICULTY_ID = ContentSelection.EASY_DIFFICULTY_ID
local MAX_SERVER_ATTEMPTS = 3

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local TutorialService = {
	RELEASE_MAP_ID = RELEASE_MAP_ID,
	EASY_DIFFICULTY_ID = EASY_DIFFICULTY_ID,
}

local function failure<T>(code: ErrorCode, operation: string): Result.Failure<ServiceError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_TUTORIAL_SERVICE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and value > 0 and Validation.isSafeInteger(value :: number)
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, unknown)
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

local function resultOk(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function ownerError(value: unknown): ErrorCode
	local code = if type(value) == "table" then rawget(value :: any, "code") else nil
	if code == "NOT_READY" or code == "SESSION_LOST" or code == "BUSY" then
		return "NOT_READY"
	elseif code == "STALE_REVISION" then
		return "STALE_REVISION"
	elseif code == "TRANSACTION_CONFLICT" then
		return "TRANSACTION_CONFLICT"
	end
	return "UNAVAILABLE"
end

local function tutorialView(profile: any): TutorialProtocol.View?
	local tutorial = rawget(profile, "tutorial")
	if type(tutorial) ~= "table" then
		return nil
	end
	local value = {
		version = rawget(tutorial, "version"),
		firstJoin = rawget(tutorial, "firstJoin"),
		tutorialCompleted = rawget(tutorial, "tutorialCompleted"),
		tutorialStep = rawget(tutorial, "tutorialStep"),
		attempt = rawget(tutorial, "attempt"),
		skipped = rawget(tutorial, "skipped"),
		trackedMatchId = if rawget(tutorial, "trackedMatchId") == "" then nil else rawget(tutorial, "trackedMatchId"),
	}
	local validated = TutorialProtocol.validateView(value)
	return if validated.ok then validated.value else nil
end

local function observation(profile: any, advanced: boolean): Result.Result<Observation, ServiceError>
	local view = tutorialView(profile)
	local revision = rawget(profile, "revision")
	if view == nil or type(revision) ~= "number" or not Validation.isSafeInteger(revision) or revision < 1 then
		return failure("PROFILE_INVALID", "observe")
	end
	return Result.ok(table.freeze({ advanced = advanced, revision = revision, tutorial = view }))
end

local function readProfile(data: ServiceData, userId: number, operation: string): Result.Result<any, ServiceError>
	local stateCalled, state = callNonYielding(data.profileOwner.getState, data.profileOwner, userId)
	if not stateCalled or state ~= "Ready" then
		return failure("NOT_READY", operation)
	end
	local called, read = callNonYielding(data.profileOwner.read, data.profileOwner, userId)
	if not called or not resultOk(read) then
		return failure("NOT_READY", operation)
	end
	return Result.ok((read :: any).value)
end

local function hashToken(value: string): string
	local hash = 2_166_136_261
	for index = 1, #value do
		hash = bit32.bxor(hash, string.byte(value, index))
		hash = (hash * 16_777_619) % 4_294_967_296
	end
	return string.format("%08x", hash)
end

local function serverTransactionId(operation: string, eventId: string, tutorialAttempt: number): string?
	-- Replayed tutorials may observe the same durable queue, Match, or return ID.
	-- Include the server-owned attempt in the hash so a receipt from an older
	-- journey cannot turn the new attempt's observation into a false replay.
	local eventNamespace = `attempt:{tutorialAttempt}|event:{eventId}`
	local created = Ids.makeTransactionId(`tutorial-{operation}-{hashToken(eventNamespace)}`)
	return if created.ok then created.value else nil
end

local function receiptResult(profile: any, changed: boolean): any
	return table.freeze({
		resultCode = if changed then "TUTORIAL_CHANGED" else "TUTORIAL_UNCHANGED",
		goldBalance = rawget(profile, "gold"),
		unitIds = table.freeze({}),
		towerIds = table.freeze({}),
		newFlags = table.freeze({}),
		pityCount = 0,
	})
end

local function mutationReceipt(
	transactionId: string,
	transaction: any
): Result.Result<TutorialProtocol.MutationReceipt, ServiceError>
	local ownerValue = if resultOk(transaction) then (transaction :: any).value else nil
	local profile = if type(ownerValue) == "table" then rawget(ownerValue, "profile") else nil
	local ownerResult = if type(ownerValue) == "table" then rawget(ownerValue, "result") else nil
	local revision = if type(ownerValue) == "table" then rawget(ownerValue, "profileRevision") else nil
	local view = if type(profile) == "table" then tutorialView(profile) else nil
	if
		view == nil
		or type(ownerResult) ~= "table"
		or (ownerResult.resultCode ~= "TUTORIAL_CHANGED" and ownerResult.resultCode ~= "TUTORIAL_UNCHANGED")
		or type(revision) ~= "number"
	then
		return failure("PROFILE_INVALID", "transact")
	end
	local receipt = {
		transactionId = transactionId,
		changed = ownerResult.resultCode == "TUTORIAL_CHANGED",
		revision = revision,
		tutorial = view,
	}
	local validated = TutorialProtocol.validateMutationReceipt(receipt)
	return if validated.ok then Result.ok(validated.value) else failure("PROFILE_INVALID", "transact")
end

local function transact(
	data: ServiceData,
	userId: number,
	transactionId: string,
	expectedRevision: number,
	operation: string,
	fingerprint: string,
	callback: (any) -> Result.Result<boolean, string>
): Result.Result<TutorialProtocol.MutationReceipt, ServiceError>
	local called, transaction = callNonYielding(
		data.profileOwner.transact,
		data.profileOwner,
		userId,
		transactionId,
		expectedRevision,
		"Tutorial",
		fingerprint,
		function(profile: any): unknown
			local changed = callback(profile)
			if not changed.ok then
				return Result.err(changed.error)
			end
			return Result.ok(receiptResult(profile, changed.value))
		end
	)
	if not called or type(transaction) ~= "table" then
		return failure("UNAVAILABLE", operation)
	end
	if not resultOk(transaction) then
		return failure(ownerError((transaction :: any).error), operation)
	end
	local receipt = mutationReceipt(transactionId, transaction)
	if receipt.ok and receipt.value.changed then
		pcall(data.profileOwner.queueImportantSave, data.profileOwner, userId)
	end
	return receipt
end

local function observeTransition(
	data: ServiceData,
	userId: number,
	operation: string,
	eventId: string,
	expectedStep: number,
	callback: (any) -> Result.Result<boolean, string>
): Result.Result<Observation, ServiceError>
	if #eventId < 1 or #eventId > 160 then
		return failure("INVALID_EVENT", operation)
	end
	for _attempt = 1, MAX_SERVER_ATTEMPTS do
		local read = readProfile(data, userId, operation)
		if not read.ok then
			return read
		end
		local view = tutorialView(read.value)
		if view == nil then
			return failure("PROFILE_INVALID", operation)
		end
		if view.tutorialStep ~= expectedStep or view.tutorialCompleted then
			return observation(read.value, false)
		end
		local transactionId = serverTransactionId(operation, eventId, view.attempt)
		if transactionId == nil then
			return failure("INVALID_EVENT", operation)
		end
		local changed = transact(
			data,
			userId,
			transactionId,
			read.value.revision,
			operation,
			`tutorial|{operation}|{view.attempt}|{expectedStep}|{hashToken(eventId)}`,
			callback
		)
		if changed.ok then
			return Result.ok(table.freeze({
				advanced = changed.value.changed,
				revision = changed.value.revision,
				tutorial = changed.value.tutorial,
			}))
		end
		if changed.error.code ~= "STALE_REVISION" then
			return changed
		end
	end
	return failure("STALE_REVISION", operation)
end

local function attacks(definition: ConfigTypes.TowerDefinition?): boolean
	if definition == nil then
		return false
	end
	for _, level in definition.levels do
		if level.attack ~= nil then
			return true
		end
	end
	return false
end

local function findTowerUnit(profile: any, towerId: string): string?
	local bestUnitId: string? = nil
	local bestSequence = math.huge
	for unitId, unit in profile.units do
		if unit.towerId == towerId and unit.acquisitionSequence < bestSequence then
			bestUnitId = unitId
			bestSequence = unit.acquisitionSequence
		end
	end
	return bestUnitId
end

local function nextSequence(profile: any): number
	local sequence = 0
	for _, unit in profile.units do
		sequence = math.max(sequence, unit.acquisitionSequence)
	end
	return sequence + 1
end

local function grantStarter(
	profile: any,
	towerId: string,
	preferredUnitId: string,
	fallbackUnitId: string,
	now: number
): string?
	local owned = findTowerUnit(profile, towerId)
	if owned ~= nil then
		return owned
	end
	local unitCount = 0
	for _ in profile.units do
		unitCount += 1
	end
	if unitCount >= ProfileSchema.MAX_UNITS then
		return nil
	end
	local unitId = if profile.units[preferredUnitId] == nil then preferredUnitId else fallbackUnitId
	if profile.units[unitId] ~= nil then
		return nil
	end
	local sequence = nextSequence(profile)
	if not Validation.isSafeInteger(sequence) then
		return nil
	end
	profile.units[unitId] = {
		unitId = unitId,
		towerId = towerId,
		favorite = false,
		locked = false,
		acquiredAt = now,
		acquisitionSequence = sequence,
	}
	profile.stats.towersAcquired += 1
	return unitId
end

local function unitCount(profile: any): number
	local count = 0
	for _ in profile.units do
		count += 1
	end
	return count
end

local function starterSlotsRequired(profile: any): number
	local required = 0
	if findTowerUnit(profile, ProfileSchema.DART_STARTER_TOWER_ID) == nil then
		required += 1
	end
	if findTowerUnit(profile, ProfileSchema.BOMBARDIER_STARTER_TOWER_ID) == nil then
		required += 1
	end
	return required
end

local function hasValidTutorialLoadout(profile: any, configuration: ConfigTypes.CoreConfiguration): boolean
	for _, unitId in profile.equippedUnitIds do
		local unit = profile.units[unitId]
		if unit ~= nil and attacks(configuration.towers.byId[unit.towerId]) then
			return true
		end
	end
	return false
end

local function installStarterLoadout(profile: any, dartUnitId: string, bombardierUnitId: string)
	local loadout = { dartUnitId, bombardierUnitId }
	local seenTowers = {
		[ProfileSchema.DART_STARTER_TOWER_ID] = true,
		[ProfileSchema.BOMBARDIER_STARTER_TOWER_ID] = true,
	}
	for _, unitId in profile.equippedUnitIds do
		local unit = profile.units[unitId]
		if unit ~= nil and not seenTowers[unit.towerId] and #loadout < ProfileSchema.MAX_EQUIPPED_UNITS then
			seenTowers[unit.towerId] = true
			table.insert(loadout, unitId)
		end
	end
	profile.equippedUnitIds = loadout
end

local function installStableStarterLoadout(profile: any, now: number): boolean
	local dartUnitId = grantStarter(
		profile,
		ProfileSchema.DART_STARTER_TOWER_ID,
		ProfileSchema.DART_STARTER_UNIT_ID,
		"unit:tutorial-dart-v1",
		now
	)
	local bombardierUnitId = grantStarter(
		profile,
		ProfileSchema.BOMBARDIER_STARTER_TOWER_ID,
		ProfileSchema.BOMBARDIER_STARTER_UNIT_ID,
		"unit:tutorial-bombardier-v1",
		now
	)
	if dartUnitId == nil or bombardierUnitId == nil then
		return false
	end
	installStarterLoadout(profile, dartUnitId, bombardierUnitId)
	return true
end

local function installOwnedAttacker(profile: any, configuration: ConfigTypes.CoreConfiguration): boolean
	if hasValidTutorialLoadout(profile, configuration) then
		return true
	end
	local bestUnitId: string? = nil
	local bestSequence = math.huge
	for unitId, unit in profile.units do
		if attacks(configuration.towers.byId[unit.towerId]) and unit.acquisitionSequence < bestSequence then
			bestUnitId = unitId
			bestSequence = unit.acquisitionSequence
		end
	end
	if bestUnitId == nil then
		return false
	end
	local loadout = { bestUnitId }
	for _, unitId in profile.equippedUnitIds do
		if unitId ~= bestUnitId and #loadout < ProfileSchema.MAX_EQUIPPED_UNITS then
			table.insert(loadout, unitId)
		end
	end
	profile.equippedUnitIds = loadout
	return true
end

function Methods.getView(self: Service, userIdValue: unknown): Result.Result<Observation, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "getView")
	end
	local read = readProfile(data, userIdValue :: number, "getView")
	return if read.ok then observation(read.value, false) else read
end

function Methods.initialize(self: Service, userIdValue: unknown): Result.Result<Observation, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "initialize")
	end
	local userId = userIdValue :: number
	local dart = data.configuration.towers.byId[ProfileSchema.DART_STARTER_TOWER_ID]
	local bombardier = data.configuration.towers.byId[ProfileSchema.BOMBARDIER_STARTER_TOWER_ID]
	if not attacks(dart) or not attacks(bombardier) then
		return failure("STARTER_UNAVAILABLE", "initialize")
	end
	local nowCalled, now = pcall(data.clock)
	if not nowCalled or type(now) ~= "number" or not Validation.isSafeInteger(now) or now < 0 then
		return failure("UNAVAILABLE", "initialize")
	end
	return observeTransition(data, userId, "initialize", "starter-v1", 0, function(profile)
		if unitCount(profile) + starterSlotsRequired(profile) > ProfileSchema.MAX_UNITS then
			-- A capacity-saturated legacy profile is already an established account.
			-- Preserve every owned unit and complete initialization server-side rather
			-- than trapping step 0 or deleting inventory to make room for new starters.
			profile.tutorial.firstJoin = false
			profile.tutorial.tutorialCompleted = true
			profile.tutorial.tutorialStep = TutorialProtocol.COMPLETE_STEP
			profile.tutorial.skipped = false
			profile.tutorial.trackedMatchId = ""
			return Result.ok(true)
		end
		if not installStableStarterLoadout(profile, now :: number) then
			return Result.err("STARTER_UNAVAILABLE")
		end
		profile.tutorial.firstJoin = false
		profile.tutorial.tutorialStep = 1
		return Result.ok(true)
	end)
end

local function clientTransition(
	data: ServiceData,
	userId: number,
	intentValue: unknown,
	operation: string,
	callback: (any) -> Result.Result<boolean, string>
): Result.Result<TutorialProtocol.MutationReceipt, ServiceError>
	local intent = TutorialProtocol.ActionIntentSchema:validate(intentValue)
	if not intent.ok then
		return failure("INVALID_INTENT", operation)
	end
	return transact(
		data,
		userId,
		intent.value.transactionId,
		intent.value.expectedRevision,
		operation,
		`tutorial|{operation}|{intent.value.expectedRevision}`,
		callback
	)
end

function Methods.advance(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<TutorialProtocol.MutationReceipt, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "advance")
	end
	return clientTransition(data, userIdValue :: number, intentValue, "advance", function(profile)
		local step = profile.tutorial.tutorialStep
		if step == 1 then
			profile.tutorial.tutorialStep = 2
			return Result.ok(true)
		elseif step == 2 and hasValidTutorialLoadout(profile, data.configuration) then
			profile.tutorial.tutorialStep = 3
			return Result.ok(true)
		end
		return Result.err("OUT_OF_ORDER")
	end)
end

function Methods.skip(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<TutorialProtocol.MutationReceipt, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "skip")
	end
	return clientTransition(data, userIdValue :: number, intentValue, "skip", function(profile)
		local step = profile.tutorial.tutorialStep
		if step < 1 or step >= TutorialProtocol.COMPLETE_STEP then
			return Result.err("OUT_OF_ORDER")
		end
		profile.tutorial.firstJoin = false
		profile.tutorial.tutorialCompleted = true
		profile.tutorial.tutorialStep = TutorialProtocol.COMPLETE_STEP
		profile.tutorial.skipped = true
		profile.tutorial.trackedMatchId = ""
		return Result.ok(true)
	end)
end

function Methods.replay(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<TutorialProtocol.MutationReceipt, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "replay")
	end
	local nowCalled, now = pcall(data.clock)
	if not nowCalled or type(now) ~= "number" or not Validation.isSafeInteger(now) or now < 0 then
		return failure("UNAVAILABLE", "replay")
	end
	return clientTransition(data, userIdValue :: number, intentValue, "replay", function(profile)
		if
			profile.tutorial.tutorialStep ~= TutorialProtocol.COMPLETE_STEP
			or profile.tutorial.attempt >= ProfileSchema.MAX_TUTORIAL_ATTEMPT
		then
			return Result.err("OUT_OF_ORDER")
		end
		local hasStableStarterCapacity = unitCount(profile) + starterSlotsRequired(profile) <= ProfileSchema.MAX_UNITS
		if hasStableStarterCapacity then
			if not installStableStarterLoadout(profile, now :: number) then
				return Result.err("STARTER_UNAVAILABLE")
			end
		elseif not installOwnedAttacker(profile, data.configuration) then
			-- This can only occur for malformed/non-production legacy content: the
			-- released catalogs have always included an attacking starter. Keep the
			-- terminal state intact instead of opening an unfinishable replay.
			return Result.err("STARTER_UNAVAILABLE")
		end
		profile.tutorial.tutorialCompleted = false
		profile.tutorial.tutorialStep = 1
		profile.tutorial.attempt += 1
		profile.tutorial.skipped = false
		profile.tutorial.trackedMatchId = ""
		return Result.ok(true)
	end)
end

function Methods.observeStarterLoadout(
	self: Service,
	userIdValue: unknown,
	eventId: string
): Result.Result<Observation, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "starter-loadout")
	end
	return observeTransition(data, userIdValue :: number, "starter-loadout", eventId, 2, function(profile)
		if not hasValidTutorialLoadout(profile, data.configuration) then
			return Result.err("INVALID_LOADOUT")
		end
		profile.tutorial.tutorialStep = 3
		return Result.ok(true)
	end)
end

local function singletonTutorialQueue(userId: number, snapshot: any): boolean
	if
		type(snapshot) ~= "table"
		or type(snapshot.configuration) ~= "table"
		or snapshot.configuration.mapId ~= RELEASE_MAP_ID
		or snapshot.configuration.difficultyId ~= EASY_DIFFICULTY_ID
		or snapshot.configuration.privacy ~= "PartyOnly"
		or type(snapshot.members) ~= "table"
		or #snapshot.members ~= 1
		or snapshot.members[1].userId ~= userId
		or snapshot.members[1].isCaptain ~= true
		or snapshot.members[1].readiness ~= "Ready"
		or type(snapshot.enrollments) ~= "table"
		or #snapshot.enrollments ~= 1
	then
		return false
	end
	local enrollment = snapshot.enrollments[1]
	return type(enrollment) == "table"
		and enrollment.kind == "Solo"
		and enrollment.leaderUserId == userId
		and type(enrollment.userIds) == "table"
		and #enrollment.userIds == 1
		and enrollment.userIds[1] == userId
end

function TutorialService.isSoloEasyQueue(userIdValue: unknown, snapshotValue: unknown): boolean
	return validUserId(userIdValue) and singletonTutorialQueue(userIdValue :: number, snapshotValue)
end

function Methods.observeSoloEasyQueue(
	self: Service,
	userIdValue: unknown,
	snapshotValue: unknown,
	eventId: string
): Result.Result<Observation, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) or type(eventId) ~= "string" then
		return failure("INVALID_EVENT", "solo-easy-queue")
	end
	local userId = userIdValue :: number
	if not singletonTutorialQueue(userId, snapshotValue) then
		local current = readProfile(data, userId, "solo-easy-queue")
		return if current.ok then observation(current.value, false) else current
	end
	return observeTransition(data, userId, "solo-easy-queue", eventId, 3, function(profile)
		profile.tutorial.tutorialStep = 4
		return Result.ok(true)
	end)
end

local function validMatchArrival(userId: number, value: unknown): MatchArrival?
	if type(value) ~= "table" then
		return nil
	end
	local matchId = Ids.validateMatchId((value :: any).matchId)
	local expected = (value :: any).expectedUserIds
	if
		not matchId.ok
		or (value :: any).mapId ~= RELEASE_MAP_ID
		or (value :: any).difficultyId ~= EASY_DIFFICULTY_ID
		or (value :: any).privacy ~= "PartyOnly"
		or (value :: any).authenticatedParticipant ~= true
		or (value :: any).spectator ~= false
		or type(expected) ~= "table"
		or #expected ~= 1
		or expected[1] ~= userId
	then
		return nil
	end
	return value :: MatchArrival
end

function Methods.observeMatchArrival(
	self: Service,
	userIdValue: unknown,
	arrivalValue: unknown
): Result.Result<Observation, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "match-arrival")
	end
	local userId = userIdValue :: number
	local arrival = validMatchArrival(userId, arrivalValue)
	if arrival == nil then
		local current = readProfile(data, userId, "match-arrival")
		return if current.ok then observation(current.value, false) else current
	end
	return observeTransition(data, userId, "match-arrival", arrival.matchId, 4, function(profile)
		profile.tutorial.tutorialStep = 5
		profile.tutorial.trackedMatchId = arrival.matchId
		return Result.ok(true)
	end)
end

local function observeTracked(
	data: ServiceData,
	userId: number,
	operation: string,
	matchIdValue: unknown,
	expectedStep: number,
	nextStep: number
): Result.Result<Observation, ServiceError>
	local matchId = Ids.validateMatchId(matchIdValue)
	if not matchId.ok then
		return failure("INVALID_EVENT", operation)
	end
	return observeTransition(data, userId, operation, matchId.value, expectedStep, function(profile)
		if profile.tutorial.trackedMatchId ~= matchId.value then
			return Result.err("FOREIGN_MATCH")
		end
		profile.tutorial.tutorialStep = nextStep
		return Result.ok(true)
	end)
end

function Methods.observePlacement(
	self: Service,
	userIdValue: unknown,
	matchId: unknown
): Result.Result<Observation, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "placement")
	end
	return observeTracked(data, userIdValue :: number, "placement", matchId, 5, 6)
end

function Methods.observeUpgrade(
	self: Service,
	userIdValue: unknown,
	matchId: unknown
): Result.Result<Observation, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "upgrade")
	end
	return observeTracked(data, userIdValue :: number, "upgrade", matchId, 6, 7)
end

function Methods.observeResult(
	self: Service,
	userIdValue: unknown,
	evidenceValue: unknown
): Result.Result<Observation, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) or type(evidenceValue) ~= "table" then
		return failure("INVALID_EVENT", "result")
	end
	local evidence = evidenceValue :: any
	local matchId = Ids.validateMatchId(evidence.matchId)
	if
		not matchId.ok
		or evidence.mapId ~= RELEASE_MAP_ID
		or evidence.difficultyId ~= EASY_DIFFICULTY_ID
		or evidence.authenticatedParticipant ~= true
		or evidence.spectator ~= false
		or evidence.durable ~= true
	then
		local current = readProfile(data, userIdValue :: number, "result")
		return if current.ok then observation(current.value, false) else current
	end
	return observeTracked(data, userIdValue :: number, "result", matchId.value, 7, 8)
end

function Methods.observeLobbyReturn(
	self: Service,
	userIdValue: unknown,
	matchId: unknown
): Result.Result<Observation, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID", "lobby-return")
	end
	local userId = userIdValue :: number
	local validatedMatchId = Ids.validateMatchId(matchId)
	if not validatedMatchId.ok then
		return failure("INVALID_EVENT", "lobby-return")
	end
	local read = readProfile(data, userId, "lobby-return")
	if not read.ok then
		return read
	end
	local view = tutorialView(read.value)
	if view == nil then
		return failure("PROFILE_INVALID", "lobby-return")
	end
	if view.tutorialStep == 8 then
		if view.trackedMatchId ~= validatedMatchId.value then
			return observation(read.value, false)
		end
	elseif view.tutorialStep >= 4 and view.tutorialStep <= 7 then
		if view.tutorialStep >= 5 and view.trackedMatchId ~= validatedMatchId.value then
			return observation(read.value, false)
		end
		return observeTransition(
			data,
			userId,
			"lobby-return-repair",
			validatedMatchId.value,
			view.tutorialStep,
			function(profile)
				profile.tutorial.tutorialStep = 3
				profile.tutorial.trackedMatchId = ""
				return Result.ok(true)
			end
		)
	else
		return observation(read.value, false)
	end
	return observeTransition(data, userId, "lobby-return", validatedMatchId.value, 8, function(profile)
		if profile.tutorial.trackedMatchId ~= validatedMatchId.value then
			return Result.err("FOREIGN_MATCH")
		end
		profile.tutorial.tutorialStep = TutorialProtocol.COMPLETE_STEP
		profile.tutorial.tutorialCompleted = true
		profile.tutorial.skipped = false
		profile.tutorial.trackedMatchId = ""
		return Result.ok(true)
	end)
end

function Methods.repairTravel(
	self: Service,
	userIdValue: unknown,
	eventIdValue: unknown
): Result.Result<Observation, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) or type(eventIdValue) ~= "string" then
		return failure("INVALID_EVENT", "repair-travel")
	end
	local userId = userIdValue :: number
	local read = readProfile(data, userId, "repair-travel")
	if not read.ok then
		return read
	end
	local view = tutorialView(read.value)
	if view == nil then
		return failure("PROFILE_INVALID", "repair-travel")
	end
	if view.tutorialStep < 4 or view.tutorialStep > 7 then
		return observation(read.value, false)
	end
	return observeTransition(data, userId, "repair-travel", eventIdValue :: string, view.tutorialStep, function(profile)
		profile.tutorial.tutorialStep = 3
		profile.tutorial.trackedMatchId = ""
		return Result.ok(true)
	end)
end

function TutorialService.new(
	profileOwnerValue: unknown,
	configuration: ConfigTypes.CoreConfiguration,
	dependencies: Dependencies?
): Result.Result<Service, ServiceError>
	if
		type(profileOwnerValue) ~= "table"
		or type((profileOwnerValue :: any).getState) ~= "function"
		or type((profileOwnerValue :: any).read) ~= "function"
		or type((profileOwnerValue :: any).transact) ~= "function"
		or type((profileOwnerValue :: any).queueImportantSave) ~= "function"
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	if not ConfigurationValidator.isValidatedConfiguration(configuration) then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local clock = if dependencies == nil then os.time else dependencies.clock or os.time
	if type(clock) ~= "function" then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods)
	DATA[service] = {
		profileOwner = profileOwnerValue :: ProfileOwner,
		configuration = configuration,
		clock = clock,
	}
	return Result.ok(service)
end

return table.freeze(TutorialService)
