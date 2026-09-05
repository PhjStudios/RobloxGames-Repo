--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local KeyboardNavigation = {}

function KeyboardNavigation.ownsKey(key: Enum.KeyCode, includeAppBack: boolean?): boolean
	return key == Enum.KeyCode.Tab
		or key == Enum.KeyCode.F6
		or (includeAppBack == true and key == Enum.KeyCode.Backspace)
end

function KeyboardNavigation.appBackAllowed(menuIsOpen: boolean, focusedTextBox: TextBox?): boolean
	return not menuIsOpen and focusedTextBox == nil
end

function KeyboardNavigation.bind(guiName: string, callback: (string, boolean) -> (), includeAppBack: boolean?): () -> ()
	local actionName = "ATDKeyboardNavigation_" .. guiName
	local keys = { Enum.KeyCode.Tab, Enum.KeyCode.F6 }
	if includeAppBack then
		table.insert(keys, Enum.KeyCode.Backspace)
	end
	ContextActionService:BindActionAtPriority(actionName, function(_action, state, input)
		if state ~= Enum.UserInputState.Begin or GuiService.MenuIsOpen then
			return Enum.ContextActionResult.Pass
		end
		local player = Players.LocalPlayer
		local playerGui = if player == nil then nil else player:FindFirstChildOfClass("PlayerGui")
		local gui = if playerGui == nil then nil else playerGui:FindFirstChild(guiName)
		if gui == nil or not gui:IsA("ScreenGui") or not gui.Enabled then
			return Enum.ContextActionResult.Pass
		end
		local focused = UserInputService:GetFocusedTextBox()
		if includeAppBack and input.KeyCode == Enum.KeyCode.Backspace then
			if not KeyboardNavigation.appBackAllowed(GuiService.MenuIsOpen, focused) then
				return Enum.ContextActionResult.Pass
			end
			callback("Backspace", false)
			return Enum.ContextActionResult.Sink
		end
		if focused ~= nil then
			if not focused:IsDescendantOf(gui) then
				return Enum.ContextActionResult.Pass
			end
			focused:ReleaseFocus(false)
		end
		if KeyboardNavigation.ownsKey(input.KeyCode) then
			callback("Tab", false)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(keys))
	return function()
		ContextActionService:UnbindAction(actionName)
	end
end

return table.freeze(KeyboardNavigation)
