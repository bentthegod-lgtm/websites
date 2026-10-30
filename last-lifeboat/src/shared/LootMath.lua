--[[
	LootMath - loot slots, weight, rarity rolls and the escape payout (pure, unit-tested).

	Carried loot is a list of item keys (GameConfig.Loot). It only pays out if you ESCAPE:
	  coins = floor(sum(values) * ship LootMult * (Full Crew 1.25) * (x2 Loot pass 2))
	        + EscapeBase * LootMult + ReviveBonus per revive
	Everyone left behind gets the Participation reward ("LOST AT SEA").
]]

local GameConfig = require(script.Parent.Config.GameConfig)
local Upgrades = require(script.Parent.Upgrades)

local LootMath = {}

local R = GameConfig.Rewards

function LootMath.rank(rarity)
	return table.find(GameConfig.RarityOrder, rarity) or 0
end

function LootMath.item(key)
	return GameConfig.Loot[key]
end

function LootMath.slots(slotLevel, vip)
	return Upgrades.effect("Slots", slotLevel or 0) + (if vip then 1 else 0)
end

function LootMath.weight(items)
	local w = 0
	for _, key in ipairs(items or {}) do
		local def = GameConfig.Loot[key]
		w += def and def.Weight or 0
	end
	return w
end

function LootMath.walkSpeed(items)
	local M = GameConfig.Move
	return math.max(M.MinWalk, M.Walk - LootMath.weight(items) * M.WeightSlow)
end

function LootMath.value(items)
	local v = 0
	for _, key in ipairs(items or {}) do
		local def = GameConfig.Loot[key]
		v += def and def.Value or 0
	end
	return v
end

-- Rarity weights for a spot. depthFrac: 0 = top deck .. 1 = lowest deck. tier: 1..3.
function LootMath.rarityWeights(depthFrac, tier)
	local rules = GameConfig.LootRules
	local out = {}
	local boost = (1 + rules.DepthBonus * math.clamp(depthFrac or 0, 0, 1)) * (1 + rules.TierBonus * ((tier or 1) - 1))
	for _, rarity in ipairs(GameConfig.RarityOrder) do
		local w = GameConfig.Rarities[rarity].Weight
		out[rarity] = if rarity == "Common" then w else w * boost
	end
	return out
end

function LootMath.rollRarity(rng, depthFrac, tier)
	local weights = LootMath.rarityWeights(depthFrac, tier)
	local total = 0
	for _, rarity in ipairs(GameConfig.RarityOrder) do
		total += weights[rarity]
	end
	local roll = rng:NextNumber() * total
	for _, rarity in ipairs(GameConfig.RarityOrder) do
		roll -= weights[rarity]
		if roll <= 0 then
			return rarity
		end
	end
	return GameConfig.RarityOrder[#GameConfig.RarityOrder]
end

function LootMath.itemsOf(rarity)
	local list = {}
	for _, key in ipairs(GameConfig.LootOrder) do
		if GameConfig.Loot[key].Rarity == rarity then
			table.insert(list, key)
		end
	end
	return list
end

function LootMath.roll(rng, depthFrac, tier)
	local list = LootMath.itemsOf(LootMath.rollRarity(rng, depthFrac, tier))
	return list[rng:NextInteger(1, #list)]
end

--[[
	summary = { escaped, items = { keys }, shipKey, fullCrew, double, revives }
	Returns { coins, banked (raw value), lines = { {text, coins} }, bestRank }.
]]
function LootMath.payout(summary)
	local ship = GameConfig.Ships[summary.shipKey] or GameConfig.Ships.Gull
	local lines = {}
	local revives = tonumber(summary.revives) or 0
	revives = if revives ~= revives then 0 else math.clamp(math.floor(revives), 0, 20)
	if not summary.escaped then
		local coins = R.Participation + revives * R.ReviveBonus
		table.insert(lines, { "Lost at sea", R.Participation })
		if revives > 0 then
			table.insert(lines, { string.format("Revives x%d", revives), revives * R.ReviveBonus })
		end
		return { coins = coins, banked = 0, lines = lines, bestRank = 0 }
	end
	local raw = LootMath.value(summary.items)
	local bestRank = 0
	for _, key in ipairs(summary.items or {}) do
		local def = GameConfig.Loot[key]
		if def then
			bestRank = math.max(bestRank, LootMath.rank(def.Rarity))
		end
	end
	local mult = ship.LootMult
	if summary.fullCrew then
		mult *= GameConfig.Lifeboat.FullCrewBonus
	end
	if summary.double then
		mult *= R.DoubleLoot
	end
	local lootCoins = math.floor(raw * mult)
	local escapeCoins = math.floor(R.EscapeBase * ship.LootMult)
	table.insert(lines, { "Escaped", escapeCoins })
	if raw > 0 then
		table.insert(lines, { string.format("Loot banked (%d)", raw), math.floor(raw * ship.LootMult) })
		if summary.fullCrew then
			table.insert(lines, { "Full Crew! x1.25", math.floor(raw * ship.LootMult * GameConfig.Lifeboat.FullCrewBonus) - math.floor(raw * ship.LootMult) })
		end
		if summary.double then
			table.insert(lines, { "x2 Loot", lootCoins - math.floor(raw * ship.LootMult * (if summary.fullCrew then GameConfig.Lifeboat.FullCrewBonus else 1)) })
		end
	end
	if revives > 0 then
		table.insert(lines, { string.format("Revives x%d", revives), revives * R.ReviveBonus })
	end
	return { coins = lootCoins + escapeCoins + revives * R.ReviveBonus, banked = raw, lines = lines, bestRank = bestRank }
end

-- Comma list for attributes ("GoldBar,PocketWatch") and back.
function LootMath.encode(items)
	return table.concat(items or {}, ",")
end

function LootMath.decode(text)
	local items = {}
	if type(text) ~= "string" then
		return items
	end
	for key in string.gmatch(text, "[^,]+") do
		if GameConfig.Loot[key] then
			table.insert(items, key)
		end
	end
	return items
end

return LootMath
