local L = require("./loader")
local Progress = L.shared("Progress")
local ScrapConfig = L.shared("Config/ScrapConfig")
local QuestConfig = L.shared("Config/QuestConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Progress: " .. name, fn = fn })
end

local function has(list, key)
	return table.find(list, key) ~= nil
end

test("collecting counts the object, its rarity and every lower rarity", function()
	local keys = Progress.collectStats(ScrapConfig.ById.SteelSafe)
	assert(has(keys, "Collect") and has(keys, "CollectId:SteelSafe"))
	assert(has(keys, "CollectRarity:Rare") and has(keys, "CollectRarity:Uncommon") and has(keys, "CollectRarity:Common"))
	assert(not has(keys, "CollectRarity:Legendary"))
	assert(has(keys, "CollectHeavy") and has(keys, "CollectMedium"))
	local can = Progress.collectStats(ScrapConfig.ById.SodaCan)
	assert(not has(can, "CollectMedium") and not has(can, "CollectHeavy"))
end)

test("UTC day boundaries", function()
	assert(Progress.dayNumber(0) == 0 and Progress.dayNumber(86399) == 0 and Progress.dayNumber(86400) == 1)
	assert(Progress.secondsUntilNextDay(86400 * 5 + 100) == 86300)
end)

test("daily objectives are deterministic, distinct and scale with tier", function()
	local a = Progress.rollDaily(12345, 20000, 1)
	local b = Progress.rollDaily(12345, 20000, 1)
	assert(#a == QuestConfig.Daily.Count)
	local ids = {}
	for i, o in ipairs(a) do
		assert(o.Id == b[i].Id and o.Target == b[i].Target, "not deterministic")
		assert(not ids[o.Id], "duplicate objective")
		ids[o.Id] = true
		assert(o.Target >= 1 and o.Reward > 0 and o.Progress == 0 and not o.Done)
	end
	local high = Progress.rollDaily(12345, 20000, 4)
	for i, o in ipairs(high) do
		if o.Id == a[i].Id then
			assert(o.Reward > a[i].Reward, "rewards should scale with tier")
		end
	end
	local otherDay = Progress.rollDaily(12345, 20001, 1)
	local same = true
	for i, o in ipairs(otherDay) do
		if o.Id ~= a[i].Id then
			same = false
		end
	end
	local otherPlayer = Progress.rollDaily(999, 20000, 1)
	for i, o in ipairs(otherPlayer) do
		if o.Id ~= a[i].Id then
			same = false
		end
	end
	assert(not same, "every player gets the same objectives every day")
end)

test("achievement targets: -1 means the whole codex", function()
	for _, a in ipairs(QuestConfig.Achievements) do
		if a.Target == -1 then
			assert(Progress.achievementTarget(a) == #ScrapConfig.List)
		end
	end
end)

return cases
