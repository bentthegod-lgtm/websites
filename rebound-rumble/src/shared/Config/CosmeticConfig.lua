--[[
	Cosmetics: purely visual, no stat differences of any kind.

	Categories
	  ParryFx   - the weapon swung when you parry (built from parts by WeaponModels).
	  Trail     - the trail the ball leaves after YOU deflect it.
	  Explosion - the colour of the explosion when YOUR deflect eliminates someone.

	Crates roll a rarity first (odds shown in the UI), then a random item of that rarity
	from the crate's pool. Duplicates are refunded in coins.
]]

local Rarities = {
	Order = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Exclusive" },
	Common = { Color = { 190, 196, 206 }, Refund = 40 },
	Rare = { Color = { 80, 170, 255 }, Refund = 120 },
	Epic = { Color = { 190, 100, 255 }, Refund = 300 },
	Legendary = { Color = { 255, 196, 60 }, Refund = 800 },
	Mythic = { Color = { 255, 70, 120 }, Refund = 2000 },
	Exclusive = { Color = { 90, 255, 220 }, Refund = 0 },
}

local Items = {
	-- Parry effects (weapon style + colours)
	{ Id = "Blade", Category = "ParryFx", Name = "Training Blade", Rarity = "Common", Style = "Sword", Color = { 210, 215, 225 }, Accent = { 90, 70, 50 }, Default = true },
	{ Id = "Slugger", Category = "ParryFx", Name = "Slugger", Rarity = "Common", Style = "Bat", Color = { 196, 150, 100 }, Accent = { 40, 40, 40 } },
	{ Id = "NeonSlugger", Category = "ParryFx", Name = "Neon Slugger", Rarity = "Rare", Style = "Bat", Color = { 60, 255, 200 }, Accent = { 20, 20, 30 }, Neon = true },
	{ Id = "Moonlit", Category = "ParryFx", Name = "Moonlit Katana", Rarity = "Rare", Style = "Katana", Color = { 200, 220, 255 }, Accent = { 30, 30, 60 } },
	{ Id = "Thunder", Category = "ParryFx", Name = "Thunder Mallet", Rarity = "Epic", Style = "Hammer", Color = { 255, 230, 90 }, Accent = { 70, 80, 120 }, Neon = true },
	{ Id = "Reaper", Category = "ParryFx", Name = "Reaper's Arc", Rarity = "Legendary", Style = "Scythe", Color = { 150, 60, 255 }, Accent = { 25, 20, 30 }, Neon = true },
	{ Id = "Solar", Category = "ParryFx", Name = "Solar Edge", Rarity = "Mythic", Style = "Sword", Color = { 255, 140, 40 }, Accent = { 255, 240, 160 }, Neon = true },

	-- Ball trails
	{ Id = "Basic", Category = "Trail", Name = "Basic Streak", Rarity = "Common", Colors = { { 255, 255, 255 }, { 200, 220, 255 } }, Default = true },
	{ Id = "Ember", Category = "Trail", Name = "Ember", Rarity = "Common", Colors = { { 255, 160, 60 }, { 255, 60, 30 } } },
	{ Id = "Aqua", Category = "Trail", Name = "Aqua Rush", Rarity = "Rare", Colors = { { 80, 230, 255 }, { 30, 90, 255 } } },
	{ Id = "Toxic", Category = "Trail", Name = "Toxic", Rarity = "Rare", Colors = { { 170, 255, 60 }, { 40, 160, 40 } } },
	{ Id = "Royal", Category = "Trail", Name = "Royal Velvet", Rarity = "Epic", Colors = { { 200, 90, 255 }, { 255, 200, 90 } } },
	{ Id = "Galaxy", Category = "Trail", Name = "Galaxy", Rarity = "Legendary", Colors = { { 60, 30, 160 }, { 255, 120, 220 } }, Sparkles = true },
	{ Id = "Prism", Category = "Trail", Name = "Prism Pulse (animated)", Rarity = "Exclusive", Colors = { { 255, 60, 60 }, { 60, 120, 255 } }, Animated = true, Pass = "PrismTrail", Crate = false },

	-- Explosion colours
	{ Id = "Classic", Category = "Explosion", Name = "Classic Boom", Rarity = "Common", Color = { 255, 140, 40 }, Default = true },
	{ Id = "Frost", Category = "Explosion", Name = "Frostburst", Rarity = "Common", Color = { 150, 220, 255 } },
	{ Id = "Plasma", Category = "Explosion", Name = "Plasma Pop", Rarity = "Rare", Color = { 90, 255, 170 } },
	{ Id = "Void", Category = "Explosion", Name = "Void Implosion", Rarity = "Epic", Color = { 120, 40, 200 } },
	{ Id = "Supernova", Category = "Explosion", Name = "Supernova", Rarity = "Legendary", Color = { 255, 240, 140 } },
	{ Id = "Rainbow", Category = "Explosion", Name = "Rainbow Burst", Rarity = "Mythic", Color = { 255, 80, 200 }, Rainbow = true },
}

local Crates = {
	Basic = {
		Name = "Basic Crate",
		CoinPrice = 400,
		Odds = { Common = 62, Rare = 26, Epic = 9, Legendary = 2.6, Mythic = 0.4 },
		Color = { 120, 180, 255 },
	},
	Elite = {
		Name = "Elite Crate",
		CoinPrice = 1500,
		Odds = { Rare = 55, Epic = 32, Legendary = 11, Mythic = 2 },
		Color = { 200, 110, 255 },
	},
	Premium = {
		Name = "Premium Spin",
		-- Opened with Premium Spins bought as a Developer Product (see ShopConfig).
		SpinCurrency = "PremiumSpins",
		Odds = { Rare = 40, Epic = 38, Legendary = 18, Mythic = 4 },
		Color = { 255, 200, 80 },
	},
}

return {
	Rarities = Rarities,
	Items = Items,
	Crates = Crates,
	CrateOrder = { "Basic", "Elite", "Premium" },
	Categories = { "ParryFx", "Trail", "Explosion" },
	CategoryNames = { ParryFx = "Parry Effects", Trail = "Ball Trails", Explosion = "Explosions" },
	-- Every this many opens without a Legendary or better, the next open is Legendary+.
	PityEvery = 40,
	-- Confetti colours used by the Server Explosion Party.
	ConfettiColors = { { 255, 80, 120 }, { 255, 210, 60 }, { 80, 220, 255 }, { 140, 255, 120 }, { 200, 120, 255 } },
}
