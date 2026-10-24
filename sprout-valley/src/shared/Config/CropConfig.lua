--[[
	Every crop in Sprout Valley.

	SeedPrice   coins per seed in the Seed Shop
	Value       sell price of one fruit at exactly BaseKg with no mutations
	BaseKg      average fruit weight; the harvest rolls a weight around it
	GrowTime    seconds from planting to the first ripe fruit (real time, keeps going offline)
	Regrow      multi-harvest crops only: seconds to grow the next fruit after picking
	StockChance chance to appear in each 5-minute Seed Shop restock
	StockQty    {min, max} seeds per player when it appears
	Model       procedural model recipe (see CropModels.lua): Type + colors
]]

local Crops = {
	-- Common
	{ Id = "Carrot", Name = "Carrot", Rarity = "Common", SeedPrice = 10, Value = 22, BaseKg = 0.3, GrowTime = 45, StockChance = 1, StockQty = { 8, 20 },
		Model = { Type = "Root", Leaf = { 80, 170, 60 }, Fruit = { 255, 130, 30 } } },
	{ Id = "Radish", Name = "Radish", Rarity = "Common", SeedPrice = 18, Value = 38, BaseKg = 0.25, GrowTime = 70, StockChance = 1, StockQty = { 5, 15 },
		Model = { Type = "Root", Leaf = { 90, 180, 70 }, Fruit = { 230, 50, 90 }, Round = true } },
	{ Id = "Lettuce", Name = "Lettuce", Rarity = "Common", SeedPrice = 25, Value = 55, BaseKg = 0.6, GrowTime = 100, StockChance = 0.9, StockQty = { 4, 12 },
		Model = { Type = "Leafy", Leaf = { 120, 200, 80 }, Fruit = { 170, 230, 120 } } },
	{ Id = "Strawberry", Name = "Strawberry", Rarity = "Common", SeedPrice = 50, Value = 14, BaseKg = 0.05, GrowTime = 90, Regrow = 30, StockChance = 0.9, StockQty = { 3, 10 },
		Model = { Type = "Bush", Leaf = { 60, 150, 60 }, Fruit = { 235, 40, 60 }, FruitSize = 0.45 } },

	-- Uncommon
	{ Id = "Blueberry", Name = "Blueberry", Rarity = "Uncommon", SeedPrice = 120, Value = 22, BaseKg = 0.02, GrowTime = 140, Regrow = 40, StockChance = 0.7, StockQty = { 2, 8 },
		Model = { Type = "Bush", Leaf = { 50, 130, 70 }, Fruit = { 70, 90, 220 }, FruitSize = 0.32, FruitCount = 9 } },
	{ Id = "Tomato", Name = "Tomato", Rarity = "Uncommon", SeedPrice = 200, Value = 35, BaseKg = 0.25, GrowTime = 180, Regrow = 55, StockChance = 0.65, StockQty = { 2, 6 },
		Model = { Type = "Stake", Leaf = { 70, 160, 60 }, Fruit = { 230, 50, 40 }, FruitSize = 0.55 } },
	{ Id = "Corn", Name = "Corn", Rarity = "Uncommon", SeedPrice = 260, Value = 45, BaseKg = 0.4, GrowTime = 200, Regrow = 70, StockChance = 0.6, StockQty = { 2, 6 },
		Model = { Type = "Stalk", Leaf = { 100, 180, 60 }, Fruit = { 250, 210, 60 } } },
	{ Id = "BellPepper", Name = "Bell Pepper", Rarity = "Uncommon", SeedPrice = 300, Value = 50, BaseKg = 0.2, GrowTime = 220, Regrow = 75, StockChance = 0.5, StockQty = { 1, 5 },
		Model = { Type = "Stake", Leaf = { 60, 150, 60 }, Fruit = { 250, 200, 40 }, FruitSize = 0.6, Tall = false } },

	-- Rare
	{ Id = "Pumpkin", Name = "Pumpkin", Rarity = "Rare", SeedPrice = 600, Value = 1150, BaseKg = 6, GrowTime = 420, StockChance = 0.4, StockQty = { 1, 4 },
		Model = { Type = "Ground", Leaf = { 70, 150, 50 }, Fruit = { 250, 140, 30 }, FruitSize = 2.2, Ribbed = true } },
	{ Id = "Watermelon", Name = "Watermelon", Rarity = "Rare", SeedPrice = 750, Value = 1500, BaseKg = 7, GrowTime = 480, StockChance = 0.35, StockQty = { 1, 3 },
		Model = { Type = "Ground", Leaf = { 60, 140, 50 }, Fruit = { 40, 130, 50 }, Accent = { 140, 210, 110 }, FruitSize = 2.4, Long = true } },
	{ Id = "Cactus", Name = "Cactus", Rarity = "Rare", SeedPrice = 900, Value = 110, BaseKg = 1.5, GrowTime = 360, Regrow = 110, StockChance = 0.3, StockQty = { 1, 3 },
		Model = { Type = "Cactus", Leaf = { 70, 150, 80 }, Fruit = { 255, 120, 170 }, FruitSize = 0.55 } },
	{ Id = "Grape", Name = "Grape", Rarity = "Rare", SeedPrice = 1100, Value = 140, BaseKg = 0.5, GrowTime = 400, Regrow = 120, StockChance = 0.25, StockQty = { 1, 3 },
		Model = { Type = "Stake", Leaf = { 80, 150, 60 }, Fruit = { 130, 60, 170 }, FruitSize = 0.3, Bunches = true } },

	-- Epic
	{ Id = "Apple", Name = "Apple Tree", Rarity = "Epic", SeedPrice = 2500, Value = 260, BaseKg = 0.3, GrowTime = 720, Regrow = 180, StockChance = 0.18, StockQty = { 1, 3 },
		Model = { Type = "Tree", Leaf = { 70, 160, 60 }, Fruit = { 220, 40, 40 }, Trunk = { 120, 80, 50 }, FruitSize = 0.55 } },
	{ Id = "Coconut", Name = "Coconut Palm", Rarity = "Epic", SeedPrice = 3200, Value = 340, BaseKg = 1.4, GrowTime = 780, Regrow = 200, StockChance = 0.15, StockQty = { 1, 2 },
		Model = { Type = "Palm", Leaf = { 80, 170, 60 }, Fruit = { 110, 75, 45 }, Trunk = { 160, 120, 80 }, FruitSize = 0.75 } },
	{ Id = "Mango", Name = "Mango Tree", Rarity = "Epic", SeedPrice = 4000, Value = 420, BaseKg = 0.6, GrowTime = 840, Regrow = 220, StockChance = 0.12, StockQty = { 1, 2 },
		Model = { Type = "Tree", Leaf = { 50, 140, 70 }, Fruit = { 255, 160, 40 }, Accent = { 230, 80, 50 }, Trunk = { 110, 75, 50 }, FruitSize = 0.65, Oval = true } },
	{ Id = "Pineapple", Name = "Pineapple", Rarity = "Epic", SeedPrice = 3000, Value = 4200, BaseKg = 2, GrowTime = 900, StockChance = 0.14, StockQty = { 1, 2 },
		Model = { Type = "Rosette", Leaf = { 70, 150, 80 }, Fruit = { 240, 180, 50 }, FruitSize = 1.2 } },

	-- Legendary
	{ Id = "DragonFruit", Name = "Dragon Fruit", Rarity = "Legendary", SeedPrice = 12000, Value = 1100, BaseKg = 0.5, GrowTime = 1200, Regrow = 260, StockChance = 0.07, StockQty = { 1, 2 },
		Model = { Type = "Cactus", Leaf = { 80, 170, 90 }, Fruit = { 240, 50, 150 }, Accent = { 120, 220, 80 }, FruitSize = 0.8, Arms = 3 } },
	{ Id = "GlowMushroom", Name = "Glow Mushroom", Rarity = "Legendary", SeedPrice = 15000, Value = 1300, BaseKg = 0.15, GrowTime = 1080, Regrow = 240, StockChance = 0.06, StockQty = { 1, 2 },
		Model = { Type = "Mushroom", Leaf = { 230, 225, 210 }, Fruit = { 80, 230, 255 }, Glow = { 80, 230, 255 } } },
	{ Id = "Frostmint", Name = "Frostmint", Rarity = "Legendary", SeedPrice = 18000, Value = 1500, BaseKg = 0.1, GrowTime = 1260, Regrow = 280, StockChance = 0.05, StockQty = { 1, 2 },
		Model = { Type = "Bush", Leaf = { 140, 230, 220 }, Fruit = { 210, 250, 255 }, FruitSize = 0.4, LeafMaterial = "Glass", Glow = { 170, 240, 255 } } },

	-- Mythic
	{ Id = "MoonMelon", Name = "Moon Melon", Rarity = "Mythic", SeedPrice = 45000, Value = 95000, BaseKg = 9, GrowTime = 2400, StockChance = 0.03, StockQty = { 1, 1 },
		Model = { Type = "Ground", Leaf = { 90, 110, 160 }, Fruit = { 210, 225, 255 }, Accent = { 150, 165, 210 }, FruitSize = 2.6, Glow = { 190, 210, 255 }, Craters = true } },
	{ Id = "StarFruit", Name = "Star Fruit", Rarity = "Mythic", SeedPrice = 60000, Value = 4200, BaseKg = 0.35, GrowTime = 2100, Regrow = 420, StockChance = 0.025, StockQty = { 1, 1 },
		Model = { Type = "Tree", Leaf = { 60, 120, 120 }, Fruit = { 255, 235, 90 }, Trunk = { 90, 70, 100 }, FruitSize = 0.6, Star = true, Glow = { 255, 240, 140 } } },
	{ Id = "EmberPepper", Name = "Ember Pepper", Rarity = "Mythic", SeedPrice = 75000, Value = 5000, BaseKg = 0.15, GrowTime = 2160, Regrow = 450, StockChance = 0.02, StockQty = { 1, 1 },
		Model = { Type = "Stake", Leaf = { 120, 60, 40 }, Fruit = { 255, 90, 30 }, FruitSize = 0.5, Glow = { 255, 120, 40 }, Ember = true } },

	-- Divine
	{ Id = "Cloudberry", Name = "Cloudberry", Rarity = "Divine", SeedPrice = 200000, Value = 14000, BaseKg = 0.08, GrowTime = 3000, Regrow = 600, StockChance = 0.01, StockQty = { 1, 1 },
		Model = { Type = "Bush", Leaf = { 245, 248, 255 }, Fruit = { 255, 210, 90 }, FruitSize = 0.45, Floating = true, Glow = { 255, 240, 200 } } },
	{ Id = "CrystalBeet", Name = "Crystal Beet", Rarity = "Divine", SeedPrice = 250000, Value = 450000, BaseKg = 2.5, GrowTime = 3600, StockChance = 0.008, StockQty = { 1, 1 },
		Model = { Type = "Root", Leaf = { 160, 90, 200 }, Fruit = { 200, 120, 255 }, Round = true, Crystal = true, Glow = { 210, 150, 255 } } },

	-- Prismatic
	{ Id = "PrismPear", Name = "Prism Pear", Rarity = "Prismatic", SeedPrice = 900000, Value = 50000, BaseKg = 0.4, GrowTime = 4800, Regrow = 900, StockChance = 0.004, StockQty = { 1, 1 },
		Model = { Type = "Tree", Leaf = { 200, 230, 255 }, Fruit = { 255, 255, 255 }, Trunk = { 230, 230, 240 }, FruitSize = 0.6, Prism = true, LeafMaterial = "Glass", Glow = { 220, 200, 255 } } },
	{ Id = "StarlightLotus", Name = "Starlight Lotus", Rarity = "Prismatic", SeedPrice = 1200000, Value = 3500000, BaseKg = 1.2, GrowTime = 5400, StockChance = 0.003, StockQty = { 1, 1 },
		Model = { Type = "Lotus", Leaf = { 60, 160, 120 }, Fruit = { 255, 200, 240 }, Accent = { 140, 220, 255 }, Glow = { 255, 220, 250 } } },
}

local byId = {}
for i, crop in ipairs(Crops) do
	crop.Order = i
	byId[crop.Id] = crop
end

return {
	List = Crops,
	ById = byId,
}
