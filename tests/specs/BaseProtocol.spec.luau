--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Shared = game:GetService("ReplicatedStorage").Shared
local BaseProtocol = require(Shared.match.BaseProtocol)
local PayloadValidation = require(Shared.network.PayloadValidation)
local Validation = require(Shared.util.Validation)

type Assertions = TestHarness.Assertions

local function validSnapshot(): { [string]: any }
	return {
		matchId = "match:phase10-protocol",
		enemyEpoch = 7,
		mapId = "map:phase10-protocol",
		difficultyId = "difficulty:phase10-protocol",
		basePosition = Vector3.new(20, 5, -20),
		baseRevision = 3,
		status = "Active",
		currentHealth = 75,
		maximumHealth = 100,
		lowHealth = false,
		initializedServerTime = 10,
		updatedServerTime = 12,
	}
end

local function expectSnapshotSuccess(assertions: Assertions, value: unknown): BaseProtocol.BaseSnapshot
	local result = BaseProtocol.validateBaseSnapshot(value)
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local snapshot = (result :: any).value :: BaseProtocol.BaseSnapshot
	assertions.isTrue(table.isfrozen(snapshot))
	return snapshot
end

local function expectSnapshotFailure(
	assertions: Assertions,
	value: unknown,
	code: Validation.Code?,
	path: string?
): Validation.Issue
	local result = BaseProtocol.validateBaseSnapshot(value)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local issue = (result :: any).error :: Validation.Issue
	assertions.isTrue(table.isfrozen(issue))
	assertions.isTrue(table.isfrozen(issue.pathSegments))
	if code ~= nil then
		assertions.equal(issue.code, code)
	end
	if path ~= nil then
		assertions.equal(issue.path, path)
	end
	return issue
end

local function expectMessageSuccess(assertions: Assertions, value: unknown): BaseProtocol.BaseReplicationMessage
	local result = BaseProtocol.validateBaseReplicationMessage(value)
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local message = (result :: any).value :: BaseProtocol.BaseReplicationMessage
	assertions.isTrue(table.isfrozen(message))
	assertions.isTrue(table.isfrozen(message.snapshot))
	return message
end

local function expectMessageFailure(
	assertions: Assertions,
	value: unknown,
	code: Validation.Code?,
	path: string?
): Validation.Issue
	local result = BaseProtocol.validateBaseReplicationMessage(value)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	local issue = (result :: any).error :: Validation.Issue
	assertions.isTrue(table.isfrozen(issue))
	if code ~= nil then
		assertions.equal(issue.code, code)
	end
	if path ~= nil then
		assertions.equal(issue.path, path)
	end
	return issue
end

return TestHarness.suite("base protocol wire contract", {
	TestHarness.case("exports the exact endpoints bounds kinds and authenticated schemas", function(assertions)
		assertions.equal(BaseProtocol.GET_BASE_SNAPSHOT_ENDPOINT, "GetBaseSnapshot")
		assertions.equal(BaseProtocol.BASE_REPLICATION_ENDPOINT, "BaseReplication")
		assertions.equal(BaseProtocol.STATE_KIND, "State")
		assertions.equal(BaseProtocol.DAMAGE_KIND, "Damage")
		assertions.equal(table.concat(BaseProtocol.REPLICATION_KINDS, ","), "State,Damage")
		assertions.equal(BaseProtocol.MAX_ENEMY_EPOCH, 4_096)
		assertions.equal(BaseProtocol.MAX_BASE_COORDINATE, 100_000)
		assertions.equal(BaseProtocol.MAX_LEAKS_PER_MESSAGE, 128)
		assertions.equal(BaseProtocol.MAX_BROADCAST_RECIPIENTS, 4)
		assertions.equal(BaseProtocol.MAX_LIFETIME_PUBLICATIONS, 4_098)
		assertions.equal(BaseProtocol.MAX_BASE_REVISION, Validation.MAX_SAFE_INTEGER)
		assertions.isTrue(table.isfrozen(BaseProtocol))
		assertions.isTrue(table.isfrozen(BaseProtocol.REPLICATION_KINDS))
		assertions.isTrue(PayloadValidation.isSchema(BaseProtocol.GetBaseSnapshotPayloadSchema))
		assertions.isTrue(PayloadValidation.isSchema(BaseProtocol.BaseSnapshotSchema))
		assertions.isTrue(PayloadValidation.isSchema(BaseProtocol.BaseReplicationSchema))
		assertions.isTrue(table.isfrozen(BaseProtocol.GetBaseSnapshotPayloadSchema))
		assertions.isTrue(table.isfrozen(BaseProtocol.BaseSnapshotSchema))
		assertions.isTrue(table.isfrozen(BaseProtocol.BaseReplicationSchema))
	end),

	TestHarness.case("accepts only the exact detached empty recovery payload", function(assertions)
		local authored = {}
		local result = BaseProtocol.GetBaseSnapshotPayloadSchema:validate(authored)
		assertions.isTrue(result.ok)
		assertions.notEqual((result :: any).value, authored)
		assertions.isTrue(table.isfrozen((result :: any).value))
		assertions.isFalse(BaseProtocol.GetBaseSnapshotPayloadSchema:validate({ extra = true }).ok)
		assertions.isFalse(BaseProtocol.GetBaseSnapshotPayloadSchema:validate(setmetatable({}, {})).ok)
		assertions.isFalse(BaseProtocol.GetBaseSnapshotPayloadSchema:validate(Instance.new("Folder")).ok)
	end),

	TestHarness.case("validates detaches and freezes complete authoritative snapshots", function(assertions)
		local authored = validSnapshot()
		local snapshot = expectSnapshotSuccess(assertions, authored)
		assertions.notEqual(snapshot, authored)
		assertions.equal(snapshot.matchId, authored.matchId)
		assertions.equal(snapshot.basePosition, authored.basePosition)
		assertions.equal(snapshot.currentHealth, 75)

		authored.matchId = "match:changed"
		authored.currentHealth = 1
		authored.basePosition = Vector3.zero
		assertions.equal(snapshot.matchId, "match:phase10-protocol")
		assertions.equal(snapshot.currentHealth, 75)
		assertions.equal(snapshot.basePosition, Vector3.new(20, 5, -20))
	end),

	TestHarness.case(
		"enforces exact snapshot structure IDs epochs safe integers and finite values",
		function(assertions)
			local cases: { { field: string, value: any } } = {
				{ field = "matchId", value = "map:phase10-protocol" },
				{ field = "enemyEpoch", value = 0 },
				{ field = "enemyEpoch", value = 4_097 },
				{ field = "mapId", value = "match:phase10-protocol" },
				{ field = "difficultyId", value = "enemy:phase10-protocol" },
				{ field = "baseRevision", value = 0 },
				{ field = "baseRevision", value = 1.5 },
				{ field = "baseRevision", value = Validation.MAX_SAFE_INTEGER + 1 },
				{ field = "currentHealth", value = -1 },
				{ field = "currentHealth", value = 0 / 0 },
				{ field = "maximumHealth", value = 0 },
				{ field = "maximumHealth", value = math.huge },
				{ field = "initializedServerTime", value = -1 },
				{ field = "updatedServerTime", value = -math.huge },
				{ field = "status", value = "DefeatPending" },
				{ field = "lowHealth", value = 1 },
				{ field = "basePosition", value = "Workspace.DefenderBase" },
			}
			for _, fixture in cases do
				local value = validSnapshot()
				value[fixture.field] = fixture.value
				expectSnapshotFailure(assertions, value, nil, nil)
			end

			local missing = validSnapshot()
			missing.mapId = nil
			expectSnapshotFailure(assertions, missing, "MISSING_FIELD", "payload.mapId")
			local extra = validSnapshot()
			extra.marker = Instance.new("Part")
			expectSnapshotFailure(assertions, extra, "UNKNOWN_FIELD", "payload")
			expectSnapshotFailure(assertions, setmetatable(validSnapshot(), {}), "INVALID_TABLE", "payload")
		end
	),

	TestHarness.case("enforces health time position status and exact low-health invariants", function(assertions)
		local invalidCurrent = validSnapshot()
		invalidCurrent.currentHealth = 101
		expectSnapshotFailure(assertions, invalidCurrent, "INVALID_TOTAL", "payload.currentHealth")

		local badTime = validSnapshot()
		badTime.updatedServerTime = 9
		expectSnapshotFailure(assertions, badTime, "INVALID_ORDER", "payload.updatedServerTime")

		for _, position in
			{
				Vector3.new(100_001, 0, 0),
				Vector3.new(0, -100_001, 0),
				Vector3.new(0, 0, 100_001),
			}
		do
			local badPosition = validSnapshot()
			badPosition.basePosition = position
			expectSnapshotFailure(assertions, badPosition, "OUT_OF_RANGE", "payload.basePosition")
		end

		local falseLow = validSnapshot()
		falseLow.currentHealth = 25
		expectSnapshotFailure(assertions, falseLow, "INVALID_REFERENCE", "payload.lowHealth")
		local falseHealthy = validSnapshot()
		falseHealthy.currentHealth = 26
		falseHealthy.lowHealth = true
		expectSnapshotFailure(assertions, falseHealthy, "INVALID_REFERENCE", "payload.lowHealth")

		local zeroActive = validSnapshot()
		zeroActive.currentHealth = 0
		zeroActive.lowHealth = true
		expectSnapshotFailure(assertions, zeroActive, "INVALID_REFERENCE", "payload.status")
		local liveDefeated = validSnapshot()
		liveDefeated.status = "Defeated"
		expectSnapshotFailure(assertions, liveDefeated, "INVALID_REFERENCE", "payload.status")

		local threshold = validSnapshot()
		threshold.maximumHealth = 101
		threshold.currentHealth = 25
		threshold.lowHealth = true
		expectSnapshotSuccess(assertions, threshold)
		threshold.currentHealth = 26
		threshold.lowHealth = false
		expectSnapshotSuccess(assertions, threshold)

		local defeated = validSnapshot()
		defeated.status = "Defeated"
		defeated.currentHealth = 0
		defeated.lowHealth = true
		expectSnapshotSuccess(assertions, defeated)
		defeated.status = "Faulted"
		expectSnapshotSuccess(assertions, defeated)
	end),

	TestHarness.case("accepts detached State and bounded coalesced Damage messages", function(assertions)
		local authoredSnapshot = validSnapshot()
		local stateAuthored = {
			kind = "State",
			snapshot = authoredSnapshot,
		}
		local state = expectMessageSuccess(assertions, stateAuthored) :: BaseProtocol.BaseStateMessage
		assertions.equal(state.kind, "State")
		assertions.notEqual(state, stateAuthored)
		assertions.notEqual(state.snapshot, authoredSnapshot)

		local damageAuthored = {
			kind = "Damage",
			snapshot = validSnapshot(),
			appliedDamage = 25,
			leakCount = 2,
			lowHealthCrossed = false,
		}
		local damage = expectMessageSuccess(assertions, damageAuthored) :: BaseProtocol.BaseDamageMessage
		assertions.equal(damage.kind, "Damage")
		assertions.equal(damage.appliedDamage, 25)
		assertions.equal(damage.leakCount, 2)
		assertions.isFalse(damage.lowHealthCrossed)

		local crossingSnapshot = validSnapshot()
		crossingSnapshot.currentHealth = 25
		crossingSnapshot.lowHealth = true
		expectMessageSuccess(assertions, {
			kind = "Damage",
			snapshot = crossingSnapshot,
			appliedDamage = 50,
			leakCount = 4,
			lowHealthCrossed = true,
		})
	end),

	TestHarness.case("rejects malformed and contradictory Damage feedback", function(assertions)
		local function damageMessage(): { [string]: any }
			return {
				kind = "Damage",
				snapshot = validSnapshot(),
				appliedDamage = 25,
				leakCount = 2,
				lowHealthCrossed = false,
			}
		end

		local zeroDamage = damageMessage()
		zeroDamage.appliedDamage = 0
		expectMessageFailure(assertions, zeroDamage, nil, nil)
		local tooManyLeaks = damageMessage()
		tooManyLeaks.leakCount = 129
		expectMessageFailure(assertions, tooManyLeaks, nil, nil)
		local moreLeaksThanDamage = damageMessage()
		moreLeaksThanDamage.leakCount = 26
		expectMessageFailure(assertions, moreLeaksThanDamage, "INVALID_TOTAL", "payload.leakCount")
		local impossibleHealthDelta = damageMessage()
		impossibleHealthDelta.appliedDamage = 26
		expectMessageFailure(assertions, impossibleHealthDelta, "INVALID_TOTAL", "payload.appliedDamage")
		local excessiveDamage = damageMessage()
		excessiveDamage.snapshot.currentHealth = 0
		excessiveDamage.snapshot.status = "Defeated"
		excessiveDamage.snapshot.lowHealth = true
		excessiveDamage.appliedDamage = 101
		expectMessageFailure(assertions, excessiveDamage, "INVALID_TOTAL", "payload.appliedDamage")
		local falseCrossing = damageMessage()
		falseCrossing.lowHealthCrossed = true
		expectMessageFailure(assertions, falseCrossing, "INVALID_REFERENCE", "payload.lowHealthCrossed")
		local faultDamage = damageMessage()
		faultDamage.snapshot.status = "Faulted"
		expectMessageFailure(assertions, faultDamage, "INVALID_REFERENCE", "payload.snapshot.status")

		for _, malformed in
			{
				{ kind = "Damage", snapshot = validSnapshot(), appliedDamage = 1, leakCount = 1 },
				{
					kind = "Damage",
					snapshot = validSnapshot(),
					appliedDamage = 1,
					leakCount = 1,
					lowHealthCrossed = false,
					extra = true,
				},
				{ kind = "Defeat", snapshot = validSnapshot() },
				setmetatable(damageMessage(), {}),
			}
		do
			expectMessageFailure(assertions, malformed, nil, nil)
		end
	end),

	TestHarness.case("keeps hostile payload values out of fixed validation diagnostics", function(assertions)
		local privateSentinel = "PRIVATE_BASE_PROTOCOL_SENTINEL_99b3"
		local hostile = validSnapshot()
		hostile[privateSentinel] = privateSentinel
		local issue = expectSnapshotFailure(assertions, hostile, "UNKNOWN_FIELD", "payload")
		assertions.isNil(string.find(issue.code, privateSentinel, 1, true))
		assertions.isNil(string.find(issue.path, privateSentinel, 1, true))
		assertions.isNil(string.find(issue.message, privateSentinel, 1, true))

		local invocationCount = 0
		local hostileKey = setmetatable({}, {
			__tostring = function()
				invocationCount += 1
				return privateSentinel
			end,
		})
		local hostileKeySnapshot = validSnapshot()
		hostileKeySnapshot[hostileKey] = privateSentinel
		expectSnapshotFailure(assertions, hostileKeySnapshot, "INVALID_TABLE", "payload")
		assertions.equal(invocationCount, 0)
	end),
})
