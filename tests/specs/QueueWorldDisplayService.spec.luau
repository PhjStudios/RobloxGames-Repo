--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local QueueWorldDisplayService = require(script.Parent.Parent.ProductionServerLobbyQueue.QueueWorldDisplayService)

local function snapshot(members: { any }): any
	local enrollment = if #members == 0
		then {}
		else {
			{
				sequence = 1,
				kind = "Solo",
				leaderUserId = members[1].userId,
				userIds = { members[1].userId },
				source = "UI",
			},
		}
	return {
		version = 1,
		queueId = "queue:backyard-squad",
		revision = 1,
		state = "Open",
		captainUserId = if #members == 0 then nil else members[1].userId,
		configuration = {
			mapId = "map:phase07-graybox",
			difficultyId = "difficulty:local",
			privacy = "Public",
			maxPlayers = 4,
		},
		members = members,
		enrollments = enrollment,
		canStart = #members > 0 and members[1].readiness == "Ready",
	}
end

return TestHarness.suite("read-only queue world display", {
	TestHarness.case("renders bounded state portraits and clears empty residue", function(assertions)
		local part = Instance.new("Part")
		part.Name = "QueueDisplayAnchor"
		local result = QueueWorldDisplayService.new({ {
			queueId = "queue:backyard-squad",
			adornee = part,
		} })
		assertions.isTrue(result.ok)
		if not result.ok then
			part:Destroy()
			return
		end
		local service = result.value
		assertions.isTrue(service:update(
			"queue:backyard-squad",
			snapshot({ {
				userId = 101,
				order = 1,
				isCaptain = true,
				readiness = "Ready",
			} })
		).ok)
		assertions.equal(service:getMetrics().portraitCount, 1)
		assertions.isNotNil(part:FindFirstChild(QueueWorldDisplayService.DISPLAY_NAME))
		assertions.isTrue(service:update("queue:backyard-squad", snapshot({})).ok)
		assertions.equal(service:getMetrics().portraitCount, 0)
		assertions.isTrue(service:cleanup().ok)
		assertions.isNil(part:FindFirstChild(QueueWorldDisplayService.DISPLAY_NAME))
		part:Destroy()
	end),

	TestHarness.case("rejects mismatched snapshots and authored display conflicts", function(assertions)
		local part = Instance.new("Part")
		local conflict = Instance.new("Folder")
		conflict.Name = QueueWorldDisplayService.DISPLAY_NAME
		conflict.Parent = part
		assertions.isFalse(QueueWorldDisplayService.new({
			{
				queueId = "queue:backyard-squad",
				adornee = part,
			},
		}).ok)
		conflict:Destroy()
		local created = QueueWorldDisplayService.new({ {
			queueId = "queue:backyard-squad",
			adornee = part,
		} })
		assertions.isTrue(created.ok)
		if created.ok then
			local wrong = snapshot({})
			wrong.queueId = "queue:other"
			assertions.isFalse(created.value:update("queue:backyard-squad", wrong).ok)
			created.value:cleanup()
		end
		part:Destroy()
	end),
})
