--!strict

-- Test-only capability dispatcher. No chat handler, remote, production require,
-- persistent profile/currency method, or automatic startup registration exists.
local ServerStorage = game:GetService("ServerStorage")
local Commands = { MAX_COMMANDS_PER_MINUTE = 30, MAX_TEST_CASH = 50_000 }
local Methods = {}
Methods.__index = Methods
local ROLES = { [140661668701496] = "Lobby", [104415140644510] = "Match" }
local SCENARIOS = { Idle = true, Normal = true, Boss = true, Dense = true, Results = true, Cleanup = true }

local function integer(value: any, maximum: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= 0 and value <= maximum
end

function Commands.authorized(environment: any): boolean
	if
		type(environment) ~= "table"
		or getmetatable(environment) ~= nil
		or environment.gameId ~= 10764687717
		or ROLES[environment.placeId] ~= environment.role
		or environment.role == nil
		or environment.creatorType ~= "Group"
		or environment.creatorId ~= 35420107
		or environment.isServer ~= true
		or environment.runtimeOnly ~= true
	then
		return false
	end
	if environment.isStudio == true then
		return true
	end
	return environment.isStudio == false
		and environment.confirmedPrivateTest == true
		and environment.privateServer == true
		and integer(environment.userId, 9_007_199_254_740_991)
		and environment.userId > 0
		and type(environment.allowlistedUserIds) == "table"
		and getmetatable(environment.allowlistedUserIds) == nil
		and rawget(environment.allowlistedUserIds, environment.userId) == true
end

local function exactTestLocation(): boolean
	local support = script.Parent
	local tests = if support then support.Parent else nil
	return script:IsA("ModuleScript")
		and script.Name == "SafeDevelopmentCommands"
		and support ~= nil
		and support:IsA("Folder")
		and support.Name == "Support"
		and tests ~= nil
		and tests:IsA("Folder")
		and tests.Name == "AutomatedTests"
		and tests.Parent == ServerStorage
end

local function call(callback: any, ...: any): (boolean, any)
	if type(callback) ~= "function" then
		return false, nil
	end
	local thread = coroutine.create(callback)
	local ok, result = coroutine.resume(thread, ...)
	if not ok or coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, result
end

function Methods.execute(self: any, command: unknown, argument: unknown): any
	local ok, environment = call(self.environment)
	if self.closed or not exactTestLocation() or not ok or not Commands.authorized(environment) then
		return { ok = false, code = "DENIED" }
	end
	local timed, at = call(self.clock)
	if not timed or type(at) ~= "number" or at ~= at or at < 0 or at == math.huge then
		return { ok = false, code = "DENIED" }
	end
	if at - self.window >= 60 then
		self.window, self.count = at, 0
	end
	if self.count >= Commands.MAX_COMMANDS_PER_MINUTE then
		return { ok = false, code = "RATE_LIMITED" }
	end
	local mutating = command == "StartWave" or command == "GrantBattleCash" or command == "PresentationScenario"
	if mutating and (environment.role ~= "Match" or self.adapters.testRuntime ~= true) then
		return { ok = false, code = "DENIED" }
	end
	local callback
	if
		command == "GrantBattleCash"
		and integer(argument, 10_000)
		and self.cash + argument <= Commands.MAX_TEST_CASH
	then
		callback = self.adapters.grantBattleCash
	elseif command == "StartWave" and argument == nil then
		callback = self.adapters.startWave
	elseif command == "Inspect" and argument == nil then
		callback = self.adapters.inspect
	elseif command == "ValidateMap" and argument == nil then
		callback = self.adapters.validateMap
	elseif command == "PresentationScenario" and type(argument) == "string" and SCENARIOS[argument] then
		callback = self.adapters.presentationScenario
	end
	if callback == nil then
		return { ok = false, code = "INVALID_COMMAND" }
	end
	self.count += 1
	-- Reserve before calling: a failing adapter may already have applied a test
	-- mutation, so an ambiguous failure must still consume the session budget.
	if command == "GrantBattleCash" then
		self.cash += argument
	end
	local called, result = call(callback, argument)
	if not called then
		return { ok = false, code = "FAILED" }
	end
	if command == "Inspect" then
		if type(result) ~= "table" or getmetatable(result) ~= nil then
			return { ok = false, code = "FAILED" }
		end
		local safe = {}
		for _, key in { "towers", "enemies", "effects", "sounds", "instances", "connections", "requests", "wave" } do
			if not integer(result[key], 1_000_000) then
				return { ok = false, code = "FAILED" }
			end
			safe[key] = result[key]
		end
		return { ok = true, value = table.freeze(safe) }
	elseif command == "ValidateMap" then
		if
			type(result) ~= "table"
			or getmetatable(result) ~= nil
			or type(result.valid) ~= "boolean"
			or not integer(result.issueCount, 1000)
		then
			return { ok = false, code = "FAILED" }
		end
		return { ok = true, value = table.freeze({ valid = result.valid, issueCount = result.issueCount }) }
	elseif result ~= true then
		return { ok = false, code = "FAILED" }
	end
	return { ok = true }
end

function Methods.cleanup(self: any)
	self.closed = true
	self.adapters = {}
	self.environment = function()
		return nil
	end
end

function Commands.new(environment: () -> any, adapters: any, clock: (() -> number)?): any
	assert(exactTestLocation(), "development commands require the exact isolated test root")
	local safeAdapters = {}
	if type(adapters) == "table" and getmetatable(adapters) == nil then
		for _, key in
			{ "testRuntime", "grantBattleCash", "startWave", "inspect", "validateMap", "presentationScenario" }
		do
			safeAdapters[key] = adapters[key]
		end
	end
	return setmetatable({
		environment = environment,
		adapters = table.freeze(safeAdapters),
		clock = clock or os.clock,
		window = 0,
		count = 0,
		cash = 0,
		closed = false,
	}, Methods)
end

return table.freeze(Commands)
