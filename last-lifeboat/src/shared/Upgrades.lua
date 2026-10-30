--[[
	Upgrades - coin upgrades bought in the lobby shop (pure, unit-tested).
	Each has 5 levels. Costs[i] buys level i; Effects[level + 1] is the value at that level.
]]

local GameConfig = require(script.Parent.Config.GameConfig)

local Upgrades = {}

Upgrades.MaxLevel = 5

function Upgrades.def(key)
	return GameConfig.Upgrades[key]
end

function Upgrades.clampLevel(level)
	level = math.floor(tonumber(level) or 0)
	if level ~= level then
		return 0
	end
	return math.clamp(level, 0, Upgrades.MaxLevel)
end

-- Cost of the NEXT level (nil when maxed or unknown).
function Upgrades.cost(key, level)
	local def = GameConfig.Upgrades[key]
	level = Upgrades.clampLevel(level)
	if not def or level >= Upgrades.MaxLevel then
		return nil
	end
	return def.Costs[level + 1]
end

function Upgrades.effect(key, level)
	local def = GameConfig.Upgrades[key]
	if not def then
		return nil
	end
	return def.Effects[Upgrades.clampLevel(level) + 1]
end

function Upgrades.totalCost(key)
	local sum = 0
	for _, c in ipairs(GameConfig.Upgrades[key].Costs) do
		sum += c
	end
	return sum
end

-- Every effect a player's upgrade levels give (levels: { Lungs = 2, ... }).
function Upgrades.effects(levels)
	levels = levels or {}
	local out = {}
	for _, key in ipairs(GameConfig.UpgradeOrder) do
		out[key] = Upgrades.effect(key, levels[key] or 0)
	end
	return out
end

return Upgrades
