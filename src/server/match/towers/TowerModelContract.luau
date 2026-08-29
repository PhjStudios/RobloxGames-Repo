--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetSchema = require(ReplicatedStorage.Shared.config.AssetSchema)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local TowerSchema = require(ReplicatedStorage.Shared.config.TowerSchema)
local ConfigTypes = require(ReplicatedStorage.Shared.types.ConfigTypes)
local Ids = require(ReplicatedStorage.Shared.util.Ids)
local Result = require(ReplicatedStorage.Shared.util.Result)

export type Operation = "validateTemplate" | "validateLive" | "selectLiveVariant"

export type ContractError = {
	code: string,
	operation: Operation,
	path: string,
}

export type ContractSnapshot = {
	contractVersion: number,
	towerId: Ids.TowerId,
	modelAssetKey: ConfigTypes.AssetKey,
	mode: "Template" | "Live",
	selectedLevelIndex: number?,
	levelCount: number,
	descendantCount: number,
	basePartCount: number,
	attachmentCount: number,
	muzzleCount: number,
	hookCount: number,
}

local CONTRACT_VERSION = 1
local CONTRACT_ATTRIBUTE = "ATDTowerModelContractVersion"
local MAX_DESCENDANTS = 297
local MAX_BASE_PARTS = 33
local MAX_VARIANTS = 32
local MAX_ATTACHMENTS = 160
local MAX_MUZZLES_PER_VARIANT = 4
local MAX_HOOKS = 3
local MAX_DIRECT_CHILDREN = 32
local MAX_DEPTH = 5
local MAX_SIZE_COMPONENT = 64
local MAX_COORDINATE = 100_000

local ALLOWED_CLASSES: { [string]: boolean } = table.freeze({
	AnimationController = true,
	Animator = true,
	Attachment = true,
	Folder = true,
	Model = true,
	Part = true,
	StringValue = true,
})

local TowerModelContract = {
	CONTRACT_ATTRIBUTE = CONTRACT_ATTRIBUTE,
	CONTRACT_VERSION = CONTRACT_VERSION,
	MAX_ATTACHMENTS = MAX_ATTACHMENTS,
	MAX_BASE_PARTS = MAX_BASE_PARTS,
	MAX_COORDINATE = MAX_COORDINATE,
	MAX_DESCENDANTS = MAX_DESCENDANTS,
	MAX_HOOKS = MAX_HOOKS,
	MAX_MUZZLES_PER_VARIANT = MAX_MUZZLES_PER_VARIANT,
	MAX_VARIANTS = MAX_VARIANTS,
}

type ValidationMode = "Template" | "Live"

type CanonicalSelection = {
	configuration: ConfigTypes.CoreConfiguration,
	definition: ConfigTypes.TowerDefinition,
	levelIndex: number?,
}

type Counts = {
	descendants: number,
	baseParts: number,
	attachments: number,
	muzzles: number,
	hooks: number,
}

type QueueEntry = {
	instance: Instance,
	depth: number,
}

local function makeError(code: string, operation: Operation, path: string): ContractError
	return table.freeze({
		code = code,
		operation = operation,
		path = path,
	})
end

local function failure(code: string, operation: Operation, path: string): Result.Result<ContractSnapshot, ContractError>
	return Result.err(makeError(code, operation, path))
end

local function callNonYielding(callback: () -> unknown): (boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed, value = coroutine.resume(thread)
	if not resumed then
		return false, nil
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, value
end

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function cframeIsBounded(value: CFrame): boolean
	local components = { value:GetComponents() }
	for _, component in components do
		if not isFinite(component) then
			return false
		end
	end
	return math.abs(components[1]) <= MAX_COORDINATE
		and math.abs(components[2]) <= MAX_COORDINATE
		and math.abs(components[3]) <= MAX_COORDINATE
end

local function sizeIsValid(value: Vector3): boolean
	return isFinite(value.X)
		and isFinite(value.Y)
		and isFinite(value.Z)
		and value.X > 0
		and value.Y > 0
		and value.Z > 0
		and value.X <= MAX_SIZE_COMPONENT
		and value.Y <= MAX_SIZE_COMPONENT
		and value.Z <= MAX_SIZE_COMPONENT
end

local function canonicalSelection(
	configurationValue: unknown,
	definitionValue: unknown,
	levelValue: unknown?,
	requireLevel: boolean,
	operation: Operation
): (CanonicalSelection?, ContractError?)
	if
		not ConfigurationValidator.isValidatedConfiguration(configurationValue)
		or not AssetSchema.isValidatedManifest((configurationValue :: any).assets)
		or not TowerSchema.isValidatedCatalog((configurationValue :: any).towers)
	then
		return nil, makeError("UNAUTHENTICATED_CONFIGURATION", operation, "Configuration")
	end
	if type(definitionValue) ~= "table" or getmetatable(definitionValue :: any) ~= nil then
		return nil, makeError("INVALID_DEFINITION", operation, "Definition")
	end

	local configuration = configurationValue :: ConfigTypes.CoreConfiguration
	local definition = definitionValue :: ConfigTypes.TowerDefinition
	if configuration.towers.byId[definition.id] ~= definition then
		return nil, makeError("INVALID_DEFINITION", operation, "Definition")
	end
	local retainsDefinition = false
	for _, candidate in configuration.towers.ordered do
		if candidate == definition then
			retainsDefinition = true
			break
		end
	end
	if not retainsDefinition then
		return nil, makeError("INVALID_DEFINITION", operation, "Definition")
	end
	local modelAsset = configuration.assets.byKey[definition.modelAssetKey]
	if modelAsset == nil or modelAsset.kind ~= "TowerModel" then
		return nil, makeError("INVALID_MODEL_ASSET", operation, "Definition.modelAssetKey")
	end
	local retainsAsset = false
	for _, candidate in configuration.assets.ordered do
		if candidate == modelAsset then
			retainsAsset = true
			break
		end
	end
	if not retainsAsset then
		return nil, makeError("INVALID_MODEL_ASSET", operation, "Definition.modelAssetKey")
	end
	if #definition.levels < 1 or #definition.levels > MAX_VARIANTS then
		return nil, makeError("INVALID_LEVEL_COUNT", operation, "Definition.levels")
	end

	local levelIndex: number? = nil
	if requireLevel then
		for index, candidate in definition.levels do
			if candidate == levelValue then
				levelIndex = index
				break
			end
		end
		if levelIndex == nil then
			return nil, makeError("INVALID_LEVEL", operation, "Level")
		end
	elseif levelValue ~= nil then
		return nil, makeError("INVALID_LEVEL", operation, "Level")
	end

	return {
		configuration = configuration,
		definition = definition,
		levelIndex = levelIndex,
	}, nil
end

local function directChildren(
	parent: Instance,
	operation: Operation,
	path: string
): ({ [string]: Instance }?, ContractError?)
	local children = parent:GetChildren()
	if #children > MAX_DIRECT_CHILDREN then
		return nil, makeError("BOUND_EXCEEDED", operation, path)
	end
	local byName: { [string]: Instance } = {}
	for _, child in children do
		if child.Parent ~= parent or byName[child.Name] ~= nil then
			return nil, makeError("INVALID_HIERARCHY", operation, path)
		end
		byName[child.Name] = child
	end
	return byName, nil
end

local function hasExactKeys(children: { [string]: Instance }, expected: { [string]: string }): boolean
	local count = 0
	for name, child in children do
		local expectedClass = expected[name]
		if expectedClass == nil or child.ClassName ~= expectedClass then
			return false
		end
		count += 1
	end
	local expectedCount = 0
	for name, expectedClass in expected do
		local child = children[name]
		if child == nil or child.ClassName ~= expectedClass then
			return false
		end
		expectedCount += 1
	end
	return count == expectedCount
end

local function validateTagsAndAttributes(
	instance: Instance,
	isRoot: boolean,
	operation: Operation,
	path: string
): ContractError?
	if #instance:GetTags() ~= 0 then
		return makeError("INVALID_TAG", operation, path)
	end
	local attributes = instance:GetAttributes()
	local count = 0
	for key, value in attributes do
		count += 1
		if not isRoot or key ~= CONTRACT_ATTRIBUTE or type(value) ~= "number" or value ~= CONTRACT_VERSION then
			return makeError("INVALID_ATTRIBUTE", operation, path)
		end
	end
	if isRoot and count ~= 1 then
		return makeError("INVALID_ATTRIBUTE", operation, path)
	elseif not isRoot and count ~= 0 then
		return makeError("INVALID_ATTRIBUTE", operation, path)
	end
	return nil
end

local function validatePart(
	part: BasePart,
	expectedTransparency: number,
	operation: Operation,
	path: string
): ContractError?
	if
		part.ClassName ~= "Part"
		or not part.Anchored
		or not part.Massless
		or part.CastShadow
		or part.CanCollide
		or part.CanTouch
		or part.CanQuery
		or part.Transparency ~= expectedTransparency
		or not sizeIsValid(part.Size)
		or not cframeIsBounded(part.CFrame)
		or not cframeIsBounded(part.PivotOffset)
	then
		return makeError("INVALID_PROPERTY", operation, path)
	end
	return nil
end

local function boundedBreadthFirst(root: Model, operation: Operation): (Counts?, ContractError?)
	local counts: Counts = {
		descendants = 0,
		baseParts = 0,
		attachments = 0,
		muzzles = 0,
		hooks = 0,
	}
	local queue: { QueueEntry } = { { instance = root, depth = 0 } }
	local cursor = 1
	while cursor <= #queue do
		local entry = queue[cursor]
		cursor += 1
		local instance = entry.instance
		if #instance.Name > 32 then
			return nil, makeError("INVALID_HIERARCHY", operation, "Tower")
		end
		local path = instance.Name
		if entry.depth > MAX_DEPTH or ALLOWED_CLASSES[instance.ClassName] ~= true then
			return nil, makeError("INVALID_CLASS", operation, path)
		end
		local metadataError = validateTagsAndAttributes(instance, instance == root, operation, path)
		if metadataError ~= nil then
			return nil, metadataError
		end
		if instance ~= root then
			counts.descendants += 1
		end
		if instance:IsA("BasePart") then
			counts.baseParts += 1
		elseif instance:IsA("Attachment") then
			counts.attachments += 1
			if not cframeIsBounded((instance :: Attachment).CFrame) then
				return nil, makeError("INVALID_TRANSFORM", operation, path)
			end
		elseif instance:IsA("StringValue") then
			counts.hooks += 1
		end
		if
			counts.descendants > MAX_DESCENDANTS
			or counts.baseParts > MAX_BASE_PARTS
			or counts.attachments > MAX_ATTACHMENTS
			or counts.hooks > MAX_HOOKS
		then
			return nil, makeError("BOUND_EXCEEDED", operation, path)
		end
		local children = instance:GetChildren()
		if #children > MAX_DIRECT_CHILDREN then
			return nil, makeError("BOUND_EXCEEDED", operation, path)
		end
		for _, child in children do
			if child.Parent ~= instance then
				return nil, makeError("INVALID_HIERARCHY", operation, path)
			end
			table.insert(queue, { instance = child, depth = entry.depth + 1 })
		end
	end
	return counts, nil
end

local function validateHierarchy(
	selection: CanonicalSelection,
	root: Model,
	mode: ValidationMode,
	operation: Operation
): (Counts?, ContractError?)
	if root.Name ~= "Tower" or not root.Archivable or (mode == "Template" and root.Parent ~= nil) then
		return nil, makeError("INVALID_ROOT", operation, "Tower")
	end

	local counts, boundsError = boundedBreadthFirst(root, operation)
	if boundsError ~= nil then
		return nil, boundsError
	end
	local rootChildren, rootChildrenError = directChildren(root, operation, "Tower")
	if rootChildrenError ~= nil then
		return nil, rootChildrenError
	end
	if
		rootChildren == nil
		or not hasExactKeys(rootChildren, {
			Animation = "Folder",
			Root = "Part",
			UpgradeVariants = "Folder",
		})
	then
		return nil, makeError("INVALID_HIERARCHY", operation, "Tower")
	end

	local rootPart = rootChildren.Root :: Part
	if root.PrimaryPart ~= rootPart then
		return nil, makeError("INVALID_PRIMARY_PART", operation, "Tower.PrimaryPart")
	end
	local rootPartError = validatePart(rootPart, 1, operation, "Tower.Root")
	if rootPartError ~= nil then
		return nil, rootPartError
	end
	if mode == "Template" and (rootPart.CFrame ~= CFrame.identity or rootPart.PivotOffset ~= CFrame.identity) then
		return nil, makeError("INVALID_TEMPLATE_PIVOT", operation, "Tower.Root.CFrame")
	end
	local rootPartChildren = directChildren(rootPart, operation, "Tower.Root")
	if rootPartChildren == nil or not hasExactKeys(rootPartChildren, {}) then
		return nil, makeError("INVALID_HIERARCHY", operation, "Tower.Root")
	end

	local animation = rootChildren.Animation
	local animationChildren = directChildren(animation, operation, "Tower.Animation")
	if
		animationChildren == nil
		or not hasExactKeys(animationChildren, { Controller = "AnimationController", Hooks = "Folder" })
	then
		return nil, makeError("INVALID_HIERARCHY", operation, "Tower.Animation")
	end
	local controllerChildren = directChildren(animationChildren.Controller, operation, "Tower.Animation.Controller")
	if controllerChildren == nil or not hasExactKeys(controllerChildren, { Animator = "Animator" }) then
		return nil, makeError("INVALID_HIERARCHY", operation, "Tower.Animation.Controller")
	end
	local animatorChildren =
		directChildren(controllerChildren.Animator, operation, "Tower.Animation.Controller.Animator")
	if animatorChildren == nil or not hasExactKeys(animatorChildren, {}) then
		return nil, makeError("INVALID_HIERARCHY", operation, "Tower.Animation.Controller.Animator")
	end

	local anyAttack = false
	for _, level in selection.definition.levels do
		if level.attack ~= nil then
			anyAttack = true
			break
		end
	end
	local expectedHooks: { [string]: string } = { Idle = "StringValue", Upgrade = "StringValue" }
	if anyAttack then
		expectedHooks.Attack = "StringValue"
	end
	local hooksChildren = directChildren(animationChildren.Hooks, operation, "Tower.Animation.Hooks")
	if hooksChildren == nil or not hasExactKeys(hooksChildren, expectedHooks) then
		return nil, makeError("INVALID_HIERARCHY", operation, "Tower.Animation.Hooks")
	end
	if
		(hooksChildren.Idle :: StringValue).Value ~= "hook.idle"
		or (hooksChildren.Upgrade :: StringValue).Value ~= "hook.upgrade"
		or (anyAttack and (hooksChildren.Attack :: StringValue).Value ~= "hook.attack")
	then
		return nil, makeError("INVALID_PROPERTY", operation, "Tower.Animation.Hooks")
	end
	for name, hook in hooksChildren do
		local hookChildren = directChildren(hook, operation, `Tower.Animation.Hooks.{name}`)
		if hookChildren == nil or not hasExactKeys(hookChildren, {}) then
			return nil, makeError("INVALID_HIERARCHY", operation, `Tower.Animation.Hooks.{name}`)
		end
	end

	local variants = rootChildren.UpgradeVariants
	local variantChildren = directChildren(variants, operation, "Tower.UpgradeVariants")
	if variantChildren == nil or #selection.definition.levels > MAX_VARIANTS then
		return nil, makeError("INVALID_HIERARCHY", operation, "Tower.UpgradeVariants")
	end
	local expectedVariantCount = #selection.definition.levels
	local actualVariantCount = 0
	for _ in variantChildren do
		actualVariantCount += 1
	end
	if actualVariantCount ~= expectedVariantCount then
		return nil, makeError("INVALID_HIERARCHY", operation, "Tower.UpgradeVariants")
	end

	local muzzleCount = 0
	for levelIndex, level in selection.definition.levels do
		local levelName = string.format("Level%02d", levelIndex)
		local variant = variantChildren[levelName]
		if variant == nil or variant.ClassName ~= "Model" then
			return nil, makeError("INVALID_HIERARCHY", operation, `Tower.UpgradeVariants.{levelName}`)
		end
		local variantChildrenByName = directChildren(variant, operation, `Tower.UpgradeVariants.{levelName}`)
		if variantChildrenByName == nil or not hasExactKeys(variantChildrenByName, { Body = "Part" }) then
			return nil, makeError("INVALID_HIERARCHY", operation, `Tower.UpgradeVariants.{levelName}`)
		end
		local body = variantChildrenByName.Body :: Part
		if (variant :: Model).PrimaryPart ~= body then
			return nil, makeError("INVALID_PRIMARY_PART", operation, `Tower.UpgradeVariants.{levelName}.PrimaryPart`)
		end
		local expectedTransparency = 0
		if mode == "Live" and selection.levelIndex ~= levelIndex then
			expectedTransparency = 1
		end
		local bodyError = validatePart(body, expectedTransparency, operation, `Tower.UpgradeVariants.{levelName}.Body`)
		if bodyError ~= nil then
			return nil, bodyError
		end
		local bodyChildren = directChildren(body, operation, `Tower.UpgradeVariants.{levelName}.Body`)
		if bodyChildren == nil or not hasExactKeys(bodyChildren, { Aim = "Folder", Muzzles = "Folder" }) then
			return nil, makeError("INVALID_HIERARCHY", operation, `Tower.UpgradeVariants.{levelName}.Body`)
		end

		local aimChildren = directChildren(bodyChildren.Aim, operation, `Tower.UpgradeVariants.{levelName}.Body.Aim`)
		local muzzleChildren =
			directChildren(bodyChildren.Muzzles, operation, `Tower.UpgradeVariants.{levelName}.Body.Muzzles`)
		if aimChildren == nil or muzzleChildren == nil then
			return nil, makeError("INVALID_HIERARCHY", operation, `Tower.UpgradeVariants.{levelName}.Body`)
		end
		if level.attack == nil then
			if not hasExactKeys(aimChildren, {}) or not hasExactKeys(muzzleChildren, {}) then
				return nil, makeError("INVALID_HIERARCHY", operation, `Tower.UpgradeVariants.{levelName}.Body`)
			end
		else
			if not hasExactKeys(aimChildren, { AimPivot = "Attachment" }) then
				return nil, makeError("INVALID_HIERARCHY", operation, `Tower.UpgradeVariants.{levelName}.Body.Aim`)
			end
			local levelMuzzleCount = 0
			for _, muzzle in muzzleChildren do
				levelMuzzleCount += 1
				if muzzle.ClassName ~= "Attachment" then
					return nil,
						makeError("INVALID_HIERARCHY", operation, `Tower.UpgradeVariants.{levelName}.Body.Muzzles`)
				end
			end
			if levelMuzzleCount < 1 or levelMuzzleCount > MAX_MUZZLES_PER_VARIANT then
				return nil, makeError("INVALID_HIERARCHY", operation, `Tower.UpgradeVariants.{levelName}.Body.Muzzles`)
			end
			-- Table iteration is not ordered, so prove dense names independently.
			for muzzleIndex = 1, levelMuzzleCount do
				local muzzle = muzzleChildren[string.format("Muzzle%02d", muzzleIndex)]
				if muzzle == nil or muzzle.ClassName ~= "Attachment" then
					return nil,
						makeError("INVALID_HIERARCHY", operation, `Tower.UpgradeVariants.{levelName}.Body.Muzzles`)
				end
			end
			muzzleCount += levelMuzzleCount
		end
	end
	(counts :: Counts).muzzles = muzzleCount
	return counts, nil
end

local function validateCore(
	configurationValue: unknown,
	definitionValue: unknown,
	levelValue: unknown?,
	modelValue: unknown,
	mode: ValidationMode,
	operation: Operation
): Result.Result<ContractSnapshot, ContractError>
	local selection, selectionError =
		canonicalSelection(configurationValue, definitionValue, levelValue, mode == "Live", operation)
	if selectionError ~= nil then
		return Result.err(selectionError)
	end
	if typeof(modelValue) ~= "Instance" or (modelValue :: Instance).ClassName ~= "Model" then
		return failure("INVALID_MODEL", operation, "Tower")
	end
	local root = modelValue :: Model
	local counts, hierarchyError = validateHierarchy(selection :: CanonicalSelection, root, mode, operation)
	if hierarchyError ~= nil then
		return Result.err(hierarchyError)
	end
	local authenticated = selection :: CanonicalSelection
	local measured = counts :: Counts
	local snapshot: ContractSnapshot = table.freeze({
		contractVersion = CONTRACT_VERSION,
		towerId = authenticated.definition.id,
		modelAssetKey = authenticated.definition.modelAssetKey,
		mode = mode,
		selectedLevelIndex = authenticated.levelIndex,
		levelCount = #authenticated.definition.levels,
		descendantCount = measured.descendants,
		basePartCount = measured.baseParts,
		attachmentCount = measured.attachments,
		muzzleCount = measured.muzzles,
		hookCount = measured.hooks,
	})
	return Result.ok(snapshot)
end

local function invokeValidation(
	operation: Operation,
	callback: () -> unknown
): Result.Result<ContractSnapshot, ContractError>
	local completed, value = callNonYielding(callback)
	if not completed then
		return failure("VALIDATION_FAILED", operation, "Tower")
	end
	return value :: Result.Result<ContractSnapshot, ContractError>
end

function TowerModelContract.validateTemplate(
	configurationValue: unknown,
	definitionValue: unknown,
	modelValue: unknown
): Result.Result<ContractSnapshot, ContractError>
	return invokeValidation("validateTemplate", function()
		return validateCore(configurationValue, definitionValue, nil, modelValue, "Template", "validateTemplate")
	end)
end

function TowerModelContract.validateLive(
	configurationValue: unknown,
	definitionValue: unknown,
	levelValue: unknown,
	modelValue: unknown
): Result.Result<ContractSnapshot, ContractError>
	return invokeValidation("validateLive", function()
		return validateCore(configurationValue, definitionValue, levelValue, modelValue, "Live", "validateLive")
	end)
end

function TowerModelContract.selectLiveVariant(
	configurationValue: unknown,
	definitionValue: unknown,
	levelValue: unknown,
	modelValue: unknown
): Result.Result<ContractSnapshot, ContractError>
	local operation: Operation = "selectLiveVariant"
	return invokeValidation(operation, function()
		local templateResult = validateCore(configurationValue, definitionValue, nil, modelValue, "Template", operation)
		if not templateResult.ok then
			return templateResult
		end
		local selection, selectionError =
			canonicalSelection(configurationValue, definitionValue, levelValue, true, operation)
		if selectionError ~= nil then
			return Result.err(selectionError)
		end
		local root = modelValue :: Model
		local variants = root:FindFirstChild("UpgradeVariants") :: Folder
		for levelIndex = 1, #(selection :: CanonicalSelection).definition.levels do
			local variant = variants:FindFirstChild(string.format("Level%02d", levelIndex)) :: Model
			local body = variant:FindFirstChild("Body") :: Part
			body.Transparency = if levelIndex == (selection :: CanonicalSelection).levelIndex then 0 else 1
		end
		return validateCore(configurationValue, definitionValue, levelValue, modelValue, "Live", operation)
	end)
end

return table.freeze(TowerModelContract)
