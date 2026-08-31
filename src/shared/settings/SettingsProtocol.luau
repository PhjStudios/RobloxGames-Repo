--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type Settings = {
	version: number,
	masterVolume: number,
	musicVolume: number,
	sfxVolume: number,
	uiVolume: number,
	cameraShakeIntensity: number,
	damageNumbersEnabled: boolean,
	enemyHealthBarsEnabled: boolean,
	otherPlayerEffectsEnabled: boolean,
	lowDetailEnabled: boolean,
	reducedMotionEnabled: boolean,
	towerRangeEnabled: boolean,
	uiScale: number,
}

export type UpdateIntent = Settings & {
	transactionId: string,
	expectedRevision: number,
}

export type UpdateReceipt = {
	transactionId: string,
	revision: number,
	changed: boolean,
	settings: Settings,
}

local SETTINGS_FIELDS: { [string]: any } = {
	version = PayloadValidation.integer(2, 2),
	masterVolume = PayloadValidation.number(0, 1),
	musicVolume = PayloadValidation.number(0, 1),
	sfxVolume = PayloadValidation.number(0, 1),
	uiVolume = PayloadValidation.number(0, 1),
	cameraShakeIntensity = PayloadValidation.number(0, 1),
	damageNumbersEnabled = PayloadValidation.boolean(),
	enemyHealthBarsEnabled = PayloadValidation.boolean(),
	otherPlayerEffectsEnabled = PayloadValidation.boolean(),
	lowDetailEnabled = PayloadValidation.boolean(),
	reducedMotionEnabled = PayloadValidation.boolean(),
	towerRangeEnabled = PayloadValidation.boolean(),
	uiScale = PayloadValidation.number(0.75, 1.25),
}

local SETTINGS = PayloadValidation.record(SETTINGS_FIELDS)

local updateFields = table.clone(SETTINGS_FIELDS)
updateFields.transactionId = PayloadValidation.id("transaction")
updateFields.expectedRevision = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)

local UPDATE_INTENT = PayloadValidation.record(updateFields)
local UPDATE_RECEIPT = PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	revision = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER),
	changed = PayloadValidation.boolean(),
	settings = SETTINGS,
})

local SettingsProtocol = {
	SettingsValidator = SETTINGS,
	SettingsSchema = PayloadValidation.schema(SETTINGS),
	UpdateIntentSchema = PayloadValidation.schema(UPDATE_INTENT),
	UpdateReceiptSchema = PayloadValidation.schema(UPDATE_RECEIPT),
}

local function failure(path: { Validation.PathSegment }, message: string)
	return Result.err(Validation.issue("INVALID_REFERENCE", path, message))
end

function SettingsProtocol.validateUpdateReceipt(value: unknown): Result.Result<UpdateReceipt, Validation.Issue>
	local result = SettingsProtocol.UpdateReceiptSchema:validate(value)
	if not result.ok then
		return Result.err(result.error)
	end
	local receipt = result.value :: UpdateReceipt
	if receipt.settings.version ~= 2 then
		return failure({ "payload", "settings", "version" }, "Settings receipt version is unsupported")
	end
	return Result.ok(receipt)
end

return table.freeze(SettingsProtocol)
