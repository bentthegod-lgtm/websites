--[[
	Token-bucket rate limiter for remotes: allows short bursts (dragging across a row of
	ripe crops) but caps the sustained rate.
]]

local RateLimit = {}
RateLimit.__index = RateLimit

function RateLimit.new(perSecond, burst)
	return setmetatable({ rate = perSecond, burst = burst, buckets = {} }, RateLimit)
end

function RateLimit:allow(player)
	local now = os.clock()
	local b = self.buckets[player]
	if not b then
		b = { tokens = self.burst, at = now }
		self.buckets[player] = b
	end
	b.tokens = math.min(self.burst, b.tokens + (now - b.at) * self.rate)
	b.at = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

function RateLimit:forget(player)
	self.buckets[player] = nil
end

return RateLimit
