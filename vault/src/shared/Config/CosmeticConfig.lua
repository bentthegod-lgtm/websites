--[[
	CosmeticConfig - looks only. Stack themes tint and decorate the carried stack, trails
	follow the character, deposit effects play at the machine. No cosmetic changes any stat.
	Source: "Default" (everyone), "Achievement" (granted by QuestService), "Tokens" (bought
	with Vault Tokens), "Robux" (ShopConfig product or pass).
]]

local CosmeticConfig = {}

CosmeticConfig.Kinds = {
	Theme = {
		Classic = { Name = "Classic", Source = "Default", Order = 1, Description = "Plain banded loot." },
		Midnight = { Name = "Midnight", Source = "Tokens", Cost = 20, Order = 2, Tint = { 60, 70, 120 }, Description = "Dark steel straps and blue trim." },
		Gilded = { Name = "Gilded", Source = "Achievement", Achievement = "Collector1000", Order = 3, Tint = { 255, 200, 70 }, Description = "Gold-trimmed straps (Hoarder achievement)." },
		Royal = { Name = "Royal", Source = "Achievement", Achievement = "FirstLegendary", Order = 4, Tint = { 160, 60, 200 }, Description = "Velvet and gold (Legend achievement)." },
		Prismatic = { Name = "Prismatic", Source = "Achievement", Achievement = "BookComplete", Order = 5, Tint = { 120, 230, 255 }, Glow = true, Description = "Shimmering trim (Complete Collection)." },
		NeonVault = { Name = "Neon Vault", Source = "Robux", Order = 6, Tint = { 60, 255, 170 }, Glow = true, Description = "Glowing neon straps." },
		GoldenGlow = { Name = "Golden Glow", Source = "Robux", Order = 7, Tint = { 255, 210, 90 }, Glow = true, Description = "Your stack glows gold." },
	},
	Trail = {
		None = { Name = "None", Source = "Default", Order = 1, Description = "No trail." },
		Sparkle = { Name = "Sparkle", Source = "Tokens", Cost = 15, Order = 2, Color = { 255, 240, 200 }, Description = "A faint sparkle as you run." },
		GoldTrail = { Name = "Gold Trail", Source = "Robux", Order = 3, Color = { 255, 196, 60 }, Description = "A trail of gold dust." },
	},
	DepositFx = {
		Standard = { Name = "Standard", Source = "Default", Order = 1, Description = "Machine lights and a cash burst." },
		CoinBurst = { Name = "Coin Burst", Source = "Tokens", Cost = 12, Order = 2, Description = "Coins spray from the machine." },
		Confetti = { Name = "Confetti", Source = "Robux", Order = 3, Description = "Confetti on every deposit." },
	},
}

CosmeticConfig.KindOrder = { "Theme", "Trail", "DepositFx" }

return CosmeticConfig
