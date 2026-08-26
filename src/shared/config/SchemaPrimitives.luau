--!strict

local ConfigTypes = require(script.Parent.Parent.types.ConfigTypes)
local AssetSchema = require(script.Parent.AssetSchema)
local Validation = require(script.Parent.Parent.util.Validation)

local FEATURE_FIELDS: { [string]: boolean } = table.freeze({
	key = true,
	kind = true,
})

local NO_RUNTIME_FIELDS: { [string]: boolean } = table.freeze({})

local FEATURE_KINDS: { [string]: boolean } = table.freeze({
	AttackBehavior = true,
	EnemyBehavior = true,
	EndlessWaveGenerator = true,
	MergeProgression = true,
	ResistanceProfile = true,
	StatusEffect = true,
})

local SchemaPrimitives = {}

function SchemaPrimitives.requiredText(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment },
	maximumCharacters: number
): (string?, Validation.Issue?)
	local value, missingIssue = Validation.getRequiredField(record, fieldName, path)
	if missingIssue ~= nil then
		return nil, missingIssue
	end

	local fieldPath = Validation.appendPath(path, fieldName)
	if type(value) ~= "string" then
		return nil, Validation.issueWithType("INVALID_TYPE", fieldPath, "Expected a string", value)
	end
	if not Validation.isDisplayText(value, maximumCharacters) then
		return nil, Validation.issue("INVALID_STRING", fieldPath, "String is blank, malformed, or outside its limit")
	end

	return value, nil
end

function SchemaPrimitives.optionalText(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment },
	maximumCharacters: number
): (string?, Validation.Issue?)
	local value = Validation.getField(record, fieldName)
	if value == nil then
		return nil, nil
	end

	local fieldPath = Validation.appendPath(path, fieldName)
	if type(value) ~= "string" then
		return nil, Validation.issueWithType("INVALID_TYPE", fieldPath, "Expected a string", value)
	end
	if not Validation.isDisplayText(value, maximumCharacters) then
		return nil, Validation.issue("INVALID_STRING", fieldPath, "String is blank, malformed, or outside its limit")
	end

	return value, nil
end

local function requiredNumber(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment }
): (number?, Validation.Issue?)
	local value, missingIssue = Validation.getRequiredField(record, fieldName, path)
	if missingIssue ~= nil then
		return nil, missingIssue
	end

	local fieldPath = Validation.appendPath(path, fieldName)
	if type(value) ~= "number" then
		return nil, Validation.issueWithType("INVALID_TYPE", fieldPath, "Expected a number", value)
	end
	if not Validation.isFiniteNumber(value) then
		return nil, Validation.issue("NON_FINITE_NUMBER", fieldPath, "Number must be finite")
	end

	-- Reconstruct all accepted zero values with one canonical representation.
	return if value == 0 then 0 else value, nil
end

function SchemaPrimitives.requiredBoolean(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment }
): (boolean?, Validation.Issue?)
	local value, missingIssue = Validation.getRequiredField(record, fieldName, path)
	if missingIssue ~= nil then
		return nil, missingIssue
	end

	local fieldPath = Validation.appendPath(path, fieldName)
	if type(value) ~= "boolean" then
		return nil, Validation.issueWithType("INVALID_TYPE", fieldPath, "Expected a boolean", value)
	end

	return value, nil
end

function SchemaPrimitives.nonNegativeNumber(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment }
): (number?, Validation.Issue?)
	local value, issue = requiredNumber(record, fieldName, path)
	if issue ~= nil then
		return nil, issue
	end
	if (value :: number) < 0 then
		return nil,
			Validation.issue(
				"OUT_OF_RANGE",
				Validation.appendPath(path, fieldName),
				"Number must be greater than or equal to zero"
			)
	end
	return value, nil
end

function SchemaPrimitives.positiveNumber(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment }
): (number?, Validation.Issue?)
	local value, issue = requiredNumber(record, fieldName, path)
	if issue ~= nil then
		return nil, issue
	end
	if (value :: number) <= 0 then
		return nil,
			Validation.issue("OUT_OF_RANGE", Validation.appendPath(path, fieldName), "Number must be greater than zero")
	end
	return value, nil
end

function SchemaPrimitives.nonNegativeInteger(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment }
): (number?, Validation.Issue?)
	local value, issue = requiredNumber(record, fieldName, path)
	if issue ~= nil then
		return nil, issue
	end
	if not Validation.isSafeInteger(value :: number) then
		return nil,
			Validation.issue(
				"NOT_INTEGER",
				Validation.appendPath(path, fieldName),
				"Number must be an exact safe integer"
			)
	end
	if (value :: number) < 0 then
		return nil,
			Validation.issue(
				"OUT_OF_RANGE",
				Validation.appendPath(path, fieldName),
				"Integer must be greater than or equal to zero"
			)
	end
	return value, nil
end

function SchemaPrimitives.positiveInteger(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment }
): (number?, Validation.Issue?)
	local value, issue = SchemaPrimitives.nonNegativeInteger(record, fieldName, path)
	if issue ~= nil then
		return nil, issue
	end
	if (value :: number) < 1 then
		return nil,
			Validation.issue("OUT_OF_RANGE", Validation.appendPath(path, fieldName), "Integer must be at least one")
	end
	return value, nil
end

function SchemaPrimitives.supportedVersion(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment },
	expectedVersion: number
): (ConfigTypes.ConfigurationVersion?, Validation.Issue?)
	local value, issue = SchemaPrimitives.positiveInteger(record, fieldName, path)
	if issue ~= nil then
		return nil, issue
	end
	if value ~= expectedVersion then
		return nil,
			Validation.issue(
				"UNSUPPORTED_VERSION",
				Validation.appendPath(path, fieldName),
				"Configuration version is not supported by this reader"
			)
	end

	return value, nil
end

function SchemaPrimitives.boundedNumber(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment },
	minimum: number,
	maximum: number
): (number?, Validation.Issue?)
	local value, issue = requiredNumber(record, fieldName, path)
	if issue ~= nil then
		return nil, issue
	end
	if (value :: number) < minimum or (value :: number) > maximum then
		return nil,
			Validation.issue(
				"OUT_OF_RANGE",
				Validation.appendPath(path, fieldName),
				"Number is outside its technical range"
			)
	end
	return value, nil
end

function SchemaPrimitives.boundedInteger(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment },
	minimum: number,
	maximum: number
): (number?, Validation.Issue?)
	local value, issue = SchemaPrimitives.nonNegativeInteger(record, fieldName, path)
	if issue ~= nil then
		return nil, issue
	end
	if (value :: number) < minimum or (value :: number) > maximum then
		return nil,
			Validation.issue(
				"OUT_OF_RANGE",
				Validation.appendPath(path, fieldName),
				"Integer is outside its technical range"
			)
	end
	return value, nil
end

function SchemaPrimitives.requiredSymbolicKey(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment }
): (ConfigTypes.FeatureKey?, Validation.Issue?)
	local value, issue = Validation.getRequiredField(record, fieldName, path)
	if issue ~= nil then
		return nil, issue
	end
	local fieldPath = Validation.appendPath(path, fieldName)
	if type(value) ~= "string" then
		return nil, Validation.issueWithType("INVALID_TYPE", fieldPath, "Symbolic key must be a string", value)
	end
	if not Validation.isSymbolicKey(value) then
		return nil, Validation.issue("INVALID_REFERENCE", fieldPath, "Symbolic key is not canonical")
	end
	return value, nil
end

function SchemaPrimitives.assetKey(
	record: Validation.RawObject,
	fieldName: string,
	path: { Validation.PathSegment },
	manifest: ConfigTypes.AssetManifest,
	expectedKind: ConfigTypes.AssetKind,
	required: boolean
): (ConfigTypes.AssetKey?, Validation.Issue?)
	local fieldPath = Validation.appendPath(path, fieldName)
	if not AssetSchema.isValidatedManifest(manifest) then
		return nil,
			Validation.issue(
				"INVALID_REFERENCE",
				fieldPath,
				"Asset lookup requires a manifest validated by AssetSchema"
			)
	end

	local value = Validation.getField(record, fieldName)
	if value == nil then
		if required then
			return nil,
				Validation.issue(
					"MISSING_FIELD",
					Validation.appendPath(path, fieldName),
					"Definition is missing a required field"
				)
		end
		return nil, nil
	end

	if type(value) ~= "string" then
		return nil, Validation.issueWithType("INVALID_TYPE", fieldPath, "Asset key must be a string", value)
	end
	if not Validation.isSymbolicKey(value) then
		return nil,
			Validation.issue("INVALID_ASSET_KEY", fieldPath, "Asset key does not use the canonical symbolic grammar")
	end

	local byKey = rawget(manifest :: any, "byKey")
	local asset = rawget(byKey, value) :: ConfigTypes.AssetDefinition?
	if asset == nil then
		return nil, Validation.issue("UNKNOWN_ASSET_KEY", fieldPath, "Asset key is not declared in the manifest")
	end
	if rawget(asset :: any, "kind") ~= expectedKind then
		return nil, Validation.issue("WRONG_ASSET_KIND", fieldPath, "Asset key has the wrong declared kind")
	end

	return value, nil
end

function SchemaPrimitives.featureReference(
	value: unknown,
	path: { Validation.PathSegment },
	expectedKind: ConfigTypes.FeatureKind
): (ConfigTypes.FeatureReference?, Validation.Issue?)
	local record, recordIssue = Validation.readObject(value, path, FEATURE_FIELDS, NO_RUNTIME_FIELDS)
	if recordIssue ~= nil then
		return nil, recordIssue
	end

	local rawKind, kindIssue = Validation.getRequiredField(record :: Validation.RawObject, "kind", path)
	if kindIssue ~= nil then
		return nil, kindIssue
	end
	local kindPath = Validation.appendPath(path, "kind")
	if type(rawKind) ~= "string" then
		return nil, Validation.issueWithType("INVALID_TYPE", kindPath, "Feature kind must be a string", rawKind)
	end
	if FEATURE_KINDS[rawKind] ~= true then
		return nil, Validation.issue("INVALID_ENUM", kindPath, "Feature kind is not recognized")
	end
	if rawKind ~= expectedKind then
		return nil, Validation.issue("INVALID_REFERENCE", kindPath, "Feature reference has the wrong kind")
	end

	local rawKey, keyIssue = Validation.getRequiredField(record :: Validation.RawObject, "key", path)
	if keyIssue ~= nil then
		return nil, keyIssue
	end
	local keyPath = Validation.appendPath(path, "key")
	if type(rawKey) ~= "string" then
		return nil, Validation.issueWithType("INVALID_TYPE", keyPath, "Feature key must be a string", rawKey)
	end
	if not Validation.isSymbolicKey(rawKey) then
		return nil, Validation.issue("INVALID_REFERENCE", keyPath, "Feature key is not canonical")
	end

	local reference: ConfigTypes.FeatureReference = table.freeze({
		kind = expectedKind,
		key = rawKey,
	})
	return reference, nil
end

function SchemaPrimitives.featureReferenceList(
	value: unknown,
	path: { Validation.PathSegment },
	expectedKind: ConfigTypes.FeatureKind
): ({ ConfigTypes.FeatureReference }?, Validation.Issue?)
	local rawEntries, arrayIssue = Validation.readArray(value, path, Validation.MAX_LIST_ENTRIES)
	if arrayIssue ~= nil then
		return nil, arrayIssue
	end
	if #(rawEntries :: { unknown }) == 0 then
		return nil, Validation.issue("EMPTY_COLLECTION", path, "Optional reference list must be non-empty when present")
	end

	local references: { ConfigTypes.FeatureReference } = {}
	local firstPaths: { [string]: string } = {}
	for index = 1, #(rawEntries :: { unknown }) do
		local rawReference = (rawEntries :: { unknown })[index]
		local referencePath = Validation.appendPath(path, index)
		local reference, referenceIssue = SchemaPrimitives.featureReference(rawReference, referencePath, expectedKind)
		if referenceIssue ~= nil then
			return nil, referenceIssue
		end

		local key = (reference :: ConfigTypes.FeatureReference).key
		local keyPath = Validation.appendPath(referencePath, "key")
		local firstPath = firstPaths[key]
		if firstPath ~= nil then
			return nil,
				Validation.issueWithRelated(
					"DUPLICATE_VALUE",
					keyPath,
					"Reference duplicates an earlier list entry",
					firstPath
				)
		end
		firstPaths[key] = Validation.renderPath(keyPath)
		table.insert(references, reference :: ConfigTypes.FeatureReference)
	end

	return table.freeze(references), nil
end

function SchemaPrimitives.optionalTags(
	record: Validation.RawObject,
	path: { Validation.PathSegment }
): ({ ConfigTypes.FeatureKey }?, Validation.Issue?)
	local value = Validation.getField(record, "tags")
	if value == nil then
		return nil, nil
	end

	local tagsPath = Validation.appendPath(path, "tags")
	local rawTags, arrayIssue = Validation.readArray(value, tagsPath, Validation.MAX_LIST_ENTRIES)
	if arrayIssue ~= nil then
		return nil, arrayIssue
	end
	if #(rawTags :: { unknown }) == 0 then
		return nil, Validation.issue("EMPTY_COLLECTION", tagsPath, "Optional tag list must be non-empty when present")
	end

	local tags: { ConfigTypes.FeatureKey } = {}
	local firstPaths: { [string]: string } = {}
	for index = 1, #(rawTags :: { unknown }) do
		local rawTag = (rawTags :: { unknown })[index]
		local tagPath = Validation.appendPath(tagsPath, index)
		if type(rawTag) ~= "string" then
			return nil, Validation.issueWithType("INVALID_TYPE", tagPath, "Tag must be a string", rawTag)
		end
		if not Validation.isSymbolicKey(rawTag) then
			return nil, Validation.issue("INVALID_REFERENCE", tagPath, "Tag key is not canonical")
		end

		local firstPath = firstPaths[rawTag]
		if firstPath ~= nil then
			return nil,
				Validation.issueWithRelated(
					"DUPLICATE_VALUE",
					tagPath,
					"Tag duplicates an earlier list entry",
					firstPath
				)
		end
		firstPaths[rawTag] = Validation.renderPath(tagPath)
		table.insert(tags, rawTag)
	end

	return table.freeze(tags), nil
end

return table.freeze(SchemaPrimitives)
