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

test("every rarity a crate can roll has items", function()
	for key, crate in pairs(CosmeticConfig.Crates) do
		for rarity, w in pairs(crate.Odds) do
			if w > 0 then
				assert(#CrateRoll.pool(CosmeticConfig, rarity) > 0, key .. " can roll empty rarity " .. rarity)
			end
		end
	end
end)

test("pass-exclusive items never drop", function()
	local rng = Rng.new(77)
	for _ = 1, 3000 do
		local item = CrateRoll.roll(CosmeticConfig.Crates.Premium, CosmeticConfig, rng, 0)
		assert(not item.Pass and item.Crate ~= false, "dropped exclusive " .. item.Id)
	end
end)

test("rolled rarity frequencies match the published odds", function()
	local rng = Rng.new(2024)
	local crate = CosmeticConfig.Crates.Basic
	local counts = {}
	local n = 20000
	local pity = 0
	for _ = 1, n do
		local _, info = CrateRoll.roll(crate, CosmeticConfig, rng, 0) -- pity disabled (always 0)
		counts[info.rarity] = (counts[info.rarity] or 0) + 1
		pity = info.pity
	end
	for _, row in ipairs(CrateRoll.odds(crate, CosmeticConfig)) do
		local observed = (counts[row.rarity] or 0) / n * 100
		assert(math.abs(observed - row.percent) < 1.5, row.rarity .. " observed " .. observed .. " vs " .. row.percent)
	end
	assert(pity >= 0)
end)

test("pity guarantees Legendary+ and resets", function()
	local rng = Rng.new(5)
	local _, info = CrateRoll.roll(CosmeticConfig.Crates.Basic, CosmeticConfig, rng, CosmeticConfig.PityEvery - 1)
	assert(info.pityTriggered and (info.rarity == "Legendary" or info.rarity == "Mythic"))
	assert(info.pity == 0)
	-- Pity counter never exceeds PityEvery in a long session.
	local pity, maxPity = 0, 0
	for _ = 1, 5000 do
		local _, i = CrateRoll.roll(CosmeticConfig.Crates.Basic, CosmeticConfig, rng, pity)
		pity = i.pity
		maxPity = math.max(maxPity, pity)
	end
	assert(maxPity < CosmeticConfig.PityEvery, "pity overflow " .. maxPity)
end)

test("every item id is unique and has a known category and rarity", function()
	local seen = {}
	for _, item in ipairs(CosmeticConfig.Items) do
		assert(not seen[item.Id], "duplicate id " .. item.Id)
		seen[item.Id] = true
		assert(table.find(CosmeticConfig.Categories, item.Category), item.Id .. " bad category")
		assert(CosmeticConfig.Rarities[item.Rarity], item.Id .. " bad rarity")
	end
	for _, category in ipairs(CosmeticConfig.Categories) do
		local defaults = 0
		for _, item in ipairs(CosmeticConfig.Items) do
			if item.Category == category and item.Default then
				defaults += 1
			end
		end
		assert(defaults == 1, category .. " needs exactly one default")
	end
end)

return cases
