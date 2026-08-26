local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local Cleanup = require(ReplicatedStorage.Shared.util.Cleanup)

local placeId = game.PlaceId
local isStudio = RunService:IsStudio()
local unresolvedContext = EnvironmentContext.new("server", "Unresolved", placeId, isStudio)
local unresolvedLog = Log.new(unresolvedContext)

local configurationResult = PlaceRoles.validateConfiguration()
if not configurationResult.ok then
	unresolvedLog:error("place-role", "configuration_rejected", configurationResult.message, {
		code = configurationResult.code,
	})
	return
end

local roleResult = PlaceRoles.resolve(ReplicatedStorage:GetAttribute(PlaceRoles.ATTRIBUTE_NAME), placeId, isStudio)

if not roleResult.ok then
	unresolvedLog:error("place-role", "boot_rejected", roleResult.message, {
		code = roleResult.code,
	})
	return
end

local environmentContext = EnvironmentContext.withRole(unresolvedContext, roleResult.role)
local log = Log.new(environmentContext)

local lifecycleRunner = ServiceLifecycle.new(log)
lifecycleRunner:initialize()
lifecycleRunner:start()

local bootstrapCleanup = Cleanup.new(log, "bootstrap")
bootstrapCleanup:add(function()
	if lifecycleRunner:getState() == "Started" then
		lifecycleRunner:shutdown()
	end
end)

log:info("bootstrap", "ready", "Server bootstrap ready", {
	cleanupState = bootstrapCleanup:getState(),
	cleanupTaskCount = bootstrapCleanup:getTaskCount(),
	lifecycleState = lifecycleRunner:getState(),
	serviceCount = lifecycleRunner:getRegisteredServiceCount(),
})
