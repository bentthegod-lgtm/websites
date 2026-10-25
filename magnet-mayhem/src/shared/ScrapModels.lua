--[[
	ScrapModels - procedural models for every ScrapConfig entry, built from parts.

	ScrapModels.build(id, cframe, scale) returns a Model whose PrimaryPart "Root" is an
	invisible box at `cframe`; every part is anchored, non-colliding and not queryable
	(scrap never blocks players or raycasts). The same builder makes world scrap (scale 1)
	and the smaller pieces in a player's pile (scale < 1).

	To swap in Blender meshes later: replace a builder with one that clones a MeshPart
	from ReplicatedStorage and keeps the same Root/pivot convention.
]]

local ScrapConfig = require(script.Parent.Config.ScrapConfig)

local ScrapModels = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local at = CFrame.new
local ang = CFrame.Angles
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders lie along X; stand them up
local FACING = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along Z

local RUST = rgb(150, 82, 46)
local RUST_DARK = rgb(104, 56, 34)
local STEEL = rgb(150, 154, 160)
local STEEL_DARK = rgb(88, 92, 98)
local CHROME = rgb(210, 214, 220)
local BLACK = rgb(36, 36, 40)
local YELLOW = rgb(236, 186, 46)
local RED = rgb(186, 52, 44)

local function newKit(model, origin, scale)
	local kit = { count = 0 }
	local function place(offset)
		local p = offset.Position * scale
		return origin * (CFrame.new(p) * (offset - offset.Position))
	end
	function kit.part(name, size, offset, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * scale
		p.Color = color
		p.Material = material or M.Metal
		if shape then
			p.Shape = shape
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = size.Magnitude * scale > 1.2
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = place(offset)
		p.Parent = model
		kit.count += 1
		return p
	end
	function kit.box(name, size, offset, color, material)
		return kit.part(name, size, offset, color, material)
	end
	function kit.cyl(name, height, diameter, offset, color, material)
		return kit.part(name, Vector3.new(height, diameter, diameter), offset * UPRIGHT, color, material, Enum.PartType.Cylinder)
	end
	function kit.disc(name, depth, diameter, offset, color, material)
		return kit.part(name, Vector3.new(depth, diameter, diameter), offset * FACING, color, material, Enum.PartType.Cylinder)
	end
	function kit.rod(name, length, diameter, offset, color, material) -- along X
		return kit.part(name, Vector3.new(length, diameter, diameter), offset, color, material, Enum.PartType.Cylinder)
	end
	function kit.ball(name, diameter, offset, color, material)
		return kit.part(name, Vector3.new(diameter, diameter, diameter), offset, color, material, Enum.PartType.Ball)
	end
	function kit.wedge(name, size, offset, color, material)
		local p = Instance.new("WedgePart")
		p.Name = name
		p.Size = size * scale
		p.Color = color
		p.Material = material or M.Metal
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = place(offset)
		p.Parent = model
		kit.count += 1
		return p
	end
	function kit.neon(name, size, offset, color, shape)
		local p = kit.part(name, size, offset, color, M.Neon, shape)
		p.CastShadow = false
		return p
	end
	return kit
end

local B = {}

-- Rustyard -----------------------------------------------------------------------------

function B.SodaCan(k)
	k.cyl("Body", 0.55, 0.42, at(0, 0, 0) * ang(0.3, 0, 0.5), rgb(196, 44, 52))
	k.cyl("Crush", 0.18, 0.5, at(0.04, 0.12, 0.06) * ang(0.3, 0, 0.5), rgb(178, 36, 44))
	k.cyl("Top", 0.06, 0.4, at(0.13, 0.25, 0.08) * ang(0.3, 0, 0.5), CHROME)
	k.box("Stripe", Vector3.new(0.1, 0.3, 0.43), at(-0.02, -0.02, 0) * ang(0.3, 0, 0.5), rgb(240, 240, 240), M.SmoothPlastic)
end

function B.Bolt(k)
	k.cyl("Shaft", 0.8, 0.2, at(0, 0, 0) * ang(0, 0, math.rad(70)), STEEL)
	k.cyl("Head", 0.16, 0.42, at(-0.38, 0.14, 0) * ang(0, 0, math.rad(70)), STEEL_DARK)
	for i = 0, 3 do
		k.cyl("Thread" .. i, 0.04, 0.24, at(0.05 + i * 0.13, -0.02 - i * 0.05, 0) * ang(0, 0, math.rad(70)), CHROME)
	end
end

function B.Washer(k)
	k.cyl("Ring", 0.08, 0.7, at(0, 0, 0), STEEL)
	k.cyl("Hole", 0.1, 0.28, at(0, 0, 0), BLACK)
	k.cyl("Rim", 0.09, 0.74, at(0, -0.01, 0), STEEL_DARK)
end

function B.Gear(k)
	k.cyl("Hub", 0.28, 1.0, at(0, 0, 0), RUST)
	k.cyl("Axle", 0.32, 0.3, at(0, 0, 0), BLACK)
	for i = 0, 7 do
		local a = i * math.pi / 4
		k.box("Tooth" .. i, Vector3.new(0.3, 0.26, 0.24), at(math.cos(a) * 0.55, 0, math.sin(a) * 0.55) * ang(0, -a, 0), RUST_DARK)
	end
end

function B.RustyPipe(k)
	k.rod("Pipe", 2.8, 0.55, at(0, 0, 0) * ang(0, 0.3, 0), RUST)
	k.rod("Flange", 0.14, 0.85, at(-1.3, 0, 0.4) * ang(0, 0.3, 0), RUST_DARK)
	k.rod("Elbow", 0.6, 0.6, at(1.38, 0.22, -0.43) * ang(0, 0.3, math.rad(40)), RUST_DARK)
	k.rod("Hollow", 0.16, 0.36, at(-1.42, 0, 0.44) * ang(0, 0.3, 0), BLACK)
end

function B.MetalSign(k)
	k.box("Plate", Vector3.new(2.3, 1.5, 0.08), at(0, 0.2, 0) * ang(-0.4, 0.2, 0.15), YELLOW)
	k.box("Border", Vector3.new(2.4, 0.1, 0.09), at(0, 0.92, -0.28) * ang(-0.4, 0.2, 0.15), BLACK)
	k.box("Symbol", Vector3.new(0.9, 0.18, 0.09), at(0, 0.2, -0.02) * ang(-0.4, 0.2, 0.15 + 0.8), BLACK)
	k.box("Symbol2", Vector3.new(0.9, 0.18, 0.09), at(0, 0.2, -0.02) * ang(-0.4, 0.2, 0.15 - 0.8), BLACK)
	k.rod("Post", 1.2, 0.14, at(0.3, -0.55, 0.3) * ang(0, 0.2, 1.2), STEEL_DARK)
	k.wedge("Bent", Vector3.new(0.08, 0.4, 0.6), at(-1.05, -0.4, 0.2) * ang(-0.4, 0.2, 0.15), RUST)
end

function B.Toolbox(k)
	k.box("Body", Vector3.new(1.9, 0.9, 0.85), at(0, 0, 0), RED)
	k.box("Lid", Vector3.new(1.95, 0.25, 0.9), at(0, 0.55, 0), rgb(166, 40, 36))
	k.box("HandleL", Vector3.new(0.1, 0.3, 0.1), at(-0.45, 0.82, 0), BLACK)
	k.box("HandleR", Vector3.new(0.1, 0.3, 0.1), at(0.45, 0.82, 0), BLACK)
	k.box("Grip", Vector3.new(1.0, 0.1, 0.12), at(0, 0.98, 0), BLACK)
	k.box("Latch", Vector3.new(0.25, 0.2, 0.05), at(0, 0.32, -0.45), CHROME)
	k.box("Wrench", Vector3.new(1.1, 0.1, 0.18), at(0.2, 0.7, 0.3) * ang(0, 0.4, 0), STEEL)
end

function B.IndustrialFan(k)
	k.disc("Housing", 0.5, 2.9, at(0, 0.2, 0), STEEL_DARK)
	k.disc("Guard", 0.08, 2.7, at(0, 0.2, -0.3), STEEL, M.DiamondPlate)
	k.disc("Hub", 0.6, 0.6, at(0, 0.2, -0.05), BLACK)
	for i = 0, 3 do
		k.box("Blade" .. i, Vector3.new(1.1, 0.4, 0.06), at(0, 0.2, -0.12) * ang(0, 0, i * math.pi / 2) * at(0.65, 0, 0) * ang(0.35, 0, 0), RUST)
	end
	k.box("Stand", Vector3.new(0.3, 0.9, 0.3), at(0, -1.25, 0.1), STEEL_DARK)
	k.box("Foot", Vector3.new(1.4, 0.15, 0.6), at(0, -1.7, 0.1), BLACK)
end

function B.HeavyChain(k)
	for i = 0, 6 do
		local x = -1.35 + i * 0.45
		local y = math.sin(i * 0.9) * 0.15
		local link = if i % 2 == 0 then ang(0, 0, 0) else ang(math.rad(90), 0, 0)
		k.box("LinkA" .. i, Vector3.new(0.55, 0.12, 0.12), at(x, y + 0.15, 0) * link, STEEL_DARK)
		k.box("LinkB" .. i, Vector3.new(0.55, 0.12, 0.12), at(x, y - 0.15, 0) * link, STEEL_DARK)
	end
	k.box("Hook", Vector3.new(0.18, 0.6, 0.18), at(1.6, -0.1, 0) * ang(0, 0, 0.5), RUST)
end

function B.EngineComponent(k)
	k.box("Block", Vector3.new(1.8, 1.1, 1.2), at(0, 0, 0), STEEL_DARK)
	k.box("Head", Vector3.new(1.9, 0.35, 1.0), at(0, 0.72, 0), RUST)
	for i = 0, 2 do
		k.cyl("Plug" .. i, 0.4, 0.18, at(-0.55 + i * 0.55, 1.05, 0), BLACK)
	end
	k.disc("Pulley", 0.2, 0.9, at(0.95, -0.1, -0.2) * ang(0, math.rad(90), 0), BLACK)
	k.rod("Hose", 1.4, 0.16, at(0, 0.3, -0.65) * ang(0, 0, 0.3), rgb(40, 40, 44), M.Rubber)
end

function B.MotorcycleEngine(k)
	k.box("Crank", Vector3.new(1.8, 1.2, 1.3), at(0, -0.3, 0), rgb(60, 62, 70))
	k.box("CylL", Vector3.new(0.75, 1.4, 0.85), at(-0.55, 0.75, 0) * ang(0, 0, 0.35), CHROME)
	k.box("CylR", Vector3.new(0.75, 1.4, 0.85), at(0.55, 0.75, 0) * ang(0, 0, -0.35), CHROME)
	for i = 0, 3 do
		k.box("FinL" .. i, Vector3.new(0.95, 0.06, 1.0), at(-0.62 - i * 0.07, 0.4 + i * 0.28, 0) * ang(0, 0, 0.35), STEEL)
		k.box("FinR" .. i, Vector3.new(0.95, 0.06, 1.0), at(0.62 + i * 0.07, 0.4 + i * 0.28, 0) * ang(0, 0, -0.35), STEEL)
	end
	k.disc("Cover", 0.15, 1.0, at(0, -0.3, -0.72), CHROME)
	k.rod("Exhaust", 2.2, 0.28, at(0.2, -0.85, 0.5) * ang(0, 0.15, 0), CHROME)
end

function B.IndustrialMotor(k)
	k.rod("Body", 2.6, 2.0, at(0, 0, 0), rgb(46, 92, 150))
	for i = 0, 5 do
		k.rod("Rib" .. i, 0.12, 2.15, at(-1.0 + i * 0.4, 0, 0), rgb(36, 72, 120))
	end
	k.rod("Shaft", 0.9, 0.3, at(1.7, 0, 0), CHROME)
	k.rod("EndCap", 0.3, 1.7, at(-1.4, 0, 0), STEEL_DARK)
	k.box("Base", Vector3.new(2.6, 0.3, 1.8), at(0, -1.1, 0), STEEL_DARK)
	k.box("Junction", Vector3.new(0.7, 0.5, 0.6), at(0, 1.15, 0), rgb(36, 72, 120))
	k.box("Label", Vector3.new(0.6, 0.35, 0.02), at(0.2, 0.3, -1.01), YELLOW, M.SmoothPlastic)
end

function B.SteelSafe(k)
	k.box("Body", Vector3.new(2.8, 3.0, 2.6), at(0, 0, 0), rgb(56, 64, 58))
	k.box("Door", Vector3.new(2.4, 2.6, 0.12), at(0, 0, -1.33), rgb(66, 76, 68))
	k.disc("Dial", 0.15, 0.8, at(0, 0.4, -1.42), CHROME)
	k.disc("DialMark", 0.17, 0.2, at(0, 0.4, -1.43), BLACK)
	k.box("Handle", Vector3.new(0.9, 0.14, 0.14), at(0, -0.4, -1.47), CHROME)
	for _, x in ipairs({ -1.2, 1.2 }) do
		k.box("Hinge" .. x, Vector3.new(0.14, 0.5, 0.2), at(x, 0.8, -1.35), BLACK)
		k.box("HingeB" .. x, Vector3.new(0.14, 0.5, 0.2), at(x, -0.8, -1.35), BLACK)
	end
	k.box("Feet", Vector3.new(2.6, 0.2, 2.4), at(0, -1.6, 0), BLACK)
	k.box("Gold", Vector3.new(0.5, 0.12, 0.02), at(0, 1.1, -1.4), YELLOW, M.SmoothPlastic)
end

function B.PowerCore(k)
	k.cyl("Shell", 2.2, 1.3, at(0, 0, 0), rgb(54, 58, 70))
	k.neon("Core", Vector3.new(1.6, 0.95, 0.95), at(0, 0, 0) * UPRIGHT, rgb(80, 230, 255), Enum.PartType.Cylinder)
	for _, y in ipairs({ -0.95, 0.95 }) do
		k.cyl("Cap" .. y, 0.35, 1.55, at(0, y, 0), STEEL_DARK)
	end
	for i = 0, 3 do
		local a = i * math.pi / 2
		k.box("Bar" .. i, Vector3.new(0.14, 2.1, 0.14), at(math.cos(a) * 0.7, 0, math.sin(a) * 0.7), CHROME)
	end
	k.box("Hazard", Vector3.new(0.6, 0.25, 0.02), at(0, 0.6, -0.68), YELLOW, M.SmoothPlastic)
end

function B.MagneticReactor(k)
	k.box("Base", Vector3.new(4, 0.5, 4), at(0, -1.7, 0), rgb(40, 42, 50))
	k.cyl("Column", 2.4, 1.6, at(0, -0.2, 0), rgb(70, 74, 86))
	k.neon("Core", Vector3.new(1.8, 1.8, 1.8), at(0, 0.6, 0), rgb(255, 120, 60), Enum.PartType.Ball)
	for i = 0, 2 do
		k.part("Ring" .. i, Vector3.new(0.25, 3.2 - i * 0.3, 3.2 - i * 0.3), at(0, 0.6, 0) * ang(i * 1.05, 0.4, math.rad(90)), if i == 1 then YELLOW else CHROME, M.Metal, Enum.PartType.Cylinder)
	end
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		k.box("Pylon" .. i, Vector3.new(0.4, 2.8, 0.4), at(math.cos(a) * 1.6, -0.3, math.sin(a) * 1.6), rgb(176, 50, 44))
		k.neon("Tip" .. i, Vector3.new(0.45, 0.3, 0.45), at(math.cos(a) * 1.6, 1.2, math.sin(a) * 1.6), rgb(255, 190, 90))
	end
end

-- Metro Wreck --------------------------------------------------------------------------

function B.Hubcap(k)
	k.cyl("Disc", 0.14, 1.9, at(0, 0, 0) * ang(0.25, 0, 0), CHROME)
	k.cyl("Center", 0.2, 0.6, at(0, 0.04, 0) * ang(0.25, 0, 0), STEEL)
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		k.box("Spoke" .. i, Vector3.new(0.7, 0.05, 0.14), at(math.cos(a) * 0.5, 0.08, math.sin(a) * 0.5) * ang(0.25, -a, 0), STEEL_DARK)
	end
end

function B.ParkingMeter(k)
	k.cyl("Pole", 2.4, 0.22, at(0, -0.4, 0), STEEL_DARK)
	k.box("Head", Vector3.new(0.75, 0.9, 0.55), at(0, 1.1, 0), rgb(70, 80, 70))
	k.box("Window", Vector3.new(0.5, 0.35, 0.02), at(0, 1.2, -0.29), rgb(220, 230, 220), M.Glass)
	k.box("Flag", Vector3.new(0.2, 0.12, 0.02), at(0.05, 1.18, -0.3), RED, M.SmoothPlastic)
	k.ball("Dome", 0.75, at(0, 1.55, 0), rgb(70, 80, 70))
	k.box("Base", Vector3.new(0.6, 0.12, 0.6), at(0, -1.6, 0), BLACK)
end

function B.TrafficLight(k)
	k.box("Housing", Vector3.new(1.1, 3.0, 1.0), at(0, 0, 0) * ang(0, 0, math.rad(80)), rgb(40, 44, 40))
	local lamps = { rgb(220, 50, 40), rgb(240, 190, 40), rgb(60, 220, 90) }
	for i, c in ipairs(lamps) do
		local y = 1.0 - (i - 1)
		k.disc("Lamp" .. i, 0.12, 0.7, at(0, 0, 0) * ang(0, 0, math.rad(80)) * at(0, y, -0.52), c, M.Glass)
		k.box("Visor" .. i, Vector3.new(0.9, 0.1, 0.4), at(0, 0, 0) * ang(0, 0, math.rad(80)) * at(0, y + 0.42, -0.68), BLACK)
	end
	k.rod("Arm", 1.6, 0.25, at(-1.9, 0.6, 0) * ang(0, 0, 0.1), YELLOW)
end

function B.ManholeCover(k)
	k.cyl("Lid", 0.2, 2.7, at(0, 0, 0) * ang(0.2, 0, 0.1), rgb(62, 60, 56))
	for i = -2, 2 do
		k.box("Grip" .. i, Vector3.new(2.0 - math.abs(i) * 0.3, 0.05, 0.1), at(0, 0.12, i * 0.32) * ang(0.2, 0, 0.1), rgb(82, 80, 74))
	end
	k.cyl("Rim", 0.18, 2.8, at(0, -0.02, 0) * ang(0.2, 0, 0.1), RUST_DARK)
end

function B.StreetLamp(k)
	k.rod("Pole", 4.4, 0.32, at(0, 0, 0) * ang(0, 0, 0.12), rgb(50, 60, 56))
	k.box("Bend", Vector3.new(0.3, 1.0, 0.3), at(2.25, 0.6, 0) * ang(0, 0, -0.5), rgb(50, 60, 56))
	k.box("Head", Vector3.new(1.2, 0.35, 0.6), at(2.7, 1.05, 0), rgb(40, 46, 44))
	k.box("Bulb", Vector3.new(0.9, 0.1, 0.4), at(2.7, 0.85, 0), rgb(255, 220, 150), M.Glass)
	k.box("Base", Vector3.new(0.7, 0.5, 0.7), at(-2.2, -0.2, 0), rgb(40, 46, 44))
end

function B.CarDoor(k)
	k.box("Panel", Vector3.new(3.6, 2.0, 0.22), at(0, -0.3, 0) * ang(0.2, 0, 0.08), rgb(54, 102, 170))
	k.box("Window", Vector3.new(2.8, 1.0, 0.08), at(0.1, 1.2, 0) * ang(0.2, 0, 0.08), rgb(180, 200, 220), M.Glass)
	k.box("Frame", Vector3.new(3.0, 0.12, 0.24), at(0.1, 1.75, 0.1) * ang(0.2, 0, 0.08), rgb(40, 40, 44))
	k.box("Handle", Vector3.new(0.5, 0.12, 0.1), at(1.1, 0.2, -0.18) * ang(0.2, 0, 0.08), CHROME)
	k.box("Dent", Vector3.new(0.9, 0.6, 0.06), at(-0.8, -0.5, -0.12) * ang(0.2, 0.2, 0.08), rgb(44, 86, 146))
	k.box("Rust", Vector3.new(1.2, 0.25, 0.06), at(-0.3, -1.25, -0.1) * ang(0.2, 0, 0.08), RUST)
end

function B.WreckedScooter(k)
	k.box("Deck", Vector3.new(3.2, 0.4, 1.0), at(0, -0.4, 0) * ang(0, 0, 0.1), rgb(210, 200, 170))
	k.box("Body", Vector3.new(1.6, 1.2, 1.0), at(-0.8, 0.3, 0) * ang(0, 0, 0.1), rgb(110, 170, 160))
	k.box("Seat", Vector3.new(1.4, 0.25, 0.8), at(-0.8, 1.0, 0) * ang(0, 0, 0.1), BLACK, M.Fabric)
	k.box("Stem", Vector3.new(0.25, 1.8, 0.25), at(1.4, 0.6, 0) * ang(0, 0, -0.25), CHROME)
	k.rod("Bars", 1.3, 0.14, at(1.65, 1.45, 0) * ang(0, math.rad(90), 0), BLACK)
	k.disc("WheelF", 0.35, 1.1, at(1.6, -0.7, 0), BLACK)
	k.disc("WheelB", 0.35, 1.1, at(-1.4, -0.75, 0), BLACK)
	k.ball("Light", 0.4, at(1.65, 1.0, -0.15), rgb(255, 240, 200), M.Glass)
end

function B.EngineBlock(k)
	k.box("Block", Vector3.new(3.2, 1.9, 1.9), at(0, 0, 0), rgb(70, 74, 80))
	k.box("ValveL", Vector3.new(3.0, 0.45, 0.75), at(0, 1.15, -0.55) * ang(-0.3, 0, 0), RED)
	k.box("ValveR", Vector3.new(3.0, 0.45, 0.75), at(0, 1.15, 0.55) * ang(0.3, 0, 0), RED)
	k.box("Intake", Vector3.new(2.4, 0.5, 0.6), at(0, 1.4, 0), STEEL)
	k.disc("Pulley", 0.25, 1.1, at(1.75, 0.1, 0) * ang(0, math.rad(90), 0), BLACK)
	k.box("Pan", Vector3.new(2.8, 0.45, 1.5), at(0, -1.15, 0), BLACK)
	for i = 0, 3 do
		k.rod("Exh" .. i, 0.7, 0.2, at(-1.0 + i * 0.66, 0.2, -1.2) * ang(0, math.rad(90), 0.4), RUST)
	end
end

function B.ArmoredATM(k)
	k.box("Cabinet", Vector3.new(2.6, 3.8, 2.0), at(0, 0, 0), rgb(84, 92, 104), M.DiamondPlate)
	k.box("Screen", Vector3.new(1.5, 0.9, 0.06), at(0, 0.9, -1.02), rgb(40, 120, 150), M.Glass)
	k.box("Keypad", Vector3.new(1.0, 0.6, 0.2), at(0, 0.05, -1.08) * ang(-0.4, 0, 0), BLACK)
	k.box("Slot", Vector3.new(1.2, 0.12, 0.08), at(0, -0.55, -1.03), BLACK)
	k.box("Cash", Vector3.new(0.9, 0.08, 0.3), at(0, -0.55, -1.12), rgb(110, 190, 100), M.SmoothPlastic)
	k.box("Top", Vector3.new(2.8, 0.3, 2.2), at(0, 2.0, 0), rgb(200, 40, 40))
	k.box("Bolted", Vector3.new(2.8, 0.25, 2.2), at(0, -1.9, 0), BLACK)
end

function B.GoldenTaxi(k)
	local gold = rgb(255, 196, 50)
	k.box("Body", Vector3.new(7.4, 1.6, 3.4), at(0, -0.4, 0), gold)
	k.box("Cabin", Vector3.new(3.8, 1.3, 3.1), at(-0.3, 1.0, 0), gold)
	k.box("Windows", Vector3.new(3.6, 1.0, 3.2), at(-0.3, 1.05, 0), rgb(60, 60, 80), M.Glass)
	k.box("Sign", Vector3.new(1.2, 0.5, 0.6), at(-0.3, 1.9, 0), rgb(255, 250, 220), M.Neon)
	k.box("Checker", Vector3.new(7.45, 0.3, 3.45), at(0, -0.05, 0), BLACK)
	k.box("Bumper", Vector3.new(0.3, 0.4, 3.4), at(3.8, -0.8, 0), CHROME)
	k.box("BumperB", Vector3.new(0.3, 0.4, 3.4), at(-3.8, -0.8, 0), CHROME)
	for _, p in ipairs({ { 2.4, 1.75 }, { 2.4, -1.75 }, { -2.4, 1.75 }, { -2.4, -1.75 } }) do
		k.disc("Wheel" .. p[1] .. p[2], 0.6, 1.5, at(p[1], -1.15, p[2]), BLACK)
	end
	k.box("Lamp", Vector3.new(0.2, 0.3, 0.7), at(3.72, -0.3, 1.1), rgb(255, 250, 230), M.Neon)
	k.box("Lamp2", Vector3.new(0.2, 0.3, 0.7), at(3.72, -0.3, -1.1), rgb(255, 250, 230), M.Neon)
end

function B.StormShard(k)
	k.neon("Crystal", Vector3.new(0.7, 1.5, 0.7), at(0, 0, 0) * ang(0.3, 0.7, 0.2), rgb(150, 110, 255))
	k.neon("Crystal2", Vector3.new(0.45, 0.9, 0.45), at(0.35, -0.3, 0.1) * ang(-0.4, 0.2, 0.7), rgb(110, 200, 255))
	k.box("Rock", Vector3.new(0.9, 0.4, 0.8), at(0, -0.7, 0) * ang(0.1, 0.4, 0), rgb(60, 56, 70), M.Slate)
end

-- Builds the model. `scale` defaults to 1.
function ScrapModels.build(id, cframe, scale)
	local def = ScrapConfig.ById[id]
	scale = scale or 1
	cframe = cframe or CFrame.new()
	local model = Instance.new("Model")
	model.Name = id
	local root = Instance.new("Part")
	root.Name = "Root"
	local s = (def and def.Size or 1) * scale
	root.Size = Vector3.new(s, s, s)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = cframe
	root.Parent = model
	model.PrimaryPart = root
	local builder = B[id]
	if builder then
		builder(newKit(model, cframe, scale))
	else
		local kit = newKit(model, cframe, scale)
		kit.box("Lump", Vector3.new(1, 1, 1), at(0, 0, 0), RUST)
	end
	return model
end

-- For BulkMoveTo: every part and its offset from the model's pivot.
function ScrapModels.partsAndOffsets(model)
	local pivot = model:GetPivot()
	local parts, offsets = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(offsets, pivot:ToObjectSpace(d.CFrame))
		end
	end
	return parts, offsets
end

ScrapModels.Builders = B

return ScrapModels
