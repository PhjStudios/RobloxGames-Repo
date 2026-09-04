--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local ContentSelection = require(ReplicatedStorage.Shared.config.ContentSelection)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)

export type Selection = {
	mapId: Ids.MapId,
	difficultyId: Ids.DifficultyId,
	overridden: boolean,
}

export type ErrorCode =
	"INVALID_DEPENDENCIES"
	| "STUDIO_ONLY"
	| "ATTRIBUTE_READ_FAILED"
	| "PARTIAL_SELECTION"
	| "INVALID_SELECTION"

export type SelectionError = {
	code: ErrorCode,
	operation: "resolve",
}

export type AttributeReader = (attributeName: string) -> unknown

local ROOT_NAME = "ATDMapTemplates"
local MAP_ATTRIBUTE = "ATDStudioMapId"
local DIFFICULTY_ATTRIBUTE = "ATDStudioDifficultyId"

local DirectStudioContentSelection = {
	ROOT_NAME = ROOT_NAME,
	MAP_ATTRIBUTE = MAP_ATTRIBUTE,
	DIFFICULTY_ATTRIBUTE = DIFFICULTY_ATTRIBUTE,
}

local function failure(code: ErrorCode): Result.Failure<SelectionError>
	return Result.err(table.freeze({ code = code, operation = "resolve" }))
end

local function defaultSelection(): Selection
	return table.freeze({
		mapId = ContentSelection.DEVELOPMENT_MAP_ID :: Ids.MapId,
		difficultyId = ContentSelection.DEVELOPMENT_DIFFICULTY_ID :: Ids.DifficultyId,
		overridden = false,
	})
end

local function supportedPair(
	configuration: ConfigTypes.CoreConfiguration,
	mapId: Ids.MapId,
	difficultyId: Ids.DifficultyId
): boolean
	local map = configuration.maps.byId[mapId]
	local difficulty = configuration.difficulties.byId[difficultyId]
	local schedules = configuration.waves.byMapId[mapId]
	local schedule = if schedules == nil then nil else schedules[difficultyId]
	if map == nil or difficulty == nil or schedule == nil then
		return false
	end
	local supported = false
	for _, candidate in map.supportedDifficultyIds do
		supported = supported or candidate == difficultyId
	end
	return supported
		and (
			(difficulty.kind == "Finite" and schedule.kind == "AuthoredFinite")
			or (difficulty.kind == "Endless" and schedule.kind == "GeneratedEndless")
		)
end

function DirectStudioContentSelection.resolve(
	configurationValue: unknown,
	isStudioValue: unknown,
	attributeReaderValue: unknown
): Result.Result<Selection, SelectionError>
	if type(isStudioValue) ~= "boolean" or not ConfigurationValidator.isValidatedConfiguration(configurationValue) then
		return failure("INVALID_DEPENDENCIES")
	end
	if not isStudioValue then
		-- Direct selection is an explicit local-development capability. Published
		-- jobs must enter through authenticated ticket admission, even when they
		-- are public/VIP servers rather than Roblox-reserved servers.
		return failure("STUDIO_ONLY")
	end
	local configuration = configurationValue :: ConfigTypes.CoreConfiguration
	if
		not supportedPair(
			configuration,
			ContentSelection.DEVELOPMENT_MAP_ID :: Ids.MapId,
			ContentSelection.DEVELOPMENT_DIFFICULTY_ID :: Ids.DifficultyId
		)
	then
		return failure("INVALID_SELECTION")
	end
	if type(attributeReaderValue) ~= "function" then
		return failure("INVALID_DEPENDENCIES")
	end
	local reader = attributeReaderValue :: AttributeReader
	local mapRead, mapValue = pcall(reader, MAP_ATTRIBUTE)
	local difficultyRead, difficultyValue = pcall(reader, DIFFICULTY_ATTRIBUTE)
	if not mapRead or not difficultyRead then
		return failure("ATTRIBUTE_READ_FAILED")
	end
	if mapValue == nil and difficultyValue == nil then
		return Result.ok(defaultSelection())
	end
	if mapValue == nil or difficultyValue == nil then
		return failure("PARTIAL_SELECTION")
	end
	local mapId = Ids.validateMapId(mapValue)
	local difficultyId = Ids.validateDifficultyId(difficultyValue)
	if not mapId.ok or not difficultyId.ok or not supportedPair(configuration, mapId.value, difficultyId.value) then
		return failure("INVALID_SELECTION")
	end
	return Result.ok(table.freeze({
		mapId = mapId.value,
		difficultyId = difficultyId.value,
		overridden = true,
	}))
end

return table.freeze(DirectStudioContentSelection)
