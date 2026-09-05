--!strict

local TextService = game:GetService("TextService")
local TextLayout = { MIN_BODY_SIZE = 16, MIN_TOUCH_SIZE = 44, MAX_ROWS = 128 }

-- This fallback is a conservative deterministic layout estimate, not font-render evidence.
function TextLayout.height(text: string, textSize: number, width: number): number
	local columns = math.max(1, math.floor(math.max(1, width - 16) / (textSize * 0.62)))
	local lines = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		lines += math.max(1, math.ceil((utf8.len(line) or #line) / columns))
	end
	return math.ceil(lines * textSize * 1.3 + 12)
end

function TextLayout.scale(object: Instance): number
	local scale = 1
	local cursor: Instance? = object
	for _ = 1, 32 do
		if cursor == nil or cursor:IsA("ScreenGui") then
			break
		end
		if cursor:IsA("GuiObject") then
			local transform = cursor:FindFirstChildOfClass("UIScale")
			if transform then
				scale *= (transform :: UIScale).Scale
			end
		end
		cursor = cursor.Parent
	end
	return if scale == scale and scale >= 0.25 and scale <= 4 then scale else 1
end

function TextLayout.measure(
	text: string,
	textSize: number,
	width: number,
	font: Enum.Font?,
	physicalScale: number?
): number
	local scale = physicalScale or 1
	if scale ~= scale or scale < 0.25 or scale > 4 then
		scale = 1
	end
	local height = TextLayout.height(text, textSize, width)
	pcall(function()
		-- This must run in the rendering client: Studio command contexts may not
		-- apply that client's live preferred text size to TextService measurements.
		-- Preferred font sizing is applied after UIScale and is not linear. Measure
		-- the physical font/width first, then convert the result to layout units.
		local bounds = TextService:GetTextSize(
			text,
			textSize * scale,
			font or Enum.Font.Gotham,
			Vector2.new(math.max(1, (width - 16) * scale), 10_000)
		)
		height = math.max(height, math.ceil(bounds.Y / scale + 16))
	end)
	return height
end

function TextLayout.plan(
	rows: { { height: number } },
	maximumHeight: number
): { height: number, canvasHeight: number, offsets: { number } }
	local offsets = {}
	local cursor = 8
	for index, row in rows do
		if index > TextLayout.MAX_ROWS then
			break
		end
		offsets[index] = cursor
		cursor += math.max(1, row.height) + 8
	end
	return { height = math.max(44, math.min(cursor, maximumHeight)), canvasHeight = cursor, offsets = offsets }
end

function TextLayout.reflow(panel: GuiObject, width: number, maximumHeight: number, minimumTouchHeight: number?)
	local physicalScale = TextLayout.scale(panel)
	local touchHeight =
		math.max(TextLayout.MIN_TOUCH_SIZE / physicalScale, minimumTouchHeight or TextLayout.MIN_TOUCH_SIZE)
	local originalHeight = if panel.Size.Y.Scale > 0 then maximumHeight else panel.Size.Y.Offset
	local scroll: ScrollingFrame
	if panel:IsA("ScrollingFrame") then
		scroll = panel
	else
		local existing = panel:FindFirstChild("ATDReadableContent")
		if existing ~= nil and existing:IsA("ScrollingFrame") then
			scroll = existing
		else
			scroll = Instance.new("ScrollingFrame")
			scroll.Name = "ATDReadableContent"
			scroll.BorderSizePixel = 0
			scroll.BackgroundTransparency = 1
			scroll.ScrollBarThickness = 6
			scroll.ScrollingDirection = Enum.ScrollingDirection.Y
			scroll.Size = UDim2.fromScale(1, 1)
			scroll.ZIndex = panel.ZIndex
			scroll.Parent = panel
			for _, child in panel:GetChildren() do
				if child ~= scroll and child:IsA("GuiObject") then
					child.Parent = scroll
				end
			end
		end
	end
	local items = {}
	local listLayout = scroll:FindFirstChildOfClass("UIListLayout")
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			local order = child:GetAttribute("ATDFlowOrder")
			if type(order) ~= "number" then
				order = if listLayout ~= nil
					then child.LayoutOrder
					else child.Position.Y.Scale * math.max(44, originalHeight) + child.Position.Y.Offset
			end
			table.insert(items, { control = child, order = order })
		end
	end
	table.sort(items, function(left, right)
		return left.order < right.order
	end)
	local rows = {}
	local currentRow: any = nil
	for _, item in items do
		local child = item.control
		local height = child.Size.Y.Offset
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			child.TextScaled = false
			child.TextWrapped = true
			child.TextSize = math.max(TextLayout.MIN_BODY_SIZE, child.TextSize)
			local childWidth = math.max(44, width * child.Size.X.Scale + child.Size.X.Offset)
			height = TextLayout.measure(child.Text, child.TextSize, childWidth, child.Font, physicalScale)
			if child:IsA("TextButton") then
				height = math.max(touchHeight, height)
			end
		end
		if currentRow == nil or item.order ~= currentRow.order then
			currentRow = { order = item.order, height = height, items = {} }
			table.insert(rows, currentRow)
		end
		currentRow.height = math.max(currentRow.height, height)
		table.insert(currentRow.items, child)
	end
	local layout = TextLayout.plan(rows, maximumHeight)
	for index, row in rows do
		if index > TextLayout.MAX_ROWS then
			break
		end
		for _, child in row.items do
			child.AnchorPoint = Vector2.new(child.AnchorPoint.X, 0)
			child.Position = UDim2.new(child.Position.X.Scale, child.Position.X.Offset, 0, layout.offsets[index])
			child.Size = UDim2.new(child.Size.X.Scale, child.Size.X.Offset, 0, row.height)
		end
	end
	scroll.CanvasSize = UDim2.fromOffset(0, layout.canvasHeight)
	if not panel:IsA("ScrollingFrame") then
		panel.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, layout.height)
	end
end

return table.freeze(TextLayout)
