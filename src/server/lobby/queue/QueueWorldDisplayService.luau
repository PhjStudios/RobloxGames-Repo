--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local QueueProtocol = require(ReplicatedStorage.Shared.queue.QueueProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)

export type Anchor = {
	queueId: string,
	adornee: BasePart | Attachment,
}

export type Dependencies = {
	mapDisplayName: (string) -> string?,
	difficultyDisplayName: (string) -> string?,
	playerDisplayName: (number) -> string?,
}

export type ErrorCode =
	"INVALID_ANCHORS"
	| "DISPLAY_CONFLICT"
	| "INVALID_SNAPSHOT"
	| "QUEUE_NOT_FOUND"
	| "WRONG_STATE"
	| "CLEANED"
export type Operation = "new" | "update" | "cleanup"
export type DisplayError = { code: ErrorCode, operation: Operation }

type Display = {
	queueId: string,
	gui: BillboardGui,
	state: TextLabel,
	configuration: TextLabel,
	roster: TextLabel,
	blockers: TextLabel,
	portraits: Frame,
	portraitImages: { ImageLabel },
}

type LifecycleState = "Constructed" | "Initialized" | "Started" | "Shutdown"
type ServiceData = {
	displays: { [string]: Display },
	state: LifecycleState,
	updateCount: number,
	dependencies: Dependencies?,
}

local Methods = {}
Methods.__index = Methods
export type Service = typeof(setmetatable({} :: {}, Methods))

local DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ServiceData }
local DISPLAY_NAME = "ATDQueueWorldDisplay"
local SERVICE_NAME = "QueueWorldDisplayService"

local QueueWorldDisplayService = {
	DISPLAY_NAME = DISPLAY_NAME,
}

local function failure<T>(code: ErrorCode, operation: Operation)
	return Result.err(table.freeze({ code = code, operation = operation }))
end

local function requireData(value: unknown): ServiceData
	local data = if type(value) == "table" then DATA[value :: any] else nil
	if data == nil then
		error("[ATD_QUEUE_WORLD_DISPLAY][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function label(name: string, parent: Instance, height: number, order: number): TextLabel
	local instance = Instance.new("TextLabel")
	instance.Name = name
	instance.LayoutOrder = order
	instance.Size = UDim2.new(1, -16, 0, height)
	instance.BackgroundTransparency = 1
	instance.Font = Enum.Font.GothamMedium
	instance.TextColor3 = Color3.fromRGB(242, 246, 250)
	instance.TextStrokeColor3 = Color3.fromRGB(20, 24, 28)
	instance.TextStrokeTransparency = 0.55
	instance.TextSize = 18
	instance.TextWrapped = true
	instance.TextXAlignment = Enum.TextXAlignment.Left
	instance.Parent = parent
	return instance
end

local function createDisplay(anchor: Anchor): Display?
	if anchor.adornee:FindFirstChild(DISPLAY_NAME) ~= nil then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = DISPLAY_NAME
	gui.Adornee = anchor.adornee
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.Size = UDim2.fromOffset(360, 230)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(26, 31, 38)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(163, 190, 212)
	stroke.Thickness = 2
	stroke.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local title = label("Title", panel, 28, 1)
	title.Font = Enum.Font.GothamBold
	title.Text = "SQUAD QUEUE"
	local state = label("State", panel, 24, 2)
	local configuration = label("Configuration", panel, 42, 3)
	local roster = label("Roster", panel, 28, 4)
	local blockers = label("Readiness", panel, 30, 5)
	blockers.TextSize = 15

	local portraits = Instance.new("Frame")
	portraits.Name = "Portraits"
	portraits.LayoutOrder = 6
	portraits.Size = UDim2.new(1, -16, 0, 50)
	portraits.BackgroundTransparency = 1
	portraits.Parent = panel
	local portraitLayout = Instance.new("UIListLayout")
	portraitLayout.FillDirection = Enum.FillDirection.Horizontal
	portraitLayout.Padding = UDim.new(0, 8)
	portraitLayout.SortOrder = Enum.SortOrder.LayoutOrder
	portraitLayout.Parent = portraits

	gui.Parent = anchor.adornee
	return {
		queueId = anchor.queueId,
		gui = gui,
		state = state,
		configuration = configuration,
		roster = roster,
		blockers = blockers,
		portraits = portraits,
		portraitImages = {},
	}
end

local function clearPortraits(display: Display)
	for _, portrait in display.portraitImages do
		portrait:Destroy()
	end
	table.clear(display.portraitImages)
end

local function resolvedName(callback: ((any) -> string?)?, value: any, fallback: string): string
	if callback == nil then
		return fallback
	end
	local called, result = pcall(callback, value)
	return if called and type(result) == "string" and #result >= 1 and #result <= 64 then result else fallback
end

local function render(data: ServiceData, display: Display, snapshot: QueueProtocol.Snapshot)
	display.state.Text = `STATE: {string.upper(snapshot.state)}{if snapshot.publicStatus == nil
		then ""
		else ` · {snapshot.publicStatus}`}`
	local dependencies = data.dependencies
	local mapName = resolvedName(
		if dependencies == nil then nil else dependencies.mapDisplayName,
		snapshot.configuration.mapId,
		"Unavailable map"
	)
	local difficultyName = resolvedName(
		if dependencies == nil then nil else dependencies.difficultyDisplayName,
		snapshot.configuration.difficultyId,
		"Unavailable difficulty"
	)
	display.configuration.Text = `{mapName}\n{difficultyName} · {snapshot.configuration.privacy}`
	local captainName = if snapshot.captainUserId == nil
		then nil
		else resolvedName(
			if dependencies == nil then nil else dependencies.playerDisplayName,
			snapshot.captainUserId,
			"Player"
		)
	display.roster.Text = `PLAYERS {#snapshot.members}/{snapshot.configuration.maxPlayers}{if snapshot.captainUserId
			== nil
		then ""
		else ` · CAPTAIN {captainName}`}`
	local blockerCount = 0
	for _, member in snapshot.members do
		if member.readiness ~= "Ready" then
			blockerCount += 1
		end
	end
	display.blockers.Text = if #snapshot.members == 0
		then "Walk onto the zone or use the Queue screen."
		elseif blockerCount == 0 then "READY · Captain starts manually"
		else `{blockerCount} readiness blocker{if blockerCount == 1 then "" else "s"}`
	clearPortraits(display)
	for index, member in snapshot.members do
		local portrait = Instance.new("ImageLabel")
		portrait.Name = `Member{index}`
		portrait.LayoutOrder = index
		portrait.Size = UDim2.fromOffset(48, 48)
		portrait.BackgroundColor3 = if member.isCaptain
			then Color3.fromRGB(171, 126, 43)
			else Color3.fromRGB(58, 68, 79)
		portrait.BorderSizePixel = 0
		portrait.Image = `rbxthumb://type=AvatarHeadShot&id={member.userId}&w=150&h=150`
		portrait.Parent = display.portraits
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = portrait
		table.insert(display.portraitImages, portrait)
	end
end

function Methods.update(
	self: Service,
	queueIdValue: unknown,
	snapshotValue: unknown
): Result.Result<boolean, DisplayError>
	local data = requireData(self)
	if data.state == "Shutdown" then
		return failure("CLEANED", "update")
	end
	if type(queueIdValue) ~= "string" then
		return failure("QUEUE_NOT_FOUND", "update")
	end
	local display = data.displays[queueIdValue :: string]
	if display == nil then
		return failure("QUEUE_NOT_FOUND", "update")
	end
	local snapshot = QueueProtocol.validateSnapshot(snapshotValue)
	if not snapshot.ok or snapshot.value.queueId ~= queueIdValue then
		return failure("INVALID_SNAPSHOT", "update")
	end
	render(data, display, snapshot.value)
	data.updateCount += 1
	return Result.ok(true)
end

function Methods.cleanup(self: Service): Result.Result<boolean, DisplayError>
	local data = requireData(self)
	if data.state == "Shutdown" then
		return Result.ok(false)
	end
	for _, display in data.displays do
		clearPortraits(display)
		display.gui:Destroy()
	end
	table.clear(data.displays)
	data.state = "Shutdown"
	return Result.ok(true)
end

function Methods.getMetrics(self: Service)
	local data = requireData(self)
	local count = 0
	local portraits = 0
	for _, display in data.displays do
		count += 1
		portraits += #display.portraitImages
	end
	return table.freeze({
		state = data.state,
		displayCount = count,
		portraitCount = portraits,
		updateCount = data.updateCount,
	})
end

function Methods.getServiceDefinition(self: Service): ServiceLifecycle.ServiceDefinition
	local data = requireData(self)
	return table.freeze({
		name = SERVICE_NAME,
		dependencies = table.freeze({}),
		initialize = function()
			if data.state ~= "Constructed" then
				error("[ATD_QUEUE_WORLD_DISPLAY][code=INVALID_INITIALIZE_STATE]", 0)
			end
			data.state = "Initialized"
		end,
		start = function()
			if data.state ~= "Initialized" then
				error("[ATD_QUEUE_WORLD_DISPLAY][code=INVALID_START_STATE]", 0)
			end
			data.state = "Started"
		end,
		shutdown = function()
			local cleaned = self:cleanup()
			if not cleaned.ok then
				error("[ATD_QUEUE_WORLD_DISPLAY][code=CLEANUP_FAILED]", 0)
			end
		end,
	})
end

function QueueWorldDisplayService.new(
	anchorsValue: unknown,
	dependenciesValue: Dependencies?
): Result.Result<Service, DisplayError>
	if
		type(anchorsValue) ~= "table"
		or getmetatable(anchorsValue :: any) ~= nil
		or #anchorsValue < 1
		or #anchorsValue > 16
	then
		return failure("INVALID_ANCHORS", "new")
	end
	if
		dependenciesValue ~= nil
		and (
			type(dependenciesValue) ~= "table"
			or type(dependenciesValue.mapDisplayName) ~= "function"
			or type(dependenciesValue.difficultyDisplayName) ~= "function"
			or type(dependenciesValue.playerDisplayName) ~= "function"
		)
	then
		return failure("INVALID_ANCHORS", "new")
	end
	local displays: { [string]: Display } = {}
	for _, anchorValue in anchorsValue :: { unknown } do
		if type(anchorValue) ~= "table" or getmetatable(anchorValue :: any) ~= nil then
			for _, display in displays do
				display.gui:Destroy()
			end
			return failure("INVALID_ANCHORS", "new")
		end
		local anchor = anchorValue :: any
		local validAdornee = typeof(anchor.adornee) == "Instance"
			and (anchor.adornee:IsA("BasePart") or anchor.adornee:IsA("Attachment"))
		if type(anchor.queueId) ~= "string" or displays[anchor.queueId] ~= nil or not validAdornee then
			for _, display in displays do
				display.gui:Destroy()
			end
			return failure("INVALID_ANCHORS", "new")
		end
		local display = createDisplay(anchor :: Anchor)
		if display == nil then
			for _, created in displays do
				created.gui:Destroy()
			end
			return failure("DISPLAY_CONFLICT", "new")
		end
		displays[anchor.queueId] = display
	end
	local service = setmetatable({}, Methods) :: Service
	table.freeze(service)
	DATA[service] = {
		displays = displays,
		state = "Constructed",
		updateCount = 0,
		dependencies = dependenciesValue,
	}
	return Result.ok(service)
end

table.freeze(Methods)
return table.freeze(QueueWorldDisplayService)
