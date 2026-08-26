export type PlaceRole = "Development" | "Lobby" | "Match"

export type ResolutionErrorCode =
	"INVALID_DECLARED_ROLE"
	| "DEVELOPMENT_ROLE_OUTSIDE_STUDIO"
	| "PLACE_ID_UNCONFIGURED"
	| "INVALID_ACTUAL_PLACE_ID"
	| "PLACE_ID_MISMATCH"

export type ResolutionSuccess = {
	ok: true,
	role: PlaceRole,
	actualPlaceId: number,
	expectedPlaceId: number?,
}

export type ResolutionFailure = {
	ok: false,
	code: ResolutionErrorCode,
	message: string,
}

export type Resolution = ResolutionSuccess | ResolutionFailure

export type ConfigurationSuccess = {
	ok: true,
}

export type ConfigurationFailure = {
	ok: false,
	code: "INVALID_CONFIGURATION",
	message: string,
}

export type ConfigurationResult = ConfigurationSuccess | ConfigurationFailure

local DEVELOPMENT_ROLE: PlaceRole = "Development"
local LOBBY_ROLE: PlaceRole = "Lobby"
local MATCH_ROLE: PlaceRole = "Match"

local VALID_ROLES: { [string]: boolean } = table.freeze({
	[DEVELOPMENT_ROLE] = true,
	[LOBBY_ROLE] = true,
	[MATCH_ROLE] = true,
})

-- False is an intentionally non-numeric sentinel. It cannot be passed to a
-- Roblox API accidentally and becomes nil through getConfiguredPlaceId().
local CONFIGURED_PLACE_IDS: { [string]: number | false } = table.freeze({
	[DEVELOPMENT_ROLE] = false,
	[LOBBY_ROLE] = 100561454756026,
	[MATCH_ROLE] = 136401514513678,
})

local PlaceRoles = {
	ATTRIBUTE_NAME = "ATDPlaceRole",
	DEVELOPMENT_ROLE = DEVELOPMENT_ROLE,
	LOBBY_ROLE = LOBBY_ROLE,
	MATCH_ROLE = MATCH_ROLE,
}

local function isPositiveInteger(value: number): boolean
	return value == value and value > 0 and value < math.huge and value % 1 == 0
end

local function resolutionFailure(code: ResolutionErrorCode, message: string): ResolutionFailure
	return {
		ok = false,
		code = code,
		message = message,
	}
end

local function configurationFailure(message: string): ConfigurationFailure
	return {
		ok = false,
		code = "INVALID_CONFIGURATION",
		message = message,
	}
end

function PlaceRoles.getConfiguredPlaceId(role: PlaceRole): number?
	local configuredPlaceId = CONFIGURED_PLACE_IDS[role]

	if configuredPlaceId == false then
		return nil
	end

	return configuredPlaceId
end

function PlaceRoles.validateConfiguration(): ConfigurationResult
	if CONFIGURED_PLACE_IDS[DEVELOPMENT_ROLE] ~= false then
		return configurationFailure("Development must never have a configured production PlaceId")
	end

	local lobbyPlaceId = CONFIGURED_PLACE_IDS[LOBBY_ROLE]
	if lobbyPlaceId == false or not isPositiveInteger(lobbyPlaceId) then
		return configurationFailure("Lobby must have one positive integer PlaceId")
	end

	local matchPlaceId = CONFIGURED_PLACE_IDS[MATCH_ROLE]
	if matchPlaceId ~= false and not isPositiveInteger(matchPlaceId) then
		return configurationFailure("Match PlaceId must be a positive integer or the unset sentinel")
	end

	return {
		ok = true,
	}
end

function PlaceRoles.resolve(declaredRole: unknown, actualPlaceId: number, isStudio: boolean): Resolution
	if type(declaredRole) ~= "string" or VALID_ROLES[declaredRole] ~= true then
		return resolutionFailure(
			"INVALID_DECLARED_ROLE",
			`Expected ReplicatedStorage attribute '{PlaceRoles.ATTRIBUTE_NAME}' to be Development, Lobby, or Match; received {typeof(
				declaredRole
			)}`
		)
	end

	local role = declaredRole :: PlaceRole

	if role == DEVELOPMENT_ROLE then
		if not isStudio then
			return resolutionFailure(
				"DEVELOPMENT_ROLE_OUTSIDE_STUDIO",
				"The combined Development project is allowed only in Roblox Studio"
			)
		end

		local developmentPlaceId = CONFIGURED_PLACE_IDS[LOBBY_ROLE]
		if developmentPlaceId == false then
			return resolutionFailure("PLACE_ID_UNCONFIGURED", "Development requires the Lobby PlaceId to be configured")
		end

		if not isPositiveInteger(actualPlaceId) then
			return resolutionFailure(
				"INVALID_ACTUAL_PLACE_ID",
				`Development requires the known Lobby place; received invalid PlaceId {actualPlaceId}`
			)
		end

		if actualPlaceId ~= developmentPlaceId then
			return resolutionFailure(
				"PLACE_ID_MISMATCH",
				`Development is paired with Lobby PlaceId {developmentPlaceId}, but booted in {actualPlaceId}`
			)
		end

		return {
			ok = true,
			role = role,
			actualPlaceId = actualPlaceId,
			expectedPlaceId = developmentPlaceId,
		}
	end

	local configuredPlaceId = CONFIGURED_PLACE_IDS[role]
	if configuredPlaceId == false then
		return resolutionFailure(
			"PLACE_ID_UNCONFIGURED",
			`Declared role '{role}' has no configured PlaceId and cannot boot safely`
		)
	end

	if not isPositiveInteger(actualPlaceId) then
		return resolutionFailure(
			"INVALID_ACTUAL_PLACE_ID",
			`Declared role '{role}' requires a published positive integer PlaceId; received {actualPlaceId}`
		)
	end

	if actualPlaceId ~= configuredPlaceId then
		return resolutionFailure(
			"PLACE_ID_MISMATCH",
			`Declared role '{role}' expected PlaceId {configuredPlaceId}, but booted in {actualPlaceId}`
		)
	end

	return {
		ok = true,
		role = role,
		actualPlaceId = actualPlaceId,
		expectedPlaceId = configuredPlaceId,
	}
end

return table.freeze(PlaceRoles)
