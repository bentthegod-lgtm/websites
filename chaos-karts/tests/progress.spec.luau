local Loader = require("./loader")
local Progress = Loader.shared("Progress")
local GameConfig = Loader.shared("Config/GameConfig")
local Format = Loader.shared("Format")

return {
	{
		name = "Progress: daily streak (claim once a day, missing a day resets, the 7th day repeats)",
		fn = function()
			local state = { LastDay = 0, Streak = 0 }
			local can, streak, index = Progress.daily(state, 100)
			assert(can and streak == 1 and index == 1)
			state.LastDay, state.Streak = 100, 1
			assert(not Progress.daily(state, 100), "claimed twice")
			can, streak = Progress.daily(state, 101)
			assert(can and streak == 2)
			can, streak = Progress.daily(state, 103)
			assert(can and streak == 1, "missed day kept the streak")
			state.LastDay, state.Streak = 200, 9
			local _, _, idx = Progress.daily(state, 201)
			assert(idx == #GameConfig.DailyRewards)
		end,
	},
	{
		name = "Progress: codes are case / space insensitive; levels from XP",
		fn = function()
			assert(Progress.normalizeCode(" release ") == "RELEASE" and Progress.normalizeCode("ch aos") == "CHAOS")
			assert(Progress.normalizeCode("") == nil and Progress.normalizeCode(5) == nil and Progress.normalizeCode(string.rep("a", 50)) == nil)
			local l, into, need = Progress.level(0)
			assert(l == 1 and into == 0 and need == GameConfig.Levels.Base)
			l = Progress.level(GameConfig.Levels.Base)
			assert(l == 2)
			l = Progress.level(10 ^ 9)
			assert(l == GameConfig.Levels.Max)
		end,
	},
	{
		name = "Format: race times and ordinals",
		fn = function()
			assert(Format.raceTime(83.456) == "1:23.456", Format.raceTime(83.456))
			assert(Format.raceTime(nil) == "--:--.---")
			assert(Format.ordinal(1) == "1st" and Format.ordinal(2) == "2nd" and Format.ordinal(3) == "3rd" and Format.ordinal(11) == "11th" and Format.ordinal(12) == "12th" and Format.ordinal(22) == "22nd")
		end,
	},
}
