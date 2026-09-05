--!strict

local Dictionary = require(script.Parent.AnalyticsDictionary)
local Methods = {}
Methods.__index = Methods
local AnalyticsService = {
	MAX_BUFFER = 128,
	MAX_PER_MINUTE = 120,
	MAX_BATCH = 32,
	TTL_SECONDS = 30,
	MAX_ATTEMPTS = 2,
}

-- A sink must return without yielding. A reviewed external adapter, if added,
-- must own its asynchronous work; this layer never waits on network delivery.
local function nonYielding(callback: (...any) -> any, ...: any): (boolean, any)
	local thread = coroutine.create(callback)
	local ok, result = coroutine.resume(thread, ...)
	if not ok or coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, nil
	end
	return true, result
end

local function now(self: any): number?
	local ok, value = nonYielding(self.clock)
	if not ok or type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return nil
	end
	return value
end

function Methods.emit(self: any, name: unknown, fields: unknown, correlation: unknown): boolean
	if self.closed then
		return false
	end
	local safe = Dictionary.validate(name, fields)
	if
		safe == nil
		or (
			correlation ~= nil
			and (
				type(correlation) ~= "string"
				or #correlation > 48
				or string.match(correlation, "^c%-%x+%-%d+$") == nil
			)
		)
	then
		self.rejected += 1
		return false
	end
	local at = now(self)
	if at == nil then
		self.dropped += 1
		return false
	end
	if at - self.windowAt >= 60 then
		self.windowAt, self.windowCount = at, 0
	end
	if self.windowCount >= AnalyticsService.MAX_PER_MINUTE then
		self.dropped += 1
		return false
	end
	self.windowCount += 1
	if self.sink == nil then
		self.accepted += 1
		self.disabled += 1
		return true
	end
	if #self.queue >= AnalyticsService.MAX_BUFFER then
		self.dropped += 1
		return false
	end
	self.accepted += 1
	table.insert(self.queue, {
		record = table.freeze({
			version = Dictionary.VERSION,
			contentVersion = Dictionary.CONTENT_VERSION,
			name = name,
			fields = safe,
			correlation = correlation,
		}),
		at = at,
		attempts = 0,
	})
	return true
end

function Methods.drain(self: any): number
	if self.closed or self.draining then
		return 0
	end
	local at = now(self)
	if at == nil then
		return 0
	end
	self.draining = true
	local count = math.min(#self.queue, AnalyticsService.MAX_BATCH)
	local processed = 0
	for _ = 1, count do
		if self.closed then
			break
		end
		local pending = table.remove(self.queue, 1)
		processed += 1
		if at - pending.at >= AnalyticsService.TTL_SECONDS then
			self.dropped += 1
		else
			pending.attempts += 1
			local ok, delivered = nonYielding(self.sink, pending.record)
			if ok and delivered == true then
				self.delivered += 1
			elseif
				not self.closed
				and pending.attempts < AnalyticsService.MAX_ATTEMPTS
				and #self.queue < AnalyticsService.MAX_BUFFER
			then
				table.insert(self.queue, pending)
			else
				self.dropped += 1
			end
		end
	end
	self.draining = false
	return processed
end

function Methods.getMetrics(self: any): any
	return table.freeze({
		accepted = self.accepted,
		rejected = self.rejected,
		dropped = self.dropped,
		delivered = self.delivered,
		disabled = self.disabled,
		buffered = #self.queue,
		closed = self.closed,
	})
end

function Methods.cleanup(self: any)
	self.closed = true
	self.dropped += #self.queue
	table.clear(self.queue)
	self.sink = nil
end

function AnalyticsService.new(clock: (() -> number)?, sink: ((any) -> boolean)?): any
	assert(clock == nil or type(clock) == "function", "invalid analytics clock")
	assert(sink == nil or type(sink) == "function", "invalid analytics sink")
	return setmetatable({
		clock = clock or os.clock,
		sink = sink,
		queue = {},
		closed = false,
		draining = false,
		windowAt = 0,
		windowCount = 0,
		accepted = 0,
		rejected = 0,
		dropped = 0,
		delivered = 0,
		disabled = 0,
	}, Methods)
end

AnalyticsService.nonYielding = nonYielding
return table.freeze(AnalyticsService)
