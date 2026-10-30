local L = require("./loader")
local LakeGen = L.shared("LakeGen")
local GameConfig = L.shared("Config/GameConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "LakeGen: " .. name, fn = fn })
end

local function same(a, b)
	for k, t in pairs(a.tiles) do
		local u = b.tiles[k]
		if not u or u.type ~= t.type or u.thick ~= t.thick or u.drift ~= t.drift then
			return false
		end
	end
	return true
end

test("same seed + difficulty gives the same lake; different seeds differ", function()
	local a = LakeGen.generate(1234, "Normal")
	local b = LakeGen.generate(1234, "Normal")
	local c = LakeGen.generate(9999, "Normal")
	assert(same(a, b), "not deterministic")
	assert(not same(a, c), "seed ignored")
end)

test("grid size, zones by row, world <-> cell round trip", function()
	local layout = LakeGen.generate(5, "Easy")
	assert(#layout.order == GameConfig.Lake.Columns * LakeGen.Rows)
	assert(LakeGen.zoneOfRow(0) == 1 and LakeGen.zoneOfRow(LakeGen.Rows - 1) == #GameConfig.Zones)
	for _, t in ipairs(layout.order) do
		local x, z = LakeGen.cellToWorld(t.c, t.r)
		local c, r = LakeGen.worldToCell(x, z)
		assert(c == t.c and r == t.r, "round trip failed")
		assert(t.zone == LakeGen.zoneOfRow(t.r))
	end
	assert(LakeGen.worldToCell(0, GameConfig.Lake.ShoreZ - 1) == nil, "shore counted as lake")
	assert(LakeGen.worldToCell(0 / 0, 50) == nil, "NaN accepted")
end)

test("first two rows are always thick solid ice", function()
	for seed = 1, 40 do
		local layout = LakeGen.generate(seed, "Nightmare")
		for c = 0, GameConfig.Lake.Columns - 1 do
			for r = 0, 1 do
				local t = layout.tiles[LakeGen.key(c, r)]
				assert(t.type == "ice" and t.thick == 3, "row " .. r .. " not safe on seed " .. seed)
			end
		end
	end
end)

test("every core and brazier is reachable from the shore, for every difficulty (200 seeds)", function()
	for seed = 1, 50 do
		for _, diff in ipairs(GameConfig.DifficultyOrder) do
			local layout = LakeGen.generate(seed * 7919, diff)
			assert(#layout.cores == GameConfig.Difficulties[diff].Cores, "core count " .. #layout.cores .. " on " .. diff)
			for _, core in ipairs(layout.cores) do
				assert(LakeGen.pathLength(layout, core.c, core.r), "unreachable core seed " .. seed .. " " .. diff)
				assert(core.zone >= 1 and core.r >= 2, "core on the safe rows")
			end
			for _, b in ipairs(layout.braziers) do
				assert(LakeGen.pathLength(layout, b.c, b.r), "unreachable brazier")
			end
		end
	end
end)

test("harder difficulties: more thin ice + holes, fewer braziers", function()
	local thin, holes, braziers = {}, {}, {}
	for _, diff in ipairs(GameConfig.DifficultyOrder) do
		thin[diff], holes[diff], braziers[diff] = 0, 0, 0
		for seed = 1, 20 do
			local s = LakeGen.summary(LakeGen.generate(seed, diff))
			thin[diff] += s.thin
			holes[diff] += s.water
			braziers[diff] += s.brazier
		end
	end
	assert(thin.Easy < thin.Normal and thin.Normal < thin.Hard and thin.Hard < thin.Nightmare, "thin ice not scaling")
	assert(holes.Easy < holes.Nightmare, "holes not scaling")
	assert(braziers.Easy > braziers.Nightmare, "braziers not scaling")
end)

test("zones look different: Thin Flats thinnest, Boulder Isles rockiest, wreck in Wreck Bay", function()
	local thin, rock = { 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0 }
	for seed = 1, 20 do
		local layout = LakeGen.generate(seed, "Normal")
		for _, t in ipairs(layout.order) do
			if t.type == "ice" and t.thick == 1 then
				thin[t.zone] += 1
			elseif t.type == "rock" then
				rock[t.zone] += 1
			end
		end
		assert(#layout.wreck == 6, "wreck size")
		for _, t in ipairs(layout.wreck) do
			assert(t.zone == 4, "wreck outside Wreck Bay")
		end
		assert(#layout.drifts >= 14, "not enough drifts for the bigger lake")
	end
	assert(thin[2] > thin[1] and thin[2] > thin[3], "Thin Flats not the thinnest")
	assert(rock[3] > rock[1] and rock[3] > rock[2] and rock[3] > rock[4] and rock[3] > rock[5], "Boulder Isles not the rockiest")
end)

test("bigger lake: 26 x 50 tiles, 5 zones, 400 studs out", function()
	assert(#GameConfig.Zones == 5 and GameConfig.Zones[5].Id == "DeepHollow")
	assert(GameConfig.Lake.Columns >= 24 and GameConfig.Lake.Columns <= 28, "width")
	assert(LakeGen.Rows == 50 and LakeGen.Rows * GameConfig.Lake.TileSize == 400, "length")
	local _, zFar = LakeGen.cellToWorld(0, LakeGen.Rows - 1)
	assert(zFar > 430, "far edge " .. zFar)
end)

test("The Deep Hollow: half-sunken lighthouse ringed by ice spires, cores out there, the monster sleeps there", function()
	for seed = 1, 40 do
		local layout = LakeGen.generate(seed * 31, "Easy")
		local lc, lr = layout.landmarkCell[1], layout.landmarkCell[2]
		assert(LakeGen.zoneOfRow(lr) == 5 and LakeGen.zoneOfRow(lr + 1) == 5, "lighthouse outside the Deep Hollow")
		for dc = 0, 1 do
			for dr = 0, 1 do
				assert(layout.tiles[LakeGen.key(lc + dc, lr + dr)].type == "landmark", "lighthouse carved through")
			end
		end
		assert(#layout.spires >= 6, "spires " .. #layout.spires)
		local deep = 0
		for _, core in ipairs(layout.cores) do
			if core.zone == 5 then
				deep += 1
			end
		end
		assert(deep >= 1, "no core in the Deep Hollow")
		assert(LakeGen.zoneOfRow(layout.monsterCell[2]) == 5)
		assert(not LakeGen.walkable(layout.tiles[LakeGen.key(lc, lr)]), "lighthouse walkable")
	end
end)

return cases
