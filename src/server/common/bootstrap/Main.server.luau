local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local EnvironmentContext = require(ReplicatedStorage.Shared.logging.EnvironmentContext)
local Log = require(ReplicatedStorage.Shared.logging.Log)
local ProductionRemotes = require(ReplicatedStorage.Shared.network.ProductionRemotes)
local ServiceLifecycle = require(ReplicatedStorage.Shared.lifecycle.ServiceLifecycle)
local Cleanup = require(ReplicatedStorage.Shared.util.Cleanup)
local ProductionRateLimits = require(script.Parent.Parent.networking.ProductionRateLimits)
local ServerRemoteRegistry = require(script.Parent.Parent.networking.ServerRemoteRegistry)
local Shutdown = require(script.Parent.Shutdown)

local placeId = game.PlaceId
local isStudio = RunService:IsStudio()
local unresolvedContext = EnvironmentContext.new("server", "Unresolved", placeId, isStudio)
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

local serverRemoteRegistry =
	ServerRemoteRegistry.new(log, ProductionRemotes, ReplicatedStorage, roleResult.role, ProductionRateLimits)
local lifecycleRunner = ServiceLifecycle.new(log)
lifecycleRunner:register(serverRemoteRegistry:getServiceDefinition())
lifecycleRunner:initialize()
lifecycleRunner:start()

local bootstrapCleanup = Cleanup.new(log, "bootstrap")
bootstrapCleanup:add(function()
	if lifecycleRunner:getState() == "Started" then
		lifecycleRunner:shutdown()
	end
end)

game:BindToClose(function(closeReason)
	local closeReasonName = if typeof(closeReason) == "EnumItem" then closeReason.Name else "Unknown"

	log:info("shutdown", "started", "Server shutdown started", {
		budgetSeconds = Shutdown.DEFAULT_BUDGET_SECONDS,
		closeReason = closeReasonName,
	})

	local runnerSucceeded, shutdownResult = pcall(function()
		return Shutdown.run(log, function()
			bootstrapCleanup:cleanup()
		end, Shutdown.DEFAULT_BUDGET_SECONDS)
	end)

	if not runnerSucceeded then
		log:warn("shutdown", "runner_failed", "Server shutdown runner failed", {
			cleanupState = bootstrapCleanup:getState(),
			code = "SHUTDOWN_RUNNER_FAILED",
			lifecycleState = lifecycleRunner:getState(),
		})
		return
	end

	if shutdownResult.status == "Completed" then
		log:info("shutdown", "completed", "Server shutdown completed", {
			cleanupState = bootstrapCleanup:getState(),
			lifecycleState = lifecycleRunner:getState(),
		})
	elseif shutdownResult.status == "Failed" then
		log:warn("shutdown", "failed", "Server shutdown cleanup failed", {
			cleanupState = bootstrapCleanup:getState(),
			code = "SHUTDOWN_FAILED",
			lifecycleState = lifecycleRunner:getState(),
		})
	else
		log:warn("shutdown", "timed_out", "Server shutdown cleanup timed out", {
			budgetSeconds = Shutdown.DEFAULT_BUDGET_SECONDS,
			cleanupState = bootstrapCleanup:getState(),
			code = "SHUTDOWN_TIMED_OUT",
			lifecycleState = lifecycleRunner:getState(),
		})
	end
end)

log:info("bootstrap", "ready", "Server bootstrap ready", {
	cleanupState = bootstrapCleanup:getState(),
	cleanupTaskCount = bootstrapCleanup:getTaskCount(),
	lifecycleState = lifecycleRunner:getState(),
	serviceCount = lifecycleRunner:getRegisteredServiceCount(),
})
