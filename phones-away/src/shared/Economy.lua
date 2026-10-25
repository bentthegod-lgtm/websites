--[[
	Economy - pure Clout math: multipliers (bounded), upgrade stats and prices, levels and
	school-year ranks, daily streak, codes, detention bail.
]]

local Economy = {}

-- passes = { DoubleClout = bool, VIP = bool }. Bonuses ADD and are capped.
function Economy.cloutMultiplier(passes, shopCfg)
	local m = 1
	if passes.DoubleClout then
		m += shopCfg.DoubleCloutBonus
	end
	if passes.VIP then
		m += shopCfg.VipCloutBonus
	end
	return math.min(m, shopCfg.MaxCloutMultiplier)
end

local function tierDef(upgradeCfg, key, tier)
	local def = upgradeCfg[key]
	local t = math.clamp(math.floor(tonumber(tier) or def.Start), def.Start, Economy.maxTier(upgradeCfg, key))
	return def.Tiers[t], t
end
Economy.tierDef = tierDef

function Economy.maxTier(upgradeCfg, key)
	return #upgradeCfg[key].Tiers
end

--[[
	The stats that matter to detection and earning, from the profile's upgrade tiers and
	owned passes. passes = { ProPhone, SilentMode, ExtraHide }.
]]
function Economy.phoneStats(upgrades, passes, upgradeCfg)
	upgrades = upgrades or {}
	passes = passes or {}
	local phone = tierDef(upgradeCfg, "Phone", upgrades.Phone)
	local rate = phone.Rate
	local phoneName = phone.Name
	if passes.ProPhone then
		rate = math.max(rate, upgradeCfg.ProPhone.Rate)
		phoneName = upgradeCfg.ProPhone.Name
	end
	local earbudsTier = upgrades.Earbuds or 0
	if passes.SilentMode then
		earbudsTier = math.max(earbudsTier, upgradeCfg.SilentModeEarbudsTier)
	end
	local hide = tierDef(upgradeCfg, "Hide", upgrades.Hide).Seconds
	if passes.ExtraHide then
		hide = math.max(upgradeCfg.MinHideSeconds, hide - upgradeCfg.ExtraHideSpeedBonus)
	end
	return {
		rate = rate,
		phoneName = phoneName,
		glow = tierDef(upgradeCfg, "Case", upgrades.Case).Glow,
		noise = tierDef(upgradeCfg, "Earbuds", earbudsTier).Noise,
		cover = tierDef(upgradeCfg, "Cover", upgrades.Cover).Sight,
		hide = hide,
		linger = tierDef(upgradeCfg, "Backpack", upgrades.Backpack).Linger,
	}
end

-- Price of the next tier, or nil when maxed.
function Economy.nextUpgrade(upgradeCfg, key, currentTier)
	local def = upgradeCfg[key]
	if not def then
		return nil
	end
	local nextTier = (currentTier or def.Start) + 1
	local t = def.Tiers[nextTier]
	if not t then
		return nil
	end
	return t.Price, nextTier, t
end

---------------------------------------------------------------------------------------------
-- Levels and ranks
---------------------------------------------------------------------------------------------

function Economy.xpToNext(level, xpCfg)
	return xpCfg.Base + xpCfg.Step * (math.max(1, level) - 1)
end

-- Returns newLevel, newXp, levelsGained
function Economy.addXP(level, xp, amount, xpCfg)
	level, xp = level or 1, (xp or 0) + math.max(0, math.floor(amount or 0))
	local gained = 0
	while level < xpCfg.MaxLevel and xp >= Economy.xpToNext(level, xpCfg) do
		xp -= Economy.xpToNext(level, xpCfg)
		level += 1
		gained += 1
	end
	if level >= xpCfg.MaxLevel then
		xp = math.min(xp, Economy.xpToNext(level, xpCfg))
	end
	return level, xp, gained
end

function Economy.rankFor(level, ranks)
	local best = ranks[1]
	for _, rank in ipairs(ranks) do
		if level >= rank.MinLevel then
			best = rank
		end
	end
	return best
end

function Economy.bailCost(level, gameCfg)
	return gameCfg.DetentionBailBase + gameCfg.DetentionBailPerLevel * math.max(0, (level or 1) - 1)
end

---------------------------------------------------------------------------------------------
-- Daily streak and codes
---------------------------------------------------------------------------------------------

function Economy.dayNumber(unixTime)
	return math.floor(unixTime / 86400)
end

-- daily = { Last, Streak } -> { claimable, streak (after claiming), amount, nextIn }
function Economy.daily(daily, now, rewards)
	local today = Economy.dayNumber(now)
	local last = daily.Last or 0
	if last >= today then
		return { claimable = false, streak = daily.Streak or 0, amount = 0, nextIn = (today + 1) * 86400 - now }
	end
	local streak = if last == today - 1 then (daily.Streak or 0) + 1 else 1
	local index = ((streak - 1) % #rewards) + 1
	return { claimable = true, streak = streak, amount = rewards[index], nextIn = 0, dayIndex = index }
end

function Economy.normalizeCode(text)
	if type(text) ~= "string" or #text > 40 then
		return nil
	end
	local cleaned = string.upper((string.gsub(text, "%s+", "")))
	if cleaned == "" or not string.match(cleaned, "^[%w_]+$") then
		return nil
	end
	return cleaned
end

-- Returns ok, rewardOrReason, normalizedCode
function Economy.redeem(codes, redeemed, text, now)
	local code = Economy.normalizeCode(text)
	if not code then
		return false, "Invalid code."
	end
	local def = codes[code]
	if not def then
		return false, "That code doesn't exist."
	end
	if def.Expires and now > def.Expires then
		return false, "That code has expired."
	end
	if redeemed[code] then
		return false, "You already redeemed that code."
	end
	return true, def, code
end

return Economy
