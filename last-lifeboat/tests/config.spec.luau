local L = require("./loader")
local fs = require("@lune/fs")
local GameConfig = L.shared("Config/GameConfig")
local ShopConfig = L.shared("Config/ShopConfig")
local AudioAssets = L.shared("Config/AudioAssets")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Config: " .. name, fn = fn })
end

test("ships: three, ordered easier to harder, unlocks 0 / 3 / 10, round times ~3/4/5 min, 8 players", function()
	assert(#GameConfig.ShipOrder == 3 and GameConfig.MaxPlayers == 8)
	local prev
	for i, key in ipairs(GameConfig.ShipOrder) do
		local def = GameConfig.Ships[key]
		assert(def.Order == i and def.Name and def.Blurb and def.Color and def.Hull, key)
		for _, theme in ipairs(def.Decks) do
			assert(GameConfig.Themes[theme], key .. " unknown theme " .. theme)
		end
		assert(def.LurchEvery[1] >= 18 and def.LurchEvery[2] <= 25 and def.LurchEvery[1] < def.LurchEvery[2], key .. " lurch interval")
		if prev then
			assert(def.Length > prev.Length and #def.Decks > #prev.Decks and def.RoundTime > prev.RoundTime and def.UnlockEscapes > prev.UnlockEscapes and def.LootMult > prev.LootMult, key .. " not harder")
		end
		prev = def
	end
	assert(GameConfig.Ships.Gull.UnlockEscapes == 0 and GameConfig.Ships.Aurora.UnlockEscapes == 3 and GameConfig.Ships.Leviathan.UnlockEscapes == 10)
	assert(GameConfig.Ships.Gull.RoundTime == 180 and GameConfig.Ships.Aurora.RoundTime == 240 and GameConfig.Ships.Leviathan.RoundTime == 300)
	assert(not string.find(string.lower(GameConfig.Ships.Leviathan.Name .. GameConfig.Ships.Aurora.Name .. GameConfig.Ships.Gull.Name), "titanic"))
	local project = fs.readFile("default.project.json")
	assert(string.find(project, '"MaxPlayers": 8', 1, true), "server MaxPlayers is not 8")
end)

test("loot: every item has a rarity, a value that rises with rarity, sane weight; heavy items exist", function()
	local minByRank = {}
	local heavy = 0
	for _, key in ipairs(GameConfig.LootOrder) do
		local def = GameConfig.Loot[key]
		assert(def and def.Name and GameConfig.Rarities[def.Rarity] and def.Value > 0 and def.Weight >= 0 and def.Weight <= 3, key)
		local rank = table.find(GameConfig.RarityOrder, def.Rarity)
		minByRank[rank] = math.min(minByRank[rank] or math.huge, def.Value)
		if def.Weight >= 2 then
			heavy += 1
		end
	end
	for rank = 2, #GameConfig.RarityOrder do
		assert(minByRank[rank] > minByRank[rank - 1] * 1.5, "rarity values overlap")
	end
	assert(heavy >= 2 and GameConfig.Loot.GoldBar.Weight >= 2 and GameConfig.Loot.Painting.Weight >= 2)
	local count = 0
	for _ in pairs(GameConfig.Loot) do
		count += 1
	end
	assert(count == #GameConfig.LootOrder, "LootOrder out of sync")
end)

test("shop: every product / pass has a 0 placeholder id, a price and a description; prices as asked", function()
	local want = { LifeJacket = 25, Flare = 49, Coins500 = 49, Coins1500 = 129, Coins4500 = 349, DoubleLoot = 199, Grapple = 249, Captain = 149, VIP = 299 }
	local seen = {}
	for _, p in ipairs(ShopConfig.Products) do
		assert(p.ProductId == 0 and p.Name and p.Description and p.Grants, p.Key)
		seen[p.Key] = p.Robux
	end
	for _, p in ipairs(ShopConfig.Passes) do
		assert(p.PassId == 0 and p.Name and p.Description, p.Key)
		seen[p.Key] = p.Robux
	end
	for key, price in pairs(want) do
		assert(seen[key] == price, key .. " price " .. tostring(seen[key]))
	end
end)

test("rewards, codes, session goals, grapple and flare are sane", function()
	for code, def in pairs(GameConfig.Codes) do
		assert((def.Coins or 0) + (def.LifeJacket or 0) > 0, code)
	end
	assert(#GameConfig.SessionGoals == 3)
	for _, g in ipairs(GameConfig.SessionGoals) do
		assert(g.Target > 0 and g.Coins > 0 and g.Stat and g.Text)
	end
	assert(GameConfig.Grapple.Range == 40 and GameConfig.Grapple.Cooldown == 12 and GameConfig.Flare.ArrowTime == 15)
	assert(GameConfig.Obstacles.SoloHold == 4 and GameConfig.Sinking.ValveDelay == 6 and GameConfig.Sinking.BraceTime == 2)
	assert(#GameConfig.DailyRewards == 7)
end)

-- Every slot the code plays (grep: Audio.play("X") / loop) must exist.
local USED = {
	"Brace", "Horn", "Lurch", "ShipCreak", "ShipHum", "Waves", "Seagulls", "Pickup", "PickupRare", "Legendary", "Drop",
	"Splash", "Gasp", "LowOxygen", "Downed", "Revive", "Grapple", "Flare", "Lever", "Bulkhead", "Valve", "SteamHiss",
	"SteamBurst", "Spark", "ChandelierFall", "PropSlide", "Winch", "Oars", "LobbyMusic", "RoundMusic", "FinalMinute",
	"Countdown", "UIClick", "Coins", "Escape", "LostAtSea",
}

test("audio: only IDs DEAD AIR / THIN ICE already use; empty slots are \"\"; volumes sane; every used slot exists", function()
	local known = fs.readFile("../dead-air/src/shared/Config/AudioAssets.lua") .. fs.readFile("../thin-ice/src/shared/Config/AudioAssets.lua")
	local GROUPS = { Effects = true, Ambient = true, Music = true, UI = true }
	local filled, empty = 0, 0
	local function checkId(slot, id)
		assert(type(id) == "string", slot .. " id not a string")
		if id == "" then
			empty += 1
			return
		end
		local n = string.match(id, "^rbxassetid://(%d+)$")
		assert(n, slot .. " malformed: " .. id)
		assert(string.find(known, '"rbxassetid://' .. n .. '"', 1, true), slot .. " uses an ID not found in DEAD AIR / THIN ICE: " .. n)
		filled += 1
	end
	for slot, def in pairs(AudioAssets) do
		assert(def.Group == nil or GROUPS[def.Group], slot .. " unknown group")
		assert((def.Volume or 0.5) > 0 and (def.Volume or 0.5) <= 1, slot .. " volume")
		if def.Layers then
			for _, layer in ipairs(def.Layers) do
				checkId(slot, layer.Id)
				assert((def.Volume or 0.5) * (layer.Volume or 1) <= 1, slot .. " layer too loud")
			end
		else
			checkId(slot, def.Id)
		end
		if def.Looped then
			assert((def.Volume or 0.5) <= 0.6, slot .. " loop too loud")
		end
	end
	for _, slot in ipairs(USED) do
		assert(AudioAssets[slot], "missing slot " .. slot)
	end
	for slot in pairs(AudioAssets) do
		assert(table.find(USED, slot), "slot " .. slot .. " is never played")
	end
	assert(filled >= 25 and empty >= 3, string.format("%d filled, %d empty", filled, empty))
end)

return cases
