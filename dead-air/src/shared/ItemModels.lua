--[[
	ItemModels - procedural 3D models for every carryable item.

	build(kind, cframe) returns an invisible root Part (the pickup's hitbox, sized like
	ItemConfig[kind].Size with Y up) with detail parts welded to it. Game code moves and
	tweens the root only; the details follow through their welds. The model is built
	already in place at `cframe` so it is correct before it is parented anywhere.
	Used by the server (pickups, thrown items) and the client (inventory icons).
]]

local ItemConfig = require(script.Parent.Config.ItemConfig)

local ItemModels = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders lie along X; this stands them up
local FACING = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along Z (faces the front)

local function tint(list)
	return rgb(list[1], list[2], list[3])
end

-- Context passed to each builder: adds a detail part at an offset from the root.
local function newKit(root, origin)
	local kit = {}
	function kit.part(name, size, offset, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or M.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = size.Magnitude > 0.6
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = origin * offset
		p.Parent = root
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	function kit.box(name, size, offset, color, material)
		return kit.part(name, size, offset, color, material)
	end
	-- Upright cylinder: `height` along Y, `diameter` across.
	function kit.cyl(name, height, diameter, offset, color, material)
		return kit.part(name, Vector3.new(height, diameter, diameter), offset * UPRIGHT, color, material, Enum.PartType.Cylinder)
	end
	-- Cylinder whose axis points along Z (towards the item's front).
	function kit.disc(name, depth, diameter, offset, color, material)
		return kit.part(name, Vector3.new(depth, diameter, diameter), offset * FACING, color, material, Enum.PartType.Cylinder)
	end
	function kit.ball(name, diameter, offset, color, material)
		return kit.part(name, Vector3.new(diameter, diameter, diameter), offset, color, material, Enum.PartType.Ball)
	end
	return kit
end

local at = CFrame.new
local builders = {}

-- Security keycard: blue card with photo, chip, magnetic stripe and a clip slot.
function builders.Keycard(k, def)
	local base = tint(def.Color)
	k.box("Card", Vector3.new(0.9, 0.05, 1.3), at(0, -0.01, 0), base)
	k.box("Header", Vector3.new(0.9, 0.012, 0.28), at(0, 0.02, -0.5), rgb(235, 235, 228))
	k.box("Photo", Vector3.new(0.28, 0.012, 0.34), at(-0.24, 0.02, -0.08), rgb(200, 190, 175))
	k.box("NameLine1", Vector3.new(0.34, 0.012, 0.05), at(0.17, 0.02, -0.18), rgb(225, 228, 235))
	k.box("NameLine2", Vector3.new(0.26, 0.012, 0.05), at(0.13, 0.02, -0.07), rgb(225, 228, 235))
	k.box("Chip", Vector3.new(0.18, 0.014, 0.14), at(0.22, 0.02, 0.12), rgb(212, 175, 70), M.Metal)
	k.box("Stripe", Vector3.new(0.9, 0.012, 0.16), at(0, 0.02, 0.42), rgb(25, 25, 28))
	k.box("ClipSlot", Vector3.new(0.3, 0.014, 0.05), at(0, 0.02, -0.6), rgb(30, 40, 60))
end

-- Cartridge fuse: ceramic body, copper end caps and blade contacts, warning band.
function builders.Fuse(k, def)
	local copper = tint(def.Color)
	k.cyl("Body", 0.9, 0.38, at(0, 0, 0), rgb(232, 226, 210), M.SmoothPlastic)
	k.cyl("Band", 0.22, 0.39, at(0, 0.1, 0), rgb(220, 120, 40))
	k.cyl("CapTop", 0.18, 0.46, at(0, 0.52, 0), copper, M.Metal)
	k.cyl("CapBottom", 0.18, 0.46, at(0, -0.52, 0), copper, M.Metal)
	k.box("BladeTop", Vector3.new(0.26, 0.1, 0.05), at(0, 0.66, 0), copper, M.Metal)
	k.box("BladeBottom", Vector3.new(0.26, 0.1, 0.05), at(0, -0.66, 0), copper, M.Metal)
	k.box("Rating", Vector3.new(0.12, 0.2, 0.01), at(0, -0.15, -0.19), rgb(40, 40, 40))
end

-- Jerry can: red body with a stamped X, triple handle and a spout with a yellow cap.
function builders.FuelCan(k, def)
	local red = tint(def.Color)
	local dark = rgb(110, 26, 22)
	k.box("Body", Vector3.new(1.3, 1.45, 0.76), at(0, -0.12, 0), red, M.Metal)
	k.box("Seam", Vector3.new(1.34, 1.49, 0.06), at(0, -0.12, 0), dark, M.Metal)
	for side = -1, 1, 2 do
		k.box("CrossA", Vector3.new(1.4, 0.07, 0.03), at(0, -0.12, side * 0.39) * CFrame.Angles(0, 0, math.rad(42)), dark, M.Metal)
		k.box("CrossB", Vector3.new(1.4, 0.07, 0.03), at(0, -0.12, side * 0.39) * CFrame.Angles(0, 0, math.rad(-42)), dark, M.Metal)
	end
	for i = -1, 1 do
		k.box("Handle" .. i, Vector3.new(0.08, 0.26, 0.5), at(-0.12 + i * 0.2, 0.7, 0), dark, M.Metal)
	end
	k.box("Grip", Vector3.new(0.5, 0.08, 0.5), at(-0.12, 0.84, 0), dark, M.Metal)
	k.cyl("Spout", 0.28, 0.24, at(0.48, 0.68, 0) * CFrame.Angles(0, 0, math.rad(-30)), rgb(90, 90, 92), M.Metal)
	k.cyl("Cap", 0.12, 0.28, at(0.56, 0.82, 0) * CFrame.Angles(0, 0, math.rad(-30)), rgb(230, 190, 40))
end

-- Glass bottle: body, rounded shoulder, neck, lip and a peeling paper label.
function builders.Bottle(k, def)
	local glass = tint(def.Color)
	local t = def.Transparency or 0.25
	local parts = {
		k.cyl("Body", 0.68, 0.44, at(0, -0.24, 0), glass, M.Glass),
		k.ball("Shoulder", 0.44, at(0, 0.08, 0), glass, M.Glass),
		k.cyl("Neck", 0.36, 0.17, at(0, 0.4, 0), glass, M.Glass),
		k.cyl("Lip", 0.06, 0.2, at(0, 0.58, 0), glass, M.Glass),
	}
	for _, p in ipairs(parts) do
		p.Transparency = t
	end
	k.cyl("Label", 0.3, 0.45, at(0, -0.25, 0), rgb(214, 196, 150), M.SmoothPlastic)
	k.box("LabelStripe", Vector3.new(0.2, 0.05, 0.01), at(0, -0.2, -0.226), rgb(140, 40, 34))
end

-- Tin can: steel body, rolled rims, faded label and a pull-tab lid.
function builders.Can(k, def)
	local steel = tint(def.Color)
	k.cyl("Body", 0.72, 0.48, at(0, 0, 0), steel, M.Metal)
	k.cyl("RimTop", 0.05, 0.5, at(0, 0.38, 0), rgb(185, 186, 180), M.Metal)
	k.cyl("RimBottom", 0.05, 0.5, at(0, -0.38, 0), rgb(185, 186, 180), M.Metal)
	k.cyl("Label", 0.46, 0.49, at(0, 0, 0), rgb(168, 70, 52))
	k.cyl("LabelBand", 0.08, 0.495, at(0, 0.08, 0), rgb(228, 210, 160))
	k.box("Tab", Vector3.new(0.12, 0.02, 0.07), at(0.08, 0.41, 0), rgb(200, 200, 196), M.Metal)
end

-- Twin-bell alarm clock: round red case, white face with hands, bells, hammer and feet.
function builders.AlarmClock(k, def)
	local red = tint(def.Color)
	local metal = rgb(200, 196, 186)
	k.disc("Case", 0.36, 0.62, at(0, -0.05, 0), red, M.Metal)
	k.disc("Face", 0.02, 0.5, at(0, -0.05, -0.18), rgb(240, 236, 220))
	k.disc("Bezel", 0.03, 0.56, at(0, -0.05, -0.17), metal, M.Metal)
	k.box("HourHand", Vector3.new(0.03, 0.14, 0.01), at(0.03, -0.0, -0.195) * CFrame.Angles(0, 0, math.rad(-35)), rgb(20, 20, 20))
	k.box("MinuteHand", Vector3.new(0.025, 0.2, 0.01), at(-0.04, 0.02, -0.196) * CFrame.Angles(0, 0, math.rad(25)), rgb(20, 20, 20))
	k.box("Pin", Vector3.new(0.04, 0.04, 0.01), at(0, -0.05, -0.198), rgb(180, 30, 30))
	k.ball("BellLeft", 0.24, at(-0.2, 0.3, 0), metal, M.Metal)
	k.ball("BellRight", 0.24, at(0.2, 0.3, 0), metal, M.Metal)
	k.box("Hammer", Vector3.new(0.03, 0.16, 0.03), at(0, 0.3, 0), metal, M.Metal)
	k.box("Handle", Vector3.new(0.3, 0.03, 0.04), at(0, 0.38, 0.05), metal, M.Metal)
	k.box("FootLeft", Vector3.new(0.05, 0.12, 0.05), at(-0.18, -0.36, 0) * CFrame.Angles(0, 0, math.rad(-20)), metal, M.Metal)
	k.box("FootRight", Vector3.new(0.05, 0.12, 0.05), at(0.18, -0.36, 0) * CFrame.Angles(0, 0, math.rad(20)), metal, M.Metal)
end

-- Flight-data recorder: ribbed dark casing, reflective stripes, carry handle, red LED.
function builders.BlackBox(k, def)
	local shell = tint(def.Color)
	local orange = rgb(235, 110, 30)
	k.box("Casing", Vector3.new(1.5, 0.8, 1.1), at(0, -0.08, 0), shell, M.Metal)
	k.box("Base", Vector3.new(1.6, 0.1, 1.2), at(0, -0.45, 0), rgb(55, 55, 58), M.Metal)
	for i = -2, 2 do
		k.box("Rib" .. i, Vector3.new(0.05, 0.7, 1.14), at(i * 0.28, -0.08, 0), rgb(48, 48, 52), M.Metal)
	end
	k.box("StripeFront", Vector3.new(1.52, 0.12, 0.02), at(0, 0.1, -0.56), orange, M.Fabric)
	k.box("StripeBack", Vector3.new(1.52, 0.12, 0.02), at(0, 0.1, 0.56), orange, M.Fabric)
	k.box("Plate", Vector3.new(0.5, 0.22, 0.02), at(-0.35, -0.18, -0.565), rgb(200, 200, 196), M.Metal)
	k.box("HandleLeft", Vector3.new(0.06, 0.18, 0.06), at(-0.3, 0.41, 0), rgb(80, 80, 84), M.Metal)
	k.box("HandleRight", Vector3.new(0.06, 0.18, 0.06), at(0.3, 0.41, 0), rgb(80, 80, 84), M.Metal)
	k.box("HandleBar", Vector3.new(0.66, 0.06, 0.08), at(0, 0.48, 0), rgb(80, 80, 84), M.Metal)
	k.ball("Led", 0.09, at(0.5, 0.0, -0.56), rgb(255, 40, 40), M.Neon)
end

-- D-cell battery: black body, green label, brass top with a positive nub.
function builders.Battery(k, def)
	k.cyl("Body", 0.7, 0.38, at(0, -0.08, 0), tint(def.Color), M.SmoothPlastic)
	k.cyl("Label", 0.42, 0.385, at(0, -0.1, 0), rgb(70, 170, 80))
	k.cyl("Top", 0.14, 0.38, at(0, 0.34, 0), rgb(200, 160, 60), M.Metal)
	k.cyl("Nub", 0.06, 0.14, at(0, 0.43, 0), rgb(210, 200, 180), M.Metal)
	k.cyl("Bottom", 0.02, 0.36, at(0, -0.44, 0), rgb(160, 160, 160), M.Metal)
	k.box("Plus", Vector3.new(0.08, 0.08, 0.01), at(0, 0.0, -0.195), rgb(240, 240, 240))
end

function ItemModels.build(kind, cframe)
	local def = ItemConfig[kind]
	cframe = cframe or CFrame.new()
	local root = Instance.new("Part")
	root.Name = kind
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.Transparency = 1
	root.Size = Vector3.new(def.Size[1], def.Size[2], def.Size[3])
	root.CFrame = cframe
	local builder = builders[kind]
	if builder then
		builder(newKit(root, cframe), def)
	else
		root.Transparency = def.Transparency or 0
		root.Color = tint(def.Color)
	end
	if def.Glow then
		local light = Instance.new("PointLight")
		light.Color = tint(def.Glow)
		light.Range = 7
		light.Brightness = 0.7
		light.Shadows = false
		light.Parent = root
	end
	return root
end

return ItemModels
