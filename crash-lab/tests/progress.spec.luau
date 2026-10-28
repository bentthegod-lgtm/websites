local L = require("./loader")
local Progress = L.shared("Progress")
local QuestConfig = L.shared("Config/QuestConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Progress: " .. name, fn = fn })
end

test("UTC day number changes exactly at midnight UTC", function()
	local midnight = 1800000000 - (1800000000 % 86400)
	assert(Progress.dayNumber(midnight - 1) + 1 == Progress.dayNumber(midnight))
	assert(Progress.dayNumber(midnight) == Progress.dayNumber(midnight + 86399))
end)

test("daily challenges: deterministic, unique, achievable, machine only if owned", function()
	local stats = { BestDistance = 200, BestScore = 900 }
	local a = Progress.dailyFor(20000, 1234, stats, { "Standard" })
	local b = Progress.dailyFor(20000, 1234, stats, { "Standard" })
	assert(#a == QuestConfig.DailyCount)
	local seen = {}
	for i, c in ipairs(a) do
		assert(c.Id == b[i].Id and c.Target == b[i].Target, "not deterministic")
		assert(not seen[c.Id], "duplicate challenge")
		seen[c.Id] = true
		assert(c.Target > 0 and c.Reward > 0 and type(c.Text) == "string")
		if c.Id == "Distance" then
			assert(c.Target <= stats.BestDistance, "distance challenge above the player's record")
		end
		if c.Machine then
			assert(c.Machine == "Standard" and c.Stat == "Machine:Standard")
		end
	end
	-- Different days or players differ eventually.
	local different = false
	for day = 20001, 20010 do
		local c = Progress.dailyFor(day, 1234, stats, { "Standard" })
		if c[1].Id ~= a[1].Id then
			different = true
		end
	end
	assert(different, "challenges never change")
	-- A new player gets base targets.
	local fresh = Progress.dailyFor(5, 1, {}, { "Standard" })
	for _, c in ipairs(fresh) do
		assert(c.Target >= 1)
	end
end)

test("prestige needs the Air Cannon and the score", function()
	local p = { Stats = { BestScore = 5000 }, Machines = { Standard = true }, RunEarned = 0 }
	assert(not Progress.prestige(p).eligible)
	p.Machines.AirCannon = true
	assert(Progress.prestige(p).eligible)
	p.Stats.BestScore = 100
	assert(not Progress.prestige(p).eligible)
	p.RunEarned = 125000
	assert(Progress.prestige(p).credits == 3)
	assert(#Progress.prestige(p).resets > 0 and #Progress.prestige(p).keeps > 0)
end)

return cases
