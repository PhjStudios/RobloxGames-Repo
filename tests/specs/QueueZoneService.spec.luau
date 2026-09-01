--!strict

local ServerStorage = game:GetService("ServerStorage")

local QueueZoneService = require(ServerStorage.AutomatedTests.ProductionServerLobbyQueue.QueueZoneService)
local TestHarness = require(script.Parent.Parent.Support.TestHarness)

type Assertions = TestHarness.Assertions

local function success(assertions: Assertions, value: any): any
	assertions.isTrue(value.ok)
	if not value.ok then
		error("expected zone operation to succeed", 0)
	end
	return value.value
end

return TestHarness.suite("sampled lobby queue zones", {
	TestHarness.case("reconciles duplicate parts departure cadence and transient sample failure", function(assertions)
		local time = 100
		local firstSample: any = { 20, 10, 10 }
		local secondSample: any = {}
		local calls: { string } = {}
		local owner: any = {}
		function owner:enterPhysical(queueId: string, userId: number): any
			table.insert(calls, `enter:{queueId}:{userId}`)
			return { ok = true, value = true }
		end
		function owner:leavePhysical(queueId: string, userId: number): any
			table.insert(calls, `leave:{queueId}:{userId}`)
			return { ok = true, value = true }
		end

		local service = success(
			assertions,
			QueueZoneService.new(owner, {
				{
					queueId = "queue:one",
					sampleUserIds = function(): unknown
						return firstSample
					end,
				},
				{
					queueId = "queue:two",
					sampleUserIds = function(): unknown
						return secondSample
					end,
				},
			}, {
				clock = function(): number
					return time
				end,
				sampleIntervalSeconds = 0.15,
			})
		)
		local definition = service:getServiceDefinition()
		definition.initialize()
		definition.start()

		assertions.equal(success(assertions, service:step(true)), 2)
		assertions.equal(calls[1], "enter:queue:one:10")
		assertions.equal(calls[2], "enter:queue:one:20")
		assertions.equal(service:getMetrics().trackedOccupantCount, 2)

		time = 100.05
		assertions.equal(success(assertions, service:step(false)), 0)
		assertions.equal(#calls, 2)

		firstSample = { 20, 30 }
		time = 100.2
		assertions.equal(success(assertions, service:step(false)), 2)
		assertions.equal(calls[3], "enter:queue:one:20")
		assertions.equal(calls[4], "enter:queue:one:30")
		assertions.equal(calls[5], "leave:queue:one:10")

		firstSample = { [2] = 20 }
		time = 100.4
		assertions.equal(success(assertions, service:step(true)), 1)
		assertions.equal(service:getMetrics().sampleFailureCount, 1)
		assertions.equal(service:getMetrics().trackedOccupantCount, 2)
		assertions.equal(#calls, 5)

		firstSample = {}
		time = 100.6
		assertions.equal(success(assertions, service:step(true)), 2)
		assertions.equal(calls[6], "leave:queue:one:20")
		assertions.equal(calls[7], "leave:queue:one:30")
		assertions.equal(service:getMetrics().trackedOccupantCount, 0)
	end),

	TestHarness.case(
		"cleans tracked occupants deterministically and rejects malformed boundaries",
		function(assertions)
			local malformed = QueueZoneService.new({}, {}, {})
			assertions.isFalse(malformed.ok)
			local time = 5
			local calls: { string } = {}
			local owner: any = {}
			function owner:enterPhysical(_queueId: string, _userId: number): any
				return { ok = true, value = true }
			end
			function owner:leavePhysical(queueId: string, userId: number): any
				table.insert(calls, `{queueId}:{userId}`)
				return { ok = true, value = true }
			end
			local service = success(
				assertions,
				QueueZoneService.new(owner, {
					{
						queueId = "queue:one",
						sampleUserIds = function(): unknown
							return { 40, 10 }
						end,
					},
				}, {
					clock = function(): number
						return time
					end,
				})
			)
			assertions.equal(success(assertions, service:step(true)), 1)
			assertions.isTrue(success(assertions, service:cleanup()))
			assertions.equal(calls[1], "queue:one:10")
			assertions.equal(calls[2], "queue:one:40")
			assertions.equal(service:getMetrics().trackedOccupantCount, 0)
			assertions.isTrue(success(assertions, service:cleanup()))
			local afterCleanup = service:step(true)
			assertions.isFalse(afterCleanup.ok)
			if not afterCleanup.ok then
				assertions.equal(afterCleanup.error.code, "CLEANED")
			end
		end
	),
})
