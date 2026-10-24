--[[
	Spawn rolls (pure, unit tested). `rand` is any function returning a number in [0, 1).
]]

local Spawner = {}

-- Returns { [rarity] = weight } with luck applied to Rare+ and mythicBoost to Mythic+.
function Spawner.rarityWeights(rarityCfg, luck, mythicBoost)
	luck = math.max(1, luck or 1)
	mythicBoost = math.max(1, mythicBoost or 1)
	local weights = {}
	for index, name in ipairs(rarityCfg.Order) do
		local w = rarityCfg.Tiers[name].Weight
		if index >= rarityCfg.LuckFromIndex then
			w *= luck
		end
		if index >= rarityCfg.MythicFromIndex then
			w *= mythicBoost
		end
		weights[name] = w
	end
	return weights
end

-- Normalised probabilities, for the shop / HUD "odds" display.
function Spawner.rarityChances(rarityCfg, luck, mythicBoost)
	local weights = Spawner.rarityWeights(rarityCfg, luck, mythicBoost)
	local total = 0
	for _, w in pairs(weights) do
		total += w
	end
	local chances = {}
	for name, w in pairs(weights) do
		chances[name] = w / total
	end
	return chances
end

-- order: array of keys, weights: map key -> weight >= 0
function Spawner.pickWeighted(order, weights, r)
	local total = 0
	for _, key in ipairs(order) do
		total += math.max(0, weights[key] or 0)
	end
	if total <= 0 then
		return order[1]
	end
	local target = r * total
	local acc = 0
	local last
	for _, key in ipairs(order) do
		local w = math.max(0, weights[key] or 0)
		if w > 0 then
			acc += w
			last = key
			if target < acc then
				return key
			end
		end
	end
	return last
end

function Spawner.rollRarity(rarityCfg, rand, luck, mythicBoost)
	return Spawner.pickWeighted(rarityCfg.Order, Spawner.rarityWeights(rarityCfg, luck, mythicBoost), rand())
end

function Spawner.rollSpecies(blobbyCfg, rarity, rand)
	local pool = blobbyCfg.ByRarity[rarity]
	assert(pool and #pool > 0, "no species for rarity " .. tostring(rarity))
	-- Cheaper species of a tier are a bit more common than the pricey ones.
	local order, weights = {}, {}
	for i, species in ipairs(pool) do
		order[i] = species.Id
		weights[species.Id] = 1 / (1 + (i - 1) * 0.35)
	end
	return blobbyCfg.ById[Spawner.pickWeighted(order, weights, rand())]
end

-- Returns a mutation key or nil.
function Spawner.mutationChances(mutationCfg, boost)
	boost = math.max(1, boost or 1)
	local total = 0
	for _, key in ipairs(mutationCfg.Order) do
		total += mutationCfg.Types[key].Chance * boost
	end
	local scale = if total > mutationCfg.MaxTotalChance then mutationCfg.MaxTotalChance / total else 1
	local chances = {}
	for _, key in ipairs(mutationCfg.Order) do
		chances[key] = mutationCfg.Types[key].Chance * boost * scale
	end
	return chances
end

function Spawner.rollMutation(mutationCfg, rand, boost)
	local chances = Spawner.mutationChances(mutationCfg, boost)
	local r = rand()
	local acc = 0
	for _, key in ipairs(mutationCfg.Order) do
		acc += chances[key]
		if r < acc then
			return key
		end
	end
	return nil
end

-- odds: { { Rarity = "Mythic", Chance = 0.92 }, ... }
function Spawner.rollCrate(odds, rand)
	local order, weights = {}, {}
	for i, entry in ipairs(odds) do
		order[i] = entry.Rarity
		weights[entry.Rarity] = entry.Chance
	end
	return Spawner.pickWeighted(order, weights, rand())
end

return Spawner
