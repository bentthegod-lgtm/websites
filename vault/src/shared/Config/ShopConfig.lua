--[[
	ShopConfig - OPTIONAL Robux items. The base game is fully playable without them.
	  * Cosmetics (stack themes, a trail, a deposit effect): looks only.
	  * VIP pass: a modest convenience - +10% deposit payout and a VIP tag.
	  * Value Boost product: a temporary +25% loot value for 15 minutes (stacks in time up
	    to 60 minutes).
	IDs of 0 mean "not created yet": Studio grants the item for free (testing) and a live
	game says "not available yet". Prices here are display only (set the real price in
	Creator Hub).
]]

return {
	Passes = {
		{ Key = "VIP", Name = "VIP", Robux = 149, PassId = 0, Description = "+10% deposit payout and a gold VIP tag." },
		{ Key = "NeonVault", Name = "Neon Vault Theme", Robux = 99, PassId = 0, Kind = "Theme", Item = "NeonVault", Description = "A glowing neon stack theme." },
		{ Key = "GoldTrail", Name = "Gold Trail", Robux = 79, PassId = 0, Kind = "Trail", Item = "GoldTrail", Description = "A trail of gold dust." },
	},
	Products = {
		{ Key = "GoldenGlow", Name = "Golden Glow Theme", Robux = 129, ProductId = 0, Kind = "Theme", Item = "GoldenGlow", Description = "Your stack glows gold. Yours forever." },
		{ Key = "Confetti", Name = "Confetti Deposits", Robux = 79, ProductId = 0, Kind = "DepositFx", Item = "Confetti", Description = "Confetti on every deposit. Yours forever." },
		{ Key = "ValueBoost", Name = "Value Boost (15 min)", Robux = 49, ProductId = 0, Boost = 900, Description = "+25% loot value for 15 minutes." },
	},
	BoostMax = 3600,
}
