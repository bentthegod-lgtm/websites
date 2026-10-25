--[[
	Cosmetics: purely visual, no stat differences.

	Skin       - colour / material of your phone (seen by classmates when it's out!)
	Decor      - a little item on your desk, built from parts
	Wallpaper  - the background of your phone screen UI

	Items with a Price can be bought with Clout in the LOCKER. Crates roll a rarity first
	(odds shown before buying) and then an item of that rarity. Duplicates refund Clout.
]]

local Rarities = {
	Order = { "Common", "Rare", "Epic", "Legendary", "Mythic" },
	Common = { Color = { 200, 205, 215 }, Refund = 25 },
	Rare = { Color = { 80, 170, 255 }, Refund = 70 },
	Epic = { Color = { 190, 100, 255 }, Refund = 180 },
	Legendary = { Color = { 255, 196, 60 }, Refund = 450 },
	Mythic = { Color = { 255, 70, 140 }, Refund = 1100 },
}

local Items = {
	-- Phone skins
	{ Id = "Default", Category = "Skin", Name = "Factory Fresh", Rarity = "Common", Default = true },
	{ Id = "Bubblegum", Category = "Skin", Name = "Bubblegum", Rarity = "Common", Color = { 255, 140, 200 }, Price = 150 },
	{ Id = "Mint", Category = "Skin", Name = "Mint Chip", Rarity = "Common", Color = { 140, 240, 200 }, Price = 150 },
	{ Id = "Camo", Category = "Skin", Name = "Desk Camo", Rarity = "Rare", Color = { 150, 120, 80 }, Material = "Wood", Price = 600 },
	{ Id = "Denim", Category = "Skin", Name = "Denim", Rarity = "Rare", Color = { 70, 100, 160 }, Material = "Fabric" },
	{ Id = "Marble", Category = "Skin", Name = "Marble Luxe", Rarity = "Epic", Color = { 235, 235, 240 }, Material = "Marble" },
	{ Id = "Lava", Category = "Skin", Name = "Lava Lamp", Rarity = "Epic", Color = { 255, 90, 40 }, Neon = true },
	{ Id = "Gold", Category = "Skin", Name = "Solid Gold (fake)", Rarity = "Legendary", Color = { 255, 200, 60 }, Material = "Foil" },
	{ Id = "Galaxy", Category = "Skin", Name = "Galaxy Brain", Rarity = "Legendary", Color = { 90, 50, 200 }, Neon = true },
	{ Id = "Hologram", Category = "Skin", Name = "Hologram", Rarity = "Mythic", Color = { 120, 255, 240 }, Material = "Glass", Neon = true },

	-- Desk decorations
	{ Id = "None", Category = "Decor", Name = "Clean desk", Rarity = "Common", Default = true },
	{ Id = "Pencils", Category = "Decor", Name = "Pencil Cup", Rarity = "Common", Price = 100, Style = "Pencils" },
	{ Id = "Plant", Category = "Decor", Name = "Tiny Cactus", Rarity = "Common", Price = 150, Style = "Plant" },
	{ Id = "Duck", Category = "Decor", Name = "Rubber Duck", Rarity = "Rare", Price = 500, Style = "Duck" },
	{ Id = "Apple", Category = "Decor", Name = "Apple for Teacher", Rarity = "Rare", Style = "Apple" },
	{ Id = "LavaLamp", Category = "Decor", Name = "Lava Lamp", Rarity = "Epic", Style = "LavaLamp" },
	{ Id = "Trophy", Category = "Decor", Name = "Participation Trophy", Rarity = "Epic", Style = "Trophy" },
	{ Id = "Globe", Category = "Decor", Name = "Spinny Globe", Rarity = "Legendary", Style = "Globe" },
	{ Id = "Crown", Category = "Decor", Name = "Class Crown", Rarity = "Mythic", Style = "Crown" },

	-- Wallpapers (phone UI background gradient)
	{ Id = "Default", Category = "Wallpaper", Name = "Midnight", Rarity = "Common", Colors = { { 30, 30, 60 }, { 10, 10, 25 } }, Default = true },
	{ Id = "Sunset", Category = "Wallpaper", Name = "Sunset", Rarity = "Common", Colors = { { 255, 120, 90 }, { 120, 40, 140 } }, Price = 120 },
	{ Id = "Ocean", Category = "Wallpaper", Name = "Ocean", Rarity = "Common", Colors = { { 40, 180, 255 }, { 10, 40, 120 } }, Price = 120 },
	{ Id = "Matcha", Category = "Wallpaper", Name = "Matcha", Rarity = "Rare", Colors = { { 160, 230, 120 }, { 40, 110, 60 } }, Price = 400 },
	{ Id = "Vapor", Category = "Wallpaper", Name = "Vaporwave", Rarity = "Rare", Colors = { { 255, 110, 220 }, { 60, 220, 255 } } },
	{ Id = "Candy", Category = "Wallpaper", Name = "Candy Shop", Rarity = "Epic", Colors = { { 255, 200, 230 }, { 255, 120, 170 } } },
	{ Id = "Aurora", Category = "Wallpaper", Name = "Aurora", Rarity = "Legendary", Colors = { { 80, 255, 180 }, { 90, 60, 220 } } },
	{ Id = "GoldRush", Category = "Wallpaper", Name = "Gold Rush", Rarity = "Mythic", Colors = { { 255, 230, 120 }, { 200, 110, 20 } } },
}

local Crates = {
	-- Clout crate: free-to-play path to every crate item.
	Locker = {
		Name = "Locker Crate",
		CloutPrice = 900,
		Odds = { Common = 55, Rare = 30, Epic = 11, Legendary = 3.5, Mythic = 0.5 },
		Color = { 120, 180, 255 },
	},
	-- Robux crate (bought as a Developer Product, see ShopConfig). Hidden and refused for
	-- players whose PolicyService info restricts paid random items.
	Skin = {
		Name = "Phone Skin Crate",
		Product = "SkinCrate",
		Odds = { Rare = 50, Epic = 33, Legendary = 14, Mythic = 3 },
		Categories = { Skin = true },
		Color = { 255, 120, 220 },
	},
}

return {
	Rarities = Rarities,
	Items = Items,
	Crates = Crates,
	CrateOrder = { "Locker", "Skin" },
	Categories = { "Skin", "Decor", "Wallpaper" },
	CategoryNames = { Skin = "Phone Skins", Decor = "Desk Decor", Wallpaper = "Wallpapers" },
	PityEvery = 30, -- every 30 opens without Legendary+, the next is Legendary+
	AnnounceRank = 4, -- Legendary and up are announced server-wide
}
