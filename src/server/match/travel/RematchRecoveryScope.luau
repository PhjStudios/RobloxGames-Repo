--!strict

export type Schedule = (delaySeconds: number, callback: () -> ()) -> unknown
export type Cancel = (handle: unknown) -> ()

export type Metrics = {
	cleaned: boolean,
	contextCount: number,
	scheduledCount: number,
}

export type Scope = {
	register: (self: Scope, key: string, context: unknown) -> boolean,
	get: (self: Scope, key: string) -> unknown?,
	remove: (self: Scope, key: string) -> unknown?,
	schedule: (self: Scope, key: string, delaySeconds: number, callback: (unknown) -> ()) -> boolean,
	cleanup: (self: Scope, settle: ((unknown) -> ())?) -> boolean,
	getMetrics: (self: Scope) -> Metrics,
}

type Scheduled = {
	handle: unknown?,
}

type Entry = {
	context: unknown,
	scheduled: Scheduled?,
}

type ScopeData = {
	schedule: Schedule,
	cancel: Cancel,
	entries: { [string]: Entry },
	cleaned: boolean,
}

local MAX_KEY_LENGTH = 128

local DATA: { [Scope]: ScopeData } = setmetatable({}, { __mode = "k" }) :: any
local Methods = {}
Methods.__index = Methods

local function dataFor(self: Scope): ScopeData
	local data = DATA[self]
	if data == nil then
		error("[ATD_REMATCH_RECOVERY_SCOPE][code=INVALID_SCOPE]", 0)
	end
	return data
end

local function validKey(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_KEY_LENGTH
end

local function validDelay(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function cancelScheduled(data: ScopeData, entry: Entry)
	local scheduled = entry.scheduled
	entry.scheduled = nil
	if scheduled ~= nil and scheduled.handle ~= nil then
		pcall(data.cancel, scheduled.handle)
	end
end

function Methods.register(self: Scope, keyValue: string, context: unknown): boolean
	local data = dataFor(self)
	if data.cleaned or not validKey(keyValue) or context == nil or data.entries[keyValue] ~= nil then
		return false
	end
	data.entries[keyValue] = {
		context = context,
		scheduled = nil,
	}
	return true
end

function Methods.get(self: Scope, keyValue: string): unknown?
	local data = dataFor(self)
	if data.cleaned or not validKey(keyValue) then
		return nil
	end
	local entry = data.entries[keyValue]
	return if entry == nil then nil else entry.context
end

function Methods.remove(self: Scope, keyValue: string): unknown?
	local data = dataFor(self)
	if not validKey(keyValue) then
		return nil
	end
	local entry = data.entries[keyValue]
	if entry == nil then
		return nil
	end
	data.entries[keyValue] = nil
	cancelScheduled(data, entry)
	return entry.context
end

function Methods.schedule(self: Scope, keyValue: string, delaySeconds: number, callback: (unknown) -> ()): boolean
	local data = dataFor(self)
	local entry = if validKey(keyValue) then data.entries[keyValue] else nil
	if
		data.cleaned
		or entry == nil
		or entry.scheduled ~= nil
		or not validDelay(delaySeconds)
		or type(callback) ~= "function"
	then
		return false
	end
	local scheduled: Scheduled = { handle = nil }
	entry.scheduled = scheduled
	local called, handle = pcall(data.schedule, delaySeconds, function()
		local current = data.entries[keyValue]
		if data.cleaned or current ~= entry or current.scheduled ~= scheduled then
			return
		end
		current.scheduled = nil
		callback(current.context)
	end)
	if not called or handle == nil then
		if data.entries[keyValue] == entry and entry.scheduled == scheduled then
			entry.scheduled = nil
		end
		return false
	end
	scheduled.handle = handle
	return true
end

function Methods.cleanup(self: Scope, settle: ((unknown) -> ())?): boolean
	local data = dataFor(self)
	if data.cleaned then
		return false
	end
	data.cleaned = true
	for _, entry in data.entries do
		if settle ~= nil then
			pcall(settle, entry.context)
		end
		cancelScheduled(data, entry)
	end
	table.clear(data.entries)
	return true
end

function Methods.getMetrics(self: Scope): Metrics
	local data = dataFor(self)
	local contextCount = 0
	local scheduledCount = 0
	for _, entry in data.entries do
		contextCount += 1
		if entry.scheduled ~= nil then
			scheduledCount += 1
		end
	end
	return table.freeze({
		cleaned = data.cleaned,
		contextCount = contextCount,
		scheduledCount = scheduledCount,
	})
end

local RematchRecoveryScope = {}

function RematchRecoveryScope.new(scheduleValue: unknown, cancelValue: unknown): Scope
	if type(scheduleValue) ~= "function" or type(cancelValue) ~= "function" then
		error("[ATD_REMATCH_RECOVERY_SCOPE][code=INVALID_DEPENDENCIES]", 0)
	end
	local scope = setmetatable({}, Methods) :: any
	DATA[scope] = {
		schedule = scheduleValue :: Schedule,
		cancel = cancelValue :: Cancel,
		entries = {},
		cleaned = false,
	}
	table.freeze(scope)
	return scope
end

table.freeze(Methods)
return table.freeze(RematchRecoveryScope)
