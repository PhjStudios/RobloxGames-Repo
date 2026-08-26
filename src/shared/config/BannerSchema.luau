--!strict

local SchemaPrimitives = require(script.Parent.SchemaPrimitives)
local TowerSchema = require(script.Parent.TowerSchema)
local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local Ids = require(script.Parent.Parent.util.Ids)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

local ROOT_PATH: { Validation.PathSegment } = { "Banners" }

local BANNER_FIELDS: { [string]: boolean } = table.freeze({
	displayName = true,
	id = true,
	outcomes = true,
	pityRule = true,
	pullOptions = true,
	version = true,
})

local BANNER_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	currentPityCount = true,
	isAvailable = true,
	player = true,
	rng = true,
	rollState = true,
	selectedOutcome = true,
	transactionId = true,
})

local PULL_OPTIONS_FIELDS: { [string]: boolean } = table.freeze({
	onePull = true,
	tenPull = true,
})

local PULL_OPTION_FIELDS: { [string]: boolean } = table.freeze({
	goldCost = true,
})

local PULL_OPTION_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	deducted = true,
	purchasedAt = true,
})

local OUTCOME_FIELDS: { [string]: boolean } = table.freeze({
	probabilityPercent = true,
	towerId = true,
})

local OUTCOME_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	rolled = true,
	unitId = true,
})

local PITY_RULE_FIELDS: { [string]: boolean } = table.freeze({
	guaranteedTowerId = true,
	hardPityPullCount = true,
	kind = true,
})

local PITY_RULE_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({
	currentPullCount = true,
	hasTriggered = true,
	player = true,
})

local NO_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({})

local PROBABILITY_TOTAL_PERCENT = 100
local PROBABILITY_TOTAL_TOLERANCE_PERCENT = 1e-9
local MIN_PROBABILITY_PERCENT = PROBABILITY_TOTAL_TOLERANCE_PERCENT
local MAX_BANNER_OUTCOMES = 1_000
local MAX_PITY_PULL_COUNT = 1_000_000

local validatedCatalogs: { [ConfigTypes.BannerCatalog]: boolean } = setmetatable({}, {
	__mode = "k",
}) :: any

local BannerSchema = {
	PROBABILITY_TOTAL_PERCENT = PROBABILITY_TOTAL_PERCENT,
	PROBABILITY_TOTAL_TOLERANCE_PERCENT = PROBABILITY_TOTAL_TOLERANCE_PERCENT,
	MIN_PROBABILITY_PERCENT = MIN_PROBABILITY_PERCENT,
	MAX_BANNER_OUTCOMES = MAX_BANNER_OUTCOMES,
	MAX_PITY_PULL_COUNT = MAX_PITY_PULL_COUNT,
}

local function validatePullOption(
	value: unknown,
	path: { Validation.PathSegment }
): (ConfigTypes.BannerPullOptionDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, PULL_OPTION_FIELDS, PULL_OPTION_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local goldCost, goldCostIssue = SchemaPrimitives.positiveInteger(record :: Validation.RawObject, "goldCost", path)
	if goldCostIssue ~= nil then
		return nil, goldCostIssue
	end

	return table.freeze({
		goldCost = goldCost :: number,
	}), nil
end

local function validatePullOptions(
	value: unknown,
	path: { Validation.PathSegment }
): (ConfigTypes.BannerPullOptionsDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, PULL_OPTIONS_FIELDS, NO_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawOnePull, onePullMissing = Validation.getRequiredField(record :: Validation.RawObject, "onePull", path)
	if onePullMissing ~= nil then
		return nil, onePullMissing
	end
	local onePull, onePullIssue = validatePullOption(rawOnePull, Validation.appendPath(path, "onePull"))
	if onePullIssue ~= nil then
		return nil, onePullIssue
	end

	local rawTenPull, tenPullMissing = Validation.getRequiredField(record :: Validation.RawObject, "tenPull", path)
	if tenPullMissing ~= nil then
		return nil, tenPullMissing
	end
	local tenPull, tenPullIssue = validatePullOption(rawTenPull, Validation.appendPath(path, "tenPull"))
	if tenPullIssue ~= nil then
		return nil, tenPullIssue
	end

	return table.freeze({
		onePull = onePull :: ConfigTypes.BannerPullOptionDefinition,
		tenPull = tenPull :: ConfigTypes.BannerPullOptionDefinition,
	}),
		nil
end

local function validateOutcomes(
	value: unknown,
	path: { Validation.PathSegment },
	towers: ConfigTypes.TowerCatalog
): (
	{ ConfigTypes.BannerOutcomeDefinition }?,
	{ [Ids.TowerId]: boolean }?,
	Validation.Issue?
)
	local rawOutcomes, arrayIssue = Validation.readArray(value, path, MAX_BANNER_OUTCOMES)
	if arrayIssue ~= nil then
		return nil, nil, arrayIssue
	end
	if #(rawOutcomes :: { unknown }) == 0 then
		return nil, nil, Validation.issue("EMPTY_COLLECTION", path, "Banner must define at least one outcome")
	end

	local outcomes: { ConfigTypes.BannerOutcomeDefinition } = {}
	local outcomeIds: { [Ids.TowerId]: boolean } = {}
	local firstIdPaths: { [string]: string } = {}
	local probabilityTotal = 0
	local probabilityCompensation = 0
	local towerById = rawget(towers :: any, "byId")

	for index = 1, #(rawOutcomes :: { unknown }) do
		local outcomePath = Validation.appendPath(path, index)
		local record, recordIssue = Validation.readObject(
			(rawOutcomes :: { unknown })[index],
			outcomePath,
			OUTCOME_FIELDS,
			OUTCOME_RUNTIME_FIELDS
		)
		if recordIssue ~= nil then
			return nil, nil, recordIssue
		end

		local rawTowerId, towerIdMissing =
			Validation.getRequiredField(record :: Validation.RawObject, "towerId", outcomePath)
		if towerIdMissing ~= nil then
			return nil, nil, towerIdMissing
		end
		local towerIdPath = Validation.appendPath(outcomePath, "towerId")
		local towerIdResult = Ids.validateTowerId(rawTowerId)
		if not towerIdResult.ok then
			return nil,
				nil,
				Validation.issueWithCause(
					"INVALID_ID",
					towerIdPath,
					"Banner outcome tower ID is invalid",
					towerIdResult.error.code
				)
		end
		local towerId = towerIdResult.value

		local firstPath = firstIdPaths[towerId]
		if firstPath ~= nil then
			return nil,
				nil,
				Validation.issueWithRelated(
					"DUPLICATE_VALUE",
					towerIdPath,
					"Banner outcome duplicates an earlier tower reference",
					firstPath
				)
		end
		firstIdPaths[towerId] = Validation.renderPath(towerIdPath)

		if rawget(towerById, towerId) == nil then
			return nil,
				nil,
				Validation.issue("INVALID_REFERENCE", towerIdPath, "Banner outcome references an unknown tower")
		end

		local probabilityPercent, probabilityIssue = SchemaPrimitives.boundedNumber(
			record :: Validation.RawObject,
			"probabilityPercent",
			outcomePath,
			MIN_PROBABILITY_PERCENT,
			PROBABILITY_TOTAL_PERCENT
		)
		if probabilityIssue ~= nil then
			return nil, nil, probabilityIssue
		end

		local adjustedProbability = (probabilityPercent :: number) - probabilityCompensation
		local nextTotal = probabilityTotal + adjustedProbability
		probabilityCompensation = (nextTotal - probabilityTotal) - adjustedProbability
		probabilityTotal = nextTotal

		local outcome: ConfigTypes.BannerOutcomeDefinition = table.freeze({
			towerId = towerId,
			probabilityPercent = probabilityPercent :: number,
		})
		table.insert(outcomes, outcome)
		outcomeIds[towerId] = true
	end

	if math.abs(probabilityTotal - PROBABILITY_TOTAL_PERCENT) > PROBABILITY_TOTAL_TOLERANCE_PERCENT then
		return nil,
			nil,
			Validation.issue(
				"INVALID_TOTAL",
				path,
				"Banner outcome probabilities must total 100 percent within the configured tolerance"
			)
	end

	return table.freeze(outcomes), outcomeIds, nil
end

local function validatePityRule(
	value: unknown,
	path: { Validation.PathSegment },
	towers: ConfigTypes.TowerCatalog,
	outcomeIds: { [Ids.TowerId]: boolean }
): (ConfigTypes.BannerPityRuleDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, PITY_RULE_FIELDS, PITY_RULE_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawKind, kindMissing = Validation.getRequiredField(record :: Validation.RawObject, "kind", path)
	if kindMissing ~= nil then
		return nil, kindMissing
	end
	local kindPath = Validation.appendPath(path, "kind")
	if type(rawKind) ~= "string" then
		return nil, Validation.issueWithType("INVALID_TYPE", kindPath, "Pity-rule kind must be a string", rawKind)
	end
	if rawKind ~= "GuaranteedTower" then
		return nil, Validation.issue("INVALID_ENUM", kindPath, "Pity-rule kind is not recognized")
	end

	local hardPityPullCount, pullCountIssue = SchemaPrimitives.boundedInteger(
		record :: Validation.RawObject,
		"hardPityPullCount",
		path,
		1,
		MAX_PITY_PULL_COUNT
	)
	if pullCountIssue ~= nil then
		return nil, pullCountIssue
	end

	local rawGuaranteedTowerId, guaranteedTowerIdMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "guaranteedTowerId", path)
	if guaranteedTowerIdMissing ~= nil then
		return nil, guaranteedTowerIdMissing
	end
	local guaranteedTowerIdPath = Validation.appendPath(path, "guaranteedTowerId")
	local guaranteedTowerIdResult = Ids.validateTowerId(rawGuaranteedTowerId)
	if not guaranteedTowerIdResult.ok then
		return nil,
			Validation.issueWithCause(
				"INVALID_ID",
				guaranteedTowerIdPath,
				"Pity target tower ID is invalid",
				guaranteedTowerIdResult.error.code
			)
	end
	local guaranteedTowerId = guaranteedTowerIdResult.value

	local towerById = rawget(towers :: any, "byId")
	if rawget(towerById, guaranteedTowerId) == nil then
		return nil,
			Validation.issue("INVALID_REFERENCE", guaranteedTowerIdPath, "Pity target references an unknown tower")
	end
	if outcomeIds[guaranteedTowerId] ~= true then
		return nil,
			Validation.issue("INVALID_REFERENCE", guaranteedTowerIdPath, "Pity target is not an outcome of this banner")
	end

	return table.freeze({
		kind = "GuaranteedTower",
		hardPityPullCount = hardPityPullCount :: number,
		guaranteedTowerId = guaranteedTowerId,
	}),
		nil
end

local function validateDefinitionAt(
	value: unknown,
	path: { Validation.PathSegment },
	towers: ConfigTypes.TowerCatalog,
	firstIdPaths: { [string]: string }?
): (ConfigTypes.BannerDefinition?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, BANNER_FIELDS, BANNER_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawId, idMissing = Validation.getRequiredField(record :: Validation.RawObject, "id", path)
	if idMissing ~= nil then
		return nil, idMissing
	end
	local idPath = Validation.appendPath(path, "id")
	local idResult = Ids.validateBannerId(rawId)
	if not idResult.ok then
		return nil, Validation.issueWithCause("INVALID_ID", idPath, "Banner ID is invalid", idResult.error.code)
	end
	local id = idResult.value
	if firstIdPaths ~= nil then
		local firstPath = firstIdPaths[id]
		if firstPath ~= nil then
			return nil,
				Validation.issueWithRelated(
					"DUPLICATE_ID",
					idPath,
					"Banner ID duplicates an earlier catalog entry",
					firstPath
				)
		end
		firstIdPaths[id] = Validation.renderPath(idPath)
	end

	local version, versionIssue = SchemaPrimitives.positiveInteger(record :: Validation.RawObject, "version", path)
	if versionIssue ~= nil then
		return nil, versionIssue
	end

	local displayName, displayNameIssue = SchemaPrimitives.requiredText(
		record :: Validation.RawObject,
		"displayName",
		path,
		Validation.MAX_NAME_CHARACTERS
	)
	if displayNameIssue ~= nil then
		return nil, displayNameIssue
	end

	local rawPullOptions, pullOptionsMissing =
		Validation.getRequiredField(record :: Validation.RawObject, "pullOptions", path)
	if pullOptionsMissing ~= nil then
		return nil, pullOptionsMissing
	end
	local pullOptions, pullOptionsIssue =
		validatePullOptions(rawPullOptions, Validation.appendPath(path, "pullOptions"))
	if pullOptionsIssue ~= nil then
		return nil, pullOptionsIssue
	end

	local rawOutcomes, outcomesMissing = Validation.getRequiredField(record :: Validation.RawObject, "outcomes", path)
	if outcomesMissing ~= nil then
		return nil, outcomesMissing
	end
	local outcomes, outcomeIds, outcomesIssue =
		validateOutcomes(rawOutcomes, Validation.appendPath(path, "outcomes"), towers)
	if outcomesIssue ~= nil then
		return nil, outcomesIssue
	end

	local pityRule: ConfigTypes.BannerPityRuleDefinition? = nil
	local rawPityRule = Validation.getField(record :: Validation.RawObject, "pityRule")
	if rawPityRule ~= nil then
		local pityRuleIssue: Validation.Issue?
		pityRule, pityRuleIssue = validatePityRule(
			rawPityRule,
			Validation.appendPath(path, "pityRule"),
			towers,
			outcomeIds :: { [Ids.TowerId]: boolean }
		)
		if pityRuleIssue ~= nil then
			return nil, pityRuleIssue
		end
	end

	local definition: ConfigTypes.BannerDefinition = table.freeze({
		id = id,
		version = version :: ConfigTypes.ConfigurationVersion,
		displayName = displayName :: string,
		pullOptions = pullOptions :: ConfigTypes.BannerPullOptionsDefinition,
		outcomes = outcomes :: { ConfigTypes.BannerOutcomeDefinition },
		pityRule = pityRule,
	})
	return definition, nil
end

local function invalidTowerCatalogResult(): Result.Failure<Validation.Issue>
	return Result.err(
		Validation.issue("INVALID_REFERENCE", { "TowerCatalog" }, "Expected a tower catalog validated by TowerSchema")
	)
end

function BannerSchema.validateDefinition(
	value: unknown,
	towers: ConfigTypes.TowerCatalog
): Result.Result<ConfigTypes.BannerDefinition, Validation.Issue>
	if not TowerSchema.isValidatedCatalog(towers) then
		return invalidTowerCatalogResult()
	end

	local definition, issue = validateDefinitionAt(value, { "Banner" }, towers, nil)
	if issue ~= nil then
		return Result.err(issue)
	end
	return Result.ok(definition :: ConfigTypes.BannerDefinition)
end

function BannerSchema.validateCatalog(
	value: unknown,
	towers: ConfigTypes.TowerCatalog
): Result.Result<ConfigTypes.BannerCatalog, Validation.Issue>
	if not TowerSchema.isValidatedCatalog(towers) then
		return invalidTowerCatalogResult()
	end

	local rawDefinitions, arrayIssue = Validation.readArray(value, ROOT_PATH, Validation.MAX_CATALOG_ENTRIES)
	if arrayIssue ~= nil then
		return Result.err(arrayIssue)
	end

	local ordered: { ConfigTypes.BannerDefinition } = {}
	local byId: { [Ids.BannerId]: ConfigTypes.BannerDefinition } = {}
	local firstIdPaths: { [string]: string } = {}
	for index = 1, #(rawDefinitions :: { unknown }) do
		local definition, issue = validateDefinitionAt(
			(rawDefinitions :: { unknown })[index],
			Validation.appendPath(ROOT_PATH, index),
			towers,
			firstIdPaths
		)
		if issue ~= nil then
			return Result.err(issue)
		end

		local canonicalDefinition = definition :: ConfigTypes.BannerDefinition
		table.insert(ordered, canonicalDefinition)
		byId[canonicalDefinition.id] = canonicalDefinition
	end

	local catalog: ConfigTypes.BannerCatalog = table.freeze({
		ordered = table.freeze(ordered),
		byId = table.freeze(byId),
	})
	validatedCatalogs[catalog] = true
	return Result.ok(catalog)
end

function BannerSchema.isValidatedCatalog(value: unknown): boolean
	return type(value) == "table" and validatedCatalogs[value :: any] == true
end

return table.freeze(BannerSchema)
