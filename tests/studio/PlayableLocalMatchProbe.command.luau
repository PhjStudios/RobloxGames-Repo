--!strict

-- Execute in the Match play session's Client DataModel. The returned checkpoint
-- can be compared across Ready, Playing, Results, and replay without adding a
-- production diagnostics remote.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ContentSelection = require(ReplicatedStorage.Shared.config.ContentSelection)
local Enemies = require(ReplicatedStorage.Shared.config.Enemies)
local Towers = require(ReplicatedStorage.Shared.config.Towers)

local player = Players.LocalPlayer
if player == nil then
	error("[ATD_PLAYABLE_STUDIO][code=LOCAL_PLAYER_MISSING]", 0)
end
local playerGui = player:FindFirstChildOfClass("PlayerGui")
local gui = if playerGui == nil then nil else playerGui:FindFirstChild("ATDPlayableMatch")
local world = Workspace:FindFirstChild("_ATDPlayablePresentation")
local templates = ReplicatedStorage:FindFirstChild(ContentSelection.PLAYABLE_TEMPLATE_ROOT_NAME)
if gui == nil or not gui:IsA("ScreenGui") then
	error("[ATD_PLAYABLE_STUDIO][code=GUI_MISSING]", 0)
end
if world == nil or not world:IsA("Folder") then
	error("[ATD_PLAYABLE_STUDIO][code=WORLD_PRESENTATION_MISSING]", 0)
end
if templates == nil or not templates:IsA("Folder") then
	error("[ATD_PLAYABLE_STUDIO][code=CONTENT_TEMPLATES_MISSING]", 0)
end
if
	templates:GetAttribute("ATDContentContract") ~= ContentSelection.PLAYABLE_TEMPLATE_CONTRACT_VERSION
	or templates:GetAttribute("ContentVersion") ~= ContentSelection.CONTENT_VERSION
then
	error("[ATD_PLAYABLE_STUDIO][code=CONTENT_ROOT_IDENTITY_INVALID]", 0)
end

local root = gui:FindFirstChild("Root")
local top = if root == nil then nil else root:FindFirstChild("TopHUD")
local ready = if root == nil then nil else root:FindFirstChild("ReadyOverlay")
local results = if root == nil then nil else root:FindFirstChild("ResultsOverlay")
local towerPanel = if root == nil then nil else root:FindFirstChild("TowerPanel")
local towers = world:FindFirstChild("Towers")
local enemies = world:FindFirstChild("Enemies")
local effects = world:FindFirstChild("AttackEffects")
if
	root == nil
	or top == nil
	or ready == nil
	or results == nil
	or towerPanel == nil
	or towers == nil
	or enemies == nil
	or effects == nil
then
	error("[ATD_PLAYABLE_STUDIO][code=PRESENTATION_CONTRACT_INCOMPLETE]", 0)
end

local readyVisible = (ready :: GuiObject).Visible
local resultsVisible = (results :: GuiObject).Visible
local state = if resultsVisible then "Results" elseif readyVisible then "Ready" else "Playing"
local resultTitle = results:FindFirstChild("ResultTitle")
local resultText = if resultTitle ~= nil and resultTitle:IsA("TextLabel") then resultTitle.Text else ""
local result = if string.find(resultText, "VICTORY", 1, true) ~= nil
	then "Victory"
	elseif string.find(resultText, "DEFEAT", 1, true) ~= nil then "Defeat"
	else "None"

local wave = top:FindFirstChild("Wave")
local base = top:FindFirstChild("BaseHealth")
local cash = top:FindFirstChild("BattleCash")
if
	wave == nil
	or not wave:IsA("TextLabel")
	or base == nil
	or not base:IsA("TextButton")
	or cash == nil
	or not cash:IsA("TextLabel")
then
	error("[ATD_PLAYABLE_STUDIO][code=HUD_CONTRACT_INCOMPLETE]", 0)
end

local expectedTemplateNames: { [string]: boolean } = {}
for _, tower in Towers do
	expectedTemplateNames[tower.modelAssetKey] = true
end
for _, enemy in Enemies do
	expectedTemplateNames[enemy.modelAssetKey] = true
end

local templateNames: { string } = {}
for _, child in templates:GetChildren() do
	if not child:IsA("Model") then
		error("[ATD_PLAYABLE_STUDIO][code=CONTENT_TEMPLATE_CLASS_INVALID]", 0)
	end
	if not expectedTemplateNames[child.Name] then
		error("[ATD_PLAYABLE_STUDIO][code=CONTENT_TEMPLATE_UNEXPECTED]", 0)
	end
	if
		child:GetAttribute("ATDContentContract") ~= ContentSelection.PLAYABLE_TEMPLATE_CONTRACT_VERSION
		or child:GetAttribute("AssetKey") ~= child.Name
	then
		error("[ATD_PLAYABLE_STUDIO][code=CONTENT_TEMPLATE_IDENTITY_INVALID]", 0)
	end
	table.insert(templateNames, child.Name)
end
table.sort(templateNames)
local expectedCount = 0
for _ in expectedTemplateNames do
	expectedCount += 1
end
if #templateNames ~= expectedCount then
	error("[ATD_PLAYABLE_STUDIO][code=CONTENT_TEMPLATE_COUNT_INVALID]", 0)
end
for _, descendant in world:GetDescendants() do
	if descendant:IsA("BaseScript") then
		error("[ATD_PLAYABLE_STUDIO][code=PRESENTATION_SCRIPT_LEAK]", 0)
	end
end

local towerCount = #towers:GetChildren()
local enemyCount = #enemies:GetChildren()

local report = table.freeze({
	state = state,
	result = result,
	waveText = wave.Text,
	baseText = base.Text,
	cashText = cash.Text,
	towerPanelVisible = (towerPanel :: GuiObject).Visible,
	towerCount = towerCount,
	enemyCount = enemyCount,
	attackEffectCount = #effects:GetChildren(),
	templateNames = table.freeze(templateNames),
})
print(`[ATD_PLAYABLE_STUDIO][status=PASS][state={state}][result={result}][towers={towerCount}][enemies={enemyCount}]`)
return report
