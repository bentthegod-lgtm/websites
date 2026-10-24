local CropConfig = require("../src/shared/Config/CropConfig")
local RarityConfig = require("../src/shared/Config/RarityConfig")
local MutationConfig = require("../src/shared/Config/MutationConfig")
local WeatherConfig = require("../src/shared/Config/WeatherConfig")
local GearConfig = require("../src/shared/Config/GearConfig")
local ShopConfig = require("../src/shared/Config/ShopConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local AudioAssets = require("../src/shared/Config/AudioAssets")
local Growth = require("../src/shared/Growth")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Config: " .. name, fn = fn })
end

local ARCHETYPES = { Root = true, Leafy = true, Bush = true, Stake = true, Stalk = true, Ground = true, Cactus = true, Tree = true, Palm = true, Mushroom = true, Rosette = true, Lotus = true }

test("about 25 crops covering every rarity, all fields valid", function()
	assert(#CropConfig.List >= 24 and #CropConfig.List <= 30, "crop count " .. #CropConfig.List)
	local rarities = {}
	for _, crop in ipairs(CropConfig.List) do
		assert(RarityConfig.Tiers[crop.Rarity], crop.Id .. " rarity")
		rarities[crop.Rarity] = true
		assert(crop.SeedPrice > 0 and crop.Value > 0 and crop.BaseKg > 0 and crop.GrowTime > 0, crop.Id .. " numbers")
		assert(crop.StockChance > 0 and crop.StockChance <= 1, crop.Id .. " stock chance")
		assert(crop.StockQty[1] >= 1 and crop.StockQty[2] >= crop.StockQty[1], crop.Id .. " stock qty")
		assert(ARCHETYPES[crop.Model.Type], crop.Id .. " model type " .. tostring(crop.Model.Type))
		assert(#crop.Model.Leaf == 3 and #crop.Model.Fruit == 3, crop.Id .. " colours")
		if crop.Regrow then
			-- Regrowing plants must restart at the Full stage.
			assert(crop.Regrow <= crop.GrowTime * (1 - Growth.FULL), crop.Id .. " regrow too long")
		end
	end
	for _, r in ipairs(RarityConfig.Order) do
		assert(rarities[r], "no crop of rarity " .. r)
	end
end)

test("required crops from the design are present", function()
	for _, id in ipairs({ "Carrot", "Strawberry", "Blueberry", "Tomato", "Corn", "Pumpkin", "Watermelon", "Apple", "Coconut", "Cactus", "DragonFruit", "Mango", "GlowMushroom", "MoonMelon", "StarFruit" }) do
		assert(CropConfig.ById[id], "missing " .. id)
	end
end)

test("rarer seeds cost more and stock less often", function()
	local function avg(rarity, field)
		local total, n = 0, 0
		for _, crop in ipairs(CropConfig.List) do
			if crop.Rarity == rarity then
				total += crop[field]
				n += 1
			end
		end
		return total / n
	end
	for i = 2, #RarityConfig.Order do
		local lo, hi = RarityConfig.Order[i - 1], RarityConfig.Order[i]
		assert(avg(hi, "SeedPrice") > avg(lo, "SeedPrice"), hi .. " seeds should cost more than " .. lo)
		assert(avg(hi, "StockChance") < avg(lo, "StockChance") or avg(lo, "StockChance") == 1, hi .. " should stock less often")
	end
end)

test("every crop pays back its seed price", function()
	for _, crop in ipairs(CropConfig.List) do
		if crop.Regrow then
			local harvests = math.ceil(crop.SeedPrice / crop.Value)
			assert(harvests <= 8, crop.Id .. " needs " .. harvests .. " harvests to pay back its seed")
		else
			assert(crop.Value > crop.SeedPrice, crop.Id .. " sells for less than its seed")
		end
	end
end)

test("weather events reference real mutations and have lighting", function()
	for _, key in ipairs(WeatherConfig.Order) do
		local e = WeatherConfig.Events[key]
		assert(e, key)
		assert(e.Weight > 0 and e.Duration > 0 and e.TickChance > 0 and e.TickChance <= MutationConfig.ChanceCap)
		assert((e.Mutation and MutationConfig.Mutations[e.Mutation]) or (e.Variant and MutationConfig.Variants[e.Variant]), key .. " mutation")
		if e.StrikeMutation then
			assert(MutationConfig.Mutations[e.StrikeMutation])
		end
		assert(e.Lighting and e.Lighting.ClockTime, key .. " lighting")
	end
	assert(WeatherConfig.MinGap >= 600 and WeatherConfig.MaxGap <= 900, "events should be ~10-15 minutes apart")
end)

test("shop: every id is 0 until set up, keys unique, required items exist", function()
	local keys = {}
	for _, p in ipairs(ShopConfig.Products) do
		assert(p.ProductId == 0, p.Key .. " has a non-zero placeholder id")
		assert(not keys[p.Key], "duplicate " .. p.Key)
		keys[p.Key] = true
		assert(p.Robux > 0)
		if p.Crate then
			assert(ShopConfig.Crates[p.Crate])
		end
		if p.Weather then
			local e = WeatherConfig.Events[p.Weather]
			assert(e and not e.Rare, "totems may only start common weather")
		end
	end
	for _, p in ipairs(ShopConfig.Passes) do
		assert(p.PassId == 0, p.Key .. " has a non-zero placeholder id")
		keys[p.Key] = true
	end
	for _, k in ipairs({ "Coins1", "InstantRestock", "GrowthSkip", "SeedCrate", "RainTotem", "DoubleSell", "VIP", "BigBackpack", "AutoWater", "LuckyGardener" }) do
		assert(keys[k], "missing shop item " .. k)
	end
end)

test("gear, codes and daily rewards reference real things", function()
	for _, id in ipairs(GearConfig.Order) do
		assert(GearConfig.Gear[id] and GearConfig.Gear[id].Price > 0, id)
	end
	local function checkBundle(b, where)
		for crop in pairs(b.Seeds or {}) do
			assert(CropConfig.ById[crop], where .. " seed " .. crop)
		end
		for gear in pairs(b.Gear or {}) do
			assert(GearConfig.Gear[gear], where .. " gear " .. gear)
		end
	end
	for code, b in pairs(GameConfig.Codes) do
		assert(code == string.upper(code), "codes must be upper case")
		checkBundle(b, "code " .. code)
	end
	for i, b in ipairs(GameConfig.Daily) do
		checkBundle(b, "daily " .. i)
	end
	assert(#GameConfig.Daily == 7)
	checkBundle({ Seeds = GameConfig.StartingSeeds, Gear = GameConfig.StartingGear }, "starting kit")
end)

test("no invented audio ids: only reused ids or empty slots", function()
	local allowed = {
		["rbxassetid://9116173869"] = true,
		["rbxassetid://9113880475"] = true,
		["rbxassetid://9116612715"] = true,
		["rbxassetid://9120839599"] = true,
		["rbxassetid://9116537007"] = true,
	}
	for name, def in pairs(AudioAssets) do
		assert(def.Id == "" or allowed[def.Id], name .. " uses an unknown id " .. tostring(def.Id))
	end
end)

return cases
