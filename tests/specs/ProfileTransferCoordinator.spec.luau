--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local ProfileTransferCoordinator = require(script.Parent.Parent.ProductionServerTravel.ProfileTransferCoordinator)
local Result = require(ReplicatedStorage.Shared.util.Result)

local function owner(): (any, any)
	local state = {
		owned = { [101] = true, [202] = true },
		gated = {},
		loadoutRevision = { [101] = 101, [202] = 202 },
		failBeginUserId = nil,
		failReleaseUserId = nil,
		failLoadUserId = nil,
		onRelease = nil,
		log = {},
	} :: any
	local adapter = {}
	function adapter:beginTransfer(userId)
		table.insert(state.log, `begin:{userId}`)
		if state.owned[userId] ~= true or state.gated[userId] or state.failBeginUserId == userId then
			return Result.err({ code = "NOT_READY" })
		end
		state.gated[userId] = true
		return Result.ok({ userId = userId, loadoutRevision = state.loadoutRevision[userId] })
	end
	function adapter:cancelTransfer(userId)
		table.insert(state.log, `cancel:{userId}`)
		if not state.gated[userId] or state.owned[userId] ~= true then
			return Result.err({ code = "INVALID_STATE" })
		end
		state.gated[userId] = nil
		return Result.ok(true)
	end
	function adapter:release(userId)
		table.insert(state.log, `release:{userId}`)
		if state.onRelease ~= nil then
			state.onRelease(userId)
		end
		if state.failReleaseUserId == userId or state.owned[userId] ~= true then
			return if state.failReleaseUserId == userId
				then Result.err({ code = "RELEASE_FAILED" })
				else Result.ok(false)
		end
		state.owned[userId] = false
		state.gated[userId] = nil
		return Result.ok(true)
	end
	function adapter:load(userId)
		table.insert(state.log, `load:{userId}`)
		if state.failLoadUserId == userId then
			return Result.err({ code = "LOAD_FAILED" })
		end
		state.owned[userId] = true
		state.gated[userId] = nil
		return Result.ok(true)
	end
	return adapter, state
end

local function service(assertions, adapter, isPresent): any
	local created = ProfileTransferCoordinator.new(adapter, {
		isPresent = isPresent or function(_userId)
			return true
		end,
		snapshotLoadout = function(userId, profile)
			return {
				userId = userId,
				revision = profile.loadoutRevision,
				slots = { { slot = 1, towerId = `tower:{userId}` } },
			}
		end,
	})
	assertions.isTrue(created.ok)
	return created.value
end

return TestHarness.suite("atomic profile ownership transfer", {
	TestHarness.case("closes every mutation gate before saving and releasing the roster", function(assertions)
		local adapter, state = owner()
		local serviceValue = service(assertions, adapter)
		local prepared = serviceValue:prepare({ 101, 202 })
		assertions.isTrue(prepared.ok)
		assertions.isTrue(table.isfrozen(prepared.value.orderedUserIds))
		assertions.isTrue(table.isfrozen(prepared.value.loadouts))
		assertions.isTrue(table.isfrozen(prepared.value.loadouts[1]))
		assertions.isTrue(table.isfrozen(prepared.value.loadouts[1].slots))
		assertions.equal(state.log[1], "begin:101")
		assertions.equal(state.log[2], "begin:202")
		assertions.equal(state.log[3], "release:101")
		assertions.equal(state.log[4], "release:202")
		assertions.isFalse(state.owned[101])
		assertions.isFalse(state.owned[202])
		assertions.isTrue(serviceValue:commit(prepared.value.handle).value)
		assertions.isFalse(state.owned[101])
	end),
	TestHarness.case("reacquires earlier releases when a later release fails", function(assertions)
		local adapter, state = owner()
		state.failReleaseUserId = 202
		local prepared = service(assertions, adapter):prepare({ 101, 202 })
		assertions.isFalse(prepared.ok)
		assertions.equal(prepared.error.code, "RELEASE_FAILED")
		assertions.equal(state.log[#state.log], "load:101")
		assertions.equal(state.log[#state.log - 1], "load:202")
		assertions.isTrue(state.owned[101])
		assertions.isTrue(state.owned[202])
	end),
	TestHarness.case("settles a departed earlier release without reacquiring an orphan lease", function(assertions)
		local adapter, state = owner()
		local present = { [101] = true, [202] = true }
		state.failReleaseUserId = 202
		state.onRelease = function(userId)
			if userId == 101 then
				present[userId] = nil
			end
		end
		local serviceValue = service(assertions, adapter, function(userId)
			return present[userId] == true
		end)
		local prepared = serviceValue:prepare({ 101, 202 })
		assertions.isFalse(prepared.ok)
		assertions.equal(prepared.error.code, "RELEASE_FAILED")
		assertions.isNil(table.find(state.log, "load:101"))
		assertions.equal(state.log[#state.log], "release:101")
		assertions.isFalse(state.owned[101])
		assertions.isNil(state.gated[101])
		assertions.isTrue(state.owned[202])
		assertions.equal(serviceValue:step(), 0)
	end),
	TestHarness.case("settles ownership when presence changes during reacquisition", function(assertions)
		local adapter, state = owner()
		local checks = 0
		local serviceValue = service(assertions, adapter, function(userId)
			if userId ~= 202 then
				return true
			end
			checks += 1
			return checks == 1
		end)
		local prepared = serviceValue:prepare({ 101, 202 })
		assertions.isTrue(prepared.ok)
		assertions.isTrue(serviceValue:rollback(prepared.value.handle).ok)
		assertions.isNil(table.find(state.log, "load:202", 6))
		assertions.isFalse(state.owned[202])
		assertions.equal(serviceValue:step(), 0)
	end),
	TestHarness.case("settles a committed lease when its player departs while load yields", function(assertions)
		local adapter, state = owner()
		state.owned[101] = false
		local present = true
		local originalLoad = adapter.load
		function adapter:load(userId)
			local loaded = originalLoad(self, userId)
			present = false
			return loaded
		end
		local serviceValue = service(assertions, adapter, function(userId)
			return userId == 101 and present
		end)
		assertions.isTrue(serviceValue:recoverCommitted(101).ok)
		assertions.equal(state.log[1], "load:101")
		assertions.equal(state.log[2], "release:101")
		assertions.isFalse(state.owned[101])
		assertions.isNil(state.gated[101])
	end),
	TestHarness.case("retains an ambiguous release until a later recovery step succeeds", function(assertions)
		local adapter, state = owner()
		state.failReleaseUserId = 202
		state.failLoadUserId = 202
		local serviceValue = service(assertions, adapter)
		local prepared = serviceValue:prepare({ 101, 202 })
		assertions.isFalse(prepared.ok)
		assertions.equal(prepared.error.code, "ROLLBACK_FAILED")
		state.failLoadUserId = nil
		assertions.equal(serviceValue:step(), 1)
		assertions.isTrue(state.owned[101])
		assertions.isTrue(state.owned[202])
	end),
	TestHarness.case("reopens earlier mutation gates when another profile cannot freeze", function(assertions)
		local adapter, state = owner()
		state.failBeginUserId = 202
		local prepared = service(assertions, adapter):prepare({ 101, 202 })
		assertions.isFalse(prepared.ok)
		assertions.equal(prepared.error.code, "PROFILE_NOT_READY")
		assertions.equal(state.log[3], "cancel:101")
		assertions.isNil(state.log[4])
		assertions.isTrue(state.owned[101])
		assertions.isTrue(state.owned[202])
		assertions.isNil(state.gated[101])
	end),
	TestHarness.case(
		"rejects a mutation interleaved with release and preserves the frozen revision",
		function(assertions)
			local adapter, state = owner()
			local mutationAccepted = false
			state.onRelease = function(userId)
				if userId == 101 and not state.gated[202] then
					state.loadoutRevision[202] += 1
					mutationAccepted = true
				end
			end
			local prepared = service(assertions, adapter):prepare({ 101, 202 })
			assertions.isTrue(prepared.ok)
			assertions.isFalse(mutationAccepted)
			assertions.equal(prepared.value.loadouts[2].revision, 202)
		end
	),
	TestHarness.case("rolls back every released profile in reverse order", function(assertions)
		local adapter, state = owner()
		local serviceValue = service(assertions, adapter)
		local prepared = serviceValue:prepare({ 101, 202 }).value
		assertions.isTrue(serviceValue:rollback(prepared.handle).value)
		assertions.equal(state.log[5], "load:202")
		assertions.equal(state.log[6], "load:101")
		assertions.isTrue(state.owned[101])
		assertions.isTrue(state.owned[202])
	end),
	TestHarness.case("keeps rollback idempotent after background recovery completes", function(assertions)
		local adapter, state = owner()
		local serviceValue = service(assertions, adapter)
		local handle = serviceValue:prepare({ 101, 202 }).value.handle
		state.failLoadUserId = 202
		assertions.equal(serviceValue:rollback(handle).error.code, "ROLLBACK_FAILED")
		state.failLoadUserId = nil
		assertions.equal(serviceValue:step(), 1)
		assertions.isFalse(serviceValue:rollback(handle).value)
		assertions.isTrue(state.owned[101])
		assertions.isTrue(state.owned[202])
	end),
	TestHarness.case("cleanup safely rolls back an uncommitted transfer", function(assertions)
		local adapter, state = owner()
		local serviceValue = service(assertions, adapter)
		assertions.isTrue(serviceValue:prepare({ 101, 202 }).ok)
		assertions.isTrue(serviceValue:cleanup().value)
		assertions.isTrue(state.owned[101])
		assertions.isTrue(state.owned[202])
		assertions.equal(serviceValue:prepare({ 101 }).error.code, "CLEANED")
	end),
	TestHarness.case(
		"supports a bounded ownership-release marker without validating an attacking loadout",
		function(assertions)
			local adapter, state = owner()
			function adapter:beginTransfer(userId)
				table.insert(state.log, `begin:{userId}`)
				state.gated[userId] = true
				return Result.ok({ userId = userId, equippedUnitIds = {} })
			end
			local created = ProfileTransferCoordinator.new(adapter, {
				isPresent = function(_userId)
					return true
				end,
				snapshotLoadout = function(userId, _profile)
					return { userId = userId, ownershipRelease = true }
				end,
			})
			assertions.isTrue(created.ok)
			local prepared = created.value:prepare({ 101 })
			assertions.isTrue(prepared.ok)
			assertions.isTrue(prepared.value.loadouts[1].ownershipRelease)
			assertions.isNil((prepared.value.loadouts[1] :: any).slots)
			assertions.isTrue(created.value:commit(prepared.value.handle).ok)
			assertions.isFalse(state.owned[101])
		end
	),
})
