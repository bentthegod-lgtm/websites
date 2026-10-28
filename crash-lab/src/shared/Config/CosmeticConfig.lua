--[[
	CosmeticConfig - dummy designs, trails and launch effects. Cosmetic only: none of these
	change physics, scoring or rewards.

	Sources: Default (owned), Coins (buy in the Cosmetics tab), Achievement (unlocked by an
	achievement), Robux (ShopConfig product / pass).
]]

local CosmeticConfig = {}

CosmeticConfig.Skins = {
	Default = { Name = "Classic Dummy", Body = { 250, 214, 70 }, Accent = { 30, 30, 34 }, Source = "Default" },
	Safety = { Name = "Safety Orange", Body = { 255, 132, 40 }, Accent = { 245, 245, 245 }, Source = "Coins", Cost = 750 },
	Lab = { Name = "Lab Coat", Body = { 236, 240, 245 }, Accent = { 70, 140, 230 }, Source = "Coins", Cost = 2000 },
	Hazard = { Name = "Hazard Stripes", Body = { 250, 210, 40 }, Accent = { 20, 20, 20 }, Source = "Achievement", Achievement = "Destroy25" },
	Pinball = { Name = "Pinball Wizard", Body = { 120, 90, 230 }, Accent = { 255, 230, 90 }, Source = "Achievement", Achievement = "Impacts12" },
	Astro = { Name = "Astro Dummy", Body = { 240, 240, 240 }, Accent = { 230, 80, 60 }, Source = "Achievement", Achievement = "Dist400" },
	Gold = { Name = "Golden Dummy", Body = { 255, 200, 60 }, Accent = { 140, 90, 20 }, Source = "Achievement", Achievement = "Launch100", Material = "Metal" },
	Chrome = { Name = "Chrome Dummy", Body = { 205, 210, 220 }, Accent = { 60, 60, 70 }, Source = "Achievement", Achievement = "Certified", Material = "Metal" },
	Neon = { Name = "Neon Dummy", Body = { 60, 240, 200 }, Accent = { 20, 40, 60 }, Source = "Robux", Material = "Neon" },
}
CosmeticConfig.SkinOrder = { "Default", "Safety", "Lab", "Hazard", "Pinball", "Astro", "Gold", "Chrome", "Neon" }

CosmeticConfig.Trails = {
	None = { Name = "No trail", Source = "Default" },
	Smoke = { Name = "Smoke Trail", Color = { 200, 200, 200 }, Source = "Coins", Cost = 1200 },
	Hazard = { Name = "Hazard Trail", Color = { 255, 200, 40 }, Source = "Coins", Cost = 3500 },
	Rainbow = { Name = "Rainbow Trail", Rainbow = true, Source = "Robux" },
}
CosmeticConfig.TrailOrder = { "None", "Smoke", "Hazard", "Rainbow" }

CosmeticConfig.LaunchFx = {
	Standard = { Name = "Standard Puff", Source = "Default" },
	Confetti = { Name = "Confetti Burst", Source = "Coins", Cost = 2500 },
	Fireworks = { Name = "Fireworks Launch", Source = "Robux" },
}
CosmeticConfig.LaunchFxOrder = { "Standard", "Confetti", "Fireworks" }

CosmeticConfig.Kinds = {
	Skin = CosmeticConfig.Skins,
	Trail = CosmeticConfig.Trails,
	LaunchFx = CosmeticConfig.LaunchFx,
}

return CosmeticConfig
