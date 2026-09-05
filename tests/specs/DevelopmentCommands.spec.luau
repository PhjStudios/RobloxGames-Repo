--!strict

local Harness = require(script.Parent.Parent.Support.TestHarness)
local Commands = require(script.Parent.Parent.Support.SafeDevelopmentCommands)

local function environment(): any
	return {
		gameId = 10764687717,
		placeId = 104415140644510,
		role = "Match",
		creatorType = "Group",
		creatorId = 35420107,
		isStudio = true,
		isServer = true,
		runtimeOnly = true,
	}
end

return Harness.suite("isolated fail-closed development commands", {
	Harness.case("rejects mismatched place universe ownership role and execution context", function(a)
		local valid = environment()
		a.isTrue(Commands.authorized(valid))
		for _, field in
			{ "gameId", "placeId", "role", "creatorType", "creatorId", "isServer", "runtimeOnly", "isStudio" }
		do
			local rejected = table.clone(valid)
			rejected[field] = nil
			a.isFalse(Commands.authorized(rejected))
		end
		valid.gameId = 10757629094
		a.isFalse(Commands.authorized(valid))
	end),
	Harness.case("published use requires all private-test conditions and an explicit allowed account", function(a)
		local valid = environment()
		valid.isStudio = false
		valid.confirmedPrivateTest = true
		valid.privateServer = true
		valid.userId = 123
		valid.allowlistedUserIds = { [123] = true }
		a.isTrue(Commands.authorized(valid))
		for _, field in { "confirmedPrivateTest", "privateServer", "userId", "allowlistedUserIds" } do
			local rejected = table.clone(valid)
			rejected[field] = nil
			a.isFalse(Commands.authorized(rejected))
		end
		valid.allowlistedUserIds = setmetatable({}, {
			__index = function()
				return true
			end,
		})
		a.isFalse(Commands.authorized(valid))
	end),
	Harness.case("caps test cash and cannot invoke persistent currency or inventory operations", function(a)
		local cash = 0
		local commands = Commands.new(environment, {
			testRuntime = true,
			grantBattleCash = function(amount)
				cash += amount
				return true
			end,
		}, function()
			return 0
		end)
		for _ = 1, 5 do
			a.isTrue(commands:execute("GrantBattleCash", 10_000).ok)
		end
		a.isFalse(commands:execute("GrantBattleCash", 1).ok)
		a.equal(cash, 50_000)
		for _, name in { "GrantGold", "GrantInventory", "ResetPity", "DataStore", "Teleport", "Profile", "Purchase" } do
			a.isFalse(commands:execute(name, 1).ok)
		end
	end),
	Harness.case("reauthorizes every call and restricts mutating adapters to the isolated Match runtime", function(a)
		local env = environment()
		local invoked = 0
		local commands = Commands.new(function()
			return env
		end, {
			testRuntime = true,
			startWave = function()
				invoked += 1
				return true
			end,
		})
		a.isTrue(commands:execute("StartWave").ok)
		env.gameId = 10757629094
		a.isFalse(commands:execute("StartWave").ok)
		a.equal(invoked, 1)
		local missing = Commands.new(environment, {
			startWave = function()
				error("must never be called")
			end,
		})
		a.isFalse(missing:execute("StartWave").ok)
	end),
	Harness.case("rejects synthetic adapter authority and metatable inspection projections", function(a)
		local commands = Commands.new(
			environment,
			setmetatable({}, {
				__index = function(_, key)
					return if key == "testRuntime"
						then true
						else function()
							error("must never run")
						end
				end,
			})
		)
		a.equal(commands:execute("StartWave").code, "DENIED")
		for _, command in { "Inspect", "ValidateMap" } do
			local invalid = Commands.new(environment, {
				inspect = function()
					return setmetatable({}, {
						__index = function()
							error("private")
						end,
					})
				end,
				validateMap = function()
					return setmetatable({}, {
						__index = function()
							error("private")
						end,
					})
				end,
			})
			a.equal(invalid:execute(command).code, "FAILED")
		end
	end),
	Harness.case("ambiguous cash adapter failure consumes the finite session grant budget", function(a)
		local applied = 0
		local commands = Commands.new(environment, {
			testRuntime = true,
			grantBattleCash = function(amount)
				applied += amount
				coroutine.yield()
			end,
		})
		for _ = 1, 5 do
			a.equal(commands:execute("GrantBattleCash", 10_000).code, "FAILED")
		end
		a.equal(commands:execute("GrantBattleCash", 1).code, "INVALID_COMMAND")
		a.equal(applied, Commands.MAX_TEST_CASH)
	end),
	Harness.case("inspections are bounded projections and strip sensitive adapter data", function(a)
		local commands = Commands.new(environment, {
			inspect = function()
				return {
					towers = 1,
					enemies = 2,
					effects = 3,
					sounds = 0,
					instances = 20,
					connections = 2,
					requests = 4,
					wave = 5,
					profile = "private",
					accessCode = "secret",
				}
			end,
		})
		local result = commands:execute("Inspect")
		a.isTrue(result.ok)
		a.equal(result.value.enemies, 2)
		a.isNil(result.value.profile)
		a.isNil(result.value.accessCode)
		commands:cleanup()
		a.isFalse(commands:execute("Inspect").ok)
	end),
	Harness.case("bounds request density and contains failed or yielding adapters", function(a)
		local calls = 0
		local commands = Commands.new(environment, {
			testRuntime = true,
			startWave = function()
				calls += 1
				return true
			end,
		}, function()
			return 0
		end)
		for _ = 1, 40 do
			commands:execute("StartWave")
		end
		a.equal(calls, 30)
		for _, callback in
			{
				function()
					error("private")
				end,
				function()
					coroutine.yield()
				end,
			}
		do
			local failing = Commands.new(environment, { testRuntime = true, startWave = callback })
			a.isFalse(failing:execute("StartWave").ok)
		end
	end),
})
