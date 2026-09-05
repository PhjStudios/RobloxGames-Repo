--!strict

local Harness = require(script.Parent.Parent.Support.TestHarness)
local Modules = script.Parent.Parent.ProductionServerAnalytics
local Dictionary = require(Modules.AnalyticsDictionary)
local Delivery = require(Modules.AnalyticsService)
local Observer = require(Modules.OutcomeObserver)
local Shared = game:GetService("ReplicatedStorage").Shared
local Content = require(Shared.config.ContentSelection)
local EnvironmentContext = require(Shared.logging.EnvironmentContext)
local Log = require(Shared.logging.Log)
local ConfigurationValidator = require(Shared.config.ConfigurationValidator)
local ProfileService = require(script.Parent.Parent.ProductionServerProfile.ProfileService)
local TutorialService = require(script.Parent.Parent.ProductionServerProfile.TutorialService)
local IsolatedProfileStore = require(script.Parent.Parent.Fixtures.IsolatedProfileStore)

local function harness(): (any, { any }, (number) -> ())
	local at = 0
	local records = {}
	local observer = Observer.new(nil, function()
		return at
	end, function(record)
		table.insert(records, record)
		return true
	end, "ab12")
	return observer, records, function(value)
		at = value
	end
end

return Harness.suite("bounded privacy-safe authoritative observability", {
	Harness.case("every event requires exact bounded dimensions and rejects hostile values", function(a)
		for name, definition in Dictionary.DEFINITIONS do
			local fields = {}
			for key, rule in definition do
				fields[key] = if rule.kind == "integer" then 0 else next(rule.values)
			end
			a.isNotNil(Dictionary.validate(name, fields))
			for _, sensitive in
				{ "userId", "name", "profile", "chat", "accessCode", "teleportData", "receipt", "inventory" }
			do
				local hostile = table.clone(fields)
				hostile[sensitive] = "private"
				a.isNil(Dictionary.validate(name, hostile))
			end
			for key, rule in definition do
				local hostile = table.clone(fields)
				hostile[key] = if rule.kind == "integer" then math.huge else string.rep("x", 4096)
				a.isNil(Dictionary.validate(name, hostile))
				hostile[key] = nil
				a.isNil(Dictionary.validate(name, hostile))
			end
		end
		a.isNil(Dictionary.validate("attack.v1", {}))
		a.isNil(Dictionary.validate("queue.v1", setmetatable({}, {})))
	end),
	Harness.case("default delivery is disabled and has no pending work", function(a)
		local delivery = Delivery.new(function()
			return 0
		end)
		a.isTrue(delivery:emit("queue.v1", { action = "Entered", members = 1 }))
		a.equal(delivery:getMetrics().disabled, 1)
		a.equal(delivery:getMetrics().buffered, 0)
	end),
	Harness.case("enforces per-minute ingestion and per-drain delivery bounds", function(a)
		local at, sent = 0, 0
		local delivery = Delivery.new(function()
			return at
		end, function()
			sent += 1
			return true
		end)
		for _ = 1, 200 do
			delivery:emit("queue.v1", { action = "Entered", members = 1 })
		end
		a.equal(delivery:getMetrics().accepted, 120)
		a.equal(delivery:getMetrics().dropped, 80)
		a.equal(delivery:drain(), 32)
		a.equal(sent, 32)
		at = 60
		a.isTrue(delivery:emit("queue.v1", { action = "Entered", members = 1 }))
	end),
	Harness.case("throwing and yielding sinks retry only once then drop", function(a)
		for _, sink in
			{
				function()
					error("secret destination failure")
				end,
				function()
					coroutine.yield()
				end,
				function()
					return false
				end,
			}
		do
			local delivery = Delivery.new(function()
				return 0
			end, sink)
			delivery:emit("queue.v1", { action = "Entered", members = 1 })
			delivery:drain()
			a.equal(delivery:getMetrics().buffered, 1)
			delivery:drain()
			a.equal(delivery:getMetrics().buffered, 0)
			a.equal(delivery:getMetrics().dropped, 1)
		end
	end),
	Harness.case("reentrant failed delivery never grows the queue beyond its capacity", function(a)
		local at = 59
		local delivery: any
		local peak = 0
		delivery = Delivery.new(function()
			return at
		end, function()
			for _ = 1, 9 do
				delivery:emit("queue.v1", { action = "Entered", members = 1 })
			end
			peak = math.max(peak, delivery:getMetrics().buffered)
			a.equal(delivery:drain(), 0)
			return false
		end)
		for _ = 1, 120 do
			delivery:emit("queue.v1", { action = "Entered", members = 1 })
		end
		at = 60
		a.equal(delivery:drain(), 32)
		a.equal(peak, Delivery.MAX_BUFFER)
		a.isTrue(delivery:getMetrics().buffered <= Delivery.MAX_BUFFER)
		a.isTrue(delivery:getMetrics().dropped > 0)
	end),
	Harness.case("expires records and discards pending work on shutdown", function(a)
		local at, calls = 0, 0
		local delivery = Delivery.new(function()
			return at
		end, function()
			calls += 1
			return true
		end)
		delivery:emit("queue.v1", { action = "Entered", members = 1 })
		at = 31
		delivery:drain()
		a.equal(calls, 0)
		delivery:emit("queue.v1", { action = "Entered", members = 1 })
		delivery:cleanup()
		a.equal(delivery:getMetrics().buffered, 0)
		a.isFalse(delivery:emit("queue.v1", { action = "Entered", members = 1 }))
	end),
	Harness.case("preserves genuine service identity and multiple returns despite observer failure", function(a)
		local observer = harness()
		local marker = {}
		local service = {}
		function service.invoke(self, argument)
			a.equal(self, service)
			a.equal(argument, "ok")
			return marker, nil, 7
		end
		local wrapped = observer:wrap(service, function()
			error("observer failure")
		end)
		local result, middle, last = wrapped:invoke("ok")
		a.equal(result, marker)
		a.isNil(middle)
		a.equal(last, 7)
		local yielding = observer:wrap(service, function()
			coroutine.yield()
		end)
		a.equal(yielding:invoke("ok"), marker)
	end),
	Harness.case("profile events follow applied tutorial commits and never replay or failed mutations", function(a)
		local observer, records = harness()
		local outcome = {
			ok = true,
			value = {
				applied = true,
				result = { resultCode = "TUTORIAL_CHANGED" },
				profile = { tutorial = { tutorialStep = 1, tutorialCompleted = false } },
			},
		}
		local service = {
			transact = function()
				return outcome
			end,
		}
		local profile = observer:profile(service)
		a.equal(
			profile:transact(123456789, "transaction:x", 1, "Tutorial", "tutorial|initialize|1", function() end),
			outcome
		)
		outcome.value.applied = false
		profile:transact(123456789, "transaction:x", 1, "Tutorial", "tutorial|initialize|1", function() end)
		observer.delivery:drain()
		a.equal(#records, 1)
		a.equal(records[1].fields.action, "Initialized")
		a.equal(records[1].correlation, "c-ab12-1")
		a.isNil(records[1].fields.userId)
	end),
	Harness.case("acquisition emits one aggregate and Gold sink per successful receipt", function(a)
		local observer, records = harness()
		local receipt = {
			transactionId = "transaction:pull",
			quantity = 2,
			pityAfter = 14,
			cost = 200,
			results = { { isNew = true }, { isNew = false } },
		}
		local service = observer:acquisition({
			pull = function()
				return { ok = true, value = receipt }
			end,
		})
		service:pull(12)
		service:pull(12)
		observer.delivery:drain()
		a.equal(#records, 2)
		a.equal(records[1].fields.newCount, 1)
		a.equal(records[2].fields.direction, "Sink")
	end),
	Harness.case("production profile and tutorial authority still commit while the sink fails", function(a)
		local config = ConfigurationValidator.validateLoaded().value
		local rawProfile = ProfileService.new(config.towers, IsolatedProfileStore.new(), {
			sessionId = "session:analytics",
			clock = function()
				return 1_700_100_000
			end,
			wait = function() end,
		}).value
		a.isTrue(rawProfile:load(101).ok)
		local observer = Observer.new(nil, function()
			return 0
		end, function()
			error("unavailable sink")
		end, "ab")
		local profile = observer:profile(rawProfile)
		local tutorial = TutorialService.new(profile, config, {
			clock = function()
				return 1_700_100_000
			end,
		}).value
		local initialized = tutorial:initialize(101)
		a.isTrue(initialized.ok)
		a.equal(initialized.value.tutorial.tutorialStep, 1)
		a.equal(observer.delivery:getMetrics().accepted, 1)
		local revision = rawProfile:read(101).value.revision
		a.isTrue(tutorial:initialize(101).ok)
		a.equal(rawProfile:read(101).value.revision, revision)
		a.equal(observer.delivery:getMetrics().accepted, 1)
		observer.delivery:drain()
		observer.delivery:drain()
		a.equal(observer.delivery:getMetrics().dropped, 1)
		a.equal(rawProfile:getState(101), "Ready")
		a.isTrue(profile:release(101).ok)
		observer:cleanup()
	end),
	Harness.case("sink shutdown during delivery leaves no retry or dangling records", function(a)
		local delivery: any
		delivery = Delivery.new(function()
			return 0
		end, function()
			delivery:cleanup()
			return false
		end)
		for _ = 1, 2 do
			delivery:emit("queue.v1", { action = "Entered", members = 1 })
		end
		a.equal(delivery:drain(), 1)
		a.equal(delivery:getMetrics().buffered, 0)
	end),
	Harness.case("reward source is emitted only for a durably Granted claim and deduplicated", function(a)
		local observer, records = harness()
		local view = { status = "Pending", resultId = "result:private", persistentGoldAwarded = 500 }
		local claims = observer:rewards({
			claim = function()
				return { ok = true, value = view }
			end,
		})
		claims:claim(12, "result:private")
		view.status = "Granted"
		claims:claim(12, "result:private")
		claims:claim(12, "result:private")
		observer.delivery:drain()
		local gold = 0
		for _, record in records do
			if record.name == "gold.v1" then
				gold += 1
			end
		end
		a.equal(gold, 1)
	end),
	Harness.case("match transitions do not emit for per-frame or per-attack changes", function(a)
		local observer, records = harness()
		local observe = observer:matchObserver("internal-match", Content.RELEASE_MAP_ID, Content.EASY_DIFFICULTY_ID)
		observe({ state = "Ready", readyCount = 0, wavesCompleted = 0 })
		for attacks = 1, 100 do
			observe({ state = "Playing", readyCount = 1, wavesCompleted = 0, attackCount = attacks })
		end
		observe({ state = "Results", readyCount = 1, wavesCompleted = 20, result = "Victory" })
		observer.delivery:drain()
		a.equal(#records, 3)
		a.equal(records[1].fields.action, "Ready")
		a.equal(records[2].fields.action, "Started")
		a.equal(records[3].fields.waveBucket, 4)
	end),
	Harness.case("operational logs rate limit and reject unsafe fields with opaque correlation", function(a)
		local count = 0
		local observer = Observer.new({
			warn = function()
				count += 1
			end,
		}, function()
			return 0
		end, nil, "aa")
		for _ = 1, 1000 do
			observer:failure("profile", "Unavailable")
		end
		observer:failure("profile", "raw-player-secret")
		a.equal(count, 1)
		local logger = Log.new(EnvironmentContext.new("server", "Match", 104415140644510, true))
		for _, fields in
			{
				{ correlation = "user:123" },
				{ code = string.rep("x", 129) },
				{ secret = "private" },
				setmetatable({}, {
					__iter = function()
						error("private")
					end,
				}),
			}
		do
			a.isFalse(pcall(logger.formatRecord, logger, "WARN", "profile", "failed", "Safe message", fields))
		end
		a.isTrue(
			pcall(logger.formatRecord, logger, "WARN", "profile", "failed", "Safe message", { correlation = "c-aa-1" })
		)
	end),
	Harness.case("correlation and dedup caches stay bounded and cleanup releases all records", function(a)
		local observer, _, advance = harness()
		for index = 1, 1000 do
			advance(index * 60)
			observer:emit("queue.v1", { action = "Entered", members = 1 }, index, tostring(index))
			observer.delivery:drain()
		end
		a.equal(#observer.scopes.order, Observer.MAX_SCOPES)
		a.equal(#observer.seen.order, Observer.MAX_DEDUP)
		observer:cleanup()
		a.equal(#observer.scopes.order, 0)
		a.equal(#observer.seen.order, 0)
		a.equal(observer.delivery:getMetrics().buffered, 0)
	end),
})
