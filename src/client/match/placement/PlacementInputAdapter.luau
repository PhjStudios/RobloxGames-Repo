--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type InputFamily = "Desktop" | "Touch" | "Gamepad"
export type ActionKind = "Position" | "Confirm" | "Cancel" | "Rotate" | "SelectSlot" | "CycleSlot"
export type Action = {
	kind: ActionKind,
	source: InputFamily,
	screenPosition: Vector2?,
	rotationDegrees: number?,
	slot: number?,
	direction: number?,
}

export type Metrics = {
	preferredInput: InputFamily,
	activeTouchCount: number,
	gestureTouchCount: number,
	reticle: Vector2,
	viewport: Vector2,
	actionCount: number,
	positionActionCount: number,
	confirmActionCount: number,
	cleaned: boolean,
}

export type ErrorCode = "INVALID_ARGUMENT" | "UNAVAILABLE" | "TOUCH_LIMIT" | "CLEANED_UP"
export type Error = {
	code: ErrorCode,
}

type TouchState = {
	start: Vector2,
	last: Vector2,
	blocked: boolean,
	gesture: boolean,
}

type AdapterData = {
	preferredInput: InputFamily,
	viewport: Vector2,
	reticle: Vector2,
	touches: { [number]: TouchState },
	touchCount: number,
	cleaned: boolean,
	actionCount: number,
	positionActionCount: number,
	confirmActionCount: number,
}

local AdapterMethods = {}
AdapterMethods.__index = AdapterMethods

export type Adapter = typeof(setmetatable({} :: {}, AdapterMethods))
export type AdapterResult = Result.Result<Adapter, Error>

local ADAPTER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: AdapterData }

local MAX_ACTIVE_TOUCHES = 4
local MAX_TOUCH_ID = 64
local TAP_MOVEMENT_PIXELS = 12
local GAMEPAD_DEADZONE = 0.15
local GAMEPAD_RETICLE_SPEED = 720
local MAX_GAMEPAD_STEP_SECONDS = 0.1
local ROTATION_STEP_DEGREES = 15
local DEFAULT_VIEWPORT = Vector2.new(1280, 720)

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_ARGUMENT = table.freeze({ code = "INVALID_ARGUMENT" :: "INVALID_ARGUMENT" }),
	UNAVAILABLE = table.freeze({ code = "UNAVAILABLE" :: "UNAVAILABLE" }),
	TOUCH_LIMIT = table.freeze({ code = "TOUCH_LIMIT" :: "TOUCH_LIMIT" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local PlacementInputAdapter = {
	MAX_ACTIVE_TOUCHES = MAX_ACTIVE_TOUCHES,
	TAP_MOVEMENT_PIXELS = TAP_MOVEMENT_PIXELS,
	GAMEPAD_DEADZONE = GAMEPAD_DEADZONE,
	GAMEPAD_RETICLE_SPEED = GAMEPAD_RETICLE_SPEED,
	MAX_GAMEPAD_STEP_SECONDS = MAX_GAMEPAD_STEP_SECONDS,
	ROTATION_STEP_DEGREES = ROTATION_STEP_DEGREES,
}

local function failure(code: ErrorCode)
	return Result.err(ERRORS[code])
end

local function requireData(value: unknown): AdapterData
	if type(value) ~= "table" then
		error("[ATD_PLACEMENT_INPUT_ADAPTER][code=INVALID_CONTEXT]", 0)
	end
	local data = ADAPTER_DATA[value :: any]
	if data == nil then
		error("[ATD_PLACEMENT_INPUT_ADAPTER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function validScreenPosition(value: unknown): boolean
	if typeof(value) ~= "Vector2" then
		return false
	end
	local position = value :: Vector2
	return Validation.isFiniteNumber(position.X)
		and Validation.isFiniteNumber(position.Y)
		and math.abs(position.X) <= 100_000
		and math.abs(position.Y) <= 100_000
end

local function validTouchId(value: unknown): boolean
	return type(value) == "number"
		and Validation.isSafeInteger(value :: number)
		and value >= 1
		and value <= MAX_TOUCH_ID
end

local function makeAction(data: AdapterData, kind: ActionKind, source: InputFamily, fields: any?): Action
	local selected = fields or {}
	local action: Action = table.freeze({
		kind = kind,
		source = source,
		screenPosition = selected.screenPosition,
		rotationDegrees = selected.rotationDegrees,
		slot = selected.slot,
		direction = selected.direction,
	})
	data.actionCount += 1
	if kind == "Position" then
		data.positionActionCount += 1
	elseif kind == "Confirm" then
		data.confirmActionCount += 1
	end
	return action
end

local function clampReticle(position: Vector2, viewport: Vector2): Vector2
	return Vector2.new(math.clamp(position.X, 0, viewport.X), math.clamp(position.Y, 0, viewport.Y))
end

function AdapterMethods.setPreferredInput(self: Adapter, value: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if value ~= "Desktop" and value ~= "Touch" and value ~= "Gamepad" then
		return failure("INVALID_ARGUMENT")
	end
	local changed = data.preferredInput ~= value
	data.preferredInput = value :: InputFamily
	return Result.ok(changed)
end

function AdapterMethods.setViewport(self: Adapter, value: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not validScreenPosition(value) then
		return failure("INVALID_ARGUMENT")
	end
	local viewport = value :: Vector2
	if viewport.X < 1 or viewport.Y < 1 or viewport.X > 16_384 or viewport.Y > 16_384 then
		return failure("INVALID_ARGUMENT")
	end
	data.viewport = viewport
	data.reticle = clampReticle(data.reticle, viewport)
	return Result.ok(data.reticle)
end

function AdapterMethods.desktopPointer(self: Adapter, value: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not validScreenPosition(value) then
		return failure("INVALID_ARGUMENT")
	end
	if data.preferredInput ~= "Desktop" then
		return failure("UNAVAILABLE")
	end
	return Result.ok(makeAction(data, "Position", "Desktop", { screenPosition = value }))
end

function AdapterMethods.touchBegan(
	self: Adapter,
	touchIdValue: unknown,
	positionValue: unknown,
	processedValue: unknown
)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if
		not validTouchId(touchIdValue)
		or not validScreenPosition(positionValue)
		or type(processedValue) ~= "boolean"
	then
		return failure("INVALID_ARGUMENT")
	end
	local touchId = touchIdValue :: number
	if data.touches[touchId] ~= nil then
		return failure("INVALID_ARGUMENT")
	end
	if data.touchCount >= MAX_ACTIVE_TOUCHES then
		return failure("TOUCH_LIMIT")
	end
	local position = positionValue :: Vector2
	data.touches[touchId] = {
		start = position,
		last = position,
		blocked = processedValue :: boolean or data.preferredInput ~= "Touch",
		gesture = false,
	}
	data.touchCount += 1
	if data.touchCount > 1 then
		for _, touch in data.touches do
			touch.gesture = true
		end
	end
	return Result.ok(true)
end

function AdapterMethods.touchChanged(self: Adapter, touchIdValue: unknown, positionValue: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not validTouchId(touchIdValue) or not validScreenPosition(positionValue) then
		return failure("INVALID_ARGUMENT")
	end
	local touch = data.touches[touchIdValue :: number]
	if touch == nil then
		return failure("UNAVAILABLE")
	end
	local position = positionValue :: Vector2
	touch.last = position
	if (position - touch.start).Magnitude > TAP_MOVEMENT_PIXELS then
		touch.gesture = true
	end
	return Result.ok(true)
end

local function endTouch(data: AdapterData, touchId: number, cancelled: boolean): Action?
	local touch = data.touches[touchId]
	if touch == nil then
		return nil
	end
	data.touches[touchId] = nil
	data.touchCount -= 1
	if cancelled or touch.blocked or touch.gesture or data.touchCount ~= 0 or data.preferredInput ~= "Touch" then
		return nil
	end
	return makeAction(data, "Position", "Touch", { screenPosition = touch.last })
end

function AdapterMethods.touchEnded(self: Adapter, touchIdValue: unknown, positionValue: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not validTouchId(touchIdValue) or not validScreenPosition(positionValue) then
		return failure("INVALID_ARGUMENT")
	end
	local touch = data.touches[touchIdValue :: number]
	if touch == nil then
		return failure("UNAVAILABLE")
	end
	touch.last = positionValue :: Vector2
	if (touch.last - touch.start).Magnitude > TAP_MOVEMENT_PIXELS then
		touch.gesture = true
	end
	return Result.ok(endTouch(data, touchIdValue :: number, false))
end

function AdapterMethods.touchCancelled(self: Adapter, touchIdValue: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not validTouchId(touchIdValue) or data.touches[touchIdValue :: number] == nil then
		return failure("INVALID_ARGUMENT")
	end
	endTouch(data, touchIdValue :: number, true)
	return Result.ok(true)
end

function AdapterMethods.confirm(self: Adapter, sourceValue: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if sourceValue ~= "Desktop" and sourceValue ~= "Touch" and sourceValue ~= "Gamepad" then
		return failure("INVALID_ARGUMENT")
	end
	if sourceValue ~= data.preferredInput then
		return failure("UNAVAILABLE")
	end
	return Result.ok(makeAction(data, "Confirm", sourceValue :: InputFamily))
end

function AdapterMethods.cancel(self: Adapter, sourceValue: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if sourceValue ~= "Desktop" and sourceValue ~= "Touch" and sourceValue ~= "Gamepad" then
		return failure("INVALID_ARGUMENT")
	end
	if sourceValue ~= data.preferredInput then
		return failure("UNAVAILABLE")
	end
	return Result.ok(makeAction(data, "Cancel", sourceValue :: InputFamily))
end

function AdapterMethods.rotate(self: Adapter, sourceValue: unknown, directionValue: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if
		(sourceValue ~= "Desktop" and sourceValue ~= "Touch" and sourceValue ~= "Gamepad")
		or (directionValue ~= -1 and directionValue ~= 1)
	then
		return failure("INVALID_ARGUMENT")
	end
	if sourceValue ~= data.preferredInput then
		return failure("UNAVAILABLE")
	end
	return Result.ok(makeAction(data, "Rotate", sourceValue :: InputFamily, {
		rotationDegrees = (directionValue :: number) * ROTATION_STEP_DEGREES,
	}))
end

function AdapterMethods.selectSlot(self: Adapter, sourceValue: unknown, slotValue: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if
		(sourceValue ~= "Desktop" and sourceValue ~= "Touch" and sourceValue ~= "Gamepad")
		or type(slotValue) ~= "number"
		or not Validation.isSafeInteger(slotValue :: number)
		or slotValue < 1
		or slotValue > 5
	then
		return failure("INVALID_ARGUMENT")
	end
	return Result.ok(makeAction(data, "SelectSlot", sourceValue :: InputFamily, { slot = slotValue }))
end

function AdapterMethods.cycleSlot(self: Adapter, directionValue: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if directionValue ~= -1 and directionValue ~= 1 then
		return failure("INVALID_ARGUMENT")
	end
	if data.preferredInput ~= "Gamepad" then
		return failure("UNAVAILABLE")
	end
	return Result.ok(makeAction(data, "CycleSlot", "Gamepad", { direction = directionValue }))
end

function AdapterMethods.gamepadStep(self: Adapter, axisValue: unknown, deltaSecondsValue: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if
		type(deltaSecondsValue) ~= "number"
		or not Validation.isFiniteNumber(deltaSecondsValue :: number)
		or deltaSecondsValue < 0
		or deltaSecondsValue > MAX_GAMEPAD_STEP_SECONDS
		or not validScreenPosition(axisValue)
	then
		return failure("INVALID_ARGUMENT")
	end
	if data.preferredInput ~= "Gamepad" then
		return failure("UNAVAILABLE")
	end
	local axis = axisValue :: Vector2
	local magnitude = math.min(axis.Magnitude, 1)
	if magnitude <= GAMEPAD_DEADZONE or deltaSecondsValue == 0 then
		return Result.ok(nil)
	end
	local scaledMagnitude = (magnitude - GAMEPAD_DEADZONE) / (1 - GAMEPAD_DEADZONE)
	local delta = axis.Unit * scaledMagnitude * GAMEPAD_RETICLE_SPEED * (deltaSecondsValue :: number)
	data.reticle = clampReticle(data.reticle + delta, data.viewport)
	return Result.ok(makeAction(data, "Position", "Gamepad", { screenPosition = data.reticle }))
end

function AdapterMethods.getReticle(self: Adapter)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	return Result.ok(data.reticle)
end

function AdapterMethods.getMetrics(self: Adapter): Metrics
	local data = requireData(self)
	local gestureCount = 0
	for _, touch in data.touches do
		if touch.gesture then
			gestureCount += 1
		end
	end
	return table.freeze({
		preferredInput = data.preferredInput,
		activeTouchCount = data.touchCount,
		gestureTouchCount = gestureCount,
		reticle = data.reticle,
		viewport = data.viewport,
		actionCount = data.actionCount,
		positionActionCount = data.positionActionCount,
		confirmActionCount = data.confirmActionCount,
		cleaned = data.cleaned,
	})
end

function AdapterMethods.cleanup(self: Adapter)
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(true)
	end
	data.cleaned = true
	data.touches = {}
	data.touchCount = 0
	return Result.ok(true)
end

function PlacementInputAdapter.new(): AdapterResult
	local adapter = setmetatable({}, AdapterMethods) :: Adapter
	table.freeze(adapter)
	ADAPTER_DATA[adapter] = {
		preferredInput = "Desktop",
		viewport = DEFAULT_VIEWPORT,
		reticle = DEFAULT_VIEWPORT * 0.5,
		touches = {},
		touchCount = 0,
		cleaned = false,
		actionCount = 0,
		positionActionCount = 0,
		confirmActionCount = 0,
	}
	return Result.ok(adapter)
end

table.freeze(AdapterMethods)
return table.freeze(PlacementInputAdapter)
