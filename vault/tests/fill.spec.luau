local L = require("./loader")
local FillGrid = L.shared("FillGrid")
local PoolProfile = L.shared("PoolProfile")
local SpatialHash = L.shared("SpatialHash")
local RefillQueue = L.shared("RefillQueue")
local Rng = L.shared("Rng")
local Vector3 = L.roblox.Vector3

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Fill: " .. name, fn = fn })
end

-- Same exclusions as Pools.FillExclude (door swing, threshold, rare spot).
local EXCLUDE = { { 5, 13, 29, 49.5 }, { -8, 8, 46.5, 50 }, { -14.5, -9.5, 38.5, 43.5 } }
local function padded(list, pad)
	local out = {}
	for _, b in ipairs(list) do
		table.insert(out, { b[1] - pad, b[2] + pad, b[3] - pad, b[4] + pad })
	end
	return out
end

test("the grid tiles the whole treasure surface: no gap wider than 2.7 studs", function()
	local slots = FillGrid.generate(7919, EXCLUDE)
	local gap, at = FillGrid.maxGap(slots, padded(EXCLUDE, 2), 0.7)
	assert(gap <= 2.7, string.format("bare patch of %.2f studs at %s", gap, tostring(at)))
end)

test("slot count stays within the per-depth budget and every slot sits on the surface", function()
	local P = PoolProfile.Pool
	for seed = 1, 7 do
		local slots = FillGrid.generate(seed * 7919, EXCLUDE)
		assert(#slots >= 1500 and #slots <= 2000, "slots " .. #slots)
		for _, s in ipairs(slots) do
			assert(s.x > P.x0 and s.x < P.x1 and s.z > P.z0 and s.z < P.z1, "slot outside the pool")
			assert(math.abs(s.h - PoolProfile.surface(s.z)) < 1e-9, "slot not on the surface")
			assert(not FillGrid.excluded(EXCLUDE, s.x, s.z), "slot in an excluded area")
			assert(s.bonus >= 1 and s.bonus <= 1.8 + 1e-9, "bonus range")
		end
	end
	local a, b = FillGrid.generate(42, EXCLUDE), FillGrid.generate(42, EXCLUDE)
	assert(#a == #b and a[100].x == b[100].x and a[100].z == b[100].z, "not deterministic")
end)

test("deeper slots get more luck", function()
	local shallow, deep = 0, 0
	for _, s in ipairs(FillGrid.generate(5, EXCLUDE)) do
		if s.h > -10 then
			shallow = math.max(shallow, s.bonus)
		elseif s.h <= -41.9 then
			deep = math.max(deep, s.bonus)
		end
	end
	assert(deep > shallow + 0.6, "bonus should rise with depth")
end)

test("spatial hash: query / nearest match brute force; move and remove keep it exact", function()
	local rng = Rng.new(3)
	local h = SpatialHash.new(8)
	local points = {}
	for i = 1, 3000 do
		points[i] = Vector3.new(rng:NextNumber(-60, 60), rng:NextNumber(-40, 0), rng:NextNumber(-50, 50))
		h:insert(i, points[i])
	end
	for _ = 1, 200 do
		local i = rng:NextInteger(1, 3000)
		if rng:NextNumber() < 0.5 then
			points[i] = points[i] + Vector3.new(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10))
			h:move(i, points[i])
		else
			points[i] = nil
			h:remove(i)
		end
	end
	for _ = 1, 50 do
		local q = Vector3.new(rng:NextNumber(-60, 60), -20, rng:NextNumber(-50, 50))
		local r = rng:NextNumber(2, 20)
		local brute, bruteNear, bruteD = {}, nil, math.huge
		for i, p in pairs(points) do
			local dx, dz = p.X - q.X, p.Z - q.Z
			if dx * dx + dz * dz <= r * r then
				brute[i] = true
			end
			local d = (p - q).Magnitude
			if d <= r and d < bruteD then
				bruteNear, bruteD = i, d
			end
		end
		local got = h:query(q, r)
		local n = 0
		for _ in pairs(brute) do
			n += 1
		end
		assert(#got == n, string.format("query returned %d, brute force %d", #got, n))
		for _, k in ipairs(got) do
			assert(brute[k], "query returned a point out of range")
		end
		assert(h:nearest(q, r) == bruteNear, "nearest differs from brute force")
	end
	local count = 0
	for _ in pairs(points) do
		count += 1
	end
	assert(h.size == count, "size bookkeeping")
end)

test("refill queue: slots come back after the delay, in order, a few per tick", function()
	local q = RefillQueue.new()
	for i = 1, 10 do
		q:push(i, 100 + i * 0.1)
	end
	assert(#q:popDue(100) == 0, "refilled before the delay")
	local first = q:popDue(100.35)
	assert(#first == 3 and first[1] == 1 and first[3] == 3, "due order")
	local capped = q:popDue(200, 4)
	assert(#capped == 4 and capped[1] == 4, "max per tick")
	assert(q:size() == 3, "remaining")
	q:clear()
	assert(q:size() == 0 and #q:popDue(1e9) == 0, "clear")
end)

return cases
