--[[
	Abilities. One is equipped per player (two with the Extra Slot game pass). Bought with
	in-game coins only - never with Robux - and equipping is only allowed in the lobby.

	Balance notes (keep none of them overpowered):
	  * Dash / Super Jump are movement only: they help you get spacing, they never parry.
	  * Freeze only works while the ball is targeting you and has the longest cooldown. It
	    slows the ball for a moment; you still have to parry it yourself.
	  * Shield saves you once per round from a miss, but the ball keeps its speed and is
	    sent to a random player, so it gives no kill credit. It is the most expensive one.
	  * Swap moves you, not the ball's target: it is a repositioning trick.
]]

return {
	Order = { "Dash", "SuperJump", "Swap", "Freeze", "Shield" },

	Abilities = {
		Dash = {
			Name = "Dash",
			Description = "Burst forward in the direction you move.",
			Price = 0,
			Cooldown = 6,
			Rarity = "Common",
			Power = 95, -- studs/s burst
			Duration = 0.18,
			Color = { 120, 220, 255 },
		},
		SuperJump = {
			Name = "Super Jump",
			Description = "Launch high into the air to get away from the crowd.",
			Price = 750,
			Cooldown = 8,
			Rarity = "Rare",
			Power = 115,
			Color = { 140, 255, 160 },
		},
		Swap = {
			Name = "Swap",
			Description = "Swap places with a random opponent. The ball keeps its target.",
			Price = 1500,
			Cooldown = 22,
			Rarity = "Epic",
			Color = { 200, 140, 255 },
		},
		Freeze = {
			Name = "Freeze",
			Description = "Only while the ball is chasing you: slow it to a crawl for 1.2s. You still have to parry.",
			Price = 2500,
			Cooldown = 30,
			Rarity = "Epic",
			SlowFactor = 0.3,
			Duration = 1.2,
			Color = { 160, 230, 255 },
		},
		Shield = {
			Name = "Shield",
			Description = "One free save per round: your first miss is absorbed and the ball flies to a random player (no kill credit).",
			Price = 4000,
			Cooldown = 0, -- passive, once per round
			Rarity = "Legendary",
			Color = { 255, 215, 100 },
			Passive = true,
		},
	},

	DefaultOwned = { "Dash" },
	MaxSlots = 1,
	MaxSlotsWithPass = 2,
}
