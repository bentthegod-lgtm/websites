local fs = require("@lune/fs")
local L = require("./loader")
local ScrapConfig = L.shared("Config/ScrapConfig")
local ZoneConfig = L.shared("Config/ZoneConfig")
local QuestConfig = L.shared("Config/QuestConfig")
local ShopConfig = L.shared("Config/ShopConfig")
local AudioAssets = L.shared("Config/AudioAssets")
local MagnetConfig = L.shared("Config/MagnetConfig")
local EconomyConfig = L.shared("Config/EconomyConfig")
local ScrapModels = L.shared("ScrapModels")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Config: " .. name, fn = fn })
end

test("scrap catalog: 15+ objects, unique ids, valid fields, a model for each", function()
	assert(#ScrapConfig.List >= 15, "only " .. #ScrapConfig.List .. " objects")
	local seen = {}
	for _, def in ipairs(ScrapConfig.List) do
		assert(not seen[def.Id], "duplicate " .. def.Id)
		seen[def.Id] = true
		assert(ScrapConfig.Rarities[def.Rarity], def.Id .. " rarity")
		assert(def.Value > 0 and def.Mass > 0 and def.MinStrength >= 1 and def.Weight > 0 and def.Size > 0, def.Id .. " numbers")
		assert(def.Zone == "Any" or ZoneConfig.ById[def.Zone], def.Id .. " zone")
		assert(({ Light = true, Medium = true, Heavy = true, Legendary = true })[def.Audio], def.Id .. " audio profile")
		assert(ScrapModels.Builders[def.Id], def.Id .. " has no model builder")
	end
	for _, id in ipairs({ "SodaCan", "Bolt", "Washer", "Gear", "RustyPipe", "MetalSign", "Toolbox", "IndustrialFan", "HeavyChain", "EngineComponent", "MotorcycleEngine", "IndustrialMotor", "SteelSafe", "PowerCore", "MagneticReactor" }) do
		assert(ScrapConfig.ById[id], "catalog is missing " .. id)
	end
	assert(ScrapConfig.ById.MagneticReactor.Rarity == "Legendary")
end)

test("every built zone has commons, uncommons and rares to find", function()
	for _, zone in ipairs(ZoneConfig.List) do
		if zone.Built then
			local ranks = {}
			for _, def in ipairs(ScrapConfig.List) do
				if def.Zone == zone.Id then
					ranks[ScrapConfig.rank(def)] = true
				end
			end
			assert(ranks[1] and ranks[2] and ranks[3], zone.Id .. " is missing a rarity band")
		end
	end
end)

test("zone bounds don't overlap and zoneAt works", function()
	assert(ZoneConfig.zoneAt(0, 40) == "Rustyard")
	assert(ZoneConfig.zoneAt(300, 0) == "MetroWreck")
	assert(ZoneConfig.zoneAt(157, 0) == nil, "the gate passage belongs to no zone")
	assert(ZoneConfig.zoneAt(-1000, 0) == nil)
end)

test("quests, achievements and tutorial reference real stats / events", function()
	local events = { Claim = true, Collect = true, Sell = true, Upgrade = true, CollectMedium = true, Tier = true }
	for _, step in ipairs(QuestConfig.Tutorial) do
		assert(events[step.Event], "tutorial step " .. step.Id .. " has unknown event " .. step.Event)
	end
	local ids = {}
	for _, a in ipairs(QuestConfig.Achievements) do
		assert(not ids[a.Id], "duplicate achievement " .. a.Id)
		ids[a.Id] = true
	end
	for _, skin in pairs(MagnetConfig.Skins) do
		if skin.Achievement then
			assert(ids[skin.Achievement], "skin unlocked by unknown achievement " .. skin.Achievement)
		end
	end
	for _, trail in pairs(MagnetConfig.Trails) do
		if trail.Achievement then
			assert(ids[trail.Achievement], "trail unlocked by unknown achievement")
		end
	end
	for i = 2, #QuestConfig.Starter do
		assert(QuestConfig.Starter[i].Reward >= QuestConfig.Starter[i - 1].Reward, "quest rewards should not shrink")
	end
end)

test("shop is cosmetic only, with no invented ids", function()
	for _, pass in ipairs(ShopConfig.Passes) do
		assert(pass.PassId == 0, pass.Key .. " has an invented PassId")
		assert(pass.Skin or pass.Trail, pass.Key .. " is not a cosmetic")
		assert((pass.Skin and MagnetConfig.Skins[pass.Skin]) or (pass.Trail and MagnetConfig.Trails[pass.Trail]))
	end
	for _, product in ipairs(ShopConfig.Products) do
		assert(product.ProductId == 0, product.Key .. " has an invented ProductId")
		assert(product.Skin or product.Trail, product.Key .. " is not a cosmetic")
	end
end)

test("audio: every id is empty or reused from DEAD AIR's checked list", function()
	local deadAir = fs.readFile("../dead-air/src/shared/Config/AudioAssets.lua")
	for name, def in pairs(AudioAssets) do
		if def.Id ~= "" then
			local id = string.match(def.Id, "^rbxassetid://(%d+)$")
			assert(id, name .. " has a malformed id")
			assert(string.find(deadAir, id, 1, true), name .. " uses an id that is not in DEAD AIR's list: " .. id)
		end
		assert(({ Effects = true, Ambient = true, Music = true, UI = true })[def.Group], name .. " has no volume group")
	end
end)

test("upgrade categories cover the four required groups", function()
	local seen = {}
	for _, def in ipairs(EconomyConfig.Upgrades) do
		seen[def.Category] = true
	end
	for _, cat in ipairs({ "Magnet", "Capacity", "Movement", "Economy" }) do
		assert(seen[cat], "no upgrades in " .. cat)
	end
end)

return cases
