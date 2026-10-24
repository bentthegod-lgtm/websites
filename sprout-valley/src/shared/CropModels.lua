--[[
	Procedural crop models, built entirely from parts.

	CropModels.build(crop, stage, baseCFrame, opts) -> Model
	  stage 1 Sprout, 2 Small, 3 Full, 4 Ripe (fruit + sparkles)
	  opts.mutations (list), opts.variant ("Golden"/"Rainbow"), opts.seed (number, jitter),
	  opts.lucky (Lucky Fertilizer applied: green sparkles)

	Every crop's Model.Type picks an archetype below; colours and flags come from
	CropConfig. All parts are anchored, non-colliding (players walk through gardens) and
	queryable so clicks/taps on a plant reach its tile. The invisible "Base" part is the
	PrimaryPart and footprint. These are placeholders for Blender meshes (see POLISH.md).
]]

local Config = script.Parent:WaitForChild("Config")
local MutationConfig = require(Config.MutationConfig)
local Rng = require(script.Parent.Rng)

local CropModels = {}

local SOIL = Color3.fromRGB(110, 76, 48)

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function material(name, fallback)
	if name then
		local ok, value = pcall(function()
			return Enum.Material[name]
		end)
		if ok and value then
			return value
		end
	end
	return fallback or Enum.Material.SmoothPlastic
end

local function newContext(model, baseCFrame, crop, stage, seed)
	local ctx = {
		model = model,
		base = baseCFrame,
		crop = crop,
		spec = crop.Model,
		stage = stage,
		ripe = stage >= 4,
		s = if stage == 2 then 0.55 else 1,
		fruits = {},
		rng = Rng.new(seed or 1),
		parts = 0,
	}
	ctx.leafColor = rgb(ctx.spec.Leaf)
	ctx.fruitColor = rgb(ctx.spec.Fruit)
	ctx.leafMaterial = material(ctx.spec.LeafMaterial, Enum.Material.SmoothPlastic)

	local function finish(p, color, mat, localCFrame, name)
		p.Name = name or "Part"
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = true
		p.CastShadow = ctx.parts < 12
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.CFrame = baseCFrame * localCFrame
		p.Parent = model
		ctx.parts += 1
		return p
	end

	function ctx.block(size, localCFrame, color, mat, name)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Block
		p.Size = size
		return finish(p, color, mat, localCFrame, name)
	end

	function ctx.ball(d, localCFrame, color, mat, name)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(d, d, d)
		return finish(p, color, mat, localCFrame, name)
	end

	-- Ellipsoid: a block with a sphere mesh stretched to its size.
	function ctx.ell(size, localCFrame, color, mat, name)
		local p = ctx.block(size, localCFrame, color, mat, name)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		return p
	end

	-- Vertical cylinder centred on localCFrame.
	function ctx.cyl(height, d, localCFrame, color, mat, name)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(height, d, d)
		return finish(p, color, mat, localCFrame * CFrame.Angles(0, 0, math.pi / 2), name)
	end

	function ctx.fruit(p)
		table.insert(ctx.fruits, p)
		return p
	end

	function ctx.jitter(amount)
		return (ctx.rng:NextNumber() - 0.5) * 2 * amount
	end

	return ctx
end

local L = CFrame.new
local A = CFrame.Angles
local rad = math.rad

---------------------------------------------------------------------------------------------
-- Archetypes
---------------------------------------------------------------------------------------------

local function sprout(ctx)
	ctx.ell(Vector3.new(1.3, 0.3, 1.3), L(0, 0.05, 0), SOIL:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Ground, "Mound")
	ctx.cyl(0.55, 0.12, L(0, 0.3, 0), ctx.leafColor:Lerp(Color3.new(1, 1, 1), 0.15))
	ctx.ell(Vector3.new(0.55, 0.08, 0.32), L(0.24, 0.58, 0) * A(0, 0, rad(25)), ctx.leafColor, ctx.leafMaterial, "Leaf")
	ctx.ell(Vector3.new(0.55, 0.08, 0.32), L(-0.24, 0.58, 0) * A(0, 0, rad(-25)), ctx.leafColor, ctx.leafMaterial, "Leaf")
end

local Archetypes = {}

function Archetypes.Root(ctx)
	local s, spec = ctx.s, ctx.spec
	local count = 5
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + ctx.jitter(0.3)
		ctx.ell(Vector3.new(0.22 * s, 1.5 * s, 0.55 * s), L(0, 0, 0) * A(0, a, 0) * L(0, 0.75 * s, 0.22 * s) * A(rad(18), 0, 0), ctx.leafColor, ctx.leafMaterial, "Leaf")
	end
	if ctx.ripe or ctx.stage == 3 then
		local grow = if ctx.ripe then 1 else 0.6
		if spec.Round then
			ctx.fruit(ctx.ball(1.0 * grow, L(0, 0.25 * grow, 0), ctx.fruitColor, if spec.Crystal then Enum.Material.Glass else nil, "Fruit"))
		else
			ctx.fruit(ctx.cyl(0.5 * grow, 0.8 * grow, L(0, 0.15, 0), ctx.fruitColor, nil, "Fruit"))
		end
		if spec.Crystal and ctx.ripe then
			for i = 1, 3 do
				local a = i * math.pi * 2 / 3
				ctx.fruit(ctx.block(Vector3.new(0.22, 0.9, 0.22), L(0, 0, 0) * A(0, a, 0) * L(0.45, 0.45, 0) * A(0, 0, rad(-25)), ctx.fruitColor:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Neon, "Shard"))
			end
		end
	end
end

function Archetypes.Leafy(ctx)
	local s = ctx.s
	for i = 1, 7 do
		local a = (i / 7) * math.pi * 2 + ctx.jitter(0.2)
		ctx.ell(Vector3.new(1.2 * s, 0.35 * s, 0.8 * s), A(0, a, 0) * L(0.55 * s, 0.25 * s, 0) * A(0, 0, rad(25)), ctx.leafColor, ctx.leafMaterial, "Leaf")
	end
	if ctx.stage >= 3 then
		local d = if ctx.ripe then 1.4 else 0.9
		local head = ctx.ball(d, L(0, d * 0.45, 0), ctx.fruitColor, Enum.Material.SmoothPlastic, "Head")
		if ctx.ripe then
			ctx.fruit(head)
			ctx.ell(Vector3.new(1.0, 0.5, 1.0), L(0, d * 0.85, 0), ctx.fruitColor:Lerp(Color3.new(1, 1, 1), 0.25), nil, "Heart")
		end
	end
end

function Archetypes.Bush(ctx)
	local s, spec = ctx.s, ctx.spec
	local lift = if spec.Floating then 1.0 * s else 0
	local leafMat = if spec.Floating then Enum.Material.SmoothPlastic else ctx.leafMaterial
	local balls = {
		{ L(0, 0.85 * s + lift, 0), 1.7 * s },
		{ L(0.65 * s, 0.6 * s + lift, 0.2 * s), 1.2 * s },
		{ L(-0.6 * s, 0.6 * s + lift, 0.3 * s), 1.2 * s },
		{ L(0.1 * s, 0.6 * s + lift, -0.65 * s), 1.2 * s },
	}
	if spec.Floating then
		ctx.cyl(1.2 * s, 0.12, L(0, 0.6 * s, 0), Color3.fromRGB(200, 200, 215))
	end
	for _, b in ipairs(balls) do
		local p = ctx.ball(b[2], b[1], ctx.leafColor, leafMat, "Leaves")
		if spec.Floating then
			p.Transparency = 0.1
		elseif spec.LeafMaterial == "Glass" then
			p.Transparency = 0.25
		end
	end
	if ctx.ripe then
		local count = spec.FruitCount or 6
		for i = 1, count do
			local a = (i / count) * math.pi * 2 + ctx.jitter(0.25)
			local y = 0.45 + ctx.rng:NextNumber() * 0.7 + lift
			local r = 0.95 + ctx.jitter(0.1)
			ctx.fruit(ctx.ball(spec.FruitSize or 0.4, L(math.cos(a) * r, y, math.sin(a) * r), ctx.fruitColor, if spec.Glow then Enum.Material.Neon else nil, "Fruit"))
		end
	end
end

function Archetypes.Stake(ctx)
	local s, spec = ctx.s, ctx.spec
	local h = 2.8 * s
	ctx.block(Vector3.new(0.18, h + 0.4, 0.18), L(0.05, h / 2, 0.05), Color3.fromRGB(150, 110, 70), Enum.Material.Wood, "Stake")
	ctx.cyl(h, 0.14, L(0, h / 2, 0), ctx.leafColor:Lerp(Color3.new(0, 0, 0), 0.15))
	for i = 1, 5 do
		local side = if i % 2 == 0 then 1 else -1
		local y = (0.5 + (i - 1) * 0.5) * s
		ctx.ell(Vector3.new(0.9 * s, 0.45 * s, 0.7 * s), L(side * 0.38 * s, y, ctx.jitter(0.25) * s) * A(0, 0, rad(-20 * side)), ctx.leafColor, ctx.leafMaterial, "Leaf")
	end
	ctx.ball(0.9 * s, L(0, h + 0.1, 0), ctx.leafColor, ctx.leafMaterial, "Top")
	if ctx.ripe then
		local fs = spec.FruitSize or 0.5
		for i = 1, 4 do
			local a = i * math.pi / 2 + 0.4
			local pos = Vector3.new(math.cos(a) * 0.6, 0.9 + (i % 2) * 0.8, math.sin(a) * 0.6)
			if spec.Bunches then
				for k = 0, 4 do
					local row = if k < 3 then 0 else 1
					local ox = if k < 3 then (k - 1) * fs * 0.9 else (k - 3.5) * fs * 0.9
					ctx.fruit(ctx.ball(fs, L(pos.X + ox, pos.Y - row * fs * 0.8, pos.Z), ctx.fruitColor, nil, "Grape"))
				end
			else
				local mat = if spec.Ember then Enum.Material.Neon else nil
				ctx.fruit(ctx.ell(Vector3.new(fs, fs * (if spec.Ember then 1.6 else 1.05), fs), L(pos.X, pos.Y, pos.Z), ctx.fruitColor, mat, "Fruit"))
				ctx.block(Vector3.new(0.08, 0.2, 0.08), L(pos.X, pos.Y + fs * 0.6, pos.Z), Color3.fromRGB(60, 120, 40), nil, "Stem")
			end
		end
	end
end

function Archetypes.Stalk(ctx)
	local s = ctx.s
	for k, x in ipairs({ -0.55, 0.55 }) do
		local h = (3.0 + k * 0.3) * s
		ctx.cyl(h, 0.22, L(x, h / 2, 0), ctx.leafColor:Lerp(Color3.new(0, 0, 0), 0.1), nil, "Stalk")
		for i = 1, 3 do
			local a = i * 2.1 + k
			ctx.block(Vector3.new(0.06, 1.7 * s, 0.35 * s), L(x, (0.8 + i * 0.6) * s, 0) * A(0, a, 0) * L(0, 0, 0.35 * s) * A(rad(45), 0, 0), ctx.leafColor, ctx.leafMaterial, "Leaf")
		end
		ctx.block(Vector3.new(0.1, 0.5 * s, 0.1), L(x, h + 0.2 * s, 0), Color3.fromRGB(220, 200, 120), nil, "Tassel")
		if ctx.ripe then
			local cobCf = L(x, h * 0.55, 0) * A(0, k * 2, 0) * L(0, 0, 0.3) * A(rad(-30), 0, 0)
			ctx.fruit(ctx.cyl(1.0, 0.4, cobCf, ctx.fruitColor, Enum.Material.Pebble, "Cob"))
			ctx.block(Vector3.new(0.45, 0.8, 0.12), cobCf * L(0, -0.25, -0.15), ctx.leafColor:Lerp(Color3.new(1, 1, 0.6), 0.3), nil, "Husk")
		end
	end
end

function Archetypes.Ground(ctx)
	local s, spec = ctx.s, ctx.spec
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2 + ctx.jitter(0.3)
		ctx.ell(Vector3.new(1.3 * s, 0.25 * s, 1.0 * s), A(0, a, 0) * L(1.0 * s, 0.15, 0) * A(0, 0, rad(10)), ctx.leafColor, ctx.leafMaterial, "Leaf")
	end
	ctx.cyl(0.1, 2.6 * s, L(0, 0.05, 0), ctx.leafColor:Lerp(Color3.new(0, 0, 0), 0.25), nil, "Vines")
	if ctx.stage < 3 then
		return
	end
	local fs = (spec.FruitSize or 2) * (if ctx.ripe then 1 else 0.45)
	local color = if ctx.ripe then ctx.fruitColor else ctx.leafColor:Lerp(ctx.fruitColor, 0.3)
	local size = if spec.Long then Vector3.new(fs * 0.75, fs * 0.65, fs * 1.15) else Vector3.new(fs, fs * 0.75, fs)
	local centre = L(0.1, size.Y * 0.5, 0.1)
	local mat = if spec.Glow and ctx.ripe then Enum.Material.Glass else nil
	local body = ctx.ell(size, centre, color, mat, "Fruit")
	if ctx.ripe then
		ctx.fruit(body)
	end
	if spec.Ribbed then
		for i = 1, 3 do
			local rib = ctx.ell(Vector3.new(size.X * 0.45, size.Y * 0.98, size.Z * 1.02), centre * A(0, i * math.pi / 3, 0), color:Lerp(Color3.new(0.5, 0.2, 0), 0.12), nil, "Rib")
			if ctx.ripe then
				ctx.fruit(rib)
			end
		end
		ctx.cyl(0.5, 0.25, centre * L(0, size.Y * 0.5 + 0.15, 0), Color3.fromRGB(100, 80, 40), Enum.Material.Wood, "Stem")
	end
	if spec.Long and spec.Accent then
		for i = -1, 1 do
			local stripe = ctx.ell(Vector3.new(size.X * 0.25, size.Y * 1.02, size.Z * 1.01), centre * L(i * size.X * 0.3, 0, 0), rgb(spec.Accent), nil, "Stripe")
			if ctx.ripe then
				ctx.fruit(stripe)
			end
		end
	end
	if spec.Craters and ctx.ripe then
		for i = 1, 5 do
			local a = i * 1.3
			local dir = Vector3.new(math.cos(a), 0.4 + (i % 2) * 0.35, math.sin(a)).Unit
			ctx.ball(fs * 0.22, centre * L(dir.X * size.X * 0.45, dir.Y * size.Y * 0.45, dir.Z * size.Z * 0.45), rgb(spec.Accent or { 150, 160, 200 }), nil, "Crater")
		end
	end
end

function Archetypes.Cactus(ctx)
	local s, spec = ctx.s, ctx.spec
	local h = 2.4 * s
	ctx.cyl(h, 0.85 * s, L(0, h / 2, 0), ctx.leafColor, ctx.leafMaterial, "Body")
	ctx.ball(0.85 * s, L(0, h, 0), ctx.leafColor, ctx.leafMaterial, "Top")
	local arms = spec.Arms or 2
	local tips = { L(0, h + 0.35 * s, 0) }
	for i = 1, arms do
		local a = i * (math.pi * 2 / arms) + 0.5
		local out = A(0, a, 0)
		local y = (1.0 + (i % 2) * 0.4) * s
		ctx.block(Vector3.new(0.55 * s, 0.45 * s, 0.45 * s), out * L(0.55 * s, y, 0), ctx.leafColor, ctx.leafMaterial, "Arm")
		ctx.cyl(0.9 * s, 0.45 * s, out * L(0.8 * s, y + 0.4 * s, 0), ctx.leafColor, ctx.leafMaterial, "Arm")
		ctx.ball(0.45 * s, out * L(0.8 * s, y + 0.85 * s, 0), ctx.leafColor, ctx.leafMaterial, "ArmTop")
		table.insert(tips, out * L(0.8 * s, y + 1.05 * s, 0))
	end
	for i = 1, 6 do
		local a = i * 1.05
		ctx.block(Vector3.new(0.05, 0.05, 0.25), L(math.cos(a) * 0.43 * s, (0.4 + (i % 3) * 0.6) * s, math.sin(a) * 0.43 * s) * A(0, -a, 0), Color3.fromRGB(245, 240, 210), nil, "Spine")
	end
	if ctx.ripe then
		local fs = spec.FruitSize or 0.5
		for _, tip in ipairs(tips) do
			ctx.fruit(ctx.ell(Vector3.new(fs, fs * 1.3, fs), tip * L(0, fs * 0.4, 0), ctx.fruitColor, nil, "Fruit"))
			if spec.Accent then
				ctx.block(Vector3.new(fs * 0.25, fs * 0.5, 0.08), tip * L(fs * 0.45, fs * 0.5, 0) * A(0, 0, rad(-30)), rgb(spec.Accent), nil, "Scale")
			end
		end
	end
end

local function hueColor(i, count)
	return Color3.fromHSV(((i - 1) / math.max(count, 1)) % 1, 0.55, 1)
end

function Archetypes.Tree(ctx)
	local s, spec = ctx.s, ctx.spec
	local trunk = rgb(spec.Trunk or { 120, 80, 50 })
	local h = 2.6 * s
	ctx.cyl(h, 0.55 * s, L(0, h / 2, 0), trunk, Enum.Material.Wood, "Trunk")
	ctx.cyl(0.3, 0.8 * s, L(0, 0.1, 0), trunk, Enum.Material.Wood, "Roots")
	ctx.block(Vector3.new(0.9 * s, 0.22 * s, 0.22 * s), L(0.3 * s, h * 0.75, 0) * A(0, 0, rad(35)), trunk, Enum.Material.Wood, "Branch")
	local leafMat = if spec.LeafMaterial then ctx.leafMaterial else Enum.Material.Grass
	local canopy = {
		{ L(0, h + 0.7 * s, 0), 2.5 * s },
		{ L(0.85 * s, h + 0.25 * s, 0.3 * s), 1.8 * s },
		{ L(-0.8 * s, h + 0.3 * s, 0.4 * s), 1.8 * s },
		{ L(0, h + 0.25 * s, -0.85 * s), 1.8 * s },
	}
	for _, c in ipairs(canopy) do
		local p = ctx.ball(c[2], c[1], ctx.leafColor, leafMat, "Canopy")
		if spec.LeafMaterial == "Glass" then
			p.Transparency = 0.2
		end
	end
	if ctx.ripe then
		local count = if spec.Star then 4 else 6
		local fs = spec.FruitSize or 0.5
		for i = 1, count do
			local a = (i / count) * math.pi * 2 + 0.3
			local r = 1.25 * s
			local pos = L(math.cos(a) * r, h - 0.05 + (i % 2) * 0.5, math.sin(a) * r)
			local color = if spec.Prism then hueColor(i, count) else ctx.fruitColor
			if spec.Accent and i % 2 == 0 then
				color = color:Lerp(rgb(spec.Accent), 0.4)
			end
			if spec.Star then
				ctx.fruit(ctx.ball(fs * 0.55, pos, color, Enum.Material.Neon, "Fruit"))
				for k = 0, 2 do
					ctx.fruit(ctx.block(Vector3.new(fs * 1.3, fs * 0.28, fs * 0.28), pos * A(0, 0, k * math.pi / 3), color, nil, "Point"))
				end
			else
				local size = if spec.Oval then Vector3.new(fs * 0.8, fs * 1.15, fs * 0.8) else Vector3.new(fs, fs, fs)
				ctx.fruit(ctx.ell(size, pos, color, if spec.Prism then Enum.Material.Glass else nil, "Fruit"))
				ctx.block(Vector3.new(0.06, 0.18, 0.06), pos * L(0, size.Y * 0.55, 0), trunk, nil, "Stem")
			end
		end
	end
end

function Archetypes.Palm(ctx)
	local s, spec = ctx.s, ctx.spec
	local trunk = rgb(spec.Trunk or { 160, 120, 80 })
	local y, x = 0, 0
	for i = 1, 5 do
		local seg = 0.75 * s
		ctx.cyl(seg, (0.6 - i * 0.04) * s, L(x, y + seg / 2, 0) * A(0, 0, rad(-4 * i)), trunk:Lerp(Color3.new(0, 0, 0), (i % 2) * 0.12), Enum.Material.Wood, "Trunk")
		y += seg * 0.95
		x += 0.07 * i * s
	end
	local top = L(x, y, 0)
	for i = 1, 7 do
		local a = i * math.pi * 2 / 7
		ctx.block(Vector3.new(0.55 * s, 0.08, 2.3 * s), top * A(0, a, 0) * A(rad(-28), 0, 0) * L(0, 0, 1.05 * s), ctx.leafColor, ctx.leafMaterial, "Frond")
	end
	ctx.ball(0.6 * s, top, ctx.leafColor:Lerp(Color3.new(0, 0, 0), 0.2), nil, "Crown")
	if ctx.ripe then
		local fs = spec.FruitSize or 0.7
		for i = 1, 3 do
			local a = i * math.pi * 2 / 3
			ctx.fruit(ctx.ball(fs, top * L(math.cos(a) * 0.4, -0.45, math.sin(a) * 0.4), ctx.fruitColor, Enum.Material.Wood, "Coconut"))
		end
	end
end

function Archetypes.Mushroom(ctx)
	local s, spec = ctx.s, ctx.spec
	local shrooms = { { 0, 0, 1.3, 1.3 }, { 0.75, 0.4, 0.9, 0.9 }, { -0.6, -0.5, 0.7, 0.75 } }
	for _, m in ipairs(shrooms) do
		local h = m[3] * s
		ctx.cyl(h, 0.28 * m[4] * s, L(m[1] * s, h / 2, m[2] * s), ctx.leafColor, nil, "Stem")
		local capColor = if ctx.stage >= 3 then ctx.fruitColor else ctx.fruitColor:Lerp(Color3.new(0.3, 0.3, 0.35), 0.5)
		local cap = ctx.ell(Vector3.new(1.2 * m[4] * s, 0.55 * m[4] * s, 1.2 * m[4] * s), L(m[1] * s, h + 0.05, m[2] * s), capColor, if ctx.ripe then Enum.Material.Neon else nil, "Cap")
		if ctx.ripe then
			ctx.fruit(cap)
		end
		ctx.ball(0.16 * s, L(m[1] * s + 0.25 * m[4], h + 0.25 * m[4] * s, m[2] * s), Color3.fromRGB(255, 255, 255), if spec.Glow then Enum.Material.Neon else nil, "Spot")
	end
end

function Archetypes.Rosette(ctx)
	local s, spec = ctx.s, ctx.spec
	for i = 1, 9 do
		local a = i * math.pi * 2 / 9
		ctx.block(Vector3.new(0.28 * s, 1.5 * s, 0.1), A(0, a, 0) * L(0, 0.6 * s, 0.35 * s) * A(rad(38), 0, 0), ctx.leafColor, ctx.leafMaterial, "Spike")
	end
	if ctx.stage < 3 then
		return
	end
	local fs = (spec.FruitSize or 1.1) * (if ctx.ripe then 1 else 0.55)
	local color = if ctx.ripe then ctx.fruitColor else ctx.leafColor:Lerp(ctx.fruitColor, 0.4)
	local body = ctx.ell(Vector3.new(fs * 0.85, fs * 1.15, fs * 0.85), L(0, 0.35 + fs * 0.55, 0), color, Enum.Material.Pebble, "Fruit")
	if ctx.ripe then
		ctx.fruit(body)
	end
	for i = 1, 5 do
		local a = i * math.pi * 2 / 5
		ctx.block(Vector3.new(0.18, 0.7 * fs, 0.06), L(0, 0.35 + fs * 1.15, 0) * A(0, a, 0) * L(0, 0.2, 0.08) * A(rad(25), 0, 0), ctx.leafColor, nil, "Crown")
	end
end

function Archetypes.Lotus(ctx)
	local s, spec = ctx.s, ctx.spec
	local water = ctx.cyl(0.12, 3.3, L(0, 0.06, 0), Color3.fromRGB(110, 190, 230), Enum.Material.Glass, "Pond")
	water.Transparency = 0.3
	for i = 1, 3 do
		local a = i * 2.1
		ctx.cyl(0.06, 1.2 * s, L(math.cos(a) * 0.95, 0.16, math.sin(a) * 0.95), ctx.leafColor, nil, "Pad")
	end
	if ctx.stage < 3 then
		ctx.ell(Vector3.new(0.35 * s, 0.6 * s, 0.35 * s), L(0, 0.4, 0), rgb(spec.Accent or spec.Fruit), nil, "Bud")
		return
	end
	if not ctx.ripe then
		ctx.ell(Vector3.new(0.7, 1.1, 0.7), L(0, 0.7, 0), rgb(spec.Accent or spec.Fruit), nil, "Bud")
		return
	end
	for ring = 1, 2 do
		local n = if ring == 1 then 8 else 6
		for i = 1, n do
			local a = i * math.pi * 2 / n + ring * 0.3
			local petalColor = if ring == 1 then ctx.fruitColor else ctx.fruitColor:Lerp(Color3.new(1, 1, 1), 0.5)
			ctx.fruit(ctx.ell(Vector3.new(0.6, 0.15, 1.5 - ring * 0.3), L(0, 0.35 + ring * 0.1, 0) * A(0, a, 0) * L(0, 0, 0.5) * A(rad(-25 - ring * 15), 0, 0), petalColor, nil, "Petal"))
		end
	end
	ctx.fruit(ctx.ball(0.6, L(0, 0.7, 0), rgb(spec.Accent or { 255, 240, 150 }), Enum.Material.Neon, "Heart"))
end

---------------------------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------------------------

local function colorSequence(colors)
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for i, c in ipairs(colors) do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(keys)
end

local function emitter(parent, name, colors, rate, size)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Color = colorSequence(colors)
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.8, 1.6)
	e.Speed = NumberRange.new(0.6, 1.6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.1)
	e.Acceleration = Vector3.new(0, 1.5, 0)
	e.Parent = parent
	return e
end

local TINTS = {
	Wet = { 0.12, nil, 0.25 },
	Chilled = { 0.3, nil, 0 },
	Frozen = { 0.55, "Ice", 0 },
	Shocked = { 0.25, nil, 0 },
	Bloodlit = { 0.45, nil, 0 },
	Aurora = { 0.35, nil, 0 },
}

local function applyMutations(ctx, mutations, variant)
	local colors = {}
	for _, name in ipairs(mutations or {}) do
		local def = MutationConfig.Mutations[name]
		if def then
			local c = rgb(def.Color)
			table.insert(colors, c)
			local tint = TINTS[name]
			if tint then
				for _, f in ipairs(ctx.fruits) do
					f.Color = f.Color:Lerp(c, tint[1])
					if tint[2] then
						f.Material = material(tint[2])
					end
					if tint[3] > 0 then
						f.Reflectance = tint[3]
					end
				end
			end
		end
	end
	if variant == "Golden" then
		table.insert(colors, rgb(MutationConfig.Variants.Golden.Color))
		for _, f in ipairs(ctx.fruits) do
			f.Color = Color3.fromRGB(255, 200, 45)
			f.Material = Enum.Material.Foil
		end
	elseif variant == "Rainbow" then
		for i, f in ipairs(ctx.fruits) do
			f.Color = hueColor(i, #ctx.fruits)
			f.Material = Enum.Material.Neon
		end
		for i = 1, 4 do
			table.insert(colors, hueColor(i, 4))
		end
	end
	return colors
end

---------------------------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------------------------

function CropModels.build(crop, stage, baseCFrame, opts)
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = crop.Id
	local ctx = newContext(model, baseCFrame, crop, stage, opts.seed)

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(3.4, 0.2, 3.4)
	base.Transparency = 1
	base.Anchored = true
	base.CanCollide = false
	base.CanTouch = false
	base.CanQuery = true
	base.CFrame = baseCFrame * L(0, 0.1, 0)
	base.Parent = model
	model.PrimaryPart = base

	if stage <= 1 then
		sprout(ctx)
	else
		local builder = Archetypes[ctx.spec.Type] or Archetypes.Bush
		builder(ctx)
	end

	local auraColors = if stage >= 3 then applyMutations(ctx, opts.mutations, opts.variant) else {}
	if #auraColors > 0 then
		local aura = emitter(base, "Aura", auraColors, 4 + #auraColors * 2, 0.35)
		aura.Speed = NumberRange.new(0.3, 1)
		aura.Acceleration = Vector3.new(0, 2.5, 0)
	end
	if stage >= 4 then
		emitter(base, "Sparkle", { Color3.fromRGB(255, 255, 220), Color3.fromRGB(255, 240, 150) }, 3, 0.25)
	end
	if opts.lucky then
		local lucky = emitter(base, "Lucky", { Color3.fromRGB(120, 255, 120), Color3.fromRGB(220, 255, 160) }, 2, 0.22)
		lucky.Acceleration = Vector3.new(0, 3, 0)
	end
	if ctx.spec.Glow and stage >= 3 then
		local light = Instance.new("PointLight")
		light.Color = rgb(ctx.spec.Glow)
		light.Range = if stage >= 4 then 10 else 6
		light.Brightness = if stage >= 4 then 1.4 else 0.6
		light.Parent = base
	end
	if ctx.spec.Ember and stage >= 4 then
		local fire = emitter(base, "Embers", { Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 80, 30) }, 6, 0.2)
		fire.Acceleration = Vector3.new(0, 4, 0)
	end
	return model, ctx.fruits, ctx.parts
end

-- Small display-only version (seed packet / shop preview). Not used for gameplay.
function CropModels.archetypes()
	local list = {}
	for name in pairs(Archetypes) do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

return CropModels
