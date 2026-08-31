--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsProtocol = require(ReplicatedStorage.Shared.settings.SettingsProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type ProfileOwner = {
	getState: (self: ProfileOwner, userId: number) -> unknown,
	read: (self: ProfileOwner, userId: number) -> unknown,
	transact: (
		self: ProfileOwner,
		userId: number,
		transactionId: string,
		expectedRevision: number,
		kind: string,
		fingerprint: string,
		callback: (profile: any) -> unknown
	) -> unknown,
}

export type ErrorCode =
	"INVALID_DEPENDENCIES"
	| "INVALID_USER_ID"
	| "INVALID_INTENT"
	| "NOT_READY"
	| "STALE_REVISION"
	| "TRANSACTION_CONFLICT"
	| "PROFILE_INVALID"
	| "REVISION_EXHAUSTED"
	| "CALLBACK_FAILED"
	| "UNAVAILABLE"

export type ServiceError = { code: ErrorCode }

type ServiceData = { profileOwner: ProfileOwner }

local Methods = {}
Methods.__index = Methods

export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local SettingsService = {}

local function failure<T>(code: ErrorCode): Result.Failure<ServiceError>
	return Result.err(table.freeze({ code = code }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_SETTINGS_SERVICE][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validUserId(value: unknown): boolean
	return type(value) == "number" and value > 0 and Validation.isSafeInteger(value :: number)
end

local function callNonYielding(callback: (...any) -> any, ...: any): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed or coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function ownerError(value: unknown): ErrorCode
	local code = if type(value) == "table" then rawget(value :: any, "code") else nil
	if code == "NOT_READY" or code == "PROFILE_NOT_READY" then
		return "NOT_READY"
	elseif code == "STALE" or code == "STALE_REVISION" then
		return "STALE_REVISION"
	elseif code == "RECEIPT_CONFLICT" or code == "TRANSACTION_CONFLICT" then
		return "TRANSACTION_CONFLICT"
	elseif code == "PROFILE_INVALID" then
		return "PROFILE_INVALID"
	end
	return "UNAVAILABLE"
end

local function settingsFromProfile(profile: any): SettingsProtocol.Settings?
	local rawSettings = if type(profile) == "table" then rawget(profile, "settings") else nil
	local validated = SettingsProtocol.SettingsSchema:validate(rawSettings)
	return if validated.ok then validated.value :: SettingsProtocol.Settings else nil
end

function Methods.getSettings(
	self: Service,
	userIdValue: unknown
): Result.Result<SettingsProtocol.Settings, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID")
	end
	local userId = userIdValue :: number
	local stateCalled, state = callNonYielding(data.profileOwner.getState, data.profileOwner, userId)
	if not stateCalled or state ~= "Ready" then
		return failure("NOT_READY")
	end
	local called, readResult = callNonYielding(data.profileOwner.read, data.profileOwner, userId)
	if not called or type(readResult) ~= "table" or (readResult :: any).ok ~= true then
		return failure("UNAVAILABLE")
	end
	local settings = settingsFromProfile((readResult :: any).value)
	return if settings == nil then failure("PROFILE_INVALID") else Result.ok(settings)
end

function Methods.update(
	self: Service,
	userIdValue: unknown,
	intentValue: unknown
): Result.Result<SettingsProtocol.UpdateReceipt, ServiceError>
	local data = requireData(self)
	if not validUserId(userIdValue) then
		return failure("INVALID_USER_ID")
	end
	local validated = SettingsProtocol.UpdateIntentSchema:validate(intentValue)
	if not validated.ok then
		return failure("INVALID_INTENT")
	end
	local intent = validated.value :: SettingsProtocol.UpdateIntent
	if intent.expectedRevision >= Validation.MAX_SAFE_INTEGER then
		return failure("REVISION_EXHAUSTED")
	end
	local fingerprint = table.concat({
		"settings-v2",
		tostring(intent.masterVolume),
		tostring(intent.musicVolume),
		tostring(intent.sfxVolume),
		tostring(intent.uiVolume),
		tostring(intent.cameraShakeIntensity),
		tostring(intent.damageNumbersEnabled),
		tostring(intent.enemyHealthBarsEnabled),
		tostring(intent.otherPlayerEffectsEnabled),
		tostring(intent.lowDetailEnabled),
		tostring(intent.reducedMotionEnabled),
		tostring(intent.towerRangeEnabled),
		tostring(intent.uiScale),
	}, "|")
	local called, transaction = callNonYielding(
		data.profileOwner.transact,
		data.profileOwner,
		userIdValue :: number,
		intent.transactionId,
		intent.expectedRevision,
		"SettingsUpdate",
		fingerprint,
		function(profile: any): unknown
			local previous = settingsFromProfile(profile)
			if previous == nil then
				return failure("PROFILE_INVALID")
			end
			local nextSettings: SettingsProtocol.Settings = {
				version = intent.version,
				masterVolume = intent.masterVolume,
				musicVolume = intent.musicVolume,
				sfxVolume = intent.sfxVolume,
				uiVolume = intent.uiVolume,
				cameraShakeIntensity = intent.cameraShakeIntensity,
				damageNumbersEnabled = intent.damageNumbersEnabled,
				enemyHealthBarsEnabled = intent.enemyHealthBarsEnabled,
				otherPlayerEffectsEnabled = intent.otherPlayerEffectsEnabled,
				lowDetailEnabled = intent.lowDetailEnabled,
				reducedMotionEnabled = intent.reducedMotionEnabled,
				towerRangeEnabled = intent.towerRangeEnabled,
				uiScale = intent.uiScale,
			}
			local changed = false
			for key, value in nextSettings do
				if (previous :: any)[key] ~= value then
					changed = true
					break
				end
			end
			profile.settings = nextSettings
			return Result.ok(table.freeze({
				resultCode = if changed then "SETTINGS_CHANGED" else "SETTINGS_UNCHANGED",
				goldBalance = rawget(profile, "gold"),
				unitIds = table.freeze({}),
				towerIds = table.freeze({}),
				newFlags = table.freeze({}),
				pityCount = 0,
			}))
		end
	)
	if not called or type(transaction) ~= "table" then
		return failure("CALLBACK_FAILED")
	end
	local result = transaction :: any
	if result.ok ~= true then
		return failure(ownerError(result.error))
	end
	local ownerValue = result.value
	if type(ownerValue) ~= "table" then
		return failure("UNAVAILABLE")
	end
	local stored = rawget(ownerValue, "result")
	local profile = rawget(ownerValue, "profile")
	local revision = rawget(ownerValue, "profileRevision")
	local resultCode = if type(stored) == "table" then rawget(stored, "resultCode") else nil
	local settings = settingsFromProfile(profile)
	if
		(resultCode ~= "SETTINGS_CHANGED" and resultCode ~= "SETTINGS_UNCHANGED")
		or type(revision) ~= "number"
		or not Validation.isSafeInteger(revision)
		or revision < 1
		or settings == nil
	then
		return failure("UNAVAILABLE")
	end
	local value: SettingsProtocol.UpdateReceipt = table.freeze({
		transactionId = intent.transactionId,
		revision = revision :: number,
		changed = resultCode == "SETTINGS_CHANGED",
		settings = settings,
	})
	local receipt = SettingsProtocol.validateUpdateReceipt(value)
	return if receipt.ok then Result.ok(receipt.value) else failure("UNAVAILABLE")
end

function SettingsService.new(profileOwnerValue: unknown): Result.Result<Service, ServiceError>
	if
		type(profileOwnerValue) ~= "table"
		or type((profileOwnerValue :: any).getState) ~= "function"
		or type((profileOwnerValue :: any).read) ~= "function"
		or type((profileOwnerValue :: any).transact) ~= "function"
	then
		return failure("INVALID_DEPENDENCIES")
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = { profileOwner = profileOwnerValue :: ProfileOwner }
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(SettingsService)
