--[[
	Pure retention logic: daily streak, code normalisation and session goals.
]]

local Rewards = {}

local DAY = 86400

function Rewards.dayNumber(now)
	return math.floor(now / DAY)
end

--[[
	lastDay: UTC day number of the last claim (0 = never). streak: current streak.
	Returns { canClaim, streak (the streak after claiming), rewardIndex, secondsLeft }.
]]
function Rewards.dailyStatus(lastDay, streak, now, rewardCount)
	local today = Rewards.dayNumber(now)
	lastDay = lastDay or 0
	streak = streak or 0
	local canClaim = lastDay < today
	local nextStreak
	if not canClaim then
		nextStreak = streak
	elseif lastDay == today - 1 then
		nextStreak = streak + 1
	else
		nextStreak = 1
	end
	return {
		canClaim = canClaim,
		streak = math.max(nextStreak, 1),
		rewardIndex = ((math.max(nextStreak, 1) - 1) % rewardCount) + 1,
		secondsLeft = if canClaim then 0 else (today + 1) * DAY - now,
	}
end

function Rewards.normalizeCode(code)
	if type(code) ~= "string" or #code > 40 then
		return nil
	end
	local clean = string.upper(code):gsub("[^%w]", "")
	if #clean == 0 or #clean > 20 then
		return nil
	end
	return clean
end

function Rewards.goalFor(def, level, scale)
	local f = scale ^ level
	return {
		id = def.Id,
		target = math.max(1, math.ceil(def.Base * f)),
		reward = math.floor(def.Reward * f / 5 + 0.5) * 5,
		progress = 0,
	}
end

-- Picks `count` goals with different ids (not in `active`).
function Rewards.pickGoals(goalDefs, count, rng, level, scale, active)
	local taken = {}
	for _, g in ipairs(active or {}) do
		taken[g.id] = true
	end
	local out = {}
	local pool = {}
	for _, def in ipairs(goalDefs) do
		if not taken[def.Id] then
			table.insert(pool, def)
		end
	end
	while #out < count and #pool > 0 do
		local def = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(out, Rewards.goalFor(def, level, scale))
	end
	return out
end

-- Adds progress to matching goals; returns the goals that just completed.
function Rewards.progressGoals(goals, eventId, amount)
	local done = {}
	for _, goal in ipairs(goals) do
		if goal.id == eventId and goal.progress < goal.target then
			goal.progress = math.min(goal.target, goal.progress + amount)
			if goal.progress >= goal.target then
				table.insert(done, goal)
			end
		end
	end
	return done
end

return Rewards
