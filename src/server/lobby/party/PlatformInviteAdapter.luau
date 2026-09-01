--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local PartyProtocol = require(ReplicatedStorage.Shared.party.PartyProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type Status = "Prompted" | "Unavailable" | "Denied"
export type LaunchHint = {
	version: number,
	inviterUserId: number,
	partyIntentId: string,
}
export type Dependencies = {
	canPrompt: (Player) -> unknown,
	prompt: (Player, string) -> unknown,
}
export type ErrorCode = "INVALID_DEPENDENCIES" | "INVALID_PLAYER" | "INVALID_HINT" | "UNAVAILABLE"
export type AdapterError = { code: ErrorCode, operation: string }

type AdapterData = {
	dependencies: Dependencies,
}

local Methods = {}
Methods.__index = Methods
export type Adapter = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: AdapterData }
local VERSION = 1
local PREFIX = "atd-party-v1|"
local MAX_LAUNCH_DATA_BYTES = 160

local PlatformInviteAdapter = {
	VERSION = VERSION,
	MAX_LAUNCH_DATA_BYTES = MAX_LAUNCH_DATA_BYTES,
}

local function failure<T>(code: ErrorCode, operation: string): Result.Failure<AdapterError>
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): AdapterData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_PLATFORM_INVITE_ADAPTER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and Validation.isSafeInteger(value) and (value :: number) > 0
end

local function validPlayer(value: unknown): boolean
	if typeof(value) ~= "Instance" then
		return false
	end
	local succeeded, valid = pcall(function(): boolean
		return (value :: Instance):IsA("Player") and validUserId((value :: Player).UserId)
	end)
	return succeeded and valid
end

function PlatformInviteAdapter.buildLaunchData(
	inviterUserIdValue: unknown,
	partyIntentIdValue: unknown
): Result.Result<string, AdapterError>
	if not validUserId(inviterUserIdValue) or not PartyProtocol.isInvitationId(partyIntentIdValue) then
		return failure("INVALID_HINT", "buildLaunchData")
	end
	local value = `{PREFIX}{inviterUserIdValue}|{partyIntentIdValue}`
	if #value > MAX_LAUNCH_DATA_BYTES then
		return failure("INVALID_HINT", "buildLaunchData")
	end
	return Result.ok(value)
end

function PlatformInviteAdapter.parseLaunchData(value: unknown): Result.Result<LaunchHint, AdapterError>
	if type(value) ~= "string" or #value < #PREFIX + 3 or #value > MAX_LAUNCH_DATA_BYTES then
		return failure("INVALID_HINT", "parseLaunchData")
	end
	if string.sub(value, 1, #PREFIX) ~= PREFIX then
		return failure("INVALID_HINT", "parseLaunchData")
	end
	local separator = string.find(value, "|", #PREFIX + 1, true)
	if separator == nil then
		return failure("INVALID_HINT", "parseLaunchData")
	end
	local userIdText = string.sub(value, #PREFIX + 1, separator - 1)
	if #userIdText < 1 or #userIdText > 16 or string.match(userIdText, "^%d+$") == nil then
		return failure("INVALID_HINT", "parseLaunchData")
	end
	local inviterUserId = tonumber(userIdText)
	local intentId = string.sub(value, separator + 1)
	if not validUserId(inviterUserId) or not PartyProtocol.isInvitationId(intentId) then
		return failure("INVALID_HINT", "parseLaunchData")
	end
	return Result.ok(table.freeze({
		version = VERSION,
		inviterUserId = inviterUserId :: number,
		partyIntentId = intentId,
	}))
end

function Methods.prompt(
	self: Adapter,
	playerValue: unknown,
	inviterUserIdValue: unknown,
	partyIntentIdValue: unknown
): Result.Result<Status, AdapterError>
	local data = requireData(self)
	if not validPlayer(playerValue) then
		return failure("INVALID_PLAYER", "prompt")
	end
	local launchData = PlatformInviteAdapter.buildLaunchData(inviterUserIdValue, partyIntentIdValue)
	if not launchData.ok then
		return failure("INVALID_HINT", "prompt")
	end
	local canCall, canPromptValue = pcall(data.dependencies.canPrompt, playerValue :: Player)
	if not canCall then
		return Result.ok("Unavailable")
	elseif canPromptValue ~= true then
		return Result.ok(if canPromptValue == false then "Denied" else "Unavailable")
	end
	local prompted, promptValue = pcall(data.dependencies.prompt, playerValue :: Player, launchData.value)
	if not prompted then
		return Result.ok("Unavailable")
	end
	if promptValue == false then
		return Result.ok("Denied")
	end
	return Result.ok("Prompted")
end

function PlatformInviteAdapter.new(dependenciesValue: unknown): Result.Result<Adapter, AdapterError>
	if
		type(dependenciesValue) ~= "table"
		or getmetatable(dependenciesValue :: any) ~= nil
		or type((dependenciesValue :: any).canPrompt) ~= "function"
		or type((dependenciesValue :: any).prompt) ~= "function"
	then
		return failure("INVALID_DEPENDENCIES", "new")
	end
	local adapter = setmetatable({}, Methods) :: Adapter
	table.freeze(adapter)
	DATA[adapter] = { dependencies = dependenciesValue :: Dependencies }
	return Result.ok(adapter)
end

function PlatformInviteAdapter.newProduction(): Result.Result<Adapter, AdapterError>
	return PlatformInviteAdapter.new({
		canPrompt = function(player: Player): unknown
			return SocialService:CanSendGameInviteAsync(player)
		end,
		prompt = function(player: Player, launchData: string): unknown
			local options = Instance.new("ExperienceInviteOptions")
			options.LaunchData = launchData
			local succeeded, result = pcall(function(): unknown
				return SocialService:PromptGameInvite(player, options)
			end)
			options:Destroy()
			if not succeeded then
				error(result, 0)
			end
			return true
		end,
	})
end

table.freeze(Methods)
return table.freeze(PlatformInviteAdapter)
