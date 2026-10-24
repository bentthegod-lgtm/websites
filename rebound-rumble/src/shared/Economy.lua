--[[
	Economy - pure coin math: match rewards, pass multipliers, daily streak, codes.
]]

local Economy = {}

-- passes = { VIP = bool, DoubleCoins = bool }
function Economy.coinMultiplier(passes, shopCfg)
	local m = 1
	if passes.VIP then
		m += shopCfg.VipCoinBonus
	end
	if passes.DoubleCoins then
		m += shopCfg.DoubleCoinBonus
	end
	return math.min(m, shopCfg.MaxCoinMultiplier)
end

--[[
	summary = { kills, won, survivedSeconds, parries, winStreak (after this round) }
	Returns { lines = { { label, amount } }, base, total, multiplier }
]]
function Economy.matchReward(summary, rewardsCfg, multiplier)
	local lines = {}
	local base = 0
	local function add(label, amount)
		amount = math.floor(amount)
		if amount > 0 then
			table.insert(lines, { label = label, amount = amount })
			base += amount
		end
	end
	add("Played", rewardsCfg.Participation)
	add(string.format("Kills x%d", summary.kills or 0), (summary.kills or 0) * rewardsCfg.Kill)
	add("Parries", math.min(rewardsCfg.ParryCap, (summary.parries or 0) * rewardsCfg.Parry))
	local survival = math.floor(math.max(0, summary.survivedSeconds or 0) / rewardsCfg.SurvivalStep) * rewardsCfg.SurvivalCoins
	add("Survival", math.min(rewardsCfg.SurvivalCap, survival))
	if summary.won then
		add("Victory", rewardsCfg.Win)
		local streak = math.max(0, (summary.winStreak or 1) - 1)
		add(string.format("Win streak x%d", summary.winStreak or 1), math.min(rewardsCfg.StreakBonusCap, streak * rewardsCfg.StreakBonus))
	end
	local m = multiplier or 1
	return { lines = lines, base = base, total = math.floor(base * m + 0.5), multiplier = m }
end

function Economy.dayNumber(unixTime)
	return math.floor(unixTime / 86400)
end

--[[
	daily = { Last = dayNumber or 0, Streak = n }
	Returns { claimable, streak (after claiming), amount, nextIn (seconds until claimable) }
]]
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
