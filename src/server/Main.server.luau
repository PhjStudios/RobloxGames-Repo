local TweenService = game:GetService("TweenService")

local RED_BRICK_COUNT = 5
local BLUE_BRICK_COUNT = 4
local BRICK_SIZE = Vector3.new(4, 2, 4)
local BRICK_SPACING = 6
local BRICK_START_Y = 3
local RED_ROW_Z = 0
local BLUE_ROW_Z = 8
local JUMP_HEIGHT = 6
local RED_JUMP_INTERVAL_SECONDS = 5
local BLUE_JUMP_INTERVAL_SECONDS = 2
local JUMP_HALF_DURATION_SECONDS = 0.4

local brickFolder = Instance.new("Folder")
brickFolder.Name = "JumpingBricks"
brickFolder.Parent = workspace

local function createBrickRow(count: number, namePrefix: string, color: Color3, rowZ: number): { BasePart }
	local bricks = {}

	for index = 1, count do
		local brick = Instance.new("Part")
		brick.Name = `{namePrefix}{index}`
		brick.Anchored = true
		brick.CanCollide = true
		brick.Color = color
		brick.Material = Enum.Material.Brick
		brick.Size = BRICK_SIZE

		local offsetFromCenter = index - (count + 1) / 2
		brick.Position = Vector3.new(offsetFromCenter * BRICK_SPACING, BRICK_START_Y, rowZ)
		brick.Parent = brickFolder

		table.insert(bricks, brick)
	end

	return bricks
end

local redBricks = createBrickRow(RED_BRICK_COUNT, "Brick", Color3.fromRGB(196, 40, 28), RED_ROW_Z)
local blueBricks = createBrickRow(BLUE_BRICK_COUNT, "BlueBrick", Color3.fromRGB(13, 105, 172), BLUE_ROW_Z)

local jumpTweenInfo = TweenInfo.new(JUMP_HALF_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local fallTweenInfo = TweenInfo.new(JUMP_HALF_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function playTweens(tweens: { Tween })
	for _, tween in tweens do
		tween:Play()
	end

	task.wait(JUMP_HALF_DURATION_SECONDS)
end

local function jumpBricks(bricks: { BasePart })
	local fallTweens = {}
	local jumpTweens = {}

	for _, brick in bricks do
		local startingPosition = brick.Position
		table.insert(
			jumpTweens,
			TweenService:Create(brick, jumpTweenInfo, {
				Position = startingPosition + Vector3.new(0, JUMP_HEIGHT, 0),
			})
		)
		table.insert(
			fallTweens,
			TweenService:Create(brick, fallTweenInfo, {
				Position = startingPosition,
			})
		)
	end

	playTweens(jumpTweens)
	playTweens(fallTweens)
end

local function runJumpLoop(bricks: { BasePart }, intervalSeconds: number)
	task.wait(intervalSeconds)

	while true do
		local jumpStartedAt = os.clock()
		jumpBricks(bricks)

		local elapsed = os.clock() - jumpStartedAt
		task.wait(math.max(0, intervalSeconds - elapsed))
	end
end

task.spawn(runJumpLoop, redBricks, RED_JUMP_INTERVAL_SECONDS)
runJumpLoop(blueBricks, BLUE_JUMP_INTERVAL_SECONDS)
