local load = require("./loader")
local CrateRoll = load("CrateRoll")
local Rng = load("Rng")
local CosmeticConfig = load("Config/CosmeticConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "CrateRoll: " .. name, fn = fn })
end

test("displayed odds add up to 100% for every crate", function()
	for key, crate in pairs(CosmeticConfig.Crates) do
		local sum = 0
		for _, row in ipairs(CrateRoll.odds(crate, CosmeticConfig)) do
			sum += row.percent
		end
		assert(math.abs(sum - 100) < 1e-6, key .. " sums to " .. sum)
	end
end)

test("every rarity a crate can roll has items in that crate's categories", function()
	for key, crate in pairs(CosmeticConfig.Crates) do
		for rarity, w in pairs(crate.Odds) do
			if w > 0 then
				assert(#CrateRoll.pool(CosmeticConfig, rarity, crate) > 0, key .. " can roll empty rarity " .. rarity)
			end
		end
	end
end)

test("skin crate only gives skins, never defaults", function()
	local crate = CosmeticConfig.Crates.Skin
	local rng = Rng.new(9)
	for _ = 1, 500 do
		local item = CrateRoll.roll(crate, CosmeticConfig, rng, 0)
		assert(item.Category == "Skin" and not item.Default)
	end
end)

test("roll frequencies roughly match the published odds", function()
	local crate = CosmeticConfig.Crates.Locker
	local rng = Rng.new(42)
	local counts, n = {}, 20000
	local pity = 0
	for _ = 1, n do
		local _, info = CrateRoll.roll(crate, CosmeticConfig, rng, 0)
		counts[info.rarity] = (counts[info.rarity] or 0) + 1
		pity = info.pity
	end
	assert(pity <= 1)
	for _, row in ipairs(CrateRoll.odds(crate, CosmeticConfig)) do
		local got = (counts[row.rarity] or 0) / n * 100
		assert(math.abs(got - row.percent) < 1.5, row.rarity .. " " .. got .. " vs " .. row.percent)
	end
end)

test("pity guarantees Legendary+ and resets", function()
	local crate = CosmeticConfig.Crates.Locker
	local _, info = CrateRoll.roll(crate, CosmeticConfig, Rng.new(1), CosmeticConfig.PityEvery - 1)
	assert(info.pityTriggered and CrateRoll.rankOf(CosmeticConfig, info.rarity) >= CrateRoll.rankOf(CosmeticConfig, "Legendary"))
	assert(info.pity == 0)
end)

test("find is per category (Default exists in several)", function()
	assert(CrateRoll.find(CosmeticConfig, "Skin", "Default").Category == "Skin")
	assert(CrateRoll.find(CosmeticConfig, "Wallpaper", "Default").Category == "Wallpaper")
	assert(CrateRoll.find(CosmeticConfig, "Skin", "Nope") == nil)
end)

return cases
