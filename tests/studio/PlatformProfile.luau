--!strict

-- Runtime-only MCP harness. Inject PerformanceWindow as a local dependency;
-- no source is mapped into any production project and no raw payload is retained.
return function(options: any, Window: any)
	local RunService = game:GetService("RunService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Stats = game:GetService("Stats")
	assert(RunService:IsStudio() and RunService:IsRunning(), "staging Studio runtime required")
	assert(game.GameId == 10764687717 and game.CreatorId == 35420107, "staging ownership mismatch")
	assert(game.CreatorType == Enum.CreatorType.Group, "staging owner type mismatch")
	local role = ReplicatedStorage:GetAttribute("ATDPlaceRole")
	assert(
		(role == "Lobby" and game.PlaceId == 140661668701496) or (role == "Match" and game.PlaceId == 104415140644510),
		"staging place role mismatch"
	)
	local duration = options.durationSeconds
	assert(type(duration) == "number" and duration >= 2 and duration <= 45, "bounded duration required")
	local frame = Window.new()
	local networks, connections, added, removed = {}, {}, 0, 0
	local started = os.clock()
	local function readStats()
		local report = { instances = #game:GetDescendants() }
		for _, property in { "DataReceiveKbps", "DataSendKbps", "PhysicsReceiveKbps", "PhysicsSendKbps" } do
			local ok, value = pcall(function()
				return (Stats :: any)[property]
			end)
			if ok then
				report[property] = value
			end
		end
		local ok, memory = pcall(Stats.GetTotalMemoryUsageMb, Stats)
		if ok then
			report.memoryMb = memory
		end
		if RunService:IsClient() and role == "Match" then
			report.guiPhase = "Unavailable"
			local player = game:GetService("Players").LocalPlayer
			local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
			local gui = if playerGui then playerGui:FindFirstChild("ATDPlayableMatch") else nil
			local root = if gui and gui:IsA("ScreenGui") and gui.Enabled then gui:FindFirstChild("Root") else nil
			if root and root:IsA("GuiObject") and root.Visible then
				local ready = root:FindFirstChild("ReadyOverlay")
				local results = root:FindFirstChild("ResultsOverlay")
				local hud = root:FindFirstChild("TopHUD")
				local base = if hud then hud:FindFirstChild("BaseHealth") else nil
				local boss = root:FindFirstChild("BossStatus")
				local health = if boss then boss:FindFirstChild("Health") else nil
				local readyVisible = ready ~= nil and ready:IsA("GuiObject") and ready.Visible
				local resultsVisible = results ~= nil and results:IsA("GuiObject") and results.Visible
				if readyVisible ~= resultsVisible then
					report.guiPhase = if readyVisible then "Ready" else "Results"
				elseif not readyVisible and hud and hud:IsA("GuiObject") and hud.Visible then
					if base and base:IsA("GuiButton") and base.Active then
						report.guiPhase = "Playing"
					end
				end
				if boss and boss:IsA("GuiObject") then
					report.bossPanelVisible = boss.Visible
					-- The panel alone also signals an upcoming boss wave. Its health
					-- child distinguishes a currently displayed boss health summary.
					report.bossHealthVisible = boss.Visible
						and health ~= nil
						and health:IsA("GuiObject")
						and health.Visible
				end
			end
		end
		local world = workspace:FindFirstChild("_ATDPlayablePresentation")
		if world then
			report.presentationInstances = #world:GetDescendants()
			for _, name in { "Towers", "Enemies", "AttackEffects" } do
				local root = world:FindFirstChild(name)
				report[name] = if root then #root:GetChildren() else 0
			end
		end
		return report
	end
	local before = readStats()
	local samples = { before }
	local ok, failure = pcall(function()
		local signal = if RunService:IsClient() then RunService.RenderStepped else RunService.Heartbeat
		table.insert(
			connections,
			signal:Connect(function(dt)
				frame:add(dt * 1000)
			end)
		)
		table.insert(
			connections,
			game.DescendantAdded:Connect(function()
				added += 1
			end)
		)
		table.insert(
			connections,
			game.DescendantRemoving:Connect(function()
				removed += 1
			end)
		)
		if RunService:IsClient() then
			local protocol = require(ReplicatedStorage.Shared.match.PlayableMatchProtocol)
			local allow = { [protocol.ENDPOINTS.REPLICATION] = true, [protocol.ENDPOINTS.ATTACK_EVENT] = true }
			for _, remote in ReplicatedStorage:GetDescendants() do
				local endpointName = if remote.Parent then remote.Parent.Name else ""
				if
					(remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent"))
					and remote.Name == "Event"
					and allow[endpointName]
				then
					local row = {
						count = 0,
						estimatedBytes = 0,
						maximumBytes = 0,
						unmeasurable = 0,
						transport = remote.ClassName,
					}
					networks[endpointName] = row
					table.insert(
						connections,
						(remote :: RemoteEvent).OnClientEvent:Connect(function(payload)
							row.count += 1
							local size = Window.payloadEstimate(payload)
							if size then
								row.estimatedBytes += size
								row.maximumBytes = math.max(row.maximumBytes, size)
							else
								row.unmeasurable += 1
							end
						end)
					)
				end
			end
		end
		while os.clock() - started < duration do
			task.wait(1)
			table.insert(samples, readStats())
		end
	end)
	local remaining = 0
	for _, connection in connections do
		pcall(function()
			connection:Disconnect()
		end)
		remaining += if connection.Connected then 1 else 0
	end
	assert(remaining == 0, "probe listener cleanup failed")
	assert(ok, failure)
	return {
		evidence = "Studio-emulated",
		role = role,
		context = if RunService:IsClient() then "Client" else "Server",
		durationSeconds = os.clock() - started,
		frameMs = frame:summary(),
		before = before,
		after = readStats(),
		secondSamples = samples,
		network = networks,
		instancesAdded = added,
		instancesRemoved = removed,
		probeConnectionsAfter = remaining,
		payloadUnit = "JSON-like estimate including field names; not wire bytes",
		guiPhaseMeaning = "Client GUI observation only; boss panel may warn of an upcoming wave, health visibility indicates a displayed boss summary",
	}
end
