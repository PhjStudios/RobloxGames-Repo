local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlaceRoles = require(ReplicatedStorage.Shared.config.PlaceRoles)

local configurationResult = PlaceRoles.validateConfiguration()
if not configurationResult.ok then
	error(
		`[ATD][ERROR][context=server][subsystem=place-role][event=configuration_rejected][code={configurationResult.code}] {configurationResult.message}`,
		0
	)
end

local roleResult =
	PlaceRoles.resolve(ReplicatedStorage:GetAttribute(PlaceRoles.ATTRIBUTE_NAME), game.PlaceId, RunService:IsStudio())

if not roleResult.ok then
	error(
		`[ATD][ERROR][context=server][subsystem=place-role][event=boot_rejected][code={roleResult.code}] {roleResult.message}`,
		0
	)
end

if RunService:IsStudio() then
	print(
		`[ATD][INFO][context=server][subsystem=bootstrap][event=ready][role={roleResult.role}][placeId={game.PlaceId}] Server bootstrap ready`
	)
end
