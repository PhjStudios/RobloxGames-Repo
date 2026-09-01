--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type FailureClass = "Retryable" | "Terminal"
export type Adapter = {
	reserveServer: (self: Adapter, placeId: number) -> any,
	teleportReserved: (
		self: Adapter,
		placeId: number,
		accessCode: string,
		players: { unknown },
		routingData: unknown
	) -> any,
	teleportPublic: (self: Adapter, placeId: number, players: { unknown }, routingData: unknown) -> any,
	connectInitFailed: (self: Adapter, listener: (unknown, FailureClass, unknown) -> ()) -> any,
	queueReserveFailure: (self: Adapter, failureClass: FailureClass, count: number?) -> (),
	queueTeleportFailure: (self: Adapter, failureClass: FailureClass, count: number?) -> (),
	emitInitFailure: (
		self: Adapter,
		player: unknown,
		failureClass: FailureClass,
		placeId: number?,
		routingData: unknown?
	) -> (),
	getCalls: (
		self: Adapter
	) -> {
		reserveCount: number,
		teleportCount: number,
		publicTeleportCount: number,
		teleports: { any },
		publicTeleports: { any },
	},
}

type QueuedFailure = { failureClass: FailureClass }
type Data = {
	reserveFailures: { QueuedFailure },
	teleportFailures: { QueuedFailure },
	listeners: { [number]: (unknown, FailureClass, unknown) -> () },
	nextListenerId: number,
	reserveCount: number,
	teleportCount: number,
	publicTeleportCount: number,
	teleports: { any },
	publicTeleports: { any },
}

local Methods = {}
Methods.__index = Methods

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: Data }
local IsolatedTeleportAdapter = {}

local function dataFor(value: unknown): Data
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ISOLATED_TELEPORT_ADAPTER][code=INVALID_CONTEXT]", 0)
	end
	return data :: Data
end

local function clone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local output = {}
	for key, child in value do
		output[clone(key)] = clone(child)
	end
	return output
end

local function queuedError(code: string, failureClass: FailureClass)
	return Result.err(table.freeze({ code = code, failureClass = failureClass }))
end

local function validPlayers(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or #value < 1 or #value > 4 then
		return false
	end
	local seen: { [number]: boolean } = {}
	local count = 0
	for key, candidate in value :: { [any]: unknown } do
		if
			type(key) ~= "number"
			or not Validation.isSafeInteger(key)
			or key < 1
			or type(candidate) ~= "table"
			or type((candidate :: any).userId) ~= "number"
			or not Validation.isSafeInteger((candidate :: any).userId)
			or (candidate :: any).userId <= 0
			or seen[(candidate :: any).userId]
		then
			return false
		end
		count += 1
		seen[(candidate :: any).userId] = true
	end
	return count == #value
end

local function enqueue(target: { QueuedFailure }, failureClass: FailureClass, countValue: number?)
	local count = countValue or 1
	if
		(failureClass ~= "Retryable" and failureClass ~= "Terminal")
		or type(count) ~= "number"
		or count < 1
		or count % 1 ~= 0
	then
		error("[ISOLATED_TELEPORT_ADAPTER][code=INVALID_FAILURE]", 0)
	end
	for _ = 1, count do
		table.insert(target, { failureClass = failureClass })
	end
end

function Methods:reserveServer(placeId: number): any
	local data = dataFor(self)
	data.reserveCount += 1
	if type(placeId) ~= "number" or placeId <= 0 then
		return queuedError("INVALID_ARGUMENT", "Terminal")
	end
	local queued = table.remove(data.reserveFailures, 1)
	if queued ~= nil then
		return queuedError("RESERVE_FAILED", queued.failureClass)
	end
	return Result.ok(table.freeze({
		accessCode = `isolated-access-{data.reserveCount}`,
		privateServerId = `isolated-private-{data.reserveCount}`,
	}))
end

function Methods:teleportReserved(placeId: number, accessCode: string, players: { unknown }, routingData: unknown): any
	local data = dataFor(self)
	data.teleportCount += 1
	if
		type(placeId) ~= "number"
		or placeId <= 0
		or type(accessCode) ~= "string"
		or #accessCode < 1
		or not validPlayers(players)
	then
		return queuedError("INVALID_ARGUMENT", "Terminal")
	end
	table.insert(data.teleports, {
		placeId = placeId,
		accessCode = accessCode,
		players = clone(players),
		routingData = clone(routingData),
	})
	local queued = table.remove(data.teleportFailures, 1)
	if queued ~= nil then
		return queuedError("TELEPORT_FAILED", queued.failureClass)
	end
	return Result.ok(true)
end

function Methods:teleportPublic(placeId: number, players: { unknown }, routingData: unknown): any
	local data = dataFor(self)
	data.publicTeleportCount += 1
	local routing = TravelProtocol.validateRoutingData(routingData)
	if
		type(placeId) ~= "number"
		or placeId <= 0
		or not validPlayers(players)
		or not routing.ok
		or routing.value.kind ~= "Return"
	then
		return queuedError("INVALID_ARGUMENT", "Terminal")
	end
	table.insert(data.publicTeleports, {
		placeId = placeId,
		players = clone(players),
		routingData = clone(routing.value),
	})
	local queued = table.remove(data.teleportFailures, 1)
	if queued ~= nil then
		return queuedError("TELEPORT_FAILED", queued.failureClass)
	end
	return Result.ok(true)
end

function Methods:connectInitFailed(listener: (unknown, FailureClass, unknown) -> ()): any
	if type(listener) ~= "function" then
		error("[ISOLATED_TELEPORT_ADAPTER][code=INVALID_LISTENER]", 0)
	end
	local data = dataFor(self)
	local id = data.nextListenerId
	data.nextListenerId += 1
	data.listeners[id] = listener
	local connected = true
	local connection = {}
	function connection.Disconnect(_connection: unknown)
		if connected then
			connected = false
			data.listeners[id] = nil
		end
	end
	return table.freeze(connection)
end

function Methods:queueReserveFailure(failureClass: FailureClass, count: number?)
	enqueue(dataFor(self).reserveFailures, failureClass, count)
end

function Methods:queueTeleportFailure(failureClass: FailureClass, count: number?)
	enqueue(dataFor(self).teleportFailures, failureClass, count)
end

local function containsUser(call: any, player: unknown): boolean
	local id = if type(player) == "table" then (player :: any).userId else nil
	for _, candidate in call.players do
		if type(candidate) == "table" and (candidate :: any).userId == id then
			return true
		end
	end
	return false
end

function Methods:emitInitFailure(
	player: unknown,
	failureClass: FailureClass,
	placeIdValue: number?,
	routingDataValue: unknown?
)
	local data = dataFor(self)
	local placeId = placeIdValue
	local routingData = routingDataValue
	if placeId == nil or routingData == nil then
		for index = #data.teleports, 1, -1 do
			local call = data.teleports[index]
			if containsUser(call, player) then
				placeId = call.placeId
				routingData = call.routingData
				break
			end
		end
	end
	if placeId == nil or routingData == nil then
		for index = #data.publicTeleports, 1, -1 do
			local call = data.publicTeleports[index]
			if containsUser(call, player) then
				placeId = call.placeId
				routingData = call.routingData
				break
			end
		end
	end
	local context = if placeId == nil or routingData == nil
		then nil
		else { placeId = placeId, routingData = clone(routingData) }
	local ids: { number } = {}
	for id in data.listeners do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local listener = data.listeners[id]
		if listener ~= nil then
			listener(player, failureClass, context)
		end
	end
end

function Methods:getCalls(): {
	reserveCount: number,
	teleportCount: number,
	publicTeleportCount: number,
	teleports: { any },
	publicTeleports: { any },
}
	local data = dataFor(self)
	return table.freeze({
		reserveCount = data.reserveCount,
		teleportCount = data.teleportCount,
		publicTeleportCount = data.publicTeleportCount,
		teleports = table.freeze(clone(data.teleports)),
		publicTeleports = table.freeze(clone(data.publicTeleports)),
	})
end

function IsolatedTeleportAdapter.new(): Adapter
	local adapter = setmetatable({}, Methods) :: any
	table.freeze(adapter)
	DATA[adapter] = {
		reserveFailures = {},
		teleportFailures = {},
		listeners = {},
		nextListenerId = 1,
		reserveCount = 0,
		teleportCount = 0,
		publicTeleportCount = 0,
		teleports = {},
		publicTeleports = {},
	}
	return adapter :: Adapter
end

table.freeze(Methods)
return table.freeze(IsolatedTeleportAdapter)
