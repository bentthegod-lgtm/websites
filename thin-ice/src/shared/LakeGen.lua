--[[
	LakeGen - pure, seeded generation of the frozen lake (no Roblox instances).

	The lake is a grid of square tiles: columns across, rows away from the shore. Row 0 is
	the edge by the lobby plaza; rows are grouped into five zones (Pine Shallows, Thin
	Flats, Boulder Isles, Wreck Bay, The Deep Hollow). Each tile is one of:
	  ice      walkable; thick = 1 (thin), 2 (normal) or 3 (thick) - see GameConfig.Ice
	  water    an open hole (you fall in)
	  rock     a boulder or ice-crystal cluster (blocks you)
	  wreck    part of the wrecked boat in Wreck Bay (blocks you)
	  brazier  thick ice with a fire on it (never breaks, warms you)
	  landmark the half-sunken lighthouse in The Deep Hollow (blocks you; ringed by ice spires,
	           which are "rock" tiles with style "spire")

	The same seed + difficulty always gives the same lake. generate() also guarantees that
	every frozen core can be walked to from the shore and back (it carves a path of ice
	if the random layout cut one off).
]]

local GameConfig = require(script.Parent.Config.GameConfig)
local Rng = require(script.Parent.Rng)

local LakeGen = {}

local L = GameConfig.Lake
LakeGen.Columns = L.Columns
LakeGen.Rows = L.RowsPerZone * #GameConfig.Zones

local function key(c, r)
	return c .. "," .. r
end
LakeGen.key = key

-- Centre of a tile in world X / Z.
function LakeGen.cellToWorld(c, r)
	local x = (c - L.Columns / 2 + 0.5) * L.TileSize
	local z = L.ShoreZ + (r + 0.5) * L.TileSize
	return x, z
end

-- Tile under a world X / Z (nil, nil if off the lake).
function LakeGen.worldToCell(x, z)
	if x ~= x or z ~= z then
		return nil, nil
	end
	local c = math.floor(x / L.TileSize + L.Columns / 2)
	local r = math.floor((z - L.ShoreZ) / L.TileSize)
	if c < 0 or c >= L.Columns or r < 0 or r >= LakeGen.Rows then
		return nil, nil
	end
	return c, r
end

function LakeGen.zoneOfRow(r)
	return math.clamp(math.floor(r / L.RowsPerZone) + 1, 1, #GameConfig.Zones)
end

function LakeGen.walkable(tile)
	return tile ~= nil and (tile.type == "ice" or tile.type == "brazier")
end

-- Breadth-first search over walkable tiles from any tile in row 0 to (c, r).
-- Returns the path length in tiles, or nil if unreachable.
function LakeGen.pathLength(layout, c, r)
	local target = key(c, r)
	local seen, queue, head = {}, {}, 1
	for col = 0, L.Columns - 1 do
		local t = layout.tiles[key(col, 0)]
		if LakeGen.walkable(t) then
			seen[key(col, 0)] = 1
			table.insert(queue, { col, 0 })
		end
	end
	while head <= #queue do
		local cur = queue[head]
		head += 1
		local d = seen[key(cur[1], cur[2])]
		if key(cur[1], cur[2]) == target then
			return d
		end
		for _, off in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local nc, nr = cur[1] + off[1], cur[2] + off[2]
			local k = key(nc, nr)
			if not seen[k] and LakeGen.walkable(layout.tiles[k]) then
				seen[k] = d + 1
				table.insert(queue, { nc, nr })
			end
		end
	end
	return nil
end

-- Opens a route from (c, r) back to the shore: the route that turns the FEWEST blocked tiles
-- into ice (0-1 BFS: open ice costs 0, a hole / rock costs 1; the lighthouse is never cut
-- through). Thickness 2, so the carved tiles are safe to walk once.
local function carve(layout, c, r)
	local cost, from = {}, {}
	local deque, head, tail = {}, 0, 0
	local start = key(c, r)
	cost[start] = 0
	deque[tail] = { start, c, r }
	tail += 1
	local goal
	while head < tail do
		local cur = deque[head]
		deque[head] = nil
		head += 1
		local ck, cc, rr = cur[1], cur[2], cur[3]
		if rr == 0 then
			goal = ck
			break
		end
		for _, off in ipairs({ { 0, -1 }, { 1, 0 }, { -1, 0 }, { 0, 1 } }) do
			local nc, nr = cc + off[1], rr + off[2]
			local nk = key(nc, nr)
			local t = layout.tiles[nk]
			if t and t.type ~= "landmark" then
				local step = if LakeGen.walkable(t) then 0 else 1
				if cost[nk] == nil or cost[ck] + step < cost[nk] then
					cost[nk] = cost[ck] + step
					from[nk] = ck
					if step == 0 then
						head -= 1
						deque[head] = { nk, nc, nr }
					else
						deque[tail] = { nk, nc, nr }
						tail += 1
					end
				end
			end
		end
	end
	local k = goal
	while k do
		local t = layout.tiles[k]
		if not LakeGen.walkable(t) then
			t.type = "ice"
			t.thick = 2
			t.style = nil
		end
		k = from[k]
	end
end

-- Zones the cores go to, in order: every difficulty has at least one in The Deep Hollow.
local CORE_ZONES = { 2, 3, 4, 5, 3, 4, 5, 2 }

function LakeGen.generate(seed, difficultyName)
	local diff = GameConfig.Difficulties[difficultyName] or GameConfig.Difficulties.Normal
	local rng = Rng.new(seed)
	local layout = {
		seed = seed,
		difficulty = difficultyName,
		columns = L.Columns,
		rows = LakeGen.Rows,
		tiles = {},
		order = {},
		cores = {},
		braziers = {},
		drifts = {},
		wreck = {},
	}

	-- 1. Base tiles, zone by zone.
	for r = 0, LakeGen.Rows - 1 do
		local zoneIndex = LakeGen.zoneOfRow(r)
		local zone = GameConfig.Zones[zoneIndex]
		for c = 0, L.Columns - 1 do
			local t = { c = c, r = r, zone = zoneIndex, type = "ice", thick = 2 }
			if r <= 1 then
				t.thick = 3 -- the first two rows are always safe
			else
				local roll = rng:NextNumber()
				local hole = zone.Holes * diff.HoleScale
				local rock = zone.Rocks
				local thin = zone.Thin * diff.ThinScale
				if roll < hole then
					t.type = "water"
				elseif roll < hole + rock then
					t.type = "rock"
					t.style = if rng:NextNumber() < 0.45 then "crystal" else "boulder"
				elseif roll < hole + rock + thin then
					t.thick = 1
				else
					t.thick = if rng:NextNumber() < (if zoneIndex == 1 then 0.55 else 0.25) then 3 else 2
				end
			end
			layout.tiles[key(c, r)] = t
			table.insert(layout.order, t)
		end
	end

	-- 2. The wrecked boat: a 2 x 3 block of tiles in Wreck Bay.
	do
		local zoneStart = 3 * L.RowsPerZone
		local wc = rng:NextInteger(3, L.Columns - 5)
		local wr = rng:NextInteger(zoneStart + 2, zoneStart + 4)
		for dc = 0, 1 do
			for dr = 0, 2 do
				local t = layout.tiles[key(wc + dc, wr + dr)]
				t.type = "wreck"
				t.style = nil
				table.insert(layout.wreck, t)
			end
		end
		layout.wreckCell = { wc, wr }
	end

	-- 2b. The Deep Hollow's landmark: a half-sunken lighthouse (2 x 2 tiles) in the middle of
	-- the zone, ringed by eight standing ice spires.
	do
		local zones = #GameConfig.Zones
		local lc = L.Columns // 2 - 1
		local lr = (zones - 1) * L.RowsPerZone + L.RowsPerZone // 2 - 1
		for dc = 0, 1 do
			for dr = 0, 1 do
				local t = layout.tiles[key(lc + dc, lr + dr)]
				t.type = "landmark"
				t.style = nil
			end
		end
		layout.landmarkCell = { lc, lr }
		layout.spires = {}
		for i = 0, 7 do
			local a = i * math.pi / 4
			local sc = math.floor(lc + 0.5 + math.cos(a) * 3.6 + 0.5)
			local sr = math.floor(lr + 0.5 + math.sin(a) * 3.6 + 0.5)
			local t = layout.tiles[key(sc, sr)]
			if t and t.type ~= "landmark" and t.type ~= "wreck" then
				t.type = "rock"
				t.style = "spire"
				table.insert(layout.spires, t)
			end
		end
	end

	-- Picks a random plain-ice tile in a zone (not reserved).
	local reserved = {}
	local function pickIce(zoneIndex, minRow)
		local r0 = (zoneIndex - 1) * L.RowsPerZone
		for _ = 1, 200 do
			local c = rng:NextInteger(1, L.Columns - 2)
			local r = rng:NextInteger(math.max(r0, minRow or r0), r0 + L.RowsPerZone - 1)
			local t = layout.tiles[key(c, r)]
			if t.type == "ice" and not reserved[key(c, r)] then
				reserved[key(c, r)] = true
				return t
			end
		end
		return nil
	end

	-- The monster sleeps at the far end of The Deep Hollow, off to one side. Nothing you
	-- need (a core or a fire) is placed within SleepClear tiles of it, so it can't wake
	-- right on top of someone chipping a core.
	layout.monsterCell = { 4, LakeGen.Rows - 2 }
	do
		local mc, mr = layout.monsterCell[1], layout.monsterCell[2]
		local clear = GameConfig.Monster.SleepClear
		for dc = -clear, clear do
			for dr = -clear, clear do
				reserved[key(mc + dc, mr + dr)] = true
			end
		end
	end

	-- 3. Braziers spread over the zones (round-robin), on solid ice.
	for i = 1, diff.Braziers do
		local t = pickIce(((i - 1) % #GameConfig.Zones) + 1, 2)
		if t then
			t.type = "brazier"
			t.thick = 3
			table.insert(layout.braziers, t)
		end
	end

	-- 4. Frozen cores, mostly out in the deeper zones.
	for i = 1, diff.Cores do
		local t = pickIce(CORE_ZONES[((i - 1) % #CORE_ZONES) + 1], 2)
		if t then
			t.thick = 3 -- the block sits on solid ice
			table.insert(layout.cores, { id = "Core" .. i, c = t.c, r = t.r, zone = t.zone })
		end
	end

	-- 5. Snow drifts (refill snowballs).
	for zoneIndex, zone in ipairs(GameConfig.Zones) do
		for _ = 1, zone.Drifts do
			local t = pickIce(zoneIndex)
			if t then
				t.drift = true
				table.insert(layout.drifts, t)
			end
		end
	end

	-- 6. Make sure every core and brazier can be reached from the shore.
	for _, core in ipairs(layout.cores) do
		if not LakeGen.pathLength(layout, core.c, core.r) then
			carve(layout, core.c, core.r)
		end
	end
	for _, b in ipairs(layout.braziers) do
		if not LakeGen.pathLength(layout, b.c, b.r) then
			carve(layout, b.c, b.r)
		end
	end

	return layout
end

-- Counts tile types (for tests and the debug overlay).
function LakeGen.summary(layout)
	local counts = { ice = 0, water = 0, rock = 0, wreck = 0, brazier = 0, landmark = 0, thin = 0 }
	for _, t in ipairs(layout.order) do
		counts[t.type] += 1
		if t.type == "ice" and t.thick == 1 then
			counts.thin += 1
		end
	end
	return counts
end

return LakeGen
