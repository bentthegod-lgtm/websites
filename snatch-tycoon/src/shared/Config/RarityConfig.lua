--[[
	Rarity tiers. Weight is the base spawn weight on the carpet (luck multiplies the rarer
	tiers, see Spawner.rarityWeights). Colors are used for glow, nameplates and the feed.
]]

return {
	Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" },
	Tiers = {
		Common = { Weight = 520, Color = { 214, 220, 228 }, Scale = 1.0, Glow = false, Sparkles = false, Announce = false },
		Uncommon = { Weight = 260, Color = { 96, 226, 118 }, Scale = 1.08, Glow = false, Sparkles = false, Announce = false },
		Rare = { Weight = 130, Color = { 72, 156, 255 }, Scale = 1.16, Glow = false, Sparkles = false, Announce = false },
		Epic = { Weight = 60, Color = { 186, 96, 255 }, Scale = 1.26, Glow = true, Sparkles = false, Announce = false },
		Legendary = { Weight = 22, Color = { 255, 186, 40 }, Scale = 1.38, Glow = true, Sparkles = true, Announce = true },
		Mythic = { Weight = 6, Color = { 255, 64, 112 }, Scale = 1.5, Glow = true, Sparkles = true, Announce = true },
		Secret = { Weight = 1.2, Color = { 30, 255, 226 }, Scale = 1.66, Glow = true, Sparkles = true, Announce = true },
	},
	-- Tiers from this index up are multiplied by luck.
	LuckFromIndex = 3,
	-- Tiers from this index up are also multiplied by "Mythic Madness" style boosts.
	MythicFromIndex = 6,
}
