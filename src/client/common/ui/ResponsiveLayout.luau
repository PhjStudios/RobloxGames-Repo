--!strict

export type Mode = "Compact" | "Standard" | "TenFoot"

export type Layout = {
	mode: Mode,
	logicalWidth: number,
	logicalHeight: number,
	safeMargin: number,
	headerHeight: number,
	navigationWidth: number,
	bottomNavigationHeight: number,
	contentWidth: number,
	contentHeight: number,
	panelPadding: number,
	cardWidth: number,
	inventoryColumns: number,
	touchTarget: number,
	baseTextSize: number,
	titleTextSize: number,
	modalWidth: number,
	toastWidth: number,
}

local MIN_VIEWPORT_WIDTH = 240
-- CoreUISafeInsets can reduce a supported 375px landscape viewport below 320px.
local MIN_VIEWPORT_HEIGHT = 240
local MAX_VIEWPORT_AXIS = 16_384
local MIN_UI_SCALE = 0.75
local MAX_UI_SCALE = 1.25
local MIN_TEXT_SCALE = 0.85
local MAX_TEXT_SCALE = 1.5
local MIN_CARD_WIDTH = 164
local MAX_COLUMNS = 6

local ResponsiveLayout = {
	MIN_VIEWPORT_WIDTH = MIN_VIEWPORT_WIDTH,
	MIN_VIEWPORT_HEIGHT = MIN_VIEWPORT_HEIGHT,
	MAX_VIEWPORT_AXIS = MAX_VIEWPORT_AXIS,
	MIN_UI_SCALE = MIN_UI_SCALE,
	MAX_UI_SCALE = MAX_UI_SCALE,
	MIN_TEXT_SCALE = MIN_TEXT_SCALE,
	MAX_TEXT_SCALE = MAX_TEXT_SCALE,
	MAX_COLUMNS = MAX_COLUMNS,
}

local function finiteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function boundedScale(value: unknown, minimum: number, maximum: number): number?
	if not finiteNumber(value) or (value :: number) < minimum or (value :: number) > maximum then
		return nil
	end
	return value :: number
end

function ResponsiveLayout.resolve(viewportValue: unknown, uiScaleValue: unknown?, textScaleValue: unknown?): Layout?
	if typeof(viewportValue) ~= "Vector2" then
		return nil
	end
	local viewport = viewportValue :: Vector2
	if
		not finiteNumber(viewport.X)
		or not finiteNumber(viewport.Y)
		or viewport.X < MIN_VIEWPORT_WIDTH
		or viewport.Y < MIN_VIEWPORT_HEIGHT
		or viewport.X > MAX_VIEWPORT_AXIS
		or viewport.Y > MAX_VIEWPORT_AXIS
	then
		return nil
	end

	local uiScale = if uiScaleValue == nil then 1 else boundedScale(uiScaleValue, MIN_UI_SCALE, MAX_UI_SCALE)
	local textScale = if textScaleValue == nil then 1 else boundedScale(textScaleValue, MIN_TEXT_SCALE, MAX_TEXT_SCALE)
	if uiScale == nil or textScale == nil then
		return nil
	end

	local logicalWidth = viewport.X / uiScale
	local logicalHeight = viewport.Y / uiScale
	local mode: Mode = "Standard"
	if logicalWidth < 720 or logicalHeight < 540 then
		mode = "Compact"
	elseif logicalWidth >= 1_700 and logicalHeight >= 850 then
		mode = "TenFoot"
	end

	local safeMargin = if mode == "TenFoot" then 36 elseif mode == "Compact" then 10 else 18
	local headerHeight = if mode == "TenFoot" then 92 elseif mode == "Compact" then 64 else 72
	local navigationWidth = if mode == "Compact" then 0 else (if mode == "TenFoot" then 252 else 208)
	local bottomNavigationHeight = if mode == "Compact" then 68 else 0
	local panelPadding = if mode == "TenFoot" then 24 elseif mode == "Compact" then 10 else 16
	local touchTarget = math.max(if mode == "TenFoot" then 64 else 48, math.ceil(44 / uiScale))
	local contentWidth = math.max(
		MIN_CARD_WIDTH,
		logicalWidth - safeMargin * 2 - navigationWidth - (if navigationWidth > 0 then panelPadding else 0)
	)
	local contentHeight =
		math.max(120, logicalHeight - safeMargin * 2 - headerHeight - bottomNavigationHeight - panelPadding)
	local availableGridWidth = math.max(MIN_CARD_WIDTH, contentWidth - panelPadding * 2)
	local gap = if mode == "TenFoot" then 16 else 10
	local columns = math.clamp(math.floor((availableGridWidth + gap) / (MIN_CARD_WIDTH + gap)), 1, MAX_COLUMNS)
	local cardWidth = math.floor((availableGridWidth - gap * (columns - 1)) / columns)
	local baseText = if mode == "TenFoot" then 23 elseif mode == "Compact" then 16 else 18
	local baseTextSize = math.clamp(math.floor(baseText * textScale + 0.5), 14, 34)

	return table.freeze({
		mode = mode,
		logicalWidth = logicalWidth,
		logicalHeight = logicalHeight,
		safeMargin = safeMargin,
		headerHeight = headerHeight,
		navigationWidth = navigationWidth,
		bottomNavigationHeight = bottomNavigationHeight,
		contentWidth = contentWidth,
		contentHeight = contentHeight,
		panelPadding = panelPadding,
		cardWidth = cardWidth,
		inventoryColumns = columns,
		touchTarget = touchTarget,
		baseTextSize = baseTextSize,
		titleTextSize = math.clamp(baseTextSize + 8, 20, 42),
		modalWidth = math.min(if mode == "Compact" then 420 else 560, contentWidth - panelPadding * 2),
		toastWidth = math.min(if mode == "Compact" then 360 else 440, contentWidth - panelPadding * 2),
	})
end

return table.freeze(ResponsiveLayout)
