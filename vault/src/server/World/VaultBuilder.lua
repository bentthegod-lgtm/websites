--[[
	VaultBuilder - builds the whole underground vault: seven depths stacked in one
	continuous structure around a shared elevator shaft.

	Every depth follows the same floor plan, dressed differently by Themes:
	  * Arrival hall (z -72..-38): elevator cabin in the back wall, deposit machine(s) on the
	    left, upgrade terminal on the right, depth signage, the painted depth number,
	    maintenance / security access doors, cameras.
	  * A line of pillars with an overhead "MAIN CHAMBER" beam (z -38).
	  * Main chamber (z -36..72): a clear central aisle from the elevator to the exit, the
	    depth's landmark, storage along the side walls, collection zones left and right.
	  * Exit route (z 74..97): a corridor to a massive circular vault door with restricted
	    signage, a reinforced window into a preview chamber of the NEXT depth, and sealed
	    maintenance stairs going down behind the door.
	Ceiling infrastructure on every floor: beams, ventilation ducts, cable trays, pipes,
	light fixtures.

	Loot spawn points are generated per depth (floor grid in the collection zones plus
	shelf / table / plinth points the theme adds) and filtered against keep-out boxes
	(aisle, landmark, machines, doorways) so loot never blocks a route.
	Returns a world record (see the bottom) used by every service.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local GameConfig = require(Shared.Config.GameConfig)
local DepthConfig = require(Shared.Config.DepthConfig)
local LootTable = require(Shared.LootTable)
local Props = require(script.Parent.Props)
local Machines = require(script.Parent.Machines)
local Themes = require(script.Parent.Themes)

local VaultBuilder = {}

local M = Enum.Material
local C = Props.Colors
local Z = Vector3.zAxis

local W2 = GameConfig.RoomWidth / 2 -- 84
local FRONT = GameConfig.RoomFront -- -72
local BACK = GameConfig.RoomBack -- 74
local H = GameConfig.CeilingHeight -- 34
local HALL_END = -38

local function facing(pos, dir)
	return CFrame.lookAt(pos, pos + dir)
end

-- Keep-out boxes in the XZ plane (relative to the depth origin): {x0, x1, z0, z1}.
local function inBox(box, x, z, pad)
	pad = pad or 0
	return x >= box[1] - pad and x <= box[2] + pad and z >= box[3] - pad and z <= box[4] + pad
end
VaultBuilder.inBox = inBox

local function shell(ctx)
	local b, y0, pal = ctx.b, ctx.y0, ctx.palette
	local wall, floor, trim, accent, light = Props.rgb(pal.Wall), Props.rgb(pal.Floor), Props.rgb(pal.Trim), Props.rgb(pal.Accent), Props.rgb(pal.Light)
	local style = ctx.style
	-- Floor slab and the arrival hall's metal plates.
	b.part({ Name = "Floor", Size = Vector3.new(GameConfig.RoomWidth + 4, 2, BACK - FRONT + 4), CFrame = CFrame.new(0, y0 - 1, (FRONT + BACK) / 2), Color = floor, Material = style.FloorMaterial, Reflectance = style.FloorReflect or 0 })
	b.deco({ Name = "HallPlates", Size = Vector3.new(GameConfig.RoomWidth, 0.06, HALL_END - FRONT), CFrame = CFrame.new(0, y0 + 0.03, (FRONT + HALL_END) / 2), Color = trim, Material = M.DiamondPlate })
	-- Walls (2 thick) with openings for the elevator (front) and exit corridor (back).
	local function wallPart(name, size, pos)
		return b.part({ Name = name, Size = size, CFrame = CFrame.new(pos), Color = wall, Material = style.WallMaterial })
	end
	wallPart("WallLeft", Vector3.new(2, H, BACK - FRONT + 4), Vector3.new(-W2 - 1, y0 + H / 2, (FRONT + BACK) / 2))
	wallPart("WallRight", Vector3.new(2, H, BACK - FRONT + 4), Vector3.new(W2 + 1, y0 + H / 2, (FRONT + BACK) / 2))
	-- Front wall: elevator opening x -7..7, height 11.
	wallPart("WallFrontL", Vector3.new(W2 - 7, H, 2), Vector3.new(-(W2 + 7) / 2, y0 + H / 2, FRONT - 1))
	wallPart("WallFrontR", Vector3.new(W2 - 7, H, 2), Vector3.new((W2 + 7) / 2, y0 + H / 2, FRONT - 1))
	wallPart("WallFrontTop", Vector3.new(14, H - 11, 2), Vector3.new(0, y0 + 11 + (H - 11) / 2, FRONT - 1))
	-- Back wall: corridor opening x -12..12, height 20.
	wallPart("WallBackL", Vector3.new(W2 - 12, H, 2), Vector3.new(-(W2 + 12) / 2, y0 + H / 2, BACK + 1))
	wallPart("WallBackR", Vector3.new(W2 - 12, H, 2), Vector3.new((W2 + 12) / 2, y0 + H / 2, BACK + 1))
	wallPart("WallBackTop", Vector3.new(24, H - 20, 2), Vector3.new(0, y0 + 20 + (H - 20) / 2, BACK + 1))
	b.part({ Name = "Ceiling", Size = Vector3.new(GameConfig.RoomWidth + 4, 2, BACK - FRONT + 4), CFrame = CFrame.new(0, y0 + H + 1, (FRONT + BACK) / 2), Color = trim, Material = M.Concrete })
	-- Wainscot band and top trim (accent stripe) on the long walls.
	for _, x in ipairs({ -W2 + 0.15, W2 - 0.15 }) do
		b.deco({ Name = "Wainscot", Size = Vector3.new(0.3, 3, BACK - FRONT), CFrame = CFrame.new(x, y0 + 1.5, (FRONT + BACK) / 2), Color = trim, Material = M.Metal })
		b.deco({ Name = "WallStripe", Size = Vector3.new(0.32, 0.5, BACK - FRONT), CFrame = CFrame.new(x, y0 + 3.2, (FRONT + BACK) / 2), Color = accent, Material = M.Metal })
	end
	-- Pilasters along the side walls every 16 studs.
	for z = FRONT + 10, BACK - 8, 16 do
		for _, x in ipairs({ -W2 + 0.7, W2 - 0.7 }) do
			b.part({ Name = "Pilaster", Size = Vector3.new(1.4, H, 2.4), CFrame = CFrame.new(x, y0 + H / 2, z), Color = trim, Material = style.WallMaterial })
		end
	end
	-- Ceiling beams, ducts, cable trays, pipes.
	for z = FRONT + 12, BACK - 6, 18 do
		b.deco({ Name = "CeilingBeam", Size = Vector3.new(GameConfig.RoomWidth, 1.6, 1.2), CFrame = CFrame.new(0, y0 + H - 0.8, z), Color = C.SteelDark, Material = M.Metal })
	end
	for _, x in ipairs({ -44, 44 }) do
		Props.duct(b, Vector3.new(x, y0 + H - 3.2, FRONT + 4), Vector3.new(x, y0 + H - 3.2, BACK - 4), 3.4, C.SteelLight)
	end
	for _, x in ipairs({ -18, 18 }) do
		Props.cableTray(b, Vector3.new(x, y0 + H - 2.2, FRONT + 4), Vector3.new(x, y0 + H - 2.2, BACK - 4))
	end
	for _, x in ipairs({ -W2 + 1.2, W2 - 1.2 }) do
		Props.pipe(b, Vector3.new(x, y0 + H - 6, FRONT + 4), Vector3.new(x, y0 + H - 6, BACK - 4), 1.2, style.PipeColor or C.SteelLight)
		Props.pipe(b, Vector3.new(x, y0 + H - 7.6, FRONT + 4), Vector3.new(x, y0 + H - 7.6, BACK - 4), 0.7, accent)
	end
	-- Light fixtures: 3 x 3 over the chamber, 2 in the hall (shadows on the centre row only).
	ctx.lights = {}
	for _, x in ipairs({ -30, 0, 30 }) do
		for _, z in ipairs({ -18, 12, 42 }) do
			local _, l = Props.lightFixture(b, CFrame.new(x, y0 + H - 1.8, z), light, style.LightBrightness or 2.2, 46, 8)
			l.Shadows = x == 0
			table.insert(ctx.lights, l)
		end
	end
	for _, x in ipairs({ -30, 30 }) do
		local _, l = Props.lightFixture(b, CFrame.new(x, y0 + H - 1.8, -56), light, (style.LightBrightness or 2.2) * 0.9, 40, 8)
		l.Shadows = false
		table.insert(ctx.lights, l)
	end
end

local function arrival(ctx)
	local b, y0, pal, def = ctx.b, ctx.y0, ctx.palette, ctx.def
	local accent, trim = Props.rgb(pal.Accent), Props.rgb(pal.Trim)
	-- Elevator cabin in the front wall.
	local cabinCF = facing(Vector3.new(0, y0, FRONT - 6.5), Z)
	ctx.elevator = Machines.elevator(b, cabinCF, def.Code, accent)
	-- Elevator surround: frame, depth display, call panel, hazard sill.
	b.deco({ Name = "ElevatorFrameTop", Size = Vector3.new(17, 1.4, 1), CFrame = CFrame.new(0, y0 + 11.7, FRONT + 0.4), Color = C.SteelDark, Material = M.Metal })
	for _, x in ipairs({ -8, 8 }) do
		b.deco({ Name = "ElevatorFrameSide", Size = Vector3.new(1.2, 11, 1), CFrame = CFrame.new(x, y0 + 5.5, FRONT + 0.4), Color = C.SteelDark, Material = M.Metal })
	end
	local display = b.deco({ Name = "DepthDisplay", Size = Vector3.new(5, 1.6, 0.3), CFrame = facing(Vector3.new(0, y0 + 13.4, FRONT + 0.2), Z), Color = C.Black, Material = M.SmoothPlastic })
	ctx.elevator.display = Props.text(display, Enum.NormalId.Front, def.Code, { Color = Color3.fromRGB(255, 170, 60), PPS = 40, Brightness = 2, LightInfluence = 0 })
	Props.accessPanel(b, facing(Vector3.new(9.6, y0 + 4.4, FRONT + 0.2), Z), true)
	Props.hazardStripes(b, CFrame.new(0, y0, FRONT + 1.4), 14, 1.2)
	Props.sign(b, facing(Vector3.new(0, y0 + 17, FRONT + 0.2), Z), 30, 3.4, def.Code .. "  |  " .. string.upper(def.Name), { Color = accent, PPS = 30 })
	Props.sign(b, facing(Vector3.new(0, y0 + 14.9, FRONT + 0.2), Z), 10, 0.9, "ELEVATOR - ALL DEPTHS", { PPS = 40, Trim = false })
	Props.floorText(b, CFrame.new(0, y0, -60) * CFrame.Angles(0, math.pi, 0), 9, 7, def.Code, accent)
	-- Deposit machine(s) on the left (two in the starting area so a crowd doesn't queue).
	ctx.deposits = {}
	local xs = if def.Depth == 1 then { -28, -50 } else { -30 }
	for i, x in ipairs(xs) do
		local id = string.format("D%d_%d", def.Depth, i)
		table.insert(ctx.deposits, Machines.deposit(b, facing(Vector3.new(x, y0, -60), Z), id, accent))
		table.insert(ctx.keepOut, { x - 6, x + 6, -64, -42 })
	end
	-- Upgrade terminal on the right.
	ctx.terminal = Machines.terminal(b, facing(Vector3.new(30, y0, -58), Z), accent, def.Depth == 1)
	table.insert(ctx.keepOut, { 24, 36, -62, -50 })
	-- Hanging direction signs.
	Props.sign(b, facing(Vector3.new(-28, y0 + 14, -46), -Z), 12, 1.6, "<<  DEPOSIT", { Color = Color3.fromRGB(120, 255, 170), PPS = 30 })
	Props.sign(b, facing(Vector3.new(30, y0 + 14, -46), -Z), 12, 1.6, "UPGRADES  >>", { Color = accent, PPS = 30 })
	for _, x in ipairs({ -28, 30 }) do
		for _, dx in ipairs({ -5, 5 }) do
			b.deco({ Name = "SignCable", Size = Vector3.new(0.08, H - 15, 0.08), CFrame = CFrame.new(x + dx, y0 + 14.8 + (H - 15) / 2, -46), Color = C.Black, CastShadow = false })
		end
	end
	-- Side access doors and cameras.
	Props.accessDoor(b, facing(Vector3.new(-W2, y0, -54), Vector3.xAxis), "MAINTENANCE")
	Props.accessDoor(b, facing(Vector3.new(W2, y0, -54), -Vector3.xAxis), "SECURITY")
	Props.camera(b, facing(Vector3.new(-W2 + 0.4, y0 + H - 4, FRONT + 4), Vector3.new(1, 0, 1).Unit))
	Props.camera(b, facing(Vector3.new(W2 - 0.4, y0 + H - 4, FRONT + 4), Vector3.new(-1, 0, 1).Unit))
	Props.camera(b, facing(Vector3.new(-W2 + 0.4, y0 + H - 4, BACK - 4), Vector3.new(1, 0, -1).Unit))
	Props.camera(b, facing(Vector3.new(W2 - 0.4, y0 + H - 4, BACK - 4), Vector3.new(-1, 0, -1).Unit))
	-- The pillar line between the hall and the chamber, with the overhead beam.
	for _, x in ipairs({ -58, -38, -18, 18, 38, 58 }) do
		Props.pillar(b, CFrame.new(x, y0, HALL_END), H, 3, trim, ctx.style.WallMaterial)
		table.insert(ctx.keepOut, { x - 3, x + 3, HALL_END - 3, HALL_END + 3 })
	end
	b.deco({ Name = "ChamberBeam", Size = Vector3.new(GameConfig.RoomWidth, 2.4, 2), CFrame = CFrame.new(0, y0 + H - 5, HALL_END), Color = C.SteelDark, Material = M.Metal })
	Props.sign(b, facing(Vector3.new(0, y0 + H - 5, HALL_END - 1.1), -Z), 22, 2, "MAIN CHAMBER  -  " .. def.Code, { Color = accent, PPS = 30 })
	-- Central aisle markings from the elevator to the exit corridor.
	for _, x in ipairs({ -6.5, 6.5 }) do
		b.deco({ Name = "AisleLine", Size = Vector3.new(0.4, 0.05, BACK - FRONT - 4), CFrame = CFrame.new(x, y0 + 0.03, (FRONT + BACK) / 2 + 1), Color = C.Hazard, CastShadow = false })
	end
	table.insert(ctx.keepOut, { -7.5, 7.5, FRONT, BACK + 30 })
	table.insert(ctx.keepOut, { -W2, W2, FRONT, HALL_END + 2 }) -- the arrival hall itself
end

local function exitRoute(ctx)
	local b, y0, pal, def = ctx.b, ctx.y0, ctx.palette, ctx.def
	local accent, wall = Props.rgb(pal.Accent), Props.rgb(pal.Wall)
	local zEnd = BACK + 23
	local wz = BACK + 12 -- centre of the preview window
	local nextDef = DepthConfig.get(def.Depth + 1)
	b.part({ Name = "CorridorFloor", Size = Vector3.new(26, 2, zEnd - BACK + 2), CFrame = CFrame.new(0, y0 - 1, (BACK + zEnd) / 2 + 1), Color = C.SteelDark, Material = M.DiamondPlate })
	b.part({ Name = "CorridorCeiling", Size = Vector3.new(26, 2, zEnd - BACK + 2), CFrame = CFrame.new(0, y0 + 21, (BACK + zEnd) / 2 + 1), Color = C.SteelDark, Material = M.Concrete })
	b.part({ Name = "CorridorWallL", Size = Vector3.new(2, 20, zEnd - BACK), CFrame = CFrame.new(-13, y0 + 10, (BACK + zEnd) / 2 + 1), Color = wall, Material = ctx.style.WallMaterial })
	-- Right wall with the preview window (12 wide, y 3..12).
	b.part({ Name = "CorridorWallR1", Size = Vector3.new(2, 20, wz - 6 - BACK - 2), CFrame = CFrame.new(13, y0 + 10, (BACK + 2 + wz - 6) / 2), Color = wall, Material = ctx.style.WallMaterial })
	b.part({ Name = "CorridorWallR2", Size = Vector3.new(2, 20, zEnd - wz - 6), CFrame = CFrame.new(13, y0 + 10, (wz + 6 + zEnd) / 2), Color = wall, Material = ctx.style.WallMaterial })
	b.part({ Name = "CorridorWallR3", Size = Vector3.new(2, 3, 12), CFrame = CFrame.new(13, y0 + 1.5, wz), Color = wall, Material = ctx.style.WallMaterial })
	b.part({ Name = "CorridorWallR4", Size = Vector3.new(2, 8, 12), CFrame = CFrame.new(13, y0 + 16, wz), Color = wall, Material = ctx.style.WallMaterial })
	b.part({ Name = "PreviewGlass", Size = Vector3.new(0.6, 9, 12), CFrame = CFrame.new(13, y0 + 7.5, wz), Color = C.Glass, Material = M.Glass, Transparency = 0.55, CastShadow = false })
	for _, z in ipairs({ wz - 5.7, wz - 2, wz + 2, wz + 5.7 }) do
		b.deco({ Name = "GlassBar", Size = Vector3.new(0.8, 9, 0.35), CFrame = CFrame.new(12.6, y0 + 7.5, z), Color = C.SteelDark, Material = M.Metal })
	end
	-- Restricted signage and warning lights by the door.
	local restricted = if nextDef then string.format("RESTRICTED  -  %s %s  -  CLEARANCE REQUIRED", nextDef.Code, string.upper(nextDef.Name)) else "NO FURTHER ACCESS  -  ANCIENT VAULT COMPLEX: SEALED"
	Props.sign(b, facing(Vector3.new(0, y0 + 18.4, zEnd - 0.6), -Z), 22, 1.6, restricted, { Color = Color3.fromRGB(255, 90, 80), PPS = 30 })
	for _, x in ipairs({ -10.5, 10.5 }) do
		Props.warningLight(b, CFrame.new(x, y0 + 17, zEnd - 1.2), Color3.fromRGB(255, 150, 40))
	end
	Props.hazardStripes(b, CFrame.new(0, y0, zEnd - 3), 22, 1.4)
	Props.camera(b, facing(Vector3.new(-11.6, y0 + 17, BACK + 4), Vector3.new(1, 0, 1).Unit))
	-- End wall with a square opening behind the round door.
	b.part({ Name = "DoorWallL", Size = Vector3.new(6, 20, 2), CFrame = CFrame.new(-10, y0 + 10, zEnd + 1.5), Color = wall, Material = ctx.style.WallMaterial })
	b.part({ Name = "DoorWallR", Size = Vector3.new(6, 20, 2), CFrame = CFrame.new(10, y0 + 10, zEnd + 1.5), Color = wall, Material = ctx.style.WallMaterial })
	b.part({ Name = "DoorWallTop", Size = Vector3.new(14, 6, 2), CFrame = CFrame.new(0, y0 + 17, zEnd + 1.5), Color = wall, Material = ctx.style.WallMaterial })
	ctx.exitDoor = Props.vaultDoor(b, facing(Vector3.new(0, y0 + 8.5, zEnd), -Z), 15, accent, ctx.folder)
	ctx.exitDoor.next = def.Depth + 1
	ctx.exitDoor.model:SetAttribute("ExitDoor", true)
	ctx.exitDoor.model:SetAttribute("NextDepth", def.Depth + 1) -- the client swings it open once that depth is unlocked
	-- Behind the door: sealed maintenance stairs going down.
	local stairs = { z0 = zEnd + 3, steps = 10 }
	for i = 1, stairs.steps do
		b.part({ Name = "Step", Size = Vector3.new(12, 1, 2), CFrame = CFrame.new(0, y0 - i * 1.0 - 0.5, stairs.z0 + i * 2), Color = C.SteelDark, Material = M.DiamondPlate })
	end
	for _, x in ipairs({ -7, 7 }) do
		b.part({ Name = "StairWall", Size = Vector3.new(2, 30, stairs.steps * 2 + 6), CFrame = CFrame.new(x, y0 - 2, stairs.z0 + stairs.steps + 2), Color = wall, Material = ctx.style.WallMaterial })
	end
	b.part({ Name = "StairCeiling", Size = Vector3.new(16, 2, stairs.steps * 2 + 6), CFrame = CFrame.new(0, y0 + 13, stairs.z0 + stairs.steps + 2), Color = C.SteelDark, Material = M.Concrete })
	local grate = b.part({ Name = "SealedGrate", Size = Vector3.new(12, 16, 0.6), CFrame = CFrame.new(0, y0 - stairs.steps + 6, stairs.z0 + stairs.steps * 2 + 3), Color = C.SteelDark, Material = M.DiamondPlate })
	Props.text(grate, Enum.NormalId.Front, "SEALED - USE ELEVATOR", { Color = C.Hazard, PPS = 20 })
	b.part({ Name = "StairBottom", Size = Vector3.new(12, 1, 6), CFrame = CFrame.new(0, y0 - stairs.steps - 1.5, stairs.z0 + stairs.steps * 2 + 0.5), Color = C.SteelDark, Material = M.DiamondPlate })
	local stairLight = b.deco({ Name = "StairLight", Size = Vector3.new(4, 0.2, 0.6), CFrame = CFrame.new(0, y0 + 11.8, stairs.z0 + stairs.steps), Color = Color3.fromRGB(255, 120, 60), Material = M.Neon })
	local sl = Instance.new("PointLight")
	sl.Color = Color3.fromRGB(255, 140, 80)
	sl.Range = 18
	sl.Brightness = 0.9
	sl.Shadows = false
	sl.Parent = stairLight
	-- Corridor light.
	local _, cl = Props.lightFixture(b, CFrame.new(0, y0 + 19.4, (BACK + zEnd) / 2), Props.rgb(pal.Light), 1.8, 30, 8)
	cl.Shadows = false
	-- Preview chamber: what waits on the next depth, behind reinforced glass.
	local pv = { x0 = 14, x1 = 32, z0 = wz - 8.5, z1 = wz + 8.5 }
	local nextPal = if nextDef then nextDef.Palette else { Wall = { 90, 84, 70 }, Floor = { 60, 54, 44 }, Accent = { 190, 160, 110 }, Light = { 255, 220, 170 } }
	b.part({ Name = "PreviewFloor", Size = Vector3.new(pv.x1 - pv.x0, 1, pv.z1 - pv.z0), CFrame = CFrame.new((pv.x0 + pv.x1) / 2, y0 - 0.5, (pv.z0 + pv.z1) / 2), Color = Props.rgb(nextPal.Floor), Material = M.Marble })
	b.part({ Name = "PreviewCeiling", Size = Vector3.new(pv.x1 - pv.x0, 1, pv.z1 - pv.z0), CFrame = CFrame.new((pv.x0 + pv.x1) / 2, y0 + 14.5, (pv.z0 + pv.z1) / 2), Color = Props.rgb(nextPal.Wall), Material = M.Concrete })
	b.part({ Name = "PreviewBack", Size = Vector3.new(1, 15, pv.z1 - pv.z0), CFrame = CFrame.new(pv.x1 + 0.5, y0 + 7, (pv.z0 + pv.z1) / 2), Color = Props.rgb(nextPal.Wall), Material = M.Concrete })
	for _, z in ipairs({ pv.z0 - 0.5, pv.z1 + 0.5 }) do
		b.part({ Name = "PreviewSide", Size = Vector3.new(pv.x1 - pv.x0 + 2, 15, 1), CFrame = CFrame.new((pv.x0 + pv.x1) / 2, y0 + 7, z), Color = Props.rgb(nextPal.Wall), Material = M.Concrete })
	end
	local spot = b.deco({ Name = "PreviewLight", Size = Vector3.new(6, 0.2, 6), CFrame = CFrame.new(23, y0 + 13.9, wz), Color = Props.rgb(nextPal.Light), Material = M.Neon })
	local pl = Instance.new("SpotLight")
	pl.Face = Enum.NormalId.Bottom
	pl.Angle = 90
	pl.Range = 22
	pl.Brightness = 2.4
	pl.Color = Props.rgb(nextPal.Light)
	pl.Shadows = false
	pl.Parent = spot
	local label = if nextDef then string.format("%s  %s", nextDef.Code, string.upper(nextDef.Name)) else "ANCIENT VAULT  -  COMING SOON"
	Props.sign(b, facing(Vector3.new(pv.x1, y0 + 11.5, wz), -Vector3.xAxis), 12, 1.6, label, { Color = Props.rgb(nextPal.Accent), PPS = 30 })
	ctx.preview = { cframes = {}, nextDepth = if nextDef then nextDef.Depth else nil }
	for i, z in ipairs({ wz - 4.5, wz, wz + 4.5 }) do
		local top = Props.displayCase(b, CFrame.new(23, y0, z), 3.4, 3, 2.4 + (i % 2) * 0.6, Props.rgb(nextPal.Wall), 2.6)
		table.insert(ctx.preview.cframes, top)
	end
end

-- Floor spawn grid in the collection zones, plus the theme's extra points, filtered.
local function spawnPoints(ctx)
	local rng = Random.new(ctx.def.Depth * 1013)
	local points = {}
	local function ok(x, z)
		if x < -W2 + 4 or x > W2 - 4 or z < HALL_END + 3 or z > BACK - 3 then
			return false
		end
		for _, box in ipairs(ctx.keepOut) do
			if inBox(box, x, z, 1.5) then
				return false
			end
		end
		for _, p in ipairs(points) do
			local d = p.local2 - Vector2.new(x, z)
			if d.Magnitude < 3.2 then
				return false
			end
		end
		return true
	end
	for _, zone in ipairs(ctx.zones) do
		for x = zone[1], zone[2], 6.5 do
			for z = zone[3], zone[4], 6.5 do
				local jx, jz = x + rng:NextNumber(-1.4, 1.4), z + rng:NextNumber(-1.4, 1.4)
				if ok(jx, jz) then
					table.insert(points, { cframe = CFrame.new(jx, ctx.y0, jz) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), size = "L", kind = "Floor", local2 = Vector2.new(jx, jz) })
				end
			end
		end
	end
	for _, extra in ipairs(ctx.extraPoints) do
		local pos = extra.cframe.Position
		table.insert(points, { cframe = extra.cframe * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), size = extra.size, kind = extra.kind, local2 = Vector2.new(pos.X, pos.Z) })
	end
	for i, p in ipairs(points) do
		p.index = i
		p.local2 = nil
	end
	return points
end

function VaultBuilder.build()
	local existing = Workspace:FindFirstChild("Vault")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Vault"
	folder.Parent = Workspace
	local lootFolder = Instance.new("Folder")
	lootFolder.Name = "Loot"
	lootFolder.Parent = folder

	local world = { folder = folder, lootFolder = lootFolder, depths = {}, machines = {}, partCount = 0 }
	local shaftDepths = {}
	for _, def in ipairs(DepthConfig.List) do
		local y0 = -(def.Depth - 1) * GameConfig.DepthSpacing
		local depthFolder = Instance.new("Folder")
		depthFolder.Name = def.Code
		depthFolder.Parent = folder
		local b = Props.builder(depthFolder)
		local ctx = {
			b = b,
			folder = depthFolder,
			y0 = y0,
			def = def,
			palette = def.Palette,
			style = Themes.style(def.Depth),
			keepOut = {},
			extraPoints = {},
			zones = { { -48, -13, -30, GameConfig.RoomBack - 8 }, { 13, 48, -30, GameConfig.RoomBack - 8 } },
		}
		shell(ctx)
		arrival(ctx)
		exitRoute(ctx)
		Themes.build(ctx) -- landmark, storage, decor; adds keep-outs and extra points
		ctx.points = spawnPoints(ctx)
		local record = {
			depth = def.Depth,
			def = def,
			y0 = y0,
			folder = depthFolder,
			points = ctx.points,
			keepOut = ctx.keepOut,
			deposits = ctx.deposits,
			terminal = ctx.terminal,
			elevator = ctx.elevator,
			exitDoor = ctx.exitDoor,
			preview = ctx.preview,
			landmark = ctx.landmark,
			rarePoint = ctx.rarePoint,
			ambience = ctx.ambience,
			parts = b.count,
		}
		-- Loot staged in the preview chamber: the next floor's items, decorative only.
		record.previewItems = ctx.preview.nextDepth
		world.depths[def.Depth] = record
		for _, machine in ipairs(ctx.deposits) do
			world.machines[machine.id] = machine
			machine.depth = def.Depth
		end
		world.partCount += b.count
		table.insert(shaftDepths, { y = y0, code = def.Code })
	end
	-- One shaft through every floor.
	local shaftFolder = Instance.new("Folder")
	shaftFolder.Name = "Shaft"
	shaftFolder.Parent = folder
	local sb = Props.builder(shaftFolder)
	Machines.shaft(sb, GameConfig.CeilingHeight + 2, -(DepthConfig.Count - 1) * GameConfig.DepthSpacing - 4, FRONT - 13.5, shaftDepths)
	world.partCount += sb.count
	-- Starting area extras: four leaderboards on the hall walls and the how-to board.
	local d1 = world.depths[1]
	local b1 = Props.builder(d1.folder)
	world.boards = {}
	for i, lb in ipairs(GameConfig.Leaderboards) do
		local x = if i <= 2 then -W2 + 1.7 else W2 - 1.7 -- in front of the pilasters
		local z = if i % 2 == 1 then -44 else -64.5
		local dir = if i <= 2 then Vector3.xAxis else -Vector3.xAxis
		world.boards[lb.Key] = Machines.leaderboard(b1, facing(Vector3.new(x, 9, z), dir), lb.Title)
	end
	Props.sign(b1, facing(Vector3.new(-14, 7.5, FRONT + 0.2), Z), 9, 4.2, "1  COLLECT\n2  DEPOSIT\n3  UPGRADE\n4  GO DEEPER", { Color = Color3.fromRGB(255, 226, 150), PPS = 30, Name = "HowToBoard" })
	world.spawn = Instance.new("SpawnLocation")
	world.spawn.Name = "VaultSpawn"
	world.spawn.Anchored = true
	world.spawn.Size = Vector3.new(8, 0.2, 6)
	world.spawn.CFrame = CFrame.new(0, 0.1, -64)
	world.spawn.Transparency = 1
	world.spawn.CanCollide = false
	world.spawn.Neutral = true
	world.spawn.Duration = 0
	world.spawn.Parent = folder
	world.partCount += b1.count
	return world
end

-- Which depth a world position is on (by height band).
function VaultBuilder.depthAt(position)
	return DepthConfig.depthAtY(position.Y, GameConfig.DepthSpacing)
end

-- Sanity check used by the harness: every spawn point is inside its room, on its floor,
-- and outside every keep-out box.
function VaultBuilder.validatePoint(record, point)
	local pos = point.cframe.Position
	if pos.X < -W2 + 3 or pos.X > W2 - 3 or pos.Z < HALL_END or pos.Z > BACK - 2 then
		return false, "outside the room"
	end
	if pos.Y < record.y0 - 0.01 or pos.Y > record.y0 + 12 then
		return false, "not on this floor"
	end
	if point.kind == "Floor" then
		for _, box in ipairs(record.keepOut) do
			if inBox(box, pos.X, pos.Z, 1) then
				return false, "inside a keep-out box"
			end
		end
	end
	if not LootTable.SizeRank[point.size] then
		return false, "bad size"
	end
	return true
end

return VaultBuilder
