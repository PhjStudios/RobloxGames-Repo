--!strict

local ServerStorage = game:GetService("ServerStorage")

local PartyService = require(ServerStorage.AutomatedTests.ProductionServerLobbyParty.PartyService)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

type Assertions = TestHarness.Assertions

type Rig = {
	service: PartyService.Service,
	now: number,
	present: { [number]: boolean },
	permissions: { [string]: boolean },
	changes: { PartyService.Change },
}

local function success(assertions: Assertions, value: any): any
	assertions.isTrue(value.ok)
	if not value.ok then
		error("expected party operation to succeed", 0)
	end
	return value.value
end

local function permissionKey(left: number, right: number): string
	return `{left}:{right}`
end

local function makeRig(assertions: Assertions): Rig
	local rig = {
		service = nil :: any,
		now = 100,
		present = { [10] = true, [20] = true, [30] = true, [40] = true, [50] = true },
		permissions = {},
		changes = {},
	} :: Rig
	for _, target in { 20, 30, 40, 50 } do
		rig.permissions[permissionKey(10, target)] = true
		rig.permissions[permissionKey(20, target)] = true
	end
	local partySequence = 0
	local invitationSequence = 0
	rig.service = success(
		assertions,
		PartyService.new({
			clock = function(): number
				return rig.now
			end,
			makePartyId = function(): string
				partySequence += 1
				return `party:p{partySequence}`
			end,
			makeInvitationId = function(): string
				invitationSequence += 1
				return `invitation:i{invitationSequence}`
			end,
			isPresent = function(userId: number): boolean
				return rig.present[userId] == true
			end,
			canInvite = function(inviterUserId: number, targetUserId: number): boolean
				return rig.permissions[permissionKey(inviterUserId, targetUserId)] == true
			end,
			isProfileReady = function(userId: number): boolean
				return userId ~= 50
			end,
			getQueueState = function(_members: { number }): string
				return "Idle"
			end,
			onChanged = function(change: PartyService.Change)
				table.insert(rig.changes, change)
			end,
			invitationLifetimeSeconds = 30,
		})
	)
	return rig
end

local function create(assertions: Assertions, rig: Rig, userId: number, transactionId: string): any
	return success(
		assertions,
		rig.service:create(userId, {
			transactionId = transactionId,
			expectedRevision = 0,
			privacy = "InviteOnly",
		})
	)
end

local function invite(assertions: Assertions, rig: Rig, revision: number, targetUserId: number, suffix: string): any
	return success(
		assertions,
		rig.service:invite(10, {
			transactionId = `transaction:invite-{suffix}`,
			expectedRevision = revision,
			targetUserId = targetUserId,
		})
	)
end

local function accept(assertions: Assertions, rig: Rig, userId: number, suffix: string): any
	local incoming = success(assertions, rig.service:getSnapshot(userId)).incomingInvitations[1]
	assertions.isNotNil(incoming)
	return success(
		assertions,
		rig.service:accept(userId, {
			transactionId = `transaction:accept-{suffix}`,
			expectedRevision = incoming.partyRevision,
			invitationId = incoming.invitationId,
		})
	)
end

return TestHarness.suite("ephemeral same-server party service", {
	TestHarness.case("creates invites accepts replays and orders members authoritatively", function(assertions)
		local rig = makeRig(assertions)
		local created = create(assertions, rig, 10, "transaction:create-main")
		assertions.equal(created.partyRevision, 1)
		assertions.equal(created.reason, "PartyCreated")
		assertions.equal(#created.snapshot.party.members, 1)
		local invited = invite(assertions, rig, 1, 20, "twenty")
		assertions.equal(invited.reason, "InvitationSent")
		assertions.equal(invited.partyRevision, 2)
		assertions.equal(invited.snapshot.party.pendingInvitationCount, 1)
		invite(assertions, rig, 2, 30, "thirty-pending")
		local refreshedInvite = success(assertions, rig.service:getSnapshot(20)).incomingInvitations[1]
		assertions.equal(refreshedInvite.partyRevision, 3)
		local accepted = accept(assertions, rig, 20, "twenty")
		assertions.equal(accepted.reason, "InvitationAccepted")
		assertions.equal(accepted.partyRevision, 4)
		assertions.equal(#accepted.snapshot.party.members, 2)
		assertions.equal(accepted.snapshot.party.members[1].userId, 10)
		assertions.equal(accepted.snapshot.party.members[2].userId, 20)

		local incomingId = invited.snapshot.party.partyId
		assertions.equal(accepted.snapshot.party.partyId, incomingId)
		local replayed = rig.service:accept(20, {
			transactionId = "transaction:accept-twenty",
			expectedRevision = 3,
			invitationId = "invitation:i1",
		})
		assertions.isTrue(replayed.ok)
		if replayed.ok then
			assertions.equal(replayed.value, accepted)
		end
		assertions.equal(rig.service:getMetrics().memberCount, 2)
		assertions.isTrue(#rig.changes >= 3)
	end),

	TestHarness.case("serializes capacity leadership kick and disconnect cleanup", function(assertions)
		local rig = makeRig(assertions)
		create(assertions, rig, 10, "transaction:create-capacity")
		invite(assertions, rig, 1, 20, "a")
		accept(assertions, rig, 20, "a")
		invite(assertions, rig, 3, 30, "b")
		accept(assertions, rig, 30, "b")
		invite(assertions, rig, 5, 40, "c")
		local full = accept(assertions, rig, 40, "c")
		assertions.equal(#full.snapshot.party.members, 4)

		local rejected = rig.service:invite(10, {
			transactionId = "transaction:invite-full",
			expectedRevision = full.partyRevision,
			targetUserId = 50,
		})
		assertions.isFalse(rejected.ok)
		if not rejected.ok then
			assertions.equal(rejected.error.code, "PARTY_FULL")
		end

		local transfer = success(
			assertions,
			rig.service:transferLeadership(10, {
				transactionId = "transaction:transfer",
				expectedRevision = full.partyRevision,
				targetUserId = 20,
			})
		)
		assertions.equal(transfer.snapshot.party.leaderUserId, 20)
		assertions.equal(transfer.snapshot.party.members[1].userId, 20)
		local oldLeaderKick = rig.service:kick(10, {
			transactionId = "transaction:old-leader-kick",
			expectedRevision = transfer.partyRevision,
			targetUserId = 30,
		})
		assertions.isFalse(oldLeaderKick.ok)
		local kicked = success(
			assertions,
			rig.service:kick(20, {
				transactionId = "transaction:new-leader-kick",
				expectedRevision = transfer.partyRevision,
				targetUserId = 30,
			})
		)
		assertions.equal(#kicked.snapshot.party.members, 3)
		assertions.isNil(rig.service:getPartyForUser(30))

		assertions.isTrue(rig.service:removePlayer(20).ok)
		local afterDisconnect = success(assertions, rig.service:getSnapshot(10))
		assertions.equal(afterDisconnect.party.leaderUserId, 10)
		assertions.equal(#afterDisconnect.party.members, 2)
	end),

	TestHarness.case("expires invitations denies permission and bounds mutation receipts", function(assertions)
		local rig = makeRig(assertions)
		local created = create(assertions, rig, 10, "transaction:create-expiry")
		rig.permissions[permissionKey(10, 50)] = false
		local denied = rig.service:invite(10, {
			transactionId = "transaction:permission-denied",
			expectedRevision = created.partyRevision,
			targetUserId = 50,
		})
		assertions.isFalse(denied.ok)
		if not denied.ok then
			assertions.equal(denied.error.code, "PERMISSION_DENIED")
		end
		invite(assertions, rig, created.partyRevision, 20, "expires")
		rig.now = 131
		local target = success(assertions, rig.service:getSnapshot(20))
		assertions.equal(#target.incomingInvitations, 0)

		local current = success(assertions, rig.service:getSnapshot(10))
		for index = 1, 40 do
			local privacy = if index % 2 == 0 then "InviteOnly" else "FriendsOnly"
			local updated = success(
				assertions,
				rig.service:setPrivacy(10, {
					transactionId = `transaction:privacy-{index}`,
					expectedRevision = current.party.revision,
					privacy = privacy,
				})
			)
			current = updated.snapshot
		end
		assertions.equal(rig.service:getMetrics().receiptCount, 32)
		local conflict = rig.service:setPrivacy(10, {
			transactionId = "transaction:privacy-40",
			expectedRevision = current.party.revision,
			privacy = "FriendsOnly",
		})
		assertions.isFalse(conflict.ok)
		if not conflict.ok then
			assertions.equal(conflict.error.code, "TRANSACTION_CONFLICT")
		end
		assertions.isTrue(rig.service:cleanup().ok)
		assertions.equal(rig.service:getMetrics().partyCount, 0)
	end),

	TestHarness.case(
		"emits bounded deterministic decline leave disband departure and shutdown reasons",
		function(assertions)
			local declinedRig = makeRig(assertions)
			create(assertions, declinedRig, 10, "transaction:create-decline")
			local invitation = invite(assertions, declinedRig, 1, 20, "decline")
			local incoming = success(assertions, declinedRig.service:getSnapshot(20)).incomingInvitations[1]
			local declined = success(
				assertions,
				declinedRig.service:decline(20, {
					transactionId = "transaction:decline-reason",
					expectedRevision = incoming.partyRevision,
					invitationId = incoming.invitationId,
				})
			)
			assertions.equal(declined.reason, "InvitationDeclined")
			local beforeDisband = success(assertions, declinedRig.service:getSnapshot(10))
			local disbanded = success(
				assertions,
				declinedRig.service:disband(10, {
					transactionId = "transaction:disband-reason",
					expectedRevision = beforeDisband.party.revision,
				})
			)
			assertions.equal(disbanded.reason, "LeaderDisbanded")
			assertions.equal(declinedRig.changes[#declinedRig.changes].reason, "LeaderDisbanded")
			assertions.isTrue(invitation.changed)

			local leaveRig = makeRig(assertions)
			local created = create(assertions, leaveRig, 10, "transaction:create-leave")
			local left = success(
				assertions,
				leaveRig.service:leave(10, {
					transactionId = "transaction:leave-reason",
					expectedRevision = created.partyRevision,
				})
			)
			assertions.equal(left.reason, "LastMemberLeft")

			local departureRig = makeRig(assertions)
			create(assertions, departureRig, 10, "transaction:create-departure")
			assertions.isTrue(success(assertions, departureRig.service:removePlayer(10, "ServerLeave")))
			assertions.equal(departureRig.changes[#departureRig.changes].reason, "MemberServerLeft")

			local shutdownRig = makeRig(assertions)
			create(assertions, shutdownRig, 10, "transaction:create-shutdown")
			assertions.isTrue(success(assertions, shutdownRig.service:cleanup()))
			assertions.equal(shutdownRig.changes[#shutdownRig.changes].reason, "ServerShutdown")
		end
	),

	TestHarness.case("reconstructs only a complete ready prior roster with its valid leader", function(assertions)
		local rig = makeRig(assertions)
		local reconstructed = success(assertions, rig.service:reconstruct(20, { 10, 20, 30 }))
		assertions.equal(reconstructed.leaderUserId, 20)
		assertions.equal(reconstructed.members[1], 20)
		assertions.equal(reconstructed.members[2], 10)
		assertions.equal(reconstructed.members[3], 30)
		local memberParty = rig.service:getPartyForUser(10)
		assertions.isNotNil(memberParty)
		if memberParty ~= nil then
			assertions.equal(memberParty.partyId, reconstructed.partyId)
		end
		assertions.equal(rig.service:getMetrics().receiptCount, 0)

		local duplicate = rig.service:reconstruct(20, { 20, 30 })
		assertions.isFalse(duplicate.ok)
		if not duplicate.ok then
			assertions.equal(duplicate.error.code, "RECONSTRUCTION_UNAVAILABLE")
		end
		local notReadyRig = makeRig(assertions)
		local notReady = notReadyRig.service:reconstruct(10, { 10, 50 })
		assertions.isFalse(notReady.ok)
		assertions.isNil(notReadyRig.service:getPartyForUser(10))
	end),
})
