--!strict

-- Runtime-only LocalScript runner. It sends ordinary validated requests for the
-- local participant; it cannot inject waves, cash, entities, damage or results.
return function(Window: any, maximumSeconds: number?)
	local RunService = game:GetService("RunService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local Stats = game:GetService("Stats")
	assert(RunService:IsStudio() and RunService:IsRunning() and RunService:IsClient(), "Studio client required")
	assert(game.GameId == 10764687717 and game.PlaceId == 104415140644510, "staging Match required")
	assert(game.CreatorType == Enum.CreatorType.Group and game.CreatorId == 35420107, "staging owner required")
	assert(
		ReplicatedStorage:GetAttribute("ATDPlaceRole") == "Match" and Players.LocalPlayer ~= nil,
		"Match role required"
	)
	local limit = maximumSeconds or 600
	assert(type(limit) == "number" and limit >= 30 and limit <= 600, "duration must be 30 to 600 seconds")
	local Protocol = require(ReplicatedStorage.Shared.match.PlayableMatchProtocol)
	local Requests = require(ReplicatedStorage.Shared.network.RequestProtocol)
	local Registry = require(ReplicatedStorage.Shared.network.RemoteRegistry)
	local Catalog = require(ReplicatedStorage.Shared.network.ProductionRemotes)
	local nonce = string.sub(game:GetService("HttpService"):GenerateGUID(false), 1, 20)
	local started = os.clock()
	local deadline = started + limit
	local connections, samples, network = {}, {}, {}
	local current: any = nil
	local pending: any = nil
	local retired = {}
	local replayFrom: string? = nil
	local fault: string? = nil
	local sequence, completed = 0, 0
	local sampleFrames: any = nil
	local remotes = {}
	local codes = {
		Timeout = true,
		EndpointUnavailable = true,
		InvalidResponse = true,
		InvalidSnapshot = true,
		RequestRejected = true,
		ActionRejected = true,
		ScenarioChanged = true,
		RequiresSoloFiniteReady = true,
		CleanupMismatch = true,
		HarnessFailed = true,
	}
	local function failureCode(value: any): string
		if type(value) ~= "string" or #value > 2_048 then
			return "HarnessFailed"
		end
		for code in codes do
			if value == code or string.sub(value, -(#code + 2)) == ": " .. code then
				return code
			end
		end
		return "HarnessFailed"
	end
	local function check()
		assert(fault == nil, fault)
		assert(os.clock() < deadline, "Timeout")
	end
	local function awaitCondition(predicate: () -> boolean, timeout: number?)
		local untilTime = math.min(deadline, os.clock() + (timeout or limit))
		while not predicate() do
			check()
			assert(os.clock() < untilTime, "Timeout")
			task.wait(math.min(0.1, untilTime - os.clock()))
		end
		check()
	end
	local function countEnvelope(name: string, envelope: any)
		local row = network[name]
		if row == nil then
			row = { count = 0, estimatedBytes = 0, maximumBytes = 0, unmeasurable = 0 }
			network[name] = row
		end
		row.count += 1
		local bytes = Window.payloadEstimate(envelope)
		if bytes ~= nil then
			row.estimatedBytes += bytes
			row.maximumBytes = math.max(row.maximumBytes, bytes)
		else
			row.unmeasurable += 1
		end
	end
	local function observe(payload: any)
		local checked = Protocol.validateSnapshot(payload)
		assert(checked.ok, "InvalidSnapshot")
		local value = checked.value
		assert(
			#value.towers == 0
				and string.find(value.mapDisplayName, "[%c]") == nil
				and string.find(value.difficultyDisplayName, "[%c]") == nil,
			"ScenarioChanged"
		)
		assert(
			value.viewerRole == "Participant"
				and value.rewarding == false
				and value.modeKind == "Finite"
				and value.participants.participantCount == 1,
			"RequiresSoloFiniteReady"
		)
		if retired[value.matchId] then
			return
		end
		if current ~= nil then
			assert(value.mapId == current.mapId and value.difficultyId == current.difficultyId, "ScenarioChanged")
			if value.matchId ~= current.matchId then
				assert(replayFrom == current.matchId and value.state == "Ready", "ScenarioChanged")
				retired[current.matchId] = true
				replayFrom = nil
			elseif value.revision < current.revision then
				return
			end
		end
		-- Only current request identity is transiently held. Never return raw
		-- snapshots, participant IDs, inventories, settings or reward receipts.
		current = {
			matchId = value.matchId,
			mapId = value.mapId,
			difficultyId = value.difficultyId,
			mapName = value.mapDisplayName,
			difficultyName = value.difficultyDisplayName,
			contentVersion = value.contentVersion,
			revision = value.revision,
			state = value.state,
			outcome = value.result,
			wave = value.waveNumber,
			wavesCompleted = value.stats.wavesCompleted,
			baseHealth = value.baseHealth,
			towers = #value.towers,
			enemies = #value.enemies,
		}
	end
	local function connect(signal: RBXScriptSignal, callback: (...any) -> ())
		table.insert(
			connections,
			signal:Connect(function(...)
				local ok, code = pcall(callback, ...)
				if not ok then
					fault = failureCode(code)
				end
			end)
		)
	end
	local function request(name: string, payload: any, schema: any)
		check()
		assert(pending == nil and sequence < 10, "HarnessFailed")
		local checked = schema:validate(payload)
		assert(checked.ok, "InvalidResponse")
		sequence += 1
		local id = Requests.createRequestId(`repeat-{nonce}-{sequence}`)
		assert(id.ok, "HarnessFailed")
		local envelope = Requests.buildRequest(id.value, checked.value)
		assert(envelope.ok, "HarnessFailed")
		local item = { id = id.value.value, name = name, matchId = payload.matchId, done = false }
		pending = item
		countEnvelope(name .. ".Request", envelope.value)
		remotes[name].Request:FireServer(envelope.value)
		awaitCondition(function()
			return item.done
		end, 10)
		pending = nil
	end
	local function sample(cycle: number, phase: string)
		local expected = current.state
		sampleFrames = Window.new()
		local settledAt = os.clock() + 2
		awaitCondition(function()
			assert(current.state == expected, "ScenarioChanged")
			return os.clock() >= settledAt
		end, 3)
		local world = workspace:FindFirstChild("_ATDPlayablePresentation")
		assert(world ~= nil, "CleanupMismatch")
		local towers = world:FindFirstChild("Towers")
		local enemies = world:FindFirstChild("Enemies")
		local effects = world:FindFirstChild("AttackEffects")
		assert(towers ~= nil and enemies ~= nil and effects ~= nil, "CleanupMismatch")
		local worldTowers, worldEnemies, worldEffects =
			#towers:GetChildren(), #enemies:GetChildren(), #effects:GetChildren()
		if expected == "Ready" then
			assert(
				current.towers == 0
					and current.enemies == 0
					and worldTowers == 0
					and worldEnemies == 0
					and worldEffects == 0
					and #world:GetChildren() == 3
					and #world:GetDescendants() == 3,
				"CleanupMismatch"
			)
		end
		local measured, memory = pcall(Stats.GetTotalMemoryUsageMb, Stats)
		local traffic = {}
		for key, row in network do
			traffic[key] = table.clone(row)
		end
		table.insert(samples, {
			cycle = cycle,
			phase = phase,
			elapsedSeconds = os.clock() - started,
			mapName = current.mapName,
			difficultyName = current.difficultyName,
			contentVersion = current.contentVersion,
			state = current.state,
			outcome = current.outcome,
			terminalWave = current.wave,
			wavesCompleted = current.wavesCompleted,
			baseHealth = current.baseHealth,
			memoryMb = if measured then memory else nil,
			instances = #game:GetDescendants(),
			worldChildren = #world:GetChildren(),
			worldDescendants = #world:GetDescendants(),
			towers = worldTowers,
			enemies = worldEnemies,
			effects = worldEffects,
			frameMs = sampleFrames:summary(),
			network = traffic,
		})
		sampleFrames = nil
	end
	local succeeded, failure = pcall(function()
		local root = ReplicatedStorage:FindFirstChild(Registry.ROOT_NAME)
		local version = if root then root:FindFirstChild(Registry.VERSION_NAME) else nil
		assert(version ~= nil, "EndpointUnavailable")
		for _, name in
			{ Protocol.ENDPOINTS.GET_SNAPSHOT, Protocol.ENDPOINTS.SUBMIT_READY, Protocol.ENDPOINTS.SUBMIT_REPLAY }
		do
			local definition = Catalog:get(name)
			assert(definition.kind == "Request" and definition.direction == "ClientToServer", "EndpointUnavailable")
			local endpoint = version:FindFirstChild(name)
			local send = if endpoint then endpoint:FindFirstChild("Request") else nil
			local response = if endpoint then endpoint:FindFirstChild("Response") else nil
			assert(send and send:IsA("RemoteEvent") and response and response:IsA("RemoteEvent"), "EndpointUnavailable")
			remotes[name] = { Request = send }
			connect(response.OnClientEvent, function(envelope: any, ...: any)
				local parsed = Requests.parseResponse(envelope, ...)
				assert(parsed.ok, "InvalidResponse")
				local value = parsed.value
				local item = pending
				if item == nil or item.name ~= name or item.id ~= value.requestId.value then
					return
				end
				countEnvelope(name .. ".Response", envelope)
				assert(Requests.isSuccess(value), "RequestRejected")
				if name == Protocol.ENDPOINTS.GET_SNAPSHOT then
					observe(value.payload)
				else
					local receipt = Protocol.validateActionReceipt(value.payload)
					assert(receipt.ok and receipt.value.matchId == item.matchId, "InvalidResponse")
					assert(receipt.value.accepted, "ActionRejected")
				end
				item.done = true
			end)
		end
		for _, name in { Protocol.ENDPOINTS.REPLICATION, Protocol.ENDPOINTS.ATTACK_EVENT } do
			local endpoint = version:FindFirstChild(name)
			local event = if endpoint then endpoint:FindFirstChild("Event") else nil
			assert(event and event:IsA("RemoteEvent"), "EndpointUnavailable")
			connect(event.OnClientEvent, function(envelope: any, ...: any)
				countEnvelope(name, envelope)
				local parsed = Requests.parseEvent(envelope, ...)
				assert(parsed.ok, "InvalidResponse")
				if name == Protocol.ENDPOINTS.REPLICATION then
					observe(parsed.value.payload)
				else
					assert(Protocol.validateAttackEvent(parsed.value.payload).ok, "InvalidResponse")
				end
			end)
		end
		connect(RunService.RenderStepped, function(dt: number)
			if sampleFrames ~= nil then
				sampleFrames:add(dt * 1000)
			end
		end)
		request(Protocol.ENDPOINTS.GET_SNAPSHOT, {}, Protocol.GetSnapshotPayloadSchema)
		assert(current ~= nil and current.state == "Ready", "RequiresSoloFiniteReady")
		for cycle = 1, 3 do
			sample(cycle, "Ready")
			request(Protocol.ENDPOINTS.SUBMIT_READY, { matchId = current.matchId }, Protocol.ReadyPayloadSchema)
			awaitCondition(function()
				return current.state == "Results"
			end)
			sample(cycle, "Terminal")
			completed += 1
			local previous = current.matchId
			replayFrom = previous
			request(Protocol.ENDPOINTS.SUBMIT_REPLAY, { matchId = previous }, Protocol.ReplayPayloadSchema)
			awaitCondition(function()
				return current.matchId ~= previous and current.state == "Ready"
			end, 10)
		end
		sample(3, "FinalReady")
	end)
	local remaining = 0
	for _, connection in connections do
		pcall(function()
			connection:Disconnect()
		end)
		remaining += if connection.Connected then 1 else 0
	end
	table.clear(connections)
	table.clear(remotes)
	table.clear(retired)
	current, pending, replayFrom, sampleFrames = nil, nil, nil, nil
	return {
		procedure = "ATD_REPEATED_SESSION_PROFILE",
		version = 1,
		evidence = "Studio-emulated",
		ok = succeeded and remaining == 0,
		code = if remaining > 0 then "CleanupMismatch" elseif succeeded then "Completed" else failureCode(failure),
		requestedCycles = 3,
		completedCycles = completed,
		maximumSeconds = limit,
		durationSeconds = os.clock() - started,
		requests = sequence,
		probeConnectionsAfter = remaining,
		samples = samples,
		network = network,
		meaning = "No-tower finite leak outcomes and local replay; not campaign victory, published return, or long-term soak acceptance",
		payloadUnit = "JSON-like estimates; not Roblox wire bytes",
	}
end
