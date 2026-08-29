--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local AssetSchema = require(ReplicatedStorage.Shared.config.AssetSchema)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local TowerSchema = require(ReplicatedStorage.Shared.config.TowerSchema)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)

local TowerModelContract = require(script.Parent.TowerModelContract)

export type FactoryState = "Ready" | "Faulted" | "Cleaned"
export type Operation = "new" | "createTemplate" | "createAllTemplates" | "cleanup"

export type FactoryError = {
	code: string,
	operation: Operation,
}

export type TemplateSet = {
	ordered: { Model },
	byTowerId: { [Ids.TowerId]: Model },
}

export type TestDependencies = {
	isStudio: () -> unknown,
	createInstance: (className: string) -> unknown,
	destroyInstance: (instance: Instance) -> unknown,
}

export type Factory = {
	createTemplate: (self: Factory, definitionValue: unknown) -> Result.Result<Model, FactoryError>,
	createAllTemplates: (self: Factory) -> Result.Result<TemplateSet, FactoryError>,
	cleanup: (self: Factory) -> Result.Result<boolean, FactoryError>,
	getState: (self: Factory) -> FactoryState,
}

export type TestConstructor = (
	configurationValue: unknown,
	dependenciesValue: unknown
) -> Result.Result<Factory, FactoryError>

type Dependencies = {
	isStudio: () -> unknown,
	createInstance: (className: string) -> unknown,
	destroyInstance: (instance: Instance) -> unknown,
}

type FactoryData = {
	state: FactoryState,
	configuration: ConfigTypes.CoreConfiguration?,
	dependencies: Dependencies?,
	intermediates: { Instance },
	busy: boolean,
	reentryViolation: boolean,
	cleanupRequested: boolean,
}

local SINGLE_TOWER_ID = "tower:phase12-single"
local SPLASH_TOWER_ID = "tower:phase12-splash"
local SUPPORT_TOWER_ID = "tower:phase12-support"
local MAX_TEMPLATES = 3

local MUZZLES_BY_TOWER_ID: { [string]: number } = table.freeze({
	[SINGLE_TOWER_ID] = 1,
	[SPLASH_TOWER_ID] = 2,
	[SUPPORT_TOWER_ID] = 0,
})

local TEST_DEPENDENCY_FIELDS: { [string]: boolean } = table.freeze({
	createInstance = true,
	destroyInstance = true,
	isStudio = true,
})

local FactoryMethods = {}
FactoryMethods.__index = FactoryMethods
local FACTORY_DATA: { [Factory]: FactoryData } = setmetatable({}, { __mode = "k" }) :: any

local TowerGrayboxFactory = {
	newForTests = nil :: TestConstructor?,
}

local CLEANUP_TRUE = Result.ok(true)
local CLEANUP_FALSE = Result.ok(false)

local function makeError(code: string, operation: Operation): FactoryError
	return table.freeze({
		code = code,
		operation = operation,
	})
end

local function failure<T>(code: string, operation: Operation): Result.Result<T, FactoryError>
	return Result.err(makeError(code, operation))
end

local function callNonYielding(callback: (...any) -> unknown, ...: any): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread, ...)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function requireData(factory: Factory): FactoryData
	local data = FACTORY_DATA[factory]
	if data == nil then
		error("[ATD_TOWER_GRAYBOX_FACTORY][code=INVALID_SELF]", 0)
	end
	return data
end

local function destroyInstance(data: FactoryData, instance: Instance): boolean
	local dependencies = data.dependencies
	if dependencies == nil then
		return false
	end
	local completed, value = callNonYielding(dependencies.destroyInstance, instance)
	return completed and value == true
end

local function destroyIntermediates(data: FactoryData): boolean
	local cleaned = true
	local retained: { Instance } = {}
	for index = #data.intermediates, 1, -1 do
		local model = data.intermediates[index]
		if not destroyInstance(data, model) then
			cleaned = false
			retained[#retained + 1] = model
		end
	end
	data.intermediates = retained
	return cleaned
end

local function clearData(data: FactoryData): boolean
	if not destroyIntermediates(data) then
		data.busy = false
		data.reentryViolation = false
		data.cleanupRequested = false
		data.state = "Faulted"
		return false
	end
	data.configuration = nil
	data.dependencies = nil
	data.busy = false
	data.reentryViolation = false
	data.cleanupRequested = false
	data.state = "Cleaned"
	return true
end

local function fault(data: FactoryData)
	destroyIntermediates(data)
	data.state = "Faulted"
	data.busy = false
	data.reentryViolation = false
	data.cleanupRequested = false
end

local function enter(data: FactoryData, operation: Operation): FactoryError?
	if data.busy then
		data.reentryViolation = true
		return makeError("REENTRANT", operation)
	end
	if data.state == "Cleaned" then
		return makeError("CLEANED", operation)
	elseif data.state == "Faulted" then
		return makeError("FAULTED", operation)
	end
	data.busy = true
	data.reentryViolation = false
	data.cleanupRequested = false
	return nil
end

local function operationWasInterrupted(data: FactoryData): boolean
	return data.reentryViolation or data.cleanupRequested
end

local function finishFailure<T>(data: FactoryData, code: string, operation: Operation): Result.Result<T, FactoryError>
	if data.cleanupRequested then
		if clearData(data) then
			return failure("CLEANED", operation)
		end
		return failure("CLEANUP_FAILED", operation)
	end
	fault(data)
	return failure(code, operation)
end

local function finishSuccess(data: FactoryData)
	data.busy = false
	data.reentryViolation = false
	data.cleanupRequested = false
end

local function exactConfiguration(value: unknown): ConfigTypes.CoreConfiguration?
	if
		not ConfigurationValidator.isValidatedConfiguration(value)
		or not AssetSchema.isValidatedManifest((value :: any).assets)
		or not TowerSchema.isValidatedCatalog((value :: any).towers)
	then
		return nil
	end
	return value :: ConfigTypes.CoreConfiguration
end

local function exactDefinition(
	configuration: ConfigTypes.CoreConfiguration,
	value: unknown
): ConfigTypes.TowerDefinition?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local definition = value :: ConfigTypes.TowerDefinition
	if configuration.towers.byId[definition.id] ~= definition then
		return nil
	end
	local retainsDefinition = false
	for _, candidate in configuration.towers.ordered do
		if candidate == definition then
			retainsDefinition = true
			break
		end
	end
	if not retainsDefinition then
		return nil
	end
	local asset = configuration.assets.byKey[definition.modelAssetKey]
	if asset == nil or asset.kind ~= "TowerModel" then
		return nil
	end
	for _, candidate in configuration.assets.ordered do
		if candidate == asset then
			return definition
		end
	end
	return nil
end

local function pristineInstance(value: unknown, className: string, seen: { [Instance]: boolean }): Instance?
	if typeof(value) ~= "Instance" then
		return nil
	end
	local instance = value :: Instance
	if
		instance.ClassName ~= className
		or instance.Parent ~= nil
		or seen[instance]
		or #instance:GetChildren() ~= 0
		or #instance:GetTags() ~= 0
		or next(instance:GetAttributes()) ~= nil
	then
		return nil
	end
	seen[instance] = true
	return instance
end

local function createExact(data: FactoryData, className: string, seen: { [Instance]: boolean }): Instance?
	local dependencies = data.dependencies
	if dependencies == nil then
		return nil
	end
	local completed, value = callNonYielding(dependencies.createInstance, className)
	if not completed then
		return nil
	end
	local instance = pristineInstance(value, className, seen)
	if instance == nil then
		return nil
	end
	if operationWasInterrupted(data) then
		if not destroyInstance(data, instance) then
			data.intermediates[#data.intermediates + 1] = instance
		end
		return nil
	end
	return instance
end

local function configurePart(part: Part, size: Vector3)
	part.Anchored = true
	part.Massless = true
	part.CastShadow = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 0
	part.Size = size
	part.CFrame = CFrame.identity
	part.PivotOffset = CFrame.identity
end

local function bodySize(towerId: string, levelIndex: number): Vector3
	local growth = (levelIndex - 1) * 0.25
	if towerId == SINGLE_TOWER_ID then
		return Vector3.new(2 + growth, 3 + growth, 2 + growth)
	elseif towerId == SPLASH_TOWER_ID then
		return Vector3.new(3 + growth, 2.5 + growth, 3 + growth)
	end
	return Vector3.new(2.5 + growth, 2 + growth, 2.5 + growth)
end

local function buildTemplate(data: FactoryData, definition: ConfigTypes.TowerDefinition): Model?
	local muzzleCount = MUZZLES_BY_TOWER_ID[definition.id]
	if muzzleCount == nil then
		return nil
	end
	local seen: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local rootValue = createExact(data, "Model", seen)
	if rootValue == nil then
		return nil
	end
	local root = rootValue :: Model
	data.intermediates[#data.intermediates + 1] = root

	local built, modelValue = callNonYielding(function(): Model
		root.Name = "Tower"
		root.Archivable = true
		root:SetAttribute(TowerModelContract.CONTRACT_ATTRIBUTE, TowerModelContract.CONTRACT_VERSION)

		local rootPart = createExact(data, "Part", seen) :: Part?
		if rootPart == nil then
			error("INSTANCE_CREATION_FAILED", 0)
		end
		rootPart.Name = "Root"
		configurePart(rootPart, Vector3.new(2, 1, 2))
		rootPart.Transparency = 1
		rootPart.Parent = root
		root.PrimaryPart = rootPart

		local animation = createExact(data, "Folder", seen) :: Folder?
		if animation == nil then
			error("INSTANCE_CREATION_FAILED", 0)
		end
		animation.Name = "Animation"
		animation.Parent = root

		local controller = createExact(data, "AnimationController", seen) :: AnimationController?
		local animator = createExact(data, "Animator", seen) :: Animator?
		local hooks = createExact(data, "Folder", seen) :: Folder?
		if controller == nil or animator == nil or hooks == nil then
			error("INSTANCE_CREATION_FAILED", 0)
		end
		controller.Name = "Controller"
		controller.Parent = animation
		animator.Name = "Animator"
		animator.Parent = controller
		hooks.Name = "Hooks"
		hooks.Parent = animation

		local function addHook(name: string, value: string)
			local hook = createExact(data, "StringValue", seen) :: StringValue?
			if hook == nil then
				error("INSTANCE_CREATION_FAILED", 0)
			end
			hook.Name = name
			hook.Value = value
			hook.Parent = hooks
		end
		addHook("Idle", "hook.idle")
		addHook("Upgrade", "hook.upgrade")
		local anyAttack = false
		for _, level in definition.levels do
			if level.attack ~= nil then
				anyAttack = true
				break
			end
		end
		if anyAttack then
			addHook("Attack", "hook.attack")
		end

		local variants = createExact(data, "Folder", seen) :: Folder?
		if variants == nil then
			error("INSTANCE_CREATION_FAILED", 0)
		end
		variants.Name = "UpgradeVariants"
		variants.Parent = root

		for levelIndex, level in definition.levels do
			local variant = createExact(data, "Model", seen) :: Model?
			local body = createExact(data, "Part", seen) :: Part?
			local aim = createExact(data, "Folder", seen) :: Folder?
			local muzzles = createExact(data, "Folder", seen) :: Folder?
			if variant == nil or body == nil or aim == nil or muzzles == nil then
				error("INSTANCE_CREATION_FAILED", 0)
			end
			variant.Name = string.format("Level%02d", levelIndex)
			body.Name = "Body"
			configurePart(body, bodySize(definition.id, levelIndex))
			aim.Name = "Aim"
			muzzles.Name = "Muzzles"
			aim.Parent = body
			muzzles.Parent = body
			body.Parent = variant
			variant.PrimaryPart = body
			variant.Parent = variants

			if level.attack ~= nil then
				if muzzleCount < 1 then
					error("UNSUPPORTED_DEFINITION", 0)
				end
				local aimPivot = createExact(data, "Attachment", seen) :: Attachment?
				if aimPivot == nil then
					error("INSTANCE_CREATION_FAILED", 0)
				end
				aimPivot.Name = "AimPivot"
				aimPivot.CFrame = CFrame.identity
				aimPivot.Parent = aim
				for muzzleIndex = 1, muzzleCount do
					local muzzle = createExact(data, "Attachment", seen) :: Attachment?
					if muzzle == nil then
						error("INSTANCE_CREATION_FAILED", 0)
					end
					muzzle.Name = string.format("Muzzle%02d", muzzleIndex)
					local horizontalOffset = (muzzleIndex - (muzzleCount + 1) / 2) * 0.75
					muzzle.CFrame = CFrame.new(horizontalOffset, 0, -1)
					muzzle.Parent = muzzles
				end
			end
		end

		if operationWasInterrupted(data) then
			error("OPERATION_INTERRUPTED", 0)
		end
		return root
	end)
	if not built or operationWasInterrupted(data) or modelValue ~= root then
		return nil
	end
	local validation = TowerModelContract.validateTemplate(data.configuration, definition, root)
	if not validation.ok then
		return nil
	end
	return root
end

local function studioGate(data: FactoryData): (boolean, string?)
	local dependencies = data.dependencies
	if dependencies == nil then
		return false, "INVALID_DEPENDENCIES"
	end
	local completed, value = callNonYielding(dependencies.isStudio)
	if not completed or operationWasInterrupted(data) then
		return false, "STUDIO_CHECK_FAILED"
	end
	if type(value) ~= "boolean" then
		return false, "STUDIO_CHECK_FAILED"
	elseif value ~= true then
		return false, "NOT_STUDIO"
	end
	return true, nil
end

function FactoryMethods.createTemplate(self: Factory, definitionValue: unknown): Result.Result<Model, FactoryError>
	local operation: Operation = "createTemplate"
	local data = requireData(self)
	local enterError = enter(data, operation)
	if enterError ~= nil then
		return Result.err(enterError)
	end
	local configuration = data.configuration :: ConfigTypes.CoreConfiguration
	local definition = exactDefinition(configuration, definitionValue)
	if definition == nil then
		data.busy = false
		return failure("INVALID_DEFINITION", operation)
	end
	if MUZZLES_BY_TOWER_ID[definition.id] == nil then
		data.busy = false
		return failure("UNSUPPORTED_DEFINITION", operation)
	end
	local studioAllowed, studioError = studioGate(data)
	if not studioAllowed then
		if studioError == "NOT_STUDIO" then
			data.busy = false
			return failure("NOT_STUDIO", operation)
		end
		return finishFailure(data, studioError :: string, operation)
	end
	local model = buildTemplate(data, definition)
	if model == nil then
		return finishFailure(data, "TEMPLATE_CREATION_FAILED", operation)
	end
	local successResult = Result.ok(model)
	data.intermediates[#data.intermediates] = nil
	finishSuccess(data)
	return successResult
end

function FactoryMethods.createAllTemplates(self: Factory): Result.Result<TemplateSet, FactoryError>
	local operation: Operation = "createAllTemplates"
	local data = requireData(self)
	local enterError = enter(data, operation)
	if enterError ~= nil then
		return Result.err(enterError)
	end
	local configuration = data.configuration :: ConfigTypes.CoreConfiguration
	if #configuration.towers.ordered ~= MAX_TEMPLATES then
		data.busy = false
		return failure("UNSUPPORTED_CATALOG", operation)
	end
	local expectedTowerIds = { SINGLE_TOWER_ID, SPLASH_TOWER_ID, SUPPORT_TOWER_ID }
	for index, definition in configuration.towers.ordered do
		if
			exactDefinition(configuration, definition) == nil
			or definition.id ~= expectedTowerIds[index]
			or MUZZLES_BY_TOWER_ID[definition.id] == nil
		then
			data.busy = false
			return failure("UNSUPPORTED_CATALOG", operation)
		end
	end
	local studioAllowed, studioError = studioGate(data)
	if not studioAllowed then
		if studioError == "NOT_STUDIO" then
			data.busy = false
			return failure("NOT_STUDIO", operation)
		end
		return finishFailure(data, studioError :: string, operation)
	end

	local ordered: { Model } = table.create(#configuration.towers.ordered)
	local byTowerId: { [Ids.TowerId]: Model } = {}
	for index, definition in configuration.towers.ordered do
		local model = buildTemplate(data, definition)
		if model == nil then
			return finishFailure(data, "TEMPLATE_CREATION_FAILED", operation)
		end
		ordered[index] = model
		byTowerId[definition.id] = model
	end
	local templateSet: TemplateSet = table.freeze({
		ordered = table.freeze(ordered),
		byTowerId = table.freeze(byTowerId),
	})
	local successResult = Result.ok(templateSet)
	-- Ownership transfers only after the complete detached result and its Result
	-- wrapper exist. Factory cleanup never destroys transferred templates.
	table.clear(data.intermediates)
	finishSuccess(data)
	return successResult
end

function FactoryMethods.cleanup(self: Factory): Result.Result<boolean, FactoryError>
	local data = requireData(self)
	if data.busy then
		data.cleanupRequested = true
		return CLEANUP_FALSE
	end
	if data.state == "Cleaned" then
		return CLEANUP_FALSE
	end
	data.busy = true
	if not clearData(data) then
		return failure("CLEANUP_FAILED", "cleanup")
	end
	return CLEANUP_TRUE
end

function FactoryMethods.getState(self: Factory): FactoryState
	return requireData(self).state
end

local function construct(configurationValue: unknown, dependencies: Dependencies): Result.Result<Factory, FactoryError>
	local configuration = exactConfiguration(configurationValue)
	if configuration == nil then
		return failure("UNAUTHENTICATED_CONFIGURATION", "new")
	end
	local factory = setmetatable({}, FactoryMethods) :: Factory
	table.freeze(factory)
	FACTORY_DATA[factory] = {
		state = "Ready",
		configuration = configuration,
		dependencies = dependencies,
		intermediates = {},
		busy = false,
		reentryViolation = false,
		cleanupRequested = false,
	}
	return Result.ok(factory)
end

local function productionIsStudio(): unknown
	return RunService:IsStudio()
end

local function productionCreateInstance(className: string): unknown
	return Instance.new(className)
end

local function productionDestroyInstance(instance: Instance): unknown
	instance:Destroy()
	return true
end

local PRODUCTION_DEPENDENCIES: Dependencies = table.freeze({
	isStudio = productionIsStudio,
	createInstance = productionCreateInstance,
	destroyInstance = productionDestroyInstance,
})

local function testModuleIdentityIsExact(): boolean
	if not script:IsA("ModuleScript") or script.Name ~= "TowerGrayboxFactory" then
		return false
	end
	local productionServerTowers = script.Parent
	if
		productionServerTowers == nil
		or not productionServerTowers:IsA("Folder")
		or productionServerTowers.Name ~= "ProductionServerTowers"
	then
		return false
	end
	local automatedTests = productionServerTowers.Parent
	if automatedTests == nil or not automatedTests:IsA("Folder") or automatedTests.Name ~= "AutomatedTests" then
		return false
	end
	if automatedTests.Parent ~= ServerStorage then
		return false
	end
	local support = automatedTests:FindFirstChild("Support")
	return support ~= nil
		and support:IsA("Folder")
		and support:FindFirstChild("TestRunner") ~= nil
		and ServerScriptService:FindFirstChild("Server") == nil
end

function TowerGrayboxFactory.new(configurationValue: unknown): Result.Result<Factory, FactoryError>
	return construct(configurationValue, PRODUCTION_DEPENDENCIES)
end

if testModuleIdentityIsExact() then
	TowerGrayboxFactory.newForTests = function(
		configurationValue: unknown,
		dependenciesValue: unknown
	): Result.Result<Factory, FactoryError>
		if type(dependenciesValue) ~= "table" or getmetatable(dependenciesValue :: any) ~= nil then
			return failure("INVALID_DEPENDENCIES", "new")
		end
		local fieldCount = 0
		for key in next, dependenciesValue :: { [any]: unknown } do
			if type(key) ~= "string" or TEST_DEPENDENCY_FIELDS[key] ~= true then
				return failure("INVALID_DEPENDENCIES", "new")
			end
			fieldCount += 1
		end
		local dependencies = dependenciesValue :: any
		if
			fieldCount ~= 3
			or type(dependencies.isStudio) ~= "function"
			or type(dependencies.createInstance) ~= "function"
			or type(dependencies.destroyInstance) ~= "function"
		then
			return failure("INVALID_DEPENDENCIES", "new")
		end
		return construct(
			configurationValue,
			table.freeze({
				isStudio = dependencies.isStudio,
				createInstance = dependencies.createInstance,
				destroyInstance = dependencies.destroyInstance,
			})
		)
	end
end

table.freeze(FactoryMethods)
return table.freeze(TowerGrayboxFactory)
