--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyProtocol = require(ReplicatedStorage.Shared.lobby.LobbyProtocol)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Dependencies = {
	clock: () -> unknown,
	schedule: (() -> ()) -> unknown,
	activeRoutes: any,
	teleportAdapter: any,
	profileTransfer: any,
	getPlayer: (number) -> unknown,
	isPresent: (number) -> unknown,
	makeAttemptId: () -> unknown,
	developmentSimulation: boolean?,
}

export type ErrorCode = "INVALID_DEPENDENCIES" | "INVALID_ARGUMENT" | "CLEANED" | "BUSY" | "TRANSFER_FAILED"
export type ReconnectError = { code: ErrorCode, operation: string }

type ReceiptEntry = {
	transactionId: string,
	receipt: LobbyProtocol.ReconnectReceipt,
}

type ReceiptLedger = {
	byId: { [string]: LobbyProtocol.ReconnectReceipt },
	ring: { ReceiptEntry? },
	count: number,
	nextIndex: number,
}

type PendingReconnect = {
	userId: number,
	player: unknown,
	handle: unknown,
	transactionId: string,
	view: LobbyProtocol.ActiveRouteView,
	startedAt: number,
	rollbackRequested: boolean,
	departureObserved: boolean,
	destinationPlaceId: number,
	routeId: string,
	attemptId: string,
}

type ScheduledReconnect = {
	transactionId: string,
	receipt: LobbyProtocol.ReconnectReceipt,
	cancelled: boolean,
	workerState: "Queued" | "Running" | "Finished",
}

type ServiceData = {
	dependencies: Dependencies,
	receiptsByUserId: { [number]: ReceiptLedger },
	pendingByUserId: { [number]: PendingReconnect },
	pendingByPlayer: { [any]: PendingReconnect },
	cachedRouteByUserId: { [number]: any },
	scheduledByUserId: { [number]: ScheduledReconnect },
	connection: any?,
	shutdownRequested: boolean,
	runningOperations: number,
	cleaned: boolean,
}

local Methods = {}
Methods.__index = Methods
export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local MAX_RECEIPTS = 32
local INITIALIZATION_TIMEOUT_SECONDS = 30
local LobbyReconnectService = { INITIALIZATION_TIMEOUT_SECONDS = INITIALIZATION_TIMEOUT_SECONDS }

local function failure<T>(code: ErrorCode, operation: string): Result.Failure<ReconnectError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_LOBBY_RECONNECT][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and value > 0
end

local function resultOk(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function currentTime(data: ServiceData): number?
	local called, value = pcall(data.dependencies.clock)
	return if called
			and type(value) == "number"
			and Validation.isSafeInteger(value :: number)
			and value >= 0
		then value :: number
		else nil
end

local function routeView(route: any?): LobbyProtocol.ActiveRouteView
	local candidate: LobbyProtocol.ActiveRouteView = if route == nil
		then { version = LobbyProtocol.VERSION, status = "None", matchId = nil, expiresAt = nil }
		else {
			version = LobbyProtocol.VERSION,
			status = "Available",
			matchId = route.matchId,
			expiresAt = route.expiresAt,
		}
	local validated = LobbyProtocol.validateActiveRoute(candidate)
	if not validated.ok then
		error("[ATD_LOBBY_RECONNECT][code=INVALID_VIEW]", 0)
	end
	return validated.value
end

local function findRoute(data: ServiceData, userId: number): any?
	local nowValue = currentTime(data)
	if nowValue == nil then
		return nil
	end
	local called, resultValue =
		pcall(data.dependencies.activeRoutes.find, data.dependencies.activeRoutes, userId, nowValue)
	return if called
			and type(resultValue) == "table"
			and (resultValue :: any).ok == true
		then (resultValue :: any).value
		else nil
end

local function ledger(data: ServiceData, userId: number): ReceiptLedger
	local value = data.receiptsByUserId[userId]
	if value == nil then
		value = { byId = {}, ring = {}, count = 0, nextIndex = 1 }
		data.receiptsByUserId[userId] = value
	end
	return value
end

local function storeReceipt(data: ServiceData, userId: number, receipt: LobbyProtocol.ReconnectReceipt)
	local value = ledger(data, userId)
	if value.byId[receipt.transactionId] ~= nil then
		return
	end
	if value.count == MAX_RECEIPTS then
		local evicted = value.ring[value.nextIndex]
		if evicted ~= nil then
			value.byId[evicted.transactionId] = nil
		end
	else
		value.count += 1
	end
	value.ring[value.nextIndex] = { transactionId = receipt.transactionId, receipt = receipt }
	value.byId[receipt.transactionId] = receipt
	value.nextIndex = (value.nextIndex % MAX_RECEIPTS) + 1
end

local function makeReceipt(
	transactionId: string,
	status: LobbyProtocol.ReconnectStatus,
	view: LobbyProtocol.ActiveRouteView
): LobbyProtocol.ReconnectReceipt
	local candidate: LobbyProtocol.ReconnectReceipt = table.freeze({
		transactionId = transactionId,
		status = status,
		route = view,
	})
	local validated = LobbyProtocol.validateReconnectReceipt(candidate)
	if not validated.ok then
		error("[ATD_LOBBY_RECONNECT][code=INVALID_RECEIPT]", 0)
	end
	return validated.value
end

local function receipt(
	data: ServiceData,
	userId: number,
	transactionId: string,
	status: LobbyProtocol.ReconnectStatus,
	view: LobbyProtocol.ActiveRouteView
): LobbyProtocol.ReconnectReceipt
	local value = makeReceipt(transactionId, status, view)
	if not data.cleaned then
		storeReceipt(data, userId, value)
	end
	return value
end

local function replaceReceipt(data: ServiceData, pending: PendingReconnect, status: LobbyProtocol.ReconnectStatus)
	local existing = data.receiptsByUserId[pending.userId]
	if existing == nil or existing.byId[pending.transactionId] == nil then
		return
	end
	local validated = LobbyProtocol.validateReconnectReceipt({
		transactionId = pending.transactionId,
		status = status,
		route = pending.view,
	})
	if not validated.ok then
		return
	end
	existing.byId[pending.transactionId] = validated.value
	for index, entry in existing.ring do
		if entry ~= nil and entry.transactionId == pending.transactionId then
			existing.ring[index] = { transactionId = pending.transactionId, receipt = validated.value }
			break
		end
	end
end

local function failPending(data: ServiceData, player: unknown): boolean
	local pending = data.pendingByPlayer[player :: any]
	if pending == nil then
		return false
	end
	pending.rollbackRequested = true
	local called, rolledBack =
		pcall(data.dependencies.profileTransfer.rollback, data.dependencies.profileTransfer, pending.handle)
	replaceReceipt(data, pending, "Failed")
	if not called or not resultOk(rolledBack) then
		return false
	end
	data.pendingByPlayer[player :: any] = nil
	data.pendingByUserId[pending.userId] = nil
	return true
end

local function completePending(data: ServiceData, userId: number): boolean
	local pending = data.pendingByUserId[userId]
	if pending == nil then
		return false
	end
	local called, committed =
		pcall(data.dependencies.profileTransfer.commit, data.dependencies.profileTransfer, pending.handle)
	if not called or not resultOk(committed) then
		return false
	end
	data.pendingByPlayer[pending.player :: any] = nil
	data.pendingByUserId[userId] = nil
	return true
end

local function matchesInitFailure(pending: PendingReconnect, contextValue: unknown): boolean
	if type(contextValue) ~= "table" or getmetatable(contextValue :: any) ~= nil then
		return false
	end
	local context = contextValue :: any
	local routing = TravelProtocol.validateRoutingData(context.routingData)
	return context.placeId == pending.destinationPlaceId
		and routing.ok
		and routing.value.kind == "Rejoin"
		and routing.value.routeId == pending.routeId
		and routing.value.attemptId == pending.attemptId
end

function Methods.getView(
	self: Service,
	userIdValue: unknown
): Result.Result<LobbyProtocol.ActiveRouteView, ReconnectError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "getView")
	end
	if not validUserId(userIdValue) then
		return failure("INVALID_ARGUMENT", "getView")
	end
	local userId = userIdValue :: number
	local route = findRoute(data, userId)
	if data.cleaned then
		return failure("CLEANED", "getView")
	end
	data.cachedRouteByUserId[userId] = route
	return Result.ok(routeView(route))
end

local function performReconnect(
	data: ServiceData,
	userId: number,
	transactionId: string,
	route: any?,
	scheduled: ScheduledReconnect?
): LobbyProtocol.ReconnectReceipt
	local view = routeView(route)
	if data.shutdownRequested then
		return makeReceipt(transactionId, "Failed", view)
	end
	if data.pendingByUserId[userId] ~= nil then
		return receipt(data, userId, transactionId, "Failed", view)
	end
	if route == nil then
		return receipt(data, userId, transactionId, "Unavailable", view)
	end
	local observedAt = currentTime(data)
	if observedAt == nil then
		return receipt(data, userId, transactionId, "Failed", view)
	end
	if type(route.expiresAt) ~= "number" or route.expiresAt <= observedAt then
		data.cachedRouteByUserId[userId] = nil
		return receipt(data, userId, transactionId, "Stale", routeView(nil))
	end
	local presentCalled, present = pcall(data.dependencies.isPresent, userId)
	local playerCalled, player = pcall(data.dependencies.getPlayer, userId)
	if not presentCalled or present ~= true or not playerCalled or player == nil then
		return receipt(data, userId, transactionId, "Failed", view)
	end
	local attemptCalled, attemptValue = pcall(data.dependencies.makeAttemptId)
	local attemptId = if attemptCalled then TravelProtocol.validateOpaqueId(attemptValue, "attempt") else nil
	if attemptId == nil or not attemptId.ok then
		return receipt(data, userId, transactionId, "Failed", view)
	end
	local routing = TravelProtocol.rejoin(route.routeId, attemptId.value)
	if not routing.ok then
		return receipt(data, userId, transactionId, "Stale", routeView(nil))
	end
	local preparedCalled, prepared =
		pcall(data.dependencies.profileTransfer.prepare, data.dependencies.profileTransfer, { userId })
	if not preparedCalled or type(prepared) ~= "table" or (prepared :: any).ok ~= true then
		return receipt(data, userId, transactionId, "Failed", view)
	end
	local handle = (prepared :: any).value.handle
	local pending: PendingReconnect = {
		userId = userId,
		player = player,
		handle = handle,
		transactionId = transactionId,
		view = view,
		startedAt = observedAt,
		rollbackRequested = false,
		departureObserved = false,
		destinationPlaceId = route.destinationPlaceId,
		routeId = route.routeId,
		attemptId = attemptId.value,
	}
	-- Publish ownership immediately after prepare returns. From this point onward,
	-- cleanup must either join this operation or retain the handle until a
	-- successful rollback/commit proves that the released profile was settled.
	data.pendingByUserId[userId] = pending
	data.pendingByPlayer[player :: any] = pending
	local stillPresentCalled, stillPresent = pcall(data.dependencies.isPresent, userId)
	if
		data.shutdownRequested
		or (scheduled ~= nil and (scheduled.cancelled or data.scheduledByUserId[userId] ~= scheduled))
		or not stillPresentCalled
		or stillPresent ~= true
	then
		failPending(data, player)
		return makeReceipt(transactionId, "Failed", view)
	end
	local startedAt = currentTime(data)
	if startedAt == nil then
		failPending(data, player)
		return receipt(data, userId, transactionId, "Failed", view)
	end
	if route.expiresAt <= startedAt then
		data.cachedRouteByUserId[userId] = nil
		failPending(data, player)
		return receipt(data, userId, transactionId, "Stale", routeView(nil))
	end
	pending.startedAt = startedAt
	local teleportedCalled, teleported = pcall(
		data.dependencies.teleportAdapter.teleportReserved,
		data.dependencies.teleportAdapter,
		route.destinationPlaceId,
		route.reservedServerAccessCode,
		{ player },
		routing.value
	)
	local initialized = teleportedCalled and type(teleported) == "table" and (teleported :: any).ok == true
	local status: LobbyProtocol.ReconnectStatus = "Failed"
	if
		initialized
		and not data.shutdownRequested
		and data.dependencies.developmentSimulation ~= true
		and data.pendingByUserId[userId] == pending
	then
		status = "Initializing"
	else
		failPending(data, player)
	end
	return receipt(data, userId, transactionId, status, view)
end

local function beginReconnect(
	data: ServiceData,
	userIdValue: unknown,
	transactionIdValue: unknown
): Result.Result<LobbyProtocol.ReconnectReceipt, ReconnectError>
	if data.cleaned or data.shutdownRequested then
		return failure("CLEANED", "beginReconnect")
	end
	local transactionId = Ids.validateTransactionId(transactionIdValue)
	if not validUserId(userIdValue) or not transactionId.ok then
		return failure("INVALID_ARGUMENT", "beginReconnect")
	end
	local userId = userIdValue :: number
	local previous = data.receiptsByUserId[userId]
	local replay = if previous == nil then nil else previous.byId[transactionId.value]
	if replay ~= nil then
		return Result.ok(replay)
	end
	local scheduled = data.scheduledByUserId[userId]
	if scheduled ~= nil then
		if scheduled.cancelled then
			return Result.ok(makeReceipt(transactionId.value, "Failed", routeView(data.cachedRouteByUserId[userId])))
		end
		if scheduled.transactionId == transactionId.value then
			return Result.ok(scheduled.receipt)
		end
		return Result.ok(
			receipt(data, userId, transactionId.value, "Failed", routeView(data.cachedRouteByUserId[userId]))
		)
	end
	local route = data.cachedRouteByUserId[userId]
	local view = routeView(route)
	if route == nil then
		return Result.ok(receipt(data, userId, transactionId.value, "Unavailable", view))
	end
	local now = currentTime(data)
	if data.shutdownRequested then
		return failure("CLEANED", "beginReconnect")
	end
	if now == nil then
		return Result.ok(receipt(data, userId, transactionId.value, "Failed", view))
	end
	if type(route.expiresAt) ~= "number" or route.expiresAt <= now then
		data.cachedRouteByUserId[userId] = nil
		return Result.ok(receipt(data, userId, transactionId.value, "Stale", routeView(nil)))
	end
	local initial = makeReceipt(transactionId.value, "Initializing", view)
	local scheduledReconnect: ScheduledReconnect = {
		transactionId = transactionId.value,
		receipt = initial,
		cancelled = false,
		workerState = "Queued",
	}
	data.scheduledByUserId[userId] = scheduledReconnect
	local scheduling = true
	local ranInline = false
	local scheduledCalled, scheduleResult = pcall(data.dependencies.schedule, function()
		if scheduling then
			ranInline = true
			return
		end
		if
			data.cleaned
			or data.shutdownRequested
			or scheduledReconnect.cancelled
			or scheduledReconnect.workerState ~= "Queued"
			or data.scheduledByUserId[userId] ~= scheduledReconnect
		then
			scheduledReconnect.workerState = "Finished"
			if data.scheduledByUserId[userId] == scheduledReconnect then
				data.scheduledByUserId[userId] = nil
			end
			return
		end
		scheduledReconnect.workerState = "Running"
		data.runningOperations += 1
		local completed = pcall(function()
			-- The cached public view can race a terminal Return in another server.
			-- Re-read immediately before releasing profile ownership so a route
			-- cleared after request admission cannot revive a completed Match.
			local currentRoute = findRoute(data, userId)
			local sameRoute = currentRoute ~= nil
				and route ~= nil
				and currentRoute.routeId == route.routeId
				and currentRoute.matchId == route.matchId
			data.cachedRouteByUserId[userId] = currentRoute
			if not sameRoute then
				receipt(
					data,
					userId,
					transactionId.value,
					if currentRoute == nil then "Unavailable" else "Failed",
					routeView(currentRoute)
				)
				return
			end
			performReconnect(data, userId, transactionId.value, currentRoute, scheduledReconnect)
		end)
		data.runningOperations -= 1
		if not completed and not data.cleaned then
			receipt(data, userId, transactionId.value, "Failed", view)
		end
		scheduledReconnect.workerState = "Finished"
		if data.scheduledByUserId[userId] == scheduledReconnect then
			data.scheduledByUserId[userId] = nil
		end
	end)
	scheduling = false
	if
		data.shutdownRequested
		or scheduledReconnect.cancelled
		or scheduledReconnect.workerState ~= "Queued"
		or data.scheduledByUserId[userId] ~= scheduledReconnect
		or not scheduledCalled
		or ranInline
		or scheduleResult == false
	then
		scheduledReconnect.cancelled = true
		scheduledReconnect.workerState = "Finished"
		if data.scheduledByUserId[userId] == scheduledReconnect then
			data.scheduledByUserId[userId] = nil
		end
		if data.shutdownRequested then
			return failure("CLEANED", "beginReconnect")
		end
		return Result.ok(receipt(data, userId, transactionId.value, "Failed", view))
	end
	return Result.ok(initial)
end

function Methods.beginReconnect(
	self: Service,
	userIdValue: unknown,
	transactionIdValue: unknown
): Result.Result<LobbyProtocol.ReconnectReceipt, ReconnectError>
	local data = requireData(self)
	if data.cleaned or data.shutdownRequested then
		return failure("CLEANED", "beginReconnect")
	end
	data.runningOperations += 1
	local called, resultValue = pcall(beginReconnect, data, userIdValue, transactionIdValue)
	data.runningOperations -= 1
	if not called then
		error(resultValue, 0)
	end
	return resultValue :: Result.Result<LobbyProtocol.ReconnectReceipt, ReconnectError>
end

function Methods.reconnect(
	self: Service,
	userIdValue: unknown,
	transactionIdValue: unknown
): Result.Result<LobbyProtocol.ReconnectReceipt, ReconnectError>
	local data = requireData(self)
	if data.cleaned or data.shutdownRequested then
		return failure("CLEANED", "reconnect")
	end
	local transactionId = Ids.validateTransactionId(transactionIdValue)
	if not validUserId(userIdValue) or not transactionId.ok then
		return failure("INVALID_ARGUMENT", "reconnect")
	end
	local userId = userIdValue :: number
	local previous = data.receiptsByUserId[userId]
	local replay = if previous == nil then nil else previous.byId[transactionId.value]
	if replay ~= nil then
		return Result.ok(replay)
	end
	data.runningOperations += 1
	local called, reconnectReceipt = pcall(function(): LobbyProtocol.ReconnectReceipt
		local route = findRoute(data, userId)
		data.cachedRouteByUserId[userId] = route
		return performReconnect(data, userId, transactionId.value, route, nil)
	end)
	data.runningOperations -= 1
	if not called then
		error(reconnectReceipt, 0)
	end
	return Result.ok(reconnectReceipt :: LobbyProtocol.ReconnectReceipt)
end

local function step(data: ServiceData): number
	local current = currentTime(data)
	if current == nil then
		return 0
	end
	local completed = 0
	for userId, pending in data.pendingByUserId do
		local presentCalled, present = pcall(data.dependencies.isPresent, userId)
		if pending.departureObserved or not presentCalled or present ~= true then
			if completePending(data, userId) then
				completed += 1
			end
		elseif pending.rollbackRequested or current >= pending.startedAt + INITIALIZATION_TIMEOUT_SECONDS then
			if failPending(data, pending.player) then
				completed += 1
			end
		end
	end
	return completed
end

function Methods.step(self: Service): number
	local data = requireData(self)
	if data.cleaned or data.shutdownRequested then
		return 0
	end
	data.runningOperations += 1
	local called, completed = pcall(step, data)
	data.runningOperations -= 1
	if not called then
		error(completed, 0)
	end
	return completed :: number
end

function Methods.removePlayer(self: Service, userIdValue: unknown)
	local data = requireData(self)
	if not data.cleaned and not data.shutdownRequested and validUserId(userIdValue) then
		data.runningOperations += 1
		local userId = userIdValue :: number
		local scheduled = data.scheduledByUserId[userId]
		if scheduled ~= nil then
			scheduled.cancelled = true
		end
		data.cachedRouteByUserId[userId] = nil
		local pending = data.pendingByUserId[userId]
		if pending ~= nil then
			pending.departureObserved = true
		end
		if completePending(data, userId) or pending == nil then
			data.receiptsByUserId[userId] = nil
		end
		data.runningOperations -= 1
	end
end

function Methods.cleanup(self: Service): Result.Result<boolean, ReconnectError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	data.shutdownRequested = true
	if data.connection ~= nil then
		pcall(function()
			data.connection:Disconnect()
		end)
	end
	data.connection = nil
	for _, scheduled in data.scheduledByUserId do
		if scheduled.workerState == "Queued" then
			scheduled.cancelled = true
			scheduled.workerState = "Finished"
		end
	end
	if data.runningOperations > 0 then
		return failure("BUSY", "cleanup")
	end
	local allSettled = true
	local coordinatorBusy = false
	local pendingReconnects = table.create(1)
	for _, pending in data.pendingByUserId do
		table.insert(pendingReconnects, pending)
	end
	for _, pending in pendingReconnects do
		local userId = pending.userId
		if data.pendingByUserId[userId] ~= pending then
			continue
		end
		local presentCalled, present = pcall(data.dependencies.isPresent, userId)
		local called, settled
		if presentCalled and present == false then
			called, settled =
				pcall(data.dependencies.profileTransfer.commit, data.dependencies.profileTransfer, pending.handle)
		else
			-- Unknown presence is not proof of departure. Rollback owns the
			-- presence-aware recovery policy and retains an unsettled handle if it
			-- cannot safely decide between reacquisition and release.
			called, settled =
				pcall(data.dependencies.profileTransfer.rollback, data.dependencies.profileTransfer, pending.handle)
		end
		if called and resultOk(settled) then
			data.pendingByUserId[userId] = nil
			data.pendingByPlayer[pending.player :: any] = nil
		else
			allSettled = false
			coordinatorBusy = coordinatorBusy
				or (
					called
					and type(settled) == "table"
					and type((settled :: any).error) == "table"
					and (settled :: any).error.code == "BUSY"
				)
		end
	end
	if not allSettled then
		return failure(if coordinatorBusy then "BUSY" else "TRANSFER_FAILED", "cleanup")
	end
	data.cleaned = true
	table.clear(data.pendingByUserId)
	table.clear(data.pendingByPlayer)
	table.clear(data.receiptsByUserId)
	table.clear(data.cachedRouteByUserId)
	table.clear(data.scheduledByUserId)
	return Result.ok(true)
end

function LobbyReconnectService.new(dependenciesValue: unknown): Result.Result<Service, ReconnectError>
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local dependencies = dependenciesValue :: any
	if
		type(dependencies.clock) ~= "function"
		or type(dependencies.schedule) ~= "function"
		or type(dependencies.activeRoutes) ~= "table"
		or type(dependencies.activeRoutes.find) ~= "function"
		or type(dependencies.teleportAdapter) ~= "table"
		or type(dependencies.teleportAdapter.teleportReserved) ~= "function"
		or type(dependencies.teleportAdapter.connectInitFailed) ~= "function"
		or type(dependencies.profileTransfer) ~= "table"
		or type(dependencies.profileTransfer.prepare) ~= "function"
		or type(dependencies.profileTransfer.rollback) ~= "function"
		or type(dependencies.profileTransfer.commit) ~= "function"
		or type(dependencies.getPlayer) ~= "function"
		or type(dependencies.isPresent) ~= "function"
		or type(dependencies.makeAttemptId) ~= "function"
		or (dependencies.developmentSimulation ~= nil and type(dependencies.developmentSimulation) ~= "boolean")
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	local data: ServiceData = {
		dependencies = dependenciesValue :: Dependencies,
		receiptsByUserId = {},
		pendingByUserId = {},
		pendingByPlayer = setmetatable({}, { __mode = "k" }),
		cachedRouteByUserId = {},
		scheduledByUserId = {},
		connection = nil,
		shutdownRequested = false,
		runningOperations = 0,
		cleaned = false,
	}
	DATA[service] = data
	local connected, connection = pcall(
		dependencies.teleportAdapter.connectInitFailed,
		dependencies.teleportAdapter,
		function(player, _failureClass, context)
			if data.cleaned or data.shutdownRequested then
				return
			end
			data.runningOperations += 1
			local pending = data.pendingByPlayer[player :: any]
			if pending ~= nil and matchesInitFailure(pending, context) then
				failPending(data, player)
			end
			data.runningOperations -= 1
		end
	)
	if not connected or connection == nil then
		DATA[service] = nil
		return failure("INVALID_DEPENDENCIES", "new")
	end
	data.connection = connection
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(LobbyReconnectService)
