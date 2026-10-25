--[[
	ShopConfig - OPTIONAL Robux items. Cosmetics only: no stats, no progression.
	IDs of 0 mean "not created yet": Studio grants the item for free (testing), a live game
	says "not available yet". Prices are display only (the real price is set in Creator Hub).
]]

return {
	Passes = {
		{ Key = "ChromeSkin", Name = "Chrome Magnet", Robux = 99, PassId = 0, Skin = "Chrome", Description = "A mirror-polished chrome magnet skin." },
		{ Key = "GoldSkin", Name = "Gold Rush Magnet", Robux = 199, PassId = 0, Skin = "GoldRush", Description = "A shining gold magnet with a warm core." },
		{ Key = "SparkTrail", Name = "Spark Trail", Robux = 79, PassId = 0, Trail = "Spark", Description = "Leave a trail of sparks while you run." },
	},
	Products = {
		{ Key = "NeonSkin", Name = "Neon Pulse Magnet", Robux = 149, ProductId = 0, Skin = "NeonPulse", Description = "A glowing teal magnet. Yours forever once bought." },
		{ Key = "PlasmaTrail", Name = "Plasma Trail", Robux = 99, ProductId = 0, Trail = "Plasma", Description = "A cool blue plasma trail. Yours forever once bought." },
	},
}
