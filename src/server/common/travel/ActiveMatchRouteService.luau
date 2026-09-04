--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Adapter = {
	getAsync: (self: Adapter, key: string) -> unknown,
	updateAsync: (self: Adapter, key: string, expirationSeconds: number, transform: (unknown) -> unknown) -> unknown,
	removeAsync: (self: Adapter, key: string) -> unknown,
}

export type Route = {
	version: number,
	revision: number,
	routeId: string,
	userId: number,
	ticketId: string,
	matchId: string,
	destinationPlaceId: number,
	destinationJobId: string?,
	reservedServerAccessCode: string,
	createdAt: number,
	expiresAt: number,
}

export type ErrorCode = "INVALID_ARGUMENT" | "NOT_FOUND" | "EXPIRED" | "CONFLICT" | "STORE_UNAVAILABLE"
export type Operation = "create" | "bindDestination" | "find" | "resolve" | "takeForMatch" | "clear"
export type RouteError = { code: ErrorCode, operation: Operation }
export type CreateOutcome = { route: Route, applied: boolean }

type ServiceData = { adapter: Adapter }

local VERSION = 1
local MAX_ROUTE_SECONDS = 2_700
local MAX_TOKEN_BYTES = 200
-- MemoryStoreHashMap UpdateAsync treats a nil transform result as an aborted
-- write, not a deletion. A deliberately invalid value is therefore the atomic
-- cleared state: readers ignore it and a later create may replace it.
local CLEARED_ROUTE_TOMBSTONE = table.freeze({ cleared = true })
local ROUTE_FIELDS = table.freeze({
	version = true,
	revision = true,
	routeId = true,
	userId = true,
	ticketId = true,
	matchId = true,
	destinationPlaceId = true,
	destinationJobId = true,
	reservedServerAccessCode = true,
	createdAt = true,
	expiresAt = true,
})

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local ActiveMatchRouteService = {
	VERSION = VERSION,
	MAX_ROUTE_SECONDS = MAX_ROUTE_SECONDS,
}

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<RouteError>
	return Result.err(table.freeze({ code = code, operation = operation }))
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

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_ACTIVE_MATCH_ROUTE][code=INVALID_CONTEXT]", 0)
	end
	return data :: ServiceData
end

local function userId(value: unknown): number?
	return if type(value) == "number"
			and Validation.isSafeInteger(value :: number)
			and value > 0
		then value :: number
		else nil
end

local function token(value: unknown, prefix: string?): string?
	if type(value) ~= "string" or #value < 1 or #value > MAX_TOKEN_BYTES then
		return nil
	end
	if prefix ~= nil and string.sub(value :: string, 1, #prefix + 1) ~= `{prefix}:` then
		return nil
	end
	return value :: string
end

local function routeKey(value: number): string
	return `active-route/{value}`
end

local function validate(value: unknown): Route?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local record = value :: { [any]: unknown }
	local count = 0
	for key in record do
		if type(key) ~= "string" or ROUTE_FIELDS[key] ~= true then
			return nil
		end
		count += 1
	end
	if count ~= 10 and count ~= 11 then
		return nil
	end
	local routeId = TravelProtocol.validateOpaqueId(record.routeId, "route")
	local ticketId = TravelProtocol.validateOpaqueId(record.ticketId, "ticket")
	local routeUserId = userId(record.userId)
	local revision = if type(record.revision) == "number"
			and Validation.isSafeInteger(record.revision :: number)
			and record.revision >= 1
		then record.revision :: number
		else nil
	local destinationPlaceId = userId(record.destinationPlaceId)
	local matchId = token(record.matchId, "match")
	local destinationJobId = if record.destinationJobId == nil then nil else token(record.destinationJobId, nil)
	local accessCode = token(record.reservedServerAccessCode, nil)
	local createdAt = if type(record.createdAt) == "number"
			and Validation.isSafeInteger(record.createdAt :: number)
			and record.createdAt >= 0
		then record.createdAt :: number
		else nil
	local expiresAt = if type(record.expiresAt) == "number"
			and Validation.isSafeInteger(record.expiresAt :: number)
			and record.expiresAt >= 0
		then record.expiresAt :: number
		else nil
	if
		record.version ~= VERSION
		or not routeId.ok
		or not ticketId.ok
		or routeUserId == nil
		or revision == nil
		or destinationPlaceId == nil
		or matchId == nil
		or (record.destinationJobId ~= nil and destinationJobId == nil)
		or accessCode == nil
		or createdAt == nil
		or expiresAt == nil
		or expiresAt <= createdAt
		or expiresAt - createdAt > MAX_ROUTE_SECONDS
	then
		return nil
	end
	return table.freeze({
		version = VERSION,
		revision = revision,
		routeId = routeId.value,
		userId = routeUserId,
		ticketId = ticketId.value,
		matchId = matchId,
		destinationPlaceId = destinationPlaceId,
		destinationJobId = destinationJobId,
		reservedServerAccessCode = accessCode,
		createdAt = createdAt,
		expiresAt = expiresAt,
	})
end

function Methods.bindDestination(
	self: Service,
	userIdValue: unknown,
	matchIdValue: unknown,
	destinationJobIdValue: unknown,
	nowValue: unknown?
): Result.Result<CreateOutcome, RouteError>
	local data = requireData(self)
	local id = userId(userIdValue)
	local expectedMatchId = token(matchIdValue, "match")
	local destinationJobId = token(destinationJobIdValue, nil)
	local currentTime = nowValue or os.time()
	if
		id == nil
		or expectedMatchId == nil
		or destinationJobId == nil
		or type(currentTime) ~= "number"
		or not Validation.isSafeInteger(currentTime :: number)
		or currentTime < 0
	then
		return failure("INVALID_ARGUMENT", "bindDestination")
	end
	local transformError: ErrorCode? = nil
	local applied = false
	local called, stored = pcall(
		data.adapter.updateAsync,
		data.adapter,
		routeKey(id),
		MAX_ROUTE_SECONDS,
		function(current)
			transformError = nil
			applied = false
			local route = validate(current)
			if route == nil or route.userId ~= id then
				transformError = "NOT_FOUND"
				return nil
			end
			if route.expiresAt <= (currentTime :: number) then
				transformError = "EXPIRED"
				return nil
			end
			if route.matchId ~= expectedMatchId then
				transformError = "CONFLICT"
				return nil
			end
			if route.destinationJobId ~= nil then
				if route.destinationJobId ~= destinationJobId then
					transformError = "CONFLICT"
					return nil
				end
				return route
			end
			if route.revision >= Validation.MAX_SAFE_INTEGER then
				transformError = "CONFLICT"
				return nil
			end
			local replacement = clone(route)
			replacement.revision += 1
			replacement.destinationJobId = destinationJobId
			applied = true
			return replacement
		end
	)
	if not called then
		return failure("STORE_UNAVAILABLE", "bindDestination")
	end
	if transformError ~= nil then
		return failure(transformError :: ErrorCode, "bindDestination")
	end
	local canonical = validate(stored)
	if canonical == nil or canonical.destinationJobId == nil then
		return failure("STORE_UNAVAILABLE", "bindDestination")
	end
	return Result.ok(table.freeze({ route = canonical, applied = applied }))
end

function Methods.create(self: Service, routeValue: unknown, nowValue: unknown): Result.Result<CreateOutcome, RouteError>
	local data = requireData(self)
	local route = validate(routeValue)
	if
		route == nil
		or type(nowValue) ~= "number"
		or not Validation.isSafeInteger(nowValue :: number)
		or nowValue < route.createdAt
		or nowValue >= route.expiresAt
	then
		return failure("INVALID_ARGUMENT", "create")
	end
	local applied = false
	local conflict = false
	local called, stored = pcall(
		data.adapter.updateAsync,
		data.adapter,
		routeKey(route.userId),
		route.expiresAt - (nowValue :: number),
		function(current)
			-- UpdateAsync may retry this transform. These outcomes describe only
			-- the final invocation whose value was accepted by the store.
			applied = false
			conflict = false
			local existing = validate(current)
			if existing ~= nil and existing.expiresAt > (nowValue :: number) then
				if existing.routeId == route.routeId and existing.matchId == route.matchId then
					return existing
				end
				conflict = true
				return nil
			end
			applied = true
			return route
		end
	)
	if not called then
		return failure("STORE_UNAVAILABLE", "create")
	end
	if conflict then
		return failure("CONFLICT", "create")
	end
	local canonical = validate(stored)
	if canonical == nil then
		return failure("STORE_UNAVAILABLE", "create")
	end
	return Result.ok(table.freeze({ route = canonical, applied = applied }))
end

function Methods.resolve(
	self: Service,
	userIdValue: unknown,
	routeIdValue: unknown,
	nowValue: unknown
): Result.Result<Route?, RouteError>
	local id = userId(userIdValue)
	local routeId = TravelProtocol.validateOpaqueId(routeIdValue, "route")
	if
		id == nil
		or not routeId.ok
		or type(nowValue) ~= "number"
		or not Validation.isSafeInteger(nowValue :: number)
		or nowValue < 0
	then
		return failure("INVALID_ARGUMENT", "resolve")
	end
	local found = Methods.find(self, id, nowValue)
	if not found.ok or found.value == nil or found.value.routeId ~= routeId.value then
		return Result.ok(nil)
	end
	return found
end

local function readRoute(
	data: ServiceData,
	id: number,
	nowValue: number,
	failOpen: boolean
): Result.Result<Route?, RouteError>
	local called, stored = pcall(data.adapter.getAsync, data.adapter, routeKey(id))
	if not called then
		return if failOpen then Result.ok(nil) else failure("STORE_UNAVAILABLE", "find")
	end
	local route = validate(stored)
	if route == nil or route.userId ~= id or route.expiresAt <= nowValue then
		return Result.ok(nil)
	end
	if route.destinationJobId == nil then
		return Result.ok(nil)
	end
	return Result.ok(route)
end

function Methods.find(self: Service, userIdValue: unknown, nowValue: unknown): Result.Result<Route?, RouteError>
	local id = userId(userIdValue)
	if id == nil or type(nowValue) ~= "number" or not Validation.isSafeInteger(nowValue :: number) or nowValue < 0 then
		return failure("INVALID_ARGUMENT", "find")
	end
	-- Ordinary Lobby eligibility deliberately fails open so the experience
	-- remains usable if routing storage is temporarily unavailable.
	return readRoute(requireData(self), id, nowValue :: number, true)
end

-- Tutorial recovery needs stronger evidence than the public fail-open view: a
-- storage failure is unknown state, not proof that the player's Match vanished.
function Methods.findConfirmed(
	self: Service,
	userIdValue: unknown,
	nowValue: unknown
): Result.Result<Route?, RouteError>
	local id = userId(userIdValue)
	if id == nil or type(nowValue) ~= "number" or not Validation.isSafeInteger(nowValue :: number) or nowValue < 0 then
		return failure("INVALID_ARGUMENT", "find")
	end
	return readRoute(requireData(self), id, nowValue :: number, false)
end

-- Atomically removes and returns the exact current route for a rematch. Unlike
-- find followed by clear, a transient read cannot erase an unknown prior route.
-- An unproven UpdateAsync response always fails closed. The transform may have
-- committed before the response was lost, so returning the captured route would
-- let a caller reuse a route that may already have been consumed.
function Methods.takeForMatch(
	self: Service,
	userIdValue: unknown,
	matchIdValue: unknown,
	nowValue: unknown
): Result.Result<Route, RouteError>
	local data = requireData(self)
	local id = userId(userIdValue)
	local expectedMatchId = token(matchIdValue, "match")
	if
		id == nil
		or expectedMatchId == nil
		or type(nowValue) ~= "number"
		or not Validation.isSafeInteger(nowValue :: number)
		or nowValue < 0
	then
		return failure("INVALID_ARGUMENT", "takeForMatch")
	end
	local previous: Route? = nil
	local transformError: ErrorCode? = nil
	local called = pcall(data.adapter.updateAsync, data.adapter, routeKey(id), MAX_ROUTE_SECONDS, function(current)
		-- UpdateAsync may invoke the transform more than once. Only the final
		-- invocation describes the value whose write was accepted.
		previous = nil
		transformError = nil
		local route = validate(current)
		if route == nil or route.userId ~= id or route.destinationJobId == nil then
			transformError = "NOT_FOUND"
			return nil
		elseif route.expiresAt <= (nowValue :: number) then
			transformError = "EXPIRED"
			return nil
		elseif route.matchId ~= expectedMatchId then
			transformError = "CONFLICT"
			return nil
		end
		previous = route
		return CLEARED_ROUTE_TOMBSTONE
	end)
	if not called then
		return failure("STORE_UNAVAILABLE", "takeForMatch")
	elseif previous ~= nil then
		return Result.ok(previous :: Route)
	elseif transformError ~= nil then
		return failure(transformError :: ErrorCode, "takeForMatch")
	end
	return failure("STORE_UNAVAILABLE", "takeForMatch")
end

function Methods.clear(self: Service, userIdValue: unknown, matchIdValue: unknown): Result.Result<boolean, RouteError>
	local data = requireData(self)
	local id = userId(userIdValue)
	local expectedMatchId = token(matchIdValue, "match")
	if id == nil or expectedMatchId == nil then
		return failure("INVALID_ARGUMENT", "clear")
	end
	local removed = false
	local called = pcall(data.adapter.updateAsync, data.adapter, routeKey(id), MAX_ROUTE_SECONDS, function(current)
		-- Only the final retry attempt determines whether this call removed it.
		removed = false
		local route = validate(current)
		if route == nil or route.matchId ~= expectedMatchId then
			return nil
		end
		removed = true
		return CLEARED_ROUTE_TOMBSTONE
	end)
	if not called then
		return failure("STORE_UNAVAILABLE", "clear")
	end
	return Result.ok(removed)
end

function ActiveMatchRouteService.new(adapterValue: unknown): Result.Result<Service, RouteError>
	if
		type(adapterValue) ~= "table"
		or type((adapterValue :: any).getAsync) ~= "function"
		or type((adapterValue :: any).updateAsync) ~= "function"
		or type((adapterValue :: any).removeAsync) ~= "function"
	then
		return failure("INVALID_ARGUMENT", "create")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = { adapter = adapterValue :: Adapter }
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(ActiveMatchRouteService)
