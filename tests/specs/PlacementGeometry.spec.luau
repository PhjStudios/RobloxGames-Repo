--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local PlacementGeometry = require(game:GetService("ReplicatedStorage").Shared.match.PlacementGeometry)

local BOUNDS = table.freeze({
	cframe = CFrame.new(0, 0, 0),
	size = Vector3.new(100, 20, 100),
})

local LAND_ZONE = table.freeze({
	cframe = CFrame.new(0, -4, 0),
	size = Vector3.new(80, 2, 80),
	surfaceCategory = "Land",
})

local function evaluate(
	position: Vector2,
	radius: number,
	zones: { any }?,
	exclusions: { any }?,
	footprints: { Vector3 }?
): any
	return PlacementGeometry.evaluate(
		position,
		radius,
		BOUNDS,
		zones or { LAND_ZONE },
		exclusions or {},
		footprints or {}
	)
end

return TestHarness.suite("shared deterministic placement geometry", {
	TestHarness.case("publishes the reviewed numeric and surface bounds", function(assertions)
		assertions.equal(PlacementGeometry.MAX_COORDINATE, 100_000)
		assertions.equal(PlacementGeometry.MAX_RADIUS, 4_096)
		assertions.isTrue(PlacementGeometry.isSurfaceCategory("Land"))
		assertions.isTrue(PlacementGeometry.isSurfaceCategory("Elevated"))
		assertions.isTrue(PlacementGeometry.isSurfaceCategory("Water"))
		assertions.isTrue(PlacementGeometry.isApprovedSurface("Land"))
		assertions.isTrue(PlacementGeometry.isApprovedSurface("Elevated"))
		assertions.isFalse(PlacementGeometry.isApprovedSurface("Water"))
		assertions.isFalse(PlacementGeometry.isSurfaceCategory("Air"))
	end),

	TestHarness.case("normalizes bounded yaw deterministically", function(assertions)
		assertions.equal(PlacementGeometry.normalizeYawDegrees(0), 0)
		assertions.equal(PlacementGeometry.normalizeYawDegrees(-0), 0)
		assertions.equal(PlacementGeometry.normalizeYawDegrees(360), 0)
		assertions.equal(PlacementGeometry.normalizeYawDegrees(-90), 270)
		assertions.equal(PlacementGeometry.normalizeYawDegrees(45.5), 45.5)
		assertions.isNil(PlacementGeometry.normalizeYawDegrees(361))
		assertions.isNil(PlacementGeometry.normalizeYawDegrees(0 / 0))
		assertions.isNil(PlacementGeometry.normalizeYawDegrees(math.huge))
	end),

	TestHarness.case("accepts upright yaw regions and rejects pitch or roll", function(assertions)
		assertions.isTrue(PlacementGeometry.isUprightYawCFrame(CFrame.Angles(0, math.rad(37), 0)))
		assertions.isFalse(PlacementGeometry.isUprightYawCFrame(CFrame.Angles(math.rad(1), 0, 0)))
		assertions.isFalse(PlacementGeometry.isUprightYawCFrame(CFrame.Angles(0, 0, math.rad(1))))
		assertions.isFalse(PlacementGeometry.isUprightYawCFrame(CFrame.new(100_001, 0, 0)))
		assertions.isFalse(PlacementGeometry.isUprightYawCFrame("CFrame"))
	end),

	TestHarness.case("evaluates an upright oriented zone in object space", function(assertions)
		local oriented = table.freeze({
			cframe = CFrame.new(10, 4, -5) * CFrame.Angles(0, math.rad(45), 0),
			size = Vector3.new(20, 2, 8),
			surfaceCategory = "Elevated",
		})
		local center = Vector2.new(10, -5)
		local result = PlacementGeometry.evaluate(center, 2, BOUNDS, { oriented }, {}, {})
		assertions.isTrue(result.valid)
		assertions.equal(result.reason, "Valid")
		assertions.equal(result.surfaceCategory, "Elevated")
		assertions.equal(result.position, Vector3.new(10, 5, -5))
		assertions.equal(result.zoneIndex, 1)
	end),

	TestHarness.case("requires full-footprint containment while allowing boundary contact", function(assertions)
		local touching = evaluate(Vector2.new(38, 0), 2)
		assertions.isTrue(touching.valid)
		local partial = evaluate(Vector2.new(38.01, 0), 2)
		assertions.isFalse(partial.valid)
		assertions.equal(partial.reason, "OutsideZone")
		local outsideBounds = evaluate(Vector2.new(49, 0), 2)
		assertions.isFalse(outsideBounds.valid)
		assertions.equal(outsideBounds.reason, "InvalidPosition")
	end),

	TestHarness.case("allows exact exclusion tangency and rejects positive penetration", function(assertions)
		local exclusion = table.freeze({
			cframe = CFrame.new(10, -4, 0),
			size = Vector3.new(4, 2, 4),
		})
		local tangent = evaluate(Vector2.new(6, 0), 2, nil, { exclusion })
		assertions.isTrue(tangent.valid)
		local penetrates = evaluate(Vector2.new(6.001, 0), 2, nil, { exclusion })
		assertions.isFalse(penetrates.valid)
		assertions.equal(penetrates.reason, "Excluded")
	end),

	TestHarness.case("allows exact tower tangency and rejects positive overlap", function(assertions)
		local existing = PlacementGeometry.encodeFootprint(Vector2.new(10, 0), 3)
		assertions.isNotNil(existing)
		local tangent = evaluate(Vector2.new(5, 0), 2, nil, nil, { existing :: Vector3 })
		assertions.isTrue(tangent.valid)
		local overlap = evaluate(Vector2.new(5.01, 0), 2, nil, nil, { existing :: Vector3 })
		assertions.isFalse(overlap.valid)
		assertions.equal(overlap.reason, "Occupied")
	end),

	TestHarness.case("derives height only from the selected zone top face", function(assertions)
		assertions.equal(PlacementGeometry.groundHeight(LAND_ZONE), -3)
		local result = evaluate(Vector2.new(0, 0), 1)
		assertions.equal(result.position, Vector3.new(0, -3, 0))
	end),

	TestHarness.case("keeps the future water surface inert", function(assertions)
		local water = table.freeze({
			cframe = LAND_ZONE.cframe,
			size = LAND_ZONE.size,
			surfaceCategory = "Water",
		})
		local result = evaluate(Vector2.new(0, 0), 1, { water })
		assertions.isFalse(result.valid)
		assertions.equal(result.reason, "InvalidSurface")
	end),

	TestHarness.case("rejects no containing zone and ambiguous multiple zones", function(assertions)
		local none = evaluate(Vector2.new(0, 0), 1, {})
		assertions.isFalse(none.valid)
		assertions.equal(none.reason, "OutsideZone")
		local duplicate = evaluate(Vector2.new(0, 0), 1, { LAND_ZONE, LAND_ZONE })
		assertions.isFalse(duplicate.valid)
		assertions.equal(duplicate.reason, "OutsideZone")
	end),

	TestHarness.case("encodes only bounded positive footprints", function(assertions)
		local encoded = PlacementGeometry.encodeFootprint(Vector2.new(-7, 9), 2.5)
		assertions.equal(encoded, Vector3.new(-7, 2.5, 9))
		local position, radius = PlacementGeometry.decodeFootprint(encoded)
		assertions.equal(position, Vector2.new(-7, 9))
		assertions.equal(radius, 2.5)
		assertions.isNil(PlacementGeometry.encodeFootprint(Vector2.new(0, 0), 0))
		assertions.isNil(PlacementGeometry.encodeFootprint(Vector2.new(100_001, 0), 1))
		local invalidPosition, invalidRadius = PlacementGeometry.decodeFootprint(Vector3.new(0, -1, 0))
		assertions.isNil(invalidPosition)
		assertions.isNil(invalidRadius)
	end),

	TestHarness.case("fails closed for malformed and nonfinite candidate values", function(assertions)
		local nonfinite = PlacementGeometry.evaluate(Vector2.new(0 / 0, 0), 1, BOUNDS, { LAND_ZONE }, {}, {})
		assertions.isFalse(nonfinite.valid)
		assertions.equal(nonfinite.reason, "InvalidPosition")
		assertions.isFalse(evaluate(Vector2.new(0, 0), 0).valid)
		assertions.isFalse(evaluate(Vector2.new(0, 0), 4_097).valid)
		assertions.isTrue(PlacementGeometry.circleIntersectsRegion(Vector2.new(0, 0), 1, {}))
	end),

	TestHarness.case("returns frozen deterministic outcomes", function(assertions)
		local first = evaluate(Vector2.new(1, 2), 1)
		local second = evaluate(Vector2.new(1, 2), 1)
		assertions.isTrue(table.isfrozen(first))
		assertions.isTrue(table.isfrozen(second))
		assertions.equal(first.valid, second.valid)
		assertions.equal(first.reason, second.reason)
		assertions.equal(first.position, second.position)
	end),
})
