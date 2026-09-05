--!strict

local Localization = require(script.Parent.Localization)
local Messages = require(script.Parent.Messages)
local WorldMessages = {}
local PREFIX = "ATDMessageArgument_"

-- Only the owned queue display vocabulary crosses this presentation boundary.
local function entryFor(key: unknown): any
	return if type(key) == "string" and string.sub(key, 1, 12) == "queue_world." then Messages.entries[key] else nil
end

function WorldMessages.render(label: TextLabel): boolean
	local key = label:GetAttribute("ATDMessageKey")
	local entry = entryFor(key)
	if entry == nil then
		return false
	end
	local arguments = {}
	for name in entry.arguments do
		local value = label:GetAttribute(PREFIX .. name)
		arguments[name] = if (name == "state" or name == "publicStatus" or name == "privacy")
				and type(value) == "string"
			then Localization.enum("state", value)
			else value
	end
	local result = Localization.format(key, arguments)
	if not result.ok then
		return false
	end
	label.Text = result.value
	return true
end

function WorldMessages.set(label: TextLabel, key: string, arguments: { [string]: any }?): boolean
	local entry = entryFor(key)
	if entry == nil then
		return false
	end
	local values = arguments or {}
	-- Validate before changing any replicated presentation metadata.
	if not Localization.format(key, values, "en").ok then
		return false
	end
	for name in label:GetAttributes() do
		if string.sub(name, 1, #PREFIX) == PREFIX then
			label:SetAttribute(name, nil)
		end
	end
	for name, value in values do
		label:SetAttribute(PREFIX .. name, value)
	end
	label:SetAttribute("ATDMessageKey", key)
	label.AutoLocalize = false
	label.RichText = false
	return WorldMessages.render(label)
end

return table.freeze(WorldMessages)
