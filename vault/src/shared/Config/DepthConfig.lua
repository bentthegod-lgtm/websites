--[[
	DepthConfig - the seven floors of the vault, top to bottom.

	Unlocking depth d needs depth d-1 unlocked plus the cash (and, deeper down, Vault Token)
	price. Every unlocked floor stays open for good (until a rebirth, which resets depths).
	Every pool is FILLED with pickups (one per fill slot, ~1,700 per depth); a collected
	slot refills RefillDelay seconds later, so the pool never looks emptied. A depth's fill
	only exists while someone is on (or heading to) it (LootService).

	Palette colours are used by VaultBuilder for walls, floors, trims and lights; Ambient
	names the sound profile in AudioAssets.Ambience; Lighting names a LightingPresets entry.
]]

local DepthConfig = {}

DepthConfig.List = {
	{
		Depth = 1,
		Code = "B1",
		Name = "Cash Vault",
		Tagline = "Loose bills, cash stacks and banded bundles.",
		UnlockCash = 0,
		UnlockTokens = 0,
		RefillDelay = 4, -- seconds before a collected slot refills
		Lighting = "CashVault",
		Ambient = "CashVault",
		Palette = { Wall = { 146, 146, 142 }, Floor = { 96, 98, 102 }, Trim = { 70, 72, 78 }, Accent = { 214, 176, 82 }, Light = { 255, 244, 224 }, Glow = { 120, 220, 130 } },
	},
	{
		Depth = 2,
		Code = "B2",
		Name = "Gold Reserve",
		Tagline = "Bullion bars, stacks and heavy bricks.",
		UnlockCash = 5000,
		UnlockTokens = 0,
		RefillDelay = 4.5, -- seconds before a collected slot refills
		Lighting = "GoldReserve",
		Ambient = "GoldReserve",
		Palette = { Wall = { 112, 104, 92 }, Floor = { 74, 70, 64 }, Trim = { 58, 52, 44 }, Accent = { 236, 184, 58 }, Light = { 255, 214, 150 }, Glow = { 255, 196, 80 } },
	},
	{
		Depth = 3,
		Code = "B3",
		Name = "Diamond Chamber",
		Tagline = "Cut diamonds, clusters and rare formations.",
		UnlockCash = 120000,
		UnlockTokens = 0,
		RefillDelay = 5, -- seconds before a collected slot refills
		Lighting = "DiamondChamber",
		Ambient = "DiamondChamber",
		Palette = { Wall = { 70, 80, 96 }, Floor = { 46, 52, 62 }, Trim = { 34, 40, 50 }, Accent = { 150, 210, 255 }, Light = { 214, 236, 255 }, Glow = { 140, 210, 255 } },
	},
	{
		Depth = 4,
		Code = "B4",
		Name = "Emerald Reserve",
		Tagline = "Emerald-cut stones in sealed display towers.",
		UnlockCash = 2500000,
		UnlockTokens = 10,
		RefillDelay = 5.5, -- seconds before a collected slot refills
		Lighting = "EmeraldReserve",
		Ambient = "EmeraldReserve",
		Palette = { Wall = { 44, 54, 50 }, Floor = { 30, 36, 34 }, Trim = { 22, 26, 24 }, Accent = { 40, 200, 110 }, Light = { 196, 255, 220 }, Glow = { 60, 230, 130 } },
	},
	{
		Depth = 5,
		Code = "B5",
		Name = "Platinum Reserve",
		Tagline = "Platinum bars, alloy canisters and heavy machinery.",
		UnlockCash = 60000000,
		UnlockTokens = 25,
		RefillDelay = 6, -- seconds before a collected slot refills
		Lighting = "PlatinumReserve",
		Ambient = "PlatinumReserve",
		Palette = { Wall = { 120, 128, 140 }, Floor = { 70, 76, 86 }, Trim = { 44, 48, 56 }, Accent = { 170, 210, 255 }, Light = { 226, 238, 255 }, Glow = { 150, 200, 255 } },
	},
	{
		Depth = 6,
		Code = "B6",
		Name = "Artifact Chamber",
		Tagline = "Ancient coins, relics and staged treasures.",
		UnlockCash = 1500000000,
		UnlockTokens = 60,
		RefillDelay = 6.5, -- seconds before a collected slot refills
		Lighting = "ArtifactChamber",
		Ambient = "ArtifactChamber",
		Palette = { Wall = { 128, 108, 86 }, Floor = { 84, 70, 56 }, Trim = { 60, 48, 38 }, Accent = { 214, 150, 80 }, Light = { 255, 222, 180 }, Glow = { 120, 230, 255 } },
	},
	{
		Depth = 7,
		Code = "B7",
		Name = "Legendary Reserve",
		Tagline = "The deepest reserve. Crowns, scepters and legendary chests.",
		UnlockCash = 40000000000,
		UnlockTokens = 150,
		RefillDelay = 7, -- seconds before a collected slot refills
		Lighting = "LegendaryReserve",
		Ambient = "LegendaryReserve",
		Palette = { Wall = { 40, 34, 46 }, Floor = { 28, 24, 32 }, Trim = { 20, 16, 24 }, Accent = { 255, 196, 60 }, Light = { 255, 226, 170 }, Glow = { 255, 190, 60 } },
	},
}

DepthConfig.Count = #DepthConfig.List

-- The next vault complex: a milestone, not part of this release. Shown as "coming soon".
DepthConfig.NextComplex = {
	Name = "Ancient Vault",
	Tagline = "A second complex of relic chambers far below the first.",
	RequiresDepth = 7,
	ComingSoon = true,
}

function DepthConfig.get(depth)
	return DepthConfig.List[depth]
end

-- The depth whose band of the world contains world height y (floors are DepthSpacing apart).
function DepthConfig.depthAtY(y, spacing)
	local d = math.floor((-(y or 0) + spacing * 0.5) / spacing) + 1
	return math.clamp(d, 1, DepthConfig.Count)
end

return DepthConfig
