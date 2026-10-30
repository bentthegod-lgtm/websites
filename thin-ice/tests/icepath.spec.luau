local L = require("./loader")
local LakeGen = L.shared("LakeGen")
local IcePath = L.shared("IcePath")
local GameConfig = L.shared("Config/GameConfig")
local V3 = L.roblox.Vector3

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "IcePath: " .. name, fn = fn })
end

-- An all-ice lake with a few chosen blocked tiles.
local function lake(blocked)
	local tiles = {}
	for r = 0, LakeGen.Rows - 1 do
		for c = 0, LakeGen.Columns - 1 do
			tiles[LakeGen.key(c, r)] = { c = c, r = r, type = "ice", thick = 2 }
		end
	end
	for _, b in ipairs(blocked or {}) do
		tiles[LakeGen.key(b[1], b[2])].type = b[3] or "water"
	end
	return tiles
end

local function pos(c, r)
	local x, z = LakeGen.cellToWorld(c, r)
	return V3.new(x, GameConfig.Lake.IceTop, z)
end

-- Walks the waypoint polyline in small steps; every point must be on open ice.
local function walkable(tiles, from, points)
	local at = from
	for _, p in ipairs(points) do
		local d = (p - at).Magnitude
		local n = math.max(1, math.ceil(d / 0.25))
		for i = 1, n do
			local q = at:Lerp(p, i / n)
			local c, r = LakeGen.worldToCell(q.X, q.Z)
			assert(c and IcePath.open(tiles, c, r), string.format("path crosses a blocked tile at %.1f, %.1f", q.X, q.Z))
		end
		at = p
	end
end

test("goes around a wall of water and rock instead of straight through", function()
	local blocked = {}
	for c = 0, LakeGen.Columns - 2 do
		table.insert(blocked, { c, 10, if c % 2 == 0 then "water" else "rock" })
	end
	local tiles = lake(blocked)
	local points, reached = IcePath.plan(tiles, pos(2, 5), pos(2, 15))
	assert(reached, "goal not reached")
	walkable(tiles, pos(2, 5), points)
	local last = points[#points]
	assert((last - pos(2, 15)).Magnitude < 0.01, "does not end at the goal")
	-- it had to detour to the gap at the far column
	local length, at = 0, pos(2, 5)
	for _, p in ipairs(points) do
		length += (p - at).Magnitude
		at = p
	end
	assert(length > 2 * (LakeGen.Columns - 3) * GameConfig.Lake.TileSize * 0.9, "path too short to have gone round: " .. length)
end)

test("never cuts a rock's corner diagonally", function()
	local tiles = lake({ { 5, 5, "rock" } })
	local cells = IcePath.find(tiles, 4, 4, 6, 6)
	local prevC, prevR = 4, 4
	for _, cell in ipairs(cells) do
		local dc, dr = cell[1] - prevC, cell[2] - prevR
		if dc ~= 0 and dr ~= 0 then
			assert(IcePath.open(tiles, prevC + dc, prevR) and IcePath.open(tiles, prevC, prevR + dr), "clipped a corner")
		end
		prevC, prevR = cell[1], cell[2]
	end
end)

test("unreachable goal: ends on the closest reachable tile, at the hole's edge", function()
	local tiles = lake({ { 8, 20 } })
	local points, reached = IcePath.plan(tiles, pos(8, 10), pos(8, 20))
	assert(not reached, "claimed to reach open water")
	walkable(tiles, pos(8, 10), points)
	local last = points[#points]
	assert((last - pos(8, 20)).Magnitude <= 4.6, "stopped far from the hole: " .. (last - pos(8, 20)).Magnitude)
	-- a sealed-off island
	local ring = {}
	for dc = -1, 1 do
		for dr = -1, 1 do
			if dc ~= 0 or dr ~= 0 then
				table.insert(ring, { 8 + dc, 25 + dr })
			end
		end
	end
	tiles = lake(ring)
	local pts, ok = IcePath.plan(tiles, pos(2, 2), pos(8, 25))
	assert(not ok and #pts > 0, "island")
	walkable(tiles, pos(2, 2), pts)
end)

test("shore-connected set skips islands; generated lakes always path from the shore to every core", function()
	local ring = {}
	for dc = -1, 1 do
		for dr = -1, 1 do
			if dc ~= 0 or dr ~= 0 then
				table.insert(ring, { 8 + dc, 25 + dr })
			end
		end
	end
	local set = IcePath.shoreConnected(lake(ring))
	assert(set[LakeGen.key(0, 0)] and not set[LakeGen.key(8, 25)], "island counted as reachable")
	for seed = 1, 20 do
		local layout = LakeGen.generate(seed, "Nightmare")
		for _, core in ipairs(layout.cores) do
			local points, reached = IcePath.plan(layout.tiles, pos(core.c, 0), pos(core.c, core.r))
			assert(reached, "seed " .. seed .. ": core unreachable")
			walkable(layout.tiles, pos(core.c, 0), points)
		end
	end
end)

return cases
