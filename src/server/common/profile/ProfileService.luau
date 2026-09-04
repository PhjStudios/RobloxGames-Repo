--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local TowerSchema = require(ReplicatedStorage.Shared.config.TowerSchema)
local ProfileProtocol = require(ReplicatedStorage.Shared.profile.ProfileProtocol)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local ProfileMigrations = require(script.Parent.ProfileMigrations)
local ProfileSchema = require(script.Parent.ProfileSchema)

export type ProfileState = "Loading" | "Ready" | "Failed" | "Releasing"

export type StoreAdapter = {
	updateAsync: (self: StoreAdapter, key: string, transform: (unknown) -> unknown) -> unknown,
}

export type MutationResult = Result.Result<ProfileSchema.ReceiptResult, string>
export type Mutation = (draft: ProfileSchema.Profile) -> MutationResult

export type TransactionOutcome = {
	applied: boolean,
	profileRevision: number,
	committedRevision: number,
	result: ProfileSchema.ReceiptResult,
	profile: ProfileSchema.Profile,
}

export type Dependencies = {
	sessionId: string?,
	clock: (() -> number)?,
	wait: ((number) -> ())?,
	maxAttempts: number?,
	baseBackoffSeconds: number?,
	lockTimeoutSeconds: number?,
	autosaveSeconds: number?,
	shutdownBudgetSeconds: number?,
}

export type ErrorCode =
	"INVALID_SERVICE"
	| "INVALID_TOWER_CATALOG"
	| "INVALID_STORE"
	| "INVALID_DEPENDENCIES"
	| "INVALID_USER_ID"
	| "INVALID_STATE"
	| "INVALID_TIME"
	| "STORE_FAILED"
	| "SESSION_LOCKED"
	| "SESSION_LOST"
	| "PROFILE_REJECTED"
	| "NOT_READY"
	| "INVALID_TRANSACTION"
	| "TRANSACTION_CONFLICT"
	| "STALE_REVISION"
	| "CALLBACK_FAILED"
	| "MUTATION_REJECTED"
	| "INVALID_MUTATION"
	| "REVISION_EXHAUSTED"
	| "BUSY"

export type ServiceError = {
	code: ErrorCode,
	operation: string,
	reason: string?,
}

type StoredSession = {
	id: string,
	heartbeatAt: number,
}

type StoredEnvelope = {
	formatVersion: number,
	profile: unknown,
	session: StoredSession?,
}

type PlayerSession = {
	state: ProfileState,
	profile: ProfileSchema.Profile?,
	migrationOutcome: ProfileMigrations.Outcome?,
	dirty: boolean,
	saving: boolean,
	lastSavedAt: number,
	hasLock: boolean,
	importantSaveQueued: boolean,
	importantSaveWorkerRunning: boolean,
	autosaveQueued: boolean,
	releaseRequested: boolean,
	transferPending: boolean,
	departed: boolean,
	consecutiveSaveFailures: number,
	nextSaveAttemptAt: number,
}

type ServiceData = {
	towers: ConfigTypes.TowerCatalog,
	store: StoreAdapter,
	sessionId: string,
	clock: () -> number,
	wait: (number) -> (),
	maxAttempts: number,
	baseBackoffSeconds: number,
	lockTimeoutSeconds: number,
	autosaveSeconds: number,
	shutdownBudgetSeconds: number,
	sessions: { [number]: PlayerSession },
	lifecycleState: "Constructed" | "Initialized" | "Started" | "ShuttingDown" | "Shutdown",
	serviceDefinition: ServiceLifecycle.ServiceDefinition?,
	connections: { RBXScriptConnection },
	activeJobs: number,
	joinLoadPlayers: { [number]: Player },
	closing: boolean,
}

local SERVICE_NAME = "ProfileService"
local STORE_FORMAT_VERSION = 1
local DEFAULT_MAX_ATTEMPTS = 3
local MAX_ATTEMPTS = 5
local DEFAULT_BACKOFF_SECONDS = 0.05
local MAX_BACKOFF_SECONDS = 1
local DEFAULT_LOCK_TIMEOUT_SECONDS = 120
local MIN_LOCK_TIMEOUT_SECONDS = 30
local MAX_LOCK_TIMEOUT_SECONDS = 3_600
local DEFAULT_AUTOSAVE_SECONDS = 60
local MIN_AUTOSAVE_SECONDS = 15
local MAX_AUTOSAVE_SECONDS = 300
local DEFAULT_SHUTDOWN_BUDGET_SECONDS = 8
local MAX_SHUTDOWN_BUDGET_SECONDS = 9
local MAX_ACTIVE_JOBS = 256
local DEPARTURE_RELEASE_CYCLES = 3

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local ProfileService = {
	STORE_FORMAT_VERSION = STORE_FORMAT_VERSION,
	DEFAULT_MAX_ATTEMPTS = DEFAULT_MAX_ATTEMPTS,
	DEFAULT_LOCK_TIMEOUT_SECONDS = DEFAULT_LOCK_TIMEOUT_SECONDS,
	DEFAULT_AUTOSAVE_SECONDS = DEFAULT_AUTOSAVE_SECONDS,
	DEFAULT_SHUTDOWN_BUDGET_SECONDS = DEFAULT_SHUTDOWN_BUDGET_SECONDS,
	departPlayerForTests = nil :: ((Service, unknown) -> boolean)?,
}

local function errorResult(code: ErrorCode, operation: string, reason: string?): Result.Failure<ServiceError>
	return Result.err(table.freeze({
		code = code,
		operation = operation,
		reason = reason,
	}))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_PROFILE_SERVICE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value) and value > 0
end

local function validToken(value: unknown, maximumBytes: number): boolean
	if type(value) ~= "string" or #value < 1 or #value > maximumBytes then
		return false
	end
	for index = 1, #value do
		local byte = string.byte(value, index)
		if byte == nil or byte < 33 or byte > 126 then
			return false
		end
	end
	return true
end

local function validRejectionReason(value: unknown): boolean
	return type(value) == "string" and #value >= 1 and #value <= 48 and string.match(value, "^[A-Z][A-Z0-9_]*$") ~= nil
end

local function readTime(data: ServiceData): number?
	local succeeded, value = pcall(data.clock)
	if not succeeded or type(value) ~= "number" or not Validation.isSafeInteger(value) or (value :: number) < 0 then
		return nil
	end
	return value :: number
end

local function leaseIsCurrent(data: ServiceData, session: PlayerSession): boolean
	if not session.hasLock then
		return false
	end
	local now = readTime(data)
	if now == nil then
		return false
	end
	local age = now - session.lastSavedAt
	return age >= 0 and age < data.lockTimeoutSeconds
end

local function failExpiredLease(session: PlayerSession)
	session.state = "Failed"
	session.profile = nil
	session.migrationOutcome = nil
	session.dirty = false
	session.hasLock = false
	session.importantSaveQueued = false
	session.autosaveQueued = false
end

local function profileKey(userId: number): string
	return `profile:{string.format("%.0f", userId)}`
end

local function parseStoredSession(value: unknown): StoredSession?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local count = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "string" or (key ~= "id" and key ~= "heartbeatAt") then
			return nil
		end
		count += 1
	end
	local id = rawget(value :: any, "id")
	local heartbeatAt = rawget(value :: any, "heartbeatAt")
	if
		count ~= 2
		or not validToken(id, 100)
		or type(heartbeatAt) ~= "number"
		or not Validation.isSafeInteger(heartbeatAt)
		or (heartbeatAt :: number) < 0
	then
		return nil
	end
	return {
		id = id :: string,
		heartbeatAt = heartbeatAt :: number,
	}
end

local function parseEnvelope(value: unknown): (StoredEnvelope?, boolean)
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil, false
	end
	if rawget(value :: any, "formatVersion") == nil then
		return nil, true
	end
	local fieldCount = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "string" or (key ~= "formatVersion" and key ~= "profile" and key ~= "session") then
			return nil, false
		end
		fieldCount += 1
	end
	if
		rawget(value :: any, "formatVersion") ~= STORE_FORMAT_VERSION
		or rawget(value :: any, "profile") == nil
		or fieldCount < 2
		or fieldCount > 3
	then
		return nil, false
	end
	local rawSession = rawget(value :: any, "session")
	local session = if rawSession == nil then nil else parseStoredSession(rawSession)
	if rawSession ~= nil and session == nil then
		return nil, false
	end
	return {
		formatVersion = STORE_FORMAT_VERSION,
		profile = rawget(value :: any, "profile"),
		session = session,
	},
		false
end

local function makeEnvelope(profile: ProfileSchema.Profile, session: StoredSession?): StoredEnvelope
	local envelope: StoredEnvelope = {
		formatVersion = STORE_FORMAT_VERSION,
		profile = profile,
		session = session,
	}
	return envelope
end

local function updateWithRetry(
	data: ServiceData,
	key: string,
	transform: (unknown) -> unknown,
	maximumAttempts: number?
): (boolean, unknown)
	local attempts = maximumAttempts or data.maxAttempts
	for attempt = 1, attempts do
		local succeeded, resultValue = pcall(data.store.updateAsync, data.store, key, transform)
		if succeeded then
			return true, resultValue
		end
		if attempt < attempts then
			local delay = math.min(data.baseBackoffSeconds * (2 ^ (attempt - 1)), MAX_BACKOFF_SECONDS)
			if not pcall(data.wait, delay) then
				break
			end
		end
	end
	return false, nil
end

local function findReceipt(
	profile: ProfileSchema.Profile,
	transactionId: Ids.TransactionId
): ProfileSchema.TransactionReceipt?
	for _, receipt in profile.receipts do
		if receipt.transactionId == transactionId then
			return receipt
		end
	end
	return nil
end

local function callMutation(callback: Mutation, draft: ProfileSchema.Profile): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, draft)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function transactionOutcome(
	profile: ProfileSchema.Profile,
	receipt: ProfileSchema.TransactionReceipt,
	applied: boolean
): TransactionOutcome
	return table.freeze({
		applied = applied,
		profileRevision = profile.revision,
		committedRevision = receipt.committedRevision,
		result = receipt.result,
		profile = profile,
	})
end

local save: (ServiceData, number, PlayerSession, boolean) -> Result.Result<boolean, ServiceError>

function Methods.getState(self: Service, userIdValue: unknown): ProfileState?
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return nil
	end
	local session = data.sessions[userIdValue :: number]
	if session ~= nil and session.state == "Ready" and not leaseIsCurrent(data, session) then
		if session.saving then
			return "Loading"
		end
		failExpiredLease(session)
	end
	return if session == nil then nil else session.state
end

function Methods.getClientSnapshot(
	self: Service,
	userIdValue: unknown
): Result.Result<ProfileProtocol.Snapshot, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return errorResult("INVALID_USER_ID", "getClientSnapshot", nil)
	end
	local state = self:getState(userIdValue)
	local session = data.sessions[userIdValue :: number]
	if session == nil then
		return Result.ok(ProfileProtocol.status("Loading"))
	end
	if state ~= "Ready" or session.profile == nil or session.migrationOutcome == nil then
		return Result.ok(ProfileProtocol.status(state or "Loading"))
	end
	return Result.ok(ProfileProtocol.ready(session.profile, session.migrationOutcome))
end

function Methods.read(self: Service, userIdValue: unknown): Result.Result<ProfileSchema.Profile, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return errorResult("INVALID_USER_ID", "read", nil)
	end
	local session = data.sessions[userIdValue :: number]
	if self:getState(userIdValue) ~= "Ready" or session == nil or session.profile == nil then
		return errorResult("NOT_READY", "read", nil)
	end
	return Result.ok(session.profile)
end

-- Synchronously closes the profile mutation gate and returns the exact profile
-- revision that a travel ticket may snapshot. No persistence call is made here;
-- the subsequent release owns the save. Because every mutation requires Ready,
-- no coroutine can change the profile after this method returns successfully.
function Methods.beginTransfer(self: Service, userIdValue: unknown): Result.Result<ProfileSchema.Profile, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return errorResult("INVALID_USER_ID", "beginTransfer", nil)
	end
	if data.closing or data.lifecycleState == "ShuttingDown" or data.lifecycleState == "Shutdown" then
		return errorResult("NOT_READY", "beginTransfer", nil)
	end
	local userId = userIdValue :: number
	local session = data.sessions[userId]
	if session ~= nil and session.state == "Ready" and not leaseIsCurrent(data, session) then
		if session.saving then
			return errorResult("BUSY", "beginTransfer", nil)
		end
		failExpiredLease(session)
		return errorResult("SESSION_LOST", "beginTransfer", nil)
	end
	if
		session == nil
		or session.state ~= "Ready"
		or session.profile == nil
		or not session.hasLock
		or session.saving
	then
		return errorResult("NOT_READY", "beginTransfer", nil)
	end
	session.state = "Releasing"
	session.releaseRequested = true
	session.transferPending = true
	return Result.ok(session.profile)
end

-- Reopens only a transfer gate that has not begun persistence. This is used
-- when another squad member cannot be frozen, before any ownership is released.
function Methods.cancelTransfer(self: Service, userIdValue: unknown): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return errorResult("INVALID_USER_ID", "cancelTransfer", nil)
	end
	local session = data.sessions[userIdValue :: number]
	if
		session == nil
		or session.state ~= "Releasing"
		or session.profile == nil
		or not session.hasLock
		or session.saving
	then
		return errorResult("INVALID_STATE", "cancelTransfer", nil)
	end
	session.releaseRequested = false
	session.transferPending = false
	session.state = "Ready"
	return Result.ok(true)
end

function Methods.load(self: Service, userIdValue: unknown): Result.Result<ProfileSchema.Profile, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return errorResult("INVALID_USER_ID", "load", nil)
	end
	if data.closing or data.lifecycleState == "Shutdown" then
		return errorResult("INVALID_STATE", "load", nil)
	end
	local userId = userIdValue :: number
	local existing = data.sessions[userId]
	if existing ~= nil and existing.state ~= "Failed" then
		if existing.state == "Releasing" and existing.hasLock and existing.profile ~= nil then
			local released = save(data, userId, existing, true)
			if not released.ok then
				return errorResult(released.error.code, "load", released.error.reason)
			end
		elseif existing.state == "Releasing" and not existing.hasLock and existing.transferPending then
			-- A successful travel release deliberately leaves a non-writable local
			-- sentinel while the Player is still present. Only an explicit recovery
			-- load may consume it; the automatic Player/heartbeat loader sees the
			-- existing session and therefore cannot reacquire the lease mid-teleport.
			data.sessions[userId] = nil
		else
			return errorResult("INVALID_STATE", "load", nil)
		end
	end
	local playerSession: PlayerSession = {
		state = "Loading",
		profile = nil,
		migrationOutcome = nil,
		dirty = false,
		saving = false,
		lastSavedAt = 0,
		hasLock = false,
		importantSaveQueued = false,
		importantSaveWorkerRunning = false,
		autosaveQueued = false,
		releaseRequested = false,
		transferPending = false,
		departed = false,
		consecutiveSaveFailures = 0,
		nextSaveAttemptAt = 0,
	}
	data.sessions[userId] = playerSession
	local function discardDepartedFailure()
		if playerSession.departed and data.sessions[userId] == playerSession then
			data.sessions[userId] = nil
		end
	end
	local now = readTime(data)
	if now == nil then
		playerSession.state = "Failed"
		discardDepartedFailure()
		return errorResult("INVALID_TIME", "load", nil)
	end

	local acceptedProfile: ProfileSchema.Profile? = nil
	local migrationOutcome: ProfileMigrations.Outcome? = nil
	local transformFailure: ErrorCode? = nil
	local function transform(storedValue: unknown): unknown
		acceptedProfile = nil
		migrationOutcome = nil
		transformFailure = nil
		local envelope: StoredEnvelope?
		local isLegacy: boolean
		if storedValue == nil then
			envelope = nil
			isLegacy = false
		else
			envelope, isLegacy = parseEnvelope(storedValue)
		end
		if storedValue ~= nil and envelope == nil and not isLegacy then
			transformFailure = "PROFILE_REJECTED"
			return nil
		end
		local storedSession = if envelope == nil then nil else envelope.session
		if storedSession ~= nil and storedSession.id ~= data.sessionId then
			local age = now - storedSession.heartbeatAt
			if age < 0 or age < data.lockTimeoutSeconds then
				transformFailure = "SESSION_LOCKED"
				return nil
			end
		end
		local rawProfile = if envelope ~= nil then envelope.profile else storedValue
		local migrated = ProfileMigrations.migrate(rawProfile, data.towers, now)
		if not migrated.ok then
			transformFailure = "PROFILE_REJECTED"
			return nil
		end
		acceptedProfile = migrated.value.profile
		migrationOutcome = migrated.value.outcome
		return makeEnvelope(migrated.value.profile, {
			id = data.sessionId,
			heartbeatAt = now,
		})
	end

	local updated = updateWithRetry(data, profileKey(userId), transform)
	if not updated or acceptedProfile == nil or migrationOutcome == nil then
		playerSession.state = "Failed"
		discardDepartedFailure()
		return errorResult(transformFailure or "STORE_FAILED", "load", nil)
	end
	if data.closing or playerSession.releaseRequested then
		playerSession.profile = acceptedProfile
		playerSession.migrationOutcome = migrationOutcome
		playerSession.hasLock = true
		playerSession.state = "Releasing"
		save(data, userId, playerSession, true)
		return errorResult("INVALID_STATE", "load", nil)
	end
	playerSession.profile = acceptedProfile
	playerSession.migrationOutcome = migrationOutcome
	playerSession.dirty = migrationOutcome ~= "Current"
	playerSession.lastSavedAt = now
	playerSession.hasLock = true
	playerSession.state = "Ready"
	return Result.ok(acceptedProfile)
end

function Methods.retryLoad(self: Service, userIdValue: unknown): Result.Result<ProfileSchema.Profile, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return errorResult("INVALID_USER_ID", "retryLoad", nil)
	end
	local session = data.sessions[userIdValue :: number]
	if session == nil or session.state ~= "Failed" or session.profile ~= nil or session.hasLock then
		return errorResult("INVALID_STATE", "retryLoad", nil)
	end
	return self:load(userIdValue)
end

function Methods.transact(
	self: Service,
	userIdValue: unknown,
	transactionIdValue: unknown,
	expectedRevisionValue: unknown,
	kindValue: unknown,
	fingerprintValue: unknown,
	callbackValue: unknown
): Result.Result<TransactionOutcome, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return errorResult("INVALID_USER_ID", "transact", nil)
	end
	local transactionId = Ids.validateTransactionId(transactionIdValue)
	if
		not transactionId.ok
		or type(expectedRevisionValue) ~= "number"
		or not Validation.isSafeInteger(expectedRevisionValue)
		or (expectedRevisionValue :: number) < 1
		or not validToken(kindValue, 48)
		or not validToken(fingerprintValue, 160)
		or type(callbackValue) ~= "function"
	then
		return errorResult("INVALID_TRANSACTION", "transact", nil)
	end
	local userId = userIdValue :: number
	if data.closing or data.lifecycleState == "ShuttingDown" or data.lifecycleState == "Shutdown" then
		return errorResult("NOT_READY", "transact", nil)
	end
	local session = data.sessions[userId]
	if session ~= nil and session.state == "Ready" and not leaseIsCurrent(data, session) then
		if session.saving then
			return errorResult("BUSY", "transact", nil)
		end
		failExpiredLease(session)
		return errorResult("SESSION_LOST", "transact", nil)
	end
	if session == nil or session.state ~= "Ready" or session.profile == nil or not session.hasLock then
		return errorResult("NOT_READY", "transact", nil)
	end
	local profile = session.profile
	local replay = findReceipt(profile, transactionId.value)
	if replay ~= nil then
		if replay.kind ~= kindValue or replay.fingerprint ~= fingerprintValue then
			return errorResult("TRANSACTION_CONFLICT", "transact", nil)
		end
		return Result.ok(transactionOutcome(profile, replay, false))
	end
	if profile.revision ~= expectedRevisionValue then
		return errorResult("STALE_REVISION", "transact", nil)
	end
	if profile.revision >= Validation.MAX_SAFE_INTEGER then
		return errorResult("REVISION_EXHAUSTED", "transact", nil)
	end

	local draft = ProfileSchema.clone(profile)
	local callbackSucceeded, mutationValue = callMutation(callbackValue :: Mutation, draft)
	if not callbackSucceeded or type(mutationValue) ~= "table" then
		return errorResult("CALLBACK_FAILED", "transact", nil)
	end
	local mutationResult = mutationValue :: any
	if mutationResult.ok ~= true then
		local reason = mutationResult.error
		return if validRejectionReason(reason)
			then errorResult("MUTATION_REJECTED", "transact", reason)
			else errorResult("CALLBACK_FAILED", "transact", nil)
	end
	local canonicalResult = ProfileSchema.validateReceiptResult(mutationResult.value)
	if not canonicalResult.ok then
		return errorResult("INVALID_MUTATION", "transact", nil)
	end
	if canonicalResult.value.goldBalance ~= (draft :: any).gold then
		return errorResult("INVALID_MUTATION", "transact", nil)
	end
	for index, unitId in canonicalResult.value.unitIds do
		local unit = (draft :: any).units and (draft :: any).units[unitId]
		if unit == nil or unit.towerId ~= canonicalResult.value.towerIds[index] then
			return errorResult("INVALID_MUTATION", "transact", nil)
		end
	end

	local now = readTime(data)
	if now == nil then
		return errorResult("INVALID_TIME", "transact", nil)
	end
	local nextRevision = profile.revision + 1
	local mutableDraft = draft :: any
	mutableDraft.schemaVersion = ProfileSchema.CURRENT_VERSION
	mutableDraft.revision = nextRevision
	mutableDraft.migration = ProfileSchema.clone(profile.migration)
	mutableDraft.receipts = ProfileSchema.clone(profile.receipts)
	local receipt: ProfileSchema.TransactionReceipt = {
		transactionId = transactionId.value,
		kind = kindValue :: string,
		fingerprint = fingerprintValue :: string,
		committedRevision = nextRevision,
		createdAt = now,
		result = canonicalResult.value,
	}
	local receipts = mutableDraft.receipts :: { ProfileSchema.TransactionReceipt }
	if #receipts >= ProfileSchema.MAX_RECEIPTS then
		table.remove(receipts, 1)
	end
	table.insert(receipts, receipt)
	local validated = ProfileSchema.validate(draft, data.towers)
	if not validated.ok then
		return errorResult("INVALID_MUTATION", "transact", nil)
	end
	session.profile = validated.value
	session.dirty = true
	local storedReceipt = findReceipt(validated.value, transactionId.value)
	if storedReceipt == nil then
		return errorResult("INVALID_MUTATION", "transact", nil)
	end
	return Result.ok(transactionOutcome(validated.value, storedReceipt, true))
end

save = function(
	data: ServiceData,
	userId: number,
	session: PlayerSession,
	release: boolean
): Result.Result<boolean, ServiceError>
	if session.profile == nil or not session.hasLock then
		return errorResult("SESSION_LOST", if release then "release" else "flush", nil)
	end
	if session.saving then
		return errorResult("BUSY", if release then "release" else "flush", nil)
	end
	local now = readTime(data)
	if now == nil then
		return errorResult("INVALID_TIME", if release then "release" else "flush", nil)
	end
	local capturedProfile = session.profile
	local capturedRevision = capturedProfile.revision
	local sessionLost = false
	session.saving = true
	local function transform(storedValue: unknown): unknown
		sessionLost = false
		local envelope, isLegacy = parseEnvelope(storedValue)
		if isLegacy or envelope == nil or envelope.session == nil or envelope.session.id ~= data.sessionId then
			sessionLost = true
			return nil
		end
		return makeEnvelope(
			capturedProfile,
			if release
				then nil
				else {
					id = data.sessionId,
					heartbeatAt = now,
				}
		)
	end
	local releaseAttempts = if session.departed then data.maxAttempts else math.min(2, data.maxAttempts)
	local updated = updateWithRetry(data, profileKey(userId), transform, if release then releaseAttempts else nil)
	session.saving = false
	if not updated then
		session.consecutiveSaveFailures = math.min(session.consecutiveSaveFailures + 1, 6)
		session.nextSaveAttemptAt = now
			+ math.min(5 * (2 ^ (session.consecutiveSaveFailures - 1)), data.autosaveSeconds)
		if not release and session.releaseRequested and session.hasLock then
			return save(data, userId, session, true)
		end
		return errorResult("STORE_FAILED", if release then "release" else "flush", nil)
	end
	if sessionLost then
		failExpiredLease(session)
		if release or session.releaseRequested then
			data.sessions[userId] = nil
		end
		return errorResult("SESSION_LOST", if release then "release" else "flush", nil)
	end
	if release then
		local retainTransferSentinel = session.transferPending and not session.departed and not data.closing
		session.hasLock = false
		session.dirty = false
		session.releaseRequested = false
		session.consecutiveSaveFailures = 0
		session.nextSaveAttemptAt = 0
		if retainTransferSentinel then
			session.profile = nil
			session.migrationOutcome = nil
		elseif data.sessions[userId] == session then
			data.sessions[userId] = nil
		end
	else
		if session.profile ~= nil and session.profile.revision == capturedRevision then
			session.dirty = false
			session.importantSaveQueued = false
		end
		session.lastSavedAt = now
		session.consecutiveSaveFailures = 0
		session.nextSaveAttemptAt = 0
		if session.releaseRequested and session.hasLock then
			return save(data, userId, session, true)
		end
		if session.importantSaveQueued and session.state == "Ready" and session.hasLock then
			session.importantSaveQueued = false
			return save(data, userId, session, false)
		end
	end
	return Result.ok(true)
end

function Methods.flush(self: Service, userIdValue: unknown): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return errorResult("INVALID_USER_ID", "flush", nil)
	end
	local userId = userIdValue :: number
	local session = data.sessions[userId]
	if session == nil or session.state ~= "Ready" then
		return errorResult("NOT_READY", "flush", nil)
	end
	return save(data, userId, session, false)
end

function Methods.release(self: Service, userIdValue: unknown): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return errorResult("INVALID_USER_ID", "release", nil)
	end
	local userId = userIdValue :: number
	local session = data.sessions[userId]
	if session == nil then
		return Result.ok(false)
	end
	if session.state == "Failed" and not session.hasLock then
		data.sessions[userId] = nil
		return Result.ok(false)
	end
	if session.state == "Releasing" and not session.hasLock then
		if (session.departed or data.closing) and data.sessions[userId] == session then
			data.sessions[userId] = nil
		end
		return Result.ok(false)
	end
	session.state = "Releasing"
	session.releaseRequested = true
	if not session.hasLock or session.profile == nil then
		session.dirty = false
		return Result.ok(false)
	end
	return save(data, userId, session, true)
end

local function spawnOwned(data: ServiceData, callback: () -> ()): boolean
	if data.closing or data.activeJobs >= MAX_ACTIVE_JOBS then
		return false
	end
	data.activeJobs += 1
	task.spawn(function()
		pcall(callback)
		data.activeJobs -= 1
	end)
	return true
end

local function releaseDepartedPlayer(
	service: Service,
	data: ServiceData,
	userId: number,
	expectedSession: PlayerSession
)
	local lastCode: ErrorCode? = nil
	for cycle = 1, DEPARTURE_RELEASE_CYCLES do
		if data.sessions[userId] ~= expectedSession then
			return
		end
		local released = service:release(userId)
		if released.ok then
			return
		end
		lastCode = released.error.code
		if lastCode ~= "STORE_FAILED" and lastCode ~= "BUSY" then
			break
		end
		if cycle < DEPARTURE_RELEASE_CYCLES then
			local delay = math.min(data.baseBackoffSeconds * (2 ^ (cycle - 1)), MAX_BACKOFF_SECONDS)
			pcall(data.wait, delay)
		end
	end

	-- A departed player's exhausted release is never made writable again. Drop only
	-- idle local state; the persisted lease remains authoritative until it expires.
	local session = data.sessions[userId]
	if session == expectedSession and session.state == "Releasing" and not session.saving then
		failExpiredLease(session)
		data.sessions[userId] = nil
	end
end

local function loadJoinedPlayer(service: Service, data: ServiceData, player: Player)
	local userId = player.UserId
	local acquiredSession: PlayerSession? = nil
	for cycle = 1, DEPARTURE_RELEASE_CYCLES do
		if player.Parent ~= Players then
			return
		end
		local loaded = service:load(userId)
		if loaded.ok then
			acquiredSession = data.sessions[userId]
			break
		end
		if loaded.error.code ~= "BUSY" and loaded.error.code ~= "INVALID_STATE" then
			break
		end
		if cycle < DEPARTURE_RELEASE_CYCLES then
			local delay = math.min(data.baseBackoffSeconds * (2 ^ (cycle - 1)), MAX_BACKOFF_SECONDS)
			pcall(data.wait, delay)
		end
	end
	if player.Parent ~= Players and acquiredSession ~= nil and data.sessions[userId] == acquiredSession then
		releaseDepartedPlayer(service, data, userId, acquiredSession)
	end
end

local function scheduleJoinedPlayerLoad(service: Service, data: ServiceData, player: Player): boolean
	if data.closing or player.Parent ~= Players then
		return false
	end
	local userId = player.UserId
	if data.joinLoadPlayers[userId] ~= nil then
		return false
	end
	data.joinLoadPlayers[userId] = player
	if
		not spawnOwned(data, function()
			pcall(loadJoinedPlayer, service, data, player)
			if data.joinLoadPlayers[userId] == player then
				data.joinLoadPlayers[userId] = nil
			end
		end)
	then
		data.joinLoadPlayers[userId] = nil
		return false
	end
	return true
end

local function scheduleDepartedPlayerRelease(service: Service, data: ServiceData, userId: number): boolean
	local departingSession = data.sessions[userId]
	if departingSession == nil then
		return false
	end
	departingSession.releaseRequested = true
	departingSession.departed = true
	if departingSession.state ~= "Failed" then
		departingSession.state = "Releasing"
	end
	local scheduled = spawnOwned(data, function()
		releaseDepartedPlayer(service, data, userId, departingSession)
	end)
	if not scheduled and not departingSession.saving and data.sessions[userId] == departingSession then
		failExpiredLease(departingSession)
		data.sessions[userId] = nil
	end
	return scheduled
end

function Methods.queueImportantSave(self: Service, userIdValue: unknown): Result.Result<boolean, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return errorResult("INVALID_USER_ID", "queueImportantSave", nil)
	end
	local userId = userIdValue :: number
	local session = data.sessions[userId]
	if session == nil or session.state ~= "Ready" or session.profile == nil or not session.hasLock then
		return errorResult("NOT_READY", "queueImportantSave", nil)
	end
	session.importantSaveQueued = true
	if session.importantSaveWorkerRunning then
		return Result.ok(false)
	end
	session.importantSaveWorkerRunning = true
	if
		not spawnOwned(data, function()
			local passes = 0
			while passes < 2 and session.importantSaveQueued and session.state == "Ready" and not data.closing do
				session.importantSaveQueued = false
				passes += 1
				local flushed = self:flush(userId)
				if not flushed.ok and (flushed.error.code == "BUSY" or flushed.error.code == "STORE_FAILED") then
					session.importantSaveQueued = true
					if flushed.error.code == "BUSY" then
						break
					end
				end
			end
			session.importantSaveWorkerRunning = false
		end)
	then
		session.importantSaveWorkerRunning = false
		return errorResult("BUSY", "queueImportantSave", nil)
	end
	return Result.ok(true)
end

function Methods.stepAutosave(self: Service): Result.Result<number, ServiceError>
	local data = requireData(self)
	if data.closing then
		return errorResult("INVALID_STATE", "stepAutosave", nil)
	end
	local now = readTime(data)
	if now == nil then
		return errorResult("INVALID_TIME", "stepAutosave", nil)
	end
	local candidates: { number } = {}
	for userId, session in data.sessions do
		if
			session.state == "Ready"
			and not session.saving
			and not session.autosaveQueued
			and now >= session.nextSaveAttemptAt
			and now - session.lastSavedAt >= data.autosaveSeconds
		then
			table.insert(candidates, userId)
		end
	end
	table.sort(candidates)
	local scheduled = 0
	for _, userId in candidates do
		local session = data.sessions[userId]
		if session ~= nil then
			session.autosaveQueued = true
		end
		if
			spawnOwned(data, function()
				self:flush(userId)
				local current = data.sessions[userId]
				if current ~= nil then
					current.autosaveQueued = false
				end
			end)
		then
			scheduled += 1
		elseif session ~= nil then
			session.autosaveQueued = false
		end
	end
	return Result.ok(scheduled)
end

local function initialize(data: ServiceData)
	if data.lifecycleState ~= "Constructed" then
		error("[ATD_PROFILE_SERVICE][code=INVALID_INITIALIZE_STATE]", 0)
	end
	data.lifecycleState = "Initialized"
end

local function start(service: Service, data: ServiceData)
	if data.lifecycleState ~= "Initialized" then
		error("[ATD_PROFILE_SERVICE][code=INVALID_START_STATE]", 0)
	end
	data.lifecycleState = "Started"
	table.insert(
		data.connections,
		Players.PlayerAdded:Connect(function(player)
			scheduleJoinedPlayerLoad(service, data, player)
		end)
	)
	table.insert(
		data.connections,
		Players.PlayerRemoving:Connect(function(player)
			scheduleDepartedPlayerRelease(service, data, player.UserId)
		end)
	)
	table.insert(
		data.connections,
		RunService.Heartbeat:Connect(function()
			service:stepAutosave()
			for _, player in Players:GetPlayers() do
				if data.sessions[player.UserId] == nil then
					scheduleJoinedPlayerLoad(service, data, player)
				end
			end
		end)
	)
	for _, player in Players:GetPlayers() do
		scheduleJoinedPlayerLoad(service, data, player)
	end
end

local function shutdown(service: Service, data: ServiceData)
	if data.lifecycleState == "Shutdown" then
		return
	end
	data.lifecycleState = "ShuttingDown"
	data.closing = true
	for index = #data.connections, 1, -1 do
		data.connections[index]:Disconnect()
	end
	table.clear(data.connections)
	local deadline = os.clock() + data.shutdownBudgetSeconds
	local userIds: { number } = {}
	for userId in data.sessions do
		table.insert(userIds, userId)
	end
	table.sort(userIds)
	local shutdownJobs = 0
	for _, userId in userIds do
		if os.clock() >= deadline then
			break
		end
		shutdownJobs += 1
		task.spawn(function()
			pcall(function()
				service:release(userId)
			end)
			shutdownJobs -= 1
		end)
	end
	while (shutdownJobs > 0 or data.activeJobs > 0) and os.clock() < deadline do
		task.wait(math.min(0.05, math.max(0, deadline - os.clock())))
	end
	data.lifecycleState = "Shutdown"
end

function Methods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	return requireData(self).serviceDefinition :: ServiceLifecycle.ServiceDefinition
end

function Methods.getMetrics(self: Service): { [string]: number | string | boolean }
	local data = requireData(self)
	local loading = 0
	local ready = 0
	local failed = 0
	local releasing = 0
	local dirty = 0
	for _, session in data.sessions do
		if session.state == "Loading" then
			loading += 1
		elseif session.state == "Ready" then
			ready += 1
		elseif session.state == "Failed" then
			failed += 1
		else
			releasing += 1
		end
		if session.dirty then
			dirty += 1
		end
	end
	return table.freeze({
		lifecycleState = data.lifecycleState,
		loadingCount = loading,
		readyCount = ready,
		failedCount = failed,
		releasingCount = releasing,
		dirtyCount = dirty,
		activeJobCount = data.activeJobs,
		closing = data.closing,
	})
end

local function generatedSessionId(): string
	local generated, value = pcall(HttpService.GenerateGUID, HttpService, false)
	if not generated or type(value) ~= "string" then
		error("[ATD_PROFILE_SERVICE][code=SESSION_ID_FAILED]", 0)
	end
	return `profile-session:{string.lower(value :: string)}`
end

function ProfileService.new(
	towersValue: unknown,
	storeValue: unknown,
	dependenciesValue: Dependencies?
): Result.Result<Service, ServiceError>
	if not TowerSchema.isValidatedCatalog(towersValue) then
		return errorResult("INVALID_TOWER_CATALOG", "new", nil)
	end
	if type(storeValue) ~= "table" or type((storeValue :: any).updateAsync) ~= "function" then
		return errorResult("INVALID_STORE", "new", nil)
	end
	if
		dependenciesValue ~= nil
		and (type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil)
	then
		return errorResult("INVALID_DEPENDENCIES", "new", nil)
	end
	local dependencies = dependenciesValue or {}
	local sessionId = dependencies.sessionId or generatedSessionId()
	local clock = dependencies.clock or os.time
	local wait = dependencies.wait or task.wait
	local maxAttempts = dependencies.maxAttempts or DEFAULT_MAX_ATTEMPTS
	local backoff = dependencies.baseBackoffSeconds or DEFAULT_BACKOFF_SECONDS
	local lockTimeout = dependencies.lockTimeoutSeconds or DEFAULT_LOCK_TIMEOUT_SECONDS
	local autosave = dependencies.autosaveSeconds or DEFAULT_AUTOSAVE_SECONDS
	local shutdownBudget = dependencies.shutdownBudgetSeconds or DEFAULT_SHUTDOWN_BUDGET_SECONDS
	if
		not validToken(sessionId, 100)
		or type(clock) ~= "function"
		or type(wait) ~= "function"
		or type(maxAttempts) ~= "number"
		or not Validation.isSafeInteger(maxAttempts)
		or maxAttempts < 1
		or maxAttempts > MAX_ATTEMPTS
		or type(backoff) ~= "number"
		or not Validation.isFiniteNumber(backoff)
		or backoff < 0
		or backoff > MAX_BACKOFF_SECONDS
		or type(lockTimeout) ~= "number"
		or not Validation.isSafeInteger(lockTimeout)
		or lockTimeout < MIN_LOCK_TIMEOUT_SECONDS
		or lockTimeout > MAX_LOCK_TIMEOUT_SECONDS
		or type(autosave) ~= "number"
		or not Validation.isSafeInteger(autosave)
		or autosave < MIN_AUTOSAVE_SECONDS
		or autosave > MAX_AUTOSAVE_SECONDS
		or autosave >= lockTimeout
		or type(shutdownBudget) ~= "number"
		or not Validation.isFiniteNumber(shutdownBudget)
		or shutdownBudget <= 0
		or shutdownBudget > MAX_SHUTDOWN_BUDGET_SECONDS
	then
		return errorResult("INVALID_DEPENDENCIES", "new", nil)
	end

	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	local data: ServiceData = {
		towers = towersValue :: ConfigTypes.TowerCatalog,
		store = storeValue :: StoreAdapter,
		sessionId = sessionId,
		clock = clock,
		wait = wait,
		maxAttempts = maxAttempts,
		baseBackoffSeconds = backoff,
		lockTimeoutSeconds = lockTimeout,
		autosaveSeconds = autosave,
		shutdownBudgetSeconds = shutdownBudget,
		sessions = {},
		lifecycleState = "Constructed",
		serviceDefinition = nil,
		connections = {},
		activeJobs = 0,
		joinLoadPlayers = {},
		closing = false,
	}
	data.serviceDefinition = table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({}),
		initialize = function()
			initialize(data)
		end,
		start = function()
			start(service, data)
		end,
		shutdown = function()
			shutdown(service, data)
		end,
	})
	DATA[service] = data
	return Result.ok(service)
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "ProfileService" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionServerProfile" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

if isExactTestModule() then
	ProfileService.departPlayerForTests = function(service: Service, userIdValue: unknown): boolean
		local data = requireData(service)
		if not validUserId(userIdValue) then
			return false
		end
		return scheduleDepartedPlayerRelease(service, data, userIdValue :: number)
	end
end

table.freeze(Methods)
return table.freeze(ProfileService)
