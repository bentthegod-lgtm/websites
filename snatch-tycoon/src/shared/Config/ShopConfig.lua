--[[
	Robux shop.

	SETUP: in Creator Hub (create.roblox.com -> your experience -> Monetization) create a
	Developer Product for every entry in Products and a Game Pass for every entry in Passes,
	then paste the numeric IDs into ProductId / PassId. The Robux prices here are DISPLAY
	ONLY: the real price is the one you set in Creator Hub, so keep them in sync.

	While an ID is 0 the Buy button grants the item for free in Studio (for testing) and
	says "not available yet" in a live game.

	Pay-to-win is bounded:
	  * 2x Cash and cash packs only speed things up; free players reach every Blobby.
	  * Speedy Snatcher keeps carry speed below normal walking speed.
	  * Lock Base Now can't chain: the base always opens for a few seconds between locks.
	  * Server Luck helps EVERYONE in the server, not just the buyer.
]]

return {
	Products = {
		{
			Key = "CashSmall", Kind = "Cash", Name = "Pocket of Cash", Robux = 19, ProductId = 0,
			Pack = { Minutes = 10, Minimum = 2500 }, Color = { 120, 230, 120 },
			Description = "10 minutes of your income (at least $2.5K).",
		},
		{
			Key = "CashMedium", Kind = "Cash", Name = "Bag of Cash", Robux = 79, ProductId = 0,
			Pack = { Minutes = 45, Minimum = 15000 }, Color = { 90, 210, 120 },
			Description = "45 minutes of your income (at least $15K).",
		},
		{
			Key = "CashLarge", Kind = "Cash", Name = "Vault of Cash", Robux = 299, ProductId = 0,
			Pack = { Minutes = 180, Minimum = 80000 }, Color = { 60, 190, 110 },
			Description = "3 hours of your income (at least $80K). Best value!",
		},
		{
			Key = "ServerLuck", Kind = "ServerLuck", Name = "Server Luck x2 (15 min)", Robux = 99, ProductId = 0,
			Color = { 90, 200, 255 },
			Description = "Doubles rare spawn odds for EVERYONE in the server for 15 minutes. Stacks time!",
		},
		{
			Key = "MythicCrate", Kind = "Crate", Name = "Mythic Crate", Robux = 249, ProductId = 0,
			Color = { 255, 64, 112 },
			Description = "A guaranteed Mythic or Secret Blobby, delivered to your base.",
			Odds = {
				{ Rarity = "Mythic", Chance = 0.92 },
				{ Rarity = "Secret", Chance = 0.08 },
			},
		},
		{
			Key = "LockNow", Kind = "LockNow", Name = "Lock Base Now", Robux = 25, ProductId = 0,
			Color = { 255, 90, 90 },
			Description = "Skip the cooldown and lock your laser door for 45 seconds right now.",
		},
	},

	Passes = {
		{ Key = "DoubleCash", Name = "2x Cash", Robux = 199, PassId = 0, Color = { 120, 230, 120 }, Description = "All your Blobbies earn double cash. Forever." },
		{ Key = "VIP", Name = "VIP", Robux = 299, PassId = 0, Color = { 255, 210, 60 }, Description = "[VIP] chat tag, gold nameplate and +1 pedestal slot." },
		{ Key = "AutoCollect", Name = "Auto-Collect", Robux = 149, PassId = 0, Color = { 90, 200, 255 }, Description = "Cash goes straight into your wallet. No pad stepping." },
		{ Key = "FastCarry", Name = "Speedy Snatcher", Robux = 129, PassId = 0, Color = { 255, 150, 60 }, Description = "Run faster while carrying a stolen Blobby (75% speed instead of 55%)." },
		{ Key = "ExtraSlots", Name = "+3 Pedestals", Robux = 249, PassId = 0, Color = { 186, 96, 255 }, Description = "Three more pedestals in your base." },
	},
}
