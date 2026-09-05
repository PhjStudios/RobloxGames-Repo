--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local messages = require("../src/shared/localization/Messages")

type Role = "Default" | "Lobby" | "Match" | "Test"

type BuildDefinition = {
	name: Role,
	project: string,
	output: string,
}

type SourceRecord = {
	className: string,
	source: string,
}

type ParsedArguments = {
	runTests: boolean,
	selectedProjects: { [Role]: boolean },
}

local BUILD_DIRECTORY = "build"
local ALL_BUILDS: { BuildDefinition } = {
	{ name = "Default", project = "default.project.json", output = "build/verify-default.rbxlx" },
	{ name = "Lobby", project = "lobby.project.json", output = "build/verify-lobby.rbxlx" },
	{ name = "Match", project = "match.project.json", output = "build/verify-match.rbxlx" },
	{ name = "Test", project = "test.project.json", output = "build/verify-test.rbxlx" },
}
local EXPECTED_PLACE_ROLES: { [Role]: string } = {
	Default = "Development",
	Lobby = "Lobby",
	Match = "Match",
	Test = "",
}
local REQUIRED_TEST_SUPPORT = table.freeze({
	RobloxAdapter = true,
	TestHarness = true,
	TestRunner = true,
})

local createdBuildDirectory = false
local ownedOutputs: { [string]: boolean } = {}
local currentStage = "startup"

local function emit(kind: string, buildName: string, code: string, path: string?)
	local output = `[ATD_BUILD][{kind}][build={buildName}][code={code}]`
	if path ~= nil then
		local safePath = if #path <= 512 and string.match(path, "^[A-Za-z0-9_./\\:-]+$") ~= nil
			then path
			else "<unsafe>"
		output ..= `[path={safePath}]`
	end
	print(output)
end

local function parseArguments(): ParsedArguments?
	local runTests = true
	local buildsOnlySeen = false
	local selectedProjects: { [Role]: boolean } = {}
	local hasProjectSelection = false
	local index = 1
	while index <= #process.args do
		local argument = process.args[index]
		if argument == "--builds-only" then
			if buildsOnlySeen then
				return nil
			end
			buildsOnlySeen = true
			runTests = false
			index += 1
		elseif argument == "--project" then
			local projectName = process.args[index + 1]
			if
				projectName ~= "Default"
				and projectName ~= "Lobby"
				and projectName ~= "Match"
				and projectName ~= "Test"
			then
				return nil
			end
			local role = projectName :: Role
			if selectedProjects[role] then
				return nil
			end
			selectedProjects[role] = true
			hasProjectSelection = true
			index += 2
		else
			return nil
		end
	end

	if runTests and hasProjectSelection then
		return nil
	end
	if not hasProjectSelection then
		for _, definition in ALL_BUILDS do
			selectedProjects[definition.name] = true
		end
	end

	return {
		runTests = runTests,
		selectedProjects = selectedProjects,
	}
end

local function cleanup(): boolean
	local cleaned = true
	for output in ownedOutputs do
		if fs.isFile(output) and not pcall(fs.removeFile, output) then
			cleaned = false
		end
	end
	if createdBuildDirectory and fs.isDir(BUILD_DIRECTORY) then
		local readSucceeded, entries = pcall(fs.readDir, BUILD_DIRECTORY)
		if readSucceeded and #(entries :: { string }) == 0 then
			if not pcall(fs.removeDir, BUILD_DIRECTORY) then
				cleaned = false
			end
		elseif not readSucceeded then
			cleaned = false
		end
	end
	return cleaned
end

local function normalizeNewlines(value: string): string
	return string.gsub(value, "\r\n", "\n")
end

local function normalizePath(value: string): string
	return string.gsub(value, "\\", "/")
end

local function countPlainOccurrences(value: string, needle: string): number
	local count = 0
	local cursor = 1
	while true do
		local _, occurrenceEnd = string.find(value, needle, cursor, true)
		if occurrenceEnd == nil then
			return count
		end
		count += 1
		cursor = occurrenceEnd + 1
	end
end

local function readSource(path: string): string?
	if not fs.isFile(path) then
		return nil
	end
	local succeeded, value = pcall(fs.readFile, path)
	if not succeeded or type(value) ~= "string" then
		return nil
	end
	return normalizeNewlines(value :: string)
end

type LocalizationToken = { kind: string, value: string, position: number }

-- A bounded lexical guard, not a Luau type checker. It checks literal arguments
-- and simple conditional fallbacks, not aliases, computed keys, interpolated
-- expressions, or whether arbitrary English source should be localized.
local function localizationTokens(source: string): { LocalizationToken }
	local tokens: { LocalizationToken } = {}
	local cursor = 1
	while cursor <= #source do
		if #tokens >= 250_000 then
			error("localization token limit", 0)
		end
		local char = string.sub(source, cursor, cursor)
		local comment = string.sub(source, cursor, cursor + 1) == "--"
		local opening = if comment then cursor + 2 else cursor
		local longEnd: number? = nil
		if string.sub(source, opening, opening) == "[" then
			local probe = opening + 1
			while string.sub(source, probe, probe) == "=" do
				probe += 1
			end
			if string.sub(source, probe, probe) == "[" then
				longEnd = probe
			end
		end
		if longEnd ~= nil then
			local closing = "]" .. string.sub(source, opening + 1, longEnd - 1) .. "]"
			local closeStart, closeEnd = string.find(source, closing, (longEnd :: number) + 1, true)
			if closeStart == nil then
				error("unterminated localization scan literal", 0)
			end
			if not comment then
				table.insert(tokens, {
					kind = "literal",
					value = string.sub(source, (longEnd :: number) + 1, closeStart - 1),
					position = cursor,
				})
			end
			cursor = (closeEnd :: number) + 1
		elseif comment then
			cursor = string.find(source, "\n", cursor + 2, true) or (#source + 1)
		elseif char == '"' or char == "'" or char == "`" then
			local first = cursor
			cursor += 1
			while cursor <= #source and string.sub(source, cursor, cursor) ~= char do
				cursor += if string.sub(source, cursor, cursor) == "\\" then 2 else 1
			end
			if cursor > #source then
				error("unterminated localization scan quote", 0)
			end
			table.insert(tokens, {
				kind = if char == "`" then "template" else "literal",
				value = string.sub(source, first + 1, cursor - 1),
				position = first,
			})
			cursor += 1
		elseif string.match(char, "%s") ~= nil then
			cursor += 1
		else
			if string.match(char, "[%a_]") ~= nil then
				local first, last = string.find(source, "[%a_][%w_]*", cursor)
				table.insert(
					tokens,
					{ kind = "identifier", value = string.sub(source, first, last), position = cursor }
				)
				cursor = (last :: number) + 1
			else
				local value = if string.sub(source, cursor, cursor + 1) == ".." then ".." else char
				table.insert(tokens, { kind = "punct", value = value, position = cursor })
				cursor += #value
			end
		end
	end
	return tokens
end

local function localizationReferences(source: string, lobbyFactories: boolean): { LocalizationToken }
	local tokens = localizationTokens(source)
	local references: { LocalizationToken } = {}
	for index, token in tokens do
		local open: number? = nil
		local argument: number? = nil
		local factory = false
		if
			token.kind == "identifier"
			and tokens[index + 1] ~= nil
			and tokens[index + 1].value == "."
			and tokens[index + 2] ~= nil
			and tokens[index + 3] ~= nil
			and tokens[index + 3].value == "("
		then
			local method = tokens[index + 2].value
			if token.value == "Localization" and (method == "text" or method == "format" or method == "bind") then
				open, argument = index + 3, if method == "bind" then 2 else 1
			elseif token.value == "WorldMessages" and method == "set" then
				open, argument = index + 3, 2
			end
		elseif
			lobbyFactories
			and token.kind == "identifier"
			and (token.value == "label" or token.value == "button" or token.value == "makeLabel" or token.value == "makeButton")
			and tokens[index + 1] ~= nil
			and tokens[index + 1].value == "("
		then
			open, argument, factory = index + 1, 3, true
		end
		if open == nil then
			continue
		end
		local depth, currentArgument, first = 1, 1, (open :: number) + 1
		for cursor = (open :: number) + 1, #tokens do
			local current = tokens[cursor]
			local value = current.value
			if current.kind == "punct" then
				if value == "(" or value == "[" or value == "{" then
					depth += 1
				elseif value == ")" or value == "]" or value == "}" then
					depth -= 1
				end
			end
			if depth == 0 or (depth == 1 and current.kind == "punct" and value == ",") then
				if currentArgument == argument then
					for candidateIndex = first, cursor - 1 do
						local candidate = tokens[candidateIndex]
						local before = tokens[candidateIndex - 1].value
						local after = tokens[candidateIndex + 1].value
						local simple = candidateIndex == first and candidateIndex == cursor - 1
						local fallback = before == "then" or before == "else" or before == "or" or before == "and"
						local keyShape = string.match(candidate.value, "^[a-z][a-z0-9_]*%.[a-z0-9_.]+$") ~= nil
						if
							candidate.kind == "literal"
							and (simple or fallback)
							and before ~= ".."
							and after ~= ".."
							and (not factory or keyShape)
						then
							table.insert(references, candidate)
						end
					end
					break
				end
				if depth == 0 then
					break
				end
				currentArgument += 1
				first = cursor + 1
			end
		end
	end
	return references
end

local function verifyLocalizationReferences(): boolean
	local fixture = [==[
-- Localization.text("missing.comment")
--[=[ Localization.bind(object, "missing.long_comment") ]=]
local ignored = 'Localization.format("missing.quoted")'
local template = `Localization.text("missing.template")`
Localization.text("common.you")
Localization.text([=[common.you]=])
Localization.format('common.you', { nested = { "missing.argument" } })
Localization.bind(find(object, { "missing.owner" }), "common.you")
Localization.text(if state == "Ready" then "common.you" else "common.unavailable")
Localization.text(key or "common.unavailable")
Localization.text("enum.navigation." .. suffix)
Localization.text(registry[key])
WorldMessages.set(object, "queue_world.title")
label("Heading", root, "common.you", 12)
button("Action", root, "Literal display text", 12)
]==]
	if #localizationReferences(fixture, true) ~= 9 or #localizationReferences(fixture, false) ~= 8 then
		emit("FAIL", "All", "LOCALIZATION_REFERENCE_SCANNER_FIXTURE_FAILED")
		return false
	end
	for _, source in
		{
			'Localization.text("missing.literal")',
			'Localization.bind(object, "missing.literal")',
			'label("Heading", root, "missing.literal")',
		}
	do
		local references = localizationReferences(source, true)
		if #references ~= 1 or messages.entries[references[1].value] ~= nil then
			emit("FAIL", "All", "LOCALIZATION_UNKNOWN_KEY_FIXTURE_FAILED")
			return false
		end
	end
	for _, registry in { messages.descriptions, messages.policies } do
		for _, key in registry do
			if messages.entries[key] == nil then
				emit("FAIL", "All", "LOCALIZATION_REGISTRY_KEY_UNKNOWN")
				return false
			end
		end
	end
	for _, registry in messages.enums do
		for _, key in registry do
			if messages.entries[key] == nil then
				emit("FAIL", "All", "LOCALIZATION_ENUM_KEY_UNKNOWN")
				return false
			end
		end
	end
	local pending = { "src" }
	local fileCount, sourceBytes, referenceCount = 0, 0, 0
	local directoryCount = 0
	while #pending > 0 do
		local directory = table.remove(pending) :: string
		directoryCount += 1
		local children = fs.readDir(directory)
		if directoryCount > 2_048 or #children > 4_096 then
			emit("FAIL", "All", "LOCALIZATION_DIRECTORY_BOUND_EXCEEDED", directory)
			return false
		end
		table.sort(children)
		for _, name in children do
			local path = directory .. "/" .. name
			if fs.isDir(path) then
				table.insert(pending, path)
			elseif string.sub(name, -5) == ".luau" then
				local source = readSource(path)
				fileCount += 1
				sourceBytes += if source == nil then 0 else #source
				if source == nil or #source > 1_000_000 or sourceBytes > 16_000_000 or fileCount > 2_048 then
					emit("FAIL", "All", "LOCALIZATION_SOURCE_BOUND_EXCEEDED", path)
					return false
				end
				for _, reference in localizationReferences(source, path == "src/client/lobby/ui/LobbyView.luau") do
					referenceCount += 1
					if messages.entries[reference.value] == nil then
						local _, lines = string.gsub(string.sub(source, 1, reference.position), "\n", "")
						emit("FAIL", "All", "LOCALIZATION_LITERAL_KEY_UNKNOWN", path .. ":" .. tostring(lines + 1))
						return false
					end
				end
			end
		end
	end
	if referenceCount < 100 then
		emit("FAIL", "All", "LOCALIZATION_REFERENCE_COVERAGE_MISSING")
		return false
	end
	print(
		`[ATD_BUILD][PASS][build=All][code=LOCALIZATION_LITERAL_REFERENCES_VALID][files={fileCount}][references={referenceCount}]`
	)
	return true
end

local function quotedField(record: string, fieldName: string): string?
	if countPlainOccurrences(record, `{fieldName} =`) ~= 1 then
		return nil
	end
	return string.match(record, fieldName .. '%s*=%s*"([A-Za-z][A-Za-z0-9_]*)"')
end

local function hasSafeProductionPlaceRoles(record: string): boolean
	if countPlainOccurrences(record, "placeRoles =") ~= 1 then
		return false
	end
	local body = string.match(record, "placeRoles%s*=%s*%{([^}]*)%}")
	if body == nil then
		return false
	end

	local foundRoles: { [string]: boolean } = {}
	local roleCount = 0
	for role in string.gmatch(body, '"([A-Za-z]+)"') do
		if (role ~= "Lobby" and role ~= "Match") or foundRoles[role] then
			return false
		end
		foundRoles[role] = true
		roleCount += 1
	end
	local remaining = string.gsub(body, '"[A-Za-z]+"', "")
	remaining = string.gsub(remaining, "[%s,]", "")
	return roleCount > 0 and remaining == ""
end

local function verifyNetworkSecurityBoundary(): boolean
	local remotesSource = readSource("src/shared/network/ProductionRemotes.luau")
	local ratesSource = readSource("src/server/common/networking/ProductionRateLimits.luau")
	if remotesSource == nil or ratesSource == nil then
		emit("FAIL", "All", "NETWORK_SOURCE_MISSING")
		return false
	end

	local remoteNames: { [string]: boolean } = {}
	local clientRequests: { [string]: boolean } = {}
	local remoteCount = 0
	for record in string.gmatch(remotesSource, "\n\t%{(.-)\n\t%},") do
		local name = quotedField(record, "name")
		local transport = quotedField(record, "transport")
		local direction = quotedField(record, "direction")
		local kind = quotedField(record, "kind")
		local response = quotedField(record, "response")
		if name == nil or remoteNames[name] or not hasSafeProductionPlaceRoles(record) then
			emit("FAIL", "All", "REMOTE_SECURITY_RECORD_INVALID", name or "<unknown>")
			return false
		end
		if direction == "ClientToServer" then
			if kind ~= "Request" or response ~= "Required" or transport ~= "ReliableRemoteEvent" then
				emit("FAIL", "All", "CLIENT_REQUEST_SHAPE_INVALID", name)
				return false
			end
			clientRequests[name] = true
		elseif direction == "ServerToClient" then
			if
				kind ~= "Event"
				or response ~= "None"
				or (transport ~= "ReliableRemoteEvent" and transport ~= "UnreliableRemoteEvent")
			then
				emit("FAIL", "All", "SERVER_EVENT_SHAPE_INVALID", name)
				return false
			end
		else
			emit("FAIL", "All", "REMOTE_DIRECTION_INVALID", name)
			return false
		end
		remoteNames[name] = true
		remoteCount += 1
	end
	if remoteCount == 0 or remoteCount ~= countPlainOccurrences(remotesSource, "\n\t\tname =") then
		emit("FAIL", "All", "REMOTE_RECORD_DISCOVERY_INVALID")
		return false
	end

	local rateEndpoints: { [string]: boolean } = {}
	local rateCount = 0
	for record in string.gmatch(ratesSource, "table%.freeze%(%{(.-)%}%)") do
		local endpoint = quotedField(record, "endpoint")
		if
			endpoint == nil
			or rateEndpoints[endpoint]
			or not clientRequests[endpoint]
			or countPlainOccurrences(record, "policy = requirePolicy(") ~= 1
		then
			emit("FAIL", "All", "RATE_POLICY_RECORD_INVALID", endpoint or "<unknown>")
			return false
		end
		rateEndpoints[endpoint] = true
		rateCount += 1
	end
	if rateCount ~= countPlainOccurrences(ratesSource, "\n\t\tendpoint =") then
		emit("FAIL", "All", "RATE_POLICY_DISCOVERY_INVALID")
		return false
	end
	for endpoint in clientRequests do
		if not rateEndpoints[endpoint] then
			emit("FAIL", "All", "CLIENT_REQUEST_RATE_POLICY_MISSING", endpoint)
			return false
		end
	end

	emit("PASS", "All", `NETWORK_REMOTES_{remoteCount}_CLIENT_REQUESTS_{rateCount}`)
	return true
end

local function verifyLobbyTravelSchedulerBoundary(): boolean
	local source = readSource("src/server/lobby/bootstrap/Main.server.luau")
	if source == nil then
		emit("FAIL", "Lobby", "LOBBY_BOOTSTRAP_SOURCE_MISSING", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	local constructorStart = string.find(source, "LobbyTravelCoordinator.new({", 1, true)
	local constructorEnd = if constructorStart == nil
		then nil
		else string.find(source, '"LOBBY_TRAVEL_COORDINATOR_UNAVAILABLE"', constructorStart, true)
	if constructorStart == nil or constructorEnd == nil then
		emit("FAIL", "Lobby", "TRAVEL_COORDINATOR_WIRING_MISSING", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	local wiring = string.sub(source, constructorStart, constructorEnd)
	if
		countPlainOccurrences(wiring, "schedule = task.defer,") ~= 1
		or countPlainOccurrences(wiring, "schedule = task.spawn,") ~= 0
	then
		emit("FAIL", "Lobby", "TRAVEL_SCHEDULER_NOT_DEFERRED", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	emit("PASS", "Lobby", "TRAVEL_SCHEDULER_DEFERRED")

	local reconnectConstructorStart = string.find(source, "LobbyReconnectService.new({", 1, true)
	local reconnectConstructorEnd = if reconnectConstructorStart == nil
		then nil
		else string.find(source, '"LOBBY_RECONNECT_UNAVAILABLE"', reconnectConstructorStart, true)
	if reconnectConstructorStart == nil or reconnectConstructorEnd == nil then
		emit("FAIL", "Lobby", "RECONNECT_SERVICE_WIRING_MISSING", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	local reconnectWiring = string.sub(source, reconnectConstructorStart, reconnectConstructorEnd)
	if
		countPlainOccurrences(reconnectWiring, "schedule = task.defer,") ~= 1
		or countPlainOccurrences(reconnectWiring, "schedule = task.spawn,") ~= 0
	then
		emit("FAIL", "Lobby", "RECONNECT_SCHEDULER_NOT_DEFERRED", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end

	local retryProfileHandlerStart = string.find(source, "LobbyProtocol.ENDPOINTS.RETRY_PROFILE,", 1, true)
	local inventoryHandlerStart = if retryProfileHandlerStart == nil
		then nil
		else string.find(source, "LobbyProtocol.ENDPOINTS.GET_INVENTORY,", retryProfileHandlerStart, true)
	if retryProfileHandlerStart == nil or inventoryHandlerStart == nil then
		emit("FAIL", "Lobby", "PROFILE_RETRY_WIRING_MISSING", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	local retryProfileHandler = string.sub(source, retryProfileHandlerStart, inventoryHandlerStart - 1)
	if
		countPlainOccurrences(retryProfileHandler, "profile:retryLoad(") ~= 1
		or countPlainOccurrences(retryProfileHandler, "scheduleRuntimeWorker(function()") ~= 1
		or countPlainOccurrences(retryProfileHandler, "task.spawn(") ~= 0
		or countPlainOccurrences(retryProfileHandler, "if runtimeCleaned then") ~= 1
		or countPlainOccurrences(retryProfileHandler, "if not scheduled then") ~= 1
	then
		emit("FAIL", "Lobby", "PROFILE_RETRY_NOT_RUNTIME_OWNED", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	emit("PASS", "Lobby", "PROFILE_RETRY_RUNTIME_OWNED")

	local publicationStart = string.find(source, "publishViews = function", 1, true)
	local publicationEnd = if publicationStart == nil
		then nil
		else string.find(source, "local processingReadyByUserId", publicationStart, true)
	if publicationStart == nil or publicationEnd == nil then
		emit("FAIL", "Lobby", "PUBLICATION_WIRING_MISSING", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	local publicationWiring = string.sub(source, publicationStart, publicationEnd - 1)
	if
		countPlainOccurrences(publicationWiring, "runRuntimeWorker(function()") ~= 4
		or countPlainOccurrences(source, "sendProfile(") ~= 1
		or countPlainOccurrences(source, "sendInventory(") ~= 1
		or countPlainOccurrences(source, "sendParty(") ~= 2
		or countPlainOccurrences(source, "sendQueues(") ~= 1
		or countPlainOccurrences(source, "sendActiveRoute(") ~= 3
	then
		emit("FAIL", "Lobby", "PUBLICATION_NOT_RUNTIME_OWNED", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	emit("PASS", "Lobby", "PUBLICATION_RUNTIME_OWNED")

	local mutationStart = string.find(source, "LobbyProtocol.ENDPOINTS.EQUIP_TOWER,", 1, true)
	local mutationEnd = if mutationStart == nil
		then nil
		else string.find(source, "LobbyProtocol.ENDPOINTS.GET_PARTY,", mutationStart, true)
	if mutationStart == nil or mutationEnd == nil then
		emit("FAIL", "Lobby", "PROFILE_MUTATION_WIRING_MISSING", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	local mutationWiring = string.sub(source, mutationStart, mutationEnd - 1)
	if
		countPlainOccurrences(mutationWiring, "ready(context.player)") ~= 6
		or countPlainOccurrences(mutationWiring, "then finishMutation(") ~= 6
	then
		emit("FAIL", "Lobby", "PROFILE_MUTATION_NOT_RUNTIME_GATED", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	emit("PASS", "Lobby", "PROFILE_MUTATION_RUNTIME_GATED")

	local activeRouteHandlerStart = string.find(source, "LobbyProtocol.ENDPOINTS.GET_ACTIVE_ROUTE,", 1, true)
	local reconnectHandlerStart = if activeRouteHandlerStart == nil
		then nil
		else string.find(source, "LobbyProtocol.ENDPOINTS.RECONNECT_ACTIVE_MATCH,", activeRouteHandlerStart, true)
	local runtimeStart = if reconnectHandlerStart == nil
		then nil
		else string.find(source, "local runtimeConnections:", reconnectHandlerStart, true)
	if activeRouteHandlerStart == nil or reconnectHandlerStart == nil or runtimeStart == nil then
		emit("FAIL", "Lobby", "RECONNECT_REQUEST_WIRING_MISSING", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	local activeRouteHandler = string.sub(source, activeRouteHandlerStart, reconnectHandlerStart - 1)
	if
		countPlainOccurrences(activeRouteHandler, "activeRouteViewByUserId[context.player.UserId]") ~= 1
		or countPlainOccurrences(activeRouteHandler, "or noActiveRouteView") ~= 0
		or countPlainOccurrences(activeRouteHandler, "ServerRequestDispatcher.reject(PUBLIC_ERRORS.UNAVAILABLE)") ~= 1
		or countPlainOccurrences(activeRouteHandler, "reconnect:getView(") ~= 0
	then
		emit(
			"FAIL",
			"Lobby",
			"ACTIVE_ROUTE_REQUEST_NOT_CONFIRMED_CACHE_ONLY",
			"src/server/lobby/bootstrap/Main.server.luau"
		)
		return false
	end

	local readyPipelineStart = string.find(source, "local function processPlayerReady", 1, true)
	local readyPipelineEnd = if readyPipelineStart == nil
		then nil
		else string.find(source, "local function finishMutation", readyPipelineStart, true)
	if readyPipelineStart == nil or readyPipelineEnd == nil then
		emit("FAIL", "Lobby", "PLAYER_READY_PIPELINE_MISSING", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	local readyPipeline = string.sub(source, readyPipelineStart, readyPipelineEnd - 1)
	local returnAdmission = string.find(readyPipeline, "returns:admitJoinData", 1, true)
	local returnedRouteRetirement = if returnAdmission == nil
		then nil
		else string.find(readyPipeline, "retireReturnedRoute(player)", returnAdmission, true)
	local initialRoute = if returnedRouteRetirement == nil
		then nil
		else string.find(readyPipeline, "refreshRoute(player)", returnedRouteRetirement, true)
	local initialPublication = if initialRoute == nil
		then nil
		else string.find(readyPipeline, "publishQueueViews()", initialRoute, true)
	local initialClaims = if initialPublication == nil
		then nil
		else string.find(readyPipeline, "pendingClaims:processReady(userId)", initialPublication, true)
	local postClaimPublication = if initialClaims == nil
		then nil
		else string.find(readyPipeline, "publishQueueViews()", initialClaims, true)
	if
		returnAdmission == nil
		or returnedRouteRetirement == nil
		or initialRoute == nil
		or initialPublication == nil
		or initialClaims == nil
		or postClaimPublication == nil
		or not (
			returnAdmission < returnedRouteRetirement
			and returnedRouteRetirement < initialRoute
			and initialRoute < initialPublication
			and initialPublication < initialClaims
			and initialClaims < postClaimPublication
		)
	then
		emit(
			"FAIL",
			"Lobby",
			"PLAYER_READY_RETURN_ROUTE_NOT_RETIRED_BEFORE_REFRESH",
			"src/server/lobby/bootstrap/Main.server.luau"
		)
		return false
	end

	local maintenanceStart = string.find(source, "local readyPlayers: { Player } = {}", runtimeStart, true)
	local maintenanceEnd = if maintenanceStart == nil
		then nil
		else string.find(source, "travelStepRunning = false", maintenanceStart, true)
	if maintenanceStart == nil or maintenanceEnd == nil then
		emit("FAIL", "Lobby", "ROUTE_FIRST_MAINTENANCE_MISSING", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	local maintenance = string.sub(source, maintenanceStart, maintenanceEnd - 1)
	local maintenanceRoute = string.find(maintenance, "refreshRoute(player)", 1, true)
	local maintenancePublication = if maintenanceRoute == nil
		then nil
		else string.find(maintenance, "publishQueueViews()", maintenanceRoute, true)
	local maintenanceClaims = if maintenancePublication == nil
		then nil
		else string.find(maintenance, "pendingClaims:processReady(player.UserId)", maintenancePublication, true)
	local maintenancePostClaims = if maintenanceClaims == nil
		then nil
		else string.find(maintenance, "publishQueueViews()", maintenanceClaims, true)
	if
		maintenanceRoute == nil
		or maintenancePublication == nil
		or maintenanceClaims == nil
		or maintenancePostClaims == nil
		or not (
			maintenanceRoute < maintenancePublication
			and maintenancePublication < maintenanceClaims
			and maintenanceClaims < maintenancePostClaims
		)
	then
		emit(
			"FAIL",
			"Lobby",
			"MAINTENANCE_ROUTE_NOT_PUBLISHED_BEFORE_CLAIMS",
			"src/server/lobby/bootstrap/Main.server.luau"
		)
		return false
	end
	local reconnectHandler = string.sub(source, reconnectHandlerStart, runtimeStart - 1)
	if
		countPlainOccurrences(reconnectHandler, "reconnect:beginReconnect(") ~= 1
		or countPlainOccurrences(reconnectHandler, "reconnect:reconnect(") ~= 0
	then
		emit("FAIL", "Lobby", "RECONNECT_REQUEST_NOT_DEFERRED", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	emit("PASS", "Lobby", "ACTIVE_ROUTE_REQUEST_CONFIRMED_CACHE_ONLY")
	emit("PASS", "Lobby", "PLAYER_READY_ROUTE_PUBLISHED_BEFORE_CLAIMS")
	emit("PASS", "Lobby", "MAINTENANCE_ROUTE_PUBLISHED_BEFORE_CLAIMS")
	emit("PASS", "Lobby", "RECONNECT_SCHEDULER_DEFERRED")

	local cleanupRegistration =
		string.find(source, "configuration.lifecycleRunner:register(runtimeCleanupDefinition)", runtimeStart, true)
	local travelRegistration = if cleanupRegistration == nil
		then nil
		else string.find(
			source,
			"configuration.lifecycleRunner:register(travel:getServiceDefinition())",
			cleanupRegistration,
			true
		)
	local runtimeRegistration = if travelRegistration == nil
		then nil
		else string.find(
			source,
			"configuration.lifecycleRunner:register(runtimeDefinition)",
			travelRegistration,
			true
		)
	if
		cleanupRegistration == nil
		or travelRegistration == nil
		or runtimeRegistration == nil
		or not (cleanupRegistration < travelRegistration and travelRegistration < runtimeRegistration)
		or countPlainOccurrences(source, "while (travelStepRunning or runtimeWorkerCount > 0)") ~= 1
		or countPlainOccurrences(source, 'cleanupUntilSettled("RECONNECT"') ~= 2
		or countPlainOccurrences(source, 'cleanupUntilSettled("PROFILE_TRANSFER"') ~= 1
		or countPlainOccurrences(source, 'error("[ATD_LOBBY_BOOTSTRAP][code=RUNTIME_NOT_QUIESCED]"') ~= 1
	then
		emit("FAIL", "Lobby", "RUNTIME_SHUTDOWN_NOT_JOINED", "src/server/lobby/bootstrap/Main.server.luau")
		return false
	end
	emit("PASS", "Lobby", "RUNTIME_SHUTDOWN_JOINED")
	return true
end

local function verifyMatchReturnSchedulerBoundary(): boolean
	local source = readSource("src/server/match/bootstrap/Main.server.luau")
	if source == nil then
		emit("FAIL", "Match", "MATCH_BOOTSTRAP_SOURCE_MISSING", "src/server/match/bootstrap/Main.server.luau")
		return false
	end
	local constructorStart = string.find(source, "MatchTravelHost.new({", 1, true)
	local constructorEnd = if constructorStart == nil
		then nil
		else string.find(source, '"MATCH_TRAVEL_HOST_UNAVAILABLE"', constructorStart, true)
	if constructorStart == nil or constructorEnd == nil then
		emit("FAIL", "Match", "MATCH_TRAVEL_HOST_WIRING_MISSING", "src/server/match/bootstrap/Main.server.luau")
		return false
	end
	local wiring = string.sub(source, constructorStart, constructorEnd)
	if
		countPlainOccurrences(wiring, "scheduleReturn = task.defer,") ~= 1
		or countPlainOccurrences(wiring, "scheduleReturn = task.spawn,") ~= 0
	then
		emit("FAIL", "Match", "RETURN_SCHEDULER_NOT_DEFERRED", "src/server/match/bootstrap/Main.server.luau")
		return false
	end
	emit("PASS", "Match", "RETURN_SCHEDULER_DEFERRED")
	if
		countPlainOccurrences(wiring, "scheduleRematch = task.defer,") ~= 1
		or countPlainOccurrences(wiring, "scheduleRematch = task.spawn,") ~= 0
	then
		emit("FAIL", "Match", "REMATCH_SCHEDULER_NOT_DEFERRED", "src/server/match/bootstrap/Main.server.luau")
		return false
	end
	emit("PASS", "Match", "REMATCH_SCHEDULER_DEFERRED")
	return true
end

local function verifyMatchDirectStudioSelectionBoundary(): boolean
	local bootstrap = readSource("src/server/match/bootstrap/Main.server.luau")
	local resolver = readSource("src/server/match/playable/DirectStudioContentSelection.luau")
	if bootstrap == nil or resolver == nil then
		emit("FAIL", "Match", "DIRECT_STUDIO_SELECTION_SOURCE_MISSING")
		return false
	end
	local selectionStart =
		string.find(bootstrap, "local directSelection: DirectStudioContentSelection.Selection?", 1, true)
	local studioBranch = if selectionStart == nil
		then nil
		else string.find(bootstrap, "if isStudio then", selectionStart, true)
	local attributeRead = if studioBranch == nil
		then nil
		else string.find(bootstrap, "templateRoot:GetAttribute(attributeName)", studioBranch, true)
	local directHostBranch = string.find(bootstrap, "\n\tif isStudio then\n\t\tlocal studioSelection", 1, true)
	local publishedHostGuard =
		string.find(bootstrap, 'if game.PrivateServerId == "" or game.PrivateServerOwnerId ~= 0 then', 1, true)
	local publishedDirectResolve = string.find(
		bootstrap,
		"DirectStudioContentSelection.resolve(configuration.coreConfiguration, false, nil)",
		1,
		true
	)
	local resolverNonStudioGuard = string.find(resolver, "if not isStudioValue then", 1, true)
	local resolverNonStudioFailure = string.find(resolver, 'return failure("STUDIO_ONLY")', 1, true)
	local resolverReaderCall = string.find(resolver, "pcall(reader", 1, true)
	if
		countPlainOccurrences(bootstrap, "RunService:IsStudio()") ~= 1
		or countPlainOccurrences(bootstrap, "DirectStudioContentSelection.resolve(") ~= 1
		or selectionStart == nil
		or studioBranch == nil
		or attributeRead == nil
		or directHostBranch == nil
		or publishedHostGuard == nil
		or publishedDirectResolve ~= nil
		or not (studioBranch < attributeRead and directHostBranch < publishedHostGuard)
		or string.find(bootstrap, 'error("[ATD_MATCH_BOOTSTRAP][code=AUTHENTICATED_TICKET_HOST_REQUIRED]", 0)', 1, true) == nil
		or string.find(bootstrap, "local initialMapId = ContentSelection.DEVELOPMENT_MAP_ID", 1, true) == nil
		or string.find(
			bootstrap,
			"MatchLifecycleService.new(configuration.log, sendMatchSnapshot, initialMapId)",
			1,
			true
		) == nil
		or string.find(bootstrap, "mapId = ticket.mapId", 1, true) == nil
		or countPlainOccurrences(resolver, 'local MAP_ATTRIBUTE = "ATDStudioMapId"') ~= 1
		or countPlainOccurrences(resolver, 'local DIFFICULTY_ATTRIBUTE = "ATDStudioDifficultyId"') ~= 1
		or resolverNonStudioGuard == nil
		or resolverNonStudioFailure == nil
		or resolverReaderCall == nil
		or not (resolverNonStudioGuard < resolverNonStudioFailure and resolverNonStudioFailure < resolverReaderCall)
	then
		emit("FAIL", "Match", "DIRECT_STUDIO_SELECTION_NOT_GUARDED", "src/server/match/bootstrap/Main.server.luau")
		return false
	end
	emit("PASS", "Match", "DIRECT_STUDIO_SELECTION_GUARDED")
	return true
end

local function verifyMatchContentRewardBoundary(): boolean
	local bootstrap = readSource("src/server/match/bootstrap/Main.server.luau")
	local host = readSource("src/server/match/travel/MatchTravelHost.luau")
	local selection = readSource("src/shared/config/ContentSelection.luau")
	if bootstrap == nil or host == nil or selection == nil then
		emit("FAIL", "Match", "CONTENT_REWARD_POLICY_SOURCE_MISSING")
		return false
	end
	if
		countPlainOccurrences(bootstrap, "ContentSelection.rewardingForSelection(") ~= 1
		or countPlainOccurrences(bootstrap, "rewarding = rewarding,") ~= 1
		or countPlainOccurrences(host, "ContentSelection.rewardingForSelection(") ~= 1
		or countPlainOccurrences(host, "evidence.rewardingMatch ~= rewardingMatch") ~= 1
		or countPlainOccurrences(host, "rewardingMatch = rewardingMatch,") ~= 1
		or countPlainOccurrences(selection, 'hasTag(map, "non-rewarding")') ~= 1
		or countPlainOccurrences(selection, 'hasTag(difficulty, "non-rewarding")') ~= 1
	then
		emit("FAIL", "Match", "CONTENT_REWARD_POLICY_NOT_GUARDED")
		return false
	end
	emit("PASS", "Match", "CONTENT_REWARD_POLICY_GUARDED")
	return true
end

local function verifyProjectSourceIsolation(): boolean
	for _, definition in ALL_BUILDS do
		local projectSource = readSource(definition.project)
		if projectSource == nil then
			emit("FAIL", definition.name, "PROJECT_FILE_MISSING", definition.project)
			return false
		end
		local normalized = string.lower(normalizePath(projectSource))
		if definition.name == "Test" then
			if string.find(normalized, "tests/studio", 1, true) ~= nil then
				emit("FAIL", definition.name, "STUDIO_TEST_SOURCE_MAPPED", definition.project)
				return false
			end
		elseif string.find(normalized, '"tests/', 1, true) ~= nil then
			emit("FAIL", definition.name, "TEST_SOURCE_MAPPED_TO_PRODUCTION", definition.project)
			return false
		end
	end
	return true
end

local function isLuaSourceContainer(instance: Instance): boolean
	return instance.ClassName == "ModuleScript" or instance.ClassName == "Script" or instance.ClassName == "LocalScript"
end

local function collectDescendantsIncluding(root: Instance): { Instance }
	local descendants = { root }
	for _, descendant in root:GetDescendants() do
		table.insert(descendants, descendant)
	end
	return descendants
end

local function countClasses(dataModel: DataModel): (number, number, number)
	local moduleCount = 0
	local scriptCount = 0
	local localScriptCount = 0
	for _, descendant in dataModel:GetDescendants() do
		if descendant.ClassName == "ModuleScript" then
			moduleCount += 1
		elseif descendant.ClassName == "Script" then
			scriptCount += 1
		elseif descendant.ClassName == "LocalScript" then
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
			or descendant.Name == "SafeDevelopmentCommands"
			or descendant.Name == "PlatformProfile"
			or descendant.Name == "RepeatedSessionProfile"
			or descendant.Name == "MicroProfile"
			or descendant.Name == "UiLayoutAudit"
			or descendant.Name == "PerformanceScenarios"
			or string.sub(descendant.Name, -5) == ".spec"
		then
			return true
		end
		if isLuaSourceContainer(descendant) then
			local source = (descendant :: LuaSourceContainer).Source
			if
				string.find(source, "[ATD_TEST]", 1, true) ~= nil
				or string.find(source, "[ATD_PHASE", 1, true) ~= nil
				or string.find(source, "PRIVATE_MODULE_LOAD_VALUE", 1, true) ~= nil
				or string.find(source, "ATD_REPEATED_SESSION_PROFILE", 1, true) ~= nil
				or string.find(source, "development commands require the exact isolated test root", 1, true) ~= nil
			then
				return true
			end
		end
	end
	return false
end

local function hasChild(parent: Instance?, name: string): boolean
	return parent ~= nil and parent:FindFirstChild(name) ~= nil
end

local function verifyRoleLayers(dataModel: DataModel, role: "Default" | "Lobby" | "Match"): boolean
	local serverContainer = dataModel:GetService("ServerScriptService"):FindFirstChild("Server")
	local starterPlayerScripts = dataModel:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local clientContainer = if starterPlayerScripts == nil then nil else starterPlayerScripts:FindFirstChild("Client")
	if
		serverContainer == nil
		or serverContainer.ClassName ~= "Folder"
		or clientContainer == nil
		or clientContainer.ClassName ~= "Folder"
	then
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

local function collectSources(root: Instance): { [string]: SourceRecord }?
	local records: { [string]: SourceRecord } = {}
	local rootPath = root:GetFullName()
	for _, instance in collectDescendantsIncluding(root) do
		if isLuaSourceContainer(instance) then
			local path = instance:GetFullName()
			local relativePath = if path == rootPath then "<root>" else string.sub(path, #rootPath + 2)
			if records[relativePath] ~= nil then
				return nil
			end
			records[relativePath] = {
				className = instance.ClassName,
				source = (instance :: LuaSourceContainer).Source,
			}
		end
	end
	return records
end

local function sourceSignature(record: SourceRecord): string
	return record.className .. "\0" .. record.source
end

local function verifyProduction(dataModel: DataModel, definition: BuildDefinition): boolean
	local modules, scripts, localScripts = countClasses(dataModel)
	if modules == 0 or scripts ~= 1 or localScripts ~= 1 then
		emit("FAIL", definition.name, `PRODUCTION_CLASS_COUNTS_{modules}_{scripts}_{localScripts}`)
		return false
	end
	local expectedRole = EXPECTED_PLACE_ROLES[definition.name]
	local actualRole = dataModel:GetService("ReplicatedStorage"):GetAttribute("ATDPlaceRole")
	if actualRole ~= expectedRole then
		emit("FAIL", definition.name, "PLACE_ROLE_MISMATCH")
		return false
	end
	local shared = dataModel:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	if shared == nil or shared.ClassName ~= "Folder" or collectSources(shared) == nil then
		emit("FAIL", definition.name, "SHARED_SOURCE_STRUCTURE")
		return false
	end
	if hasTestLeak(dataModel) then
		emit("FAIL", definition.name, "TEST_CONTENT_LEAK")
		return false
	end
	if not verifyRoleLayers(dataModel, definition.name :: "Default" | "Lobby" | "Match") then
		emit("FAIL", definition.name, "ROLE_LAYER_ISOLATION")
		return false
	end

	emit("PASS", definition.name, `MODULES_{modules}_SCRIPTS_{scripts}_LOCALSCRIPTS_{localScripts}`)
	return true
end

local function verifySpecs(specs: Instance): (boolean, number)
	local specCount = 0
	for _, descendant in specs:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			if string.sub(descendant.Name, -5) ~= ".spec" then
				return false, specCount
			end
			specCount += 1
		elseif not descendant:IsA("Folder") then
			return false, specCount
		end
	end
	return specCount > 0, specCount
end

local function verifyTest(
	dataModel: DataModel,
	definition: BuildDefinition,
	productionSourceSignatures: { [string]: boolean }
): boolean
	local modules, scripts, localScripts = countClasses(dataModel)
	if modules == 0 or scripts ~= 0 or localScripts ~= 0 then
		emit("FAIL", definition.name, `TEST_CLASS_COUNTS_{modules}_{scripts}_{localScripts}`)
		return false
	end
	local serverStorage = dataModel:GetService("ServerStorage")
	local automatedTests = serverStorage:FindFirstChild("AutomatedTests")
	local negativeControls = serverStorage:FindFirstChild("NegativeControls")
	local specs = if automatedTests == nil then nil else automatedTests:FindFirstChild("Specs")
	local fixtures = if automatedTests == nil then nil else automatedTests:FindFirstChild("Fixtures")
	local support = if automatedTests == nil then nil else automatedTests:FindFirstChild("Support")
	if
		automatedTests == nil
		or automatedTests.ClassName ~= "Folder"
		or negativeControls == nil
		or specs == nil
		or specs.ClassName ~= "Folder"
		or fixtures == nil
		or fixtures.ClassName ~= "Folder"
		or support == nil
		or support.ClassName ~= "Folder"
	then
		emit("FAIL", definition.name, "TEST_BOUNDARY_STRUCTURE")
		return false
	end
	local starterPlayerScripts = dataModel:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	if
		dataModel:GetService("ServerScriptService"):FindFirstChild("Server") ~= nil
		or (starterPlayerScripts ~= nil and starterPlayerScripts:FindFirstChild("Client") ~= nil)
	then
		emit("FAIL", definition.name, "PRODUCTION_RUNTIME_PRESENT")
		return false
	end
	for supportName in REQUIRED_TEST_SUPPORT do
		local supportModule = support:FindFirstChild(supportName)
		if supportModule == nil or supportModule.ClassName ~= "ModuleScript" then
			emit("FAIL", definition.name, "TEST_SUPPORT_MISSING", supportName)
			return false
		end
	end
	local specsValid, specCount = verifySpecs(specs)
	if not specsValid then
		emit("FAIL", definition.name, "SPEC_STRUCTURE_INVALID")
		return false
	end

	local mirroredCount = 0
	for _, child in automatedTests:GetChildren() do
		if string.sub(child.Name, 1, 10) == "Production" then
			for _, instance in collectDescendantsIncluding(child) do
				if isLuaSourceContainer(instance) then
					if instance.ClassName ~= "ModuleScript" then
						emit("FAIL", definition.name, "MIRRORED_RUNNABLE_SOURCE", instance:GetFullName())
						return false
					end
					local signature = sourceSignature({
						className = instance.ClassName,
						source = (instance :: LuaSourceContainer).Source,
					})
					if next(productionSourceSignatures) ~= nil and not productionSourceSignatures[signature] then
						emit("FAIL", definition.name, "MIRRORED_SOURCE_MISMATCH", instance:GetFullName())
						return false
					end
					mirroredCount += 1
				end
			end
		end
	end
	if mirroredCount == 0 then
		emit("FAIL", definition.name, "MIRRORED_SOURCE_MISSING")
		return false
	end

	emit("PASS", definition.name, `MODULES_{modules}_SPECS_{specCount}_MIRRORED_{mirroredCount}_RUNNABLE_SCRIPTS_0`)
	return true
end

local function sameSourceRecords(left: { [string]: SourceRecord }, right: { [string]: SourceRecord }): boolean
	local leftCount = 0
	local rightCount = 0
	for path, leftRecord in left do
		leftCount += 1
		local rightRecord = right[path]
		if
			rightRecord == nil
			or rightRecord.className ~= leftRecord.className
			or rightRecord.source ~= leftRecord.source
		then
			return false
		end
	end
	for _ in right do
		rightCount += 1
	end
	return leftCount == rightCount
end

local function verifySharedConsistency(dataModels: { [Role]: DataModel }): boolean
	local baselineName: Role? = nil
	local baseline: { [string]: SourceRecord }? = nil
	for _, definition in ALL_BUILDS do
		local dataModel = dataModels[definition.name]
		if dataModel ~= nil then
			local shared = dataModel:GetService("ReplicatedStorage"):FindFirstChild("Shared")
			if shared == nil then
				emit("FAIL", definition.name, "SHARED_SOURCE_MISSING")
				return false
			end
			local records = collectSources(shared)
			if records == nil then
				emit("FAIL", definition.name, "SHARED_SOURCE_DUPLICATE")
				return false
			end
			if baseline == nil then
				baselineName = definition.name
				baseline = records
			elseif not sameSourceRecords(baseline, records) then
				emit("FAIL", definition.name, "SHARED_SOURCE_DIVERGENCE", baselineName :: Role)
				return false
			end
		end
	end
	return true
end

local function collectProductionSignatures(dataModels: { [Role]: DataModel }): { [string]: boolean }
	local signatures: { [string]: boolean } = {}
	for _, role: Role in { "Default", "Lobby", "Match" } do
		local dataModel = dataModels[role]
		if dataModel ~= nil then
			for _, descendant in dataModel:GetDescendants() do
				if isLuaSourceContainer(descendant) then
					signatures[sourceSignature({
						className = descendant.ClassName,
						source = (descendant :: LuaSourceContainer).Source,
					})] =
						true
				end
			end
		end
	end
	return signatures
end

local function printCapturedOutput(value: unknown)
	if type(value) == "string" and #value > 0 then
		local trimmed = string.gsub(value, "%s+$", "")
		if #trimmed > 0 then
			print(trimmed)
		end
	end
end

local function runHeadlessSuite(testPlacePath: string): boolean
	local executed, result = pcall(process.exec, "lune", {
		"run",
		"tests/run.luau",
		"--built-place",
		testPlacePath,
	})
	if executed and type(result) == "table" then
		printCapturedOutput((result :: any).stdout)
		printCapturedOutput((result :: any).stderr)
	end
	if not executed or type(result) ~= "table" or not (result :: any).ok then
		emit("FAIL", "Test", "HEADLESS_SUITE_FAILED")
		return false
	end
	return true
end

local function prepareBuildDirectory(): boolean
	if fs.isFile(BUILD_DIRECTORY) then
		emit("FAIL", "All", "BUILD_PATH_NOT_DIRECTORY", BUILD_DIRECTORY)
		return false
	end
	if not fs.isDir(BUILD_DIRECTORY) then
		if not pcall(fs.writeDir, BUILD_DIRECTORY) then
			emit("FAIL", "All", "BUILD_DIRECTORY_CREATE_FAILED", BUILD_DIRECTORY)
			return false
		end
		createdBuildDirectory = true
	end
	return true
end

local function buildAndDeserialize(definition: BuildDefinition): DataModel?
	if not fs.isFile(definition.project) then
		emit("FAIL", definition.name, "PROJECT_FILE_MISSING", definition.project)
		return nil
	end
	if fs.isFile(definition.output) then
		emit("FAIL", definition.name, "OUTPUT_ALREADY_EXISTS", definition.output)
		return nil
	end
	ownedOutputs[definition.output] = true
	local executed, result = pcall(process.exec, "rojo", {
		"build",
		definition.project,
		"--output",
		definition.output,
	})
	if not executed or type(result) ~= "table" or not (result :: any).ok or not fs.isFile(definition.output) then
		emit("FAIL", definition.name, "BUILD_FAILED", definition.project)
		return nil
	end
	local readSucceeded, contents = pcall(fs.readFile, definition.output)
	if not readSucceeded then
		emit("FAIL", definition.name, "BUILD_READ_FAILED", definition.output)
		return nil
	end
	local deserialized, dataModel = pcall(roblox.deserializePlace, contents)
	if not deserialized then
		emit("FAIL", definition.name, "BUILD_DESERIALIZE_FAILED", definition.output)
		return nil
	end
	return dataModel :: DataModel
end

local function run(): boolean
	local arguments = parseArguments()
	if arguments == nil then
		emit("FAIL", "All", "INVALID_ARGUMENTS", "tests/verify-builds.luau")
		return false
	end
	currentStage = "security"
	if
		not verifyNetworkSecurityBoundary()
		or not verifyLobbyTravelSchedulerBoundary()
		or not verifyMatchReturnSchedulerBoundary()
		or not verifyMatchDirectStudioSelectionBoundary()
		or not verifyMatchContentRewardBoundary()
		or not verifyProjectSourceIsolation()
		or not verifyLocalizationReferences()
	then
		return false
	end
	currentStage = "build_directory"
	if not prepareBuildDirectory() then
		return false
	end

	local dataModels: { [Role]: DataModel } = {}
	for _, definition in ALL_BUILDS do
		if arguments.selectedProjects[definition.name] then
			currentStage = `build_{definition.name}`
			local dataModel = buildAndDeserialize(definition)
			if dataModel == nil then
				return false
			end
			dataModels[definition.name] = dataModel
		end
	end

	currentStage = "verify_production"
	for _, definition in ALL_BUILDS do
		local dataModel = dataModels[definition.name]
		if dataModel ~= nil and definition.name ~= "Test" and not verifyProduction(dataModel, definition) then
			return false
		end
	end
	currentStage = "verify_shared"
	if not verifySharedConsistency(dataModels) then
		return false
	end
	local testDataModel = dataModels.Test
	if testDataModel ~= nil then
		currentStage = "verify_test"
		if not verifyTest(testDataModel, ALL_BUILDS[4], collectProductionSignatures(dataModels)) then
			return false
		end
	end
	if arguments.runTests then
		currentStage = "headless_suite"
		if testDataModel == nil or not runHeadlessSuite(ALL_BUILDS[4].output) then
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
