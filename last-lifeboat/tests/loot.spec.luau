local L = require("./loader")
local GameConfig = L.shared("Config/GameConfig")
local LootMath = L.shared("LootMath")
local Rng = L.shared("Rng")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Loot: " .. name, fn = fn })
end

test("slots: base 3, upgrades to 6, VIP +1", function()
	assert(LootMath.slots(0, false) == 3 and LootMath.slots(5, false) == 6 and LootMath.slots(0, true) == 4 and LootMath.slots(5, true) == 7)
end)

test("heavy items slow you down, never below MinWalk", function()
	assert(LootMath.walkSpeed({}) == GameConfig.Move.Walk)
	local gold = LootMath.walkSpeed({ "GoldBar" })
	assert(gold < GameConfig.Move.Walk and LootMath.walkSpeed({ "PocketWatch", "PearlNecklace" }) == GameConfig.Move.Walk, "light items slowed")
	assert(LootMath.walkSpeed({ "GoldBar", "GoldBar", "Painting", "GoldBar" }) == GameConfig.Move.MinWalk, "floor")
	assert(LootMath.weight({ "Painting", "GoldBar" }) == 5)
end)

test("rarity rolls: deeper decks and bigger ships roll rarer loot; every rarity happens", function()
	local function rareShare(depth, tier)
		local rng = Rng.new(5)
		local rare, seen = 0, {}
		for _ = 1, 4000 do
			local key = LootMath.roll(rng, depth, tier)
			local def = GameConfig.Loot[key]
			assert(def, "rolled unknown item")
			seen[def.Rarity] = true
			if def.Rarity ~= "Common" then
				rare += 1
			end
		end
		return rare / 4000, seen
	end
	local top = rareShare(0, 1)
	local deep, seen = rareShare(1, 3)
	assert(deep > top + 0.15, string.format("depth/tier barely matter: %.2f vs %.2f", top, deep))
	for _, r in ipairs(GameConfig.RarityOrder) do
		assert(seen[r], r .. " never rolled")
	end
	assert(top > 0.25 and top < 0.55, "top deck rare share " .. top)
end)

test("payout: only escapes bank loot; ship tier, Full Crew and x2 multiply; revives add", function()
	local items = { "PocketWatch", "GoldBar" } -- 40 + 300
	local lost = LootMath.payout({ escaped = false, items = items, shipKey = "Gull" })
	assert(lost.coins == GameConfig.Rewards.Participation and lost.banked == 0, "lost players banked loot")
	local gull = LootMath.payout({ escaped = true, items = items, shipKey = "Gull" })
	assert(gull.banked == 340 and gull.coins == 340 + GameConfig.Rewards.EscapeBase, "gull " .. gull.coins)
	local lev = LootMath.payout({ escaped = true, items = items, shipKey = "Leviathan" })
	assert(lev.coins == math.floor(340 * 2.2) + math.floor(40 * 2.2), "leviathan " .. lev.coins)
	local full = LootMath.payout({ escaped = true, items = items, shipKey = "Gull", fullCrew = true })
	assert(full.coins == math.floor(340 * 1.25) + 40, "full crew " .. full.coins)
	local double = LootMath.payout({ escaped = true, items = items, shipKey = "Gull", fullCrew = true, double = true })
	assert(double.coins == math.floor(340 * 1.25 * 2) + 40, "x2 " .. double.coins)
	local sum = 0
	for _, line in ipairs(double.lines) do
		sum += line[2]
	end
	assert(sum == double.coins, "result lines don't add up: " .. sum .. " vs " .. double.coins)
	local rev = LootMath.payout({ escaped = true, items = {}, shipKey = "Gull", revives = 2 })
	assert(rev.coins == 40 + 2 * GameConfig.Rewards.ReviveBonus)
	assert(LootMath.payout({ escaped = true, items = { "RubyTiara" }, shipKey = "Gull" }).bestRank == 4)
	local junk = LootMath.payout({ escaped = true, items = { "Nope" }, shipKey = "Nope", revives = 0 / 0 })
	assert(junk.coins == GameConfig.Rewards.EscapeBase, "junk payout " .. junk.coins)
end)

test("encode / decode carried lists drop junk", function()
	local list = LootMath.decode(LootMath.encode({ "GoldBar", "PocketWatch" }) .. ",Hack,,")
	assert(#list == 2 and list[1] == "GoldBar")
	assert(#LootMath.decode(nil) == 0)
end)

return cases
