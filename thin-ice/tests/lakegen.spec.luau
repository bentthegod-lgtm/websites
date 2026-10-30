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
	local thin, rock = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
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
		assert(#layout.drifts >= 6, "not enough drifts")
	end
	assert(thin[2] > thin[1] and thin[2] > thin[3], "Thin Flats not the thinnest")
	assert(rock[3] > rock[1] and rock[3] > rock[2] and rock[3] > rock[4], "Boulder Isles not the rockiest")
end)

return cases
