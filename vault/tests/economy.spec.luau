local L = require("./loader")
local Economy = L.shared("Economy")
local LootTable = L.shared("LootTable")
local UpgradeConfig = L.shared("Config/UpgradeConfig")
local DepthConfig = L.shared("Config/DepthConfig")
local LootConfig = L.shared("Config/LootConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Economy: " .. name, fn = fn })
end

local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

test("base stats match the documented starting values", function()
	local s = Economy.stats(nil)
	assert(near(s.PickupInterval, 0.65), "pickup interval")
	assert(s.Radius == 7 and s.Capacity == 10 and s.WalkSpeed == 16, "base radius / capacity / speed")
	assert(s.MagnetRadius == 0 and s.AutoRadius == 0, "magnet and auto-collect start off")
	assert(s.ValueMult == 1 and s.DepositMult == 1 and s.Luck == 1, "multipliers start at 1")
end)

test("every upgrade level changes its stat in the right direction", function()
	local fields = {
		PickupSpeed = { "PickupInterval", -1 },
		CollectionRadius = { "Radius", 1 },
		CashMagnet = { "MagnetRadius", 1 },
		AutoCollect = { "AutoRadius", 1 },
		CarryCapacity = { "Capacity", 1 },
		StackSize = { "Capacity", 1 },
		AdvancedCapacity = { "LargeSlotFactor", -1 },
		MoveSpeed = { "WalkSpeed", 1 },
		LootValue = { "ValueMult", 1 },
		DepositBonus = { "DepositMult", 1 },
		RareLuck = { "Luck", 1 },
	}
	for _, def in ipairs(UpgradeConfig.List) do
		local field = fields[def.Key]
		assert(field, "no stat mapped for " .. def.Key)
		local base = { Upgrades = { CarryCapacity = 4 } } -- StackSize needs a capacity to scale
		for level = 0, def.Max - 1 do
			local a = table.clone(base.Upgrades)
			a[def.Key] = level
			local b = table.clone(base.Upgrades)
			b[def.Key] = level + 1
			local va = Economy.stats({ Upgrades = a })[field[1]]
			local vb = Economy.stats({ Upgrades = b })[field[1]]
			local moved = (vb - va) * field[2]
			-- Pickup speed may hit the floor; luck is capped at 2x.
			assert(moved > 0 or (def.Key == "PickupSpeed" and near(vb, 0.15)) or (def.Key == "RareLuck" and near(vb, 2)), string.format("%s level %d -> %d did not improve %s (%s -> %s)", def.Key, level, level + 1, field[1], tostring(va), tostring(vb)))
		end
	end
end)

test("upgrade prices rise every level and stop at max", function()
	for _, def in ipairs(UpgradeConfig.List) do
		local last = 0
		for level = 0, def.Max - 1 do
			local price = Economy.upgradeCost(def.Key, level)
			assert(price and price > last, def.Key .. " price did not rise at level " .. level)
			last = price
		end
		assert(Economy.upgradeCost(def.Key, def.Max) == nil, def.Key .. " should be maxed")
	end
	for _, def in ipairs(UpgradeConfig.Perks) do
		assert(#def.Costs == def.Max, def.Key .. " needs one cost per level")
		assert(Economy.perkCost(def.Key, def.Max) == nil, def.Key .. " should be maxed")
	end
end)

test("advanced upgrades are gated by depth (magnet and auto-collect come late)", function()
	assert(UpgradeConfig.ByKey.CashMagnet.UnlockDepth >= 3, "magnet too early")
	assert(UpgradeConfig.ByKey.AutoCollect.UnlockDepth >= 5, "auto-collect too early")
	assert(UpgradeConfig.ByKey.AdvancedCapacity.UnlockDepth >= 4, "advanced capacity too early")
	for _, def in ipairs(UpgradeConfig.List) do
		assert(DepthConfig.get(def.UnlockDepth), def.Key .. " unlock depth missing")
	end
end)

test("large items use fewer slots with Advanced Capacity, never below one", function()
	local big
	for _, def in ipairs(LootConfig.List) do
		if def.Slots >= 3 then
			big = def
			break
		end
	end
	assert(big, "expected an item with 3+ slots")
	local s0 = Economy.slotsFor(big, Economy.stats(nil))
	local s6 = Economy.slotsFor(big, Economy.stats({ Upgrades = { AdvancedCapacity = 6 } }))
	assert(s6 < s0 and s6 >= 1, "advanced capacity should shrink big items")
	for _, def in ipairs(LootConfig.List) do
		if def.Slots <= 1 then
			assert(Economy.slotsFor(def, Economy.stats({ Upgrades = { AdvancedCapacity = 6 } })) == 1, "small items stay 1 slot")
		end
	end
end)

test("value boost, rebirth, perks and VIP multiply value / payout modestly", function()
	local now = 1000
	local plain = Economy.stats({}, now)
	local boosted = Economy.stats({ BoostUntil = now + 60 }, now)
	local expired = Economy.stats({ BoostUntil = now - 1 }, now)
	assert(near(boosted.ValueMult, 1.25) and near(expired.ValueMult, 1), "boost only while active")
	assert(near(Economy.stats({ Rebirths = 2 }).ValueMult, 1.5), "rebirth +25% each")
	assert(near(Economy.stats({ Perks = { GoldenTouch = 5 } }).ValueMult, 1.5), "golden touch")
	assert(near(Economy.stats({ Vip = true }).DepositMult, 1.1), "VIP is +10% payout only")
	assert(Economy.stats({ Vip = true }).Capacity == plain.Capacity, "VIP gives no capacity")
	assert(Economy.depositPayout(1000, Economy.stats({ Upgrades = { DepositBonus = 4 } })) == 1200, "deposit bonus")
	assert(Economy.depositPayout(0 / 0, plain) == 0 and Economy.depositPayout(-5, plain) == 0, "bad payouts are 0")
end)

test("each depth's loot is worth clearly more than the one above", function()
	for d = 2, DepthConfig.Count do
		local above = LootTable.averageValue(d - 1, 1) / LootTable.averageSlots(d - 1)
		local here = LootTable.averageValue(d, 1) / LootTable.averageSlots(d)
		assert(here > above * 4, string.format("depth %d value per slot %.1f vs %.1f above", d, here, above))
	end
end)

-- A greedy player: fill the stack, deposit, buy the cheapest useful upgrade (or unlock
-- the next depth as soon as it is affordable), repeat. Tokens trickle in from
-- achievements / dailies at a conservative rate. Returns trips needed to reach each depth.
local function simulate(maxTrips)
	local state = { Upgrades = {}, Perks = {}, Rebirths = 0 }
	local cash, tokens, depth = 0, 0, 1
	local reached = { [1] = 0 }
	local totalSeconds = 0
	for trip = 1, maxTrips do
		local s = Economy.stats(state)
		local perSlot = LootTable.averageValue(depth, s.Luck) * s.ValueMult / LootTable.averageSlots(depth)
		local carried = math.floor(s.Capacity * perSlot)
		cash += Economy.depositPayout(carried, s)
		tokens += 0.35
		-- Trip time: pickups (or magnet/auto) plus walking to and from the machine.
		local perPickup = if s.AutoRadius > 0 then math.min(s.PickupInterval, s.AutoInterval) else s.PickupInterval
		totalSeconds += s.Capacity / LootTable.averageSlots(depth) * (perPickup + 1.6 / (1 + s.MagnetRadius / 20)) + 70 * 16 / s.WalkSpeed / 4
		local nextDef = DepthConfig.get(depth + 1)
		if nextDef and cash >= nextDef.UnlockCash and tokens >= nextDef.UnlockTokens then
			cash -= nextDef.UnlockCash
			tokens -= nextDef.UnlockTokens
			depth += 1
			reached[depth] = trip
		else
			-- Spend most of the money on upgrades, saving toward the next depth only when close.
			local saving = nextDef and cash >= nextDef.UnlockCash * 0.6
			if not saving then
				for _ = 1, 20 do
					local best, bestCost
					for _, def in ipairs(UpgradeConfig.List) do
						if depth >= def.UnlockDepth then
							local cost = Economy.upgradeCost(def.Key, state.Upgrades[def.Key] or 0)
							if cost and cost <= cash and (not bestCost or cost < bestCost) then
								best, bestCost = def, cost
							end
						end
					end
					if not best then
						break
					end
					cash -= bestCost
					state.Upgrades[best.Key] = (state.Upgrades[best.Key] or 0) + 1
				end
			end
		end
		if depth == DepthConfig.Count then
			break
		end
	end
	return reached, depth, totalSeconds
end

test("greedy player: B2 after a handful of trips, B7 reachable without Robux", function()
	local reached, depth, seconds = simulate(20000)
	local line = {}
	for d = 2, DepthConfig.Count do
		table.insert(line, string.format("B%d@%s", d, tostring(reached[d])))
	end
	print("        progression (trips): " .. table.concat(line, "  ") .. string.format("  (~%.1f h of play)", seconds / 3600))
	assert(reached[2] and reached[2] >= 5 and reached[2] <= 25, "B2 should take 5-25 trips, took " .. tostring(reached[2]))
	assert(depth == DepthConfig.Count, "B7 not reached in the simulation")
	for d = 3, DepthConfig.Count do
		assert(reached[d] - reached[d - 1] >= 5, "depth " .. d .. " came too fast after the previous one")
	end
end)

return cases
