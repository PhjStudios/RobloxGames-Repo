local EnvironmentContext = require(script.Parent.EnvironmentContext)

export type Severity = "DEBUG" | "INFO" | "WARN" | "ERROR"
export type Subsystem = "bootstrap" | "place-role" | "lifecycle" | "cleanup"
export type FieldValue = string | number | boolean
export type SafeFieldName =
	"cleanupState"
	| "cleanupTaskCount"
	| "code"
	| "container"
	| "lifecycleState"
	| "service"
	| "serviceCount"
	| "state"
export type Fields = { [SafeFieldName]: FieldValue }

export type ErrorCode =
	"INVALID_CONTEXT"
	| "INVALID_SEVERITY"
	| "INVALID_SUBSYSTEM"
	| "INVALID_EVENT"
	| "INVALID_MESSAGE"
	| "INVALID_FIELDS"
	| "INVALID_FIELD_NAME"
	| "RESERVED_FIELD"
	| "SENSITIVE_FIELD"
	| "UNKNOWN_FIELD"
	| "INVALID_FIELD_VALUE"

type LoggerData = {
	context: EnvironmentContext.Context,
}

local Logger = {}
Logger.__index = Logger

export type Logger = typeof(setmetatable({} :: LoggerData, Logger))

local Log = {}

local VALID_SEVERITIES: { [string]: boolean } = table.freeze({
	DEBUG = true,
	INFO = true,
	WARN = true,
	ERROR = true,
})

local VALID_SUBSYSTEMS: { [string]: boolean } = table.freeze({
	bootstrap = true,
	cleanup = true,
	lifecycle = true,
	["place-role"] = true,
})

local VALID_LABEL_PATTERN = "^[A-Za-z][A-Za-z0-9_.-]*$"
local VALID_STRING_FIELD_PATTERN = "^[A-Za-z0-9_%.:/<>,%-]+$"

local RESERVED_FIELDS: { [string]: boolean } = table.freeze({
	context = true,
	environment = true,
	event = true,
	placeId = true,
	role = true,
	severity = true,
	subsystem = true,
})

local SAFE_FIELDS: { [string]: boolean } = table.freeze({
	cleanupState = true,
	cleanupTaskCount = true,
	code = true,
	container = true,
	lifecycleState = true,
	service = true,
	serviceCount = true,
	state = true,
})

local SENSITIVE_FIELD_TOKENS = table.freeze({
	"profile",
	"accesscode",
	"teleportcode",
	"teleportdata",
	"purchase",
	"receipt",
	"payment",
	"product",
})

local LOGGER_REGISTRY = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }

local function requireLogger(value: unknown)
	if type(value) ~= "table" or LOGGER_REGISTRY[value] ~= true then
		error(
			"[ATD][ERROR][context=unknown][role=Unresolved][placeId=unknown][environment=unknown][subsystem=log][event=method_rejected][code=INVALID_CONTEXT] Logger method requires a genuine context-bound Log",
			0
		)
	end
end

local function basePrefix(
	context: EnvironmentContext.Context,
	severity: Severity,
	subsystem: string,
	event: string
): string
	return `[ATD][{severity}][context={context.executionContext}][role={context.placeRole}][placeId={context.placeId}][environment={context.runtimeEnvironment}][subsystem={subsystem}][event={event}]`
end

local function fail(logger: LoggerData, code: ErrorCode, message: string)
	error(basePrefix(logger.context, "ERROR", "log", "record_rejected") .. `[code={code}] {message}`, 0)
end

local function isSensitiveFieldName(fieldName: string): boolean
	local normalizedName = string.lower(string.gsub(fieldName, "[^A-Za-z0-9]", ""))
	for _, token in SENSITIVE_FIELD_TOKENS do
		if string.find(normalizedName, token, 1, true) ~= nil then
			return true
		end
	end

	return false
end

local function validateFieldValue(logger: LoggerData, fieldName: string, fieldValue: unknown): FieldValue
	local valueType = type(fieldValue)
	if valueType == "string" then
		if string.match(fieldValue :: string, VALID_STRING_FIELD_PATTERN) == nil then
			fail(
				logger,
				"INVALID_FIELD_VALUE",
				`Structured field '{fieldName}' must contain only safe token characters`
			)
		end
	elseif valueType == "number" then
		local numberValue = fieldValue :: number
		if numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
			fail(logger, "INVALID_FIELD_VALUE", `Structured field '{fieldName}' must be finite`)
		end
	elseif valueType ~= "boolean" then
		fail(
			logger,
			"INVALID_FIELD_VALUE",
			`Structured field '{fieldName}' must be a string, finite number, or boolean; received {typeof(fieldValue)}`
		)
	end

	return fieldValue :: FieldValue
end

function Logger.formatRecord(
	self: Logger,
	severity: Severity,
	subsystem: Subsystem,
	event: string,
	message: string,
	fields: Fields?
): string
	requireLogger(self)

	if type(severity) ~= "string" or VALID_SEVERITIES[severity] ~= true then
		fail(self, "INVALID_SEVERITY", "Severity must be DEBUG, INFO, WARN, or ERROR")
	end

	if type(subsystem) ~= "string" or VALID_SUBSYSTEMS[subsystem] ~= true then
		fail(self, "INVALID_SUBSYSTEM", "Subsystem is not part of the current logging contract")
	end

	if type(event) ~= "string" or string.match(event, VALID_LABEL_PATTERN) == nil then
		fail(self, "INVALID_EVENT", `Event must match {VALID_LABEL_PATTERN}`)
	end

	if
		type(message) ~= "string"
		or message == ""
		or string.find(message, "%c") ~= nil
	then
		fail(self, "INVALID_MESSAGE", "Message must be non-empty and contain no control characters")
	end

	local record = basePrefix(self.context, severity, subsystem, event)
	if fields ~= nil then
		if type(fields) ~= "table" then
			fail(self, "INVALID_FIELDS", "Structured fields must be a dictionary or nil")
		end

		local fieldNames = {}
		for fieldName in fields :: { [any]: any } do
			if type(fieldName) ~= "string" or string.match(fieldName, VALID_LABEL_PATTERN) == nil then
				fail(self, "INVALID_FIELD_NAME", `Structured field names must match {VALID_LABEL_PATTERN}`)
			end

			if RESERVED_FIELDS[fieldName] then
				fail(self, "RESERVED_FIELD", `Structured field '{fieldName}' is supplied by the logger`)
			end

			if isSensitiveFieldName(fieldName) then
				fail(self, "SENSITIVE_FIELD", "A structured field name is prohibited by the logging policy")
			end

			if SAFE_FIELDS[fieldName] ~= true then
				fail(self, "UNKNOWN_FIELD", "A structured field name is not in the safe field allowlist")
			end

			table.insert(fieldNames, fieldName)
		end

		table.sort(fieldNames)
		for _, fieldName in fieldNames do
			local fieldValue = validateFieldValue(self, fieldName, (fields :: { [string]: unknown })[fieldName])
			record ..= `[{fieldName}={tostring(fieldValue)}]`
		end
	end

	return `{record} {message}`
end

function Logger.debug(self: Logger, subsystem: Subsystem, event: string, message: string, fields: Fields?): string?
	requireLogger(self)

	if not self.context.isStudio then
		return nil
	end

	local record = self:formatRecord("DEBUG", subsystem, event, message, fields)
	print(record)
	return record
end

function Logger.info(self: Logger, subsystem: Subsystem, event: string, message: string, fields: Fields?): string?
	requireLogger(self)

	if not self.context.isStudio then
		return nil
	end

	local record = self:formatRecord("INFO", subsystem, event, message, fields)
	print(record)
	return record
end

function Logger.warn(self: Logger, subsystem: Subsystem, event: string, message: string, fields: Fields?): string
	local record = self:formatRecord("WARN", subsystem, event, message, fields)
	warn(record)
	return record
end

function Logger.error(self: Logger, subsystem: Subsystem, event: string, message: string, fields: Fields?): never
	error(self:formatRecord("ERROR", subsystem, event, message, fields), 0)
end

function Logger.getContext(self: Logger): EnvironmentContext.Context
	requireLogger(self)
	return self.context
end

function Log.new(context: EnvironmentContext.Context): Logger
	if not EnvironmentContext.isContext(context) then
		error(
			"[ATD][ERROR][context=unknown][role=Unresolved][placeId=unknown][environment=unknown][subsystem=log][event=construction_rejected][code=INVALID_CONTEXT] Log requires a genuine EnvironmentContext",
			0
		)
	end

	local logger = setmetatable({
		context = context,
	}, Logger) :: Logger

	table.freeze(logger)
	LOGGER_REGISTRY[logger] = true
	return logger
end

function Log.isLogger(value: unknown): boolean
	return type(value) == "table" and LOGGER_REGISTRY[value] == true
end

table.freeze(Logger)
return table.freeze(Log)
