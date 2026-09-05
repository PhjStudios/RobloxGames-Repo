--!strict

local Messages = require(script.Parent.Messages)

export type Mode = "en" | "pseudo30" | "pseudo40" | "pseudo50"
export type ErrorCode = "UNKNOWN_KEY" | "INVALID_ARGUMENTS" | "INVALID_MODE" | "INVALID_CATALOG"
local MODES = table.freeze({ en = 0, pseudo30 = 0.3, pseudo40 = 0.4, pseudo50 = 0.5 })
local currentMode: Mode = "en"
local bindings: { [Instance]: { [string]: { key: string, last: string } } } = setmetatable({}, { __mode = "k" }) :: any
local MAX_NUMBER = 9_007_199_254_740_991
local MAX_TEXT_BYTES = 2_048
local MAX_OUTPUT_BYTES = 8_192
local ACCENTS =
	table.freeze({ a = "á", e = "ë", i = "ï", o = "ô", u = "ü", A = "Á", E = "Ë", I = "Ï", O = "Ô", U = "Ü" })
local Localization =
	{ VERSION = 1, MAX_ARGUMENTS = 16, MAX_TEXT_BYTES = MAX_TEXT_BYTES, MAX_OUTPUT_BYTES = MAX_OUTPUT_BYTES }

local function safeText(value: unknown): boolean
	return type(value) == "string"
		and #value <= MAX_TEXT_BYTES
		and utf8.len(value) ~= nil
		and string.find(value, "[%z\1-\8\11\12\14-\31\127<>]") == nil
end

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) <= MAX_NUMBER
end

function Localization.number(value: unknown, decimals: number?): string?
	if not finite(value) or (decimals ~= nil and (decimals % 1 ~= 0 or decimals < 0 or decimals > 4)) then
		return nil
	end
	local digits = decimals
	if digits == nil then
		digits = if (value :: number) % 1 == 0 then 0 else 2
	end
	local raw = string.format("%." .. tostring(digits) .. "f", value)
	local integer, fraction = string.match(raw, "^(-?%d+)(.*)$")
	local sign = if string.sub(integer :: string, 1, 1) == "-" then "-" else ""
	local unsigned = if sign == "-" then string.sub(integer :: string, 2) else integer :: string
	local grouped = string.reverse(string.gsub(string.reverse(unsigned), "(%d%d%d)", "%1,"))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return sign .. grouped .. (fraction :: string)
end

function Localization.percent(value: unknown): string?
	if not finite(value) or (value :: number) < 0 or (value :: number) > 100 then
		return nil
	end
	-- Odds schemas allow probabilities as small as 1e-9 percent.
	local raw = string.format("%.12f", value :: number)
	if (value :: number) > 0 and tonumber(raw) == 0 then
		return nil
	end
	raw = string.gsub(string.gsub(raw, "0+$", ""), "%.$", "")
	return raw .. "%"
end

function Localization.timer(value: unknown): string?
	if not finite(value) or (value :: number) < 0 or (value :: number) > 86_400 then
		return nil
	end
	local seconds = math.ceil(value :: number)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function pseudo(source: string, expansion: number): string
	if expansion == 0 or #source == 0 or string.find(source, "%a") == nil then
		return source
	end
	local accented = string.gsub(source, "[aeiouAEIOU]", ACCENTS)
	local count = utf8.len(source) or #source
	-- Padding expands each phrase, not the bounded values substituted afterward.
	return accented .. string.rep("~", math.ceil(count * expansion))
end

function Localization.validateCatalog(): boolean
	for key, entry in Messages.entries do
		if
			type(key) ~= "string"
			or not string.match(key, "^[a-z][a-z0-9_.]+$")
			or type(entry.source) ~= "string"
			or #entry.source > MAX_TEXT_BYTES
		then
			return false
		end
		local used = {}
		for argument in string.gmatch(entry.source, "{([a-z][A-Za-z0-9]*)}") do
			if entry.arguments[argument] == nil then
				return false
			end
			used[argument] = true
		end
		local count = 0
		for name, kind in entry.arguments do
			count += 1
			if not used[name] or (kind ~= "number" and kind ~= "text" and kind ~= "proper") then
				return false
			end
		end
		if count > Localization.MAX_ARGUMENTS then
			return false
		end
		if string.find(string.gsub(entry.source, "{[a-z][A-Za-z0-9]*}", ""), "[{}]") ~= nil then
			return false
		end
	end
	return true
end

function Localization.format(key: unknown, arguments: unknown?, modeValue: unknown?): any
	local mode = if modeValue == nil then currentMode else modeValue
	if type(mode) ~= "string" or MODES[mode] == nil then
		return { ok = false, error = { code = "INVALID_MODE" } }
	end
	local entry = if type(key) == "string" then Messages.entries[key] else nil
	if entry == nil then
		return { ok = false, error = { code = "UNKNOWN_KEY" } }
	end
	local values = if arguments == nil then {} else arguments
	if type(values) ~= "table" or getmetatable(values) ~= nil then
		return { ok = false, error = { code = "INVALID_ARGUMENTS" } }
	end
	local rendered = {}
	local count = 0
	for name, value in values do
		count += 1
		local kind = entry.arguments[name]
		if count > Localization.MAX_ARGUMENTS or kind == nil then
			return { ok = false, error = { code = "INVALID_ARGUMENTS" } }
		end
		if kind == "number" then
			if not finite(value) then
				return { ok = false, error = { code = "INVALID_ARGUMENTS" } }
			end
			rendered[name] = Localization.number(value)
		elseif not safeText(value) then
			return { ok = false, error = { code = "INVALID_ARGUMENTS" } }
		else
			rendered[name] = value
		end
	end
	for name in entry.arguments do
		if rendered[name] == nil then
			return { ok = false, error = { code = "INVALID_ARGUMENTS" } }
		end
	end
	local pieces = {}
	local cursor = 1
	while true do
		local first, last, argument = string.find(entry.source, "{([a-z][A-Za-z0-9]*)}", cursor)
		if first == nil then
			table.insert(pieces, pseudo(string.sub(entry.source, cursor), if entry.properName then 0 else MODES[mode]))
			break
		end
		table.insert(
			pieces,
			pseudo(string.sub(entry.source, cursor, first - 1), if entry.properName then 0 else MODES[mode])
		)
		table.insert(pieces, rendered[argument])
		cursor = (last :: number) + 1
	end
	local output = table.concat(pieces)
	if #output > MAX_OUTPUT_BYTES then
		return { ok = false, error = { code = "INVALID_ARGUMENTS" } }
	end
	return { ok = true, value = output }
end

function Localization.text(key: string, arguments: unknown?): string
	local result = Localization.format(key, arguments)
	return if result.ok then result.value else "…"
end

function Localization.isKey(value: unknown): boolean
	return type(value) == "string" and Messages.entries[value] ~= nil
end

function Localization.bind(instance: Instance, key: string, property: string?): boolean
	local field = property or "Text"
	if field ~= "Text" and field ~= "PlaceholderText" then
		return false
	end
	local result = Localization.format(key)
	if not result.ok then
		return false
	end
	local written = pcall(function()
		(instance :: any)[field] = result.value
	end)
	if not written then
		return false
	end
	local registered = bindings[instance] or {}
	registered[field] = { key = key, last = result.value }
	bindings[instance] = registered
	instance:SetAttribute("ATDLocalization" .. field, key)
	instance:SetAttribute("ATDLocalizationLast" .. field, result.value)
	return true
end

function Localization.refresh(root: Instance)
	for _, instance in root:GetDescendants() do
		for _, field in { "Text", "PlaceholderText" } do
			local key = instance:GetAttribute("ATDLocalization" .. field)
			if type(key) == "string" then
				local last = instance:GetAttribute("ATDLocalizationLast" .. field)
				local read, current = pcall(function()
					return (instance :: any)[field]
				end)
				if read and current == last then
					Localization.bind(instance, key, field)
				end
			end
		end
	end
end

function Localization.setMode(value: unknown): boolean
	if type(value) ~= "string" or MODES[value] == nil then
		return false
	end
	currentMode = value :: Mode
	for instance, registered in bindings do
		for property, binding in registered do
			local read, displayed = pcall(function()
				return (instance :: any)[property]
			end)
			if read and displayed == binding.last then
				local translated = Localization.text(binding.key)
				if pcall(function()
					(instance :: any)[property] = translated
				end) then
					binding.last = translated
					instance:SetAttribute("ATDLocalizationLast" .. property, translated)
				end
			end
		end
	end
	return true
end

function Localization.getMode(): Mode
	return currentMode
end

function Localization.properName(value: unknown): string
	return if safeText(value) then value :: string else "…"
end

function Localization.enum(domain: string, value: string): string
	local values = Messages.enums[domain]
	local key = if values == nil then nil else values[value]
	return Localization.text(key or "common.unavailable")
end

function Localization.currency(kind: string, amount: unknown): string?
	if kind ~= "Gold" and kind ~= "BattleCash" then
		return nil
	end
	local result = Localization.format(
		if kind == "Gold" then "common.currency.gold" else "common.currency.battle_cash",
		{ amount = amount }
	)
	return if result.ok then result.value else nil
end

function Localization.contentDescription(contentId: string, fallback: string?): string
	local key = Messages.descriptions[contentId]
	return if key ~= nil then Localization.text(key) else (if safeText(fallback) then fallback :: string else "")
end

function Localization.contentPolicy(contentId: string, fallback: string?): string
	local key = Messages.policies[contentId]
	return if key ~= nil then Localization.text(key) else (if safeText(fallback) then fallback :: string else "")
end

return table.freeze(Localization)
