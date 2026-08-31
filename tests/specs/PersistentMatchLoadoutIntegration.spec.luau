--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local AcquisitionService = require(script.Parent.Parent.ProductionServerLobbyAcquisition.AcquisitionService)
local InventoryService = require(script.Parent.Parent.ProductionServerLobbyInventory.InventoryService)
local SettingsService = require(script.Parent.Parent.ProductionServerLobbySettings.SettingsService)
local ProfileService = require(script.Parent.Parent.ProductionServerProfile.ProfileService)
local PlayableMatchRuntime = require(script.Parent.Parent.ProductionServerPlayable.PlayableMatchRuntime)
local IsolatedProfileStore = require(script.Parent.Parent.Fixtures.IsolatedProfileStore)

local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local MatchLoadoutProtocol = require(ReplicatedStorage.Shared.match.MatchLoadoutProtocol)

type Assertions = TestHarness.Assertions

local USER_ID = 919
local MATCH_ID = "match:persistent-loadout"

local loaded = ConfigurationValidator.validateLoaded()
if not loaded.ok then
	error("expected production configuration", 0)
end
local CONFIGURATION = loaded.value

local function success(assertions: Assertions, result: any): any
	assertions.isTrue(result.ok)
	if not result.ok then
		error("expected persistent loadout integration operation to succeed", 0)
	end
	return result.value
end

local function profileService(assertions: Assertions, store: IsolatedProfileStore.Store, sessionId: string): any
	return success(
		assertions,
		ProfileService.new(CONFIGURATION.towers, store, {
			sessionId = sessionId,
			clock = function(): number
				return 80_000
			end,
			wait = function(_seconds: number) end,
		})
	)
end

local function matchLoadout(assertions: Assertions, inventory: any, settings: any): MatchLoadoutProtocol.Snapshot
	local slots = table.create(#inventory.equipped)
	for index, equipped in inventory.equipped do
		slots[index] = {
			slot = equipped.slot,
			unitId = equipped.unitId,
			towerId = equipped.towerId,
		}
	end
	return success(
		assertions,
		MatchLoadoutProtocol.validate({
			userId = USER_ID,
			revision = inventory.revision,
			slots = slots,
			settings = settings,
		}, CONFIGURATION)
	)
end

local function runtimeMap(): any
	local first = Vector3.new(-1, 0, 0)
	local last = Vector3.new(1, 0, 0)
	return {
		mapId = "map:phase07-graybox",
		base = { cframe = CFrame.new(last), position = last },
		bounds = { cframe = CFrame.new(), size = Vector3.new(100, 20, 100) },
		lanes = {
			{
				id = "main",
				totalDistance = 2,
				points = {
					{ kind = "Path", nodeOrder = 1, cframe = CFrame.new(first), position = first, distance = 0 },
					{ kind = "Path", nodeOrder = 2, cframe = CFrame.new(last), position = last, distance = 2 },
				},
			},
		},
		placementZones = {
			{ id = "land", cframe = CFrame.new(0, -1, 0), size = Vector3.new(80, 2, 80) },
		},
		noPlacementZones = {},
		cameraAnchors = {},
		playerSpawns = {},
	}
end

local function expectRejected(assertions: Assertions, outcome: any, reason: string)
	assertions.isFalse(outcome.accepted)
	assertions.equal(outcome.reason, reason)
end

return TestHarness.suite("persistent saved loadout controls local Match", {
	TestHarness.case(
		"persists acquired equipped slots and freezes only those choices into authoritative placement",
		function(assertions)
			local store = IsolatedProfileStore.new()
			local firstProfile = profileService(assertions, store, "loadout-session-first")
			local starter = success(assertions, firstProfile:load(USER_ID))
			local firstInventory = success(assertions, InventoryService.new(firstProfile, CONFIGURATION))
			local starterInventory = success(assertions, firstInventory:getSnapshot(USER_ID))
			assertions.equal(starterInventory.revision, starter.revision)
			assertions.equal(#starterInventory.units, 1)
			assertions.equal(#starterInventory.equipped, 1)
			assertions.equal(starterInventory.equipped[1].towerId, "tower:dart-ant")

			local starterLoadout = matchLoadout(assertions, starterInventory, starter.settings)
			assertions.equal(#starterLoadout.slots, 1)
			assertions.equal(starterLoadout.slots[1].towerId, "tower:dart-ant")
			assertions.isTrue(table.isfrozen(starterLoadout))
			assertions.isTrue(table.isfrozen(starterLoadout.slots))

			local randomCalls = 0
			local generatedCalls = 0
			local acquisition = success(
				assertions,
				AcquisitionService.new(firstProfile, CONFIGURATION, {
					nextNumber = function(): number
						randomCalls += 1
						return 0.7
					end,
				}, {
					generate = function(): string
						generatedCalls += 1
						return "unit:persistent-rapid"
					end,
				}, {
					now = function(): number
						return 80_000
					end,
				})
			)
			local pull = success(
				assertions,
				acquisition:pull(USER_ID, {
					transactionId = "transaction:persistent-pull",
					expectedRevision = starterInventory.revision,
					bannerId = "banner:starter",
					bannerVersion = 1,
					quantity = 1,
				})
			)
			assertions.equal(pull.results[1].towerId, "tower:rapid-ant")
			assertions.equal(pull.results[1].unitId, "unit:persistent-rapid")
			assertions.isTrue(pull.results[1].isNew)
			assertions.equal(pull.goldBefore, 2_000)
			assertions.equal(pull.goldAfter, 1_750)
			assertions.equal(randomCalls, 1)
			assertions.equal(generatedCalls, 1)

			local afterPull = success(assertions, firstInventory:getSnapshot(USER_ID))
			assertions.equal(#afterPull.units, 2)
			assertions.equal(#afterPull.equipped, 1)
			local equipped = success(
				assertions,
				firstInventory:equip(USER_ID, {
					transactionId = "transaction:persistent-equip",
					expectedRevision = afterPull.revision,
					unitId = "unit:persistent-rapid",
					slot = 2,
				})
			)
			assertions.isTrue(equipped.changed)
			assertions.equal(#equipped.snapshot.equipped, 2)
			assertions.equal(equipped.snapshot.equipped[2].towerId, "tower:rapid-ant")
			local settingsService = success(assertions, SettingsService.new(firstProfile))
			local preferredSettings = table.clone(CONFIGURATION.defaultSettings) :: any
			preferredSettings.transactionId = "transaction:persistent-match-settings"
			preferredSettings.expectedRevision = equipped.snapshot.revision
			preferredSettings.uiScale = 0.75
			preferredSettings.reducedMotionEnabled = true
			preferredSettings.enemyHealthBarsEnabled = false
			preferredSettings.otherPlayerEffectsEnabled = false
			preferredSettings.lowDetailEnabled = true
			preferredSettings.towerRangeEnabled = false
			local savedSettings = success(assertions, settingsService:update(USER_ID, preferredSettings))
			assertions.equal(savedSettings.settings.uiScale, 0.75)
			assertions.isTrue(firstProfile:flush(USER_ID).ok)
			assertions.isTrue(firstProfile:release(USER_ID).ok)

			local secondProfile = profileService(assertions, store, "loadout-session-second")
			local returned = success(assertions, secondProfile:load(USER_ID))
			local returnedInventoryService = success(assertions, InventoryService.new(secondProfile, CONFIGURATION))
			local returnedInventory = success(assertions, returnedInventoryService:getSnapshot(USER_ID))
			assertions.equal(returnedInventory.revision, returned.revision)
			assertions.equal(#returnedInventory.units, 2)
			assertions.equal(#returnedInventory.equipped, 2)
			assertions.equal(returnedInventory.equipped[1].towerId, "tower:dart-ant")
			assertions.equal(returnedInventory.equipped[2].towerId, "tower:rapid-ant")
			assertions.equal(returned.settings.uiScale, 0.75)
			assertions.isTrue(returned.settings.reducedMotionEnabled)

			local savedLoadout = matchLoadout(assertions, returnedInventory, returned.settings)
			assertions.equal(savedLoadout.revision, returned.revision)
			assertions.equal(#savedLoadout.slots, 2)
			assertions.equal(savedLoadout.slots[1].unitId, returnedInventory.equipped[1].unitId)
			assertions.equal(savedLoadout.slots[2].unitId, "unit:persistent-rapid")

			local runtime = success(
				assertions,
				PlayableMatchRuntime.new({
					matchId = MATCH_ID,
					configuration = CONFIGURATION,
					runtimeMap = runtimeMap(),
					participantLoadouts = { savedLoadout },
				})
			)
			local initial = success(assertions, runtime:getSnapshot(USER_ID, 100))
			assertions.equal(initial.loadoutRevision, savedLoadout.revision)
			assertions.equal(initial.settings.uiScale, 0.75)
			assertions.isTrue(initial.settings.reducedMotionEnabled)
			assertions.isFalse(initial.settings.enemyHealthBarsEnabled)
			assertions.isFalse(initial.settings.otherPlayerEffectsEnabled)
			assertions.isTrue(initial.settings.lowDetailEnabled)
			assertions.isFalse(initial.settings.towerRangeEnabled)
			assertions.equal(initial.battleCash, 500)
			assertions.equal(#initial.towerOptions, 2)
			assertions.equal(initial.towerOptions[1].towerId, "tower:dart-ant")
			assertions.equal(initial.towerOptions[2].towerId, "tower:rapid-ant")
			assertions.isTrue(runtime:submitReady(USER_ID, MATCH_ID, 100).accepted)

			expectRejected(
				assertions,
				runtime:placeTower(
					USER_ID,
					MATCH_ID,
					"tower:guard-ant",
					3,
					savedLoadout.revision,
					Vector3.new(0, 0, 0),
					0,
					100
				),
				"UnequippedTower"
			)
			expectRejected(
				assertions,
				runtime:placeTower(
					USER_ID,
					MATCH_ID,
					"tower:rapid-ant",
					1,
					savedLoadout.revision,
					Vector3.new(0, 0, 0),
					0,
					100
				),
				"UnequippedTower"
			)
			expectRejected(
				assertions,
				runtime:placeTower(
					USER_ID,
					MATCH_ID,
					"tower:dart-ant",
					1,
					savedLoadout.revision - 1,
					Vector3.new(0, 0, 0),
					0,
					100
				),
				"StaleLoadout"
			)
			expectRejected(
				assertions,
				(runtime :: any):placeTower(
					USER_ID,
					MATCH_ID,
					"tower:dart-ant",
					1,
					savedLoadout.revision,
					"not-a-vector",
					0,
					100
				),
				"InvalidPlacement"
			)
			local afterRejected = success(assertions, runtime:getSnapshot(USER_ID, 100))
			assertions.equal(afterRejected.battleCash, 500)
			assertions.equal(#afterRejected.towers, 0)

			local valid = runtime:placeTower(
				USER_ID,
				MATCH_ID,
				"tower:dart-ant",
				1,
				savedLoadout.revision,
				Vector3.new(0, 0, 0),
				0,
				100
			)
			assertions.isTrue(valid.accepted)
			local afterValid = success(assertions, runtime:getSnapshot(USER_ID, 100))
			assertions.equal(afterValid.battleCash, 380)
			assertions.equal(#afterValid.towers, 1)
			assertions.equal(afterValid.towers[1].towerId, "tower:dart-ant")

			local persistentAfterMatch = success(assertions, secondProfile:read(USER_ID))
			assertions.equal(persistentAfterMatch.gold, 1_750)
			assertions.equal(persistentAfterMatch.revision, savedLoadout.revision)
			assertions.isTrue(runtime:cleanup().ok)
			assertions.isTrue(secondProfile:release(USER_ID).ok)
		end
	),
})
