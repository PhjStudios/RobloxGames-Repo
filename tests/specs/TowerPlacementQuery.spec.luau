--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local Shared = game:GetService("ReplicatedStorage").Shared
local MatchProtocol = require(Shared.match.MatchProtocol)
local PlacementProtocol = require(Shared.match.PlacementProtocol)
local Result = require(Shared.util.Result)

local TowerPlacementService = require(script.Parent.Parent.ProductionServerPlacement.TowerPlacementService)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase13-query"
local USER_ID = 101

local function matchSnapshot(state: MatchProtocol.MatchState?, participantState: MatchProtocol.ParticipantState?): any
	local selectedState = state or "PreWave"
	local result = MatchProtocol.validateMatchSnapshot({
		matchId = MATCH_ID,
		revision = 8,
		state = selectedState,
		deadlineServerTime = if selectedState == "ReadyCheck" then 100 else nil,
		participants = {
			{ userId = USER_ID, state = participantState or "Active", ready = false },
		},
	})
	if not result.ok then
		error("query fixture match snapshot did not validate", 0)
	end
	return result.value
end

local function runtimeMap(): any
	return table.freeze({
		mapId = "map:phase07-graybox",
		bounds = table.freeze({ cframe = CFrame.new(), size = Vector3.new(120, 40, 100) }),
		placementZones = table.freeze({
			table.freeze({
				id = "land",
				cframe = CFrame.new(0, -3, 0),
				size = Vector3.new(90, 2, 70),
				surfaceCategory = "Land",
			}),
			table.freeze({
				id = "ledge",
				cframe = CFrame.new(45, 2, 0),
				size = Vector3.new(10, 2, 20),
				surfaceCategory = "Elevated",
			}),
		}),
		noPlacementZones = table.freeze({
			table.freeze({ id = "lane", cframe = CFrame.new(-25, -3, 0), size = Vector3.new(10, 2, 10) }),
		}),
	})
end

local function slot(
	index: number,
	towerId: string,
	displayName: string,
	cost: number,
	radius: number,
	cap: number,
	range: number
): any
	return table.freeze({
		kind = "Occupied",
		slot = index,
		towerId = towerId,
		displayName = displayName,
		iconAssetKey = `test.{towerId}.icon`,
		placementCost = cost,
		footprintRadiusStuds = radius,
		placementCap = cap,
		rangeStuds = range,
	})
end

local function towerView(towers: { any }?): any
	return table.freeze({
		matchId = MATCH_ID,
		towerEpoch = 1,
		userId = USER_ID,
		loadoutRevision = 3,
		slots = table.freeze({
			slot(1, "tower:phase12-single", "Phase 12 Single", 100, 2, 4, 10),
			slot(2, "tower:phase12-splash", "Phase 12 Splash", 200, 2.25, 3, 8),
			slot(3, "tower:phase12-support", "Phase 12 Support", 100, 1.75, 1, 6),
			table.freeze({ kind = "Empty", slot = 4 }),
			table.freeze({ kind = "Empty", slot = 5 }),
		}),
		towers = table.freeze(towers or {}),
	})
end

local function tower(runtimeTowerId: number, ownerUserId: number, towerId: string, x: number, radius: number): any
	return table.freeze({
		runtimeTowerId = runtimeTowerId,
		ownerUserId = ownerUserId,
		towerId = towerId,
		placementCFrame = CFrame.new(x, -3, 0),
		footprintRadiusStuds = radius,
	})
end

local function fakeDependencies(): (any, any)
	local state: any = {
		snapshot = matchSnapshot(),
		map = runtimeMap(),
		mapIdentity = true,
		view = towerView(),
		affordabilityMode = "Normal",
		checkCount = 0,
		cleanupCount = 0,
		published = {},
	}

	local lifecycle: any = {}
	function lifecycle:getSnapshot(): unknown
		return Result.ok(state.snapshot)
	end
	function lifecycle:getRuntimeMapSnapshot(): unknown
		return Result.ok(state.map)
	end
	function lifecycle:isRuntimeMapSnapshot(value: unknown): unknown
		return state.mapIdentity and value == state.map
	end

	local runtime: any = {}
	function runtime:getPlacementView(_userId: unknown): unknown
		if state.view == "NotFound" then
			return Result.err(table.freeze({ code = "NOT_FOUND" }))
		elseif state.view == "Throw" then
			error("private tower query failure", 0)
		end
		return Result.ok(state.view)
	end
	function runtime:resolveOccupiedSlot(_userId: unknown, _slot: unknown): unknown
		return Result.err(table.freeze({ code = "UNUSED" }))
	end
	function runtime:trustedDiscardCapability(_capability: unknown): unknown
		return Result.err(table.freeze({ code = "UNUSED" }))
	end
	function runtime:trustedCreate(_capability: unknown, _cframe: unknown): unknown
		return Result.err(table.freeze({ code = "UNUSED" }))
	end
	function runtime:trustedRemove(_runtimeTowerId: unknown): unknown
		return Result.err(table.freeze({ code = "UNUSED" }))
	end

	local affordability: any = {}
	function affordability:canAfford(_userId: unknown, cost: unknown): unknown
		state.checkCount += 1
		if state.affordabilityMode == "Throw" then
			error("private affordability failure", 0)
		elseif state.affordabilityMode == "Yield" then
			coroutine.yield()
		end
		return Result.ok(type(cost) == "number" and cost <= 150)
	end
	function affordability:prepare(_userId: unknown, _cost: unknown): unknown
		return Result.ok(table.freeze({}))
	end
	function affordability:commit(_token: unknown): unknown
		return Result.ok(true)
	end
	function affordability:abort(_token: unknown): unknown
		return Result.ok(true)
	end
	function affordability:getMetrics(): unknown
		return table.freeze({ checkCount = state.checkCount, outstandingCount = 0 })
	end
	function affordability:cleanup(): unknown
		state.cleanupCount += 1
		return Result.ok(true)
	end

	local dependencies = {
		matchLifecycle = lifecycle,
		towerRuntime = runtime,
		affordability = affordability,
		publishRevision = function(matchId: unknown, revision: unknown): unknown
			table.insert(state.published, table.freeze({ matchId = matchId, revision = revision }))
			return true
		end,
		isStudio = function(): unknown
			return false
		end,
		createRuntimeTrigger = function(_handler: any): unknown
			return nil
		end,
	}
	return dependencies, state
end

local function newStarted(assertions: Assertions): (any, any, any)
	local constructor = (TowerPlacementService :: any).newForTests
	assertions.isNotNil(constructor)
	local dependencies, state = fakeDependencies()
	local service = constructor(dependencies)
	local definition = service:getServiceDefinition()
	definition.initialize()
	definition.start()
	return service, definition, state
end

local function success(assertions: Assertions, value: any): any
	assertions.isTrue(value.ok)
	if not value.ok then
		error("expected placement query success", 0)
	end
	return value.value
end

local function expectError(assertions: Assertions, value: any, code: string)
	assertions.isFalse(value.ok)
	if not value.ok then
		assertions.equal(value.error.code, code)
		assertions.equal(value.error.operation, "getQuery")
	end
end

return TestHarness.suite("Phase 13 bounded placement query service", {
	TestHarness.case("builds one detached caller-private five-slot snapshot", function(assertions)
		local service, definition, state = newStarted(assertions)
		local query = success(assertions, service:getQuery(USER_ID))
		assertions.equal(query.contractVersion, 1)
		assertions.equal(query.matchId, MATCH_ID)
		assertions.equal(query.mapId, "map:phase07-graybox")
		assertions.equal(query.queryRevision, 1)
		assertions.equal(query.loadoutRevision, 3)
		assertions.equal(#query.placementZones, 2)
		assertions.equal(query.placementZones[1].surfaceCategory, "Land")
		assertions.equal(query.placementZones[2].surfaceCategory, "Elevated")
		assertions.equal(#query.exclusions, 1)
		assertions.equal(#query.slots, 5)
		assertions.equal(query.slots[1].towerId, "tower:phase12-single")
		assertions.equal(query.slots[4].kind, "Empty")
		assertions.equal(query.slots[2].affordability, "Unaffordable")
		assertions.equal(query.slots[1].affordability, "Affordable")
		assertions.equal(state.checkCount, 3)
		assertions.isTrue(table.isfrozen(query))
		definition.shutdown()
	end),

	TestHarness.case("omits client authority identities and private diagnostics recursively", function(assertions)
		local service, definition = newStarted(assertions)
		local query = success(assertions, service:getQuery(USER_ID))
		local forbidden = table.freeze({
			unitId = true,
			runtimeTowerId = true,
			ownerUserId = true,
			capability = true,
			modelAssetKey = true,
			definition = true,
			instance = true,
		})
		local function inspect(value: unknown)
			if type(value) ~= "table" then
				return
			end
			for key, child in next, value :: any do
				if type(key) == "string" then
					assertions.isFalse(forbidden[key] == true)
				end
				assertions.isFalse(typeof(child) == "Instance")
				inspect(child)
			end
		end
		inspect(query)
		definition.shutdown()
	end),

	TestHarness.case("derives current footprints and caller-owned cap counts", function(assertions)
		local service, definition, state = newStarted(assertions)
		state.view = towerView({
			tower(1, USER_ID, "tower:phase12-single", -10, 2),
			tower(2, USER_ID, "tower:phase12-single", 0, 2),
			tower(3, USER_ID, "tower:phase12-single", 10, 2),
			tower(4, USER_ID, "tower:phase12-single", 20, 2),
			tower(5, 202, "tower:phase12-support", 30, 1.75),
		})
		local query = success(assertions, service:getQuery(USER_ID))
		assertions.equal(#query.footprints, 5)
		assertions.equal(query.footprints[1], Vector3.new(-10, 2, 0))
		assertions.equal(query.slots[1].placementCount, 4)
		assertions.equal(query.slots[1].capState, "PerTypeCapped")
		assertions.equal(query.slots[3].placementCount, 0)
		assertions.equal(query.slots[3].capState, "Available")
		assertions.equal(query.slots[1].totalCount, 4)
		definition.shutdown()
	end),

	TestHarness.case("uses total-cap state ahead of per-type state", function(assertions)
		local service, definition, state = newStarted(assertions)
		local towers = {}
		for index = 1, PlacementProtocol.MAX_QUERY_FOOTPRINTS do
			table.insert(towers, tower(index, 202, "tower:phase12-single", index * 2, 0.5))
		end
		state.view = towerView(towers)
		local query = success(assertions, service:getQuery(USER_ID))
		assertions.equal(query.slots[1].totalCount, 0)
		assertions.equal(query.slots[1].globalCount, PlacementProtocol.MAX_QUERY_FOOTPRINTS)
		assertions.equal(query.slots[1].capState, "TotalCapped")
		assertions.equal(query.slots[3].capState, "TotalCapped")
		definition.shutdown()
	end),

	TestHarness.case("rejects inactive disconnected spectator and terminal lifecycle state", function(assertions)
		for _, participantState in { "Disconnected", "Returned", "Spectator" } do
			local service, definition, state = newStarted(assertions)
			state.snapshot = matchSnapshot("PreWave", participantState :: any)
			expectError(assertions, service:getQuery(USER_ID), "NOT_ELIGIBLE")
			definition.shutdown()
		end
		for _, lifecycleState in { "Loading", "ReadyCheck", "Results", "Closing" } do
			local service, definition, state = newStarted(assertions)
			state.snapshot = matchSnapshot(lifecycleState :: any, "Active")
			expectError(assertions, service:getQuery(USER_ID), "NOT_ELIGIBLE")
			definition.shutdown()
		end
	end),

	TestHarness.case("rejects unknown user and unavailable temporary loadout", function(assertions)
		local service, definition, state = newStarted(assertions)
		expectError(assertions, service:getQuery(202), "NOT_ELIGIBLE")
		state.view = "NotFound"
		expectError(assertions, service:getQuery(USER_ID), "NOT_ELIGIBLE")
		definition.shutdown()
	end),

	TestHarness.case("rejects mismatched map and TowerRuntime identities", function(assertions)
		local service, definition, state = newStarted(assertions)
		state.mapIdentity = false
		expectError(assertions, service:getQuery(USER_ID), "INTERNAL_ERROR")
		state.mapIdentity = true
		local mismatched = towerView()
		local mutable = table.clone(mismatched)
		mutable.matchId = "match:other"
		state.view = table.freeze(mutable)
		expectError(assertions, service:getQuery(USER_ID), "UNAVAILABLE")
		definition.shutdown()
	end),

	TestHarness.case("rejects oversized authoritative region and footprint sources", function(assertions)
		local service, definition, state = newStarted(assertions)
		local map = table.clone(runtimeMap())
		local zones = {}
		for index = 1, PlacementProtocol.MAX_QUERY_PLACEMENT_ZONES + 1 do
			table.insert(
				zones,
				table.freeze({
					id = `zone-{index}`,
					cframe = CFrame.new(index, 0, 0),
					size = Vector3.new(1, 1, 1),
					surfaceCategory = "Land",
				})
			)
		end
		map.placementZones = table.freeze(zones)
		state.map = table.freeze(map)
		expectError(assertions, service:getQuery(USER_ID), "UNAVAILABLE")

		state.map = runtimeMap()
		local towers = {}
		for index = 1, PlacementProtocol.MAX_QUERY_FOOTPRINTS + 1 do
			table.insert(towers, tower(index, 202, "tower:phase12-single", index, 0.5))
		end
		state.view = towerView(towers)
		expectError(assertions, service:getQuery(USER_ID), "UNAVAILABLE")
		definition.shutdown()
	end),

	TestHarness.case("contains throwing and yielding query dependencies", function(assertions)
		for _, mode in { "Throw", "Yield" } do
			local service, definition, state = newStarted(assertions)
			state.affordabilityMode = mode
			expectError(assertions, service:getQuery(USER_ID), "INTERNAL_ERROR")
			assertions.equal(service:getMetrics().queryCount, 0)
			definition.shutdown()
		end
	end),

	TestHarness.case("cleans all owned query state and rejects late work", function(assertions)
		local service, definition, state = newStarted(assertions)
		success(assertions, service:getQuery(USER_ID))
		definition.shutdown()
		assertions.equal(service:getLifecycleState(), "Shutdown")
		assertions.equal(state.cleanupCount, 1)
		expectError(assertions, service:getQuery(USER_ID), "UNAVAILABLE")
		local metrics = service:getMetrics()
		assertions.equal(metrics.connectionCount, 0)
		assertions.equal(metrics.reservationCount, 0)
		assertions.isNil(metrics.affordability)
		definition.shutdown()
		assertions.equal(state.cleanupCount, 1)
	end),
})
