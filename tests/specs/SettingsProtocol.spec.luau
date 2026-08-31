--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local SettingsProtocol = require(ReplicatedStorage.Shared.settings.SettingsProtocol)

local function settings(): any
	return {
		version = 2,
		masterVolume = 1,
		musicVolume = 0.8,
		sfxVolume = 0.7,
		uiVolume = 0.6,
		cameraShakeIntensity = 0.5,
		damageNumbersEnabled = true,
		enemyHealthBarsEnabled = true,
		otherPlayerEffectsEnabled = false,
		lowDetailEnabled = false,
		reducedMotionEnabled = true,
		towerRangeEnabled = true,
		uiScale = 1,
	}
end

local function intent(): any
	local value = settings()
	value.transactionId = "transaction:settings-a"
	value.expectedRevision = 4
	return value
end

return TestHarness.suite("persistent settings protocol", {
	TestHarness.case("accepts and detaches the exact v2 settings record", function(assertions)
		local raw = settings()
		local result = SettingsProtocol.SettingsSchema:validate(raw)
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.notEqual(result.value, raw)
			assertions.isTrue(table.isfrozen(result.value))
			assertions.equal((result.value :: any).version, 2)
			assertions.equal((result.value :: any).uiScale, 1)
		end
	end),
	TestHarness.case("accepts inclusive numeric accessibility bounds", function(assertions)
		local minimum = settings()
		minimum.masterVolume = 0
		minimum.musicVolume = 0
		minimum.sfxVolume = 0
		minimum.uiVolume = 0
		minimum.cameraShakeIntensity = 0
		minimum.uiScale = 0.75
		assertions.isTrue(SettingsProtocol.SettingsSchema:validate(minimum).ok)

		local maximum = settings()
		maximum.masterVolume = 1
		maximum.musicVolume = 1
		maximum.sfxVolume = 1
		maximum.uiVolume = 1
		maximum.cameraShakeIntensity = 1
		maximum.uiScale = 1.25
		assertions.isTrue(SettingsProtocol.SettingsSchema:validate(maximum).ok)
	end),
	TestHarness.case("rejects old versions out-of-range and non-finite numbers", function(assertions)
		local old = settings()
		old.version = 1
		assertions.isFalse(SettingsProtocol.SettingsSchema:validate(old).ok)

		local loud = settings()
		loud.masterVolume = 1.0001
		assertions.isFalse(SettingsProtocol.SettingsSchema:validate(loud).ok)

		local tiny = settings()
		tiny.uiScale = 0.7499
		assertions.isFalse(SettingsProtocol.SettingsSchema:validate(tiny).ok)

		local nonFinite = settings()
		nonFinite.cameraShakeIntensity = 0 / 0
		assertions.isFalse(SettingsProtocol.SettingsSchema:validate(nonFinite).ok)
	end),
	TestHarness.case("rejects missing unknown and type-confused fields", function(assertions)
		local missing = settings()
		missing.reducedMotionEnabled = nil
		assertions.isFalse(SettingsProtocol.SettingsSchema:validate(missing).ok)

		local private = settings()
		private.profileRevision = 5
		assertions.isFalse(SettingsProtocol.SettingsSchema:validate(private).ok)

		local confused = settings()
		confused.lowDetailEnabled = 0
		assertions.isFalse(SettingsProtocol.SettingsSchema:validate(confused).ok)
	end),
	TestHarness.case("requires a full revisioned update without client authority fields", function(assertions)
		local value = intent()
		assertions.isTrue(SettingsProtocol.UpdateIntentSchema:validate(value).ok)

		local partial = intent()
		partial.musicVolume = nil
		assertions.isFalse(SettingsProtocol.UpdateIntentSchema:validate(partial).ok)

		local forged = intent()
		forged.gold = 999_999
		assertions.isFalse(SettingsProtocol.UpdateIntentSchema:validate(forged).ok)

		local badId = intent()
		badId.transactionId = "settings-a"
		assertions.isFalse(SettingsProtocol.UpdateIntentSchema:validate(badId).ok)
	end),
	TestHarness.case("validates coherent bounded update receipts", function(assertions)
		local value = {
			transactionId = "transaction:settings-a",
			revision = 5,
			changed = true,
			settings = settings(),
		}
		local result = SettingsProtocol.validateUpdateReceipt(value)
		assertions.isTrue(result.ok)
		if result.ok then
			assertions.isTrue(table.isfrozen(result.value))
			assertions.isTrue(table.isfrozen(result.value.settings))
		end

		local wrongRevision = {
			transactionId = "transaction:settings-a",
			revision = 0,
			changed = true,
			settings = settings(),
		}
		assertions.isFalse(SettingsProtocol.validateUpdateReceipt(wrongRevision).ok)
	end),
	TestHarness.case("rejects cyclic and hostile table shapes without yielding", function(assertions)
		local cyclic = intent()
		cyclic.extra = cyclic
		assertions.isFalse(SettingsProtocol.UpdateIntentSchema:validate(cyclic).ok)

		local sparse = settings();
		(sparse :: any)[1] = "unexpected"
		assertions.isFalse(SettingsProtocol.SettingsSchema:validate(sparse).ok)
	end),
})
