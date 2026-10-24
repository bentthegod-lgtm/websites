local Rewards = require("../src/shared/Rewards")
local Rng = require("../src/shared/Rng")
local GameConfig = require("../src/shared/Config/GameConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Rewards: " .. name, fn = fn })
end

local DAY = 86400
local N = #GameConfig.Daily

test("first claim is day 1", function()
	local s = Rewards.dailyStatus(0, 0, 100 * DAY + 5, N)
	assert(s.canClaim and s.streak == 1 and s.rewardIndex == 1)
end)

test("claiming on consecutive days grows the streak and cycles after 7", function()
	local lastDay, streak = 0, 0
	for day = 1, 9 do
		local now = (500 + day) * DAY + 3600
		local s = Rewards.dailyStatus(lastDay, streak, now, N)
		assert(s.canClaim)
		assert(s.streak == day, "streak " .. s.streak .. " on day " .. day)
		assert(s.rewardIndex == ((day - 1) % N) + 1)
		lastDay, streak = Rewards.dayNumber(now), s.streak
	end
end)

test("can't claim twice in a day; countdown reaches the next UTC midnight", function()
	local now = 700 * DAY + 3600
	local s = Rewards.dailyStatus(700, 3, now, N)
	assert(not s.canClaim and s.streak == 3)
	assert(s.secondsLeft == DAY - 3600)
end)

test("missing a day resets the streak to 1", function()
	local s = Rewards.dailyStatus(700, 5, 702 * DAY + 10, N)
	assert(s.canClaim and s.streak == 1 and s.rewardIndex == 1)
end)

test("codes are normalised and junk is rejected", function()
	assert(Rewards.normalizeCode(" release ") == "RELEASE")
	assert(Rewards.normalizeCode("like-1k") == "LIKE1K")
	assert(Rewards.normalizeCode("") == nil)
	assert(Rewards.normalizeCode(123) == nil)
	assert(Rewards.normalizeCode(string.rep("A", 60)) == nil)
	assert(GameConfig.Codes[Rewards.normalizeCode("release")], "RELEASE code missing from config")
end)

test("goals: distinct ids, progress, completion and scaling", function()
	local rng = Rng.new(3)
	local goals = Rewards.pickGoals(GameConfig.Goals, 3, rng, 0, GameConfig.GoalScale, {})
	assert(#goals == 3)
	local ids = {}
	for _, g in ipairs(goals) do
		assert(not ids[g.id], "duplicate goal")
		ids[g.id] = true
	end
	local target = goals[1]
	local done = Rewards.progressGoals(goals, target.id, target.target - 1)
	assert(#done == 0)
	done = Rewards.progressGoals(goals, target.id, 5)
	assert(#done == 1 and target.progress == target.target)
	assert(#Rewards.progressGoals(goals, target.id, 1) == 0, "completed goal fired twice")
	local def = GameConfig.Goals[1]
	local easy, hard = Rewards.goalFor(def, 0, GameConfig.GoalScale), Rewards.goalFor(def, 3, GameConfig.GoalScale)
	assert(hard.target > easy.target and hard.reward > easy.reward)
	local fresh = Rewards.pickGoals(GameConfig.Goals, 1, rng, 1, GameConfig.GoalScale, goals)
	assert(fresh[1] and not ids[fresh[1].id], "replacement duplicated an active goal")
end)

return cases
