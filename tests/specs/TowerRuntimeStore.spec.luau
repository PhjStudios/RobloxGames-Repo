--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local TowerRuntimeStore = require(script.Parent.Parent.ProductionServerTowers.TowerRuntimeStore)

type Assertions = TestHarness.Assertions

type AuthorityMode = "Normal" | "Throw" | "Yield" | "Malformed"

type AuthorityState = {
	token: unknown?,
	binding: TowerRuntimeStore.PreparedCapabilityBinding?,
	status: "Idle" | "Reserved" | "Committed" | "Aborted",
	mode: AuthorityMode,
	reenter: (() -> ())?,
}

type Authority = {
	inspect: TowerRuntimeStore.PreparedCapabilityInspector,
	reserve: (
		definition: ConfigTypes.TowerDefinition,
		userId: number,
		slot: number,
		overrides: { [string]: any }?
	) -> unknown,
	commit: (token: unknown) -> boolean,
	abort: (token: unknown) -> boolean,
	state: AuthorityState,
}

local MATCH_ID = "match:phase12-runtime-store"
local TOWER_EPOCH = 1

local function expectError(assertions: Assertions, result: any, code: string, operation: string)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		assertions.isTrue(table.isfrozen(result.error))
		assertions.equal(result.error.code, code)
		assertions.equal(result.error.operation, operation)
	end
end

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected Phase 12 tower runtime operation to succeed", 0)
	end
	return result.value
end

local function temporaryUnitId(userId: number, slot: number): string
	local userSegment = if userId > 0 then `p{userId}` else `n{math.abs(userId)}`
	return `unit:p12-e{TOWER_EPOCH}-{userSegment}-s{slot}`
end

local function newAuthority(matchId: string?, towerEpoch: number?): Authority
	local state: AuthorityState = {
		token = nil,
		binding = nil,
		status = "Idle",
		mode = "Normal",
		reenter = nil,
	}

	local function reserve(
		definition: ConfigTypes.TowerDefinition,
		userId: number,
		slot: number,
		overrides: { [string]: any }?
	): unknown
		if state.status == "Reserved" then
			error("test authority already has one reserved capability", 0)
		end
		local binding: { [string]: any } = {
			matchId = matchId or MATCH_ID,
			towerEpoch = towerEpoch or TOWER_EPOCH,
			userId = userId,
			loadoutRevision = 1,
			slot = slot,
			towerId = definition.id,
			unitId = temporaryUnitId(userId, slot),
			definition = definition,
		}
		if overrides ~= nil then
			for key, value in overrides do
				binding[key] = value
			end
		end
		local token = table.freeze({})
		state.token = token
		state.binding = table.freeze(binding) :: any
		state.status = "Reserved"
		return token
	end

	local function inspect(value: unknown): unknown
		if state.mode == "Throw" then
			error("injected inspector failure", 0)
		elseif state.mode == "Yield" then
			coroutine.yield()
		elseif state.mode == "Malformed" then
			return table.freeze({ ok = true, value = "malformed" })
		end
		if state.reenter ~= nil then
			state.reenter()
		end
		if value ~= state.token or state.status ~= "Reserved" or state.binding == nil then
			return Result.err("INVALID_CAPABILITY")
		end
		return Result.ok(state.binding)
	end

	local function commit(token: unknown): boolean
		if token ~= state.token or state.status ~= "Reserved" then
			return false
		end
		state.status = "Committed"
		return true
	end

	local function abort(token: unknown): boolean
		if token ~= state.token or state.status ~= "Reserved" then
			return false
		end
		state.status = "Aborted"
		return true
	end

	return table.freeze({
		inspect = inspect,
		reserve = reserve,
		commit = commit,
		abort = abort,
		state = state,
	})
end

local function newStore(
	assertions: Assertions,
	options: { [string]: any }?,
	fixtureValue: TowerFixtures.AuthenticatedFixture?
): (TowerRuntimeStore.Store, Authority, TowerFixtures.AuthenticatedFixture)
	local fixture = fixtureValue or TowerFixtures.createAuthenticatedFixture()
	local authority = newAuthority()
	local testOptions: { [string]: any } = {
		inspectPreparedCapability = authority.inspect,
	}
	if options ~= nil then
		for key, value in options do
			testOptions[key] = value
		end
	end
	local store =
		success(assertions, TowerRuntimeStore.newForTests(MATCH_ID, TOWER_EPOCH, fixture.configuration, testOptions))
	return store, authority, fixture
end

local function prepare(
	assertions: Assertions,
	store: TowerRuntimeStore.Store,
	authority: Authority,
	definition: ConfigTypes.TowerDefinition,
	userId: number,
	slot: number,
	placementCFrame: CFrame,
	overrides: { [string]: any }?
): (unknown, TowerRuntimeStore.PreparedCreate)
	local capability = authority.reserve(definition, userId, slot, overrides)
	local prepared = success(assertions, store:prepareCreate(capability, userId, slot, placementCFrame))
	return capability, prepared
end

local function create(
	assertions: Assertions,
	store: TowerRuntimeStore.Store,
	authority: Authority,
	definition: ConfigTypes.TowerDefinition,
	userId: number,
	slot: number,
	placementCFrame: CFrame
): TowerRuntimeStore.RuntimeTowerSnapshot
	local capability, prepared = prepare(assertions, store, authority, definition, userId, slot, placementCFrame, nil)
	assertions.isTrue(authority.commit(capability))
	return success(assertions, store:commitPreparedCreate(prepared.token))
end

local function assertExactSnapshotShape(assertions: Assertions, snapshot: any, attacking: boolean)
	local expected = {
		matchId = true,
		towerEpoch = true,
		runtimeTowerId = true,
		ownerUserId = true,
		towerId = true,
		unitId = true,
		level = true,
		targetEligibility = true,
		placementCFrame = true,
		totalInvestment = true,
		cooldownEndsServerTime = true,
		lifecycle = true,
	}
	if attacking then
		expected.targetMode = true
	end
	local count = 0
	for key in next, snapshot do
		assertions.isTrue(expected[key] == true)
		count += 1
	end
	local expectedCount = if attacking then 13 else 12
	assertions.equal(count, expectedCount)
	assertions.isTrue(table.isfrozen(snapshot))
	assertions.isNil(getmetatable(snapshot))
	assertions.isNil(snapshot.definition)
	assertions.isNil(snapshot.slot)
	assertions.isNil(snapshot.capability)
	assertions.isNil(snapshot.model)
	assertions.isNil(snapshot.player)
	assertions.isFalse(typeof(snapshot) == "Instance")
end

return TestHarness.suite("server tower runtime store", {
	TestHarness.case("authenticates complete roots and binds exact match and epoch identity", function(assertions)
		local store, authority, fixture = newStore(assertions)
		assertions.isTrue(table.isfrozen(store :: any))
		local identity = success(assertions, store:getIdentity())
		assertions.equal(identity.matchId, MATCH_ID)
		assertions.equal(identity.towerEpoch, TOWER_EPOCH)
		assertions.isTrue(table.isfrozen(identity))

		expectError(
			assertions,
			TowerRuntimeStore.newForTests(MATCH_ID, 1, fixture.rawSources, {
				inspectPreparedCapability = authority.inspect,
			}),
			"UNAUTHENTICATED_CONFIGURATION",
			"new"
		)
		local lookalike = table.freeze({
			assets = fixture.configuration.assets,
			towers = fixture.configuration.towers,
			enemies = fixture.configuration.enemies,
			difficulties = fixture.configuration.difficulties,
			maps = fixture.configuration.maps,
			waves = fixture.configuration.waves,
			economy = fixture.configuration.economy,
			banners = fixture.configuration.banners,
			defaultSettings = fixture.configuration.defaultSettings,
		})
		expectError(
			assertions,
			TowerRuntimeStore.newForTests(MATCH_ID, 1, lookalike, {
				inspectPreparedCapability = authority.inspect,
			}),
			"UNAUTHENTICATED_CONFIGURATION",
			"new"
		)
		for _, epoch in { 0, TowerRuntimeStore.MAX_EPOCH + 1, math.huge, 0 / 0 } do
			expectError(
				assertions,
				TowerRuntimeStore.newForTests(MATCH_ID, epoch, fixture.configuration, {
					inspectPreparedCapability = authority.inspect,
				}),
				"INVALID_EPOCH",
				"new"
			)
		end
		expectError(
			assertions,
			TowerRuntimeStore.newForTests("bad", 1, fixture.configuration, {
				inspectPreparedCapability = authority.inspect,
			}),
			"INVALID_MATCH_ID",
			"new"
		)
		expectError(
			assertions,
			TowerRuntimeStore.newForTests(MATCH_ID, 1, fixture.configuration, {
				inspectPreparedCapability = "not-a-function",
			}),
			"INVALID_DEPENDENCY",
			"new"
		)
	end),

	TestHarness.case("commits exact initial records for all three canonical roles", function(assertions)
		local store, authority, fixture = newStore(assertions)
		local placements = {
			CFrame.new(-12, 4, 8) * CFrame.Angles(0, math.rad(15), 0),
			CFrame.new(0, 4, 8) * CFrame.Angles(0, math.rad(30), 0),
			CFrame.new(12, 4, 8) * CFrame.Angles(0, math.rad(45), 0),
		}
		local single = create(assertions, store, authority, fixture.single, 101, 1, placements[1])
		local splash = create(assertions, store, authority, fixture.splash, 101, 2, placements[2])
		local support = create(assertions, store, authority, fixture.support, 101, 3, placements[3])

		for index, snapshot in { single, splash, support } do
			assertions.equal(snapshot.matchId, MATCH_ID)
			assertions.equal(snapshot.towerEpoch, TOWER_EPOCH)
			assertions.equal(snapshot.runtimeTowerId, index)
			assertions.equal(snapshot.ownerUserId, 101)
			assertions.equal(snapshot.level, 1)
			assertions.equal(snapshot.targetEligibility, TowerRuntimeStore.TARGET_ELIGIBILITY)
			assertions.equal(snapshot.placementCFrame, placements[index])
			assertions.equal(snapshot.cooldownEndsServerTime, TowerRuntimeStore.AVAILABLE_COOLDOWN_SERVER_TIME)
			assertions.equal(snapshot.lifecycle, "Active")
		end
		assertions.equal(single.towerId, TowerFixtures.SINGLE_TOWER_ID)
		assertions.equal(single.targetMode, "First")
		assertions.equal(single.totalInvestment, 125)
		assertions.equal(splash.towerId, TowerFixtures.SPLASH_TOWER_ID)
		assertions.equal(splash.targetMode, "Strongest")
		assertions.equal(splash.totalInvestment, 200)
		assertions.equal(support.towerId, TowerFixtures.SUPPORT_TOWER_ID)
		assertions.isNil(support.targetMode)
		assertions.equal(support.totalInvestment, 100)
		assertExactSnapshotShape(assertions, single, true)
		assertExactSnapshotShape(assertions, splash, true)
		assertExactSnapshotShape(assertions, support, false)

		local listed = success(assertions, store:list())
		assertions.isTrue(table.isfrozen(listed))
		assertions.equal(#listed, 3)
		for index, snapshot in listed do
			assertions.equal(snapshot.runtimeTowerId, index)
		end
		local metrics = store:getMetrics()
		assertions.equal(metrics.activeCount, 3)
		assertions.equal(metrics.lifetimeCount, 3)
		assertions.equal(metrics.nextRuntimeTowerId, 4)
		assertions.equal(metrics.activeOwnerCount, 1)
		assertions.equal(metrics.activeOwnerTowerCount, 3)
	end),

	TestHarness.case("keeps prepared truth private and aborts without accepting its planned ID", function(assertions)
		local store, authority, fixture = newStore(assertions)
		local capability, prepared =
			prepare(assertions, store, authority, fixture.single, 101, 1, CFrame.new(1, 2, 3), nil)
		assertions.isTrue(table.isfrozen(prepared))
		assertions.isTrue(table.isfrozen(prepared.token))
		assertExactSnapshotShape(assertions, prepared.plannedSnapshot, true)
		local metrics = store:getMetrics()
		assertions.equal(metrics.activeCount, 0)
		assertions.equal(metrics.lifetimeCount, 0)
		assertions.equal(metrics.nextRuntimeTowerId, 1)
		assertions.isTrue(metrics.retainsPreparedCreate)
		expectError(assertions, store:get(1), "REENTRANT", "get")
		expectError(assertions, store:list(), "REENTRANT", "list")
		expectError(assertions, store:commitPreparedCreate(table.freeze({})), "INVALID_TOKEN", "commitPreparedCreate")
		assertions.isTrue(success(assertions, store:abortPreparedCreate(prepared.token)))
		assertions.isTrue(authority.abort(capability))
		expectError(assertions, store:commitPreparedCreate(prepared.token), "INVALID_TOKEN", "commitPreparedCreate")
		assertions.equal(store:getMetrics().nextRuntimeTowerId, 1)

		local accepted = create(assertions, store, authority, fixture.single, 101, 1, CFrame.new(4, 5, 6))
		assertions.equal(accepted.runtimeTowerId, 1)
	end),

	TestHarness.case(
		"rejects forged stale cross-owner cross-slot and mismatched canonical bindings",
		function(assertions)
			local store, authority, fixture = newStore(assertions)
			expectError(
				assertions,
				store:prepareCreate(table.freeze({}), 101, 1, CFrame.new()),
				"INVALID_CAPABILITY",
				"prepareCreate"
			)
			assertions.isFalse(store:getMetrics().faulted)

			local wrongOwner = authority.reserve(fixture.single, 101, 1, nil)
			expectError(
				assertions,
				store:prepareCreate(wrongOwner, 202, 1, CFrame.new()),
				"WRONG_OWNER",
				"prepareCreate"
			)
			assertions.isTrue(authority.abort(wrongOwner))
			local wrongSlot = authority.reserve(fixture.single, 101, 1, nil)
			expectError(assertions, store:prepareCreate(wrongSlot, 101, 2, CFrame.new()), "WRONG_SLOT", "prepareCreate")
			assertions.isTrue(authority.abort(wrongSlot))

			local fixtures = {
				{ overrides = { matchId = "match:other" }, code = "WRONG_MATCH" },
				{ overrides = { towerEpoch = 2 }, code = "WRONG_EPOCH" },
				{ overrides = { towerId = "bad" }, code = "INVALID_TOWER_ID" },
				{ overrides = { unitId = "tower:wrong-kind" }, code = "INVALID_UNIT_ID" },
				{ overrides = { loadoutRevision = 0 }, code = "INVALID_CAPABILITY_BINDING" },
			}
			for _, case in fixtures do
				local token = authority.reserve(fixture.single, 101, 1, case.overrides)
				expectError(assertions, store:prepareCreate(token, 101, 1, CFrame.new()), case.code, "prepareCreate")
				assertions.isTrue(authority.abort(token))
			end

			local other = TowerFixtures.createAuthenticatedFixture()
			local wrongDefinition = authority.reserve(fixture.single, 101, 1, {
				definition = other.single,
			})
			expectError(
				assertions,
				store:prepareCreate(wrongDefinition, 101, 1, CFrame.new()),
				"INVALID_DEFINITION",
				"prepareCreate"
			)
			assertions.isTrue(authority.abort(wrongDefinition))

			local stale = authority.reserve(fixture.single, 101, 1, nil)
			assertions.isTrue(authority.commit(stale))
			expectError(
				assertions,
				store:prepareCreate(stale, 101, 1, CFrame.new()),
				"INVALID_CAPABILITY",
				"prepareCreate"
			)
			assertions.equal(store:getMetrics().nextRuntimeTowerId, 1)
		end
	),

	TestHarness.case("rejects malformed transforms without placement or Workspace policy", function(assertions)
		local store, authority, fixture = newStore(assertions)
		local capability = authority.reserve(fixture.single, 101, 1, nil)
		expectError(assertions, store:prepareCreate(capability, 101, 1, nil), "INVALID_CFRAME", "prepareCreate")
		for _, value in { "origin", {}, Vector3.new(), CFrame.new(0 / 0, 0, 0), CFrame.new(math.huge, 0, 0) } do
			expectError(assertions, store:prepareCreate(capability, 101, 1, value), "INVALID_CFRAME", "prepareCreate")
		end
		expectError(
			assertions,
			store:prepareCreate(capability, 101, 1, CFrame.new(TowerRuntimeStore.MAX_COORDINATE + 1, 0, 0)),
			"INVALID_CFRAME",
			"prepareCreate"
		)
		local boundary = CFrame.new(-TowerRuntimeStore.MAX_COORDINATE, TowerRuntimeStore.MAX_COORDINATE, 0)
		local prepared = success(assertions, store:prepareCreate(capability, 101, 1, boundary))
		assertions.equal(prepared.plannedSnapshot.placementCFrame, boundary)
		assertions.isTrue(success(assertions, store:abortPreparedCreate(prepared.token)))
		assertions.isTrue(authority.abort(capability))
		assertions.equal(store:getMetrics().activeCount, 0)
	end),

	TestHarness.case(
		"enforces placement caps per owner and TowerId and releases each exactly once",
		function(assertions)
			local store, authority, fixture = newStore(assertions)
			local first = create(assertions, store, authority, fixture.single, 101, 1, CFrame.new(1, 0, 0))
			create(assertions, store, authority, fixture.single, 101, 1, CFrame.new(2, 0, 0))
			local capped = authority.reserve(fixture.single, 101, 1, nil)
			expectError(
				assertions,
				store:prepareCreate(capped, 101, 1, CFrame.new(3, 0, 0)),
				"PLACEMENT_CAP_EXCEEDED",
				"prepareCreate"
			)
			assertions.isTrue(authority.abort(capped))

			local otherOwner = create(assertions, store, authority, fixture.single, -202, 1, CFrame.new(4, 0, 0))
			local otherTower = create(assertions, store, authority, fixture.splash, 101, 2, CFrame.new(5, 0, 0))
			assertions.equal(otherOwner.runtimeTowerId, 3)
			assertions.equal(otherTower.runtimeTowerId, 4)
			local removed = success(assertions, store:remove(first.runtimeTowerId))
			assertions.equal(removed.lifecycle, "Removed")
			assertions.equal(removed.runtimeTowerId, first.runtimeTowerId)
			assertExactSnapshotShape(assertions, removed, true)
			expectError(assertions, store:remove(first.runtimeTowerId), "STALE_RUNTIME_ID", "remove")

			local replacement = create(assertions, store, authority, fixture.single, 101, 1, CFrame.new(6, 0, 0))
			assertions.equal(replacement.runtimeTowerId, 5)
			local metrics = store:getMetrics()
			assertions.equal(metrics.activeCount, 4)
			assertions.equal(metrics.lifetimeCount, 5)
			assertions.equal(metrics.activeOwnerCount, 2)
			assertions.equal(metrics.activeOwnerTowerCount, 3)
		end
	),

	TestHarness.case("separates recoverable active capacity from permanent lifetime exhaustion", function(assertions)
		local store, authority, fixture = newStore(assertions, {
			maxActive = 2,
			maxLifetime = 3,
		})
		local first = create(assertions, store, authority, fixture.single, 101, 1, CFrame.new(1, 0, 0))
		local second = create(assertions, store, authority, fixture.single, 101, 1, CFrame.new(2, 0, 0))
		local capacity = authority.reserve(fixture.splash, 101, 2, nil)
		expectError(
			assertions,
			store:prepareCreate(capacity, 101, 2, CFrame.new(3, 0, 0)),
			"CAPACITY_EXCEEDED",
			"prepareCreate"
		)
		assertions.isTrue(authority.abort(capacity))
		success(assertions, store:remove(first.runtimeTowerId))
		local third = create(assertions, store, authority, fixture.splash, 101, 2, CFrame.new(3, 0, 0))
		assertions.equal(third.runtimeTowerId, 3)
		success(assertions, store:remove(second.runtimeTowerId))
		success(assertions, store:remove(third.runtimeTowerId))
		local exhausted = authority.reserve(fixture.support, 101, 3, nil)
		expectError(
			assertions,
			store:prepareCreate(exhausted, 101, 3, CFrame.new(4, 0, 0)),
			"ID_EXHAUSTED",
			"prepareCreate"
		)
		assertions.isTrue(authority.abort(exhausted))
		local metrics = store:getMetrics()
		assertions.equal(metrics.activeCount, 0)
		assertions.equal(metrics.lifetimeCount, 3)
		assertions.equal(metrics.nextRuntimeTowerId, 4)
		assertions.isFalse(metrics.faulted)
	end),

	TestHarness.case("returns fresh frozen snapshots and stable stale-ID outcomes", function(assertions)
		local store, authority, fixture = newStore(assertions)
		local first = create(assertions, store, authority, fixture.single, 101, 1, CFrame.new(1, 2, 3))
		create(assertions, store, authority, fixture.splash, 101, 2, CFrame.new(4, 5, 6))
		local queriedA = success(assertions, store:get(first.runtimeTowerId))
		local queriedB = success(assertions, store:get(first.runtimeTowerId))
		assertions.notEqual(queriedA, queriedB)
		assertions.equal(queriedA.placementCFrame, first.placementCFrame)
		local changed = pcall(function()
			(queriedA :: any).level = 99
		end)
		assertions.isFalse(changed)
		assertions.equal(success(assertions, store:get(first.runtimeTowerId)).level, 1)
		local listA = success(assertions, store:list())
		local listB = success(assertions, store:list())
		assertions.notEqual(listA, listB)
		assertions.notEqual(listA[1], listB[1])
		assertions.equal(listA[1].runtimeTowerId, 1)
		assertions.equal(listA[2].runtimeTowerId, 2)
		success(assertions, store:remove(first.runtimeTowerId))
		expectError(assertions, store:get(first.runtimeTowerId), "STALE_RUNTIME_ID", "get")
		expectError(assertions, store:get(99), "NOT_FOUND", "get")
		expectError(assertions, store:get(0), "INVALID_RUNTIME_ID", "get")
	end),

	TestHarness.case("faults closed on an issued next-ID collision with no partial record", function(assertions)
		local store, authority, fixture = newStore(assertions, {
			nextRuntimeTowerId = 1,
			issuedRuntimeTowerIds = { 1 },
		})
		local capability = authority.reserve(fixture.single, 101, 1, nil)
		expectError(assertions, store:prepareCreate(capability, 101, 1, CFrame.new()), "ID_COLLISION", "prepareCreate")
		local metrics = store:getMetrics()
		assertions.isTrue(metrics.faulted)
		assertions.equal(metrics.activeCount, 0)
		assertions.equal(metrics.lifetimeCount, 1)
		assertions.equal(metrics.nextRuntimeTowerId, 1)
		expectError(assertions, store:get(1), "FAULTED", "get")
		expectError(assertions, store:list(), "FAULTED", "list")
		expectError(assertions, store:getIdentity(), "FAULTED", "getIdentity")
		expectError(assertions, store:remove(1), "FAULTED", "remove")
		expectError(assertions, store:fault(), "FAULTED", "fault")
		assertions.isTrue(authority.abort(capability))
		assertions.isTrue(success(assertions, store:cleanup()))
		assertions.isFalse(store:getMetrics().faulted)
	end),

	TestHarness.case("faults throwing yielding malformed and reentrant capability inspectors", function(assertions)
		for _, mode in { "Throw", "Yield", "Malformed" } do
			local store, authority, fixture = newStore(assertions)
			authority.state.mode = mode :: AuthorityMode
			local capability = authority.reserve(fixture.single, 101, 1, nil)
			expectError(
				assertions,
				store:prepareCreate(capability, 101, 1, CFrame.new()),
				"CALLBACK_FAILED",
				"prepareCreate"
			)
			assertions.isTrue(store:getMetrics().faulted)
			assertions.equal(store:getMetrics().activeCount, 0)
			assertions.isTrue(authority.abort(capability))
		end

		local store, authority, fixture = newStore(assertions)
		local reentrantResult: any = nil
		authority.state.reenter = function()
			reentrantResult = store:get(1)
		end
		local capability = authority.reserve(fixture.single, 101, 1, nil)
		expectError(
			assertions,
			store:prepareCreate(capability, 101, 1, CFrame.new()),
			"CALLBACK_FAILED",
			"prepareCreate"
		)
		expectError(assertions, reentrantResult, "REENTRANT", "get")
		assertions.isTrue(store:getMetrics().faulted)
		assertions.isTrue(authority.abort(capability))
	end),

	TestHarness.case(
		"defers cleanup requested inside the inspector and closes the outer operation",
		function(assertions)
			local store, authority, fixture = newStore(assertions)
			local cleanupResult: any = nil
			authority.state.reenter = function()
				cleanupResult = store:cleanup()
			end
			local capability = authority.reserve(fixture.single, 101, 1, nil)
			expectError(assertions, store:prepareCreate(capability, 101, 1, CFrame.new()), "CLEANED", "prepareCreate")
			assertions.isTrue(cleanupResult.ok)
			assertions.isFalse(cleanupResult.value)
			local metrics = store:getMetrics()
			assertions.isTrue(metrics.cleaned)
			assertions.equal(metrics.activeCount, 0)
			assertions.isFalse(metrics.retainsConfiguration)
			assertions.isFalse(metrics.retainsCapabilityInspector)
			assertions.isTrue(authority.abort(capability))
			assertions.isFalse(success(assertions, store:cleanup()))
		end
	),

	TestHarness.case("distinguishes an aborted prepare from a faulted prepare", function(assertions)
		local store, authority, fixture = newStore(assertions)
		local capability, prepared = prepare(assertions, store, authority, fixture.single, 101, 1, CFrame.new(), nil)
		assertions.isTrue(success(assertions, store:failPreparedCreate(prepared.token)))
		assertions.isTrue(authority.abort(capability))
		local metrics = store:getMetrics()
		assertions.isTrue(metrics.faulted)
		assertions.isFalse(metrics.retainsPreparedCreate)
		assertions.equal(metrics.activeCount, 0)
		expectError(assertions, store:prepareCreate(capability, 101, 1, CFrame.new()), "FAULTED", "prepareCreate")
		expectError(assertions, store:abortPreparedCreate(prepared.token), "FAULTED", "abortPreparedCreate")

		local activeStore, activeAuthority, activeFixture = newStore(assertions)
		local active = create(assertions, activeStore, activeAuthority, activeFixture.single, 101, 1, CFrame.new())
		assertions.isTrue(success(assertions, activeStore:fault()))
		assertions.equal(activeStore:getMetrics().activeCount, 1)
		expectError(assertions, activeStore:get(active.runtimeTowerId), "FAULTED", "get")
		assertions.isTrue(success(assertions, activeStore:cleanup()))
	end),

	TestHarness.case("cleans active and prepared state idempotently and makes late tokens inert", function(assertions)
		local store, authority, fixture = newStore(assertions)
		local active = create(assertions, store, authority, fixture.single, 101, 1, CFrame.new())
		local capability, prepared =
			prepare(assertions, store, authority, fixture.splash, 101, 2, CFrame.new(5, 0, 0), nil)
		assertions.isTrue(success(assertions, store:cleanup()))
		local metrics = store:getMetrics()
		assertions.isTrue(metrics.cleaned)
		assertions.isFalse(metrics.faulted)
		assertions.equal(metrics.activeCount, 0)
		assertions.equal(metrics.lifetimeCount, 0)
		assertions.equal(metrics.nextRuntimeTowerId, 1)
		assertions.equal(metrics.issuedIdCount, 0)
		assertions.equal(metrics.activeOwnerCount, 0)
		assertions.equal(metrics.activeOwnerTowerCount, 0)
		assertions.isFalse(metrics.retainsIdentity)
		assertions.isFalse(metrics.retainsConfiguration)
		assertions.isFalse(metrics.retainsCapabilityInspector)
		assertions.isFalse(metrics.retainsPreparedCreate)
		expectError(assertions, store:commitPreparedCreate(prepared.token), "CLEANED", "commitPreparedCreate")
		expectError(assertions, store:abortPreparedCreate(prepared.token), "CLEANED", "abortPreparedCreate")
		expectError(assertions, store:get(active.runtimeTowerId), "CLEANED", "get")
		expectError(assertions, store:remove(active.runtimeTowerId), "CLEANED", "remove")
		assertions.isTrue(authority.abort(capability))
		assertions.isFalse(success(assertions, store:cleanup()))
	end),

	TestHarness.case(
		"copies the canonical placement investment without arithmetic or behavior execution",
		function(assertions)
			local rawSources = TowerFixtures.rawSources()
			rawSources.towers[1].placementCost = Validation.MAX_SAFE_INTEGER
			for _, level in rawSources.towers[1].levels do
				level.upgradeCost = 0
			end
			local fixture = TowerFixtures.authenticateSources(rawSources)
			local store, authority = newStore(assertions, nil, fixture)
			local snapshot = create(assertions, store, authority, fixture.single, 101, 1, CFrame.new())
			assertions.equal(snapshot.totalInvestment, Validation.MAX_SAFE_INTEGER)
			assertions.equal(snapshot.level, 1)
			assertions.equal(snapshot.cooldownEndsServerTime, 0)
			assertions.isNil((store :: any).upgrade)
			assertions.isNil((store :: any).sell)
			assertions.isNil((store :: any).setTargetMode)
			assertions.isNil((store :: any).stepCooldown)
			assertions.isNil((store :: any).attack)
			assertions.isNil((store :: any).damage)
			assertions.isNil((store :: any).validatePlacement)
		end
	),
})
