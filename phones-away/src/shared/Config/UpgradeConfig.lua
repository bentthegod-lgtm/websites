--[[
	Clout upgrades. Tier 0 / 1 is the free starting level. Every tier is buyable with Clout
	earned by playing, so free players can max everything; game passes only skip ahead to a
	bounded tier (see ShopConfig).
]]

return {
	Order = { "Phone", "Scanner", "Earbuds", "Case", "Hide", "Cover", "Backpack", "Watch" },

	-- More answers revealed per screenshot.
	Phone = {
		Name = "Phone Model",
		Description = "Better camera = more answers per screenshot.",
		Start = 1,
		Tiers = {
			{ Name = "Hand-me-down Brick", Price = 0, Answers = 2, Color = { 120, 120, 130 }, Size = { 0.62, 1.15, 0.22 } },
			{ Name = "Flip Classic", Price = 600, Answers = 3, Color = { 70, 160, 255 }, Size = { 0.6, 1.1, 0.16 } },
			{ Name = "Slab S", Price = 2500, Answers = 4, Color = { 40, 40, 48 }, Size = { 0.6, 1.2, 0.1 } },
			{ Name = "Ultra Max 12", Price = 8000, Answers = 5, Color = { 255, 196, 70 }, Size = { 0.72, 1.45, 0.08 } },
		},
	},

	-- How long the answer scanner app takes (the phone must stay out the whole time).
	Scanner = {
		Name = "Scanner App",
		Description = "Faster answer scanning = less time with your phone out.",
		Start = 0,
		Tiers = {
			[0] = { Name = "ScanBuddy Free (ads!)", Price = 0, Seconds = 6 },
			{ Name = "ScanBuddy Plus", Price = 300, Seconds = 5 },
			{ Name = "ScanBuddy Pro", Price = 1200, Seconds = 4 },
			{ Name = "BrainBeam", Price = 3500, Seconds = 3.2 },
			{ Name = "BrainBeam Turbo", Price = 7500, Seconds = 2.5 },
		},
	},

	Case = {
		Name = "Dim Screen",
		Description = "A privacy case dims your screen and the screenshot flash.",
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
		Name = "Silent Shutter",
		Description = "Earbuds + silent mode: a quieter screenshot shutter and taps.",
		Start = 0,
		Tiers = {
			[0] = { Name = "LOUD shutter click", Price = 0, Noise = 1 },
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

	-- Late-tier gadget: glance at your wrist for 1 answer. Much less visible than a phone,
	-- but slow to recharge.
	Watch = {
		Name = "Smart Watch",
		Description = "Glance at your wrist for 1 answer. Low risk, slow cooldown.",
		Start = 0,
		Tiers = {
			[0] = { Name = "No watch", Price = 0 },
			{ Name = "Smart Watch", Price = 4000, Glance = 3, Cooldown = 45 },
			{ Name = "Smart Watch Pro", Price = 9000, Glance = 2.2, Cooldown = 30 },
		},
	},

	-- Exclusive Pro Phone (game pass): +1 answer per screenshot, but never past the best Clout
	-- phone's 5, so a free player with the Ultra Max is never behind.
	ProPhone = { Name = "Prism Pro (exclusive)", BonusAnswers = 1, Color = { 120, 255, 230 }, Size = { 0.7, 1.4, 0.07 } },
	MaxAnswersPerSnap = 5,

	-- Pass floors (bounded: the Clout shop always has a better tier on top).
	SilentModeEarbudsTier = 3,
	ExtraHideSpeedBonus = 0.05,
	MinHideSeconds = 0.15,
}
