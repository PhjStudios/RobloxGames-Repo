--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local RobloxAdapter = require(script.Parent.Parent.Support.RobloxAdapter)
local ProductionRateLimits = require(script.Parent.Parent.ProductionServerNetworking.ProductionRateLimits)
local ServerRateLimiter = require(script.Parent.Parent.ProductionServerNetworking.ServerRateLimiter)
local ServerRequestDispatcher = require(script.Parent.Parent.ProductionServerNetworking.ServerRequestDispatcher)

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage").Shared
local EnvironmentContext = require(Shared.logging.EnvironmentContext)
local Log = require(Shared.logging.Log)
local PlacementProtocol = require(Shared.match.PlacementProtocol)
local ProductionRemotes = require(Shared.network.ProductionRemotes)
local RequestProtocol = require(Shared.network.RequestProtocol)

type Assertions = TestHarness.Assertions

local playerSequence = 0

local function logger(): Log.Logger
	return Log.new(EnvironmentContext.new("server", "Match", 0, false))
end

local function newPlayer(): Player
	playerSequence += 1
	local player = Instance.new("Player") :: Player
	player.Name = `PlacementNetworkPlayer{playerSequence}`
	player.Parent = Players
	return player
end

local function connection(): RBXScriptConnection
	return RobloxAdapter.createConnection(function() end) :: any
end

local function requestWire(requestIdValue: string, payload: unknown): RequestProtocol.RawRequest
	local idResult = RequestProtocol.createRequestId(requestIdValue)
	if not idResult.ok then
		error("placement network request ID did not validate", 0)
	end
	local wireResult = RequestProtocol.buildRequest(idResult.value, payload)
	if not wireResult.ok then
		error("placement network request did not build", 0)
	end
	return wireResult.value
end

local function payload(positionXZ: Vector2): any
	return {
		matchId = "match:phase13-network",
		observedQueryRevision = 1,
		loadoutRevision = 1,
		slot = 1,
		positionXZ = positionXZ,
		yawDegrees = 0,
	}
end

local function responseCode(envelope: unknown): string
	local resultValue = RequestProtocol.parseResponse(envelope)
	if not resultValue.ok then
		error("placement network response did not parse", 0)
	end
	if resultValue.value.state == "Success" then
		return "Success"
	end
	return resultValue.value.error.code
end

local function makeRuntime(): any
	local policySetResult = ServerRateLimiter.createPolicySet(ProductionRemotes, "Match", ProductionRateLimits)
	if not policySetResult.ok then
		error("placement production policy set did not validate", 0)
	end
	local state: any = {
		rateNow = 0,
		observationNow = 0,
		handlerCount = 0,
		sent = {},
		reenter = nil,
	}
	local limiter = ServerRateLimiter.new(logger(), Players, policySetResult.value, function()
		return state.rateNow
	end, function(_handler)
		return connection()
	end, function(_report) end)
	state.limiterCleanup = limiter:initialize()
	limiter:start()

	local definition = ProductionRemotes:get(PlacementProtocol.SUBMIT_PLACEMENT_ENDPOINT)
	if definition == nil then
		error("placement production definition is missing", 0)
	end
	local contract = ServerRequestDispatcher.createRequestContract(
		ProductionRemotes,
		"Match",
		definition,
		PlacementProtocol.SubmitPlacementPayloadSchema,
		PlacementProtocol.PlacementReceiptSchema,
		function(context)
			return ServerRequestDispatcher.isContext(context)
		end,
		function(_context, canonicalPayload)
			state.handlerCount += 1
			local reenter = state.reenter
			if reenter ~= nil then
				state.reenter = nil
				reenter()
			end
			local intentValue = canonicalPayload :: PlacementProtocol.PlacementIntent
			return ServerRequestDispatcher.success(table.freeze({
				state = "Accepted",
				runtimeTowerId = state.handlerCount,
				placementCFrame = CFrame.new(intentValue.positionXZ.X, 0, intentValue.positionXZ.Y),
				queryRevision = state.handlerCount + 1,
			}))
		end
	)
	state.contract = contract
	state.responseRemote = Instance.new("RemoteEvent")
	local dispatcher = ServerRequestDispatcher.new(logger(), ProductionRemotes, "Match", Players, limiter, {
		clock = function()
			return state.observationNow
		end,
		connectPlayerRemoving = function(_handler)
			return connection()
		end,
		reporter = function(_report) end,
		sender = function(remote, player, envelope)
			table.insert(state.sent, table.freeze({ remote = remote, player = player, envelope = envelope }))
		end,
	})
	state.dispatcher = dispatcher
	dispatcher:registerContract(contract)
	state.dispatcherCleanup = dispatcher:initialize()
	dispatcher:start()
	return state
end

local function cleanupRuntime(state: any, players: { Player })
	pcall(function()
		state.dispatcherCleanup:cleanup()
	end)
	pcall(function()
		state.limiterCleanup:cleanup()
	end)
	pcall(function()
		state.responseRemote:Destroy()
	end)
	for _, player in players do
		pcall(function()
			player:Destroy()
		end)
	end
end

local function dispatch(state: any, player: Player, wire: RequestProtocol.RawRequest)
	state.dispatcher:dispatch(state.contract, state.responseRemote, player, wire)
end

return TestHarness.suite("Phase 13 placement network integration", {
	TestHarness.case(
		"rejects completed replay and extra-field payload before the placement handler",
		function(assertions)
			local state = makeRuntime()
			local player = newPlayer()
			local first = requestWire("PlacementReplay01", payload(Vector2.new(1, 2)))
			dispatch(state, player, first)
			dispatch(state, player, first)

			local extra = payload(Vector2.new(2, 3))
			extra.ownerUserId = 999
			dispatch(state, player, requestWire("PlacementExtra01", extra))

			assertions.equal(state.handlerCount, 1)
			assertions.equal(#state.sent, 3)
			assertions.equal(responseCode(state.sent[1].envelope), "Success")
			assertions.equal(responseCode(state.sent[2].envelope), "STALE_REQUEST")
			assertions.equal(responseCode(state.sent[3].envelope), "INVALID_PAYLOAD")
			cleanupRuntime(state, { player })
		end
	),

	TestHarness.case(
		"suppresses a pending duplicate request ID with one authoritative handler call",
		function(assertions)
			local state = makeRuntime()
			local player = newPlayer()
			local wire = requestWire("PlacementPending1", payload(Vector2.new(1, 2)))
			state.reenter = function()
				dispatch(state, player, wire)
			end
			dispatch(state, player, wire)
			assertions.equal(state.handlerCount, 1)
			assertions.equal(#state.sent, 1)
			assertions.equal(responseCode(state.sent[1].envelope), "Success")
			cleanupRuntime(state, { player })
		end
	),

	TestHarness.case("applies the exact three-request burst independently per live player", function(assertions)
		local state = makeRuntime()
		local first = newPlayer()
		local second = newPlayer()
		for index = 1, 4 do
			dispatch(state, first, requestWire(`PlacementBurstA{index}`, payload(Vector2.new(index, 0))))
		end
		for index = 1, 3 do
			dispatch(state, second, requestWire(`PlacementBurstB{index}`, payload(Vector2.new(index, 10))))
		end
		assertions.equal(state.handlerCount, 6)
		assertions.equal(#state.sent, 7)
		assertions.equal(responseCode(state.sent[1].envelope), "Success")
		assertions.equal(responseCode(state.sent[2].envelope), "Success")
		assertions.equal(responseCode(state.sent[3].envelope), "Success")
		assertions.equal(responseCode(state.sent[4].envelope), "RATE_LIMITED")
		assertions.equal(responseCode(state.sent[5].envelope), "Success")
		assertions.equal(responseCode(state.sent[6].envelope), "Success")
		assertions.equal(responseCode(state.sent[7].envelope), "Success")
		cleanupRuntime(state, { first, second })
	end),

	TestHarness.case("drops a detached sender without invoking or responding", function(assertions)
		local state = makeRuntime()
		local player = newPlayer()
		player.Parent = nil
		dispatch(state, player, requestWire("PlacementDetached", payload(Vector2.new(1, 2))))
		assertions.equal(state.handlerCount, 0)
		assertions.equal(#state.sent, 0)
		cleanupRuntime(state, { player })
	end),
})
