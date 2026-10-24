local Economy = require("../src/shared/Economy")
local Rng = require("../src/shared/Rng")
local Format = require("../src/shared/Format")
local MutationConfig = require("../src/shared/Config/MutationConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local ShopConfig = require("../src/shared/Config/ShopConfig")
local CropConfig = require("../src/shared/Config/CropConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Economy: " .. name, fn = fn })
end

local carrot = CropConfig.ById.Carrot

test("value at base weight with no mutations equals crop value", function()
	assert(Economy.fruitValue(carrot, carrot.BaseKg, {}, nil, MutationConfig) == carrot.Value)
end)

test("value scales linearly with weight", function()
	local v = Economy.fruitValue(carrot, carrot.BaseKg * 2, {}, nil, MutationConfig)
	assert(v == carrot.Value * 2, "got " .. v)
end)

test("environmental mutations stack additively", function()
	-- Wet (2x) + Shocked (6x) = 1 + 1 + 5 = 7x
	local m = Economy.mutationMultiplier({ "Wet", "Shocked" }, nil, MutationConfig)
	assert(m == 7, "got " .. m)
end)

test("variant multiplies the stacked total", function()
	local m = Economy.mutationMultiplier({ "Wet", "Shocked" }, "Golden", MutationConfig)
	assert(m == 70, "got " .. m)
	assert(Economy.mutationMultiplier({}, "Rainbow", MutationConfig) == 40)
end)

test("unknown mutation names are ignored", function()
	assert(Economy.mutationMultiplier({ "Bogus" }, "Nope", MutationConfig) == 1)
end)

test("Wet + Chilled combine into Frozen", function()
	local list = {}
	assert(Economy.addMutation(list, "Wet", MutationConfig))
	assert(Economy.addMutation(list, "Chilled", MutationConfig))
	assert(#list == 1 and list[1] == "Frozen", table.concat(list, ","))
	-- A frozen fruit can't be made Wet again, but can still be Shocked.
	assert(not Economy.addMutation(list, "Wet", MutationConfig))
	assert(Economy.addMutation(list, "Shocked", MutationConfig))
	assert(not Economy.addMutation(list, "Shocked", MutationConfig), "duplicate added")
	assert(Economy.mutationMultiplier(list, nil, MutationConfig) == 1 + 7 + 5)
end)

test("mutation chance boosts are bounded by the cap", function()
	local base = 0.05
	assert(Economy.mutationChance(base, false, false, MutationConfig) == base)
	assert(math.abs(Economy.mutationChance(base, true, true, MutationConfig) - 0.15) < 1e-9)
	assert(Economy.mutationChance(0.5, true, true, MutationConfig) == MutationConfig.ChanceCap)
end)

test("weight roll stays in the expected band and Huge is rare", function()
	local rng = Rng.new(42)
	local huge = 0
	for _ = 1, 20000 do
		local kg, isHuge = Economy.rollWeight(carrot, rng, GameConfig.HugeChance)
		if isHuge then
			huge += 1
			assert(kg <= carrot.BaseKg * 1.45 * 4 + 0.01, "huge too big " .. kg)
		else
			assert(kg >= carrot.BaseKg * 0.75 - 0.01 and kg <= carrot.BaseKg * 1.45 + 0.01, "kg out of band " .. kg)
		end
	end
	local rate = huge / 20000
	assert(rate > 0.012 and rate < 0.03, "huge rate " .. rate)
end)

test("natural variants: Rainbow rarer than Golden, pass boosts both", function()
	local rng = Rng.new(5)
	local counts = { Golden = 0, Rainbow = 0 }
	for _ = 1, 200000 do
		local v = Economy.rollVariant(rng, false, MutationConfig)
		if v then
			counts[v] += 1
		end
	end
	assert(counts.Golden > 1600 and counts.Golden < 2400, "golden " .. counts.Golden)
	assert(counts.Rainbow > 120 and counts.Rainbow < 290, "rainbow " .. counts.Rainbow)
end)

test("sell multiplier: pass doubles, friends add 10% each up to 30%", function()
	assert(Economy.sellMultiplier(false, 0, GameConfig, ShopConfig) == 1)
	assert(Economy.sellMultiplier(true, 0, GameConfig, ShopConfig) == 2)
	assert(math.abs(Economy.sellMultiplier(false, 2, GameConfig, ShopConfig) - 1.2) < 1e-9)
	assert(math.abs(Economy.sellMultiplier(true, 9, GameConfig, ShopConfig) - 2.6) < 1e-9)
end)

test("expansion cost grows and rows are capped (VIP adds a row)", function()
	local plot = GameConfig.Plot
	assert(Economy.expansionCost(0, plot) == plot.ExpansionBaseCost)
	assert(Economy.expansionCost(1, plot) > Economy.expansionCost(0, plot))
	assert(Economy.unlockedRows(0, false, plot) == plot.StartRows)
	assert(Economy.unlockedRows(0, true, plot) == plot.StartRows + plot.VipBonusRows)
	assert(Economy.unlockedRows(99, true, plot) == plot.Rows)
	assert(Economy.canExpand(plot.Rows - plot.StartRows - 1, false, plot))
	assert(not Economy.canExpand(plot.Rows - plot.StartRows, false, plot))
	assert(not Economy.canExpand(plot.Rows - plot.StartRows - 1, true, plot))
end)

test("itemsValue sums fruit and skips unknown crops", function()
	local items = {
		{ c = "Carrot", kg = carrot.BaseKg, m = {}, v = nil },
		{ c = "Carrot", kg = carrot.BaseKg, m = { "Wet" }, v = nil },
		{ c = "NotACrop", kg = 1, m = {} },
	}
	assert(Economy.itemsValue(items, CropConfig.ById, MutationConfig) == carrot.Value * 3)
end)

test("Format helpers", function()
	assert(Format.coins(1234) == "1,234", Format.coins(1234))
	assert(Format.coins(999) == "999")
	assert(Format.coins(123456) == "123.45K", Format.coins(123456))
	assert(Format.coins(1500000) == "1.5M", Format.coins(1500000))
	assert(Format.coins(100000000) == "100M", Format.coins(100000000))
	assert(Format.clock(125) == "2:05")
	assert(Format.duration(3725) == "1h 02m")
	assert(Format.kg(0.3) == "0.30kg")
end)

return cases
