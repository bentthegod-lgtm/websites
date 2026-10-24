local H = require("./helpers")
local Spawner = require("../src/shared/Spawner")
local RarityConfig = require("../src/shared/Config/RarityConfig")
local MutationConfig = require("../src/shared/Config/MutationConfig")
local BlobbyConfig = require("../src/shared/Config/BlobbyConfig")
local cases, test = H.suite("Spawner")

test("rarity chances sum to 1 and luck only helps rare tiers", function()
	local base = Spawner.rarityChances(RarityConfig, 1, 1)
	local lucky = Spawner.rarityChances(RarityConfig, 2, 1)
	local sum = 0
	for _, p in pairs(lucky) do
		sum += p
	end
	H.near(sum, 1, 1e-9)
	assert(lucky.Common < base.Common, "luck should lower Common")
	for i = RarityConfig.LuckFromIndex, #RarityConfig.Order do
		local name = RarityConfig.Order[i]
		assert(lucky[name] > base[name], "luck should raise " .. name)
	end
end)

test("mythic boost raises Mythic and Secret only", function()
	local w1 = Spawner.rarityWeights(RarityConfig, 1, 1)
	local w8 = Spawner.rarityWeights(RarityConfig, 1, 8)
	H.near(w8.Mythic, w1.Mythic * 8)
	H.near(w8.Secret, w1.Secret * 8)
	H.near(w8.Legendary, w1.Legendary)
end)

test("rolls hit every rarity and match the odds roughly", function()
	local rand = H.rng(42)
	local counts = {}
	local n = 200000
	for _ = 1, n do
		local r = Spawner.rollRarity(RarityConfig, rand, 1, 1)
		counts[r] = (counts[r] or 0) + 1
	end
	local chances = Spawner.rarityChances(RarityConfig, 1, 1)
	for _, name in ipairs(RarityConfig.Order) do
		assert(counts[name], "never rolled " .. name)
		local observed = counts[name] / n
		assert(math.abs(observed - chances[name]) < 0.01 + chances[name] * 0.25, name .. " observed " .. observed)
	end
end)

test("pickWeighted skips zero weights and handles the upper edge", function()
	for _, r in ipairs({ 0, 0.5, 0.999999 }) do
		local k = Spawner.pickWeighted({ "a", "b", "c" }, { a = 1, b = 0, c = 3 }, r)
		assert(k == "a" or k == "c")
	end
	H.eq(Spawner.pickWeighted({ "a", "b" }, { a = 0, b = 0 }, 0.3), "a")
end)

test("species rolls stay inside the rarity", function()
	local rand = H.rng(7)
	for _, rarity in ipairs(RarityConfig.Order) do
		for _ = 1, 50 do
			H.eq(Spawner.rollSpecies(BlobbyConfig, rarity, rand).Rarity, rarity)
		end
	end
end)

test("mutation chances are boosted but capped", function()
	local base = Spawner.mutationChances(MutationConfig, 1)
	local boosted = Spawner.mutationChances(MutationConfig, 4)
	H.near(boosted.Gold, base.Gold * 4)
	local huge = Spawner.mutationChances(MutationConfig, 1000)
	local total = 0
	for _, p in pairs(huge) do
		total += p
	end
	H.near(total, MutationConfig.MaxTotalChance, 1e-9)
	local rand = H.rng(3)
	local mutated = 0
	for _ = 1, 20000 do
		if Spawner.rollMutation(MutationConfig, rand, 1) then
			mutated += 1
		end
	end
	local expected = (base.Gold + base.Diamond + base.Rainbow) * 20000
	assert(math.abs(mutated - expected) < expected * 0.2, "mutated " .. mutated .. " expected ~" .. expected)
end)

test("mythic crate only gives Mythic or Secret", function()
	local ShopConfig = require("../src/shared/Config/ShopConfig")
	local crate
	for _, p in ipairs(ShopConfig.Products) do
		if p.Kind == "Crate" then
			crate = p
		end
	end
	local total = 0
	for _, o in ipairs(crate.Odds) do
		total += o.Chance
	end
	H.near(total, 1, 1e-9, "crate odds must add up to 100%")
	local rand = H.rng(11)
	local seen = {}
	for _ = 1, 2000 do
		local r = Spawner.rollCrate(crate.Odds, rand)
		assert(r == "Mythic" or r == "Secret")
		seen[r] = true
	end
	assert(seen.Mythic and seen.Secret)
end)

return cases
