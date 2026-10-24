--[[
	CrateRoll - pure crate / spin logic with published odds and a pity counter.
]]

local CrateRoll = {}

-- Odds as display rows in rarity order: { { rarity, percent } }.
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

function CrateRoll.pool(cosmeticCfg, rarity)
	local list = {}
	for _, item in ipairs(cosmeticCfg.Items) do
		if item.Rarity == rarity and item.Crate ~= false and not item.Pass then
			table.insert(list, item)
		end
	end
	return list
end

local function rankOf(cosmeticCfg, rarity)
	return table.find(cosmeticCfg.Rarities.Order, rarity) or 0
end

-- Rolls a rarity. With `forceLegendary` only Legendary-or-better rarities are possible.
function CrateRoll.rollRarity(crate, cosmeticCfg, rng, forceLegendary)
	local legendaryRank = rankOf(cosmeticCfg, "Legendary")
	local weights, order, total = {}, {}, 0
	for _, rarity in ipairs(cosmeticCfg.Rarities.Order) do
		local w = crate.Odds[rarity] or 0
		if forceLegendary and rankOf(cosmeticCfg, rarity) < legendaryRank then
			w = 0
		end
		if w > 0 and #CrateRoll.pool(cosmeticCfg, rarity) > 0 then
			weights[rarity] = w
			table.insert(order, rarity)
			total += w
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:next() * total
	for _, rarity in ipairs(order) do
		roll -= weights[rarity]
		if roll < 0 then
			return rarity
		end
	end
	return order[#order]
end

--[[
	Returns item, info where info = { rarity, pity (new counter), pityTriggered }
	`pity` is the number of opens since the last Legendary+.
]]
function CrateRoll.roll(crate, cosmeticCfg, rng, pity)
	pity = pity or 0
	local forced = pity + 1 >= cosmeticCfg.PityEvery
	local rarity = CrateRoll.rollRarity(crate, cosmeticCfg, rng, forced)
	if not rarity then
		return nil, nil
	end
	local pool = CrateRoll.pool(cosmeticCfg, rarity)
	local item = pool[rng:integer(1, #pool)]
	local isHigh = rankOf(cosmeticCfg, rarity) >= rankOf(cosmeticCfg, "Legendary")
	return item, { rarity = rarity, pity = if isHigh then 0 else pity + 1, pityTriggered = forced }
end

function CrateRoll.find(cosmeticCfg, id)
	for _, item in ipairs(cosmeticCfg.Items) do
		if item.Id == id then
			return item
		end
	end
	return nil
end

return CrateRoll
