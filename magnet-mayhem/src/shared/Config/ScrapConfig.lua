--[[
	ScrapConfig - the scrap catalog. Every collectible metal object is one entry here; the
	procedural model for an entry lives in ScrapModels (keyed by the same Id).

	Fields:
	  Id, Name, Rarity      unique id, display name, rarity tier (see Rarities)
	  Value                 base sell value in coins (before upgrades / prestige)
	  Mass                  capacity units it uses in the pile; also decides its weight class
	  MinStrength           magnet strength needed to pull it
	  Zone                  which zone spawns it
	  Weight                relative spawn weight inside its zone
	  Size                  rough bounding size in studs (used by pile layout and flight)
	  Audio                 audio profile: "Light" | "Medium" | "Heavy" | "Legendary"
	  Bonus                 optional collection bonus { Kind = "Coins", Amount = n }
	  StormOnly             only spawns during a Magnetic Storm
]]

local ScrapConfig = {}

ScrapConfig.Rarities = {
	Common = { Rank = 1, Color = { 200, 200, 196 }, Label = "COMMON" },
	Uncommon = { Rank = 2, Color = { 110, 220, 120 }, Label = "UNCOMMON" },
	Rare = { Rank = 3, Color = { 90, 170, 255 }, Label = "RARE" },
	Epic = { Rank = 4, Color = { 190, 110, 255 }, Label = "EPIC" },
	Legendary = { Rank = 5, Color = { 255, 190, 60 }, Label = "LEGENDARY" },
}

-- Weight classes by mass: controls flight speed, anticipation and sound.
ScrapConfig.WeightClasses = {
	{ Name = "Light", MaxMass = 2 },
	{ Name = "Medium", MaxMass = 12 },
	{ Name = "Heavy", MaxMass = math.huge },
}

ScrapConfig.List = {
	-- Rustyard: common
	{ Id = "SodaCan", Name = "Crushed Soda Can", Rarity = "Common", Value = 2, Mass = 1, MinStrength = 1, Zone = "Rustyard", Weight = 30, Size = 0.9, Audio = "Light" },
	{ Id = "Bolt", Name = "Metal Bolt", Rarity = "Common", Value = 3, Mass = 1, MinStrength = 1, Zone = "Rustyard", Weight = 26, Size = 0.9, Audio = "Light" },
	{ Id = "Washer", Name = "Steel Washer", Rarity = "Common", Value = 3, Mass = 1, MinStrength = 1, Zone = "Rustyard", Weight = 24, Size = 0.8, Audio = "Light" },
	{ Id = "Gear", Name = "Small Gear", Rarity = "Common", Value = 5, Mass = 2, MinStrength = 1, Zone = "Rustyard", Weight = 18, Size = 1.4, Audio = "Light" },
	{ Id = "RustyPipe", Name = "Rusty Pipe", Rarity = "Common", Value = 8, Mass = 3, MinStrength = 1, Zone = "Rustyard", Weight = 14, Size = 3, Audio = "Medium" },
	{ Id = "MetalSign", Name = "Broken Metal Sign", Rarity = "Common", Value = 11, Mass = 4, MinStrength = 2, Zone = "Rustyard", Weight = 10, Size = 2.6, Audio = "Medium" },
	-- Rustyard: uncommon
	{ Id = "Toolbox", Name = "Toolbox", Rarity = "Uncommon", Value = 32, Mass = 6, MinStrength = 3, Zone = "Rustyard", Weight = 6, Size = 2.2, Audio = "Medium" },
	{ Id = "IndustrialFan", Name = "Industrial Fan", Rarity = "Uncommon", Value = 46, Mass = 8, MinStrength = 3, Zone = "Rustyard", Weight = 4.5, Size = 3.2, Audio = "Medium" },
	{ Id = "HeavyChain", Name = "Heavy Chain", Rarity = "Uncommon", Value = 40, Mass = 7, MinStrength = 3, Zone = "Rustyard", Weight = 5, Size = 3, Audio = "Medium" },
	{ Id = "EngineComponent", Name = "Engine Component", Rarity = "Uncommon", Value = 72, Mass = 10, MinStrength = 4, Zone = "Rustyard", Weight = 3.5, Size = 2.6, Audio = "Medium" },
	-- Rustyard: rare
	{ Id = "MotorcycleEngine", Name = "Motorcycle Engine", Rarity = "Rare", Value = 230, Mass = 18, MinStrength = 6, Zone = "Rustyard", Weight = 1.4, Size = 3.4, Audio = "Heavy" },
	{ Id = "IndustrialMotor", Name = "Industrial Motor", Rarity = "Rare", Value = 310, Mass = 22, MinStrength = 8, Zone = "Rustyard", Weight = 1.1, Size = 3.8, Audio = "Heavy" },
	{ Id = "SteelSafe", Name = "Large Steel Safe", Rarity = "Rare", Value = 520, Mass = 32, MinStrength = 10, Zone = "Rustyard", Weight = 0.7, Size = 4.2, Audio = "Heavy", Bonus = { Kind = "Coins", Amount = 150 } },
	{ Id = "PowerCore", Name = "Experimental Power Core", Rarity = "Epic", Value = 680, Mass = 14, MinStrength = 8, Zone = "Rustyard", Weight = 0.45, Size = 2.8, Audio = "Heavy" },
	-- Rustyard: legendary
	{ Id = "MagneticReactor", Name = "Prototype Magnetic Reactor", Rarity = "Legendary", Value = 4800, Mass = 30, MinStrength = 10, Zone = "Rustyard", Weight = 0.06, Size = 5, Audio = "Legendary", Bonus = { Kind = "Coins", Amount = 1000 } },

	-- Metro Wreck
	{ Id = "Hubcap", Name = "Chrome Hubcap", Rarity = "Common", Value = 38, Mass = 3, MinStrength = 6, Zone = "MetroWreck", Weight = 26, Size = 2, Audio = "Light" },
	{ Id = "ParkingMeter", Name = "Parking Meter", Rarity = "Common", Value = 70, Mass = 6, MinStrength = 6, Zone = "MetroWreck", Weight = 18, Size = 3.4, Audio = "Medium" },
	{ Id = "TrafficLight", Name = "Fallen Traffic Light", Rarity = "Common", Value = 110, Mass = 9, MinStrength = 7, Zone = "MetroWreck", Weight = 14, Size = 3.6, Audio = "Medium" },
	{ Id = "ManholeCover", Name = "Manhole Cover", Rarity = "Uncommon", Value = 160, Mass = 11, MinStrength = 8, Zone = "MetroWreck", Weight = 9, Size = 3, Audio = "Medium" },
	{ Id = "StreetLamp", Name = "Bent Street Lamp", Rarity = "Uncommon", Value = 240, Mass = 14, MinStrength = 9, Zone = "MetroWreck", Weight = 6, Size = 5, Audio = "Heavy" },
	{ Id = "CarDoor", Name = "Car Door", Rarity = "Uncommon", Value = 330, Mass = 16, MinStrength = 10, Zone = "MetroWreck", Weight = 5, Size = 4, Audio = "Heavy" },
	{ Id = "WreckedScooter", Name = "Wrecked Scooter", Rarity = "Rare", Value = 640, Mass = 24, MinStrength = 12, Zone = "MetroWreck", Weight = 2, Size = 4.4, Audio = "Heavy" },
	{ Id = "EngineBlock", Name = "Car Engine Block", Rarity = "Rare", Value = 1150, Mass = 34, MinStrength = 14, Zone = "MetroWreck", Weight = 1.2, Size = 4, Audio = "Heavy" },
	{ Id = "ArmoredATM", Name = "Armored ATM", Rarity = "Epic", Value = 2600, Mass = 44, MinStrength = 18, Zone = "MetroWreck", Weight = 0.5, Size = 4.6, Audio = "Heavy", Bonus = { Kind = "Coins", Amount = 600 } },
	{ Id = "GoldenTaxi", Name = "The Golden Taxi", Rarity = "Legendary", Value = 26000, Mass = 60, MinStrength = 18, Zone = "MetroWreck", Weight = 0.05, Size = 8, Audio = "Legendary", Bonus = { Kind = "Coins", Amount = 5000 } },

	-- Magnetic Storm only (both zones)
	{ Id = "StormShard", Name = "Storm Shard", Rarity = "Epic", Value = 150, Mass = 2, MinStrength = 1, Zone = "Any", Weight = 10, Size = 1.6, Audio = "Legendary", StormOnly = true },
}

ScrapConfig.ById = {}
for index, def in ipairs(ScrapConfig.List) do
	def.Order = index
	ScrapConfig.ById[def.Id] = def
end

function ScrapConfig.weightClass(def)
	for _, class in ipairs(ScrapConfig.WeightClasses) do
		if def.Mass <= class.MaxMass then
			return class.Name
		end
	end
	return "Heavy"
end

function ScrapConfig.rank(def)
	return ScrapConfig.Rarities[def.Rarity].Rank
end

return ScrapConfig
