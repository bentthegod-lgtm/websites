--[[
	MagnetModel - the wearable magnet rig: a back-mounted power pack with a jointed arm that
	holds a horseshoe electromagnet over the right shoulder, pointing forward. It needs no
	custom animations and stays visible in third person.

	build(tierIndex, skinId, rootCFrame) returns (model, parts) where parts =
	{ mount, core, emitter (Attachment at the magnet face), coils = {...}, glow = PointLight }.
	Every part is unanchored, massless and non-colliding, welded to `mount`; the server
	welds `mount` to the character's HumanoidRootPart.

	Higher tiers get more coils, a bigger glowing core, fins, rings and a halo. Skins only
	recolour. To use Blender meshes later, swap the part builders below for MeshParts that
	keep the same names (Mount / Core / MagnetHead).
]]

local MagnetConfig = require(script.Parent.Config.MagnetConfig)

local MagnetModel = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local at = CFrame.new
local ang = CFrame.Angles

local function c3(t)
	return rgb(t[1], t[2], t[3])
end

-- Position of the magnet head relative to the root part (used by effects and the server).
MagnetModel.HeadOffset = CFrame.new(1.75, 2.45, -0.9)

function MagnetModel.visual(tierIndex, skinId)
	local tier = MagnetConfig.Tiers[math.clamp(tierIndex or 1, 1, #MagnetConfig.Tiers)]
	local v = table.clone(tier.Visual)
	local skin = MagnetConfig.Skins[skinId or "Default"]
	if skin then
		for _, key in ipairs({ "Body", "Prong", "Tip", "Core" }) do
			if skin[key] then
				v[key] = skin[key]
			end
		end
	end
	return v
end

function MagnetModel.build(tierIndex, skinId, rootCFrame)
	local v = MagnetModel.visual(tierIndex, skinId)
	rootCFrame = rootCFrame or CFrame.new()
	local model = Instance.new("Model")
	model.Name = "MagnetRig"
	local material = M[v.Material] or M.Metal

	local mount = Instance.new("Part")
	mount.Name = "Mount"
	mount.Size = Vector3.new(0.2, 0.2, 0.2)
	mount.Transparency = 1
	mount.CFrame = rootCFrame
	mount.Parent = model
	model.PrimaryPart = mount

	local parts = { mount = mount, coils = {} }
	local function part(name, size, offset, color, mat, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = mat or material
		if shape then
			p.Shape = shape
		end
		p.CFrame = rootCFrame * offset
		p.Parent = model
		return p
	end

	local body, prong, tip, core = c3(v.Body), c3(v.Prong), c3(v.Tip), c3(v.Core)
	-- Back pack.
	part("Pack", Vector3.new(1.7, 1.9, 0.75), at(0, 0.45, 0.95), body)
	part("PackLid", Vector3.new(1.8, 0.3, 0.85), at(0, 1.5, 0.95), c3({ v.Body[1] * 0.8, v.Body[2] * 0.8, v.Body[3] * 0.8 }))
	part("Warning", Vector3.new(0.9, 0.35, 0.04), at(0, 0.6, 1.34), rgb(236, 186, 46), M.SmoothPlastic)
	part("WarningMark", Vector3.new(0.12, 0.25, 0.05), at(0, 0.6, 1.36), rgb(30, 30, 30), M.SmoothPlastic)
	part("Battery", Vector3.new(0.5, 1.3, 0.5), at(-0.55, 0.4, 1.42), rgb(40, 40, 44), M.Metal, Enum.PartType.Block)
	local gauge = part("Gauge", Vector3.new(0.3, 0.3, 0.06), at(0.5, 1.05, 1.36), core, M.Neon)
	gauge.Name = "Gauge"
	if v.Fins then
		for i = -1, 1 do
			part("Fin" .. i, Vector3.new(0.08, 1.4, 0.5), at(i * 0.45, 0.45, 1.45), body)
		end
	end
	-- Arm over the right shoulder.
	part("ArmBase", Vector3.new(0.45, 0.45, 0.45), at(0.75, 1.45, 0.85), rgb(50, 50, 54), M.Metal, Enum.PartType.Ball)
	part("ArmLower", Vector3.new(0.3, 1.5, 0.3), at(1.15, 1.95, 0.45) * ang(-0.55, 0, -0.5), rgb(70, 70, 76))
	part("ArmElbow", Vector3.new(0.4, 0.4, 0.4), at(1.5, 2.45, 0.05), rgb(50, 50, 54), M.Metal, Enum.PartType.Ball)
	part("ArmUpper", Vector3.new(0.28, 0.28, 0.9), at(1.7, 2.45, -0.3), rgb(70, 70, 76))
	part("Cable", Vector3.new(0.12, 0.12, 1.6), at(0.9, 1.9, 0.6) * ang(0.6, 0.5, 0), rgb(30, 30, 30), M.Rubber)

	-- Horseshoe magnet head (prongs point forward, -Z).
	local head = MagnetModel.HeadOffset
	local headPart = part("MagnetHead", Vector3.new(1.3, 0.55, 0.55), head * at(0, 0, 0.35) * ang(0, 0, 0), prong)
	headPart.Shape = Enum.PartType.Block
	part("Bend", Vector3.new(1.2, 0.6, 0.6), head * at(0, 0, 0.42) * ang(0, 0, 0), prong, material, Enum.PartType.Cylinder)
	for _, x in ipairs({ -0.42, 0.42 }) do
		part("Prong" .. x, Vector3.new(0.42, 0.52, 1.15), head * at(x, 0, -0.3), prong)
		part("Tip" .. x, Vector3.new(0.44, 0.54, 0.32), head * at(x, 0, -1.0), tip, M.Metal)
	end
	local coilColor = if v.Copper then rgb(196, 112, 60) else rgb(60, 60, 70)
	for i = 1, v.Coils do
		local z = 0.15 - (i - 1) * (1.0 / math.max(1, v.Coils))
		for _, x in ipairs({ -0.42, 0.42 }) do
			local coil = part("Coil" .. i .. x, Vector3.new(0.14, 0.66, 0.66), head * at(x, 0, z) * ang(0, math.rad(90), 0), coilColor, M.Metal, Enum.PartType.Cylinder)
			table.insert(parts.coils, coil)
		end
	end
	local corePart = part("Core", Vector3.new(v.CoreSize, v.CoreSize, v.CoreSize), head * at(0, 0.35, 0.42), core, M.Neon, Enum.PartType.Ball)
	corePart.Transparency = 0.15
	parts.core = corePart
	if v.Ring then
		local ring = part("Ring", Vector3.new(0.1, 2.0, 2.0), head * at(0, 0, -0.5) * ang(0, math.rad(90), 0), core, M.Neon, Enum.PartType.Cylinder)
		ring.Transparency = 0.6
		parts.ring = ring
	end
	if v.Halo then
		local halo = part("Halo", Vector3.new(0.06, 3.2, 3.2), at(0, 2.2, 1.1) * ang(0, math.rad(90), 0), core, M.Neon, Enum.PartType.Cylinder)
		halo.Transparency = 0.7
	end

	local emitter = Instance.new("Attachment")
	emitter.Name = "Emitter"
	emitter.Position = Vector3.new(0, 0, -0.85)
	emitter.Parent = headPart
	parts.emitter = emitter
	parts.head = headPart

	local glow = Instance.new("PointLight")
	glow.Name = "CoreGlow"
	glow.Color = core
	glow.Range = 6 + v.Glow * 2
	glow.Brightness = 0.4
	glow.Shadows = false
	glow.Parent = corePart
	parts.glow = glow

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = false
			if d ~= mount then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = mount
				weld.Part1 = d
				weld.Parent = d
			end
		end
	end
	model:SetAttribute("Tier", tierIndex)
	model:SetAttribute("GlowScale", v.Glow)
	return model, parts
end

return MagnetModel
