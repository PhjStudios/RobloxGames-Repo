--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local MatchLoadoutProtocol = require(ReplicatedStorage.Shared.match.MatchLoadoutProtocol)

local loaded = ConfigurationValidator.validateLoaded()
if not loaded.ok then
	error("expected production configuration", 0)
end
local configuration = loaded.value

local function loadout(count: number): any
	local slots = {}
	for index = 1, count do
		local tower = configuration.towers.ordered[index]
		table.insert(slots, {
			slot = index,
			unitId = `unit:loadout-{index}`,
			towerId = tower.id,
		})
	end
	return {
		userId = 42,
		revision = 7,
		slots = slots,
		settings = configuration.defaultSettings,
	}
end

return TestHarness.suite("authenticated match loadout protocol", {
	TestHarness.case("detaches and freezes one through five bounded equipped slots", function(assertions)
		for count = 1, #configuration.towers.ordered do
			local raw = loadout(count)
			local result = MatchLoadoutProtocol.validate(raw, configuration)
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.isTrue(table.isfrozen(result.value))
				assertions.isTrue(table.isfrozen(result.value.slots))
				assertions.isTrue(table.isfrozen(result.value.settings))
				assertions.notEqual(result.value, raw)
				assertions.equal(#result.value.slots, count)
			end
		end
	end),
	TestHarness.case("rejects empty sparse and over-capacity loadouts", function(assertions)
		assertions.isFalse(MatchLoadoutProtocol.validate(loadout(0), configuration).ok)
		local sparse = loadout(2)
		sparse.slots[4] = sparse.slots[2]
		sparse.slots[2] = nil
		assertions.isFalse(MatchLoadoutProtocol.validate(sparse, configuration).ok)
		local over = loadout(3)
		for index = 4, 6 do
			over.slots[index] = { slot = index, unitId = `unit:over-{index}`, towerId = "tower:dart-ant" }
		end
		assertions.isFalse(MatchLoadoutProtocol.validate(over, configuration).ok)
	end),
	TestHarness.case("rejects duplicate tower definitions and unit records", function(assertions)
		local duplicateTower = loadout(2)
		duplicateTower.slots[2].towerId = duplicateTower.slots[1].towerId
		assertions.isFalse(MatchLoadoutProtocol.validate(duplicateTower, configuration).ok)
		local duplicateUnit = loadout(2)
		duplicateUnit.slots[2].unitId = duplicateUnit.slots[1].unitId
		assertions.isFalse(MatchLoadoutProtocol.validate(duplicateUnit, configuration).ok)
	end),
	TestHarness.case("rejects unknown towers and forged authenticated configuration", function(assertions)
		local unknown = loadout(1)
		unknown.slots[1].towerId = "tower:unknown"
		assertions.isFalse(MatchLoadoutProtocol.validate(unknown, configuration).ok)
		assertions.isFalse(MatchLoadoutProtocol.validate(loadout(1), table.clone(configuration) :: any).ok)
	end),
	TestHarness.case("rejects stale-shaped revisions users and unexpected private fields", function(assertions)
		local badRevision = loadout(1)
		badRevision.revision = 0
		assertions.isFalse(MatchLoadoutProtocol.validate(badRevision, configuration).ok)
		local badUser = loadout(1)
		badUser.userId = 0
		assertions.isFalse(MatchLoadoutProtocol.validate(badUser, configuration).ok)
		badUser.userId = -1
		assertions.isFalse(MatchLoadoutProtocol.validate(badUser, configuration).ok)
		local private = loadout(1)
		private.sessionLock = "PRIVATE"
		assertions.isFalse(MatchLoadoutProtocol.validate(private, configuration).ok)
		local malformedSettings = loadout(1)
		malformedSettings.settings = table.clone(configuration.defaultSettings)
		malformedSettings.settings.uiScale = 5
		assertions.isFalse(MatchLoadoutProtocol.validate(malformedSettings, configuration).ok)
	end),
})
