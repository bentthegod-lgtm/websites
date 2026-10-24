--[[
	Mutations on fruit.

	* Environmental mutations (Wet, Chilled, Frozen, Shocked, Bloodlit, Aurora) come from
	  weather events and STACK ADDITIVELY: total = 1 + sum(Multiplier - 1).
	* Variants (Golden, Rainbow) are exclusive and MULTIPLY the stacked total.
	  Example: Golden + Wet + Shocked = 10 x (1 + 1 + 5) = 70x.
	* Combos: a fruit that is both Wet and Chilled becomes Frozen (replaces both).

	Color drives the aura particles on the fruit and the UI chip.
]]

return {
	Order = { "Wet", "Chilled", "Frozen", "Shocked", "Bloodlit", "Aurora" },
	Mutations = {
		Wet = { Multiplier = 2, Color = { 90, 170, 255 }, Description = "Soaked by the rain." },
		Chilled = { Multiplier = 2, Color = { 190, 235, 255 }, Description = "Kissed by frost." },
		Frozen = { Multiplier = 8, Color = { 120, 210, 255 }, Description = "Wet + Chilled: frozen solid!" },
		Shocked = { Multiplier = 6, Color = { 255, 240, 90 }, Description = "Struck by lightning." },
		Bloodlit = { Multiplier = 5, Color = { 220, 40, 60 }, Description = "Bathed in the Blood Moon." },
		Aurora = { Multiplier = 9, Color = { 120, 255, 200 }, Description = "Touched by the Aurora." },
	},
	Combos = {
		{ Needs = { "Wet", "Chilled" }, Result = "Frozen" },
	},
	VariantOrder = { "Golden", "Rainbow" },
	Variants = {
		Golden = { Multiplier = 10, Color = { 255, 205, 50 }, NaturalChance = 0.01 },
		Rainbow = { Multiplier = 40, Color = { 255, 120, 220 }, NaturalChance = 0.001 },
	},
	-- Per-tick mutation chances can never exceed this, whatever boosts are stacked.
	ChanceCap = 0.2,
	LuckyFertilizerMultiplier = 2,
	LuckyGardenerMultiplier = 1.5, -- game pass, bounded by ChanceCap
	LuckyGardenerVariantMultiplier = 1.5,
}
