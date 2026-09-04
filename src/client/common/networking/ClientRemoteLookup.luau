--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local ProductionRemotes = require(ReplicatedStorage.Shared.network.ProductionRemotes)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local Result = require(ReplicatedStorage.Shared.util.Result)

export type ErrorCode =
	"INVALID_REGISTRY"
	| "INVALID_PARENT"
	| "INVALID_ROLE"
	| "UNKNOWN_ENDPOINT"
	| "INACTIVE_ENDPOINT"
	| "INVALID_TIMEOUT"
	| "INVALID_CLOCK"
	| "INVALID_WAIT_ADAPTER"
	| "PLACE_ROLE_UNRESOLVED"
	| "CLOCK_ANOMALY"
	| "LOOKUP_FAILED"
	| "LOOKUP_TIMEOUT"
	| "UNEXPECTED_INSTANCE"
	| "WRONG_CLASS"

export type LookupError = {
	code: ErrorCode,
	path: string,
	message: string,
}

export type ResolvedEndpoint = {
	name: string,
	definition: RemoteRegistry.Definition,
	request: RemoteEvent?,
	response: RemoteEvent?,
	event: RemoteEvent?,
}

export type LookupSuccess = Result.Success<ResolvedEndpoint>
export type LookupFailure = Result.Failure<LookupError>
export type LookupResult = Result.Result<ResolvedEndpoint, LookupError>
export type Clock = () -> number
export type WaitAdapter = (parent: Instance, childName: string, timeoutSeconds: number) -> Instance?
export type TestResolver = (
	registry: RemoteRegistry.Registry,
	replicatedStorage: Instance,
	role: RemoteRegistry.RuntimePlaceRole,
	endpointName: unknown,
	timeoutSeconds: unknown,
	clock: Clock?,
	waitAdapter: WaitAdapter?
) -> LookupResult

type Deadline = {
	clock: Clock,
	lastTime: number,
	endTime: number,
}

local ClientRemoteLookup = {
	MAX_TOTAL_TIMEOUT_SECONDS = 5,
	resolveForTests = nil :: TestResolver?,
}

local function failure(code: ErrorCode, path: string, message: string): LookupFailure
	return Result.err(table.freeze({
		code = code,
		path = path,
		message = message,
	}))
end

local function success(value: ResolvedEndpoint): LookupSuccess
	return Result.ok(table.freeze(value))
end

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function defaultClock(): number
	return os.clock()
end

local function defaultWait(parent: Instance, childName: string, timeoutSeconds: number): Instance?
	return parent:WaitForChild(childName, timeoutSeconds)
end

local function readClock(deadline: Deadline): (number?, LookupFailure?)
	local readSucceeded, value = pcall(deadline.clock)
	if not readSucceeded or type(value) ~= "number" or not isFinite(value) then
		return nil, failure("CLOCK_ANOMALY", "clock", "The lookup clock returned an invalid value")
	end
	if value < deadline.lastTime then
		return nil, failure("CLOCK_ANOMALY", "clock", "The lookup clock moved backwards")
	end

	deadline.lastTime = value
	return value, nil
end

local function waitExact(
	deadline: Deadline,
	waitAdapter: WaitAdapter,
	parent: Instance,
	childName: string,
	expectedClassName: string,
	path: string
): (Instance?, LookupFailure?)
	local before, beforeFailure = readClock(deadline)
	if before == nil then
		return nil, beforeFailure
	end

	local remaining = deadline.endTime - before
	if remaining <= 0 then
		return nil, failure("LOOKUP_TIMEOUT", path, "The bounded endpoint lookup reached its total deadline")
	end

	local waitSucceeded, child = pcall(waitAdapter, parent, childName, remaining)
	if not waitSucceeded then
		return nil, failure("LOOKUP_FAILED", path, "The fixed child lookup failed")
	end

	local after, afterFailure = readClock(deadline)
	if after == nil then
		return nil, afterFailure
	end
	if after > deadline.endTime or child == nil then
		return nil, failure("LOOKUP_TIMEOUT", path, "The bounded endpoint lookup reached its total deadline")
	end
	if typeof(child) ~= "Instance" then
		return nil, failure("UNEXPECTED_INSTANCE", path, "The fixed child lookup returned an invalid value")
	end

	local instance = child :: Instance
	if instance.Parent ~= parent or instance.Name ~= childName then
		return nil, failure("UNEXPECTED_INSTANCE", path, "The fixed child lookup returned an unrelated Instance")
	end
	if instance.ClassName ~= expectedClassName then
		return nil, failure("WRONG_CLASS", path, "A fixed network path segment has the wrong Instance class")
	end

	return instance, nil
end

local function isActive(registry: RemoteRegistry.Registry, role: RemoteRegistry.RuntimePlaceRole, name: string): boolean
	for _, definition in registry:listForRole(role) do
		if definition.name == name then
			return true
		end
	end

	return false
end

local function resolveWithDependencies(
	registry: RemoteRegistry.Registry,
	replicatedStorage: Instance,
	role: RemoteRegistry.RuntimePlaceRole,
	endpointName: unknown,
	timeoutSeconds: unknown,
	clock: Clock?,
	waitAdapter: WaitAdapter?
): LookupResult
	if not RemoteRegistry.isRegistry(registry) then
		return failure("INVALID_REGISTRY", "registry", "Endpoint lookup requires an authentic remote registry")
	end
	if typeof(replicatedStorage) ~= "Instance" or not replicatedStorage:IsA("ReplicatedStorage") then
		return failure("INVALID_PARENT", "replicatedStorage", "Endpoint lookup requires the ReplicatedStorage service")
	end
	if role ~= "Development" and role ~= "Lobby" and role ~= "Match" then
		return failure("INVALID_ROLE", "role", "Endpoint lookup requires Development, Lobby, or Match")
	end

	local definition = if type(endpointName) == "string" then registry:get(endpointName) else nil
	if definition == nil then
		return failure("UNKNOWN_ENDPOINT", "endpoint", "Endpoint lookup requires one fixed registry name")
	end
	if not isActive(registry, role, definition.name) then
		return failure("INACTIVE_ENDPOINT", "endpoint", "The fixed endpoint is not active for this place role")
	end
	if
		type(timeoutSeconds) ~= "number"
		or not isFinite(timeoutSeconds)
		or timeoutSeconds <= 0
		or timeoutSeconds > ClientRemoteLookup.MAX_TOTAL_TIMEOUT_SECONDS
	then
		return failure(
			"INVALID_TIMEOUT",
			"timeoutSeconds",
			"The total lookup timeout must be finite, positive, and at most five seconds"
		)
	end
	if clock ~= nil and type(clock) ~= "function" then
		return failure("INVALID_CLOCK", "clock", "The lookup clock must be a function or nil")
	end
	if waitAdapter ~= nil and type(waitAdapter) ~= "function" then
		return failure("INVALID_WAIT_ADAPTER", "waitAdapter", "The child lookup adapter must be a function or nil")
	end

	local selectedClock = clock or defaultClock
	local initialReadSucceeded, initialTime = pcall(selectedClock)
	if not initialReadSucceeded or type(initialTime) ~= "number" or not isFinite(initialTime) then
		return failure("CLOCK_ANOMALY", "clock", "The lookup clock returned an invalid value")
	end

	local deadline: Deadline = {
		clock = selectedClock,
		lastTime = initialTime,
		endTime = initialTime + timeoutSeconds,
	}
	if not isFinite(deadline.endTime) then
		return failure("CLOCK_ANOMALY", "clock", "The lookup deadline could not be represented safely")
	end

	local selectedWaitAdapter = waitAdapter or defaultWait
	local root, lookupFailure = waitExact(
		deadline,
		selectedWaitAdapter,
		replicatedStorage,
		RemoteRegistry.ROOT_NAME,
		"Folder",
		RemoteRegistry.ROOT_NAME
	)
	if root == nil then
		return lookupFailure :: LookupFailure
	end

	local versionPath = `{RemoteRegistry.ROOT_NAME}.{RemoteRegistry.VERSION_NAME}`
	local version, versionFailure =
		waitExact(deadline, selectedWaitAdapter, root, RemoteRegistry.VERSION_NAME, "Folder", versionPath)
	if version == nil then
		return versionFailure :: LookupFailure
	end

	local endpointPath = `{versionPath}.{definition.name}`
	local endpoint, endpointFailure =
		waitExact(deadline, selectedWaitAdapter, version, definition.name, "Folder", endpointPath)
	if endpoint == nil then
		return endpointFailure :: LookupFailure
	end

	local request: RemoteEvent? = nil
	local response: RemoteEvent? = nil
	local event: RemoteEvent? = nil
	if definition.kind == "Request" then
		local requestInstance, requestFailure =
			waitExact(deadline, selectedWaitAdapter, endpoint, "Request", "RemoteEvent", `{endpointPath}.Request`)
		if requestInstance == nil then
			return requestFailure :: LookupFailure
		end
		request = requestInstance :: RemoteEvent

		if definition.response == "Required" then
			local responseInstance, responseFailure =
				waitExact(deadline, selectedWaitAdapter, endpoint, "Response", "RemoteEvent", `{endpointPath}.Response`)
			if responseInstance == nil then
				return responseFailure :: LookupFailure
			end
			response = responseInstance :: RemoteEvent
		end
	else
		local eventInstance, eventFailure =
			waitExact(deadline, selectedWaitAdapter, endpoint, "Event", "RemoteEvent", `{endpointPath}.Event`)
		if eventInstance == nil then
			return eventFailure :: LookupFailure
		end
		event = eventInstance :: RemoteEvent
	end

	return success({
		name = definition.name,
		definition = definition,
		request = request,
		response = response,
		event = event,
	})
end

function ClientRemoteLookup.resolve(endpointName: unknown, timeoutSeconds: unknown): LookupResult
	local configurationResult = PlaceRoles.validateConfiguration()
	if not configurationResult.ok then
		return failure("PLACE_ROLE_UNRESOLVED", "role", "The fixed client place-role configuration is invalid")
	end

	local roleResult = PlaceRoles.resolve(
		ReplicatedStorage:GetAttribute(PlaceRoles.ATTRIBUTE_NAME),
		game.GameId,
		game.PlaceId,
		RunService:IsStudio()
	)
	if not roleResult.ok then
		return failure("PLACE_ROLE_UNRESOLVED", "role", "The fixed client place role could not be resolved")
	end

	return resolveWithDependencies(
		ProductionRemotes,
		ReplicatedStorage,
		roleResult.role,
		endpointName,
		timeoutSeconds,
		nil,
		nil
	)
end

-- The production client API has no registry, parent, role, clock, or wait seam.
-- Headless tests exercise the same implementation through a resolver that exists
-- only while this exact production source is mapped at the isolated test path
-- beneath ServerStorage. Production client projects place it under
-- StarterPlayerScripts and cannot satisfy this non-replicated structural gate.
local serverStorage = game:GetService("ServerStorage")
local testContainer = script.Parent
local automatedTests = testContainer.Parent
if
	script.Name == "ClientRemoteLookup"
	and testContainer.ClassName == "Folder"
	and testContainer.Name == "ProductionClientNetworking"
	and automatedTests.ClassName == "Folder"
	and automatedTests.Name == "AutomatedTests"
	and automatedTests.Parent == serverStorage
then
	ClientRemoteLookup.resolveForTests = resolveWithDependencies
end

return table.freeze(ClientRemoteLookup)
