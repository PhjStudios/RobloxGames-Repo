--!strict

local ContentSelection = require(game:GetService("ReplicatedStorage").Shared.config.ContentSelection)

local function choices(values: { string }): any
	local allowed = {}
	for _, value in values do
		allowed[value] = true
	end
	return table.freeze({ kind = "enum", values = table.freeze(allowed) })
end

local function integer(maximum: number): any
	return table.freeze({ kind = "integer", maximum = maximum })
end

local category =
	choices({ "profile", "ticket", "teleport", "configuration", "match", "reward", "analytics", "security" })
local failureCode = choices({ "Unavailable", "InvalidState", "Rejected", "TimedOut", "Capacity", "DeliveryFailed" })
local definitions = {
	["onboarding.v1"] = {
		action = choices({ "Initialized", "Advanced", "Skipped", "Replayed", "Completed" }),
		step = integer(16),
	},
	["party.v1"] = {
		action = choices({ "Created", "InvitationChanged", "MembershipChanged", "Disbanded" }),
		members = integer(4),
	},
	["queue.v1"] = {
		action = choices({ "Entered", "Cancelled", "Started", "Failed" }),
		members = integer(4),
	},
	["travel.v1"] = {
		action = choices({ "Requested", "Admitted", "Failed", "Returned", "Recovered" }),
		failureClass = choices({ "None", "Retryable", "Terminal" }),
	},
	["match.v1"] = {
		action = choices({ "Ready", "Started", "Terminal", "Returned" }),
		map = choices({ ContentSelection.RELEASE_MAP_ID, ContentSelection.DEVELOPMENT_MAP_ID }),
		difficulty = choices({
			ContentSelection.EASY_DIFFICULTY_ID,
			ContentSelection.NORMAL_DIFFICULTY_ID,
			ContentSelection.HARD_DIFFICULTY_ID,
			ContentSelection.ENDLESS_DIFFICULTY_ID,
			ContentSelection.DEVELOPMENT_DIFFICULTY_ID,
		}),
		outcome = choices({ "None", "Victory", "Defeat" }),
		waveBucket = integer(20),
	},
	["gold.v1"] = {
		direction = choices({ "Source", "Sink" }),
		reason = choices({ "MatchReward", "Chest" }),
		amountBucket = integer(100),
	},
	["acquisition.v1"] = { quantity = integer(10), newCount = integer(10), pityBucket = integer(20) },
	["operational.v1"] = { category = category, code = failureCode },
}
for _, definition in definitions do
	table.freeze(definition)
end
table.freeze(definitions)

local Dictionary = { VERSION = 1, CONTENT_VERSION = ContentSelection.CONTENT_VERSION, DEFINITIONS = definitions }

function Dictionary.validate(name: unknown, fields: unknown): any?
	if type(name) ~= "string" or type(fields) ~= "table" or getmetatable(fields) ~= nil then
		return nil
	end
	local definition = definitions[name]
	if definition == nil then
		return nil
	end
	local copy = {}
	for field, value in fields do
		local rule = definition[field]
		if rule == nil then
			return nil
		end
		if rule.kind == "enum" then
			if type(value) ~= "string" or rule.values[value] ~= true then
				return nil
			end
		elseif type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < 0 or value > rule.maximum then
			return nil
		end
		copy[field] = value
	end
	for field in definition do
		if copy[field] == nil then
			return nil
		end
	end
	return table.freeze(copy)
end

return table.freeze(Dictionary)
