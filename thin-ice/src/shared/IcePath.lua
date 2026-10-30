--[[
	IcePath - grid navigation over the lake's tiles (pure, unit-tested in Lune).

	The Antlered walks the tile graph instead of straight lines: open water, rocks and the
	wreck are never crossed. A* over the 8-neighbour grid (a diagonal step needs both
	side tiles open, so it never clips a rock's corner), then the waypoints are string-
	pulled into straight runs where the whole corridor is open ice.

	If the goal itself can't be reached (a sound out over a hole, a player in the water,
	a cut-off island) the path ends on the reachable tile closest to it and `reached` is
	false - the caller treats the end of that path as "as close as it can get".

	The lake is 26 x 50 = 1,300 tiles. The search is capped at IcePath.MaxNodes expansions
	(a cut-off goal can't flood the whole lake), and MonsterService only re-plans on a
	throttle, never per frame.
]]

local GameConfig = require(script.Parent.Config.GameConfig)
local LakeGen = require(script.Parent.LakeGen)

local IcePath = {}

local L = GameConfig.Lake
local COLS = LakeGen.Columns
local ROWS = LakeGen.Rows
local SQRT2 = math.sqrt(2)

local function index(c, r)
	return r * COLS + c
end

local function tileAt(tiles, c, r)
	if c < 0 or c >= COLS or r < 0 or r >= ROWS then
		return nil
	end
	return tiles[LakeGen.key(c, r)]
end

-- Can the monster stand on / walk across this tile?
function IcePath.passable(tile)
	return LakeGen.walkable(tile)
end

function IcePath.open(tiles, c, r)
	return IcePath.passable(tileAt(tiles, c, r))
end

-- Snapshot of which cells are open, indexed r * Columns + c (one string lookup per tile
-- per plan, instead of one per step of the search).
local KEYS = {}
for r = 0, ROWS - 1 do
	for c = 0, COLS - 1 do
		KEYS[index(c, r)] = LakeGen.key(c, r)
	end
end

local function grid(tiles)
	local open = {}
	for idx, k in pairs(KEYS) do
		open[idx] = IcePath.passable(tiles[k])
	end
	return open
end

local function isOpen(open, c, r)
	return c >= 0 and c < COLS and r >= 0 and r < ROWS and open[index(c, r)] == true
end

local function heuristic(c, r, gc, gr)
	local dx, dz = math.abs(c - gc), math.abs(r - gr)
	return math.max(dx, dz) + (SQRT2 - 1) * math.min(dx, dz)
end

-- Minimal binary heap as two parallel arrays (f values, cell indices): no table per entry.
local function push(hf, hi, n, f, idx)
	n += 1
	local i = n
	while i > 1 do
		local parent = i // 2
		if hf[parent] <= f then
			break
		end
		hf[i], hi[i] = hf[parent], hi[parent]
		i = parent
	end
	hf[i], hi[i] = f, idx
	return n
end

local function pop(hf, hi, n)
	local top = hi[1]
	local f, idx = hf[n], hi[n]
	hf[n], hi[n] = nil, nil
	n -= 1
	if n > 0 then
		local i = 1
		while true do
			local l = i * 2
			if l > n then
				break
			end
			if l < n and hf[l + 1] < hf[l] then
				l += 1
			end
			if hf[l] >= f then
				break
			end
			hf[i], hi[i] = hf[l], hi[l]
			i = l
		end
		hf[i], hi[i] = f, idx
	end
	return top, n
end

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

-- The search gives up after expanding this many cells (a goal cut off from the monster
-- would otherwise flood the whole 1,300-tile lake on every re-plan).
IcePath.MaxNodes = GameConfig.Monster.PathNodeCap or 700

--[[
	A* from cell (sc, sr) to (gc, gr). The start may be blocked (it is where the monster
	already is); every other cell on the path is open. Returns:
	  cells    { {c, r}, ... } from the first step to the last cell (empty if already there)
	  reached  true if the last cell is the goal cell
	  capped   true if the search hit IcePath.MaxNodes first (the path ends on the cell
	           closest to the goal found so far: walk it, then plan again from there)
]]
function IcePath.find(tiles, sc, sr, gc, gr, open, maxNodes)
	open = open or grid(tiles)
	maxNodes = maxNodes or IcePath.MaxNodes
	local start = index(sc, sr)
	local goal = index(gc, gr)
	local g = { [start] = 0 }
	local came = {}
	local closed = {}
	local hf, hi, n = {}, {}, 0
	n = push(hf, hi, n, heuristic(sc, sr, gc, gr), start)
	local best, bestH = start, heuristic(sc, sr, gc, gr)
	local expanded, capped = 0, false
	while n > 0 do
		local idx
		idx, n = pop(hf, hi, n)
		if not closed[idx] then
			closed[idx] = true
			if idx == goal then
				best = idx
				break
			end
			expanded += 1
			if expanded > maxNodes then
				capped = true
				break
			end
			local c, r = idx % COLS, idx // COLS
			local h = heuristic(c, r, gc, gr)
			if h < bestH then
				best, bestH = idx, h
			end
			local gi = g[idx]
			for _, off in ipairs(NEIGHBOURS) do
				local dc, dr = off[1], off[2]
				local nc, nr = c + dc, r + dr
				local diagonal = dc ~= 0 and dr ~= 0
				if isOpen(open, nc, nr) and (not diagonal or (isOpen(open, c + dc, r) and isOpen(open, c, r + dr))) then
					local nb = index(nc, nr)
					local cost = gi + (if diagonal then SQRT2 else 1)
					if not closed[nb] and (g[nb] == nil or cost < g[nb]) then
						g[nb] = cost
						came[nb] = idx
						n = push(hf, hi, n, cost + heuristic(nc, nr, gc, gr), nb)
					end
				end
			end
		end
	end
	local cells = {}
	local idx = best
	while idx ~= start do
		table.insert(cells, { idx % COLS, idx // COLS })
		idx = came[idx]
	end
	-- (built goal-first above; reverse once instead of inserting at the front each step)
	local m = #cells
	for i = 1, m // 2 do
		cells[i], cells[m + 1 - i] = cells[m + 1 - i], cells[i]
	end
	return cells, best == goal, capped
end

-- Is the straight walk from a to b (world X/Z) over open tiles all the way, with
-- `radius` studs of clearance either side?
local SIZE = L.TileSize
local HALF_COLS = COLS / 2
local function openAt(open, x, z)
	return isOpen(open, math.floor(x / SIZE + HALF_COLS), math.floor((z - L.ShoreZ) / SIZE))
end

function IcePath.clearLine(tiles, a, b, radius, open)
	open = open or grid(tiles)
	radius = radius or 1.5
	local ax, az = a.X, a.Z
	local dx, dz = b.X - ax, b.Z - az
	local len = math.sqrt(dx * dx + dz * dz)
	local steps = math.max(1, math.ceil(len))
	for i = 0, steps do
		local t = i / steps
		local x, z = ax + dx * t, az + dz * t
		if not (openAt(open, x, z) and openAt(open, x + radius, z + radius) and openAt(open, x + radius, z - radius) and openAt(open, x - radius, z + radius) and openAt(open, x - radius, z - radius)) then
			return false
		end
	end
	return true
end

local PULL_AHEAD = 6

local function centre(c, r)
	local x, z = LakeGen.cellToWorld(c, r)
	return Vector3.new(x, L.IceTop, z)
end

-- Keeps a point inside a tile (with a small margin from its edges).
local function insideCell(p, c, r, margin)
	local x, z = LakeGen.cellToWorld(c, r)
	local h = L.TileSize / 2 - (margin or 0.5)
	return Vector3.new(math.clamp(p.X, x - h, x + h), L.IceTop, math.clamp(p.Z, z - h, z + h))
end

--[[
	World-space plan from `from` to `goal`: a list of waypoints (Vector3 at ice level),
	whether the goal itself is reached, and whether the search was capped (a partial path
	toward it: not "unreachable"). maxNodes overrides IcePath.MaxNodes (tests: math.huge). The last waypoint is the goal point (kept inside
	the last tile), so the monster can step right up to the edge of a hole.
]]
function IcePath.plan(tiles, from, goal, maxNodes)
	local sc, sr = LakeGen.worldToCell(from.X, from.Z)
	local gc, gr = LakeGen.worldToCell(goal.X, goal.Z)
	if not sc or not gc then
		return {}, false
	end
	local open = grid(tiles)
	-- Goal on water / rock: aim the search at the nearest open tile instead (so it doesn't
	-- flood the whole lake looking for a way onto the hole).
	local tc, tr = gc, gr
	if not isOpen(open, gc, gr) then
		local bestD = math.huge
		for idx, ok in pairs(open) do
			if ok then
				local c, r = idx % COLS, idx // COLS
				local d = (c - gc) ^ 2 + (r - gr) ^ 2
				if d < bestD then
					tc, tr, bestD = c, r, d
				end
			end
		end
	end
	local cells, reached, capped = IcePath.find(tiles, sc, sr, tc, tr, open, maxNodes)
	reached = reached and tc == gc and tr == gr
	local points = {}
	for _, cell in ipairs(cells) do
		table.insert(points, centre(cell[1], cell[2]))
	end
	local lastC, lastR = sc, sr
	if #cells > 0 then
		lastC, lastR = cells[#cells][1], cells[#cells][2]
	end
	if isOpen(open, lastC, lastR) then
		local final = insideCell(goal, lastC, lastR)
		if #points > 0 then
			points[#points] = final
		else
			table.insert(points, final)
		end
	end
	-- Off-centre in the start tile with the first step blocked by a corner: go via its centre.
	if #points > 0 and isOpen(open, sc, sr) and not IcePath.clearLine(tiles, from, points[1], 0.5, open) then
		table.insert(points, 1, centre(sc, sr))
	end
	-- String-pull: from each point, jump to the farthest waypoint in clear sight.
	local smooth = {}
	local at = from
	local i = 1
	while i <= #points do
		-- (forward greedy: stop at the first waypoint out of sight, and look at most
		-- PULL_AHEAD waypoints ahead - each check walks the whole line, so an unlimited
		-- look-ahead on a straight cross-lake path cost O(n^2) samples)
		local j = i
		while j < #points and j - i < PULL_AHEAD and IcePath.clearLine(tiles, at, points[j + 1], nil, open) do
			j += 1
		end
		table.insert(smooth, points[j])
		at = points[j]
		i = j + 1
	end
	return smooth, reached, capped
end

-- Cells reachable on foot from the shore (row 0), as a set of keys.
function IcePath.shoreConnected(tiles)
	local seen, queue, head = {}, {}, 1
	for c = 0, COLS - 1 do
		if IcePath.open(tiles, c, 0) then
			seen[LakeGen.key(c, 0)] = true
			table.insert(queue, { c, 0 })
		end
	end
	while head <= #queue do
		local cur = queue[head]
		head += 1
		for i = 1, 4 do
			local off = NEIGHBOURS[i]
			local nc, nr = cur[1] + off[1], cur[2] + off[2]
			local k = LakeGen.key(nc, nr)
			if not seen[k] and IcePath.open(tiles, nc, nr) then
				seen[k] = true
				table.insert(queue, { nc, nr })
			end
		end
	end
	return seen
end

return IcePath
