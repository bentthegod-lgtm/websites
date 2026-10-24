local Stock = require("../src/shared/Stock")
local Crate = require("../src/shared/Crate")
local WeatherLogic = require("../src/shared/WeatherLogic")
local Rng = require("../src/shared/Rng")
local CropConfig = require("../src/shared/Config/CropConfig")
local RarityConfig = require("../src/shared/Config/RarityConfig")
local ShopConfig = require("../src/shared/Config/ShopConfig")
local WeatherConfig = require("../src/shared/Config/WeatherConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Stock/Crate/Weather: " .. name, fn = fn })
end

test("restock windows align to the interval", function()
	assert(Stock.index(599, 300) == 1 and Stock.index(600, 300) == 2)
	assert(Stock.nextAt(601, 300) == 900)
	assert(Stock.nextAt(900, 300) == 1200)
end)

test("the same window rolls the same stock (cross-server consistency)", function()
	local a = Stock.roll(CropConfig.List, Rng.new(Stock.seedFor(12345)))
	local b = Stock.roll(CropConfig.List, Rng.new(Stock.seedFor(12345)))
	assert(#a == #b)
	for i = 1, #a do
		assert(a[i].crop == b[i].crop and a[i].qty == b[i].qty)
	end
end)

test("carrots and radishes are always in stock; quantities stay in range", function()
	for seed = 1, 300 do
		local items = Stock.roll(CropConfig.List, Rng.new(seed))
		local found = {}
		for _, item in ipairs(items) do
			local crop = CropConfig.ById[item.crop]
			assert(item.qty >= crop.StockQty[1] and item.qty <= crop.StockQty[2], "qty out of range")
			found[item.crop] = true
		end
		assert(found.Carrot and found.Radish, "always-stocked seed missing")
	end
end)

test("rare seeds appear about as often as configured", function()
	local rng = Rng.new(777)
	local seen = 0
	local runs = 20000
	for _ = 1, runs do
		for _, item in ipairs(Stock.roll(CropConfig.List, rng)) do
			if item.crop == "DragonFruit" then
				seen += 1
			end
		end
	end
	local rate = seen / runs
	local expected = CropConfig.ById.DragonFruit.StockChance
	assert(math.abs(rate - expected) < expected * 0.25, string.format("rate %.4f vs %.4f", rate, expected))
end)

test("only Legendary+ stock is announced", function()
	local items = { { crop = "Carrot", qty = 5 }, { crop = "GlowMushroom", qty = 1 }, { crop = "Apple", qty = 1 }, { crop = "PrismPear", qty = 1 } }
	local rare = Stock.rare(items, CropConfig.ById, RarityConfig)
	assert(#rare == 2 and rare[1] == "GlowMushroom" and rare[2] == "PrismPear", table.concat(rare, ","))
end)

test("crate odds add up to 100% and match the weights", function()
	local crate = ShopConfig.Crates.SeedCrate
	local odds = Crate.odds(crate, CropConfig.List)
	local total = 0
	for _, o in ipairs(odds) do
		total += o.chance
		assert(#o.crops > 0)
	end
	assert(math.abs(total - 1) < 1e-9, "total " .. total)
	assert(odds[1].rarity == "Uncommon" and math.abs(odds[1].chance - 0.4) < 1e-9)
end)

test("crate rolls follow the odds and never give Common seeds", function()
	local crate = ShopConfig.Crates.SeedCrate
	local rng = Rng.new(31337)
	local byRarity = {}
	local n = 50000
	for _ = 1, n do
		local id, rarity = Crate.roll(crate, CropConfig.List, rng)
		assert(CropConfig.ById[id].Rarity == rarity)
		assert(rarity ~= "Common", "crate gave a Common seed")
		byRarity[rarity] = (byRarity[rarity] or 0) + 1
	end
	assert(math.abs(byRarity.Uncommon / n - 0.4) < 0.02)
	assert(math.abs(byRarity.Mythic / n - 0.03) < 0.006)
	assert((byRarity.Prismatic or 0) > 40 and byRarity.Prismatic < 170, "prismatic " .. tostring(byRarity.Prismatic))
end)

test("weather pick respects weights and never repeats the excluded event", function()
	local rng = Rng.new(9)
	local counts = {}
	for _ = 1, 20000 do
		local key = WeatherLogic.pick(WeatherConfig, rng, "Rain")
		assert(key ~= "Rain")
		counts[key] = (counts[key] or 0) + 1
	end
	assert(counts.Thunderstorm > counts.GoldenHour and counts.GoldenHour > counts.Aurora)
	assert(counts.Aurora > 0 and counts.BloodMoon > counts.Aurora)
	for _ = 1, 100 do
		local gap = WeatherLogic.gap(WeatherConfig, rng)
		assert(gap >= WeatherConfig.MinGap and gap <= WeatherConfig.MaxGap)
	end
end)

return cases
