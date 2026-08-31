--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local PlayableMatchProtocol = require(ReplicatedStorage.Shared.match.PlayableMatchProtocol)

local PlayableMatchRuntime = require(script.Parent.Parent.ProductionServerPlayable.PlayableMatchRuntime)

type Assertions = TestHarness.Assertions
type Runtime = PlayableMatchRuntime.Runtime
type Snapshot = PlayableMatchProtocol.Snapshot

local MATCH_ID = "match:playable-runtime"
local USER_ONE = 101
local USER_TWO = 202
local USER_THREE = 303
local USER_FOUR = 404
local EPSILON = 1e-7

local loadedConfiguration = ConfigurationValidator.validateLoaded()
if not loadedConfiguration.ok then
	error("expected the loaded production configuration to validate", 0)
end
local CONFIGURATION = loadedConfiguration.value

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		error("expected PlayableMatchRuntime operation to succeed", 0)
	end
	return result.value
end

local function expectError(assertions: Assertions, result: any, code: string, operation: string)
	assertions.isFalse(result.ok)
	assertions.isTrue(table.isfrozen(result))
	if not result.ok then
		assertions.isTrue(table.isfrozen(result.error))
		assertions.equal(result.error.code, code)
		assertions.equal(result.error.operation, operation)
	end
end

local function expectAccepted(assertions: Assertions, outcome: PlayableMatchRuntime.ActionOutcome)
	assertions.isTrue(outcome.accepted)
	assertions.equal(outcome.reason, "Accepted")
	assertions.isTrue(table.isfrozen(outcome))
end

local function expectRejected(
	assertions: Assertions,
	outcome: PlayableMatchRuntime.ActionOutcome,
	reason: PlayableMatchProtocol.ActionReason
)
	assertions.isFalse(outcome.accepted)
	assertions.equal(outcome.reason, reason)
	assertions.isTrue(table.isfrozen(outcome))
end

local function makeRuntimeMap(shortPath: boolean?): any
	local positions: { Vector3 } = {}
	if shortPath then
		positions = { Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0) }
	else
		local pointCount = 65
		for index = 0, pointCount - 1 do
			local angle = index * math.pi * 2 / 16
			table.insert(positions, Vector3.new(math.cos(angle) * 8, 0, math.sin(angle) * 8))
		end
	end

	local points = {}
	local totalDistance = 0
	local previous: Vector3? = nil
	for index, position in positions do
		if previous ~= nil then
			totalDistance += (position - previous).Magnitude
		end
		table.insert(points, {
			kind = "Path",
			nodeOrder = index,
			cframe = CFrame.new(position),
			position = position,
			distance = totalDistance,
		})
		previous = position
	end

	local endpoint = positions[#positions]
	return {
		mapId = "map:phase07-graybox",
		base = { cframe = CFrame.new(endpoint), position = endpoint },
		bounds = { cframe = CFrame.new(0, 0, 0), size = Vector3.new(100, 20, 100) },
		lanes = {
			{
				id = "main",
				totalDistance = totalDistance,
				points = points,
			},
		},
		placementZones = {
			{ id = "land", cframe = CFrame.new(0, -1, 0), size = Vector3.new(80, 2, 80) },
		},
		noPlacementZones = {},
		cameraAnchors = {
			{ id = "camera", cframe = CFrame.new(0, 30, 30), position = Vector3.new(0, 30, 30) },
		},
		playerSpawns = {
			{ id = "spawn", cframe = CFrame.new(0, 0, 20), position = Vector3.new(0, 0, 20) },
		},
	}
end

local function newRuntime(
	assertions: Assertions,
	participants: { number }?,
	matchId: string?,
	shortPath: boolean?
): Runtime
	return success(
		assertions,
		PlayableMatchRuntime.new({
			matchId = matchId or MATCH_ID,
			configuration = CONFIGURATION,
			runtimeMap = makeRuntimeMap(shortPath),
			participantUserIds = participants or { USER_ONE },
		})
	)
end

local function snapshot(assertions: Assertions, runtime: Runtime, userId: number, serverTime: number): Snapshot
	return success(assertions, runtime:getSnapshot(userId, serverTime))
end

local function readyAll(assertions: Assertions, runtime: Runtime, participants: { number }, serverTime: number)
	for _, userId in participants do
		expectAccepted(assertions, runtime:submitReady(userId, MATCH_ID, serverTime))
	end
	assertions.equal(runtime:getMetrics().state, "Playing")
end

local function advanceFrom(
	assertions: Assertions,
	runtime: Runtime,
	startingServerTime: number,
	targetServerTime: number,
	requestIncrement: number
): { PlayableMatchRuntime.AttackEvent }
	local attacks: { PlayableMatchRuntime.AttackEvent } = {}
	local currentServerTime = startingServerTime
	for _ = 1, 20_000 do
		if currentServerTime >= targetServerTime - EPSILON then
			return attacks
		end
		local requestedTime = math.min(targetServerTime, currentServerTime + requestIncrement)
		local outcome = success(assertions, runtime:step(requestedTime))
		for _, attack in outcome.attacks do
			table.insert(attacks, attack)
		end
		if outcome.serverTime <= currentServerTime + EPSILON and outcome.serverTime < targetServerTime - EPSILON then
			error("runtime made no fixed-step progress", 0)
		end
		currentServerTime = outcome.serverTime
	end
	error("runtime did not finish fixed-step advancement", 0)
end

local function runUntilResults(
	assertions: Assertions,
	runtime: Runtime,
	startingServerTime: number
): (number, { PlayableMatchRuntime.AttackEvent })
	local currentServerTime = startingServerTime
	local attacks: { PlayableMatchRuntime.AttackEvent } = {}
	for _ = 1, 5_000 do
		if runtime:getMetrics().state == "Results" then
			return currentServerTime, attacks
		end
		local outcome = success(assertions, runtime:step(currentServerTime + PlayableMatchRuntime.MAX_STEP_SECONDS))
		for _, attack in outcome.attacks do
			table.insert(attacks, attack)
		end
		assertions.isTrue(outcome.serverTime > currentServerTime)
		currentServerTime = outcome.serverTime
	end
	error("runtime did not reach Results within the bounded scenario", 0)
end

local function towerPositions(): { Vector3 }
	local positions: { Vector3 } = {}
	for row = 0, 2 do
		for column = 0, 3 do
			table.insert(positions, Vector3.new(-4.5 + column * 3, 0, -3 + row * 3))
		end
	end
	return positions
end

local function assertEquivalentSnapshot(assertions: Assertions, left: Snapshot, right: Snapshot)
	assertions.equal(left.state, right.state)
	assertions.equal(left.result, right.result)
	assertions.equal(left.revision, right.revision)
	assertions.equal(left.waveNumber, right.waveNumber)
	assertions.equal(left.wavePhase, right.wavePhase)
	assertions.equal(left.nextWaveServerTime, right.nextWaveServerTime)
	assertions.equal(left.baseHealth, right.baseHealth)
	assertions.equal(left.battleCash, right.battleCash)
	assertions.equal(left.stats.damageDealt, right.stats.damageDealt)
	assertions.equal(left.stats.battleCashEarned, right.stats.battleCashEarned)
	assertions.equal(#left.towers, #right.towers)
	assertions.equal(#left.enemies, #right.enemies)
	for index, leftTower in left.towers do
		local rightTower = right.towers[index]
		assertions.equal(leftTower.runtimeTowerId, rightTower.runtimeTowerId)
		assertions.equal(leftTower.revision, rightTower.revision)
		assertions.equal(leftTower.cooldownEndsServerTime, rightTower.cooldownEndsServerTime)
	end
	for index, leftEnemy in left.enemies do
		local rightEnemy = right.enemies[index]
		assertions.equal(leftEnemy.runtimeEnemyId, rightEnemy.runtimeEnemyId)
		assertions.equal(leftEnemy.currentHealth, rightEnemy.currentHealth)
		assertions.equal(leftEnemy.pathProgress, rightEnemy.pathProgress)
		assertions.equal(leftEnemy.position, rightEnemy.position)
	end
end

return TestHarness.suite("authoritative playable match runtime", {
	TestHarness.case(
		"requires authenticated production content and constructs a frozen ready match",
		function(assertions)
			expectError(assertions, PlayableMatchRuntime.new(nil), "INVALID_DEPENDENCIES", "new")
			expectError(
				assertions,
				PlayableMatchRuntime.new({
					matchId = MATCH_ID,
					configuration = table.clone(CONFIGURATION),
					runtimeMap = makeRuntimeMap(),
					participantUserIds = { USER_ONE },
				}),
				"UNAUTHENTICATED_CONFIGURATION",
				"new"
			)
			local wrongMap = makeRuntimeMap()
			wrongMap.mapId = "map:wrong"
			expectError(
				assertions,
				PlayableMatchRuntime.new({
					matchId = MATCH_ID,
					configuration = CONFIGURATION,
					runtimeMap = wrongMap,
					participantUserIds = { USER_ONE },
				}),
				"INVALID_RUNTIME_MAP",
				"new"
			)
			expectError(
				assertions,
				PlayableMatchRuntime.new({
					matchId = MATCH_ID,
					configuration = CONFIGURATION,
					runtimeMap = makeRuntimeMap(),
					participantUserIds = { USER_ONE, USER_ONE },
				}),
				"INVALID_PARTICIPANTS",
				"new"
			)

			local runtime = newRuntime(assertions)
			assertions.isTrue(table.isfrozen(runtime))
			local initial = snapshot(assertions, runtime, USER_ONE, 10)
			assertions.isTrue(table.isfrozen(initial))
			assertions.isTrue(table.isfrozen(initial.towerOptions))
			assertions.equal(initial.matchId, MATCH_ID)
			assertions.equal(initial.state, "Ready")
			assertions.equal(initial.battleCash, 500)
			assertions.equal(#initial.towerOptions, 3)
			assertions.equal(initial.towerOptions[1].towerId, "tower:dart-ant")
			assertions.equal(initial.totalWaves, 5)
			assertions.equal(initial.maximumBaseHealth, 30)
			assertions.isTrue(success(assertions, runtime:cleanup()))
		end
	),

	TestHarness.case("starts exactly when every active participant is ready", function(assertions)
		local runtime = newRuntime(assertions, { USER_TWO, USER_ONE })
		expectRejected(assertions, runtime:submitReady(USER_ONE, "match:stale", 100), "StaleMatch")
		expectAccepted(assertions, runtime:submitReady(USER_ONE, MATCH_ID, 100))
		expectAccepted(assertions, runtime:submitReady(USER_ONE, MATCH_ID, 100))
		local waiting = snapshot(assertions, runtime, USER_ONE, 100)
		assertions.equal(waiting.state, "Ready")
		assertions.equal(waiting.participants.readyCount, 1)
		assertions.equal(waiting.participants.participantCount, 2)

		expectAccepted(assertions, runtime:submitReady(USER_TWO, MATCH_ID, 100))
		local playing = snapshot(assertions, runtime, USER_TWO, 100)
		assertions.equal(playing.state, "Playing")
		assertions.equal(playing.wavePhase, "Intermission")
		assertions.equal(playing.nextWaveServerTime, 100 + PlayableMatchRuntime.PREPARE_SECONDS)
		assertions.equal(playing.participants.readyCount, 2)
		expectRejected(assertions, runtime:submitReady(USER_TWO, MATCH_ID, 100), "WrongState")
		assertions.isTrue(success(assertions, runtime:cleanup()))
	end),

	TestHarness.case(
		"freezes a variable equipped loadout and rejects stale or unequipped placement refs",
		function(assertions)
			local runtime = success(
				assertions,
				PlayableMatchRuntime.new({
					matchId = MATCH_ID,
					configuration = CONFIGURATION,
					runtimeMap = makeRuntimeMap(),
					participantLoadouts = {
						{
							userId = USER_ONE,
							revision = 9,
							settings = CONFIGURATION.defaultSettings,
							slots = {
								{ slot = 1, unitId = "unit:runtime-dart", towerId = "tower:dart-ant" },
							},
						},
					},
				})
			)
			local initial = snapshot(assertions, runtime, USER_ONE, 10)
			assertions.equal(initial.loadoutRevision, 9)
			assertions.equal(#initial.towerOptions, 1)
			assertions.equal(initial.towerOptions[1].slot, 1)
			assertions.equal(initial.towerOptions[1].unitId, "unit:runtime-dart")
			readyAll(assertions, runtime, { USER_ONE }, 100)
			expectRejected(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:dart-ant", 1, 8, Vector3.new(0, 0, 0), 0, 100),
				"StaleLoadout"
			)
			expectRejected(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:rapid-ant", 1, 9, Vector3.new(0, 0, 0), 0, 100),
				"UnequippedTower"
			)
			expectAccepted(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:dart-ant", 1, 9, Vector3.new(0, 0, 0), 0, 100)
			)
			assertions.isTrue(success(assertions, runtime:cleanup()))
		end
	),

	TestHarness.case(
		"spends for valid geometry and enforces occupancy affordability and the global cap",
		function(assertions)
			local runtime = newRuntime(assertions)
			readyAll(assertions, runtime, { USER_ONE }, 100)
			expectAccepted(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:dart-ant", Vector3.new(0, 999, 0), 0, 100)
			)
			local afterDart = snapshot(assertions, runtime, USER_ONE, 100)
			assertions.equal(afterDart.battleCash, 380)
			assertions.equal(#afterDart.towers, 1)
			assertions.equal(afterDart.towers[1].position, Vector3.new(0, 0, 0))
			expectRejected(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:dart-ant", Vector3.new(0, 0, 0), 0, 100),
				"InvalidPlacement"
			)
			expectRejected(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:dart-ant", Vector3.new(100, 0, 100), 0, 100),
				"InvalidPlacement"
			)
			expectAccepted(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:guard-ant", Vector3.new(4, 0, 0), 0, 100)
			)
			expectRejected(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:rapid-ant", Vector3.new(8, 0, 0), 0, 100),
				"InsufficientCash"
			)
			assertions.equal(snapshot(assertions, runtime, USER_ONE, 100).battleCash, 155)
			assertions.isTrue(success(assertions, runtime:cleanup()))

			local participants = { USER_ONE, USER_TWO, USER_THREE, USER_FOUR }
			local capped = newRuntime(assertions, participants)
			readyAll(assertions, capped, participants, 200)
			local positions = towerPositions()
			for index = 1, PlayableMatchRuntime.MAX_TOWERS do
				local owner = participants[((index - 1) % #participants) + 1]
				expectAccepted(
					assertions,
					capped:placeTower(owner, MATCH_ID, "tower:dart-ant", positions[index], 0, 200)
				)
			end
			assertions.equal(capped:getMetrics().activeTowerCount, PlayableMatchRuntime.MAX_TOWERS)
			expectRejected(
				assertions,
				capped:placeTower(USER_ONE, MATCH_ID, "tower:dart-ant", Vector3.new(9, 0, 0), 0, 200),
				"TowerCap"
			)
			assertions.isTrue(success(assertions, capped:cleanup()))
		end
	),

	TestHarness.case(
		"uses per-tower revision CAS and preserves an outstanding cooldown through control changes",
		function(assertions)
			local runtime = newRuntime(assertions)
			readyAll(assertions, runtime, { USER_ONE }, 100)
			expectAccepted(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:dart-ant", Vector3.new(0, 0, 0), 0, 100)
			)
			local attacks = advanceFrom(assertions, runtime, 100, 106.5, PlayableMatchRuntime.MAX_STEP_SECONDS)
			assertions.isTrue(#attacks >= 1)
			local before = snapshot(assertions, runtime, USER_ONE, 106.5)
			local tower = before.towers[1]
			assertions.isTrue(tower.cooldownEndsServerTime > attacks[1].serverTime)

			expectAccepted(assertions, runtime:upgradeTower(USER_ONE, MATCH_ID, tower.runtimeTowerId, tower.revision))
			local upgraded = snapshot(assertions, runtime, USER_ONE, 106.5).towers[1]
			assertions.equal(upgraded.level, 2)
			assertions.equal(upgraded.revision, tower.revision + 1)
			assertions.equal(upgraded.cooldownEndsServerTime, tower.cooldownEndsServerTime)
			expectRejected(
				assertions,
				runtime:upgradeTower(USER_ONE, MATCH_ID, tower.runtimeTowerId, tower.revision),
				"StaleTower"
			)

			expectAccepted(
				assertions,
				runtime:setTargetMode(USER_ONE, MATCH_ID, tower.runtimeTowerId, upgraded.revision, "Last")
			)
			local retargeted = snapshot(assertions, runtime, USER_ONE, 106.5).towers[1]
			assertions.equal(retargeted.targetMode, "Last")
			assertions.equal(retargeted.revision, upgraded.revision + 1)
			assertions.equal(retargeted.cooldownEndsServerTime, tower.cooldownEndsServerTime)
			expectRejected(
				assertions,
				runtime:setTargetMode(USER_ONE, MATCH_ID, tower.runtimeTowerId, upgraded.revision, "First"),
				"StaleTower"
			)
			expectRejected(
				assertions,
				runtime:sellTower(USER_ONE, "match:stale", tower.runtimeTowerId, retargeted.revision),
				"StaleMatch"
			)
			expectRejected(
				assertions,
				runtime:sellTower(USER_ONE, MATCH_ID, tower.runtimeTowerId, upgraded.revision),
				"StaleTower"
			)
			expectAccepted(assertions, runtime:sellTower(USER_ONE, MATCH_ID, tower.runtimeTowerId, retargeted.revision))
			expectRejected(
				assertions,
				runtime:sellTower(USER_ONE, MATCH_ID, tower.runtimeTowerId, retargeted.revision),
				"NotFound"
			)
			local sold = snapshot(assertions, runtime, USER_ONE, 106.5)
			assertions.equal(#sold.towers, 0)
			assertions.equal(sold.battleCash, 434)
			assertions.equal(sold.stats.placements, 1)
			assertions.equal(sold.stats.upgrades, 1)
			assertions.equal(sold.stats.sells, 1)
			assertions.isTrue(success(assertions, runtime:cleanup()))
		end
	),

	TestHarness.case(
		"applies direct damage and rational income with compact events and no idle burst",
		function(assertions)
			local runtime = newRuntime(assertions)
			readyAll(assertions, runtime, { USER_ONE }, 100)
			expectAccepted(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:dart-ant", Vector3.new(0, 0, 0), 0, 100)
			)
			local idleAttacks = advanceFrom(assertions, runtime, 100, 105.5, PlayableMatchRuntime.MAX_STEP_SECONDS)
			assertions.equal(#idleAttacks, 0)
			local firstAttacks = advanceFrom(assertions, runtime, 105.5, 106.5, PlayableMatchRuntime.MAX_STEP_SECONDS)
			assertions.equal(#firstAttacks, 1)
			local attack = firstAttacks[1]
			assertions.isTrue(table.isfrozen(attack))
			assertions.equal(attack.matchId, MATCH_ID)
			assertions.equal(attack.sequence, 1)
			assertions.equal(attack.runtimeTowerId, 1)
			assertions.equal(attack.runtimeEnemyId, 1)
			assertions.equal(attack.actualDamage, 12)
			assertions.isFalse(attack.killed)
			assertions.isTrue(PlayableMatchProtocol.validateAttackEvent(attack).ok)

			local after = snapshot(assertions, runtime, USER_ONE, 106.5)
			assertions.equal(after.battleCash, 383)
			assertions.equal(after.stats.damageDealt, 12)
			assertions.equal(after.enemies[1].currentHealth, 33)
			assertions.equal(runtime:getMetrics().attackCount, 1)
			local beforeCooldown = advanceFrom(assertions, runtime, 106.5, 106.75, 0.05)
			assertions.equal(#beforeCooldown, 0)
			assertions.isTrue(success(assertions, runtime:cleanup()))
		end
	),

	TestHarness.case("produces identical combat for coarse and fine fixed-step partitions", function(assertions)
		local coarse = newRuntime(assertions)
		local fine = newRuntime(assertions)
		for _, runtime in { coarse, fine } do
			readyAll(assertions, runtime, { USER_ONE }, 100)
			expectAccepted(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:rapid-ant", Vector3.new(0, 0, 0), 0, 100)
			)
		end
		local coarseAttacks = advanceFrom(assertions, coarse, 100, 109, PlayableMatchRuntime.MAX_STEP_SECONDS)
		local fineAttacks = advanceFrom(assertions, fine, 100, 109, PlayableMatchRuntime.FIXED_STEP_SECONDS)
		assertions.equal(#coarseAttacks, #fineAttacks)
		for index, coarseAttack in coarseAttacks do
			local fineAttack = fineAttacks[index]
			assertions.equal(coarseAttack.sequence, fineAttack.sequence)
			assertions.equal(coarseAttack.runtimeEnemyId, fineAttack.runtimeEnemyId)
			assertions.equal(coarseAttack.actualDamage, fineAttack.actualDamage)
			assertions.equal(coarseAttack.killed, fineAttack.killed)
			assertions.equal(coarseAttack.serverTime, fineAttack.serverTime)
		end
		assertEquivalentSnapshot(
			assertions,
			snapshot(assertions, coarse, USER_ONE, 109),
			snapshot(assertions, fine, USER_ONE, 109)
		)
		assertions.isTrue(success(assertions, coarse:cleanup()))
		assertions.isTrue(success(assertions, fine:cleanup()))
	end),

	TestHarness.case(
		"resolves every finite wave once grants stipends and freezes victorious Results",
		function(assertions)
			local participants = { USER_ONE, USER_TWO, USER_THREE, USER_FOUR }
			local runtime = newRuntime(assertions, participants)
			readyAll(assertions, runtime, participants, 100)
			local positions = towerPositions()
			for index = 1, PlayableMatchRuntime.MAX_TOWERS do
				local owner = participants[((index - 1) % #participants) + 1]
				expectAccepted(
					assertions,
					runtime:placeTower(owner, MATCH_ID, "tower:dart-ant", positions[index], 0, 100)
				)
			end

			local finishedServerTime, attacks = runUntilResults(assertions, runtime, 100)
			local metrics = runtime:getMetrics()
			assertions.equal(metrics.state, "Results")
			assertions.equal(metrics.result, "Victory")
			assertions.equal(metrics.waveNumber, 5)
			assertions.equal(metrics.wavesCompleted, 5)
			assertions.equal(metrics.activeEnemyCount, 0)
			assertions.equal(metrics.attackCount, #attacks)
			assertions.isTrue(#attacks > 0)
			for index, attack in attacks do
				assertions.equal(attack.sequence, index)
			end

			local completed = snapshot(assertions, runtime, USER_ONE, finishedServerTime)
			assertions.equal(completed.state, "Results")
			assertions.equal(completed.result, "Victory")
			assertions.equal(completed.wavePhase, "Results")
			assertions.equal(completed.baseHealth, 30)
			assertions.equal(completed.stats.wavesCompleted, 5)
			assertions.isTrue(completed.battleCash >= 570)
			assertions.isTrue(completed.stats.battleCashEarned >= 430)
			expectAccepted(assertions, runtime:canReplay(USER_ONE, MATCH_ID))
			expectRejected(assertions, runtime:canReplay(USER_ONE, "match:stale"), "StaleMatch")

			local duration = completed.stats.durationSeconds
			local afterResults = success(assertions, runtime:step(finishedServerTime + 100))
			assertions.equal(afterResults.serverTime, finishedServerTime)
			assertions.equal(#afterResults.attacks, 0)
			assertions.equal(
				snapshot(assertions, runtime, USER_ONE, finishedServerTime + 100).stats.durationSeconds,
				duration
			)
			assertions.isTrue(success(assertions, runtime:cleanup()))
		end
	),

	TestHarness.case(
		"reaches authoritative defeat without towers and holds terminal duration stable",
		function(assertions)
			local runtime = newRuntime(assertions, { USER_ONE }, nil, true)
			readyAll(assertions, runtime, { USER_ONE }, 100)
			local finishedServerTime, attacks = runUntilResults(assertions, runtime, 100)
			assertions.equal(#attacks, 0)
			local defeated = snapshot(assertions, runtime, USER_ONE, finishedServerTime)
			assertions.equal(defeated.state, "Results")
			assertions.equal(defeated.result, "Defeat")
			assertions.equal(defeated.baseHealth, 0)
			assertions.isTrue(defeated.stats.wavesCompleted < defeated.totalWaves)
			local duration = defeated.stats.durationSeconds
			local afterResults = success(assertions, runtime:step(finishedServerTime + 1_000))
			assertions.equal(afterResults.serverTime, finishedServerTime)
			assertions.equal(
				snapshot(assertions, runtime, USER_ONE, finishedServerTime + 1_000).stats.durationSeconds,
				duration
			)
			expectAccepted(assertions, runtime:canReplay(USER_ONE, MATCH_ID))
			assertions.isTrue(success(assertions, runtime:cleanup()))
		end
	),

	TestHarness.case(
		"preserves ready reconnect cash removes disconnected ownership and cleans all match state",
		function(assertions)
			local runtime = newRuntime(assertions, { USER_ONE, USER_TWO })
			expectAccepted(assertions, runtime:removeParticipant(USER_ONE, 50))
			assertions.equal(runtime:getMetrics().participantCount, 1)
			expectAccepted(assertions, runtime:addParticipant(USER_ONE))
			assertions.equal(snapshot(assertions, runtime, USER_ONE, 50).battleCash, 500)
			readyAll(assertions, runtime, { USER_ONE, USER_TWO }, 100)
			expectAccepted(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:dart-ant", Vector3.new(0, 0, 0), 0, 100)
			)
			assertions.equal(runtime:getMetrics().activeTowerCount, 1)
			expectAccepted(assertions, runtime:removeParticipant(USER_ONE, 100.1))
			assertions.equal(runtime:getMetrics().participantCount, 1)
			assertions.equal(runtime:getMetrics().activeTowerCount, 0)
			expectRejected(
				assertions,
				runtime:placeTower(USER_ONE, MATCH_ID, "tower:dart-ant", Vector3.new(0, 0, 0), 0, 100.1),
				"NotParticipant"
			)
			expectRejected(assertions, runtime:addParticipant(USER_ONE), "WrongState")

			assertions.isTrue(success(assertions, runtime:cleanup()))
			assertions.isFalse(success(assertions, runtime:cleanup()))
			local metrics = runtime:getMetrics()
			assertions.isTrue(metrics.cleaned)
			assertions.equal(metrics.participantCount, 0)
			assertions.equal(metrics.activeTowerCount, 0)
			assertions.equal(metrics.activeEnemyCount, 0)
			expectError(assertions, runtime:step(101), "CLEANED", "step")
			expectError(assertions, runtime:getSnapshot(USER_TWO, 101), "CLEANED", "snapshot")
		end
	),
})
