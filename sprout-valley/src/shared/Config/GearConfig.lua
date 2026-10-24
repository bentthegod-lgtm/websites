--[[
	Gear Shop (always in stock, paid with Coins).

	WateringCan   each use instantly grows the plant by Advance x GrowTime (capped at
	              MaxAdvance seconds) and can make it Wet. Per-tile cooldown.
	Sprinklers    placed on a tile; every plant within Radius tiles grows Growth x faster
	              for Duration seconds (real time).
	LuckyFertilizer  doubles that plant's weather mutation chance until it is harvested
	              (still capped by MutationConfig.ChanceCap).
	Trowel        permanent tool: pick a plant up and move it to an empty tile.
]]

return {
	Order = { "WateringCan", "Sprinkler", "ProSprinkler", "LuckyFertilizer", "Trowel" },
	Gear = {
		WateringCan = {
			Name = "Watering Can",
			Price = 150,
			Uses = 10,
			Advance = 0.08,
			MaxAdvance = 180,
			Cooldown = 15,
			WetChance = 0.1,
			Color = { 90, 170, 255 },
			Description = "10 uses. Instantly grows a plant a little and may make it Wet.",
		},
		Sprinkler = {
			Name = "Sprinkler",
			Price = 2000,
			Uses = 1,
			Radius = 1,
			Growth = 1.5,
			Duration = 300,
			Color = { 120, 200, 255 },
			Description = "Place on a tile: plants in a 3x3 area grow 1.5x faster for 5 minutes.",
		},
		ProSprinkler = {
			Name = "Pro Sprinkler",
			Price = 12000,
			Uses = 1,
			Radius = 2,
			Growth = 1.8,
			Duration = 600,
			Color = { 255, 200, 80 },
			Description = "Place on a tile: plants in a 5x5 area grow 1.8x faster for 10 minutes.",
		},
		LuckyFertilizer = {
			Name = "Lucky Fertilizer",
			Price = 5000,
			Uses = 1,
			Color = { 120, 230, 120 },
			Description = "Use on a plant: 2x weather mutation chance until it is harvested.",
		},
		Trowel = {
			Name = "Trowel",
			Price = 500,
			Uses = 1,
			Permanent = true,
			Color = { 200, 160, 110 },
			Description = "Permanent. Dig up a plant and replant it on an empty tile.",
		},
	},
	MaxSprinklers = 4,
}
