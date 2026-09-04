--!strict

export type Token = {}

export type Ownership = {
	player: unknown,
	token: Token,
}

export type OwnershipByUserId = { [number]: Ownership }

local PlayerReadyOwnership = {}

function PlayerReadyOwnership.acquire(ownershipByUserId: OwnershipByUserId, userId: number, player: unknown): Token?
	if ownershipByUserId[userId] ~= nil then
		return nil
	end
	local token = {}
	ownershipByUserId[userId] = {
		player = player,
		token = token,
	}
	return token
end

function PlayerReadyOwnership.release(
	ownershipByUserId: OwnershipByUserId,
	userId: number,
	player: unknown,
	token: Token
): boolean
	local ownership = ownershipByUserId[userId]
	if ownership == nil or ownership.player ~= player or ownership.token ~= token then
		return false
	end
	ownershipByUserId[userId] = nil
	return true
end

function PlayerReadyOwnership.removePlayer(
	ownershipByUserId: OwnershipByUserId,
	userId: number,
	player: unknown
): boolean
	local ownership = ownershipByUserId[userId]
	if ownership == nil or ownership.player ~= player then
		return false
	end
	ownershipByUserId[userId] = nil
	return true
end

return table.freeze(PlayerReadyOwnership)
