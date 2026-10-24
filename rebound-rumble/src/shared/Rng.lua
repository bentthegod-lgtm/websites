--[[
	Deterministic seeded random number generator (Park-Miller "minimal standard").

	Written in plain Luau with no Roblox types so the exact same sequence is produced in
	Roblox and in the Lune test runner. Map layouts, item placement and patrol choices
	all draw from an Rng so a run can be reproduced from its seed.
]]

local Rng = {}
Rng.__index = Rng

local MODULUS = 2147483647
local MULTIPLIER = 48271

function Rng.new(seed)
	local state = math.floor(math.abs(seed or 1)) % MODULUS
	if state == 0 then
		state = 1
	end
	return setmetatable({ state = state }, Rng)
end

function Rng:nextRaw()
	self.state = (self.state * MULTIPLIER) % MODULUS
	return self.state
end

-- Uniform float in [0, 1).
function Rng:next()
	return (self:nextRaw() - 1) / (MODULUS - 1)
end

-- Uniform integer in [min, max] (inclusive).
function Rng:integer(min, max)
	if max < min then
		min, max = max, min
	end
	return min + math.floor(self:next() * (max - min + 1))
end

-- Uniform float in [min, max).
function Rng:range(min, max)
	return min + (max - min) * self:next()
end

function Rng:chance(probability)
	return self:next() < probability
end

function Rng:pick(list)
	if #list == 0 then
		return nil
	end
	return list[self:integer(1, #list)]
end

-- Picks a key from a { key = weight } table. Keys are sorted first so the result does not
-- depend on table iteration order.
function Rng:weighted(weights)
	local keys = {}
	local total = 0
	for key, weight in pairs(weights) do
		if weight > 0 then
			table.insert(keys, key)
			total += weight
		end
	end
	table.sort(keys)
	if total <= 0 then
		return nil
	end
	local roll = self:next() * total
	for _, key in ipairs(keys) do
		roll -= weights[key]
		if roll < 0 then
			return key
		end
	end
	return keys[#keys]
end

-- In-place Fisher-Yates shuffle. Returns the same list for convenience.
function Rng:shuffle(list)
	for i = #list, 2, -1 do
		local j = self:integer(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return Rng
