local L = require("./loader")
local Progress = L.shared("Progress")
local GameConfig = L.shared("Config/GameConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Progress: " .. name, fn = fn })
end

test("round rewards: played < cores < escape; difficulty multiplies; VIP +10%", function()
	local R = GameConfig.Rewards
	local played = Progress.roundReward({ difficulty = "Easy" })
	assert(played.coins == R.Played and played.xp == R.Played * R.XpPerCoin)
	local full = Progress.roundReward({ escaped = true, cores = 2, rescues = 1, difficulty = "Easy" })
	assert(full.coins == R.Played + 2 * R.PerCore + R.PerRescue + R.Escaped)
	local hard = Progress.roundReward({ escaped = true, cores = 2, rescues = 1, difficulty = "Hard" })
	assert(hard.coins == math.floor(full.coins * GameConfig.Difficulties.Hard.Reward))
	local vip = Progress.roundReward({ escaped = true, cores = 2, rescues = 1, difficulty = "Hard", vip = true })
	assert(vip.coins == hard.coins + math.floor(hard.coins * R.VipBonus))
	local sum = 0
	for _, line in ipairs(vip.lines) do
		sum += line[2]
	end
	assert(sum == vip.coins, "lines don't add up")
	local junk = Progress.roundReward({ cores = 1e9, rescues = 0 / 0, difficulty = "Bogus" })
	assert(junk.coins == math.floor((R.Played + 20 * R.PerCore) * GameConfig.Difficulties.Normal.Reward), "junk not clamped")
end)

test("levels: xp curve rises, levelFor inverts it", function()
	assert(Progress.xpFor(1) == 0 and Progress.xpFor(2) == 100)
	for level = 2, 40 do
		assert(Progress.xpFor(level + 1) > Progress.xpFor(level))
		assert(Progress.levelFor(Progress.xpFor(level)) == level)
		assert(Progress.levelFor(Progress.xpFor(level) - 1) == level - 1)
	end
	assert(Progress.levelFor(nil) == 1)
end)

test("daily streak: claim once a day, consecutive days grow, a gap resets, caps at 7", function()
	local ok, streak, index = Progress.daily({ LastDay = 0, Streak = 0 }, 100)
	assert(ok and streak == 1 and index == 1)
	assert(not Progress.daily({ LastDay = 100, Streak = 1 }, 100))
	ok, streak = Progress.daily({ LastDay = 100, Streak = 1 }, 101)
	assert(ok and streak == 2)
	ok, streak = Progress.daily({ LastDay = 100, Streak = 5 }, 103)
	assert(ok and streak == 1)
	ok, streak, index = Progress.daily({ LastDay = 100, Streak = 30 }, 101)
	assert(ok and streak == 31 and index == #GameConfig.DailyRewards)
end)

test("codes are normalised; junk rejected", function()
	assert(Progress.normalizeCode(" thin ice ") == "THINICE")
	assert(Progress.normalizeCode("") == nil and Progress.normalizeCode(42) == nil and Progress.normalizeCode(string.rep("a", 41)) == nil)
	for code in pairs(GameConfig.Codes) do
		assert(Progress.normalizeCode(code) == code, code .. " can't be typed")
	end
end)

return cases
