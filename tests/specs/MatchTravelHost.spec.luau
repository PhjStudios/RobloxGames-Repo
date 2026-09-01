--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local ConfigurationValidator = require(ReplicatedStorage.Shared.config.ConfigurationValidator)
local MatchLoadoutProtocol = require(ReplicatedStorage.Shared.match.MatchLoadoutProtocol)
local Result = require(ReplicatedStorage.Shared.util.Result)
local TravelProtocol = require(ReplicatedStorage.Shared.travel.TravelProtocol)

local MatchTravelHost = require(script.Parent.Parent.ProductionServerMatchTravel.MatchTravelHost)

local function connection(): any
	return {
		Disconnect = function() end,
	}
end

local function success(assertions: TestHarness.Assertions, value: any): any
	if not value.ok then
		error(`expected success: {if type(value.error) == "table" then value.error.code else tostring(value.error)}`, 0)
	end
	assertions.isTrue(value.ok)
	return value.value
end

local function loadout(configuration: any, userId: number): any
	local firstTower = configuration.towers.ordered[1]
	local validated = MatchLoadoutProtocol.validate({
		userId = userId,
		revision = 7,
		slots = {
			{ slot = 1, unitId = `unit:travel-{userId}`, towerId = firstTower.id },
		},
		settings = configuration.defaultSettings,
	}, configuration)
	if not validated.ok then
		error("expected valid fixture loadout", 0)
	end
	return validated.value
end

local function makeRig(assertions: TestHarness.Assertions, userIdsValue: { number }?): any
	local configured = ConfigurationValidator.validateLoaded()
	local configuration = success(assertions, configured)
	local userIds = userIdsValue or { 101, 202 }
	local players = {}
	local ids = {}
	local routing = {}
	local live = {}
	for _, userId in userIds do
		local player = { name = `Player{userId}` }
		table.insert(players, player)
		ids[player] = userId
		live[player] = true
		routing[player] = success(assertions, TravelProtocol.match("ticket:host-test", "attempt:host-join"))
	end
	local nowValue = 1_700_000_000
	local mapId = configuration.maps.ordered[1].id
	local difficultyId = configuration.maps.ordered[1].supportedDifficultyIds[1]
	local members = {}
	for _, userId in userIds do
		table.insert(members, {
			userId = userId,
			loadout = loadout(configuration, userId),
			admissionState = "Expected",
			admittedAt = nil,
		})
	end
	local ticket = {
		version = 1,
		revision = 1,
		ticketId = "ticket:host-test",
		matchId = "match:host-test",
		resultId = "result:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
		expectedUserIds = table.clone(userIds),
		captainUserId = userIds[1],
		mapId = mapId,
		difficultyId = difficultyId,
		privacy = "PartyOnly",
		lobbyOrigin = { placeId = 100, jobId = "lobby-job" },
		members = members,
		createdAt = nowValue - 1,
		expiresAt = nowValue + 599,
		claimedDestinationJobId = nil,
		claimedDestinationAt = nil,
		state = "Teleporting",
		retryCount = 0,
		terminalReason = nil,
	}
	local added: ((any) -> ())? = nil
	local removing: ((any) -> ())? = nil
	local heartbeat: (() -> ())? = nil
	local rejected = {}
	local profileStates = {}
	for _, userId in userIds do
		profileStates[userId] = "Ready"
	end
	local profile = {}
	function profile:getState(userId)
		return profileStates[userId]
	end
	function profile:read(_userId)
		return Result.ok({})
	end
	function profile:release(_userId)
		return Result.ok(true)
	end
	function profile:load(_userId)
		return Result.ok(true)
	end
	local ticketStore = {}
	local terminalTickets = {}
	function ticketStore:get(ticketId, _currentTime)
		return if ticketId == ticket.ticketId then Result.ok(ticket) else Result.err({ code = "NOT_FOUND" })
	end
	function ticketStore:markTerminal(ticketId, reason, _currentTime)
		terminalTickets[ticketId] = reason
		return Result.ok(true)
	end
	local admissionKinds = {}
	for _, userId in userIds do
		admissionKinds[userId] = "Participant"
	end
	local admissionBindings = {}
	local returnedAdmissions = {}
	local admissionDisconnectCount = 0
	local admission = {}
	function admission:admit(player, routingData, jobId, currentTime)
		local userId = ids[player]
		if userId == nil or jobId ~= "match-job" then
			return Result.err({ code = "UNEXPECTED_PLAYER" })
		end
		local kind = if routingData.kind == "Rejoin" then "Rejoined" else admissionKinds[userId]
		admissionBindings[player] = true
		ticket.claimedDestinationJobId = jobId
		ticket.claimedDestinationAt = ticket.claimedDestinationAt or currentTime
		return Result.ok({
			kind = kind,
			userId = userId,
			matchId = ticket.matchId,
			ticketId = ticket.ticketId,
			loadout = members[table.find(userIds, userId)].loadout,
		})
	end
	function admission:disconnect(player)
		admissionDisconnectCount += 1
		admissionBindings[player] = nil
		return Result.ok(true)
	end
	function admission:markReturned(player, currentTime)
		local userId = ids[player]
		returnedAdmissions[userId] = true
		admissionBindings[player] = nil
		return Result.ok(currentTime <= ticket.expiresAt)
	end
	function admission:retryReturns(_currentTime)
		return Result.ok(0)
	end
	function admission:resolve(player)
		return if admissionBindings[player] then Result.ok(true) else Result.err({ code = "NOT_FOUND" })
	end
	function admission:cleanup()
		table.clear(admissionBindings)
		return Result.ok(true)
	end
	local boundRoutes = {}
	local clearedRoutes = {}
	local routeClearFailuresRemaining = 0
	local bindingFailuresRemaining = 0
	local routes = {}
	function routes:bindDestination(userId, matchId, jobId, _currentTime)
		if bindingFailuresRemaining > 0 then
			bindingFailuresRemaining -= 1
			return Result.err({ code = "STORE_UNAVAILABLE" })
		end
		if matchId ~= ticket.matchId or jobId ~= "match-job" then
			return Result.err({ code = "CONFLICT" })
		end
		boundRoutes[userId] = jobId
		return Result.ok({ applied = boundRoutes[userId] == nil })
	end
	function routes:find(userId, _currentTime)
		return if boundRoutes[userId] == nil
			then Result.ok(nil)
			else Result.ok({
				routeId = `route:host-{userId}`,
				userId = userId,
				ticketId = ticket.ticketId,
				matchId = ticket.matchId,
				destinationJobId = boundRoutes[userId],
			})
	end
	function routes:clear(userId, matchId)
		if routeClearFailuresRemaining > 0 then
			routeClearFailuresRemaining -= 1
			return Result.err({ code = "STORE_UNAVAILABLE" })
		end
		clearedRoutes[userId] = matchId
		return Result.ok(true)
	end
	local preparedCount = 0
	local rollbackCount = 0
	local rollbackFailuresRemaining = 0
	local commitCount = 0
	local commitFailuresRemaining = 0
	local profileTransfer = {}
	function profileTransfer:prepare(returnUserIds)
		preparedCount += 1
		return Result.ok({ handle = { roster = table.clone(returnUserIds) } })
	end
	function profileTransfer:rollback(_handle)
		rollbackCount += 1
		if rollbackFailuresRemaining > 0 then
			rollbackFailuresRemaining -= 1
			return Result.err({ code = "ROLLBACK_FAILED" })
		end
		return Result.ok(true)
	end
	function profileTransfer:commit(_handle)
		commitCount += 1
		if commitFailuresRemaining > 0 then
			commitFailuresRemaining -= 1
			return Result.err({ code = "COMMIT_FAILED" })
		end
		return Result.ok(true)
	end
	local returnRecords = { records = {} }
	local terminalReturns = {}
	function returnRecords:create(record, _currentTime)
		table.insert(self.records, record)
		return Result.ok({ record = record, applied = true })
	end
	function returnRecords:markTerminal(returnId, reason, _currentTime)
		terminalReturns[returnId] = reason
		return Result.ok(true)
	end
	local publicTeleports = {}
	local teleportShouldFail = false
	local teleportInitFailed: ((any, string, any) -> ())? = nil
	local teleport = {}
	function teleport:teleportPublic(placeId, returnPlayers, routingData)
		table.insert(publicTeleports, { placeId = placeId, players = returnPlayers, routing = routingData })
		return if teleportShouldFail
			then Result.err({ code = "TELEPORT_FAILED", failureClass = "Retryable" })
			else Result.ok(true)
	end
	function teleport:connectInitFailed(listener)
		teleportInitFailed = listener
		return connection()
	end
	local evidence: any? = nil
	local playable: any = {
		admissions = {},
		disconnections = {},
		rewardViews = {},
	}
	function playable:admitAuthorized(player, participant)
		table.insert(self.admissions, { player = player, participant = participant })
		return { accepted = true, reason = "Accepted" }
	end
	function playable:disconnectAuthorized(player)
		table.insert(self.disconnections, player)
		return { accepted = true, reason = "Accepted" }
	end
	function playable:getResultEvidence()
		return if evidence == nil then Result.err("UNAVAILABLE") else Result.ok(evidence)
	end
	function playable:getSnapshot(player)
		local userId = ids[player]
		local spectator = admissionKinds[userId] == "LateSpectator"
		return Result.ok({
			viewerRole = if spectator then "Spectator" else "Participant",
			stats = {
				battleCashEarned = if spectator then 0 else 50,
				battleCashSpent = if spectator then 0 else 25,
			},
		})
	end
	function playable:setRewardView(userId, view)
		self.rewardViews[userId] = view
		return { accepted = true, reason = "Accepted" }
	end
	local factoryCalls = {}
	local stopped = 0
	local ledgerCreates = {}
	local ledgerCreateAttempts = {}
	local ledgerCreateFailuresRemaining = 0
	local ledgerFailureCode: string? = nil
	local ledgerCommitThenFail = false
	local ledgerMarkFailureCode: string? = nil
	local ledgerFailures = {}
	local ledgerRenewals = {}
	local durableFailure = false
	local resultLedger = {}
	function resultLedger:create(record)
		table.insert(ledgerCreateAttempts, record)
		if ledgerCreateFailuresRemaining > 0 then
			ledgerCreateFailuresRemaining -= 1
			return Result.err({ code = "STORE_UNAVAILABLE" })
		end
		if ledgerCommitThenFail then
			ledgerCommitThenFail = false
			table.insert(ledgerCreates, record)
			return Result.err({ code = "STORE_UNAVAILABLE" })
		end
		if ledgerFailureCode ~= nil then
			return Result.err({ code = ledgerFailureCode })
		end
		table.insert(ledgerCreates, record)
		return Result.ok(#ledgerCreates == 1)
	end
	function resultLedger:markFailed(resultId, matchId, ticketId, reason, currentTime)
		if ledgerMarkFailureCode ~= nil then
			return Result.err({ code = ledgerMarkFailureCode })
		end
		table.insert(ledgerFailures, {
			resultId = resultId,
			matchId = matchId,
			ticketId = ticketId,
			reason = reason,
			createdAt = currentTime,
		})
		durableFailure = true
		return Result.ok(#ledgerFailures == 1)
	end
	function resultLedger:renewIntent(resultId, matchId, ticketId, currentTime)
		table.insert(ledgerRenewals, {
			resultId = resultId,
			matchId = matchId,
			ticketId = ticketId,
			currentTime = currentTime,
		})
		return Result.ok(true)
	end
	local claimCounts = {}
	local rewardClaims = {}
	function rewardClaims:claim(userId, resultId)
		claimCounts[userId] = (claimCounts[userId] or 0) + 1
		local spectator = admissionKinds[userId] == "LateSpectator"
		return Result.ok({
			resultId = resultId,
			status = if durableFailure then "Failed" elseif spectator then "Ineligible" else "Granted",
			persistentGoldAwarded = if spectator then 0 else 250,
			firstClearBonus = 0,
			battleCashEarned = if spectator then 0 else 50,
			battleCashSpent = if spectator then 0 else 25,
			reason = if durableFailure then "RESULT_PIPELINE_FAILED" elseif spectator then "Spectator" else "Granted",
		})
	end
	local rematchCalls = {}
	local travelPublications = {}
	local dependencyCleanupCount = 0
	local dependencyStepCount = 0
	local nextReturnId = 0
	local created = MatchTravelHost.new({
		configuration = configuration,
		profile = profile,
		ticketStore = ticketStore,
		admission = admission,
		routes = routes,
		returnRecords = returnRecords,
		profileTransfer = profileTransfer,
		teleport = teleport,
		resultLedger = resultLedger,
		rewardClaims = rewardClaims,
		snapshotSender = function(player, snapshot)
			table.insert(travelPublications, { player = player, snapshot = snapshot })
			return true
		end,
		playableFactory = function(factoryTicket, connectedUserIds)
			table.insert(factoryCalls, { ticket = factoryTicket, connectedUserIds = table.clone(connectedUserIds) })
			return Result.ok(playable)
		end,
		stopPlayable = function(_playable)
			stopped += 1
		end,
		createRematch = function(activeUserIds, previousTicket)
			table.insert(rematchCalls, { userIds = table.clone(activeUserIds), ticket = previousTicket })
			local revisions = {}
			for _, userId in activeUserIds do
				table.insert(revisions, { userId = userId, revision = 8 })
			end
			return {
				matchId = "match:fresh-host-test",
				resultId = "result:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
				ticketId = "ticket:fresh-host-test",
				loadouts = revisions,
			}
		end,
		stepDependencies = function()
			dependencyStepCount += 1
		end,
		cleanupDependencies = function()
			dependencyCleanupCount += 1
		end,
		environment = {
			now = function()
				return nowValue
			end,
			getUserId = function(player)
				return ids[player]
			end,
			isLive = function(player)
				return live[player] == true
			end,
			getPlayers = function()
				return table.clone(players)
			end,
			getRoutingData = function(player)
				return routing[player]
			end,
			connectPlayerAdded = function(callback)
				added = callback
				return connection()
			end,
			connectPlayerRemoving = function(callback)
				removing = callback
				return connection()
			end,
			connectHeartbeat = function(callback)
				heartbeat = callback
				return connection()
			end,
			destinationJobId = "match-job",
			lobbyPlaceId = 100,
			generateReturnId = function()
				nextReturnId += 1
				return `return:host-test-{nextReturnId}`
			end,
			safeReturnUnexpected = function(player, reason)
				table.insert(rejected, { player = player, reason = reason })
			end,
		},
	})
	local host = success(assertions, created)
	local lifecycle = host:getServiceDefinition()
	lifecycle.initialize()
	lifecycle.start()
	return {
		host = host,
		lifecycle = lifecycle,
		configuration = configuration,
		players = players,
		ids = ids,
		routing = routing,
		live = live,
		ticket = ticket,
		admissionKinds = admissionKinds,
		returnedAdmissions = returnedAdmissions,
		profileStates = profileStates,
		playable = playable,
		factoryCalls = factoryCalls,
		boundRoutes = boundRoutes,
		clearedRoutes = clearedRoutes,
		terminalTickets = terminalTickets,
		rejected = rejected,
		ledgerCreates = ledgerCreates,
		ledgerCreateAttempts = ledgerCreateAttempts,
		ledgerFailures = ledgerFailures,
		ledgerRenewals = ledgerRenewals,
		claimCounts = claimCounts,
		returnRecords = returnRecords,
		terminalReturns = terminalReturns,
		publicTeleports = publicTeleports,
		rematchCalls = rematchCalls,
		travelPublications = travelPublications,
		admissionDisconnectCount = function()
			return admissionDisconnectCount
		end,
		setBindingFailures = function(count)
			bindingFailuresRemaining = count
		end,
		setRouteClearFailures = function(count)
			routeClearFailuresRemaining = count
		end,
		dependencyCleanupCount = function()
			return dependencyCleanupCount
		end,
		dependencyStepCount = function()
			return dependencyStepCount
		end,
		fireAdded = function(player)
			(added :: any)(player)
		end,
		fireRemoving = function(player)
			(removing :: any)(player)
		end,
		fireHeartbeat = function()
			(heartbeat :: any)()
		end,
		advance = function(seconds)
			nowValue += seconds
		end,
		setEvidence = function(value)
			evidence = value
		end,
		setLedgerFailure = function(code)
			ledgerFailureCode = code
		end,
		setLedgerCreateFailures = function(count)
			ledgerCreateFailuresRemaining = count
		end,
		commitLedgerThenFail = function()
			ledgerCommitThenFail = true
		end,
		setLedgerMarkFailure = function(code)
			ledgerMarkFailureCode = code
		end,
		setTeleportFailure = function(value)
			teleportShouldFail = value
		end,
		setRollbackFailures = function(count)
			rollbackFailuresRemaining = count
		end,
		setCommitFailures = function(count)
			commitFailuresRemaining = count
		end,
		emitInitFailure = function(player, failureClass, routingData)
			local eventRouting = routingData
			if eventRouting == nil then
				eventRouting = publicTeleports[#publicTeleports].routing
			end
			(teleportInitFailed :: any)(player, failureClass, { placeId = 100, routingData = eventRouting })
		end,
		transferCounts = function()
			return preparedCount, rollbackCount, commitCount
		end,
		stopped = function()
			return stopped
		end,
	}
end

local function resultEvidence(rig: any): any
	local entries = {}
	for _, userId in rig.ticket.expectedUserIds do
		local participant = rig.admissionKinds[userId] ~= "LateSpectator"
		table.insert(entries, {
			userId = userId,
			authenticatedParticipant = participant,
			spectator = not participant,
			submittedReady = participant,
			placements = if participant then 1 else 0,
			wavesCompleted = 2,
			connectedAtResults = participant,
			battleCashEarned = if participant then 50 else 0,
			battleCashSpent = if participant then 25 else 0,
		})
	end
	return {
		matchId = rig.ticket.matchId,
		mapId = rig.ticket.mapId,
		difficultyId = rig.ticket.difficultyId,
		outcome = "Victory",
		rewardingMatch = true,
		entries = entries,
	}
end

return TestHarness.suite("ticketed Match travel host composition", {
	TestHarness.case(
		"starts lazily with only the authenticated participant and keeps a late arrival spectating",
		function(assertions)
			local rig = makeRig(assertions)
			rig.profileStates[202] = "Loading"
			rig.fireHeartbeat()
			assertions.equal(#rig.factoryCalls, 1)
			assertions.equal(#rig.factoryCalls[1].connectedUserIds, 1)
			assertions.equal(rig.factoryCalls[1].connectedUserIds[1], 101)
			assertions.equal(rig.playable.admissions[1].participant, true)
			assertions.equal(rig.boundRoutes[101], "match-job")
			assertions.equal(rig.boundRoutes[202], "match-job")

			rig.admissionKinds[202] = "LateSpectator"
			rig.profileStates[202] = "Ready"
			rig.advance(31)
			rig.fireHeartbeat()
			assertions.equal(#rig.factoryCalls, 1)
			assertions.equal(rig.playable.admissions[2].participant, false)
			local spectator = success(assertions, rig.host:getSnapshot(rig.players[2]))
			assertions.equal(spectator.viewerRole, "Spectator")
			assertions.isNil((spectator :: any).ticketId)
			assertions.isNil((spectator :: any).resultId)
			assertions.isNil((spectator :: any).reservedServerAccessCode)
			rig.lifecycle.shutdown()
		end
	),
	TestHarness.case("holds Ready until every expected arrival or the initial grace expires", function(assertions)
		local allArrive = makeRig(assertions)
		allArrive.profileStates[202] = "Loading"
		allArrive.fireHeartbeat()
		assertions.isFalse(allArrive.host:canSubmitReady(allArrive.players[1]))
		allArrive.profileStates[202] = "Ready"
		allArrive.fireHeartbeat()
		assertions.isTrue(allArrive.host:canSubmitReady(allArrive.players[1]))
		allArrive.lifecycle.shutdown()

		local grace = makeRig(assertions)
		grace.profileStates[202] = "Loading"
		grace.fireHeartbeat()
		assertions.isFalse(grace.host:canSubmitReady(grace.players[1]))
		grace.advance(30)
		assertions.isTrue(grace.host:canSubmitReady(grace.players[1]))
		grace.admissionKinds[202] = "LateSpectator"
		grace.profileStates[202] = "Ready"
		grace.fireHeartbeat()
		assertions.equal(success(assertions, grace.host:getSnapshot(grace.players[2])).viewerRole, "Spectator")
		assertions.isFalse(grace.host:canSubmitReady(grace.players[2]))
		grace.lifecycle.shutdown()
	end),
	TestHarness.case("disconnects immediately and rebinds one stable participant on a route", function(assertions)
		local rig = makeRig(assertions, { 101 })
		rig.fireHeartbeat()
		local original = rig.players[1]
		rig.live[original] = false
		rig.fireRemoving(original)
		assertions.equal(#rig.playable.disconnections, 1)
		local replacement = { name = "Replacement101" }
		rig.ids[replacement] = 101
		rig.live[replacement] = true
		rig.routing[replacement] = success(assertions, TravelProtocol.rejoin("route:host-test", "attempt:host-test"))
		table.insert(rig.players, replacement)
		rig.fireAdded(replacement)
		rig.fireHeartbeat()
		assertions.equal(#rig.factoryCalls, 1)
		assertions.equal(#rig.playable.admissions, 2)
		assertions.equal(rig.playable.admissions[2].participant, true)
		assertions.isNotNil(rig.host:getPlayable(replacement))
		rig.lifecycle.shutdown()
	end),
	TestHarness.case(
		"retries transient destination binding without stranding an admitted solo player",
		function(assertions)
			local rig = makeRig(assertions, { 101 })
			rig.setBindingFailures(2)
			rig.fireHeartbeat()
			assertions.equal(#rig.factoryCalls, 0)
			assertions.equal(#rig.rejected, 0)
			assertions.equal(rig.admissionDisconnectCount(), 1)
			rig.setBindingFailures(0)
			rig.fireHeartbeat()
			assertions.equal(#rig.factoryCalls, 1)
			assertions.equal(#rig.playable.admissions, 1)
			assertions.equal(rig.playable.admissions[1].participant, true)
			assertions.equal(#rig.rejected, 0)
			rig.lifecycle.shutdown()
		end
	),
	TestHarness.case("creates and claims one authoritative result then stops terminal retries", function(assertions)
		local rig = makeRig(assertions)
		rig.fireHeartbeat()
		rig.setEvidence(resultEvidence(rig))
		rig.fireHeartbeat()
		assertions.equal(#rig.ledgerCreates, 1)
		assertions.equal(rig.ledgerCreates[1].resultId, rig.ticket.resultId)
		assertions.equal(rig.claimCounts[101], 1)
		assertions.equal(rig.claimCounts[202], 1)
		assertions.equal(rig.playable.rewardViews[101].status, "Granted")
		rig.advance(2)
		rig.fireHeartbeat()
		assertions.equal(#rig.ledgerCreates, 1)
		assertions.equal(rig.claimCounts[101], 1)
		assertions.equal(rig.claimCounts[202], 1)
		rig.lifecycle.shutdown()
	end),
	TestHarness.case("renews an active result intent at a bounded cadence", function(assertions)
		local rig = makeRig(assertions, { 101 })
		rig.fireHeartbeat()
		assertions.equal(rig.dependencyStepCount(), 1)
		assertions.equal(#rig.ledgerRenewals, 1)
		assertions.equal(rig.ledgerRenewals[1].resultId, rig.ticket.resultId)
		rig.advance(59)
		rig.fireHeartbeat()
		assertions.equal(#rig.ledgerRenewals, 1)
		rig.advance(1)
		rig.fireHeartbeat()
		assertions.equal(#rig.ledgerRenewals, 2)
		assertions.equal(rig.dependencyStepCount(), 3)
		rig.lifecycle.shutdown()
	end),
	TestHarness.case("reuses one immutable result timestamp after an ambiguous ledger write", function(assertions)
		local rig = makeRig(assertions, { 101 })
		rig.fireHeartbeat()
		rig.setEvidence(resultEvidence(rig))
		rig.commitLedgerThenFail()
		rig.fireHeartbeat()
		assertions.equal(#rig.ledgerCreates, 1)
		local createdAt = rig.ledgerCreates[1].createdAt
		rig.advance(2)
		rig.fireHeartbeat()
		assertions.equal(#rig.ledgerCreates, 2)
		assertions.equal(rig.ledgerCreates[2].createdAt, createdAt)
		assertions.isTrue(rig.host:getMetrics().resultCreated)
		rig.lifecycle.shutdown()
	end),
	TestHarness.case("retries one cached immutable result before any shutdown failure tombstone", function(assertions)
		local rig = makeRig(assertions, { 101 })
		rig.fireHeartbeat()
		rig.setEvidence(resultEvidence(rig))
		rig.setLedgerCreateFailures(2)
		rig.fireHeartbeat()
		assertions.equal(#rig.ledgerCreateAttempts, 1)
		assertions.isFalse(rig.host:getMetrics().resultCreated)

		rig.lifecycle.shutdown()
		assertions.equal(#rig.ledgerCreateAttempts, 3)
		assertions.isTrue(rig.ledgerCreateAttempts[1] == rig.ledgerCreateAttempts[2])
		assertions.isTrue(rig.ledgerCreateAttempts[2] == rig.ledgerCreateAttempts[3])
		assertions.equal(#rig.ledgerCreates, 1)
		assertions.equal(#rig.ledgerFailures, 0)
		assertions.equal(#rig.rematchCalls, 0)
		assertions.isTrue(rig.host:getMetrics().resultCreated)
		assertions.isTrue(rig.host:getMetrics().cleaned)
	end),
	TestHarness.case("bounds and surfaces persistent shutdown durability failure", function(assertions)
		local rig = makeRig(assertions, { 101 })
		rig.fireHeartbeat()
		rig.setEvidence(resultEvidence(rig))
		rig.setLedgerFailure("STORE_UNAVAILABLE")
		rig.fireHeartbeat()

		local shutdownSucceeded, shutdownError = pcall(rig.lifecycle.shutdown)
		assertions.isFalse(shutdownSucceeded)
		assertions.isTrue(
			string.find(tostring(shutdownError), "[ATD_MATCH_TRAVEL_HOST][code=SHUTDOWN_DURABILITY_FAILED]", 1, true)
				~= nil
		)
		assertions.equal(#rig.ledgerCreateAttempts, 1 + MatchTravelHost.SHUTDOWN_DURABILITY_ATTEMPTS)
		assertions.equal(#rig.ledgerFailures, 0)
		assertions.isFalse(rig.host:getMetrics().cleaned)
		assertions.isNil(rig.terminalTickets[rig.ticket.ticketId])
		assertions.isNil(rig.clearedRoutes[101])

		rig.setLedgerFailure(nil)
		rig.lifecycle.shutdown()
		assertions.equal(#rig.ledgerCreates, 1)
		assertions.isTrue(rig.host:getMetrics().resultCreated)
		assertions.isTrue(rig.host:getMetrics().cleaned)
	end),
	TestHarness.case("durably records a late spectator as zero-Gold Ineligible", function(assertions)
		local rig = makeRig(assertions)
		rig.profileStates[202] = "Loading"
		rig.fireHeartbeat()
		rig.admissionKinds[202] = "LateSpectator"
		rig.profileStates[202] = "Ready"
		rig.advance(31)
		rig.fireHeartbeat()
		rig.setEvidence(resultEvidence(rig))
		rig.fireHeartbeat()
		assertions.equal(rig.playable.rewardViews[202].status, "Ineligible")
		assertions.equal(rig.playable.rewardViews[202].persistentGoldAwarded, 0)
		assertions.equal(rig.playable.rewardViews[202].battleCashEarned, 0)
		rig.advance(2)
		rig.fireHeartbeat()
		assertions.equal(rig.claimCounts[202], 1)
		rig.lifecycle.shutdown()
	end),
	TestHarness.case("returns a late spectator alone without moving active participants", function(assertions)
		local rig = makeRig(assertions)
		rig.profileStates[202] = "Loading"
		rig.fireHeartbeat()
		rig.admissionKinds[202] = "LateSpectator"
		rig.profileStates[202] = "Ready"
		rig.advance(31)
		rig.fireHeartbeat()
		local spectator = success(assertions, rig.host:getSnapshot(rig.players[2]))
		local returned = success(
			assertions,
			rig.host:requestReturn(rig.players[2], {
				transactionId = "transaction:spectator-return",
				matchId = spectator.matchId,
				observedRevision = spectator.revision,
			})
		)
		assertions.isTrue(returned.changed)
		assertions.equal(#rig.publicTeleports, 1)
		assertions.equal(#rig.publicTeleports[1].players, 1)
		assertions.equal(rig.publicTeleports[1].players[1], rig.players[2])
		assertions.equal(#rig.returnRecords.records[1].expectedUserIds, 1)
		assertions.equal(rig.returnRecords.records[1].expectedUserIds[1], 202)
		assertions.equal(success(assertions, rig.host:getSnapshot(rig.players[1])).returnStatus, "Idle")
		assertions.isNil(rig.clearedRoutes[101])
		rig.live[rig.players[2]] = false
		rig.fireRemoving(rig.players[2])
		assertions.isNil(rig.clearedRoutes[101])
		assertions.equal(rig.clearedRoutes[202], rig.ticket.matchId)
		assertions.isTrue(rig.returnedAdmissions[202])
		assertions.isNil(rig.returnedAdmissions[101])
		local _, _, committed = rig.transferCounts()
		assertions.equal(committed, 1)
		rig.lifecycle.shutdown()
	end),
	TestHarness.case(
		"retries departed route cleanup independently of an expired admission ticket",
		function(assertions)
			local rig = makeRig(assertions, { 101 })
			rig.fireHeartbeat()
			rig.setEvidence(resultEvidence(rig))
			rig.fireHeartbeat()
			local snapshot = success(assertions, rig.host:getSnapshot(rig.players[1]))
			assertions.isTrue(success(
				assertions,
				rig.host:requestReturn(rig.players[1], {
					transactionId = "transaction:return-expired-ticket-cleanup",
					matchId = snapshot.matchId,
					observedRevision = snapshot.revision,
				})
			).changed)
			rig.setRouteClearFailures(1)
			-- Admission durability may now be beyond the ten-minute ticket TTL; local
			-- Returned state remains authoritative while route cleanup is independent.
			rig.advance(601)
			rig.live[rig.players[1]] = false
			rig.fireRemoving(rig.players[1])
			assertions.isNil(rig.clearedRoutes[101])
			local _, _, committed = rig.transferCounts()
			assertions.equal(committed, 1)
			rig.fireHeartbeat()
			assertions.equal(rig.clearedRoutes[101], rig.ticket.matchId)
			rig.lifecycle.shutdown()
		end
	),
	TestHarness.case("retains a departed return until profile transfer commit succeeds", function(assertions)
		local rig = makeRig(assertions, { 101 })
		rig.fireHeartbeat()
		rig.setEvidence(resultEvidence(rig))
		rig.fireHeartbeat()
		local snapshot = success(assertions, rig.host:getSnapshot(rig.players[1]))
		assertions.isTrue(success(
			assertions,
			rig.host:requestReturn(rig.players[1], {
				transactionId = "transaction:return-commit-retry",
				matchId = snapshot.matchId,
				observedRevision = snapshot.revision,
			})
		).changed)
		rig.setCommitFailures(1)
		rig.live[rig.players[1]] = false
		rig.fireRemoving(rig.players[1])
		local _, _, committed = rig.transferCounts()
		assertions.equal(committed, 1)
		assertions.isNil(rig.clearedRoutes[101])

		rig.fireHeartbeat()
		local _, _, retriedCommits = rig.transferCounts()
		assertions.equal(retriedCommits, 2)
		assertions.equal(rig.clearedRoutes[101], rig.ticket.matchId)
		rig.lifecycle.shutdown()
	end),
	TestHarness.case(
		"blocks participant group return before a durable result and reconciles a partial late failure",
		function(assertions)
			local rig = makeRig(assertions)
			rig.fireHeartbeat()
			local active = success(assertions, rig.host:getSnapshot(rig.players[1]))
			local blocked = success(
				assertions,
				rig.host:requestReturn(rig.players[1], {
					transactionId = "transaction:return-before-result",
					matchId = active.matchId,
					observedRevision = active.revision,
				})
			)
			assertions.isFalse(blocked.changed)
			assertions.equal(#rig.publicTeleports, 0)
			assertions.equal(success(assertions, rig.host:getSnapshot(rig.players[2])).returnStatus, "Idle")

			rig.setEvidence(resultEvidence(rig))
			rig.fireHeartbeat()
			local results = success(assertions, rig.host:getSnapshot(rig.players[1]))
			local returned = success(
				assertions,
				rig.host:requestReturn(rig.players[1], {
					transactionId = "transaction:return-after-result",
					matchId = results.matchId,
					observedRevision = results.revision,
				})
			)
			assertions.isTrue(returned.changed)
			assertions.equal(#rig.publicTeleports, 1)
			assertions.equal(#rig.publicTeleports[1].players, 2)
			assertions.isNil(rig.clearedRoutes[101])
			assertions.isNil(rig.clearedRoutes[202])

			rig.live[rig.players[1]] = false
			rig.fireRemoving(rig.players[1])
			rig.emitInitFailure(rig.players[2], "Terminal")
			local prepared, rolledBack, committed = rig.transferCounts()
			assertions.equal(prepared, 2)
			assertions.equal(rolledBack, 1)
			assertions.equal(committed, 1)
			assertions.equal(rig.clearedRoutes[101], rig.ticket.matchId)
			assertions.isNil(rig.clearedRoutes[202])
			assertions.isTrue(rig.returnedAdmissions[101])
			assertions.isNil(rig.returnedAdmissions[202])
			assertions.equal(success(assertions, rig.host:getSnapshot(rig.players[2])).returnStatus, "Failed")
			assertions.isNil(rig.terminalReturns[rig.returnRecords.records[1].returnId])
			rig.lifecycle.shutdown()
		end
	),
	TestHarness.case(
		"reacquires every profile after all late public teleport initialization failures",
		function(assertions)
			local rig = makeRig(assertions, { 101 })
			rig.fireHeartbeat()
			rig.setEvidence(resultEvidence(rig))
			rig.fireHeartbeat()
			local snapshot = success(assertions, rig.host:getSnapshot(rig.players[1]))
			assertions.isTrue(success(
				assertions,
				rig.host:requestReturn(rig.players[1], {
					transactionId = "transaction:return-late-failure",
					matchId = snapshot.matchId,
					observedRevision = snapshot.revision,
				})
			).changed)
			rig.emitInitFailure(rig.players[1], "Terminal")
			local _, rolledBack, committed = rig.transferCounts()
			assertions.equal(rolledBack, 1)
			assertions.equal(committed, 0)
			assertions.isNil(rig.clearedRoutes[101])
			assertions.equal(success(assertions, rig.host:getSnapshot(rig.players[1])).returnStatus, "Failed")
			assertions.equal(rig.terminalReturns[rig.returnRecords.records[1].returnId], "TELEPORT_INIT_FAILED")
			rig.lifecycle.shutdown()
		end
	),
	TestHarness.case(
		"times out an initialized public return when the engine emits no terminal signal",
		function(assertions)
			local rig = makeRig(assertions, { 101 })
			rig.fireHeartbeat()
			rig.setEvidence(resultEvidence(rig))
			rig.fireHeartbeat()
			local snapshot = success(assertions, rig.host:getSnapshot(rig.players[1]))
			assertions.isTrue(success(
				assertions,
				rig.host:requestReturn(rig.players[1], {
					transactionId = "transaction:return-init-timeout",
					matchId = snapshot.matchId,
					observedRevision = snapshot.revision,
				})
			).changed)
			rig.advance(30)
			rig.fireHeartbeat()
			local _, rolledBack, committed = rig.transferCounts()
			assertions.equal(rolledBack, 1)
			assertions.equal(committed, 0)
			assertions.isNil(rig.clearedRoutes[101])
			assertions.equal(success(assertions, rig.host:getSnapshot(rig.players[1])).returnStatus, "Failed")
			assertions.equal(rig.terminalReturns[rig.returnRecords.records[1].returnId], "TELEPORT_INIT_FAILED")
			rig.lifecycle.shutdown()
		end
	),
	TestHarness.case("ignores a delayed failure from an older public return attempt", function(assertions)
		local rig = makeRig(assertions, { 101 })
		rig.fireHeartbeat()
		rig.setEvidence(resultEvidence(rig))
		rig.fireHeartbeat()
		local firstSnapshot = success(assertions, rig.host:getSnapshot(rig.players[1]))
		assertions.isTrue(success(
			assertions,
			rig.host:requestReturn(rig.players[1], {
				transactionId = "transaction:return-old-attempt",
				matchId = firstSnapshot.matchId,
				observedRevision = firstSnapshot.revision,
			})
		).changed)
		local oldRouting = rig.publicTeleports[1].routing
		rig.advance(30)
		rig.fireHeartbeat()
		local _, rollbackAfterOld = rig.transferCounts()

		local secondSnapshot = success(assertions, rig.host:getSnapshot(rig.players[1]))
		assertions.isTrue(success(
			assertions,
			rig.host:requestReturn(rig.players[1], {
				transactionId = "transaction:return-new-attempt",
				matchId = secondSnapshot.matchId,
				observedRevision = secondSnapshot.revision,
			})
		).changed)
		assertions.isTrue(rig.publicTeleports[2].routing.returnId ~= oldRouting.returnId)
		rig.emitInitFailure(rig.players[1], "Terminal", oldRouting)
		local _, rollbackAfterDelayed = rig.transferCounts()
		assertions.equal(rollbackAfterDelayed, rollbackAfterOld)
		assertions.equal(success(assertions, rig.host:getSnapshot(rig.players[1])).returnStatus, "Teleporting")

		rig.emitInitFailure(rig.players[1], "Terminal", rig.publicTeleports[2].routing)
		local _, rollbackAfterCurrent = rig.transferCounts()
		assertions.equal(rollbackAfterCurrent, rollbackAfterOld + 1)
		assertions.equal(success(assertions, rig.host:getSnapshot(rig.players[1])).returnStatus, "Failed")
		rig.lifecycle.shutdown()
	end),
	TestHarness.case(
		"presents explicit Failed views for malformed evidence and terminal ledger errors",
		function(assertions)
			local malformed = makeRig(assertions, { 101 })
			malformed.fireHeartbeat()
			local wrong = resultEvidence(malformed)
			wrong.matchId = "match:wrong-result"
			malformed.setEvidence(wrong)
			malformed.fireHeartbeat()
			assertions.equal(malformed.playable.rewardViews[101].status, "Failed")
			assertions.equal(malformed.playable.rewardViews[101].persistentGoldAwarded, 0)
			assertions.equal(malformed.playable.rewardViews[101].battleCashEarned, 50)
			assertions.isTrue(malformed.host:getMetrics().resultFailed)
			malformed.lifecycle.shutdown()

			local terminalStore = makeRig(assertions, { 101 })
			terminalStore.fireHeartbeat()
			terminalStore.setEvidence(resultEvidence(terminalStore))
			terminalStore.setLedgerFailure("RESULT_CONFLICT")
			terminalStore.fireHeartbeat()
			assertions.equal(terminalStore.playable.rewardViews[101].status, "Failed")
			assertions.equal(terminalStore.playable.rewardViews[101].reason, "RESULT_LEDGER_FAILED")
			terminalStore.lifecycle.shutdown()
		end
	),
	TestHarness.case(
		"blocks participant return until a terminal result failure is durably recorded",
		function(assertions)
			local rig = makeRig(assertions, { 101 })
			rig.fireHeartbeat()
			local wrong = resultEvidence(rig)
			wrong.matchId = "match:wrong-result"
			rig.setEvidence(wrong)
			rig.setLedgerMarkFailure("STORE_UNAVAILABLE")
			rig.fireHeartbeat()
			assertions.isFalse(rig.host:getMetrics().resultFailed)
			assertions.equal(rig.playable.rewardViews[101].status, "Pending")
			local before = success(assertions, rig.host:getSnapshot(rig.players[1]))
			local blocked = success(
				assertions,
				rig.host:requestReturn(rig.players[1], {
					transactionId = "transaction:return-before-failure-tombstone",
					matchId = before.matchId,
					observedRevision = before.revision,
				})
			)
			assertions.isFalse(blocked.changed)
			assertions.equal(#rig.publicTeleports, 0)

			rig.setLedgerMarkFailure(nil)
			rig.advance(1)
			rig.fireHeartbeat()
			assertions.isTrue(rig.host:getMetrics().resultFailed)
			assertions.equal(#rig.ledgerFailures, 1)
			assertions.equal(rig.playable.rewardViews[101].status, "Failed")
			local after = success(assertions, rig.host:getSnapshot(rig.players[1]))
			local returned = success(
				assertions,
				rig.host:requestReturn(rig.players[1], {
					transactionId = "transaction:return-after-failure-tombstone",
					matchId = after.matchId,
					observedRevision = after.revision,
				})
			)
			assertions.isTrue(returned.changed)
			assertions.equal(#rig.publicTeleports, 1)
			rig.lifecycle.shutdown()
		end
	),
	TestHarness.case(
		"rolls profiles back on failed return and commits only after bounded public travel",
		function(assertions)
			local rig = makeRig(assertions, { 101 })
			rig.fireHeartbeat()
			rig.setEvidence(resultEvidence(rig))
			rig.fireHeartbeat()
			rig.setTeleportFailure(true)
			local snapshot = success(assertions, rig.host:getSnapshot(rig.players[1]))
			local failed = success(
				assertions,
				rig.host:requestReturn(rig.players[1], {
					transactionId = "transaction:return-failed",
					matchId = snapshot.matchId,
					observedRevision = snapshot.revision,
				})
			)
			assertions.isFalse(failed.changed)
			assertions.equal(failed.snapshot.returnStatus, "Failed")
			assertions.equal(failed.snapshot.publicFailure, "TELEPORT_FAILED")
			local prepared, rolledBack, committed = rig.transferCounts()
			assertions.equal(prepared, 1)
			assertions.equal(rolledBack, 1)
			assertions.equal(committed, 0)
			assertions.isNil(rig.clearedRoutes[101])

			rig.setTeleportFailure(false)
			local current = success(assertions, rig.host:getSnapshot(rig.players[1]))
			local returned = success(
				assertions,
				rig.host:requestReturn(rig.players[1], {
					transactionId = "transaction:return-success",
					matchId = current.matchId,
					observedRevision = current.revision,
				})
			)
			if not returned.changed then
				error(`expected successful return, got {returned.snapshot.publicFailure or "unknown"}`, 0)
			end
			assertions.isTrue(returned.changed)
			assertions.equal(returned.snapshot.returnStatus, "Teleporting")
			assertions.equal(#rig.returnRecords.records, 2)
			assertions.equal(#rig.publicTeleports, 2)
			assertions.equal(rig.publicTeleports[2].routing.kind, "Return")
			assertions.isNil((rig.publicTeleports[2].routing :: any).accessCode)
			assertions.isNil(rig.clearedRoutes[101])
			prepared, rolledBack, committed = rig.transferCounts()
			assertions.equal(prepared, 2)
			assertions.equal(rolledBack, 1)
			assertions.equal(committed, 0)
			rig.live[rig.players[1]] = false
			rig.fireRemoving(rig.players[1])
			assertions.equal(rig.clearedRoutes[101], rig.ticket.matchId)
			prepared, rolledBack, committed = rig.transferCounts()
			assertions.equal(committed, 1)
			rig.lifecycle.shutdown()
		end
	),
	TestHarness.case(
		"retains and retries a failed return rollback before allowing another travel",
		function(assertions)
			local rig = makeRig(assertions, { 101 })
			rig.fireHeartbeat()
			rig.setEvidence(resultEvidence(rig))
			rig.fireHeartbeat()
			rig.setTeleportFailure(true)
			rig.setRollbackFailures(1)
			local snapshot = success(assertions, rig.host:getSnapshot(rig.players[1]))
			local failed = success(
				assertions,
				rig.host:requestReturn(rig.players[1], {
					transactionId = "transaction:return-retained-rollback",
					matchId = snapshot.matchId,
					observedRevision = snapshot.revision,
				})
			)
			assertions.isFalse(failed.changed)
			local _, rollbackAttempts = rig.transferCounts()
			assertions.equal(rollbackAttempts, 1)
			rig.fireHeartbeat()
			_, rollbackAttempts = rig.transferCounts()
			assertions.equal(rollbackAttempts, 2)
			rig.setTeleportFailure(false)
			local recovered = success(assertions, rig.host:getSnapshot(rig.players[1]))
			local returned = success(
				assertions,
				rig.host:requestReturn(rig.players[1], {
					transactionId = "transaction:return-after-retained-rollback",
					matchId = recovered.matchId,
					observedRevision = recovered.revision,
				})
			)
			assertions.isTrue(returned.changed)
			rig.lifecycle.shutdown()
		end
	),
	TestHarness.case("delegates exactly one fresh rematch only after unanimous active votes", function(assertions)
		local rig = makeRig(assertions)
		rig.fireHeartbeat()
		rig.setEvidence(resultEvidence(rig))
		rig.fireHeartbeat()
		local first = success(assertions, rig.host:getSnapshot(rig.players[1]))
		local firstVote = success(
			assertions,
			rig.host:voteRematch(rig.players[1], {
				transactionId = "transaction:rematch-one",
				matchId = first.matchId,
				observedRevision = first.revision,
				observedRematchRevision = first.rematch.revision,
				approve = true,
			})
		)
		assertions.equal(#rig.rematchCalls, 0)
		local second = success(assertions, rig.host:getSnapshot(rig.players[2]))
		success(
			assertions,
			rig.host:voteRematch(rig.players[2], {
				transactionId = "transaction:rematch-two",
				matchId = second.matchId,
				observedRevision = second.revision,
				observedRematchRevision = firstVote.snapshot.rematch.revision,
				approve = true,
			})
		)
		assertions.equal(#rig.rematchCalls, 1)
		assertions.equal(rig.rematchCalls[1].userIds[1], 101)
		assertions.equal(rig.rematchCalls[1].userIds[2], 202)
		rig.lifecycle.shutdown()
	end),
	TestHarness.case(
		"does not create a reduced-roster rematch after an admitted participant disconnects",
		function(assertions)
			local rig = makeRig(assertions)
			rig.fireHeartbeat()
			rig.live[rig.players[2]] = false
			rig.fireRemoving(rig.players[2])
			rig.setEvidence(resultEvidence(rig))
			rig.fireHeartbeat()
			local snapshot = success(assertions, rig.host:getSnapshot(rig.players[1]))
			assertions.isNil(snapshot.rematch)
			assertions.equal(#rig.rematchCalls, 0)
			rig.lifecycle.shutdown()
		end
	),
	TestHarness.case("fails malformed join data through the safe public-return seam", function(assertions)
		local rig = makeRig(assertions, { 101 })
		local malformed = { name = "Malformed" }
		rig.ids[malformed] = 999
		rig.live[malformed] = true
		rig.routing[malformed] = { ticketId = rig.ticket.ticketId, accessCode = "must-never-copy" }
		table.insert(rig.players, malformed)
		rig.fireAdded(malformed)
		assertions.equal(#rig.rejected, 1)
		assertions.equal(rig.rejected[1].reason, "MALFORMED_JOIN_DATA")
		assertions.isNil((rig.rejected[1] :: any).accessCode)
		rig.lifecycle.shutdown()
	end),
	TestHarness.case(
		"keeps active routes through Results and clears them only at terminal cleanup",
		function(assertions)
			local rig = makeRig(assertions)
			rig.fireHeartbeat()
			rig.setEvidence(resultEvidence(rig))
			rig.fireHeartbeat()
			assertions.isNil(rig.clearedRoutes[101])
			assertions.isNil(rig.terminalTickets[rig.ticket.ticketId])
			rig.lifecycle.shutdown()
			assertions.equal(rig.clearedRoutes[101], rig.ticket.matchId)
			assertions.equal(rig.clearedRoutes[202], rig.ticket.matchId)
			assertions.equal(rig.terminalTickets[rig.ticket.ticketId], "MATCH_TERMINAL_CLEANUP")
			assertions.equal(rig.dependencyCleanupCount(), 1)
		end
	),
	TestHarness.case("durably fails an unfinished result intent before terminal cleanup", function(assertions)
		local rig = makeRig(assertions, { 101 })
		rig.fireHeartbeat()
		assertions.equal(#rig.ledgerFailures, 0)
		assertions.isTrue(rig.host:cleanup().ok)
		assertions.equal(#rig.ledgerFailures, 1)
		assertions.equal(rig.ledgerFailures[1].reason, "MATCH_TERMINAL_CLEANUP")
		assertions.equal(rig.terminalTickets[rig.ticket.ticketId], "MATCH_TERMINAL_CLEANUP")
		assertions.isTrue(rig.host:getMetrics().resultFailed)
	end),
	TestHarness.case("keeps terminal cleanup fail-closed until the result ledger recovers", function(assertions)
		local rig = makeRig(assertions, { 101 })
		rig.fireHeartbeat()
		rig.setLedgerMarkFailure("STORE_UNAVAILABLE")
		local unavailable = rig.host:cleanup()
		assertions.isFalse(unavailable.ok)
		assertions.equal(unavailable.error.code, "UNAVAILABLE")
		assertions.isFalse(rig.host:getMetrics().cleaned)
		assertions.isNil(rig.terminalTickets[rig.ticket.ticketId])
		assertions.isNil(rig.clearedRoutes[101])

		rig.setLedgerMarkFailure(nil)
		assertions.isTrue(rig.host:cleanup().ok)
		assertions.equal(#rig.ledgerFailures, 1)
		assertions.equal(rig.ledgerFailures[1].reason, "MATCH_TERMINAL_CLEANUP")
		assertions.equal(rig.terminalTickets[rig.ticket.ticketId], "MATCH_TERMINAL_CLEANUP")
	end),
})
