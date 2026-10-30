local L = require("./loader")
local GameConfig = L.shared("Config/GameConfig")
local Survival = L.shared("Survival")
local Upgrades = L.shared("Upgrades")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Survival: " .. name, fn = fn })
end

test("oxygen drains 1/s underwater, runs out exactly once, refills above water", function()
	local max = GameConfig.Oxygen.Base
	local o, out = max, false
	local outs = 0
	for _ = 1, math.floor(max * 30) + 30 do
		o, out = Survival.stepOxygen(o, max, true, 1 / 30)
		if out then
			outs += 1
		end
	end
	assert(o == 0 and outs == 1, "ran out " .. outs .. " times")
	local t = 0
	while o < max do
		o = Survival.stepOxygen(o, max, false, 0.1)
		t += 0.1
	end
	assert(o == max and t <= max / GameConfig.Oxygen.Regen + 0.2, "regen too slow: " .. t)
end)

test("base breath is 12 s; Lung Capacity raises it, bounded", function()
	assert(GameConfig.Oxygen.Base == 12 and Upgrades.effect("Lungs", 0) == 12)
	local o, t = Upgrades.effect("Lungs", 5), 0
	local max = o
	while o > 0 do
		o = Survival.stepOxygen(o, max, true, 0.05)
		t += 0.05
	end
	assert(math.abs(t - max) < 0.1 and max <= 30, "max breath " .. max)
end)

test("head underwater test uses the sea level", function()
	assert(Survival.headUnderwater(-1, 0) and not Survival.headUnderwater(0.5, 0) and not Survival.headUnderwater(-0.2, 0))
end)

test("zap and revive oxygen", function()
	assert(Survival.zap(10) == 10 - GameConfig.Oxygen.ZapLoss and Survival.zap(1) == 0)
	assert(Survival.reviveOxygen(12) == 6, "revive should give 50%")
end)

test("bleed-out after 20 s; revive takes a 2 s hold", function()
	assert(GameConfig.Downed.BleedOut == 20 and GameConfig.Downed.ReviveHold == 2)
	assert(not Survival.bledOut(100, 119.9) and Survival.bledOut(100, 120))
	assert(math.abs(Survival.bleedLeft(100, 105) - 15) < 1e-9 and Survival.bleedLeft(100, 200) == 0)
	assert(Survival.reviveProgress(nil, 5) == 0 and Survival.reviveProgress(10, 11) == 0.5 and Survival.reviveProgress(10, 30) == 1)
end)

test("life jacket: needs one owned, one per round", function()
	assert(Survival.jacketAvailable(2, 0) and not Survival.jacketAvailable(2, 1) and not Survival.jacketAvailable(0, 0))
end)

test("downed bodies float up to the surface but never through a ceiling", function()
	assert(Survival.floatY(-10, 0, nil) == 0.5)
	assert(Survival.floatY(-10, 0, -4) == -4 - GameConfig.Downed.FloatClearance)
	assert(Survival.floatY(5, 0, nil) == 5, "a body above water must not sink")
end)

return cases
