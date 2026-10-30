--[[
	ShopConfig - the optional Robux items.

	IDs of 0 mean "not created yet": in Studio the Buy button grants the item for free (for
	testing); in a live game it says "not available yet". Create each item in Creator Hub
	(Monetization > Developer Products / Passes) and paste its ID here. Robux prices here are
	display-only: the real price is whatever you set in Creator Hub.

	Pay-to-win is bounded: a Life Jacket auto-revives you at most once per round, a flare
	only helps teammates near you, the grapple has a 12 s cooldown and a 40-stud range, and
	VIP's extra loot slot is one slot (free players reach 6 slots with coin upgrades).
]]

local ShopConfig = {}

ShopConfig.Products = {
	{ Key = "LifeJacket", Name = "Life Jacket", Robux = 25, ProductId = 0, Grants = { LifeJacket = 1 }, Description = "Auto-revives you once when you go down (max one per round). Stackable." },
	{ Key = "Flare", Name = "Rescue Flare", Robux = 49, ProductId = 0, Grants = { Flare = 1 }, Description = "Revives every downed teammate near you and shows a route arrow to the lifeboat for 15 s." },
	{ Key = "Coins500", Name = "Pouch of Coins", Robux = 49, ProductId = 0, Grants = { Coins = 500 }, Description = "+500 coins for upgrades." },
	{ Key = "Coins1500", Name = "Chest of Coins", Robux = 129, ProductId = 0, Grants = { Coins = 1500 }, Description = "+1,500 coins for upgrades." },
	{ Key = "Coins4500", Name = "Captain's Hoard", Robux = 349, ProductId = 0, Grants = { Coins = 4500 }, Description = "+4,500 coins for upgrades." },
}

ShopConfig.Passes = {
	{ Key = "DoubleLoot", Name = "x2 Loot", Robux = 199, PassId = 0, Description = "Everything you bank pays double coins." },
	{ Key = "Grapple", Name = "Grapple Hook", Robux = 249, PassId = 0, Description = "Press Q / L1 to grapple to a surface within 40 studs (12 s cooldown)." },
	{ Key = "Captain", Name = "Captain's Outfit", Robux = 149, PassId = 0, Description = "A captain's cap and navy coat with brass buttons. Cosmetic." },
	{ Key = "VIP", Name = "VIP", Robux = 299, PassId = 0, Description = "+1 loot slot, a [VIP] chat tag and a gold name." },
}

return ShopConfig
