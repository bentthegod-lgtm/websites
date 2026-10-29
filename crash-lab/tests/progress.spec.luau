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

test("prestige: every cycle must beat the requirement again (per-cycle best)", function()
	local p = { Stats = { BestScore = 9000 }, Machines = { Standard = true, AirCannon = true }, RunEarned = 0, Prestige = { Count = 0 } }
	assert(Progress.cycleBest(p) == 9000, "first cycle should use the all-time best")
	assert(Progress.prestige(p).eligible)
	-- After a prestige: CycleBestScore reset to 0 - the old 9000 best no longer counts.
	p.Prestige.Count = 1
	p.Stats.CycleBestScore = 0
	assert(Progress.cycleBest(p) == 0 and not Progress.prestige(p).eligible, "old best carried into the new cycle")
	-- Older saves that prestiged before CycleBestScore existed start the cycle at 0 too.
	p.Stats.CycleBestScore = nil
	assert(Progress.cycleBest(p) == 0 and not Progress.prestige(p).eligible)
	p.Stats.CycleBestScore = 3000
	assert(Progress.prestige(p).eligible and Progress.prestige(p).cycleBest == 3000)
	p.Stats.CycleBestScore = 2999
	assert(not Progress.prestige(p).eligible, "eligible below the requirement")
end)

test("daily challenges: facility challenges only for facilities the player has unlocked", function()
	local CourseConfig = L.shared("Config/CourseConfig")
	local stats = { BestDistance = 300, BestScore = 2000, BestFreeFall = 120, BestCombo = 6 }
	-- No new facility unlocked: never a facility challenge.
	for day = 30000, 30060 do
		for _, c in ipairs(Progress.dailyFor(day, 77, stats, { "Standard" }, {})) do
			assert(c.Id ~= "Facility" and c.Id ~= "FreeFall" and c.Id ~= "Combo", "facility challenge without the facility")
		end
	end
	-- With Destruction only: facility runs there, combo challenges, never free-fall.
	local seenFacility, seenCombo = false, false
	for day = 30000, 30200 do
		for _, c in ipairs(Progress.dailyFor(day, 77, stats, { "Standard" }, { "Destruction" })) do
			assert(c.Id ~= "FreeFall", "free-fall challenge without High-Altitude")
			if c.Id == "Facility" then
				seenFacility = true
				assert(c.Facility == "Destruction" and c.Stat == "Facility:Destruction" and string.find(c.Text, CourseConfig.FacilityById.Destruction.Name, 1, true))
			elseif c.Id == "Combo" then
				seenCombo = true
				assert(c.Single and c.Stat == "RunCombo" and c.Target >= 2)
			end
		end
	end
	assert(seenFacility and seenCombo, "facility challenges never offered")
	-- Same inputs, same list (deterministic); old players' lists are unchanged by the new entries.
	local a = Progress.dailyFor(31000, 9, stats, { "Standard" }, { "HighAltitude" })
	local b = Progress.dailyFor(31000, 9, stats, { "Standard" }, { "HighAltitude" })
	for i, c in ipairs(a) do
		assert(c.Id == b[i].Id and c.Target == b[i].Target)
	end
	local old = Progress.dailyFor(31000, 9, stats, { "Standard" })
	local none = Progress.dailyFor(31000, 9, stats, { "Standard" }, {})
	for i, c in ipairs(old) do
		assert(c.Id == none[i].Id, "lists changed for players without facilities")
	end
end)

test("per-facility personal bests, with the hub falling back to old global stats", function()
	local stats = { BestScore = 900, ["BestScore:Destruction"] = 400 }
	assert(Progress.facilityStat(stats, "BestScore", "Destruction") == 400)
	assert(Progress.facilityStat(stats, "BestScore", "IndustrialLab") == 900, "old saves lost their hub best")
	assert(Progress.facilityStat(stats, "BestScore", "GravityLab") == nil, "a facility inherited another's best")
end)

return cases
