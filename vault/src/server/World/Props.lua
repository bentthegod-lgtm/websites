--[[
	Props - reusable environment pieces for VaultBuilder, all built from parts.
	Every function takes a Builder context (see Props.builder) and a CFrame in world space.

	Collision: structure (walls, racks, machinery, barriers) collides; small decoration
	(cables, labels, lenses, bolts) does not, and nothing decorative is queryable, so it
	never blocks the camera or interaction checks.
]]

local Props = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local UP = CFrame.Angles(0, 0, math.pi / 2)
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

Props.Colors = {
	Steel = rgb(78, 82, 90),
	SteelDark = rgb(46, 48, 54),
	SteelLight = rgb(130, 136, 146),
	Concrete = rgb(150, 150, 146),
	Hazard = rgb(236, 190, 40),
	Black = rgb(20, 20, 24),
	White = rgb(236, 236, 230),
	Red = rgb(220, 40, 40),
	Green = rgb(60, 220, 110),
	Amber = rgb(255, 170, 40),
	Glass = rgb(200, 226, 240),
	Wood = rgb(124, 86, 52),
	Bill = rgb(118, 164, 104),
	Gold = rgb(236, 184, 58),
}
local C = Props.Colors

function Props.rgb(t)
	return rgb(t[1], t[2], t[3])
end

-- A builder context: counts parts and parents them into `parent`.
function Props.builder(parent)
	local b = { parent = parent, count = 0 }
	function b.part(props)
		local p = Instance.new(props.Class or "Part")
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = props.Material or M.SmoothPlastic
		p.Color = props.Color or C.Steel
		p.Size = props.Size
		p.CFrame = props.CFrame
		if props.Shape then
			p.Shape = props.Shape
		end
		p.CanCollide = props.CanCollide ~= false
		p.CanQuery = props.CanQuery == true
		p.CanTouch = props.CanTouch == true
		p.CastShadow = props.CastShadow ~= false
		if props.Transparency then
			p.Transparency = props.Transparency
		end
		if props.Reflectance then
			p.Reflectance = props.Reflectance
		end
		p.Name = props.Name or "Part"
		p.Parent = props.Parent or b.parent
		b.count += 1
		return p
	end
	-- Decorative: no collision, no shadow for tiny bits.
	function b.deco(props)
		props.CanCollide = false
		if props.CastShadow == nil then
			props.CastShadow = props.Size.Magnitude > 3
		end
		return b.part(props)
	end
	function b.cyl(props)
		props.Shape = Enum.PartType.Cylinder
		return b.part(props)
	end
	function b.folder(name, parent)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent or b.parent
		return f
	end
	return b
end

-- Text on a part face.
function Props.text(part, face, text, opts)
	opts = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.PPS or 40
	gui.LightInfluence = opts.LightInfluence or 0.2
	gui.Brightness = opts.Brightness or 1.4
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = opts.Font or Enum.Font.GothamBlack
	label.TextColor3 = opts.Color or C.White
	label.TextStrokeTransparency = opts.Stroke or 1
	label.TextXAlignment = opts.AlignX or Enum.TextXAlignment.Center
	label.Parent = gui
	return label
end

-- Wall sign: a backing plate with text, mounted facing -Z of `cf` (cf.LookVector).
function Props.sign(b, cf, w, h, text, opts)
	opts = opts or {}
	local plate = b.deco({ Name = opts.Name or "Sign", Size = Vector3.new(w, h, 0.25), CFrame = cf, Color = opts.Back or C.SteelDark, Material = M.Metal })
	if opts.Trim ~= false then
		b.deco({ Name = "SignTrim", Size = Vector3.new(w + 0.3, 0.18, 0.3), CFrame = cf * CFrame.new(0, -h / 2 - 0.05, 0), Color = opts.TrimColor or C.Hazard, Material = M.Metal })
	end
	local label = Props.text(plate, Enum.NormalId.Front, text, { Color = opts.Color, PPS = opts.PPS or 30, Font = opts.Font })
	return plate, label
end

-- Ceiling light fixture with an actual light (SpotLight pointing down).
function Props.lightFixture(b, cf, color, brightness, range, length)
	length = length or 6
	b.deco({ Name = "FixtureHousing", Size = Vector3.new(length, 0.4, 1.2), CFrame = cf, Color = C.SteelDark, Material = M.Metal })
	local tube = b.deco({ Name = "FixtureTube", Size = Vector3.new(length - 0.4, 0.15, 0.8), CFrame = cf * CFrame.new(0, -0.25, 0), Color = color, Material = M.Neon })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 120
	light.Brightness = brightness or 2
	light.Range = range or 40
	light.Color = color
	light.Shadows = true
	light.Parent = tube
	return tube, light
end

-- Security camera on a wall bracket, looking along cf.LookVector, angled down.
function Props.camera(b, cf)
	b.deco({ Name = "CamBracket", Size = Vector3.new(0.3, 0.3, 1.2), CFrame = cf * CFrame.new(0, 0, -0.6), Color = C.SteelDark, Material = M.Metal })
	local body = cf * CFrame.new(0, -0.3, -1.4) * CFrame.Angles(math.rad(-22), 0, 0)
	b.deco({ Name = "CamBody", Size = Vector3.new(0.7, 0.6, 1.4), CFrame = body, Color = C.White, Material = M.SmoothPlastic })
	b.deco({ Name = "CamHood", Size = Vector3.new(0.85, 0.1, 1.6), CFrame = body * CFrame.new(0, 0.35, -0.1), Color = C.White })
	b.deco({ Name = "CamLens", Size = Vector3.new(0.1, 0.4, 0.4), CFrame = body * CFrame.new(0, 0, -0.72) * ALONG_Z, Color = C.Black, Material = M.Glass, Shape = Enum.PartType.Cylinder })
	b.deco({ Name = "CamLed", Size = Vector3.new(0.1, 0.1, 0.1), CFrame = body * CFrame.new(0.25, 0.18, -0.71), Color = C.Red, Material = M.Neon })
end

-- Access-control panel (keypad + card reader + status LED) on a wall, facing cf.LookVector.
function Props.accessPanel(b, cf, ok)
	b.deco({ Name = "AccessPanel", Size = Vector3.new(0.9, 1.3, 0.2), CFrame = cf, Color = C.SteelDark, Material = M.Metal })
	b.deco({ Name = "AccessScreen", Size = Vector3.new(0.6, 0.35, 0.05), CFrame = cf * CFrame.new(0, 0.35, -0.12), Color = if ok then C.Green else C.Red, Material = M.Neon })
	for row = 0, 2 do
		for col = 0, 2 do
			b.deco({ Name = "Key", Size = Vector3.new(0.14, 0.12, 0.05), CFrame = cf * CFrame.new((col - 1) * 0.2, -0.05 - row * 0.16, -0.12), Color = C.SteelLight, Material = M.Metal })
		end
	end
	b.deco({ Name = "CardSlot", Size = Vector3.new(0.5, 0.05, 0.08), CFrame = cf * CFrame.new(0, -0.55, -0.12), Color = C.Black })
end

-- Smaller secure access door in a wall (decorative, sealed), facing cf.LookVector.
function Props.accessDoor(b, cf, label)
	b.part({ Name = "DoorFrame", Size = Vector3.new(6, 9, 0.6), CFrame = cf * CFrame.new(0, 4.5, 0), Color = C.SteelDark, Material = M.Metal })
	b.deco({ Name = "DoorLeaf", Size = Vector3.new(4.6, 8, 0.4), CFrame = cf * CFrame.new(0, 4.2, -0.32), Color = C.Steel, Material = M.DiamondPlate })
	b.deco({ Name = "DoorWindow", Size = Vector3.new(1.4, 1.8, 0.1), CFrame = cf * CFrame.new(0, 6.2, -0.55), Color = C.Glass, Material = M.Glass, Transparency = 0.4 })
	b.deco({ Name = "DoorBar", Size = Vector3.new(3.6, 0.25, 0.3), CFrame = cf * CFrame.new(0, 3.8, -0.6), Color = C.SteelLight, Material = M.Metal })
	for _, y in ipairs({ 1.6, 6.8 }) do
		b.deco({ Name = "Hinge", Size = Vector3.new(0.3, 0.8, 0.3), CFrame = cf * CFrame.new(-2.45, y, -0.4), Color = C.SteelLight, Material = M.Metal })
	end
	Props.accessPanel(b, cf * CFrame.new(3.8, 4.4, -0.35), false)
	if label then
		Props.sign(b, cf * CFrame.new(0, 9.9, -0.4), 5, 0.9, label, { PPS = 40 })
	end
	b.deco({ Name = "HazardSill", Size = Vector3.new(6, 0.06, 1.2), CFrame = cf * CFrame.new(0, 0.03, -0.9), Color = C.Hazard })
end

-- Massive circular vault door in a reinforced frame. The door leaf is its own Model
-- ("Leaf") whose PrimaryPart sits on the hinge axis, so a client can swing it open.
-- cf: centre of the door on the wall plane, LookVector pointing out of the vault side.
function Props.vaultDoor(b, cf, diameter, accent, parent)
	diameter = diameter or 22
	local r = diameter / 2
	local frame = Instance.new("Model")
	frame.Name = "VaultDoor"
	frame.Parent = parent or b.parent
	local fb = Props.builder(frame)
	-- Square frame around the opening + ring of blocks.
	local segments = 20
	for i = 0, segments - 1 do
		local a = i / segments * math.pi * 2
		fb.part({ Name = "Ring", Size = Vector3.new(r * 2 * math.pi / segments + 0.4, 2.6, 3.2), CFrame = cf * CFrame.new(math.cos(a) * (r + 1.3), math.sin(a) * (r + 1.3), 0) * CFrame.Angles(0, 0, a + math.pi / 2), Color = C.SteelDark, Material = M.Metal })
	end
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		fb.deco({ Name = "FrameBolt", Size = Vector3.new(0.5, 0.7, 0.7), CFrame = cf * CFrame.new(math.cos(a) * (r + 1.3), math.sin(a) * (r + 1.3), -1.75) * ALONG_Z, Color = accent, Material = M.Metal, Shape = Enum.PartType.Cylinder })
	end
	-- Hinge block on the right side (from the vault side).
	local hingeX = r + 2.4
	fb.part({ Name = "HingeBlock", Size = Vector3.new(2.2, diameter * 0.7, 3.6), CFrame = cf * CFrame.new(hingeX, 0, -0.6), Color = C.Steel, Material = M.DiamondPlate })
	for _, y in ipairs({ -r * 0.45, 0, r * 0.45 }) do
		fb.deco({ Name = "HingePin", Size = Vector3.new(diameter * 0.12, 1.1, 1.1), CFrame = cf * CFrame.new(hingeX - 0.4, y, -2.3) * UP, Color = C.SteelLight, Material = M.Metal, Shape = Enum.PartType.Cylinder })
	end
	-- Leaf.
	local leaf = Instance.new("Model")
	leaf.Name = "Leaf"
	leaf.Parent = frame
	local lb = Props.builder(leaf)
	local pivot = lb.deco({ Name = "HingeAxis", Size = Vector3.new(0.4, 0.4, 0.4), CFrame = cf * CFrame.new(hingeX - 1.2, 0, -2.2), Transparency = 1 })
	lb.part({ Name = "Disc", Size = Vector3.new(2.6, diameter, diameter), CFrame = cf * CFrame.new(0, 0, -0.9) * ALONG_Z, Color = C.SteelLight, Material = M.Metal, Shape = Enum.PartType.Cylinder, Reflectance = 0.08 })
	lb.deco({ Name = "DiscRim", Size = Vector3.new(0.6, diameter * 0.94, diameter * 0.94), CFrame = cf * CFrame.new(0, 0, -2.3) * ALONG_Z, Color = C.Steel, Material = M.DiamondPlate, Shape = Enum.PartType.Cylinder })
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		lb.deco({ Name = "LockBolt", Size = Vector3.new(1.4, 0.9, 0.9), CFrame = cf * CFrame.new(math.cos(a) * r * 0.82, math.sin(a) * r * 0.82, -2.6) * ALONG_Z, Color = accent, Material = M.Metal, Shape = Enum.PartType.Cylinder })
	end
	lb.deco({ Name = "Hub", Size = Vector3.new(1.2, diameter * 0.2, diameter * 0.2), CFrame = cf * CFrame.new(0, 0, -2.9) * ALONG_Z, Color = C.SteelDark, Material = M.Metal, Shape = Enum.PartType.Cylinder })
	for i = 0, 2 do
		lb.deco({ Name = "Spoke", Size = Vector3.new(diameter * 0.5, 0.45, 0.45), CFrame = cf * CFrame.new(0, 0, -3.3) * CFrame.Angles(0, 0, i * math.pi / 3), Color = C.SteelLight, Material = M.Metal })
	end
	lb.deco({ Name = "WheelRim", Size = Vector3.new(0.4, diameter * 0.52, diameter * 0.52), CFrame = cf * CFrame.new(0, 0, -3.3) * ALONG_Z, Color = accent, Material = M.Metal, Shape = Enum.PartType.Cylinder, Transparency = 0 })
	leaf.PrimaryPart = pivot
	b.count += fb.count + lb.count
	return { model = frame, leaf = leaf, pivot = pivot }
end

-- Storage rack: uprights + shelves; returns the world CFrames of each shelf top centre.
-- cf: rack centre on the floor, LookVector = the side players stand on.
function Props.rack(b, cf, width, depth, shelves, height, color, heavy)
	local post = if heavy then 0.7 else 0.4
	for _, x in ipairs({ -width / 2, width / 2 }) do
		for _, z in ipairs({ -depth / 2, depth / 2 }) do
			b.part({ Name = "RackUpright", Size = Vector3.new(post, height, post), CFrame = cf * CFrame.new(x, height / 2, z), Color = color, Material = M.Metal })
		end
	end
	local tops = {}
	for i = 1, shelves do
		local y = 0.6 + (i - 1) * ((height - 1) / math.max(1, shelves - 1))
		b.part({ Name = "RackShelf", Size = Vector3.new(width, 0.25, depth), CFrame = cf * CFrame.new(0, y, 0), Color = if heavy then C.SteelDark else C.Steel, Material = M.DiamondPlate })
		b.deco({ Name = "RackLip", Size = Vector3.new(width, 0.35, 0.12), CFrame = cf * CFrame.new(0, y + 0.1, -depth / 2), Color = C.Hazard, Material = M.Metal })
		table.insert(tops, cf * CFrame.new(0, y + 0.125, 0))
	end
	if heavy then
		for _, x in ipairs({ -width / 2, width / 2 }) do
			b.deco({ Name = "RackBrace", Size = Vector3.new(0.25, height * 1.1, 0.25), CFrame = cf * CFrame.new(x, height / 2, depth / 2) * CFrame.Angles(0, 0, math.rad(if x > 0 then 18 else -18)), Color = color, Material = M.Metal })
		end
	end
	return tops
end

-- Safety railing from a to b (world points on the floor) with hazard-striped posts.
function Props.railing(b, a, z, height)
	height = height or 3.4
	local mid = (a + z) / 2
	local len = (z - a).Magnitude
	local cf = CFrame.lookAt(mid, mid + (z - a).Unit) -- along -Z of this frame
	b.part({ Name = "RailTop", Size = Vector3.new(0.3, 0.3, len), CFrame = cf * CFrame.new(0, height, 0), Color = C.Hazard, Material = M.Metal })
	b.deco({ Name = "RailMid", Size = Vector3.new(0.2, 0.2, len), CFrame = cf * CFrame.new(0, height * 0.5, 0), Color = C.SteelLight, Material = M.Metal })
	local posts = math.max(2, math.floor(len / 5) + 1)
	for i = 0, posts - 1 do
		local t = i / (posts - 1) - 0.5
		b.part({ Name = "RailPost", Size = Vector3.new(0.35, height, 0.35), CFrame = cf * CFrame.new(0, height / 2, t * len), Color = if i % 2 == 0 then C.Hazard else C.Black, Material = M.Metal })
	end
end

-- Hazard stripe band on the floor: alternating yellow / black, from `cf` along its X axis.
function Props.hazardStripes(b, cf, length, width)
	local n = math.max(2, math.floor(length / 1.6))
	for i = 0, n - 1 do
		b.deco({ Name = "Stripe", Size = Vector3.new(length / n, 0.05, width), CFrame = cf * CFrame.new((i + 0.5) * length / n - length / 2, 0.025, 0) * CFrame.Angles(0, math.rad(0), 0), Color = if i % 2 == 0 then C.Hazard else C.Black, Material = M.SmoothPlastic, CastShadow = false })
	end
end

-- Painted floor text (e.g. the depth number at the arrival point). cf: on the floor,
-- text reads facing up; `rotation` turns it.
function Props.floorText(b, cf, w, h, text, color)
	local p = b.deco({ Name = "FloorText", Size = Vector3.new(w, 0.05, h), CFrame = cf * CFrame.new(0, 0.03, 0), Color = C.Black, Transparency = 1, CastShadow = false })
	Props.text(p, Enum.NormalId.Top, text, { Color = color, PPS = 12, LightInfluence = 1, Brightness = 1 })
	return p
end

-- Rectangular ventilation duct along a line at ceiling height, with vent grilles.
function Props.duct(b, from, to, width, color)
	local mid = (from + to) / 2
	local len = (to - from).Magnitude
	local cf = CFrame.lookAt(mid, to)
	b.deco({ Name = "Duct", Size = Vector3.new(width, width * 0.7, len), CFrame = cf, Color = color or C.SteelLight, Material = M.Metal })
	local joints = math.floor(len / 24)
	for i = 1, joints do
		b.deco({ Name = "DuctJoint", Size = Vector3.new(width + 0.3, width * 0.7 + 0.3, 0.4), CFrame = cf * CFrame.new(0, 0, -len / 2 + i * len / (joints + 1)), Color = C.SteelDark, Material = M.Metal })
	end
	for i = 1, math.max(1, joints - 1) do
		b.deco({ Name = "Vent", Size = Vector3.new(width * 0.7, 0.1, 1.6), CFrame = cf * CFrame.new(0, -width * 0.35 - 0.05, -len / 2 + (i + 0.5) * len / (joints + 1)), Color = C.Black, Material = M.Metal })
	end
end

-- Cable tray with a bundle of coloured cables.
function Props.cableTray(b, from, to)
	local mid = (from + to) / 2
	local len = (to - from).Magnitude
	local cf = CFrame.lookAt(mid, to)
	b.deco({ Name = "Tray", Size = Vector3.new(2, 0.15, len), CFrame = cf, Color = C.SteelDark, Material = M.Metal })
	for i, color in ipairs({ C.Black, rgb(40, 80, 160), C.Red, C.Black }) do
		b.deco({ Name = "Cable", Size = Vector3.new(0.18, 0.18, len), CFrame = cf * CFrame.new(-0.6 + (i - 1) * 0.4, 0.17, 0), Color = color, Material = M.Rubber, CastShadow = false })
	end
end

-- Horizontal pipe run (cylinder) with brackets.
function Props.pipe(b, from, to, d, color)
	local mid = (from + to) / 2
	local len = (to - from).Magnitude
	local cf = CFrame.lookAt(mid, to) * ALONG_Z
	b.deco({ Name = "Pipe", Size = Vector3.new(len, d, d), CFrame = cf, Color = color or C.SteelLight, Material = M.Metal, Shape = Enum.PartType.Cylinder })
	local n = math.floor(len / 28)
	for i = 1, n do
		b.deco({ Name = "PipeClamp", Size = Vector3.new(0.4, d + 0.3, d + 0.3), CFrame = cf * CFrame.new(-len / 2 + i * len / (n + 1), 0, 0), Color = C.SteelDark, Material = M.Metal, Shape = Enum.PartType.Cylinder })
	end
end

-- Rotating-beacon style warning light (static: a neon dome on a base + a small light).
function Props.warningLight(b, cf, color)
	b.deco({ Name = "BeaconBase", Size = Vector3.new(0.8, 0.3, 0.8), CFrame = cf, Color = C.SteelDark, Material = M.Metal })
	local dome = b.deco({ Name = "Beacon", Size = Vector3.new(0.65, 0.65, 0.65), CFrame = cf * CFrame.new(0, 0.4, 0), Color = color or C.Amber, Material = M.Neon, Shape = Enum.PartType.Ball })
	local light = Instance.new("PointLight")
	light.Color = color or C.Amber
	light.Range = 10
	light.Brightness = 1
	light.Shadows = false
	light.Parent = dome
	return dome
end

-- Pillar with a reinforced base and cap.
function Props.pillar(b, cf, height, w, color, material)
	b.part({ Name = "Pillar", Size = Vector3.new(w, height, w), CFrame = cf * CFrame.new(0, height / 2, 0), Color = color, Material = material or M.Concrete })
	b.deco({ Name = "PillarBase", Size = Vector3.new(w + 0.8, 1.2, w + 0.8), CFrame = cf * CFrame.new(0, 0.6, 0), Color = C.SteelDark, Material = M.Metal })
	b.deco({ Name = "PillarGuard", Size = Vector3.new(w + 0.9, 0.7, w + 0.9), CFrame = cf * CFrame.new(0, 2.2, 0), Color = C.Hazard, Material = M.Metal })
	b.deco({ Name = "PillarCap", Size = Vector3.new(w + 0.8, 1, w + 0.8), CFrame = cf * CFrame.new(0, height - 0.5, 0), Color = C.SteelDark, Material = M.Metal })
end

-- Table / counter; returns the CFrame of its top surface centre.
function Props.table(b, cf, w, d, h, topColor, legColor)
	b.part({ Name = "TableTop", Size = Vector3.new(w, 0.3, d), CFrame = cf * CFrame.new(0, h - 0.15, 0), Color = topColor, Material = M.Metal })
	for _, x in ipairs({ -w / 2 + 0.3, w / 2 - 0.3 }) do
		for _, z in ipairs({ -d / 2 + 0.3, d / 2 - 0.3 }) do
			b.part({ Name = "TableLeg", Size = Vector3.new(0.3, h - 0.3, 0.3), CFrame = cf * CFrame.new(x, (h - 0.3) / 2, z), Color = legColor or C.SteelDark, Material = M.Metal })
		end
	end
	return cf * CFrame.new(0, h, 0)
end

-- Glass display case on a plinth; returns the CFrame of the inner floor (for decor).
function Props.displayCase(b, cf, w, d, h, plinthColor, glassH)
	b.part({ Name = "CasePlinth", Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, h / 2, 0), Color = plinthColor, Material = M.Metal })
	b.deco({ Name = "CaseTrim", Size = Vector3.new(w + 0.2, 0.15, d + 0.2), CFrame = cf * CFrame.new(0, h, 0), Color = C.SteelLight, Material = M.Metal })
	glassH = glassH or 2.4
	b.part({ Name = "CaseGlass", Size = Vector3.new(w - 0.1, glassH, d - 0.1), CFrame = cf * CFrame.new(0, h + glassH / 2, 0), Color = C.Glass, Material = M.Glass, Transparency = 0.7, CastShadow = false })
	b.deco({ Name = "CaseLid", Size = Vector3.new(w, 0.12, d), CFrame = cf * CFrame.new(0, h + glassH + 0.06, 0), Color = C.SteelLight, Material = M.Metal })
	return cf * CFrame.new(0, h + 0.08, 0)
end

-- Wooden pallet; returns the top CFrame.
function Props.pallet(b, cf)
	for _, z in ipairs({ -1.2, 0, 1.2 }) do
		b.part({ Name = "PalletBeam", Size = Vector3.new(3.4, 0.4, 0.5), CFrame = cf * CFrame.new(0, 0.2, z), Color = C.Wood, Material = M.Wood })
	end
	for i = -3, 3 do
		b.deco({ Name = "PalletSlat", Size = Vector3.new(0.4, 0.12, 3.0), CFrame = cf * CFrame.new(i * 0.5, 0.46, 0), Color = rgb(150, 110, 70), Material = M.WoodPlanks })
	end
	return cf * CFrame.new(0, 0.52, 0)
end

return Props
