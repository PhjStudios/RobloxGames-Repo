--!strict

local Result = require(script.Parent.Parent.util.Result)

export type Transport = "ReliableRemoteEvent"
export type Direction = "ClientToServer" | "ServerToClient"
export type Kind = "Request" | "Event"
export type ResponseBehavior = "None" | "Required"
export type PlaceRole = "Lobby" | "Match"
export type RuntimePlaceRole = "Development" | PlaceRole

export type Definition = {
	name: string,
	transport: Transport,
	direction: Direction,
	kind: Kind,
	response: ResponseBehavior,
	placeRoles: { PlaceRole },
}

export type ErrorCode =
	"INVALID_TYPE"
	| "INVALID_TABLE"
	| "INVALID_ARRAY"
	| "TOO_MANY_DEFINITIONS"
	| "UNKNOWN_FIELD"
	| "MISSING_FIELD"
	| "NAME_TOO_LONG"
	| "INVALID_NAME"
	| "RESERVED_NAME"
	| "INVALID_ENUM"
	| "EMPTY_PLACE_ROLES"
	| "DUPLICATE_PLACE_ROLE"
	| "INVALID_COMBINATION"
	| "DUPLICATE_DEFINITION"
	| "CONFLICTING_DEFINITION"

export type Error = {
	code: ErrorCode,
	path: string,
	message: string,
}

local ROOT_NAME = "ATDNetwork"
local VERSION_NAME = "v1"
local MAX_DEFINITIONS = 128
local MAX_NAME_BYTES = 48
local DEFINITION_FIELD_COUNT = 6

local DEFINITION_FIELDS: { [string]: boolean } = table.freeze({
	name = true,
	transport = true,
	direction = true,
	kind = true,
	response = true,
	placeRoles = true,
})

local REQUIRED_FIELDS: { string } = table.freeze({
	"name",
	"transport",
	"direction",
	"kind",
	"response",
	"placeRoles",
})

local RESERVED_NAMES: { [string]: boolean } = table.freeze({
	[string.lower(ROOT_NAME)] = true,
	[string.lower(VERSION_NAME)] = true,
	event = true,
	request = true,
	response = true,
})

local EMPTY_DEFINITIONS: { Definition } = table.freeze({})
local AUTHENTIC_DEFINITIONS = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
local AUTHENTIC_REGISTRIES = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }

type RegistryData = {
	_ordered: { Definition },
	_byName: { [string]: Definition },
	_byRole: { [RuntimePlaceRole]: { Definition } },
	_count: number,
}

local Registry = {}
Registry.__index = Registry

export type Registry = typeof(setmetatable({} :: RegistryData, Registry))

local RemoteRegistry = {
	ROOT_NAME = ROOT_NAME,
	VERSION_NAME = VERSION_NAME,
	MAX_DEFINITIONS = MAX_DEFINITIONS,
	MAX_NAME_BYTES = MAX_NAME_BYTES,
}

local function makeError(code: ErrorCode, path: string, message: string): Error
	return table.freeze({
		code = code,
		path = path,
		message = message,
	})
end

local function definitionPath(index: number): string
	return `definitions[{index}]`
end

local function fieldPath(index: number, fieldName: string): string
	return `{definitionPath(index)}.{fieldName}`
end

local function indexedFieldPath(index: number, fieldName: string, fieldIndex: number): string
	return `{fieldPath(index, fieldName)}[{fieldIndex}]`
end

local function readDefinitionArray(value: unknown): ({ unknown }?, Error?)
	if type(value) ~= "table" then
		return nil, makeError("INVALID_TYPE", "definitions", "Remote definitions must be a dense array")
	end

	local rawTable = value :: { [any]: unknown }
	if getmetatable(rawTable) ~= nil then
		return nil, makeError("INVALID_TABLE", "definitions", "Remote definitions must use a plain table")
	end

	local entryCount = 0
	local maximumIndex = 0
	local hasInvalidKey = false
	for rawKey in next, rawTable do
		entryCount += 1
		if entryCount > MAX_DEFINITIONS then
			return nil,
				makeError("TOO_MANY_DEFINITIONS", "definitions", "Remote definition count exceeds the technical limit")
		end

		if type(rawKey) ~= "number" or rawKey < 1 or rawKey % 1 ~= 0 then
			hasInvalidKey = true
		else
			maximumIndex = math.max(maximumIndex, rawKey)
		end
	end

	if hasInvalidKey then
		return nil, makeError("INVALID_ARRAY", "definitions", "Remote definitions must be a dense one-based array")
	end
	if maximumIndex > MAX_DEFINITIONS then
		return nil,
			makeError("TOO_MANY_DEFINITIONS", "definitions", "Remote definition count exceeds the technical limit")
	end
	if maximumIndex ~= entryCount then
		return nil, makeError("INVALID_ARRAY", "definitions", "Remote definitions must be a dense one-based array")
	end

	local copy: { unknown } = table.create(entryCount)
	for index = 1, entryCount do
		copy[index] = rawget(rawTable, index)
	end
	return copy, nil
end

local function readDefinitionRecord(value: unknown, index: number): ({ [string]: unknown }?, Error?)
	local path = definitionPath(index)
	if type(value) ~= "table" then
		return nil, makeError("INVALID_TYPE", path, "Remote definition must be a plain table")
	end

	local rawTable = value :: { [any]: unknown }
	if getmetatable(rawTable) ~= nil then
		return nil, makeError("INVALID_TABLE", path, "Remote definition must not have a metatable")
	end

	local fieldCount = 0
	local hasUnknownField = false
	for rawKey in next, rawTable do
		fieldCount += 1
		if fieldCount > DEFINITION_FIELD_COUNT then
			return nil, makeError("UNKNOWN_FIELD", path, "Remote definition contains an unknown field")
		end
		if type(rawKey) ~= "string" or DEFINITION_FIELDS[rawKey] ~= true then
			hasUnknownField = true
		end
	end

	if hasUnknownField then
		return nil, makeError("UNKNOWN_FIELD", path, "Remote definition contains an unknown field")
	end

	for _, fieldName in REQUIRED_FIELDS do
		if rawget(rawTable, fieldName) == nil then
			return nil,
				makeError("MISSING_FIELD", fieldPath(index, fieldName), "Remote definition is missing a required field")
		end
	end

	return rawTable :: { [string]: unknown }, nil
end

local function isAsciiLetter(byte: number): boolean
	return (byte >= string.byte("A") and byte <= string.byte("Z"))
		or (byte >= string.byte("a") and byte <= string.byte("z"))
end

local function isAsciiUppercaseLetter(byte: number): boolean
	return byte >= string.byte("A") and byte <= string.byte("Z")
end

local function isAsciiDigit(byte: number): boolean
	return byte >= string.byte("0") and byte <= string.byte("9")
end

local function usesCanonicalNameGrammar(value: string): boolean
	if #value < 1 then
		return false
	end

	local firstByte = string.byte(value, 1)
	if firstByte == nil or not isAsciiUppercaseLetter(firstByte) then
		return false
	end

	for index = 2, #value do
		local byte = string.byte(value, index)
		if byte == nil or (not isAsciiLetter(byte) and not isAsciiDigit(byte)) then
			return false
		end
	end

	return true
end

local function validateName(value: unknown, index: number): (string?, Error?)
	local path = fieldPath(index, "name")
	if type(value) ~= "string" then
		return nil, makeError("INVALID_TYPE", path, "Remote name must be a string")
	end
	if #value > MAX_NAME_BYTES then
		return nil, makeError("NAME_TOO_LONG", path, "Remote name exceeds the protocol byte limit")
	end
	if RESERVED_NAMES[string.lower(value)] == true then
		return nil, makeError("RESERVED_NAME", path, "Remote name is reserved by the protocol layout")
	end
	if not usesCanonicalNameGrammar(value) then
		return nil, makeError("INVALID_NAME", path, "Remote name must use the canonical single-token grammar")
	end

	return value, nil
end

local function validateEnum(
	value: unknown,
	index: number,
	fieldName: string,
	allowedValues: { [string]: boolean },
	description: string
): (string?, Error?)
	local path = fieldPath(index, fieldName)
	if type(value) ~= "string" then
		return nil, makeError("INVALID_TYPE", path, `{description} must be a string`)
	end
	if allowedValues[value] ~= true then
		return nil, makeError("INVALID_ENUM", path, `{description} is not recognized`)
	end
	return value, nil
end

local TRANSPORTS: { [string]: boolean } = table.freeze({ ReliableRemoteEvent = true })
local DIRECTIONS: { [string]: boolean } = table.freeze({ ClientToServer = true, ServerToClient = true })
local KINDS: { [string]: boolean } = table.freeze({ Event = true, Request = true })
local RESPONSES: { [string]: boolean } = table.freeze({ None = true, Required = true })
local PLACE_ROLES: { [string]: boolean } = table.freeze({ Lobby = true, Match = true })

local function validatePlaceRoles(value: unknown, index: number): ({ PlaceRole }?, Error?)
	local path = fieldPath(index, "placeRoles")
	if type(value) ~= "table" then
		return nil, makeError("INVALID_TYPE", path, "Remote place roles must be a dense array")
	end

	local rawTable = value :: { [any]: unknown }
	if getmetatable(rawTable) ~= nil then
		return nil, makeError("INVALID_TABLE", path, "Remote place roles must not have a metatable")
	end

	local entryCount = 0
	local maximumIndex = 0
	local hasInvalidKey = false
	for rawKey in next, rawTable do
		entryCount += 1
		if entryCount > 2 then
			return nil, makeError("INVALID_ARRAY", path, "Remote place roles exceed the supported role count")
		end
		if type(rawKey) ~= "number" or rawKey < 1 or rawKey % 1 ~= 0 then
			hasInvalidKey = true
		else
			maximumIndex = math.max(maximumIndex, rawKey)
		end
	end

	if hasInvalidKey or maximumIndex ~= entryCount then
		return nil, makeError("INVALID_ARRAY", path, "Remote place roles must be a dense one-based array")
	end
	if entryCount == 0 then
		return nil, makeError("EMPTY_PLACE_ROLES", path, "Remote definition must declare at least one place role")
	end

	local hasLobby = false
	local hasMatch = false
	for roleIndex = 1, entryCount do
		local rawRole = rawget(rawTable, roleIndex)
		local rolePath = indexedFieldPath(index, "placeRoles", roleIndex)
		if type(rawRole) ~= "string" then
			return nil, makeError("INVALID_TYPE", rolePath, "Remote place role must be a string")
		end
		if PLACE_ROLES[rawRole] ~= true then
			return nil, makeError("INVALID_ENUM", rolePath, "Remote place role is not recognized")
		end
		if (rawRole == "Lobby" and hasLobby) or (rawRole == "Match" and hasMatch) then
			return nil, makeError("DUPLICATE_PLACE_ROLE", rolePath, "Remote place role duplicates an earlier role")
		end
		hasLobby = hasLobby or rawRole == "Lobby"
		hasMatch = hasMatch or rawRole == "Match"
	end

	local canonicalRoles: { PlaceRole } = {}
	if hasLobby then
		table.insert(canonicalRoles, "Lobby")
	end
	if hasMatch then
		table.insert(canonicalRoles, "Match")
	end
	return canonicalRoles, nil
end

local function validateDefinition(value: unknown, index: number): (Definition?, Error?)
	local record, recordError = readDefinitionRecord(value, index)
	if recordError ~= nil then
		return nil, recordError
	end
	local rawRecord = record :: { [string]: unknown }

	local name, nameError = validateName(rawget(rawRecord, "name"), index)
	if nameError ~= nil then
		return nil, nameError
	end

	local transport, transportError =
		validateEnum(rawget(rawRecord, "transport"), index, "transport", TRANSPORTS, "Remote transport")
	if transportError ~= nil then
		return nil, transportError
	end

	local direction, directionError =
		validateEnum(rawget(rawRecord, "direction"), index, "direction", DIRECTIONS, "Remote direction")
	if directionError ~= nil then
		return nil, directionError
	end

	local kind, kindError = validateEnum(rawget(rawRecord, "kind"), index, "kind", KINDS, "Remote kind")
	if kindError ~= nil then
		return nil, kindError
	end

	local response, responseError =
		validateEnum(rawget(rawRecord, "response"), index, "response", RESPONSES, "Remote response behavior")
	if responseError ~= nil then
		return nil, responseError
	end

	local placeRoles, placeRolesError = validatePlaceRoles(rawget(rawRecord, "placeRoles"), index)
	if placeRolesError ~= nil then
		return nil, placeRolesError
	end

	if kind == "Request" and direction ~= "ClientToServer" then
		return nil,
			makeError(
				"INVALID_COMBINATION",
				fieldPath(index, "direction"),
				"Request remotes must use the client-to-server direction"
			)
	end
	if kind == "Event" and response ~= "None" then
		return nil,
			makeError("INVALID_COMBINATION", fieldPath(index, "response"), "Event remotes cannot declare a response")
	end

	local definition: Definition = table.freeze({
		name = name :: string,
		transport = transport :: Transport,
		direction = direction :: Direction,
		kind = kind :: Kind,
		response = response :: ResponseBehavior,
		placeRoles = table.freeze(placeRoles :: { PlaceRole }),
	})
	AUTHENTIC_DEFINITIONS[definition] = true
	return definition, nil
end

local function definitionsEqual(left: Definition, right: Definition): boolean
	if
		left.name ~= right.name
		or left.transport ~= right.transport
		or left.direction ~= right.direction
		or left.kind ~= right.kind
		or left.response ~= right.response
		or rawlen(left.placeRoles) ~= rawlen(right.placeRoles)
	then
		return false
	end

	for index = 1, rawlen(left.placeRoles) do
		if rawget(left.placeRoles, index) ~= rawget(right.placeRoles, index) then
			return false
		end
	end
	return true
end

local function isAuthenticRegistry(value: unknown): boolean
	return type(value) == "table" and AUTHENTIC_REGISTRIES[value :: any] == true
end

function Registry.get(self: Registry, name: string): Definition?
	if not isAuthenticRegistry(self) or type(name) ~= "string" then
		return nil
	end

	local byName = rawget(self :: any, "_byName") :: { [string]: Definition }
	local definition = rawget(byName, name)
	if definition == nil or AUTHENTIC_DEFINITIONS[definition] ~= true then
		return nil
	end
	return definition
end

function Registry.list(self: Registry): { Definition }
	if not isAuthenticRegistry(self) then
		return EMPTY_DEFINITIONS
	end
	return rawget(self :: any, "_ordered") :: { Definition }
end

function Registry.listForRole(self: Registry, role: RuntimePlaceRole): { Definition }
	if not isAuthenticRegistry(self) or type(role) ~= "string" then
		return EMPTY_DEFINITIONS
	end

	local byRole = rawget(self :: any, "_byRole") :: { [RuntimePlaceRole]: { Definition } }
	local definitions = rawget(byRole :: any, role)
	if type(definitions) ~= "table" then
		return EMPTY_DEFINITIONS
	end
	return definitions :: { Definition }
end

function Registry.count(self: Registry): number
	if not isAuthenticRegistry(self) then
		return 0
	end
	return rawget(self :: any, "_count") :: number
end

function RemoteRegistry.create(value: unknown): Result.Result<Registry, Error>
	local rawDefinitions, arrayError = readDefinitionArray(value)
	if arrayError ~= nil then
		return Result.err(arrayError)
	end

	local ordered: { Definition } = {}
	local firstByName: { [string]: Definition } = {}
	for index = 1, rawlen(rawDefinitions :: { unknown }) do
		local definition, definitionError = validateDefinition(rawget(rawDefinitions :: { unknown }, index), index)
		if definitionError ~= nil then
			return Result.err(definitionError)
		end

		local canonicalDefinition = definition :: Definition
		local existing = rawget(firstByName, canonicalDefinition.name)
		if existing ~= nil then
			if definitionsEqual(existing, canonicalDefinition) then
				return Result.err(
					makeError(
						"DUPLICATE_DEFINITION",
						fieldPath(index, "name"),
						"Remote definition duplicates an earlier definition"
					)
				)
			end
			return Result.err(
				makeError(
					"CONFLICTING_DEFINITION",
					fieldPath(index, "name"),
					"Remote name conflicts with an earlier definition"
				)
			)
		end

		firstByName[canonicalDefinition.name] = canonicalDefinition
		table.insert(ordered, canonicalDefinition)
	end

	table.sort(ordered, function(left: Definition, right: Definition): boolean
		return left.name < right.name
	end)

	local byName: { [string]: Definition } = {}
	local lobby: { Definition } = {}
	local match: { Definition } = {}
	for _, definition in ordered do
		byName[definition.name] = definition
		for _, placeRole in definition.placeRoles do
			if placeRole == "Lobby" then
				table.insert(lobby, definition)
			else
				table.insert(match, definition)
			end
		end
	end

	local frozenOrdered = table.freeze(ordered)
	local byRole: { [RuntimePlaceRole]: { Definition } } = table.freeze({
		Development = frozenOrdered,
		Lobby = table.freeze(lobby),
		Match = table.freeze(match),
	})
	local registry = setmetatable({
		_ordered = frozenOrdered,
		_byName = table.freeze(byName),
		_byRole = byRole,
		_count = rawlen(frozenOrdered),
	}, Registry) :: Registry
	table.freeze(registry)
	AUTHENTIC_REGISTRIES[registry] = true
	return Result.ok(registry)
end

function RemoteRegistry.isRegistry(value: unknown): boolean
	return isAuthenticRegistry(value)
end

table.freeze(Registry)
return table.freeze(RemoteRegistry)
