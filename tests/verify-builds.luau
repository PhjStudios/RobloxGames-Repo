--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

type BuildDefinition = {
	name: string,
	project: string,
	output: string,
	role: "Default" | "Lobby" | "Match" | "Test",
}

type SourceDefinition = {
	dataModelPath: string,
	className: "ModuleScript" | "Script" | "LocalScript",
	sourcePath: string,
}

local BUILD_DIRECTORY = "build"
local BUILDS: { BuildDefinition } = {
	{ name = "Default", project = "default.project.json", output = "build/verify-default.rbxlx", role = "Default" },
	{ name = "Lobby", project = "lobby.project.json", output = "build/verify-lobby.rbxlx", role = "Lobby" },
	{ name = "Match", project = "match.project.json", output = "build/verify-match.rbxlx", role = "Match" },
	{ name = "Test", project = "test.project.json", output = "build/verify-test.rbxlx", role = "Test" },
}
local EXPECTED_PRODUCTION_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Assets",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Assets.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.AssetSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/AssetSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Banners",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Banners.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.BannerSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/BannerSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.ConfigurationValidator",
		className = "ModuleScript",
		sourcePath = "src/shared/config/ConfigurationValidator.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.DefaultSettings",
		className = "ModuleScript",
		sourcePath = "src/shared/config/DefaultSettings.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Difficulties",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Difficulties.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.DifficultySchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/DifficultySchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Economy",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Economy.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.EconomySchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/EconomySchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Enemies",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Enemies.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.EnemySchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/EnemySchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Maps",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Maps.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.MapSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/MapSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.PlaceRoles",
		className = "ModuleScript",
		sourcePath = "src/shared/config/PlaceRoles.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.SchemaPrimitives",
		className = "ModuleScript",
		sourcePath = "src/shared/config/SchemaPrimitives.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.SettingsSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/SettingsSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Towers",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Towers.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.TowerSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/TowerSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.Waves",
		className = "ModuleScript",
		sourcePath = "src/shared/config/Waves.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.config.WaveSchema",
		className = "ModuleScript",
		sourcePath = "src/shared/config/WaveSchema.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.lifecycle.ServiceLifecycle",
		className = "ModuleScript",
		sourcePath = "src/shared/lifecycle/ServiceLifecycle.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.logging.EnvironmentContext",
		className = "ModuleScript",
		sourcePath = "src/shared/logging/EnvironmentContext.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.logging.Log",
		className = "ModuleScript",
		sourcePath = "src/shared/logging/Log.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.match.MatchProtocol",
		className = "ModuleScript",
		sourcePath = "src/shared/match/MatchProtocol.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.match.BaseProtocol",
		className = "ModuleScript",
		sourcePath = "src/shared/match/BaseProtocol.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.match.EnemyProtocol",
		className = "ModuleScript",
		sourcePath = "src/shared/match/EnemyProtocol.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.match.WaveProtocol",
		className = "ModuleScript",
		sourcePath = "src/shared/match/WaveProtocol.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.network.ProductionRemotes",
		className = "ModuleScript",
		sourcePath = "src/shared/network/ProductionRemotes.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.network.PayloadValidation",
		className = "ModuleScript",
		sourcePath = "src/shared/network/PayloadValidation.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.network.RemoteRegistry",
		className = "ModuleScript",
		sourcePath = "src/shared/network/RemoteRegistry.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.network.RequestProtocol",
		className = "ModuleScript",
		sourcePath = "src/shared/network/RequestProtocol.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.types.ConfigTypes",
		className = "ModuleScript",
		sourcePath = "src/shared/types/ConfigTypes.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.util.Cleanup",
		className = "ModuleScript",
		sourcePath = "src/shared/util/Cleanup.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.util.Ids",
		className = "ModuleScript",
		sourcePath = "src/shared/util/Ids.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.util.Result",
		className = "ModuleScript",
		sourcePath = "src/shared/util/Result.luau",
	},
	{
		dataModelPath = "ReplicatedStorage.Shared.util.Validation",
		className = "ModuleScript",
		sourcePath = "src/shared/util/Validation.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.bootstrap.Main",
		className = "Script",
		sourcePath = "src/server/common/bootstrap/Main.server.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.bootstrap.ServerBootstrap",
		className = "ModuleScript",
		sourcePath = "src/server/common/bootstrap/ServerBootstrap.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.bootstrap.Shutdown",
		className = "ModuleScript",
		sourcePath = "src/server/common/bootstrap/Shutdown.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.networking.ProductionRateLimits",
		className = "ModuleScript",
		sourcePath = "src/server/common/networking/ProductionRateLimits.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.networking.ServerRemoteRegistry",
		className = "ModuleScript",
		sourcePath = "src/server/common/networking/ServerRemoteRegistry.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.networking.ServerRateLimiter",
		className = "ModuleScript",
		sourcePath = "src/server/common/networking/ServerRateLimiter.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.common.networking.ServerRequestDispatcher",
		className = "ModuleScript",
		sourcePath = "src/server/common/networking/ServerRequestDispatcher.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.common.bootstrap.Main",
		className = "LocalScript",
		sourcePath = "src/client/common/bootstrap/Main.client.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.common.bootstrap.ClientBootstrap",
		className = "ModuleScript",
		sourcePath = "src/client/common/bootstrap/ClientBootstrap.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.common.networking.ClientRemoteLookup",
		className = "ModuleScript",
		sourcePath = "src/client/common/networking/ClientRemoteLookup.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.common.networking.ClientRequestTracker",
		className = "ModuleScript",
		sourcePath = "src/client/common/networking/ClientRequestTracker.luau",
	},
})
local EXPECTED_MATCH_SERVER_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ServerScriptService.Server.match.maps.MapContract",
		className = "ModuleScript",
		sourcePath = "src/server/match/maps/MapContract.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.maps.MapLoader",
		className = "ModuleScript",
		sourcePath = "src/server/match/maps/MapLoader.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.maps.MapValidator",
		className = "ModuleScript",
		sourcePath = "src/server/match/maps/MapValidator.luau",
	},
})
local EXPECTED_MATCH_BASE_SERVER_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ServerScriptService.Server.match.base.BaseReplicationPublisher",
		className = "ModuleScript",
		sourcePath = "src/server/match/base/BaseReplicationPublisher.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.base.BaseRuntime",
		className = "ModuleScript",
		sourcePath = "src/server/match/base/BaseRuntime.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.base.BaseRuntimeService",
		className = "ModuleScript",
		sourcePath = "src/server/match/base/BaseRuntimeService.luau",
	},
})
local EXPECTED_MATCH_ENEMY_SERVER_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ServerScriptService.Server.match.enemies.EnemyPath",
		className = "ModuleScript",
		sourcePath = "src/server/match/enemies/EnemyPath.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.enemies.EnemyReplicationPublisher",
		className = "ModuleScript",
		sourcePath = "src/server/match/enemies/EnemyReplicationPublisher.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.enemies.EnemyRuntimeStore",
		className = "ModuleScript",
		sourcePath = "src/server/match/enemies/EnemyRuntimeStore.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.enemies.EnemySimulationService",
		className = "ModuleScript",
		sourcePath = "src/server/match/enemies/EnemySimulationService.luau",
	},
})
local EXPECTED_MATCH_WAVE_SERVER_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ServerScriptService.Server.match.waves.WaveReplicationPublisher",
		className = "ModuleScript",
		sourcePath = "src/server/match/waves/WaveReplicationPublisher.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.waves.WaveRuntime",
		className = "ModuleScript",
		sourcePath = "src/server/match/waves/WaveRuntime.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.waves.WaveRuntimeService",
		className = "ModuleScript",
		sourcePath = "src/server/match/waves/WaveRuntimeService.luau",
	},
})
local EXPECTED_MATCH_LIFECYCLE_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ServerScriptService.Server.match.lifecycle.MatchLifecycleService",
		className = "ModuleScript",
		sourcePath = "src/server/match/lifecycle/MatchLifecycleService.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.lifecycle.MatchStateMachine",
		className = "ModuleScript",
		sourcePath = "src/server/match/lifecycle/MatchStateMachine.luau",
	},
})
local EXPECTED_MATCH_ROSTER_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ServerScriptService.Server.match.roster.ParticipantRoster",
		className = "ModuleScript",
		sourcePath = "src/server/match/roster/ParticipantRoster.luau",
	},
})
local EXPECTED_MATCH_READY_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ServerScriptService.Server.match.ready.ReadyCheckCoordinator",
		className = "ModuleScript",
		sourcePath = "src/server/match/ready/ReadyCheckCoordinator.luau",
	},
	{
		dataModelPath = "ServerScriptService.Server.match.ready.SnapshotBroadcaster",
		className = "ModuleScript",
		sourcePath = "src/server/match/ready/SnapshotBroadcaster.luau",
	},
})
local EXPECTED_MATCH_CLIENT_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.MatchReadyController",
		className = "ModuleScript",
		sourcePath = "src/client/match/MatchReadyController.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.MatchReadyView",
		className = "ModuleScript",
		sourcePath = "src/client/match/MatchReadyView.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.MatchReadyViewModel",
		className = "ModuleScript",
		sourcePath = "src/client/match/MatchReadyViewModel.luau",
	},
})
local EXPECTED_MATCH_BASE_CLIENT_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.base.BaseController",
		className = "ModuleScript",
		sourcePath = "src/client/match/base/BaseController.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.base.BaseStateReducer",
		className = "ModuleScript",
		sourcePath = "src/client/match/base/BaseStateReducer.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.base.BaseViewModel",
		className = "ModuleScript",
		sourcePath = "src/client/match/base/BaseViewModel.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.base.BaseWorldView",
		className = "ModuleScript",
		sourcePath = "src/client/match/base/BaseWorldView.luau",
	},
})
local EXPECTED_MATCH_ENEMY_CLIENT_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.enemies.EnemyController",
		className = "ModuleScript",
		sourcePath = "src/client/match/enemies/EnemyController.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.enemies.EnemyPresentation",
		className = "ModuleScript",
		sourcePath = "src/client/match/enemies/EnemyPresentation.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.enemies.EnemyRenderer",
		className = "ModuleScript",
		sourcePath = "src/client/match/enemies/EnemyRenderer.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.enemies.EnemyReplicationState",
		className = "ModuleScript",
		sourcePath = "src/client/match/enemies/EnemyReplicationState.luau",
	},
})
local EXPECTED_MATCH_WAVE_CLIENT_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.waves.WaveController",
		className = "ModuleScript",
		sourcePath = "src/client/match/waves/WaveController.luau",
	},
	{
		dataModelPath = "StarterPlayer.StarterPlayerScripts.Client.match.waves.WaveStateReducer",
		className = "ModuleScript",
		sourcePath = "src/client/match/waves/WaveStateReducer.luau",
	},
})
local EXPECTED_TEST_OWNED_SOURCES: { SourceDefinition } = table.freeze({
	{
		dataModelPath = "ServerStorage.AutomatedTests.Fixtures.BaseFixtures",
		className = "ModuleScript",
		sourcePath = "tests/fixtures/BaseFixtures.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Fixtures.ConfigurationFixtures",
		className = "ModuleScript",
		sourcePath = "tests/fixtures/ConfigurationFixtures.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Fixtures.EnemyFixtures",
		className = "ModuleScript",
		sourcePath = "tests/fixtures/EnemyFixtures.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Fixtures.MapFixtures",
		className = "ModuleScript",
		sourcePath = "tests/fixtures/MapFixtures.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Fixtures.NetworkFixtures",
		className = "ModuleScript",
		sourcePath = "tests/fixtures/NetworkFixtures.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Fixtures.WaveFixtures",
		className = "ModuleScript",
		sourcePath = "tests/fixtures/WaveFixtures.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.AuthenticatedWaveFixtures.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/AuthenticatedWaveFixtures.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.Cleanup.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/Cleanup.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.BaseController.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/BaseController.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.BaseDefeatIntegration.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/BaseDefeatIntegration.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.BaseProtocol.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/BaseProtocol.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.BaseReplicationPublisher.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/BaseReplicationPublisher.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.BaseRuntime.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/BaseRuntime.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.BaseRuntimeService.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/BaseRuntimeService.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.BaseStateReducer.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/BaseStateReducer.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.BaseViewModel.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/BaseViewModel.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.BaseWorldView.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/BaseWorldView.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ClientRequestTracker.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ClientRequestTracker.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ConfigurationContractEdges.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ConfigurationContractEdges.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ConfigurationFailures.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ConfigurationFailures.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ConfigurationLoaded.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ConfigurationLoaded.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ConfigurationPrivacy.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ConfigurationPrivacy.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ConfigurationSchemas.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ConfigurationSchemas.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.CoreContracts.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/CoreContracts.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.EnemyController.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/EnemyController.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.EnemyMovement.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/EnemyMovement.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.EnemyPath.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/EnemyPath.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.EnemyPresentation.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/EnemyPresentation.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.EnemyProtocol.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/EnemyProtocol.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.EnemyRenderer.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/EnemyRenderer.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.EnemyReplicationPublisher.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/EnemyReplicationPublisher.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.EnemyReplicationState.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/EnemyReplicationState.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.EnemyRuntimeStore.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/EnemyRuntimeStore.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.EnemySimulationIntegration.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/EnemySimulationIntegration.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.EnemySimulationService.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/EnemySimulationService.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MapContract.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MapContract.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MapLoader.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MapLoader.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MapValidator.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MapValidator.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MatchLifecycleService.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MatchLifecycleService.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MatchProtocol.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MatchProtocol.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MatchReadyController.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MatchReadyController.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MatchReadyView.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MatchReadyView.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MatchReadyViewModel.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MatchReadyViewModel.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.MatchStateMachine.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/MatchStateMachine.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.NetworkSecurity.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/NetworkSecurity.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.PayloadValidation.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/PayloadValidation.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ParticipantRoster.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ParticipantRoster.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.RemoteRegistry.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/RemoteRegistry.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.RemoteRuntime.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/RemoteRuntime.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ReadyCheckCoordinator.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ReadyCheckCoordinator.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.SnapshotBroadcaster.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/SnapshotBroadcaster.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.RequestProtocol.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/RequestProtocol.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ServerRateLimiter.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ServerRateLimiter.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.ServerRequestDispatcher.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/ServerRequestDispatcher.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.Smoke.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/Smoke.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.WaveController.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/WaveController.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.WaveProtocol.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/WaveProtocol.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.WaveReplicationPublisher.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/WaveReplicationPublisher.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.WaveRuntime.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/WaveRuntime.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.WaveRuntimeIntegration.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/WaveRuntimeIntegration.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.WaveRuntimeService.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/WaveRuntimeService.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Specs.WaveStateReducer.spec",
		className = "ModuleScript",
		sourcePath = "tests/specs/WaveStateReducer.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Support.RobloxAdapter",
		className = "ModuleScript",
		sourcePath = "tests/support/RobloxAdapter.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Support.TestHarness",
		className = "ModuleScript",
		sourcePath = "tests/support/TestHarness.luau",
	},
	{
		dataModelPath = "ServerStorage.AutomatedTests.Support.TestRunner",
		className = "ModuleScript",
		sourcePath = "tests/support/TestRunner.luau",
	},
	{
		dataModelPath = "ServerStorage.NegativeControls.Assertion.IntentionalFailure.spec",
		className = "ModuleScript",
		sourcePath = "tests/negative/assertion/IntentionalFailure.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.NegativeControls.Dependencies.BrokenDependency",
		className = "ModuleScript",
		sourcePath = "tests/negative/dependencies/BrokenDependency.luau",
	},
	{
		dataModelPath = "ServerStorage.NegativeControls.MalformedDiscovery.Misnamed",
		className = "ModuleScript",
		sourcePath = "tests/negative/malformed-discovery/Misnamed.luau",
	},
	{
		dataModelPath = "ServerStorage.NegativeControls.MalformedRoot.Specs.WouldPass.spec",
		className = "ModuleScript",
		sourcePath = "tests/negative/malformed-root/WouldPass.spec.luau",
	},
	{
		dataModelPath = "ServerStorage.NegativeControls.ModuleLoad.IntentionalLoadFailure.spec",
		className = "ModuleScript",
		sourcePath = "tests/negative/module-load/IntentionalLoadFailure.spec.luau",
	},
})

local createdBuildDirectory = false
local ownedOutputs: { [string]: boolean } = {}
local currentStage = "startup"

local function normalizeNewlines(value: string): string
	return string.gsub(value, "\r\n", "\n")
end

local function verifyPhase11Scope(): boolean
	local exactEmptyConfigs = {
		{
			path = "src/shared/config/Enemies.luau",
			expected = table.concat({
				"--!strict",
				"",
				"local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)",
				"",
				"local Enemies: { ConfigTypes.EnemyDefinition } = {}",
				"",
				"return table.freeze(Enemies)",
				"",
			}, "\n"),
		},
		{
			path = "src/shared/config/Assets.luau",
			expected = table.concat({
				"--!strict",
				"",
				"local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)",
				"",
				"local Assets: { ConfigTypes.AssetDefinition } = {}",
				"",
				"return table.freeze(Assets)",
				"",
			}, "\n"),
		},
		{
			path = "src/shared/config/Difficulties.luau",
			expected = table.concat({
				"--!strict",
				"",
				"local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)",
				"",
				"-- Authored difficulty content is intentionally empty until a content packet.",
				"local Difficulties: { ConfigTypes.DifficultyDefinition } = {}",
				"",
				"return table.freeze(Difficulties)",
				"",
			}, "\n"),
		},
		{
			path = "src/shared/config/Maps.luau",
			expected = table.concat({
				"--!strict",
				"",
				"local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)",
				"",
				"-- Authored map content is intentionally empty until a content packet.",
				"local Maps: { ConfigTypes.MapDefinition } = {}",
				"",
				"return table.freeze(Maps)",
				"",
			}, "\n"),
		},
		{
			path = "src/shared/config/Waves.luau",
			expected = table.concat({
				"--!strict",
				"",
				"local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)",
				"",
				"-- Authored wave schedules are intentionally empty until a content packet.",
				"local Waves: { ConfigTypes.WaveScheduleDefinition } = {}",
				"",
				"return table.freeze(Waves)",
				"",
			}, "\n"),
		},
		{
			path = "src/shared/config/Towers.luau",
			expected = table.concat({
				"--!strict",
				"",
				"local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)",
				"",
				"local Towers: { ConfigTypes.TowerDefinition } = {}",
				"",
				"return table.freeze(Towers)",
				"",
			}, "\n"),
		},
		{
			path = "src/shared/config/Banners.luau",
			expected = table.concat({
				"--!strict",
				"",
				"local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)",
				"",
				"-- Authored banners are intentionally empty until a content and balance packet.",
				"local Banners: { ConfigTypes.BannerDefinition } = {}",
				"",
				"return table.freeze(Banners)",
				"",
			}, "\n"),
		},
		{
			path = "src/shared/config/Economy.luau",
			expected = table.concat({
				"--!strict",
				"",
				"local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)",
				"",
				"-- Only approved structural policy is authored here. Difficulty-specific values",
				"-- remain empty until a later content and balance packet defines real content.",
				"local difficultyRules: { ConfigTypes.DifficultyEconomyDefinition } = {}",
				"local sellRefund: ConfigTypes.SellRefundConfiguration = {",
				"\tbasisPoints = 7_000,",
				'\trounding = "Floor",',
				"}",
				"",
				"local Economy: ConfigTypes.AuthoredEconomyConfiguration = {",
				"\tversion = 1,",
				"\tsellRefund = table.freeze(sellRefund),",
				"\tdifficultyRules = table.freeze(difficultyRules),",
				"}",
				"",
				"return table.freeze(Economy)",
				"",
			}, "\n"),
		},
	}
	for _, definition in exactEmptyConfigs do
		if not fs.isFile(definition.path) then
			return false
		end
		local readSucceeded, source = pcall(fs.readFile, definition.path)
		if not readSucceeded or normalizeNewlines(source :: string) ~= definition.expected then
			return false
		end
	end

	for _, forbiddenDirectory in
		{
			"src/server/match/towers",
			"src/client/match/towers",
		}
	do
		if fs.isDir(forbiddenDirectory) then
			return false
		end
	end

	for _, definition in EXPECTED_MATCH_ENEMY_SERVER_SOURCES do
		local readSucceeded, source = pcall(fs.readFile, definition.sourcePath)
		if not readSucceeded then
			return false
		end
		local lowered = string.lower(source :: string)
		for _, forbidden in
			{
				"pathfindingservice",
				"rbxassetid://",
			}
		do
			if string.find(lowered, forbidden, 1, true) ~= nil then
				return false
			end
		end
	end
	for _, definition in EXPECTED_MATCH_ENEMY_CLIENT_SOURCES do
		local readSucceeded, source = pcall(fs.readFile, definition.sourcePath)
		if not readSucceeded or string.find(string.lower(source :: string), "rbxassetid://", 1, true) ~= nil then
			return false
		end
	end
	for _, forbiddenOutput in
		{
			"build.rbxlx",
			"build/default.rbxlx",
			"build/lobby.rbxlx",
			"build/match.rbxlx",
			"build/test.rbxlx",
		}
	do
		if fs.isFile(forbiddenOutput) then
			return false
		end
	end
	return true
end

local function safeLogPath(path: string): string
	if #path > 512 or string.match(path, "^[A-Za-z0-9_.:-]+$") == nil then
		return "<unsafe>"
	end
	return path
end

local function emit(kind: string, buildName: string, code: string, path: string?)
	local pathField = if path == nil then "" else `[path={safeLogPath(path)}]`
	print(`[ATD_BUILD_CHECK][{kind}][build={buildName}][code={code}]{pathField}`)
end

local function cleanup(): boolean
	local succeeded = true
	for _, definition in BUILDS do
		if ownedOutputs[definition.output] and fs.isFile(definition.output) then
			if not pcall(fs.removeFile, definition.output) then
				succeeded = false
			end
		end
	end

	if createdBuildDirectory and fs.isDir(BUILD_DIRECTORY) then
		local readSucceeded, entries = pcall(fs.readDir, BUILD_DIRECTORY)
		if readSucceeded and #(entries :: { string }) == 0 then
			if not pcall(fs.removeDir, BUILD_DIRECTORY) then
				succeeded = false
			end
		elseif not readSucceeded then
			succeeded = false
		end
	end

	return succeeded
end

local function collectDescendants(root: Instance): { Instance }
	local descendants: { Instance } = {}
	local function visit(parent: Instance)
		for _, child in parent:GetChildren() do
			table.insert(descendants, child)
			visit(child)
		end
	end
	visit(root)
	return descendants
end

local function countClasses(dataModel: DataModel): (number, number, number)
	local moduleCount = 0
	local scriptCount = 0
	local localScriptCount = 0
	currentStage = "count_get_descendants"
	local descendants = dataModel:GetDescendants()
	currentStage = "count_iterate_descendants"
	for index, descendant in descendants do
		currentStage = `count_descendant_{index}`
		local className = descendant.ClassName
		if className == "ModuleScript" then
			moduleCount += 1
		elseif className == "Script" then
			scriptCount += 1
		elseif className == "LocalScript" then
			localScriptCount += 1
		end
	end
	return moduleCount, scriptCount, localScriptCount
end

local function hasTestLeak(dataModel: DataModel): boolean
	for _, descendant in dataModel:GetDescendants() do
		local path = descendant:GetFullName()
		if
			string.find(path, "AutomatedTests", 1, true) ~= nil
			or string.find(path, "NegativeControls", 1, true) ~= nil
			or string.sub(descendant.Name, -5) == ".spec"
		then
			return true
		end
		if
			descendant.ClassName == "ModuleScript"
			or descendant.ClassName == "Script"
			or descendant.ClassName == "LocalScript"
		then
			local source = (descendant :: LuaSourceContainer).Source
			if
				string.find(source, "ATD_TEST", 1, true) ~= nil
				or string.find(source, "ATD_PHASE06_STUDIO", 1, true) ~= nil
				or string.find(source, "ATD_PHASE07_STUDIO", 1, true) ~= nil
				or string.find(source, "ATD_PHASE07_AUTHORING", 1, true) ~= nil
				or string.find(source, "ATD_PHASE09_STUDIO", 1, true) ~= nil
				or string.find(source, "PRIVATE_MODULE_LOAD_VALUE", 1, true) ~= nil
			then
				return true
			end
		end
	end
	return false
end

local function isLuaSourceContainer(instance: Instance): boolean
	return instance.ClassName == "ModuleScript" or instance.ClassName == "Script" or instance.ClassName == "LocalScript"
end

local function expectedProductionSources(role: "Default" | "Lobby" | "Match"): { SourceDefinition }
	local expected: { SourceDefinition } = {}
	for _, source in EXPECTED_PRODUCTION_SOURCES do
		if role == "Match" and source.dataModelPath == "ServerScriptService.Server.common.bootstrap.Main" then
			table.insert(expected, {
				dataModelPath = source.dataModelPath,
				className = source.className,
				sourcePath = "src/server/match/bootstrap/Main.server.luau",
			})
		elseif
			role == "Match"
			and source.dataModelPath == "StarterPlayer.StarterPlayerScripts.Client.common.bootstrap.Main"
		then
			table.insert(expected, {
				dataModelPath = source.dataModelPath,
				className = source.className,
				sourcePath = "src/client/match/bootstrap/Main.client.luau",
			})
		else
			table.insert(expected, source)
		end
	end
	if role ~= "Lobby" then
		for _, source in EXPECTED_MATCH_SERVER_SOURCES do
			table.insert(expected, source)
		end
		for _, source in EXPECTED_MATCH_BASE_SERVER_SOURCES do
			table.insert(expected, source)
		end
		for _, source in EXPECTED_MATCH_ENEMY_SERVER_SOURCES do
			table.insert(expected, source)
		end
		for _, source in EXPECTED_MATCH_WAVE_SERVER_SOURCES do
			table.insert(expected, source)
		end
		for _, source in EXPECTED_MATCH_LIFECYCLE_SOURCES do
			table.insert(expected, source)
		end
		for _, source in EXPECTED_MATCH_ROSTER_SOURCES do
			table.insert(expected, source)
		end
		for _, source in EXPECTED_MATCH_READY_SOURCES do
			table.insert(expected, source)
		end
		for _, source in EXPECTED_MATCH_CLIENT_SOURCES do
			table.insert(expected, source)
		end
		for _, source in EXPECTED_MATCH_BASE_CLIENT_SOURCES do
			table.insert(expected, source)
		end
		for _, source in EXPECTED_MATCH_ENEMY_CLIENT_SOURCES do
			table.insert(expected, source)
		end
		for _, source in EXPECTED_MATCH_WAVE_CLIENT_SOURCES do
			table.insert(expected, source)
		end
	end
	return expected
end

local function verifyProductionSources(dataModel: DataModel, definition: BuildDefinition): boolean
	local expectedSources = expectedProductionSources(definition.role :: "Default" | "Lobby" | "Match")
	local expectedByPath: { [string]: SourceDefinition } = {}
	for _, expected in expectedSources do
		if expectedByPath[expected.dataModelPath] ~= nil then
			emit("FAIL", definition.name, "EXPECTED_SOURCE_PATH_DUPLICATE", expected.dataModelPath)
			return false
		end
		expectedByPath[expected.dataModelPath] = expected
	end

	local actualSources: { LuaSourceContainer } = {}
	for _, descendant in dataModel:GetDescendants() do
		if isLuaSourceContainer(descendant) then
			table.insert(actualSources, descendant :: LuaSourceContainer)
		end
	end
	table.sort(actualSources, function(left, right)
		local leftPath = left:GetFullName()
		local rightPath = right:GetFullName()
		if leftPath ~= rightPath then
			return leftPath < rightPath
		end
		if left.ClassName ~= right.ClassName then
			return left.ClassName < right.ClassName
		end
		return left.Source < right.Source
	end)

	local actualByPath: { [string]: LuaSourceContainer } = {}
	local actualPaths: { string } = {}
	local previousPath: string? = nil
	for _, actual in actualSources do
		local path = actual:GetFullName()
		if path == previousPath then
			emit("FAIL", definition.name, "PRODUCTION_SOURCE_PATH_DUPLICATE", path)
			return false
		end
		previousPath = path
		actualByPath[path] = actual
		table.insert(actualPaths, path)
	end

	if #actualPaths ~= #expectedSources then
		emit("FAIL", definition.name, `PRODUCTION_SOURCE_COUNT_{#actualPaths}`)
		return false
	end
	for _, path in actualPaths do
		if expectedByPath[path] == nil then
			emit("FAIL", definition.name, "PRODUCTION_SOURCE_UNEXPECTED", path)
			return false
		end
	end

	for _, expected in expectedSources do
		local actual = actualByPath[expected.dataModelPath]
		if actual == nil then
			emit("FAIL", definition.name, "PRODUCTION_SOURCE_MISSING", expected.dataModelPath)
			return false
		end
		if actual.ClassName ~= expected.className then
			emit("FAIL", definition.name, "PRODUCTION_SOURCE_CLASS_MISMATCH", expected.dataModelPath)
			return false
		end
		if not fs.isFile(expected.sourcePath) then
			emit("FAIL", definition.name, "AUTHORITATIVE_SOURCE_MISSING", expected.dataModelPath)
			return false
		end
		local readSucceeded, expectedSource = pcall(fs.readFile, expected.sourcePath)
		if not readSucceeded then
			emit("FAIL", definition.name, "AUTHORITATIVE_SOURCE_READ_FAILED", expected.dataModelPath)
			return false
		end
		if actual.Source ~= expectedSource then
			emit("FAIL", definition.name, "PRODUCTION_SOURCE_CONTENT_MISMATCH", expected.dataModelPath)
			return false
		end
	end

	return true
end

local function hasChild(parent: Instance?, name: string): boolean
	return parent ~= nil and parent:FindFirstChild(name) ~= nil
end

local function verifyRoleLayers(dataModel: DataModel, role: "Default" | "Lobby" | "Match"): boolean
	local serverContainer = dataModel:GetService("ServerScriptService"):FindFirstChild("Server")
	local starterPlayerScripts = dataModel:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local clientContainer = if starterPlayerScripts == nil then nil else starterPlayerScripts:FindFirstChild("Client")
	if serverContainer == nil or clientContainer == nil then
		return false
	end

	local expectedLobby = role ~= "Match"
	local expectedMatch = role ~= "Lobby"
	return hasChild(serverContainer, "common")
		and hasChild(clientContainer, "common")
		and hasChild(serverContainer, "lobby") == expectedLobby
		and hasChild(clientContainer, "lobby") == expectedLobby
		and hasChild(serverContainer, "match") == expectedMatch
		and hasChild(clientContainer, "match") == expectedMatch
end

local function hasAncestor(instance: Instance, ancestor: Instance): boolean
	local current = instance.Parent
	while current ~= nil do
		if current == ancestor then
			return true
		end
		current = current.Parent
	end
	return false
end

local function verifyTestOwnedSources(
	dataModel: DataModel,
	definition: BuildDefinition,
	excludedProductionContainers: { Instance }
): boolean
	local expectedByPath: { [string]: SourceDefinition } = {}
	for _, expected in EXPECTED_TEST_OWNED_SOURCES do
		if expectedByPath[expected.dataModelPath] ~= nil then
			emit("FAIL", definition.name, "EXPECTED_TEST_SOURCE_PATH_DUPLICATE", expected.dataModelPath)
			return false
		end
		expectedByPath[expected.dataModelPath] = expected
	end

	local actualSources: { ModuleScript } = {}
	for _, descendant in dataModel:GetDescendants() do
		local belongsToProductionContainer = false
		for _, container in excludedProductionContainers do
			if hasAncestor(descendant, container) then
				belongsToProductionContainer = true
				break
			end
		end
		if descendant.ClassName == "ModuleScript" and not belongsToProductionContainer then
			table.insert(actualSources, descendant :: ModuleScript)
		end
	end
	table.sort(actualSources, function(left, right)
		local leftPath = left:GetFullName()
		local rightPath = right:GetFullName()
		if leftPath ~= rightPath then
			return leftPath < rightPath
		end
		return left.Source < right.Source
	end)

	if #actualSources ~= #EXPECTED_TEST_OWNED_SOURCES then
		emit("FAIL", definition.name, `TEST_OWNED_SOURCE_COUNT_{#actualSources}`)
		return false
	end

	local actualByPath: { [string]: ModuleScript } = {}
	local previousPath: string? = nil
	for _, actual in actualSources do
		local path = actual:GetFullName()
		if path == previousPath then
			emit("FAIL", definition.name, "TEST_OWNED_SOURCE_PATH_DUPLICATE", path)
			return false
		end
		previousPath = path
		if expectedByPath[path] == nil then
			emit("FAIL", definition.name, "TEST_OWNED_SOURCE_UNEXPECTED", path)
			return false
		end
		actualByPath[path] = actual
	end

	for _, expected in EXPECTED_TEST_OWNED_SOURCES do
		local actual = actualByPath[expected.dataModelPath]
		if actual == nil then
			emit("FAIL", definition.name, "TEST_OWNED_SOURCE_MISSING", expected.dataModelPath)
			return false
		end
		if actual.ClassName ~= expected.className then
			emit("FAIL", definition.name, "TEST_OWNED_SOURCE_CLASS_MISMATCH", expected.dataModelPath)
			return false
		end
		if not fs.isFile(expected.sourcePath) then
			emit("FAIL", definition.name, "TEST_OWNED_AUTHORITATIVE_SOURCE_MISSING", expected.dataModelPath)
			return false
		end
		local readSucceeded, expectedSource = pcall(fs.readFile, expected.sourcePath)
		if not readSucceeded or actual.Source ~= expectedSource then
			emit("FAIL", definition.name, "TEST_OWNED_SOURCE_CONTENT_MISMATCH", expected.dataModelPath)
			return false
		end
	end

	return true
end

local function verifyMirroredSources(
	definition: BuildDefinition,
	container: Instance?,
	expectedSources: { SourceDefinition },
	codePrefix: string
): boolean
	if container == nil or container.ClassName ~= "Folder" then
		emit("FAIL", definition.name, `{codePrefix}_CONTAINER_MISSING`)
		return false
	end

	local descendants = collectDescendants(container)
	if #descendants ~= #expectedSources then
		emit("FAIL", definition.name, `{codePrefix}_SOURCE_COUNT`)
		return false
	end

	for _, expectedSourceDefinition in expectedSources do
		local moduleName = string.match(expectedSourceDefinition.dataModelPath, "([^.]+)$")
		local module = if moduleName == nil then nil else container:FindFirstChild(moduleName)
		if module == nil or module.ClassName ~= "ModuleScript" then
			emit("FAIL", definition.name, `{codePrefix}_SOURCE_MISMATCH`, container:GetFullName())
			return false
		end
		if not fs.isFile(expectedSourceDefinition.sourcePath) then
			emit("FAIL", definition.name, `{codePrefix}_AUTHORITATIVE_SOURCE_MISSING`, module:GetFullName())
			return false
		end

		local readSucceeded, expectedSource = pcall(fs.readFile, expectedSourceDefinition.sourcePath)
		if not readSucceeded or (module :: ModuleScript).Source ~= expectedSource then
			emit("FAIL", definition.name, `{codePrefix}_SOURCE_CONTENT_MISMATCH`, module:GetFullName())
			return false
		end
	end

	return true
end

local function verifyProduction(dataModel: DataModel, definition: BuildDefinition): boolean
	currentStage = `verify_counts_{definition.name}`
	local modules, scripts, localScripts = countClasses(dataModel)
	local expectedModules = if definition.role == "Lobby" then 46 else 77
	if modules ~= expectedModules or scripts ~= 1 or localScripts ~= 1 then
		emit("FAIL", definition.name, `PRODUCTION_CLASS_COUNTS_{modules}_{scripts}_{localScripts}`)
		return false
	end
	currentStage = `verify_sources_{definition.name}`
	if not verifyProductionSources(dataModel, definition) then
		return false
	end
	currentStage = `verify_leaks_{definition.name}`
	if hasTestLeak(dataModel) then
		emit("FAIL", definition.name, "TEST_CONTENT_LEAK")
		return false
	end
	currentStage = `verify_layers_{definition.name}`
	if not verifyRoleLayers(dataModel, definition.role :: "Default" | "Lobby" | "Match") then
		emit("FAIL", definition.name, "ROLE_LAYER_ISOLATION")
		return false
	end

	emit("PASS", definition.name, `MODULES_{modules}_SCRIPTS_{scripts}_LOCALSCRIPTS_{localScripts}`)
	return true
end

local function verifyTest(dataModel: DataModel, definition: BuildDefinition): boolean
	local modules, scripts, localScripts = countClasses(dataModel)
	if modules ~= 144 then
		emit("FAIL", definition.name, `TEST_MODULE_COUNT_{modules}`)
		return false
	end
	if scripts ~= 0 or localScripts ~= 0 then
		emit("FAIL", definition.name, "RUNNABLE_SCRIPT_PRESENT")
		return false
	end

	local replicatedStorage = dataModel:GetService("ReplicatedStorage")
	local shared = replicatedStorage:FindFirstChild("Shared")
	local sharedModules = 0
	if shared ~= nil then
		for _, descendant in collectDescendants(shared) do
			if descendant.ClassName == "ModuleScript" then
				sharedModules += 1
			end
		end
	end
	if sharedModules ~= 37 then
		emit("FAIL", definition.name, "SHARED_MODULE_COUNT")
		return false
	end

	local serverStorage = dataModel:GetService("ServerStorage")
	local automatedTests = serverStorage:FindFirstChild("AutomatedTests")
	local productionServerNetworking = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionServerNetworking")
	local productionClientNetworking = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionClientNetworking")
	local productionClientMatch = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionClientMatch")
	local productionClientEnemies = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionClientEnemies")
	local productionClientBase = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionClientBase")
	local productionClientWaves = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionClientWaves")
	local productionServerEnemies = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionServerEnemies")
	local productionServerBase = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionServerBase")
	local productionServerWaves = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionServerWaves")
	local productionServerMaps = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionServerMaps")
	local productionServerMatchLifecycle = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionServerMatchLifecycle")
	local productionServerMatchRoster = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionServerMatchRoster")
	local productionServerMatchReady = if automatedTests == nil
		then nil
		else automatedTests:FindFirstChild("ProductionServerMatchReady")
	local starterPlayerScripts = dataModel:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	if
		automatedTests == nil
		or serverStorage:FindFirstChild("NegativeControls") == nil
		or dataModel:GetService("ServerScriptService"):FindFirstChild("Server") ~= nil
		or (starterPlayerScripts ~= nil and starterPlayerScripts:FindFirstChild("Client") ~= nil)
	then
		emit("FAIL", definition.name, "TEST_BOUNDARY_STRUCTURE")
		return false
	end

	local expectedNetworkingContainers = {
		{
			container = productionServerNetworking,
			sources = {
				{
					moduleName = "ProductionRateLimits",
					sourcePath = "src/server/common/networking/ProductionRateLimits.luau",
				},
				{
					moduleName = "ServerRemoteRegistry",
					sourcePath = "src/server/common/networking/ServerRemoteRegistry.luau",
				},
				{
					moduleName = "ServerRateLimiter",
					sourcePath = "src/server/common/networking/ServerRateLimiter.luau",
				},
				{
					moduleName = "ServerRequestDispatcher",
					sourcePath = "src/server/common/networking/ServerRequestDispatcher.luau",
				},
			},
		},
		{
			container = productionClientNetworking,
			sources = {
				{
					moduleName = "ClientRemoteLookup",
					sourcePath = "src/client/common/networking/ClientRemoteLookup.luau",
				},
				{
					moduleName = "ClientRequestTracker",
					sourcePath = "src/client/common/networking/ClientRequestTracker.luau",
				},
			},
		},
	}
	for _, expectedContainer in expectedNetworkingContainers do
		local container = expectedContainer.container
		if container == nil or container.ClassName ~= "Folder" then
			emit("FAIL", definition.name, "TEST_NETWORKING_CONTAINER_MISSING")
			return false
		end

		local descendants = collectDescendants(container)
		if #descendants ~= #expectedContainer.sources then
			emit("FAIL", definition.name, "TEST_NETWORKING_SOURCE_COUNT")
			return false
		end

		for _, expectedSourceDefinition in expectedContainer.sources do
			local module = container:FindFirstChild(expectedSourceDefinition.moduleName)
			if module == nil or module.ClassName ~= "ModuleScript" then
				emit("FAIL", definition.name, "TEST_NETWORKING_SOURCE_MISMATCH", container:GetFullName())
				return false
			end

			if not fs.isFile(expectedSourceDefinition.sourcePath) then
				emit("FAIL", definition.name, "TEST_NETWORKING_AUTHORITATIVE_SOURCE_MISSING", module:GetFullName())
				return false
			end

			local readSucceeded, expectedSource = pcall(fs.readFile, expectedSourceDefinition.sourcePath)
			if not readSucceeded or (module :: ModuleScript).Source ~= expectedSource then
				emit("FAIL", definition.name, "TEST_NETWORKING_SOURCE_CONTENT_MISMATCH", module:GetFullName())
				return false
			end
		end
	end
	local networkingModules = 6
	if not verifyMirroredSources(definition, productionServerMaps, EXPECTED_MATCH_SERVER_SOURCES, "TEST_MAP") then
		return false
	end
	if
		not verifyMirroredSources(
			definition,
			productionServerBase,
			EXPECTED_MATCH_BASE_SERVER_SOURCES,
			"TEST_SERVER_BASE"
		)
	then
		return false
	end
	if
		not verifyMirroredSources(
			definition,
			productionServerEnemies,
			EXPECTED_MATCH_ENEMY_SERVER_SOURCES,
			"TEST_SERVER_ENEMY"
		)
	then
		return false
	end
	if
		not verifyMirroredSources(
			definition,
			productionServerWaves,
			EXPECTED_MATCH_WAVE_SERVER_SOURCES,
			"TEST_SERVER_WAVE"
		)
	then
		return false
	end
	if
		not verifyMirroredSources(
			definition,
			productionServerMatchLifecycle,
			EXPECTED_MATCH_LIFECYCLE_SOURCES,
			"TEST_MATCH_LIFECYCLE"
		)
	then
		return false
	end
	if
		not verifyMirroredSources(
			definition,
			productionServerMatchRoster,
			EXPECTED_MATCH_ROSTER_SOURCES,
			"TEST_MATCH_ROSTER"
		)
	then
		return false
	end
	if
		not verifyMirroredSources(
			definition,
			productionServerMatchReady,
			EXPECTED_MATCH_READY_SOURCES,
			"TEST_MATCH_READY"
		)
	then
		return false
	end
	if
		not verifyMirroredSources(definition, productionClientMatch, EXPECTED_MATCH_CLIENT_SOURCES, "TEST_CLIENT_MATCH")
	then
		return false
	end
	if
		not verifyMirroredSources(
			definition,
			productionClientBase,
			EXPECTED_MATCH_BASE_CLIENT_SOURCES,
			"TEST_CLIENT_BASE"
		)
	then
		return false
	end
	if
		not verifyMirroredSources(
			definition,
			productionClientEnemies,
			EXPECTED_MATCH_ENEMY_CLIENT_SOURCES,
			"TEST_CLIENT_ENEMY"
		)
	then
		return false
	end
	if
		not verifyMirroredSources(
			definition,
			productionClientWaves,
			EXPECTED_MATCH_WAVE_CLIENT_SOURCES,
			"TEST_CLIENT_WAVE"
		)
	then
		return false
	end
	local mapModules = #EXPECTED_MATCH_SERVER_SOURCES
	local serverBaseModules = #EXPECTED_MATCH_BASE_SERVER_SOURCES
	local serverEnemyModules = #EXPECTED_MATCH_ENEMY_SERVER_SOURCES
	local serverWaveModules = #EXPECTED_MATCH_WAVE_SERVER_SOURCES
	local matchLifecycleModules = #EXPECTED_MATCH_LIFECYCLE_SOURCES
	local matchRosterModules = #EXPECTED_MATCH_ROSTER_SOURCES
	local matchReadyModules = #EXPECTED_MATCH_READY_SOURCES
	local clientMatchModules = #EXPECTED_MATCH_CLIENT_SOURCES
	local clientBaseModules = #EXPECTED_MATCH_BASE_CLIENT_SOURCES
	local clientEnemyModules = #EXPECTED_MATCH_ENEMY_CLIENT_SOURCES
	local clientWaveModules = #EXPECTED_MATCH_WAVE_CLIENT_SOURCES
	if
		not verifyTestOwnedSources(dataModel, definition, {
			shared :: Instance,
			productionServerNetworking :: Instance,
			productionClientNetworking :: Instance,
			productionClientMatch :: Instance,
			productionClientBase :: Instance,
			productionClientEnemies :: Instance,
			productionClientWaves :: Instance,
			productionServerBase :: Instance,
			productionServerEnemies :: Instance,
			productionServerWaves :: Instance,
			productionServerMaps :: Instance,
			productionServerMatchLifecycle :: Instance,
			productionServerMatchRoster :: Instance,
			productionServerMatchReady :: Instance,
		})
	then
		return false
	end
	local testOwnedModules = #EXPECTED_TEST_OWNED_SOURCES

	emit(
		"PASS",
		definition.name,
		`MODULES_{modules}_SHARED_{sharedModules}_NETWORKING_{networkingModules}_MAPS_{mapModules}_SERVER_BASE_{serverBaseModules}_SERVER_ENEMIES_{serverEnemyModules}_SERVER_WAVES_{serverWaveModules}_MATCH_LIFECYCLE_{matchLifecycleModules}_MATCH_ROSTER_{matchRosterModules}_MATCH_READY_{matchReadyModules}_CLIENT_MATCH_{clientMatchModules}_CLIENT_BASE_{clientBaseModules}_CLIENT_ENEMIES_{clientEnemyModules}_CLIENT_WAVES_{clientWaveModules}_TEST_OWNED_{testOwnedModules}_RUNNABLE_SCRIPTS_0`
	)
	return true
end

local function run(): boolean
	currentStage = "phase11_scope"
	if not verifyPhase11Scope() then
		emit("FAIL", "All", "PHASE11_SCOPE_BOUNDARY")
		return false
	end
	currentStage = "build_directory"
	if fs.isFile(BUILD_DIRECTORY) then
		emit("FAIL", "All", "BUILD_PATH_NOT_DIRECTORY")
		return false
	end
	if not fs.isDir(BUILD_DIRECTORY) then
		if not pcall(fs.writeDir, BUILD_DIRECTORY) then
			emit("FAIL", "All", "BUILD_DIRECTORY_CREATE_FAILED")
			return false
		end
		createdBuildDirectory = true
	end

	for _, definition in BUILDS do
		currentStage = `build_{definition.name}`
		if fs.isFile(definition.output) then
			emit("FAIL", definition.name, "OUTPUT_ALREADY_EXISTS")
			return false
		end
		ownedOutputs[definition.output] = true
		local executed, result = pcall(process.exec, "rojo", {
			"build",
			definition.project,
			"--output",
			definition.output,
		})
		if not executed or not (result :: any).ok or not fs.isFile(definition.output) then
			emit("FAIL", definition.name, "BUILD_FAILED")
			return false
		end

		local readSucceeded, contents = pcall(fs.readFile, definition.output)
		if not readSucceeded then
			emit("FAIL", definition.name, "READ_FAILED")
			return false
		end
		currentStage = `deserialize_{definition.name}`
		local parsed, dataModel = pcall(roblox.deserializePlace, contents)
		if not parsed then
			emit("FAIL", definition.name, "DESERIALIZE_FAILED")
			return false
		end

		currentStage = `verify_{definition.name}`
		local verified = if definition.role == "Test"
			then verifyTest(dataModel :: DataModel, definition)
			else verifyProduction(dataModel :: DataModel, definition)
		if not verified then
			return false
		end
	end

	return true
end

local completed, verified = xpcall(run, function()
	return false
end)
local cleaned = cleanup()
if not completed then
	emit("FAIL", "All", `VERIFIER_CRASH_{currentStage}`)
end
if not cleaned then
	emit("FAIL", "All", "OUTPUT_CLEANUP_FAILED")
end

if completed and verified and cleaned then
	process.exit(0)
else
	process.exit(1)
end
