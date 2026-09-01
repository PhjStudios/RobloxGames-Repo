--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local Validation = require(ReplicatedStorage.Shared.util.Validation)

export type AdmissionState = "Expected" | "Admitted" | "LateSpectator" | "Returned"
export type TicketState = "Created" | "Teleporting" | "Active" | "Terminal"
export type Privacy = "Public" | "PartyOnly"

export type LobbyOrigin = {
	placeId: number,
	jobId: string,
}

export type LoadoutSlot = {
	slot: number,
	unitId: string,
	towerId: string,
}

export type LoadoutSnapshot = {
	userId: number,
	revision: number,
	slots: { LoadoutSlot },
	settings: { [string]: boolean | number },
}

export type Member = {
	userId: number,
	loadout: LoadoutSnapshot,
	admissionState: AdmissionState,
	admittedAt: number?,
}

export type Ticket = {
	version: number,
	revision: number,
	ticketId: string,
	matchId: string,
	resultId: string,
	expectedUserIds: { number },
	captainUserId: number,
	mapId: string,
	difficultyId: string,
	privacy: Privacy,
	lobbyOrigin: LobbyOrigin,
	members: { Member },
	createdAt: number,
	expiresAt: number,
	claimedDestinationJobId: string?,
	claimedDestinationAt: number?,
	state: TicketState,
	retryCount: number,
	terminalReason: string?,
}

export type ErrorCode = "INVALID_TICKET" | "INVALID_LOADOUT" | "INVALID_STATE" | "CAPACITY_EXCEEDED"
export type TicketError = { code: ErrorCode, path: string }

local VERSION = 1
local MAX_MEMBERS = 4
local MAX_TTL_SECONDS = 600
local MAX_RETRIES = 5
local MAX_TOKEN_BYTES = 100
local MAX_SLOTS = 5

local ROOT_FIELDS = table.freeze({
	version = true,
	revision = true,
	ticketId = true,
	matchId = true,
	resultId = true,
	expectedUserIds = true,
	captainUserId = true,
	mapId = true,
	difficultyId = true,
	privacy = true,
	lobbyOrigin = true,
	members = true,
	createdAt = true,
	expiresAt = true,
	claimedDestinationJobId = true,
	claimedDestinationAt = true,
	state = true,
	retryCount = true,
	terminalReason = true,
})
local ORIGIN_FIELDS = table.freeze({ placeId = true, jobId = true })
local MEMBER_FIELDS = table.freeze({ userId = true, loadout = true, admissionState = true, admittedAt = true })
local LOADOUT_FIELDS = table.freeze({ userId = true, revision = true, slots = true, settings = true })
local SLOT_FIELDS = table.freeze({ slot = true, unitId = true, towerId = true })
local SETTINGS_FIELDS = table.freeze({
	version = true,
	masterVolume = true,
	musicVolume = true,
	sfxVolume = true,
	uiVolume = true,
	cameraShakeIntensity = true,
	damageNumbersEnabled = true,
	enemyHealthBarsEnabled = true,
	otherPlayerEffectsEnabled = true,
	lowDetailEnabled = true,
	towerRangeEnabled = true,
	uiScale = true,
	reducedMotionEnabled = true,
})
local ADMISSION_STATES: { [string]: boolean } = table.freeze({
	Expected = true,
	Admitted = true,
	LateSpectator = true,
	Returned = true,
})
local TICKET_STATES: { [string]: boolean } = table.freeze({
	Created = true,
	Teleporting = true,
	Active = true,
	Terminal = true,
})

local MatchTicketContract = {
	VERSION = VERSION,
	MAX_MEMBERS = MAX_MEMBERS,
	MAX_TTL_SECONDS = MAX_TTL_SECONDS,
	MAX_RETRIES = MAX_RETRIES,
}

local function failure(code: ErrorCode, path: string): Result.Failure<TicketError>
	return Result.err(table.freeze({ code = code, path = path }))
end

local function clone(value: any, seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end
	local memo = seen or {}
	if memo[value] ~= nil then
		return memo[value]
	end
	local output = {}
	memo[value] = output
	for key, child in value do
		output[clone(key, memo)] = clone(child, memo)
	end
	return output
end

local function freezeDeep(value: any): any
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			freezeDeep(child)
		end
		table.freeze(value)
	end
	return value
end

local function plain(value: unknown): { [any]: unknown }?
	return if type(value) == "table" and getmetatable(value :: any) == nil then value :: { [any]: unknown } else nil
end

local function onlyFields(record: { [any]: unknown }, fields: { [string]: boolean }): boolean
	for key in record do
		if type(key) ~= "string" or fields[key] ~= true then
			return false
		end
	end
	return true
end

local function exactFields(record: { [any]: unknown }, fields: { [string]: boolean }): boolean
	if not onlyFields(record, fields) then
		return false
	end
	for key in fields do
		if rawget(record, key) == nil then
			return false
		end
	end
	return true
end

local function safeInteger(value: unknown, minimum: number, maximum: number): number?
	return if type(value) == "number"
			and Validation.isSafeInteger(value :: number)
			and (value :: number) >= minimum
			and (value :: number) <= maximum
		then value :: number
		else nil
end

local function boundedToken(value: unknown, prefix: string?): string?
	if type(value) ~= "string" or #value < 1 or #value > MAX_TOKEN_BYTES then
		return nil
	end
	if prefix ~= nil and string.sub(value :: string, 1, #prefix + 1) ~= `{prefix}:` then
		return nil
	end
	for index = 1, #value do
		local byte = string.byte(value :: string, index)
		if byte < 33 or byte > 126 then
			return nil
		end
	end
	return value :: string
end

local function denseArray(value: unknown, maximum: number, minimum: number): { unknown }?
	local record = plain(value)
	if record == nil then
		return nil
	end
	local count = 0
	local largest = 0
	for key in record do
		if type(key) ~= "number" or not Validation.isSafeInteger(key) or key < 1 then
			return nil
		end
		count += 1
		largest = math.max(largest, key)
	end
	if count ~= largest or count < minimum or count > maximum then
		return nil
	end
	return value :: { unknown }
end

local function normalizedSettings(value: unknown): { [string]: boolean | number }?
	local record = plain(value)
	if record == nil or not exactFields(record, SETTINGS_FIELDS) or record.version ~= 2 then
		return nil
	end
	for _, field in { "masterVolume", "musicVolume", "sfxVolume", "uiVolume", "cameraShakeIntensity" } do
		local numberValue = record[field]
		if
			type(numberValue) ~= "number"
			or not Validation.isFiniteNumber(numberValue :: number)
			or numberValue < 0
			or numberValue > 1
		then
			return nil
		end
	end
	if
		type(record.uiScale) ~= "number"
		or not Validation.isFiniteNumber(record.uiScale :: number)
		or record.uiScale < 0.75
		or record.uiScale > 1.25
	then
		return nil
	end
	for _, field in
		{
			"damageNumbersEnabled",
			"enemyHealthBarsEnabled",
			"otherPlayerEffectsEnabled",
			"lowDetailEnabled",
			"towerRangeEnabled",
			"reducedMotionEnabled",
		}
	do
		if type(record[field]) ~= "boolean" then
			return nil
		end
	end
	return clone(record)
end

local function normalizedLoadout(value: unknown, expectedUserId: number): LoadoutSnapshot?
	local record = plain(value)
	if record == nil or not exactFields(record, LOADOUT_FIELDS) or record.userId ~= expectedUserId then
		return nil
	end
	local revision = safeInteger(record.revision, 1, Validation.MAX_SAFE_INTEGER)
	local source = denseArray(record.slots, MAX_SLOTS, 1)
	local settings = normalizedSettings(record.settings)
	if revision == nil or source == nil or settings == nil then
		return nil
	end
	local slots: { LoadoutSlot } = table.create(#source)
	local units: { [string]: boolean } = {}
	local towers: { [string]: boolean } = {}
	for index, rawSlot in source do
		local slot = plain(rawSlot)
		if slot == nil or not exactFields(slot, SLOT_FIELDS) or slot.slot ~= index then
			return nil
		end
		local unitId = boundedToken(slot.unitId, "unit")
		local towerId = boundedToken(slot.towerId, "tower")
		if unitId == nil or towerId == nil or units[unitId] or towers[towerId] then
			return nil
		end
		units[unitId] = true
		towers[towerId] = true
		slots[index] = { slot = index, unitId = unitId, towerId = towerId }
	end
	return {
		userId = expectedUserId,
		revision = revision,
		slots = slots,
		settings = settings,
	}
end

function MatchTicketContract.clone<T>(value: T): T
	return clone(value)
end

function MatchTicketContract.validate(value: unknown): Result.Result<Ticket, TicketError>
	local record = plain(value)
	if record == nil or not onlyFields(record, ROOT_FIELDS) then
		return failure("INVALID_TICKET", "ticket")
	end
	for _, required in
		{
			"version",
			"revision",
			"ticketId",
			"matchId",
			"resultId",
			"expectedUserIds",
			"captainUserId",
			"mapId",
			"difficultyId",
			"privacy",
			"lobbyOrigin",
			"members",
			"createdAt",
			"expiresAt",
			"state",
			"retryCount",
		}
	do
		if rawget(record, required) == nil then
			return failure("INVALID_TICKET", `ticket.{required}`)
		end
	end
	local ticketId = TravelProtocol.validateOpaqueId(record.ticketId, "ticket")
	local revision = safeInteger(record.revision, 1, Validation.MAX_SAFE_INTEGER)
	local matchId = boundedToken(record.matchId, "match")
	local resultId = boundedToken(record.resultId, "result")
	local captainUserId = safeInteger(record.captainUserId, 1, Validation.MAX_SAFE_INTEGER)
	local mapId = boundedToken(record.mapId, "map")
	local difficultyId = boundedToken(record.difficultyId, "difficulty")
	local privacy = record.privacy
	local createdAt = safeInteger(record.createdAt, 0, Validation.MAX_SAFE_INTEGER)
	local expiresAt = safeInteger(record.expiresAt, 0, Validation.MAX_SAFE_INTEGER)
	local retryCount = safeInteger(record.retryCount, 0, MAX_RETRIES)
	if
		record.version ~= VERSION
		or not ticketId.ok
		or revision == nil
		or matchId == nil
		or resultId == nil
		or #resultId > 43
		or captainUserId == nil
		or mapId == nil
		or difficultyId == nil
		or (privacy ~= "Public" and privacy ~= "PartyOnly")
		or createdAt == nil
		or expiresAt == nil
		or expiresAt <= createdAt
		or expiresAt - createdAt > MAX_TTL_SECONDS
		or retryCount == nil
		or type(record.state) ~= "string"
		or TICKET_STATES[record.state :: string] ~= true
	then
		return failure("INVALID_TICKET", "ticket")
	end

	local origin = plain(record.lobbyOrigin)
	local originPlaceId = if origin == nil then nil else safeInteger(origin.placeId, 1, Validation.MAX_SAFE_INTEGER)
	local originJobId = if origin == nil then nil else boundedToken(origin.jobId, nil)
	if origin == nil or not exactFields(origin, ORIGIN_FIELDS) or originPlaceId == nil or originJobId == nil then
		return failure("INVALID_TICKET", "ticket.lobbyOrigin")
	end

	local rawUserIds = denseArray(record.expectedUserIds, MAX_MEMBERS, 1)
	local rawMembers = denseArray(record.members, MAX_MEMBERS, 1)
	if rawUserIds == nil or rawMembers == nil or #rawUserIds ~= #rawMembers then
		return failure("CAPACITY_EXCEEDED", "ticket.expectedUserIds")
	end
	local expectedUserIds: { number } = table.create(#rawUserIds)
	local members: { Member } = table.create(#rawMembers)
	local seen: { [number]: boolean } = {}
	local captainFound = false
	for index, rawUserId in rawUserIds do
		local userId = safeInteger(rawUserId, 1, Validation.MAX_SAFE_INTEGER)
		local member = plain(rawMembers[index])
		if
			userId == nil
			or seen[userId]
			or member == nil
			or not onlyFields(member, MEMBER_FIELDS)
			or member.userId ~= userId
		then
			return failure("INVALID_TICKET", `ticket.members[{index}]`)
		end
		for _, required in { "userId", "loadout", "admissionState" } do
			if rawget(member, required) == nil then
				return failure("INVALID_TICKET", `ticket.members[{index}].{required}`)
			end
		end
		local loadout = normalizedLoadout(member.loadout, userId)
		local state = member.admissionState
		local admittedAt = if member.admittedAt == nil
			then nil
			else safeInteger(member.admittedAt, createdAt, expiresAt)
		if
			loadout == nil
			or type(state) ~= "string"
			or ADMISSION_STATES[state :: string] ~= true
			or ((state == "Expected") ~= (admittedAt == nil))
		then
			return failure("INVALID_LOADOUT", `ticket.members[{index}]`)
		end
		seen[userId] = true
		captainFound = captainFound or userId == captainUserId
		expectedUserIds[index] = userId
		members[index] = {
			userId = userId,
			loadout = loadout,
			admissionState = state :: AdmissionState,
			admittedAt = admittedAt,
		}
	end
	if not captainFound then
		return failure("INVALID_TICKET", "ticket.captainUserId")
	end

	local destinationJobId = if record.claimedDestinationJobId == nil
		then nil
		else boundedToken(record.claimedDestinationJobId, nil)
	local destinationAt = if record.claimedDestinationAt == nil
		then nil
		else safeInteger(record.claimedDestinationAt, createdAt, expiresAt)
	if (destinationJobId == nil) ~= (destinationAt == nil) then
		return failure("INVALID_STATE", "ticket.claimedDestinationJobId")
	end
	local state = record.state :: TicketState
	if
		(state == "Active" and destinationJobId == nil)
		or ((state == "Created" or state == "Teleporting") and destinationJobId ~= nil)
	then
		return failure("INVALID_STATE", "ticket.state")
	end
	local terminalReason = if record.terminalReason == nil then nil else boundedToken(record.terminalReason, nil)
	if (state == "Terminal") ~= (terminalReason ~= nil) then
		return failure("INVALID_STATE", "ticket.terminalReason")
	end

	local ticket: Ticket = {
		version = VERSION,
		revision = revision,
		ticketId = ticketId.value,
		matchId = matchId,
		resultId = resultId,
		expectedUserIds = expectedUserIds,
		captainUserId = captainUserId,
		mapId = mapId,
		difficultyId = difficultyId,
		privacy = privacy :: Privacy,
		lobbyOrigin = { placeId = originPlaceId, jobId = originJobId },
		members = members,
		createdAt = createdAt,
		expiresAt = expiresAt,
		claimedDestinationJobId = destinationJobId,
		claimedDestinationAt = destinationAt,
		state = state,
		retryCount = retryCount,
		terminalReason = terminalReason,
	}
	return Result.ok(freezeDeep(ticket) :: Ticket)
end

function MatchTicketContract.member(ticket: Ticket, userId: number): (Member?, number?)
	for index, member in ticket.members do
		if member.userId == userId then
			return member, index
		end
	end
	return nil, nil
end

return table.freeze(MatchTicketContract)
