local fs = require("@lune/fs")
local L = require("./loader")
local AudioAssets = L.shared("Config/AudioAssets")
local LootConfig = L.shared("Config/LootConfig")
local DepthConfig = L.shared("Config/DepthConfig")
local ShopConfig = L.shared("Config/ShopConfig")
local CosmeticConfig = L.shared("Config/CosmeticConfig")
local QuestConfig = L.shared("Config/QuestConfig")
local GameConfig = L.shared("Config/GameConfig")
local LightingPresets = L.shared("LightingPresets")
local LootModels = L.shared("LootModels")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Config: " .. name, fn = fn })
end

-- Every id DEAD AIR uses (read from its own config, so this can't drift).
local function deadAirIds()
	local ids = {}
	local ok, text = pcall(fs.readFile, "../dead-air/src/shared/Config/AudioAssets.lua")
	assert(ok, "DEAD AIR's AudioAssets.lua is needed to verify reused audio ids")
	for id in string.gmatch(text, "rbxassetid://%d+") do
		ids[id] = true
	end
	return ids
end

test("audio: no invented ids - every filled id is one DEAD AIR already uses", function()
	local allowed = deadAirIds()
	local filled = 0
	for name, def in pairs(AudioAssets.Sounds) do
		assert(def.Id == "" or allowed[def.Id], name .. " uses an id not found in DEAD AIR: " .. tostring(def.Id))
		assert(def.Id ~= "rbxassetid://123456789", name .. " uses a placeholder id")
		assert(def.Group == "Effects" or def.Group == "Ambient" or def.Group == "Music" or def.Group == "UI", name .. " needs a volume group")
		if def.Id ~= "" then
			filled += 1
		end
	end
	assert(filled >= 15, "expected the reused sound set")
	for _, category in pairs(LootConfig.Categories) do
		assert(AudioAssets.Sounds[category.Sound], "pickup sound cue missing: " .. category.Sound)
	end
	for d = 1, DepthConfig.Count do
		local ambience = AudioAssets.Ambience[DepthConfig.get(d).Ambient]
		assert(ambience, "ambience for depth " .. d)
		for key in pairs(ambience.Loops) do
			assert(AudioAssets.Sounds[key], key)
		end
		for _, key in ipairs(ambience.OneShots) do
			assert(AudioAssets.Sounds[key], key)
		end
		assert(AudioAssets.Sounds[ambience.Music], "music slot " .. ambience.Music)
	end
end)

test("every loot item and stack piece has a model", function()
	for _, def in ipairs(LootConfig.List) do
		assert(LootModels.hasModel(def.Id), def.Id .. " has no model builder")
		local model = LootModels.build(def.Id, L.roblox.CFrame.new(), 1)
		assert(model.PrimaryPart and model.PrimaryPart.Name == "Hitbox", def.Id .. " needs a Hitbox primary part")
		assert(model:GetAttribute("Item") == def.Id, def.Id .. " attribute")
		local parts = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
				assert(d.CanCollide == false and d.Anchored == true, def.Id .. " parts must be anchored and non-colliding")
			end
		end
		assert(parts >= 2 and parts <= 60, def.Id .. " part count " .. parts)
	end
	-- Pool fill: every common-to-rare normal item is ONE part; Epic+ use the detailed model.
	for _, def in ipairs(LootConfig.List) do
		if not def.Special and LootConfig.rank(def) < 4 then
			assert(LootModels.isSimple(def.Id), def.Id .. " needs a single-part fill look")
			local p = LootModels.simple(def.Id, L.roblox.CFrame.new())
			assert(p:IsA("BasePart") and #p:GetChildren() == 0 and not p.CanCollide and p.Anchored and not p.CastShadow, def.Id .. " fill part")
			assert(math.max(p.Size.X, p.Size.Z) <= 2.4, def.Id .. " is wider than a fill slot")
		end
	end
	for _, category in ipairs(LootConfig.CategoryOrder) do
		local piece = LootModels.piece(category, "Classic", L.roblox.CFrame.new(), true)
		assert(#piece:GetChildren() >= 1, category .. " piece is empty")
	end
end)

test("depths: unlock prices rise, every depth has lighting, palette and ambience", function()
	local last = -1
	for d = 1, DepthConfig.Count do
		local def = DepthConfig.get(d)
		assert(def.Depth == d and def.Code == "B" .. d, "depth codes")
		assert(def.UnlockCash > last, "depth " .. d .. " price should rise")
		last = def.UnlockCash
		assert(LightingPresets[def.Lighting], "lighting preset " .. def.Lighting)
		for _, key in ipairs({ "Wall", "Floor", "Trim", "Accent", "Light", "Glow" }) do
			assert(def.Palette[key], "palette " .. key)
		end
	end
	assert(DepthConfig.get(1).UnlockCash == 0, "B1 is free")
	assert(DepthConfig.NextComplex and DepthConfig.NextComplex.ComingSoon, "second complex framework")
	-- Height bands: each floor's y maps back to its depth.
	for d = 1, DepthConfig.Count do
		local y = -(d - 1) * GameConfig.DepthSpacing
		assert(DepthConfig.depthAtY(y + 3, GameConfig.DepthSpacing) == d, "depthAtY " .. d)
		assert(DepthConfig.depthAtY(y + 28, GameConfig.DepthSpacing) == d, "depthAtY ceiling " .. d)
		assert(DepthConfig.depthAtY(y - 42 + 0.5, GameConfig.DepthSpacing) == d, "depthAtY pool bottom " .. d)
	end
end)

test("shop: ids are 0 (never invented) and nothing sells power", function()
	for _, pass in ipairs(ShopConfig.Passes) do
		assert(pass.PassId == 0, pass.Key .. " pass id must stay 0 until created in Creator Hub")
		assert(pass.Key == "VIP" or pass.Kind, pass.Key .. " must be cosmetic or the VIP convenience")
	end
	for _, product in ipairs(ShopConfig.Products) do
		assert(product.ProductId == 0, product.Key .. " product id must stay 0")
		assert(product.Kind or product.Boost, product.Key .. " must be a cosmetic or the timed boost")
		if product.Boost then
			assert(product.Boost <= 900 and ShopConfig.BoostMax <= 3600, "boost must stay modest and temporary")
		end
	end
	for kind, catalog in pairs(CosmeticConfig.Kinds) do
		local defaults = 0
		for id, def in pairs(catalog) do
			for _, stat in ipairs({ "Capacity", "Value", "Speed", "Multiplier", "Radius" }) do
				assert(def[stat] == nil, kind .. ":" .. id .. " must not change " .. stat)
			end
			if def.Source == "Default" then
				defaults += 1
			elseif def.Source == "Tokens" then
				assert(def.Cost and def.Cost > 0, id .. " token cost")
			end
		end
		assert(defaults == 1, kind .. " needs exactly one default")
	end
end)

test("achievements and dailies reference real stats and cosmetics", function()
	local ids = {}
	for _, def in ipairs(QuestConfig.Achievements) do
		assert(not ids[def.Id], "duplicate achievement " .. def.Id)
		ids[def.Id] = true
		assert(type(def.Stat) == "string" and def.Tokens and def.Tokens >= 0, def.Id)
		if def.Cosmetic then
			local kind, item = string.match(def.Cosmetic, "^(%a+):(%a+)$")
			assert(CosmeticConfig.Kinds[kind] and CosmeticConfig.Kinds[kind][item], def.Id .. " cosmetic")
		end
	end
	for _, t in ipairs(QuestConfig.Daily.Templates) do
		assert(DepthConfig.get(t.MinDepth), t.Id)
	end
	for code, reward in pairs(GameConfig.Codes) do
		assert(code == string.upper(code) and (reward.Cash or reward.Tokens), "code " .. code)
	end
end)

return cases
