--[[
	Pure economy math (no Roblox APIs, configs passed in) so it can be unit tested in Lune.

	Fruit value = crop.Value x (kg / crop.BaseKg) x mutation multiplier
	Mutation multiplier = variant x (1 + sum(env multiplier - 1))
]]

local Economy = {}

-- Rolls a fruit weight around crop.BaseKg. Returns kg (2 decimals) and whether it is Huge.
function Economy.rollWeight(crop, rng, hugeChance)
	local r = (rng:NextNumber() + rng:NextNumber()) / 2
	local w = 0.75 + r * 0.7
	local huge = false
	if rng:NextNumber() < (hugeChance or 0) then
		w *= rng:NextNumber(2.5, 4)
		huge = true
	end
	local kg = math.max(0.01, math.floor(crop.BaseKg * w * 100 + 0.5) / 100)
	return kg, huge
end

function Economy.mutationMultiplier(mutations, variant, mutationConfig)
	local total = 1
	for _, name in ipairs(mutations or {}) do
		local def = mutationConfig.Mutations[name]
		if def then
			total += def.Multiplier - 1
		end
	end
	local v = variant and mutationConfig.Variants[variant]
	if v then
		total *= v.Multiplier
	end
	return total
end

function Economy.fruitValue(crop, kg, mutations, variant, mutationConfig)
	local weightMultiplier = (tonumber(kg) or crop.BaseKg) / crop.BaseKg
	local value = crop.Value * weightMultiplier * Economy.mutationMultiplier(mutations, variant, mutationConfig)
	return math.max(1, math.floor(value + 0.5))
end

function Economy.sellMultiplier(hasDoubleSell, friends, gameConfig, shopConfig)
	local m = if hasDoubleSell then shopConfig.DoubleSellMultiplier else 1
	local bonus = math.min((friends or 0) * gameConfig.FriendBoostPer, gameConfig.FriendBoostMax)
	return m * (1 + bonus)
end

function Economy.expansionCost(purchasedRows, plotConfig)
	local raw = plotConfig.ExpansionBaseCost * plotConfig.ExpansionGrowth ^ purchasedRows
	return math.floor(raw / 10 + 0.5) * 10
end

function Economy.unlockedRows(purchasedRows, vip, plotConfig)
	local rows = plotConfig.StartRows + purchasedRows + (if vip then plotConfig.VipBonusRows else 0)
	return math.clamp(rows, 1, plotConfig.Rows)
end

function Economy.canExpand(purchasedRows, vip, plotConfig)
	return Economy.unlockedRows(purchasedRows, vip, plotConfig) < plotConfig.Rows
end

local function has(list, name)
	return table.find(list, name) ~= nil
end

--[[
	Adds a mutation to a fruit's mutation list (in place). Applies combos (Wet + Chilled ->
	Frozen). A fruit that already has a combo result does not take its ingredients again.
	Returns true if the list changed.
]]
function Economy.addMutation(list, name, mutationConfig)
	if not mutationConfig.Mutations[name] or has(list, name) then
		return false
	end
	for _, combo in ipairs(mutationConfig.Combos) do
		if has(list, combo.Result) and table.find(combo.Needs, name) then
			return false
		end
	end
	table.insert(list, name)
	for _, combo in ipairs(mutationConfig.Combos) do
		local all = true
		for _, need in ipairs(combo.Needs) do
			if not has(list, need) then
				all = false
				break
			end
		end
		if all then
			for _, need in ipairs(combo.Needs) do
				table.remove(list, table.find(list, need))
			end
			if not has(list, combo.Result) then
				table.insert(list, combo.Result)
			end
		end
	end
	return true
end

function Economy.mutationChance(base, luckyFertilizer, luckyPass, mutationConfig)
	local chance = base
	if luckyFertilizer then
		chance *= mutationConfig.LuckyFertilizerMultiplier
	end
	if luckyPass then
		chance *= mutationConfig.LuckyGardenerMultiplier
	end
	return math.min(chance, mutationConfig.ChanceCap)
end

-- Natural variant roll at planting / regrow time. Rainbow is checked first.
function Economy.rollVariant(rng, luckyPass, mutationConfig)
	local boost = if luckyPass then mutationConfig.LuckyGardenerVariantMultiplier else 1
	local roll = rng:NextNumber()
	local rainbow = mutationConfig.Variants.Rainbow.NaturalChance * boost
	local golden = mutationConfig.Variants.Golden.NaturalChance * boost
	if roll < rainbow then
		return "Rainbow"
	elseif roll < rainbow + golden then
		return "Golden"
	end
	return nil
end

-- Total coins for a list of fruit items { c = cropId, kg, m = {...}, v = variant }.
function Economy.itemsValue(items, cropById, mutationConfig)
	local total = 0
	for _, item in ipairs(items) do
		local crop = cropById[item.c]
		if crop then
			total += Economy.fruitValue(crop, item.kg, item.m, item.v, mutationConfig)
		end
	end
	return total
end

return Economy
