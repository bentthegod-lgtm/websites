--[[
	Pure growth math. A plant record is
	  { c = cropId, g = grown seconds, m = {mutations}, v = variant?, h = harvests,
	    lu = luckyFertilizer?, w = last watered (unix)? }
	Growth is measured in "grown seconds" so boosts simply add more seconds per second.
	Offline growth is applied on load from the saved Updated timestamp.
]]

local Growth = {}

-- Stage thresholds on progress (0..1): 1 sprout, 2 small, 3 full, 4 ripe.
Growth.SMALL = 0.2
Growth.FULL = 0.55
Growth.StageNames = { "Sprout", "Small", "Full", "Ripe" }

function Growth.progress(plant, crop)
	return math.clamp((plant.g or 0) / crop.GrowTime, 0, 1)
end

function Growth.stage(plant, crop)
	local p = Growth.progress(plant, crop)
	if p >= 1 then
		return 4
	elseif p >= Growth.FULL or (plant.h or 0) > 0 then
		return 3
	elseif p >= Growth.SMALL then
		return 2
	end
	return 1
end

function Growth.isRipe(plant, crop)
	return (plant.g or 0) >= crop.GrowTime
end

function Growth.advance(plant, crop, grownSeconds)
	if grownSeconds > 0 and grownSeconds == grownSeconds then
		plant.g = math.min(crop.GrowTime, (plant.g or 0) + grownSeconds)
	end
	return plant.g
end

function Growth.remaining(plant, crop, rate)
	return math.max(0, crop.GrowTime - (plant.g or 0)) / math.max(rate or 1, 0.01)
end

-- Offline catch-up: elapsed real seconds at the given rate, capped.
function Growth.offline(plant, crop, elapsed, rate, cap)
	local seconds = math.clamp(elapsed or 0, 0, cap or math.huge)
	return Growth.advance(plant, crop, seconds * (rate or 1))
end

-- After picking. Returns true if the plant stays (multi-harvest) and resets its fruit.
function Growth.harvest(plant, crop)
	if not crop.Regrow then
		return false
	end
	plant.g = math.max(0, crop.GrowTime - crop.Regrow)
	plant.h = (plant.h or 0) + 1
	plant.m = {}
	plant.v = nil
	plant.lu = nil
	return true
end

function Growth.toColRow(index, cols)
	return ((index - 1) % cols) + 1, ((index - 1) // cols) + 1
end

function Growth.toIndex(col, row, cols)
	return (row - 1) * cols + col
end

-- Best growth multiplier from active sprinklers covering (col,row).
function Growth.sprinklerMultiplier(index, sprinklers, now, gearConfig, cols)
	local col, row = Growth.toColRow(index, cols)
	local best = 1
	for _, s in ipairs(sprinklers or {}) do
		local def = gearConfig.Gear[s.k]
		if def and (s.e or 0) > now then
			local sc, sr = Growth.toColRow(s.i, cols)
			if math.abs(sc - col) <= def.Radius and math.abs(sr - row) <= def.Radius then
				best = math.max(best, def.Growth)
			end
		end
	end
	return best
end

function Growth.pruneSprinklers(sprinklers, now)
	local kept = {}
	for _, s in ipairs(sprinklers or {}) do
		if (s.e or 0) > now then
			table.insert(kept, s)
		end
	end
	return kept
end

-- Watering can: grown seconds to add.
function Growth.waterAdvance(crop, canDef)
	return math.min(crop.GrowTime * canDef.Advance, canDef.MaxAdvance)
end

return Growth
