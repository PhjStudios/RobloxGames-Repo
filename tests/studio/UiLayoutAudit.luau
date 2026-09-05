--!strict

-- Read-only, runtime-only Studio Client audit. Inject this source through the
-- authorized Studio tool; it is not mapped into a production or Test place.
-- Geometry and hit tests identify review candidates, not human acceptance.
return function(options: any?)
	local RunService = game:GetService("RunService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local GuiService = game:GetService("GuiService")
	assert(RunService:IsStudio() and RunService:IsRunning() and RunService:IsClient(), "Studio Client runtime required")
	assert(game.GameId == 10764687717 and game.CreatorId == 35420107, "staging ownership mismatch")
	assert(game.CreatorType == Enum.CreatorType.Group, "staging owner type mismatch")
	local role = ReplicatedStorage:GetAttribute("ATDPlaceRole")
	assert(
		(role == "Lobby" and game.PlaceId == 140661668701496) or (role == "Match" and game.PlaceId == 104415140644510),
		"staging place role mismatch"
	)
	options = options or {}
	assert(type(options) == "table", "audit options must be a table")
	for key in options do
		assert(key == "rootName", "unknown audit option")
	end
	local expectedName = if role == "Lobby" then "ATDLobbyGui" else "ATDPlayableMatch"
	assert(options.rootName == nil or options.rootName == expectedName, "role GUI mismatch")
	local player = Players.LocalPlayer
	assert(player ~= nil, "local client required")
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	assert(playerGui ~= nil, "PlayerGui unavailable")
	local gui = playerGui:FindFirstChild(expectedName)
	assert(gui ~= nil and gui:IsA("ScreenGui"), "expected ATD ScreenGui unavailable")
	local root = gui:FindFirstChild("Root")
	assert(root ~= nil and root:IsA("GuiObject"), "expected ATD Root unavailable")
	local MAX_CONTROLS, MAX_INSTANCES, MAX_DEPTH = 512, 4096, 32
	local EPSILON = 1
	local TOUCH_EPSILON = 0.01
	local MAX_PLACEHOLDER_BYTES = 2048
	local function rect(object: GuiObject): any
		local position, size = object.AbsolutePosition, object.AbsoluteSize
		return { x = position.X, y = position.Y, width = size.X, height = size.Y }
	end
	local function intersect(a: any, b: any): any
		local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
		return {
			x = x,
			y = y,
			width = math.max(0, math.min(a.x + a.width, b.x + b.width) - x),
			height = math.max(0, math.min(a.y + a.height, b.y + b.height) - y),
		}
	end
	local function contains(outer: any, inner: any): boolean
		return inner.x >= outer.x - EPSILON
			and inner.y >= outer.y - EPSILON
			and inner.x + inner.width <= outer.x + outer.width + EPSILON
			and inner.y + inner.height <= outer.y + outer.height + EPSILON
	end
	local function boundedName(value: string): string
		-- Only source-owned instance names are included. No Text, profiles, player
		-- names, full DataModel paths, or external GUI names are collected.
		return string.sub(string.gsub(value, "[^%w_%-]", "_"), 1, 64)
	end
	local function path(object: Instance?): string?
		if object == nil then
			return nil
		end
		if object ~= gui and not object:IsDescendantOf(gui) then
			return "ExternalGuiObject"
		end
		local segments = {}
		local cursor: Instance? = object
		for _ = 1, MAX_DEPTH do
			if cursor == nil or cursor == gui then
				break
			end
			table.insert(segments, 1, boundedName(cursor.Name))
			cursor = cursor.Parent
		end
		return table.concat(segments, "/")
	end
	local function ancestryVisible(object: GuiObject): boolean
		local cursor: Instance? = object
		for _ = 1, MAX_DEPTH do
			if cursor == gui then
				return gui.Enabled
			end
			if cursor == nil or (cursor:IsA("GuiObject") and not cursor.Visible) then
				return false
			end
			cursor = cursor.Parent
		end
		return false
	end
	local safeRoot = rect(root)
	local selected = GuiService.SelectedObject
	local focusedTextBox = game:GetService("UserInputService"):GetFocusedTextBox()
	local controls, textLabels, stack = {}, {}, { gui :: Instance }
	local visited, hiddenControls, hitTestFailures = 0, 0, 0
	local counts = {
		WithinCurrentViewport = 0,
		ScrollableOffViewport = 0,
		ClippedWithoutScroll = 0,
		NoDrawableArea = 0,
		textOverflowCandidates = 0,
		labelOverflowCandidates = 0,
		undersizedTouchControls = 0,
		placeholdersNeedingVisualReview = 0,
		overlayCandidates = 0,
		offSafeRoot = 0,
		disabledControls = 0,
	}
	local truncated = false
	while #stack > 0 do
		if visited >= MAX_INSTANCES or #controls >= MAX_CONTROLS then
			truncated = true
			break
		end
		local current = table.remove(stack) :: Instance
		visited += 1
		for _, child in current:GetChildren() do
			if #stack + visited >= MAX_INSTANCES then
				truncated = true
				break
			end
			table.insert(stack, child)
		end
		if current:IsA("TextLabel") and ancestryVisible(current) then
			if #textLabels >= MAX_CONTROLS then
				truncated = true
				break
			end
			local labelRect = rect(current)
			local overflow = not current.TextFits
				or current.TextBounds.X > labelRect.width + EPSILON
				or current.TextBounds.Y > labelRect.height + EPSILON
			counts.labelOverflowCandidates += if overflow then 1 else 0
			table.insert(textLabels, {
				path = path(current),
				rect = labelRect,
				fits = current.TextFits,
				overflowCandidate = overflow,
				scaled = current.TextScaled,
				textSize = current.TextSize,
			})
		end
		if not current:IsA("GuiButton") and not current:IsA("TextBox") then
			continue
		end
		local control = current :: GuiObject
		if not ancestryVisible(control) then
			hiddenControls += 1
			continue
		end
		local bounds = rect(control)
		local clippedRect = intersect(bounds, safeRoot)
		local clips, scrolls = {}, {}
		local enabledScrollBelow, fixedClip, scrollClipped = false, false, false
		local ancestor: Instance? = control.Parent
		for _ = 1, MAX_DEPTH do
			if ancestor == nil or ancestor == gui then
				break
			end
			if ancestor:IsA("GuiObject") then
				local ancestorRect = rect(ancestor)
				local scrolling = ancestor:IsA("ScrollingFrame")
				if scrolling then
					local scrollingFrame = ancestor :: ScrollingFrame
					local window = scrollingFrame.AbsoluteWindowSize
					ancestorRect.width, ancestorRect.height = window.X, window.Y
					table.insert(scrolls, {
						path = path(ancestor),
						rect = ancestorRect,
						canvasPosition = { x = scrollingFrame.CanvasPosition.X, y = scrollingFrame.CanvasPosition.Y },
						canvasSize = {
							x = scrollingFrame.AbsoluteCanvasSize.X,
							y = scrollingFrame.AbsoluteCanvasSize.Y,
						},
						enabled = scrollingFrame.ScrollingEnabled,
						direction = scrollingFrame.ScrollingDirection.Name,
						viewportOutsideSafeRoot = not contains(safeRoot, ancestorRect),
					})
					if scrollingFrame.ScrollingEnabled then
						enabledScrollBelow = true
						if not contains(ancestorRect, bounds) then
							scrollClipped = true
						end
					end
				end
				if ancestor.ClipsDescendants or scrolling then
					clippedRect = intersect(clippedRect, ancestorRect)
					if not contains(ancestorRect, bounds) then
						table.insert(clips, { path = path(ancestor), scrolling = scrolling, rect = ancestorRect })
						if not enabledScrollBelow then
							fixedClip = true
						end
					end
				end
			end
			ancestor = ancestor.Parent
		end
		local offRoot = not contains(safeRoot, bounds)
		local clipped = not contains(clippedRect, bounds)
		local classification = "WithinCurrentViewport"
		if bounds.width <= 0 or bounds.height <= 0 then
			classification = "NoDrawableArea"
		elseif clipped then
			classification = if enabledScrollBelow
					and not fixedClip
					and scrollClipped
				then "ScrollableOffViewport"
				else "ClippedWithoutScroll"
		end
		counts[classification] += 1
		counts.offSafeRoot += if offRoot then 1 else 0
		local enabled = control.Active and (not control:IsA("TextBox") or control.TextEditable)
		local undersized = enabled and (bounds.width < 44 - TOUCH_EPSILON or bounds.height < 44 - TOUCH_EPSILON)
		counts.undersizedTouchControls += if undersized then 1 else 0
		counts.disabledControls += if enabled then 0 else 1
		local row: any = {
			path = path(control),
			class = control.ClassName,
			ancestryVisible = true,
			rect = bounds,
			visibleRect = clippedRect,
			classification = classification,
			offSafeRoot = offRoot,
			clippedNow = clipped,
			fixedContainerClip = fixedClip,
			enabled = enabled,
			undersizedTouchCandidate = undersized,
			selectable = control.Selectable,
			selected = selected == control,
			textBoxFocused = focusedTextBox == control,
			selectionOrder = control.SelectionOrder,
			layoutOrder = control.LayoutOrder,
			zIndex = control.ZIndex,
			navigation = {
				up = path(control.NextSelectionUp),
				down = path(control.NextSelectionDown),
				left = path(control.NextSelectionLeft),
				right = path(control.NextSelectionRight),
			},
			clipAncestors = clips,
			scrollAncestors = scrolls,
			scrollReachability = if #scrolls > 0 then "RequiresInputVerification" else "NotApplicable",
		}
		if control:IsA("TextButton") or control:IsA("TextBox") then
			local textControl = control :: TextButton
			local textBounds = textControl.TextBounds
			-- Wrapped TextBounds can be clipped to the control's rectangle. The
			-- engine's TextFits result is also required to detect omitted lines.
			local textOverflow = not textControl.TextFits
				or textBounds.X > bounds.width + EPSILON
				or textBounds.Y > bounds.height + EPSILON
			counts.textOverflowCandidates += if textOverflow then 1 else 0
			row.text = {
				bounds = { x = textBounds.X, y = textBounds.Y },
				size = textControl.TextSize,
				scaled = textControl.TextScaled,
				wrapped = textControl.TextWrapped,
				fits = textControl.TextFits,
				overflowCandidate = textOverflow,
			}
			local key = control:GetAttribute("ATDLocalizationText")
			if type(key) == "string" and #key <= 128 and string.match(key, "^[%w_.]+$") then
				row.text.localizationKey = key
			end
			if control:IsA("TextBox") then
				local placeholder = control.PlaceholderText
				local bounded = #placeholder <= MAX_PLACEHOLDER_BYTES
				row.text.placeholder = {
					characterCount = if bounded then utf8.len(placeholder) else nil,
					byteCount = math.min(#placeholder, MAX_PLACEHOLDER_BYTES),
					truncated = not bounded,
					notMeasured = true,
					requiresVisualReview = #placeholder > 0,
				}
				counts.placeholdersNeedingVisualReview += if #placeholder > 0 then 1 else 0
			end
		end
		local overlays, seen = {}, {}
		if clippedRect.width > 1 and clippedRect.height > 1 then
			for _, horizontal in { 0.25, 0.5, 0.75 } do
				local ok, hits = pcall(function()
					return playerGui:GetGuiObjectsAtPosition(
						math.floor(clippedRect.x + clippedRect.width * horizontal),
						math.floor(clippedRect.y + clippedRect.height * 0.5)
					)
				end)
				if not ok then
					hitTestFailures += 1
					continue
				end
				for index, hit in hits do
					if index > 64 or hit == control or hit:IsDescendantOf(control) then
						break
					end
					if hit:IsAncestorOf(control) or not hit.Active or seen[hit] then
						continue
					end
					seen[hit] = true
					table.insert(overlays, { path = path(hit), class = hit.ClassName })
					break
				end
			end
		end
		row.activeOverlayCandidates = overlays
		counts.overlayCandidates += if #overlays > 0 then 1 else 0
		table.insert(controls, row)
	end
	table.sort(controls, function(a, b)
		return a.path < b.path
	end)
	local camera = workspace.CurrentCamera
	return {
		evidence = "Studio-emulated",
		context = "Client",
		role = role,
		rootName = expectedName,
		rootEnabled = gui.Enabled,
		safeRoot = safeRoot,
		viewport = if camera then { x = camera.ViewportSize.X, y = camera.ViewportSize.Y } else nil,
		selectedPath = path(selected),
		focusedTextBoxPath = path(focusedTextBox),
		visitedInstances = visited,
		hiddenInteractiveControls = hiddenControls,
		visibleInteractiveControls = #controls,
		truncated = truncated,
		hitTestFailures = hitTestFailures,
		counts = counts,
		controls = controls,
		textLabels = textLabels,
		limits = {
			controls = MAX_CONTROLS,
			textLabels = MAX_CONTROLS,
			instances = MAX_INSTANCES,
			ancestryDepth = MAX_DEPTH,
			hitSamplesPerControl = 3,
			placeholderBytes = MAX_PLACEHOLDER_BYTES,
			touchMinimumPixels = 44,
			touchTolerancePixels = TOUCH_EPSILON,
			geometryTolerancePixels = EPSILON,
		},
		mutations = 0,
		connectionsCreated = 0,
		interpretation = "Current geometry only. Scroll-hidden content requires scrolling/focus verification; overlay hits are candidates. TextBox placeholder bounds are not measured: verify them visually in the rendering client at the current preferences and scale. No clipping is not first-session, input, physical-device, or human readability acceptance.",
	}
end
