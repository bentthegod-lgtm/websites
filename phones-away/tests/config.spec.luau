local load = require("./loader")
local ShopConfig = load("Config/ShopConfig")
local CosmeticConfig = load("Config/CosmeticConfig")
local PhoneConfig = load("Config/PhoneConfig")
local TeacherConfig = load("Config/TeacherConfig")
local ProgressionConfig = load("Config/ProgressionConfig")
local AudioAssets = load("Config/AudioAssets")
local ChatLines = load("Config/ChatLines")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Config: " .. name, fn = fn })
end

test("every product / pass has a 0 placeholder id, a unique key and a display price", function()
	local keys = {}
	for _, p in ipairs(ShopConfig.Products) do
		assert(p.ProductId == 0, p.Key .. " has a real-looking id")
		assert(not keys[p.Key], "duplicate " .. p.Key)
		keys[p.Key] = true
		assert(type(p.Robux) == "number" and p.Robux > 0 and p.Grants)
	end
	for _, p in ipairs(ShopConfig.Passes) do
		assert(p.PassId == 0, p.Key .. " has a real-looking id")
		assert(not keys[p.Key], "duplicate " .. p.Key)
		keys[p.Key] = true
	end
	for _, key in ipairs({ "PizzaParty", "DetentionPass", "HallPass", "AnswerPeek", "SkinCrate", "DoubleClout", "VIP", "SilentMode", "ExtraHide", "ProPhone" }) do
		assert(keys[key], key .. " missing")
	end
end)

test("random-item products are flagged and point at a real crate", function()
	for _, p in ipairs(ShopConfig.Products) do
		if p.Grants.Crate then
			assert(p.Random == true, p.Key .. " must be flagged Random (PolicyService)")
			assert(CosmeticConfig.Crates[p.Grants.Crate])
		end
	end
end)

test("cosmetics: one default per category, unique ids per category, known rarities", function()
	local defaults, seen = {}, {}
	for _, item in ipairs(CosmeticConfig.Items) do
		assert(CosmeticConfig.Rarities[item.Rarity], item.Id .. " rarity")
		local key = item.Category .. "/" .. item.Id
		assert(not seen[key], "duplicate " .. key)
		seen[key] = true
		if item.Default then
			defaults[item.Category] = (defaults[item.Category] or 0) + 1
		end
	end
	for _, cat in ipairs(CosmeticConfig.Categories) do
		assert(defaults[cat] == 1, cat .. " defaults " .. tostring(defaults[cat]))
	end
end)

test("scanner config and grades are well formed", function()
	local snap = PhoneConfig.Snap
	assert(snap.AimSeconds > 0 and snap.FlashMultiplier > 1 and snap.FlashInstant > 0)
	local GameConfig = load("Config/GameConfig")
	local last = math.huge
	for _, g in ipairs(GameConfig.Test.Grades) do
		assert(g.Min < last and g.Clout > 0, g.Letter)
		last = g.Min
	end
	assert(GameConfig.Test.Grades[1].Letter == "A+" and GameConfig.Test.Grades[#GameConfig.Test.Grades].Min == 0)
end)

test("the answer key is not in shared (replicated) code", function()
	local fs = require("@lune/fs")
	local function walk(dir)
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path)
			else
				assert(not string.find(fs.readFile(path), "The capital of Turkey is...", 1, true), "question bank found in " .. path)
			end
		end
	end
	walk("src/shared")
	walk("src/client")
end)

test("teacher phases and events are complete", function()
	for _, phase in ipairs({ "Board", "Lecture", "Walk", "Quiz", "FireDrill", "LunchCheck" }) do
		local p = TeacherConfig.Phases[phase]
		assert(p and p.Label and p.Duration and p.Sight and p.Hearing, phase)
	end
	for _, key in ipairs(TeacherConfig.EventOrder) do
		assert(TeacherConfig.Events[key].Weight > 0, key)
	end
	assert(TeacherConfig.Phases.Board.Sight == 0, "board phase must be safe")
end)

test("goals reference stats and rewards; ranks are ordered", function()
	for _, g in ipairs(ProgressionConfig.Goals) do
		assert(g.Id and g.Stat and g.Target > 0 and g.Clout > 0)
	end
	local last = 0
	for _, r in ipairs(ProgressionConfig.Ranks) do
		assert(r.MinLevel > last)
		last = r.MinLevel
	end
	assert(ProgressionConfig.Ranks[#ProgressionConfig.Ranks].Name == "Legend")
end)

test("audio: no invented ids (only empty or reused dead-air ids)", function()
	local allowed = {
		["rbxassetid://9113880475"] = true, ["rbxassetid://9125756882"] = true, ["rbxassetid://9125757128"] = true,
		["rbxassetid://9116173869"] = true, ["rbxassetid://9113087803"] = true, ["rbxassetid://9119661709"] = true,
		["rbxassetid://9120839599"] = true, ["rbxassetid://9119129301"] = true, ["rbxassetid://9119633070"] = true,
		["rbxassetid://9120851227"] = true, ["rbxassetid://9043338697"] = true, ["rbxassetid://1837953706"] = true,
		["rbxassetid://9113722650"] = true, ["rbxassetid://9114480271"] = true,
	}
	for name, def in pairs(AudioAssets) do
		assert(def.Id == "" or allowed[def.Id], name .. " uses an unknown id " .. tostring(def.Id))
	end
end)

test("chat lines format with a name", function()
	for key, list in pairs(ChatLines) do
		if key ~= "Handles" then
			for _, line in ipairs(list) do
				local ok = pcall(string.format, line, "Tester")
				assert(ok, line)
			end
		end
	end
end)

return cases
