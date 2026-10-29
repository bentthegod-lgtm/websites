--[[
	LootModels - every loot item, carried-stack piece and the overhead carry crate, built
	from parts (Roblox-native models; POLISH.md lists which to swap for Blender meshes).

	build(itemId, baseCFrame) -> Model. The model's bottom sits on baseCFrame (the spawn
	surface); its PrimaryPart "Hitbox" is an invisible box around it. Every part is anchored,
	non-colliding, non-touching and non-queryable: loot never blocks players or the camera.
	piece(category, themeId) -> Model sized to StackLayout.PieceSize (for carried stacks).
	crate(themeId) -> Model sized to StackLayout.CrateSize.
	Distinct silhouettes per item: loose bills vs banded stacks vs strapped bundles, bevelled
	bars vs bricks vs crates, cut gems vs clusters vs formations, and so on.
]]

local LootConfig = require(script.Parent.Config.LootConfig)
local CosmeticConfig = require(script.Parent.Config.CosmeticConfig)
local StackLayout = require(script.Parent.StackLayout)

local LootModels = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local UP = CFrame.Angles(0, 0, math.pi / 2) -- cylinders run along X; this stands them up

local C = {
	Bill = rgb(118, 164, 104),
	BillDark = rgb(78, 120, 72),
	BillLight = rgb(176, 206, 160),
	Band = rgb(236, 232, 214),
	BandGold = rgb(222, 176, 64),
	Gold = rgb(236, 184, 58),
	GoldDark = rgb(196, 146, 40),
	Platinum = rgb(214, 220, 228),
	PlatinumDark = rgb(164, 172, 184),
	Diamond = rgb(206, 236, 255),
	Emerald = rgb(40, 190, 104),
	EmeraldDark = rgb(20, 120, 64),
	Bronze = rgb(176, 124, 70),
	Stone = rgb(168, 160, 146),
	Velvet = rgb(120, 30, 46),
	VelvetBlue = rgb(34, 40, 80),
	Wood = rgb(124, 86, 52),
	Steel = rgb(70, 74, 82),
	SteelLight = rgb(120, 126, 136),
	Ruby = rgb(220, 40, 70),
	Sapphire = rgb(60, 110, 240),
	Black = rgb(22, 22, 26),
}
LootModels.Colors = C

-- Context: parts are added relative to the model's base frame.
local function kit(model, base, anchored, scale)
	scale = scale or 1
	local k = {}
	-- Offsets are scaled about the model's base, so a scaled model still sits on its surface.
	local function place(offset)
		if scale == 1 then
			return base * offset
		end
		return base * (CFrame.new(offset.Position * scale) * offset.Rotation)
	end
	function k.part(name, size, offset, color, material, shape, extra)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * scale
		p.Color = color
		p.Material = material or M.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.Anchored = anchored
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = size.Magnitude * scale > 1.2
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = place(offset)
		if extra then
			for key, v in pairs(extra) do
				p[key] = v
			end
		end
		p.Parent = model
		return p
	end
	function k.box(name, size, offset, color, material, extra)
		return k.part(name, size, offset, color, material, nil, extra)
	end
	function k.wedge(name, size, offset, color, material)
		local p = Instance.new("WedgePart")
		p.Name = name
		p.Size = size * scale
		p.Color = color
		p.Material = material or M.SmoothPlastic
		p.Anchored = anchored
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.CFrame = place(offset)
		p.Parent = model
		return p
	end
	-- Upright cylinder: height along Y.
	function k.cyl(name, height, diameter, offset, color, material, extra)
		return k.part(name, Vector3.new(height, diameter, diameter), offset * UP, color, material, Enum.PartType.Cylinder, extra)
	end
	-- Flat-lying cylinder along X (coins, rods).
	function k.rod(name, length, diameter, offset, color, material, extra)
		return k.part(name, Vector3.new(length, diameter, diameter), offset, color, material, Enum.PartType.Cylinder, extra)
	end
	function k.ball(name, d, offset, color, material, extra)
		return k.part(name, Vector3.new(d, d, d), offset, color, material, Enum.PartType.Ball, extra)
	end
	-- A cut gem: a cube balanced on a corner (reads as a faceted stone) with a bright core.
	function k.gem(name, s, offset, color, extra)
		local g = k.box(name, Vector3.new(s, s, s), offset * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), color, M.Glass, { Transparency = 0.18, Reflectance = 0.35 })
		if extra ~= false then
			k.box(name .. "Core", Vector3.new(s * 0.42, s * 0.42, s * 0.42), offset * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), color, M.Neon, { Transparency = 0.35 })
		end
		return g
	end
	-- An emerald cut: an octagonal prism (two boxes, one turned 45 degrees).
	function k.octo(name, w, h, d, offset, color)
		k.box(name, Vector3.new(w, h, d), offset, color, M.Glass, { Transparency = 0.15, Reflectance = 0.3 })
		k.box(name .. "B", Vector3.new(w * 0.78, h * 1.002, d * 0.78), offset * CFrame.Angles(0, math.rad(45), 0), color, M.Glass, { Transparency = 0.15, Reflectance = 0.3 })
		return k.box(name .. "Core", Vector3.new(w * 0.4, h * 0.5, d * 0.4), offset, color, M.Neon, { Transparency = 0.4 })
	end
	-- A bevelled bullion bar: wide base, narrower top, stamped plate.
	function k.bar(name, len, h, w, offset, color, dark)
		k.box(name, Vector3.new(len, h * 0.62, w), offset * CFrame.new(0, h * 0.31, 0), color, M.Metal, { Reflectance = 0.18 })
		k.box(name .. "Top", Vector3.new(len * 0.86, h * 0.4, w * 0.72), offset * CFrame.new(0, h * 0.8, 0), color, M.Metal, { Reflectance = 0.22 })
		return k.box(name .. "Stamp", Vector3.new(len * 0.34, 0.02, w * 0.36), offset * CFrame.new(0, h + 0.005, 0), dark, M.Metal)
	end
	-- A banded stack of banknotes.
	function k.notes(name, len, h, w, offset, bandColor)
		k.box(name, Vector3.new(len, h, w), offset * CFrame.new(0, h / 2, 0), C.Bill, M.Fabric)
		k.box(name .. "Top", Vector3.new(len * 0.98, 0.03, w * 0.98), offset * CFrame.new(0, h + 0.012, 0), C.BillLight, M.SmoothPlastic)
		k.box(name .. "Edge", Vector3.new(len * 1.002, h * 0.5, w * 1.002), offset * CFrame.new(0, h * 0.45, 0), C.BillDark, M.Fabric)
		return k.box(name .. "Band", Vector3.new(len * 0.18, h * 1.04, w * 1.04), offset * CFrame.new(0, h / 2, 0), bandColor or C.Band, M.SmoothPlastic)
	end
	return k
end

local function at(x, y, z)
	return CFrame.new(x, y, z)
end

local builders = {}

-- Cash ------------------------------------------------------------------------------------

function builders.Bill(k)
	for i, v in ipairs({ { 0, 0.03, 0, 0 }, { 0.18, 0.07, 0.1, 28 }, { -0.14, 0.11, -0.06, -22 } }) do
		k.box("Note" .. i, Vector3.new(1.25, 0.03, 0.56), at(v[1], v[2], v[3]) * CFrame.Angles(0, math.rad(v[4]), 0), if i == 2 then C.BillLight else C.Bill, M.Fabric)
	end
	k.box("Mark", Vector3.new(0.3, 0.035, 0.3), at(0.18, 0.08, 0.1) * CFrame.Angles(0, math.rad(28), 0), C.BillDark)
end

function builders.CashStack(k)
	k.notes("Stack", 1.2, 0.36, 0.56, at(0, 0, 0))
end

function builders.CashBundle(k)
	for i, p in ipairs({ { -0.32, -0.3 }, { 0.32, -0.3 }, { -0.32, 0.3 }, { 0.32, 0.3 } }) do
		k.notes("Stack" .. i, 0.6, 0.42, 0.56, at(p[1] * 1.95, 0, p[2]) * CFrame.Angles(0, math.rad(90), 0))
	end
	k.box("StrapX", Vector3.new(2.6, 0.46, 0.12), at(0, 0.23, 0), C.BandGold, M.Fabric)
	k.box("StrapZ", Vector3.new(0.12, 0.46, 1.28), at(0, 0.23, 0), C.BandGold, M.Fabric)
end

function builders.PremiumBundle(k)
	for layer = 0, 1 do
		for i = 0, 5 do
			local x, z = (i % 3 - 1) * 0.7, (i // 3 - 0.5) * 0.62
			k.notes("S" .. layer .. i, 0.66, 0.38, 0.58, at(x, layer * 0.39, z) * CFrame.Angles(0, math.rad(90), 0), C.BandGold)
		end
	end
	k.box("Wrap", Vector3.new(2.2, 0.86, 1.36), at(0, 0.43, 0), rgb(230, 240, 255), M.Glass, { Transparency = 0.75 })
	k.box("Seal", Vector3.new(0.5, 0.02, 0.5), at(0, 0.87, 0), C.BandGold, M.Metal)
end

function builders.GoldenBundle(k)
	builders.CashBundle(k)
	k.box("GoldWrap", Vector3.new(2.7, 0.5, 1.34), at(0, 0.25, 0), C.Gold, M.Glass, { Transparency = 0.6 })
	k.ball("Glow", 0.3, at(0, 0.6, 0), C.Gold, M.Neon)
end

-- Gold ------------------------------------------------------------------------------------

function builders.GoldBar(k)
	k.bar("Bar", 1.1, 0.34, 0.5, at(0, 0, 0), C.Gold, C.GoldDark)
end

function builders.GoldStack(k)
	local n = 0
	for layer, count in ipairs({ 3, 2, 1 }) do
		for i = 1, count do
			n += 1
			local x = (i - (count + 1) / 2) * 0.56
			k.bar("Bar" .. n, 1.0, 0.3, 0.5, at(x, (layer - 1) * 0.31, 0) * CFrame.Angles(0, math.rad(90), 0), C.Gold, C.GoldDark)
		end
	end
end

function builders.GoldBrick(k)
	k.bar("Brick", 2.2, 0.62, 1.0, at(0, 0, 0), C.Gold, C.GoldDark)
	k.box("Plate", Vector3.new(0.8, 0.3, 0.02), at(0, 0.24, -0.51), C.GoldDark, M.Metal)
end

function builders.GoldCrate(k)
	k.box("Floor", Vector3.new(2.2, 0.12, 1.5), at(0, 0.06, 0), C.Steel, M.DiamondPlate)
	for _, x in ipairs({ -1.05, 1.05 }) do
		k.box("Side", Vector3.new(0.1, 0.7, 1.5), at(x, 0.4, 0), C.Wood, M.WoodPlanks)
	end
	for _, z in ipairs({ -0.7, 0.7 }) do
		k.box("End", Vector3.new(2.2, 0.7, 0.1), at(0, 0.4, z), C.Wood, M.WoodPlanks)
	end
	for i = 0, 5 do
		local x, z = (i % 3 - 1) * 0.62, (i // 3 - 0.5) * 0.6
		k.bar("Bar" .. i, 0.58, 0.28, 0.5, at(x, 0.12 + (i % 2) * 0.28, z), C.Gold, C.GoldDark)
	end
	k.box("Band", Vector3.new(2.24, 0.12, 1.54), at(0, 0.62, 0), C.BandGold, M.Metal)
end

function builders.GiantGoldBar(k)
	k.bar("Giant", 3.4, 0.9, 1.4, at(0, 0, 0), C.Gold, C.GoldDark)
	k.ball("Glow", 0.4, at(0, 1.2, 0), C.Gold, M.Neon, { Transparency = 0.3 })
end

-- Diamonds --------------------------------------------------------------------------------

function builders.Diamond(k)
	k.cyl("Pad", 0.06, 0.8, at(0, 0.03, 0), C.VelvetBlue, M.Fabric)
	k.gem("Gem", 0.5, at(0, 0.5, 0), C.Diamond)
end

function builders.DiamondCluster(k)
	k.box("Rock", Vector3.new(0.9, 0.24, 0.7), at(0, 0.12, 0), rgb(90, 92, 100), M.Slate)
	k.gem("Gem1", 0.46, at(-0.18, 0.62, 0), C.Diamond)
	k.gem("Gem2", 0.34, at(0.26, 0.5, 0.12), C.Diamond, false)
	k.gem("Gem3", 0.28, at(0.05, 0.42, -0.24), C.Diamond, false)
end

function builders.LargeGem(k)
	k.cyl("Stand", 0.3, 0.7, at(0, 0.15, 0), C.SteelLight, M.Metal)
	k.cyl("Cushion", 0.12, 0.6, at(0, 0.36, 0), C.VelvetBlue, M.Fabric)
	k.gem("Gem", 0.8, at(0, 1.1, 0), C.Diamond)
end

function builders.DiamondFormation(k)
	k.box("Base", Vector3.new(1.8, 0.4, 1.4), at(0, 0.2, 0), rgb(70, 72, 82), M.Slate)
	local spikes = { { 0, 1.5, 0, 0, 0 }, { -0.5, 1.1, 0.2, -18, 10 }, { 0.5, 1.2, -0.2, 16, -12 }, { 0.2, 0.9, 0.45, 8, 22 }, { -0.3, 0.8, -0.4, -10, -20 } }
	for i, s in ipairs(spikes) do
		k.box("Crystal" .. i, Vector3.new(0.4, s[2], 0.4), at(s[1], 0.35 + s[2] / 2, s[3]) * CFrame.Angles(math.rad(s[5]), math.rad(45), math.rad(s[4])), C.Diamond, M.Glass, { Transparency = 0.2, Reflectance = 0.35 })
	end
	k.box("Core", Vector3.new(0.3, 1.0, 0.3), at(0, 0.9, 0), C.Diamond, M.Neon, { Transparency = 0.4 })
end

function builders.PerfectDiamond(k)
	k.cyl("Pedestal", 0.5, 1.2, at(0, 0.25, 0), C.SteelLight, M.Metal)
	k.cyl("Ring", 0.08, 1.3, at(0, 0.52, 0), C.Diamond, M.Neon)
	k.gem("Gem", 1.2, at(0, 1.6, 0), C.Diamond)
end

-- Emeralds --------------------------------------------------------------------------------

function builders.Emerald(k)
	k.cyl("Pad", 0.06, 0.8, at(0, 0.03, 0), C.Black, M.Fabric)
	k.octo("Gem", 0.6, 0.34, 0.44, at(0, 0.24, 0), C.Emerald)
end

function builders.EmeraldCluster(k)
	k.box("Rock", Vector3.new(0.9, 0.22, 0.7), at(0, 0.11, 0), rgb(60, 66, 62), M.Slate)
	k.octo("Gem1", 0.4, 0.62, 0.32, at(-0.18, 0.5, 0), C.Emerald)
	k.octo("Gem2", 0.32, 0.44, 0.26, at(0.22, 0.42, 0.1), C.Emerald)
	k.octo("Gem3", 0.26, 0.36, 0.22, at(0.06, 0.38, -0.22), C.EmeraldDark)
end

function builders.PremiumEmerald(k)
	k.box("Tray", Vector3.new(1.2, 0.14, 1.0), at(0, 0.07, 0), C.Gold, M.Metal)
	k.box("Lining", Vector3.new(1.06, 0.04, 0.86), at(0, 0.15, 0), C.Black, M.Fabric)
	k.octo("Gem", 0.84, 0.46, 0.62, at(0, 0.4, 0), C.Emerald)
	for _, x in ipairs({ -0.5, 0.5 }) do
		k.box("Prong", Vector3.new(0.06, 0.4, 0.06), at(x * 0.86, 0.36, 0), C.Gold, M.Metal)
	end
end

function builders.GrandEmerald(k)
	k.box("Base", Vector3.new(1.5, 0.3, 1.5), at(0, 0.15, 0), C.Steel, M.Metal)
	k.octo("Gem", 0.9, 1.9, 0.9, at(0, 1.25, 0), C.Emerald)
	k.box("Cap", Vector3.new(0.6, 0.3, 0.6), at(0, 2.35, 0) * CFrame.Angles(0, math.rad(22), 0), C.Emerald, M.Glass, { Transparency = 0.15 })
end

function builders.RoyalEmerald(k)
	builders.PremiumEmerald(k)
	k.cyl("Halo", 0.06, 1.4, at(0, 0.9, 0), C.Gold, M.Neon, { Transparency = 0.2 })
end

-- Platinum --------------------------------------------------------------------------------

function builders.PlatinumBar(k)
	k.bar("Bar", 1.1, 0.32, 0.48, at(0, 0, 0), C.Platinum, C.PlatinumDark)
end

function builders.MetalStack(k)
	for layer = 0, 1 do
		for i = 0, 1 do
			if layer == 0 then
				k.bar("Bar" .. layer .. i, 1.1, 0.3, 0.48, at(0, 0, (i - 0.5) * 0.52), C.Platinum, C.PlatinumDark)
			else
				k.bar("Bar" .. layer .. i, 1.1, 0.3, 0.48, at((i - 0.5) * 0.52, 0.31, 0) * CFrame.Angles(0, math.rad(90), 0), C.Platinum, C.PlatinumDark)
			end
		end
	end
end

function builders.AlloyCanister(k)
	k.cyl("Body", 1.6, 0.9, at(0, 0.8, 0), C.SteelLight, M.Metal)
	k.cyl("CapTop", 0.16, 1.0, at(0, 1.62, 0), C.Steel, M.DiamondPlate)
	k.cyl("CapBottom", 0.16, 1.0, at(0, 0.08, 0), C.Steel, M.DiamondPlate)
	k.cyl("Band", 0.16, 0.94, at(0, 0.9, 0), rgb(120, 200, 255), M.Neon)
	k.box("Handle", Vector3.new(0.5, 0.08, 0.08), at(0, 1.8, 0), C.Steel, M.Metal)
	k.box("Label", Vector3.new(0.4, 0.3, 0.02), at(0, 1.2, -0.46), rgb(240, 200, 40))
end

function builders.PlatinumCase(k)
	k.box("Case", Vector3.new(2.0, 0.5, 1.3), at(0, 0.25, 0), C.Steel, M.DiamondPlate)
	k.box("Lining", Vector3.new(1.84, 0.04, 1.14), at(0, 0.51, 0), C.VelvetBlue, M.Fabric)
	for i = 0, 3 do
		k.bar("Bar" .. i, 0.4, 0.2, 0.9, at((i - 1.5) * 0.44, 0.52, 0), C.Platinum, C.PlatinumDark)
	end
	k.box("Lid", Vector3.new(2.0, 1.2, 0.08), at(0, 1.1, 0.68) * CFrame.Angles(math.rad(-18), 0, 0), C.Steel, M.DiamondPlate)
	k.box("Latch", Vector3.new(0.3, 0.16, 0.06), at(0, 0.32, -0.66), C.Platinum, M.Metal)
end

function builders.PlatinumCore(k)
	builders.AlloyCanister(k)
	k.ball("Core", 0.7, at(0, 2.3, 0), rgb(160, 220, 255), M.Neon, { Transparency = 0.15 })
end

-- Artifacts -------------------------------------------------------------------------------

function builders.AncientCoin(k)
	for i, v in ipairs({ { 0, 0, 0 }, { 0.12, 0.08, 0.1 }, { -0.08, 0.16, -0.05 } }) do
		k.cyl("Coin" .. i, 0.07, 0.62, at(v[1], 0.04 + v[2], v[3]), rgb(206, 156, 70), M.Metal, { Reflectance = 0.15 })
	end
	k.cyl("Stamp", 0.01, 0.3, at(-0.08, 0.235, -0.05), rgb(150, 104, 40), M.Metal)
end

function builders.Relic(k)
	k.cyl("Foot", 0.14, 0.5, at(0, 0.07, 0), C.Bronze, M.Metal)
	k.ball("Body", 0.8, at(0, 0.55, 0), C.Bronze, M.Metal, { Reflectance = 0.1 })
	k.cyl("Neck", 0.3, 0.3, at(0, 1.02, 0), C.Bronze, M.Metal)
	k.cyl("Rim", 0.08, 0.46, at(0, 1.2, 0), rgb(214, 170, 90), M.Metal)
	k.cyl("Band", 0.08, 0.82, at(0, 0.6, 0), rgb(60, 140, 160), M.Metal)
end

function builders.Statuette(k)
	k.box("Plinth", Vector3.new(0.8, 0.3, 0.8), at(0, 0.15, 0), C.Stone, M.Marble)
	k.box("Body", Vector3.new(0.44, 0.9, 0.32), at(0, 0.75, 0), rgb(196, 156, 80), M.Metal)
	k.ball("Head", 0.36, at(0, 1.36, 0), rgb(196, 156, 80), M.Metal)
	k.box("Headdress", Vector3.new(0.5, 0.2, 0.4), at(0, 1.5, 0.02), rgb(60, 130, 170), M.Metal)
	for _, x in ipairs({ -0.27, 0.27 }) do
		k.box("Arm", Vector3.new(0.1, 0.6, 0.12), at(x, 0.8, 0), rgb(196, 156, 80), M.Metal)
	end
end

function builders.Sarcophagus(k)
	k.box("Base", Vector3.new(0.9, 0.5, 2.0), at(0, 0.25, 0), rgb(150, 112, 60), M.Sandstone)
	k.box("Lid", Vector3.new(0.84, 0.24, 1.94), at(0, 0.62, 0), rgb(206, 160, 70), M.Metal, { Reflectance = 0.1 })
	k.box("Face", Vector3.new(0.5, 0.06, 0.5), at(0, 0.77, -0.62), rgb(236, 196, 90), M.Metal)
	for i = -2, 2 do
		k.box("Stripe" .. i, Vector3.new(0.86, 0.02, 0.06), at(0, 0.745, i * 0.32 + 0.2), rgb(40, 110, 160), M.Metal)
	end
end

function builders.AncientIdol(k)
	k.box("Plinth", Vector3.new(1.4, 0.4, 1.4), at(0, 0.2, 0), C.Stone, M.Marble)
	k.box("Body", Vector3.new(0.8, 1.6, 0.6), at(0, 1.2, 0), C.Gold, M.Metal, { Reflectance = 0.2 })
	k.ball("Head", 0.7, at(0, 2.3, 0), C.Gold, M.Metal, { Reflectance = 0.2 })
	for _, x in ipairs({ -0.15, 0.15 }) do
		k.ball("Eye", 0.14, at(x, 2.36, -0.3), C.Ruby, M.Neon)
	end
end

-- Legendary -------------------------------------------------------------------------------

function builders.Chalice(k)
	k.cyl("Foot", 0.08, 0.6, at(0, 0.04, 0), C.Gold, M.Metal)
	k.cyl("Stem", 0.5, 0.14, at(0, 0.33, 0), C.Gold, M.Metal)
	k.ball("Knot", 0.24, at(0, 0.4, 0), C.Gold, M.Metal)
	k.cyl("Cup", 0.46, 0.56, at(0, 0.82, 0), C.Gold, M.Metal, { Reflectance = 0.2 })
	k.ball("Bowl", 0.56, at(0, 0.62, 0), C.Gold, M.Metal, { Reflectance = 0.2 })
	for i = 0, 2 do
		k.ball("Jewel" .. i, 0.12, at(math.cos(i * 2.09) * 0.29, 0.82, math.sin(i * 2.09) * 0.29), if i == 1 then C.Sapphire else C.Ruby, M.Glass)
	end
end

function builders.Crown(k)
	k.ball("Cap", 0.9, at(0, 0.45, 0), C.Velvet, M.Fabric)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		k.box("Band" .. i, Vector3.new(0.34, 0.3, 0.08), at(math.cos(a) * 0.5, 0.2, math.sin(a) * 0.5) * CFrame.Angles(0, -a + math.pi / 2, 0), C.Gold, M.Metal, { Reflectance = 0.2 })
		if i % 2 == 0 then
			k.wedge("Spike" .. i, Vector3.new(0.1, 0.36, 0.2), at(math.cos(a) * 0.52, 0.53, math.sin(a) * 0.52) * CFrame.Angles(0, -a + math.pi / 2, 0), C.Gold, M.Metal)
			k.ball("Gem" .. i, 0.12, at(math.cos(a) * 0.55, 0.2, math.sin(a) * 0.55), if i % 4 == 0 then C.Ruby else C.Sapphire, M.Glass)
		end
	end
	k.ball("Orb", 0.2, at(0, 0.98, 0), C.Gold, M.Metal)
end

function builders.Scepter(k)
	k.box("Cushion", Vector3.new(1.9, 0.2, 0.8), at(0, 0.1, 0), C.Velvet, M.Fabric)
	k.rod("Rod", 1.8, 0.14, at(0, 0.3, 0), C.Gold, M.Metal, { Reflectance = 0.2 })
	k.ball("Head", 0.36, at(1.0, 0.3, 0), C.Sapphire, M.Glass, { Reflectance = 0.3 })
	for _, x in ipairs({ -0.5, 0, 0.6 }) do
		k.rod("Ring", 0.08, 0.22, at(x, 0.3, 0), C.Gold, M.Metal)
	end
	k.ball("Pommel", 0.2, at(-0.92, 0.3, 0), C.Gold, M.Metal)
end

function builders.LegendChest(k)
	k.box("Box", Vector3.new(2.0, 0.9, 1.3), at(0, 0.45, 0), C.Wood, M.WoodPlanks)
	k.rod("Lid", 2.0, 1.3, at(0, 0.9, 0), C.Wood, M.WoodPlanks)
	for _, x in ipairs({ -0.85, 0, 0.85 }) do
		k.box("Band", Vector3.new(0.14, 0.92, 1.34), at(x, 0.46, 0), C.Gold, M.Metal)
		k.rod("LidBand", 0.14, 1.34, at(x, 0.9, 0), C.Gold, M.Metal)
	end
	k.box("Lock", Vector3.new(0.3, 0.36, 0.08), at(0, 0.75, -0.68), C.Gold, M.Metal)
	k.ball("Gem", 0.18, at(0, 1.3, -0.4), C.Ruby, M.Neon)
end

function builders.TreasureHoard(k)
	builders.LegendChest(k)
	for i = 0, 11 do
		local a = i * 0.9
		k.cyl("Coin" .. i, 0.06, 0.34, at(math.cos(a) * (0.7 + (i % 3) * 0.22), 0.03 + (i % 2) * 0.05, math.sin(a) * (0.9 + (i % 3) * 0.2)), C.Gold, M.Metal)
	end
	k.ball("Glow", 0.5, at(0, 1.65, 0), C.Gold, M.Neon, { Transparency = 0.3 })
end

-- Build -----------------------------------------------------------------------------------

local function bounds(model, base)
	local minV, maxV
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			local local0 = base:PointToObjectSpace(p.CFrame.Position)
			local half = p.Size.Magnitude / 2 * 0.7
			local lo = local0 - Vector3.new(half, half, half)
			local hi = local0 + Vector3.new(half, half, half)
			minV = if minV then Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z)) else lo
			maxV = if maxV then Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z)) else hi
		end
	end
	return minV, maxV
end

-- scale (optional): display copies on landmarks are built larger.
function LootModels.build(itemId, base, scale)
	local def = LootConfig.ById[itemId]
	assert(def, "unknown loot " .. tostring(itemId))
	base = base or CFrame.new()
	local model = Instance.new("Model")
	model.Name = itemId
	local builder = builders[itemId]
	assert(builder, "no model for " .. itemId)
	builder(kit(model, base, true, scale))
	local minV, maxV = bounds(model, base)
	local height = math.max(0.3, maxV.Y)
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(math.max(0.6, maxV.X - minV.X), height, math.max(0.6, maxV.Z - minV.Z))
	hitbox.CFrame = base * CFrame.new((maxV.X + minV.X) / 2, height / 2, (maxV.Z + minV.Z) / 2)
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = false
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	-- Only the rarest loot carries a light (a small one); Epic and up get a sparkle emitter.
	local rank = LootConfig.rank(def)
	if rank >= 5 then
		local light = Instance.new("PointLight")
		light.Range = 8
		light.Brightness = 1.2
		local c = LootConfig.Rarities[def.Rarity].Color
		light.Color = rgb(c[1], c[2], c[3])
		light.Shadows = false
		light.Parent = hitbox
	end
	if rank >= 4 then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "Sparkle"
		sparkle.Rate = if rank >= 5 then 6 else 2.5
		sparkle.Lifetime = NumberRange.new(0.6, 1.1)
		sparkle.Speed = NumberRange.new(0.2, 0.6)
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0) })
		sparkle.LightEmission = 1
		local c = LootConfig.Rarities[def.Rarity].Color
		sparkle.Color = ColorSequence.new(rgb(c[1], c[2], c[3]))
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Parent = hitbox
	end
	model:SetAttribute("Item", itemId)
	return model
end

function LootModels.hasModel(itemId)
	return builders[itemId] ~= nil
end

-- Carried-stack pieces --------------------------------------------------------------------

local function themeOf(themeId)
	return CosmeticConfig.Kinds.Theme[themeId or "Classic"] or CosmeticConfig.Kinds.Theme.Classic
end

local function strapColor(theme, default)
	if theme.Tint then
		return rgb(theme.Tint[1], theme.Tint[2], theme.Tint[3])
	end
	return default
end

local pieceBuilders = {}
local P = StackLayout.PieceSize

function pieceBuilders.Cash(k, theme)
	k.notes("Notes", P.X, P.Y, P.Z, at(0, -P.Y / 2, 0), strapColor(theme, C.Band))
end

function pieceBuilders.Gold(k, theme)
	k.bar("Bar", P.X, P.Y, P.Z, at(0, -P.Y / 2, 0), C.Gold, strapColor(theme, C.GoldDark))
end

function pieceBuilders.Platinum(k, theme)
	k.bar("Bar", P.X, P.Y, P.Z, at(0, -P.Y / 2, 0), C.Platinum, strapColor(theme, C.PlatinumDark))
end

local function tray(k, theme, liner)
	k.box("Tray", Vector3.new(P.X, P.Y * 0.4, P.Z), at(0, -P.Y * 0.3, 0), strapColor(theme, C.Steel), M.Metal)
	k.box("Liner", Vector3.new(P.X * 0.9, 0.03, P.Z * 0.86), at(0, -P.Y * 0.08, 0), liner, M.Fabric)
	k.box("Lid", Vector3.new(P.X, P.Y * 0.56, P.Z), at(0, P.Y * 0.2, 0), rgb(220, 236, 255), M.Glass, { Transparency = 0.72 })
end

function pieceBuilders.Diamond(k, theme)
	tray(k, theme, C.VelvetBlue)
	k.gem("GemA", 0.2, at(-0.24, 0.04, 0), C.Diamond, false)
	k.gem("GemB", 0.2, at(0.24, 0.04, 0), C.Diamond, false)
end

function pieceBuilders.Emerald(k, theme)
	tray(k, theme, C.Black)
	k.octo("GemA", 0.3, 0.16, 0.24, at(-0.24, 0.0, 0), C.Emerald)
	k.octo("GemB", 0.3, 0.16, 0.24, at(0.24, 0.0, 0), C.Emerald)
end

function pieceBuilders.Artifact(k, theme)
	k.box("Crate", Vector3.new(P.X, P.Y, P.Z), at(0, 0, 0), C.Wood, M.WoodPlanks)
	k.box("Strap", Vector3.new(0.12, P.Y * 1.04, P.Z * 1.04), at(0, 0, 0), strapColor(theme, C.Steel), M.Metal)
	k.cyl("Relic", 0.2, 0.3, at(0.28, P.Y / 2 + 0.1, 0), C.Bronze, M.Metal)
end

function pieceBuilders.Legendary(k, theme)
	k.box("Chest", Vector3.new(P.X, P.Y, P.Z), at(0, 0, 0), C.Velvet, M.Fabric)
	k.box("Trim", Vector3.new(P.X * 1.02, 0.08, P.Z * 1.02), at(0, P.Y * 0.32, 0), strapColor(theme, C.Gold), M.Metal)
	k.ball("Gem", 0.16, at(0, P.Y * 0.32, -P.Z / 2), C.Ruby, M.Glass)
end

local function finishPiece(model, theme)
	if theme.Glow then
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and (p.Name:find("Band") or p.Name:find("Stamp") or p.Name:find("Trim") or p.Name:find("Strap") or p.Name == "Tray") then
				p.Material = M.Neon
			end
		end
	end
	return model
end

-- A carried-stack piece centred on `base` (piece size StackLayout.PieceSize).
function LootModels.piece(category, themeId, base, anchored, scale)
	local theme = themeOf(themeId)
	local model = Instance.new("Model")
	model.Name = "Piece_" .. category
	local builder = pieceBuilders[category] or pieceBuilders.Cash
	builder(kit(model, base or CFrame.new(), anchored ~= false, scale), theme)
	return finishPiece(model, theme)
end

-- The overhead carry crate for very large stacks (StackLayout "Crate" mode).
function LootModels.crate(themeId, base, anchored)
	local theme = themeOf(themeId)
	local model = Instance.new("Model")
	model.Name = "CarryCrate"
	local k = kit(model, base or CFrame.new(), anchored ~= false)
	local S = StackLayout.CrateSize
	k.box("Body", Vector3.new(S.X, S.Y, S.Z), at(0, 0, 0), C.Steel, M.DiamondPlate)
	for _, x in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1, 1 }) do
			k.box("Post", Vector3.new(0.18, S.Y + 0.04, 0.18), at(x * S.X / 2, 0, z * S.Z / 2), C.SteelLight, M.Metal)
		end
	end
	for _, x in ipairs({ -S.X * 0.3, S.X * 0.3 }) do
		k.box("Strap", Vector3.new(0.22, S.Y + 0.06, S.Z + 0.06), at(x, 0, 0), strapColor(theme, rgb(230, 180, 40)), M.Fabric)
	end
	k.box("Stencil", Vector3.new(S.X * 0.4, S.Y * 0.36, 0.02), at(0, 0, -S.Z / 2 - 0.02), rgb(240, 200, 40), M.SmoothPlastic)
	return finishPiece(model, theme)
end

return LootModels
