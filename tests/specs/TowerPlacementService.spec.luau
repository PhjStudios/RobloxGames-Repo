--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local Shared = game:GetService("ReplicatedStorage").Shared
local MatchProtocol = require(Shared.match.MatchProtocol)
local Result = require(Shared.util.Result)

local TowerPlacementService = require(script.Parent.Parent.ProductionServerPlacement.TowerPlacementService)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase13-placement"
local FIRST_USER_ID = 101
local SECOND_USER_ID = 202

local function runtimeMap(): any
	return table.freeze({
		mapId = "map:phase07-graybox",
		bounds = table.freeze({ cframe = CFrame.new(0, 0, 0), size = Vector3.new(200, 40, 140) }),
		placementZones = table.freeze({
			table.freeze({
				id = "land",
				cframe = CFrame.new(-40, -3, 0),
				size = Vector3.new(100, 2, 100),
				surfaceCategory = "Land",
			}),
			table.freeze({
				id = "elevated",
				cframe = CFrame.new(40, 3, 0),
				size = Vector3.new(40, 2, 40),
				surfaceCategory = "Elevated",
			}),
			table.freeze({
				id = "water",
				cframe = CFrame.new(80, -3, 0),
				size = Vector3.new(20, 2, 20),
				surfaceCategory = "Water",
			}),
		}),
		noPlacementZones = table.freeze({
			table.freeze({
				id = "lane",
				cframe = CFrame.new(-60, -3, 0),
				size = Vector3.new(10, 2, 10),
			}),
		}),
	})
end

local function occupiedSlot(
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
		iconAssetKey = `test.phase13.slot-{index}`,
		placementCost = cost,
		footprintRadiusStuds = radius,
		placementCap = cap,
		rangeStuds = range,
	})
end

local function loadoutSlots(): { any }
	return table.freeze({
		occupiedSlot(1, "tower:phase12-single", "Phase 12 Single", 100, 2, 4, 10),
		occupiedSlot(2, "tower:phase12-splash", "Phase 12 Splash", 200, 2.25, 3, 8),
		occupiedSlot(3, "tower:phase12-support", "Phase 12 Support", 100, 1.75, 1, 6),
		table.freeze({ kind = "Empty", slot = 4 }),
		table.freeze({ kind = "Empty", slot = 5 }),
	})
end

local function intent(userId: number, positionXZ: Vector2, slot: number?, revision: number?): any
	return {
		matchId = MATCH_ID,
		observedQueryRevision = revision or 1,
		loadoutRevision = 1,
		slot = slot or 1,
		positionXZ = positionXZ,
		yawDegrees = if userId == FIRST_USER_ID then -90 else 450 - 360,
	}
end

local function makeMatchSnapshot(state: any): MatchProtocol.MatchSnapshot
	local resultValue = MatchProtocol.validateMatchSnapshot({
		matchId = state.matchId,
		revision = state.matchRevision,
		state = state.matchState,
		participants = {
			{ userId = FIRST_USER_ID, state = state.participantStates[FIRST_USER_ID], ready = false },
			{ userId = SECOND_USER_ID, state = state.participantStates[SECOND_USER_ID], ready = false },
		},
	})
	if not resultValue.ok then
		error("placement match fixture did not validate", 0)
	end
	return resultValue.value
end

local function runHook(state: any, name: string)
	local callback = state.hooks[name]
	if callback ~= nil then
		state.hooks[name] = nil
		callback()
	end
end

local function frozenTower(
	runtimeTowerId: number,
	ownerUserId: number,
	towerId: string,
	placementCFrame: CFrame,
	radius: number
): any
	return table.freeze({
		matchId = MATCH_ID,
		towerEpoch = 1,
		runtimeTowerId = runtimeTowerId,
		ownerUserId = ownerUserId,
		towerId = towerId,
		placementCFrame = placementCFrame,
		footprintRadiusStuds = radius,
		level = 1,
	})
end

local function fakeDependencies(): (any, any)
	local state: any = {
		matchId = MATCH_ID,
		matchRevision = 1,
		matchState = "PreWave",
		participantStates = {
			[FIRST_USER_ID] = "Active",
			[SECOND_USER_ID] = "Active",
		},
		map = runtimeMap(),
		loadoutRevisions = {
			[FIRST_USER_ID] = 1,
			[SECOND_USER_ID] = 1,
		},
		towers = {},
		nextRuntimeTowerId = 0,
		capabilities = {},
		chargeTokens = {},
		hooks = {},
		createMode = "Normal",
		commitMode = "Normal",
		publicationMode = "Normal",
		checkCount = 0,
		prepareCount = 0,
		commitCount = 0,
		abortCount = 0,
		resolveCount = 0,
		discardCount = 0,
		createCount = 0,
		removeCount = 0,
		cleanupCount = 0,
		published = {},
		isStudio = false,
		triggerCreateMode = "Normal",
		triggerCreateCount = 0,
		triggerDestroyCount = 0,
		triggerHandler = nil,
		definition = nil,
		service = nil,
	}

	function state:addTower(ownerUserId: number, towerIdValue: string, x: number, radius: number): any
		state.nextRuntimeTowerId += 1
		local record = frozenTower(state.nextRuntimeTowerId, ownerUserId, towerIdValue, CFrame.new(x, -2, 30), radius)
		table.insert(state.towers, record)
		return record
	end

	local lifecycle: any = {}
	function lifecycle:getSnapshot(): unknown
		runHook(state, "getSnapshot")
		return Result.ok(makeMatchSnapshot(state))
	end
	function lifecycle:getRuntimeMapSnapshot(): unknown
		runHook(state, "getRuntimeMapSnapshot")
		return Result.ok(state.map)
	end
	function lifecycle:isRuntimeMapSnapshot(value: unknown): unknown
		runHook(state, "isRuntimeMapSnapshot")
		return value == state.map
	end

	local runtime: any = {}
	function runtime:getPlacementView(userIdValue: unknown): unknown
		runHook(state, "getPlacementView")
		if
			type(userIdValue) ~= "number"
			or state.loadoutRevisions[userIdValue] == nil
			or state.participantStates[userIdValue] == nil
		then
			return Result.err(table.freeze({ code = "NOT_FOUND" }))
		end
		local towerCopies = table.create(#state.towers)
		for _, tower in state.towers do
			table.insert(towerCopies, tower)
		end
		return Result.ok(table.freeze({
			matchId = state.matchId,
			towerEpoch = 1,
			userId = userIdValue,
			loadoutRevision = state.loadoutRevisions[userIdValue],
			slots = loadoutSlots(),
			towers = table.freeze(towerCopies),
		}))
	end
	function runtime:resolveOccupiedSlot(userIdValue: unknown, slotValue: unknown): unknown
		state.resolveCount += 1
		local slots = loadoutSlots()
		local selected = if type(slotValue) == "number" then slots[slotValue] else nil
		if
			type(userIdValue) ~= "number"
			or state.loadoutRevisions[userIdValue] == nil
			or selected == nil
			or selected.kind ~= "Occupied"
		then
			return Result.err(table.freeze({ code = "EMPTY_SLOT" }))
		end
		local capability = table.freeze({})
		state.capabilities[capability] = {
			userId = userIdValue,
			slot = slotValue,
			selected = selected,
		}
		runHook(state, "resolveOccupiedSlot")
		return Result.ok(capability)
	end
	function runtime:trustedDiscardCapability(capability: unknown): unknown
		local binding = if type(capability) == "table" then state.capabilities[capability] else nil
		if binding == nil then
			return Result.err(table.freeze({ code = "INVALID_CAPABILITY" }))
		end
		state.capabilities[capability] = nil
		state.discardCount += 1
		return Result.ok(true)
	end
	function runtime:trustedCreate(capability: unknown, placementCFrame: unknown): unknown
		local binding = if type(capability) == "table" then state.capabilities[capability] else nil
		if binding == nil or typeof(placementCFrame) ~= "CFrame" then
			return Result.err(table.freeze({ code = "INVALID_CAPABILITY" }))
		end
		state.capabilities[capability] = nil
		state.createCount += 1
		if state.createMode == "ErrorBeforeCreate" then
			return Result.err(table.freeze({ code = "MODEL_PREPARE_FAILED" }))
		elseif state.createMode == "ThrowBeforeCreate" then
			error("injected private create failure", 0)
		elseif state.createMode == "YieldBeforeCreate" then
			coroutine.yield()
			return Result.err(table.freeze({ code = "UNREACHABLE" }))
		end
		state.nextRuntimeTowerId += 1
		local created = frozenTower(
			state.nextRuntimeTowerId,
			binding.userId,
			binding.selected.towerId,
			placementCFrame :: CFrame,
			binding.selected.footprintRadiusStuds
		)
		table.insert(state.towers, created)
		runHook(state, "trustedCreate")
		if state.createMode == "MalformedAfterCreate" then
			return Result.ok(table.freeze({ runtimeTowerId = created.runtimeTowerId }))
		end
		return Result.ok(created)
	end
	function runtime:trustedRemove(runtimeTowerIdValue: unknown): unknown
		for index, tower in state.towers do
			if tower.runtimeTowerId == runtimeTowerIdValue then
				table.remove(state.towers, index)
				state.removeCount += 1
				return Result.ok(tower)
			end
		end
		return Result.err(table.freeze({ code = "NOT_FOUND" }))
	end

	local affordability: any = {}
	function affordability:canAfford(_userId: unknown, cost: unknown): unknown
		state.checkCount += 1
		runHook(state, "canAfford")
		return Result.ok(type(cost) == "number" and cost <= 150)
	end
	function affordability:prepare(userIdValue: unknown, costValue: unknown): unknown
		state.prepareCount += 1
		local token = table.freeze({})
		state.chargeTokens[token] = { userId = userIdValue, cost = costValue }
		runHook(state, "prepareCharge")
		return Result.ok(token)
	end
	function affordability:commit(token: unknown): unknown
		if type(token) ~= "table" or state.chargeTokens[token] == nil then
			return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
		end
		if state.commitMode == "ErrorBeforeCommit" then
			return Result.err(table.freeze({ code = "INJECTED" }))
		end
		state.chargeTokens[token] = nil
		state.commitCount += 1
		runHook(state, "commitCharge")
		if state.commitMode == "ErrorAfterCommit" then
			return Result.err(table.freeze({ code = "INJECTED" }))
		end
		return Result.ok(true)
	end
	function affordability:abort(token: unknown): unknown
		if type(token) ~= "table" or state.chargeTokens[token] == nil then
			return Result.err(table.freeze({ code = "INVALID_TOKEN" }))
		end
		state.chargeTokens[token] = nil
		state.abortCount += 1
		return Result.ok(true)
	end
	function affordability:getMetrics(): unknown
		local outstandingCount = 0
		for _ in state.chargeTokens do
			outstandingCount += 1
		end
		return table.freeze({
			checkCount = state.checkCount,
			prepareCount = state.prepareCount,
			commitCount = state.commitCount,
			abortCount = state.abortCount,
			outstandingCount = outstandingCount,
		})
	end
	function affordability:cleanup(): unknown
		state.cleanupCount += 1
		table.clear(state.chargeTokens)
		return Result.ok(true)
	end

	return {
		matchLifecycle = lifecycle,
		towerRuntime = runtime,
		affordability = affordability,
		publishRevision = function(matchIdValue: unknown, revisionValue: unknown): unknown
			table.insert(state.published, table.freeze({ matchId = matchIdValue, revision = revisionValue }))
			runHook(state, "publishRevision")
			return state.publicationMode == "Normal"
		end,
		isStudio = function(): unknown
			return state.isStudio
		end,
		createRuntimeTrigger = function(handler: any): unknown
			state.triggerCreateCount += 1
			if state.triggerCreateMode == "Throw" then
				error("PRIVATE_TRIGGER_CREATE_FAILURE", 0)
			elseif state.triggerCreateMode == "Yield" then
				coroutine.yield()
			elseif state.triggerCreateMode == "Collision" then
				return nil
			end
			state.triggerHandler = handler
			local trigger: any = {}
			function trigger:Destroy()
				state.triggerDestroyCount += 1
			end
			return trigger
		end,
	},
		state
end

local function newStarted(assertions: Assertions): (any, any, any)
	local constructor = (TowerPlacementService :: any).newForTests
	assertions.isNotNil(constructor)
	local dependencies, state = fakeDependencies()
	local service = constructor(dependencies)
	local definition = service:getServiceDefinition()
	state.service = service
	state.definition = definition
	definition.initialize()
	definition.start()
	return service, definition, state
end

local function newStudioStarted(assertions: Assertions): (any, any, any)
	local constructor = (TowerPlacementService :: any).newForTests
	assertions.isNotNil(constructor)
	local dependencies, state = fakeDependencies()
	state.isStudio = true
	local service = constructor(dependencies)
	local definition = service:getServiceDefinition()
	state.service = service
	state.definition = definition
	definition.initialize()
	definition.start()
	return service, definition, state
end

local function accepted(assertions: Assertions, resultValue: any): any
	assertions.isTrue(resultValue.ok)
	if not resultValue.ok then
		error("expected accepted placement result", 0)
	end
	assertions.equal(resultValue.value.state, "Accepted")
	return resultValue.value
end

local function rejected(assertions: Assertions, resultValue: any, reason: string): any
	assertions.isTrue(resultValue.ok)
	if not resultValue.ok then
		error("expected rejected placement receipt", 0)
	end
	assertions.equal(resultValue.value.state, "Rejected")
	assertions.equal(resultValue.value.reason, reason)
	return resultValue.value
end

local function expectUnavailableError(assertions: Assertions, resultValue: any)
	assertions.isFalse(resultValue.ok)
	if not resultValue.ok then
		assertions.equal(resultValue.error.code, "UNAVAILABLE")
		assertions.equal(resultValue.error.operation, "submitPlacement")
	end
end

local function countKeys(value: { [any]: any }): number
	local count = 0
	for _ in value do
		count += 1
	end
	return count
end

local function assertNoTransactionResidue(assertions: Assertions, service: any, state: any)
	assertions.equal(service:getMetrics().reservationCount, 0)
	assertions.equal(countKeys(state.chargeTokens), 0)
	assertions.equal(countKeys(state.capabilities), 0)
end

return TestHarness.suite("Phase 13 authoritative tower placement", {
	TestHarness.case("commits one canonical placement and publishes its new revision", function(assertions)
		local service, definition, state = newStarted(assertions)
		local receipt =
			accepted(assertions, service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 0))))
		assertions.equal(receipt.runtimeTowerId, 1)
		assertions.equal(receipt.queryRevision, 2)
		assertions.equal(receipt.placementCFrame, CFrame.new(-40, -2, 0) * CFrame.Angles(0, math.rad(270), 0))
		assertions.equal(#state.towers, 1)
		assertions.equal(state.towers[1].ownerUserId, FIRST_USER_ID)
		assertions.equal(state.towers[1].towerId, "tower:phase12-single")
		assertions.equal(state.prepareCount, 1)
		assertions.equal(state.commitCount, 1)
		assertions.equal(state.abortCount, 0)
		assertions.equal(state.resolveCount, 1)
		assertions.equal(state.createCount, 1)
		assertions.equal(#state.published, 1)
		assertions.equal(state.published[1].matchId, MATCH_ID)
		assertions.equal(state.published[1].revision, 2)
		assertNoTransactionResidue(assertions, service, state)
		definition.shutdown()
	end),

	TestHarness.case(
		"serializes same-snapshot overlap and admits non-overlap within revision lag",
		function(assertions)
			local service, definition, state = newStarted(assertions)
			local firstQuery = service:getQuery(FIRST_USER_ID)
			local secondQuery = service:getQuery(SECOND_USER_ID)
			assertions.isTrue(firstQuery.ok)
			assertions.isTrue(secondQuery.ok)
			accepted(assertions, service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 0))))
			rejected(
				assertions,
				service:submitPlacement(SECOND_USER_ID, intent(SECOND_USER_ID, Vector2.new(-40, 0))),
				"Occupied"
			)
			accepted(assertions, service:submitPlacement(SECOND_USER_ID, intent(SECOND_USER_ID, Vector2.new(-30, 0))))
			assertions.equal(#state.towers, 2)
			assertions.equal(state.createCount, 2)
			assertions.equal(state.prepareCount, 2)
			assertions.equal(state.commitCount, 2)
			assertions.equal(service:getMetrics().queryRevision, 3)
			assertNoTransactionResidue(assertions, service, state)
			definition.shutdown()
		end
	),

	TestHarness.case(
		"rejects sender match slot loadout and query-revision failures before mutation",
		function(assertions)
			local cases = {
				{
					reason = "NotEligible",
					mutate = function(_state: any, payload: any)
						payload.matchId = "match:other"
					end,
				},
				{
					reason = "NotEligible",
					mutate = function(state: any, _payload: any)
						state.participantStates[FIRST_USER_ID] = "Spectator"
					end,
				},
				{
					reason = "InvalidSlot",
					mutate = function(_state: any, payload: any)
						payload.slot = 4
					end,
				},
				{
					reason = "Stale",
					mutate = function(_state: any, payload: any)
						payload.loadoutRevision = 2
					end,
				},
				{
					reason = "Stale",
					mutate = function(_state: any, payload: any)
						payload.observedQueryRevision = 2
					end,
				},
			}
			for _, testCase in cases do
				local service, definition, state = newStarted(assertions)
				local payload = intent(FIRST_USER_ID, Vector2.new(-40, 0))
				testCase.mutate(state, payload)
				rejected(assertions, service:submitPlacement(FIRST_USER_ID, payload), testCase.reason)
				assertions.equal(state.prepareCount, 0)
				assertions.equal(state.createCount, 0)
				assertions.equal(#state.towers, 0)
				assertNoTransactionResidue(assertions, service, state)
				definition.shutdown()
			end
		end
	),

	TestHarness.case("admits exactly four revision lag and rejects the fifth", function(assertions)
		local service, definition, state = newStarted(assertions)
		for _, x in { -80, -70, -50, -40 } do
			accepted(assertions, service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(x, 0), 1, 1)))
		end
		accepted(assertions, service:submitPlacement(SECOND_USER_ID, intent(SECOND_USER_ID, Vector2.new(-30, 0), 1, 1)))
		assertions.equal(service:getMetrics().queryRevision, 6)
		rejected(
			assertions,
			service:submitPlacement(SECOND_USER_ID, intent(SECOND_USER_ID, Vector2.new(-20, 0), 1, 1)),
			"Stale"
		)
		assertions.equal(#state.towers, 5)
		assertions.equal(state.prepareCount, 5)
		assertions.equal(state.commitCount, 5)
		assertNoTransactionResidue(assertions, service, state)
		definition.shutdown()
	end),

	TestHarness.case("rejects every server-owned map surface and footprint boundary", function(assertions)
		local cases = {
			{ position = Vector2.new(99, 0), reason = "InvalidPosition" },
			{ position = Vector2.new(15, 0), reason = "OutsideZone" },
			{ position = Vector2.new(9, 0), reason = "OutsideZone" },
			{ position = Vector2.new(80, 0), reason = "InvalidSurface" },
			{ position = Vector2.new(-60, 0), reason = "Excluded" },
		}
		for _, testCase in cases do
			local service, definition, state = newStarted(assertions)
			rejected(
				assertions,
				service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, testCase.position)),
				testCase.reason
			)
			assertions.equal(state.prepareCount, 0)
			assertions.equal(#state.towers, 0)
			assertNoTransactionResidue(assertions, service, state)
			definition.shutdown()
		end

		local overlapService, overlapDefinition, overlapState = newStarted(assertions)
		overlapState:addTower(SECOND_USER_ID, "tower:phase12-single", -40, 2)
		rejected(
			assertions,
			overlapService:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 30))),
			"Occupied"
		)
		assertions.equal(overlapState.prepareCount, 0)
		assertNoTransactionResidue(assertions, overlapService, overlapState)
		overlapDefinition.shutdown()
	end),

	TestHarness.case("enforces canonical per-type total and affordability boundaries", function(assertions)
		local unaffordableService, unaffordableDefinition, unaffordableState = newStarted(assertions)
		rejected(
			assertions,
			unaffordableService:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 0), 2)),
			"Unaffordable"
		)
		assertions.equal(unaffordableState.prepareCount, 0)
		unaffordableDefinition.shutdown()

		local cappedService, cappedDefinition, cappedState = newStarted(assertions)
		for index, x in { -80, -70, -50, -30 } do
			local tower = cappedState:addTower(FIRST_USER_ID, "tower:phase12-single", x, 2)
			local mutable = table.clone(tower)
			mutable.placementCFrame = CFrame.new(x, -2, 30 + index)
			cappedState.towers[index] = table.freeze(mutable)
		end
		rejected(
			assertions,
			cappedService:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(0, 0))),
			"Capped"
		)
		assertions.equal(cappedState.prepareCount, 0)
		assertNoTransactionResidue(assertions, cappedService, cappedState)
		cappedDefinition.shutdown()
	end),

	TestHarness.case("contains malformed and hostile direct intents at the protocol boundary", function(assertions)
		local service, definition, state = newStarted(assertions)
		local hostile = intent(FIRST_USER_ID, Vector2.new(-40, 0))
		hostile.ownerUserId = SECOND_USER_ID
		local resultValue = service:submitPlacement(FIRST_USER_ID, hostile)
		assertions.isFalse(resultValue.ok)
		if not resultValue.ok then
			assertions.equal(resultValue.error.code, "INVALID_ARGUMENT")
		end
		for _, value in
			{
				Vector2.new(0 / 0, 0),
				Vector2.new(math.huge, 0),
				Vector2.new(-math.huge, 0),
				Vector2.new(100_001, 0),
			}
		do
			local invalid = intent(FIRST_USER_ID, value)
			local invalidResult = service:submitPlacement(FIRST_USER_ID, invalid)
			assertions.isFalse(invalidResult.ok)
		end
		for _, yaw in { 0 / 0, math.huge, -math.huge, 361 } do
			local invalid = intent(FIRST_USER_ID, Vector2.new(-40, 0))
			invalid.yawDegrees = yaw
			assertions.isFalse(service:submitPlacement(FIRST_USER_ID, invalid).ok)
		end
		assertions.isFalse(service:submitPlacement(FIRST_USER_ID, {}).ok)
		assertions.equal(state.prepareCount, 0)
		assertions.equal(#state.towers, 0)
		assertNoTransactionResidue(assertions, service, state)
		definition.shutdown()
	end),

	TestHarness.case("rolls back disconnect after creation with one charge reservation", function(assertions)
		local service, definition, state = newStarted(assertions)
		state.hooks.resolveOccupiedSlot = function()
			state.participantStates[FIRST_USER_ID] = "Disconnected"
			state.matchRevision += 1
		end
		rejected(
			assertions,
			service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 0))),
			"NotEligible"
		)
		assertions.equal(state.prepareCount, 1)
		assertions.equal(state.commitCount, 0)
		assertions.equal(state.abortCount, 1)
		assertions.equal(state.createCount, 1)
		assertions.equal(state.removeCount, 1)
		assertions.equal(#state.towers, 0)
		assertNoTransactionResidue(assertions, service, state)
		definition.shutdown()
	end),

	TestHarness.case("aborts a prepared charge when cleanup interrupts admission", function(assertions)
		local service, _definition, state = newStarted(assertions)
		state.hooks.prepareCharge = function()
			state.definition.shutdown()
		end
		expectUnavailableError(
			assertions,
			service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 0)))
		)
		assertions.equal(service:getLifecycleState(), "Shutdown")
		assertions.equal(state.prepareCount, 1)
		assertions.equal(state.abortCount, 1)
		assertions.equal(state.createCount, 0)
		assertions.equal(#state.towers, 0)
		assertions.equal(state.cleanupCount, 1)
		assertNoTransactionResidue(assertions, service, state)
	end),

	TestHarness.case("discards a capability when cleanup interrupts issuance", function(assertions)
		local service, _definition, state = newStarted(assertions)
		state.hooks.resolveOccupiedSlot = function()
			state.definition.shutdown()
		end
		expectUnavailableError(
			assertions,
			service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 0)))
		)
		assertions.equal(service:getLifecycleState(), "Shutdown")
		assertions.equal(state.resolveCount, 1)
		assertions.equal(state.discardCount, 1)
		assertions.equal(state.createCount, 0)
		assertions.equal(state.abortCount, 1)
		assertions.equal(#state.towers, 0)
		assertNoTransactionResidue(assertions, service, state)
	end),

	TestHarness.case("fails closed on placement-service reentry before any mutation", function(assertions)
		local service, definition, state = newStarted(assertions)
		local nestedResult: any = nil
		state.hooks.canAfford = function()
			nestedResult = service:submitPlacement(SECOND_USER_ID, intent(SECOND_USER_ID, Vector2.new(-30, 0)))
		end
		expectUnavailableError(
			assertions,
			service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 0)))
		)
		expectUnavailableError(assertions, nestedResult)
		assertions.equal(service:getLifecycleState(), "Failed")
		assertions.equal(state.prepareCount, 0)
		assertions.equal(state.createCount, 0)
		assertions.equal(#state.towers, 0)
		assertions.equal(state.cleanupCount, 1)
		assertNoTransactionResidue(assertions, service, state)
		definition.shutdown()
	end),

	TestHarness.case("reverses model create and post-commit faults without partial state", function(assertions)
		for _, mode in { "ErrorBeforeCreate", "ThrowBeforeCreate", "YieldBeforeCreate", "MalformedAfterCreate" } do
			local service, definition, state = newStarted(assertions)
			state.createMode = mode
			local resultValue = service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 0)))
			if mode ~= "ErrorBeforeCreate" then
				expectUnavailableError(assertions, resultValue)
			else
				rejected(assertions, resultValue, "Unavailable")
			end
			assertions.equal(state.prepareCount, 1)
			assertions.equal(state.abortCount, 1)
			assertions.equal(state.commitCount, 0)
			assertions.equal(#state.towers, 0)
			assertions.equal(state.removeCount, if mode == "MalformedAfterCreate" then 1 else 0)
			assertNoTransactionResidue(assertions, service, state)
			definition.shutdown()
			assertions.equal(service:getLifecycleState(), "Shutdown")
		end
	end),

	TestHarness.case(
		"removes the tower when placeholder finalization fails before or after consume",
		function(assertions)
			for _, mode in { "ErrorBeforeCommit", "ErrorAfterCommit" } do
				local service, definition, state = newStarted(assertions)
				state.commitMode = mode
				rejected(
					assertions,
					service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 0))),
					"Unavailable"
				)
				assertions.equal(state.createCount, 1)
				assertions.equal(state.removeCount, 1)
				assertions.equal(#state.towers, 0)
				assertions.equal(state.abortCount, if mode == "ErrorBeforeCommit" then 1 else 0)
				assertNoTransactionResidue(assertions, service, state)
				definition.shutdown()
			end
		end
	),

	TestHarness.case("keeps accepted authority when revision publication is unavailable", function(assertions)
		local service, definition, state = newStarted(assertions)
		state.publicationMode = "Failure"
		accepted(assertions, service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 0))))
		assertions.equal(#state.towers, 1)
		assertions.equal(service:getMetrics().publicationCount, 0)
		assertions.equal(service:getMetrics().publicationFailureCount, 1)
		assertNoTransactionResidue(assertions, service, state)
		definition.shutdown()
	end),

	TestHarness.case(
		"owns a bounded Studio refresh and diagnostics trigger with complete cleanup",
		function(assertions)
			local service, definition, state = newStudioStarted(assertions)
			assertions.equal(TowerPlacementService.STUDIO_TRIGGER_NAME, "_ATDPhase13PlacementEvidence")
			assertions.equal(state.triggerCreateCount, 1)
			assertions.equal(service:getMetrics().studioTriggerCount, 1)
			local invoke = state.triggerHandler :: any

			local missing = invoke()
			assertions.isFalse(missing.ok)
			assertions.equal(missing.error.code, "INVALID_ARGUMENT")
			assertions.equal(missing.error.operation, "studioEvidence")
			local extra = invoke({ operation = "Refresh", extra = true })
			assertions.isFalse(extra.ok)
			assertions.equal(extra.error.code, "INVALID_ARGUMENT")

			local refreshed = invoke({ operation = "Refresh" })
			assertions.isTrue(refreshed.ok)
			assertions.equal(refreshed.value.matchId, MATCH_ID)
			assertions.equal(refreshed.value.queryRevision, 1)
			assertions.isTrue(refreshed.value.published)
			assertions.equal(#state.published, 1)

			local diagnostics = invoke({ operation = "Diagnostics" })
			assertions.isTrue(diagnostics.ok)
			assertions.isTrue(table.isfrozen(diagnostics.value))
			assertions.equal(diagnostics.value.studioOperationCount, 2)
			assertions.equal(diagnostics.value.studioRefreshCount, 1)
			assertions.equal(diagnostics.value.publicationCount, 1)
			assertions.equal(diagnostics.value.reservationCount, 0)

			state.publicationMode = "Failure"
			local unavailable = invoke({ operation = "Refresh" })
			assertions.isFalse(unavailable.ok)
			assertions.equal(unavailable.error.code, "UNAVAILABLE")
			assertions.equal(service:getMetrics().publicationFailureCount, 1)

			state.publicationMode = "Normal"
			state.matchState = "Loading"
			local inactive = invoke({ operation = "Refresh" })
			assertions.isFalse(inactive.ok)
			assertions.equal(inactive.error.code, "NOT_ELIGIBLE")

			definition.shutdown()
			assertions.equal(state.triggerDestroyCount, 1)
			assertions.equal(service:getMetrics().studioTriggerCount, 0)
			assertions.equal(service:getMetrics().studioOperationCount, 0)
			assertions.equal(service:getMetrics().studioRefreshCount, 0)
			local late = invoke({ operation = "Diagnostics" })
			assertions.isFalse(late.ok)
			assertions.equal(late.error.code, "UNAVAILABLE")
		end
	),

	TestHarness.case("returns bounded receipts and rejects every late post-cleanup mutation", function(assertions)
		local service, definition, state = newStarted(assertions)
		local receipt = rejected(
			assertions,
			service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(80, 0))),
			"InvalidSurface"
		)
		for _, forbidden in
			{
				"ownerUserId",
				"unitId",
				"towerId",
				"cost",
				"capability",
				"definition",
				"model",
			}
		do
			assertions.isNil(receipt[forbidden])
		end
		definition.shutdown()
		assertions.equal(service:getLifecycleState(), "Shutdown")
		expectUnavailableError(
			assertions,
			service:submitPlacement(FIRST_USER_ID, intent(FIRST_USER_ID, Vector2.new(-40, 0)))
		)
		assertions.equal(state.prepareCount, 0)
		assertions.equal(state.createCount, 0)
		assertions.equal(#state.towers, 0)
		assertNoTransactionResidue(assertions, service, state)
	end),
})
