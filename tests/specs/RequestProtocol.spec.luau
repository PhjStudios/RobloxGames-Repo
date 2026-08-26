--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Shared = game:GetService("ReplicatedStorage").Shared
local RequestProtocol = require(Shared.network.RequestProtocol)
local Validation = require(Shared.util.Validation)

type Assertions = TestHarness.Assertions

local ERROR_FIELDS: { [string]: boolean } = table.freeze({
	code = true,
	path = true,
	message = true,
})

local PUBLIC_ERROR_FIELDS: { [string]: boolean } = table.freeze({
	code = true,
	metadata = true,
})

local function expectSuccess(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	return result.value
end

local function expectFailure(
	assertions: Assertions,
	result: any,
	code: RequestProtocol.ErrorCode,
	path: string
): RequestProtocol.Error
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local errorValue = result.error :: RequestProtocol.Error
	assertions.equal(errorValue.code, code)
	assertions.equal(errorValue.path, path)
	assertions.isTrue(type(errorValue.message) == "string" and #errorValue.message > 0)
	assertions.isTrue(RequestProtocol.isError(errorValue))
	assertions.isTrue(table.isfrozen(errorValue))
	local fieldCount = 0
	for fieldName in next, errorValue :: any do
		fieldCount += 1
		assertions.isTrue(type(fieldName) == "string" and ERROR_FIELDS[fieldName] == true)
	end
	assertions.equal(fieldCount, 3)
	return errorValue
end

local function requestId(assertions: Assertions, value: string): RequestProtocol.RequestId
	local canonical = expectSuccess(assertions, RequestProtocol.createRequestId(value)) :: RequestProtocol.RequestId
	assertions.isTrue(RequestProtocol.isRequestId(canonical))
	assertions.isTrue(table.isfrozen(canonical))
	assertions.equal(canonical.value, value)
	return canonical
end

local function publicError(
	assertions: Assertions,
	code: RequestProtocol.PublicErrorCode,
	issue: Validation.Issue?
): RequestProtocol.PublicError
	local errorValue =
		expectSuccess(assertions, RequestProtocol.createPublicError(code, issue)) :: RequestProtocol.PublicError
	assertions.isTrue(RequestProtocol.isPublicError(errorValue))
	assertions.isTrue(table.isfrozen(errorValue))
	return errorValue
end

local function assertExactPublicError(assertions: Assertions, errorValue: RequestProtocol.PublicError)
	local fieldCount = 0
	for fieldName in next, errorValue :: any do
		fieldCount += 1
		assertions.isTrue(type(fieldName) == "string" and PUBLIC_ERROR_FIELDS[fieldName] == true)
	end
	local expectedFieldCount = if errorValue.metadata == nil then 1 else 2
	assertions.equal(fieldCount, expectedFieldCount)
	assertions.isTrue(table.isfrozen(errorValue))
	if errorValue.metadata ~= nil then
		assertions.isTrue(table.isfrozen(errorValue.metadata))
	end
end

local function graphContains(root: unknown, target: unknown, seen: { [any]: boolean }?): boolean
	if root == target then
		return true
	end
	if type(root) ~= "table" then
		return false
	end
	local visited = seen or {}
	if rawget(visited, root) == true then
		return false
	end
	rawset(visited, root, true)
	for key, value in next, root :: any do
		if graphContains(key, target, visited) or graphContains(value, target, visited) then
			return true
		end
	end
	return false
end

local function hostileTable(invocations: { count: number }): { [any]: unknown }
	return setmetatable({ private = true }, {
		__index = function()
			invocations.count += 1
			return "PRIVATE_INDEX"
		end,
		__len = function()
			invocations.count += 1
			return 1
		end,
		__pairs = function()
			invocations.count += 1
			return next, {}, nil
		end,
		__iter = function()
			invocations.count += 1
			return next, {}, nil
		end,
		__tostring = function()
			invocations.count += 1
			return "PRIVATE_TOSTRING"
		end,
		__metatable = "locked",
	})
end

return TestHarness.suite("request protocol contract", {
	TestHarness.case("exports the fixed ID bounds and exact public error allowlist", function(assertions)
		assertions.equal(RequestProtocol.MIN_REQUEST_ID_BYTES, 8)
		assertions.equal(RequestProtocol.MAX_REQUEST_ID_BYTES, 48)
		assertions.equal(RequestProtocol.MAX_VALIDATION_PATH_BYTES, 256)
		assertions.isTrue(table.isfrozen(RequestProtocol))
		assertions.isTrue(table.isfrozen(RequestProtocol.PUBLIC_ERROR_CODES))

		local expected = {
			"RATE_LIMITED",
			"NOT_AUTHORIZED",
			"INVALID_PAYLOAD",
			"DUPLICATE_REQUEST",
			"STALE_REQUEST",
			"UNAVAILABLE",
			"INTERNAL_ERROR",
		}
		assertions.equal(rawlen(RequestProtocol.PUBLIC_ERROR_CODES), rawlen(expected))
		for index = 1, rawlen(expected) do
			local code = expected[index]
			assertions.equal(RequestProtocol.PUBLIC_ERROR_CODES[index], code)
			assertions.isTrue(RequestProtocol.isPublicErrorCode(code))
		end
		assertions.isFalse(RequestProtocol.isPublicErrorCode("PRIVATE_ERROR"))
		assertions.isFalse(RequestProtocol.isPublicErrorCode({ code = "RATE_LIMITED" }))
	end),

	TestHarness.case("creates only authentic bounded ASCII request IDs without coercion", function(assertions)
		for _, value in
			{
				"A1234567",
				"01234567",
				"a_b-cD09",
				"550e8400-e29b-41d4-a716-446655440000",
				string.rep("Z", RequestProtocol.MAX_REQUEST_ID_BYTES),
			}
		do
			requestId(assertions, value)
		end

		for _, value in
			{
				"",
				string.rep("a", RequestProtocol.MIN_REQUEST_ID_BYTES - 1),
				string.rep("a", RequestProtocol.MAX_REQUEST_ID_BYTES + 1),
				"_1234567",
				"-1234567",
				"A123456.",
				"A123456 ",
				"A123456" .. string.char(255),
			}
		do
			expectFailure(assertions, RequestProtocol.createRequestId(value), "INVALID_REQUEST_ID", "requestId")
		end
		for _, idKind in
			{
				"tower",
				"enemy",
				"map",
				"difficulty",
				"wave",
				"banner",
				"unit",
				"queue",
				"match",
				"transaction",
			}
		do
			expectFailure(
				assertions,
				RequestProtocol.createRequestId(`{idKind}:fixture`),
				"INVALID_REQUEST_ID",
				"requestId"
			)
		end

		local coercionCount = 0
		local hostile = setmetatable({}, {
			__tostring = function()
				coercionCount += 1
				return "A1234567"
			end,
		})
		expectFailure(assertions, RequestProtocol.createRequestId(hostile), "INVALID_REQUEST_ID", "requestId")
		assertions.equal(coercionCount, 0)
		assertions.isFalse(RequestProtocol.isRequestId(table.freeze({ value = "A1234567" })))
	end),

	TestHarness.case("builds and parses detached frozen request envelopes", function(assertions)
		local id = requestId(assertions, "Request_01")
		local payload = { value = "kept" }
		local wire = expectSuccess(assertions, RequestProtocol.buildRequest(id, payload)) :: RequestProtocol.RawRequest
		assertions.isTrue(table.isfrozen(wire))
		assertions.equal(wire.requestId, id.value)
		assertions.equal(wire.payload, payload)

		local authored = { requestId = id.value, payload = payload }
		local parsed = expectSuccess(assertions, RequestProtocol.parseRequest(authored)) :: RequestProtocol.Request
		assertions.isTrue(table.isfrozen(parsed))
		assertions.notEqual(parsed, authored)
		assertions.notEqual(parsed.requestId, id)
		assertions.isTrue(RequestProtocol.isRequestId(parsed.requestId))
		assertions.equal(parsed.requestId.value, id.value)
		assertions.equal(parsed.payload, payload)

		authored.requestId = "Changed_1"
		authored.payload = { value = "changed" }
		assertions.equal(parsed.requestId.value, id.value)
		assertions.equal(parsed.payload, payload)
		expectFailure(
			assertions,
			RequestProtocol.buildRequest({ value = id.value }, payload),
			"INVALID_REQUEST_ID",
			"request.requestId"
		)
		expectFailure(assertions, RequestProtocol.buildRequest(id, nil), "MISSING_FIELD", "request.payload")
	end),

	TestHarness.case("builds and parses the exact event envelope without an ID", function(assertions)
		local payload = { event = true }
		local wire = expectSuccess(assertions, RequestProtocol.buildEvent(payload)) :: RequestProtocol.RawEvent
		assertions.isTrue(table.isfrozen(wire))
		assertions.equal(wire.payload, payload)
		local parsed =
			expectSuccess(assertions, RequestProtocol.parseEvent({ payload = payload })) :: RequestProtocol.Event
		assertions.isTrue(table.isfrozen(parsed))
		assertions.equal(parsed.payload, payload)
		expectFailure(assertions, RequestProtocol.buildEvent(nil), "MISSING_FIELD", "event.payload")
		expectFailure(
			assertions,
			RequestProtocol.parseEvent({ requestId = "Request_01", payload = payload }),
			"UNKNOWN_FIELD",
			"event"
		)
	end),

	TestHarness.case("rejects malformed request and event top-level records in stable order", function(assertions)
		expectFailure(assertions, RequestProtocol.parseRequest(nil), "INVALID_TYPE", "request")
		expectFailure(assertions, RequestProtocol.parseRequest("private"), "INVALID_TYPE", "request")
		expectFailure(assertions, RequestProtocol.parseRequest({ payload = {} }), "MISSING_FIELD", "request.requestId")
		expectFailure(
			assertions,
			RequestProtocol.parseRequest({ requestId = "Request_01" }),
			"MISSING_FIELD",
			"request.payload"
		)
		expectFailure(
			assertions,
			RequestProtocol.parseRequest({ requestId = "Request_01", payload = {}, extra = true }),
			"UNKNOWN_FIELD",
			"request"
		)
		expectFailure(
			assertions,
			RequestProtocol.parseRequest({ requestId = "bad", payload = {} }),
			"INVALID_REQUEST_ID",
			"request.requestId"
		)
		expectFailure(
			assertions,
			RequestProtocol.parseRequest({ requestId = "Request_01", payload = {} }, "second"),
			"MULTIPLE_ARGUMENTS",
			"request"
		)
		expectFailure(
			assertions,
			RequestProtocol.parseRequest({ requestId = "Request_01", payload = {} }, nil),
			"MULTIPLE_ARGUMENTS",
			"request"
		)
		expectFailure(assertions, RequestProtocol.parseEvent({ payload = {} }, "second"), "MULTIPLE_ARGUMENTS", "event")

		local nonStringKey = { requestId = "Request_01", payload = {}, [1] = true }
		expectFailure(assertions, RequestProtocol.parseRequest(nonStringKey), "UNKNOWN_FIELD", "request")
		local withMetatable = setmetatable({ requestId = "Request_01", payload = {} }, {})
		expectFailure(assertions, RequestProtocol.parseRequest(withMetatable), "INVALID_TABLE", "request")
	end),

	TestHarness.case("builds parses and authenticates successful responses", function(assertions)
		local id = requestId(assertions, "Success_01")
		local payload = { accepted = true }
		local wire = expectSuccess(assertions, RequestProtocol.buildSuccess(id, payload)) :: RequestProtocol.RawSuccess
		assertions.isTrue(table.isfrozen(wire))
		assertions.equal(wire.state, "Success")
		assertions.equal(wire.requestId, id.value)
		assertions.equal(wire.payload, payload)

		local authored = { requestId = id.value, state = "Success", payload = payload }
		local response = expectSuccess(assertions, RequestProtocol.parseResponse(authored)) :: RequestProtocol.Success
		assertions.isTrue(RequestProtocol.isSuccess(response))
		assertions.isTrue(table.isfrozen(response))
		assertions.notEqual(response, authored)
		assertions.equal(response.requestId.value, id.value)
		assertions.equal(response.payload, payload)
		assertions.equal(response.state, "Success")

		expectFailure(assertions, RequestProtocol.buildSuccess({}, payload), "INVALID_REQUEST_ID", "response.requestId")
		expectFailure(assertions, RequestProtocol.buildSuccess(id, nil), "MISSING_FIELD", "response.payload")
	end),

	TestHarness.case("builds parses and authenticates rejected responses for every public code", function(assertions)
		local id = requestId(assertions, "Reject_001")
		for _, code in RequestProtocol.PUBLIC_ERROR_CODES do
			local errorValue = publicError(assertions, code, nil)
			assertExactPublicError(assertions, errorValue)
			local wire =
				expectSuccess(assertions, RequestProtocol.buildRejected(id, errorValue)) :: RequestProtocol.RawRejected
			assertions.isTrue(table.isfrozen(wire))
			assertions.isTrue(table.isfrozen(wire.error))
			assertions.notEqual(wire.error, errorValue)
			assertions.equal(wire.error.code, code)

			local response = expectSuccess(assertions, RequestProtocol.parseResponse(wire)) :: RequestProtocol.Rejected
			assertions.isTrue(RequestProtocol.isRejected(response))
			assertions.isTrue(table.isfrozen(response))
			assertions.isTrue(RequestProtocol.isPublicError(response.error))
			assertions.notEqual(response.error, errorValue)
			assertions.equal(response.error.code, code)
			assertions.equal(response.state, "Rejected")
		end

		expectFailure(
			assertions,
			RequestProtocol.buildRejected(id, table.freeze({ code = "RATE_LIMITED" })),
			"INVALID_PUBLIC_ERROR",
			"response.error"
		)
	end),

	TestHarness.case("allows only bounded canonical validation-path metadata", function(assertions)
		local issue = Validation.issue("INVALID_TYPE", { "payload", "items", 1, "name" }, "Static validator issue")
		local errorValue = publicError(assertions, "INVALID_PAYLOAD", issue)
		assertExactPublicError(assertions, errorValue)
		assertions.isNotNil(errorValue.metadata)
		assertions.equal(
			(errorValue.metadata :: RequestProtocol.PublicErrorMetadata).validationPath,
			"payload.items[1].name"
		)

		for _, code in RequestProtocol.PUBLIC_ERROR_CODES do
			if code ~= "INVALID_PAYLOAD" then
				expectFailure(
					assertions,
					RequestProtocol.createPublicError(code, issue),
					"INVALID_PUBLIC_ERROR",
					"publicError.metadata"
				)
			end
		end

		local invalidRoot = Validation.issue("INVALID_TYPE", { "private", "value" }, "Static issue")
		expectFailure(
			assertions,
			RequestProtocol.createPublicError("INVALID_PAYLOAD", invalidRoot),
			"INVALID_VALIDATION_PATH",
			"publicError.metadata.validationPath"
		)
		local counterfeitIssue = table.freeze({ path = "payload.value" })
		local counterfeitResult = RequestProtocol.createPublicError("INVALID_PAYLOAD", counterfeitIssue :: any)
		assertions.isTrue(counterfeitResult.ok)
		assertions.equal((counterfeitResult :: any).value.metadata.validationPath, "payload.value")

		local longSegments = { "payload" }
		for _ = 1, 4 do
			table.insert(longSegments, string.rep("a", Validation.MAX_KEY_BYTES))
		end
		local longIssue = Validation.issue("INVALID_TYPE", longSegments, "Static issue")
		assertions.isTrue(#longIssue.path > RequestProtocol.MAX_VALIDATION_PATH_BYTES)
		local omitted = publicError(assertions, "INVALID_PAYLOAD", longIssue)
		assertions.isNil(omitted.metadata)
	end),

	TestHarness.case("strictly revalidates public error wire records after transport copying", function(assertions)
		local idValue = "Public_001"
		local wire = {
			requestId = idValue,
			state = "Rejected",
			error = {
				code = "INVALID_PAYLOAD",
				metadata = { validationPath = "payload.items[128].name" },
			},
		}
		local response = expectSuccess(assertions, RequestProtocol.parseResponse(wire)) :: RequestProtocol.Rejected
		assertions.equal(response.error.code, "INVALID_PAYLOAD")
		assertions.equal(
			(response.error.metadata :: RequestProtocol.PublicErrorMetadata).validationPath,
			"payload.items[128].name"
		)
		assertions.notEqual(response.error, wire.error)
		assertions.notEqual(response.error.metadata, wire.error.metadata)

		local invalidErrors = {
			{ code = "PRIVATE_ERROR" },
			{ code = "RATE_LIMITED", metadata = { validationPath = "payload" } },
			{ code = "INVALID_PAYLOAD", message = "private" },
			{ code = "INVALID_PAYLOAD", metadata = {} },
			{ code = "INVALID_PAYLOAD", metadata = { validationPath = "private.value" } },
			{ code = "INVALID_PAYLOAD", metadata = { validationPath = "payload.items[0]" } },
			{ code = "INVALID_PAYLOAD", metadata = { validationPath = "payload.items[01]" } },
			{ code = "INVALID_PAYLOAD", metadata = { validationPath = "payload.items[129]" } },
			{ code = "INVALID_PAYLOAD", metadata = { validationPath = "payload..value" } },
			{ code = "INVALID_PAYLOAD", metadata = { validationPath = string.rep("p", 257) } },
		}
		for _, invalidError in invalidErrors do
			local result = RequestProtocol.parseResponse({
				requestId = idValue,
				state = "Rejected",
				error = invalidError,
			})
			assertions.isFalse(result.ok)
		end

		local hostileMetadata = setmetatable({ validationPath = "payload.value" }, {})
		expectFailure(
			assertions,
			RequestProtocol.parseResponse({
				requestId = idValue,
				state = "Rejected",
				error = { code = "INVALID_PAYLOAD", metadata = hostileMetadata },
			}),
			"INVALID_TABLE",
			"response.error.metadata"
		)
		local hostileError = setmetatable({ code = "RATE_LIMITED" }, {})
		expectFailure(
			assertions,
			RequestProtocol.parseResponse({
				requestId = idValue,
				state = "Rejected",
				error = hostileError,
			}),
			"INVALID_TABLE",
			"response.error"
		)
	end),

	TestHarness.case("rejects malformed response states and overlapping wire shapes", function(assertions)
		expectFailure(assertions, RequestProtocol.parseResponse(nil), "INVALID_TYPE", "response")
		expectFailure(
			assertions,
			RequestProtocol.parseResponse({ requestId = "Response_1", payload = {} }),
			"MISSING_FIELD",
			"response.state"
		)
		expectFailure(
			assertions,
			RequestProtocol.parseResponse({ requestId = "Response_1", state = "Pending", payload = {} }),
			"INVALID_STATE",
			"response.state"
		)
		expectFailure(
			assertions,
			RequestProtocol.parseResponse({ requestId = "Response_1", state = "Success" }),
			"MISSING_FIELD",
			"response.payload"
		)
		expectFailure(
			assertions,
			RequestProtocol.parseResponse({
				requestId = "Response_1",
				state = "Success",
				payload = {},
				error = { code = "RATE_LIMITED" },
			}),
			"UNKNOWN_FIELD",
			"response"
		)
		expectFailure(
			assertions,
			RequestProtocol.parseResponse({
				requestId = "Response_1",
				state = "Rejected",
				error = { code = "RATE_LIMITED" },
				payload = {},
			}),
			"UNKNOWN_FIELD",
			"response"
		)
		expectFailure(
			assertions,
			RequestProtocol.parseResponse({
				requestId = "Response_1",
				state = "Rejected",
				error = { code = "RATE_LIMITED" },
			}, "second"),
			"MULTIPLE_ARGUMENTS",
			"response"
		)
		local metatableResponse = setmetatable({
			requestId = "Response_1",
			state = "Success",
			payload = {},
		}, {})
		expectFailure(assertions, RequestProtocol.parseResponse(metatableResponse), "INVALID_TABLE", "response")
	end),

	TestHarness.case("constructs authentic immutable Pending Success and Rejected states", function(assertions)
		local id = requestId(assertions, "States_001")
		local pending = expectSuccess(assertions, RequestProtocol.createPending(id)) :: RequestProtocol.Pending
		assertions.isTrue(RequestProtocol.isPending(pending))
		assertions.isTrue(table.isfrozen(pending))
		assertions.equal(pending.state, "Pending")

		local payload = table.freeze({ accepted = true })
		local success = expectSuccess(assertions, RequestProtocol.createSuccess(id, payload)) :: RequestProtocol.Success
		assertions.isTrue(RequestProtocol.isSuccess(success))
		assertions.isTrue(table.isfrozen(success))
		assertions.equal(success.state, "Success")
		assertions.equal(success.payload, payload)

		local safeError = publicError(assertions, "UNAVAILABLE", nil)
		local rejected =
			expectSuccess(assertions, RequestProtocol.createRejected(id, safeError)) :: RequestProtocol.Rejected
		assertions.isTrue(RequestProtocol.isRejected(rejected))
		assertions.isTrue(table.isfrozen(rejected))
		assertions.equal(rejected.state, "Rejected")
		assertions.equal(rejected.error, safeError)

		assertions.isFalse(RequestProtocol.isPending(table.freeze({ requestId = id, state = "Pending" })))
		assertions.isFalse(
			RequestProtocol.isSuccess(table.freeze({ requestId = id, state = "Success", payload = payload }))
		)
		assertions.isFalse(
			RequestProtocol.isRejected(table.freeze({ requestId = id, state = "Rejected", error = safeError }))
		)
		expectFailure(
			assertions,
			RequestProtocol.createPending({ value = id.value }),
			"INVALID_REQUEST_ID",
			"pending.requestId"
		)
		expectFailure(assertions, RequestProtocol.createSuccess(id, nil), "MISSING_FIELD", "success.payload")
		expectFailure(assertions, RequestProtocol.createRejected(id, {}), "INVALID_PUBLIC_ERROR", "rejected.error")
	end),

	TestHarness.case("does not invoke hostile payload metamethods during cheap envelope checks", function(assertions)
		local invocations = { count = 0 }
		local hostilePayload = hostileTable(invocations)
		local valid = RequestProtocol.parseRequest({ requestId = "Hostile_1", payload = hostilePayload })
		assertions.isTrue(valid.ok)
		assertions.equal((valid :: any).value.payload, hostilePayload)
		assertions.equal(invocations.count, 0)

		expectFailure(
			assertions,
			RequestProtocol.parseRequest({ requestId = "bad", payload = hostilePayload }),
			"INVALID_REQUEST_ID",
			"request.requestId"
		)
		expectFailure(
			assertions,
			RequestProtocol.parseRequest({ requestId = "Hostile_1", payload = hostilePayload, extra = true }),
			"UNKNOWN_FIELD",
			"request"
		)
		expectFailure(
			assertions,
			RequestProtocol.parseResponse({
				requestId = "Hostile_1",
				state = "Success",
				payload = hostilePayload,
				extra = true,
			}),
			"UNKNOWN_FIELD",
			"response"
		)
		assertions.equal(invocations.count, 0)
	end),

	TestHarness.case("never retains or echoes rejected envelope values", function(assertions)
		local privateObject = { secret = "PRIVATE_PAYLOAD_SENTINEL_06_4" }
		local requestFailure = expectFailure(
			assertions,
			RequestProtocol.parseRequest({ requestId = "bad", payload = privateObject }),
			"INVALID_REQUEST_ID",
			"request.requestId"
		)
		assertions.isFalse(graphContains(requestFailure, privateObject))
		for _, fieldName in { "code", "path", "message" } do
			assertions.isNil(string.find((requestFailure :: any)[fieldName], privateObject.secret, 1, true))
		end

		local rejectedFailure = expectFailure(
			assertions,
			RequestProtocol.parseResponse({
				requestId = "Private_1",
				state = "Rejected",
				error = { code = "PRIVATE_ERROR", secret = privateObject },
			}),
			"UNKNOWN_FIELD",
			"response.error"
		)
		assertions.isFalse(graphContains(rejectedFailure, privateObject))
		assertions.isNil(string.find(rejectedFailure.message, privateObject.secret, 1, true))
	end),
})
