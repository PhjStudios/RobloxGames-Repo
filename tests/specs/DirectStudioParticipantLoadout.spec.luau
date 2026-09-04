--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local MatchLoadoutProtocol = require(ReplicatedStorage.Shared.match.MatchLoadoutProtocol)

local DirectStudioParticipantLoadout =
	require(script.Parent.Parent.ProductionServerPlayable.DirectStudioParticipantLoadout)

local loaded = ConfigurationValidator.validateLoaded()
if not loaded.ok then
	error("expected production configuration", 0)
end
local configuration = loaded.value

return TestHarness.suite("direct Studio participant loadout", {
	TestHarness.case(
		"creates the frozen deterministic starter while preserving the negative owner",
		function(assertions)
			local first = DirectStudioParticipantLoadout.create(-4, configuration)
			local second = DirectStudioParticipantLoadout.create(-4, configuration)
			assertions.isTrue(first.ok)
			assertions.isTrue(second.ok)
			if not first.ok or not second.ok then
				return
			end
			assertions.isTrue(table.isfrozen(first.value))
			assertions.isTrue(table.isfrozen(first.value.slots))
			assertions.equal(first.value.userId, -4)
			assertions.equal(first.value.revision, 1)
			assertions.equal(#first.value.slots, 2)
			for index, slot in first.value.slots do
				assertions.equal(slot.slot, second.value.slots[index].slot)
				assertions.equal(slot.unitId, second.value.slots[index].unitId)
				assertions.equal(slot.towerId, second.value.slots[index].towerId)
			end
			assertions.equal(first.value.slots[1].unitId, "unit:starter-1")
			assertions.equal(first.value.slots[1].towerId, "tower:dart-ant")
			assertions.equal(first.value.slots[2].unitId, "unit:starter-2")
			assertions.equal(first.value.slots[2].towerId, "tower:bombardier-ant")
			assertions.isFalse(MatchLoadoutProtocol.validate(first.value, configuration).ok)
		end
	),

	TestHarness.case("rejects non-Studio identities malformed content and forged configuration", function(assertions)
		assertions.isFalse(DirectStudioParticipantLoadout.create(1, configuration).ok)
		assertions.isFalse(DirectStudioParticipantLoadout.create(0, configuration).ok)
		assertions.isFalse(DirectStudioParticipantLoadout.create(-1.5, configuration).ok)
		assertions.isFalse(DirectStudioParticipantLoadout.create(-1, table.clone(configuration)).ok)

		local created = DirectStudioParticipantLoadout.create(-1, configuration)
		assertions.isTrue(created.ok)
		if not created.ok then
			return
		end
		local forged = table.clone(created.value)
		forged.slots = table.clone(created.value.slots)
		forged.slots[1] = table.clone(forged.slots[1])
		forged.slots[1].towerId = "tower:unknown"
		assertions.isFalse(DirectStudioParticipantLoadout.validate(forged, configuration).ok)
	end),
})
