--!strict

-- This tracked harness is intentionally absent from every Rojo project. Follow
-- docs/NETWORK_SECURITY_STUDIO_REGRESSION.md; never publish or save it in a place.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StudioTestService = game:GetService("StudioTestService")

local Shared = ReplicatedStorage:FindFirstChild("Shared")
local EXPECTED_CASE_COUNT = 10
local terminal = false
local connections: { RBXScriptConnection } = {}
local completedCaseCount = 0

local function cleanupConnections()
	for index = #connections, 1, -1 do
		pcall(function()
			connections[index]:Disconnect()
		end)
	end
	table.clear(connections)
end

local function failHarness(code: string)
	if terminal then
		return
	end
	terminal = true
	cleanupConnections()
	print(`[ATD_PHASE06_STUDIO][FAIL][context=client][code={code}]`)
end

local function passHarness(caseName: string)
	if terminal then
		return
	end
	if completedCaseCount ~= EXPECTED_CASE_COUNT then
		failHarness("CASE_COUNT_MISMATCH")
		return
	end
	terminal = true
	cleanupConnections()
	print(`[ATD_PHASE06_STUDIO][PASS][context=client][case={caseName}][caseCount={completedCaseCount}]`)
end

local function recordCase()
	completedCaseCount += 1
end

if not RunService:IsStudio() or not RunService:IsClient() or not RunService:IsRunning() then
	failHarness("INVALID_RUNTIME")
	return
end

if Shared == nil or not Shared:IsA("Folder") then
	failHarness("SOURCE_TREE_MISSING")
	return
end

local sourceLoaded, sourceModules = pcall(function()
	return {
		PlaceRoles = require((Shared :: Folder).config.PlaceRoles),
		PayloadValidation = require((Shared :: Folder).network.PayloadValidation),
		RemoteRegistry = require((Shared :: Folder).network.RemoteRegistry),
		RequestProtocol = require((Shared :: Folder).network.RequestProtocol),
	}
end)

if not sourceLoaded then
	failHarness("SOURCE_LOAD_FAILED")
	return
end

local Modules = sourceModules :: any
local PlaceRoles = Modules.PlaceRoles
local PayloadValidation = Modules.PayloadValidation
local RemoteRegistry = Modules.RemoteRegistry
local RequestProtocol = Modules.RequestProtocol

local FIXTURE_ROOT_NAME = "ATDPhase06StudioFixture"
local VERSION_NAME = "v1"
local STARTUP_TIMEOUT_SECONDS = 45
local PROTOCOL_TIMEOUT_SECONDS = 120
local RESPONSE_TIMEOUT_SECONDS = 5
local DISCONNECT_TIMEOUT_SECONDS = 90

local IDENTITY_ENDPOINT = "StudioIdentity"
local NUMERIC_ENDPOINT = "StudioNumeric"
local DEFAULT_INSTANCE_ENDPOINT = "StudioInstanceDefault"
local EXPLICIT_INSTANCE_ENDPOINT = "StudioInstanceExplicit"
local BURST_ENDPOINT = "StudioBurst"
local HELLO_ENDPOINT = "StudioClientHello"
local COMPLETE_ENDPOINT = "StudioClientComplete"
local FINAL_ACK_ENDPOINT = "StudioFinalAck"
local ASSIGNMENT_ENDPOINT = "StudioAssignment"
local LEAVE_ENDPOINT = "StudioLeave"
local CONTINUE_ENDPOINT = "StudioContinue"
local FINISHED_ENDPOINT = "StudioFinished"

type RequestPair = {
	request: RemoteEvent,
	response: RemoteEvent,
}

local deadline = os.clock() + STARTUP_TIMEOUT_SECONDS
local requestPairs: { [string]: RequestPair } = {}
local clientEvents: { [string]: RemoteEvent } = {}
local serverEvents: { [string]: RemoteEvent } = {}
local responses: { [string]: { [string]: { any } } } = {}
local assignedSlot: number? = nil
local leaveInstruction: boolean? = nil
local continueRequested = false
local finishedReceived = false

local function remainingSeconds(maximum: number?): number
	local remaining = deadline - os.clock()
	if maximum ~= nil then
		remaining = math.min(remaining, maximum)
	end
	return math.max(0, remaining)
end

local function waitForExactChild(parent: Instance, name: string, className: string): Instance?
	local child = parent:FindFirstChild(name)
	if child == nil then
		local remaining = remainingSeconds()
		if remaining <= 0 then
			return nil
		end
		child = parent:WaitForChild(name, remaining)
	end
	if child == nil or child.Parent ~= parent or child.Name ~= name or child.ClassName ~= className then
		return nil
	end
	return child
end

local function waitUntil(predicate: () -> boolean, maximum: number?): boolean
	local localDeadline = deadline
	if maximum ~= nil then
		localDeadline = math.min(localDeadline, os.clock() + maximum)
	end
	while not terminal and os.clock() < localDeadline do
		if predicate() then
			return true
		end
		task.wait()
	end
	return not terminal and predicate()
end

local function rawResponseList(endpoint: string, requestId: string): { any }
	local byId = responses[endpoint]
	if byId == nil then
		return {}
	end
	return byId[requestId] or {}
end

local function awaitResponse(endpoint: string, requestId: string): any?
	local arrived = waitUntil(function(): boolean
		return #rawResponseList(endpoint, requestId) >= 1
	end, RESPONSE_TIMEOUT_SECONDS)
	if not arrived then
		return nil
	end
	local values = rawResponseList(endpoint, requestId)
	if #values ~= 1 then
		return nil
	end
	return values[1]
end

local function sendRequest(endpoint: string, requestIdValue: string, payload: unknown): boolean
	local pair = requestPairs[endpoint]
	if pair == nil then
		return false
	end
	local idResult = RequestProtocol.createRequestId(requestIdValue)
	if not idResult.ok then
		return false
	end
	local wireResult = RequestProtocol.buildRequest(idResult.value, payload)
	if not wireResult.ok then
		return false
	end
	return pcall(function()
		pair.request:FireServer(wireResult.value)
	end)
end

local function sendEvent(endpoint: string, payload: unknown): boolean
	local remote = clientEvents[endpoint]
	if remote == nil then
		return false
	end
	local wireResult = RequestProtocol.buildEvent(payload)
	if not wireResult.ok then
		return false
	end
	return pcall(function()
		remote:FireServer(wireResult.value)
	end)
end

local function isExactRecord(value: unknown, fields: { [string]: string }): boolean
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return false
	end
	local count = 0
	for key, fieldType in fields do
		count += 1
		if type(rawget(value :: any, key)) ~= fieldType then
			return false
		end
	end
	local actualCount = 0
	for key in next, value :: any do
		actualCount += 1
		if rawget(fields, key) == nil then
			return false
		end
	end
	return actualCount == count
end

local function expectSuccess(endpoint: string, requestId: string): any?
	local response = awaitResponse(endpoint, requestId)
	if response == nil or not RequestProtocol.isSuccess(response) then
		return nil
	end
	return response.payload
end

local function expectRejected(endpoint: string, requestId: string, code: string, path: string?): boolean
	local response = awaitResponse(endpoint, requestId)
	if response == nil or not RequestProtocol.isRejected(response) or response.error.code ~= code then
		return false
	end
	if path == nil then
		return true
	end
	local metadata = response.error.metadata
	return metadata ~= nil and metadata.validationPath == path
end

local function expectAccepted(endpoint: string, requestId: string): boolean
	local payload = expectSuccess(endpoint, requestId)
	return isExactRecord(payload, { accepted = "boolean" }) and payload.accepted == true
end

local function expectSlot(endpoint: string, requestId: string, slot: number): boolean
	local payload = expectSuccess(endpoint, requestId)
	return isExactRecord(payload, { slot = "number" }) and payload.slot == slot
end

local runSucceeded = pcall(function()
	local roleResult = PlaceRoles.resolve(
		ReplicatedStorage:GetAttribute(PlaceRoles.ATTRIBUTE_NAME),
		game.PlaceId,
		RunService:IsStudio()
	)
	if not roleResult.ok or roleResult.role ~= "Match" then
		failHarness("WRONG_PLACE_OR_ROLE")
		return
	end

	local productionRoot = waitForExactChild(ReplicatedStorage, RemoteRegistry.ROOT_NAME, "Folder")
	if productionRoot == nil then
		failHarness("PRODUCTION_ROOT_MISSING")
		return
	end
	local productionRootCount = 0
	for _, child in ReplicatedStorage:GetChildren() do
		if child.Name == RemoteRegistry.ROOT_NAME then
			productionRootCount += 1
		end
	end
	local productionVersion = waitForExactChild(productionRoot, RemoteRegistry.VERSION_NAME, "Folder")
	if productionRootCount ~= 1 or productionVersion == nil or #productionVersion:GetChildren() ~= 0 then
		failHarness("PRODUCTION_ROOT_INVALID")
		return
	end

	local root = waitForExactChild(ReplicatedStorage, FIXTURE_ROOT_NAME, "Folder")
	if root == nil then
		failHarness("FIXTURE_ROOT_MISSING")
		return
	end
	local version = waitForExactChild(root, VERSION_NAME, "Folder")
	local objectFolder = waitForExactChild(root, "FixtureObjects", "Folder")
	local allowedPart = if objectFolder == nil then nil else waitForExactChild(objectFolder, "AllowedPart", "Part")
	local wrongClass = if objectFolder == nil then nil else waitForExactChild(objectFolder, "WrongClass", "Folder")
	local outsidePart = waitForExactChild(root, "OutsidePart", "Part")
	if version == nil or objectFolder == nil or allowedPart == nil or wrongClass == nil or outsidePart == nil then
		failHarness("FIXTURE_OBJECT_MISSING")
		return
	end

	local requestNames = {
		IDENTITY_ENDPOINT,
		NUMERIC_ENDPOINT,
		DEFAULT_INSTANCE_ENDPOINT,
		EXPLICIT_INSTANCE_ENDPOINT,
		BURST_ENDPOINT,
	}
	for _, endpointName in requestNames do
		local endpoint = waitForExactChild(version, endpointName, "Folder")
		local request = if endpoint == nil then nil else waitForExactChild(endpoint, "Request", "RemoteEvent")
		local response = if endpoint == nil then nil else waitForExactChild(endpoint, "Response", "RemoteEvent")
		if endpoint == nil or request == nil or response == nil then
			failHarness("REQUEST_ENDPOINT_MISSING")
			return
		end
		requestPairs[endpointName] = {
			request = request :: RemoteEvent,
			response = response :: RemoteEvent,
		}
		responses[endpointName] = {}
		table.insert(
			connections,
			(response :: RemoteEvent).OnClientEvent:Connect(function(...: unknown)
				if terminal then
					return
				end
				local parsedResult = RequestProtocol.parseResponse(...)
				if not parsedResult.ok then
					failHarness("MALFORMED_RESPONSE")
					return
				end
				local parsed = parsedResult.value
				local requestId = parsed.requestId.value
				local byId = responses[endpointName]
				local list = byId[requestId]
				if list == nil then
					list = {}
					byId[requestId] = list
				end
				table.insert(list, parsed)
			end)
		)
	end

	local clientEventNames = {
		HELLO_ENDPOINT,
		COMPLETE_ENDPOINT,
		FINAL_ACK_ENDPOINT,
	}
	for _, endpointName in clientEventNames do
		local endpoint = waitForExactChild(version, endpointName, "Folder")
		local event = if endpoint == nil then nil else waitForExactChild(endpoint, "Event", "RemoteEvent")
		if endpoint == nil or event == nil then
			failHarness("CLIENT_EVENT_MISSING")
			return
		end
		clientEvents[endpointName] = event :: RemoteEvent
	end

	local serverEventNames = {
		ASSIGNMENT_ENDPOINT,
		LEAVE_ENDPOINT,
		CONTINUE_ENDPOINT,
		FINISHED_ENDPOINT,
	}
	for _, endpointName in serverEventNames do
		local endpoint = waitForExactChild(version, endpointName, "Folder")
		local event = if endpoint == nil then nil else waitForExactChild(endpoint, "Event", "RemoteEvent")
		if endpoint == nil or event == nil then
			failHarness("SERVER_EVENT_MISSING")
			return
		end
		serverEvents[endpointName] = event :: RemoteEvent
	end

	local assignmentSchema = PayloadValidation.schema(PayloadValidation.record({
		slot = PayloadValidation.integer(1, 2),
	}))
	local leaveSchema = PayloadValidation.schema(PayloadValidation.record({
		leave = PayloadValidation.boolean(),
	}))
	local continueSchema = PayloadValidation.schema(PayloadValidation.record({
		continue = PayloadValidation.boolean(),
	}))
	local finishedSchema = PayloadValidation.schema(PayloadValidation.record({
		passed = PayloadValidation.boolean(),
	}))

	local function connectValidatedEvent(endpointName: string, schema: any, callback: (any) -> ())
		table.insert(
			connections,
			serverEvents[endpointName].OnClientEvent:Connect(function(...: unknown)
				if terminal then
					return
				end
				local parsedResult = RequestProtocol.parseEvent(...)
				if not parsedResult.ok then
					failHarness("MALFORMED_SERVER_EVENT")
					return
				end
				local payloadResult = schema:validate(parsedResult.value.payload)
				if not payloadResult.ok then
					failHarness("INVALID_SERVER_EVENT_PAYLOAD")
					return
				end
				callback(payloadResult.value)
			end)
		)
	end

	connectValidatedEvent(ASSIGNMENT_ENDPOINT, assignmentSchema, function(payload: any)
		if assignedSlot ~= nil then
			failHarness("DUPLICATE_ASSIGNMENT")
			return
		end
		assignedSlot = payload.slot
	end)
	connectValidatedEvent(LEAVE_ENDPOINT, leaveSchema, function(payload: any)
		if leaveInstruction ~= nil then
			failHarness("DUPLICATE_LEAVE_BARRIER")
			return
		end
		leaveInstruction = payload.leave
	end)
	connectValidatedEvent(CONTINUE_ENDPOINT, continueSchema, function(payload: any)
		if payload.continue == true then
			continueRequested = true
		end
	end)
	connectValidatedEvent(FINISHED_ENDPOINT, finishedSchema, function(payload: any)
		if payload.passed == true then
			finishedReceived = true
		end
	end)
	deadline = os.clock() + PROTOCOL_TIMEOUT_SECONDS

	if not sendEvent(HELLO_ENDPOINT, { ready = true }) then
		failHarness("HELLO_SEND_FAILED")
		return
	end
	if not waitUntil(function(): boolean
		return assignedSlot ~= nil
	end, RESPONSE_TIMEOUT_SECONDS) then
		failHarness("ASSIGNMENT_TIMEOUT")
		return
	end
	local slot = assignedSlot :: number
	recordCase()

	local sharedRequestId = "IdentityShared"
	if not sendRequest(IDENTITY_ENDPOINT, sharedRequestId, { value = 1 }) then
		failHarness("IDENTITY_SEND_FAILED")
		return
	end
	if not expectSlot(IDENTITY_ENDPOINT, sharedRequestId, slot) then
		failHarness("ORIGIN_ROUTING_FAILED")
		return
	end
	task.wait(0.25)
	if #rawResponseList(IDENTITY_ENDPOINT, sharedRequestId) ~= 1 then
		failHarness("CROSS_PLAYER_RESPONSE")
		return
	end
	recordCase()

	local otherUserId = 0
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			otherUserId = player.UserId
			break
		end
	end
	local forgedId = `ForgedField{slot}`
	if
		not sendRequest(IDENTITY_ENDPOINT, forgedId, {
			value = 1,
			claimedUserId = otherUserId,
			privateNote = "STUDIO_PRIVATE_SENTINEL_06_5",
		}) or not expectRejected(IDENTITY_ENDPOINT, forgedId, "INVALID_PAYLOAD", "payload")
	then
		failHarness("FORGED_FIELD_NOT_REJECTED")
		return
	end
	recordCase()

	local finiteVector2 = Vector2.new(1, 2)
	local finiteVector3 = Vector3.new(1, 2, 3)
	local finiteCFrame = CFrame.new(1, 2, 3)
	local numericCases = {
		{
			id = `NumericV2{slot}`,
			payload = {
				vector2 = Vector2.new(0 / 0, 0),
				vector3 = finiteVector3,
				transform = finiteCFrame,
			},
			path = "payload.vector2.X",
		},
		{
			id = `NumericV3{slot}`,
			payload = {
				vector2 = finiteVector2,
				vector3 = Vector3.new(0, math.huge, 0),
				transform = finiteCFrame,
			},
			path = "payload.vector3.Y",
		},
		{
			id = `NumericCF{slot}`,
			payload = {
				vector2 = finiteVector2,
				vector3 = finiteVector3,
				transform = CFrame.new(0, 0, math.huge),
			},
			path = "payload.transform.Z",
		},
	}
	for _, numericCase in numericCases do
		if
			not sendRequest(NUMERIC_ENDPOINT, numericCase.id, numericCase.payload)
			or not expectRejected(NUMERIC_ENDPOINT, numericCase.id, "INVALID_PAYLOAD", numericCase.path)
		then
			failHarness("NON_FINITE_NOT_REJECTED")
			return
		end
	end
	local numericOkId = `NumericOk{slot}`
	if
		not sendRequest(NUMERIC_ENDPOINT, numericOkId, {
			vector2 = finiteVector2,
			vector3 = finiteVector3,
			transform = finiteCFrame,
		}) or not expectAccepted(NUMERIC_ENDPOINT, numericOkId)
	then
		failHarness("FINITE_NUMERIC_FAILED")
		return
	end
	recordCase()

	local localInstanceSchema = PayloadValidation.schema(PayloadValidation.record({
		reference = PayloadValidation.instance(
			PayloadValidation.instancePolicy("Part", objectFolder :: Instance, false)
		),
	}))
	local localInstanceResult = localInstanceSchema:validate({ reference = allowedPart })
	if localInstanceResult.ok or localInstanceResult.error.code ~= "INVALID_REFERENCE" then
		failHarness("CLIENT_INSTANCE_POLICY_ACCEPTED")
		return
	end

	local defaultInstanceId = `DefaultInst{slot}`
	if
		not sendRequest(DEFAULT_INSTANCE_ENDPOINT, defaultInstanceId, { reference = allowedPart })
		or not expectRejected(DEFAULT_INSTANCE_ENDPOINT, defaultInstanceId, "INVALID_PAYLOAD", "payload.reference")
	then
		failHarness("DEFAULT_INSTANCE_NOT_REJECTED")
		return
	end
	recordCase()

	local explicitOkId = `ExplicitOk{slot}`
	if
		not sendRequest(EXPLICIT_INSTANCE_ENDPOINT, explicitOkId, { reference = allowedPart })
		or not expectAccepted(EXPLICIT_INSTANCE_ENDPOINT, explicitOkId)
	then
		failHarness("SERVER_INSTANCE_POLICY_FAILED")
		return
	end
	local explicitOutsideId = `ExplicitOut{slot}`
	if
		not sendRequest(EXPLICIT_INSTANCE_ENDPOINT, explicitOutsideId, { reference = outsidePart })
		or not expectRejected(EXPLICIT_INSTANCE_ENDPOINT, explicitOutsideId, "INVALID_PAYLOAD", "payload.reference")
	then
		failHarness("INSTANCE_ANCESTRY_NOT_REJECTED")
		return
	end
	local explicitClassId = `ExplicitClass{slot}`
	if
		not sendRequest(EXPLICIT_INSTANCE_ENDPOINT, explicitClassId, { reference = wrongClass })
		or not expectRejected(EXPLICIT_INSTANCE_ENDPOINT, explicitClassId, "INVALID_PAYLOAD", "payload.reference")
	then
		failHarness("INSTANCE_CLASS_NOT_REJECTED")
		return
	end
	recordCase()

	local burstFirstId = `BurstFirst{slot}`
	local burstSecondId = `BurstSecond{slot}`
	if
		not sendRequest(BURST_ENDPOINT, burstFirstId, { value = 1 })
		or not sendRequest(BURST_ENDPOINT, burstSecondId, { value = 1 })
		or not expectAccepted(BURST_ENDPOINT, burstFirstId)
		or not expectRejected(BURST_ENDPOINT, burstSecondId, "RATE_LIMITED", nil)
	then
		failHarness("BURST_ISOLATION_FAILED")
		return
	end
	recordCase()

	local afterBurstId = `IdentityAfterBurst{slot}`
	if
		not sendRequest(IDENTITY_ENDPOINT, afterBurstId, { value = 1 })
		or not expectSlot(IDENTITY_ENDPOINT, afterBurstId, slot)
	then
		failHarness("ACTION_ISOLATION_FAILED")
		return
	end
	recordCase()

	if not sendEvent(COMPLETE_ENDPOINT, { complete = true }) then
		failHarness("COMPLETE_SEND_FAILED")
		return
	end
	if not waitUntil(function(): boolean
		return leaveInstruction ~= nil
	end, nil) then
		failHarness("LEAVE_BARRIER_TIMEOUT")
		return
	end

	if slot == 1 then
		if leaveInstruction ~= true then
			failHarness("INVALID_LEAVE_INSTRUCTION")
			return
		end
		local canLeaveRead, canLeave = pcall(function(): boolean
			return StudioTestService:CanLeaveTest()
		end)
		if not canLeaveRead or canLeave ~= true then
			failHarness("STUDIO_LEAVE_UNAVAILABLE")
			return
		end
		local leaveSucceeded = pcall(function()
			StudioTestService:LeaveTest()
		end)
		if not leaveSucceeded then
			failHarness("STUDIO_LEAVE_FAILED")
			return
		end
		terminal = true
		cleanupConnections()
		return
	end
	if leaveInstruction ~= false then
		failHarness("INVALID_LEAVE_INSTRUCTION")
		return
	end

	if not waitUntil(function(): boolean
		return continueRequested
	end, DISCONNECT_TIMEOUT_SECONDS) then
		failHarness("CONTINUE_EVENT_TIMEOUT")
		return
	end
	local afterLeaveId = "IdentityAfterLeave2"
	if
		not sendRequest(IDENTITY_ENDPOINT, afterLeaveId, { value = 1 })
		or not expectSlot(IDENTITY_ENDPOINT, afterLeaveId, slot)
	then
		failHarness("POST_DISCONNECT_REQUEST_FAILED")
		return
	end
	recordCase()
	if not sendEvent(FINAL_ACK_ENDPOINT, { complete = true }) then
		failHarness("FINAL_ACK_FAILED")
		return
	end
	if not waitUntil(function(): boolean
		return finishedReceived
	end, RESPONSE_TIMEOUT_SECONDS) then
		failHarness("FINISHED_EVENT_TIMEOUT")
		return
	end
	recordCase()
	passHarness("completed")
end)

if not runSucceeded and not terminal then
	failHarness("CLIENT_EXECUTION_FAILED")
end
