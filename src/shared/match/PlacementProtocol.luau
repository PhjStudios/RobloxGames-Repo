--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

local PlacementGeometry = require(script.Parent.PlacementGeometry)

export type AffordabilityState = "Affordable" | "Unaffordable"
export type CapState = "Available" | "PerTypeCapped" | "TotalCapped"
export type PlacementRejectionReason =
	"NotEligible"
	| "Stale"
	| "InvalidSlot"
	| "InvalidPosition"
	| "InvalidSurface"
	| "OutsideZone"
	| "Excluded"
	| "Occupied"
	| "Capped"
	| "Unaffordable"
	| "Unavailable"

export type Bounds = PlacementGeometry.Bounds
export type PlacementZone = PlacementGeometry.PlacementZone
export type Exclusion = PlacementGeometry.Exclusion

export type QuerySlot = {
	kind: "Empty" | "Occupied",
	slot: number,
	towerId: string?,
	displayName: string?,
	iconAssetKey: string?,
	rangeStuds: number?,
	footprintRadiusStuds: number?,
	placementCost: number?,
	placementCount: number?,
	placementCap: number?,
	totalCount: number?,
	totalCap: number?,
	globalCount: number?,
	globalCap: number?,
	affordability: AffordabilityState?,
	capState: CapState?,
}

export type QuerySnapshot = {
	contractVersion: number,
	matchId: string,
	mapId: string,
	queryRevision: number,
	loadoutRevision: number,
	bounds: Bounds,
	placementZones: { PlacementZone },
	exclusions: { Exclusion },
	footprints: { Vector3 },
	slots: { QuerySlot },
}

export type PlacementIntent = {
	matchId: string,
	observedQueryRevision: number,
	loadoutRevision: number,
	slot: number,
	positionXZ: Vector2,
	yawDegrees: number,
}

export type AcceptedReceipt = {
	state: "Accepted",
	runtimeTowerId: number,
	placementCFrame: CFrame,
	queryRevision: number,
}

export type RejectedReceipt = {
	state: "Rejected",
	reason: PlacementRejectionReason,
	queryRevision: number,
}

export type PlacementReceipt = AcceptedReceipt | RejectedReceipt

local CONTRACT_VERSION = 1
local GET_QUERY_ENDPOINT = "GetTowerPlacementQuery"
local SUBMIT_PLACEMENT_ENDPOINT = "SubmitTowerPlacement"
local REVISION_ENDPOINT = "TowerPlacementRevision"
local MAX_QUERY_PLACEMENT_ZONES = 24
local MAX_QUERY_EXCLUSIONS = 24
local MAX_QUERY_FOOTPRINTS = 128
local MAX_LOADOUT_SLOTS = 5
local MAX_TOTAL_ACTIVE_PER_OWNER = 32
local MAX_QUERY_REVISION_LAG = 4
local MAX_RUNTIME_TOWER_ID = 4_096
local MAX_SAFE_INTEGER = Validation.MAX_SAFE_INTEGER
local MAX_TEXT_BYTES = 100
local MAX_ASSET_KEY_BYTES = 100

local POSITIVE_SAFE_INTEGER = PayloadValidation.integer(1, MAX_SAFE_INTEGER)
local NONNEGATIVE_SAFE_INTEGER = PayloadValidation.integer(0, MAX_SAFE_INTEGER)
local BOUNDED_NUMBER = PayloadValidation.number(0, PlacementGeometry.MAX_COORDINATE)

local BOUNDS_VALIDATOR = PayloadValidation.record({
	cframe = PayloadValidation.cframe(),
	size = PayloadValidation.vector3(),
})

local PLACEMENT_ZONE_VALIDATOR = PayloadValidation.record({
	cframe = PayloadValidation.cframe(),
	size = PayloadValidation.vector3(),
	surfaceCategory = PayloadValidation.enum({ "Land", "Elevated", "Water" }),
})

local EXCLUSION_VALIDATOR = PayloadValidation.record({
	cframe = PayloadValidation.cframe(),
	size = PayloadValidation.vector3(),
})

local QUERY_SLOT_VALIDATOR = PayloadValidation.record({
	kind = PayloadValidation.enum({ "Empty", "Occupied" }),
	slot = PayloadValidation.integer(1, MAX_LOADOUT_SLOTS),
	towerId = PayloadValidation.optional(PayloadValidation.id("tower")),
	displayName = PayloadValidation.optional(PayloadValidation.string(MAX_TEXT_BYTES, 1)),
	iconAssetKey = PayloadValidation.optional(PayloadValidation.string(MAX_ASSET_KEY_BYTES, 1)),
	rangeStuds = PayloadValidation.optional(BOUNDED_NUMBER),
	footprintRadiusStuds = PayloadValidation.optional(PayloadValidation.number(0.000001, PlacementGeometry.MAX_RADIUS)),
	placementCost = PayloadValidation.optional(NONNEGATIVE_SAFE_INTEGER),
	placementCount = PayloadValidation.optional(NONNEGATIVE_SAFE_INTEGER),
	placementCap = PayloadValidation.optional(POSITIVE_SAFE_INTEGER),
	totalCount = PayloadValidation.optional(NONNEGATIVE_SAFE_INTEGER),
	totalCap = PayloadValidation.optional(POSITIVE_SAFE_INTEGER),
	globalCount = PayloadValidation.optional(NONNEGATIVE_SAFE_INTEGER),
	globalCap = PayloadValidation.optional(POSITIVE_SAFE_INTEGER),
	affordability = PayloadValidation.optional(PayloadValidation.enum({ "Affordable", "Unaffordable" })),
	capState = PayloadValidation.optional(PayloadValidation.enum({ "Available", "PerTypeCapped", "TotalCapped" })),
})

local GetQueryPayloadSchema = PayloadValidation.schema(PayloadValidation.record({}))
local QuerySnapshotSchema = PayloadValidation.schema(PayloadValidation.record({
	contractVersion = PayloadValidation.integer(CONTRACT_VERSION, CONTRACT_VERSION),
	matchId = PayloadValidation.id("match"),
	mapId = PayloadValidation.id("map"),
	queryRevision = POSITIVE_SAFE_INTEGER,
	loadoutRevision = POSITIVE_SAFE_INTEGER,
	bounds = BOUNDS_VALIDATOR,
	placementZones = PayloadValidation.array(PLACEMENT_ZONE_VALIDATOR, MAX_QUERY_PLACEMENT_ZONES, 1),
	exclusions = PayloadValidation.array(EXCLUSION_VALIDATOR, MAX_QUERY_EXCLUSIONS),
	footprints = PayloadValidation.array(PayloadValidation.vector3(), MAX_QUERY_FOOTPRINTS),
	slots = PayloadValidation.array(QUERY_SLOT_VALIDATOR, MAX_LOADOUT_SLOTS, MAX_LOADOUT_SLOTS),
}))

local SubmitPlacementPayloadSchema = PayloadValidation.schema(PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	observedQueryRevision = POSITIVE_SAFE_INTEGER,
	loadoutRevision = POSITIVE_SAFE_INTEGER,
	slot = PayloadValidation.integer(1, MAX_LOADOUT_SLOTS),
	positionXZ = PayloadValidation.vector2(),
	yawDegrees = PayloadValidation.number(-360, 360),
}))

local ACCEPTED_RECEIPT_VALIDATOR = PayloadValidation.record({
	state = PayloadValidation.enum({ "Accepted" }),
	runtimeTowerId = PayloadValidation.integer(1, MAX_RUNTIME_TOWER_ID),
	placementCFrame = PayloadValidation.cframe(),
	queryRevision = POSITIVE_SAFE_INTEGER,
})

local REJECTED_RECEIPT_VALIDATOR = PayloadValidation.record({
	state = PayloadValidation.enum({ "Rejected" }),
	reason = PayloadValidation.enum({
		"NotEligible",
		"Stale",
		"InvalidSlot",
		"InvalidPosition",
		"InvalidSurface",
		"OutsideZone",
		"Excluded",
		"Occupied",
		"Capped",
		"Unaffordable",
		"Unavailable",
	}),
	queryRevision = POSITIVE_SAFE_INTEGER,
})

local PlacementReceiptSchema = PayloadValidation.schema(PayloadValidation.union({
	ACCEPTED_RECEIPT_VALIDATOR,
	REJECTED_RECEIPT_VALIDATOR,
}))

local RevisionEventSchema = PayloadValidation.schema(PayloadValidation.record({
	matchId = PayloadValidation.id("match"),
	queryRevision = POSITIVE_SAFE_INTEGER,
}))

local function issue(code: Validation.Code, path: { Validation.PathSegment }, message: string)
	return Result.err(Validation.issue(code, path, message))
end

local function hasOccupiedFields(slot: QuerySlot): boolean
	return slot.towerId ~= nil
		and slot.displayName ~= nil
		and slot.rangeStuds ~= nil
		and slot.footprintRadiusStuds ~= nil
		and slot.placementCost ~= nil
		and slot.placementCount ~= nil
		and slot.placementCap ~= nil
		and slot.totalCount ~= nil
		and slot.totalCap ~= nil
		and slot.globalCount ~= nil
		and slot.globalCap ~= nil
		and slot.affordability ~= nil
		and slot.capState ~= nil
end

local function hasNoOccupiedFields(slot: QuerySlot): boolean
	return slot.towerId == nil
		and slot.displayName == nil
		and slot.iconAssetKey == nil
		and slot.rangeStuds == nil
		and slot.footprintRadiusStuds == nil
		and slot.placementCost == nil
		and slot.placementCount == nil
		and slot.placementCap == nil
		and slot.totalCount == nil
		and slot.totalCap == nil
		and slot.globalCount == nil
		and slot.globalCap == nil
		and slot.affordability == nil
		and slot.capState == nil
end

local PlacementProtocol = {
	CONTRACT_VERSION = CONTRACT_VERSION,
	GET_QUERY_ENDPOINT = GET_QUERY_ENDPOINT,
	SUBMIT_PLACEMENT_ENDPOINT = SUBMIT_PLACEMENT_ENDPOINT,
	REVISION_ENDPOINT = REVISION_ENDPOINT,
	MAX_QUERY_PLACEMENT_ZONES = MAX_QUERY_PLACEMENT_ZONES,
	MAX_QUERY_EXCLUSIONS = MAX_QUERY_EXCLUSIONS,
	MAX_QUERY_FOOTPRINTS = MAX_QUERY_FOOTPRINTS,
	MAX_LOADOUT_SLOTS = MAX_LOADOUT_SLOTS,
	MAX_TOTAL_ACTIVE_PER_OWNER = MAX_TOTAL_ACTIVE_PER_OWNER,
	MAX_QUERY_REVISION_LAG = MAX_QUERY_REVISION_LAG,
	MAX_RUNTIME_TOWER_ID = MAX_RUNTIME_TOWER_ID,
	GetQueryPayloadSchema = GetQueryPayloadSchema,
	QuerySnapshotSchema = QuerySnapshotSchema,
	SubmitPlacementPayloadSchema = SubmitPlacementPayloadSchema,
	PlacementReceiptSchema = PlacementReceiptSchema,
	RevisionEventSchema = RevisionEventSchema,
}

function PlacementProtocol.validateQuerySnapshot(value: unknown): Result.Result<QuerySnapshot, Validation.Issue>
	local schemaResult = QuerySnapshotSchema:validate(value)
	if not schemaResult.ok then
		return Result.err(schemaResult.error)
	end
	local snapshot = schemaResult.value :: QuerySnapshot
	if not PlacementGeometry.isUprightYawCFrame(snapshot.bounds.cframe) then
		return issue(
			"INVALID_REFERENCE",
			{ "payload", "bounds", "cframe" },
			"Map bounds must be an upright bounded region"
		)
	end
	if
		not PlacementGeometry.circleInsideRegion(
			Vector2.new(snapshot.bounds.cframe.X, snapshot.bounds.cframe.Z),
			0.000001,
			snapshot.bounds
		)
	then
		return issue("OUT_OF_RANGE", { "payload", "bounds", "size" }, "Map bounds size is invalid")
	end

	for index, zone in snapshot.placementZones do
		if
			not PlacementGeometry.isUprightYawCFrame(zone.cframe)
			or not PlacementGeometry.isSurfaceCategory(zone.surfaceCategory)
			or PlacementGeometry.groundHeight(zone) == nil
		then
			return issue("INVALID_REFERENCE", { "payload", "placementZones", index }, "Placement zone is invalid")
		end
	end
	for index, exclusion in snapshot.exclusions do
		if
			not PlacementGeometry.isUprightYawCFrame(exclusion.cframe)
			or PlacementGeometry.groundHeight(exclusion) == nil
		then
			return issue("INVALID_REFERENCE", { "payload", "exclusions", index }, "Exclusion region is invalid")
		end
	end
	for index, footprint in snapshot.footprints do
		local position, radius = PlacementGeometry.decodeFootprint(footprint)
		if position == nil or radius == nil then
			return issue("OUT_OF_RANGE", { "payload", "footprints", index }, "Footprint encoding is invalid")
		end
	end

	for index, slot in snapshot.slots do
		if slot.slot ~= index then
			return issue(
				"INVALID_ORDER",
				{ "payload", "slots", index, "slot" },
				"Loadout slots must be dense and ordered"
			)
		end
		if slot.kind == "Empty" then
			if not hasNoOccupiedFields(slot) then
				return issue("INVALID_REFERENCE", { "payload", "slots", index }, "Empty slot carries occupied metadata")
			end
		elseif not hasOccupiedFields(slot) then
			return issue("MISSING_FIELD", { "payload", "slots", index }, "Occupied slot is missing preview metadata")
		else
			local placementCount = slot.placementCount :: number
			local placementCap = slot.placementCap :: number
			local totalCount = slot.totalCount :: number
			local totalCap = slot.totalCap :: number
			local globalCount = slot.globalCount :: number
			local globalCap = slot.globalCap :: number
			if placementCount > placementCap or totalCount > totalCap or globalCount > globalCap then
				return issue("OUT_OF_RANGE", { "payload", "slots", index }, "Placement counts exceed their caps")
			end
			local expectedCapState: CapState = if totalCount >= totalCap or globalCount >= globalCap
				then "TotalCapped"
				elseif placementCount >= placementCap then "PerTypeCapped"
				else "Available"
			if slot.capState ~= expectedCapState then
				return issue(
					"INVALID_REFERENCE",
					{ "payload", "slots", index, "capState" },
					"Cap state does not match counts"
				)
			end
		end
	end
	return Result.ok(snapshot)
end

function PlacementProtocol.validatePlacementIntent(value: unknown): Result.Result<PlacementIntent, Validation.Issue>
	local schemaResult = SubmitPlacementPayloadSchema:validate(value)
	if not schemaResult.ok then
		return Result.err(schemaResult.error)
	end
	local intent = schemaResult.value :: PlacementIntent
	if
		math.abs(intent.positionXZ.X) > PlacementGeometry.MAX_COORDINATE
		or math.abs(intent.positionXZ.Y) > PlacementGeometry.MAX_COORDINATE
		or PlacementGeometry.normalizeYawDegrees(intent.yawDegrees) == nil
	then
		return issue("OUT_OF_RANGE", { "payload", "positionXZ" }, "Placement intent is outside technical bounds")
	end
	return Result.ok(intent)
end

function PlacementProtocol.validateReceipt(value: unknown): Result.Result<PlacementReceipt, Validation.Issue>
	local schemaResult = PlacementReceiptSchema:validate(value)
	if not schemaResult.ok then
		return Result.err(schemaResult.error)
	end
	local receipt = schemaResult.value :: PlacementReceipt
	if receipt.state == "Accepted" and not PlacementGeometry.isUprightYawCFrame(receipt.placementCFrame) then
		return issue("INVALID_REFERENCE", { "payload", "placementCFrame" }, "Accepted placement CFrame is not upright")
	end
	return Result.ok(receipt)
end

return table.freeze(PlacementProtocol)
