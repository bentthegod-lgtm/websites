--[[
	ShopConfig - OPTIONAL Robux items. Cosmetic only: no stats, no progression, no coins.
	IDs of 0 mean "not created yet": Studio grants the item for free (testing), a live game
	says "not available yet". Prices are display only (the real price is set in Creator Hub).
]]

return {
	Passes = {
		{ Key = "RainbowTrail", Name = "Rainbow Trail", Robux = 99, PassId = 0, Kind = "Trail", Item = "Rainbow", Description = "Your dummy leaves a rainbow behind it." },
	},
	Products = {
		{ Key = "NeonDummy", Name = "Neon Dummy", Robux = 149, ProductId = 0, Kind = "Skin", Item = "Neon", Description = "A glowing neon dummy design. Yours forever once bought." },
		{ Key = "Fireworks", Name = "Fireworks Launch", Robux = 99, ProductId = 0, Kind = "LaunchFx", Item = "Fireworks", Description = "Every launch goes off with fireworks. Yours forever once bought." },
	},
}
