--[[
	DummyModel - the crash-test dummy, built from parts.

	build(skinId, cframe, opts) returns (model, parts):
	  * opts.ragdoll (default true): 11 unanchored body parts joined by BallSocketConstraints
	    with angle limits (neck, shoulders, elbows, hips, knees), NoCollisionConstraints
	    between joined pairs (so limbs don't fight each other), and physical properties
	    from the dummy class (density / elasticity). Decorations (crash-test quadrant
	    markers, visor) are massless, non-colliding and welded.
	  * opts.ragdoll = false: everything anchored (lobby displays, previews).
	The torso is the PrimaryPart and is named "Root"; the server samples it.
	No humanoid: the dummy is a pure physics object, so it can't be "controlled".
]]

local CosmeticConfig = require(script.Parent.Config.CosmeticConfig)

local DummyModel = {}

local rgb = Color3.fromRGB
local function color(t)
	return rgb(t[1], t[2], t[3])
end

-- name, size, offset from root (dummy standing, root at torso centre)
local BODY = {
	{ "Root", Vector3.new(2, 1.7, 1.1), Vector3.new(0, 0, 0) },
	{ "Pelvis", Vector3.new(1.8, 0.8, 1), Vector3.new(0, -1.3, 0) },
	{ "Head", Vector3.new(1.35, 1.45, 1.35), Vector3.new(0, 1.65, 0), Enum.PartType.Ball },
	{ "LeftUpperArm", Vector3.new(0.62, 1.2, 0.62), Vector3.new(-1.36, 0.2, 0) },
	{ "LeftLowerArm", Vector3.new(0.56, 1.15, 0.56), Vector3.new(-1.36, -1.0, 0) },
	{ "RightUpperArm", Vector3.new(0.62, 1.2, 0.62), Vector3.new(1.36, 0.2, 0) },
	{ "RightLowerArm", Vector3.new(0.56, 1.15, 0.56), Vector3.new(1.36, -1.0, 0) },
	{ "LeftUpperLeg", Vector3.new(0.78, 1.35, 0.78), Vector3.new(-0.5, -2.4, 0) },
	{ "LeftLowerLeg", Vector3.new(0.72, 1.35, 0.72), Vector3.new(-0.5, -3.75, 0) },
	{ "RightUpperLeg", Vector3.new(0.78, 1.35, 0.78), Vector3.new(0.5, -2.4, 0) },
	{ "RightLowerLeg", Vector3.new(0.72, 1.35, 0.72), Vector3.new(0.5, -3.75, 0) },
}
DummyModel.PartNames = {}
for _, b in ipairs(BODY) do
	table.insert(DummyModel.PartNames, b[1])
end

-- part0, part1, joint position (root space), cone limit (deg), twist (deg)
local JOINTS = {
	{ "Root", "Head", Vector3.new(0, 0.9, 0), 35, 30 },
	{ "Root", "Pelvis", Vector3.new(0, -0.9, 0), 25, 20 },
	{ "Root", "LeftUpperArm", Vector3.new(-1.1, 0.7, 0), 95, 45 },
	{ "LeftUpperArm", "LeftLowerArm", Vector3.new(-1.36, -0.42, 0), 70, 10 },
	{ "Root", "RightUpperArm", Vector3.new(1.1, 0.7, 0), 95, 45 },
	{ "RightUpperArm", "RightLowerArm", Vector3.new(1.36, -0.42, 0), 70, 10 },
	{ "Pelvis", "LeftUpperLeg", Vector3.new(-0.5, -1.7, 0), 75, 25 },
	{ "LeftUpperLeg", "LeftLowerLeg", Vector3.new(-0.5, -3.08, 0), 70, 8 },
	{ "Pelvis", "RightUpperLeg", Vector3.new(0.5, -1.7, 0), 75, 25 },
	{ "RightUpperLeg", "RightLowerLeg", Vector3.new(0.5, -3.08, 0), 70, 8 },
}

-- Standing height (feet to head top) and root height above the feet.
DummyModel.RootHeight = 4.43
DummyModel.Height = 6.8

local function part(name, size, cf, col, shape, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = col
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function decorate(target, size, offset, col, material, shape)
	local d = Instance.new("Part")
	d.Name = "Deco"
	d.Size = size
	d.CFrame = target.CFrame * offset
	d.Color = col
	d.Material = material or Enum.Material.SmoothPlastic
	if shape then
		d.Shape = shape
	end
	d.Massless = true
	d.CanCollide = false
	d.CanQuery = false
	d.CanTouch = false
	d.CastShadow = false
	d.Anchored = target.Anchored
	d.Parent = target
	if not target.Anchored then
		local w = Instance.new("WeldConstraint")
		w.Part0 = target
		w.Part1 = d
		w.Parent = d
	end
	return d
end

-- Crash-test quadrant marker: a yellow/black disc split into four.
local function marker(target, offset, accent, body)
	local disc = CFrame.Angles(0, math.rad(90), 0)
	decorate(target, Vector3.new(0.06, 0.62, 0.62), offset * disc, accent, nil, Enum.PartType.Cylinder)
	decorate(target, Vector3.new(0.08, 0.31, 0.04), offset * CFrame.new(0, 0.155, 0), body)
	decorate(target, Vector3.new(0.04, 0.31, 0.08), offset * CFrame.new(0, -0.155, 0) * CFrame.Angles(0, math.rad(90), 0), body)
end

function DummyModel.build(skinId, cframe, opts)
	opts = opts or {}
	local ragdoll = opts.ragdoll ~= false
	local skin = CosmeticConfig.Skins[skinId or "Default"] or CosmeticConfig.Skins.Default
	local body = color(skin.Body)
	local accent = color(skin.Accent)
	local material = if skin.Material then Enum.Material[skin.Material] else Enum.Material.SmoothPlastic
	local model = Instance.new("Model")
	model.Name = "CrashDummy"
	local parts = {}
	for _, b in ipairs(BODY) do
		local p = part(b[1], b[2], cframe * CFrame.new(b[3]), body, b[4], model)
		p.Material = material
		p.Anchored = not ragdoll
		p.CanCollide = true
		p.CanQuery = false -- never blocks raycasts / camera
		if ragdoll and opts.physics then
			p.CustomPhysicalProperties = PhysicalProperties.new(opts.physics.Density, 0.45, opts.physics.Elasticity, 1, 1)
		end
		parts[b[1]] = p
	end
	model.PrimaryPart = parts.Root
	-- Joints-coloured accents: dark hands / feet / belt make the pose readable mid-air.
	parts.LeftLowerLeg.Color = accent
	parts.RightLowerLeg.Color = accent
	parts.Pelvis.Color = accent:Lerp(body, 0.4)
	-- Decorations.
	marker(parts.Head, CFrame.new(0.68, 0.05, 0), accent, body)
	marker(parts.Head, CFrame.new(-0.68, 0.05, 0) * CFrame.Angles(0, math.rad(180), 0), accent, body)
	marker(parts.Root, CFrame.new(0, 0.2, -0.56) * CFrame.Angles(0, math.rad(90), 0), accent, body)
	decorate(parts.Head, Vector3.new(0.9, 0.32, 0.12), CFrame.new(0, 0.12, -0.64), rgb(40, 42, 48)) -- visor slot
	decorate(parts.Root, Vector3.new(2.04, 0.18, 1.14), CFrame.new(0, -0.55, 0), accent) -- chest band
	decorate(parts.LeftLowerArm, Vector3.new(0.6, 0.35, 0.6), CFrame.new(0, -0.55, 0), accent)
	decorate(parts.RightLowerArm, Vector3.new(0.6, 0.35, 0.6), CFrame.new(0, -0.55, 0), accent)
	if ragdoll then
		for _, j in ipairs(JOINTS) do
			local p0, p1 = parts[j[1]], parts[j[2]]
			local world = cframe * CFrame.new(j[3])
			local a0 = Instance.new("Attachment")
			a0.Name = "J_" .. j[2]
			a0.CFrame = p0.CFrame:ToObjectSpace(world) * CFrame.Angles(0, 0, math.rad(-90))
			a0.Parent = p0
			local a1 = Instance.new("Attachment")
			a1.Name = "J_" .. j[2]
			a1.CFrame = p1.CFrame:ToObjectSpace(world) * CFrame.Angles(0, 0, math.rad(-90))
			a1.Parent = p1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "Joint_" .. j[2]
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = j[4]
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -j[5]
			socket.TwistUpperAngle = j[5]
			socket.Restitution = 0.05
			socket.Parent = p1
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = p0
			nc.Part1 = p1
			nc.Parent = p1
		end
		-- Legs and arms never fight each other either.
		for _, pair in ipairs({ { "LeftUpperLeg", "RightUpperLeg" }, { "LeftLowerLeg", "RightLowerLeg" }, { "LeftUpperArm", "Head" }, { "RightUpperArm", "Head" } }) do
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = parts[pair[1]]
			nc.Part1 = parts[pair[2]]
			nc.Parent = parts[pair[1]]
		end
	end
	return model, parts
end

-- Every body part (not decorations) - the parts that can touch the course.
function DummyModel.bodyParts(model)
	local list = {}
	for _, name in ipairs(DummyModel.PartNames) do
		local p = model:FindFirstChild(name)
		if p then
			table.insert(list, p)
		end
	end
	return list
end

return DummyModel
