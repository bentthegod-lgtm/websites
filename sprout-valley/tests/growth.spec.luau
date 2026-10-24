local Growth = require("../src/shared/Growth")
local CropConfig = require("../src/shared/Config/CropConfig")
local GearConfig = require("../src/shared/Config/GearConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Growth: " .. name, fn = fn })
end

local carrot = CropConfig.ById.Carrot
local berry = CropConfig.ById.Strawberry

test("stages go sprout -> small -> full -> ripe", function()
	local plant = { c = "Carrot", g = 0 }
	assert(Growth.stage(plant, carrot) == 1)
	plant.g = carrot.GrowTime * 0.3
	assert(Growth.stage(plant, carrot) == 2)
	plant.g = carrot.GrowTime * 0.7
	assert(Growth.stage(plant, carrot) == 3)
	plant.g = carrot.GrowTime
	assert(Growth.stage(plant, carrot) == 4 and Growth.isRipe(plant, carrot))
end)

test("advance never overshoots and ignores NaN / negative", function()
	local plant = { g = 0 }
	Growth.advance(plant, carrot, 0 / 0)
	Growth.advance(plant, carrot, -5)
	assert(plant.g == 0)
	Growth.advance(plant, carrot, 1e9)
	assert(plant.g == carrot.GrowTime)
end)

test("offline growth uses elapsed time x rate, capped", function()
	local plant = { g = 0 }
	Growth.offline(plant, CropConfig.ById.MoonMelon, 600, 1.25, 86400)
	assert(plant.g == 750, "got " .. plant.g)
	local p2 = { g = 0 }
	Growth.offline(p2, CropConfig.ById.StarlightLotus, 10 ^ 9, 1, 100)
	assert(p2.g == 100, "cap ignored")
	local p3 = { g = 0 }
	Growth.offline(p3, carrot, -50, 1, 100)
	assert(p3.g == 0, "negative elapsed grew the plant")
end)

test("remaining time divides by the growth rate", function()
	local plant = { g = 0 }
	assert(Growth.remaining(plant, carrot, 1) == carrot.GrowTime)
	assert(Growth.remaining(plant, carrot, 1.5) == carrot.GrowTime / 1.5)
end)

test("single-harvest crops are removed, multi-harvest regrow from Full", function()
	local plant = { g = carrot.GrowTime }
	assert(Growth.harvest(plant, carrot) == false)
	local bush = { g = berry.GrowTime, m = { "Wet" }, v = "Golden", lu = true }
	assert(Growth.harvest(bush, berry) == true)
	assert(bush.g == berry.GrowTime - berry.Regrow and bush.h == 1)
	assert(#bush.m == 0 and bush.v == nil and bush.lu == nil, "fruit state not reset")
	assert(Growth.stage(bush, berry) == 3, "regrowing bush should look Full")
	assert(Growth.remaining(bush, berry, 1) == berry.Regrow)
end)

test("tile index <-> col/row round trip", function()
	for index = 1, 60 do
		local col, row = Growth.toColRow(index, 6)
		assert(col >= 1 and col <= 6 and row >= 1 and row <= 10)
		assert(Growth.toIndex(col, row, 6) == index)
	end
end)

test("sprinklers boost tiles in radius until they expire", function()
	local now = 1000
	local sprinklers = { { i = Growth.toIndex(3, 3, 6), k = "Sprinkler", e = now + 10 } }
	assert(Growth.sprinklerMultiplier(Growth.toIndex(4, 4, 6), sprinklers, now, GearConfig, 6) == 1.5)
	assert(Growth.sprinklerMultiplier(Growth.toIndex(5, 3, 6), sprinklers, now, GearConfig, 6) == 1, "outside radius boosted")
	assert(Growth.sprinklerMultiplier(Growth.toIndex(3, 3, 6), sprinklers, now + 11, GearConfig, 6) == 1, "expired sprinkler")
	table.insert(sprinklers, { i = Growth.toIndex(5, 5, 6), k = "ProSprinkler", e = now + 10 })
	assert(Growth.sprinklerMultiplier(Growth.toIndex(4, 4, 6), sprinklers, now, GearConfig, 6) == 1.8, "best sprinkler wins")
	assert(#Growth.pruneSprinklers(sprinklers, now + 11) == 0)
end)

test("watering can advance is a share of grow time, capped", function()
	local can = GearConfig.Gear.WateringCan
	assert(Growth.waterAdvance(carrot, can) == carrot.GrowTime * can.Advance)
	assert(Growth.waterAdvance(CropConfig.ById.StarlightLotus, can) == can.MaxAdvance)
end)

return cases
