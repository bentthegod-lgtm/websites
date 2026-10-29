--[[
	Themes - the classic columned chambers of B6 and B7 (B1-B5 have their own floor plans in
	Plans.lua), the shared helpers both use, per-depth materials, and the preview rooms.

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

local M = Enum.Material
local rgb = Color3.fromRGB
local Z = Vector3.zAxis
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

-- B1-B5 have their own floor plans (Plans.lua); the classic chamber themes are B6 and B7.
local BUILDERS = { [6] = artifactChamber, [7] = legendaryReserve }

-- Shared helpers (Plans.lua builds B1-B5 with them).
Themes.helpers = { point = point, reserve = reserve, emitter = emitter, light = light, decoLoot = decoLoot }

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
