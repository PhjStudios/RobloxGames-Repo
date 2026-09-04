--!strict

-- Stable identity policy shared by server-owned selection, onboarding, Studio
-- authoring, and client presentation. Gameplay statistics remain authoritative
-- in their dedicated validated catalogs.
local DART_STARTER_TOWER_ID = "tower:dart-ant"
local BOMBARDIER_STARTER_TOWER_ID = "tower:bombardier-ant"

local function hasTag(definition: any, expected: string): boolean
	if type(definition) ~= "table" or type(definition.tags) ~= "table" then
		return false
	end
	for _, tag in definition.tags do
		if tag == expected then
			return true
		end
	end
	return false
end

local function rewardingForSelection(configuration: any, mapId: unknown, difficultyId: unknown): boolean?
	if
		type(configuration) ~= "table"
		or type(mapId) ~= "string"
		or type(difficultyId) ~= "string"
		or type(configuration.maps) ~= "table"
		or type(configuration.maps.byId) ~= "table"
		or type(configuration.difficulties) ~= "table"
		or type(configuration.difficulties.byId) ~= "table"
	then
		return nil
	end
	local map = configuration.maps.byId[mapId]
	local difficulty = configuration.difficulties.byId[difficultyId]
	if type(map) ~= "table" or type(difficulty) ~= "table" or type(map.supportedDifficultyIds) ~= "table" then
		return nil
	end
	local supported = false
	for _, supportedDifficultyId in map.supportedDifficultyIds do
		supported = supported or supportedDifficultyId == difficultyId
	end
	if not supported then
		return nil
	end
	return not hasTag(map, "non-rewarding") and not hasTag(difficulty, "non-rewarding")
end

local ContentSelection = {
	CONTENT_VERSION = 1,

	DEVELOPMENT_MAP_ID = "map:phase07-graybox",
	DEVELOPMENT_DIFFICULTY_ID = "difficulty:local",

	RELEASE_MAP_ID = "map:backyard-garden-v1",
	EASY_DIFFICULTY_ID = "difficulty:easy-v1",
	NORMAL_DIFFICULTY_ID = "difficulty:normal-v1",
	HARD_DIFFICULTY_ID = "difficulty:hard-v1",
	ENDLESS_DIFFICULTY_ID = "difficulty:endless-v1",

	RELEASE_BANNER_ID = "banner:garden-v1",
	ENDLESS_GENERATOR_KEY = "wave-generator.garden-v1",

	PLAYABLE_TEMPLATE_ROOT_NAME = "ATDPlayableTemplates",
	PLAYABLE_TEMPLATE_CONTRACT_VERSION = "playable-local-match-v1",

	DART_STARTER_UNIT_ID = "unit:starter-1",
	BOMBARDIER_STARTER_UNIT_ID = "unit:starter-2",
	DART_STARTER_TOWER_ID = DART_STARTER_TOWER_ID,
	BOMBARDIER_STARTER_TOWER_ID = BOMBARDIER_STARTER_TOWER_ID,
	rewardingForSelection = rewardingForSelection,
	STARTER_TOWER_IDS = table.freeze({
		DART_STARTER_TOWER_ID,
		BOMBARDIER_STARTER_TOWER_ID,
	}),
	STARTER_UNIT_IDS = table.freeze({
		"unit:starter-1",
		"unit:starter-2",
	}),
	RELEASE_DIFFICULTY_IDS = table.freeze({
		"difficulty:easy-v1",
		"difficulty:normal-v1",
		"difficulty:hard-v1",
		"difficulty:endless-v1",
	}),
}

return table.freeze(ContentSelection)
