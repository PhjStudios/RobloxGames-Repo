--!strict

export type ProfileState = "Loading" | "Ready" | "Failed" | "Releasing"
export type PrimaryScreen = "Home" | "Inventory" | "Chests" | "Settings"
export type InputFamily = "Desktop" | "Touch" | "Gamepad"
export type ToastKind = "Info" | "Success" | "Warning" | "Error"

export type TowerCard = {
	unitId: string,
	towerId: string,
	displayName: string,
	description: string,
	acquisitionSource: string,
	copies: number,
	favorite: boolean,
	locked: boolean,
	equippedSlot: number?,
	placementCost: number,
	placementCap: number,
	damage: number,
	rangeStuds: number,
	cooldownSeconds: number,
	targetModesText: string,
	upgradePreview: string,
}

export type Settings = {
	masterVolume: number,
	musicVolume: number,
	sfxVolume: number,
	uiVolume: number,
	cameraShakeIntensity: number,
	reducedMotionEnabled: boolean,
	damageNumbersEnabled: boolean,
	enemyHealthBarsEnabled: boolean,
	otherPlayerEffectsEnabled: boolean,
	lowDetailEnabled: boolean,
	towerRangeEnabled: boolean,
	uiScale: number,
}

export type BannerOdd = {
	towerId: string,
	displayName: string,
	probabilityPercent: number,
}

export type Banner = {
	bannerId: string,
	displayName: string,
	onePullCost: number,
	tenPullCost: number,
	pityCount: number,
	hardPityPullCount: number,
	odds: { BannerOdd },
	earnOnly: boolean,
	canPullOne: boolean,
	canPullTen: boolean,
	transactionPending: boolean,
}

export type Modal = {
	id: string,
	title: string,
	message: string,
	confirmText: string?,
	cancelText: string?,
	dismissable: boolean,
	busy: boolean,
}

export type Toast = {
	id: string,
	kind: ToastKind,
	title: string,
	message: string,
	repeatCount: number,
}

export type RenderState = {
	profileState: ProfileState,
	screen: PrimaryScreen,
	profileRevision: number?,
	statusText: string,
	canRetry: boolean,
	canLeave: boolean,
	inputFamily: InputFamily,
	viewport: Vector2,
	preferredTextScale: number,
	preferredTransparency: number,
	reducedMotion: boolean,
	gold: number?,
	progressionText: string?,
	isFirstJoin: boolean,
	didMigrate: boolean,
	inventory: { TowerCard },
	selectedUnitId: string?,
	settings: Settings?,
	banner: Banner?,
	modals: { Modal },
	toasts: { Toast },
}

local MAX_INVENTORY = 200
local MAX_MODAL_DEPTH = 4
local MAX_TOASTS = 5
local MAX_ODDS = 32
local MAX_TEXT_BYTES = 240
local MAX_MODAL_MESSAGE_BYTES = 1_024
local MAX_GOLD = 2 ^ 31 - 1
local MAX_COPIES = 10_000
local MAX_PITY = 1_000_000

local PROFILE_STATES: { [string]: boolean } = table.freeze({
	Loading = true,
	Ready = true,
	Failed = true,
	Releasing = true,
})
local SCREENS: { [string]: boolean } = table.freeze({
	Home = true,
	Inventory = true,
	Chests = true,
	Settings = true,
})
local INPUT_FAMILIES: { [string]: boolean } = table.freeze({
	Desktop = true,
	Touch = true,
	Gamepad = true,
})
local TOAST_KINDS: { [string]: boolean } = table.freeze({
	Info = true,
	Success = true,
	Warning = true,
	Error = true,
})

local ROOT_FIELDS: { [string]: boolean } = table.freeze({
	profileState = true,
	screen = true,
	profileRevision = true,
	statusText = true,
	canRetry = true,
	canLeave = true,
	inputFamily = true,
	viewport = true,
	preferredTextScale = true,
	preferredTransparency = true,
	reducedMotion = true,
	gold = true,
	progressionText = true,
	isFirstJoin = true,
	didMigrate = true,
	inventory = true,
	selectedUnitId = true,
	settings = true,
	banner = true,
	modals = true,
	toasts = true,
})

local TOWER_FIELDS: { [string]: boolean } = table.freeze({
	unitId = true,
	towerId = true,
	displayName = true,
	description = true,
	acquisitionSource = true,
	copies = true,
	favorite = true,
	locked = true,
	equippedSlot = true,
	placementCost = true,
	placementCap = true,
	damage = true,
	rangeStuds = true,
	cooldownSeconds = true,
	targetModesText = true,
	upgradePreview = true,
})

local SETTINGS_FIELDS: { [string]: boolean } = table.freeze({
	masterVolume = true,
	musicVolume = true,
	sfxVolume = true,
	uiVolume = true,
	cameraShakeIntensity = true,
	reducedMotionEnabled = true,
	damageNumbersEnabled = true,
	enemyHealthBarsEnabled = true,
	otherPlayerEffectsEnabled = true,
	lowDetailEnabled = true,
	towerRangeEnabled = true,
	uiScale = true,
})

local BANNER_FIELDS: { [string]: boolean } = table.freeze({
	bannerId = true,
	displayName = true,
	onePullCost = true,
	tenPullCost = true,
	pityCount = true,
	hardPityPullCount = true,
	odds = true,
	earnOnly = true,
	canPullOne = true,
	canPullTen = true,
	transactionPending = true,
})

local ODD_FIELDS: { [string]: boolean } = table.freeze({
	towerId = true,
	displayName = true,
	probabilityPercent = true,
})

local MODAL_FIELDS: { [string]: boolean } = table.freeze({
	id = true,
	title = true,
	message = true,
	confirmText = true,
	cancelText = true,
	dismissable = true,
	busy = true,
})

local TOAST_FIELDS: { [string]: boolean } = table.freeze({
	id = true,
	kind = true,
	title = true,
	message = true,
	repeatCount = true,
})

local LobbyUiModel = {
	MAX_INVENTORY = MAX_INVENTORY,
	MAX_MODAL_DEPTH = MAX_MODAL_DEPTH,
	MAX_TOASTS = MAX_TOASTS,
	MAX_ODDS = MAX_ODDS,
	MAX_MODAL_MESSAGE_BYTES = MAX_MODAL_MESSAGE_BYTES,
}

local function finiteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function integer(value: unknown, minimum: number, maximum: number): boolean
	return finiteNumber(value)
		and (value :: number) % 1 == 0
		and (value :: number) >= minimum
		and (value :: number) <= maximum
end

local function boundedNumber(value: unknown, minimum: number, maximum: number): boolean
	return finiteNumber(value) and (value :: number) >= minimum and (value :: number) <= maximum
end

local function safeText(value: unknown, maximumBytes: number, allowEmpty: boolean?): boolean
	return type(value) == "string"
		and (allowEmpty == true or #value >= 1)
		and #value <= maximumBytes
		and string.find(value, "[%z\1-\8\11\12\14-\31]") == nil
end

local function safeId(value: unknown): boolean
	return safeText(value, 96) and string.match(value :: string, "^[A-Za-z0-9][A-Za-z0-9_.:%-]*$") ~= nil
end

local function exactRecord(value: unknown, fields: { [string]: boolean }): { [any]: unknown }?
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil
	end
	local record = value :: { [any]: unknown }
	for key in next, record do
		if type(key) ~= "string" or rawget(fields, key :: string) ~= true then
			return nil
		end
	end
	return record
end

local function denseCount(value: unknown, maximum: number): (number?, { [any]: unknown }?)
	if type(value) ~= "table" or getmetatable(value :: any) ~= nil then
		return nil, nil
	end
	local array = value :: { [any]: unknown }
	local count = 0
	for key in next, array do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > maximum then
			return nil, nil
		end
		count += 1
	end
	for index = 1, count do
		if rawget(array, index) == nil then
			return nil, nil
		end
	end
	return count, array
end

local function canonicalTower(value: unknown): TowerCard?
	local record = exactRecord(value, TOWER_FIELDS)
	if record == nil then
		return nil
	end
	local unitId = rawget(record, "unitId")
	local towerId = rawget(record, "towerId")
	local displayName = rawget(record, "displayName")
	local description = rawget(record, "description")
	local source = rawget(record, "acquisitionSource")
	local copies = rawget(record, "copies")
	local favorite = rawget(record, "favorite")
	local locked = rawget(record, "locked")
	local equippedSlot = rawget(record, "equippedSlot")
	local placementCost = rawget(record, "placementCost")
	local placementCap = rawget(record, "placementCap")
	local damage = rawget(record, "damage")
	local rangeStuds = rawget(record, "rangeStuds")
	local cooldownSeconds = rawget(record, "cooldownSeconds")
	local targetModesText = rawget(record, "targetModesText")
	local upgradePreview = rawget(record, "upgradePreview")
	if
		not safeId(unitId)
		or not safeId(towerId)
		or not safeText(displayName, 48)
		or not safeText(description, MAX_TEXT_BYTES, true)
		or not safeText(source, 96)
		or not integer(copies, 1, MAX_COPIES)
		or type(favorite) ~= "boolean"
		or type(locked) ~= "boolean"
		or (equippedSlot ~= nil and not integer(equippedSlot, 1, 5))
		or not integer(placementCost, 0, MAX_GOLD)
		or not integer(placementCap, 1, 1_000)
		or not boundedNumber(damage, 0, 1_000_000)
		or not boundedNumber(rangeStuds, 0, 10_000)
		or not boundedNumber(cooldownSeconds, 0.01, 1_000)
		or not safeText(targetModesText, 120)
		or not safeText(upgradePreview, MAX_TEXT_BYTES, true)
	then
		return nil
	end
	return table.freeze({
		unitId = unitId :: string,
		towerId = towerId :: string,
		displayName = displayName :: string,
		description = description :: string,
		acquisitionSource = source :: string,
		copies = copies :: number,
		favorite = favorite :: boolean,
		locked = locked :: boolean,
		equippedSlot = equippedSlot :: number?,
		placementCost = placementCost :: number,
		placementCap = placementCap :: number,
		damage = damage :: number,
		rangeStuds = rangeStuds :: number,
		cooldownSeconds = cooldownSeconds :: number,
		targetModesText = targetModesText :: string,
		upgradePreview = upgradePreview :: string,
	})
end

local function canonicalSettings(value: unknown): Settings?
	local record = exactRecord(value, SETTINGS_FIELDS)
	if record == nil then
		return nil
	end
	for _, field in { "masterVolume", "musicVolume", "sfxVolume", "uiVolume", "cameraShakeIntensity" } do
		if not boundedNumber(rawget(record, field), 0, 1) then
			return nil
		end
	end
	for _, field in
		{
			"reducedMotionEnabled",
			"damageNumbersEnabled",
			"enemyHealthBarsEnabled",
			"otherPlayerEffectsEnabled",
			"lowDetailEnabled",
			"towerRangeEnabled",
		}
	do
		if type(rawget(record, field)) ~= "boolean" then
			return nil
		end
	end
	if not boundedNumber(rawget(record, "uiScale"), 0.75, 1.25) then
		return nil
	end
	return table.freeze({
		masterVolume = record.masterVolume :: number,
		musicVolume = record.musicVolume :: number,
		sfxVolume = record.sfxVolume :: number,
		uiVolume = record.uiVolume :: number,
		cameraShakeIntensity = record.cameraShakeIntensity :: number,
		reducedMotionEnabled = record.reducedMotionEnabled :: boolean,
		damageNumbersEnabled = record.damageNumbersEnabled :: boolean,
		enemyHealthBarsEnabled = record.enemyHealthBarsEnabled :: boolean,
		otherPlayerEffectsEnabled = record.otherPlayerEffectsEnabled :: boolean,
		lowDetailEnabled = record.lowDetailEnabled :: boolean,
		towerRangeEnabled = record.towerRangeEnabled :: boolean,
		uiScale = record.uiScale :: number,
	})
end

local function canonicalBanner(value: unknown): Banner?
	local record = exactRecord(value, BANNER_FIELDS)
	if record == nil then
		return nil
	end
	local bannerId = rawget(record, "bannerId")
	local displayName = rawget(record, "displayName")
	local oneCost = rawget(record, "onePullCost")
	local tenCost = rawget(record, "tenPullCost")
	local pity = rawget(record, "pityCount")
	local hardPity = rawget(record, "hardPityPullCount")
	local earnOnly = rawget(record, "earnOnly")
	local canPullOne = rawget(record, "canPullOne")
	local canPullTen = rawget(record, "canPullTen")
	local pending = rawget(record, "transactionPending")
	local oddsCount, oddsValue = denseCount(rawget(record, "odds"), MAX_ODDS)
	if
		not safeId(bannerId)
		or not safeText(displayName, 64)
		or not integer(oneCost, 1, MAX_GOLD)
		or not integer(tenCost, 1, MAX_GOLD)
		or not integer(pity, 0, MAX_PITY)
		or not integer(hardPity, 1, MAX_PITY)
		or (pity :: number) >= (hardPity :: number)
		or earnOnly ~= true
		or type(canPullOne) ~= "boolean"
		or type(canPullTen) ~= "boolean"
		or type(pending) ~= "boolean"
		or oddsCount == nil
		or oddsCount < 1
	then
		return nil
	end
	local odds = table.create(oddsCount) :: { BannerOdd }
	local seen: { [string]: boolean } = {}
	local total = 0
	for index = 1, oddsCount do
		local odd = exactRecord((oddsValue :: { [any]: unknown })[index], ODD_FIELDS)
		if odd == nil then
			return nil
		end
		local towerId = rawget(odd, "towerId")
		local oddDisplayName = rawget(odd, "displayName")
		local probability = rawget(odd, "probabilityPercent")
		if
			not safeId(towerId)
			or seen[towerId :: string] == true
			or not safeText(oddDisplayName, 48)
			or not boundedNumber(probability, 1e-9, 100)
		then
			return nil
		end
		seen[towerId :: string] = true
		total += probability :: number
		odds[index] = table.freeze({
			towerId = towerId :: string,
			displayName = oddDisplayName :: string,
			probabilityPercent = probability :: number,
		})
	end
	if math.abs(total - 100) > 1e-9 then
		return nil
	end
	return table.freeze({
		bannerId = bannerId :: string,
		displayName = displayName :: string,
		onePullCost = oneCost :: number,
		tenPullCost = tenCost :: number,
		pityCount = pity :: number,
		hardPityPullCount = hardPity :: number,
		odds = table.freeze(odds),
		earnOnly = true,
		canPullOne = canPullOne :: boolean,
		canPullTen = canPullTen :: boolean,
		transactionPending = pending :: boolean,
	})
end

local function canonicalModals(value: unknown): { Modal }?
	local count, array = denseCount(value, MAX_MODAL_DEPTH)
	if count == nil then
		return nil
	end
	local result = table.create(count) :: { Modal }
	local seen: { [string]: boolean } = {}
	for index = 1, count do
		local record = exactRecord((array :: { [any]: unknown })[index], MODAL_FIELDS)
		if record == nil then
			return nil
		end
		local id = rawget(record, "id")
		local title = rawget(record, "title")
		local message = rawget(record, "message")
		local confirmText = rawget(record, "confirmText")
		local cancelText = rawget(record, "cancelText")
		local dismissable = rawget(record, "dismissable")
		local busy = rawget(record, "busy")
		if
			not safeId(id)
			or seen[id :: string] == true
			or not safeText(title, 64)
			or not safeText(message, MAX_MODAL_MESSAGE_BYTES)
			or (confirmText ~= nil and not safeText(confirmText, 40))
			or (cancelText ~= nil and not safeText(cancelText, 40))
			or type(dismissable) ~= "boolean"
			or type(busy) ~= "boolean"
			or (confirmText == nil and cancelText == nil and dismissable ~= true)
		then
			return nil
		end
		seen[id :: string] = true
		result[index] = table.freeze({
			id = id :: string,
			title = title :: string,
			message = message :: string,
			confirmText = confirmText :: string?,
			cancelText = cancelText :: string?,
			dismissable = dismissable :: boolean,
			busy = busy :: boolean,
		})
	end
	return table.freeze(result)
end

local function canonicalToasts(value: unknown): { Toast }?
	local count, array = denseCount(value, MAX_TOASTS)
	if count == nil then
		return nil
	end
	local result = table.create(count) :: { Toast }
	local seen: { [string]: boolean } = {}
	for index = 1, count do
		local record = exactRecord((array :: { [any]: unknown })[index], TOAST_FIELDS)
		if record == nil then
			return nil
		end
		local id = rawget(record, "id")
		local kind = rawget(record, "kind")
		local title = rawget(record, "title")
		local message = rawget(record, "message")
		local repeatCount = rawget(record, "repeatCount")
		if
			not safeId(id)
			or seen[id :: string] == true
			or type(kind) ~= "string"
			or rawget(TOAST_KINDS, kind) ~= true
			or not safeText(title, 48)
			or not safeText(message, 180)
			or not integer(repeatCount, 1, 999)
		then
			return nil
		end
		seen[id :: string] = true
		result[index] = table.freeze({
			id = id :: string,
			kind = kind :: ToastKind,
			title = title :: string,
			message = message :: string,
			repeatCount = repeatCount :: number,
		})
	end
	return table.freeze(result)
end

function LobbyUiModel.canonicalize(value: unknown): RenderState?
	local record = exactRecord(value, ROOT_FIELDS)
	if record == nil then
		return nil
	end
	local profileState = rawget(record, "profileState")
	local screen = rawget(record, "screen")
	local statusText = rawget(record, "statusText")
	local canRetry = rawget(record, "canRetry")
	local canLeave = rawget(record, "canLeave")
	local inputFamily = rawget(record, "inputFamily")
	local viewport = rawget(record, "viewport")
	local preferredTextScale = rawget(record, "preferredTextScale")
	local preferredTransparency = rawget(record, "preferredTransparency")
	local reducedMotion = rawget(record, "reducedMotion")
	local isFirstJoin = rawget(record, "isFirstJoin")
	local didMigrate = rawget(record, "didMigrate")
	local modals = canonicalModals(rawget(record, "modals"))
	local toasts = canonicalToasts(rawget(record, "toasts"))
	if
		type(profileState) ~= "string"
		or rawget(PROFILE_STATES, profileState) ~= true
		or type(screen) ~= "string"
		or rawget(SCREENS, screen) ~= true
		or not safeText(statusText, 160)
		or type(canRetry) ~= "boolean"
		or type(canLeave) ~= "boolean"
		or (canRetry and profileState ~= "Failed")
		or type(inputFamily) ~= "string"
		or rawget(INPUT_FAMILIES, inputFamily) ~= true
		or typeof(viewport) ~= "Vector2"
		or not boundedNumber((viewport :: Vector2).X, 240, 16_384)
		or not boundedNumber((viewport :: Vector2).Y, 320, 16_384)
		or not boundedNumber(preferredTextScale, 0.85, 1.5)
		or not boundedNumber(preferredTransparency, 0, 1)
		or type(reducedMotion) ~= "boolean"
		or type(isFirstJoin) ~= "boolean"
		or type(didMigrate) ~= "boolean"
		or modals == nil
		or toasts == nil
	then
		return nil
	end

	local profileRevision = rawget(record, "profileRevision")
	local gold = rawget(record, "gold")
	local progressionText = rawget(record, "progressionText")
	local selectedUnitId = rawget(record, "selectedUnitId")
	local settingsValue = rawget(record, "settings")
	local bannerValue = rawget(record, "banner")
	local inventoryValue = rawget(record, "inventory")
	local inventory = {} :: { TowerCard }
	local settings: Settings? = nil
	local banner: Banner? = nil
	if profileState == "Ready" then
		local inventoryCount, inventoryArray = denseCount(inventoryValue, MAX_INVENTORY)
		if
			not integer(profileRevision, 0, MAX_GOLD)
			or not integer(gold, 0, MAX_GOLD)
			or not safeText(progressionText, 96)
			or inventoryCount == nil
			or inventoryCount < 1
			or (selectedUnitId ~= nil and not safeId(selectedUnitId))
		then
			return nil
		end
		local seenUnitIds: { [string]: boolean } = {}
		local equippedTowerIds: { [string]: boolean } = {}
		local copyCounts: { [string]: number } = {}
		local seenSlots: { [number]: boolean } = {}
		local equippedCount = 0
		for index = 1, inventoryCount do
			local tower = canonicalTower((inventoryArray :: { [any]: unknown })[index])
			if tower == nil or seenUnitIds[tower.unitId] then
				return nil
			end
			seenUnitIds[tower.unitId] = true
			copyCounts[tower.towerId] = (copyCounts[tower.towerId] or 0) + 1
			if tower.equippedSlot ~= nil then
				if seenSlots[tower.equippedSlot] or equippedTowerIds[tower.towerId] then
					return nil
				end
				seenSlots[tower.equippedSlot] = true
				equippedTowerIds[tower.towerId] = true
				equippedCount += 1
			end
			inventory[index] = tower
		end
		for _, tower in inventory do
			if tower.copies ~= copyCounts[tower.towerId] then
				return nil
			end
		end
		if equippedCount < 1 or (selectedUnitId ~= nil and not seenUnitIds[selectedUnitId :: string]) then
			return nil
		end
		settings = canonicalSettings(settingsValue)
		if settings == nil then
			return nil
		end
		if bannerValue ~= nil then
			banner = canonicalBanner(bannerValue)
			if banner == nil then
				return nil
			end
		end
	else
		if
			profileRevision ~= nil
			or gold ~= nil
			or progressionText ~= nil
			or inventoryValue ~= nil
			or selectedUnitId ~= nil
			or settingsValue ~= nil
			or bannerValue ~= nil
			or isFirstJoin ~= false
			or didMigrate ~= false
			or #modals > 0
		then
			return nil
		end
	end

	return table.freeze({
		profileState = profileState :: ProfileState,
		screen = screen :: PrimaryScreen,
		profileRevision = profileRevision :: number?,
		statusText = statusText :: string,
		canRetry = canRetry :: boolean,
		canLeave = canLeave :: boolean,
		inputFamily = inputFamily :: InputFamily,
		viewport = viewport :: Vector2,
		preferredTextScale = preferredTextScale :: number,
		preferredTransparency = preferredTransparency :: number,
		reducedMotion = reducedMotion :: boolean,
		gold = gold :: number?,
		progressionText = progressionText :: string?,
		isFirstJoin = isFirstJoin :: boolean,
		didMigrate = didMigrate :: boolean,
		inventory = table.freeze(inventory),
		selectedUnitId = selectedUnitId :: string?,
		settings = settings,
		banner = banner,
		modals = modals,
		toasts = toasts,
	})
end

return table.freeze(LobbyUiModel)
