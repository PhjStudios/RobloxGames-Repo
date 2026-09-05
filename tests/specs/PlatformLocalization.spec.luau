--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local Localization = require(ReplicatedStorage.Shared.localization.Localization)
local Messages = require(ReplicatedStorage.Shared.localization.Messages)
local Towers = require(ReplicatedStorage.Shared.config.Towers)
local Maps = require(ReplicatedStorage.Shared.config.Maps)
local Difficulties = require(ReplicatedStorage.Shared.config.Difficulties)
local Enemies = require(ReplicatedStorage.Shared.config.Enemies)
local Banners = require(ReplicatedStorage.Shared.config.Banners)
local AcquisitionConfig = require(ReplicatedStorage.Shared.acquisition.AcquisitionConfig)
local WorldMessages = require(ReplicatedStorage.Shared.localization.WorldMessages)

return TestHarness.suite("platform localization contracts", {
	TestHarness.case(
		"static metadata rebinds controls whose constructor reference is no longer retained",
		function(assertions)
			local root = Instance.new("Folder")
			local label = Instance.new("TextLabel")
			label.Parent = root
			local key = "playable_match_view.ready"
			local english = Localization.text(key)
			label.Text = english
			label:SetAttribute("ATDLocalizationText", key)
			label:SetAttribute("ATDLocalizationLastText", english)
			Localization.setMode("pseudo50")
			Localization.refresh(root)
			local expanded = label.Text
			Localization.setMode("en")
			assertions.isTrue(expanded ~= english)
			assertions.equal(label.Text, english)
			root:Destroy()
		end
	),
	TestHarness.case("static controls retranslate live without overwriting a later dynamic value", function(assertions)
		local button = Instance.new("TextButton")
		assertions.isTrue(Localization.bind(button, "playable_match_view.ready"))
		assertions.equal(button:GetAttribute("ATDLocalizationText"), "playable_match_view.ready")
		local english = button.Text
		Localization.setMode("pseudo50")
		local expanded = button.Text
		Localization.setMode("en")
		assertions.isTrue(expanded ~= english)
		assertions.equal(button.Text, english)
		button.Text = "Dynamic state"
		Localization.setMode("pseudo30")
		local preserved = button.Text
		Localization.setMode("en")
		assertions.equal(preserved, "Dynamic state")
		assertions.equal(Localization.format("lobby_view.ant_tower_defense", {}, "pseudo50").value, "ANT TOWER DEFENSE")
		button:Destroy()
	end),
	TestHarness.case(
		"world signs preserve keys and proper names while formatting in the client locale",
		function(assertions)
			local label = Instance.new("TextLabel")
			assertions.isTrue(
				WorldMessages.set(
					label,
					"queue_world.roster_captain",
					{ count = 2, capacity = 4, captain = "Scout Ant" }
				)
			)
			assertions.equal(label:GetAttribute("ATDMessageKey"), "queue_world.roster_captain")
			local english = label.Text
			Localization.setMode("pseudo50")
			local rendered = WorldMessages.render(label)
			Localization.setMode("en")
			assertions.isTrue(rendered)
			assertions.isTrue(label.Text ~= english)
			assertions.contains(label.Text, "Scout Ant")
			assertions.isFalse(WorldMessages.set(label, "common.you"))
			assertions.isFalse(
				WorldMessages.set(
					label,
					"queue_world.roster_captain",
					{ count = 2, capacity = 4, captain = "<script>" }
				)
			)
			assertions.isTrue(WorldMessages.set(label, "queue_world.empty"))
			assertions.isNil(label:GetAttribute("ATDMessageArgument_captain"))
			label:Destroy()
		end
	),
	TestHarness.case("critical ready and rematch counts accept authoritative numeric arguments", function(assertions)
		assertions.equal(
			Localization.text("playable_match_controller.players_ready", {
				mapDisplayName = "Garden",
				difficultyDisplayName = "Normal",
				readyCount = 1,
				participantCount = 4,
			}),
			"Garden • Normal\n1/4 players ready"
		)
		assertions.equal(
			Localization.text("playable_match_controller.connected_participant_votes", { state = "Pending", votes = 3 }),
			"Pending • 3 connected participant votes"
		)
	end),
	TestHarness.case("all catalog keys placeholders and concrete argument schemas agree", function(assertions)
		assertions.isTrue(Localization.validateCatalog())
		local count = 0
		for key, entry in Messages.entries do
			count += 1
			local arguments = {}
			for name, kind in entry.arguments do
				assertions.isTrue(kind == "number" or kind == "text" or kind == "proper")
				arguments[name] = if kind == "number" then 12 else "Bounded value"
			end
			local rendered = Localization.format(key, arguments, "en")
			assertions.isTrue(rendered.ok)
			assertions.isTrue(#rendered.value <= Localization.MAX_OUTPUT_BYTES)
		end
		assertions.isTrue(count > 400)
	end),
	TestHarness.case(
		"every current content name and description has explicit localization policy",
		function(assertions)
			for _, catalog in { Towers, Maps, Difficulties, Enemies, Banners } do
				for _, definition in catalog do
					assertions.equal(Messages.properNames[definition.id], definition.displayName)
					if definition.description ~= nil then
						assertions.isNotNil(Messages.descriptions[definition.id])
						assertions.equal(Localization.contentDescription(definition.id), definition.description)
					end
				end
			end
			for _, policy in AcquisitionConfig.banners do
				assertions.equal(Localization.contentPolicy(policy.bannerId), policy.policyDisclosure)
			end
		end
	),
	TestHarness.case(
		"thirty forty and fifty percent expansion preserves named arguments and proper names",
		function(assertions)
			local key = "lobby_controller.gold_is_permanent_and_opens_earn_only"
			local source = Localization.format(key, {}, "en")
			assertions.isTrue(source.ok)
			local sourceLength = utf8.len(source.value) :: number
			for mode, expansion in { pseudo30 = 0.3, pseudo40 = 0.4, pseudo50 = 0.5 } do
				local expanded = Localization.format(key, {}, mode)
				assertions.isTrue(expanded.ok)
				local length = utf8.len(expanded.value) :: number
				assertions.isTrue(length >= sourceLength * (1 + expansion))
				assertions.isTrue(length <= sourceLength * (1 + expansion) + 1)
				local result = Localization.format(
					"match.result.victory",
					{ mapName = "Backyard Garden", difficultyName = "Easy", waves = 20, health = 100, damage = 15_000 },
					mode
				)
				assertions.isTrue(result.ok)
				assertions.contains(result.value, "Backyard Garden")
				assertions.contains(result.value, "Easy")
				assertions.contains(result.value, "15,000")
			end
		end
	),
	TestHarness.case("rejects missing extra hostile unbounded and nonfinite arguments", function(assertions)
		for _, arguments in
			{ {}, { amount = 1, extra = true }, { amount = math.huge }, { amount = 0 / 0 }, { amount = "12" } }
		do
			assertions.isFalse(Localization.format("common.currency.gold", arguments, "en").ok)
		end
		for _, value in { "<b>unsafe</b>", "bad\0value", string.rep("x", Localization.MAX_TEXT_BYTES + 1), "\255" } do
			assertions.isFalse(Localization.format("lobby.party.picker", { player = value }, "en").ok)
		end
		assertions.isFalse(Localization.format("missing.key", {}, "en").ok)
		assertions.isFalse(Localization.format("common.you", {}, "invented-language").ok)
		assertions.isFalse(Localization.setMode("fr"))
	end),
	TestHarness.case(
		"formats numbers currencies exact odds and timers through one English boundary",
		function(assertions)
			assertions.equal(Localization.number(2_147_483_647), "2,147,483,647")
			assertions.equal(Localization.number(-1_250.5, 2), "-1,250.50")
			assertions.equal(Localization.currency("Gold", 2_250), "2,250 Gold")
			assertions.equal(Localization.currency("BattleCash", 500), "500 Battle Cash")
			assertions.equal(Localization.percent(0.125), "0.125%")
			assertions.equal(Localization.percent(0.00001), "0.00001%")
			assertions.equal(Localization.percent(0.000000001), "0.000000001%")
			assertions.equal(Localization.percent(100), "100%")
			assertions.equal(Localization.timer(65.1), "1:06")
			assertions.isNil(Localization.number(math.huge))
			assertions.isNil(Localization.percent(101))
			assertions.isNil(Localization.timer(-1))
		end
	),
})
