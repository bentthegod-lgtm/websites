--[[
	ItemOdds - position-weighted item rolls (Stage 3 uses it; tested from Stage 1).
	weights(place, field) -> { [itemId] = weight }: the back of the pack gets better odds of
	tier-3 items, the front of tier-1 items, and every item always keeps a non-zero chance
	(nothing is ever guaranteed).
]]

local PowerUps = require(script.Parent.Config.PowerUps)

local ItemOdds = {}

function ItemOdds.tierWeights(place, field)
	local t = if field <= 1 then 0 else math.clamp((place - 1) / (field - 1), 0, 1)
	local out = {}
	for tier = 1, 3 do
		out[tier] = PowerUps.TierWeights.Front[tier] + (PowerUps.TierWeights.Back[tier] - PowerUps.TierWeights.Front[tier]) * t
	end
	return out
end

function ItemOdds.weights(place, field)
	local tiers = ItemOdds.tierWeights(place, field)
	local perTier = { 0, 0, 0 }
	for _, id in ipairs(PowerUps.ORDER) do
		local tier = PowerUps.Items[id].tier
		perTier[tier] += 1
	end
	local out = {}
	for _, id in ipairs(PowerUps.ORDER) do
		local tier = PowerUps.Items[id].tier
		out[id] = math.max(0.5, tiers[tier] / perTier[tier])
	end
	return out
end

function ItemOdds.roll(place, field, rng)
	local w = ItemOdds.weights(place, field)
	local total = 0
	for _, id in ipairs(PowerUps.ORDER) do
		total += w[id]
	end
	local r = rng:NextNumber() * total
	for _, id in ipairs(PowerUps.ORDER) do
		r -= w[id]
		if r <= 0 then
			return id
		end
	end
	return PowerUps.ORDER[#PowerUps.ORDER]
end

return ItemOdds
