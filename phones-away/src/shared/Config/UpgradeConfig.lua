--[[
	Clout upgrades. Tier 0 / 1 is the free starting level. Every tier is buyable with Clout
	earned by playing, so free players can max everything; game passes only skip ahead to a
	bounded tier (see ShopConfig).
]]

return {
	Order = { "Phone", "Case", "Earbuds", "Cover", "Hide", "Backpack" },

	Phone = {
		Name = "Phone Model",
		Description = "Better phone = more Clout per second.",
		Start = 1,
		Tiers = {
			{ Name = "Hand-me-down Brick", Price = 0, Rate = 1.0, Color = { 120, 120, 130 }, Size = { 0.62, 1.15, 0.22 } },
			{ Name = "Flip Classic", Price = 250, Rate = 1.35, Color = { 70, 160, 255 }, Size = { 0.6, 1.1, 0.16 } },
			{ Name = "Slab S", Price = 800, Rate = 1.75, Color = { 40, 40, 48 }, Size = { 0.6, 1.2, 0.1 } },
			{ Name = "Slab S Plus", Price = 2000, Rate = 2.2, Color = { 230, 230, 240 }, Size = { 0.66, 1.3, 0.09 } },
			{ Name = "Fold Z", Price = 5000, Rate = 2.75, Color = { 90, 60, 160 }, Size = { 0.85, 1.3, 0.09 } },
			{ Name = "Ultra Max 12", Price = 12000, Rate = 3.3, Color = { 255, 196, 70 }, Size = { 0.72, 1.45, 0.08 } },
		},
	},

	Case = {
		Name = "Phone Case",
		Description = "Dims your screen glow: harder to see.",
		Start = 0,
		Tiers = {
			[0] = { Name = "No case", Price = 0, Glow = 1 },
			{ Name = "Matte Case", Price = 150, Glow = 0.88 },
			{ Name = "Privacy Screen", Price = 600, Glow = 0.76 },
			{ Name = "Stealth Shell", Price = 1800, Glow = 0.66 },
			{ Name = "Ninja Sleeve", Price = 4500, Glow = 0.58 },
		},
	},

	Earbuds = {
		Name = "Earbuds",
		Description = "Silent taps: less noise for the teacher to hear.",
		Start = 0,
		Tiers = {
			[0] = { Name = "Loud speaker", Price = 0, Noise = 1 },
			{ Name = "Wired Buds", Price = 120, Noise = 0.8 },
			{ Name = "Wireless Buds", Price = 500, Noise = 0.62 },
			{ Name = "Noise-Cancel Pods", Price = 1500, Noise = 0.48 },
			{ Name = "Whisper Pods", Price = 4000, Noise = 0.38 },
		},
	},

	Cover = {
		Name = "Cover",
		Description = "Hide behind something: less of your glow is visible.",
		Start = 0,
		Tiers = {
			[0] = { Name = "Nothing", Price = 0, Sight = 1 },
			{ Name = "Hoodie Hood", Price = 300, Sight = 0.86 },
			{ Name = "Textbook Stand", Price = 1200, Sight = 0.74 },
			{ Name = "Textbook Fort", Price = 3500, Sight = 0.64 },
		},
	},

	Hide = {
		Name = "Hide Speed",
		Description = "How fast your phone vanishes when you let go.",
		Start = 0,
		Tiers = {
			[0] = { Name = "Fumbly", Price = 0, Seconds = 0.45 },
			{ Name = "Quick Hands", Price = 200, Seconds = 0.38 },
			{ Name = "Smooth Operator", Price = 900, Seconds = 0.31 },
			{ Name = "Lightning Reflexes", Price = 2500, Seconds = 0.25 },
			{ Name = "Magician", Price = 6000, Seconds = 0.2 },
		},
	},

	Backpack = {
		Name = "Backpack Spot",
		Description = "A hiding spot: the phone stops glowing sooner after you hide it.",
		Start = 0,
		Tiers = {
			[0] = { Name = "Desk shelf", Price = 0, Linger = 1.0 },
			{ Name = "Backpack Pocket", Price = 700, Linger = 0.55 },
			{ Name = "Secret Compartment", Price = 3000, Linger = 0.2 },
		},
	},

	-- Exclusive Pro Phone (game pass): 10% above the best Clout phone, nothing more.
	ProPhone = { Name = "Prism Pro (exclusive)", Rate = 3.6, Color = { 120, 255, 230 }, Size = { 0.7, 1.4, 0.07 } },

	-- Pass floors (bounded: the Clout shop always has a better tier on top).
	SilentModeEarbudsTier = 3,
	ExtraHideSpeedBonus = 0.05,
	MinHideSeconds = 0.15,
}
