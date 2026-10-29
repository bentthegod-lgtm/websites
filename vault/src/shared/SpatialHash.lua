--[[
	SpatialHash - a uniform XZ grid of buckets for "what's near here" queries over thousands
	of objects (the loot filling a pool), without looping over all of them.
	insert / move / remove by key; query(pos, radius) returns the keys whose stored point is
	within radius (horizontal distance); nearest(pos, radius, filter) the closest one.
]]

local SpatialHash = {}
SpatialHash.__index = SpatialHash

function SpatialHash.new(cell)
	return setmetatable({ cell = cell or 8, buckets = {}, where = {}, points = {}, size = 0 }, SpatialHash)
end

local function bkey(self, x, z)
	return math.floor(x / self.cell) * 100003 + math.floor(z / self.cell)
end

function SpatialHash:insert(key, pos)
	if self.where[key] then
		self:remove(key)
	end
	local k = bkey(self, pos.X, pos.Z)
	local bucket = self.buckets[k]
	if not bucket then
		bucket = {}
		self.buckets[k] = bucket
	end
	bucket[key] = true
	self.where[key] = k
	self.points[key] = pos
	self.size += 1
end

function SpatialHash:remove(key)
	local k = self.where[key]
	if k == nil then
		return
	end
	local bucket = self.buckets[k]
	bucket[key] = nil
	if next(bucket) == nil then
		self.buckets[k] = nil
	end
	self.where[key] = nil
	self.points[key] = nil
	self.size -= 1
end

function SpatialHash:move(key, pos)
	local k = bkey(self, pos.X, pos.Z)
	if self.where[key] == k then
		self.points[key] = pos
	else
		self:insert(key, pos)
	end
end

function SpatialHash:query(pos, radius, out)
	out = out or {}
	local c = self.cell
	for ix = math.floor((pos.X - radius) / c), math.floor((pos.X + radius) / c) do
		for iz = math.floor((pos.Z - radius) / c), math.floor((pos.Z + radius) / c) do
			local bucket = self.buckets[ix * 100003 + iz]
			if bucket then
				for key in pairs(bucket) do
					local p = self.points[key]
					local dx, dz = p.X - pos.X, p.Z - pos.Z
					if dx * dx + dz * dz <= radius * radius then
						table.insert(out, key)
					end
				end
			end
		end
	end
	return out
end

-- Nearest key within radius by 3D distance (filter(key, point) -> bool optional).
function SpatialHash:nearest(pos, radius, filter)
	local best, bestD
	for _, key in ipairs(self:query(pos, radius)) do
		local p = self.points[key]
		local d = (p - pos).Magnitude
		if d <= radius and (not bestD or d < bestD) and (not filter or filter(key, p)) then
			best, bestD = key, d
		end
	end
	return best, bestD
end

return SpatialHash
