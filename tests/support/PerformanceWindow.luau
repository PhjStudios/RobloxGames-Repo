--!strict

-- Test-only statistics. Values are observations, never gameplay authority.
local PerformanceWindow = { MAX_SAMPLES = 8192, MAX_PAYLOAD_NODES = 4096, MAX_PAYLOAD_DEPTH = 12 }

function PerformanceWindow.new(capacity: number?)
	local limit = capacity or PerformanceWindow.MAX_SAMPLES
	assert(limit >= 1 and limit <= PerformanceWindow.MAX_SAMPLES and limit % 1 == 0, "invalid sample capacity")
	local samples = {}
	local rejected, total, maximum, count = 0, 0, 0, 0
	local cursor = 1
	return {
		add = function(_self: any, value: unknown): boolean
			if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
				rejected += 1
				return false
			end
			count += 1
			total += value
			maximum = math.max(maximum, value)
			samples[cursor] = value
			cursor = cursor % limit + 1
			return true
		end,
		summary = function(_self: any)
			local sorted = table.clone(samples)
			table.sort(sorted)
			local function percentile(fraction: number)
				return sorted[math.max(1, math.ceil(#sorted * fraction))]
			end
			return table.freeze({
				count = count,
				available = count > 0,
				retained = #samples,
				rejected = rejected,
				mean = if count == 0 then nil else total / count,
				maximum = if count == 0 then nil else maximum,
				p50 = percentile(0.5),
				p95 = percentile(0.95),
				p99 = percentile(0.99),
				percentileScope = if count > limit then "LatestWindow" else "AllSamples",
			})
		end,
	}
end

-- Count a documented JSON-like representation, including keys and Vector3
-- numeric components. This is deliberately NOT called Roblox wire bytes.
function PerformanceWindow.payloadEstimate(value: unknown): (number?, string?)
	local seen = {}
	local nodes = 0
	local function count(item: any, depth: number): number
		nodes += 1
		assert(nodes <= PerformanceWindow.MAX_PAYLOAD_NODES and depth <= PerformanceWindow.MAX_PAYLOAD_DEPTH, "limit")
		local kind = typeof(item)
		if kind == "nil" then
			return 4
		elseif kind == "boolean" then
			return if item then 4 else 5
		elseif kind == "number" then
			assert(item == item and math.abs(item) < math.huge, "number")
			return #string.format("%.17g", item)
		elseif kind == "string" then
			assert(#item <= 8192, "string")
			local escaped = string.gsub(item, '[%z\1-\31\\"]', function(character)
				return if character == '"' or character == "\\" then "\\" .. character else "\\u0000"
			end)
			return #escaped + 2
		elseif kind == "Vector3" then
			return 4 + count(item.X, depth + 1) + count(item.Y, depth + 1) + count(item.Z, depth + 1)
		elseif kind == "Vector2" then
			return 3 + count(item.X, depth + 1) + count(item.Y, depth + 1)
		elseif kind == "table" then
			assert(getmetatable(item) == nil, "metatable")
			assert(not seen[item], "cycle")
			seen[item] = true
			local bytes, entries = 2, 0
			for key, child in item do
				assert(type(key) == "string" or type(key) == "number", "key")
				bytes += count(tostring(key), depth + 1) + 1 + count(child, depth + 1)
				entries += 1
			end
			seen[item] = nil
			return bytes + math.max(0, entries - 1)
		end
		error("unsupported")
	end
	local ok, bytes = pcall(count, value, 0)
	return if ok then bytes else nil, if ok then nil else "UnmeasurablePayload"
end

function PerformanceWindow.classify(value: unknown, target: number, warning: number, failure: number): string
	assert(target >= 0 and target <= warning and warning <= failure, "invalid budget")
	if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return "Unavailable"
	end
	return if value > failure
		then "Fail"
		elseif value > warning then "Warning"
		elseif value > target then "AboveTarget"
		else "Target"
end

return table.freeze(PerformanceWindow)
