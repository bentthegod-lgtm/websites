--[[
	Session goals (pure, unit tested). A few goals are active at once; completing one
	replaces it with the next goal from the pool. The pool loops with bigger targets.

	state = { active = { { pool = index, cycle = n, progress = number, target = number } }, nextIndex, cycle }
]]

local Goals = {}

local function targetFor(goal, cycle)
	if goal.Stat == "Collect" then
		return goal.Target * 10 ^ cycle
	end
	return goal.Target * (1 + cycle * 2)
end
Goals.targetFor = targetFor

local function pull(state, pool)
	local index = state.nextIndex
	local goal = pool[index]
	local entry = { pool = index, cycle = state.cycle, progress = 0, target = targetFor(goal, state.cycle) }
	state.nextIndex += 1
	if state.nextIndex > #pool then
		state.nextIndex = 1
		state.cycle += 1
	end
	return entry
end

function Goals.new(pool, activeCount)
	local state = { active = {}, nextIndex = 1, cycle = 0 }
	for i = 1, math.min(activeCount, #pool) do
		state.active[i] = pull(state, pool)
	end
	return state
end

-- Adds progress to every active goal tracking `stat`. Stats that track a running maximum
-- can pass `absolute = true` to set progress instead of adding.
-- Returns an array of completed entries ({ goal = poolGoal, entry = entry }).
function Goals.record(state, pool, stat, amount, absolute)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return {}
	end
	local completed = {}
	for slot, entry in ipairs(state.active) do
		local goal = pool[entry.pool]
		if goal.Stat == stat then
			entry.progress = if absolute then math.max(entry.progress, amount) else entry.progress + amount
			if entry.progress >= entry.target then
				table.insert(completed, { goal = goal, entry = entry })
				state.active[slot] = pull(state, pool)
			end
		end
	end
	return completed
end

function Goals.describe(goal, entry, formatNumber)
	local target = entry.target
	local shown = if formatNumber then formatNumber(target) else tostring(target)
	if string.find(goal.Text, "%%s") then
		return (string.format(goal.Text, shown))
	end
	return goal.Text
end

return Goals
