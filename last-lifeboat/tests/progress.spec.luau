local L = require("./loader")
local GameConfig = L.shared("Config/GameConfig")
local Progress = L.shared("Progress")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Progress: " .. name, fn = fn })
end

test("daily streak: claim once a day, grows on consecutive days, resets after a gap, caps the reward", function()
	local can, streak, index = Progress.daily({ LastDay = 0, Streak = 0 }, 100)
	assert(can and streak == 1 and index == 1)
	can = Progress.daily({ LastDay = 100, Streak = 1 }, 100)
	assert(not can, "claimed twice in a day")
	can, streak = Progress.daily({ LastDay = 100, Streak = 1 }, 101)
	assert(can and streak == 2)
	can, streak = Progress.daily({ LastDay = 100, Streak = 5 }, 103)
	assert(can and streak == 1, "gap did not reset")
	local _, _, idx = Progress.daily({ LastDay = 199, Streak = 30 }, 200)
	assert(idx == #GameConfig.DailyRewards)
end)

test("codes: RELEASE, MAYDAY, ABANDONSHIP exist and normalise", function()
	for _, code in ipairs({ "RELEASE", "MAYDAY", "ABANDONSHIP" }) do
		assert(GameConfig.Codes[code], code)
	end
	assert(Progress.normalizeCode(" may day ") == "MAYDAY" and Progress.normalizeCode("") == nil and Progress.normalizeCode(5) == nil and Progress.normalizeCode(string.rep("a", 50)) == nil)
end)

test("ship unlocks: Gull always, Aurora at 3 escapes, Leviathan at 10", function()
	assert(Progress.shipUnlocked("Gull", 0) and not Progress.shipUnlocked("Aurora", 2) and Progress.shipUnlocked("Aurora", 3))
	assert(not Progress.shipUnlocked("Leviathan", 9) and Progress.shipUnlocked("Leviathan", 10) and not Progress.shipUnlocked("Nope", 99))
end)

test("vote: majority wins, ties go to the easier ship, locked votes don't count, none = Gull", function()
	assert(Progress.tally({}) == "Gull")
	assert(Progress.tally({ a = { ship = "Aurora", escapes = 5 }, b = { ship = "Gull", escapes = 0 } }) == "Gull", "tie")
	assert(Progress.tally({ a = { ship = "Aurora", escapes = 5 }, b = { ship = "Aurora", escapes = 3 }, c = { ship = "Gull", escapes = 0 } }) == "Aurora")
	local winner, counts = Progress.tally({ a = { ship = "Leviathan", escapes = 2 }, b = { ship = "Leviathan", escapes = 0 }, c = { ship = "Gull" } })
	assert(winner == "Gull" and counts.Leviathan == 0, "locked votes counted")
	assert(Progress.tally({ a = "junk", b = { ship = 5 } }) == "Gull")
end)

return cases
