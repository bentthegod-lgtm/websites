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
-- The Antlered: very tall, gaunt, blind and antlered; pale ice-blue hide stretched over
-- ribs, arms that hang past its knees, ice crystals growing from its shoulders and spine,
-- and a slow plume of frost breath. No eyes - a smooth cracked plate where a face should be.
--
-- The head (skull, snout, face plate, antlers, breath) is its own sub-model "Head" so the
-- client can tilt it to listen (EffectsController animates it around Models.MonsterNeck).
---------------------------------------------------------------------------------------------

Models.MonsterNeck = CFrame.new(0, 13.6, -1.6) -- neck joint, relative to the model's pivot

function Models.monster(pivot, parent)
	local m = model("Antlered", parent, pivot)
	local head = Instance.new("Model")
	head.Name = "Head"
	head.Parent = m
	local function add(name, size, offset, color, material, into)
		return part({ Name = name, Size = size, CFrame = pivot * offset, Color = color or P.Monster, Material = material or M.Ice, Parent = into or m })
	end
	local lean = CFrame.Angles(math.rad(-16), 0, 0)
	-- long, thin legs with a backward-bent knee
	for _, side in ipairs({ -1, 1 }) do
		add("Thigh", Vector3.new(1.1, 5, 1.1), CFrame.new(side * 1.1, 7.2, 0.4) * CFrame.Angles(math.rad(-14), 0, 0), P.MonsterDark, M.Slate)
		add("Shin", Vector3.new(0.9, 5.2, 0.9), CFrame.new(side * 1.1, 2.7, 0.2) * CFrame.Angles(math.rad(10), 0, 0), P.Monster)
		add("Foot", Vector3.new(1.3, 0.45, 2.6), CFrame.new(side * 1.1, 0.22, -0.5), P.MonsterDark, M.Slate)
		for t = -1, 1 do
			add("Toe", Vector3.new(0.25, 0.25, 1.1), CFrame.new(side * 1.1 + t * 0.4, 0.15, -2.1), P.IceLight)
		end
	end
	-- gaunt hunched torso: a thin core, a ribcage of bars, a ridge of spine
	local torsoCF = CFrame.new(0, 11.4, -0.4) * lean
	add("Pelvis", Vector3.new(2.8, 1.2, 1.6), CFrame.new(0, 9.6, 0.2), P.MonsterDark, M.Slate)
	add("Torso", Vector3.new(2.6, 5.4, 1.6), torsoCF, P.Monster)
	for i = 0, 4 do
		local y = 1.6 - i * 0.75
		add("Rib", Vector3.new(3.4 - i * 0.18, 0.28, 2.1), torsoCF * CFrame.new(0, y, -0.15), P.IceLight, M.Ice)
	end
	add("Spine", Vector3.new(0.7, 6, 0.7), torsoCF * CFrame.new(0, 0.2, 0.95), P.MonsterDark, M.Slate)
	add("Shoulders", Vector3.new(4.6, 0.9, 1.4), torsoCF * CFrame.new(0, 2.5, 0), P.MonsterDark, M.Slate)
	-- ice crystals growing out of its shoulders and back
	local crystals = { { -1.9, 3.3, 0.2, 18, 1.6 }, { -1.5, 3.0, 0.6, -10, 1.1 }, { 1.8, 3.2, 0.3, -20, 1.4 }, { 0.3, 2.4, 1.3, 40, 1.3 }, { -0.3, 0.8, 1.3, 50, 1.0 }, { 0.2, -0.8, 1.2, 35, 0.8 } }
	for _, c in ipairs(crystals) do
		local cr = add("Crystal", Vector3.new(0.45, c[5] * 1.8, 0.45), torsoCF * CFrame.new(c[1], c[2], c[3]) * CFrame.Angles(math.rad(c[4]), 0, math.rad(c[1] * 12)), P.Crystal, M.Glass)
		cr.Transparency = 0.2
	end
	-- arms that hang down past the knees, with long claws
	for _, side in ipairs({ -1, 1 }) do
		local shoulder = torsoCF * CFrame.new(side * 2.3, 2.3, 0)
		add("UpperArm", Vector3.new(0.8, 5, 0.8), shoulder * CFrame.Angles(math.rad(10), 0, math.rad(side * 5)) * CFrame.new(0, -2.5, 0), P.MonsterDark, M.Slate)
		add("Forearm", Vector3.new(0.65, 5.2, 0.65), shoulder * CFrame.new(side * 0.35, -7.4, -0.9), P.Monster)
		add("Hand", Vector3.new(0.9, 0.8, 0.5), shoulder * CFrame.new(side * 0.35, -10.3, -1.0), P.Monster)
		for f = -1, 1 do
			add("Claw", Vector3.new(0.18, 1.9, 0.18), shoulder * CFrame.new(side * 0.35 + f * 0.28, -11.5, -1.15) * CFrame.Angles(math.rad(-12), 0, 0), P.IceLight)
		end
	end
	-- neck + long blind skull (no eyes: a smooth cracked plate where the face should be)
	add("Neck", Vector3.new(0.75, 2, 0.75), torsoCF * CFrame.new(0, 3.5, -0.6) * CFrame.Angles(math.rad(-20), 0, 0), P.MonsterDark, M.Slate)
	local headCF = Models.MonsterNeck * CFrame.new(0, 1.1, -0.6) * CFrame.Angles(math.rad(-18), 0, 0)
	add("Skull", Vector3.new(1.6, 2.2, 2.7), headCF, P.IceLight, M.Ice, head)
	add("Jaw", Vector3.new(1.2, 0.5, 1.9), headCF * CFrame.new(0, -1.2, -0.9), P.Monster, M.Ice, head)
	local snout = add("Snout", Vector3.new(1.05, 1, 1.7), headCF * CFrame.new(0, -0.6, -1.9), P.Monster, M.Ice, head)
	add("FacePlate", Vector3.new(1.35, 0.9, 0.2), headCF * CFrame.new(0, 0.35, -1.42), P.MonsterDark, M.Slate, head)
	add("FaceCrack", Vector3.new(0.1, 0.8, 0.05), headCF * CFrame.new(0.2, 0.35, -1.53) * CFrame.Angles(0, 0, math.rad(20)), rgb(170, 230, 255), M.Neon, head)
	for _, side in ipairs({ -1, 1 }) do
		local base = headCF * CFrame.new(side * 0.55, 1.1, 0.25)
		local beam = base * CFrame.Angles(math.rad(-8), 0, math.rad(-side * 36)) * CFrame.new(0, 2.3, 0)
		add("Antler", Vector3.new(0.32, 4.6, 0.32), beam, P.IceLight, M.Ice, head)
		add("Tine", Vector3.new(0.26, 2, 0.26), beam * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(side * 58)) * CFrame.new(0, 1, 0), P.IceLight, M.Ice, head)
		add("Tine", Vector3.new(0.24, 1.6, 0.24), beam * CFrame.new(0, 1.5, 0) * CFrame.Angles(math.rad(25), 0, math.rad(-side * 25)) * CFrame.new(0, 0.8, 0), P.IceLight, M.Ice, head)
		add("Tine", Vector3.new(0.22, 1.3, 0.22), beam * CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, math.rad(side * 40)) * CFrame.new(0, 0.6, 0), P.IceLight, M.Ice, head)
	end
	-- frost breath: a slow cold plume from the snout
	local mouth = Instance.new("Attachment")
	mouth.Name = "Breath"
	mouth.CFrame = snout.CFrame:ToObjectSpace(snout.CFrame * CFrame.new(0, -0.3, -0.9))
	mouth.Parent = snout
	local breath = Instance.new("ParticleEmitter")
	breath.Name = "FrostBreath"
	breath.Color = ColorSequence.new(rgb(210, 236, 255))
	breath.LightEmission = 0.5
	breath.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 2.2) })
	breath.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	breath.Lifetime = NumberRange.new(1.4, 2.2)
	breath.Speed = NumberRange.new(1.2, 2.4)
	breath.SpreadAngle = Vector2.new(18, 18)
	breath.Rate = 6
	breath.EmissionDirection = Enum.NormalId.Front
	breath.Parent = mouth
	head.PrimaryPart = head:FindFirstChild("Skull")
	-- a faint cold glow so it reads in the dark (not eyes - it has none)
	light(m.Root, rgb(150, 210, 255), 16, 0.7)
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
	-- departure lights (blink faster as the sled gets ready to leave - client-side)
	for i, x in ipairs({ -2.4, 0, 2.4 }) do
		local bulb = part({ Name = "SledLight" .. i, Size = Vector3.new(0.6, 0.6, 0.6), Shape = Enum.PartType.Ball, CFrame = pivot * CFrame.new(x, 4.1, 5.4), Color = rgb(255, 120, 90), Material = M.Neon, Parent = m })
		light(bulb, rgb(255, 120, 90), 10, 0.6).Name = "SledGlow"
	end
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
	-- a column of light it sends up the sky as cores come in (seen from across the lake)
	part({ Name = "BeaconBeam", Size = Vector3.new(2.4, 220, 2.4), CFrame = pivot * CFrame.new(0, 125, 0), Color = P.Core, Material = M.Neon, Transparency = 1, Parent = m, CastShadow = false })
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

-- A standing ice spire: a tall, leaning shard with a few smaller ones at its foot.
function Models.spire(pivot, parent, rng)
	local m = model("IceSpire", parent, pivot)
	local function r()
		return if rng then rng:NextNumber() else 0.5
	end
	local h = 11 + r() * 7
	part({ Name = "Spire", Size = Vector3.new(1.8, h, 1.8), CFrame = pivot * CFrame.new(0, h / 2 - 0.5, 0) * CFrame.Angles(math.rad(r() * 8 - 4), r() * 3, math.rad(r() * 8 - 4)), Color = P.Crystal, Material = M.Glass, Transparency = 0.2, Parent = m, CanCollide = true })
	part({ Name = "Tip", Size = Vector3.new(0.9, 3, 0.9), CFrame = pivot * CFrame.new(0, h + 0.6, 0) * CFrame.Angles(0, math.rad(45), 0), Color = P.IceLight, Material = M.Ice, Parent = m })
	for i = 1, 3 do
		local a = i * 2.1 + r()
		local sh = 2 + r() * 3
		part({ Name = "Shard", Size = Vector3.new(0.8, sh, 0.8), CFrame = pivot * CFrame.new(math.cos(a) * 1.6, sh / 2 - 0.3, math.sin(a) * 1.6) * CFrame.Angles(math.cos(a) * 0.4, a, math.sin(a) * 0.4), Color = P.Crystal, Material = M.Glass, Transparency = 0.25, Parent = m, CanCollide = true })
	end
	return m
end

-- The half-sunken lighthouse in The Deep Hollow: a striped tower tipped over in the ice,
-- frost on everything, and a lamp that still flickers a cold, dying blue.
function Models.lighthouse(pivot, parent)
	local m = model("Lighthouse", parent, pivot)
	local tilt = pivot * CFrame.Angles(math.rad(11), math.rad(25), math.rad(-7)) * CFrame.new(0, -4, 0)
	local stripes = { rgb(170, 70, 70), rgb(224, 222, 214) }
	for i = 0, 5 do
		local w = 9 - i * 0.6
		part({ Name = "Tower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, w, w), CFrame = tilt * CFrame.new(0, 2 + i * 4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = stripes[(i % 2) + 1]:Lerp(rgb(150, 180, 210), 0.35), Material = M.Concrete, Parent = m, CanCollide = true })
	end
	local top = tilt * CFrame.new(0, 25, 0)
	part({ Name = "Gallery", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 8.6, 8.6), CFrame = top * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(60, 66, 80), Material = M.Metal, Parent = m })
	part({ Name = "LampRoom", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 5.2, 5.2), CFrame = top * CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(150, 210, 240), Material = M.Glass, Transparency = 0.4, Parent = m })
	local lamp = part({ Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = top * CFrame.new(0, 2.2, 0), Color = rgb(120, 200, 255), Material = M.Neon, Parent = m })
	local l = light(lamp, rgb(120, 200, 255), 46, 1.6)
	l.Name = "LighthouseLight"
	part({ Name = "Cap", Size = Vector3.new(4.8, 1.8, 4.8), CFrame = top * CFrame.new(0, 5, 0) * CFrame.Angles(0, math.rad(45), 0), Color = rgb(60, 66, 80), Material = M.Metal, Parent = m })
	part({ Name = "CapSnow", Size = Vector3.new(4.2, 0.6, 4.2), CFrame = top * CFrame.new(0, 6.1, 0) * CFrame.Angles(0, math.rad(45), 0), Color = P.Snow, Material = M.Snow, Parent = m })
	-- the ice heaved up where it went in, with icicles off the gallery
	for i = 0, 7 do
		local a = i * math.pi / 4 + 0.2
		part({ Name = "Heave", Size = Vector3.new(4, 1.6 + (i % 3) * 0.6, 2.4), CFrame = pivot * CFrame.new(math.cos(a) * 6.5, 0.4, math.sin(a) * 6.5) * CFrame.Angles(math.rad(14), a, math.rad(10)), Color = P.IceLight, Material = M.Ice, Parent = m, CanCollide = true })
		part({ Name = "Icicle", Size = Vector3.new(0.3, 1.8 + (i % 2), 0.3), CFrame = top * CFrame.new(math.cos(a) * 4.1, -1.2, math.sin(a) * 4.1), Color = P.Crystal, Material = M.Glass, Transparency = 0.2, Parent = m })
	end
	return m, lamp
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
