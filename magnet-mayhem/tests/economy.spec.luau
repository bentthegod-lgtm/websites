local L = require("./loader")
local Economy = L.shared("Economy")
local EconomyConfig = L.shared("Config/EconomyConfig")
local MagnetConfig = L.shared("Config/MagnetConfig")
local ScrapConfig = L.shared("Config/ScrapConfig")
local ZoneConfig = L.shared("Config/ZoneConfig")
local Format = L.shared("Format")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Economy: " .. name, fn = fn })
end

test("upgrade prices rise every level and stop at max", function()
	for _, def in ipairs(EconomyConfig.Upgrades) do
		local last = 0
		for level = 0, def.Max - 1 do
			local price = Economy.upgradePrice(def.Key, level)
			assert(price and price > last, def.Key .. " level " .. level .. " price " .. tostring(price))
			last = price
		end
		assert(Economy.upgradePrice(def.Key, def.Max) == nil, def.Key .. " should be maxed")
	end
	assert(Economy.upgradePrice("Bogus", 0) == nil)
end)

test("every upgrade level changes at least one stat (no dead upgrades)", function()
	local fields = { "MagnetStrength", "AttractionRange", "AttractionSpeed", "MaximumScrapCapacity", "HeavyObjectCapability", "ScrapValueMultiplier", "PulseRadius", "PulseCooldown", "CollectionEfficiency", "WalkSpeed", "SprintMultiplier", "LuckyChance" }
	for _, def in ipairs(EconomyConfig.Upgrades) do
		for level = 0, def.Max - 1 do
			local a = Economy.stats({ [def.Key] = level }, 1, 0)
			local b = Economy.stats({ [def.Key] = level + 1 }, 1, 0)
			local changed = false
			for _, f in ipairs(fields) do
				if a[f] ~= b[f] then
					changed = true
				end
			end
			assert(changed, def.Key .. " level " .. level .. " -> " .. (level + 1) .. " changes nothing")
		end
	end
end)

test("stats are clamped: impossible levels and tiers can't exceed the maximum", function()
	local maxed = {}
	for _, def in ipairs(EconomyConfig.Upgrades) do
		maxed[def.Key] = def.Max
	end
	local legit = Economy.stats(maxed, #MagnetConfig.Tiers, 0)
	local hacked = Economy.stats({ Strength = 9999, Range = -5, Capacity = 1e9 }, 99, 0)
	assert(hacked.MagnetStrength <= legit.MagnetStrength and hacked.AttractionRange >= MagnetConfig.Base.Range)
	assert(hacked.MaximumScrapCapacity <= legit.MaximumScrapCapacity)
	assert(Economy.stats({ Range = -5 }, -3, -2).AttractionRange == MagnetConfig.Base.Range)
end)

test("first sale pays for a first upgrade (no early grind)", function()
	local stats = Economy.stats({}, 1, 0)
	-- Fill the starting capacity with the spawn-area commons (rank 1) at their average value per mass.
	local value, mass = 0, 0
	for _, def in ipairs(ScrapConfig.List) do
		if def.Zone == "Rustyard" and def.Rarity == "Common" and def.MinStrength <= stats.MagnetStrength then
			value += def.Value * def.Weight
			mass += def.Mass * def.Weight
		end
	end
	local firstSale = Economy.saleValue(stats.MaximumScrapCapacity * value / mass, stats.ScrapValueMultiplier)
	local cheapest = math.huge
	for _, def in ipairs(EconomyConfig.Upgrades) do
		cheapest = math.min(cheapest, Economy.upgradePrice(def.Key, 0))
	end
	assert(firstSale >= cheapest, string.format("first sale %d < cheapest upgrade %d", firstSale, cheapest))
	assert(firstSale < cheapest * 6, "first sale buys too much at once")
end)

test("magnet tiers get stronger and pricier; tier 3 opens Metro Wreck", function()
	for i = 2, #MagnetConfig.Tiers do
		assert(MagnetConfig.Tiers[i].Strength > MagnetConfig.Tiers[i - 1].Strength)
		assert(MagnetConfig.Tiers[i].Price > MagnetConfig.Tiers[i - 1].Price)
	end
	local metro = ZoneConfig.ById.MetroWreck
	assert(Economy.stats({}, 3, 0).MagnetStrength >= metro.Unlock.Strength)
	assert(Economy.stats({ Strength = 12 }, 1, 0).MagnetStrength < metro.Unlock.Strength, "Metro should need a tier upgrade")
end)

test("every scrap object can be pulled by some reachable magnet", function()
	local maxed = {}
	for _, def in ipairs(EconomyConfig.Upgrades) do
		maxed[def.Key] = def.Max
	end
	local best = Economy.stats(maxed, #MagnetConfig.Tiers, 0)
	for _, def in ipairs(ScrapConfig.List) do
		assert(def.MinStrength <= best.MagnetStrength, def.Id .. " can never be pulled")
		assert(def.Mass <= Economy.stats({}, 1, 0).MaximumScrapCapacity * 2.5 or def.Rarity ~= "Common", def.Id .. " too big for its tier")
	end
end)

test("sale value and lucky / storm item values round sensibly", function()
	assert(Economy.saleValue(100, 1.25) == 125)
	assert(Economy.saleValue(0, 5) == 0 and Economy.saleValue(-50, 2) == 0)
	local can = ScrapConfig.ById.SodaCan
	assert(Economy.itemValue(can, false) == 2)
	assert(Economy.itemValue(can, true) == 3)
	assert(Economy.itemValue(can, false, 1.25) == 3)
end)

test("prestige: no cores below the threshold, more cores for bigger runs", function()
	local min = EconomyConfig.Prestige.MinRunEarned
	assert(Economy.prestigeCores(min - 1) == 0)
	assert(Economy.prestigeCores(min) == EconomyConfig.Prestige.CoresBase)
	assert(Economy.prestigeCores(min * 4) == EconomyConfig.Prestige.CoresBase * 2)
	local a, b = Economy.stats({}, 1, 0), Economy.stats({}, 1, 5)
	assert(b.ScrapValueMultiplier > a.ScrapValueMultiplier and b.AttractionSpeed > a.AttractionSpeed)
end)

test("format: abbreviations and exact values", function()
	assert(Format.short(999) == "999")
	assert(Format.short(1234) == "1.23K", Format.short(1234))
	assert(Format.short(12345) == "12.3K", Format.short(12345))
	assert(Format.short(3456789) == "3.45M", Format.short(3456789))
	assert(Format.short(2500000000) == "2.5B")
	assert(Format.exact(1234567) == "1,234,567")
	assert(Format.stat(2.5) == "2.5" and Format.stat(3) == "3")
	assert(Format.clock(75) == "1:15" and Format.clock(3725) == "1:02:05")
end)

return cases
