--[[
	TeacherRig - builds a friendly, slightly cartoony teacher NPC from parts with Motor6D
	joints (RootJoint, Neck, Left/RightShoulder, Left/RightHip) so the client can animate
	her procedurally (TeacherController sets Motor6D.Transform every frame).

	The Root part is anchored and invisible; the server moves it. Every other part is
	unanchored, massless and non-colliding, held by the joints / welds.

	TeacherRig.build(style) -> model, joints
	style = { Name, Skin, Shirt, Cardigan, Pants, Hair, Shoes, Accent, Glasses = bool,
	          Bun = bool, Tie = bool, Height = number (scale), Skirt = bool, Beard = bool }
]]

local TeacherRig = {}

TeacherRig.Styles = {
	Teacher = {
		Name = "Ms. Bellweather",
		Skin = { 236, 196, 160 },
		Shirt = { 250, 246, 236 },
		Cardigan = { 64, 168, 160 },
		Pants = { 70, 72, 100 },
		Skirt = true,
		Hair = { 120, 70, 40 },
		Shoes = { 90, 50, 40 },
		Accent = { 255, 120, 90 }, -- lanyard + earrings
		Glasses = true,
		Bun = true,
		Height = 1,
	},
	Substitute = {
		Name = "Mr. Dozely",
		Skin = { 205, 160, 120 },
		Shirt = { 210, 200, 150 },
		Cardigan = { 140, 110, 80 }, -- tweed-ish vest
		Pants = { 90, 80, 70 },
		Hair = { 170, 170, 175 },
		Shoes = { 60, 45, 35 },
		Accent = { 90, 120, 200 },
		Glasses = false,
		Bun = false,
		Tie = true,
		Beard = true,
		Height = 0.97,
	},
	Principal = {
		Name = "Principal Granite",
		Skin = { 150, 105, 75 },
		Shirt = { 240, 240, 245 },
		Cardigan = { 45, 50, 70 }, -- suit jacket
		Pants = { 45, 50, 70 },
		Hair = { 40, 35, 35 },
		Shoes = { 25, 25, 28 },
		Accent = { 200, 40, 50 },
		Glasses = true,
		Bun = false,
		Tie = true,
		Height = 1.12,
	},
}

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Roblox forces Ball parts to a uniform size, so non-uniform "balls" (eyes, hair, cheeks)
-- use a Block with a built-in Sphere SpecialMesh instead (no imported assets).
local function shapeBall(p, size)
	if math.abs(size.X - size.Y) < 1e-3 and math.abs(size.Y - size.Z) < 1e-3 then
		p.Shape = Enum.PartType.Ball
		return
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
end

local function newPart(model, name, size, color, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	for k, v in pairs(props or {}) do
		if k == "Shape" and v == Enum.PartType.Ball then
			shapeBall(p, (props and props.Size) or size)
		elseif k ~= "Size" or not (props and props.Shape == Enum.PartType.Ball) then
			p[k] = v
		end
	end
	if props and props.Size and props.Shape == Enum.PartType.Ball then
		p.Size = props.Size
	end
	p.Parent = model
	return p
end

-- Welds `part` to `to` keeping the given offset (relative to `to`).
local function attach(part, to, offset)
	part.CFrame = to.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function motor(name, part0, part1, c0, c1)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
	part1.CFrame = part0.CFrame * c0 * c1:Inverse()
	return m
end

function TeacherRig.build(style, cframe)
	style = style or TeacherRig.Styles.Teacher
	local s = style.Height or 1
	local model = Instance.new("Model")
	model.Name = style.Name or "Teacher"
	cframe = cframe or CFrame.new()

	local legH, torsoH, torsoW, armH = 2.6 * s, 2.5 * s, 2.2 * s, 2.3 * s
	local root = newPart(model, "Root", Vector3.new(2, 2, 1), rgb(style.Pants), { Transparency = 1, Anchored = true, CastShadow = false })
	root.CFrame = cframe * CFrame.new(0, legH, 0)
	model.PrimaryPart = root
	model:SetAttribute("LegH", legH)

	local torso = newPart(model, "Torso", Vector3.new(torsoW, torsoH, 1.1 * s), rgb(style.Shirt))
	local joints = {}
	joints.RootJoint = motor("RootJoint", root, torso, CFrame.new(0, torsoH / 2, 0), CFrame.new())

	-- Cardigan / jacket: two front panels and a back panel over the shirt.
	local cardigan = rgb(style.Cardigan)
	attach(newPart(model, "JacketBack", Vector3.new(torsoW + 0.08, torsoH - 0.1, 0.2), cardigan), torso, CFrame.new(0, 0.02, 0.5 * s))
	for side = -1, 1, 2 do
		attach(newPart(model, "JacketFront", Vector3.new(torsoW * 0.36, torsoH - 0.1, 0.16), cardigan), torso, CFrame.new(side * torsoW * 0.33, 0.02, -0.56 * s))
		attach(newPart(model, "Pocket", Vector3.new(0.45, 0.35, 0.06), cardigan:Lerp(Color3.new(0, 0, 0), 0.15)), torso, CFrame.new(side * torsoW * 0.33, -0.65 * s, -0.66 * s))
	end
	attach(newPart(model, "Collar", Vector3.new(torsoW * 0.5, 0.3, 1.0 * s), rgb(style.Shirt)), torso, CFrame.new(0, torsoH / 2 - 0.1, -0.02))
	for i = 0, 2 do
		attach(newPart(model, "Button", Vector3.new(0.12, 0.12, 0.06), Color3.fromRGB(240, 220, 160), { Shape = Enum.PartType.Ball }), torso, CFrame.new(torsoW * 0.15, 0.6 - i * 0.55, -0.66 * s))
	end
	if style.Tie then
		attach(newPart(model, "Tie", Vector3.new(0.32, torsoH * 0.62, 0.08), rgb(style.Accent)), torso, CFrame.new(0, torsoH * 0.12, -0.6 * s))
	else
		-- Lanyard with a staff badge
		attach(newPart(model, "Lanyard", Vector3.new(0.9, 0.06, 0.06), rgb(style.Accent)), torso, CFrame.new(0, 0.9 * s, -0.62 * s) * CFrame.Angles(0, 0, 0))
		attach(newPart(model, "LanyardL", Vector3.new(0.06, 1.1, 0.06), rgb(style.Accent)), torso, CFrame.new(-0.42, 0.35 * s, -0.62 * s) * CFrame.Angles(0, 0, math.rad(-12)))
		attach(newPart(model, "LanyardR", Vector3.new(0.06, 1.1, 0.06), rgb(style.Accent)), torso, CFrame.new(0.42, 0.35 * s, -0.62 * s) * CFrame.Angles(0, 0, math.rad(12)))
		attach(newPart(model, "Badge", Vector3.new(0.5, 0.36, 0.05), Color3.fromRGB(250, 250, 255)), torso, CFrame.new(0, -0.25 * s, -0.66 * s))
	end

	-- Hips / skirt
	if style.Skirt then
		attach(newPart(model, "Skirt", Vector3.new(torsoW + 0.15, 1.3 * s, 1.3 * s), rgb(style.Pants)), torso, CFrame.new(0, -torsoH / 2 - 0.45 * s, 0))
	else
		attach(newPart(model, "Belt", Vector3.new(torsoW + 0.04, 0.25, 1.14 * s), Color3.fromRGB(40, 30, 25)), torso, CFrame.new(0, -torsoH / 2 + 0.12, 0))
	end

	-- Head
	local skin = rgb(style.Skin)
	local head = newPart(model, "Head", Vector3.new(1.75 * s, 1.75 * s, 1.75 * s), skin, { Shape = Enum.PartType.Ball })
	joints.Neck = motor("Neck", torso, head, CFrame.new(0, torsoH / 2, 0), CFrame.new(0, -0.95 * s, 0))
	attach(newPart(model, "NeckPart", Vector3.new(0.6, 0.5, 0.6), skin, { Shape = Enum.PartType.Cylinder }), torso, CFrame.new(0, torsoH / 2 + 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local eyeColor = Color3.fromRGB(35, 30, 40)
	for side = -1, 1, 2 do
		attach(newPart(model, "Eye", Vector3.new(0.22, 0.28, 0.12), eyeColor, { Shape = Enum.PartType.Ball }), head, CFrame.new(side * 0.33 * s, 0.1 * s, -0.8 * s))
		attach(newPart(model, "EyeShine", Vector3.new(0.07, 0.07, 0.05), Color3.new(1, 1, 1), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon }), head, CFrame.new(side * 0.33 * s + 0.04, 0.16 * s, -0.86 * s))
		attach(newPart(model, "Cheek", Vector3.new(0.3, 0.16, 0.08), Color3.fromRGB(255, 150, 150), { Shape = Enum.PartType.Ball, Transparency = 0.35 }), head, CFrame.new(side * 0.5 * s, -0.2 * s, -0.72 * s))
		attach(newPart(model, "Brow", Vector3.new(0.34, 0.07, 0.06), rgb(style.Hair):Lerp(Color3.new(0, 0, 0), 0.2)), head, CFrame.new(side * 0.33 * s, 0.38 * s, -0.8 * s) * CFrame.Angles(0, 0, math.rad(side * -6)))
		attach(newPart(model, "Ear", Vector3.new(0.2, 0.42, 0.3), skin, { Shape = Enum.PartType.Ball }), head, CFrame.new(side * 0.88 * s, 0, 0))
		if style.Glasses then
			attach(newPart(model, "Lens", Vector3.new(0.48, 0.4, 0.05), Color3.fromRGB(40, 40, 50), { Transparency = 0.15 }), head, CFrame.new(side * 0.33 * s, 0.1 * s, -0.88 * s))
			attach(newPart(model, "LensGlass", Vector3.new(0.38, 0.3, 0.03), Color3.fromRGB(200, 230, 255), { Transparency = 0.6, Material = Enum.Material.Glass }), head, CFrame.new(side * 0.33 * s, 0.1 * s, -0.91 * s))
		end
		if not style.Tie then
			attach(newPart(model, "Earring", Vector3.new(0.12, 0.12, 0.12), rgb(style.Accent), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon }), head, CFrame.new(side * 0.9 * s, -0.3 * s, 0))
		end
	end
	if style.Glasses then
		attach(newPart(model, "Bridge", Vector3.new(0.2, 0.05, 0.05), Color3.fromRGB(40, 40, 50)), head, CFrame.new(0, 0.12 * s, -0.9 * s))
	end
	attach(newPart(model, "Nose", Vector3.new(0.2, 0.25, 0.2), skin:Lerp(Color3.fromRGB(220, 140, 120), 0.25), { Shape = Enum.PartType.Ball }), head, CFrame.new(0, -0.08 * s, -0.86 * s))
	local mouth = attach(newPart(model, "Mouth", Vector3.new(0.42, 0.09, 0.06), Color3.fromRGB(150, 60, 70)), head, CFrame.new(0, -0.42 * s, -0.78 * s))
	mouth:SetAttribute("Smile", true)

	-- Hair
	local hair = rgb(style.Hair)
	attach(newPart(model, "HairTop", Vector3.new(1.86 * s, 1.0 * s, 1.86 * s), hair, { Shape = Enum.PartType.Ball }), head, CFrame.new(0, 0.42 * s, 0.06))
	attach(newPart(model, "HairBack", Vector3.new(1.8 * s, 1.3 * s, 0.9 * s), hair, { Shape = Enum.PartType.Ball }), head, CFrame.new(0, 0.05, 0.45 * s))
	if style.Bun then
		attach(newPart(model, "Bun", Vector3.new(0.85, 0.85, 0.85), hair, { Shape = Enum.PartType.Ball }), head, CFrame.new(0, 0.85 * s, 0.55 * s))
		attach(newPart(model, "Pencil", Vector3.new(0.08, 0.08, 1.1), Color3.fromRGB(255, 205, 60)), head, CFrame.new(0.1, 0.95 * s, 0.55 * s) * CFrame.Angles(0, math.rad(70), math.rad(20)))
	end
	if style.Beard then
		attach(newPart(model, "Beard", Vector3.new(1.3 * s, 0.7 * s, 0.6 * s), hair, { Shape = Enum.PartType.Ball }), head, CFrame.new(0, -0.6 * s, -0.45 * s))
		attach(newPart(model, "Moustache", Vector3.new(0.7, 0.18, 0.15), hair), head, CFrame.new(0, -0.3 * s, -0.84 * s))
	end

	-- Arms (pivot at the shoulder)
	local sleeve = cardigan
	for side = -1, 1, 2 do
		local arm = newPart(model, if side < 0 then "LeftArm" else "RightArm", Vector3.new(0.68 * s, armH, 0.7 * s), sleeve)
		local jointName = if side < 0 then "LeftShoulder" else "RightShoulder"
		joints[jointName] = motor(jointName, torso, arm, CFrame.new(side * (torsoW / 2 + 0.36 * s), torsoH / 2 - 0.3 * s, 0), CFrame.new(0, armH / 2 - 0.3 * s, 0))
		attach(newPart(model, "Cuff", Vector3.new(0.74 * s, 0.22, 0.76 * s), rgb(style.Shirt)), arm, CFrame.new(0, -armH / 2 + 0.25, 0))
		attach(newPart(model, "Hand", Vector3.new(0.62 * s, 0.62 * s, 0.62 * s), skin, { Shape = Enum.PartType.Ball }), arm, CFrame.new(0, -armH / 2 - 0.12, 0))
		if side > 0 then
			-- Whiteboard marker in the right hand
			local marker = attach(newPart(model, "Marker", Vector3.new(0.16, 0.7, 0.16), Color3.fromRGB(40, 90, 220)), arm, CFrame.new(0, -armH / 2 - 0.3, -0.25) * CFrame.Angles(math.rad(70), 0, 0))
			marker.Name = "Marker"
		end
	end

	-- Legs
	for side = -1, 1, 2 do
		local leg = newPart(model, if side < 0 then "LeftLeg" else "RightLeg", Vector3.new(0.85 * s, legH, 0.9 * s), if style.Skirt then skin:Lerp(Color3.fromRGB(60, 60, 80), 0.55) else rgb(style.Pants))
		local jointName = if side < 0 then "LeftHip" else "RightHip"
		joints[jointName] = motor(jointName, torso, leg, CFrame.new(side * 0.55 * s, -torsoH / 2, 0), CFrame.new(0, legH / 2, 0))
		attach(newPart(model, "Shoe", Vector3.new(0.95 * s, 0.42, 1.35 * s), rgb(style.Shoes)), leg, CFrame.new(0, -legH / 2 + 0.2, -0.2 * s))
	end

	-- Name tag (always visible): who is watching you.
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(220, 34)
	tag.StudsOffset = Vector3.new(0, 2.2 * s, 0)
	tag.AlwaysOnTop = false
	tag.MaxDistance = 120
	tag.Adornee = head
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = style.Name or "Teacher"
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = tag
	tag.Parent = head

	return model, joints
end

-- Places the rig at (x, z) facing `heading` (radians, facing = (sin h, cos h)).
function TeacherRig.place(model, x, z, heading, floorY)
	local y = (floorY or 0) + (model:GetAttribute("LegH") or 2.6)
	model.PrimaryPart.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, heading + math.pi, 0)
end

return TeacherRig
