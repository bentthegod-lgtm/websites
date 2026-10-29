--[[
	LightingPresets - the look of each depth. The server applies the Cash Vault preset; each
	client switches preset by the depth its character is on (LightingController), so players
	on different floors each see their own floor's lighting.

	Underground: no sun or sky is relied on (ClockTime night, OutdoorAmbient low), the rooms
	are lit by Ambient plus the fixtures VaultBuilder places. Ambient stays high enough that
	loot is always readable; deeper floors get more contrast, not darkness.
	Bloom is restrained (high threshold) so only neon trims and gems glow.
]]

local LightingPresets = {}

local function preset(ambient, brightness, top, exposure, cc, bloom)
	return {
		Lighting = {
			Ambient = Color3.fromRGB(ambient[1], ambient[2], ambient[3]),
			OutdoorAmbient = Color3.fromRGB(math.floor(ambient[1] * 0.6), math.floor(ambient[2] * 0.6), math.floor(ambient[3] * 0.6)),
			Brightness = brightness,
			ColorShift_Top = Color3.fromRGB(top[1], top[2], top[3]),
			ClockTime = 0,
			ExposureCompensation = exposure,
			FogColor = Color3.fromRGB(math.floor(ambient[1] * 0.4), math.floor(ambient[2] * 0.4), math.floor(ambient[3] * 0.4)),
			FogStart = 160,
			FogEnd = 520,
			GlobalShadows = true,
		},
		ColorCorrection = { Brightness = cc[1], Contrast = cc[2], Saturation = cc[3], TintColor = Color3.fromRGB(cc[4][1], cc[4][2], cc[4][3]) },
		Bloom = { Intensity = bloom[1], Size = 22, Threshold = bloom[2] },
	}
end

LightingPresets.CashVault = preset({ 128, 126, 120 }, 1.4, { 255, 244, 224 }, 0.25, { 0.02, 0.08, -0.05, { 255, 250, 240 } }, { 0.35, 1.7 })
LightingPresets.GoldReserve = preset({ 132, 112, 84 }, 1.3, { 255, 214, 150 }, 0.2, { 0.02, 0.1, 0.02, { 255, 238, 214 } }, { 0.45, 1.55 })
LightingPresets.DiamondChamber = preset({ 104, 120, 142 }, 1.3, { 214, 236, 255 }, 0.2, { 0.02, 0.12, 0, { 238, 246, 255 } }, { 0.55, 1.45 })
LightingPresets.EmeraldReserve = preset({ 86, 118, 100 }, 1.2, { 196, 255, 220 }, 0.25, { 0.03, 0.12, 0.05, { 236, 255, 242 } }, { 0.5, 1.5 })
LightingPresets.PlatinumReserve = preset({ 118, 124, 138 }, 1.4, { 226, 238, 255 }, 0.2, { 0.02, 0.14, -0.12, { 236, 242, 255 } }, { 0.35, 1.7 })
LightingPresets.ArtifactChamber = preset({ 122, 104, 84 }, 1.25, { 255, 222, 180 }, 0.2, { 0.02, 0.12, 0.02, { 255, 242, 226 } }, { 0.45, 1.55 })
LightingPresets.LegendaryReserve = preset({ 104, 88, 104 }, 1.3, { 255, 226, 170 }, 0.3, { 0.03, 0.16, 0.08, { 255, 240, 224 } }, { 0.6, 1.4 })

function LightingPresets.apply(lighting, p)
	for k, v in pairs(p.Lighting) do
		lighting[k] = v
	end
	local cc = lighting:FindFirstChild("Vault_CC") or Instance.new("ColorCorrectionEffect")
	cc.Name = "Vault_CC"
	for k, v in pairs(p.ColorCorrection) do
		cc[k] = v
	end
	cc.Parent = lighting
	local bloom = lighting:FindFirstChild("Vault_Bloom") or Instance.new("BloomEffect")
	bloom.Name = "Vault_Bloom"
	for k, v in pairs(p.Bloom) do
		bloom[k] = v
	end
	bloom.Parent = lighting
end

return LightingPresets
