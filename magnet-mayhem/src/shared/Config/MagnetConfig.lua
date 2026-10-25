--[[
	MagnetConfig - magnet tiers (bought once each, in order) and the base numbers the
	upgrade levels in EconomyConfig build on. Economy.stats() turns tier + levels + prestige
	into the final MagnetStrength, AttractionRange, ... values.

	Each tier also changes how the magnet looks (MagnetModel reads Visual) and sounds.
]]

local MagnetConfig = {}

MagnetConfig.Tiers = {
	{
		Name = "Scrap Coil",
		Price = 0,
		Strength = 1,
		RangeBonus = 0,
		CapacityMult = 1,
		Visual = { Body = { 120, 116, 108 }, Prong = { 178, 64, 52 }, Tip = { 200, 200, 196 }, Core = { 255, 170, 60 }, Coils = 1, CoreSize = 0.5, Material = "Metal", Glow = 1 },
	},
	{
		Name = "Copper Coil",
		Price = 400,
		Strength = 3,
		RangeBonus = 2,
		CapacityMult = 1.3,
		Visual = { Body = { 96, 92, 88 }, Prong = { 196, 70, 52 }, Tip = { 220, 220, 214 }, Core = { 255, 150, 60 }, Coils = 2, CoreSize = 0.6, Material = "Metal", Glow = 1.3, Copper = true },
	},
	{
		Name = "Steel Dynamo",
		Price = 4000,
		Strength = 6,
		RangeBonus = 4,
		CapacityMult = 1.7,
		Visual = { Body = { 70, 74, 82 }, Prong = { 210, 60, 50 }, Tip = { 235, 235, 240 }, Core = { 120, 200, 255 }, Coils = 3, CoreSize = 0.7, Material = "DiamondPlate", Glow = 1.6, Copper = true },
	},
	{
		Name = "Neodymium Pro",
		Price = 40000,
		Strength = 10,
		RangeBonus = 7,
		CapacityMult = 2.2,
		Visual = { Body = { 44, 48, 58 }, Prong = { 220, 40, 60 }, Tip = { 245, 245, 255 }, Core = { 90, 160, 255 }, Coils = 4, CoreSize = 0.8, Material = "Metal", Glow = 2, Copper = true, Fins = true },
	},
	{
		Name = "Quantum Core",
		Price = 350000,
		Strength = 15,
		RangeBonus = 10,
		CapacityMult = 3,
		Visual = { Body = { 34, 34, 46 }, Prong = { 130, 70, 255 }, Tip = { 230, 230, 255 }, Core = { 170, 110, 255 }, Coils = 5, CoreSize = 0.95, Material = "Metal", Glow = 2.4, Copper = false, Fins = true, Ring = true },
	},
	{
		Name = "Singularity",
		Price = 2500000,
		Strength = 22,
		RangeBonus = 14,
		CapacityMult = 4,
		Visual = { Body = { 20, 20, 26 }, Prong = { 255, 180, 40 }, Tip = { 255, 250, 230 }, Core = { 255, 230, 140 }, Coils = 6, CoreSize = 1.1, Material = "Metal", Glow = 2.8, Copper = false, Fins = true, Ring = true, Halo = true },
	},
}

-- Base values before any upgrade level (see Economy.stats).
MagnetConfig.Base = {
	Range = 16,
	Capacity = 30,
	PulseRadius = 26,
	PulseCooldown = 12,
	Concurrent = 3, -- objects in flight at once
	ClaimsPerSecond = 6,
	WalkSpeed = 16,
	SprintMultiplier = 1.25,
	FlightSpeed = 34, -- studs per second for a light object at speed multiplier 1
}

-- Magnet skins only change colours. Owned via achievements, Game Passes or products.
MagnetConfig.Skins = {
	Default = { Name = "Factory Finish" },
	Hazard = { Name = "Hazard Stripes", Prong = { 245, 200, 40 }, Tip = { 30, 30, 30 }, Body = { 50, 50, 50 }, Source = "Achievement", Achievement = "FirstPrestige" },
	Chrome = { Name = "Chrome", Prong = { 220, 224, 232 }, Tip = { 255, 255, 255 }, Body = { 150, 156, 166 }, Source = "Pass" },
	GoldRush = { Name = "Gold Rush", Prong = { 255, 196, 60 }, Tip = { 255, 240, 190 }, Body = { 120, 90, 30 }, Core = { 255, 220, 120 }, Source = "Pass" },
	NeonPulse = { Name = "Neon Pulse", Prong = { 40, 255, 200 }, Tip = { 220, 255, 250 }, Body = { 20, 30, 40 }, Core = { 60, 255, 220 }, Source = "Product" },
}
MagnetConfig.SkinOrder = { "Default", "Hazard", "Chrome", "GoldRush", "NeonPulse" }

MagnetConfig.Trails = {
	None = { Name = "No Trail" },
	Spark = { Name = "Spark Trail", Color = { 255, 200, 90 }, Source = "Pass" },
	Plasma = { Name = "Plasma Trail", Color = { 120, 160, 255 }, Source = "Product" },
	Rust = { Name = "Rust Dust", Color = { 190, 110, 60 }, Source = "Achievement", Achievement = "Collect1000" },
}
MagnetConfig.TrailOrder = { "None", "Rust", "Spark", "Plasma" }

return MagnetConfig
