--[[
	Rarity tiers, lowest to highest. Color is used for UI text, seed packets and
	announcements. Prismatic is drawn as an animated rainbow gradient in the UI.
]]

return {
	Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Prismatic" },
	Tiers = {
		Common = { Rank = 1, Color = { 200, 200, 190 } },
		Uncommon = { Rank = 2, Color = { 110, 210, 90 } },
		Rare = { Rank = 3, Color = { 80, 160, 255 } },
		Epic = { Rank = 4, Color = { 180, 100, 255 } },
		Legendary = { Rank = 5, Color = { 255, 170, 40 } },
		Mythic = { Rank = 6, Color = { 255, 80, 140 } },
		Divine = { Rank = 7, Color = { 255, 236, 120 } },
		Prismatic = { Rank = 8, Color = { 120, 255, 230 } },
	},
	-- A seed of this rank or higher appearing in the Seed Shop is announced to the server.
	AnnounceStockRank = 5,
	-- A harvest of this rank or higher is announced to the server.
	AnnounceHarvestRank = 6,
}
