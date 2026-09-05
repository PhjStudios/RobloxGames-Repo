--!strict

-- Client-only screen cursor. It never decides placement legality or sends requests.
local PlacementCursor = {}

function PlacementCursor.step(position: Vector2?, viewport: Vector2, axis: Vector2, deltaSeconds: number): Vector2
	local width = math.clamp(viewport.X, 240, 16384)
	local height = math.clamp(viewport.Y, 240, 16384)
	local current = position or Vector2.new(width * 0.5, height * 0.5)
	if axis.X ~= axis.X or axis.Y ~= axis.Y or deltaSeconds ~= deltaSeconds then
		return Vector2.new(math.clamp(current.X, 20, width - 20), math.clamp(current.Y, 20, height - 20))
	end
	local direction = Vector2.new(math.clamp(axis.X, -1, 1), math.clamp(axis.Y, -1, 1))
	if direction.Magnitude > 1 then
		direction = direction.Unit
	end
	local nextPosition = current + direction * math.min(width, height) * 0.6 * math.clamp(deltaSeconds, 0, 0.1)
	return Vector2.new(math.clamp(nextPosition.X, 20, width - 20), math.clamp(nextPosition.Y, 20, height - 20))
end

return table.freeze(PlacementCursor)
