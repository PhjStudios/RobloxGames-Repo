--!strict

local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type RoutingKind = "Match" | "Rejoin" | "Return"

export type MatchRoutingData = {
	version: number,
	kind: "Match",
	ticketId: string,
	attemptId: string,
}

export type RejoinRoutingData = {
	version: number,
	kind: "Rejoin",
	routeId: string,
	attemptId: string,
}

export type ReturnRoutingData = {
	version: number,
	kind: "Return",
	returnId: string,
}

export type RoutingData = MatchRoutingData | RejoinRoutingData | ReturnRoutingData

local VERSION = 1
local MAX_OPAQUE_ID_BYTES = 80
local ID_KINDS: { [string]: boolean } = table.freeze({
	attempt = true,
	return_ = true,
	route = true,
	ticket = true,
})

local TravelProtocol = {
	VERSION = VERSION,
	MAX_OPAQUE_ID_BYTES = MAX_OPAQUE_ID_BYTES,
}

local function issue(path: { Validation.PathSegment }, message: string)
	return Result.err(Validation.issue("INVALID_FORMAT", path, message))
end

local function isExactRecord(value: unknown, fields: { [string]: boolean }): boolean
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return false
	end
	local count = 0
	for key in next, value :: { [any]: unknown } do
		if type(key) ~= "string" or fields[key] ~= true then
			return false
		end
		count += 1
	end
	local expected = 0
	for _ in fields do
		expected += 1
	end
	return count == expected
end

local function validBody(body: string): boolean
	if #body < 1 then
		return false
	end
	local previousSeparator = false
	for index = 1, #body do
		local byte = string.byte(body, index)
		local alphanumeric = (byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57)
		local separator = byte == 45 or byte == 46 or byte == 95
		if not alphanumeric and not separator then
			return false
		end
		if separator and (index == 1 or index == #body or previousSeparator) then
			return false
		end
		previousSeparator = separator
	end
	return true
end

function TravelProtocol.validateOpaqueId(value: unknown, kindValue: unknown)
	if type(kindValue) ~= "string" then
		return issue({ "kind" }, "Opaque ID kind is invalid")
	end
	local storageKind = if kindValue == "return" then "return_" else kindValue
	if ID_KINDS[storageKind] ~= true then
		return issue({ "kind" }, "Opaque ID kind is unsupported")
	end
	if type(value) ~= "string" or #value > MAX_OPAQUE_ID_BYTES then
		return issue({ "id" }, "Opaque ID has an invalid type or length")
	end
	local prefix = `{kindValue}:`
	if string.sub(value :: string, 1, #prefix) ~= prefix or not validBody(string.sub(value :: string, #prefix + 1)) then
		return issue({ "id" }, "Opaque ID is malformed")
	end
	return Result.ok(value :: string)
end

function TravelProtocol.validateRoutingData(value: unknown): Result.Result<RoutingData, Validation.Issue>
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return issue({ "payload" }, "Routing data must be one plain record")
	end
	local record = value :: { [any]: unknown }
	if rawget(record, "version") ~= VERSION or type(rawget(record, "kind")) ~= "string" then
		return issue({ "payload" }, "Routing version or kind is invalid")
	end
	local kind = rawget(record, "kind") :: string
	if kind == "Match" then
		if not isExactRecord(record, { version = true, kind = true, ticketId = true, attemptId = true }) then
			return issue({ "payload" }, "Match routing data contains unexpected fields")
		end
		local ticket = TravelProtocol.validateOpaqueId(rawget(record, "ticketId"), "ticket")
		local attempt = TravelProtocol.validateOpaqueId(rawget(record, "attemptId"), "attempt")
		if not ticket.ok then
			return issue({ "payload", "ticketId" }, "Match ticket ID is invalid")
		elseif not attempt.ok then
			return issue({ "payload", "attemptId" }, "Match attempt ID is invalid")
		end
		return Result.ok(
			table.freeze({ version = VERSION, kind = "Match", ticketId = ticket.value, attemptId = attempt.value })
		)
	elseif kind == "Rejoin" then
		if not isExactRecord(record, { version = true, kind = true, routeId = true, attemptId = true }) then
			return issue({ "payload" }, "Rejoin routing data contains unexpected fields")
		end
		local route = TravelProtocol.validateOpaqueId(rawget(record, "routeId"), "route")
		local attempt = TravelProtocol.validateOpaqueId(rawget(record, "attemptId"), "attempt")
		if not route.ok then
			return issue({ "payload", "routeId" }, "Rejoin route ID is invalid")
		elseif not attempt.ok then
			return issue({ "payload", "attemptId" }, "Rejoin attempt ID is invalid")
		end
		return Result.ok(
			table.freeze({ version = VERSION, kind = "Rejoin", routeId = route.value, attemptId = attempt.value })
		)
	elseif kind == "Return" then
		if not isExactRecord(record, { version = true, kind = true, returnId = true }) then
			return issue({ "payload" }, "Return routing data contains unexpected fields")
		end
		local returnId = TravelProtocol.validateOpaqueId(rawget(record, "returnId"), "return")
		if not returnId.ok then
			return issue({ "payload", "returnId" }, "Return ID is invalid")
		end
		return Result.ok(table.freeze({ version = VERSION, kind = "Return", returnId = returnId.value }))
	end
	return issue({ "payload", "kind" }, "Routing kind is unsupported")
end

function TravelProtocol.match(ticketId: unknown, attemptId: unknown): Result.Result<MatchRoutingData, Validation.Issue>
	return TravelProtocol.validateRoutingData({
		version = VERSION,
		kind = "Match",
		ticketId = ticketId,
		attemptId = attemptId,
	}) :: any
end

function TravelProtocol.rejoin(routeId: unknown, attemptId: unknown): Result.Result<RejoinRoutingData, Validation.Issue>
	return TravelProtocol.validateRoutingData({
		version = VERSION,
		kind = "Rejoin",
		routeId = routeId,
		attemptId = attemptId,
	}) :: any
end

function TravelProtocol.returnToLobby(returnId: unknown): Result.Result<ReturnRoutingData, Validation.Issue>
	return TravelProtocol.validateRoutingData({ version = VERSION, kind = "Return", returnId = returnId }) :: any
end

return table.freeze(TravelProtocol)
