--!strict

-- Invoke only in an authorized Studio runtime. No captures or labels leave the
-- local tool result; every LibMP object is disposed even if analysis fails.
return function(Window: any, restore: any)
	-- LibMP exposes no state getters. The operator must record these values
	-- before capture; do not silently assume the user's profiler state.
	assert(type(restore) == "table" and getmetatable(restore) == nil, "recorded profiler restore state required")
	assert(
		type(restore.profilerEnabled) == "boolean" and type(restore.captureEnabled) == "boolean",
		"recorded toggles required"
	)
	assert(
		type(restore.frameLimit) == "number"
			and restore.frameLimit % 1 == 0
			and restore.frameLimit >= 1
			and restore.frameLimit <= 256,
		"recorded frame limit required"
	)
	local RunService = game:GetService("RunService")
	assert(RunService:IsStudio() and RunService:IsRunning(), "Studio runtime required")
	assert(game.GameId == 10764687717 and game.CreatorId == 35420107, "staging identity required")
	assert(game.CreatorType == Enum.CreatorType.Group, "staging group ownership required")
	local role = game:GetService("ReplicatedStorage"):GetAttribute("ATDPlaceRole")
	assert(
		(role == "Match" and game.PlaceId == 104415140644510) or (role == "Lobby" and game.PlaceId == 140661668701496),
		"staging place role required"
	)
	local LibMP = require("@rbx/LibMP")
	local session, iterator
	local ok, report = pcall(function()
		assert(LibMP.Control:SetFrameLimit(128), "capture frame limit unavailable")
		assert(LibMP.Control:EnableProfiler(true), "profiler unavailable")
		assert(LibMP.Control:EnableCapture(true), "capture unavailable")
		task.wait(3)
		session = LibMP.Session.OpenFromBuffer(LibMP.Control:CaptureToBufferSync())
		LibMP.Control:EnableCapture(false)
		LibMP.Control:EnableProfiler(false)
		assert(session ~= nil, "capture unavailable")
		local first, last = session:GetFrameIdMin(), session:GetFrameIdMax()
		assert(first > 0 and last >= first, "no captured frames available")
		local scale = session:FetchGlobalDesc().TickToMsCpu
		local frames = Window.new()
		for id = first, last do
			local frame = session:FetchFrameDesc(id)
			if not frame.IsPaused and not frame.IsIncomplete then
				frames:add((frame.TickEndCpu - frame.TickStartCpu) * scale)
			end
		end
		assert(frames:summary().available, "no eligible frame timings available")
		local timerIds = session:FindTimerIds(
			"ATD.*|Script_Main|render3D|render2D|physicsSteppedTotal|RunService.Heartbeat|RenderSteppedInternal|Replicator SendData*",
			false
		)
		local totals = {}
		iterator = session:CreateLogIterator()
		iterator:Configure({ TimerIds = timerIds, SkipGpuThreads = true, SkipEvents = true, EmitThreadFrameEnd = true })
		local state = iterator:GetState()
		iterator:RewindTo(first, last)
		local entries = 0
		local function add(timerId: number, start: number, finish: number)
			local value = math.max(0, finish - start) * scale
			local row = totals[timerId]
				or { name = session:FetchTimerDesc(timerId).TimerName, inclusiveCpuMs = 0, spans = 0, maximumSpanMs = 0 }
			row.inclusiveCpuMs += value
			row.spans += 1
			row.maximumSpanMs = math.max(row.maximumSpanMs, value)
			totals[timerId] = row
		end
		while iterator:Step() do
			entries += 1
			assert(entries < 2_000_000, "bounded profiler analysis exceeded")
			if state:IsThreadFrameEnd() then
				for depth = state:ThreadStackDepth() - 1, 0, -1 do
					local element = iterator:GetCurrentThreadStackElement(depth)
					if element then
						add(element:EnterTimerId(), element:EnterTimestampFrameLocal(), state:Timestamp())
					end
				end
			elseif state:IsExit() and not state:ThreadStackWasOverflowed() then
				local start
				if state:ThreadStackIsUnderflowed() then
					start = session:FetchFrameDesc(state:FrameId()).TickStartCpu
				else
					local element = iterator:GetCurrentThreadStackElement(state:ThreadStackDepth())
					start = element:EnterTimestampFrameLocal()
				end
				add(state:TimerId(), start, state:Timestamp())
			end
		end
		local scopes = {}
		for _, row in totals do
			row.meanPerCapturedFrameMs = row.inclusiveCpuMs / math.max(1, last - first + 1)
			table.insert(scopes, row)
		end
		table.sort(scopes, function(a, b)
			return a.inclusiveCpuMs > b.inclusiveCpuMs
		end)
		return {
			frameMs = frames:summary(),
			first = { id = first, absoluteId = session:FetchFrameDesc(first).FrameAbsoluteId },
			last = { id = last, absoluteId = session:FetchFrameDesc(last).FrameAbsoluteId },
			scopes = scopes,
			meaning = "CPU inclusive work summed across threads; not GPU or critical-path time",
		}
	end)
	local cleanupSucceeded = true
	local function cleanup(callback: () -> ())
		local succeeded = pcall(callback)
		cleanupSucceeded = succeeded and cleanupSucceeded
	end
	if iterator then
		cleanup(function()
			iterator:Dispose()
		end)
	end
	if session then
		cleanup(function()
			session:Dispose()
		end)
	end
	cleanup(function()
		assert(LibMP.Control:SetFrameLimit(restore.frameLimit), "restore frame limit failed")
	end)
	cleanup(function()
		assert(LibMP.Control:EnableProfiler(restore.profilerEnabled), "restore profiler failed")
	end)
	cleanup(function()
		assert(LibMP.Control:EnableCapture(restore.captureEnabled), "restore capture failed")
	end)
	assert(cleanupSucceeded, "profiler cleanup or state restoration failed")
	assert(ok, report)
	report.restored = table.clone(restore)
	return report
end
