--!strict

-- Fresh, detached Phase 09 fixtures. Authored enemy data is authenticated by
-- the production schemas, while route snapshots contain only immutable Roblox
-- value types and frozen tables. Nothing here is mapped into production.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AssetSchema = require(Shared.config.AssetSchema)
local EnemySchema = require(Shared.config.EnemySchema)
local ConfigTypes = require(Shared.types.ConfigTypes)
local Ids = require(Shared.util.Ids)

local EnemyFixtures = {}

export type RawRecord = { [string]: any }

export type AuthenticatedCatalogFixture = {
	rawAssets: { RawRecord },
	rawEnemies: { RawRecord },
	manifest: ConfigTypes.AssetManifest,
	catalog: ConfigTypes.EnemyCatalog,
}

export type RoutePointKind = "EnemySpawn" | "PathNode" | "DefenderBase"

export type RoutePointSnapshot = {
	kind: RoutePointKind,
	nodeOrder: number?,
	cframe: CFrame,
	position: Vector3,
	distance: number,
}

export type RuntimeLaneSnapshot = {
	id: string,
	totalDistance: number,
	points: { RoutePointSnapshot },
}

export type PointSnapshot = {
	cframe: CFrame,
	position: Vector3,
}

export type RegionSnapshot = {
	id: string,
	cframe: CFrame,
	size: Vector3,
}

export type NamedPointSnapshot = {
	id: string,
	cframe: CFrame,
	position: Vector3,
}

export type RuntimeMapSnapshot = {
	mapId: Ids.MapId,
	base: PointSnapshot,
	bounds: {
		cframe: CFrame,
		size: Vector3,
	},
	lanes: { RuntimeLaneSnapshot },
	placementZones: { RegionSnapshot },
	noPlacementZones: { RegionSnapshot },
	cameraAnchors: { NamedPointSnapshot },
	playerSpawns: { NamedPointSnapshot },
}

EnemyFixtures.NORMAL_ENEMY_ID = "enemy:phase09-normal"
EnemyFixtures.FAST_ENEMY_ID = "enemy:phase09-fast"
EnemyFixtures.SLOW_ENEMY_ID = "enemy:phase09-slow"
EnemyFixtures.MAP_ID = "map:phase09-synthetic"
EnemyFixtures.BENT_LANE_ID = "alpha-bent"
EnemyFixtures.STRAIGHT_LANE_ID = "beta-straight"
EnemyFixtures.BENT_LANE_TOTAL_DISTANCE = 40
EnemyFixtures.STRAIGHT_LANE_TOTAL_DISTANCE = 20

local PLACEHOLDER_MODEL_KEY = "test.phase09.enemy-model"
local BASE_POSITION = Vector3.new(20, 5, 20)

function EnemyFixtures.rawAssets(): { RawRecord }
	return {
		{
			key = PLACEHOLDER_MODEL_KEY,
			kind = "EnemyModel",
		},
	}
end

function EnemyFixtures.rawEnemies(): { RawRecord }
	return {
		{
			id = EnemyFixtures.NORMAL_ENEMY_ID,
			displayName = "Phase 09 Normal Fixture",
			modelAssetKey = PLACEHOLDER_MODEL_KEY,
			maxHealth = 100,
			moveSpeedStudsPerSecond = 10,
			leakDamage = 0,
			damageIncomeClass = "None",
		},
		{
			id = EnemyFixtures.FAST_ENEMY_ID,
			displayName = "Phase 09 Fast Fixture",
			modelAssetKey = PLACEHOLDER_MODEL_KEY,
			maxHealth = 50,
			moveSpeedStudsPerSecond = 20,
			leakDamage = 0,
			damageIncomeClass = "None",
		},
		{
			id = EnemyFixtures.SLOW_ENEMY_ID,
			displayName = "Phase 09 Slow Fixture",
			modelAssetKey = PLACEHOLDER_MODEL_KEY,
			maxHealth = 150,
			moveSpeedStudsPerSecond = 5,
			leakDamage = 0,
			damageIncomeClass = "None",
		},
	}
end

function EnemyFixtures.authenticateCatalog(
	rawAssets: { RawRecord },
	rawEnemies: { RawRecord }
): AuthenticatedCatalogFixture
	local manifestResult = AssetSchema.validateManifest(rawAssets)
	if not manifestResult.ok then
		error("Phase 09 fixture asset manifest failed production validation", 0)
	end
	local manifest = manifestResult.value :: ConfigTypes.AssetManifest
	if not AssetSchema.isValidatedManifest(manifest) then
		error("Phase 09 fixture asset manifest was not authenticated", 0)
	end

	local catalogResult = EnemySchema.validateCatalog(rawEnemies, manifest)
	if not catalogResult.ok then
		error("Phase 09 fixture enemy catalog failed production validation", 0)
	end
	local catalog = catalogResult.value :: ConfigTypes.EnemyCatalog
	if not EnemySchema.isValidatedCatalog(catalog) then
		error("Phase 09 fixture enemy catalog was not authenticated", 0)
	end

	return table.freeze({
		rawAssets = rawAssets,
		rawEnemies = rawEnemies,
		manifest = manifest,
		catalog = catalog,
	})
end

function EnemyFixtures.createAuthenticatedCatalogFixture(): AuthenticatedCatalogFixture
	return EnemyFixtures.authenticateCatalog(EnemyFixtures.rawAssets(), EnemyFixtures.rawEnemies())
end

function EnemyFixtures.createAuthenticatedCatalog(): ConfigTypes.EnemyCatalog
	return EnemyFixtures.createAuthenticatedCatalogFixture().catalog
end

local function routePoint(
	kind: RoutePointKind,
	nodeOrder: number?,
	position: Vector3,
	distance: number
): RoutePointSnapshot
	return table.freeze({
		kind = kind,
		nodeOrder = nodeOrder,
		cframe = CFrame.new(position),
		position = position,
		distance = distance,
	})
end

function EnemyFixtures.createBentLane(): RuntimeLaneSnapshot
	local points: { RoutePointSnapshot } = {
		routePoint("EnemySpawn", nil, Vector3.new(0, 5, 0), 0),
		routePoint("PathNode", 1, Vector3.new(10, 5, 0), 10),
		routePoint("PathNode", 2, Vector3.new(10, 5, 20), 30),
		routePoint("DefenderBase", nil, BASE_POSITION, EnemyFixtures.BENT_LANE_TOTAL_DISTANCE),
	}
	return table.freeze({
		id = EnemyFixtures.BENT_LANE_ID,
		totalDistance = EnemyFixtures.BENT_LANE_TOTAL_DISTANCE,
		points = table.freeze(points),
	})
end

function EnemyFixtures.createStraightLane(): RuntimeLaneSnapshot
	local points: { RoutePointSnapshot } = {
		routePoint("EnemySpawn", nil, Vector3.new(0, 5, 20), 0),
		routePoint("PathNode", 1, Vector3.new(10, 5, 20), 10),
		routePoint("DefenderBase", nil, BASE_POSITION, EnemyFixtures.STRAIGHT_LANE_TOTAL_DISTANCE),
	}
	return table.freeze({
		id = EnemyFixtures.STRAIGHT_LANE_ID,
		totalDistance = EnemyFixtures.STRAIGHT_LANE_TOTAL_DISTANCE,
		points = table.freeze(points),
	})
end

local function pointSnapshot(position: Vector3): PointSnapshot
	return table.freeze({
		cframe = CFrame.new(position),
		position = position,
	})
end

local function regionSnapshot(id: string, cframe: CFrame, size: Vector3): RegionSnapshot
	return table.freeze({
		id = id,
		cframe = cframe,
		size = size,
	})
end

local function namedPointSnapshot(id: string, position: Vector3): NamedPointSnapshot
	return table.freeze({
		id = id,
		cframe = CFrame.new(position),
		position = position,
	})
end

function EnemyFixtures.createRuntimeMapSnapshot(): RuntimeMapSnapshot
	local mapIdResult = Ids.validateMapId(EnemyFixtures.MAP_ID)
	if not mapIdResult.ok then
		error("Phase 09 fixture MapId failed production validation", 0)
	end

	return table.freeze({
		mapId = mapIdResult.value,
		base = pointSnapshot(BASE_POSITION),
		bounds = table.freeze({
			cframe = CFrame.new(10, 5, 10),
			size = Vector3.new(60, 20, 60),
		}),
		lanes = table.freeze({
			EnemyFixtures.createBentLane(),
			EnemyFixtures.createStraightLane(),
		}),
		placementZones = table.freeze({
			regionSnapshot("fixture-land", CFrame.new(10, 0, 10), Vector3.new(50, 2, 50)),
		}),
		noPlacementZones = table.freeze({
			regionSnapshot("fixture-route", CFrame.new(10, 0, 10), Vector3.new(4, 1, 40)),
		}),
		cameraAnchors = table.freeze({
			namedPointSnapshot("fixture-overview", Vector3.new(10, 30, 35)),
		}),
		playerSpawns = table.freeze({
			namedPointSnapshot("fixture-player", Vector3.new(25, 5, 25)),
		}),
	})
end

return table.freeze(EnemyFixtures)
