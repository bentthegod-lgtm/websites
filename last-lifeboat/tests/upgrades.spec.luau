local L = require("./loader")
local GameConfig = L.shared("Config/GameConfig")
local Upgrades = L.shared("Upgrades")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Upgrades: " .. name, fn = fn })
end

test("five upgrades, five levels each, rising costs, maxed returns nil", function()
	assert(#GameConfig.UpgradeOrder == 5)
	for _, key in ipairs(GameConfig.UpgradeOrder) do
		local def = GameConfig.Upgrades[key]
		assert(#def.Costs == 5 and #def.Effects == 6, key)
		local prev = 0
		for level = 0, 4 do
			local cost = Upgrades.cost(key, level)
			assert(cost and cost > prev, key .. " cost not rising")
			prev = cost
		end
		assert(Upgrades.cost(key, 5) == nil and Upgrades.cost(key, 99) == nil)
		assert(Upgrades.totalCost(key) >= 2000 and Upgrades.totalCost(key) <= 8000, key .. " total " .. Upgrades.totalCost(key))
	end
	assert(Upgrades.cost("Nope", 0) == nil and Upgrades.effect("Nope", 0) == nil)
end)

test("effects are monotonic and bounded", function()
	local bounds = { Lungs = { 12, 30 }, Swim = { 1, 1.5 }, Grip = { 0.25, 1 }, Slots = { 3, 6 }, Climb = { 1, 1.6 } }
	for key, b in pairs(bounds) do
		local prev = nil
		for level = 0, 5 do
			local e = Upgrades.effect(key, level)
			assert(e >= b[1] and e <= b[2], key .. " out of bounds at " .. level)
			if prev then
				if key == "Grip" then
					assert(e <= prev, "grip should reduce sliding")
				else
					assert(e >= prev, key .. " decreases")
				end
			end
			prev = e
		end
	end
	assert(Upgrades.effect("Lungs", -3) == 12 and Upgrades.effect("Lungs", 0 / 0) == 12 and Upgrades.effect("Lungs", 9) == 25, "clamping")
	local all = Upgrades.effects({ Lungs = 2 })
	assert(all.Lungs == 17 and all.Slots == 3)
end)

return cases
