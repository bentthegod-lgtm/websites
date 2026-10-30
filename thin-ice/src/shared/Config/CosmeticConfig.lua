--[[
	CosmeticConfig - the wardrobe. Outfits add a beanie, scarf and jacket tint built from
	parts on the player's character; lanterns change the lantern light colour. Nothing here
	changes gameplay.

	Source: "Default" (everyone), "Coins" (Cost), "Product" (Robux developer product),
	"Pass" (VIP game pass), "Level" (reach Level).
]]

local CosmeticConfig = {}

CosmeticConfig.Outfits = {
	Classic = { Name = "Classic Woolies", Source = "Default", Beanie = { 236, 236, 240 }, Scarf = { 214, 72, 72 }, Jacket = { 236, 196, 110 } },
	Mint = { Name = "Mint Parka", Source = "Coins", Cost = 400, Beanie = { 140, 220, 210 }, Scarf = { 70, 90, 140 }, Jacket = { 120, 200, 190 } },
	Berry = { Name = "Berry Puffer", Source = "Coins", Cost = 650, Beanie = { 220, 140, 200 }, Scarf = { 240, 240, 244 }, Jacket = { 214, 90, 150 } },
	Ranger = { Name = "Lake Ranger", Source = "Level", Level = 5, Beanie = { 60, 90, 70 }, Scarf = { 236, 200, 90 }, Jacket = { 80, 120, 90 } },
	Midnight = { Name = "Midnight Hiker", Source = "Coins", Cost = 1200, Beanie = { 40, 44, 70 }, Scarf = { 120, 170, 255 }, Jacket = { 50, 60, 100 } },
	Polar = { Name = "Polar Explorer", Source = "Product", Beanie = { 250, 250, 255 }, Scarf = { 80, 170, 255 }, Jacket = { 240, 244, 250 } },
	Golden = { Name = "Golden Parka", Source = "Pass", Beanie = { 255, 214, 90 }, Scarf = { 140, 90, 40 }, Jacket = { 240, 190, 70 } },
}
CosmeticConfig.OutfitOrder = { "Classic", "Mint", "Berry", "Ranger", "Midnight", "Polar", "Golden" }

CosmeticConfig.Lanterns = {
	Warm = { Name = "Warm Lantern", Source = "Default", Color = { 255, 196, 120 } },
	Frost = { Name = "Frost Lantern", Source = "Coins", Cost = 300, Color = { 150, 220, 255 } },
	Ember = { Name = "Ember Lantern", Source = "Level", Level = 3, Color = { 255, 120, 70 } },
	Aurora = { Name = "Aurora Lantern", Source = "Product", Color = { 120, 255, 190 } },
}
CosmeticConfig.LanternOrder = { "Warm", "Frost", "Ember", "Aurora" }

CosmeticConfig.Kinds = { Outfit = CosmeticConfig.Outfits, Lantern = CosmeticConfig.Lanterns }
CosmeticConfig.Defaults = { Outfit = "Classic", Lantern = "Warm" }

return CosmeticConfig
