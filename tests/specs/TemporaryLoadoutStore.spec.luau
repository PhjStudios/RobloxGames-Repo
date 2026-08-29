--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local Validation = require(ReplicatedStorage.Shared.util.Validation)

local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local TemporaryLoadoutStore = require(script.Parent.Parent.ProductionServerTowers.TemporaryLoadoutStore)
local TowerRuntimeStore = require(script.Parent.Parent.ProductionServerTowers.TowerRuntimeStore)

type Assertions = TestHarness.Assertions

local MATCH_ID = "match:phase12-temporary-loadout"
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
		error("expected temporary loadout operation to succeed", 0)
	end
	return result.value
end

local function definitions(fixture: TowerFixtures.AuthenticatedFixture): { any }
	return { fixture.single, fixture.splash, fixture.support }
end

local function participant(userId: number, state: string): any
	return table.freeze({
		userId = userId,
		state = state,
		ready = false,
	})
end

local function matchSnapshot(revision: number, participantsValue: { any }, matchId: string?): any
	local participants = table.clone(participantsValue)
	table.freeze(participants)
	return table.freeze({
		matchId = matchId or MATCH_ID,
		revision = revision,
		state = "PreWave",
		participants = participants,
	})
end

local function newStore(
	assertions: Assertions,
	options: { [string]: any }?,
	fixtureValue: TowerFixtures.AuthenticatedFixture?
): (TemporaryLoadoutStore.Store, TowerFixtures.AuthenticatedFixture)
	local fixture = fixtureValue or TowerFixtures.createAuthenticatedFixture()
	local constructor = TemporaryLoadoutStore.newForTests :: TemporaryLoadoutStore.TestConstructor?
	assertions.isNotNil(constructor)
	if constructor == nil then
		error("temporary loadout test constructor unavailable", 0)
	end
	local store = success(
		assertions,
		constructor(fixture.configuration, MATCH_ID, TOWER_EPOCH, definitions(fixture), options or {})
	)
	return store, fixture
end

local function activate(assertions: Assertions, store: TemporaryLoadoutStore.Store, participantsValue: { any }): any
	local snapshot = matchSnapshot(1, participantsValue)
	assertions.isTrue(success(assertions, store:synchronizeParticipants(snapshot)))
	assertions.isTrue(success(assertions, store:activate()))
	return snapshot
end

local function assertExactLoadoutShape(assertions: Assertions, snapshot: any)
	assertions.isTrue(table.isfrozen(snapshot))
	assertions.isNil(getmetatable(snapshot))
	local expectedRootFields = table.freeze({ matchId = true, revision = true, slots = true, userId = true })
	local rootCount = 0
	for key in next, snapshot do
		assertions.isTrue(expectedRootFields[key] == true)
		rootCount += 1
	end
	assertions.equal(rootCount, 4)
	assertions.isTrue(table.isfrozen(snapshot.slots))
	assertions.equal(#snapshot.slots, 5)
	for index = 1, 5 do
		local slot = snapshot.slots[index]
		assertions.isTrue(table.isfrozen(slot))
		assertions.isNil(getmetatable(slot))
		assertions.equal(slot.slot, index)
		local fieldCount = 0
		for _ in next, slot do
			fieldCount += 1
		end
		if index <= 3 then
			assertions.equal(slot.kind, "Occupied")
			assertions.equal(fieldCount, 4)
			assertions.isNotNil(slot.towerId)
			assertions.isNotNil(slot.unitId)
		else
			assertions.equal(slot.kind, "Empty")
			assertions.equal(fieldCount, 2)
			assertions.isNil(slot.towerId)
			assertions.isNil(slot.unitId)
		end
		assertions.isNil(slot.definition)
		assertions.isNil(slot.player)
	end
	assertions.isNil(snapshot.player)
	assertions.isNil(snapshot.capability)
	assertions.isFalse(typeof(snapshot) == "Instance")
end

local function prepareCapability(
	assertions: Assertions,
	store: TemporaryLoadoutStore.Store,
	userId: number,
	slot: number
): (TemporaryLoadoutStore.CreationCapability, TemporaryLoadoutStore.PreparedCapability)
	local capability = success(assertions, store:issueCreationCapability(userId, slot))
	local prepared = success(assertions, store:prepareCreationCapability(capability))
	return capability, prepared
end

return TestHarness.suite("TemporaryLoadoutStore", {
	TestHarness.case("authenticates exact fixture definitions and rejects foreign identity", function(assertions)
		local fixture = TowerFixtures.createAuthenticatedFixture()
		local created = TemporaryLoadoutStore.new(fixture.configuration, MATCH_ID, TOWER_EPOCH, definitions(fixture))
		local store = success(assertions, created)
		assertions.equal(store:getMetrics().state, "Prepared")
		assertions.isTrue(success(assertions, store:cleanup()))

		expectError(
			assertions,
			TemporaryLoadoutStore.new(fixture.rawSources, MATCH_ID, TOWER_EPOCH, definitions(fixture)),
			"UNAUTHENTICATED_CONFIGURATION",
			"new"
		)
		expectError(
			assertions,
			TemporaryLoadoutStore.new(fixture.configuration, "tower:wrong", TOWER_EPOCH, definitions(fixture)),
			"INVALID_MATCH_ID",
			"new"
		)
		for _, epoch in { 0, -1, 4_097, 0 / 0, math.huge } do
			expectError(
				assertions,
				TemporaryLoadoutStore.new(fixture.configuration, MATCH_ID, epoch, definitions(fixture)),
				"INVALID_EPOCH",
				"new"
			)
		end

		local other = TowerFixtures.createAuthenticatedFixture()
		local invalidDefinitions = {
			{ other.single, fixture.splash, fixture.support },
			{ fixture.single, fixture.single, fixture.support },
			{ fixture.splash, fixture.single, fixture.support },
			{ fixture.single, fixture.splash },
			{ fixture.single, fixture.splash, fixture.support, fixture.single },
		}
		for _, definitionList in invalidDefinitions do
			expectError(
				assertions,
				TemporaryLoadoutStore.new(fixture.configuration, MATCH_ID, TOWER_EPOCH, definitionList),
				"INVALID_DEFINITIONS",
				"new"
			)
		end

		local constructor = TemporaryLoadoutStore.newForTests :: TemporaryLoadoutStore.TestConstructor
		expectError(
			assertions,
			constructor(fixture.configuration, MATCH_ID, TOWER_EPOCH, definitions(fixture), {
				unexpected = true,
			}),
			"INVALID_TEST_OPTIONS",
			"new"
		)
	end),

	TestHarness.case("creates exact stable five-slot snapshots for positive and negative users", function(assertions)
		local store, fixture = newStore(assertions)
		local source = matchSnapshot(7, {
			participant(-7, "Active"),
			participant(40, "Active"),
		})
		assertions.isTrue(success(assertions, store:synchronizeParticipants(source)))
		assertions.isFalse(success(assertions, store:synchronizeParticipants(source)))
		assertions.isTrue(success(assertions, store:activate()))

		local negative = success(assertions, store:getLoadout(-7))
		local positive = success(assertions, store:getLoadout(40))
		assertExactLoadoutShape(assertions, negative)
		assertExactLoadoutShape(assertions, positive)
		assertions.equal(negative.matchId, MATCH_ID)
		assertions.equal(negative.userId, -7)
		assertions.equal(negative.revision, 1)
		assertions.equal(positive.revision, 2)
		assertions.equal(negative.slots[1].towerId, fixture.single.id)
		assertions.equal(negative.slots[2].towerId, fixture.splash.id)
		assertions.equal(negative.slots[3].towerId, fixture.support.id)
		assertions.equal(negative.slots[1].unitId, "unit:p12-e1-n7-s1")
		assertions.equal(positive.slots[3].unitId, "unit:p12-e1-p40-s3")
		assertions.notEqual(negative.slots[1].unitId, positive.slots[1].unitId)

		local repeated = success(assertions, store:getLoadout(-7))
		assertions.notEqual(repeated, negative)
		assertions.notEqual(repeated.slots, negative.slots)
		assertions.notEqual(repeated.slots[1], negative.slots[1])
		assertions.equal(repeated.slots[1].unitId, negative.slots[1].unitId)

		local metrics = store:getMetrics()
		assertions.equal(metrics.state, "Active")
		assertions.equal(metrics.loadoutCount, 2)
		assertions.equal(metrics.unitIdCount, 6)
		assertions.equal(metrics.occupiedSlotCount, 6)
		assertions.equal(metrics.emptySlotCount, 4)
		assertions.equal(metrics.nextLoadoutRevision, 3)
		assertions.equal(metrics.lastParticipantRevision, 7)
		assertions.isTrue(metrics.retainsParticipantSnapshot)
		assertions.isTrue(success(assertions, store:cleanup()))
	end),

	TestHarness.case(
		"admits only first Active observation and retains disconnect return spectator identities",
		function(assertions)
			local store = newStore(assertions)
			activate(assertions, store, {
				participant(10, "Active"),
				participant(20, "Disconnected"),
				participant(30, "Returned"),
				participant(40, "Spectator"),
			})

			local original = success(assertions, store:getLoadout(10))
			for _, userId in { 20, 30, 40, 99 } do
				expectError(assertions, store:getLoadout(userId), "NOT_FOUND", "getLoadout")
			end

			assertions.isTrue(success(
				assertions,
				store:synchronizeParticipants(matchSnapshot(2, {
					participant(10, "Disconnected"),
					participant(20, "Active"),
					participant(30, "Returned"),
					participant(40, "Spectator"),
				}))
			))
			local admittedLater = success(assertions, store:getLoadout(20))
			assertions.equal(admittedLater.revision, 2)

			assertions.isFalse(success(
				assertions,
				store:synchronizeParticipants(matchSnapshot(3, {
					participant(10, "Returned"),
					participant(20, "Spectator"),
					participant(30, "Returned"),
					participant(40, "Spectator"),
				}))
			))
			local retainedTen = success(assertions, store:getLoadout(10))
			local retainedTwenty = success(assertions, store:getLoadout(20))
			assertions.equal(retainedTen.revision, original.revision)
			assertions.equal(retainedTen.slots[1].unitId, original.slots[1].unitId)
			assertions.equal(retainedTwenty.revision, admittedLater.revision)
			assertions.equal(retainedTwenty.slots[2].unitId, admittedLater.slots[2].unitId)
			assertions.isTrue(success(assertions, store:cleanup()))
		end
	),

	TestHarness.case("supports maximum safe Studio user identities without scientific notation", function(assertions)
		local store = newStore(assertions)
		activate(assertions, store, {
			participant(-Validation.MAX_SAFE_INTEGER, "Active"),
			participant(Validation.MAX_SAFE_INTEGER, "Active"),
		})
		local negative = success(assertions, store:getLoadout(-Validation.MAX_SAFE_INTEGER))
		local positive = success(assertions, store:getLoadout(Validation.MAX_SAFE_INTEGER))
		assertions.equal(negative.slots[1].unitId, "unit:p12-e1-n9007199254740991-s1")
		assertions.equal(positive.slots[3].unitId, "unit:p12-e1-p9007199254740991-s3")
		assertions.isNil(string.find(positive.slots[3].unitId, "+", 1, true))
		assertions.isTrue(success(assertions, store:cleanup()))
	end),

	TestHarness.case("faults stale copied malformed and wrong-match participant snapshots", function(assertions)
		local equalStore = newStore(assertions)
		local first = activate(assertions, equalStore, { participant(10, "Active") })
		assertions.isFalse(success(assertions, equalStore:synchronizeParticipants(first)))
		expectError(
			assertions,
			equalStore:synchronizeParticipants(matchSnapshot(1, { participant(10, "Active") })),
			"STALE_PARTICIPANT_SNAPSHOT",
			"synchronizeParticipants"
		)
		assertions.isTrue(equalStore:getMetrics().faulted)
		expectError(assertions, equalStore:getLoadout(10), "FAULTED", "getLoadout")
		assertions.isTrue(success(assertions, equalStore:cleanup()))

		local lowerStore = newStore(assertions)
		activate(assertions, lowerStore, { participant(10, "Active") })
		assertions.isFalse(success(
			assertions,
			lowerStore:synchronizeParticipants(matchSnapshot(3, {
				participant(10, "Active"),
			}))
		))
		expectError(
			assertions,
			lowerStore:synchronizeParticipants(matchSnapshot(2, { participant(10, "Active") })),
			"STALE_PARTICIPANT_SNAPSHOT",
			"synchronizeParticipants"
		)
		assertions.isTrue(success(assertions, lowerStore:cleanup()))

		local wrongMatchStore = newStore(assertions)
		expectError(
			assertions,
			wrongMatchStore:synchronizeParticipants(matchSnapshot(1, {}, "match:other")),
			"WRONG_MATCH",
			"synchronizeParticipants"
		)
		assertions.isTrue(success(assertions, wrongMatchStore:cleanup()))

		local malformedStore = newStore(assertions)
		expectError(
			assertions,
			malformedStore:synchronizeParticipants({
				matchId = MATCH_ID,
				revision = 1,
				state = "PreWave",
				participants = {},
			}),
			"INVALID_PARTICIPANT_SNAPSHOT",
			"synchronizeParticipants"
		)
		assertions.isTrue(success(assertions, malformedStore:cleanup()))
	end),

	TestHarness.case("faults atomically on loadout UnitId revision and admission limits", function(assertions)
		local collisionStore = newStore(assertions, {
			makeUnitId = function(_epoch: number, _userId: number, _slot: number): unknown
				return "unit:phase12-collision"
			end,
		})
		expectError(
			assertions,
			collisionStore:synchronizeParticipants(matchSnapshot(1, { participant(10, "Active") })),
			"UNIT_ID_COLLISION",
			"synchronizeParticipants"
		)
		assertions.equal(collisionStore:getMetrics().loadoutCount, 0)
		assertions.equal(collisionStore:getMetrics().unitIdCount, 0)
		assertions.isTrue(success(assertions, collisionStore:cleanup()))

		local invalidStore = newStore(assertions, {
			makeUnitId = function(_epoch: number, _userId: number, _slot: number): unknown
				return "tower:wrong-kind"
			end,
		})
		expectError(
			assertions,
			invalidStore:synchronizeParticipants(matchSnapshot(1, { participant(10, "Active") })),
			"UNIT_ID_FAILED",
			"synchronizeParticipants"
		)
		assertions.isTrue(success(assertions, invalidStore:cleanup()))

		local unitBoundStore = newStore(assertions, { maxUnitIds = 2 })
		expectError(
			assertions,
			unitBoundStore:synchronizeParticipants(matchSnapshot(1, { participant(10, "Active") })),
			"UNIT_ID_EXHAUSTED",
			"synchronizeParticipants"
		)
		assertions.isTrue(success(assertions, unitBoundStore:cleanup()))

		local admissionStore = newStore(assertions, { maxLoadouts = 1 })
		expectError(
			assertions,
			admissionStore:synchronizeParticipants(matchSnapshot(1, {
				participant(10, "Active"),
				participant(20, "Active"),
			})),
			"CAPACITY_EXCEEDED",
			"synchronizeParticipants"
		)
		assertions.isTrue(success(assertions, admissionStore:cleanup()))

		local revisionStore = newStore(assertions, { nextLoadoutRevision = Validation.MAX_SAFE_INTEGER })
		expectError(
			assertions,
			revisionStore:synchronizeParticipants(matchSnapshot(1, { participant(10, "Active") })),
			"REVISION_EXHAUSTED",
			"synchronizeParticipants"
		)
		assertions.isTrue(success(assertions, revisionStore:cleanup()))
	end),

	TestHarness.case("contains throwing yielding reentrant and cleanup UnitId callbacks", function(assertions)
		for _, mode in { "throw", "yield" } do
			local store = newStore(assertions, {
				makeUnitId = function(_epoch: number, _userId: number, _slot: number): unknown
					if mode == "throw" then
						error("injected UnitId failure", 0)
					end
					coroutine.yield()
					return nil
				end,
			})
			expectError(
				assertions,
				store:synchronizeParticipants(matchSnapshot(1, { participant(10, "Active") })),
				"CALLBACK_FAILED",
				"synchronizeParticipants"
			)
			assertions.isTrue(store:getMetrics().faulted)
			assertions.isTrue(success(assertions, store:cleanup()))
		end

		local reentryStore: TemporaryLoadoutStore.Store? = nil
		local constructed = newStore(assertions, {
			makeUnitId = function(epoch: number, userId: number, slot: number): unknown
				local current = reentryStore :: TemporaryLoadoutStore.Store
				expectError(assertions, current:getLoadout(userId), "REENTRANT", "getLoadout")
				local sign = if userId > 0 then "p" else "n"
				return `unit:p12-e{epoch}-{sign}{math.abs(userId)}-s{slot}`
			end,
		})
		reentryStore = constructed
		expectError(
			assertions,
			constructed:synchronizeParticipants(matchSnapshot(1, { participant(10, "Active") })),
			"CALLBACK_FAILED",
			"synchronizeParticipants"
		)
		assertions.isTrue(success(assertions, constructed:cleanup()))

		local cleanupStore: TemporaryLoadoutStore.Store? = nil
		local cleanupConstructed = newStore(assertions, {
			makeUnitId = function(epoch: number, userId: number, slot: number): unknown
				local current = cleanupStore :: TemporaryLoadoutStore.Store
				assertions.isFalse(success(assertions, current:cleanup()))
				return `unit:p12-e{epoch}-p{userId}-s{slot}`
			end,
		})
		cleanupStore = cleanupConstructed
		expectError(
			assertions,
			cleanupConstructed:synchronizeParticipants(matchSnapshot(1, { participant(10, "Active") })),
			"CLEANED",
			"synchronizeParticipants"
		)
		assertions.isTrue(cleanupConstructed:getMetrics().cleaned)
		assertions.isFalse(success(assertions, cleanupConstructed:cleanup()))
	end),

	TestHarness.case("issues opaque one-use capabilities and exact prepared bindings", function(assertions)
		local store, fixture = newStore(assertions)
		activate(assertions, store, { participant(101, "Active"), participant(202, "Spectator") })
		expectError(assertions, store:issueCreationCapability(202, 1), "NOT_FOUND", "issueCreationCapability")
		expectError(assertions, store:issueCreationCapability(101, 4), "EMPTY_SLOT", "issueCreationCapability")
		expectError(assertions, store:issueCreationCapability(101, 0), "INVALID_SLOT", "issueCreationCapability")

		local capability = success(assertions, store:issueCreationCapability(101, 1))
		assertions.isTrue(table.isfrozen(capability))
		assertions.isNil(next(capability))
		expectError(assertions, store:issueCreationCapability(101, 1), "CAPABILITY_ACTIVE", "issueCreationCapability")
		local secondIssued = success(assertions, store:issueCreationCapability(101, 2))
		local prepared = success(assertions, store:prepareCreationCapability(capability))
		assertions.isTrue(table.isfrozen(prepared))
		assertions.isNil(next(prepared))
		expectError(
			assertions,
			store:prepareCreationCapability(capability),
			"INVALID_CAPABILITY",
			"prepareCreationCapability"
		)
		expectError(
			assertions,
			store:prepareCreationCapability(secondIssued),
			"CAPABILITY_ACTIVE",
			"prepareCreationCapability"
		)

		local inspector = success(assertions, store:getPreparedCapabilityInspector())
		assertions.equal(inspector, success(assertions, store:getPreparedCapabilityInspector()))
		expectError(assertions, inspector(table.freeze({})), "INVALID_CAPABILITY", "inspectPreparedCapability")
		local inspected = success(assertions, inspector(prepared))
		assertions.isTrue(table.isfrozen(inspected))
		assertions.equal(inspected.matchId, MATCH_ID)
		assertions.equal(inspected.towerEpoch, TOWER_EPOCH)
		assertions.equal(inspected.userId, 101)
		assertions.equal(inspected.loadoutRevision, 1)
		assertions.equal(inspected.slot, 1)
		assertions.equal(inspected.towerId, fixture.single.id)
		assertions.equal(inspected.unitId, "unit:p12-e1-p101-s1")
		assertions.equal(inspected.definition, fixture.single)
		expectError(assertions, inspector(prepared), "INVALID_CAPABILITY", "inspectPreparedCapability")
		assertions.isTrue(success(assertions, store:commitPreparedCapability(prepared)))
		expectError(assertions, store:commitPreparedCapability(prepared), "INVALID_TOKEN", "commitPreparedCapability")
		expectError(
			assertions,
			store:prepareCreationCapability(capability),
			"INVALID_CAPABILITY",
			"prepareCreationCapability"
		)

		local replacement = success(assertions, store:issueCreationCapability(101, 1))
		local replacementPrepared = success(assertions, store:prepareCreationCapability(replacement))
		expectError(
			assertions,
			store:commitPreparedCapability(replacementPrepared),
			"INVALID_TOKEN",
			"commitPreparedCapability"
		)
		assertions.isTrue(success(assertions, store:abortPreparedCapability(replacementPrepared)))

		local secondPrepared = success(assertions, store:prepareCreationCapability(secondIssued))
		assertions.isTrue(success(assertions, store:abortPreparedCapability(secondPrepared)))
		assertions.equal(store:getMetrics().issuedCapabilityCount, 0)
		assertions.equal(store:getMetrics().reservedCapabilityCount, 0)
		assertions.isTrue(success(assertions, store:cleanup()))
	end),

	TestHarness.case("faults on capability generation exhaustion and revokes all authority", function(assertions)
		local store = newStore(assertions, { maxCapabilityGeneration = 1 })
		activate(assertions, store, { participant(101, "Active") })
		local _, prepared = prepareCapability(assertions, store, 101, 1)
		assertions.isTrue(success(assertions, store:abortPreparedCapability(prepared)))
		expectError(
			assertions,
			store:issueCreationCapability(101, 1),
			"CAPABILITY_EXHAUSTED",
			"issueCreationCapability"
		)
		assertions.isTrue(store:getMetrics().faulted)
		assertions.equal(store:getMetrics().issuedCapabilityCount, 0)
		assertions.equal(store:getMetrics().reservedCapabilityCount, 0)
		assertions.isTrue(success(assertions, store:cleanup()))
	end),

	TestHarness.case(
		"bridges real capabilities into TowerRuntimeStore and rejects cross-owner replay",
		function(assertions)
			local loadoutStore, fixture = newStore(assertions)
			activate(assertions, loadoutStore, { participant(101, "Active"), participant(202, "Active") })
			local inspector = success(assertions, loadoutStore:getPreparedCapabilityInspector())
			local runtimeStore =
				success(assertions, TowerRuntimeStore.new(MATCH_ID, TOWER_EPOCH, fixture.configuration, inspector))

			local acceptedTokens: { TemporaryLoadoutStore.PreparedCapability } = {}
			local retainedCommitResult: unknown? = nil
			for slot = 1, 3 do
				local _, preparedCapability = prepareCapability(assertions, loadoutStore, 101, slot)
				local preparedCreate = success(
					assertions,
					runtimeStore:prepareCreate(preparedCapability, 101, slot, CFrame.new(slot * 5, 0, 0))
				)
				assertions.equal(preparedCreate.plannedSnapshot.ownerUserId, 101)
				assertions.equal(preparedCreate.plannedSnapshot.towerId, definitions(fixture)[slot].id)
				assertions.equal(preparedCreate.plannedSnapshot.unitId, `unit:p12-e1-p101-s{slot}`)
				local commitResult = loadoutStore:commitPreparedCapability(preparedCapability)
				assertions.isTrue(success(assertions, commitResult))
				if retainedCommitResult == nil then
					retainedCommitResult = commitResult
				else
					assertions.equal(commitResult, retainedCommitResult)
				end
				local committed = success(assertions, runtimeStore:commitPreparedCreate(preparedCreate.token))
				assertions.equal(committed.runtimeTowerId, slot)
				table.insert(acceptedTokens, preparedCapability)
			end
			assertions.equal(runtimeStore:getMetrics().activeCount, 3)

			local _, wrongOwner = prepareCapability(assertions, loadoutStore, 202, 1)
			expectError(
				assertions,
				runtimeStore:prepareCreate(wrongOwner, 101, 1, CFrame.new()),
				"WRONG_OWNER",
				"prepareCreate"
			)
			assertions.isTrue(success(assertions, loadoutStore:abortPreparedCapability(wrongOwner)))
			expectError(
				assertions,
				runtimeStore:prepareCreate(wrongOwner, 202, 1, CFrame.new()),
				"INVALID_CAPABILITY",
				"prepareCreate"
			)

			local _, wrongSlot = prepareCapability(assertions, loadoutStore, 202, 2)
			expectError(
				assertions,
				runtimeStore:prepareCreate(wrongSlot, 202, 3, CFrame.new()),
				"WRONG_SLOT",
				"prepareCreate"
			)
			assertions.isTrue(success(assertions, loadoutStore:abortPreparedCapability(wrongSlot)))
			for _, replay in acceptedTokens do
				expectError(
					assertions,
					runtimeStore:prepareCreate(replay, 101, 1, CFrame.new()),
					"INVALID_CAPABILITY",
					"prepareCreate"
				)
			end

			assertions.isTrue(success(assertions, runtimeStore:cleanup()))
			assertions.isTrue(success(assertions, loadoutStore:cleanup()))
			expectError(assertions, inspector(wrongSlot), "CLEANED", "inspectPreparedCapability")
			assertions.equal(runtimeStore:getMetrics().activeCount, 0)
			assertions.equal(loadoutStore:getMetrics().loadoutCount, 0)
		end
	),

	TestHarness.case(
		"makes old-store capabilities inert across match replacement fault and cleanup",
		function(assertions)
			local first, fixture = newStore(assertions)
			activate(assertions, first, { participant(101, "Active") })
			local _, prepared = prepareCapability(assertions, first, 101, 1)
			local firstInspector = success(assertions, first:getPreparedCapabilityInspector())

			local second = success(
				assertions,
				TemporaryLoadoutStore.new(
					fixture.configuration,
					"match:phase12-replacement",
					TOWER_EPOCH,
					definitions(fixture)
				)
			)
			local replacementSnapshot = matchSnapshot(1, { participant(101, "Active") }, "match:phase12-replacement")
			assertions.isTrue(success(assertions, second:synchronizeParticipants(replacementSnapshot)))
			assertions.isTrue(success(assertions, second:activate()))
			local secondInspector = success(assertions, second:getPreparedCapabilityInspector())
			expectError(assertions, secondInspector(prepared), "INVALID_CAPABILITY", "inspectPreparedCapability")

			assertions.isTrue(success(assertions, first:fault()))
			expectError(assertions, firstInspector(prepared), "FAULTED", "inspectPreparedCapability")
			expectError(assertions, first:getLoadout(101), "FAULTED", "getLoadout")
			assertions.isTrue(success(assertions, first:cleanup()))
			expectError(assertions, firstInspector(prepared), "CLEANED", "inspectPreparedCapability")
			assertions.isFalse(success(assertions, first:cleanup()))
			local metrics = first:getMetrics()
			assertions.equal(metrics.state, "Cleaned")
			assertions.equal(metrics.loadoutCount, 0)
			assertions.equal(metrics.unitIdCount, 0)
			assertions.equal(metrics.issuedCapabilityCount, 0)
			assertions.equal(metrics.reservedCapabilityCount, 0)
			assertions.isFalse(metrics.retainsIdentity)
			assertions.isFalse(metrics.retainsConfiguration)
			assertions.isFalse(metrics.retainsDefinitions)
			assertions.isFalse(metrics.retainsParticipantSnapshot)
			assertions.isFalse(metrics.retainsInspector)
			assertions.isTrue(success(assertions, second:cleanup()))
		end
	),
})
