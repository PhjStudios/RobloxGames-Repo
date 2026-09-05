--!strict

local Harness = require(script.Parent.Parent.Support.TestHarness)
local Report = require(script.Parent.Parent.Support.ContentBalanceReport)
local Shared = game:GetService("ReplicatedStorage").Shared
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local ContentSelection = require(Shared.config.ContentSelection)

return Harness.suite("read-only deterministic balance report", {
	Harness.case("renders byte-identical bounded content budgets from unchanged production inputs", function(a)
		local config = ConfigurationValidator.validateLoaded().value
		local before = config.towers.byId[ContentSelection.DART_STARTER_TOWER_ID].levels[1].attack.damage
		local first = Report.render(config, false)
		a.equal(first, Report.render(config, false))
		a.isTrue(#first < 100_000)
		a.contains(first, "content version 1")
		a.contains(first, "| 10000 |")
		a.contains(first, "role.balanced")
		a.equal(config.towers.byId[ContentSelection.DART_STARTER_TOWER_ID].levels[1].attack.damage, before)
	end),
	Harness.case("exports campaign results from the existing production runtime simulation", function(a)
		local config = ConfigurationValidator.validateLoaded().value
		local report = Report.render(config)
		a.contains(report, "Production-runtime campaign outcomes")
		a.contains(report, "| difficulty:easy-v1 | Victory | 20 |")
		print("ATD_BALANCE_REPORT_BEGIN\n" .. report .. "ATD_BALANCE_REPORT_END")
	end),
})
