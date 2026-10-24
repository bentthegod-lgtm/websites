--[[
	Robux shop.

	SETUP: create each Developer Product / Game Pass in Creator Hub
	(create.roblox.com -> your experience -> Monetization) and paste its numeric ID below.
	While an ID is 0:
	  * in Studio the Buy button grants it for free (for testing; passes last for the session),
	  * in a live game the button says "not available yet".
	Robux prices here are DISPLAY ONLY. The real price is whatever you set in Creator Hub, so
	keep the two in sync.

	Pay-to-win is bounded: coin packs are fixed amounts, Lucky Gardener is capped by
	MutationConfig.ChanceCap, weather totems only start common events, and the seed crate
	cannot give anything the free Seed Shop does not also sell.
]]

return {
	-- Developer Products (consumables)
	Products = {
		{ Key = "Coins1", Category = "Coins", Name = "Handful of Coins", Robux = 25, ProductId = 0, Coins = 2500, Color = { 255, 210, 80 } },
		{ Key = "Coins2", Category = "Coins", Name = "Sack of Coins", Robux = 99, ProductId = 0, Coins = 15000, Color = { 255, 190, 60 } },
		{ Key = "Coins3", Category = "Coins", Name = "Barrel of Coins", Robux = 249, ProductId = 0, Coins = 60000, Color = { 255, 170, 40 } },
		{ Key = "Coins4", Category = "Coins", Name = "Wagon of Coins", Robux = 799, ProductId = 0, Coins = 300000, Color = { 255, 150, 30 } },

		{ Key = "InstantRestock", Category = "Boosts", Name = "Restock for Everyone!", Robux = 39, ProductId = 0,
			Description = "Instantly restocks the Seed Shop for the WHOLE server. Everyone hears who did it.", Color = { 120, 220, 120 } },
		{ Key = "GrowthSkip", Category = "Boosts", Name = "Growth Skip", Robux = 19, ProductId = 0,
			Description = "Instantly ripens one plant. Pick it with the Growth Skip tool on your hotbar.", Color = { 170, 120, 255 } },
		{ Key = "RainTotem", Category = "Boosts", Name = "Rain Totem", Robux = 29, ProductId = 0, Weather = "Rain",
			Description = "Starts Rain for the whole server (or right after the current event).", Color = { 110, 170, 255 } },
		{ Key = "StormTotem", Category = "Boosts", Name = "Storm Totem", Robux = 49, ProductId = 0, Weather = "Thunderstorm",
			Description = "Starts a Thunderstorm for the whole server. Lightning = Shocked fruit!", Color = { 255, 235, 90 } },
		{ Key = "GoldenTotem", Category = "Boosts", Name = "Golden Hour Totem", Robux = 79, ProductId = 0, Weather = "GoldenHour",
			Description = "Starts Golden Hour for the whole server. Golden fruit sells for 10x.", Color = { 255, 200, 60 } },

		{ Key = "SeedCrate", Category = "Crates", Name = "Seed Crate", Robux = 49, ProductId = 0, Crate = "SeedCrate",
			Description = "One random seed from Uncommon to Prismatic. Odds below.", Color = { 200, 140, 90 } },
		{ Key = "SeedCrate5", Category = "Crates", Name = "5x Seed Crate", Robux = 199, ProductId = 0, Crate = "SeedCrate", Rolls = 5,
			Description = "Five Seed Crate rolls for the price of four.", Color = { 220, 120, 80 } },
	},

	-- Crate odds: rarity first, then an even pick among that rarity's crops.
	Crates = {
		SeedCrate = {
			Name = "Seed Crate",
			Odds = {
				{ Rarity = "Uncommon", Weight = 40 },
				{ Rarity = "Rare", Weight = 30 },
				{ Rarity = "Epic", Weight = 18 },
				{ Rarity = "Legendary", Weight = 8 },
				{ Rarity = "Mythic", Weight = 3 },
				{ Rarity = "Divine", Weight = 0.8 },
				{ Rarity = "Prismatic", Weight = 0.2 },
			},
		},
	},

	-- Game Passes (permanent)
	Passes = {
		{ Key = "DoubleSell", Name = "2x Sell Value", Robux = 199, PassId = 0, Color = { 255, 200, 60 },
			Description = "Everything you sell is worth double. Forever." },
		{ Key = "VIP", Name = "VIP Gardener", Robux = 149, PassId = 0, Color = { 255, 120, 200 },
			Description = "VIP name tag + chat tag, +1 garden row (6 tiles), +50% daily reward coins." },
		{ Key = "BigBackpack", Name = "Bigger Backpack", Robux = 79, PassId = 0, Color = { 160, 120, 80 },
			Description = "Carry 200 fruit instead of 60." },
		{ Key = "AutoWater", Name = "Auto-Water", Robux = 129, PassId = 0, Color = { 90, 170, 255 },
			Description = "Your garden waters itself: crops grow 25% faster, online AND offline." },
		{ Key = "LuckyGardener", Name = "Lucky Gardener", Robux = 249, PassId = 0, Color = { 120, 230, 120 },
			Description = "1.5x mutation and Golden/Rainbow chance (capped, so it stays fair)." },
	},

	CategoryOrder = { "Coins", "Boosts", "Crates", "Passes" },

	-- Pass effect tuning
	DoubleSellMultiplier = 2,
	AutoWaterGrowth = 1.25,
	VipDailyBonus = 1.5,
}
