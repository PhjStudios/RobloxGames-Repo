--!strict

local HttpService = game:GetService("HttpService")
local AnalyticsService = require(script.Parent.AnalyticsService)
local Dictionary = require(script.Parent.AnalyticsDictionary)

local Methods = {}
Methods.__index = Methods
local OutcomeObserver = { MAX_SCOPES = 128, MAX_DEDUP = 256, MAX_LOGS_PER_MINUTE = 16 }

local function bounded(self: any, bucket: any, key: string, value: any, limit: number)
	if bucket.values[key] == nil then
		if #bucket.order == limit then
			bucket.values[table.remove(bucket.order, 1)] = nil
		end
		table.insert(bucket.order, key)
	end
	bucket.values[key] = { value = value, at = self.clock() }
end

function Methods.correlation(self: any, scope: any): string?
	if self.nonce == nil then
		return nil
	end
	local key = tostring(scope or "server")
	local existing = self.scopes.values[key]
	if existing ~= nil and self.clock() - existing.at < 1800 then
		return existing.value
	end
	self.sequence += 1
	local value = `c-{self.nonce}-{self.sequence}`
	bounded(self, self.scopes, key, value, OutcomeObserver.MAX_SCOPES)
	return value
end

function Methods.emit(self: any, name: string, fields: any, scope: any?, dedup: string?): boolean
	if self.closed then
		return false
	end
	if dedup ~= nil then
		local previous = self.seen.values[dedup]
		if previous ~= nil and self.clock() - previous.at < 1800 then
			return false
		end
	end
	local emitted = self.delivery:emit(name, fields, self:correlation(scope))
	if emitted and dedup ~= nil then
		bounded(self, self.seen, dedup, true, OutcomeObserver.MAX_DEDUP)
	end
	return emitted
end

function Methods.record(self: any, name: string, fields: any, scope: any?, dedup: string?): boolean
	local ok, value = AnalyticsService.nonYielding(self.emit, self, name, fields, scope, dedup)
	return ok and value == true
end

function Methods.failure(self: any, category: string, code: string)
	local fields = Dictionary.validate("operational.v1", { category = category, code = code })
	if self.closed or fields == nil then
		return
	end
	local at = self.clock()
	if at - self.logWindow >= 60 then
		self.logWindow, self.logCount = at, 0
	end
	local key = category .. ":" .. code
	if self.logCount >= OutcomeObserver.MAX_LOGS_PER_MINUTE or at - (self.lastLog[key] or -math.huge) < 30 then
		return
	end
	self.lastLog[key] = at
	self.logCount += 1
	local correlation = self:correlation("server")
	self.delivery:emit("operational.v1", fields, correlation)
	if self.logger ~= nil then
		AnalyticsService.nonYielding(
			self.logger.warn,
			self.logger,
			category,
			"operation_failed",
			"Server operation requires attention",
			{ code = code, correlation = correlation }
		)
	end
end

function Methods.forget(self: any, scope: any)
	local key = tostring(scope)
	self.scopes.values[key] = nil
	local index = table.find(self.scopes.order, key)
	if index ~= nil then
		table.remove(self.scopes.order, index)
	end
end

-- Delegation keeps the original service and its genuine self/return identities.
-- Observation runs only after the authoritative call; any observer exception or
-- attempted yield is contained and cannot change that call's return values.
function Methods.wrap(_self: any, service: any, after: (string, any, any) -> ()): any
	local cache = {}
	return setmetatable({}, {
		__index = function(_, key)
			local value = service[key]
			if type(value) ~= "function" then
				return value
			end
			if cache[key] == nil then
				cache[key] = function(_proxy, ...)
					local arguments = table.pack(...)
					local returned = table.pack(value(service, ...))
					AnalyticsService.nonYielding(after, key, arguments, returned[1])
					return table.unpack(returned, 1, returned.n)
				end
			end
			return cache[key]
		end,
	})
end

function Methods.profile(self: any, service: any): any
	return self:wrap(service, function(method, args, result)
		if
			(method == "getState" and result == "Failed")
			or (type(result) == "table" and result.ok == false and (method == "load" or method == "flush"))
		then
			self:failure("profile", "Unavailable")
		elseif method == "release" then
			self:forget(args[1])
		elseif
			method == "transact"
			and result.ok == true
			and result.value.applied == true
			and args[4] == "Tutorial"
		then
			local tutorial = result.value.profile.tutorial
			local operation = string.match(args[5], "^tutorial|([^|]+)|")
			local action = if operation == "skip"
				then "Skipped"
				elseif operation == "replay" then "Replayed"
				elseif operation == "initialize" then "Initialized"
				elseif tutorial.tutorialCompleted then "Completed"
				else "Advanced"
			if result.value.result.resultCode == "TUTORIAL_CHANGED" then
				self:emit("onboarding.v1", { action = action, step = tutorial.tutorialStep }, args[1])
			end
		end
	end)
end

function Methods.acquisition(self: any, service: any): any
	return self:wrap(service, function(method, args, result)
		if method ~= "pull" or not result.ok then
			return
		end
		local receipt = result.value
		local newCount = 0
		for _, item in receipt.results do
			newCount += if item.isNew then 1 else 0
		end
		local key = `chest:{args[1]}:{receipt.transactionId}`
		if
			self:emit("acquisition.v1", {
				quantity = receipt.quantity,
				newCount = newCount,
				pityBucket = math.min(20, math.floor(receipt.pityAfter / 5)),
			}, args[1], key)
		then
			self:emit(
				"gold.v1",
				{ direction = "Sink", reason = "Chest", amountBucket = math.min(100, math.ceil(receipt.cost / 100)) },
				args[1]
			)
		end
	end)
end

function Methods.rewards(self: any, service: any): any
	return self:wrap(service, function(method, args, result)
		if method ~= "claim" then
			return
		end
		if
			not result.ok
			or result.value.status == "Failed"
			or (result.value.status == "Pending" and result.value.reason == "LEDGER_ACK_PENDING")
		then
			self:failure("reward", "Unavailable")
		elseif result.value.status == "Granted" then
			self:emit("gold.v1", {
				direction = "Source",
				reason = "MatchReward",
				amountBucket = math.min(100, math.ceil(result.value.persistentGoldAwarded / 100)),
			}, args[1], `reward:{args[1]}:{result.value.resultId}`)
		end
	end)
end

function Methods.queue(self: any, service: any): any
	return self:wrap(service, function(method, args, result)
		if (method == "enterPhysical" or method == "leavePhysical") and result.ok and result.value == true then
			local current = service:getSnapshot(args[1])
			if current.ok then
				self:emit("queue.v1", {
					action = if method == "enterPhysical" then "Entered" else "Cancelled",
					members = #current.value.members,
				}, args[2])
			end
			return
		end
		local action = ({
			join = "Entered",
			joinSolo = "Entered",
			joinParty = "Entered",
			leave = "Cancelled",
			start = "Started",
		})[method]
		if action == nil then
			return
		end
		if not result.ok then
			self:emit("queue.v1", { action = "Failed", members = 0 }, args[1])
			return
		end
		local receipt = result.value
		if receipt.changed then
			self:emit(
				"queue.v1",
				{ action = action, members = #receipt.snapshot.members },
				args[1],
				`queue:{args[1]}:{receipt.transactionId}`
			)
		end
	end)
end

function Methods.travel(self: any, service: any): any
	return self:wrap(service, function(method, args, result)
		if method == "start" then
			if result.ok then
				self:emit("travel.v1", { action = "Requested", failureClass = "None" }, "server", `travel:{args[1]}`)
			else
				self:failure("teleport", "Unavailable")
				self:emit("travel.v1", { action = "Failed", failureClass = result.error.failureClass }, "server")
			end
		end
	end)
end

function Methods.admissions(self: any, service: any): any
	return self:wrap(service, function(method, _args, result)
		if method ~= "admit" then
			return
		end
		if result.ok then
			local outcome = result.value
			self:emit(
				"travel.v1",
				{ action = if outcome.kind == "Rejoined" then "Recovered" else "Admitted", failureClass = "None" },
				outcome.userId,
				`admit:{outcome.userId}:{outcome.matchId}:{outcome.kind}`
			)
		else
			self:failure("ticket", "Rejected")
		end
	end)
end

function Methods.matchObserver(self: any, scope: string, mapId: string, difficultyId: string): (any) -> ()
	local previousState: string? = nil
	local previousReady = 0
	return function(metrics)
		local fields = {
			action = "Ready",
			map = mapId,
			difficulty = difficultyId,
			outcome = metrics.result or "None",
			waveBucket = math.min(20, math.floor(metrics.wavesCompleted / 5)),
		}
		if metrics.readyCount > previousReady then
			self:emit("match.v1", fields, scope)
		end
		local action = if metrics.state == "Playing" and previousState ~= "Playing"
			then "Started"
			elseif metrics.state == "Results" and previousState ~= "Results" then "Terminal"
			else nil
		previousState, previousReady = metrics.state, metrics.readyCount
		if action ~= nil then
			fields.action = action
			self:emit("match.v1", fields, scope)
		end
	end
end

function Methods.cleanup(self: any)
	self.closed = true
	self.delivery:cleanup()
	table.clear(self.scopes.values)
	table.clear(self.scopes.order)
	table.clear(self.seen.values)
	table.clear(self.seen.order)
	table.clear(self.lastLog)
end

function OutcomeObserver.new(logger: any?, clock: (() -> number)?, sink: ((any) -> boolean)?, nonce: string?): any
	local selectedClock = clock or os.clock
	local generated, value = pcall(function()
		return HttpService:GenerateGUID(false)
	end)
	local selectedNonce = nonce or (if generated and type(value) == "string" then string.gsub(value, "%-", "") else nil)
	assert(
		selectedNonce == nil or (#selectedNonce <= 32 and string.match(selectedNonce, "^%x+$") ~= nil),
		"invalid correlation nonce"
	)
	return setmetatable({
		logger = logger,
		clock = selectedClock,
		delivery = AnalyticsService.new(selectedClock, sink),
		nonce = selectedNonce,
		sequence = 0,
		scopes = { values = {}, order = {} },
		seen = { values = {}, order = {} },
		lastLog = {},
		logWindow = 0,
		logCount = 0,
		closed = false,
	}, Methods)
end

return table.freeze(OutcomeObserver)
