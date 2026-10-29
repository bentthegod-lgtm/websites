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
local function simulate(maxTrips, searchSeconds, poolLuck, valueScale)
	local state = { Upgrades = {}, Perks = {}, Rebirths = 0 }
	local cash, tokens, depth = 0, 0, 1
	local reached = { [1] = 0 }
	local reachedAt = { [1] = 0 }
	local totalSeconds = 0
	for trip = 1, maxTrips do
		local s = Economy.stats(state)
		local perSlot = LootTable.averageValue(depth, math.min(2, s.Luck * (poolLuck or 1))) * s.ValueMult * (valueScale or 1) / LootTable.averageSlots(depth)
		local carried = math.floor(s.Capacity * perSlot)
		cash += Economy.depositPayout(carried, s)
		-- Trip time: pickups (or magnet/auto) plus walking to and from the machine.
		local perPickup = if s.AutoRadius > 0 then math.min(s.PickupInterval, s.AutoInterval) else s.PickupInterval
		local tripSeconds = s.Capacity / LootTable.averageSlots(depth) * (perPickup + (searchSeconds or 1.6) / (1 + s.MagnetRadius / 20)) + 70 * 16 / s.WalkSpeed / 4
		totalSeconds += tripSeconds
		-- Tokens (achievements, dailies) come with play time, not with trip count.
		tokens += 0.35 * tripSeconds / 150
		local nextDef = DepthConfig.get(depth + 1)
		if nextDef and cash >= nextDef.UnlockCash and tokens >= nextDef.UnlockTokens then
			cash -= nextDef.UnlockCash
			tokens -= nextDef.UnlockTokens
			depth += 1
			reached[depth] = trip
			reachedAt[depth] = totalSeconds
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
	return reached, depth, totalSeconds, reachedAt
end

-- The pools used to hold ~60 scattered items (about 1.6 s of searching per pickup); now
-- they are packed full (the next item is ~2.4 studs away, ~0.25 s) and deeper slots are
-- luckier (average fill bonus ~1.4). Times to reach B2 / B7 must stay roughly the same.
local SPARSE_SEARCH, DENSE_SEARCH, DENSE_LUCK = 1.6, 0.25, 1.4

local function describe(label, reached, reachedAt)
	local line = {}
	for d = 2, DepthConfig.Count do
		table.insert(line, string.format("B%d@%s", d, tostring(reached[d])))
	end
	print(string.format("        %s: %s  (B2 ~%.0f min, B7 ~%.1f h)", label, table.concat(line, " "), (reachedAt[2] or 0) / 60, (reachedAt[DepthConfig.Count] or 0) / 3600))
end

test("greedy player: B2 after a handful of trips, B7 reachable without Robux", function()
	local reached, depth, _, at = simulate(20000, DENSE_SEARCH, DENSE_LUCK)
	describe("full pools (trips)", reached, at)
	-- Full pools make trips short, so B2 takes more (quicker) trips than it used to.
	assert(reached[2] and reached[2] >= 10 and reached[2] <= 45, "B2 should take 10-45 trips, took " .. tostring(reached[2]))
	assert(at[2] >= 10 * 60 and at[2] <= 30 * 60, string.format("B2 should take 10-30 minutes, took %.0f", at[2] / 60))
	assert(depth == DepthConfig.Count, "B7 not reached in the simulation")
	for d = 3, DepthConfig.Count do
		assert(reached[d] - reached[d - 1] >= 5, "depth " .. d .. " came too fast after the previous one")
	end
end)

test("full pools keep the time to reach B2 and B7 close to the sparse-loot balance", function()
	local LootConfig = L.shared("Config/LootConfig")
	local reachedS, _, _, atS = simulate(20000, SPARSE_SEARCH, 1, 1 / LootConfig.FullPoolValue)
	describe("before: sparse floors, original values", reachedS, atS)
	-- Reference: the balance as it was before the pools were filled.
	local refB2Min, refB7Hours = atS[2] / 60, atS[DepthConfig.Count] / 3600
	local _, _, _, at = simulate(20000, DENSE_SEARCH, DENSE_LUCK)
	local b2, b7 = at[2] / 60, at[DepthConfig.Count] / 3600
	assert(math.abs(b2 - refB2Min) / refB2Min < 0.35, string.format("B2 now %.0f min vs %.0f before", b2, refB2Min))
	assert(math.abs(b7 - refB7Hours) / refB7Hours < 0.25, string.format("B7 now %.1f h vs %.1f before", b7, refB7Hours))
end)

return cases
