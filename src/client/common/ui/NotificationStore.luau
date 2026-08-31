--!strict

export type Kind = "Info" | "Success" | "Warning" | "Error"

export type NotificationInput = {
	kind: Kind,
	title: string,
	message: string,
	dedupeKey: string?,
	durationSeconds: number?,
}

export type Notification = {
	id: string,
	kind: Kind,
	title: string,
	message: string,
	dedupeKey: string?,
	repeatCount: number,
	expiresAt: number,
}

export type PushOutcome = {
	kind: "Added" | "Deduplicated",
	id: string,
}

export type ErrorCode = "INVALID_ARGUMENT" | "CLOCK_FAILED" | "CLEANED_UP"
export type Error = { code: ErrorCode }
export type Outcome<T> = { ok: true, value: T } | { ok: false, error: Error }

type StoreData = {
	now: () -> number,
	entries: { Notification },
	nextId: number,
	cleaned: boolean,
}

local StoreMethods = {}
StoreMethods.__index = StoreMethods

export type Store = typeof(setmetatable({} :: {}, StoreMethods))

local MAX_NOTIFICATIONS = 5
local MAX_TITLE_BYTES = 48
local MAX_MESSAGE_BYTES = 180
local MAX_DEDUPE_KEY_BYTES = 64
local MIN_DURATION_SECONDS = 1
local MAX_DURATION_SECONDS = 15
local DEFAULT_DURATION_SECONDS = 5
local MAX_REPEAT_COUNT = 999
local MAX_ID = 2 ^ 31 - 1

local KIND_SET: { [string]: boolean } = table.freeze({
	Info = true,
	Success = true,
	Warning = true,
	Error = true,
})

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_ARGUMENT = table.freeze({ code = "INVALID_ARGUMENT" :: "INVALID_ARGUMENT" }),
	CLOCK_FAILED = table.freeze({ code = "CLOCK_FAILED" :: "CLOCK_FAILED" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: StoreData }

local NotificationStore = {
	MAX_NOTIFICATIONS = MAX_NOTIFICATIONS,
	MAX_REPEAT_COUNT = MAX_REPEAT_COUNT,
}

local function ok<T>(value: T): Outcome<T>
	return table.freeze({ ok = true :: true, value = value })
end

local function failure<T>(code: ErrorCode): Outcome<T>
	return table.freeze({ ok = false :: false, error = ERRORS[code] })
end

local function requireData(value: unknown): StoreData
	if type(value) ~= "table" or DATA[value :: any] == nil then
		error("[ATD_NOTIFICATION_STORE][code=INVALID_CONTEXT]", 0)
	end
	return DATA[value :: any]
end

local function finiteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function safeText(value: unknown, maximumBytes: number): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= maximumBytes
		and string.find(value, "[%z\1-\8\11\12\14-\31]") == nil
end

local function safeDedupeKey(value: unknown): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= MAX_DEDUPE_KEY_BYTES
		and string.match(value, "^[A-Za-z0-9][A-Za-z0-9_.:-]*$") ~= nil
end

local function readNow(data: StoreData): number?
	local succeeded, value = pcall(data.now)
	if not succeeded or not finiteNumber(value) or (value :: number) < 0 then
		return nil
	end
	return value :: number
end

local function copyEntry(entry: Notification): Notification
	return table.freeze({
		id = entry.id,
		kind = entry.kind,
		title = entry.title,
		message = entry.message,
		dedupeKey = entry.dedupeKey,
		repeatCount = entry.repeatCount,
		expiresAt = entry.expiresAt,
	})
end

local function prune(data: StoreData, now: number): number
	local removed = 0
	for index = #data.entries, 1, -1 do
		if data.entries[index].expiresAt <= now then
			table.remove(data.entries, index)
			removed += 1
		end
	end
	return removed
end

local function canonicalInput(value: unknown): NotificationInput?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local record = value :: { [any]: unknown }
	local count = 0
	for key in next, record do
		if
			type(key) ~= "string"
			or (
				key ~= "kind"
				and key ~= "title"
				and key ~= "message"
				and key ~= "dedupeKey"
				and key ~= "durationSeconds"
			)
		then
			return nil
		end
		count += 1
	end
	if count < 3 or count > 5 then
		return nil
	end
	local kind = rawget(record, "kind")
	local title = rawget(record, "title")
	local message = rawget(record, "message")
	local dedupeKey = rawget(record, "dedupeKey")
	local duration = rawget(record, "durationSeconds")
	if
		type(kind) ~= "string"
		or rawget(KIND_SET, kind) ~= true
		or not safeText(title, MAX_TITLE_BYTES)
		or not safeText(message, MAX_MESSAGE_BYTES)
		or (dedupeKey ~= nil and not safeDedupeKey(dedupeKey))
		or (
			duration ~= nil
			and (
				not finiteNumber(duration)
				or (duration :: number) < MIN_DURATION_SECONDS
				or (duration :: number) > MAX_DURATION_SECONDS
			)
		)
	then
		return nil
	end
	return {
		kind = kind :: Kind,
		title = title :: string,
		message = message :: string,
		dedupeKey = dedupeKey :: string?,
		durationSeconds = duration :: number?,
	}
end

local function nextId(data: StoreData): string
	for _ = 1, MAX_NOTIFICATIONS + 1 do
		local candidate = `toast:{data.nextId}`
		data.nextId = if data.nextId >= MAX_ID then 1 else data.nextId + 1
		local occupied = false
		for _, entry in data.entries do
			if entry.id == candidate then
				occupied = true
				break
			end
		end
		if not occupied then
			return candidate
		end
	end
	error("[ATD_NOTIFICATION_STORE][code=ID_EXHAUSTED]", 0)
end

function StoreMethods.push(self: Store, value: unknown): Outcome<PushOutcome>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local input = canonicalInput(value)
	if input == nil then
		return failure("INVALID_ARGUMENT")
	end
	local now = readNow(data)
	if now == nil then
		return failure("CLOCK_FAILED")
	end
	prune(data, now)
	local duration = input.durationSeconds or DEFAULT_DURATION_SECONDS
	if input.dedupeKey ~= nil then
		for index, entry in data.entries do
			if entry.dedupeKey == input.dedupeKey then
				local updated: Notification = {
					id = entry.id,
					kind = entry.kind,
					title = entry.title,
					message = entry.message,
					dedupeKey = entry.dedupeKey,
					repeatCount = math.min(MAX_REPEAT_COUNT, entry.repeatCount + 1),
					expiresAt = now + duration,
				}
				data.entries[index] = updated
				return ok(table.freeze({ kind = "Deduplicated" :: "Deduplicated", id = entry.id }))
			end
		end
	end
	if #data.entries >= MAX_NOTIFICATIONS then
		table.remove(data.entries, 1)
	end
	local id = nextId(data)
	table.insert(data.entries, {
		id = id,
		kind = input.kind,
		title = input.title,
		message = input.message,
		dedupeKey = input.dedupeKey,
		repeatCount = 1,
		expiresAt = now + duration,
	})
	return ok(table.freeze({ kind = "Added" :: "Added", id = id }))
end

function StoreMethods.dismiss(self: Store, idValue: unknown): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if not safeDedupeKey(idValue) then
		return failure("INVALID_ARGUMENT")
	end
	for index, entry in data.entries do
		if entry.id == idValue then
			table.remove(data.entries, index)
			return ok(true)
		end
	end
	return ok(false)
end

function StoreMethods.tick(self: Store): Outcome<number>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local now = readNow(data)
	if now == nil then
		return failure("CLOCK_FAILED")
	end
	return ok(prune(data, now))
end

function StoreMethods.getSnapshot(self: Store): Outcome<{ Notification }>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local now = readNow(data)
	if now == nil then
		return failure("CLOCK_FAILED")
	end
	prune(data, now)
	local entries = table.create(#data.entries) :: { Notification }
	for index, entry in data.entries do
		entries[index] = copyEntry(entry)
	end
	return ok(table.freeze(entries))
end

function StoreMethods.cleanup(self: Store): Outcome<boolean>
	local data = requireData(self)
	if data.cleaned then
		return ok(true)
	end
	data.cleaned = true
	table.clear(data.entries)
	return ok(true)
end

function NotificationStore.new(nowValue: unknown?): Outcome<Store>
	local now = if nowValue == nil then os.clock else nowValue
	if type(now) ~= "function" then
		return failure("INVALID_ARGUMENT")
	end
	local store = setmetatable({}, StoreMethods) :: Store
	table.freeze(store)
	DATA[store] = {
		now = now :: () -> number,
		entries = {},
		nextId = 1,
		cleaned = false,
	}
	if readNow(DATA[store]) == nil then
		DATA[store] = nil
		return failure("CLOCK_FAILED")
	end
	return ok(store)
end

table.freeze(StoreMethods)
return table.freeze(NotificationStore)
