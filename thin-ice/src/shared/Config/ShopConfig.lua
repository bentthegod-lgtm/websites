--[[
	ShopConfig - optional Robux items. Everything is cosmetic except the Thermos Flask,
	a one-run boost that lets you thaw yourself once (a friend can do it for free).

	IDs of 0 mean "not created yet": in Studio the Buy button grants the item for free
	(for testing); in a live game it says "not available yet". Create each item in
	Creator Hub (Monetization) and paste its ID here. Robux prices here are display-only.
]]

local ShopConfig = {}

ShopConfig.Products = {
	{ Key = "Flask1", Name = "Thermos Flask", Robux = 25, ProductId = 0, Grants = { Flask = 1 }, Description = "Thaw yourself once, 8 s after freezing. Used up on your next run where you freeze." },
	{ Key = "Flask5", Name = "Thermos Flask x5", Robux = 99, ProductId = 0, Grants = { Flask = 5 }, Description = "Five flasks." },
	{ Key = "Polar", Name = "Polar Explorer Outfit", Robux = 79, ProductId = 0, Grants = { Outfit = "Polar" }, Description = "A bright white parka with a blue scarf." },
	{ Key = "Aurora", Name = "Aurora Lantern", Robux = 49, ProductId = 0, Grants = { Lantern = "Aurora" }, Description = "Your lantern glows aurora green." },
}

ShopConfig.Passes = {
	{ Key = "VIP", Name = "VIP", Robux = 149, PassId = 0, Grants = { Outfit = "Golden" }, Description = "VIP tag, the Golden Parka and +10% coins from runs." },
}

return ShopConfig
