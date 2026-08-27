--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local EnemyRenderer = require(script.Parent.Parent.ProductionClientEnemies.EnemyRenderer)

local Shared = game:GetService("ReplicatedStorage").Shared
local EnemyProtocol = require(Shared.match.EnemyProtocol)

type Assertions = TestHarness.Assertions
type Renderer = EnemyRenderer.Renderer

local newForTests = EnemyRenderer.newForTests
if newForTests == nil then
	error("[ATD_TEST_FIXTURE][code=ENEMY_RENDERER_TEST_CONSTRUCTOR_MISSING]", 0)
end

local function canonicalCFrame(position: Vector3): CFrame
	local direction = Vector3.xAxis
	local right = direction:Cross(Vector3.yAxis).Unit
	local up = right:Cross(direction).Unit
	return CFrame.fromMatrix(position, right, up, -direction)
end

local function entry(runtimeEnemyId: number, revision: number, progress: number, sampleTime: number, speed: number?)
	local startPosition = Vector3.zero
	local endPosition = Vector3.new(100, 0, 0)
	local position = startPosition:Lerp(endPosition, progress / 100)
	local result = EnemyProtocol.validateEnemyStateEntry({
		runtimeEnemyId = runtimeEnemyId,
		enemyId = "enemy:phase09-test",
		laneId = "lane:straight",
		revision = revision,
		lifecycle = "Active",
		pathProgress = progress,
		currentHealth = 100,
		maximumHealth = 100,
		slowMultiplier = 1,
		spawnServerTime = 1,
		sampleServerTime = sampleTime,
		worldCFrame = canonicalCFrame(position),
		effectiveSpeed = speed or 0,
		segmentIndex = 1,
		segmentStartDistance = 0,
		segmentEndDistance = 100,
		segmentStartPosition = startPosition,
		segmentEndPosition = endPosition,
	})
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=ENEMY_RENDERER_ENTRY_INVALID][path={result.error.path}]`, 0)
	end
	return result.value
end

local function snapshot(matchId: string?, epoch: number?, entries: { any }): EnemyRenderer.Snapshot
	table.freeze(entries)
	return table.freeze({
		locked = matchId ~= nil,
		matchId = matchId,
		enemyEpoch = epoch,
		entries = entries,
	}) :: EnemyRenderer.Snapshot
end

local function expectRenderer(parent: Instance): Renderer
	local result = (newForTests :: EnemyRenderer.TestConstructor)(parent)
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=ENEMY_RENDERER_CREATION_FAILED][detail={result.error.code}]`, 0)
	end
	return result.value
end

local function render(renderer: Renderer, state: EnemyRenderer.Snapshot, now: number): EnemyRenderer.Metrics
	local result = renderer:render(state, now)
	if not result.ok then
		error(`[ATD_TEST_FIXTURE][code=ENEMY_RENDERER_RENDER_FAILED][detail={result.error.code}]`, 0)
	end
	return result.value
end

local function root(parent: Instance): Folder
	local candidate = parent:FindFirstChild(EnemyRenderer.ROOT_NAME)
	if candidate == nil or not candidate:IsA("Folder") then
		error("[ATD_TEST_FIXTURE][code=ENEMY_RENDERER_ROOT_MISSING]", 0)
	end
	return candidate
end

local function model(parent: Instance, runtimeEnemyId: number): Model
	local candidate = root(parent):FindFirstChild(`{EnemyRenderer.MODEL_PREFIX}{string.format("%04d", runtimeEnemyId)}`)
	if candidate == nil or not candidate:IsA("Model") then
		error("[ATD_TEST_FIXTURE][code=ENEMY_RENDERER_MODEL_MISSING]", 0)
	end
	return candidate
end

local function modelPosition(parent: Instance, runtimeEnemyId: number): Vector3
	local primaryPart = model(parent, runtimeEnemyId).PrimaryPart
	if primaryPart == nil then
		error("[ATD_TEST_FIXTURE][code=ENEMY_RENDERER_PRIMARY_PART_MISSING]", 0)
	end
	return primaryPart.CFrame.Position
end

local function expectNear(assertions: Assertions, actual: number, expected: number, tolerance: number?)
	assertions.isTrue(math.abs(actual - expected) <= (tolerance or 1e-5))
end

local function destroy(parent: Instance, renderer: Renderer)
	renderer:cleanup()
	parent:Destroy()
end

return TestHarness.suite("programmatic enemy placeholder renderer", {
	TestHarness.case("creates one fixed non-authoritative three-Part visual per active ID", function(assertions)
		local parent = Instance.new("Folder")
		local renderer = expectRenderer(parent)
		local state = snapshot("match:renderer", 1, { entry(1, 1, 5, 10), entry(2, 1, 15, 10) })
		local metrics = render(renderer, state, 10.15)
		assertions.equal(metrics.visualCount, 2)
		assertions.equal(#root(parent):GetChildren(), 2)

		for runtimeEnemyId = 1, 2 do
			local visual = model(parent, runtimeEnemyId)
			assertions.equal(#visual:GetChildren(), 3)
			assertions.isNotNil(visual.PrimaryPart)
			for _, name in EnemyRenderer.PART_NAMES do
				local part = visual:FindFirstChild(name)
				assertions.isNotNil(part)
				if part ~= nil and part:IsA("Part") then
					assertions.isTrue(part.Anchored)
					assertions.isFalse(part.CanCollide)
					assertions.isFalse(part.CanTouch)
					assertions.isFalse(part.CanQuery)
					assertions.isFalse(part.CastShadow)
					assertions.isTrue(part.Massless)
				end
			end
		end
		destroy(parent, renderer)
	end),

	TestHarness.case(
		"smooths medium corrections for exactly the bounded window and snaps large ones",
		function(assertions)
			local parent = Instance.new("Folder")
			local renderer = expectRenderer(parent)
			render(renderer, snapshot("match:renderer", 1, { entry(1, 1, 2, 10) }), 10.15)
			expectNear(assertions, modelPosition(parent, 1).X, 2)

			local corrected = snapshot("match:renderer", 1, { entry(1, 2, 4, 10.2) })
			local started = render(renderer, corrected, 10.35)
			expectNear(assertions, modelPosition(parent, 1).X, 2)
			expectNear(assertions, started.lastPassMaximumCorrectionError, 2)
			render(renderer, corrected, 10.45)
			expectNear(assertions, modelPosition(parent, 1).X, 3)
			render(renderer, corrected, 10.55)
			expectNear(assertions, modelPosition(parent, 1).X, 4)

			local snapped = snapshot("match:renderer", 1, { entry(1, 3, 20, 10.6) })
			render(renderer, snapped, 10.75)
			expectNear(assertions, modelPosition(parent, 1).X, 20)
			destroy(parent, renderer)
		end
	),

	TestHarness.case("recreates a locally removed Part or owned root without changing identity", function(assertions)
		local parent = Instance.new("Folder")
		local renderer = expectRenderer(parent)
		local state = snapshot("match:renderer", 1, { entry(1, 1, 5, 10) })
		local first = render(renderer, state, 10.15)
		local firstModel = model(parent, 1)
		local head = firstModel:FindFirstChild("Head")
		assertions.isNotNil(head)
		if head ~= nil then
			head:Destroy()
		end
		local repaired = render(renderer, state, 10.16)
		assertions.equal(repaired.recreationCount, first.recreationCount + 1)
		assertions.notEqual(model(parent, 1), firstModel)
		assertions.equal(#model(parent, 1):GetChildren(), 3)
		local repairedModel = model(parent, 1)
		repairedModel:Destroy()
		local modelRepaired = render(renderer, state, 10.165)
		assertions.equal(modelRepaired.visualCount, 1)
		assertions.notEqual(model(parent, 1), repairedModel)
		local propertyDamagedModel = model(parent, 1)
		local thorax = propertyDamagedModel:FindFirstChild("Thorax") :: Part
		thorax.Massless = false
		render(renderer, state, 10.167)
		assertions.notEqual(model(parent, 1), propertyDamagedModel)

		local firstRoot = root(parent)
		firstRoot:Destroy()
		local rootRepaired = render(renderer, state, 10.17)
		assertions.equal(rootRepaired.visualCount, 1)
		assertions.notEqual(root(parent), firstRoot)
		destroy(parent, renderer)
	end),

	TestHarness.case("removes despawned visuals and replaces all presentation on epoch change", function(assertions)
		local parent = Instance.new("Folder")
		local renderer = expectRenderer(parent)
		local firstState = snapshot("match:renderer", 1, { entry(1, 1, 5, 10), entry(2, 1, 8, 10) })
		render(renderer, firstState, 10.15)
		local removedModel = model(parent, 1)
		local keptModel = model(parent, 2)
		local afterDespawn = render(renderer, snapshot("match:renderer", 1, { entry(2, 1, 8, 10) }), 10.16)
		assertions.equal(afterDespawn.visualCount, 1)
		assertions.isNil(removedModel.Parent)
		assertions.equal(model(parent, 2), keptModel)

		local oldRoot = root(parent)
		local replacement = render(renderer, snapshot("match:renderer", 2, { entry(1, 1, 12, 11) }), 11.15)
		assertions.equal(replacement.visualCount, 1)
		assertions.isNil(oldRoot.Parent)
		assertions.isNil(keptModel.Parent)
		destroy(parent, renderer)
	end),

	TestHarness.case("enforces the active visual bound and deterministic numeric IDs", function(assertions)
		local parent = Instance.new("Folder")
		local renderer = expectRenderer(parent)
		local entries = table.create(EnemyRenderer.MAX_VISUALS)
		for runtimeEnemyId = 1, EnemyRenderer.MAX_VISUALS do
			entries[runtimeEnemyId] = entry(runtimeEnemyId, 1, (runtimeEnemyId % 90) + 1, 10)
		end
		local full = render(renderer, snapshot("match:renderer", 1, entries), 10.15)
		assertions.equal(full.visualCount, EnemyRenderer.MAX_VISUALS)
		assertions.equal(#root(parent):GetChildren(), EnemyRenderer.MAX_VISUALS)

		local overflowEntries = table.clone(entries)
		overflowEntries[EnemyRenderer.MAX_VISUALS + 1] = entry(EnemyRenderer.MAX_VISUALS + 1, 1, 70, 10)
		local invalid = snapshot("match:renderer", 1, overflowEntries)
		assertions.isFalse(renderer:render(invalid, 10.16).ok)
		destroy(parent, renderer)
	end),

	TestHarness.case("reset and cleanup destroy exact owned presentation idempotently", function(assertions)
		local parent = Instance.new("Folder")
		local renderer = expectRenderer(parent)
		render(renderer, snapshot("match:renderer", 1, { entry(1, 1, 5, 10) }), 10.15)
		assertions.isTrue(renderer:reset().ok)
		assertions.isNil(parent:FindFirstChild(EnemyRenderer.ROOT_NAME))
		local unlocked = snapshot(nil, nil, {})
		local empty = render(renderer, unlocked, 10.2)
		assertions.equal(empty.visualCount, 0)
		assertions.isTrue(renderer:cleanup().ok)
		assertions.isTrue(renderer:cleanup().ok)
		assertions.isFalse(renderer:render(unlocked, 10.3).ok)
		assertions.isNil(parent:FindFirstChild(EnemyRenderer.ROOT_NAME))
		parent:Destroy()
	end),
})
