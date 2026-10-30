local L = require("./loader")
local fs = require("@lune/fs")
local GameConfig = L.shared("Config/GameConfig")
local CosmeticConfig = L.shared("Config/CosmeticConfig")
local ShopConfig = L.shared("Config/ShopConfig")
local AudioAssets = L.shared("Config/AudioAssets")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Config: " .. name, fn = fn })
end

test("difficulties: every field, ordered harder", function()
	local prev
	for _, name in ipairs(GameConfig.DifficultyOrder) do
		local d = GameConfig.Difficulties[name]
		assert(d, name)
		for _, key in ipairs({ "Cores", "ThinScale", "HoleScale", "Braziers", "WarmthDrain", "MonsterSpeed", "MonsterHearing", "Grace", "TimeLimit", "Reward", "Color" }) do
			assert(d[key] ~= nil, name .. "." .. key)
		end
		if prev then
			assert(d.Cores >= prev.Cores and d.MonsterSpeed > prev.MonsterSpeed and d.Grace < prev.Grace and d.Reward > prev.Reward, name .. " not harder")
		end
		-- The monster's hunt speed beats a walker but a sprinter can still break away briefly.
		assert(d.MonsterSpeed > GameConfig.Move.Walk and d.MonsterSpeed <= GameConfig.Move.Sprint, name .. " speed")
		prev = d
	end
end)

test("cosmetics: valid sources, every product / pass grant exists", function()
	for kind, catalog in pairs(CosmeticConfig.Kinds) do
		for id, def in pairs(catalog) do
			assert(def.Name and def.Source, kind .. ":" .. id)
			if def.Source == "Coins" then
				assert(type(def.Cost) == "number" and def.Cost > 0)
			elseif def.Source == "Level" then
				assert(type(def.Level) == "number")
			end
		end
		assert(catalog[CosmeticConfig.Defaults[kind]].Source == "Default")
	end
	assert(#CosmeticConfig.OutfitOrder == 7 and #CosmeticConfig.LanternOrder == 4)
	local productSourced = {}
	for _, p in ipairs(ShopConfig.Products) do
		assert(p.Key and p.Name and p.Robux and p.ProductId == 0 and p.Grants, p.Key)
		for kind, value in pairs(p.Grants) do
			if kind ~= "Flask" then
				assert(CosmeticConfig.Kinds[kind][value].Source == "Product", p.Key .. " grants a non-product cosmetic")
				productSourced[kind .. ":" .. value] = true
			end
		end
	end
	for kind, catalog in pairs(CosmeticConfig.Kinds) do
		for id, def in pairs(catalog) do
			if def.Source == "Product" then
				assert(productSourced[kind .. ":" .. id], kind .. ":" .. id .. " can't be bought")
			end
		end
	end
	assert(ShopConfig.Passes[1].Key == "VIP" and CosmeticConfig.Outfits[ShopConfig.Passes[1].Grants.Outfit].Source == "Pass")
end)

test("audio: no invented IDs (every ID is one DEAD AIR already uses)", function()
	local deadAir = fs.readFile("../dead-air/src/shared/Config/AudioAssets.lua")
	local n = 0
	for slot, def in pairs(AudioAssets) do
		assert(type(def.Id) == "string", slot)
		if def.Id ~= "" then
			local id = string.match(def.Id, "^rbxassetid://(%d+)$")
			assert(id, slot .. " malformed")
			assert(string.find(deadAir, id, 1, true), slot .. " uses an ID not found in DEAD AIR")
			n += 1
		end
	end
	assert(n >= 15, "only " .. n .. " sounds")
end)

test("goals and codes reward something; noise categories have intervals", function()
	for _, goal in ipairs(GameConfig.Goals) do
		assert(goal.Target > 0 and goal.Coins > 0 and goal.Stat)
	end
	for code, def in pairs(GameConfig.Codes) do
		assert((def.Coins or 0) + (def.Flask or 0) > 0, code)
	end
	for gait in pairs(GameConfig.Noise.StepInterval) do
		assert(GameConfig.Noise.Categories[gait], gait)
	end
	assert(GameConfig.Lake.TilesPerStep >= 16 and GameConfig.Lake.TilesPerStep <= 128, "build step")
end)

return cases
