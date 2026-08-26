local PlaceRoles = require(script.Parent.Parent.config.PlaceRoles)

export type ExecutionContext = "client" | "server"
export type PlaceRole = PlaceRoles.PlaceRole | "Unresolved"
export type RuntimeEnvironment = "studio" | "production"

export type Context = {
	executionContext: ExecutionContext,
	placeRole: PlaceRole,
	placeId: number,
	isStudio: boolean,
	runtimeEnvironment: RuntimeEnvironment,
}

export type ErrorCode =
	"INVALID_CONTEXT"
	| "INVALID_EXECUTION_CONTEXT"
	| "INVALID_PLACE_ROLE"
	| "INVALID_PLACE_ID"
	| "INVALID_STUDIO_FLAG"

local EnvironmentContext = {}

local VALID_EXECUTION_CONTEXTS: { [string]: boolean } = table.freeze({
	client = true,
	server = true,
})

local VALID_PLACE_ROLES: { [string]: boolean } = table.freeze({
	Unresolved = true,
	[PlaceRoles.DEVELOPMENT_ROLE] = true,
	[PlaceRoles.LOBBY_ROLE] = true,
	[PlaceRoles.MATCH_ROLE] = true,
})

local CONTEXT_REGISTRY = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }

local function fail(code: ErrorCode, message: string)
	error(
		`[ATD][ERROR][context=unknown][role=Unresolved][placeId=unknown][environment=unknown][subsystem=environment][event=construction_rejected][code={code}] {message}`,
		0
	)
end

local function isNonNegativeInteger(value: number): boolean
	return value == value and value >= 0 and value < math.huge and value % 1 == 0
end

function EnvironmentContext.new(
	executionContext: unknown,
	placeRole: unknown,
	placeId: unknown,
	isStudio: unknown
): Context
	if type(executionContext) ~= "string" or VALID_EXECUTION_CONTEXTS[executionContext] ~= true then
		fail("INVALID_EXECUTION_CONTEXT", "Execution context must be 'client' or 'server'")
	end

	if type(placeRole) ~= "string" or VALID_PLACE_ROLES[placeRole] ~= true then
		fail("INVALID_PLACE_ROLE", "Place role must be Unresolved, Development, Lobby, or Match")
	end

	if type(placeId) ~= "number" or not isNonNegativeInteger(placeId) then
		fail("INVALID_PLACE_ID", "PlaceId must be a finite non-negative integer")
	end

	if type(isStudio) ~= "boolean" then
		fail("INVALID_STUDIO_FLAG", "Studio flag must be a boolean")
	end

	local context: Context = table.freeze({
		executionContext = executionContext :: ExecutionContext,
		placeRole = placeRole :: PlaceRole,
		placeId = placeId,
		isStudio = isStudio,
		runtimeEnvironment = if isStudio then "studio" else "production",
	})

	CONTEXT_REGISTRY[context] = true
	return context
end

function EnvironmentContext.withRole(context: Context, placeRole: PlaceRoles.PlaceRole): Context
	if not EnvironmentContext.isContext(context) then
		fail("INVALID_CONTEXT", "withRole requires a genuine EnvironmentContext")
	end

	if type(placeRole) ~= "string" or placeRole == "Unresolved" or VALID_PLACE_ROLES[placeRole] ~= true then
		fail("INVALID_PLACE_ROLE", "Resolved place role must be Development, Lobby, or Match")
	end

	return EnvironmentContext.new(context.executionContext, placeRole, context.placeId, context.isStudio)
end

function EnvironmentContext.isContext(value: unknown): boolean
	return type(value) == "table" and CONTEXT_REGISTRY[value] == true
end

return table.freeze(EnvironmentContext)
