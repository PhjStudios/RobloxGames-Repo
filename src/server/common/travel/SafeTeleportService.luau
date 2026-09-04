--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type FailureClass = "Retryable" | "Terminal"
export type Rollback = {
	ticketId: string,
	failedUserIds: { number },
	presentUserIds: { number },
	departedUserIds: { number },
	partial: boolean,
}
export type ReservedServer = {
	ticketId: string,
	placeId: number,
	privateServerId: string,
	accessCode: string,
	orderedUserIds: { number },
}
export type Completion = {
	ticketId: string,
	departedUserIds: { number },
}
export type Dependencies = {
	now: (() -> unknown)?,
	wait: ((number) -> ())?,
	schedule: ((() -> ()) -> unknown)?,
	getUserId: ((unknown) -> unknown)?,
	isPresent: ((unknown) -> unknown)?,
	onRollback: ((Rollback) -> ())?,
	onComplete: ((Completion) -> ())?,
	onReserved: ((ReservedServer) -> unknown)?,
	maxAttempts: number?,
	baseBackoffSeconds: number?,
	reconciliationSeconds: number?,
}
export type ErrorCode =
	"INVALID_ARGUMENT"
	| "BUSY"
	| "STORE_UNAVAILABLE"
	| "RESERVE_FAILED"
	| "RESERVATION_CALLBACK_FAILED"
	| "TELEPORT_FAILED"
	| "CLEANED"
export type Operation = "start" | "finish" | "cleanup"
export type TeleportError = { code: ErrorCode, operation: Operation, failureClass: FailureClass }
export type StartOutcome = { status: "Initialized", attemptCount: number, memberCount: number }

type Adapter = {
	reserveServer: (self: Adapter, placeId: number) -> any,
	teleportReserved: (
		self: Adapter,
		placeId: number,
		accessCode: string,
		players: { unknown },
		routingData: unknown
	) -> any,
	connectInitFailed: (self: Adapter, listener: (unknown, FailureClass, unknown) -> ()) -> any,
}
type Store = {
	markTeleporting: (self: Store, ticketId: unknown, nowValue: unknown) -> any,
	recordRetry: (self: Store, ticketId: unknown, nowValue: unknown) -> any,
	markTerminal: (self: Store, ticketId: unknown, reason: unknown, nowValue: unknown) -> any,
}
type MemberState = "Pending" | "Failed" | "Departed"
type Session = {
	ticketId: string,
	placeId: number,
	accessCode: string,
	playersByUserId: { [number]: unknown },
	orderedUserIds: { number },
	attemptIdsByUserId: { [number]: string },
	nextAttemptSequence: number,
	attemptsByUserId: { [number]: number },
	retryingUserIds: { [number]: boolean },
	attemptCount: number,
	memberStates: { [number]: MemberState },
	initializationSucceeded: boolean,
	reconciling: boolean,
	reconciled: boolean,
}
type ServiceData = {
	adapter: Adapter,
	store: Store,
	now: () -> unknown,
	wait: (number) -> (),
	schedule: (() -> ()) -> unknown,
	getUserId: (unknown) -> unknown,
	isPresent: (unknown) -> unknown,
	onRollback: (Rollback) -> (),
	onComplete: (Completion) -> (),
	onReserved: (ReservedServer) -> unknown,
	maxAttempts: number,
	baseBackoffSeconds: number,
	reconciliationPolls: number,
	sessions: { [string]: Session },
	ticketByUserId: { [number]: string },
	connection: any,
	activeWorkerCount: number,
	cleanupRunning: boolean,
	closing: boolean,
	cleaned: boolean,
}

local DEFAULT_MAX_ATTEMPTS = 3
local MAX_ATTEMPTS = 5
local MAX_BACKOFF_SECONDS = 1
local DEFAULT_RECONCILIATION_SECONDS = 20
local MAX_RECONCILIATION_SECONDS = 30
local MIN_RECONCILIATION_SECONDS = 0.25
local RECONCILIATION_POLL_SECONDS = 0.25

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local SafeTeleportService = {}

local function failure<T>(code: ErrorCode, operation: Operation, failureClass: FailureClass): Result.Failure<TeleportError>
	return Result.err(table.freeze({ code = code, operation = operation, failureClass = failureClass }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_SAFE_TELEPORT][code=INVALID_CONTEXT]", 0)
	end
	return data :: ServiceData
end

local function beginWorker(data: ServiceData): boolean
	if data.closing or data.cleaned then
		return false
	end
	data.activeWorkerCount += 1
	return true
end

local function runOwnedWorker(data: ServiceData, callback: () -> ())
	local called, callbackError = pcall(callback)
	data.activeWorkerCount -= 1
	if not called then
		error(callbackError, 0)
	end
end

local function currentTime(data: ServiceData): number?
	local called, value = pcall(data.now)
	return if called
			and type(value) == "number"
			and Validation.isSafeInteger(value :: number)
			and value >= 0
		then value :: number
		else nil
end

local function resultSucceeded(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function resultFailureClass(value: unknown): FailureClass
	if
		type(value) == "table"
		and type((value :: any).error) == "table"
		and (value :: any).error.failureClass == "Terminal"
	then
		return "Terminal"
	end
	return "Retryable"
end

local function readUserId(data: ServiceData, player: unknown): number?
	local called, value = pcall(data.getUserId, player)
	return if called
			and type(value) == "number"
			and Validation.isSafeInteger(value :: number)
			and value > 0
		then value :: number
		else nil
end

local function playerIsPresent(data: ServiceData, player: unknown): boolean
	local called, value = pcall(data.isPresent, player)
	return called and value == true
end

local function detachSession(data: ServiceData, session: Session)
	data.sessions[session.ticketId] = nil
	for _, userId in session.orderedUserIds do
		if data.ticketByUserId[userId] == session.ticketId then
			data.ticketByUserId[userId] = nil
		end
	end
	session.accessCode = ""
	table.clear(session.playersByUserId)
	table.clear(session.attemptIdsByUserId)
	table.clear(session.retryingUserIds)
	table.clear(session.memberStates)
end

local function rollbackSnapshot(session: Session): Rollback
	local failed: { number } = {}
	local present: { number } = {}
	local departed: { number } = {}
	for _, userId in session.orderedUserIds do
		local state = session.memberStates[userId]
		if state == "Failed" then
			table.insert(failed, userId)
		end
		if state == "Departed" then
			table.insert(departed, userId)
		else
			table.insert(present, userId)
		end
	end
	return table.freeze({
		ticketId = session.ticketId,
		failedUserIds = table.freeze(failed),
		presentUserIds = table.freeze(present),
		departedUserIds = table.freeze(departed),
		partial = #departed > 0,
	})
end

local function notifyStableRollback(data: ServiceData, session: Session, terminalReason: string?)
	local snapshot = rollbackSnapshot(session)
	pcall(data.onRollback, snapshot)
	if not snapshot.partial then
		local nowValue = currentTime(data)
		if nowValue ~= nil then
			pcall(
				data.store.markTerminal,
				data.store,
				session.ticketId,
				terminalReason or "TELEPORT_INIT_FAILED",
				nowValue
			)
		end
		detachSession(data, session)
	end
end

local function runReconciliation(data: ServiceData, session: Session, terminalReason: string?)
	if data.closing or data.cleaned or data.sessions[session.ticketId] ~= session or session.reconciled then
		session.reconciling = false
		return
	end
	for poll = 0, data.reconciliationPolls do
		local unresolved = 0
		for _, userId in session.orderedUserIds do
			local state = session.memberStates[userId]
			if state == "Pending" or state == "Failed" then
				local player = session.playersByUserId[userId]
				if player == nil or not playerIsPresent(data, player) then
					session.memberStates[userId] = "Departed"
				else
					-- Even a member whose initialization failure was already
					-- classified can still leave after the signal. Observe the full
					-- bounded window before publishing the stable partition.
					unresolved += 1
				end
			end
		end
		if unresolved == 0 then
			break
		elseif poll == data.reconciliationPolls then
			for _, userId in session.orderedUserIds do
				if session.memberStates[userId] == "Pending" then
					session.memberStates[userId] = "Failed"
				end
			end
			break
		end
		pcall(data.wait, RECONCILIATION_POLL_SECONDS)
		if data.closing or data.cleaned or data.sessions[session.ticketId] ~= session then
			session.reconciling = false
			return
		end
	end
	session.reconciling = false
	session.reconciled = true
	local departedUserIds: { number } = {}
	local failedCount = 0
	for _, userId in session.orderedUserIds do
		if session.memberStates[userId] == "Departed" then
			table.insert(departedUserIds, userId)
		elseif session.memberStates[userId] == "Failed" then
			failedCount += 1
		end
	end
	if session.initializationSucceeded and failedCount == 0 and #departedUserIds == #session.orderedUserIds then
		-- A successful initialization whose entire roster left is the expected
		-- completion path, not a partial rollback. Keep rollback notifications
		-- exclusively for a stable Failed/Departed partition.
		pcall(
			data.onComplete,
			table.freeze({
				ticketId = session.ticketId,
				departedUserIds = table.freeze(departedUserIds),
			})
		)
		detachSession(data, session)
		return
	end
	notifyStableRollback(data, session, terminalReason)
end

local function reconcileSession(data: ServiceData, session: Session, terminalReason: string?)
	if
		data.closing
		or data.cleaned
		or data.sessions[session.ticketId] ~= session
		or session.reconciled
		or session.reconciling
	then
		return
	end
	session.reconciling = true
	if not beginWorker(data) then
		session.reconciling = false
		return
	end
	local pending = true
	local function callback()
		if not pending then
			return
		end
		pending = false
		runOwnedWorker(data, function()
			if data.closing or data.cleaned then
				session.reconciling = false
				return
			end
			runReconciliation(data, session, terminalReason)
		end)
	end
	local called, scheduled = pcall(data.schedule, callback)
	if not called or scheduled == false then
		-- Scheduling is an optimization and must not erase the only rollback path.
		callback()
	end
end

local function recordRetry(data: ServiceData, ticketId: string)
	local nowValue = currentTime(data)
	if nowValue ~= nil then
		pcall(data.store.recordRetry, data.store, ticketId, nowValue)
	end
end

local function teleportCall(data: ServiceData, session: Session, players: { unknown }): (boolean, FailureClass)
	local attemptId = `attempt:{session.nextAttemptSequence}`
	session.nextAttemptSequence += 1
	local routing = TravelProtocol.match(session.ticketId, attemptId)
	if not routing.ok then
		return false, "Terminal"
	end
	for _, player in players do
		local userId = readUserId(data, player)
		if userId == nil or session.playersByUserId[userId] ~= player then
			return false, "Terminal"
		end
		session.attemptIdsByUserId[userId] = attemptId
	end
	local called, resultValue =
		pcall(data.adapter.teleportReserved, data.adapter, session.placeId, session.accessCode, players, routing.value)
	if called and resultSucceeded(resultValue) then
		return true, "Retryable"
	end
	return false, if called then resultFailureClass(resultValue) else "Retryable"
end

local function retryInitFailure(
	data: ServiceData,
	session: Session,
	userId: number,
	player: unknown,
	failureClass: FailureClass
)
	if
		data.closing
		or data.cleaned
		or data.sessions[session.ticketId] ~= session
		or session.playersByUserId[userId] ~= player
	then
		return
	end
	if session.reconciled or session.memberStates[userId] ~= "Pending" or session.retryingUserIds[userId] then
		return
	end
	local present = playerIsPresent(data, player)
	if data.closing or data.cleaned or not present then
		return
	end
	session.retryingUserIds[userId] = true
	local function finishRetry()
		session.retryingUserIds[userId] = nil
	end
	local attempts = session.attemptsByUserId[userId] or 1
	local currentClass = failureClass
	while currentClass == "Retryable" and attempts < data.maxAttempts do
		recordRetry(data, session.ticketId)
		if data.closing or data.cleaned or data.sessions[session.ticketId] ~= session then
			finishRetry()
			return
		end
		local delay = math.min(data.baseBackoffSeconds * (2 ^ (attempts - 1)), MAX_BACKOFF_SECONDS)
		pcall(data.wait, delay)
		if
			data.closing
			or data.cleaned
			or data.sessions[session.ticketId] ~= session
			or session.playersByUserId[userId] ~= player
		then
			finishRetry()
			return
		end
		present = playerIsPresent(data, player)
		if
			data.closing
			or data.cleaned
			or data.sessions[session.ticketId] ~= session
			or session.playersByUserId[userId] ~= player
			or not present
		then
			finishRetry()
			return
		end
		attempts += 1
		session.attemptsByUserId[userId] = attempts
		session.attemptCount += 1
		local succeeded, nextClass = teleportCall(data, session, { player })
		if
			data.closing
			or data.cleaned
			or data.sessions[session.ticketId] ~= session
			or session.playersByUserId[userId] ~= player
		then
			finishRetry()
			return
		end
		if succeeded then
			session.initializationSucceeded = true
			finishRetry()
			reconcileSession(data, session, nil)
			return
		end
		currentClass = nextClass
	end
	finishRetry()
	session.memberStates[userId] = "Failed"
	reconcileSession(data, session, nil)
end

local function handleInitFailure(data: ServiceData, player: unknown, failureClassValue: unknown, contextValue: unknown)
	if data.closing or data.cleaned then
		return
	end
	local userId = readUserId(data, player)
	if userId == nil then
		return
	end
	local ticketId = data.ticketByUserId[userId]
	local session = if ticketId == nil then nil else data.sessions[ticketId]
	if session == nil or session.reconciled then
		return
	end
	if type(contextValue) ~= "table" or getmetatable(contextValue :: any) ~= nil then
		return
	end
	local context = contextValue :: any
	local routing = TravelProtocol.validateRoutingData(context.routingData)
	if
		context.placeId ~= session.placeId
		or not routing.ok
		or routing.value.kind ~= "Match"
		or routing.value.ticketId ~= session.ticketId
		or routing.value.attemptId ~= session.attemptIdsByUserId[userId]
	then
		return
	end
	local failureClass: FailureClass = if failureClassValue == "Terminal" then "Terminal" else "Retryable"
	retryInitFailure(data, session, userId, player, failureClass)
end

function Methods.start(
	self: Service,
	ticketIdValue: unknown,
	matchPlaceIdValue: unknown,
	playersValue: unknown
): Result.Result<StartOutcome, TeleportError>
	local data = requireData(self)
	if data.closing or data.cleaned then
		return failure("CLEANED", "start", "Terminal")
	end
	local ticketId = TravelProtocol.validateOpaqueId(ticketIdValue, "ticket")
	if
		not ticketId.ok
		or type(matchPlaceIdValue) ~= "number"
		or not Validation.isSafeInteger(matchPlaceIdValue :: number)
		or matchPlaceIdValue <= 0
		or type(playersValue) ~= "table"
		or getmetatable(playersValue :: any) ~= nil
		or #playersValue < 1
		or #playersValue > 4
	then
		return failure("INVALID_ARGUMENT", "start", "Terminal")
	end
	if data.sessions[ticketId.value] ~= nil then
		return failure("BUSY", "start", "Retryable")
	end
	local players = playersValue :: { unknown }
	local orderedUserIds: { number } = table.create(#players)
	local playersByUserId: { [number]: unknown } = {}
	for index, player in players do
		local id = readUserId(data, player)
		if
			id == nil
			or playersByUserId[id] ~= nil
			or data.ticketByUserId[id] ~= nil
			or not playerIsPresent(data, player)
		then
			return failure("INVALID_ARGUMENT", "start", "Terminal")
		end
		orderedUserIds[index] = id
		playersByUserId[id] = player
	end
	local nowValue = currentTime(data)
	if nowValue == nil then
		return failure("INVALID_ARGUMENT", "start", "Terminal")
	end
	local marked, markResult = pcall(data.store.markTeleporting, data.store, ticketId.value, nowValue)
	if not marked or not resultSucceeded(markResult) then
		return failure("STORE_UNAVAILABLE", "start", "Retryable")
	end

	local reservation: any = nil
	local reserveClass: FailureClass = "Retryable"
	local attemptCount = 0
	for attempt = 1, data.maxAttempts do
		attemptCount = attempt
		local called, reserveResult = pcall(data.adapter.reserveServer, data.adapter, matchPlaceIdValue)
		if called and resultSucceeded(reserveResult) then
			local candidate = (reserveResult :: any).value
			if
				type(candidate) == "table"
				and type(candidate.accessCode) == "string"
				and #candidate.accessCode >= 1
				and #candidate.accessCode <= 200
				and type(candidate.privateServerId) == "string"
				and #candidate.privateServerId <= 200
			then
				reservation = candidate
				break
			end
		end
		reserveClass = if called then resultFailureClass(reserveResult) else "Retryable"
		if reserveClass == "Terminal" or attempt == data.maxAttempts then
			pcall(data.store.markTerminal, data.store, ticketId.value, "RESERVE_FAILED", nowValue)
			return failure("RESERVE_FAILED", "start", reserveClass)
		end
		recordRetry(data, ticketId.value)
		pcall(data.wait, math.min(data.baseBackoffSeconds * (2 ^ (attempt - 1)), MAX_BACKOFF_SECONDS))
	end
	if reservation == nil then
		return failure("RESERVE_FAILED", "start", reserveClass)
	end

	local session: Session = {
		ticketId = ticketId.value,
		placeId = matchPlaceIdValue :: number,
		accessCode = reservation.accessCode,
		playersByUserId = playersByUserId,
		orderedUserIds = orderedUserIds,
		attemptIdsByUserId = {},
		nextAttemptSequence = 1,
		attemptsByUserId = {},
		retryingUserIds = {},
		attemptCount = attemptCount,
		memberStates = {},
		initializationSucceeded = false,
		reconciling = false,
		reconciled = false,
	}
	for _, id in orderedUserIds do
		session.attemptsByUserId[id] = 1
		session.memberStates[id] = "Pending"
		data.ticketByUserId[id] = session.ticketId
	end
	data.sessions[session.ticketId] = session
	local reservedSnapshot: ReservedServer = table.freeze({
		ticketId = session.ticketId,
		placeId = session.placeId,
		privateServerId = reservation.privateServerId,
		accessCode = session.accessCode,
		orderedUserIds = table.freeze(table.clone(orderedUserIds)),
	})
	local callbackCalled, callbackResult = pcall(data.onReserved, reservedSnapshot)
	local callbackSucceeded = callbackCalled
		and (callbackResult == nil or callbackResult == true or resultSucceeded(callbackResult))
	if not callbackSucceeded then
		for _, id in orderedUserIds do
			session.memberStates[id] = "Failed"
		end
		pcall(data.store.markTerminal, data.store, session.ticketId, "RESERVATION_CALLBACK_FAILED", nowValue)
		reconcileSession(data, session, "RESERVATION_CALLBACK_FAILED")
		return failure("RESERVATION_CALLBACK_FAILED", "start", "Terminal")
	end

	for attempt = 1, data.maxAttempts do
		session.attemptCount += 1
		local succeeded, failureClass = teleportCall(data, session, players)
		if succeeded then
			session.initializationSucceeded = true
			reconcileSession(data, session, nil)
			return Result.ok(
				table.freeze({ status = "Initialized", attemptCount = session.attemptCount, memberCount = #players })
			)
		end
		if failureClass == "Terminal" or attempt == data.maxAttempts then
			for _, id in orderedUserIds do
				session.memberStates[id] = "Failed"
			end
			reconcileSession(data, session, "TELEPORT_FAILED")
			return failure("TELEPORT_FAILED", "start", failureClass)
		end
		recordRetry(data, session.ticketId)
		pcall(data.wait, math.min(data.baseBackoffSeconds * (2 ^ (attempt - 1)), MAX_BACKOFF_SECONDS))
	end
	return failure("TELEPORT_FAILED", "start", "Retryable")
end

function Methods.finish(self: Service, ticketIdValue: unknown): Result.Result<boolean, TeleportError>
	local data = requireData(self)
	if data.closing or data.cleaned then
		return failure("CLEANED", "finish", "Terminal")
	end
	local ticketId = TravelProtocol.validateOpaqueId(ticketIdValue, "ticket")
	if not ticketId.ok then
		return failure("INVALID_ARGUMENT", "finish", "Terminal")
	end
	local session = data.sessions[ticketId.value]
	if session == nil then
		return Result.ok(false)
	end
	detachSession(data, session)
	return Result.ok(true)
end

function Methods.getMetrics(self: Service): { activeSessionCount: number, activeMemberCount: number, cleaned: boolean }
	local data = requireData(self)
	local sessions = 0
	local members = 0
	for _, session in data.sessions do
		sessions += 1
		members += #session.orderedUserIds
	end
	return table.freeze({ activeSessionCount = sessions, activeMemberCount = members, cleaned = data.cleaned })
end

function Methods.cleanup(self: Service): Result.Result<boolean, TeleportError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	if data.cleanupRunning then
		return failure("BUSY", "cleanup", "Retryable")
	end
	data.closing = true
	data.cleanupRunning = true
	local connection = data.connection
	data.connection = nil
	if connection ~= nil then
		pcall(function()
			connection:Disconnect()
		end)
	end
	data.cleanupRunning = false
	if data.activeWorkerCount > 0 then
		return failure("BUSY", "cleanup", "Retryable")
	end
	data.cleaned = true
	for _, session in data.sessions do
		session.accessCode = ""
		table.clear(session.playersByUserId)
		table.clear(session.attemptIdsByUserId)
	end
	table.clear(data.sessions)
	table.clear(data.ticketByUserId)
	return Result.ok(true)
end

function SafeTeleportService.new(
	storeValue: unknown,
	adapterValue: unknown,
	dependenciesValue: Dependencies?
): Result.Result<Service, TeleportError>
	if
		type(storeValue) ~= "table"
		or type((storeValue :: any).markTeleporting) ~= "function"
		or type((storeValue :: any).recordRetry) ~= "function"
		or type((storeValue :: any).markTerminal) ~= "function"
		or type(adapterValue) ~= "table"
		or type((adapterValue :: any).reserveServer) ~= "function"
		or type((adapterValue :: any).teleportReserved) ~= "function"
		or type((adapterValue :: any).connectInitFailed) ~= "function"
		or (
			dependenciesValue ~= nil
			and (type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil)
		)
	then
		return failure("INVALID_ARGUMENT", "start", "Terminal")
	end
	local dependencies = dependenciesValue or {}
	local maxAttempts = dependencies.maxAttempts or DEFAULT_MAX_ATTEMPTS
	local backoff = dependencies.baseBackoffSeconds or 0.05
	local reconciliationSeconds = dependencies.reconciliationSeconds or DEFAULT_RECONCILIATION_SECONDS
	if
		(dependencies.now ~= nil and type(dependencies.now) ~= "function")
		or (dependencies.wait ~= nil and type(dependencies.wait) ~= "function")
		or (dependencies.schedule ~= nil and type(dependencies.schedule) ~= "function")
		or (dependencies.getUserId ~= nil and type(dependencies.getUserId) ~= "function")
		or (dependencies.isPresent ~= nil and type(dependencies.isPresent) ~= "function")
		or (dependencies.onRollback ~= nil and type(dependencies.onRollback) ~= "function")
		or (dependencies.onComplete ~= nil and type(dependencies.onComplete) ~= "function")
		or (dependencies.onReserved ~= nil and type(dependencies.onReserved) ~= "function")
		or type(maxAttempts) ~= "number"
		or not Validation.isSafeInteger(maxAttempts)
		or maxAttempts < 1
		or maxAttempts > MAX_ATTEMPTS
		or type(backoff) ~= "number"
		or not Validation.isFiniteNumber(backoff)
		or backoff < 0
		or backoff > MAX_BACKOFF_SECONDS
		or type(reconciliationSeconds) ~= "number"
		or not Validation.isFiniteNumber(reconciliationSeconds)
		or reconciliationSeconds < MIN_RECONCILIATION_SECONDS
		or reconciliationSeconds > MAX_RECONCILIATION_SECONDS
	then
		return failure("INVALID_ARGUMENT", "start", "Terminal")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	local data: ServiceData = {
		adapter = adapterValue :: Adapter,
		store = storeValue :: Store,
		now = dependencies.now or os.time,
		wait = dependencies.wait or task.wait,
		schedule = dependencies.schedule or function(callback: () -> ()): unknown
			return task.spawn(callback)
		end,
		getUserId = dependencies.getUserId or function(player: unknown): unknown
			return if typeof(player) == "Instance" and (player :: Instance):IsA("Player")
				then (player :: Player).UserId
				else nil
		end,
		isPresent = dependencies.isPresent or function(player: unknown): unknown
			return typeof(player) == "Instance"
				and (player :: Instance):IsA("Player")
				and (player :: Player).Parent ~= nil
		end,
		onRollback = dependencies.onRollback or function(_snapshot: Rollback) end,
		onComplete = dependencies.onComplete or function(_snapshot: Completion) end,
		onReserved = dependencies.onReserved or function(_snapshot: ReservedServer): unknown
			return true
		end,
		maxAttempts = maxAttempts,
		baseBackoffSeconds = backoff,
		reconciliationPolls = math.ceil(reconciliationSeconds / RECONCILIATION_POLL_SECONDS),
		sessions = {},
		ticketByUserId = {},
		connection = nil,
		activeWorkerCount = 0,
		cleanupRunning = false,
		closing = false,
		cleaned = false,
	}
	local connected, connection = pcall(
		(adapterValue :: any).connectInitFailed,
		adapterValue,
		function(player, failureClass, context)
			if not beginWorker(data) then
				return
			end
			runOwnedWorker(data, function()
				handleInitFailure(data, player, failureClass, context)
			end)
		end
	)
	if not connected or connection == nil or type((connection :: any).Disconnect) ~= "function" then
		return failure("INVALID_ARGUMENT", "start", "Terminal")
	end
	data.connection = connection
	DATA[service] = data
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(SafeTeleportService)
