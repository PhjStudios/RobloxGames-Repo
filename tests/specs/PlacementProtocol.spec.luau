--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local Shared = game:GetService("ReplicatedStorage").Shared
local PayloadValidation = require(Shared.network.PayloadValidation)
local PlacementGeometry = require(Shared.match.PlacementGeometry)
local PlacementProtocol = require(Shared.match.PlacementProtocol)

local function occupiedSlot(slot: number): any
	return {
		kind = "Occupied",
		slot = slot,
		towerId = "tower:phase12-single",
		displayName = "Phase 12 Single",
		iconAssetKey = "test.phase12.single-icon",
		rangeStuds = 10,
		footprintRadiusStuds = 2,
		placementCost = 100,
		placementCount = 0,
		placementCap = 4,
		totalCount = 0,
		totalCap = PlacementProtocol.MAX_TOTAL_ACTIVE_PER_OWNER,
		globalCount = 0,
		globalCap = PlacementProtocol.MAX_QUERY_FOOTPRINTS,
		affordability = "Affordable",
		capState = "Available",
	}
end

local function querySnapshot(zoneCount: number?, exclusionCount: number?, footprintCount: number?): any
	local zones = {}
	for index = 1, zoneCount or 1 do
		table.insert(zones, {
			cframe = CFrame.new(index * 2, -4, 0),
			size = Vector3.new(2, 2, 2),
			surfaceCategory = if index % 3 == 0 then "Water" else "Land",
		})
	end
	local exclusions = {}
	for index = 1, exclusionCount or 0 do
		table.insert(exclusions, {
			cframe = CFrame.new(index, -4, index),
			size = Vector3.new(1, 1, 1),
		})
	end
	local footprints = {}
	for index = 1, footprintCount or 0 do
		table.insert(footprints, Vector3.new(index, 1, -index))
	end
	return {
		contractVersion = 1,
		matchId = "match:phase13-protocol",
		mapId = "map:phase07-graybox",
		queryRevision = 1,
		loadoutRevision = 1,
		bounds = { cframe = CFrame.new(), size = Vector3.new(200, 20, 200) },
		placementZones = zones,
		exclusions = exclusions,
		footprints = footprints,
		slots = {
			occupiedSlot(1),
			{ kind = "Empty", slot = 2 },
			{ kind = "Empty", slot = 3 },
			{ kind = "Empty", slot = 4 },
			{ kind = "Empty", slot = 5 },
		},
	}
end

return TestHarness.suite("Phase 13 placement wire protocol", {
	TestHarness.case("publishes the exact endpoints versions and technical ceilings", function(assertions)
		assertions.equal(PlacementProtocol.CONTRACT_VERSION, 1)
		assertions.equal(PlacementProtocol.GET_QUERY_ENDPOINT, "GetTowerPlacementQuery")
		assertions.equal(PlacementProtocol.SUBMIT_PLACEMENT_ENDPOINT, "SubmitTowerPlacement")
		assertions.equal(PlacementProtocol.REVISION_ENDPOINT, "TowerPlacementRevision")
		assertions.equal(PlacementProtocol.MAX_QUERY_PLACEMENT_ZONES, 24)
		assertions.equal(PlacementProtocol.MAX_QUERY_EXCLUSIONS, 24)
		assertions.equal(PlacementProtocol.MAX_QUERY_FOOTPRINTS, 128)
		assertions.equal(PlacementProtocol.MAX_LOADOUT_SLOTS, 5)
		assertions.equal(PlacementProtocol.MAX_QUERY_REVISION_LAG, 4)
		assertions.isTrue(PayloadValidation.isSchema(PlacementProtocol.QuerySnapshotSchema))
	end),

	TestHarness.case("accepts only the exact empty query payload", function(assertions)
		assertions.isTrue(PlacementProtocol.GetQueryPayloadSchema:validate({}).ok)
		assertions.isFalse(PlacementProtocol.GetQueryPayloadSchema:validate({ matchId = "match:x" }).ok)
		assertions.isFalse(PlacementProtocol.GetQueryPayloadSchema:validate("query").ok)
	end),

	TestHarness.case("canonicalizes a bounded placement intent", function(assertions)
		local result = PlacementProtocol.validatePlacementIntent({
			matchId = "match:phase13-protocol",
			observedQueryRevision = 7,
			loadoutRevision = 2,
			slot = 3,
			positionXZ = Vector2.new(10, -20),
			yawDegrees = -90,
		})
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.isTrue(table.isfrozen(result.value))
			assertions.equal(result.value.positionXZ, Vector2.new(10, -20))
			assertions.equal(PlacementGeometry.normalizeYawDegrees(result.value.yawDegrees), 270)
		end
	end),

	TestHarness.case("rejects nonfinite unsafe and hostile intent numbers", function(assertions)
		for _, position in
			{
				Vector2.new(0 / 0, 0),
				Vector2.new(math.huge, 0),
				Vector2.new(-math.huge, 0),
				Vector2.new(100_001, 0),
			}
		do
			local result = PlacementProtocol.validatePlacementIntent({
				matchId = "match:phase13-protocol",
				observedQueryRevision = 1,
				loadoutRevision = 1,
				slot = 1,
				positionXZ = position,
				yawDegrees = 0,
			})
			assertions.isFalse(result.ok)
		end
		for _, yaw in { 0 / 0, math.huge, -math.huge, 361, -361 } do
			assertions.isFalse(PlacementProtocol.validatePlacementIntent({
				matchId = "match:phase13-protocol",
				observedQueryRevision = 1,
				loadoutRevision = 1,
				slot = 1,
				positionXZ = Vector2.new(),
				yawDegrees = yaw,
			}).ok)
		end
	end),

	TestHarness.case("rejects transform authority extra fields and malformed shapes", function(assertions)
		local base: any = {
			matchId = "match:phase13-protocol",
			observedQueryRevision = 1,
			loadoutRevision = 1,
			slot = 1,
			positionXZ = Vector2.new(),
			yawDegrees = 0,
		}
		for _, field in
			{
				"ownerUserId",
				"towerId",
				"unitId",
				"runtimeTowerId",
				"placementCFrame",
				"pitch",
				"roll",
				"cost",
				"cap",
				"model",
			}
		do
			local hostile = table.clone(base)
			hostile[field] = if field == "placementCFrame" then CFrame.new() else "forged"
			assertions.isFalse(PlacementProtocol.validatePlacementIntent(hostile).ok)
		end
		base.positionXZ = { X = 0, Y = 0 }
		assertions.isFalse(PlacementProtocol.validatePlacementIntent(base).ok)
	end),

	TestHarness.case("accepts a detached client-safe query snapshot", function(assertions)
		local result = PlacementProtocol.validateQuerySnapshot(querySnapshot())
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.isTrue(table.isfrozen(result.value))
			assertions.isTrue(table.isfrozen(result.value.slots))
			assertions.isTrue(table.isfrozen(result.value.slots[1]))
			assertions.equal(result.value.slots[1].towerId, "tower:phase12-single")
		end
	end),

	TestHarness.case("fits the maximum client-safe snapshot inside the shared node budget", function(assertions)
		local maximum = querySnapshot(24, 24, 128)
		maximum.slots = {
			occupiedSlot(1),
			occupiedSlot(2),
			occupiedSlot(3),
			occupiedSlot(4),
			occupiedSlot(5),
		}
		local result = PlacementProtocol.validateQuerySnapshot(maximum)
		assertions.isTrue(result.ok)
	end),

	TestHarness.case("rejects query privacy and mutation authority fields", function(assertions)
		for _, field in
			{ "players", "owners", "unitIds", "runtimeTowerIds", "capabilities", "instances", "definitions" }
		do
			local snapshot = querySnapshot()
			snapshot[field] = {}
			assertions.isFalse(PlacementProtocol.validateQuerySnapshot(snapshot).ok)
		end
		for _, field in { "unitId", "ownerUserId", "modelAssetKey", "capability" } do
			local snapshot = querySnapshot()
			snapshot.slots[1][field] = "forged"
			assertions.isFalse(PlacementProtocol.validateQuerySnapshot(snapshot).ok)
		end
	end),

	TestHarness.case("enforces exact slot shape order and cap consistency", function(assertions)
		local unordered = querySnapshot()
		unordered.slots[2].slot = 3
		assertions.isFalse(PlacementProtocol.validateQuerySnapshot(unordered).ok)

		local missing = querySnapshot()
		missing.slots[1].displayName = nil
		assertions.isFalse(PlacementProtocol.validateQuerySnapshot(missing).ok)

		local emptyExtra = querySnapshot()
		emptyExtra.slots[2].towerId = "tower:phase12-single"
		assertions.isFalse(PlacementProtocol.validateQuerySnapshot(emptyExtra).ok)

		local wrongCap = querySnapshot()
		wrongCap.slots[1].placementCount = 4
		wrongCap.slots[1].capState = "Available"
		assertions.isFalse(PlacementProtocol.validateQuerySnapshot(wrongCap).ok)
	end),

	TestHarness.case("accepts declared water but rejects malformed surface and footprint records", function(assertions)
		local water = querySnapshot()
		water.placementZones[1].surfaceCategory = "Water"
		assertions.isTrue(PlacementProtocol.validateQuerySnapshot(water).ok)
		water.placementZones[1].surfaceCategory = "Air"
		assertions.isFalse(PlacementProtocol.validateQuerySnapshot(water).ok)

		local footprint = querySnapshot()
		footprint.footprints = { Vector3.new(0, -1, 0) }
		assertions.isFalse(PlacementProtocol.validateQuerySnapshot(footprint).ok)
	end),

	TestHarness.case("rejects oversized query arrays without partial acceptance", function(assertions)
		assertions.isFalse(PlacementProtocol.validateQuerySnapshot(querySnapshot(25, 0, 0)).ok)
		assertions.isFalse(PlacementProtocol.validateQuerySnapshot(querySnapshot(1, 25, 0)).ok)
		assertions.isFalse(PlacementProtocol.validateQuerySnapshot(querySnapshot(1, 0, 129)).ok)
	end),

	TestHarness.case("validates accepted and privacy-safe rejected receipts", function(assertions)
		local accepted = PlacementProtocol.validateReceipt({
			state = "Accepted",
			runtimeTowerId = 7,
			placementCFrame = CFrame.new(1, 2, 3) * CFrame.Angles(0, math.rad(45), 0),
			queryRevision = 2,
		})
		assertions.isTrue(accepted.ok)
		assertions.isFalse(PlacementProtocol.validateReceipt({
			state = "Accepted",
			runtimeTowerId = 7,
			placementCFrame = CFrame.Angles(math.rad(5), 0, 0),
			queryRevision = 2,
		}).ok)
		assertions.isTrue(PlacementProtocol.validateReceipt({
			state = "Rejected",
			reason = "Occupied",
			queryRevision = 2,
		}).ok)
		assertions.isFalse(PlacementProtocol.validateReceipt({
			state = "Rejected",
			reason = "OtherPlayerAtPosition",
			queryRevision = 2,
		}).ok)
	end),

	TestHarness.case("validates only the bounded revision notification shape", function(assertions)
		assertions.isTrue(PlacementProtocol.RevisionEventSchema:validate({
			matchId = "match:phase13-protocol",
			queryRevision = 2,
		}).ok)
		assertions.isFalse(PlacementProtocol.RevisionEventSchema:validate({
			matchId = "match:phase13-protocol",
			queryRevision = 2,
			ownerUserId = 1,
		}).ok)
	end),
})
