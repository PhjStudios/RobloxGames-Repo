--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local ContentSelection = require(ReplicatedStorage.Shared.config.ContentSelection)
local MatchLoadoutProtocol = require(ReplicatedStorage.Shared.match.MatchLoadoutProtocol)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type ErrorCode = "INVALID_USER_ID" | "INVALID_CONFIGURATION" | "INVALID_LOADOUT"
export type LoadoutError = { code: ErrorCode }

local DirectStudioParticipantLoadout = {}

local function failure(code: ErrorCode): Result.Failure<LoadoutError>
	return Result.err(table.freeze({ code = code }))
end

local function validStudioUserId(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value :: number) and value < 0
end

-- Production and ticket loadouts deliberately remain positive-only. This
-- server-only adapter borrows the complete authenticated validator with a
-- temporary positive identity, then restores the Studio test player's exact
-- negative UserId for runtime ownership and client comparisons.
function DirectStudioParticipantLoadout.validate(
	value: unknown,
	configuration: ConfigTypes.CoreConfiguration
): Result.Result<MatchLoadoutProtocol.Snapshot, LoadoutError>
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return failure("INVALID_LOADOUT")
	end
	local userId = rawget(value :: any, "userId")
	if not validStudioUserId(userId) then
		return failure("INVALID_USER_ID")
	end
	local candidate = table.clone(value :: any)
	candidate.userId = 1
	local validated = MatchLoadoutProtocol.validate(candidate, configuration)
	if not validated.ok then
		return failure("INVALID_LOADOUT")
	end
	local snapshot = table.clone(validated.value)
	snapshot.userId = userId :: number
	return Result.ok(table.freeze(snapshot) :: MatchLoadoutProtocol.Snapshot)
end

function DirectStudioParticipantLoadout.create(
	userIdValue: unknown,
	configurationValue: unknown
): Result.Result<MatchLoadoutProtocol.Snapshot, LoadoutError>
	if not validStudioUserId(userIdValue) then
		return failure("INVALID_USER_ID")
	end
	if not ConfigurationValidator.isValidatedConfiguration(configurationValue) then
		return failure("INVALID_CONFIGURATION")
	end
	local configuration = configurationValue :: ConfigTypes.CoreConfiguration
	if #ContentSelection.STARTER_TOWER_IDS ~= #ContentSelection.STARTER_UNIT_IDS then
		return failure("INVALID_CONFIGURATION")
	end
	local slots = table.create(#ContentSelection.STARTER_TOWER_IDS)
	for index, towerId in ContentSelection.STARTER_TOWER_IDS do
		if configuration.towers.byId[towerId] == nil then
			return failure("INVALID_CONFIGURATION")
		end
		slots[index] = {
			slot = index,
			unitId = ContentSelection.STARTER_UNIT_IDS[index],
			towerId = towerId,
		}
	end
	return DirectStudioParticipantLoadout.validate({
		userId = userIdValue,
		revision = 1,
		slots = slots,
		settings = configuration.defaultSettings,
	}, configuration)
end

return table.freeze(DirectStudioParticipantLoadout)
