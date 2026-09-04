--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type ErrorCode = "INVALID_DEPENDENCIES" | "INVALID_PLAYER" | "BUSY" | "CLEANED"
export type ReturnError = { code: ErrorCode }
export type Dependencies = {
	ownershipTransfer: unknown,
	teleport: unknown,
	lobbyPlaceId: number,
	getUserId: (unknown) -> unknown,
	isLive: (unknown) -> unknown,
	getProfileState: (number) -> unknown,
	rejectPlayer: (unknown, string) -> unknown,
	makeReturnId: () -> unknown,
	schedule: (() -> ()) -> unknown,
	connectPlayerRemoving: ((unknown) -> ()) -> unknown,
	wait: (number) -> (),
	monotonic: () -> unknown,
	timeoutSeconds: number?,
}

type ServiceData = {
	dependencies: Dependencies,
	activeUserIds: { [number]: boolean },
	workersByUserId: {
		[number]: {
			userId: number,
			player: unknown,
			state: "Queued" | "Running",
		},
	},
	pendingByPlayer: {
		[any]: {
			userId: number,
			player: unknown,
			handle: unknown,
			deadline: number,
			rollbackPending: boolean?,
			rejectAfterRollback: boolean?,
			returnId: string,
			destinationPlaceId: number,
		},
	},
	pendingByUserId: {
		[number]: {
			userId: number,
			player: unknown,
			handle: unknown,
			deadline: number,
			rollbackPending: boolean?,
			rejectAfterRollback: boolean?,
			returnId: string,
			destinationPlaceId: number,
		},
	},
	rejectedPlayers: { [any]: boolean },
	connections: { any },
	ingressOperationsRunning: number,
	closing: boolean,
	cleaned: boolean,
}

local DEFAULT_TIMEOUT_SECONDS = 30
local MAX_TIMEOUT_SECONDS = 60
local MAX_ACTIVE_RETURNS = 32
local POLL_SECONDS = 0.1
local PUBLIC_REJECT_REASON = "Match admission could not be authorized. Please rejoin the Lobby."

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local UnexpectedReturnService = {}

local function failure<T>(code: ErrorCode): Result.Failure<ReturnError>
	return Result.err(table.freeze({ code = code }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_UNEXPECTED_RETURN][code=INVALID_CONTEXT]", 0)
	end
	return data :: ServiceData
end

local function successful(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function userId(data: ServiceData, player: unknown): number?
	local called, value = pcall(data.dependencies.getUserId, player)
	return if called and type(value) == "number" and Validation.isSafeInteger(value) and value > 0 then value else nil
end

local function live(data: ServiceData, player: unknown): boolean
	local called, value = pcall(data.dependencies.isLive, player)
	return called and value == true
end

local function monotonic(data: ServiceData): number?
	local called, value = pcall(data.dependencies.monotonic)
	return if called and type(value) == "number" and Validation.isFiniteNumber(value) and value >= 0 then value else nil
end

local function activeCount(data: ServiceData): number
	local count = 0
	for _ in data.activeUserIds do
		count += 1
	end
	return count
end

local function runIngressOperation(data: ServiceData, callback: () -> unknown): unknown
	data.ingressOperationsRunning += 1
	local called, resultValue = pcall(callback)
	data.ingressOperationsRunning -= 1
	if not called then
		error(resultValue, 0)
	end
	return resultValue
end

local function rejectLivePlayer(data: ServiceData, player: unknown): boolean
	if data.rejectedPlayers[player :: any] or not live(data, player) then
		return false
	end
	local called = pcall(data.dependencies.rejectPlayer, player, PUBLIC_REJECT_REASON)
	if called then
		data.rejectedPlayers[player :: any] = true
	end
	return called
end

local function matchesInitFailure(pending: any, contextValue: unknown): boolean
	if type(contextValue) ~= "table" or getmetatable(contextValue :: any) ~= nil then
		return false
	end
	local context = contextValue :: any
	local routing = TravelProtocol.validateRoutingData(context.routingData)
	return context.placeId == pending.destinationPlaceId
		and routing.ok
		and routing.value.kind == "Return"
		and routing.value.returnId == pending.returnId
end

local function failPending(data: ServiceData, player: unknown): boolean
	local pending = data.pendingByPlayer[player :: any]
	if pending == nil then
		return false
	end
	local rolledBack = false
	for _attempt = 1, 3 do
		local called, resultValue = pcall(
			(data.dependencies.ownershipTransfer :: any).rollback,
			data.dependencies.ownershipTransfer,
			pending.handle
		)
		if called and successful(resultValue) then
			rolledBack = true
			break
		end
	end
	if not rolledBack then
		-- Retain the only handle capable of reacquiring this live player's
		-- profile; a later adapter signal or cleanup can retry it.
		pending.rollbackPending = true
		return false
	end
	data.pendingByPlayer[player :: any] = nil
	data.pendingByUserId[pending.userId] = nil
	data.activeUserIds[pending.userId] = nil
	if pending.rejectAfterRollback then
		rejectLivePlayer(data, player)
	end
	return true
end

local function completePending(data: ServiceData, player: unknown): boolean
	local pending = data.pendingByPlayer[player :: any]
	if pending == nil then
		return false
	end
	if pending.rollbackPending then
		return failPending(data, player)
	end
	local committedCalled, committed =
		pcall((data.dependencies.ownershipTransfer :: any).commit, data.dependencies.ownershipTransfer, pending.handle)
	if not committedCalled or not successful(committed) then
		-- The player is already gone, so retain this handle for step() to retry;
		-- it must never be converted into a live-player rollback.
		return false
	end
	data.pendingByPlayer[player :: any] = nil
	data.pendingByUserId[pending.userId] = nil
	data.activeUserIds[pending.userId] = nil
	return true
end

function Methods.step(self: Service): number
	local data = requireData(self)
	if data.cleaned or data.closing then
		return 0
	end
	local settled = 0
	local players: { unknown } = {}
	local currentTime = monotonic(data)
	for player, pending in data.pendingByPlayer do
		if
			pending.rollbackPending
			or not live(data, player)
			or (currentTime ~= nil and currentTime >= pending.deadline)
		then
			table.insert(players, player)
		end
	end
	for _, player in players do
		local pending = data.pendingByPlayer[player :: any]
		if pending ~= nil then
			if not live(data, player) and not pending.rollbackPending then
				if completePending(data, player) then
					settled += 1
				end
			else
				local stateCalled, state = pcall(data.dependencies.getProfileState, pending.userId)
				if pending.rollbackPending and stateCalled and state == "Ready" then
					data.pendingByPlayer[player :: any] = nil
					data.pendingByUserId[pending.userId] = nil
					data.activeUserIds[pending.userId] = nil
					if pending.rejectAfterRollback then
						rejectLivePlayer(data, player)
					end
					settled += 1
				elseif failPending(data, player) then
					settled += 1
				end
			end
		end
	end
	return settled
end

local function run(data: ServiceData, player: unknown, id: number)
	local start = monotonic(data)
	local timeout = data.dependencies.timeoutSeconds or DEFAULT_TIMEOUT_SECONDS
	if start == nil then
		data.activeUserIds[id] = nil
		rejectLivePlayer(data, player)
		return
	end
	while not data.closing and live(data, player) do
		local stateCalled, state = pcall(data.dependencies.getProfileState, id)
		if stateCalled and state == "Ready" then
			break
		elseif stateCalled and state == "Failed" then
			data.activeUserIds[id] = nil
			rejectLivePlayer(data, player)
			return
		end
		local current = monotonic(data)
		if current == nil or current >= start + timeout then
			data.activeUserIds[id] = nil
			rejectLivePlayer(data, player)
			return
		end
		pcall(data.dependencies.wait, POLL_SECONDS)
	end
	if data.closing or not live(data, player) then
		data.activeUserIds[id] = nil
		return
	end
	local idCalled, idValue = pcall(data.dependencies.makeReturnId)
	local returnId = if idCalled then TravelProtocol.validateOpaqueId(idValue, "return") else nil
	local routing = if returnId ~= nil and returnId.ok then TravelProtocol.returnToLobby(returnId.value) else nil
	if routing == nil or not routing.ok then
		data.activeUserIds[id] = nil
		rejectLivePlayer(data, player)
		return
	end
	local preparedCalled, prepared =
		pcall((data.dependencies.ownershipTransfer :: any).prepare, data.dependencies.ownershipTransfer, { id })
	if not preparedCalled or not successful(prepared) then
		data.activeUserIds[id] = nil
		rejectLivePlayer(data, player)
		return
	end
	local handle = (prepared :: any).value.handle
	local pending = {
		userId = id,
		player = player,
		handle = handle,
		deadline = (monotonic(data) or start) + timeout,
		rejectAfterRollback = true,
		returnId = returnId.value,
		destinationPlaceId = data.dependencies.lobbyPlaceId,
	}
	data.pendingByPlayer[player :: any] = pending
	data.pendingByUserId[id] = pending
	if data.closing or not live(data, player) then
		failPending(data, player)
		return
	end
	local called, teleported = pcall(
		(data.dependencies.teleport :: any).teleportPublic,
		data.dependencies.teleport,
		data.dependencies.lobbyPlaceId,
		{ player },
		routing.value
	)
	if not called or not successful(teleported) then
		failPending(data, player)
	end
end

function Methods.returnPlayer(self: Service, player: unknown): Result.Result<boolean, ReturnError>
	local data = requireData(self)
	if data.cleaned or data.closing then
		return failure("CLEANED")
	end
	return runIngressOperation(data, function()
		local id = userId(data, player)
		if id == nil or not live(data, player) then
			return failure("INVALID_PLAYER")
		end
		if data.activeUserIds[id] or activeCount(data) >= MAX_ACTIVE_RETURNS then
			if not data.activeUserIds[id] then
				rejectLivePlayer(data, player)
			end
			return failure("BUSY")
		end
		data.activeUserIds[id] = true
		local worker = {
			userId = id,
			player = player,
			state = "Queued" :: "Queued" | "Running",
		}
		data.workersByUserId[id] = worker
		local called, scheduled = pcall(data.dependencies.schedule, function()
			if data.closing or data.workersByUserId[id] ~= worker then
				return
			end
			worker.state = "Running"
			local runCalled = pcall(run, data, player, id)
			if not runCalled and data.pendingByUserId[id] == nil then
				data.activeUserIds[id] = nil
				if not data.closing then
					rejectLivePlayer(data, player)
				end
			end
			if data.workersByUserId[id] == worker then
				data.workersByUserId[id] = nil
			end
		end)
		if not called or scheduled == false then
			if data.workersByUserId[id] == worker then
				data.workersByUserId[id] = nil
			end
			data.activeUserIds[id] = nil
			rejectLivePlayer(data, player)
			return failure("BUSY")
		end
		return Result.ok(true)
	end) :: any
end

function Methods.cleanup(self: Service): Result.Result<boolean, ReturnError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	data.closing = true
	if data.ingressOperationsRunning > 0 then
		return failure("BUSY")
	end
	for id, worker in data.workersByUserId do
		if worker.state == "Queued" then
			data.workersByUserId[id] = nil
			if data.pendingByUserId[id] == nil then
				data.activeUserIds[id] = nil
			end
		end
	end
	for _, worker in data.workersByUserId do
		if worker.state == "Running" then
			return failure("BUSY")
		end
	end
	for index = #data.connections, 1, -1 do
		pcall(function()
			data.connections[index]:Disconnect()
		end)
	end
	table.clear(data.connections)
	for player, pending in data.pendingByPlayer do
		local settledCalled: boolean
		local settled: unknown
		if live(data, player) then
			settledCalled, settled = pcall(
				(data.dependencies.ownershipTransfer :: any).rollback,
				data.dependencies.ownershipTransfer,
				pending.handle
			)
		else
			settledCalled, settled = pcall(
				(data.dependencies.ownershipTransfer :: any).commit,
				data.dependencies.ownershipTransfer,
				pending.handle
			)
		end
		if settledCalled and successful(settled) then
			data.pendingByPlayer[player :: any] = nil
			data.pendingByUserId[pending.userId] = nil
			data.activeUserIds[pending.userId] = nil
		end
	end
	if next(data.pendingByUserId) ~= nil then
		return failure("BUSY")
	end
	data.cleaned = true
	table.clear(data.pendingByPlayer)
	table.clear(data.pendingByUserId)
	table.clear(data.activeUserIds)
	table.clear(data.workersByUserId)
	return Result.ok(true)
end

function Methods.isBusy(self: Service): boolean
	local data = requireData(self)
	return data.ingressOperationsRunning > 0 or next(data.workersByUserId) ~= nil
end

function UnexpectedReturnService.new(dependenciesValue: unknown): Result.Result<Service, ReturnError>
	if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
		return failure("INVALID_DEPENDENCIES")
	end
	local dependencies = dependenciesValue :: any
	local timeout = dependencies.timeoutSeconds or DEFAULT_TIMEOUT_SECONDS
	if
		type(dependencies.ownershipTransfer) ~= "table"
		or type(dependencies.ownershipTransfer.prepare) ~= "function"
		or type(dependencies.ownershipTransfer.rollback) ~= "function"
		or type(dependencies.ownershipTransfer.commit) ~= "function"
		or type(dependencies.teleport) ~= "table"
		or type(dependencies.teleport.teleportPublic) ~= "function"
		or type(dependencies.teleport.connectInitFailed) ~= "function"
		or type(dependencies.lobbyPlaceId) ~= "number"
		or not Validation.isSafeInteger(dependencies.lobbyPlaceId)
		or dependencies.lobbyPlaceId <= 0
		or type(dependencies.getUserId) ~= "function"
		or type(dependencies.isLive) ~= "function"
		or type(dependencies.getProfileState) ~= "function"
		or type(dependencies.rejectPlayer) ~= "function"
		or type(dependencies.makeReturnId) ~= "function"
		or type(dependencies.schedule) ~= "function"
		or type(dependencies.connectPlayerRemoving) ~= "function"
		or type(dependencies.wait) ~= "function"
		or type(dependencies.monotonic) ~= "function"
		or type(timeout) ~= "number"
		or not Validation.isSafeInteger(timeout)
		or timeout < 1
		or timeout > MAX_TIMEOUT_SECONDS
	then
		return failure("INVALID_DEPENDENCIES")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	local data: ServiceData = {
		dependencies = dependenciesValue :: Dependencies,
		activeUserIds = {},
		workersByUserId = {},
		pendingByPlayer = setmetatable({}, { __mode = "k" }),
		pendingByUserId = {},
		rejectedPlayers = setmetatable({}, { __mode = "k" }),
		connections = {},
		ingressOperationsRunning = 0,
		closing = false,
		cleaned = false,
	}
	DATA[service] = data
	local initCalled, initConnection = pcall(
		dependencies.teleport.connectInitFailed,
		dependencies.teleport,
		function(player, _failureClass, context)
			if not data.cleaned and not data.closing then
				runIngressOperation(data, function()
					local pending = data.pendingByPlayer[player :: any]
					if pending ~= nil and matchesInitFailure(pending, context) then
						failPending(data, player)
					end
				end)
			end
		end
	)
	local removingCalled, removingConnection = pcall(dependencies.connectPlayerRemoving, function(player)
		if not data.cleaned and not data.closing then
			runIngressOperation(data, function()
				completePending(data, player)
			end)
		end
	end)
	if not initCalled or initConnection == nil or not removingCalled or removingConnection == nil then
		if initCalled and initConnection ~= nil then
			pcall(function()
				initConnection:Disconnect()
			end)
		end
		DATA[service] = nil
		return failure("INVALID_DEPENDENCIES")
	end
	table.insert(data.connections, initConnection)
	table.insert(data.connections, removingConnection)
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(UnexpectedReturnService)
