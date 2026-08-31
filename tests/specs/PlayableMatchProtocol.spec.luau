--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local Protocol = require(game:GetService("ReplicatedStorage").Shared.match.PlayableMatchProtocol)

local function towerOption(towerId: string, name: string, cost: number)
	return {
		towerId = towerId,
		displayName = name,
		placementCost = cost,
		description = `Place {name} to defend the lane.`,
	}
end

local function validSnapshot()
	return {
		matchId = "match:playable-protocol",
		revision = 7,
		state = "Playing",
		result = "None",
		mapId = "map:phase07-graybox",
		mapDisplayName = "Backyard Graybox",
		difficultyId = "difficulty:local",
		difficultyDisplayName = "Local",
		serverTime = 110,
		waveNumber = 2,
		totalWaves = 5,
		wavePhase = "Resolving",
		nextWaveServerTime = 0,
		baseHealth = 27,
		maximumBaseHealth = 30,
		enemiesAlive = 1,
		battleCash = 245,
		participants = { readyCount = 1, participantCount = 1 },
		towerOptions = {
			towerOption("tower:dart-ant", "Dart Ant", 120),
			towerOption("tower:rapid-ant", "Rapid Ant", 165),
			towerOption("tower:guard-ant", "Guard Ant", 225),
		},
		towers = {
			{
				runtimeTowerId = 1,
				revision = 1,
				towerId = "tower:dart-ant",
				displayName = "Dart Ant",
				ownerUserId = 42,
				level = 2,
				targetMode = "First",
				position = Vector3.new(4, 1, 7),
				rotationDegrees = 90,
				totalInvestment = 230,
				cooldownEndsServerTime = 110.4,
				damage = 22,
				cooldownSeconds = 0.7,
				rangeStuds = 27,
				upgradeCost = 190,
				sellValue = 161,
			},
		},
		enemies = {
			{
				runtimeEnemyId = 3,
				enemyId = "enemy:worker-ant",
				displayName = "Worker Ant",
				currentHealth = 21,
				maximumHealth = 45,
				position = Vector3.new(-8, 2, 3),
				pathProgress = 18,
			},
		},
		stats = {
			durationSeconds = 10,
			wavesCompleted = 1,
			damageDealt = 24,
			battleCashEarned = 76,
			battleCashSpent = 230,
			placements = 1,
			upgrades = 1,
			sells = 0,
			baseHealthRemaining = 27,
		},
	}
end

return TestHarness.suite("playable match wire protocol", {
	TestHarness.case("exports the fixed authority-safe endpoint family", function(assertions)
		assertions.equal(Protocol.ENDPOINTS.GET_SNAPSHOT, "GetPlayableMatchSnapshot")
		assertions.equal(Protocol.ENDPOINTS.SUBMIT_READY, "SubmitPlayableReady")
		assertions.equal(Protocol.ENDPOINTS.SUBMIT_PLACEMENT, "SubmitPlayablePlacement")
		assertions.equal(Protocol.ENDPOINTS.SUBMIT_UPGRADE, "SubmitTowerUpgrade")
		assertions.equal(Protocol.ENDPOINTS.SUBMIT_SELL, "SubmitTowerSell")
		assertions.equal(Protocol.ENDPOINTS.SUBMIT_TARGET_MODE, "SubmitTowerTargetMode")
		assertions.equal(Protocol.ENDPOINTS.SUBMIT_REPLAY, "SubmitPlayableReplay")
		assertions.equal(Protocol.ENDPOINTS.REPLICATION, "PlayableMatchReplication")
		assertions.equal(Protocol.ENDPOINTS.ATTACK_EVENT, "CombatAttackEvent")
		assertions.isTrue(table.isfrozen(Protocol.ENDPOINTS))
	end),
	TestHarness.case("validates and detaches one owner-private playable snapshot", function(assertions)
		local raw = validSnapshot()
		local result = Protocol.validateSnapshot(raw)
		assertions.isTrue(result.ok)
		if not result.ok then
			return
		end
		assertions.isTrue(table.isfrozen(result.value))
		assertions.isTrue(table.isfrozen(result.value.towers))
		assertions.isTrue(table.isfrozen(result.value.enemies))
		assertions.notEqual(result.value, raw)
		assertions.notEqual(result.value.towers[1], raw.towers[1])
		raw.battleCash = 9_999
		raw.towers[1].level = 9
		assertions.equal(result.value.battleCash, 245)
		assertions.equal(result.value.towers[1].level, 2)
	end),
	TestHarness.case("rejects inconsistent health counts and result state", function(assertions)
		local health = validSnapshot()
		health.baseHealth = 31
		assertions.isFalse(Protocol.validateSnapshot(health).ok)

		local count = validSnapshot()
		count.enemiesAlive = 0
		assertions.isFalse(Protocol.validateSnapshot(count).ok)

		local resultState = validSnapshot()
		resultState.state = "Results"
		resultState.wavePhase = "Results"
		assertions.isFalse(Protocol.validateSnapshot(resultState).ok)

		local healthyResult = validSnapshot()
		healthyResult.state = "Results"
		healthyResult.result = "Victory"
		healthyResult.wavePhase = "Results"
		assertions.isTrue(Protocol.validateSnapshot(healthyResult).ok)
	end),
	TestHarness.case("bounds arrays and requires exactly three tower options", function(assertions)
		local full = validSnapshot()
		local towerTemplate = full.towers[1]
		local enemyTemplate = full.enemies[1]
		table.clear(full.towers)
		table.clear(full.enemies)
		for runtimeTowerId = 1, Protocol.MAX_ACTIVE_TOWERS do
			local tower = table.clone(towerTemplate)
			tower.runtimeTowerId = runtimeTowerId
			table.insert(full.towers, tower)
		end
		for runtimeEnemyId = 1, Protocol.MAX_ACTIVE_ENEMIES do
			local enemy = table.clone(enemyTemplate)
			enemy.runtimeEnemyId = runtimeEnemyId
			table.insert(full.enemies, enemy)
		end
		full.enemiesAlive = #full.enemies
		assertions.isTrue(Protocol.validateSnapshot(full).ok)

		local tooFew = validSnapshot()
		table.remove(tooFew.towerOptions)
		assertions.isFalse(Protocol.SnapshotSchema:validate(tooFew).ok)

		local tooManyEnemies = validSnapshot()
		local entry = tooManyEnemies.enemies[1]
		for _ = 2, Protocol.MAX_ACTIVE_ENEMIES + 1 do
			table.insert(tooManyEnemies.enemies, entry)
		end
		assertions.isFalse(Protocol.SnapshotSchema:validate(tooManyEnemies).ok)
	end),
	TestHarness.case("accepts only intent fields and rejects client combat authority", function(assertions)
		local placement = {
			matchId = "match:playable-protocol",
			towerId = "tower:dart-ant",
			position = Vector3.new(1, 2, 3),
			rotationDegrees = 90,
		}
		assertions.isTrue(Protocol.PlacementPayloadSchema:validate(placement).ok)
		placement.damage = 999
		assertions.isFalse(Protocol.PlacementPayloadSchema:validate(placement).ok)

		assertions.isTrue(Protocol.TargetModePayloadSchema:validate({
			matchId = "match:playable-protocol",
			runtimeTowerId = 1,
			towerRevision = 1,
			targetMode = "Weakest",
		}).ok)
		assertions.isFalse(Protocol.TargetModePayloadSchema:validate({
			matchId = "match:playable-protocol",
			runtimeTowerId = 1,
			towerRevision = 1,
			targetMode = "First",
			targetRuntimeEnemyId = 3,
		}).ok)
	end),
	TestHarness.case("ties receipt acceptance to its public reason", function(assertions)
		local accepted = Protocol.validateActionReceipt({
			accepted = true,
			reason = "Accepted",
			matchId = "match:playable-protocol",
			revision = 8,
			battleCash = 125,
		})
		assertions.isTrue(accepted.ok)
		assertions.isFalse(Protocol.validateActionReceipt({
			accepted = false,
			reason = "Accepted",
			matchId = "match:playable-protocol",
			revision = 8,
			battleCash = 125,
		}).ok)
	end),
	TestHarness.case("validates compact server-authored attacks without hit inputs", function(assertions)
		local event = {
			matchId = "match:playable-protocol",
			sequence = 4,
			runtimeTowerId = 2,
			runtimeEnemyId = 7,
			sourcePosition = Vector3.new(1, 2, 3),
			targetPosition = Vector3.new(8, 2, 3),
			actualDamage = 12,
			killed = false,
			serverTime = 110,
		}
		assertions.isTrue(Protocol.validateAttackEvent(event).ok)
		event.actualDamage = 0
		assertions.isFalse(Protocol.validateAttackEvent(event).ok)
	end),
})
