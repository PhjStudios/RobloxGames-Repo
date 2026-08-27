--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Log = require(ReplicatedStorage.Shared.logging.Log)
local Cleanup = require(ReplicatedStorage.Shared.util.Cleanup)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

local MapContract = require(script.Parent.MapContract)
local MapValidator = require(script.Parent.MapValidator)

export type LoaderState = "Idle" | "Loading" | "Loaded" | "Unloading" | "Cleaned" | "Failed"

export type LoaderOperation = "load" | "getSnapshot" | "getLane" | "unload" | "cleanup"

export type LoaderErrorCode =
	"INVALID_MAP_ID"
	| "INVALID_LANE_ID"
	| "INVALID_STATE"
	| "NOT_LOADED"
	| "CATALOG_ROOT_MISSING"
	| "CATALOG_ROOT_CONFLICT"
	| "CATALOG_LIMIT_EXCEEDED"
	| "TEMPLATE_NOT_FOUND"
	| "TEMPLATE_DUPLICATE"
	| "TEMPLATE_INVALID"
	| "RUNTIME_ROOT_CONFLICT"
	| "CLONE_FAILED"
	| "LANE_NOT_FOUND"
	| "CLEANUP_FAILED"
	| "ROLLBACK_FAILED"

export type LoaderError = {
	code: LoaderErrorCode,
	operation: LoaderOperation,
	state: LoaderState,
	validationReport: MapValidator.MapValidationReport?,
}

export type RoutePointKind = "EnemySpawn" | "PathNode" | "DefenderBase"

export type RoutePointSnapshot = {
	kind: RoutePointKind,
	nodeOrder: number?,
	cframe: CFrame,
	position: Vector3,
	distance: number,
}

export type RuntimeLaneSnapshot = {
	id: string,
	totalDistance: number,
	points: { RoutePointSnapshot },
}

export type RuntimeMapSnapshot = {
	mapId: Ids.MapId,
	base: MapValidator.PointSnapshot,
	bounds: {
		cframe: CFrame,
		size: Vector3,
	},
	lanes: { RuntimeLaneSnapshot },
	placementZones: { MapValidator.RegionSnapshot },
	noPlacementZones: { MapValidator.RegionSnapshot },
	cameraAnchors: { MapValidator.NamedPointSnapshot },
	playerSpawns: { MapValidator.NamedPointSnapshot },
}

type CloneTemplate = (template: Model) -> Instance?

type LoaderData = {
	logger: Log.Logger,
	state: LoaderState,
	loadCleanup: Cleanup.Container?,
	snapshot: RuntimeMapSnapshot?,
	cloneTemplate: CloneTemplate?,
}

local LoaderMethods = {}
LoaderMethods.__index = LoaderMethods

export type Loader = typeof(setmetatable({} :: {}, LoaderMethods))

local LOAD_CLEANUP_LABEL = "match-map-loader"
local LOADER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: LoaderData }

local MapLoader = {}

local function makeError(
	code: LoaderErrorCode,
	operation: LoaderOperation,
	state: LoaderState,
	validationReport: MapValidator.MapValidationReport?
): LoaderError
	if validationReport ~= nil then
		return table.freeze({
			code = code,
			operation = operation,
			state = state,
			validationReport = validationReport,
		})
	end

	return table.freeze({
		code = code,
		operation = operation,
		state = state,
	}) :: LoaderError
end

local function failure<T>(
	code: LoaderErrorCode,
	operation: LoaderOperation,
	state: LoaderState,
	validationReport: MapValidator.MapValidationReport?
): Result.Failure<LoaderError>
	return Result.err(makeError(code, operation, state, validationReport))
end

local function requireLoaderData(value: unknown): LoaderData
	if type(value) ~= "table" then
		error("[ATD_MAP_LOADER][code=INVALID_CONTEXT]", 0)
	end
	local data = LOADER_DATA[value :: any]
	if data == nil then
		error("[ATD_MAP_LOADER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function defaultCloneTemplate(template: Model): Instance?
	return template:Clone()
end

local function directNamedChildren(parent: Instance, name: string, stopAfter: number?): { Instance }
	local matches: { Instance } = {}
	for _, child in parent:GetChildren() do
		if child.Name == name then
			table.insert(matches, child)
			if stopAfter ~= nil and #matches >= stopAfter then
				break
			end
		end
	end
	return matches
end

local function resolveCatalogRoot(): (Folder?, LoaderErrorCode?)
	local roots = directNamedChildren(ServerStorage, MapContract.TRUSTED_CATALOG_NAME, 2)
	if #roots == 0 then
		return nil, "CATALOG_ROOT_MISSING"
	elseif #roots > 1 or not roots[1]:IsA("Folder") then
		return nil, "CATALOG_ROOT_CONFLICT"
	end
	return roots[1] :: Folder, nil
end

local function selectTemplate(catalogRoot: Folder, mapId: Ids.MapId): (Model?, LoaderErrorCode?)
	local children = catalogRoot:GetChildren()
	if #children > MapContract.Limits.MAX_CATALOG_TEMPLATES then
		return nil, "CATALOG_LIMIT_EXCEEDED"
	end

	local malformed = false
	local matches: { Model } = {}
	for _, child in children do
		if not child:IsA("Model") then
			malformed = true
			continue
		end

		local attributeValue = child:GetAttribute(MapContract.Attributes.MapId)
		local attributeResult = Ids.validateMapId(attributeValue)
		if not attributeResult.ok then
			malformed = true
		elseif attributeResult.value == mapId then
			table.insert(matches, child :: Model)
		end
	end

	if #matches > 1 then
		return nil, "TEMPLATE_DUPLICATE"
	elseif malformed then
		return nil, "TEMPLATE_INVALID"
	elseif #matches == 0 then
		return nil, "TEMPLATE_NOT_FOUND"
	end
	return matches[1], nil
end

local function runtimeRootConflicts(): boolean
	return #directNamedChildren(Workspace, MapContract.RUNTIME_ROOT_NAME, 1) > 0
end

local function ownsUniqueRuntimeRoot(staged: Model): boolean
	local roots = directNamedChildren(Workspace, MapContract.RUNTIME_ROOT_NAME, 2)
	return #roots == 1 and roots[1] == staged
end

local function validateCandidate(
	candidate: Model,
	mapId: Ids.MapId
): (MapValidator.ValidatedMapSnapshot?, MapValidator.MapValidationReport?)
	local callSucceeded, rawResult = pcall(MapValidator.validate, candidate, mapId)
	if not callSucceeded then
		return nil, nil
	end

	local validationResult =
		rawResult :: Result.Result<MapValidator.ValidatedMapSnapshot, MapValidator.MapValidationReport>
	if not validationResult.ok then
		return nil, validationResult.error
	end
	return validationResult.value, nil
end

local function routePoint(
	kind: RoutePointKind,
	nodeOrder: number?,
	cframe: CFrame,
	position: Vector3,
	distance: number
): RoutePointSnapshot
	if nodeOrder ~= nil then
		return table.freeze({
			kind = kind,
			nodeOrder = nodeOrder,
			cframe = cframe,
			position = position,
			distance = distance,
		})
	end

	return table.freeze({
		kind = kind,
		cframe = cframe,
		position = position,
		distance = distance,
	}) :: RoutePointSnapshot
end

local function deriveSnapshot(validated: MapValidator.ValidatedMapSnapshot): RuntimeMapSnapshot?
	local lanes: { RuntimeLaneSnapshot } = table.create(#validated.lanes)
	for _, lane in validated.lanes do
		local points: { RoutePointSnapshot } = table.create(#lane.nodes + 2)
		local previousPosition = lane.spawn.position
		local cumulativeDistance = 0
		table.insert(points, routePoint("EnemySpawn", nil, lane.spawn.cframe, lane.spawn.position, cumulativeDistance))

		for _, node in lane.nodes do
			local segmentDistance = (node.position - previousPosition).Magnitude
			if not Validation.isFiniteNumber(segmentDistance) then
				return nil
			end
			cumulativeDistance += segmentDistance
			if not Validation.isFiniteNumber(cumulativeDistance) then
				return nil
			end
			table.insert(points, routePoint("PathNode", node.order, node.cframe, node.position, cumulativeDistance))
			previousPosition = node.position
		end

		local finalSegmentDistance = (validated.base.position - previousPosition).Magnitude
		if not Validation.isFiniteNumber(finalSegmentDistance) then
			return nil
		end
		cumulativeDistance += finalSegmentDistance
		if not Validation.isFiniteNumber(cumulativeDistance) then
			return nil
		end
		table.insert(
			points,
			routePoint("DefenderBase", nil, validated.base.cframe, validated.base.position, cumulativeDistance)
		)

		table.insert(
			lanes,
			table.freeze({
				id = lane.id,
				totalDistance = cumulativeDistance,
				points = table.freeze(points),
			})
		)
	end

	return table.freeze({
		mapId = validated.mapId,
		base = validated.base,
		bounds = validated.bounds,
		lanes = table.freeze(lanes),
		placementZones = validated.placementZones,
		noPlacementZones = validated.noPlacementZones,
		cameraAnchors = validated.cameraAnchors,
		playerSpawns = validated.playerSpawns,
	})
end

local function releaseOwnedLoad(data: LoaderData): boolean
	local loadCleanup = data.loadCleanup
	data.snapshot = nil
	data.loadCleanup = nil
	if loadCleanup == nil then
		return true
	end
	return pcall(function()
		loadCleanup:cleanup()
	end)
end

local function rollbackLoad(
	data: LoaderData,
	code: LoaderErrorCode,
	validationReport: MapValidator.MapValidationReport?
): Result.Failure<LoaderError>
	if not releaseOwnedLoad(data) then
		data.state = "Failed"
		data.cloneTemplate = nil
		return failure("ROLLBACK_FAILED", "load", data.state, nil)
	end
	data.state = "Idle"
	return failure(code, "load", data.state, validationReport)
end

local function failLoadWithoutResources(
	data: LoaderData,
	code: LoaderErrorCode,
	validationReport: MapValidator.MapValidationReport?
): Result.Failure<LoaderError>
	data.snapshot = nil
	data.loadCleanup = nil
	data.state = "Idle"
	return failure(code, "load", data.state, validationReport)
end

function LoaderMethods.load(self: Loader, mapIdValue: unknown): Result.Result<RuntimeMapSnapshot, LoaderError>
	local data = requireLoaderData(self)
	if data.state ~= "Idle" then
		return failure("INVALID_STATE", "load", data.state, nil)
	end

	local mapIdResult = Ids.validateMapId(mapIdValue)
	if not mapIdResult.ok then
		return failure("INVALID_MAP_ID", "load", data.state, nil)
	end
	local mapId = mapIdResult.value
	data.state = "Loading"

	local catalogRoot, catalogError = resolveCatalogRoot()
	if catalogRoot == nil then
		return failLoadWithoutResources(data, catalogError :: LoaderErrorCode, nil)
	end

	local template, templateError = selectTemplate(catalogRoot, mapId)
	if template == nil then
		return failLoadWithoutResources(data, templateError :: LoaderErrorCode, nil)
	end

	local originalSnapshot, originalReport = validateCandidate(template, mapId)
	if originalSnapshot == nil then
		return failLoadWithoutResources(data, "TEMPLATE_INVALID", originalReport)
	end
	local _ = originalSnapshot

	if runtimeRootConflicts() then
		return failLoadWithoutResources(data, "RUNTIME_ROOT_CONFLICT", nil)
	end

	local loadCleanup = Cleanup.new(data.logger, LOAD_CLEANUP_LABEL)
	data.loadCleanup = loadCleanup
	local cloneTemplate = data.cloneTemplate
	if cloneTemplate == nil then
		return rollbackLoad(data, "CLONE_FAILED", nil)
	end
	local cloneSucceeded, cloneValue = pcall(cloneTemplate, template)
	if
		not cloneSucceeded
		or typeof(cloneValue) ~= "Instance"
		or cloneValue == template
		or not (cloneValue :: Instance):IsA("Model")
		or (cloneValue :: Instance).Parent ~= nil
	then
		return rollbackLoad(data, "CLONE_FAILED", nil)
	end

	local staged = cloneValue :: Model
	local ownershipSucceeded = pcall(function()
		loadCleanup:add(staged)
	end)
	if not ownershipSucceeded then
		local destroySucceeded = pcall(function()
			staged:Destroy()
		end)
		if not destroySucceeded or not releaseOwnedLoad(data) then
			data.state = "Failed"
			data.cloneTemplate = nil
			return failure("ROLLBACK_FAILED", "load", data.state, nil)
		end
		data.state = "Idle"
		return failure("CLONE_FAILED", "load", data.state, nil)
	end

	local stagedSnapshot, stagedReport = validateCandidate(staged, mapId)
	if stagedSnapshot == nil then
		return rollbackLoad(data, "TEMPLATE_INVALID", stagedReport)
	end
	local runtimeSnapshot = deriveSnapshot(stagedSnapshot)
	if runtimeSnapshot == nil then
		return rollbackLoad(data, "TEMPLATE_INVALID", nil)
	end

	local renameSucceeded = pcall(function()
		staged.Name = MapContract.RUNTIME_ROOT_NAME
	end)
	if not renameSucceeded then
		return rollbackLoad(data, "CLONE_FAILED", nil)
	end
	if runtimeRootConflicts() then
		return rollbackLoad(data, "RUNTIME_ROOT_CONFLICT", nil)
	end

	local publishSucceeded = pcall(function()
		staged.Parent = Workspace
	end)
	if not publishSucceeded or staged.Parent ~= Workspace then
		return rollbackLoad(data, "CLONE_FAILED", nil)
	end
	if not ownsUniqueRuntimeRoot(staged) then
		return rollbackLoad(data, "RUNTIME_ROOT_CONFLICT", nil)
	end

	data.snapshot = runtimeSnapshot
	data.state = "Loaded"
	return Result.ok(runtimeSnapshot)
end

function LoaderMethods.getSnapshot(self: Loader): Result.Result<RuntimeMapSnapshot, LoaderError>
	local data = requireLoaderData(self)
	if data.state == "Idle" then
		return failure("NOT_LOADED", "getSnapshot", data.state, nil)
	elseif data.state ~= "Loaded" then
		return failure("INVALID_STATE", "getSnapshot", data.state, nil)
	end

	local snapshot = data.snapshot
	if snapshot == nil then
		data.state = "Failed"
		data.cloneTemplate = nil
		return failure("INVALID_STATE", "getSnapshot", data.state, nil)
	end
	return Result.ok(snapshot)
end

function LoaderMethods.getLane(self: Loader, laneIdValue: unknown): Result.Result<RuntimeLaneSnapshot, LoaderError>
	local data = requireLoaderData(self)
	if data.state == "Idle" then
		return failure("NOT_LOADED", "getLane", data.state, nil)
	elseif data.state ~= "Loaded" then
		return failure("INVALID_STATE", "getLane", data.state, nil)
	end

	if type(laneIdValue) ~= "string" or not Validation.isSymbolicKey(laneIdValue) then
		return failure("INVALID_LANE_ID", "getLane", data.state, nil)
	end

	local snapshot = data.snapshot
	if snapshot == nil then
		data.state = "Failed"
		data.cloneTemplate = nil
		return failure("INVALID_STATE", "getLane", data.state, nil)
	end
	for _, lane in snapshot.lanes do
		if lane.id == laneIdValue then
			return Result.ok(lane)
		end
	end
	return failure("LANE_NOT_FOUND", "getLane", data.state, nil)
end

function LoaderMethods.unload(self: Loader): Result.Result<boolean, LoaderError>
	local data = requireLoaderData(self)
	if data.state == "Idle" then
		return Result.ok(false)
	elseif data.state ~= "Loaded" then
		return failure("INVALID_STATE", "unload", data.state, nil)
	end

	data.state = "Unloading"
	if not releaseOwnedLoad(data) then
		data.state = "Failed"
		data.cloneTemplate = nil
		return failure("CLEANUP_FAILED", "unload", data.state, nil)
	end
	data.state = "Idle"
	return Result.ok(true)
end

function LoaderMethods.cleanup(self: Loader): Result.Result<boolean, LoaderError>
	local data = requireLoaderData(self)
	if data.state == "Cleaned" then
		return Result.ok(false)
	elseif data.state ~= "Idle" and data.state ~= "Loaded" then
		return failure("INVALID_STATE", "cleanup", data.state, nil)
	end

	data.state = "Unloading"
	if not releaseOwnedLoad(data) then
		data.state = "Failed"
		data.cloneTemplate = nil
		return failure("CLEANUP_FAILED", "cleanup", data.state, nil)
	end
	data.cloneTemplate = nil
	data.state = "Cleaned"
	return Result.ok(true)
end

function LoaderMethods.getState(self: Loader): LoaderState
	return requireLoaderData(self).state
end

local function construct(logger: Log.Logger, cloneTemplate: CloneTemplate): Loader
	local loader = setmetatable({}, LoaderMethods) :: Loader
	table.freeze(loader)
	LOADER_DATA[loader] = {
		logger = logger,
		state = "Idle",
		loadCleanup = nil,
		snapshot = nil,
		cloneTemplate = cloneTemplate,
	}
	return loader
end

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "MapLoader" then
		return false
	end
	local productionServerMaps = script.Parent
	if
		productionServerMaps == nil
		or not productionServerMaps:IsA("Folder")
		or productionServerMaps.Name ~= "ProductionServerMaps"
	then
		return false
	end
	local automatedTests = productionServerMaps.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	if automatedTests.Parent ~= ServerStorage then
		return false
	end

	local supportMatches = directNamedChildren(automatedTests, "Support", 2)
	if #supportMatches ~= 1 or not supportMatches[1]:IsA("Folder") then
		return false
	end
	local support = supportMatches[1]
	local runnerMatches = directNamedChildren(support, "TestRunner", 2)
	local adapterMatches = directNamedChildren(support, "RobloxAdapter", 2)
	if
		#runnerMatches ~= 1
		or not runnerMatches[1]:IsA("ModuleScript")
		or #adapterMatches ~= 1
		or not adapterMatches[1]:IsA("ModuleScript")
	then
		return false
	end
	return ServerScriptService:FindFirstChild("Server") == nil
end

function MapLoader.new(logger: Log.Logger): Loader
	if not Log.isLogger(logger) then
		error("[ATD_MAP_LOADER][code=INVALID_LOGGER]", 0)
	end
	return construct(logger, defaultCloneTemplate)
end

function MapLoader.newForTests(logger: Log.Logger, cloneTemplate: CloneTemplate): Loader
	if not Log.isLogger(logger) then
		error("[ATD_MAP_LOADER][code=INVALID_LOGGER]", 0)
	end
	if not testModuleIdentityIsExact() then
		error("[ATD_MAP_LOADER][code=TEST_CONSTRUCTOR_FORBIDDEN]", 0)
	end
	if type(cloneTemplate) ~= "function" then
		error("[ATD_MAP_LOADER][code=INVALID_CLONE_ADAPTER]", 0)
	end
	return construct(logger, cloneTemplate)
end

table.freeze(LoaderMethods)
return table.freeze(MapLoader)
