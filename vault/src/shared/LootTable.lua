--[[
	LootTable - weighted loot rolls for a floor (pure; the server's LootService uses it).

	roll(depth, active, luck, rng, sizeLimit) picks one non-special item of that depth:
	  * weights come from LootConfig.SpawnWeight;
	  * Rare and better are multiplied by `luck` (1..2, Rare Loot Luck upgrade - the best
	    luck among players on that floor);
	  * items already at their MaxActive cap (active[id] >= MaxActive) are skipped;
	  * sizeLimit ("S" / "M" / "L") skips items too big for the chosen spawn point.
	Returns the def, or nil when everything is capped.
]]

local LootConfig = require(script.Parent.Config.LootConfig)

local LootTable = {}

local SIZE_RANK = { S = 1, M = 2, L = 3 }
LootTable.SizeRank = SIZE_RANK

function LootTable.fits(def, sizeLimit)
	return SIZE_RANK[def.Size] <= SIZE_RANK[sizeLimit or "L"]
end

function LootTable.weight(def, luck)
	local w = def.SpawnWeight
	if LootConfig.rank(def) >= 3 then
		w *= math.clamp(luck or 1, 1, 2)
	end
	return w
end

function LootTable.roll(depth, active, luck, rng, sizeLimit)
	local pool = LootConfig.ByDepth[depth]
	if not pool then
		return nil
	end
	local total = 0
	local candidates = {}
	for _, def in ipairs(pool) do
		if (active[def.Id] or 0) < def.MaxActive and LootTable.fits(def, sizeLimit) then
			local w = LootTable.weight(def, luck)
			total += w
			table.insert(candidates, { def = def, w = w })
		end
	end
	if total <= 0 then
		return nil
	end
	local pick = rng:NextNumber() * total
	for _, c in ipairs(candidates) do
		pick -= c.w
		if pick < 0 then
			return c.def
		end
	end
	return candidates[#candidates].def
end

-- Average value of one item on a floor (for balance tests and the depth panel preview).
function LootTable.averageValue(depth, luck)
	local pool = LootConfig.ByDepth[depth] or {}
	local total, sum = 0, 0
	for _, def in ipairs(pool) do
		local w = LootTable.weight(def, luck)
		total += w
		sum += w * def.Value
	end
	return if total > 0 then sum / total else 0
end

-- Average capacity slots of one item on a floor.
function LootTable.averageSlots(depth)
	local pool = LootConfig.ByDepth[depth] or {}
	local total, sum = 0, 0
	for _, def in ipairs(pool) do
		total += def.SpawnWeight
		sum += def.SpawnWeight * def.Slots
	end
	return if total > 0 then sum / total else 1
end

return LootTable
