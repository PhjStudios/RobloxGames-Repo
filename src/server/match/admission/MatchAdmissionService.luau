--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type AdmissionKind = "Participant" | "Rejoined" | "LateSpectator"
export type AdmissionOutcome = {
	kind: AdmissionKind,
	userId: number,
	matchId: string,
	ticketId: string,
	loadout: unknown,
}
export type ErrorCode =
	"INVALID_ARGUMENT"
	| "MALFORMED_JOIN_DATA"
	| "UNEXPECTED_PLAYER"
	| "STALE_TICKET"
	| "WRONG_DESTINATION"
	| "ALREADY_CONSUMED"
	| "PROFILE_CONFLICT"
	| "DUPLICATE_CONNECTION"
	| "STALE_ROUTE"
	| "UNAVAILABLE"
	| "CLEANED"
export type Operation = "admit" | "disconnect" | "return" | "retryReturns" | "resolve" | "cleanup"
export type AdmissionError = { code: ErrorCode, operation: Operation }
export type Dependencies = {
	getUserId: ((unknown) -> unknown)?,
	isLive: ((unknown) -> unknown)?,
	validateProfile: ((number, unknown) -> unknown)?,
	validateRejoinProfile: ((number, unknown) -> unknown)?,
	graceSeconds: number?,
}

type TicketStore = {
	get: (self: TicketStore, ticketId: unknown, nowValue: unknown) -> any,
	claimDestination: (self: TicketStore, ticketId: unknown, jobId: unknown, nowValue: unknown) -> any,
	markAdmission: (
		self: TicketStore,
		ticketId: unknown,
		jobId: unknown,
		userId: unknown,
		state: unknown,
		nowValue: unknown
	) -> any,
}
type RouteService = {
	resolve: (self: RouteService, userId: unknown, routeId: unknown, nowValue: unknown) -> any,
}
type Binding = AdmissionOutcome & { player: unknown }
type ServiceData = {
	ticketStore: TicketStore,
	routeService: RouteService,
	getUserId: (unknown) -> unknown,
	isLive: (unknown) -> unknown,
	validateProfile: (number, unknown) -> unknown,
	validateRejoinProfile: (number, unknown) -> unknown,
	graceSeconds: number,
	bindingsByPlayer: { [any]: Binding },
	bindingsByUserId: { [number]: Binding },
	retainedParticipantsByUserId: { [number]: AdmissionOutcome },
	cachedAdmissionByUserId: { [number]: "Expected" | "Admitted" | "LateSpectator" | "Returned" },
	returnedByUserId: { [number]: boolean },
	pendingReturnsByUserId: {
		[number]: { ticketId: string, matchId: string, destinationJobId: string, userId: number },
	},
	boundTicket: any?,
	boundTicketId: string?,
	boundMatchId: string?,
	cleaned: boolean,
}

local DEFAULT_GRACE_SECONDS = 30
local MAX_GRACE_SECONDS = 60

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }

local MatchAdmissionService = {
	DEFAULT_GRACE_SECONDS = DEFAULT_GRACE_SECONDS,
}

local function failure<T>(code: ErrorCode, operation: Operation): Result.Failure<AdmissionError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_MATCH_ADMISSION][code=INVALID_CONTEXT]", 0)
	end
	return data :: ServiceData
end

local function successful(value: unknown): boolean
	return type(value) == "table" and (value :: any).ok == true
end

local function errorCode(value: unknown): string?
	return if type(value) == "table"
			and type((value :: any).error) == "table"
			and type((value :: any).error.code) == "string"
		then (value :: any).error.code
		else nil
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

local function isLive(data: ServiceData, player: unknown): boolean
	local called, value = pcall(data.isLive, player)
	return called and value == true
end

local function memberFor(ticket: any, userId: number): any?
	if type(ticket) ~= "table" or type(ticket.members) ~= "table" then
		return nil
	end
	for _, member in ticket.members do
		if type(member) == "table" and member.userId == userId then
			return member
		end
	end
	return nil
end

local function profileMatches(data: ServiceData, userId: number, loadout: unknown): boolean
	local called, value = pcall(data.validateProfile, userId, loadout)
	return called and value == true
end

local function rejoinProfileMatches(data: ServiceData, userId: number, loadout: unknown): boolean
	local called, value = pcall(data.validateRejoinProfile, userId, loadout)
	return called and value == true
end

local function ticketFromResult(value: unknown): any?
	if not successful(value) then
		return nil
	end
	local resultValue = (value :: any).value
	if type(resultValue) ~= "table" then
		return nil
	end
	return if type(resultValue.ticket) == "table" then resultValue.ticket else resultValue
end

local function rereadTicket(data: ServiceData, ticketId: string, nowValue: number): any?
	local called, value = pcall(data.ticketStore.get, data.ticketStore, ticketId, nowValue)
	return if called then ticketFromResult(value) else nil
end

local function exactDestination(ticket: any, ticketId: string, destinationJobId: string): boolean
	return type(ticket) == "table"
		and ticket.ticketId == ticketId
		and ticket.claimedDestinationJobId == destinationJobId
		and type(ticket.claimedDestinationAt) == "number"
end

local function exactAdmission(
	ticket: any,
	ticketId: string,
	destinationJobId: string,
	userId: number,
	targetState: "Admitted" | "LateSpectator"
): boolean
	local member = memberFor(ticket, userId)
	return exactDestination(ticket, ticketId, destinationJobId)
		and member ~= nil
		and member.admissionState == targetState
end

local function mapTicketError(value: unknown): ErrorCode
	local code = errorCode(value)
	if code == "EXPIRED" or code == "NOT_FOUND" then
		return "STALE_TICKET"
	elseif code == "DESTINATION_CONFLICT" then
		return "WRONG_DESTINATION"
	elseif code == "UNEXPECTED_MEMBER" then
		return "UNEXPECTED_PLAYER"
	elseif code == "INVALID_STATE" then
		return "ALREADY_CONSUMED"
	end
	return "UNAVAILABLE"
end

local function bind(
	data: ServiceData,
	player: unknown,
	outcome: AdmissionOutcome
): Result.Result<AdmissionOutcome, AdmissionError>
	if data.bindingsByPlayer[player :: any] ~= nil or data.bindingsByUserId[outcome.userId] ~= nil then
		return failure("DUPLICATE_CONNECTION", "admit")
	end
	if
		data.boundTicketId ~= nil and (data.boundTicketId ~= outcome.ticketId or data.boundMatchId ~= outcome.matchId)
	then
		return failure("WRONG_DESTINATION", "admit")
	end
	local binding: Binding = {
		kind = outcome.kind,
		userId = outcome.userId,
		matchId = outcome.matchId,
		ticketId = outcome.ticketId,
		loadout = outcome.loadout,
		player = player,
	}
	data.boundTicketId = outcome.ticketId
	data.boundMatchId = outcome.matchId
	data.bindingsByPlayer[player :: any] = binding
	data.bindingsByUserId[outcome.userId] = binding
	if outcome.kind == "Participant" or outcome.kind == "Rejoined" then
		data.retainedParticipantsByUserId[outcome.userId] = table.freeze({
			kind = "Participant",
			userId = outcome.userId,
			matchId = outcome.matchId,
			ticketId = outcome.ticketId,
			loadout = outcome.loadout,
		})
	end
	return Result.ok(table.freeze(outcome))
end

local function cacheTicket(data: ServiceData, ticket: any)
	data.boundTicket = ticket
	for _, member in ticket.members do
		if member.admissionState == "Returned" then
			data.cachedAdmissionByUserId[member.userId] = "Returned"
			data.returnedByUserId[member.userId] = true
		elseif data.cachedAdmissionByUserId[member.userId] == nil then
			data.cachedAdmissionByUserId[member.userId] = member.admissionState
		end
	end
end

local function initialAdmission(
	data: ServiceData,
	player: unknown,
	userId: number,
	ticketId: string,
	destinationJobId: string,
	nowValue: number
): Result.Result<AdmissionOutcome, AdmissionError>
	local got, getResult = pcall(data.ticketStore.get, data.ticketStore, ticketId, nowValue)
	if not got or not successful(getResult) then
		return failure(if got then mapTicketError(getResult) else "UNAVAILABLE", "admit")
	end
	local ticket = ticketFromResult(getResult)
	local member = memberFor(ticket, userId)
	if ticket == nil or member == nil then
		return failure("UNEXPECTED_PLAYER", "admit")
	end
	if member.admissionState ~= "Expected" then
		return failure("ALREADY_CONSUMED", "admit")
	end
	if not profileMatches(data, userId, member.loadout) then
		return failure("PROFILE_CONFLICT", "admit")
	end
	if data.boundTicketId ~= nil and (data.boundTicketId ~= ticketId or data.boundMatchId ~= ticket.matchId) then
		return failure("WRONG_DESTINATION", "admit")
	end
	local claimed, claimResult =
		pcall(data.ticketStore.claimDestination, data.ticketStore, ticketId, destinationJobId, nowValue)
	if not claimed or not successful(claimResult) then
		local canonical = rereadTicket(data, ticketId, nowValue)
		if not exactDestination(canonical, ticketId, destinationJobId) then
			if type(canonical) == "table" and canonical.claimedDestinationJobId ~= nil then
				return failure("WRONG_DESTINATION", "admit")
			end
			return failure(if claimed then mapTicketError(claimResult) else "UNAVAILABLE", "admit")
		end
		ticket = canonical
	else
		ticket = ticketFromResult(claimResult)
	end
	member = memberFor(ticket, userId)
	if ticket == nil or member == nil or type(ticket.claimedDestinationAt) ~= "number" then
		return failure("UNAVAILABLE", "admit")
	end
	cacheTicket(data, ticket)
	local late = nowValue >= ticket.claimedDestinationAt + data.graceSeconds
	local targetState = if late then "LateSpectator" else "Admitted"
	local marked, markResult = pcall(
		data.ticketStore.markAdmission,
		data.ticketStore,
		ticketId,
		destinationJobId,
		userId,
		targetState,
		nowValue
	)
	local markedTicket = ticketFromResult(markResult)
	if not marked or not successful(markResult) then
		markedTicket = rereadTicket(data, ticketId, nowValue)
		if not exactAdmission(markedTicket, ticketId, destinationJobId, userId, targetState) then
			return failure(if marked then mapTicketError(markResult) else "UNAVAILABLE", "admit")
		end
	end
	if markedTicket ~= nil then
		data.boundTicket = markedTicket
	end
	data.cachedAdmissionByUserId[userId] = targetState
	local outcome: AdmissionOutcome = {
		kind = if late then "LateSpectator" else "Participant",
		userId = userId,
		matchId = ticket.matchId,
		ticketId = ticketId,
		loadout = member.loadout,
	}
	return bind(data, player, outcome)
end

local function rejoinAdmission(
	data: ServiceData,
	player: unknown,
	userId: number,
	routeId: string,
	destinationJobId: string,
	nowValue: number
): Result.Result<AdmissionOutcome, AdmissionError>
	local resolved, routeResult = pcall(data.routeService.resolve, data.routeService, userId, routeId, nowValue)
	if not resolved or not successful(routeResult) or (routeResult :: any).value == nil then
		return failure("STALE_ROUTE", "admit")
	end
	local route = (routeResult :: any).value
	if type(route) ~= "table" or route.destinationJobId ~= destinationJobId then
		return failure("WRONG_DESTINATION", "admit")
	end
	local ticket = data.boundTicket
	local retained = data.retainedParticipantsByUserId[userId]
	local member = memberFor(ticket, userId)
	if
		ticket == nil
		or member == nil
		or ticket.ticketId ~= route.ticketId
		or ticket.matchId ~= route.matchId
		or ticket.claimedDestinationJobId ~= destinationJobId
	then
		return failure("STALE_ROUTE", "admit")
	end
	if retained ~= nil then
		if
			retained.ticketId ~= ticket.ticketId
			or retained.matchId ~= ticket.matchId
			or not rejoinProfileMatches(data, userId, retained.loadout)
		then
			return failure("PROFILE_CONFLICT", "admit")
		end
		return bind(data, player, {
			kind = "Rejoined",
			userId = userId,
			matchId = retained.matchId,
			ticketId = retained.ticketId,
			loadout = retained.loadout,
		})
	end
	if data.cachedAdmissionByUserId[userId] ~= "Expected" or type(ticket.claimedDestinationAt) ~= "number" then
		return failure("STALE_ROUTE", "admit")
	end
	if not profileMatches(data, userId, member.loadout) then
		return failure("PROFILE_CONFLICT", "admit")
	end
	local late = nowValue >= ticket.claimedDestinationAt + data.graceSeconds
	local targetState = if late then "LateSpectator" else "Admitted"
	local marked, markResult = pcall(
		data.ticketStore.markAdmission,
		data.ticketStore,
		ticket.ticketId,
		destinationJobId,
		userId,
		targetState,
		nowValue
	)
	local markedTicket = ticketFromResult(markResult)
	if not marked or not successful(markResult) then
		markedTicket = rereadTicket(data, ticket.ticketId, nowValue)
		if exactAdmission(markedTicket, ticket.ticketId, destinationJobId, userId, targetState) then
			data.boundTicket = markedTicket
		else
			local code = if marked then errorCode(markResult) else nil
			-- A bound Match host may outlive its ten-minute pre-admission ticket.
			-- Only a never-admitted expected member with a still-live authenticated
			-- route may fail open to a non-rewarding spectator after grace.
			if not late or (code ~= "EXPIRED" and code ~= "NOT_FOUND") then
				return failure(if marked then mapTicketError(markResult) else "UNAVAILABLE", "admit")
			end
		end
	else
		if markedTicket ~= nil then
			data.boundTicket = markedTicket
		end
	end
	data.cachedAdmissionByUserId[userId] = targetState
	local outcome: AdmissionOutcome = {
		kind = if late then "LateSpectator" else "Participant",
		userId = userId,
		matchId = ticket.matchId,
		ticketId = ticket.ticketId,
		loadout = member.loadout,
	}
	return bind(data, player, outcome)
end

function Methods.admit(
	self: Service,
	player: unknown,
	routingDataValue: unknown,
	destinationJobIdValue: unknown,
	nowValue: unknown
): Result.Result<AdmissionOutcome, AdmissionError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "admit")
	end
	local userId = readUserId(data, player)
	if
		userId == nil
		or not isLive(data, player)
		or type(destinationJobIdValue) ~= "string"
		or #destinationJobIdValue < 1
		or #destinationJobIdValue > 100
		or type(nowValue) ~= "number"
		or not Validation.isSafeInteger(nowValue :: number)
		or nowValue < 0
	then
		return failure("INVALID_ARGUMENT", "admit")
	end
	if data.bindingsByPlayer[player :: any] ~= nil or data.bindingsByUserId[userId] ~= nil then
		return failure("DUPLICATE_CONNECTION", "admit")
	end
	if data.returnedByUserId[userId] then
		return failure("ALREADY_CONSUMED", "admit")
	end
	local routing = TravelProtocol.validateRoutingData(routingDataValue)
	if not routing.ok or routing.value.kind == "Return" then
		return failure("MALFORMED_JOIN_DATA", "admit")
	end
	if routing.value.kind == "Match" then
		return initialAdmission(
			data,
			player,
			userId,
			routing.value.ticketId,
			destinationJobIdValue :: string,
			nowValue :: number
		)
	end
	return rejoinAdmission(
		data,
		player,
		userId,
		routing.value.routeId,
		destinationJobIdValue :: string,
		nowValue :: number
	)
end

local function attemptReturned(data: ServiceData, pending: any, nowValue: number): boolean
	local marked, markResult = pcall(
		data.ticketStore.markAdmission,
		data.ticketStore,
		pending.ticketId,
		pending.destinationJobId,
		pending.userId,
		"Returned",
		nowValue
	)
	local markedTicket = if marked then ticketFromResult(markResult) else nil
	if marked and successful(markResult) then
		if markedTicket ~= nil then
			data.boundTicket = markedTicket
		end
		data.pendingReturnsByUserId[pending.userId] = nil
		return true
	end
	local canonical = rereadTicket(data, pending.ticketId, nowValue)
	local member = memberFor(canonical, pending.userId)
	if
		exactDestination(canonical, pending.ticketId, pending.destinationJobId)
		and member ~= nil
		and member.admissionState == "Returned"
	then
		data.boundTicket = canonical
		data.pendingReturnsByUserId[pending.userId] = nil
		return true
	end
	return false
end

function Methods.markReturned(self: Service, player: unknown, nowValue: unknown): Result.Result<boolean, AdmissionError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "return")
	end
	if type(nowValue) ~= "number" or not Validation.isSafeInteger(nowValue :: number) or nowValue < 0 then
		return failure("INVALID_ARGUMENT", "return")
	end
	local binding = data.bindingsByPlayer[player :: any]
	local userId = if binding == nil then readUserId(data, player) else binding.userId
	if userId == nil then
		return failure("INVALID_ARGUMENT", "return")
	end
	if data.returnedByUserId[userId] then
		local pending = data.pendingReturnsByUserId[userId]
		return Result.ok(if pending == nil then true else attemptReturned(data, pending, nowValue :: number))
	end
	if
		binding == nil
		or data.boundTicketId ~= binding.ticketId
		or data.boundMatchId ~= binding.matchId
		or type(data.boundTicket) ~= "table"
		or data.boundTicket.claimedDestinationJobId == nil
	then
		return failure("UNEXPECTED_PLAYER", "return")
	end
	data.returnedByUserId[userId] = true
	data.cachedAdmissionByUserId[userId] = "Returned"
	data.retainedParticipantsByUserId[userId] = nil
	data.bindingsByPlayer[player :: any] = nil
	if data.bindingsByUserId[userId] == binding then
		data.bindingsByUserId[userId] = nil
	end
	local pending = {
		ticketId = binding.ticketId,
		matchId = binding.matchId,
		destinationJobId = data.boundTicket.claimedDestinationJobId,
		userId = userId,
	}
	data.pendingReturnsByUserId[userId] = pending
	return Result.ok(attemptReturned(data, pending, nowValue :: number))
end

function Methods.retryReturns(self: Service, nowValue: unknown): Result.Result<number, AdmissionError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "retryReturns")
	end
	if type(nowValue) ~= "number" or not Validation.isSafeInteger(nowValue :: number) or nowValue < 0 then
		return failure("INVALID_ARGUMENT", "retryReturns")
	end
	local resolved = 0
	for _, pending in data.pendingReturnsByUserId do
		if attemptReturned(data, pending, nowValue :: number) then
			resolved += 1
		end
	end
	return Result.ok(resolved)
end

function Methods.disconnect(self: Service, player: unknown): Result.Result<AdmissionOutcome?, AdmissionError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "disconnect")
	end
	local binding = data.bindingsByPlayer[player :: any]
	if binding == nil then
		return Result.ok(nil)
	end
	data.bindingsByPlayer[player :: any] = nil
	if data.bindingsByUserId[binding.userId] == binding then
		data.bindingsByUserId[binding.userId] = nil
	end
	return Result.ok(table.freeze({
		kind = binding.kind,
		userId = binding.userId,
		matchId = binding.matchId,
		ticketId = binding.ticketId,
		loadout = binding.loadout,
	}))
end

function Methods.resolve(self: Service, player: unknown): Result.Result<AdmissionOutcome, AdmissionError>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED", "resolve")
	end
	local binding = data.bindingsByPlayer[player :: any]
	if binding == nil or data.bindingsByUserId[binding.userId] ~= binding or not isLive(data, player) then
		return failure("UNEXPECTED_PLAYER", "resolve")
	end
	return Result.ok(table.freeze({
		kind = binding.kind,
		userId = binding.userId,
		matchId = binding.matchId,
		ticketId = binding.ticketId,
		loadout = binding.loadout,
	}))
end

function Methods.getMetrics(self: Service): { participantCount: number, spectatorCount: number, cleaned: boolean }
	local data = requireData(self)
	local participants = 0
	local spectators = 0
	for _, binding in data.bindingsByUserId do
		if binding.kind == "LateSpectator" then
			spectators += 1
		else
			participants += 1
		end
	end
	return table.freeze({ participantCount = participants, spectatorCount = spectators, cleaned = data.cleaned })
end

function Methods.cleanup(self: Service): Result.Result<boolean, AdmissionError>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(false)
	end
	data.cleaned = true
	table.clear(data.bindingsByPlayer)
	table.clear(data.bindingsByUserId)
	table.clear(data.retainedParticipantsByUserId)
	table.clear(data.cachedAdmissionByUserId)
	table.clear(data.returnedByUserId)
	table.clear(data.pendingReturnsByUserId)
	data.boundTicket = nil
	data.boundTicketId = nil
	data.boundMatchId = nil
	return Result.ok(true)
end

function MatchAdmissionService.new(
	ticketStoreValue: unknown,
	routeServiceValue: unknown,
	dependenciesValue: Dependencies?
): Result.Result<Service, AdmissionError>
	if
		type(ticketStoreValue) ~= "table"
		or type((ticketStoreValue :: any).get) ~= "function"
		or type((ticketStoreValue :: any).claimDestination) ~= "function"
		or type((ticketStoreValue :: any).markAdmission) ~= "function"
		or type(routeServiceValue) ~= "table"
		or type((routeServiceValue :: any).resolve) ~= "function"
		or (
			dependenciesValue ~= nil
			and (type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil)
		)
	then
		return failure("INVALID_ARGUMENT", "admit")
	end
	local dependencies = dependenciesValue or {}
	local graceSeconds = dependencies.graceSeconds or DEFAULT_GRACE_SECONDS
	if
		(dependencies.getUserId ~= nil and type(dependencies.getUserId) ~= "function")
		or (dependencies.isLive ~= nil and type(dependencies.isLive) ~= "function")
		or (dependencies.validateProfile ~= nil and type(dependencies.validateProfile) ~= "function")
		or (dependencies.validateRejoinProfile ~= nil and type(dependencies.validateRejoinProfile) ~= "function")
		or type(graceSeconds) ~= "number"
		or not Validation.isSafeInteger(graceSeconds)
		or graceSeconds < 1
		or graceSeconds > MAX_GRACE_SECONDS
	then
		return failure("INVALID_ARGUMENT", "admit")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		ticketStore = ticketStoreValue :: TicketStore,
		routeService = routeServiceValue :: RouteService,
		getUserId = dependencies.getUserId or function(player: unknown): unknown
			return if typeof(player) == "Instance" and (player :: Instance):IsA("Player")
				then (player :: Player).UserId
				else nil
		end,
		isLive = dependencies.isLive or function(player: unknown): unknown
			return typeof(player) == "Instance"
				and (player :: Instance):IsA("Player")
				and (player :: Player).Parent ~= nil
		end,
		validateProfile = dependencies.validateProfile or function(_userId: number, _loadout: unknown): unknown
			return false
		end,
		validateRejoinProfile = dependencies.validateRejoinProfile
			or dependencies.validateProfile
			or function(_userId: number, _loadout: unknown): unknown
				return false
			end,
		graceSeconds = graceSeconds,
		bindingsByPlayer = setmetatable({}, { __mode = "k" }),
		bindingsByUserId = {},
		retainedParticipantsByUserId = {},
		cachedAdmissionByUserId = {},
		returnedByUserId = {},
		pendingReturnsByUserId = {},
		boundTicket = nil,
		boundTicketId = nil,
		boundMatchId = nil,
		cleaned = false,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(MatchAdmissionService)
