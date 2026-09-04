--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local DirectStudioContentSelection = require(script.Parent.Parent.ProductionServerPlayable.DirectStudioContentSelection)

local loaded = ConfigurationValidator.validateLoaded()
if not loaded.ok then
	error("expected loaded production configuration", 0)
end
local CONFIGURATION = loaded.value

local function resolve(isStudio: boolean, attributes: { [string]: unknown }): any
	return DirectStudioContentSelection.resolve(CONFIGURATION, isStudio, function(name)
		return attributes[name]
	end)
end

return TestHarness.suite("direct Studio content selection", {
	TestHarness.case(
		"never reads Studio attributes outside Studio and fails the direct path closed",
		function(assertions)
			local reads = 0
			local result = DirectStudioContentSelection.resolve(CONFIGURATION, false, function()
				reads += 1
				error("must not read", 0)
			end)
			assertions.isFalse(result.ok)
			if not result.ok then
				assertions.equal(result.error.code, "STUDIO_ONLY")
			end
			assertions.equal(reads, 0)
		end
	),

	TestHarness.case(
		"uses an explicit validated Studio pair and reads only the bounded attributes",
		function(assertions)
			local requested = {}
			local attributes = {
				[DirectStudioContentSelection.MAP_ATTRIBUTE] = "map:backyard-garden-v1",
				[DirectStudioContentSelection.DIFFICULTY_ATTRIBUTE] = "difficulty:easy-v1",
			}
			local result = DirectStudioContentSelection.resolve(CONFIGURATION, true, function(name)
				table.insert(requested, name)
				return attributes[name]
			end)
			assertions.isTrue(result.ok)
			if result.ok then
				assertions.equal(result.value.mapId, "map:backyard-garden-v1")
				assertions.equal(result.value.difficultyId, "difficulty:easy-v1")
				assertions.isTrue(result.value.overridden)
			end
			assertions.equal(#requested, 2)
			assertions.equal(requested[1], "ATDStudioMapId")
			assertions.equal(requested[2], "ATDStudioDifficultyId")
		end
	),

	TestHarness.case("defaults only when both attributes are absent", function(assertions)
		local absent = resolve(true, {})
		assertions.isTrue(absent.ok)
		if absent.ok then
			assertions.isFalse(absent.value.overridden)
		end
		local partial = resolve(true, {
			[DirectStudioContentSelection.MAP_ATTRIBUTE] = "map:backyard-garden-v1",
		})
		assertions.isFalse(partial.ok)
		if not partial.ok then
			assertions.equal(partial.error.code, "PARTIAL_SELECTION")
		end
	end),

	TestHarness.case("fails closed on malformed unsupported and unreadable pairs", function(assertions)
		local malformed = resolve(true, {
			[DirectStudioContentSelection.MAP_ATTRIBUTE] = "not-a-map",
			[DirectStudioContentSelection.DIFFICULTY_ATTRIBUTE] = "difficulty:easy-v1",
		})
		assertions.isFalse(malformed.ok)
		if not malformed.ok then
			assertions.equal(malformed.error.code, "INVALID_SELECTION")
		end
		local unsupported = resolve(true, {
			[DirectStudioContentSelection.MAP_ATTRIBUTE] = "map:phase07-graybox",
			[DirectStudioContentSelection.DIFFICULTY_ATTRIBUTE] = "difficulty:easy-v1",
		})
		assertions.isFalse(unsupported.ok)
		if not unsupported.ok then
			assertions.equal(unsupported.error.code, "INVALID_SELECTION")
		end
		local unreadable = DirectStudioContentSelection.resolve(CONFIGURATION, true, function()
			error("read failed", 0)
		end)
		assertions.isFalse(unreadable.ok)
		if not unreadable.ok then
			assertions.equal(unreadable.error.code, "ATTRIBUTE_READ_FAILED")
		end
	end),
})
