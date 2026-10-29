--[[
	LootConfig - every loot type in the vault.

	Fields per item:
	  Id, Name, Category (stack style + pickup sound), Depth (floor it spawns on),
	  Rarity, Value (base cash value), SpawnWeight (relative chance on its floor),
	  MaxActive (cap of this item alive at once on its floor), Slots (carrying capacity it
	  uses), Size ("S" fits shelves, "M" tables and floor, "L" floor plinths only),
	  Pickup ("Light" / "Heavy": heavier items play a heavier sound and a longer lift),
	  Special (only spawned by rare loot events, never by the normal table).
	Models are built from parts by LootModels.build(Id).
]]

local LootConfig = {}

LootConfig.Rarities = {
	Common = { Rank = 1, Color = { 210, 214, 220 } },
	Uncommon = { Rank = 2, Color = { 110, 220, 120 } },
	Rare = { Rank = 3, Color = { 90, 160, 255 } },
	Epic = { Rank = 4, Color = { 190, 110, 255 } },
	Legendary = { Rank = 5, Color = { 255, 190, 50 } },
	Mythic = { Rank = 6, Color = { 255, 80, 120 } },
}
LootConfig.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

-- Category: the look of a carried stack piece and the pickup sound group.
LootConfig.Categories = {
	Cash = { Name = "Cash", Sound = "CashPickup", Color = { 96, 168, 92 } },
	Gold = { Name = "Gold", Sound = "GoldPickup", Color = { 236, 184, 58 } },
	Diamond = { Name = "Diamonds", Sound = "GemPickup", Color = { 196, 232, 255 } },
	Emerald = { Name = "Emeralds", Sound = "GemPickup", Color = { 40, 200, 110 } },
	Platinum = { Name = "Platinum", Sound = "MetalPickup", Color = { 214, 220, 228 } },
	Artifact = { Name = "Artifacts", Sound = "ArtifactPickup", Color = { 190, 140, 80 } },
	Legendary = { Name = "Legendary", Sound = "ArtifactPickup", Color = { 255, 200, 70 } },
}
LootConfig.CategoryOrder = { "Cash", "Gold", "Diamond", "Emerald", "Platinum", "Artifact", "Legendary" }

local function item(id, name, category, depth, rarity, value, weight, maxActive, slots, size, pickup)
	return {
		Id = id,
		Name = name,
		Category = category,
		Depth = depth,
		Rarity = rarity,
		Value = value,
		SpawnWeight = weight,
		MaxActive = maxActive,
		Slots = slots,
		Size = size,
		Pickup = pickup or "Light",
	}
end

local function special(id, name, category, depth, rarity, value)
	local def = item(id, name, category, depth, rarity, value, 0, 1, 2, "L", "Heavy")
	def.Special = true
	return def
end

LootConfig.List = {
	-- Depth 1: Cash Vault
	item("Bill", "Loose Bills", "Cash", 1, "Common", 10, 60, 40, 1, "S"),
	item("CashStack", "Cash Stack", "Cash", 1, "Uncommon", 35, 28, 18, 1, "S"),
	item("CashBundle", "Cash Bundle", "Cash", 1, "Rare", 90, 10, 8, 1, "M"),
	item("PremiumBundle", "Premium Bundle", "Cash", 1, "Epic", 300, 2, 2, 2, "M"),
	-- Depth 2: Gold Reserve
	item("GoldBar", "Small Gold Bar", "Gold", 2, "Common", 120, 58, 36, 1, "S"),
	item("GoldStack", "Gold Stack", "Gold", 2, "Uncommon", 320, 28, 16, 2, "M"),
	item("GoldBrick", "Large Gold Brick", "Gold", 2, "Rare", 800, 11, 7, 3, "L", "Heavy"),
	item("GoldCrate", "Premium Gold Bundle", "Gold", 2, "Epic", 2500, 3, 2, 3, "L", "Heavy"),
	-- Depth 3: Diamond Chamber
	item("Diamond", "Diamond", "Diamond", 3, "Common", 900, 58, 36, 1, "S"),
	item("DiamondCluster", "Diamond Cluster", "Diamond", 3, "Uncommon", 2200, 28, 16, 1, "S"),
	item("LargeGem", "Large Gemstone", "Diamond", 3, "Rare", 5500, 11, 7, 2, "M"),
	item("DiamondFormation", "Diamond Formation", "Diamond", 3, "Epic", 18000, 3, 2, 3, "L", "Heavy"),
	-- Depth 4: Emerald Reserve
	item("Emerald", "Emerald", "Emerald", 4, "Common", 6000, 58, 34, 1, "S"),
	item("EmeraldCluster", "Emerald Cluster", "Emerald", 4, "Uncommon", 14000, 28, 16, 1, "S"),
	item("PremiumEmerald", "Premium Gemstone", "Emerald", 4, "Rare", 35000, 11, 7, 2, "M"),
	item("GrandEmerald", "Rare Large Emerald", "Emerald", 4, "Epic", 110000, 3, 2, 3, "L", "Heavy"),
	-- Depth 5: Platinum Reserve
	item("PlatinumBar", "Platinum Bar", "Platinum", 5, "Common", 40000, 58, 34, 1, "S"),
	item("MetalStack", "Precious Metal Stack", "Platinum", 5, "Uncommon", 95000, 28, 16, 2, "M"),
	item("AlloyCanister", "Rare Alloy Container", "Platinum", 5, "Rare", 240000, 11, 7, 3, "L", "Heavy"),
	item("PlatinumCase", "Premium Metallic Treasure", "Platinum", 5, "Epic", 800000, 3, 2, 3, "L", "Heavy"),
	-- Depth 6: Artifact Chamber
	item("AncientCoin", "Ancient Coin", "Artifact", 6, "Common", 260000, 58, 34, 1, "S"),
	item("Relic", "Rare Relic", "Artifact", 6, "Uncommon", 650000, 28, 16, 1, "M"),
	item("Statuette", "Decorative Artifact", "Artifact", 6, "Rare", 1600000, 11, 7, 2, "M"),
	item("Sarcophagus", "Collectible Treasure", "Artifact", 6, "Epic", 5000000, 3, 2, 3, "L", "Heavy"),
	-- Depth 7: Legendary Reserve
	item("Chalice", "Gilded Chalice", "Legendary", 7, "Uncommon", 1800000, 56, 32, 1, "S"),
	item("Crown", "Jeweled Crown", "Legendary", 7, "Rare", 4500000, 28, 16, 2, "M"),
	item("Scepter", "Royal Scepter", "Legendary", 7, "Epic", 14000000, 12, 7, 2, "M"),
	item("LegendChest", "Legendary Chest", "Legendary", 7, "Legendary", 40000000, 3, 2, 3, "L", "Heavy"),
	-- Rare loot events (one per depth, spawned by LootService's event timer only)
	special("GoldenBundle", "Golden Cash Bundle", "Cash", 1, "Legendary", 1500),
	special("GiantGoldBar", "Giant Gold Bar", "Gold", 2, "Legendary", 30000),
	special("PerfectDiamond", "Perfect Diamond", "Diamond", 3, "Mythic", 250000),
	special("RoyalEmerald", "Royal Emerald", "Emerald", 4, "Legendary", 1500000),
	special("PlatinumCore", "Platinum Core", "Platinum", 5, "Legendary", 10000000),
	special("AncientIdol", "Ancient Relic", "Artifact", 6, "Mythic", 60000000),
	special("TreasureHoard", "Legendary Treasure Chest", "Legendary", 7, "Mythic", 200000000),
}

LootConfig.ById = {}
LootConfig.ByDepth = {}
LootConfig.SpecialByDepth = {}
for index, def in ipairs(LootConfig.List) do
	def.Order = index
	LootConfig.ById[def.Id] = def
	if def.Special then
		LootConfig.SpecialByDepth[def.Depth] = def
	else
		LootConfig.ByDepth[def.Depth] = LootConfig.ByDepth[def.Depth] or {}
		table.insert(LootConfig.ByDepth[def.Depth], def)
	end
end

function LootConfig.rank(def)
	return LootConfig.Rarities[def.Rarity].Rank
end

return LootConfig
