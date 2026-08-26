--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local PayloadValidation = require(ReplicatedStorage.Shared.network.PayloadValidation)
local ProductionRemotes = require(ReplicatedStorage.Shared.network.ProductionRemotes)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)

export type ErrorCode =
	"INVALID_CONTEXT"
	| "INVALID_REGISTRY"
	| "INVALID_ROLE"
	| "PLACE_ROLE_UNRESOLVED"
	| "UNKNOWN_ENDPOINT"
	| "INACTIVE_ENDPOINT"
	| "WRONG_DIRECTION"
	| "WRONG_KIND"
	| "INVALID_REQUEST_SCHEMA"
	| "INVALID_RESPONSE_SCHEMA"
	| "RESPONSE_SCHEMA_MISMATCH"
	| "DUPLICATE_REGISTRATION"
	| "UNREGISTERED_ENDPOINT"
	| "UNEXPECTED_RESPONSE_ENDPOINT"
	| "PENDING_LIMIT_REACHED"
	| "ID_GENERATION_FAILED"
	| "INVALID_PAYLOAD"
	| "INVALID_PENDING"
	| "MALFORMED_RESPONSE"
	| "MISMATCHED_RESPONSE"
	| "STALE_RESPONSE"

export type Error = {
	code: ErrorCode,
	path: string,
	message: string,
}

export type IdGenerator = () -> unknown

export type BuiltRequest = {
	definition: RemoteRegistry.Definition,
	envelope: RequestProtocol.RawRequest,
	pending: RequestProtocol.Pending?,
}

export type Stats = {
	registrationCount: number,
	pendingCount: number,
	terminalIdCount: number,
}

type Registration = {
	definition: RemoteRegistry.Definition,
	requestSchema: PayloadValidation.Schema,
	responseSchema: PayloadValidation.Schema?,
}

type PendingEntry = {
	definition: RemoteRegistry.Definition,
	pending: RequestProtocol.Pending,
}

type TrackerData = {
	registry: RemoteRegistry.Registry,
	role: RemoteRegistry.RuntimePlaceRole,
	generator: IdGenerator,
	activeByName: { [string]: RemoteRegistry.Definition },
	registrations: { [string]: Registration },
	registrationsByDefinition: { [any]: Registration },
	registrationCount: number,
	pendingById: { [string]: PendingEntry },
	pendingCount: number,
	terminalRing: { string },
	terminalHead: number,
	terminalCount: number,
	terminalSet: { [string]: boolean },
}

local TrackerMethods = {}
TrackerMethods.__index = TrackerMethods

export type Tracker = typeof(setmetatable({} :: {}, TrackerMethods))

export type TrackerResult = Result.Result<Tracker, Error>
export type RegistrationResult = Result.Result<RemoteRegistry.Definition, Error>
export type BuildResult = Result.Result<BuiltRequest, Error>
export type ResponseResult = Result.Result<RequestProtocol.Response, Error>
export type CancelResult = Result.Result<RequestProtocol.Pending, Error>
export type TestConstructor = (
	RemoteRegistry.Registry,
	RemoteRegistry.RuntimePlaceRole,
	IdGenerator
) -> TrackerResult

local MAX_PENDING = 32
local MAX_TERMINAL_IDS = 128
local MAX_GENERATION_ATTEMPTS = 8

local TRACKER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: TrackerData }

local ClientRequestTracker = {
	MAX_PENDING = MAX_PENDING,
	MAX_TERMINAL_IDS = MAX_TERMINAL_IDS,
	MAX_GENERATION_ATTEMPTS = MAX_GENERATION_ATTEMPTS,
	newForTests = nil :: TestConstructor?,
}

local function failure(code: ErrorCode, path: string, message: string)
	return Result.err(table.freeze({
		code = code,
		path = path,
		message = message,
	}))
end

local function requireData(value: unknown): TrackerData
	if type(value) ~= "table" then
		error("[ATD_CLIENT_REQUEST_TRACKER][code=INVALID_CONTEXT]", 0)
	end
	local data = TRACKER_DATA[value :: any]
	if data == nil then
		error("[ATD_CLIENT_REQUEST_TRACKER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function defaultGenerator(): string
	return HttpService:GenerateGUID(false)
end

local function addTerminalId(data: TrackerData, requestId: string)
	if rawget(data.terminalSet, requestId) == true then
		return
	end

	if data.terminalCount < MAX_TERMINAL_IDS then
		local index = ((data.terminalHead + data.terminalCount - 1) % MAX_TERMINAL_IDS) + 1
		rawset(data.terminalRing, index, requestId)
		data.terminalCount += 1
	else
		local evicted = rawget(data.terminalRing, data.terminalHead)
		if evicted ~= nil then
			rawset(data.terminalSet, evicted, nil)
		end
		rawset(data.terminalRing, data.terminalHead, requestId)
		data.terminalHead = (data.terminalHead % MAX_TERMINAL_IDS) + 1
	end

	rawset(data.terminalSet, requestId, true)
end

local function removePending(data: TrackerData, requestId: string): PendingEntry?
	local entry = rawget(data.pendingById, requestId)
	if entry ~= nil then
		rawset(data.pendingById, requestId, nil)
		data.pendingCount -= 1
	end
	return entry
end

local function generateRequestId(data: TrackerData): RequestProtocol.RequestId?
	for _ = 1, MAX_GENERATION_ATTEMPTS do
		local generated, rawValue = pcall(data.generator)
		if generated then
			local requestIdResult = RequestProtocol.createRequestId(rawValue)
			if requestIdResult.ok then
				local value = requestIdResult.value.value
				if rawget(data.pendingById, value) == nil and rawget(data.terminalSet, value) ~= true then
					return requestIdResult.value
				end
			end
		end
	end
	return nil
end

local function createWithDependencies(
	registry: RemoteRegistry.Registry,
	role: RemoteRegistry.RuntimePlaceRole,
	generator: IdGenerator
): TrackerResult
	if not RemoteRegistry.isRegistry(registry) then
		return failure("INVALID_REGISTRY", "registry", "Client request tracking requires an authentic registry")
	end
	if role ~= "Development" and role ~= "Lobby" and role ~= "Match" then
		return failure("INVALID_ROLE", "role", "Client request tracking requires Development, Lobby, or Match")
	end
	if type(generator) ~= "function" then
		return failure("ID_GENERATION_FAILED", "generator", "The request ID generator must be a function")
	end

	local activeByName: { [string]: RemoteRegistry.Definition } = {}
	for _, definition in registry:listForRole(role) do
		activeByName[definition.name] = definition
	end

	local tracker = setmetatable({}, TrackerMethods) :: Tracker
	table.freeze(tracker)
	TRACKER_DATA[tracker] = {
		registry = registry,
		role = role,
		generator = generator,
		activeByName = activeByName,
		registrations = {},
		registrationsByDefinition = {},
		registrationCount = 0,
		pendingById = {},
		pendingCount = 0,
		terminalRing = table.create(MAX_TERMINAL_IDS),
		terminalHead = 1,
		terminalCount = 0,
		terminalSet = {},
	}
	return Result.ok(tracker)
end

function TrackerMethods.register(
	self: Tracker,
	endpointName: unknown,
	requestSchema: unknown,
	responseSchema: unknown
): RegistrationResult
	local data = requireData(self)
	local definition = if type(endpointName) == "string" then data.registry:get(endpointName) else nil
	if definition == nil then
		return failure("UNKNOWN_ENDPOINT", "endpoint", "Registration requires one fixed registry endpoint")
	end
	if rawget(data.activeByName, definition.name) ~= definition then
		return failure("INACTIVE_ENDPOINT", "endpoint", "The fixed endpoint is inactive for this place role")
	end
	if definition.direction ~= "ClientToServer" then
		return failure("WRONG_DIRECTION", "endpoint", "Client requests require a client-to-server definition")
	end
	if definition.kind ~= "Request" then
		return failure("WRONG_KIND", "endpoint", "Client request tracking requires a Request definition")
	end
	if not PayloadValidation.isSchema(requestSchema) then
		return failure("INVALID_REQUEST_SCHEMA", "requestSchema", "Registration requires an authentic request schema")
	end
	if definition.response == "Required" then
		if not PayloadValidation.isSchema(responseSchema) then
			return failure(
				"INVALID_RESPONSE_SCHEMA",
				"responseSchema",
				"A response-required definition requires an authentic response schema"
			)
		end
	elseif responseSchema ~= nil then
		return failure(
			"RESPONSE_SCHEMA_MISMATCH",
			"responseSchema",
			"A no-response definition cannot register a response schema"
		)
	end
	if rawget(data.registrations, definition.name) ~= nil then
		return failure("DUPLICATE_REGISTRATION", "endpoint", "The fixed endpoint is already registered")
	end

	local registration = table.freeze({
		definition = definition,
		requestSchema = requestSchema :: PayloadValidation.Schema,
		responseSchema = responseSchema :: PayloadValidation.Schema?,
	})
	data.registrations[definition.name] = registration
	rawset(data.registrationsByDefinition, definition, registration)
	data.registrationCount += 1
	return Result.ok(definition)
end

function TrackerMethods.buildRequest(self: Tracker, endpointName: unknown, payload: unknown): BuildResult
	local data = requireData(self)
	local registration = if type(endpointName) == "string" then rawget(data.registrations, endpointName) else nil
	if registration == nil then
		return failure("UNREGISTERED_ENDPOINT", "endpoint", "Request construction requires a registered endpoint")
	end

	local requiresResponse = registration.definition.response == "Required"
	if requiresResponse and data.pendingCount >= MAX_PENDING then
		return failure("PENDING_LIMIT_REACHED", "pending", "The global pending-request limit is reached")
	end

	local payloadResult = registration.requestSchema:validate(payload)
	if not payloadResult.ok or payloadResult.value == nil then
		local path = if payloadResult.ok then "payload" else payloadResult.error.path
		return failure("INVALID_PAYLOAD", path, "Request payload failed its fixed schema")
	end

	local requestId = generateRequestId(data)
	if requestId == nil then
		return failure("ID_GENERATION_FAILED", "requestId", "A unique bounded request ID could not be generated")
	end
	local envelopeResult = RequestProtocol.buildRequest(requestId, payloadResult.value)
	if not envelopeResult.ok then
		return failure("INVALID_PAYLOAD", "payload", "Request payload could not form the exact wire envelope")
	end

	local pending: RequestProtocol.Pending? = nil
	if requiresResponse then
		local pendingResult = RequestProtocol.createPending(requestId)
		if not pendingResult.ok then
			return failure("ID_GENERATION_FAILED", "requestId", "Pending state could not be created safely")
		end
		pending = pendingResult.value
		rawset(data.pendingById, requestId.value, {
			definition = registration.definition,
			pending = pending,
		})
		data.pendingCount += 1
	else
		addTerminalId(data, requestId.value)
	end

	return Result.ok(table.freeze({
		definition = registration.definition,
		envelope = envelopeResult.value,
		pending = pending,
	}))
end

function TrackerMethods.handleResponse(
	self: Tracker,
	definition: unknown,
	responseValue: unknown,
	...: unknown
): ResponseResult
	local data = requireData(self)
	local registration = rawget(data.registrationsByDefinition, definition)
	if registration == nil then
		return failure(
			"UNREGISTERED_ENDPOINT",
			"endpoint",
			"Response handling requires a captured registered definition"
		)
	end
	if registration.definition.response ~= "Required" or registration.responseSchema == nil then
		return failure("UNEXPECTED_RESPONSE_ENDPOINT", "endpoint", "A no-response definition cannot accept a response")
	end

	local parsedResult = RequestProtocol.parseResponse(responseValue, ...)
	if not parsedResult.ok then
		return failure("MALFORMED_RESPONSE", parsedResult.error.path, "Response failed the exact public envelope")
	end
	local parsed = parsedResult.value
	local requestId = parsed.requestId.value
	local entry = rawget(data.pendingById, requestId)
	if entry == nil then
		return failure("STALE_RESPONSE", "response.requestId", "Response does not match a live pending request")
	end
	if entry.definition ~= registration.definition then
		return failure(
			"MISMATCHED_RESPONSE",
			"response.requestId",
			"Response arrived through a different fixed endpoint"
		)
	end

	local terminal: RequestProtocol.Response
	if RequestProtocol.isSuccess(parsed) then
		local payloadResult = (registration.responseSchema :: PayloadValidation.Schema):validate(parsed.payload)
		if not payloadResult.ok or payloadResult.value == nil then
			local path = if payloadResult.ok then "payload" else payloadResult.error.path
			return failure("MALFORMED_RESPONSE", path, "Success payload failed its fixed response schema")
		end
		local successResult = RequestProtocol.createSuccess(entry.pending.requestId, payloadResult.value)
		if not successResult.ok then
			return failure("MALFORMED_RESPONSE", "response", "Success state could not be canonicalized safely")
		end
		terminal = successResult.value
	else
		local rejectedResult =
			RequestProtocol.createRejected(entry.pending.requestId, (parsed :: RequestProtocol.Rejected).error)
		if not rejectedResult.ok then
			return failure("MALFORMED_RESPONSE", "response", "Rejected state could not be canonicalized safely")
		end
		terminal = rejectedResult.value
	end

	removePending(data, requestId)
	addTerminalId(data, requestId)
	return Result.ok(terminal)
end

function TrackerMethods.cancel(self: Tracker, pending: unknown): CancelResult
	local data = requireData(self)
	if not RequestProtocol.isPending(pending) then
		return failure("INVALID_PENDING", "pending", "Cancellation requires an authentic live Pending state")
	end
	local canonicalPending = pending :: RequestProtocol.Pending
	local requestId = canonicalPending.requestId.value
	local entry = rawget(data.pendingById, requestId)
	if entry == nil or entry.pending ~= canonicalPending then
		return failure("INVALID_PENDING", "pending", "Cancellation requires an authentic live Pending state")
	end

	removePending(data, requestId)
	addTerminalId(data, requestId)
	return Result.ok(canonicalPending)
end

function TrackerMethods.clear(self: Tracker)
	local data = requireData(self)
	table.clear(data.pendingById)
	table.clear(data.terminalRing)
	table.clear(data.terminalSet)
	data.pendingCount = 0
	data.terminalHead = 1
	data.terminalCount = 0
end

function TrackerMethods.getStats(self: Tracker): Stats
	local data = requireData(self)
	return table.freeze({
		registrationCount = data.registrationCount,
		pendingCount = data.pendingCount,
		terminalIdCount = data.terminalCount,
	})
end

function ClientRequestTracker.new(): TrackerResult
	local configurationResult = PlaceRoles.validateConfiguration()
	if not configurationResult.ok then
		return failure("PLACE_ROLE_UNRESOLVED", "role", "The fixed client place-role configuration is invalid")
	end
	local roleResult = PlaceRoles.resolve(
		ReplicatedStorage:GetAttribute(PlaceRoles.ATTRIBUTE_NAME),
		game.PlaceId,
		RunService:IsStudio()
	)
	if not roleResult.ok then
		return failure("PLACE_ROLE_UNRESOLVED", "role", "The fixed client place role could not be resolved")
	end
	return createWithDependencies(ProductionRemotes, roleResult.role, defaultGenerator)
end

local serverStorage = game:GetService("ServerStorage")
local testContainer = script.Parent
local automatedTests = testContainer.Parent
if
	script.Name == "ClientRequestTracker"
	and testContainer.ClassName == "Folder"
	and testContainer.Name == "ProductionClientNetworking"
	and automatedTests.ClassName == "Folder"
	and automatedTests.Name == "AutomatedTests"
	and automatedTests.Parent == serverStorage
then
	ClientRequestTracker.newForTests = createWithDependencies
end

table.freeze(TrackerMethods)
return table.freeze(ClientRequestTracker)
