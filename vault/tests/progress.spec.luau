local L = require("./loader")
local Progress = L.shared("Progress")
local QuestConfig = L.shared("Config/QuestConfig")
local LootConfig = L.shared("Config/LootConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Progress: " .. name, fn = fn })
end

test("UTC day number and reset countdown", function()
	assert(Progress.dayNumber(0) == 0 and Progress.dayNumber(86399) == 0 and Progress.dayNumber(86400) == 1, "day boundaries")
	assert(Progress.secondsUntilNextDay(86400 * 5 + 100) == 86300, "countdown")
end)

test("daily challenges are deterministic per player / day and vary by day", function()
	local a = Progress.rollDaily(12345, 100, 3)
	local b = Progress.rollDaily(12345, 100, 3)
	assert(#a == QuestConfig.Daily.Count, "three challenges")
	for i = 1, #a do
		assert(a[i].Id == b[i].Id and a[i].Target == b[i].Target, "same roll")
	end
	local differs = false
	for day = 101, 110 do
		local c = Progress.rollDaily(12345, day, 3)
		for i = 1, #c do
			if c[i].Id ~= a[i].Id then
				differs = true
			end
		end
	end
	assert(differs, "different days should roll different challenges")
end)

test("daily templates respect min depth; money targets scale with depth", function()
	for day = 1, 40 do
		for _, c in ipairs(Progress.rollDaily(777, day, 1)) do
			for _, t in ipairs(QuestConfig.Daily.Templates) do
				if t.Id == c.Id then
					assert(t.MinDepth <= 1, c.Id .. " should not appear at depth 1")
				end
			end
		end
	end
	local function depositTarget(depth)
		for day = 1, 200 do
			for _, c in ipairs(Progress.rollDaily(5, day, depth)) do
				if c.Id == "Deposit" then
					return c.Target
				end
			end
		end
		return nil
	end
	local t1, t4 = depositTarget(1), depositTarget(4)
	assert(t1 and t4 and t4 > t1 * 100, "deposit targets should scale with depth")
	for _, c in ipairs(Progress.rollDaily(9, 3, 5)) do
		if c.Id == "Visit" then
			assert(c.Stat == "Visit:5", "visit challenge points at the deepest depth")
		end
	end
end)

test("book size and the -1 / -2 achievement targets", function()
	assert(Progress.bookSize() == #LootConfig.List and Progress.bookSize() == 35, "35 entries")
	assert(Progress.achievementTarget({ Target = -1 }) == 35, "whole book")
	assert(Progress.achievementTarget({ Target = -2 }) == 18, "half the book, rounded up")
	assert(Progress.achievementTarget({ Target = 7 }) == 7, "plain target")
end)

test("collect stats and rare finds", function()
	local def = LootConfig.ById.GoldBar
	local stats = Progress.collectStats(def)
	assert(stats[1] == "Collect" and stats[2] == "Collect:Gold" and stats[3] == "CollectId:GoldBar", "stat keys")
	assert(not Progress.isRareFind(def), "a gold bar is not a rare find")
	assert(Progress.isRareFind(LootConfig.ById.PerfectDiamond), "a Mythic special is")
end)

return cases
