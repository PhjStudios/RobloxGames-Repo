--!strict

-- Fresh, authenticated Phase 10 fixtures. This module is test-only and is not
-- mapped into any production project.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AssetSchema = require(Shared.config.AssetSchema)
local DifficultySchema = require(Shared.config.DifficultySchema)
local ConfigTypes = require(Shared.types.ConfigTypes)
local Result = require(Shared.util.Result)

local ConfigurationFixtures = require(script.Parent.ConfigurationFixtures)
local EnemyFixtures = require(script.Parent.EnemyFixtures)

local BaseFixtures = {}

BaseFixtures.MATCH_ID = "match:phase10-base-runtime"
BaseFixtures.OTHER_MATCH_ID = "match:phase10-other-runtime"
BaseFixtures.ENEMY_EPOCH = 7
BaseFixtures.DIFFICULTY_ID = "difficulty:normal"

export type DifficultyFixture = {
	catalog: ConfigTypes.DifficultyCatalog,
	definition: ConfigTypes.DifficultyDefinition,
	rawSources: { [string]: any },
}

export type LifecycleControl = {
	state: string,
	revision: number,
	matchId: string,
	mapSnapshot: unknown,
	snapshotAvailable: boolean,
	mapAvailable: boolean,
	onGetSnapshot: (() -> ())?,
	onGetRuntimeMapSnapshot: (() -> ())?,
}

function BaseFixtures.createDifficultyFixture(maximumHealth: number?): DifficultyFixture
	local rawSources = ConfigurationFixtures.validSources()
	rawSources.difficulties[1].base.maxHealth = maximumHealth or 100
	local manifestResult = AssetSchema.validateManifest(rawSources.assets)
	if not manifestResult.ok then
		error("Phase 10 fixture asset manifest failed validation", 0)
	end
	local difficultyResult = DifficultySchema.validateCatalog(rawSources.difficulties, manifestResult.value)
	if not difficultyResult.ok then
		error("Phase 10 fixture difficulty catalog failed validation", 0)
	end
	local catalog = difficultyResult.value
	local definition = catalog.byId[BaseFixtures.DIFFICULTY_ID]
	if definition == nil then
		error("Phase 10 fixture difficulty definition is missing", 0)
	end
	return table.freeze({
		catalog = catalog,
		definition = definition,
		rawSources = rawSources,
	})
end

function BaseFixtures.createLifecycle(initialState: string?, matchId: string?): ({ [string]: any }, LifecycleControl)
	local control: LifecycleControl = {
		state = initialState or "ReadyCheck",
		revision = 1,
		matchId = matchId or BaseFixtures.MATCH_ID,
		mapSnapshot = EnemyFixtures.createRuntimeMapSnapshot(),
		snapshotAvailable = true,
		mapAvailable = true,
		onGetSnapshot = nil,
		onGetRuntimeMapSnapshot = nil,
	}
	local lifecycle = {}

	function lifecycle.getSnapshot(_self: unknown): unknown
		if control.onGetSnapshot ~= nil then
			control.onGetSnapshot()
		end
		if not control.snapshotAvailable then
			return Result.err(table.freeze({ code = "UNAVAILABLE" }))
		end
		return Result.ok(table.freeze({
			matchId = control.matchId,
			revision = control.revision,
			state = control.state,
			participants = table.freeze({}),
		}))
	end

	function lifecycle.getRuntimeMapSnapshot(_self: unknown): unknown
		if control.onGetRuntimeMapSnapshot ~= nil then
			control.onGetRuntimeMapSnapshot()
		end
		if not control.mapAvailable then
			return Result.err(table.freeze({ code = "UNAVAILABLE" }))
		end
		return Result.ok(control.mapSnapshot)
	end

	return lifecycle, control
end

return table.freeze(BaseFixtures)
