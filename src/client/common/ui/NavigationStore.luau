--!strict

export type PrimaryScreen = "Home" | "Inventory" | "Chests" | "Settings"

export type ModalEntry = {
	id: string,
	restoreFocusKey: string?,
}

export type ScreenMemory = {
	selectionKey: string?,
	scrollOffset: number,
}

export type Snapshot = {
	revision: number,
	activeScreen: PrimaryScreen,
	modals: { ModalEntry },
	memory: { [PrimaryScreen]: ScreenMemory },
}

export type BackOutcome = {
	kind: "ModalClosed" | "ScreenChanged" | "Noop",
	modalId: string?,
	restoreFocusKey: string?,
}

export type ErrorCode = "INVALID_ARGUMENT" | "MODAL_ACTIVE" | "DUPLICATE_MODAL" | "MODAL_STACK_FULL" | "CLEANED_UP"

export type Error = { code: ErrorCode }
export type Outcome<T> = { ok: true, value: T } | { ok: false, error: Error }

type StoreData = {
	activeScreen: PrimaryScreen,
	modals: { ModalEntry },
	memory: { [PrimaryScreen]: ScreenMemory },
	revision: number,
	cleaned: boolean,
}

local StoreMethods = {}
StoreMethods.__index = StoreMethods

export type Store = typeof(setmetatable({} :: {}, StoreMethods))

local MAX_MODAL_DEPTH = 4
local MAX_KEY_BYTES = 64
local MAX_SCROLL_OFFSET = 10_000_000
local SCREEN_ORDER: { PrimaryScreen } = table.freeze({ "Home", "Inventory", "Chests", "Settings" })
local SCREEN_SET: { [string]: boolean } = table.freeze({
	Home = true,
	Inventory = true,
	Chests = true,
	Settings = true,
})

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_ARGUMENT = table.freeze({ code = "INVALID_ARGUMENT" :: "INVALID_ARGUMENT" }),
	MODAL_ACTIVE = table.freeze({ code = "MODAL_ACTIVE" :: "MODAL_ACTIVE" }),
	DUPLICATE_MODAL = table.freeze({ code = "DUPLICATE_MODAL" :: "DUPLICATE_MODAL" }),
	MODAL_STACK_FULL = table.freeze({ code = "MODAL_STACK_FULL" :: "MODAL_STACK_FULL" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: StoreData }

local NavigationStore = {
	MAX_MODAL_DEPTH = MAX_MODAL_DEPTH,
	SCREENS = SCREEN_ORDER,
}

local function ok<T>(value: T): Outcome<T>
	return table.freeze({ ok = true :: true, value = value })
end

local function failure<T>(code: ErrorCode): Outcome<T>
	return table.freeze({ ok = false :: false, error = ERRORS[code] })
end

local function requireData(value: unknown): StoreData
	if type(value) ~= "table" or DATA[value :: any] == nil then
		error("[ATD_NAVIGATION_STORE][code=INVALID_CONTEXT]", 0)
	end
	return DATA[value :: any]
end

local function safeKey(value: unknown): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= MAX_KEY_BYTES
		and string.match(value, "^[A-Za-z0-9][A-Za-z0-9_.:-]*$") ~= nil
end

local function isScreen(value: unknown): boolean
	return type(value) == "string" and rawget(SCREEN_SET, value :: string) == true
end

local function copyModal(entry: ModalEntry): ModalEntry
	return table.freeze({ id = entry.id, restoreFocusKey = entry.restoreFocusKey })
end

local function snapshot(data: StoreData): Snapshot
	local modals = table.create(#data.modals) :: { ModalEntry }
	for index, entry in data.modals do
		modals[index] = copyModal(entry)
	end
	local memory = {} :: { [PrimaryScreen]: ScreenMemory }
	for _, screen in SCREEN_ORDER do
		local remembered = data.memory[screen]
		memory[screen] = table.freeze({
			selectionKey = remembered.selectionKey,
			scrollOffset = remembered.scrollOffset,
		})
	end
	return table.freeze({
		revision = data.revision,
		activeScreen = data.activeScreen,
		modals = table.freeze(modals),
		memory = table.freeze(memory),
	})
end

function StoreMethods.getSnapshot(self: Store): Outcome<Snapshot>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	return ok(snapshot(data))
end

function StoreMethods.setPrimary(self: Store, value: unknown): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not isScreen(value) then
		return failure("INVALID_ARGUMENT")
	end
	if #data.modals > 0 then
		return failure("MODAL_ACTIVE")
	end
	local screen = value :: PrimaryScreen
	if data.activeScreen == screen then
		return ok(false)
	end
	data.activeScreen = screen
	data.revision += 1
	return ok(true)
end

function StoreMethods.remember(
	self: Store,
	screenValue: unknown,
	selectionKeyValue: unknown,
	scrollOffsetValue: unknown
): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if
		not isScreen(screenValue)
		or (selectionKeyValue ~= nil and not safeKey(selectionKeyValue))
		or type(scrollOffsetValue) ~= "number"
		or scrollOffsetValue ~= scrollOffsetValue
		or scrollOffsetValue == math.huge
		or scrollOffsetValue == -math.huge
		or scrollOffsetValue < 0
		or scrollOffsetValue > MAX_SCROLL_OFFSET
	then
		return failure("INVALID_ARGUMENT")
	end
	local screen = screenValue :: PrimaryScreen
	local current = data.memory[screen]
	local selectionKey = selectionKeyValue :: string?
	local scrollOffset = scrollOffsetValue :: number
	if current.selectionKey == selectionKey and current.scrollOffset == scrollOffset then
		return ok(false)
	end
	data.memory[screen] = {
		selectionKey = selectionKey,
		scrollOffset = scrollOffset,
	}
	data.revision += 1
	return ok(true)
end

function StoreMethods.pushModal(self: Store, idValue: unknown, restoreFocusKeyValue: unknown?): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not safeKey(idValue) or (restoreFocusKeyValue ~= nil and not safeKey(restoreFocusKeyValue)) then
		return failure("INVALID_ARGUMENT")
	end
	local id = idValue :: string
	for _, entry in data.modals do
		if entry.id == id then
			return failure("DUPLICATE_MODAL")
		end
	end
	if #data.modals >= MAX_MODAL_DEPTH then
		return failure("MODAL_STACK_FULL")
	end
	table.insert(data.modals, {
		id = id,
		restoreFocusKey = restoreFocusKeyValue :: string?,
	})
	data.revision += 1
	return ok(true)
end

function StoreMethods.popModal(self: Store): Outcome<ModalEntry?>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local entry = table.remove(data.modals)
	if entry == nil then
		return ok(nil)
	end
	data.revision += 1
	return ok(copyModal(entry))
end

function StoreMethods.back(self: Store): Outcome<BackOutcome>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local modal = table.remove(data.modals)
	if modal ~= nil then
		data.revision += 1
		return ok(table.freeze({
			kind = "ModalClosed" :: "ModalClosed",
			modalId = modal.id,
			restoreFocusKey = modal.restoreFocusKey,
		}))
	end
	if data.activeScreen ~= "Home" then
		data.activeScreen = "Home"
		data.revision += 1
		return ok(table.freeze({
			kind = "ScreenChanged" :: "ScreenChanged",
			modalId = nil,
			restoreFocusKey = nil,
		}))
	end
	return ok(table.freeze({
		kind = "Noop" :: "Noop",
		modalId = nil,
		restoreFocusKey = nil,
	}))
end

function StoreMethods.cleanup(self: Store): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return ok(true)
	end
	data.cleaned = true
	table.clear(data.modals)
	return ok(true)
end

function NavigationStore.new(initialScreenValue: unknown?): Outcome<Store>
	local initialScreen: PrimaryScreen = "Home"
	if initialScreenValue ~= nil then
		if not isScreen(initialScreenValue) then
			return failure("INVALID_ARGUMENT")
		end
		initialScreen = initialScreenValue :: PrimaryScreen
	end
	local memory = {} :: { [PrimaryScreen]: ScreenMemory }
	for _, screen in SCREEN_ORDER do
		memory[screen] = { selectionKey = nil, scrollOffset = 0 }
	end
	local store = setmetatable({}, StoreMethods) :: Store
	table.freeze(store)
	DATA[store] = {
		activeScreen = initialScreen,
		modals = {},
		memory = memory,
		revision = 0,
		cleaned = false,
	}
	return ok(store)
end

table.freeze(StoreMethods)
return table.freeze(NavigationStore)
