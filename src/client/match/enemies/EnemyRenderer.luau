--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EnemyProtocol = require(ReplicatedStorage.Shared.match.EnemyProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local EnemyPresentation = require(script.Parent.EnemyPresentation)

export type ErrorCode =
	"INVALID_CONTEXT"
	| "INVALID_PARENT"
	| "INVALID_SNAPSHOT"
	| "INVALID_TIME"
	| "RENDER_FAILED"
	| "CLEANED_UP"

export type Error = {
	code: ErrorCode,
}

export type Snapshot = {
	locked: boolean,
	matchId: string?,
	enemyEpoch: number?,
	entries: { EnemyProtocol.EnemyStateEntry },
}

export type Metrics = {
	visualCount: number,
	renderPassCount: number,
	recreationCount: number,
	lastPassMaximumCorrectionError: number,
	maximumCorrectionError: number,
	maximumPivotResidual: number,
}

export type Renderer = {
	render: (self: Renderer, snapshot: Snapshot, serverTime: unknown) -> Result.Result<Metrics, Error>,
	getMetrics: (self: Renderer) -> Result.Result<Metrics, Error>,
	reset: (self: Renderer) -> Result.Result<boolean, Error>,
	cleanup: (self: Renderer) -> Result.Result<boolean, Error>,
}

export type TestConstructor = (parent: Instance) -> Result.Result<Renderer, Error>

type Visual = {
	model: Model,
	head: Part,
	thorax: Part,
	abdomen: Part,
}

type Track = {
	previous: EnemyProtocol.EnemyStateEntry?,
	current: EnemyProtocol.EnemyStateEntry,
	displayed: CFrame?,
	correctionOffset: Vector3,
	correctionStartedAt: number?,
}

type RendererData = {
	parent: Instance,
	material: Enum.Material?,
	pivotModel: (Model, CFrame) -> (),
	getModelPivot: (Model) -> CFrame,
	root: Folder?,
	visualsById: { [number]: Visual },
	tracksById: { [number]: Track },
	matchId: string?,
	enemyEpoch: number?,
	cleaned: boolean,
	renderPassCount: number,
	recreationCount: number,
	lastPassMaximumCorrectionError: number,
	maximumCorrectionError: number,
	maximumPivotResidual: number,
}

local ROOT_NAME = "ATDEnemyVisuals"
local MODEL_PREFIX = "EnemyVisual"
local PART_NAMES = table.freeze({ "Head", "Thorax", "Abdomen" })
local PART_SIZES = table.freeze({
	Head = Vector3.new(1, 1, 1),
	Thorax = Vector3.new(0.85, 0.7, 0.8),
	Abdomen = Vector3.new(1.05, 0.75, 0.95),
})
local PART_OFFSETS = table.freeze({
	Head = CFrame.new(0, 0.05, -0.68),
	Thorax = CFrame.identity,
	Abdomen = CFrame.new(0, -0.02, 0.84),
})
local PROPERTY_TOLERANCE = 1e-5

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_CONTEXT = table.freeze({ code = "INVALID_CONTEXT" :: "INVALID_CONTEXT" }),
	INVALID_PARENT = table.freeze({ code = "INVALID_PARENT" :: "INVALID_PARENT" }),
	INVALID_SNAPSHOT = table.freeze({ code = "INVALID_SNAPSHOT" :: "INVALID_SNAPSHOT" }),
	INVALID_TIME = table.freeze({ code = "INVALID_TIME" :: "INVALID_TIME" }),
	RENDER_FAILED = table.freeze({ code = "RENDER_FAILED" :: "RENDER_FAILED" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local RendererMethods = {}
RendererMethods.__index = RendererMethods

local RENDERER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: RendererData }

local EnemyRenderer = {
	ROOT_NAME = ROOT_NAME,
	MODEL_PREFIX = MODEL_PREFIX,
	PART_NAMES = PART_NAMES,
	MAX_VISUALS = EnemyProtocol.MAX_ACTIVE_ENEMIES,
	newForTests = nil :: TestConstructor?,
}

local function failure(code: ErrorCode)
	return Result.err(ERRORS[code])
end

local function requireData(value: unknown): RendererData
	if type(value) ~= "table" then
		error("[ATD_ENEMY_RENDERER][code=INVALID_CONTEXT]", 0)
	end
	local data = RENDERER_DATA[value :: any]
	if data == nil then
		error("[ATD_ENEMY_RENDERER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function modelName(runtimeEnemyId: number): string
	return `{MODEL_PREFIX}{string.format("%04d", runtimeEnemyId)}`
end

local function metrics(data: RendererData): Metrics
	local visualCount = 0
	for _ in data.visualsById do
		visualCount += 1
	end
	return table.freeze({
		visualCount = visualCount,
		renderPassCount = data.renderPassCount,
		recreationCount = data.recreationCount,
		lastPassMaximumCorrectionError = data.lastPassMaximumCorrectionError,
		maximumCorrectionError = data.maximumCorrectionError,
		maximumPivotResidual = data.maximumPivotResidual,
	})
end

local function destroyVisual(visual: Visual)
	pcall(function()
		visual.model:Destroy()
	end)
end

local function clearOwned(data: RendererData)
	for runtimeEnemyId, visual in data.visualsById do
		destroyVisual(visual)
		data.visualsById[runtimeEnemyId] = nil
	end
	table.clear(data.tracksById)
	local root = data.root
	data.root = nil
	if root ~= nil then
		pcall(function()
			(root :: Folder):Destroy()
		end)
	end
end

local function resetData(data: RendererData)
	clearOwned(data)
	data.matchId = nil
	data.enemyEpoch = nil
	data.renderPassCount = 0
	data.recreationCount = 0
	data.lastPassMaximumCorrectionError = 0
	data.maximumCorrectionError = 0
	data.maximumPivotResidual = 0
end

local function ensureRoot(data: RendererData): Folder
	local root = data.root
	local rootValid = false
	if root ~= nil then
		local checked, valid = pcall(function(): boolean
			return (root :: Folder).Parent == data.parent and (root :: Folder).Name == ROOT_NAME
		end)
		rootValid = checked and valid
	end
	if root ~= nil and not rootValid then
		clearOwned(data)
		root = nil
	end
	if root == nil then
		root = Instance.new("Folder")
		root.Name = ROOT_NAME
		root.Parent = data.parent
		data.root = root
	end
	return root
end

local function configurePart(data: RendererData, name: "Head" | "Thorax" | "Abdomen"): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = PART_SIZES[name]
	if data.material ~= nil then
		part.Material = data.material
	end
	part.Transparency = 0
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.CFrame = PART_OFFSETS[name]
	return part
end

local function createVisual(data: RendererData, runtimeEnemyId: number, root: Folder): Visual
	local model = Instance.new("Model")
	model.Name = modelName(runtimeEnemyId)
	local head = configurePart(data, "Head")
	local thorax = configurePart(data, "Thorax")
	local abdomen = configurePart(data, "Abdomen")
	head.Parent = model
	thorax.Parent = model
	abdomen.Parent = model
	model.PrimaryPart = thorax
	model.Parent = root
	local visual = {
		model = model,
		head = head,
		thorax = thorax,
		abdomen = abdomen,
	}
	data.visualsById[runtimeEnemyId] = visual
	data.recreationCount += 1
	return visual
end

local function closeNumber(left: number, right: number): boolean
	return math.abs(left - right) <= PROPERTY_TOLERANCE
end

local function closeVector(left: Vector3, right: Vector3): boolean
	return (left - right).Magnitude <= PROPERTY_TOLERANCE
end

local function validPart(
	part: Part,
	name: "Head" | "Thorax" | "Abdomen",
	model: Model,
	material: Enum.Material?
): boolean
	return part.Parent == model
		and part.Name == name
		and part:IsA("Part")
		and closeVector(part.Size, PART_SIZES[name])
		and (material == nil or part.Material == material)
		and closeNumber(part.Transparency, 0)
		and part.Anchored
		and not part.CanCollide
		and not part.CanTouch
		and not part.CanQuery
		and not part.CastShadow
		and part.Massless
end

local function validRelativeCFrame(part: Part, thorax: Part, expected: CFrame): boolean
	local actual = thorax.CFrame:ToObjectSpace(part.CFrame)
	return (actual.Position - expected.Position).Magnitude <= PROPERTY_TOLERANCE
		and actual.LookVector:Dot(expected.LookVector) >= 1 - PROPERTY_TOLERANCE
		and actual.UpVector:Dot(expected.UpVector) >= 1 - PROPERTY_TOLERANCE
end

local function validVisual(data: RendererData, visual: Visual, runtimeEnemyId: number, root: Folder): boolean
	local model = visual.model
	if
		model.Parent ~= root
		or model.Name ~= modelName(runtimeEnemyId)
		or model.PrimaryPart ~= visual.thorax
		or #model:GetChildren() ~= 3
	then
		return false
	end
	if
		not validPart(visual.head, "Head", model, data.material)
		or not validPart(visual.thorax, "Thorax", model, data.material)
		or not validPart(visual.abdomen, "Abdomen", model, data.material)
	then
		return false
	end
	return validRelativeCFrame(visual.head, visual.thorax, PART_OFFSETS.Head)
		and validRelativeCFrame(visual.abdomen, visual.thorax, PART_OFFSETS.Abdomen)
end

local function ensureVisual(data: RendererData, runtimeEnemyId: number, root: Folder): Visual
	local visual = data.visualsById[runtimeEnemyId]
	local validationSucceeded = true
	local isValid = false
	if visual ~= nil then
		validationSucceeded, isValid = pcall(validVisual, data, visual, runtimeEnemyId, root)
	end
	if visual ~= nil and (not validationSucceeded or not isValid) then
		destroyVisual(visual)
		data.visualsById[runtimeEnemyId] = nil
		visual = nil
	end
	return visual or createVisual(data, runtimeEnemyId, root)
end

local function validateSnapshot(value: unknown): Snapshot?
	if type(value) ~= "table" or not table.isfrozen(value :: any) then
		return nil
	end
	local snapshot = value :: any
	if
		type(snapshot.locked) ~= "boolean"
		or type(snapshot.entries) ~= "table"
		or not table.isfrozen(snapshot.entries)
	then
		return nil
	end
	if snapshot.locked then
		if
			type(snapshot.matchId) ~= "string"
			or type(snapshot.enemyEpoch) ~= "number"
			or not Validation.isSafeInteger(snapshot.enemyEpoch)
			or snapshot.enemyEpoch < 1
		then
			return nil
		end
	elseif snapshot.matchId ~= nil or snapshot.enemyEpoch ~= nil or #snapshot.entries ~= 0 then
		return nil
	end
	if #snapshot.entries > EnemyProtocol.MAX_ACTIVE_ENEMIES then
		return nil
	end
	local previousId = 0
	local entryCount = 0
	for index, entry in snapshot.entries do
		entryCount += 1
		if index ~= entryCount then
			return nil
		end
		if
			type(entry) ~= "table"
			or not table.isfrozen(entry)
			or getmetatable(entry) ~= nil
			or type(entry.runtimeEnemyId) ~= "number"
			or not Validation.isSafeInteger(entry.runtimeEnemyId)
			or entry.runtimeEnemyId < 1
			or entry.runtimeEnemyId > EnemyProtocol.MAX_RUNTIME_ENEMY_ID
			or type(entry.revision) ~= "number"
			or not Validation.isSafeInteger(entry.revision)
			or entry.revision < 1
			or entry.runtimeEnemyId <= previousId
		then
			return nil
		end
		previousId = entry.runtimeEnemyId
	end
	if entryCount ~= #snapshot.entries then
		return nil
	end
	return snapshot :: Snapshot
end

local function composePosition(target: CFrame, offset: Vector3): CFrame
	return CFrame.new(target.Position + offset) * target.Rotation
end

local function updateTrack(
	data: RendererData,
	track: Track?,
	entry: EnemyProtocol.EnemyStateEntry,
	serverTime: number
): (Track, number)
	if track == nil then
		return {
			previous = nil,
			current = entry,
			displayed = nil,
			correctionOffset = Vector3.zero,
			correctionStartedAt = nil,
		},
			0
	end
	if entry.revision == track.current.revision then
		return track, 0
	end
	if entry.revision < track.current.revision then
		return track, 0
	end

	track.previous = track.current
	track.current = entry
	track.correctionOffset = Vector3.zero
	track.correctionStartedAt = nil
	if track.displayed == nil then
		return track, 0
	end
	local sampleResult = EnemyPresentation.sample(track.previous, track.current, serverTime)
	if not sampleResult.ok or sampleResult.value.snapped or sampleResult.value.segmentGap then
		return track, 0
	end
	local correctionResult = EnemyPresentation.classifyCorrection(
		(track.displayed :: CFrame).Position,
		sampleResult.value.worldCFrame.Position
	)
	if not correctionResult.ok then
		return track, 0
	end
	local correction = correctionResult.value
	if correction.mode == "Smooth" then
		track.correctionOffset = correction.offset
		track.correctionStartedAt = serverTime
	end
	data.maximumCorrectionError = math.max(data.maximumCorrectionError, correction.errorStuds)
	return track, correction.errorStuds
end

local function renderTrack(track: Track, serverTime: number): CFrame?
	local sampleResult = EnemyPresentation.sample(track.previous, track.current, serverTime)
	if not sampleResult.ok then
		return nil
	end
	local target = sampleResult.value.worldCFrame
	local correctionStartedAt = track.correctionStartedAt
	if correctionStartedAt == nil then
		track.correctionOffset = Vector3.zero
		return target
	end
	local elapsed = serverTime - correctionStartedAt
	if elapsed < 0 then
		return nil
	end
	local remaining = 1 - math.clamp(elapsed / EnemyPresentation.SMOOTH_CORRECTION_SECONDS, 0, 1)
	if remaining <= 0 then
		track.correctionOffset = Vector3.zero
		track.correctionStartedAt = nil
		return target
	end
	return composePosition(target, track.correctionOffset * remaining)
end

function RendererMethods.render(
	self: Renderer,
	snapshotValue: Snapshot,
	serverTimeValue: unknown
): Result.Result<Metrics, Error>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local snapshot = validateSnapshot(snapshotValue)
	if snapshot == nil then
		return failure("INVALID_SNAPSHOT")
	end
	if type(serverTimeValue) ~= "number" or not Validation.isFiniteNumber(serverTimeValue) or serverTimeValue < 0 then
		return failure("INVALID_TIME")
	end
	local serverTime = serverTimeValue :: number

	if not snapshot.locked then
		if data.matchId ~= nil or data.root ~= nil then
			resetData(data)
		end
		return Result.ok(metrics(data))
	end
	if data.matchId ~= snapshot.matchId or data.enemyEpoch ~= snapshot.enemyEpoch then
		resetData(data)
		data.matchId = snapshot.matchId
		data.enemyEpoch = snapshot.enemyEpoch
	end

	local activeIds: { [number]: boolean } = {}
	data.lastPassMaximumCorrectionError = 0
	local root = if #snapshot.entries > 0 then ensureRoot(data) else data.root
	for _, entry in snapshot.entries do
		local runtimeEnemyId = entry.runtimeEnemyId
		activeIds[runtimeEnemyId] = true
		local existingTrack = data.tracksById[runtimeEnemyId]
		if existingTrack == nil or entry.revision ~= existingTrack.current.revision then
			local validated = EnemyProtocol.validateEnemyStateEntry(entry)
			if not validated.ok then
				return failure("INVALID_SNAPSHOT")
			end
		end
		local track, correctionError = updateTrack(data, existingTrack, entry, serverTime)
		data.tracksById[runtimeEnemyId] = track
		data.lastPassMaximumCorrectionError = math.max(data.lastPassMaximumCorrectionError, correctionError)
		local target = renderTrack(track, serverTime)
		if target == nil or root == nil then
			return failure("RENDER_FAILED")
		end
		local visual = ensureVisual(data, runtimeEnemyId, root)
		local moved = pcall(function()
			data.pivotModel(visual.model, target :: CFrame)
		end)
		if not moved then
			return failure("RENDER_FAILED")
		end
		track.displayed = target
		local readSucceeded, actualPivot = pcall(data.getModelPivot, visual.model)
		if not readSucceeded or typeof(actualPivot) ~= "CFrame" then
			return failure("RENDER_FAILED")
		end
		local residual = ((actualPivot :: CFrame).Position - target.Position).Magnitude
		data.maximumPivotResidual = math.max(data.maximumPivotResidual, residual)
	end

	for runtimeEnemyId, visual in data.visualsById do
		if activeIds[runtimeEnemyId] ~= true then
			destroyVisual(visual)
			data.visualsById[runtimeEnemyId] = nil
			data.tracksById[runtimeEnemyId] = nil
		end
	end
	for runtimeEnemyId in data.tracksById do
		if activeIds[runtimeEnemyId] ~= true then
			data.tracksById[runtimeEnemyId] = nil
		end
	end

	data.renderPassCount += 1
	return Result.ok(metrics(data))
end

function RendererMethods.getMetrics(self: Renderer): Result.Result<Metrics, Error>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	return Result.ok(metrics(data))
end

function RendererMethods.reset(self: Renderer): Result.Result<boolean, Error>
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	resetData(data)
	return Result.ok(true)
end

function RendererMethods.cleanup(self: Renderer): Result.Result<boolean, Error>
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(true)
	end
	resetData(data)
	data.cleaned = true
	return Result.ok(true)
end

local function construct(
	parent: Instance,
	material: Enum.Material?,
	pivotModel: (Model, CFrame) -> (),
	getModelPivot: (Model) -> CFrame
): Result.Result<Renderer, Error>
	if typeof(parent) ~= "Instance" then
		return failure("INVALID_PARENT")
	end
	local renderer = setmetatable({}, RendererMethods) :: any
	table.freeze(renderer)
	RENDERER_DATA[renderer] = {
		parent = parent,
		material = material,
		pivotModel = pivotModel,
		getModelPivot = getModelPivot,
		root = nil,
		visualsById = {},
		tracksById = {},
		matchId = nil,
		enemyEpoch = nil,
		cleaned = false,
		renderPassCount = 0,
		recreationCount = 0,
		lastPassMaximumCorrectionError = 0,
		maximumCorrectionError = 0,
		maximumPivotResidual = 0,
	}
	return Result.ok(renderer :: Renderer)
end

function EnemyRenderer.new(): Result.Result<Renderer, Error>
	return construct(
		game:GetService("Workspace"),
		Enum.Material.SmoothPlastic,
		function(model: Model, worldCFrame: CFrame)
			model:PivotTo(worldCFrame)
		end,
		function(model: Model): CFrame
			return model:GetPivot()
		end
	)
end

local function isExactTestModule(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "EnemyRenderer" then
		return false
	end
	local container = script.Parent
	if container == nil or not container:IsA("Folder") or container.Name ~= "ProductionClientEnemies" then
		return false
	end
	local automatedTests = container.Parent
	return automatedTests ~= nil
		and automatedTests:IsA("Folder")
		and automatedTests.Name == "AutomatedTests"
		and automatedTests.Parent == ServerStorage
end

if isExactTestModule() then
	EnemyRenderer.newForTests = function(parent: Instance): Result.Result<Renderer, Error>
		return construct(parent, nil, function(model: Model, worldCFrame: CFrame)
			local primaryPart = model.PrimaryPart
			if primaryPart == nil then
				error("[ATD_ENEMY_RENDERER_TEST_ADAPTER][code=PRIMARY_PART_MISSING]", 0)
			end
			local relativeByPart: { [Part]: CFrame } = {}
			for _, child in model:GetChildren() do
				if child:IsA("Part") then
					relativeByPart[child] = (primaryPart :: Part).CFrame:ToObjectSpace(child.CFrame)
				end
			end
			for part, relative in relativeByPart do
				part.CFrame = worldCFrame * relative
			end
		end, function(model: Model): CFrame
			local primaryPart = model.PrimaryPart
			if primaryPart == nil then
				error("[ATD_ENEMY_RENDERER_TEST_ADAPTER][code=PRIMARY_PART_MISSING]", 0)
			end
			return (primaryPart :: Part).CFrame
		end)
	end
end

table.freeze(RendererMethods)
return table.freeze(EnemyRenderer)
