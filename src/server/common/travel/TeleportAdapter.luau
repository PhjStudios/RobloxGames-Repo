--!strict

local RunService = game:GetService("RunService")

local TravelProtocol = require(game:GetService("ReplicatedStorage").Shared.travel.TravelProtocol)
local Result = require(game:GetService("ReplicatedStorage").Shared.util.Result)
local Validation = require(game:GetService("ReplicatedStorage").Shared.util.Validation)

export type FailureClass = "Retryable" | "Terminal"
export type Reservation = { accessCode: string, privateServerId: string }
export type InitFailureContext = { placeId: number, routingData: TravelProtocol.RoutingData }
export type InitFailureListener = (player: Player, failureClass: FailureClass, context: InitFailureContext?) -> ()
export type Adapter = {
	reserveServer: (self: Adapter, placeId: number) -> Result.Result<Reservation, AdapterError>,
	teleportReserved: (
		self: Adapter,
		placeId: number,
		accessCode: string,
		players: { Player },
		routingData: TravelProtocol.RoutingData
	) -> Result.Result<boolean, AdapterError>,
	teleportPublic: (
		self: Adapter,
		placeId: number,
		players: { Player },
		routingData: TravelProtocol.ReturnRoutingData
	) -> Result.Result<boolean, AdapterError>,
	connectInitFailed: (self: Adapter, listener: InitFailureListener) -> RBXScriptConnection,
	getKind: (self: Adapter) -> string,
}

export type ErrorCode =
	"STUDIO_FORBIDDEN"
	| "STUDIO_REQUIRED"
	| "INVALID_ARGUMENT"
	| "RESERVE_FAILED"
	| "TELEPORT_FAILED"
export type AdapterError = { code: ErrorCode, failureClass: FailureClass }

local TERMINAL_RESULTS: { [string]: boolean } = table.freeze({
	GameEnded = true,
	GameNotFound = true,
	Unauthorized = true,
})

local TeleportAdapter = {}

local function failure<T>(code: ErrorCode, failureClass: FailureClass): Result.Failure<AdapterError>
	return Result.err(table.freeze({ code = code, failureClass = failureClass }))
end

local function validPlaceId(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and value > 0
end

local function validAccessCode(value: unknown): boolean
	return type(value) == "string" and #value >= 1 and #value <= 200
end

local function validPlayers(value: unknown): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil or #value < 1 or #value > 4 then
		return false
	end
	local seen: { [number]: boolean } = {}
	for index, player in value :: { any } do
		if
			index < 1
			or typeof(player) ~= "Instance"
			or not player:IsA("Player")
			or player.UserId <= 0
			or seen[player.UserId]
		then
			return false
		end
		seen[player.UserId] = true
	end
	return true
end

function TeleportAdapter.classifyFailure(value: unknown): FailureClass
	local name = if typeof(value) == "EnumItem"
		then (value :: EnumItem).Name
		elseif type(value) == "string" then value
		else "Failure"
	return if TERMINAL_RESULTS[name] == true then "Terminal" else "Retryable"
end

local function initFailureContext(placeIdValue: unknown, optionsValue: unknown): InitFailureContext?
	if not validPlaceId(placeIdValue) or typeof(optionsValue) ~= "Instance" then
		return nil
	end
	local options = optionsValue :: Instance
	if not options:IsA("TeleportOptions") then
		return nil
	end
	local called, routingValue = pcall((options :: TeleportOptions).GetTeleportData, options)
	local routing = if called then TravelProtocol.validateRoutingData(routingValue) else nil
	if routing == nil or not routing.ok then
		return nil
	end
	return table.freeze({ placeId = placeIdValue :: number, routingData = routing.value })
end

function TeleportAdapter.newProduction(): Result.Result<Adapter, AdapterError>
	if RunService:IsStudio() then
		return failure("STUDIO_FORBIDDEN", "Terminal")
	end
	local loaded, teleportService = pcall(function()
		return game:GetService("TeleportService")
	end)
	if not loaded then
		return failure("TELEPORT_FAILED", "Retryable")
	end
	local adapter = {} :: any
	function adapter:reserveServer(placeId: number): Result.Result<Reservation, AdapterError>
		if not validPlaceId(placeId) then
			return failure("INVALID_ARGUMENT", "Terminal")
		end
		local called, accessCode, privateServerId = pcall(function()
			return (teleportService :: TeleportService):ReserveServer(placeId)
		end)
		if
			not called
			or not validAccessCode(accessCode)
			or type(privateServerId) ~= "string"
			or #privateServerId > 200
		then
			return failure("RESERVE_FAILED", "Retryable")
		end
		return Result.ok(
			table.freeze({ accessCode = accessCode :: string, privateServerId = privateServerId :: string })
		)
	end
	function adapter:teleportReserved(
		placeId: number,
		accessCode: string,
		players: { Player },
		routingData: TravelProtocol.RoutingData
	): Result.Result<boolean, AdapterError>
		local routing = TravelProtocol.validateRoutingData(routingData)
		if
			not validPlaceId(placeId)
			or not validAccessCode(accessCode)
			or not validPlayers(players)
			or not routing.ok
		then
			return failure("INVALID_ARGUMENT", "Terminal")
		end
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = accessCode
		options:SetTeleportData(routing.value)
		local called, failureValue = pcall(function()
			(teleportService :: TeleportService):TeleportAsync(placeId, players, options)
		end)
		options:Destroy()
		if not called then
			return failure("TELEPORT_FAILED", TeleportAdapter.classifyFailure(failureValue))
		end
		return Result.ok(true)
	end
	function adapter:teleportPublic(
		placeId: number,
		players: { Player },
		routingData: TravelProtocol.ReturnRoutingData
	): Result.Result<boolean, AdapterError>
		local routing = TravelProtocol.validateRoutingData(routingData)
		if
			not validPlaceId(placeId)
			or not validPlayers(players)
			or not routing.ok
			or routing.value.kind ~= "Return"
		then
			return failure("INVALID_ARGUMENT", "Terminal")
		end
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData(routing.value)
		local called, failureValue = pcall(function()
			(teleportService :: TeleportService):TeleportAsync(placeId, players, options)
		end)
		options:Destroy()
		if not called then
			return failure("TELEPORT_FAILED", TeleportAdapter.classifyFailure(failureValue))
		end
		return Result.ok(true)
	end
	function adapter:connectInitFailed(listener: InitFailureListener): RBXScriptConnection
		if type(listener) ~= "function" then
			error("[ATD_TELEPORT_ADAPTER][code=INVALID_LISTENER]", 0)
		end
		return (teleportService :: TeleportService).TeleportInitFailed:Connect(
			function(player, teleportResult, _errorMessage, placeId, teleportOptions)
				listener(
					player,
					TeleportAdapter.classifyFailure(teleportResult),
					initFailureContext(placeId, teleportOptions)
				)
			end
		)
	end
	function adapter:getKind(): string
		return "ProductionTeleportService"
	end
	return Result.ok(table.freeze(adapter) :: Adapter)
end

function TeleportAdapter.newStudioDevelopment(): Result.Result<Adapter, AdapterError>
	if not RunService:IsStudio() then
		return failure("STUDIO_REQUIRED", "Terminal")
	end
	local signal = Instance.new("BindableEvent")
	local adapter = {} :: any
	function adapter:reserveServer(placeId: number): Result.Result<Reservation, AdapterError>
		if not validPlaceId(placeId) then
			return failure("INVALID_ARGUMENT", "Terminal")
		end
		return Result.ok(table.freeze({
			accessCode = "studio-isolated-reservation",
			privateServerId = "studio-isolated-private-server",
		}))
	end
	function adapter:teleportReserved(
		placeId: number,
		accessCode: string,
		players: { Player },
		routingData: TravelProtocol.RoutingData
	): Result.Result<boolean, AdapterError>
		if
			not validPlaceId(placeId)
			or accessCode ~= "studio-isolated-reservation"
			or not validPlayers(players)
			or not TravelProtocol.validateRoutingData(routingData).ok
		then
			return failure("INVALID_ARGUMENT", "Terminal")
		end
		return Result.ok(true)
	end
	function adapter:teleportPublic(
		placeId: number,
		players: { Player },
		routingData: TravelProtocol.ReturnRoutingData
	): Result.Result<boolean, AdapterError>
		local routing = TravelProtocol.validateRoutingData(routingData)
		if
			not validPlaceId(placeId)
			or not validPlayers(players)
			or not routing.ok
			or routing.value.kind ~= "Return"
		then
			return failure("INVALID_ARGUMENT", "Terminal")
		end
		return Result.ok(true)
	end
	function adapter:connectInitFailed(listener: InitFailureListener): RBXScriptConnection
		if type(listener) ~= "function" then
			error("[ATD_TELEPORT_ADAPTER][code=INVALID_LISTENER]", 0)
		end
		return signal.Event:Connect(listener)
	end
	function adapter:getKind(): string
		return "StudioDevelopmentTeleport"
	end
	return Result.ok(table.freeze(adapter) :: Adapter)
end

return table.freeze(TeleportAdapter)
