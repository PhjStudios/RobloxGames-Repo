--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local ClientBootstrap = require(script.Parent.ClientBootstrap)
local MatchReadyController = require(script.Parent.Parent.Parent.match.MatchReadyController)
local EnemyController = require(script.Parent.Parent.Parent.match.enemies.EnemyController)

local MATCH_ROLE = "Match" :: PlaceRoles.PlaceRole

local handle = ClientBootstrap.run(MATCH_ROLE, function(configuration)
	local controllerResult = MatchReadyController.new(configuration.log)
	if not controllerResult.ok then
		error("[ATD_MATCH_CLIENT_BOOTSTRAP][code=CONTROLLER_CREATION_FAILED]", 0)
	end
	configuration.lifecycleRunner:register(controllerResult.value:getServiceDefinition())

	local enemyControllerResult = EnemyController.new(configuration.log)
	if not enemyControllerResult.ok then
		error("[ATD_MATCH_CLIENT_BOOTSTRAP][code=ENEMY_CONTROLLER_CREATION_FAILED]", 0)
	end
	configuration.lifecycleRunner:register(enemyControllerResult.value:getServiceDefinition())
end)

if handle ~= nil then
	local destroyingConnection = script.Destroying:Connect(function()
		handle.cleanup:cleanup()
	end)
	handle.cleanup:add(destroyingConnection)
end
