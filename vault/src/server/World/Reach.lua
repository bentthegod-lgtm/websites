--[[
	Reach - geometric reachability for a depth, from the parts that were actually built.

	  * A collision index of every colliding part on the floor (oriented boxes, bucketed on
	    an XZ grid).
	  * A walk grid: 2-stud cells where a character fits (feet, waist and head probes and a
	    footprint clear of colliding parts), flood-filled from the elevator arrival, so a
	    cell walled off by racks or inner walls does not count.
	  * pointOk(point): a loot spawn point is not buried in a part, and at least one reachable
	    cell is within pickup range with a clear line from the character to the item.
	VaultBuilder drops spawn points that fail; the harness asserts every point passes and
	that the machines and the exit door are reachable. Pure maths over parts - no raycasts
	(world parts are not queryable).
]]

local Reach = {}

local CELL = 2
local BUCKET = 8
Reach.PickupRange = 6.5 -- base Collection Radius 7, minus a margin
Reach.RootHeight = 3

local function key(ix, iz)
	return ix * 65536 + iz
end

-- Collision index over every colliding BasePart under `root`.
function Reach.index(root)
	local idx = { buckets = {} }
	for _, p in ipairs(root:GetDescendants()) do
		if p:IsA("BasePart") and p.CanCollide then
			local cf, half = p.CFrame, p.Size / 2
			local r = cf.RightVector * half.X
			local u = cf.UpVector * half.Y
			local l = cf.LookVector * half.Z
			local ext = Vector3.new(math.abs(r.X) + math.abs(u.X) + math.abs(l.X), math.abs(r.Y) + math.abs(u.Y) + math.abs(l.Y), math.abs(r.Z) + math.abs(u.Z) + math.abs(l.Z))
			local c = cf.Position
			local entry = { cf = cf, half = half, minY = c.Y - ext.Y, maxY = c.Y + ext.Y }
			for ix = math.floor((c.X - ext.X) / BUCKET), math.floor((c.X + ext.X) / BUCKET) do
				for iz = math.floor((c.Z - ext.Z) / BUCKET), math.floor((c.Z + ext.Z) / BUCKET) do
					local k = key(ix, iz)
					idx.buckets[k] = idx.buckets[k] or {}
					table.insert(idx.buckets[k], entry)
				end
			end
		end
	end
	return idx
end

-- Is the point inside a colliding part (grown by `pad`)?
function Reach.blocked(idx, pos, pad)
	pad = pad or 0
	local list = idx.buckets[key(math.floor(pos.X / BUCKET), math.floor(pos.Z / BUCKET))]
	if not list then
		return false
	end
	for _, e in ipairs(list) do
		if pos.Y >= e.minY - pad and pos.Y <= e.maxY + pad then
			local l = e.cf:PointToObjectSpace(pos)
			if math.abs(l.X) <= e.half.X + pad and math.abs(l.Y) <= e.half.Y + pad and math.abs(l.Z) <= e.half.Z + pad then
				return true
			end
		end
	end
	return false
end

local function standable(idx, x, y0, z)
	for _, h in ipairs({ 0.9, 2.6, 4.4 }) do
		if Reach.blocked(idx, Vector3.new(x, y0 + h, z), 0.1) then
			return false
		end
	end
	for _, o in ipairs({ { 0.8, 0 }, { -0.8, 0 }, { 0, 0.8 }, { 0, -0.8 } }) do
		if Reach.blocked(idx, Vector3.new(x + o[1], y0 + 1.6, z + o[2]), 0) then
			return false
		end
	end
	return true
end

--[[
	Walk grid for a depth. bounds = { x0, x1, z0, z1 } (room interior), start = Vector3.
	Returns { cells = { [key] = Vector3 (feet) }, list = { Vector3 } } of REACHABLE cells.
]]
function Reach.walk(idx, y0, bounds, start)
	local function cellOf(x, z)
		return math.floor((x - bounds[1]) / CELL), math.floor((z - bounds[3]) / CELL)
	end
	local nx = math.floor((bounds[2] - bounds[1]) / CELL)
	local nz = math.floor((bounds[4] - bounds[3]) / CELL)
	local ok = {}
	local function centre(ix, iz)
		return bounds[1] + (ix + 0.5) * CELL, bounds[3] + (iz + 0.5) * CELL
	end
	local function isOk(ix, iz)
		if ix < 0 or iz < 0 or ix >= nx or iz >= nz then
			return false
		end
		local k = key(ix, iz)
		if ok[k] == nil then
			local x, z = centre(ix, iz)
			ok[k] = standable(idx, x, y0, z)
		end
		return ok[k]
	end
	local walk = { cells = {}, list = {} }
	local sx, sz = cellOf(start.X, start.Z)
	if not isOk(sx, sz) then
		return walk
	end
	local queue, head = { { sx, sz } }, 1
	walk.cells[key(sx, sz)] = true
	while head <= #queue do
		local c = queue[head]
		head += 1
		local x, z = centre(c[1], c[2])
		table.insert(walk.list, Vector3.new(x, y0, z))
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local ix, iz = c[1] + d[1], c[2] + d[2]
			local k = key(ix, iz)
			if not walk.cells[k] and isOk(ix, iz) then
				walk.cells[k] = true
				table.insert(queue, { ix, iz })
			end
		end
	end
	-- Bucket reachable cells for range queries.
	walk.buckets = {}
	for _, p in ipairs(walk.list) do
		local k = key(math.floor(p.X / BUCKET), math.floor(p.Z / BUCKET))
		walk.buckets[k] = walk.buckets[k] or {}
		table.insert(walk.buckets[k], p)
	end
	return walk
end

-- Reachable cells within `range` (horizontal) of a position.
function Reach.near(walk, pos, range)
	local out = {}
	for ix = math.floor((pos.X - range) / BUCKET), math.floor((pos.X + range) / BUCKET) do
		for iz = math.floor((pos.Z - range) / BUCKET), math.floor((pos.Z + range) / BUCKET) do
			for _, p in ipairs(walk.buckets[key(ix, iz)] or {}) do
				if (Vector3.new(p.X - pos.X, 0, p.Z - pos.Z)).Magnitude <= range then
					table.insert(out, p)
				end
			end
		end
	end
	return out
end

local function clearLine(idx, a, b)
	local d = b - a
	local len = d.Magnitude
	local steps = math.max(1, math.floor(len / 0.5))
	for i = 1, steps - 1 do
		local t = i / steps
		if len * (1 - t) > 0.7 and Reach.blocked(idx, a + d * t, 0) then
			return false
		end
	end
	return true
end

-- A spawn point is OK if it isn't buried and someone standing nearby can reach and see it.
function Reach.pointOk(idx, walk, pos)
	if Reach.blocked(idx, pos + Vector3.new(0, 0.35, 0), 0) then
		return false, "inside a part"
	end
	local target = pos + Vector3.new(0, 0.35, 0)
	for _, feet in ipairs(Reach.near(walk, pos, Reach.PickupRange)) do
		local root = feet + Vector3.new(0, Reach.RootHeight, 0)
		if (root - target).Magnitude <= Reach.PickupRange and clearLine(idx, root, target) then
			return true
		end
	end
	return false, "no reachable spot in pickup range"
end

-- Is there a reachable cell within `range` of a position (machines, the exit door)?
function Reach.reachable(walk, pos, range)
	return #Reach.near(walk, pos, range or 4) > 0
end

return Reach
