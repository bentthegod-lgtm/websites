--[[
	Models - procedural models built from parts, shared by the server (the world) and the
	preview tools: the Antlered, a frozen-player ice block, a frozen core in its ice, the
	carried shard, pine trees, ice-crystal clusters, boulders, a brazier, a snow drift,
	the sled, the beacon, the wrecked boat and lamp posts.

	Every model is anchored and built around a pivot at its base; decorative parts don't
	collide unless they are meant to block.
]]

local Models = {}

local rgb = Color3.fromRGB
local M = Enum.Material

Models.Palette = {
	IceLight = rgb(214, 236, 248),
	Ice = rgb(176, 214, 236),
	IceDeep = rgb(120, 170, 212),
	Water = rgb(18, 36, 64),
	Snow = rgb(240, 244, 248),
	Wood = rgb(176, 130, 86),
	WoodDark = rgb(110, 76, 50),
	Pine = rgb(52, 112, 96),
	PineDark = rgb(36, 84, 74),
	Rock = rgb(110, 118, 134),
	Crystal = rgb(170, 210, 240),
	Monster = rgb(128, 160, 205),
	MonsterDark = rgb(52, 76, 120),
	Fire = rgb(255, 170, 70),
	Core = rgb(120, 230, 255),
}
local P = Models.Palette

-- Makes a part. opts: Size, CFrame, Color, Material, Transparency, Shape, Name, CanCollide,
-- Parent, Reflectance.
function Models.part(opts)
	local p = Instance.new(opts.Class or "Part")
	p.Name = opts.Name or "Part"
	p.Anchored = true
	p.Size = opts.Size
	p.CFrame = opts.CFrame
	p.Color = opts.Color or P.Snow
	p.Material = opts.Material or M.SmoothPlastic
	p.Transparency = opts.Transparency or 0
	p.Reflectance = opts.Reflectance or 0
	p.CanCollide = opts.CanCollide == true
	p.CanQuery = opts.CanCollide == true
	p.CanTouch = false
	p.CastShadow = opts.CastShadow ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.Shape then
		p.Shape = opts.Shape
	end
	p.Parent = opts.Parent
	return p
end
local part = Models.part

local function model(name, parent, pivot)
	local m = Instance.new("Model")
	m.Name = name
	local root = part({ Name = "Root", Size = Vector3.new(1, 1, 1), CFrame = pivot, Transparency = 1, Parent = m, CastShadow = false })
	m.PrimaryPart = root
	m.Parent = parent
	return m
end

local function light(parentPart, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parentPart
	return l
end
Models.light = light

---------------------------------------------------------------------------------------------
-- The Antlered: tall, gaunt, blind, antlered, pale-blue, long arms, hunched.
---------------------------------------------------------------------------------------------

function Models.monster(pivot, parent)
	local m = model("Antlered", parent, pivot)
	local function add(name, size, offset, color, material)
		return part({ Name = name, Size = size, CFrame = pivot * offset, Color = color or P.Monster, Material = material or M.Ice, Parent = m })
	end
	local lean = CFrame.Angles(math.rad(-14), 0, 0)
	-- legs
	add("LegL", Vector3.new(1.4, 6.4, 1.4), CFrame.new(-1.2, 3.2, 0), P.MonsterDark, M.Slate)
	add("LegR", Vector3.new(1.4, 6.4, 1.4), CFrame.new(1.2, 3.2, 0), P.MonsterDark, M.Slate)
	add("FootL", Vector3.new(1.6, 0.5, 2.4), CFrame.new(-1.2, 0.25, -0.4), P.Monster)
	add("FootR", Vector3.new(1.6, 0.5, 2.4), CFrame.new(1.2, 0.25, -0.4), P.Monster)
	-- hunched torso
	local torsoCF = CFrame.new(0, 9.4, -0.6) * lean
	add("Torso", Vector3.new(4.2, 6, 2.2), torsoCF, P.Monster)
	add("Ribs", Vector3.new(3.4, 3.2, 0.3), torsoCF * CFrame.new(0, 0.3, -1.2), P.IceLight, M.Glass).Transparency = 0.2
	add("Spine", Vector3.new(0.8, 6.2, 0.8), torsoCF * CFrame.new(0, 0.2, 1.2), P.MonsterDark, M.Slate)
	-- long arms down to the knees
	for _, side in ipairs({ -1, 1 }) do
		local shoulder = torsoCF * CFrame.new(side * 2.6, 2.3, 0)
		add("UpperArm", Vector3.new(1, 4.4, 1), shoulder * CFrame.Angles(math.rad(12), 0, math.rad(side * 6)) * CFrame.new(0, -2.2, 0), P.MonsterDark, M.Slate)
		add("Forearm", Vector3.new(0.8, 4.6, 0.8), shoulder * CFrame.new(side * 0.3, -6.4, -0.9), P.Monster)
		for f = -1, 1 do
			add("Claw", Vector3.new(0.25, 1.6, 0.25), shoulder * CFrame.new(side * 0.3 + f * 0.3, -9.3, -1.1) * CFrame.Angles(math.rad(-10), 0, 0), P.IceLight)
		end
	end
	-- neck + long blind skull (no eyes: a smooth plate where the face should be)
	local headCF = torsoCF * CFrame.new(0, 3.8, -1.2) * CFrame.Angles(math.rad(-20), 0, 0)
	add("Neck", Vector3.new(0.9, 1.6, 0.9), torsoCF * CFrame.new(0, 3.2, -0.7), P.MonsterDark, M.Slate)
	add("Skull", Vector3.new(1.8, 2.4, 2.8), headCF, P.IceLight)
	add("Snout", Vector3.new(1.2, 1.1, 1.6), headCF * CFrame.new(0, -0.7, -1.9), P.Monster)
	add("FacePlate", Vector3.new(1.5, 1, 0.2), headCF * CFrame.new(0, 0.3, -1.45), P.MonsterDark, M.Slate)
	-- antlers
	for _, side in ipairs({ -1, 1 }) do
		local base = headCF * CFrame.new(side * 0.6, 1.2, 0.2)
		local beam = base * CFrame.Angles(0, 0, math.rad(-side * 38)) * CFrame.new(0, 1.9, 0)
		add("Antler", Vector3.new(0.35, 3.8, 0.35), beam, P.IceLight)
		add("Tine", Vector3.new(0.3, 1.8, 0.3), beam * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(side * 60)) * CFrame.new(0, 0.9, 0), P.IceLight)
		add("Tine", Vector3.new(0.3, 1.4, 0.3), beam * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, math.rad(-side * 30)) * CFrame.new(0, 0.7, 0), P.IceLight)
	end
	-- a faint cold glow so it reads in the dark (not eyes - it has none)
	light(m.Root, rgb(150, 210, 255), 14, 0.6)
	return m
end

---------------------------------------------------------------------------------------------
-- Ice blocks, cores, shards
---------------------------------------------------------------------------------------------

-- A clear block a frozen player is held in.
function Models.iceBlock(pivot, parent)
	local m = model("IceBlock", parent, pivot)
	part({ Name = "Block", Size = Vector3.new(4.4, 6.4, 3.4), CFrame = pivot * CFrame.new(0, 3.2, 0), Color = P.Crystal, Material = M.Glass, Transparency = 0.45, Parent = m, CanCollide = true })
	part({ Name = "Frost", Size = Vector3.new(4.6, 0.6, 3.6), CFrame = pivot * CFrame.new(0, 6.3, 0), Color = P.Snow, Material = M.Snow, Parent = m })
	part({ Name = "Chunk", Size = Vector3.new(1.4, 1.2, 1.2), CFrame = pivot * CFrame.new(2.2, 0.6, -1.3) * CFrame.Angles(0, 0.6, 0.3), Color = P.Crystal, Material = M.Glass, Transparency = 0.3, Parent = m })
	return m
end

-- A frozen core sealed in a jagged block of ice (chip it out with a prompt).
function Models.frozenCore(pivot, parent)
	local m = model("FrozenCore", parent, pivot)
	local core = part({ Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.8, 1.8), CFrame = pivot * CFrame.new(0, 2.2, 0), Color = P.Core, Material = M.Neon, Parent = m })
	light(core, P.Core, 16, 1.4)
	part({ Name = "Shell", Size = Vector3.new(3.6, 4.2, 3.6), CFrame = pivot * CFrame.new(0, 2.1, 0) * CFrame.Angles(0, math.rad(20), 0), Color = P.Crystal, Material = M.Glass, Transparency = 0.5, Parent = m, CanCollide = true })
	for i = 1, 4 do
		local a = i * math.pi / 2 + 0.4
		part({ Name = "Spike", Size = Vector3.new(0.9, 3.2, 0.9), CFrame = pivot * CFrame.new(math.cos(a) * 2, 1.4, math.sin(a) * 2) * CFrame.Angles(math.cos(a) * 0.5, 0, math.sin(a) * 0.5), Color = P.IceLight, Material = M.Ice, Parent = m })
	end
	return m, core
end

-- The glowing shard that hovers over a carrier's head.
function Models.carriedShard(pivot, parent)
	local m = model("CarriedCore", parent, pivot)
	local shard = part({ Name = "Shard", Size = Vector3.new(1.2, 1.8, 1.2), CFrame = pivot * CFrame.Angles(0, 0, math.rad(45)), Color = P.Core, Material = M.Neon, Parent = m })
	light(shard, P.Core, 12, 1.2)
	return m
end

---------------------------------------------------------------------------------------------
-- Scenery
---------------------------------------------------------------------------------------------

function Models.pine(pivot, parent, scale)
	scale = scale or 1
	local m = model("Pine", parent, pivot)
	part({ Name = "Trunk", Size = Vector3.new(1.2, 4, 1.2) * scale, CFrame = pivot * CFrame.new(0, 2 * scale, 0), Color = P.WoodDark, Material = M.Wood, Parent = m, CanCollide = true })
	local tiers = { { 7, 3, 4.2 }, { 5.4, 2.6, 6.6 }, { 3.8, 2.2, 8.6 }, { 2.2, 1.8, 10.2 } }
	for i, t in ipairs(tiers) do
		part({ Name = "Needles", Size = Vector3.new(t[1], t[2], t[1]) * scale, CFrame = pivot * CFrame.new(0, t[3] * scale, 0), Color = if i % 2 == 0 then P.PineDark else P.Pine, Material = M.Grass, Parent = m })
		part({ Name = "SnowCap", Size = Vector3.new(t[1] * 0.75, 0.4, t[1] * 0.75) * scale, CFrame = pivot * CFrame.new(0, (t[3] + t[2] / 2 + 0.1) * scale, 0), Color = P.Snow, Material = M.Snow, Parent = m })
	end
	return m
end

function Models.boulder(pivot, parent, rng)
	local m = model("Boulder", parent, pivot)
	local r = function()
		return if rng then rng:NextNumber() else 0.5
	end
	part({ Name = "Stone", Size = Vector3.new(6.4, 4 + r() * 2, 6.2), CFrame = pivot * CFrame.new(0, 2.4, 0) * CFrame.Angles(r() * 0.3, r() * 3, r() * 0.2), Color = P.Rock, Material = M.Slate, Parent = m, CanCollide = true })
	part({ Name = "Stone", Size = Vector3.new(3.4, 2.4, 3.2), CFrame = pivot * CFrame.new(2.4, 1.2, 2) * CFrame.Angles(0.2, r() * 3, 0.3), Color = P.Rock:Lerp(P.Snow, 0.15), Material = M.Slate, Parent = m, CanCollide = true })
	part({ Name = "Snow", Size = Vector3.new(5, 0.5, 4.6), CFrame = pivot * CFrame.new(0, 4.6, 0), Color = P.Snow, Material = M.Snow, Parent = m })
	return m
end

function Models.crystals(pivot, parent, rng)
	local m = model("Crystals", parent, pivot)
	for i = 1, 6 do
		local a = i * 1.05 + (if rng then rng:NextNumber() else 0)
		local h = 3 + (if rng then rng:NextNumber() * 4 else 2) + (if i == 1 then 2 else 0)
		local d = if i == 1 then 0 else 1.6
		part({ Name = "Crystal", Size = Vector3.new(1.2, h, 1.2), CFrame = pivot * CFrame.new(math.cos(a) * d, h / 2, math.sin(a) * d) * CFrame.Angles(math.cos(a) * 0.35, a, math.sin(a) * 0.35), Color = P.Crystal, Material = M.Glass, Transparency = 0.15, Parent = m, CanCollide = true })
	end
	return m
end

function Models.brazier(pivot, parent)
	local m = model("Brazier", parent, pivot)
	part({ Name = "Bowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 3.6, 3.6), CFrame = pivot * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(60, 60, 66), Material = M.Metal, Parent = m, CanCollide = true })
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3
		part({ Name = "Leg", Size = Vector3.new(0.3, 2.2, 0.3), CFrame = pivot * CFrame.new(math.cos(a) * 1.2, 1.1, math.sin(a) * 1.2), Color = rgb(50, 50, 56), Material = M.Metal, Parent = m })
	end
	local flame = part({ Name = "Flame", Size = Vector3.new(2, 2.2, 2), CFrame = pivot * CFrame.new(0, 4.2, 0) * CFrame.Angles(0, math.rad(45), 0), Color = P.Fire, Material = M.Neon, Transparency = 0.15, Parent = m })
	part({ Name = "FlameCore", Size = Vector3.new(1, 1.6, 1), CFrame = pivot * CFrame.new(0, 4.6, 0), Color = rgb(255, 230, 140), Material = M.Neon, Parent = m })
	light(flame, P.Fire, 22, 2)
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 6
	fire.Parent = flame
	return m
end

function Models.campfire(pivot, parent)
	local m = model("Campfire", parent, pivot)
	for i = 0, 7 do
		local a = i * math.pi / 4
		part({ Name = "Stone", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = pivot * CFrame.new(math.cos(a) * 2.2, 0.5, math.sin(a) * 2.2), Color = rgb(226, 228, 232), Material = M.Slate, Parent = m })
	end
	for i = 0, 2 do
		part({ Name = "Log", Size = Vector3.new(0.6, 0.6, 3.2), CFrame = pivot * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, i * math.pi / 3, 0), Color = P.WoodDark, Material = M.Wood, Parent = m })
	end
	local flame = part({ Name = "Flame", Size = Vector3.new(1.6, 1.8, 1.6), CFrame = pivot * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, math.rad(45), 0), Color = P.Fire, Material = M.Neon, Transparency = 0.1, Parent = m })
	light(flame, P.Fire, 24, 2.2)
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Parent = flame
	return m
end

function Models.drift(pivot, parent)
	local m = model("SnowDrift", parent, pivot)
	part({ Name = "Snow", Shape = Enum.PartType.Ball, Size = Vector3.new(4.6, 4.6, 4.6), CFrame = pivot * CFrame.new(0, 0.4, 0), Color = P.Snow, Material = M.Snow, Parent = m })
	part({ Name = "Snow", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = pivot * CFrame.new(1.8, 0.2, 1), Color = P.Snow, Material = M.Snow, Parent = m })
	part({ Name = "Snow", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = pivot * CFrame.new(-1.6, 0.1, -1.1), Color = P.Snow, Material = M.Snow, Parent = m })
	return m
end

function Models.lampPost(pivot, parent)
	local m = model("LampPost", parent, pivot)
	part({ Name = "Post", Size = Vector3.new(0.6, 7, 0.6), CFrame = pivot * CFrame.new(0, 3.5, 0), Color = P.WoodDark, Material = M.Wood, Parent = m, CanCollide = true })
	part({ Name = "Cap", Size = Vector3.new(1.8, 0.4, 1.8), CFrame = pivot * CFrame.new(0, 7.9, 0), Color = rgb(40, 34, 30), Material = M.Metal, Parent = m })
	local lamp = part({ Name = "Lamp", Size = Vector3.new(1.4, 1.4, 1.4), CFrame = pivot * CFrame.new(0, 7, 0), Color = rgb(255, 214, 150), Material = M.Neon, Parent = m })
	light(lamp, rgb(255, 196, 130), 20, 1.4)
	return m
end

function Models.sled(pivot, parent)
	local m = model("Sled", parent, pivot)
	for _, side in ipairs({ -1, 1 }) do
		part({ Name = "Runner", Size = Vector3.new(0.4, 0.5, 12), CFrame = pivot * CFrame.new(side * 2.6, 0.25, 0), Color = rgb(70, 70, 76), Material = M.Metal, Parent = m })
		part({ Name = "Curl", Size = Vector3.new(0.4, 1.6, 0.5), CFrame = pivot * CFrame.new(side * 2.6, 0.9, -6.1) * CFrame.Angles(math.rad(-30), 0, 0), Color = rgb(70, 70, 76), Material = M.Metal, Parent = m })
		part({ Name = "Rail", Size = Vector3.new(0.4, 1.4, 10), CFrame = pivot * CFrame.new(side * 2.8, 1.9, 0.6), Color = P.Wood, Material = M.Wood, Parent = m })
	end
	part({ Name = "Deck", Size = Vector3.new(5.8, 0.6, 10.5), CFrame = pivot * CFrame.new(0, 1.2, 0.4), Color = P.Wood, Material = M.Wood, Parent = m, CanCollide = true })
	part({ Name = "Back", Size = Vector3.new(5.8, 2.4, 0.5), CFrame = pivot * CFrame.new(0, 2.6, 5.4), Color = P.Wood, Material = M.Wood, Parent = m })
	part({ Name = "Blanket", Size = Vector3.new(5, 0.3, 4), CFrame = pivot * CFrame.new(0, 1.6, 2.4), Color = rgb(190, 70, 60), Material = M.Fabric, Parent = m })
	local lantern = part({ Name = "Lantern", Size = Vector3.new(0.8, 1, 0.8), CFrame = pivot * CFrame.new(2.8, 3.2, -4.4), Color = rgb(255, 210, 140), Material = M.Neon, Parent = m })
	light(lantern, rgb(255, 196, 130), 16, 1.4)
	return m
end

-- The beacon: a stone tower with a big bowl; it lights up as cores are delivered.
function Models.beacon(pivot, parent)
	local m = model("Beacon", parent, pivot)
	part({ Name = "Base", Size = Vector3.new(7, 2, 7), CFrame = pivot * CFrame.new(0, 1, 0), Color = rgb(150, 154, 166), Material = M.Slate, Parent = m, CanCollide = true })
	part({ Name = "Tower", Size = Vector3.new(4, 9, 4), CFrame = pivot * CFrame.new(0, 6.5, 0), Color = rgb(130, 134, 148), Material = M.Slate, Parent = m, CanCollide = true })
	part({ Name = "Bowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 6, 6), CFrame = pivot * CFrame.new(0, 11.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(70, 70, 78), Material = M.Metal, Parent = m })
	local flame = part({ Name = "Flame", Size = Vector3.new(3.4, 3.4, 3.4), CFrame = pivot * CFrame.new(0, 13.6, 0) * CFrame.Angles(0, math.rad(45), 0), Color = P.Core, Material = M.Neon, Transparency = 0.7, Parent = m })
	local l = light(flame, P.Core, 40, 0.2)
	l.Name = "BeaconLight"
	return m, flame
end

function Models.wreck(pivot, parent)
	local m = model("Wreck", parent, pivot)
	local hull = pivot * CFrame.Angles(math.rad(8), math.rad(12), math.rad(-14))
	part({ Name = "Hull", Size = Vector3.new(9, 3.4, 20), CFrame = hull * CFrame.new(0, 1.2, 0), Color = rgb(96, 66, 48), Material = M.WoodPlanks, Parent = m, CanCollide = true })
	part({ Name = "Deck", Size = Vector3.new(8, 0.5, 18), CFrame = hull * CFrame.new(0, 3, 0), Color = rgb(140, 100, 70), Material = M.WoodPlanks, Parent = m })
	part({ Name = "Cabin", Size = Vector3.new(5, 4, 6), CFrame = hull * CFrame.new(0, 5.2, 3), Color = rgb(150, 110, 80), Material = M.Wood, Parent = m, CanCollide = true })
	part({ Name = "CabinRoof", Size = Vector3.new(6, 0.6, 7), CFrame = hull * CFrame.new(0, 7.5, 3), Color = P.Snow, Material = M.Snow, Parent = m })
	part({ Name = "Mast", Size = Vector3.new(0.8, 14, 0.8), CFrame = hull * CFrame.new(0, 10, -3) * CFrame.Angles(math.rad(-20), 0, math.rad(10)), Color = P.WoodDark, Material = M.Wood, Parent = m })
	part({ Name = "Sail", Size = Vector3.new(6, 6, 0.2), CFrame = hull * CFrame.new(1.6, 12, -4.2) * CFrame.Angles(math.rad(-20), math.rad(20), math.rad(18)), Color = rgb(220, 214, 196), Material = M.Fabric, Parent = m })
	part({ Name = "IceRime", Size = Vector3.new(10, 1, 21), CFrame = hull * CFrame.new(0, 0, 0), Color = P.IceLight, Material = M.Ice, Parent = m })
	return m
end

function Models.hut(pivot, parent)
	local m = model("ExitHut", parent, pivot)
	part({ Name = "Floor", Size = Vector3.new(12, 1, 10), CFrame = pivot * CFrame.new(0, 0.5, 0), Color = P.WoodDark, Material = M.WoodPlanks, Parent = m, CanCollide = true })
	for _, x in ipairs({ -5.6, 5.6 }) do
		part({ Name = "Wall", Size = Vector3.new(0.8, 7, 10), CFrame = pivot * CFrame.new(x, 4.5, 0), Color = P.Wood, Material = M.WoodPlanks, Parent = m, CanCollide = true })
	end
	part({ Name = "BackWall", Size = Vector3.new(12, 7, 0.8), CFrame = pivot * CFrame.new(0, 4.5, 4.6), Color = P.Wood, Material = M.WoodPlanks, Parent = m, CanCollide = true })
	for _, side in ipairs({ -1, 1 }) do
		part({ Name = "Roof", Size = Vector3.new(7.6, 0.8, 11.5), CFrame = pivot * CFrame.new(side * 3.2, 9.2, 0) * CFrame.Angles(0, 0, math.rad(-side * 30)), Color = rgb(150, 70, 60), Material = M.Wood, Parent = m })
		part({ Name = "RoofSnow", Size = Vector3.new(7.6, 0.4, 11.6), CFrame = pivot * CFrame.new(side * 3.2, 9.7, 0) * CFrame.Angles(0, 0, math.rad(-side * 30)), Color = P.Snow, Material = M.Snow, Parent = m })
	end
	local window = part({ Name = "Window", Size = Vector3.new(3, 2, 0.3), CFrame = pivot * CFrame.new(0, 5, 5.05), Color = rgb(255, 210, 140), Material = M.Neon, Parent = m })
	light(window, rgb(255, 190, 120), 16, 1.2)
	part({ Name = "Sign", Size = Vector3.new(6, 1.6, 0.3), CFrame = pivot * CFrame.new(0, 8.4, -5.2), Color = P.WoodDark, Material = M.Wood, Parent = m })
	return m
end

-- A blocky winter kid (used by previews / the lobby statues - real players use their avatars).
function Models.kid(pivot, parent, colors)
	local m = model("Kid", parent, pivot)
	local skin = rgb(240, 200, 150)
	part({ Name = "LegL", Size = Vector3.new(0.95, 2, 1), CFrame = pivot * CFrame.new(-0.5, 1, 0), Color = rgb(70, 74, 120), Parent = m })
	part({ Name = "LegR", Size = Vector3.new(0.95, 2, 1), CFrame = pivot * CFrame.new(0.5, 1, 0), Color = rgb(70, 74, 120), Parent = m })
	part({ Name = "Torso", Size = Vector3.new(2, 2, 1), CFrame = pivot * CFrame.new(0, 3, 0), Color = colors.Jacket, Parent = m })
	part({ Name = "Belt", Size = Vector3.new(2.05, 0.3, 1.05), CFrame = pivot * CFrame.new(0, 2.2, 0), Color = rgb(70, 60, 50), Parent = m })
	part({ Name = "ArmL", Size = Vector3.new(1, 2, 1), CFrame = pivot * CFrame.new(-1.5, 3, 0), Color = colors.Jacket, Parent = m })
	part({ Name = "ArmR", Size = Vector3.new(1, 2, 1), CFrame = pivot * CFrame.new(1.5, 3, 0), Color = colors.Jacket, Parent = m })
	part({ Name = "Head", Size = Vector3.new(1.3, 1.2, 1.2), CFrame = pivot * CFrame.new(0, 4.6, 0), Color = skin, Parent = m })
	part({ Name = "Scarf", Size = Vector3.new(1.5, 0.4, 1.4), CFrame = pivot * CFrame.new(0, 4.05, 0), Color = colors.Scarf, Material = M.Fabric, Parent = m })
	part({ Name = "Beanie", Size = Vector3.new(1.4, 0.7, 1.3), CFrame = pivot * CFrame.new(0, 5.4, 0), Color = colors.Beanie, Material = M.Fabric, Parent = m })
	part({ Name = "Pompom", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = pivot * CFrame.new(0, 5.9, 0), Color = rgb(250, 250, 250), Material = M.Fabric, Parent = m })
	local lantern = part({ Name = "Lantern", Size = Vector3.new(0.6, 0.8, 0.6), CFrame = pivot * CFrame.new(-1.6, 1.6, -0.3), Color = colors.Lantern or rgb(255, 210, 140), Material = M.Neon, Parent = m })
	light(lantern, colors.Lantern or rgb(255, 196, 120), 10, 1)
	return m
end

return Models
