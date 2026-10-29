--[[
	Reach - geometric reachability for a depth, from the parts that were actually built.

	  * A collision index of every colliding part (oriented boxes, bucketed on an XZ grid).
	  * A multi-level walk graph: for each 1.5-stud column every walkable surface (the top
	    face of a colliding part tilted at most ~53 degrees: decks, steps, treasure
	    terraces, ramp slabs, tunnel floors) becomes a node if a character fits on it
	    (feet, waist and head probes and a footprint clear of parts). Neighbouring nodes
	    connect when their heights differ by at most MaxStep (1.25 studs per 1.5 studs,
	    i.e. one 1-stud stair or a 40-degree slope - what a Humanoid walks without jumping).
	    The graph is flood-filled from the arrival deck, so walled-off space and anything
	    only reachable by jumping or climbing never counts.
	  * pointOk(point): a loot spawn point is not buried in a part, and some reachable node
	    is within pickup range with a clear line from the character to the item.
	VaultBuilder drops spawn points that fail; the harness asserts every point passes, that
	the machines, the door and (with the door open) the next depth's rim are reachable.
	Pure maths over parts - no raycasts (world parts are not queryable).
]]

local Reach = {}

local CELL = 1.5
local BUCKET = 8
Reach.Cell = CELL
Reach.MaxStep = 1.25
Reach.PickupRange = 6.5 -- base Collection Radius 7, minus a margin
Reach.RootHeight = 3

local function key(ix, iz)
	return (ix + 32768) * 65536 + (iz + 32768)
end

-- Collision index over every colliding BasePart under the given roots.
function Reach.index(roots)
	if typeof(roots) == "Instance" then
		roots = { roots }
	end
	local idx = { buckets = {} }
	for _, root in ipairs(roots) do
		for _, p in ipairs(root:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide then
				local cf, half = p.CFrame, p.Size / 2
				local r = cf.RightVector * half.X
				local u = cf.UpVector * half.Y
				local l = cf.LookVector * half.Z
				local ext = Vector3.new(math.abs(r.X) + math.abs(u.X) + math.abs(l.X), math.abs(r.Y) + math.abs(u.Y) + math.abs(l.Y), math.abs(r.Z) + math.abs(u.Z) + math.abs(l.Z))
				local c = cf.Position
				local entry = { cf = cf, half = half, up = cf.UpVector, minY = c.Y - ext.Y, maxY = c.Y + ext.Y }
				for ix = math.floor((c.X - ext.X) / BUCKET), math.floor((c.X + ext.X) / BUCKET) do
					for iz = math.floor((c.Z - ext.Z) / BUCKET), math.floor((c.Z + ext.Z) / BUCKET) do
						local k = key(ix, iz)
						idx.buckets[k] = idx.buckets[k] or {}
						table.insert(idx.buckets[k], entry)
					end
				end
			end
		end
	end
	return idx
end

local function bucketOf(idx, x, z)
	return idx.buckets[key(math.floor(x / BUCKET), math.floor(z / BUCKET))]
end

-- Is the point inside a colliding part (grown by `pad`)?
function Reach.blocked(idx, pos, pad)
	pad = pad or 0
	local list = bucketOf(idx, pos.X, pos.Z)
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

-- Heights of every walkable top face over (x, z) between yMin and yMax.
local function floorsAt(idx, x, z, yMin, yMax)
	local out = {}
	for _, e in ipairs(bucketOf(idx, x, z) or {}) do
		local u = e.up
		if u.Y >= 0.6 and e.maxY >= yMin and e.minY <= yMax then
			local top = e.cf.Position + u * e.half.Y
			local y = top.Y - (u.X * (x - top.X) + u.Z * (z - top.Z)) / u.Y
			if y >= yMin and y <= yMax then
				local l = e.cf:PointToObjectSpace(Vector3.new(x, y, z))
				if math.abs(l.X) <= e.half.X + 0.01 and math.abs(l.Z) <= e.half.Z + 0.01 then
					local dup = false
					for _, f in ipairs(out) do
						if math.abs(f - y) < 0.3 then
							dup = true
						end
					end
					if not dup then
						table.insert(out, y)
					end
				end
			end
		end
	end
	return out
end

local function standable(idx, x, y, z)
	for _, h in ipairs({ 1.35, 2.6, 4.4 }) do
		if Reach.blocked(idx, Vector3.new(x, y + h, z), 0.1) then
			return false
		end
	end
	for _, o in ipairs({ { 0.8, 0 }, { -0.8, 0 }, { 0, 0.8 }, { 0, -0.8 } }) do
		if Reach.blocked(idx, Vector3.new(x + o[1], y + 1.7, z + o[2]), 0) then
			return false
		end
	end
	return true
end

--[[
	Walk graph. bounds = { x0, x1, z0, z1, yMin, yMax }; start = a position on the arrival
	deck. Returns { nodes = { Vector3 feet positions of REACHABLE nodes }, buckets }.
]]
function Reach.walk(idx, bounds, start)
	local nx = math.floor((bounds[2] - bounds[1]) / CELL)
	local nz = math.floor((bounds[4] - bounds[3]) / CELL)
	local columns = {}
	local function centre(ix, iz)
		return bounds[1] + (ix + 0.5) * CELL, bounds[3] + (iz + 0.5) * CELL
	end
	local function column(ix, iz)
		if ix < 0 or iz < 0 or ix >= nx or iz >= nz then
			return {}
		end
		local k = key(ix, iz)
		local col = columns[k]
		if not col then
			col = {}
			local x, z = centre(ix, iz)
			for _, y in ipairs(floorsAt(idx, x, z, bounds[5], bounds[6])) do
				if standable(idx, x, y, z) then
					table.insert(col, { y = y, seen = false })
				end
			end
			columns[k] = col
		end
		return col
	end
	local walk = { list = {}, buckets = {} }
	local sx = math.floor((start.X - bounds[1]) / CELL)
	local sz = math.floor((start.Z - bounds[3]) / CELL)
	local first
	for _, n in ipairs(column(sx, sz)) do
		if not first or math.abs(n.y - start.Y) < math.abs(first.y - start.Y) then
			first = n
		end
	end
	if not first then
		return walk
	end
	first.seen = true
	local queue, head = { { sx, sz, first } }, 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		local x, z = centre(c[1], c[2])
		local p = Vector3.new(x, c[3].y, z)
		table.insert(walk.list, p)
		local bk = key(math.floor(x / BUCKET), math.floor(z / BUCKET))
		walk.buckets[bk] = walk.buckets[bk] or {}
		table.insert(walk.buckets[bk], p)
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local ix, iz = c[1] + d[1], c[2] + d[2]
			for _, n in ipairs(column(ix, iz)) do
				if not n.seen and math.abs(n.y - c[3].y) <= Reach.MaxStep then
					n.seen = true
					table.insert(queue, { ix, iz, n })
				end
			end
		end
	end
	return walk
end

-- Reachable nodes within `range` (horizontal) of a position, optionally within dy.
function Reach.near(walk, pos, range, dy)
	local out = {}
	for ix = math.floor((pos.X - range) / BUCKET), math.floor((pos.X + range) / BUCKET) do
		for iz = math.floor((pos.Z - range) / BUCKET), math.floor((pos.Z + range) / BUCKET) do
			for _, p in ipairs(walk.buckets[key(ix, iz)] or {}) do
				if Vector3.new(p.X - pos.X, 0, p.Z - pos.Z).Magnitude <= range and (not dy or math.abs(p.Y - pos.Y) <= dy) then
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
	for _, feet in ipairs(Reach.near(walk, pos, Reach.PickupRange, 8)) do
		local root = feet + Vector3.new(0, Reach.RootHeight, 0)
		if (root - target).Magnitude <= Reach.PickupRange and clearLine(idx, root, target) then
			return true
		end
	end
	return false, "no reachable spot in pickup range"
end

-- Is there a reachable node within `range` (and 4 studs of height) of a position?
function Reach.reachable(walk, pos, range)
	return #Reach.near(walk, pos, range or 4, 4) > 0
end

return Reach
