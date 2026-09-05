--!strict

-- Static MicroProfiler labels only. No samples, timers, counters, instance
-- references, or gameplay values are retained by this adapter.
local LABELS = table.freeze({
	["ATD.Runtime.Step"] = true,
	["ATD.Runtime.WaveStart"] = true,
	["ATD.Runtime.Spawn"] = true,
	["ATD.Runtime.Movement"] = true,
	["ATD.Runtime.TargetCandidates"] = true,
	["ATD.Runtime.TargetSelect"] = true,
	["ATD.Runtime.Attacks"] = true,
	["ATD.Runtime.WaveResolve"] = true,
	["ATD.Runtime.Snapshot"] = true,
	["ATD.Service.Step"] = true,
	["ATD.Service.SnapshotPublish"] = true,
	["ATD.Service.AttackPublish"] = true,
	["ATD.Client.UI"] = true,
	["ATD.Client.World"] = true,
	["ATD.Client.Aim"] = true,
	["ATD.Client.Effects"] = true,
	["ATD.Client.EffectCreate"] = true,
	["ATD.Client.Presentation"] = true,
})

local function create(backend: any): any
	local valid = type(backend) == "table" and getmetatable(backend) == nil
	local beginScope = if valid and type(backend.beginScope) == "function" then backend.beginScope else nil
	local endScope = if valid and type(backend.endScope) == "function" then backend.endScope else nil
	local scope = {}
	function scope.begin(label: string): boolean
		if beginScope == nil or endScope == nil or LABELS[label] ~= true then
			return false
		end
		local succeeded = pcall(beginScope, label)
		if not succeeded then
			-- Disable a failing engine adapter instead of repeatedly attempting it.
			beginScope = nil
		end
		return succeeded
	end
	function scope.finish(started: boolean)
		if started and endScope ~= nil then
			local succeeded = pcall(endScope)
			if not succeeded then
				beginScope, endScope = nil, nil
			end
		end
	end
	-- Every instrumented operation returns one result (or none). Preserve that
	-- result identity and any thrown error while ending the scope on either path.
	-- When the engine API is absent, call directly without pcall/allocation.
	function scope.call(label: string, callback: (...any) -> any, ...: any): any
		local started = scope.begin(label)
		if not started then
			return callback(...)
		end
		local succeeded, result = pcall(callback, ...)
		scope.finish(started)
		if not succeeded then
			error(result, 0)
		end
		return result
	end
	return table.freeze(scope)
end

local engine = create({ beginScope = debug.profilebegin, endScope = debug.profileend })
return table.freeze({
	begin = engine.begin,
	finish = engine.finish,
	call = engine.call,
	create = create,
	LABELS = LABELS,
})
