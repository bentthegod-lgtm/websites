--[[
	Progress - daily streak, codes and levels (pure, unit-tested).
]]

local GameConfig = require(script.Parent.Config.GameConfig)

local Progress = {}

--[[
	Daily streak. `day` is the UTC day number (os.time() // 86400). Returns
	(canClaim, newStreak, rewardIndex). Missing a day resets the streak to 1; after 7 days
	the last reward repeats.
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

function Progress.xpForLevel(level)
	local L = GameConfig.Levels
	return L.Base + L.Step * (level - 1)
end

-- Level from total XP: returns level, xpIntoLevel, xpNeededForNext.
function Progress.level(totalXp)
	local L = GameConfig.Levels
	local level = 1
	local xp = math.max(0, math.floor(tonumber(totalXp) or 0))
	while level < L.Max do
		local need = Progress.xpForLevel(level)
		if xp < need then
			return level, xp, need
		end
		xp -= need
		level += 1
	end
	return level, 0, 0
end

return Progress
