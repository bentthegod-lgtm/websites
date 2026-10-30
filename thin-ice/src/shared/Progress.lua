--[[
	Progress - pure reward / level / daily-streak maths (unit-tested).
]]

local GameConfig = require(script.Parent.Config.GameConfig)

local Progress = {}

local R = GameConfig.Rewards

--[[
	summary = { escaped, cores, rescues, survived, difficulty, vip }
	Everyone who played gets something; cores, rescues and escaping add more, all scaled by
	the difficulty. VIP adds a modest bonus.
]]
function Progress.roundReward(summary)
	local diff = GameConfig.Difficulties[summary.difficulty] or GameConfig.Difficulties.Normal
	local lines = { { "Played", R.Played } }
	local base = R.Played
	local cores = math.clamp(math.floor(tonumber(summary.cores) or 0), 0, 20)
	local rescues = math.clamp(math.floor(tonumber(summary.rescues) or 0), 0, 20)
	if cores > 0 then
		base += cores * R.PerCore
		table.insert(lines, { string.format("Cores x%d", cores), cores * R.PerCore })
	end
	if rescues > 0 then
		base += rescues * R.PerRescue
		table.insert(lines, { string.format("Rescues x%d", rescues), rescues * R.PerRescue })
	end
	if summary.escaped then
		base += R.Escaped
		table.insert(lines, { "Escaped", R.Escaped })
	end
	local coins = math.floor(base * diff.Reward)
	if diff.Reward ~= 1 then
		table.insert(lines, { string.format("%s x%.1f", summary.difficulty, diff.Reward), coins - base })
	end
	if summary.vip then
		local bonus = math.floor(coins * R.VipBonus)
		coins += bonus
		table.insert(lines, { "VIP +10%", bonus })
	end
	return { coins = coins, xp = coins * R.XpPerCoin, lines = lines }
end

-- XP needed to reach `level` (level 1 = 0).
function Progress.xpFor(level)
	level = math.max(1, math.floor(level))
	return math.floor(100 * (level - 1) ^ 1.6)
end

function Progress.levelFor(xp)
	local level = 1
	while Progress.xpFor(level + 1) <= (xp or 0) and level < 200 do
		level += 1
	end
	return level
end

--[[
	Daily streak. `day` is the UTC day number (os.time() // 86400). Returns
	(canClaim, newStreak, rewardIndex). Missing a day resets the streak to 1; the reward
	list repeats its last entry after 7 days.
]]
function Progress.daily(state, day)
	local last = tonumber(state.LastDay) or -10
	if last == day then
		return false, state.Streak or 0, nil
	end
	local streak = if last == day - 1 then (state.Streak or 0) + 1 else 1
	local index = math.min(streak, #GameConfig.DailyRewards)
	return true, streak, index
end

-- Normalises a code the way players type it.
function Progress.normalizeCode(raw)
	if type(raw) ~= "string" or #raw > 40 then
		return nil
	end
	local code = string.upper((raw:gsub("%s", "")))
	if code == "" then
		return nil
	end
	return code
end

return Progress
