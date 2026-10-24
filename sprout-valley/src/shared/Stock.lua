--[[
	Seed Shop stock rolls (pure). The scheduled stock is rolled from the restock index, so
	every server shows the same seeds for the same 5-minute window; an Instant Restock
	purchase rolls a fresh random stock for that server only.
]]

local Stock = {}

function Stock.index(now, interval)
	return math.floor(now / interval)
end

function Stock.nextAt(now, interval)
	return (Stock.index(now, interval) + 1) * interval
end

-- Seed for the scheduled roll of a given window (stable across servers).
function Stock.seedFor(index)
	return (index * 7919 + 104729) % 2147483646 + 1
end

-- Returns { { crop = id, qty = n }, ... } in crop order.
function Stock.roll(cropList, rng)
	local items = {}
	for _, crop in ipairs(cropList) do
		if crop.StockChance >= 1 or rng:NextNumber() < crop.StockChance then
			table.insert(items, { crop = crop.Id, qty = rng:NextInteger(crop.StockQty[1], crop.StockQty[2]) })
		end
	end
	return items
end

-- Crop ids in the stock whose rarity is worth a server-wide announcement.
function Stock.rare(items, cropById, rarityConfig)
	local out = {}
	for _, item in ipairs(items) do
		local crop = cropById[item.crop]
		if crop and rarityConfig.Tiers[crop.Rarity].Rank >= rarityConfig.AnnounceStockRank then
			table.insert(out, item.crop)
		end
	end
	return out
end

return Stock
