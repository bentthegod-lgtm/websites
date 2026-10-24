--[[
	BlobbyModels - builds a Blobby entirely from parts.

	Structure of a built model:
	  Model "Blobby"  (PrimaryPart = Root, attributes Species / Rarity / Mutation / Bob / Phase)
	    Root        invisible, anchored, at the feet. Servers move this.
	    Body        main body part, joined to Root by Motor6D "Bob" (pivot at the feet).
	                The client animates Bob.Transform (bounce, wobble, spin, ...).
	    ...         every other part is welded to Body (WeldConstraint), except spinning
	                parts (propeller, halo) which hang off a Motor6D named "Spinner".
	All parts are massless and non-colliding, so a model can be welded onto a character's
	head and carried around without affecting physics.

	Body-coloured parts have the attribute BodyPart = true (mutations recolour them and the
	client cycles their hue for Rainbow).
]]

local CollectionService = game:GetService("CollectionService")

local BlobbyModels = {}

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end
BlobbyModels.rgb = rgb

local function shade(color, k)
	return Color3.new(math.clamp(color.R * k, 0, 1), math.clamp(color.G * k, 0, 1), math.clamp(color.B * k, 0, 1))
end

local WHITE = Color3.fromRGB(250, 250, 250)
local BLACK = Color3.fromRGB(22, 20, 26)
local MOUTH = Color3.fromRGB(70, 22, 34)
local GOLD = Color3.fromRGB(255, 206, 64)
local PINK = Color3.fromRGB(255, 120, 150)

---------------------------------------------------------------------------------------------
-- Part helpers. Positions are given in "unscaled" studs relative to an origin CFrame and
-- multiplied by the builder scale.
---------------------------------------------------------------------------------------------

local function newPart(ctx, name, className, size, cframe, color, opts)
	opts = opts or {}
	local p = Instance.new(className)
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = opts.material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = opts.shadow ~= false
	p.Transparency = opts.transparency or 0
	p.Reflectance = opts.reflectance or 0
	if opts.body then
		p:SetAttribute("BodyPart", true)
		table.insert(ctx.bodyParts, p)
	end
	p.Parent = ctx.model
	table.insert(ctx.parts, p)
	if opts.weldTo ~= false then
		table.insert(ctx.toWeld, { part = p, to = opts.weldTo })
	end
	return p
end

-- Ellipsoid: a block with a sphere mesh that fills it.
local function ell(ctx, name, size, cframe, color, opts)
	local p = newPart(ctx, name, "Part", size, cframe, color, opts)
	p.Shape = Enum.PartType.Block
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Vertical cylinder (height along the frame's Y axis).
local function cyl(ctx, name, height, diameter, cframe, color, opts)
	local p = newPart(ctx, name, "Part", ctx.v(height, diameter, diameter), cframe * CFrame.Angles(0, 0, math.pi / 2), color, opts)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function block(ctx, name, size, cframe, color, opts)
	return newPart(ctx, name, "Part", size, cframe, color, opts)
end

---------------------------------------------------------------------------------------------
-- Body shapes. Each returns layout info in unscaled studs:
--   top, faceX, faceY, faceZ (front surface, negative), halfW, neckY, neckZ, back, headScale
---------------------------------------------------------------------------------------------

local Shapes = {}

function Shapes.Round(ctx, L, sp, bodyColor)
	ctx.main = ell(ctx, "Body", ctx.v(3.2, 3.0, 3.2), L(0, 1.6, 0), bodyColor, { body = true, weldTo = false })
	ctx.mainY = 1.6
	if sp.Belly then
		ell(ctx, "Belly", ctx.v(2.2, 1.9, 0.6), L(0, 1.25, -1.3), rgb(sp.Belly))
	end
	return { top = 3.1, faceX = 0, faceY = 1.95, faceZ = -1.45, halfW = 1.6, neckY = 0.85, neckZ = -1.45, back = 1.5, headScale = 1 }
end

function Shapes.Tall(ctx, L, sp, bodyColor)
	ctx.main = ell(ctx, "Body", ctx.v(2.6, 4.6, 2.6), L(0, 2.3, 0), bodyColor, { body = true, weldTo = false })
	ctx.mainY = 2.3
	if sp.Belly then
		ell(ctx, "Belly", ctx.v(1.7, 2.4, 0.5), L(0, 1.8, -1.08), rgb(sp.Belly))
	end
	return { top = 4.6, faceX = 0, faceY = 3.1, faceZ = -1.15, halfW = 1.3, neckY = 2.0, neckZ = -1.33, back = 1.25, headScale = 0.9 }
end

function Shapes.Flat(ctx, L, sp, bodyColor)
	ctx.main = ell(ctx, "Body", ctx.v(4.4, 1.8, 4.4), L(0, 0.9, 0), bodyColor, { body = true, weldTo = false })
	ctx.mainY = 0.9
	if sp.Belly then
		-- a pat of butter / syrup puddle on top
		cyl(ctx, "Topping", 0.25, 3.0, L(0, 1.72, 0.2), rgb(sp.Belly))
		block(ctx, "Butter", ctx.v(0.9, 0.4, 0.9), L(0.3, 1.95, 0.4) * CFrame.Angles(0, 0.5, 0), Color3.fromRGB(255, 236, 140))
	end
	return { top = 1.85, faceX = 0, faceY = 1.05, faceZ = -2.1, halfW = 2.2, neckY = 0.55, neckZ = -2.15, back = 2.1, headScale = 1, noFeet = true }
end

function Shapes.Spiky(ctx, L, sp, bodyColor)
	local info = Shapes.Round(ctx, L, sp, bodyColor)
	local accent = rgb(sp.Accent)
	local spikeMat = if sp.NeonAccent then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local count = 7
	for i = 0, count - 1 do
		local a = i * 2 * math.pi / count
		for _, e in ipairs({ math.rad(30), math.rad(62) }) do
			local dir = Vector3.new(math.sin(a) * math.cos(e), math.sin(e), math.cos(a) * math.cos(e))
			-- keep the face clear
			if not (dir.Z < -0.6 and e < 0.6) then
				local pos = Vector3.new(dir.X * 1.5, 1.6 + dir.Y * 1.42, dir.Z * 1.5)
				local cf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.Angles(0, math.pi / 4, 0)
				block(ctx, "Spike", ctx.v(0.5, 1.1, 0.5), L(0, 0, 0) * CFrame.new(cf.Position * ctx.s) * (cf - cf.Position), accent, { material = spikeMat })
			end
		end
	end
	if sp.Hat == "None" then
		block(ctx, "Spike", ctx.v(0.55, 1.3, 0.55), L(0, 3.3, 0) * CFrame.Angles(0, math.pi / 4, 0), accent, { material = spikeMat })
	end
	return info
end

function Shapes.Pear(ctx, L, sp, bodyColor)
	ctx.main = ell(ctx, "Body", ctx.v(3.4, 2.6, 3.4), L(0, 1.3, 0), bodyColor, { body = true, weldTo = false })
	ctx.mainY = 1.3
	ell(ctx, "Head", ctx.v(2.5, 2.2, 2.5), L(0, 3.1, 0), bodyColor, { body = true })
	if sp.Belly then
		ell(ctx, "Belly", ctx.v(2.4, 1.6, 0.6), L(0, 1.2, -1.45), rgb(sp.Belly))
	end
	return { top = 4.15, faceX = 0, faceY = 3.1, faceZ = -1.2, halfW = 1.7, neckY = 2.15, neckZ = -1.35, back = 1.6, headScale = 0.85 }
end

function Shapes.Cube(ctx, L, sp, bodyColor)
	local opts = { body = true, weldTo = false }
	if sp.Jelly then
		opts.material = Enum.Material.Glass
		opts.transparency = 0.3
		opts.reflectance = 0.15
	end
	ctx.main = block(ctx, "Body", ctx.v(3, 3, 3), L(0, 1.5, 0), bodyColor, opts)
	ctx.mainY = 1.5
	if sp.Jelly then
		ell(ctx, "Grape", ctx.v(1.0, 1.0, 1.0), L(0.4, 1.1, 0.3), Color3.fromRGB(120, 40, 160))
	else
		block(ctx, "Lid", ctx.v(3.1, 0.35, 3.1), L(0, 3.0, 0), shade(bodyColor, 1.15), { body = true })
	end
	return { top = 3.15, faceX = 0, faceY = 1.9, faceZ = -1.5, halfW = 1.5, neckY = 0.9, neckZ = -1.55, back = 1.5, headScale = 1 }
end

function Shapes.Noodle(ctx, L, sp, bodyColor)
	local segs = { { 0, 0.95, 1.9 }, { 0.35, 2.35, 1.8 }, { -0.25, 3.7, 1.75 } }
	for i, s in ipairs(segs) do
		local p = ell(ctx, if i == 1 then "Body" else "Segment", ctx.v(s[3], s[3], s[3]), L(s[1], s[2], 0), bodyColor, { body = true, weldTo = if i == 1 then false else nil })
		if i == 1 then
			ctx.main = p
			ctx.mainY = s[2]
		end
	end
	if sp.NeonAccent then
		for _, y in ipairs({ 1.65, 3.05 }) do
			cyl(ctx, "Ring", 0.2, 1.5, L(0.05, y, 0), rgb(sp.Accent), { material = Enum.Material.Neon })
		end
	end
	ell(ctx, "Head", ctx.v(2.3, 2.2, 2.3), L(0.1, 5.0, 0), bodyColor, { body = true })
	return { top = 6.05, faceX = 0.1, faceY = 5.0, faceZ = -1.1, halfW = 1.15, neckY = 4.0, neckZ = -1.0, back = 1.1, headScale = 0.8, armY = 2.4, noFeet = true }
end

function Shapes.Dumpling(ctx, L, _sp, bodyColor)
	ctx.main = ell(ctx, "Body", ctx.v(3.8, 2.4, 3.8), L(0, 1.2, 0), bodyColor, { body = true, weldTo = false })
	ctx.mainY = 1.2
	ell(ctx, "Pinch", ctx.v(1.3, 0.9, 1.3), L(0, 2.45, 0), bodyColor, { body = true })
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		ell(ctx, "Pleat", ctx.v(0.35, 0.5, 1.6), L(math.sin(a) * 0.75, 2.2, math.cos(a) * 0.75) * CFrame.Angles(0, a, 0) * CFrame.Angles(0.5, 0, 0), shade(bodyColor, 0.9), { body = true })
	end
	return { top = 2.85, faceX = 0, faceY = 1.25, faceZ = -1.78, halfW = 1.9, neckY = 0.6, neckZ = -1.75, back = 1.8, headScale = 0.8, noFeet = true }
end

---------------------------------------------------------------------------------------------
-- Eyes (and the mouth)
---------------------------------------------------------------------------------------------

local Eyes = {}

local function pupilColor(sp)
	return if sp.NeonAccent then rgb(sp.Accent) else BLACK
end
local function pupilMaterial(sp)
	return if sp.NeonAccent then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

local function smile(ctx, F, y)
	ell(ctx, "Mouth", ctx.v(0.9, 0.32, 0.3), F(0, y or -0.55, -0.02), MOUTH)
end

function Eyes.Googly(ctx, F, sp)
	for _, x in ipairs({ -0.5, 0.5 }) do
		ell(ctx, "Eye", ctx.v(0.95, 0.95, 0.6), F(x, 0.15, -0.05), WHITE)
		ell(ctx, "Pupil", ctx.v(0.45, 0.45, 0.3), F(x + x * 0.16, 0.08, -0.32), pupilColor(sp), { material = pupilMaterial(sp) })
	end
	smile(ctx, F)
end

function Eyes.Sleepy(ctx, F, sp, bodyColor)
	for _, x in ipairs({ -0.5, 0.5 }) do
		ell(ctx, "Eye", ctx.v(0.9, 0.8, 0.55), F(x, 0.12, -0.05), WHITE)
		ell(ctx, "Lid", ctx.v(1.0, 0.55, 0.66), F(x, 0.36, -0.1), shade(bodyColor, 0.85), { body = true })
		ell(ctx, "Pupil", ctx.v(0.4, 0.28, 0.28), F(x, 0.0, -0.3), pupilColor(sp), { material = pupilMaterial(sp) })
	end
	smile(ctx, F, -0.58)
end

function Eyes.Cyclops(ctx, F, sp)
	ell(ctx, "Eye", ctx.v(1.5, 1.5, 0.8), F(0, 0.25, -0.05), WHITE)
	ell(ctx, "Iris", ctx.v(0.8, 0.8, 0.4), F(0, 0.2, -0.38), rgb(sp.Accent), { material = pupilMaterial(sp) })
	ell(ctx, "Pupil", ctx.v(0.38, 0.38, 0.3), F(0, 0.2, -0.52), BLACK)
	smile(ctx, F, -0.72)
end

function Eyes.Tiny(ctx, F, sp)
	for _, x in ipairs({ -0.4, 0.4 }) do
		ell(ctx, "Pupil", ctx.v(0.32, 0.42, 0.25), F(x, 0.2, -0.05), pupilColor(sp), { material = pupilMaterial(sp) })
		ell(ctx, "Blush", ctx.v(0.45, 0.25, 0.15), F(x * 2.1, -0.18, 0.02), PINK)
	end
	smile(ctx, F, -0.4)
end

function Eyes.Angry(ctx, F, sp)
	for _, x in ipairs({ -0.5, 0.5 }) do
		ell(ctx, "Eye", ctx.v(0.9, 0.8, 0.55), F(x, 0.12, -0.05), WHITE)
		ell(ctx, "Pupil", ctx.v(0.42, 0.42, 0.3), F(x * 0.85, 0.08, -0.3), pupilColor(sp), { material = pupilMaterial(sp) })
		local tilt = if x < 0 then -0.38 else 0.38
		block(ctx, "Brow", ctx.v(0.8, 0.2, 0.22), F(x, 0.7, -0.22) * CFrame.Angles(0, 0, tilt), BLACK)
	end
	ell(ctx, "Mouth", ctx.v(1.0, 0.25, 0.3), F(0, -0.6, -0.02), MOUTH)
	block(ctx, "Tooth", ctx.v(0.22, 0.2, 0.1), F(0.18, -0.55, -0.16), WHITE)
end

function Eyes.Shades(ctx, F)
	for _, x in ipairs({ -0.48, 0.48 }) do
		block(ctx, "Lens", ctx.v(0.85, 0.55, 0.2), F(x, 0.2, -0.14), BLACK, { reflectance = 0.35 })
		block(ctx, "Shine", ctx.v(0.22, 0.12, 0.05), F(x - 0.18, 0.32, -0.26), WHITE, { material = Enum.Material.Neon })
	end
	block(ctx, "Bridge", ctx.v(0.3, 0.1, 0.15), F(0, 0.32, -0.14), BLACK)
	smile(ctx, F)
end

function Eyes.Stalks(ctx, F, sp)
	for _, x in ipairs({ -0.5, 0.5 }) do
		cyl(ctx, "Stalk", 1.3, 0.22, F(x, 1.05, 0.35) * CFrame.Angles(0, 0, -x * 0.4), shade(rgb(sp.Body), 0.85), { body = true })
		ell(ctx, "Eye", ctx.v(0.8, 0.8, 0.8), F(x * 1.25, 1.75, 0.3), WHITE)
		ell(ctx, "Pupil", ctx.v(0.36, 0.36, 0.25), F(x * 1.25, 1.75, -0.08), pupilColor(sp), { material = pupilMaterial(sp) })
	end
	smile(ctx, F, -0.3)
end

---------------------------------------------------------------------------------------------
-- Hats. T(x, y, z) is relative to the top of the head, scaled by headScale.
---------------------------------------------------------------------------------------------

local Hats = {}

local function spinner(ctx, hubCFrame, speed)
	local hub = block(ctx, "SpinnerHub", ctx.v(0.2, 0.2, 0.2), hubCFrame, WHITE, { transparency = 1, weldTo = false })
	table.insert(ctx.spinners, { hub = hub, speed = speed })
	return hub
end

function Hats.None() end

function Hats.Top(ctx, T, sp)
	local color = rgb(sp.Accent)
	cyl(ctx, "Brim", 0.15, 2.3, T(0, 0, 0), color)
	cyl(ctx, "Crown", 1.5, 1.5, T(0, 0.8, 0), color)
	cyl(ctx, "Band", 0.32, 1.56, T(0, 0.28, 0), Color3.fromRGB(220, 40, 60))
end

function Hats.Crown(ctx, T)
	cyl(ctx, "CrownRing", 0.6, 1.8, T(0, 0.2, 0), GOLD, { material = Enum.Material.Metal, reflectance = 0.2 })
	for i = 0, 4 do
		local a = i * 2 * math.pi / 5
		block(ctx, "CrownPoint", ctx.hv(0.42, 0.62, 0.42), T(math.sin(a) * 0.72, 0.62, math.cos(a) * 0.72) * CFrame.Angles(0, a + math.pi / 4, 0) * CFrame.Angles(math.pi / 4, 0, 0), GOLD, { material = Enum.Material.Metal })
	end
	ell(ctx, "Jewel", ctx.hv(0.32, 0.32, 0.2), T(0, 0.22, -0.9), Color3.fromRGB(255, 40, 80), { material = Enum.Material.Neon })
end

function Hats.Propeller(ctx, T, sp)
	ell(ctx, "Cap", ctx.hv(1.7, 0.95, 1.7), T(0, 0.05, 0), rgb(sp.Accent))
	cyl(ctx, "Stem", 0.55, 0.16, T(0, 0.65, 0), BLACK)
	local hub = spinner(ctx, T(0, 0.95, 0), 12)
	block(ctx, "Blade", ctx.hv(2.4, 0.08, 0.38), T(0, 0.95, 0), Color3.fromRGB(255, 220, 60), { weldTo = hub })
	block(ctx, "Blade", ctx.hv(0.38, 0.08, 2.4), T(0, 0.95, 0), Color3.fromRGB(60, 200, 255), { weldTo = hub })
end

function Hats.Wizard(ctx, T, sp)
	local color = shade(rgb(sp.Body), 0.55)
	local star = rgb(sp.Accent)
	cyl(ctx, "Brim", 0.12, 2.5, T(0, 0.02, 0), color)
	cyl(ctx, "Tier", 0.85, 1.6, T(0, 0.45, 0), color)
	cyl(ctx, "Tier", 0.8, 1.1, T(0.05, 1.2, 0.05) * CFrame.Angles(0.08, 0, 0.08), color)
	cyl(ctx, "Tier", 0.75, 0.6, T(0.15, 1.9, 0.12) * CFrame.Angles(0.18, 0, 0.18), color)
	ell(ctx, "Star", ctx.hv(0.48, 0.48, 0.48), T(0.24, 2.35, 0.2), star, { material = Enum.Material.Neon })
	cyl(ctx, "Band", 0.2, 1.62, T(0, 0.2, 0), star)
end

function Hats.Chef(ctx, T)
	cyl(ctx, "Band", 0.6, 1.6, T(0, 0.25, 0), WHITE)
	ell(ctx, "Puff", ctx.hv(2.0, 1.2, 2.0), T(0, 1.0, 0), WHITE)
	for _, x in ipairs({ -0.5, 0.5 }) do
		ell(ctx, "Puff", ctx.hv(1.2, 1.0, 1.2), T(x, 1.3, 0.1), WHITE)
	end
end

function Hats.Party(ctx, T, sp)
	local a, b = rgb(sp.Accent), WHITE
	local tiers = { { 0.5, 1.4, 0.25 }, { 0.5, 1.05, 0.75 }, { 0.5, 0.72, 1.25 }, { 0.45, 0.4, 1.7 } }
	for i, t in ipairs(tiers) do
		cyl(ctx, "Tier", t[1], t[2], T(0, t[3], 0), if i % 2 == 1 then a else b)
	end
	ell(ctx, "Pom", ctx.hv(0.5, 0.5, 0.5), T(0, 2.05, 0), Color3.fromRGB(255, 230, 80))
end

function Hats.Halo(ctx, T)
	local hub = spinner(ctx, T(0, 0.9, 0), 1.5)
	local n = 10
	for i = 0, n - 1 do
		local a = i * 2 * math.pi / n
		block(ctx, "Halo", ctx.hv(0.62, 0.14, 0.2), T(math.sin(a) * 0.95, 0.9, math.cos(a) * 0.95) * CFrame.Angles(0, a + math.pi / 2, 0), Color3.fromRGB(255, 240, 150), { material = Enum.Material.Neon, weldTo = hub, shadow = false })
	end
end

function Hats.Viking(ctx, T)
	local metal = Color3.fromRGB(170, 176, 186)
	ell(ctx, "Helmet", ctx.hv(2.3, 1.4, 2.3), T(0, -0.05, 0), metal, { material = Enum.Material.Metal })
	cyl(ctx, "HelmetBand", 0.28, 2.2, T(0, -0.3, 0), Color3.fromRGB(180, 120, 50))
	for _, x in ipairs({ -1, 1 }) do
		ell(ctx, "Horn", ctx.hv(0.5, 1.2, 0.5), T(x * 1.15, 0.35, 0) * CFrame.Angles(0, 0, -x * 0.65), Color3.fromRGB(250, 238, 210))
		ell(ctx, "HornTip", ctx.hv(0.34, 0.7, 0.34), T(x * 1.5, 0.95, 0) * CFrame.Angles(0, 0, -x * 0.25), Color3.fromRGB(250, 238, 210))
	end
end

function Hats.Beanie(ctx, T, sp)
	ell(ctx, "Beanie", ctx.hv(2.0, 1.25, 2.0), T(0, -0.05, 0), rgb(sp.Accent))
	cyl(ctx, "Cuff", 0.38, 2.0, T(0, -0.32, 0), WHITE)
	ell(ctx, "Pom", ctx.hv(0.6, 0.6, 0.6), T(0, 0.62, 0), WHITE)
end

---------------------------------------------------------------------------------------------
-- Accessories. L is the body origin, F the face origin, info the shape layout.
---------------------------------------------------------------------------------------------

local Acc = {}

function Acc.Bowtie(ctx, L, _F, info, sp)
	local c = rgb(sp.Accent)
	local y, z = info.neckY, info.neckZ - 0.1
	for _, x in ipairs({ -0.35, 0.35 }) do
		ell(ctx, "Bow", ctx.v(0.62, 0.5, 0.3), L(info.faceX + x, y, z) * CFrame.Angles(0, 0, x), c)
	end
	ell(ctx, "Knot", ctx.v(0.3, 0.3, 0.3), L(info.faceX, y, z - 0.08), shade(c, 0.8))
end

function Acc.Mustache(ctx, _L, F, _info, sp)
	local color = if sp.Hat == "Wizard" then WHITE else Color3.fromRGB(74, 48, 32)
	for _, x in ipairs({ -0.38, 0.38 }) do
		ell(ctx, "Mustache", ctx.v(0.8, 0.3, 0.28), F(x, -0.32, -0.12) * CFrame.Angles(0, 0, -x * 0.7), color)
		ell(ctx, "Curl", ctx.v(0.3, 0.3, 0.25), F(x * 2.1, -0.18, -0.08), color)
	end
end

function Acc.Tongue(ctx, _L, F)
	ell(ctx, "Tongue", ctx.v(0.45, 0.22, 0.6), F(0.15, -0.68, -0.25) * CFrame.Angles(0.4, 0, 0), PINK)
end

function Acc.Cape(ctx, L, _F, info)
	local red = Color3.fromRGB(210, 36, 56)
	local h = math.max(1.6, info.neckY + 0.8)
	block(ctx, "Cape", ctx.v(info.halfW * 1.5, h, 0.14), L(0, h / 2 + 0.1, info.back + 0.08) * CFrame.Angles(-0.12, 0, 0), red, { material = Enum.Material.Fabric })
	ell(ctx, "Collar", ctx.v(info.halfW * 1.4, 0.45, 0.6), L(0, info.neckY + 0.45, info.back - 0.1), GOLD, { material = Enum.Material.Metal })
end

function Acc.Monocle(ctx, _L, F)
	local axisZ = CFrame.Angles(0, math.pi / 2, 0)
	newPart(ctx, "MonocleRim", "Part", ctx.v(0.08, 0.82, 0.82), F(0.5, 0.15, -0.4) * axisZ, GOLD, { material = Enum.Material.Metal }).Shape = Enum.PartType.Cylinder
	newPart(ctx, "MonocleGlass", "Part", ctx.v(0.1, 0.66, 0.66), F(0.5, 0.15, -0.42) * axisZ, Color3.fromRGB(200, 240, 255), { material = Enum.Material.Glass, transparency = 0.5 }).Shape = Enum.PartType.Cylinder
	block(ctx, "Chain", ctx.v(0.06, 1.0, 0.06), F(0.85, -0.35, -0.35) * CFrame.Angles(0, 0, 0.35), GOLD, { material = Enum.Material.Metal })
end

function Acc.Antenna(ctx, L, _F, info, sp)
	local x = info.faceX + 0.45
	cyl(ctx, "Antenna", 1.4, 0.12, L(x + 0.15, info.top + 0.55, 0.1) * CFrame.Angles(0, 0, -0.25), BLACK)
	ell(ctx, "AntennaBall", ctx.v(0.45, 0.45, 0.45), L(x + 0.33, info.top + 1.25, 0.1), rgb(sp.Accent), { material = Enum.Material.Neon })
end

function Acc.Tail(ctx, L, _F, info, sp)
	local body = rgb(sp.Body)
	local b = info.back
	ell(ctx, "Tail", ctx.v(1.0, 1.0, 1.4), L(0, 0.8, b + 0.2), body, { body = true })
	ell(ctx, "Tail", ctx.v(0.72, 0.72, 1.0), L(0, 1.25, b + 1.0), body, { body = true })
	ell(ctx, "TailTip", ctx.v(0.55, 0.55, 0.55), L(0, 1.75, b + 1.45), rgb(sp.Accent), { material = if sp.NeonAccent then Enum.Material.Neon else Enum.Material.SmoothPlastic })
end

function Acc.Arms(ctx, L, _F, info, sp)
	local body = rgb(sp.Body)
	local y = info.armY or (info.neckY + 0.3)
	for _, x in ipairs({ -1, 1 }) do
		ell(ctx, "Arm", ctx.v(0.75, 1.3, 0.75), L(x * (info.halfW + 0.05), y, -0.2) * CFrame.Angles(0, 0, -x * 0.75), body, { body = true })
	end
end

function Acc.Wings(ctx, L, _F, info, sp)
	local neon = sp.NeonAccent
	local color = if neon then rgb(sp.Accent) else WHITE
	local opts = { material = if neon then Enum.Material.Neon else Enum.Material.Glass, transparency = if neon then 0.25 else 0.35, shadow = false }
	local y = math.max(1.4, info.top * 0.55)
	for _, x in ipairs({ -1, 1 }) do
		ell(ctx, "Wing", ctx.v(0.22, 2.0, 1.5), L(x * 0.95, y, info.back + 0.35) * CFrame.Angles(0, x * 0.55, x * 0.45), color, opts)
	end
end

---------------------------------------------------------------------------------------------
-- Mutation looks
---------------------------------------------------------------------------------------------

function BlobbyModels.applyMutation(bodyParts, mutationKey, mutationDef)
	if not mutationKey or not mutationDef then
		return
	end
	for _, p in ipairs(bodyParts) do
		if mutationKey == "Gold" then
			p.Color = rgb(mutationDef.Color)
			p.Material = Enum.Material.Metal
			p.Reflectance = 0.25
		elseif mutationKey == "Diamond" then
			p.Color = rgb(mutationDef.Color)
			p.Material = Enum.Material.Glass
			p.Transparency = 0.12
			p.Reflectance = 0.35
		elseif mutationKey == "Rainbow" then
			p.Material = Enum.Material.SmoothPlastic
			p:SetAttribute("Rainbow", true)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------

--[[
	species     BlobbyConfig entry
	cframe      where the feet go (model faces the frame's -Z)
	opts = { rarity = RarityConfig tier, mutation = key?, mutationDef = def?, phase = number? }
	returns { model, root, main, motor, height, promptAttachment, labelAttachment }
]]
function BlobbyModels.build(species, cframe, opts)
	opts = opts or {}
	local rarity = opts.rarity or { Scale = 1, Color = { 255, 255, 255 } }
	local s = rarity.Scale or 1

	local model = Instance.new("Model")
	model.Name = species.Id
	local ctx = { model = model, parts = {}, bodyParts = {}, toWeld = {}, spinners = {}, s = s, hs = s }
	ctx.v = function(x, y, z)
		return Vector3.new(x * s, y * s, z * s)
	end
	local function L(x, y, z)
		return cframe * CFrame.new(x * s, y * s, z * s)
	end

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2 * s, 0.2, 2 * s)
	root.CFrame = cframe
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Massless = true
	root.Parent = model
	model.PrimaryPart = root

	local bodyColor = rgb(species.Body)
	local shapeFn = Shapes[species.Shape] or Shapes.Round
	local info = shapeFn(ctx, L, species, bodyColor)

	local function F(x, y, z)
		return cframe * CFrame.new((info.faceX + x) * s, (info.faceY + y) * s, (info.faceZ + z) * s)
	end
	local hs = s * (info.headScale or 1)
	ctx.hv = function(x, y, z)
		return Vector3.new(x * hs, y * hs, z * hs)
	end
	local function T(x, y, z)
		return cframe * CFrame.new(info.faceX * s + x * hs, (info.top - 0.12) * s + y * hs, z * hs)
	end
	-- Hats use the head scale for their own sizes; temporarily point ctx.v at it.
	local eyesFn = Eyes[species.Eyes] or Eyes.Googly
	eyesFn(ctx, F, species, bodyColor)
	local plainV = ctx.v
	ctx.v = ctx.hv
	local hatFn = Hats[species.Hat] or Hats.None
	hatFn(ctx, T, species)
	ctx.v = plainV
	for _, accName in ipairs(species.Accessories or {}) do
		local fn = Acc[accName]
		if fn then
			fn(ctx, L, F, info, species)
		end
	end
	if not info.noFeet then
		for _, x in ipairs({ -0.62, 0.62 }) do
			ell(ctx, "Foot", ctx.v(1.0, 0.5, 1.25), L(x * info.halfW / 1.6, 0.22, -0.35), shade(bodyColor, 0.8), { body = true })
		end
	end

	BlobbyModels.applyMutation(ctx.bodyParts, opts.mutation, opts.mutationDef)

	-- Glow and sparkles by rarity
	local glowColor = rgb(rarity.Color)
	if rarity.Glow then
		local light = Instance.new("PointLight")
		light.Color = glowColor
		light.Range = 9 * s
		light.Brightness = if rarity.Sparkles then 2 else 1.2
		light.Shadows = false
		light.Parent = ctx.main
	end
	if rarity.Sparkles or opts.mutation then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		local c = if opts.mutationDef then rgb(opts.mutationDef.Color) else glowColor
		sparkles.Color = ColorSequence.new(c)
		sparkles.LightEmission = 1
		sparkles.Rate = if rarity.Sparkles then 8 else 4
		sparkles.Lifetime = NumberRange.new(0.8, 1.6)
		sparkles.Speed = NumberRange.new(1, 2.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 * s), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Parent = ctx.main
	end

	-- Joints: everything welds to the main body; the body hangs off Root on the Bob motor.
	local main = ctx.main
	for _, entry in ipairs(ctx.toWeld) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = entry.to or main
		weld.Part1 = entry.part
		weld.Parent = entry.part
	end
	for _, sp in ipairs(ctx.spinners) do
		local motor = Instance.new("Motor6D")
		motor.Name = "Spinner"
		motor.Part0 = main
		motor.Part1 = sp.hub
		motor.C0 = main.CFrame:ToObjectSpace(sp.hub.CFrame)
		motor.C1 = CFrame.new()
		motor:SetAttribute("Speed", sp.speed)
		motor.Parent = main
	end
	local motor = Instance.new("Motor6D")
	motor.Name = "Bob"
	motor.Part0 = root
	motor.Part1 = main
	motor.C0 = CFrame.new()
	motor.C1 = CFrame.new(0, -ctx.mainY * s, 0)
	motor.Parent = root

	local height = (info.top + 0.3) * s
	local promptAttachment = Instance.new("Attachment")
	promptAttachment.Name = "PromptAttachment"
	promptAttachment.Position = Vector3.new(0, height * 0.5, 0)
	promptAttachment.Parent = root
	local labelAttachment = Instance.new("Attachment")
	labelAttachment.Name = "LabelAttachment"
	labelAttachment.Position = Vector3.new(0, height + 0.6, 0)
	labelAttachment.Parent = root

	model:SetAttribute("Species", species.Id)
	model:SetAttribute("Bob", species.Bob)
	model:SetAttribute("Phase", opts.phase or 0)
	model:SetAttribute("Height", height)
	if opts.mutation then
		model:SetAttribute("Mutation", opts.mutation)
	end
	model:SetAttribute("Rarity", species.Rarity)
	CollectionService:AddTag(model, "Blobby")

	return {
		model = model,
		root = root,
		main = main,
		motor = motor,
		height = height,
		partCount = #ctx.parts + 1,
		promptAttachment = promptAttachment,
		labelAttachment = labelAttachment,
	}
end

---------------------------------------------------------------------------------------------
-- Nameplate (BillboardGui). Returns the labels so callers can update the value line.
---------------------------------------------------------------------------------------------

local function label(parent, name, text, color, order, height)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, height, 0)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.2
	l.TextStrokeColor3 = Color3.fromRGB(20, 16, 30)
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

--[[
	info = { name, rarity, rarityColor = {r,g,b}, mutation?, mutationColor?, value, valueColor? }
]]
function BlobbyModels.nameplate(built, info)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.new(7, 0, 3.2, 0)
	gui.StudsOffset = Vector3.new(0, 1.6, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Adornee = built.labelAttachment
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.Parent = gui
	local labels = {}
	if info.mutation then
		labels.mutation = label(gui, "Mutation", string.upper(info.mutation), rgb(info.mutationColor or { 255, 255, 255 }), 1, 0.22)
	end
	labels.name = label(gui, "Name", info.name, Color3.fromRGB(255, 255, 255), 2, 0.3)
	labels.rarity = label(gui, "Rarity", info.rarity, rgb(info.rarityColor), 3, 0.22)
	labels.value = label(gui, "Value", info.value or "", rgb(info.valueColor or { 120, 255, 120 }), 4, 0.26)
	gui.Parent = built.root
	return labels
end

return BlobbyModels
