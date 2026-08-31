--!strict

local UserInputService = game:GetService("UserInputService")

export type InputFamily = "Desktop" | "Touch" | "Gamepad"
export type Context = "Match" | "Ready" | "Placement" | "Tower" | "Results"
export type ActionKind =
	"SelectHotbar"
	| "CycleHotbar"
	| "CycleTower"
	| "Confirm"
	| "Cancel"
	| "Rotate"
	| "Upgrade"
	| "Sell"
	| "Retarget"
	| "Ready"
	| "Replay"
	| "FocusBase"

export type SemanticAction = {
	kind: ActionKind,
	source: InputFamily,
	slot: number?,
	direction: number?,
	screenPosition: Vector2?,
}

export type RawInput = {
	keyCode: string?,
	inputType: string?,
	position: Vector2?,
}

export type Metrics = {
	context: Context,
	preferredInput: InputFamily,
	hint: string,
	actionCount: number,
	connectionCount: number,
	cleaned: boolean,
}

export type ErrorCode = "INVALID_ARGUMENT" | "ACTION_UNAVAILABLE" | "CALLBACK_FAILED" | "CLEANED_UP"
export type InputError = {
	code: ErrorCode,
}

export type Outcome<T> = { ok: true, value: T } | { ok: false, error: InputError }
export type ActionCallback = (SemanticAction) -> ()
export type InputBeganListener = (RawInput, boolean) -> ()
export type PreferredInputListener = (InputFamily) -> ()
export type Dependencies = {
	connectInputBegan: (InputBeganListener) -> RBXScriptConnection,
	connectPreferredInputChanged: (PreferredInputListener) -> RBXScriptConnection,
	initialPreferredInput: InputFamily,
}

type InputData = {
	callback: ActionCallback,
	context: Context,
	preferredInput: InputFamily,
	connections: { RBXScriptConnection },
	actionCount: number,
	cleaned: boolean,
}

local InputMethods = {}
InputMethods.__index = InputMethods

export type InputMap = typeof(setmetatable({} :: {}, InputMethods))
export type InputResult = Outcome<InputMap>
export type TestConstructor = (ActionCallback, Dependencies) -> InputResult

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: InputData }

local CONTEXTS: { [Context]: boolean } = table.freeze({
	Match = true,
	Ready = true,
	Placement = true,
	Tower = true,
	Results = true,
})

local INPUT_FAMILIES: { [InputFamily]: boolean } = table.freeze({
	Desktop = true,
	Touch = true,
	Gamepad = true,
})

local ACTION_KINDS: { [ActionKind]: boolean } = table.freeze({
	SelectHotbar = true,
	CycleHotbar = true,
	CycleTower = true,
	Confirm = true,
	Cancel = true,
	Rotate = true,
	Upgrade = true,
	Sell = true,
	Retarget = true,
	Ready = true,
	Replay = true,
	FocusBase = true,
})

local HINTS: { [Context]: { [InputFamily]: string } } = table.freeze({
	Match = table.freeze({
		Desktop = "1–5 Select Tower • F Focus Base",
		Touch = "Tap a tower card • Tap Base to focus",
		Gamepad = "A Select Tower • LB/RB Build • D-Pad Left/Right Tower • D-Pad Down Toggle Base",
	}),
	Ready = table.freeze({
		Desktop = "R / Enter Ready",
		Touch = "Tap Ready",
		Gamepad = "A Ready",
	}),
	Placement = table.freeze({
		Desktop = "Click/Enter Place • R Rotate • Q Cancel",
		Touch = "Tap position • Confirm • Rotate • Cancel",
		Gamepad = "A Place • B Cancel • RT Rotate • LB/RB Tower",
	}),
	Tower = table.freeze({
		Desktop = "U Upgrade • T Target • X Sell • Q Close",
		Touch = "Use Upgrade, Target, Sell, or Close",
		Gamepad = "Y Upgrade • RB Target • X Sell • D-Pad Left/Right Tower • B Close",
	}),
	Results = table.freeze({
		Desktop = "R / Enter Play Again",
		Touch = "Tap Play Again",
		Gamepad = "A Play Again",
	}),
})

local ERRORS: { [ErrorCode]: InputError } = table.freeze({
	INVALID_ARGUMENT = table.freeze({ code = "INVALID_ARGUMENT" :: "INVALID_ARGUMENT" }),
	ACTION_UNAVAILABLE = table.freeze({ code = "ACTION_UNAVAILABLE" :: "ACTION_UNAVAILABLE" }),
	CALLBACK_FAILED = table.freeze({ code = "CALLBACK_FAILED" :: "CALLBACK_FAILED" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local PlayableInputMap = {
	HOTBAR_SLOTS = 5,
	newForTests = nil :: TestConstructor?,
}

local function ok<T>(value: T): Outcome<T>
	return table.freeze({
		ok = true :: true,
		value = value,
	})
end

local function failure<T>(code: ErrorCode): Outcome<T>
	return table.freeze({
		ok = false :: false,
		error = ERRORS[code],
	})
end

local function requireData(value: unknown): InputData
	if type(value) ~= "table" then
		error("[ATD_PLAYABLE_INPUT][code=INVALID_CONTEXT]", 0)
	end
	local data = DATA[value :: any]
	if data == nil then
		error("[ATD_PLAYABLE_INPUT][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function isInputFamily(value: unknown): boolean
	return type(value) == "string" and rawget(INPUT_FAMILIES, value) == true
end

local function isContext(value: unknown): boolean
	return type(value) == "string" and rawget(CONTEXTS, value) == true
end

local function isFiniteVector2(value: unknown): boolean
	if typeof(value) ~= "Vector2" then
		return false
	end
	local position = value :: Vector2
	return position.X == position.X
		and position.Y == position.Y
		and math.abs(position.X) <= 100_000
		and math.abs(position.Y) <= 100_000
end

local function actionAllowed(context: Context, kind: ActionKind): boolean
	if kind == "FocusBase" then
		return context == "Match" or context == "Placement" or context == "Tower"
	elseif kind == "CycleTower" then
		return context == "Match" or context == "Tower"
	elseif kind == "SelectHotbar" or kind == "CycleHotbar" then
		return context == "Match" or context == "Placement" or context == "Tower"
	elseif context == "Ready" then
		return kind == "Ready"
	elseif context == "Results" then
		return kind == "Replay"
	elseif context == "Placement" then
		return kind == "Confirm" or kind == "Cancel" or kind == "Rotate"
	elseif context == "Tower" then
		return kind == "Cancel" or kind == "Upgrade" or kind == "Sell" or kind == "Retarget"
	elseif context == "Match" then
		return kind == "Upgrade" or kind == "Sell" or kind == "Retarget" or kind == "Cancel"
	end
	return false
end

local function canonicalAction(
	context: Context,
	preferredInput: InputFamily,
	kindValue: unknown,
	fieldsValue: unknown
): SemanticAction?
	if type(kindValue) ~= "string" or rawget(ACTION_KINDS, kindValue) ~= true then
		return nil
	end
	local kind = kindValue :: ActionKind
	if not actionAllowed(context, kind) then
		return nil
	end

	local fields = if fieldsValue == nil then {} else fieldsValue
	if type(fields) ~= "table" or getmetatable(fields) ~= nil then
		return nil
	end
	local sourceValue = rawget(fields :: any, "source")
	local source = if sourceValue == nil then preferredInput else sourceValue
	if not isInputFamily(source) then
		return nil
	end

	local slotValue = rawget(fields :: any, "slot")
	local directionValue = rawget(fields :: any, "direction")
	local positionValue = rawget(fields :: any, "screenPosition")
	if kind == "SelectHotbar" then
		if
			type(slotValue) ~= "number"
			or slotValue % 1 ~= 0
			or slotValue < 1
			or slotValue > PlayableInputMap.HOTBAR_SLOTS
		then
			return nil
		end
	elseif slotValue ~= nil then
		return nil
	end
	if kind == "CycleHotbar" or kind == "CycleTower" then
		if directionValue ~= -1 and directionValue ~= 1 then
			return nil
		end
	elseif directionValue ~= nil then
		return nil
	end
	if positionValue ~= nil and not isFiniteVector2(positionValue) then
		return nil
	end

	return table.freeze({
		kind = kind,
		source = source :: InputFamily,
		slot = slotValue :: number?,
		direction = directionValue :: number?,
		screenPosition = positionValue :: Vector2?,
	})
end

local function hotbarAction(keyCode: string): (ActionKind?, { [string]: unknown }?)
	if keyCode == "One" or keyCode == "KeypadOne" then
		return "SelectHotbar", { slot = 1 }
	elseif keyCode == "Two" or keyCode == "KeypadTwo" then
		return "SelectHotbar", { slot = 2 }
	elseif keyCode == "Three" or keyCode == "KeypadThree" then
		return "SelectHotbar", { slot = 3 }
	elseif keyCode == "Four" or keyCode == "KeypadFour" then
		return "SelectHotbar", { slot = 4 }
	elseif keyCode == "Five" or keyCode == "KeypadFive" then
		return "SelectHotbar", { slot = 5 }
	elseif keyCode == "ButtonL1" then
		return "CycleHotbar", { direction = -1 }
	elseif keyCode == "ButtonR1" then
		return "CycleHotbar", { direction = 1 }
	end
	return nil, nil
end

local function resolveRaw(context: Context, preferredInput: InputFamily, rawValue: unknown): SemanticAction?
	if type(rawValue) ~= "table" or getmetatable(rawValue) ~= nil then
		return nil
	end
	local rawInput = rawValue :: { [any]: unknown }
	local keyCodeValue = rawget(rawInput, "keyCode")
	local inputTypeValue = rawget(rawInput, "inputType")
	local positionValue = rawget(rawInput, "position")
	if keyCodeValue ~= nil and type(keyCodeValue) ~= "string" then
		return nil
	end
	if inputTypeValue ~= nil and type(inputTypeValue) ~= "string" then
		return nil
	end
	if positionValue ~= nil and not isFiniteVector2(positionValue) then
		return nil
	end
	local keyCode = keyCodeValue or "Unknown"
	local inputType = inputTypeValue or "None"

	local source: InputFamily = preferredInput
	if string.sub(inputType, 1, 7) == "Gamepad" then
		source = "Gamepad"
	elseif inputType == "Touch" then
		source = "Touch"
	elseif inputType == "Keyboard" or string.sub(inputType, 1, 11) == "MouseButton" then
		source = "Desktop"
	end

	local kind: ActionKind? = nil
	local fields: { [string]: unknown } = { source = source }
	if context ~= "Ready" and context ~= "Results" then
		local hotbarKind, hotbarFields = hotbarAction(keyCode)
		if hotbarKind ~= nil and not (context == "Tower" and keyCode == "ButtonR1") then
			kind = hotbarKind
			fields = hotbarFields :: { [string]: unknown }
			fields.source = source
		end
	end

	if
		kind == nil
		and (context == "Match" or context == "Tower")
		and (keyCode == "DPadLeft" or keyCode == "DPadRight")
	then
		kind = "CycleTower"
		fields.direction = if keyCode == "DPadLeft" then -1 else 1
	elseif kind == nil and (keyCode == "F" or keyCode == "DPadDown") then
		kind = "FocusBase"
	elseif
		kind == nil
		and context == "Ready"
		and (
			keyCode == "R"
			or keyCode == "Return"
			or keyCode == "KeypadEnter"
			or keyCode == "Space"
			or keyCode == "ButtonA"
		)
	then
		kind = "Ready"
	elseif
		kind == nil
		and context == "Results"
		and (
			keyCode == "R"
			or keyCode == "Return"
			or keyCode == "KeypadEnter"
			or keyCode == "Space"
			or keyCode == "ButtonA"
		)
	then
		kind = "Replay"
	elseif kind == nil and context == "Placement" then
		if keyCode == "Return" or keyCode == "KeypadEnter" or keyCode == "ButtonA" or inputType == "MouseButton1" then
			kind = "Confirm"
			fields.screenPosition = positionValue
		elseif keyCode == "Escape" or keyCode == "Q" or keyCode == "ButtonB" then
			kind = "Cancel"
		elseif keyCode == "R" or keyCode == "ButtonR2" then
			kind = "Rotate"
		end
	elseif kind == nil and (context == "Tower" or context == "Match") then
		if keyCode == "Escape" or keyCode == "Q" or keyCode == "ButtonB" then
			kind = "Cancel"
		elseif keyCode == "U" or keyCode == "ButtonY" then
			kind = "Upgrade"
		elseif keyCode == "X" or keyCode == "ButtonX" then
			kind = "Sell"
		elseif keyCode == "T" or keyCode == "ButtonR1" then
			kind = "Retarget"
		end
	end
	if kind == nil then
		return nil
	end
	return canonicalAction(context, preferredInput, kind, fields)
end

function InputMethods.setContext(self: InputMap, value: unknown): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not isContext(value) then
		return failure("INVALID_ARGUMENT")
	end
	local changed = data.context ~= value
	data.context = value :: Context
	return ok(changed)
end

function InputMethods.setPreferredInput(self: InputMap, value: unknown): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not isInputFamily(value) then
		return failure("INVALID_ARGUMENT")
	end
	local changed = data.preferredInput ~= value
	data.preferredInput = value :: InputFamily
	return ok(changed)
end

function InputMethods.emit(self: InputMap, kind: unknown, fields: unknown?): Outcome<SemanticAction>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local action = canonicalAction(data.context, data.preferredInput, kind, fields)
	if action == nil then
		if type(kind) == "string" and rawget(ACTION_KINDS, kind) == true then
			return failure("ACTION_UNAVAILABLE")
		end
		return failure("INVALID_ARGUMENT")
	end
	if not pcall(data.callback, action) then
		return failure("CALLBACK_FAILED")
	end
	data.actionCount += 1
	return ok(action)
end

function InputMethods.handleRaw(self: InputMap, rawInput: unknown, processed: unknown): Outcome<SemanticAction?>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if type(processed) ~= "boolean" then
		return failure("INVALID_ARGUMENT")
	end
	if processed then
		return ok(nil)
	end
	local action = resolveRaw(data.context, data.preferredInput, rawInput)
	if action == nil then
		if type(rawInput) ~= "table" or getmetatable(rawInput) ~= nil then
			return failure("INVALID_ARGUMENT")
		end
		return ok(nil)
	end
	data.preferredInput = action.source
	if not pcall(data.callback, action) then
		return failure("CALLBACK_FAILED")
	end
	data.actionCount += 1
	return ok(action)
end

function InputMethods.getHints(self: InputMap): Outcome<string>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	return ok(HINTS[data.context][data.preferredInput])
end

function InputMethods.getMetrics(self: InputMap): Metrics
	local data = requireData(self)
	return table.freeze({
		context = data.context,
		preferredInput = data.preferredInput,
		hint = HINTS[data.context][data.preferredInput],
		actionCount = data.actionCount,
		connectionCount = #data.connections,
		cleaned = data.cleaned,
	})
end

function InputMethods.cleanup(self: InputMap): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return ok(true)
	end
	data.cleaned = true
	local succeeded = true
	for index = #data.connections, 1, -1 do
		local connection = data.connections[index]
		data.connections[index] = nil
		if not pcall(function()
			connection:Disconnect()
		end) then
			succeeded = false
		end
	end
	if not succeeded then
		return failure("CALLBACK_FAILED")
	end
	return ok(true)
end

local function construct(callback: ActionCallback, dependencies: Dependencies): InputResult
	if
		type(callback) ~= "function"
		or type(dependencies) ~= "table"
		or type(dependencies.connectInputBegan) ~= "function"
		or type(dependencies.connectPreferredInputChanged) ~= "function"
		or not isInputFamily(dependencies.initialPreferredInput)
	then
		return failure("INVALID_ARGUMENT")
	end

	local inputMap = setmetatable({}, InputMethods) :: InputMap
	table.freeze(inputMap)
	local data: InputData = {
		callback = callback,
		context = "Match",
		preferredInput = dependencies.initialPreferredInput,
		connections = {},
		actionCount = 0,
		cleaned = false,
	}
	DATA[inputMap] = data

	local connected, connectionOrError = pcall(dependencies.connectInputBegan, function(rawInput, processed)
		if not data.cleaned then
			local _ = inputMap:handleRaw(rawInput, processed)
		end
	end)
	if not connected or typeof(connectionOrError) ~= "RBXScriptConnection" then
		DATA[inputMap] = nil
		return failure("CALLBACK_FAILED")
	end
	table.insert(data.connections, connectionOrError :: RBXScriptConnection)

	local preferredConnected, preferredConnectionOrError = pcall(
		dependencies.connectPreferredInputChanged,
		function(inputFamily)
			if not data.cleaned then
				local _ = inputMap:setPreferredInput(inputFamily)
			end
		end
	)
	if not preferredConnected or typeof(preferredConnectionOrError) ~= "RBXScriptConnection" then
		inputMap:cleanup()
		DATA[inputMap] = nil
		return failure("CALLBACK_FAILED")
	end
	table.insert(data.connections, preferredConnectionOrError :: RBXScriptConnection)
	return ok(inputMap)
end

local function inputFamilyFromType(inputType: Enum.UserInputType): InputFamily
	local name = inputType.Name
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.sub(name, 1, 7) == "Gamepad" then
		return "Gamepad"
	end
	return "Desktop"
end

local function productionDependencies(): Dependencies
	local initial: InputFamily = "Desktop"
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		initial = "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		initial = "Gamepad"
	end
	return {
		initialPreferredInput = initial,
		connectInputBegan = function(listener)
			return UserInputService.InputBegan:Connect(function(input, processed)
				local position = input.Position
				listener({
					keyCode = input.KeyCode.Name,
					inputType = input.UserInputType.Name,
					position = Vector2.new(position.X, position.Y),
				}, processed)
			end)
		end,
		connectPreferredInputChanged = function(listener)
			return UserInputService.LastInputTypeChanged:Connect(function(inputType)
				listener(inputFamilyFromType(inputType))
			end)
		end,
	}
end

function PlayableInputMap.new(callback: unknown): InputResult
	if type(callback) ~= "function" then
		return failure("INVALID_ARGUMENT")
	end
	return construct(callback :: ActionCallback, productionDependencies())
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "PlayableInputMap" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionClientPlayable" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent ~= nil
		and automatedTests.Parent:IsA("ServerStorage")
end

if isExactTestModule() then
	PlayableInputMap.newForTests = construct
end

table.freeze(InputMethods)
return table.freeze(PlayableInputMap)
