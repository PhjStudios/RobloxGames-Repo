--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local ClientBootstrap = require(script.Parent.ClientBootstrap)
local LobbyController = require(script.Parent.Parent.Parent.lobby.LobbyController)

local LOBBY_ROLE = "Lobby" :: PlaceRoles.PlaceRole

local handle = ClientBootstrap.run(LOBBY_ROLE, function(configuration)
	local controllerResult = LobbyController.new(configuration.log, configuration.coreConfiguration)
	if not controllerResult.ok then
		error("[ATD_LOBBY_CLIENT_BOOTSTRAP][code=LOBBY_CONTROLLER_CREATION_FAILED]", 0)
	end
	configuration.lifecycleRunner:register(controllerResult.value:getServiceDefinition())
end)

if handle ~= nil then
	local destroyingConnection = script.Destroying:Connect(function()
		handle.cleanup:cleanup()
	end)
	handle.cleanup:add(destroyingConnection)
end
