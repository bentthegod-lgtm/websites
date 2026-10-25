--[[
	Economy - pure maths for prices, magnet stats, sale values and prestige.
	No Roblox APIs: unit-tested in tests/economy.spec.luau.
]]

local MagnetConfig = require(script.Parent.Config.MagnetConfig)
local EconomyConfig = require(script.Parent.Config.EconomyConfig)

local Economy = {}

-- Price of buying the next level of an upgrade (nil when maxed).
function Economy.upgradePrice(key, level)
	local def = EconomyConfig.ByKey[key]
	if not def or level >= def.Max then
		return nil
	end
	return math.floor(def.Base * def.Growth ^ level + 0.5)
end

function Economy.tierPrice(tier)
	local def = MagnetConfig.Tiers[tier]
	return def and def.Price or nil
end

-- Capacity curve for the Capacity upgrade level (before tier / packing multipliers).
function Economy.baseCapacity(level)
	return MagnetConfig.Base.Capacity + 18 * level + 2.2 * level * level
end

--[[
	Final magnet stats.
	  levels  = { [UpgradeKey] = level }   tier = 1..#Tiers   cores = prestige Magnet Cores
]]
function Economy.stats(levels, tier, cores)
	levels = levels or {}
	tier = math.clamp(tier or 1, 1, #MagnetConfig.Tiers)
	cores = math.max(0, cores or 0)
	local t = MagnetConfig.Tiers[tier]
	local B = MagnetConfig.Base
	local U = EconomyConfig.ByKey
	local function lv(key)
		return math.clamp(math.floor(levels[key] or 0), 0, U[key].Max)
	end
	local pulseLevel = lv("Pulse")
	local prestige = EconomyConfig.Prestige
	return {
		MagnetStrength = t.Strength + lv("Strength") * U.Strength.Per,
		AttractionRange = B.Range + lv("Range") * U.Range.Per + t.RangeBonus,
		AttractionSpeed = (1 + lv("Speed") * U.Speed.Per) * (1 + cores * prestige.SpeedPerCore),
		MaximumScrapCapacity = math.floor(Economy.baseCapacity(lv("Capacity")) * t.CapacityMult * (1 + lv("Organization") * U.Organization.Per)),
		HeavyObjectCapability = 1 + lv("Heavy") * U.Heavy.Per,
		ScrapValueMultiplier = (1 + lv("Sell") * U.Sell.Per) * (1 + cores * prestige.ValuePerCore),
		PulseRadius = B.PulseRadius + pulseLevel * U.Pulse.Per + t.RangeBonus * 1.5,
		PulseCooldown = math.max(4, B.PulseCooldown - pulseLevel * 0.7),
		CollectionEfficiency = B.Concurrent + lv("Efficiency") * U.Efficiency.Per,
		ClaimsPerSecond = B.ClaimsPerSecond + lv("Efficiency") * 1.5,
		MagnetVisualTier = tier,
		WalkSpeed = B.WalkSpeed + lv("Move") * U.Move.Per,
		SprintMultiplier = B.SprintMultiplier + lv("Sprint") * U.Sprint.Per,
		LuckyChance = lv("Rare") * U.Rare.Per,
		PileCompaction = 1 - lv("Organization") * 0.05,
	}
end

-- What one collected object is worth (before the sale multiplier).
function Economy.itemValue(def, lucky, storm)
	local v = def.Value
	if lucky then
		v *= EconomyConfig.LuckyMultiplier
	end
	if storm then
		v *= storm
	end
	return math.floor(v + 0.5)
end

-- Coins for selling a pile worth `pileValue` with the player's multiplier.
function Economy.saleValue(pileValue, multiplier)
	return math.max(0, math.floor((pileValue or 0) * (multiplier or 1) + 0.5))
end

function Economy.prestigeCores(runEarned)
	local p = EconomyConfig.Prestige
	if (runEarned or 0) < p.MinRunEarned then
		return 0
	end
	return math.floor(p.CoresBase * math.sqrt(runEarned / p.MinRunEarned))
end

return Economy
