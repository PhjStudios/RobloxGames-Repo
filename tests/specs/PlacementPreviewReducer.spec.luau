--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local PlacementPreviewReducer = require(script.Parent.Parent.ProductionClientPlacement.PlacementPreviewReducer)

local function occupied(slot: number, affordability: string?, capState: string?): any
	local selectedCap = capState or "Available"
	return {
		kind = "Occupied",
		slot = slot,
		towerId = `tower:preview-{slot}`,
		displayName = `Preview {slot}`,
		iconAssetKey = `test.preview.{slot}`,
		rangeStuds = 10 + slot,
		footprintRadiusStuds = 2,
		placementCost = 100,
		placementCount = if selectedCap == "PerTypeCapped" then 2 else 0,
		placementCap = 2,
		totalCount = if selectedCap == "TotalCapped" then 32 else 0,
		totalCap = 32,
		globalCount = 0,
		globalCap = 128,
		affordability = affordability or "Affordable",
		capState = selectedCap,
	}
end

local function snapshot(revision: number?, matchId: string?): any
	return {
		contractVersion = 1,
		matchId = matchId or "match:phase13-preview",
		mapId = "map:phase07-graybox",
		queryRevision = revision or 1,
		loadoutRevision = 2,
		bounds = { cframe = CFrame.new(), size = Vector3.new(120, 20, 120) },
		placementZones = {
			{ cframe = CFrame.new(0, -4, 0), size = Vector3.new(100, 2, 100), surfaceCategory = "Land" },
		},
		exclusions = {
			{ cframe = CFrame.new(20, -4, 0), size = Vector3.new(6, 2, 6) },
		},
		footprints = { Vector3.new(40, 2, 0) },
		slots = {
			occupied(1),
			occupied(2, "Unaffordable"),
			occupied(3, "Affordable", "PerTypeCapped"),
			{ kind = "Empty", slot = 4 },
			occupied(5),
		},
	}
end

local function reducer(): any
	local result = PlacementPreviewReducer.new()
	if not result.ok then
		error("preview reducer fixture failed", 0)
	end
	return result.value
end

local function state(value: any): any
	local result = value:getState()
	if not result.ok then
		error("preview reducer state read failed", 0)
	end
	return result.value
end

return TestHarness.suite("Phase 13 placement preview reducer", {
	TestHarness.case("starts idle with desktop hints and no mutation authority", function(assertions)
		local value = reducer()
		local current = state(value)
		assertions.isTrue(table.isfrozen(current))
		assertions.equal(current.phase, "Idle")
		assertions.equal(current.preferredInput, "Desktop")
		assertions.isNil(current.snapshot)
		assertions.isFalse(current.canConfirm)
	end),

	TestHarness.case("accepts one bounded query and selects only occupied dense slots", function(assertions)
		local value = reducer()
		local applied = value:observeQuery(snapshot())
		assertions.isTrue(applied.ok)
		assertions.equal(applied.value.kind, "Applied")
		assertions.isTrue(table.isfrozen(state(value).snapshot))
		assertions.isTrue(value:selectSlot(1).ok)
		assertions.equal(state(value).phase, "Selected")
		assertions.equal(state(value).selectedMetadata.towerId, "tower:preview-1")
		assertions.isFalse(value:selectSlot(4).ok)
		assertions.isFalse(value:selectSlot(0).ok)
	end),

	TestHarness.case("uses shared geometry for valid exclusions overlap and bounds", function(assertions)
		local value = reducer()
		value:observeQuery(snapshot())
		value:selectSlot(1)

		assertions.isTrue(value:setPosition(Vector2.new(0, 0)).ok)
		assertions.equal(state(value).validity, "Valid")
		assertions.equal(state(value).worldPosition, Vector3.new(0, -3, 0))
		assertions.isTrue(state(value).canConfirm)

		value:setPosition(Vector2.new(20, 0))
		assertions.equal(state(value).validity, "Excluded")
		assertions.isFalse(state(value).canConfirm)

		value:setPosition(Vector2.new(40, 0))
		assertions.equal(state(value).validity, "Occupied")

		value:setPosition(Vector2.new(55, 0))
		assertions.equal(state(value).validity, "OutsideZone")
	end),

	TestHarness.case("shows unaffordable and capped states in addition to geometry", function(assertions)
		local value = reducer()
		value:observeQuery(snapshot())
		value:selectSlot(2)
		value:setPosition(Vector2.new(0, 0))
		assertions.equal(state(value).validity, "Unaffordable")
		assertions.isFalse(state(value).canConfirm)

		value:selectSlot(3)
		assertions.equal(state(value).validity, "Capped")
		assertions.isFalse(state(value).canConfirm)
	end),

	TestHarness.case("rotates deliberately and submits only exact bounded intent", function(assertions)
		local value = reducer()
		value:observeQuery(snapshot())
		value:selectSlot(1)
		value:setPosition(Vector2.new(-10, 5))
		assertions.isTrue(value:rotate(-90).ok)
		assertions.equal(state(value).yawDegrees, 270)
		assertions.isTrue(value:rotate(105).ok)
		assertions.equal(state(value).yawDegrees, 15)

		local submitted = value:beginSubmit()
		assertions.isTrue(submitted.ok)
		assertions.equal(state(value).phase, "Submitting")
		assertions.equal(submitted.value.matchId, "match:phase13-preview")
		assertions.equal(submitted.value.observedQueryRevision, 1)
		assertions.equal(submitted.value.loadoutRevision, 2)
		assertions.equal(submitted.value.slot, 1)
		assertions.equal(submitted.value.positionXZ, Vector2.new(-10, 5))
		assertions.equal(submitted.value.yawDegrees, 15)
		assertions.isNil((submitted.value :: any).towerId)
		assertions.isNil((submitted.value :: any).placementCFrame)
		assertions.isFalse(value:beginSubmit().ok)
	end),

	TestHarness.case("handles accepted and rejected receipts with refresh recovery", function(assertions)
		local value = reducer()
		value:observeQuery(snapshot())
		value:selectSlot(1)
		value:setPosition(Vector2.new(0, 0))
		value:beginSubmit()
		local accepted = value:observeReceipt({
			state = "Accepted",
			runtimeTowerId = 9,
			placementCFrame = CFrame.new(0, -3, 0),
			queryRevision = 2,
		})
		assertions.isTrue(accepted.ok)
		assertions.equal(state(value).phase, "Selected")
		assertions.isTrue(state(value).refreshRequired)
		assertions.isNil(state(value).positionXZ)

		local refreshed = snapshot(2)
		assertions.isTrue(value:observeQuery(refreshed).ok)
		value:setPosition(Vector2.new(0, 0))
		value:beginSubmit()
		local rejected = value:observeReceipt({ state = "Rejected", reason = "Stale", queryRevision = 3 })
		assertions.isTrue(rejected.ok)
		assertions.equal(state(value).lastRejection, "Stale")
		assertions.isTrue(state(value).refreshRequired)
		assertions.equal(state(value).phase, "Positioned")
	end),

	TestHarness.case("coalesces revision advances and ignores foreign or stale notices", function(assertions)
		local value = reducer()
		value:observeQuery(snapshot(3))
		local foreign = value:observeRevision({ matchId = "match:other", queryRevision = 4 })
		assertions.equal(foreign.value.kind, "Foreign")
		local stale = value:observeRevision({ matchId = "match:phase13-preview", queryRevision = 2 })
		assertions.equal(stale.value.kind, "Stale")
		local advanced = value:observeRevision({ matchId = "match:phase13-preview", queryRevision = 4 })
		assertions.equal(advanced.value.kind, "Advanced")
		assertions.isTrue(advanced.value.refreshRequested)
		local coalesced = value:observeRevision({ matchId = "match:phase13-preview", queryRevision = 5 })
		assertions.isFalse(coalesced.value.refreshRequested)
	end),

	TestHarness.case("uses an authenticated revision notice to recover a missed initial query", function(assertions)
		local value = reducer()
		local bootstrap = value:observeRevision({ matchId = "match:phase13-preview", queryRevision = 1 })
		assertions.isTrue(bootstrap.ok)
		assertions.equal(bootstrap.value.kind, "Bootstrap")
		assertions.isTrue(bootstrap.value.refreshRequested)
		assertions.isTrue(state(value).refreshRequired)
		assertions.isNil(state(value).snapshot)

		local coalesced = value:observeRevision({ matchId = "match:phase13-preview", queryRevision = 2 })
		assertions.equal(coalesced.value.kind, "Bootstrap")
		assertions.isFalse(coalesced.value.refreshRequested)
		local applied = value:observeQuery(snapshot(2))
		assertions.isTrue(applied.ok)
		assertions.isFalse(state(value).refreshRequired)
	end),

	TestHarness.case("updates preferred input without losing placement state or confirming", function(assertions)
		local value = reducer()
		value:observeQuery(snapshot())
		value:selectSlot(1)
		value:setPosition(Vector2.new(0, 0))
		assertions.isTrue(value:setPreferredInput("Touch").ok)
		assertions.equal(state(value).preferredInput, "Touch")
		assertions.equal(state(value).phase, "Positioned")
		assertions.isTrue(state(value).canConfirm)
		assertions.isTrue(value:setPreferredInput("Gamepad").ok)
		assertions.equal(state(value).positionXZ, Vector2.new(0, 0))
	end),

	TestHarness.case("rejects stale queries and resets selection on match replacement", function(assertions)
		local value = reducer()
		value:observeQuery(snapshot(4))
		value:selectSlot(1)
		value:setPosition(Vector2.new(0, 0))
		local stale = value:observeQuery(snapshot(3))
		assertions.equal(stale.value.kind, "Stale")
		assertions.equal(state(value).selectedSlot, 1)

		local replaced = value:observeQuery(snapshot(1, "match:replacement"))
		assertions.equal(replaced.value.kind, "Replaced")
		assertions.equal(state(value).phase, "Idle")
		assertions.isNil(state(value).selectedSlot)
	end),

	TestHarness.case("fails closed for malformed input and leaves no state after cleanup", function(assertions)
		local value = reducer()
		assertions.isFalse(value:observeQuery({}).ok)
		assertions.isFalse(value:observeRevision({ matchId = "bad", queryRevision = 1 }).ok)
		assertions.isFalse(value:setPreferredInput("Keyboard").ok)
		assertions.isFalse(value:setPosition(Vector2.new(0 / 0, 0)).ok)
		assertions.isTrue(value:cleanup().ok)
		assertions.isFalse(value:getState().ok)
		assertions.isFalse(value:observeQuery(snapshot()).ok)
		assertions.isTrue(value:cleanup().ok)
	end),
})
