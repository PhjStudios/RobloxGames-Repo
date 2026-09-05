--!strict

-- A visual-only angle reducer. It never selects a gameplay target or schedules
-- an attack. A lost/late target simply lets the model return to its saved yaw.
export type State = { yaw: number, idleYaw: number, targetYaw: number?, targetUntil: number }
local TowerAim = { TARGET_HOLD_SECONDS = 0.65, RESPONSE = 14 }

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < 1e12
end

local function wrap(value: number): number
	return (value + math.pi) % (2 * math.pi) - math.pi
end

function TowerAim.new(idleYaw: number): State
	local yaw = if finite(idleYaw) then wrap(idleYaw) else 0
	return { yaw = yaw, idleYaw = yaw, targetYaw = nil, targetUntil = 0 }
end

function TowerAim.setIdle(state: State, yaw: number)
	if finite(yaw) then
		state.idleYaw = wrap(yaw)
	end
end

function TowerAim.observe(state: State, origin: Vector3, target: Vector3, now: number): boolean
	if typeof(origin) ~= "Vector3" or typeof(target) ~= "Vector3" or not finite(now) then
		return false
	end
	local delta = target - origin
	if not finite(delta.X) or not finite(delta.Z) or delta.X * delta.X + delta.Z * delta.Z < 0.0001 then
		return false
	end
	state.targetYaw = math.atan2(-delta.X, -delta.Z)
	state.targetUntil = now + TowerAim.TARGET_HOLD_SECONDS
	return true
end

function TowerAim.step(state: State, now: number, deltaSeconds: number, reducedMotion: boolean): number
	if not finite(now) or not finite(deltaSeconds) or deltaSeconds < 0 then
		return state.yaw
	end
	if reducedMotion then
		state.targetYaw = nil
		state.targetUntil = 0
		state.yaw = state.idleYaw
		return state.yaw
	end
	if now >= state.targetUntil then
		state.targetYaw = nil
	end
	local target = state.targetYaw or state.idleYaw
	local alpha = 1 - math.exp(-TowerAim.RESPONSE * math.min(deltaSeconds, 0.1))
	state.yaw = wrap(state.yaw + wrap(target - state.yaw) * alpha)
	return state.yaw
end

return table.freeze(TowerAim)
