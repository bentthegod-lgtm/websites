--[[
	ShopConfig - the optional Robux items. STAGE 1: placeholders only (the cosmetic shop
	arrives in Stage 7). Everything here is COSMETIC or a coin pack: NOTHING in the shop can
	change kart physics (KartStats is identical for every kart; a unit test checks no shop
	entry carries a physics key). No pay-to-win.

	IDs of 0 mean "not created yet": in Studio the Buy button grants the item for free (for
	testing); in a live game it says "not available yet". Create each item in Creator Hub
	(Monetization > Developer Products / Passes) and paste its ID here. Robux prices are
	display-only: the real price is whatever you set in Creator Hub.
]]

local ShopConfig = {}

ShopConfig.Products = {
	{ Key = "Coins500", Name = "Coin Pouch", Robux = 49, ProductId = 0, Grants = { Coins = 500 }, Description = "+500 coins for cosmetics (Stage 7 shop)." },
	{ Key = "Coins1500", Name = "Coin Crate", Robux = 129, ProductId = 0, Grants = { Coins = 1500 }, Description = "+1,500 coins for cosmetics." },
}

ShopConfig.Passes = {
	{ Key = "NeonTrails", Name = "Neon Trails", Robux = 149, PassId = 0, Cosmetic = "Trail", Description = "A glowing neon trail behind your kart. Cosmetic only." },
	{ Key = "VIP", Name = "VIP", Robux = 249, PassId = 0, Cosmetic = "Tag", Description = "A gold [VIP] name tag and chat tag. Cosmetic only." },
}

return ShopConfig
