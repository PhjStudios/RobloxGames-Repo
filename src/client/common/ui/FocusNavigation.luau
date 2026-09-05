--!strict

local FocusNavigation = { MAX_CONTROLS = 512 }

local function visibleWithin(object: GuiObject, root: Instance): boolean
	local cursor: Instance? = object
	while cursor ~= nil and cursor ~= root do
		if cursor:IsA("GuiObject") and not cursor.Visible then
			return false
		end
		cursor = cursor.Parent
	end
	return cursor == root
end

function FocusNavigation.validSelection(root: Instance?, value: unknown): GuiObject?
	local succeeded, target = pcall(function(): GuiObject?
		if root == nil or typeof(value) ~= "Instance" then
			return nil
		end
		local object = value :: Instance
		if
			not object:IsA("GuiObject")
			or not object.Selectable
			or not visibleWithin(object, root)
			or (root:IsA("ScreenGui") and not root.Enabled)
		then
			return nil
		end
		if (object:IsA("GuiButton") and object.Active) or (object:IsA("TextBox") and object.TextEditable) then
			return object
		end
		return nil
	end)
	return if succeeded then target else nil
end

function FocusNavigation.controls(root: Instance, scope: Instance?): { GuiObject }
	local result = {}
	for _, object in (scope or root):GetDescendants() do
		if
			((object:IsA("GuiButton") and object.Active) or (object:IsA("TextBox") and object.TextEditable))
			and object.Selectable
			and visibleWithin(object, root)
		then
			table.insert(result, object :: GuiObject)
		end
		if #result >= FocusNavigation.MAX_CONTROLS then
			break
		end
	end
	table.sort(result, function(left, right)
		if left.SelectionOrder ~= right.SelectionOrder then
			return left.SelectionOrder < right.SelectionOrder
		end
		return left:GetFullName() < right:GetFullName()
	end)
	return result
end

function FocusNavigation.next(controls: { GuiObject }, current: GuiObject?, direction: number): GuiObject?
	if #controls == 0 then
		return nil
	end
	local index = if current == nil then nil else table.find(controls, current)
	if index == nil then
		return if direction < 0 then controls[#controls] else controls[1]
	end
	return controls[(index - 1 + direction) % #controls + 1]
end

function FocusNavigation.link(controls: { GuiObject })
	for index, control in controls do
		control.NextSelectionUp = controls[(index - 2) % #controls + 1]
		control.NextSelectionDown = controls[index % #controls + 1]
		control.NextSelectionLeft = control.NextSelectionUp
		control.NextSelectionRight = control.NextSelectionDown
		-- GuiService.SelectedObject drives Roblox's native focus adornment.
		-- Do not parent an always-visible selection template to each button.
	end
end

function FocusNavigation.reveal(control: GuiObject?)
	if control == nil then
		return
	end
	local parent = control.Parent
	while parent ~= nil do
		if parent:IsA("ScrollingFrame") then
			local relativeX = control.AbsolutePosition.X - parent.AbsolutePosition.X
			if relativeX < 0 then
				parent.CanvasPosition =
					Vector2.new(math.max(0, parent.CanvasPosition.X + relativeX), parent.CanvasPosition.Y)
			elseif relativeX + control.AbsoluteSize.X > parent.AbsoluteSize.X then
				parent.CanvasPosition = Vector2.new(
					parent.CanvasPosition.X + relativeX + control.AbsoluteSize.X - parent.AbsoluteSize.X,
					parent.CanvasPosition.Y
				)
			end
			local relative = control.AbsolutePosition.Y - parent.AbsolutePosition.Y
			if relative < 0 then
				parent.CanvasPosition =
					Vector2.new(parent.CanvasPosition.X, math.max(0, parent.CanvasPosition.Y + relative))
			elseif relative + control.AbsoluteSize.Y > parent.AbsoluteSize.Y then
				parent.CanvasPosition = Vector2.new(
					parent.CanvasPosition.X,
					parent.CanvasPosition.Y + relative + control.AbsoluteSize.Y - parent.AbsoluteSize.Y
				)
			end
		end
		parent = parent.Parent
	end
end

return table.freeze(FocusNavigation)
