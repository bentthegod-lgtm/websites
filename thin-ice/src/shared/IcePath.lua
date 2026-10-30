--[[
	IcePath - grid navigation over the lake's tiles (pure, unit-tested in Lune).

	The Antlered walks the tile graph instead of straight lines: open water, rocks and the
	wreck are never crossed. A* over the 8-neighbour grid (a diagonal step needs both
	side tiles open, so it never clips a rock's corner), then the waypoints are string-
	pulled into straight runs where the whole corridor is open ice.

	If the goal itself can't be reached (a sound out over a hole, a player in the water,
	a cut-off island) the path ends on the reachable tile closest to it and `reached` is
	false - the caller treats the end of that path as "as close as it can get".

	It is cheap (the lake is 16 x 32 = 512 tiles) and MonsterService only re-plans on a
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

-- Minimal binary heap of { f, idx }.
local function push(heap, f, idx)
	table.insert(heap, { f, idx })
	local i = #heap
	while i > 1 do
		local parent = i // 2
		if heap[parent][1] <= heap[i][1] then
			break
		end
		heap[parent], heap[i] = heap[i], heap[parent]
		i = parent
	end
end

local function pop(heap)
	local top = heap[1]
	local last = table.remove(heap)
	if #heap > 0 then
		heap[1] = last
		local i, n = 1, #heap
		while true do
			local l, r = i * 2, i * 2 + 1
			local smallest = i
			if l <= n and heap[l][1] < heap[smallest][1] then
				smallest = l
			end
			if r <= n and heap[r][1] < heap[smallest][1] then
				smallest = r
			end
			if smallest == i then
				break
			end
			heap[smallest], heap[i] = heap[i], heap[smallest]
			i = smallest
		end
	end
	return top
end

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

--[[
	A* from cell (sc, sr) to (gc, gr). The start may be blocked (it is where the monster
	already is); every other cell on the path is open. Returns:
	  cells    { {c, r}, ... } from the first step to the last cell (empty if already there)
	  reached  true if the last cell is the goal cell
]]
function IcePath.find(tiles, sc, sr, gc, gr, open)
	open = open or grid(tiles)
	local start = index(sc, sr)
	local goal = index(gc, gr)
	local g = { [start] = 0 }
	local came = {}
	local closed = {}
	local heap = {}
	push(heap, heuristic(sc, sr, gc, gr), start)
	local best, bestH = start, heuristic(sc, sr, gc, gr)
	while #heap > 0 do
		local idx = pop(heap)[2]
		if not closed[idx] then
			closed[idx] = true
			if idx == goal then
				best = idx
				break
			end
			local c, r = idx % COLS, idx // COLS
			local h = heuristic(c, r, gc, gr)
			if h < bestH then
				best, bestH = idx, h
			end
			for _, off in ipairs(NEIGHBOURS) do
				local nc, nr = c + off[1], r + off[2]
				local diagonal = off[1] ~= 0 and off[2] ~= 0
				if isOpen(open, nc, nr) and (not diagonal or (isOpen(open, c + off[1], r) and isOpen(open, c, r + off[2]))) then
					local n = index(nc, nr)
					local cost = g[idx] + (if diagonal then SQRT2 else 1)
					if not closed[n] and (g[n] == nil or cost < g[n]) then
						g[n] = cost
						came[n] = idx
						push(heap, cost + heuristic(nc, nr, gc, gr), n)
					end
				end
			end
		end
	end
	local cells = {}
	local idx = best
	while idx ~= start do
		table.insert(cells, 1, { idx % COLS, idx // COLS })
		idx = came[idx]
	end
	return cells, best == goal
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
	World-space plan from `from` to `goal`: a list of waypoints (Vector3 at ice level) and
	whether the goal itself is reached. The last waypoint is the goal point (kept inside
	the last tile), so the monster can step right up to the edge of a hole.
]]
function IcePath.plan(tiles, from, goal)
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
	local cells, reached = IcePath.find(tiles, sc, sr, tc, tr, open)
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
		-- (forward greedy: stop at the first waypoint out of sight - linear, not quadratic)
		local j = i
		while j < #points and IcePath.clearLine(tiles, at, points[j + 1], nil, open) do
			j += 1
		end
		table.insert(smooth, points[j])
		at = points[j]
		i = j + 1
	end
	return smooth, reached
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
