--[[
	WeaponModels - parry weapons built from parts (sword, bat, katana, hammer, scythe).

	build(item) returns a Model whose PrimaryPart "Grip" sits at the origin with the weapon
	pointing along +Y. Every part is anchored, non-colliding and non-queryable: these are
	visual-only swing effects created on the client. Replace with Blender meshes later
	(see POLISH.md) by keeping the same names and the +Y orientation.
]]

local WeaponModels = {}

local function rgb(c, fallback)
	c = c or fallback
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(model, name, size, cframe, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function wedge(model, name, size, cframe, color, material)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cframe
	w.Color = color
	w.Material = material or Enum.Material.SmoothPlastic
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = false
	w.Parent = model
	return w
end

local builders = {}

function builders.Sword(model, main, accent, glow)
	local bladeMat = if glow then Enum.Material.Neon else Enum.Material.Metal
	part(model, "Pommel", Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, -0.6, 0), accent, Enum.Material.Metal, Enum.PartType.Ball)
	part(model, "Handle", Vector3.new(0.3, 1.1, 0.3), CFrame.new(0, 0, 0), accent, Enum.Material.Fabric)
	part(model, "Guard", Vector3.new(1.6, 0.25, 0.45), CFrame.new(0, 0.6, 0), accent, Enum.Material.Metal)
	part(model, "Blade", Vector3.new(0.5, 3.6, 0.12), CFrame.new(0, 2.5, 0), main, bladeMat)
	part(model, "Fuller", Vector3.new(0.12, 3, 0.14), CFrame.new(0, 2.3, 0), main:Lerp(Color3.new(1, 1, 1), 0.4), Enum.Material.Neon)
	-- Pointed tip: two wedges with their tall edge on the blade's centre line.
	wedge(model, "TipR", Vector3.new(0.12, 0.6, 0.25), CFrame.new(0, 4.6, 0.125), main, bladeMat)
	wedge(model, "TipL", Vector3.new(0.12, 0.6, 0.25), CFrame.new(0, 4.6, -0.125) * CFrame.Angles(0, math.pi, 0), main, bladeMat)
end

function builders.Katana(model, main, accent, glow)
	local bladeMat = if glow then Enum.Material.Neon else Enum.Material.Metal
	part(model, "Handle", Vector3.new(0.28, 1.4, 0.28), CFrame.new(0, -0.1, 0), accent, Enum.Material.Fabric)
	part(model, "Wrap", Vector3.new(0.3, 1.2, 0.3), CFrame.new(0, -0.1, 0), main:Lerp(accent, 0.7), Enum.Material.Fabric)
	part(model, "Tsuba", Vector3.new(0.8, 0.12, 0.8), CFrame.new(0, 0.66, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 170, 80), Enum.Material.Metal, Enum.PartType.Cylinder)
	-- Slightly curved blade made of three segments.
	for i = 0, 2 do
		local y = 1.4 + i * 1.3
		part(model, "Blade" .. i, Vector3.new(0.32, 1.35, 0.1), CFrame.new(0, y, i * i * 0.06) * CFrame.Angles(math.rad(-i * 3), 0, 0), main, bladeMat)
	end
	wedge(model, "Tip", Vector3.new(0.1, 0.5, 0.32), CFrame.new(0, 5.25, 0.3) * CFrame.Angles(math.rad(-8), 0, 0), main, bladeMat)
end

function builders.Bat(model, main, accent, glow)
	local mat = if glow then Enum.Material.Neon else Enum.Material.Wood
	part(model, "Knob", Vector3.new(0.2, 0.55, 0.55), CFrame.new(0, -0.65, 0) * CFrame.Angles(0, 0, math.rad(90)), accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	part(model, "Grip", Vector3.new(1.4, 0.32, 0.32), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), accent, Enum.Material.Fabric, Enum.PartType.Cylinder)
	part(model, "Taper", Vector3.new(1.4, 0.45, 0.45), CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(90)), main, mat, Enum.PartType.Cylinder)
	part(model, "Barrel", Vector3.new(2.2, 0.7, 0.7), CFrame.new(0, 3.0, 0) * CFrame.Angles(0, 0, math.rad(90)), main, mat, Enum.PartType.Cylinder)
	part(model, "Cap", Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 4.1, 0), main, mat, Enum.PartType.Ball)
	part(model, "Band", Vector3.new(0.12, 0.74, 0.74), CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, math.rad(90)), accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
end

function builders.Hammer(model, main, accent, glow)
	local headMat = if glow then Enum.Material.Neon else Enum.Material.Metal
	part(model, "Handle", Vector3.new(3.2, 0.35, 0.35), CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)), accent, Enum.Material.Wood, Enum.PartType.Cylinder)
	part(model, "Head", Vector3.new(1.0, 1.1, 2.2), CFrame.new(0, 3.2, 0), main, headMat)
	part(model, "FaceA", Vector3.new(1.2, 1.3, 0.25), CFrame.new(0, 3.2, 1.15), accent, Enum.Material.Metal)
	part(model, "FaceB", Vector3.new(1.2, 1.3, 0.25), CFrame.new(0, 3.2, -1.15), accent, Enum.Material.Metal)
	part(model, "Bolt", Vector3.new(0.3, 1.3, 0.3), CFrame.new(0.55, 3.2, 0), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
end

function builders.Scythe(model, main, accent, glow)
	local bladeMat = if glow then Enum.Material.Neon else Enum.Material.Metal
	part(model, "Shaft", Vector3.new(4.6, 0.28, 0.28), CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)), accent, Enum.Material.Wood, Enum.PartType.Cylinder)
	part(model, "Collar", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 3.9, 0), Color3.fromRGB(90, 90, 100), Enum.Material.Metal)
	-- Curved blade from four segments bending backwards.
	local cf = CFrame.new(0, 4.0, 0)
	for i = 1, 4 do
		local seg = cf * CFrame.Angles(math.rad(-18 * i), 0, 0) * CFrame.new(0, 0, -0.6)
		part(model, "Blade" .. i, Vector3.new(0.12, 0.6 - i * 0.08, 1.25), seg, main, bladeMat)
		cf = seg * CFrame.new(0, 0, -0.6)
	end
end

function WeaponModels.styles()
	local list = {}
	for name in pairs(builders) do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

function WeaponModels.build(item)
	local model = Instance.new("Model")
	model.Name = "Weapon_" .. (item.Id or "Unknown")
	local builder = builders[item.Style] or builders.Sword
	local main = rgb(item.Color, { 220, 220, 230 })
	local accent = rgb(item.Accent, { 60, 50, 40 })
	builder(model, main, accent, item.Neon == true)
	local grip = part(model, "GripRoot", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), Color3.new(0, 0, 0))
	grip.Transparency = 1
	model.PrimaryPart = grip
	if item.Neon then
		local light = Instance.new("PointLight")
		light.Color = main
		light.Range = 10
		light.Brightness = 2
		light.Parent = grip
	end
	return model
end

return WeaponModels
