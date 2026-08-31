--!strict

-- Run in the Match place's Edit DataModel. These lightweight client-visible
-- templates are Studio-owned content; Rojo owns only their symbolic identities.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONTRACT = "playable-local-match-v1"
local FOLDER_NAME = "ATDPlayableTemplates"

local COLORS = {
	dart = Color3.fromRGB(72, 178, 112),
	rapid = Color3.fromRGB(72, 148, 220),
	guard = Color3.fromRGB(225, 157, 66),
	worker = Color3.fromRGB(122, 75, 48),
	scout = Color3.fromRGB(208, 102, 66),
	soldier = Color3.fromRGB(92, 58, 47),
	queen = Color3.fromRGB(124, 65, 150),
}

local function part(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	shape: Enum.PartType?
): Part
	local value = Instance.new("Part")
	value.Name = name
	value.Size = size
	value.CFrame = cframe
	value.Color = color
	value.Material = Enum.Material.SmoothPlastic
	value.Shape = shape or Enum.PartType.Block
	value.Anchored = true
	value.CanCollide = false
	value.CanQuery = false
	value.CanTouch = false
	value.CastShadow = false
	value.TopSurface = Enum.SurfaceType.Smooth
	value.BottomSurface = Enum.SurfaceType.Smooth
	value.Parent = model
	return value
end

local function beginModel(folder: Folder, assetKey: string, contentKind: string, definitionId: string): Model
	local existing = folder:FindFirstChild(assetKey)
	if existing ~= nil then
		error("[ATD_PLAYABLE_CONTENT][code=STAGED_NAME_CONFLICT]", 0)
	end
	local model = Instance.new("Model")
	model.Name = assetKey
	model:SetAttribute("ATDContentContract", CONTRACT)
	model:SetAttribute("AssetKey", assetKey)
	model:SetAttribute("ContentKind", contentKind)
	model:SetAttribute("DefinitionId", definitionId)
	model.Parent = folder
	return model
end

local function tower(
	folder: Folder,
	assetKey: string,
	towerId: string,
	color: Color3,
	scale: number,
	muzzleCount: number
)
	local model = beginModel(folder, assetKey, "TowerModel", towerId)
	local root = part(model, "Root", Vector3.new(2.4, 0.5, 2.4) * scale, CFrame.new(0, 0.25 * scale, 0), color)
	part(model, "Body", Vector3.new(1.35, 1.35, 1.35) * scale, CFrame.new(0, 1.1 * scale, 0), color, Enum.PartType.Ball)
	part(
		model,
		"Head",
		Vector3.new(1.05, 0.85, 1.05) * scale,
		CFrame.new(0, 1.45 * scale, -0.8 * scale),
		color,
		Enum.PartType.Ball
	)
	for index = 1, muzzleCount do
		local offset = (index - (muzzleCount + 1) * 0.5) * 0.38 * scale
		local muzzle = part(
			model,
			`Muzzle{index}`,
			Vector3.new(0.22, 0.22, 1.1) * scale,
			CFrame.new(offset, 1.48 * scale, -1.48 * scale),
			Color3.fromRGB(238, 238, 216)
		)
		muzzle:SetAttribute("MuzzleIndex", index)
	end
	model.PrimaryPart = root
	model:PivotTo(CFrame.new())
end

local function enemy(folder: Folder, assetKey: string, enemyId: string, color: Color3, scale: number, role: string)
	local model = beginModel(folder, assetKey, "EnemyModel", enemyId)
	model:SetAttribute("Role", role)
	local thorax = part(model, "Thorax", Vector3.new(1.2, 1, 1.45) * scale, CFrame.new(), color, Enum.PartType.Ball)
	part(model, "Head", Vector3.new(0.9, 0.8, 0.9) * scale, CFrame.new(0, 0, -1.05 * scale), color, Enum.PartType.Ball)
	part(
		model,
		"Abdomen",
		Vector3.new(1.35, 1.1, 1.65) * scale,
		CFrame.new(0, 0, 1.25 * scale),
		color,
		Enum.PartType.Ball
	)
	for side = -1, 1, 2 do
		for row = -1, 1 do
			part(
				model,
				`Leg{side}_{row}`,
				Vector3.new(0.16, 0.16, 1.05) * scale,
				CFrame.new(0.58 * side * scale, -0.38 * scale, row * 0.55 * scale)
					* CFrame.Angles(0, 0, math.rad(55 * side)),
				color
			)
		end
	end
	model.PrimaryPart = thorax
	model:PivotTo(CFrame.new())
end

local expectedNames: { [string]: boolean } = {
	["tower.dart-ant-model"] = true,
	["tower.rapid-ant-model"] = true,
	["tower.guard-ant-model"] = true,
	["enemy.worker-ant-model"] = true,
	["enemy.scout-ant-model"] = true,
	["enemy.soldier-ant-model"] = true,
	["enemy.queen-ant-model"] = true,
}

local directMatches: { Instance } = {}
for _, child in ReplicatedStorage:GetChildren() do
	if child.Name == FOLDER_NAME then
		table.insert(directMatches, child)
	end
end
if #directMatches > 1 then
	error("[ATD_PLAYABLE_CONTENT][code=TARGET_DUPLICATE_CONFLICT]", 0)
end
local existing = directMatches[1]
if existing ~= nil then
	if
		not existing:IsA("Folder")
		or existing:GetAttribute("ATDContentContract") ~= CONTRACT
		or existing:GetAttribute("ContentVersion") ~= 1
	then
		error("[ATD_PLAYABLE_CONTENT][code=TARGET_CONTRACT_CONFLICT]", 0)
	end
end

local staged = Instance.new("Folder")
staged.Name = FOLDER_NAME
staged:SetAttribute("ATDContentContract", CONTRACT)
staged:SetAttribute("ContentVersion", 1)
local authored = pcall(function()
	tower(staged, "tower.dart-ant-model", "tower:dart-ant", COLORS.dart, 1, 1)
	tower(staged, "tower.rapid-ant-model", "tower:rapid-ant", COLORS.rapid, 0.9, 2)
	tower(staged, "tower.guard-ant-model", "tower:guard-ant", COLORS.guard, 1.25, 1)
	enemy(staged, "enemy.worker-ant-model", "enemy:worker-ant", COLORS.worker, 1, "Basic")
	enemy(staged, "enemy.scout-ant-model", "enemy:scout-ant", COLORS.scout, 0.72, "Fast")
	enemy(staged, "enemy.soldier-ant-model", "enemy:soldier-ant", COLORS.soldier, 1.35, "Tank")
	enemy(staged, "enemy.queen-ant-model", "enemy:garden-queen", COLORS.queen, 2.15, "Boss")
end)
if not authored then
	staged:Destroy()
	error("[ATD_PLAYABLE_CONTENT][code=STAGING_FAILED]", 0)
end

local stagedChildren = staged:GetChildren()
local seen: { [string]: boolean } = {}
if #stagedChildren ~= 7 then
	staged:Destroy()
	error("[ATD_PLAYABLE_CONTENT][code=STAGED_CATALOG_INVALID]", 0)
end
for _, child in stagedChildren do
	if not child:IsA("Model") or not expectedNames[child.Name] or seen[child.Name] then
		staged:Destroy()
		error("[ATD_PLAYABLE_CONTENT][code=STAGED_CATALOG_INVALID]", 0)
	end
	seen[child.Name] = true
end

-- The old contract-owned catalog remains untouched until every replacement has
-- been authored and checked. Parenting cannot yield; a failed swap restores the
-- detached old catalog and removes the staged copy.
local published = pcall(function()
	staged.Parent = ReplicatedStorage
	if existing ~= nil then
		existing.Parent = nil
	end
end)
if not published then
	staged.Parent = nil
	if existing ~= nil and existing.Parent == nil then
		existing.Parent = ReplicatedStorage
	end
	staged:Destroy()
	error("[ATD_PLAYABLE_CONTENT][code=PUBLISH_FAILED]", 0)
end
if existing ~= nil then
	existing:Destroy()
end

local report = {
	contract = CONTRACT,
	templateCount = #staged:GetChildren(),
	towerCount = 3,
	enemyCount = 4,
}
print(`[ATD_PLAYABLE_CONTENT][status=AUTHORED][templates={report.templateCount}]`)
return table.freeze(report)
