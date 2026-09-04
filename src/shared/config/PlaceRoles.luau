--!strict

export type PlaceRole = "Development" | "Lobby" | "Match"
export type Deployment = "Production" | "Staging"

export type ResolutionErrorCode =
	"INVALID_DECLARED_ROLE"
	| "DEVELOPMENT_ROLE_OUTSIDE_STUDIO"
	| "PLACE_ID_UNCONFIGURED"
	| "INVALID_ACTUAL_GAME_ID"
	| "GAME_ID_UNCONFIGURED"
	| "GAME_ID_MISMATCH"
	| "INVALID_ACTUAL_PLACE_ID"
	| "PLACE_ID_MISMATCH"

export type ResolutionSuccess = {
	ok: true,
	role: PlaceRole,
	deployment: Deployment,
	actualGameId: number,
	expectedGameId: number,
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

type DeploymentConfiguration = {
	gameId: number,
	placeIds: { [string]: number | false },
}

local DEVELOPMENT_ROLE: PlaceRole = "Development"
local LOBBY_ROLE: PlaceRole = "Lobby"
local MATCH_ROLE: PlaceRole = "Match"

local PRODUCTION_DEPLOYMENT: Deployment = "Production"
local STAGING_DEPLOYMENT: Deployment = "Staging"

local VALID_ROLES: { [string]: boolean } = table.freeze({
	[DEVELOPMENT_ROLE] = true,
	[LOBBY_ROLE] = true,
	[MATCH_ROLE] = true,
})

local DEPLOYMENT_ORDER: { Deployment } = table.freeze({
	PRODUCTION_DEPLOYMENT,
	STAGING_DEPLOYMENT,
})

local CONFIGURED_DEPLOYMENTS: { [string]: DeploymentConfiguration } = table.freeze({
	[PRODUCTION_DEPLOYMENT] = table.freeze({
		gameId = 10757629094,
		placeIds = table.freeze({
			[DEVELOPMENT_ROLE] = false,
			[LOBBY_ROLE] = 100561454756026,
			[MATCH_ROLE] = 136401514513678,
		}),
	}),
	[STAGING_DEPLOYMENT] = table.freeze({
		gameId = 10764687717,
		placeIds = table.freeze({
			[DEVELOPMENT_ROLE] = false,
			[LOBBY_ROLE] = 140661668701496,
			[MATCH_ROLE] = 104415140644510,
		}),
	}),
})

local DEPLOYMENT_BY_GAME_ID: { [number]: Deployment } = table.freeze({
	[10757629094] = PRODUCTION_DEPLOYMENT,
	[10764687717] = STAGING_DEPLOYMENT,
})

local PlaceRoles = {
	ATTRIBUTE_NAME = "ATDPlaceRole",
	DEVELOPMENT_ROLE = DEVELOPMENT_ROLE,
	LOBBY_ROLE = LOBBY_ROLE,
	MATCH_ROLE = MATCH_ROLE,
	PRODUCTION_DEPLOYMENT = PRODUCTION_DEPLOYMENT,
	STAGING_DEPLOYMENT = STAGING_DEPLOYMENT,
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

function PlaceRoles.isDeployment(value: unknown): boolean
	return type(value) == "string" and CONFIGURED_DEPLOYMENTS[value :: string] ~= nil
end

function PlaceRoles.getConfiguredGameId(deployment: Deployment): number?
	local configuration = CONFIGURED_DEPLOYMENTS[deployment]
	return if configuration == nil then nil else configuration.gameId
end

function PlaceRoles.getConfiguredPlaceId(deployment: Deployment, role: PlaceRole): number?
	local configuration = CONFIGURED_DEPLOYMENTS[deployment]
	if configuration == nil then
		return nil
	end

	local configuredPlaceId = configuration.placeIds[role]
	if configuredPlaceId == false then
		return nil
	end

	return configuredPlaceId
end

function PlaceRoles.validateConfiguration(): ConfigurationResult
	local seenGameIds: { [number]: boolean } = {}
	local seenPlaceIds: { [number]: boolean } = {}

	for _, deployment in DEPLOYMENT_ORDER do
		local configuration = CONFIGURED_DEPLOYMENTS[deployment]
		if configuration == nil or not isPositiveInteger(configuration.gameId) then
			return configurationFailure(`{deployment} must have one positive integer GameId`)
		end
		if seenGameIds[configuration.gameId] then
			return configurationFailure("Published deployments must have distinct GameIds")
		end
		seenGameIds[configuration.gameId] = true

		if configuration.placeIds[DEVELOPMENT_ROLE] ~= false then
			return configurationFailure(`{deployment} Development must not have an independent PlaceId`)
		end

		for _, role in { LOBBY_ROLE, MATCH_ROLE } do
			local placeId = configuration.placeIds[role]
			if placeId == false or not isPositiveInteger(placeId) then
				return configurationFailure(`{deployment} {role} must have one positive integer PlaceId`)
			end
			if seenPlaceIds[placeId] then
				return configurationFailure("Published place roles must have globally distinct PlaceIds")
			end
			seenPlaceIds[placeId] = true
		end

		if DEPLOYMENT_BY_GAME_ID[configuration.gameId] ~= deployment then
			return configurationFailure(`{deployment} GameId lookup is inconsistent`)
		end
	end

	return {
		ok = true,
	}
end

function PlaceRoles.resolve(
	declaredRole: unknown,
	actualGameIdValue: unknown,
	actualPlaceIdValue: unknown,
	isStudio: boolean
): Resolution
	if type(declaredRole) ~= "string" or VALID_ROLES[declaredRole] ~= true then
		return resolutionFailure(
			"INVALID_DECLARED_ROLE",
			`Expected ReplicatedStorage attribute '{PlaceRoles.ATTRIBUTE_NAME}' to be Development, Lobby, or Match; received {typeof(
				declaredRole
			)}`
		)
	end

	if type(actualGameIdValue) ~= "number" or not isPositiveInteger(actualGameIdValue) then
		return resolutionFailure(
			"INVALID_ACTUAL_GAME_ID",
			`Place-role resolution requires a published positive integer GameId; received {typeof(actualGameIdValue)}`
		)
	end

	local actualGameId = actualGameIdValue :: number
	local deployment = DEPLOYMENT_BY_GAME_ID[actualGameId]
	if deployment == nil then
		return resolutionFailure("GAME_ID_UNCONFIGURED", "Observed GameId is not configured for a published deployment")
	end

	local role = declaredRole :: PlaceRole
	local expectedDeployment = deployment
	if role == DEVELOPMENT_ROLE then
		if not isStudio then
			return resolutionFailure(
				"DEVELOPMENT_ROLE_OUTSIDE_STUDIO",
				"The combined Development project is allowed only in Roblox Studio"
			)
		end

		expectedDeployment = PRODUCTION_DEPLOYMENT
		if deployment ~= expectedDeployment then
			return resolutionFailure("GAME_ID_MISMATCH", "Development is paired only with the Production deployment")
		end
	end

	local configuration = CONFIGURED_DEPLOYMENTS[expectedDeployment]
	local expectedPlaceRole = if role == DEVELOPMENT_ROLE then LOBBY_ROLE else role
	local configuredPlaceId = configuration.placeIds[expectedPlaceRole]
	if configuredPlaceId == false then
		return resolutionFailure(
			"PLACE_ID_UNCONFIGURED",
			`Declared role '{role}' has no configured PlaceId and cannot boot safely`
		)
	end

	if type(actualPlaceIdValue) ~= "number" or not isPositiveInteger(actualPlaceIdValue) then
		return resolutionFailure(
			"INVALID_ACTUAL_PLACE_ID",
			`Declared role '{role}' requires a published positive integer PlaceId; received {typeof(actualPlaceIdValue)}`
		)
	end

	local actualPlaceId = actualPlaceIdValue :: number
	if actualPlaceId ~= configuredPlaceId then
		return resolutionFailure(
			"PLACE_ID_MISMATCH",
			`Declared role '{role}' does not match the configured deployment PlaceId`
		)
	end

	return {
		ok = true,
		role = role,
		deployment = expectedDeployment,
		actualGameId = actualGameId,
		expectedGameId = configuration.gameId,
		actualPlaceId = actualPlaceId,
		expectedPlaceId = configuredPlaceId,
	}
end

return table.freeze(PlaceRoles)
