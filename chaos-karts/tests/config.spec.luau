local Loader = require("./loader")
local fs = require("@lune/fs")
local GameConfig = Loader.shared("Config/GameConfig")
local KartStats = Loader.shared("Config/KartStats")
local AudioAssets = Loader.shared("Config/AudioAssets")
local ShopConfig = Loader.shared("Config/ShopConfig")
local PowerUps = Loader.shared("Config/PowerUps")
local ItemOdds = Loader.shared("ItemOdds")
local Registry = Loader.shared("Events/Registry")
local Rng = Loader.shared("Rng")

-- Every audio id this repo already uses (DEAD AIR + LAST LIFEBOAT): nothing invented.
local function knownIds()
	local ids = {}
	for _, path in ipairs({ "../dead-air/src/shared/Config/AudioAssets.lua", "../last-lifeboat/src/shared/Config/AudioAssets.lua" }) do
		local ok, text = pcall(fs.readFile, path)
		assert(ok, "can't read " .. path)
		for id in string.gmatch(text, "rbxassetid://(%d+)") do
			ids[id] = true
		end
	end
	return ids
end

local function checkSlot(name, def, ids)
	local list = {}
	if def.Id and def.Id ~= "" then
		table.insert(list, def.Id)
	end
	for _, layer in ipairs(def.Layers or {}) do
		table.insert(list, layer.Id)
	end
	for _, id in ipairs(list) do
		local n = string.match(id, "^rbxassetid://(%d+)$")
		assert(n, name .. " has a malformed id " .. id)
		assert(ids[n], name .. " uses an id not found in dead-air / last-lifeboat: " .. id)
	end
end

return {
	{
		name = "Config: content targets unchanged (25 vehicles, 12 power-ups, 35 events 25/5/5, 4 maps)",
		fn = function()
			local t = GameConfig.ContentTargets
			assert(t.Vehicles == 25 and t.PowerUps == 12 and t.Events == 35 and t.Maps == 4)
			assert(#PowerUps.ORDER == 12, "power-ups " .. #PowerUps.ORDER)
			for _, id in ipairs(PowerUps.ORDER) do
				assert(PowerUps.Items[id] and PowerUps.Items[id].implemented == false, id)
			end
			assert(#GameConfig.Roadmap == 7)
		end,
	},
	{
		name = "Config: race / bots / anti-cheat / events numbers are sane",
		fn = function()
			local R = GameConfig.Race
			assert(R.Laps == 3 and R.MaxRacers == 12 and R.DnfTimer == 30 and R.CountdownTime == 3)
			assert(GameConfig.Bots.Enabled == true and GameConfig.Bots.FillTo >= 6 and GameConfig.Bots.FillTo <= R.MaxRacers)
			assert(#GameConfig.Bots.Names >= 12 and #GameConfig.Bots.Colors >= 12)
			assert(GameConfig.Net.SendRate >= 15 and GameConfig.Net.SendRate <= 30 and GameConfig.Net.InterpDelay >= 0.05)
			assert(KartStats.MaxLegalSpeed > KartStats.TopSpeed * KartStats.BoostTopMul, "legal speed below boost speed")
			local E = GameConfig.Events
			assert(E.MaxMajor == 1 and E.MaxMinor == 1, "budget")
			assert(E.FinalLapIntervalMul < 1 and E.FinalLapCooldownMul < 1 and E.FinalLapIntensity3Mul > 1)
			assert(E.GraceSeconds >= 10)
			local rewards = GameConfig.Rewards.Places
			for i = 2, #rewards do
				assert(rewards[i] <= rewards[i - 1], "rewards not descending")
			end
			assert(#rewards >= R.MaxRacers)
			assert(GameConfig.Codes.RELEASE and GameConfig.Codes.CHAOS, "launch codes")
		end,
	},
	{
		name = "Config: audio ids are only ones already used in this repo; empty slots are empty strings",
		fn = function()
			local ids = knownIds()
			for name, def in pairs(AudioAssets) do
				assert(type(def.Id) == "string" or def.Layers, name .. " has no Id field")
				checkSlot(name, def, ids)
			end
			for _, id in ipairs(Registry.ORDER) do
				for slot, def in pairs(Registry.module(id).Sounds) do
					checkSlot(id .. "." .. slot, def, ids)
				end
			end
			assert(AudioAssets.Engine.Id == "", "engine slot should be empty until you add one")
		end,
	},
	{
		name = "Config: shop is placeholder-only with IDs of 0 and cosmetic / coin items only",
		fn = function()
			for _, p in ipairs(ShopConfig.Products) do
				assert(p.ProductId == 0, p.Key .. " has a real-looking id")
				for kind in pairs(p.Grants) do
					assert(kind == "Coins", p.Key .. " grants " .. kind)
				end
			end
			for _, p in ipairs(ShopConfig.Passes) do
				assert(p.PassId == 0 and p.Cosmetic, p.Key .. " is not a cosmetic placeholder")
			end
		end,
	},
	{
		name = "Config: position-weighted item odds (back gets stronger items, nothing guaranteed)",
		fn = function()
			local front = ItemOdds.tierWeights(1, 12)
			local back = ItemOdds.tierWeights(12, 12)
			assert(back[3] > front[3] and front[1] > back[1])
			for _, place in ipairs({ 1, 6, 12 }) do
				local w = ItemOdds.weights(place, 12)
				local total = 0
				for _, id in ipairs(PowerUps.ORDER) do
					assert(w[id] > 0, id .. " impossible at place " .. place)
					total += w[id]
				end
				for _, id in ipairs(PowerUps.ORDER) do
					assert(w[id] / total < 0.5, id .. " near-guaranteed at place " .. place)
				end
			end
			local rng = Rng.new(5)
			local seen = {}
			for _ = 1, 2000 do
				seen[ItemOdds.roll(12, 12, rng)] = true
			end
			for _, id in ipairs(PowerUps.ORDER) do
				assert(seen[id], id .. " never rolled")
			end
		end,
	},
}
