--[[
	Seed crate odds (pure). Rarity is rolled by weight, then one crop of that rarity is
	picked evenly. Rarities with no crops are skipped and the others renormalised, so the
	odds shown in the shop always add up to 100%.
]]

local Crate = {}

local function groups(crate, cropList)
	local list, total = {}, 0
	for _, entry in ipairs(crate.Odds) do
		local crops = {}
		for _, crop in ipairs(cropList) do
			if crop.Rarity == entry.Rarity then
				table.insert(crops, crop.Id)
			end
		end
		if #crops > 0 and entry.Weight > 0 then
			table.insert(list, { rarity = entry.Rarity, weight = entry.Weight, crops = crops })
			total += entry.Weight
		end
	end
	return list, total
end

-- { { rarity, chance (0..1), crops = {ids} } } for display.
function Crate.odds(crate, cropList)
	local list, total = groups(crate, cropList)
	local out = {}
	for _, g in ipairs(list) do
		table.insert(out, { rarity = g.rarity, chance = g.weight / total, crops = g.crops })
	end
	return out
end

function Crate.roll(crate, cropList, rng)
	local list, total = groups(crate, cropList)
	local r = rng:NextNumber() * total
	for _, g in ipairs(list) do
		r -= g.weight
		if r < 0 then
			return g.crops[rng:NextInteger(1, #g.crops)], g.rarity
		end
	end
	local last = list[#list]
	return last.crops[#last.crops], last.rarity
end

return Crate
