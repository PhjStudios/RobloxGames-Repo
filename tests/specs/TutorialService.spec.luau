--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

local IsolatedProfileStore = require(script.Parent.Parent.Fixtures.IsolatedProfileStore)
local TowerFixtures = require(script.Parent.Parent.Fixtures.TowerFixtures)
local ProfileSchema = require(script.Parent.Parent.ProductionServerProfile.ProfileSchema)
local ProfileService = require(script.Parent.Parent.ProductionServerProfile.ProfileService)
local TutorialService = require(script.Parent.Parent.ProductionServerProfile.TutorialService)

type Assertions = TestHarness.Assertions

local USER_ID = 101
local NOW = 1_700_100_000

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected tutorial operation to succeed", 0)
	end
	return result.value
end

local function configuration(assertions: Assertions): any
	local sources = TowerFixtures.rawSources()
	sources.towers[1].id = ProfileSchema.DART_STARTER_TOWER_ID
	sources.towers[2].id = ProfileSchema.BOMBARDIER_STARTER_TOWER_ID
	return success(assertions, ConfigurationValidator.validate(sources))
end

local function rig(assertions: Assertions): (any, any)
	local config = configuration(assertions)
	local profile = success(
		assertions,
		ProfileService.new(config.towers, IsolatedProfileStore.new(), {
			sessionId = "session:tutorial",
			clock = function()
				return NOW
			end,
			wait = function(_seconds: number) end,
		})
	)
	success(assertions, profile:load(USER_ID))
	local tutorial = success(
		assertions,
		TutorialService.new(profile, config, {
			clock = function()
				return NOW
			end,
		})
	)
	return profile, tutorial
end

local function saturatedLegacyRig(assertions: Assertions): (any, any)
	local config = configuration(assertions)
	local starter = success(assertions, ProfileSchema.createStarter(config.towers, NOW))
	local saturated = ProfileSchema.clone(starter)
	saturated.units[ProfileSchema.BOMBARDIER_STARTER_UNIT_ID] = nil
	saturated.equippedUnitIds = { ProfileSchema.DART_STARTER_UNIT_ID }
	for sequence = 2, ProfileSchema.MAX_UNITS do
		local unitId = `unit:legacy-capacity-{sequence}`
		saturated.units[unitId] = {
			unitId = unitId,
			towerId = ProfileSchema.DART_STARTER_TOWER_ID,
			favorite = false,
			locked = false,
			acquiredAt = NOW,
			acquisitionSequence = sequence,
		}
	end
	saturated.stats.towersAcquired = ProfileSchema.MAX_UNITS
	local validated = success(assertions, ProfileSchema.validate(saturated, config.towers))
	local store = IsolatedProfileStore.new()
	store:seed("profile:101", validated)
	local profile = success(
		assertions,
		ProfileService.new(config.towers, store, {
			sessionId = "session:tutorial-saturated-legacy",
			clock = function()
				return NOW
			end,
			wait = function(_seconds: number) end,
		})
	)
	success(assertions, profile:load(USER_ID))
	local tutorial = success(
		assertions,
		TutorialService.new(profile, config, {
			clock = function()
				return NOW
			end,
		})
	)
	return profile, tutorial
end

local function migratedNoBombardierRig(assertions: Assertions): (any, any)
	local config = configuration(assertions)
	local legacy = ProfileSchema.clone(success(assertions, ProfileSchema.createStarter(config.towers, NOW)))
	legacy.schemaVersion = 5
	legacy.units[ProfileSchema.BOMBARDIER_STARTER_UNIT_ID] = nil
	legacy.equippedUnitIds = { ProfileSchema.DART_STARTER_UNIT_ID }
	legacy.stats.towersAcquired = 1
	legacy.stats.matchesPlayed = 1
	legacy.tutorial = {
		firstJoin = true,
		tutorialCompleted = false,
		tutorialStep = 0,
	}
	local store = IsolatedProfileStore.new()
	store:seed("profile:101", legacy)
	local profile = success(
		assertions,
		ProfileService.new(config.towers, store, {
			sessionId = "session:tutorial-migrated-replay",
			clock = function()
				return NOW
			end,
			wait = function(_seconds: number) end,
		})
	)
	success(assertions, profile:load(USER_ID))
	local tutorial = success(
		assertions,
		TutorialService.new(profile, config, {
			clock = function()
				return NOW
			end,
		})
	)
	return profile, tutorial
end

local function intent(index: number, revision: number): any
	return {
		transactionId = `transaction:tutorial-client-{index}`,
		expectedRevision = revision,
	}
end

local function queueSnapshot(privacy: string, memberIds: { number }?): any
	local ids = memberIds or { USER_ID }
	local members = table.create(#ids)
	for index, userId in ids do
		members[index] = {
			userId = userId,
			order = index,
			isCaptain = index == 1,
			readiness = "Ready",
		}
	end
	return {
		configuration = {
			mapId = TutorialService.RELEASE_MAP_ID,
			difficultyId = TutorialService.EASY_DIFFICULTY_ID,
			privacy = privacy,
			maxPlayers = 4,
		},
		members = members,
		enrollments = {
			{
				kind = "Solo",
				leaderUserId = USER_ID,
				userIds = ids,
			},
		},
	}
end

return TestHarness.suite("TutorialService", {
	TestHarness.case("grandfathers a capacity-saturated legacy inventory without deleting units", function(assertions)
		local profile, tutorial = saturatedLegacyRig(assertions)
		local initialized = success(assertions, tutorial:initialize(USER_ID))
		assertions.isTrue(initialized.advanced)
		assertions.equal(initialized.tutorial.tutorialStep, 9)
		assertions.isTrue(initialized.tutorial.tutorialCompleted)
		assertions.isFalse(initialized.tutorial.skipped)

		local preserved = success(assertions, profile:read(USER_ID))
		local count = 0
		for _ in preserved.units do
			count += 1
		end
		assertions.equal(count, ProfileSchema.MAX_UNITS)
		assertions.isNil(preserved.units[ProfileSchema.BOMBARDIER_STARTER_UNIT_ID])
		assertions.equal(#preserved.equippedUnitIds, 1)

		local replayed = success(assertions, tutorial:replay(USER_ID, intent(70, preserved.revision)))
		assertions.equal(replayed.tutorial.tutorialStep, 1)
		local learned = success(assertions, tutorial:advance(USER_ID, intent(71, replayed.revision)))
		local loadoutReady = success(assertions, tutorial:advance(USER_ID, intent(72, learned.revision)))
		assertions.equal(loadoutReady.tutorial.tutorialStep, 3)
		local afterReplay = success(assertions, profile:read(USER_ID))
		local afterCount = 0
		for _ in afterReplay.units do
			afterCount += 1
		end
		assertions.equal(afterCount, ProfileSchema.MAX_UNITS)
		assertions.isNil(afterReplay.units[ProfileSchema.BOMBARDIER_STARTER_UNIT_ID])
	end),

	TestHarness.case(
		"replay deterministically prepares missing starters for an experienced v5 profile",
		function(assertions)
			local profile, tutorial = migratedNoBombardierRig(assertions)
			local migrated = success(assertions, profile:read(USER_ID))
			assertions.equal(migrated.tutorial.tutorialStep, 9)
			assertions.isNil(migrated.units[ProfileSchema.BOMBARDIER_STARTER_UNIT_ID])

			local replayed = success(assertions, tutorial:replay(USER_ID, intent(80, migrated.revision)))
			assertions.equal(replayed.tutorial.tutorialStep, 1)
			local prepared = success(assertions, profile:read(USER_ID))
			assertions.equal(
				prepared.units[ProfileSchema.BOMBARDIER_STARTER_UNIT_ID].towerId,
				ProfileSchema.BOMBARDIER_STARTER_TOWER_ID
			)
			assertions.equal(#prepared.equippedUnitIds, 2)
			assertions.equal(prepared.stats.towersAcquired, 2)
			local learned = success(assertions, tutorial:advance(USER_ID, intent(81, replayed.revision)))
			local loadoutReady = success(assertions, tutorial:advance(USER_ID, intent(82, learned.revision)))
			assertions.equal(loadoutReady.tutorial.tutorialStep, 3)
		end
	),

	TestHarness.case(
		"initializes both stable starters once and advances only from validated Lobby actions",
		function(assertions)
			local profile, tutorial = rig(assertions)
			local initial = success(assertions, profile:read(USER_ID))
			assertions.equal(initial.tutorial.tutorialStep, 0)
			assertions.equal(
				initial.units[ProfileSchema.DART_STARTER_UNIT_ID].towerId,
				ProfileSchema.DART_STARTER_TOWER_ID
			)
			assertions.equal(
				initial.units[ProfileSchema.BOMBARDIER_STARTER_UNIT_ID].towerId,
				ProfileSchema.BOMBARDIER_STARTER_TOWER_ID
			)
			assertions.equal(#initial.equippedUnitIds, 2)

			local initialized = success(assertions, tutorial:initialize(USER_ID))
			assertions.isTrue(initialized.advanced)
			assertions.equal(initialized.tutorial.tutorialStep, 1)
			local replayedInitialization = success(assertions, tutorial:initialize(USER_ID))
			assertions.isFalse(replayedInitialization.advanced)
			assertions.equal(replayedInitialization.revision, initialized.revision)

			local learned = success(assertions, tutorial:advance(USER_ID, intent(1, initialized.revision)))
			assertions.equal(learned.tutorial.tutorialStep, 2)
			local confirmed = success(assertions, tutorial:advance(USER_ID, intent(2, learned.revision)))
			assertions.equal(confirmed.tutorial.tutorialStep, 3)

			local public =
				success(assertions, tutorial:observeSoloEasyQueue(USER_ID, queueSnapshot("Public"), "queue-public-1"))
			assertions.isFalse(public.advanced)
			local squad = success(
				assertions,
				tutorial:observeSoloEasyQueue(USER_ID, queueSnapshot("PartyOnly", { USER_ID, 202 }), "queue-squad-1")
			)
			assertions.isFalse(squad.advanced)
			local solo =
				success(assertions, tutorial:observeSoloEasyQueue(USER_ID, queueSnapshot("PartyOnly"), "queue-solo-1"))
			assertions.isTrue(solo.advanced)
			assertions.equal(solo.tutorial.tutorialStep, 4)
		end
	),

	TestHarness.case(
		"binds accepted Match actions and durable result to one authenticated solo Easy match",
		function(assertions)
			local _profile, tutorial = rig(assertions)
			local initialized = success(assertions, tutorial:initialize(USER_ID))
			local learned = success(assertions, tutorial:advance(USER_ID, intent(10, initialized.revision)))
			success(assertions, tutorial:advance(USER_ID, intent(11, learned.revision)))
			success(assertions, tutorial:observeSoloEasyQueue(USER_ID, queueSnapshot("PartyOnly"), "queue-solo-2"))

			local invalidArrival = success(
				assertions,
				tutorial:observeMatchArrival(USER_ID, {
					matchId = "match:tutorial-invalid",
					mapId = TutorialService.RELEASE_MAP_ID,
					difficultyId = TutorialService.EASY_DIFFICULTY_ID,
					privacy = "Public",
					expectedUserIds = { USER_ID },
					authenticatedParticipant = true,
					spectator = false,
				})
			)
			assertions.isFalse(invalidArrival.advanced)

			local matchId = "match:tutorial-one"
			local arrived = success(
				assertions,
				tutorial:observeMatchArrival(USER_ID, {
					matchId = matchId,
					mapId = TutorialService.RELEASE_MAP_ID,
					difficultyId = TutorialService.EASY_DIFFICULTY_ID,
					privacy = "PartyOnly",
					expectedUserIds = { USER_ID },
					authenticatedParticipant = true,
					spectator = false,
				})
			)
			assertions.equal(arrived.tutorial.tutorialStep, 5)
			assertions.equal(arrived.tutorial.trackedMatchId, matchId)

			assertions.isFalse(tutorial:observePlacement(USER_ID, "match:foreign").ok)
			assertions.equal(success(assertions, tutorial:observePlacement(USER_ID, matchId)).tutorial.tutorialStep, 6)
			assertions.equal(success(assertions, tutorial:observeUpgrade(USER_ID, matchId)).tutorial.tutorialStep, 7)

			local nonDurable = success(
				assertions,
				tutorial:observeResult(USER_ID, {
					matchId = matchId,
					mapId = TutorialService.RELEASE_MAP_ID,
					difficultyId = TutorialService.EASY_DIFFICULTY_ID,
					authenticatedParticipant = true,
					spectator = false,
					durable = false,
				})
			)
			assertions.isFalse(nonDurable.advanced)
			local finished = success(
				assertions,
				tutorial:observeResult(USER_ID, {
					matchId = matchId,
					mapId = TutorialService.RELEASE_MAP_ID,
					difficultyId = TutorialService.EASY_DIFFICULTY_ID,
					authenticatedParticipant = true,
					spectator = false,
					durable = true,
				})
			)
			assertions.equal(finished.tutorial.tutorialStep, 8)
			local preserved = success(assertions, tutorial:repairTravel(USER_ID, "repair-after-durable-result"))
			assertions.isFalse(preserved.advanced)
			assertions.equal(preserved.tutorial.tutorialStep, 8)
			local foreignReturn = success(assertions, tutorial:observeLobbyReturn(USER_ID, "match:tutorial-foreign"))
			assertions.isFalse(foreignReturn.advanced)
			assertions.equal(foreignReturn.tutorial.tutorialStep, 8)
			local returned = success(assertions, tutorial:observeLobbyReturn(USER_ID, matchId))
			assertions.equal(returned.tutorial.tutorialStep, 9)
			assertions.isTrue(returned.tutorial.tutorialCompleted)
			assertions.isFalse(returned.tutorial.skipped)
		end
	),

	TestHarness.case("repairs an authenticated early Match return back to solo queue guidance", function(assertions)
		local _profile, tutorial = rig(assertions)
		local initialized = success(assertions, tutorial:initialize(USER_ID))
		local learned = success(assertions, tutorial:advance(USER_ID, intent(30, initialized.revision)))
		success(assertions, tutorial:advance(USER_ID, intent(31, learned.revision)))
		success(assertions, tutorial:observeSoloEasyQueue(USER_ID, queueSnapshot("PartyOnly"), "queue-early-return"))

		local matchId = "match:tutorial-early-return"
		local arrived = success(
			assertions,
			tutorial:observeMatchArrival(USER_ID, {
				matchId = matchId,
				mapId = TutorialService.RELEASE_MAP_ID,
				difficultyId = TutorialService.EASY_DIFFICULTY_ID,
				privacy = "PartyOnly",
				expectedUserIds = { USER_ID },
				authenticatedParticipant = true,
				spectator = false,
			})
		)
		assertions.equal(arrived.tutorial.tutorialStep, 5)

		local foreign = success(assertions, tutorial:observeLobbyReturn(USER_ID, "match:tutorial-other"))
		assertions.isFalse(foreign.advanced)
		assertions.equal(foreign.tutorial.tutorialStep, 5)
		local repaired = success(assertions, tutorial:observeLobbyReturn(USER_ID, matchId))
		assertions.isTrue(repaired.advanced)
		assertions.equal(repaired.tutorial.tutorialStep, 3)
		assertions.isNil(repaired.tutorial.trackedMatchId)
		assertions.isFalse(repaired.tutorial.tutorialCompleted)
	end),

	TestHarness.case(
		"permits skip only after initialization and replays without granting starters again",
		function(assertions)
			local profile, tutorial = rig(assertions)
			assertions.isFalse(tutorial:skip(USER_ID, intent(20, 1)).ok)
			local initialized = success(assertions, tutorial:initialize(USER_ID))
			local skipped = success(assertions, tutorial:skip(USER_ID, intent(21, initialized.revision)))
			assertions.equal(skipped.tutorial.tutorialStep, 9)
			assertions.isTrue(skipped.tutorial.skipped)
			local replayed = success(assertions, tutorial:replay(USER_ID, intent(22, skipped.revision)))
			assertions.equal(replayed.tutorial.tutorialStep, 1)
			assertions.equal(replayed.tutorial.attempt, 2)
			assertions.isFalse(replayed.tutorial.tutorialCompleted)
			local current = success(assertions, profile:read(USER_ID))
			assertions.equal(current.stats.towersAcquired, 2)
			assertions.equal(#current.equippedUnitIds, 2)
		end
	),

	TestHarness.case("namespaces repeated server observations by tutorial attempt", function(assertions)
		local profile, tutorial = rig(assertions)
		local initialized = success(assertions, tutorial:initialize(USER_ID))
		local learned = success(assertions, tutorial:advance(USER_ID, intent(40, initialized.revision)))
		success(assertions, tutorial:advance(USER_ID, intent(41, learned.revision)))
		local firstQueue = success(
			assertions,
			tutorial:observeSoloEasyQueue(USER_ID, queueSnapshot("PartyOnly"), "queue-reused-across-replay")
		)
		assertions.equal(firstQueue.tutorial.tutorialStep, 4)
		assertions.equal(firstQueue.tutorial.attempt, 1)

		local skipped = success(assertions, tutorial:skip(USER_ID, intent(42, firstQueue.revision)))
		local replayed = success(assertions, tutorial:replay(USER_ID, intent(43, skipped.revision)))
		local relearned = success(assertions, tutorial:advance(USER_ID, intent(44, replayed.revision)))
		local reequipped = success(assertions, tutorial:advance(USER_ID, intent(45, relearned.revision)))
		assertions.equal(reequipped.tutorial.tutorialStep, 3)
		assertions.equal(reequipped.tutorial.attempt, 2)

		local receiptCount = #success(assertions, profile:read(USER_ID)).receipts
		local secondQueue = success(
			assertions,
			tutorial:observeSoloEasyQueue(USER_ID, queueSnapshot("PartyOnly"), "queue-reused-across-replay")
		)
		assertions.isTrue(secondQueue.advanced)
		assertions.equal(secondQueue.tutorial.tutorialStep, 4)
		assertions.equal(secondQueue.tutorial.attempt, 2)
		assertions.equal(#success(assertions, profile:read(USER_ID)).receipts, receiptCount + 1)
	end),
})
