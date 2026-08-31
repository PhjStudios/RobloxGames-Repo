--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)

local LobbyProtocol = {
	ENDPOINTS = table.freeze({
		GET_PROFILE = "GetLobbyProfile",
		RETRY_PROFILE = "RetryLobbyProfile",
		GET_INVENTORY = "GetLobbyInventory",
		EQUIP_TOWER = "EquipLobbyTower",
		UNEQUIP_TOWER = "UnequipLobbyTower",
		FAVORITE_TOWER = "FavoriteLobbyTower",
		LOCK_TOWER = "LockLobbyTower",
		GET_BANNER = "GetLobbyBanner",
		PULL_CHEST = "PullLobbyChest",
		UPDATE_SETTINGS = "UpdateLobbySettings",
		PROFILE_REPLICATION = "LobbyProfileReplication",
		INVENTORY_REPLICATION = "LobbyInventoryReplication",
	}),
	EmptyPayloadSchema = PayloadValidation.schema(PayloadValidation.record({})),
	BannerRequestSchema = PayloadValidation.schema(PayloadValidation.record({
		bannerId = PayloadValidation.id("banner"),
	})),
}

return table.freeze(LobbyProtocol)
