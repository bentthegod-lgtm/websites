--[[
	Robux shop.

	SETUP: in Creator Hub (create.roblox.com -> your experience -> Monetization) create a
	Developer Product for every entry in Products and a Game Pass for every entry in Passes,
	then paste the numeric IDs below. Robux values here are DISPLAY ONLY - the real price is
	whatever you set in Creator Hub, so keep them in sync.

	While an ID is 0: in Studio the Buy button grants the item for free (testing); in a live
	game it says "not available yet".

	Fairness: nothing here changes parry timing, ball speed, ability power or cooldowns.
	Robux buys coins (which buy cosmetics/abilities that free players earn by playing),
	cosmetic spins, a social party effect, and convenience (one extra ability slot).
]]

return {
	Products = {
		{ Key = "Coins500", Name = "Pouch of Coins", Description = "+500 coins", Robux = 49, ProductId = 0, Grants = { Coins = 500 } },
		{ Key = "Coins1500", Name = "Sack of Coins", Description = "+1,500 coins (+20% bonus)", Robux = 129, ProductId = 0, Grants = { Coins = 1500 } },
		{ Key = "Coins5000", Name = "Vault of Coins", Description = "+5,000 coins (best value)", Robux = 399, ProductId = 0, Grants = { Coins = 5000 } },
		{ Key = "Spin1", Name = "Premium Spin", Description = "1 Premium Spin (no Commons, see odds)", Robux = 39, ProductId = 0, Grants = { PremiumSpins = 1 } },
		{ Key = "Spin5", Name = "5 Premium Spins", Description = "5 Premium Spins (see odds)", Robux = 179, ProductId = 0, Grants = { PremiumSpins = 5 } },
		{
			Key = "ExplosionParty",
			Name = "Server Explosion Party",
			Description = "Every explosion on the server becomes confetti for 10 minutes. Everyone sees your name!",
			Robux = 99,
			ProductId = 0,
			Grants = { ExplosionParty = 600 },
		},
	},

	Passes = {
		{ Key = "VIP", Name = "VIP", Description = "Gold VIP tag above your head and in chat, 1.5x coins.", Robux = 299, PassId = 0 },
		{ Key = "DoubleCoins", Name = "2x Coins", Description = "Double coins from every match.", Robux = 199, PassId = 0 },
		{ Key = "PrismTrail", Name = "Prism Pulse Trail", Description = "Exclusive animated rainbow ball trail. Cosmetic only.", Robux = 149, PassId = 0 },
		{ Key = "ExtraSlot", Name = "Extra Ability Slot", Description = "Equip 2 abilities (each keeps its own cooldown). Change loadout in the lobby only.", Robux = 249, PassId = 0 },
	},

	-- Coin multipliers from passes ADD together and are capped, so stacking stays bounded.
	VipCoinBonus = 0.5,
	DoubleCoinBonus = 1.0,
	MaxCoinMultiplier = 2.5,

	-- An Explosion Party bought while one is running extends it, up to this many seconds.
	ExplosionPartyMax = 1800,
}
