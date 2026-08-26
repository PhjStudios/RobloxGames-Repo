--!strict

local PayloadValidation = require(script.Parent.PayloadValidation)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type PayloadSchema = PayloadValidation.Schema

export type RequestId = {
	value: string,
}

export type PublicErrorCode =
	"RATE_LIMITED"
	| "NOT_AUTHORIZED"
	| "INVALID_PAYLOAD"
	| "DUPLICATE_REQUEST"
	| "STALE_REQUEST"
	| "UNAVAILABLE"
	| "INTERNAL_ERROR"

export type PublicErrorMetadata = {
	validationPath: string,
}

export type PublicError = {
	code: PublicErrorCode,
	metadata: PublicErrorMetadata?,
}

export type ErrorCode =
	"MULTIPLE_ARGUMENTS"
	| "INVALID_TYPE"
	| "INVALID_TABLE"
	| "UNKNOWN_FIELD"
	| "MISSING_FIELD"
	| "INVALID_REQUEST_ID"
	| "INVALID_STATE"
	| "INVALID_PUBLIC_ERROR"
	| "INVALID_VALIDATION_PATH"

export type Error = {
	code: ErrorCode,
	path: string,
	message: string,
}

export type Request = {
	requestId: RequestId,
	payload: unknown,
}

export type Event = {
	payload: unknown,
}

export type Pending = {
	requestId: RequestId,
	state: "Pending",
}

export type Success = {
	requestId: RequestId,
	state: "Success",
	payload: unknown,
}

export type Rejected = {
	requestId: RequestId,
	state: "Rejected",
	error: PublicError,
}

export type Response = Success | Rejected

export type RawRequest = {
	requestId: string,
	payload: unknown,
}

export type RawEvent = {
	payload: unknown,
}

export type RawSuccess = {
	requestId: string,
	state: "Success",
	payload: unknown,
}

export type RawRejected = {
	requestId: string,
	state: "Rejected",
	error: {
		code: PublicErrorCode,
		metadata: PublicErrorMetadata?,
	},
}

local MIN_REQUEST_ID_BYTES = 8
local MAX_REQUEST_ID_BYTES = 48
local MAX_VALIDATION_PATH_BYTES = 256

local PUBLIC_ERROR_CODES: { PublicErrorCode } = table.freeze({
	"RATE_LIMITED",
	"NOT_AUTHORIZED",
	"INVALID_PAYLOAD",
	"DUPLICATE_REQUEST",
	"STALE_REQUEST",
	"UNAVAILABLE",
	"INTERNAL_ERROR",
})

local PUBLIC_ERROR_CODE_SET: { [string]: boolean } = table.freeze({
	RATE_LIMITED = true,
	NOT_AUTHORIZED = true,
	INVALID_PAYLOAD = true,
	DUPLICATE_REQUEST = true,
	STALE_REQUEST = true,
	UNAVAILABLE = true,
	INTERNAL_ERROR = true,
})

local REQUEST_FIELDS: { [string]: boolean } = table.freeze({
	requestId = true,
	payload = true,
})
local REQUEST_FIELD_ORDER: { string } = table.freeze({ "requestId", "payload" })

local EVENT_FIELDS: { [string]: boolean } = table.freeze({
	payload = true,
})
local EVENT_FIELD_ORDER: { string } = table.freeze({ "payload" })

local SUCCESS_FIELDS: { [string]: boolean } = table.freeze({
	requestId = true,
	state = true,
	payload = true,
})
local SUCCESS_FIELD_ORDER: { string } = table.freeze({ "requestId", "state", "payload" })

local REJECTED_FIELDS: { [string]: boolean } = table.freeze({
	requestId = true,
	state = true,
	error = true,
})
local REJECTED_FIELD_ORDER: { string } = table.freeze({ "requestId", "state", "error" })

local PUBLIC_ERROR_FIELDS: { [string]: boolean } = table.freeze({
	code = true,
	metadata = true,
})
local PUBLIC_ERROR_REQUIRED_FIELDS: { string } = table.freeze({ "code" })

local PUBLIC_METADATA_FIELDS: { [string]: boolean } = table.freeze({
	validationPath = true,
})
local PUBLIC_METADATA_FIELD_ORDER: { string } = table.freeze({ "validationPath" })

local AUTHENTIC_REQUEST_IDS = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
local AUTHENTIC_PUBLIC_ERRORS = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
local AUTHENTIC_ERRORS = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
local AUTHENTIC_PENDING = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
local AUTHENTIC_SUCCESSES = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
local AUTHENTIC_REJECTIONS = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }

local RequestProtocol = {
	MIN_REQUEST_ID_BYTES = MIN_REQUEST_ID_BYTES,
	MAX_REQUEST_ID_BYTES = MAX_REQUEST_ID_BYTES,
	MAX_VALIDATION_PATH_BYTES = MAX_VALIDATION_PATH_BYTES,
	PUBLIC_ERROR_CODES = PUBLIC_ERROR_CODES,
}

local function makeError(code: ErrorCode, path: string, message: string): Error
	local errorValue = table.freeze({
		code = code,
		path = path,
		message = message,
	})
	AUTHENTIC_ERRORS[errorValue] = true
	return errorValue
end

local function isAsciiLetter(byte: number): boolean
	return (byte >= string.byte("A") and byte <= string.byte("Z"))
		or (byte >= string.byte("a") and byte <= string.byte("z"))
end

local function isAsciiDigit(byte: number): boolean
	return byte >= string.byte("0") and byte <= string.byte("9")
end

local function usesRequestIdGrammar(value: string): boolean
	local length = #value
	if length < MIN_REQUEST_ID_BYTES or length > MAX_REQUEST_ID_BYTES then
		return false
	end

	local firstByte = string.byte(value, 1)
	if firstByte == nil or (not isAsciiLetter(firstByte) and not isAsciiDigit(firstByte)) then
		return false
	end

	for index = 2, length do
		local byte = string.byte(value, index)
		if
			byte == nil
			or (
				not isAsciiLetter(byte)
				and not isAsciiDigit(byte)
				and byte ~= string.byte("_")
				and byte ~= string.byte("-")
			)
		then
			return false
		end
	end

	return true
end

local function makeRequestId(value: string): RequestId
	local requestId = table.freeze({
		value = value,
	})
	AUTHENTIC_REQUEST_IDS[requestId] = true
	return requestId
end

local function readRequestId(value: unknown, path: string): (RequestId?, Error?)
	if type(value) ~= "string" or not usesRequestIdGrammar(value) then
		return nil, makeError("INVALID_REQUEST_ID", path, "Request ID must use the bounded canonical ASCII grammar")
	end
	return makeRequestId(value), nil
end

local function isPublicErrorCode(value: unknown): boolean
	return type(value) == "string" and rawget(PUBLIC_ERROR_CODE_SET, value) == true
end

local function usesCanonicalValidationPath(value: string): boolean
	local length = #value
	if length < #"payload" or length > MAX_VALIDATION_PATH_BYTES or string.sub(value, 1, #"payload") ~= "payload" then
		return false
	end
	if length == #"payload" then
		return true
	end

	local position = #"payload" + 1
	local segmentCount = 0
	while position <= length do
		local separator = string.byte(value, position)
		if separator == string.byte(".") then
			segmentCount += 1
			if segmentCount > PayloadValidation.MAX_DEPTH + 1 then
				return false
			end
			local nameStart = position + 1
			local firstByte = string.byte(value, nameStart)
			if firstByte == nil or not isAsciiLetter(firstByte) then
				return false
			end

			position = nameStart + 1
			while position <= length do
				local byte = string.byte(value, position)
				if byte == string.byte(".") or byte == string.byte("[") then
					break
				end
				if byte == nil or (not isAsciiLetter(byte) and not isAsciiDigit(byte) and byte ~= string.byte("_")) then
					return false
				end
				position += 1
			end
			if position - nameStart > Validation.MAX_KEY_BYTES then
				return false
			end
		elseif separator == string.byte("[") then
			segmentCount += 1
			if segmentCount > PayloadValidation.MAX_DEPTH + 1 then
				return false
			end
			local digitStart = position + 1
			local firstByte = string.byte(value, digitStart)
			if firstByte == nil or firstByte < string.byte("1") or firstByte > string.byte("9") then
				return false
			end

			local indexValue = firstByte - string.byte("0")
			position = digitStart + 1
			while position <= length do
				local byte = string.byte(value, position)
				if byte == string.byte("]") then
					break
				end
				if byte == nil or not isAsciiDigit(byte) then
					return false
				end
				indexValue = indexValue * 10 + byte - string.byte("0")
				if indexValue > PayloadValidation.MAX_ARRAY_ITEMS then
					return false
				end
				position += 1
			end
			if indexValue > PayloadValidation.MAX_ARRAY_ITEMS then
				return false
			end
			if position > length or string.byte(value, position) ~= string.byte("]") then
				return false
			end
			position += 1
		else
			return false
		end
	end

	return true
end

local function makePublicError(code: PublicErrorCode, validationPath: string?): PublicError
	local metadata: PublicErrorMetadata? = nil
	if validationPath ~= nil then
		metadata = table.freeze({
			validationPath = validationPath,
		})
	end
	local errorValue = table.freeze({
		code = code,
		metadata = metadata,
	})
	AUTHENTIC_PUBLIC_ERRORS[errorValue] = true
	return errorValue
end

local function readExactRecord(
	value: unknown,
	path: string,
	allowedFields: { [string]: boolean },
	requiredFields: { string }
): ({ [any]: unknown }?, Error?)
	if type(value) ~= "table" then
		return nil, makeError("INVALID_TYPE", path, "Envelope value must be a plain table")
	end

	local rawTable = value :: { [any]: unknown }
	if getmetatable(rawTable) ~= nil then
		return nil, makeError("INVALID_TABLE", path, "Envelope value must not have a metatable")
	end

	local fieldCount = 0
	local allowedCount = 0
	for _ in next, allowedFields do
		allowedCount += 1
	end
	for rawKey in next, rawTable do
		fieldCount += 1
		if fieldCount > allowedCount or type(rawKey) ~= "string" or rawget(allowedFields, rawKey) ~= true then
			return nil, makeError("UNKNOWN_FIELD", path, "Envelope value contains an unknown field")
		end
	end

	for index = 1, rawlen(requiredFields) do
		local fieldName = rawget(requiredFields, index)
		if rawget(rawTable, fieldName) == nil then
			return nil, makeError("MISSING_FIELD", `{path}.{fieldName}`, "Envelope value is missing a required field")
		end
	end

	return rawTable, nil
end

local function hasExtraArguments(...: unknown): boolean
	return select("#", ...) > 0
end

local function readPublicError(value: unknown, path: string): (PublicError?, Error?)
	local record, recordError = readExactRecord(value, path, PUBLIC_ERROR_FIELDS, PUBLIC_ERROR_REQUIRED_FIELDS)
	if recordError ~= nil then
		return nil, recordError
	end
	local rawRecord = record :: { [any]: unknown }
	local rawCode = rawget(rawRecord, "code")
	if not isPublicErrorCode(rawCode) then
		return nil, makeError("INVALID_PUBLIC_ERROR", `{path}.code`, "Public error code is not allowlisted")
	end
	local code = rawCode :: PublicErrorCode

	local rawMetadata = rawget(rawRecord, "metadata")
	if rawMetadata == nil then
		return makePublicError(code, nil), nil
	end
	if code ~= "INVALID_PAYLOAD" then
		return nil,
			makeError("INVALID_PUBLIC_ERROR", `{path}.metadata`, "Metadata is not allowed for this public error")
	end

	local metadataRecord, metadataError =
		readExactRecord(rawMetadata, `{path}.metadata`, PUBLIC_METADATA_FIELDS, PUBLIC_METADATA_FIELD_ORDER)
	if metadataError ~= nil then
		return nil, metadataError
	end
	local rawPath = rawget(metadataRecord :: { [any]: unknown }, "validationPath")
	if type(rawPath) ~= "string" or not usesCanonicalValidationPath(rawPath) then
		return nil,
			makeError(
				"INVALID_VALIDATION_PATH",
				`{path}.metadata.validationPath`,
				"Validation path must use the bounded canonical payload-path grammar"
			)
	end

	return makePublicError(code, rawPath), nil
end

local function publicErrorWire(errorValue: PublicError): { [string]: unknown }
	local wire: { [string]: unknown } = {
		code = errorValue.code,
	}
	local metadata = errorValue.metadata
	if metadata ~= nil then
		wire.metadata = table.freeze({
			validationPath = metadata.validationPath,
		})
	end
	return table.freeze(wire)
end

function RequestProtocol.createRequestId(value: unknown): Result.Result<RequestId, Error>
	local requestId, requestIdError = readRequestId(value, "requestId")
	if requestIdError ~= nil then
		return Result.err(requestIdError)
	end
	return Result.ok(requestId :: RequestId)
end

function RequestProtocol.isRequestId(value: unknown): boolean
	return type(value) == "table" and AUTHENTIC_REQUEST_IDS[value :: any] == true
end

function RequestProtocol.isError(value: unknown): boolean
	return type(value) == "table" and AUTHENTIC_ERRORS[value :: any] == true
end

function RequestProtocol.isPublicErrorCode(value: unknown): boolean
	return isPublicErrorCode(value)
end

function RequestProtocol.createPublicError(
	code: unknown,
	validationIssue: Validation.Issue?
): Result.Result<PublicError, Error>
	if not isPublicErrorCode(code) then
		return Result.err(makeError("INVALID_PUBLIC_ERROR", "publicError.code", "Public error code is not allowlisted"))
	end
	local publicCode = code :: PublicErrorCode
	if validationIssue == nil then
		return Result.ok(makePublicError(publicCode, nil))
	end
	if publicCode ~= "INVALID_PAYLOAD" then
		return Result.err(
			makeError("INVALID_PUBLIC_ERROR", "publicError.metadata", "Metadata is not allowed for this public error")
		)
	end
	if type(validationIssue) ~= "table" or getmetatable(validationIssue :: any) ~= nil then
		return Result.err(
			makeError(
				"INVALID_VALIDATION_PATH",
				"publicError.metadata.validationPath",
				"Validation issue must provide a canonical payload path"
			)
		)
	end

	local validationPath = rawget(validationIssue :: any, "path")
	if type(validationPath) ~= "string" then
		return Result.err(
			makeError(
				"INVALID_VALIDATION_PATH",
				"publicError.metadata.validationPath",
				"Validation issue must provide a canonical payload path"
			)
		)
	end
	if #validationPath > MAX_VALIDATION_PATH_BYTES then
		return Result.ok(makePublicError(publicCode, nil))
	end
	if not usesCanonicalValidationPath(validationPath) then
		return Result.err(
			makeError(
				"INVALID_VALIDATION_PATH",
				"publicError.metadata.validationPath",
				"Validation issue must provide a canonical payload path"
			)
		)
	end

	return Result.ok(makePublicError(publicCode, validationPath))
end

function RequestProtocol.isPublicError(value: unknown): boolean
	return type(value) == "table" and AUTHENTIC_PUBLIC_ERRORS[value :: any] == true
end

function RequestProtocol.createPending(requestId: unknown): Result.Result<Pending, Error>
	if not RequestProtocol.isRequestId(requestId) then
		return Result.err(makeError("INVALID_REQUEST_ID", "pending.requestId", "Expected an authentic request ID"))
	end
	local pending = table.freeze({
		requestId = requestId :: RequestId,
		state = "Pending" :: "Pending",
	})
	AUTHENTIC_PENDING[pending] = true
	return Result.ok(pending)
end

function RequestProtocol.createSuccess(requestId: unknown, payload: unknown): Result.Result<Success, Error>
	if not RequestProtocol.isRequestId(requestId) then
		return Result.err(makeError("INVALID_REQUEST_ID", "success.requestId", "Expected an authentic request ID"))
	end
	if payload == nil then
		return Result.err(makeError("MISSING_FIELD", "success.payload", "Success state requires a payload"))
	end
	local success = table.freeze({
		requestId = requestId :: RequestId,
		state = "Success" :: "Success",
		payload = payload,
	})
	AUTHENTIC_SUCCESSES[success] = true
	return Result.ok(success)
end

function RequestProtocol.createRejected(requestId: unknown, errorValue: unknown): Result.Result<Rejected, Error>
	if not RequestProtocol.isRequestId(requestId) then
		return Result.err(makeError("INVALID_REQUEST_ID", "rejected.requestId", "Expected an authentic request ID"))
	end
	if not RequestProtocol.isPublicError(errorValue) then
		return Result.err(makeError("INVALID_PUBLIC_ERROR", "rejected.error", "Expected an authentic public error"))
	end
	local rejected = table.freeze({
		requestId = requestId :: RequestId,
		state = "Rejected" :: "Rejected",
		error = errorValue :: PublicError,
	})
	AUTHENTIC_REJECTIONS[rejected] = true
	return Result.ok(rejected)
end

function RequestProtocol.isPending(value: unknown): boolean
	return type(value) == "table" and AUTHENTIC_PENDING[value :: any] == true
end

function RequestProtocol.isSuccess(value: unknown): boolean
	return type(value) == "table" and AUTHENTIC_SUCCESSES[value :: any] == true
end

function RequestProtocol.isRejected(value: unknown): boolean
	return type(value) == "table" and AUTHENTIC_REJECTIONS[value :: any] == true
end

function RequestProtocol.parseRequest(value: unknown, ...: unknown): Result.Result<Request, Error>
	if hasExtraArguments(...) then
		return Result.err(
			makeError("MULTIPLE_ARGUMENTS", "request", "Request must contain exactly one remote argument")
		)
	end
	local record, recordError = readExactRecord(value, "request", REQUEST_FIELDS, REQUEST_FIELD_ORDER)
	if recordError ~= nil then
		return Result.err(recordError)
	end
	local rawRecord = record :: { [any]: unknown }
	local requestId, requestIdError = readRequestId(rawget(rawRecord, "requestId"), "request.requestId")
	if requestIdError ~= nil then
		return Result.err(requestIdError)
	end
	return Result.ok(table.freeze({
		requestId = requestId :: RequestId,
		payload = rawget(rawRecord, "payload"),
	}))
end

function RequestProtocol.parseEvent(value: unknown, ...: unknown): Result.Result<Event, Error>
	if hasExtraArguments(...) then
		return Result.err(makeError("MULTIPLE_ARGUMENTS", "event", "Event must contain exactly one remote argument"))
	end
	local record, recordError = readExactRecord(value, "event", EVENT_FIELDS, EVENT_FIELD_ORDER)
	if recordError ~= nil then
		return Result.err(recordError)
	end
	return Result.ok(table.freeze({
		payload = rawget(record :: { [any]: unknown }, "payload"),
	}))
end

function RequestProtocol.parseResponse(value: unknown, ...: unknown): Result.Result<Response, Error>
	if hasExtraArguments(...) then
		return Result.err(
			makeError("MULTIPLE_ARGUMENTS", "response", "Response must contain exactly one remote argument")
		)
	end
	if type(value) ~= "table" then
		return Result.err(makeError("INVALID_TYPE", "response", "Response must be a plain table"))
	end
	local rawValue = value :: { [any]: unknown }
	if getmetatable(rawValue) ~= nil then
		return Result.err(makeError("INVALID_TABLE", "response", "Response must not have a metatable"))
	end

	local rawState = rawget(rawValue, "state")
	if rawState == nil then
		return Result.err(makeError("MISSING_FIELD", "response.state", "Response is missing its state"))
	end
	if rawState ~= "Success" and rawState ~= "Rejected" then
		return Result.err(makeError("INVALID_STATE", "response.state", "Response state is not recognized"))
	end

	local allowedFields = if rawState == "Success" then SUCCESS_FIELDS else REJECTED_FIELDS
	local requiredFields = if rawState == "Success" then SUCCESS_FIELD_ORDER else REJECTED_FIELD_ORDER
	local record, recordError = readExactRecord(rawValue, "response", allowedFields, requiredFields)
	if recordError ~= nil then
		return Result.err(recordError)
	end
	local rawRecord = record :: { [any]: unknown }
	local requestId, requestIdError = readRequestId(rawget(rawRecord, "requestId"), "response.requestId")
	if requestIdError ~= nil then
		return Result.err(requestIdError)
	end

	if rawState == "Success" then
		return RequestProtocol.createSuccess(requestId, rawget(rawRecord, "payload"))
	end

	local publicError, publicErrorError = readPublicError(rawget(rawRecord, "error"), "response.error")
	if publicErrorError ~= nil then
		return Result.err(publicErrorError)
	end
	return RequestProtocol.createRejected(requestId, publicError)
end

function RequestProtocol.buildRequest(requestId: unknown, payload: unknown): Result.Result<RawRequest, Error>
	if not RequestProtocol.isRequestId(requestId) then
		return Result.err(makeError("INVALID_REQUEST_ID", "request.requestId", "Expected an authentic request ID"))
	end
	if payload == nil then
		return Result.err(makeError("MISSING_FIELD", "request.payload", "Request requires a payload"))
	end
	return Result.ok(table.freeze({
		requestId = (requestId :: RequestId).value,
		payload = payload,
	}))
end

function RequestProtocol.buildEvent(payload: unknown): Result.Result<RawEvent, Error>
	if payload == nil then
		return Result.err(makeError("MISSING_FIELD", "event.payload", "Event requires a payload"))
	end
	return Result.ok(table.freeze({
		payload = payload,
	}))
end

function RequestProtocol.buildSuccess(requestId: unknown, payload: unknown): Result.Result<RawSuccess, Error>
	if not RequestProtocol.isRequestId(requestId) then
		return Result.err(makeError("INVALID_REQUEST_ID", "response.requestId", "Expected an authentic request ID"))
	end
	if payload == nil then
		return Result.err(makeError("MISSING_FIELD", "response.payload", "Success response requires a payload"))
	end
	return Result.ok(table.freeze({
		requestId = (requestId :: RequestId).value,
		state = "Success" :: "Success",
		payload = payload,
	}))
end

function RequestProtocol.buildRejected(requestId: unknown, errorValue: unknown): Result.Result<RawRejected, Error>
	if not RequestProtocol.isRequestId(requestId) then
		return Result.err(makeError("INVALID_REQUEST_ID", "response.requestId", "Expected an authentic request ID"))
	end
	if not RequestProtocol.isPublicError(errorValue) then
		return Result.err(makeError("INVALID_PUBLIC_ERROR", "response.error", "Expected an authentic public error"))
	end
	return Result.ok(table.freeze({
		requestId = (requestId :: RequestId).value,
		state = "Rejected" :: "Rejected",
		error = publicErrorWire(errorValue :: PublicError),
	}))
end

return table.freeze(RequestProtocol)
