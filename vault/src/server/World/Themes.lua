--[[
	Themes - what makes each depth its own place: the landmark, storage, security and
	decoration, plus extra loot spawn points (shelves, tables, plinths) and keep-out boxes
	for furniture. VaultBuilder builds the shared shell; Themes.build(ctx) dresses it.

	  B1 Cash Vault       cash racks, counting stations, a safe-deposit wall,
	                      landmark: a caged pyramid of banded cash on a gold-trimmed dais
	  B2 Gold Reserve     heavy reinforced racks, bullion cages, a forklift,
	                      landmark: an overhead gantry crane lifting a pallet of gold
	  B3 Diamond Chamber  reinforced glass display cases, velvet plinths, laser fences,
	                      landmark: a giant cut crystal on a ringed pedestal under blue light
	  B4 Emerald Reserve  glass display towers, sealed premium containers, a scanner arch,
	                      landmark: an emerald obelisk on a black-stone base
	  B5 Platinum Reserve tall industrial racks, a hydraulic press, a conveyor, blast plates,
	                      landmark: a platinum refinery vessel with pipes and gauges
	  B6 Artifact Chamber stone arches and columns, mosaic floor, containment pods,
	                      landmark: a sarcophagus in a containment field under an arch
	  B7 Legendary Reserve an imposing gold arch with open double vault doors, a red carpet,
	                      gold columns, landmark: a tiered treasure dais with light shafts
	Ambient sound emitters (invisible parts tagged with an AmbientSound attribute) are
	placed by each theme; the client attaches the 3D sounds.
]]

local Props = require(script.Parent.Props)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Vault")
local LootModels = require(Shared.LootModels)

local Themes = {}

local GameConfig = require(Shared.Config.GameConfig)
local W2 = GameConfig.RoomWidth / 2 -- 70
local BACK = GameConfig.RoomBack -- 60
local RACK_X = W2 - 4 -- racks stand against the side walls
local RACK_ZS = { -24, -4, 16, 36, 52 }

local M = Enum.Material
local rgb = Color3.fromRGB
local C = Props.Colors
local X, Z = Vector3.xAxis, Vector3.zAxis
local UP = CFrame.Angles(0, 0, math.pi / 2)

local function facing(pos, dir)
	return CFrame.lookAt(pos, pos + dir)
end

local STYLES = {
	{ WallMaterial = M.Concrete, FloorMaterial = M.Concrete, LightBrightness = 2.4 },
	{ WallMaterial = M.Concrete, FloorMaterial = M.DiamondPlate, LightBrightness = 2.3, PipeColor = rgb(150, 110, 60) },
	{ WallMaterial = M.Marble, FloorMaterial = M.Marble, FloorReflect = 0.12, LightBrightness = 2.3 },
	{ WallMaterial = M.Slate, FloorMaterial = M.Slate, LightBrightness = 2.2 },
	{ WallMaterial = M.Metal, FloorMaterial = M.DiamondPlate, LightBrightness = 2.5, PipeColor = rgb(170, 200, 230) },
	{ WallMaterial = M.Sandstone, FloorMaterial = M.Sandstone, LightBrightness = 2.2, PipeColor = rgb(140, 110, 70) },
	{ WallMaterial = M.Marble, FloorMaterial = M.Marble, FloorReflect = 0.15, LightBrightness = 2.3, PipeColor = rgb(200, 160, 60) },
}

function Themes.style(depth)
	return STYLES[depth] or STYLES[1]
end

-- Helpers -----------------------------------------------------------------------------------

local function point(ctx, cf, size, kind)
	table.insert(ctx.extraPoints, { cframe = cf, size = size, kind = kind })
end

local function reserve(ctx, x0, x1, z0, z1)
	table.insert(ctx.keepOut, { x0, x1, z0, z1 })
end

local function emitter(ctx, pos, sound)
	local p = ctx.b.deco({ Name = "AmbientEmitter", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos), Transparency = 1 })
	p:SetAttribute("AmbientSound", sound)
	ctx.ambience = ctx.ambience or {}
	table.insert(ctx.ambience, p)
end

local function light(part, kind, color, brightness, range, shadows)
	local l = Instance.new(kind or "PointLight")
	l.Color = color
	l.Brightness = brightness or 1
	l.Range = range or 14
	l.Shadows = shadows == true
	if l:IsA("SpotLight") then
		l.Face = Enum.NormalId.Bottom
		l.Angle = 70
	end
	l.Parent = part
	return l
end

-- Static decorative loot (behind glass / in cages / on the landmark): no hitbox, no
-- sparkle, no light - never mistaken for a pickup, never adds a light.
local function decoLoot(ctx, itemId, cf, scale)
	local model = LootModels.build(itemId, cf, scale)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Light") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	if model.PrimaryPart then
		model.PrimaryPart:Destroy()
	end
	model.Name = "Display_" .. itemId
	model.Parent = ctx.folder
	ctx.b.count += #model:GetChildren()
	return model
end

-- Racks along both side walls, facing the centre. Lower shelves are loot points, the top
-- shelf holds sealed storage boxes.
local function sideRacks(ctx, zs, opts)
	local b, y0 = ctx.b, ctx.y0
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs(zs) do
			local cf = facing(Vector3.new(side * RACK_X, y0, z), -side * X)
			local tops = Props.rack(b, cf, opts.width or 14, 3.2, 3, opts.height or 7.6, opts.color, opts.heavy)
			for i, top in ipairs(tops) do
				if i < #tops then
					for _, dx in ipairs({ -(opts.width or 14) / 4, (opts.width or 14) / 4 }) do
						point(ctx, top * CFrame.new(dx, 0, -0.2), "S", "Shelf")
					end
				else
					for _, dx in ipairs({ -3.6, 0, 3.6 }) do
						local box = b.deco({ Name = "SealedBox", Size = Vector3.new(3, 1.6, 2.4), CFrame = top * CFrame.new(dx, 0.8, 0), Color = opts.boxColor or rgb(96, 100, 108), Material = M.Metal })
						if dx == 0 then
							Props.text(box, Enum.NormalId.Front, opts.label or "SEALED", { PPS = 30, Color = C.Hazard })
						end
					end
				end
			end
			if opts.decor then
				opts.decor(cf, tops)
			end
		end
		-- Half-height partitions between the racks make storage bays along the wall.
		for i = 1, #zs - 1 do
			local z = (zs[i] + zs[i + 1]) / 2
			b.part({ Name = "BayWall", Size = Vector3.new(12, 4.6, 0.8), CFrame = CFrame.new(side * (W2 - 6), y0 + 2.3, z), Color = opts.color or C.Steel, Material = M.Metal })
			b.deco({ Name = "BayCap", Size = Vector3.new(12.2, 0.3, 1), CFrame = CFrame.new(side * (W2 - 6), y0 + 4.75, z), Color = C.Hazard, Material = M.Metal })
		end
		reserve(ctx, if side < 0 then -W2 else W2 - 13, if side < 0 then -W2 + 13 else W2, -40, BACK)
	end
end

-- B1 Cash Vault ------------------------------------------------------------------------------

local function cashVault(ctx)
	local b, y0, accent = ctx.b, ctx.y0, Props.rgb(ctx.palette.Accent)
	sideRacks(ctx, RACK_ZS, { color = C.Steel, label = "CURRENCY" })
	-- Counting stations: steel tables with banknote counters; loot lands on the tables.
	for _, x in ipairs({ -30, 30 }) do
		for _, z in ipairs({ 4, 38 }) do
			local top = Props.table(b, facing(Vector3.new(x, y0, z), -Z), 9, 4, 3.2, C.SteelLight)
			b.deco({ Name = "Counter", Size = Vector3.new(1.8, 1.2, 1.4), CFrame = top * CFrame.new(0, 0.6, 0.8), Color = rgb(40, 44, 50), Material = M.Metal })
			b.deco({ Name = "CounterSlot", Size = Vector3.new(1.4, 0.15, 0.6), CFrame = top * CFrame.new(0, 1.25, 0.6), Color = C.Black })
			b.deco({ Name = "CounterDisplay", Size = Vector3.new(1.2, 0.4, 0.05), CFrame = top * CFrame.new(0, 0.9, 0.08), Color = rgb(80, 255, 140), Material = M.Neon })
			b.deco({ Name = "Lamp", Size = Vector3.new(0.3, 2.2, 0.3), CFrame = top * CFrame.new(-3.8, 1.1, 1.3), Color = C.SteelDark, Material = M.Metal })
			for _, dx in ipairs({ -2.6, 2.6 }) do
				point(ctx, top * CFrame.new(dx, 0, -0.4), "M", "Table")
			end
			reserve(ctx, x - 5.5, x + 5.5, z - 3, z + 3)
		end
	end
	-- Safe-deposit wall either side of the exit corridor.
	for _, side in ipairs({ -1, 1 }) do
		for col = 0, 7 do
			for row = 0, 3 do
				local x = side * (18 + col * 3.8)
				b.deco({ Name = "DepositBox", Size = Vector3.new(3.5, 2.3, 0.6), CFrame = CFrame.new(x, y0 + 4.5 + row * 2.5, BACK - 0.4), Color = if (col + row) % 2 == 0 then rgb(150, 154, 160) else rgb(132, 136, 142), Material = M.Metal })
			end
		end
		b.deco({ Name = "DepositWallFrame", Size = Vector3.new(31, 0.6, 0.9), CFrame = CFrame.new(side * 31.3, y0 + 13.8, BACK - 0.5), Color = accent, Material = M.Metal })
	end
	reserve(ctx, -50, 50, BACK - 6, BACK)
	-- Shrink-wrapped cash pallets in the collection zones (their tops are loot points).
	for _, p in ipairs({ { -22, 22 }, { 22, -14 }, { -38, -18 }, { 38, 22 } }) do
		local top = Props.pallet(b, CFrame.new(p[1], y0, p[2]))
		b.deco({ Name = "WrappedCash", Size = Vector3.new(3.2, 1.6, 2.8), CFrame = top * CFrame.new(0, 0.8, 0), Color = Color3.fromRGB(112, 158, 98), Material = M.Fabric })
		b.deco({ Name = "Wrap", Size = Vector3.new(3.3, 1.7, 2.9), CFrame = top * CFrame.new(0, 0.85, 0), Color = Color3.fromRGB(230, 240, 255), Material = M.Glass, Transparency = 0.7 })
		b.deco({ Name = "PalletStrap", Size = Vector3.new(0.3, 1.75, 2.95), CFrame = top * CFrame.new(0, 0.85, 0), Color = accent, Material = M.Fabric })
		point(ctx, top * CFrame.new(0, 1.7, 0), "M", "Pallet")
		reserve(ctx, p[1] - 2.5, p[1] + 2.5, p[2] - 2.2, p[2] + 2.2)
	end
	-- Landmark: a caged pyramid of banded cash on a gold-trimmed dais.
	local base = CFrame.new(0, y0, 18)
	b.cyl({ Name = "Dais", Size = Vector3.new(1, 16, 16), CFrame = base * CFrame.new(0, 0.5, 0) * UP, Color = rgb(60, 62, 68), Material = M.Marble })
	b.cyl({ Name = "DaisTrim", Size = Vector3.new(0.3, 16.4, 16.4), CFrame = base * CFrame.new(0, 1.05, 0) * UP, Color = accent, Material = M.Metal, CanCollide = false })
	local layer = 0
	for n = 4, 1, -1 do
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				local x, z = (i - (n - 1) / 2) * 2.3, (j - (n - 1) / 2) * 1.5
				b.deco({ Name = "CashBrick", Size = Vector3.new(2.2, 0.9, 1.4), CFrame = base * CFrame.new(x, 1.65 + layer * 0.92, z), Color = rgb(112, 158, 98), Material = M.Fabric })
				if (i + j + layer) % 2 == 0 then
					b.deco({ Name = "CashBand", Size = Vector3.new(0.4, 0.94, 1.44), CFrame = base * CFrame.new(x, 1.65 + layer * 0.92, z), Color = C.White })
				end
			end
		end
		layer += 1
	end
	for _, p in ipairs({ { -5.5, -5.5 }, { 5.5, -5.5 }, { -5.5, 5.5 }, { 5.5, 5.5 } }) do
		b.part({ Name = "CagePost", Size = Vector3.new(0.6, 8, 0.6), CFrame = base * CFrame.new(p[1], 5, p[2]), Color = accent, Material = M.Metal })
	end
	for _, side in ipairs({ { 0, -5.5, 11, 0.3 }, { 0, 5.5, 11, 0.3 }, { -5.5, 0, 0.3, 11 }, { 5.5, 0, 0.3, 11 } }) do
		b.part({ Name = "CageGlass", Size = Vector3.new(side[3], 7.4, side[4]), CFrame = base * CFrame.new(side[1], 4.8, side[2]), Color = C.Glass, Material = M.Glass, Transparency = 0.75, CastShadow = false })
	end
	b.deco({ Name = "CageRoof", Size = Vector3.new(11.6, 0.4, 11.6), CFrame = base * CFrame.new(0, 9, 0), Color = accent, Material = M.Metal })
	local plaque = Props.sign(b, base * CFrame.new(0, 2.2, -8.3) * CFrame.Angles(0, math.pi, 0), 6, 1, "RESERVE 01  -  $50,000,000", { PPS = 40, Color = accent })
	plaque.CanCollide = false
	local spot = b.deco({ Name = "LandmarkSpot", Size = Vector3.new(2, 0.2, 2), CFrame = base * CFrame.new(0, 14, 0), Color = rgb(255, 240, 210), Material = M.Neon })
	light(spot, "SpotLight", rgb(255, 236, 200), 2.2, 22, false)
	reserve(ctx, -9.5, 9.5, 8.5, 27.5)
	ctx.landmark = base
	ctx.rarePoint = base * CFrame.new(0, 0, -11)
	emitter(ctx, Vector3.new(-50, y0 + 24, 0), "Ventilation")
	emitter(ctx, Vector3.new(50, y0 + 24, 30), "Ventilation")
	emitter(ctx, Vector3.new(0, y0 + 26, 18), "LightBuzz")
end

-- B2 Gold Reserve ----------------------------------------------------------------------------

local function goldReserve(ctx)
	local b, y0, accent = ctx.b, ctx.y0, Props.rgb(ctx.palette.Accent)
	sideRacks(ctx, RACK_ZS, {
		color = rgb(60, 56, 50),
		heavy = true,
		label = "BULLION",
		boxColor = rgb(70, 66, 60),
		decor = function(cf)
			b.deco({ Name = "RackPlate", Size = Vector3.new(14, 0.5, 0.2), CFrame = cf * CFrame.new(0, 7.9, -1.7), Color = accent, Material = M.Metal })
		end,
	})
	-- Bullion cages: steel frames with mesh glass around pallets of gold.
	for _, x in ipairs({ -32, 32 }) do
		for _, z in ipairs({ 2, 40 }) do
			local base = CFrame.new(x, y0, z)
			local top = Props.pallet(b, base)
			decoLoot(ctx, "GoldCrate", top)
			for _, p in ipairs({ { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } }) do
				b.part({ Name = "CagePost", Size = Vector3.new(0.4, 6, 0.4), CFrame = base * CFrame.new(p[1], 3, p[2]), Color = rgb(60, 56, 50), Material = M.Metal })
			end
			for _, s in ipairs({ { 0, -3, 6, 0.2 }, { 0, 3, 6, 0.2 }, { -3, 0, 0.2, 6 }, { 3, 0, 0.2, 6 } }) do
				b.part({ Name = "CageMesh", Size = Vector3.new(s[3], 5.6, s[4]), CFrame = base * CFrame.new(s[1], 2.9, s[2]), Color = rgb(90, 86, 80), Material = M.ForceField, Transparency = 0.55, CastShadow = false })
			end
			b.deco({ Name = "CageTop", Size = Vector3.new(6.4, 0.3, 6.4), CFrame = base * CFrame.new(0, 6, 0), Color = rgb(60, 56, 50), Material = M.DiamondPlate })
			Props.sign(b, base * CFrame.new(0, 5, -3.2) * CFrame.Angles(0, math.pi, 0), 4, 0.7, "SECURED", { PPS = 40, Color = accent })
			reserve(ctx, x - 4, x + 4, z - 4, z + 4)
		end
	end
	-- Display stands (velvet tops): loot points.
	for _, x in ipairs({ -20, 20 }) do
		for _, z in ipairs({ -14, 48 }) do
			local cf = CFrame.new(x, y0, z)
			b.part({ Name = "Stand", Size = Vector3.new(3.4, 3, 3.4), CFrame = cf * CFrame.new(0, 1.5, 0), Color = rgb(60, 50, 40), Material = M.Wood })
			b.deco({ Name = "StandTop", Size = Vector3.new(3, 0.12, 3), CFrame = cf * CFrame.new(0, 3.06, 0), Color = rgb(120, 30, 46), Material = M.Fabric })
			b.deco({ Name = "StandTrim", Size = Vector3.new(3.6, 0.2, 3.6), CFrame = cf * CFrame.new(0, 2.95, 0), Color = accent, Material = M.Metal })
			point(ctx, cf * CFrame.new(0, 3.12, 0), "M", "Plinth")
			reserve(ctx, x - 2.5, x + 2.5, z - 2.5, z + 2.5)
		end
	end
	-- Landmark: an overhead gantry crane lifting a pallet of gold above a guarded bay.
	local zc = 16
	for _, x in ipairs({ -(W2 - 3), W2 - 3 }) do
		b.deco({ Name = "CraneRail", Size = Vector3.new(1.2, 1.2, 90), CFrame = CFrame.new(x, y0 + 22.4, 12), Color = accent, Material = M.Metal })
	end
	b.deco({ Name = "CraneBridge", Size = Vector3.new(W2 * 2 - 4, 2.6, 2.6), CFrame = CFrame.new(0, y0 + 23.4, zc), Color = rgb(236, 180, 40), Material = M.Metal })
	b.deco({ Name = "CraneBridge2", Size = Vector3.new(W2 * 2 - 4, 2.6, 2.6), CFrame = CFrame.new(0, y0 + 23.4, zc + 4), Color = rgb(236, 180, 40), Material = M.Metal })
	for i = -6, 6 do
		b.deco({ Name = "BridgeStripe", Size = Vector3.new(2, 2.62, 0.05), CFrame = CFrame.new(i * 4, y0 + 23.4, zc - 1.32), Color = if i % 2 == 0 then C.Hazard else C.Black, CastShadow = false })
	end
	b.deco({ Name = "Trolley", Size = Vector3.new(5, 2.2, 6.4), CFrame = CFrame.new(0, y0 + 21.6, zc + 2), Color = rgb(60, 56, 50), Material = M.Metal })
	for _, x in ipairs({ -1.4, 1.4 }) do
		b.deco({ Name = "HoistCable", Size = Vector3.new(0.18, 7, 0.18), CFrame = CFrame.new(x, y0 + 17, zc + 2), Color = C.Black, CastShadow = false })
	end
	b.deco({ Name = "HookBlock", Size = Vector3.new(3.4, 1.4, 1.6), CFrame = CFrame.new(0, y0 + 13, zc + 2), Color = accent, Material = M.Metal })
	for _, x in ipairs({ -1.6, 1.6 }) do
		b.deco({ Name = "Sling", Size = Vector3.new(0.15, 3.2, 0.15), CFrame = CFrame.new(x, y0 + 10.9, zc + 2) * CFrame.Angles(0, 0, math.rad(if x > 0 then 18 else -18)), Color = C.Black, CastShadow = false })
	end
	local liftTop = Props.pallet(b, CFrame.new(0, y0 + 8.5, zc + 2))
	decoLoot(ctx, "GoldCrate", liftTop)
	-- Guarded drop bay under the load.
	Props.railing(b, Vector3.new(-7, y0, zc - 4), Vector3.new(7, y0, zc - 4))
	Props.railing(b, Vector3.new(-7, y0, zc + 8), Vector3.new(7, y0, zc + 8))
	Props.railing(b, Vector3.new(-7, y0, zc - 4), Vector3.new(-7, y0, zc + 8))
	Props.railing(b, Vector3.new(7, y0, zc - 4), Vector3.new(7, y0, zc + 8))
	Props.hazardStripes(b, CFrame.new(0, y0, zc + 2), 13, 11)
	Props.warningLight(b, CFrame.new(-7, y0 + 3.6, zc - 4), C.Amber)
	Props.warningLight(b, CFrame.new(7, y0 + 3.6, zc + 8), C.Amber)
	local warm = b.deco({ Name = "GoldGlow", Size = Vector3.new(2, 0.2, 2), CFrame = CFrame.new(0, y0 + 20.4, zc + 2), Color = rgb(255, 200, 120), Material = M.Neon })
	light(warm, "SpotLight", rgb(255, 196, 110), 2.6, 26, false)
	reserve(ctx, -8.5, 8.5, zc - 5.5, zc + 9.5)
	-- Forklift parked by the racks.
	local fl = facing(Vector3.new(-52, y0, 26), Z)
	b.part({ Name = "ForkliftBody", Size = Vector3.new(3.6, 2.6, 5), CFrame = fl * CFrame.new(0, 1.9, 0), Color = rgb(236, 180, 40), Material = M.Metal })
	b.part({ Name = "ForkliftMast", Size = Vector3.new(3.2, 7, 0.5), CFrame = fl * CFrame.new(0, 3.6, -2.7), Color = rgb(40, 40, 44), Material = M.Metal })
	for _, x in ipairs({ -1, 1 }) do
		b.deco({ Name = "Fork", Size = Vector3.new(0.4, 0.2, 3), CFrame = fl * CFrame.new(x, 0.4, -4.3), Color = rgb(40, 40, 44), Material = M.Metal })
		for _, z in ipairs({ -1.6, 1.6 }) do
			b.deco({ Name = "Wheel", Size = Vector3.new(0.8, 1.4, 1.4), CFrame = fl * CFrame.new(x * 1.9, 0.7, z), Color = C.Black, Material = M.Rubber, Shape = Enum.PartType.Cylinder })
		end
	end
	b.deco({ Name = "Cage", Size = Vector3.new(3.4, 0.2, 3.4), CFrame = fl * CFrame.new(0, 5.6, 0.4), Color = rgb(40, 40, 44), Material = M.Metal })
	reserve(ctx, -56, -48, 20, 32)
	ctx.landmark = CFrame.new(0, y0, zc)
	ctx.rarePoint = CFrame.new(0, y0, zc - 9)
	emitter(ctx, Vector3.new(0, y0 + 22, zc), "Machinery")
	emitter(ctx, Vector3.new(-50, y0 + 24, -10), "Ventilation")
end

-- B3 Diamond Chamber -------------------------------------------------------------------------

local function diamondChamber(ctx)
	local b, y0, accent = ctx.b, ctx.y0, Props.rgb(ctx.palette.Accent)
	local plinth = rgb(40, 46, 58)
	-- Reinforced glass display cases along the walls with staged gems (decor).
	local items = { "DiamondCluster", "LargeGem", "Diamond", "DiamondFormation" }
	local n = 0
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -24, -2, 20, 42 }) do
			n += 1
			local base = CFrame.new(side * (W2 - 6), y0, z)
			local inner = Props.displayCase(b, base, 6, 4, 3.2, plinth, 3)
			decoLoot(ctx, items[(n - 1) % #items + 1], inner)
			b.deco({ Name = "CaseLight", Size = Vector3.new(5.6, 0.1, 3.6), CFrame = inner * CFrame.new(0, 2.9, 0), Color = rgb(200, 230, 255), Material = M.Neon, Transparency = 0.2 })
			-- Laser fence in front of each case.
			for i = 0, 2 do
				b.deco({ Name = "Laser", Size = Vector3.new(0.06, 0.06, 6.6), CFrame = CFrame.new(side * (W2 - 9.6), y0 + 0.8 + i * 1.1, z), Color = rgb(255, 50, 60), Material = M.Neon, CastShadow = false })
			end
			for _, dz in ipairs({ -3.3, 3.3 }) do
				b.part({ Name = "LaserPost", Size = Vector3.new(0.4, 3.4, 0.4), CFrame = CFrame.new(side * (W2 - 9.6), y0 + 1.7, z + dz), Color = C.SteelDark, Material = M.Metal })
			end
		end
		reserve(ctx, if side < 0 then -W2 else W2 - 11, if side < 0 then -W2 + 11 else W2, -40, BACK)
	end
	-- Open display platforms (velvet plinths) in the collection zones: loot points.
	for _, x in ipairs({ -40, -24, 24, 40 }) do
		for _, z in ipairs({ -6, 28, 48 }) do
			local cf = CFrame.new(x, y0, z)
			b.cyl({ Name = "Plinth", Size = Vector3.new(2.6, 3, 3), CFrame = cf * CFrame.new(0, 1.3, 0) * UP, Color = plinth, Material = M.Marble })
			b.cyl({ Name = "PlinthTop", Size = Vector3.new(0.12, 2.8, 2.8), CFrame = cf * CFrame.new(0, 2.66, 0) * UP, Color = rgb(30, 40, 90), Material = M.Fabric, CanCollide = false })
			b.cyl({ Name = "PlinthRing", Size = Vector3.new(0.1, 3.2, 3.2), CFrame = cf * CFrame.new(0, 0.1, 0) * UP, Color = accent, Material = M.Neon, CanCollide = false })
			point(ctx, cf * CFrame.new(0, 2.72, 0), "M", "Plinth")
			reserve(ctx, x - 2.2, x + 2.2, z - 2.2, z + 2.2)
		end
	end
	-- Landmark: a giant cut crystal on a ringed pedestal under blue light, inside a laser ring.
	local base = CFrame.new(0, y0, 18)
	b.cyl({ Name = "Pedestal", Size = Vector3.new(2, 10, 10), CFrame = base * CFrame.new(0, 1, 0) * UP, Color = plinth, Material = M.Marble, Reflectance = 0.1 })
	b.cyl({ Name = "PedestalTier", Size = Vector3.new(1.4, 7, 7), CFrame = base * CFrame.new(0, 2.7, 0) * UP, Color = rgb(60, 70, 90), Material = M.Marble })
	for i = 1, 3 do
		b.cyl({ Name = "Ring" .. i, Size = Vector3.new(0.25, 7 + i * 2.4, 7 + i * 2.4), CFrame = base * CFrame.new(0, 4 + i * 2.2, 0) * UP * CFrame.Angles(math.rad(i * 18), 0, 0), Color = accent, Material = M.Neon, CanCollide = false, Transparency = 0.25 })
	end
	b.deco({ Name = "GiantCrystal", Size = Vector3.new(5.2, 5.2, 5.2), CFrame = base * CFrame.new(0, 8.5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), Color = rgb(210, 236, 255), Material = M.Glass, Transparency = 0.12, Reflectance = 0.4 })
	b.deco({ Name = "CrystalCore", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = base * CFrame.new(0, 8.5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), Color = rgb(170, 220, 255), Material = M.Neon, Transparency = 0.3 })
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		b.part({ Name = "LaserPost", Size = Vector3.new(0.4, 2.6, 0.4), CFrame = base * CFrame.new(math.cos(a) * 8.5, 1.3, math.sin(a) * 8.5), Color = C.SteelDark, Material = M.Metal })
		local a2 = (i + 1) / 8 * math.pi * 2
		local p1 = Vector3.new(math.cos(a) * 8.5, 1.8, math.sin(a) * 8.5)
		local p2 = Vector3.new(math.cos(a2) * 8.5, 1.8, math.sin(a2) * 8.5)
		local mid = (p1 + p2) / 2
		b.deco({ Name = "LaserBeam", Size = Vector3.new(0.06, 0.06, (p2 - p1).Magnitude), CFrame = base * CFrame.lookAt(mid, p2), Color = rgb(255, 50, 60), Material = M.Neon, CastShadow = false })
	end
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local s = b.deco({ Name = "BlueSpot", Size = Vector3.new(1.2, 0.3, 1.2), CFrame = base * CFrame.new(math.cos(a) * 7, 22, math.sin(a) * 7), Color = rgb(170, 220, 255), Material = M.Neon })
		if i % 2 == 0 then
			light(s, "SpotLight", rgb(170, 220, 255), 2.6, 30, false)
		end
	end
	reserve(ctx, -10, 10, 8, 28)
	-- Security gate (turnstile frame) at the chamber entrance.
	for _, x in ipairs({ -9, 9 }) do
		b.part({ Name = "GatePost", Size = Vector3.new(1, 7, 1), CFrame = CFrame.new(x, y0 + 3.5, -32), Color = C.SteelDark, Material = M.Metal })
	end
	b.deco({ Name = "GateBeam", Size = Vector3.new(19, 0.8, 1), CFrame = CFrame.new(0, y0 + 7.2, -32), Color = accent, Material = M.Neon })
	ctx.landmark = base
	ctx.rarePoint = base * CFrame.new(0, 0, -11)
	emitter(ctx, Vector3.new(0, y0 + 20, 18), "ElectricalHum")
	emitter(ctx, Vector3.new(50, y0 + 24, 0), "Ventilation")
end

-- B4 Emerald Reserve -------------------------------------------------------------------------

local function emeraldReserve(ctx)
	local b, y0, accent = ctx.b, ctx.y0, Props.rgb(ctx.palette.Accent)
	local dark = rgb(26, 30, 28)
	-- Display towers: tall glass columns with emeralds and green light rings.
	local items = { "Emerald", "EmeraldCluster", "PremiumEmerald", "GrandEmerald" }
	local n = 0
	for _, x in ipairs({ -(W2 - 7), W2 - 7 }) do
		for _, z in ipairs({ -24, 0, 24, 48 }) do
			n += 1
			local base = CFrame.new(x, y0, z)
			b.cyl({ Name = "TowerBase", Size = Vector3.new(1.2, 5, 5), CFrame = base * CFrame.new(0, 0.6, 0) * UP, Color = dark, Material = M.Metal })
			b.cyl({ Name = "TowerGlass", Size = Vector3.new(10, 4, 4), CFrame = base * CFrame.new(0, 6.2, 0) * UP, Color = rgb(190, 255, 220), Material = M.Glass, Transparency = 0.7, CastShadow = false })
			b.cyl({ Name = "TowerCap", Size = Vector3.new(0.8, 5, 5), CFrame = base * CFrame.new(0, 11.6, 0) * UP, Color = dark, Material = M.Metal })
			for i = 0, 2 do
				b.cyl({ Name = "TowerRing", Size = Vector3.new(0.15, 4.2, 4.2), CFrame = base * CFrame.new(0, 2.5 + i * 3.4, 0) * UP, Color = accent, Material = M.Neon, CanCollide = false })
			end
			local shelf = b.deco({ Name = "TowerShelf", Size = Vector3.new(3, 0.15, 3), CFrame = base * CFrame.new(0, 5.4, 0), Color = dark, Material = M.Metal })
			decoLoot(ctx, items[(n - 1) % #items + 1], shelf.CFrame * CFrame.new(0, 0.08, 0))
			if n % 2 == 0 then
				light(shelf, "PointLight", rgb(80, 255, 150), 0.8, 10, false)
			end
		end
	end
	-- Sealed premium containers on the back wall (status lights).
	for _, side in ipairs({ -1, 1 }) do
		for i = 0, 5 do
			local x = side * (20 + i * 5.4)
			b.part({ Name = "Container", Size = Vector3.new(5, 9, 3), CFrame = CFrame.new(x, y0 + 4.5, BACK - 1.6), Color = dark, Material = M.Metal })
			b.deco({ Name = "ContainerLight", Size = Vector3.new(0.5, 0.5, 0.2), CFrame = CFrame.new(x + 1.6, y0 + 7.6, BACK - 3.2), Color = if i % 3 == 0 then C.Red else accent, Material = M.Neon })
			b.deco({ Name = "ContainerHandle", Size = Vector3.new(0.3, 2.4, 0.3), CFrame = CFrame.new(x - 1.6, y0 + 4.5, BACK - 3.2), Color = C.SteelLight, Material = M.Metal })
		end
	end
	reserve(ctx, -55, 55, BACK - 6, BACK)
	reserve(ctx, -W2, -W2 + 12, -40, BACK)
	reserve(ctx, W2 - 12, W2, -40, BACK)
	-- Premium display trays on black stands: loot points.
	for _, x in ipairs({ -38, -22, 22, 38 }) do
		for _, z in ipairs({ -10, 26, 46 }) do
			local cf = CFrame.new(x, y0, z)
			b.part({ Name = "Stand", Size = Vector3.new(3.4, 3, 2.6), CFrame = cf * CFrame.new(0, 1.5, 0), Color = dark, Material = M.Slate })
			b.deco({ Name = "StandInlay", Size = Vector3.new(3.5, 0.15, 2.7), CFrame = cf * CFrame.new(0, 3.05, 0), Color = rgb(200, 160, 60), Material = M.Metal })
			b.deco({ Name = "StandGlow", Size = Vector3.new(3.5, 0.1, 2.7), CFrame = cf * CFrame.new(0, 0.05, 0), Color = accent, Material = M.Neon })
			point(ctx, cf * CFrame.new(0, 3.12, 0), "M", "Plinth")
			reserve(ctx, x - 2.4, x + 2.4, z - 2, z + 2)
		end
	end
	-- Landmark: an emerald obelisk on a black-stone base with gold inlays.
	local base = CFrame.new(0, y0, 18)
	b.part({ Name = "ObeliskBase", Size = Vector3.new(10, 2, 10), CFrame = base * CFrame.new(0, 1, 0), Color = rgb(20, 22, 22), Material = M.Slate })
	b.part({ Name = "ObeliskBase2", Size = Vector3.new(7, 1.4, 7), CFrame = base * CFrame.new(0, 2.7, 0) * CFrame.Angles(0, math.rad(45), 0), Color = rgb(30, 34, 32), Material = M.Slate })
	for _, s in ipairs({ { 0, -5.05, 10.1, 0.12 }, { 0, 5.05, 10.1, 0.12 }, { -5.05, 0, 0.12, 10.1 }, { 5.05, 0, 0.12, 10.1 } }) do
		b.deco({ Name = "GoldInlay", Size = Vector3.new(s[3], 0.4, s[4]), CFrame = base * CFrame.new(s[1], 1.6, s[2]), Color = rgb(210, 170, 60), Material = M.Metal })
	end
	b.part({ Name = "Obelisk", Size = Vector3.new(3.6, 16, 3.6), CFrame = base * CFrame.new(0, 11.4, 0), Color = rgb(30, 200, 110), Material = M.Glass, Transparency = 0.15, Reflectance = 0.25 })
	b.deco({ Name = "ObeliskB", Size = Vector3.new(2.8, 16.02, 2.8), CFrame = base * CFrame.new(0, 11.4, 0) * CFrame.Angles(0, math.rad(45), 0), Color = rgb(30, 200, 110), Material = M.Glass, Transparency = 0.15 })
	local core = b.deco({ Name = "ObeliskCore", Size = Vector3.new(1.4, 14, 1.4), CFrame = base * CFrame.new(0, 11.4, 0), Color = rgb(60, 255, 150), Material = M.Neon, Transparency = 0.35 })
	light(core, "PointLight", rgb(80, 255, 150), 1.6, 24, false)
	b.part({ Name = "ObeliskTip", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = base * CFrame.new(0, 20.2, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), Color = rgb(30, 200, 110), Material = M.Glass, Transparency = 0.1 })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		b.part({ Name = "SecurityPost", Size = Vector3.new(0.6, 3.6, 0.6), CFrame = base * CFrame.new(math.cos(a) * 8, 1.8, math.sin(a) * 8), Color = C.SteelDark, Material = M.Metal })
		b.deco({ Name = "PostLight", Size = Vector3.new(0.7, 0.4, 0.7), CFrame = base * CFrame.new(math.cos(a) * 8, 3.8, math.sin(a) * 8), Color = accent, Material = M.Neon })
	end
	reserve(ctx, -9.5, 9.5, 8.5, 27.5)
	-- Scanner arch at the chamber entrance.
	for _, x in ipairs({ -8, 8 }) do
		b.part({ Name = "ScannerPost", Size = Vector3.new(1.4, 9, 1.4), CFrame = CFrame.new(x, y0 + 4.5, -32), Color = dark, Material = M.Metal })
	end
	b.deco({ Name = "ScannerBeam", Size = Vector3.new(17.4, 1, 1.4), CFrame = CFrame.new(0, y0 + 9.4, -32), Color = dark, Material = M.Metal })
	b.deco({ Name = "ScanLine", Size = Vector3.new(14.6, 0.12, 0.12), CFrame = CFrame.new(0, y0 + 5, -32), Color = accent, Material = M.Neon, CastShadow = false })
	ctx.landmark = base
	ctx.rarePoint = base * CFrame.new(0, 0, -11)
	emitter(ctx, Vector3.new(0, y0 + 18, 18), "ElectricalHum")
	emitter(ctx, Vector3.new(-50, y0 + 24, 30), "Ventilation")
end

-- B5 Platinum Reserve ------------------------------------------------------------------------

local function platinumReserve(ctx)
	local b, y0, accent = ctx.b, ctx.y0, Props.rgb(ctx.palette.Accent)
	sideRacks(ctx, RACK_ZS, { color = rgb(90, 100, 116), heavy = true, height = 9, label = "PT-ALLOY", boxColor = rgb(120, 130, 146) })
	-- Blast plates on the side walls above the racks.
	for _, side in ipairs({ -1, 1 }) do
		for z = -20, 52, 18 do
			b.deco({ Name = "BlastPlate", Size = Vector3.new(0.6, 8, 12), CFrame = CFrame.new(side * (W2 - 0.6), y0 + 16, z), Color = rgb(100, 108, 120), Material = M.DiamondPlate })
			b.deco({ Name = "BlastTrim", Size = Vector3.new(0.7, 0.4, 12), CFrame = CFrame.new(side * (W2 - 0.6), y0 + 20.2, z), Color = accent, Material = M.Neon })
		end
	end
	-- Hydraulic press behind a guard rail.
	local press = CFrame.new(-34, y0, 2)
	b.part({ Name = "PressBed", Size = Vector3.new(8, 2, 6), CFrame = press * CFrame.new(0, 1, 0), Color = rgb(60, 64, 72), Material = M.Metal })
	for _, x in ipairs({ -3.6, 3.6 }) do
		b.part({ Name = "PressColumn", Size = Vector3.new(0.8, 12, 0.8), CFrame = press * CFrame.new(x, 6, 0), Color = rgb(90, 96, 106), Material = M.Metal })
	end
	b.part({ Name = "PressHead", Size = Vector3.new(8.4, 2.2, 6), CFrame = press * CFrame.new(0, 12.6, 0), Color = rgb(60, 64, 72), Material = M.Metal })
	b.deco({ Name = "PressPiston", Size = Vector3.new(4, 1.4, 1.4), CFrame = press * CFrame.new(0, 9.6, 0) * UP, Color = rgb(200, 206, 214), Material = M.Metal, Shape = Enum.PartType.Cylinder })
	b.deco({ Name = "PressPlate", Size = Vector3.new(6, 0.6, 4.6), CFrame = press * CFrame.new(0, 7.3, 0), Color = rgb(150, 156, 166), Material = M.DiamondPlate })
	Props.railing(b, Vector3.new(-40, y0, -4), Vector3.new(-28, y0, -4))
	Props.railing(b, Vector3.new(-40, y0, 8), Vector3.new(-28, y0, 8))
	Props.hazardStripes(b, press * CFrame.new(0, 0, -3.6), 9, 0.6)
	Props.warningLight(b, press * CFrame.new(4.4, 14, 0), C.Amber)
	reserve(ctx, -41, -27, -5, 9)
	-- Conveyor with canisters.
	local conv = facing(Vector3.new(34, y0, 2), Z)
	b.part({ Name = "ConveyorFrame", Size = Vector3.new(4, 2.6, 18), CFrame = conv * CFrame.new(0, 1.3, 0), Color = rgb(60, 64, 72), Material = M.Metal })
	for i = -4, 4 do
		b.deco({ Name = "Roller", Size = Vector3.new(3.6, 0.5, 0.5), CFrame = conv * CFrame.new(0, 2.7, i * 2), Color = rgb(170, 176, 186), Material = M.Metal, Shape = Enum.PartType.Cylinder })
	end
	for i = -1, 1 do
		local c = b.deco({ Name = "Canister", Size = Vector3.new(2, 1.4, 1.4), CFrame = conv * CFrame.new(0, 3.7, i * 5) * UP, Color = rgb(190, 196, 206), Material = M.Metal, Shape = Enum.PartType.Cylinder })
		c.CastShadow = true
	end
	Props.railing(b, Vector3.new(31, y0, -9), Vector3.new(31, y0, 13))
	reserve(ctx, 30, 38, -9, 13)
	-- Robotic arm.
	local arm = CFrame.new(34, y0, 40)
	b.cyl({ Name = "ArmBase", Size = Vector3.new(1.4, 4, 4), CFrame = arm * CFrame.new(0, 0.7, 0) * UP, Color = rgb(60, 64, 72), Material = M.Metal })
	b.part({ Name = "ArmLower", Size = Vector3.new(1.2, 7, 1.2), CFrame = arm * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, 0, math.rad(20)), Color = rgb(236, 180, 40), Material = M.Metal })
	b.part({ Name = "ArmUpper", Size = Vector3.new(1, 6, 1), CFrame = arm * CFrame.new(-2.6, 9.4, 0) * CFrame.Angles(0, 0, math.rad(-60)), Color = rgb(236, 180, 40), Material = M.Metal })
	b.deco({ Name = "ArmGripper", Size = Vector3.new(1.6, 0.8, 1.6), CFrame = arm * CFrame.new(-5.4, 10.8, 0), Color = rgb(60, 64, 72), Material = M.Metal })
	reserve(ctx, 26, 38, 36, 44)
	-- Steel tables: loot points.
	for _, x in ipairs({ -24, 24 }) do
		for _, z in ipairs({ 34, 50 }) do
			local top = Props.table(b, CFrame.new(x, y0, z), 7, 3.4, 3.2, rgb(150, 156, 166))
			for _, dx in ipairs({ -1.8, 1.8 }) do
				point(ctx, top * CFrame.new(dx, 0, 0), "M", "Table")
			end
			reserve(ctx, x - 4, x + 4, z - 2.4, z + 2.4)
		end
	end
	-- Landmark: the platinum refinery vessel.
	local base = CFrame.new(0, y0, 18)
	b.cyl({ Name = "VesselFoot", Size = Vector3.new(1.6, 12, 12), CFrame = base * CFrame.new(0, 0.8, 0) * UP, Color = rgb(60, 64, 72), Material = M.Metal })
	b.cyl({ Name = "Vessel", Size = Vector3.new(14, 9, 9), CFrame = base * CFrame.new(0, 8.6, 0) * UP, Color = rgb(200, 206, 216), Material = M.Metal, Reflectance = 0.15 })
	b.part({ Name = "VesselDome", Size = Vector3.new(9, 9, 9), CFrame = base * CFrame.new(0, 15.6, 0), Color = rgb(200, 206, 216), Material = M.Metal, Shape = Enum.PartType.Ball })
	for i = 0, 2 do
		b.cyl({ Name = "VesselBand", Size = Vector3.new(0.6, 9.3, 9.3), CFrame = base * CFrame.new(0, 3.5 + i * 4.6, 0) * UP, Color = rgb(60, 64, 72), Material = M.Metal, CanCollide = false })
	end
	local window = b.deco({ Name = "VesselWindow", Size = Vector3.new(0.4, 3.4, 2.4), CFrame = base * CFrame.new(0, 9, -4.4) * CFrame.Angles(0, math.rad(90), 0), Color = rgb(150, 210, 255), Material = M.Neon })
	light(window, "PointLight", rgb(150, 210, 255), 1.4, 18, false)
	for _, side in ipairs({ -1, 1 }) do
		Props.pipe(b, Vector3.new(side * 4.4, y0 + 13, 18), Vector3.new(side * 20, y0 + 13, 18), 1.2, rgb(170, 176, 186))
		b.deco({ Name = "PipeDrop", Size = Vector3.new(13, 1.2, 1.2), CFrame = CFrame.new(side * 20, y0 + 6.5, 18) * UP, Color = rgb(170, 176, 186), Material = M.Metal, Shape = Enum.PartType.Cylinder })
		b.deco({ Name = "Gauge", Size = Vector3.new(0.3, 1.2, 1.2), CFrame = base * CFrame.new(side * 4.6, 6, 0), Color = C.White, Material = M.SmoothPlastic, Shape = Enum.PartType.Cylinder })
	end
	Props.railing(b, Vector3.new(-8, y0, 10), Vector3.new(8, y0, 10))
	reserve(ctx, -8.5, 8.5, 9, 27)
	reserve(ctx, -21.5, -18.5, 16.5, 19.5)
	reserve(ctx, 18.5, 21.5, 16.5, 19.5)
	ctx.landmark = base
	ctx.rarePoint = base * CFrame.new(0, 0, -12)
	emitter(ctx, Vector3.new(-34, y0 + 8, 2), "Machinery")
	emitter(ctx, Vector3.new(34, y0 + 4, 2), "Machinery")
	emitter(ctx, Vector3.new(0, y0 + 14, 18), "ElectricalHum")
end

-- B6 Artifact Chamber ------------------------------------------------------------------------

local function artifactChamber(ctx)
	local b, y0, accent = ctx.b, ctx.y0, Props.rgb(ctx.palette.Accent)
	local stone, stoneDark = rgb(176, 150, 112), rgb(128, 104, 76)
	-- Mosaic floor runner down the aisle.
	for i = 0, math.floor((BACK + 30) / 6) - 1 do
		b.deco({ Name = "Mosaic", Size = Vector3.new(12, 0.05, 5.6), CFrame = CFrame.new(0, y0 + 0.04, -34 + i * 6), Color = if i % 2 == 0 then rgb(150, 70, 50) else rgb(50, 110, 130), Material = M.Slate, CastShadow = false })
	end
	-- Stone columns along the chamber and arches over the aisle.
	for _, z in ipairs({ -22, 4, 32, 52 }) do
		for _, x in ipairs({ -12, 12 }) do
			b.cyl({ Name = "Column", Size = Vector3.new(18, 2.6, 2.6), CFrame = CFrame.new(x, y0 + 9, z) * UP, Color = stone, Material = M.Sandstone })
			b.part({ Name = "ColumnBase", Size = Vector3.new(3.4, 1.2, 3.4), CFrame = CFrame.new(x, y0 + 0.6, z), Color = stoneDark, Material = M.Sandstone })
			b.deco({ Name = "ColumnCap", Size = Vector3.new(3.4, 1, 3.4), CFrame = CFrame.new(x, y0 + 18.4, z), Color = stoneDark, Material = M.Sandstone })
			reserve(ctx, x - 2, x + 2, z - 2, z + 2)
		end
		b.deco({ Name = "Arch", Size = Vector3.new(27.4, 2.4, 3), CFrame = CFrame.new(0, y0 + 20, z), Color = stone, Material = M.Sandstone })
		b.deco({ Name = "ArchKey", Size = Vector3.new(2.6, 3, 3.2), CFrame = CFrame.new(0, y0 + 20.4, z), Color = accent, Material = M.Metal })
	end
	-- Containment pods with relics along the walls (cyan field rings).
	local items = { "Relic", "Statuette", "AncientCoin", "Sarcophagus" }
	local n = 0
	for _, x in ipairs({ -(W2 - 6), W2 - 6 }) do
		for _, z in ipairs({ -24, 0, 24, 48 }) do
			n += 1
			local base = CFrame.new(x, y0, z)
			b.cyl({ Name = "PodBase", Size = Vector3.new(1.4, 6, 6), CFrame = base * CFrame.new(0, 0.7, 0) * UP, Color = rgb(50, 54, 60), Material = M.Metal })
			b.cyl({ Name = "PodField", Size = Vector3.new(7, 5, 5), CFrame = base * CFrame.new(0, 4.9, 0) * UP, Color = rgb(120, 230, 255), Material = M.ForceField, Transparency = 0.4, CastShadow = false })
			b.cyl({ Name = "PodRing", Size = Vector3.new(0.2, 6.2, 6.2), CFrame = base * CFrame.new(0, 1.5, 0) * UP, Color = rgb(120, 230, 255), Material = M.Neon, CanCollide = false })
			b.cyl({ Name = "PodCap", Size = Vector3.new(0.8, 6, 6), CFrame = base * CFrame.new(0, 8.8, 0) * UP, Color = rgb(50, 54, 60), Material = M.Metal })
			decoLoot(ctx, items[(n - 1) % #items + 1], base * CFrame.new(0, 1.4, 0))
			if n % 2 == 1 then
				local c = b.deco({ Name = "PodLight", Size = Vector3.new(1, 0.2, 1), CFrame = base * CFrame.new(0, 8.3, 0), Color = rgb(120, 230, 255), Material = M.Neon })
				light(c, "PointLight", rgb(120, 230, 255), 0.9, 12, false)
			end
		end
	end
	reserve(ctx, -W2, -W2 + 11, -40, BACK)
	reserve(ctx, W2 - 11, W2, -40, BACK)
	-- Stepped display platforms: loot points.
	for _, x in ipairs({ -38, -24, 24, 38 }) do
		for _, z in ipairs({ -8, 16, 42 }) do
			local cf = CFrame.new(x, y0, z)
			b.part({ Name = "Step1", Size = Vector3.new(4.4, 1, 4.4), CFrame = cf * CFrame.new(0, 0.5, 0), Color = stoneDark, Material = M.Sandstone })
			b.part({ Name = "Step2", Size = Vector3.new(3.2, 1.2, 3.2), CFrame = cf * CFrame.new(0, 1.6, 0), Color = stone, Material = M.Sandstone })
			b.deco({ Name = "StepTrim", Size = Vector3.new(3.3, 0.12, 3.3), CFrame = cf * CFrame.new(0, 2.22, 0), Color = accent, Material = M.Metal })
			point(ctx, cf * CFrame.new(0, 2.28, 0), "M", "Plinth")
			reserve(ctx, x - 2.8, x + 2.8, z - 2.8, z + 2.8)
		end
	end
	-- Landmark: a sarcophagus in a containment field under a stone arch, with braziers.
	local base = CFrame.new(0, y0, 18)
	b.part({ Name = "Dais", Size = Vector3.new(12, 1.4, 14), CFrame = base * CFrame.new(0, 0.7, 0), Color = stoneDark, Material = M.Sandstone })
	b.part({ Name = "Dais2", Size = Vector3.new(8, 1, 10), CFrame = base * CFrame.new(0, 1.9, 0), Color = stone, Material = M.Sandstone })
	decoLoot(ctx, "Sarcophagus", base * CFrame.new(0, 2.4, 0), 2.2)
	b.part({ Name = "Field", Size = Vector3.new(7, 6, 8), CFrame = base * CFrame.new(0, 5.4, 0), Color = rgb(120, 230, 255), Material = M.ForceField, Transparency = 0.45, CanCollide = false, CastShadow = false })
	for _, x in ipairs({ -5.5, 5.5 }) do
		b.part({ Name = "LandmarkPillar", Size = Vector3.new(1.8, 14, 1.8), CFrame = base * CFrame.new(x, 7, 6), Color = stone, Material = M.Sandstone })
		b.cyl({ Name = "Brazier", Size = Vector3.new(1.2, 2.4, 2.4), CFrame = base * CFrame.new(x, 2.6, -6) * UP, Color = rgb(60, 50, 40), Material = M.Metal })
		local fire = b.deco({ Name = "BrazierFire", Size = Vector3.new(1.4, 1.4, 1.4), CFrame = base * CFrame.new(x, 3.7, -6), Color = rgb(255, 140, 50), Material = M.Neon, Shape = Enum.PartType.Ball })
		light(fire, "PointLight", rgb(255, 150, 70), 1.4, 16, false)
		reserve(ctx, x - 2, x + 2, 18 - 8, 18 - 4)
	end
	b.deco({ Name = "LandmarkLintel", Size = Vector3.new(13, 2, 2.4), CFrame = base * CFrame.new(0, 15, 6), Color = stone, Material = M.Sandstone })
	b.deco({ Name = "LintelGlyph", Size = Vector3.new(4, 1.2, 0.2), CFrame = base * CFrame.new(0, 15, 4.75), Color = accent, Material = M.Metal })
	reserve(ctx, -7, 7, 10, 26)
	ctx.landmark = base
	ctx.rarePoint = base * CFrame.new(0, 0, -11)
	emitter(ctx, Vector3.new(0, y0 + 12, 18), "ElectricalHum")
	emitter(ctx, Vector3.new(-50, y0 + 24, 20), "Ventilation")
end

-- B7 Legendary Reserve -----------------------------------------------------------------------

local function legendaryReserve(ctx)
	local b, y0 = ctx.b, ctx.y0
	local gold, black = rgb(220, 172, 52), rgb(24, 20, 28)
	-- Imposing entrance: a monumental gold arch with open double vault doors at the chamber line.
	for _, x in ipairs({ -15, 15 }) do
		b.part({ Name = "EntrancePylon", Size = Vector3.new(5, 26, 5), CFrame = CFrame.new(x, y0 + 13, -34), Color = black, Material = M.Marble })
		b.deco({ Name = "PylonTrim", Size = Vector3.new(5.4, 1, 5.4), CFrame = CFrame.new(x, y0 + 24, -34), Color = gold, Material = M.Metal })
		b.deco({ Name = "PylonTrim2", Size = Vector3.new(5.4, 1, 5.4), CFrame = CFrame.new(x, y0 + 2, -34), Color = gold, Material = M.Metal })
		-- Door leaves swung open against the pylons.
		local side = if x < 0 then -1 else 1
		b.part({ Name = "GrandDoor", Size = Vector3.new(1.4, 20, 12), CFrame = CFrame.new(x + side * 1.4, y0 + 10, -27.5), Color = rgb(70, 62, 56), Material = M.DiamondPlate })
		for i = 0, 3 do
			b.deco({ Name = "DoorBolt", Size = Vector3.new(1.6, 1, 1), CFrame = CFrame.new(x + side * 2.2, y0 + 4 + i * 4, -23) * UP, Color = gold, Material = M.Metal, Shape = Enum.PartType.Cylinder })
		end
		reserve(ctx, x - 3, x + 3, -37, -21)
	end
	b.deco({ Name = "EntranceLintel", Size = Vector3.new(35, 4, 5), CFrame = CFrame.new(0, y0 + 26, -34), Color = black, Material = M.Marble })
	b.deco({ Name = "LintelGold", Size = Vector3.new(35.4, 0.8, 5.4), CFrame = CFrame.new(0, y0 + 24.4, -34), Color = gold, Material = M.Metal })
	Props.sign(b, facing(Vector3.new(0, y0 + 26.2, -36.6), -Z), 22, 2.4, "LEGENDARY RESERVE", { Color = gold, PPS = 30, Back = black })
	-- Red carpet up the aisle.
	local carpetLen = BACK + 28
	b.deco({ Name = "Carpet", Size = Vector3.new(9, 0.08, carpetLen), CFrame = CFrame.new(0, y0 + 0.05, -30 + carpetLen / 2), Color = rgb(150, 24, 40), Material = M.Fabric, CastShadow = false })
	for _, x in ipairs({ -4.6, 4.6 }) do
		b.deco({ Name = "CarpetEdge", Size = Vector3.new(0.3, 0.1, carpetLen), CFrame = CFrame.new(x, y0 + 0.06, -30 + carpetLen / 2), Color = gold, Material = M.Metal, CastShadow = false })
	end
	-- Gold columns.
	for _, z in ipairs({ -14, 6, 44 }) do
		for _, x in ipairs({ -26, 26 }) do
			b.cyl({ Name = "GoldColumn", Size = Vector3.new(26, 2.4, 2.4), CFrame = CFrame.new(x, y0 + 13, z) * UP, Color = gold, Material = M.Metal, Reflectance = 0.2 })
			b.part({ Name = "ColumnFoot", Size = Vector3.new(3.4, 1.4, 3.4), CFrame = CFrame.new(x, y0 + 0.7, z), Color = black, Material = M.Marble })
			reserve(ctx, x - 2, x + 2, z - 2, z + 2)
		end
	end
	-- Treasure heaps on the side walls behind velvet ropes (decor).
	for _, x in ipairs({ -(W2 - 9), W2 - 9 }) do
		for _, z in ipairs({ -14, 16, 44 }) do
			local base = CFrame.new(x, y0, z)
			b.part({ Name = "Heap", Size = Vector3.new(8, 3, 8), CFrame = base * CFrame.new(0, 0.6, 0), Color = gold, Material = M.Metal, Shape = Enum.PartType.Ball, Reflectance = 0.2 })
			decoLoot(ctx, if z == 16 then "Crown" else "Chalice", base * CFrame.new(0, 2.3, -1))
			for _, dz in ipairs({ -5, 5 }) do
				b.part({ Name = "RopePost", Size = Vector3.new(0.4, 3, 0.4), CFrame = CFrame.new(x - math.sign(x) * 5, y0 + 1.5, z + dz), Color = gold, Material = M.Metal })
			end
			b.deco({ Name = "Rope", Size = Vector3.new(0.2, 0.2, 10), CFrame = CFrame.new(x - math.sign(x) * 5, y0 + 2.6, z), Color = rgb(150, 24, 40), Material = M.Fabric })
		end
	end
	reserve(ctx, -W2, -W2 + 15, -40, BACK)
	reserve(ctx, W2 - 15, W2, -40, BACK)
	-- Gold plinths: loot points.
	for _, x in ipairs({ -40, 40 }) do
		for _, z in ipairs({ -4, 26, 48 }) do
			local cf = CFrame.new(x, y0, z)
			b.part({ Name = "GoldPlinth", Size = Vector3.new(3.6, 3, 3.6), CFrame = cf * CFrame.new(0, 1.5, 0), Color = black, Material = M.Marble })
			b.deco({ Name = "GoldPlinthTop", Size = Vector3.new(3.8, 0.2, 3.8), CFrame = cf * CFrame.new(0, 3.05, 0), Color = gold, Material = M.Metal })
			point(ctx, cf * CFrame.new(0, 3.15, 0), "M", "Plinth")
			reserve(ctx, x - 2.4, x + 2.4, z - 2.4, z + 2.4)
		end
	end
	-- Landmark: a tiered treasure dais with a golden chest and shafts of light.
	local base = CFrame.new(0, y0, 22)
	for i, d in ipairs({ 20, 15, 10 }) do
		b.cyl({ Name = "DaisTier" .. i, Size = Vector3.new(1.2, d, d), CFrame = base * CFrame.new(0, 0.6 + (i - 1) * 1.2, 0) * UP, Color = if i % 2 == 1 then black else rgb(40, 34, 46), Material = M.Marble })
		b.cyl({ Name = "DaisRim" .. i, Size = Vector3.new(0.25, d + 0.2, d + 0.2), CFrame = base * CFrame.new(0, 1.15 + (i - 1) * 1.2, 0) * UP, Color = gold, Material = M.Metal, CanCollide = false })
	end
	decoLoot(ctx, "TreasureHoard", base * CFrame.new(0, 3.6, 0), 2)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2
		b.cyl({ Name = "LightShaft", Size = Vector3.new(24, 1.6, 1.6), CFrame = base * CFrame.new(math.cos(a) * 6, 15, math.sin(a) * 6) * UP, Color = rgb(255, 220, 140), Material = M.Neon, Transparency = 0.82, CanCollide = false, CastShadow = false })
	end
	local crown = b.deco({ Name = "DaisLight", Size = Vector3.new(3, 0.3, 3), CFrame = base * CFrame.new(0, 27.6, 0), Color = rgb(255, 220, 140), Material = M.Neon })
	light(crown, "SpotLight", rgb(255, 214, 140), 3, 34, true)
	for _, x in ipairs({ -9, 9 }) do
		b.part({ Name = "StatuePlinth", Size = Vector3.new(3, 3, 3), CFrame = base * CFrame.new(x, 1.5, -11), Color = black, Material = M.Marble })
		decoLoot(ctx, "AncientIdol", base * CFrame.new(x, 3, -11), 1.6)
	end
	reserve(ctx, -11, 11, 10, 33)
	ctx.landmark = base
	ctx.rarePoint = base * CFrame.new(0, 0, -15)
	emitter(ctx, Vector3.new(0, y0 + 20, 22), "ElectricalHum")
	emitter(ctx, Vector3.new(50, y0 + 24, 0), "Machinery")
end

local BUILDERS = { cashVault, goldReserve, diamondChamber, emeraldReserve, platinumReserve, artifactChamber, legendaryReserve }

function Themes.build(ctx)
	local fn = BUILDERS[ctx.def.Depth]
	if fn then
		fn(ctx)
	end
	-- The preview chamber shows the next depth's loot on its plinths (decor).
	local LootConfig = require(Shared.Config.LootConfig)
	local nextPool = ctx.preview and ctx.preview.nextDepth and LootConfig.ByDepth[ctx.preview.nextDepth]
	if ctx.preview then
		for i, cf in ipairs(ctx.preview.cframes) do
			if nextPool then
				local def = nextPool[math.min(#nextPool, i + 1)]
				decoLoot(ctx, def.Id, cf)
			else
				-- Beyond B7: the sealed Ancient Vault, shown as stone silhouettes.
				local idol = decoLoot(ctx, "AncientIdol", cf)
				for _, p in ipairs(idol:GetDescendants()) do
					if p:IsA("BasePart") then
						p.Color = rgb(110, 104, 96)
						p.Material = M.Slate
					end
				end
			end
		end
	end
end

return Themes
