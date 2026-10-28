local L = require("./loader")
local AudioAssets = L.shared("Config/AudioAssets")
local CourseConfig = L.shared("Config/CourseConfig")
local QuestConfig = L.shared("Config/QuestConfig")
local CosmeticConfig = L.shared("Config/CosmeticConfig")
local ShopConfig = L.shared("Config/ShopConfig")
local MachineConfig = L.shared("Config/MachineConfig")
local UpgradeConfig = L.shared("Config/UpgradeConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Config: " .. name, fn = fn })
end

-- Every id here appears in DEAD AIR's AudioAssets (checked Creator Store picks). Nothing
-- else may be used: no invented audio ids.
local ALLOWED_AUDIO = {
	["rbxassetid://1837829565"] = true,
	["rbxassetid://1837953706"] = true,
	["rbxassetid://9043338697"] = true,
	["rbxassetid://9112823813"] = true,
	["rbxassetid://9112889082"] = true,
	["rbxassetid://9113134899"] = true,
	["rbxassetid://9113722650"] = true,
	["rbxassetid://9113880475"] = true,
	["rbxassetid://9114480271"] = true,
	["rbxassetid://9114533169"] = true,
	["rbxassetid://9114591515"] = true,
	["rbxassetid://9116537007"] = true,
	["rbxassetid://9116612715"] = true,
	["rbxassetid://9116892199"] = true,
	["rbxassetid://9119386548"] = true,
	["rbxassetid://9119631707"] = true,
	["rbxassetid://9119661709"] = true,
	["rbxassetid://9120098454"] = true,
	["rbxassetid://9120851227"] = true,
	["rbxassetid://9125446564"] = true,
}

test("audio: no invented ids (only empty or reused DEAD AIR ids); every cue has a group", function()
	for name, def in pairs(AudioAssets) do
		assert(def.Id == "" or ALLOWED_AUDIO[def.Id], name .. " uses an unknown id " .. tostring(def.Id))
		assert(def.Group == "Effects" or def.Group == "Ambient" or def.Group == "Music" or def.Group == "UI", name .. " has no volume group")
	end
	for _, m in pairs(MachineConfig.ById) do
		assert(AudioAssets[m.Sound.Charge] and AudioAssets[m.Sound.Fire], m.Id .. " sound cue missing")
	end
	for _, kind in pairs(CourseConfig.DestructibleKinds) do
		assert(AudioAssets[kind.Sound], kind.Name .. " sound cue missing")
	end
end)

test("objectives reference real rings / targets / zones / prop groups", function()
	local groups = { Fence = true, PanelWall = true, Boxes = true, Pins = true, Tower = true }
	for _, o in ipairs(CourseConfig.Objectives) do
		if o.Kind == "Ring" then
			assert(CourseConfig.RingById[o.Id], o.Id)
		elseif o.Kind == "Target" then
			assert(CourseConfig.TargetById[o.Id], o.Id)
		elseif o.Kind == "Land" then
			assert(CourseConfig.ZoneById[o.Id], o.Id)
		elseif o.Kind == "Break" then
			assert(groups[o.Group], o.Id)
		elseif o.Kind == "Distance" or o.Kind == "Multi" then
			assert(o.Value and o.Value > 0, o.Id)
		else
			error("unknown objective kind " .. tostring(o.Kind))
		end
		assert(o.Points > 0 and o.MinReach > 0)
	end
	-- Something is always offered to a brand-new player.
	local easiest = math.huge
	for _, o in ipairs(CourseConfig.Objectives) do
		easiest = math.min(easiest, o.MinReach)
	end
	assert(easiest <= 90, "no objective reachable on day one")
end)

test("cosmetics, shop items and achievements reference each other correctly", function()
	for kind, catalog in pairs(CosmeticConfig.Kinds) do
		for id, def in pairs(catalog) do
			if def.Source == "Achievement" then
				assert(QuestConfig.AchievementById[def.Achievement], kind .. ":" .. id .. " needs a missing achievement")
			elseif def.Source == "Coins" then
				assert(def.Cost and def.Cost > 0, kind .. ":" .. id .. " has no price")
			end
		end
	end
	for _, list in ipairs({ ShopConfig.Products, ShopConfig.Passes }) do
		for _, item in ipairs(list) do
			local def = CosmeticConfig.Kinds[item.Kind] and CosmeticConfig.Kinds[item.Kind][item.Item]
			assert(def and def.Source == "Robux", item.Key .. " sells a non-Robux or missing cosmetic")
			assert((item.ProductId or item.PassId) == 0, item.Key .. " has a hard-coded id")
		end
	end
	for _, a in ipairs(QuestConfig.Achievements) do
		if a.Cosmetic then
			assert(CosmeticConfig.Skins[a.Cosmetic], a.Id .. " grants a missing skin")
		end
	end
end)

test("tutorial events, machine requirements and upgrade keys are all real", function()
	local events = { ClaimPad = true, Launch = true, RunDone = true, Upgrade = true, Objective = true }
	for _, step in ipairs(QuestConfig.Tutorial) do
		assert(events[step.Event], "unknown tutorial event " .. step.Event)
	end
	for _, id in ipairs(MachineConfig.Order) do
		local req = MachineConfig.ById[id].Requirement
		if req then
			assert(req.Stat == "BestDistance" or UpgradeConfig.ByKey[req.Stat], id .. " requirement stat")
		end
	end
	local categories = {}
	for _, c in ipairs(UpgradeConfig.Categories) do
		categories[c] = 0
	end
	for _, def in ipairs(UpgradeConfig.List) do
		assert(categories[def.Category], def.Key .. " has an unknown category")
		categories[def.Category] += 1
	end
	for c, n in pairs(categories) do
		assert(n >= 2, c .. " has only " .. n .. " upgrades")
	end
end)

return cases
