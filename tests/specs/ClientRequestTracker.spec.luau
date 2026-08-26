--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local NetworkFixtures = require(script.Parent.Parent.Fixtures.NetworkFixtures)
local ClientRequestTracker = require(script.Parent.Parent.ProductionClientNetworking.ClientRequestTracker)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PayloadValidation = require(ReplicatedStorage.Shared.network.PayloadValidation)
local RemoteRegistry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
local RequestProtocol = require(ReplicatedStorage.Shared.network.RequestProtocol)

type Assertions = TestHarness.Assertions
type Tracker = ClientRequestTracker.Tracker
type IdGenerator = ClientRequestTracker.IdGenerator

local PRIVATE_SENTINEL = "PRIVATE_CLIENT_TRACKER_SENTINEL_739a"

local newForTests = ClientRequestTracker.newForTests
if newForTests == nil then
	error("[ATD_TEST_FIXTURE][code=CLIENT_REQUEST_TRACKER_TEST_CONSTRUCTOR_MISSING]", 0)
end

local function makeRegistry(): RemoteRegistry.Registry
	local definitions = NetworkFixtures.validDefinitions()
	table.insert(definitions, {
		name = "TestSecondResponseRequest",
		transport = "ReliableRemoteEvent",
		direction = "ClientToServer",
		kind = "Request",
		response = "Required",
		placeRoles = { "Match" },
	})
	local result = RemoteRegistry.create(definitions)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=TRACKER_REGISTRY_CREATION_FAILED]", 0)
	end
	return result.value
end

local REGISTRY = makeRegistry()
local RESPONSE_DEFINITION = REGISTRY:get("TestResponseRequest") :: RemoteRegistry.Definition
local SECOND_RESPONSE_DEFINITION = REGISTRY:get("TestSecondResponseRequest") :: RemoteRegistry.Definition
local NO_RESPONSE_DEFINITION = REGISTRY:get("TestNoResponseRequest") :: RemoteRegistry.Definition
local REQUEST_SCHEMA = PayloadValidation.schema(PayloadValidation.record({
	count = PayloadValidation.integer(0, 10),
	label = PayloadValidation.optional(PayloadValidation.string(8)),
}))
local RESPONSE_SCHEMA = PayloadValidation.schema(PayloadValidation.record({
	accepted = PayloadValidation.boolean(),
}))

local function sequenceGenerator(values: { unknown }): (IdGenerator, () -> number)
	local index = 0
	return function(): unknown
		index += 1
		local value = rawget(values, index)
		if type(value) == "function" then
			return (value :: () -> unknown)()
		end
		return value
	end, function(): number
		return index
	end
end

local function counterGenerator(prefix: string): (IdGenerator, () -> number)
	local count = 0
	return function(): string
		count += 1
		return `{prefix}{string.format("%06d", count)}`
	end, function(): number
		return count
	end
end

local function makeTracker(generator: IdGenerator, role: RemoteRegistry.RuntimePlaceRole?): Tracker
	local result = (newForTests :: ClientRequestTracker.TestConstructor)(REGISTRY, role or "Match", generator)
	if not result.ok then
		error("[ATD_TEST_FIXTURE][code=TRACKER_CREATION_FAILED]", 0)
	end
	return result.value
end

local function registerRequired(assertions: Assertions, tracker: Tracker, endpoint: string)
	local result = tracker:register(endpoint, REQUEST_SCHEMA, RESPONSE_SCHEMA)
	assertions.isTrue(result.ok)
end

local function registerNoResponse(assertions: Assertions, tracker: Tracker)
	local result = tracker:register("TestNoResponseRequest", REQUEST_SCHEMA, nil)
	assertions.isTrue(result.ok)
end

local function expectFailure(assertions: Assertions, result: any, code: string)
	assertions.isFalse(result.ok)
	if not result.ok then
		assertions.equal(result.error.code, code)
		assertions.isTrue(table.isfrozen(result))
		assertions.isTrue(table.isfrozen(result.error))
		assertions.isNil(string.find(result.error.message, PRIVATE_SENTINEL, 1, true))
	end
end

local function successWire(requestId: string, accepted: unknown): { [string]: unknown }
	return {
		requestId = requestId,
		state = "Success",
		payload = { accepted = accepted },
	}
end

local function keyCount(value: { [any]: unknown }): number
	local count = 0
	for _ in next, value do
		count += 1
	end
	return count
end

return TestHarness.suite("bounded client request tracker", {
	TestHarness.case("gates injected construction and authenticates fixed tracker state", function(assertions)
		assertions.isTrue(table.isfrozen(ClientRequestTracker))
		assertions.equal(ClientRequestTracker.MAX_PENDING, 32)
		assertions.equal(ClientRequestTracker.MAX_TERMINAL_IDS, 128)
		assertions.equal(ClientRequestTracker.MAX_GENERATION_ATTEMPTS, 8)

		local generator = function(): string
			return "request001"
		end
		expectFailure(
			assertions,
			(newForTests :: ClientRequestTracker.TestConstructor)({} :: any, "Match", generator),
			"INVALID_REGISTRY"
		)
		expectFailure(
			assertions,
			(newForTests :: ClientRequestTracker.TestConstructor)(REGISTRY, "Other" :: any, generator),
			"INVALID_ROLE"
		)
		expectFailure(
			assertions,
			(newForTests :: ClientRequestTracker.TestConstructor)(REGISTRY, "Match", {} :: any),
			"ID_GENERATION_FAILED"
		)

		local tracker = makeTracker(generator)
		assertions.isTrue(table.isfrozen(tracker))
		local stats = tracker:getStats()
		assertions.isTrue(table.isfrozen(stats))
		assertions.equal(stats.registrationCount, 0)
		assertions.equal(stats.pendingCount, 0)
		assertions.equal(stats.terminalIdCount, 0)

		local sourceModule = script.Parent.Parent.ProductionClientNetworking.ClientRequestTracker
		local productionClone = sourceModule:Clone()
		productionClone.Name = "ClientRequestTrackerProductionLocationProbe"
		productionClone.Parent = ReplicatedStorage
		local productionLocated = require(productionClone) :: any
		assertions.equal(type(productionLocated.new), "function")
		assertions.isNil(productionLocated.newForTests)
		assertions.isTrue(table.isfrozen(productionLocated))
		productionClone:Destroy()
	end),

	TestHarness.case("registers only active canonical request definitions with matching schemas", function(assertions)
		local tracker = makeTracker(function(): string
			return "request002"
		end)
		expectFailure(
			assertions,
			tracker:register(PRIVATE_SENTINEL .. "/path", REQUEST_SCHEMA, nil),
			"UNKNOWN_ENDPOINT"
		)
		expectFailure(assertions, tracker:register("TestServerEvent", REQUEST_SCHEMA, nil), "INACTIVE_ENDPOINT")
		expectFailure(assertions, tracker:register("TestClientEvent", REQUEST_SCHEMA, nil), "WRONG_KIND")
		expectFailure(
			assertions,
			tracker:register("TestResponseRequest", {} :: any, RESPONSE_SCHEMA),
			"INVALID_REQUEST_SCHEMA"
		)
		expectFailure(
			assertions,
			tracker:register("TestResponseRequest", REQUEST_SCHEMA, nil),
			"INVALID_RESPONSE_SCHEMA"
		)
		expectFailure(
			assertions,
			tracker:register("TestNoResponseRequest", REQUEST_SCHEMA, RESPONSE_SCHEMA),
			"RESPONSE_SCHEMA_MISMATCH"
		)

		registerRequired(assertions, tracker, "TestResponseRequest")
		expectFailure(
			assertions,
			tracker:register("TestResponseRequest", REQUEST_SCHEMA, RESPONSE_SCHEMA),
			"DUPLICATE_REGISTRATION"
		)
		registerNoResponse(assertions, tracker)
		assertions.equal(tracker:getStats().registrationCount, 2)

		local lobbyTracker = makeTracker(function(): string
			return "request003"
		end, "Lobby")
		expectFailure(assertions, lobbyTracker:register("TestServerEvent", REQUEST_SCHEMA, nil), "WRONG_DIRECTION")
	end),

	TestHarness.case("builds exact detached frozen response-required request and Pending state", function(assertions)
		local tracker = makeTracker(function(): string
			return "request004"
		end)
		registerRequired(assertions, tracker, "TestResponseRequest")
		local payload = { count = 3, label = "Alpha" }
		local result = tracker:buildRequest("TestResponseRequest", payload)
		assertions.isTrue(result.ok)
		if not result.ok then
			return
		end

		local built = result.value
		assertions.isTrue(table.isfrozen(result))
		assertions.isTrue(table.isfrozen(built))
		assertions.equal(built.definition, REGISTRY:get("TestResponseRequest"))
		assertions.isTrue(table.isfrozen(built.envelope))
		assertions.equal(keyCount(built.envelope :: any), 2)
		assertions.equal(built.envelope.requestId, "request004")
		assertions.isNil((built.envelope :: any).endpoint)
		assertions.isNil((built.envelope :: any).action)
		assertions.isNil((built.envelope :: any).timestamp)
		assertions.notEqual(built.envelope.payload, payload)
		assertions.isTrue(table.isfrozen(built.envelope.payload :: any))
		assertions.equal((built.envelope.payload :: any).count, 3)
		payload.count = 9
		assertions.equal((built.envelope.payload :: any).count, 3)

		assertions.isNotNil(built.pending)
		local pending = built.pending :: RequestProtocol.Pending
		assertions.isTrue(RequestProtocol.isPending(pending))
		assertions.isTrue(table.isfrozen(pending))
		assertions.isTrue(table.isfrozen(pending.requestId))
		assertions.equal(pending.requestId.value, "request004")
		assertions.equal(tracker:getStats().pendingCount, 1)

		local cancelled = tracker:cancel(pending)
		assertions.isTrue(cancelled.ok)
		assertions.equal(tracker:getStats().pendingCount, 0)
		assertions.equal(tracker:getStats().terminalIdCount, 1)
	end),

	TestHarness.case("validates before generation and retains no rejected payload", function(assertions)
		local generator, reads = counterGenerator("invalid")
		local tracker = makeTracker(generator)
		registerRequired(assertions, tracker, "TestResponseRequest")

		expectFailure(assertions, tracker:buildRequest("TestResponseRequest", { count = 11 }), "INVALID_PAYLOAD")
		expectFailure(
			assertions,
			tracker:buildRequest("TestResponseRequest", { count = 1, private = PRIVATE_SENTINEL }),
			"INVALID_PAYLOAD"
		)
		local hostile = setmetatable({ count = 1 }, {
			__tostring = function(): string
				return PRIVATE_SENTINEL
			end,
		})
		expectFailure(assertions, tracker:buildRequest("TestResponseRequest", hostile), "INVALID_PAYLOAD")
		assertions.equal(reads(), 0)
		assertions.equal(tracker:getStats().pendingCount, 0)
		assertions.equal(tracker:getStats().terminalIdCount, 0)
		expectFailure(
			assertions,
			tracker:buildRequest(PRIVATE_SENTINEL .. "/path", { count = 1 }),
			"UNREGISTERED_ENDPOINT"
		)
	end),

	TestHarness.case(
		"builds no-response requests without Pending and independently of the Pending cap",
		function(assertions)
			local generator = counterGenerator("noreply")
			local tracker = makeTracker(generator)
			registerRequired(assertions, tracker, "TestResponseRequest")
			registerRequired(assertions, tracker, "TestSecondResponseRequest")
			registerNoResponse(assertions, tracker)

			for index = 1, ClientRequestTracker.MAX_PENDING do
				local endpoint = if index % 2 == 0 then "TestResponseRequest" else "TestSecondResponseRequest"
				local pendingResult = tracker:buildRequest(endpoint, { count = 1 })
				assertions.isTrue(pendingResult.ok)
			end
			assertions.equal(tracker:getStats().pendingCount, 32)
			expectFailure(
				assertions,
				tracker:buildRequest("TestResponseRequest", { count = 1 }),
				"PENDING_LIMIT_REACHED"
			)

			local noResponse = tracker:buildRequest("TestNoResponseRequest", { count = 2 })
			assertions.isTrue(noResponse.ok)
			if noResponse.ok then
				assertions.isNil(noResponse.value.pending)
				assertions.equal(keyCount(noResponse.value.envelope :: any), 2)
				assertions.equal((noResponse.value.envelope.payload :: any).count, 2)
			end
			assertions.equal(tracker:getStats().pendingCount, 32)
			assertions.equal(tracker:getStats().terminalIdCount, 1)
			expectFailure(
				assertions,
				tracker:handleResponse(NO_RESPONSE_DEFINITION, successWire("noreply000033", true)),
				"UNEXPECTED_RESPONSE_ENDPOINT"
			)
		end
	),

	TestHarness.case("contains generator faults and retries pending and terminal collisions", function(assertions)
		local sequence = {
			"collision1",
			"collision1",
			{},
			function(): unknown
				error(PRIVATE_SENTINEL, 0)
			end,
			"short",
			"unique001",
			"unique001",
			"unique002",
		}
		local generator, reads = sequenceGenerator(sequence)
		local tracker = makeTracker(generator)
		registerNoResponse(assertions, tracker)
		registerRequired(assertions, tracker, "TestResponseRequest")

		local first = tracker:buildRequest("TestNoResponseRequest", { count = 1 })
		assertions.isTrue(first.ok)
		local second = tracker:buildRequest("TestResponseRequest", { count = 1 })
		assertions.isTrue(second.ok)
		if second.ok then
			assertions.equal(second.value.envelope.requestId, "unique001")
		end
		local third = tracker:buildRequest("TestResponseRequest", { count = 1 })
		assertions.isTrue(third.ok)
		if third.ok then
			assertions.equal(third.value.envelope.requestId, "unique002")
		end
		assertions.equal(reads(), 8)

		local exhaustedTracker = makeTracker(function(): string
			return "repeat001"
		end)
		registerNoResponse(assertions, exhaustedTracker)
		registerRequired(assertions, exhaustedTracker, "TestResponseRequest")
		assertions.isTrue(exhaustedTracker:buildRequest("TestNoResponseRequest", { count = 1 }).ok)
		expectFailure(
			assertions,
			exhaustedTracker:buildRequest("TestResponseRequest", { count = 1 }),
			"ID_GENERATION_FAILED"
		)
		assertions.equal(exhaustedTracker:getStats().pendingCount, 0)
		assertions.equal(exhaustedTracker:getStats().terminalIdCount, 1)
	end),

	TestHarness.case("accepts a matching success only after fixed response-schema validation", function(assertions)
		local tracker = makeTracker(function(): string
			return "success01"
		end)
		registerRequired(assertions, tracker, "TestResponseRequest")
		local built = tracker:buildRequest("TestResponseRequest", { count = 4 })
		assertions.isTrue(built.ok)
		if not built.ok then
			return
		end

		local rawPayload = { accepted = true }
		local response = {
			requestId = built.value.envelope.requestId,
			state = "Success",
			payload = rawPayload,
		}
		local handled = tracker:handleResponse(RESPONSE_DEFINITION, response)
		assertions.isTrue(handled.ok)
		if handled.ok then
			assertions.isTrue(RequestProtocol.isSuccess(handled.value))
			local success = handled.value :: RequestProtocol.Success
			assertions.equal(success.requestId, (built.value.pending :: RequestProtocol.Pending).requestId)
			assertions.notEqual(success.payload, rawPayload)
			assertions.isTrue(table.isfrozen(success.payload :: any))
			assertions.equal((success.payload :: any).accepted, true)
		end
		rawPayload.accepted = false
		assertions.equal(((handled :: any).value.payload :: any).accepted, true)
		assertions.equal(tracker:getStats().pendingCount, 0)
		assertions.equal(tracker:getStats().terminalIdCount, 1)
		expectFailure(assertions, tracker:handleResponse(RESPONSE_DEFINITION, response), "STALE_RESPONSE")
	end),

	TestHarness.case("revalidates and freezes the exact allowlisted public rejection", function(assertions)
		local tracker = makeTracker(function(): string
			return "reject001"
		end)
		registerRequired(assertions, tracker, "TestResponseRequest")
		local built = tracker:buildRequest("TestResponseRequest", { count = 1 })
		assertions.isTrue(built.ok)
		if not built.ok then
			return
		end

		local rawError = {
			code = "INVALID_PAYLOAD",
			metadata = { validationPath = "payload.count" },
		}
		local handled = tracker:handleResponse(RESPONSE_DEFINITION, {
			requestId = built.value.envelope.requestId,
			state = "Rejected",
			error = rawError,
		})
		assertions.isTrue(handled.ok)
		if handled.ok then
			assertions.isTrue(RequestProtocol.isRejected(handled.value))
			local rejected = handled.value :: RequestProtocol.Rejected
			assertions.equal(rejected.requestId, (built.value.pending :: RequestProtocol.Pending).requestId)
			assertions.notEqual(rejected.error, rawError)
			assertions.isTrue(table.isfrozen(rejected))
			assertions.isTrue(table.isfrozen(rejected.error))
			assertions.isTrue(table.isfrozen(rejected.error.metadata :: any))
			assertions.equal(
				(rejected.error.metadata :: RequestProtocol.PublicErrorMetadata).validationPath,
				"payload.count"
			)
		end
		(rawError.metadata :: any).validationPath = PRIVATE_SENTINEL
		assertions.equal(
			((handled :: any).value.error.metadata :: RequestProtocol.PublicErrorMetadata).validationPath,
			"payload.count"
		)
	end),

	TestHarness.case(
		"preserves live Pending across endpoint mismatch stale and malformed responses",
		function(assertions)
			local generator, _reads = counterGenerator("matchid")
			local tracker = makeTracker(generator)
			registerRequired(assertions, tracker, "TestResponseRequest")
			registerRequired(assertions, tracker, "TestSecondResponseRequest")
			local built = tracker:buildRequest("TestResponseRequest", { count = 1 })
			assertions.isTrue(built.ok)
			if not built.ok then
				return
			end
			local requestId = built.value.envelope.requestId

			expectFailure(
				assertions,
				tracker:handleResponse(SECOND_RESPONSE_DEFINITION, successWire(requestId, true)),
				"MISMATCHED_RESPONSE"
			)
			expectFailure(
				assertions,
				tracker:handleResponse(RESPONSE_DEFINITION, successWire("unknown01", true)),
				"STALE_RESPONSE"
			)
			expectFailure(
				assertions,
				tracker:handleResponse(PRIVATE_SENTINEL .. "/path", successWire(requestId, true)),
				"UNREGISTERED_ENDPOINT"
			)
			assertions.equal(tracker:getStats().pendingCount, 1)

			local malformedCases: { unknown } = {
				42,
				{ requestId = requestId, state = "Other", payload = { accepted = true } },
				{ requestId = "short", state = "Success", payload = { accepted = true } },
				{ requestId = requestId, state = "Success", payload = { accepted = true }, extra = PRIVATE_SENTINEL },
				{ requestId = requestId, state = "Success", payload = { accepted = "yes" } },
				{ requestId = requestId, state = "Rejected", error = { code = PRIVATE_SENTINEL } },
				{ requestId = requestId, state = "Rejected", error = { code = "RATE_LIMITED", metadata = {} } },
				setmetatable(successWire(requestId, true), {
					__tostring = function(): string
						return PRIVATE_SENTINEL
					end,
				}),
			}
			for _, malformed in malformedCases do
				expectFailure(assertions, tracker:handleResponse(RESPONSE_DEFINITION, malformed), "MALFORMED_RESPONSE")
				assertions.equal(tracker:getStats().pendingCount, 1)
			end
			expectFailure(
				assertions,
				tracker:handleResponse(RESPONSE_DEFINITION, successWire(requestId, true), PRIVATE_SENTINEL),
				"MALFORMED_RESPONSE"
			)
			assertions.equal(tracker:getStats().pendingCount, 1)

			assertions.isTrue(tracker:handleResponse(RESPONSE_DEFINITION, successWire(requestId, true)).ok)
			assertions.equal(tracker:getStats().pendingCount, 0)
		end
	),

	TestHarness.case("classifies cancelled and completed IDs as stale without reviving state", function(assertions)
		local generator, _reads = counterGenerator("cancel")
		local tracker = makeTracker(generator)
		registerRequired(assertions, tracker, "TestResponseRequest")
		local first = tracker:buildRequest("TestResponseRequest", { count = 1 })
		local second = tracker:buildRequest("TestResponseRequest", { count = 2 })
		assertions.isTrue(first.ok)
		assertions.isTrue(second.ok)
		if not first.ok or not second.ok then
			return
		end

		local firstPending = first.value.pending :: RequestProtocol.Pending
		assertions.isTrue(tracker:cancel(firstPending).ok)
		expectFailure(assertions, tracker:cancel(firstPending), "INVALID_PENDING")
		local foreignId = RequestProtocol.createRequestId("foreign01")
		assertions.isTrue(foreignId.ok)
		if foreignId.ok then
			local foreignPending = RequestProtocol.createPending(foreignId.value)
			assertions.isTrue(foreignPending.ok)
			if foreignPending.ok then
				expectFailure(assertions, tracker:cancel(foreignPending.value), "INVALID_PENDING")
			end
		end
		expectFailure(
			assertions,
			tracker:handleResponse(RESPONSE_DEFINITION, successWire(first.value.envelope.requestId, true)),
			"STALE_RESPONSE"
		)
		assertions.equal(tracker:getStats().pendingCount, 1)
		assertions.isTrue(
			tracker:handleResponse(RESPONSE_DEFINITION, successWire(second.value.envelope.requestId, true)).ok
		)
		expectFailure(
			assertions,
			tracker:handleResponse(RESPONSE_DEFINITION, successWire(second.value.envelope.requestId, true)),
			"STALE_RESPONSE"
		)
	end),

	TestHarness.case("keeps exactly the newest 128 terminal IDs and permits count-evicted reuse", function(assertions)
		local nextId = "ring0001"
		local generatorReads = 0
		local tracker = makeTracker(function(): string
			generatorReads += 1
			return nextId
		end)
		registerNoResponse(assertions, tracker)

		for index = 1, ClientRequestTracker.MAX_TERMINAL_IDS + 1 do
			nextId = `ring{string.format("%04d", index)}`
			local built = tracker:buildRequest("TestNoResponseRequest", { count = index % 11 })
			assertions.isTrue(built.ok)
		end
		assertions.equal(tracker:getStats().terminalIdCount, 128)

		nextId = "ring0001"
		local evictedReuse = tracker:buildRequest("TestNoResponseRequest", { count = 1 })
		assertions.isTrue(evictedReuse.ok)
		assertions.equal(tracker:getStats().terminalIdCount, 128)

		nextId = "ring0129"
		local beforeReads = generatorReads
		expectFailure(assertions, tracker:buildRequest("TestNoResponseRequest", { count = 1 }), "ID_GENERATION_FAILED")
		assertions.equal(generatorReads - beforeReads, ClientRequestTracker.MAX_GENERATION_ATTEMPTS)
		assertions.equal(tracker:getStats().terminalIdCount, 128)
	end),

	TestHarness.case("clears all pending and recent correlation state explicitly", function(assertions)
		local generator, _reads = counterGenerator("clearid")
		local tracker = makeTracker(generator)
		registerRequired(assertions, tracker, "TestResponseRequest")
		registerNoResponse(assertions, tracker)
		local pending = tracker:buildRequest("TestResponseRequest", { count = 1 })
		assertions.isTrue(pending.ok)
		assertions.isTrue(tracker:buildRequest("TestNoResponseRequest", { count = 2 }).ok)
		assertions.equal(tracker:getStats().pendingCount, 1)
		assertions.equal(tracker:getStats().terminalIdCount, 1)

		tracker:clear()
		local stats = tracker:getStats()
		assertions.equal(stats.registrationCount, 2)
		assertions.equal(stats.pendingCount, 0)
		assertions.equal(stats.terminalIdCount, 0)
		if pending.ok then
			expectFailure(assertions, tracker:cancel(pending.value.pending), "INVALID_PENDING")
			expectFailure(
				assertions,
				tracker:handleResponse(RESPONSE_DEFINITION, successWire(pending.value.envelope.requestId, true)),
				"STALE_RESPONSE"
			)
		end
	end),
})
