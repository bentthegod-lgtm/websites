--[[
	MachineModels - the three launchers, built from parts on a launch pad.

	build(machineId, padCFrame) -> model, rig
	  rig.launchOffset : CFrame (pad space) where the dummy leaves the machine
	  rig.pivot        : CFrame (pad space) the moving group rotates around
	  rig.mover        : Model that animates (catapult arm / barrel)  - PrimaryPart = pivot
	  rig.extras       : named parts the client animates (coils, piston, beacon, tank, gauge)
	Machines face +Z in pad space. Every part is anchored and non-colliding (the dummy is
	spawned at the launch point and must never snag on its own launcher).
	The client animates rest -> charge -> fire locally from the server's machine events;
	the server never depends on these visuals.
]]

local MachineConfig = require(script.Parent.Config.MachineConfig)

local MachineModels = {}

local rgb = Color3.fromRGB
local M = Enum.Material

local STEEL = rgb(92, 98, 108)
local DARK = rgb(44, 46, 52)
local HAZARD_Y = rgb(255, 200, 40)
local HAZARD_K = rgb(28, 28, 30)

local function mk(parent, name, size, cf, col, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = col
	p.Material = material or M.Metal
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball

-- Hazard stripes along a beam (alternating yellow / black blocks).
local function stripes(parent, cf, length, width, height, count)
	for i = 0, count - 1 do
		local seg = length / count
		mk(parent, "Stripe", Vector3.new(width, height, seg), cf * CFrame.new(0, 0, -length / 2 + seg * (i + 0.5)), if i % 2 == 0 then HAZARD_Y else HAZARD_K, M.SmoothPlastic)
	end
end

local function baseFrame(model, pad, accent)
	mk(model, "Base", Vector3.new(9, 1.2, 9), pad * CFrame.new(0, 0.6, 0), DARK, M.DiamondPlate)
	mk(model, "BaseTrim", Vector3.new(9.4, 0.4, 9.4), pad * CFrame.new(0, 0.2, 0), accent, M.SmoothPlastic)
	stripes(model, pad * CFrame.new(4.4, 1.25, 0), 9, 0.3, 0.1, 6)
	stripes(model, pad * CFrame.new(-4.4, 1.25, 0), 9, 0.3, 0.1, 6)
	local panel = mk(model, "ControlPanel", Vector3.new(2.2, 2.6, 1), pad * CFrame.new(-5.6, 1.3, -3.2) * CFrame.Angles(math.rad(-15), 0, 0), STEEL)
	mk(model, "Screen", Vector3.new(1.6, 1, 0.1), panel.CFrame * CFrame.new(0, 0.5, -0.52), rgb(60, 220, 160), M.Neon)
	mk(model, "ButtonRed", Vector3.new(0.4, 0.4, 0.2), panel.CFrame * CFrame.new(-0.4, -0.5, -0.55), rgb(235, 60, 50), M.Neon, BALL)
	mk(model, "ButtonGreen", Vector3.new(0.4, 0.4, 0.2), panel.CFrame * CFrame.new(0.4, -0.5, -0.55), rgb(80, 230, 110), M.Neon, BALL)
end

local function group(parent, name, pivotCF)
	local g = Instance.new("Model")
	g.Name = name
	local pivot = mk(g, "Pivot", Vector3.new(0.4, 0.4, 0.4), pivotCF, DARK)
	pivot.Transparency = 1
	g.PrimaryPart = pivot
	g.Parent = parent
	return g
end

-- Standard Launcher: catapult arm on an axle between two uprights.
local function standard(model, pad, def)
	local accent = rgb(def.Color[1], def.Color[2], def.Color[3])
	baseFrame(model, pad, accent)
	for _, x in ipairs({ -2.2, 2.2 }) do
		mk(model, "Upright", Vector3.new(0.8, 4.2, 1.2), pad * CFrame.new(x, 3.2, -1), STEEL)
		mk(model, "Brace", Vector3.new(0.5, 4.4, 0.5), pad * CFrame.new(x, 2.6, -2.6) * CFrame.Angles(math.rad(-32), 0, 0), STEEL)
	end
	local pivotCF = pad * CFrame.new(0, 4.9, -1)
	mk(model, "Axle", Vector3.new(5, 0.7, 0.7), pivotCF * CFrame.Angles(0, 0, 0), DARK, M.Metal, CYL)
	local arm = group(model, "Arm", pivotCF)
	-- Arm points up-forward at rest; "-Z" in arm space is toward the back.
	mk(arm, "Beam", Vector3.new(0.8, 0.6, 7), pivotCF * CFrame.new(0, 0, 2.6), accent, M.Metal)
	stripes(arm, pivotCF * CFrame.new(0, 0.32, 2.6), 6.6, 0.82, 0.06, 6)
	mk(arm, "Counterweight", Vector3.new(1.8, 1.6, 1.4), pivotCF * CFrame.new(0, -0.3, -1.4), DARK, M.Metal)
	local cup = mk(arm, "Cup", Vector3.new(2.4, 0.4, 2.4), pivotCF * CFrame.new(0, 0.45, 6.1), STEEL, M.Metal)
	for _, x in ipairs({ -1.1, 1.1 }) do
		mk(arm, "CupLip", Vector3.new(0.2, 0.6, 2.4), cup.CFrame * CFrame.new(x, 0.4, 0), STEEL)
	end
	mk(arm, "CupBack", Vector3.new(2.4, 0.6, 0.2), cup.CFrame * CFrame.new(0, 0.4, -1.1), STEEL)
	-- Rest pose: tilted 20 degrees up.
	arm:PivotTo(pivotCF * CFrame.Angles(math.rad(-20), 0, 0))
	return {
		launchOffset = CFrame.new(0, def.LaunchHeight, 4.5),
		pivot = pad:ToObjectSpace(pivotCF),
		mover = arm,
		rest = math.rad(-20),
		extras = {},
	}
end

-- Spring Cannon: an open frame barrel with a big coil spring and a piston plate.
local function spring(model, pad, def)
	local accent = rgb(def.Color[1], def.Color[2], def.Color[3])
	baseFrame(model, pad, accent)
	mk(model, "Mount", Vector3.new(2.4, 2.4, 2), pad * CFrame.new(0, 2.4, -0.5), STEEL)
	local pivotCF = pad * CFrame.new(0, 3.8, -0.5)
	local barrel = group(model, "Barrel", pivotCF)
	-- Barrel runs along +Z in barrel space; rails + rings make it read as a spring launcher.
	for _, x in ipairs({ -1.15, 1.15 }) do
		mk(barrel, "Rail", Vector3.new(0.3, 0.3, 8.5), pivotCF * CFrame.new(x, 0, 2.2), STEEL)
		mk(barrel, "RailLow", Vector3.new(0.3, 0.3, 8.5), pivotCF * CFrame.new(x * 0.6, -1.05, 2.2), STEEL)
	end
	for i = 0, 3 do
		mk(barrel, "Hoop", Vector3.new(0.35, 2.7, 2.7), pivotCF * CFrame.new(0, 0, -1.4 + i * 2.6) * CFrame.Angles(0, math.rad(90), 0), accent, M.Metal, CYL)
	end
	mk(barrel, "Muzzle", Vector3.new(0.6, 3.1, 3.1), pivotCF * CFrame.new(0, 0, 6.5) * CFrame.Angles(0, math.rad(90), 0), DARK, M.Metal, CYL)
	local coils = {}
	for i = 1, 7 do
		local c = mk(barrel, "Coil" .. i, Vector3.new(0.22, 2.1, 2.1), pivotCF * CFrame.new(0, 0, -1.6 + i * 0.55) * CFrame.Angles(0, math.rad(90), 0), rgb(200, 205, 215), M.Metal, CYL)
		table.insert(coils, c)
	end
	local piston = mk(barrel, "Piston", Vector3.new(0.4, 2.2, 2.2), pivotCF * CFrame.new(0, 0, 2.6) * CFrame.Angles(0, math.rad(90), 0), HAZARD_Y, M.SmoothPlastic, CYL)
	mk(barrel, "BackPlate", Vector3.new(2.6, 2.6, 0.5), pivotCF * CFrame.new(0, 0, -2), DARK)
	barrel:PivotTo(pivotCF * CFrame.Angles(math.rad(-30), 0, 0))
	return {
		launchOffset = CFrame.new(0, def.LaunchHeight, 5.5),
		pivot = pad:ToObjectSpace(pivotCF),
		mover = barrel,
		rest = math.rad(-30),
		extras = { coils = coils, piston = piston },
	}
end

-- Experimental Air Cannon: fat barrel, pressure tank, pipes, gauge and warning beacon.
local function air(model, pad, def)
	local accent = rgb(def.Color[1], def.Color[2], def.Color[3])
	baseFrame(model, pad, accent)
	mk(model, "Turret", Vector3.new(1.6, 4.6, 4.6), pad * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)), STEEL, M.Metal, CYL)
	local tank = mk(model, "Tank", Vector3.new(5, 3.2, 3.2), pad * CFrame.new(0, 3, -3.6) * CFrame.Angles(0, math.rad(90), 0), rgb(220, 224, 230), M.Metal, CYL)
	for _, x in ipairs({ -1.6, 1.6 }) do
		mk(model, "TankBand", Vector3.new(0.3, 3.4, 3.4), tank.CFrame * CFrame.new(x, 0, 0), accent, M.Metal, CYL)
	end
	mk(model, "Pipe", Vector3.new(0.5, 0.5, 3), pad * CFrame.new(1.6, 4.6, -1.6) * CFrame.Angles(math.rad(-35), 0, 0), DARK)
	mk(model, "Pipe2", Vector3.new(0.5, 0.5, 3), pad * CFrame.new(-1.6, 4.6, -1.6) * CFrame.Angles(math.rad(-35), 0, 0), DARK)
	local gauge = mk(model, "Gauge", Vector3.new(0.2, 1.2, 1.2), pad * CFrame.new(2.6, 3.4, -3.6) * CFrame.Angles(0, 0, 0), rgb(240, 240, 235), M.SmoothPlastic, CYL)
	local needle = mk(model, "Needle", Vector3.new(0.08, 0.5, 0.08), gauge.CFrame * CFrame.new(0.12, 0.2, 0), rgb(220, 40, 30), M.SmoothPlastic)
	mk(model, "BeaconPost", Vector3.new(0.4, 3, 0.4), pad * CFrame.new(-3.6, 2.7, -3.6), STEEL)
	local beacon = mk(model, "Beacon", Vector3.new(0.9, 0.9, 0.9), pad * CFrame.new(-3.6, 4.4, -3.6), rgb(255, 80, 40), M.Neon, BALL)
	local light = Instance.new("PointLight")
	light.Name = "BeaconLight"
	light.Color = rgb(255, 90, 40)
	light.Range = 14
	light.Brightness = 0
	light.Shadows = false
	light.Parent = beacon
	local pivotCF = pad * CFrame.new(0, 4.6, 0)
	local barrel = group(model, "Barrel", pivotCF)
	mk(barrel, "Tube", Vector3.new(9, 2.6, 2.6), pivotCF * CFrame.new(0, 0, 3.2) * CFrame.Angles(0, math.rad(90), 0), STEEL, M.Metal, CYL)
	mk(barrel, "Breech", Vector3.new(2, 3.4, 3.4), pivotCF * CFrame.new(0, 0, -1.2) * CFrame.Angles(0, math.rad(90), 0), DARK, M.Metal, CYL)
	for i = 0, 2 do
		mk(barrel, "Band", Vector3.new(0.4, 2.9, 2.9), pivotCF * CFrame.new(0, 0, 0.8 + i * 2.4) * CFrame.Angles(0, math.rad(90), 0), accent, M.Metal, CYL)
	end
	local muzzle = mk(barrel, "Muzzle", Vector3.new(0.8, 3.2, 3.2), pivotCF * CFrame.new(0, 0, 7.8) * CFrame.Angles(0, math.rad(90), 0), DARK, M.Metal, CYL)
	stripes(barrel, pivotCF * CFrame.new(0, 1.35, 3.2), 7, 0.4, 0.1, 7)
	barrel:PivotTo(pivotCF * CFrame.Angles(math.rad(-45), 0, 0))
	return {
		launchOffset = CFrame.new(0, def.LaunchHeight, 6),
		pivot = pad:ToObjectSpace(pivotCF),
		mover = barrel,
		rest = math.rad(-45),
		extras = { beacon = beacon, beaconLight = light, tank = tank, needle = needle, muzzle = muzzle },
	}
end

local BUILDERS = { Standard = standard, Spring = spring, AirCannon = air }

function MachineModels.build(machineId, padCFrame)
	local def = MachineConfig.ById[machineId] or MachineConfig.ById.Standard
	local model = Instance.new("Model")
	model.Name = "Machine_" .. def.Id
	local rig = BUILDERS[def.Id](model, padCFrame, def)
	rig.machineId = def.Id
	model:SetAttribute("Machine", def.Id)
	return model, rig
end

return MachineModels
