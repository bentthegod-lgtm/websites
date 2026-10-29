local L = require("./loader")
local LootTable = L.shared("LootTable")
local LootConfig = L.shared("Config/LootConfig")
local DepthConfig = L.shared("Config/DepthConfig")
local Rng = L.shared("Rng")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Loot: " .. name, fn = fn })
end

test("every depth has a full normal loot table and one rare-event special", function()
	for d = 1, DepthConfig.Count do
		assert(#LootConfig.ByDepth[d] >= 4, "depth " .. d .. " needs 4+ items")
		assert(LootConfig.SpecialByDepth[d] and LootConfig.SpecialByDepth[d].Special, "depth " .. d .. " special")
		for _, def in ipairs(LootConfig.ByDepth[d]) do
			assert(not def.Special, "specials never roll normally")
		end
	end
end)

test("rolls follow the weights (common items are common)", function()
	local rng = Rng.new(42)
	for d = 1, DepthConfig.Count do
		local counts = {}
		for _ = 1, 4000 do
			local def = LootTable.roll(d, {}, 1, rng, "L")
			counts[def.Id] = (counts[def.Id] or 0) + 1
		end
		local total = 0
		for _, def in ipairs(LootConfig.ByDepth[d]) do
			total += def.SpawnWeight
		end
		for _, def in ipairs(LootConfig.ByDepth[d]) do
			local expected = def.SpawnWeight / total
			local got = (counts[def.Id] or 0) / 4000
			assert(math.abs(got - expected) < 0.04, string.format("%s rolled %.3f, expected %.3f", def.Id, got, expected))
		end
	end
end)

test("caps: an item at MaxActive is never rolled; all capped -> nil", function()
	local rng = Rng.new(7)
	local pool = LootConfig.ByDepth[1]
	local active = { [pool[1].Id] = pool[1].MaxActive }
	for _ = 1, 500 do
		assert(LootTable.roll(1, active, 1, rng, "L").Id ~= pool[1].Id, "capped item rolled")
	end
	for _, def in ipairs(pool) do
		active[def.Id] = def.MaxActive
	end
	assert(LootTable.roll(1, active, 1, rng, "L") == nil, "everything capped should give nil")
end)

test("spawn point size limits are respected", function()
	local rng = Rng.new(9)
	for d = 1, DepthConfig.Count do
		for _ = 1, 400 do
			local def = LootTable.roll(d, {}, 1, rng, "S")
			if def then
				assert(def.Size == "S", def.Id .. " too big for a small point")
			end
		end
	end
end)

test("luck raises the share of Rare+ items, capped at 2x", function()
	local function rareShare(luck)
		local total, rare = 0, 0
		for _, def in ipairs(LootConfig.ByDepth[3]) do
			local w = LootTable.weight(def, luck)
			total += w
			if LootConfig.rank(def) >= 3 then
				rare += w
			end
		end
		return rare / total
	end
	assert(rareShare(2) > rareShare(1), "luck should help")
	assert(math.abs(rareShare(5) - rareShare(2)) < 1e-9, "luck capped at 2")
end)

test("rarities cover Common to Mythic and values rise with rarity inside a depth", function()
	local seen = {}
	for _, def in ipairs(LootConfig.List) do
		seen[def.Rarity] = true
		assert(LootConfig.Rarities[def.Rarity], def.Id .. " has an unknown rarity")
	end
	for _, r in ipairs(LootConfig.RarityOrder) do
		assert(seen[r], "no item of rarity " .. r)
	end
	for d = 1, DepthConfig.Count do
		local list = table.clone(LootConfig.ByDepth[d])
		table.sort(list, function(a, b)
			return LootConfig.rank(a) < LootConfig.rank(b)
		end)
		for i = 2, #list do
			assert(list[i].Value >= list[i - 1].Value, "depth " .. d .. ": rarer item worth less")
		end
		assert(LootConfig.SpecialByDepth[d].Value > list[#list].Value, "special should beat the depth's best item")
	end
end)

test("pool fill: commons are unlimited, Epic+ keep their caps; refill delays are short", function()
	local rng = Rng.new(11)
	for d = 1, DepthConfig.Count do
		local active, epic = {}, 0
		for _ = 1, 1800 do
			local def = LootTable.rollFill(d, active, 1.8, rng)
			assert(def, "depth " .. d .. ": the fill ran dry")
			active[def.Id] = (active[def.Id] or 0) + 1
			if LootConfig.rank(def) >= 4 then
				epic += 1
			end
		end
		for id, n in pairs(active) do
			local def = LootConfig.ById[id]
			if LootConfig.rank(def) >= 4 then
				assert(n <= def.MaxActive, id .. " over its cap in a full pool")
			end
		end
		assert(epic <= 12, "too many detailed models in a pool: " .. epic)
		local delay = DepthConfig.get(d).RefillDelay
		assert(delay and delay > 0 and delay <= 10, "depth " .. d .. " refill delay")
	end
end)

return cases
