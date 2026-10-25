--[[
	CrateRoll - pure crate logic with published odds and a pity counter.
]]

local CrateRoll = {}

-- Display rows in rarity order: { { rarity, percent } }
function CrateRoll.odds(crate, cosmeticCfg)
	local total = 0
	for _, weight in pairs(crate.Odds) do
		total += weight
	end
	local rows = {}
	for _, rarity in ipairs(cosmeticCfg.Rarities.Order) do
		local weight = crate.Odds[rarity]
		if weight and weight > 0 then
			table.insert(rows, { rarity = rarity, percent = weight / total * 100 })
		end
	end
	return rows
end

function CrateRoll.pool(cosmeticCfg, rarity, crate)
	local list = {}
	for _, item in ipairs(cosmeticCfg.Items) do
		if item.Rarity == rarity and not item.Default and (not crate or not crate.Categories or crate.Categories[item.Category]) then
			table.insert(list, item)
		end
	end
	return list
end

local function rankOf(cosmeticCfg, rarity)
	return table.find(cosmeticCfg.Rarities.Order, rarity) or 0
end
CrateRoll.rankOf = rankOf

function CrateRoll.rollRarity(crate, cosmeticCfg, rng, forceHigh)
	local legendary = rankOf(cosmeticCfg, "Legendary")
	local order, total = {}, 0
	for _, rarity in ipairs(cosmeticCfg.Rarities.Order) do
		local w = crate.Odds[rarity] or 0
		if forceHigh and rankOf(cosmeticCfg, rarity) < legendary then
			w = 0
		end
		if w > 0 and #CrateRoll.pool(cosmeticCfg, rarity, crate) > 0 then
			table.insert(order, { rarity = rarity, w = w })
			total += w
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:next() * total
	for _, entry in ipairs(order) do
		roll -= entry.w
		if roll < 0 then
			return entry.rarity
		end
	end
	return order[#order].rarity
end

-- Returns item, { rarity, pity (new counter), pityTriggered }
function CrateRoll.roll(crate, cosmeticCfg, rng, pity)
	pity = pity or 0
	local forced = pity + 1 >= cosmeticCfg.PityEvery
	local rarity = CrateRoll.rollRarity(crate, cosmeticCfg, rng, forced)
	if not rarity then
		return nil, nil
	end
	local pool = CrateRoll.pool(cosmeticCfg, rarity, crate)
	local item = pool[rng:integer(1, #pool)]
	local high = rankOf(cosmeticCfg, rarity) >= rankOf(cosmeticCfg, "Legendary")
	return item, { rarity = rarity, pity = if high then 0 else pity + 1, pityTriggered = forced }
end

function CrateRoll.find(cosmeticCfg, category, id)
	for _, item in ipairs(cosmeticCfg.Items) do
		if item.Category == category and item.Id == id then
			return item
		end
	end
	return nil
end

return CrateRoll
