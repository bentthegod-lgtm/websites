--[[
	Experimental Gravity Lab - a dark sci-fi hall lit by cyan and purple neon. Shimmering
	low-gravity fields and a gravity-flip column hang over the course (their effect is a
	server-side force on the dummy inside them, see CrashService), bounce fields launch
	the dummy upward, flip panels on the ceiling switch the flip column off, and rings
	float in mid-air. Local coordinates (CourseConfig.Courses.GravityLab).
]]

local Kit = require(script.Parent.Parent.Kit)

local GravityLab = {}

local rgb = Kit.rgb
local M = Kit.M
local CYL = Kit.CYL
local part, deco, key = Kit.part, Kit.deco, Kit.key

local CYAN = rgb(80, 240, 255)
local PURPLE = rgb(190, 110, 255)
local PANEL = rgb(30, 32, 44)
local PANEL_LIGHT = rgb(44, 46, 62)

-- 12 thin neon edges around a box (centre / size in world space).
local function outline(centre, size, color, parent)
	local h = size / 2
	for _, sy in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			deco({ Name = "FieldEdge", Size = Vector3.new(size.X, 0.35, 0.35), CFrame = CFrame.new(centre + Vector3.new(0, sy * h.Y, sz * h.Z)), Color = color, Material = M.Neon, Parent = parent })
		end
		for _, sx in ipairs({ -1, 1 }) do
			deco({ Name = "FieldEdge", Size = Vector3.new(0.35, 0.35, size.Z), CFrame = CFrame.new(centre + Vector3.new(sx * h.X, sy * h.Y, 0)), Color = color, Material = M.Neon, Parent = parent })
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			deco({ Name = "FieldEdge", Size = Vector3.new(0.35, size.Y, 0.35), CFrame = CFrame.new(centre + Vector3.new(sx * h.X, 0, sz * h.Z)), Color = color, Material = M.Neon, Parent = parent })
		end
	end
end

function GravityLab.build(world, entry)
	local course = entry.course
	local O = entry.origin
	local A = course.Arena
	local length, half, roof = A.Length, A.HalfWidth, A.RoofY
	local root = entry.folder
	local arena = Kit.sub("Arena", root)
	local function at(x, y, z)
		return CFrame.new(O + Vector3.new(x, y, z))
	end
	local hallBack, hallEnd = -76, length + 6
	local hallLen = hallEnd - hallBack
	local hallMid = (hallBack + hallEnd) / 2
	local wallX = half + 6

	-- Floor: dark panels with a cyan grid.
	for i = 0, 5 do
		local slab = hallLen / 6
		Kit.floor(part({ Name = "LabFloor", Size = Vector3.new(wallX * 2, 2, slab), CFrame = at(0, -1, hallBack + slab * (i + 0.5)), Color = if i % 2 == 0 then PANEL else rgb(34, 36, 50), Material = M.Metal, Parent = arena }))
	end
	for z = 40, length - 10, 40 do
		deco({ Name = "GridLine", Size = Vector3.new(half * 2, 0.04, 0.3), CFrame = at(0, 0.02, z), Color = CYAN, Material = M.Neon, Transparency = 0.5, CastShadow = false, Parent = arena })
	end
	for _, x in ipairs({ -40, 40 }) do
		deco({ Name = "LaneLine", Size = Vector3.new(0.3, 0.04, length), CFrame = at(x, 0.02, length / 2 + 6), Color = PURPLE, Material = M.Neon, Transparency = 0.4, CastShadow = false, Parent = arena })
	end

	-- Walls, back wall, end wall and the roof (with the flip panels under it).
	for _, side in ipairs({ -1, 1 }) do
		key(part({ Name = "LabWall", Size = Vector3.new(4, roof + 4, hallLen), CFrame = at(side * (wallX + 2), (roof + 4) / 2 - 2, hallMid), Color = PANEL_LIGHT, Material = M.Metal, Parent = arena }), "LabWall")
		for k, y in ipairs({ 18, 58, 98, 138 }) do
			deco({ Name = "WallStrip", Size = Vector3.new(0.4, 0.8, hallLen - 4), CFrame = at(side * wallX, y, hallMid), Color = if k % 2 == 0 then PURPLE else CYAN, Material = M.Neon, Parent = arena })
		end
		for z = hallBack + 40, hallEnd - 20, 60 do
			deco({ Name = "Rib", Size = Vector3.new(1.2, roof, 3), CFrame = at(side * (wallX - 0.6), roof / 2, z), Color = rgb(56, 58, 76), Material = M.Metal, Parent = arena })
		end
	end
	part({ Name = "BackWall", Size = Vector3.new(wallX * 2 + 8, roof + 4, 4), CFrame = at(0, roof / 2, hallBack - 2), Color = PANEL_LIGHT, Material = M.Metal, Parent = arena })
	local endWall = part({ Name = "EndWall", Size = Vector3.new(wallX * 2 + 8, roof + 4, 6), CFrame = at(0, roof / 2, length + 9), Color = PANEL_LIGHT, Material = M.Metal, Parent = arena })
	key(endWall, "EndWall")
	-- A padded catch net in front of the end wall.
	key(part({ Name = "CatchNet", Size = Vector3.new(half * 2 + 8, roof - 2, 4), CFrame = at(0, roof / 2, length + 4), Color = rgb(40, 34, 70), Material = M.Fabric, Transparency = 0.6, Parent = arena }), "CatchNet")
	key(part({ Name = "Roof", Size = Vector3.new(wallX * 2 + 8, 2, hallLen + 8), CFrame = at(0, roof + 1, hallMid), Color = rgb(24, 26, 36), Material = M.Metal, Parent = arena }), "Ceiling")
	for z = hallBack + 30, hallEnd - 20, 45 do
		local strip = deco({ Name = "RoofLight", Size = Vector3.new(half * 1.4, 0.4, 1.6), CFrame = at(0, roof - 0.3, z), Color = if (z // 45) % 2 == 0 then CYAN else PURPLE, Material = M.Neon, Parent = arena })
		if (z // 45) % 2 == 0 then
			Kit.light("SurfaceLight", strip, { Face = Enum.NormalId.Bottom, Angle = 120, Range = 60, Brightness = 0.9, Color = strip.Color, Shadows = false })
		end
	end

	Kit.facilityDeck(world, entry, { accent = CYAN, deckColor = rgb(40, 42, 56), lampColor = rgb(170, 240, 255), stripes = { CYAN, rgb(28, 28, 36) } })

	-- Gravity fields: a shimmer box + neon outline + a floor emitter for each volume.
	for _, v in ipairs(course.Gravity.Volumes) do
		local col = if v.Flip then PURPLE else CYAN
		local centre = O + v.Center
		deco({ Name = v.Id, Size = v.Size, CFrame = CFrame.new(centre), Color = col, Material = M.ForceField, Transparency = 0.35, CastShadow = false, Parent = arena })
		outline(centre, v.Size, col, arena)
		deco({ Name = "Emitter", Size = Vector3.new(0.5, 18, 18), CFrame = at(v.Center.X, 0.3, v.Center.Z) * CFrame.Angles(0, 0, math.rad(90)), Shape = CYL, Color = col, Material = M.Neon, Parent = arena })
		deco({ Name = "EmitterBase", Size = Vector3.new(0.6, 22, 22), CFrame = at(v.Center.X, 0.25, v.Center.Z) * CFrame.Angles(0, 0, math.rad(90)), Shape = CYL, Color = rgb(50, 52, 70), Material = M.Metal, Parent = arena })
		Kit.ambient("GravityHum", O + Vector3.new(v.Center.X, 4, v.Center.Z), arena)
	end
	-- Flip panels on the ceiling above the flip column.
	local flip
	for _, v in ipairs(course.Gravity.Volumes) do
		if v.Flip then
			flip = v
		end
	end
	if flip then
		for ix = -1, 1 do
			for iz = -1, 1, 2 do
				local panel = part({ Name = "FlipPanel", Size = Vector3.new(18, 1, 17), CFrame = at(flip.Center.X + ix * 19, roof - 0.6, flip.Center.Z + iz * 9.5), Color = PURPLE, Material = M.Neon, Transparency = 0.15, Parent = arena })
				key(panel, "FlipPanel")
				panel:SetAttribute("CL_Flip", true)
			end
		end
	end

	-- Bounce fields.
	for _, f in ipairs(course.Bounce.Fields) do
		local pad = part({ Name = f.Id, Size = f.Size, CFrame = at(f.Position.X, f.Position.Y + f.Size.Y / 2, f.Position.Z), Color = PURPLE, Material = M.Neon, Parent = arena })
		key(pad, f.Id)
		pad:SetAttribute("CL_Bounce", course.Bounce.Boost)
		pad.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.8, 1, 50)
		deco({ Name = "BounceFrame", Size = Vector3.new(f.Size.X + 2, 0.6, f.Size.Z + 2), CFrame = at(f.Position.X, 0.3, f.Position.Z), Color = rgb(56, 58, 76), Material = M.Metal, Parent = arena })
		for k = 1, 3 do
			deco({ Name = "BounceChevron", Size = Vector3.new(f.Size.X * 0.6, 0.06, 0.6), CFrame = at(f.Position.X, f.Size.Y + 0.03, f.Position.Z - f.Size.Z / 2 + k * f.Size.Z / 4), Color = CYAN, Material = M.Neon, CastShadow = false, Parent = arena })
		end
	end

	-- Floating rings, each over a holo-emitter with a faint beam.
	for _, def in ipairs(course.Rings) do
		Kit.ring(world, def, O, arena)
		local p = def.Position
		local beamH = p.Y - def.Radius - 1
		deco({ Name = "HoloBeam", Size = Vector3.new(0.8, beamH, 0.8), CFrame = at(p.X, beamH / 2, p.Z), Color = rgb(def.Color[1], def.Color[2], def.Color[3]), Material = M.Neon, Transparency = 0.75, CastShadow = false, Parent = arena })
		deco({ Name = "HoloEmitter", Size = Vector3.new(0.5, 5, 5), CFrame = at(p.X, 0.25, p.Z) * CFrame.Angles(0, 0, math.rad(90)), Shape = CYL, Color = rgb(56, 58, 76), Material = M.Metal, Parent = arena })
	end
	for _, def in ipairs(course.Targets) do
		Kit.target(world, def, O, arena)
	end
	for _, def in ipairs(course.LandingZones) do
		Kit.zone(world, def, O, arena)
	end
	Kit.markers(world, course, O, arena, { half = half, lineColor = CYAN, signX = wallX - 1 })

	-- Lab equipment along the walls (decoration): consoles and coolant tanks.
	for i, z in ipairs({ 60, 180, 300, 420 }) do
		local side = if i % 2 == 0 then 1 else -1
		part({ Name = "Console", Size = Vector3.new(4, 4, 10), CFrame = at(side * (wallX - 3), 2, z), Color = rgb(50, 52, 70), Material = M.Metal, Parent = arena })
		deco({ Name = "ConsoleScreen", Size = Vector3.new(0.2, 2.4, 8), CFrame = at(side * (wallX - 5.05), 3.2, z), Color = if i % 2 == 0 then PURPLE else CYAN, Material = M.Neon, Transparency = 0.2, Parent = arena })
		part({ Name = "Tank", Size = Vector3.new(14, 6, 6), CFrame = at(-side * (wallX - 4), 7, z + 20) * CFrame.Angles(0, 0, math.rad(90)), Shape = CYL, Color = rgb(70, 76, 96), Material = M.Metal, Parent = arena })
		deco({ Name = "TankBand", Size = Vector3.new(1, 6.2, 6.2), CFrame = at(-side * (wallX - 4), 10, z + 20) * CFrame.Angles(0, 0, math.rad(90)), Shape = CYL, Color = CYAN, Material = M.Neon, Parent = arena })
	end
	Kit.ambient("ElectricHum", O + Vector3.new(0, 20, -30), arena)
end

return GravityLab
