--[[
	Small deterministic PRNG (Park-Miller) with the same method names as Roblox's Random
	(NextNumber / NextInteger), so pure modules can take either one. Used by unit tests and
	anywhere a reproducible roll is needed.
]]

local Rng = {}
Rng.__index = Rng

local MOD = 2147483647
local MUL = 48271

function Rng.new(seed)
	local s = math.floor(math.abs(tonumber(seed) or 1)) % MOD
	if s == 0 then
		s = 1
	end
	return setmetatable({ state = s }, Rng)
end

function Rng:nextRaw()
	self.state = (self.state * MUL) % MOD
	return self.state
end

-- [0, 1) or [min, max)
function Rng:NextNumber(min, max)
	local v = (self:nextRaw() - 1) / (MOD - 1)
	if min and max then
		return min + (max - min) * v
	end
	return v
end

-- inclusive integer in [min, max]
function Rng:NextInteger(min, max)
	if max < min then
		min, max = max, min
	end
	return min + math.floor(self:NextNumber() * (max - min + 1))
end

return Rng
