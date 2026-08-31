--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementGeometry = require(ReplicatedStorage.Shared.match.PlacementGeometry)
local PlacementProtocol = require(ReplicatedStorage.Shared.match.PlacementProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type InputFamily = "Desktop" | "Touch" | "Gamepad"
export type Phase = "Idle" | "Selected" | "Positioned" | "Submitting"
export type PreviewValidity =
	"None"
	| "Valid"
	| "InvalidPosition"
	| "InvalidSurface"
	| "OutsideZone"
	| "Excluded"
	| "Occupied"
	| "Capped"
	| "Unaffordable"
	| "Unavailable"

export type State = {
	phase: Phase,
	preferredInput: InputFamily,
	snapshot: PlacementProtocol.QuerySnapshot?,
	selectedSlot: number?,
	selectedMetadata: PlacementProtocol.QuerySlot?,
	positionXZ: Vector2?,
	worldPosition: Vector3?,
	yawDegrees: number,
	validity: PreviewValidity,
	canConfirm: boolean,
	refreshRequired: boolean,
	lastRejection: PlacementProtocol.PlacementRejectionReason?,
}

export type QueryApplyKind = "Applied" | "Replaced" | "Duplicate" | "Stale"
export type QueryApplyOutcome = {
	kind: QueryApplyKind,
	stateChanged: boolean,
}

export type RevisionApplyKind = "Bootstrap" | "Current" | "Advanced" | "Stale" | "Foreign"
export type RevisionApplyOutcome = {
	kind: RevisionApplyKind,
	refreshRequested: boolean,
}

export type ErrorCode =
	"INVALID_QUERY"
	| "INVALID_REVISION"
	| "INVALID_RECEIPT"
	| "INVALID_ARGUMENT"
	| "INVALID_SLOT"
	| "INVALID_STATE"
	| "UNAVAILABLE"
	| "CLEANED_UP"

export type Error = {
	code: ErrorCode,
}

type ReducerData = {
	snapshot: PlacementProtocol.QuerySnapshot?,
	selectedSlot: number?,
	positionXZ: Vector2?,
	worldPosition: Vector3?,
	yawDegrees: number,
	validity: PreviewValidity,
	phase: Phase,
	preferredInput: InputFamily,
	refreshRequired: boolean,
	lastRejection: PlacementProtocol.PlacementRejectionReason?,
	cleaned: boolean,
}

local ReducerMethods = {}
ReducerMethods.__index = ReducerMethods

export type Reducer = typeof(setmetatable({} :: {}, ReducerMethods))
export type ReducerResult = Result.Result<Reducer, Error>

local REDUCER_DATA = setmetatable({}, { __mode = "k" }) :: { [any]: ReducerData }

local ERRORS: { [ErrorCode]: Error } = table.freeze({
	INVALID_QUERY = table.freeze({ code = "INVALID_QUERY" :: "INVALID_QUERY" }),
	INVALID_REVISION = table.freeze({ code = "INVALID_REVISION" :: "INVALID_REVISION" }),
	INVALID_RECEIPT = table.freeze({ code = "INVALID_RECEIPT" :: "INVALID_RECEIPT" }),
	INVALID_ARGUMENT = table.freeze({ code = "INVALID_ARGUMENT" :: "INVALID_ARGUMENT" }),
	INVALID_SLOT = table.freeze({ code = "INVALID_SLOT" :: "INVALID_SLOT" }),
	INVALID_STATE = table.freeze({ code = "INVALID_STATE" :: "INVALID_STATE" }),
	UNAVAILABLE = table.freeze({ code = "UNAVAILABLE" :: "UNAVAILABLE" }),
	CLEANED_UP = table.freeze({ code = "CLEANED_UP" :: "CLEANED_UP" }),
})

local function failure(code: ErrorCode)
	return Result.err(ERRORS[code])
end

local function requireData(value: unknown): ReducerData
	if type(value) ~= "table" then
		error("[ATD_PLACEMENT_PREVIEW_REDUCER][code=INVALID_CONTEXT]", 0)
	end
	local data = REDUCER_DATA[value :: any]
	if data == nil then
		error("[ATD_PLACEMENT_PREVIEW_REDUCER][code=INVALID_CONTEXT]", 0)
	end
	return data
end

local function selectedMetadata(data: ReducerData): PlacementProtocol.QuerySlot?
	local snapshot = data.snapshot
	local slot = data.selectedSlot
	if snapshot == nil or slot == nil then
		return nil
	end
	local metadata = snapshot.slots[slot]
	return if metadata ~= nil and metadata.kind == "Occupied" then metadata else nil
end

local function clearSelection(data: ReducerData)
	data.selectedSlot = nil
	data.positionXZ = nil
	data.worldPosition = nil
	data.yawDegrees = 0
	data.validity = "None"
	data.phase = "Idle"
	data.lastRejection = nil
end

local function presentationPosition(snapshot: PlacementProtocol.QuerySnapshot, positionXZ: Vector2): Vector3?
	for _, zone in snapshot.placementZones do
		if PlacementGeometry.circleInsideRegion(positionXZ, 0.000001, zone) then
			local height = PlacementGeometry.groundHeight(zone)
			if height ~= nil then
				return Vector3.new(positionXZ.X, height, positionXZ.Y)
			end
		end
	end
	return nil
end

local function recompute(data: ReducerData)
	local metadata = selectedMetadata(data)
	if metadata == nil then
		clearSelection(data)
		return
	end

	local positionXZ = data.positionXZ
	if positionXZ == nil then
		data.worldPosition = nil
		data.validity = "None"
		data.phase = "Selected"
		return
	end

	local snapshot = data.snapshot :: PlacementProtocol.QuerySnapshot
	local evaluation = PlacementGeometry.evaluate(
		positionXZ,
		metadata.footprintRadiusStuds,
		snapshot.bounds,
		snapshot.placementZones,
		snapshot.exclusions,
		snapshot.footprints
	)
	data.worldPosition = evaluation.position or presentationPosition(snapshot, positionXZ)
	if not evaluation.valid then
		data.validity = evaluation.reason :: PreviewValidity
	elseif metadata.capState ~= "Available" then
		data.validity = "Capped"
	elseif metadata.affordability ~= "Affordable" then
		data.validity = "Unaffordable"
	else
		data.validity = "Valid"
	end
	data.phase = "Positioned"
end

local function statesShareIdentity(
	left: PlacementProtocol.QuerySnapshot,
	right: PlacementProtocol.QuerySnapshot
): boolean
	return left.matchId == right.matchId and left.mapId == right.mapId
end

function ReducerMethods.observeQuery(self: Reducer, value: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local validation = PlacementProtocol.validateQuerySnapshot(value)
	if not validation.ok then
		return failure("INVALID_QUERY")
	end
	local snapshot = validation.value
	local previous = data.snapshot
	if previous ~= nil and statesShareIdentity(previous, snapshot) then
		if snapshot.queryRevision < previous.queryRevision or snapshot.loadoutRevision < previous.loadoutRevision then
			return Result.ok(table.freeze({
				kind = "Stale" :: "Stale",
				stateChanged = false,
			}))
		elseif
			snapshot.queryRevision == previous.queryRevision
			and snapshot.loadoutRevision == previous.loadoutRevision
		then
			data.refreshRequired = false
			return Result.ok(table.freeze({
				kind = "Duplicate" :: "Duplicate",
				stateChanged = false,
			}))
		end
	end

	local replaced = previous ~= nil and not statesShareIdentity(previous, snapshot)
	data.snapshot = snapshot
	data.refreshRequired = false
	data.lastRejection = nil
	if replaced then
		clearSelection(data)
	else
		recompute(data)
	end
	return Result.ok(table.freeze({
		kind = if replaced then "Replaced" :: "Replaced" else "Applied" :: "Applied",
		stateChanged = true,
	}))
end

function ReducerMethods.observeRevision(self: Reducer, value: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local validation = PlacementProtocol.RevisionEventSchema:validate(value)
	if not validation.ok then
		return failure("INVALID_REVISION")
	end
	local event = validation.value :: { matchId: string, queryRevision: number }
	local snapshot = data.snapshot
	if snapshot == nil then
		local requested = not data.refreshRequired
		data.refreshRequired = true
		return Result.ok(table.freeze({
			kind = "Bootstrap" :: "Bootstrap",
			refreshRequested = requested,
		}))
	elseif event.matchId ~= snapshot.matchId then
		return Result.ok(table.freeze({
			kind = "Foreign" :: "Foreign",
			refreshRequested = false,
		}))
	elseif event.queryRevision < snapshot.queryRevision then
		return Result.ok(table.freeze({
			kind = "Stale" :: "Stale",
			refreshRequested = false,
		}))
	elseif event.queryRevision == snapshot.queryRevision then
		return Result.ok(table.freeze({
			kind = "Current" :: "Current",
			refreshRequested = false,
		}))
	end
	local requested = not data.refreshRequired
	data.refreshRequired = true
	return Result.ok(table.freeze({
		kind = "Advanced" :: "Advanced",
		refreshRequested = requested,
	}))
end

function ReducerMethods.selectSlot(self: Reducer, value: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if
		type(value) ~= "number"
		or not Validation.isSafeInteger(value :: number)
		or value < 1
		or value > PlacementProtocol.MAX_LOADOUT_SLOTS
	then
		return failure("INVALID_ARGUMENT")
	end
	local snapshot = data.snapshot
	if snapshot == nil or snapshot.slots[value :: number].kind ~= "Occupied" then
		return failure("INVALID_SLOT")
	end
	data.selectedSlot = value :: number
	data.lastRejection = nil
	recompute(data)
	return Result.ok(true)
end

function ReducerMethods.setPosition(self: Reducer, value: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if typeof(value) ~= "Vector2" then
		return failure("INVALID_ARGUMENT")
	end
	local position = value :: Vector2
	if
		not Validation.isFiniteNumber(position.X)
		or not Validation.isFiniteNumber(position.Y)
		or math.abs(position.X) > PlacementGeometry.MAX_COORDINATE
		or math.abs(position.Y) > PlacementGeometry.MAX_COORDINATE
	then
		return failure("INVALID_ARGUMENT")
	end
	if selectedMetadata(data) == nil or data.phase == "Submitting" then
		return failure("INVALID_STATE")
	end
	data.positionXZ = position
	data.lastRejection = nil
	recompute(data)
	return Result.ok(true)
end

function ReducerMethods.clearPosition(self: Reducer)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if selectedMetadata(data) == nil or data.phase == "Submitting" then
		return failure("INVALID_STATE")
	end
	local changed = data.positionXZ ~= nil
	data.positionXZ = nil
	data.worldPosition = nil
	data.validity = "None"
	data.phase = "Selected"
	data.lastRejection = nil
	return Result.ok(changed)
end

function ReducerMethods.rotate(self: Reducer, deltaValue: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if
		type(deltaValue) ~= "number"
		or not Validation.isFiniteNumber(deltaValue :: number)
		or math.abs(deltaValue :: number) > 360
	then
		return failure("INVALID_ARGUMENT")
	end
	if selectedMetadata(data) == nil or data.phase == "Submitting" then
		return failure("INVALID_STATE")
	end
	local normalized = PlacementGeometry.normalizeYawDegrees(data.yawDegrees + (deltaValue :: number))
	if normalized == nil then
		normalized = (data.yawDegrees + (deltaValue :: number)) % 360
	end
	data.yawDegrees = normalized
	return Result.ok(normalized)
end

function ReducerMethods.setPreferredInput(self: Reducer, value: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if value ~= "Desktop" and value ~= "Touch" and value ~= "Gamepad" then
		return failure("INVALID_ARGUMENT")
	end
	local changed = data.preferredInput ~= value
	data.preferredInput = value :: InputFamily
	return Result.ok(changed)
end

function ReducerMethods.beginSubmit(self: Reducer)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	local snapshot = data.snapshot
	local slot = data.selectedSlot
	local positionXZ = data.positionXZ
	if
		data.phase ~= "Positioned"
		or data.validity ~= "Valid"
		or snapshot == nil
		or slot == nil
		or positionXZ == nil
	then
		return failure("UNAVAILABLE")
	end
	local intent: PlacementProtocol.PlacementIntent = table.freeze({
		matchId = snapshot.matchId,
		observedQueryRevision = snapshot.queryRevision,
		loadoutRevision = snapshot.loadoutRevision,
		slot = slot,
		positionXZ = positionXZ,
		yawDegrees = data.yawDegrees,
	})
	local validation = PlacementProtocol.validatePlacementIntent(intent)
	if not validation.ok then
		return failure("INVALID_STATE")
	end
	data.phase = "Submitting"
	data.lastRejection = nil
	return Result.ok(intent)
end

function ReducerMethods.observeReceipt(self: Reducer, value: unknown)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if data.phase ~= "Submitting" then
		return failure("INVALID_STATE")
	end
	local validation = PlacementProtocol.validateReceipt(value)
	if not validation.ok then
		return failure("INVALID_RECEIPT")
	end
	local receipt = validation.value
	local snapshot = data.snapshot
	if snapshot == nil or receipt.queryRevision < snapshot.queryRevision then
		return failure("INVALID_RECEIPT")
	end
	if receipt.state == "Accepted" then
		if receipt.queryRevision <= snapshot.queryRevision then
			return failure("INVALID_RECEIPT")
		end
		data.positionXZ = nil
		data.worldPosition = nil
		data.validity = "None"
		data.phase = "Selected"
		data.refreshRequired = true
		data.lastRejection = nil
	else
		data.phase = if data.positionXZ == nil then "Selected" else "Positioned"
		data.lastRejection = receipt.reason
		if receipt.queryRevision > snapshot.queryRevision or receipt.reason == "Stale" then
			data.refreshRequired = true
		end
	end
	return Result.ok(receipt)
end

function ReducerMethods.abortSubmit(self: Reducer)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if data.phase ~= "Submitting" then
		return Result.ok(false)
	end
	data.phase = if data.positionXZ == nil then "Selected" else "Positioned"
	data.lastRejection = "Unavailable"
	return Result.ok(true)
end

function ReducerMethods.cancel(self: Reducer)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	if data.phase == "Submitting" then
		return failure("INVALID_STATE")
	end
	local changed = data.selectedSlot ~= nil
	clearSelection(data)
	return Result.ok(changed)
end

function ReducerMethods.getState(self: Reducer)
	local data = requireData(self)
	if data.cleaned then
		return failure("CLEANED_UP")
	end
	return Result.ok(table.freeze({
		phase = data.phase,
		preferredInput = data.preferredInput,
		snapshot = data.snapshot,
		selectedSlot = data.selectedSlot,
		selectedMetadata = selectedMetadata(data),
		positionXZ = data.positionXZ,
		worldPosition = data.worldPosition,
		yawDegrees = data.yawDegrees,
		validity = data.validity,
		canConfirm = data.phase == "Positioned" and data.validity == "Valid",
		refreshRequired = data.refreshRequired,
		lastRejection = data.lastRejection,
	}) :: State)
end

function ReducerMethods.cleanup(self: Reducer)
	local data = requireData(self)
	if data.cleaned then
		return Result.ok(true)
	end
	data.cleaned = true
	data.snapshot = nil
	clearSelection(data)
	data.refreshRequired = false
	return Result.ok(true)
end

local PlacementPreviewReducer = {}

function PlacementPreviewReducer.new(): ReducerResult
	local reducer = setmetatable({}, ReducerMethods) :: Reducer
	table.freeze(reducer)
	REDUCER_DATA[reducer] = {
		snapshot = nil,
		selectedSlot = nil,
		positionXZ = nil,
		worldPosition = nil,
		yawDegrees = 0,
		validity = "None",
		phase = "Idle",
		preferredInput = "Desktop",
		refreshRequired = false,
		lastRejection = nil,
		cleaned = false,
	}
	return Result.ok(reducer)
end

table.freeze(ReducerMethods)
return table.freeze(PlacementPreviewReducer)
