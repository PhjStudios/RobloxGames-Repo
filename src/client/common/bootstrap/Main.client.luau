local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local Cleanup = require(ReplicatedStorage.Shared.util.Cleanup)

local placeId = game.PlaceId
local isStudio = RunService:IsStudio()
local unresolvedContext = EnvironmentContext.new("client", "Unresolved", placeId, isStudio)
local unresolvedLog = Log.new(unresolvedContext)

local placeConfigurationResult = PlaceRoles.validateConfiguration()
if not placeConfigurationResult.ok then
	unresolvedLog:error("place-role", "configuration_rejected", placeConfigurationResult.message, {
		code = placeConfigurationResult.code,
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

local coreConfigurationResult = ConfigurationValidator.validateLoaded()
if not coreConfigurationResult.ok then
	local report = coreConfigurationResult.error
	local firstIssue = report.firstIssue
	log:error("configuration", "validation_failed", "Core configuration validation failed", {
		code = firstIssue.code,
		issueCount = #report.issues,
		validationPath = firstIssue.path,
	})
	return
end

log:info("configuration", "validated", "Core configuration validated", {
	configurationFamilyCount = ConfigurationValidator.FAMILY_COUNT,
})

local lifecycleRunner = ServiceLifecycle.new(log)
lifecycleRunner:initialize()
lifecycleRunner:start()

local bootstrapCleanup = Cleanup.new(log, "bootstrap")
bootstrapCleanup:add(function()
	if lifecycleRunner:getState() == "Started" then
		lifecycleRunner:shutdown()
	end
end)

log:info("bootstrap", "ready", "Client bootstrap ready", {
	cleanupState = bootstrapCleanup:getState(),
	cleanupTaskCount = bootstrapCleanup:getTaskCount(),
	lifecycleState = lifecycleRunner:getState(),
	serviceCount = lifecycleRunner:getRegisteredServiceCount(),
})
